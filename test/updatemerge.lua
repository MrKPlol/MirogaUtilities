-- luajit test/updatemerge.lua  (run from repo root)
local n, bad = 0, 0
local function ok(c, m) n = n + 1; if not c then bad = bad + 1; print("FAIL " .. m) end end

-- mocks -----------------------------------------------------------------------
local handlers, timers, tickers, popups, said = {}, {}, {}, {}, {}
function CreateFrame()
    local f = {}
    function f:RegisterEvent() end
    function f:SetScript(_, fn) handlers[#handlers + 1] = fn end
    return f
end
C_Timer = {
    After = function(_, fn) timers[#timers + 1] = fn end,
    NewTicker = function(_, fn)
        local t = { fn = fn }
        function t:Cancel() self.off = true end
        tickers[#tickers + 1] = t
        return t
    end,
}
local function tick() for _, t in ipairs(tickers) do if not t.off then t.fn() end end end
local function activeTickers() local c = 0; for _, t in ipairs(tickers) do if not t.off then c = c + 1 end end; return c end
function time() return 1000 end
function InCombatLockdown() return false end
local reloads = 0
function ReloadUI() reloads = reloads + 1 end
StaticPopupDialogs = {}
function StaticPopup_Show(which, a, b) popups[#popups + 1] = { which = which, a = a, b = b } end
local function lastPopup() return popups[#popups] and popups[#popups].which end
local installed = "20261115.04"
C_AddOns = { GetAddOnMetadata = function(a, f) return a == "NaowhUI" and f == "Version" and installed or nil end }
local root = { ACCENT_HEX = "40e0d0", Say = function(m) said[#said + 1] = m end, Off = function() return false end }

local function fire(event, arg)
    for _, h in ipairs(handlers) do h(nil, event, arg) end
    local t = timers; timers = {}
    for _, fn in ipairs(t) do fn() end
end

-- game state ------------------------------------------------------------------
local function NaowhEUI(v)
    return {
        ppUIScale = 0.62,
        tooltipShowTarget = false,
        chars = { someone = { level = v } },
        profiles = { Naowh = { addons = {
            EllesmereUINameplates = { bottomSlotYOffset = 22, questTextSlot = "top", width = v },
            EllesmereUIChat = { chat = { timestampAll = false } },
        } } },
        spellAssignments = { profiles = { Naowh = { specProfiles = { ["102"] = { barSpells = {
            cooldowns = { assignedSpells = { 5217, 5211 } } } } } } } },
    }
end
EllesmereUIDB = NaowhEUI(100)
EllesmereUIDB.profiles.Naowh.addons.EllesmereUINameplates.bottomSlotYOffset = 15      -- yours
EllesmereUIDB.ppUIScale = 0.63                                                        -- yours
EllesmereUIDB.tooltipShowTarget = true                                                -- yours, outside the profile
NaowhForeverDB = { profiles = { Naowh = { qol = { lockboxSkill = false, townMail = true } } } }
NaowhUIDB = { global = { installer = { records = {
    EllesmereUI = { name = "Naowh", at = 100, version = 20261115.04 },
    NaowhForever = { name = "Naowh", at = 100, version = 20261115.04 },
} } } }
local opened = 0
NaowhUI = { { RunInstaller = function() opened = opened + 1 end, HandleChatCommand = function() opened = opened + 1 end } }
NaowhUI_AddonCompartmentFunc = function() NaowhUI[1]:RunInstaller() end

assert(loadfile("MirogaUtilities/Modules/UpdateMerge.lua"))("MirogaUtilities", root)
assert(loadfile("MirogaUtilities/Modules/UpdateMergeSeed.lua"))("MirogaUtilities", root)
local um = root.UpdateMerge
local P = "\031"

-- 1. same version: nothing happens, nothing stored
fire("ADDON_LOADED", "MirogaUtilities")
fire("PLAYER_LOGIN")
ok(#popups == 0, "no popup while up to date")
ok(not um.db.merge, "no snapshot while up to date")
ok(activeTickers() == 0, "no ticker while up to date")
ok(um.db.keep.eui["profile" .. P .. "addons" .. P .. "EllesmereUINameplates" .. P .. "bottomSlotYOffset"], "seed in keep list")
ok(um.db.keep.eui["scale"], "seed: ui scale")

-- 2. NaowhUI add-on updated: popup offers the snapshot
installed = "20261120.01"
fire("PLAYER_LOGIN")
ok(lastPopup() == "MIROGA_MERGE_SNAP" and popups[#popups].a == "20261120.01", "snapshot popup with version")
ok(not um.db.merge, "no snapshot before you agree")

-- "Snapshot + NaowhUI"
StaticPopupDialogs.MIROGA_MERGE_SNAP.OnAccept()
ok(um.Phase() == "snapped", "snapshot taken")
ok(opened == 1, "installer opened after the snapshot")
ok(activeTickers() == 1, "one watcher while importing")
ok(said[#said] and said[#said]:find("Snapshot saved"), "snapshot message")
EllesmereUIDB.profiles.Naowh.addons.EllesmereUIChat.chat.timestampAll = "changed"
ok(um.db.merge.sources.eui.snap.profile.addons.EllesmereUIChat.chat.timestampAll == false, "snapshot is a copy")
EllesmereUIDB.profiles.Naowh.addons.EllesmereUIChat.chat.timestampAll = false

-- 3. import EUI only, then a reload (NaowhUI does that itself)
EllesmereUIDB = NaowhEUI(120)                                           -- width changed by Naowh
NaowhUIDB.global.installer.records.EllesmereUI.at = 200
NaowhUIDB.global.installer.records.EllesmereUI.version = 20261120.01
tick()
ok(lastPopup() == "MIROGA_MERGE_SNAP", "half done: no reload popup yet")
um.StopWatch()
fire("PLAYER_LOGIN")
ok(lastPopup() == "MIROGA_MERGE_PARTIAL" and popups[#popups].a == "1" and popups[#popups].b == "2", "partial popup 1 of 2")
ok(um.Phase() == "snapped", "still waiting for forever")

-- 4. import Forever: the watcher sees it, reload popup
NaowhForeverDB.profiles.Naowh = { qol = { lockboxSkill = true, townMail = true } }
NaowhUIDB.global.installer.records.NaowhForever.at = 200
NaowhUIDB.global.installer.records.NaowhForever.version = 20261120.01
tick()
ok(lastPopup() == "MIROGA_MERGE_RELOAD", "reload popup when all profiles are imported")
ok(activeTickers() == 0, "watcher stopped")

-- 5. after the reload: review rows, snapshot gone
fire("PLAYER_LOGIN")
ok(lastPopup() == "MIROGA_MERGE_READY", "go-through popup")
ok(um.Phase() == "review", "review phase")
ok(um.db.merge.sources.eui.snap == nil and um.db.merge.sources.forever.snap == nil, "snapshot dropped after diff")
local rows = {}
for _, id in ipairs({ "eui", "forever" }) do
    for i, r in ipairs(um.Rows(id).rows) do rows[r.path] = { r = r, i = i, id = id } end
end
local y = rows["profile" .. P .. "addons" .. P .. "EllesmereUINameplates" .. P .. "bottomSlotYOffset"]
ok(y and y.r.old == 15 and y.r.new == 22 and y.r.kind == "yours" and y.r.pick == "old", "kept setting starts on OLD")
local w = rows["profile" .. P .. "addons" .. P .. "EllesmereUINameplates" .. P .. "width"]
ok(w and w.r.old == 100 and w.r.new == 120 and w.r.kind == "update" and w.r.pick == "new", "update change starts on NEW")
local sc = rows["scale"]
ok(sc and sc.r.old == 0.63 and sc.r.pick == "old", "ui scale row")
local rs = rows["profile" .. P .. "qol" .. P .. "lockboxSkill"]
ok(rs and rs.r.old == false and rs.r.new == true and rs.r.kind == "update", "forever row")
local tt = rows["globals" .. P .. "tooltipShowTarget"]
ok(tt and tt.r.old == true and tt.r.new == false and tt.r.kind == "yours" and tt.r.pick == "old", "global tooltip setting row")
ok(um.TotalRows() == 5, "only real differences (chars ignored): " .. um.TotalRows())

-- 6. you flip two rows, apply
um.SetPick(w.id, w.i, "old")      -- keep your width
um.SetPick(sc.id, sc.i, "new")    -- take Naowh's scale
local done, written = um.Apply()
ok(done and written == 3, "apply wrote " .. tostring(written))
ok(EllesmereUIDB.tooltipShowTarget == true, "global setting written back at the top level")
ok(um.Label(tt.r.keys) == "General > tooltipShowTarget", "global label: " .. um.Label(tt.r.keys))
local np = EllesmereUIDB.profiles.Naowh.addons.EllesmereUINameplates
ok(np.bottomSlotYOffset == 15 and np.width == 100, "OLD values in the live table")
ok(EllesmereUIDB.ppUIScale == 0.62, "NEW value untouched")
ok(NaowhForeverDB.profiles.Naowh.qol.lockboxSkill == true, "forever NEW kept")
ok(not um.db.merge, "merge state cleared")
ok(um.db.keep.eui["profile" .. P .. "addons" .. P .. "EllesmereUINameplates" .. P .. "width"], "OLD pick joins the keep list")
ok(not um.db.keep.eui["scale"], "NEW pick leaves the keep list")

-- 7. back to idle
local count = #popups
fire("PLAYER_LOGIN")
ok(#popups == count, "no popup when up to date")
ok(activeTickers() == 0, "no ticker when idle")

-- 8. /nui without the popup: the guard still snapshots first
installed = "20261201.01"
um.Guard()
NaowhUI[1]:HandleChatCommand("")
ok(um.Phase() == "snapped", "guard snapshot on /nui")
ok(said[#said]:find("before NaowhUI opened"), "guard message")
um.Cancel(); um.StopWatch()

-- 9. failed snapshot: installer stays closed
NaowhForeverDB.profiles.Naowh = {}
local before = opened
ok(um.SnapAndInstall() == false and opened == before, "empty profile: no installer")
ok(said[#said]:find("Snapshot failed"), "failure message")

-- display
ok(um.Value(true) == "On" and um.Value(false) == "Off" and um.Value(0.626) == "0.63", "value text")
ok(um.Label(y.r.keys) == "Nameplates > bottomSlotYOffset", "label")

print(n .. " checks, " .. bad .. " failures"); os.exit(bad == 0 and 0 or 1)
