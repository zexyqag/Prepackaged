local State = require "Prepackaged/State"
local Text = require "Prepackaged/Text"

local Backup = {}

Backup.FOLDER = "Prepackaged/backups"
-- keysB42.ini and ModOptions.ini, as copies taken before Prepackaged writes them.
Backup.FILES = Backup.FOLDER .. "/binds"
-- Server presets as the game reads them, before Prepackaged sets one up or restores one.
Backup.SERVERS = Backup.FOLDER .. "/servers"
-- Each file is a few KB, and 20 cover months of weekly pack updates. Lua can't delete files, so the backups after the
-- first take turns in this many files.
Backup.KEEP = 20
-- A restore reloads Lua with this reason.
Backup.RESET_REASON = "PrepackagedRestore"
Backup.DATE = "%Y-%m-%d %H:%M"

-- Backup 1 of a folder is the state from before Prepackaged first changed it, and is never overwritten.
function Backup.path(folder, n)
    if n == 1 then
        return folder .. "/first.txt"
    end
    return folder .. "/" .. tostring((n - 2) % Backup.KEEP + 1) .. ".txt"
end

local function isCount(text)
    return text ~= nil and string.match(text, "^[0-9]+$") ~= nil
end

local function head(backup)
    local lines = { "backup|" .. tostring(backup.n) .. "|" .. backup.date }
    local before = backup.before
    if before.kind == "pack" or before.kind == "defaults" or before.kind == "host" then
        lines[#lines + 1] = "before|" .. before.kind .. "|" .. before.id .. "|" .. before.version
    else
        lines[#lines + 1] = "before|restore|" .. tostring(before.n)
    end
    return lines
end

-- The backup and before lines, or false when the line is neither. The version is only shown, so any written one is
-- read: a backup that no longer reads would give its number, even first.txt's, to the next backup.
local function readHead(backup, line, f, packKind)
    local kind = f[1]
    if kind == "backup" and #f >= 3 and isCount(f[2]) then
        backup.n, backup.date = tonumber(f[2]), Text.after(line, 2)
    elseif kind == "before" and f[2] == packKind and #f == 4 and f[4] ~= "" then
        backup.before = { kind = packKind, id = f[3], version = f[4] }
    elseif kind == "before" and f[2] == "restore" and #f == 3 and isCount(f[3]) then
        backup.before = { kind = "restore", n = tonumber(f[3]) }
    else
        return false
    end
    return true
end

local function complete(backup)
    return backup.n ~= nil and backup.n >= 1 and backup.before ~= nil
end

function Backup.encode(backup)
    local lines = head(backup)
    for _, id in ipairs(backup.mods) do
        lines[#lines + 1] = "active|" .. id
    end
    for _, map in ipairs(backup.maps) do
        lines[#lines + 1] = "map|" .. map
    end
    for _, line in ipairs(State.encode(backup.pack)) do
        lines[#lines + 1] = line
    end
    return lines
end

function Backup.decode(lines)
    local backup, rest = { kind = "mods", mods = {}, maps = {} }, {}
    for _, line in ipairs(lines) do
        local f = Text.split(line, "|")
        if not readHead(backup, line, f, "pack") then
            if f[1] == "active" and #f >= 2 then
                backup.mods[#backup.mods + 1] = Text.after(line, 1)
            elseif f[1] == "map" and #f >= 2 then
                backup.maps[#backup.maps + 1] = Text.after(line, 1)
            else
                rest[#rest + 1] = line
            end
        end
    end
    if not complete(backup) then
        return nil
    end
    backup.pack = State.pack(State.decode(rest))
    return backup
end

-- The lines of both files as they were read.
function Backup.encodeFiles(backup)
    local lines = head(backup)
    for _, line in ipairs(backup.keys) do
        lines[#lines + 1] = "keys|" .. line
    end
    for _, line in ipairs(backup.options) do
        lines[#lines + 1] = "options|" .. line
    end
    return lines
end

function Backup.decodeFiles(lines)
    local backup = { kind = "files", keys = {}, options = {} }
    for _, line in ipairs(lines) do
        local f = Text.split(line, "|")
        if not readHead(backup, line, f, "defaults") then
            if f[1] == "keys" and #f >= 2 then
                backup.keys[#backup.keys + 1] = Text.after(line, 1)
            elseif f[1] == "options" and #f >= 2 then
                backup.options[#backup.options + 1] = Text.after(line, 1)
            end
        end
    end
    if not complete(backup) then
        return nil
    end
    return backup
end

-- Every server option and every sandbox option the game has loaded, as Name=value.
function Backup.encodeServer(backup)
    local lines = head(backup)
    lines[#lines + 1] = "server|" .. backup.name
    for _, line in ipairs(backup.ini) do
        lines[#lines + 1] = "ini|" .. line
    end
    for _, line in ipairs(backup.sandbox) do
        lines[#lines + 1] = "sandbox|" .. line
    end
    return lines
end

function Backup.decodeServer(lines)
    local backup = { kind = "server", ini = {}, sandbox = {} }
    for _, line in ipairs(lines) do
        local f = Text.split(line, "|")
        if not readHead(backup, line, f, "host") then
            if f[1] == "server" and #f >= 2 and Text.after(line, 1) ~= "" then
                backup.name = Text.after(line, 1)
            elseif f[1] == "ini" and #f >= 2 then
                backup.ini[#backup.ini + 1] = Text.after(line, 1)
            elseif f[1] == "sandbox" and #f >= 2 then
                backup.sandbox[#backup.sandbox + 1] = Text.after(line, 1)
            end
        end
    end
    if not complete(backup) or backup.name == nil then
        return nil
    end
    return backup
end

function Backup.sort(list)
    table.sort(list, function(a, b) return a.n > b.n end)
    return list
end

-- Both kinds newest first: each in its own order, the two by date, and on the same minute the key binds first.
function Backup.merge(mods, files)
    local list, i, j = {}, 1, 1
    while mods[i] ~= nil or files[j] ~= nil do
        if mods[i] == nil or (files[j] ~= nil and files[j].date >= mods[i].date) then
            list[#list + 1] = files[j]
            j = j + 1
        else
            list[#list + 1] = mods[i]
            i = i + 1
        end
    end
    return list
end

function Backup.next(list)
    local n = 0
    for _, backup in ipairs(list) do
        n = math.max(n, backup.n)
    end
    return n + 1
end

return Backup
