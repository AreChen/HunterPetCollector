-- Hunter Pet Collector - main window and collection journal
local ADDON, ns = ...
local W = ns.W
local L = ns.L

local FRAME_W, FRAME_H = 1060, 650
local COLS, ROWS = 4, 3
local TILE_W, TILE_H = 126, 156
local TILE_GAP = 8
local FAMILY_ROWS = 13

local state = {
    family = 0,           -- 0 = all
    search = "",
    showCollected = true,
    showMissing = true,
    rarity = { true, true, true, true, true },
    tameableNow = false,
    role = "all",         -- "all" | "dps" | "tank" | "support"
    sort = "family",      -- see SORTS
    page = 1,
    selected = nil,
    tab = "collection",
}
ns.uiState = state

local main, collection, board, options
local tiles = {}
local filtered = {}

------------------------------------------------------------------------
-- Filtering
------------------------------------------------------------------------
local function MatchesSearch(look, q)
    if q == "" then return true end
    if look.name:lower():find(q, 1, true) then return true end
    for _, s in ipairs(look.sources) do
        if s.name:lower():find(q, 1, true) or (s.englishName or ""):lower():find(q, 1, true) or (s.zone or ""):lower():find(q, 1, true) or (s.englishZone or ""):lower():find(q, 1, true) then return true end
    end
    local fam = ns.families[look.family]
    return fam and (fam.name:lower():find(q, 1, true) ~= nil or (fam.englishName or ""):lower():find(q, 1, true) ~= nil)
end

local function CanTameNow(look)
    local lvl = UnitLevel("player")
    for _, s in ipairs(look.sources) do
        if (s.minLevel or 0) <= lvl then return true end
    end
    return false
end

local SORTS = {
    { key = "family",  label = L["Family"] },
    { key = "dps",     label = L["Best DPS"] },
    { key = "tank",    label = L["Best tank"] },
    { key = "support", label = L["Best support"] },
    { key = "rarity",  label = L["Rarest first"] },
    { key = "level",   label = L["Level"] },
}
ns.SORTS = SORTS

local function SortFiltered()
    local mode = state.sort
    if mode == "family" then return end -- lookList is already in family order
    local order = {}
    for i, l in ipairs(filtered) do order[l] = i end
    table.sort(filtered, function(a, b)
        if mode == "rarity" then
            if a.rarity ~= b.rarity then return a.rarity > b.rarity end
        elseif mode == "level" then
            if a.minLevel ~= b.minLevel then return a.minLevel < b.minLevel end
        else
            local ra, rb = ns.FamilyRole(a.family)[mode], ns.FamilyRole(b.family)[mode]
            if ra ~= rb then return ra > rb end
            if a.rarity ~= b.rarity then return a.rarity > b.rarity end
        end
        return order[a] < order[b]
    end)
end

