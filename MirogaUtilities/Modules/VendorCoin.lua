-- Vendor coin: a red coin in the top right corner of every bag item that
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
-- maintenance on Nov 18, then 1 copper). That fixed cost per auction is the
-- only part that depends on the amount, so every item gets one verdict that
-- never flips because a stack grows or shrinks:
--   red coin    vendor wins even for a full stack: sell, whatever you have
--   amber coin  amount decides: vendor wins for one unit, AH for a full
--               stack. The tooltip says from how many on the AH pays more
--               and what that means for what you carry (all bags together)
--   no coin     AH wins already for a single unit
-- Not stackable = full stack of 1, so those are only red or nothing.
--
-- Items on the Stockpile hold list get a green hourglass (top left) instead.
-- Both marks also show in Auctionator's selling tab.
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
    bound = false, rates = {}, minDeposit = 100, amber = true, tooltip = true,
    coinCorner = "TOPRIGHT", holdCorner = "TOPLEFT",
}

-- the four corners: frame point, offset, Baganator's corner name
vc.CORNERS = {
    { "TOPLEFT", "Top left", 2, -2, "top_left", "tl" },
    { "TOPRIGHT", "Top right", -2, -2, "top_right", "tr" },
    { "BOTTOMLEFT", "Bottom left", 2, 2, "bottom_left", "bl" },
    { "BOTTOMRIGHT", "Bottom right", -2, 2, "bottom_right", "br" },
}
local CORNER = {}
for _, c in ipairs(vc.CORNERS) do CORNER[c[1]] = c end

local function CornerOf(key)
    local db = vc.db or vc.DEFAULTS
    return CORNER[db[key]] and db[key] or vc.DEFAULTS[key]
end

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

-- how many of the item are in the bags, all stacks together
local function BagCount(itemLink)
    local f = C_Item and C_Item.GetItemCount or GetItemCount
    if not f then return 0 end
    local ok, n = pcall(f, itemLink, false)
    return ok and tonumber(n) or 0
end
vc.BagCount = BagCount

-- per unit, in copper, after cut + effort + deposit, for an auction of q
local function NetFor(a, q)
    return a.base - math.max(a.rateDeposit, a.minDeposit / math.max(1, q))
end

-- the whole picture of an item, or nil while its data is not loaded yet,
-- or false when there is nothing to compare (no vendor or no AH price).
-- have: amount to show the numbers for (default: what the bags hold)
-- a.verdict: "vendor" (red), "amount" (amber) or false (AH wins)
function vc.Analyze(itemLink, have)
    if type(itemLink) ~= "string" or not Auctionator_OK() then return nil end
    local stackSize = select(8, GetItemInfo(itemLink))
    local sellPrice = select(11, GetItemInfo(itemLink))
    if sellPrice == nil then return nil end
    if sellPrice <= 0 then return false end
    local ok, ah = pcall(Auctionator.API.v1.GetAuctionPriceByItemLink, CALLER, itemLink)
    if not ok or not ah or ah <= 0 then return false end
    local db = vc.db or vc.DEFAULTS
    local a = {
        vendor = sellPrice, ah = ah,
        lot = math.max(1, tonumber(stackSize) or 1),
        base = ah * (1 - (db.cut + (db.effort or 0)) / 100),
        rateDeposit = db.deposit and sellPrice * vc.Rate() or 0,
        minDeposit = db.deposit and (db.minDeposit or 0) or 0,
    }
    a.netFull, a.netOne = NetFor(a, a.lot), NetFor(a, 1)
    if sellPrice >= a.netFull then
        a.verdict = "vendor"
    elseif sellPrice >= a.netOne then
        a.verdict = "amount"
        -- smallest auction where the fixed cost is small enough
        local q = math.floor(a.minDeposit / (a.base - sellPrice)) + 1
        while q > 1 and sellPrice < NetFor(a, q - 1) do q = q - 1 end
        while sellPrice >= NetFor(a, q) do q = q + 1 end
        a.breakEven = q
    else
        a.verdict = false
    end
    a.have = math.max(1, have or BagCount(itemLink))
    -- one auction holds at most a full stack; more is several full ones
    a.netHave = NetFor(a, math.min(a.have, a.lot))
    a.vendorWinsHave = sellPrice >= a.netHave
    return a
end

-- old shape: verdict for a full stack, vendor, ah, net, deposit, lot
function vc.Evaluate(itemLink)
    local a = vc.Analyze(itemLink, 1)
    if not a then return a end
    return a.verdict == "vendor", a.vendor, a.ah, a.netFull, a.base - a.netFull, a.lot
end

