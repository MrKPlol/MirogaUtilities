-- Login quiet: hides the addon chatter after a login or /reload.
--
-- Two ways, both made for addons (no hooks on Blizzard's chat frames):
-- * print() goes through setprinthandler, swapped for the quiet window.
-- * Lines added straight to a chat frame are swept out afterwards with the
--   frames' secure RemoveMessagesByPredicate. Addon lines carry no chat
--   data behind the color; real chat and system messages always do, so
--   they stay. Secret texts are never touched.
--
-- Hidden lines are kept for this session: /mu > Login quiet prints them.
local _, root = ...
local lq = {}
root.LoginQuiet = lq

lq.DEFAULTS = { enabled = true, seconds = 10 }
lq.hidden = {}

local issecret = issecretvalue or function() return false end
local SWEEPS = { 0.5, 1.5, 3, 5, 7.5 } -- plus one at the end of the window

local active, originalPrint = false, nil

local function Remember(text)
    if type(text) == "string" and not issecret(text) and text:find("%S") then
        lq.hidden[#lq.hidden + 1] = text
    end
end

-- true for lines without chat data: those come from addons
local function IsAddonLine(message, r, g, b, ...)
    if select("#", ...) > 0 then return false end
    if issecret(message) then return false end
    Remember(message)
    return true
end

local function Sweep()
    for i = 1, NUM_CHAT_WINDOWS or 10 do
        local frame = _G["ChatFrame" .. i]
        if frame and frame.RemoveMessagesByPredicate then
            pcall(frame.RemoveMessagesByPredicate, frame, IsAddonLine)
        end
    end
end

local function QuietPrint(...)
    local ok, text = pcall(string.join, " ", tostringall(...))
    if ok then Remember(text) end
end

local function Stop()
    if not active then return end
    active = false
    Sweep()
    if originalPrint and getprinthandler() == QuietPrint then
        setprinthandler(originalPrint)
    end
    originalPrint = nil
    if #lq.hidden > 0 then
        root.Say(("%d login lines hidden. |cff%s/mu|r > Login quiet shows them."):format(#lq.hidden, root.ACCENT_HEX))
    end
end

-- from loading on: swallow print() and wait for entering the world
local function Start()
    if active or not (lq.db and lq.db.enabled) then return end
    active = true
    if getprinthandler and setprinthandler then
        originalPrint = getprinthandler()
        setprinthandler(QuietPrint)
    end
end

-- the clock runs from entering the world, loading screens take long
local function Schedule()
    if not active then return end
    local seconds = lq.db.seconds
    for _, t in ipairs(SWEEPS) do
        if t < seconds then C_Timer.After(t, Sweep) end
    end
    C_Timer.After(seconds, Stop)
end

-- prints the hidden lines of this session
function lq.Show()
    if #lq.hidden == 0 then
        root.Say("No login lines hidden this session.")
        return
    end
    root.Say(("Hidden after login (%d):"):format(#lq.hidden))
    local out = DEFAULT_CHAT_FRAME
    for _, text in ipairs(lq.hidden) do
        out:AddMessage("|cff888888>|r " .. text)
    end
end

function lq.SetEnabled(value)
    if lq.db then lq.db.enabled = value end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, arg1, arg2)
    if event == "ADDON_LOADED" then
        if arg1 ~= "MirogaUtilities" then return end
        self:UnregisterEvent("ADDON_LOADED")
        if root.Off("LoginQuiet", self) then return end
        if type(MirogaUtilitiesDB) ~= "table" then MirogaUtilitiesDB = {} end
        MirogaUtilitiesDB.loginQuiet = MirogaUtilitiesDB.loginQuiet or {}
        local db = MirogaUtilitiesDB.loginQuiet
        for key, value in pairs(lq.DEFAULTS) do
            if db[key] == nil then db[key] = value end
        end
        lq.db = db
        -- addons that load after this one print during the rest of loading
        Start()
        self:RegisterEvent("PLAYER_ENTERING_WORLD")
        return
    end
    -- PLAYER_ENTERING_WORLD (isInitialLogin, isReloadingUi): only once
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    Schedule()
end)
