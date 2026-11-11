-- Hunter Pet Collector - Pet XP Bar
-- Movable, scalable pet XP bar with a live, animated pet model.
--  * Hunters: your real pet's level and experience (hidden on game versions
--    where pets don't level, like MoP Classic, unless you turn that off).
--  * Any other class: a pretend wolf that earns the experience you earn,
--    just for fun. It can't pass your level, like a real hunter pet.
-- Bar settings live in their own saved variable, HPCPetXPDB. Nothing here
-- reads or writes the collection data. The pretend wolf's level is saved
-- per character in HunterPetCodexCharDB.fakePet.
--
-- Originally the standalone HPC_PetXPBar addon. Everything is kept in its
-- own table (ns.XP) so it can't clash with the rest of the addon.

local ADDON, ns = ...
local X = {}
ns.XP = X

local WHITE = "Interface\\Buttons\\WHITE8x8"
local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil
X.BACKDROP_TEMPLATE = BACKDROP_TEMPLATE
X.WHITE = WHITE

---------------------------------------------------------------------------
-- Defaults (Hunter Pet Collector's look: dark panel, thin grey edge, green)
---------------------------------------------------------------------------
X.DEFAULTS = {
    point         = { "CENTER", "UIParent", "CENTER", 0, -180 },
    width         = 385,
    height        = 9,
    scale         = 1.2,
    locked        = false,
    hideWhenNoPet = true,
    textMode      = "full",      -- full | percent | remaining | none
    borderStyle   = "thin",      -- thin | tooltip
    showSpark     = true,
    showTicks     = true,
    showGains     = true,

    fillColor     = { r = 0.67, g = 0.83, b = 0.45, a = 1 },
    bgColor       = { r = 0.06, g = 0.06, b = 0.07, a = 0.96 },
    borderColor   = { r = 0.22, g = 0.22, b = 0.24, a = 1 },
    textColor     = { r = 1.00, g = 1.00, b = 1.00, a = 1 },

    showModel     = true,
    modelMode     = "ride",      -- ride (runs along the bar) | beside
    modelSide     = "LEFT",      -- LEFT | RIGHT (beside mode)
    modelSize     = 40,
    modelFacing   = 80,          -- degrees; 90 = side on, facing along the bar
    modelZoom     = 1.35,        -- camera distance; higher = further away (less cropping)
    modelAnim     = "run",       -- idle | walk | run
}

local function CopyDefaults(src, dst)
    if type(dst) ~= "table" then dst = {} end
    for k, v in pairs(src) do
        if type(v) == "table" then
            dst[k] = CopyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end
X.CopyDefaults = CopyDefaults

X.BORDERS = {
    tooltip = {
        bgFile = WHITE, edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 },
    },
    thin = {
        bgFile = WHITE, edgeFile = WHITE,
        edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 },
    },
}
local INSET = { tooltip = 4, thin = 2 }
local ANIMS = { idle = 0, walk = 4, run = 5 }

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function Fmt(n)
    n = math.floor((n or 0) + 0.5)
    if BreakUpLargeNumbers then return BreakUpLargeNumbers(n) end
    local s, r = tostring(n), 0
    repeat s, r = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2") until r == 0
    return s
end
X.Fmt = Fmt

local function FmtTime(sec)
    if not sec or sec <= 0 or sec ~= sec or sec == math.huge then return "-" end
    local h = math.floor(sec / 3600)
    local m = math.floor((sec % 3600) / 60)
    if h > 0 then return h .. "h " .. m .. "m" end
    return math.max(m, 1) .. "m"
end

local function Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
X.Clamp = Clamp

local function C(c) return c.r, c.g, c.b, c.a or 1 end
X.C = C

local function Safe(obj, method, ...)
    if obj and obj[method] then pcall(obj[method], obj, ...) end
end

local function IsHunter() return ns.playerClass == "HUNTER" end

---------------------------------------------------------------------------
-- Pretend wolf (non-hunters), saved per character
---------------------------------------------------------------------------
local FAKE_NAME = "Wolf"
local KILL_XP_AT_CAP = 45

