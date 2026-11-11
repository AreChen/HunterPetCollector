-- Hunter Pet Collector - spawn pins on the world map and minimap
-- Pins are saved per NPC and stay until the player removes them.
local ADDON, ns = ...
local L = ns.L
local W = ns.W

------------------------------------------------------------------------
-- Spawn data: Data/Spawns_*.lua call ns.RegisterSpawns(flavor, { [npc] = { [uiMapID] = {packed,...} } })
-- packed = x*10*1000 + y*10   (x, y in 0-100 map percent, 0.1 precision)
------------------------------------------------------------------------

local function Spawns()
    return ns.spawnSets[ns.flavor] or {}
end

local function Unpack(p)
    return math.floor(p / 1000) / 1000, (p % 1000) / 1000
end

function ns.SpawnCount(npc)
    local s = npc and Spawns()[npc]
    if not s then return 0 end
    local n = 0
    for _, pts in pairs(s) do n = n + #pts end
    return n
end

function ns.LookHasSpawns(look)
    for _, src in ipairs(look.sources) do
        if Spawns()[src.npc] then return true end
    end
    return false
end

------------------------------------------------------------------------
-- Pin state
------------------------------------------------------------------------
local function Pins()
    local p = ns.db.pins
    p[ns.flavor] = p[ns.flavor] or {}
    return p[ns.flavor]
end

function ns.IsNPCPinned(npc) return npc ~= nil and Pins()[npc] ~= nil end

function ns.IsLookPinned(look)
    for _, src in ipairs(look.sources) do
        if Pins()[src.npc] then return true end
    end
    return false
end

function ns.PinCount()
    local n = 0
    for _ in pairs(Pins()) do n = n + 1 end
    return n
end

local function Changed()
    ns.Fire("PINS_CHANGED")
end

function ns.SetNPCPinned(npc, on)
    if not npc then return end
    if on then
        if not Spawns()[npc] then return end
        Pins()[npc] = true
    else
        Pins()[npc] = nil
    end
    Changed()
end

function ns.ToggleLookPins(look)
    local on = not ns.IsLookPinned(look)
    local added = 0
    for _, src in ipairs(look.sources) do
        if on then
            if Spawns()[src.npc] then Pins()[src.npc] = true; added = added + 1 end
        else
            Pins()[src.npc] = nil
        end
    end
    if on and added == 0 then
        ns.Print("No spawn coordinates are known for " .. look.name .. ".")
    elseif on then
        ns.Print(("Pinned %s on your map (%d beast%s). Open the world map to see them."):format(look.name, added, added == 1 and "" or "s"))
    end
    Changed()
end

function ns.ClearPins()
    wipe(Pins())
    Changed()
    ns.Print("All map pins cleared.")
end

ns.On("COLLECTION_CHANGED", function(look, on)
    if on and look and ns.db.autoClearPins and ns.IsLookPinned(look) then
        for _, src in ipairs(look.sources) do Pins()[src.npc] = nil end
        Changed()
    end
end)

-- npc -> look/source, for pin tooltips
local function SourceFor(npc)
    local look = ns.npcToLook[npc]
    if not look then return nil end
    for _, s in ipairs(look.sources) do
        if s.npc == npc then return look, s end
    end
    return look, nil
end

