-- The mod list a pack asks for, compared with the list in use, and the Mods screen's preset file. Pure: the caller
-- passes in what the game knows.
local ModList = {}

-- The Mods screen's presets, one "name:id;id;" line each, after a favourites line.
ModList.PRESET_FILE = "pz_modlist_settings.cfg"

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

local function same(a, b)
    if #a ~= #b then
        return false
    end
    for i = 1, #a do
        if a[i] ~= b[i] then
            return false
        end
    end
    return true
end

-- Optional mods ticked at first: the ones enabled now.
function ModList.ticks(pack, active)
    local on, ticks = set(active), {}
    for _, entry in ipairs(pack.optional) do
        if on[entry.id] then
            ticks[entry.id] = true
        end
    end
    return ticks
end

-- args: pack; active, the mod ids enabled now in order; state (State); ticks, { [optional id] = true };
-- status(id), "ok", "missing" or "unavailable".
-- Using a pack replaces the list. Using the pack in use again, such as a newer version, replaces only the mods that
-- came from it last time and keeps the player's own after the pack's. Optional mods follow their ticks either way.
function ModList.plan(args)
    local pack, active, state = args.pack, args.active, args.state
    local plan = {
        update = state.current == pack.id,
        active = {}, fromPack = {}, missing = {}, unavailable = {}, optional = {}, extras = {},
    }
    for i, id in ipairs(active) do
        plan.active[i] = id
    end
    local function take(id)
        local status = args.status(id)
        if status == "ok" then
            plan.fromPack[#plan.fromPack + 1] = id
        elseif status == "missing" then
            plan.missing[#plan.missing + 1] = id
        else
            plan.unavailable[#plan.unavailable + 1] = id
        end
        return status
    end
    for _, id in ipairs(pack.mods) do
        take(id)
    end
    local packed = set(pack.mods)
    for _, entry in ipairs(pack.optional) do
        packed[entry.id] = true
        local status = args.status(entry.id)
        local ticked = status == "ok" and args.ticks[entry.id] == true
        plan.optional[#plan.optional + 1] = { id = entry.id, label = entry.label, status = status, ticked = ticked }
        if ticked then
            plan.fromPack[#plan.fromPack + 1] = entry.id
        end
    end
    plan.mods = {}
    for i, id in ipairs(plan.fromPack) do
        plan.mods[i] = id
    end
    if plan.update then
        local previous = set(state.mods)
        for _, id in ipairs(active) do
            if not previous[id] and not packed[id] then
                plan.extras[#plan.extras + 1] = id
                plan.mods[#plan.mods + 1] = id
            end
        end
    end
    local before, after = set(active), set(plan.mods)
    plan.added = without(plan.mods, before)
    plan.removed = without(active, after)
    plan.kept = only(plan.fromPack, before)
    plan.reordered = not same(only(active, after), only(plan.mods, before))
    plan.changed = not same(active, plan.mods)
    return plan
end

-- A preset name the Mods screen accepts (SandboxOptions.isValidPresetName) and the state file can hold.
function ModList.presetName(text)
    return string.match((string.gsub(text, '[/\\:;"%.|]', "")), "^[ \t]*(.-)[ \t]*$")
end

-- The preset file's lines with `name` holding `mods`; other lines stay as they are.
function ModList.withPreset(lines, name, mods)
    local entry = name .. ":" .. table.concat(mods, ";") .. (#mods > 0 and ";" or "")
    local result, placed = {}, false
    for _, line in ipairs(lines) do
        local sep = string.find(line, ":", 1, true)
        if sep ~= nil and string.sub(line, 1, sep - 1) == name then
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
