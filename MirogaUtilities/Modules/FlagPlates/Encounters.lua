-------------------------------------------------------------------------------
--  FlagPlates - Encounters: sound + chat line when a flagged player shows up,
--  and per player counters (met, killed, killed you), saved in each entry.
--
--  Sighting: the nameplate code calls ns.OnSighted(entry, unit) when a flagged
--  player's plate is painted and ns.OnLost(unit) when it goes away. A new
--  encounter starts after 5 minutes out of view and counts as "met"; within
--  an encounter the alert repeats per db.repeatGap (see OnSighted).
--
--  Forever has no combat log, so kills are detected two ways:
--    * the honor kill chat line (CHAT_MSG_COMBAT_HONOR_GAIN) names the victim
--    * your flagged target dies while you are in combat
--  Your deaths: the death recap's killing blow when its source name is public,
--  else a flagged player who had you targeted when you died.
--  Every name read is checked for secrecy first; secret names never count.
-------------------------------------------------------------------------------
local _, root = ...
local ns = root.FlagPlates
if not ns then return end

local issecret = issecretvalue or function() return false end
local function public(v) return v ~= nil and not issecret(v) end

local ENCOUNTER_GAP = 300   -- seconds without a sighting before a new encounter
local SAME_DEATH = 30       -- one death is counted once, whichever path saw it

ns.SOUNDS = {
    { key = "raid", label = "Raid warning", id = SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959 },
    { key = "ready", label = "Ready check", id = SOUNDKIT and SOUNDKIT.READY_CHECK or 8960 },
    { key = "alarm", label = "Alarm clock", id = SOUNDKIT and SOUNDKIT.ALARM_CLOCK_WARNING_3 or 12889 },
    { key = "pvp", label = "PvP warning", id = SOUNDKIT and SOUNDKIT.UI_PVP_HONOR_PRESTIGE_OPEN_WINDOW or 12867 },
    { key = "none", label = "Off" },
}

function ns.PlayAlertSound(key)
    for _, s in ipairs(ns.SOUNDS) do
        if s.key == (key or ns.db.sound) and s.id then
            pcall(PlaySound, s.id, "Master")
            return
        end
    end
end

function ns.StatsText(e, long)
    local met, kills, deaths = e.met or 0, e.kills or 0, e.deaths or 0
    if long then
        return string.format("met %d×, you killed %d×, killed you %d×", met, kills, deaths)
    end
    return string.format("|cffbbbbbb%d|r met  |cff66ff66%d|r K  |cffff6666%d|r D", met, kills, deaths)
end

-------------------------------------------------------------------------------
--  Sightings
-------------------------------------------------------------------------------
-- Only a plate APPEARING can alert, never a repaint of one already in view.
-- An appearance alerts when the player was out of sight for OUT_OF_SIGHT
-- seconds (plates flicker at the edge of range) and the last alert for them
-- is db.repeatGap seconds old; a new encounter (5 min gap) always alerts.
-- Several players showing up together share one sound.
local OUT_OF_SIGHT = 30
local SOUND_GAP = 5

local unitEntry = {}   -- nameplate unit -> entry shown on it
local lostAt = {}      -- entry -> when its last plate went away
local lastAlert = {}   -- entry -> when it last alerted (this session)
local lastSound = 0

local function InView(entry)
    for _, e in pairs(unitEntry) do
        if e == entry then return true end
    end
    return false
end

local function Alert(entry, fresh, now)
    lastAlert[entry] = now
    if now - lastSound >= SOUND_GAP then
        lastSound = now
        ns.PlayAlertSound()
    end
    if not ns.db.alert then return end
    if fresh then
        ns.Print("|cffffffff%s|r spotted! %s", ns.DisplayName(entry), ns.StatsText(entry, true))
    else
        ns.Print("|cffffffff%s|r is back in view.", ns.DisplayName(entry))
    end
end

