-- Hunter Pet Collector - leaderboard page
local ADDON, ns = ...
local W = ns.W
local L = ns.L

local ROWS = 16
local filter = "all"
local page, list, mine, info, filterBtns

local COLS = {
    { key = "rank",   title = "#",        width = 44,  justify = "CENTER" },
    { key = "name",   title = "Hunter",   width = 300, justify = "LEFT" },
    { key = "points", title = "Points",   width = 110, justify = "RIGHT" },
    { key = "looks",  title = "Looks",    width = 110, justify = "RIGHT" },
    { key = "pct",    title = "Complete", width = 140, justify = "LEFT" },
    { key = "seen",   title = "Updated",  width = 110, justify = "RIGHT" },
    { key = "src",    title = "",         width = 40,  justify = "CENTER" },
}

local MEDALS = { "ffd700", "c0c0c0", "cd7f32" }

function ns.BuildBoard(parent)
    page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints()
    page:Hide()

    local panel = W.Panel(page, { 0.07, 0.07, 0.08, 1 })
    panel:SetPoint("TOPLEFT", 12, -12)
    panel:SetPoint("BOTTOMRIGHT", -12, 12)

    local title = W.Text(panel, "GameFontNormalLarge", 16, "LEFT")
    title:SetPoint("TOPLEFT", 16, -14)
    title:SetText("Hunter Pet Collector Leaderboard - " .. (ns.IsMegaServer() and "WoW: Forever" or (GetRealmName and GetRealmName() or "")))
    title:SetTextColor(1, 1, 1)

    info = W.Text(panel, "GameFontDisableSmall", nil, "LEFT")
    info:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)
    info:SetText((ns.IsMegaServer() and "Every hunter playing WoW: Forever." or "Hunters on this server only.") .. " Shared through your guild, group, friends and anyone you've shared with before. /hpc comm checks the connection.")

    mine = W.Text(panel, "GameFontNormal", nil, "RIGHT")
    mine:SetPoint("TOPRIGHT", -16, -16)

    -- filter + refresh buttons
    filterBtns = {}
    local fAll = W.Button(panel, "Everyone", 80, 22)
    fAll:SetPoint("TOPLEFT", info, "BOTTOMLEFT", 0, -10)
    local fGuild = W.Button(panel, "My guild", 80, 22)
    fGuild:SetPoint("LEFT", fAll, "RIGHT", 6, 0)
    filterBtns.all, filterBtns.guild = fAll, fGuild
    fAll:SetScript("OnClick", function() filter = "all"; ns.RefreshBoard() end)
    fGuild:SetScript("OnClick", function() filter = "guild"; ns.RefreshBoard() end)

    local refresh = W.Button(panel, "Ask for scores", 110, 22)
    refresh:SetPoint("TOPRIGHT", -16, -48)
    refresh.tooltip = "Ask other Pet Collector users nearby, in your guild and on your realm to share their scores."
    refresh:SetScript("OnClick", function(self)
        ns.AskServer()   -- first, while this is still the click
        ns.BroadcastScore(true, true)
        ns.RequestScores(nil, true)
        self:Disable()
        self.text:SetText(L["Asked!"])
        ns.After(60, function() self:Enable(); self.text:SetText(L["Ask for scores"]) end)   -- once a minute
    end)

    -- column header
    local head = CreateFrame("Frame", nil, panel)
    head:SetPoint("TOPLEFT", 12, -98)
    head:SetPoint("TOPRIGHT", -12, -98)
    head:SetHeight(20)
    local hbg = head:CreateTexture(nil, "BACKGROUND")
    hbg:SetAllPoints()
    hbg:SetTexture(W.WHITE)
    hbg:SetVertexColor(1, 1, 1, 0.05)
    local x = 6
    for _, c in ipairs(COLS) do
        local t = W.Text(head, "GameFontNormalSmall", nil, c.justify)
        t:SetPoint("LEFT", x, 0)
        t:SetWidth(c.width - 10)
        t:SetText(c.title)
        t:SetTextColor(W.ACCENT[1], W.ACCENT[2], W.ACCENT[3])
        x = x + c.width
    end

    list = W.List(panel, 26, ROWS, function(l, i)
        local row = CreateFrame("Frame", nil, l)
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.bg:SetTexture(W.WHITE)
        row.cells = {}
        local cx = 6
        for ci, c in ipairs(COLS) do
            if c.key == "pct" then
                local bar = W.Bar(row, c.width - 20, 10)
                bar:SetPoint("LEFT", cx, 0)
                bar.text:SetFontObject("GameFontHighlightSmall")
                bar.text:ClearAllPoints()
                bar.text:SetPoint("LEFT", bar, "RIGHT", 4, 0)
                row.bar = bar
            else
                local t = W.Text(row, ci == 2 and "GameFontHighlight" or "GameFontHighlightSmall", nil, c.justify)
                t:SetPoint("LEFT", cx, 0)
                t:SetWidth(c.width - 10)
                t:SetWordWrap(false)
                row.cells[c.key] = t
            end
            cx = cx + c.width
        end
        row.verified = row:CreateTexture(nil, "ARTWORK")
        row.verified:SetSize(14, 14)
        row.verified:SetPoint("CENTER", row.cells.src, "CENTER")
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            local e = self.entry
            if not e then return end
            GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
            -- Forever: the realm part is just whichever realm the game put
            -- them on this time, so show the name alone
            GameTooltip:AddLine(ns.flavor == "forever" and (strsplit("-", e.name)) or e.name, W.ClassColor(e.class))
            GameTooltip:AddDoubleLine(L["Points"], e.points, 0.8, 0.8, 0.8, 1, 0.82, 0)
            GameTooltip:AddDoubleLine(L["Looks collected"], e.count or "?", 0.8, 0.8, 0.8, 1, 1, 1)
            GameTooltip:AddDoubleLine(L["Last update"], W.TimeAgo(e.ts), 0.8, 0.8, 0.8, 1, 1, 1)
            if e.direct then
                GameTooltip:AddLine(L["Received directly from this player."], 0.3, 1, 0.3, true)
            else
                GameTooltip:AddLine(L["Relayed by another player - not yet confirmed directly."], 0.7, 0.7, 0.7, true)
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return row
    end, function(row, e, idx)
        row.entry = e
        local isMe = ns.IsMe(e.name)
        if isMe then
            row.bg:SetVertexColor(W.ACCENT[1], W.ACCENT[2], W.ACCENT[3], 0.16)
        else
            row.bg:SetVertexColor(1, 1, 1, idx % 2 == 0 and 0.025 or 0)
        end
        local rank = idx <= 3 and ("|cff%s%d|r"):format(MEDALS[idx], idx) or tostring(idx)
        row.cells.rank:SetText(rank)
        local short = e.name
        local n, realm = strsplit("-", e.name)
        local _, myRealm = strsplit("-", ns.playerName or "")
        if realm == myRealm or ns.flavor == "forever" then short = n end   -- Forever: one mega-server
        row.cells.name:SetText(short)
        row.cells.name:SetTextColor(W.ClassColor(e.class))
        row.cells.points:SetText(("|cffffd100%d|r"):format(e.points))
        row.cells.looks:SetText(e.count or "?")
        local total = ns.totalPoints or 0
        row.bar:SetProgress(e.points, total, total > 0 and ("%.1f%%"):format(100 * e.points / total) or "")
        row.cells.seen:SetText(W.TimeAgo(e.ts))
        row.cells.src:SetText("")
        if e.direct then
            row.verified:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
            row.verified:SetAlpha(1)
        else
            row.verified:SetTexture("Interface\\RaidFrame\\ReadyCheck-Waiting")
            row.verified:SetAlpha(0.6)
        end
    end)
    list:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -4)
    list:SetPoint("TOPRIGHT", head, "BOTTOMRIGHT", 0, -4)
    list:SetHeight(26 * ROWS)

    page.empty = W.Text(panel, "GameFontDisable", nil, "CENTER")
    page.empty:SetPoint("CENTER", list, "CENTER")
    page.empty:SetText("No other collectors seen yet.\nScores arrive as you meet other hunters using Hunter Pet Collector.")

    local foot = W.Text(panel, "GameFontDisableSmall", nil, "LEFT")
    foot:SetPoint("BOTTOMLEFT", 16, 12)
    foot:SetText("|TInterface\\RaidFrame\\ReadyCheck-Ready:12|t received from the player   |TInterface\\RaidFrame\\ReadyCheck-Waiting:12|t relayed by someone else    Points: Common 5 - Uncommon 10 - Rare 25 - Epic 50 - Legendary 100")
    return page
end

function ns.RefreshBoard()
    if not page or not page:IsShown() then return end
    ns.UpdateSelfOnBoard()
    for k, b in pairs(filterBtns) do b:SetSelected(k == filter) end
    local items = ns.SortedBoard(filter)
    list:SetItems(items)
    -- "nobody yet" means nobody but you (you're only listed on a hunter)
    local others = 0
    for _, e in ipairs(items) do if not ns.IsMe(e.name) then others = others + 1 end end
    page.empty:SetShown(others == 0)
    if ns.playerClass == "HUNTER" then
        for i, e in ipairs(items) do
            if ns.IsMe(e.name) then
                mine:SetText(("Your rank: |cffffd100#%d|r of %d"):format(i, #items))
                break
            end
        end
    else
        mine:SetText("|cff999999Log in on a hunter to join the board|r")
    end
end

ns.On("BOARD_CHANGED", function()
    if page and page:IsShown() then
        if not page.pending then
            page.pending = true
            ns.After(0.5, function() page.pending = false; ns.RefreshBoard() end)
        end
    end
end)
