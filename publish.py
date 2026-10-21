#!/usr/bin/env python3
"""The Publish workflow's decisions: the latest version, the next one from the commits since it, whether there is
anything to publish, the change log as release notes (Markdown) and as the Steam change note, and the version in the
uploaded mod.info files.

    python3 publish.py latest RELEASES
    python3 publish.py plan --since TAG --commits FILE
    python3 publish.py notes --out FILE --commits FILE [--notes TEXT]
    python3 publish.py steam --notes FILE --version VERSION --url URL --out FILE
    python3 publish.py modversion --version VERSION FOLDER

Step outputs go to the file $GITHUB_OUTPUT names; plan sets MODE, TAG and VERSION for the later steps in $GITHUB_ENV.
"""
import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

VERSION = re.compile(r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)")
TAG = re.compile(rf"v{VERSION.pattern}")
# Conventional Commits 1.0.0: type(scope)!: description. Types and footer tokens aren't case-sensitive, BREAKING CHANGE is.
SUBJECT = re.compile(r"(?P<type>[A-Za-z][A-Za-z0-9-]*)(?:\((?P<scope>[^()\r\n]*)\))?(?P<bang>!)?: (?P<description>\S.*)")
BREAKING = re.compile(r"BREAKING[ -]CHANGE: ?(?P<text>.*)")
RELEASE_AS = re.compile(r"(?i:release-as): ?(?P<version>.*)")
FOOTER = re.compile(r"(?:[A-Za-z][A-Za-z0-9-]*|BREAKING CHANGE)(?:: | #)")
LEVELS = ["none", "patch", "minor", "major"]
TYPES = {"feat": "minor", "fix": "patch"}
# k_cchPublishedDocumentChangeDescriptionMax in the Steamworks SDK.
STEAM_NOTE_MAX = 8000
PAGE_FIELDS = ("title", "description", "visibility")
# The game takes the last line holding modversion= (ChooseGameInfo.java:239-240).
MODVERSION = re.compile(r"\s*modversion=")


class Failure(Exception):
    pass


def write(variable, values):
    with open(os.environ[variable], "a", encoding="utf-8") as out:
        for key, value in values.items():
            out.write(f"{key}={value}\n")


def output(**values):
    write("GITHUB_OUTPUT", values)


def git(*args, check=True):
    run = subprocess.run(["git", *args], capture_output=True, text=True)
    if check and run.returncode != 0:
        raise Failure(f"git {' '.join(args)} failed: {run.stderr.strip()}")
    return run


def parts(version):
    return tuple(int(part) for part in version.split("."))


def latest(releases, tags):
    """The published release with the highest vMAJOR.MINOR.PATCH tag, else the highest such tag: a tag without a
    release counts as released. Other tags don't count."""
    found = [{"tag": r["tag"], "prerelease": r["prerelease"], "release": True} for r in releases if TAG.fullmatch(r["tag"])]
    if not found:
        found = [{"tag": t, "prerelease": False, "release": False} for t in tags if TAG.fullmatch(t)]
    return max(found, key=lambda r: parts(r["tag"][1:]), default=None)


def parse_commit(subject, body):
    """A commit's part in the next version: its level, any Release-As, and what the change log says of it."""
    match = SUBJECT.fullmatch(subject.strip())
    breaking, release_as, lines = [], [], body.splitlines()
    for n, line in enumerate(lines):
        found = BREAKING.fullmatch(line.rstrip())
        if found:
            text = [found["text"]]
            for more in lines[n + 1:]:
                if not more.strip() or FOOTER.match(more):
                    break
                text.append(more.strip())
            breaking.append(" ".join(t for t in text if t))
        explicit = RELEASE_AS.fullmatch(line.rstrip())
        if explicit:
            release_as.append(explicit["version"].strip())
    kind = match["type"].lower() if match else None
    if (match and match["bang"]) or breaking:
        level = "major"
    else:
        level = TYPES.get(kind, "none")
    return {"subject": subject.strip(), "type": kind, "scope": (match["scope"] or "").strip() if match else "", "level": level,
            "description": match["description"].strip() if match else subject.strip(), "breaking": breaking, "release_as": release_as}


def commits_since(tag):
    """The commits since tag, oldest first, merges left out: the commits they merge are counted."""
    if git("rev-parse", "-q", "--verify", f"refs/tags/{tag}^{{commit}}", check=False).returncode != 0:
        raise Failure(f"the tag {tag} isn't in this checkout: it needs the full history (fetch-depth: 0)")
    if git("merge-base", "--is-ancestor", tag, "HEAD", check=False).returncode != 0:
        raise Failure(f"the latest version, {tag}, isn't in the history of this commit, so the commits since it are unknown")
    log = git("log", "--no-merges", "--reverse", "--format=%s%x1f%b%x1e", f"{tag}..HEAD").stdout
    commits = []
    for record in log.split("\x1e"):
        fields = record.strip("\n").split("\x1f")
        if len(fields) == 2:
            commits.append(parse_commit(*fields))
    return commits


def level_of(commits):
    return max((c["level"] for c in commits), key=LEVELS.index, default="none")


