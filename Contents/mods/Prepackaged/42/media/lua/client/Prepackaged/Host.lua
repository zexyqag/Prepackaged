-- A server preset in Zomboid/Server for Host, set up from a pack or put back from a backup, and the lines a dedicated
-- server needs. A mod's sandbox options exist only while the mod is loaded, and the game saves a preset with only the
-- options it has, so the pack's mods and the preset's own are loaded first, as its own server settings screen does
-- (ServerSettingsScreen.lua:3087-3098), and the player's own list again after. The job is kept in a file across both
-- reloads.
local Backup = require "Prepackaged/Backup"
local Enable = require "Prepackaged/Enable"
local Files = require "Prepackaged/Files"
local Parse = require "Prepackaged/Parse"
local Rows = require "Prepackaged/Rows"
local Sandbox = require "Prepackaged/Sandbox"
local Server = require "Prepackaged/Server"
local State = require "Prepackaged/State"
local Text = require "Prepackaged/Text"

local Host = {}

Host.RELOAD = "PrepackagedHost"
Host.DONE = "PrepackagedHostDone"

-- The game's parts the setup needs, checked before anything is written.
function Host.missing()
    if type(ServerSettings) ~= "table" or ServerSettings.new == nil then
        return "ServerSettings"
    elseif getServerSettingsManager == nil then
        return "getServerSettingsManager"
    elseif serverFileExists == nil then
        return "serverFileExists"
    end
end

local function hostMissing()
    local screen = MainScreen.instance and MainScreen.instance.onlineCoopScreen
    if type(CoopConnection) ~= "table" then
        return "CoopConnection"
    elseif screen == nil then
        return "MainScreen.onlineCoopScreen"
    end
    for _, name in ipairs({ "loadOptions", "saveOptions", "aboutToShow" }) do
        if type(screen[name]) ~= "function" then
            return "CoopOptionsScreen." .. name
        end
    end
end

local function failed(key, ...)
    return { error = key, args = { ... } }
end

-- The name as the game saves it (ServerSettings sanitizes it), the files of it already there and its Mods line, or why
-- it can't be used.
function Host.check(text)
    if Text.trim(text) == "" then
        return { problem = getText("UI_Prepackaged_HostNoName") }
    end
    local settings = ServerSettings.new(text)
    if not settings:isValid() then
        return { problem = settings:getErrorMsg() }
    end
    local name = settings:getName()
    local manager = getServerSettingsManager()
    if not manager:isValidName(name) then
        return { problem = getText("UI_Prepackaged_HostBadName", name) }
    elseif not manager:settingsFolderValidLengthChecks(name) then
        return { problem = getText("UI_Prepackaged_HostLongName", name) }
    end
    local check = { name = name, exists = {}, existing = false }
    for _, suffix in ipairs(Server.SUFFIXES) do
        check.exists[suffix] = serverFileExists(name .. suffix)
        check.existing = check.existing or check.exists[suffix]
    end
    if check.existing then
        settings:loadFiles()
        check.mods = settings:getServerOptions():getOptionByName("Mods"):getValue()
    end
    return check
end

-- The check of a name, or what stops the setup, as text to show.
function Host.prepare(text)
    local missing = Host.missing()
    if missing ~= nil then
        return nil, getText("UI_Prepackaged_HostFeature", missing)
    end
    local ok, check = pcall(Host.check, text)
    if not ok then
        return nil, tostring(check)
    end
    return check.problem == nil and check or nil, check.problem
end

