-- The game's key binds and mod options: read for the defaults review, backed up, written the way the options screen
-- writes them, and restored.
local Backup = require "Prepackaged/Backup"
local Defaults = require "Prepackaged/Defaults"
local Files = require "Prepackaged/Files"
local Parse = require "Prepackaged/Parse"
local Rows = require "Prepackaged/Rows"
local Shipped = require "Prepackaged/Shipped"
local State = require "Prepackaged/State"
local Text = require "Prepackaged/Text"

local Settings = {}

Settings.KEYS = "keysB42.ini"
Settings.OPTIONS = "ModOptions.ini"
local TYPES = { tickbox = true, textentry = true, slider = true, combobox = true, multipletickbox = true, colorpicker = true, keybind = true }

local function modOptions()
    return type(PZAPI) == "table" and type(PZAPI.ModOptions) == "table" and PZAPI.ModOptions or nil
end

-- A copy of what an option holds now (ModOptions.lua:40-204).
local function valueOf(option)
    local kind = option.type
    if kind == "combobox" then
        return option.selected
    elseif kind == "keybind" then
        return option.key
    elseif kind == "colorpicker" then
        local c = option.color
        return c and { r = c.r, g = c.g, b = c.b, a = c.a }
    elseif kind == "multipletickbox" then
        local list = {}
        for i, v in ipairs(option.values) do
            list[i] = v.value
        end
        return list
    end
    return option.value
end

