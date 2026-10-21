require "ISUI/ISButton"
local Backup = require "Prepackaged/Backup"
local Discovery = require "Prepackaged/Discovery"
local Enable = require "Prepackaged/Enable"
local Files = require "Prepackaged/Files"
local Host = require "Prepackaged/Host"
local PackWindow = require "Prepackaged/UI/PackWindow"
local SandboxScreen = require "Prepackaged/SandboxScreen"
local ServerWindow = require "Prepackaged/UI/ServerWindow"
local Settings = require "Prepackaged/Settings"

local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local UI_BORDER_SPACING = 10
local BUTTON_HGT = FONT_HGT_SMALL + 6
local TITLES = { "UI_Prepackaged_Button", "UI_Prepackaged_ButtonUpdate", "UI_Prepackaged_ButtonDefaults" }

local followsClass = false

local function titleOf()
    local state = Files.loadState()
    local current = Discovery.current(state)
    if current ~= nil and Discovery.isUpdate(current, state) then
        return 2
    elseif Settings.waiting(current, state) > 0 then
        return 3
    end
    return 1
end

-- Worked out here and kept, so showing the menu never reads a pack file.
local function refreshTitle()
    local button = MainScreen.instance and MainScreen.instance.prepackagedButton
    if button ~= nil then
        local ok, index = pcall(titleOf)
        button:setTitle(getText(TITLES[ok and index or 1]))
    end
end

local function openWindow()
    PackWindow.open(refreshTitle)
end

-- The button shows and hides with vanilla's corner buttons (MainScreen.setBottomPanelVisible, MainScreen.lua:28-44).
-- Vanilla's function runs as before, and nothing of ours may raise inside it.
local function follow(setVisible)
    return function(panel, visible)
        setVisible(panel, visible)
        pcall(function()
            local button = panel.parent and panel.parent.prepackagedButton
            if button ~= nil then
                button:setVisible(visible)
            end
        end)
    end
end

local function addButton()
    local screen = MainScreen.instance
    if screen == nil or screen.prepackagedButton ~= nil then
        return
    end
    local below = screen.resetLua or screen.termsOfService or screen.reportBug
    if below == nil then
        print("[Prepackaged] WARNING: the main menu has none of the corner buttons the Prepackaged button goes above")
        return
    end
    local width = below.width
    for _, key in ipairs(TITLES) do
        width = math.max(width, getTextManager():MeasureStringX(UIFont.Small, getText(key)) + UI_BORDER_SPACING * 2)
    end
    local button = ISButton:new(below:getRight() - width, below.y - UI_BORDER_SPACING - BUTTON_HGT, width, BUTTON_HGT, getText(TITLES[1]), nil, openWindow)
    button:initialise()
    button.borderColor = { r = 1, g = 1, b = 1, a = 0.7 }
    button.textColor = { r = 1, g = 1, b = 1, a = 0.7 }
    button:setAnchorLeft(false)
    button:setAnchorTop(false)
    button:setAnchorRight(true)
    button:setAnchorBottom(true)
    -- Vanilla may hide the menu before this runs, as for +connect (MainScreen.lua:1808).
    local panel = screen.bottomPanel
    button:setVisible(panel:isVisible())
    screen:addChild(button)
    screen.prepackagedButton = button
    -- The class function too: a mod that sets the panel's back to it keeps the button in step.
    if not followsClass and type(MainScreen.setBottomPanelVisible) == "function" then
        MainScreen.setBottomPanelVisible = follow(MainScreen.setBottomPanelVisible)
        followsClass = true
    end
    panel.setVisible = follow(panel.setVisible)
    refreshTitle()
end

-- Vanilla's handler, registered before any mod's, has made the sandbox screen (MainScreen.lua:716, 2178).
local function onMainMenuEnter()
    addButton()
    pcall(SandboxScreen.add)
    pcall(SandboxScreen.ensurePreset)
end

-- The reload after using a pack is the first time its mods' options exist, so their review opens by itself, once.
local function onResetLua(reason)
    if reason == Host.RELOAD then
        Host.resume()
    elseif reason == Host.DONE then
        ServerWindow.finished(Host.done())
    end
    if reason == Enable.RESET_REASON or reason == Backup.RESET_REASON then
        openWindow()
    end
    if reason == Enable.RESET_REASON and PackWindow.instance ~= nil then
        PackWindow.instance:offerDefaults()
    end
end

local function onModsModified()
    refreshTitle()
    if PackWindow.instance ~= nil then
        PackWindow.instance:onModsModified()
    end
end

Events.OnMainMenuEnter.Add(onMainMenuEnter)
Events.OnResetLua.Add(onResetLua)
Events.OnModsModified.Add(onModsModified)
