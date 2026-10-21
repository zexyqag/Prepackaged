-- Finds pack files: in every installed mod, enabled or not, in Zomboid/Lua/Prepackaged/packs and on the clipboard.
-- An entry is { source = "mod" | "file" | "clipboard", name = mod id or file name, lines, result = Parse.read },
-- plus modName and enabled for a mod.
local Files = require "Prepackaged/Files"
local Parse = require "Prepackaged/Parse"

local Discovery = {}

local function modEntry(info, lines)
    local id = info:getId()
    return {
        source = "mod", name = id, modName = info:getName(), enabled = isModActive(info),
        lines = lines, result = Parse.read(lines, id),
    }
end

local function fileEntry(name, lines)
    return { source = "file", name = name, lines = lines, result = Parse.read(lines) }
end

-- Mods in id order, as the Mods screen reads them: the first folder of an id counts.
function Discovery.fromMods()
    local list, seen = {}, {}
    for _, dir in ipairs(getModDirectoryTable()) do
        local info = getModInfo(dir)
        if info ~= nil and not seen[info:getId()] then
            seen[info:getId()] = true
            local lines = Files.readMod(info:getId(), Parse.FILE)
            if lines ~= nil then
                list[#list + 1] = modEntry(info, lines)
            end
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

function Discovery.fromFiles()
    local list = {}
    for _, name in ipairs(Files.list(Files.PACKS)) do
        if string.match(string.lower(name), "%.txt$") then
            local lines = Files.read(Files.PACKS .. "/" .. name)
            if lines ~= nil then
                list[#list + 1] = fileEntry(name, lines)
            end
        end
    end
    return list
end

function Discovery.all()
    local list = Discovery.fromMods()
    for _, entry in ipairs(Discovery.fromFiles()) do
        list[#list + 1] = entry
    end
    return list
end

-- nil when the clipboard holds no text.
function Discovery.fromClipboard()
    local text = Clipboard.getClipboard()
    if text == nil or not string.find(text, "[^ \t\r\n]") then
        return nil
    end
    local lines = Parse.lines(text)
    return { source = "clipboard", lines = lines, result = Parse.read(lines) }
end

-- Saves a pasted pack as Prepackaged/packs/<id>.txt, so Lua reloads find it again, and returns it as a file entry.
function Discovery.keep(entry)
    local name = entry.result.pack.id .. ".txt"
    Files.write(Files.PACKS .. "/" .. name, entry.lines)
    return fileEntry(name, entry.lines)
end

-- The pack in use, read again from where it was found; nil if it is gone or no longer has the same id.
function Discovery.current(state)
    local source = state.source
    if state.current == nil or source == nil then
        return nil
    end
    local entry = nil
    if source.kind == "mod" then
        local info = getModInfoByID(source.name)
        local lines = info and Files.readMod(source.name, Parse.FILE)
        entry = lines and modEntry(info, lines)
    else
        local lines = Files.read(Files.PACKS .. "/" .. source.name)
        entry = lines and fileEntry(source.name, lines)
    end
    if entry ~= nil and entry.result.pack.id == state.current then
        return entry
    end
    return nil
end

-- Whether an entry is a usable newer version of the pack in use.
function Discovery.isUpdate(entry, state)
    local pack = entry.result.pack
    return #entry.result.errors == 0 and pack.id == state.current and state.applied ~= nil and pack.version > state.applied
end

return Discovery
