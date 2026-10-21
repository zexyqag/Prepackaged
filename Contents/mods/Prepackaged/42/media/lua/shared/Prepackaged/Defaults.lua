-- What each @keys and @modoptions entry of the pack in use needs, judged against the game as it is loaded now, and the
-- keys that end up on more than one bind. Values: a bind is { key, altCode, shift, ctrl, alt }; a mod option holds what
-- its type holds (combobox the index, multipletickbox a list of booleans, colorpicker { r, g, b, a }).
local Parse = require "Prepackaged/Parse"

local Defaults = {}

-- MainOptions.loadKeys gives these binds other keys on an AZERTY keyboard (MainOptions.lua:3496-3505).
local AZERTY = { Left = 16, Forward = 44, Shout = 30, VehicleHorn = 30 }
-- Mouse buttons are 10000 + the button, and Core.isKey takes them whatever modifiers are held (Core.java:2786-2789).
local MOUSE = 10000

local function flag(value)
    return value and true or false
end

-- A keyBinding entry as MainOptions.loadKeys makes it the default (MainOptions.lua:3478-3507).
function Defaults.keyDefault(entry, azerty)
    local key, altCode = entry.key, entry.alt or 0
    if key == nil then
        key, altCode = altCode, 0
    end
    if azerty and AZERTY[entry.value] ~= nil then
        key = AZERTY[entry.value]
    end
    return { key = tonumber(key) or 0, altCode = tonumber(altCode) or 0, shift = flag(entry.shift), ctrl = flag(entry.ctrl), alt = flag(entry.altKey) }
end

-- As keysB42.ini holds a bind (MainOptions.writeKey). Codes may still be KEY_ names.
function Defaults.bindText(bind)
    local text = "key:" .. tostring(bind.key)
    if bind.altCode ~= 0 then
        text = text .. ";altCode:" .. tostring(bind.altCode)
    end
    if bind.shift then
        text = text .. ";shift:true"
    end
    if bind.ctrl then
        text = text .. ";ctrl:true"
    end
    if bind.alt then
        text = text .. ";alt:true"
    end
    return text
end

local function same(kind, a, b)
    if a == nil or b == nil then
        return a == b
    elseif kind == "bind" then
        return a.key == b.key and a.altCode == b.altCode and a.shift == b.shift and a.ctrl == b.ctrl and a.alt == b.alt
    elseif kind == "multipletickbox" then
        if #a ~= #b then
            return false
        end
        for i = 1, #a do
            if a[i] ~= b[i] then
                return false
            end
        end
        return true
    elseif kind == "colorpicker" then
        return a.r == b.r and a.g == b.g and a.b == b.b and a.a == b.a
    end
    return a == b
end
Defaults.same = same

local function kindOf(item)
    return item.kind == "bind" and "bind" or item.type
end

local function code(value, resolve)
    if type(value) == "number" then
        return value
    end
    return resolve(value)
end

-- The bind with its KEY_ names as codes, or nil and the name that is no key.
local function bindValue(bind, resolve)
    local key, altCode = code(bind.key, resolve), code(bind.altCode, resolve)
    if key == nil then
        return nil, bind.key
    elseif altCode == nil then
        return nil, bind.altCode
    end
    return { key = key, altCode = altCode, shift = bind.shift, ctrl = bind.ctrl, alt = bind.alt }
end

-- A value from the ledger, written by an earlier pack, or nil.
local function valueOf(item, text, resolve)
    if item.kind == "bind" then
        local bind = Parse.bindSpec(text)
        return bind and (bindValue(bind, resolve))
    end
    local value = Parse.optionValue(item.type, text)
    if item.type == "keybind" and value ~= nil then
        return code(value, resolve)
    end
    return value
end