-- experience the wolf needs for its next level (a gentle curve, for fun)
local function FakeNeeded(level) return 100 + level * level * 15 end

local function Fake()
    if not ns.cdb then return nil end
    ns.cdb.fakePet = ns.cdb.fakePet or { level = 1, xp = 0 }
    return ns.cdb.fakePet
end

local function MaxPlayerLevel()
    for _, fn in ipairs({ GetMaxLevelForPlayerExpansion, GetMaxPlayerLevel }) do
        if fn then
            local ok, v = pcall(fn)
            if ok and v then return v end
        end
    end
    return MAX_PLAYER_LEVEL or 60
end

-- add experience to the wolf; returns levels gained
function X.FeedFakePet(amount)
    local p = Fake()
    if not p or not amount or amount <= 0 then return 0 end
    local cap = UnitLevel("player") or 1
    local gained = 0
    p.xp = p.xp + amount
    while p.level < cap and p.xp >= FakeNeeded(p.level) do
        p.xp = p.xp - FakeNeeded(p.level)
        p.level = p.level + 1
        gained = gained + 1
    end
    if p.level >= cap then p.xp = math.min(p.xp, FakeNeeded(p.level) - 1) end
    if gained > 0 then ns.Print(("Your wolf reached level %d!"):format(p.level)) end
    return gained
end

-- a wolf model from the addon's own beast list (lowest-level wolf look)
local wolfDisplay
local function WolfDisplay()
    if wolfDisplay ~= nil then return wolfDisplay end
    wolfDisplay = false
    local best
    for _, look in ipairs(ns.lookList or {}) do
        if look.family == 1 and look.id and (not best or (look.minLevel or 99) < (best.minLevel or 99)) then best = look end
    end
    if best then wolfDisplay = best.id end
    return wolfDisplay
end

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
local state = {
    pct = 0, shown = 0, moving = false,
    cur = 0, max = 1, level = 0, name = nil, preview = false,
    session = 0, sessionStart = nil,
    anim = nil, celebrate = 0, flash = 0, gainT = nil,
}
X.state = state

local f, bar, spark, gloss, text, flash, box, model, gainText
local ticks = {}

---------------------------------------------------------------------------
-- Pet data: cur, max, level, name, isFake
---------------------------------------------------------------------------
local function GetPetData()
    if IsHunter() then
        if not GetPetExperience or not UnitExists("pet") then return end
        local ok, cur, max = pcall(GetPetExperience)
        if not ok or not max or max == 0 then return end   -- pets don't level here (MoP)
        return cur, max, UnitLevel("pet") or 0, UnitName("pet")
    end
    local p = Fake()
    if not p then return end
    return p.xp, FakeNeeded(p.level), p.level, FAKE_NAME, true
end
X.GetPetData = GetPetData

