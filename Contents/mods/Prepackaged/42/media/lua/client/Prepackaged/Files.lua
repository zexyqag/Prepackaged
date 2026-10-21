-- Files under Zomboid/Lua and inside mods.
local ModList = require "Prepackaged/ModList"
local State = require "Prepackaged/State"

local Files = {}

Files.PACKS = "Prepackaged/packs"

-- All lines of a reader, closed after; nil without a reader.
function Files.readLines(reader)
    if reader == nil then
        return nil
    end
    local lines = {}
    local line = reader:readLine()
    while line ~= nil do
        lines[#lines + 1] = line
        line = reader:readLine()
    end
    reader:close()
    return lines
end

-- A file under Zomboid/Lua, or nil.
function Files.read(path)
    return Files.readLines(getFileReader(path, false))
end

-- A file in a mod's version folder or else its common folder, enabled or not, or nil.
function Files.readMod(modId, name)
    return Files.readLines(getModFileReader(modId, name, false))
end

function Files.write(path, lines)
    local writer = getFileWriter(path, true, false)
    if #lines > 0 then
        writer:write(table.concat(lines, "\n") .. "\n")
    end
    writer:close()
end

-- File names in a folder under Zomboid/Lua, sorted.
function Files.list(folder)
    local names = {}
    local found = listFilesInZomboidLuaDirectory(folder)
    for i = 0, found:size() - 1 do
        names[#names + 1] = found:get(i)
    end
    table.sort(names)
    return names
end

function Files.loadState()
    return State.decode(Files.read(State.FILE) or {})
end

function Files.saveState(state)
    Files.write(State.FILE, State.encode(state))
end

-- Sets a preset in the Mods screen's list.
function Files.savePreset(name, mods)
    Files.write(ModList.PRESET_FILE, ModList.withPreset(Files.read(ModList.PRESET_FILE) or {}, name, mods))
end

return Files
