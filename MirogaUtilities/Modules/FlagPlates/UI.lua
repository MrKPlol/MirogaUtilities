-------------------------------------------------------------------------------
--  KPFlagPlates - UI: in-game menu (/mu flag) to manage the list
-------------------------------------------------------------------------------
local _, root = ...
local ns = root.FlagPlates
if not ns then return end

local ROW_H, ROWS_W = 22, 300
local frame, input, filterBox, scroll, content, countText, swatch
local rows = {}

local function Button(parent, text, w, h)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, h or 22)
    b:SetText(text)
    return b
end

local function Check(parent, label, key, onChange)
    local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    c:SetSize(24, 24)
    local t = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t:SetPoint("LEFT", c, "RIGHT", 2, 0)
    t:SetText(label)
    c:SetScript("OnShow", function(self) self:SetChecked(ns.db[key]) end)
    c:SetScript("OnClick", function(self)
        ns.db[key] = self:GetChecked() and true or false
        if onChange then onChange() end
    end)
    return c
end

local function AddFromInput()
    local first, last = ns.ParseName(input:GetText())
    if not first then return end
    if ns.Add(first, last) then
        input:SetText("")
    else
        ns.Print("Already on the list.")
    end
    input:ClearFocus()
end

local function UpdateSwatch()
    local c = ns.db.color
    swatch.tex:SetColorTexture(c.r, c.g, c.b, 1)
end

local function SetColor(r, g, b)
    local c = ns.db.color
    c.r, c.g, c.b = r, g, b
    UpdateSwatch()
    ns.RepaintAll()
end

local function OpenColorPicker()
    local c = ns.db.color
    ColorPickerFrame:SetupColorPickerAndShow({
        r = c.r, g = c.g, b = c.b,
        hasOpacity = false,
        swatchFunc = function()
            SetColor(ColorPickerFrame:GetColorRGB())
        end,
        cancelFunc = function(prev)
            if prev then SetColor(prev.r, prev.g, prev.b) end
        end,
    })
end

local function GetRow(i)
    local row = rows[i]
    if row then return row end
    row = CreateFrame("Frame", nil, content)
    row:SetSize(ROWS_W, ROW_H)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.04 or 0)
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.text:SetPoint("LEFT", 6, 0)
    row.text:SetJustifyH("LEFT")
    row.del = Button(row, "X", 24, 18)
    row.del:SetPoint("RIGHT", -2, 0)
    row.stats = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.stats:SetPoint("RIGHT", row.del, "LEFT", -6, 0)
    row.stats:SetJustifyH("RIGHT")
    row.text:SetPoint("RIGHT", row.stats, "LEFT", -6, 0)
    row.text:SetWordWrap(false)
    row.del:SetScript("OnClick", function(self)
        local key = self:GetParent().key
        if key then ns.Remove(key) end
    end)
    row.del:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Remove")
        GameTooltip:Show()
    end)
    row.del:SetScript("OnLeave", GameTooltip_Hide)
    rows[i] = row
    return row
end

