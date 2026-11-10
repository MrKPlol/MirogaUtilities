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
root.FlagPlates.Slash = function(m) calls.flag = m end
root.FlagPlates.ToggleTarget = function() calls.target = true end
root.CombatText.Slash = function(m) calls.text = m end
local mu = SlashCmdList.MIROGAUTILITIES
mu(""); ok(shown, "panel opens"); mu(""); ok(not shown, "panel closes")
mu("target"); ok(calls.target, "target")
mu("flag add Void Fury"); ok(calls.flag == "add Void Fury", "flag args")
mu("TEXT test"); ok(calls.text == "test", "text args")
mu("nope"); ok(calls.say and calls.say:find("/mu target"), "help")
print(n .. " checks, " .. bad .. " failures"); os.exit(bad == 0 and 0 or 1)
