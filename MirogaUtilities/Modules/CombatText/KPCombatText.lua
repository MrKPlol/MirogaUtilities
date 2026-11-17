-- KPCombatText.lua — scrolling combat text that stays readable under the secret-value API.
--
-- C_CombatText provides incoming combat text for the selected unit. This addon
-- separates damage taken from heals and gains; it does not reconstruct outgoing
-- per-spell damage from the combat log or bypass secret-value restrictions.
--
-- Combat payloads go straight to display unless the client can prove them public.

local addonName, root = ...
local ns = root.CombatText
if not ns then return end

-- ---------------------------------------------------------------------------
-- event info access

local function cleanNum(value)
    -- Older beta clients have no detector. Display their payloads without math;
    -- never probe secrecy by deliberately throwing from a per-event closure.
    if not issecretvalue or issecretvalue(value) then return nil end
    if type(value) ~= "number" and type(value) ~= "string" then return nil end
    local n = tonumber(value)
    if n and n == n and math.abs(n) < math.huge then return n end
end

local pending = {}
local boundUnit
local function bindUnit(unit)
    local setActiveUnit = C_CombatText and C_CombatText.SetActiveUnit
    if type(setActiveUnit) ~= "function" then return false end
    local ok = pcall(setActiveUnit, unit)
    if ok and boundUnit ~= unit then
        pending = {}
        boundUnit = unit
    end
    return ok
end

-- ---------------------------------------------------------------------------
-- message classification
-- Colors follow the MSBT conventions players have read for fifteen years.

local TYPES = {
    SPELL_DAMAGE        = { color = { 1.00, 0.95, 0.55 }, size = 20 },
    SPELL_DAMAGE_CRIT   = { color = { 1.00, 0.62, 0.00 }, size = 28, crit = true },
    SPELL_SPLIT_DAMAGE  = { color = { 1.00, 0.95, 0.55 }, size = 18 },
    DAMAGE              = { color = { 1.00, 1.00, 1.00 }, size = 18 },
    DAMAGE_CRIT         = { color = { 1.00, 0.82, 0.00 }, size = 26, crit = true },
    PERIODICAURA_DAMAGE = { color = { 0.80, 0.60, 1.00 }, size = 15, dim = true },
    SPELL_DAMAGE_SHIELD = { color = { 0.70, 0.80, 1.00 }, size = 16 },
    HEAL                = { color = { 0.10, 0.95, 0.10 }, size = 17 },
    HEAL_CRIT           = { color = { 0.10, 1.00, 0.40 }, size = 24, crit = true },
    PERIODICHEAL        = { color = { 0.10, 0.75, 0.10 }, size = 14, dim = true },
    ABSORB              = { color = { 0.55, 0.75, 1.00 }, size = 15 },
    RESIST              = { color = { 0.60, 0.60, 0.90 }, size = 14, dim = true },
    BLOCK               = { color = { 0.60, 0.60, 0.90 }, size = 14, dim = true },
    MISS                = { color = { 0.85, 0.85, 0.85 }, size = 15, text = true },
    DODGE               = { color = { 0.85, 0.85, 0.85 }, size = 15, text = true },
    PARRY               = { color = { 0.85, 0.85, 0.85 }, size = 15, text = true },
    EVADE               = { color = { 0.85, 0.85, 0.85 }, size = 15, text = true },
    IMMUNE              = { color = { 0.85, 0.85, 0.85 }, size = 15, text = true },
    HEALTH_LOW          = { color = { 1.00, 0.15, 0.15 }, size = 20, text = true },
    MANA_LOW            = { color = { 0.30, 0.55, 1.00 }, size = 20, text = true },
    MANA                = { color = { 0.30, 0.55, 1.00 }, size = 14, dim = true },
    ENERGY              = { color = { 1.00, 0.85, 0.10 }, size = 14, dim = true },
    RAGE                = { color = { 1.00, 0.35, 0.10 }, size = 14, dim = true },
    FOCUS               = { color = { 1.00, 0.60, 0.20 }, size = 14, dim = true },
    RUNE                = { color = { 0.60, 0.85, 1.00 }, size = 14 },
    COMBO_POINTS        = { color = { 1.00, 0.75, 0.20 }, size = 16 },
    HONOR_GAINED        = { color = { 0.65, 0.35, 1.00 }, size = 16 },
    AURA_START          = { color = { 0.35, 1.00, 0.60 }, size = 15, text = true },
    AURA_END            = { color = { 0.55, 0.75, 0.60 }, size = 14, text = true, dim = true },
    AURA_START_HARMFUL  = { color = { 1.00, 0.40, 0.30 }, size = 19, text = true },
    AURA_END_HARMFUL    = { color = { 0.90, 0.55, 0.50 }, size = 14, text = true, dim = true },
    SPELL_AURA_START    = { color = { 0.35, 1.00, 0.60 }, size = 15, text = true },
    SPELL_AURA_END      = { color = { 0.55, 0.75, 0.60 }, size = 14, text = true, dim = true },
    ENTERING_COMBAT     = { color = { 1.00, 0.55, 0.00 }, size = 16, text = true },
    LEAVING_COMBAT      = { color = { 0.60, 0.60, 0.60 }, size = 16, text = true, dim = true },
    EXPERIENCE_GAINED   = { color = { 0.60, 0.40, 1.00 }, size = 15 },
    MONEY               = { color = { 1.00, 0.85, 0.00 }, size = 14 },
    SPELL_CAST          = { color = { 1.00, 0.95, 0.55 }, size = 15, text = true },
    DISPELFAILED        = { color = { 0.85, 0.50, 0.50 }, size = 14, text = true, dim = true },
    SPELL_REFLECT       = { color = { 0.70, 0.80, 1.00 }, size = 16 },
}

local TEXT_LABELS = {
    MISS = MISS, DODGE = DODGE, PARRY = PARRY, EVADE = EVADE, IMMUNE = IMMUNE,
    HEALTH_LOW = LOW_HEALTH, MANA_LOW = LOW_MANA,
    ENTERING_COMBAT = ENTERING_COMBAT, LEAVING_COMBAT = LEAVING_COMBAT,
}

-- Incoming damage types (things that hit you) render on the left stream.
local INCOMING = {
    DAMAGE = true, DAMAGE_CRIT = true, SPELL_DAMAGE = true, SPELL_DAMAGE_CRIT = true,
    SPELL_SPLIT_DAMAGE = true, PERIODICAURA_DAMAGE = true, MISS = true, DODGE = true,
    PARRY = true, EVADE = true, IMMUNE = true, AURA_START_HARMFUL = true,
}

