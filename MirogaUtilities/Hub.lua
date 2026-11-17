-- Hub.lua: the one window for every module (/mu). Flat dark surfaces,
-- white-alpha lines and one accent, in the style of EllesmereUI and Naowh
-- Forever. Fonts come from those addons when installed, else the game font.
local _, root = ...
local ACCENT, ACCENT_HEX, Say = root.ACCENT, root.ACCENT_HEX, root.Say

local T = {
    bg     = { 0.098, 0.106, 0.114 },  -- #191b1d
    panel  = { 0.118, 0.125, 0.133 },  -- #1e2022
    line   = { 1, 1, 1, 0.07 },
    fg     = { 0.94, 0.945, 0.953 },
    muted  = { 0.60, 0.62, 0.65 },
    track  = { 0.267, 0.267, 0.267 },
}
local WHITE = "Interface\\Buttons\\WHITE8x8"
local PAD = 28            -- page side padding
local WINDOW_W, WINDOW_H, SIDEBAR_W = 800, 690, 210

local FONT, MONO = STANDARD_TEXT_FONT, nil
do
    local probe = UIParent:CreateFontString()
    local function try(path)
        local ok, valid = pcall(probe.SetFont, probe, path, 12, "")
        return ok and valid ~= false
    end
    for _, path in ipairs({ "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.ttf",
        "Interface\\AddOns\\NaowhForever\\Core\\Media\\Fonts\\Naowh.ttf" }) do
        if try(path) then FONT = path; break end
    end
    local mono = "Interface\\AddOns\\NaowhForever\\Core\\Media\\Fonts\\JetBrainsMonoNL-Regular.ttf"
    if try(mono) then MONO = mono end
end

-- ---------------------------------------------------------------------------
-- primitives

local function Text(parent, size, color, mono)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(mono and MONO or FONT, size, "")
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 0.6)
    color = color or T.fg
    fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    fs:SetJustifyH("LEFT")
    return fs
end

local function Fill(parent, color, layer)
    local tex = parent:CreateTexture(nil, layer or "BACKGROUND")
    tex:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
    return tex
end

local function FlatButton(parent, text, width, onClick, primary)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(width, 26)
    b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    local label = Text(b, 12)
    label:SetPoint("LEFT", 8, 0)
    label:SetPoint("RIGHT", -8, 0)
    label:SetJustifyH("CENTER")
    label:SetWordWrap(false)
    label:SetText(text)
    b.label = label
    local function paint(hover)
        if primary then
            b:SetBackdropColor(ACCENT[1], ACCENT[2], ACCENT[3], hover and 0.45 or 0.30)
            b:SetBackdropBorderColor(ACCENT[1], ACCENT[2], ACCENT[3], hover and 0.9 or 0.6)
            label:SetTextColor(1, 1, 1, hover and 1 or 0.9)
        else
            b:SetBackdropColor(0.089, 0.080, 0.072, hover and 0.75 or 0.6)
            b:SetBackdropBorderColor(1, 1, 1, hover and 0.45 or 0.25)
            label:SetTextColor(1, 1, 1, hover and 0.85 or 0.65)
        end
    end
    paint(false)
    b:SetScript("OnEnter", function() paint(true) end)
    b:SetScript("OnLeave", function() paint(false) end)
    if onClick then b:SetScript("OnClick", onClick) end
    function b:SetLabel(t) label:SetText(t) end
    return b
end

local function Toggle(parent, get, set)
    local t = CreateFrame("Button", nil, parent)
    t:SetSize(40, 20)
    local track = Fill(t, T.track, "ARTWORK")
    track:SetAllPoints()
    local knob = t:CreateTexture(nil, "OVERLAY")
    knob:SetColorTexture(1, 1, 1, 1)
    knob:SetSize(14, 14)
    local function paint()
        local on = get() and true or false
        knob:ClearAllPoints()
        if on then
            track:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.8)
            knob:SetPoint("RIGHT", -3, 0)
            knob:SetVertexColor(1, 1, 1, 1)
        else
            track:SetColorTexture(T.track[1], T.track[2], T.track[3], 0.65)
            knob:SetPoint("LEFT", 3, 0)
            knob:SetVertexColor(1, 1, 1, 0.5)
        end
    end
    t:SetScript("OnClick", function()
        set(not get())
        paint()
    end)
    t.Refresh = paint
    return t
end

-- flat slider: white-alpha track, accent fill up to a white thumb
local function FlatSlider(parent, width, min, max, step, get, set, format)
    local s = CreateFrame("Slider", nil, parent)
    s:SetOrientation("HORIZONTAL")
    s:SetSize(width, 16)
    s:SetMinMaxValues(min, max)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)
    s:EnableMouseWheel(true)
    local track = Fill(s, { 1, 1, 1, 0.16 }, "BACKGROUND")
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")
    track:SetHeight(4)
    s:SetThumbTexture(WHITE)
    local thumb = s:GetThumbTexture()
    thumb:SetSize(8, 16)
    thumb:SetVertexColor(1, 1, 1, 1)
    local fill = Fill(s, { ACCENT[1], ACCENT[2], ACCENT[3], 0.75 }, "ARTWORK")
    fill:SetPoint("LEFT", track, "LEFT")
    fill:SetPoint("RIGHT", thumb, "CENTER")
    fill:SetHeight(4)
    local value = Text(parent, 12, ACCENT)
    value:SetPoint("LEFT", s, "RIGHT", 10, 0)
    value:SetWidth(56)
    local refreshing = false
    local function show(v) value:SetText(format and format(v) or tostring(v)) end
    s:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v / step + 0.5) * step
        show(v)
        if not refreshing then set(v) end
    end)
    s:SetScript("OnMouseWheel", function(self, delta)
        self:SetValue(math.max(min, math.min(max, self:GetValue() + delta * step)))
    end)
    s.Refresh = function()
        refreshing = true
        s:SetValue(get())
        show(get())
        refreshing = false
    end
    return s
end

-- button that shows the current choice and opens a menu of all choices
local function MenuButton(parent, width, choices, get, set)
    local b = FlatButton(parent, "", width)
    b.label:SetJustifyH("LEFT")
    local arrow = Text(b, 10, T.muted)
    arrow:SetPoint("RIGHT", -8, 0)
    arrow:SetText("v")
    local function list() return type(choices) == "function" and choices() or choices end
    local function refresh()
        for _, c in ipairs(list()) do
            if c.value == get() then b:SetLabel(c.text); return end
        end
        b:SetLabel(tostring(get() or "-"))
    end
    b:SetScript("OnClick", function(self)
        if MenuUtil and MenuUtil.CreateContextMenu then
            MenuUtil.CreateContextMenu(self, function(_, menu)
                menu:SetScrollMode(320)
                for _, c in ipairs(list()) do
                    menu:CreateRadio(c.text, function() return get() == c.value end, function()
                        set(c.value)
                        refresh()
                    end)
                end
            end)
        else
            local items, nextValue = list(), nil
            for i, c in ipairs(items) do
                if c.value == get() then nextValue = items[i % #items + 1].value end
            end
            set(nextValue == nil and items[1].value or nextValue)
            refresh()
        end
    end)
    b.Refresh = refresh
    return b
end

local function Swatch(parent, get, set)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(22, 22)
    b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    b:SetBackdropBorderColor(1, 1, 1, 0.3)
    local function refresh()
        local r, g, bl = get()
        b:SetBackdropColor(r, g, bl, 1)
    end
    b:SetScript("OnClick", function()
        local r, g, bl = get()
        ColorPickerFrame:SetupColorPickerAndShow({
            r = r, g = g, b = bl,
            swatchFunc = function() set(ColorPickerFrame:GetColorRGB()); refresh() end,
            cancelFunc = function(prev) set(prev.r, prev.g, prev.b); refresh() end,
        })
    end)
    b.Refresh = refresh
    return b
end

local function Input(parent, width, placeholder, onEnter, onChange)
    local e = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    e:SetSize(width, 26)
    e:SetAutoFocus(false)
    e:SetFont(FONT, 13, "")
    e:SetTextColor(T.fg[1], T.fg[2], T.fg[3])
    e:SetTextInsets(8, 8, 0, 0)
    e:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    e:SetBackdropColor(0.03, 0.023, 0.018, 0.5)
    e:SetBackdropBorderColor(1, 1, 1, 0.15)
    local hint = Text(e, 12, { 1, 1, 1, 0.3 })
    hint:SetPoint("LEFT", 8, 0)
    hint:SetText(placeholder)
    e:SetScript("OnTextChanged", function(self)
        hint:SetShown(self:GetText() == "")
        if onChange then onChange(self:GetText()) end
    end)
    e:SetScript("OnEditFocusGained", function(self) self:SetBackdropBorderColor(ACCENT[1], ACCENT[2], ACCENT[3], 0.7) end)
    e:SetScript("OnEditFocusLost", function(self) self:SetBackdropBorderColor(1, 1, 1, 0.15) end)
    e:SetScript("OnEscapePressed", e.ClearFocus)
    e:SetScript("OnEnterPressed", function(self) if onEnter then onEnter(self:GetText()) end end)
    return e
end

-- ---------------------------------------------------------------------------
-- page: fixed title block, scrolling body with a cursor for rows

local function NewPage(parent, title, subtitle)
    local page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints()
    page:Hide()
    page.refreshers = {}
    page.rows = 0
    local head = Text(page, 22)
    head:SetPoint("TOPLEFT", PAD, -22)
    head:SetText(title)
    local sub = Text(page, 12, T.muted)
    sub:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -6)
    sub:SetPoint("RIGHT", page, "RIGHT", -PAD - 30, 0)
    sub:SetText(subtitle or "")
    local div = Fill(page, T.line, "ARTWORK")
    div:SetPoint("TOPLEFT", PAD, -76)
    div:SetPoint("TOPRIGHT", -PAD, -76)
    div:SetHeight(1)

    local scroll = CreateFrame("ScrollFrame", nil, page)
    scroll:SetPoint("TOPLEFT", 0, -78)
    scroll:SetPoint("BOTTOMRIGHT", 0, 6)
    local body = CreateFrame("Frame", nil, scroll)
    body:SetSize(WINDOW_W - SIDEBAR_W - 2, 10)
    scroll:SetScrollChild(body)
    page.body, page.scroll = body, scroll
    page.y = -12

    local bar = Fill(page, { 1, 1, 1, 0.18 }, "ARTWORK")
    bar:SetWidth(3)
    bar:Hide()
    local function updateBar()
        local view, full = scroll:GetHeight(), body:GetHeight()
        if full <= view + 1 then bar:Hide(); return end
        local h = math.max(24, view * view / full)
        local offset = scroll:GetVerticalScroll() / (full - view) * (view - h)
        bar:SetHeight(h)
        bar:ClearAllPoints()
        bar:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", -8, -offset)
        bar:Show()
    end
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = math.max(0, body:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(maxScroll, self:GetVerticalScroll() - delta * 48)))
        updateBar()
    end)
    function page:Finish()
        body:SetHeight(-self.y + 16)
        updateBar()
    end
    page:SetScript("OnShow", function(self)
        for _, refresh in ipairs(self.refreshers) do refresh() end
        updateBar()
    end)
    function page:Refresh()
        for _, refresh in ipairs(self.refreshers) do refresh() end
    end
    return page
