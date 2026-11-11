-- Hunter Pet Collector - Core
-- Collection tracking, rarity/points, flavour detection and API compatibility.
local ADDON, ns = ...
local L = ns.L
ns.ADDON = ADDON
ns.VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)(ADDON, "Version") or "dev"

------------------------------------------------------------------------
-- Flavour detection
------------------------------------------------------------------------
local _, _, _, TOC = GetBuildInfo()
TOC = tonumber(TOC) or 0
if TOC >= 50000 and TOC < 60000 then
    ns.flavor = "mop"
    ns.flavorName = "Mists of Pandaria Classic"
elseif TOC >= 16000 and TOC < 17000 then
    ns.flavor = "forever"
    ns.flavorName = "WoW: Forever"
elseif TOC < 20000 then
    ns.flavor = "forever"          -- Classic Era / Hardcore / SoD share the vanilla beast list
    ns.flavorName = "Classic Era"
else
    ns.flavor = "mop"               -- best available fallback for other clients
    ns.flavorName = "Unsupported client (using MoP data)"
end

------------------------------------------------------------------------
-- Small compat helpers (probe APIs, never branch on project id alone)
------------------------------------------------------------------------
local issecret = issecretvalue or function() return false end
ns.IsSecret = issecret

function ns.SafeGUID(unit)
    local ok, guid = pcall(UnitGUID, unit)
    if not ok or guid == nil or issecret(guid) then return nil end
    return guid
end

-- Creature-0-1-2-3-NPCID-spawn  /  Pet-0-1-2-3-NPCID-petnumber
function ns.NPCIDFromGUID(guid)
    if not guid then return nil end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind == "Creature" or kind == "Pet" or kind == "Vehicle" then
        return tonumber(id)
    end
end

function ns.After(sec, fn)
    if C_Timer and C_Timer.After then C_Timer.After(sec, fn) else fn() end
end

-- "Name-Realm" with the realm written the way the game's addon messages use
-- it (no spaces, hyphens or apostrophes), so names always compare equal.
function ns.NormalizeName(full)
    if not full then return nil end
    local name, realm = strsplit("-", full, 2)
    if not realm or realm == "" then
        realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or ""
    end
    realm = realm:gsub("[%s%-']", "")
    return name .. "-" .. realm
end

function ns.Print(...)
    print("|cffabd473Pet Collector|r:", ...)
end

ns.callbacks = {}
function ns.On(event, fn)
    ns.callbacks[event] = ns.callbacks[event] or {}
    table.insert(ns.callbacks[event], fn)
end
function ns.Fire(event, ...)
    for _, fn in ipairs(ns.callbacks[event] or {}) do
        local ok, err = pcall(fn, ...)
        if not ok then geterrorhandler()(err) end
    end
end

------------------------------------------------------------------------
-- Rarity & points
------------------------------------------------------------------------
ns.RARITY = {
    [1] = { key = "common",    name = L["Common"],    points = 5,   color = { 0.86, 0.86, 0.86 }, hex = "dcdcdc" },
    [2] = { key = "uncommon",  name = L["Uncommon"],  points = 10,  color = { 0.12, 1.00, 0.00 }, hex = "1eff00" },
    [3] = { key = "rare",      name = L["Rare"],      points = 25,  color = { 0.00, 0.44, 0.87 }, hex = "0070dd" },
    [4] = { key = "epic",      name = L["Epic"],      points = 50,  color = { 0.64, 0.21, 0.93 }, hex = "a335ee" },
    [5] = { key = "legendary", name = L["Legendary"], points = 100, color = { 1.00, 0.50, 0.00 }, hex = "ff8000" },
}

ns.CLASSIFICATION = { [0] = "Normal", [1] = "Elite", [2] = "Rare Elite", [3] = "Boss", [4] = "Rare" }

