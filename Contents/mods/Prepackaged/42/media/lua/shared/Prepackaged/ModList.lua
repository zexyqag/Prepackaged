local Text = require "Prepackaged/Text"

local ModList = {}

ModList.PRESET_FILE = "pz_modlist_settings.cfg"
local FAVOURITES = "!fav!"

local same = Text.same

local function set(list)
    local result = {}
    for _, id in ipairs(list) do
        result[id] = true
    end
    return result
end

local function only(list, keep)
    local result = {}
    for _, id in ipairs(list) do
        if keep[id] then
            result[#result + 1] = id
        end
    end
    return result
end

local function without(list, drop)
    local result = {}
    for _, id in ipairs(list) do
        if not drop[id] then
            result[#result + 1] = id
        end
    end
    return result
end

-- Each mod after the mods its require= names, theirs first, as Java loads them (ZomboidFileSystem.java:806-837).
-- The Mods screen's correctAndSaveModOrder (ModSelectorModel.lua:138-163) does this one level deep. Iterative, for
-- Kahlua's short call stack; a cycle is cut where it closes. The mods already in result stay where they are.
local function withRequired(ids, requires, result)
    local state = set(result)
    for _, root in ipairs(ids) do
        if state[root] == nil then
            state[root] = "open"
            local stack = { { id = root, needs = requires(root), next = 1 } }
            while #stack > 0 do
                local frame = stack[#stack]
                local need = frame.needs[frame.next]
                if need == nil then
                    state[frame.id] = "done"
                    result[#result + 1] = frame.id
                    stack[#stack] = nil
                else
                    frame.next = frame.next + 1
                    if state[need] == nil then
                        state[need] = "open"
                        stack[#stack + 1] = { id = need, needs = requires(need), next = 1 }
                    end
                end
            end
        end
    end
    return result
end

function ModList.ticks(pack, active)
    local on, ticks = set(active), {}
    for _, entry in ipairs(pack.optional) do
        if on[entry.id] then
            ticks[entry.id] = true
        end
    end
    return ticks
end

function ModList.plan(args)
    local pack, active, state = args.pack, args.active, args.state
    local plan = {
        update = state.current == pack.id,
        active = Text.copy(active), missing = {}, unavailable = {}, optional = {}, extras = {},
    }
    local chosen = {}
    for _, id in ipairs(pack.mods) do
        local status = args.status(id)
        if status == "ok" then
            chosen[#chosen + 1] = id
        elseif status == "missing" then
            plan.missing[#plan.missing + 1] = id
        else
            plan.unavailable[#plan.unavailable + 1] = id
        end
    end
    local packed = set(pack.mods)
    for _, entry in ipairs(pack.optional) do
        packed[entry.id] = true
        local status = args.status(entry.id)
        local ticked = status == "ok" and args.ticks[entry.id] == true
        plan.optional[#plan.optional + 1] = { id = entry.id, label = entry.label, status = status, ticked = ticked }
        if ticked then
            chosen[#chosen + 1] = entry.id
        end
    end
    plan.fromPack = withRequired(chosen, args.requires, {})
    if plan.update then
        local previous, placed = set(state.mods), set(plan.fromPack)
        for _, id in ipairs(active) do
            if not previous[id] and not packed[id] and not placed[id] then
                plan.extras[#plan.extras + 1] = id
            end
        end
    end
    plan.mods = withRequired(plan.extras, args.requires, Text.copy(plan.fromPack))
    local named = set(chosen)
    for _, id in ipairs(plan.extras) do
        named[id] = true
    end
    plan.required = without(plan.mods, named)
    if #pack.mapOrder > 0 then
        plan.maps = Text.copy(pack.mapOrder)
    elseif plan.update then
        plan.maps = Text.copy(args.maps)
    else
        plan.maps = {}
    end
    local before, after = set(active), set(plan.mods)
    plan.added = without(plan.mods, before)
    plan.removed = without(active, after)
    plan.kept = only(plan.fromPack, before)
    plan.reordered = not same(only(active, after), only(plan.mods, before))
    plan.modsChanged = not same(active, plan.mods)
    plan.mapsChanged = not same(args.maps, plan.maps)
    plan.changed = plan.modsChanged or plan.mapsChanged
    return plan
end

-- SandboxOptions.isValidPresetName refuses these.
function ModList.presetName(text)
    return Text.trim((string.gsub(text, '[/\\:;"%.|]', "")))
end

-- The Mods screen reads line 1 as the favourites when it starts with !fav!, and always writes one there
-- (ModSelectorModel.lua:304-365).
function ModList.withPreset(lines, name, mods)
    local entry = name .. ":" .. table.concat(mods, ";") .. (#mods > 0 and ";" or "")
    local result, placed = {}, false
    local favourites = lines[1] ~= nil and string.sub(lines[1], 1, #FAVOURITES) == FAVOURITES
    if not favourites then
        result[1] = FAVOURITES .. ":"
    end
    for i, line in ipairs(lines) do
        local sep = string.find(line, ":", 1, true)
        if (i > 1 or not favourites) and sep ~= nil and string.sub(line, 1, sep - 1) == name then
            if not placed then
                result[#result + 1] = entry
                placed = true
            end
        else
            result[#result + 1] = line
        end
    end
    if not placed then
        result[#result + 1] = entry
    end
    return result
end

return ModList
