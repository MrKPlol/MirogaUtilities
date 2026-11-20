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
-- The lock: since 1.14.25 LayerSwap holds Host on for 4 min after every swap
-- and refuses Host off meanwhile (LayerSwapDB.hostLockUntil). With "No lock
-- after swaps" the lock is never written: a metatable on LayerSwapDB drops
-- the two lock keys. When the ask had turned Host on for you (hostForced),
-- LayerSwap's own Host.release then turns it off a few seconds after you left
-- the host's group, instead of 4 min later. While your own ask runs Host shows
-- on, but LayerSwap invites nobody then (canInvite: own ask waiting).
--
-- The off goes through /ls off at your first click or movement key after the login:
-- LayerSwap may join or leave a chat channel there, which the game allows
-- only inside a real click. Nothing is changed in LayerSwap's files.
local _, root = ...
local lh = {}
root.LayerHost = lh

lh.DEFAULTS = { enabled = true, wantHost = false, noLock = true, noCap = true }

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
lh.dropped = 0   -- locks dropped this session

local LOCK_KEYS = { hostLockUntil = true, hostLockWho = true }
local function LockWanted()
    return not (lh.db and lh.db.enabled and lh.db.noLock)
end
-- LayerSwap's count of 10 swaps an hour (LayerSwapDB.limit, 1.14.38+): kept
-- out while "No hourly swap limit" is on, so its wait never starts
local function CapWanted()
    return not (lh.db and lh.db.enabled and lh.db.noCap)
end
lh.capDropped = lh.capDropped or 0

-- the metatable is only ever added to LayerSwap's saved table, never to one
-- that already has a metatable of its own
function lh.GuardLock()
    if not Present() or (LockWanted() and CapWanted()) then return false end
    local t = LayerSwapDB
    if not CapWanted() and rawget(t, "limit") ~= nil then rawset(t, "limit", nil) end
    local mt = getmetatable(t)
    if mt then return mt.mirogaLock == true end
    if rawget(t, "hostLockUntil") ~= nil then
        rawset(t, "hostLockUntil", nil)
        rawset(t, "hostLockWho", nil)
        lh.dropped = lh.dropped + 1
    end
    setmetatable(t, { mirogaLock = true, __newindex = function(tbl, key, value)
        if key == "limit" and value ~= nil and not CapWanted() then
            lh.capDropped = lh.capDropped + 1
            if lh.OnChange then lh.OnChange() end
            return
        end
        if LOCK_KEYS[key] and value ~= nil and not LockWanted() then
            if key == "hostLockUntil" then
                lh.dropped = lh.dropped + 1
                if lh.OnChange then lh.OnChange() end
            end
            return
        end
        rawset(tbl, key, value)
    end })
    return true
end

function lh.LockGuarded()
    local mt = Present() and getmetatable(LayerSwapDB)
    return mt and mt.mirogaLock == true and not LockWanted() or false
end
function lh.CapGuarded()
    local mt = Present() and getmetatable(LayerSwapDB)
    return mt and mt.mirogaLock == true and not CapWanted() or false
end

-- runs inside a click; true when it turned Host off
function lh.TryOff()
    if not lh.armed then return false end
    if not (lh.db and lh.db.enabled and Present()) or lh.db.wantHost then lh.armed = false; return false end
    if not lh.Hosting() then lh.armed = false; return false end
    if InCombatLockdown() or lh.Busy() then return false end   -- next click
    lh.armed = false
lh.dropped = 0   -- locks dropped this session

local LOCK_KEYS = { hostLockUntil = true, hostLockWho = true }
local function LockWanted()
    return not (lh.db and lh.db.enabled and lh.db.noLock)
end
-- LayerSwap's count of 10 swaps an hour (LayerSwapDB.limit, 1.14.38+): kept
-- out while "No hourly swap limit" is on, so its wait never starts
local function CapWanted()
    return not (lh.db and lh.db.enabled and lh.db.noCap)
end
lh.capDropped = lh.capDropped or 0

-- the metatable is only ever added to LayerSwap's saved table, never to one
-- that already has a metatable of its own
function lh.GuardLock()
    if not Present() or (LockWanted() and CapWanted()) then return false end
    local t = LayerSwapDB
    if not CapWanted() and rawget(t, "limit") ~= nil then rawset(t, "limit", nil) end
    local mt = getmetatable(t)
    if mt then return mt.mirogaLock == true end
    if rawget(t, "hostLockUntil") ~= nil then
        rawset(t, "hostLockUntil", nil)
        rawset(t, "hostLockWho", nil)
        lh.dropped = lh.dropped + 1
    end
    setmetatable(t, { mirogaLock = true, __newindex = function(tbl, key, value)
        if key == "limit" and value ~= nil and not CapWanted() then
            lh.capDropped = lh.capDropped + 1
            if lh.OnChange then lh.OnChange() end
            return
        end
        if LOCK_KEYS[key] and value ~= nil and not LockWanted() then
            if key == "hostLockUntil" then
                lh.dropped = lh.dropped + 1
                if lh.OnChange then lh.OnChange() end
            end
            return
        end
        rawset(tbl, key, value)
    end })
    return true
end

function lh.LockGuarded()
    local mt = Present() and getmetatable(LayerSwapDB)
    return mt and mt.mirogaLock == true and not LockWanted() or false
end
function lh.CapGuarded()
    local mt = Present() and getmetatable(LayerSwapDB)
    return mt and mt.mirogaLock == true and not CapWanted() or false
end
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

-- No mouse scripts on WorldFrame or UIParent: a mouse handler there turns
-- on mouse input for a full-screen frame and swallows every click. Instead
-- the game's own click and movement bindings are hooked; they run inside
-- the real key press or click, which is what LayerSwap's channel join needs.
local hooked = false
local function Hook()
    if hooked or not hooksecurefunc then return end
    hooked = true
    local function try() if lh.armed then lh.TryOff() end end
    for _, name in ipairs({ "CameraOrSelectOrMoveStart", "TurnOrActionStart", "MoveForwardStart",
        "MoveBackwardStart", "StrafeLeftStart", "StrafeRightStart", "JumpOrAscendStart" }) do
        if type(_G[name]) == "function" then hooksecurefunc(name, try) end
    end
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
        lh.GuardLock()
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
    lh.GuardLock()
    if not isLogin or not Present() or not lh.db.enabled or lh.db.wantHost then return end
    lh.armed = true
    Hook()
end)
