-- Hunter Pet Collector - tracking arrow and rare tracker
--   * Track a look: an arrow guides you to its nearest spawn point, then on to the
--     next one once you've checked it, so you can sweep every spawn of a rare.
--   * Rare tracker: nameplates, mouseover, target and minimap rare markers are
--     watched; a wanted beast pops an alert with its model, a sound and a Target button.
local ADDON, ns = ...
local W = ns.W

local ARRIVE_YARDS = 35       -- "you're here, look around"
local VISIT_SECONDS = 5       -- time spent at a spawn before the arrow moves on
local LIVE_SECONDS = 120      -- how long a sighting from a rare marker stays the target

------------------------------------------------------------------------
-- Tracking state
------------------------------------------------------------------------
local visited = {}            -- [mapID * 1e7 + packed] = true   (this session)
local live                    -- { mapID, x, y, t, npc }   exact position from a rare marker
local trackedCache, trackedCacheId
local current            -- the spawn the arrow points at: { key, mapID, packed, wx, wy, npc, ... }

local function TrackedId()
    local t = ns.cdb.tracking
    return t[ns.flavor]
end

local function TrackedLook()
    local id = TrackedId()
    return id and ns.looks[id]
end

function ns.IsTracking(look)
    return look ~= nil and TrackedId() == look.id
end

-- set of NPC ids (with spawn data) for the tracked look; used by the map pins
function ns.TrackedNPCs()
    local look = TrackedLook()
    if not look then return nil end
    if trackedCacheId ~= look.id then
        trackedCacheId, trackedCache = look.id, {}
        local spawns = ns.Spawns()
        for _, s in ipairs(look.sources) do
            if spawns[s.npc] then trackedCache[s.npc] = true end
        end
        if not next(trackedCache) then trackedCache = nil end
    end
    return trackedCache
end

function ns.StartTracking(look)
    if not look then return end
    if not ns.LookHasSpawns(look) then
        ns.Print("No spawn coordinates are known for " .. look.name .. ", so it can't be tracked.")
        return
    end
    ns.cdb.tracking[ns.flavor] = look.id
    wipe(visited)
    live = nil
    trackedCacheId = nil
    if not ns.db.showArrow then ns.db.showArrow = true end
    ns.Print(("Tracking |cff%s%s|r. Follow the arrow; it moves on to the next spawn once you've checked one."):format(ns.RARITY[look.rarity].hex, look.name))
    ns.Fire("TRACKING_CHANGED", look)
    ns.Fire("PINS_CHANGED")
end

function ns.StopTracking()
    if not TrackedId() then return end
    ns.cdb.tracking[ns.flavor] = nil
    live, trackedCacheId, trackedCache = nil, nil, nil
    ns.Print("Stopped tracking.")
    ns.Fire("TRACKING_CHANGED")
    ns.Fire("PINS_CHANGED")
end

function ns.ToggleTracking(look)
    if ns.IsTracking(look) then ns.StopTracking() else ns.StartTracking(look) end
end

------------------------------------------------------------------------
-- Hunt mode: every uncollected look (matching the hunt filters) is shown on
-- the maps and the arrow leads to the nearest one. Looks drop off as you
-- collect them.
------------------------------------------------------------------------
local huntSet, huntCount, huntDirty = nil, 0, true

local function HuntCfg()
    ns.cdb.hunt = ns.cdb.hunt or {}
    local h = ns.cdb.hunt
    if h.minRarity == nil then h.minRarity = 1 end
    if h.levelOnly == nil then h.levelOnly = true end
    return h
end
ns.HuntCfg = HuntCfg

function ns.IsHunting() return HuntCfg().on and true or false end

local function HuntWants(look)
    local h = HuntCfg()
    if ns.IsCollected(look) or look.rarity < h.minRarity then return false end
    if h.levelOnly then
        local lvl = UnitLevel("player") or 0
        local ok = false
        for _, s in ipairs(look.sources) do
            if (s.minLevel or 0) <= lvl then ok = true break end
        end
        if not ok then return false end
    end
    return true
