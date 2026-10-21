local Backup = require "Prepackaged/Backup"
local ModList = require "Prepackaged/ModList"
local Parse = require "Prepackaged/Parse"
local State = require "Prepackaged/State"
local Text = require "Prepackaged/Text"

local Files = {}

Files.PACKS = "Prepackaged/packs"
Files.PRESET_COPY = Backup.FOLDER .. "/" .. ModList.PRESET_FILE

local function readAll(reader)
    local lines = {}
    local line = reader:readLine()
    while line ~= nil do
        lines[#lines + 1] = line
        line = reader:readLine()
    end
    reader:close()
    return lines
end

-- A pack file is read only up to Parse's caps, so a huge one costs no more than a big one.
local function readPack(reader)
    if reader == nil then
        return nil
    end
    local lines = Parse.collect(function() return reader:readLine() end)
    reader:close()
    return lines
end

function Files.read(path)
    local reader = getFileReader(path, false)
    return reader and readAll(reader)
end

function Files.readPack(path)
    return readPack(getFileReader(path, false))
end

-- The mod's version folder first, then its common folder, enabled or not.
function Files.readModPack(modId)
    return readPack(getModFileReader(modId, Parse.FILE, false))
end

local function writeChecked(path, lines, ending)
    local writer = getFileWriter(path, true, false)
    if writer == nil then
        return false
    end
    if #lines > 0 then
        writer:write(table.concat(lines, ending) .. ending)
    end
    writer:close()
    local back = Files.read(path)
    return back ~= nil and Text.same(back, lines)
end

-- True only when the file reads back as exactly these lines: getFileWriter truncates first and its PrintWriter
-- swallows IO errors (LuaManager.java:5853-5858, 10655-10670). The game ends the lines of its own files with CRLF.
function Files.write(path, lines, ending)
    local ok, written = pcall(writeChecked, path, lines, ending or "\n")
    return ok and written
end

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
    return Files.write(State.FILE, State.encode(state))
end

local function backups(folder, decode)
    local list = {}
    for _, name in ipairs(Files.list(folder)) do
        if string.match(string.lower(name), "%.txt$") then
            local ok, backup = pcall(function() return decode(Files.read(folder .. "/" .. name) or {}) end)
            if ok and backup ~= nil then
                list[#list + 1] = backup
            end
        end
    end
    return Backup.sort(list)
end

function Files.backups()
    return backups(Backup.FOLDER, Backup.decode)
end

function Files.fileBackups()
    return backups(Backup.FILES, Backup.decodeFiles)
end

function Files.saveBackup(backup)
    return Files.write(Backup.path(Backup.FOLDER, backup.n), Backup.encode(backup))
end

function Files.saveFileBackup(backup)
    return Files.write(Backup.path(Backup.FILES, backup.n), Backup.encodeFiles(backup))
end

-- The old file is copied first: a failed rewrite would lose every preset in it.
function Files.savePreset(name, mods)
    local lines = Files.read(ModList.PRESET_FILE) or {}
    return Files.write(Files.PRESET_COPY, lines) and Files.write(ModList.PRESET_FILE, ModList.withPreset(lines, name, mods))
end

return Files
