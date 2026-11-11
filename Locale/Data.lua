local _, ns = ...
function ns.LocalizeNPC(id, fallback)
    local db = ns.db and ns.db.officialNPCNames
    local flavor = db and db[ns.flavor]
    local names = flavor and flavor[GetLocale()]
    return (names and names[id]) or (ns.NPCNames and ns.NPCNames[id]) or fallback
end

function ns.LocalizeZone(zone, npc, flavor)
    if GetLocale() == "enUS" then return zone end
    if ns.L[zone] ~= zone then return ns.L[zone] end
    local spawns = ns.spawnSets[flavor] and ns.spawnSets[flavor][npc]
    if not spawns or not C_Map or not C_Map.GetMapInfo then return zone end
    local found
    for mapID in pairs(spawns) do
        local info = C_Map.GetMapInfo(mapID)
        local name = info and info.name
        if name and name ~= "" then
            if found and found ~= name then return zone end
            found = name
        end
    end
    return found or zone
end
