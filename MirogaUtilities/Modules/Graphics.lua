-- Graphics: the hidden graphics values the Options menu cannot reach (or resets),
-- written again after every login. Idea and the facts below from Panorama
-- (Dldvlpr, GPL-3.0, github.com/dldvlpr-addons-wow/Panorama, 1.7.3):
--  * the client may still change CVars after entering the world, so the values
--    are written 4.35 s after login (Panorama, after KelaGraphics);
--  * ResampleSharpness runs backwards: 0 = sharpest, 2 = softest;
--  * the Ground Clutter slider writes groundEffectDensity 48 at most; the
--    engine takes up to 256.
-- A preset or slider change in the Graphics menu can overwrite these values;
-- they come back at the next login or with "Apply now".
-- The values from before are kept in MirogaGraphicsDB.saved for "Restore".
local _, root = ...
local gx = {}
root.Graphics = gx

-- the look: chosen for Ryzen 7 5800X3D + RX 9060 XT, 1080p 144 Hz (cap 141),
-- render scale 100 %, CMAA2. Raid/battleground values (RAID*) stay untouched.
-- Picture from screenshots 17.11.: half the world pixels sat below 30/255;
-- gamma 1.15 lifted them but laid a grey veil over the picture (user, 17.11.).
-- 1.05/60/48 was far too dark at night (mean 8/255 in Hyjal). Now gamma 1.2 lifts
-- shadows and mid tones, contrast 62 keeps black black (no veil), brightness 50.
gx.SETTINGS = {
    { cvar = "groundEffectDensity", label = "Grass density", min = 16, max = 256, step = 8, value = 80,
        desc = "Menu max is 48. 80 = clearly fuller meadows; 256 costs a lot of FPS." },
    { cvar = "groundEffectDist", label = "Grass distance", min = 40, max = 320, step = 10, value = 320,
        desc = "How far out grass is drawn." },
    { cvar = "ResampleAlwaysSharpen", label = "Always sharpen", bool = true, value = 1,
        desc = "Sharpening also at 100 % render scale (CMAA2 softens the picture)." },
    { cvar = "ResampleSharpness", label = "Sharpness", min = 0, max = 2, step = 0.1, value = 0.3,
        desc = "Backwards: 0 = sharpest, 2 = softest. The game default is 0.5." },
    { cvar = "skyCloudLod", label = "Cloud detail", min = 0, max = 3, step = 1, value = 3,
        desc = "Sky clouds, 3 = full." },
    { cvar = "ffxGlow", label = "Full-screen glow", bool = true, value = 1,
        desc = "Soft glow on bright light." },
    { cvar = "reflectionMode", label = "Water reflections", min = 0, max = 3, step = 1, value = 3,
        desc = "What water mirrors: 3 = the full scenery. Not in the menu." },
    { cvar = "rippleDetail", label = "Water ripples", min = 0, max = 2, step = 1, value = 2,
        desc = "Ripple detail on water, 2 = full. Not in the menu." },
    { cvar = "entityLodDist", label = "Character detail distance", min = 1, max = 50, step = 1, value = 10,
        desc = "How far players and creatures keep full detail. Game default 5." },
    { cvar = "screenshotQuality", label = "Screenshot quality", min = 1, max = 10, step = 1, value = 10,
        desc = "Free: only affects saved screenshots." },
    { cvar = "Gamma", label = "Gamma", min = 0.3, max = 2.8, step = 0.05, value = 1.2, picture = true,
        desc = "Mid tones and shadows. Game default 1.0." },
    { cvar = "Contrast", label = "Contrast", min = 0, max = 100, step = 1, value = 62, picture = true,
        desc = "Game default 50." },
    { cvar = "Brightness", label = "Brightness", min = 0, max = 100, step = 1, value = 50, picture = true,
        desc = "Game default 50." },
}

gx.DEFAULTS = { on = true, values = {}, saved = {} }

local SETTLE = 4.35

local function Get(name)
    local ok, value = pcall(C_CVar.GetCVar, name)
    return ok and value or nil
end

local function Set(name, value)
    local ok, result = pcall(C_CVar.SetCVar, name, tostring(value))
    return ok and result ~= false
end

local function Round(v, step)
    return math.floor(v / step + 0.5) * step
end

function gx.Exists(s)
    return Get(s.cvar) ~= nil
end

-- the value this module writes (nil = left alone)
function gx.Wanted(s)
    local db = gx.db
    local v = db and db.values[s.cvar]
    if v == nil then v = s.value end
    return v
end

function gx.Current(s)
    return tonumber(Get(s.cvar))
end

-- writes every wanted value; keeps the first value seen for Restore
function gx.ApplyAll(quiet)
    local db = gx.db
    if not db or not db.on then return end
    local failed
    for _, s in ipairs(gx.SETTINGS) do
        local want = gx.Wanted(s)
        local now = Get(s.cvar)
        if want ~= nil and now ~= nil then
            if db.saved[s.cvar] == nil then db.saved[s.cvar] = now end
            if tonumber(now) ~= tonumber(want) and not Set(s.cvar, want) then failed = s.cvar end
        end
    end
    if failed then
        root.Say("The game refused " .. failed .. ".")
    elseif not quiet then
        root.Say("Graphics values written.")
    end
    if gx.OnChange then gx.OnChange() end
end

function gx.SetValue(s, v)
    local db = gx.db
    if not db then return end
    if s.step then v = Round(v, s.step) end
    db.values[s.cvar] = v
    if db.on then
        if db.saved[s.cvar] == nil then db.saved[s.cvar] = Get(s.cvar) end
        Set(s.cvar, v)
    end
end

-- back to the values from before this module, and stop writing
function gx.Restore()
    local db = gx.db
    if not db then return end
    for name, value in pairs(db.saved) do Set(name, value) end
    db.saved = {}
    db.on = false
    root.Say("Graphics back to your values from before. Writing stopped.")
    if gx.OnChange then gx.OnChange() end
end

function gx.SetOn(on)
    local db = gx.db
    if not db then return end
    db.on = on
    if on then gx.ApplyAll() else gx.Restore() end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, addon)
    if event == "ADDON_LOADED" then
        if addon ~= "MirogaUtilities" then return end
        self:UnregisterEvent("ADDON_LOADED")
        if root.Off("Graphics", self) then return end
        if type(MirogaGraphicsDB) ~= "table" then MirogaGraphicsDB = {} end
        local db = MirogaGraphicsDB
        for key, value in pairs(gx.DEFAULTS) do
            if db[key] == nil then db[key] = type(value) == "table" and {} or value end
        end
        gx.db = db
        self:RegisterEvent("PLAYER_ENTERING_WORLD")
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        C_Timer.After(SETTLE, function() gx.ApplyAll(true) end)
    end
end)