-- Canonical names from Blizzard_CombatText/Shared/CombatText.lua. Keep the old
-- beta names above as aliases, but select payload fields before testing secrecy.
local ALIASES = {
    SPLIT_DAMAGE = "SPELL_SPLIT_DAMAGE", DAMAGE_SHIELD = "SPELL_DAMAGE_SHIELD",
    PERIODIC_HEAL = "PERIODICHEAL", PERIODIC_HEAL_CRIT = "HEAL_CRIT",
    HEAL_ABSORB = "HEAL", HEAL_CRIT_ABSORB = "HEAL_CRIT",
    PERIODIC_HEAL_ABSORB = "PERIODICHEAL", ABSORB_ADDED = "ABSORB",
    SPELL_AURA_START_HARMFUL = "AURA_START_HARMFUL", SPELL_AURA_END_HARMFUL = "AURA_END_HARMFUL",
    SPELL_MISS = "MISS", SPELL_DODGE = "DODGE", SPELL_PARRY = "PARRY",
    SPELL_EVADE = "EVADE", SPELL_IMMUNE = "IMMUNE",
    SPELL_BLOCK = "BLOCK", SPELL_ABSORB = "ABSORB", SPELL_RESIST = "RESIST",
}
for name, alias in pairs(ALIASES) do
    TYPES[name] = TYPES[alias]
    TEXT_LABELS[name] = TEXT_LABELS[alias]
    INCOMING[name] = INCOMING[alias]
end
local SECOND_AMOUNT = {
    HEAL = true, HEAL_CRIT = true, PERIODICHEAL = true, PERIODIC_HEAL = true,
    PERIODIC_HEAL_CRIT = true, HEAL_ABSORB = true, HEAL_CRIT_ABSORB = true,
    PERIODIC_HEAL_ABSORB = true, ABSORB_ADDED = true,
}
local MITIGATION = {
    BLOCK = "blocked", SPELL_BLOCK = "blocked", ABSORB = "absorbed",
    SPELL_ABSORB = "absorbed", RESIST = "resisted", SPELL_RESIST = "resisted",
}
for name in pairs(MITIGATION) do
    INCOMING[name] = true
    local label = name:gsub("SPELL_", "")
    TEXT_LABELS[name] = _G["COMBAT_TEXT_" .. label] or label
end
INCOMING.DAMAGE_SHIELD, INCOMING.SPELL_DAMAGE_SHIELD = true, true
INCOMING.AURA_END_HARMFUL, INCOMING.SPELL_AURA_END_HARMFUL = true, true
for _, name in ipairs({ "DEFLECT", "REFLECT", "SPELL_DEFLECT", "SPELL_REFLECT", "SPELL_MISFIRE" }) do
    TYPES[name] = TYPES.MISS
    INCOMING[name] = true
    TEXT_LABELS[name] = _G["COMBAT_TEXT_" .. name:gsub("SPELL_", "")] or name:gsub("SPELL_", "")
end
-- Damage taken by spell school (UNIT_COMBAT schoolMask). Physical keeps the
-- melee hit/crit styles; the rest use Blizzard's combat log school colors.
local SCHOOLS = {
    { bit = 2,  key = "SCHOOL_HOLY",   label = "Holy damage",   color = { 1.00, 0.90, 0.50 }, icon = "Interface\\Icons\\Spell_Holy_HolyBolt" },
    { bit = 4,  key = "SCHOOL_FIRE",   label = "Fire damage",   color = { 1.00, 0.50, 0.00 }, icon = "Interface\\Icons\\Spell_Fire_FlameBolt" },
    { bit = 8,  key = "SCHOOL_NATURE", label = "Nature damage", color = { 0.30, 1.00, 0.30 }, icon = "Interface\\Icons\\Spell_Nature_Lightning" },
    { bit = 16, key = "SCHOOL_FROST",  label = "Frost damage",  color = { 0.50, 1.00, 1.00 }, icon = "Interface\\Icons\\Spell_Frost_FrostBolt02" },
    { bit = 32, key = "SCHOOL_SHADOW", label = "Shadow damage", color = { 0.60, 0.45, 1.00 }, icon = "Interface\\Icons\\Spell_Shadow_ShadowBolt" },
    { bit = 64, key = "SCHOOL_ARCANE", label = "Arcane damage", color = { 1.00, 0.50, 1.00 }, icon = "Interface\\Icons\\Spell_Nature_StarFall" },
}
local PHYSICAL_ICON = "Interface\\Icons\\Ability_MeleeDamage"
-- Heals by school (Holy / Nature), everything else gets the generic heal.
local HEAL_ICONS = { [2] = "Interface\\Icons\\Spell_Holy_FlashHeal", [8] = "Interface\\Icons\\Spell_Nature_HealingTouch" }
local HEAL_ICON = "Interface\\Icons\\Spell_Holy_Heal"
local ICON_FMT = "|T%s:0:0:0:0:64:64:5:59:5:59|t %s"
local AURA_KIND = {
    AURA_START = "HELPFUL", SPELL_AURA_START = "HELPFUL", AURA_END = "HELPFUL", SPELL_AURA_END = "HELPFUL",
    AURA_START_HARMFUL = "HARMFUL", SPELL_AURA_START_HARMFUL = "HARMFUL",
    AURA_END_HARMFUL = "HARMFUL", SPELL_AURA_END_HARMFUL = "HARMFUL",
}

-- The aura's own icon: looked up on the player by name (works for buffs from
-- others too), then as a known spell, else a generic buff/debuff icon. The
-- name may be secret, so every lookup runs in pcall and its result only ever
-- reaches string.format, never a comparison.
local function auraIcon(name, filter)
    if name ~= nil then
        local getAura = C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName
        if getAura then
            local ok, aura = pcall(getAura, "player", name, filter)
            if ok and type(aura) == "table" and aura.icon ~= nil then return aura.icon end
        end
        local getTexture = C_Spell and C_Spell.GetSpellTexture
        if getTexture then
            local ok, icon = pcall(getTexture, name)
            if ok and icon ~= nil then return icon end
        end
    end
    -- unknown: no icon rather than a wrong one
end
for _, school in ipairs(SCHOOLS) do
    TYPES[school.key] = { color = school.color, size = 20 }
    TYPES[school.key .. "_CRIT"] = { color = school.color, size = 28, crit = true }
end
local UNKNOWN = { color = { 0.7, 0.7, 0.7 }, size = 14, dim = true }
local DEFAULT = { color = { 1, 1, 1 }, size = 18 }
local RESOURCE_TYPES = {
    MANA = TYPES.MANA, ENERGY = TYPES.ENERGY, RAGE = TYPES.RAGE, FOCUS = TYPES.FOCUS,
    RUNIC_POWER = TYPES.RUNE, COMBO_POINTS = TYPES.COMBO_POINTS,
    HOLY_POWER = DEFAULT, SOUL_SHARDS = DEFAULT, CHI = DEFAULT, ARCANE_CHARGES = DEFAULT,
}
TYPES.ENERGIZE, TYPES.PERIODIC_ENERGIZE = DEFAULT, DEFAULT
-- a gain reads "+20 Rage", never a bare number
local RESOURCE_LABEL = {
    MANA = "Mana", ENERGY = "Energy", RAGE = "Rage", FOCUS = "Focus", RUNIC_POWER = "Runic Power",
    RUNE = "Runic Power", HOLY_POWER = "Holy Power", SOUL_SHARDS = "Soul Shards", CHI = "Chi",
    ARCANE_CHARGES = "Arcane Charges",
}

