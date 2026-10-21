-- What the Prepackaged screens show, as rows. Pure: text is a translation key with args, or literal text from a pack.
-- Row styles: title, section, text, note, error, warning (with the pack line, 0 for none), mod { id, name } and
-- tick { id, name, label, ticked, status }.
local Rows = {}

local function text(rows, style, key, ...)
    rows[#rows + 1] = { style = style, key = key, args = { ... } }
end

function Rows.name(pack)
    return pack.name or pack.id
end

-- The source of a discovered pack as { key, args }.
function Rows.source(entry)
    if entry.source == "mod" then
        return { key = entry.enabled and "UI_Prepackaged_SourceModOn" or "UI_Prepackaged_SourceModOff", args = { entry.modName, entry.name } }
    elseif entry.source == "file" then
        return { key = "UI_Prepackaged_SourceFile", args = { entry.name } }
    end
    return { key = "UI_Prepackaged_SourceClipboard", args = {} }
end

-- The pack in use compared with this one, as { key, args }, or nil when it isn't the pack in use.
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

local function notes(rows, style, list)
    for _, note in ipairs(list) do
        rows[#rows + 1] = { style = style, line = note.line, key = "UI_Prepackaged_Diag_" .. note.code, args = note.args }
    end
end

-- The details of a discovered pack.
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
    if #result.errors > 0 then
        text(rows, "section", "UI_Prepackaged_DetailErrors", #result.errors)
        notes(rows, "error", result.errors)
    end
    if #result.warnings > 0 then
        text(rows, "section", "UI_Prepackaged_DetailWarnings", #result.warnings)
        notes(rows, "warning", result.warnings)
    end
    return rows
end

-- The review before a pack's mod list is applied. names: { pack = display name, preset = the backup preset's name,
-- of = function(id) -> the mod's name or nil }.
function Rows.review(plan, pack, state, names)
    local rows = {}
    local function section(key, list)
        if #list == 0 then
            return
        end
        text(rows, "section", key, #list)
        for _, id in ipairs(list) do
            rows[#rows + 1] = { style = "mod", id = id, name = names.of(id) }
        end
    end
    if not plan.update then
        text(rows, "title", "UI_Prepackaged_ReviewUse", names.pack, pack.version)
    elseif state.applied ~= nil and pack.version > state.applied then
        text(rows, "title", "UI_Prepackaged_ReviewUpdate", names.pack, state.applied, pack.version)
    else
        text(rows, "title", "UI_Prepackaged_ReviewAgain", names.pack, pack.version)
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
    if plan.reordered then
        text(rows, "note", "UI_Prepackaged_ReviewOrder")
    end
    if not plan.update then
        text(rows, "note", "UI_Prepackaged_ReviewOwnMods")
    end
    if not plan.changed then
        text(rows, "note", "UI_Prepackaged_ReviewNoChange")
        return rows
    end
    if #plan.active > 0 then
        text(rows, "note", "UI_Prepackaged_ReviewBackup", names.preset)
    end
    text(rows, "note", "UI_Prepackaged_ReviewReload")
    return rows
end

return Rows
