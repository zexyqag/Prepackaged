require "ISUI/ISPanel"
local Build = require "Prepackaged/Build"
local Rows = require "Prepackaged/Rows"
local Subscriptions = require "Prepackaged/Subscriptions"
local Widgets = require "Prepackaged/UI/Widgets"
local Workshop = require "Prepackaged/Workshop"

local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local FONT_HGT_LARGE = getTextManager():getFontHeight(UIFont.Large)
local UI_BORDER_SPACING = 10
local BUTTON_HGT = FONT_HGT_SMALL + 6

local SubscriptionsWindow = ISPanel:derive("PrepackagedSubscriptionsWindow")

function SubscriptionsWindow:new(x, y, width, height, owner, entry)
    local o = ISPanel.new(self, x, y, width, height)
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.9 }
    o.borderColor = { r = 1, g = 1, b = 1, a = 0.2 }
    o.owner = owner
    o.entry = entry
    o.tree = Subscriptions.tree(entry.result.pack)
    o.status = ""
    return o
end

function SubscriptionsWindow:createChildren()
    local top = UI_BORDER_SPACING * 2 + FONT_HGT_LARGE + FONT_HGT_SMALL + UI_BORDER_SPACING
    local bottom = self.height - UI_BORDER_SPACING - BUTTON_HGT
    self.list = Widgets.RowList:new(UI_BORDER_SPACING, top, self.width - UI_BORDER_SPACING * 2, bottom - UI_BORDER_SPACING - top)
    self.list:initialise()
    self.list:instantiate()
    self.list:setOnOpen(self, self.onOpen)
    self:addChild(self.list)

    self.backButton = Widgets.button(self, UI_BORDER_SPACING, bottom, { getText("UI_btn_back") }, self.onBack)
    Build.cancel(self.backButton)
    self.refreshButton = Widgets.button(self, 0, bottom, { getText("UI_Prepackaged_Refresh") }, self.refresh)
    self.refreshButton:setX(self.width - UI_BORDER_SPACING - self.refreshButton.width)
    self:refresh()
end

function SubscriptionsWindow:prerender()
    ISPanel.prerender(self)
    self:drawText(getText("UI_Prepackaged_SubsTitle", Rows.name(self.entry.result.pack)), UI_BORDER_SPACING, UI_BORDER_SPACING, 1, 1, 1, 1, UIFont.Large)
    self:drawText(self.status, UI_BORDER_SPACING, UI_BORDER_SPACING + FONT_HGT_LARGE + UI_BORDER_SPACING / 2, 0.8, 0.8, 0.8, 1, UIFont.Small)
end

-- Rows are made at the start and once Steam has answered every batch; in between only the status counts.
function SubscriptionsWindow:refresh()
    if self.query ~= nil then
        self.query.stop()
    end
    local steam = getSteamModeActive()
    local result = Subscriptions.start(self.tree, steam)
    self.result = result
    self:show()
    if steam then
        local installed = Workshop.installed()
        self.query = Workshop.query(self.tree.ids, function(batch, status, details)
            Subscriptions.answer(result, batch, status, details, installed)
            if result.answered == result.asked then
                self:show()
            else
                self:showStatus()
            end
        end)
    end
end

function SubscriptionsWindow:showStatus()
    local status = Subscriptions.status(self.result)
    self.status = getText(status.key, unpack(status.args))
end

function SubscriptionsWindow:show()
    self:showStatus()
    self.list:setRows(Rows.subscriptions(self.tree, self.result, isSteamOverlayEnabled()))
end

function SubscriptionsWindow:onOpen(row)
    if Workshop.open(row.open) == "overlay" then
        self.status = getText("UI_Prepackaged_SubsOpened", row.name)
    else
        self.status = getText("UI_Prepackaged_SubsCopied", row.name, Workshop.PAGE .. row.open)
    end
end

-- Answers that come later do nothing: the query is stopped.
function SubscriptionsWindow:onBack()
    if self.query ~= nil then
        self.query.stop()
    end
    self:setVisible(false)
    self:removeFromUIManager()
    self.owner:onSubscriptionsClosed()
end

function SubscriptionsWindow.open(owner, entry)
    local window = SubscriptionsWindow:new(owner.x, owner.y, owner.width, owner.height, owner, entry)
    window:initialise()
    window:addToUIManager()
    return window
end

return SubscriptionsWindow
