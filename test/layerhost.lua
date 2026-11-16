-- luajit test/layerhost.lua  (run from repo root)
local n, bad = 0, 0
local function ok(c, m) n = n + 1; if not c then bad = bad + 1; print("FAIL " .. m) end end

local handler, clickFn
function CreateFrame()
    return { RegisterEvent = function() end, UnregisterEvent = function() end,
        SetScript = function(_, _, fn) handler = fn end }
end
WorldFrame = { HookScript = function(_, _, fn) clickFn = fn end }
local now, combat, group = 1000, false, false
function time() return now end
function InCombatLockdown() return combat end
function IsInGroup() return group end
local said = {}
local root = { Say = function(m) said[#said + 1] = m end, Off = function() return false end }
local slash = {}
LayerSwapDB = { hosting = true }
SlashCmdList = { LAYERSWAP = function(msg)
    slash[#slash + 1] = msg
    if msg == "off" then LayerSwapDB.hosting = false elseif msg == "on" then LayerSwapDB.hosting = true end
end }
MirogaUtilitiesDB = nil
assert(loadfile("MirogaUtilities/Modules/LayerHost.lua"))("MirogaUtilities", root)
local lh = root.LayerHost
local function login(isLogin) handler({ RegisterEvent = function() end, UnregisterEvent = function() end }, "PLAYER_ENTERING_WORLD", isLogin) end
local function logout() handler(nil, "PLAYER_LOGOUT") end
local function click() if clickFn then clickFn() end end

handler({ UnregisterEvent = function() end, RegisterEvent = function() end }, "ADDON_LOADED", "MirogaUtilities")
ok(lh.db.enabled and lh.db.wantHost == false, "defaults")

-- login: LayerSwap turned Host on; off at the first click, not before
login(true)
ok(lh.armed and #slash == 0, "armed, nothing sent without a click")
combat = true; click(); ok(LayerSwapDB.hosting == true, "not in combat")
combat = false; click()
ok(LayerSwapDB.hosting == false and slash[1] == "off", "first click turns Host off")
ok(not lh.armed and said[#said]:find("Host is off"), "said once, disarmed")
click(); ok(#slash == 1, "later clicks do nothing")

-- you turn it on yourself, log out: it stays your choice
SlashCmdList.LAYERSWAP("on")
logout()
ok(lh.db.wantHost == true, "your own on is remembered")
login(true); click()
ok(LayerSwapDB.hosting == true and not lh.armed, "next login: stays on")

-- you turn it off again
SlashCmdList.LAYERSWAP("off"); logout()
ok(lh.db.wantHost == false, "your off is remembered")

-- LayerSwap's own ask holds Host on (forced + 4 min lock): hands off
LayerSwapDB.hosting = true
login(true)
LayerSwapDB.hostForced, LayerSwapDB.hostLockUntil = "Miroga", now + 240
local count = #slash
click(); ok(#slash == count and LayerSwapDB.hosting == true, "no off during LayerSwap's 4 min")
logout(); ok(lh.db.wantHost == false, "a forced on is not your choice")
LayerSwapDB.hostForced, LayerSwapDB.hostLockUntil = nil, nil
now = now + 300
click(); ok(LayerSwapDB.hosting == false, "after the lock: the next click turns it off")

-- in a group: wait
LayerSwapDB.hosting = true; login(true); group = true
count = #slash; click(); ok(#slash == count, "not while in a group")
group = false; click(); ok(LayerSwapDB.hosting == false, "after the group")

-- a /reload is no login
LayerSwapDB.hosting = true; login(false)
ok(not lh.armed, "reload does nothing")
-- switch off: LayerSwap decides
lh.Set("enabled", false); LayerSwapDB.hosting = true; login(true)
ok(not lh.armed, "module setting off: hands off")

print(n .. " checks, " .. bad .. " failures"); os.exit(bad == 0 and 0 or 1)