def bump(version, level):
    """While MAJOR is 0, a breaking change raises MINOR, as a feature does."""
    major, minor, patch = parts(version)
    if level == "major" and major > 0:
        return f"{major + 1}.0.0"
    if level in ("major", "minor"):
        return f"{major}.{minor + 1}.0"
    return f"{major}.{minor}.{patch + 1}"


def next_version(latest_version, commits):
    """The version the commits make: the highest Release-As, else the bump of their highest level; None when no commit
    is releasable."""
    explicit = []
    for commit in commits:
        for value in commit["release_as"]:
            if not VERSION.fullmatch(value):
                raise Failure(f"the commit '{commit['subject']}' has Release-As: {value}, which is not MAJOR.MINOR.PATCH")
            if parts(value) <= parts(latest_version):
                raise Failure(f"the commit '{commit['subject']}' has Release-As: {value}, which is not higher than the latest version, "
                              f"{latest_version}")
            explicit.append(value)
    if explicit:
        return max(explicit, key=parts)
    level = level_of(commits)
    return None if level == "none" else bump(latest_version, level)


def page(text):
    """The Workshop page fields of a workshop.txt."""
    fields = {key: [] for key in PAGE_FIELDS}
    for line in re.split(r"\r\n|\r|\n", text.removeprefix("\ufeff")):
        key, _, value = line.partition("=")
        if key in fields:
            fields[key].append(value)
    return {key: "\n".join(values) for key, values in fields.items()}


def changed(since, paths):
    return [line for line in git("diff", "--no-renames", "--name-only", since, "HEAD", "--", *paths).stdout.splitlines() if line]


def page_changed(since):
    before = page(git("show", f"{since}:workshop.txt").stdout)
    return before != page(Path("workshop.txt").read_text(encoding="utf-8")) or bool(changed(since, ["preview.png"]))


def plan(since):
    """release when a commit is releasable and Contents/ changed, page when only the Workshop page did, else none."""
    commits = commits_since(since)
    version = next_version(since[1:], commits)
    files = changed(since, ["Contents/"])
    print(f"Commits since {since}: {len(commits)}, {'making ' + version if version else 'none releasable'}. "
          f"Files changed under Contents/: {len(files)}.")
    if version and files:
        return "release", version, commits
    if version:
        print(f"::notice::The commits since {since} would make {version}, but nothing under Contents/ changed, so there is no release.")
    elif files:
        print(f"::notice::Files under Contents/ changed since {since}, but no commit since is a fix, a feature, a breaking change "
              "or a Release-As, so there is no release.")
    return ("page" if page_changed(since) else "none"), since[1:], commits


# ---------------------------------------------------------------------------------------------- change log, Markdown

def commit_line(commit, text):
    return (f"**{commit['scope']}:** " if commit["scope"] else "") + text


def notes(text, commits):
    sections = [text.strip()] if text.strip() else []
    breaking = [commit_line(c, t) for c in commits if c["level"] == "major" for t in (c["breaking"] or [c["description"]])]
    if breaking:
        sections.append("### Breaking changes\n\n" + "\n".join(f"- {line}" for line in breaking))
    for heading, kind in (("Features", "feat"), ("Fixes", "fix")):
        lines = [commit_line(c, c["description"]) for c in commits if c["type"] == kind and c["level"] != "major"]
        if lines:
            sections.append(f"### {heading}\n\n" + "\n".join(f"- {line}" for line in lines))
    return "\n\n".join(sections) + "\n" if sections else ""


# ---------------------------------------------------------------------------------------------- change log, Steam

INLINE = [
    (re.compile(r"\[((?:\\.|[^\]\\])*)\]\(([^)\s]+)\)"), r"[url=\2]\1[/url]"),
    (re.compile(r"\*\*(.+?)\*\*"), r"[b]\1[/b]"),
    (re.compile(r"`([^`]*)`"), r"\1"),
    (re.compile(r"\\([\\`*_\[\]<>#|~!(){}+.-])"), r"\1"),
]


def inline(text):
    for pattern, replacement in INLINE:
        text = pattern.sub(replacement, text)
    return text


def steam_lines(markdown):
    lines, listing = [], False
    for raw in markdown.replace("\r", "").split("\n"):
        line = raw.strip()
        item = re.fullmatch(r"[-*] (.*)", line)
        heading = re.fullmatch(r"#{1,6} (.*)", line)
        if listing and not item:
            lines.append("[/list]")
            listing = False
        if line == "" and lines and (lines[-1] == "" or lines[-1].startswith("[b]") and lines[-1].endswith("[/b]")):
            continue
        if item:
            if not listing:
                lines.append("[list]")
                listing = True
            lines.append("[*]" + inline(item[1]))
        elif heading:
            lines.append(f"[b]{inline(heading[1])}[/b]")
        else:
            lines.append(inline(line))
    if listing:
        lines.append("[/list]")
    return lines


