-- Hunter Pet Collector - Leaderboard sync
-- Addons can't reach the internet, so scores spread player-to-player:
-- guild, party/raid and a hidden realm-wide addon channel. Each client also
-- relays the best scores it knows about, so the board grows beyond the
-- people you've personally met.
local ADDON, ns = ...

local PREFIX = "HPCodex1"
local CHANNEL = "HPCodexBoard"
local PROTO = "1"
local MAX_RELAY = 8               -- entries per relay message
local SHARE_EVERY = 1200          -- your score goes out every 20 minutes
local ENTRY_TTL = 60 * 60 * 24 * 45 -- forget players not seen for 45 days

local C = C_ChatInfo or {}
local SendAddon = C.SendAddonMessage or SendAddonMessage
local RegisterPrefix = C.RegisterAddonMessagePrefix or RegisterAddonMessagePrefix

------------------------------------------------------------------------
-- Board storage
------------------------------------------------------------------------
function ns.Board()
    local b = ns.db.board
    b[ns.flavor] = b[ns.flavor] or {}
    return b[ns.flavor]
end

local function now() return GetServerTime and GetServerTime() or time() end

function ns.CanShareScore()
    return ns.db.shareScore and ns.playerClass == "HUNTER" and not ns.tampered
end

-- How a hunter is identified on the board. Normally "Name-Realm". On WoW:
-- Forever's mega-server the game spells realms differently depending on
-- who's looking, so the same hunter could show up twice: there the
-- character name alone is used. e.name keeps the full name for whispers.
function ns.BoardKey(name)
    if not name then return nil end
    if ns.flavor == "forever" then return (strsplit("-", name)) end
    return ns.NormalizeName(name)
end
-- On Forever other players' games can show us under a different name than
-- our own game does (e.g. "Ashie" to us, "Ashie Archer" to everyone else).
-- We learn those names from our own messages echoing back (see OnMessage).
local function Aliases()
    if not ns.cdb then return {} end
    ns.cdb.aliases = ns.cdb.aliases or {}
    return ns.cdb.aliases
end
function ns.IsMe(name)
    if name == nil or ns.playerName == nil then return false end
    local key = ns.BoardKey(name)
    return key == ns.BoardKey(ns.playerName) or Aliases()[key] == true
end
function ns.BoardEntry(name) return ns.Board()[ns.BoardKey(name)] end

-- entry = { name, class, points, count, total, ts, direct=bool, guild=bool }
local function Upsert(e)
    if not e.name or not e.points or e.points < 0 then return end
    if not ns.IsLocalPlayer(e.name) then return end   -- this server only
    if ns.totalPoints and ns.totalPoints > 0 and e.points > ns.totalPoints * 1.1 + 500 then return end -- implausible
    local board, key = ns.Board(), ns.BoardKey(e.name)
    local old = board[key]
    if old and (old.ts or 0) > (e.ts or 0) then
        -- keep newer data, but remember a direct sighting
        if e.direct then old.direct = true; old.name = e.name end
        if e.guild then old.guild = true end
        if e.reply then old.reply = e.reply end
        return
    end
    if old then
        -- a name heard straight from the player is the one whispers work with
        if not e.direct and old.direct then e.name = old.name end
        e.reply = e.reply or old.reply
        e.direct = e.direct or old.direct
        e.guild = e.guild or old.guild
        e.class = e.class or old.class
    end
    board[key] = e
    ns.Fire("BOARD_CHANGED")
end

function ns.PruneBoard()
    local cutoff = now() - ENTRY_TTL
    for k, e in pairs(ns.Board()) do
        if (e.ts or 0) < cutoff then ns.Board()[k] = nil end
    end
end

