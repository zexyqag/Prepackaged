# Contributing to Prepackaged

Bug reports and ideas are welcome as GitHub issues. Using a pack and the pack file format are in the [README](README.md).

## Repository layout

- `Contents/mods/Prepackaged/`: the mod. `common/media/lua/` has the Lua both builds run (`shared/` and `client/`, the windows in `client/Prepackaged/UI/`) and the English translations; `42/` and `41/` have each build's `mod.info` and `Prepackaged/Build` module, which holds what differs between them. Build 41 reads only the mod's root, so the upload puts Build 41's mod there (`publish.py stage`): `41/mod.info`, the poster of `42/`, `common/media` with `41/media` over it, and the translations as `UI_EN.txt`.
- `workshop.txt`: the Workshop page: the item's `id=`, title, description, tags and visibility.
- `preview.png`: the Workshop preview image.
- `publish.py` and `.github/workflows/publish.yml`: the release workflow.
- `site/`: the map pack page (`index.html`, `page.js`, and `packs.js` with its rules), which `.github/workflows/pages.yml` publishes on GitHub Pages with the grid script of the Zomboid Map Index. It isn't part of the mod.
- `.gitignore`: a whitelist. A new top-level file or folder is ignored until it has its own `!/path` rule.

## Commit messages

Releases are made from the commit messages, so they follow [Conventional Commits](https://www.conventionalcommits.org/). The type decides what the next release is:

| Type | For | Version |
|---|---|---|
| `fix:` | a bug fix | patch |
| `feat:` | a new feature or setting | minor |
| `feat!:` (any type with `!`), or a `BREAKING CHANGE:` footer | a change that breaks existing settings or saves | major (minor while the version is 0.x) |
| `docs:`, `chore:`, `ci:`, `refactor:` and others | everything else | none |

A scope is fine (`fix(fog): ...`).

## Changes

- The Lua runs in the game's Kahlua, a Lua 5.1 implementation, so later Lua features such as `goto`, `//` and bitwise operators aren't available.
- New player-facing texts go in the English translations under `common/`, on one line each, as Build 41 reads them.
- What only one build has goes in the `Build` modules of `41/` and `42/`, not in `common/`.
