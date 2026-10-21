local State = require "Prepackaged/State"
local Text = require "Prepackaged/Text"

local Backup = {}

Backup.FOLDER = "Prepackaged/backups"
-- Each file is a few KB, and 20 cover months of weekly pack updates. Lua can't delete files, so the backups after the
-- first take turns in this many files.
Backup.KEEP = 20

-- Backup 1 is the list from before Prepackaged first changed it, and is never overwritten.
function Backup.path(n)
    if n == 1 then
        return Backup.FOLDER .. "/first.txt"
    end
    return Backup.FOLDER .. "/" .. tostring((n - 2) % Backup.KEEP + 1) .. ".txt"
end

local function isCount(text)
    return text ~= nil and string.match(text, "^[0-9]+$") ~= nil
end

function Backup.encode(backup)
    local lines = { "backup|" .. tostring(backup.n) .. "|" .. backup.date }
    local before = backup.before
    if before.kind == "pack" then
        lines[#lines + 1] = "before|pack|" .. before.id .. "|" .. tostring(before.version)
    else
        lines[#lines + 1] = "before|restore|" .. tostring(before.n)
    end
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
    local backup, rest = { mods = {}, maps = {} }, {}
    for _, line in ipairs(lines) do
        local f = Text.split(line, "|")
        local kind = f[1]
        if kind == "backup" and #f >= 3 and isCount(f[2]) then
            backup.n, backup.date = tonumber(f[2]), Text.after(line, 2)
        elseif kind == "before" and f[2] == "pack" and #f == 4 and isCount(f[4]) then
            backup.before = { kind = "pack", id = f[3], version = tonumber(f[4]) }
        elseif kind == "before" and f[2] == "restore" and #f == 3 and isCount(f[3]) then
            backup.before = { kind = "restore", n = tonumber(f[3]) }
        elseif kind == "active" and #f >= 2 then
            backup.mods[#backup.mods + 1] = Text.after(line, 1)
        elseif kind == "map" and #f >= 2 then
            backup.maps[#backup.maps + 1] = Text.after(line, 1)
        else
            rest[#rest + 1] = line
        end
    end
    if backup.n == nil or backup.n < 1 or backup.before == nil then
        return nil
    end
    backup.pack = State.pack(State.decode(rest))
    return backup
end

function Backup.sort(list)
    table.sort(list, function(a, b) return a.n > b.n end)
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
