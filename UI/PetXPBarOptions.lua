-- Hunter Pet Collector - Pet XP Bar: options window
-- Styled with Hunter Pet Collector's own widgets (UI/Widgets.lua).
local ADDON, ns = ...
local X = ns.XP
local W

local panel
local refreshers = {}

local PRESETS = {
    { name = "Hunter",  fill = { 0.67, 0.83, 0.45 }, border = { 0.22, 0.22, 0.24 } },
    { name = "Gold",    fill = { 0.85, 0.68, 0.30 }, border = { 0.45, 0.36, 0.18 } },
    { name = "Arcane",  fill = { 0.62, 0.38, 0.95 }, border = { 0.40, 0.28, 0.60 } },
    { name = "Frost",   fill = { 0.30, 0.65, 1.00 }, border = { 0.25, 0.40, 0.60 } },
    { name = "Ember",   fill = { 1.00, 0.45, 0.15 }, border = { 0.55, 0.30, 0.15 } },
}

---------------------------------------------------------------------------
-- Colour picker (works with both old and new ColorPickerFrame APIs)
---------------------------------------------------------------------------
local function OpenColor(c, onChange)
    local r, g, b, a = c.r, c.g, c.b, c.a or 1
    local function apply()
        local nr, ng, nb = ColorPickerFrame:GetColorRGB()
        local na
        if ColorPickerFrame.GetColorAlpha then
            na = ColorPickerFrame:GetColorAlpha()
        elseif OpacitySliderFrame then
            na = 1 - OpacitySliderFrame:GetValue()
        end
        c.r, c.g, c.b, c.a = nr, ng, nb, na or a
        onChange()
    end
    local function cancel()
        c.r, c.g, c.b, c.a = r, g, b, a
        onChange()
    end
    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({
            r = r, g = g, b = b, opacity = a, hasOpacity = true,
            swatchFunc = apply, opacityFunc = apply, cancelFunc = cancel,
        })
    else
        ColorPickerFrame:Hide()
        ColorPickerFrame.hasOpacity = true
        ColorPickerFrame.opacity = 1 - a
        ColorPickerFrame.previousValues = { r, g, b, a }
        ColorPickerFrame.func = apply
        ColorPickerFrame.opacityFunc = apply
        ColorPickerFrame.cancelFunc = cancel
        ColorPickerFrame:SetColorRGB(r, g, b)
        ColorPickerFrame:Show()
    end
end

