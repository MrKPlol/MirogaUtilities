-- Quest marker recorder: saves where the game's own quest guide points for
-- every quest in your log (map POI, objective icon, next waypoint), per
-- objective state. Used to build guides from Blizzard's positions instead of
-- estimates. Data: MirogaUtilitiesDB.questPOI[questID][state] = { map, x, y, src }.
-- Records only while on (/mu poi), silently, at most every 2 seconds.
local _, root = ...
local qp = {}
root.QuestPOI = qp

local function DB()
    if type(MirogaUtilitiesDB) ~= "table" then return nil end
    MirogaUtilitiesDB.questPOI = MirogaUtilitiesDB.questPOI or {}
    return MirogaUtilitiesDB.questPOI
end

function qp.On() return type(MirogaUtilitiesDB) == "table" and MirogaUtilitiesDB.questPOIOn == true end

local function State(questID)
    local parts = {}
    local objectives = C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(questID)
    for i, o in ipairs(objectives or {}) do
        parts[#parts + 1] = (o.finished and "1" or "0")
        if i > 8 then break end
    end
    if C_QuestLog.IsComplete and C_QuestLog.IsComplete(questID) then return "done" end
    return table.concat(parts)
end

local function Put(questID, state, src, map, x, y)
    if not (x and y) or x <= 0 or y <= 0 then return end
    local db = DB()
    if not db then return end
    db[questID] = db[questID] or {}
    local key = state .. ":" .. src
    db[questID][key] = { map = map, x = math.floor(x * 1000 + 0.5) / 10, y = math.floor(y * 1000 + 0.5) / 10, t = time() }
end

function qp.Record()
    if not qp.On() then return 0 end
    local count = 0
    local map = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local maps = { map }
    if map then
        local info = C_Map.GetMapInfo(map)
        if info and info.parentMapID and info.parentMapID ~= 0 then maps[#maps + 1] = info.parentMapID end
    end
    for _, m in ipairs(maps) do
        local list = C_QuestLog.GetQuestsOnMap and C_QuestLog.GetQuestsOnMap(m)
        for _, q in ipairs(list or {}) do
            if q.questID then
                Put(q.questID, State(q.questID), "map", m, q.x, q.y)
                count = count + 1
            end
        end
    end
    for i = 1, (C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries() or 0) do
        local info = C_QuestLog.GetInfo(i)
        local id = info and not info.isHeader and info.questID
        if id and id > 0 then
            local state = State(id)
            if QuestPOIGetIconInfo then
                local _, x, y = QuestPOIGetIconInfo(id)
                if map then Put(id, state, "icon", map, x, y) end
            end
            if C_QuestLog.GetNextWaypoint then
                local wm, wx, wy = C_QuestLog.GetNextWaypoint(id)
                if wm then Put(id, state, "way", wm, wx, wy) end
            end
        end
    end
    return count
end

function qp.Toggle()
    if type(MirogaUtilitiesDB) ~= "table" then MirogaUtilitiesDB = {} end
    MirogaUtilitiesDB.questPOIOn = not qp.On()
    local n = 0
    for _ in pairs(DB() or {}) do n = n + 1 end
    root.Say("Quest marker recorder " .. (qp.On() and "|cff40ff60on|r" or "|cffff5050off|r") .. " (" .. n .. " quests saved).")
    if qp.On() then qp.Record() end
end

local last = 0
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        for _, e in ipairs({ "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "ZONE_CHANGED_NEW_AREA", "QUEST_POI_UPDATE", "UNIT_QUEST_LOG_CHANGED" }) do
            pcall(self.RegisterEvent, self, e)
        end
    end
    if not qp.On() or GetTime() - last < 2 then return end
    last = GetTime()
    pcall(qp.Record)
end)