-- ---------------------------------------------------------------------------
-- user settings (the hub edits KPCombatTextDB.options, then calls
-- ns.ApplySettings). Event categories gate what is shown; color slots
-- recolor the shared TYPES styles in place, so aliases follow automatically.

local CATEGORIES = {
    { key = "damage", label = "Damage taken", types = { "DAMAGE", "DAMAGE_CRIT", "SPELL_DAMAGE", "SPELL_DAMAGE_CRIT",
        "SPELL_SPLIT_DAMAGE", "SPLIT_DAMAGE", "DAMAGE_SHIELD", "SPELL_DAMAGE_SHIELD" } },
    { key = "dots", label = "Damage over time", types = { "PERIODICAURA_DAMAGE" } },
    { key = "avoid", label = "Misses, dodges, parries, immunes", types = { "MISS", "DODGE", "PARRY", "EVADE", "IMMUNE",
        "DEFLECT", "REFLECT", "SPELL_MISS", "SPELL_DODGE", "SPELL_PARRY", "SPELL_EVADE", "SPELL_IMMUNE",
        "SPELL_DEFLECT", "SPELL_REFLECT", "SPELL_MISFIRE" } },
    { key = "mitigation", label = "Blocked, absorbed, resisted", types = { "BLOCK", "ABSORB", "RESIST",
        "SPELL_BLOCK", "SPELL_ABSORB", "SPELL_RESIST" } },
    { key = "debuffs", label = "Debuffs gained", types = { "AURA_START_HARMFUL", "SPELL_AURA_START_HARMFUL",
        "AURA_END_HARMFUL", "SPELL_AURA_END_HARMFUL" } },
    { key = "heals", label = "Heals", types = { "HEAL", "HEAL_CRIT", "HEAL_ABSORB", "HEAL_CRIT_ABSORB", "PERIODIC_HEAL_CRIT" } },
    { key = "hots", label = "Heals over time", types = { "PERIODICHEAL", "PERIODIC_HEAL", "PERIODIC_HEAL_ABSORB" } },
    { key = "shields", label = "Shields gained", types = { "ABSORB_ADDED" } },
    { key = "buffs", label = "Buffs gained", types = { "AURA_START", "SPELL_AURA_START", "AURA_END", "SPELL_AURA_END" } },
    { key = "resources", label = "Resource gains (mana, rage, energy, ...)", types = { "ENERGIZE",
        "MANA", "ENERGY", "RAGE", "FOCUS", "RUNE" } },
    -- every builder adds one: noise next to a combo point display, off unless switched on
    { key = "combo", label = "Combo points", types = { "COMBO_POINTS" }, default = false },
    -- Passive regeneration ticks every few seconds; off unless switched on.
    { key = "ticks", label = "Resource ticks (regeneration)", types = { "PERIODIC_ENERGIZE" }, default = false },
    { key = "combat", label = "Entering / leaving combat", types = { "ENTERING_COMBAT", "LEAVING_COMBAT" } },
    { key = "warnings", label = "Low health / low mana", types = { "HEALTH_LOW", "MANA_LOW" } },
    { key = "other", label = "Other (honor, experience, money, ...)", types = {} },
}
local CATEGORY_OF = {}
local CATEGORY_DEFAULT = {}
for _, category in ipairs(CATEGORIES) do
    for _, name in ipairs(category.types) do CATEGORY_OF[name] = category.key end
    CATEGORY_DEFAULT[category.key] = category.default ~= false
end
-- Aura fades have their own switch on top of their category.
local FADES = { AURA_END = true, SPELL_AURA_END = true, AURA_END_HARMFUL = true, SPELL_AURA_END_HARMFUL = true }

local COLOR_SLOTS = {
    { key = "DAMAGE", label = "Melee hit", types = { "DAMAGE" } },
    { key = "DAMAGE_CRIT", label = "Melee crit", types = { "DAMAGE_CRIT" } },
    { key = "SPELL_DAMAGE", label = "Spell hit", types = { "SPELL_DAMAGE", "SPELL_SPLIT_DAMAGE" } },
    { key = "SPELL_DAMAGE_CRIT", label = "Spell crit", types = { "SPELL_DAMAGE_CRIT" } },
    { key = "PERIODICAURA_DAMAGE", label = "Damage over time", types = { "PERIODICAURA_DAMAGE" } },
    { key = "MISS", label = "Miss / dodge / parry", types = { "MISS", "DODGE", "PARRY", "EVADE", "IMMUNE" } },
    { key = "BLOCK", label = "Blocked / absorbed / resisted", types = { "BLOCK", "ABSORB", "RESIST" } },
    { key = "AURA_START_HARMFUL", label = "Debuff", types = { "AURA_START_HARMFUL" } },
    { key = "SCHOOL_HOLY", label = "Holy damage", types = { "SCHOOL_HOLY", "SCHOOL_HOLY_CRIT" } },
    { key = "SCHOOL_FIRE", label = "Fire damage", types = { "SCHOOL_FIRE", "SCHOOL_FIRE_CRIT" } },
    { key = "SCHOOL_NATURE", label = "Nature damage", types = { "SCHOOL_NATURE", "SCHOOL_NATURE_CRIT" } },
    { key = "SCHOOL_FROST", label = "Frost damage", types = { "SCHOOL_FROST", "SCHOOL_FROST_CRIT" } },
    { key = "SCHOOL_SHADOW", label = "Shadow damage", types = { "SCHOOL_SHADOW", "SCHOOL_SHADOW_CRIT" } },
    { key = "SCHOOL_ARCANE", label = "Arcane damage", types = { "SCHOOL_ARCANE", "SCHOOL_ARCANE_CRIT" } },
    { key = "HEAL", label = "Heal", types = { "HEAL" } },
    { key = "HEAL_CRIT", label = "Heal crit", types = { "HEAL_CRIT" } },
    { key = "PERIODICHEAL", label = "Heal over time", types = { "PERIODICHEAL" } },
    { key = "AURA_START", label = "Buff", types = { "AURA_START", "SPELL_AURA_START" } },
    { key = "ENTERING_COMBAT", label = "Entering combat", types = { "ENTERING_COMBAT" } },
    { key = "LEAVING_COMBAT", label = "Leaving combat", types = { "LEAVING_COMBAT" } },
}
local DEFAULT_COLORS = {}
for _, slot in ipairs(COLOR_SLOTS) do
    local c = TYPES[slot.key].color
    DEFAULT_COLORS[slot.key] = { c[1], c[2], c[3] }
