-- Resolve names through the game's unit tooltip. Requests are sequential because
-- NPC data may arrive asynchronously and the client can throttle lookups.
local _, ns = ...
local queue, pending, attempted = {}, {}, {}
local tooltip, active, serial, cooling = nil, nil, 0, false
local pump

local function cacheName(id, name)
    if not ns.db or type(name) ~= "string" or ns.IsSecret(name) or name == "" or name == RETRIEVING_DATA or name == UNKNOWN then return end
    local db = ns.db
    db.officialNPCNames = db.officialNPCNames or {}
    db.officialNPCNames[ns.flavor] = db.officialNPCNames[ns.flavor] or {}
    local byFlavor = db.officialNPCNames[ns.flavor]
    byFlavor[GetLocale()] = byFlavor[GetLocale()] or {}
    if byFlavor[GetLocale()][id] == name then return end
    byFlavor[GetLocale()][id] = name
    for _, look in ipairs(ns.lookList or {}) do
        for i, src in ipairs(look.sources or {}) do
            if src.npc == id then
                src.name = name
                if i == 1 then look.name = name end
            end
        end
    end
    if ns.RefreshCollection then ns.RefreshCollection() end
end

local function finish(token)
    if not active or active.token ~= token then return end
    pending[active.id] = nil
    active = nil
    cooling = true
    C_Timer.After(0.4, function() cooling = false; pump() end)
end

local function onTooltip(frame, data)
    if frame ~= tooltip or not active or not data or ns.IsSecret(data.guid) then return end
    if type(data.guid) ~= "string" or not data.guid:match("^Creature%-") or ns.NPCIDFromGUID(data.guid) ~= active.id then return end
    local lines = data.lines
    local name = lines and lines[1] and lines[1].leftText
    if type(name) ~= "string" or ns.IsSecret(name) or name == "" or name == RETRIEVING_DATA or name == UNKNOWN then return end
    local id, token = active.id, active.token
    cacheName(id, name)
    finish(token)
end

local function setup()
    if tooltip then return true end
    if not (C_Timer and C_Timer.After and TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit and CreateFrame) then return false end
    tooltip = CreateFrame("GameTooltip", "HPCOfficialNameTooltip", UIParent, "GameTooltipTemplate")
    tooltip:Show()
    tooltip:SetOwner(UIParent, "ANCHOR_NONE")
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, onTooltip)
    return true
end

pump = function()
    if active or cooling then return end
    local id = table.remove(queue, 1)
    if not id then return end
    serial = serial + 1
    local token = serial
    active = {id=id, token=token}
    local link = ("unit:Creature-0-0-0-0-%d-0"):format(id)
    pcall(tooltip.SetHyperlink, tooltip, link)
    C_Timer.After(0.4, function()
        if active and active.token == token then pcall(tooltip.SetHyperlink, tooltip, link) end
    end)
    C_Timer.After(0.8, function() finish(token) end)
end

function ns.RequestOfficialNPCName(id)
    if type(id) ~= "number" or id <= 0 or not ns.db then return end
    local db = ns.db.officialNPCNames
    if db and db[ns.flavor] and db[ns.flavor][GetLocale()] and db[ns.flavor][GetLocale()][id] then return end
    if pending[id] or attempted[id] or not setup() then return end
    attempted[id], pending[id] = true, true
    queue[#queue + 1] = id
    pump()
end

-- Names of actual targets and mouseover creatures are reliable even if
-- querying an arbitrary ID is unavailable on this client.
if CreateFrame then
    local observer = CreateFrame("Frame")
    observer:RegisterEvent("PLAYER_TARGET_CHANGED")
    observer:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
    observer:SetScript("OnEvent", function(_, event)
        local unit = event == "PLAYER_TARGET_CHANGED" and "target" or "mouseover"
        local guid = ns.SafeGUID and ns.SafeGUID(unit)
        if not guid or ns.IsSecret(guid) or not guid:match("^Creature%-") then return end
        local id = ns.NPCIDFromGUID(guid)
        if not id or not ns.npcToLook or not ns.npcToLook[id] then return end
        local ok, name = pcall(UnitName, unit)
        if ok then cacheName(id, name) end
    end)
end
