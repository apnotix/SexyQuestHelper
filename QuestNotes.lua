-- Chat-Meldungen zu den eigenen Quests: angenommen, Fortschritt, bereit zur Abgabe, abgegeben.
-- Jede Art ist einzeln einstellbar (Seite "Chat-Meldungen" im Einstellungsfenster, /sem), ebenso wohin die Meldung geht:
-- nur ins eigene Chatfenster, in den Gruppenchat (Party/Raid/Instanz) oder in den Gildenchat.
-- Eigene Datei, damit die Hauptdatei nicht noch mehr lokale Variablen braucht (Lua erlaubt höchstens 200 je Block).

local SEM = LibStub("SexyEditMode-1.0", true)
local de = GetLocale() == "deDE"
local function T(d, e) return de and d or e end

-- progressDone: nur erfüllte Ziele melden (3/3), nicht jeden Zähler; progressBatch: Änderungen einer Quest kurz sammeln und als eine Zeile melden
local DEFAULTS = { accepted = true, progress = true, progressDone = false, progressBatch = true, ready = true, turnedIn = false, channel = "SELF" }

local function Get(key)
	local n = SexyQuestHelperDB and SexyQuestHelperDB.notes
	local v = n and n[key]
	if v == nil then return DEFAULTS[key] end
	return v
end

local function Set(key, value)
	SexyQuestHelperDB = SexyQuestHelperDB or {}
	SexyQuestHelperDB.notes = SexyQuestHelperDB.notes or {}
	SexyQuestHelperDB.notes[key] = value
end

-- Fortschritt melden: "off", "done" (nur erfüllte Ziele) oder "all" (jeder Zähler). Ältere Einstellungen (progress / progressDone) gelten weiter,
-- solange die Auswahl nie gesetzt wurde.
local function ProgressMode()
	local n = SexyQuestHelperDB and SexyQuestHelperDB.notes
	if n and n.progressMode then return n.progressMode end
	if n and n.progressDone then return "done" end
	if n and n.progress == false then return "off" end
	return "all"
end

-- Ziel der Meldung. Ohne Gruppe bzw. Gilde fällt sie ins eigene Chatfenster zurück.
-- (SAY geht bewusst nicht: Blizzard erlaubt es nur aus einer Tasteneingabe heraus, nicht aus einem Ereignis.)
local function Send(text)
	local channel = Get("channel")
	if channel == "GROUP" and IsInGroup() then
		local chat = IsInRaid() and "RAID" or ((IsPartyLFG and IsPartyLFG()) and "INSTANCE_CHAT" or "PARTY")
		local ok, err = pcall(SendChatMessage, "[SQH] " .. text, chat)
		if not ok then DEFAULT_CHAT_FRAME:AddMessage("|cffe8c26a[SQH]|r " .. text) end
	elseif channel == "GUILD" and IsInGuild() then
		local ok, err = pcall(SendChatMessage, "[SQH] " .. text, "GUILD")
		if not ok then DEFAULT_CHAT_FRAME:AddMessage("|cffe8c26a[SQH]|r " .. text) end
	else
		DEFAULT_CHAT_FRAME:AddMessage("|cffe8c26a[SQH]|r " .. text)
	end
end

local function QuestLink(id)
	local link = GetQuestLink and GetQuestLink(id)
	if link then return link end
	local title = C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id)
	return "[" .. (title or ("Quest " .. id)) .. "]"
end

