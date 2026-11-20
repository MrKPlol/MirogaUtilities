-- luajit test/weeklyreminder.lua  (run from repo root)
local n, bad = 0, 0
local function ok(c, m) n = n + 1; if not c then bad = bad + 1; print("FAIL " .. m) end end

strlower = string.lower
local timers = {}
C_Timer = { After = function(s, fn) timers[#timers + 1] = fn end }
C_DateAndTime = { GetSecondsUntilWeeklyReset = function() return 3600 end, GetSecondsUntilDailyReset = function() return 600 end }
local function Widget()
    local w = { shown = false }
    setmetatable(w, { __index = function(t, k)
        return function(self, ...)
            if k == "Show" then self.shown = true elseif k == "Hide" then self.shown = false
            elseif k == "IsShown" then return self.shown
            elseif k == "SetText" then self.text = ...
            elseif k == "GetText" then return self.text
            elseif k == "GetStringWidth" then return 100
            elseif k == "GetStringHeight" then return (#(rawget(self, "text") or "") > (rawget(self, "wrapAt") or 999)) and 24 or 12
            elseif k == "GetObjectType" then return "FontString"
            elseif k == "SetFont" then return true
            elseif k == "SetScript" then local ev, fn = ...; rawset(self, "s_" .. ev, fn)
            elseif k == "CreateFontString" or k == "CreateTexture" or k == "CreateAnimationGroup" or k == "CreateAnimation" then return Widget()
            elseif k == "GetPoint" then return "TOP", nil, "TOP", 0, -150 end
        end
    end })
    return w
end
local frames, handler = {}, nil
function CreateFrame(kind, name)
    local f = Widget()
    f.regs = {}
    f.RegisterEvent = function(self, e) self.regs[e] = true end
    f.UnregisterEvent = function(self, e) self.regs[e] = nil end
    f.UnregisterAllEvents = function(self) self.regs = {} end
    frames[#frames + 1] = f
    if not handler then f.SetScript = function(self, _, fn) handler = fn end end
    return f
end
UIParent, GameTooltip, STANDARD_TEXT_FONT = Widget(), Widget(), "x"
function GameTooltip_Hide() end
function IsInInstance() return false, "none" end
function IsShiftKeyDown() return false end
function UnitGUID() return "Player-1" end
local level = 60
function UnitLevel() return level end
function time() return 1000 end
local qiID
local log, done, complete, bags = {}, {}, {}, {}
C_QuestLog = {
    IsQuestFlaggedCompleted = function(id) return done[id] end,
    GetLogIndexForQuestID = function(id) return log[id] end,
    IsComplete = function(id) return complete[id] end,
    GetSelectedQuest = function() return qiID end,
}
C_Item = { GetItemCount = function(id) return bags[id] or 0 end, GetItemIconByID = function() return 1 end }
local hooked = {}
function hooksecurefunc(name, fn) hooked[name] = fn end
QuestInfo_Display = function() end
GetQuestLogQuestText = function() end

QuestInfoFrame = { questLog = true }
local obj1, obj2 = Widget(), Widget()
QuestInfoObjectivesFrame = { Objectives = { obj1, obj2 } }

local root = { Off = function() return false end, ACCENT_HEX = "40e0d0" }
assert(loadfile("MirogaUtilities/Modules/WeeklyReminder.lua"))("MirogaUtilities", root)
local wg = root.WeeklyReminder
local self = frames[1]
handler(self, "ADDON_LOADED", "MirogaUtilities")
ok(wg.db and hooked.QuestInfo_Display, "loaded and hooked")
handler(self, "PLAYER_ENTERING_WORLD")

local function keys() local t = {}; for _, l in ipairs(wg.Lines()) do t[#t + 1] = l[1] end; return table.concat(t, ",") end
ok(keys() == "pickup", "pickup at 60")
level = 59; ok(keys() == "", "nothing below 60"); level = 60
done[96075] = true; ok(keys() == "", "done this week"); done[96075] = nil
-- seen at Pix: the line names the dungeon
GetQuestID = function() return 96076 end
handler(self, "QUEST_DETAIL")
ok(wg.Lines()[1][2]:find("Dire Maul", 1, true), "this week's quest named")
log[96076] = 3; ok(keys() == "", "in log, not complete: nothing")
complete[96076] = true; ok(keys() == "turnin", "turn-in line")
complete[96076] = nil

-- loot alert
ok(wg.ItemFor(368, "King Gordok").id == 272022, "Gordok by encounter id")
bags[272022] = 1; ok(wg.ItemFor(368, "King Gordok") == nil, "already have it"); bags[272022] = nil
ok(wg.ItemFor(9999, "Balnazzar") == nil, "other quest's boss ignored")
handler(self, "ENCOUNTER_END", 368, "King Gordok", 1, 5, 1)
ok(self.regs.BAG_UPDATE_DELAYED, "waiting for the item")
bags[272022] = 1; handler(self, "BAG_UPDATE_DELAYED")
ok(not self.regs.BAG_UPDATE_DELAYED, "cleared after looting")
log[96076] = nil; log[96087] = 1
ok(wg.ItemFor(nil, "Balnazzar").id == 272025, "Balnazzar by name")
log[96087] = nil

-- quest log annotation
qiID = 96076
obj1.shown, obj1.text = true, "0/1 Felvine Seed"
obj2.shown, obj2.text = true, "Ancient Memento: 1/1 (Complete)"
hooked.QuestInfo_Display()
ok(obj1.text:find("Alzzin the Wildshaper, DM East", 1, true), "boss after objective")
ok(obj2.text:find("Prince Tortheldrin", 1, true), "second objective")
hooked.QuestInfo_Display()
local _, c = obj1.text:gsub("Alzzin", "")
ok(c == 1, "not added twice")

-- EllesmereUI details window: appended only while it stays one line
log[96076] = 3
local e1, e2 = Widget(), Widget()
e1.shown, e1.text, e1.wrapAt = true, "Felvine Seed: 0/1", 60
e2.shown, e2.text, e2.wrapAt = true, "Earthstone Diamond Pinky Ring: 0/1", 60
local child = { GetRegions = function() return e1, e2 end }
local scrollf = { GetScrollChild = function() return child end }
EUI_QuestDetails = { IsShown = function() return true end, GetChildren = function() return scrollf end }
ok(hooked.GetQuestLogQuestText, "hooked EUI redraw")
hooked.GetQuestLogQuestText(3)
local snap = timers; timers = {}; for _, fn in ipairs(snap) do fn() end
ok(e1.text:find("Alzzin", 1, true), "EUI: boss added")
ok(#e1.text - #"Felvine Seed: 0/1" < 60, "EUI line fits")
ok(e2.text:find("Gordok", 1, true) and not e2.text:find("King Gordok", 1, true), "EUI: short form when long")
log[96076] = nil

-- login chat line
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) chatMsg = m end }
ok(wg.TimeLeft(3 * 86400 + 5 * 3600) == "3 days 5 h", "time left text")
ok(wg.TimeLeft(5400) == "1 h 30 min", "hours text")
ok(wg.ChatLine():find("not picked up", 1, true) and wg.ChatLine():find("left", 1, true), "chat: not picked up")
log[96076] = 3; bags[272022] = 1
ok(wg.ChatLine():find("Dire Maul", 1, true) and wg.ChatLine():find("1/3 items", 1, true), "chat: items so far")
complete[96076] = true; ok(wg.ChatLine():find("turn in", 1, true), "chat: ready"); complete[96076] = nil
log[96076] = nil; bags[272022] = nil
done[96076] = true; ok(wg.ChatLine() == nil, "chat: done, silent"); done[96076] = nil
level = 59; ok(wg.ChatLine() == nil, "chat: not below 60"); level = 60
timers = {}; handler(self, "PLAYER_ENTERING_WORLD", true, false)
local snap = timers; timers = {}; for _, fn in ipairs(snap) do fn() end
ok(chatMsg and chatMsg:find("Weekly quest", 1, true), "chat line printed after login")

-- winterspring
ok(not keys():find("winter"), "no winter line for characters without the daily")
log[5201] = 2; wg.Lines(); log[5201] = nil
ok(keys():find("winter"), "winter line once known")
done[5201] = true; ok(not keys():find("winter"), "winter done today"); done[5201] = nil
level = 59; ok(not keys():find("winter"), "winter: only at 60"); level = 60
wg.winterShown = true; ok(not keys():find("winter"), "winter line short-lived")

print(("weeklyreminder: %d/%d ok"):format(n - bad, n))
os.exit(bad == 0 and 0 or 1)
