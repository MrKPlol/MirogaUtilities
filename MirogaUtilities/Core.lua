-- Module switchboard and slash commands. OptionalDeps load the standalone
-- addons first, so a module stays off while its standalone addon is still
-- enabled. The window lives in Hub.lua, which loads after the modules.
local _, root = ...

root.ACCENT = { 0.25, 0.88, 0.82 } -- turquoise, same as the flagged plates
root.ACCENT_HEX = "40e0d0"

local function Say(text)
    DEFAULT_CHAT_FRAME:AddMessage("|cff" .. root.ACCENT_HEX .. "Miroga Utilities:|r " .. text)
end
root.Say = Say

-- ---------------------------------------------------------------------------
-- module switchboard: MirogaUtilitiesDB.off[key] = true keeps a module from
-- starting at the next login or reload. Every module asks once, in its own
-- first event after the saved variables are in, and then stays silent.

root.MODULES = {
    { key = "CombatText", label = "Combat text", desc = "Damage, heals, buffs and debuffs on you, in movable boxes." },
    { key = "Powershift", label = "Powershift", desc = "Form to form in one key press, travel form included." },
    { key = "FlagPlates", label = "Flagged players", desc = "Turquoise nameplates, alerts and statistics for players on your list." },
    { key = "AutoMark", label = "Auto mark", desc = "Raid marks on your own group." },
    { key = "VendorCoin", label = "Vendor coin", desc = "Red coin on items the vendor pays more for than the AH." },
    { key = "Stockpile", label = "Stockpile", desc = "Hold raid materials, cheap price hints, snipe alerts." },
    { key = "NaowhTweaks", label = "Naowh tweaks", desc = "Scrolls and buff drinks only in dungeons and raids." },
    { key = "UpdateMerge", label = "Update merge", desc = "After a NaowhUI update: OLD or NEW for every changed setting." },
    { key = "LayerHost", label = "LayerSwap host", desc = "LayerSwap's Host off after login, unless you turned it on yourself." },
    { key = "Weather", label = "Weather", desc = "One key: storms low, again: your weather back." },
    { key = "LoginQuiet", label = "Login quiet", desc = "No addon spam in the chat after login or reload." },
}

-- the saved choice (false until the saved variables are loaded)
function root.IsOff(key)
    local db = MirogaUtilitiesDB
    return type(db) == "table" and type(db.off) == "table" and db.off[key] == true or false
end

-- a module's gate: true = off, its frame is silenced for this session
function root.Off(key, frame)
    if not root.IsOff(key) then return false end
    root.offNow = root.offNow or {}
    root.offNow[key] = true
    if frame and frame.UnregisterAllEvents then frame:UnregisterAllEvents() end
    return true
end

-- off for this session (the switch may already say otherwise until reload)
function root.Stopped(key) return root.offNow and root.offNow[key] or false end

function root.SetModule(key, on)
    if type(MirogaUtilitiesDB) ~= "table" then MirogaUtilitiesDB = {} end
    MirogaUtilitiesDB.off = MirogaUtilitiesDB.off or {}
    MirogaUtilitiesDB.off[key] = (not on) or nil
end

