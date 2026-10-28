local Files = require "Prepackaged/Files"
local Parse = require "Prepackaged/Parse"
local Text = require "Prepackaged/Text"
local Version = require "Prepackaged/Version"

local Discovery = {}

-- One bad file is shown as a broken pack: nothing it does may break the window or the main menu.
local function load(entry, read, sourceMod)
    local ok, lines = pcall(read)
    if ok and lines == nil then
        return nil
    end
    local result = lines
    if ok then
        ok, result = pcall(Parse.read, lines, sourceMod)
    end
    if not ok then
        print("[Prepackaged] WARNING: a pack file could not be read: " .. tostring(result))
        lines, result = {}, Parse.failed(result)
    end
    entry.lines, entry.result = lines, result
    return entry
end

local function modEntry(info)
    local id = info:getId()
    local entry = { source = "mod", name = id, modName = info:getName(), enabled = isModActive(info) }
    return load(entry, function() return Files.readModPack(id) end, id)
end

local function fileEntry(name)
    return load({ source = "file", name = name }, function() return Files.readPack(Files.PACKS .. "/" .. name) end)
end

-- The first folder of an id counts, as for getModFileReader (LuaManager.java:4333-4337).
function Discovery.fromMods()
    local list, seen = {}, {}
    for _, dir in ipairs(getModDirectoryTable()) do
        local info = getModInfo(dir)
        if info ~= nil and not seen[info:getId()] then
            seen[info:getId()] = true
            list[#list + 1] = modEntry(info)
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

function Discovery.fromFiles()
    local list = {}
    for _, name in ipairs(Files.list(Files.PACKS)) do
        if string.match(string.lower(name), "%.txt$") then
            list[#list + 1] = fileEntry(name)
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

function Discovery.fromClipboard()
    local text = Clipboard.getClipboard()
    if not string.find(text, "[^ \t\r\n]") then
        return nil
    end
    return load({ source = "clipboard" }, function() return Parse.lines(text) end)
end

-- The same text only: another text with the same id is listed too, and Apply asks before replacing its file.
function Discovery.sameAs(entries, entry)
    for _, listed in ipairs(entries) do
        if Text.same(listed.lines, entry.lines) then
            return listed
        end
    end
    return nil
end

local function packFile(entry)
    return entry.result.pack.id .. ".txt"
end

function Discovery.replaced(entry)
    local existing = fileEntry(packFile(entry))
    if existing ~= nil and not Text.same(existing.lines, entry.lines) then
        return existing
    end
    return nil
end

-- Saved so that Lua reloads find it again.
function Discovery.keep(entry)
    local name = packFile(entry)
    if not Files.write(Files.PACKS .. "/" .. name, entry.lines) then
        return nil
    end
    return { source = "file", name = name, lines = entry.lines, result = entry.result }
end

function Discovery.current(state)
    local source = state.source
    if state.current == nil or source == nil then
        return nil
    end
    local entry = nil
    if source.kind == "mod" then
        local info = getModInfoByID(source.name)
        entry = info and modEntry(info)
    else
        entry = fileEntry(source.name)
    end
    if entry ~= nil and entry.result.pack.id == state.current then
        return entry
    end
    return nil
end

function Discovery.isUpdate(entry, state)
    local pack = entry.result.pack
    return #entry.result.errors == 0 and pack.id == state.current and state.applied ~= nil and Version.compare(pack.version, state.applied) > 0
end

return Discovery