-- The pages ModOptions.ini is read into: a page made again under the same id replaces the first in Dict.
local function pages(mo)
    local list = {}
    for _, page in ipairs(mo.Data) do
        if type(page) == "table" and page.modOptionsID ~= nil and mo.Dict[page.modOptionsID] == page and type(page.data) == "table" and type(page.dict) == "table" then
            list[#list + 1] = page
        end
    end
    return list
end

-- A mod option's default is what it holds before ModOptions.ini is first loaded into it. Mods make their options
-- when their Lua loads, and the first load comes when the main menu builds the options screen. An option made after
-- every load doesn't hold the player's value: its line is still in OtherOptions, and a save writes both.
local defaults = {}
local function snapshot()
    for _, page in ipairs(pages(PZAPI.ModOptions)) do
        for _, option in ipairs(page.data) do
            if type(option) == "table" and TYPES[option.type] and defaults[option] == nil then
                defaults[option] = { value = valueOf(option) }
            end
        end
    end
end

do
    local mo = modOptions()
    if mo ~= nil and type(mo.load) == "function" and type(mo.Data) == "table" and type(mo.Dict) == "table" then
        local load = mo.load
        mo.load = function(...)
            pcall(snapshot)
            return load(...)
        end
    end
end

-- MainOptions is a Lua global of the options screen, not an API: each part used is checked first.
local function bindsMissing()
    if type(keyBinding) ~= "table" then
        return "keyBinding"
    elseif type(MainOptions) ~= "table" then
        return "MainOptions"
    end
    for _, field in ipairs({ "keys", "keyText" }) do
        if type(MainOptions[field]) ~= "table" then
            return "MainOptions." .. field
        end
    end
    if type(MainOptions.saveKeys) ~= "function" then
        return "MainOptions.saveKeys"
    end
end

local function optionsMissing()
    local mo = modOptions()
    if mo == nil then
        return "PZAPI.ModOptions"
    end
    for _, field in ipairs({ "Data", "Dict", "OtherOptions" }) do
        if type(mo[field]) ~= "table" then
            return "PZAPI.ModOptions." .. field
        end
    end
    if type(mo.save) ~= "function" then
        return "PZAPI.ModOptions.save"
    end
end

local function title(key, fallback)
    return type(key) == "string" and getTextOrNull(key) or fallback
end

local function flag(value)
    return value and true or false
end

-- Each bind as the options screen holds it: MainOptions.keyText is what Apply saves, MainOptions.keys what the screen
-- was built from (MainOptions.lua:2161-2199, 3706-3742).
local function readBinds(targets)
    local missing = bindsMissing()
    if missing ~= nil then
        targets.missing.binds = missing
        return
    end
    local keys, texts = {}, {}
    for _, k in ipairs(MainOptions.keys) do
        if type(k) == "table" and k.value ~= nil then
            keys[k.value] = k
        end
    end
    for _, t in ipairs(MainOptions.keyText) do
        if type(t) == "table" and t.value == nil and not t.isModBind and type(t.txt) == "table" and type(t.txt.getName) == "function" and type(t.keyCode) == "number" then
            texts[t.txt:getName()] = t
        end
    end
    -- Binds but none in a shape known here: the options screen has changed.
    if next(texts) == nil and #MainOptions.keys > 0 then
        targets.missing.binds = "MainOptions.keyText"
        return
    end
    local azerty = getCore():isAzerty()
    local group = { title = getText("UI_Prepackaged_DefaultsOtherKeys") }
    for _, entry in ipairs(keyBinding) do
        local name = type(entry) == "table" and entry.value
        if type(name) == "string" and string.sub(name, 1, 1) == "[" then
            local category = string.gsub(string.gsub(name, "%[", ""), "%]", "")
            group = { title = title("UI_optionscreen_binding_" .. category, category) }
        elseif type(name) == "string" and keys[name] ~= nil and texts[name] ~= nil and targets.binds[name] == nil then
            local t = texts[name]
            targets.n = targets.n + 1
            local target = {
                kind = "bind", name = name, title = title("UI_optionscreen_binding_" .. name, name), group = group, order = targets.n,
                default = Defaults.keyDefault(entry, azerty), keys = keys[name], text = t,
                current = { key = tonumber(t.keyCode) or 0, altCode = tonumber(t.altCode) or 0, shift = flag(t.shift), ctrl = flag(t.ctrl), alt = flag(t.alt) },
            }
            if Shipped[name] ~= nil then
                target.shipped = Defaults.keyDefault(Shipped[name], azerty)
            end
            targets.binds[name] = target
            targets.bindList[#targets.bindList + 1] = target
        end
    end
end

local function enabled(option)
    if option.type == "multipletickbox" then
        for _, v in ipairs(option.values) do
            if v.isEnabled == false then
                return false
            end
        end
        return true
    end
    return option.isEnabled ~= false
end

local function readOptions(targets)
    local missing = optionsMissing()
    if missing ~= nil then
        targets.missing.options = missing
        return
    end
    for _, page in ipairs(pages(PZAPI.ModOptions)) do
        local id = page.modOptionsID
        local group = { title = title(page.name, tostring(page.name or id)) }
        targets.pages[id] = group
        for _, option in ipairs(page.data) do
            -- The file is loaded into the option the page's dict holds (ModOptions.lua:305).
            local key = type(option) == "table" and TYPES[option.type] and option.id ~= nil and page.dict[option.id] == option and id .. "|" .. option.id
            if key and defaults[option] == nil then
                targets.unread[key] = true
            elseif key and targets.options[key] == nil then
                targets.n = targets.n + 1
                local target = {
                    kind = "opt", type = option.type, page = id, option = option.id, group = group, pageTitle = group.title,
                    title = title(option.name, tostring(option.name or option.id)), order = targets.n,
                    current = valueOf(option), enabled = enabled(option), game = option, pageObject = page,
                }
                if option.type == "keybind" then
                    target.default = option.defaultkey
                    targets.keyOptions[#targets.keyOptions + 1] = target
                else
                    target.default = defaults[option].value
                end
                if option.type == "combobox" then
                    target.labels, target.count = option.values, #option.values
                elseif option.type == "multipletickbox" then
                    target.names, target.count = {}, #option.values
                    for i, v in ipairs(option.values) do
                        target.names[i] = title(v.name, tostring(v.name))
                    end
                elseif option.type == "slider" then
                    target.min, target.max = option.min, option.max
                end
                targets.options[key] = target
            end
        end
    end
end

function Settings.read()
    local targets = { binds = {}, bindList = {}, options = {}, keyOptions = {}, pages = {}, unread = {}, missing = {}, n = 0 }
    readBinds(targets)
    readOptions(targets)
    return targets
end

-- KEY_ names as the game gives them to Lua (LuaManager.exposeKeyboardKeys).
function Settings.resolve(name)
    local value = type(Keyboard) == "table" and Keyboard[name] or nil
    return type(value) == "number" and value or nil
end

-- Defaults belong to the pack in use, at the version applied: a newer pack file waits for Update.
function Settings.applies(entry, state)
    if entry == nil or #entry.result.errors > 0 then
        return false
    end
    local pack = entry.result.pack
    return pack.id == state.current and pack.version == state.applied and #pack.keys + #pack.modoptions > 0
end

function Settings.review(entry, state, all)
    local pack = entry.result.pack
    local targets = Settings.read()
    local review = Defaults.review({
        pack = pack, targets = targets, all = all, resolve = Settings.resolve,
        record = function(kind, key) return State.decision(state, kind, pack.id, key) end,
    })
    return review, targets
end

-- How many entries wait for the player's decision.
function Settings.waiting(entry, state)
    if not Settings.applies(entry, state) then
        return 0
    end
    return #Settings.review(entry, state, false).rows
end

-- For the pack's details: every entry, judged as if nothing had been decided.
function Settings.check(entry)
    local pack = entry.result.pack
    if #pack.keys + #pack.modoptions == 0 then
        return nil
    end
    local review = Defaults.review({ pack = pack, targets = Settings.read(), all = true, resolve = Settings.resolve, record = function() return nil end })
    return { keys = #pack.keys, options = #pack.modoptions, review = review }
end

local function keyName(code)
    if code == 0 then
        return getText("UI_Prepackaged_KeyNone")
    elseif type(code) ~= "number" then
        return tostring(code)
    end
    return getKeyName(code)
end

local function onOff(value)
    return getText(value and "UI_Prepackaged_On" or "UI_Prepackaged_Off")
end

function Settings.show(target, value)
    if value == nil then
        return getText("UI_Prepackaged_NoValue")
    end
    local kind = target.kind == "bind" and "bind" or target.type
    if kind == "bind" then
        local text = keyName(value.key)
        if value.alt then
            text = getText("UI_Prepackaged_KeyAlt", text)
        end
        if value.ctrl then
            text = getText("UI_Prepackaged_KeyCtrl", text)
        end
        if value.shift then
            text = getText("UI_Prepackaged_KeyShift", text)
        end
        if value.altCode ~= 0 then
            text = getText("UI_Prepackaged_KeyOr", text, keyName(value.altCode))
        end
        return text
    elseif kind == "keybind" then
        return keyName(value)
    elseif kind == "tickbox" then
        return onOff(value)
    elseif kind == "combobox" then
        return target.labels[value] or tostring(value)
    elseif kind == "multipletickbox" then
        local parts = {}
        for i, v in ipairs(value) do
            parts[i] = getText("UI_Prepackaged_Tick", target.names[i] or tostring(i), onOff(v))
        end
        return table.concat(parts, ", ")
    elseif kind == "colorpicker" then
        return tostring(value.r) .. " " .. tostring(value.g) .. " " .. tostring(value.b) .. " " .. tostring(value.a)
    elseif kind == "textentry" then
        return getText("UI_Prepackaged_Quoted", value)
    end
    return tostring(value)
end

function Settings.names(pack)
    return { pack = Rows.name(pack), version = pack.version, value = Settings.show, key = keyName }
end

-- MainOptions.loadKeys reads keys.ini while there is no keysB42.ini (MainOptions.lua:3520-3525).
local function keysSource()
    if cacheFileExists("keys.ini") and not cacheFileExists(Settings.KEYS) then
        return "keys.ini"
    end
    return Settings.KEYS
end

local function failed(key, ...)
    return { error = key, args = { ... } }
end

-- Both files as the game reads them now, in the next backup, read back.
local function backUp(before)
    local backup = {
        n = Backup.next(Files.fileBackups()), date = os.date(Backup.DATE), before = before,
        keys = Files.read(keysSource()) or {}, options = Files.read(Settings.OPTIONS) or {},
    }
    if not Files.saveFileBackup(backup) then
        return nil, Backup.path(Backup.FILES, backup.n)
    end
    return backup
end

local function backUpOrFail(before)
    local ok, backup, path = pcall(backUp, before)
    if ok and backup ~= nil then
        return backup
    end
    return nil, failed("UI_Prepackaged_FailFilesBackup", ok and path or Backup.FILES)
end

-- As the options screen applies a change: the mod hears of it first, keybinds excepted (MainOptions.lua:2819-3046).
local function setOption(option, value)
    if option.type == "multipletickbox" then
        for i, v in ipairs(value) do
            if option.values[i].value ~= v then
                if option.onChangeApply then
                    option:onChangeApply(i, v)
                end
                option:setValue(i, v)
            end
        end
        return
    end
    if option.type == "colorpicker" then
        value = { r = value.r, g = value.g, b = value.b, a = value.a }
    end
    if option.type ~= "keybind" and option.onChangeApply then
        option:onChangeApply(value)
    end
    option:setValue(value)
    -- setValue sets the key the options screen saves, not its button's title (ModOptions.lua:192-197).
    local element = option.element
    if option.type == "keybind" and element ~= nil and element.btn ~= nil then
        element.btn:setTitle(getKeyName(value))
    end
end

local function setBind(target, bind)
    local k, t = target.keys, target.text
    k.key, k.altCode, k.shift, k.ctrl, k.alt = bind.key, bind.altCode, bind.shift, bind.ctrl, bind.alt
    t.keyCode, t.altCode, t.shift, t.ctrl, t.alt = bind.key, bind.altCode, bind.shift, bind.ctrl, bind.alt
    if t.btn ~= nil and type(MainOptions.getKeyPrefix) == "function" then
        t.btn:setTitle(MainOptions.getKeyPrefix(t) .. getKeyName(bind.key))
    end
    getCore():addKeyBinding(target.name, bind.key, bind.altCode, bind.shift, bind.ctrl, bind.alt)
end

-- PZAPI.ModOptions:save writes the lines of mods that aren't loaded without a line break (ModOptions.lua:286-288).
-- Each line gets exactly one, so a mod that fixes the same bug adds at most empty lines, which this drops again.
local function guard(lines)
    local kept = {}
    for _, line in ipairs(lines) do
        local stop = #line
        while stop > 0 and (string.byte(line, stop) == 10 or string.byte(line, stop) == 13) do
            stop = stop - 1
        end
        if stop > 0 then
            kept[#kept + 1] = string.sub(line, 1, stop) .. "\r\n"
        end
    end
    for i = 1, math.max(#lines, #kept) do
        lines[i] = kept[i]
    end
end

local function bindName(line)
    local i = string.find(line, "=", 1, true)
    if i ~= nil then
        return string.sub(line, 1, i - 1), string.sub(line, i + 1)
    end
end

-- The game's writers empty the file first: when one stops part way, the file is written back from the backup.
local function save(path, before, writer, ...)
    if pcall(writer, ...) then
        return true
    end
    Files.write(path, before, "\r\n")
    return false
end

-- saveKeys writes only the binds of mods that are loaded (MainOptions.lua:3706-3714). The lines of the others go back
-- after them, so a mod enabled again still finds the player's binds.
local function keepOthers(before)
    local lines, written = Files.read(Settings.KEYS) or {}, {}
    local count = #lines
    for _, line in ipairs(lines) do
        local name = bindName(line)
        if name ~= nil then
            written[name] = true
        end
    end
    for _, line in ipairs(before) do
        local name = bindName(line)
        if name ~= nil and not written[name] then
            lines[#lines + 1] = line
        end
    end
    if #lines > count then
        Files.write(Settings.KEYS, lines, "\r\n")
    end
end

local function savedBinds()
    local saved = {}
    for _, line in ipairs(Files.read(Settings.KEYS) or {}) do
        local name, spec = bindName(line)
        if name ~= nil then
            saved[name] = Parse.bindSpec(spec)
        end
    end
    return saved
end

local function savedOptions()
    local saved = {}
    for _, line in ipairs(Files.read(Settings.OPTIONS) or {}) do
        local f = Text.split(line, "|")
        if #f >= 4 then
            saved[f[2] .. "|" .. f[3]] = { type = f[1], text = Text.after(line, 3) }
        end
    end
    return saved
end

local function readsBack(item, binds, options)
    if item.kind == "bind" then
        local bind = binds[item.target.name]
        return bind ~= nil and Defaults.same("bind", bind, item.to)
    end
    local saved = options[item.key]
    return saved ~= nil and saved.type == item.type and Defaults.same(item.type, Parse.optionValue(item.type, saved.text), item.to)
end

-- Mod options first: their key binds sit in MainOptions.keyText too, which saveKeys writes into keysB42.ini.
local function write(binds, options, backup)
    local done, touched, order = {}, {}, {}
    for _, item in ipairs(options) do
        if pcall(setOption, item.target.game, item.to) then
            done[#done + 1] = item
            local page = item.target.pageObject
            if not touched[page] then
                touched[page], order[#order + 1] = true, page
            end
        end
    end
    for _, page in ipairs(order) do
        pcall(page.apply, page)
    end
    for _, item in ipairs(binds) do
        if pcall(setBind, item.target, item.to) then
            done[#done + 1] = item
        end
    end
    if #binds > 0 and save(Settings.KEYS, backup.keys, MainOptions.saveKeys) then
        keepOthers(backup.keys)
    end
    if #options > 0 then
        local mo = PZAPI.ModOptions
        guard(mo.OtherOptions)
        save(Settings.OPTIONS, backup.options, mo.save, mo)
    end
    local savedB, savedO = savedBinds(), savedOptions()
    local written, count = {}, 0
    for _, item in ipairs(done) do
        if readsBack(item, savedB, savedO) then
            written[item], count = true, count + 1
        end
    end
    return written, #binds + #options - count
end

-- Backs up both files, writes the ticked rows and reads the files back: only what reads back counts as applied. The
-- ledger takes every decision.
function Settings.apply(entry, state, review, ticks)
    if state.newer then
        return failed("UI_Prepackaged_FailNewer", State.FILE)
    end
    local pack = entry.result.pack
    local binds, options = {}, {}
    for _, item in ipairs(review.rows) do
        if ticks[item] then
            local list = item.kind == "bind" and binds or options
            list[#list + 1] = item
        end
    end
    local written, lost, backup = {}, 0, nil
    if #binds + #options > 0 then
        local problem
        backup, problem = backUpOrFail({ kind = "defaults", id = pack.id, version = pack.version })
        if backup == nil then
            return problem
        end
        written, lost = write(binds, options, backup)
    end
    for _, record in ipairs(Defaults.records(pack.id, review, ticks, written)) do
        State.decide(state, record)
    end
    if not Files.saveState(state) then
        return failed("UI_Prepackaged_FailDefaultsState", State.FILE)
    end
    if lost > 0 then
        return failed("UI_Prepackaged_FailDefaultsWrite", lost, backup.n)
    end
    return { changed = #binds + #options, backup = backup and backup.n }
end

-- The ledger stays as it is: restored values count as the player's.
function Settings.restore(backup)
    local current, problem = backUpOrFail({ kind = "restore", n = backup.n })
    if current == nil then
        return problem
    end
    if not Files.write(Settings.KEYS, backup.keys, "\r\n") then
        return failed("UI_Prepackaged_FailRestoreFile", Settings.KEYS, current.n)
    end
    if not Files.write(Settings.OPTIONS, backup.options, "\r\n") then
        return failed("UI_Prepackaged_FailRestoreFile", Settings.OPTIONS, current.n)
    end
    getCore():ResetLua("default", Backup.RESET_REASON)
    return { reloaded = true }
end

return Settings