-- A Mods line's ids, with \ removed as the server does (GameServer.java:641-649).
local function modIds(value, into, seen)
    for _, id in ipairs(Text.split((string.gsub(value, "\\", "")), ";")) do
        id = Text.trim(id)
        if id ~= "" and not seen[id] then
            seen[id] = true
            into[#into + 1] = id
        end
    end
end

-- The mods to load for a job: these, then the existing preset's own.
local function toLoad(mods, check)
    local list, seen = {}, {}
    modIds(table.concat(mods, ";"), list, seen)
    modIds(check.mods or "", list, seen)
    return list
end

local function checked(fields, check)
    fields.name, fields.existing, fields.reload = check.name, check.existing, not Enable.loaded(fields.mods)
    fields.unusable = Enable.unusable(fields.mods)
    return fields
end

-- The pack's own Mods and WorkshopItems: optional mods a player ticked aren't in the pack's WorkshopItems.
function Host.packJob(entry, check)
    local pack = entry.result.pack
    local sandbox = {}
    for i, e in ipairs(pack.sandbox) do
        sandbox[i] = Sandbox.line(e)
    end
    return checked({
        title = Rows.name(pack), before = { kind = "pack", id = pack.id, version = pack.version }, memory = Server.memory(pack.hostmemory),
        mods = toLoad(pack.mods, check), ini = Sandbox.ini(pack), sandbox = sandbox,
    }, check)
end

-- Every value of the backup again, with the mods of its Mods line loaded, and Prepackaged to finish the job.
function Host.restoreJob(backup, check)
    local mods = { Parse.MOD_ID }
    for _, e in ipairs(Sandbox.entries(backup.ini)) do
        if e.name == "Mods" then
            mods[#mods + 1] = e.value
        end
    end
    return checked({
        title = backup.name, before = { kind = "restore", n = backup.n }, mods = toLoad(mods, check), ini = Text.copy(backup.ini),
        sandbox = Text.copy(backup.sandbox),
    }, check)
end

local function optionLines(options)
    local lines = {}
    for i = 1, options:getNumOptions() do
        local option = options:getOptionByIndex(i - 1)
        lines[i] = option:getName() .. "=" .. option:getValueAsString()
    end
    return lines
end

-- The preset as the game loads it now: every server setting, and the sandbox settings of the game and of the mods
-- loaded now.
local function backUp(job)
    local settings = ServerSettings.new(job.name)
    settings:loadFiles()
    local before = job.before
    if before.kind == "pack" then
        before = { kind = "host", id = before.id, version = before.version }
    end
    local backup = {
        n = Backup.next(Files.serverBackups()), date = os.date(Backup.DATE), before = before, name = job.name,
        ini = optionLines(settings:getServerOptions()), sandbox = optionLines(settings:getSandboxOptions()),
    }
    if not Files.saveServerBackup(backup) then
        return nil, Backup.path(Backup.SERVERS, backup.n)
    end
    return backup
end

local function set(options, e)
    local option = options:getOptionByName(e.name)
    if option == nil then
        return "missing"
    elseif not option:isValidString(e.value) then
        return "invalid"
    end
    option:parse(e.value)
    return "set", option:getValueAsString()
end

local function lines(list)
    local result = {}
    for i, e in ipairs(list) do
        result[i] = Sandbox.line(e)
    end
    return result
end

-- Loaded or made new, then each value as a preset file sets it (isValidString, then parse: SandboxOptions.java:657-665),
-- saved, and read back: a value the files don't give back is listed.
local function apply(job)
    local settings = ServerSettings.new(job.name)
    if job.existing then
        settings:loadFiles()
    else
        settings:resetToDefault()
    end
    local server, sandbox = settings:getServerOptions(), settings:getSandboxOptions()
    local ini = Sandbox.sort(Sandbox.entries(job.ini), function(e) return set(server, e) end)
    local sorted = Sandbox.sort(Sandbox.entries(job.sandbox), function(e) return set(sandbox, e) end)
    if not settings:saveFiles() then
        job.error, job.detail = "UI_Prepackaged_HostNotSaved", "Zomboid/Server"
        return
    end
    local back = ServerSettings.new(job.name)
    back:loadFiles()
    local lost = {}
    for _, pair in ipairs({ { ini.set, back:getServerOptions() }, { sorted.set, back:getSandboxOptions() } }) do
        for _, e in ipairs(pair[1]) do
            local option = pair[2]:getOptionByName(e.name)
            if option == nil or option:getValueAsString() ~= e.text then
                lost[#lost + 1] = e
            end
        end
    end
    job.set = lines(sorted.set)
    job.missing = lines(ini.missing)
    job.invalid = lines(ini.invalid)
    for _, e in ipairs(sorted.missing) do
        job.missing[#job.missing + 1] = Sandbox.line(e)
    end
    for _, e in ipairs(sorted.invalid) do
        job.invalid[#job.invalid + 1] = Sandbox.line(e)
    end
    job.lost = lines(lost)
end

-- Nil, or the file the backup couldn't be saved in.
local function keep(job)
    local ok, backup, path = pcall(backUp, job)
    if not ok or backup == nil then
        return ok and path or Backup.SERVERS
    end
    job.backup = backup.n
end

local function run(job)
    local ok, problem = pcall(function()
        local path = job.existing and job.backup == nil and keep(job)
        if path then
            job.error, job.detail = "UI_Prepackaged_HostNoBackup", path
        else
            apply(job)
        end
    end)
    if not ok then
        job.error, job.detail = "UI_Prepackaged_HostFailed", tostring(problem)
    end
    job.step = "done"
    return job
end

-- An existing preset is backed up first, with its mods loaded, and nothing is written to it unless the backup reads back.
function Host.start(job, state)
    if state.newer then
        return failed("UI_Prepackaged_FailNewer", State.FILE)
    elseif job.reload and getCore().DelayResetLua == nil then
        return failed("UI_Prepackaged_HostFeature", "Core.DelayResetLua")
    end
    if job.existing and not job.reload then
        local path = keep(job)
        if path ~= nil then
            return failed("UI_Prepackaged_FailServerBackup", path)
        end
    end
    if not job.reload then
        return { job = run(job) }
    end
    job.step = "reload"
    if not Files.write(Server.FILE, Server.encodeJob(job)) then
        return failed("UI_Prepackaged_FailHostFile", Server.FILE)
    end
    local list = ActiveMods.getById("serversettings"):getMods()
    list:clear()
    for _, id in ipairs(job.mods) do
        list:add(id)
    end
    getCore():ResetLua("serversettings", Host.RELOAD)
    return { reloaded = true }
end

-- With the pack's mods loaded. The reload back to the player's list waits until this reload is over
-- (MainScreenState.update runs CheckDelayResetLua), so it never starts inside one.
function Host.resume()
    pcall(function()
        local job = Server.decodeJob(Files.read(Server.FILE) or {})
        if job ~= nil and job.step == "reload" then
            Files.write(Server.FILE, Server.encodeJob(run(job)))
        end
    end)
    getCore():DelayResetLua("default", Host.DONE)
end

-- The finished job, read once.
function Host.done()
    local job = Server.decodeJob(Files.read(Server.FILE) or {})
    Files.write(Server.FILE, {})
    if job == nil or job.step ~= "done" then
        return nil
    end
    return job
end

-- The Host screen reads host.ini each time it shows (CoopOptionsScreen.lua:315-364), so the server and memory go there,
-- after reading it, so the player's own name in it stays. Nil, or the part of the screen the game lacks.
function Host.show(job)
    local missing = hostMissing()
    if missing ~= nil then
        return missing
    end
    local screen = MainScreen.instance.onlineCoopScreen
    screen:loadOptions()
    CoopConnection.servername = job.name
    if job.memory ~= nil then
        CoopConnection.memory = job.memory
    end
    screen:saveOptions()
    MainScreen.instance.bottomPanel:setVisible(false)
    screen:aboutToShow()
    screen:setVisible(true)
end

local LEFT = { Version = "UI_Prepackaged_LinesLeftVersion", Group = "UI_Prepackaged_LinesLeftGroup", Value = "UI_Prepackaged_LinesLeftValue" }

-- The server .ini lines and the SandboxVars block, typed by each option where the game has it loaded. Text for the
-- clipboard and the file, and what the window says of it.
function Host.serverLines(entry)
    local pack = entry.result.pack
    local options = SandboxOptions ~= nil and SandboxOptions.new ~= nil and SandboxOptions.new() or nil
    local entries, invalid, names = {}, {}, {}
    for i = 1, options and options:getNumOptions() or 0 do
        names[i] = options:getOptionByIndex(i - 1):getName()
    end
    for _, e in ipairs(pack.sandbox) do
        local option = options and options:getOptionByName(e.name)
        if option == nil then
            entries[#entries + 1] = { name = e.name, value = e.value, line = e.line, text = e.value }
        elseif not option:isValidString(e.value) then
            invalid[#invalid + 1] = e
        else
            option:parse(e.value)
            entries[#entries + 1] = { name = e.name, value = e.value, line = e.line, text = option:getValueAsString(), type = option:getType() }
        end
    end
    local code, left = Sandbox.lua(entries, names)
    local dropped = {}
    for _, l in ipairs(left) do
        dropped[l.entry] = true
    end
    local written, untyped = 0, 0
    for _, e in ipairs(entries) do
        if not dropped[e] then
            written = written + 1
            untyped = untyped + (e.type == nil and 1 or 0)
        end
    end
    local head = getText("UI_Prepackaged_LinesHead", Rows.name(pack), pack.id, pack.version)
    local text = { "# " .. head, "# " .. getText("UI_Prepackaged_LinesIni") }
    for _, line in ipairs(Sandbox.ini(pack)) do
        text[#text + 1] = line
    end
    text[#text + 1] = ""
    text[#text + 1] = "-- " .. head
    text[#text + 1] = "-- " .. getText("UI_Prepackaged_LinesSandbox", written)
    for _, line in ipairs(code) do
        text[#text + 1] = line
    end
    for _, e in ipairs(invalid) do
        text[#text + 1] = "-- " .. getText("UI_Prepackaged_LinesLeftInvalid", Sandbox.line(e))
    end
    for _, l in ipairs(left) do
        text[#text + 1] = "-- " .. getText(LEFT[l.reason], Sandbox.line(l.entry))
    end
    return { pack = pack, text = text, typed = written - untyped, untyped = untyped, invalid = invalid, left = left, path = Server.linesPath(pack) }
end

return Host
