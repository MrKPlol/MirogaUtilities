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
local PAGES = { o = "text", e = "events", a = "alerts", s = "shift" }

local function Open(page)
    if root.OpenHub then root.OpenHub(page) end
end

SLASH_MIROGAUTILITIES1 = "/mu"
SLASH_MIROGAUTILITIES2 = "/miroga"
SlashCmdList.MIROGAUTILITIES = function(msg)
    local command, rest = strtrim(msg or ""):match("^(%S*)%s*(.-)$")
    command = strlower(command)
    local ct, fp = root.CombatText, root.FlagPlates
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
    elseif PAGES[command] then
        Open(PAGES[command])
    else
        Say("/mu (window), /mu t (flag target), /mu f (players), /mu c (combat text), /mu r (auto mark), /mu m (move boxes), /mu p (preview)")
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
