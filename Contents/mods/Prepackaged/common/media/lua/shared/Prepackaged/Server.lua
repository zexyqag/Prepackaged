-- A server preset set up from a pack: the job kept across the reloads, the files it touches, and the Host screen's memory.
local Build = require "Prepackaged/Build"
local Text = require "Prepackaged/Text"

local Server = {}

Server.FILE = Build.FOLDER .. "/host.txt"
Server.LINES = Build.FOLDER .. "/server"
-- The Host screen offers 512 + n * 256 MB for n from 1 to 62, and shows any other value as its first choice
-- (CoopOptionsScreen.lua:178-184, 345-350).
local MEMORY_STEP, MEMORY_BASE, MEMORY_CHOICES = 256, 512, 62

function Server.memory(mb)
    if mb == nil then
        return nil
    end
    local n = math.floor((mb - MEMORY_BASE) / MEMORY_STEP)
    return MEMORY_BASE + math.max(1, math.min(MEMORY_CHOICES, n)) * MEMORY_STEP
end

function Server.linesPath(pack)
    return Server.LINES .. "/" .. pack.id .. ".txt"
end

-- What saveFiles does to each of the preset's files (ServerSettings.java:63-80): exists[suffix] for those already there.
function Server.files(name, exists)
    local list = {}
    local function add(key, suffix)
        list[#list + 1] = { key = key, args = { name .. suffix } }
    end
    for _, suffix in ipairs({ ".ini", "_SandboxVars.lua" }) do
        add(exists[suffix] and "UI_Prepackaged_HostFileChanged" or "UI_Prepackaged_HostFileCreated", suffix)
    end
    add(exists["_spawnregions.lua"] and "UI_Prepackaged_HostFileRewritten" or "UI_Prepackaged_HostRegionsCreated", "_spawnregions.lua")
    if exists["_spawnpoints.lua"] then
        add("UI_Prepackaged_HostFileRewritten", "_spawnpoints.lua")
    end
    if exists["_zombies.ini"] then
        add("UI_Prepackaged_HostZombiesRemoved", "_zombies.ini")
    end
    return list
end

Server.SUFFIXES = { ".ini", "_SandboxVars.lua", "_spawnregions.lua", "_spawnpoints.lua", "_zombies.ini" }

-- Line kinds of the job's lists, in the order they are written.
local LISTS = { { "mod", "mods" }, { "ini", "ini" }, { "sandbox", "sandbox" }, { "set", "set" }, { "missing", "missing" },
    { "invalid", "invalid" }, { "lost", "lost" } }
local LIST = {}
for _, pair in ipairs(LISTS) do
    LIST[pair[1]] = pair[2]
end

-- step is reload (waiting for the game to load the pack's mods), apply, or done with its result.
function Server.encodeJob(job)
    local lines = { "step|" .. job.step, "server|" .. job.name, "title|" .. job.title, "existing|" .. (job.existing and "1" or "0"),
        "reload|" .. (job.reload and "1" or "0") }
    local before = job.before
    if before.kind == "pack" then
        lines[#lines + 1] = "before|pack|" .. before.id .. "|" .. before.version
    else
        lines[#lines + 1] = "before|restore|" .. tostring(before.n)
    end
    if job.memory ~= nil then
        lines[#lines + 1] = "memory|" .. tostring(job.memory)
    end
    if job.backup ~= nil then
        lines[#lines + 1] = "backup|" .. tostring(job.backup)
    end
    for _, pair in ipairs(LISTS) do
        for _, line in ipairs(job[pair[2]] or {}) do
            lines[#lines + 1] = pair[1] .. "|" .. line
        end
    end
    if job.error ~= nil then
        lines[#lines + 1] = "error|" .. job.error .. "|" .. (job.detail or "")
    end
    return lines
end

local STEPS = { reload = true, apply = true, done = true }

local function count(text)
    return text ~= nil and string.match(text, "^[0-9]+$") ~= nil
end

function Server.decodeJob(lines)
    local job = {}
    for _, pair in ipairs(LISTS) do
        job[pair[2]] = {}
    end
    for _, line in ipairs(lines) do
        local f = Text.split(line, "|")
        local kind = f[1]
        if LIST[kind] ~= nil and #f >= 2 then
            local list = job[LIST[kind]]
            list[#list + 1] = Text.after(line, 1)
        elseif kind == "step" and STEPS[f[2]] then
            job.step = f[2]
        elseif kind == "server" and #f >= 2 and Text.after(line, 1) ~= "" then
            job.name = Text.after(line, 1)
        elseif kind == "title" and #f >= 2 then
            job.title = Text.after(line, 1)
        elseif (kind == "existing" or kind == "reload") and (f[2] == "1" or f[2] == "0") then
            job[kind] = f[2] == "1"
        elseif kind == "before" and f[2] == "pack" and #f == 4 then
            job.before = { kind = "pack", id = f[3], version = f[4] }
        elseif kind == "before" and f[2] == "restore" and #f == 3 and count(f[3]) then
            job.before = { kind = "restore", n = tonumber(f[3]) }
        elseif (kind == "memory" or kind == "backup") and count(f[2]) then
            job[kind] = tonumber(f[2])
        elseif kind == "error" and #f >= 3 then
            job.error, job.detail = f[2], Text.after(line, 2)
        end
    end
    if job.step == nil or job.name == nil or job.title == nil or job.before == nil or job.existing == nil or job.reload == nil then
        return nil
    end
    return job
end

return Server
