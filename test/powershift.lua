-- luajit test/powershift.lua  (run from repo root)
local checks, fails = 0, 0
local function ok(c, m) checks = checks + 1; if not c then fails = fails + 1; print("FAIL: " .. m) end end
local frames, combat, forms = {}, false, { 5487, 16, 768 }
local function NewFrame(name)
    local f = { attrs = {}, events = {} }
    function f:SetAttribute(k, v) if combat then error("protected") end self.attrs[k] = v end
    function f:RegisterForClicks(...) self.clicks = { ... } end
    function f:RegisterEvent(e) self.events[e] = true end
    function f:UnregisterEvent(e) self.events[e] = nil end
    function f:SetScript(k, fn) self[k] = fn end
    if name then frames[name] = f end
    return f
end
CreateFrame = function(_, name) return NewFrame(name) end
UIParent = {}
format = string.format
local driver
RegisterStateDriver = function(_, state, d) driver = d end
UnitClass = function() return "Druid", "DRUID" end
InCombatLockdown = function() return combat end
GetNumShapeshiftForms = function() return #forms end
GetShapeshiftFormInfo = function(i) return "icon", false, true, forms[i] end
local watcher
local real = CreateFrame
CreateFrame = function(t, n, ...) local f = real(t, n); if not n then watcher = f end; return f end
assert(loadfile("MirogaUtilities/Modules/Powershift.lua"))("MirogaUtilities", {})
local cat, bear = frames.MirogaShiftCat, frames.MirogaShiftBear
for _, b in ipairs({ cat, bear }) do
    ok(b.attrs.pressAndHoldAction == true, "hold action")
    ok(b.attrs.type == "macro" and b.attrs.macrotext == "/cancelform", "down cancels")
    ok(b.attrs.typerelease == "spell", "up casts")
    ok(b.clicks[1] == "AnyDown" and b.clicks[2] == "AnyUp", "both edges")
end
ok(cat.attrs.spell == 768, "cat id"); ok(bear.attrs.spell == 5487, "bear id")
forms[1] = 9634; combat = true; watcher.OnEvent(watcher, "UPDATE_SHAPESHIFT_FORMS")
ok(bear.attrs.spell == 5487 and watcher.events.PLAYER_REGEN_ENABLED, "defers in combat")
combat = false; watcher.OnEvent(watcher, "PLAYER_REGEN_ENABLED")
ok(bear.attrs.spell == 9634 and not watcher.events.PLAYER_REGEN_ENABLED, "dire bear after combat")
ok(driver == "[swimming] none; none", "travel driver without travel forms")
forms[4] = 783; watcher.OnEvent(watcher, "SPELLS_CHANGED")
ok(driver == "[swimming] none; [form:4] off; [indoors] none; land", "travel driver with travel form: " .. tostring(driver))
print(checks .. " checks, " .. fails .. " failures"); os.exit(fails == 0 and 0 or 1)
