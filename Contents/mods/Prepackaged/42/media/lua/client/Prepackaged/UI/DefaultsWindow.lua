require "ISUI/ISPanel"
local Defaults = require "Prepackaged/Defaults"
local Files = require "Prepackaged/Files"
local Rows = require "Prepackaged/Rows"
local Settings = require "Prepackaged/Settings"
local Widgets = require "Prepackaged/UI/Widgets"

local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local FONT_HGT_LARGE = getTextManager():getFontHeight(UIFont.Large)
local UI_BORDER_SPACING = 10
local BUTTON_HGT = FONT_HGT_SMALL + 6

local DefaultsWindow = ISPanel:derive("PrepackagedDefaultsWindow")

function DefaultsWindow:new(x, y, width, height, owner, entry)
    local o = ISPanel.new(self, x, y, width, height)
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.9 }
    o.borderColor = { r = 1, g = 1, b = 1, a = 0.2 }
    o.owner = owner
    o.entry = entry
    o.all = false
    -- The player's own ticks, by entry, kept when the rows are made again.
    o.choices = {}
    return o
end

function DefaultsWindow:createChildren()
    local top = UI_BORDER_SPACING * 2 + FONT_HGT_LARGE + FONT_HGT_SMALL + UI_BORDER_SPACING
    local bottom = self.height - UI_BORDER_SPACING - BUTTON_HGT
    self.list = Widgets.RowList:new(UI_BORDER_SPACING, top, self.width - UI_BORDER_SPACING * 2, bottom - UI_BORDER_SPACING - top)
    self.list:initialise()
    self.list:instantiate()
    self.list:setOnTick(self, self.onTick)
    self:addChild(self.list)

    self.backButton = Widgets.button(self, UI_BORDER_SPACING, bottom, { getText("UI_Prepackaged_NotNow") }, self.onBack)
    self.backButton:enableCancelColor()
    self.allButton = Widgets.button(self, self.backButton:getRight() + UI_BORDER_SPACING, bottom, { getText("UI_Prepackaged_ShowAll"), getText("UI_Prepackaged_ShowNew") }, self.onAll)
    self.applyButton = Widgets.button(self, 0, bottom, { getText("UI_Prepackaged_Apply") }, self.onApply)
    self.applyButton:setX(self.width - UI_BORDER_SPACING - self.applyButton.width)
    self.applyButton:enableAcceptColor()
    self:update()
end

function DefaultsWindow:prerender()
    ISPanel.prerender(self)
    self:drawText(getText("UI_Prepackaged_DefaultsTitle"), UI_BORDER_SPACING, UI_BORDER_SPACING, 1, 1, 1, 1, UIFont.Large)
    self:drawText(getText("UI_Prepackaged_DefaultsSubtitle"), UI_BORDER_SPACING, UI_BORDER_SPACING + FONT_HGT_LARGE + UI_BORDER_SPACING / 2, 0.8, 0.8, 0.8, 1, UIFont.Small)
end

local function choice(item)
    return item.kind .. "\n" .. item.key
end

-- The game is read again each time, so Apply never uses values from before.
function DefaultsWindow:update()
    self.state = Files.loadState()
    self.review, self.targets = Settings.review(self.entry, self.state, self.all)
    self.ticks = Defaults.ticks(self.review)
    for _, item in ipairs(self.review.rows) do
        local chosen = self.choices[choice(item)]
        if chosen ~= nil then
            self.ticks[item] = chosen or nil
        end
    end
    self:show()
end

function DefaultsWindow:show()
    local clashes = Defaults.clashes(self.targets, self.review, self.ticks)
    self.list:setRows(Rows.defaults(self.review, self.ticks, clashes, Settings.names(self.entry.result.pack)))
end

function DefaultsWindow:onTick(row)
    local ticked = not self.ticks[row.item]
    self.ticks[row.item] = ticked or nil
    self.choices[choice(row.item)] = ticked
    self:show()
end

function DefaultsWindow:onAll()
    self.all = not self.all
    self.allButton:setTitle(getText(self.all and "UI_Prepackaged_ShowNew" or "UI_Prepackaged_ShowAll"))
    self:update()
end

function DefaultsWindow:close(result)
    self:setVisible(false)
    self:removeFromUIManager()
    self.owner:onDefaultsClosed(result)
end

-- Not now: nothing is written, and every row waits.
function DefaultsWindow:onBack()
    self:close(nil)
end

function DefaultsWindow:onApply()
    self:close(Settings.apply(self.entry, self.state, self.review, self.ticks))
end

function DefaultsWindow.open(owner, entry)
    local window = DefaultsWindow:new(owner.x, owner.y, owner.width, owner.height, owner, entry)
    window:initialise()
    window:addToUIManager()
    return window
end

return DefaultsWindow
