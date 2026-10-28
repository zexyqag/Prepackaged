-- What Prepackaged does differently on each build of the game: this is Build 41's, and 42/ holds Build 42's. The rest
-- of Prepackaged is in common/, and the upload puts both at the mod's root, where Build 41 reads them.
local Build = {}

Build.NUMBER = 41
-- Prepackaged's folder in Zomboid/Lua. Both builds use the same Zomboid folder, so Build 41 keeps its files apart.
Build.FOLDER = "Prepackaged41"
-- The key binds file. Build 41 has no mod options of its own, so no file for them.
Build.KEYS = "keys.ini"
Build.OPTIONS = nil
-- The Mods screen keeps no presets of mod lists.
Build.MOD_LIST_PRESETS = false
-- Pack files put in Prepackaged's packs folder by hand aren't found: only those Prepackaged saved itself.
Build.DROPPED_PACKS = false
-- Build 41's tick boxes use this texture (ISTickBox.lua:301).
Build.TICK = "Quest_Succeed"

-- The names Prepackaged wrote in each folder, as Build 41's Lua can't list one.
local INDEX = "index.lst"

local function readLines(path)
    local reader = getFileReader(path, false)
    if reader == nil then
        return nil
    end
    local lines = {}
    local line = reader:readLine()
    while line ~= nil do
        lines[#lines + 1] = line
        line = reader:readLine()
    end
    reader:close()
    return lines
end

function Build.keysSource()
    return Build.KEYS
end

-- The names in a folder's index. A file named there but gone reads as missing, as a listed one deleted since would.
function Build.list(folder)
    local names = {}
    for _, name in ipairs(readLines(folder .. "/" .. INDEX) or {}) do
        if name ~= "" then
            names[#names + 1] = name
        end
    end
    return names
end

-- Adds a file Prepackaged wrote to its folder's index.
function Build.written(path)
    local folder, name = string.match(path, "^(.*)/([^/]+)$")
    if folder == nil or name == INDEX then
        return
    end
    local names = readLines(folder .. "/" .. INDEX) or {}
    for _, known in ipairs(names) do
        if known == name then
            return
        end
    end
    names[#names + 1] = name
    local writer = getFileWriter(folder .. "/" .. INDEX, true, false)
    if writer ~= nil then
        writer:write(table.concat(names, "\n") .. "\n")
        writer:close()
    end
end

-- mod.info has no loadModAfter or loadModBefore on Build 41.
function Build.loadOrder(info)
    return nil, nil
end

-- Build 41 keeps one key per bind, with no second key and no modifiers (Core.java:2443-2449).
function Build.bindFits(bind)
    return bind.altCode == 0 and not bind.shift and not bind.ctrl and not bind.alt
end

function Build.showBind(t)
    if t.btn ~= nil then
        t.btn:setTitle(getKeyName(t.keyCode))
    end
end

function Build.addBind(t)
    getCore():addKeyBinding(t.txt:getName(), t.keyCode)
end

function Build.nameFits(manager, name)
    return true
end

-- Build 41 names apart from Build 42's: a sandbox preset of either build in the shared folder would be the other's too.
function Build.presetName(id)
    return "Pack " .. id .. " 41"
end

function Build.serverName(id)
    return id .. "-41"
end

-- As Build 42's enableAcceptColor and enableCancelColor colour a button (ISButton.lua:386-400 of 42.20.2).
local function colour(button, c)
    local r, g, b = c:getR(), c:getG(), c:getB()
    button:setBackgroundRGBA(r, g, b, 0.25)
    button:setBackgroundColorMouseOverRGBA(r, g, b, 0.50)
    button:setBorderRGBA(r, g, b, 1)
end

function Build.accept(button)
    colour(button, getCore():getGoodHighlitedColor())
end

function Build.cancel(button)
    colour(button, getCore():getBadHighlitedColor())
end

-- As Build 41's lists draw the selected row (ISScrollingListBox.lua:246).
function Build.drawSelection(list, x, y, w, h)
    list:drawRect(x, y, w, h, 0.3, 0.7, 0.35, 0.15)
end

function Build.drawMouseOver(list, x, y, w, h)
    list:drawRect(x, y, w, h, 0.1, 1, 1, 1)
end

return Build
