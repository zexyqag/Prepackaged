require "ISUI/ISButton"
require "ISUI/ISModalDialog"
require "ISUI/ISScrollingListBox"

local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local FONT_HGT_MEDIUM = getTextManager():getFontHeight(UIFont.Medium)
local UI_BORDER_SPACING = 10
local BUTTON_HGT = FONT_HGT_SMALL + 6
local BUTTON_PADDING = 32 + UI_BORDER_SPACING * 2
local INDENT = UI_BORDER_SPACING * 2
local BOX = FONT_HGT_SMALL + 4
local SCROLLBAR = 20
local GHC = getCore():getGoodHighlitedColor()
local BHC = getCore():getBadHighlitedColor()

local Widgets = {}

-- Wide enough for each of titles, so a title can change without a new layout.
function Widgets.button(parent, x, y, titles, onClick)
    local width = 0
    for _, title in ipairs(titles) do
        width = math.max(width, BUTTON_PADDING + getTextManager():MeasureStringX(UIFont.Small, title))
    end
    local b = ISButton:new(x, y, width, BUTTON_HGT, titles[1], parent, onClick)
    b:initialise()
    b:instantiate()
    b.borderColor = { r = 1, g = 1, b = 1, a = 0.1 }
    parent:addChild(b)
    return b
end

local function modal(text, yesno, onClick)
    local w, h = 400, 120
    local dialog = ISModalDialog:new((getCore():getScreenWidth() - w) / 2, (getCore():getScreenHeight() - h) / 2, w, h, text, yesno, nil, onClick)
    dialog:initialise()
    dialog:addToUIManager()
    dialog:setAlwaysOnTop(true)
    dialog:setCapture(true)
    dialog:bringToTop()
    return dialog
end

-- lines are joined with line breaks: the dialog grows to its longest line and doesn't wrap (ISModalDialog.CalcSize).
function Widgets.tell(lines)
    return modal(table.concat(lines, "\n"), false)
end

function Widgets.ask(lines, target, onYes)
    return modal(table.concat(lines, "\n"), true, function(_, button)
        if button.internal == "YES" then
            onYes(target)
        end
    end)
end