local standalone = {}
for module, addon in pairs({ CombatText = "KPCombatText", FlagPlates = "KPFlagPlates" }) do
    if C_AddOns.IsAddOnLoaded(addon) then
        standalone[#standalone + 1] = addon
    else
        root[module] = {}
    end
end

local notice = CreateFrame("Frame")
notice:RegisterEvent("PLAYER_LOGIN")
notice:SetScript("OnEvent", function()
    if #standalone > 0 then
        table.sort(standalone)
        Say("Disable " .. table.concat(standalone, " and ") .. " in the addon list. Those modules are off until then.")
    end
end)

-- ---------------------------------------------------------------------------
-- slash commands: one letter each, the old long forms still work

local TEXT_SHORT = { m = "anchor", p = "test", b = "blizz" }
local PAGES = { o = "text", e = "events", a = "alerts", s = "shift", u = "merge" }

local function Open(page)
    if root.OpenHub then root.OpenHub(page) end
end

local COMMAND_MODULE = {
    t = "FlagPlates", target = "FlagPlates", f = "FlagPlates", flag = "FlagPlates", a = "FlagPlates",
    m = "CombatText", p = "CombatText", b = "CombatText", c = "CombatText", text = "CombatText",
    o = "CombatText", e = "CombatText",
    r = "AutoMark", mark = "AutoMark", q = "LoginQuiet", quiet = "LoginQuiet",
    w = "Weather", weather = "Weather", h = "Stockpile", hold = "Stockpile",
    v = "VendorCoin", vendor = "VendorCoin", s = "Powershift", u = "UpdateMerge",
}

SLASH_MIROGAUTILITIES1 = "/mu"
SLASH_MIROGAUTILITIES2 = "/miroga"
SlashCmdList.MIROGAUTILITIES = function(msg)
    local command, rest = strtrim(msg or ""):match("^(%S*)%s*(.-)$")
    command = strlower(command)
    local ct, fp = root.CombatText, root.FlagPlates
    local module = COMMAND_MODULE[command]
    if module and root.Stopped(module) then
        Say(module .. " is off. Turn it on in /mu > Home.")
        return
    end
    if command == "" then
        if root.ToggleHub then root.ToggleHub() end
    elseif command == "t" or command == "target" then
        if fp then fp.ToggleTarget() end
    elseif command == "f" or command == "flag" then
        if not fp then return end
        if rest == "" then Open("players") else fp.Slash(rest) end
    elseif TEXT_SHORT[command] then
        if ct then ct.Slash(TEXT_SHORT[command] .. (rest ~= "" and (" " .. rest) or "")) end
    elseif command == "c" or command == "text" then
        if not ct then return end
        if rest == "" then Open("text") else ct.Slash(TEXT_SHORT[rest] or rest) end
    elseif command == "r" or command == "mark" then
        if rest == "now" and root.AutoMark then root.AutoMark.Apply(true) else Open("marks") end
    elseif command == "q" or command == "quiet" then
        if not root.LoginQuiet then return end
        if rest == "" then root.LoginQuiet.Show() else Open("quiet") end
    elseif command == "w" or command == "weather" then
        if not root.Weather then return end
        if rest == "" then root.Weather.Toggle() else Open("weather") end
    elseif command == "h" or command == "hold" then
        if not root.Stockpile then return end
        if rest == "o" then Open("stockpile")
        elseif root.Stockpile.Slash(rest) == false then Say("/mu h (item under mouse), /mu h 12.5 (target), /mu h sync, /mu h o") end
    elseif command == "v" or command == "vendor" then
        if not root.VendorCoin then return end
        if rest == "" then root.VendorCoin.Explain() else Open("vendor") end
    elseif command == "poi" then
        if root.QuestPOI then root.QuestPOI.Toggle() end
    elseif PAGES[command] then
        Open(PAGES[command])
    else
        Say("/mu (window), /mu t (flag target), /mu f (players), /mu c (combat text), /mu r (auto mark), /mu w (weather low/back), /mu v (vendor or AH), /mu h (hold item), /mu u (update merge), /mu q (hidden login lines), /mu m (move boxes), /mu p (preview)")
    end
end

-- ---------------------------------------------------------------------------
-- empty system lines: Forever sends some CHAT_MSG_SYSTEM events with an empty
-- text (seen after joining a guild), which show up as a bare timestamp.
-- Only lines that are exactly empty are dropped; secret texts pass untouched.

local issecret = issecretvalue or function() return false end
local addFilter = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
if addFilter then
    addFilter("CHAT_MSG_SYSTEM", function(_, _, msg, ...)
        if type(msg) == "string" and not issecret(msg) and not msg:find("%S") then return true end
        return false, msg, ...
    end)
end
