# Contributing to Prepackaged

This is for working on the repository. Using a pack and the pack file format are in the [README](README.md).

## Repository layout

- `Contents/mods/Prepackaged/`: the mod, as the Workshop item holds it. `42/` has `mod.info`, `poster.png` and the Lua in `media/lua/` (`shared/` and `client/`, the windows in `client/Prepackaged/UI/`); `common/` has the English translations.
- `workshop.txt`: the Workshop page: the item's `id=`, title, description, tags and visibility.
- `preview.png`: the Workshop preview image.
- `publish.py` and `.github/workflows/publish.yml`: the Publish workflow, below.
- `.gitignore`: a whitelist. A new top-level file or folder is ignored until it has its own `!/path` rule.

## Not in the repository

The test harness lives outside the repository.

## Publishing

Run the **Publish** workflow (Actions, Publish, Run workflow), optionally with notes for the top of the change log. It starts from the latest version: the highest `vX.Y.Z` release, or while there is none, the highest `vX.Y.Z` tag. Then:

- **A release** when a commit since then is releasable (below) and something under `Contents/` changed. It is tagged `vX.Y.Z`, its notes are the change log (your notes, then the breaking changes, features and fixes from the commit messages), and `Contents/` and `preview.png` are uploaded to the Workshop item in `workshop.txt`'s `id=`, with the change log as the Steam change note.
- **Only the Workshop page** is updated when the title, description or visibility in `workshop.txt`, or `preview.png`, changed.
- **Nothing** otherwise.

| Commit message | From 0.3.0 | From 1.4.2 |
|---|---|---|
| `fix: ...` | 0.3.1 | 1.4.3 |
| `feat: ...` | 0.4.0 | 1.5.0 |
| `feat!: ...` (any type with `!`), or a `BREAKING CHANGE:` footer | 0.4.0 | 2.0.0 |
| any other type (`docs:`, `chore:`, ...) or message | no release | no release |

A scope is fine (`fix(ui): ...`), and the highest of the commits counts. While MAJOR is 0, a breaking change raises MINOR, as a feature does. A `Release-As: X.Y.Z` footer sets the version instead; it must be higher than the latest. That is how 1.0.0 is made.

**The first release:** while there is no `vX.Y.Z` release or tag, the version comes from a `Release-As: X.Y.Z` footer in a commit message, such as `Release-As: 0.1.0`; without one, Publish stops and says to add one.

The version is set by Publish: `mod.info` has no `modversion=` line in the repository, and Publish writes it into the uploaded copy. When the upload fails, the release stays a pre-release, and the next run uploads it again before it publishes anything newer.

Setup: the `steam` environment holds the secrets `STEAM_USERNAME` and `STEAM_CONFIG_VDF` (steamcmd's `config/config.vdf` after a login with Steam Guard). Upload the item once from the game, which creates it and writes its `id=` into `workshop.txt`, commit that, and tag the commit you uploaded with its version (`git tag v0.1.0 <commit>`, then push the tag).
