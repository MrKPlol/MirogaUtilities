-- Friend tooltips: EllesmereUI's own friends list (since 9.8.9) shows a slim
-- tooltip on its rows. This one shows what Blizzard's card showed and more,
-- with class, faction and zone icons, in EllesmereUI's own tooltip frame (its
-- background, border and font), so it looks like the rest of the UI.
--
-- How: EllesmereUI_FriendsList.lua calls EllesmereUI.ShowWidgetTooltip(row,
-- text, opts) by table lookup on every hover. The wrapper swaps the text when
-- the row carries a friend record (row.rec.info, a Battle.net account info),
-- and passes everything else through. Nothing in EllesmereUI's files changes;
-- if building the text fails, EllesmereUI's own text shows.
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
local ZONE_ICON = "|TInterface\\Icons\\INV_Misc_Map_01:12:12:0:0:64:64:5:59:5:59|t "
local GROUP_ICON = "|TInterface\\Icons\\Spell_Holy_PrayerOfSpirit:12:12:0:0:64:64:5:59:5:59|t "
local SIZE = 12

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

-- the tooltip text for one friend record
function ft.Build(rec)
    local info = rec and rec.info
    if type(info) ~= "table" then return nil end
    local gi = type(info.gameAccountInfo) == "table" and info.gameAccountInfo or nil
    local db = ft.db or ft.DEFAULTS
    local icons = db.icons
    local lines = {}
    local function Add(text) lines[#lines + 1] = text end

    local fav = info.isFavorite and " |cffffd100*|r" or ""
    Add(("|cff%s%s|r%s"):format(BNET_HEX, AccountName(info), fav))

    if SameGame(gi) and Str(gi.characterName) then
        local file = ClassFile(info, gi)
        local nameLine = (icons and file and ClassIcon(file) or "") ..
            ("|cff%s%s|r"):format(file and ClassHex(file) or "ffffff", gi.characterName)
        local realm = db.realm and RealmText(info, gi)
        if realm then nameLine = nameLine .. ("|cff%s - %s|r"):format(DIM_HEX, realm) end
        Add(nameLine)

        local level = Num(gi.characterLevel)
        local parts = {}
        if level then parts[#parts + 1] = ("|cff%sLevel %d|r"):format(LevelHex(level), level) end
        if db.race and Str(gi.raceName) then parts[#parts + 1] = gi.raceName end
        if Str(gi.className) then parts[#parts + 1] = ("|cff%s%s|r"):format(file and ClassHex(file) or "ffffff", gi.className) end
        if #parts > 0 then Add(table.concat(parts, " ")) end

        local faction = Str(gi.factionName)
        if faction then
            local icon = icons and FACTION_ICON[faction] and ("|T%s:%d:%d|t "):format(FACTION_ICON[faction], SIZE, SIZE) or ""
            Add(icon .. ("|cff%s%s|r"):format(FACTION_HEX[faction] or "ffffff", faction))
        end
        if Str(gi.areaName) then Add((icons and ZONE_ICON or "") .. gi.areaName) end
        if gi.isInCurrentPlayerGroup then Add((icons and GROUP_ICON or "") .. ("|cff%sIn your group|r"):format(ACCENT_HEX)) end
    elseif gi and gi.isOnline then
        local presence = Str(gi.richPresence)
        if presence then Add(("|cff%s%s|r"):format(LABEL_HEX, presence)) end
    else
        local last = LastOnline(info)
        Add(("|cff%s%s|r"):format(DIM_HEX, last or "Offline"))
    end

    if db.note then
        local note = Str(info.note)
        if note and EllesmereUI and EllesmereUI.StripFriendNoteTag then
            local ok, stripped = pcall(EllesmereUI.StripFriendNoteTag, note)
            if ok then note = Str(stripped) end
        end
        if note then Add(("|cff%sNote:|r %s"):format(DIM_HEX, note)) end
    end
    if db.broadcast then
        local text = Str(info.customMessage)
        if text then Add(("|cff%s%s|r"):format(BNET_HEX, text)) end
    end
    return table.concat(lines, "\n")
end

local TIP_OPTS = { anchor = "right", justify = "LEFT", width = 240 }

function ft.Hook()
    if ft.hooked then return true end
    local eui = EllesmereUI
    local original = type(eui) == "table" and eui.ShowWidgetTooltip
    if type(original) ~= "function" then return false end
    eui.ShowWidgetTooltip = function(label, text, opts, ...)
        if ft.db and type(label) == "table" then
            local rec = rawget(label, "rec")
            if type(rec) == "table" and type(rec.info) == "table" then
                local ok, rich = pcall(ft.Build, rec)
                if ok and rich then
                    ft.shown = (ft.shown or 0) + 1
                    return original(label, rich, TIP_OPTS, ...)
                end
            end
        end
        return original(label, text, opts, ...)
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
