-- Naowh tweaks: small changes to Naowh Forever without touching its files.
--
-- Scrolls only in instances: Naowh's Buffs & Consumables row shows a stat
-- scroll you carry everywhere its consumables show. Its "Show in the World"
-- switch covers food, flasks, elixirs and scrolls together, so this drops
-- only the scroll icon outside dungeons and raids. Naowh's list builder
-- (NaowhForever.AuraBuffs.Buffs.Collect) is wrapped; its UI looks the
-- function up on every refresh, so the wrapper is used from then on.
local _, root = ...
local nt = {}
root.NaowhTweaks = nt

nt.DEFAULTS = { scrollsInstanceOnly = true }

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
        if type(list) == "table" and db and db.scrollsInstanceOnly and not InDungeonOrRaid() then
            for i = #list, 1, -1 do
                if type(list[i]) == "table" and list[i].key == "scroll" then table.remove(list, i) end
            end
        end
        return list
    end
    wrapped = true
    return true
end

function nt.Set(key, value)
    if not nt.db then return end
    nt.db[key] = value
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self, event, addon)
    if event == "ADDON_LOADED" then
        if addon == "MirogaUtilities" then
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
end)
