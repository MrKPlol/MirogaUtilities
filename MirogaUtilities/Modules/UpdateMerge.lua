-- Update merge: a Naowh update without losing your own settings.
--
-- 1. A newer NaowhUI add-on than your last import: a popup offers ONE
--    snapshot of your Naowh profiles (EllesmereUI + Naowh Forever) and then
--    opens NaowhUI's installer.
-- 2. When every profile carries the new version, the update is done. After
--    a reload, every setting that differs from the snapshot is one row:
--    OLD (before) on the left, NEW (after) on the right. You pick a side.
-- 3. Apply writes the OLD picks into the live tables, reloads, and throws the
--    snapshot away. Only a short list of paths you kept on OLD stays, so the
--    next update starts those rows on OLD again.
--
-- Nothing runs while no update waits: no snapshots, no tickers.
local _, root = ...
local um = {}
root.UpdateMerge = um

local SEP = "\31"

-- EllesmereUI keeps some settings outside the profile (tooltips, window
-- skins, unlock anchors), and NaowhUI imports those too. Everything at the
-- top of EllesmereUIDB counts, except profiles, characters and caches.
local EUI_NOT_GLOBAL = {
    profiles = true, spellAssignments = true, ppUIScale = true, chars = true,
    cdmCachedBarSizes = true, lastSpecByChar = true, goldLedger = true, _migrations = true,
    lastLoginVersion = true, profileOrder = true, activeProfile = true, dismissedConflicts = true,
}

local function EUIGlobals()
    local out = {}
    for k, v in pairs(EllesmereUIDB) do
        if type(k) == "string" and not EUI_NOT_GLOBAL[k] and k:sub(1, 1) ~= "_" then out[k] = v end
    end
    return out
end

local SOURCES = {
    {
        id = "eui", label = "EllesmereUI", record = "EllesmereUI",
        ready = function() return type(EllesmereUIDB) == "table" end,
        parts = function(name)
            local db = EllesmereUIDB
            local sa = type(db.spellAssignments) == "table" and db.spellAssignments.profiles
            return {
                profile = type(db.profiles) == "table" and db.profiles[name] or nil,
                spells = type(sa) == "table" and sa[name] or nil,
                scale = db.ppUIScale,
                globals = EUIGlobals(),
            }
        end,
        container = function(name, part)
            local db = EllesmereUIDB
            if part == "scale" then return db, "ppUIScale" end
            if part == "globals" then return db, nil end
            if part == "profile" then
                db.profiles = db.profiles or {}
                return db.profiles, name
            end
            db.spellAssignments = db.spellAssignments or {}
            db.spellAssignments.profiles = db.spellAssignments.profiles or {}
            return db.spellAssignments.profiles, name
        end,
    },
    {
        id = "forever", label = "Naowh Forever", record = "NaowhForever",
        ready = function() return type(NaowhForeverDB) == "table" end,
        parts = function(name)
            return { profile = type(NaowhForeverDB.profiles) == "table" and NaowhForeverDB.profiles[name] or nil }
        end,
        container = function(name)
            NaowhForeverDB.profiles = NaowhForeverDB.profiles or {}
            return NaowhForeverDB.profiles, name
        end,
    },
}
um.SOURCES = SOURCES

-- ---------------------------------------------------------------------------
-- tables

local function Copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = Copy(x) end
    return out
end
um.Copy = Copy

-- 1..n with only plain values: one setting (a spell list, a bag order)
local function IsList(t)
    if type(t) ~= "table" then return false end
    local n = #t
    if n == 0 then return false end
    local count = 0
    for k, v in pairs(t) do
        count = count + 1
        if type(k) ~= "number" or type(v) == "table" then return false end
    end
    return count == n
end
um.IsList = IsList

-- positions drift by fractions of a pixel on every save: not a change
local function Near(a, b)
    if type(a) == "number" and type(b) == "number" then
        local tol = (math.abs(a) < 5 and math.abs(b) < 5) and 0.001 or 1
        return math.abs(a - b) < tol
    end
    return a == b
end

