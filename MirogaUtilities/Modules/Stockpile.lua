-- Stockpile: items you keep for later instead of selling them today.
--
-- * Hold list: your own items (/mu h on the item under the mouse, or the
--   hub) plus an optional preset of raid materials. Held items get a green
--   hourglass in the bags instead of the red vendor coin.
-- * Cheap hint: the tooltip says when today's AH price is far below the
--   average of the days before (Auctionator's price history).
-- * Snipe: every held item goes into the Auctionator shopping list
--   "Miroga Hold" with a max price (your target, or the cheap line), so one
--   click at the AH searches all of them. After each Auctionator scan the
--   chat names held items that are at or under that price.
--
-- * Old prices: the tooltip warns when an item's AH price is a day old or
--   more, and the chat at the AH when the last Auctionator scan is.
--
-- The preset (Forever data, Nov 2026): reagents of the level 300 flasks and
-- the best elixirs, top enchanting materials and the rare bars and
-- essences of the max-level recipes. Raids open on Dec 9; these are what
-- raiders and crafters buy. Leveling materials (Thorium, Runecloth, Rugged
-- Leather) are left out: they get cheaper once fewer players level.
local _, root = ...
local sp = {}
root.Stockpile = sp

local CALLER = "MirogaUtilities"
local LIST_NAME = "Miroga Hold"
sp.LIST_NAME = LIST_NAME

sp.PRESET = {
    { group = "Flask herbs" },
    { 13468, "Black Lotus", "every flask of the titans, wisdom, power, chromatic" },
    { 248822, "Death Lotus", "every new Forever flask" },
    { 248821, "Demonsage", "Flask of Natural Accuracy / Aggression" },
    { 248823, "Marefoil", "Flask of Natural Precision / Swiftness" },
    { 13463, "Dreamfoil", "flasks, Greater Arcane, Mageblood, protection potions" },
    { 13465, "Mountain Silversage", "flasks, Mongoose, Greater Arcane" },
    { 13467, "Icecap", "flasks, Greater Frost Protection" },
    { 13464, "Golden Sansam", "flasks, Forever elixirs" },
    { 8846, "Gromsblood", "Flask of the Titans, Giants, Demonslaying" },
    { 13466, "Plaguebloom", "Mongoose, Mageblood, Greater Nature Protection" },
    { 13423, "Stonescale Oil", "Flask of the Titans, Greater Stoneshield" },
    { group = "Enchanting" },
    { 14344, "Large Brilliant Shard", "every high weapon and chest enchant" },
    { 20725, "Nexus Crystal", "the best enchants" },
    { 16203, "Greater Eternal Essence", "max-level enchants" },
    { 16204, "Illusion Dust", "max-level enchants" },
    { 274030, "Malleable Essence of Nature", "new Forever enchants and crafts" },
    { group = "Bars and essences" },
    { 12363, "Arcane Crystal", "Arcanite Bar" },
    { 12360, "Arcanite Bar", "max-level weapons and armor" },
    { 251291, "Heavy Thorium Bar", "new Forever crafts" },
    { 251290, "Legionite Bar", "new Forever crafts" },
    { 249726, "Azerothium Bar", "new Forever crafts" },
    { 12811, "Righteous Orb", "max-level crafts" },
    { 12803, "Living Essence", "max-level crafts" },
    { 7078, "Essence of Fire", "fire resistance gear" },
    { 7076, "Essence of Earth", "max-level crafts" },
    { 7080, "Essence of Water", "max-level crafts" },
    { 7082, "Essence of Air", "max-level crafts" },
    { 12808, "Essence of Undeath", "max-level crafts" },
    { 19726, "Bloodvine", "max-level crafts" },
    { 17010, "Fiery Core", "fire resistance gear" },
    { 17011, "Lava Core", "fire resistance gear" },
    { group = "Cloth and leather" },
    { 14227, "Ironweb Spider Silk", "max-level tailoring" },
    { 14342, "Mooncloth", "max-level tailoring" },
    { 12810, "Enchanted Leather", "max-level leatherworking" },
    { 248825, "Fel Leather", "new Forever leatherworking" },
}
local presetSet = {}
for _, entry in ipairs(sp.PRESET) do
    if entry[1] then presetSet[entry[1]] = entry end
end
sp.presetSet = presetSet

sp.DEFAULTS = {
    preset = true, tooltip = true, alerts = true, cheapPct = 60, stale = true,
    items = {}, removed = {}, alerted = {},
}

local GetItemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
local GetItemInfoInstant = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant

local function Changed()
    if root.VendorCoin and root.VendorCoin.Refresh then
        root.VendorCoin.Refresh()
    elseif sp.OnChange then
        sp.OnChange()
    end
end

function sp.ItemID(item)
    if type(item) == "number" then return item end
    if type(item) ~= "string" then return nil end
    local id = tonumber(item) or tonumber(item:match("item:(%d+)"))
    if not id and GetItemInfoInstant then id = GetItemInfoInstant(item) end
    return id
end

-- ---------------------------------------------------------------------------
-- the hold list

function sp.IsHeld(item)
    local db, id = sp.db, sp.ItemID(item)
    if not db or not id then return false end
    if db.items[id] then return true end
    return db.preset and presetSet[id] ~= nil and not db.removed[id]
end

function sp.Toggle(item)
    local db, id = sp.db, sp.ItemID(item)
    if not db or not id then return end
    local held
    if sp.IsHeld(id) then
        db.items[id] = nil
        if presetSet[id] then db.removed[id] = true end
        held = false
    else
        db.removed[id] = nil
        if not (db.preset and presetSet[id]) then db.items[id] = {} end
        held = true
    end
    Changed()
    return held
end

-- target in copper, nil clears it
function sp.SetTarget(item, copper)
    local db, id = sp.db, sp.ItemID(item)
    if not db or not id then return end
    if not sp.IsHeld(id) then sp.Toggle(id) end
    db.items[id] = db.items[id] or {}
    db.items[id].target = copper and copper > 0 and math.floor(copper) or nil
    db.alerted[id] = nil
    Changed()
end

function sp.Target(id)
    local entry = sp.db and sp.db.items[id]
    return entry and entry.target
end

-- every held item ID, presets first in their order, then your own sorted
function sp.HeldList()
    local db, list, seen = sp.db, {}, {}
    if not db then return list end
    if db.preset then
        for _, entry in ipairs(sp.PRESET) do
            local id = entry[1]
            if id and not db.removed[id] then
                list[#list + 1] = id
                seen[id] = true
            end
        end
    end
    local own = {}
    for id in pairs(db.items) do
        if not seen[id] then own[#own + 1] = id end
    end
    table.sort(own, function(a, b)
        return (GetItemInfo(a) or tostring(a)) < (GetItemInfo(b) or tostring(b))
    end)
    for _, id in ipairs(own) do list[#list + 1] = id end
    return list
end

function sp.Name(id)
    local name = GetItemInfo(id)
    if name then return name end
    local entry = presetSet[id]
    return entry and entry[2] or ("item " .. id)
end

-- ---------------------------------------------------------------------------
-- prices: today and the days before

local function Auctionator_OK()
    return Auctionator and Auctionator.API and Auctionator.API.v1
        and Auctionator.API.v1.GetAuctionPriceByItemID
end

function sp.HasAuctionator()
    return Auctionator_OK() and true or false
end

-- now = Auctionator's last price, avg = mean low of up to 7 days before the
-- newest day, days = how many of those days there were
function sp.Prices(id)
    if not Auctionator_OK() then return nil end
    local ok, now = pcall(Auctionator.API.v1.GetAuctionPriceByItemID, CALLER, id)
    now = ok and now or nil
    local avg, days
    local database = Auctionator.Database
    if database and database.GetPriceHistory then
        local okHistory, history = pcall(database.GetPriceHistory, database, tostring(id))
        if okHistory and type(history) == "table" and #history > 1 then
            local total, count = 0, 0
            -- history is newest first; skip the newest day (that is "now")
            for i = 2, math.min(#history, 8) do
                local low = history[i].minSeen
                if low and low > 0 then
                    total, count = total + low, count + 1
                end
            end
            if count > 0 then avg, days = total / count, count end
        end
    end
    return now, avg, days
end

local MIN_DAYS = 3

-- true when today's price is under cheapPct of the average before
function sp.IsCheap(id)
    local now, avg, days = sp.Prices(id)
    if not now or not avg or (days or 0) < MIN_DAYS then return false, now, avg end
    local pct = (sp.db or sp.DEFAULTS).cheapPct
    return now <= avg * pct / 100, now, avg
end

-- the price a snipe buys at: your target, else the cheap line
function sp.SnipePrice(id)
    local target = sp.Target(id)
    if target then return target, true end
    local _, avg, days = sp.Prices(id)
    if avg and (days or 0) >= MIN_DAYS then
        return math.floor(avg * (sp.db or sp.DEFAULTS).cheapPct / 100), false
    end
end

-- days since Auctionator last saw the item (0 = today), nil = never / > 21
function sp.ItemAge(id)
    if not (Auctionator_OK() and Auctionator.API.v1.GetAuctionAgeByItemID) then return nil end
    local ok, age = pcall(Auctionator.API.v1.GetAuctionAgeByItemID, CALLER, id)
    return ok and age or nil
end

-- seconds since the newest Auctionator scan of any kind, nil = none known
function sp.ScanAge()
    local state = Auctionator and Auctionator.SavedState
    if type(state) ~= "table" then return nil end
    local newest
    for _, key in ipairs({ "TimeOfLastReplicateScan", "TimeOfLastGetAllScan", "TimeOfLastBrowseScan" }) do
        local t = tonumber(state[key])
        if t and (not newest or t > newest) then newest = t end
    end
    return newest and (time() - newest) or nil
end

function sp.AgeText(seconds)
    if not seconds then return "never" end
    if seconds < 3600 then return math.floor(seconds / 60) .. " min ago" end
    if seconds < 86400 then return math.floor(seconds / 3600) .. " h ago" end
    local days = math.floor(seconds / 86400)
    return days .. (days == 1 and " day ago" or " days ago")
end

local DAY = 86400
local function WarnOldScan()
    if not (sp.db and sp.db.stale and sp.HasAuctionator()) then return end
    local age = sp.ScanAge()
    if not age or age >= DAY then
        root.Say(("|cffff9933Old prices:|r last Auctionator scan %s. Scan before you trust coins and snipes."):format(sp.AgeText(age)))
    end
end
sp.WarnOldScan = WarnOldScan

-- ---------------------------------------------------------------------------
-- Auctionator shopping list

function sp.SyncAuctionator(quiet)
    if not (Auctionator_OK() and Auctionator.API.v1.CreateShoppingList
        and Auctionator.API.v1.ConvertToSearchString) then
        if not quiet then root.Say("Auctionator is not loaded.") end
        return
    end
    local terms, missing = {}, 0
    for _, id in ipairs(sp.HeldList()) do
        local name = GetItemInfo(id)
        if name then
            local maxPrice = sp.SnipePrice(id)
            local ok, term = pcall(Auctionator.API.v1.ConvertToSearchString, CALLER,
                { searchString = name, isExact = true, maxPrice = maxPrice })
            if ok and term then terms[#terms + 1] = term end
        else
            missing = missing + 1
            if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
        end
    end
    local ok = pcall(Auctionator.API.v1.CreateShoppingList, CALLER, LIST_NAME, terms)
    if not quiet then
        if ok then
            root.Say(("%d items in Auctionator's list |cff%s%s|r%s."):format(#terms, root.ACCENT_HEX, LIST_NAME,
                missing > 0 and (" (" .. missing .. " not loaded yet, try again)") or ""))
        else
            root.Say("Auctionator did not take the list.")
        end
    end
end

-- after an Auctionator scan: held items at or under their snipe price
local function CheckSnipes()
    local db = sp.db
    if not db or not db.alerts then return end
    local hits = {}
    for _, id in ipairs(sp.HeldList()) do
        local now = sp.Prices(id)
        local limit = sp.SnipePrice(id)
        if now and limit and now <= limit then
            if db.alerted[id] ~= now then
                db.alerted[id] = now
                local link = select(2, GetItemInfo(id)) or sp.Name(id)
                hits[#hits + 1] = link .. " " .. GetMoneyString(now, true)
            end
        else
            db.alerted[id] = nil
        end
    end
    if #hits > 0 then
        root.Say("|cff40ff60Snipe:|r " .. table.concat(hits, ", ") .. "  (list: " .. LIST_NAME .. ")")
    end
end

-- ---------------------------------------------------------------------------
-- tooltip

local function Money(c) return GetMoneyString(math.max(0, math.floor(c + 0.5)), true) end

local function AddLines(tooltip)
    local db = sp.db
    if not db or not tooltip or not tooltip.GetItem then return end
    local ok, _, link = pcall(tooltip.GetItem, tooltip)
    if not ok or not link then return end
    local id = sp.ItemID(link)
    if not id then return end
    local held = sp.IsHeld(id)
    local cheap, now, avg
    if db.tooltip or held then cheap, now, avg = sp.IsCheap(id) end
    if held then
        local target = sp.Target(id)
        tooltip:AddLine("|cff40ff60Miroga: hold|r" .. (target and ("  target " .. Money(target)) or ""))
    end
    if now and avg and (cheap or held) then
        local diff = (now / avg - 1) * 100
        tooltip:AddLine(("%sAH %s  vs  %s average (%+d %%)|r"):format(
            cheap and "|cff40ff60Cheap now: " or "|cffaaaaaa", Money(now), Money(avg), math.floor(diff + 0.5)))
    end
    if db.stale then
        local age = sp.ItemAge(id)
        if age and age >= 1 then
            tooltip:AddLine(("|cffff9933AH price %d %s old: scan again before you decide.|r"):format(age, age == 1 and "day" or "days"))
        end
    end
    tooltip:Show()
end

local function HookTooltips()
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip)
            if tooltip == GameTooltip or tooltip == ItemRefTooltip then AddLines(tooltip) end
        end)
    elseif GameTooltip.HookScript then
        GameTooltip:HookScript("OnTooltipSetItem", AddLines)
        if ItemRefTooltip then ItemRefTooltip:HookScript("OnTooltipSetItem", AddLines) end
    end
end

-- ---------------------------------------------------------------------------
-- /mu h

local function MouseItem()
    local ok, _, link = pcall(GameTooltip.GetItem, GameTooltip)
    if ok and link and GameTooltip:IsShown() then return link end
end

function sp.ToggleMouse()
    local link = MouseItem()
    if not link then
        root.Say("Point at an item and press the key (or /mu h) again.")
        return
    end
    local held = sp.Toggle(link)
    root.Say(link .. (held and " |cff40ff60held|r: no vendor coin, on the snipe list." or " no longer held."))
end
MirogaUtilities_ToggleHold = sp.ToggleMouse
BINDING_NAME_MIROGA_HOLD = "Stockpile: hold / release item under mouse"

-- "12.5" or "12g50s" or "1g 2s 3c" -> copper
function sp.ParseMoney(text)
    text = strlower(strtrim(text or ""))
    if text == "" then return nil end
    local plain = tonumber(text)
    if plain then return math.floor(plain * 10000 + 0.5) end
    local total, found = 0, false
    for number, unit in text:gmatch("([%d%.]+)%s*([gsc])") do
        local n = tonumber(number)
        if n then
            found = true
            total = total + n * (unit == "g" and 10000 or unit == "s" and 100 or 1)
        end
    end
    return found and math.floor(total + 0.5) or nil
end

function sp.Slash(rest)
    rest = strtrim(rest or "")
    if rest == "" then return sp.ToggleMouse() end
    if rest == "sync" then return sp.SyncAuctionator() end
    local copper = sp.ParseMoney(rest)
    local link = MouseItem()
    if copper and link then
        sp.SetTarget(link, copper)
        root.Say(link .. " target " .. Money(copper) .. ".")
        return
    end
    return false
end

-- ---------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self, event, addon)
    if event == "ADDON_LOADED" and addon == "MirogaUtilities" then
        if type(MirogaStockpileDB) ~= "table" then MirogaStockpileDB = {} end
        local db = MirogaStockpileDB
        for key, value in pairs(sp.DEFAULTS) do
            if db[key] == nil then db[key] = type(value) == "table" and {} or value end
        end
        sp.db = db
    elseif event == "PLAYER_LOGIN" then
        HookTooltips()
        if Auctionator_OK() and Auctionator.API.v1.RegisterForDBUpdate then
            pcall(Auctionator.API.v1.RegisterForDBUpdate, CALLER, function()
                CheckSnipes()
                if sp.OnChange then sp.OnChange() end
            end)
        end
        -- warm the item cache so names exist for the list and the hub
        if C_Item and C_Item.RequestLoadItemDataByID then
            for _, id in ipairs(sp.HeldList()) do C_Item.RequestLoadItemDataByID(id) end
        end
        self:RegisterEvent("AUCTION_HOUSE_SHOW")
        -- after the login chat has settled (login quiet sweeps for 10 s)
        C_Timer.After(15, WarnOldScan)
    elseif event == "AUCTION_HOUSE_SHOW" then
        -- fresh max prices every visit; quiet, Auctionator shows the list
        sp.SyncAuctionator(true)
        WarnOldScan()
    end
end)
