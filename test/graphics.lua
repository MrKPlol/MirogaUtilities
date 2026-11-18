-- luajit test/graphics.lua  (run from repo root)
local n, bad = 0, 0
local function ok(c, m) n = n + 1; if not c then bad = bad + 1; print("FAIL " .. m) end end

local handler, frame, timers = nil, nil, {}
function CreateFrame()
    frame = { RegisterEvent = function() end, UnregisterEvent = function() end,
        SetScript = function(_, _, fn) handler = fn end }
    return frame
end
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
local cv = { groundEffectDensity = "48", groundEffectDist = "320", ResampleAlwaysSharpen = "0",
    ResampleSharpness = "0.5", skyCloudLod = "3", ffxGlow = "1", Gamma = "1.000000", Contrast = "50", Brightness = "50" }
local writes = 0
C_CVar = { GetCVar = function(k) return cv[k] end,
    SetCVar = function(k, v) writes = writes + 1; cv[k] = v; return true end }
local said = {}
local root = { Say = function(m) said[#said + 1] = m end, Off = function() return false end }
assert(loadfile("MirogaUtilities/Modules/Graphics.lua"))("MirogaUtilities", root)
local gx = root.Graphics
handler(frame, "ADDON_LOADED", "MirogaUtilities")
ok(gx.db and gx.db.on, "on by default")
handler(frame, "PLAYER_ENTERING_WORLD")
ok(#timers == 1, "apply waits for the client to settle")
ok(cv.groundEffectDensity == "48", "nothing written before the timer")
timers[1]()
ok(cv.groundEffectDensity == "80", "grass density written")
ok(cv.ResampleAlwaysSharpen == "1" and cv.ResampleSharpness == "0.3", "sharpening written")
ok(cv.Gamma == "1.2" and cv.Contrast == "62" and cv.Brightness == "50", "picture written")
ok(gx.db.saved.groundEffectDensity == "48" and gx.db.saved.Gamma == "1.000000", "originals kept")
local before = writes
gx.ApplyAll(true)
ok(writes == before, "no rewrite when values match")
local gamma
for _, s in ipairs(gx.SETTINGS) do if s.cvar == "Gamma" then gamma = s end end
gx.SetValue(gamma, 1.33)
ok(cv.Gamma == "1.35" and gx.db.saved.Gamma == "1.000000", "gamma rounded to step, original kept")
gx.Restore()
ok(cv.groundEffectDensity == "48" and cv.Gamma == "1.000000" and cv.ResampleSharpness == "0.5", "restore puts originals back")
ok(not gx.db.on and next(gx.db.saved) == nil, "restore stops writing")
gx.ApplyAll(true)
ok(cv.groundEffectDensity == "48", "off: nothing written")
print(n .. " checks, " .. bad .. " failures"); os.exit(bad == 0 and 0 or 1)