-- Alle Quests im Questlog (ohne Überschriften)
local function LogIds()
	local ids = {}
	local n = (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and (C_QuestLog.GetNumQuestLogEntries()))
		or (GetNumQuestLogEntries and (GetNumQuestLogEntries())) or 0
	for i = 1, n do
		local id
		if C_QuestLog and C_QuestLog.GetInfo then
			local info = C_QuestLog.GetInfo(i)
			if info and not info.isHeader then id = info.questID end
		elseif GetQuestLogTitle then
			local _, _, _, isHeader, _, _, _, questID = GetQuestLogTitle(i)
			if not isHeader then id = questID end
		end
		if id and id > 0 then ids[#ids + 1] = id end
	end
	return ids
end

-- Stand einer Quest: { items = { { text, have, need, done }, ... }, complete = bool }
local function Objectives(id)
	local out = { items = {} }
	if C_QuestLog and C_QuestLog.GetQuestObjectives then
		local ok, objs = pcall(C_QuestLog.GetQuestObjectives, id)
		if ok and type(objs) == "table" then
			for _, o in ipairs(objs) do
				out.items[#out.items + 1] = {
					text = o.text or "", have = o.numFulfilled or 0, need = o.numRequired or 0, done = o.finished and true or false,
				}
			end
		end
	end
	if C_QuestLog and C_QuestLog.IsComplete then
		local ok, complete = pcall(C_QuestLog.IsComplete, id)
		out.complete = ok and complete and true or false
	end
	return out
end

local snap, primed = {}, false

-- Fortschritt einer Quest sammeln: je Ziel der neueste Text; nach kurzer Ruhe eine Zeile für die ganze Quest
local BATCH_WAIT = 2
local batch = {}   -- [Quest] = { [Ziel-Nr] = Text }
local PROGRESS_LINE = T("Fortschritt: ", "Progress: ")   -- ohne Questnamen: nur die Ziele mit ihrem Stand

-- Gesammelten Fortschritt einer Quest jetzt senden (nach Ruhe oder vor "Bereit zur Abgabe"/"Abgegeben", damit die Reihenfolge stimmt)
local function FlushProgress(id)
	local b = batch[id]
	if not b then return end
	batch[id] = nil
	local parts = {}
	for i = 1, 20 do if b[i] then parts[#parts + 1] = b[i] end end
	if #parts > 0 then Send(PROGRESS_LINE .. table.concat(parts, "; ")) end
end

local function Progress(id, index, text)
	if not Get("progressBatch") then Send(PROGRESS_LINE .. text); return end
	local b = batch[id]
	if not b then
		b = {}
		batch[id] = b
		C_Timer.After(BATCH_WAIT, function()
			if batch[id] == b then FlushProgress(id) end
		end)
	end
	b[index] = text
end

-- Vergleicht den Questlog mit dem letzten Stand und meldet, was sich geändert hat. announce = false: nur Stand merken.
local function Check(announce)
	local present = {}
	for _, id in ipairs(LogIds()) do
		present[id] = true
		local now, old = Objectives(id), snap[id]
		if old and announce then
			local mode = ProgressMode()
			-- Wird die Quest mit diesem Schritt fertig und "Bereit zur Abgabe" ist an, entfällt der letzte Fortschritt: die Meldung sagt es schon
			local willReady = Get("ready") and now.complete and not old.complete
			if mode ~= "off" and not willReady then
				for i, o in ipairs(now.items) do
					local p = old.items[i]
					local changed = p and (o.have > p.have or (o.done and not p.done))
					-- "nur erfüllte Ziele": der Zähler allein zählt nicht, das Ziel muss gerade fertig geworden sein
					if changed and o.text ~= "" and (mode == "all" or (o.done and not p.done)) then
						Progress(id, i, o.text)
					end
				end
			end
			if Get("ready") and now.complete and not old.complete then
				batch[id] = nil   -- noch gesammelter Fortschritt dieser Quest wird verworfen
				Send(T("Bereit zur Abgabe: ", "Ready to turn in: ") .. QuestLink(id))
			end
		end
		snap[id] = now
	end
	for id in pairs(snap) do
		if not present[id] then snap[id] = nil end
	end
end

local pending
local function CheckSoon()
	if pending then return end
	pending = true
	C_Timer.After(0.3, function()
		pending = false
		Check(primed)
	end)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("QUEST_ACCEPTED")
frame:RegisterEvent("QUEST_TURNED_IN")
frame:RegisterEvent("QUEST_LOG_UPDATE")
frame:SetScript("OnEvent", function(_, event, a, b)
	if event == "PLAYER_LOGIN" then
		if SEM and SEM.RegisterPage then
			SEM:RegisterPage({
				name = "SexyQuestHelper: " .. T("Chat-Meldungen", "Chat messages"),
				category = T("Verwaltung", "Manage"),   -- Zwischenüberschrift in der Seitenleiste des Einstellungsfensters
				addon = "SexyQuestHelper",
				description = T("Meldungen zu deinen Quests im Chat: angenommen, Fortschritt, bereit zur Abgabe, abgegeben.",
					"Chat messages about your quests: accepted, progress, ready to turn in, turned in."),
				settings = {
					{ type = "header", name = T("Meldungen", "Messages"), id = "notes" },
					{ type = "check", name = T("Quest angenommen", "Quest accepted"),
						get = function() return Get("accepted") end, set = function(v) Set("accepted", v and true or false) end },
					{ type = "select", name = T("Questfortschritt melden", "Report quest progress"),
						options = {
							{ value = "off", label = T("Aus", "Off") },
							{ value = "done", label = T("Zwischenziele", "Intermediate goals") },
							{ value = "all", label = T("Alle", "All") },
						},
						get = function() return ProgressMode() end, set = function(v) Set("progressMode", v) end },
					{ type = "check", name = T("Änderungen einer Quest zu einer Zeile zusammenfassen", "Combine the changes of a quest into one line"),
						get = function() return Get("progressBatch") end, set = function(v) Set("progressBatch", v and true or false) end },
					{ type = "check", name = T("Bereit zur Abgabe", "Ready to turn in"),
						get = function() return Get("ready") end, set = function(v) Set("ready", v and true or false) end },
					{ type = "check", name = T("Quest abgegeben", "Quest turned in"),
						get = function() return Get("turnedIn") end, set = function(v) Set("turnedIn", v and true or false) end },
					{ type = "header", name = T("Wohin", "Where"), id = "target" },
					{ type = "select", name = T("Kanal", "Channel"),
						options = {
							{ value = "SELF", label = T("Nur ich (Chatfenster)", "Only me (chat window)") },
							{ value = "GROUP", label = T("Gruppe (Party, Raid, Instanz)", "Group (party, raid, instance)") },
							{ value = "GUILD", label = T("Gilde", "Guild") },
						},
						get = function() return Get("channel") end, set = function(v) Set("channel", v) end },
				},
			})
		end
	elseif event == "PLAYER_ENTERING_WORLD" then
		-- Nach dem Laden ist der Questlog erst nach einer Weile vollständig: bis dahin nur den Stand merken, nichts melden
		primed = false
		C_Timer.After(5, function()
			Check(false)
			primed = true
		end)
	elseif event == "QUEST_ACCEPTED" then
		local id = b or a   -- Classic: (Logindex, Quest-ID), Retail: (Quest-ID)
		if primed and Get("accepted") and id then
			Send(T("Quest angenommen: ", "Quest accepted: ") .. QuestLink(id))
		end
		CheckSoon()
	elseif event == "QUEST_TURNED_IN" then
		if primed and Get("turnedIn") and a then
			FlushProgress(a)
			Send(T("Quest abgegeben: ", "Quest turned in: ") .. QuestLink(a))
		end
		CheckSoon()
	elseif event == "QUEST_LOG_UPDATE" then
		CheckSoon()
	end
end)