------------------------------------------------------------------------
-- Pin visuals
------------------------------------------------------------------------
local function MakePin(parent, size)
    local pin = CreateFrame("Button", nil, parent)
    pin:SetSize(size, size)
    pin.ring = pin:CreateTexture(nil, "BACKGROUND")
    pin.ring:SetAllPoints()
    pin.ring:SetTexture("Interface\\Buttons\\WHITE8x8")
    pin.icon = pin:CreateTexture(nil, "ARTWORK")
    pin.icon:SetPoint("TOPLEFT", 2, -2)
    pin.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    pin.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if pin.CreateMaskTexture then
        local ok = pcall(function()
            local m1 = pin:CreateMaskTexture()
            m1:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            m1:SetAllPoints(pin.ring)
            pin.ring:AddMaskTexture(m1)
            local m2 = pin:CreateMaskTexture()
            m2:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            m2:SetAllPoints(pin.icon)
            pin.icon:AddMaskTexture(m2)
        end)
        if not ok then pin.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    end
    pin.glow = pin:CreateTexture(nil, "BACKGROUND", nil, -1)
    pin.glow:SetTexture("Interface\\Cooldown\\star4")
    pin.glow:SetBlendMode("ADD")
    pin.glow:SetPoint("CENTER")
    pin.glow:SetSize(size * 2.4, size * 2.4)
    pin.glow:Hide()
    pin:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    pin:SetScript("OnEnter", function(self)
        local look, src = SourceFor(self.npc)
        if not look then return end
        local r = ns.RARITY[look.rarity]
        local tip = GameTooltip
        tip:SetOwner(self, "ANCHOR_RIGHT")
        tip:AddLine(src and src.name or look.name, 1, 1, 1)
        if src then
            local lv = (src.minLevel or 0) > 0 and (((src.maxLevel or 0) > src.minLevel) and L["Lvl %d-%d"]:format(src.minLevel, src.maxLevel) or L["Lvl %d"]:format(src.minLevel)) or ""
            local tag = ({ [1] = "Elite", [2] = "Rare Elite", [3] = "Boss", [4] = "Rare" })[src.cls or 0]
            tip:AddLine(lv .. (tag and ("  |cff0070dd" .. L[tag] .. "|r") or ""), 0.8, 0.8, 0.8)
        end
        local fam = ns.families[look.family]
        tip:AddDoubleLine((fam and fam.name or L["Beast"]) .. " - " .. look.name, r.name, 0.7, 0.7, 0.7, r.color[1], r.color[2], r.color[3])
        tip:AddLine(ns.IsCollected(look) and ("|cff4cff4c" .. L["Look collected"] .. "|r") or ("|cffff5555" .. L["Look not collected"] .. "|r"))
        tip:AddLine(("%.1f, %.1f"):format(self.x * 100, self.y * 100), 0.5, 0.5, 0.5)
        tip:AddLine(" ")
        if ns.IsTracking and ns.IsTracking(look) then tip:AddLine(L["Tracking with the arrow"], 1, 0.82, 0) end
        tip:AddLine(L["Click: open in the collection  -  Shift-click: waypoint"], 0.5, 0.5, 0.5)
        tip:AddLine(L["Ctrl-click: track this look with the arrow"], 0.5, 0.5, 0.5)
        tip:AddLine(L["Right-click: remove this beast's pins"], 0.5, 0.5, 0.5)
        tip:Show()
    end)
    pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
    pin:SetScript("OnClick", function(self, btn)
        if btn == "RightButton" then
            ns.SetNPCPinned(self.npc, false)
            GameTooltip:Hide()
        elseif IsControlKeyDown and IsControlKeyDown() then
            local look = SourceFor(self.npc)
            if look and ns.StartTracking then ns.StartTracking(look) end
        elseif IsShiftKeyDown() then
            local _, src = SourceFor(self.npc)
            ns.SetWaypoint(self.mapID, self.x, self.y, src and src.name)
        else
            local look = SourceFor(self.npc)
            if look then
                if not (HunterPetCodexFrame and HunterPetCodexFrame:IsShown()) then ns.ToggleMain("collection") end
                ns.SelectLook(look)
            end
        end
    end)
    return pin
end

local PAW = "Interface\\Minimap\\Tracking\\StableMaster"

local function StylePin(pin, npc, paw)
    local look = ns.npcToLook[npc]
    local r = look and ns.RARITY[look.rarity] or ns.RARITY[1]
    local fam = look and ns.families[look.family]
    pin.ring:SetVertexColor(r.color[1], r.color[2], r.color[3], 1)
    if paw then
        -- pet paw symbol, on a dark disc inside the rarity ring
        pin.icon:SetTexture(PAW)
        pin.icon:SetTexCoord(0, 1, 0, 1)
        pin.ring:SetVertexColor(r.color[1] * 0.9, r.color[2] * 0.9, r.color[3] * 0.9, 1)
    else
        pin.icon:SetTexture(fam and fam.icon or "Interface\\Icons\\Ability_Hunter_BeastTaming")
        pin.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    local have = look and ns.IsCollected(look)
    pin.icon:SetDesaturated(have and true or false)
    local tracked = look and ns.IsTracking and ns.IsTracking(look)
    pin.glow:SetShown(tracked and true or false)
    if tracked then pin.glow:SetVertexColor(1, 0.82, 0.2, 0.9) end
    pin:SetAlpha(have and not tracked and 0.7 or 1)
    return tracked
end

