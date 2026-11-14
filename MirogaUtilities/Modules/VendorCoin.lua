-- Vendor coin: a red coin in the bottom right corner of every bag item that
-- brings more at the vendor than on the auction house.
--
-- AH side, per unit:  Auctionator price  - cut (5 %)  - effort (3 %)  - deposit
-- Effort is your own work for listing and relisting, on top of the cut.
-- The deposit only stays with the AH if the auction does not sell, so it is a
-- switch: on = count one failed listing (careful), off = the item sells.
-- Forever works the deposit out on the server. While the AH is open the
-- module asks it once per listing time and keeps the rate (deposit divided
-- by vendor price); until then it guesses the Classic rates 5/20/60 %.
-- Every auction costs at least the minimum deposit (1 silver until the
-- maintenance on Nov 18, then 1 copper), spread over the stack you list.
--
-- Items on the Stockpile hold list get a green watch instead of the coin.
-- Both marks also show in Auctionator's selling tab (top right there).
--
-- Bags: Baganator corner widget ("Miroga: vendor beats AH"). Without
-- Baganator the plain Blizzard bags get the coin directly.
local _, root = ...
local vc = {}
root.VendorCoin = vc

local CALLER = "MirogaUtilities"
local GUESS_RATES = { 0.05, 0.20, 0.60 }
vc.DURATIONS = { { 1, "2 hours" }, { 2, "8 hours" }, { 3, "24 hours" } }
vc.DEFAULTS = {
    enabled = true, cut = 5, effort = 3, deposit = true, duration = 3,
    bound = false, rates = {}, minDeposit = 100,
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
    return GUESS_RATES[db.duration] or 0.6, false
end

-- all numbers per unit, in copper. nil = not decidable (no data yet)
-- count = stack size you would list; the minimum deposit is per auction
function vc.Evaluate(itemLink, count)
    if type(itemLink) ~= "string" or not Auctionator_OK() then return nil end
    local sellPrice = select(11, GetItemInfo(itemLink))
    if sellPrice == nil then return nil end
    if sellPrice <= 0 then return false end
    local ok, ah = pcall(Auctionator.API.v1.GetAuctionPriceByItemLink, CALLER, itemLink)
    if not ok or not ah or ah <= 0 then return false end
    local db = vc.db or vc.DEFAULTS
    local net = ah * (1 - (db.cut + (db.effort or 0)) / 100)
    local deposit = 0
    if db.deposit then
        deposit = math.max(sellPrice * vc.Rate(), (db.minDeposit or 0) / math.max(1, count or 1))
    end
    net = net - deposit
    return sellPrice > net, sellPrice, ah, net, deposit
end

-- a bag slot: "hold" (green watch), "vendor" (red coin), false, or nil
-- when the item data is not loaded yet
local function Mark(itemLink, isBound, count)
    local sp = root.Stockpile
    if sp and sp.IsHeld(itemLink) then return "hold" end
    local db = vc.db
    if not db or not db.enabled then return false end
    if isBound and not db.bound then return false end
    local result = vc.Evaluate(itemLink, count)
    if result == nil then return nil end
    return result and "vendor" or false
end
vc.Mark = Mark

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

local function MakeWatch(parent)
    local watch = parent:CreateTexture(nil, "OVERLAY", nil, 7)
    watch:SetTexture("Interface\\Icons\\INV_Misc_PocketWatch_01")
    watch:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    watch:SetVertexColor(0.55, 1, 0.55)
    watch:SetSize(14, 14)
    return watch
end

-- ---------------------------------------------------------------------------
-- Baganator

local WIDGET_ID = "miroga_vendor_coin"
local HOLD_ID = "miroga_hold_watch"
local usingBaganator = false

local function RegisterBaganator()
    if usingBaganator or not (Baganator and Baganator.API and Baganator.API.RegisterCornerWidget) then
        return
    end
    usingBaganator = true
    local function Widget(label, id, want, make)
        Baganator.API.RegisterCornerWidget(label, id,
            function(_, details)
                if not details or not details.itemLink then return false end
                local mark = Mark(details.itemLink, details.isBound, details.itemCount)
                if mark == nil then return nil end
                return mark == want
            end,
            function(itemButton)
                local frame = CreateFrame("Frame", nil, itemButton)
                frame:SetSize(14, 14)
                frame.padding = 0
                make(frame):SetAllPoints()
                return frame
            end,
            { corner = "bottom_right", priority = 1 })
    end
    Widget("Miroga: vendor beats AH", WIDGET_ID, "vendor", MakeCoin)
    Widget("Miroga: hold for later", HOLD_ID, "hold", MakeWatch)
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
            mark = Mark(info.hyperlink, info.isBound, info.stackCount) or false
        end
    end
    if mark == "vendor" and not button.MirogaVendorCoin then
        button.MirogaVendorCoin = MakeCoin(button)
        button.MirogaVendorCoin:SetPoint("BOTTOMRIGHT", -2, 2)
    end
    if mark == "hold" and not button.MirogaHoldWatch then
        button.MirogaHoldWatch = MakeWatch(button)
        button.MirogaHoldWatch:SetPoint("BOTTOMRIGHT", -2, 2)
    end
    if button.MirogaVendorCoin then button.MirogaVendorCoin:SetShown(mark == "vendor") end
    if button.MirogaHoldWatch then button.MirogaHoldWatch:SetShown(mark == "hold") end
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
-- Auctionator's selling tab: its bag view uses AuctionatorGroupsViewItem
-- buttons. The stack count sits bottom right there, so the marks go top right.

local sellButtons = setmetatable({}, { __mode = "k" })

local function UpdateSellButton(button)
    local info = button.itemInfo
    local mark = false
    if info and info.itemLink then
        mark = Mark(info.itemLink, false, info.itemCount) or false
    end
    if mark == "vendor" and not button.MirogaVendorCoin then
        button.MirogaVendorCoin = MakeCoin(button)
        button.MirogaVendorCoin:SetPoint("TOPRIGHT", -2, -2)
    end
    if mark == "hold" and not button.MirogaHoldWatch then
        button.MirogaHoldWatch = MakeWatch(button)
        button.MirogaHoldWatch:SetPoint("TOPRIGHT", -2, -2)
    end
    if button.MirogaVendorCoin then button.MirogaVendorCoin:SetShown(mark == "vendor") end
    if button.MirogaHoldWatch then button.MirogaHoldWatch:SetShown(mark == "hold") end
end

local auctionatorHooked = false
local function HookAuctionator()
    if auctionatorHooked or not AuctionatorGroupsViewItemMixin then return end
    auctionatorHooked = true
    -- buttons get the mixin's functions when they are made (first AH visit),
    -- so hooking the mixin at login reaches all of them
    hooksecurefunc(AuctionatorGroupsViewItemMixin, "SetItemInfo", function(button)
        sellButtons[button] = true
        UpdateSellButton(button)
    end)
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
    for button in pairs(sellButtons) do
        if button:IsVisible() then UpdateSellButton(button) end
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
    local best, cheapest
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.hyperlink and not info.isBound then
                local sellPrice = select(11, GetItemInfo(info.hyperlink))
                -- the bigger the vendor price, the less rounding in the rate
                local wantBest = sellPrice and sellPrice >= 100 and (not best or sellPrice > best.price)
                local wantCheap = sellPrice and sellPrice > 0 and (not cheapest or sellPrice < cheapest.price)
                if wantBest or wantCheap then
                    local location = ItemLocation:CreateFromBagAndSlot(bag, slot)
                    local okValid, valid = pcall(C_AuctionHouse.IsSellItemValid, location, false)
                    if okValid and valid then
                        local entry = { location = location, price = sellPrice, id = info.itemID }
                        if wantBest then best = entry end
                        if wantCheap then cheapest = entry end
                    end
                end
            end
        end
    end
    local function Deposit(entry, duration)
        local commodity = false
        if C_AuctionHouse.GetItemCommodityStatus then
            local ok, status = pcall(C_AuctionHouse.GetItemCommodityStatus, entry.location)
            commodity = ok and Enum.ItemCommodityStatus and status == Enum.ItemCommodityStatus.Commodity
        end
        local ok, deposit
        if commodity and C_AuctionHouse.CalculateCommodityDeposit then
            ok, deposit = pcall(C_AuctionHouse.CalculateCommodityDeposit, entry.id, duration, 1)
        else
            ok, deposit = pcall(C_AuctionHouse.CalculateItemDeposit, entry.location, duration, 1)
        end
        if ok and type(deposit) == "number" and deposit >= 0 then return deposit end
    end
    local changed
    if best then
        for _, d in ipairs(vc.DURATIONS) do
            local deposit = Deposit(best, d[1])
            -- at the floor the deposit says nothing about the rate
            if deposit and deposit > (db.minDeposit or 0) then
                local rate = deposit / best.price
                if db.rates[d[1]] ~= rate then
                    db.rates[d[1]] = rate
                    changed = true
                end
            end
        end
    end
    -- the cheapest item at the shortest time shows the minimum: if the game
    -- asks more than the rate gives, that is the floor; if it asks less than
    -- the floor we knew, the floor went down (1 silver -> 1 copper)
    if cheapest then
        local rate = db.rates[1] or GUESS_RATES[1]
        local deposit = Deposit(cheapest, 1)
        if deposit and deposit > 0 then
            local formula = cheapest.price * rate
            local floor = db.minDeposit
            if deposit > formula + 1 then
                floor = deposit
            elseif deposit < floor then
                floor = deposit
            end
            if floor ~= db.minDeposit then
                db.minDeposit = floor
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
    local sp = root.Stockpile
    if sp and sp.IsHeld(itemLink) then
        root.Say(itemLink .. ": |cff40ff60held|r for later (Stockpile), no vendor coin.")
    end
    local mark, vendor, ah, net, deposit = vc.Evaluate(itemLink)
    local age = sp and sp.ItemAge(sp.ItemID(itemLink))
    if age and age >= 1 then
        root.Say(("|cffff9933The AH price is %d %s old.|r"):format(age, age == 1 and "day" or "days"))
    end
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
        HookAuctionator()
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
