-- Addon fixes: stops the errors other addons throw in battlegrounds at
-- their source, instead of hiding them. Nothing in their files is changed;
-- each fix wraps one entry point the addon itself exposes, and only steps in
-- when the game has locked the data that entry point would trip over.
--
-- Found in BugSack (17.11.2026, BG sessions):
--   ProcDoc 4.20      5147x "iterate a table that cannot be accessed while tainted":
--                     UNIT_AURA's updateInfo lists are locked in a BG; ProcDoc only
--                     checks issecretvalue, then ipairs()es them (HandleAuraUpdate).
--                     Fix: its aura frame gets the event without the locked payload,
--                     so it does its full buff scan, which already handles locks.
--   WIM 3.19          560x same message: WhisperEngine replays every system line
--                     through Blizzard's chat filter list, a secure array a tainted
--                     caller may not walk in a BG. Fix: no replay there (it only
--                     feeds WIM's "player is offline" notes in whisper windows).
--   NaowhForever_Discovery 1.3  ~190x calendarType is secret in a BG, Holidays.Read
--                     compares it. Fix: Read waits while the calendar is locked
--                     and the holidays read before stay.
--   HappyCamper 1.1   JoinTemporaryChannel blocked: its channel check rejoins the
--                     camp channel from a timer, which a BG forbids. Fix: no
--                     channel check while in a BG or arena.
--
-- Errors raised there are reported even inside pcall, so the only real fix is
-- not to touch the locked data at all.
local _, root = ...
local af = {}
root.AddonFixes = af

af.FIXES = {
    { key = "procdoc", addon = "ProcDoc", label = "ProcDoc: locked buff lists",
        desc = "Hands ProcDoc the aura event without the locked lists; it scans your buffs instead." },
    { key = "wim", addon = "WIM", label = "WIM: chat filter replay",
        desc = "WIM no longer replays system lines through the chat filters in battlegrounds." },
    { key = "naowh", addon = "NaowhForever_Discovery", label = "Naowh Discovery: holiday calendar",
        desc = "Holiday check waits while the calendar is locked; the last known holidays stay." },
    { key = "happycamper", addon = "HappyCamper", label = "HappyCamper: channel rejoin",
        desc = "No camp channel check in battlegrounds and arenas, where joining is blocked." },
}
af.DEFAULTS = { procdoc = true, wim = true, naowh = true, happycamper = true }
af.hits = {}        -- [key] = times stepped in this session
af.installed = {}   -- [key] = true once wrapped

local issecret = issecretvalue or function() return false end

local function Hit(key)
    af.hits[key] = (af.hits[key] or 0) + 1
end

local function On(key)
    return af.db ~= nil and af.db[key] ~= false
end

-- true when addon code may not read this table (or the value is secret)
local function Locked(t)
    if t == nil then return false end
    if issecret(t) then return true end
    if type(t) ~= "table" then return false end
    if canaccesstable then
        local ok, can = pcall(canaccesstable, t)
        return not ok or issecret(can) or can ~= true
    end
    if issecrettable then
        local ok, sec = pcall(issecrettable, t)
        return not ok or issecret(sec) or sec == true
    end
    return false
end
af.Locked = Locked

-- battleground, arena, or the game's chat lockdown
function af.Restricted()
    local chat = C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
    if chat then
        local ok, locked = pcall(chat)
        if ok and not issecret(locked) and locked == true then return true end
    end
    local _, kind = IsInInstance()
    return kind == "pvp" or kind == "arena"
end

-- ---------------------------------------------------------------------------
-- ProcDoc

local AURA_LISTS = { "removedAuraInstanceIDs", "addedAuras", "updatedAuraInstanceIDs" }

-- the payload with nothing locked in it, or nil
function af.CleanAuraInfo(info)
    if info == nil then return nil end
    if Locked(info) then return nil, true end
    for _, field in ipairs(AURA_LISTS) do
        local list = info[field]
        if Locked(list) then return nil, true end
        if field == "addedAuras" and type(list) == "table" then
            for _, aura in ipairs(list) do
                if Locked(aura) then return nil, true end
            end
        end
    end
    return info
end

local function FixProcDoc()
    local frame = _G.ProcDocAuraFrame
    if not (frame and frame.GetScript) then return false end
    local original = frame:GetScript("OnEvent")
    if type(original) ~= "function" then return false end
    frame:SetScript("OnEvent", function(self, event, unit, info, ...)
        if On("procdoc") and event == "UNIT_AURA" then
            local clean, dropped = af.CleanAuraInfo(info)
            if dropped then Hit("procdoc") end
            return original(self, event, unit, clean, ...)
        end
        return original(self, event, unit, info, ...)
    end)
    return true
end

-- ---------------------------------------------------------------------------
-- WIM

local function FixWIM()
    local engine = type(WIM) == "table" and type(WIM.modules) == "table" and WIM.modules.WhisperEngine
    local original = engine and engine.CHAT_MSG_SYSTEM
    if type(original) ~= "function" then return false end
    engine.CHAT_MSG_SYSTEM = function(self, ...)
        if On("wim") and af.Restricted() then
            Hit("wim")
            return
        end
        return original(self, ...)
    end
    return true
end

-- ---------------------------------------------------------------------------
-- NaowhForever_Discovery

-- true when one of today's calendar events has secret fields
function af.CalendarLocked()
    if not (C_DateAndTime and C_Calendar and C_Calendar.GetDayEvent) then return false end
    local now, shown = C_DateAndTime.GetCurrentCalendarTime(), C_Calendar.GetMonthInfo(0)
    if Locked(now) or Locked(shown) then return true end
    if not (now and shown) then return false end
    local offset = (now.year - shown.year) * 12 + now.month - shown.month
    local count = C_Calendar.GetNumDayEvents(offset, now.monthDay)
    if issecret(count) then return true end
    for i = 1, count or 0 do
        local event = C_Calendar.GetDayEvent(offset, now.monthDay, i)
        if Locked(event) then return true end
        if type(event) == "table" and (issecret(event.calendarType) or issecret(event.sequenceType)) then return true end
    end
    return false
end

local function FixNaowh()
    local ns = type(NaowhForever) == "table" and NaowhForever
    local holidays = ns and type(ns.Completo) == "table" and ns.Completo.Holidays
    local original = type(holidays) == "table" and holidays.Read
    if type(original) ~= "function" then return false end
    holidays.Read = function(...)
        if On("naowh") and af.CalendarLocked() then
            Hit("naowh")
            return
        end
        return original(...)
    end
    return true
end

-- ---------------------------------------------------------------------------
-- HappyCamper

local function FixHappyCamper()
    local comm = type(HappyCamper_NS) == "table" and HappyCamper_NS.Comm
    local original = type(comm) == "table" and comm.CheckChannelOff
    if type(original) ~= "function" then return false end
    comm.CheckChannelOff = function(self, ...)
        if On("happycamper") then
            local _, kind = IsInInstance()
            if kind == "pvp" or kind == "arena" then
                Hit("happycamper")
                return
            end
        end
        return original(self, ...)
    end
    return true
end

local INSTALL = { procdoc = FixProcDoc, wim = FixWIM, naowh = FixNaowh, happycamper = FixHappyCamper }

-- wraps every fix whose addon is loaded and not wrapped yet; a fix that is
-- switched off stays wrapped but passes everything through
function af.Install()
    for _, fix in ipairs(af.FIXES) do
        if not af.installed[fix.key] and C_AddOns.IsAddOnLoaded(fix.addon) then
            local ok, done = pcall(INSTALL[fix.key])
            if ok and done then af.installed[fix.key] = true end
        end
    end
end

function af.Set(key, value)
    if af.db then af.db[key] = value and true or false end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" and name == "MirogaUtilities" then
        if root.Off("AddonFixes", self) then return end
        if type(MirogaUtilitiesDB) ~= "table" then MirogaUtilitiesDB = {} end
        MirogaUtilitiesDB.addonFixes = MirogaUtilitiesDB.addonFixes or {}
        af.db = MirogaUtilitiesDB.addonFixes
        for key, value in pairs(af.DEFAULTS) do
            if af.db[key] == nil then af.db[key] = value end
        end
        self:RegisterEvent("PLAYER_LOGIN")
        af.Install()
    elseif af.db then
        -- an addon loaded after us (or later, on demand): wrap it now
        af.Install()
    end
end)
