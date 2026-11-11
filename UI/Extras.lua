-- Hunter Pet Collector - minimap button, addon compartment and unit tooltips
local ADDON, ns = ...
local W = ns.W

------------------------------------------------------------------------
-- Minimap button (no libraries needed)
------------------------------------------------------------------------
local button

local function Position()
    local angle = math.rad(ns.db.minimap.angle or 200)
    local r = (Minimap:GetWidth() / 2) + 6
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
end

local function ScoreTooltip(owner, anchor)
    GameTooltip:SetOwner(owner, anchor or "ANCHOR_LEFT")
    GameTooltip:AddLine("Hunter Pet Collector", 1, 1, 1)
    local points, count, total, maxPoints = ns.GetScore()
    GameTooltip:AddDoubleLine("Points", ("%d / %d"):format(points, maxPoints), 0.8, 0.8, 0.8, 1, 0.82, 0)
    GameTooltip:AddDoubleLine("Looks", ("%d / %d"):format(count, total), 0.8, 0.8, 0.8, 1, 1, 1)
    local board = ns.SortedBoard()
    for i, e in ipairs(board) do
        if ns.IsMe(e.name) then
            GameTooltip:AddDoubleLine("Leaderboard rank", ("#%d of %d"):format(i, #board), 0.8, 0.8, 0.8, 1, 1, 1)
        end
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Left-click: open the collection", 0.5, 0.5, 0.5)
    GameTooltip:AddLine("Right-click: leaderboard", 0.5, 0.5, 0.5)
    GameTooltip:AddLine("Shift-click: Pet XP Bar options", 0.5, 0.5, 0.5)
    GameTooltip:AddLine("Drag: move button", 0.5, 0.5, 0.5)
    GameTooltip:Show()
end
ns.ScoreTooltip = ScoreTooltip

function ns.UpdateMinimapButton()
    if not button then return end
    if ns.db.minimap.hide then button:Hide() else button:Show(); Position() end
end

local function CreateMinimapButton()
    button = CreateFrame("Button", "HunterPetCodexMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture("Interface\\Icons\\Ability_Hunter_BeastTaming")
    icon:SetSize(20, 20)
    icon:SetPoint("TOPLEFT", 7, -5)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")

    button:SetScript("OnClick", function(_, btn)
        if IsShiftKeyDown() and ns.XP and ns.XP.OpenOptions then ns.XP.OpenOptions()
        elseif btn == "RightButton" then ns.ToggleMain("board") else ns.ToggleMain() end
    end)
    button:SetScript("OnEnter", function(self) ScoreTooltip(self) end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local s = Minimap:GetEffectiveScale()
            ns.db.minimap.angle = math.deg(math.atan2(cy / s - my, cx / s - mx))
            Position()
        end)
    end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    ns.UpdateMinimapButton()
end

-- Addon compartment (mainline-based clients); referenced from the TOC
function HunterPetCodex_OnCompartmentClick(_, button)
    if button == "RightButton" then ns.ToggleMain("board") else ns.ToggleMain() end
end
function HunterPetCodex_OnCompartmentEnter(_, frame) ScoreTooltip(frame or UIParent, "ANCHOR_LEFT") end
function HunterPetCodex_OnCompartmentLeave() GameTooltip:Hide() end

------------------------------------------------------------------------
-- Unit tooltips: show codex status on tameable beasts
------------------------------------------------------------------------
local function AddCodexLine(tooltip, unit)
    if not ns.db or not ns.db.tooltip or ns.playerClass ~= "HUNTER" then return end
    if tooltip ~= GameTooltip then return end
    unit = unit or "mouseover"
    local guid = ns.SafeGUID(unit)
    local npc = ns.NPCIDFromGUID(guid)
    if not npc or (guid and guid:sub(1, 3) == "Pet") then return end
    local look = ns.npcToLook[npc]
    if not look then return end
    local r = ns.RARITY[look.rarity]
    local status = ns.IsCollected(look) and "|cff4cff4cCollected|r" or "|cffff5555Not collected|r"
    tooltip:AddLine(("|TInterface\\Icons\\Ability_Hunter_BeastTaming:0|t |cff%s%s look|r  %s"):format(r.hex, r.name, status))
    tooltip:Show()
end

local function HookTooltips()
    if TooltipDataProcessor and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
            local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
            pcall(AddCodexLine, tooltip, ok and unit or nil)
        end)
    else
        GameTooltip:HookScript("OnTooltipSetUnit", function(tooltip)
            local _, unit = tooltip:GetUnit()
            pcall(AddCodexLine, tooltip, unit)
        end)
    end
end

ns.On("READY", function()
    CreateMinimapButton()
    HookTooltips()
end)
