require "ISUI/ISPanel"
local Build = require "Prepackaged/Build"
local DefaultsWindow = require "Prepackaged/UI/DefaultsWindow"
local Discovery = require "Prepackaged/Discovery"
local Enable = require "Prepackaged/Enable"
local Files = require "Prepackaged/Files"
local RestoreWindow = require "Prepackaged/UI/RestoreWindow"
local ReviewWindow = require "Prepackaged/UI/ReviewWindow"
local Rows = require "Prepackaged/Rows"
local SandboxScreen = require "Prepackaged/SandboxScreen"
local ServerWindow = require "Prepackaged/UI/ServerWindow"
local Settings = require "Prepackaged/Settings"
local SubscriptionsWindow = require "Prepackaged/UI/SubscriptionsWindow"
local Widgets = require "Prepackaged/UI/Widgets"

local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local FONT_HGT_LARGE = getTextManager():getFontHeight(UIFont.Large)
local UI_BORDER_SPACING = 10
local BUTTON_HGT = FONT_HGT_SMALL + 6

local PackWindow = ISPanel:derive("PrepackagedPackWindow")

local function size(total, fraction, minimum)
    return math.floor(math.min(total - UI_BORDER_SPACING * 2, math.max(minimum, total * fraction)))
end

-- The bottom row from the left, as field, text and handler; Use stays at the right.
local LEFT = { { "backButton", "UI_btn_back", "onBack" }, { "pasteButton", "UI_Prepackaged_Paste", "onPaste" },
    { "restoreButton", "UI_Prepackaged_Restore", "onRestore" }, { "defaultsButton", "UI_Prepackaged_Defaults", "onDefaults" },
    { "subscriptionsButton", "UI_Prepackaged_Subscriptions", "onSubscriptions" }, { "serverButton", "UI_Prepackaged_Server", "onServer" } }
local RIGHT = { "UI_Prepackaged_Use", "UI_Prepackaged_Update" }

-- At least as wide as its row of buttons.
local function minimumWidth()
    local width = Widgets.width(RIGHT) + UI_BORDER_SPACING * 2
    for _, b in ipairs(LEFT) do
        width = width + Widgets.width({ b[2] }) + UI_BORDER_SPACING
    end
    return math.max(800, width)
end

function PackWindow:new(x, y, width, height, onClose)
    local o = ISPanel.new(self, x, y, width, height)
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.9 }
    o.borderColor = { r = 1, g = 1, b = 1, a = 0.2 }
    o.status = ""
    o.onClose = onClose
    return o
end

function PackWindow:createChildren()
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

    local x = UI_BORDER_SPACING
    for _, b in ipairs(LEFT) do
        self[b[1]] = Widgets.button(self, x, bottom, { getText(b[2]) }, self[b[3]])
        x = self[b[1]]:getRight() + UI_BORDER_SPACING
    end
    Build.cancel(self.backButton)
    self.useButton = Widgets.button(self, 0, bottom, { getText(RIGHT[1]), getText(RIGHT[2]) }, self.onUse)
    self.useButton:setX(self.width - UI_BORDER_SPACING - self.useButton.width)
    Build.accept(self.useButton)
    self:refresh()
end

function PackWindow:prerender()
    ISPanel.prerender(self)
    self:drawText(getText("UI_Prepackaged_Title"), UI_BORDER_SPACING, UI_BORDER_SPACING, 1, 1, 1, 1, UIFont.Large)
    self:drawText(self.status, UI_BORDER_SPACING, UI_BORDER_SPACING + FONT_HGT_LARGE + UI_BORDER_SPACING / 2, 0.8, 0.8, 0.8, 1, UIFont.Small)
end

local function isCurrent(entry, state)
    local source = state.source
    return source ~= nil and entry.source == source.kind and entry.name == source.name and entry.result.pack.id == state.current
end

local function sameSource(a, b)
    return a.source == b.source and a.name == b.name
end

function PackWindow:statusText(current)
    local state = self.state
    local applied = state.applied or getText("UI_Prepackaged_NoVersion")
    if state.current == nil then
        return getText("UI_Prepackaged_NoCurrent")
    elseif current == nil then
        return getText("UI_Prepackaged_CurrentGone", state.current, applied)
    elseif Discovery.isUpdate(current, state) then
        return getText("UI_Prepackaged_CurrentUpdate", Rows.name(current.result.pack), applied, current.result.pack.version)
    end
    return getText("UI_Prepackaged_Current", Rows.name(current.result.pack), applied)
end

