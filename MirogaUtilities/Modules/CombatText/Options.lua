-- Options.lua — settings panel (Esc > Options > AddOns > KPCombatText).
--
-- Every control writes KPCombatTextDB.options through ns.Options() and then
-- calls ns.ApplySettings(); the core reads nothing from these widgets, and no
-- widget here ever displays combat payloads.

local addonName, root = ...
local ns = root.CombatText
if not ns then return end
if not (Settings and Settings.RegisterCanvasLayoutCategory) then return end

local TITLE = "Miroga Combat Text"
local ROW = 34
local LEFT = 16
local CONTROL_X = 230

local BUILTIN_FONTS = {
    { name = "Friz Quadrata (game default)", path = "Fonts\\FRIZQT__.TTF" },
    { name = "Arial Narrow", path = "Fonts\\ARIALN.TTF" },
    { name = "Skurri", path = "Fonts\\skurri.ttf" },
    { name = "Morpheus", path = "Fonts\\MORPHEUS.ttf" },
}
local OUTLINE_CHOICES = {
    { value = "default", text = "Game default" },
    { value = "NONE", text = "None" },
    { value = "OUTLINE", text = "Outline" },
    { value = "THICKOUTLINE", text = "Thick outline" },
}
local DIRECTION_CHOICES = { "up", "down", "left", "right" }
local STREAM_LABELS = { incoming = "Damage taken (left box)", gains = "Heals and gains (right box)" }

local function changed()
    ns.ApplySettings()
end

-- ---------------------------------------------------------------------------
-- widget helpers; each returns a refresh function the page calls on show

local function newPage(name)
    local page = CreateFrame("Frame")
    page.refreshers = {}
    page.name = name
    page:SetScript("OnShow", function(self)
        for _, refresh in ipairs(self.refreshers) do refresh() end
    end)
    local title = page:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", LEFT, -16)
    title:SetText(name)
    return page
end

local function header(page, text, x, y)
    local fs = page:CreateFontString(nil, "ARTWORK", "GameFontHighlightMedium")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(text)
    local line = page:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.15)
    line:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -4)
    line:SetSize(x == LEFT and 600 or 280, 1)
end

local function label(page, text, y)
    local fs = page:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    fs:SetPoint("TOPLEFT", LEFT + 8, y - 6)
    fs:SetText(text)
    return fs
end

local function checkbox(page, text, x, y, get, set)
    local cb = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", x, y)
    cb.Text:SetFontObject("GameFontHighlight")
    cb.Text:SetText(text)
    cb:SetScript("OnClick", function(self)
        set(self:GetChecked() and true or false)
        changed()
    end)
    table.insert(page.refreshers, function() cb:SetChecked(get()) end)
    return cb
end

local function slider(page, text, y, key, step, format)
    label(page, text, y)
    local limit = ns.LIMITS[key]
    local s = CreateFrame("Frame", nil, page, "MinimalSliderWithSteppersTemplate")
    s:SetPoint("TOPLEFT", CONTROL_X, y + 4)
    s:SetWidth(260)
    local formatters = {
        [MinimalSliderWithSteppersMixin.Label.Right] = CreateMinimalSliderFormatter(MinimalSliderWithSteppersMixin.Label.Right, format),
    }
    local steps = math.floor((limit[2] - limit[1]) / step + 0.5)
    local refreshing = false
    s:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
        if refreshing then return end
        ns.Options()[key] = math.floor(value / step + 0.5) * step
        changed()
    end, s)
    table.insert(page.refreshers, function()
        refreshing = true
        s:Init(ns.Options()[key], limit[1], limit[2], steps, formatters)
        refreshing = false
    end)
end

-- choices: list of { value, text }; get/set work on the value
local function dropdown(page, text, y, choices, get, set, width, x)
    if text then label(page, text, y) end
    local dd = CreateFrame("DropdownButton", nil, page, "WowStyle1DropdownTemplate")
    dd:SetPoint("TOPLEFT", x or CONTROL_X, y)
    dd:SetWidth(width or 260)
    dd:SetupMenu(function(_, root)
        root:SetScrollMode(360)
        for _, choice in ipairs(type(choices) == "function" and choices() or choices) do
            root:CreateRadio(choice.text, function() return get() == choice.value end, function()
                set(choice.value)
                changed()
            end)
        end
    end)
    table.insert(page.refreshers, function() dd:GenerateMenu() end)
    return dd
