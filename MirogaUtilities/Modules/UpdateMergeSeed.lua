-- Keep list seed: the settings you kept on OLD in the merge of 16.11.2026
-- (Naowh 20261115.04). Loaded once into MirogaUpdateMergeDB.keep.
local _, root = ...
local um = root.UpdateMerge
local SEED = {
    eui = {
        "profile\031addons\031EllesmereUIActionBars\031bars\031Bar2\031barVisibility",
        "profile\031addons\031EllesmereUIActionBars\031bars\031Bar2\031mouseoverAlpha",
        "profile\031addons\031EllesmereUIActionBars\031bars\031Bar2\031mouseoverEnabled",
        "profile\031addons\031EllesmereUIActionBars\031bars\031Bar3\031barVisibility",
        "profile\031addons\031EllesmereUIActionBars\031bars\031Bar3\031mouseoverAlpha",
        "profile\031addons\031EllesmereUIActionBars\031bars\031Bar3\031mouseoverEnabled",
        "profile\031addons\031EllesmereUIActionBars\031bars\031Bar4\031barVisibility",
        "profile\031addons\031EllesmereUIActionBars\031bars\031Bar4\031mouseoverAlpha",
        "profile\031addons\031EllesmereUIActionBars\031bars\031Bar4\031mouseoverEnabled",
        "profile\031addons\031EllesmereUIActionBars\031bars\031MainBar\031barVisibility",
        "profile\031addons\031EllesmereUIActionBars\031bars\031MainBar\031mouseoverAlpha",
        "profile\031addons\031EllesmereUIActionBars\031bars\031MainBar\031mouseoverEnabled",
        "profile\031addons\031EllesmereUIChat\031chat\031lockChatSize",
        "profile\031addons\031EllesmereUIChat\031chat\031timestampAll",
        "profile\031addons\031EllesmereUIChat\031chat\031timestampFormat",
        "profile\031addons\031EllesmereUICooldownManager\031customActiveStates\031#1259416",
        "profile\031addons\031EllesmereUICooldownManager\031customActiveStates\031#1259416\031cdStateEffect",
        "profile\031addons\031EllesmereUIDamageMeters\031dm\031windows\031#1\031hideInPvP",
        "profile\031addons\031EllesmereUIDamageMeters\031dm\031windows\031#1\031hideOutOfInstance",
        "profile\031addons\031EllesmereUIDamageMeters\031dm\031windows\031#2\031hideInPvP",
        "profile\031addons\031EllesmereUIDamageMeters\031dm\031windows\031#2\031hideOutOfInstance",
        "profile\031addons\031EllesmereUINameplates\031bottomSlotYOffset",
        "profile\031addons\031EllesmereUINameplates\031classificationHideRare",
        "profile\031addons\031EllesmereUINameplates\031classificationSlot",
        "profile\031addons\031EllesmereUINameplates\031questTextSlot",
        "profile\031addons\031EllesmereUINameplates\031showQuestObjectiveTypeIcon",
        "profile\031addons\031EllesmereUIQoL\031cursor\031castCircle\031enabled",
        "profile\031addons\031EllesmereUIQoL\031cursor\031enabled",
        "profile\031addons\031EllesmereUIQoL\031cursor\031gcd\031enabled",
        "profile\031specUnlockOverrides\031baselineLayout\031elems\031PAB_Buffs\031w",
        "profile\031specUnlockOverrides\031baselineLayout\031elems\031PAB_CustomBuff_6\031w",
        "profile\031specUnlockOverrides\031baselineLayout\031elems\031PAB_CustomDebuff_3\031w",
        "profile\031specUnlockOverrides\031baselineLayout\031elems\031PAB_Debuffs\031w",
        "profile\031specUnlockOverrides\031baselineLayout\031elems\031PAB_Debuffs\031x",
        "profile\031specUnlockOverrides\031baselineLayout\031elems\031RF_PartyFrames\031h",
        "profile\031specUnlockOverrides\031baselineLayout\031elems\031RF_RaidFrames\031w",
        "scale",
        "spells\031specProfiles\031102\031barSpells\031cooldowns\031assignedSpells",
        "spells\031specProfiles\031102\031barSpells\031custom_6_204310_438\031assignedSpells",
        "spells\031specProfiles\031102\031barSpells\031custom_6_204310_438\031customSpellIDs\031#1259416",
    },
    forever = {
        "profile\031discovery\031bagMapPins",
        "profile\031druidMana\031fiveSecond",
        "profile\031druidMana\031powershift",
        "profile\031journal\031questsOpen",
        "profile\031qol\031bagSpace",
        "profile\031qol\031consumableBarDeclined\031#13443",
        "profile\031qol\031consumableBarDeclined\031#13446",
        "profile\031qol\031consumableBarDeclined\031#250947",
        "profile\031qol\031consumableBarDeclined\031#3928",
        "profile\031qol\031consumableBarDeclined\031#6149",
        "profile\031qol\031foodBarGrow",
        "profile\031qol\031restock",
        "profile\031qol\031townMail",
        "profile\031qol\031townMinimap",
        "profile\031qol\031townPinSize",
        "profile\031qol\031townProfession",
        "profile\031qol\031xpBarBreakdown",
        "profile\031qol\031xpTickerHistoryCount",
        "profile\031threatMeter\031enabled",
        "profile\031trackingReminder\031enabled",
    },
}

function um.Seed(db)
    if db.seeded then return end
    db.seeded = true
    for id, paths in pairs(SEED) do
        local keep = db.keep[id] or {}
        db.keep[id] = keep
        for _, path in ipairs(paths) do keep[path] = true end
    end
end