-- a bag slot: "hold" (green hourglass), "vendor" (red coin), "amount"
-- (amber coin), false, or nil when the item data is not loaded yet.
-- Only the item counts, never the slot: all its stacks look the same.
local function Mark(itemLink, isBound)
    local sp = root.Stockpile
    if sp and sp.IsHeld(itemLink) then return "hold" end
    local db = vc.db
    if not db or not db.enabled then return false end
    if isBound and not db.bound then return false end
    local a = vc.Analyze(itemLink, 1)
    if a == nil then return nil end
    if not a then return false end
    if a.verdict == "amount" and not db.amber then return false end
    return a.verdict
end
vc.Mark = Mark

-- ---------------------------------------------------------------------------
-- words for the tooltip

local function Money(c) return GetMoneyString(math.max(0, math.floor(c + 0.5)), true) end

function vc.Summary(a)
    if a.verdict == "vendor" then
        return "|cffff3030vendor|r - beats the AH even for a full stack"
    elseif a.verdict == "amount" then
        return ("|cffff9e14amount decides|r - AH pays more from %d on"):format(a.breakEven)
    end
    return "|cff40ff60AH|r - beats the vendor even for a single one"
end

function vc.Details(a)
    local lines = {}
    lines[#lines + 1] = ("each: vendor %s, AH %s, after fees %s (1) / %s (stack of %d)"):format(
        Money(a.vendor), Money(a.ah), Money(a.netOne), Money(a.netFull), a.lot)
    if a.verdict == "amount" then
        local n = math.min(a.have, a.lot)
        lines[#lines + 1] = ("you have %d: %s each at the AH -> %s"):format(a.have, Money(a.netHave),
            a.vendorWinsHave and ("|cffff9e14vendor now, or collect %d more|r"):format(a.breakEven - n)
            or "|cff40ff60AH|r")
    end
    return lines
end

-- tooltip: one line, two for amber below the break-even.
--   left = what to do with what you carry, right = per unit vendor vs AH
local GRAY, RED, AMBER, GREEN = "|cffaaaaaa", "|cffff3030", "|cffff9e14", "|cff40ff60"

local function Coin(c)
    c = math.floor((c or 0) + 0.5)
    if c <= 0 then return "0" end
    return GetMoneyString(c, true)
end

local function AddTooltip(tooltip)
    local db = vc.db
    if not db or not db.enabled or not db.tooltip or not tooltip or not tooltip.GetItem then return end
    local ok, _, link = pcall(tooltip.GetItem, tooltip)
    if not ok or not link then return end
    local mark = Mark(link, false)
    if mark ~= "vendor" and mark ~= "amount" then return end
    local a = vc.Analyze(link)
    if not a then return end
    local vendorFirst = GRAY .. "Vendor|r " .. Coin(a.vendor) .. GRAY .. "  AH|r " .. Coin(a.netHave)
    if a.verdict == "vendor" then
        -- red holds even for a full stack, so show that best case
        tooltip:AddDoubleLine("Miroga: " .. RED .. "sell to vendor|r",
            GRAY .. "Vendor|r " .. Coin(a.vendor) .. GRAY .. "  AH|r " .. Coin(a.netFull))
    elseif a.vendorWinsHave then
        tooltip:AddDoubleLine("Miroga: " .. AMBER .. "vendor for now|r", vendorFirst)
        tooltip:AddLine(("%sAH pays more from %d on (you have %d) -> %s each|r"):format(
            GRAY, a.breakEven, a.have, Coin(a.netFull)))
    else
        tooltip:AddDoubleLine("Miroga: " .. GREEN .. "AH|r" .. GRAY .. " (from " .. a.breakEven .. ")|r",
            GRAY .. "AH|r " .. Coin(a.netHave) .. GRAY .. "  Vendor|r " .. Coin(a.vendor))
    end
    tooltip:Show()
end

local function HookTooltip()
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip)
            if tooltip == GameTooltip then AddTooltip(tooltip) end
        end)
    elseif GameTooltip.HookScript then
        GameTooltip:HookScript("OnTooltipSetItem", AddTooltip)
    end
end

-- ---------------------------------------------------------------------------
-- the coin

local COIN_COLORS = { vendor = { 1, 0.12, 0.12 }, amount = { 1, 0.62, 0.08 } }

local function MakeCoin(parent)
    local coin = parent:CreateTexture(nil, "OVERLAY", nil, 7)
    coin:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
    coin:SetDesaturated(true)
    coin:SetVertexColor(unpack(COIN_COLORS.vendor))
    coin:SetSize(14, 14)
    return coin
end

local function ColorCoin(coin, mark)
    local c = COIN_COLORS[mark]
    if coin and c then coin:SetVertexColor(c[1], c[2], c[3]) end