function ns.RefreshUI()
    if not frame or not frame:IsShown() then return end
    local keys = ns.SortedKeys(filterBox:GetText())
    for i, k in ipairs(keys) do
        local e = ns.db.entries[k]
        local row = GetRow(i)
        row.key = k
        if e.last then
            row.text:SetText(e.first .. " |cffaaaaaa" .. e.last .. "|r")
        else
            row.text:SetText(e.first .. " |cff777777(any surname)|r")
        end
        row.stats:SetText(ns.StatsText and ns.StatsText(e) or "")
        row:Show()
    end
    for i = #keys + 1, #rows do
        rows[i].key = nil
        rows[i]:Hide()
    end
    content:SetHeight(math.max(1, #keys * ROW_H))
    countText:SetText(("%d flagged"):format(ns.Count()))
end

local function Build()
    local ok, f = pcall(CreateFrame, "Frame", "KPFlagPlatesFrame", UIParent, "BasicFrameTemplateWithInset")
    if not ok then
        f = CreateFrame("Frame", "KPFlagPlatesFrame", UIParent, "BackdropTemplate")
        f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
            insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        f:SetBackdropColor(0, 0, 0, 0.9)
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", 0, 0)
    end
    frame = f
    f:SetSize(350, 470)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    tinsert(UISpecialFrames, "KPFlagPlatesFrame")   -- ESC closes

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", 0, -6)
    title:SetText("|cff40e0d0KP FlagPlates|r")

    -- Add row
    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("TOPLEFT", 16, -34)
    hint:SetText("Name, or Name + Surname:")

    input = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    input:SetSize(200, 22)
    input:SetPoint("TOPLEFT", 22, -50)
    input:SetAutoFocus(false)
    input:SetMaxLetters(48)
    input:SetScript("OnEnterPressed", AddFromInput)
    input:SetScript("OnEscapePressed", input.ClearFocus)

    local add = Button(f, "Add", 90)
    add:SetPoint("LEFT", input, "RIGHT", 8, 0)
    add:SetScript("OnClick", AddFromInput)

    local addT = Button(f, "Add / Remove Target", 200)
    addT:SetPoint("TOPLEFT", input, "BOTTOMLEFT", -6, -6)
    addT:SetScript("OnClick", function() ns.ToggleTarget() end)

    -- Filter
    local fl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fl:SetPoint("TOPLEFT", 16, -112)
    fl:SetText("Search:")
    filterBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    filterBox:SetSize(150, 20)
    filterBox:SetPoint("LEFT", fl, "RIGHT", 10, 0)
    filterBox:SetAutoFocus(false)
    filterBox:SetScript("OnTextChanged", function() ns.RefreshUI() end)
    filterBox:SetScript("OnEscapePressed", filterBox.ClearFocus)

    countText = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    countText:SetPoint("TOPRIGHT", -18, -114)

    -- List
    scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 14, -134)
    scroll:SetPoint("BOTTOMRIGHT", -32, 112)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(ROWS_W, 1)
    scroll:SetScrollChild(content)
    local listBg = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    listBg:SetPoint("TOPLEFT", scroll, -2, 2)
    listBg:SetPoint("BOTTOMRIGHT", scroll, 24, -2)
    listBg:SetColorTexture(0, 0, 0, 0.35)

    -- Options
    local cBar = Check(f, "Colour health bar", "colorBar", ns.RepaintAll)
    cBar:SetPoint("BOTTOMLEFT", 14, 78)
    local cName = Check(f, "Colour name", "colorName", ns.RepaintAll)
    cName:SetPoint("LEFT", cBar, "RIGHT", 130, 0)
    local cAlert = Check(f, "Chat alert when a flagged player appears", "alert")
    cAlert:SetPoint("BOTTOMLEFT", 14, 54)

    swatch = CreateFrame("Button", nil, f)
    swatch:SetSize(20, 20)
    swatch:SetPoint("BOTTOMLEFT", 20, 24)
    local border = swatch:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints()
    border:SetColorTexture(1, 1, 1, 0.8)
    swatch.tex = swatch:CreateTexture(nil, "ARTWORK")
    swatch.tex:SetPoint("TOPLEFT", 2, -2)
    swatch.tex:SetPoint("BOTTOMRIGHT", -2, 2)
    swatch:SetScript("OnClick", OpenColorPicker)
    local sl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sl:SetPoint("LEFT", swatch, "RIGHT", 6, 0)
    sl:SetText("Colour")

    local reset = Button(f, "Turquoise", 80, 20)
    reset:SetPoint("LEFT", sl, "RIGHT", 8, 0)
    reset:SetScript("OnClick", function()
        local d = ns.DEFAULTS.color
        SetColor(d.r, d.g, d.b)
    end)

    local clear = Button(f, "Clear all", 80, 20)
    clear:SetPoint("BOTTOMRIGHT", -16, 24)
    clear:SetScript("OnClick", function() StaticPopup_Show("KPFLAGPLATES_CLEAR") end)

    local help = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    help:SetPoint("BOTTOM", 0, 8)
    help:SetText("/mu t = flag / unflag target   |   right-click player: Flag")

    f:SetScript("OnShow", function()
        UpdateSwatch()
        ns.RefreshUI()
    end)
    f:Hide()
end

StaticPopupDialogs["KPFLAGPLATES_CLEAR"] = {
    text = "Remove ALL flagged names?",
    button1 = YES,
    button2 = NO,
    OnAccept = function() ns.ClearAll() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

function ns.ToggleUI()
    if not frame then Build() end
    if frame:IsShown() then frame:Hide() else frame:Show() end
end