local function Same(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return Near(a, b) end
    for k, v in pairs(a) do if not Same(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
um.Same = Same

local function KeyText(k) return type(k) == "number" and ("#" .. k) or tostring(k) end

function um.PathKey(keys)
    local t = {}
    for i, k in ipairs(keys) do t[i] = KeyText(k) end
    return table.concat(t, SEP)
end

local function Get(snap, keys)
    local v = snap
    for _, k in ipairs(keys) do
        if type(v) ~= "table" then return nil end
        v = v[k]
    end
    return v
end
um.Get = Get

local function Leaf(v) return type(v) ~= "table" or IsList(v) or next(v) == nil end

-- walks old and new side by side; a value, a list or a block that exists on
-- one side only is one row
local function Walk(a, b, keys, out)
    if a ~= nil and b ~= nil and not Leaf(a) and not Leaf(b) then
        for k, x in pairs(a) do
            keys[#keys + 1] = k
            Walk(x, b[k], keys, out)
            keys[#keys] = nil
        end
        for k, y in pairs(b) do
            if a[k] == nil then
                keys[#keys + 1] = k
                Walk(nil, y, keys, out)
                keys[#keys] = nil
            end
        end
    elseif not Same(a, b) then
        out[#out + 1] = { unpack(keys) }
    end
end

-- key lists of every setting that differs
function um.Diff(old, new)
    old, new = old or {}, new or {}
    local out = {}
    for part in pairs(old) do Walk(old[part], new[part], { part }, out) end
    for part in pairs(new) do
        if old[part] == nil then Walk(nil, new[part], { part }, out) end
    end
    return out
end

local function Count(v)
    if Leaf(v) then return 1 end
    local n = 0
    for _, x in pairs(v) do n = n + Count(x) end
    return n
end
um.CountLeaves = Count

-- the path, a parent or a child of it is on your keep list
local function Kept(keep, path)
    if keep[path] then return true end
    for t in pairs(keep) do
        if path:sub(1, #t + 1) == t .. SEP or t:sub(1, #path + 1) == path .. SEP then return true end
    end
    return false
end
um.Kept = Kept

function um.BuildRows(old, new, keep)
    local rows = {}
    for _, keys in ipairs(um.Diff(old, new)) do
        local path = um.PathKey(keys)
        local yours = Kept(keep or {}, path)
        rows[#rows + 1] = {
            path = path, keys = keys, old = Copy(Get(old, keys)), new = Copy(Get(new, keys)),
            kind = yours and "yours" or "update", pick = yours and "old" or "new",
        }
    end
    table.sort(rows, function(a, b) return a.path < b.path end)
    return rows
end

-- ---------------------------------------------------------------------------
-- NaowhUI state

local function Records()
    local g = type(NaowhUIDB) == "table" and NaowhUIDB.global
    local inst = type(g) == "table" and g.installer
    return type(inst) == "table" and inst.records or nil
end

function um.Record(src)
    local records = Records()
    local r = records and records[src.record]
    if type(r) ~= "table" or not r.name then return nil end
    return r
end

function um.InstalledVersion()
    local get = C_AddOns and C_AddOns.GetAddOnMetadata
    return tonumber(get and get("NaowhUI", "Version") or nil)
end

function um.ImportedVersion()
    local newest
    for _, src in ipairs(SOURCES) do
        local rec = um.Record(src)
        local v = rec and tonumber(rec.version)
        if v and (not newest or v > newest) then newest = v end
    end
    return newest
end

-- a newer NaowhUI than your profiles, not skipped
function um.UpdateWaiting()
    local installed, imported = um.InstalledVersion(), um.ImportedVersion()
    if not (installed and imported) or installed <= imported then return nil end
    if um.db.skipVersion == installed then return nil end
    return installed, imported
end

function um.Phase() return um.db and um.db.merge and um.db.merge.phase or nil end

-- ---------------------------------------------------------------------------
-- the one snapshot

function um.TakeSnapshot()
    local m = { phase = "snapped", version = um.InstalledVersion(), sources = {}, when = time() }
    local summary = {}
    for _, src in ipairs(SOURCES) do
        local rec = src.ready() and um.Record(src)
        if rec then
            local live = src.parts(rec.name)
            local copy = Copy(live)
            local n = Count(copy.profile)
            if not Same(copy, live) or n < 2 then
                return false, src.label .. ": snapshot check failed"
            end
            m.sources[src.id] = { name = rec.name, at = rec.at, snap = copy }
            summary[#summary + 1] = ("%s %d"):format(src.label, n)
        end
    end
    if not next(m.sources) then return false, "no Naowh profile found" end
    um.db.merge = m
    return true, table.concat(summary, ", ")
end

-- profiles that got the new version since the snapshot
function um.Status()
    local m = um.db.merge
    if not m then return nil end
    local done, total = 0, 0
    for _, src in ipairs(SOURCES) do
        local s = m.sources[src.id]
        if s then
            total = total + 1
            local rec = um.Record(src)
            if rec and rec.at ~= s.at and (tonumber(rec.version) or 0) >= (m.version or 0) then done = done + 1 end
        end
    end
    return done, total
end

function um.Finished()
    local done, total = um.Status()
    return done ~= nil and total > 0 and done == total
end

-- after the reload: rows from snapshot vs live, snapshot dropped
function um.BuildReview()
    local m = um.db.merge
    if not m or m.phase ~= "snapped" then return 0 end
    local total = 0
    for _, src in ipairs(SOURCES) do
        local s = m.sources[src.id]
        local rec = s and src.ready() and um.Record(src)
        if s and rec and rec.at ~= s.at then
            s.rows = um.BuildRows(s.snap, src.parts(rec.name), um.db.keep[src.id] or {})
            s.version = rec.version
            total = total + #s.rows
        end
        if s then s.snap = nil end
    end
    m.phase = "review"
    if total == 0 then um.db.merge = nil end
    return total
end

function um.Rows(id)
    local m = um.db and um.db.merge
    local s = m and m.phase == "review" and m.sources[id]
    return s and s.rows and #s.rows > 0 and s or nil
end

function um.Count(id)
    local s = um.Rows(id)
    if not s then return 0, 0 end
    local open = 0
    for _, r in ipairs(s.rows) do if not r.pick then open = open + 1 end end
    return #s.rows, open
end

function um.TotalRows()
    local total = 0
    for _, src in ipairs(SOURCES) do total = total + (um.Count(src.id)) end
    return total
end

function um.SetPick(id, i, pick)
    local s = um.Rows(id)
    if s and s.rows[i] then s.rows[i].pick = pick end
end

function um.SetAll(id, kind, pick)
    local s = um.Rows(id)
    if not s then return end
    for _, r in ipairs(s.rows) do
        if not kind or r.kind == kind then r.pick = pick end
    end
end

function um.SourceByID(id)
    for _, src in ipairs(SOURCES) do if src.id == id then return src end end
end

local function Write(src, name, keys, value)
    local holder, key = src.container(name, keys[1])
    local first = 2
    if key == nil then           -- the part is the holder itself (EUI globals)
        if #keys < 2 then return end
        key, first = keys[2], 3
    end
    if #keys == first - 1 then holder[key] = Copy(value); return end
    if type(holder[key]) ~= "table" then holder[key] = {} end
    local t = holder[key]
    for i = first, #keys - 1 do
        local k = keys[i]
        if type(t[k]) ~= "table" then
            if value == nil then return end
            t[k] = {}
        end
        t = t[k]
    end
    t[keys[#keys]] = Copy(value)
end
um.Write = Write

-- writes every OLD pick; the keep list follows your picks
function um.Apply()
    local m = um.db.merge
    if not m or m.phase ~= "review" then return false, "nothing to apply" end
    for _, src in ipairs(SOURCES) do
        local s = um.Rows(src.id)
        if s then
            for _, r in ipairs(s.rows) do
                if not r.pick then return false, src.label .. ": pick OLD or NEW in every row first" end
            end
        end
    end
    local written = 0
    for _, src in ipairs(SOURCES) do
        local s = um.Rows(src.id)
        if s then
            local keep = um.db.keep[src.id] or {}
            um.db.keep[src.id] = keep
            for _, r in ipairs(s.rows) do
                if r.pick == "old" then
                    Write(src, s.name, r.keys, r.old)
                    keep[r.path] = true
                    written = written + 1
                else
                    keep[r.path] = nil
                end
            end
        end
    end
    um.db.merge = nil
    return true, written
end

function um.Cancel() um.db.merge = nil end

-- ---------------------------------------------------------------------------
-- display

local function Spell(id)
    if type(id) ~= "number" then return tostring(id) end
    if id < 0 then
        local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(-id)
        return name or ("item " .. -id)
    end
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
    return name or tostring(id)
end

local function Pretty(k)
    if type(k) == "number" then return "#" .. k end
    return (tostring(k):gsub("^EllesmereUI(%u)", "%1"))
end

local PART_LABEL = { spells = "CDM spells", scale = "UI scale", globals = "General" }

function um.Label(keys)
    local parts = {}
    for i, k in ipairs(keys) do
        if i == 1 then
            if PART_LABEL[k] then parts[#parts + 1] = PART_LABEL[k] end
        elseif not (i == 2 and k == "addons" and keys[1] == "profile") then
            parts[#parts + 1] = Pretty(k)
        end
    end
    return table.concat(parts, " > ")
end

function um.Group(keys)
    if PART_LABEL[keys[1]] then return PART_LABEL[keys[1]] end
    return Pretty((keys[2] == "addons" and keys[3]) or keys[2] or "?")
end

function um.Value(v)
    if v == nil then return "|cff777777none|r" end
    if v == true then return "On" end
    if v == false then return "Off" end
    if type(v) == "number" then
        if v == math.floor(v) then return tostring(v) end
        return (("%.2f"):format(v):gsub("0+$", ""):gsub("%.$", ""))
    end
    if type(v) == "string" then
        if v == "" then return "|cff777777empty|r" end
        return #v > 26 and (v:sub(1, 24) .. "..") or v
    end
    if IsList(v) then return #v .. " entries" end
    local n = 0
    for _ in pairs(v) do n = n + 1 end
    return n == 0 and "|cff777777empty|r" or (n .. " settings")
end

function um.Details(v, spells)
    if type(v) ~= "table" then return nil end
    local lines = {}
    if IsList(v) then
        for i, x in ipairs(v) do
            lines[#lines + 1] = i .. ". " .. (spells and Spell(x) or tostring(x))
            if i >= 30 then lines[#lines + 1] = "..."; break end
        end
    else
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        for i, k in ipairs(keys) do
            lines[#lines + 1] = Pretty(k) .. ": " .. um.Value(v[k])
            if i >= 30 then lines[#lines + 1] = "..."; break end
        end
    end
    return lines
end

-- ---------------------------------------------------------------------------
-- flow: popups and one short-lived watcher

local function OpenInstaller()
    if NaowhUI_AddonCompartmentFunc then NaowhUI_AddonCompartmentFunc(); return true end
    local nui = type(NaowhUI) == "table" and NaowhUI[1]
    if nui and nui.RunInstaller then nui:RunInstaller(); return true end
    return false
end

local watcher, Show
local function StopWatch() if watcher then watcher:Cancel(); watcher = nil end end

-- runs only between snapshot and the end of the import
local function Watch()
    if watcher or not (C_Timer and C_Timer.NewTicker) then return end
    watcher = C_Timer.NewTicker(2, function()
        if um.Phase() ~= "snapped" then StopWatch(); return end
        if um.Finished() then
            StopWatch()
            Show("MIROGA_MERGE_RELOAD")
        end
    end)
end
um.Watch, um.StopWatch = Watch, StopWatch

function um.SnapAndInstall()
    local ok, info = um.TakeSnapshot()
    if not ok then
        root.Say("|cffff5050Snapshot failed:|r " .. info .. ". NaowhUI was not opened.")
        return false
    end
    root.Say("Snapshot saved (" .. info .. " settings). NaowhUI opens: import the update there.")
    Watch()
    if not OpenInstaller() then root.Say("Open NaowhUI yourself: /nui") end
    return true
end

local function Popups()
    if StaticPopupDialogs.MIROGA_MERGE_SNAP then return end
    local HEAD = "|cff40e0d0Miroga Utilities|r\n\n"
    local function base(t)
        t.timeout, t.whileDead, t.preferredIndex = 0, true, 3
        if t.hideOnEscape == nil then t.hideOnEscape = true end
        return t
    end
    StaticPopupDialogs.MIROGA_MERGE_SNAP = base({
        text = HEAD .. "NaowhUI %s is installed, your profiles still have %s.\n\n" ..
            "Save a snapshot of your settings first? Then NaowhUI opens, you import the update, " ..
            "and afterwards you pick OLD or NEW for every setting it changed.",
        button1 = "Snapshot + NaowhUI", button2 = "Later", button3 = "Skip version",
        OnAccept = function() um.SnapAndInstall() end,
        OnAlt = function() um.db.skipVersion = um.InstalledVersion() end,
    })
    StaticPopupDialogs.MIROGA_MERGE_RELOAD = base({
        text = HEAD .. "The Naowh update is done. Reload now and go through OLD and NEW together?",
        button1 = "Reload", button2 = "Later",
        OnAccept = function() ReloadUI() end,
    })
    StaticPopupDialogs.MIROGA_MERGE_PARTIAL = base({
        text = HEAD .. "The Naowh update is not finished: %s of %s profiles have the new version.",
        button1 = "Open NaowhUI", button2 = "I'm done", button3 = "Cancel merge",
        hideOnEscape = false,
        OnAccept = function() Watch(); OpenInstaller() end,
        OnCancel = function(_, _, reason)
            if reason ~= "clicked" then return end
            local n = um.BuildReview()
            if n > 0 then Show("MIROGA_MERGE_READY", tostring(n)) end
        end,
        OnAlt = function() um.Cancel(); root.Say("Merge cancelled, snapshot deleted.") end,
    })
    StaticPopupDialogs.MIROGA_MERGE_READY = base({
        text = HEAD .. "The update changed %s settings. Go through them now: OLD (before) or NEW (after)?",
        button1 = "Go through", button2 = "Later",
        OnAccept = function() if root.OpenHub then root.OpenHub("merge") end end,
    })
end

Show = function(which, a, b)
    if not (StaticPopupDialogs and StaticPopup_Show) then return end
    Popups()
    StaticPopup_Show(which, a, b)
end
um.Show = Show

-- login / reload: where are we?
function um.OnLogin()
    local phase = um.Phase()
    if phase == "snapped" then
        if um.Finished() then
            local n = um.BuildReview()
            if n > 0 then Show("MIROGA_MERGE_READY", tostring(n))
            else root.Say("Naowh update done: nothing differs from your snapshot.") end
        else
            local done, total = um.Status()
            Show("MIROGA_MERGE_PARTIAL", tostring(done), tostring(total))
            Watch()
        end
        return um.Phase()
    elseif phase == "review" then
        Show("MIROGA_MERGE_READY", tostring(um.TotalRows()))
        return "review"
    end
    local installed, imported = um.UpdateWaiting()
    if installed then
        Show("MIROGA_MERGE_SNAP", tostring(installed), tostring(imported))
        return "waiting"
    end
    return nil
end

-- NaowhUI opened some other way (/nui, minimap) while an update waits:
-- the snapshot still comes first
local function Guard(owner, key)
    if type(owner) ~= "table" or type(owner[key]) ~= "function" then return end
    local original = owner[key]
    owner[key] = function(...)
        if not um.Phase() and um.UpdateWaiting() then
            local ok, info = um.TakeSnapshot()
            if ok then
                root.Say("Snapshot saved before NaowhUI opened (" .. info .. " settings).")
                Watch()
            end
        end
        return original(...)
    end
end

function um.Guard()
    local nui = type(NaowhUI) == "table" and NaowhUI[1]
    if type(nui) == "table" then
        Guard(nui, "RunInstaller")
        Guard(nui, "HandleChatCommand")
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self, event, addon)
    if event == "ADDON_LOADED" then
        if addon ~= "MirogaUtilities" then return end
        if root.Off("UpdateMerge", self) then return end
        local db = type(MirogaUpdateMergeDB) == "table" and MirogaUpdateMergeDB or {}
        MirogaUpdateMergeDB = db
        db.keep = type(db.keep) == "table" and db.keep or {}
        um.db = db
        if um.Seed then um.Seed(db) end
        return
    end
    if not um.db then return end
    pcall(um.Guard)
    C_Timer.After(3, function()
        if InCombatLockdown() then return end
        local ok, err = pcall(um.OnLogin)
        if not ok then root.Say("Update merge: " .. tostring(err)) end
    end)
end)
