-- luajit test/mailhelper.lua  (run from repo root)
local n, bad = 0, 0
local function ok(c, m) n = n + 1; if not c then bad = bad + 1; print("FAIL " .. m) end end

function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
strlower, floor = string.lower, math.floor
local handler
function CreateFrame() return { RegisterEvent = function() end, UnregisterEvent = function() end,
    SetScript = function(_, _, fn) handler = fn end } end
local hooks = {}
function hooksecurefunc(name, fn) hooks[name] = fn end

local function Box(text)
    local b = { text = text or "", focus = false }
    function b:GetText() return self.text end
    function b:SetText(t) self.text = t; if self.onChange then self.onChange() end end
    function b:SetCursorPosition() end
    function b:HasFocus() return self.focus end
    function b:ClearFocus() self.focus = false end
    return b
end
SendMailNameEditBox, SendMailSubjectEditBox = Box(), Box()
local onShow
SendMailFrame = { IsShown = function() return true end, HookScript = function(_, _, fn) onShow = fn end }
local items, copper, me = {}, 0, "Miroga Tegridy"
ATTACHMENTS_MAX_SEND = 12
function HasSendMailItem(i) return items[i] ~= nil end
function GetSendMailItem(i) local it = items[i]; return it[1], 1, 1, it[2] end
SendMailMoney = {}
function MoneyInputFrame_GetCopper() return copper end
function UnitName() return me end
function SendMailFrame_CanSend() end
function SendMailFrame_Reset() end

local root = { Off = function() return false end }
assert(loadfile("MirogaUtilities/Modules/MailHelper.lua"))("MirogaUtilities", root)
local mh = root.MailHelper
handler({ UnregisterEvent = function() end }, "ADDON_LOADED", "MirogaUtilities")
ok(mh.hooked and hooks.SendMailFrame_CanSend and onShow, "hooked")
local CanSend = hooks.SendMailFrame_CanSend
SendMailSubjectEditBox.onChange = CanSend   -- like the XML OnTextChanged

-- partner
ok(mh.Partner("Miroga Tegridy", "Miroga Tegridy", "Aandy Bank") == "Aandy Bank", "miroga -> aandy")
ok(mh.Partner("aandy bank", "Miroga Tegridy", "Aandy Bank") == "Miroga Tegridy", "aandy -> miroga")
ok(mh.Partner("Aandy", "Miroga Tegridy", "Aandy Bank") == "Miroga Tegridy", "first name only")
ok(mh.Partner("Moroga Tegridy", "Miroga Tegridy", "Aandy Bank") == nil, "alt not in pair")

-- recipient
onShow()
ok(SendMailNameEditBox.text == "Aandy Bank", "recipient filled")
SendMailNameEditBox.text = "Someone"; onShow()
ok(SendMailNameEditBox.text == "Someone", "typed recipient kept")
SendMailNameEditBox.text = ""; me = "Moroga Tegridy"; onShow()
ok(SendMailNameEditBox.text == "", "alt gets nothing")
me = "Aandy Bank"; hooks.SendMailFrame_Reset()
ok(SendMailNameEditBox.text == "Miroga Tegridy", "after send: refilled")

-- subject
items[1] = { "Linen Cloth", 20 }; CanSend()
ok(SendMailSubjectEditBox.text == "Linen Cloth (20)", "item subject")
items[1] = nil; items[3] = { "Copper Ore", 1 }; CanSend()
ok(SendMailSubjectEditBox.text == "Copper Ore", "follows first item")
items[3] = nil; CanSend()
ok(SendMailSubjectEditBox.text == "", "cleared when empty")
copper = 125050; CanSend()
ok(SendMailSubjectEditBox.text == "12g 50s 50c", "money subject")
copper = 0; SendMailSubjectEditBox.text = "for you"; items[1] = { "Linen Cloth", 5 }; CanSend()
ok(SendMailSubjectEditBox.text == "for you", "typed subject kept")
ok(mh.MoneyText(5) == "5c" and mh.MoneyText(10000) == "1g", "money text")
mh.Set("subject", false); SendMailSubjectEditBox.text = ""; CanSend()
ok(SendMailSubjectEditBox.text == "", "subject off")

print(("mailhelper: %d/%d ok"):format(n - bad, n))
os.exit(bad == 0 and 0 or 1)