local function wrap(text, font, width)
    local lines, current = {}, ""
    for word in string.gmatch(text, "[^ ]+") do
        local longer = current == "" and word or current .. " " .. word
        if current ~= "" and getTextManager():MeasureStringX(font, longer) > width then
            lines[#lines + 1] = current
            current = word
        else
            current = longer
        end
    end
    lines[#lines + 1] = current
    return lines
end

local function modText(id, name)
    if name ~= nil and name ~= id then
        return getText("UI_Prepackaged_ModName", name, id)
    end
    return id
end

local function rowText(row)
    if row.text ~= nil then
        return row.text
    elseif row.style == "mod" then
        return modText(row.id, row.name)
    elseif row.style == "tick" then
        local text = row.label and getText("UI_Prepackaged_ModName", row.label, row.id) or modText(row.id, row.name)
        if row.status == "missing" then
            return getText("UI_Prepackaged_TickMissing", text)
        elseif row.status == "unavailable" then
            return getText("UI_Prepackaged_TickUnavailable", text)
        end
        return text
    end
    local text = getText(row.key, unpack(row.args))
    if row.line ~= nil and row.line > 0 then
        return getText("UI_Prepackaged_Line", row.line, text)
    end
    return text
end

local STYLES = {
    title = { font = UIFont.Medium, top = 0, indent = 0, r = 1, g = 1, b = 1 },
    section = { font = UIFont.Small, top = UI_BORDER_SPACING, indent = 0, r = 1, g = 1, b = 1 },
    text = { font = UIFont.Small, top = 0, indent = 0, r = 0.8, g = 0.8, b = 0.8 },
    note = { font = UIFont.Small, top = UI_BORDER_SPACING / 2, indent = 0, r = 0.7, g = 0.7, b = 0.7 },
    alert = { font = UIFont.Small, top = UI_BORDER_SPACING / 2, indent = 0, r = 0.9, g = 0.6, b = 0.2 },
    error = { font = UIFont.Small, top = 0, indent = INDENT, r = BHC:getR(), g = BHC:getG(), b = BHC:getB() },
    warning = { font = UIFont.Small, top = 0, indent = INDENT, r = 0.9, g = 0.6, b = 0.2 },
    mod = { font = UIFont.Small, top = 0, indent = INDENT, r = 0.7, g = 0.7, b = 0.7 },
    tick = { font = UIFont.Small, top = 2, indent = INDENT, r = 0.9, g = 0.9, b = 0.9 },
}

Widgets.RowList = ISScrollingListBox:derive("PrepackagedRowList")
local RowList = Widgets.RowList

function RowList:new(x, y, width, height)
    local o = ISScrollingListBox.new(self, x, y, width, height)
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.3 }
    o.borderColor = { r = 1, g = 1, b = 1, a = 0.2 }
    o.drawBorder = true
    o.tickTexture = getTexture("media/ui/inventoryPanes/Tickbox_Tick.png")
    return o
end

function RowList:setOnTick(target, onTick)
    self.tickTarget = target
    self.onTick = onTick
end

function RowList:setRows(rows)
    self:clear()
    self.selected = -1
    local width = self.width - UI_BORDER_SPACING * 2 - SCROLLBAR
    for _, row in ipairs(rows) do
        local style = STYLES[row.style]
        local textWidth = width - style.indent - (row.style == "tick" and BOX + UI_BORDER_SPACING / 2 or 0)
        local item = self:addItem("", row)
        item.lines = wrap(rowText(row), style.font, textWidth)
        item.height = style.top + #item.lines * getTextManager():getFontHeight(style.font) + 4
    end
end

function RowList:doDrawItem(y, item, alt)
    local row, style = item.item, STYLES[item.item.style]
    local top = y + style.top + 2
    local x = UI_BORDER_SPACING + style.indent
    local r, g, b = style.r, style.g, style.b
    if row.style == "section" then
        self:drawRect(UI_BORDER_SPACING, y + style.top - 1, self.width - UI_BORDER_SPACING * 2, 1, 0.2, 1, 1, 1)
    elseif row.style == "tick" then
        local usable = row.status == "ok"
        if usable and self.mouseoverselected == item.index and self:isMouseOver() then
            self:drawRect(x, top, BOX, BOX, 1, 0.3, 0.3, 0.3)
        else
            self:drawRectBorder(x, top, BOX, BOX, 1, 0.4, 0.4, 0.4)
        end
        if row.ticked then
            self:drawTextureScaled(self.tickTexture, x + 2, top + 2, BOX - 4, BOX - 4, 1, GHC:getR(), GHC:getG(), GHC:getB())
        end
        if not usable then
            r, g, b = 0.5, 0.5, 0.5
        end
        x = x + BOX + UI_BORDER_SPACING / 2
    end
    local lineHgt = getTextManager():getFontHeight(style.font)
    for i, line in ipairs(item.lines) do
        self:drawText(line, x, top + (i - 1) * lineHgt, r, g, b, 1, style.font)
    end
    return y + item.height
end

function RowList:onMouseDown(x, y)
    local item = self.items[self:rowAt(x, y)]
    if item ~= nil and item.item.style == "tick" and item.item.status == "ok" and self.onTick ~= nil then
        getSoundManager():playUISound("UISelectListItem")
        self.onTick(self.tickTarget, item.item)
    end
end

Widgets.PackList = ISScrollingListBox:derive("PrepackagedPackList")
local PackList = Widgets.PackList

function PackList:new(x, y, width, height)
    local o = ISScrollingListBox.new(self, x, y, width, height)
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.3 }
    o.borderColor = { r = 1, g = 1, b = 1, a = 0.2 }
    o.drawBorder = true
    o.itemheight = FONT_HGT_MEDIUM + FONT_HGT_SMALL + UI_BORDER_SPACING
    return o
end

function PackList:doDrawItem(y, item, alt)
    if self.selected == item.index then
        self:drawSelection(0, y, self:getWidth(), item.height - 1)
    elseif self.mouseoverselected == item.index and self:isMouseOver() and not self:isMouseOverScrollBar() then
        self:drawMouseOverHighlight(0, y, self:getWidth(), item.height - 1)
    end
    self:drawRectBorder(0, y, self:getWidth(), item.height, 0.5, self.borderColor.r, self.borderColor.g, self.borderColor.b)
    local data = item.item
    local r, g, b = 1, 1, 1
    if data.color == "good" then
        r, g, b = GHC:getR(), GHC:getG(), GHC:getB()
    elseif data.color == "bad" then
        r, g, b = BHC:getR(), BHC:getG(), BHC:getB()
    end
    local top = y + UI_BORDER_SPACING / 2
    self:drawText(data.title, UI_BORDER_SPACING, top, r, g, b, 1, UIFont.Medium)
    self:drawText(data.detail, UI_BORDER_SPACING, top + FONT_HGT_MEDIUM, 0.7, 0.7, 0.7, 1, UIFont.Small)
    return y + item.height
end

return Widgets
