require "ISUI/ISPanel"
local Backup = require "Prepackaged/Backup"
local Enable = require "Prepackaged/Enable"
local Files = require "Prepackaged/Files"
local Rows = require "Prepackaged/Rows"
local Settings = require "Prepackaged/Settings"
local Widgets = require "Prepackaged/UI/Widgets"

local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local FONT_HGT_LARGE = getTextManager():getFontHeight(UIFont.Large)
local UI_BORDER_SPACING = 10
local BUTTON_HGT = FONT_HGT_SMALL + 6

local RestoreWindow = ISPanel:derive("PrepackagedRestoreWindow")

function RestoreWindow:new(x, y, width, height, owner, state)
    local o = ISPanel.new(self, x, y, width, height)
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.9 }
    o.borderColor = { r = 1, g = 1, b = 1, a = 0.2 }
    o.owner = owner
    o.state = state
    return o
end

function RestoreWindow:createChildren()
    local top = UI_BORDER_SPACING * 2 + FONT_HGT_LARGE + FONT_HGT_SMALL + UI_BORDER_SPACING
    local bottom = self.height - UI_BORDER_SPACING - BUTTON_HGT
    local height = bottom - UI_BORDER_SPACING - top
    local listWidth = math.floor((self.width - UI_BORDER_SPACING * 3) * 0.4)
    self.list = Widgets.PackList:new(UI_BORDER_SPACING, top, listWidth, height)
    self.list:initialise()
    self.list:instantiate()
    self.list:setOnMouseDownFunction(self, self.onSelect)
    self:addChild(self.list)
    local detailsX = self.list:getRight() + UI_BORDER_SPACING
    self.details = Widgets.RowList:new(detailsX, top, self.width - detailsX - UI_BORDER_SPACING, height)
    self.details:initialise()
    self.details:instantiate()
    self:addChild(self.details)

    self.backButton = Widgets.button(self, UI_BORDER_SPACING, bottom, { getText("UI_btn_back") }, self.onBack)
    self.backButton:enableCancelColor()
    self.restoreButton = Widgets.button(self, 0, bottom, { getText("UI_Prepackaged_RestoreThis") }, self.onRestore)
    self.restoreButton:setX(self.width - UI_BORDER_SPACING - self.restoreButton.width)
    self.restoreButton:enableAcceptColor()
    self:refresh()
end

function RestoreWindow:prerender()
    ISPanel.prerender(self)
    self:drawText(getText("UI_Prepackaged_RestoreTitle"), UI_BORDER_SPACING, UI_BORDER_SPACING, 1, 1, 1, 1, UIFont.Large)
    self:drawText(getText("UI_Prepackaged_RestoreKept", Backup.KEEP), UI_BORDER_SPACING, UI_BORDER_SPACING + FONT_HGT_LARGE + UI_BORDER_SPACING / 2, 0.8, 0.8, 0.8, 1, UIFont.Small)
end

function RestoreWindow:refresh()
    for _, backup in ipairs(Backup.merge(Files.backups(), Files.fileBackups())) do
        local head, detail = Rows.backupTitle(backup), Rows.backupDetail(backup)
        local data = { backup = backup, title = getText(head.key, unpack(head.args)), detail = getText(detail.key, unpack(detail.args)) }
        self.list:addItem(data.title, data)
    end
    self.list.selected = 1
    self:onSelect(self.list.items[1] and self.list.items[1].item)
end

function RestoreWindow:onSelect(data)
    self.backup = data and data.backup
    if self.backup == nil then
        self.details:setRows({ { style = "note", key = "UI_Prepackaged_NoBackups", args = {} } })
    else
        self.details:setRows(Rows.backup(self.backup, Enable.nameOf))
    end
    self.restoreButton:setEnable(self.backup ~= nil)
end

function RestoreWindow:close()
    self:setVisible(false)
    self:removeFromUIManager()
    self.owner:onRestoreClosed()
end

function RestoreWindow:onBack()
    self:close()
end

function RestoreWindow:onRestore()
    if self.backup.kind == "files" then
        Widgets.ask({ getText("UI_Prepackaged_AskRestoreFiles"), getText("UI_Prepackaged_AskRestoreFilesBackup") }, self, self.commit)
    else
        Widgets.ask({ getText("UI_Prepackaged_AskRestore", #self.backup.mods), getText("UI_Prepackaged_AskRestoreBackup") }, self, self.commit)
    end
end

function RestoreWindow:commit()
    local result
    if self.backup.kind == "files" then
        result = Settings.restore(self.backup)
    else
        result = Enable.restore(self.backup, self.state)
    end
    if result.reloaded then
        return
    end
    self:close()
    if result.error ~= nil then
        Widgets.tell({ getText(result.error, unpack(result.args)) })
    end
end

function RestoreWindow.open(owner, state)
    local window = RestoreWindow:new(owner.x, owner.y, owner.width, owner.height, owner, state)
    window:initialise()
    window:addToUIManager()
    return window
end

return RestoreWindow
