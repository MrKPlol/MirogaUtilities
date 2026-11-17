-------------------------------------------------------------------------------
--  KPFlagPlates - Core: saved list, name matching
--
--  WoW Forever characters have a first name AND a surname. UnitName(unit)
--  returns them as (name, surname). An entry can be "First" (matches every
--  character with that first name) or "First Surname" (matches exactly).
--
--  Midnight-API restriction: UnitName can return SECRET values (unit identity
--  restricted, e.g. some instanced PvP). Secrets can't be compared or used as
--  table keys, so every read is checked with issecretvalue first and such units
--  are simply never flagged.
-------------------------------------------------------------------------------
local ADDON, root = ...
local ns = root.FlagPlates
if not ns then return end

local issecret = issecretvalue or function() return false end
local strlower, strmatch, strgsub, format = string.lower, string.match, string.gsub, string.format
local tinsert, tsort = table.insert, table.sort

ns.DEFAULTS = {
    color     = { r = 0.25, g = 0.88, b = 0.82 },  -- turquoise (#40E0D0)
    colorBar  = true,    -- colour the health bar
    colorName = true,    -- colour the name text
    alert     = false,   -- chat line when a flagged player's plate appears
    sound     = "raid",  -- ns.SOUNDS key played when one shows up
    repeatGap = 120,     -- seconds before the same player can alert again (0 = once per encounter)
    tooltip   = true,    -- flag + statistics lines in the unit tooltip
}

local function CopyDefaults(dst, src)
    for k, v in pairs(src) do
        if dst[k] == nil then
            if type(v) == "table" then
                dst[k] = {}
                CopyDefaults(dst[k], v)
            else
                dst[k] = v
            end
        elseif type(v) == "table" and type(dst[k]) == "table" then
            CopyDefaults(dst[k], v)
        end
    end
end

function ns.InitDB()
    if type(KPFlagPlatesDB) ~= "table" then KPFlagPlatesDB = {} end
    local db = KPFlagPlatesDB
    if type(db.entries) ~= "table" then db.entries = {} end
    CopyDefaults(db, ns.DEFAULTS)
    ns.db = db
end

-------------------------------------------------------------------------------
--  Names
-------------------------------------------------------------------------------
local function Trim(s) return (strgsub(s, "^%s+", ""):gsub("%s+$", "")) end

-- Character names contain no spaces or hyphens, so both separate the parts.
-- Returns first, surname (surname nil when not given).
function ns.ParseName(text)
    if type(text) ~= "string" then return nil end
    text = Trim(text)
    if text == "" then return nil end
    local first, rest = strmatch(text, "^([^%s%-]+)[%s%-]+(.+)$")
    if not first then return text, nil end
    local last = strmatch(rest, "^([^%s%-]+)")
    return first, last
end

local function Key(first, last)
    return strlower(first) .. "|" .. (last and last ~= "" and strlower(last) or "")
end
ns.Key = Key

function ns.DisplayName(e)
    if e.last and e.last ~= "" then return e.first .. " " .. e.last end
    return e.first
end

-- Entry for (name, surname) or nil. Exact "first|surname" wins over first-only.
function ns.Lookup(name, surname)
    if type(name) ~= "string" or name == "" then return nil end
    local entries = ns.db.entries
    if type(surname) == "string" and surname ~= "" then
        local e = entries[Key(name, surname)]
        if e then return e end
    end
    return entries[Key(name)]
end

-- Safe read of a unit's name: nil unless both parts are plain (non-secret).
function ns.UnitNames(unit)
    if not unit or not UnitExists(unit) then return nil end
    local isPlayer = UnitIsPlayer(unit)
    if issecret(isPlayer) or not isPlayer then return nil end
    local name, surname = UnitName(unit)
    if issecret(name) or issecret(surname) then return nil end
    if type(name) ~= "string" or name == "" or name == UNKNOWNOBJECT then return nil end
    if type(surname) ~= "string" then surname = nil end
    return name, surname
end

function ns.IsUnitFlagged(unit)
    local name, surname = ns.UnitNames(unit)
    if not name then return nil end
    return ns.Lookup(name, surname)
end

-------------------------------------------------------------------------------
--  List operations (every change refreshes plates + menu)
-------------------------------------------------------------------------------
function ns.Changed()
    if ns.RefreshAllPlates then ns.RefreshAllPlates() end
    if ns.RefreshUI then ns.RefreshUI() end
end

function ns.Add(first, last)
    if not first or first == "" then return false end
    local k = Key(first, last)
    if ns.db.entries[k] then return false end
    ns.db.entries[k] = { first = first, last = (last ~= "" and last) or nil, added = time() }
    ns.Changed()
    return true
end

function ns.Remove(key)
    if not ns.db.entries[key] then return false end
    ns.db.entries[key] = nil
    ns.Changed()
    return true
end

function ns.ClearAll()
    wipe(ns.db.entries)
    ns.Changed()
end

function ns.SortedKeys(filter)
    local keys = {}
    filter = filter and filter ~= "" and strlower(filter) or nil
    for k, e in pairs(ns.db.entries) do
        if not filter or string.find(strlower(ns.DisplayName(e)), filter, 1, true) then
            tinsert(keys, k)
        end
    end
    tsort(keys)
    return keys
end

function ns.Count()
    local n = 0
    for _ in pairs(ns.db.entries) do n = n + 1 end
    return n
end

-------------------------------------------------------------------------------
--  Chat output
-------------------------------------------------------------------------------
local PREFIX = "|cff40e0d0FlagPlates|r: "
function ns.Print(msg, ...)
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. format(msg, ...))
end

