# Contributing to Prepackaged

Bug reports and ideas are welcome as GitHub issues. Using a pack and the pack file format are in the [README](README.md).

## Repository layout

- `Contents/mods/Prepackaged/`: the mod, as the Workshop item holds it. `42/` has `mod.info`, `poster.png` and the Lua in `media/lua/` (`shared/` and `client/`, the windows in `client/Prepackaged/UI/`); `common/` has the English translations.
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
- New player-facing texts go in the English translations under `common/`.