end

local DEFAULTS = {
    font = false,          -- false: the game's combat font
    outline = "default",   -- default, NONE, OUTLINE, THICKOUTLINE
    scale = 1,
    lifetime = 1.9,
    distance = 110,
    window = 0.45,
    critPop = true,
    fades = true,
    schoolColors = true,  -- damage taken in its spell school's color
    schoolIcons = true,   -- small school icon in front of damage taken
    blizzSelf = false,    -- Blizzard's own self combat text next to ours
    worldFont = true,     -- our font for Blizzard's damage numbers over enemies too
}
local FLAGS = { "critPop", "fades", "schoolColors", "schoolIcons", "blizzSelf", "worldFont" }
local LIMITS = {
    scale = { 0.5, 2.5 }, lifetime = { 0.5, 5 }, distance = { 0, 400 }, window = { 0, 2 },
}
local OUTLINES = { default = true, NONE = true, OUTLINE = true, THICKOUTLINE = true }

local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function savedOptions()
    -- Saved variables arrive after this file runs; repair the table at use.
    if type(KPCombatTextDB) ~= "table" then KPCombatTextDB = {} end
    local o = KPCombatTextDB.options
    if type(o) ~= "table" then o = {}; KPCombatTextDB.options = o end
    for key, limit in pairs(LIMITS) do
        if not finite(o[key]) then o[key] = DEFAULTS[key] end
        o[key] = math.min(limit[2], math.max(limit[1], o[key]))
    end
    if not OUTLINES[o.outline] then o.outline = DEFAULTS.outline end
    if type(o.font) ~= "string" then o.font = DEFAULTS.font end
    -- one-time: the font MSBT used in Anniversary (GothamNarrowUltra, thin
    -- outline), shipped in Forever by NaowhUI_Media. A missing file falls back
    -- to the game font in applySettings.
    if o.fontPreset ~= "msbt-gotham" then
        o.fontPreset = "msbt-gotham"
        o.font = "Interface\\AddOns\\NaowhUI_Media\\Shared\\Fonts\\GothamNarrowUltra.ttf"
        o.outline = "OUTLINE"
    end
    for _, key in ipairs(FLAGS) do
        if type(o[key]) ~= "boolean" then o[key] = DEFAULTS[key] end
    end
    if type(o.show) ~= "table" then o.show = {} end
    if type(o.colors) ~= "table" then o.colors = {} end
    if type(o.streamOff) ~= "table" then o.streamOff = {} end
    return o
end

local function savedColor(o, key)
    local c = o.colors[key]
    if type(c) == "table" and finite(c[1]) and finite(c[2]) and finite(c[3]) then return c end
    return DEFAULT_COLORS[key]
end

local function shown(mtype)
    local o = savedOptions()
    if FADES[mtype] and not o.fades then return false end
    local key = CATEGORY_OF[mtype] or "other"
    local v = o.show[key]
    if v == nil then return CATEGORY_DEFAULT[key] ~= false end
    return v == true
end

local function categoryShown(key)
    local v = savedOptions().show[key]
    if v == nil then return CATEGORY_DEFAULT[key] ~= false end
    return v == true
end

local function setCategoryShown(key, v)
    -- nil keeps the category on its default, so later default changes apply
    local show = savedOptions().show
    if (v and true or false) == (CATEGORY_DEFAULT[key] ~= false) then show[key] = nil else show[key] = v and true or false end
end


-- ---------------------------------------------------------------------------
-- consolidation: the first hit renders immediately; repeats inside the window
-- update that same line in place ("340" grows into "1020 x3") and refresh its
-- lifetime, so a burst reads as one living number instead of a queue delay.
-- (defined after render, which it calls)

local WINDOW = DEFAULTS.window
local LIFETIME, RISE -- set with the rendering defaults below
local render -- forward-declared: consolidate calls it, defined below

local function amountText(amount, label)
    if not label then return BreakUpLargeNumbers(amount) end
    return "+" .. BreakUpLargeNumbers(amount) .. " " .. label
end

local function consolidate(now, mtype, amount, opts, key, label)
    key = key or mtype
    local p = pending[key]
    if WINDOW > 0 and p and p.entry and p.entry.fs and not p.entry.done and (now - p.t) <= WINDOW and amount then
        p.n = p.n + 1
        p.sum = p.sum + amount
        p.t = now
        local text = amountText(p.sum, p.label) .. " x" .. p.n
        p.entry.fs:SetText(text)
        -- refresh the lifetime without jumping back to the spawn point
        p.entry.push = (p.entry.push or 0) + (now - p.entry.born) / LIFETIME * RISE
        p.entry.born = now
        return
    end
    if amount then
        local entry = render(now, mtype, amountText(amount, label), opts)
        if entry and entry.fs then
            pending[key] = { t = now, n = 1, sum = amount, entry = entry, label = label }
        end
    end
end

-- ---------------------------------------------------------------------------
-- rendering: a pool of rising, fading font strings in two streams

local pool = {}
local active = {}
local MAX_ACTIVE = 128
local updater = CreateFrame("Frame")
updater:Hide()

if type(KPCombatTextDB) ~= "table" then KPCombatTextDB = {} end
local streams = {}
local DIRECTIONS = { up = { 0, 1 }, down = { 0, -1 }, left = { -1, 0 }, right = { 1, 0 } }
local POINTS = { CENTER = true, TOP = true, BOTTOM = true, LEFT = true, RIGHT = true,
    TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true }

local function validPosition(s)
    return type(s) == "table" and POINTS[s.point] and POINTS[s.relPoint] and finite(s.x) and finite(s.y)
end

local function savedStreams()
    -- WoW restores saved variables after executing addon files, so the load-time
    -- default alone cannot validate a persisted root. Recheck at first use.
    if type(KPCombatTextDB) ~= "table" then KPCombatTextDB = {} end
    if type(KPCombatTextDB.streams) ~= "table" then KPCombatTextDB.streams = {} end
    return KPCombatTextDB.streams
end

local function saveAnchor(stream)
    local point, _, relPoint, x, y = stream.anchor:GetPoint()
    if point then
        local saved = savedStreams()
        local s = type(saved[stream.name]) == "table" and saved[stream.name] or {}
        s.point, s.relPoint, s.x, s.y = point, relPoint, x, y
        s.direction = stream.direction
        saved[stream.name] = s
    end
end