end

local function Section(page, text)
    if page.y < -12 then page.y = page.y - 14 end
    local fs = Text(page.body, 11, { 1, 1, 1, 0.45 })
    fs:SetPoint("TOPLEFT", PAD + 2, page.y)
    fs:SetText(text:upper())
    page.y = page.y - 20
    page.rows = 0
    return fs
end

local function Row(page, label, desc, height)
    local row = CreateFrame("Frame", nil, page.body)
    row:SetPoint("TOPLEFT", PAD, page.y)
    row:SetPoint("TOPRIGHT", -PAD, page.y)
    row:SetHeight(height or (desc and 44 or 34))
    page.rows = page.rows + 1
    Fill(row, { 0, 0, 0, page.rows % 2 == 1 and 0.12 or 0.22 }):SetAllPoints()
    local name = Text(row, 13)
    if desc then
        name:SetPoint("TOPLEFT", 12, -8)
        local d = Text(row, 11, T.muted)
        d:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -4)
        d:SetPoint("RIGHT", row, "RIGHT", -200, 0)
        d:SetWordWrap(false)
        d:SetText(desc)
        row.desc = d
    else
        name:SetPoint("LEFT", 12, 0)
    end
    name:SetText(label or "")
    row.name = name
    page.y = page.y - row:GetHeight() - 2
    return row
end