---------------------------------------------------------------------------
-- Tooltip
---------------------------------------------------------------------------
local function ShowTooltip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    local a = ns.W.ACCENT
    if state.preview then
        GameTooltip:AddLine("Pet XP Bar (preview)", a[1], a[2], a[3])
        GameTooltip:AddLine("No levelling pet is out.", 1, 1, 1, true)
    else
        GameTooltip:AddLine(string.format("%s  (Level %d)", state.name or "Pet", state.level), a[1], a[2], a[3])
        GameTooltip:AddDoubleLine("Experience", Fmt(state.cur) .. " / " .. Fmt(state.max), 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddDoubleLine("To next level", Fmt(state.max - state.cur), 0.8, 0.8, 0.8, 1, 1, 1)
        if state.session > 0 and state.sessionStart then
            local elapsed = GetTime() - state.sessionStart
            local perHour = elapsed > 0 and (state.session / elapsed * 3600) or 0
            GameTooltip:AddDoubleLine("Gained this session", Fmt(state.session), 0.8, 0.8, 0.8, 1, 1, 1)
            GameTooltip:AddDoubleLine("XP per hour", Fmt(perHour), 0.8, 0.8, 0.8, 1, 1, 1)
            GameTooltip:AddDoubleLine("Time to level",
                FmtTime(perHour > 0 and (state.max - state.cur) / perHour * 3600 or nil), 0.8, 0.8, 0.8, 1, 1, 1)
        end
        if state.fake then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("A pretend wolf, just for fun. It earns the experience you earn and can't pass your level.", 0.6, 0.6, 0.6, true)
        end
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(X.db.locked and "Shift-drag to move" or "Drag to move", 0.6, 0.6, 0.6)
    GameTooltip:AddLine("Right-click for options  -  Ctrl+wheel to scale", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Position
---------------------------------------------------------------------------
function X.SavePosition()
    local p, _, rp, x, y = f:GetPoint(1)
    X.db.point = { p, "UIParent", rp, x, y }
end

function X.RestorePosition()
    local pt = X.db.point
    f:ClearAllPoints()
    f:SetPoint(pt[1] or "CENTER", UIParent, pt[3] or "CENTER", pt[4] or 0, pt[5] or 0)
end

---------------------------------------------------------------------------
-- Model
---------------------------------------------------------------------------
local function ApplyModelView()
    if not model then return end
    local db = X.db
    local deg = db.modelFacing or 90
    if db.modelMode ~= "ride" and db.modelSide == "RIGHT" then deg = -deg end
    Safe(model, "SetFacing", math.rad(deg))
    Safe(model, "SetPortraitZoom", 0)
    Safe(model, "SetCamDistanceScale", db.modelZoom or 1)
    state.anim = nil -- force the animation to be re-applied
end

function X.RefreshModel()
    if not model then return end
    if not X.db.showModel then box:Hide(); return end
    box:Show()
    Safe(model, "ClearModel")
    if IsHunter() and UnitExists("pet") then
        Safe(model, "SetUnit", "pet")
    elseif not IsHunter() and WolfDisplay() then
        Safe(model, "SetDisplayInfo", WolfDisplay())
    else
        Safe(model, "SetUnit", "player") -- preview
    end
    ApplyModelView()
    -- Models sometimes load blank on the first frame; re-apply shortly after.
    if C_Timer and C_Timer.After then
        C_Timer.After(0.4, ApplyModelView)
    end
end

-- the hunter pet's model ID as shown on the bar (the pet scan uses it on
-- newer engines, where a pet's creature ID is the same for every pet)
function X.PetModelDisplayID()
    if not model or not IsHunter() or not UnitExists("pet") or not model.GetDisplayInfo then return nil end
    local ok, id = pcall(model.GetDisplayInfo, model)
    if ok then return id end
end

local function UpdateAnim()
    if not model or not box:IsShown() or not model.SetAnimation then return end
    local db, want = X.db, nil
    if GetTime() < state.celebrate then
        want = ANIMS.run
    elseif db.modelMode == "ride" and state.moving then
        want = ANIMS.run
    else
        want = ANIMS[db.modelAnim] or 0
    end
    if want ~= state.anim then
        pcall(model.SetAnimation, model, want)
        state.anim = want
    end
end

---------------------------------------------------------------------------
-- Spark + rider position (follows the fill edge)
---------------------------------------------------------------------------
local function UpdateEdge()
    local db = X.db
    spark:SetShown(db.showSpark and state.shown > 0.003 and state.shown < 0.997)
    if db.showModel and db.modelMode == "ride" then
        local w = bar:GetWidth()
        box:ClearAllPoints()
        box:SetPoint("BOTTOM", bar, "TOPLEFT", w * state.shown, -db.modelSize * 0.22)
    end
end

---------------------------------------------------------------------------
-- Text
---------------------------------------------------------------------------
local MIN_FONT, READABLE_FONT = 7, 9

-- The longest-to-shortest ways to say it, for the chosen text style
local function TextOptions()
    local mode = X.db.textMode
    if mode == "none" then return { "" } end
    if state.preview then return { "Preview - no levelling pet", "Preview" } end
    local pct = state.cur / state.max * 100
    local full = string.format("Lv %d   %s / %s   (%.1f%%)", state.level, Fmt(state.cur), Fmt(state.max), pct)
    local mid = string.format("Lv %d  %s/%s", state.level, Fmt(state.cur), Fmt(state.max))
    local short = string.format("Lv %d  %d%%", state.level, math.floor(pct))
    local tiny = string.format("%d%%", math.floor(pct))
    if mode == "percent" then
        return { string.format("Lv %d   %.1f%%", state.level, pct), short, tiny }
    elseif mode == "remaining" then
        return { string.format("Lv %d   %s to go", state.level, Fmt(state.max - state.cur)),
            string.format("%s to go", Fmt(state.max - state.cur)), tiny }
    end
    return { full, mid, short, tiny }
end

-- Fit the text inside the bar: biggest font the bar's height allows, made
-- smaller (and then shorter wording) until it fits the bar's width.
local function UpdateText()
    if not text then return end
    local options = TextOptions()
    -- the bar's inner width, from the settings (the frame may not be laid out yet)
    local room = X.db.width - 2 * (INSET[X.db.borderStyle] or 2) - 6
    local size = Clamp(math.floor(X.db.height * 0.68 + 0.5), MIN_FONT, 22)
    local fits = function() local w = text:GetStringWidth(); return not w or w <= room end
    for i, s in ipairs(options) do
        -- shrink to a readable size before trying shorter wording; only the
        -- shortest wording goes all the way down
        local floor = (i == #options) and MIN_FONT or math.min(size, READABLE_FONT)
        local try = size
        text:SetFont(STANDARD_TEXT_FONT, try, "OUTLINE")
        text:SetText(s)
        while not fits() and try > floor do
            try = try - 1
            text:SetFont(STANDARD_TEXT_FONT, try, "OUTLINE")
        end
        if fits() or i == #options then break end
    end
end
X.UpdateText = UpdateText

---------------------------------------------------------------------------
-- XP update
---------------------------------------------------------------------------
function X.LevelUp()
    state.flash = 1.2
    state.celebrate = GetTime() + 2.5
    state.shown = 0
end

function X.ShowGain(n)
    if not X.db.showGains then return end
    gainText:SetText("+" .. Fmt(n) .. " XP")
    state.gainT = 0
    gainText:Show()
end

function X.UpdateXP()
    if not f then return end
    if not ns.db.petXPBar then f:Hide(); return end   -- turned off in Hunter Pet Collector's options
    local cur, max, lvl, name, fake = GetPetData()
    if not cur then
        if X.optionsOpen or not X.db.hideWhenNoPet then
            state.preview = true
            cur, max, lvl, name = 6200, 10000, 0, nil
        else
            f:Hide()
            return
        end
    else
        -- Track gains (only for the same pet).
        if not state.preview and state.name == name and state.level > 0 then
            local gained = 0
            if lvl > state.level then
                gained = (state.max - state.cur) + cur
                X.LevelUp()
            elseif lvl == state.level and cur > state.cur then
                gained = cur - state.cur
            end
            if gained > 0 then
                state.sessionStart = state.sessionStart or GetTime()
                state.session = state.session + gained
                X.ShowGain(gained)
                if X.db.modelMode ~= "ride" then state.celebrate = math.max(state.celebrate, GetTime() + 1.2) end
            end
        end
        state.preview = false
    end
    state.cur, state.max, state.level, state.name, state.fake = cur, max, lvl, name, fake
    state.pct = Clamp(cur / max, 0, 1)
    f:Show()
    UpdateText()
end

---------------------------------------------------------------------------
-- Layout (applies all visual settings)
---------------------------------------------------------------------------
function X.Layout()
    if not f then return end
    local db = X.db
    local style = X.BORDERS[db.borderStyle] or X.BORDERS.thin
    local inset = INSET[db.borderStyle] or 2

    f:SetScale(db.scale)
    f:SetSize(db.width, db.height + inset * 2)
    f:SetBackdrop(style)
    f:SetBackdropColor(C(db.bgColor))
    f:SetBackdropBorderColor(C(db.borderColor))

    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", inset, -inset)
    bar:SetPoint("BOTTOMRIGHT", -inset, inset)
    bar:SetStatusBarColor(C(db.fillColor))

    gloss:SetHeight(math.max(1, db.height * 0.45))
    spark:SetSize(math.max(12, db.height), db.height * 2.4)
    flash:SetVertexColor(db.fillColor.r, db.fillColor.g, db.fillColor.b)

    local bw = db.width - inset * 2
    for i = 1, 9 do
        local t = ticks[i]
        t:ClearAllPoints()
        t:SetPoint("TOP", bar, "TOPLEFT", bw * i / 10, 0)
        t:SetPoint("BOTTOM", bar, "BOTTOMLEFT", bw * i / 10, 0)
        t:SetShown(db.showTicks)
    end

    local fontSize = Clamp(math.floor(db.height * 0.68 + 0.5), MIN_FONT, 22)
    -- never draw outside the bar (UpdateText sizes the text to fit)
    text:ClearAllPoints()
    text:SetPoint("LEFT", bar, "LEFT", 3, 0)
    text:SetPoint("RIGHT", bar, "RIGHT", -3, 0)
    text:SetJustifyH("CENTER")
    if text.SetWordWrap then text:SetWordWrap(false) end
    text:SetTextColor(C(db.textColor))
    gainText:SetFont(STANDARD_TEXT_FONT, fontSize + 1, "OUTLINE")
    gainText:SetTextColor(db.fillColor.r, db.fillColor.g, db.fillColor.b)

    -- Pet model
    if db.showModel then
        box:Show()
        local size = db.modelSize
        box:SetSize(size, size)
        box:ClearAllPoints()
        model:ClearAllPoints()
        if db.modelMode == "ride" then
            box:SetBackdrop(nil)
            box:EnableMouse(false)
            model:SetAllPoints(box)
        else
            box:SetBackdrop(style)
            box:SetBackdropColor(C(db.bgColor))
            box:SetBackdropBorderColor(C(db.borderColor))
            box:EnableMouse(true)
            if db.modelSide == "RIGHT" then
                box:SetPoint("LEFT", f, "RIGHT", 3, 0)
            else
                box:SetPoint("RIGHT", f, "LEFT", -3, 0)
            end
            model:SetPoint("TOPLEFT", box, "TOPLEFT", inset, -inset)
            model:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -inset, inset)
        end
        ApplyModelView()
    else
        box:Hide()
    end

    UpdateEdge()
    UpdateText()
end

function X.Refresh()
    X.Layout()
    X.UpdateXP()
end

---------------------------------------------------------------------------
-- Build frames
---------------------------------------------------------------------------
local function StartDrag()
    if not X.db.locked or IsShiftKeyDown() then f:StartMoving() end
end
local function StopDrag()
    f:StopMovingOrSizing()
    X.SavePosition()
end

local function OnUpdate(self, elapsed)
    -- Smoothly animate the fill towards the real value.
    local diff = state.pct - state.shown
    if math.abs(diff) > 0.0005 then
        state.shown = state.shown + diff * math.min(1, elapsed * 5)
        if math.abs(state.pct - state.shown) <= 0.0005 then state.shown = state.pct end
        bar:SetValue(state.shown)
        state.moving = true
        UpdateEdge()
    elseif state.moving then
        state.moving = false
        bar:SetValue(state.shown)
        UpdateEdge()
    end

    UpdateAnim()

    -- Floating "+XP" text
    if state.gainT then
        state.gainT = state.gainT + elapsed
        local p = state.gainT / 1.6
        if p >= 1 then
            state.gainT = nil
            gainText:Hide()
        else
            gainText:ClearAllPoints()
            gainText:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", -4, 2 + p * 18)
            gainText:SetAlpha(1 - p * p)
        end
    end

    -- Level-up flash
    if state.flash > 0 then
        state.flash = state.flash - elapsed
        flash:SetAlpha(math.max(0, state.flash) * (0.6 + 0.4 * math.sin(GetTime() * 14)))
    else
        flash:SetAlpha(0)
    end
end

function X.Build()
    f = CreateFrame("Frame", "HPCPetXPBarFrame", UIParent, BACKDROP_TEMPLATE)
    X.frame = f
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", StartDrag)
    f:SetScript("OnDragStop", StopDrag)
    f:SetScript("OnMouseUp", function(_, btn) if btn == "RightButton" then X.OpenOptions() end end)
    f:SetScript("OnEnter", ShowTooltip)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, delta)
        if not IsControlKeyDown() then return end
        X.db.scale = Clamp(math.floor((X.db.scale + delta * 0.05) * 100 + 0.5) / 100, 0.5, 2.5)
        X.Layout()
        if X.RefreshOptions then X.RefreshOptions() end
    end)

    -- Bar
    bar = CreateFrame("StatusBar", nil, f)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    local fill = bar:GetStatusBarTexture()

    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.35)

    gloss = bar:CreateTexture(nil, "ARTWORK", nil, 2)
    gloss:SetPoint("TOPLEFT", bar, "TOPLEFT")
    gloss:SetPoint("TOPRIGHT", fill, "TOPRIGHT")
    gloss:SetColorTexture(1, 1, 1, 0.13)

    for i = 1, 9 do
        local t = bar:CreateTexture(nil, "ARTWORK", nil, 3)
        t:SetWidth(1)
        t:SetColorTexture(0, 0, 0, 0.35)
        ticks[i] = t
    end

    -- Overlay (text, spark, flash) sits above the bar
    local overlay = CreateFrame("Frame", nil, bar)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(bar:GetFrameLevel() + 3)

    spark = overlay:CreateTexture(nil, "OVERLAY")
    spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    spark:SetBlendMode("ADD")
    spark:SetPoint("CENTER", fill, "RIGHT", 0, 0)

    flash = overlay:CreateTexture(nil, "OVERLAY", nil, 1)
    flash:SetAllPoints(bar)
    flash:SetTexture(WHITE)
    flash:SetBlendMode("ADD")
    flash:SetAlpha(0)

    text = overlay:CreateFontString(nil, "OVERLAY")
    X.text = text
    text:SetPoint("CENTER", bar, "CENTER", 0, 0)
    text:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")

    gainText = f:CreateFontString(nil, "OVERLAY")
    gainText:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
    gainText:Hide()

    -- Pet model box
    box = CreateFrame("Frame", nil, f, BACKDROP_TEMPLATE)
    box:SetFrameLevel(f:GetFrameLevel() + 5)
    box:RegisterForDrag("LeftButton")
    box:SetScript("OnDragStart", StartDrag)
    box:SetScript("OnDragStop", StopDrag)
    box:SetScript("OnMouseUp", function(_, btn) if btn == "RightButton" then X.OpenOptions() end end)
    box:SetScript("OnEnter", function() ShowTooltip(box) end)
    box:SetScript("OnLeave", function() GameTooltip:Hide() end)

    model = CreateFrame("PlayerModel", nil, box)
    pcall(model.SetScript, model, "OnModelLoaded", ApplyModelView)

    f:SetScript("OnUpdate", OnUpdate)
    X.RestorePosition()
