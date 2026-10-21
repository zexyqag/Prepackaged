local Text = require "Prepackaged/Text"

local State = {}

State.FILE = "Prepackaged/state.txt"
State.FORMAT = 1

-- unknown keeps lines a newer Prepackaged wrote, so this one writes them back.
function State.new()
    return { mods = {}, unknown = {} }
end

local KNOWN = { format = true, current = true, source = true, applied = true, mod = true }

function State.decode(lines)
    local state = State.new()
    for _, line in ipairs(lines) do
        local f = Text.split(line, "|")
        local kind = f[1]
        if not KNOWN[kind] then
            if line ~= "" then
                state.unknown[#state.unknown + 1] = line
            end
        elseif kind == "format" and #f == 2 and string.match(f[2], "^[0-9]+$") then
            state.newer = tonumber(f[2]) > State.FORMAT
        elseif kind == "current" and #f == 2 and f[2] ~= "" then
            state.current = f[2]
        elseif kind == "source" and #f >= 3 and (f[2] == "mod" or f[2] == "file") and Text.after(line, 2) ~= "" then
            state.source = { kind = f[2], name = Text.after(line, 2) }
        elseif kind == "applied" and #f == 2 and string.match(f[2], "^[0-9]+$") then
            state.applied = tonumber(f[2])
        elseif kind == "mod" and #f >= 2 and Text.after(line, 1) ~= "" then
            state.mods[#state.mods + 1] = Text.after(line, 1)
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
        lines[#lines + 1] = "applied|" .. tostring(state.applied)
    end
    for _, id in ipairs(state.mods) do
        lines[#lines + 1] = "mod|" .. id
    end
    for _, line in ipairs(state.unknown) do
        lines[#lines + 1] = line
    end
    return lines
end

-- Unknown lines stay in the state file: a backup keeps only the pack in use.
function State.pack(state)
    return { current = state.current, source = state.source, applied = state.applied, mods = Text.copy(state.mods), unknown = {} }
end

function State.setPack(state, pack)
    state.current, state.source, state.applied, state.mods = pack.current, pack.source, pack.applied, Text.copy(pack.mods)
end

function State.record(state, pack, source, mods)
    State.setPack(state, { current = pack.id, source = source, applied = pack.version, mods = mods })
end

return State