local function Control(page, row, widget, x)
    widget:SetPoint("RIGHT", row, "RIGHT", x or -12, 0)
    if row.desc and not row.descFitted then
        row.descFitted = true
        row.desc:SetPoint("RIGHT", widget, "LEFT", -12, 0)
    end
    if widget.Refresh then page.refreshers[#page.refreshers + 1] = widget.Refresh end
    return widget
end

local function ToggleRow(page, label, desc, get, set)
    local row = Row(page, label, desc)
    Control(page, row, Toggle(row, get, set))
    return row
end

local function ButtonRow(page, label, desc, text, onClick, primary)
    local row = Row(page, label, desc)
    row.button = Control(page, row, FlatButton(row, text, 130, onClick, primary))
    return row
end

local function SliderRow(page, label, desc, min, max, step, get, set, format)
    local row = Row(page, label, desc)
    Control(page, row, FlatSlider(row, 170, min, max, step, get, set, format), -78)
    return row
end

local function MenuRow(page, label, desc, choices, get, set)
    local row = Row(page, label, desc)
    Control(page, row, MenuButton(row, 220, choices, get, set))
    return row
end

-- two-column grid of small cells (toggles, swatches)
local function Grid(page, count, build)
    local half = math.ceil(count / 2)
    local width = (WINDOW_W - SIDEBAR_W - 2 - 2 * PAD - 4) / 2
    for i = 1, count do
        local column = i <= half and 0 or 1
        local line = column == 0 and i or i - half
        local cell = CreateFrame("Frame", nil, page.body)
        cell:SetSize(width, 32)
        cell:SetPoint("TOPLEFT", PAD + column * (width + 4), page.y - (line - 1) * 34)
        Fill(cell, { 0, 0, 0, line % 2 == 1 and 0.12 or 0.22 }):SetAllPoints()
        build(cell, i)
    end
    page.y = page.y - half * 34
end

local function Note(page, text)
    local fs = Text(page.body, 11, T.muted)
    fs:SetPoint("TOPLEFT", PAD + 2, page.y - 8)
    fs:SetPoint("RIGHT", page.body, "RIGHT", -PAD, 0)
    fs:SetText(text)
    page.y = page.y - 44
    return fs
end

local function ButtonBar(page, buttons)
    page.y = page.y - 12
    local last
    for _, spec in ipairs(buttons) do
        local b = FlatButton(page.body, spec[1], spec[2], spec[3], spec[4])
        if last then b:SetPoint("LEFT", last, "RIGHT", 8, 0) else b:SetPoint("TOPLEFT", PAD, page.y) end
        last = b
        spec.button = b
    end
    page.y = page.y - 34
end

-- ---------------------------------------------------------------------------
-- combat text: general

local BUILTIN_FONTS = {
    { value = false, text = "Addon default" },
    { value = "Interface\\AddOns\\NaowhUI_Media\\Shared\\Fonts\\GothamNarrowUltra.ttf", text = "Gotham Narrow Ultra" },
    { value = "Fonts\\FRIZQT__.TTF", text = "Friz Quadrata" },
    { value = "Fonts\\ARIALN.TTF", text = "Arial Narrow" },
    { value = "Fonts\\skurri.ttf", text = "Skurri" },
    { value = "Fonts\\MORPHEUS.ttf", text = "Morpheus" },
}

local function FontChoices()
    local list, seen = {}, {}
    for _, f in ipairs(BUILTIN_FONTS) do
        list[#list + 1] = f
        if f.value then seen[f.value:lower()] = true end
    end
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM then
        local names = LSM:List("font")
        for _, name in ipairs(names) do
            local path = LSM:Fetch("font", name, true)
            if type(path) == "string" and not seen[path:lower()] then
                list[#list + 1] = { value = path, text = name }
                seen[path:lower()] = true
            end
        end
    end
    return list
end

local OUTLINES = {
    { value = "default", text = "Game default" },
    { value = "NONE", text = "None" },
    { value = "OUTLINE", text = "Outline" },
    { value = "THICKOUTLINE", text = "Thick outline" },
}

local DIRS = { "up", "down", "left", "right" }
local DIR_TEXT = { up = "Up", down = "Down", left = "Left", right = "Right" }

local function PositionRow(page, ct, name, label)
    local row = Row(page, label, "Steps of 10 px, Shift: 1 px.")
    local function step(dx, dy)
        local n = IsShiftKeyDown() and 1 or 10
        ct.MoveStream(name, dx * n, dy * n)
        ct.Sample(name)
        page:Refresh()
    end
    local yPlus = FlatButton(row, "+", 24, function() step(0, 1) end)
    yPlus:SetPoint("RIGHT", -12, 0)
    local yVal = Text(row, 12, ACCENT)
    yVal:SetWidth(44)
    yVal:SetJustifyH("CENTER")
    yVal:SetPoint("RIGHT", yPlus, "LEFT", -2, 0)
    local yMinus = FlatButton(row, "-", 24, function() step(0, -1) end)
    yMinus:SetPoint("RIGHT", yVal, "LEFT", -2, 0)
    local yLabel = Text(row, 11, T.muted)
    yLabel:SetPoint("RIGHT", yMinus, "LEFT", -4, 0)
    yLabel:SetText("Y")
    local xPlus = FlatButton(row, "+", 24, function() step(1, 0) end)
    xPlus:SetPoint("RIGHT", yLabel, "LEFT", -10, 0)
    local xVal = Text(row, 12, ACCENT)
    xVal:SetWidth(44)
    xVal:SetJustifyH("CENTER")
    xVal:SetPoint("RIGHT", xPlus, "LEFT", -2, 0)
    local xMinus = FlatButton(row, "-", 24, function() step(-1, 0) end)
    xMinus:SetPoint("RIGHT", xVal, "LEFT", -2, 0)
    local xLabel = Text(row, 11, T.muted)
    xLabel:SetPoint("RIGHT", xMinus, "LEFT", -4, 0)
    xLabel:SetText("X")
    local dir
    dir = FlatButton(row, "", 62, function()
        local current, nextDir = ct.streams[name].direction, DIRS[1]
        for i, d in ipairs(DIRS) do
            if d == current then nextDir = DIRS[i % #DIRS + 1] end
        end
        ct.SetDirection(name, nextDir)
        ct.Sample(name)
        dir:SetLabel(DIR_TEXT[nextDir])
    end)
    dir:SetPoint("RIGHT", xLabel, "LEFT", -10, 0)
    row.desc:SetPoint("RIGHT", dir, "LEFT", -8, 0)
    page.refreshers[#page.refreshers + 1] = function()
        local x, y = ct.StreamPosition(name)
        xVal:SetText(x)
        yVal:SetText(y)
        dir:SetLabel(DIR_TEXT[ct.streams[name].direction] or "Up")
    end
end

local function BuildTextPage(page)
    local ct = root.CombatText
    local function o() return ct.Options() end
    local function apply() ct.ApplySettings() end
    local L = ct.LIMITS

    Section(page, "Scroll areas")
    ToggleRow(page, "Damage taken & debuffs", "Left box.",
        function() return not o().streamOff.incoming end,
        function(v) o().streamOff.incoming = not v or nil end)
    ToggleRow(page, "Heals, buffs & gains", "Right box.",
        function() return not o().streamOff.gains end,
        function(v) o().streamOff.gains = not v or nil end)
    PositionRow(page, ct, "incoming", "Damage taken box")
    PositionRow(page, ct, "gains", "Heals & buffs box")

    Section(page, "Text")
    MenuRow(page, "Font", nil, FontChoices,
        function() return o().font end, function(v) o().font = v; apply(); ct.Sample("incoming") end)
    MenuRow(page, "Outline", nil, OUTLINES,
        function() return o().outline end, function(v) o().outline = v; apply(); ct.Sample("incoming") end)
    SliderRow(page, "Text size", nil, L.scale[1], L.scale[2], 0.05,
        function() return o().scale end, function(v) o().scale = v; apply() end,
        function(v) return string.format("%d%%", v * 100 + 0.5) end)
    SliderRow(page, "Display time", nil, L.lifetime[1], L.lifetime[2], 0.1,
        function() return o().lifetime end, function(v) o().lifetime = v; apply() end,
        function(v) return string.format("%.1f s", v) end)
    SliderRow(page, "Scroll distance", nil, L.distance[1], L.distance[2], 10,
        function() return o().distance end, function(v) o().distance = v; apply() end,
        function(v) return string.format("%d px", v) end)
    SliderRow(page, "Merge repeats within", "Same hit twice in this window: one line, x2.", L.window[1], L.window[2], 0.05,
        function() return o().window end, function(v) o().window = v; apply() end,
        function(v) return v < 0.01 and "off" or string.format("%.2f s", v) end)

    Section(page, "Extras")
    ToggleRow(page, "Spell school colors", "Fire orange, frost blue, ... (colors on the Events page).",
        function() return o().schoolColors end, function(v) o().schoolColors = v; apply() end)
    ToggleRow(page, "Icons", "School icon on damage and heals, aura icon on buffs and debuffs.",
        function() return o().schoolIcons end, function(v) o().schoolIcons = v; apply() end)
    ToggleRow(page, "Crits pop larger", nil,
        function() return o().critPop end, function(v) o().critPop = v; apply() end)
    ToggleRow(page, "Same font for your damage", "Blizzard's numbers over enemies. Takes effect after a logout.",
        function() return o().worldFont end, function(v) o().worldFont = v end)
    ToggleRow(page, "Blizzard's own text too", "Shows Blizzard's incoming numbers as well (doubles them).",
        function() return o().blizzSelf end,
        function(v) if v ~= o().blizzSelf then ct.ToggleBlizzard() end end)

    local bar = {
        { "Move boxes", 120, nil, true },
        { "Preview", 90, function() ct.Preview() end },
        { "Reset positions", 120, function() ct.ResetPositions(); page:Refresh() end },
        { "Reset settings", 120, function()
            KPCombatTextDB.options = nil
            apply()
            page:Refresh()
        end },
    }
    bar[1][3] = function() bar[1].button:SetLabel(ct.SetAnchorsShown(nil) and "Lock boxes" or "Move boxes") end
    ButtonBar(page, bar)
    page:HookScript("OnHide", function()
        ct.SetAnchorsShown(nil, false)
        bar[1].button:SetLabel("Move boxes")
    end)
    page:Finish()
end

-- ---------------------------------------------------------------------------
-- combat text: events & colors

local function BuildEventsPage(page)
    local ct = root.CombatText
    local function o() return ct.Options() end

    Section(page, "Show")
    local items = {}
    for _, c in ipairs(ct.CATEGORIES) do items[#items + 1] = c end
    items[#items + 1] = { key = "__fades", label = "Buff / debuff fades" }
    Grid(page, #items, function(cell, i)
        local item = items[i]
        local label = Text(cell, 12)
        label:SetPoint("LEFT", 10, 0)
        label:SetPoint("RIGHT", -56, 0)
        label:SetWordWrap(false)
        label:SetText(item.label)
        local get, set
        if item.key == "__fades" then
            get = function() return o().fades end
            set = function(v) o().fades = v end
        else
            get = function() return ct.CategoryShown(item.key) end
            set = function(v) ct.SetCategoryShown(item.key, v) end
        end
        local t = Toggle(cell, get, set)
        t:SetPoint("RIGHT", -8, 0)
        page.refreshers[#page.refreshers + 1] = t.Refresh
    end)

    Section(page, "Colors")
    local slots = ct.COLOR_SLOTS
    Grid(page, #slots, function(cell, i)
        local slot = slots[i]
        local label = Text(cell, 12)
        label:SetPoint("LEFT", 10, 0)
        label:SetText(slot.label)
        local function get()
            local c = ct.Color(o(), slot.key)
            return c[1], c[2], c[3]
        end
        local sw = Swatch(cell, get, function(r, g, b)
            o().colors[slot.key] = { r, g, b }
            ct.ApplySettings()
            local c = ct.Color(o(), slot.key)
            label:SetTextColor(c[1], c[2], c[3])
        end)
        sw:SetPoint("RIGHT", -10, 0)
        page.refreshers[#page.refreshers + 1] = function()
            sw.Refresh()
            local r, g, b = get()
            label:SetTextColor(r, g, b)
        end
    end)
    ButtonBar(page, {
        { "Reset colors", 120, function()
            o().colors = {}
            ct.ApplySettings()
            page:Refresh()
        end },
        { "Show all events", 130, function()
            o().show, o().fades = {}, true
            page:Refresh()
        end },
    })
    page:Finish()
end

-- ---------------------------------------------------------------------------
-- flagged players: the list

StaticPopupDialogs["MIROGA_CLEAR_FLAGS"] = {
    text = "Remove ALL flagged players from the list?",
    button1 = YES,
    button2 = NO,
    OnAccept = function() root.FlagPlates.ClearAll() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function BuildPlayersPage(page)
    local fp = root.FlagPlates
    local filter = ""

    Section(page, "Add a player")
    local addRow = Row(page, "", nil, 40)
    local input
    local function add(text)
        local first, last = fp.ParseName(text)
        if not first then return end
        if fp.Add(first, last) then
            input:SetText("")
        else
            fp.Print("Already on the list.")
        end
        input:ClearFocus()
    end
    input = Input(addRow, 220, "Name or Name Surname", add)
    input:SetPoint("LEFT", 8, 0)
    local addButton = FlatButton(addRow, "Add", 70, function() add(input:GetText()) end, true)
    addButton:SetPoint("LEFT", input, "RIGHT", 6, 0)
    local targetButton = FlatButton(addRow, "Flag / unflag target", 150, function() fp.ToggleTarget() end)
    targetButton:SetPoint("RIGHT", -8, 0)
    Note(page, "A first name alone matches every surname. Right-click any player for |cff" .. ACCENT_HEX .. "Flag player|r.")
    page.y = page.y + 12

    local header = Section(page, "On your list")
    local searchRow = Row(page, "", nil, 40)
    local search = Input(searchRow, 220, "Search", nil, function(text)
        filter = text
        if page.RefreshList then page.RefreshList() end
    end)
    search:SetPoint("LEFT", 8, 0)
    local clear = FlatButton(searchRow, "Remove all", 110, function() StaticPopup_Show("MIROGA_CLEAR_FLAGS") end)
    clear:SetPoint("RIGHT", -8, 0)

    local listTop = page.y
    local rows = {}
    local empty = Text(page.body, 12, T.muted)
    empty:SetPoint("TOPLEFT", PAD + 12, listTop - 10)
    empty:SetText("Nobody yet.")

    local function GetRow(i)
        if rows[i] then return rows[i] end
        local row = CreateFrame("Frame", nil, page.body)
        row:SetHeight(30)
        Fill(row, { 0, 0, 0, i % 2 == 1 and 0.12 or 0.22 }):SetAllPoints()
        row.name = Text(row, 13)
        row.name:SetPoint("LEFT", 12, 0)
        row.del = FlatButton(row, "X", 26, function()
            if row.key then fp.Remove(row.key) end
        end)
        row.del:SetHeight(22)
        row.del:SetPoint("RIGHT", -8, 0)
        row.stats = Text(row, 11, T.muted)
        row.stats:SetPoint("RIGHT", row.del, "LEFT", -10, 0)
        row.stats:SetJustifyH("RIGHT")
        row.name:SetPoint("RIGHT", row.stats, "LEFT", -10, 0)
        row.name:SetWordWrap(false)
        rows[i] = row
        return row
    end

    function page.RefreshList()
        if not fp.db then return end
        local keys = fp.SortedKeys(filter)
        header:SetText(string.format("ON YOUR LIST  |cff%s%d|r", ACCENT_HEX, fp.Count()))
        for i, k in ipairs(keys) do
            local e = fp.db.entries[k]
            local row = GetRow(i)
            row.key = k
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", PAD, listTop - (i - 1) * 32)
            row:SetPoint("TOPRIGHT", -PAD, listTop - (i - 1) * 32)
            if e.last then
                row.name:SetText(e.first .. " |cffaaaaaa" .. e.last .. "|r")
            else
                row.name:SetText(e.first .. " |cff777777(any surname)|r")
            end
            row.stats:SetText(fp.StatsText and fp.StatsText(e) or "")
            row:Show()
        end
        for i = #keys + 1, #rows do
            rows[i].key = nil
            rows[i]:Hide()
        end
        empty:SetShown(#keys == 0)
        page.y = listTop - math.max(1, #keys) * 32
        page:Finish()
    end
    page.refreshers[#page.refreshers + 1] = page.RefreshList
    page:Finish()
end

-- ---------------------------------------------------------------------------
-- flagged players: plates, alerts, statistics

local function BuildAlertsPage(page)
    local fp = root.FlagPlates
    local function db() return fp.db or {} end
    local function repaint() if fp.RepaintAll then fp.RepaintAll() end end

    Section(page, "Nameplates")
    local colorRow = Row(page, "Flag color")
    local swatch = Swatch(colorRow, function()
        local c = db().color or fp.DEFAULTS.color
        return c.r, c.g, c.b
    end, function(r, g, b)
        local c = db().color
        c.r, c.g, c.b = r, g, b
        repaint()
    end)
    Control(page, colorRow, swatch, -100)
    Control(page, colorRow, FlatButton(colorRow, "Default", 76, function()
        local c, d = db().color, fp.DEFAULTS.color
        c.r, c.g, c.b = d.r, d.g, d.b
        repaint()
        swatch.Refresh()
    end))
    ToggleRow(page, "Color the health bar", nil,
        function() return db().colorBar end, function(v) db().colorBar = v; repaint() end)
    ToggleRow(page, "Color the name", nil,
        function() return db().colorName end, function(v) db().colorName = v; repaint() end)

    Section(page, "When one shows up")
    ToggleRow(page, "Chat message", "Name plus how often you met, killed and were killed by them.",
        function() return db().alert end, function(v) db().alert = v end)
    local soundChoices = {}
    for _, s in ipairs(fp.SOUNDS or {}) do soundChoices[#soundChoices + 1] = { value = s.key, text = s.label } end
    MenuRow(page, "Sound", "Plays when a flagged player shows up. Several at once give one sound.", soundChoices,
        function() return db().sound end,
        function(v) db().sound = v; fp.PlayAlertSound(v) end)
    MenuRow(page, "Alert again", "When the same player comes back into view after 30 s out of sight.", {
        { value = 0, text = "Never (once per encounter)" },
        { value = 60, text = "After 1 min" },
        { value = 120, text = "After 2 min" },
        { value = 300, text = "After 5 min" },
    }, function() return db().repeatGap end, function(v) db().repeatGap = v end)

    Section(page, "Statistics")
    ToggleRow(page, "Show in tooltip", "Flagged + met / killed / deaths under the player's name.",
        function() return db().tooltip end, function(v) db().tooltip = v end)
    ButtonRow(page, "Clear statistics", "Resets the counters of every player. The list stays.", "Clear",
        function() fp.ConfirmPurgeStats() end)
    Note(page, "Kills count from honor kill messages and from your flagged target dying while you fight. Deaths come from the death recap or a flagged player who had you targeted.")
    page:Finish()
end

-- ---------------------------------------------------------------------------
-- powershift

local SHIFT_KEYS = {
    { "Cat Form", "CLICK MirogaShiftCat:LeftButton" },
    { "Bear Form", "CLICK MirogaShiftBear:LeftButton" },
    { "Travel / Aquatic Form", "CLICK MirogaShiftTravel:LeftButton", "Detects: Aquatic in water, Travel outdoors. Again = cancel." },
}

local function BuildShiftPage(page)
    local _, class = UnitClass("player")
    if class ~= "DRUID" then
        Note(page, "Powershift is for druids only.")
        page:Finish()
        return
    end
    Section(page, "Keys")
    for _, key in ipairs(SHIFT_KEYS) do
        local row = Row(page, key[1], key[3])
        local bound = Text(row, 13, ACCENT, MONO ~= nil)
        bound:SetPoint("RIGHT", -14, 0)
        bound:SetJustifyH("RIGHT")
        page.refreshers[#page.refreshers + 1] = function()
            local k1, k2 = GetBindingKey(key[2])
            if k1 then
                bound:SetText(GetBindingText(k1) .. (k2 and ("|cff888888 / |r" .. GetBindingText(k2)) or ""))
            else
                bound:SetText("|cff888888not bound|r")
            end
        end
    end
    ButtonBar(page, { { "Set keys", 120, function()
        local ok = Settings and Settings.KEYBINDINGS_CATEGORY_ID
            and pcall(Settings.OpenToCategory, Settings.KEYBINDINGS_CATEGORY_ID)
        if not ok then Say("Game Menu > Options > Keybindings > AddOns.") end
    end, true } })
    Note(page, "Key down cancels your form, key up casts the new one, so the main bar never sticks on page 1. Works in combat. Keybindings > AddOns.")
    page:Finish()
end

-- ---------------------------------------------------------------------------
-- auto mark

local function BuildMarksPage(page)
    local am = root.AutoMark
    local function db() return am.db or {} end

    Section(page, "Auto Mark")
    ToggleRow(page, "On", "When a new player joins and only your listed players are in the party.",
        function() return db().enabled end, function(v) am.SetEnabled(v) end)

    Section(page, "Players and marks")
    for i = 1, am.SLOTS do
        local row = Row(page, "Player " .. i, nil, 40)
        local input = Input(row, 230, "Name or Name Surname", function(text)
            db().slots[i].name = strtrim(text)
        end, function(text)
            if db().slots then db().slots[i].name = strtrim(text) end
        end)
        input:SetPoint("LEFT", 90, 0)
        input:SetScript("OnEditFocusLost", function(self)
            self:SetBackdropBorderColor(1, 1, 1, 0.15)
            db().slots[i].name = strtrim(self:GetText())
        end)
        page.refreshers[#page.refreshers + 1] = function()
            if db().slots and not input:HasFocus() then input:SetText(db().slots[i].name or "") end
        end
        Control(page, row, MenuButton(row, 170, am.MarkChoices,
            function() return db().slots and db().slots[i].mark or 0 end,
            function(v) db().slots[i].mark = v end))
    end
    MenuRow(page, "Your own mark", "Goes on you too when the group is all yours.", am.MarkChoices(),
        function() return db().self end, function(v) db().self = v end)

    ButtonBar(page, {
        { "Check now", 110, function() am.Apply(true) end, true },
        { "Set key", 100, function()
            local ok = Settings and Settings.KEYBINDINGS_CATEGORY_ID
                and pcall(Settings.OpenToCategory, Settings.KEYBINDINGS_CATEGORY_ID)
            if not ok then Say("Game Menu > Options > Keybindings > AddOns.") end
        end },
        { "Reset button position", 170, function() am.ResetPosition() end },
    })
    Note(page, "Forever lets addons set marks only on a click or key press, so a |cff" .. ACCENT_HEX .. "Mark group|r button pops up: one click marks everyone (or bind a key). Right-drag moves it.")
    page:Finish()
end

-- ---------------------------------------------------------------------------
-- weather

local function BuildWeatherPage(page)
    local wx = root.Weather
    local function db() return wx.db or wx.DEFAULTS end

    Section(page, "Weather")
    ToggleRow(page, "Low weather", "On: rain, snow and sandstorms drop to the level below. Off: your old values come back.",
        function() return wx.IsLow() end, function(v) wx.SetLow(v) end)
    SliderRow(page, "Low level", "0 = no weather, 3 = full storm. Changes apply at once while low is on.",
        0, 3, 1, function() return db().level end, function(v) wx.SetLevel(v) end,
        function(v) return tostring(v) end)

    Section(page, "Automatic")
    ToggleRow(page, "In storm zones", "Low while you are in a zone on the list, back when you leave.",
        function() return db().autoZones end, function(v) wx.SetAuto("autoZones", v) end)
    ToggleRow(page, "In battlegrounds", "Low inside every battleground, back when you leave.",
        function() return db().autoBG end, function(v) wx.SetAuto("autoBG", v) end)
    local zoneRow = Row(page, "Zones", nil, 40)
    local zones = Input(zoneRow, 430, "Zone, Zone, ...", function(text)
        wx.SetZones(strtrim(text))
    end)
    zones:SetPoint("LEFT", 70, 0)
    zones:SetScript("OnEditFocusLost", function(self)
        self:SetBackdropBorderColor(1, 1, 1, 0.15)
        wx.SetZones(strtrim(self:GetText()))
    end)
    page.refreshers[#page.refreshers + 1] = function()
        if not zones:HasFocus() then zones:SetText(db().zones or "") end
    end
    ButtonBar(page, { { "Add current zone", 150, function() wx.AddCurrentZone() end } })
    Note(page, "Zone names as the game shows them, split by commas. Switch it off by hand inside a zone and it stays off until you leave.")

    Section(page, "Status")
    local row = Row(page, "Now in the game", "weatherDensity right now, and the value \"off\" brings back.")
    local status = Text(row, 13, ACCENT, MONO ~= nil)
    status:SetPoint("RIGHT", -14, 0)
    status:SetJustifyH("RIGHT")
    page.refreshers[#page.refreshers + 1] = function()
        local now = wx.Current()
        local back = db().saved and db().saved.weatherDensity
        status:SetText((now and tostring(now) or "?") .. (wx.IsLow() and back and ("|cff888888  (back: " .. back .. ")|r") or ""))
    end

    ButtonBar(page, {
        { "Toggle now", 110, function() wx.Toggle() end, true },
        { "Set key", 100, function()
            local ok = Settings and Settings.KEYBINDINGS_CATEGORY_ID
                and pcall(Settings.OpenToCategory, Settings.KEYBINDINGS_CATEGORY_ID)
            if not ok then Say("Game Menu > Options > Keybindings > AddOns.") end
        end },
    })
    Note(page, "Key: Keybindings > AddOns > |cff" .. ACCENT_HEX .. "Weather: low / back|r. Fog from the zone's lighting may stay; particles go.")
    page:Finish()
end

-- ---------------------------------------------------------------------------
-- login quiet

local function BuildQuietPage(page)
    local lq = root.LoginQuiet
    local function db() return lq.db or lq.DEFAULTS end

    Section(page, "Login quiet")
    ToggleRow(page, "On", "Hides addon messages after login and /reload. Player chat and system messages stay.",
        function() return db().enabled end, function(v) lq.SetEnabled(v) end)
    SliderRow(page, "Quiet for", "Seconds after the loading screen. Slow addons talk late.",
        3, 30, 1, function() return db().seconds end, function(v) db().seconds = v end,
        function(v) return v .. " s" end)

    Section(page, "This session")
    local row = Row(page, "Hidden lines", "Everything that was swallowed since the last login or reload.")
    local count = Text(row, 13, ACCENT, MONO ~= nil)
    count:SetPoint("RIGHT", -14, 0)
    count:SetJustifyH("RIGHT")
    page.refreshers[#page.refreshers + 1] = function() count:SetText(tostring(#lq.hidden)) end

    ButtonBar(page, { { "Show in chat", 130, function() lq.Show() end, true } })
    Note(page, "Takes effect from the next login or /reload.")
    page:Finish()
end

-- ---------------------------------------------------------------------------
-- vendor coin

local function BuildVendorPage(page)
    local vc = root.VendorCoin
    local function db() return vc.db or vc.DEFAULTS end
    local function set(key) return function(v) vc.Set(key, v) end end

    Section(page, "Vendor coin")
    ToggleRow(page, "Red coin on bag items", "When the vendor pays more than the AH after its fees. Held items get the hourglass.",
        function() return db().enabled end, set("enabled"))
    ToggleRow(page, "Soulbound items too", "They can't go to the AH anyway, so off keeps the bags calm.",
        function() return db().bound end, set("bound"))
    ToggleRow(page, "Amber coin when the amount decides", "Vendor wins for one, AH for a full stack. The tooltip says from how many on.",
        function() return db().amber end, set("amber"))
    ToggleRow(page, "Coin details in the tooltip", "Prices per unit, the break-even amount and what you carry.",
        function() return db().tooltip end, set("tooltip"))
    local corners = {}
    for _, c in ipairs(vc.CORNERS) do corners[#corners + 1] = { value = c[1], text = c[2] } end
    MenuRow(page, "Coin corner", "Where the red coin sits on the item. Bags, Baganator and Auctionator.",
        corners, function() return db().coinCorner end, set("coinCorner"))
    MenuRow(page, "Hourglass corner", "Where the green hourglass of held items sits.",
        corners, function() return db().holdCorner end, set("holdCorner"))

    Section(page, "Auction house fees")
    SliderRow(page, "AH cut", "Taken from every sale. 5 % at the faction AH, 15 % at a neutral one.",
        0, 15, 1, function() return db().cut end, set("cut"), function(v) return v .. " %" end)
    SliderRow(page, "Your effort", "Extra on top of the cut for the work of listing and relisting.",
        0, 15, 1, function() return db().effort end, set("effort"), function(v) return v .. " %" end)
    ToggleRow(page, "Count the deposit", "On: as if one listing does not sell and the deposit is lost. Off: it sells.",
        function() return db().deposit end, set("deposit"))
    local choices = {}
    for _, d in ipairs(vc.DURATIONS) do choices[#choices + 1] = { value = d[1], text = d[2] } end
    MenuRow(page, "Listing time", "The deposit grows with the listing time.",
        choices, function() return db().duration end, set("duration"))
    MenuRow(page, "Minimum deposit", "Per auction, shared by a full stack of the item. Forever: 1 silver, 1 copper after Nov 18.",
        { { value = 100, text = "1 silver" }, { value = 1, text = "1 copper" } },
        function() return db().minDeposit end, set("minDeposit"))

    Section(page, "Status")
    local row = Row(page, "Deposit rate", "Share of the vendor price. Measured each time the AH opens.")
    local status = Text(row, 13, ACCENT, MONO ~= nil)
    status:SetPoint("RIGHT", -14, 0)
    status:SetJustifyH("RIGHT")
    local source = Row(page, "Prices from", "Auctionator's scan database. Scan at the AH to fill it.")
    local src = Text(source, 13, ACCENT, MONO ~= nil)
    src:SetPoint("RIGHT", -14, 0)
    src:SetJustifyH("RIGHT")
    page.refreshers[#page.refreshers + 1] = function()
        local rate, measured = vc.Rate()
        status:SetText(("%.1f %%"):format(rate * 100) .. (measured and "" or "|cff888888  (guess, open the AH once)|r"))
        local sp = root.Stockpile
        if not vc.HasAuctionator() then
            src:SetText("|cffff5050Auctionator missing|r")
        elseif sp then
            local age = sp.ScanAge()
            local old = not age or age >= 86400
            src:SetText("Auctionator, scan " .. (old and "|cffff9933" or "") .. sp.AgeText(age) .. (old and "|r" or ""))
        else
            src:SetText("Auctionator")
        end
    end
    Note(page, "The item tooltip shows the numbers. Baganator shows them as corner widgets 'Miroga: ...' under Icons; the corner set here wins.")
    page:Finish()
end

-- ---------------------------------------------------------------------------
-- stockpile

local function BuildStockpilePage(page)
    local sp = root.Stockpile
    local function db() return sp.db or sp.DEFAULTS end
    local function set(key) return function(v)
        if sp.db then sp.db[key] = v end
        if root.VendorCoin then root.VendorCoin.Refresh() end
    end end

    Section(page, "Hold for later")
    ToggleRow(page, "Raid preset", "Flask herbs, top enchanting mats, rare bars and essences. Raids open Dec 9.",
        function() return db().preset end, set("preset"))
    ToggleRow(page, "Cheap hint in tooltips", "Green line when today's AH price is far under the days before.",
        function() return db().tooltip end, set("tooltip"))
    SliderRow(page, "Cheap below", "Share of the average of the last 7 days. Also the snipe price without a target.",
        30, 95, 5, function() return db().cheapPct end, set("cheapPct"), function(v) return v .. " %" end)
    ToggleRow(page, "Snipe alerts", "After each Auctionator scan: held items at or under their snipe price in chat.",
        function() return db().alerts end, set("alerts"))
    ToggleRow(page, "Old price warning", "Tooltip and AH chat say so when prices are a day old or more.",
        function() return db().stale end, set("stale"))

    Section(page, "Add an item")
    local addRow = Row(page, "", nil, 40)
    local input
    local function add(text)
        local id = sp.ItemID(strtrim(text or ""))
        if not id then
            Say("Shift-click an item into the field, or type its item ID.")
            return
        end
        if not sp.IsHeld(id) then sp.Toggle(id) end
        input:SetText("")
        input:ClearFocus()
    end
    input = Input(addRow, 300, "Shift-click an item here, or its ID", add)
    input:SetPoint("LEFT", 8, 0)
    -- shift-clicked links land in the focused edit box
    if ChatEdit_InsertLink then
        hooksecurefunc("ChatEdit_InsertLink", function(link)
            if input:HasFocus() and link then input:SetText(link) end
        end)
    end
    local addButton = FlatButton(addRow, "Hold", 70, function() add(input:GetText()) end, true)
    addButton:SetPoint("LEFT", input, "RIGHT", 6, 0)
    ButtonBar(page, {
        { "Send to Auctionator", 170, function() sp.SyncAuctionator() end, true },
    })
    Note(page, "Bags: point at an item and press your key (Keybindings > AddOns). Target price: type it in the list below, 12.5 = 12g 50s. Auctionator list: |cff" .. ACCENT_HEX .. sp.LIST_NAME .. "|r.")

    local header = Section(page, "Held items")
    local listTop = page.y
    local rows = {}
    local function Money(c) return c and GetMoneyString(math.floor(c + 0.5), true) or "-" end

    local function GetRow(i)
        if rows[i] then return rows[i] end
        local row = CreateFrame("Frame", nil, page.body)
        row:SetHeight(30)
        Fill(row, { 0, 0, 0, i % 2 == 1 and 0.12 or 0.22 }):SetAllPoints()
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(20, 20)
        row.icon:SetPoint("LEFT", 8, 0)
        row.name = Text(row, 13)
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
        row.name:SetWidth(170)
        row.name:SetWordWrap(false)
        row.name:SetJustifyH("LEFT")
        row.del = FlatButton(row, "X", 26, function()
            if row.id then sp.Toggle(row.id) end
        end)
        row.del:SetHeight(22)
        row.del:SetPoint("RIGHT", -8, 0)
        row.target = Input(row, 70, "target", function(text)
            if row.id then sp.SetTarget(row.id, sp.ParseMoney(text)) end
            row.target:ClearFocus()
        end)
        row.target:SetHeight(22)
        row.target:SetPoint("RIGHT", row.del, "LEFT", -6, 0)
        row.prices = Text(row, 11, T.muted)
        row.prices:SetPoint("LEFT", row.name, "RIGHT", 8, 0)
        row.prices:SetPoint("RIGHT", row.target, "LEFT", -8, 0)
        row.prices:SetJustifyH("RIGHT")
        row.prices:SetWordWrap(false)
        rows[i] = row
        return row
    end

    function page.RefreshList()
        if not sp.db then return end
        local ids = sp.HeldList()
        header:SetText(("HELD ITEMS  |cff%s%d|r"):format(ACCENT_HEX, #ids))
        for i, id in ipairs(ids) do
            local row = GetRow(i)
            row.id = id
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", PAD, listTop - (i - 1) * 32)
            row:SetPoint("TOPRIGHT", -PAD, listTop - (i - 1) * 32)
            local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)
            row.icon:SetTexture(icon or 134400)
            local quality = C_Item and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(id)
            local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
            row.name:SetText(sp.Name(id))
            if color then row.name:SetTextColor(color.r, color.g, color.b) else row.name:SetTextColor(1, 1, 1) end
            local cheap, now, avg = sp.IsCheap(id)
            local snipe = sp.SnipePrice(id)
            local age = sp.ItemAge(id)
            local text = (cheap and "|cff40ff60" or "") .. Money(now) .. (cheap and "|r" or "")
                .. "  |cff777777avg|r " .. Money(avg) .. "  |cff777777snipe|r " .. Money(snipe)
            if age and age >= 1 then text = text .. "  |cffff9933" .. age .. "d old|r" end
            row.prices:SetText(text)
            if not row.target:HasFocus() then
                local target = sp.Target(id)
                row.target:SetText(target and tostring(target / 10000) or "")
            end
            row:Show()
        end
        for i = #ids + 1, #rows do
            rows[i].id = nil
            rows[i]:Hide()
        end
        page.y = listTop - math.max(1, #ids) * 32
        page:Finish()
    end
    page.refreshers[#page.refreshers + 1] = page.RefreshList
    page:Finish()
end

-- ---------------------------------------------------------------------------
-- naowh tweaks

local function BuildNaowhPage(page)
    local nt = root.NaowhTweaks
    local function db() return nt.db or nt.DEFAULTS end
    Section(page, "Buffs & Consumables")
    ToggleRow(page, "Scrolls only in dungeons and raids", "Naowh's scroll reminder stays away in the open world. Food, flasks and elixirs keep Naowh's own rules.",
        function() return db().scrollsInstanceOnly end, function(v) nt.Set("scrollsInstanceOnly", v) end)
    ToggleRow(page, "Buff drinks only in dungeons and raids", "Kreeg's Stout, Rumsey Rum, Juju, Zanza and the other buff items stay away in the open world.",
        function() return db().drinksInstanceOnly end, function(v) nt.Set("drinksInstanceOnly", v) end)
    Section(page, "RestedXP")
    ToggleRow(page, "/rxp hide hides Naowh's guide window too", "With Naowh's RXP skin, /rxp hide left its list on screen. Now it goes and comes back with /rxp show.",
        function() return db().rxpHide end, function(v) nt.Set("rxpHide", v) end)
    local row = Row(page, "Naowh Forever", "Needs Naowh Forever: Combat with its Buffs & Consumables row.")
    local status = Text(row, 13, ACCENT, MONO ~= nil)
    status:SetPoint("RIGHT", -14, 0)
    status:SetJustifyH("RIGHT")
    page.refreshers[#page.refreshers + 1] = function()
        status:SetText(nt.HasNaowh() and "found" or "|cffff5050not loaded|r")
    end
    Note(page, "Takes effect at the next refresh of Naowh's row (moving, buffing or a zone change).")
    page:Finish()
end

-- ---------------------------------------------------------------------------
-- update merge: every row the same, OLD left, NEW right, the lit one counts

local PICK_W = 150
local KIND_TITLE = {
    yours = "You kept these on OLD last time",
    update = "Changed by the update",
}
local KIND_NOTE = {
    yours = "Your own settings from the last merge. They start on OLD.",
    update = "Not on your list. They start on NEW.",
}

local function PickButton(parent, onClick)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(PICK_W, 26)
    b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    local label = Text(b, 12)
    label:SetPoint("LEFT", 8, 0)
    label:SetPoint("RIGHT", -8, 0)
    label:SetJustifyH("CENTER")
    label:SetWordWrap(false)
    b.label = label
    local hover, on = false, false
    local function paint()
        if on then
            b:SetBackdropColor(ACCENT[1], ACCENT[2], ACCENT[3], hover and 0.50 or 0.38)
            b:SetBackdropBorderColor(ACCENT[1], ACCENT[2], ACCENT[3], 1)
            label:SetTextColor(1, 1, 1, 1)
        else
            b:SetBackdropColor(0.089, 0.080, 0.072, hover and 0.75 or 0.6)
            b:SetBackdropBorderColor(1, 1, 1, hover and 0.35 or 0.15)
            label:SetTextColor(1, 1, 1, hover and 0.75 or 0.45)
        end
    end
    function b:SetOn(v) on = v and true or false; paint() end
    b:SetScript("OnEnter", function(self)
        hover = true; paint()
        if self.details then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self.head or "", 1, 1, 1)
            for _, line in ipairs(self.details) do GameTooltip:AddLine(line, 0.8, 0.8, 0.8) end
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function() hover = false; paint(); GameTooltip:Hide() end)
    b:SetScript("OnClick", onClick)
    paint()
    return b
end

local function BuildMergePage(page)
    local um = root.UpdateMerge
    local realBody = page.body
    local holder

    local function Rebuild()
        if holder then holder:Hide() end
        holder = CreateFrame("Frame", nil, realBody)
        holder:SetPoint("TOPLEFT")
        holder:SetSize(realBody:GetWidth(), 1)
        page.body, page.y, page.refreshers = holder, -12, {}

        local phase = um.Phase()
        if phase == "review" then
            for _, src in ipairs(um.SOURCES) do
                local s = um.Rows(src.id)
                if s then
                    Section(page, ("%s  ·  Naowh %s  ·  %d settings"):format(src.label, tostring(s.version or "?"), #s.rows))
                    local head = CreateFrame("Frame", nil, holder)
                    head:SetPoint("TOPLEFT", PAD, page.y)
                    head:SetPoint("TOPRIGHT", -PAD, page.y)
                    head:SetHeight(20)
                    local newHead = Text(head, 12, ACCENT)
                    newHead:SetPoint("RIGHT", -12, 0)
                    newHead:SetWidth(PICK_W)
                    newHead:SetJustifyH("CENTER")
                    newHead:SetText("NEW  ·  after")
                    local oldHead = Text(head, 12, ACCENT)
                    oldHead:SetPoint("RIGHT", newHead, "LEFT", -8, 0)
                    oldHead:SetWidth(PICK_W)
                    oldHead:SetJustifyH("CENTER")
                    oldHead:SetText("OLD  ·  before")
                    page.y = page.y - 24

                    for _, kind in ipairs({ "yours", "update" }) do
                        local list = {}
                        for i, r in ipairs(s.rows) do if r.kind == kind then list[#list + 1] = i end end
                        if #list > 0 then
                            local sec = Section(page, KIND_TITLE[kind] .. "  (" .. #list .. ")")
                            sec:SetTextColor(1, 1, 1, 0.7)
                            local paints = {}
                            local bar = CreateFrame("Frame", nil, holder)
                            bar:SetPoint("TOPLEFT", PAD, page.y + 18)
                            bar:SetPoint("TOPRIGHT", -PAD, page.y + 18)
                            bar:SetHeight(18)
                            local allNew = FlatButton(bar, "All NEW", PICK_W, function()
                                um.SetAll(src.id, kind, "new"); for _, f in ipairs(paints) do f() end
                            end)
                            allNew:SetHeight(18)
                            allNew:SetPoint("RIGHT", -12, 0)
                            local allOld = FlatButton(bar, "All OLD", PICK_W, function()
                                um.SetAll(src.id, kind, "old"); for _, f in ipairs(paints) do f() end
                            end)
                            allOld:SetHeight(18)
                            allOld:SetPoint("RIGHT", allNew, "LEFT", -8, 0)
                            local note = Text(holder, 11, T.muted)
                            note:SetPoint("TOPLEFT", PAD + 2, page.y)
                            note:SetText(KIND_NOTE[kind])
                            page.y = page.y - 18

                            local lastGroup
                            for _, i in ipairs(list) do
                                local r = s.rows[i]
                                local group = um.Group(r.keys)
                                local row = Row(page, um.Label(r.keys), group ~= lastGroup and group or " ", 40)
                                lastGroup = group
                                row.name:SetPoint("RIGHT", row, "RIGHT", -(2 * PICK_W + 32), 0)
                                row.name:SetWordWrap(false)
                                local spells = r.keys[1] == "spells"
                                local newB, oldB
                                local function paint()
                                    oldB:SetOn(r.pick == "old")
                                    newB:SetOn(r.pick == "new")
                                end
                                newB = PickButton(row, function() um.SetPick(src.id, i, "new"); paint() end)
                                newB:SetPoint("RIGHT", -12, 0)
                                oldB = PickButton(row, function() um.SetPick(src.id, i, "old"); paint() end)
                                oldB:SetPoint("RIGHT", newB, "LEFT", -8, 0)
                                oldB.label:SetText(um.Value(r.old))
                                newB.label:SetText(um.Value(r.new))
                                oldB.head, newB.head = "OLD: " .. um.Label(r.keys), "NEW: " .. um.Label(r.keys)
                                oldB.details, newB.details = um.Details(r.old, spells), um.Details(r.new, spells)
                                if row.desc then row.desc:SetPoint("RIGHT", oldB, "LEFT", -12, 0) end
                                paint()
                                paints[#paints + 1] = paint
                            end
                        end
                    end
                end
            end
            ButtonBar(page, {
                { "Apply and reload", 170, function()
                    if InCombatLockdown() then Say("Not in combat."); return end
                    local ok, result = um.Apply()
                    if not ok then Say(result); return end
                    Say(("%d settings back to OLD, everything else stays NEW. Reloading."):format(result))
                    ReloadUI()
                end, true },
                { "Keep all NEW", 140, function()
                    um.Cancel()
                    Say("Everything stays as the update set it.")
                    Rebuild()
                end },
            })
        else
            Section(page, "Status")
            local installed, imported = um.InstalledVersion(), um.ImportedVersion()
            local row = Row(page, "NaowhUI", "Installed add-on and the version in your profiles.")
            local v = Text(row, 12, ACCENT, MONO ~= nil)
            v:SetPoint("RIGHT", -14, 0)
            v:SetJustifyH("RIGHT")
            v:SetText(("%s  /  %s"):format(tostring(installed or "-"), tostring(imported or "-")))
            local state = Row(page, "Update", nil)
            local st = Text(state, 12, ACCENT, MONO ~= nil)
            st:SetPoint("RIGHT", -14, 0)
            st:SetJustifyH("RIGHT")
            if phase == "snapped" then
                local done, total = um.Status()
                st:SetText(("snapshot saved, %d of %d profiles imported"):format(done or 0, total or 0))
                ButtonBar(page, {
                    { "Open NaowhUI", 140, function() um.Watch(); if NaowhUI_AddonCompartmentFunc then NaowhUI_AddonCompartmentFunc() end end, true },
                    { "Cancel merge", 140, function() um.Cancel(); Say("Merge cancelled, snapshot deleted."); Rebuild() end },
                })
            elseif um.UpdateWaiting() then
                st:SetText("|cffffcc00new version waiting|r")
                ButtonBar(page, {
                    { "Snapshot + NaowhUI", 170, function() um.SnapAndInstall(); Rebuild() end, true },
                })
            else
                st:SetText("up to date")
            end
            local kept = 0
            for _, list in pairs(um.db and um.db.keep or {}) do for _ in pairs(list) do kept = kept + 1 end end
            local k = Row(page, "Your kept settings", "Start on OLD at the next update.")
            local kt = Text(k, 12, ACCENT, MONO ~= nil)
            kt:SetPoint("RIGHT", -14, 0)
            kt:SetJustifyH("RIGHT")
            kt:SetText(tostring(kept))
            Note(page, "Nothing runs until NaowhUI is newer than your profiles. Then: snapshot, import in NaowhUI, reload, " ..
                "and here every changed setting with OLD (before) left and NEW (after) right.")
        end
        page:Finish()
    end

    page.Rebuild = Rebuild
    page:SetScript("OnShow", function() Rebuild() end)
    Rebuild()
end

-- ---------------------------------------------------------------------------
-- commands

local COMMANDS = {
    { "/mu", "open this window" },
    { "/mu t", "flag / unflag your target (works in a macro)" },
}

local function BuildHelpPage(page)
    Section(page, "Slash commands")
    for _, c in ipairs(COMMANDS) do
        local row = Row(page, c[2], nil, 28)
        row.name:ClearAllPoints()
        row.name:SetPoint("LEFT", 180, 0)
        local cmd = Text(row, 12, ACCENT, MONO ~= nil)
        cmd:SetPoint("LEFT", 12, 0)
        cmd:SetText(c[1])
    end
    Note(page, "Everything else is in this window or under Keybindings > AddOns. Every setting is account-wide.")
    page:Finish()
end

-- ---------------------------------------------------------------------------
-- hub window

-- ---------------------------------------------------------------------------
-- LayerSwap host

local function BuildLayerPage(page)
    local lh = root.LayerHost
    local function db() return lh.db or lh.DEFAULTS end
    Section(page, "Host")
    ToggleRow(page, "Host off after login", "LayerSwap turns Host on at every login. This turns it off at your first click, unless you turned it on yourself.",
        function() return db().enabled end, function(v) lh.Set("enabled", v) end)
    local function StatusRow(label, desc, get)
        local row = Row(page, label, desc)
        local t = Text(row, 12, ACCENT, MONO ~= nil)
        t:SetPoint("RIGHT", -14, 0)
        t:SetJustifyH("RIGHT")
        page.refreshers[#page.refreshers + 1] = function() t:SetText(get()) end
    end
    Section(page, "Status")
    StatusRow("LayerSwap", nil, function() return lh.Present() and "found" or "|cffff5050not loaded|r" end)
    StatusRow("Host now", "After a swap of yours LayerSwap keeps it on 4 min, then off by itself.", function()
        if not lh.Present() then return "-" end
        local left = lh.LockLeft()
        if lh.Hosting() and left > 0 then return ("on, %d:%02d after your swap"):format(math.floor(left / 60), left % 60) end
        return lh.Hosting() and "on" or "off"
    end)
    StatusRow("At the next login", "What you leave it at when you log out.", function()
        if not db().enabled then return "LayerSwap decides (on)" end
        return db().wantHost and "on (you turned it on)" or "off"
    end)
    Note(page, "Turn Host on in LayerSwap (button, /ls host) and it stays on, also after the next login, until you turn it off there.")
    page:Finish()
end

-- ---------------------------------------------------------------------------
-- home: every module with its switch; a change needs a reload

local function BuildHomePage(page)
    Section(page, "Modules")
    local changed = {}
    local reloadRow
    local function update()
        local any = next(changed) ~= nil
        if reloadRow then reloadRow:SetShown(any) end
    end
    for _, m in ipairs(root.MODULES) do
        local key = m.key
        local start = not root.IsOff(key)
        local unavailable = (key == "CombatText" or key == "FlagPlates") and not root[key]
        local row = ToggleRow(page, m.label, unavailable and "Off while its standalone addon is enabled." or m.desc,
            function() return not root.IsOff(key) end,
            function(v)
                root.SetModule(key, v)
                if v == start then changed[key] = nil else changed[key] = true end
                update()
            end)
        if unavailable then row.name:SetTextColor(1, 1, 1, 0.4) end
    end
    page.y = page.y - 6
    reloadRow = Row(page, "|cffffcc00Changes start after a reload.|r", nil, 34)
    local reload = FlatButton(reloadRow, "Reload now", 130, function() ReloadUI() end, true)
    reload:SetPoint("RIGHT", -12, 0)
    reloadRow:Hide()
    Note(page, "A module that is off does not start at all: no events, no hooks, no memory. Its settings stay saved.")
    BuildHelpPage(page)   -- the slash commands below the switches
end

local TABS = {
    { key = "home", label = "Home", sub = "Modules on or off, and every slash command.",
        icon = "Interface\\Icons\\Ability_Druid_CatForm", build = BuildHomePage },
    { group = "COMBAT" },
    { key = "text", label = "Combat text", sub = "Damage, heals, buffs and debuffs on you: boxes, font, timing.",
        icon = "Interface\\Icons\\Spell_Fire_FlameBolt", module = "CombatText", build = BuildTextPage },
    { key = "events", label = "Events & colors", sub = "What shows up, and in which color.",
        icon = "Interface\\Icons\\INV_Misc_Gem_Variety_01", module = "CombatText", build = BuildEventsPage },
    { key = "shift", label = "Powershift", sub = "Form to form in one key press, without the action bar bug.",
        icon = "Interface\\Icons\\Ability_Druid_CatForm", module = "Powershift", build = BuildShiftPage },
    { group = "PLAYERS & GROUP" },
    { key = "players", label = "Flagged players", sub = "Everyone on this list gets marked nameplates, alerts and statistics.",
        icon = "Interface\\Icons\\Ability_Hunter_SniperShot", module = "FlagPlates", build = BuildPlayersPage },
    { key = "alerts", label = "Plates & alerts", sub = "Plate color, sound, chat message and statistics.",
        icon = "Interface\\Icons\\Spell_Holy_SealOfWisdom", module = "FlagPlates", build = BuildAlertsPage },
    { key = "marks", label = "Auto mark", sub = "Raid marks on your own group, nobody else in it.",
        icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1", module = "AutoMark", build = BuildMarksPage },
    { group = "BAGS & GOLD" },
    { key = "vendor", label = "Vendor coin", sub = "Red coin on items the vendor pays more for than the AH.",
        icon = "Interface\\Icons\\INV_Misc_Coin_04", module = "VendorCoin", build = BuildVendorPage },
    { key = "stockpile", label = "Stockpile", sub = "Keep raid materials for later, see cheap prices, snipe them.",
        icon = "Interface\\Icons\\INV_Relics_Hourglass", module = "VendorCoin", build = BuildStockpilePage },
    { group = "NAOWH" },
    { key = "naowh", label = "Naowh tweaks", sub = "Small changes to Naowh Forever, without touching its files.",
        icon = "Interface\\Icons\\INV_Scroll_03", module = "NaowhTweaks", build = BuildNaowhPage },
    { key = "merge", label = "Update merge", sub = "After a Naowh update: OLD or NEW for every setting that changed.",
        icon = "Interface\\Icons\\INV_Misc_Book_09", module = "UpdateMerge", build = BuildMergePage },
    { group = "WORLD & CHAT" },
    { key = "layer", label = "LayerSwap host", sub = "Host off by default, on only when you turn it on.",
        icon = "Interface\\Icons\\Spell_Arcane_PortalDalaran", module = "LayerHost", build = BuildLayerPage },
    { key = "weather", label = "Weather", sub = "One click: storms low. Next click: your old weather back.",
        icon = "Interface\\Icons\\Spell_Frost_IceStorm", module = "Weather", build = BuildWeatherPage },
    { key = "quiet", label = "Login quiet", sub = "No addon spam in the chat after login or /reload.",
        icon = "Interface\\Icons\\INV_Misc_Note_02", module = "LoginQuiet", build = BuildQuietPage },
}

local hub, current
local tabButtons, pages = {}, {}

local function SelectTab(key)
    if not pages[key] then key = "home" end
    current = key
    for _, tab in ipairs(TABS) do
        if tab.key then
            local b, on = tabButtons[tab.key], tab.key == key
            b.marker:SetShown(on)
            b.fill:SetShown(on)
            b.label:SetTextColor(1, 1, 1, on and 1 or 0.6)
            b.icon:SetAlpha(on and 1 or 0.6)
            pages[tab.key]:SetShown(on)
        end
    end
end

local function BuildHub()
    local f = CreateFrame("Frame", "MirogaUtilitiesPanel", UIParent, "BackdropTemplate")
    f:SetSize(WINDOW_W, WINDOW_H)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    f:SetBackdropColor(T.bg[1], T.bg[2], T.bg[3], 0.97)
    f:SetBackdropBorderColor(0, 0, 0, 1)
    tinsert(UISpecialFrames, "MirogaUtilitiesPanel")

    local side = CreateFrame("Frame", nil, f)
    side:SetPoint("TOPLEFT", 1, -1)
    side:SetPoint("BOTTOMLEFT", 1, 1)
    side:SetWidth(SIDEBAR_W)
    Fill(side, T.panel):SetAllPoints()
    local sideLine = Fill(side, T.line, "ARTWORK")
    sideLine:SetPoint("TOPRIGHT")
    sideLine:SetPoint("BOTTOMRIGHT")
    sideLine:SetWidth(1)

    local logo = side:CreateTexture(nil, "ARTWORK")
    logo:SetSize(30, 30)
    logo:SetPoint("TOPLEFT", 18, -18)
    logo:SetTexture("Interface\\Icons\\Ability_Druid_CatForm")
    logo:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local brand = Text(side, 16)
    brand:SetPoint("TOPLEFT", logo, "TOPRIGHT", 10, -1)
    brand:SetText("|cff" .. ACCENT_HEX .. "Miroga|r Utilities")
    local version = Text(side, 10, T.muted)
    version:SetPoint("TOPLEFT", brand, "BOTTOMLEFT", 0, -3)
    version:SetText("v" .. (C_AddOns.GetAddOnMetadata("MirogaUtilities", "Version") or "?"))
    local brandLine = Fill(side, T.line, "ARTWORK")
    brandLine:SetPoint("TOPLEFT", 0, -66)
    brandLine:SetPoint("TOPRIGHT", -1, -66)
    brandLine:SetHeight(1)

    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", side, "TOPRIGHT")
    content:SetPoint("BOTTOMRIGHT", -1, 1)

    local close = CreateFrame("Button", nil, f)
    close:SetSize(28, 28)
    close:SetPoint("TOPRIGHT", -10, -10)
    close:SetFrameLevel(f:GetFrameLevel() + 20)
    local x = Text(close, 16, { 1, 1, 1, 0.5 })
    x:SetPoint("CENTER")
    x:SetText("X")
    close:SetScript("OnEnter", function() x:SetTextColor(1, 1, 1, 1) end)
    close:SetScript("OnLeave", function() x:SetTextColor(1, 1, 1, 0.5) end)
    close:SetScript("OnClick", function() f:Hide() end)

    local y = -78
    for _, tab in ipairs(TABS) do
        if tab.group then
            if y < -78 then y = y - 8 end
            local g = Text(side, 10, { 1, 1, 1, 0.4 })
            g:SetPoint("TOPLEFT", 20, y)
            g:SetText(tab.group)
            y = y - 17
        else
            local b = CreateFrame("Button", nil, side)
            b:SetPoint("TOPLEFT", 8, y)
            b:SetPoint("TOPRIGHT", -9, y)
            b:SetHeight(27)
            y = y - 29
            b.fill = Fill(b, { ACCENT[1], ACCENT[2], ACCENT[3], 0.16 })
            b.fill:SetAllPoints()
            b.marker = Fill(b, { ACCENT[1], ACCENT[2], ACCENT[3], 1 }, "ARTWORK")
            b.marker:SetPoint("TOPLEFT")
            b.marker:SetPoint("BOTTOMLEFT")
            b.marker:SetWidth(3)
            local hl = b:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, 0.04)
            b.icon = b:CreateTexture(nil, "ARTWORK")
            b.icon:SetSize(18, 18)
            b.icon:SetPoint("LEFT", 14, 0)
            b.icon:SetTexture(tab.icon)
            b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            b.label = Text(b, 13)
            b.label:SetPoint("LEFT", b.icon, "RIGHT", 10, 0)
            b.label:SetText(tab.label)
            tabButtons[tab.key] = b

            local page = NewPage(content, tab.label, tab.sub)
            pages[tab.key] = page
            if tab.module and (not root[tab.module] or (root.Stopped and root.Stopped(tab.module))) then
                b.icon:SetDesaturated(true)
                b.label:SetAlpha(0.45)
                Note(page, "This module is off. Turn it on under Home, then reload.")
                page:Finish()
            else
                local ok, err = pcall(tab.build, page)
                if not ok then
                    Note(page, "|cffff6666This page failed to build:|r " .. tostring(err))
                    page:Finish()
                end
            end
            b:SetScript("OnClick", function() SelectTab(tab.key) end)
        end
    end

    local hint = Text(side, 11, T.muted, MONO ~= nil)
    hint:SetPoint("BOTTOMLEFT", 20, 14)
    hint:SetText("/mu  ·  /mu t")
    return f
end

local function OpenHub(key)
    hub = hub or BuildHub()
    SelectTab(key or current or "home")
    hub:Show()
end
root.OpenHub = OpenHub

function root.ToggleHub()
    if hub and hub:IsShown() then hub:Hide() else OpenHub() end
end

function MirogaUtilities_OnCompartmentClick()
    root.ToggleHub()
end

-- the modules' own entry points now open their hub pages
if root.CombatText then
    root.CombatText.OpenOptions = function() OpenHub("text") end
end
if root.FlagPlates then
    local fp = root.FlagPlates
    fp.ToggleUI = function()
        if hub and hub:IsShown() and current == "players" then hub:Hide() else OpenHub("players") end
    end
    -- list changes (add, remove, stats) refresh the open players page
    fp.RefreshUI = function()
        local page = pages.players
        if page and page:IsVisible() and page.RefreshList then page.RefreshList() end
    end
end

-- a scan, a measured deposit or a hold change updates the open pages
local function RefreshShopPages()
    for _, key in ipairs({ "vendor", "stockpile" }) do
        local page = pages[key]
        if page and page:IsVisible() then page:Refresh() end
    end
end
if root.VendorCoin then root.VendorCoin.OnChange = RefreshShopPages end
if root.Stockpile then root.Stockpile.OnChange = RefreshShopPages end

-- a key press updates the open weather page
if root.Weather then
    root.Weather.OnChange = function()
        local page = pages.weather
        if page and page:IsVisible() then page:Refresh() end
    end
end

-- Esc > Options > AddOns: one entry that opens this window
if Settings and Settings.RegisterCanvasLayoutCategory then
    local stub = CreateFrame("Frame")
    local title = Text(stub, 20)
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("|cff" .. ACCENT_HEX .. "Miroga|r Utilities")
    local note = Text(stub, 12, T.muted)
    note:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    note:SetText("All settings live in one window: /mu")
    local open = FlatButton(stub, "Open Miroga Utilities", 180, function()
        if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
        OpenHub()
    end, true)
    open:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -16)
    local category = Settings.RegisterCanvasLayoutCategory(stub, "Miroga Utilities")
    Settings.RegisterAddOnCategory(category)
end
