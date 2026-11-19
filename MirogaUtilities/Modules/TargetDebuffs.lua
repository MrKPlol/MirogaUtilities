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
-- PvE only: hidden in battlegrounds, arenas and on player targets. Auras the
-- game keeps secret (boss encounters, if Forever locks them) leave the slot dim.
local _, root = ...
local td = {}
root.TargetDebuffs = td

td.SLOTS = {
    { key = "demo", label = "Demoralizing Shout / Roar",
        spells = { { id = 1160, name = "Demoralizing Shout" }, { id = 99, name = "Demoralizing Roar" } } },
    { key = "ff", label = "Faerie Fire",
        spells = { { id = 770, name = "Faerie Fire" }, { id = 16857, name = "Faerie Fire (Feral)" } } },
}
td.DEFAULTS = { demo = true, ff = true, showMissing = true, matchBar = true, size = 44, x = 2, y = 0, side = "LEFT" }
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

-- PvE only: no row in battlegrounds and arenas, none on players
function td.TargetWanted()
    if not UnitExists("target") then return false end
    local _, kind = IsInInstance()
    if kind == "pvp" or kind == "arena" then return false end
    local player = UnitIsPlayer("target")
    if issecret(player) or player then return false end
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

-- size and spacing of the bar's own icons (EllesmereUI "cropped" icons are
-- wider than tall): nil when the bar shows no icon right now
function td.BarGeometry()
    local bar = _G[td.ANCHOR]
    if not (bar and bar.GetChildren) then return nil end
    local list = {}
    for _, c in ipairs({ bar:GetChildren() }) do
        if c:IsShown() and c ~= row then
            local w, h, l = c:GetWidth(), c:GetHeight(), c:GetLeft()
            if w and h and l and w > 10 and h > 10 and not issecret(w) and not issecret(l) then
                list[#list + 1] = { w = w, h = h, l = l }
            end
        end
    end
    if #list == 0 then return nil end
    table.sort(list, function(a, b) return a.l < b.l end)
    local first, gap = list[1], nil
    if list[2] then gap = list[2].l - (first.l + first.w) end
    if not gap or gap < 0 or gap > 20 then gap = 2 end
    return first.w, first.h, gap
end

function td.Layout()
    if not row then return end
    local w, h, gap = Opt("size"), Opt("size"), 2
    if Opt("matchBar") then
        local bw, bh, bg = td.BarGeometry()
        if bw then w, h, gap = bw, bh, bg end
    end
    td.geometry = { w = w, h = h, gap = gap }
    local shown = {}
    for _, f in ipairs(icons) do
        if Opt(f.slot.key) then shown[#shown + 1] = f else f:Hide() end
    end
    row:SetSize(math.max(1, #shown * w + (#shown - 1) * gap), h)
    -- crop the texture to the icon's shape, as EllesmereUI does
    local crop = (w > h) and (1 - h / w) / 2 or 0
    for i, f in ipairs(shown) do
        f:SetSize(w, h)
        f.tex:SetTexCoord(0.07, 0.93, 0.07 + crop * 0.86, 0.93 - crop * 0.86)
        f:ClearAllPoints()
        f:SetPoint("LEFT", row, "LEFT", (i - 1) * (w + gap), 0)
    end
    row:ClearAllPoints()
    local bar = _G[td.ANCHOR]
    local x, y = Opt("x"), Opt("y")
    if bar and bar.GetLeft then
        local d = Opt("matchBar") and gap or math.abs(x)
        if Opt("side") == "RIGHT" then
            row:SetPoint("LEFT", bar, "RIGHT", d, y)
        else
            row:SetPoint("RIGHT", bar, "LEFT", -d, y)
        end
        td.anchored = true
    else
        row:SetPoint("CENTER", UIParent, "CENTER", 0, -180 + y)
        td.anchored = false
    end
end

-- preview: both icons lit with a running timer, no target needed (the hub page)
function td.SetPreview(on)
    td.preview = on and true or false
    if on then Build(); td.Layout() end
    td.Update()
end

function td.Update()
    if not row then return end
    if td.preview then
        local now = GetTime()
        for i, f in ipairs(icons) do
            if Opt(f.slot.key) then
                f.tex:SetTexture(SlotIcon(f.slot))
                f.tex:SetDesaturated(i == 2 and Opt("showMissing"))
                f:SetAlpha((i == 2 and Opt("showMissing")) and 0.4 or 1)
                if i == 1 then f.cd:SetCooldown(now - 12, 30); f.cd:Show() else f.cd:Hide() end
                f:Show()
            end
        end
        row:Show()
        return
    end
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
        self:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    elseif event == "PLAYER_ENTERING_WORLD" then
        Build()
        -- EllesmereUI builds its bars after login; anchor once they exist
        td.Layout()
        C_Timer.After(2, td.Layout)
        local bar = _G[td.ANCHOR]
        if bar and bar.HookScript and not td.barHooked then
            td.barHooked = true
            bar:HookScript("OnSizeChanged", function() td.Layout() end)
        end
        td.Update()
    else
        td.Update()
    end
end)