-- Adds the target, or removes it when it's already flagged (exact entry first).
function ns.ToggleTarget()
    if not UnitExists("target") then
        ns.Print("No target.")
        return
    end
    local isPlayer = UnitIsPlayer("target")
    if issecret(isPlayer) then
        ns.Print("Target's identity is hidden here (restricted).")
        return
    end
    if not isPlayer then
        ns.Print("Target is not a player.")
        return
    end
    local name, surname = ns.UnitNames("target")
    if not name then
        ns.Print("Target's name is hidden here (restricted).")
        return
    end
    local exact = Key(name, surname)
    if ns.db.entries[exact] then
        local disp = ns.DisplayName(ns.db.entries[exact])
        ns.Remove(exact)
        ns.Print("Removed |cffffffff%s|r.", disp)
        return
    end
    local firstOnly = Key(name)
    if surname and ns.db.entries[firstOnly] then
        ns.Print("|cffffffff%s|r is already flagged by first name. Edit it in /mu.", name)
        return
    end
    ns.Add(name, surname)
    ns.Print("Added |cffffffff%s|r.", ns.DisplayName(ns.db.entries[exact]))
end

-------------------------------------------------------------------------------
--  Right-click unit menu: "Flag player" / "Unflag player"
--  Menu.ModifyMenu is Blizzard's addon hook for context menus (Midnight API).
-------------------------------------------------------------------------------
local function AddMenuEntry(owner, root, contextData)
    local unit = contextData and contextData.unit
    local name, surname
    if unit then
        name, surname = ns.UnitNames(unit)
    elseif contextData and type(contextData.name) == "string" and not issecret(contextData.name) then
        name = contextData.name
    end
    if not name then return end
    local entry = ns.Lookup(name, surname)
    root:CreateDivider()
    if entry then
        root:CreateButton("|cff40e0d0Unflag player|r", function()
            for k, e in pairs(ns.db.entries) do
                if e == entry then ns.Remove(k) break end
            end
            ns.Print("Removed |cffffffff%s|r.", ns.DisplayName(entry))
        end)
    else
        root:CreateButton("|cff40e0d0Flag player|r", function()
            ns.Add(name, surname)
            ns.Print("Added |cffffffff%s|r.", surname and (name .. " " .. surname) or name)
        end)
    end
end

local function HookMenus()
    if not (Menu and Menu.ModifyMenu) then return end
    for _, tag in ipairs({
        "MENU_UNIT_PLAYER", "MENU_UNIT_TARGET", "MENU_UNIT_FOCUS", "MENU_UNIT_PARTY",
        "MENU_UNIT_RAID_PLAYER", "MENU_UNIT_ENEMY_PLAYER", "MENU_UNIT_FRIEND",
    }) do
        pcall(Menu.ModifyMenu, tag, AddMenuEntry)
    end
end

-------------------------------------------------------------------------------
--  Boot
-------------------------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:SetScript("OnEvent", function(self, event, name)
    if name ~= ADDON then return end
    self:UnregisterEvent("ADDON_LOADED")
    if root and root.Off and root.Off("FlagPlates", self) then return end
    ns.InitDB()
    HookMenus()
    if ns.InitEncounters then ns.InitEncounters() end
    if ns.OnInit then ns.OnInit() end
end)
