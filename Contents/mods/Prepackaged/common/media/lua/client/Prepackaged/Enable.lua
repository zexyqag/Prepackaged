local Backup = require "Prepackaged/Backup"
local Build = require "Prepackaged/Build"
local Discovery = require "Prepackaged/Discovery"
local Files = require "Prepackaged/Files"
local ModList = require "Prepackaged/ModList"
local State = require "Prepackaged/State"
local Text = require "Prepackaged/Text"

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

-- Every mod of the list that can be used is loaded now, so their sandbox options exist. isAvailable also checks each
-- require= mod, as the game does before it loads one (ChooseGameInfo.java:620-675).
function Enable.loaded(mods)
    for _, id in ipairs(mods) do
        if Enable.status(id) == "ok" and not isModActive(getModInfoByID(id)) then
            return false
        end
    end
    return true
end

-- The mods of the list the game can't use.
function Enable.unusable(mods)
    local ids = {}
    for _, id in ipairs(mods) do
        if Enable.status(id) == "unavailable" then
            ids[#ids + 1] = id
        end
    end
    return ids
end

function Enable.nameOf(id)
    local info = getModInfoByID(id)
    return info and info:getName()
end

-- Each list is split at commas only (ChooseGameInfo.java:224-231), so "\A, \B" leaves a space.
local function ids(list)
    local result, seen = {}, {}
    for i = 0, (list and list:size() or 0) - 1 do
        local id = Text.trim(list:get(i))
        if id ~= "" and not seen[id] then
            seen[id] = true
            result[#result + 1] = id
        end
    end
    return result
end

function Enable.rules(id)
    local info = getModInfoByID(id)
    local after, before = Build.loadOrder(info)
    return { require = ids(info and info:getRequire()), loadModAfter = ids(after), loadModBefore = ids(before) }
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
        status = Enable.status, rules = Enable.rules,
    })
end

-- For the pack's author: the pack's own list with every optional mod ticked.
function Enable.packConflicts(entry)
    local pack, ticks = entry.result.pack, {}
    for _, optional in ipairs(pack.optional) do
        ticks[optional.id] = true
    end
    return ModList.plan({
        pack = pack, active = {}, maps = {}, state = State.new(), ticks = ticks, status = Enable.status, rules = Enable.rules,
    }).conflicts
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
            n = Backup.next(Files.backups()), date = os.date(Backup.DATE), mods = active, maps = maps, before = change.before,
            pack = State.pack(state),
        }
        if not Files.saveBackup(backup) then
            return failed("UI_Prepackaged_FailBackup", Backup.path(Backup.FOLDER, backup.n))
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
        getCore():ResetLua("default", change.reason)
        return { reloaded = true }
    end
    return { entry = entry }
end

function Enable.apply(entry, plan, state)
    local pack = entry.result.pack
    return commit(state, {
        mods = plan.mods, maps = plan.maps, entry = entry, before = { kind = "pack", id = pack.id, version = pack.version },
        record = function(s, kept) State.record(s, pack, { kind = kept.source, name = kept.name }, plan.fromPack) end,
        reason = Enable.RESET_REASON,
    })
end

-- The pack in use goes back to what it was when the backup was taken.
function Enable.restore(backup, state)
    return commit(state, {
        mods = backup.mods, maps = backup.maps, before = { kind = "restore", n = backup.n },
        record = function(s) State.setPack(s, backup.pack) end,
        reason = Backup.RESET_REASON,
    })
end

return Enable
