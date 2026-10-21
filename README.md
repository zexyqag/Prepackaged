# Prepackaged

A Project Zomboid Build 42 mod that turns a mod pack into a guided setup. A pack author ships one small pack file; Prepackaged finds it and enables the pack's mods in the pack's load order, after a review of every change.

> **Status: in development.** Pack discovery, mod enabling, the key bind and mod option defaults, the subscription helper, sandbox settings and server setup exist so far. The pack format may still change.

## Using a pack

1. Subscribe to Prepackaged, the pack and the pack's mods (the pack's collection usually holds them all), and enable Prepackaged in the Mods screen.
2. In the main menu, press **Prepackaged** in the bottom right corner. The window lists every pack found:
   - in any installed mod, enabled or not;
   - in `Zomboid/Lua/Prepackaged/packs/*.txt`;
   - on the clipboard, with **Paste a pack**.
3. Select a pack and press **Use this pack**. The review shows the optional mods to tick, the mods that get enabled and disabled, and how many of the pack's mods are not installed.
4. **Apply** backs up your mod list in use, in its exact load order and with its map order, then puts the pack's list in place and reloads the game's mods. If some of the pack's mods can't be enabled, Apply asks again first. **Save as my preset** saves the reviewed list as a Mods screen preset; those keep the mods, not their order.

**Subscriptions**, for the selected pack in the Prepackaged window and in the review when mods are missing, lists the pack's collections and sub-collections from its `@collections` section, nested, each as "N items, M not subscribed", then the pack's items that are in no collection. Steam's Subscribe to all on a collection's page leaves out its sub-collections, so each collection you lack items from has an **Open** button for its page: in the Steam overlay, or with the overlay off, as an address on the clipboard. Steam downloads what you subscribe to, and **Refresh** shows how far it got. The game may not see newly downloaded mods until it restarts.

Using a pack replaces your mod list. Mods you add afterwards are yours: when the pack updates, only the mods that came from the pack change. Whenever Apply would disable mods, the review lists them with a note that removing mods from an existing world can lose their items or break the save, and on an update of the pack in use a new major version warns that existing worlds may not work with it. Back up your saves first. Each mod's `require=` mods are put before it, as the game loads them. Where the pack's order goes against a mod's own `require=`, `loadModAfter=` or `loadModBefore=`, the review and the pack's details list it, and the pack's order is used.

**Restore** in the Prepackaged window lists the backups with their date, and puts one back after backing up what is in use: a mod list in its exact order, or your key binds and mod options. What you had before Prepackaged first changed it is kept for good; of the others, the newest 20 of each kind are kept, in `Zomboid/Lua/Prepackaged/backups` (key binds and mod options in its `binds` folder).

A pack's key binds and mod options are suggestions, never forced. After Apply, a review shows them in sections (key binds, then each mod's options) as your value and the pack's value, and changes only the rows you tick. A tick starts on where you have the game's default or a value Prepackaged set, for this pack or another; a value you keep by unticking is yours from then on. The review also lists keys that end up on more than one action, and entries of mods that aren't loaded, which wait for the next start. What you untick isn't asked again until the pack changes it, and **Defaults** in the Prepackaged window shows the review again, with every entry if you like. `keysB42.ini` and `ModOptions.ini` are backed up first, the same way as the mod list, and Restore puts them back.

A pack's sandbox settings belong to a world or a server, so using a pack changes none of them: the review lists them, and on an update what changed. On the New Game sandbox screen, **Apply pack** puts them into the screen's settings, which you can still change before Next, and lists the lines it couldn't use. The sandbox preset `Pack <id>` holds them too. Prepackaged writes it once per pack version while the pack's mods are loaded, and leaves it as it is once you save changes of your own over it.

**Server** in the Prepackaged window, for the selected pack: **Copy server lines** puts the `WorkshopItems`, `Mods` and `Map` lines for a dedicated server's `.ini`, and the lines to add to the end of its `_SandboxVars.lua`, on the clipboard and in `Zomboid/Lua/Prepackaged/server/<id>.txt`. **Set up a server** makes or changes a server preset in `Zomboid/Server` for Host and opens the Host screen with it, after listing every file it changes. A preset it changes is backed up first, and Restore puts it back. When the pack's mods aren't all loaded, the game reloads its mods with them, so their sandbox settings exist, then with your own list again.

