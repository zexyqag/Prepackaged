-- Character classes are spelled out because Kahlua's %a, %d and %w also match non-ASCII letters and digits.
local Text = require "Prepackaged/Text"
local Version = require "Prepackaged/Version"

local Parse = {}

Parse.FILE = "prepackaged.txt"
Parse.MOD_ID = "Prepackaged"
-- Generous for real packs (a few hundred lines and a few KB), small enough that a hostile file is read in a second or
-- two in Kahlua. A line holds a whole Mods or WorkshopItems list, so it may be long.
Parse.MAX_LINES = 20000
Parse.MAX_SIZE = 1000000
Parse.MAX_LINE = 100000
-- Nobody reads more, and each note becomes a row in the window.
Parse.MAX_NOTES = 100

local trim, split = Text.trim, Text.split
local MOC_ID = "ModOptionsControl"
local ID_MAX = 48
local WHOLE_DIGITS = 9
-- PublishedFileId_t is a uint64.
local WORKSHOP_MAX = "18446744073709551615"
-- Java's UTF-8 reader keeps a byte order mark as this one character at the start of the first line.
local BOM = 65279
local NEEDS = { ZombieBuddy = true }
local BOOLEANS = { ["true"] = true, ["false"] = false }
local SANDBOX_NAME = "^[A-Za-z_][A-Za-z0-9_]*$"
local SANDBOX_TABLE_NAME = "^[A-Za-z_][A-Za-z0-9_]*%.[A-Za-z_][A-Za-z0-9_]*$"

local function splitAt(text, separator)
    local i = string.find(text, separator, 1, true)
    if i == nil then
        return nil
    end
    return trim(string.sub(text, 1, i - 1)), trim(string.sub(text, i + 1))
end

local function isWhole(text)
    return string.match(text, "^[0-9]+$") ~= nil
end

-- With the exponent Kahlua's tostring writes below 0.001 and from 10^7 (Java's Double.toString).
local function isNumber(text)
    local e = string.find(text, "[eE]")
    if e ~= nil then
        if string.match(string.sub(text, e + 1), "^[+-]?[0-9]+$") == nil then
            return false
        end
        text = string.sub(text, 1, e - 1)
    end
    return string.match(text, "^%-?[0-9]+$") ~= nil or string.match(text, "^%-?[0-9]*%.[0-9]+$") ~= nil
end

local function isWorkshopId(text)
    if string.match(text, "^[1-9][0-9]*$") == nil then
        return false
    end
    return #text < #WORKSHOP_MAX or (#text == #WORKSHOP_MAX and text <= WORKSHOP_MAX)
end

local function isKeyCode(text)
    return isWhole(text) or string.match(text, "^KEY_[A-Za-z0-9_]+$") ~= nil
end

local function keyCode(text)
    if isWhole(text) then
        return tonumber(text)
    end
    return text
end

