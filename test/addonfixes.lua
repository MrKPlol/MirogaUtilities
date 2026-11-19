-- luajit test/addonfixes.lua  (run from repo root)
local n, bad = 0, 0
local function ok(c, m) n = n + 1; if not c then bad = bad + 1; print("FAIL " .. m) end end

-- secrets and locked tables, as the game marks them
local SECRET, LOCKED = {}, setmetatable({}, { __mode = "k" })
function issecretvalue(v) return v == SECRET end
function canaccesstable(t) return not LOCKED[t] end
local function locked(t) LOCKED[t] = true; return t end

local instance = "none"
function IsInInstance() return instance ~= "none", instance end
C_ChatInfo = { InChatMessagingLockdown = function() return false end }
local loaded = {}
C_AddOns = { IsAddOnLoaded = function(a) return loaded[a] == true end }
local handler
function CreateFrame() return { RegisterEvent = function() end, SetScript = function(_, _, fn) handler = fn end } end

-- the four addons, as far as the fixes touch them
local got
ProcDocAuraFrame = { script = function(_, _, unit, info) got = { unit = unit, info = info } end }
function ProcDocAuraFrame:GetScript() return self.script end
function ProcDocAuraFrame:SetScript(_, fn) self.script = fn end
local wimCalls = 0
local filterCalls = 0
local function wimFilter() filterCalls = filterCalls + 1; return true end
WIM = { modules = { WhisperEngine = { enabled = true, ChatMessageEventFilter = wimFilter,
    CHAT_MSG_SYSTEM = function() wimCalls = wimCalls + 1 end } } }
local chatFilters = {}
ChatFrameUtil = {
    AddMessageEventFilter = function(e, f) chatFilters[e] = chatFilters[e] or {}; chatFilters[e][f] = true end,
    RemoveMessageEventFilter = function(e, f) if chatFilters[e] then chatFilters[e][f] = nil end end }
for _, e in ipairs({ "CHAT_MSG_SYSTEM", "CHAT_MSG_BN_INLINE_TOAST_ALERT" }) do ChatFrameUtil.AddMessageEventFilter(e, wimFilter) end
local reads = 0
NaowhForever = { Completo = { Holidays = { Read = function() reads = reads + 1 end } } }
local checks = 0
HappyCamper_NS = { Comm = { CheckChannelOff = function() checks = checks + 1 end } }
local calEvent = { calendarType = "HOLIDAY", sequenceType = "ONGOING" }
C_DateAndTime = { GetCurrentCalendarTime = function() return { year = 2026, month = 11, monthDay = 18 } end }
C_Calendar = { GetMonthInfo = function() return { year = 2026, month = 11 } end,
    GetNumDayEvents = function() return 1 end, GetDayEvent = function() return calEvent end }

local root = { Off = function() return false end }
assert(loadfile("MirogaUtilities/Modules/AddonFixes.lua"))("MirogaUtilities", root)
local af = root.AddonFixes
MirogaUtilitiesDB = nil
loaded.ProcDoc, loaded.WIM = true, true
handler({ RegisterEvent = function() end }, "ADDON_LOADED", "MirogaUtilities")
ok(af.installed.procdoc and af.installed.wim and not af.installed.naowh, "loaded addons wrapped, others not yet")
loaded.NaowhForever_Discovery, loaded.HappyCamper = true, true
handler(nil, "ADDON_LOADED", "HappyCamper")
ok(af.installed.naowh and af.installed.happycamper, "late addons wrapped on their ADDON_LOADED")
ok(MirogaUtilitiesDB.addonFixes.procdoc == true, "defaults saved")

-- ProcDoc
local frame = ProcDocAuraFrame
local open = { addedAuras = { { spellId = 1 } }, removedAuraInstanceIDs = { 3 } }
frame.script(frame, "UNIT_AURA", "player", open)
ok(got.info == open and (af.hits.procdoc or 0) == 0, "readable payload passes untouched")
frame.script(frame, "UNIT_AURA", "player", { removedAuraInstanceIDs = locked({ 1 }) })
ok(got.info == nil and af.hits.procdoc == 1, "locked list: payload dropped")
frame.script(frame, "UNIT_AURA", "player", { addedAuras = { locked({}) } })
ok(got.info == nil and af.hits.procdoc == 2, "locked aura inside: dropped")
frame.script(frame, "UNIT_AURA", "player", locked({}))
ok(got.info == nil and af.hits.procdoc == 3, "locked payload: dropped")
af.Set("procdoc", false)
local lockedInfo = locked({})
frame.script(frame, "UNIT_AURA", "player", lockedInfo)
ok(got.info == lockedInfo, "switched off: passes through")

