-- LayerSwap host: off by default, on only when you turn it on yourself.
--
-- LayerSwap turns Host on at every login. Since 1.14.25 its own ask turns
-- Host on and keeps it on for 4 min after a swap, then off again by itself
-- (when it was off before). This module only adds the default: after a login
-- Host goes off, unless you had turned it on yourself last session.
--
-- "Yourself": at logout Host is on, LayerSwap holds no ask of its own
-- (hostForced) and no 4 min lock runs. Then it stays on at the next login,
-- until you turn it off again.
--
-- The off goes through /ls off at your first mouse click after the login:
-- LayerSwap may join or leave a chat channel there, which the game allows
-- only inside a real click. Nothing is changed in LayerSwap's files.
local _, root = ...
local lh = {}
root.LayerHost = lh

lh.DEFAULTS = { enabled = true, wantHost = false }

local function Present()
    return type(LayerSwapDB) == "table" and SlashCmdList and type(SlashCmdList.LAYERSWAP) == "function"
end
lh.Present = Present

function lh.Hosting() return Present() and LayerSwapDB.hosting ~= false or false end

function lh.LockLeft()
    local untilAt = Present() and tonumber(LayerSwapDB.hostLockUntil)
    return untilAt and math.max(0, untilAt - time()) or 0
end

-- LayerSwap's own ask holds Host on right now: never interfere
function lh.Busy()
    return LayerSwapDB.hostForced ~= nil or lh.LockLeft() > 0 or IsInGroup()
end

lh.armed = false

-- runs inside a click; true when it turned Host off
function lh.TryOff()
    if not lh.armed then return false end
    if not (lh.db and lh.db.enabled and Present()) or lh.db.wantHost then lh.armed = false; return false end
    if not lh.Hosting() then lh.armed = false; return false end
    if InCombatLockdown() or lh.Busy() then return false end   -- next click
    lh.armed = false
    SlashCmdList.LAYERSWAP("off")
    if not lh.Hosting() then
        root.Say("LayerSwap Host is off (your default). Click Host in LayerSwap to keep it on.")
        return true
    end
    return false
end

-- at logout: what you left it at becomes your default
function lh.Remember()
    if not (lh.db and Present()) or lh.armed then return end
    if not lh.Hosting() then
        lh.db.wantHost = false
    elseif LayerSwapDB.hostForced == nil and lh.LockLeft() <= 0 then
        lh.db.wantHost = true
    end
end

function lh.Set(key, value)
    if lh.db then lh.db[key] = value end
end

local hooked = false
local function Hook()
    if hooked or not WorldFrame then return end
    hooked = true
    WorldFrame:HookScript("OnMouseDown", function() if lh.armed then lh.TryOff() end end)
    if UIParent then UIParent:HookScript("OnMouseDown", function() if lh.armed then lh.TryOff() end end) end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= "MirogaUtilities" then return end
        self:UnregisterEvent("ADDON_LOADED")
        if root.Off("LayerHost", self) then return end
        if type(MirogaUtilitiesDB) ~= "table" then MirogaUtilitiesDB = {} end
        MirogaUtilitiesDB.layerHost = MirogaUtilitiesDB.layerHost or {}
        local db = MirogaUtilitiesDB.layerHost
        for key, value in pairs(lh.DEFAULTS) do
            if db[key] == nil then db[key] = value end
        end
        lh.db = db
        self:RegisterEvent("PLAYER_ENTERING_WORLD")
        self:RegisterEvent("PLAYER_LOGOUT")
        return
    end
    if event == "PLAYER_LOGOUT" then
        lh.Remember()
        return
    end
    -- PLAYER_ENTERING_WORLD: only a real login turns LayerSwap's Host on
    local isLogin = arg1
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    if not isLogin or not Present() or not lh.db.enabled or lh.db.wantHost then return end
    lh.armed = true
    Hook()
end)
