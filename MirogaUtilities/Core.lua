-- Module switchboard and the /mu command. The window lives in Hub.lua,
-- which loads after the modules.
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
    { key = "VendorCoin", label = "Vendor coin & stockpile", desc = "Red coin when the vendor pays more than the AH; hold raid materials, cheap hints, snipes." },
    { key = "NaowhTweaks", label = "Naowh tweaks", desc = "Scrolls and buff drinks only in dungeons and raids." },
    { key = "UpdateMerge", label = "Update merge", desc = "After a NaowhUI update: OLD or NEW for every changed setting." },
    { key = "LayerHost", label = "LayerSwap host", desc = "LayerSwap's Host off after login, unless you turned it on yourself." },
    { key = "Weather", label = "Weather", desc = "One key: storms low, again: your weather back." },
    { key = "Graphics", label = "Graphics", desc = "Hidden graphics values (grass, sharpening, gamma) written after every login." },
    { key = "BGQuiet", label = "BG quiet", desc = "In battlegrounds: BugSack muted, join lines, crafting lines, channel notices and \"+\" spam hidden." },
    { key = "AddonFixes", label = "Addon fixes", desc = "ProcDoc, WIM, Naowh Discovery and HappyCamper errors in battlegrounds stopped at the source." },
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

root.CombatText, root.FlagPlates = {}, {}

-- ---------------------------------------------------------------------------
-- slash commands: everything lives in the window. Only flagging the target
-- stays a command, so it works from a macro.

SLASH_MIROGAUTILITIES1 = "/mu"
SlashCmdList.MIROGAUTILITIES = function(msg)
    local command = strlower(strtrim(msg or ""))
    if command == "t" then
        if root.Stopped("FlagPlates") then
            Say("Flagged players is off. Turn it on in /mu > Home.")
        else
            root.FlagPlates.ToggleTarget()
        end
    elseif root.ToggleHub then
        root.ToggleHub()
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