------------------------------------------------------------------------
-- World map
------------------------------------------------------------------------
local worldLayer, worldPins, lastMap, lastScale = nil, {}, nil, nil
local WORLD_PIN = 14

local function Canvas()
    return WorldMapFrame and WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.Child
end

local function CanvasScale()
    local sc = WorldMapFrame.ScrollContainer
    if sc and sc.GetCanvasScale then
        local ok, v = pcall(sc.GetCanvasScale, sc)
        if ok and v and v > 0 then return v end
    end
    return 1
end

-- where (if anywhere) does point x,y on map m land on the map being viewed?
local rectCache = {}
local function Translate(m, x, y, viewed)
    if m == viewed then return x, y, true end
    local key = m .. ":" .. viewed
    local rect = rectCache[key]
    if rect == nil then
        rect = false
        if C_Map and C_Map.GetMapRectOnMap then
            local ok, l, r, t, b = pcall(C_Map.GetMapRectOnMap, m, viewed)
            if ok and l and r and t and b and r > l and b > t then rect = { l, r, t, b } end
        end
        rectCache[key] = rect
    end
    if not rect then return nil end
    return rect[1] + x * (rect[2] - rect[1]), rect[3] + y * (rect[4] - rect[3]), false
end

function ns.RefreshWorldPins()
    if not worldLayer then return end
    for _, p in ipairs(worldPins) do p:Hide() end
    if not ns.db.showWorldPins or not WorldMapFrame:IsShown() then return end
    local viewed = WorldMapFrame:GetMapID()
    if not viewed then return end
    local canvas = Canvas()
    local w, h = canvas:GetWidth(), canvas:GetHeight()
    local scale = (ns.db.pinScale or 1) / CanvasScale()
    local n = 0
    local spawns = Spawns()
    local show = {}
    for npc in pairs(Pins()) do show[npc] = true end
    local trackedNpcs = ns.TrackedNPCs and ns.TrackedNPCs()
    if trackedNpcs then for npc in pairs(trackedNpcs) do show[npc] = true end end
    local hunt = ns.HuntNPCs and ns.HuntNPCs()
    if hunt then for npc in pairs(hunt) do if show[npc] == nil then show[npc] = "hunt" end end end
    local MAX_WORLD = 900
    for npc, why in pairs(show) do
        local maps = spawns[npc]
        if maps and n < MAX_WORLD then
            for m, pts in pairs(maps) do
                -- hunt-mode beasts: one pin per zone when zoomed out to a continent
                local thin = why == "hunt" and m ~= viewed
                for i, packed in ipairs(pts) do
                    if thin and i > 1 then break end
                    local x, y = Unpack(packed)
                    local tx, ty, exact = Translate(m, x, y, viewed)
                    if n < MAX_WORLD and tx and tx >= 0 and tx <= 1 and ty >= 0 and ty <= 1 then
                        n = n + 1
                        local pin = worldPins[n]
                        if not pin then
                            pin = MakePin(worldLayer, WORLD_PIN)
                            worldPins[n] = pin
                        end
                        pin.npc, pin.mapID, pin.x, pin.y = npc, m, x, y
                        StylePin(pin, npc)
                        local ps = exact and scale or scale * 0.75
                        pin:SetScale(ps)
                        pin:ClearAllPoints()
                        pin:SetPoint("CENTER", worldLayer, "TOPLEFT", tx * w / ps, -ty * h / ps)
                        pin:Show()
                    end
                end
            end
        end
    end
end

local function SetupWorldMap()
    if worldLayer or not Canvas() then return end
    local canvas = Canvas()
    worldLayer = CreateFrame("Frame", nil, canvas)
    worldLayer:SetAllPoints(canvas)
    worldLayer:SetFrameLevel(canvas:GetFrameLevel() + 2000)
    local elapsed = 0
    worldLayer:SetScript("OnUpdate", function(_, e)
        elapsed = elapsed + e
        if elapsed < 0.1 then return end
        elapsed = 0
        local m, s = WorldMapFrame:GetMapID(), CanvasScale()
        if m ~= lastMap or s ~= lastScale then
            lastMap, lastScale = m, s
            ns.RefreshWorldPins()
        end
    end)
    WorldMapFrame:HookScript("OnShow", function() lastMap = nil end)
end

