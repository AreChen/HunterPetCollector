-- Hunter Pet Collector - shared widgets & styling
local ADDON, ns = ...
local L = ns.L
local W = {}
ns.W = W

W.ACCENT = { 0.67, 0.83, 0.45 }   -- hunter green
W.BG = { 0.06, 0.06, 0.07, 0.96 }
W.PANEL = { 0.10, 0.10, 0.11, 0.92 }
W.EDGE = { 0.22, 0.22, 0.24, 1 }
W.WHITE = "Interface\\Buttons\\WHITE8x8"

local BACKDROP = { bgFile = W.WHITE, edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12, insets = { left = 4, right = 4, top = 4, bottom = 4 } }

function W.Panel(parent, bg, edge)
    local f = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    W.Skin(f, bg, edge)
    return f
end

function W.Skin(f, bg, edge)
    if not f.SetBackdrop then Mixin(f, BackdropTemplateMixin); end
    f:SetBackdrop(BACKDROP)
    bg, edge = bg or W.PANEL, edge or W.EDGE
    f:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
    f:SetBackdropBorderColor(edge[1], edge[2], edge[3], edge[4] or 1)
end

function W.Text(parent, template, size, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
    if size then
        local font, _, flags = fs:GetFont()
        fs:SetFont(font, size, flags)
    end
    if justify then fs:SetJustifyH(justify) end
    return fs
end

-- Flat button with hover/selected states
function W.Button(parent, text, width, height)
    local b = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    b:SetSize(width or 100, height or 22)
    W.Skin(b, { 0.14, 0.14, 0.15, 1 }, W.EDGE)
    b.text = W.Text(b, "GameFontHighlightSmall")
    b.text:SetPoint("CENTER")
    b.text:SetText(L[text or ""])
    b:SetScript("OnEnter", function(self)
        if not self.selected then self:SetBackdropBorderColor(W.ACCENT[1], W.ACCENT[2], W.ACCENT[3], 0.8) end
        if self.tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(self.tooltip, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function(self)
        if not self.selected then self:SetBackdropBorderColor(unpack(W.EDGE)) end
        GameTooltip:Hide()
    end)
    function b:SetSelected(on)
        self.selected = on
        if on then
            self:SetBackdropColor(W.ACCENT[1] * 0.35, W.ACCENT[2] * 0.35, W.ACCENT[3] * 0.35, 1)
            self:SetBackdropBorderColor(W.ACCENT[1], W.ACCENT[2], W.ACCENT[3], 1)
        else
            self:SetBackdropColor(0.14, 0.14, 0.15, 1)
            self:SetBackdropBorderColor(unpack(W.EDGE))
        end
    end
    return b
end

function W.Check(parent, label, onClick)
    local b = CreateFrame("CheckButton", nil, parent)
    b:SetSize(16, 16)
    local box = W.Panel(b, { 0.12, 0.12, 0.13, 1 })
    box:SetAllPoints()
    box:SetFrameLevel(b:GetFrameLevel())
    local mark = b:CreateTexture(nil, "OVERLAY")
    mark:SetTexture(W.WHITE)
    mark:SetPoint("TOPLEFT", 4, -4)
    mark:SetPoint("BOTTOMRIGHT", -4, 4)
    mark:SetVertexColor(unpack(W.ACCENT))
    b:SetCheckedTexture(mark)
    b.label = W.Text(b, "GameFontHighlightSmall", nil, "LEFT")
    b.label:SetPoint("LEFT", b, "RIGHT", 6, 0)
    b.label:SetText(label)
    b:SetHitRectInsets(0, -(b.label:GetStringWidth() + 8), 0, 0)
    b:SetScript("OnClick", function(self) if onClick then onClick(self, self:GetChecked()) end end)
    return b
end

function W.SearchBox(parent, width, onChange)
    local box = W.Panel(parent, { 0.03, 0.03, 0.04, 1 })
    box:SetSize(width, 24)
    local eb = CreateFrame("EditBox", nil, box)
    eb:SetPoint("TOPLEFT", 22, 0)
    eb:SetPoint("BOTTOMRIGHT", -20, 0)
    eb:SetAutoFocus(false)
    eb:SetFontObject("GameFontHighlightSmall")
    local icon = box:CreateTexture(nil, "OVERLAY")
    icon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    icon:SetSize(14, 14)
    icon:SetPoint("LEFT", 5, -1)
    icon:SetVertexColor(0.6, 0.6, 0.6)
    local hint = W.Text(box, "GameFontDisableSmall", nil, "LEFT")
    hint:SetPoint("LEFT", eb, "LEFT", 0, 0)
    hint:SetText(L["Search beasts or zones"])
    local clear = CreateFrame("Button", nil, box)
    clear:SetSize(14, 14)
    clear:SetPoint("RIGHT", -4, 0)
    clear:SetNormalTexture("Interface\\FriendsFrame\\ClearBroadcastIcon")
    clear:SetAlpha(0.6)
    clear:Hide()
    clear:SetScript("OnClick", function() eb:SetText(""); eb:ClearFocus() end)
    eb:SetScript("OnTextChanged", function(self)
        local t = self:GetText()
        hint:SetShown(t == "" and not self:HasFocus())
        clear:SetShown(t ~= "")
        if onChange then onChange(t) end
    end)
    eb:SetScript("OnEditFocusGained", function() hint:Hide() end)
    eb:SetScript("OnEditFocusLost", function(self) hint:SetShown(self:GetText() == "") end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    box.editBox = eb
    return box
end

-- Simple virtual list: fixed row pool, scroll by mouse wheel, thin scroll indicator
function W.List(parent, rowHeight, numRows, makeRow, fillRow)
    local list = CreateFrame("Frame", nil, parent)
    list.rows, list.offset, list.items = {}, 0, {}
    for i = 1, numRows do
        local row = makeRow(list, i)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * rowHeight)
        row:SetPoint("RIGHT", -6, 0)
        row:SetHeight(rowHeight)
        list.rows[i] = row
    end
    local track = list:CreateTexture(nil, "BACKGROUND")
    track:SetTexture(W.WHITE)
    track:SetVertexColor(1, 1, 1, 0.04)
    track:SetPoint("TOPRIGHT", 0, 0)
    track:SetPoint("BOTTOMRIGHT", 0, 0)
    track:SetWidth(3)
    local thumb = list:CreateTexture(nil, "ARTWORK")
    thumb:SetTexture(W.WHITE)
    thumb:SetVertexColor(W.ACCENT[1], W.ACCENT[2], W.ACCENT[3], 0.7)
    thumb:SetWidth(3)

    function list:Refresh()
        local n = #self.items
        local maxOff = math.max(0, n - numRows)
        if self.offset > maxOff then self.offset = maxOff end
        for i, row in ipairs(self.rows) do
            local item = self.items[i + self.offset]
            if item then fillRow(row, item, i + self.offset); row:Show() else row:Hide() end
        end
        if n > numRows then
            local h = self:GetHeight()
            local th = math.max(16, h * numRows / n)
            thumb:SetHeight(th)
            thumb:ClearAllPoints()
            thumb:SetPoint("TOPRIGHT", 0, -((h - th) * self.offset / maxOff))
            thumb:Show(); track:Show()
        else
            thumb:Hide(); track:Hide()
        end
    end
    function list:SetItems(items)
        self.items = items
        self:Refresh()
    end
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(self, d)
        self.offset = math.max(0, self.offset - d * 3)
        self:Refresh()
    end)
    return list
end

-- Texture gradient that works with both the old and new SetGradient signatures
function W.Gradient(tex, r1, g1, b1, r2, g2, b2, a1, a2, orient)
    orient = orient or "HORIZONTAL"
    if CreateColor and pcall(tex.SetGradient, tex, orient, CreateColor(r1, g1, b1, a1 or 1), CreateColor(r2, g2, b2, a2 or 1)) then
        return
    end
    if tex.SetGradientAlpha then
        pcall(tex.SetGradientAlpha, tex, orient, r1, g1, b1, a1 or 1, r2, g2, b2, a2 or 1)
    else
        pcall(tex.SetGradient, tex, orient, r1, g1, b1, r2, g2, b2)
    end
end

-- Thin progress bar
function W.Bar(parent, width, height)
    local bar = W.Panel(parent, { 0.03, 0.03, 0.04, 1 })
    bar:SetSize(width, height)
    bar.fill = bar:CreateTexture(nil, "ARTWORK")
    bar.fill:SetTexture(W.WHITE)
    bar.fill:SetPoint("TOPLEFT", 1, -1)
    bar.fill:SetPoint("BOTTOMLEFT", 1, 1)
    W.Gradient(bar.fill, 0.35, 0.55, 0.2, W.ACCENT[1], W.ACCENT[2], W.ACCENT[3])
    bar.text = W.Text(bar, "GameFontHighlightSmall")
    bar.text:SetPoint("CENTER", 0, 0)
    function bar:SetProgress(v, max, label)
        local pct = (max and max > 0) and math.min(1, v / max) or 0
        self.fill:SetWidth(math.max(0.01, (self:GetWidth() - 2) * pct))
        self.fill:SetShown(pct > 0)
        self.text:SetText(label or ("%d / %d"):format(v, max))
    end
    return bar
end

function W.ClassColor(class)
    local c = class and (C_ClassColor and C_ClassColor.GetClassColor(class) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]))
    if c then return c.r, c.g, c.b end
    return 0.67, 0.83, 0.45
end

function W.TimeAgo(ts)
    local d = (GetServerTime and GetServerTime() or time()) - (ts or 0)
    if d < 90 then return "just now" end
    if d < 3600 then return math.floor(d / 60) .. "m ago" end
    if d < 86400 then return math.floor(d / 3600) .. "h ago" end
    return math.floor(d / 86400) .. "d ago"
end
