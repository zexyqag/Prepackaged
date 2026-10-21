local Backup = require "Prepackaged/Backup"
local Discovery = require "Prepackaged/Discovery"
local Files = require "Prepackaged/Files"
local ModList = require "Prepackaged/ModList"
local State = require "Prepackaged/State"
local Text = require "Prepackaged/Text"

local Enable = {}

Enable.RESET_REASON = "PrepackagedMods"
local DATE = "%Y-%m-%d %H:%M"

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

-- require= is split at commas only (ChooseGameInfo.java:225), so "\A, \B" leaves a space.
function Enable.requires(id)
    local info = getModInfoByID(id)
    local list = info and info:getRequire()
    local result = {}
    for i = 0, (list and list:size() or 0) - 1 do
        local need = Text.trim(list:get(i))
        if need ~= "" then
            result[#result + 1] = need
        end
    end
    return result
end

local function items(list)
    local result = {}
    for i = 0, list:size() - 1 do
        result[#result + 1] = list:get(i)
    end
    return result
end

function Enable.active()
    return items(ActiveMods.getById("default"):getMods())
end

function Enable.maps()
    return items(ActiveMods.getById("default"):getMapOrder())
end

function Enable.plan(entry, state, ticks)
    return ModList.plan({
        pack = entry.result.pack, active = Enable.active(), maps = Enable.maps(), state = state, ticks = ticks,
        status = Enable.status, requires = Enable.requires,
    })
end

local function failed(key, ...)
    return { error = key, args = { ... } }
end

-- Every change of the list goes here. Nothing is touched until the list in use is backed up and read back, and the
-- state saved; then the list is saved as the Mods screen does (ModSelectorModel.lua:279-301). A reload ends this Lua
-- state.
local function commit(state, change)
    if state.newer then
        return failed("UI_Prepackaged_FailNewer", State.FILE)
    end
    local active, maps = Enable.active(), Enable.maps()
    if not Text.same(active, change.mods) or not Text.same(maps, change.maps) then
        local backup = {
            n = Backup.next(Files.backups()), date = os.date(DATE), mods = active, maps = maps, before = change.before,
            pack = State.pack(state),
        }
        if not Files.saveBackup(backup) then
            return failed("UI_Prepackaged_FailBackup", Backup.path(backup.n))
        end
    end
    local entry = change.entry
    if entry ~= nil and entry.source == "clipboard" then
        entry = Discovery.keep(entry)
        if entry == nil then
            return failed("UI_Prepackaged_FailPackFile", Files.PACKS)
        end
    end
    change.record(state, entry)
    if not Files.saveState(state) then
        return failed("UI_Prepackaged_FailState", State.FILE)
    end
    local default = ActiveMods.getById("default")
    local mods, order = default:getMods(), default:getMapOrder()
    mods:clear()
    for _, id in ipairs(change.mods) do
        mods:add(id)
    end
    order:clear()
    for _, map in ipairs(change.maps) do
        order:add(map)
    end
    saveModsFile()
    ActiveMods.getById("currentGame"):copyFrom(default)
    if ActiveMods.requiresResetLua(default) then
        getCore():ResetLua("default", Enable.RESET_REASON)
        return { reloaded = true }
    end
    return { entry = entry }
end

function Enable.apply(entry, plan, state)
    local pack = entry.result.pack
    return commit(state, {
        mods = plan.mods, maps = plan.maps, entry = entry, before = { kind = "pack", id = pack.id, version = pack.version },
        record = function(s, kept) State.record(s, pack, { kind = kept.source, name = kept.name }, plan.fromPack) end,
    })
end

-- The pack in use goes back to what it was when the backup was taken.
function Enable.restore(backup, state)
    return commit(state, {
        mods = backup.mods, maps = backup.maps, before = { kind = "restore", n = backup.n },
        record = function(s) State.setPack(s, backup.pack) end,
    })
end

return Enable