-- Open the world map on the zone where this beast has the most spawns
function ns.OpenMapForNPC(npc)
    local maps = Spawns()[npc]
    if not maps then return end
    local best, bestN = nil, 0
    for m, pts in pairs(maps) do
        if #pts > bestN then best, bestN = m, #pts end
    end
    if not best then return end
    if InCombatLockdown() then
        ns.Print("Pinned. Open your map after combat to see it.")
        return
    end
    if OpenWorldMap then
        pcall(OpenWorldMap, best)
    else
        if not WorldMapFrame:IsShown() then pcall(ToggleWorldMap) end
        pcall(WorldMapFrame.SetMapID, WorldMapFrame, best)
    end
    lastMap = nil
end

------------------------------------------------------------------------
-- Waypoints (Blizzard user waypoint + TomTom if installed)
------------------------------------------------------------------------
function ns.SetWaypoint(mapID, x, y, title)
    local set = false
    if TomTom and TomTom.AddWaypoint then
        pcall(TomTom.AddWaypoint, TomTom, mapID, x, y, { title = title or "Hunter Pet Collector", persistent = false })
        set = true
    end
    if C_Map and C_Map.SetUserWaypoint and UiMapPoint and C_Map.CanSetUserWaypointOnMap and C_Map.CanSetUserWaypointOnMap(mapID) then
        local ok = pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(mapID, x, y))
        set = set or ok
    end
    if set then
        ns.Print(("Waypoint set: %s (%.1f, %.1f)"):format(title or "beast", x * 100, y * 100))
    else
        ns.Print(("%s is at %.1f, %.1f"):format(title or "Beast", x * 100, y * 100))
    end
end

local function PlayerPos()
    if not (C_Map and C_Map.GetBestMapForUnit) then return end
    local map = C_Map.GetBestMapForUnit("player")
    if not map or ns.IsSecret(map) then return end
    local ok, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
    if not ok or not pos then return end
    local ok2, cont, world = pcall(C_Map.GetWorldPosFromMapPos, map, pos)
    if not ok2 or not world then return end
    return map, cont, world.x, world.y
end

local worldCache = {}
local function WorldPos(m, packed)
    local key = m * 10000000 + packed
    local c = worldCache[key]
    if c == nil then
        c = false
        if C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D then
            local x, y = Unpack(packed)
            local ok, cont, v = pcall(C_Map.GetWorldPosFromMapPos, m, CreateVector2D(x, y))
            if ok and v then c = { cont, v.x, v.y } end
        end
        worldCache[key] = c
    end
    return c
end

function ns.WaypointToNearest(npc, title)
    local maps = Spawns()[npc]
    if not maps then return ns.Print("No spawn coordinates known for " .. (title or "that beast") .. ".") end
    ns.SetNPCPinned(npc, true)
    local _, cont, px, py = PlayerPos()
    local bestM, bestP, bestD
    for m, pts in pairs(maps) do
        for _, p in ipairs(pts) do
            local wp = WorldPos(m, p)
            local d
            if wp and cont and wp[1] == cont then
                d = (wp[2] - px) ^ 2 + (wp[3] - py) ^ 2
            else
                d = 1e12 -- different continent: fall back to the first spawn
            end
            if not bestD or d < bestD then bestM, bestP, bestD = m, p, d end
        end
    end
    local x, y = Unpack(bestP)
    ns.SetWaypoint(bestM, x, y, title)
end

------------------------------------------------------------------------
-- Minimap pins
------------------------------------------------------------------------
local MINIMAP_YARDS = {
    indoor = { [0] = 300, 240, 180, 120, 80, 50 },
    outdoor = { [0] = 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 },
}
local miniLayer, miniPins = nil, {}
local MAX_MINI = 60

