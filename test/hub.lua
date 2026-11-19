-- luajit test/hub.lua  (run from repo root): builds the window with stub
-- frames and checks the sidebar / sub tab wiring.
local n, bad = 0, 0
local function ok(c, m) n = n + 1; if not c then bad = bad + 1; print("FAIL " .. m) end end

local texts, failures, shownLog = {}, {}, {}
local stub
local mt = {}
mt.__index = function(self, k)
    if k == "GetStringWidth" or k == "GetHeight" or k == "GetWidth" or k == "GetVerticalScroll" then return function() return 50 end end
    if k == "SetText" then return function(s, t) rawset(s, "_text", t); texts[#texts + 1] = t
        if type(t) == "string" and t:find("failed to build") then failures[#failures + 1] = t end end end
    if k == "SetShown" then return function(s, v) rawset(s, "_shown", v) end end
    if k == "Show" then return function(s) rawset(s, "_shown", true) end end
    if k == "Hide" then return function(s) rawset(s, "_shown", false) end end
    if k == "IsShown" or k == "IsVisible" then return function(s) return rawget(s, "_shown") end end
    if k == "SetScript" then return function(s, ev, fn) rawset(s, "_" .. ev, fn) end end
    return stub()
end
mt.__call = function() return stub() end
for _, m in ipairs({ "__add", "__sub", "__mul", "__div", "__unm" }) do mt[m] = function() return 0 end end
mt.__lt = function() return false end
mt.__le = function() return false end
mt.__concat = function(a, b) return tostring(type(a) == "table" and "" or a) .. tostring(type(b) == "table" and "" or b) end
stub = function() return setmetatable({}, mt) end

setmetatable(_G, { __index = function(_, k) return stub() end })
CreateFrame = function() return stub() end
STANDARD_TEXT_FONT = "font"
UISpecialFrames = {}
C_AddOns = { GetAddOnMetadata = function() return "1.0" end }
Settings = nil

local root = { ACCENT = { 0, 1, 1 }, ACCENT_HEX = "40e0d0", Say = function() end }
root.Stopped = function(m) return m == "Weather" end
root.CombatText, root.FlagPlates = { }, { }
for _, m in ipairs({ "Powershift", "AutoMark", "FriendTips", "VendorCoin", "Stockpile", "NaowhTweaks", "UpdateMerge", "LayerHost", "AddonFixes", "TargetDebuffs", "Weather", "Graphics", "BGQuiet", "LoginQuiet" }) do
    root[m] = setmetatable({}, { __index = function() return stub() end })
end
root.MODULES = { { key = "Weather", label = "Weather", desc = "w" }, { key = "Graphics", label = "Graphics", desc = "g" } }
root.IsOff = function() return false end
assert(loadfile("MirogaUtilities/Hub.lua"))("MirogaUtilities", root)

ok(type(root.OpenHub) == "function", "OpenHub exported")
local okRun, err = pcall(root.OpenHub, "weather")
ok(okRun, "window builds: " .. tostring(err))
local function has(t) for _, v in ipairs(texts) do if v == t then return true end end return false end
for _, label in ipairs({ "Combat text", "Flagged players", "Vendor & stockpile", "Naowh", "World",
    "Display", "Events & colors", "List", "Plates & alerts", "Graphics", "Weather", "LayerSwap", "Login", "Battlegrounds", "Addon fixes", "Quiet chat", "Target debuffs", "Group & friends", "Friend tooltips" }) do
    ok(has(label), "label " .. label)
end
ok(has("Stockpile"), "stockpile sub tab")
ok(has("This module is off. Switch it on next to the title, then reload."), "stopped weather page says so")
ok(has("Search settings"), "search box in the sidebar")
ok(has("|cffffcc00on after reload|r"), "header switch: weather on, but stopped this session")
ok(has("on"), "header switch: graphics on")
ok(has("WORLD & CHAT"), "home groups switches like the sidebar")
ok(pcall(root.OpenHub, "combat"), "sidebar key opens its first page")
ok(pcall(root.OpenHub, "nope"), "unknown key falls back home")
print(("%d checks, %d failures"):format(n, bad))
os.exit(bad == 0 and 0 or 1)
