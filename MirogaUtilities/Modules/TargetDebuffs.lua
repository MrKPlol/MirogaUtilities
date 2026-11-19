-- Target debuffs: a small icon row next to the EllesmereUI cooldown manager's
-- buff bar (the one with Moonfire) for debuffs that count no matter who cast
-- them. EllesmereUI's bars read auras with "HARMFUL|PLAYER", so a warrior's
-- Demoralizing Shout or another druid's Faerie Fire never shows there.
--
-- Slots (one per effect, any rank, any caster):
--   Demoralizing: Demoralizing Shout or Demoralizing Roar (they do not stack)
--   Faerie Fire:  Faerie Fire or Faerie Fire (Feral)
-- An icon shows only while ANOTHER player's debuff is on the target (yours
-- show in EllesmereUI's own bar); nothing else, no placeholders.
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
td.DEFAULTS = { demo = true, ff = true, cdmTrack = true, matchBar = true, size = 36, x = 2, y = 0, side = "LEFT" }
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

-- true when the aura is the player's own (or cannot be told: then not shown)
local function Mine(aura)
    local own = aura.isFromPlayerOrPlayerPet
    if issecret(own) then return true end
    if own then return true end
    local src = aura.sourceUnit
    if issecret(src) then return true end
    return src == "player" or src == "pet"
end
td.Mine = Mine

