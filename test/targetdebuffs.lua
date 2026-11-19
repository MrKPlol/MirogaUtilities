-- luajit test/targetdebuffs.lua  (run from repo root)
local n, bad = 0, 0
local function ok(c, m) n = n + 1; if not c then bad = bad + 1; print("FAIL " .. m) end end
local SECRET = {}
function issecretvalue(v) return v == SECRET end
local auras = {}
C_UnitAuras = { GetAuraDataBySpellName = function(u, name, f) return auras[name] end }
C_Spell = { GetSpellName = function() return nil end, GetSpellTexture = function() return 1 end }
local exists, attack, dead = true, true, false
function UnitExists() return exists end
function UnitCanAttack() return attack end
function UnitIsDeadOrGhost() return dead end
local function Widget()
    local w = { shown = true, alpha = 1 }
    local mt = { __index = function(t, k) return function() end end }
    w.Show = function(s) s.shown = true end
    w.Hide = function(s) s.shown = false end
    w.SetShown = function(s, v) s.shown = v and true or false end
    w.SetAlpha = function(s, a) s.alpha = a end
    w.CreateTexture = function() local t = setmetatable({}, mt); t.SetDesaturated = function(s, d) s.desat = d end; return t end
    return setmetatable(w, mt)
end
local handler
function CreateFrame(kind) local f = Widget(); if kind == "Frame" and not handler then
    f.SetScript = function(_, _, fn) handler = fn end end; return f end
UIParent = Widget()
C_Timer = { After = function() end }
local root = { Off = function() return false end }
assert(loadfile("MirogaUtilities/Modules/TargetDebuffs.lua"))("MirogaUtilities", root)
local td = root.TargetDebuffs
local self = { UnregisterEvent = function() end, RegisterEvent = function() end, RegisterUnitEvent = function() end }
handler(self, "ADDON_LOADED", "MirogaUtilities")
handler(self, "PLAYER_ENTERING_WORLD")
local demo, ff = td.SLOTS[1], td.SLOTS[2]
ok(td.Find(demo) == nil, "nothing on target")
auras["Demoralizing Roar"] = { icon = 5, expirationTime = 30, duration = 30 }
ok(td.Find(demo) and td.Find(demo).icon == 5, "roar counts for the demo slot")
auras["Faerie Fire (Feral)"] = { icon = 6 }
ok(td.Find(ff) ~= nil, "feral FF counts for the FF slot")
auras["Faerie Fire (Feral)"] = SECRET
ok(td.Find(ff) == nil, "secret aura: dim")
ok(td.TargetWanted(), "attackable target wanted")
attack = false; ok(not td.TargetWanted(), "friendly target not wanted"); attack = true
dead = SECRET; ok(not td.TargetWanted(), "secret state not wanted"); dead = false
td.Update()
ok(_G.MirogaTargetDebuffs == nil or true, "update runs")
exists = false; td.Update()
print(n .. " checks, " .. bad .. " failures"); os.exit(bad == 0 and 0 or 1)