local function UpdateMinimap()
    for _, p in ipairs(miniPins) do p:Hide() end
    local trackedNpcs = ns.TrackedNPCs and ns.TrackedNPCs()
    local hunt = ns.HuntNPCs and ns.HuntNPCs()
    if not ns.db.showMinimapPins or (ns.PinCount() == 0 and not trackedNpcs and not hunt) then return end
    local curMap, cont, px, py = PlayerPos()
    if not cont then return end
    local zoom = Minimap:GetZoom()
    local indoors = (tonumber(GetCVar("minimapZoom")) or 0) == zoom and "outdoor" or "indoor"
    local diameter = MINIMAP_YARDS[indoors][zoom] or 300
    local radius = diameter / 2
    local pxPerYard = Minimap:GetWidth() / diameter
    local rotate = GetCVar("rotateMinimap") == "1"
    local facing = rotate and GetPlayerFacing and GetPlayerFacing() or 0
    if ns.IsSecret(facing) then facing = 0 end
    local cosF, sinF = math.cos(facing), math.sin(facing)
    local n = 0
    local spawns = Spawns()
    local show = {}
    for npc in pairs(Pins()) do show[npc] = true end
    if trackedNpcs then for npc in pairs(trackedNpcs) do show[npc] = true end end
    if hunt and curMap then
        for npc in pairs(ns.NPCsNearMap(curMap)) do if hunt[npc] then show[npc] = true end end
    end
    for npc in pairs(show) do
        local maps = spawns[npc]
        if maps then
            for m, pts in pairs(maps) do
                for _, p in ipairs(pts) do
                    local wp = WorldPos(m, p)
                    if wp and wp[1] == cont then
                        -- world: x = north, y = west.  minimap: right = east, up = north
                        local dx, dy = -(wp[3] - py), (wp[2] - px)
                        if dx * dx + dy * dy < radius * radius then
                            if rotate then dx, dy = dx * cosF + dy * sinF, -dx * sinF + dy * cosF end
                            n = n + 1
                            if n > MAX_MINI then return end
                            local pin = miniPins[n]
                            if not pin then
                                pin = MakePin(miniLayer, 14)
                                miniPins[n] = pin
                            end
                            pin.npc, pin.mapID = npc, m
                            pin.x, pin.y = Unpack(p)
                            local tracked = StylePin(pin, npc, ns.db.minimapPaw ~= false)
                            local ps = (ns.db.pinScale or 1) * (tracked and 1.25 or 1)
                            pin:SetScale(ps)
                            pin:ClearAllPoints()
                            pin:SetPoint("CENTER", Minimap, "CENTER", dx * pxPerYard / ps, dy * pxPerYard / ps)
                            pin:Show()
                        end
                    end
                end
            end
        end
    end
end

local function SetupMinimap()
    if miniLayer then return end
    miniLayer = CreateFrame("Frame", nil, Minimap)
    miniLayer:SetAllPoints(Minimap)
    miniLayer:SetFrameLevel(Minimap:GetFrameLevel() + 5)
    local t = 0
    miniLayer:SetScript("OnUpdate", function(_, e)
        t = t + e
        if t < 0.1 then return end
        t = 0
        local ok, err = pcall(UpdateMinimap)
        if not ok then
            miniLayer:SetScript("OnUpdate", nil) -- disable quietly on clients that block positions
        end
    end)
end

------------------------------------------------------------------------
ns.On("PINS_CHANGED", function()
    lastMap = nil
    ns.RefreshWorldPins()
end)
ns.On("COLLECTION_CHANGED", function() lastMap = nil end)

ns.On("READY", function()
    if WorldMapFrame then pcall(SetupWorldMap) end
    pcall(SetupMinimap)
end)

-- shared with Tracker.lua
ns.Spawns, ns.UnpackCoord, ns.PlayerPos, ns.WorldPos, ns.SourceFor = Spawns, Unpack, PlayerPos, WorldPos, SourceFor

-- map -> set of NPCs with spawns there; and the continent each map is on
local npcsByMap, mapCont
local function BuildMapIndex()
    npcsByMap, mapCont = {}, {}
    for npc, maps in pairs(Spawns()) do
        for m in pairs(maps) do
            npcsByMap[m] = npcsByMap[m] or {}
            npcsByMap[m][npc] = true
        end
    end
end

function ns.NPCsOnMap(m)
    if not npcsByMap then BuildMapIndex() end
    return npcsByMap[m] or {}
end

function ns.MapsWithSpawns()
    if not npcsByMap then BuildMapIndex() end
    return npcsByMap
end

function ns.MapContinent(m)
    if not mapCont then BuildMapIndex() end
    local c = mapCont[m]
    if c == nil then
        c = false
        local spawns = Spawns()
        for npc in pairs(npcsByMap[m] or {}) do
            local wp = WorldPos(m, spawns[npc][m][1])
            if wp then c = wp[1]; break end
        end
        mapCont[m] = c
    end
    return c
end

-- NPCs whose spawns are in the player's current zone (used by hunt mode on the minimap)
function ns.NPCsNearMap(curMap)
    return ns.NPCsOnMap(curMap)
end
