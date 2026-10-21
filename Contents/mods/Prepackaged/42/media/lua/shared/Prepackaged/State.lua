-- What Prepackaged remembers between starts: the pack in use, where it came from, the version applied, the mods
-- that came from it and the mod lists saved before each change. Pure: State.decode and State.encode work on lines.
local State = {}

State.FILE = "Prepackaged/state.txt"
State.BACKUPS = 5

function State.new()
    return { mods = {}, backups = {} }
end

local function fields(line)
    local list, from = {}, 1
    while true do
        local i = string.find(line, "|", from, true)
        if i == nil then
            list[#list + 1] = string.sub(line, from)
            return list
        end
        list[#list + 1] = string.sub(line, from, i - 1)
        from = i + 1
    end
end

-- The text after the first `count` fields, which may itself hold |.
local function rest(line, count)
    local from = 1
    for _ = 1, count do
        from = string.find(line, "|", from, true) + 1
    end
    return string.sub(line, from)
end

local function modList(text)
    local list = {}
    for id in string.gmatch(text, "[^;]+") do
        list[#list + 1] = id
    end
    return list
end

-- Lines that don't fit are skipped.
function State.decode(lines)
    local state = State.new()
    for _, line in ipairs(lines) do
        local f = fields(line)
        local kind = f[1]
        if kind == "current" and #f == 2 and f[2] ~= "" then
            state.current = f[2]
        elseif kind == "source" and #f >= 3 and (f[2] == "mod" or f[2] == "file") and rest(line, 2) ~= "" then
            state.source = { kind = f[2], name = rest(line, 2) }
        elseif kind == "applied" and #f == 2 and string.match(f[2], "^[0-9]+$") then
            state.applied = tonumber(f[2])
        elseif kind == "mod" and #f >= 2 and rest(line, 1) ~= "" then
            state.mods[#state.mods + 1] = rest(line, 1)
        elseif kind == "backup" and #f >= 4 and string.match(f[2], "^[0-9]+$") then
            state.backups[#state.backups + 1] = { n = tonumber(f[2]), preset = f[3], mods = modList(rest(line, 3)) }
        end
    end
    return state
end

function State.encode(state)
    local lines = {}
    if state.current ~= nil then
        lines[#lines + 1] = "current|" .. state.current
    end
    if state.source ~= nil then
        lines[#lines + 1] = "source|" .. state.source.kind .. "|" .. state.source.name
    end
    if state.applied ~= nil then
        lines[#lines + 1] = "applied|" .. tostring(state.applied)
    end
    for _, id in ipairs(state.mods) do
        lines[#lines + 1] = "mod|" .. id
    end
    for _, backup in ipairs(state.backups) do
        lines[#lines + 1] = "backup|" .. tostring(backup.n) .. "|" .. backup.preset .. "|" .. table.concat(backup.mods, ";")
    end
    return lines
end

-- Keeps the newest State.BACKUPS lists, oldest first.
function State.addBackup(state, preset, mods)
    local last = state.backups[#state.backups]
    local copy = {}
    for i, id in ipairs(mods) do
        copy[i] = id
    end
    state.backups[#state.backups + 1] = { n = last and last.n + 1 or 1, preset = preset, mods = copy }
    while #state.backups > State.BACKUPS do
        table.remove(state.backups, 1)
    end
end

-- source: { kind = "mod" | "file", name = mod id or file name in Prepackaged/packs }.
function State.record(state, pack, source, mods)
    state.current = pack.id
    state.source = source
    state.applied = pack.version
    state.mods = {}
    for i, id in ipairs(mods) do
        state.mods[i] = id
    end
end

return State
