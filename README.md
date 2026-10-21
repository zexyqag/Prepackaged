# Prepackaged

A Project Zomboid Build 42 mod that turns a mod pack into a guided setup. A pack author ships one small pack file; Prepackaged finds it and enables the pack's mods in the pack's load order, after a review of every change.

> **Status: in development.** Pack discovery, mod enabling and the key bind and mod option defaults exist so far. The pack format may still change.

## Using a pack

1. Subscribe to Prepackaged, the pack and the pack's mods (the pack's collection usually holds them all), and enable Prepackaged in the Mods screen.
2. In the main menu, press **Prepackaged** in the bottom right corner. The window lists every pack found:
   - in any installed mod, enabled or not;
   - in `Zomboid/Lua/Prepackaged/packs/*.txt`;
   - on the clipboard, with **Paste a pack**.
3. Select a pack and press **Use this pack**. The review shows the optional mods to tick, the mods that get enabled and disabled, and how many of the pack's mods are not installed.
4. **Apply** backs up your mod list in use, in its exact load order and with its map order, then puts the pack's list in place and reloads the game's mods. If some of the pack's mods can't be enabled, Apply asks again first. **Save as my preset** saves the reviewed list as a Mods screen preset; those keep the mods, not their order.

Using a pack replaces your mod list. Mods you add afterwards are yours: when the pack updates, only the mods that came from the pack change. Each mod's `require=` mods are put before it, as the game loads them. Where the pack's order goes against a mod's own `require=`, `loadModAfter=` or `loadModBefore=`, the review and the pack's details list it, and the pack's order is used.

**Restore** in the Prepackaged window lists the backups with their date, and puts one back after backing up what is in use: a mod list in its exact order, or your key binds and mod options. What you had before Prepackaged first changed it is kept for good; of the others, the newest 20 of each kind are kept, in `Zomboid/Lua/Prepackaged/backups` (key binds and mod options in its `binds` folder).

A pack's key binds and mod options are suggestions, never forced. After Apply, a review shows them in sections (key binds, then each mod's options) as your value and the pack's value, and changes only the rows you tick. A tick starts on where you have the game's default or what Prepackaged set before. The review also lists keys that end up on more than one action, and entries of mods that aren't loaded, which wait for the next start. What you untick isn't asked again until the pack changes it, and **Defaults** in the Prepackaged window shows the review again, with every entry if you like. `keysB42.ini` and `ModOptions.ini` are backed up first, the same way as the mod list, and Restore puts them back.

## Pack file format

A pack mod is a normal Build 42 mod (`42/mod.info` and `common/`) with a `prepackaged.txt`. The game reads it from the mod's version folder (the highest one not newer than the game, such as `42` or `42.20`) when it is there, else from `common/`. The file is plain text, read line by line and never run as code.

- Lines starting with `#` are comments. CRLF, LF and a UTF-8 byte order mark are fine.
- `@section` lines start a section. Unknown sections are skipped with a warning.
- Mistakes are reported with their line number. Errors make the pack unusable; a warning mostly means its line is skipped.
- A pack file can have up to 20,000 lines and 1,000,000 characters, and a line up to 100,000 characters.

| Section | Lines |
|---|---|
| `@pack` | `key = value`. Required: `id` (1 to 48 of `A-Z a-z 0-9 _ -`), `version` (a whole number, raised on every change), `WorkshopItems` and `Mods` (`;`-separated, as in the server `.ini`). Mods are in load order and include `Prepackaged`, and for a pack inside a mod, that mod. With `@keys` or `@modoptions`, put `Prepackaged` first: mods that load before it can make a player's own mod options look like defaults, and the pack's details warn about it. Optional: `name`, `collection` (top collection IDs), `Map`, `MapOrder`, `needs`, `heap`, `hostmemory`. `MapOrder` lists map folders, `;`-separated, in priority order: the first wins where maps overlap. Without it, using the pack clears your map order and the game orders the maps by the mod list. List keys may repeat. |
| `@optional` | `ModId` or `ModId = label`: mods the player can tick. |
| `@collections` | `<collectionId> = <title> \| <itemId>;<itemId>;...`, one line per collection or sub-collection. A parent lists a child collection as `c:<collectionId>`. |
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
version = 3
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

`@sandbox` and `@locks` are read and checked already; applying them comes in later versions.