end

---------------------------------------------------------------------------
-- Events (set up from Hunter Pet Collector's own READY, after saved data
-- has loaded)
---------------------------------------------------------------------------
local lastXP, lastXPMax

-- "You have slain %s!" in the game's language, as a pattern
local killPattern
local function KillPattern()
    if killPattern == nil then
        local fmt = SELFKILLOTHER or "You have slain %s!"
        local a, b = fmt:match("^(.-)%%s(.*)$")
        local function esc(x) return (x:gsub("%p", "%%%0")) end
        killPattern = a and ("^" .. esc(a) .. ".+" .. esc(b) .. "$") or false
    end
    return killPattern
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(self, event, arg1)
    if event == "PLAYER_ENTERING_WORLD" then
        X.RefreshModel()
        X.UpdateXP()
    elseif event == "UNIT_PET" then
        if arg1 == "player" then
            X.RefreshModel()
            X.UpdateXP()
        end
    elseif event == "UNIT_MODEL_CHANGED" then
        if arg1 == "pet" then X.RefreshModel() end
    elseif event == "UNIT_LEVEL" then
        if arg1 == "pet" or arg1 == "player" then X.UpdateXP() end
    elseif event == "PLAYER_XP_UPDATE" then
        -- the pretend wolf earns what you earn
        local xp, max = UnitXP("player") or 0, UnitXPMax("player") or 0
        if not IsHunter() and lastXP then
            local gained
            if xp >= lastXP then gained = xp - lastXP
            else gained = (lastXPMax or 0) - lastXP + xp end   -- you levelled up
            X.FeedFakePet(gained)
            X.UpdateXP()
        end
        lastXP, lastXPMax = xp, max
    elseif event == "CHAT_MSG_COMBAT_HOSTILE_DEATH" then
        -- At max level you earn no experience, so the wolf gets a bit for
        -- each kill. Uses the "You have slain X!" chat line: some game
        -- versions forbid addons from reading the combat log.
        if IsHunter() or (UnitLevel("player") or 0) < MaxPlayerLevel() then return end
        if type(arg1) ~= "string" or (issecretvalue and issecretvalue(arg1)) then return end
        if KillPattern() and arg1:match(KillPattern()) then
            X.FeedFakePet(KILL_XP_AT_CAP)
            X.UpdateXP()
        end
    else -- UNIT_PET_EXPERIENCE, PET_UI_UPDATE
        X.UpdateXP()
    end