local function createStream(name, x, label)
    local anchor = CreateFrame("Frame", "KPCombatText" .. label .. "Anchor", UIParent)
    local stream = { name = name, anchor = anchor, defaultX = x, direction = "up" }
    streams[name] = stream
    anchor:SetSize(160, 40)
    anchor:SetPoint("CENTER", UIParent, "CENTER", x, 120)
    anchor:SetMovable(true)
    anchor:EnableMouse(false)
    anchor:SetClampedToScreen(true)
    anchor:Hide()
    anchor:RegisterForDrag("LeftButton")
    anchor:SetScript("OnDragStart", anchor.StartMoving)
    anchor:SetScript("OnDragStop", function()
        anchor:StopMovingOrSizing()
        saveAnchor(stream)
    end)
    local texture = anchor:CreateTexture(nil, "BACKGROUND")
    texture:SetAllPoints()
    texture:SetColorTexture(0, 0.8, 0.9, 0.25)
    local text = anchor:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetAllPoints()
    text:SetText("KPCombatText: " .. label)
    text:SetJustifyH("CENTER")
end

createStream("incoming", -180, "Incoming")
createStream("gains", 180, "Gains")

local function restoreAnchor()
    local saved = savedStreams()
    for name, stream in pairs(streams) do
        local s = saved[name]
        -- Preserve the old shared anchor's placement as two initial positions.
        local old = KPCombatTextDB.anchor
        if not validPosition(s) and validPosition(old) then
            -- Old boxes were 260px wide; the new 160px boxes need a 50px
            -- correction to preserve their centers at edge/corner attachments.
            local correction = old.point:find("LEFT", 1, true) and 50 or (old.point:find("RIGHT", 1, true) and -50 or 0)
            s = { point = old.point, relPoint = old.relPoint, x = old.x + stream.defaultX + correction, y = old.y }
            saved[name] = s
        end
        local anchor = stream.anchor
        anchor:ClearAllPoints()
        if validPosition(s) then
            anchor:SetPoint(s.point, UIParent, s.relPoint, s.x, s.y)
        else
            anchor:SetPoint("CENTER", UIParent, "CENTER", stream.defaultX, 120)
        end
        stream.direction = type(s) == "table" and DIRECTIONS[s.direction] and s.direction or "up"
    end
    KPCombatTextDB.anchor = nil
end

-- font cache: captured once from a fresh font string BEFORE any SetText. A widget
-- that has displayed secret text hands marked values back from its getters
-- (live-proven: GetPoint returned <secret string> after SetText(secret)), so the
-- addon never reads back from a rendered widget — it reuses this clean cache.
local baseFont, baseFlags
-- the user's font choice, resolved by ApplySettings; nil falls back to the base
local userFont, userFlags
local textScale, critPop = DEFAULTS.scale, DEFAULTS.critPop

local function acquire()
    local fs = table.remove(pool)
    if not fs then
        fs = UIParent:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
        fs:SetFontObject("GameFontNormalHuge")
        local f, _, fl = fs:GetFont()
        if f and not baseFont then baseFont, baseFlags = f, fl end
    end
    return fs
end

local function release(fs)
    fs:Hide()
    table.insert(pool, fs)
end

-- All base sizes read a quarter larger than the original ClearCombatText ones.
local SIZE_BOOST = 1.25
LIFETIME, RISE = DEFAULTS.lifetime, DEFAULTS.distance

local function setFont(fs, size)
    local font = userFont or baseFont
    if font then fs:SetFont(font, size, userFlags or baseFlags) end
end