end

local function button(page, text, x, y, width, onClick)
    local b = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    b:SetPoint("TOPLEFT", x, y)
    b:SetSize(width, 24)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

local function colorSwatch(page, slot, x, y)
    local b = CreateFrame("Button", nil, page)
    b:SetPoint("TOPLEFT", x, y)
    b:SetSize(20, 20)
    local border = b:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints()
    border:SetColorTexture(0.5, 0.5, 0.5, 1)
    local fill = b:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", 2, -2)
    fill:SetPoint("BOTTOMRIGHT", -2, 2)
    local text = page:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetPoint("LEFT", b, "RIGHT", 8, 0)
    text:SetText(slot.label)

    local function refresh()
        local c = ns.Color(ns.Options(), slot.key)
        fill:SetColorTexture(c[1], c[2], c[3], 1)
        text:SetTextColor(c[1], c[2], c[3])
    end
    local function store(r, g, b2)
        ns.Options().colors[slot.key] = { r, g, b2 }
        changed()
        refresh()
    end
    b:SetScript("OnClick", function()
        local c = ns.Color(ns.Options(), slot.key)
        ColorPickerFrame:SetupColorPickerAndShow({
            r = c[1], g = c[2], b = c[3],
            swatchFunc = function() store(ColorPickerFrame:GetColorRGB()) end,
            cancelFunc = function(previous) store(previous.r, previous.g, previous.b) end,
        })
    end)
    table.insert(page.refreshers, refresh)
end

-- ---------------------------------------------------------------------------
-- page 1: look and placement