end
ns.HuntWants = HuntWants

function ns.HuntNPCs()
    if not ns.IsHunting() then return nil end
    if huntDirty or not huntSet then
        huntDirty = false
        huntSet, huntCount = {}, 0
        local spawns = ns.Spawns()
        for _, look in ipairs(ns.lookList) do
            if HuntWants(look) then
                local any = false
                for _, s in ipairs(look.sources) do
                    if spawns[s.npc] then huntSet[s.npc] = true; any = true end
                end
                if any then huntCount = huntCount + 1 end
            end
        end
    end
    return huntSet
end

function ns.HuntCount()
    ns.HuntNPCs()
    return huntCount
end

function ns.RefreshHunt()
    huntDirty = true
    current = nil
    ns.Fire("PINS_CHANGED")
    if ns.UpdateArrowVisibility then ns.UpdateArrowVisibility() end
end

function ns.SetHunting(on)
    HuntCfg().on = on and true or false
    huntDirty = true
    wipe(visited)
    if on then
        if not ns.db.showArrow then ns.db.showArrow = true end
        local n = ns.HuntCount()
        ns.Print(("Hunting %d uncollected look%s. They're on your map and minimap, and the arrow leads to the nearest one."):format(n, n == 1 and "" or "s"))
    else
        ns.Print("Stopped hunting.")
    end
    ns.Fire("TRACKING_CHANGED")
    ns.RefreshHunt()
end

function ns.ToggleHunting() ns.SetHunting(not ns.IsHunting()) end

------------------------------------------------------------------------
-- Choosing the target spawn
------------------------------------------------------------------------

local function PickHuntTarget(cont, px, py)
    local hunt = ns.HuntNPCs()
    if not hunt then return nil end
    local spawns = ns.Spawns()
    local best, bestD, total, left = nil, nil, 0, 0
    for m, npcs in pairs(ns.MapsWithSpawns()) do
        if ns.MapContinent(m) == cont then
            for npc in pairs(npcs) do
                if hunt[npc] then
                    for _, p in ipairs(spawns[npc][m]) do
                        local wp = ns.WorldPos(m, p)
                        if wp then
                            total = total + 1
                            local key = m * 10000000 + p
                            if not visited[key] then
                                left = left + 1
                                local d = (wp[2] - px) ^ 2 + (wp[3] - py) ^ 2
                                if not bestD or d < bestD then
                                    best, bestD = { key = key, mapID = m, packed = p, wx = wp[2], wy = wp[3], npc = npc }, d
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    if total > 0 and not best then
        wipe(visited)
        return PickHuntTarget(cont, px, py)
    end
    if best then best.total, best.left = total, left; return best end
    return { elsewhere = ns.HuntCount() > 0 and "other continents" or "" , none = ns.HuntCount() == 0 }
end

