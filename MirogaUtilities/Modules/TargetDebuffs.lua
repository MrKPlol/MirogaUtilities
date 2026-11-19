-- Target debuffs: a small icon row next to the EllesmereUI cooldown manager's
-- buff bar (the one with Moonfire) for debuffs that count no matter who cast
-- them. EllesmereUI's bars read auras with "HARMFUL|PLAYER", so a warrior's
-- Demoralizing Shout or another druid's Faerie Fire never shows there.
--
-- Slots (one per effect, any rank, any caster):
--   Demoralizing: Demoralizing Shout or Demoralizing Roar (they do not stack)
--   Faerie Fire:  Faerie Fire or Faerie Fire (Feral)
-- Lit with the remaining time while on the target, dimmed while missing
-- (that is the "apply it" hint). Only for an attackable, living target.
-- Auras the game keeps secret (battlegrounds, encounters) leave the slot dim.
local _, root = ...
local td = {}
root.TargetDebuffs = td

td.SLOTS = {
    { key = "demo", label = "Demoralizing Shout / Roar",
        spells = { { id = 1160, name = "Demoralizing Shout" }, { id = 99, name = "Demoralizing Roar" } } },
    { key = "ff", label = "Faerie Fire",
        spells = { { id = 770, name = "Faerie Fire" }, { id = 16857, name = "Faerie Fire (Feral)" } } },
}
td.DEFAULTS = { demo = true, ff = true, showMissing = true, size = 44, x = -4, y = 0, side = "LEFT" }
td.ANCHOR = "ECME_CDMBar_buffs" -- EllesmereUI CDM bar 3 ("buffs"), Moonfire's bar

local issecret = issecretvalue or function() return false end

local function Opt(key)
    local db = td.db or td.DEFAULTS
    local v = db[key]
    if v == nil then return td.DEFAULTS[key] end
    return v
end

-- localized names (enUS client: same as the fallbacks)
local function SpellName(s)
    if not s.localName then
        local n = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(s.id)
        s.localName = (type(n) == "string" and not issecret(n) and n ~= "") and n or s.name
    end
    return s.localName
end

-- the first aura of the slot on the target: aura table or nil (secret = nil)
function td.Find(slot)
    local get = C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName
    if not get then return nil end
    for _, s in ipairs(slot.spells) do
        local ok, aura = pcall(get, "target", SpellName(s), "HARMFUL")
        if ok and type(aura) == "table" and not issecret(aura) then
            local exp, dur = aura.expirationTime, aura.duration
            if issecret(exp) or issecret(dur) then exp, dur = nil, nil end
            return { icon = (not issecret(aura.icon)) and aura.icon or nil, expirationTime = exp, duration = dur }
        end
    end
end

function td.TargetWanted()
    if not UnitExists("target") then return false end
    local can = UnitCanAttack("player", "target")
    local dead = UnitIsDeadOrGhost("target")
    if issecret(can) or issecret(dead) then return false end
    return can and not dead
end

-- ---------------------------------------------------------------------------
-- frames

local row, icons = nil, {}

local function SlotIcon(slot)
    local s = slot.spells[1]
    if not s.tex then
        local t = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(s.id)
        s.tex = (t and not issecret(t)) and t or 134400
    end
    return s.tex
end

local function Build()
    if row then return end
    row = CreateFrame("Frame", "MirogaTargetDebuffs", UIParent)
    row:SetFrameStrata("MEDIUM")
    for i, slot in ipairs(td.SLOTS) do
        local f = CreateFrame("Frame", nil, row)
        f.tex = f:CreateTexture(nil, "ARTWORK")
        f.tex:SetAllPoints()
        f.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        f.border = f:CreateTexture(nil, "BACKGROUND")
        f.border:SetPoint("TOPLEFT", -1, 1)
        f.border:SetPoint("BOTTOMRIGHT", 1, -1)
        f.border:SetColorTexture(0, 0, 0, 1)
        f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
        f.cd:SetAllPoints()
        f.cd:SetDrawEdge(false)
        f.cd:SetReverse(true)
        f.slot = slot
        icons[i] = f
    end
end

function td.Layout()
    if not row then return end
    local size, gap = Opt("size"), 2
    local shown = {}
    for _, f in ipairs(icons) do
        if Opt(f.slot.key) then shown[#shown + 1] = f else f:Hide() end
    end
    row:SetSize(math.max(1, #shown * size + (#shown - 1) * gap), size)
    for i, f in ipairs(shown) do
        f:SetSize(size, size)
        f:ClearAllPoints()
        f:SetPoint("LEFT", row, "LEFT", (i - 1) * (size + gap), 0)
    end
    row:ClearAllPoints()
    local bar = _G[td.ANCHOR]
    local x, y = Opt("x"), Opt("y")
    if bar and bar.GetLeft then
        if Opt("side") == "RIGHT" then
            row:SetPoint("LEFT", bar, "RIGHT", math.abs(x), y)
        else
            row:SetPoint("RIGHT", bar, "LEFT", -math.abs(x), y)
        end
        td.anchored = true
    else
        row:SetPoint("CENTER", UIParent, "CENTER", 0, -180 + y)
        td.anchored = false
    end
end

function td.Update()
    if not row then return end
    if not td.TargetWanted() then row:Hide(); return end
    local any = false
    for _, f in ipairs(icons) do
        if Opt(f.slot.key) then
            local aura = td.Find(f.slot)
            if aura then
                f.tex:SetTexture(aura.icon or SlotIcon(f.slot))
                f.tex:SetDesaturated(false)
                f:SetAlpha(1)
                if aura.duration and aura.duration > 0 and aura.expirationTime then
                    f.cd:SetCooldown(aura.expirationTime - aura.duration, aura.duration)
                    f.cd:Show()
                else
                    f.cd:Hide()
                end
                f:Show(); any = true
            elseif Opt("showMissing") then
                f.tex:SetTexture(SlotIcon(f.slot))
                f.tex:SetDesaturated(true)
                f:SetAlpha(0.4)
                f.cd:Hide()
                f:Show(); any = true
            else
                f:Hide()
            end
        end
    end
    row:SetShown(any)
end

function td.Set(key, value)
    if td.db then td.db[key] = value end
    td.Layout(); td.Update()
end

-- ---------------------------------------------------------------------------
-- events

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= "MirogaUtilities" then return end
        self:UnregisterEvent("ADDON_LOADED")
        if root.Off("TargetDebuffs", self) then return end
        if type(MirogaUtilitiesDB) ~= "table" then MirogaUtilitiesDB = {} end
        MirogaUtilitiesDB.targetDebuffs = MirogaUtilitiesDB.targetDebuffs or {}
        td.db = MirogaUtilitiesDB.targetDebuffs
        self:RegisterEvent("PLAYER_ENTERING_WORLD")
        self:RegisterEvent("PLAYER_TARGET_CHANGED")
        self:RegisterUnitEvent("UNIT_AURA", "target")
        self:RegisterUnitEvent("UNIT_FLAGS", "target")
        self:RegisterUnitEvent("UNIT_HEALTH", "target")
    elseif event == "PLAYER_ENTERING_WORLD" then
        Build()
        -- EllesmereUI builds its bars after login; anchor once they exist
        td.Layout()
        C_Timer.After(2, td.Layout)
        td.Update()
    else
        td.Update()
    end
end)
