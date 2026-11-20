-- Mail helper: the send tab fills in the other character of a pair as the
-- recipient (Miroga <-> Aandy, the bank), and every mail gets a subject.
--
-- Subject: Blizzard's SendMailFrame_Update names the mail after the first
-- attachment, but in the Forever client only inside
-- "if itemCount > 0 and C_Mail.IsCODEnabled()". Forever has C.O.D. off, so
-- the subject stays empty and Send stays grey. A hook after
-- SendMailFrame_CanSend (which runs after every attachment, money or text
-- change) does the same naming: "Item (20)", or the gold amount for a
-- money-only mail. A subject you typed yourself is never replaced.
local _, root = ...
local mh = {}
root.MailHelper = mh

mh.DEFAULTS = { recipient = true, subject = true, money = true, a = "Miroga Tegridy", b = "Aandy Bank" }
mh.auto = nil       -- the subject we wrote last; anything else came from you
mh.filled = 0       -- recipients filled this session (hub status)

local function Lower(s) return type(s) == "string" and strlower(strtrim(s)) or "" end
local function First(s) return (Lower(s):match("^(%S+)")) or "" end

-- the pair partner of `me`, or nil when `me` is in no pair
function mh.Partner(me, a, b)
    me, a, b = Lower(me), strtrim(a or ""), strtrim(b or "")
    if me == "" or a == "" or b == "" then return nil end
    if me == Lower(a) then return b end
    if me == Lower(b) then return a end
    -- UnitName may come without the surname, the setting with it (or the other way)
    if First(me) == First(a) then return b end
    if First(me) == First(b) then return a end
end

function mh.MyName()
    local name = UnitName and UnitName("player")
    if issecretvalue and issecretvalue(name) then return nil end
    return name
end

function mh.FillRecipient()
    local db = mh.db
    if not (db and db.recipient) or not SendMailNameEditBox then return end
    if SendMailNameEditBox:GetText() ~= "" then return end
    local other = mh.Partner(mh.MyName(), db.a, db.b)
    if not other then return end
    SendMailNameEditBox:SetText(other)
    SendMailNameEditBox:SetCursorPosition(#other)
    mh.filled = mh.filled + 1
    -- straight on to the attachments, not into the name box
    if SendMailNameEditBox:HasFocus() then SendMailNameEditBox:ClearFocus() end
end

-- "12g 3s 50c" for a money-only mail
function mh.MoneyText(copper)
    local g, s, c = floor(copper / 10000), floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. "g" end
    if s > 0 then parts[#parts + 1] = s .. "s" end
    if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "c" end
    return table.concat(parts, " ")
end

-- what the subject should be right now: first attachment, else money, else ""
function mh.WantedSubject()
    for i = 1, ATTACHMENTS_MAX_SEND or 12 do
        if HasSendMailItem(i) then
            local name, _, _, count = GetSendMailItem(i)
            if type(name) == "string" and name ~= "" then
                if (count or 1) > 1 then return name .. " (" .. count .. ")" end
                return name
            end
        end
    end
    if mh.db.money and SendMailMoney and MoneyInputFrame_GetCopper then
        local copper = MoneyInputFrame_GetCopper(SendMailMoney) or 0
        if copper > 0 then return mh.MoneyText(copper) end
    end
    return ""
end

local busy = false
function mh.UpdateSubject()
    local db = mh.db
    if busy or not (db and db.subject) or not SendMailSubjectEditBox then return end
    local current = SendMailSubjectEditBox:GetText()
    if current ~= "" and current ~= mh.auto then return end   -- yours, keep it
    local wanted = mh.WantedSubject()
    if wanted == current then mh.auto = wanted ~= "" and wanted or nil; return end
    busy = true
    SendMailSubjectEditBox:SetText(wanted)   -- OnTextChanged runs CanSend again: Send lights up
    busy = false
    mh.auto = wanted ~= "" and wanted or nil
end

function mh.Hook()
    if mh.hooked or not SendMailFrame_CanSend then return false end
    hooksecurefunc("SendMailFrame_CanSend", mh.UpdateSubject)
    -- send tab opened (a reply writes the sender in afterwards, so replies stay replies)
    if SendMailFrame then SendMailFrame:HookScript("OnShow", mh.FillRecipient) end
    -- after a sent mail the form is emptied: same partner again
    hooksecurefunc("SendMailFrame_Reset", function()
        mh.auto = nil
        if SendMailFrame and SendMailFrame:IsShown() then mh.FillRecipient() end
    end)
    mh.hooked = true
    return true
end

function mh.Set(key, value)
    if not mh.db then return end
    if key == "a" or key == "b" then mh.db[key] = strtrim(value or "") else mh.db[key] = value and true or false end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, name)
    if name == "MirogaUtilities" then
        if root.Off("MailHelper", self) then return end
        if type(MirogaUtilitiesDB) ~= "table" then MirogaUtilitiesDB = {} end
        MirogaUtilitiesDB.mail = MirogaUtilitiesDB.mail or {}
        mh.db = MirogaUtilitiesDB.mail
        for key, value in pairs(mh.DEFAULTS) do
            if mh.db[key] == nil then mh.db[key] = value end
        end
    end
    -- Blizzard_MailFrame may load on demand
    if mh.db and mh.Hook() then self:UnregisterEvent("ADDON_LOADED") end
end)