def steam(markdown, version, url):
    """The change log as Steam shows a change note: BBCode, no double quote (the VDF string is quoted), within Steam's
    limit, else cut with a pointer to the release."""
    def safe(text):
        return text.replace('"', "'").replace("\\", "/")

    lines = [f"[b]Version {version}[/b]", ""] + [safe(line) for line in steam_lines(markdown)]
    while lines and lines[-1] == "":
        lines.pop()
    text = "\n".join(lines)
    if len(text.encode()) <= STEAM_NOTE_MAX:
        return text
    pointer = safe(f"\n\n... The full change log is on GitHub: {url}")
    kept, size, listing = [], 0, False
    for line in lines:
        inside = (listing or line == "[list]") and line != "[/list]"
        if size + len(line.encode()) + 1 + (len("[/list]\n") if inside else 0) + len(pointer.encode()) > STEAM_NOTE_MAX:
            break
        kept.append(line)
        size += len(line.encode()) + 1
        listing = inside
    if listing and kept[-1] == "[list]":
        kept.pop()
    elif listing:
        kept.append("[/list]")
    return "\n".join(kept).rstrip("\n") + pointer


# ---------------------------------------------------------------------------------------------- the uploaded mod.info

def with_modversion(text, version):
    """mod.info text with one modversion= line: in place of the first one there, else at the end in the file's line
    ending. Every other line stays as it is."""
    line, out, placed = f"modversion={version}", [], False
    for raw in re.findall(r"[^\n]*\n|[^\n]+$", text):
        if not MODVERSION.match(raw):
            out.append(raw)
        elif not placed:
            out.append(line + raw[len(raw.rstrip("\r\n")):])
            placed = True
    if not placed:
        newline = "\r\n" if "\r\n" in text else "\n"
        if out and not out[-1].endswith("\n"):
            out[-1] += newline
        out.append(line + newline)
    return "".join(out)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("latest")
    p.add_argument("releases", type=Path, help="one JSON object per line: tag, prerelease")
    p = sub.add_parser("plan")
    p.add_argument("--since", required=True)
    p.add_argument("--commits", type=Path, required=True)
    p = sub.add_parser("notes")
    p.add_argument("--notes", default="")
    p.add_argument("--commits", type=Path, required=True)
    p.add_argument("--out", type=Path, required=True)
    p = sub.add_parser("steam")
    p.add_argument("--notes", type=Path, required=True)
    p.add_argument("--version", required=True)
    p.add_argument("--url", required=True)
    p.add_argument("--out", type=Path, required=True)
    p = sub.add_parser("modversion")
    p.add_argument("--version", required=True)
    p.add_argument("folder", type=Path)
    args = parser.parse_args()

    if args.command == "latest":
        releases = [json.loads(line) for line in args.releases.read_text(encoding="utf-8").splitlines() if line.strip()]
        found = latest(releases, git("tag", "--list").stdout.splitlines())
        if found is None:
            raise Failure("there is no vMAJOR.MINOR.PATCH release or tag yet, so the version to start from is unknown: tag the commit "
                          "that is on the Workshop with its version (git tag vX.Y.Z <commit>, then git push origin vX.Y.Z) and run Publish again")
        if not found["release"]:
            print(f"No release has a vMAJOR.MINOR.PATCH tag yet, so the latest version is the tag {found['tag']}.")
        elif found["prerelease"]:
            print(f"The latest release is {found['tag']}, a pre-release: its Workshop upload hasn't finished.")
        else:
            print(f"The latest release is {found['tag']}.")
        output(tag=found["tag"], version=found["tag"][1:], pending="true" if found["prerelease"] else "false")
    elif args.command == "plan":
        mode, version, commits = plan(args.since)
        args.commits.write_text(json.dumps(commits, indent=1), encoding="utf-8")
        if mode == "release":
            print(f"Releasing {version}.")
        elif mode == "page":
            print(f"::notice::Only the Workshop page changed since {args.since}: the page is updated, and the mod stays at {version}.")
        else:
            print(f"::notice::Nothing to publish since {args.since}.")
        write("GITHUB_ENV", {"MODE": mode, "TAG": f"v{version}", "VERSION": version})
    elif args.command == "notes":
        text = notes(args.notes, json.loads(args.commits.read_text(encoding="utf-8")))
        args.out.write_text(text, encoding="utf-8")
        print(text)
    elif args.command == "steam":
        args.out.write_text(steam(args.notes.read_text(encoding="utf-8"), args.version, args.url), encoding="utf-8")
    elif args.command == "modversion":
        if not VERSION.fullmatch(args.version):
            raise Failure(f"--version {args.version} is not MAJOR.MINOR.PATCH")
        infos = sorted(args.folder.rglob("mod.info"))
        if not infos:
            raise Failure(f"there is no mod.info under {args.folder}")
        for info in infos:
            text = info.read_bytes().decode("utf-8", "surrogateescape")
            info.write_bytes(with_modversion(text, args.version).encode("utf-8", "surrogateescape"))
            print(f"{info.relative_to(args.folder)}: modversion={args.version}")


if __name__ == "__main__":
    try:
        main()
    except Failure as failure:
        print(f"::error::{failure}")
        sys.exit(1)
