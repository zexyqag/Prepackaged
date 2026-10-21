# Prepackaged

A Project Zomboid Build 42 mod that turns a mod pack into a guided setup. A pack author ships one small pack file; Prepackaged finds it and enables the pack's mods in the pack's load order, after a review of every change.

> **Status: in development.** Only pack discovery and mod enabling exist so far. The pack format may still change.

## Using a pack

1. Subscribe to Prepackaged, the pack and the pack's mods (the pack's collection usually holds them all), and enable Prepackaged in the Mods screen.
2. In the main menu, press **Prepackaged** in the bottom right corner. The window lists every pack found:
   - in any installed mod, enabled or not;
   - in `Zomboid/Lua/Prepackaged/packs/*.txt`;
   - on the clipboard, with **Paste a pack**.
3. Select a pack and press **Use this pack**. The review shows the optional mods to tick, the mods that get enabled and disabled, and how many of the pack's mods are not installed.
4. **Apply** backs up your mod list in use, in its exact load order and with its map order, then puts the pack's list in place and reloads the game's mods. If some of the pack's mods can't be enabled, Apply asks again first. **Save as my preset** saves the reviewed list as a Mods screen preset; those keep the mods, not their order.

Using a pack replaces your mod list. Mods you add afterwards are yours: when the pack updates, only the mods that came from the pack change. Each mod's `require=` mods are put before it, as the game loads them.

**Restore** in the Prepackaged window lists the backups with their date and number of mods, and puts one back in its exact order, after backing up the list in use. Your list from before Prepackaged is kept for good; of the others, the newest 20 are kept, in `Zomboid/Lua/Prepackaged/backups`.

## Pack file format

A pack mod is a normal Build 42 mod (`42/mod.info` and `common/`) with a `prepackaged.txt`. The game reads it from the mod's version folder (the highest one not newer than the game, such as `42` or `42.20`) when it is there, else from `common/`. The file is plain text, read line by line and never run as code.

- Lines starting with `#` are comments. CRLF, LF and a UTF-8 byte order mark are fine.
- `@section` lines start a section. Unknown sections are skipped with a warning.
- Mistakes are reported with their line number. Errors make the pack unusable; a warning mostly means its line is skipped.
- A pack file can have up to 20,000 lines and 1,000,000 characters, and a line up to 100,000 characters.

| Section | Lines |
|---|---|
| `@pack` | `key = value`. Required: `id` (1 to 48 of `A-Z a-z 0-9 _ -`), `version` (a whole number, raised on every change), `WorkshopItems` and `Mods` (`;`-separated, as in the server `.ini`). Mods are in load order and include `Prepackaged`, and for a pack inside a mod, that mod. Optional: `name`, `collection` (top collection IDs), `Map`, `MapOrder`, `needs`, `heap`, `hostmemory`. `MapOrder` lists map folders, `;`-separated, in priority order: the first wins where maps overlap. Without it, using the pack clears your map order and the game orders the maps by the mod list. List keys may repeat. |
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

`@keys`, `@modoptions`, `@sandbox` and `@locks` are read and checked already; applying them comes in later versions.