end

-- hourglass for held items: the small UI glyph first, then the hourglass
-- icon, then the old pocket watch, whichever the client has
local HOURGLASSES = {
    { "Interface\\Common\\mini-hourglass", false },
    { "Interface\\Icons\\INV_Relics_Hourglass", true },
    { "Interface\\Icons\\INV_Misc_PocketWatch_01", true },
}

local function MakeWatch(parent)
    local glass = parent:CreateTexture(nil, "OVERLAY", nil, 7)
    for _, choice in ipairs(HOURGLASSES) do
        if glass:SetTexture(choice[1]) ~= false then
            if choice[2] then
                glass:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                glass:SetVertexColor(0.55, 1, 0.55)
            else
                glass:SetVertexColor(0.3, 1, 0.3)
            end
            break
        end
    end
    glass:SetSize(14, 14)
    return glass
end

-- ---------------------------------------------------------------------------
-- Baganator

-- Baganator puts a widget in its corner only the first time it sees the ID
-- and has no API to move it. So each mark is registered four times, one ID
-- per corner (miroga_vendor_coin_tr, ..._tl, ...), and only the one in the
-- corner chosen in the hub shows. IDs from older versions are skipped by
-- Baganator because nobody registers them any more.
local usingBaganator = false

local function RegisterBaganator()
    if usingBaganator or not (Baganator and Baganator.API and Baganator.API.RegisterCornerWidget) then
        return
    end
    usingBaganator = true
    -- want: the marks this widget shows (the coin shows red and amber)
    local function Widget(label, id, want, make, corner, key)
        Baganator.API.RegisterCornerWidget(label, id,
            function(frame, details)
                if CornerOf(key) ~= corner[1] then return false end
                if not details or not details.itemLink then return false end
                local mark = Mark(details.itemLink, details.isBound)
                if mark == nil then return nil end
                if not want[mark] then return false end
                ColorCoin(frame and frame.coin, mark)
                return true
            end,
            function(itemButton)
                local frame = CreateFrame("Frame", nil, itemButton)
                frame:SetSize(14, 14)
                frame.padding = 0
                local tex = make(frame)
                tex:SetAllPoints()
                if make == MakeCoin then frame.coin = tex end
                return frame
            end,
            { corner = corner[5], priority = 1 })
    end
    for _, c in ipairs(vc.CORNERS) do
        Widget("Miroga: vendor coin (" .. strlower(c[2]) .. ")", "miroga_vendor_coin_" .. c[6],
            { vendor = true, amount = true }, MakeCoin, c, "coinCorner")
        Widget("Miroga: hold hourglass (" .. strlower(c[2]) .. ")", "miroga_hold_watch_" .. c[6],
            { hold = true }, MakeWatch, c, "holdCorner")
    end
end

-- ---------------------------------------------------------------------------
-- Blizzard bags (only when Baganator is not there)

local hooked = {}

-- shows the right mark on a plain button, in the chosen corner
local function Place(button, mark)
    local isCoin = mark == "vendor" or mark == "amount"
    if isCoin and not button.MirogaVendorCoin then button.MirogaVendorCoin = MakeCoin(button) end
    if mark == "hold" and not button.MirogaHoldWatch then button.MirogaHoldWatch = MakeWatch(button) end
    local coin, glass = button.MirogaVendorCoin, button.MirogaHoldWatch
    if coin then
        local c = CORNER[CornerOf("coinCorner")]
        coin:ClearAllPoints()
        coin:SetPoint(c[1], c[3], c[4])
        ColorCoin(coin, mark)
        coin:SetShown(isCoin)
    end
    if glass then
        local c = CORNER[CornerOf("holdCorner")]
        glass:ClearAllPoints()
        glass:SetPoint(c[1], c[3], c[4])
        glass:SetShown(mark == "hold")
    end
end

local function UpdateButton(button)
    if not button or not button.GetBagID then return end
    local mark = false
    local bag, slot = button:GetBagID(), button:GetID()
    if bag and slot and C_Container then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info and info.hyperlink then
            mark = Mark(info.hyperlink, info.isBound) or false
        end
    end
    Place(button, mark)
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
-- buttons. Same corners as in the bags.

local sellButtons = setmetatable({}, { __mode = "k" })

local function UpdateSellButton(button)
    local info = button.itemInfo
    local mark = false
    if info and info.itemLink then
        mark = Mark(info.itemLink, false) or false
    end
    Place(button, mark)
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

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self, event, addon)
    if event == "ADDON_LOADED" and addon == "MirogaUtilities" then
        if root.Off("VendorCoin", self) then return end
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
        HookTooltip()
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
