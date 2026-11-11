-- Hunter Pet Collector - easy pet feeding (game versions with pet happiness,
-- like WoW: Forever; does nothing on MoP Classic, where pets don't eat)
--
--  * A Feed button: one click feeds your pet the best food in your bags that
--    it will eat. Hover it to see what it will use and how many you have.
--  * A happiness face: green happy, yellow content, red unhappy.
--  * A warning when your pet stops being happy (unhappy pets do less damage).
--
-- The button is a secure action button (the game only lets addons cast
-- spells that way), so it can only be changed out of combat: food choice and
-- visibility update as soon as combat ends.
local ADDON, ns = ...
local F = {}
ns.Feed = F

local FOOD_TYPES = { "Meat", "Fish", "Cheese", "Bread", "Fungus", "Fruit" }
F.FOOD_TYPES = FOOD_TYPES

-- Original-game diets, used if the game doesn't report the pet's diet
local FAMILY_DIET = {
    Bat = { 5, 6 }, Bear = { 1, 2, 3, 4, 5, 6 }, Boar = { 1, 2, 3, 4, 5, 6 },
    ["Carrion Bird"] = { 1, 2 }, Cat = { 1, 2 }, Crab = { 2, 4, 5, 6 },
    Crocolisk = { 1, 2 }, Gorilla = { 5, 6 }, Hyena = { 1, 6 }, Owl = { 1 },
    Raptor = { 1 }, Scorpid = { 1 }, Spider = { 1 }, Tallstrider = { 3, 5, 6 },
    Turtle = { 2, 5, 6 }, ["Wind Serpent"] = { 2, 3, 4 }, Wolf = { 1 },
}

local HAPPY_TEXT = { "Unhappy", "Content", "Happy" }
local HAPPY_COLOR = { { 1, 0.25, 0.25 }, { 1, 0.82, 0 }, { 0.3, 1, 0.3 } }
local HAPPY_TIP = { "Unhappy: 75% damage. Feed it!", "Content: normal damage.", "Happy: 125% damage." }

---------------------------------------------------------------------------
-- What does the pet eat, and what's the best food for it?
---------------------------------------------------------------------------
function F.Supported()
    return ns.playerClass == "HUNTER" and GetPetHappiness ~= nil and GetPetFoodTypes ~= nil
end

-- set of food type numbers the current pet eats
function F.Diet()
    local diet = {}
    if GetPetFoodTypes then
        local ok, a, b, c, d, e, f = pcall(GetPetFoodTypes)
        if ok then
            for _, name in ipairs({ a, b, c, d, e, f }) do
                for i, t in ipairs(FOOD_TYPES) do
                    if type(name) == "string" and name:lower():find(t:lower(), 1, true) then diet[i] = true end
                end
            end
        end
    end
    if not next(diet) then
        local fam = UnitCreatureFamily and UnitCreatureFamily("pet")
        for _, i in ipairs(FAMILY_DIET[fam or ""] or {}) do diet[i] = true end
    end
    return diet
end

-- Pick from { {id=, count=, level=, type=}, ... }. Pets refuse food 30+
-- levels below them, and the closer the food's level the more happiness it
-- gives. Prefer the cheapest food within 10 levels of the pet (saving the
-- good stuff), otherwise the highest-level food it will still eat.
function F.Choose(items, petLevel, diet)
    local good, ok
    for _, it in ipairs(items) do
        if diet[it.type] and it.level > petLevel - 30 then
            if it.level >= petLevel - 10 then
                if not good or it.level < good.level or (it.level == good.level and it.count > good.count) then good = it end
            elseif not ok or it.level > ok.level then
                ok = it
            end
        end
    end
    return good or ok
end

local function BagItems()
    local items, seen = {}, {}
    local getID = (C_Container and C_Container.GetContainerItemID) or GetContainerItemID
    local getSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
    local getCount = GetItemCount
    if not getID or not getSlots then return items end
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        for slot = 1, getSlots(bag) or 0 do
            local id = getID(bag, slot)
            local food = id and ns.PET_FOODS and ns.PET_FOODS[id]
            if food and not seen[id] then
                seen[id] = true
                items[#items + 1] = { id = id, level = food[1], type = food[2], count = getCount and getCount(id) or 1 }
            end
        end
    end
    return items
end

function F.BestFood()
    if not UnitExists("pet") then return nil end
    return F.Choose(BagItems(), UnitLevel("pet") or 1, F.Diet())
end

---------------------------------------------------------------------------
-- Button
---------------------------------------------------------------------------
local button, face, pending
local W

local function FeedSpellName()
    if GetSpellInfo then
        local ok, name = pcall(GetSpellInfo, 6991)
        if ok and name then return name end
    end
    if C_Spell and C_Spell.GetSpellName then
        local ok, name = pcall(C_Spell.GetSpellName, 6991)
        if ok and name then return name end
    end
    return "Feed Pet"
end

local function ItemName(id)
    local name = GetItemInfo and GetItemInfo(id)
    return name or ("item:" .. id)
end

local function ItemIcon(id)
    if GetItemIcon then return GetItemIcon(id) end
    return select(10, GetItemInfo(id))
end

local function SavePos()
    local p, _, rp, x, y = button:GetPoint(1)
    ns.db.feedPos = { p, rp, x, y }
end

local function Build()
    W = ns.W
    local ok = pcall(function()
        button = CreateFrame("Button", "HPCFeedPetButton", UIParent, "SecureActionButtonTemplate")
    end)
    if not ok or not button then button = nil; return end
    button:SetSize(32, 32)
    button:SetFrameStrata("MEDIUM")
    button:SetClampedToScreen(true)
    button:SetMovable(true)
    button:RegisterForClicks("AnyUp", "AnyDown")
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnDragStart", function(self)
        if IsShiftKeyDown() and not InCombatLockdown() then self:StartMoving() end
    end)
    button:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SavePos() end)
    W.Skin(button, { 0.06, 0.06, 0.07, 0.96 }, W.EDGE)

    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", 2, -2)
    button.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button.count = W.Text(button, "NumberFontNormal", nil, "RIGHT")
    button.count:SetPoint("BOTTOMRIGHT", -2, 2)

    -- happiness face, a coloured dot in the corner
    face = button:CreateTexture(nil, "OVERLAY")
    face:SetSize(10, 10)
    face:SetPoint("TOPLEFT", -3, 3)
    face:SetTexture(W.WHITE)
    button.face = face

    local hl = button:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(button.icon)
    hl:SetColorTexture(1, 1, 1, 0.15)

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Feed pet", 1, 1, 1)
        local h = GetPetHappiness and select(1, GetPetHappiness())
        if h and HAPPY_TEXT[h] then
            local c = HAPPY_COLOR[h]
            GameTooltip:AddLine(HAPPY_TIP[h], c[1], c[2], c[3])
        end
        local food = self.food
        if food then
            GameTooltip:AddDoubleLine("Will use", ItemName(food.id), 0.8, 0.8, 0.8, 1, 1, 1)
            GameTooltip:AddDoubleLine("In your bags", tostring(food.count), 0.8, 0.8, 0.8, 1, 1, 1)
        else
            GameTooltip:AddLine("No food in your bags that your pet will eat.", 1, 0.4, 0.4, true)
        end
        local diet = {}
        for i in pairs(F.Diet()) do diet[#diet + 1] = FOOD_TYPES[i] end
        table.sort(diet)
        if #diet > 0 then GameTooltip:AddDoubleLine("Eats", table.concat(diet, ", "), 0.8, 0.8, 0.8, 0.67, 0.83, 0.45) end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Click to feed  -  Shift-drag to move", 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local p = ns.db.feedPos
    if p and p[1] then
        button:SetPoint(p[1], UIParent, p[2] or p[1], p[3] or 0, p[4] or 0)
    else
        button:SetPoint("CENTER", UIParent, "CENTER", 175, -180)   -- just right of the XP bar
    end
    button:Hide()
end

-- face colour: safe any time (not part of the secure setup)
local lastHappy
local function UpdateFace()
    if not button then return end
    local h = GetPetHappiness and UnitExists("pet") and select(1, GetPetHappiness())
    local c = h and HAPPY_COLOR[h]
    if c then face:SetVertexColor(c[1], c[2], c[3]); face:Show() else face:Hide() end
    -- warn when the pet stops being happy
    if h and lastHappy and h < lastHappy and h < 3 and ns.db.feedWarn then
        local msg = ("Your pet is %s - feed it!"):format(HAPPY_TEXT[h]:lower())
        ns.Print("|cffff8080" .. msg .. "|r")
        if UIErrorsFrame and UIErrorsFrame.AddMessage then UIErrorsFrame:AddMessage(msg, 1, 0.5, 0.3) end
        if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then pcall(PlaySound, SOUNDKIT.RAID_WARNING) end
    end
    lastHappy = h
end
F.UpdateFace = UpdateFace

-- food choice and visibility: only out of combat (secure button)
function F.Update()
    if not button then return end
    UpdateFace()
    if InCombatLockdown() then pending = true; return end
    pending = false
    if not ns.db.feedButton or not F.Supported() or not UnitExists("pet") then
        button:Hide()
        return
    end
    local food = F.BestFood()
    button.food = food
    if food then
        button:SetAttribute("type", "macro")
        button:SetAttribute("macrotext", "/cast " .. FeedSpellName() .. "\n/use " .. ItemName(food.id))
        button.icon:SetTexture(ItemIcon(food.id) or "Interface\\Icons\\Ability_Hunter_BeastTraining")
        button.icon:SetDesaturated(false)
        button.count:SetText(food.count > 1 and food.count or "")
    else
        button:SetAttribute("type", nil)
        button:SetAttribute("macrotext", nil)
        button.icon:SetTexture("Interface\\Icons\\Ability_Hunter_BeastTraining")
        button.icon:SetDesaturated(true)
        button.count:SetText("")
    end
    button:Show()
end

function F.ResetPosition()
    ns.db.feedPos = nil
    if button and not InCombatLockdown() then
        button:ClearAllPoints()
        button:SetPoint("CENTER", UIParent, "CENTER", 175, -180)
    end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event, unit)
    if event == "UNIT_HAPPINESS" then
        if unit and unit ~= "pet" then return end
        UpdateFace()
    elseif event == "UNIT_PET" then
        if unit ~= "player" then return end
        lastHappy = nil
        F.Update()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pending then F.Update() end
    elseif event == "UNIT_LEVEL" then
        if unit == "pet" then F.Update() end   -- food that's right for it changes with its level
    else -- BAG_UPDATE_DELAYED, PET_UI_UPDATE
        F.Update()
    end
end)

function F.Init()
    if button or not F.Supported() then return end   -- MoP Classic or not a hunter: nothing to do
    Build()
    if not button then return end
    for _, e in ipairs({ "UNIT_PET", "UNIT_HAPPINESS", "PET_UI_UPDATE", "BAG_UPDATE_DELAYED",
                         "PLAYER_REGEN_ENABLED", "UNIT_LEVEL" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    F.Update()
end
F.button = function() return button end
ns.On("READY", F.Init)