function ns.OnSighted(entry, unit)
    local now = time()
    if unit then
        if unitEntry[unit] == entry then return end   -- repaint, already counted
        local already = InView(entry)
        unitEntry[unit] = entry
        if already then return end
    end
    local fresh = not entry.lastSeen or now - entry.lastSeen > ENCOUNTER_GAP
    entry.lastSeen = now
    if fresh then
        entry.met = (entry.met or 0) + 1
        Alert(entry, true, now)
        if ns.RefreshUI then ns.RefreshUI() end
        return
    end
    local gap = ns.db.repeatGap or 0
    if gap <= 0 then return end
    if lostAt[entry] and now - lostAt[entry] < OUT_OF_SIGHT then return end
    if lastAlert[entry] and now - lastAlert[entry] < gap then return end
    Alert(entry, false, now)
end

function ns.OnLost(unit)
    local entry = unitEntry[unit]
    if not entry then return end
    unitEntry[unit] = nil
    if not InView(entry) then
        local now = time()
        lostAt[entry] = now
        entry.lastSeen = now   -- encounters run from the last moment in view
    end
end

function ns.OnLostAll()
    for unit in pairs(unitEntry) do ns.OnLost(unit) end
end

-------------------------------------------------------------------------------
--  Kills and deaths
-------------------------------------------------------------------------------
-- Entry for a bare first name from a chat line: first-name entries match
-- directly; a full entry only when it is the only one with that first name.
local function EntryByFirstName(name)
    local entry = ns.Lookup(name)
    if entry then return entry end
    local found
    local lower = strlower(name)
    for _, e in pairs(ns.db.entries) do
        if strlower(e.first) == lower then
            if found then return nil end
            found = e
        end
    end
    return found
end

local function CountKill(entry)
    local now = time()
    if entry.lastKill and now - entry.lastKill < SAME_DEATH then return end
    entry.lastKill = now
    entry.kills = (entry.kills or 0) + 1
    ns.Print("You killed |cffffffff%s|r! %s", ns.DisplayName(entry), ns.StatsText(entry, true))
    if ns.RefreshUI then ns.RefreshUI() end
end

local function CountDeath(entry)
    entry.deaths = (entry.deaths or 0) + 1
    ns.Print("|cffffffff%s|r killed you. %s", ns.DisplayName(entry), ns.StatsText(entry, true))
    if ns.RefreshUI then ns.RefreshUI() end
end

-- "%s dies, honorable kill Rank: %s (%d Honor Points)" -> Lua pattern
local honorPattern
do
    local fmt = _G.COMBATLOG_HONORGAIN
    if type(fmt) == "string" then
        honorPattern = "^" .. fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
            :gsub("%%s", "(.-)"):gsub("%%d", "%%d+") .. "$"
    end
end

local function OnHonorGain(msg)
    if not honorPattern or not public(msg) or type(msg) ~= "string" then return end
    local name = msg:match(honorPattern)
    if not name or name == "" then return end
    name = name:match("^([^%s%-]+)") or name
    local entry = EntryByFirstName(name)
    if entry then CountKill(entry) end
end

-- counts only the change alive -> dead, never a corpse you click on
local targetAlive = false
local function TargetDead()
    if not UnitExists("target") then return nil end
    local dead = UnitIsDeadOrGhost("target")
    if not public(dead) then return nil end
    return dead
end

local function OnTargetChanged()
    targetAlive = TargetDead() == false
end

local function OnTargetHealth()
    local dead = TargetDead()
    if dead == false then targetAlive = true; return end
    if not dead or not targetAlive then return end
    targetAlive = false
    local inCombat = UnitAffectingCombat("player")
    if public(inCombat) and not inCombat then return end
    local entry = ns.IsUnitFlagged("target")
    if entry then CountKill(entry) end
end

-- the killing blow from the death recap, when its source name is public
local function RecapKiller()
    local get = C_DeathRecap and C_DeathRecap.GetRecapEvents
    if not get then return nil end
    local ok, events = pcall(get)
    if not ok or not public(events) or type(events) ~= "table" then return nil end
    local first = events[1]
    if type(first) ~= "table" then return nil end
    local name = first.sourceName
    if not public(name) or type(name) ~= "string" then return nil end
    local base, surname = name:match("^([^%s%-]+)[%s%-]+(.+)$")
    return ns.Lookup(base or name, surname) or EntryByFirstName(base or name)