-- another player's aura of the slot on the target: { icon, expirationTime,
-- duration } or nil. Yours never count (EllesmereUI's bar shows them).
function td.Find(slot)
    local byIndex = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    if not byIndex then return nil end
    local names = {}
    for _, s in ipairs(slot.spells) do names[SpellName(s)] = true end
    for i = 1, 40 do
        local ok, aura = pcall(byIndex, "target", i, "HARMFUL")
        if not ok or aura == nil then break end
        if type(aura) == "table" and not issecret(aura) then
            local name = aura.name
            if not issecret(name) and names[name] and not Mine(aura) then
                local exp, dur = aura.expirationTime, aura.duration
                if issecret(exp) or issecret(dur) then exp, dur = nil, nil end
                return { icon = (not issecret(aura.icon)) and aura.icon or nil, expirationTime = exp, duration = dur }
            end
        end
    end
end

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

-- the buffs bar's settings in EllesmereUI's saved profile
local function BarData()
    local db = EllesmereUIDB
    local prof = type(db) == "table" and db.profiles and db.profiles[db.activeProfile or "Default"]
    local cdm = prof and prof.addons and prof.addons.EllesmereUICooldownManager
    local bars = cdm and cdm.cdmBars and cdm.cdmBars.bars
    if type(bars) ~= "table" then return nil end
    for _, bd in ipairs(bars) do
        if bd.key == "buffs" then return bd end
    end
end

-- icon width, height and gap as the bar draws them: the bar's own height is
-- one icon (EllesmereUI sizes in screen pixels, so its numbers are not ours),
-- the width follows the bar's crop (cropped icons are wider than tall)
function td.BarGeometry()
    local bar = _G[td.ANCHOR]
    if not (bar and bar.GetHeight) then return nil end
    local h = bar:GetHeight()
    if issecret(h) or not h or h < 8 or h > 90 then return nil end
    local es, rs = bar:GetEffectiveScale(), UIParent:GetEffectiveScale()
    if es and rs and rs > 0 then h = h * es / rs end
    local bd = BarData()
    local cf = 1
    if bd and bd.iconShape == "cropped" then
        cf = 1 - 2 * ((bd.iconCropPercent or 8) / 100)
    end
    local size = (bd and bd.iconSize) or h
    local unit = h / (size * cf)          -- our units per EllesmereUI unit
    local gap = ((bd and bd.spacing) or 2) * unit
    return h / cf, h, gap
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
    local crop = (w > h) and (1 - h / w) / 2 or 0
    for _, f in ipairs(icons) do
        f:SetSize(w, h)
        f.tex:SetTexCoord(0.07, 0.93, 0.07 + crop * 0.86, 0.93 - crop * 0.86)
    end
    row:SetSize(w, h)
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

-- the shown icons side by side, the first one next to the bar
function td.Pack(shown)
    local g = td.geometry or { w = 36, h = 36, gap = 2 }
    local n = #shown
    row:SetSize(math.max(1, n * g.w + math.max(0, n - 1) * g.gap), g.h)
    local right = Opt("side") ~= "RIGHT"   -- left of the bar: grow leftwards
    for i, f in ipairs(shown) do
        f:ClearAllPoints()
        if right then
            f:SetPoint("RIGHT", row, "RIGHT", -(i - 1) * (g.w + g.gap), 0)
        else
            f:SetPoint("LEFT", row, "LEFT", (i - 1) * (g.w + g.gap), 0)
        end
        f:Show()
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
                f.tex:SetDesaturated(false)
                f:SetAlpha(1)
                f.cd:SetCooldown(now - 6 * i, 30); f.cd:Show()
                f:Show()
            end
        end
        local shown = {}
        for _, f in ipairs(icons) do if Opt(f.slot.key) then shown[#shown + 1] = f end end
        td.Pack(shown)
        row:Show()
        return
    end
    if not td.TargetWanted() then row:Hide(); return end
    -- only present debuffs, packed from the bar outwards
    local shown = {}
    for _, f in ipairs(icons) do
        local aura = Opt(f.slot.key) and td.Find(f.slot)
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
            shown[#shown + 1] = f
        else
            f:Hide()
        end
    end
    td.Pack(shown)
    local any = #shown > 0
    row:SetShown(any)
end

-- ---------------------------------------------------------------------------
-- own debuffs in the EllesmereUI bar: that bar shows what Blizzard's cooldown
-- manager tracks as buffs. Naowh's druid layout hides Demoralizing Roar and
-- leaves Faerie Fire out, and the layout lives on Blizzard's server, so it is
-- set here through the game's own settings code (same as dragging it in the
-- Cooldown Manager window) whenever the layout loads or changes.
td.CDM_SPELLS = { [99] = true, [1160] = true, [770] = true, [16857] = true }

function td.FixCDM()
    if td.cdmBusy or not Opt("cdmTrack") then return 0 end
    if InCombatLockdown and InCombatLockdown() then td.cdmPending = true; return 0 end
    local s = CooldownViewerSettings
    local dp = s and s.GetDataProvider and s:GetDataProvider()
    local lm = s and s.GetLayoutManager and s:GetLayoutManager()
    local cat = Enum and Enum.CooldownViewerCategory and Enum.CooldownViewerCategory.TrackedBuff
    if not (dp and lm and cat and dp.GetOrderedCooldownIDs and dp.SetCooldownToCategory) then return 0 end
    if s.IsShown and s:IsShown() then return 0 end -- the player is editing it
    td.cdmBusy = true
    local okRun, moved = pcall(function()
        local n = 0
        for _, id in ipairs(dp:GetOrderedCooldownIDs() or {}) do
            local info = dp:GetCooldownInfoForID(id)
            local hit = false
            for _, sp in ipairs(info and { info.spellID, info.overrideSpellID } or {}) do
                if not issecret(sp) and td.CDM_SPELLS[sp] then hit = true end
            end
            if hit and info.category ~= cat then
                local st = dp:SetCooldownToCategory(id, cat)
                if st == nil or st == Enum.CooldownLayoutStatus.Success then n = n + 1 end
            end
        end
        if n > 0 then s:SaveCurrentLayout() end
        return n
    end)
    td.cdmBusy = false
    td.cdmPending = false
    return okRun and moved or 0
end

local function QueueFixCDM()
    if td.cdmQueued then return end
    td.cdmQueued = true
    C_Timer.After(1, function() td.cdmQueued = false; td.FixCDM() end)
end
td.QueueFixCDM = QueueFixCDM

function td.Set(key, value)
    if td.db then td.db[key] = value end
    if key == "cdmTrack" and value then QueueFixCDM() end
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
        self:RegisterEvent("PLAYER_REGEN_ENABLED")
        if EventRegistry and EventRegistry.RegisterCallback then
            EventRegistry:RegisterCallback("CooldownViewerSettings.OnDataChanged", QueueFixCDM, td)
            EventRegistry:RegisterCallback("CooldownViewerSettings.OnHide", QueueFixCDM, td)
        end
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
        C_Timer.After(3, QueueFixCDM)
    elseif event == "PLAYER_REGEN_ENABLED" then
        if td.cdmPending then QueueFixCDM() end
    else
        td.Update()
    end
end)
