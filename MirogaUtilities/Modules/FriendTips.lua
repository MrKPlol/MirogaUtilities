-- Friend tooltips: EllesmereUI's own friends list (since 9.8.9) shows a slim
-- tooltip on its rows. This one shows what Blizzard's card showed and more:
-- every WoW character the friend is logged in with (two clients at once),
-- class, level, race, faction, zone, realm, group, note and broadcast, with
-- class, faction and zone icons.
--
-- It uses the game tooltip, which EllesmereUI reskins like every other
-- tooltip (background, black border, font size), so it looks like the rest
-- of the UI. EllesmereUI_FriendsList.lua calls EllesmereUI.ShowWidgetTooltip /
-- HideWidgetTooltip by table lookup on every hover: the wrappers show and hide
-- ours for rows carrying a friend record (row.rec.info) and pass everything
-- else through. Nothing in EllesmereUI's files changes; if ours fails,
-- EllesmereUI's own tooltip shows.
local _, root = ...
local ft = {}
root.FriendTips = ft

ft.DEFAULTS = { icons = true, levelColor = true, race = true, realm = true, note = true, broadcast = true }
ft.hooked = false

local issecret = issecretvalue or function() return false end
local function Str(v)
    return type(v) == "string" and not issecret(v) and v ~= "" and v or nil
end
local function Num(v)
    return type(v) == "number" and not issecret(v) and v or nil
end

local ACCENT_HEX = root.ACCENT_HEX or "40e0d0"
local BNET_HEX, DIM_HEX, LABEL_HEX = "82c5ff", "8a8f96", "b8bcc2"
local FACTION_HEX = { Alliance = "4a8cff", Horde = "ff4040" }
local FACTION_ICON = {
    Alliance = "Interface\\FriendsFrame\\PlusManz-Alliance",
    Horde = "Interface\\FriendsFrame\\PlusManz-Horde",
}
local CLASS_TEX = "Interface\\WorldStateFrame\\Icons-Classes"
local ZONE_ICON = "|TInterface\\Icons\\INV_Misc_Map_01:16:16:0:0:64:64:5:59:5:59|t "
local GROUP_ICON = "|TInterface\\Icons\\Spell_Holy_PrayerOfSpirit:16:16:0:0:64:64:5:59:5:59|t "
local SIZE = 16

local function Hex(c)
    if not c then return nil end
    local r, g, b = c.r or c[1], c.g or c[2], c.b or c[3]
    if not (r and g and b) then return nil end
    return ("%02x%02x%02x"):format(r * 255, g * 255, b * 255)
end

local function Kit() return EllesmereUI and EllesmereUI.FriendsKit and EllesmereUI.FriendsKit._tile end

-- class token (DRUID) for an account
local function ClassFile(info, gi)
    local kit = Kit()
    if kit and kit.ClassFile then
        local ok, file = pcall(kit.ClassFile, info)
        if ok and Str(file) then return file end
    end
    local id = Num(gi.classID)
    if id and id > 0 and GetClassInfo then
        local _, file = GetClassInfo(id)
        if Str(file) then return file end
    end
    local name = Str(gi.className)
    if name then
        for _, list in ipairs({ LOCALIZED_CLASS_NAMES_MALE or {}, LOCALIZED_CLASS_NAMES_FEMALE or {} }) do
            for token, loc in pairs(list) do
                if loc == name then return token end
            end
        end
        return name:upper()
    end
end

local function ClassIcon(file)
    local c = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[file]
    if not c then return "" end
    return ("|T%s:%d:%d:0:0:256:256:%d:%d:%d:%d|t "):format(CLASS_TEX, SIZE, SIZE,
        c[1] * 256 + 4, c[2] * 256 - 4, c[3] * 256 + 4, c[4] * 256 - 4)
end

local function ClassHex(file)
    local c = (C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(file))
        or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[file])
    return Hex(c) or "ffffff"
end

local function LevelHex(level)
    if not (ft.db.levelColor and GetQuestDifficultyColor) then return "ffffff" end
    local ok, c = pcall(GetQuestDifficultyColor, level)
    return ok and Hex(c) or "ffffff"
end

local function AccountName(info)
    local kit = Kit()
    if kit and kit.Name then
        local ok, name = pcall(kit.Name, info)
        if ok and Str(name) then return name end
    end
    return Str(info.accountName) or Str(info.battleTag) or "?"
end

