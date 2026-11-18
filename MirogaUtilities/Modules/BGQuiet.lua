-- BG quiet: less noise inside battlegrounds and arenas.
--
-- Errors: other addons (ProcDoc, WIM, HappyCamper, ForeverCCG, Naowh Discovery)
-- break on the secret values Forever hands out in instances and throw hundreds
-- of errors per match. BugSack plays its sound for each one. Inside a
-- battleground BugSack is muted (BugSackDB.mute) and gets its old setting back
-- when you leave. BugGrabber still records everything, /bugsack shows it.
--
-- Chat: message filters (no hooks on the chat frames), only while inside:
--  * "X creates: Conjured Water" lines from other players
--  * "Changed Channel" / "Left Channel" notices
--  * one- or two-character messages in instance/raid chat ("+", "1", "++")
--  * "11 players have joined the battle." / "X has left the battle." (system,
--    repeated hundreds of times while the match fills up)
-- Secret texts are never looked at or filtered.
local _, root = ...
local bq = {}
root.BGQuiet = bq

bq.DEFAULTS = { mute = true, crafts = true, notices = true, short = true, joins = true, arena = true, bigwigs = true }

local issecret = issecretvalue or function() return false end
local AddFilter = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter

local inside = false
bq.hiddenCount = 0

local function Hide()
    bq.hiddenCount = bq.hiddenCount + 1
    return true
end

local function Plain(text)
    return type(text) == "string" and not issecret(text)
end

-- others' crafting lines: the author is not you
local function CraftFilter(_, _, msg, author)
    if not inside or not bq.db.crafts then return false end
    if not Plain(msg) or not Plain(author) then return false end
    local me = UnitName("player")
    if author == me or Ambiguate(author, "short") == me then return false end
    return Hide()
end

local function NoticeFilter(_, _, msg)
    if not inside or not bq.db.notices then return false end
    if not Plain(msg) then return false end
    return Hide()
end

local function ShortFilter(_, _, msg)
    if not inside or not bq.db.short then return false end
    if not Plain(msg) then return false end
    local text = strtrim(msg)
    if text ~= "" and #text <= 2 then return Hide() end
    return false
end

-- Join/leave lines. Blizzard's BattlegroundChatFilters (secure frame) swallows
-- the single "X has joined the raid group" system messages for 60 s after
-- PLAYER_ENTERING_BATTLEGROUND and prints a summary every 5 s with
-- DEFAULT_CHAT_FRAME:AddMessage ("11 players have joined the battle."), which
-- no message filter can catch. Our filter is added at load, so it runs before
-- Blizzard's: the single messages are hidden here, the summary stays empty.
local JOIN_GLOBALS = { "ERR_RAID_MEMBER_ADDED_S", "ERR_BG_PLAYER_JOINED_SS",
    "ERR_RAID_MEMBER_REMOVED_S", "ERR_BG_PLAYER_LEFT_S" }
local JOIN_PATTERNS = { "joined the battle%.?$", "left the battle%.?$", "joined the raid group%.?$",
    "left the raid group%.?$" }
