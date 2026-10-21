-- Reads a pack file (prepackaged.txt). Pure: no game calls.
-- Character classes are spelled out because Kahlua's %a, %d and %w also match non-ASCII letters and digits.
local Parse = {}

Parse.FILE = "prepackaged.txt"

local MOD_ID = "Prepackaged"
local MOC_ID = "ModOptionsControl"
local ID_MAX = 48
local WHOLE_DIGITS = 9
local WORKSHOP_DIGITS = 20
-- Java's UTF-8 reader keeps a byte order mark as this one character at the start of the first line.
local BOM = 65279
local NEEDS = { ZombieBuddy = true }
local BOOLEANS = { ["true"] = true, ["false"] = false }
local SANDBOX_NAME = "^[A-Za-z_][A-Za-z0-9_]*$"
local SANDBOX_TABLE_NAME = "^[A-Za-z_][A-Za-z0-9_]*%.[A-Za-z_][A-Za-z0-9_]*$"

local function trim(text)
    return string.match(text, "^[ \t]*(.-)[ \t]*$")
end

-- separator is one character.
local function split(text, separator)
    local parts, from = {}, 1
    while true do
        local i = string.find(text, separator, from, true)
        if i == nil then
            parts[#parts + 1] = string.sub(text, from)
            return parts
        end
        parts[#parts + 1] = string.sub(text, from, i - 1)
        from = i + 1
    end
end

-- Splits at the first separator, both sides trimmed; nil without one.
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

local function isNumber(text)
    return string.match(text, "^%-?[0-9]+$") ~= nil or string.match(text, "^%-?[0-9]*%.[0-9]+$") ~= nil
end

local function isWorkshopId(text)
    return #text <= WORKSHOP_DIGITS and string.match(text, "^[1-9][0-9]*$") ~= nil
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

local function add(list, line, code, ...)
    list[#list + 1] = { line = line, code = code, args = { ... } }
end

local function warn(ctx, line, code, ...)
    add(ctx.warnings, line, code, ...)
end

local function fail(ctx, line, code, ...)
    add(ctx.errors, line, code, ...)
end

-- Stable, so notes on one line keep the order they were found in.
local function byLine(list)
    for i = 2, #list do
        local item, j = list[i], i - 1
        while j >= 1 and list[j].line > item.line do
            list[j + 1] = list[j]
            j = j - 1
        end
        list[j + 1] = item
    end
end

-- Splits a ;-list into list, skipping empty entries and noting bad and repeated ones. at maps entry to line.
local function addEach(ctx, n, value, list, at, check, code)
    for _, item in ipairs(split(value, ";")) do
        if check == nil then
            item = string.gsub(item, "\\", "")
        end
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
        if isWhole(value) and #value <= WHOLE_DIGITS and tonumber(value) >= 1 then
            ctx.pack.version = tonumber(value)
        else
            fail(ctx, n, "BadVersion", value)
        end
    end,
    collection = function(ctx, n, value)
        addEach(ctx, n, value, ctx.pack.collection, ctx.lines.collection, isWorkshopId, "BadWorkshopId")
    end,
    workshopitems = function(ctx, n, value)
        addEach(ctx, n, value, ctx.pack.workshopItems, ctx.lines.workshopItems, isWorkshopId, "BadWorkshopId")
    end,
    mods = function(ctx, n, value)
        addEach(ctx, n, value, ctx.pack.mods, ctx.lines.mods)
    end,
    map = function(ctx, n, value)
        if value ~= "" then
            ctx.pack.map = value
        end
    end,
    needs = function(ctx, n, value)
        addEach(ctx, n, value, ctx.pack.needs, {}, function(item) return NEEDS[item] ~= nil end, "UnknownNeed")
    end,
    heap = function(ctx, n, value)
        ctx.pack.heap = positive(ctx, n, "heap", value)
    end,
    hostmemory = function(ctx, n, value)
        ctx.pack.hostmemory = positive(ctx, n, "hostmemory", value)
    end,
}
-- Keys that take one value; the list keys may repeat, and their lines add up.
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
        if item == "" then
            -- empty entries, such as a trailing ;, are skipped
        elseif not isWorkshopId(target) then
            warn(ctx, n, "BadWorkshopId", item)
        elseif seen[target] then
            warn(ctx, n, "Duplicate", target)
        else
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
    local bind = { name = name, altCode = 0, shift = false, ctrl = false, alt = false, line = n }
    for _, part in ipairs(split(spec, ";")) do
        part = trim(part)
        if part ~= "" and not keyPart(bind, part) then
            warn(ctx, n, "BadKeyPart", part)
        end
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

-- Typed value and its text as written back, by ModOptions type; nil when the text doesn't fit the type.
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

local function modOptionLine(ctx, n, line)
    local fields = split(line, "|")
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

-- One Page or Page.option per line; Mod Options Control's own lists split on ; , and spaces.
local function lockLine(ctx, n, line)
    if string.find(line, "[;, \t]") then
        return warn(ctx, n, "BadLock", line)
    end
    local dot = string.find(line, ".", 1, true)
    local page = dot and string.sub(line, 1, dot - 1) or line
    local option = dot and string.sub(line, dot + 1) or nil
    if page == "" or option == "" then
        return warn(ctx, n, "BadLock", line)
    end
    if ctx.seen.locks[line] then
        return warn(ctx, n, "Duplicate", line)
    end
    ctx.seen.locks[line] = true
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

-- Reports each collection reached again while it is still being walked, at the line that refers back to it.
local function cycles(ctx)
    local byId = ctx.seen.collections
    local state = {}
    local function walk(entry)
        state[entry.id] = "open"
        for _, child in ipairs(entry.children) do
            local target = byId[child]
            if target ~= nil then
                if state[child] == "open" then
                    warn(ctx, entry.line, "CollectionCycle", entry.id, child)
                elseif state[child] == nil then
                    walk(target)
                end
            end
        end
        state[entry.id] = "done"
    end
    for _, entry in ipairs(ctx.pack.collections) do
        if state[entry.id] == nil then
            walk(entry)
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
        if ctx.lines.mods[MOD_ID] == nil then
            fail(ctx, keys.mods, "MissingMod", MOD_ID)
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
    byLine(ctx.errors)
    byLine(ctx.warnings)
end

-- Splits pasted text into lines as a file reader would: CRLF and LF end a line, and a last one ends the text.
function Parse.lines(text)
    local lines = split(text, "\n")
    if lines[#lines] == "" then
        lines[#lines] = nil
    end
    for i, line in ipairs(lines) do
        lines[i] = string.gsub(line, "\r$", "")
    end
    return lines
end

-- sourceMod: the mod the file came from, which the pack's Mods must then include.
-- Returns { pack, errors, warnings, lines }; each note is { line, code, args }, line 0 for the whole file.
-- lines holds the first line of each @pack key and of each mod, Workshop item and top collection.
function Parse.read(lines, sourceMod)
    local ctx = {
        pack = {
            collection = {}, workshopItems = {}, mods = {}, needs = {},
            optional = {}, collections = {}, keys = {}, modoptions = {}, sandbox = {}, locks = {},
        },
        errors = {},
        warnings = {},
        lines = { pack = {}, mods = {}, workshopItems = {}, collection = {} },
        seen = { optional = {}, collections = {}, keys = {}, modoptions = {}, sandbox = {}, locks = {} },
    }
    local section = nil
    for n, raw in ipairs(lines) do
        local line = raw
        if n == 1 and string.byte(line, 1) == BOM then
            line = string.sub(line, 2)
        end
        line = trim(line)
        local first = string.sub(line, 1, 1)
        if line == "" or first == "#" then
            -- blank lines and comments
        elseif first == "@" then
            local name = string.lower(trim(string.sub(line, 2)))
            section = SECTIONS[name] or false
            if not section then
                warn(ctx, n, "UnknownSection", line)
            end
        elseif section == nil then
            warn(ctx, n, "OutsideSection")
        elseif section then
            section(ctx, n, line)
        end
    end
    finish(ctx, sourceMod)
    return { pack = ctx.pack, errors = ctx.errors, warnings = ctx.warnings, lines = ctx.lines }
end

return Parse
