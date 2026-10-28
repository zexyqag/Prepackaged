-- What Prepackaged does differently on each build of the game: this is Build 42's, and 41/ holds Build 41's. The rest
-- of Prepackaged is in common/.
local Build = {}

Build.NUMBER = 42
-- Prepackaged's folder in Zomboid/Lua. Both builds use the same Zomboid folder.
Build.FOLDER = "Prepackaged"
-- The key binds file, and the mod options file of PZAPI.ModOptions.
Build.KEYS = "keysB42.ini"
Build.OPTIONS = "ModOptions.ini"
-- The Mods screen keeps presets of mod lists.
Build.MOD_LIST_PRESETS = true
-- Pack files put in Prepackaged's packs folder by hand are found.
Build.DROPPED_PACKS = true
Build.TICK = "media/ui/inventoryPanes/Tickbox_Tick.png"

-- The file the game reads the binds from: keys.ini while there is no keysB42.ini (MainOptions.lua:3520-3525).
function Build.keysSource()
    if cacheFileExists("keys.ini") and not cacheFileExists(Build.KEYS) then
        return "keys.ini"
    end
    return Build.KEYS
end

-- The names of the files in a folder of Zomboid/Lua.
function Build.list(folder)
    local names = {}
    local found = listFilesInZomboidLuaDirectory(folder)
    for i = 0, found:size() - 1 do
        names[#names + 1] = found:get(i)
    end
    return names
end

-- Called with each file Prepackaged writes: a build that can list folders needs nothing.
function Build.written(path)
end

-- A mod's loadModAfter and loadModBefore, as mod.info gives them.
function Build.loadOrder(info)
    return info and info:getLoadAfter(), info and info:getLoadBefore()
end

-- Whether the game can hold a bind: every bind here.
function Build.bindFits(bind)
    return true
end

-- A bind on its button, as the options screen shows it.
function Build.showBind(t)
    if t.btn ~= nil and type(MainOptions.getKeyPrefix) == "function" then
        t.btn:setTitle(MainOptions.getKeyPrefix(t) .. getKeyName(t.keyCode))
    end
end

-- A bind in the game's key map, as saveKeys adds it.
function Build.addBind(t)
    getCore():addKeyBinding(t.txt:getName(), t.keyCode, t.altCode, t.shift or false, t.ctrl or false, t.alt or false)
end

-- The server name checks besides isValidName.
function Build.nameFits(manager, name)
    return manager:settingsFolderValidLengthChecks(name)
end

-- What Prepackaged names for a pack in the folders both builds share.
function Build.presetName(id)
    return "Pack " .. id
end

function Build.serverName(id)
    return id
end

function Build.accept(button)
    button:enableAcceptColor()
end

function Build.cancel(button)
    button:enableCancelColor()
end

function Build.drawSelection(list, x, y, w, h)
    list:drawSelection(x, y, w, h)
end

function Build.drawMouseOver(list, x, y, w, h)
    list:drawMouseOverHighlight(x, y, w, h)
end

return Build