local function misfit(target, value)
    local kind = target.type
    if kind == "combobox" and value > target.count then
        return "Range", { value, 1, target.count }
    elseif kind == "slider" and type(target.min) == "number" and type(target.max) == "number" and (value < target.min or value > target.max) then
        return "Range", { value, target.min, target.max }
    elseif kind == "multipletickbox" and #value ~= target.count then
        return "Count", { #value, target.count }
    end
end

-- args: pack, targets (Settings.read), record(kind, key) for the ledger, resolve(KEY_ name) for a code, and all to show
-- the entries decided before too.
function Defaults.review(args)
    local targets, resolve = args.targets, args.resolve
    local review = { all = args.all == true, rows = {}, same = {}, waiting = {}, server = {}, invalid = {}, decided = 0, blocked = {} }
    local function put(list, item, reason, reasonArgs)
        item.reason, item.args = reason, reasonArgs or {}
        list[#list + 1] = item
    end
    local function judge(item, target, value)
        local kind = kindOf(item)
        item.target, item.to, item.from = target, value, target.current
        item.section = (kind == "bind" or kind == "keybind") and "keys" or "options"
        if target.enabled == false then
            return put(review.server, item, "Server")
        elseif same(kind, target.current, value) then
            return put(review.same, item)
        end
        local record = args.record(item.kind, item.key)
        local asked = record ~= nil and record.asked == item.text
        if asked and not review.all then
            review.decided = review.decided + 1
            return
        end
        local applied = nil
        if record ~= nil and record.applied ~= nil then
            applied = valueOf(item, record.applied, resolve)
        end
        item.own = not same(kind, target.current, target.default) and not (applied ~= nil and same(kind, target.current, applied))
        item.declined = asked and record.decision == "declined"
        item.ticked = not item.own and not item.declined
        review.rows[#review.rows + 1] = item
    end
    local function absent(item, kind, reason)
        local missing = targets.missing[kind]
        if missing ~= nil then
            review.blocked[kind] = missing
            return put(review.waiting, item, "Feature", { missing })
        end
        put(review.waiting, item, reason)
    end
    for _, bind in ipairs(args.pack.keys) do
        local item = { kind = "bind", key = bind.name, name = bind.name, text = Defaults.bindText(bind), line = bind.line }
        local value, bad = bindValue(bind, resolve)
        local target = targets.binds[bind.name]
        if value == nil then
            put(review.invalid, item, "KeyName", { bad })
        elseif target == nil then
            absent(item, "binds", "NotLoaded")
        else
            judge(item, target, value)
        end
    end
    for _, m in ipairs(args.pack.modoptions) do
        local key = m.page .. "|" .. m.option
        local item = { kind = "opt", key = key, page = m.page, option = m.option, type = m.type, text = m.text, line = m.line }
        local value = m.value
        if m.type == "keybind" then
            value = code(m.value, resolve)
        end
        local target = targets.options[key]
        if value == nil then
            put(review.invalid, item, "KeyName", { m.value })
        elseif target == nil then
            absent(item, "options", targets.pages[m.page] and "NoOption" or "NotLoaded")
        else
            local reason, reasonArgs = "Type", { m.type, target.type }
            if target.type == m.type then
                reason, reasonArgs = misfit(target, value)
            end
            if reason ~= nil then
                item.target = target
                put(review.invalid, item, reason, reasonArgs)
            else
                judge(item, target, value)
            end
        end
    end
    -- In the game's order: each target has a place from 1 to targets.n. Kahlua's table.sort is a plain quicksort, slow
    -- on a list nearly in order, such as a pasted keysB42.ini.
    local at = {}
    for _, item in ipairs(review.rows) do
        at[item.target.order] = item
    end
    review.rows = {}
    for order = 1, targets.n do
        if at[order] ~= nil then
            review.rows[#review.rows + 1] = at[order]
        end
    end
    return review
end

local function counter()
    return { n = 0, nn = 0, p = 0, pn = 0 }
end

-- n: binds, p: the pack's; nn and pn leave out binds on the key the game ships them on.
local function count(c, e)
    c.n = c.n + 1
    if not e.shipped then
        c.nn = c.nn + 1
    end
    if e.set then
        c.p = c.p + 1
        if not e.shipped then
            c.pn = c.pn + 1
        end
    end
end

local function signature(bind)
    return (bind.shift and "s" or "") .. (bind.ctrl and "c" or "") .. (bind.alt and "a" or "")
end

-- The binds on one key that clash with a bind the pack sets, in linear time: binds with other modifiers don't clash
-- (Core.invalidBindingShiftCtrl, Core.java:2782-2827) unless the key is a mouse button, and a mod option key bind
-- reads the key alone, so it clashes with every bind on it. Two binds the game ships, both on their shipped keys,
-- share them by design.
local function involved(list, key)
    local whole, mods, buckets = counter(), counter(), {}
    for _, e in ipairs(list) do
        count(whole, e)
        if e.mod then
            count(mods, e)
        else
            local s = signature(e.bind)
            buckets[s] = buckets[s] or counter()
            count(buckets[s], e)
        end
    end
    local result = {}
    for _, e in ipairs(list) do
        local c = whole
        if not e.mod and key < MOUSE then
            local b = buckets[signature(e.bind)]
            c = { n = b.n + mods.n, nn = b.nn + mods.nn, p = b.p + mods.p, pn = b.pn + mods.pn }
        end
        local partners
        if e.set then
            partners = e.shipped and c.nn or c.n - 1
        else
            partners = e.shipped and c.pn or c.p
        end
        if partners > 0 then
            result[#result + 1] = e
        end
    end
    return result
end

-- After the ticked changes, each key that a bind the pack sets shares with another bind, in the order of the first bind
-- on it. ticks[item] is true for a ticked row.
function Defaults.clashes(targets, review, ticks)
    local final, set = {}, {}
    for _, item in ipairs(review.rows) do
        if ticks[item] then
            final[item.target], set[item.target] = item.to, true
        end
    end
    for _, item in ipairs(review.same) do
        set[item.target] = true
    end
    local groups, keys = {}, {}
    local function occupy(target, bind, mod)
        local e = { target = target, bind = bind, mod = mod, set = set[target] == true,
            shipped = not mod and target.shipped ~= nil and same("bind", bind, target.shipped) }
        local function at(key)
            if key > 0 then
                if groups[key] == nil then
                    groups[key] = {}
                    keys[#keys + 1] = key
                end
                local list = groups[key]
                list[#list + 1] = e
            end
        end
        at(bind.key)
        if bind.altCode ~= bind.key then
            at(bind.altCode)
        end
    end
    for _, target in ipairs(targets.bindList) do
        occupy(target, final[target] or target.current, false)
    end
    for _, target in ipairs(targets.keyOptions) do
        local key = final[target]
        if key == nil then
            key = target.current
        end
        occupy(target, { key = tonumber(key) or 0, altCode = 0, shift = false, ctrl = false, alt = false }, true)
    end
    local result = {}
    for _, key in ipairs(keys) do
        local list = groups[key]
        if #list > 1 then
            local binds = involved(list, key)
            if #binds > 0 then
                result[#result + 1] = { key = key, binds = binds }
            end
        end
    end
    return result
end

-- What Apply leaves in the ledger: applied for each ticked row that was written, declined for each unticked row, and
-- same for each entry that already had the pack's value. A ticked row that wasn't written is asked again.
function Defaults.records(pack, review, ticks, written)
    local list = {}
    local function add(item, decision)
        list[#list + 1] = {
            kind = item.kind, pack = pack, key = item.key, decision = decision, asked = item.text,
            applied = decision == "applied" and item.text or nil,
        }
    end
    for _, item in ipairs(review.rows) do
        if not ticks[item] then
            add(item, "declined")
        elseif written[item] then
            add(item, "applied")
        end
    end
    for _, item in ipairs(review.same) do
        add(item, "same")
    end
    return list
end

function Defaults.ticks(review)
    local ticks = {}
    for _, item in ipairs(review.rows) do
        ticks[item] = item.ticked or nil
    end
    return ticks
end

return Defaults
