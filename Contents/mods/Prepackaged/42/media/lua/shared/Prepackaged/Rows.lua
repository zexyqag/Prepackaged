-- Text from a pack is only ever an argument or a row's literal text, never a format.
local Parse = require "Prepackaged/Parse"

local Rows = {}

local function text(rows, style, key, ...)
    rows[#rows + 1] = { style = style, key = key, args = { ... } }
end

local function modified(bind)
    return bind.shift or bind.ctrl or bind.alt
end

local function mods(rows, list, of)
    for _, id in ipairs(list) do
        rows[#rows + 1] = { style = "mod", id = id, name = of and of(id) }
    end
end

local function conflicts(rows, heading, list, of)
    if #list == 0 then
        return
    end
    text(rows, "section", heading)
    for _, c in ipairs(list) do
        local key = c.rule == "loadModBefore" and "UI_Prepackaged_ConflictBefore" or "UI_Prepackaged_ConflictAfter"
        text(rows, "warning", key, of(c.id) or c.id, of(c.other) or c.other, c.rule)
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

-- An entry's name as the game shows it, else as the pack writes it.
local function label(item)
    local target = item.target
    if target ~= nil and target.page ~= nil then
        return target.pageTitle .. ": " .. target.title
    elseif target ~= nil then
        return target.title
    elseif item.kind == "bind" then
        return item.name
    end
    return item.page .. ": " .. item.option
end

local function reasons(rows, list, style, lines)
    for i, item in ipairs(list) do
        if i > Parse.MAX_NOTES then
            text(rows, "note", "UI_Prepackaged_DetailMore", #list - Parse.MAX_NOTES)
            return
        end
        rows[#rows + 1] = { style = style, line = lines and item.line or nil, key = "UI_Prepackaged_Reason_" .. item.reason, args = { label(item), unpack(item.args) } }
    end
end

local function blocked(rows, review)
    if review.blocked.binds ~= nil then
        text(rows, "alert", "UI_Prepackaged_DefaultsFeatureKeys", review.blocked.binds)
    end
    if review.blocked.options ~= nil then
        text(rows, "alert", "UI_Prepackaged_DefaultsFeatureOptions", review.blocked.options)
    end
end

-- For the pack's author: every entry the game as loaded now can't place, in line order.
local function unplaced(rows, check)
    text(rows, "text", "UI_Prepackaged_DetailDefaults", check.keys, check.options)
    local review = check.review
    blocked(rows, review)
    local at, last = {}, 0
    for _, items in ipairs({ review.invalid, review.waiting }) do
        for _, item in ipairs(items) do
            if item.reason ~= "Feature" then
                at[item.line], last = item, math.max(last, item.line)
            end
        end
    end
    local list = {}
    for line = 1, last do
        if at[line] ~= nil then
            list[#list + 1] = at[line]
        end
    end
    if #list == 0 then
        return
    end
    text(rows, "section", "UI_Prepackaged_DetailUnplaced", #list)
    reasons(rows, list, "warning", true)
end

function Rows.details(entry, state, packConflicts, of, check)
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
    if check ~= nil then
        unplaced(rows, check)
    end
    notes(rows, "error", "UI_Prepackaged_DetailErrors", result.errors, result.more.errors)
    notes(rows, "warning", "UI_Prepackaged_DetailWarnings", result.warnings, result.more.warnings)
    conflicts(rows, "UI_Prepackaged_ReviewConflicts", packConflicts, of)
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
    conflicts(rows, "UI_Prepackaged_ReviewConflicts", plan.conflicts, names.of)
    conflicts(rows, "UI_Prepackaged_ReviewOwnConflicts", plan.ownConflicts, names.of)
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

-- Each row's tick is ticks[row.item]. names: pack and version for the title, value(target, value) and key(code) as
-- the game names them.
function Rows.defaults(review, ticks, clashes, names)
    local rows = {}
    text(rows, "title", review.all and "UI_Prepackaged_DefaultsAllHead" or "UI_Prepackaged_DefaultsHead", names.pack, names.version)
    text(rows, "note", "UI_Prepackaged_DefaultsIntro")
    blocked(rows, review)
    local sections = { keys = {}, options = {} }
    for _, item in ipairs(review.rows) do
        local list = sections[item.section]
        list[#list + 1] = item
    end
    for _, section in ipairs({ { "UI_Prepackaged_DefaultsKeys", sections.keys }, { "UI_Prepackaged_DefaultsOptions", sections.options } }) do
        local list = section[2]
        if #list > 0 then
            text(rows, "section", section[1], #list)
            local group = nil
            for _, item in ipairs(list) do
                local target = item.target
                if target.group ~= group then
                    group = target.group
                    rows[#rows + 1] = { style = "group", text = group.title }
                end
                local key = item.declined and "UI_Prepackaged_DefaultsDeclined" or item.own and "UI_Prepackaged_DefaultsOwn" or "UI_Prepackaged_DefaultsChange"
                rows[#rows + 1] = {
                    style = "tick", status = "ok", item = item, ticked = ticks[item] == true, key = key,
                    args = { target.title, names.value(target, item.from), names.value(target, item.to) },
                }
            end
        end
    end
    if #clashes > 0 then
        text(rows, "section", "UI_Prepackaged_DefaultsClashes", #clashes)
        for _, clash in ipairs(clashes) do
            text(rows, "warning", "UI_Prepackaged_DefaultsClash", names.key(clash.key))
            for _, e in ipairs(clash.binds) do
                local target = e.target
                if e.mod or not modified(e.bind) then
                    text(rows, "item", "UI_Prepackaged_DefaultsClashBind", target.title, target.group.title)
                else
                    text(rows, "item", "UI_Prepackaged_DefaultsClashKey", target.title, target.group.title, names.value(target, e.bind))
                end
            end
        end
    end
    if #review.invalid > 0 then
        text(rows, "section", "UI_Prepackaged_DefaultsInvalid", #review.invalid)
        reasons(rows, review.invalid, "warning", false)
    end
    if #review.waiting > 0 then
        text(rows, "section", "UI_Prepackaged_DefaultsWaiting", #review.waiting)
        reasons(rows, review.waiting, "item", false)
    end
    if #review.server > 0 then
        text(rows, "section", "UI_Prepackaged_DefaultsServer", #review.server)
        reasons(rows, review.server, "item", false)
    end
    if #review.same > 0 then
        text(rows, "note", "UI_Prepackaged_DefaultsSame", #review.same)
    end
    if review.decided > 0 then
        text(rows, "note", "UI_Prepackaged_DefaultsDecided", review.decided)
    end
    text(rows, "note", #review.rows > 0 and "UI_Prepackaged_DefaultsRestart" or "UI_Prepackaged_DefaultsNothing")
    return rows
end

function Rows.backupTitle(backup)
    if backup.kind == "files" then
        if backup.n == 1 then
            return { key = "UI_Prepackaged_FilesFirst", args = {} }
        elseif backup.before.kind == "defaults" then
            return { key = "UI_Prepackaged_FilesBeforePack", args = { backup.before.id, backup.before.version } }
        end
        return { key = "UI_Prepackaged_FilesBeforeRestore", args = { backup.before.n } }
    end
    if backup.n == 1 then
        return { key = "UI_Prepackaged_BackupFirst", args = {} }
    elseif backup.before.kind == "pack" then
        return { key = "UI_Prepackaged_BackupBeforePack", args = { backup.before.id, backup.before.version } }
    end
    return { key = "UI_Prepackaged_BackupBeforeRestore", args = { backup.before.n } }
end

function Rows.backupDetail(backup)
    if backup.kind == "files" then
        return { key = "UI_Prepackaged_FilesDetail", args = { backup.n, backup.date } }
    end
    return { key = "UI_Prepackaged_BackupDetail", args = { backup.n, backup.date, #backup.mods } }
end

function Rows.backup(backup, of)
    local rows = {}
    local head = Rows.backupTitle(backup)
    text(rows, "title", head.key, unpack(head.args))
    local detail = Rows.backupDetail(backup)
    text(rows, "text", detail.key, unpack(detail.args))
    if backup.kind == "files" then
        text(rows, "text", "UI_Prepackaged_FilesKeys", #backup.keys)
        text(rows, "text", "UI_Prepackaged_FilesOptions", #backup.options)
        text(rows, "note", "UI_Prepackaged_FilesRestore")
        return rows
    end
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