local function found(window)
    local entries = Discovery.all()
    if window.pasted ~= nil then
        entries[#entries + 1] = window.pasted
    end
    return entries
end

function PackWindow:refresh(wanted)
    self.state = Files.loadState()
    local entries = found(self)
    self.list:clear()
    local current, selected = nil, 1
    for i, entry in ipairs(entries) do
        local pack = entry.result.pack
        local data = { entry = entry, title = Rows.name(pack) or getText("UI_Prepackaged_NoName") }
        if pack.version ~= nil then
            data.title = data.title .. " " .. getText("UI_Prepackaged_Version", pack.version)
        end
        local source = Rows.source(entry)
        data.detail = getText(source.key, unpack(source.args))
        if #entry.result.errors > 0 then
            data.color = "bad"
        elseif isCurrent(entry, self.state) then
            data.color = "good"
            data.detail = getText("UI_Prepackaged_ListInUse", data.detail)
            current = entry
        end
        self.list:addItem(data.title, data)
        if (wanted ~= nil and sameSource(entry, wanted)) or (wanted == nil and entry == current) then
            selected = i
        end
    end
    self.status = self:statusText(current)
    self.current = current
    local ok, waiting = pcall(Settings.waiting, current, self.state)
    if ok and waiting > 0 then
        self.status = getText("UI_Prepackaged_StatusDefaults", self.status, waiting)
    end
    self.defaultsButton:setEnable(Settings.applies(current, self.state))
    self.list.selected = selected
    self:onSelect(self.list.items[selected] and self.list.items[selected].item)
end

function PackWindow:onSelect(data)
    self.entry = data and data.entry
    if self.entry == nil then
        self.details:setRows({ { style = "note", key = Build.DROPPED_PACKS and "UI_Prepackaged_NoPacks" or "UI_Prepackaged_NoPacksPaste", args = { Build.FOLDER .. "/packs" } } })
        self.useButton:setEnable(false)
        self.subscriptionsButton:setEnable(false)
        self.serverButton:setEnable(false)
        return
    end
    local pack = self.entry.result.pack
    self.subscriptionsButton:setEnable(#pack.workshopItems + #pack.collection + #pack.collections > 0)
    local ok, check = pcall(Settings.check, self.entry)
    local okSandbox, sandbox = pcall(SandboxScreen.check, self.entry, self.state)
    self.details:setRows(Rows.details(self.entry, self.state, Enable.packConflicts(self.entry), Enable.nameOf, ok and check or nil, okSandbox and sandbox or nil))
    self.useButton:setEnable(#self.entry.result.errors == 0)
    self.serverButton:setEnable(#self.entry.result.errors == 0)
    self.useButton:setTitle(getText(Discovery.isUpdate(self.entry, self.state) and "UI_Prepackaged_Update" or "UI_Prepackaged_Use"))
end

function PackWindow:onPaste()
    local entry = Discovery.fromClipboard()
    if entry == nil then
        Widgets.tell({ getText("UI_Prepackaged_ClipboardEmpty"), getText("UI_Prepackaged_ClipboardHow") })
        return
    end
    local listed = Discovery.sameAs(found(self), entry)
    if listed ~= nil then
        self:refresh(listed)
        self.status = getText("UI_Prepackaged_AlreadyListed")
        return
    end
    self.pasted = entry
    self:refresh(entry)
end

function PackWindow:onUse()
    self:setVisible(false)
    self.review = ReviewWindow.open(self, self.entry, self.state)
end

-- A pasted pack that was applied is a file now. Without a reload the pack's defaults can be reviewed at once.
function PackWindow:onReviewClosed(applied)
    self.review = nil
    self:setVisible(true)
    if applied then
        self.pasted = nil
        pcall(SandboxScreen.ensurePreset)
        self:refresh()
        self:offerDefaults()
    else
        self:refresh(self.entry)
    end
end

-- Right after using a pack: the review opens by itself when something waits.
function PackWindow:offerDefaults()
    local ok, waiting = pcall(Settings.waiting, self.current, self.state)
    if ok and waiting > 0 then
        self:onDefaults()
    end
end

function PackWindow:onDefaults()
    self:setVisible(false)
    self.defaults = DefaultsWindow.open(self, self.current)
end

function PackWindow:onDefaultsClosed(result)
    self.defaults = nil
    self:setVisible(true)
    self:refresh(self.entry)
    if result == nil then
        return
    elseif result.error ~= nil then
        Widgets.tell({ getText(result.error, unpack(result.args)) })
    elseif result.changed > 0 then
        self.status = getText("UI_Prepackaged_DefaultsDone", result.changed)
    end
end

function PackWindow:onSubscriptions()
    self:setVisible(false)
    SubscriptionsWindow.open(self, self.entry)
end

function PackWindow:onSubscriptionsClosed()
    self:setVisible(true)
end

function PackWindow:onServer()
    self:setVisible(false)
    ServerWindow.open(self, self.entry)
end

-- A server set up without a reload: the Host screen shows it, in place of this window.
function PackWindow:onServerClosed(job)
    if job == nil then
        self:setVisible(true)
        return
    end
    self:onBack()
    ServerWindow.finished(job)
end

function PackWindow:onRestore()
    self:setVisible(false)
    RestoreWindow.open(self, self.state)
end

function PackWindow:onRestoreClosed(job)
    if job ~= nil then
        self:onServerClosed(job)
        return
    end
    self:setVisible(true)
    self:refresh(self.entry)
end

-- The game has looked at the mod folders again (ZomboidFileSystem.java:1302-1319): mods may be installed or gone.
function PackWindow:onModsModified()
    if self.review ~= nil then
        self.review:update()
    end
    if self.defaults ~= nil then
        self.defaults:update()
    end
    self:refresh(self.entry)
end

function PackWindow:onBack()
    self:setVisible(false)
    self:removeFromUIManager()
    PackWindow.instance = nil
    MainScreen.instance.bottomPanel:setVisible(true)
    self.onClose()
end

function PackWindow.open(onClose)
    if PackWindow.instance ~= nil then
        return
    end
    local screenW, screenH = getCore():getScreenWidth(), getCore():getScreenHeight()
    local width, height = size(screenW, 0.6, minimumWidth()), size(screenH, 0.7, 500)
    local window = PackWindow:new((screenW - width) / 2, (screenH - height) / 2, width, height, onClose)
    window:initialise()
    window:addToUIManager()
    PackWindow.instance = window
    MainScreen.instance.bottomPanel:setVisible(false)
end

return PackWindow
