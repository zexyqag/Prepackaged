require "ISUI/ISButton"
local Discovery = require "Prepackaged/Discovery"
local Enable = require "Prepackaged/Enable"
local Files = require "Prepackaged/Files"
local PackWindow = require "Prepackaged/UI/PackWindow"

local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local UI_BORDER_SPACING = 10
local BUTTON_HGT = FONT_HGT_SMALL + 6
local TITLES = { "UI_Prepackaged_Button", "UI_Prepackaged_ButtonUpdate" }

local followsClass = false

local function hasUpdate()
    local state = Files.loadState()
    local current = Discovery.current(state)
    return current ~= nil and Discovery.isUpdate(current, state)
end

-- Worked out here and kept, so showing the menu never reads a pack file.
local function refreshTitle()
    local button = MainScreen.instance and MainScreen.instance.prepackagedButton
    if button ~= nil then
        local ok, update = pcall(hasUpdate)
        button:setTitle(getText(TITLES[ok and update and 2 or 1]))
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

local function onResetLua(reason)
    if reason == Enable.RESET_REASON then
        openWindow()
    end
end

local function onModsModified()
    refreshTitle()
    if PackWindow.instance ~= nil then
        PackWindow.instance:onModsModified()
    end
end

Events.OnMainMenuEnter.Add(addButton)
Events.OnResetLua.Add(onResetLua)
Events.OnModsModified.Add(onModsModified)
