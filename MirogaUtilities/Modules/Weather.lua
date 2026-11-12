-- Weather switch: one click (or key) drops the weather to a low level, the
-- next click puts your old values back. Forever still has the old weather
-- CVars (weatherDensity 0-3, plus RAIDweatherDensity for the raid graphics
-- preset). Rain, snow and sand particles scale with them; fog that comes
-- from the zone's lighting may stay.
--
-- Automatic: low in listed zones and in battlegrounds, back when you leave.
-- Switching it off by hand inside such a place holds until you leave it.
--
-- The game writes CVars to Config.wtf itself, so "low" survives a relog.
-- The values from before are kept in MirogaWeatherDB to restore them later.
local _, root = ...
local wx = {}
root.Weather = wx

local CVARS = { "weatherDensity", "RAIDweatherDensity" }
wx.DEFAULTS = {
    low = false, byAuto = false, level = 0, saved = {},
    autoZones = true, autoBG = true,
    zones = "Dun Morogh, Winterspring, Tanaris, Silithus",
}

BINDING_NAME_MIROGA_WEATHER = "Weather: low / back"

local function Get(name)
    local ok, value = pcall(C_CVar.GetCVar, name)
    return ok and value or nil
end

local function Set(name, value)
    local ok, result = pcall(C_CVar.SetCVar, name, tostring(value))
    return ok and result ~= false
end

local function Changed()
    if wx.OnChange then wx.OnChange() end
end

function wx.IsLow()
    return wx.db and wx.db.low or false
end

-- current value of the main CVar, for the hub
function wx.Current()
    return tonumber(Get(CVARS[1]))
end

-- the switch itself; reason is shown in chat ("Tanaris", "battleground")
local function Apply(low, reason)
    local db = wx.db
    if not db or low == db.low then return true end
    local failed
    for _, name in ipairs(CVARS) do
        if low then
            local value = Get(name)
            if value then
                db.saved[name] = value
                if not Set(name, db.level) then failed = name end
            end
        else
            local value = db.saved[name]
            if value and not Set(name, value) then failed = name end
        end
    end
    if failed then
        root.Say("The game refused to change " .. failed .. ". Try again out of combat.")
        Changed()
        return false
    end
    db.low = low
    local back = db.saved[CVARS[1]] or "?"
    local why = reason and (" (" .. reason .. ")") or ""
    if low then
        root.Say(("Weather |cff%slow|r%s. Back to %s with /mu w."):format(root.ACCENT_HEX, why, back))
    else
        root.Say("Weather back to " .. back .. why .. ".")
    end
    Changed()
    return true
end

-- ---------------------------------------------------------------------------
-- automatic: listed zones and battlegrounds

local suppressed -- place where low was switched off by hand

function wx.ZoneList()
    local list = {}
    for name in ((wx.db and wx.db.zones) or ""):gmatch("[^,]+") do
        name = strtrim(name)
        if name ~= "" then list[#list + 1] = name end
    end
    return list
end

function wx.CurrentZone()
    return GetRealZoneText() or ""
end

-- the place that wants low weather right now, or nil
local function AutoPlace()
    local db = wx.db
    if db.autoBG then
        local _, instanceType = IsInInstance()
        if instanceType == "pvp" then return "battleground" end
    end
    if db.autoZones then
        local zone = strlower(wx.CurrentZone())
        if zone ~= "" then
            for _, name in ipairs(wx.ZoneList()) do
                if strlower(name) == zone then return wx.CurrentZone() end
            end
        end
    end
end

function wx.Evaluate()
    local db = wx.db
    if not db then return end
    local place = AutoPlace()
    if place ~= suppressed then suppressed = nil end
    if place then
        if not db.low and not suppressed then
            if Apply(true, place) then db.byAuto = true end
        end
    elseif db.low and db.byAuto then
        if Apply(false, "auto") then db.byAuto = false end
    end
end

-- ---------------------------------------------------------------------------
-- manual

function wx.SetLow(low)
    local db = wx.db
    if not db or low == db.low then return end
    if Apply(low) then
        db.byAuto = false
        -- off by hand inside an auto place: leave it off until you go
        if not low then suppressed = AutoPlace() end
    end
end

function wx.Toggle()
    wx.SetLow(not wx.IsLow())
end
MirogaUtilities_ToggleWeather = wx.Toggle

-- the low level can be changed while low is on: it applies at once
function wx.SetLevel(level)
    local db = wx.db
    if not db then return end
    db.level = level
    if db.low then
        for _, name in ipairs(CVARS) do Set(name, level) end
    end
end

function wx.SetAuto(key, value)
    if not wx.db then return end
    wx.db[key] = value
    suppressed = nil
    wx.Evaluate()
end

function wx.SetZones(text)
    if not wx.db then return end
    wx.db.zones = text
    wx.Evaluate()
end

-- adds the zone you stand in to the list
function wx.AddCurrentZone()
    local zone = wx.CurrentZone()
    if zone == "" then return end
    for _, name in ipairs(wx.ZoneList()) do
        if strlower(name) == strlower(zone) then
            root.Say(zone .. " is already on the list.")
            return
        end
    end
    local list = wx.ZoneList()
    list[#list + 1] = zone
    wx.SetZones(table.concat(list, ", "))
    root.Say(zone .. " added.")
    Changed()
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, addon)
    if event == "ADDON_LOADED" then
        if addon ~= "MirogaUtilities" then return end
        self:UnregisterEvent("ADDON_LOADED")
        if type(MirogaWeatherDB) ~= "table" then MirogaWeatherDB = {} end
        local db = MirogaWeatherDB
        for key, value in pairs(wx.DEFAULTS) do
            if db[key] == nil then db[key] = type(value) == "table" and {} or value end
        end
        wx.db = db
        self:RegisterEvent("PLAYER_ENTERING_WORLD")
        self:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        return
    end
    wx.Evaluate()
end)
