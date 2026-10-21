-- Text from a pack is only ever an argument or a row's literal text, never a format.
local Parse = require "Prepackaged/Parse"
local Sandbox = require "Prepackaged/Sandbox"
local Server = require "Prepackaged/Server"
local Subscriptions = require "Prepackaged/Subscriptions"
local Version = require "Prepackaged/Version"

local Rows = {}

local function text(rows, style, key, ...)
    rows[#rows + 1] = { style = style, key = key, args = { ... } }
end

-- Up to MAX_NOTES rows from list, then a count of the rest.
local function capped(rows, list, row)
    for i, item in ipairs(list) do
        if i > Parse.MAX_NOTES then
            text(rows, "note", "UI_Prepackaged_DetailMore", #list - Parse.MAX_NOTES)
            return
        end
        rows[#rows + 1] = row(item)
    end
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
    end
    local order = Version.compare(pack.version, state.applied)
    if order > 0 then
        return { key = "UI_Prepackaged_UseNewer", args = { pack.version, state.applied } }
    elseif order < 0 then
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
    capped(rows, list, function(item)
        return { style = style, line = lines and item.line or nil, key = "UI_Prepackaged_Reason_" .. item.reason, args = { label(item), unpack(item.args) } }
    end)
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

local REASONS = { missing = "UI_Prepackaged_SandboxMissing", invalid = "UI_Prepackaged_SandboxInvalid", hidden = "UI_Prepackaged_SandboxHidden",
    lost = "UI_Prepackaged_SandboxLost" }

local function unused(rows, sorted, style)
    for _, status in ipairs({ "missing", "invalid", "hidden", "lost" }) do
        capped(rows, sorted[status] or {}, function(e)
            return { style = style, line = e.line, key = REASONS[status], args = { Sandbox.line(e) } }
        end)
    end
end

-- sandbox: missing, the part of the sandbox screen the game lacks; sorted, the lines as the game loaded now takes them;
-- inUse and record, the preset Pack <id> of the pack in use.
local function sandboxDetails(rows, pack, sandbox)
    text(rows, "text", "UI_Prepackaged_DetailSandbox", #pack.sandbox)
    if sandbox.missing ~= nil then
        text(rows, "alert", "UI_Prepackaged_DetailSandboxFeature", sandbox.missing)
    end
    local name = Sandbox.presetName(pack)
    local record = sandbox.record
    if not sandbox.inUse then
        text(rows, "note", "UI_Prepackaged_DetailSandboxUse", name)
    elseif record ~= nil and record.version == pack.version and record.status == "written" then
        text(rows, "note", "UI_Prepackaged_DetailPresetWritten", name, pack.version)
    elseif record ~= nil and record.version == pack.version then
        text(rows, "note", "UI_Prepackaged_DetailPresetKept", name)
    else
        text(rows, "note", "UI_Prepackaged_DetailPresetWaiting", name)
    end
    local sorted = sandbox.sorted
    if sorted ~= nil and #sorted.missing + #sorted.invalid > 0 then
        text(rows, "section", "UI_Prepackaged_DetailSandboxUnplaced", #sorted.missing + #sorted.invalid)
        unused(rows, sorted, "warning")
    end
end

function Rows.details(entry, state, packConflicts, of, check, sandbox)
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
    if #pack.collection > 0 and #pack.collections == 0 then
        text(rows, "note", "UI_Prepackaged_DetailNoCollections")
    end
    if pack.map ~= nil then
        text(rows, "text", "UI_Prepackaged_DetailMap", pack.map)
    end
    if #pack.sandbox > 0 and sandbox ~= nil then
        sandboxDetails(rows, pack, sandbox)
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
        return text(rows, "title", "UI_Prepackaged_ReviewUse", name, pack.version)
    end
    local order = Version.compare(pack.version, state.applied)
    if order > 0 then
        text(rows, "title", "UI_Prepackaged_ReviewUpdate", name, state.applied, pack.version)
    elseif order < 0 then
        text(rows, "title", "UI_Prepackaged_ReviewDowngrade", name, state.applied, pack.version)
    else
        text(rows, "title", "UI_Prepackaged_ReviewAgain", name, pack.version)
    end
    if Version.compare(pack.version, state.applied, 1) > 0 then
        text(rows, "alert", "UI_Prepackaged_ReviewMajor")
    end
end

-- Sandbox settings belong to a world or a server, not to the game, so the review only tells of them and of what the
-- version in use set differently.
local function sandboxReview(rows, plan, pack, state)
    local diff = plan.update and state.applied ~= nil and Sandbox.diff(state.sandbox, pack.sandbox)
    if #pack.sandbox == 0 and not (diff and #diff.removed > 0) then
        return
    end
    text(rows, "section", "UI_Prepackaged_ReviewSandbox", #pack.sandbox)
    text(rows, "note", "UI_Prepackaged_ReviewSandboxWorld", Sandbox.presetName(pack))
    if not diff then
        return
    end
    local changes = {}
    for _, c in ipairs(diff.changed) do
        changes[#changes + 1] = { key = "UI_Prepackaged_ReviewSandboxChanged", args = { c.name, c.from, c.to } }
    end
    for _, c in ipairs(diff.added) do
        changes[#changes + 1] = { key = "UI_Prepackaged_ReviewSandboxAdded", args = { c.name, c.to } }
    end
    for _, c in ipairs(diff.removed) do
        changes[#changes + 1] = { key = "UI_Prepackaged_ReviewSandboxRemoved", args = { c.name, c.from } }
    end
    if #changes == 0 then
        text(rows, "note", "UI_Prepackaged_ReviewSandboxSame", state.applied)
        return
    end
    text(rows, "text", "UI_Prepackaged_ReviewSandboxChanges", #changes, state.applied)
    capped(rows, changes, function(c) return { style = "item", key = c.key, args = c.args } end)
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
    -- Every mod an update disables came from the pack: the player's own are kept.
    if #plan.removed > 0 then
        text(rows, "section", plan.update and "UI_Prepackaged_ReviewUpdateRemoved" or "UI_Prepackaged_ReviewRemoved", #plan.removed)
        text(rows, "alert", "UI_Prepackaged_ReviewRemovedWorlds")
        mods(rows, plan.removed, names.of)
    end
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
    sandboxReview(rows, plan, pack, state)
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
    if backup.kind == "server" then
        if backup.before.kind == "host" then
            return { key = "UI_Prepackaged_ServerBackupBeforePack", args = { backup.name, backup.before.id, backup.before.version } }
        end
        return { key = "UI_Prepackaged_ServerBackupBeforeRestore", args = { backup.name, backup.before.n } }
    end
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
    if backup.kind == "server" then
        return { key = "UI_Prepackaged_ServerBackupDetail", args = { backup.n, backup.date } }
    end
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
    if backup.kind == "server" then
        text(rows, "text", "UI_Prepackaged_ServerBackupIni", backup.name, #backup.ini)
        text(rows, "text", "UI_Prepackaged_ServerBackupSandbox", backup.name, #backup.sandbox)
        text(rows, "note", "UI_Prepackaged_ServerBackupRestore")
        return rows
    end
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
    elseif pack.current ~= nil then
        text(rows, "note", "UI_Prepackaged_RestorePackUnknown", pack.current)
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

-- A dialog doesn't wrap or scroll, so it lists this many lines of a kind.
local DIALOG_LINES = 10

local function say(lines, key, ...)
    lines[#lines + 1] = { key = key, args = { ... } }
end

local function listed(lines, sorted, statuses)
    local count = 0
    for _, status in ipairs(statuses) do
        for _, e in ipairs(sorted[status]) do
            count = count + 1
            if count <= DIALOG_LINES then
                say(lines, REASONS[status], Sandbox.line(e))
            end
        end
    end
    if count > DIALOG_LINES then
        say(lines, "UI_Prepackaged_DialogMore", count - DIALOG_LINES)
    end
end

-- The dialog after Apply pack on the sandbox screen.
function Rows.sandboxApplied(result)
    local lines, sorted = {}, result.sorted
    say(lines, "UI_Prepackaged_SandboxApplied", Rows.name(result.pack), result.pack.version, #sorted.changed, #sorted.same)
    listed(lines, sorted, { "missing", "invalid", "hidden" })
    say(lines, "UI_Prepackaged_SandboxCheck")
    return lines
end

-- What setting up a server will do, asked before anything is written. check.exists: the preset's files already there.
function Rows.hostAsk(job, check)
    local lines = {}
    if job.before.kind == "pack" then
        say(lines, "UI_Prepackaged_HostAsk", job.name, job.title, job.before.version)
    else
        say(lines, "UI_Prepackaged_HostAskRestore", job.name, job.before.n)
    end
    for _, f in ipairs(Server.files(job.name, check.exists)) do
        say(lines, f.key, unpack(f.args))
    end
    if job.before.kind == "pack" then
        say(lines, "UI_Prepackaged_HostAskPack", #job.sandbox)
    else
        say(lines, "UI_Prepackaged_HostAskBackup", #job.ini, #job.sandbox)
    end
    if job.existing then
        say(lines, "UI_Prepackaged_HostAskSaved")
    end
    if job.reload then
        say(lines, "UI_Prepackaged_HostAskReload")
    end
    if job.memory ~= nil then
        say(lines, "UI_Prepackaged_HostAskMemory", job.memory)
    end
    say(lines, "UI_Prepackaged_HostAskGo")
    return lines
end

-- The dialog once the preset is saved, or why it isn't.
function Rows.hosted(job)
    local lines = {}
    if job.error ~= nil then
        say(lines, job.error, job.name, job.detail)
        return lines
    end
    say(lines, "UI_Prepackaged_HostDone", job.name, #job.set)
    local sorted = { missing = Sandbox.entries(job.missing), invalid = Sandbox.entries(job.invalid), lost = Sandbox.entries(job.lost) }
    listed(lines, sorted, { "missing", "invalid", "lost" })
    if job.backup ~= nil then
        say(lines, "UI_Prepackaged_HostBackup", job.backup)
    end
    return lines
end

-- Longer lines are cut in the window: the clipboard and the file hold them whole.
local CLIP = 120

local function clip(line)
    if #line > CLIP then
        return string.sub(line, 1, CLIP) .. "..."
    end
    return line
end

local LEFT = { Version = "UI_Prepackaged_ServerLeftVersion", Group = "UI_Prepackaged_ServerLeftGroup" }

-- info: pack, text (the lines as copied), path, typed and untyped counts, invalid and left (Sandbox.lua) entries,
-- hostMissing, reload and memory.
function Rows.server(info)
    local rows, pack = {}, info.pack
    text(rows, "title", "UI_Prepackaged_ServerHead", Rows.name(pack), pack.version)
    text(rows, "section", "UI_Prepackaged_ServerHostHead")
    text(rows, "note", "UI_Prepackaged_ServerHostHow")
    if info.hostMissing ~= nil then
        text(rows, "alert", "UI_Prepackaged_ServerHostFeature", info.hostMissing)
    end
    if info.reload then
        text(rows, "note", "UI_Prepackaged_ServerReload")
    end
    if info.memory ~= nil then
        text(rows, "text", "UI_Prepackaged_ServerMemory", info.memory)
    end
    text(rows, "section", "UI_Prepackaged_ServerLinesHead")
    text(rows, "note", "UI_Prepackaged_ServerLinesHow", info.path)
    text(rows, "text", "UI_Prepackaged_ServerLinesCount", #pack.workshopItems, #pack.mods, info.typed + info.untyped)
    if info.untyped > 0 then
        text(rows, "note", "UI_Prepackaged_ServerUntyped", info.untyped)
    end
    local left = #info.invalid + #info.left
    if left > 0 then
        text(rows, "section", "UI_Prepackaged_ServerLeft", left)
        capped(rows, info.invalid, function(e) return { style = "warning", line = e.line, key = REASONS.invalid, args = { Sandbox.line(e) } } end)
        capped(rows, info.left, function(l)
            return { style = "warning", line = l.entry.line, key = LEFT[l.reason], args = { Sandbox.line(l.entry) } }
        end)
    end
    text(rows, "section", "UI_Prepackaged_ServerPreview", #info.text)
    capped(rows, info.text, function(line) return { style = "code", text = clip(line) } end)
    return rows
end

local ITEM = {
    NotSubscribed = "UI_Prepackaged_SubsItemNotSubscribed", Downloading = "UI_Prepackaged_SubsItemDownloading",
    NeedsUpdate = "UI_Prepackaged_SubsItemNeedsUpdate", Error = "UI_Prepackaged_SubsItemError", NoDetails = "UI_Prepackaged_SubsItemNoDetails",
    NoAnswer = "UI_Prepackaged_SubsItemNoAnswer", Unknown = "UI_Prepackaged_SubsItemUnknown", Asking = "UI_Prepackaged_SubsItemAsking",
}

local function part(row, key, n)
    if n > 0 then
        row.parts[#row.parts + 1] = { key = key, args = { n } }
    end
end

-- The collection's own items: its page's Subscribe to all covers those, not its sub-collections.
local function collection(line, result)
    local name = line.entry.title ~= "" and line.entry.title or line.id
    local count = Subscriptions.count(line.entry.items, result.states)
    local row = { style = "collection", depth = line.depth, name = name, parts = {} }
    if count.action then
        row.open = line.id
    end
    if count.total == 0 then
        row.key, row.args = "UI_Prepackaged_SubsEmpty", { name }
    elseif count.Installed == count.total then
        row.style, row.key, row.args = "done", "UI_Prepackaged_SubsDone", { name, count.total }
    elseif count.asking + count.unknown == count.total then
        row.key, row.args = "UI_Prepackaged_SubsCount", { name, count.total }
        part(row, "UI_Prepackaged_SubsAsking", count.asking)
    else
        row.key, row.args = "UI_Prepackaged_SubsLine", { name, count.total, count.NotSubscribed }
        part(row, "UI_Prepackaged_SubsDownloading", count.Downloading)
        part(row, "UI_Prepackaged_SubsNeedsUpdate", count.NeedsUpdate)
        part(row, "UI_Prepackaged_SubsMissing", count.missing)
        part(row, "UI_Prepackaged_SubsAsking", count.asking)
    end
    return row
end

-- Only items that aren't installed get a row; an Open only where nothing is on its way.
local function loose(rows, tree, result)
    if #tree.loose == 0 then
        return
    end
    text(rows, "section", tree.listed and "UI_Prepackaged_SubsLoose" or "UI_Prepackaged_SubsItems", #tree.loose)
    local installed = 0
    for _, id in ipairs(tree.loose) do
        local state = result.states[id]
        if state == "Installed" then
            installed = installed + 1
        else
            local name = result.titles[id] or id
            rows[#rows + 1] = { style = "item", key = ITEM[state], args = { name }, name = name, open = Subscriptions.needsAction(state) and id or nil }
        end
    end
    if installed == #tree.loose then
        text(rows, "done", "UI_Prepackaged_SubsAllInstalled", installed)
    elseif installed > 0 then
        text(rows, "note", "UI_Prepackaged_SubsMoreInstalled", installed)
    end
end

function Rows.subscriptions(tree, result, overlay)
    local rows = {}
    text(rows, "note", "UI_Prepackaged_SubsIntro")
    if not result.steam then
        text(rows, "alert", "UI_Prepackaged_SubsNoSteam")
    elseif not overlay then
        text(rows, "alert", "UI_Prepackaged_SubsNoOverlay")
    end
    if #tree.lines > 0 then
        text(rows, "section", "UI_Prepackaged_SubsCollections", #tree.lines)
    end
    for _, line in ipairs(tree.lines) do
        if line.entry == nil then
            rows[#rows + 1] = { style = "collection", depth = line.depth, key = "UI_Prepackaged_SubsUnlisted", args = { line.id }, name = line.id, open = line.id }
        else
            rows[#rows + 1] = collection(line, result)
        end
    end
    loose(rows, tree, result)
    text(rows, "note", "UI_Prepackaged_SubsAfter")
    return rows
end

return Rows
