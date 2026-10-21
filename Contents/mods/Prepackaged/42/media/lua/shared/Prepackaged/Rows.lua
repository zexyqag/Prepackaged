-- Text from a pack is only ever an argument or a row's literal text, never a format.
local Parse = require "Prepackaged/Parse"

local Rows = {}

local function text(rows, style, key, ...)
    rows[#rows + 1] = { style = style, key = key, args = { ... } }
end

local function mods(rows, list, of)
    for _, id in ipairs(list) do
        rows[#rows + 1] = { style = "mod", id = id, name = of and of(id) }
    end
end

function Rows.name(pack)
    return pack.name or pack.id
end

function Rows.source(entry)
    if entry.source == "mod" then
        return { key = entry.enabled and "UI_Prepackaged_SourceModOn" or "UI_Prepackaged_SourceModOff", args = { entry.modName, entry.name } }
    elseif entry.source == "file" then
        return { key = "UI_Prepackaged_SourceFile", args = { entry.name } }
    end
    return { key = "UI_Prepackaged_SourceClipboard", args = {} }
end

function Rows.use(pack, state)
    if pack.id == nil or pack.id ~= state.current or state.applied == nil or pack.version == nil then
        return nil
    elseif pack.version > state.applied then
        return { key = "UI_Prepackaged_UseNewer", args = { pack.version, state.applied } }
    elseif pack.version < state.applied then
        return { key = "UI_Prepackaged_UseOlder", args = { pack.version, state.applied } }
    end
    return { key = "UI_Prepackaged_UseSame", args = { pack.version } }
end

local function notes(rows, style, heading, list, more)
    if #list == 0 then
        return
    end
    text(rows, "section", heading, #list + more)
    for _, note in ipairs(list) do
        rows[#rows + 1] = { style = style, line = note.line, key = "UI_Prepackaged_Diag_" .. note.code, args = note.args }
    end
    if more > 0 then
        text(rows, "note", "UI_Prepackaged_DetailMore", more)
    end
end

function Rows.details(entry, state)
    local result, rows = entry.result, {}
    local pack = result.pack
    local name = Rows.name(pack)
    if name ~= nil then
        rows[#rows + 1] = { style = "title", text = name }
    else
        text(rows, "title", "UI_Prepackaged_NoName")
    end
    if pack.id ~= nil then
        text(rows, "text", "UI_Prepackaged_DetailId", pack.id)
    end
    if pack.version ~= nil then
        text(rows, "text", "UI_Prepackaged_DetailVersion", pack.version)
    end
    local source = Rows.source(entry)
    text(rows, "text", source.key, unpack(source.args))
    text(rows, "text", "UI_Prepackaged_DetailMods", #pack.mods, #pack.optional)
    text(rows, "text", "UI_Prepackaged_DetailItems", #pack.workshopItems, #pack.collections)
    if pack.map ~= nil then
        text(rows, "text", "UI_Prepackaged_DetailMap", pack.map)
    end
    local use = Rows.use(pack, state)
    if use ~= nil then
        text(rows, "note", use.key, unpack(use.args))
    end
    notes(rows, "error", "UI_Prepackaged_DetailErrors", result.errors, result.more.errors)
    notes(rows, "warning", "UI_Prepackaged_DetailWarnings", result.warnings, result.more.warnings)
    return rows
end

local function title(rows, plan, pack, state, name)
    if not plan.update or state.applied == nil then
        text(rows, "title", "UI_Prepackaged_ReviewUse", name, pack.version)
    elseif pack.version > state.applied then
        text(rows, "title", "UI_Prepackaged_ReviewUpdate", name, state.applied, pack.version)
    elseif pack.version < state.applied then
        text(rows, "title", "UI_Prepackaged_ReviewDowngrade", name, state.applied, pack.version)
    else
        text(rows, "title", "UI_Prepackaged_ReviewAgain", name, pack.version)
    end
end

function Rows.review(plan, pack, state, names)
    local rows = {}
    local function section(key, list)
        if #list > 0 then
            text(rows, "section", key, #list)
            mods(rows, list, names.of)
        end
    end
    title(rows, plan, pack, state, names.pack)
    if #plan.missing > 0 then
        text(rows, "alert", "UI_Prepackaged_ReviewMissingCount", #plan.missing, #pack.mods)
        text(rows, "note", "UI_Prepackaged_ReviewSubscribe")
        if #pack.collection > 0 then
            text(rows, "note", "UI_Prepackaged_ReviewCollection", pack.collection[1])
        end
    end
    if #plan.optional > 0 then
        text(rows, "section", "UI_Prepackaged_ReviewOptional", #plan.optional)
        for _, entry in ipairs(plan.optional) do
            rows[#rows + 1] = {
                style = "tick", id = entry.id, name = names.of(entry.id), label = entry.label,
                ticked = entry.ticked, status = entry.status,
            }
        end
    end
    section("UI_Prepackaged_ReviewAdded", plan.added)
    section("UI_Prepackaged_ReviewRemoved", plan.removed)
    section("UI_Prepackaged_ReviewExtras", plan.extras)
    section("UI_Prepackaged_ReviewMissing", plan.missing)
    section("UI_Prepackaged_ReviewUnavailable", plan.unavailable)
    section("UI_Prepackaged_ReviewKept", plan.kept)
    if #plan.required > 0 then
        text(rows, "note", "UI_Prepackaged_ReviewRequired", table.concat(plan.required, ", "))
    end
    if plan.reordered then
        text(rows, "note", "UI_Prepackaged_ReviewOrder")
    end
    if not plan.update then
        text(rows, "note", "UI_Prepackaged_ReviewOwnMods")
    end
    if plan.mapsChanged and #plan.maps > 0 then
        text(rows, "note", "UI_Prepackaged_ReviewMapOrder", table.concat(plan.maps, "; "))
    elseif plan.mapsChanged then
        text(rows, "note", "UI_Prepackaged_ReviewMapOrderCleared")
    end
    if not plan.changed then
        text(rows, "note", "UI_Prepackaged_ReviewNoChange")
        return rows
    end
    text(rows, "note", "UI_Prepackaged_ReviewBackup")
    if plan.modsChanged then
        text(rows, "note", "UI_Prepackaged_ReviewReload")
    end
    return rows
end

function Rows.backupTitle(backup)
    if backup.n == 1 then
        return { key = "UI_Prepackaged_BackupFirst", args = {} }
    elseif backup.before.kind == "pack" then
        return { key = "UI_Prepackaged_BackupBeforePack", args = { backup.before.id, backup.before.version } }
    end
    return { key = "UI_Prepackaged_BackupBeforeRestore", args = { backup.before.n } }
end

function Rows.backupDetail(backup)
    return { key = "UI_Prepackaged_BackupDetail", args = { backup.n, backup.date, #backup.mods } }
end

function Rows.backup(backup, of)
    local rows = {}
    local head = Rows.backupTitle(backup)
    text(rows, "title", head.key, unpack(head.args))
    local detail = Rows.backupDetail(backup)
    text(rows, "text", detail.key, unpack(detail.args))
    text(rows, "section", "UI_Prepackaged_BackupMods", #backup.mods)
    mods(rows, backup.mods, of)
    if #backup.maps > 0 then
        text(rows, "section", "UI_Prepackaged_BackupMaps", #backup.maps)
        mods(rows, backup.maps)
    end
    local pack = backup.pack
    if pack.current ~= nil and pack.applied ~= nil then
        text(rows, "note", "UI_Prepackaged_RestorePack", pack.current, pack.applied)
    else
        text(rows, "note", "UI_Prepackaged_RestoreNoPack")
    end
    local found = false
    for _, id in ipairs(backup.mods) do
        found = found or id == Parse.MOD_ID
    end
    if not found then
        text(rows, "alert", "UI_Prepackaged_RestoreWithout")
    end
    text(rows, "note", "UI_Prepackaged_RestoreBackup")
    return rows
end

return Rows