render = function(now, mtype, text, opts)
    -- Secret events cannot consolidate. Bound burst allocation and per-frame work.
    if #active >= MAX_ACTIVE then return nil end
    opts = opts or TYPES[mtype] or DEFAULT
    local stream = streams[INCOMING[mtype] and "incoming" or "gains"]
    if savedOptions().streamOff[stream.name] then return nil end
    local fs = acquire()
    if not fs then return nil end -- guard: stub layer may fail under injection
    fs:SetText(text)
    fs:SetAlpha(1) -- pooled strings carry the tail of their last fade
    fs:SetTextColor(opts.color[1], opts.color[2], opts.color[3], opts.dim and 0.75 or 1)
    local size = math.max(6, math.floor(opts.size * textScale * SIZE_BOOST + 0.5))
    setFont(fs, size)
    -- our own clean numbers only: after SetText the widget may carry the secret
    -- marker, and its getters hand back marked values (GetPoint proved it live)
    -- No overlap: when the newest line in this stream has not yet moved a full
    -- line away from the spawn point, every line in the stream is pushed on by
    -- the missing distance, so a burst stacks like a list instead of piling up.
    local lineH = size * 1.15
    local newest
    for i = #active, 1, -1 do
        if active[i].stream == stream then newest = active[i]; break end
    end
    if newest then
        local moved = (now - newest.born) / LIFETIME * RISE + newest.push
        if moved < lineH then
            local delta = lineH - moved
            for _, a in ipairs(active) do
                if a.stream == stream then a.push = a.push + delta end
            end
        end
    end
    local spawnX = math.random(-12, 12)
    fs:ClearAllPoints()
    fs:SetPoint("CENTER", stream.anchor, "CENTER", spawnX, 0)
    fs:Show()
    local entry = { fs = fs, born = now, size = size, fontSize = size, crit = opts.crit and critPop, done = false, spawnX = spawnX, stream = stream, push = 0 }
    active[#active + 1] = entry
    updater:Show()
    return entry
end

updater:SetScript("OnUpdate", function(self, elapsed)
    local now = GetTime()
    for i = #active, 1, -1 do
        local a = active[i]
        local age = now - a.born
        -- lines pushed far past the scroll distance leave early
        if age >= LIFETIME or a.push > RISE * 1.5 + 60 then
            a.done = true
            release(a.fs)
            table.remove(active, i)
        else
            local k = age / LIFETIME
            local direction = DIRECTIONS[a.stream.direction]
            -- no GetPoint read-back: the widget may carry the secret marker and
            -- its getters return marked values, which SetPoint rejects. We own
            -- spawnX; the anchor frame never displayed a secret, so it is clean.
            local d = k * RISE + a.push
            a.fs:SetPoint("CENTER", a.stream.anchor, "CENTER", a.spawnX + d * direction[1], d * direction[2])
            a.fs:SetAlpha((1 - k) ^ 1.4)
            if a.crit and (userFont or baseFont) then
                local pop = 1 + 0.35 * math.max(0, 1 - age * 8)
                local size = math.floor(a.size * pop)
                if size ~= a.fontSize then
                    setFont(a.fs, size)
                    a.fontSize = size
                end
            end
        end
    end
    -- expired consolidation windows release their claim; the line itself fades
    -- on its own refreshed lifetime
    for mtype, p in pairs(pending) do
        if (now - p.t) > WINDOW then
            pending[mtype] = nil
        end
    end
    if #active == 0 then self:Hide() end
end)

-- ---------------------------------------------------------------------------
-- settings application

-- A font path is tried on this private string, which never shows combat text,
-- so the result is a clean boolean and a missing file falls back to the base.
local fontProbe = UIParent:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")

-- Blizzard's CombatText frame draws the same incoming numbers over the
-- character. It is only hidden, never written to: its OnEvent bails while
-- hidden, and the enableFloatingCombatText CVar stays as the player set it.
local blizzHooked = false
local function applyBlizzard()
    local frame = _G.CombatText
    if not frame then return end
    if not blizzHooked then
        blizzHooked = true
        frame:HookScript("OnShow", function(self)
            if not savedOptions().blizzSelf then self:Hide() end
        end)
    end
    if savedOptions().blizzSelf then
        if GetCVarBool("enableFloatingCombatText") then frame:Show() end
    else
        frame:Hide()
    end
end

-- Blizzard's floating numbers over enemies (your damage and heals) read
-- DAMAGE_TEXT_FONT once at login, so this runs at our ADDON_LOADED (saved
-- variables are in, the engine has not cached it yet) and needs a logout to
-- change. A path the real font object rejects is never written.
local function applyWorldFont()
    local o = savedOptions()
    if not o.worldFont or type(o.font) ~= "string" then return end
    local object = _G.CombatTextFont
    if object and not pcall(object.SetFont, object, o.font, 120, "") then return end
    DAMAGE_TEXT_FONT = o.font
end
ns.ApplyWorldFont = applyWorldFont

local function applySettings()
    local o = savedOptions()
    applyBlizzard()
    LIFETIME, RISE, WINDOW = o.lifetime, o.distance, o.window
    textScale, critPop = o.scale, o.critPop
    userFlags = o.outline ~= "default" and (o.outline == "NONE" and "" or o.outline) or nil
    userFont = nil
    if o.font and fontProbe.SetFont then
        local ok, valid = pcall(fontProbe.SetFont, fontProbe, o.font, 16, "")
        if ok and valid ~= false then userFont = o.font end
    end
    for _, slot in ipairs(COLOR_SLOTS) do
        local c = savedColor(o, slot.key)
        for _, name in ipairs(slot.types) do
            local color = TYPES[name].color
            color[1], color[2], color[3] = c[1], c[2], c[3]
        end
    end
end

-- ---------------------------------------------------------------------------
-- the event

local unitCombatLive = false
local UNIT_COMBAT_COVERS = {}
for _, name in ipairs({ "DAMAGE", "DAMAGE_CRIT", "SPELL_DAMAGE", "SPELL_DAMAGE_CRIT", "SPELL_SPLIT_DAMAGE",
    "SPLIT_DAMAGE", "DAMAGE_SHIELD", "SPELL_DAMAGE_SHIELD", "PERIODICAURA_DAMAGE", "HEAL", "HEAL_CRIT",
    "PERIODICHEAL", "PERIODIC_HEAL", "PERIODIC_HEAL_CRIT", "HEAL_ABSORB", "HEAL_CRIT_ABSORB",
    "PERIODIC_HEAL_ABSORB" }) do
    UNIT_COMBAT_COVERS[name] = true
end

local function public(value)
    return value ~= nil and not (issecretvalue and issecretvalue(value))
end

local function schoolOf(mask)
    if not public(mask) or type(mask) ~= "number" then return nil end
    for _, school in ipairs(SCHOOLS) do
        if bit.band(mask, school.bit) ~= 0 then return school end
    end
end

local function onUnitCombat(unit, action, flagText, amount, schoolMask)
    if not public(action) or (action ~= "WOUND" and action ~= "HEAL") then return end
    if amount == nil then return end
    unitCombatLive = true
    local crit = public(flagText) and (flagText == "CRITICAL" or flagText == "CRUSHING")
    if action == "HEAL" then
        local mtype = crit and "HEAL_CRIT" or "HEAL"
        if not shown(mtype) then return end
        local text = string.format("+%s", BreakUpLargeNumbers(amount))
        if savedOptions().schoolIcons then
            local mask = public(schoolMask) and type(schoolMask) == "number" and schoolMask or 0
            local icon = HEAL_ICON
            for b, path in pairs(HEAL_ICONS) do
                if bit.band(mask, b) ~= 0 then icon = path end
            end
            text = string.format(ICON_FMT, icon, text)
        end
        render(GetTime(), mtype, text)
        return
    end
    -- Fully absorbed, blocked or resisted hits come from C_CombatText as text.
    if public(flagText) and (flagText == "ABSORB" or flagText == "BLOCK" or flagText == "RESIST") then return end
    local mtype = crit and "DAMAGE_CRIT" or "DAMAGE"
    if not shown(mtype) then return end
    local o = savedOptions()
    local school = schoolOf(schoolMask)
    local style = TYPES[mtype]
    if school and o.schoolColors then style = TYPES[school.key .. (crit and "_CRIT" or "")] end
    local text
    if o.schoolIcons and public(schoolMask) then
        local icon = school and school.icon or PHYSICAL_ICON
        text = string.format("|T%s:0:0:0:0:64:64:5:59:5:59|t -%s", icon, BreakUpLargeNumbers(amount))
    else
        text = string.format("-%s", BreakUpLargeNumbers(amount))
    end
    render(GetTime(), mtype, text, style)
end

-- Aura icons: C_CombatText only names the aura (often secret), so the icon
-- comes from UNIT_AURA on the player. Added auras feed a short FIFO per kind;
-- removed ones are looked up in a cache by auraInstanceID. Whichever of the
-- two events arrives first waits up to AURA_MATCH seconds for the other.
local AURA_MATCH = 0.3
local auraCache = {}    -- auraInstanceID -> { icon, key }
local auraQueue = {}    -- key -> { { icon, t }, ... }  icons waiting for text
local auraWaiting = {}  -- key -> { { entry, label, t }, ... }  text waiting for an icon

local function auraKey(aura, ending)
    local kind = "HELPFUL"
    if public(aura.isHarmful) and aura.isHarmful then kind = "HARMFUL" end
    return kind .. (ending and "_END" or "")
end

local function fresh(list, now)
    while list[1] and now - list[1].t > AURA_MATCH do table.remove(list, 1) end
    return list
end

local function deliverIcon(key, icon)
    if icon == nil then return end
    local now = GetTime()
    local waiting = fresh(auraWaiting[key] or {}, now)
    auraWaiting[key] = waiting
    local w = table.remove(waiting, 1)
    if w then
        w.done = true
        if w.entry.fs and not w.entry.done then w.entry.fs:SetText(string.format(ICON_FMT, icon, w.label)) end
        return
    end
    local queue = fresh(auraQueue[key] or {}, now)
    auraQueue[key] = queue
    queue[#queue + 1] = { icon = icon, t = now }
end

local function cacheAura(aura, announce)
    local id = aura.auraInstanceID
    local key = auraKey(aura)
    if public(id) then auraCache[id] = { icon = aura.icon, key = key } end
    if announce then deliverIcon(key, aura.icon) end
end

local function rescanAuras()
    auraCache = {}
    local getByIndex = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    if not getByIndex then return end
    for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
        for i = 1, 100 do
            local ok, aura = pcall(getByIndex, "player", i, filter)
            if not ok or type(aura) ~= "table" then break end
            cacheAura(aura, false)
        end
    end
end

-- In combat the client hands out the whole update as secrets (isFullUpdate
-- and the ID lists are secret), so every field is checked before use and a
-- secret update is skipped; those auras fall back to the generic icon.
local function onUnitAura(unit, info)
    if type(info) ~= "table" then return end
    local full = info.isFullUpdate
    if not public(full) and full ~= nil then return end
    if full then rescanAuras(); return end
    local added, removed = info.addedAuras, info.removedAuraInstanceIDs
    if public(added) and type(added) == "table" then
        for _, aura in ipairs(added) do
            if public(aura) and type(aura) == "table" then pcall(cacheAura, aura, true) end
        end
    end
    if public(removed) and type(removed) == "table" then
        for _, id in ipairs(info.removedAuraInstanceIDs) do
            local cached = public(id) and auraCache[id]
            if cached then
                auraCache[id] = nil
                deliverIcon(cached.key .. "_END", cached.icon)
            end
        end
    end
end

local function lastAuraIcon(filter)
    local getByIndex = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    if not getByIndex then return nil end
    local icon
    for i = 1, 100 do
        local ok, aura = pcall(getByIndex, "player", i, filter)
        if not ok or type(aura) ~= "table" then break end
        icon = aura.icon
    end
    return icon
end

-- C_CombatText aura message: use a waiting icon, else show the fallback and
-- let a UNIT_AURA arriving right after swap in the real one.
local function renderAura(mtype, label, opts, data)
    local filter = AURA_KIND[mtype]
    local key = filter .. ((mtype:find("_END", 1, true)) and "_END" or "")
    local now = GetTime()
    local queued = table.remove(fresh(auraQueue[key] or {}, now), 1)
    if queued then
        render(now, mtype, string.format(ICON_FMT, queued.icon, label), opts)
        return
    end
    local icon = auraIcon(data, filter)
    local entry = render(now, mtype, icon ~= nil and string.format(ICON_FMT, icon, label) or label, opts)
    if entry then
        local waiting = fresh(auraWaiting[key] or {}, now)
        auraWaiting[key] = waiting
        local rec = { entry = entry, label = label, t = now }
        waiting[#waiting + 1] = rec
        -- In combat UNIT_AURA is secret and never delivers. One frame later the
        -- new aura sits on the player; the client appends it, so the last aura
        -- of that kind is the new one. Its icon may be secret, which a texture
        -- escape inside SetText accepts.
        if icon == nil and not key:find("_END", 1, true) and C_Timer then
            C_Timer.After(0, function()
                if rec.done or entry.done or not entry.fs then return end
                rec.done = true
                for i, r in ipairs(auraWaiting[key] or {}) do
                    if r == rec then table.remove(auraWaiting[key], i); break end
                end
                local lastIcon = lastAuraIcon(filter)
                if lastIcon ~= nil then entry.fs:SetText(string.format(ICON_FMT, lastIcon, label)) end
            end)
        end
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("UNIT_EXITING_VEHICLE")
f:RegisterEvent("UNIT_ENTERED_VEHICLE")
f:RegisterEvent("UNIT_PET")
f:RegisterEvent("PLAYER_REGEN_DISABLED")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, unit, showVehicle)
    if event == "COMBAT_TEXT_UPDATE" or event == "UNIT_COMBAT" or event == "UNIT_AURA" then return end -- handled by the hooks below
    if event == "ADDON_LOADED" then
        if unit == addonName and root.Off and root.Off("CombatText", self) then return end
        if unit == "Blizzard_CombatText" then applyBlizzard() end
        if unit == addonName then applyWorldFont() end
        return
    end
    if root.Stopped and root.Stopped("CombatText") then return end
    if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        if C_CombatText == nil then return end
        local mtype = event == "PLAYER_REGEN_DISABLED" and "ENTERING_COMBAT" or "LEAVING_COMBAT"
        if shown(mtype) then render(GetTime(), mtype, TEXT_LABELS[mtype] or mtype) end
        return
    end
    if event == "PLAYER_LOGIN" then
        restoreAnchor() -- position restores even on clients without C_CombatText
        rescanAuras()
        applySettings()
        if C_CombatText == nil then return end
        bindUnit("player")
        
        return
    end
    -- keep the stream bound to the player across loading screens, vehicles and pets
    if C_CombatText == nil then return end
    if event == "UNIT_ENTERED_VEHICLE" and unit == "player" then
        bindUnit(showVehicle and "vehicle" or "player")
        return
    elseif event == "UNIT_EXITING_VEHICLE" and unit == "player" then
        bindUnit("player")
        return
    end
    if event == "PLAYER_ENTERING_WORLD" or unit == "player" then
        if UnitHasVehicleUI("player") then
            bindUnit("vehicle")
        else
            bindUnit("player")
        end
    end
end)

-- UNIT_COMBAT reports every hit and heal on the player, including the ones
-- Blizzard's combat text filters out, and its schoolMask is public. Once it
-- has delivered one event, C_CombatText's damage and heal types are dropped
-- so nothing shows twice; avoids, mitigation, auras and resources stay there.
f:RegisterEvent("COMBAT_TEXT_UPDATE")
pcall(f.RegisterUnitEvent, f, "UNIT_COMBAT", "player", "vehicle")
pcall(f.RegisterUnitEvent, f, "UNIT_AURA", "player")
f:HookScript("OnEvent", function(self, event, ...)
    if event == "UNIT_COMBAT" then onUnitCombat(...)
    elseif event == "UNIT_AURA" then pcall(onUnitAura, ...) end
end)
f:HookScript("OnEvent", function(self, event, mtype)
    if event ~= "COMBAT_TEXT_UPDATE" then return end
    local getCurrentEventInfo = C_CombatText and C_CombatText.GetCurrentEventInfo
    if type(getCurrentEventInfo) ~= "function" then return end
    if issecretvalue and issecretvalue(mtype) then return end
    if type(mtype) ~= "string" then return end
    if unitCombatLive and UNIT_COMBAT_COVERS[mtype] then return end
    if not shown(mtype) then return end
    local data, a2, a3 = getCurrentEventInfo()
    local opts = TYPES[mtype] or UNKNOWN
    if opts.text then
        local label = TEXT_LABELS[mtype] or mtype
        if data ~= nil then label = tostring(data) end
        if AURA_KIND[mtype] and savedOptions().schoolIcons then
            renderAura(mtype, label, opts, data)
            return
        end
        render(GetTime(), mtype, label, opts)
        return
    end
    if MITIGATION[mtype] then
        if a2 ~= nil and data ~= nil then
            local style = opts
            if issecretvalue and not issecretvalue(a3) and a3 == true then style = TYPES.DAMAGE_CRIT end
            -- string.format accepts secrets and preserves their marker; only
            -- the public event label is concatenated, never a combat payload.
            local text = string.format("-%s (%s " .. MITIGATION[mtype] .. ")", tostring(data), tostring(a2))
            render(GetTime(), mtype, text, style)
        else
            render(GetTime(), mtype, TEXT_LABELS[mtype], opts)
        end
        return
    end
    local value = data
    if SECOND_AMOUNT[mtype] then value = a2 end
    if value == nil then return end
    if mtype == "HEAL_ABSORB" or mtype == "HEAL_CRIT_ABSORB" or mtype == "PERIODIC_HEAL_ABSORB" then
        if a3 ~= nil then
            render(GetTime(), mtype, string.format("+%s (%s absorbed)", tostring(value), tostring(a3)), opts)
            return
        end
    end
    local key, label = nil, RESOURCE_LABEL[mtype]
    local resource = mtype == "ENERGIZE" or mtype == "PERIODIC_ENERGIZE"
    local power = resource and not (issecretvalue and issecretvalue(a2)) and type(a2) == "string" and a2 or nil
    if power == "COMBO_POINTS" or mtype == "COMBO_POINTS" then
        -- Blizzard's COMBO_POINTS carries the count you have, a gain carries +1
        if not categoryShown("combo") then return end
        local n = cleanNum(value)
        if not n then return end
        local text = mtype == "COMBO_POINTS" and (n == 1 and "1 Combo Point" or (n .. " Combo Points")) or ("+" .. n .. " Combo Point" .. (n == 1 and "" or "s"))
        render(GetTime(), mtype, text, TYPES.COMBO_POINTS)
        return
    end
    if power and RESOURCE_TYPES[power] then
        opts = RESOURCE_TYPES[power]
        key = mtype .. ":" .. power
        label = RESOURCE_LABEL[power]
    end
    local amount = cleanNum(value)
    -- an unknown or secret power type: no bare number that nobody can read
    if resource and not key then return end
    if amount then
        consolidate(GetTime(), mtype, amount, opts, key, label)
    else
        render(GetTime(), mtype, tostring(value), opts)
    end
end)

-- ---------------------------------------------------------------------------
-- slash commands

-- target: "incoming", "gains" or nil for both; show: nil toggles
local function setAnchorsShown(target, show)
    savedStreams()
    if show == nil then
        if target then
            show = not streams[target].anchor:IsShown()
        else
            show = not (streams.incoming.anchor:IsShown() and streams.gains.anchor:IsShown())
        end
    end
    for name, stream in pairs(streams) do
        if not target or target == name then
            local anchor = stream.anchor
            if not show then
                anchor:StopMovingOrSizing()
                anchor:Hide()
                anchor:EnableMouse(false)
                saveAnchor(stream)
            else
                anchor:Show()
                anchor:EnableMouse(true)
            end
        end
    end
    return show
end

local function setDirection(target, direction)
    local stream = streams[target]
    stream.direction = direction
    saveAnchor(stream)
    savedStreams()[target].direction = direction
end

local function resetPositions()
    savedStreams()
    KPCombatTextDB.anchor = nil
    KPCombatTextDB.streams = {}
    restoreAnchor()
end

local function preview()
    local now = GetTime()
    render(now, "SCHOOL_FIRE_CRIT", "|T" .. SCHOOLS[2].icon .. ":0:0:0:0:64:64:5:59:5:59|t -4,912", TYPES.SCHOOL_FIRE_CRIT)
    render(now, "DAMAGE", "|T" .. PHYSICAL_ICON .. ":0:0:0:0:64:64:5:59:5:59|t -1,377", TYPES.DAMAGE)
    render(now, "SCHOOL_FROST", "|T" .. SCHOOLS[4].icon .. ":0:0:0:0:64:64:5:59:5:59|t -862", TYPES.SCHOOL_FROST)
    render(now, "HEAL_CRIT", string.format(ICON_FMT, HEAL_ICONS[2], "+1,208"))
    render(now, "HEAL", string.format(ICON_FMT, HEAL_ICONS[8], "+385"))
    render(now, "HEALTH_LOW", LOW_HEALTH or "Low health!")
    render(now, "AURA_START_HARMFUL", string.format(ICON_FMT, "Interface\\Icons\\Spell_Shadow_CurseOfTounges", "Curse of Tongues"))
    render(now, "AURA_START", string.format(ICON_FMT, "Interface\\Icons\\Spell_Shadow_ManaBurn", "Clearcasting"))
end

local function toggleBlizzard()
    -- toggle Blizzard's own self combat text next to ours
    local o = savedOptions()
    o.blizzSelf = not o.blizzSelf
    applyBlizzard()
    return o.blizzSelf
end

ns.CATEGORIES, ns.COLOR_SLOTS, ns.DEFAULTS, ns.LIMITS = CATEGORIES, COLOR_SLOTS, DEFAULTS, LIMITS
ns.CategoryShown, ns.SetCategoryShown = categoryShown, setCategoryShown
ns.DEFAULT_COLORS, ns.DIRECTIONS, ns.streams = DEFAULT_COLORS, DIRECTIONS, streams
ns.Options, ns.Color, ns.ApplySettings = savedOptions, savedColor, applySettings
ns.SetAnchorsShown, ns.SetDirection, ns.ResetPositions = setAnchorsShown, setDirection, resetPositions
ns.Preview, ns.ToggleBlizzard = preview, toggleBlizzard

-- fine positioning from the hub: offsets relative to the anchor's own point
function ns.MoveStream(name, dx, dy)
    local stream = streams[name]
    local anchor = stream.anchor
    local point, _, relPoint, x, y = anchor:GetPoint()
    if not point then return end
    anchor:ClearAllPoints()
    anchor:SetPoint(point, UIParent, relPoint, math.floor(x + dx + 0.5), math.floor(y + dy + 0.5))
    saveAnchor(stream)
end

function ns.StreamPosition(name)
    local _, _, _, x, y = streams[name].anchor:GetPoint()
    return math.floor((x or 0) + 0.5), math.floor((y or 0) + 0.5)
end

function ns.Sample(name)
    if name == "incoming" then
        render(GetTime(), "DAMAGE", "-1,234")
    else
        render(GetTime(), "HEAL", "+1,234")
    end
end

