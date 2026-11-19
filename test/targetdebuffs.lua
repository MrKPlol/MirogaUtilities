-- luajit test/targetdebuffs.lua  (run from repo root)
local n, bad = 0, 0
local function ok(c, m) n = n + 1; if not c then bad = bad + 1; print("FAIL " .. m) end end
local SECRET = {}
function issecretvalue(v) return v == SECRET end
local list = {}
C_UnitAuras = { GetAuraDataByIndex = function(u, i, f) return list[i] end }
C_Spell = { GetSpellName = function() return nil end, GetSpellTexture = function() return 1 end }
local exists, attack, dead = true, true, false
function UnitExists() return exists end
function UnitCanAttack() return attack end
function UnitIsDeadOrGhost() return dead end
local inst, isPlayer = "none", false
function IsInInstance() return inst ~= "none", inst end
function UnitIsPlayer() return isPlayer end
function GetTime() return 100 end
local function Widget()
    local w = { shown = true, alpha = 1 }
    local mt = { __index = function(t, k) return function() end end }
    w.Show = function(s) s.shown = true end
    w.Hide = function(s) s.shown = false end
    w.SetShown = function(s, v) s.shown = v and true or false end
    w.SetAlpha = function(s, a) s.alpha = a end
    w.GetHeight = function() return 37 end
    w.GetEffectiveScale = function() return 1 end
    w.CreateTexture = function() local t = setmetatable({}, mt); t.SetDesaturated = function(s, d) s.desat = d end; return t end
    return setmetatable(w, mt)
end
local handler
function CreateFrame(kind, name) local f = Widget(); if name then _G[name] = f end
    if kind == "Frame" and not handler then f.SetScript = function(_, _, fn) handler = fn end end; return f end
UIParent = Widget()
ECME_CDMBar_buffs = Widget()
EllesmereUIDB = { activeProfile = "Naowh", profiles = { Naowh = { addons = { EllesmereUICooldownManager = { cdmBars = { bars = {
    { key = "cooldowns" }, { key = "buffs", iconSize = 44, iconShape = "cropped", iconCropPercent = 8, spacing = 2 } } } } } } } }
C_Timer = { After = function() end }
local root = { Off = function() return false end }
assert(loadfile("MirogaUtilities/Modules/TargetDebuffs.lua"))("MirogaUtilities", root)
local td = root.TargetDebuffs
local self = { UnregisterEvent = function() end, RegisterEvent = function() end, RegisterUnitEvent = function() end }
handler(self, "ADDON_LOADED", "MirogaUtilities")
handler(self, "PLAYER_ENTERING_WORLD")
local demo, ff = td.SLOTS[1], td.SLOTS[2]
ok(td.Find(demo) == nil, "nothing on target")
list = { { name = "Demoralizing Roar", sourceUnit = "player", isFromPlayerOrPlayerPet = true, icon = 5 } }
ok(td.Find(demo) == nil, "my own roar: not shown (EUI bar shows it)")
list = { { name = "Demoralizing Roar", sourceUnit = "player", isFromPlayerOrPlayerPet = true },
    { name = "Demoralizing Shout", sourceUnit = "party1", isFromPlayerOrPlayerPet = false, icon = 7, expirationTime = 30, duration = 30 } }
ok(td.Find(demo) and td.Find(demo).icon == 7, "a warrior's shout: shown")
list = { { name = "Faerie Fire", sourceUnit = SECRET, isFromPlayerOrPlayerPet = false } }
ok(td.Find(ff) == nil, "unknown caster: not shown")
list = { { name = "Faerie Fire (Feral)", sourceUnit = "raid3", isFromPlayerOrPlayerPet = false } }
ok(td.Find(ff) ~= nil, "another druid's feral FF: shown")
list = { SECRET }
ok(td.Find(ff) == nil, "secret aura: not shown")
local w, h, gap = td.BarGeometry()
ok(h == 37 and math.abs(w - 37 / 0.84) < 0.01, "icon size from the bar height and crop")
ok(td.TargetWanted(), "attackable target wanted")
attack = false; ok(not td.TargetWanted(), "friendly target not wanted"); attack = true
inst = "pvp"; ok(not td.TargetWanted(), "battleground: no row"); inst = "party"
isPlayer = true; ok(not td.TargetWanted(), "player target: no row"); isPlayer = false
list = {}
td.Update(); ok(not _G.MirogaTargetDebuffs.shown, "nothing foreign: row hidden")
list = { { name = "Demoralizing Shout", sourceUnit = "party1", isFromPlayerOrPlayerPet = false } }
td.Update(); ok(_G.MirogaTargetDebuffs.shown, "foreign shout: row shown")
print(n .. " checks, " .. bad .. " failures"); os.exit(bad == 0 and 0 or 1)