---------------------------------------------------------------------------
-- Widgets (thin wrappers around Hunter Pet Collector's)
---------------------------------------------------------------------------
local function Label(parent, text, x, y, template)
    local fs = W.Text(parent, template or "GameFontHighlightSmall", nil, "LEFT")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(text)
    return fs
end

local function Header(parent, text, y)
    local fs = Label(parent, text, 18, y, "GameFontNormal")
    fs:SetTextColor(W.ACCENT[1], W.ACCENT[2], W.ACCENT[3])
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(W.ACCENT[1], W.ACCENT[2], W.ACCENT[3], 0.3)
    line:SetHeight(1)
    line:SetPoint("LEFT", fs, "RIGHT", 8, 0)
    line:SetPoint("RIGHT", parent, "RIGHT", -18, 0)
    return fs
end

local function Button(parent, text, w, h, x, y, onClick)
    local b = W.Button(parent, text, w, h)
    b:SetPoint("TOPLEFT", x, y)
    b.label = b.text
    b:SetScript("OnClick", onClick)
    return b
end

local function Check(parent, text, key, x, y, after)
    local cb = W.Check(parent, text, function(self, on)
        X.db[key] = on and true or false
        if after then after() end
        X.Refresh()
    end)
    cb:SetPoint("TOPLEFT", x, y)
    table.insert(refreshers, function() cb:SetChecked(X.db[key] and true or false) end)
    return cb
end

local function Slider(parent, text, x, y, minV, maxV, step, get, set, fmt)
    Label(parent, text, x, y)
    local val = W.Text(parent, "GameFontNormalSmall", nil, "RIGHT")
    val:SetPoint("TOPLEFT", x + 150, y)
    val:SetWidth(40)
    val:SetTextColor(W.ACCENT[1], W.ACCENT[2], W.ACCENT[3])

    local s = CreateFrame("Slider", nil, parent, X.BACKDROP_TEMPLATE)
    s:SetOrientation("HORIZONTAL")
    s:SetSize(190, 12)
    s:SetPoint("TOPLEFT", x, y - 16)
    W.Skin(s, { 0.03, 0.03, 0.04, 1 }, W.EDGE)
    s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    s:EnableMouseWheel(true)

    local updating = false
    s:SetScript("OnValueChanged", function(self, v)
        v = math.floor(v / step + 0.5) * step
        val:SetText(fmt and fmt(v) or tostring(v))
        if updating then return end
        set(v)
        X.Layout()
    end)
    s:SetScript("OnMouseWheel", function(self, delta)
        self:SetValue(X.Clamp((self:GetValue() or minV) + delta * step, minV, maxV))
    end)
    table.insert(refreshers, function()
        updating = true
        s:SetValue(get())
        val:SetText(fmt and fmt(get()) or tostring(get()))
        updating = false
    end)
    return s
end

local function Cycle(parent, text, x, y, options, get, set)
    Label(parent, text, x, y)
    local b
    b = Button(parent, "", 190, 20, x, y - 15, function()
        local cur, idx = get(), 1
        for i, o in ipairs(options) do if o[1] == cur then idx = i end end
        idx = idx % #options + 1
        set(options[idx][1])
        b.label:SetText(options[idx][2])
        X.Refresh()
    end)
    table.insert(refreshers, function()
        local cur = get()
        for _, o in ipairs(options) do if o[1] == cur then b.label:SetText(o[2]) end end
    end)
    return b
end

local function Swatch(parent, text, key, x, y)
    local b = CreateFrame("Button", nil, parent, X.BACKDROP_TEMPLATE)
    b:SetSize(20, 20)
    b:SetPoint("TOPLEFT", x, y)
    W.Skin(b, { 0.03, 0.03, 0.04, 1 }, W.EDGE)
    local tex = b:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("TOPLEFT", 2, -2)
    tex:SetPoint("BOTTOMRIGHT", -2, 2)
    tex:SetTexture(X.WHITE)
    local fs = W.Text(b, "GameFontHighlightSmall", nil, "LEFT")
    fs:SetPoint("LEFT", b, "RIGHT", 5, 0)
    fs:SetText(text)
    local function update() local c = X.db[key]; tex:SetVertexColor(c.r, c.g, c.b, c.a or 1) end
    b:SetScript("OnClick", function()
        OpenColor(X.db[key], function() update(); X.Layout() end)
    end)
    table.insert(refreshers, update)
    return b
end

---------------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------------
function X.RefreshOptions()
    if not panel then return end
    for _, fn in ipairs(refreshers) do fn() end
end

local function BuildPanel()
    W = ns.W
    panel = W.Panel(UIParent, W.BG, { W.ACCENT[1], W.ACCENT[2], W.ACCENT[3], 1 })
    _G.HPCPetXPOptions = panel
    panel:SetSize(440, 560)
    panel:SetPoint("CENTER")
    panel:SetFrameStrata("DIALOG")
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    tinsert(UISpecialFrames, "HPCPetXPOptions")

    local logo = ns.CreateLogo and ns.CreateLogo(panel, 34)
    if logo then logo:SetPoint("TOPLEFT", 12, -10) end
    local tx = logo and 54 or 18
    local title = Label(panel, "Pet XP Bar", tx, -12, "GameFontNormalLarge")
    title:SetTextColor(1, 1, 1)
    local sub = Label(panel, "Hunter Pet Collector", tx, -32)
    sub:SetTextColor(W.ACCENT[1], W.ACCENT[2], W.ACCENT[3])

    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)

    local L, R = 22, 230
    local db = function() return X.db end

    -- Bar ------------------------------------------------------------------
    Header(panel, "Bar", -60)
    Slider(panel, "Scale", L, -80, 0.5, 2.5, 0.05,
        function() return db().scale end, function(v) db().scale = v end,
        function(v) return string.format("%.2f", v) end)
    Slider(panel, "Width", L, -120, 120, 600, 5,
        function() return db().width end, function(v) db().width = v end)
    Slider(panel, "Height", L, -160, 8, 40, 1,
        function() return db().height end, function(v) db().height = v end)

    Cycle(panel, "Text", R, -80, {
        { "full", "Level, XP and %" }, { "percent", "Level and %" },
        { "remaining", "XP remaining" }, { "none", "Hidden" },
    }, function() return db().textMode end, function(v) db().textMode = v end)
    Cycle(panel, "Border", R, -120, {
        { "thin", "Thin line" }, { "tooltip", "Rounded" },
    }, function() return db().borderStyle end, function(v) db().borderStyle = v end)
    Check(panel, "Show spark", "showSpark", R, -164)
    Check(panel, "Show 10% ticks", "showTicks", R + 100, -164)

    -- Colours --------------------------------------------------------------
    Header(panel, "Colours", -205)
    Swatch(panel, "Fill", "fillColor", L, -225)
    Swatch(panel, "Background", "bgColor", L + 100, -225)
    Swatch(panel, "Border", "borderColor", L + 220, -225)
    Swatch(panel, "Text", "textColor", L + 320, -225)

    Label(panel, "Presets", L, -258)
    for i, p in ipairs(PRESETS) do
        local b = Button(panel, p.name, 66, 20, L + 50 + (i - 1) * 70, -254, function()
            local d = db()
            d.fillColor.r, d.fillColor.g, d.fillColor.b = unpack(p.fill)
            d.borderColor.r, d.borderColor.g, d.borderColor.b = unpack(p.border)
            X.RefreshOptions()
            X.Layout()
        end)
        b.label:SetTextColor(p.fill[1], p.fill[2], p.fill[3])
    end

    -- Pet ------------------------------------------------------------------
    Header(panel, "Pet", -295)
    Check(panel, "Show animated pet", "showModel", L, -319, function()
        X.RefreshModel()
    end)
    Cycle(panel, "Pet position", L, -345, {
        { "beside-LEFT", "Beside bar (left)" }, { "beside-RIGHT", "Beside bar (right)" },
        { "ride", "Runs along the bar" },
    }, function()
        local d = db()
        return d.modelMode == "ride" and "ride" or ("beside-" .. d.modelSide)
    end, function(v)
        local d = db()
        if v == "ride" then
            d.modelMode = "ride"
        else
            d.modelMode = "beside"
            d.modelSide = v:match("beside%-(%a+)")
        end
    end)
    Cycle(panel, "Animation", L, -390, {
        { "walk", "Walking" }, { "run", "Running" }, { "idle", "Idle" },
    }, function() return db().modelAnim end, function(v) db().modelAnim = v end)

    Slider(panel, "Pet size", R, -315, 24, 128, 2,
        function() return db().modelSize end, function(v) db().modelSize = v end)
    Slider(panel, "Pet facing", R, -355, 0, 360, 5,
        function() return db().modelFacing end, function(v) db().modelFacing = v end,
        function(v) return v .. "\194\176" end)
    Slider(panel, "Pet zoom", R, -395, 0.5, 2.5, 0.05,
        function() return db().modelZoom end, function(v) db().modelZoom = v end,
        function(v) return string.format("%.2f", v) end)

    -- Behaviour ------------------------------------------------------------
    Header(panel, "Behaviour", -440)
    Check(panel, "Lock position (Shift-drag still moves)", "locked", L, -464)
    Check(panel, "Hide when no levelling pet", "hideWhenNoPet", L, -488)
    Check(panel, "Floating +XP popups", "showGains", R + 40, -464)

    -- Footer ---------------------------------------------------------------
    Button(panel, "Reset position", 120, 22, L, -522, function()
        X.db.point = X.CopyDefaults(X.DEFAULTS.point, nil)
        X.RestorePosition()
    end)
    -- resets the bar's look only (HPCPetXPDB); never touches your collection
    Button(panel, "Reset bar settings", 130, 22, L + 128, -522, function()
        wipe(HPCPetXPDB)
        X.CopyDefaults(X.DEFAULTS, HPCPetXPDB)
        HPCPetXPDB.settingsVersion = 3
        X.db = HPCPetXPDB
        X.RestorePosition()
        X.RefreshOptions()
        X.RefreshModel()
        X.Refresh()
    end)
    Button(panel, "Done", 90, 22, 440 - 22 - 90, -522, function() panel:Hide() end)

    panel:SetScript("OnShow", function()
        X.optionsOpen = true
        X.RefreshOptions()
        X.UpdateXP()
    end)
    panel:SetScript("OnHide", function()
        X.optionsOpen = false
        X.UpdateXP()
    end)
    panel:Hide()
end

function X.OpenOptions()
    if not X.frame then return end
    if not panel then BuildPanel() end
    if panel:IsShown() then panel:Hide() else panel:Show() end
end
