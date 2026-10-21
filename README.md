# Prepackaged

A Project Zomboid Build 42 mod that turns a mod pack into a guided setup. A pack author ships one small pack file; Prepackaged finds it and enables the pack's mods in the pack's load order, after a review of every change.

> **Status: in development.** Only pack discovery and mod enabling exist so far. The pack format may still change.

## Using a pack

1. Subscribe to Prepackaged and the pack, and enable Prepackaged.
2. In the main menu, press **Prepackaged** in the bottom right corner. The window lists every pack found:
   - in any installed mod, enabled or not;
   - in `Zomboid/Lua/Prepackaged/packs/*.txt`;
   - on the clipboard, with **Paste a pack**.
3. Select a pack and press **Use this pack**. The review shows the optional mods to tick, the mods that get enabled and disabled, and the ones that are not installed.
4. **Apply** saves your current mod list as the Mods screen preset "Before *pack id*", puts the pack's list in place and reloads the game's mods. **Save as my preset** saves the reviewed list as a preset of your own.

Using a pack replaces your mod list. Mods you add afterwards are yours: when the pack updates, only the mods that came from the pack change.

## Pack file format

A pack mod is a normal Build 42 mod (`42/mod.info` and `common/`) with a `prepackaged.txt` in `common/` or `42/`. The file is plain text, read line by line and never run as code.

- Lines starting with `#` are comments. CRLF, LF and a UTF-8 byte order mark are fine.
- `@section` lines start a section. Unknown sections are skipped with a warning.
- Mistakes are reported with their line number. Errors make the pack unusable; a warning mostly means its line is skipped.

| Section | Lines |
|---|---|
| `@pack` | `key = value`. Required: `id` (1 to 48 of `A-Z a-z 0-9 _ -`), `version` (a whole number, raised on every change), `WorkshopItems` and `Mods` (`;`-separated, as in the server `.ini`). Mods are in load order and include `Prepackaged`, and for a pack inside a mod, that mod. Optional: `name`, `collection` (top collection IDs), `Map`, `needs`, `heap`, `hostmemory`. List keys may repeat. |
| `@optional` | `ModId` or `ModId = label`: mods the player can tick. |
| `@collections` | `<collectionId> = <title> \| <itemId>;<itemId>;...`, one line per collection or sub-collection. A parent lists a child collection as `c:<collectionId>`. |
| `@keys` | `keysB42.ini` lines: `Name=key:<code>[;altCode:<code>][;shift:true][;ctrl:true][;alt:true]`; a code may be a `KEY_` name. |
| `@modoptions` | `ModOptions.ini` lines: `type\|page\|option\|value`. |
| `@sandbox` | Sandbox preset lines: `FullName=value`. |
| `@locks` | `Page` or `Page.option`, for a Mod Options Control rules file. |

Lines from your own `keysB42.ini`, `ModOptions.ini`, a sandbox preset and the server `.ini` can be pasted as they are.

```
# Prepackaged pack file
@pack
id = MartyPack
name = Marty's Apocalypse
version = 3
collection = 3830000001
WorkshopItems = 3830000099;3830000098;3820511464
Mods = Prepackaged;MartyPackDefaults;Crepuscular
Map = Muldraugh, KY

@optional
BetterSorting = Better Sorting

@collections
3830000001 = Marty's Apocalypse | c:3830000002;3830000099;3830000098
3830000002 = Maps | 3820511464
```

`@keys`, `@modoptions`, `@sandbox` and `@locks` are read and checked already; applying them comes in later versions.
