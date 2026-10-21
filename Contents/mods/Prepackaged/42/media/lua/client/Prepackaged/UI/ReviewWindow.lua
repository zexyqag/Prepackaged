-- The review of a pack's mod list before anything changes: optional mods to tick, Save as my preset, Apply.
require "ISUI/ISPanel"
require "ISUI/ISTextBox"
local Enable = require "Prepackaged/Enable"
local Files = require "Prepackaged/Files"
local ModList = require "Prepackaged/ModList"
local Rows = require "Prepackaged/Rows"
local Widgets = require "Prepackaged/UI/Widgets"

local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local FONT_HGT_LARGE = getTextManager():getFontHeight(UIFont.Large)
local UI_BORDER_SPACING = 10
local BUTTON_HGT = FONT_HGT_SMALL + 6

local ReviewWindow = ISPanel:derive("PrepackagedReviewWindow")

function ReviewWindow:new(x, y, width, height, owner, entry, state)
    local o = ISPanel.new(self, x, y, width, height)
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.9 }
    o.borderColor = { r = 1, g = 1, b = 1, a = 0.2 }
    o.owner = owner
    o.entry = entry
    o.state = state
    o.ticks = ModList.ticks(entry.result.pack, Enable.active())
    o.notice = ""
    return o
end

function ReviewWindow:createChildren()
    local top = UI_BORDER_SPACING * 2 + FONT_HGT_LARGE + FONT_HGT_SMALL + UI_BORDER_SPACING
    local bottom = self.height - UI_BORDER_SPACING - BUTTON_HGT
    self.list = Widgets.RowList:new(UI_BORDER_SPACING, top, self.width - UI_BORDER_SPACING * 2, bottom - UI_BORDER_SPACING - top)
    self.list:initialise()
    self.list:instantiate()
    self.list:setOnTick(self, self.onTick)
    self:addChild(self.list)

    self.backButton = Widgets.button(self, UI_BORDER_SPACING, bottom, { getText("UI_btn_back") }, self.onBack)
    self.backButton:enableCancelColor()
    self.presetButton = Widgets.button(self, self.backButton:getRight() + UI_BORDER_SPACING, bottom, { getText("UI_Prepackaged_SavePreset") }, self.onPreset)
    self.applyButton = Widgets.button(self, 0, bottom, { getText("UI_Prepackaged_Apply") }, self.onApply)
    self.applyButton:setX(self.width - UI_BORDER_SPACING - self.applyButton.width)
    self.applyButton:enableAcceptColor()
    self:update()
end

function ReviewWindow:prerender()
    ISPanel.prerender(self)
    self:drawText(getText("UI_Prepackaged_ReviewTitle"), UI_BORDER_SPACING, UI_BORDER_SPACING, 1, 1, 1, 1, UIFont.Large)
    self:drawText(self.notice, UI_BORDER_SPACING, UI_BORDER_SPACING + FONT_HGT_LARGE + UI_BORDER_SPACING / 2, 0.8, 0.8, 0.8, 1, UIFont.Small)
end

function ReviewWindow:update()
    local pack = self.entry.result.pack
    self.plan = Enable.plan(self.entry, self.state, self.ticks)
    local names = { pack = Rows.name(pack), preset = Enable.backupName(pack), of = Enable.nameOf }
    self.list:setRows(Rows.review(self.plan, pack, self.state, names))
end

function ReviewWindow:onTick(row)
    self.ticks[row.id] = not row.ticked or nil
    self:update()
end

function ReviewWindow:isValidPreset(text)
    return SandboxOptions.isValidPresetName(text)
end

function ReviewWindow:onPreset()
    local w, h = 280, 180
    local name = ModList.presetName(Rows.name(self.entry.result.pack))
    local modal = ISTextBox:new((getCore():getScreenWidth() - w) / 2, (getCore():getScreenHeight() - h) / 2, w, h, getText("UI_Prepackaged_PresetPrompt"), name, self, self.onPresetName)
    modal.backgroundColor.a = 0.9
    modal:initialise()
    modal:setAlwaysOnTop(true)
    modal:setCapture(true)
    modal:setValidateFunction(self, self.isValidPreset)
    modal:addToUIManager()
    modal:bringToTop()
end

function ReviewWindow:onPresetName(button)
    if button.internal ~= "OK" then
        return
    end
    local name = button.parent.entry:getText()
    Files.savePreset(name, self.plan.mods)
    self.notice = getText("UI_Prepackaged_PresetSaved", name)
end

function ReviewWindow:close(applied)
    self:setVisible(false)
    self:removeFromUIManager()
    self.owner:onReviewClosed(applied)
end

function ReviewWindow:onBack()
    self:close(false)
end

function ReviewWindow:onApply()
    if not Enable.apply(self.entry, self.plan, self.state) then
        self:close(true)
    end
end

function ReviewWindow.open(owner, entry, state)
    local window = ReviewWindow:new(owner.x, owner.y, owner.width, owner.height, owner, entry, state)
    window:initialise()
    window:addToUIManager()
end

return ReviewWindow