local function PickTarget(cont, px, py)
    local look = TrackedLook()
    if not look then return PickHuntTarget(cont, px, py) end
    if live and (GetTime() - live.t) < LIVE_SECONDS then
        local wp = ns.WorldPos(live.mapID, live.packed)
        if wp and wp[1] == cont then
            return { key = "live", mapID = live.mapID, packed = live.packed, wx = wp[2], wy = wp[3], npc = live.npc, live = true }
        end
    end
    local spawns = ns.Spawns()
    local best, bestD, anyOnCont, total, left = nil, nil, false, 0, 0
    local otherZones = {}
    for _, src in ipairs(look.sources) do
        local maps = spawns[src.npc]
        if maps then
            for m, pts in pairs(maps) do
                for _, p in ipairs(pts) do
                    local wp = ns.WorldPos(m, p)
                    if wp and wp[1] == cont then
                        anyOnCont = true
                        total = total + 1
                        local key = m * 10000000 + p
                        if not visited[key] then
                            left = left + 1
                            local d = (wp[2] - px) ^ 2 + (wp[3] - py) ^ 2
                            if not bestD or d < bestD then
                                best, bestD = { key = key, mapID = m, packed = p, wx = wp[2], wy = wp[3], npc = src.npc }, d
                            end
                        end
                    else
                        otherZones[src.zone ~= "" and src.zone or ("map " .. m)] = true
                    end
                end
            end
        end
    end
    if anyOnCont and not best then
        -- every spawn on this continent has been checked: start the sweep again
        wipe(visited)
        ns.Print("You've checked every spawn of " .. look.name .. " here. Starting the sweep again.")
        return PickTarget(cont, px, py)
    end
    if best then
        best.total, best.left = total, left
        return best
    end
    local zones = {}
    for z in pairs(otherZones) do zones[#zones + 1] = z end
    table.sort(zones)
    return { elsewhere = table.concat(zones, ", ") }
end

function ns.SkipSpawn()
    if current and current.key and current.key ~= "live" then
        visited[current.key] = true
    elseif current and current.live then
        live = nil
    end
    current = nil
end

------------------------------------------------------------------------
-- Arrow frame
------------------------------------------------------------------------
local arrowFrame

local function Compass(angle)
    -- angle: radians counter-clockwise from north
    local dirs = { "N", "NW", "W", "SW", "S", "SE", "E", "NE" }
    local i = math.floor(((angle % (2 * math.pi)) / (2 * math.pi)) * 8 + 0.5) % 8 + 1
    return dirs[i]
end

local function BuildArrow()
    local f = CreateFrame("Button", "HunterPetCodexArrow", UIParent)
    f:SetSize(170, 92)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f:Hide()

    local pos = ns.db.arrowPos
    if pos and pos[1] then
        f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        f:SetPoint("TOP", UIParent, "TOP", 0, -140)
    end

    f.arrow = f:CreateTexture(nil, "ARTWORK")
    f.arrow:SetTexture("Interface\\Minimap\\MinimapArrow")
    f.arrow:SetSize(52, 52)
    f.arrow:SetPoint("TOP", 0, 0)

    f.pulse = f:CreateTexture(nil, "BACKGROUND")
    f.pulse:SetTexture("Interface\\Cooldown\\star4")
    f.pulse:SetBlendMode("ADD")
    f.pulse:SetSize(80, 80)
    f.pulse:SetPoint("CENTER", f.arrow, "CENTER")
    f.pulse:Hide()

    f.title = W.Text(f, "GameFontNormal", 13, "CENTER")
    f.title:SetPoint("TOP", f.arrow, "BOTTOM", 0, 2)
    f.title:SetWidth(240)
    f.title:SetWordWrap(false)
    f.dist = W.Text(f, "GameFontHighlight", 12, "CENTER")
    f.dist:SetPoint("TOP", f.title, "BOTTOM", 0, -2)
    f.sub = W.Text(f, "GameFontDisableSmall", nil, "CENTER")
    f.sub:SetPoint("TOP", f.dist, "BOTTOM", 0, -2)
    f.sub:SetWidth(260)

    f:SetScript("OnDragStart", function(self) if IsShiftKeyDown() then self:StartMoving() end end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        ns.db.arrowPos = { p, rp, x, y }
    end)
    f:SetScript("OnClick", function(_, btn)
        if btn == "RightButton" then
            if TrackedLook() then ns.StopTracking() elseif ns.IsHunting() then ns.SetHunting(false) end
        elseif IsControlKeyDown and IsControlKeyDown() then
            ns.SkipSpawn()
        else
            local look = TrackedLook() or (current and current.npc and ns.npcToLook[current.npc])
            if look then
                if not (HunterPetCodexFrame and HunterPetCodexFrame:IsShown()) then ns.ToggleMain("collection") end
                ns.SelectLook(look)
            end
        end
    end)
    f:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Hunter Pet Collector - tracking", 1, 1, 1)
        local look = TrackedLook()
        if look then GameTooltip:AddLine(look.name, unpack(ns.RARITY[look.rarity].color)) end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Click: open in the collection", 0.6, 0.6, 0.6)
        GameTooltip:AddLine("Ctrl-click: skip to the next spawn", 0.6, 0.6, 0.6)
        GameTooltip:AddLine("Shift-drag: move", 0.6, 0.6, 0.6)
        GameTooltip:AddLine("Right-click: stop tracking", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local acc, arriveT, pulseT = 0, nil, 0
    f:SetScript("OnUpdate", function(self, elapsed)
        pulseT = pulseT + elapsed
        if self.pulse:IsShown() then self.pulse:SetAlpha(0.35 + 0.35 * math.sin(pulseT * 5)) end
        acc = acc + elapsed
        if acc < 0.05 then return end
        acc = 0
        local look = TrackedLook()
        local hunting = not look and ns.IsHunting()
        if not look and not hunting then self:Hide(); return end
        if hunting then
            look = current and current.npc and ns.npcToLook[current.npc]
            if look then
                local r = ns.RARITY[look.rarity]
                self.title:SetText("Hunting: " .. look.name)
                self.title:SetTextColor(r.color[1], r.color[2], r.color[3])
            else
                self.title:SetText(("Hunting %d looks"):format(ns.HuntCount()))
                self.title:SetTextColor(0.67, 0.83, 0.45)
            end
        else
            local r = ns.RARITY[look.rarity]
            self.title:SetText(look.name)
            self.title:SetTextColor(r.color[1], r.color[2], r.color[3])
        end

        local _, cont, px, py = ns.PlayerPos()
        if not cont then
            self.arrow:Hide(); self.pulse:Hide()
            self.dist:SetText("|cff999999No position here|r")
            self.sub:SetText("The arrow works outdoors")
            return
        end
        if not current or (current.wx == nil and not current.elsewhere) then current = PickTarget(cont, px, py) end
        if not current then return end
        if current.none then
            self.arrow:Hide(); self.pulse:Hide()
            self.dist:SetText("|cff4cff4cEverything collected!|r")
            self.sub:SetText("Nothing left that matches your hunt filters")
            if math.random() < 0.02 then current = nil end
            return
        end
        if current.elsewhere then
            self.arrow:Hide(); self.pulse:Hide()
            self.dist:SetText("|cffffd100Not on this continent|r")
            self.sub:SetText(current.elsewhere ~= "" and ("Found in: " .. current.elsewhere) or "")
            -- check again now and then (you may have travelled)
            if math.random() < 0.02 then current = nil end
            return
        end

        local dNorth, dWest = current.wx - px, current.wy - py
        local dist = math.sqrt(dNorth * dNorth + dWest * dWest)
        local angle = math.atan2(dWest, dNorth)
        local facing = GetPlayerFacing and GetPlayerFacing()
        if facing and ns.IsSecret(facing) then facing = nil end

        look = look or ns.npcToLook[current.npc]
        local src
        for _, s in ipairs(look and look.sources or {}) do if s.npc == current.npc then src = s end end
        local where = src and src.zone ~= "" and src.zone or ""
        local x, y = ns.UnpackCoord(current.packed)
        if current.live then
            self.sub:SetText(("|cff4cff4cSpotted!|r  %s (%.0f, %.0f)"):format(where, x * 100, y * 100))
        else
            if hunting then
                self.sub:SetText(("%s (%.0f, %.0f)  -  %s"):format(where, x * 100, y * 100, src and src.name or ""))
            else
                self.sub:SetText(("Spawn %d of %d left  -  %s (%.0f, %.0f)"):format(current.left or 0, current.total or 0, where, x * 100, y * 100))
            end
        end

        if dist <= ARRIVE_YARDS then
            self.arrow:Hide()
            self.pulse:Show()
            self.dist:SetText("|cff4cff4cYou're here - look around!|r")
            arriveT = arriveT or GetTime()
            if GetTime() - arriveT > VISIT_SECONDS and not current.live then
                visited[current.key] = true
                current, arriveT = nil, nil
            end
            return
        end
        arriveT = nil
        self.pulse:Hide()
        self.arrow:Show()
        if facing then
            local rel = angle - facing
            self.arrow:SetRotation(rel)
            -- green when roughly ahead, yellow to the side, red behind
            local off = math.abs(((rel + math.pi) % (2 * math.pi)) - math.pi)
            if off < 0.5 then self.arrow:SetVertexColor(0.3, 1, 0.3)
            elseif off < 1.6 then self.arrow:SetVertexColor(1, 0.85, 0.2)
            else self.arrow:SetVertexColor(1, 0.3, 0.3) end
            self.dist:SetText(("%d yards"):format(dist))
        else
            self.arrow:SetRotation(angle)
            self.arrow:SetVertexColor(0.8, 0.8, 0.8)
            self.dist:SetText(("%d yards  %s"):format(dist, Compass(angle)))
        end
        -- re-pick now and then so the arrow follows the closest spawn as you move
        if math.random() < 0.03 and not current.live then current = nil end
    end)
    arrowFrame = f
end

function ns.UpdateArrowVisibility()
    if not arrowFrame then BuildArrow() end
    current = nil
    arrowFrame:SetShown(ns.db.showArrow and (TrackedLook() ~= nil or ns.IsHunting()) and ns.playerClass == "HUNTER")
end

function ns.ResetArrowPosition()
    ns.db.arrowPos = {}
    if not arrowFrame then BuildArrow() end
    arrowFrame:ClearAllPoints()
    arrowFrame:SetPoint("TOP", UIParent, "TOP", 0, -140)
end

ns.On("TRACKING_CHANGED", ns.UpdateArrowVisibility)
ns.On("COLLECTION_CHANGED", function(look, on)
    if ns.IsHunting() then
        huntDirty = true
        if current and current.npc and look and ns.npcToLook[current.npc] == look then current = nil end
        ns.Fire("PINS_CHANGED")
    end
    if on and look and ns.IsTracking(look) then
        ns.Print(("Got it! |cff%s%s|r collected - tracking stopped."):format(ns.RARITY[look.rarity].hex, look.name))
        ns.StopTracking()
    end
end)

------------------------------------------------------------------------
-- Rare tracker
------------------------------------------------------------------------
local alerted = {}       -- [npc] = time of last alert
local ALERT_COOLDOWN = 180

local function Wanted(npc)
    local look = ns.npcToLook[npc]
    if not look then return nil end
    if ns.IsTracking(look) then return look, "tracked" end
    if ns.IsCollected(look) then return nil end
    if ns.IsHunting() and HuntWants(look) then return look, "hunt" end
    local mode = ns.db.alertMode or "rares"
    if mode == "all" then return look, "uncollected" end
    if mode == "rares" then
        for _, s in ipairs(look.sources) do
            if s.npc == npc and (s.cls == 4 or s.cls == 2) then return look, "rare" end
        end
    end
    return nil
end

local popup, targetButton

local function BuildPopup()
    popup = W.Panel(UIParent, { 0.05, 0.05, 0.06, 0.95 }, { 0.67, 0.83, 0.45, 1 })
    popup:SetSize(330, 96)
    popup:SetPoint("TOP", UIParent, "TOP", 0, -230)
    popup:SetFrameStrata("HIGH")
    popup:EnableMouse(true)
    popup:Hide()

    popup.model = CreateFrame("PlayerModel", nil, popup)
    popup.model:SetPoint("TOPLEFT", 4, -4)
    popup.model:SetSize(88, 88)

    popup.head = W.Text(popup, "GameFontNormalSmall", nil, "LEFT")
    popup.head:SetPoint("TOPLEFT", popup.model, "TOPRIGHT", 8, -4)
    popup.name = W.Text(popup, "GameFontNormalLarge", 16, "LEFT")
    popup.name:SetPoint("TOPLEFT", popup.head, "BOTTOMLEFT", 0, -3)
    popup.name:SetWidth(220)
    popup.name:SetWordWrap(false)
    popup.info = W.Text(popup, "GameFontHighlightSmall", nil, "LEFT")
    popup.info:SetPoint("TOPLEFT", popup.name, "BOTTOMLEFT", 0, -3)

    popup.track = W.Button(popup, "Track", 60, 20)
    popup.track:SetPoint("BOTTOMRIGHT", -8, 8)
    popup.track:SetScript("OnClick", function()
        if popup.look then ns.StartTracking(popup.look) end
        popup:Hide()
    end)

    local close = CreateFrame("Button", nil, popup, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() popup:Hide() end)

    popup:SetScript("OnHide", function()
        if targetButton and not InCombatLockdown() then targetButton:Hide() end
    end)
    popup.timer = 0
    popup:SetScript("OnUpdate", function(self, e)
        self.timer = self.timer + e
        if self.timer > 30 then self:Hide() end
    end)
end

-- Targeting is a protected action, so it needs a secure button set up outside combat.
local function ShowTargetButton(name)
    if InCombatLockdown() or not name then return end
    if not targetButton then
        local ok = pcall(function()
            targetButton = CreateFrame("Button", "HunterPetCodexTargetButton", UIParent, "SecureActionButtonTemplate")
            targetButton:SetSize(70, 20)
            targetButton:SetFrameStrata("DIALOG")
            W.Skin(targetButton, { 0.14, 0.14, 0.15, 1 }, { 0.67, 0.83, 0.45, 1 })
            targetButton.text = W.Text(targetButton, "GameFontHighlightSmall")
            targetButton.text:SetPoint("CENTER")
            targetButton.text:SetText("Target")
            targetButton:RegisterForClicks("AnyUp", "AnyDown")
            targetButton:SetAttribute("type", "macro")
        end)
        if not ok then targetButton = nil; return end
    end
    targetButton:SetAttribute("macrotext", "/targetexact " .. name)
    targetButton:ClearAllPoints()
    targetButton:SetPoint("RIGHT", popup.track, "LEFT", -6, 0)
    targetButton:Show()
end

local function Alert(npc, look, why, mapID, packed)
    if not ns.db.alertEnabled then return end
    if not popup then BuildPopup() end
    local src
    for _, s in ipairs(look.sources) do if s.npc == npc then src = s end end
    local name = src and src.name or look.name
    local r = ns.RARITY[look.rarity]
    popup.look = look
    popup.timer = 0
    popup.model:ClearModel()
    popup.model:SetDisplayInfo(look.id)
    popup.model:SetFacing(0.6)
    popup.head:SetText(why == "tracked" and "|cffffd100TRACKED BEAST SPOTTED|r" or "|cffabd473WANTED BEAST NEARBY|r")
    popup.name:SetText(name)
    popup.name:SetTextColor(r.color[1], r.color[2], r.color[3])
    popup.info:SetText(("%s look  -  |cffffd100%d pts|r  -  %s"):format(r.name, r.points,
        ns.IsCollected(look) and "|cff4cff4ccollected|r" or "|cffff5555not collected|r"))
    popup:Show()
    ShowTargetButton(name)

    if ns.db.alertSound then
        if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then pcall(PlaySound, SOUNDKIT.RAID_WARNING, "Master") end
        if FlashClientIcon then pcall(FlashClientIcon) end
    end
    if RaidNotice_AddMessage and RaidWarningFrame then
        pcall(RaidNotice_AddMessage, RaidWarningFrame, ("|cff%s%s|r nearby!"):format(r.hex, name), ChatTypeInfo and ChatTypeInfo.RAID_WARNING or { r = 1, g = 1, b = 1 })
    end
    ns.Print(("|cff%s%s|r spotted nearby (%s look, %d pts)."):format(r.hex, name, r.name, r.points))

    -- if we know exactly where it is, point the arrow there
    if mapID and packed and ns.IsTracking(look) then
        live = { mapID = mapID, packed = packed, t = GetTime(), npc = npc }
        current = nil
    end
end

local function Consider(npc, guid, mapID, packed)
    if not npc then return end
    local look, why = Wanted(npc)
    if not look then return end
    local now = GetTime()
    if alerted[npc] and now - alerted[npc] < ALERT_COOLDOWN then
        -- still refresh the live position for the arrow
        if mapID and packed and ns.IsTracking(look) then live = { mapID = mapID, packed = packed, t = now, npc = npc } end
        return
    end
    alerted[npc] = now
    Alert(npc, look, why, mapID, packed)
end

local function CheckUnit(unit)
    if not UnitExists(unit) then return end
    local guid = ns.SafeGUID(unit)
    if not guid or guid:sub(1, 8) ~= "Creature" then return end
    local ok, dead = pcall(UnitIsDead, unit)
    if ok and dead and not ns.IsSecret(dead) then return end
    Consider(ns.NPCIDFromGUID(guid), guid)
end

local function ScanNameplates()
    if not (C_NamePlate and C_NamePlate.GetNamePlates) then return end
    for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
        local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
        if unit then CheckUnit(unit) end
    end
end

local function ScanVignettes()
    local V = C_VignetteInfo
    if not (V and V.GetVignettes and V.GetVignetteInfo) then return end
    local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    for _, vg in ipairs(V.GetVignettes() or {}) do
        local ok, info = pcall(V.GetVignetteInfo, vg)
        if ok and info and info.objectGUID and not ns.IsSecret(info.objectGUID) then
            local npc = ns.NPCIDFromGUID(info.objectGUID)
            if npc and ns.npcToLook[npc] then
                local packed
                if map and V.GetVignettePosition then
                    local okp, pos = pcall(V.GetVignettePosition, vg, map)
                    if okp and pos and pos.x then
                        packed = math.floor(pos.x * 1000 + 0.5) * 1000 + math.floor(pos.y * 1000 + 0.5)
                    end
                end
                Consider(npc, info.objectGUID, packed and map, packed)
            end
        end
    end
end

function ns.TestAlert()
    local look = TrackedLook()
    if not look then
        for _, l in ipairs(ns.lookList) do if l.rarity >= 3 then look = l break end end
    end
    if look then Alert(look.sources[1].npc, look, "tracked") end
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event, arg1)
    if event == "NAME_PLATE_UNIT_ADDED" then
        CheckUnit(arg1)
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        CheckUnit("mouseover")
    elseif event == "PLAYER_TARGET_CHANGED" then
        CheckUnit("target")
    elseif event == "VIGNETTE_MINIMAP_UPDATED" or event == "VIGNETTES_UPDATED" then
        pcall(ScanVignettes)
    elseif event == "PLAYER_REGEN_ENABLED" then
        if targetButton and popup and not popup:IsShown() then targetButton:Hide() end
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        current = nil
    elseif event == "PLAYER_LEVEL_UP" then
        if ns.IsHunting() then ns.RefreshHunt() end
    end
end)

ns.On("READY", function()
    if ns.playerClass ~= "HUNTER" then return end
    for _, e in ipairs({ "NAME_PLATE_UNIT_ADDED", "UPDATE_MOUSEOVER_UNIT", "PLAYER_TARGET_CHANGED",
        "VIGNETTE_MINIMAP_UPDATED", "VIGNETTES_UPDATED", "PLAYER_REGEN_ENABLED", "ZONE_CHANGED_NEW_AREA", "PLAYER_LEVEL_UP" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    -- nameplates can already be up when an alert-worthy beast walks in; rescan gently
    if C_Timer and C_Timer.NewTicker then
        C_Timer.NewTicker(2, function()
            if ns.db.alertEnabled then pcall(ScanNameplates); pcall(ScanVignettes) end
        end)
    end
    ns.UpdateArrowVisibility()
end)
