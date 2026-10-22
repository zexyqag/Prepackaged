-- The pack's @sandbox lines: sorted by what the game makes of them, as Lua for a server's _SandboxVars.lua, the record of
-- the preset Pack <id>, and the changes between two versions.
local Text = require "Prepackaged/Text"

local Sandbox = {}

Sandbox.RECORDS = "Prepackaged/presets"
Sandbox.STATUSES = { "changed", "same", "set", "hidden", "missing", "invalid", "lost" }

local KEYWORDS = {}
for _, word in ipairs({ "and", "break", "do", "else", "elseif", "end", "false", "for", "function", "if", "in", "local", "nil", "not",
    "or", "repeat", "return", "then", "true", "until", "while" }) do
    KEYWORDS[word] = true
end

-- Preset names may not hold / \ : ; " . (SandboxOptions.isValidPresetName), and a pack id never does.
function Sandbox.presetName(pack)
    return "Pack " .. pack.id
end

function Sandbox.recordPath(pack)
    return Sandbox.RECORDS .. "/" .. pack.id .. ".txt"
end

function Sandbox.line(entry)
    return entry.name .. "=" .. entry.value
end

-- look(entry) gives the entry's status, one of STATUSES, and the value as the game holds it.
function Sandbox.sort(entries, look)
    local sorted = {}
    for _, status in ipairs(Sandbox.STATUSES) do
        sorted[status] = {}
    end
    for _, entry in ipairs(entries) do
        local status, text = look(entry)
        local list = sorted[status]
        list[#list + 1] = { name = entry.name, value = entry.value, line = entry.line, text = text }
    end
    return sorted
end

-- Name=value as the server .ini holds it, the lines after the first = kept whole.
function Sandbox.entries(lines)
    local list = {}
    for _, line in ipairs(lines) do
        local i = string.find(line, "=", 1, true)
        if i ~= nil and i > 1 then
            list[#list + 1] = { name = string.sub(line, 1, i - 1), value = string.sub(line, i + 1) }
        end
    end
    return list
end

-- What the game's escapes need, and every other control character as \ddd, which Lua 5.1 and Kahlua both read.
local function quote(text)
    if string.find(text, "[^ -~]") == nil then
        return '"' .. string.gsub(text, '["\\]', "\\%0") .. '"'
    end
    local parts = {}
    for i = 1, #text do
        local c = string.sub(text, i, i)
        local b = string.byte(c)
        if c == '"' or c == "\\" then
            parts[i] = "\\" .. c
        elseif b < 32 or b == 127 then
            parts[i] = string.format("\\%03d", b)
        else
            parts[i] = c
        end
    end
    return '"' .. table.concat(parts) .. '"'
end
Sandbox.quote = quote

-- Number literals as Java's Double.toString and Integer.toString write them, which Lua reads as numbers.
local function isNumber(text)
    return string.match(text, "^%-?[0-9]+%.?[0-9]*$") ~= nil or string.match(text, "^%-?[0-9]+%.?[0-9]*[eE][%-+]?[0-9]+$") ~= nil
end

-- As the game writes a value of this type (ConfigOption.getValueAsLuaString). A string, or a value whose type isn't
-- known, is written as text, which every type reads (setValueFromObject); a number in a text option would come back
-- as "20.0".
local function value(entry)
    local kind, text = entry.type, entry.text
    if kind == "boolean" and (text == "true" or text == "false") then
        return text
    elseif (kind == "integer" or kind == "enum" or kind == "double") and isNumber(text) then
        return text
    end
    return quote(text)
end

local function field(name)
    if KEYWORDS[name] then
        return '["' .. name .. '"]'
    end
    return "." .. name
end

local function groupOf(name)
    local dot = string.find(name, ".", 1, true)
    return dot and string.sub(name, 1, dot - 1), dot
end

-- Appended after the game's SandboxVars = { ... }: in a file the server never wrote the first line fails, so the server
-- stops instead of upgrading the values as version 0. The server rewrites the file, so a line that would replace one of
-- its groups, or fail and drop the lines after it, is left out. names: the game's options loaded here.
function Sandbox.lua(entries, names)
    local plain, groups = {}, {}
    for _, name in ipairs(names or {}) do
        local group = groupOf(name)
        if group ~= nil then
            groups[group] = true
        else
            plain[name] = true
        end
    end
    local function clash(name)
        local group = groupOf(name)
        if group == "VERSION" then
            return "Version"
        elseif group ~= nil and plain[group] then
            return "Value"
        elseif group == nil and groups[name] then
            return "Group"
        end
    end
    local packGroups = {}
    for _, e in ipairs(entries) do
        local group = groupOf(e.name)
        if group ~= nil and clash(e.name) == nil then
            packGroups[group] = true
        end
    end
    local lines, made, left = {}, {}, {}
    for _, e in ipairs(entries) do
        local group, dot = groupOf(e.name)
        local reason = clash(e.name) or (group == nil and packGroups[e.name] and "Group") or nil
        if reason ~= nil then
            left[#left + 1] = { entry = e, reason = reason }
        else
            local target = "SandboxVars" .. field(e.name)
            if group ~= nil then
                local parent = "SandboxVars" .. field(group)
                if not made[group] then
                    made[group] = true
                    lines[#lines + 1] = parent .. " = " .. parent .. " or {}"
                end
                target = parent .. field(string.sub(e.name, dot + 1))
            end
            lines[#lines + 1] = target .. " = " .. value(e)
        end
    end
    return lines, left
end

-- The server .ini lines the pack sets. Map only when the pack has one: the server keeps its own otherwise.
function Sandbox.ini(pack)
    local lines = { "WorkshopItems=" .. table.concat(pack.workshopItems, ";"), "Mods=" .. table.concat(pack.mods, ";") }
    if pack.map ~= nil then
        lines[#lines + 1] = "Map=" .. pack.map
    end
    return lines
end

-- Pack lines since the version in use: changed, added and no longer set, each in its pack's order.
function Sandbox.diff(old, new)
    local before, now = {}, {}
    for _, e in ipairs(Sandbox.entries(old)) do
        before[e.name] = e.value
    end
    local diff = { changed = {}, added = {}, removed = {} }
    for _, e in ipairs(new) do
        now[e.name] = true
        local from = before[e.name]
        if from == nil then
            diff.added[#diff.added + 1] = { name = e.name, to = e.value }
        elseif from ~= e.value then
            diff.changed[#diff.changed + 1] = { name = e.name, from = from, to = e.value }
        end
    end
    for _, e in ipairs(Sandbox.entries(old)) do
        if not now[e.name] then
            diff.removed[#diff.removed + 1] = { name = e.name, from = e.value }
        end
    end
    return diff
end

-- The preset Pack <id> as Prepackaged last wrote it: the version, written or kept (the player's own), each option as the
-- preset file reads back, and the pack lines it couldn't use.
function Sandbox.encodeRecord(record)
    local lines = { "preset|" .. record.version .. "|" .. record.status }
    for _, line in ipairs(record.values) do
        lines[#lines + 1] = "value|" .. line
    end
    for _, s in ipairs(record.skipped) do
        lines[#lines + 1] = "skip|" .. s.status .. "|" .. s.line
    end
    return lines
end

local SKIPPED = { hidden = true, missing = true, invalid = true, lost = true }

function Sandbox.decodeRecord(lines)
    local record = { values = {}, skipped = {} }
    for _, line in ipairs(lines) do
        local f = Text.split(line, "|")
        if f[1] == "preset" and #f == 3 and f[2] ~= "" and (f[3] == "written" or f[3] == "kept") then
            record.version, record.status = f[2], f[3]
        elseif f[1] == "value" and #f >= 2 then
            record.values[#record.values + 1] = Text.after(line, 1)
        elseif f[1] == "skip" and #f >= 3 and SKIPPED[f[2]] then
            record.skipped[#record.skipped + 1] = { status = f[2], line = Text.after(line, 2) }
        end
    end
    if record.version == nil then
        return nil
    end
    return record
end

return Sandbox
