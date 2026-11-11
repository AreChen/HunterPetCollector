-- Hunter Pet Collector - backup codes
-- /hpc export gives a short text code holding your whole collection. Keep it
-- anywhere outside the game (Discord, a note on your phone). If your WTF
-- folder is ever lost, the game is reinstalled or you move PC, /hpc import
-- puts the collection back. A code only works for the character it was
-- made for (same name and class) and the same game version.
local ADDON, ns = ...
local W

local B36 = "0123456789abcdefghijklmnopqrstuvwxyz"

local function enc(n)
    n = math.floor(n)
    if n == 0 then return "0" end
    local out = ""
    while n > 0 do
        local r = n % 36
        out = B36:sub(r + 1, r + 1) .. out
        n = math.floor(n / 36)
    end
    return out
end

local function dec(str)
    local n = 0
    for i = 1, #str do
        local c = B36:find(str:sub(i, i), 1, true)
        if not c then return nil end
        n = n * 36 + (c - 1)
    end
    return n
end

local FLAVOR_CODE = { mop = "m", forever = "f" }
local FLAVOR_FROM = { m = "mop", f = "forever" }

local function ShortName() return (strsplit("-", ns.playerName or "")) end

local function Checksum(body)
    return enc(ns.Hash(body, 5381) % 2176782336)   -- 6 base36 digits
end

function ns.MakeBackupCode()
    local ids = {}
    for id in pairs(ns.Collected()) do ids[#ids + 1] = id end
    table.sort(ids)
    for i, id in ipairs(ids) do ids[i] = enc(id) end
    local body = table.concat({ "HPC1", FLAVOR_CODE[ns.flavor] or "m", ShortName(), ns.playerClassFile or "", table.concat(ids, ".") }, "-")
    return body .. "-" .. Checksum(body), #ids
end

-- returns count, or nil + reason
function ns.ImportBackupCode(code)
    code = (code or ""):gsub("%s", "")
    local body, sum = code:match("^(.+)%-(%w+)$")
    if not body or Checksum(body) ~= sum then return nil, "That code isn't valid. Check it was copied in full." end
    local ver, fl, name, class, list = strsplit("-", body, 5)
    if ver ~= "HPC1" then return nil, "That code is from a different version of the addon." end
    if FLAVOR_FROM[fl] ~= ns.flavor then return nil, "That code is for the other game version (MoP Classic / Forever)." end
    if name ~= ShortName() or class ~= (ns.playerClassFile or "") then
        return nil, "That code belongs to " .. tostring(name) .. ", not this character."
    end
    local col, n = ns.Collected(), 0
    for part in (list or ""):gmatch("[^%.]+") do
        local id = dec(part)
        if id and not col[id] then
            col[id] = { t = time(), name = ns.looks[id] and ns.looks[id].name or nil, auto = "import" }
            n = n + 1
        end
    end
    ns.SignCollection()
    ns.Fire("COLLECTION_CHANGED")
    return n
end

------------------------------------------------------------------------
-- Copy / paste window
------------------------------------------------------------------------
local box

local function BuildBox()
    W = ns.W
    box = W.Panel(UIParent, W.BG, { 0.67, 0.83, 0.45, 1 })
    box:SetSize(460, 220)
    box:SetPoint("CENTER")
    box:SetFrameStrata("DIALOG")
    box:EnableMouse(true); box:SetMovable(true); box:RegisterForDrag("LeftButton")
    box:SetScript("OnDragStart", box.StartMoving); box:SetScript("OnDragStop", box.StopMovingOrSizing)
    tinsert(UISpecialFrames, "HunterPetCollectorBackupBox")
    _G.HunterPetCollectorBackupBox = box

    box.title = W.Text(box, "GameFontNormal", 14, "LEFT")
    box.title:SetPoint("TOPLEFT", 12, -10)
    box.info = W.Text(box, "GameFontHighlightSmall", nil, "LEFT")
    box.info:SetPoint("TOPLEFT", box.title, "BOTTOMLEFT", 0, -6)
    box.info:SetPoint("RIGHT", -12, 0)

    local holder = W.Panel(box, { 0.02, 0.02, 0.03, 1 })
    holder:SetPoint("TOPLEFT", 12, -60)
    holder:SetPoint("BOTTOMRIGHT", -12, 44)
    local scroll = CreateFrame("ScrollFrame", nil, holder, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -26, 6)
    local eb = CreateFrame("EditBox", nil, scroll)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetFontObject("GameFontHighlightSmall")
    eb:SetWidth(390)
    eb:SetMaxLetters(0)
    eb:SetScript("OnEscapePressed", function() box:Hide() end)
    scroll:SetScrollChild(eb)
    box.edit = eb

    local close = CreateFrame("Button", nil, box, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)

    box.action = W.Button(box, "Import", 100, 22)
    box.action:SetPoint("BOTTOMRIGHT", -12, 12)
    box.status = W.Text(box, "GameFontHighlightSmall", nil, "LEFT")
    box.status:SetPoint("BOTTOMLEFT", 12, 17)
    box.status:SetPoint("RIGHT", box.action, "LEFT", -8, 0)
end

function ns.ShowExport()
    if not box then BuildBox() end
    local code, n = ns.MakeBackupCode()
    box.title:SetText("Backup code")
    box.info:SetText(("Your %d collected looks. Press Ctrl+C to copy, then keep it somewhere outside the game."):format(n))
    box.edit:SetText(code)
    box.edit:SetScript("OnTextChanged", function(self, user) if user then self:SetText(code); self:HighlightText() end end)
    box.edit:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    box.action:Hide()
    box.status:SetText("")
    box:Show()
    box.edit:SetFocus()
    box.edit:HighlightText()
    ns.cdb.lastExportCount = n
end

function ns.ShowImport()
    if not box then BuildBox() end
    box.title:SetText("Restore from a backup code")
    box.info:SetText("Paste the code you saved with /hpc export (Ctrl+V), then press Import. Looks are added; nothing is removed.")
    box.edit:SetText("")
    box.edit:SetScript("OnTextChanged", nil)
    box.edit:SetScript("OnEditFocusGained", nil)
    box.action:Show()
    box.status:SetText("")
    box.action:SetScript("OnClick", function()
        local n, err = ns.ImportBackupCode(box.edit:GetText())
        if n then
            box.status:SetText(("|cff4cff4cRestored %d look%s.|r"):format(n, n == 1 and "" or "s"))
            ns.Print(("Restored %d look%s from your backup code."):format(n, n == 1 and "" or "s"))
        else
            box.status:SetText("|cffff5555" .. err .. "|r")
        end
    end)
    box:Show()
    box.edit:SetFocus()
end

-- a gentle reminder now and then, once you've collected a few new looks
ns.On("READY", function()
    if ns.playerClass ~= "HUNTER" then return end
    ns.After(25, function()
        local _, count = ns.GetScore()
        if count - (ns.cdb.lastExportCount or 0) >= 15 then
            ns.Print("Tip: type |cffffd100/hpc export|r to get a backup code for your collection and keep it somewhere safe.")
        end
    end)
end)
