-- Powershift without the Forever action bar bug. Recasting a form within one
-- press leaves the client reporting no form, so Action Bar 1 falls back to
-- the caster page. The key press cancels the form and the key release casts
-- it: Blizzard's secure press-and-hold path, usable in combat.
local _, class = UnitClass("player")
if class ~= "DRUID" then return end

local BEAR_FORM, DIRE_BEAR_FORM, CAT_FORM = 5487, 9634, 768
local TRAVEL_FORM, AQUATIC_FORM = 783, 1066

_G["BINDING_NAME_CLICK MirogaShiftCat:LeftButton"] = "Powershift: Cat Form"
_G["BINDING_NAME_CLICK MirogaShiftBear:LeftButton"] = "Powershift: Bear Form"
_G["BINDING_NAME_CLICK MirogaShiftTravel:LeftButton"] = "Powershift: Travel / Aquatic Form"

local function CreateShiftButton(name, spellID, template)
    local button = CreateFrame("Button", name, UIParent, template or "SecureActionButtonTemplate")
    button:RegisterForClicks("AnyDown", "AnyUp")
    button:SetAttribute("pressAndHoldAction", true)
    button:SetAttribute("type", "macro")
    button:SetAttribute("macrotext", "/cancelform")
    button:SetAttribute("typerelease", "spell")
    button:SetAttribute("spell", spellID)
    return button
end

CreateShiftButton("MirogaShiftCat", CAT_FORM)
local bearButton = CreateShiftButton("MirogaShiftBear", BEAR_FORM)

-- Travel key with detection: Aquatic Form while swimming, Travel Form
-- outdoors. Pressing it in the form it would pick only cancels the form.
-- Indoors it does nothing, so a stray press keeps Bear or Cat Form.
-- A state driver swaps the action, so this also works in combat.
local travelButton = CreateShiftButton("MirogaShiftTravel", TRAVEL_FORM,
    "SecureActionButtonTemplate, SecureHandlerStateTemplate")
travelButton:SetAttribute("_onstate-water", format([[
    if newstate == "swim" or newstate == "land" then
        self:SetAttribute("macrotext", "/cancelform")
        self:SetAttribute("typerelease", "spell")
        self:SetAttribute("spell", newstate == "swim" and %d or %d)
    elseif newstate == "off" then
        self:SetAttribute("macrotext", "/cancelform")
        self:SetAttribute("typerelease", "macro")
    else
        self:SetAttribute("macrotext", "")
        self:SetAttribute("typerelease", "macro")
    end
]], AQUATIC_FORM, TRAVEL_FORM))

-- Form indices depend on which forms are known, so the driver is rebuilt
-- from the stance bar whenever it changes.
local function FormIndex(spellID)
    for i = 1, GetNumShapeshiftForms() do
        local _, _, _, id = GetShapeshiftFormInfo(i)
        if id == spellID then return i end
    end
end

local function TravelDriver()
    local aquatic, travel = FormIndex(AQUATIC_FORM), FormIndex(TRAVEL_FORM)
    local parts = {}
    if aquatic then
        parts[#parts + 1] = format("[swimming,form:%d] off; [swimming] swim", aquatic)
    else
        parts[#parts + 1] = "[swimming] none"
    end
    if travel then
        parts[#parts + 1] = format("[form:%d] off; [indoors] none; land", travel)
    else
        parts[#parts + 1] = "none"
    end
    return table.concat(parts, "; ")
end

local lastDriver
local function UpdateTravelDriver()
    local driver = TravelDriver()
    if driver ~= lastDriver then
        lastDriver = driver
        RegisterStateDriver(travelButton, "water", driver)
    end
end

-- Dire Bear Form replaces Bear Form on the stance bar once learned.
local watcher = CreateFrame("Frame")
local function UpdateBearSpell()
    if InCombatLockdown() then
        watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    watcher:UnregisterEvent("PLAYER_REGEN_ENABLED")
    -- Dire Bear Form (level 40) always wins over Bear Form
    local spell = BEAR_FORM
    for i = 1, GetNumShapeshiftForms() do
        local _, _, _, spellID = GetShapeshiftFormInfo(i)
        if spellID == DIRE_BEAR_FORM then spell = DIRE_BEAR_FORM end
    end
    if spell ~= DIRE_BEAR_FORM and C_SpellBook and C_SpellBook.IsSpellKnown
        and C_SpellBook.IsSpellKnown(DIRE_BEAR_FORM) then
        spell = DIRE_BEAR_FORM
    end
    bearButton:SetAttribute("spell", spell)
    UpdateTravelDriver()
end
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:RegisterEvent("UPDATE_SHAPESHIFT_FORMS")
watcher:RegisterEvent("SPELLS_CHANGED")
watcher:SetScript("OnEvent", UpdateBearSpell)
