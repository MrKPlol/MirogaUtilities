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

print(n .. " checks, " .. bad .. " failures"); os.exit(bad == 0 and 0 or 1)
