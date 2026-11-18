-- luajit test/bgquiet.lua  (run from repo root)
local n, bad = 0, 0
local function ok(c, m) n = n + 1; if not c then bad = bad + 1; print("FAIL " .. m) end end
local handler, frame
function CreateFrame()
    frame = { RegisterEvent = function() end, UnregisterEvent = function() end,
        SetScript = function(_, _, fn) handler = fn end }
    return frame
end
local filters = {}
ChatFrameUtil = { AddMessageEventFilter = function(e, fn) filters[e] = fn end }
local kind = "none"
function IsInInstance() return kind ~= "none", kind end
function UnitName() return "Miroga" end
function Ambiguate(n) return (n:gsub("%-.*", "")) end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
local secret = {}
function issecretvalue(v) return v == secret end
BugSackDB = { mute = false }
ERR_RAID_MEMBER_ADDED_S = "%s has joined the raid group."
function date() return "21:22:00" end
function GetRealZoneText() return "Alterac Valley" end
function hooksecurefunc() end
DEFAULT_CHAT_FRAME = {}
local root = { Off = function() return false end }
assert(loadfile("MirogaUtilities/Modules/BGQuiet.lua"))("MirogaUtilities", root)
local bq = root.BGQuiet
handler(frame, "ADDON_LOADED", "MirogaUtilities")
handler(frame, "PLAYER_ENTERING_WORLD")
ok(not filters.CHAT_MSG_TRADESKILLS(nil, nil, "Thorny creates: Water", "Thorny"), "outside: crafts shown")
ok(BugSackDB.mute == false, "outside: BugSack not muted")
kind = "pvp"; handler(frame, "ZONE_CHANGED_NEW_AREA")
ok(BugSackDB.mute == true, "inside: BugSack muted")
ok(filters.CHAT_MSG_TRADESKILLS(nil, nil, "Thorny creates: Water", "Thorny-Realm"), "inside: others' crafts hidden")
ok(not filters.CHAT_MSG_TRADESKILLS(nil, nil, "You create: Water", "Miroga"), "own craft shown")
ok(filters.CHAT_MSG_CHANNEL_NOTICE(nil, nil, "YOU_CHANGED"), "channel notice hidden")
ok(filters.CHAT_MSG_INSTANCE_CHAT(nil, nil, " + "), "plus hidden")
ok(not filters.CHAT_MSG_INSTANCE_CHAT(nil, nil, "inc stables"), "real message shown")
ok(not filters.CHAT_MSG_INSTANCE_CHAT(nil, nil, secret), "secret never filtered")
ok(filters.CHAT_MSG_SYSTEM(nil, nil, "11 players have joined the battle."), "join count hidden")
ok(filters.CHAT_MSG_SYSTEM(nil, nil, "Cabalist Microheal has joined the battle."), "single join hidden")
ok(filters.CHAT_MSG_SYSTEM(nil, nil, "Rudra has left the battle"), "leave hidden")
ok(not filters.CHAT_MSG_SYSTEM(nil, nil, "Whiskia claims the Snowfall graveyard!"), "other system shown")
ok(filters.CHAT_MSG_SYSTEM({ _isWIM = true }, nil, "Rudra-Realm has joined the raid group."), "raid join hidden (before Blizzard's summary)")
ok(bq.hiddenCount == 7, "counted")
ok(#bq.db.diag.lines == 4 and bq.db.diag.lines[4]:find("WIM"), "diagnosis logs source")
handler(frame, "PLAYER_LOGOUT")
ok(BugSackDB.mute == false, "logout: BugSack unmuted in the saved file")
kind = "none"; handler(frame, "ZONE_CHANGED_NEW_AREA")
ok(BugSackDB.mute == false, "outside again: not muted")
BugSackDB.mute = true; kind = "pvp"; handler(frame, "ZONE_CHANGED_NEW_AREA"); kind = "none"; handler(frame, "ZONE_CHANGED_NEW_AREA")
ok(BugSackDB.mute == true, "user's own mute kept")
print(n .. " checks, " .. bad .. " failures"); os.exit(bad == 0 and 0 or 1)