for _, name in ipairs(JOIN_GLOBALS) do
    local s = _G[name]
    if type(s) == "string" then
        s = s:gsub("([%[%]%(%)%.%-%+%*%?%^%$])", "%%%1"):gsub("%%%d?%$?s", ".-")
        JOIN_PATTERNS[#JOIN_PATTERNS + 1] = "^" .. s .. "$"
    end
end

-- diagnosis of the last battleground: who joined how often, and from where
local function Log(kind, text, frame)
    local d = bq.db and bq.db.diag
    if not d or #d.lines >= 400 then return end
    local from = type(frame) == "table" and (frame._isWIM and "WIM" or (frame.GetName and frame:GetName())) or "?"
    d.lines[#d.lines + 1] = ("%s %s %s %s"):format(date("%H:%M:%S"), kind, tostring(from), text)
end
bq.Log = Log

local function JoinFilter(frame, _, msg)
    if not inside or not bq.db.joins then return false end
    if not Plain(msg) then
        if bq.db.diag then bq.db.diag.secret = (bq.db.diag.secret or 0) + 1 end
        return false
    end
    for _, p in ipairs(JOIN_PATTERNS) do
        if msg:find(p) then
            Log("hide", msg, frame)
            return Hide()
        end
    end
    return false
end

-- BugSack sound off while inside, old value back afterwards
local function Mute(on)
    local sack = type(BugSackDB) == "table" and BugSackDB
    if not sack then return end
    local db = bq.db
    if on then
        if db.savedMute == nil then db.savedMute = sack.mute and true or false end
        sack.mute = true
    elseif db.savedMute ~= nil then
        sack.mute = db.savedMute
        db.savedMute = nil
    end
end

function bq.Evaluate()
    local db = bq.db
    if not db then return end
    local _, kind = IsInInstance()
    local now = kind == "pvp" or (db.arena and kind == "arena")
    if now ~= inside then
        inside = now
        if now then
            bq.hiddenCount = 0
            db.diag = { zone = GetRealZoneText and GetRealZoneText() or "?", lines = {} }
        end
    end
    Mute(inside and db.mute)
    if bq.OnChange then bq.OnChange() end
end

function bq.IsInside() return inside end

-- BigWigs asks for Capping in every battleground through its "Show zone
-- messages" option (BigWigs/Loader.lua, additionalPrintZones). That option is
-- the only switch for it, so it is turned off while this is on.
function bq.SyncBigWigs()
    local loader = _G.BigWigsLoader
    local profile = loader and loader.db and loader.db.profile
    if bq.db and bq.db.bigwigs and type(profile) == "table" and profile.showZoneMessages ~= false then
        profile.showZoneMessages = false
    end
end

function bq.Set(key, value)
    if not bq.db then return end
    bq.db[key] = value
    if key == "bigwigs" then bq.SyncBigWigs() end
    bq.Evaluate()
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, addon)
    if event == "ADDON_LOADED" then
        if addon ~= "MirogaUtilities" then return end
        self:UnregisterEvent("ADDON_LOADED")
        if root.Off("BGQuiet", self) then return end
        if type(MirogaUtilitiesDB) ~= "table" then MirogaUtilitiesDB = {} end
        MirogaUtilitiesDB.bgQuiet = MirogaUtilitiesDB.bgQuiet or {}
        local db = MirogaUtilitiesDB.bgQuiet
        for key, value in pairs(bq.DEFAULTS) do
            if db[key] == nil then db[key] = value end
        end
        bq.db = db
        if AddFilter then
            AddFilter("CHAT_MSG_TRADESKILLS", CraftFilter)
            AddFilter("CHAT_MSG_CHANNEL_NOTICE", NoticeFilter)
            AddFilter("CHAT_MSG_SYSTEM", JoinFilter)
            AddFilter("CHAT_MSG_BG_SYSTEM_NEUTRAL", JoinFilter)
            for _, e in ipairs({ "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
                "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER" }) do
                AddFilter(e, ShortFilter)
            end
        end
        self:RegisterEvent("PLAYER_ENTERING_WORLD")
        self:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        self:RegisterEvent("PLAYER_LOGOUT")
        self:RegisterEvent("PLAYER_ENTERING_BATTLEGROUND")
        -- summary lines are added straight to the frame: watched for the diagnosis
        if DEFAULT_CHAT_FRAME and hooksecurefunc then
            hooksecurefunc(DEFAULT_CHAT_FRAME, "AddMessage", function(_, text)
                if inside and Plain(text) and text:find("the battle") then Log("shown", text) end
            end)
        end
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then bq.SyncBigWigs() end
    if event == "PLAYER_ENTERING_BATTLEGROUND" then
        bq.Evaluate()
        Log("event", "PLAYER_ENTERING_BATTLEGROUND")
        return
    end
    if event == "PLAYER_LOGOUT" then
        -- never leave BugSack muted in the saved file
        Mute(false)
        return
    end
    bq.Evaluate()
end)
