-------------------------------------------------------------------------------
--  KPFlagPlates - Plates: colours flagged players' nameplates
--
--  Supports three nameplate owners at once (each only touches its own frames):
--    * EllesmereUI Nameplates (NaowhUI uses it) - _G.EllesmereNameplates_NS.plates[unit]
--      -> plate.health (StatusBar), plate.name (FontString)
--    * Plater -> nameplate.unitFramePlater.healthBar.barTexture (Texture),
--      unitFrame.healthBar.unitName (FontString)
--    * Blizzard -> nameplate.UnitFrame.healthBar (StatusBar), UnitFrame.name
--
--  How: hooksecurefunc on each bar/text's own colour setter. Whenever the owning
--  addon repaints (threat, reaction, Plater's colour lerp ...), the post-hook paints
--  the flag colour back on top. Nothing of the owners is replaced, so no taint into
--  their code and no fight over priorities.
--
--  Restrictions respected:
--    * Forbidden nameplates (friendly plates inside instances) are never returned by
--      C_NamePlate.GetNamePlateForUnit (includeForbidden = false) and are skipped.
--    * Colour args passed to the hooked setters may be SECRET: they are never read.
--      The original colour saved for restoring may be secret too; secrets may be
--      stored and passed back to setters, only not compared.
-------------------------------------------------------------------------------
local _, root = ...
local ns = root.FlagPlates
if not ns then return end

local hooksecurefunc, pcall = hooksecurefunc, pcall
local issecret = issecretvalue or function() return false end
local GetNamePlateForUnit = C_NamePlate.GetNamePlateForUnit
local GetNamePlates = C_NamePlate.GetNamePlates

-- obj -> "bar" | "tex" | "fs"   (objects currently painted with the flag colour)
local flagged = {}
-- obj -> { [setter] = { r, g, b, a } } colours before we painted (for restore)
local original = {}
-- obj..setter -> true once hooked (hooks can't be removed, so only once)
local hooked = {}
-- unit -> { obj, ... } objects flagged for that nameplate unit
local tagged = {}
local guard = false

local WHITE = { r = 1, g = 1, b = 1 }
-- Per kind: { setter, getter, colour (nil = flag colour) }.
-- Font strings: Blizzard tints names with SetVertexColor, EUI/Plater with
-- SetTextColor; the vertex colour multiplies the text colour, so text gets the
-- flag colour and vertex is held at white.
local SETTERS = {
    bar = { { "SetStatusBarColor", "GetStatusBarColor" } },
    tex = { { "SetVertexColor", "GetVertexColor" } },
    fs  = { { "SetTextColor", "GetTextColor" }, { "SetVertexColor", "GetVertexColor", WHITE } },
}

local function Paint(obj, kind)
    local flag = ns.db.color
    guard = true
    for _, s in ipairs(SETTERS[kind]) do
        local c = s[3] or flag
        pcall(obj[s[1]], obj, c.r, c.g, c.b, 1)
    end
    guard = false
end

local function EnsureHooks(obj, kind)
    for _, s in ipairs(SETTERS[kind]) do
        local id = s[1]
        hooked[obj] = hooked[obj] or {}
        if not hooked[obj][id] then
            hooked[obj][id] = true
            hooksecurefunc(obj, id, function(self)
                if guard then return end
                local k = flagged[self]
                if k then Paint(self, k) end
            end)
        end
    end
end

local function Usable(obj, kind)
    if type(obj) ~= "table" then return false end
    for _, s in ipairs(SETTERS[kind]) do
        if type(obj[s[1]]) ~= "function" then return false end
    end
    if obj.IsForbidden and obj:IsForbidden() then return false end
    return true
end

local function Flag(unit, obj, kind)
    if not Usable(obj, kind) then return end
    if not flagged[obj] then
        local saved = {}
        for _, s in ipairs(SETTERS[kind]) do
            local ok, r, g, b, a = pcall(obj[s[2]], obj)
            -- r may be SECRET: no compare on it, only issecretvalue / type.
            if ok and (issecret(r) or type(r) == "number") then
                saved[s[1]] = { r, g, b, a or 1 }
            end
        end
        original[obj] = saved
    end
    EnsureHooks(obj, kind)
    flagged[obj] = kind
    local list = tagged[unit]
    if not list then list = {}; tagged[unit] = list end
    list[#list + 1] = obj
    Paint(obj, kind)
end

local function Unflag(obj)
    local kind = flagged[obj]
    if not kind then return end
    flagged[obj] = nil
    local saved = original[obj]
    original[obj] = nil
    if not saved then return end
    guard = true
    for _, s in ipairs(SETTERS[kind]) do
        local o = saved[s[1]]
        if o then pcall(obj[s[1]], obj, o[1], o[2], o[3], o[4]) end
    end
    guard = false
end

local function ClearUnit(unit)
    local list = tagged[unit]
    if not list then return end
    tagged[unit] = nil
    for i = 1, #list do Unflag(list[i]) end
end

-- Lets the owning addons repaint a plate after we released it.
local function OwnersRepaint(unit)
    local ens = _G.EllesmereNameplates_NS
    local plate = ens and type(ens.plates) == "table" and ens.plates[unit]
    if plate then
        -- EUI skips unchanged colours; drop its caches so it really repaints.
        plate._lastHCr, plate._lastHCg, plate._lastHCb = nil, nil, nil
        if plate.UpdateHealthColor then pcall(plate.UpdateHealthColor, plate) end
        if plate.UpdateName then pcall(plate.UpdateName, plate) end
    end
    local np = GetNamePlateForUnit(unit)
    local uf = np and np.unitFramePlater
    if uf and Plater and Plater.RefreshNameplateColor then
        pcall(Plater.RefreshNameplateColor, uf)
    end
end

local function CollectTargets(unit, add)
    local db = ns.db
    -- EllesmereUI
    local ens = _G.EllesmereNameplates_NS
    local plate = ens and type(ens.plates) == "table" and ens.plates[unit]
    if plate then
        if db.colorBar then add(plate.health, "bar") end
        if db.colorName then add(plate.name, "fs") end
    end
    local np = GetNamePlateForUnit(unit)   -- forbidden plates excluded
    if not np then return end
    -- Plater
    local puf = np.unitFramePlater
    if type(puf) == "table" and puf.healthBar then
        if db.colorBar then add(puf.healthBar.barTexture, "tex") end
        if db.colorName then add(puf.healthBar.unitName or puf.unitName, "fs") end
    end
    -- Blizzard (also friendly name-only plates EUI leaves to Blizzard)
    local uf = np.UnitFrame
    if type(uf) == "table" and uf ~= puf and not (uf.IsForbidden and uf:IsForbidden()) then
        if db.colorBar then add(uf.healthBar, "bar") end
        if db.colorName then add(uf.name, "fs") end
    end
end


function ns.UpdateUnit(unit)
    if not ns.db then return end
    local had = tagged[unit] ~= nil
    ClearUnit(unit)
    local entry = ns.IsUnitFlagged(unit)
    if entry then
        CollectTargets(unit, function(obj, kind) Flag(unit, obj, kind) end)
        if ns.OnSighted then ns.OnSighted(entry, unit) end
    else
        if ns.OnLost then ns.OnLost(unit) end
        if had then OwnersRepaint(unit) end
    end
end

function ns.RefreshAllPlates()
    if not ns.db then return end
    local seen = {}
    for _, np in ipairs(GetNamePlates() or {}) do
        local unit = (np.GetUnit and np:GetUnit()) or np.unitToken or (np.UnitFrame and np.UnitFrame.unit)
        if unit then
            seen[unit] = true
            ns.UpdateUnit(unit)
        end
    end
    for unit in pairs(tagged) do
        if not seen[unit] then ClearUnit(unit) end
    end
end

-- Repaint everything with a new colour / after toggling bar/name colouring.
function ns.RepaintAll()
    for unit in pairs(tagged) do
        ClearUnit(unit)
        OwnersRepaint(unit)
    end
    ns.RefreshAllPlates()
end

-------------------------------------------------------------------------------
--  Events. Our handler may run before EUI/Plater built the plate for the unit,
--  so updates are deferred one frame.
-------------------------------------------------------------------------------
local ev = CreateFrame("Frame")
local function Deferred(unit)
    C_Timer.After(0, function()
        if UnitExists(unit) then ns.UpdateUnit(unit) end
    end)
end

ev:SetScript("OnEvent", function(_, event, unit)
    if event == "NAME_PLATE_UNIT_ADDED" then
        ClearUnit(unit)
        Deferred(unit)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        ClearUnit(unit)
        if ns.OnLost then ns.OnLost(unit) end
    elseif event == "UNIT_NAME_UPDATE" then
        if unit and string.find(unit, "^nameplate") then Deferred(unit) end
    elseif event == "PLAYER_ENTERING_WORLD" then
        if ns.OnLostAll then ns.OnLostAll() end
        C_Timer.After(1, ns.RefreshAllPlates)
    end
end)

function ns.OnInit()
    ev:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    ev:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    ev:RegisterEvent("UNIT_NAME_UPDATE")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
end
