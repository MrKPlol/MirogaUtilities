-- luajit test/core.lua  (run from repo root)
local n, bad = 0, 0
local function ok(c, m) n = n + 1; if not c then bad = bad + 1; print("FAIL " .. m) end end
local loaded, calls, shown = {}, {}, false
C_AddOns = { IsAddOnLoaded = function(a) return loaded[a] end }
local function frame()
  local f = {}
  return setmetatable(f, { __index = function(_, k)
    if k == "IsShown" then return function() return shown end end
    if k == "SetShown" then return function(_, v) shown = v end end
    if k == "CreateFontString" then return function() return frame() end end
    return function() end end })
end
CreateFrame = function() return frame() end
UIParent, UISpecialFrames, SlashCmdList = {}, {}, {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) calls.say = m end }
strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
strlower, tinsert = string.lower, table.insert
local root = {}
assert(loadfile("MirogaUtilities/Core.lua"))("MirogaUtilities", root)
root.ToggleHub = function() shown = not shown end
root.FlagPlates.ToggleTarget = function() calls.target = true end
local mu = SlashCmdList.MIROGAUTILITIES
mu(""); ok(shown, "panel opens"); mu(""); ok(not shown, "panel closes")
mu("t"); ok(calls.target, "target")
mu("nope"); ok(shown, "anything else opens the window"); mu("")
ok(SLASH_MIROGAUTILITIES2 == nil, "only /mu")

-- module switches
ok(not root.IsOff("Weather"), "on by default (no saved variables yet)")
MirogaUtilitiesDB = {}
root.SetModule("Weather", false)
ok(root.IsOff("Weather") and MirogaUtilitiesDB.off.Weather == true, "switch off saved")
local frame = { UnregisterAllEvents = function(self) self.silenced = true end }
ok(root.Off("Weather", frame) and frame.silenced, "module gate silences its frame")
ok(root.Stopped("Weather"), "stopped for this session")
root.SetModule("FlagPlates", false); root.Off("FlagPlates"); calls.target, calls.say = nil, nil
mu("t"); ok(not calls.target and calls.say and calls.say:find("is off"), "/mu t of an off module only says so")
root.SetModule("Weather", true)
ok(not root.IsOff("Weather") and MirogaUtilitiesDB.off.Weather == nil, "switch on clears the entry")
ok(root.Stopped("Weather"), "still stopped until reload")
ok(#root.MODULES == 17, "seventeen modules listed")
print(n .. " checks, " .. bad .. " failures"); os.exit(bad == 0 and 0 or 1)