end

-- a flagged player (nameplate or target) who had you targeted
local function TargetingKiller()
    local units = { "target" }
    for _, np in ipairs(C_NamePlate.GetNamePlates() or {}) do
        local unit = (np.GetUnit and np:GetUnit()) or np.unitToken or (np.UnitFrame and np.UnitFrame.unit)
        if unit then units[#units + 1] = unit end
    end
    for _, unit in ipairs(units) do
        local entry = ns.IsUnitFlagged(unit)
        if entry then
            local onMe = UnitIsUnit(unit .. "target", "player")
            if public(onMe) and onMe then return entry end
        end
    end
end

local deathCandidate
local function OnPlayerDead()
    -- read the targets now, before they switch; the recap fills a moment later
    deathCandidate = TargetingKiller()
    C_Timer.After(1, function()
        local entry = RecapKiller() or deathCandidate
        deathCandidate = nil
        if entry then CountDeath(entry) end
    end)
end

-------------------------------------------------------------------------------
--  Events (registered once the saved list is loaded)
-------------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event, arg1)
    if event == "CHAT_MSG_COMBAT_HONOR_GAIN" then
        OnHonorGain(arg1)
    elseif event == "UNIT_HEALTH" then
        OnTargetHealth()
    elseif event == "PLAYER_TARGET_CHANGED" then
        OnTargetChanged()
    elseif event == "PLAYER_DEAD" then
        OnPlayerDead()
    end
end)

function ns.InitEncounters()
    -- one-time: chat line on by default now that it carries the counters
    if not ns.db.alertDefaultOn then
        ns.db.alertDefaultOn = true
        ns.db.alert = true
    end
    pcall(ev.RegisterEvent, ev, "CHAT_MSG_COMBAT_HONOR_GAIN")
    ev:RegisterUnitEvent("UNIT_HEALTH", "target")
    ev:RegisterEvent("PLAYER_TARGET_CHANGED")
    ev:RegisterEvent("PLAYER_DEAD")
end

-- wipe every counter (the flagged list itself stays)
function ns.PurgeStats()
    for _, e in pairs(ns.db.entries) do
        e.met, e.kills, e.deaths, e.lastSeen, e.lastKill = nil, nil, nil, nil, nil
    end
    ns.Print("Statistics cleared.")
    if ns.RefreshUI then ns.RefreshUI() end
end

StaticPopupDialogs["MIROGA_PURGE_STATS"] = {
    text = "Clear met / killed / deaths for every flagged player?\nThe list itself stays.",
    button1 = YES,
    button2 = NO,
    OnAccept = function() ns.PurgeStats() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

function ns.ConfirmPurgeStats()
    StaticPopup_Show("MIROGA_PURGE_STATS")
end

-------------------------------------------------------------------------------
--  Unit tooltip: "Flagged" plus the counters and when you last met
-------------------------------------------------------------------------------
local function Ago(t)
    local d = time() - t
    if d < 60 then return "just now" end
    if d < 3600 then return string.format("%d min ago", d / 60) end
    if d < 86400 then return string.format("%d h ago", d / 3600) end
    return string.format("%d days ago", d / 86400)
end

local function AddTooltipLines(tooltip)
    if not ns.db or not ns.db.tooltip or tooltip ~= GameTooltip then return end
    local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
    if not ok or not public(unit) or not unit then return end
    local entry = ns.IsUnitFlagged(unit)
    if not entry then return end
    local c = ns.db.color
    local seen = entry.lastSeen and ("  |cff999999· " .. Ago(entry.lastSeen) .. "|r") or ""
    tooltip:AddLine("Flagged" .. seen, c.r, c.g, c.b)
    tooltip:AddLine(string.format("|cffcccccc%d met|r  |cff66ff66%d killed|r  |cffff6666%d deaths|r",
        entry.met or 0, entry.kills or 0, entry.deaths or 0))
    tooltip:Show()
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
        pcall(AddTooltipLines, tooltip)
    end)
else
    GameTooltip:HookScript("OnTooltipSetUnit", function(tooltip) pcall(AddTooltipLines, tooltip) end)
end
