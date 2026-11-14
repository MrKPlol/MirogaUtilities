-- Vendor coin: a red coin in the bottom right corner of every bag item that
-- brings more at the vendor than on the auction house.
--
-- AH side, per unit:  Auctionator price  - cut (5 %)  - effort (3 %)  - deposit
-- Effort is your own work for listing and relisting, on top of the cut.
-- The deposit only stays with the AH if the auction does not sell, so it is a
-- switch: on = count one failed listing (careful), off = the item sells.
-- Forever works the deposit out on the server. While the AH is open the
-- module asks it once per listing time and keeps the rate (deposit divided
-- by vendor price); until then it uses 15 % as a guess.
--
-- Bags: Baganator corner widget ("Miroga: vendor beats AH"). Without
-- Baganator the plain Blizzard bags get the coin directly.
local _, root = ...
local vc = {}
root.VendorCoin = vc

local CALLER = "MirogaUtilities"
local GUESS_RATE = 0.15
vc.DURATIONS = { { 1, "2 hours" }, { 2, "8 hours" }, { 3, "24 hours" } }
vc.DEFAULTS = {
    enabled = true, cut = 5, effort = 3, deposit = true, duration = 3,
    bound = false, rates = {},
}

local GetItemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo

local function Auctionator_OK()
    return Auctionator and Auctionator.API and Auctionator.API.v1
        and Auctionator.API.v1.GetAuctionPriceByItemLink
end

function vc.HasAuctionator()
    return Auctionator_OK() and true or false
end

-- deposit rate for the chosen listing time, and whether it was measured
function vc.Rate()
    local db = vc.db or vc.DEFAULTS
    local rate = db.rates and db.rates[db.duration]
    if rate then return rate, true end
    return GUESS_RATE, false
end

-- all numbers per unit, in copper. nil = not decidable (no data yet)
function vc.Evaluate(itemLink)
    if type(itemLink) ~= "string" or not Auctionator_OK() then return nil end
    local sellPrice = select(11, GetItemInfo(itemLink))
    if sellPrice == nil then return nil end
    if sellPrice <= 0 then return false end
    local ok, ah = pcall(Auctionator.API.v1.GetAuctionPriceByItemLink, CALLER, itemLink)
    if not ok or not ah or ah <= 0 then return false end
    local db = vc.db or vc.DEFAULTS
    local net = ah * (1 - (db.cut + (db.effort or 0)) / 100)
    local deposit = 0
    if db.deposit then deposit = sellPrice * vc.Rate() end
    net = net - deposit
    return sellPrice > net, sellPrice, ah, net, deposit
end

-- a bag slot: true = coin
local function ShouldMark(itemLink, isBound)
    local db = vc.db
    if not db or not db.enabled then return false end
    if isBound and not db.bound then return false end
    return vc.Evaluate(itemLink)
end

-- ---------------------------------------------------------------------------
-- the coin

local function MakeCoin(parent)
    local coin = parent:CreateTexture(nil, "OVERLAY", nil, 7)
    coin:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
    coin:SetDesaturated(true)
    coin:SetVertexColor(1, 0.12, 0.12)
    coin:SetSize(14, 14)
    return coin
end

-- ---------------------------------------------------------------------------
-- Baganator

local WIDGET_ID = "miroga_vendor_coin"
local usingBaganator = false

local function RegisterBaganator()
    if usingBaganator or not (Baganator and Baganator.API and Baganator.API.RegisterCornerWidget) then
        return
    end
    usingBaganator = true
    Baganator.API.RegisterCornerWidget("Miroga: vendor beats AH", WIDGET_ID,
        function(coin, details)
            if not details or not details.itemLink then return false end
            return ShouldMark(details.itemLink, details.isBound)
        end,
        function(itemButton)
            local frame = CreateFrame("Frame", nil, itemButton)
            frame:SetSize(14, 14)
            frame.padding = 0
            MakeCoin(frame):SetAllPoints()
            return frame
        end,
        { corner = "bottom_right", priority = 1 })
end

-- ---------------------------------------------------------------------------
-- Blizzard bags (only when Baganator is not there)

local hooked = {}

local function UpdateButton(button)
    if not button or not button.GetBagID then return end
    local mark = false
    local bag, slot = button:GetBagID(), button:GetID()
    if bag and slot and C_Container then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info and info.hyperlink then
            mark = ShouldMark(info.hyperlink, info.isBound) == true
        end
    end
    if mark and not button.MirogaVendorCoin then
        button.MirogaVendorCoin = MakeCoin(button)
        button.MirogaVendorCoin:SetPoint("BOTTOMRIGHT", -2, 2)
    end
    if button.MirogaVendorCoin then button.MirogaVendorCoin:SetShown(mark) end
end

local function UpdateFrame(frame)
    if not frame.EnumerateValidItems then return end
    for _, button in frame:EnumerateValidItems() do UpdateButton(button) end
end

