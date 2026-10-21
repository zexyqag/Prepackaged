-- Writes a parsed pack out as server lines, a SandboxVars block, Mod Options Control rules and a pack file. Pure.
local Serialise = {}

-- A Lua string literal. Control characters become three-digit escapes, so a digit after one can't join it.
local function quote(text)
    return '"' .. string.gsub(text, '[%c"\\]', function(c)
        if c == '"' or c == "\\" then
            return "\\" .. c
        end
        local code = tostring(string.byte(c))
        return "\\" .. string.rep("0", 3 - #code) .. code
    end) .. '"'
end

local function words(text)
    local list = {}
    for word in string.gmatch(text, "[^ ]+") do
        list[#list + 1] = word
    end
    return list
end

-- Lines for Zomboid/Server/<server>.ini.
function Serialise.serverLines(pack)
    local lines = {
        "WorkshopItems=" .. table.concat(pack.workshopItems, ";"),
        "Mods=" .. table.concat(pack.mods, ";"),
    }
    if pack.map ~= nil then
        lines[#lines + 1] = "Map=" .. pack.map
    end
    return lines
end

-- Lines to append to <server>_SandboxVars.lua. Every value is a string: the game parses a string into any option
-- type when it reads the file, while a number given to a string option would come back as "20.0".
function Serialise.sandboxLines(pack)
    local lines, tables = {}, {}
    for _, entry in ipairs(pack.sandbox) do
        local name = string.match(entry.name, "^([^.]+)%.")
        if name ~= nil and not tables[name] then
            tables[name] = true
            lines[#lines + 1] = "SandboxVars." .. name .. " = SandboxVars." .. name .. " or {}"
        end
        lines[#lines + 1] = "SandboxVars." .. entry.name .. " = " .. quote(entry.value)
    end
    return lines
end

-- A Lua value in the shape Mod Options Control stores for the option type; nil for a key name keyCode can't resolve.
local function literal(entry, keyCode)
    local kind, value = entry.type, entry.value
    if kind == "tickbox" or kind == "combobox" then
        return tostring(value)
    elseif kind == "slider" then
        return entry.text
    elseif kind == "textentry" then
        return quote(value)
    elseif kind == "multipletickbox" then
        local parts = {}
        for i, tick in ipairs(value) do
            parts[i] = tostring(tick)
        end
        return "{ " .. table.concat(parts, ", ") .. " }"
    elseif kind == "colorpicker" then
        local t = words(entry.text)
        return "{ r = " .. t[1] .. ", g = " .. t[2] .. ", b = " .. t[3] .. ", a = " .. t[4] .. " }"
    elseif type(value) == "number" then
        return tostring(value)
    end
    local code = keyCode(value)
    if code ~= nil then
        return tostring(code)
    end
end

-- Zomboid/Lua/ModOptionsControl_rules.txt for Mod Options Control's Import. Each @locks entry is locked; options with a
-- pack value carry it, on a locked page all of them, since a locked option without a value gets the mod's default.
-- keyCode(name) turns a KEY_ name into its number. Returns the lines and notes for values left out.
function Serialise.mocRules(pack, keyCode)
    local pages, order = {}, {}
    local function page(id)
        if pages[id] == nil then
            pages[id] = { opts = {}, order = {} }
            order[#order + 1] = id
        end
        return pages[id]
    end
    local function option(p, id)
        if p.opts[id] == nil then
            p.opts[id] = {}
            p.order[#p.order + 1] = id
        end
        return p.opts[id]
    end
    for _, lock in ipairs(pack.locks) do
        local p = page(lock.page)
        if lock.option == nil then
            p.lock = true
        else
            option(p, lock.option).lock = true
        end
    end
    for _, entry in ipairs(pack.modoptions) do
        local p = pages[entry.page]
        if p ~= nil and (p.lock or p.opts[entry.option] ~= nil) then
            option(p, entry.option).entry = entry
        end
    end
    local lines, notes = { "return {" }, {}
    for _, id in ipairs(order) do
        local p = pages[id]
        lines[#lines + 1] = "    [" .. quote(id) .. "] = {"
        if p.lock then
            lines[#lines + 1] = "        lock = true,"
        end
        lines[#lines + 1] = "        opts = {"
        for _, optionId in ipairs(p.order) do
            local o = p.opts[optionId]
            local fields = {}
            if o.lock then
                fields[#fields + 1] = "lock = true"
            end
            if o.entry ~= nil then
                local value = literal(o.entry, keyCode)
                if value == nil then
                    notes[#notes + 1] = { line = o.entry.line, code = "UnknownKeyName", args = { o.entry.text } }
                else
                    fields[#fields + 1] = "value = " .. value
                end
            end
            if #fields > 0 then
                lines[#lines + 1] = "            [" .. quote(optionId) .. "] = { " .. table.concat(fields, ", ") .. " },"
            end
        end
        lines[#lines + 1] = "        },"
        lines[#lines + 1] = "    },"
    end
    lines[#lines + 1] = "}"
    return lines, notes
end

local function keyText(bind)
    local text = bind.name .. "=key:" .. tostring(bind.key)
    if bind.altCode ~= 0 then
        text = text .. ";altCode:" .. tostring(bind.altCode)
    end
    for _, flag in ipairs({ "shift", "ctrl", "alt" }) do
        if bind[flag] then
            text = text .. ";" .. flag .. ":true"
        end
    end
    return text
end

local function collectionText(entry)
    local items = {}
    for _, child in ipairs(entry.children) do
        items[#items + 1] = "c:" .. child
    end
    for _, item in ipairs(entry.items) do
        items[#items + 1] = item
    end
    return entry.id .. " = " .. entry.title .. " | " .. table.concat(items, ";")
end

local SECTIONS = {
    { "optional", function(e) return e.label and (e.id .. " = " .. e.label) or e.id end },
    { "collections", collectionText },
    { "keys", keyText },
    { "modoptions", function(e) return e.type .. "|" .. e.page .. "|" .. e.option .. "|" .. e.text end },
    { "sandbox", function(e) return e.name .. "=" .. e.value end },
    { "locks", function(e) return e.option and (e.page .. "." .. e.option) or e.page end },
}

-- A pack file that reads back to the same pack.
function Serialise.pack(pack)
    local lines = { "# Prepackaged pack file", "@pack" }
    local function put(key, value)
        lines[#lines + 1] = key .. " = " .. value
    end
    put("id", pack.id)
    if pack.name ~= nil then
        put("name", pack.name)
    end
    put("version", tostring(pack.version))
    if #pack.collection > 0 then
        put("collection", table.concat(pack.collection, ";"))
    end
    put("WorkshopItems", table.concat(pack.workshopItems, ";"))
    put("Mods", table.concat(pack.mods, ";"))
    if pack.map ~= nil then
        put("Map", pack.map)
    end
    if #pack.needs > 0 then
        put("needs", table.concat(pack.needs, ";"))
    end
    if pack.heap ~= nil then
        put("heap", tostring(pack.heap))
    end
    if pack.hostmemory ~= nil then
        put("hostmemory", tostring(pack.hostmemory))
    end
    for _, section in ipairs(SECTIONS) do
        local entries = pack[section[1]]
        if #entries > 0 then
            lines[#lines + 1] = ""
            lines[#lines + 1] = "@" .. section[1]
            for _, entry in ipairs(entries) do
                lines[#lines + 1] = section[2](entry)
            end
        end
    end
    return lines
end

return Serialise