local function fontChoices()
    local list, seen = {}, {}
    for _, font in ipairs(BUILTIN_FONTS) do
        list[#list + 1] = { value = font.path, text = font.name }
        seen[font.path:lower()] = true
    end
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM then
        for _, name in ipairs(LSM:List("font")) do
            local path = LSM:Fetch("font", name, true)
            if type(path) == "string" and not seen[path:lower()] then
                list[#list + 1] = { value = path, text = name }
                seen[path:lower()] = true
            end
        end
    end
    table.insert(list, 1, { value = false, text = "Addon default" })
    return list
end

local general = newPage(TITLE)
local y = -52
header(general, "Text", LEFT, y)
y = y - 30
dropdown(general, "Font", y, fontChoices,
    function() return ns.Options().font end, function(v) ns.Options().font = v end)
y = y - ROW
dropdown(general, "Outline", y, OUTLINE_CHOICES,
    function() return ns.Options().outline end, function(v) ns.Options().outline = v end)
y = y - ROW
slider(general, "Text size", y, "scale", 0.05, function(v) return string.format("%d%%", v * 100 + 0.5) end)
y = y - ROW
slider(general, "Display time", y, "lifetime", 0.1, function(v) return string.format("%.1f s", v) end)
y = y - ROW
slider(general, "Scroll distance", y, "distance", 10, function(v) return string.format("%d px", v) end)
y = y - ROW
slider(general, "Merge repeats within", y, "window", 0.05, function(v)
    return v < 0.01 and "off" or string.format("%.2f s", v)
end)
y = y - ROW
checkbox(general, "Crits pop larger for a moment", LEFT + 4, y,
    function() return ns.Options().critPop end, function(v) ns.Options().critPop = v end)
y = y - ROW
checkbox(general, "Color damage taken by spell school", LEFT + 4, y,
    function() return ns.Options().schoolColors end, function(v) ns.Options().schoolColors = v end)
checkbox(general, "Icons (school, heal, buff/debuff)", LEFT + 4 + 310, y,
    function() return ns.Options().schoolIcons end, function(v) ns.Options().schoolIcons = v end)

y = y - 44
header(general, "Scroll areas", LEFT, y)
y = y - 30
for _, name in ipairs({ "incoming", "gains" }) do
    checkbox(general, STREAM_LABELS[name], LEFT + 4, y,
        function() return not ns.Options().streamOff[name] end,
        function(v) ns.Options().streamOff[name] = not v or nil end)
    local directions = {}
    for _, d in ipairs(DIRECTION_CHOICES) do directions[#directions + 1] = { value = d, text = "Scroll " .. d } end
    dropdown(general, nil, y, directions,
        function() return ns.streams[name].direction end,
        function(v) ns.SetDirection(name, v) end, 160, CONTROL_X + 100)
    y = y - ROW
end
local unlock
unlock = button(general, "Move boxes", LEFT + 8, y, 130, function()
    local shown = ns.SetAnchorsShown(nil)
    unlock:SetText(shown and "Lock boxes" or "Move boxes")
end)
general:HookScript("OnHide", function()
    -- leaving the panel locks the boxes so they never stay draggable by accident
    ns.SetAnchorsShown(nil, false)
    unlock:SetText("Move boxes")
end)
button(general, "Preview", LEFT + 146, y, 110, function() ns.Preview() end)
button(general, "Reset positions", LEFT + 264, y, 140, function()
    ns.ResetPositions()
    for _, refresh in ipairs(general.refreshers) do refresh() end
end)

y = y - 44
header(general, "Blizzard combat text", LEFT, y)
y = y - 30
checkbox(general, "Show Blizzard's own text for incoming damage too (doubles numbers)", LEFT + 4, y,
    function() return ns.Options().blizzSelf end,
    function(v) if v ~= ns.Options().blizzSelf then ns.ToggleBlizzard() end end)
local note = general:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
note:SetPoint("TOPLEFT", LEFT + 8, y - 30)
note:SetWidth(580)
note:SetJustifyH("LEFT")
note:SetText("Damage you deal is not affected: it stays with Blizzard's own floating combat text.")

general.OnDefault = function()
    -- keeps box positions; those have their own reset button
    KPCombatTextDB.options = nil
    ns.ApplySettings()
end
general.OnRefresh = function(self)
    for _, refresh in ipairs(self.refreshers) do refresh() end
end

-- ---------------------------------------------------------------------------
-- page 2: what to show and in which color

local events = newPage("Events & Colors")
y = -52
header(events, "Show", LEFT, y)
y = y - 30
local half = math.ceil((#ns.CATEGORIES + 1) / 2)
for i, category in ipairs(ns.CATEGORIES) do
    local column = i <= half and 0 or 1
    local row = column == 0 and i - 1 or i - 1 - half
    checkbox(events, category.label, LEFT + 4 + column * 310, y - row * 28,
        function() return ns.Options().show[category.key] ~= false end,
        function(v)
            if v then v = nil end -- nil = shown, the default
            ns.Options().show[category.key] = v
        end)
end
checkbox(events, "Buff / debuff fades", LEFT + 4 + 310, y - (#ns.CATEGORIES - half) * 28,
    function() return ns.Options().fades end, function(v) ns.Options().fades = v end)

y = y - half * 28 - 20
header(events, "Colors", LEFT, y)
y = y - 30
half = math.ceil(#ns.COLOR_SLOTS / 2)
for i, slot in ipairs(ns.COLOR_SLOTS) do
    local column = i <= half and 0 or 1
    local row = column == 0 and i - 1 or i - 1 - half
    colorSwatch(events, slot, LEFT + 10 + column * 310, y - row * 28)
end
y = y - half * 28 - 8
button(events, "Reset colors", LEFT + 8, y, 140, function()
    ns.Options().colors = {}
    changed()
    for _, refresh in ipairs(events.refreshers) do refresh() end
end)
events.OnDefault = function()
    local o = ns.Options()
    o.show, o.colors, o.fades = {}, {}, true
    ns.ApplySettings()
end
events.OnRefresh = general.OnRefresh

-- ---------------------------------------------------------------------------
-- registration

local category = Settings.RegisterCanvasLayoutCategory(general, TITLE)
Settings.RegisterCanvasLayoutSubcategory(category, events, events.name)
Settings.RegisterAddOnCategory(category)

function ns.OpenOptions()
    Settings.OpenToCategory(category:GetID())
end

-- addon compartment (minimap addon button) entry, declared in the .toc
function KPCombatText_OpenOptions()
    ns.OpenOptions()
end
