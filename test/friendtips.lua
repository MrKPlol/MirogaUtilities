-- luajit test/friendtips.lua  (run from repo root)
local n, bad = 0, 0
local function ok(c, m) n = n + 1; if not c then bad = bad + 1; print("FAIL " .. m) end end

local handler
function CreateFrame() return { RegisterEvent = function() end, UnregisterEvent = function() end,
    SetScript = function(_, _, fn) handler = fn end } end
WOW_PROJECT_ID, BNET_CLIENT_WOW = 18, "WoW"
CLASS_ICON_TCOORDS = { DRUID = { 0.74, 0.98, 0, 0.25 } }
RAID_CLASS_COLORS = { DRUID = { r = 1, g = 0.49, b = 0.04 } }
LOCALIZED_CLASS_NAMES_MALE = { DRUID = "Druid" }
function GetQuestDifficultyColor() return { r = 1, g = 1, b = 0 } end
local shownWith
EllesmereUI = { ShowWidgetTooltip = function(label, text, opts) shownWith = { label = label, text = text, opts = opts } end }

local root = { Off = function() return false end, ACCENT_HEX = "40e0d0" }
assert(loadfile("MirogaUtilities/Modules/FriendTips.lua"))("MirogaUtilities", root)
local ft = root.FriendTips
handler({ UnregisterEvent = function() end }, "ADDON_LOADED", "MirogaUtilities")
ok(ft.hooked, "hooked into EllesmereUI.ShowWidgetTooltip")

local online = { accountName = "Karl", isFavorite = true, note = "raid buddy", customMessage = "LF guild",
    gameAccountInfo = { isOnline = true, clientProgram = "WoW", wowProjectID = 18, characterName = "Miroga",
        realmName = "CAMWOWUS2Realm10RPPvP", className = "Druid", raceName = "Night Elf", characterLevel = 40,
        factionName = "Alliance", areaName = "Ashenvale", isInCurrentPlayerGroup = true } }
EllesmereUI.ShowWidgetTooltip({ rec = { info = online } }, "slim", { anchor = "right" })
local t = shownWith.text
for _, want in ipairs({ "Karl", "Miroga", "Level 40", "Night Elf", "Druid", "Alliance", "Ashenvale", "In your group",
    "raid buddy", "LF guild", "PlusManz%-Alliance", "Icons%-Classes", "INV_Misc_Map_01" }) do
    ok(t:find(want), "shows " .. want)
end
ok(not t:find("CAMWOWUS2"), "internal realm name hidden")
ok(shownWith.opts.justify == "LEFT", "left aligned")

ft.Set("icons", false)
EllesmereUI.ShowWidgetTooltip({ rec = { info = online } }, "slim")
ok(not shownWith.text:find("|T"), "icons off: no icons")

local offline = { accountName = "Bob", gameAccountInfo = { isOnline = false } }
EllesmereUI.ShowWidgetTooltip({ rec = { info = offline } }, "slim")
ok(shownWith.text:find("Bob") and shownWith.text:find("Offline"), "offline friend")

EllesmereUI.ShowWidgetTooltip({}, "option help", { anchor = "below" })
ok(shownWith.text == "option help" and shownWith.opts.anchor == "below", "other tooltips untouched")

print(n .. " checks, " .. bad .. " failures"); os.exit(bad == 0 and 0 or 1)