local function HookBlizzard()
    if usingBaganator then return end
    local frames = {}
    if ContainerFrameCombinedBags then frames[#frames + 1] = ContainerFrameCombinedBags end
    local i = 1
    while _G["ContainerFrame" .. i] do
        frames[#frames + 1] = _G["ContainerFrame" .. i]
        i = i + 1
    end
    for _, frame in ipairs(frames) do
        if not hooked[frame] and frame.UpdateItems then
            hooked[frame] = true
            hooksecurefunc(frame, "UpdateItems", UpdateFrame)
        end
    end
end

-- ---------------------------------------------------------------------------
-- refresh after a scan or a settings change

function vc.Refresh()
    if usingBaganator then
        if Baganator.API.RequestItemButtonsRefresh then Baganator.API.RequestItemButtonsRefresh() end
    else
        for frame in pairs(hooked) do
            if frame:IsShown() then UpdateFrame(frame) end
        end
    end
    if vc.OnChange then vc.OnChange() end
end

function vc.Set(key, value)
    if not vc.db then return end
    vc.db[key] = value
    vc.Refresh()
end

-- ---------------------------------------------------------------------------
-- deposit rate, measured at the open AH

local function MeasureDeposit()
    local db = vc.db
    if not db or not C_AuctionHouse or not C_AuctionHouse.CalculateItemDeposit then return end
    if not (C_Container and ItemLocation) then return end
    local best
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.hyperlink and not info.isBound then
                local sellPrice = select(11, GetItemInfo(info.hyperlink))
                -- the bigger the vendor price, the less rounding in the rate
                if sellPrice and sellPrice >= 100 and (not best or sellPrice > best.price) then
                    local location = ItemLocation:CreateFromBagAndSlot(bag, slot)
                    local okValid, valid = pcall(C_AuctionHouse.IsSellItemValid, location, false)
                    if okValid and valid then
                        best = { location = location, price = sellPrice, id = info.itemID }
                    end
                end
            end
        end
    end
    if not best then return end
    local commodity = false
    if C_AuctionHouse.GetItemCommodityStatus then
        local ok, status = pcall(C_AuctionHouse.GetItemCommodityStatus, best.location)
        commodity = ok and Enum.ItemCommodityStatus and status == Enum.ItemCommodityStatus.Commodity
    end
    local changed
    for _, d in ipairs(vc.DURATIONS) do
        local ok, deposit
        if commodity and C_AuctionHouse.CalculateCommodityDeposit then
            ok, deposit = pcall(C_AuctionHouse.CalculateCommodityDeposit, best.id, d[1], 1)
        else
            ok, deposit = pcall(C_AuctionHouse.CalculateItemDeposit, best.location, d[1], 1)
        end
        if ok and type(deposit) == "number" and deposit >= 0 then
            local rate = deposit / best.price
            if db.rates[d[1]] ~= rate then
                db.rates[d[1]] = rate
                changed = true
            end
        end
    end
    if changed then vc.Refresh() end
end

-- ---------------------------------------------------------------------------
-- /mu v: check the item under the mouse, or explain

function vc.Explain(itemLink)
    if not itemLink then
        local _, link = GameTooltip:GetItem()
        itemLink = link
    end
    if not itemLink then
        root.Say("Point at an item in your bags and type /mu v again.")
        return
    end
    if not Auctionator_OK() then
        root.Say("Auctionator is not loaded.")
        return
    end
    local mark, vendor, ah, net, deposit = vc.Evaluate(itemLink)
    if mark == nil then
        root.Say(itemLink .. ": item data not loaded yet, try again.")
    elseif not vendor then
        root.Say(itemLink .. ": no vendor price or no AH price.")
    else
        local money = function(c) return GetMoneyString(math.max(0, math.floor(c + 0.5)), true) end
        root.Say(("%s: vendor %s, AH %s, after cut + effort%s %s -> |cff%s%s|r"):format(
            itemLink, money(vendor), money(ah),
            deposit > 0 and " + deposit" or "", money(net),
            mark and "ff3030" or root.ACCENT_HEX, mark and "vendor" or "AH"))
    end
end

-- ---------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self, event, addon)
    if event == "ADDON_LOADED" and addon == "MirogaUtilities" then
        if type(MirogaVendorDB) ~= "table" then MirogaVendorDB = {} end
        local db = MirogaVendorDB
        for key, value in pairs(vc.DEFAULTS) do
            if db[key] == nil then db[key] = type(value) == "table" and {} or value end
        end
        vc.db = db
    elseif event == "PLAYER_LOGIN" then
        RegisterBaganator()
        HookBlizzard()
        if Auctionator_OK() and Auctionator.API.v1.RegisterForDBUpdate then
            pcall(Auctionator.API.v1.RegisterForDBUpdate, CALLER, vc.Refresh)
        end
        self:RegisterEvent("AUCTION_HOUSE_SHOW")
        -- Baganator retries by itself when an item is not cached yet
        if not usingBaganator then self:RegisterEvent("GET_ITEM_INFO_RECEIVED") end
    elseif event == "AUCTION_HOUSE_SHOW" then
        C_Timer.After(1, MeasureDeposit)
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        -- vendor prices of uncached items arrive later; one refresh per burst
        if not self.pending and (not ContainerFrameUtil_IsAnyBagOpen or ContainerFrameUtil_IsAnyBagOpen()) then
            self.pending = true
            C_Timer.After(0.5, function()
                self.pending = false
                vc.Refresh()
            end)
        end
    end
end)
