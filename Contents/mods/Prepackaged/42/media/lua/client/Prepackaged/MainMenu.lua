-- The main menu's Prepackaged button, above the buttons in the bottom right corner, shown and hidden with the menu.
require "ISUI/ISButton"
local Discovery = require "Prepackaged/Discovery"
local Enable = require "Prepackaged/Enable"
local Files = require "Prepackaged/Files"
local PackWindow = require "Prepackaged/UI/PackWindow"

local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local UI_BORDER_SPACING = 10
local BUTTON_HGT = FONT_HGT_SMALL + 6
local TITLES = { "UI_Prepackaged_Button", "UI_Prepackaged_ButtonUpdate" }

-- Says so when the pack in use has a newer version where it was found.
local function title()
    local state = Files.loadState()
    local current = Discovery.current(state)
    return getText(TITLES[current ~= nil and Discovery.isUpdate(current, state) and 2 or 1])
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
    local button = ISButton:new(below:getRight() - width, below.y - UI_BORDER_SPACING - BUTTON_HGT, width, BUTTON_HGT, title(), nil, PackWindow.open)
    button:initialise()
    button.borderColor = { r = 1, g = 1, b = 1, a = 0.7 }
    button.textColor = { r = 1, g = 1, b = 1, a = 0.7 }
    button:setAnchorLeft(false)
    button:setAnchorTop(false)
    button:setAnchorRight(true)
    button:setAnchorBottom(true)
    screen:addChild(button)
    screen.prepackagedButton = button
    -- MainScreen.setBottomPanelVisible shows and hides vanilla's corner buttons with the menu; this adds ours.
    local panel = screen.bottomPanel
    local setVisible = panel.setVisible
    panel.setVisible = function(self, visible)
        setVisible(self, visible)
        if visible then
            button:setTitle(title())
        end
        button:setVisible(visible)
    end
end

local function onResetLua(reason)
    if reason == Enable.RESET_REASON then
        PackWindow.open()
    end
end

Events.OnMainMenuEnter.Add(addButton)
Events.OnResetLua.Add(onResetLua)