## Pack file format

A pack mod is a normal Build 42 mod (`42/mod.info` and `common/`) with a `prepackaged.txt`. The game reads it from the mod's version folder (the highest one not newer than the game, such as `42` or `42.20`) when it is there, else from `common/`. The file is plain text, read line by line and never run as code.

- Lines starting with `#` are comments. CRLF, LF and a UTF-8 byte order mark are fine.
- `@section` lines start a section. Unknown sections are skipped with a warning.
- Mistakes are reported with their line number. Errors make the pack unusable; a warning mostly means its line is skipped.
- A pack file can have up to 20,000 lines and 1,000,000 characters, and a line up to 100,000 characters.

| Section | Lines |
|---|---|
| `@pack` | `key = value`. Required: `id` (1 to 48 of `A-Z a-z 0-9 _ -`), `version` (`MAJOR.MINOR.PATCH`, such as `1.4.2`: three whole numbers without leading zeros, raised on every change, and compared part by part; raise MAJOR when existing worlds may not survive the update), `WorkshopItems` and `Mods` (`;`-separated, as in the server `.ini`). Mods are in load order and include `Prepackaged`, and for a pack inside a mod, that mod. With `@keys` or `@modoptions`, put `Prepackaged` first: mods that load before it can make a player's own mod options look like defaults, and the pack's details warn about it. Optional: `name`, `collection` (top collection IDs), `Map`, `MapOrder`, `needs`, `heap`, `hostmemory`. `MapOrder` lists map folders, `;`-separated, in priority order: the first wins where maps overlap. Without it, using the pack clears your map order and the game orders the maps by the mod list. List keys may repeat. |
| `@optional` | `ModId` or `ModId = label`: mods the player can tick. |
| `@collections` | `<collectionId> = <title> \| <itemId>;<itemId>;...`, one line per collection or sub-collection. A parent lists a child collection as `c:<collectionId>`. Subscriptions shows this tree; without it, only the top collection can be opened. |
| `@keys` | `keysB42.ini` lines: `Name=key:<code>[;altCode:<code>][;shift:true][;ctrl:true][;alt:true]`; a code may be a `KEY_` name. |
| `@modoptions` | `ModOptions.ini` lines: `type\|page\|option\|value`. A `textentry` value is kept exactly as written, spaces included. |
| `@sandbox` | Sandbox preset lines: `FullName=value`. |
| `@locks` | `Page` or `Page.option`, split at the first `.`, for a Mod Options Control rules file. |

Lines from your own `keysB42.ini`, `ModOptions.ini`, a sandbox preset and the server `.ini` can be pasted as they are.

```
# Prepackaged pack file
@pack
id = ExamplePack
name = Example Pack
version = 1.0.0
collection = 3000000001
WorkshopItems = 3000000101;3000000102;3000000103
Mods = Prepackaged;ExamplePackDefaults;ExampleWeapons
Map = Muldraugh, KY

@optional
ExampleMap = Map: Example Town

@collections
3000000001 = Example Pack | c:3000000002;3000000101;3000000102
3000000002 = Maps | 3000000103
```

`@locks` is read and checked already; using it comes in a later version.

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

The version is set by Publish: `mod.info` has no `modversion=` line in the repository, and Publish writes it into the uploaded copy. When the upload fails, the release stays a pre-release, and the next run uploads it again before it publishes anything newer.

Setup: the `steam` environment holds the secrets `STEAM_USERNAME` and `STEAM_CONFIG_VDF` (steamcmd's `config/config.vdf` after a login with Steam Guard). Upload the item once from the game, which creates it and writes its `id=` into `workshop.txt`, commit that, and tag the commit you uploaded with its version (`git tag v0.1.0 <commit>`, then push the tag).
