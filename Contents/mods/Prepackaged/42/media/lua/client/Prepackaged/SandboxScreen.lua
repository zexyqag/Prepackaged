-- The New Game sandbox screen: an Apply pack button that puts the pack's @sandbox values into the screen's settings, and
-- the preset Pack <id> in its list. SandboxOptionsScreen is a Lua global of the game, not an API, so each part used is
-- checked first.
require "ISUI/ISButton"
local Discovery = require "Prepackaged/Discovery"
local Enable = require "Prepackaged/Enable"
local Files = require "Prepackaged/Files"
local Rows = require "Prepackaged/Rows"
local Sandbox = require "Prepackaged/Sandbox"
local Version = require "Prepackaged/Version"
local Widgets = require "Prepackaged/UI/Widgets"

local UI_BORDER_SPACING = 10

local SandboxScreen = {}

local function optionsMissing()
    if type(SandboxOptions) ~= "table" or SandboxOptions.new == nil then
        return "SandboxOptions.new"
    end
end

local function presetsMissing()
    if getSandboxPresets == nil then
        return "getSandboxPresets"
    elseif deleteSandboxPreset == nil then
        return "deleteSandboxPreset"
    end
    return optionsMissing()
end

-- The screen's settings are copied to and from a SandboxOptions as the screen's own presets are
-- (SandboxOptions.lua:773-816, 865-870).
function SandboxScreen.missing(screen)
    local missing = optionsMissing()
    if missing ~= nil then
        return missing
    elseif type(SandboxOptionsScreen) ~= "table" then
        return "SandboxOptionsScreen"
    end
    for _, name in ipairs({ "settingsFromUI", "settingsToUI" }) do
        if type(SandboxOptionsScreen[name]) ~= "function" then
            return "SandboxOptionsScreen." .. name
        end
    end
    if screen == nil then
        return "MainScreen.sandOptions"
    elseif type(screen.presetPanel) ~= "table" then
        return "SandboxOptionsScreen.presetPanel"
    elseif type(screen.controls) ~= "table" then
        return "SandboxOptionsScreen.controls"
    end
end

local function screenOf()
    return MainScreen.instance and MainScreen.instance.sandOptions
end

-- The pack in use, with no errors, and whether its file is still at the version applied: a newer one waits for Update.
function SandboxScreen.current(state)
    local entry = Discovery.current(state)
    if entry == nil or #entry.result.errors > 0 or state.applied == nil then
        return nil
    end
    return entry, Version.compare(entry.result.pack.version, state.applied) == 0
end

-- The pack's values over the screen's: a line whose option isn't loaded, isn't valid for it, or has no control on this
-- screen, which Next would not carry into the world, is listed.
function SandboxScreen.apply(screen)
    local state = Files.loadState()
    local entry, applied = SandboxScreen.current(state)
    if entry == nil then
        return { error = "UI_Prepackaged_SandboxNoPack", args = {} }
    end
    local pack = entry.result.pack
    if not applied then
        return { error = "UI_Prepackaged_SandboxUpdate", args = { Rows.name(pack), pack.version, state.applied } }
    elseif #pack.sandbox == 0 then
        return { error = "UI_Prepackaged_SandboxNone", args = { Rows.name(pack) } }
    end
    local missing = SandboxScreen.missing(screen)
    if missing ~= nil then
        return { error = "UI_Prepackaged_SandboxFeature", args = { missing } }
    end
    local options = SandboxOptions.new()
    screen:settingsFromUI(options)
    local sorted = Sandbox.sort(pack.sandbox, function(e)
        local option = options:getOptionByName(e.name)
        if option == nil then
            return "missing"
        elseif not option:isValidString(e.value) then
            return "invalid"
        elseif screen.controls[e.name] == nil then
            return "hidden"
        end
        local before = option:getValueAsString()
        option:parse(e.value)
        return before == option:getValueAsString() and "same" or "changed"
    end)
    screen:settingsToUI(options)
    return { pack = pack, sorted = sorted }
end

local function onApply(screen)
    local ok, result = pcall(SandboxScreen.apply, screen)
    if not ok then
        result = { error = "UI_Prepackaged_SandboxFailed", args = { tostring(result) } }
    end
    if result.error ~= nil then
        Widgets.tell({ getText(result.error, unpack(result.args)) })
    else
        Widgets.tell(Widgets.lines(Rows.sandboxApplied(result)))
    end
end