------------------------------------------------------------------------
-- Data registration (Data/*.lua call this)
------------------------------------------------------------------------
ns.datasets = {}
ns.spawnSets = {}
function ns.RegisterSpawns(flavor, t) ns.spawnSets[flavor] = t end
function ns.RegisterData(flavor, data)
    ns.datasets[flavor] = data
end

-- Build runtime indexes from the compact dataset for the active flavour.
-- look = { id=displayId, family=famId, rarity=1..5, sources={ {npc,name,min,max,cls,zone}, ... } }
function ns.BuildIndex()
    local data = ns.datasets[ns.flavor] or ns.datasets.mop or ns.datasets.forever
    ns.data = data
    ns.families, ns.looks, ns.lookList, ns.npcToLook = {}, {}, {}, {}
    if not data then return end

    for id, f in pairs(data.families) do
        ns.families[id] = { id = id, name = f[1], icon = "Interface\\Icons\\" .. f[2], exotic = f[3] and true or false }
    end

    for _, row in ipairs(data.looks) do
        local look = { id = row[1], family = row[2], rarity = row[3], sources = {} }
        for i = 4, #row do
            local s = row[i]
            local src = { npc = s[1], name = s[2], minLevel = s[3], maxLevel = s[4], cls = s[5], zone = s[6] }
            look.sources[#look.sources + 1] = src
            ns.npcToLook[s[1]] = look
        end
        look.name = look.sources[1] and look.sources[1].name or ("Display " .. look.id)
        local lo, hi = 999, 0
        for _, s in ipairs(look.sources) do
            if s.minLevel > 0 and s.minLevel < lo then lo = s.minLevel end
            if s.maxLevel > hi then hi = s.maxLevel end
        end
        look.minLevel, look.maxLevel = (lo == 999 and 0 or lo), hi
        ns.looks[look.id] = look
        ns.lookList[#ns.lookList + 1] = look
    end

    -- Beasts discovered in-game that the shipped data didn't know about
    for displayId, d in pairs(ns.db.discovered[ns.flavor] or {}) do
        if not ns.looks[displayId] then
            local look = { id = displayId, family = d.family or 0, rarity = 2, discovered = true,
                name = d.name or "Unknown beast", minLevel = d.level or 0, maxLevel = d.level or 0,
                sources = { { npc = d.npc or 0, name = d.name or "?", minLevel = d.level or 0, maxLevel = d.level or 0, cls = 0, zone = d.zone or "Discovered in-game" } } }
            ns.looks[displayId] = look
            ns.lookList[#ns.lookList + 1] = look
            if d.npc then ns.npcToLook[d.npc] = look end
        end
    end

    -- Never lose a collected look because the shipped data changed: anything
    -- in your collection that this version's data doesn't know about still
    -- shows (and scores) as a kept look.
    local col = ns.cdb and ns.cdb.collected and ns.cdb.collected[ns.flavor]
    for id, e in pairs(col or {}) do
        if not ns.looks[id] then
            local look = { id = id, family = 0, rarity = 2, discovered = true, kept = true,
                name = e.name or ("Look " .. id), minLevel = 0, maxLevel = 0,
                sources = { { npc = e.npc or 0, name = e.name or "?", minLevel = 0, maxLevel = 0, cls = 0, zone = "Kept from an earlier version" } } }
            ns.looks[id] = look
            ns.lookList[#ns.lookList + 1] = look
            if e.npc and not ns.npcToLook[e.npc] then ns.npcToLook[e.npc] = look end
        end
    end

    ns.totalPoints = 0
    for _, look in ipairs(ns.lookList) do
        ns.totalPoints = ns.totalPoints + ns.RARITY[look.rarity].points
    end
    table.sort(ns.lookList, function(a, b)
        if a.family ~= b.family then
            local fa, fb = ns.families[a.family], ns.families[b.family]
            return (fa and fa.name or "~") < (fb and fb.name or "~")
        end
        if a.rarity ~= b.rarity then return a.rarity > b.rarity end
        return a.name < b.name
    end)
end

------------------------------------------------------------------------
-- Saved variables
------------------------------------------------------------------------
local DB_DEFAULTS = {
    minimap = { angle = 200, hide = false },
    tooltip = true,
    shareScore = true,
    useChannel = true,
    shareWithFriends = true,
    board = {},          -- [flavor] = { [name-realm] = entry }
    backup = {},         -- [name-realm] = { [flavor] = { looks = {...}, sig = ... } }
    discovered = {},     -- [flavor] = { [displayId] = info }
    window = {},
    pins = {},           -- [flavor] = { [npcId] = true }   map pins stay until cleared
    showWorldPins = true,
    showMinimapPins = true,
    autoClearPins = false,
    pinScale = 1,
    minimapPaw = true,
    showArrow = true,
    arrowPos = {},
    alertEnabled = true,
    alertSound = true,
    alertMode = "rares",   -- "tracked" | "rares" | "all"
    petXPBar = true,       -- pet XP bar on/off (its own settings live in HPCPetXPDB)
    feedButton = true,     -- one-click Feed button (game versions where pets eat)
    feedWarn = true,       -- warn when the pet stops being happy
}
local CHAR_DEFAULTS = {
    collected = {},      -- [flavor] = { [displayId] = { t=time, npc=id, name=str, auto=bool } }
    tracking = {},       -- [flavor] = displayId of the look the arrow is tracking
}

local function ApplyDefaults(t, d)
    for k, v in pairs(d) do
        if t[k] == nil then
            t[k] = type(v) == "table" and CopyTable(v) or v
        elseif type(v) == "table" and type(t[k]) == "table" then
            ApplyDefaults(t[k], v)
        end
    end
end

------------------------------------------------------------------------
-- Collection API
------------------------------------------------------------------------
function ns.Collected()
    local c = ns.cdb.collected
    c[ns.flavor] = c[ns.flavor] or {}
    return c[ns.flavor]
end

function ns.IsCollected(look)
    return ns.Collected()[look.id] ~= nil
end

function ns.GetScore()
    local points, count = 0, 0
    for displayId in pairs(ns.Collected()) do
        local look = ns.looks[displayId]
        if look then
            points = points + ns.RARITY[look.rarity].points
            count = count + 1
        end
    end
    return points, count, #ns.lookList, ns.totalPoints
end

------------------------------------------------------------------------
-- Integrity: the collection is signed with the character's GUID so that
-- hand-edited or copied SavedVariables are detected. (Nothing an addon does
-- can be fully tamper-proof, but this stops casual cheating.)
------------------------------------------------------------------------
local function Hash(str, seed)
    local h = seed
    for i = 1, #str do
        h = (h * 33 + str:byte(i)) % 4294967296
    end
    return h
end

-- Who a collection is signed for: the character's GUID (falls back to
-- Name-Realm where the GUID is hidden).
local function Identity()
    return ns.playerGUID or ns.playerName
end

-- Signs a collection table. Returns the current signature format and the
-- 1.1-1.4.3 format, which is still accepted when verifying.
local function SignTable(tbl, who)
    who = who or Identity()
    if not who then return nil end
    local keys = {}
    for id, e in pairs(tbl) do
        keys[#keys + 1] = ("%d:%s:%s:%s"):format(id, tostring(e.npc or 0), tostring(e.t or 0), tostring(e.auto or ""))
    end
    table.sort(keys)
    local blob = who .. "|" .. ns.flavor .. "|" .. table.concat(keys, ";") .. "|hpc-v2"
    local h1, h2 = Hash(blob, 5381), Hash(blob:reverse(), 7919)
    local ok, old = pcall(string.format, "%08x%08x", h1, h2)
    return ("v3:%.0f:%.0f"):format(h1, h2), ok and old or nil
end

local function Matches(sig, tbl, who)
    if not sig then return false end
    local cur, old = SignTable(tbl, who)
    return sig == cur or (old ~= nil and sig == old)
end

------------------------------------------------------------------------
-- Backup: every collected look is also written to the account-wide saved
-- file. That file isn't tied to a realm or character, so it survives realm
-- transfers and covers the case where the game fails to load the
-- per-character file. Collected looks are never removed except by /hpc reset.
------------------------------------------------------------------------
local function ShortName(full) return (strsplit("-", full or "")) end

local function BackupFor(key, create)
    local b = ns.db.backup
    if not b[key] then
        if not create then return nil end
        b[key] = {}
    end
    local entry = b[key]
    entry.class = entry.class or ns.playerClassFile
    if not entry[ns.flavor] then
        if not create then return nil end
        entry[ns.flavor] = { looks = {} }
    end
    return entry[ns.flavor], entry
end

local function Sign()
    local who = Identity()
    ns.cdb.sig = ns.cdb.sig or {}
    ns.cdb.signer = ns.cdb.signer or {}
    ns.cdb.sig[ns.flavor] = (SignTable(ns.Collected(), who))
    ns.cdb.signer[ns.flavor] = who
    -- the backup only ever grows: looks already in a valid backup are kept
    -- even if this character's file lost them. Only /hpc reset empties it.
    local bk = BackupFor(ns.playerName, true)
    local keep = {}
    if not ns.resetting and bk.looks and next(bk.looks) and Matches(bk.sig, bk.looks, bk.signer) then
        keep = bk.looks
    end
    local looks = {}
    for id, e in pairs(keep) do looks[id] = e end
    for id, e in pairs(ns.Collected()) do
        looks[id] = { t = e.t, npc = e.npc, name = e.name, auto = e.auto }
    end
    bk.looks = looks
    bk.signer = who
    bk.sig = (SignTable(bk.looks, who))
end
ns.SignCollection = function() if not ns.tampered then Sign() end end
ns.Hash = Hash

local function BackupValid(bk)
    return bk and bk.looks and next(bk.looks) ~= nil and Matches(bk.sig, bk.looks, bk.signer)
end

local function CopyInto(col, looks)
    local n = 0
    for id, e in pairs(looks) do
        if not col[id] then
            col[id] = { t = e.t, npc = e.npc, name = e.name, auto = e.auto }
            n = n + 1
        end
    end
    return n
end

-- Backups from other characters with the same name and class: after a realm
-- transfer the character's key changes, so offer to bring the collection over.
local function TransferCandidates()
    local out = {}
    local myShort = ShortName(ns.playerName)
    for key, entry in pairs(ns.db.backup) do
        if key ~= ns.playerName and ShortName(key) == myShort and entry.class == ns.playerClassFile then
            local bk = entry[ns.flavor]
            if BackupValid(bk) then
                local n = 0
                for _ in pairs(bk.looks) do n = n + 1 end
                out[#out + 1] = { key = key, bk = bk, count = n }
            end
        end
    end
    table.sort(out, function(a, b) return a.count > b.count end)
    return out
end

function ns.AdoptBackup(key)
    local entry = ns.db.backup[key]
    local bk = entry and entry[ns.flavor]
    if not BackupValid(bk) then return ns.Print("That backup can't be used.") end
    -- only the same character (same name and class) can take a collection over
    if ShortName(key) ~= ShortName(ns.playerName) or entry.class ~= ns.playerClassFile then
        return ns.Print("That backup belongs to a different character, so it can't be moved here.")
    end
    local n = CopyInto(ns.Collected(), bk.looks)
    ns.tampered = false
    Sign()
    ns.Print(("Brought over %d look%s from %s."):format(n, n == 1 and "" or "s", key))
    ns.Fire("COLLECTION_CHANGED")
end

function ns.VerifyCollection()
    ns.cdb.sig = ns.cdb.sig or {}
    ns.cdb.signer = ns.cdb.signer or {}
    local col = ns.Collected()
    local charSig, charSigner = ns.cdb.sig[ns.flavor], ns.cdb.signer[ns.flavor]

    -- one-time 1.0 -> 1.1 migration: manual marks no longer count
    if not ns.cdb.migrated11 then
        local removed = 0
        for id, e in pairs(col) do
            if e.auto == "manual" then col[id] = nil; removed = removed + 1 end
        end
        if removed > 0 then ns.Print(("Removed %d manually-marked look%s. Only beasts you actually tame count now."):format(removed, removed == 1 and "" or "s")) end
        ns.cdb.migrated11 = true
        if removed > 0 then charSig = nil end
    end

    -- is this character's own file intact?
    local valid
    if charSig == nil or next(col) == nil then
        valid = true                                  -- new character or fresh file
    elseif Matches(charSig, col, charSigner or Identity()) then
        valid = true                                  -- signed here, or before a realm transfer
    elseif charSigner == nil then
        valid = true                                  -- file from 1.1-1.4.3 copied after a transfer
    else
        valid = false
    end

    -- restore anything the account-wide backup has that this file lost
    local restored = 0
    local bk = BackupFor(ns.playerName, false)
    if BackupValid(bk) then restored = CopyInto(col, bk.looks) end
    -- WoW: Forever: realms are hidden layers, so the realm in our saved name
    -- can differ between sessions. Same name and class on this account is
    -- the same character: bring its looks back quietly (add only).
    if ns.flavor == "forever" then
        for _, c in ipairs(TransferCandidates()) do restored = restored + CopyInto(col, c.bk.looks) end
    end
    -- and anything an update-time snapshot still has
    for _, snap in ipairs(ns.db.snapshots or {}) do
        local entry = snap.backup and snap.backup[ns.playerName]
        local sb = entry and entry[ns.flavor]
        if BackupValid(sb) then restored = restored + CopyInto(col, sb.looks) end
    end
    if restored > 0 then
        ns.Print(("Restored %d look%s from your backup."):format(restored, restored == 1 and "" or "s"))
    end

    ns.tampered = not valid
    if ns.tampered then
        ns.Print("|cffff4040Your collection data was changed outside the game.|r Your score won't be shared. Put back your original saved file to share it again.")
    else
        Sign()
    end

    -- realm transfer: nothing here, but a same-name hunter elsewhere has a backup
    -- (not on Forever: there it was brought back above)
    if next(col) == nil and ns.flavor ~= "forever" then
        local cands = TransferCandidates()
        if cands[1] then
            ns.pendingAdopt = cands[1]
            StaticPopup_Show("HPC_ADOPT_BACKUP", cands[1].key, cands[1].count)
        end
    end
    return valid
end

function ns.ResetCollection()
    wipe(ns.Collected())
    ns.tampered = false
    ns.resetting = true
    Sign()
    ns.resetting = nil
    -- a reset is deliberate: don't let update snapshots bring the looks back
    for _, snap in ipairs(ns.db.snapshots or {}) do
        local entry = snap.backup and snap.backup[ns.playerName]
        if entry then entry[ns.flavor] = nil end
    end
    ns.Fire("COLLECTION_CHANGED")
    ns.Print("Collection reset. Summon or tame your pets to collect them again.")
end

-- Only the tame/summon/stable scanners call this; there's no manual marking.
local function AddCollected(look, info)
    local col = ns.Collected()
    if col[look.id] then return false end
    col[look.id] = { t = time(), npc = info.npc, name = info.name, auto = info.auto }
    if not ns.tampered then Sign() end
    ns.Fire("COLLECTION_CHANGED", look, true)
    return true
end

-- Hidden model used to read display IDs where the client supports it
local probe
-- Newer game engines (WoW: Forever) give every tamed pet the same creature
-- ID, so it says nothing about which beast it was.
local GENERIC_PET_NPC = { [165189] = true }
ns.GENERIC_PET_NPC = GENERIC_PET_NPC

local function GoodID(id) return type(id) == "number" and id > 0 and not issecret(id) and id or nil end

-- The model of a unit, read from a tiny, nearly invisible model frame. On
-- newer engines the model loads a moment after SetUnit, so a first call can
-- come back empty; ScanActivePet tries again shortly after.
local function DisplayIDForUnit(unit)
    if not probe then
        probe = CreateFrame("PlayerModel", nil, UIParent)
        probe:SetSize(2, 2)
        probe:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
        probe:SetFrameStrata("BACKGROUND")
        probe:SetAlpha(0.01)   -- shown (so the model loads) but not visible
    end
    probe:Show()
    local ok = pcall(probe.SetUnit, probe, unit)
    if not ok or not probe.GetDisplayInfo then return nil end
    local ok2, id = pcall(probe.GetDisplayInfo, probe)
    if ok2 and GoodID(id) then return id end
end

-- Pets we've identified before (from the stable or a scan), remembered per
-- character by name and family. On WoW: Forever the game only reveals a
-- pet's model at the stable, so one stable visit is enough after this.
local function PetMemoryKey(name, family)
    if not name or issecret(name) then return nil end
    return tostring(name) .. "|" .. tostring(family or "")
end
local function RememberPet(name, family, display, npc)
    local key = PetMemoryKey(name, family)
    if not key or not (display or npc) or not ns.cdb then return end
    ns.cdb.petMemory = ns.cdb.petMemory or {}
    ns.cdb.petMemory[key] = { display = display, npc = npc }
end
local function RecallPet(name, family)
    local key = PetMemoryKey(name, family)
    local m = key and ns.cdb and ns.cdb.petMemory and ns.cdb.petMemory[key]
    if m then return m.display, m.npc end
end
ns.RememberPet, ns.RecallPet = RememberPet, RecallPet

-- The active pet's model and original creature from the game's stable
-- functions (newer engines list active pets with both).
local function ActivePetFromStable()
    if not (C_StableInfo and UnitExists("pet")) then return end
    local name, level = UnitName("pet"), UnitLevel("pet")
    if issecret(name) then return end
    local function match(info)
        if type(info) ~= "table" or info.name ~= name then return end
        if info.level and level and info.level ~= level then return end
        local npc = GoodID(info.creatureID)
        if npc and GENERIC_PET_NPC[npc] then npc = nil end
        local disp = GoodID(info.displayID)
        if disp or npc then return disp, npc end
    end
    if C_StableInfo.GetActivePetList then
        local ok, list = pcall(C_StableInfo.GetActivePetList)
        if ok and type(list) == "table" then
            for _, info in ipairs(list) do
                local d, n = match(info)
                if d or n then return d, n end
            end
        end
    end
    if C_StableInfo.GetStablePetInfo then
        for slot = 1, 5 do
            local ok, info = pcall(C_StableInfo.GetStablePetInfo, slot)
            if ok then
                local d, n = match(info)
                if d or n then return d, n end
            end
        end
    end
end

local function ZoneText()
    local z = GetRealZoneText and GetRealZoneText() or GetZoneText()
    if issecret(z) then return nil end
    return z
end

-- Credit a beast we can identify by NPC id and/or display id.
function ns.CreditBeast(npc, displayId, name, family, level, source)
    local look = (displayId and ns.looks[displayId]) or (npc and ns.npcToLook[npc])
    if not look and displayId then
        -- unknown to the shipped data: learn it so it still counts
        local disc = ns.db.discovered
        disc[ns.flavor] = disc[ns.flavor] or {}
        if not disc[ns.flavor][displayId] then
            disc[ns.flavor][displayId] = { npc = npc, name = name, family = family, level = level, zone = ZoneText() }
            ns.BuildIndex()
            look = ns.looks[displayId]
            ns.Print(("Discovered a new look: |cff%s%s|r (added to your collection)"):format(ns.RARITY[2].hex, name or "?"))
        else
            look = ns.looks[displayId]
        end
    end
    if look and AddCollected(look, { npc = npc, name = name, auto = source }) then
        local r = ns.RARITY[look.rarity]
        ns.Print(("New look collected: |cff%s[%s]|r %s  |cffffd100+%d points|r"):format(r.hex, r.name, look.name, r.points))
        if PlaySound and SOUNDKIT and SOUNDKIT.UI_TRANSMOG_ITEM_CLICK then pcall(PlaySound, SOUNDKIT.UI_TRANSMOG_ITEM_CLICK) end
    end
    return look
end

local function FamilyIdByName(fname)
    if not fname or issecret(fname) then return nil end
    for id, f in pairs(ns.families) do
        if f.name == fname then return id end
    end
end

-- Inspect the player's current pet
-- small per-character log of what the scanner saw, for /hpc log
function ns.Log(text)
    local log = ns.cdb.log or {}
    ns.cdb.log = log
    table.insert(log, 1, date("%d %b %H:%M") .. "  " .. text)
    while #log > 30 do table.remove(log) end
end

-- /hpc petinfo: everything the game will tell an addon about the active
-- pet, to work out how to recognise it on a new game version.
function ns.PetInfoReport()
    local P = function(...) ns.Print(...) end
    local function show(v)
        if issecret(v) then return "<hidden>" end
        if type(v) == "table" then
            local parts = {}
            for k, x in pairs(v) do
                if type(x) ~= "table" and type(x) ~= "function" then parts[#parts + 1] = tostring(k) .. "=" .. tostring(x) end
            end
            table.sort(parts)
            return "{" .. table.concat(parts, ", ") .. "}"
        end
        return tostring(v)
    end
    P("|cffffd100Pet info|r (send a screenshot of this to the addon author)")
    P("Game " .. show(select(4, GetBuildInfo())) .. ", class " .. show(ns.playerClass) .. ", pet out: " .. show(UnitExists("pet")))
    if not UnitExists("pet") then return end
    P("GUID " .. show(ns.SafeGUID("pet")) .. "  name " .. show(UnitName("pet")) .. "  level " .. show(UnitLevel("pet"))
        .. "  family " .. show(UnitCreatureFamily and UnitCreatureFamily("pet")))
    local m = CreateFrame("PlayerModel", nil, UIParent)
    m:SetSize(64, 64); m:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0); m:SetAlpha(0.01); m:Show()
    pcall(m.SetUnit, m, "pet")
    local function readModel(when)
        local ok1, d = pcall(function() return m.GetDisplayInfo and m:GetDisplayInfo() end)
        local ok2, f = pcall(function() return m.GetModelFileID and m:GetModelFileID() end)
        P(when .. ": model display " .. show(ok1 and d or "error") .. ", model file " .. show(ok2 and f or "error"))
    end
    readModel("Model now")
    ns.After(2, function() readModel("Model after 2s"); m:Hide() end)
    local fns = {}
    for k, v in pairs(C_StableInfo or {}) do if type(v) == "function" then fns[#fns + 1] = k end end
    table.sort(fns)
    P("C_StableInfo: " .. (#fns > 0 and table.concat(fns, ", ") or "not available"))
    if C_StableInfo and C_StableInfo.GetActivePetList then
        local ok, list = pcall(C_StableInfo.GetActivePetList)
        P("Active pets: " .. (ok and type(list) == "table" and (show(list[1]) .. " (" .. #list .. " pets)") or show(list)))
    end
    if C_StableInfo and C_StableInfo.GetStablePetInfo then
        local ok, info = pcall(C_StableInfo.GetStablePetInfo, 1)
        P("Stable slot 1 (new): " .. show(ok and info or "error"))
    end
    if GetStablePetInfo then
        local ok, a, b, c, d, e = pcall(GetStablePetInfo, 1)
        P("Stable slot 1 (old): " .. (ok and (show(a) .. ", " .. show(b) .. ", " .. show(c) .. ", " .. show(d) .. ", " .. show(e)) or "error"))
    end
    P("Stable display function: " .. show(C_PlayerInfo and C_PlayerInfo.GetPetStableCreatureDisplayInfoID ~= nil))
    if GetPetExperience then P("Pet XP: " .. show(select(1, GetPetExperience())) .. " / " .. show(select(2, GetPetExperience()))) end
end

function ns.ScanActivePet(verbose, retried)
    local function why(msg)
        if verbose then ns.Print(msg) end
    end
    if ns.playerClass ~= "HUNTER" then return why("Only hunters collect pets.") end
    if not UnitExists("pet") then return why("You have no pet out. Summon it and try /hpc scan again.") end
    local guid = ns.SafeGUID("pet")
    -- must be a real tamed hunter pet: "Pet-" GUID with a beast family
    -- (rules out guardians, vehicles, mind-controlled or charmed units)
    if not guid then return why("The game didn't give the pet's ID. Try again out of combat.") end
    if guid:sub(1, 4) ~= "Pet-" then return why("Your current pet isn't a tamed hunter pet (" .. (strsplit("-", guid)) .. ").") end
    local fam = UnitCreatureFamily and UnitCreatureFamily("pet")
    if not fam or issecret(fam) then return why("The game didn't say what family your pet is.") end
    local npc = ns.NPCIDFromGUID(guid)
    if npc and GENERIC_PET_NPC[npc] then npc = nil end   -- shared ID for every tamed pet
    local display = DisplayIDForUnit("pet")
    if not display or not npc then
        local d2, n2 = ActivePetFromStable()
        display, npc = display or d2, npc or n2
    end
    -- just tamed: we know which wild beast it was
    if not display and not npc and ns.pendingTame and ns.pendingTame.npc and not GENERIC_PET_NPC[ns.pendingTame.npc] then
        npc = ns.pendingTame.npc
    end
    -- remembered from an earlier stable visit, scan or tame
    if not display and not npc then
        display, npc = RecallPet(UnitName("pet"), fam)
    end
    -- last resort: the model the Pet XP Bar is showing (only on the retry,
    -- once it has had time to switch to this pet)
    if not display and not npc and retried and ns.XP and ns.XP.PetModelDisplayID then
        display = GoodID(ns.XP.PetModelDisplayID())
    end
    if not npc and not display then
        -- the model may still be loading: try once more in a moment
        if not retried then
            ns.After(1.5, function() ns.ScanActivePet(verbose, true) end)
            return
        end
        ns.Log("Couldn't read the pet's model (" .. tostring(UnitName("pet")) .. ")")
        if not verbose and ns.cdb and not ns.cdb.stableHintShown then
            ns.cdb.stableHintShown = true
            ns.Print("Tip: visit a stable master once so the addon can see which beasts your pets are. It remembers them after that.")
        end
        return why("Couldn't identify your pet yet. Visit a stable master once: after that the addon remembers your pets.")
    end
    RememberPet(UnitName("pet"), fam, display, npc)
    local name = UnitName("pet")
    if issecret(name) then name = nil end
    local family = FamilyIdByName(UnitCreatureFamily and UnitCreatureFamily("pet"))
    -- Use the beast's original creature name where we know it
    local look = (display and ns.looks[display]) or (npc and ns.npcToLook[npc])
    local beastName = name
    if ns.pendingTame and ns.pendingTame.npc == npc then
        beastName = ns.pendingTame.name or beastName   -- the creature's real name, not the pet's
    end
    if look and npc then
        for _, s in ipairs(look.sources) do if s.npc == npc then beastName = s.name end end
    end
    ns.pendingTame = nil
    local before = look and ns.IsCollected(look)
    local got = ns.CreditBeast(npc, display, beastName, family, UnitLevel("pet"), "pet")
    local what = ("%s (%s, creature %s, model %s)"):format(beastName or "?", fam, tostring(npc or "?"), tostring(display or "?"))
    if got then
        if before then
            why("Your pet " .. what .. " is the look |cffffd100" .. got.name .. "|r, already collected.")
        elseif ns.IsCollected(got) then
            ns.Log("Collected " .. got.name .. " from " .. what)
        end
    else
        why("Your pet " .. what .. " didn't match any look.")
        ns.Log("No match for " .. what)
    end
end

function ns.ShowLog()
    local log = ns.cdb.log or {}
    if #log == 0 then return ns.Print("Nothing logged yet. Pets are logged when they're summoned, tamed or found in the stable.") end
    ns.Print("Recent pet scans (newest first):")
    for i = 1, math.min(10, #log) do print("   " .. log[i]) end
end

-- MoP Classic: the stable exposes each slot's creature display ID directly
-- (the same call Blizzard's stable window uses for its 3D preview).
-- Slots 1-5 are the Call Pet slots, 6-205 the stable pages.
local function StableFrameShown()
    return (PetStableFrame and PetStableFrame:IsShown()) or (StableFrame and StableFrame:IsShown()) or false
end

local function ScanStableMists()
    local getDisplay = C_PlayerInfo and C_PlayerInfo.GetPetStableCreatureDisplayInfoID
    if not (getDisplay and GetStablePetInfo) then return false end
    local found = 0
    local _, before = ns.GetScore()
    for slot = 1, 205 do
        local ok, _, petName, level, familyName = pcall(GetStablePetInfo, slot)
        if ok and petName then
            local ok2, disp = pcall(getDisplay, slot)
            if ok2 and type(disp) == "number" and disp > 0 and not issecret(disp) then
                found = found + 1
                local fam = FamilyIdByName(familyName)
                local known = ns.looks[disp]
                local wasNew = not (known and ns.IsCollected(known))
                local got = ns.CreditBeast(nil, disp, known and known.name or ((familyName or "Beast") .. " (stabled)"), fam, level, "stable")
                if got and wasNew and ns.IsCollected(got) then ns.Log("Collected " .. got.name .. " from the stable (" .. tostring(petName) .. ", model " .. disp .. ")") end
            end
        end
    end
    if found > 0 and StableFrameShown() then
        local _, after = ns.GetScore()
        ns.Print(("Checked %d stabled pet%s: %d new look%s collected."):format(found, found == 1 and "" or "s", after - before, after - before == 1 and "" or "s"))
    end
    return found > 0
end
ns.ScanStableMists = ScanStableMists


-- Stable scanning on clients exposing C_StableInfo (mainline-based clients)
function ns.ScanStable()
    if ScanStableMists() then return end
    if not (C_StableInfo and C_StableInfo.GetStablePetInfo) then return end
    for slot = 1, 205 do
        local ok, info = pcall(C_StableInfo.GetStablePetInfo, slot)
        if ok and type(info) == "table" then
            local disp = GoodID(info.displayID)
            local npc = GoodID(info.creatureID)
            if npc and GENERIC_PET_NPC[npc] then npc = nil end   -- shared ID, says nothing
            if disp or npc then
                RememberPet(info.name, info.familyName, disp, npc)
                ns.CreditBeast(npc, disp, info.name, FamilyIdByName(info.familyName), info.level, "stable")
            end
        end
    end
end

------------------------------------------------------------------------
-- Update safety: the first time a new version loads, copy every saved
-- collection aside before anything else runs. The last 3 snapshots are kept;
-- VerifyCollection restores from them if a looks ever goes missing.
------------------------------------------------------------------------
local function DeepCopy(t)
    if type(t) ~= "table" then return t end
    local r = {}
    for k, v in pairs(t) do r[k] = DeepCopy(v) end
    return r
end

function ns.SnapshotOnUpdate()
    local db = ns.db
    if db.lastVersion == ns.VERSION then return end
    db.snapshots = db.snapshots or {}
    if db.backup and next(db.backup) then
        table.insert(db.snapshots, 1, { from = db.lastVersion or "?", to = ns.VERSION, t = time(), backup = DeepCopy(db.backup) })
        while #db.snapshots > 3 do table.remove(db.snapshots) end
    end
    db.lastVersion = ns.VERSION
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
local TAME_BEAST = 1515
local f = CreateFrame("Frame")
ns.eventFrame = f
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")

f:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= ADDON then return end
        HunterPetCodexDB = HunterPetCodexDB or {}
        HunterPetCodexCharDB = HunterPetCodexCharDB or {}
        ApplyDefaults(HunterPetCodexDB, DB_DEFAULTS)
        ApplyDefaults(HunterPetCodexCharDB, CHAR_DEFAULTS)
        ns.db, ns.cdb = HunterPetCodexDB, HunterPetCodexCharDB
        ns.SnapshotOnUpdate()
        ns.BuildIndex()
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        local _, class = UnitClass("player")
        ns.playerClass = class
        ns.playerName = ns.NormalizeName(UnitName("player") .. "-" .. ((GetNormalizedRealmName and GetNormalizedRealmName()) or GetRealmName() or ""))
        ns.playerClassFile = class
        ns.playerGUID = ns.SafeGUID("player")
        ns.VerifyCollection()
        if class == "HUNTER" then
            self:RegisterEvent("UNIT_PET")
            self:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
            self:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
            self:RegisterEvent("PET_STABLE_SHOW")
            self:RegisterEvent("PET_STABLE_UPDATE")
            ns.After(4, ns.ScanActivePet)
            ns.After(6, function() pcall(ScanStableMists) end)   -- Call Pet slots, if the client allows it away from a stable
        end
        ns.Fire("READY")
    elseif event == "UNIT_PET" then
        if ... == "player" then ns.After(0.5, ns.ScanActivePet) end
    elseif event == "UNIT_SPELLCAST_START" then
        local _, _, spellID = ...
        if spellID == TAME_BEAST then
            local tname = UnitName("target")
            if issecret(tname) then tname = nil end
            ns.pendingTame = { npc = ns.NPCIDFromGUID(ns.SafeGUID("target")), name = tname }
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local _, _, spellID = ...
        if spellID == TAME_BEAST then ns.After(1.5, ns.ScanActivePet) end
    elseif event == "PET_STABLE_SHOW" or event == "PET_STABLE_UPDATE" then
        ns.After(0.2, ns.ScanStable)
    end
end)

-- Only ever ADD our own entry. Never reassign the StaticPopupDialogs global:
-- that taints every game popup, including the logout countdown, and the
-- game then blocks logging out.
StaticPopupDialogs.HPC_ADOPT_BACKUP = {
    text = "Hunter Pet Collector found a collection for %s (%d looks).\n\nIs this the same character after a realm transfer or rename? Bring the collection over?",
    button1 = YES or "Yes", button2 = NO or "No",
    OnAccept = function() if ns.pendingAdopt then ns.AdoptBackup(ns.pendingAdopt.key) end end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------
SLASH_HUNTERPETCODEX1 = "/petcodex"
SLASH_HUNTERPETCODEX2 = "/hpc"
SlashCmdList.HUNTERPETCODEX = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "board" or msg == "leaderboard" then
        ns.ToggleMain("board")
    elseif msg == "scan" then
        ns.ScanActivePet(true); ns.ScanStable()
    elseif msg == "restore" then
        local found = false
        for key, entry in pairs(ns.db.backup) do
            if key ~= ns.playerName and ShortName(key) == ShortName(ns.playerName) and entry[ns.flavor] and entry[ns.flavor].looks and next(entry[ns.flavor].looks) then
                found = true
                ns.Print("Backup found: " .. key .. "  -  type /hpc restore " .. key)
            end
        end
        if not found then ns.Print("No other backups found.") end
    elseif msg:match("^restore ") then
        local key = msg:match("^restore%s+(.+)$")
        for k in pairs(ns.db.backup) do if k:lower() == key then ns.AdoptBackup(k) end end
    elseif msg == "log" then
        ns.ShowLog()
    elseif msg == "options" or msg == "config" or msg == "settings" then
        ns.OpenOptions()
    elseif msg == "clear" or msg == "clearpins" then
        ns.ClearPins()
    elseif msg == "track" or msg == "stop" or msg == "untrack" then
        ns.StopTracking()
    elseif msg == "debug" then
        ns.commDebug = not ns.commDebug
        ns.Print("Sharing debug " .. (ns.commDebug and "on: every score message sent and received is printed." or "off."))
    elseif msg == "comm" or msg == "sync" then
        ns.CommReport()
    elseif msg == "export" or msg == "backup" then
        ns.ShowExport()
    elseif msg == "import" then
        ns.ShowImport()
    elseif msg == "logo" then
        ns.ToggleLogoTuner()
    elseif msg == "hunt" then
        ns.ToggleHunting()
    elseif msg == "next" then
        ns.SkipSpawn()
    elseif msg == "petinfo" then
        ns.PetInfoReport()
    elseif msg == "feed" then
        if not (ns.Feed and ns.Feed.Supported()) then
            ns.Print("Pets don't need feeding in this game version (or you're not on a hunter).")
        else
            local food = ns.Feed.BestFood()
            ns.Print(food and ("Click the Feed button to feed your pet " .. (GetItemInfo(food.id) or "food") .. ".")
                or "No food in your bags that your pet will eat.")
        end
    elseif msg == "xp" or msg == "xpbar" then
        if ns.XP and ns.XP.OpenOptions then ns.XP.OpenOptions() end
    elseif msg == "minimap" then
        ns.db.minimap.hide = not ns.db.minimap.hide
        ns.UpdateMinimapButton()
    elseif msg == "tooltip" then
        ns.db.tooltip = not ns.db.tooltip
        ns.Print("Tooltip info " .. (ns.db.tooltip and "on" or "off"))
    elseif msg == "share" then
        ns.db.shareScore = not ns.db.shareScore
        ns.Print("Score sharing " .. (ns.db.shareScore and "on" or "off"))
    elseif msg == "help" then
        ns.Print("/hpc - open the collection  |  /hpc board - leaderboard  |  /hpc scan - rescan your pet")
        ns.Print("/hpc options - settings  |  /hpc clear - remove all map pins")
        ns.Print("/hpc hunt - show and track every uncollected look  |  /hpc next - skip to the next spawn  |  /hpc stop - stop tracking")
        ns.Print("/hpc scan - check your current pet  |  /hpc log - what the addon has collected recently")
        ns.Print("/hpc export - backup code for your collection  |  /hpc import - restore from a code")
        ns.Print("/hpc minimap | tooltip | share - toggle options")
        ns.Print("/hpc xp - Pet XP Bar options (also /petxp)")
        ns.Print("/hpc feed - what the Feed button will feed your pet")
    else
        ns.ToggleMain()
    end
end
