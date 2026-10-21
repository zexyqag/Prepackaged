-- Puts a pack's mod list in place, after saving the list in use as a Mods screen preset.
local Discovery = require "Prepackaged/Discovery"
local Files = require "Prepackaged/Files"
local ModList = require "Prepackaged/ModList"
local State = require "Prepackaged/State"

local Enable = {}

Enable.RESET_REASON = "PrepackagedMods"

function Enable.status(id)
    local info = getModInfoByID(id)
    if info == nil then
        return "missing"
    elseif not info:isAvailable() then
        return "unavailable"
    end
    return "ok"
end

function Enable.nameOf(id)
    local info = getModInfoByID(id)
    return info and info:getName()
end

-- The Mods screen's list, in load order.
function Enable.active()
    local mods = ActiveMods.getById("default"):getMods()
    local list = {}
    for i = 0, mods:size() - 1 do
        list[#list + 1] = mods:get(i)
    end
    return list
end

function Enable.backupName(pack)
    return ModList.presetName(getText("UI_Prepackaged_BackupPreset", pack.id))
end

function Enable.plan(entry, state, ticks)
    return ModList.plan({
        pack = entry.result.pack, active = Enable.active(), state = state, ticks = ticks, status = Enable.status,
    })
end

-- Saves the state and the mods file as the Mods screen does, then reloads Lua when the loaded mods differ.
-- Returns whether it reloaded, which ends this Lua state.
function Enable.apply(entry, plan, state)
    local pack = entry.result.pack
    if entry.source == "clipboard" then
        entry = Discovery.keep(entry)
    end
    if plan.changed and #plan.active > 0 then
        local preset = Enable.backupName(pack)
        Files.savePreset(preset, plan.active)
        State.addBackup(state, preset, plan.active)
    end
    State.record(state, pack, { kind = entry.source, name = entry.name }, plan.fromPack)
    Files.saveState(state)
    local default = ActiveMods.getById("default")
    local mods = default:getMods()
    mods:clear()
    for _, id in ipairs(plan.mods) do
        mods:add(id)
    end
    saveModsFile()
    ActiveMods.getById("currentGame"):copyFrom(default)
    if ActiveMods.requiresResetLua(default) then
        getCore():ResetLua("default", Enable.RESET_REASON)
        return true
    end
    return false
end

return Enable