end)

-- Settings updates for players who already have saved bar settings. Each
-- step only changes values still at the old default, never your own picks.
local SETTINGS_VERSION = 3
local function UpgradeSettings(db)
    local v = db.settingsVersion or 1
    if v < 2 then
        -- 1.9.22 framed the pet too tightly and clipped its nose and tail
        if db.modelZoom == 1.0 then db.modelZoom = X.DEFAULTS.modelZoom end
        if db.modelFacing == 90 then db.modelFacing = X.DEFAULTS.modelFacing end
    end
    if v < 3 then
        -- 1.9.29: slimmer, wider bar with the pet running along it
        local old = { width = 260, height = 16, scale = 1.0, modelMode = "beside", modelAnim = "walk",
            modelSize = 56, modelFacing = 65, modelZoom = 1.6 }
        for k, was in pairs(old) do
            if db[k] == was then db[k] = X.DEFAULTS[k] end
        end
    end
    db.settingsVersion = SETTINGS_VERSION
end
X.UpgradeSettings = UpgradeSettings

ns.On("READY", function()
    local had = HPCPetXPDB ~= nil
    HPCPetXPDB = CopyDefaults(X.DEFAULTS, HPCPetXPDB)
    if had then UpgradeSettings(HPCPetXPDB) else HPCPetXPDB.settingsVersion = SETTINGS_VERSION end
    X.db = HPCPetXPDB
    X.Build()
    X.Layout()
    lastXP, lastXPMax = UnitXP("player") or 0, UnitXPMax("player") or 0
    for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "UNIT_PET", "UNIT_PET_EXPERIENCE",
                         "UNIT_LEVEL", "UNIT_MODEL_CHANGED", "PET_UI_UPDATE", "PLAYER_XP_UPDATE" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    if not IsHunter() then pcall(ev.RegisterEvent, ev, "CHAT_MSG_COMBAT_HOSTILE_DEATH") end
    X.RefreshModel()
    X.UpdateXP()
end)

---------------------------------------------------------------------------
-- Slash commands (/hpc xp also opens the options; see Core.lua)
---------------------------------------------------------------------------
SLASH_HPCPETXP1 = "/petxp"
SLASH_HPCPETXP2 = "/hpcxp"
SlashCmdList.HPCPETXP = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if not X.frame then return end
    if msg == "lock" then
        X.db.locked = true
    elseif msg == "unlock" then
        X.db.locked = false
    elseif msg == "reset" then
        X.db.point = CopyDefaults(X.DEFAULTS.point, nil)
        X.RestorePosition()
    else
        X.OpenOptions()
        return
    end
    if X.RefreshOptions then X.RefreshOptions() end
    ns.Print("Pet XP Bar " .. (msg == "reset" and "position reset." or (X.db.locked and "locked." or "unlocked.")))
end
