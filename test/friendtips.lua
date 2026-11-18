-- luajit test/friendtips.lua  (run from repo root)
local n, bad = 0, 0
local function ok(c, m) n = n + 1; if not c then bad = bad + 1; print("FAIL " .. m) end end

local handler
function CreateFrame() return { RegisterEvent = function() end, UnregisterEvent = function() end,
    SetScript = function(_, _, fn) handler = fn end } end
WOW_PROJECT_ID, BNET_CLIENT_WOW = 18, "WoW"
CLASS_ICON_TCOORDS = { DRUID = { 0.74, 0.98, 0, 0.25 }, ROGUE = { 0.49, 0.73, 0, 0.25 } }
RAID_CLASS_COLORS = { DRUID = { r = 1, g = 0.49, b = 0.04 }, ROGUE = { r = 1, g = 0.96, b = 0.41 } }
LOCALIZED_CLASS_NAMES_MALE = { DRUID = "Druid", ROGUE = "Rogue" }
function GetQuestDifficultyColor() return { r = 1, g = 1, b = 0 } end

-- game tooltip stand-in
local lines, owner, shown = {}, nil, false
GameTooltip = {
    IsForbidden = function() return false end,
    SetOwner = function(_, o) owner = o; lines = {} end,
    ClearAllPoints = function() end, SetPoint = function() end,
    AddLine = function(_, t) lines[#lines + 1] = t end,
    AddDoubleLine = function(_, l, r) lines[#lines + 1] = l .. " || " .. r end,
    Show = function() shown = true end, Hide = function() shown = false end,
    IsOwned = function(_, o) return owner == o end,
}
local euiShown, euiHidden = nil, 0
EllesmereUI = {
    ShowWidgetTooltip = function(label, text, opts) euiShown = { label = label, text = text, opts = opts } end,
    HideWidgetTooltip = function() euiHidden = euiHidden + 1 end,
}
local accounts = {}
C_BattleNet = {
    GetFriendNumGameAccounts = function() return #accounts end,
    GetFriendGameAccountInfo = function(_, i) return accounts[i] end,
}

local root = { Off = function() return false end, ACCENT_HEX = "40e0d0" }
assert(loadfile("MirogaUtilities/Modules/FriendTips.lua"))("MirogaUtilities", root)
local ft = root.FriendTips
handler({ UnregisterEvent = function() end }, "ADDON_LOADED", "MirogaUtilities")
ok(ft.hooked, "hooked into EllesmereUI")
local function all() return table.concat(lines, "\n") end

local druid = { gameAccountID = 1, isOnline = true, clientProgram = "WoW", wowProjectID = 18, characterName = "Miroga",
    realmName = "CAMWOWUS2Realm10RPPvP", className = "Druid", raceName = "Night Elf", characterLevel = 40,
    factionName = "Alliance", areaName = "Ashenvale", isInCurrentPlayerGroup = true }
local rogue = { gameAccountID = 2, isOnline = true, clientProgram = "WoW", wowProjectID = 18, characterName = "Aandy",
    className = "Rogue", raceName = "Human", characterLevel = 12, factionName = "Alliance", areaName = "Elwynn Forest" }
local app = { gameAccountID = 3, isOnline = true, clientProgram = "BSAp", richPresence = "In the app" }
accounts = { app, druid, rogue }
local online = { accountName = "Karl", isFavorite = true, note = "raid buddy", customMessage = "LF guild", gameAccountInfo = druid }
local row = { rec = { index = 1, info = online } }

EllesmereUI.ShowWidgetTooltip(row, "slim", { anchor = "right" })
ok(shown and owner == row, "game tooltip shown on the row")
ok(euiShown == nil, "EllesmereUI's small tooltip not shown")
local t = all()
for _, want in ipairs({ "Karl", "Online", "Miroga", "Level 40", "Night Elf", "Druid", "Alliance", "Ashenvale",
    "In your group", "raid buddy", "LF guild", "PlusManz%-Alliance", "Icons%-Classes", "INV_Misc_Map_01",
    "Aandy", "Level 12", "Elwynn Forest", "In the app" }) do
    ok(t:find(want), "shows " .. want)
end
ok(not t:find("CAMWOWUS2"), "internal realm name hidden")
ok(t:find("Aandy") > t:find("Miroga") and t:find("In the app") > t:find("Aandy"), "both characters before other games")

EllesmereUI.HideWidgetTooltip()
ok(not shown and euiHidden >= 1, "hide hides ours and EllesmereUI's")

ft.Set("icons", false)
EllesmereUI.ShowWidgetTooltip(row, "slim")
ok(not all():find("|T"), "icons off: no icons")

accounts = {}
local offline = { accountName = "Bob", gameAccountInfo = { isOnline = false } }
EllesmereUI.ShowWidgetTooltip({ rec = { index = 2, info = offline } }, "slim")
ok(all():find("Bob") and all():find("Offline"), "offline friend")

euiShown = nil
EllesmereUI.ShowWidgetTooltip({}, "option help", { anchor = "below" })
ok(euiShown and euiShown.text == "option help", "other tooltips untouched")

print(n .. " checks, " .. bad .. " failures"); os.exit(bad == 0 and 0 or 1)
