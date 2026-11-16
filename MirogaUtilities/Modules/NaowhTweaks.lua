-- Naowh tweaks: small changes to Naowh Forever without touching its files.
--
-- Only in instances: Naowh's Buffs & Consumables row shows a stat scroll and
-- buff drinks (Kreeg's Stout, Rumsey Rum, Juju, Zanza: Naowh's "other"
-- group) everywhere its consumables show. Its "Show in the World" switch
-- covers food, flasks, elixirs and scrolls together, so this drops only
-- those icons outside dungeons and raids. Naowh's list builder
-- (NaowhForever.AuraBuffs.Buffs.Collect) is wrapped; its UI looks the
-- function up on every refresh, so the wrapper is used from then on.
local _, root = ...
local nt = {}
root.NaowhTweaks = nt

nt.DEFAULTS = { scrollsInstanceOnly = true, drinksInstanceOnly = true, rxpHide = true }

-- row key -> setting that keeps it to dungeons and raids
local INSTANCE_ONLY = { scroll = "scrollsInstanceOnly", other = "drinksInstanceOnly" }

local function InDungeonOrRaid()
    local inInstance, kind = IsInInstance()
    return inInstance and (kind == "party" or kind == "raid")
end

local function Buffs()
    local ns = _G.NaowhForever
    return ns and ns.AuraBuffs and ns.AuraBuffs.Buffs
end

function nt.HasNaowh()
    local buffs = Buffs()
    return buffs and type(buffs.Collect) == "function" or false
end

local wrapped = false
local function Wrap()
    if wrapped then return true end
    local buffs = Buffs()
    if not (buffs and type(buffs.Collect) == "function") then return false end
    local original = buffs.Collect
    buffs.Collect = function(...)
        local list = original(...)
        local db = nt.db
        if type(list) == "table" and db and not InDungeonOrRaid() then
            for i = #list, 1, -1 do
                local setting = type(list[i]) == "table" and INSTANCE_ONLY[list[i].key]
                if setting and db[setting] then table.remove(list, i) end
            end
        end
        return list
    end
    wrapped = true
    return true
end

-- ---------------------------------------------------------------------------
-- RXP: Naowh's guide window (NaowhRXPWindow) replaces RXP's own list, and
-- /rxp hide only hides RXP's frames (arrow, list). This hides Naowh's window
-- along with them and brings it back with /rxp show.

local function RXPHidden()
    local rxp = _G.RXP
    local p = type(rxp) == "table" and type(rxp.settings) == "table" and rxp.settings.profile
    return type(p) == "table" and (p.showEnabled == false or p.hideGuideWindow == true) or false
end
nt.RXPHidden = RXPHidden

local windowHooked, toggleHooked = false, false
function nt.SyncRXP()
    local w = _G.NaowhRXPWindow
    if not (w and nt.db) then return end
    if not windowHooked then
        windowHooked = true
        w:HookScript("OnShow", function(self)
            if nt.db and nt.db.rxpHide and RXPHidden() then self:Hide() end
        end)
    end
    if not nt.db.rxpHide then return end
    if RXPHidden() then
        if w:IsShown() then w:Hide() end
    elseif not w:IsShown() and nt.rxpHidByUs then
        w:Show()
        local v2 = _G.RXP.v2
        if type(v2) == "table" and type(v2.UpdateGuideWindow) == "function" then pcall(v2.UpdateGuideWindow, v2) end
    end
    nt.rxpHidByUs = RXPHidden()
end

local function HookRXP()
    local settings = type(_G.RXP) == "table" and _G.RXP.settings
    if toggleHooked or type(settings) ~= "table" or type(settings.ToggleActive) ~= "function" then return end
    toggleHooked = true
    hooksecurefunc(settings, "ToggleActive", function() C_Timer.After(0, nt.SyncRXP) end)
end
nt.HookRXP = HookRXP

function nt.Set(key, value)
    if not nt.db then return end
    nt.db[key] = value
    if key == "rxpHide" then nt.rxpHidByUs = RXPHidden(); nt.SyncRXP() end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self, event, addon)
    if event == "ADDON_LOADED" then
        if addon == "MirogaUtilities" then
            if root.Off("NaowhTweaks", self) then return end
            local db = MirogaUtilitiesDB
            if type(db) ~= "table" then
                db = {}
                MirogaUtilitiesDB = db
            end
            db.naowh = type(db.naowh) == "table" and db.naowh or {}
            for key, value in pairs(nt.DEFAULTS) do
                if db.naowh[key] == nil then db.naowh[key] = value end
            end
            nt.db = db.naowh
        elseif addon == "NaowhForever_Combat" then
            Wrap()
        end
        return
    end
    -- PLAYER_LOGIN: Naowh's modules are loaded by now
    Wrap()
    if not nt.db then return end
    HookRXP()
    -- Naowh builds its window a moment after login
    for _, delay in ipairs({ 2, 6, 15 }) do C_Timer.After(delay, nt.SyncRXP) end
end)
