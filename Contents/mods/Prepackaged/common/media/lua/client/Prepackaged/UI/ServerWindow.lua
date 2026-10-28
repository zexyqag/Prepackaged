require "ISUI/ISPanel"
require "ISUI/ISTextBox"
local Build = require "Prepackaged/Build"
local Enable = require "Prepackaged/Enable"
local Files = require "Prepackaged/Files"
local Host = require "Prepackaged/Host"
local Rows = require "Prepackaged/Rows"
local Server = require "Prepackaged/Server"
local Widgets = require "Prepackaged/UI/Widgets"

local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local FONT_HGT_LARGE = getTextManager():getFontHeight(UIFont.Large)
local UI_BORDER_SPACING = 10
local BUTTON_HGT = FONT_HGT_SMALL + 6

local ServerWindow = ISPanel:derive("PrepackagedServerWindow")

function ServerWindow:new(x, y, width, height, owner, entry)
    local o = ISPanel.new(self, x, y, width, height)
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.9 }
    o.borderColor = { r = 1, g = 1, b = 1, a = 0.2 }
    o.owner = owner
    o.entry = entry
    o.status = ""
    return o
end

function ServerWindow:createChildren()
    local top = UI_BORDER_SPACING * 2 + FONT_HGT_LARGE + FONT_HGT_SMALL + UI_BORDER_SPACING
    local bottom = self.height - UI_BORDER_SPACING - BUTTON_HGT
    self.list = Widgets.RowList:new(UI_BORDER_SPACING, top, self.width - UI_BORDER_SPACING * 2, bottom - UI_BORDER_SPACING - top)
    self.list:initialise()
    self.list:instantiate()
    self:addChild(self.list)

    self.backButton = Widgets.button(self, UI_BORDER_SPACING, bottom, { getText("UI_btn_back") }, self.onBack)
    Build.cancel(self.backButton)
    self.copyButton = Widgets.button(self, self.backButton:getRight() + UI_BORDER_SPACING, bottom, { getText("UI_Prepackaged_LinesCopy") }, self.onCopy)
    self.hostButton = Widgets.button(self, 0, bottom, { getText("UI_Prepackaged_HostButton") }, self.onHost)
    self.hostButton:setX(self.width - UI_BORDER_SPACING - self.hostButton.width)
    Build.accept(self.hostButton)
    self:update()
end

function ServerWindow:prerender()
    ISPanel.prerender(self)
    self:drawText(getText("UI_Prepackaged_ServerTitle"), UI_BORDER_SPACING, UI_BORDER_SPACING, 1, 1, 1, 1, UIFont.Large)
    self:drawText(self.status, UI_BORDER_SPACING, UI_BORDER_SPACING + FONT_HGT_LARGE + UI_BORDER_SPACING / 2, 0.8, 0.8, 0.8, 1, UIFont.Small)
end

function ServerWindow:update()
    local pack = self.entry.result.pack
    local ok, info = pcall(Host.serverLines, self.entry)
    if not ok then
        self.info = nil
        self.list:setRows({ { style = "alert", key = "UI_Prepackaged_LinesFailed", args = { tostring(info) } } })
        self.copyButton:setEnable(false)
    else
        self.info = info
        info.hostMissing = Host.missing()
        info.reload = not Enable.loaded(pack.mods)
        info.memory = Server.memory(pack.hostmemory)
        self.list:setRows(Rows.server(info))
        self.copyButton:setEnable(true)
    end
    self.hostButton:setEnable(Host.missing() == nil)
end

-- The clipboard holds what the window shows, and the file keeps it after the clipboard changes.
function ServerWindow:onCopy()
    local info = self.info
    Clipboard.setClipboard(table.concat(info.text, "\n") .. "\n")
    if Files.write(info.path, info.text, "\r\n") then
        self.status = getText("UI_Prepackaged_LinesCopied", info.path)
    else
        self.status = getText("UI_Prepackaged_LinesCopiedOnly", info.path)
    end
end

-- The box asks on every frame (ISTextBox.updateButtons), so each text is checked once, and OK's tooltip says why not.
function ServerWindow:isValidName(text)
    if self.named ~= text then
        local check, problem = Host.prepare(text)
        self.named, self.nameOk = text, check ~= nil
        self.nameBox:setValidateTooltipText(problem)
    end
    return self.nameOk
end

function ServerWindow:onHost()
    local w, h = 280, 180
    local modal = ISTextBox:new((getCore():getScreenWidth() - w) / 2, (getCore():getScreenHeight() - h) / 2, w, h, getText("UI_Prepackaged_HostPrompt"),
        Build.serverName(self.entry.result.pack.id), self, self.onHostName)
    modal.backgroundColor.a = 0.9
    modal:initialise()
    modal:setAlwaysOnTop(true)
    modal:setCapture(true)
    self.nameBox = modal
    modal:setValidateFunction(self, self.isValidName)
    modal:addToUIManager()
    modal:bringToTop()
end

function ServerWindow:onHostName(button)
    if button.internal ~= "OK" then
        return
    end
    local check, problem = Host.prepare(button.parent.entry:getText())
    if check == nil then
        Widgets.tell({ problem })
        return
    end
    self.job = Host.packJob(self.entry, check)
    Widgets.ask(Widgets.lines(Rows.hostAsk(self.job, check)), self, self.commit)
end

function ServerWindow:commit()
    local result = Host.start(self.job, Files.loadState())
    if result.reloaded then
        return
    elseif result.error ~= nil then
        Widgets.tell({ getText(result.error, unpack(result.args)) })
        return
    end
    self:close(result.job)
end

function ServerWindow:close(job)
    self:setVisible(false)
    self:removeFromUIManager()
    self.owner:onServerClosed(job)
end

function ServerWindow:onBack()
    self:close(nil)
end

-- The setup's end: the Host screen with the server chosen, and what was set. Also after the reloads, from MainMenu.
function ServerWindow.finished(job)
    if job == nil then
        Widgets.tell({ getText("UI_Prepackaged_HostLost", Server.FILE) })
        return
    end
    local lines = Widgets.lines(Rows.hosted(job))
    if job.error == nil then
        local missing = Host.show(job)
        if missing ~= nil then
            lines[#lines + 1] = getText("UI_Prepackaged_HostNoScreen", missing, job.name)
        end
    end
    Widgets.tell(lines)
end

function ServerWindow.open(owner, entry)
    local window = ServerWindow:new(owner.x, owner.y, owner.width, owner.height, owner, entry)
    window:initialise()
    window:addToUIManager()
    return window
end

return ServerWindow
