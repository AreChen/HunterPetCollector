-- Hunter Pet Collector - logo
-- A night elf hunter and a bear, drawn live from the game's own models and
-- lit pure black, standing on a hill in front of a green moon inside a gold
-- ring. The moon, hill and ring are the addon's own textures; the figures are
-- the game's models, rendered at runtime (nothing is copied into the addon).
local ADDON, ns = ...

local MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"
local BEAR_DISPLAY = 707          -- Elder Black Bear (exists in MoP Classic and Forever)
local ELF_NPC = 3936              -- Shandris Feathermoon, night elf huntress with a bow

-- Make a model render as a solid black silhouette.
local function Blacken(m)
    -- black fog right up to the camera turns every pixel of the model black
    pcall(m.SetFogColor, m, 0.02, 0.04, 0.02)
    pcall(m.SetFogNear, m, 0)
    pcall(m.SetFogFar, m, 0.01)
    -- and switch the lighting off for good measure (both API styles)
    if not pcall(m.SetLight, m, true, { omnidirectional = false, point = CreateVector3D and CreateVector3D(0, 0, 0) or nil,
        ambientIntensity = 0, ambientColor = CreateColor and CreateColor(0, 0, 0) or nil,
        diffuseIntensity = 0, diffuseColor = CreateColor and CreateColor(0, 0, 0) or nil }) then
        pcall(m.SetLight, m, true, false, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    end
end

local function SetupModel(m, facing, zoom, anim)
    pcall(m.SetPortraitZoom, m, 0)
    pcall(m.SetCamDistanceScale, m, zoom or 1)
    pcall(m.SetPosition, m, 0, 0, 0)
    pcall(m.SetFacing, m, facing)
    pcall(m.SetAnimation, m, anim or 0)
    Blacken(m)
end

local function LoadElf(m)
    local _, race = UnitRace("player")
    if race == "NightElf" then
        -- your own night elf, with your own bow on your back
        pcall(m.SetUnit, m, "player")
    else
        pcall(m.SetCreature, m, ELF_NPC)
        -- the creature may not be in the game's cache yet; fall back to you
        ns.After(1.5, function()
            local ok, fid = pcall(m.GetModelFileID, m)
            if not ok or not fid or fid == 0 then pcall(m.SetUnit, m, "player") end
            m:refresh()
        end)
    end
end

-- Placement of each model inside the logo, as fractions of the logo size.
-- zoom: smaller = bigger model. facing: radians (positive turns to screen-right).
local DEFAULT_TUNE = {
    elf  = { x = 0.20, y = 0.23, w = 0.28, h = 0.56, zoom = 0.78, facing = 1.45, anim = 0 },
    -- the bear walks, facing the same way as the elf
    bear = { x = 0.41, y = 0.24, w = 0.38, h = 0.30, zoom = 1.30, facing = 1.45, anim = 4 },
}

local TUNE_VERSION = 5
local function Tune()
    ns.db.logoTune = ns.db.logoTune or {}
    local t = ns.db.logoTune
    if (ns.db.logoTuneVersion or 1) < TUNE_VERSION then
        -- 1.8.5: elf back where it was (a little further left) and standing; bear walking
        for _, who in ipairs({ "elf", "bear" }) do
            if t[who] then
                for _, k in ipairs({ "x", "y", "facing", "anim" }) do t[who][k] = DEFAULT_TUNE[who][k] end
            end
        end
        ns.db.logoTuneVersion = TUNE_VERSION
    end
    for who, d in pairs(DEFAULT_TUNE) do
        t[who] = t[who] or {}
        for k, v in pairs(d) do if t[who][k] == nil then t[who][k] = v end end
    end
    return t
end

local logos = {}

local function Place(f)
    local size = f.size
    local t = Tune()
    for who, m in pairs({ elf = f.elf, bear = f.bear }) do
        local c = t[who]
        m:ClearAllPoints()
        m:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", size * c.x, size * c.y)
        m:SetSize(size * c.w, size * c.h)
        m:refresh()
    end
end

function ns.RefreshLogos()
    for _, f in ipairs(logos) do if f:IsVisible() then Place(f) end end
end

-- size: width and height in pixels
function ns.CreateLogo(parent, size)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size)
    f.size = size

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture(MEDIA .. "logo_bg")

    local elf = CreateFrame("PlayerModel", nil, f)
    local bear = CreateFrame("PlayerModel", nil, f)

    -- hill and ring sit in front of the models
    local front = CreateFrame("Frame", nil, f)
    front:SetAllPoints()
    front:SetFrameLevel(math.max(elf:GetFrameLevel(), bear:GetFrameLevel()) + 2)
    local hill = front:CreateTexture(nil, "ARTWORK")
    hill:SetAllPoints()
    hill:SetTexture(MEDIA .. "logo_hill")
    local ring = front:CreateTexture(nil, "OVERLAY")
    ring:SetAllPoints()
    ring:SetTexture(MEDIA .. "logo_ring")

    function elf:refresh() local c = Tune().elf; SetupModel(self, c.facing, c.zoom, c.anim) end
    function bear:refresh() local c = Tune().bear; SetupModel(self, c.facing, c.zoom, c.anim) end

    local function load()
        bear:ClearModel()
        pcall(bear.SetDisplayInfo, bear, BEAR_DISPLAY)
        elf:ClearModel()
        LoadElf(elf)
        Place(f)
    end
    for _, m in ipairs({ elf, bear }) do
        m:SetScript("OnShow", function(self) self:refresh() end)
        if m.HasScript and m:HasScript("OnModelLoaded") then
            m:SetScript("OnModelLoaded", function(self) self:refresh() end)
        end
    end
    f:SetScript("OnShow", load)
    f.elf, f.bear, f.Reload = elf, bear, load
    logos[#logos + 1] = f
    if f:IsVisible() then load() end
    return f
end

------------------------------------------------------------------------
-- /hpc logo : nudge the bear and the elf into place, live
------------------------------------------------------------------------
local tuner
function ns.ToggleLogoTuner()
    if tuner then tuner:SetShown(not tuner:IsShown()); return end
    local W = ns.W
    tuner = W.Panel(UIParent, W.BG, { 0.67, 0.83, 0.45, 1 })
    tuner:SetSize(300, 214)
    tuner:SetPoint("CENTER", 300, 0)
    tuner:SetFrameStrata("DIALOG")
    tuner:EnableMouse(true); tuner:SetMovable(true); tuner:RegisterForDrag("LeftButton")
    tuner:SetScript("OnDragStart", tuner.StartMoving); tuner:SetScript("OnDragStop", tuner.StopMovingOrSizing)
    local title = W.Text(tuner, "GameFontNormal", nil, "LEFT")
    title:SetPoint("TOPLEFT", 10, -8); title:SetText("Logo tuner  |cff999999(drag to move)|r")
    local close = CreateFrame("Button", nil, tuner, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)

    local steps = { x = 0.01, y = 0.01, zoom = 0.05, facing = 0.1, w = 0.02, h = 0.02 }
    local function nudge(who, key, dir)
        local t = Tune()[who]
        t[key] = t[key] + steps[key] * dir
        if key == "zoom" then t[key] = math.max(0.2, t[key]) end
        ns.RefreshLogos()
    end
    local rows = {
        { "Left / Right", "x", -1, 1 }, { "Down / Up", "y", -1, 1 },
        { "Bigger / Smaller", "zoom", -1, 1 }, { "Turn", "facing", -1, 1 },
    }
    local y = -30
    for col, who in ipairs({ "elf", "bear" }) do
        local hx = 110 + (col - 1) * 90
        local h = W.Text(tuner, "GameFontHighlightSmall", nil, "CENTER")
        h:SetPoint("TOPLEFT", hx, y); h:SetWidth(84); h:SetText(who == "elf" and "Night elf" or "Bear")
    end
    y = y - 18
    for _, r in ipairs(rows) do
        local l = W.Text(tuner, "GameFontHighlightSmall", nil, "LEFT")
        l:SetPoint("TOPLEFT", 10, y - 4); l:SetText(r[1])
        for col, who in ipairs({ "elf", "bear" }) do
            local hx = 110 + (col - 1) * 90
            local a = W.Button(tuner, r[2] == "y" and "v" or "<", 40, 20); a:SetPoint("TOPLEFT", hx, y)
            local b = W.Button(tuner, r[2] == "y" and "^" or ">", 40, 20); b:SetPoint("TOPLEFT", hx + 44, y)
            a:SetScript("OnClick", function() nudge(who, r[2], r[3]) end)
            b:SetScript("OnClick", function() nudge(who, r[2], r[4]) end)
        end
        y = y - 26
    end
    local reset = W.Button(tuner, "Reset", 70, 22); reset:SetPoint("BOTTOMLEFT", 10, 10)
    reset:SetScript("OnClick", function() ns.db.logoTune = nil; ns.db.logoTuneVersion = TUNE_VERSION; ns.RefreshLogos() end)
    local print_ = W.Button(tuner, "Print values", 100, 22); print_:SetPoint("BOTTOMRIGHT", -10, 10)
    print_:SetScript("OnClick", function()
        local t = Tune()
        for _, who in ipairs({ "elf", "bear" }) do
            local c = t[who]
            ns.Print(("%s: x=%.2f y=%.2f w=%.2f h=%.2f zoom=%.2f facing=%.2f"):format(who, c.x, c.y, c.w, c.h, c.zoom, c.facing))
        end
    end)
    -- make sure there's a logo on screen to look at
    if not (HunterPetCodexFrame and HunterPetCodexFrame:IsShown()) then ns.ToggleMain("collection") end
end
