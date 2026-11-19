-- luajit test/naowhtweaks.lua  (run from repo root)
local n, bad = 0, 0
local function ok(c, m) n = n + 1; if not c then bad = bad + 1; print("FAIL " .. m) end end

local handler
function CreateFrame()
    return { RegisterEvent = function() end, SetScript = function(_, _, fn) handler = fn end }
end
local inside, kind = false, "none"
function IsInInstance() return inside, kind end
NaowhForever = { AuraBuffs = { Buffs = { Collect = function()
    return { { key = "food" }, { key = "scroll" }, { key = "other" }, { key = "flask" } }
end } } }
MirogaUtilitiesDB = nil
local timers = {}
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
function hooksecurefunc(t, name, fn)
    local orig = t[name]
    t[name] = function(...) local r = { orig(...) }; fn(...); return unpack(r) end
end
local profile = { showEnabled = true }
RXP = { settings = { profile = profile, ToggleActive = function() profile.showEnabled = not profile.showEnabled end },
    v2 = { UpdateGuideWindow = function() end } }
local onShow
NaowhRXPWindow = { shown = true,
    IsShown = function(self) return self.shown end,
    Hide = function(self) self.shown = false end,
    Show = function(self) self.shown = true; if onShow then onShow(self) end end,
    HookScript = function(_, _, fn) onShow = fn end }
local root = { Off = function() return false end }
assert(loadfile("MirogaUtilities/Modules/NaowhTweaks.lua"))("MirogaUtilities", root)
local nt = root.NaowhTweaks
handler(nil, "ADDON_LOADED", "MirogaUtilities")
handler(nil, "PLAYER_LOGIN")

local function keys()
    local out = {}
    for _, e in ipairs(NaowhForever.AuraBuffs.Buffs.Collect()) do out[#out + 1] = e.key end
    return table.concat(out, ",")
end
ok(nt.db.scrollsInstanceOnly and nt.db.drinksInstanceOnly, "both on by default")
ok(keys() == "food,flask", "open world: no scroll, no buff drinks: " .. keys())
inside, kind = true, "party"
ok(keys() == "food,scroll,other,flask", "dungeon: everything")
inside, kind = true, "raid"
ok(keys() == "food,scroll,other,flask", "raid: everything")
inside, kind = false, "none"
nt.Set("drinksInstanceOnly", false)
ok(keys() == "food,other,flask", "drinks switch off: drinks everywhere")
nt.Set("scrollsInstanceOnly", false)
ok(keys() == "food,scroll,other,flask", "both off: Naowh's own rules")

-- RXP: /rxp hide takes Naowh's window along, /rxp show brings it back
for _, fn in ipairs(timers) do fn() end; timers = {}
ok(NaowhRXPWindow.shown, "guide shown: Naowh window stays")
RXP.settings.ToggleActive(); for _, fn in ipairs(timers) do fn() end; timers = {}
ok(not NaowhRXPWindow.shown, "/rxp hide hides Naowh's window")
NaowhRXPWindow:Show()
ok(not NaowhRXPWindow.shown, "Naowh redraw while hidden: hidden again")
RXP.settings.ToggleActive(); for _, fn in ipairs(timers) do fn() end; timers = {}
ok(NaowhRXPWindow.shown, "/rxp show brings it back")
nt.Set("rxpHide", false)
RXP.settings.ToggleActive(); for _, fn in ipairs(timers) do fn() end; timers = {}
ok(NaowhRXPWindow.shown, "switch off: Naowh's own behaviour")

-- druid buffs: with another druid, only while missing on me
local WILD = { class = "DRUID", spells = { 1126, 5232 } }
local FORT = { class = "PRIEST", spells = { 1243 } }

local origCollect = function() return { { key = "food" }, { key = WILD }, { key = FORT } } end

nt.db.scrollsInstanceOnly, nt.db.drinksInstanceOnly = false, false
local group, onMe = { "DRUID" }, false
function GetNumGroupMembers() return #group end
function IsInRaid() return false end
function UnitIsUnit(u) return u == "player" end
function UnitClass(u) local i = tonumber(u:match("%d+")); local c = group[(i or 0) + 1]; return c, c end
C_UnitAuras = { GetPlayerAuraBySpellID = function(id) if onMe and id == 5232 then return {} end end }
local function rows()
    local out = {}
    for _, e in ipairs(nt.Filter(origCollect())) do out[#out + 1] = type(e.key) == "table" and e.key.class or e.key end
    return table.concat(out, ",")
end
ok(rows() == "food,DRUID,PRIEST", "solo: Naowh's rule")
group = { "DRUID", "WARRIOR" }; onMe = true
ok(rows() == "food,DRUID,PRIEST", "only druid: Naowh's rule even with buff on me")
group = { "DRUID", "WARRIOR", "DRUID" }; onMe = false
ok(rows() == "food,DRUID,PRIEST", "other druid, missing on me: shows")
onMe = true
ok(rows() == "food,PRIEST", "other druid, on me: hidden, priest buff stays")
nt.Set("druidSelfOnly", false)
ok(rows() == "food,DRUID,PRIEST", "switch off: Naowh's rule")

print(n .. " checks, " .. bad .. " failures"); os.exit(bad == 0 and 0 or 1)
