-- Hunter Pet Collector - Options panel (Game Menu > Options > AddOns > Hunter Pet Collector)
local ADDON, ns = ...
local W = ns.W
local L = ns.L

local panel, category
local controls = {}

local function Header(parent, text, y)
    local t = W.Text(parent, "GameFontNormal", nil, "LEFT")
    t:SetPoint("TOPLEFT", 16, y)
    t:SetText(L[text])
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetTexture(W.WHITE)
    line:SetVertexColor(1, 0.82, 0, 0.25)
    line:SetHeight(1)
    line:SetPoint("LEFT", t, "RIGHT", 8, 0)
    line:SetPoint("RIGHT", parent, "RIGHT", -16, 0)
    return t
end

local function Check(parent, label, desc, key, y, onChange)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", 20, y)
    cb:SetSize(26, 26)
    local text = cb.Text or cb.text
    if type(text) ~= "table" then
        text = W.Text(cb, "GameFontHighlight", nil, "LEFT")
        text:SetPoint("LEFT", cb, "RIGHT", 2, 1)
    end
    text:SetText(L[label])
    local d = W.Text(parent, "GameFontDisableSmall", nil, "LEFT")
    d:SetPoint("TOPLEFT", cb, "BOTTOMLEFT", 28, 4)
    d:SetPoint("RIGHT", parent, "RIGHT", -24, 0)
    d:SetText(L[desc])
    cb:SetScript("OnClick", function(self)
        local v = self:GetChecked() and true or false
        ns.db[key] = v
        if onChange then onChange(v) end
    end)
    cb.refresh = function() cb:SetChecked(ns.db[key] and true or false) end
    controls[#controls + 1] = cb
    return cb
end

local function Button(parent, text, width, x, y, onClick)
    local b = W.Button(parent, text, width, 24)
    function b:SetText(value) self.text:SetText(L[value]) end
    b:SetPoint("TOPLEFT", x, y)
    b:SetText(L[text])
    b:SetScript("OnClick", onClick)
    return b
end

local function Build(parent)
    panel = CreateFrame("Frame", "HunterPetCodexOptions", parent)
    panel:SetAllPoints(parent)
    panel.name = "Hunter Pet Collector"
    panel:Hide()

    local icon = ns.CreateLogo(panel, 56)
    icon:SetPoint("TOPLEFT", 10, -6)
    local title = W.Text(panel, "GameFontNormalLarge", 20, "LEFT")
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -2)
    title:SetText("Hunter Pet Collector")
    local sub = W.Text(panel, "GameFontHighlightSmall", nil, "LEFT")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    sub:SetText(("v%s  -  %s"):format(ns.VERSION, ns.flavorName))

    local stats = W.Text(panel, "GameFontHighlight", nil, "RIGHT")
    stats:SetPoint("TOPRIGHT", -20, -22)
    panel.stats = stats

    -- everything below the title scrolls, so the panel fits any screen
    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -62)
    scroll:SetPoint("BOTTOMRIGHT", -28, 8)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(600, 900)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function(self, w) if w and w > 0 then content:SetWidth(w) end end)
    panel.content = content

    local y = -8
    Header(content, "Map pins", y); y = y - 22
    Check(content, "Show pins on the world map", "Spawn locations of the beasts you've pinned, coloured by rarity.", "showWorldPins", y,
        function() ns.Fire("PINS_CHANGED") end); y = y - 44
    Check(content, "Show pins on the minimap", "Nearby pinned spawns appear around the edge of your minimap.", "showMinimapPins", y); y = y - 44
    Check(content, "Remove pins once the look is collected", "Off: pins stay until you clear them yourself.", "autoClearPins", y); y = y - 46

    local sizeLabel = W.Text(content, "GameFontHighlight", nil, "LEFT")
    sizeLabel:SetPoint("TOPLEFT", 24, y - 5)
    sizeLabel:SetText(L["Pin size:"])
    local sizes = { { "Small", 0.8 }, { "Medium", 1 }, { "Large", 1.3 } }
    panel.sizeButtons = {}
    for i, s in ipairs(sizes) do
        local b = Button(content, s[1], 80, 90 + (i - 1) * 86, y, function()
            ns.db.pinScale = s[2]
            ns.Fire("PINS_CHANGED")
            panel.refresh()
        end)
        b.value = s[2]
        panel.sizeButtons[i] = b
    end
    Button(content, "Clear all pins", 120, 370, y, function() ns.ClearPins(); panel.refresh() end)
    y = y - 40

    Header(content, "Tracking arrow", y); y = y - 22
    Check(content, "Show the tracking arrow", "Points to the nearest spawn of the look you're tracking and walks you through each spawn point in turn.", "showArrow", y,
        function() ns.UpdateArrowVisibility() end); y = y - 44
    Check(content, "Use a paw symbol for minimap pins", "Off: show the beast family's icon instead.", "minimapPaw", y); y = y - 46
    Button(content, "Stop tracking", 120, 20, y, function() ns.StopTracking() end)
    Button(content, "Reset arrow position", 150, 146, y, function() ns.ResetArrowPosition() end)
    y = y - 40

    Header(content, "Hunt mode", y); y = y - 22
    local huntNote = W.Text(content, "GameFontHighlightSmall", nil, "LEFT")
    huntNote:SetPoint("TOPLEFT", 24, y)
    huntNote:SetPoint("RIGHT", content, "RIGHT", -24, 0)
    huntNote:SetText(L["Shows every look you haven't collected on your maps, and the arrow leads you to the nearest one. Looks disappear as you collect them."])
    y = y - 30
    local huntBtn = Button(content, "Start hunting", 140, 20, y, function() ns.ToggleHunting(); panel.refresh() end)
    panel.huntBtn = huntBtn
    local lvl = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    lvl:SetPoint("TOPLEFT", 176, y + 1)
    lvl:SetSize(26, 26)
    local lvlText = (type(lvl.Text) == "table" and lvl.Text) or W.Text(lvl, "GameFontHighlight", nil, "LEFT")
    lvlText:ClearAllPoints(); lvlText:SetPoint("LEFT", lvl, "RIGHT", 2, 1)
    lvlText:SetText(L["Only beasts I can tame at my level"])
    lvl:SetScript("OnClick", function(self) ns.HuntCfg().levelOnly = self:GetChecked() and true or false; ns.RefreshHunt(); panel.refresh() end)
    panel.huntLevel = lvl
    y = y - 34
    local minLabel = W.Text(content, "GameFontHighlight", nil, "LEFT")
    minLabel:SetPoint("TOPLEFT", 24, y - 5)
    minLabel:SetText(L["Hunt:"])
    panel.huntRarity = {}
    local mins = { { "Everything", 1 }, { "Uncommon+", 2 }, { "Rare+", 3 }, { "Epic+", 4 } }
    for i, m in ipairs(mins) do
        local b = Button(content, m[1], 100, 70 + (i - 1) * 106, y, function()
            ns.HuntCfg().minRarity = m[2]; ns.RefreshHunt(); panel.refresh()
        end)
        b.value = m[2]
        panel.huntRarity[i] = b
    end
    y = y - 40

    Header(content, "Rare tracker", y); y = y - 22
    Check(content, "Alert me when a wanted beast is nearby", "Watches nameplates, your mouseover, your target and rare markers on the minimap.", "alertEnabled", y); y = y - 44
    Check(content, "Play a sound and flash the game icon", "Uses the raid warning sound.", "alertSound", y); y = y - 46
    local modeLabel = W.Text(content, "GameFontHighlight", nil, "LEFT")
    modeLabel:SetPoint("TOPLEFT", 24, y - 5)
    modeLabel:SetText(L["Alert for:"])
    local modes = { { "Tracked look", "tracked" }, { "Uncollected rares", "rares" }, { "Any uncollected", "all" } }
    panel.modeButtons = {}
    for i, m in ipairs(modes) do
        local b = Button(content, m[1], 128, 90 + (i - 1) * 134, y, function()
            ns.db.alertMode = m[2]
            panel.refresh()
        end)
        b.value = m[2]
        panel.modeButtons[i] = b
    end
    y = y - 34
    Button(content, "Test alert", 120, 20, y, function() ns.TestAlert() end)
    y = y - 40

    Header(content, "Display", y); y = y - 22
    Check(content, "Show minimap button", "Left-click opens the collection, right-click opens the leaderboard.", "showMinimapButton", y,
        function(v) ns.db.minimap.hide = not v; ns.UpdateMinimapButton() end); y = y - 44
    Check(content, "Show collection info on beast tooltips", "Hovering a tameable beast shows its rarity and whether you have its look.", "tooltip", y); y = y - 50

    Header(content, "Pet XP Bar", y); y = y - 22
    Check(content, "Show the Pet XP Bar", "Hunters see their own pet, animated, with its level and experience. Other classes get a pretend wolf that levels up with them, just for fun.", "petXPBar", y,
        function() if ns.XP and ns.XP.UpdateXP then ns.XP.UpdateXP() end end); y = y - 44
    Button(content, "Pet XP Bar options", 150, 20, y, function() if ns.XP and ns.XP.OpenOptions then ns.XP.OpenOptions() end end)
    y = y - 40

    Header(content, "Pet feeding", y); y = y - 22
    local fnote = W.Text(content, "GameFontDisableSmall", nil, "LEFT")
    fnote:SetPoint("TOPLEFT", 24, y); fnote:SetPoint("RIGHT", content, "RIGHT", -24, 0)
    fnote:SetText(L["For game versions where pets need feeding, like WoW: Forever."])
    y = y - 18
    Check(content, "Show the Feed button", "One click feeds your pet the best food in your bags that it will eat. A dot shows its mood: green happy, yellow content, red unhappy. Shift-drag to move it.", "feedButton", y,
        function() if ns.Feed then ns.Feed.Update() end end); y = y - 56
    Check(content, "Warn when my pet isn't happy", "A message and sound when your pet drops to content or unhappy (unhappy pets do less damage).", "feedWarn", y); y = y - 46
    Button(content, "Reset Feed button position", 180, 20, y, function() if ns.Feed then ns.Feed.ResetPosition() end end)
    y = y - 40

    Header(content, "Leaderboard", y); y = y - 22
    Check(content, "Share my score", "Send your points to other Pet Collector users in your guild, group and realm.", "shareScore", y,
        function(v) if v then ns.BroadcastScore(true) end end); y = y - 44
    Check(content, "Use the realm-wide channel", "Reach every hunter on your server with the addon. It joins automatically. If your game client doesn't allow that, type /join HPCodexBoard once.", "useChannel", y); y = y - 56
    Check(content, "Share with friends on this server", "Friends on your friends list who are on this server get your score and send theirs back.", "shareWithFriends", y); y = y - 46
    Button(content, "Check connection", 140, 20, y, function() ns.CommReport() end)
    y = y - 40

    Header(content, "Backup", y); y = y - 26
    local bnote = W.Text(content, "GameFontHighlightSmall", nil, "LEFT")
    bnote:SetPoint("TOPLEFT", 24, y)
    bnote:SetPoint("RIGHT", content, "RIGHT", -24, 0)
    bnote:SetText("Your collection is saved by the game and backed up account-wide. For extra safety (new PC, reinstall, lost WTF folder), save a backup code outside the game.")
    y = y - 32
    Button(content, "Get backup code", 150, 20, y, function() ns.ShowExport() end)
    Button(content, "Restore from code", 150, 176, y, function() ns.ShowImport() end)
    y = y - 40

    Header(content, "Collection", y); y = y - 26
    local note = W.Text(content, "GameFontHighlightSmall", nil, "LEFT")
    note:SetPoint("TOPLEFT", 24, y)
    note:SetPoint("RIGHT", content, "RIGHT", -24, 0)
    note:SetText("Looks are only collected by taming or summoning the beast (and from the stable where the game allows it). There's no manual marking, so every score on the leaderboard was earned in-game.")
    y = y - 40
    Button(content, "Open the collection", 140, 20, y, function()
        -- don't close the game's settings window from here (that taints the
        -- game menu); just put the collection on top of it
        ns.ToggleMain("collection")
        local f = HunterPetCodexFrame
        if f and f:IsShown() then
            f:SetFrameStrata("DIALOG")
            if not f.strataHooked then
                f.strataHooked = true
                f:HookScript("OnHide", function(self) self:SetFrameStrata("HIGH") end)
            end
        end
    end)
    Button(content, "Rescan my pet", 140, 166, y, function() ns.ScanActivePet(); ns.ScanStable(); panel.refresh() end)
    content:SetHeight(-y + 40)

    function panel.refresh()
        ns.db.showMinimapButton = not ns.db.minimap.hide
        for _, c in ipairs(controls) do c.refresh() end
        local h = ns.HuntCfg()
        panel.huntBtn:SetText(h.on and L["Stop hunting (%d)"]:format(ns.HuntCount()) or L["Start hunting"])
        panel.huntLevel:SetChecked(h.levelOnly)
        for _, b in ipairs(panel.huntRarity) do
            if h.minRarity == b.value then b:LockHighlight() else b:UnlockHighlight() end
        end
        for _, b in ipairs(panel.modeButtons) do
            if (ns.db.alertMode or "rares") == b.value then b:LockHighlight() else b:UnlockHighlight() end
        end
        for _, b in ipairs(panel.sizeButtons) do
            if math.abs((ns.db.pinScale or 1) - b.value) < 0.01 then b:LockHighlight() else b:UnlockHighlight() end
        end
        local points, count, total, maxPoints = ns.GetScore()
        stats:SetText(("|cffffd100%d|r / %d points\n%d / %d looks   %d pinned"):format(points, maxPoints, count, total, ns.PinCount()))
    end
    panel:SetScript("OnShow", panel.refresh)

    return panel
end

function ns.BuildOptions(parent)
    if panel then return panel end
    return Build(parent)
end

function ns.OpenOptions()
    ns.ToggleMain("options")
end

ns.On("PINS_CHANGED", function() if panel and panel:IsShown() then panel.refresh() end end)
ns.On("TRACKING_CHANGED", function() if panel and panel:IsShown() then panel.refresh() end end)
