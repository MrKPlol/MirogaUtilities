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

-- Travel key: Aquatic Form while swimming, Travel Form otherwise. A state
-- driver swaps the spell, so this also works in combat.
local travelButton = CreateShiftButton("MirogaShiftTravel", TRAVEL_FORM,
    "SecureActionButtonTemplate, SecureHandlerStateTemplate")
travelButton:SetAttribute("_onstate-water", format(
    [[self:SetAttribute("spell", newstate == "swim" and %d or %d)]],
    AQUATIC_FORM, TRAVEL_FORM))
RegisterStateDriver(travelButton, "water", "[swimming] swim; land")

-- Dire Bear Form replaces Bear Form on the stance bar once learned.
local watcher = CreateFrame("Frame")
local function UpdateBearSpell()
    if InCombatLockdown() then
        watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    watcher:UnregisterEvent("PLAYER_REGEN_ENABLED")
    for i = 1, GetNumShapeshiftForms() do
        local _, _, _, spellID = GetShapeshiftFormInfo(i)
        if spellID == DIRE_BEAR_FORM or spellID == BEAR_FORM then
            bearButton:SetAttribute("spell", spellID)
            return
        end
    end
end
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:RegisterEvent("UPDATE_SHAPESHIFT_FORMS")
watcher:SetScript("OnEvent", UpdateBearSpell)