local function RealmText(info, gi)
    local realm = Str(gi.realmDisplayName) or Str(gi.realmName)
    local kit = Kit()
    local ruleset
    if kit and kit.Ruleset then
        local ok, r = pcall(kit.Ruleset, info)
        if ok then ruleset = Str(r) end
    end
    -- Forever's realm names are internal ("CAMWOWUS2Realm10RPPvP"): the ruleset says more
    if realm and realm:find("Realm%d") then realm = nil end
    if realm and ruleset then return realm .. " (" .. ruleset .. ")" end
    return realm or ruleset
end

local function SameGame(gi)
    if not (gi and gi.isOnline) then return false end
    if gi.clientProgram ~= (BNET_CLIENT_WOW or "WoW") then return false end
    return gi.wowProjectID == WOW_PROJECT_ID or gi.wowProjectID == nil
end

local function LastOnline(info)
    local U = FriendsListUtil
    if U and U.GetLastOnlineText then
        local ok, text = pcall(U.GetLastOnlineText, info)
        if ok and Str(text) then return text end
    end
end

-- every WoW character the friend is logged in with (a friend can run two
-- clients at once), same game first; other games come as rich presence
function ft.GameAccounts(rec)
    local info = rec.info
    local list, seen = {}, {}
    local count = C_BattleNet and C_BattleNet.GetFriendNumGameAccounts and Num(rec.index)
        and C_BattleNet.GetFriendNumGameAccounts(rec.index)
    if Num(count) and count > 0 then
        for i = 1, count do
            local gi = C_BattleNet.GetFriendGameAccountInfo(rec.index, i)
            local id = gi and Num(gi.gameAccountID)
            if type(gi) == "table" and gi.isOnline and not (id and seen[id]) then
                if id then seen[id] = true end
                list[#list + 1] = gi
            end
        end
    end
    local main = type(info.gameAccountInfo) == "table" and info.gameAccountInfo or nil
    if #list == 0 and main and main.isOnline then list[1] = main end
    -- same game first, the character Battle.net names as the main one first
    local mainID = main and Num(main.gameAccountID)
    local function rank(gi)
        if not SameGame(gi) then return 2 end
        return (mainID and Num(gi.gameAccountID) == mainID) and 0 or 1
    end
    table.sort(list, function(a, b)
        local ra, rb = rank(a), rank(b)
        if ra ~= rb then return ra < rb end
        return (Str(a.characterName) or "") < (Str(b.characterName) or "")
    end)
    return list
end

local function Status(info, games)
    if #games == 0 then return ("|cff%sOffline|r"):format(DIM_HEX) end
    if info.isDND then return "|cffff4040Busy|r" end
    if info.isAFK then return "|cffffd100Away|r" end
    return "|cff40ff40Online|r"
end

-- fills the game tooltip for one friend record; false when nothing to show
function ft.Fill(tip, rec)
    local info = rec and rec.info
    if type(info) ~= "table" then return false end
    local db = ft.db or ft.DEFAULTS
    local icons = db.icons
    local games = ft.GameAccounts(rec)

    local fav = info.isFavorite and " |cffffd100*|r" or ""
    tip:AddDoubleLine(("|cff%s%s|r%s"):format(BNET_HEX, AccountName(info), fav), Status(info, games))

    local shownChar = false
    for _, gi in ipairs(games) do
        if SameGame(gi) and Str(gi.characterName) then
            if shownChar then tip:AddLine(" ") end
            shownChar = true
            local file = ClassFile({ gameAccountInfo = gi }, gi)
            local classHex = file and ClassHex(file) or "ffffff"
            local level = Num(gi.characterLevel)
            local afk = gi.isGameAFK and (" |cff%s(AFK)|r"):format(DIM_HEX) or (gi.isGameBusy and (" |cff%s(Busy)|r"):format(DIM_HEX)) or ""
            tip:AddDoubleLine((icons and file and ClassIcon(file) or "") .. ("|cff%s%s|r"):format(classHex, gi.characterName) .. afk,
                level and ("|cff%sLevel %d|r"):format(LevelHex(level), level) or "")
            local who = {}
            if db.race and Str(gi.raceName) then who[#who + 1] = gi.raceName end
            if Str(gi.className) then who[#who + 1] = ("|cff%s%s|r"):format(classHex, gi.className) end
            local faction = Str(gi.factionName)
            local right = ""
            if faction then
                right = (icons and FACTION_ICON[faction] and ("|T%s:%d:%d|t "):format(FACTION_ICON[faction], SIZE, SIZE) or "")
                    .. ("|cff%s%s|r"):format(FACTION_HEX[faction] or "ffffff", faction)
            end
            tip:AddDoubleLine(table.concat(who, " "), right, 1, 1, 1)
            local realm = db.realm and RealmText({ gameAccountInfo = gi }, gi)
            if Str(gi.areaName) or realm then
                tip:AddDoubleLine((Str(gi.areaName) and ((icons and ZONE_ICON or "") .. gi.areaName) or ""),
                    realm and ("|cff%s%s|r"):format(DIM_HEX, realm) or "", 1, 1, 1)
            end
            if gi.isInCurrentPlayerGroup then
                tip:AddLine((icons and GROUP_ICON or "") .. ("|cff%sIn your group|r"):format(ACCENT_HEX))
            end
        end
    end
    for _, gi in ipairs(games) do
        if not SameGame(gi) then
            local presence = Str(gi.richPresence) or Str(gi.clientProgram)
            if presence then tip:AddLine(("|cff%s%s|r"):format(LABEL_HEX, presence), 1, 1, 1, true) end
        end
    end
    if #games == 0 then
        local last = LastOnline(info)
        if last then tip:AddLine(("|cff%s%s|r"):format(DIM_HEX, last)) end
    end

    local note = db.note and Str(info.note)
    if note and EllesmereUI and EllesmereUI.StripFriendNoteTag then
        local ok, stripped = pcall(EllesmereUI.StripFriendNoteTag, note)
        if ok then note = Str(stripped) end
    end
    local broadcast = db.broadcast and Str(info.customMessage)
    if note or broadcast then tip:AddLine(" ") end
    if note then tip:AddLine(("|cff%sNote:|r %s"):format(DIM_HEX, note), 1, 1, 1, true) end
    if broadcast then tip:AddLine(("|cff%s%s|r"):format(BNET_HEX, broadcast), 1, 1, 1, true) end
    return true
end

-- the friend's tooltip on the game tooltip, which EllesmereUI skins like
-- every other tooltip (its background, black border and font size)
function ft.Show(row, rec)
    local tip = GameTooltip
    if not tip or tip:IsForbidden() then return false end
    tip:SetOwner(row, "ANCHOR_NONE")
    tip:ClearAllPoints()
    tip:SetPoint("TOPLEFT", row, "TOPRIGHT", 6, 0)
    local ok, filled = pcall(ft.Fill, tip, rec)
    if not (ok and filled) then
        tip:Hide()
        return false
    end
    tip:Show()
    ft.owner = row
    ft.shown = (ft.shown or 0) + 1
    return true
end

function ft.Hook()
    if ft.hooked then return true end
    local eui = EllesmereUI
    local show, hide = type(eui) == "table" and eui.ShowWidgetTooltip, type(eui) == "table" and eui.HideWidgetTooltip
    if type(show) ~= "function" or type(hide) ~= "function" then return false end
    eui.ShowWidgetTooltip = function(label, text, opts, ...)
        if ft.db and type(label) == "table" then
            local rec = rawget(label, "rec")
            if type(rec) == "table" and type(rec.info) == "table" and ft.Show(label, rec) then
                hide(true)   -- EllesmereUI's small one stays away
                return
            end
        end
        return show(label, text, opts, ...)
    end
    eui.HideWidgetTooltip = function(...)
        local owner = ft.owner
        if owner then
            ft.owner = nil
            if GameTooltip and GameTooltip:IsOwned(owner) then GameTooltip:Hide() end
        end
        return hide(...)
    end
    ft.hooked = true
    return true
end

function ft.Set(key, value)
    if ft.db then ft.db[key] = value and true or false end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, name)
    if name == "MirogaUtilities" then
        if root.Off("FriendTips", self) then return end
        if type(MirogaUtilitiesDB) ~= "table" then MirogaUtilitiesDB = {} end
        MirogaUtilitiesDB.friendTips = MirogaUtilitiesDB.friendTips or {}
        ft.db = MirogaUtilitiesDB.friendTips
        for key, value in pairs(ft.DEFAULTS) do
            if ft.db[key] == nil then ft.db[key] = value end
        end
    end
    if ft.db and ft.Hook() then self:UnregisterEvent("ADDON_LOADED") end
end)