function ns.ApplyFilters()
    wipe(filtered)
    local q = state.search:lower()
    local col = ns.Collected()
    for _, look in ipairs(ns.lookList) do
        local have = col[look.id] ~= nil
        if (state.family == 0 or look.family == state.family)
            and ((have and state.showCollected) or (not have and state.showMissing))
            and state.rarity[look.rarity]
            and (not state.tameableNow or CanTameNow(look))
            and MatchesSearch(look, q) then
            filtered[#filtered + 1] = look
        end
    end
    SortFiltered()
    local pages = math.max(1, math.ceil(#filtered / (COLS * ROWS)))
    if state.page > pages then state.page = pages end
    if main and main:IsShown() then ns.RefreshCollection() end
end

------------------------------------------------------------------------
-- Model helpers
------------------------------------------------------------------------
local function ShowLook(model, look)
    model:ClearModel()
    model:SetDisplayInfo(look.id)
    if model.SetPortraitZoom then model:SetPortraitZoom(0) end
    if model.SetCamDistanceScale then model:SetCamDistanceScale(model.camScale or 1) end
    model:SetPosition(0, 0, 0)
    model:SetFacing(model.baseFacing or 0.55)
end

------------------------------------------------------------------------
-- Tile grid
------------------------------------------------------------------------
local function TileTooltip(tile)
    local look = tile.look
    if not look then return end
    local r = ns.RARITY[look.rarity]
    local fam = ns.families[look.family]
    GameTooltip:SetOwner(tile, "ANCHOR_RIGHT")
    GameTooltip:AddLine(look.name, r.color[1], r.color[2], r.color[3])
    GameTooltip:AddDoubleLine(fam and fam.name or "Beast", r.name .. "  |cffffd100" .. r.points .. " pts|r", 0.8, 0.8, 0.8, 1, 1, 1)
    local roleText, roleData = ns.RoleSummary(look)
    GameTooltip:AddLine(roleText)
    GameTooltip:AddLine(L[roleData.note], 0.75, 0.75, 0.75, true)
    if ns.IsCollected(look) then
        GameTooltip:AddLine(L["Collected"], 0.3, 1, 0.3)
    else
        GameTooltip:AddLine(L["Not collected"], 1, 0.3, 0.3)
    end
    local s = look.sources[1]
    if s then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(("%s  |cff999999(%d source%s)|r"):format(s.zone ~= "" and s.zone or "Unknown location", #look.sources, #look.sources == 1 and "" or "s"), 0.9, 0.9, 0.9, true)
    end
    GameTooltip:AddLine(" ")
    if ns.LookHasSpawns and ns.LookHasSpawns(look) then
        GameTooltip:AddLine(ns.IsLookPinned(look) and "Right-click to remove its map pins" or "Right-click to show spawns on your map", 0.5, 0.5, 0.5)
    end
    GameTooltip:AddLine(L["Click to inspect"], 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

local function CreateTile(parent, i)
    local tile = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    tile:SetSize(TILE_W, TILE_H)
    W.Skin(tile, { 0.08, 0.08, 0.09, 1 })
    tile:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local bg = tile:CreateTexture(nil, "BACKGROUND", nil, 1)
    bg:SetTexture(W.WHITE)
    bg:SetPoint("TOPLEFT", 1, -1)
    bg:SetPoint("BOTTOMRIGHT", -1, 1)
    tile.bg = bg

    local model = CreateFrame("PlayerModel", nil, tile)
    model:SetPoint("TOPLEFT", 3, -3)
    model:SetPoint("BOTTOMRIGHT", -3, 30)
    model.camScale = 1.15
    tile.model = model

    -- dim overlay for uncollected looks (sits above the model)
    local shade = CreateFrame("Frame", nil, tile)
    shade:SetAllPoints(model)
    shade:SetFrameLevel(model:GetFrameLevel() + 2)
    local shadeTex = shade:CreateTexture(nil, "OVERLAY")
    shadeTex:SetAllPoints()
    shadeTex:SetTexture(W.WHITE)
    shadeTex:SetVertexColor(0, 0, 0, 0.55)
    tile.shade = shade

    local overlay = CreateFrame("Frame", nil, tile)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(model:GetFrameLevel() + 3)

    tile.name = W.Text(overlay, "GameFontHighlightSmall", nil, "CENTER")
    tile.name:SetPoint("BOTTOMLEFT", 4, 14)
    tile.name:SetPoint("BOTTOMRIGHT", -4, 14)
    tile.name:SetHeight(12)
    tile.name:SetWordWrap(false)

    tile.sub = W.Text(overlay, "GameFontDisableSmall", 9, "CENTER")
    tile.sub:SetPoint("BOTTOMLEFT", 4, 3)
    tile.sub:SetPoint("BOTTOMRIGHT", -4, 3)
    tile.sub:SetHeight(10)

    tile.check = overlay:CreateTexture(nil, "OVERLAY")
    tile.check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    tile.check:SetSize(16, 16)
    tile.check:SetPoint("TOPRIGHT", -4, -4)

    tile.famIcon = overlay:CreateTexture(nil, "OVERLAY")
    tile.famIcon:SetSize(16, 16)
    tile.famIcon:SetPoint("TOPLEFT", 4, -4)
    tile.famIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    tile.pin = overlay:CreateTexture(nil, "OVERLAY")
    tile.pin:SetTexture("Interface\\Minimap\\Tracking\\None")
    tile.pin:SetSize(14, 14)
    tile.pin:SetPoint("TOPRIGHT", -22, -5)
    tile.pin:Hide()

    tile.gem = overlay:CreateTexture(nil, "OVERLAY")
    tile.gem:SetTexture(W.WHITE)
    tile.gem:SetHeight(2)
    tile.gem:SetPoint("BOTTOMLEFT", 1, 1)
    tile.gem:SetPoint("BOTTOMRIGHT", -1, 1)

    tile.sel = overlay:CreateTexture(nil, "OVERLAY")
    tile.sel:SetTexture("Interface\\Buttons\\WHITE8x8")
    tile.sel:SetAllPoints()
    tile.sel:SetVertexColor(W.ACCENT[1], W.ACCENT[2], W.ACCENT[3], 0.08)
    tile.sel:Hide()

    tile:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(W.ACCENT[1], W.ACCENT[2], W.ACCENT[3], 1)
        TileTooltip(self)
    end)
    tile:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        ns.StyleTile(self)
    end)
    tile:SetScript("OnClick", function(self, button)
        if not self.look then return end
        if button == "RightButton" then
            ns.ToggleLookPins(self.look)
            TileTooltip(self)
        else
            ns.SelectLook(self.look)
        end
    end)
    tile:EnableMouseWheel(true)
    tile:SetScript("OnMouseWheel", function(_, d) ns.ChangePage(-d) end)
    return tile
end

function ns.StyleTile(tile)
    local look = tile.look
    if not look then return end
    local r = ns.RARITY[look.rarity]
    local have = ns.IsCollected(look)
    local sel = state.selected == look
    tile.shade:SetShown(not have)
    tile.check:SetShown(have)
    tile.pin:SetShown(ns.IsLookPinned and ns.IsLookPinned(look) or false)
    tile.sel:SetShown(sel)
    tile.name:SetTextColor(have and r.color[1] or r.color[1] * 0.6, have and r.color[2] or r.color[2] * 0.6, have and r.color[3] or r.color[3] * 0.6)
    tile.gem:SetVertexColor(r.color[1], r.color[2], r.color[3], have and 1 or 0.45)
    W.Gradient(tile.bg, r.color[1] * 0.06, r.color[2] * 0.06, r.color[3] * 0.06, r.color[1] * 0.22, r.color[2] * 0.22, r.color[3] * 0.22, 1, 1, "VERTICAL")
    if sel then
        tile:SetBackdropBorderColor(W.ACCENT[1], W.ACCENT[2], W.ACCENT[3], 1)
    else
        tile:SetBackdropBorderColor(r.color[1] * 0.55, r.color[2] * 0.55, r.color[3] * 0.55, have and 1 or 0.5)
    end
end

function ns.ChangePage(delta)
    local pages = math.max(1, math.ceil(#filtered / (COLS * ROWS)))
    local p = math.min(pages, math.max(1, state.page + delta))
    if p ~= state.page then
        state.page = p
        ns.RefreshCollection()
    end
end

------------------------------------------------------------------------
-- Detail pane
------------------------------------------------------------------------
local detail
local ANIMS = { { "Idle", 0 }, { "Walk", 4 }, { "Run", 5 }, { "Attack", 16 }, { "Roar", 55 } }

local function BuildDetail(parent)
    detail = W.Panel(parent, { 0.07, 0.07, 0.08, 1 })

    local model = CreateFrame("PlayerModel", nil, detail)
    model:SetPoint("TOPLEFT", 1, -1)
    model:SetPoint("TOPRIGHT", -1, -1)
    model:SetHeight(270)
    model.camScale = 1
    model.baseFacing = 0.55
    detail.model = model

    local floor = detail:CreateTexture(nil, "BACKGROUND", nil, 1)
    floor:SetTexture(W.WHITE)
    floor:SetPoint("TOPLEFT", model, "TOPLEFT")
    floor:SetPoint("BOTTOMRIGHT", model, "BOTTOMRIGHT")
    detail.floor = floor

    -- drag to rotate (left) / pan (right), wheel to zoom
    model:EnableMouse(true)
    model:EnableMouseWheel(true)
    model.facing, model.zoom, model.panY, model.panZ = 0.55, 1, 0, 0
    model:SetScript("OnMouseDown", function(self, btn)
        self.dragBtn = btn
        self.lastX, self.lastY = GetCursorPosition()
        self.spinning = false
    end)
    model:SetScript("OnMouseUp", function(self) self.dragBtn = nil end)
    model:SetScript("OnUpdate", function(self, elapsed)
        if self.dragBtn then
            local x, y = GetCursorPosition()
            local dx, dy = x - self.lastX, y - self.lastY
            self.lastX, self.lastY = x, y
            if self.dragBtn == "LeftButton" then
                self.facing = self.facing + dx * 0.012
                self:SetFacing(self.facing)
            else
                local s = self:GetEffectiveScale() * 120
                self.panY = math.max(-2, math.min(2, self.panY + dx / s))
                self.panZ = math.max(-2, math.min(2, self.panZ + dy / s))
                self:SetPosition(0, self.panY, self.panZ)
            end
        elseif self.spinning then
            self.facing = self.facing + elapsed * 0.6
            self:SetFacing(self.facing)
        end
    end)
    model:SetScript("OnMouseWheel", function(self, d)
        self.zoom = math.max(0.45, math.min(2.5, self.zoom - d * 0.1))
        if self.SetCamDistanceScale then self:SetCamDistanceScale(self.zoom) end
    end)
    function model:ResetView()
        self.facing, self.zoom, self.panY, self.panZ = 0.55, 1, 0, 0
        if self.SetCamDistanceScale then self:SetCamDistanceScale(1) end
        self:SetPosition(0, 0, 0)
        self:SetFacing(self.facing)
    end

    -- view controls
    local controls = CreateFrame("Frame", nil, detail)
    controls:SetPoint("BOTTOMLEFT", model, "BOTTOMLEFT", 6, 6)
    controls:SetPoint("BOTTOMRIGHT", model, "BOTTOMRIGHT", -6, 6)
    controls:SetHeight(20)
    controls:SetFrameLevel(model:GetFrameLevel() + 5)
    detail.animButtons = {}
    local canAnimate = model.SetAnimation ~= nil
    if canAnimate then
        for i, a in ipairs(ANIMS) do
            local b = W.Button(controls, a[1], 44, 18)
            if i == 1 then b:SetPoint("LEFT", 0, 0) else b:SetPoint("LEFT", detail.animButtons[i - 1], "RIGHT", 3, 0) end
            b:SetScript("OnClick", function()
                pcall(model.SetAnimation, model, a[2])
                for _, o in ipairs(detail.animButtons) do o:SetSelected(o == b) end
            end)
            detail.animButtons[i] = b
        end
    end
    -- animation buttons share the full width of the viewer
    controls:SetScript("OnSizeChanged", function(self, w)
        local n = #detail.animButtons
        if n == 0 or not w or w <= 0 then return end
        local bw = math.floor((w - (n - 1) * 3) / n)
        for _, b in ipairs(detail.animButtons) do b:SetWidth(bw) end
    end)

    -- camera buttons sit in the top-right corner of the viewer
    local camera = CreateFrame("Frame", nil, detail)
    camera:SetPoint("TOPRIGHT", model, "TOPRIGHT", -6, -6)
    camera:SetSize(90, 18)
    camera:SetFrameLevel(model:GetFrameLevel() + 5)
    local spin = W.Button(camera, "Spin", 42, 18)
    spin:SetPoint("RIGHT", -46, 0)
    spin.tooltip = L["Turntable rotation"]
    spin:SetScript("OnClick", function(self)
        model.spinning = not model.spinning
        self:SetSelected(model.spinning)
    end)
    detail.spin = spin
    local reset = W.Button(camera, "Reset", 42, 18)
    reset:SetPoint("RIGHT", 0, 0)
    reset.tooltip = "Reset camera\n|cff999999Drag: rotate  -  Right-drag: move  -  Wheel: zoom|r"
    reset:SetScript("OnClick", function() model:ResetView() end)

    -- text block
    local name = W.Text(detail, "GameFontNormalLarge", 17, "LEFT")
    name:SetPoint("TOPLEFT", model, "BOTTOMLEFT", 12, -12)
    name:SetPoint("RIGHT", detail, "RIGHT", -12, 0)
    name:SetWordWrap(false)
    detail.name = name

    local famIcon = detail:CreateTexture(nil, "ARTWORK")
    famIcon:SetSize(16, 16)
    famIcon:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -6)
    famIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    detail.famIcon = famIcon
    local fam = W.Text(detail, "GameFontHighlightSmall", nil, "LEFT")
    fam:SetPoint("LEFT", famIcon, "RIGHT", 6, 0)
    detail.fam = fam

    local rar = W.Text(detail, "GameFontNormalSmall", nil, "RIGHT")
    rar:SetPoint("RIGHT", detail, "RIGHT", -12, 0)
    rar:SetPoint("TOP", famIcon, "TOP", 0, -2)
    detail.rarity = rar

    local status = W.Text(detail, "GameFontHighlightSmall", nil, "LEFT")
    status:SetPoint("TOPLEFT", famIcon, "BOTTOMLEFT", 0, -8)
    status:SetPoint("RIGHT", detail, "RIGHT", -180, 0)
    detail.status = status

    local mark = W.Button(detail, L["Show on map"], 96, 20)
    mark:SetPoint("RIGHT", detail, "RIGHT", -12, 0)
    mark:SetPoint("TOP", status, "TOP", 0, 4)
    mark.tooltip = "Pin every known spawn of this look on your world map and minimap.\nPins stay until you remove them or press Clear pins."
    mark:SetScript("OnClick", function()
        local look = state.selected
        if look then ns.ToggleLookPins(look) end
    end)
    detail.mark = mark

    local track = W.Button(detail, L["Track"], 60, 20)
    track:SetPoint("RIGHT", mark, "LEFT", -6, 0)
    track.tooltip = "Show an arrow that guides you to the nearest spawn, then on to the next one.\nYou'll also get an alert when this beast is nearby."
    track:SetScript("OnClick", function()
        local look = state.selected
        if look then ns.ToggleTracking(look) end
    end)
    detail.track = track

    local hdr = W.Text(detail, "GameFontNormalSmall", nil, "LEFT")
    local combat = W.Text(detail, "GameFontHighlightSmall", nil, "LEFT")
    combat:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, -8)
    combat:SetPoint("RIGHT", detail, "RIGHT", -12, 0)
    detail.combat = combat
    local combatNote = W.Text(detail, "GameFontDisableSmall", nil, "LEFT")
    combatNote:SetPoint("TOPLEFT", combat, "BOTTOMLEFT", 0, -3)
    combatNote:SetPoint("RIGHT", detail, "RIGHT", -12, 0)
    combatNote:SetHeight(24)
    combatNote:SetJustifyV("TOP")
    detail.combatNote = combatNote

    hdr:SetPoint("TOPLEFT", combatNote, "BOTTOMLEFT", 0, -6)
    hdr:SetText(L["WHERE TO TAME"])
    hdr:SetTextColor(W.ACCENT[1], W.ACCENT[2], W.ACCENT[3])
    detail.srcHeader = hdr

    local rule = detail:CreateTexture(nil, "ARTWORK")
    rule:SetTexture(W.WHITE)
    rule:SetVertexColor(1, 1, 1, 0.08)
    rule:SetHeight(1)
    rule:SetPoint("LEFT", hdr, "RIGHT", 8, 0)
    rule:SetPoint("RIGHT", detail, "RIGHT", -12, 0)

    local srcList = W.List(detail, 34, 4, function(list, i)
        local row = CreateFrame("Frame", nil, list)
        row.name = W.Text(row, "GameFontHighlightSmall", nil, "LEFT")
        row.name:SetPoint("TOPLEFT", 2, -3)
        row.name:SetPoint("RIGHT", -70, 0)
        row.name:SetWordWrap(false)
        row.lvl = W.Text(row, "GameFontDisableSmall", nil, "RIGHT")
        row.lvl:SetPoint("TOPRIGHT", -2, -3)
        row.zone = W.Text(row, "GameFontDisableSmall", nil, "LEFT")
        row.zone:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
        row.zone:SetPoint("RIGHT", -2, 0)
        row.zone:SetWordWrap(false)
        row:EnableMouse(true)
        row.hl = row:CreateTexture(nil, "BACKGROUND")
        row.hl:SetAllPoints()
        row.hl:SetTexture(W.WHITE)
        row.hl:SetVertexColor(1, 1, 1, 0)
        row.pinIcon = row:CreateTexture(nil, "OVERLAY")
        row.pinIcon:SetTexture("Interface\\Minimap\\Tracking\\None")
        row.pinIcon:SetSize(12, 12)
        row.pinIcon:SetPoint("BOTTOMRIGHT", -2, 3)
        row:SetScript("OnEnter", function(self)
            if not self.src then return end
            self.hl:SetVertexColor(1, 1, 1, 0.05)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:AddLine(self.src.name, 1, 1, 1)
            GameTooltip:AddLine(self.src.zone ~= "" and self.src.zone or "Unknown location", 0.8, 0.8, 0.8, true)
            local n = ns.SpawnCount and ns.SpawnCount(self.src.npc) or 0
            if n > 0 then
                GameTooltip:AddLine(("%d known spawn point%s"):format(n, n == 1 and "" or "s"), 0.6, 0.8, 0.6)
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Click: pin on map and open it", 0.5, 0.5, 0.5)
                GameTooltip:AddLine("Shift-click: waypoint to the nearest spawn", 0.5, 0.5, 0.5)
                GameTooltip:AddLine("Right-click: remove this beast's pins", 0.5, 0.5, 0.5)
            else
                GameTooltip:AddLine("No spawn coordinates known", 0.6, 0.6, 0.6)
            end
            GameTooltip:AddLine("NPC ID " .. (self.src.npc or "?"), 0.4, 0.4, 0.4)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function(self) self.hl:SetVertexColor(1, 1, 1, 0); GameTooltip:Hide() end)
        row:SetScript("OnMouseUp", function(self, btn)
            if not self.src then return end
            if btn == "RightButton" then
                ns.SetNPCPinned(self.src.npc, false)
            elseif IsShiftKeyDown() then
                ns.WaypointToNearest(self.src.npc, self.src.name)
            else
                ns.SetNPCPinned(self.src.npc, true)
                ns.OpenMapForNPC(self.src.npc)
            end
            list:Refresh()
        end)
        return row
    end, function(row, src)
        row.src = src
        local tag = ""
        if src.cls == 4 then tag = " |cff0070dd(" .. L["Rare"] .. ")|r"
        elseif src.cls == 2 then tag = " |cffa335ee(" .. L["Rare Elite"] .. ")|r"
        elseif src.cls == 1 then tag = " |cffffd100(" .. L["Elite"] .. ")|r"
        elseif src.cls == 3 then tag = " |cffff8000(" .. L["Boss"] .. ")|r" end
        row.name:SetText(src.name .. tag)
        local lv
        if (src.minLevel or 0) == 0 and (src.maxLevel or 0) == 0 then lv = ""
        elseif src.minLevel == src.maxLevel or (src.maxLevel or 0) == 0 then lv = L["Lvl %d"]:format(src.minLevel)
        else lv = L["Lvl %d-%d"]:format(src.minLevel, src.maxLevel) end
        row.lvl:SetText(lv)
        row.zone:SetText(src.zone ~= "" and src.zone or L["Unknown location"])
        row.pinIcon:SetShown(ns.IsNPCPinned and ns.IsNPCPinned(src.npc) or false)
    end)
    srcList:SetPoint("TOPLEFT", hdr, "BOTTOMLEFT", 0, -6)
    srcList:SetPoint("RIGHT", detail, "RIGHT", -8, 0)
    srcList:SetHeight(34 * 4)
    detail.sources = srcList

    detail.empty = W.Text(detail, "GameFontDisable", nil, "CENTER")
    detail.empty:SetPoint("CENTER")
    detail.empty:SetText(L["Select a beast"])
    return detail
end

function ns.UpdateMapButton()
    if not detail or not state.selected then return end
    local look = state.selected
    local has = ns.LookHasSpawns(look)
    detail.track:SetShown(has)
    if has then
        local on = ns.IsTracking(look)
        detail.track.text:SetText(on and L["Stop"] or L["Track"])
        detail.track:SetSelected(on)
    end
    if not has then
        detail.mark.text:SetText(L["No spawn data"])
        detail.mark:Disable()
        detail.mark:SetAlpha(0.5)
    else
        detail.mark:Enable()
        detail.mark:SetAlpha(1)
        detail.mark.text:SetText(ns.IsLookPinned(look) and L["Hide from map"] or L["Show on map"])
    end
    if detail.sources then detail.sources:Refresh() end
end

function ns.SelectLook(look)
    state.selected = look
    if not detail then return end
    local show = look ~= nil
    for _, region in ipairs({ detail.model, detail.name, detail.fam, detail.famIcon, detail.rarity, detail.status, detail.mark, detail.track, detail.sources, detail.srcHeader, detail.combat, detail.combatNote }) do
        region:SetShown(show)
    end
    detail.empty:SetShown(not show)
    if look then
        for _, src in ipairs(look.sources) do ns.RequestOfficialNPCName(src.npc) end
        local r = ns.RARITY[look.rarity]
        local fam = ns.families[look.family]
        if detail.current ~= look then
            detail.current = look
            ShowLook(detail.model, look)
            detail.model:ResetView()
            for i, b in ipairs(detail.animButtons) do b:SetSelected(i == 1) end
        end
        W.Gradient(detail.floor, r.color[1] * 0.04, r.color[2] * 0.04, r.color[3] * 0.04, r.color[1] * 0.25, r.color[2] * 0.25, r.color[3] * 0.25, 1, 1, "VERTICAL")
        detail.name:SetText(look.name)
        detail.name:SetTextColor(r.color[1], r.color[2], r.color[3])
        detail.famIcon:SetTexture(fam and fam.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        detail.fam:SetText((fam and fam.name or L["Unknown family"]) .. (fam and fam.exotic and "  |cffff8000" .. L["Exotic"] .. "|r" or "") .. (look.discovered and "  |cff999999" .. L["(discovered in-game)"] .. "|r" or ""))
        detail.rarity:SetText(L["|cff%s%s|r  |cffffd100%d pts|r"]:format(r.hex, r.name, r.points))
        local roleText, roleData = ns.RoleSummary(look)
        detail.combat:SetText(roleText .. (roleData.type and ("  |cff999999(" .. L[roleData.type] .. ")|r") or ""))
        detail.combatNote:SetText(L[roleData.note or ""])
        local have = ns.Collected()[look.id]
        if have then
            local when = have.t and date("%d %b %Y", have.t) or ""
            local how = ({ pet = L[" - tamed/summoned"], stable = L[" - found in stable"] })[have.auto or ""] or ""
            detail.status:SetText("|cff4cff4c" .. L["Collected"] .. "|r  |cff999999" .. when .. how .. "|r")
        else
            detail.status:SetText("|cffff5555" .. L["Not collected"] .. "|r")
        end
        ns.UpdateMapButton()
        detail.sources.offset = 0
        detail.sources:SetItems(look.sources)
    end
    for _, t in ipairs(tiles) do if t:IsShown() then ns.StyleTile(t) end end
end

------------------------------------------------------------------------
-- Collection page
------------------------------------------------------------------------
local famList, pageText, countText, emptyText

local function FamilyItems()
    local items = { { id = 0, name = L["All Families"], icon = "Interface\\Icons\\Ability_Hunter_BeastTaming" } }
    local fams = {}
    for _, f in pairs(ns.families) do fams[#fams + 1] = f end
    local roleKey = (state.role ~= "all") and state.role or nil
    if roleKey then
        table.sort(fams, function(a, b)
            local ra, rb = ns.FamilyRole(a.id)[roleKey], ns.FamilyRole(b.id)[roleKey]
            if ra ~= rb then return ra > rb end
            return a.name < b.name
        end)
    else
        table.sort(fams, function(a, b) return a.name < b.name end)
    end
    local col = ns.Collected()
    local have, total = {}, {}
    for _, look in ipairs(ns.lookList) do
        total[look.family] = (total[look.family] or 0) + 1
        if col[look.id] then have[look.family] = (have[look.family] or 0) + 1 end
        total[0] = (total[0] or 0) + 1
        if col[look.id] then have[0] = (have[0] or 0) + 1 end
    end
    items[1].have, items[1].total = have[0] or 0, total[0] or 0
    local prevScore, rank = nil, 0
    for _, f in ipairs(fams) do
        if (total[f.id] or 0) > 0 then
            local n = #items  -- position among families (items[1] is "All")
            if roleKey then
                local sc = ns.FamilyRole(f.id)[roleKey]
                if sc ~= prevScore then rank = n; prevScore = sc end
            end
            items[#items + 1] = { id = f.id, name = f.name, icon = f.icon, exotic = f.exotic, have = have[f.id] or 0, total = total[f.id], rank = rank }
        end
    end
    if roleKey then items[1].name = "All - ranked " .. ns.ROLE_INFO[roleKey].label end
    return items
end

local function BuildCollection(parent)
    local page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints()

    -- left: search, filters, families
    local left = W.Panel(page, { 0.07, 0.07, 0.08, 1 })
    left:SetPoint("TOPLEFT", 12, -12)
    left:SetPoint("BOTTOMLEFT", 12, 12)
    left:SetWidth(200)

    local search = W.SearchBox(left, 184, function(t)
        state.search = t
        state.page = 1
        ns.ApplyFilters()
    end)
    search:SetPoint("TOP", 0, -8)
    page.search = search

    local y = -42
    local function addCheck(label, get, set)
        local c = W.Check(left, label, function(_, v) set(v); state.page = 1; ns.ApplyFilters() end)
        c:SetPoint("TOPLEFT", 10, y)
        c:SetChecked(get())
        y = y - 20
        return c
    end
    addCheck(L["Collected"], function() return state.showCollected end, function(v) state.showCollected = v end)
    addCheck(L["Not collected"], function() return state.showMissing end, function(v) state.showMissing = v end)
    addCheck(L["Tameable at my level"], function() return state.tameableNow end, function(v) state.tameableNow = v end)

    -- rarity toggles
    local rx = 10
    y = y - 4
    for i = 1, 5 do
        local r = ns.RARITY[i]
        local b = W.Button(left, "", 32, 16)
        b:SetPoint("TOPLEFT", rx, y)
        rx = rx + 36
        b.swatch = b:CreateTexture(nil, "ARTWORK")
        b.swatch:SetTexture(W.WHITE)
        b.swatch:SetPoint("TOPLEFT", 3, -3)
        b.swatch:SetPoint("BOTTOMRIGHT", -3, 3)
        b.tooltip = ("%s  (%d pts)\nClick to show/hide"):format(r.name, r.points)
        local function paint()
            b.swatch:SetVertexColor(r.color[1], r.color[2], r.color[3], state.rarity[i] and 1 or 0.15)
        end
        paint()
        b:SetScript("OnClick", function()
            state.rarity[i] = not state.rarity[i]
            paint()
            state.page = 1
            ns.ApplyFilters()
        end)
    end
    y = y - 24

    -- role filter
    page.roleButtons = {}
    local roles = { { "all", L["All"] }, { "dps", "DPS" }, { "tank", L["Tank"] }, { "support", L["Support"] } }
    local bx = 10
    for _, rr in ipairs(roles) do
        local w = rr[1] == "support" and 54 or 40
        local b = W.Button(left, rr[2], w, 18)
        b:SetPoint("TOPLEFT", bx, y)
        bx = bx + w + 3
        b.key = rr[1]
        b.tooltip = rr[1] == "all" and "Normal order, families A-Z" or ("Rank every pet from best to worst " .. rr[2] .. ".\nThe family list on the left becomes the ranking.\n|cff999999" .. L[(ns.ROLE_DATA[ns.flavor] or {}).specNote or ""] .. "|r")
        b:SetScript("OnClick", function()
            state.role = rr[1]
            state.sort = rr[1] == "all" and "family" or rr[1]
            state.family = 0
            for _, o in ipairs(page.roleButtons) do o:SetSelected(o.key == state.role) end
            if page.sortText then page.sortText() end
            state.page = 1
            ns.ApplyFilters()
        end)
        b:SetSelected(rr[1] == state.role)
        page.roleButtons[#page.roleButtons + 1] = b
    end
    y = y - 24

    -- sort
    local sortLabel = W.Text(left, "GameFontHighlightSmall", nil, "LEFT")
    sortLabel:SetPoint("TOPLEFT", 12, y - 4)
    sortLabel:SetText(L["Sort:"])
    local sortBtn = W.Button(left, "", 142, 18)
    sortBtn:SetPoint("TOPLEFT", 46, y)
    sortBtn.tooltip = "Click to change the order.\nRight-click to go back."
    sortBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local function sortText()
        for _, so in ipairs(SORTS) do if so.key == state.sort then sortBtn.text:SetText(so.label) end end
    end
    sortText()
    page.sortText = sortText
    sortBtn:SetScript("OnClick", function(_, btn)
        local idx = 1
        for i, so in ipairs(SORTS) do if so.key == state.sort then idx = i end end
        idx = idx + (btn == "RightButton" and -1 or 1)
        if idx > #SORTS then idx = 1 elseif idx < 1 then idx = #SORTS end
        state.sort = SORTS[idx].key
        sortText()
        -- keep the role tabs in step with the sort
        state.role = (state.sort == "dps" or state.sort == "tank" or state.sort == "support") and state.sort or "all"
        for _, o in ipairs(page.roleButtons) do o:SetSelected(o.key == state.role) end
        state.page = 1
        ns.ApplyFilters()
    end)
    y = y - 26

    local famHdr = W.Text(left, "GameFontNormalSmall", nil, "LEFT")
    famHdr:SetPoint("TOPLEFT", 10, y)
    famHdr:SetText(L["FAMILIES"])
    famHdr:SetTextColor(W.ACCENT[1], W.ACCENT[2], W.ACCENT[3])
    y = y - 16

    famList = W.List(left, 24, FAMILY_ROWS, function(list)
        local row = CreateFrame("Button", nil, list)
        row.hl = row:CreateTexture(nil, "BACKGROUND")
        row.hl:SetAllPoints()
        row.hl:SetTexture(W.WHITE)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(18, 18)
        row.icon:SetPoint("LEFT", 4, 0)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.name = W.Text(row, "GameFontHighlightSmall", nil, "LEFT")
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.count = W.Text(row, "GameFontDisableSmall", nil, "RIGHT")
        row.count:SetPoint("RIGHT", -4, 0)
        row:SetScript("OnClick", function(self)
            state.family = self.item.id
            state.page = 1
            ns.ApplyFilters()
            famList:Refresh()
        end)
        row:SetScript("OnEnter", function(self) if state.family ~= self.item.id then self.hl:SetVertexColor(1, 1, 1, 0.06) end end)
        row:SetScript("OnLeave", function(self) list:Refresh() end)
        return row
    end, function(row, item)
        row.item = item
        row.icon:SetTexture(item.icon)
        local roleKey = state.role ~= "all" and state.role or nil
        if roleKey and item.id ~= 0 then
            local info = ns.ROLE_INFO[roleKey]
            local rank = item.rank or 0
            local medal = rank == 1 and "|cffffd700" or rank == 2 and "|cffc0c0c0" or rank == 3 and "|cffcd7f32" or "|cff999999"
            row.name:SetText(("%s#%d|r %s%s"):format(medal, rank, item.name, item.exotic and " |cffff8000*|r" or ""))
            row.count:SetText(("|cff%s%d|r"):format(info.color, ns.FamilyRole(item.id)[roleKey]))
        else
            row.name:SetText(item.name .. (item.exotic and " |cffff8000*|r" or ""))
            local done = item.total > 0 and item.have == item.total
            row.count:SetText(done and ("|cff4cff4c%d/%d|r"):format(item.have, item.total) or ("%d/%d"):format(item.have, item.total))
        end
        if state.family == item.id then
            row.hl:SetVertexColor(W.ACCENT[1], W.ACCENT[2], W.ACCENT[3], 0.22)
        else
            row.hl:SetVertexColor(1, 1, 1, 0)
        end
    end)
    famList:SetPoint("TOPLEFT", 6, y)
    famList:SetPoint("BOTTOMRIGHT", -4, 8)

    -- centre: grid
    local gridW = COLS * TILE_W + (COLS - 1) * TILE_GAP
    local grid = CreateFrame("Frame", nil, page)
    grid:SetPoint("TOPLEFT", left, "TOPRIGHT", 14, 0)
    grid:SetSize(gridW, ROWS * TILE_H + (ROWS - 1) * TILE_GAP)
    for i = 1, COLS * ROWS do
        local t = CreateTile(grid, i)
        local c, r = (i - 1) % COLS, math.floor((i - 1) / COLS)
        t:SetPoint("TOPLEFT", c * (TILE_W + TILE_GAP), -r * (TILE_H + TILE_GAP))
        tiles[i] = t
    end
    emptyText = W.Text(grid, "GameFontDisable", nil, "CENTER")
    emptyText:SetPoint("CENTER")
    emptyText:SetText("No beasts match these filters")

    local prev = W.Button(page, "<", 28, 22)
    prev:SetPoint("TOPLEFT", grid, "BOTTOMLEFT", 0, -14)
    prev:SetScript("OnClick", function() ns.ChangePage(-1) end)
    local nextB = W.Button(page, ">", 28, 22)
    nextB:SetPoint("TOPRIGHT", grid, "BOTTOMRIGHT", 0, -14)
    nextB:SetScript("OnClick", function() ns.ChangePage(1) end)
    pageText = W.Text(page, "GameFontHighlightSmall", nil, "CENTER")
    pageText:SetPoint("TOP", grid, "BOTTOM", 0, -19)
    countText = W.Text(page, "GameFontDisableSmall", nil, "CENTER")
    countText:SetPoint("TOP", pageText, "BOTTOM", 0, -6)

    -- right: detail
    local d = BuildDetail(page)
    d:SetPoint("TOPLEFT", grid, "TOPRIGHT", 14, 0)
    d:SetPoint("BOTTOMRIGHT", -12, 12)
    return page
end

function ns.RefreshCollection()
    if not collection then return end
    local per = COLS * ROWS
    local pages = math.max(1, math.ceil(#filtered / per))
    for i, tile in ipairs(tiles) do
        local look = filtered[(state.page - 1) * per + i]
        if look then
            if look.sources[1] then ns.RequestOfficialNPCName(look.sources[1].npc) end
            if tile.look ~= look then
                tile.look = look
                ShowLook(tile.model, look)
            end
            local fam = ns.families[look.family]
            tile.famIcon:SetTexture(fam and fam.icon or nil)
            tile.name:SetText(look.name)
            local s = look.sources[1]
            local lv = look.minLevel > 0 and ((look.maxLevel > look.minLevel and L["Lvl %d-%d"]:format(look.minLevel, look.maxLevel) or L["Lvl %d"]:format(look.minLevel))) or ""
            if state.sort == "dps" or state.sort == "tank" or state.sort == "support" then
                local info = ns.ROLE_INFO[state.sort]
                tile.sub:SetText(("|cff%s%s %d|r"):format(info.color, info.label, ns.FamilyRole(look.family)[state.sort]))
            else
                tile.sub:SetText(lv ~= "" and lv or (s and s.zone or ""))
            end
            ns.StyleTile(tile)
            tile:Show()
        else
            tile.look = nil
            tile:Hide()
        end
    end
    emptyText:SetShown(#filtered == 0)
    pageText:SetText(L["Page %d / %d"]:format(state.page, pages))
    countText:SetText(L["%d looks shown"]:format(#filtered))
    famList:SetItems(FamilyItems())
    if state.selected and not ns.looks[state.selected.id] then state.selected = nil end
    if not state.selected and filtered[1] then ns.SelectLook(filtered[1]) else ns.SelectLook(state.selected) end
end

------------------------------------------------------------------------
-- Main window
------------------------------------------------------------------------
local tabs = {}
local function UpdateHeader()
    if not main then return end
    local points, count, total, maxPoints = ns.GetScore()
    main.pointsBar:SetProgress(points, maxPoints, L["|cffffd100%d|r / %d points"]:format(points, maxPoints))
    main.looksBar:SetProgress(count, total, L["%d / %d looks"]:format(count, total))
    local pins = ns.PinCount and ns.PinCount() or 0
    main.clearPins:SetShown(pins > 0)
    local hunting = ns.IsHunting and ns.IsHunting()
    main.hunt:SetSelected(hunting)
    main.hunt.text:SetText(hunting and L["Hunting (%d)"]:format(ns.HuntCount()) or L["Hunt all"])
    main.hunt:SetWidth(main.hunt.text:GetStringWidth() + 18)
    main.clearPins.text:SetText(L["Clear pins (%d)"]:format(pins))
    main.clearPins:SetWidth(main.clearPins.text:GetStringWidth() + 18)
    if ns.tampered then
        main.pointsBar:SetProgress(points, maxPoints, "|cffff4040Edited outside the game - /hpc reset|r")
    end
end
ns.UpdateHeader = UpdateHeader

local function SelectTab(which)
    state.tab = which
    collection:SetShown(which == "collection")
    if board then board:SetShown(which == "board") end
    if which == "options" and not options and ns.BuildOptions then
        options = ns.BuildOptions(main.body)
    end
    if options then options:SetShown(which == "options") end
    for k, b in pairs(tabs) do b:SetSelected(k == which) end
    if which == "board" and ns.RefreshBoard then ns.RefreshBoard() end
    if which == "collection" then ns.ApplyFilters() end
end

local function BuildMain()
    main = CreateFrame("Frame", "HunterPetCodexFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    W.Skin(main, W.BG, { 0.3, 0.3, 0.32, 1 })
    main:SetSize(FRAME_W, FRAME_H)
    main:SetPoint("CENTER")
    main:SetFrameStrata("HIGH")
    main:SetToplevel(true)
    main:SetClampedToScreen(true)
    main:EnableMouse(true)
    main:SetMovable(true)
    main:RegisterForDrag("LeftButton")
    main:SetScript("OnDragStart", main.StartMoving)
    main:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        ns.db.window = { p, rp, x, y }
    end)
    main:Hide()
    tinsert(UISpecialFrames, "HunterPetCodexFrame")

    if ns.db.window and ns.db.window[1] then
        main:ClearAllPoints()
        main:SetPoint(ns.db.window[1], UIParent, ns.db.window[2], ns.db.window[3], ns.db.window[4])
    end

    -- header
    local header = CreateFrame("Frame", nil, main)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:SetHeight(54)
    local hbg = header:CreateTexture(nil, "BACKGROUND")
    hbg:SetAllPoints()
    hbg:SetTexture(W.WHITE)
    W.Gradient(hbg, 0.16, 0.22, 0.11, 0.06, 0.06, 0.07, 1, 1, "HORIZONTAL")
    local line = header:CreateTexture(nil, "ARTWORK")
    line:SetTexture(W.WHITE)
    line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT")
    line:SetPoint("BOTTOMRIGHT")
    line:SetVertexColor(W.ACCENT[1], W.ACCENT[2], W.ACCENT[3], 0.5)

    local icon = ns.CreateLogo(header, 50)
    icon:SetPoint("LEFT", 6, 0)
    local title = W.Text(header, "GameFontNormalLarge", 18, "LEFT")
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -8)
    title:SetText("Hunter Pet Collector")
    title:SetTextColor(1, 1, 1)
    local sub = W.Text(header, "GameFontDisableSmall", nil, "LEFT")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
    sub:SetText(ns.flavorName .. "  -  v" .. ns.VERSION)

    main.pointsBar = W.Bar(header, 220, 16)
    main.pointsBar:SetPoint("TOPRIGHT", -280, -10)
    main.looksBar = W.Bar(header, 220, 16)
    main.looksBar:SetPoint("TOPRIGHT", main.pointsBar, "BOTTOMRIGHT", 0, -4)

    local tabC = W.Button(header, "Collection", 96, 24)
    tabC:SetPoint("RIGHT", -160, 0)
    tabC:SetScript("OnClick", function() SelectTab("collection") end)
    tabs.collection = tabC
    local tabB = W.Button(header, "Leaderboard", 96, 24)
    tabB:SetPoint("LEFT", tabC, "RIGHT", 6, 0)
    tabB:SetScript("OnClick", function() SelectTab("board") end)
    tabs.board = tabB

    local gear = CreateFrame("Button", nil, header)
    gear:SetSize(18, 18)
    gear:SetPoint("RIGHT", -34, 0)
    gear:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
    gear:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    gear:SetScript("OnClick", function() ns.OpenOptions() end)
    gear:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_BOTTOM"); GameTooltip:SetText("Options"); GameTooltip:Show() end)
    gear:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local clearPins = W.Button(header, "Clear pins", 74, 18)
    clearPins:SetPoint("RIGHT", main.looksBar, "LEFT", -14, 0)
    clearPins:Hide()
    clearPins.tooltip = "Remove every spawn pin from your maps"
    clearPins:SetScript("OnClick", function() ns.ClearPins() end)
    main.clearPins = clearPins

    local hunt = W.Button(header, "Hunt all", 74, 18)
    hunt:SetPoint("RIGHT", main.pointsBar, "LEFT", -14, 0)
    hunt.tooltip = "Show every look you haven't collected on your map and minimap, with the arrow leading to the nearest one. Looks drop off as you collect them.\n|cff999999Filters are in Options.|r"
    hunt:SetScript("OnClick", function() ns.ToggleHunting() end)
    main.hunt = hunt

    local close = CreateFrame("Button", nil, header, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 0, 0)
    close:SetScript("OnClick", function() main:Hide() end)

    local body = CreateFrame("Frame", nil, main)
    body:SetPoint("TOPLEFT", header, "BOTTOMLEFT")
    body:SetPoint("BOTTOMRIGHT")
    main.body = body

    collection = BuildCollection(body)
    if ns.BuildBoard then board = ns.BuildBoard(body) end

    main:SetScript("OnShow", function()
        if PlaySound and SOUNDKIT then pcall(PlaySound, SOUNDKIT.IG_CHARACTER_INFO_OPEN) end
        for _, t in ipairs(tiles) do t.look = nil end   -- models need reloading after being hidden
        if detail then detail.current = nil end
        UpdateHeader()
        SelectTab(state.tab)
    end)
    main:SetScript("OnHide", function()
        if PlaySound and SOUNDKIT then pcall(PlaySound, SOUNDKIT.IG_CHARACTER_INFO_CLOSE) end
    end)
end

-- Only ever called from a click or a slash command, so opening the window
-- can also share your score server-wide (at most every 20 minutes).
function ns.ToggleMain(tab)
    if not main then BuildMain() end
    if tab then state.tab = tab end
    if main:IsShown() and not tab then main:Hide() else
        local opening = not main:IsShown()
        main:Show(); SelectTab(state.tab)
        if opening and ns.AskServer then pcall(ns.AskServer, true) end
    end
end

ns.On("COLLECTION_CHANGED", function()
    if main and main:IsShown() then
        UpdateHeader()
        ns.ApplyFilters()
    end
end)

ns.On("PINS_CHANGED", function()
    if main and main:IsShown() then
        UpdateHeader()
        ns.UpdateMapButton()
        for _, t in ipairs(tiles) do if t:IsShown() and t.look then ns.StyleTile(t) end end
    end
end)

ns.On("TRACKING_CHANGED", function()
    if main and main:IsShown() then ns.UpdateMapButton() end
end)

ns.On("TRACKING_CHANGED", function()
    if main and main:IsShown() then UpdateHeader() end
end)
