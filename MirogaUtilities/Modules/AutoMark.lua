-- Auto raid marks for your own group. Up to four players, each with a chosen
-- raid mark (plus an optional one for you). When someone joins the party and
-- everyone in it is on the list (no stranger), the marks are ready.
--
-- Checked against the Forever UI source (RaidMarkersDocumentation.lua):
-- SetRaidTarget HasRestrictions (addons may not call it) and
-- GetRaidTargetIndex has SecretReturns, so an addon can never read a mark.
-- The marks therefore go on through Blizzard's secure "raidtarget" action
-- with action "set": it checks the mark in secure code and only sets it,
-- never toggles it off like /tm does. A "Mark group" button (also bindable
-- under Keybindings > AddOns) clicks one hidden mark button per player.
-- Which marks this session already set is remembered per GUID, so the
-- button pops up only for players that still need one.
local _, root = ...
local am = {}
root.AutoMark = am

local issecret = issecretvalue or function() return false end
local strlower, strmatch, format = string.lower, string.match, string.format

local SLOTS = 4
local BUTTON = "MirogaAutoMarkButton"
_G["BINDING_NAME_CLICK " .. BUTTON .. ":LeftButton"] = "Auto Mark: mark group"

am.SLOTS = SLOTS
am.DEFAULTS = { enabled = true, self = 0, slots = {} }
local DEFAULT_MARKS = { 1, 2, 3, 4 } -- star, circle, diamond, triangle

function am.MarkText(i)
    if not i or i == 0 then return "None" end
    return format("|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_%d:14|t  %s", i, _G["RAID_TARGET_" .. i] or ("Mark " .. i))
end