-- WIM: friend online lines
local engine = WIM.modules.WhisperEngine
local wrap = engine.ChatMessageEventFilter
ok(af.installed.wimonline and wrap ~= wimFilter, "online fix wraps the filter")
ok(chatFilters.CHAT_MSG_BN_INLINE_TOAST_ALERT[wrap] and not chatFilters.CHAT_MSG_BN_INLINE_TOAST_ALERT[wimFilter], "registered filter swapped")
ok(chatFilters.CHAT_MSG_SYSTEM[wrap] and not chatFilters.CHAT_MSG_SYSTEM[wimFilter], "swapped on other events too")
local chat = {}
ok(wrap(chat, "CHAT_MSG_BN_INLINE_TOAST_ALERT", "FRIEND_ONLINE", "x") == false and filterCalls == 0, "online line passes")
ok(wrap(chat, "CHAT_MSG_BN_INLINE_TOAST_ALERT", "FRIEND_OFFLINE", "x") == false and af.hits.wimonline == 2, "offline line passes")
ok(wrap(chat, "CHAT_MSG_BN_INLINE_TOAST_ALERT", "FRIEND_REQUEST", "x") == true and filterCalls == 1, "other alerts: WIM decides")
ok(wrap({ _isWIM = true }, "CHAT_MSG_BN_INLINE_TOAST_ALERT", "FRIEND_ONLINE") == true and filterCalls == 2, "WIM windows untouched")
ok(wrap(chat, "CHAT_MSG_BN_INLINE_TOAST_ALERT", SECRET) == true, "secret kind: WIM decides")
ok(wrap(chat, "CHAT_MSG_WHISPER", "hi") == true, "whispers: WIM decides")
af.Set("wimonline", false)
ok(wrap(chat, "CHAT_MSG_BN_INLINE_TOAST_ALERT", "FRIEND_ONLINE") == true, "switched off: WIM decides")
af.Set("wimonline", true)

-- WIM
engine:CHAT_MSG_SYSTEM("x"); ok(wimCalls == 1, "outside: replay runs")
instance = "pvp"; engine:CHAT_MSG_SYSTEM("x"); ok(wimCalls == 1 and af.hits.wim == 1, "BG: no replay")
instance = "none"; C_ChatInfo.InChatMessagingLockdown = function() return true end
engine:CHAT_MSG_SYSTEM("x"); ok(wimCalls == 1, "chat lockdown: no replay")
C_ChatInfo.InChatMessagingLockdown = function() return false end

-- Naowh
local H = NaowhForever.Completo.Holidays
H.Read(); ok(reads == 1, "calendar readable: Read runs")
calEvent.calendarType = SECRET
H.Read(); ok(reads == 1 and af.hits.naowh == 1, "secret calendar: Read waits")
calEvent.calendarType = "HOLIDAY"

-- HappyCamper
local comm = HappyCamper_NS.Comm
comm:CheckChannelOff(); ok(checks == 1, "outside: check runs")
instance = "arena"; comm:CheckChannelOff(); ok(checks == 1 and af.hits.happycamper == 1, "arena: no check")

-- EllesmereUI two tanks
local GREEN, RED, PURPLE = { r = 0, g = 1, b = 0 }, { r = 1, g = 0, b = 0 }, { r = 0.7, g = 0.2, b = 1 }
local tanking = {} -- [token] = isTanking
function UnitDetailedThreatSituation(u) return tanking[u] end
C_CurveUtil = { EvaluateColorValueFromBoolean = function(c, t, f) if c then return t end return f end }
local coTank = true
_G.EllesmereNameplates_NS = { db = { tankHasAggro = GREEN, tankNoAggro = RED }, defaults = {},
    ComputeOffTankFold = function(unit, r, g, b, otr, otg, otb)
        if not coTank then return false end
        if tanking.party1 then return true, otr, otg, otb, 1 end
        return true, r, g, b, 0
    end }
loaded.EllesmereUINameplates = true
handler(nil, "ADDON_LOADED", "EllesmereUINameplates")
ok(af.installed.euitanks, "EUI fold wrapped")
local NS = _G.EllesmereNameplates_NS
local function fold() return NS.ComputeOffTankFold("nameplate1", 0.5, 0.5, 0.5, PURPLE.r, PURPLE.g, PURPLE.b) end
tanking = { player = true, party1 = true }
local o, r, g, b = fold(); ok(o and r == 0 and g == 1, "on me: green, even when the co-tank reads tanking")
tanking = { player = false, party1 = true }
o, r, g, b = fold(); ok(o and r == 0.7 and b == 1, "on co-tank: purple")
tanking = { player = false, party1 = false, party2 = true }
o, r, g, b = fold(); ok(o and r == 1 and g == 0, "on a dps: red")
coTank = false
ok(fold() == false, "no co-tank: EUI as usual")
coTank = true; tanking = {}
o, r = fold(); ok(o and r == 0.5, "refused read: EUI's own fold")

print(n .. " checks, " .. bad .. " failures"); os.exit(bad == 0 and 0 or 1)
