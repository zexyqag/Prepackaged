local Build = require "Prepackaged/Build"
local Sandbox = require "Prepackaged/Sandbox"
local Text = require "Prepackaged/Text"
local Version = require "Prepackaged/Version"

local State = {}

State.FILE = Build.FOLDER .. "/state.txt"
State.FORMAT = 1
local DECISIONS = { applied = true, declined = true, same = true }

-- unknown keeps lines a newer Prepackaged wrote, so this one writes them back. sandbox holds the pack's @sandbox lines
-- as Name=value, for what an update changes; sandboxed says they were recorded, which a state from before them wasn't.
function State.new()
    return { mods = {}, sandbox = {}, sandboxed = false, ledger = {}, at = {}, entries = {}, unknown = {} }
end

local KNOWN = { format = true, current = true, source = true, applied = true, mod = true, sandboxed = true, sandbox = true }

local function entry(kind, key)
    return kind .. "\n" .. key
end

local function where(kind, pack, key)
    return kind .. "\n" .. pack .. "\n" .. key
end

-- The ledger holds, per pack and entry, the pack value last decided on and the value Prepackaged last applied.
function State.decision(state, kind, pack, key)
    local i = state.at[where(kind, pack, key)]
    return i and state.ledger[i]
end

-- The values Prepackaged applied for this entry under any pack, until a decline makes the value the player's.
function State.applied(state, kind, key)
    local list = {}
    for _, i in ipairs(state.entries[entry(kind, key)] or {}) do
        list[#list + 1] = state.ledger[i].applied
    end
    return list
end

local function put(state, record)
    local id = where(record.kind, record.pack, record.key)
    local i = state.at[id]
    if i == nil then
        i = #state.ledger + 1
        state.at[id] = i
        local key = entry(record.kind, record.key)
        state.entries[key] = state.entries[key] or {}
        table.insert(state.entries[key], i)
    end
    state.ledger[i] = record
end

-- An unchanged entry keeps the value applied before. A declined one keeps the player's value, so no pack applied it.
function State.decide(state, record)
    local old = State.decision(state, record.kind, record.pack, record.key)
    if record.decision == "declined" then
        for _, i in ipairs(state.entries[entry(record.kind, record.key)] or {}) do
            state.ledger[i].applied = nil
        end
    elseif record.applied == nil and old ~= nil then
        record.applied = old.applied
    end
    put(state, record)
end

-- bind|pack|decision|asked|applied|name and opt|pack|decision|asked|applied|page|option. Pack values hold no |, nor
-- do pages and options; a bind name may, so it comes last. Anything else is kept as an unknown line.
local function ledgerLine(state, line, f)
    if not DECISIONS[f[3]] or f[2] == "" or f[4] == "" then
        return false
    end
    local applied = f[5] ~= "" and f[5] or nil
    if f[1] == "bind" and #f >= 6 and Text.after(line, 5) ~= "" then
        put(state, { kind = "bind", pack = f[2], decision = f[3], asked = f[4], applied = applied, key = Text.after(line, 5) })
        return true
    elseif f[1] == "opt" and #f == 7 and f[6] ~= "" and f[7] ~= "" then
        put(state, { kind = "opt", pack = f[2], decision = f[3], asked = f[4], applied = applied, key = f[6] .. "|" .. f[7] })
        return true
    end
    return false
end

function State.decode(lines)
    local state = State.new()
    for _, line in ipairs(lines) do
        local f = Text.split(line, "|")
        local kind = f[1]
        if kind == "bind" or kind == "opt" then
            if not (#f >= 6 and ledgerLine(state, line, f)) then
                state.unknown[#state.unknown + 1] = line
            end
        elseif not KNOWN[kind] then
            if line ~= "" then
                state.unknown[#state.unknown + 1] = line
            end
        elseif kind == "format" and #f == 2 and string.match(f[2], "^[0-9]+$") then
            state.newer = tonumber(f[2]) > State.FORMAT
        elseif kind == "current" and #f == 2 and f[2] ~= "" then
            state.current = f[2]
        elseif kind == "source" and #f >= 3 and (f[2] == "mod" or f[2] == "file") and Text.after(line, 2) ~= "" then
            state.source = { kind = f[2], name = Text.after(line, 2) }
        elseif kind == "applied" and #f == 2 and Version.valid(f[2]) then
            state.applied = f[2]
        elseif kind == "mod" and #f >= 2 and Text.after(line, 1) ~= "" then
            state.mods[#state.mods + 1] = Text.after(line, 1)
        elseif kind == "sandboxed" and #f == 2 and f[2] == "1" then
            state.sandboxed = true
        elseif kind == "sandbox" and #f >= 2 and string.find(Text.after(line, 1), "=", 2, true) then
            state.sandbox[#state.sandbox + 1] = Text.after(line, 1)
        end
    end
    return state
end

function State.encode(state)
    local lines = { "format|" .. tostring(State.FORMAT) }
    if state.current ~= nil then
        lines[#lines + 1] = "current|" .. state.current
    end
    if state.source ~= nil then
        lines[#lines + 1] = "source|" .. state.source.kind .. "|" .. state.source.name
    end
    if state.applied ~= nil then
        lines[#lines + 1] = "applied|" .. state.applied
    end
    for _, id in ipairs(state.mods) do
        lines[#lines + 1] = "mod|" .. id
    end
    if state.sandboxed then
        lines[#lines + 1] = "sandboxed|1"
    end
    for _, line in ipairs(state.sandbox) do
        lines[#lines + 1] = "sandbox|" .. line
    end
    for _, r in ipairs(state.ledger) do
        local head = r.kind .. "|" .. r.pack .. "|" .. r.decision .. "|" .. r.asked .. "|" .. (r.applied or "") .. "|"
        lines[#lines + 1] = head .. r.key
    end
    for _, line in ipairs(state.unknown) do
        lines[#lines + 1] = line
    end
    return lines
end

-- Unknown lines and the ledger stay in the state file: a backup keeps only the pack in use.
function State.pack(state)
    local pack = State.new()
    pack.current, pack.source, pack.applied, pack.mods = state.current, state.source, state.applied, Text.copy(state.mods)
    pack.sandbox, pack.sandboxed = Text.copy(state.sandbox), state.sandboxed
    return pack
end

function State.setPack(state, pack)
    state.current, state.source, state.applied, state.mods = pack.current, pack.source, pack.applied, Text.copy(pack.mods)
    state.sandbox, state.sandboxed = Text.copy(pack.sandbox), pack.sandboxed
end

function State.record(state, pack, source, mods)
    local sandbox = {}
    for i, entry in ipairs(pack.sandbox) do
        sandbox[i] = Sandbox.line(entry)
    end
    State.setPack(state, { current = pack.id, source = source, applied = pack.version, mods = mods, sandbox = sandbox, sandboxed = true })
end

return State