local function words(text)
    local list = {}
    for _, word in ipairs(split(text, " ")) do
        if word ~= "" then
            list[#list + 1] = word
        end
    end
    return list
end

local function add(ctx, kind, line, code, ...)
    local list = ctx[kind]
    if #list < Parse.MAX_NOTES then
        list[#list + 1] = { line = line, code = code, args = { ... } }
    else
        ctx.more[kind] = ctx.more[kind] + 1
    end
end

local function warn(ctx, line, code, ...)
    add(ctx, "warnings", line, code, ...)
end

local function fail(ctx, line, code, ...)
    add(ctx, "errors", line, code, ...)
end

-- Linear, and stable so notes on one line keep the order they were found in.
local function byLine(list)
    local buckets, last = {}, 0
    for _, note in ipairs(list) do
        local bucket = buckets[note.line]
        if bucket == nil then
            bucket = {}
            buckets[note.line] = bucket
        end
        bucket[#bucket + 1] = note
        last = math.max(last, note.line)
    end
    local i = 0
    for line = 0, last do
        for _, note in ipairs(buckets[line] or {}) do
            i = i + 1
            list[i] = note
        end
    end
end

local function addEach(ctx, n, value, list, at, check, code)
    for _, item in ipairs(split(value, ";")) do
        item = trim(item)
        if item ~= "" then
            if check ~= nil and not check(item) then
                warn(ctx, n, code, item)
            elseif at[item] ~= nil then
                warn(ctx, n, "Duplicate", item)
            else
                at[item] = n
                list[#list + 1] = item
            end
        end
    end
end

local function positive(ctx, n, key, value)
    if isWhole(value) and #value <= WHOLE_DIGITS and tonumber(value) >= 1 then
        return tonumber(value)
    end
    warn(ctx, n, "BadNumber", key, value)
end

local PACK = {
    id = function(ctx, n, value)
        if #value <= ID_MAX and string.match(value, "^[A-Za-z0-9_%-]+$") then
            ctx.pack.id = value
        else
            fail(ctx, n, "BadId", value)
        end
    end,
    name = function(ctx, n, value)
        if value ~= "" then
            ctx.pack.name = value
        end
    end,
    version = function(ctx, n, value)
        if Version.valid(value) then
            ctx.pack.version = value
        else
            fail(ctx, n, Version.valid(value .. ".0.0") and "WholeVersion" or "BadVersion", value)
        end
    end,
    collection = function(ctx, n, value)
        addEach(ctx, n, value, ctx.pack.collection, ctx.lines.collection, isWorkshopId, "BadWorkshopId")
    end,
    workshopitems = function(ctx, n, value)
        addEach(ctx, n, value, ctx.pack.workshopItems, ctx.lines.workshopItems, isWorkshopId, "BadWorkshopId")
    end,
    -- The server and the mods file drop every \ (GameServer.java:641-649, ActiveModsFile.java:108).
    mods = function(ctx, n, value)
        addEach(ctx, n, (string.gsub(value, "\\", "")), ctx.pack.mods, ctx.lines.mods)
    end,
    map = function(ctx, n, value)
        if value ~= "" then
            ctx.pack.map = value
        end
    end,
    maporder = function(ctx, n, value)
        addEach(ctx, n, value, ctx.pack.mapOrder, ctx.lines.mapOrder)
    end,
    needs = function(ctx, n, value)
        addEach(ctx, n, value, ctx.pack.needs, ctx.lines.needs, function(item) return NEEDS[item] ~= nil end, "UnknownNeed")
    end,
    heap = function(ctx, n, value)
        ctx.pack.heap = positive(ctx, n, "heap", value)
    end,
    hostmemory = function(ctx, n, value)
        ctx.pack.hostmemory = positive(ctx, n, "hostmemory", value)
    end,
}
local SINGLE = { id = true, name = true, version = true, map = true, heap = true, hostmemory = true }

local function packLine(ctx, n, line)
    local key, value = splitAt(line, "=")
    if key == nil then
        return warn(ctx, n, "BadLine")
    end
    local name = string.lower(key)
    if PACK[name] == nil then
        return warn(ctx, n, "UnknownKey", key)
    end
    if ctx.lines.pack[name] ~= nil and SINGLE[name] then
        return warn(ctx, n, "RepeatedKey", key)
    end
    ctx.lines.pack[name] = ctx.lines.pack[name] or n
    PACK[name](ctx, n, value)
end

local function optionalLine(ctx, n, line)
    local id, label = splitAt(line, "=")
    if id == nil then
        id, label = line, ""
    end
    id = trim((string.gsub(id, "\\", "")))
    if id == "" or string.find(id, ";", 1, true) then
        return warn(ctx, n, "BadModId", id)
    end
    if ctx.seen.optional[id] then
        return warn(ctx, n, "Duplicate", id)
    end
    ctx.seen.optional[id] = true
    local entry = { id = id, line = n }
    if label ~= "" then
        entry.label = label
    end
    local list = ctx.pack.optional
    list[#list + 1] = entry
end

local function collectionLine(ctx, n, line)
    local id, rest = splitAt(line, "=")
    if id == nil then
        return warn(ctx, n, "BadLine")
    end
    if not isWorkshopId(id) then
        return warn(ctx, n, "BadWorkshopId", id)
    end
    -- Titles may hold |, so the last one ends the title.
    local bar = nil
    local from = 1
    while true do
        local i = string.find(rest, "|", from, true)
        if i == nil then
            break
        end
        bar, from = i, i + 1
    end
    if bar == nil then
        return warn(ctx, n, "BadLine")
    end
    if ctx.seen.collections[id] then
        return warn(ctx, n, "RepeatedCollection", id)
    end
    local entry = { id = id, title = trim(string.sub(rest, 1, bar - 1)), items = {}, children = {}, line = n }
    local seen = {}
    for _, item in ipairs(split(string.sub(rest, bar + 1), ";")) do
        item = trim(item)
        local child = string.match(item, "^c:(.*)$")
        local target = trim(child or item)
        if item ~= "" and not isWorkshopId(target) then
            warn(ctx, n, "BadWorkshopId", item)
        elseif item ~= "" and seen[target] then
            warn(ctx, n, "Duplicate", target)
        elseif item ~= "" then
            seen[target] = true
            local list = child and entry.children or entry.items
            list[#list + 1] = target
        end
    end
    ctx.seen.collections[id] = entry
    local list = ctx.pack.collections
    list[#list + 1] = entry
end

local function keyPart(bind, part)
    local name, value = splitAt(part, ":")
    -- A code alone is the key, as keys.ini holds a bind.
    if name == nil and bind.key == nil and isKeyCode(part) then
        bind.key = keyCode(part)
        return true
    end
    if name == "key" or name == "altCode" then
        if not isKeyCode(value) then
            return false
        end
        bind[name] = keyCode(value)
        return true
    end
    if (name == "shift" or name == "ctrl" or name == "alt") and BOOLEANS[value] ~= nil then
        bind[name] = BOOLEANS[value]
        return true
    end
    return false
end

-- The bind and the parts that aren't part of a bind.
local function keySpec(spec)
    local bind, bad = { altCode = 0, shift = false, ctrl = false, alt = false }, {}
    for _, part in ipairs(split(spec, ";")) do
        part = trim(part)
        if part ~= "" and not keyPart(bind, part) then
            bad[#bad + 1] = part
        end
    end
    return bind, bad
end

-- A keysB42.ini value such as key:34;shift:true, or a keys.ini one such as 34, or nil.
function Parse.bindSpec(spec)
    local bind, bad = keySpec(spec)
    if bind.key == nil or #bad > 0 then
        return nil
    end
    return bind
end

local function keyLine(ctx, n, line)
    if string.sub(line, 1, 1) == "[" then
        return
    end
    local name, spec = splitAt(line, "=")
    if name == nil or name == "" then
        return warn(ctx, n, "BadLine")
    end
    if name == "VERSION" then
        return
    end
    local bind, bad = keySpec(spec)
    bind.name, bind.line = name, n
    for _, part in ipairs(bad) do
        warn(ctx, n, "BadKeyPart", part)
    end
    if bind.key == nil then
        return warn(ctx, n, "BadKey", name)
    end
    if ctx.seen.keys[name] then
        return warn(ctx, n, "Duplicate", name)
    end
    ctx.seen.keys[name] = true
    local list = ctx.pack.keys
    list[#list + 1] = bind
end

local VALUES = {
    tickbox = function(text)
        if BOOLEANS[text] ~= nil then
            return BOOLEANS[text], text
        end
    end,
    combobox = function(text)
        if isWhole(text) and #text <= WHOLE_DIGITS and tonumber(text) >= 1 then
            return tonumber(text), tostring(tonumber(text))
        end
    end,
    slider = function(text)
        if isNumber(text) then
            return tonumber(text), text
        end
    end,
    multipletickbox = function(text)
        local list = words(text)
        local values = {}
        for i, word in ipairs(list) do
            if BOOLEANS[word] == nil then
                return nil
            end
            values[i] = BOOLEANS[word]
        end
        if #values > 0 then
            return values, table.concat(list, " ")
        end
    end,
    colorpicker = function(text)
        local list = words(text)
        if #list ~= 4 then
            return nil
        end
        for _, word in ipairs(list) do
            if not isNumber(word) then
                return nil
            end
        end
        local color = { r = tonumber(list[1]), g = tonumber(list[2]), b = tonumber(list[3]), a = tonumber(list[4]) }
        return color, table.concat(list, " ")
    end,
    textentry = function(text)
        return text, text
    end,
    keybind = function(text)
        if isKeyCode(text) then
            return keyCode(text), text
        end
    end,
}

-- A ModOptions.ini value of this type, or nil.
function Parse.optionValue(kind, text)
    local read = VALUES[kind]
    return read and (read(text))
end

-- raw is the line before trimming: the game keeps a textentry value exactly (ModOptions.lua:304-307).
local function modOptionLine(ctx, n, line, raw)
    local fields = split(raw, "|")
    if #fields < 4 then
        return warn(ctx, n, "BadLine")
    end
    if #fields > 4 then
        return warn(ctx, n, "TooManyFields")
    end
    local kind, page, option, text = trim(fields[1]), trim(fields[2]), trim(fields[3]), fields[4]
    if VALUES[kind] == nil then
        return warn(ctx, n, "UnknownType", kind)
    end
    if page == "" or option == "" then
        return warn(ctx, n, "BadLine")
    end
    if kind ~= "textentry" then
        text = trim(text)
    end
    -- The game ignores an empty textentry line when it loads ModOptions.ini.
    if text == "" then
        return warn(ctx, n, "EmptyValue", page .. "|" .. option)
    end
    local value, written = VALUES[kind](text)
    if value == nil then
        return warn(ctx, n, "BadValue", kind, text)
    end
    local key = page .. "|" .. option
    if ctx.seen.modoptions[key] then
        return warn(ctx, n, "Duplicate", key)
    end
    ctx.seen.modoptions[key] = true
    local list = ctx.pack.modoptions
    list[#list + 1] = { type = kind, page = page, option = option, value = value, text = written, line = n }
end

local function sandboxLine(ctx, n, line)
    local name, value = splitAt(line, "=")
    if name == nil then
        return warn(ctx, n, "BadLine")
    end
    if name == "VERSION" then
        return
    end
    if not string.match(name, SANDBOX_NAME) and not string.match(name, SANDBOX_TABLE_NAME) then
        return warn(ctx, n, "BadSandboxName", name)
    end
    if ctx.seen.sandbox[name] then
        return warn(ctx, n, "Duplicate", name)
    end
    ctx.seen.sandbox[name] = true
    local list = ctx.pack.sandbox
    list[#list + 1] = { name = name, value = value, line = n }
end

-- The rules file takes any page and option id (MOC_Shared.lua:64-89), so only the first . splits.
local function lockLine(ctx, n, line)
    local dot = string.find(line, ".", 1, true)
    local page = dot and trim(string.sub(line, 1, dot - 1)) or line
    local option = dot and trim(string.sub(line, dot + 1)) or nil
    if page == "" or option == "" then
        return warn(ctx, n, "BadLock", line)
    end
    local key = option and (page .. "." .. option) or page
    if ctx.seen.locks[key] then
        return warn(ctx, n, "Duplicate", key)
    end
    ctx.seen.locks[key] = true
    local list = ctx.pack.locks
    list[#list + 1] = { page = page, option = option, line = n }
end

local SECTIONS = {
    pack = packLine,
    optional = optionalLine,
    collections = collectionLine,
    keys = keyLine,
    modoptions = modOptionLine,
    sandbox = sandboxLine,
    locks = lockLine,
}

-- Iterative: Kahlua's call stack ends at about 100 frames.
local function cycles(ctx)
    local byId, state = ctx.seen.collections, {}
    for _, root in ipairs(ctx.pack.collections) do
        if state[root.id] == nil then
            state[root.id] = "open"
            local stack = { { entry = root, next = 1 } }
            while #stack > 0 do
                local frame = stack[#stack]
                local child = frame.entry.children[frame.next]
                if child == nil then
                    state[frame.entry.id] = "done"
                    stack[#stack] = nil
                else
                    frame.next = frame.next + 1
                    local target = byId[child]
                    if target ~= nil and state[child] == "open" then
                        warn(ctx, frame.entry.line, "CollectionCycle", frame.entry.id, child)
                    elseif target ~= nil and state[child] == nil then
                        state[child] = "open"
                        stack[#stack + 1] = { entry = target, next = 1 }
                    end
                end
            end
        end
    end
end

local function finish(ctx, sourceMod)
    local pack, keys = ctx.pack, ctx.lines.pack
    if keys.id == nil then
        fail(ctx, 0, "MissingKey", "id")
    end
    if keys.version == nil then
        fail(ctx, 0, "MissingKey", "version")
    end
    if #pack.workshopItems == 0 then
        fail(ctx, keys.workshopitems or 0, "MissingKey", "WorkshopItems")
    end
    if #pack.mods == 0 then
        fail(ctx, keys.mods or 0, "MissingKey", "Mods")
    else
        if ctx.lines.mods[Parse.MOD_ID] == nil then
            fail(ctx, keys.mods, "MissingMod", Parse.MOD_ID)
        end
        if sourceMod ~= nil and ctx.lines.mods[sourceMod] == nil then
            fail(ctx, keys.mods, "MissingMod", sourceMod)
        end
    end
    local optional = {}
    for _, entry in ipairs(pack.optional) do
        if ctx.lines.mods[entry.id] ~= nil then
            warn(ctx, entry.line, "OptionalInMods", entry.id)
        else
            optional[#optional + 1] = entry
        end
    end
    pack.optional = optional
    local byId = ctx.seen.collections
    for _, entry in ipairs(pack.collections) do
        for _, child in ipairs(entry.children) do
            if byId[child] == nil then
                warn(ctx, entry.line, "UnknownCollection", child)
            end
        end
    end
    if #pack.collections > 0 then
        for _, id in ipairs(pack.collection) do
            if byId[id] == nil then
                warn(ctx, ctx.lines.collection[id], "UnknownCollection", id)
            end
        end
    end
    cycles(ctx)
    if #pack.locks > 0 and ctx.lines.mods[MOC_ID] == nil then
        warn(ctx, pack.locks[1].line, "LocksWithoutMOC", MOC_ID)
    end
    -- Defaults are noted as mods load: Shipped copies keyBinding and Settings wraps PZAPI.ModOptions.load.
    if #pack.keys + #pack.modoptions > 0 and ctx.lines.mods[Parse.MOD_ID] ~= nil and pack.mods[1] ~= Parse.MOD_ID then
        warn(ctx, ctx.lines.mods[Parse.MOD_ID], "NotFirst", Parse.MOD_ID)
    end
end

local function newContext()
    return {
        pack = {
            collection = {}, workshopItems = {}, mods = {}, mapOrder = {}, needs = {},
            optional = {}, collections = {}, keys = {}, modoptions = {}, sandbox = {}, locks = {},
        },
        errors = {},
        warnings = {},
        more = { errors = 0, warnings = 0 },
        lines = { pack = {}, mods = {}, workshopItems = {}, collection = {}, mapOrder = {}, needs = {} },
        seen = { optional = {}, collections = {}, keys = {}, modoptions = {}, sandbox = {}, locks = {} },
    }
end

local function result(ctx)
    byLine(ctx.errors)
    byLine(ctx.warnings)
    return { pack = ctx.pack, errors = ctx.errors, warnings = ctx.warnings, more = ctx.more }
end

-- Stops one line past a cap, so read still sees that the file is too big.
function Parse.collect(nextLine)
    local lines, size = {}, 0
    local line = nextLine()
    while line ~= nil do
        lines[#lines + 1] = line
        size = size + #line
        if #lines > Parse.MAX_LINES or size > Parse.MAX_SIZE then
            return lines
        end
        line = nextLine()
    end
    return lines
end

-- As BufferedReader.readLine splits a file: CRLF, LF and CR end a line.
function Parse.lines(text)
    local from = 1
    return Parse.collect(function()
        if from > #text then
            return nil
        end
        local i = string.find(text, "[\r\n]", from)
        local stop = (i or #text + 1) - 1
        local line = string.sub(text, from, math.min(stop, from + Parse.MAX_SIZE))
        from = (i ~= nil and string.sub(text, i, i + 1) == "\r\n") and i + 2 or stop + 2
        return line
    end)
end

function Parse.failed(message)
    local ctx = newContext()
    fail(ctx, 0, "Unreadable", string.sub(tostring(message), 1, 200))
    return result(ctx)
end

function Parse.read(lines, sourceMod)
    local ctx = newContext()
    local size = 0
    for _, line in ipairs(lines) do
        size = size + #line
    end
    if #lines > Parse.MAX_LINES or size > Parse.MAX_SIZE then
        fail(ctx, 0, "TooBig", Parse.MAX_LINES, Parse.MAX_SIZE)
        return result(ctx)
    end
    local section = nil
    for n, raw in ipairs(lines) do
        if #raw > Parse.MAX_LINE then
            fail(ctx, n, "LineTooLong", Parse.MAX_LINE)
        else
            if n == 1 and string.byte(raw, 1) == BOM then
                raw = string.sub(raw, 2)
            end
            local line = trim(raw)
            local first = string.sub(line, 1, 1)
            if first == "@" then
                local name = string.lower(trim(string.sub(line, 2)))
                section = SECTIONS[name] or false
                if not section then
                    warn(ctx, n, "UnknownSection", line)
                end
            elseif line ~= "" and first ~= "#" and section == nil then
                warn(ctx, n, "OutsideSection")
            elseif line ~= "" and first ~= "#" and section then
                section(ctx, n, line, raw)
            end
        end
    end
    finish(ctx, sourceMod)
    return result(ctx)
end

return Parse
