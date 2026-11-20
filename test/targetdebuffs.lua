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
ok(td.Find(demo) and td.Find(demo).mine, "my own roar: shown")
td.db.mine = false; ok(td.Find(demo) == nil, "mine off: own roar hidden"); td.db.mine = nil
list = { { name = "Demoralizing Roar", sourceUnit = "player", isFromPlayerOrPlayerPet = true },
    { name = "Demoralizing Shout", sourceUnit = "party1", isFromPlayerOrPlayerPet = false, icon = 7, expirationTime = 30, duration = 30 } }
ok(td.Find(demo) ~= nil, "roar + warrior shout: slot shown"); list = { list[2] }; ok(td.Find(demo).icon == 7 and not td.Find(demo).mine, "a warrior's shout alone: shown")
list = { { name = "Faerie Fire", sourceUnit = SECRET, isFromPlayerOrPlayerPet = false } }
ok(td.Find(ff) ~= nil, "unknown caster: shown")
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

-- Moonfire's Always Show in EllesmereUI
EllesmereUIDB.spellAssignments = { profiles = { Naowh = { specProfiles = { [102] = { spellSettingsBuff = {
    [8921] = { alwaysShow = "on" }, [8924] = { alwaysShow = "off" }, [93402] = { alwaysShow = "on" } } } } } } }
local mf = EllesmereUIDB.spellAssignments.profiles.Naowh.specProfiles[102].spellSettingsBuff
ok(td.FixMoonfire() == 1 and mf[8921].alwaysShow == "off", "moonfire always-show switched off")
ok(mf[93402].alwaysShow == "on" and mf[8924].alwaysShow == "off", "other spells untouched")
ok(td.FixMoonfire() == 0, "second run: nothing to do")
td.Set("moonfire", false); ok(mf[8921].alwaysShow == "on" and mf[8924].alwaysShow == "off", "option off: restored only what we changed")
td.Set("moonfire", true); ok(mf[8921].alwaysShow == "off", "option on again")

-- own FF / Roar into the cooldown manager's tracked buffs
Enum = { CooldownViewerCategory = { TrackedBuff = 2 }, CooldownLayoutStatus = { Success = 0 } }
function InCombatLockdown() return false end
local infos = { [199376] = { spellID = 99, category = -2 }, [199443] = { spellID = 770, category = 1 },
    [199455] = { spellID = 8921, category = 2 } }
local saved = 0
CooldownViewerSettings = { IsShown = function() return false end,
    SaveCurrentLayout = function() saved = saved + 1 end,
    GetLayoutManager = function() return {} end,
    GetDataProvider = function() return {
        GetOrderedCooldownIDs = function() return { 199376, 199443, 199455 } end,
        GetCooldownInfoForID = function(_, id) return infos[id] end,
        SetCooldownToCategory = function(_, id, c) infos[id].category = c; return 0 end } end }
td.db.cdmTrack = true
ok(td.FixCDM() == 2 and saved == 1, "roar + ff moved to tracked buffs, saved once")
ok(infos[199376].category == 2 and infos[199443].category == 2 and infos[199455].category == 2, "categories set")
ok(td.FixCDM() == 0 and saved == 1, "second run: nothing to do")
infos[199443].category = 1
function InCombatLockdown() return true end
ok(td.FixCDM() == 0 and td.cdmPending, "in combat: deferred")
function InCombatLockdown() return false end
td.db.cdmTrack = false; ok(td.FixCDM() == 0, "switched off: untouched"); td.db.cdmTrack = true
ok(td.FixCDM() == 1, "after combat: fixed")
print(n .. " checks, " .. bad .. " failures"); os.exit(bad == 0 and 0 or 1)
