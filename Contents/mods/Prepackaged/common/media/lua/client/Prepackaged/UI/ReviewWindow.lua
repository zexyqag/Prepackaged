require "ISUI/ISPanel"
require "ISUI/ISTextBox"
local Build = require "Prepackaged/Build"
local Discovery = require "Prepackaged/Discovery"
local Enable = require "Prepackaged/Enable"
local Files = require "Prepackaged/Files"
local ModList = require "Prepackaged/ModList"
local Rows = require "Prepackaged/Rows"
local SubscriptionsWindow = require "Prepackaged/UI/SubscriptionsWindow"
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
    Build.cancel(self.backButton)
    local x = self.backButton:getRight() + UI_BORDER_SPACING
    if Build.MOD_LIST_PRESETS then
        self.presetButton = Widgets.button(self, x, bottom, { getText("UI_Prepackaged_SavePreset") }, self.onPreset)
        x = self.presetButton:getRight() + UI_BORDER_SPACING
    end
    self.subscriptionsButton = Widgets.button(self, x, bottom, { getText("UI_Prepackaged_Subscriptions") }, self.onSubscriptions)
    self.applyButton = Widgets.button(self, 0, bottom, { getText("UI_Prepackaged_Apply") }, self.onApply)
    self.applyButton:setX(self.width - UI_BORDER_SPACING - self.applyButton.width)
    Build.accept(self.applyButton)
    self:update()
end

function ReviewWindow:prerender()
    ISPanel.prerender(self)
    self:drawText(getText("UI_Prepackaged_ReviewTitle"), UI_BORDER_SPACING, UI_BORDER_SPACING, 1, 1, 1, 1, UIFont.Large)
    self:drawText(self.notice, UI_BORDER_SPACING, UI_BORDER_SPACING + FONT_HGT_LARGE + UI_BORDER_SPACING / 2, 0.8, 0.8, 0.8, 1, UIFont.Small)
end

-- Also when mods are subscribed or updated, so Apply never uses a plan made before.
function ReviewWindow:update()
    local pack = self.entry.result.pack
    self.plan = Enable.plan(self.entry, self.state, self.ticks)
    self.list:setRows(Rows.review(self.plan, pack, self.state, { pack = Rows.name(pack), of = Enable.nameOf }))
    self.subscriptionsButton:setVisible(#self.plan.missing > 0)
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
    if Files.savePreset(name, self.plan.mods) then
        self.notice = getText("UI_Prepackaged_PresetSaved", name)
    else
        self.notice = getText("UI_Prepackaged_PresetFailed", Files.PRESET_COPY)
    end
end

function ReviewWindow:onSubscriptions()
    self:setVisible(false)
    SubscriptionsWindow.open(self, self.entry)
end

function ReviewWindow:onSubscriptionsClosed()
    self:setVisible(true)
end

function ReviewWindow:close(applied)
    self:setVisible(false)
    self:removeFromUIManager()
    self.owner:onReviewClosed(applied)
end

function ReviewWindow:onBack()
    self:close(false)
end

local function version(entry)
    return entry.result.pack.version or getText("UI_Prepackaged_NoVersion")
end

function ReviewWindow:onApply()
    local left = #self.plan.missing + #self.plan.unavailable
    if left > 0 then
        local lines = { getText("UI_Prepackaged_AskIncomplete", left, #self.entry.result.pack.mods), getText("UI_Prepackaged_AskApplyAnyway") }
        Widgets.ask(lines, self, self.checkReplace)
    else
        self:checkReplace()
    end
end

function ReviewWindow:checkReplace()
    local replaced = self.entry.source == "clipboard" and Discovery.replaced(self.entry)
    if replaced then
        local lines = {
            getText("UI_Prepackaged_AskReplace", Files.PACKS .. "/" .. replaced.name),
            getText("UI_Prepackaged_AskReplaceVersions", version(replaced), version(self.entry)),
        }
        Widgets.ask(lines, self, self.commit)
    else
        self:commit()
    end
end

function ReviewWindow:commit()
    local result = Enable.apply(self.entry, self.plan, self.state)
    if result.reloaded then
        return
    end
    self:close(result.error == nil)
    if result.error ~= nil then
        Widgets.tell({ getText(result.error, unpack(result.args)) })
    end
end

function ReviewWindow.open(owner, entry, state)
    local window = ReviewWindow:new(owner.x, owner.y, owner.width, owner.height, owner, entry, state)
    window:initialise()
    window:addToUIManager()
    return window
end

return ReviewWindow