function am.MarkChoices()
    local list = { { value = 0, text = "None" } }
    for i = 1, 8 do list[#list + 1] = { value = i, text = am.MarkText(i) } end
    return list
end

local function Say(text)
    if root.Say then root.Say(text) end
end

-- ---------------------------------------------------------------------------
-- saved settings

local function InitDB()
    if type(MirogaAutoMarkDB) ~= "table" then MirogaAutoMarkDB = {} end
    local db = MirogaAutoMarkDB
    if db.enabled == nil then db.enabled = true end
    if type(db.self) ~= "number" then db.self = 0 end
    if type(db.slots) ~= "table" then db.slots = {} end
    for i = 1, SLOTS do
        local s = db.slots[i]
        if type(s) ~= "table" then
            s = {}
            db.slots[i] = s
        end
        if type(s.name) ~= "string" then s.name = "" end
        if type(s.mark) ~= "number" then s.mark = DEFAULT_MARKS[i] end
    end
    if type(db.applied) ~= "table" then db.applied = {} end -- GUID -> mark our click set
    am.db = db
    am.applied = db.applied
end

-- "First" matches every surname, "First Surname" only that character.
local function Parse(text)
    text = strmatch(text or "", "^%s*(.-)%s*$")
    if text == "" then return nil end
    local first, last = strmatch(text, "^([^%s%-]+)[%s%-]+([^%s%-]+)")
    if not first then return strlower(text), nil end
    return strlower(first), strlower(last)
end

-- Plain names of a unit, nil while secret or not known yet.
local function UnitNames(unit)
    local name, surname = UnitName(unit)
    if issecret(name) or issecret(surname) then return nil end
    if type(name) ~= "string" or name == "" or name == UNKNOWNOBJECT then return nil end
    return strlower(name), type(surname) == "string" and surname ~= "" and strlower(surname) or nil
end

-- Slot index for a unit, or nil when nobody on the list matches.
local function MatchSlot(unit)
    local name, surname = UnitNames(unit)
    if not name then return nil, true end -- unknown yet
    local best
    for i, s in ipairs(am.db.slots) do
        local first, last = Parse(s.name)
        if first == name then
            if last and last == surname then return i end
            if not last and not best then best = i end
        end
    end
    return best
end

-- ---------------------------------------------------------------------------
-- the check: only your listed players in the party, nobody else

-- Returns missing and wanted marks as { unit, mark } pairs, or nil + reason.
function am.Evaluate()
    local db = am.db
    if not db or not db.enabled then return nil, "off" end
    if IsInRaid() then return nil, "raid" end
    if not IsInGroup() or GetNumSubgroupMembers() == 0 then return nil, "solo" end
    local wanted, unknown = {}, false
    for i = 1, 4 do
        local unit = "party" .. i
        if UnitExists(unit) then
            local slot, notKnown = MatchSlot(unit)
            if notKnown then
                unknown = true
            elseif not slot then
                return nil, "stranger"
            elseif db.slots[slot].mark > 0 then
                wanted[#wanted + 1] = { unit, db.slots[slot].mark }
            end
        end
    end
    if unknown then return nil, "unknown" end
    if db.self > 0 then wanted[#wanted + 1] = { "player", db.self } end
    -- the current mark is unreadable (secret): go by what our clicks set
    local missing = {}
    for _, w in ipairs(wanted) do
        local guid = UnitGUID(w[1])
        if not (guid and not issecret(guid) and am.applied[guid] == w[2]) then
            missing[#missing + 1] = w
        end
    end
    return missing, wanted
end

-- ---------------------------------------------------------------------------
-- secure button: the visible popup and the key binding

local button = CreateFrame("Button", BUTTON, UIParent, "SecureActionButtonTemplate, BackdropTemplate")
button:SetSize(150, 34)
button:SetPoint("TOP", UIParent, "TOP", 0, -180)
button:SetFrameStrata("HIGH")
button:SetClampedToScreen(true)
button:SetMovable(true)
-- fire once, on release, for mouse and key alike (SecureActionButton_OnClick)
button:SetAttribute("useOnKeyDown", false)
button:RegisterForClicks("LeftButtonUp")
button:RegisterForDrag("RightButton")
button:SetAttribute("type", "macro")
button:SetAttribute("macrotext", "")
button:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
button:SetBackdropColor(0.098, 0.106, 0.114, 0.95)
local A = root.ACCENT or { 0.25, 0.88, 0.82 }
button:SetBackdropBorderColor(A[1], A[2], A[3], 0.9)
button:Hide()

local label = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
label:SetPoint("TOP", 0, -4)
label:SetTextColor(1, 1, 1)
label:SetText("Mark group")
local icons = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
icons:SetPoint("BOTTOM", 0, 4)

local hl = button:CreateTexture(nil, "HIGHLIGHT")
hl:SetAllPoints()
hl:SetColorTexture(A[1], A[2], A[3], 0.15)

button:SetScript("OnDragStart", function(self)
    if not InCombatLockdown() then self:StartMoving() end
end)
button:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, rel, x, y = self:GetPoint()
    am.db.pos = { point, rel, x, y }
end)
button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("Miroga Utilities: Auto Mark")
    GameTooltip:AddLine("Left-click: put the marks on your group.", 1, 1, 1)
    GameTooltip:AddLine("Right-drag: move.", 1, 1, 1)
    GameTooltip:Show()
end)
button:SetScript("OnLeave", GameTooltip_Hide)

-- one hidden secure mark button per player (4 party + you)
local markers = {}
for i = 1, 5 do
    local b = CreateFrame("Button", BUTTON .. i, UIParent, "SecureActionButtonTemplate")
    b:SetAttribute("type", "raidtarget")
    b:SetAttribute("action", "set")
    b:SetAttribute("useOnKeyDown", false) -- /click sends a release
    b:RegisterForClicks("AnyUp")
    b:Hide()
    markers[i] = b
end

-- After a click the marks are on: hide until a new player joins. The key
-- binding keeps working while hidden and simply sets the marks again.
local lastMarked = {}
button:HookScript("PostClick", function(_, _, down)
    if down then return end
    for _, m in ipairs(lastMarked) do
        local guid = UnitGUID(m[1])
        if guid and not issecret(guid) then am.applied[guid] = m[2] end
    end
    if InCombatLockdown() then
        am.hideAfterCombat = true
        am.WaitForCombat()
    else
        button:Hide()
    end
end)

local function RestorePosition()
    local p = am.db.pos
    if type(p) == "table" and p[1] then
        button:ClearAllPoints()
        button:SetPoint(p[1], UIParent, p[2] or p[1], p[3] or 0, p[4] or 0)
    end
end

function am.ResetPosition()
    am.db.pos = nil
    if InCombatLockdown() then return end
    button:ClearAllPoints()
    button:SetPoint("TOP", UIParent, "TOP", 0, -180)
end

local pending = false     -- a change waits for combat to end
local events = CreateFrame("Frame")

function am.WaitForCombat()
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
end

local function HideButton()
    button:Hide()
end

local function Disarm()
    lastMarked = {}
    button:SetAttribute("macrotext", "")
    button:Hide()
end

-- Apply the check. `announce` prints why nothing happened (manual check).
-- Returns true when the popup is up.
function am.Apply(announce)
    if InCombatLockdown() then
        pending = true
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        return false
    end
    local missing, wanted = am.Evaluate()
    if not missing or #wanted == 0 then
        local reason = wanted
        Disarm()
        if announce then
            if missing then Say("Nobody on your list has a mark chosen.")
            elseif reason == "stranger" then Say("Someone in the party is not on your list, no marks.")
            elseif reason == "unknown" then Say("Names are not known yet, try again in a moment.")
            elseif reason == "raid" then Say("Auto Mark only works in a party, not in a raid.")
            elseif reason == "off" then Say("Auto Mark is off (/mu r).")
            else Say("You are not in a party.") end
        end
        return false, reason
    end
    -- arm every wanted mark ("set" never removes one), so the key always works
    local lines, marks = {}, {}
    lastMarked = wanted
    for i, m in ipairs(wanted) do
        markers[i]:SetAttribute("unit", m[1])
        markers[i]:SetAttribute("marker", m[2])
        lines[#lines + 1] = "/click " .. BUTTON .. i
        marks[#marks + 1] = format("|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_%d:12|t", m[2])
    end
    button:SetAttribute("macrotext", table.concat(lines, "\n"))
    icons:SetText(table.concat(marks, " "))
    -- pop up only when someone still needs a mark, or on a manual check
    if #missing == 0 and not announce then
        button:Hide()
        return false, "done"
    end
    local wasShown = button:IsShown()
    button:Show()
    if not wasShown then
        local key = GetBindingKey("CLICK " .. BUTTON .. ":LeftButton")
        Say("Only your people in the group: click |cff" .. (root.ACCENT_HEX or "40e0d0") .. "Mark group|r"
            .. (key and (" or press " .. GetBindingText(key)) or "") .. ".")
    end
    return true
end

-- ---------------------------------------------------------------------------
-- events: check when a new player joins, keep an open popup up to date

local known = {}          -- GUIDs of the party at the last roster update
local retries = 0

local function Snapshot()
    local now, added = {}, false
    for i = 1, 4 do
        local guid = UnitGUID("party" .. i)
        if guid and not issecret(guid) then
            now[guid] = true
            if not known[guid] then added = true end
        end
    end
    known = now
    return added
end

local function Check()
    local up, reason = am.Apply(false)
    -- freshly joined players can show up as "Unknown" for a moment
    if not up and reason == "unknown" and retries < 5 then
        retries = retries + 1
        C_Timer.After(1, Check)
    end
end

events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, arg)
    if event == "ADDON_LOADED" then
        if arg ~= "MirogaUtilities" then return end
        self:UnregisterEvent("ADDON_LOADED")
        InitDB()
        RestorePosition()
        self:RegisterEvent("PLAYER_ENTERING_WORLD")
        self:RegisterEvent("GROUP_ROSTER_UPDATE")
    elseif event == "PLAYER_ENTERING_WORLD" then
        Snapshot() -- a reload in a group is not a new invite
        am.Apply(false) -- arm the key binding again (pops up only if a mark is missing)
    elseif event == "GROUP_ROSTER_UPDATE" then
        if not IsInGroup() then wipe(am.applied) end -- group gone, marks gone
        if Snapshot() then
            retries = 0
            C_Timer.After(0.5, Check)
        else
            am.Apply(false) -- someone left: units shifted, re-arm or disarm
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        if am.hideAfterCombat then
            am.hideAfterCombat = false
            HideButton()
        end
        if pending then
            pending = false
            am.Apply(false)
        end
    end
end)

function am.SetEnabled(on)
    am.db.enabled = on and true or false
    if InCombatLockdown() then
        pending = true
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
    elseif not on then
        Disarm()
    end
end
