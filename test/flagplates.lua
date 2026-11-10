-- luajit test/test.lua  (run from repo root)
local fails, checks = 0, 0
local function ok(cond, msg)
    checks = checks + 1
    if not cond then fails = fails + 1; print("FAIL: " .. msg) end
end

---------------------------------------------------------------- mocks
local SECRET = setmetatable({}, { __tostring = function() return "<secret>" end,
    __eq = function() error("compare on secret") end })
function issecretvalue(v) return v == nil and false or rawequal(v, SECRET) end

local chat = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) chat[#chat + 1] = m end }
UNKNOWNOBJECT = "Unknown"; YES = "Yes"; NO = "No"
UISpecialFrames, StaticPopupDialogs, SlashCmdList = {}, {}, {}
function time() return 1 end
function GetTime() return 100 end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
tinsert = table.insert
C_Timer = { queue = {}, After = function(_, fn) table.insert(C_Timer.queue, fn) end }
local function flush() local q = C_Timer.queue; C_Timer.queue = {}; for _, f in ipairs(q) do f() end end

function hooksecurefunc(t, name, fn)
    local orig = t[name]
    t[name] = function(...) local r = { orig(...) }; fn(...); return unpack(r) end
end

local function Obj()
    local o = { col = { 1, 0, 0, 1 }, vcol = { 1, 1, 1, 1 } }
    function o:SetStatusBarColor(r, g, b, a) self.col = { r, g, b, a or 1 } end
    function o:GetStatusBarColor() return unpack(self.col) end
    function o:SetVertexColor(r, g, b, a) self.vcol = { r, g, b, a or 1 } end
    function o:GetVertexColor() return unpack(self.vcol) end
    function o:SetTextColor(r, g, b, a) self.col = { r, g, b, a or 1 } end
    function o:GetTextColor() return unpack(self.col) end
    function o:IsForbidden() return false end
    return o
end

-- generic frame for UI/boot
local frames = {}
local FrameMT = {}
FrameMT.__index = function(t, k)
    return function(self, ...)
        if k == "RegisterEvent" then self.events = self.events or {}; self.events[...] = true
        elseif k == "SetScript" then local n, f = ...; self.scripts = self.scripts or {}; self.scripts[n] = f
        elseif k == "IsShown" then return self.shown
        elseif k == "Show" then self.shown = true; if self.scripts and self.scripts.OnShow then self.scripts.OnShow(self) end
        elseif k == "Hide" then self.shown = false
        elseif k == "GetText" then return self.txt or ""
        elseif k == "SetText" then self.txt = ...
        elseif k == "GetChecked" then return self.checked
        elseif k == "CreateTexture" or k == "CreateFontString" then return setmetatable({}, FrameMT)
        elseif k == "GetParent" then return self.parent
        end
    end
end
function CreateFrame(_, name, parent)
    local f = setmetatable({ parent = parent, events = {}, scripts = {}, shown = false, txt = "", checked = false }, FrameMT)
    frames[#frames + 1] = f
    if name then _G[name] = f end
    return f
end
UIParent = CreateFrame("Frame")
GameTooltip = CreateFrame("Frame"); GameTooltip_Hide = function() end

-- units
local units = {}
function UnitExists(u) return units[u] ~= nil end
function UnitIsPlayer(u) return units[u] and units[u].player end
function UnitName(u) local x = units[u]; if x then return x.name, x.surname end end

-- nameplates: EUI plate, Plater frame, Blizzard frame per unit
local plates = {}
local function MakePlate(unit)
    local np = { unitToken = unit }
    function np:GetUnit() return self.unitToken end
    np.UnitFrame = { healthBar = Obj(), name = Obj(), IsForbidden = function() return false end }
    np.unitFramePlater = { healthBar = { barTexture = Obj(), unitName = Obj() } }
    local eui = { health = Obj(), name = Obj() }
    function eui:UpdateHealthColor() self.health:SetStatusBarColor(1, 0, 0) end
    function eui:UpdateName() self.name:SetTextColor(1, 1, 1) end
    plates[unit] = { np = np, eui = eui }
    return np, eui
end
_G.EllesmereNameplates_NS = { plates = setmetatable({}, { __index = function(_, u) return plates[u] and plates[u].eui end }) }
C_NamePlate = {
    GetNamePlateForUnit = function(u) return plates[u] and plates[u].np end,
    GetNamePlates = function() local t = {}; for _, p in pairs(plates) do t[#t + 1] = p.np end; return t end,
}
Plater = { RefreshNameplateColor = function(uf) uf.healthBar.barTexture:SetVertexColor(1, 0, 0) end }
Menu = { tags = {}, ModifyMenu = function(tag, cb) Menu.tags[tag] = cb end }
ColorPickerFrame = {}

---------------------------------------------------------------- load addon
local ns = {}
for _, f in ipairs({ "Core.lua", "Plates.lua", "UI.lua" }) do
    local chunk = assert(loadfile("MirogaUtilities/Modules/FlagPlates/" .. f))
    chunk("KPFlagPlates", { FlagPlates = ns })
end
-- fire ADDON_LOADED on boot frame
for _, fr in ipairs(frames) do
    if fr.scripts and fr.scripts.OnEvent and fr.events and fr.events.ADDON_LOADED then
        fr.scripts.OnEvent(fr, "ADDON_LOADED", "KPFlagPlates")
    end
end
local ev
for _, fr in ipairs(frames) do if fr.events and fr.events.NAME_PLATE_UNIT_ADDED then ev = fr end end
ok(ev, "event frame registered")
local function Fire(e, u) ev.scripts.OnEvent(ev, e, u) end
local TQ = { 0.25, 0.88, 0.82 }
local function isTQ(c) return math.abs(c[1] - TQ[1]) < 1e-6 and math.abs(c[2] - TQ[2]) < 1e-6 end

---------------------------------------------------------------- parse
local a, b = ns.ParseName("  Mirog  Banks ")
ok(a == "Mirog" and b == "Banks", "parse two parts")
a, b = ns.ParseName("Mirog-Banks"); ok(a == "Mirog" and b == "Banks", "parse hyphen")
a, b = ns.ParseName("Mirog"); ok(a == "Mirog" and b == nil, "parse one part")
ok(ns.ParseName("   ") == nil, "parse empty")

---------------------------------------------------------------- list
ok(ns.Add("Stephen", "Kinks"), "add exact")
ok(not ns.Add("stephen", "KINKS"), "dup case-insensitive")
ok(ns.Add("Moroga"), "add first only")
ok(ns.Lookup("Stephen", "Kinks"), "lookup exact")
ok(not ns.Lookup("Stephen", "Other"), "exact needs surname")
ok(ns.Lookup("Moroga", "Anything"), "first-only matches any surname")
ok(ns.Lookup("moroga", nil), "first-only no surname")

---------------------------------------------------------------- plates
units.nameplate1 = { player = true, name = "Stephen", surname = "Kinks" }
local np1, eui1 = MakePlate("nameplate1")
units.nameplate2 = { player = true, name = "Stranger", surname = "Danger" }
local np2, eui2 = MakePlate("nameplate2")
Fire("NAME_PLATE_UNIT_ADDED", "nameplate1"); Fire("NAME_PLATE_UNIT_ADDED", "nameplate2"); flush()

ok(isTQ(eui1.health.col), "EUI bar turquoise")
ok(isTQ(eui1.name.col), "EUI name turquoise")
ok(isTQ(np1.unitFramePlater.healthBar.barTexture.vcol), "Plater bar turquoise")
ok(isTQ(np1.unitFramePlater.healthBar.unitName.col), "Plater name turquoise")
ok(isTQ(np1.UnitFrame.healthBar.col), "Blizz bar turquoise")
ok(isTQ(np1.UnitFrame.name.col) and np1.UnitFrame.name.vcol[1] == 1, "Blizz name text tq + vertex white")
ok(not isTQ(eui2.health.col), "unflagged plate untouched")

-- owner repaints -> hook re-applies
eui1:UpdateHealthColor(); ok(isTQ(eui1.health.col), "EUI repaint overridden")
np1.unitFramePlater.healthBar.barTexture:SetVertexColor(0, 1, 0); ok(isTQ(np1.unitFramePlater.healthBar.barTexture.vcol), "Plater lerp overridden")
np1.UnitFrame.name:SetVertexColor(1, 0, 0); ok(np1.UnitFrame.name.vcol[1] == 1 and np1.UnitFrame.name.vcol[2] == 1, "Blizz name vertex held white")
eui2:UpdateHealthColor(); ok(eui2.health.col[1] == 1 and eui2.health.col[2] == 0, "unflagged repaint passes")

-- remove -> restore
ns.Remove(ns.Key("Stephen", "Kinks"))
ok(not isTQ(eui1.health.col), "EUI restored after remove")
ok(not isTQ(np1.UnitFrame.healthBar.col), "Blizz restored after remove")
eui1:UpdateHealthColor(); ok(not isTQ(eui1.health.col), "no override after remove")

-- target toggle
units.target = { player = true, name = "Stephen", surname = "Kinks" }
ns.ToggleTarget(); ok(ns.Lookup("Stephen", "Kinks"), "/fpt adds")
ok(isTQ(eui1.health.col), "re-flagged on add")
ns.ToggleTarget(); ok(not ns.Lookup("Stephen", "Kinks"), "/fpt again removes")
ns.ToggleTarget(); ok(ns.Lookup("Stephen", "Kinks"), "slash /fpt")

-- secret names never flagged, no error
units.nameplate3 = { player = true, name = SECRET, surname = SECRET }
local np3, eui3 = MakePlate("nameplate3")
Fire("NAME_PLATE_UNIT_ADDED", "nameplate3"); flush()
ok(not isTQ(eui3.health.col), "secret name not flagged")
units.target = { player = SECRET, name = "X" }
ns.ToggleTarget(); ok(chat[#chat]:find("hidden"), "secret target handled")

-- plate removed -> unit reuse by other player
Fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
units.nameplate1 = { player = true, name = "Nobody", surname = "X" }
Fire("NAME_PLATE_UNIT_ADDED", "nameplate1"); flush()
eui1:UpdateHealthColor(); ok(not isTQ(eui1.health.col), "pooled plate clean after reuse")

-- colour change + toggle bar off
ns.db.color = { r = 1, g = 0, b = 1 }
units.nameplate1 = { player = true, name = "Stephen", surname = "Kinks" }
Fire("NAME_PLATE_UNIT_ADDED", "nameplate1"); flush()
ok(eui1.health.col[1] == 1 and eui1.health.col[2] == 0 and eui1.health.col[3] == 1, "custom colour")
ns.db.colorBar = false; ns.RepaintAll()
ok(eui1.health.col[3] ~= 1 or eui1.health.col[1] ~= 1 or eui1.health.col[2] ~= 0, "bar off restores")
ok(eui1.name.col[3] == 1 and eui1.name.col[2] == 0, "name still coloured")

-- slash add/del/list, menu
ns.Slash("add Anna Bell"); ok(ns.Lookup("Anna", "Bell"), "/fp add")
ns.Slash("del anna bell"); ok(not ns.Lookup("Anna", "Bell"), "/fp del")
ns.Slash("list")
ok(Menu.tags.MENU_UNIT_PLAYER, "menu hooked")
local created = {}
local root = { CreateDivider = function() end, CreateButton = function(_, t, fn) created[#created + 1] = { t, fn } end }
units.party1 = { player = true, name = "Menu", surname = "Guy" }
Menu.tags.MENU_UNIT_PLAYER(nil, root, { unit = "party1" })
ok(created[1] and created[1][1]:find("Flag player"), "menu offers flag")
created[1][2](); ok(ns.Lookup("Menu", "Guy"), "menu flag adds")

-- UI build + refresh
ns.ToggleUI(); ok(KPFlagPlatesFrame and KPFlagPlatesFrame.shown, "UI opens")
ns.RefreshUI()
ns.ToggleUI(); ok(not KPFlagPlatesFrame.shown, "UI closes")

print(("%d checks, %d failed"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