-- After the game's own preset controls, which the panel is centred with (SandboxOptions.lua:433-484).
function SandboxScreen.add()
    local screen = screenOf()
    if screen == nil or screen.prepackagedButton ~= nil or SandboxScreen.missing(screen) ~= nil then
        return
    end
    local panel = screen.presetPanel
    local button = Widgets.button(panel, panel:getWidth() + UI_BORDER_SPACING, 0, { getText("UI_Prepackaged_SandboxApplyButton") }, function() onApply(screen) end)
    panel:setWidth(button:getRight())
    panel:setX((screen:getWidth() - panel:getWidth()) / 2)
    screen.prepackagedButton = button
end

local function listed(name)
    local presets = getSandboxPresets()
    for i = 0, presets:size() - 1 do
        if presets:get(i) == name then
            return true
        end
    end
    return false
end

local function values(options)
    local list = {}
    for i = 1, options:getNumOptions() do
        local option = options:getOptionByIndex(i - 1)
        list[i] = option:getName() .. "=" .. option:getValueAsString()
    end
    return list
end

-- Since Prepackaged wrote it, the player saved other values over it, or it was never Prepackaged's.
local function changed(record, name)
    if record == nil or #record.values == 0 then
        return true
    end
    local options = SandboxOptions.new()
    options:loadPresetFile(name)
    for _, e in ipairs(Sandbox.entries(record.values)) do
        local option = options:getOptionByName(e.name)
        if option ~= nil and option:getValueAsString() ~= e.value then
            return true
        end
    end
    return false
end

local function write(pack, name)
    local options = SandboxOptions.new()
    local sorted = Sandbox.sort(pack.sandbox, function(e)
        local option = options:getOptionByName(e.name)
        if option == nil then
            return "missing"
        elseif not option:isValidString(e.value) then
            return "invalid"
        end
        option:parse(e.value)
        return "set", option:getValueAsString()
    end)
    if not options:savePresetFile(name) then
        return nil
    end
    -- The game's preset files cut a value at a second = (ConfigFile.read), so each value is read back.
    local back = SandboxOptions.new()
    if not back:loadPresetFile(name) then
        return nil
    end
    for _, e in ipairs(sorted.set) do
        if back:getOptionByName(e.name):getValueAsString() ~= e.text then
            sorted.lost[#sorted.lost + 1] = e
        end
    end
    local skipped = {}
    for _, status in ipairs({ "missing", "invalid", "lost" }) do
        for _, e in ipairs(sorted[status]) do
            skipped[#skipped + 1] = { status = status, line = Sandbox.line(e) }
        end
    end
    return { version = pack.version, status = "written", values = values(back), skipped = skipped }
end

-- Once per pack version, while the pack's mods are loaded: a preset the player changed is left as it is, and one the
-- player deleted comes back with the next version. Without its record a preset would look like the player's, so it
-- goes again when the record can't be saved.
function SandboxScreen.ensurePreset()
    if presetsMissing() ~= nil then
        return
    end
    local entry, applied = SandboxScreen.current(Files.loadState())
    local pack = entry and entry.result.pack
    if not applied or #pack.sandbox == 0 then
        return
    end
    local path = Sandbox.recordPath(pack)
    local record = Sandbox.decodeRecord(Files.read(path) or {})
    if (record ~= nil and record.version == pack.version) or not Enable.loaded(pack.mods) then
        return
    end
    local name = Sandbox.presetName(pack)
    if listed(name) and changed(record, name) then
        Files.write(path, Sandbox.encodeRecord({ version = pack.version, status = "kept", values = record and record.values or {}, skipped = {} }))
        return
    end
    local new = write(pack, name)
    if new == nil then
        return
    elseif not Files.write(path, Sandbox.encodeRecord(new)) then
        deleteSandboxPreset(name)
        return
    end
    local screen = screenOf()
    if screen ~= nil and type(screen.loadPresets) == "function" then
        screen:loadPresets()
    end
end

-- For the pack's details: each line as the game loaded now takes it, and the preset of the pack in use.
function SandboxScreen.check(entry, state)
    local pack = entry.result.pack
    local current, applied = SandboxScreen.current(state)
    local info = { missing = SandboxScreen.missing(screenOf()), inUse = applied and current.result.pack.id == pack.id }
    if info.inUse then
        info.record = Sandbox.decodeRecord(Files.read(Sandbox.recordPath(pack)) or {})
    end
    if optionsMissing() == nil then
        local options = SandboxOptions.new()
        info.sorted = Sandbox.sort(pack.sandbox, function(e)
            local option = options:getOptionByName(e.name)
            if option == nil then
                return "missing"
            end
            return option:isValidString(e.value) and "set" or "invalid"
        end)
    end
    return info
end

return SandboxScreen