function ns.SortedBoard(filter)
    local list = {}
    for _, e in pairs(ns.Board()) do
        if filter ~= "guild" or e.guild or ns.IsMe(e.name) then
            list[#list + 1] = e
        end
    end
    table.sort(list, function(a, b)
        if a.points ~= b.points then return a.points > b.points end
        return a.name < b.name
    end)
    return list
end

------------------------------------------------------------------------
-- Outgoing queue (throttled; never sends in restricted contexts)
------------------------------------------------------------------------
local queue, sending = {}, false
-- Whisper bookkeeping, keyed by AddrKey(target): when we last whispered an
-- address and what we sent, so a "No player named" reply can be hidden and
-- the message resent to the player's next possible address.
local recentWhisper, lastMsgTo, shortToFull = {}, {}, {}
local function AddrKey(name) return ((name or ""):lower():gsub("[^%w]", "")) end
ns.AddrKey = AddrKey

local function ChannelNumber()
    local id = GetChannelName(CHANNEL)
    if id and id > 0 then return id end
end

local function CanSend()
    if C.InChatMessagingLockdown then
        local ok, locked = pcall(C.InChatMessagingLockdown)
        if ok and locked then return false end
    end
    return true
end

-- counters for /hpc comm
ns.commStats = { sent = {}, recv = {}, fail = {}, lastResult = {} }
local stats = ns.commStats
local function Count(t, k) t[k] = (t[k] or 0) + 1 end

-- Some game versions refuse addon messages on custom chat channels
-- (result 4, "invalid chat type"). Remember that for this game build so we
-- stop trying; a new game patch gets one fresh try.
local function GameBuild() return GetBuildInfo and select(2, GetBuildInfo()) or "?" end
function ns.ChannelUnsupported()
    return ns.db and ns.db.channelUnsupported == GameBuild()
end

local function ResultName(res)
    local e = Enum and Enum.SendAddonMessageResult
    if e and type(res) == "number" then
        for k, v in pairs(e) do if v == res then return k end end
    end
    return tostring(res)
end

local function IsInvalidChatType(res)
    local e = Enum and Enum.SendAddonMessageResult
    if e and e.InvalidChatType then return res == e.InvalidChatType end
    return res == 4
end

local function SendOne(item)
    local target = item.target
    if item.dist == "CHANNEL" then target = ChannelNumber() end
    if item.dist == "CHANNEL" and not target then Count(stats.fail, "CHANNEL"); return end
    if item.dist == "WHISPER" and target then
        recentWhisper[AddrKey(target)] = GetTime()
        lastMsgTo[AddrKey(target)] = item.msg
        -- the game sometimes leaves the realm out of its "No player named" reply
        shortToFull[AddrKey((strsplit("-", target)))] = AddrKey(target)
    end
    local ok, res = pcall(SendAddon, PREFIX, item.msg, item.dist, target)
    if ns.commDebug then ns.Print(("|cff80c0ffsent|r %s%s: %s  -> %s"):format(item.dist, target and (" " .. tostring(target)) or "", item.msg, ok and tostring(res) or ("error " .. tostring(res)))) end
    -- newer clients return a result code (0 = success), older ones true/nil
    local good = ok and (res == nil or res == true or res == 0)
    stats.lastResult[item.dist] = ok and ResultName(res) or ("error: " .. tostring(res))
    if item.dist == "CHANNEL" and ok and IsInvalidChatType(res) and not ns.ChannelUnsupported() then
        ns.db.channelUnsupported = GameBuild()
        ns.channelState = "not supported by this game version"
        if ns.commDebug then ns.Print("This game version doesn't allow addon messages on chat channels. Using guild, group, friends and direct sharing instead.") end
    end
    if good then Count(stats.sent, item.dist) else Count(stats.fail, item.dist) end
end

local function Pump()
    if #queue == 0 then sending = false return end
    sending = true
    if CanSend() then SendOne(table.remove(queue, 1)) end
    ns.After(1.2, Pump)
end

local function Enqueue(msg, dist, target)
    for _, q in ipairs(queue) do
        if q.msg == msg and q.dist == dist and q.target == target then return end
    end
    if #queue > 60 then table.remove(queue, 1) end
    queue[#queue + 1] = { msg = msg, dist = dist, target = target }
    if not sending then Pump() end
end

------------------------------------------------------------------------
-- Server only: scores from other realms are ignored, so the board is
-- purely your server (and its connected realms). Each game version keeps
-- its own board. WoW: Forever is one mega-server, so there everyone
-- playing Forever counts (still no Battle.net).
------------------------------------------------------------------------
local localRealms
local function LocalRealms()
    if localRealms then return localRealms end
    localRealms = {}
    local mine = GetNormalizedRealmName and GetNormalizedRealmName() or (GetRealmName and GetRealmName())
    if not mine then localRealms = nil; return {} end   -- not known yet, try again later
    localRealms[(mine:gsub("[%s%-']", ""))] = true
    if GetAutoCompleteRealms then
        for _, r in ipairs(GetAutoCompleteRealms() or {}) do localRealms[(r:gsub("[%s%-']", ""))] = true end
    end
    return localRealms
end

function ns.IsMegaServer() return ns.flavor == "forever" end

function ns.IsLocalPlayer(name)
    if not name then return false end
    if ns.IsMegaServer() then return true end
    local _, realm = strsplit("-", ns.NormalizeName(name), 2)
    if not realm or realm == "" then return true end
    local realms = LocalRealms()
    if not next(realms) then return true end
    return realms[realm] or false
end

-- character friends on this server get your score by addon whisper
local function FriendTargets()
    local whispers = {}
    if C_FriendList and C_FriendList.GetNumFriends then
        for i = 1, C_FriendList.GetNumFriends() or 0 do
            local ok, info = pcall(C_FriendList.GetFriendInfoByIndex, i)
            if ok and info and info.connected and info.name and ns.IsLocalPlayer(info.name) then
                whispers[#whispers + 1] = info.name
            end
        end
    end
    return whispers
end

------------------------------------------------------------------------
-- Known collectors: anyone who has ever sent you their own score (in a
-- group, guild, as a friend...) gets your score by hidden addon whisper from
-- then on, even when you're not grouped. This works whatever happens to the
-- server channel. Only used for players we haven't heard on the channel,
-- guild or group in the last 15 minutes. At most one every 4 minutes. Offline
-- players are left alone and the game's "No player named ..." message
-- is hidden.
------------------------------------------------------------------------
local lastWhisper, offline, heardShared, heardAny = {}, {}, {}, {}
local SHARED_FRESH = 900   -- heard through channel/guild/group in the last 15 min
local ONLINE_FRESH = 2700  -- heard from them at all in the last 45 min: still online
local WHISPER_GAP, MAX_KNOWN = 1200, 15   -- routine score whispers: every 20 min

local function Short(name) return (strsplit("-", name or "")) end

local function KnownCollectors()
    local list, cutoff = {}, now() - 14 * 86400
    for _, e in pairs(ns.Board()) do
        if e.direct and e.name and not ns.IsMe(e.name) and (e.ts or 0) > cutoff and ns.IsLocalPlayer(e.name) then
            list[#list + 1] = e
        end
    end
    table.sort(list, function(a, b) return (a.ts or 0) > (b.ts or 0) end)
    return list
end

-- When the game says someone isn't online, leave them alone for a while:
-- 10 minutes, then 20, 40, and at most once an hour. Hearing anything from
-- them (they logged back in) clears it straight away.
local function MarkOffline(name)
    local o = offline[Short(name)] or { step = 0 }
    o.step = math.min(o.step + 1, 4)
    o.retry = now() + math.min(300 * 2 ^ o.step, 3600)
    offline[Short(name)] = o
end

local function MarkOnline(name)
    offline[Short(name)] = nil
end

-- True when this player already reaches us without whispers: we've heard
-- them on the server channel, guild or group lately, or they're in our
-- group right now. Then the channel/guild/group carries our score to them
-- too and a whisper would just be a duplicate.
local function ReachedWithoutWhisper(name)
    local h = heardShared[Short(name)]
    if h and now() - h < SHARED_FRESH then return true end
    local short = Short(name)
    if (UnitInParty and UnitInParty(short)) or (UnitInRaid and UnitInRaid(short)) then return true end
    return false
end
ns.ReachedWithoutWhisper = ReachedWithoutWhisper

-- Whisper rules, so nobody gets spammed however big the board gets:
--  * at most 15 players per round (friends included), the most recently
--    active ones first, sent 1.2 s apart
--  * routine updates: at most once every 20 minutes per player, and only to
--    players heard from in the last 45 minutes (so they're online)
--  * a "probe" (your login, or pressing Ask for scores) also tries the
--    others once; offline ones are then left alone for a while
--  * players we already reach through guild or group get no whispers
local function HeardRecently(name)
    local h = heardAny[Short(name)]
    return h and now() - h < ONLINE_FRESH
end

-- Where to whisper a player. Each player has a short list of possible
-- addresses, tried in order; one the game says doesn't exist is marked bad
-- and skipped, and the message is resent to the next. Hearing from the
-- player again clears the marks (the error may only have meant they were
-- offline). On WoW: Forever there's just one: their full name, no realm.
local badAddr, addrInfo = {}, {}
local function Candidates(display, real)
    local list, seen = {}, {}
    local function add(n)
        if n and n ~= "" and not seen[AddrKey(n)] then seen[AddrKey(n)] = true; list[#list + 1] = n end
    end
    local dShort = strsplit("-", display or "", 2)
    if ns.IsMegaServer() then
        -- WoW: Forever: everyone is "Name Surname" on one big server; realms
        -- are hidden layers, so the full name with no realm is the only
        -- address that works (confirmed in game). If it fails, they're offline.
        add(dShort ~= "" and dShort or nil)
        if #list == 0 then add(real and (strsplit("-", real))) end
        return list
    end
    add(display)
    add(real)
    return list
end
ns.WhisperCandidates = Candidates

-- first address not known to fail, or nil when they've all failed
local function Resolve(display, real)
    for _, n in ipairs(Candidates(display, real)) do
        if not badAddr[AddrKey(n)] then
            addrInfo[AddrKey(n)] = { display = display, real = real }
            return n
        end
    end
end
ns.ResolveWhisper = Resolve

local function ClearBad(display, real)
    for _, n in ipairs(Candidates(display, real)) do badAddr[AddrKey(n)] = nil end
end

local function Whisper(msg, name, force, probe)
    local t = now()
    local o = offline[Short(name)]
    if o and t < o.retry then return end
    if ReachedWithoutWhisper(name) then return end
    if not probe and not HeardRecently(name) then return end
    if not force and lastWhisper[name] and t - lastWhisper[name] < WHISPER_GAP then return end
    lastWhisper[name] = t
    Enqueue(msg, "WHISPER", name)
end

local function SendToFriends(msg, force, probe)
    local targets, seen = {}, {}
    local function add(name)
        if name and not seen[name] and not ns.IsMe(name) then
            seen[name] = true
            targets[#targets + 1] = name
        end
    end
    for _, e in ipairs(KnownCollectors()) do add(Resolve(e.name, e.reply)) end   -- newest first
    if ns.db.shareWithFriends then
        for _, name in ipairs(FriendTargets()) do add(ns.NormalizeName(name)) end
    end
    local n = 0
    for _, name in ipairs(targets) do
        if n >= MAX_KNOWN then break end
        local o = offline[Short(name)]
        local eligible = not (o and now() < o.retry) and not ReachedWithoutWhisper(name)
            and (probe or HeardRecently(name))
            and (force or not lastWhisper[name] or now() - lastWhisper[name] >= WHISPER_GAP)
        if eligible then
            n = n + 1
            Whisper(msg, name, force, probe)
        end
    end
end

-- Hide "No player named 'X' is currently playing." for our own hidden
-- whispers, and remember that X is offline.
local function NotFoundPattern(fmt)
    local a, b = (fmt or ""):match("^(.-)%%s(.*)$")
    if not a then return nil end
    local function esc(x) return (x:gsub("%p", "%%%0")) end
    return "^" .. esc(a) .. "(.+)" .. esc(b) .. "$"
end
ns.NotFoundPattern = NotFoundPattern

-- The game's "No player named 'X' is currently playing." for a player we
-- whispered in the last 15 seconds: hide it and treat them as offline.
-- (the game may print "Name-Realm" as "Name Realm", so names are compared
-- with spaces and punctuation removed)
local function RecentlyWhispered(text)
    if type(text) ~= "string" then return end
    local pattern = NotFoundPattern(ERR_CHAT_PLAYER_NOT_FOUND_S)
    if pattern then
        local who = text:match(pattern)
        if not who then return end
        local key = AddrKey(who)
        if not recentWhisper[key] and shortToFull[key] then key = shortToFull[key] end
        local t = recentWhisper[key]
        if t and GetTime() - t < 15 then return key, who end
        return
    end
    -- no usable game string: look for a recent address anywhere in the line
    local flat = AddrKey(text)
    for key, t in pairs(recentWhisper) do
        if GetTime() - t < 15 and key ~= "" and flat:find(key, 1, true) then return key, key end
    end
end

-- The game runs this once per chat tab that shows system messages, so a
-- message hidden in one tab is remembered for a moment and hidden in the
-- others too (the retry and offline marks only happen the first time).
local hiddenAt = {}
function ns.CommSystemFilter(_, _, text)
    if type(text) == "string" and hiddenAt[text] and GetTime() - hiddenAt[text] < 3 then return true end
    local key, who = RecentlyWhispered(text)
    if not key then return false end
    hiddenAt[text] = GetTime()
    badAddr[key] = true
    recentWhisper[key] = nil
    local info, msg = addrInfo[key], lastMsgTo[key]
    local nextAddr = info and Resolve(info.display, info.real)
    if nextAddr and msg then
        -- that address doesn't exist: try the player's next one
        Enqueue(msg, "WHISPER", nextAddr)
        if ns.commDebug then ns.Print("|cff808080no player at " .. tostring(who) .. ", trying " .. nextAddr .. "|r") end
    else
        if info then
            if info.display then MarkOffline(info.display) end
            if info.real then MarkOffline(info.real) end
        else
            MarkOffline(who)
        end
        if ns.commDebug then ns.Print("|cff808080hid the offline notice for " .. tostring(who) .. "|r") end
    end
    return true
end
if ChatFrame_AddMessageEventFilter then
    ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", ns.CommSystemFilter)
end

-- True when everyone else in our group is also in our guild, so a guild
-- message already reaches them.
local function GroupAllGuild()
    if not (IsInGuild() and UnitIsInMyGuild and GetNumGroupMembers) then return false end
    local raid = IsInRaid and IsInRaid()
    for i = 1, GetNumGroupMembers() do
        local unit = raid and ("raid" .. i) or ("party" .. i)
        if UnitExists(unit) and not (UnitIsUnit and UnitIsUnit(unit, "player")) and not UnitIsInMyGuild(unit) then return false end
    end
    return true
end

-- Where a hidden score message goes: your guild, plus your group unless
-- everyone in it is a guildmate (so nobody gets it twice).
-- Hidden addon messages are never sent on the server channel: MoP Classic
-- refuses them, and WoW: Forever accepts them but never delivers them. The
-- channel is only used for the visible "Ask for scores" chat line.
-- extra: also answer the way someone asked (e.g. a raid or instance group).
local function Distributions(extra)
    local d = {}
    local function add(x) for _, v in ipairs(d) do if v == x then return end end d[#d + 1] = x end
    if IsInGuild() then add("GUILD") end
    if IsInRaid and IsInRaid() then
        if IsInRaid(LE_PARTY_CATEGORY_INSTANCE) then add("INSTANCE_CHAT") elseif not GroupAllGuild() then add("RAID") end
    elseif IsInGroup and IsInGroup() then
        if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then add("INSTANCE_CHAT") elseif not GroupAllGuild() then add("PARTY") end
    end
    if extra and extra ~= "WHISPER" and extra ~= "CHANNEL" then add(extra) end
    return d
end

------------------------------------------------------------------------
-- Messages
--   S;proto;name;class;points;count;total;ts           my own score
--   R;proto;name,class,points,count,ts;...             relayed scores
--   Q;proto                                            please send scores
------------------------------------------------------------------------
local function MyEntry()
    local points, count, total = ns.GetScore()
    return { name = ns.playerName, class = ns.playerClassFile, points = points, count = count, total = total,
        ts = now(), direct = true, guild = IsInGuild() }
end

function ns.UpdateSelfOnBoard()
    if ns.playerClass ~= "HUNTER" or ns.tampered then return end
    Upsert(MyEntry())
end

local lastBroadcast = 0
-- name: how the game shows them; real: their own name for themselves
function ns.BroadcastScoreTo(name, real)
    if not ns.CanShareScore() then return end
    local target = Resolve(name, real)
    if not target then return end
    local e = MyEntry()
    lastWhisper[name] = now()
    lastWhisper[target] = now()
    Enqueue(table.concat({ "S", PROTO, e.name, e.class or "", e.points, e.count, e.total, e.ts }, ";"), "WHISPER", target)
end

-- probe: also whisper your score right now to every known collector (your
-- login and the Ask for scores button). Otherwise whispers go out at most
-- every 20 minutes, to players heard from recently.
local lastProbe = 0
function ns.ResetCommThrottles() lastProbe = 0; lastBroadcast = 0; ns.ResetRelay() end   -- tests only
function ns.BroadcastScore(force, probe, extraDist)
    if probe then
        if now() - lastProbe < 60 then probe = nil else lastProbe = now() end   -- at most once a minute
    end
    if not ns.db.shareScore or ns.playerClass ~= "HUNTER" or ns.tampered then return end
    if not force and now() - lastBroadcast < 20 then return end
    lastBroadcast = now()
    local e = MyEntry()
    Upsert(e)
    ns.sentTs = ns.sentTs or {}
    ns.sentTs[e.ts] = true   -- to recognise our own messages when they echo back
    local msg = table.concat({ "S", PROTO, e.name, e.class or "", e.points, e.count, e.total, e.ts }, ";")
    for _, dist in ipairs(Distributions(extraDist)) do Enqueue(msg, dist) end
    SendToFriends(msg, probe, probe)
end

local lastRelay = 0
function ns.ResetRelay() lastRelay = 0 end   -- tests only
-- Pass on the top scores we heard straight from the players (never ones we
-- were only told about, so relays don't bounce around), at most every 10
-- minutes, and only scores updated in the last day.
function ns.RelayTop()
    if not ns.db.shareScore then return end
    if now() - lastRelay < 600 then return end
    lastRelay = now()
    local parts, n = { "R", PROTO }, 0
    for _, e in ipairs(ns.SortedBoard()) do
        if n >= MAX_RELAY then break end
        if e.direct and (e.ts or 0) > now() - 86400 and not ns.IsMe(e.name) then
            n = n + 1
            parts[#parts + 1] = table.concat({ e.name, e.class or "", e.points, e.count or 0, e.ts or 0 }, ",")
        end
    end
    if #parts <= 2 then return end
    local msg = table.concat(parts, ";")
    if #msg > 250 then msg = msg:sub(1, 250):gsub(";[^;]*$", "") end
    for _, dist in ipairs(Distributions()) do Enqueue(msg, dist) end
end

local lastRequest = 0
-- probe: also ask known collectors we haven't heard from lately (login and
-- the Ask for scores button only)
function ns.RequestScores(quiet, probe)
    if quiet and now() - lastRequest < 60 then return end
    lastRequest = now()
    local q = "Q;" .. PROTO .. ";" .. (ns.playerName or "")   -- our real name, for replies
    for _, dist in ipairs(Distributions()) do Enqueue(q, dist) end
    -- Known collectors normally get no separate request: the score whisper
    -- that goes with it (BroadcastScore with probe) gets their reply. If we
    -- can't send a score (not a hunter, sharing off), ask them directly.
    if probe and not ns.CanShareScore() then SendToFriends(q, true, true) end
end

local lastAnswer = 0
stats.rejected = {}
local function Reject(why, sender, msg)
    Count(stats.rejected, why)
    if ns.commDebug then ns.Print(("|cffff8080ignored|r from %s (%s): %s"):format(tostring(sender), why, tostring(msg))) end
end

-- On Forever a player can arrive under two names: the one everyone's game
-- shows (the sender, e.g. "Ashie Archer-Realm6") and their real character
-- name, which is what whispers must go to (e.g. "Ashie-Realm2"). Messages
-- carry the real name; note both as online.
local function NoteHeard(real, shared)
    if not real then return end
    MarkOnline(real)
    heardAny[Short(real)] = now()
    if shared then heardShared[Short(real)] = now() end
end

local function OnMessage(msg, dist, sender)
    if issecretvalue and (issecretvalue(msg) or issecretvalue(sender)) then return end
    Count(stats.recv, dist or "?")
    sender = ns.NormalizeName(sender)
    MarkOnline(sender)
    heardAny[Short(sender)] = now()
    if dist == "CHANNEL" or dist == "GUILD" or dist == "PARTY" or dist == "RAID" or dist == "INSTANCE_CHAT" then
        heardShared[Short(sender)] = now()
    end
    if ns.commDebug then ns.Print(("|cff80ff80got|r %s from %s: %s"):format(tostring(dist), sender, msg)) end
    local kind, proto, rest = strsplit(";", msg, 3)
    if proto ~= PROTO then return end

    if kind == "S" and rest then
        local name, class, points, count, total, ts = strsplit(";", rest)
        points, count, total, ts = tonumber(points), tonumber(count), tonumber(total), tonumber(ts)
        if not points then return Reject("bad score", sender, msg) end
        name = ns.NormalizeName(name)
        local real = name   -- the player's own name for themselves: whispers go here
        if ns.IsMegaServer() then
            -- Forever: a player's game may name them differently from how
            -- everyone else sees them. The sender name comes from the game
            -- and can't be faked, so that's who the score belongs to.
            if dist ~= "WHISPER" and ns.BoardKey(name) == ns.BoardKey(ns.playerName) and ts and ns.sentTs and ns.sentTs[ts]
                and points == select(1, ns.GetScore()) then
                -- our own message coming back: this is how others see us
                local key = ns.BoardKey(sender)
                if key ~= ns.BoardKey(ns.playerName) and not Aliases()[key] then
                    Aliases()[key] = true
                    ns.Board()[key] = nil
                    ns.Fire("BOARD_CHANGED")
                end
                return
            end
            name = sender
        elseif ns.BoardKey(name) ~= ns.BoardKey(sender) then
            return Reject("name doesn't match sender", sender, msg) -- only trust a player's own score directly
        end
        if ns.IsMe(name) then return end
        if not ns.IsLocalPlayer(name) then return Reject("other realm", sender, msg) end
        NoteHeard(real, dist ~= "WHISPER")
        ClearBad(sender, real)
        Upsert({ name = name, class = class ~= "" and class or nil, points = points, count = count, total = total,
            ts = math.min(ts or now(), now()), direct = true, guild = (dist == "GUILD") or nil, reply = real })
        -- someone whispered us their score (they just logged in or pressed
        -- Ask): send ours back once, unless we sent it to them recently
        if dist == "WHISPER" and ns.db.shareScore and ns.playerClass == "HUNTER" and not ns.tampered
            and (not lastWhisper[sender] or now() - lastWhisper[sender] >= WHISPER_GAP) then
            ns.BroadcastScoreTo(sender, real)
        end
    elseif kind == "R" and rest then
        for _, chunk in ipairs({ strsplit(";", rest) }) do
            local name, class, points, count, ts = strsplit(",", chunk)
            points, count, ts = tonumber(points), tonumber(count), tonumber(ts)
            name = name and ns.NormalizeName(name)
            if name and points and not ns.IsMe(name) then
                Upsert({ name = name, class = class ~= "" and class or nil, points = points, count = count,
                    ts = math.min(ts or 0, now()), direct = false })
            end
        end
    elseif kind == "Q" then
        local asker = rest and rest ~= "" and ns.NormalizeName((strsplit(";", rest))) or sender
        -- our own ask echoing back through the guild or group: don't answer it
        if ns.IsMe(sender) or ns.IsMe(asker) then return end
        NoteHeard(asker, dist ~= "WHISPER")
        ClearBad(sender, asker)
        if dist == "WHISPER" and ns.IsLocalPlayer(sender) then
            ns.BroadcastScoreTo(sender, asker)
            return
        end
        if now() - lastAnswer > 60 then
            lastAnswer = now()
            ns.After(1 + math.random() * 4, function()
                ns.BroadcastScore(true, nil, dist)   -- also answer the way they asked
                ns.After(3, ns.RelayTop)
            end)
        end
    end
end

------------------------------------------------------------------------
-- Wiring
------------------------------------------------------------------------
ns.channelState = "not joined yet"
-- Joining: JoinTemporaryChannel works for addons on most clients (it's what
-- joined your friend automatically). The other join calls are Blizzard-only
-- and caused the "blocked from an action" popup, so they're never used.
-- One attempt per login. If the game ever blocks it, the addon remembers that
-- and never tries again on that account; you'd type /join HPCodexBoard instead.
local hidden, triedThisSession = false, false
local function TryAutoJoin()
    if triedThisSession or ns.db.channelJoinBlocked or not JoinTemporaryChannel then return end
    if InCombatLockdown and InCombatLockdown() then return end
    triedThisSession = true
    ns.joiningChannel = true
    pcall(JoinTemporaryChannel, CHANNEL)
    ns.After(3, function() ns.joiningChannel = nil end)
end

local function JoinChannel()
    if not ns.db.useChannel then ns.channelState = "off in options"; return end
    if not ChannelNumber() then TryAutoJoin() end
    local n = ChannelNumber()
    if n then
        ns.channelState = "joined (#" .. n .. ") - used when you press Ask for scores"
        -- keep it out of chat windows; only hidden addon messages use it
        if not hidden and ChatFrame_RemoveChannel then
            hidden = true
            for i = 1, (NUM_CHAT_WINDOWS or 10) do
                local cf = _G["ChatFrame" .. i]
                if cf then pcall(ChatFrame_RemoveChannel, cf, CHANNEL) end
            end
        end
    else
        ns.channelState = ns.db.channelJoinBlocked and ("not joined - type /join " .. CHANNEL .. " once") or "joining..."
    end
end
ns.CheckChannel = JoinChannel
ns.CHANNEL = CHANNEL

------------------------------------------------------------------------
-- Server-wide "who has the addon?" through ordinary chat.
-- The game refuses hidden addon messages on chat channels, but an addon may
-- post a normal chat line there when the player clicks a button. Pressing
-- Ask for scores posts one short coded line (our score) in HPCodexBoard.
-- Every addon user is in that channel: they add us to their board and
-- whisper their score back with a hidden addon whisper. The line is hidden
-- from chat for addon users; the channel isn't on any chat tab anyway.
------------------------------------------------------------------------
local CHAT_TAG = "HPC1:"
local lastServerAsk = 0
stats.serverAsk, stats.serverHeard = 0, 0

local function IsOurChannel(channelName, baseName)
    local want = CHANNEL:lower()
    if type(baseName) == "string" and baseName:lower() == want then return true end
    return type(channelName) == "string" and channelName:lower():find(want, 1, true) ~= nil
end

-- Must be called straight from a click or typed command: the game only lets
-- addons post in chat channels then, never from a timer.
--   auto = true: opening the addon's window. Posts at most every 20 minutes.
--   otherwise: the Ask for scores button, at most once a minute.
local lastAutoAsk = 0
local AUTO_ASK_EVERY = 1200
function ns.AskServer(auto)
    if not ns.db.useChannel then return end
    if now() - lastServerAsk < 60 then return end
    if auto and now() - lastAutoAsk < AUTO_ASK_EVERY then return end
    if ns.db.serverAskBlocked == GameBuild() then return end   -- the game refused it on this version
    if auto and ns.db.serverAutoBlocked == GameBuild() then return end
    local n = ChannelNumber()
    if not n or not SendChatMessage then return end
    if not CanSend() then return end
    lastServerAsk = now()
    local line
    if ns.CanShareScore() then
        local points, count, total = ns.GetScore()
        line = table.concat({ CHAT_TAG .. "S", ns.playerClassFile or "", points, count, total, ns.playerName or "" }, ":")
    else
        line = CHAT_TAG .. "Q:" .. (ns.playerName or "")   -- not on a hunter: just ask for scores
    end
    if auto then lastAutoAsk = now() end
    ns.autoPosting = auto and true or nil
    local ok, err = pcall(SendChatMessage, line, "CHANNEL", nil, n)
    ns.autoPosting = nil
    stats.serverAsk = stats.serverAsk + 1
    if ns.commDebug then ns.Print(("|cff80c0ffposted|r in %s: %s  -> %s"):format(CHANNEL, line, ok and "ok" or ("error " .. tostring(err)))) end
end
function ns.ResetServerAsk() lastServerAsk = 0; lastAutoAsk = 0 end   -- tests only

local function OnServerLine(text, sender, guid)
    if type(text) ~= "string" or text:sub(1, #CHAT_TAG) ~= CHAT_TAG then return end
    sender = ns.NormalizeName(sender)
    if not sender or ns.IsMe(sender) then return end
    -- our own line coming back. On Forever the game may show us to others
    -- under a different name, so check the sender's ID and remember that name.
    if type(guid) == "string" and not (issecretvalue and issecretvalue(guid)) and guid == UnitGUID("player") then
        local key = ns.BoardKey(sender)
        if not Aliases()[key] then
            Aliases()[key] = true
            ns.Board()[key] = nil
            ns.Fire("BOARD_CHANGED")
        end
        return
    end
    if ns.commDebug then ns.Print(("|cff80ff80heard|r in %s from %s: %s"):format(CHANNEL, sender, text)) end
    if not ns.IsLocalPlayer(sender) then return Reject("other realm", sender, text) end
    local kind, class, points, count, total, realS = strsplit(":", text:sub(#CHAT_TAG + 1))
    points, count, total = tonumber(points), tonumber(count), tonumber(total)
    -- the poster's real name (whispers go there); older versions don't send it
    local real = (kind == "Q" and class) or (kind == "S" and realS) or nil
    real = (real and real ~= "") and ns.NormalizeName(real) or sender
    if kind == "Q" then class = nil end
    if kind == "S" and not points then return Reject("bad server line", sender, text) end
    if kind ~= "S" and kind ~= "Q" then return Reject("bad server line", sender, text) end
    stats.serverHeard = stats.serverHeard + 1
    MarkOnline(sender)
    heardAny[Short(sender)] = now()
    NoteHeard(real)
    ClearBad(sender, real)
    if kind == "S" then
        Upsert({ name = sender, class = class ~= "" and class or nil, points = points, count = count, total = total,
            ts = now(), direct = true, reply = real })
    end
    -- answer with a hidden whisper to their real name, after a short random
    -- wait so a busy server doesn't answer all at once
    if ns.CanShareScore() and (not lastWhisper[sender] or now() - lastWhisper[sender] >= 60) then
        lastWhisper[sender] = now()
        ns.After(1 + math.random() * 6, function() ns.BroadcastScoreTo(sender, real) end)
    end
end
ns.OnServerLine = OnServerLine

-- hide our coded lines from chat, whatever tab the channel ends up on
function ns.CommChannelFilter(_, _, text, _, _, channelName, _, _, _, _, baseName)
    if type(text) == "string" and text:sub(1, #CHAT_TAG) == CHAT_TAG and IsOurChannel(channelName, baseName) then
        return true
    end
    return false
end
if ChatFrame_AddMessageEventFilter then
    ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL", ns.CommChannelFilter)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("CHAT_MSG_ADDON")
ev:RegisterEvent("CHANNEL_UI_UPDATE")
ev:RegisterEvent("ADDON_ACTION_FORBIDDEN")
ev:RegisterEvent("ADDON_ACTION_BLOCKED")
ev:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE")
ev:RegisterEvent("CHAT_MSG_CHANNEL")
ev:SetScript("OnEvent", function(_, event, ...)
    if event == "CHAT_MSG_ADDON" then
        local prefix, msg, dist, sender = ...
        if prefix == PREFIX and msg and sender then OnMessage(msg, dist, sender) end
    elseif event == "CHAT_MSG_CHANNEL" then
        local text, sender, _, channelName, _, _, _, _, baseName, _, _, guid = ...
        if issecretvalue and (issecretvalue(text) or issecretvalue(sender)) then return end
        if IsOurChannel(channelName, baseName) then OnServerLine(text, sender, guid) end
    elseif event == "ADDON_ACTION_FORBIDDEN" or event == "ADDON_ACTION_BLOCKED" then
        local addon, func = ...
        if addon == ADDON then
            if tostring(func):find("SendChatMessage") and ns.autoPosting then
                -- the automatic post when opening the window was refused:
                -- keep the Ask for scores button, drop the automatic one
                ns.db.serverAutoBlocked = GameBuild()
                return
            end
            if tostring(func):find("SendChatMessage") then
                -- this game version won't let addons post in the channel:
                -- stop trying until the next game patch
                if ns.db.serverAskBlocked ~= GameBuild() then
                    ns.db.serverAskBlocked = GameBuild()
                    ns.Print("This game version doesn't let addons post in the score channel, so Ask for scores uses guild, group, friends and known players only.")
                end
                return
            end
            if ns.joiningChannel or tostring(func):find("Channel") then
                -- this client doesn't let addons join channels: never try again
                ns.db.channelJoinBlocked = true
                ns.Print("This game client doesn't let addons join chat channels. Type |cffffd100/join " .. CHANNEL .. "|r once to share scores server-wide.")
                return
            end
            ns.blocked = (ns.blocked or "") .. " " .. tostring(func)
            ns.Print("|cffff8080The game blocked an action:|r " .. tostring(func) .. ". Please tell the addon author.")
        end
    elseif event == "CHANNEL_UI_UPDATE" or event == "CHAT_MSG_CHANNEL_NOTICE" then
        local n = ChannelNumber()
        if n then
            local was = ns.channelState
            JoinChannel()   -- hides it from the chat tabs
        end
    end
end)

-- merge entries saved under older spellings of a name (e.g. "Shek'zeer"
-- vs "Shekzeer") so nobody shows up twice; the newest score wins
function ns.MergeBoardNames()
    local board, merged = ns.Board(), {}
    for k, e in pairs(board) do
        e.name = ns.NormalizeName(e.name or k)
        local key = ns.BoardKey(e.name)
        local cur = merged[key]
        if not cur or (e.ts or 0) > (cur.ts or 0) then
            if cur then
                if not e.direct and cur.direct then e.name = cur.name end
                e.direct = e.direct or cur.direct; e.guild = e.guild or cur.guild
            end
            merged[key] = e
        else
            if e.direct and not cur.direct then cur.name = e.name end
            cur.direct = cur.direct or e.direct; cur.guild = cur.guild or e.guild
        end
    end
    wipe(board)
    for k, e in pairs(merged) do if ns.IsLocalPlayer(e.name) then board[k] = e end end
end

ns.On("READY", function()
    if RegisterPrefix then pcall(RegisterPrefix, PREFIX) end
    ns.PruneBoard()
    ns.MergeBoardNames()
    if ns.tampered then ns.Board()[ns.BoardKey(ns.playerName)] = nil end
    ns.UpdateSelfOnBoard()
    -- channels need a moment after login before they can be joined; keep
    -- retrying (the general channels must exist first on some clients)
    ns.After(8, function()
        JoinChannel()
        if ns.db.useChannel and not ChannelNumber() and ns.db.channelJoinBlocked and ns.playerClass == "HUNTER" and not ns.cdb.channelHintShown then
            ns.cdb.channelHintShown = true
            ns.Print("To share scores with everyone on your server, type |cffffd100/join " .. CHANNEL .. "|r once. The game remembers it after that.")
        end
        -- Sharing schedule: your score goes out when you log in, when you
        -- collect a new look, and every 20 minutes. Other players' scores
        -- are only asked for when you press Ask for scores.
        ns.After(4, function() ns.BroadcastScore(true, true) end)
    end)
    if C_Timer and C_Timer.NewTicker then
        C_Timer.NewTicker(SHARE_EVERY, function()
            ns.BroadcastScore(true)
            ns.After(5, ns.RelayTop)
        end)
    end
end)

-- a new look: share the new score (30 seconds later, so taming several in
-- a row sends one update, not one each)
local pending
ns.On("COLLECTION_CHANGED", function()
    ns.UpdateSelfOnBoard()
    if pending then return end
    pending = true
    ns.After(30, function() pending = false; ns.BroadcastScore(true) end)
end)

------------------------------------------------------------------------
-- /hpc comm : show how sharing is doing
------------------------------------------------------------------------
function ns.CommReport()
    local function fmt(t)
        local parts = {}
        for k, v in pairs(t) do parts[#parts + 1] = k .. " " .. v end
        table.sort(parts)
        return #parts > 0 and table.concat(parts, ", ") or "none"
    end
    ns.Print("Realm channel: " .. tostring(ns.channelState) .. (ns.db.useChannel and "" or " (disabled)"))
    ns.Print("Sent: " .. fmt(stats.sent) .. "   Failed: " .. fmt(stats.fail))
    ns.Print("Received: " .. fmt(stats.recv) .. "   Ignored: " .. fmt(stats.rejected))
    local n = 0
    for _ in pairs(ns.Board()) do n = n + 1 end
    -- Forever: show the full name others see (learned from our own echoed
    -- messages), never the hidden realm
    local me = ns.playerName
    if ns.IsMegaServer() then
        me = (strsplit("-", me or ""))
        for key in pairs(Aliases()) do if #key > #me then me = key end end
    end
    ns.Print("You are: " .. tostring(me) .. "   Hunters on your board: " .. n)
    local lr = {}
    for k, v in pairs(stats.lastResult) do lr[#lr + 1] = k .. "=" .. v end
    if #lr > 0 then ns.Print("Last send results: " .. table.concat(lr, ", ")) end
    ns.Print(("Friends online on this server: %d"):format(#FriendTargets()))
    ns.Print(("Server asks posted: %d   Hunters found that way: %d"):format(stats.serverAsk, stats.serverHeard))
    JoinChannel()
    if ns.blocked then ns.Print("Blocked by the game this session:" .. ns.blocked) end
end
