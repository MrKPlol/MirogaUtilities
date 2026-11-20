-- Weekly quest: Pix Xizzix's "In Demand" weekly in Booty Bay (one of four
-- rotates in each week, Undermine Satchel, 10-100 gold).
--
--  * on-screen line "weekly is up" until you pick it up, and "turn it in"
--    once all three items are in your bags. A click on a line hides it until
--    the next login or /reload, then it comes back while still true.
--  * the quest log names the boss behind every objective, "Felvine Seed: 0/1
--    - Alzzin the Wildshaper, DM East": Blizzard's details (map, popup) and
--    EllesmereUI's own details window (click a quest in its tracker).
--  * a blinking item icon after one of the quest bosses dies while you still
--    need its item, until it is in your bags, you click it or leave.
--  * a short line for the Winterspring saber daily (Winterfall Intrusion) on
--    characters that have done it before, while it is open today.
--
-- Light: no OnUpdate, no ticker. Quest log changes are folded into one check
-- per half second; everything else runs on a handful of events.
local _, root = ...
local wg = {}
root.WeeklyReminder = wg

wg.DEFAULTS = { pickup = true, turnin = true, questLog = true, loot = true, winter = true, chat = true, pos = nil }

-- The four quests. Encounter IDs from Naowh Forever's Undermine Real table
-- (Blizzard's dungeon encounter IDs); bosses without a known ID match by the
-- name ENCOUNTER_END reports.
wg.QUESTS = {
    [96076] = { short = "Dire Maul", items = {
        { id = 272020, name = "Felvine Seed", boss = "Alzzin the Wildshaper", short = "Alzzin", where = "DM East", enc = 346 },
        { id = 272021, name = "Ancient Memento", boss = "Prince Tortheldrin", short = "Tortheldrin", where = "DM West", enc = 361 },
        { id = 272022, name = "Earthstone Diamond Pinky Ring", boss = "King Gordok", short = "Gordok", where = "DM North", enc = 368 },
    } },
    [96075] = { short = "Blackrock", items = {
        { id = 272017, name = "Nefarion's Remit", boss = "General Drakkisath", short = "Drakkisath", where = "UBRS", enc = 3069 },
        { id = 272018, name = "Overseer's License", boss = "Overlord Wyrmthalak", short = "Wyrmthalak", where = "LBRS", enc = 275 },
        { id = 272019, name = "Bronzebeard Wedding Contract", boss = "Emperor Thaurissan", short = "Thaurissan", where = "BRD", enc = 2790 },
    } },
    [96087] = { short = "Scholo + Strat", items = {
        { id = 272023, name = "Headmaster's Records", boss = "Darkmaster Gandling", short = "Gandling", where = "Scholomance", enc = 2801 },
        { id = 272024, name = "Grain Shipment Records", boss = "Baron Rivendare", short = "Rivendare", where = "Strat Undead", enc = 484 },
        { id = 272025, name = "Dathrohan's Correspondence", boss = "Balnazzar", short = "Balnazzar", where = "Strat Live", names = { "balnazzar", "dathrohan" } },
    } },
    [96088] = { short = "Titan relics", items = {
        { id = 272026, name = "Ysera's Tear", boss = "Shade of Eranikus", short = "Eranikus", where = "Sunken Temple", names = { "eranikus" } },
        { id = 272027, name = "Mark of Xavius", boss = "Varrox Bleakhoof", short = "Varrox", where = "Blackmaw Hold", names = { "varrox" } },
        { id = 272028, name = "Freya's Sigil", boss = "Nanaya", short = "Nanaya", where = "Shaper's Terrace", names = { "nanaya" } },
    } },
}
wg.WINTER_QUEST = 5201          -- Winterfall Intrusion (Wintersaber Trainers daily)
wg.MIN_LEVEL = 60

local ACCENT_HEX = root.ACCENT_HEX or "40e0d0"
local GOLD_HEX, DIM_HEX = "ffd100", "8a8f96"
local FONT_PATHS = { "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.ttf" }
local SIZE, ICON = 18, 40
local WINTER_SECONDS = 12

local function Done(id) return C_QuestLog.IsQuestFlaggedCompleted(id) and true or false end
local function InLog(id)
    local i = C_QuestLog.GetLogIndexForQuestID(id)
    return i ~= nil and i > 0
end
local function Count(id) return (C_Item and C_Item.GetItemCount or GetItemCount)(id) or 0 end

-- the In Demand quest in the log, or nil
function wg.Active()
    for id in pairs(wg.QUESTS) do
        if InLog(id) then return id end
    end
end

-- true when this week's quest is done (any of the four: only one is offered)
function wg.DoneThisWeek()
    for id in pairs(wg.QUESTS) do
        if Done(id) then return true end
    end
    return false
end

-- which of the four is offered this week, if seen on any character since the reset
function wg.ThisWeek()
    local w = wg.db and wg.db.week
    if w and w.id and (w.untilTime or 0) > time() then return w.id end
end

local function Remember(id)
    if not (wg.QUESTS[id] and wg.db) then return end
    local left = C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset and C_DateAndTime.GetSecondsUntilWeeklyReset()
    if left then wg.db.week = { id = id, untilTime = time() + left } end
end

-- the lines that should be on screen now: { key, text }
function wg.Lines()
    local db, out = wg.db, {}
    if not db then return out end
    local level = UnitLevel("player") or 0
    local active = wg.Active()
    if level >= wg.MIN_LEVEL then
        if active then
            if db.turnin and C_QuestLog.IsComplete(active) then
                out[#out + 1] = { "turnin", ("|cff%sWeekly quest:|r turn in at |cff%sPix Xizzix|r, Booty Bay"):format(GOLD_HEX, ACCENT_HEX) }
            end
        elseif db.pickup and not wg.DoneThisWeek() then
            local q = wg.QUESTS[wg.ThisWeek() or 0]
            out[#out + 1] = { "pickup", ("|cff%sWeekly quest is up%s|r - |cff%sPix Xizzix|r, Booty Bay"):format(
                GOLD_HEX, q and (": " .. q.short) or "", ACCENT_HEX) }
        end
    end
    local me = wg.charKey
    if me and InLog(wg.WINTER_QUEST) then db.winterChars[me] = true end   -- this character does the dailies
    if db.winter and level >= wg.MIN_LEVEL and me and db.winterChars[me] and not wg.winterShown
        and not Done(wg.WINTER_QUEST) and not InLog(wg.WINTER_QUEST) then
        out[#out + 1] = { "winter", ("|cff%sWinterspring daily|r is open: Winterfall Intrusion"):format("9ad0ff") }
    end
    return out
end

-- "3 days 5 h" until the weekly reset
function wg.TimeLeft(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    local d, h = math.floor(seconds / 86400), math.floor(seconds % 86400 / 3600)
    if d > 0 then return ("%d day%s %d h"):format(d, d == 1 and "" or "s", h) end
    if h > 0 then return ("%d h %d min"):format(h, math.floor(seconds % 3600 / 60)) end
    return ("%d min"):format(math.floor(seconds / 60))
end

-- one chat line after login while this week's quest is still open (level 60)
function wg.ChatLine()
    local db = wg.db
    if not (db and db.chat) or (UnitLevel("player") or 0) < wg.MIN_LEVEL or wg.DoneThisWeek() then return nil end
    local left = C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset and C_DateAndTime.GetSecondsUntilWeeklyReset()
    local active = wg.Active()
    local q = wg.QUESTS[active or wg.ThisWeek() or 0]
    local state
    if active and C_QuestLog.IsComplete(active) then
        state = "ready to turn in at Pix Xizzix"
    elseif active then
        local have = 0
        for _, item in ipairs(q.items) do if Count(item.id) > 0 then have = have + 1 end end
        state = ("%d/3 items"):format(have)
    else
        state = "not picked up yet (Pix Xizzix, Booty Bay)"
    end
    return ("|cff%sWeekly quest%s:|r %s - |cff%s%s left|r"):format(GOLD_HEX, q and (" " .. q.short) or "",
        state, ACCENT_HEX, left and wg.TimeLeft(left) or "?")
end

-- ---------------------------------------------------------------------------
-- on-screen lines

local holder, rows, hidden = nil, {}, {}

local function SetFont(fs, size)
    for _, path in ipairs(FONT_PATHS) do
        if fs:SetFont(path, size, "OUTLINE") then return end
    end
    fs:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE")
end

local function SavePos()
    local point, _, relPoint, x, y = holder:GetPoint(1)
    wg.db.pos = { point = point, relPoint = relPoint, x = x, y = y }
end

function wg.Place()
    if not holder then return end
    local p = wg.db and wg.db.pos
    holder:ClearAllPoints()
    if p then holder:SetPoint(p.point, UIParent, p.relPoint, p.x, p.y)
    else holder:SetPoint("TOP", UIParent, "TOP", 0, -150) end
end

local function Row(i)
    local b = rows[i]
    if b then return b end
    b = CreateFrame("Button", nil, holder)
    b:SetHeight(SIZE + 8)
    b.text = b:CreateFontString(nil, "OVERLAY")
    SetFont(b.text, SIZE)
    b.text:SetPoint("CENTER")
    b:RegisterForClicks("LeftButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnClick", function(self)
        hidden[self.key] = true
        if self.key == "winter" then wg.winterShown = true end
        wg.Refresh()
    end)
    -- Shift-drag moves all lines
    b:SetScript("OnDragStart", function() if IsShiftKeyDown() then holder:StartMoving() end end)
    b:SetScript("OnDragStop", function() holder:StopMovingOrSizing(); SavePos() end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Click: hide until the next login or /reload.", 1, 1, 1)
        GameTooltip:AddLine("Shift-drag: move.", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    rows[i] = b
    return b
end

function wg.Refresh()
    if not wg.db then return end
    if not holder then
        holder = CreateFrame("Frame", "MirogaWeeklyReminderLines", UIParent)
        holder:SetSize(10, 10)
        holder:SetMovable(true)
        holder:SetClampedToScreen(true)
        wg.Place()
    end
    local lines = wg.Lines()
    if wg.preview then lines = { { "preview", ("|cff%sWeekly quest is up: Dire Maul|r - |cff%sPix Xizzix|r, Booty Bay"):format(GOLD_HEX, ACCENT_HEX) } } end
    local pvp = select(2, IsInInstance())
    local n = 0
    for _, line in ipairs(lines) do
        if not hidden[line[1]] and pvp ~= "pvp" and pvp ~= "arena" then
            n = n + 1
            local b = Row(n)
            b.key = line[1]
            b.text:SetText(line[2])
            b:SetWidth(b.text:GetStringWidth() + 20)
            b:ClearAllPoints()
            b:SetPoint("TOP", holder, "TOP", 0, -(n - 1) * (SIZE + 10))
            b:Show()
            if line[1] == "winter" and not wg.winterTimer then
                wg.winterTimer = true
                C_Timer.After(WINTER_SECONDS, function() wg.winterShown = true; wg.Refresh() end)
            end
        end
    end
    for i = n + 1, #rows do rows[i]:Hide() end
end

-- ---------------------------------------------------------------------------
-- loot reminder: blinking item icon

local loot, pending = nil, nil   -- pending = item entry

local function ItemFor(encounterID, name)
    local q = wg.QUESTS[wg.Active() or 0]
    if not q then return nil end
    name = type(name) == "string" and not (issecretvalue and issecretvalue(name)) and strlower(name) or ""
    for _, item in ipairs(q.items) do
        local hit = item.enc and item.enc == encounterID
        if not hit and name ~= "" then
            if name == strlower(item.boss) then hit = true end
            for _, part in ipairs(item.names or {}) do
                if name:find(part, 1, true) then hit = true end
            end
        end
        if hit and Count(item.id) == 0 then return item end
    end
end
wg.ItemFor = ItemFor

local function ShowLoot()
    if not loot then
        loot = CreateFrame("Button", "MirogaWeeklyReminderLoot", UIParent)
        loot:SetSize(ICON, ICON)
        loot:SetPoint("CENTER", UIParent, "CENTER", 0, 140)
        loot.icon = loot:CreateTexture(nil, "ARTWORK")
        loot.icon:SetAllPoints()
        loot.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        loot.border = loot:CreateTexture(nil, "BACKGROUND")
        loot.border:SetPoint("TOPLEFT", -1, 1)
        loot.border:SetPoint("BOTTOMRIGHT", 1, -1)
        loot.border:SetColorTexture(0, 0, 0, 1)
        loot.label = loot:CreateFontString(nil, "OVERLAY")
        SetFont(loot.label, 15)
        loot.label:SetPoint("TOP", loot, "BOTTOM", 0, -4)
        local blink = loot:CreateAnimationGroup()
        blink:SetLooping("BOUNCE")
        local fade = blink:CreateAnimation("Alpha")
        fade:SetFromAlpha(1)
        fade:SetToAlpha(0.25)
        fade:SetDuration(0.5)
        loot.blink = blink
        loot:SetScript("OnClick", function() wg.ClearLoot() end)
    end
    local icon = C_Item.GetItemIconByID and C_Item.GetItemIconByID(pending.id)
    loot.icon:SetTexture(icon or 134400)
    loot.label:SetText(("|cff%sLoot %s|r"):format(GOLD_HEX, pending.name))
    loot:Show()
    loot.blink:Play()
end

function wg.ClearLoot()
    pending = nil
    if loot then loot.blink:Stop(); loot:Hide() end
    wg.events:UnregisterEvent("BAG_UPDATE_DELAYED")
end

function wg.BossDied(encounterID, name)
    if not (wg.db and wg.db.loot) then return end
    local item = ItemFor(encounterID, name)
    if not item then return end
    pending = item
    wg.events:RegisterEvent("BAG_UPDATE_DELAYED")
    ShowLoot()
end

-- ---------------------------------------------------------------------------
-- quest log: boss and place behind each objective

-- one objective line: append the boss, as long as the line stays one line
-- (EllesmereUI places its lines by measured height, a wrap would overlap)
local function Tag(fs, q, keepHeight)
    local text = fs:IsShown() and fs:GetText()
    if not text or text:find("|cff" .. DIM_HEX, 1, true) then return end
    for _, item in ipairs(q.items) do
        if text:find(item.name, 1, true) then
            local h = fs:GetStringHeight()
            for _, tail in ipairs({ item.boss .. ", " .. item.where, item.short .. ", " .. item.where, item.short }) do
                fs:SetText(("%s  |cff%s- %s|r"):format(text, DIM_HEX, tail))
                if not keepHeight or fs:GetStringHeight() <= h + 1 then return end
            end
            fs:SetText(text)
            return
        end
    end
end

-- Blizzard's quest details (map and popup): lines are chained, wrapping is fine
local function Annotate()
    if not (wg.db and wg.db.questLog) then return end
    -- Blizzard's QuestInfo_GetQuestID is local to QuestInfo.lua: same logic here
    local id
    if QuestInfoFrame and QuestInfoFrame.questLog then id = C_QuestLog.GetSelectedQuest()
    elseif GetQuestID then id = GetQuestID() end
    local q = id and wg.QUESTS[id]
    local list = q and QuestInfoObjectivesFrame and QuestInfoObjectivesFrame.Objectives
    if not list then return end
    for _, fs in ipairs(list) do Tag(fs, q, false) end
end

-- EllesmereUI's own quest details window (click a quest in its tracker).
-- Its Refresh is private; it calls GetQuestLogQuestText on every redraw, so a
-- hook there plus one frame of delay lands right after the window is drawn.
local euiQueued = false
local function AnnotateEUI()
    euiQueued = false
    local win = _G.EUI_QuestDetails
    local q = wg.QUESTS[wg.Active() or 0]
    if not (q and win and win:IsShown() and wg.db and wg.db.questLog) then return end
    for _, kid in ipairs({ win:GetChildren() }) do
        local child = kid.GetScrollChild and kid:GetScrollChild()
        if child then
            for _, r in ipairs({ child:GetRegions() }) do
                if r.GetText and r:GetObjectType() == "FontString" then Tag(r, q, true) end
            end
        end
    end
end
wg.AnnotateEUI = AnnotateEUI
local function QueueEUI()
    if euiQueued or not _G.EUI_QuestDetails then return end
    euiQueued = true
    C_Timer.After(0, AnnotateEUI)
end
wg.QueueEUI = QueueEUI
wg.Annotate = Annotate

-- ---------------------------------------------------------------------------

function wg.Set(key, value)
    if wg.db then wg.db[key] = value and true or false end
    wg.Refresh()
    if key == "loot" and not value then wg.ClearLoot() end
end

function wg.ResetPosition()
    if wg.db then wg.db.pos = nil end
    wg.Place()
end

function wg.Preview(on)
    wg.preview = on or nil
    wg.Refresh()
end

local queued = false
local function Soon()
    if queued then return end
    queued = true
    C_Timer.After(0.5, function() queued = false; wg.Refresh() end)
end

local function AtReset()
    -- re-check right after the daily / weekly reset while logged in
    local d = C_DateAndTime and C_DateAndTime.GetSecondsUntilDailyReset and C_DateAndTime.GetSecondsUntilDailyReset()
    if d and d > 0 then C_Timer.After(d + 10, function() wg.winterShown, wg.winterTimer = nil, nil; wg.Refresh(); AtReset() end) end
end

-- QuestInfo_Display may arrive after us: try again on later loads
function wg.HookBlizzard()
    if wg.blizzHooked or not QuestInfo_Display then return end
    hooksecurefunc("QuestInfo_Display", Annotate)
    wg.blizzHooked = true
end

local events = CreateFrame("Frame")
wg.events = events
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, a, b, _, _, e)
    if event == "ADDON_LOADED" then
        if a ~= "MirogaUtilities" then
            if wg.db then wg.HookBlizzard(); if wg.blizzHooked then self:UnregisterEvent("ADDON_LOADED") end end
            return
        end
        if root.Off("WeeklyReminder", self) then return end
        if type(MirogaUtilitiesDB) ~= "table" then MirogaUtilitiesDB = {} end
        MirogaUtilitiesDB.weeklyReminder = MirogaUtilitiesDB.weeklyReminder or {}
        wg.db = MirogaUtilitiesDB.weeklyReminder
        for key, value in pairs(wg.DEFAULTS) do
            if wg.db[key] == nil then wg.db[key] = value end
        end
        wg.db.winterChars = wg.db.winterChars or {}
        if GetQuestLogQuestText then hooksecurefunc("GetQuestLogQuestText", QueueEUI) end
        wg.HookBlizzard()
        if wg.blizzHooked then self:UnregisterEvent("ADDON_LOADED") end
        for _, ev in ipairs({ "PLAYER_ENTERING_WORLD", "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_TURNED_IN",
            "QUEST_DETAIL", "PLAYER_LEVEL_UP", "ENCOUNTER_END" }) do
            self:RegisterEvent(ev)
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        wg.HookBlizzard()
        if a then   -- isInitialLogin: one chat line, a few seconds in (after the login spam)
            C_Timer.After(6, function()
                local line = wg.ChatLine()
                if line then DEFAULT_CHAT_FRAME:AddMessage(line) end
            end)
        end
        if not wg.charKey then
            wg.charKey = UnitGUID("player")
            AtReset()
        end
        if pending and not IsInInstance() then wg.ClearLoot() end
        Soon()
    elseif event == "ENCOUNTER_END" then
        if e == 1 then wg.BossDied(a, b) end
    elseif event == "BAG_UPDATE_DELAYED" then
        if pending and Count(pending.id) > 0 then wg.ClearLoot() end
    elseif event == "QUEST_DETAIL" then
        Remember(GetQuestID and GetQuestID())
    elseif event == "QUEST_ACCEPTED" or event == "QUEST_TURNED_IN" then
        local id = event == "QUEST_ACCEPTED" and (b or a) or a
        if id == wg.WINTER_QUEST and wg.charKey then wg.db.winterChars[wg.charKey] = true end
        Remember(id)
        Soon()
    else
        Soon()
    end
end)
