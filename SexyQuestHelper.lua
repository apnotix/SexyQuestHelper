-- SexyQuestHelper: vergleicht die Quests des aktuellen Gebiets mit allen
-- Gruppenmitgliedern, die ebenfalls dieses Addon nutzen.
--
-- Ablauf: Jeder Client liest seine Quests des aktuellen Gebiets (Questlog-
-- Kategorie = Gebietsname), sendet die Quest-IDs per Addon-Nachricht an die
-- Gruppe und vergleicht sie mit den empfangenen Listen der anderen.

local PREFIX = "SexyQuestHelper"
local VERSION = "1.0.15" -- wird vom Release-Workflow zusammen mit ## Version in der .toc angehoben (GetAddOnMetadata fehlt auf Forever)
local versions = {} -- [name] = Addon-Version des Mitglieds
local blockedBy = {}      -- [name] = { [questID] = true }: Quests aus MEINER Liste, die das Mitglied laut seiner Meldung nicht annehmen kann
local learnedBlocked = {} -- wie blockedBy, aber aus Fehlermeldungen beim Teilen gelernt
local completedBy = {} -- [name] = { [questID] = true }: Quests aus MEINER Liste, die das Mitglied schon abgeschlossen hat
local SCAN_DELAY = 1        -- Sekunden Entprellung nach Events
local DIFF_SETTLE = 4       -- Sekunden, die ein Unterschied bestehen muss, bevor das Fenster erscheint
local IGNORE_AFTER_SCAN = 2 -- Sekunden, in denen eigene Auf-/Zuklapp-Events ignoriert werden
local CHUNK_SIZE = 200      -- Zeichen Quest-IDs pro Nachricht (Limit: 255 inkl. Header)

-- Einstellungen (Edit Mode); gespeichert wird nur, was vom Standard abweicht
local DEFAULTS = {
	settleDelay = DIFF_SETTLE, -- Sekunden, die ein Unterschied bestehen muss, bevor das Fenster erscheint
	autoClose = 0,             -- Sekunden bis das Fenster von selbst zugeht (0 = aus)
	sound = false,             -- Ton beim Erscheinen
	chatNotice = false,        -- Hinweis im Chat, was fehlt
	hideZone = false,          -- Gebiets-Etikett im Titel ausblenden
	helpAuto = false,          -- zweites Fenster (Mitspielern helfen) einschalten: es geht dann von selbst auf
	helpReady = false,         -- Quests, die ich noch im Log habe und nur noch abgeben muss, zaehlen als erledigt
}
local cfg = setmetatable({}, { __index = DEFAULTS })

local isDE = GetLocale() == "deDE"
local function T(de, en) return isDE and de or en end

local SEM = LibStub("SexyEditMode-1.0")
local frame = CreateFrame("Frame")
local ui                      -- Anzeigefenster (lazy)
local helpUI                  -- zweites Fenster: Mitspielern helfen
local RefreshHelp
local myZone, myZoneKey, myIds, myTitles = "", "", {}, {} -- myZone: lokaler Name, myZoneKey: sprachunabhaengiger Vergleichsschluessel
local mySignature = ""
local members = {}            -- [name] = { zone = "", ids = { [id] = true } }
local scanTimer, ignoreUntil = nil, 0
local progressBy = {}         -- [name] = { [questID] = { pct = 0-100, ready = bool } }: Fortschritt der Mitglieder
local myProgress = {}         -- dasselbe fuer mich
local detailsBy = {}          -- [name] = { [questID] = { "Zieltext", ... } }: die Ziele der Mitglieder
local Refresh
local anyAddonMsgs = 0
local recvCount, lastRecv, lastReply, prefixOk = 0, "-", 0, nil
local testMode = false -- /sqh test: simuliert ein Gruppenmitglied

---------------------------------------------------------------------------
-- Questlog lesen
---------------------------------------------------------------------------

local function NumEntries()
	if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
		return (C_QuestLog.GetNumQuestLogEntries())
	end
	return (GetNumQuestLogEntries and GetNumQuestLogEntries()) or 0
end

-- Liefert title, isHeader, isCollapsed, questID (Retail/neue Clients oder Legacy-API)
local function GetEntry(i)
	if C_QuestLog and C_QuestLog.GetInfo then
		local info = C_QuestLog.GetInfo(i)
		if info then return info.title, info.isHeader, info.isCollapsed, info.questID end
	elseif GetQuestLogTitle then
		local title, _, _, isHeader, isCollapsed, _, _, questID = GetQuestLogTitle(i)
		return title, isHeader, isCollapsed, questID
	end
end

local function SetHeaderCollapsed(i, collapsed)
	local fn
	if collapsed then
		fn = (C_QuestLog and C_QuestLog.CollapseQuestHeader) or CollapseQuestHeader
	else
		fn = (C_QuestLog and C_QuestLog.ExpandQuestHeader) or ExpandQuestHeader
	end
	if fn then fn(i) end
end

local function IsDone(id)
	local fn = (C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted) or IsQuestFlaggedCompleted
	return fn and fn(id) and true or false
end

local function IsActive(id)
	if C_QuestLog and C_QuestLog.IsOnQuest then return C_QuestLog.IsOnQuest(id) and true or false end
	return GetQuestLogIndexByID and (GetQuestLogIndexByID(id) or 0) > 0 or false
end

-- Liest ein QuestieDB-Feld; Listenfelder liefern eine Liste oder nil, Zahlenfelder 0.
local function DbField(id, key)
	local ok, value = pcall(_G.QuestDB.Get, id, key)
	return ok and value or nil
end

local function AnyDone(list)
	for _, q in ipairs(list) do if IsDone(q) then return true end end
	return false
end

-- Pruefung ueber die Daten des Addons QuestieDB (optional): Vorquests, ausschliessende
-- Quests, Folgequest bereits erreicht, Mindeststufe. Nil = unbekannt.
local function CanAcceptByQuestieDB(id)
	local db = _G.QuestDB
	if not (db and db.Get and db.Exists) then return nil end
	local ok, exists = pcall(db.Exists, id)
	if not (ok and exists) then return nil end

	local single, group = DbField(id, "preQuestSingle"), DbField(id, "preQuestGroup")
	if type(single) == "table" and #single > 0 then
		if not AnyDone(single) then return false end -- keine der Alternativ-Vorquests erledigt
	elseif type(group) == "table" then
		for _, q in ipairs(group) do
			if not IsDone(q) then return false end -- alle Gruppen-Vorquests noetig
		end
	end

	local exclusive = DbField(id, "exclusiveTo")
	if type(exclusive) == "table" then
		for _, q in ipairs(exclusive) do
			if IsDone(q) or IsActive(q) then return false end
		end
	end

	local nextInChain = DbField(id, "nextQuestInChain")
	if type(nextInChain) == "number" and nextInChain > 0 and (IsDone(nextInChain) or IsActive(nextInChain)) then
		return false -- schon weiter in der Questkette
	end

	local minLevel = DbField(id, "requiredLevel")
	if type(minLevel) == "number" and minLevel > 0 and UnitLevel("player") < minLevel then return false end
	return true
end

-- Kann ICH diese Quest annehmen (Vorquest erfuellt, Stufe, ...)? Dafuer gibt es
-- keine Blizzard-API. Reihenfolge: QuestieDB-Daten, sonst Questie (IsDoable), sonst
-- "ja" (unbekannt; dann lernen wir aus der Fehlermeldung beim Teilen).
local acceptCache = {}
local function CanAccept(id)
	local c = acceptCache[id]
	if c and GetTime() - c.t < 30 then return c.value end
	local value = true
	local byDb = CanAcceptByQuestieDB(id)
	if byDb ~= nil then
		value = byDb
	else
		local loader = _G.QuestieLoader
		if loader and loader.ImportModule then
			local ok, qdb = pcall(loader.ImportModule, loader, "QuestieDB")
			if ok and qdb and qdb.IsDoable then
				local ok2, doable = pcall(qdb.IsDoable, id)
				if ok2 and doable == false then value = false end
			end
		end
	end
	acceptCache[id] = { value = value, t = GetTime() }
	return value
end

local function CurrentZone()
	return (GetRealZoneText and GetRealZoneText()) or (GetZoneText and GetZoneText()) or ""
end

-- Zonennamen sind je Client-Sprache uebersetzt und taugen nicht zum Vergleich
-- zwischen Spielern. Stattdessen wird die UiMapID der Zone gesendet (bei
-- Mikro-/Dungeonkarten die uebergeordnete Zonenkarte). Ohne C_Map: Name.
local ZONE_MAPTYPE = (Enum and Enum.UIMapType and Enum.UIMapType.Zone) or 3

local function ZoneKey()
	if C_Map and C_Map.GetBestMapForUnit then
		local id = C_Map.GetBestMapForUnit("player")
		if id then
			for _ = 1, 10 do
				local info = C_Map.GetMapInfo(id)
				if info and info.mapType and info.mapType > ZONE_MAPTYPE and info.parentMapID and info.parentMapID > 0 then
					id = info.parentMapID
				else
					break
				end
			end
			return "m" .. id
		end
	end
	return "n:" .. CurrentZone()
end

-- Lesbarer Name zu einem Schluessel, in der Sprache des eigenen Clients.
local function ZoneLabel(key)
	local id = key:match("^m(%d+)$")
	if id and C_Map and C_Map.GetMapInfo then
		local info = C_Map.GetMapInfo(tonumber(id))
		if info and info.name then return info.name end
	end
	return (key:gsub("^n:", ""))
end

-- Klappt zugeklappte Kategorien kurz auf (sonst fehlen deren Quests in der
-- Liste), liest die Quests der aktuellen Zone und klappt wieder zu.
local function ScanQuests()
	local zone = CurrentZone()
	local key = ZoneKey()
	local mapName = ZoneLabel(key)
	local ids, titles = {}, {}

	local reopened = {}
	for i = NumEntries(), 1, -1 do
		local title, isHeader, isCollapsed = GetEntry(i)
		if isHeader and isCollapsed then
			SetHeaderCollapsed(i, false)
			reopened[title] = true
		end
	end

	local inZone = false
	for i = 1, NumEntries() do
		local title, isHeader, _, questID = GetEntry(i)
		if isHeader then
			inZone = (title == zone or title == mapName)
		elseif inZone and questID and questID > 0 then
			ids[questID] = true
			titles[questID] = title
		end
	end

	for i = NumEntries(), 1, -1 do
		local title, isHeader = GetEntry(i)
		if isHeader and reopened[title] then
			SetHeaderCollapsed(i, true)
		end
	end

	return zone, ids, titles, key
end

local function SortedIds(ids)
	local list = {}
	for id in pairs(ids) do list[#list + 1] = id end
	table.sort(list)
	return list
end

---------------------------------------------------------------------------
-- Kommunikation
---------------------------------------------------------------------------

-- Gleiche Logik wie SexyInterrupter: INSTANCE_CHAT nur bei Dungeonfinder-/
-- Schlachtfeldgruppen. IsInGroup(LE_PARTY_CATEGORY_INSTANCE) darf hier NICHT
-- benutzt werden: ist die Konstante auf dem Client nil, zaehlt der Aufruf wie
-- IsInGroup() und es ginge faelschlich immer an INSTANCE_CHAT (kommt nie an).
local function GroupChannel()
	if not IsInGroup() and not IsInRaid() then return nil end
	local _, instanceType = IsInInstance()
	if instanceType == "pvp" or (IsPartyLFG and IsPartyLFG()) then return "INSTANCE_CHAT" end
	if IsInRaid() then return "RAID" end
	return "PARTY"
end

local sendCount, lastSendResult = 0, nil
local function Send(msg, channel)
	local fn = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
	sendCount = sendCount + 1
	lastSendResult = fn(PREFIX, msg, channel)
end

local BroadcastProgress

local function Broadcast()
	local channel = GroupChannel()
	if not channel then return end

	local zone = myZoneKey:gsub("|", "")
	local list = SortedIds(myIds)
	local first = true
	local chunk = ""

	local function flush()
		Send((first and ("H|" .. zone .. "|") or "A|") .. chunk, channel)
		first, chunk = false, ""
	end

	for _, id in ipairs(list) do
		local s = tostring(id)
		if #chunk + #s + 1 > CHUNK_SIZE then flush() end
		chunk = (chunk == "") and s or (chunk .. "," .. s)
	end
	-- Auch eine leere Liste senden, damit andere "keine Quests" von "kein Addon" unterscheiden.
	if first or chunk ~= "" then flush() end
	-- Version separat senden: aeltere Clients ignorieren unbekannte Nachrichtentypen.
	Send("V|" .. VERSION, channel)
	if BroadcastProgress then BroadcastProgress() end
end

-- Zwei Dinge kann nur der jeweils ANDERE wissen: ob er eine Quest aus unserer
-- Liste schon abgegeben hat (Folgequest!) und ob er sie ueberhaupt annehmen
-- koennte (Vorquest fehlt). Deshalb melden wir ihm nach jeder empfangenen Liste,
-- welche Quests aus SEINER Liste wir schon abgeschlossen haben ("C"/"E") bzw.
-- nicht annehmen koennen ("N"/"O"). Er blendet sie aus seinen Unterschieden aus.
local function SendIdList(first, cont, list, channel)
	local isFirst, chunk = true, ""
	local function flush()
		Send((isFirst and first or cont) .. "|" .. chunk, channel)
		isFirst, chunk = false, ""
	end
	for _, id in ipairs(list) do
		local s = tostring(id)
		if #chunk + #s + 1 > CHUNK_SIZE then flush() end
		chunk = (chunk == "") and s or (chunk .. "," .. s)
	end
	if isFirst or chunk ~= "" then flush() end -- auch leer senden: setzt alte Meldungen zurueck
end

-- Zieltexte meiner Quests ("Id=Ziel~Ziel", Quests durch ^ getrennt). Die Trennzeichen kommen in Zieltexten
-- nicht vor (werden sonst entfernt), Kommas dagegen schon, darum nicht wie die Id-Listen mit Komma getrennt.
local function SendDetails(channel)
	local list = {}
	for _, id in ipairs(SortedIds(myIds)) do
		local p = myProgress[id]
		if p and p.objs and #p.objs > 0 then
			local parts = {}
			for i = 1, math.min(#p.objs, 4) do
				parts[#parts + 1] = (tostring(p.objs[i]):gsub("[|~%^=]", ""):sub(1, 44))
			end
			list[#list + 1] = id .. "=" .. table.concat(parts, "~")
		end
	end
	local isFirst, chunk = true, ""
	local function flush()
		Send((isFirst and "D|" or "F|") .. chunk, channel)
		isFirst, chunk = false, ""
	end
	for _, entry in ipairs(list) do
		if chunk ~= "" and #chunk + #entry + 1 > CHUNK_SIZE then flush() end
		chunk = (chunk == "") and entry or (chunk .. "^" .. entry)
	end
	if isFirst or chunk ~= "" then flush() end
end

-- Fortschritt meiner Quests ("Id=Prozent", ein angehaengtes r heisst: nur noch abzugeben). Aeltere
-- Clients ignorieren die unbekannten Nachrichtentypen "P", "S", "D" und "F".
local lastProgressSent, lastProgressAt = "", 0
function BroadcastProgress()
	local channel = GroupChannel()
	if not channel then return end
	local list = {}
	for _, id in ipairs(SortedIds(myIds)) do
		local p = myProgress[id]
		if p then list[#list + 1] = id .. "=" .. p.pct .. (p.ready and "r" or "") end
	end
	local text = table.concat(list, ",")
	if text == lastProgressSent and GetTime() - lastProgressAt < 2 then return end
	lastProgressSent, lastProgressAt = text, GetTime()
	SendIdList("P", "S", list, channel)
	SendDetails(channel)
end

local replyPending = {}
local function ScheduleDoneReply(name)
	if replyPending[name] then return end
	replyPending[name] = true
	C_Timer.After(1.5, function()
		replyPending[name] = nil
		local m, channel = members[name], GroupChannel()
		if not m or not channel then return end
		local done, blocked = {}, {}
		for id in pairs(m.ids) do
			if IsDone(id) then
				done[#done + 1] = id
			elseif not myIds[id] and not CanAccept(id) then
				blocked[#blocked + 1] = id
			end
		end
		table.sort(done); table.sort(blocked)
		SendIdList("C", "E", done, channel)
		SendIdList("N", "O", blocked, channel)
	end)
end

local function OnAddonMessage(prefix, msg, _, sender)
	anyAddonMsgs = anyAddonMsgs + 1
	if prefix ~= PREFIX then return end
	-- Realm-Suffix ("Name-Realm", auf Forever teils mit abgekuerztem/doppeltem Realm) abschneiden
	-- Forever liefert "Name Realm" (Leerzeichen), Retail "Name-Realm"
	local name = tostring(sender):match("^([^%s%-]+)") or tostring(sender)
	if name == UnitName("player") then return end
	recvCount, lastRecv = recvCount + 1, tostring(sender)

	local kind, rest = msg:match("^(%a)|(.*)$")
	if kind == "H" then
		local zone, idStr = rest:match("^([^|]*)|(.*)$")
		if not zone then return end
		members[name] = { zone = zone, ids = {} }
		rest = idStr
	elseif kind == "A" then
		if not members[name] then return end
	elseif kind == "R" then
		-- Anfrage eines Mitglieds, das uns noch nicht kennt: Liste erneut senden
		if GetTime() - lastReply > 3 then
			lastReply = GetTime()
			Broadcast()
		end
		return
	elseif kind == "V" then
		versions[name] = rest
		Refresh()
		return
	elseif kind == "P" or kind == "S" then
		if kind == "P" or not progressBy[name] then progressBy[name] = {} end
		for id, pct, r in rest:gmatch("(%d+)=(%d+)(r?)") do
			progressBy[name][tonumber(id)] = { pct = tonumber(pct), ready = r == "r" }
		end
		Refresh()
		return
	elseif kind == "D" or kind == "F" then
		if kind == "D" or not detailsBy[name] then detailsBy[name] = {} end
		for entry in rest:gmatch("[^%^]+") do
			local id, objs = entry:match("^(%d+)=(.*)$")
			if id then
				local list = {}
				for text in objs:gmatch("[^~]+") do list[#list + 1] = text end
				detailsBy[name][tonumber(id)] = list
			end
		end
		Refresh()
		return
	elseif kind == "C" or kind == "E" or kind == "N" or kind == "O" then
		local store = (kind == "C" or kind == "E") and completedBy or blockedBy
		if kind == "C" or kind == "N" or not store[name] then store[name] = {} end
		for id in rest:gmatch("%d+") do store[name][tonumber(id)] = true end
		Refresh()
		return
	else
		return
	end

	for id in rest:gmatch("%d+") do
		members[name].ids[tonumber(id)] = true
	end
	ScheduleDoneReply(name)
	Refresh()
end

---------------------------------------------------------------------------
-- Anzeige
---------------------------------------------------------------------------

local WIDTH = 376
local pendingSig, pendingSince -- noch nicht angezeigter Unterschied und seit wann er besteht
local forceShow = false     -- per /sqh erzwungen (auch ohne Unterschiede)
local SetTestMode           -- schaltet das simulierte Gruppenmitglied (/sqh test, Edit Mode)
local editPreview = false   -- Testdaten laufen nur wegen des Edit Mode
local dismissedSig = nil    -- Unterschiede, die der Nutzer weggeklickt hat
local scanReady = false     -- erst nach dem Login-Abgleich (siehe PLAYER_LOGIN) darf das Fenster von selbst aufgehen
local rowPool = {}
local requested = {}

local function QuestName(id)
	if myTitles[id] then return myTitles[id] end
	local title = C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id)
	if title then return title end
	if C_QuestLog and C_QuestLog.RequestLoadQuestByID and not requested[id] then
		requested[id] = true
		C_QuestLog.RequestLoadQuestByID(id) -- Antwort: QUEST_DATA_LOAD_RESULT -> Refresh
	end
	return "Quest " .. id
end

local function QuestLink(id)
	local link = GetQuestLink and GetQuestLink(id)
	if link then return link end
	return ("|cffffff00|Hquest:%d:%d|h[%s]|h|r"):format(id, UnitLevel("player"), QuestName(id))
end

local function QuestLogIndex(id)
	local index = (C_QuestLog and C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(id))
		or (GetQuestLogIndexByID and GetQuestLogIndexByID(id))
	return (index and index > 0) and index or nil
end

local function InGroup()
	return IsInGroup() or IsInRaid()
end

-- Retail kann die Teilbarkeit direkt abfragen. Im Legacy-Client geht das nur
-- ueber die Auswahl im Questlog, die wir nicht bei jedem Refresh veraendern
-- wollen - dort wird der Button angezeigt und erst beim Klick geprueft.
-- Fortschritt einer Quest: Prozent (alle Ziele zusammen), ob sie nur noch abzugeben ist und die Zieltexte
-- ("Wolf getoetet: 3/8"). Die Texte brauchen die anderen, weil sie eine schon abgegebene Quest selbst
-- nicht mehr lesen koennen.
local function QuestProgress(id)
	local ready = false
	if C_QuestLog and C_QuestLog.IsComplete then
		-- Rueckgabe je Client true/1 (fertig), nil/false (offen) oder -1 (gescheitert): nur fertig zaehlt
		local c = C_QuestLog.IsComplete(id)
		ready = (c == true or c == 1)
	elseif IsQuestComplete then
		local c = IsQuestComplete(id)
		ready = (c == true or c == 1)
	end
	local done, need = 0, 0
	local texts = {}
	if C_QuestLog and C_QuestLog.GetQuestObjectives then
		local ok, objectives = pcall(C_QuestLog.GetQuestObjectives, id)
		if ok and type(objectives) == "table" then
			for _, o in ipairs(objectives) do
				local required = tonumber(o.numRequired) or 0
				if required > 0 then
					need = need + required
					done = done + math.min(tonumber(o.numFulfilled) or 0, required)
				end
				if type(o.text) == "string" and o.text ~= "" then texts[#texts + 1] = o.text end
			end
		end
	else
		local index = QuestLogIndex(id)
		if index and GetNumQuestLeaderBoards and GetQuestLogLeaderBoard then
			for i = 1, GetNumQuestLeaderBoards(index) do
				local text = GetQuestLogLeaderBoard(i, index)
				text = tostring(text or "")
				local a, b = text:match("(%d+)/(%d+)")
				if a and b and tonumber(b) > 0 then
					need = need + tonumber(b)
					done = done + math.min(tonumber(a), tonumber(b))
				end
				if text ~= "" then texts[#texts + 1] = text end
			end
		end
	end
	if ready then return 100, true, texts end
	if need > 0 then return math.floor(done * 100 / need), false, texts end
	return 0, false, texts
end

local function ComputeProgress(ids)
	local result = {}
	for id in pairs(ids) do
		local pct, ready, texts = QuestProgress(id)
		result[id] = { pct = pct, ready = ready, objs = texts }
	end
	return result
end

local function CanShare(id)
	if not myIds[id] or not InGroup() or testMode then return false end
	if C_QuestLog and C_QuestLog.IsPushableQuest then return C_QuestLog.IsPushableQuest(id) and true or false end
	return true
end

local lastShare -- { id, t }: zuletzt geteilte Quest, um Fehlermeldungen zuzuordnen

-- Im Kampf lassen sich Quests nicht teilen: Der Knopf ist dann grau und wirkungslos
local function InCombat() return InCombatLockdown() or UnitAffectingCombat("player") end

local function UpdateShareButton(btn)
	local off = InCombat() and true or false
	btn.disabled = off
	if off then
		btn.bg:SetColorTexture(0.2, 0.18, 0.15, 1)
		btn.text:SetTextColor(0.5, 0.47, 0.42)
		btn.text:SetText(T("Kampf", "Combat")) -- Hinweis, warum der Knopf aus ist
		btn.hl:Hide()
	else
		btn.bg:SetColorTexture(0.184, 0.42, 0.235, 1)
		btn.text:SetTextColor(1, 1, 1)
		btn.text:SetText(T("Teilen", "Share"))
		btn.hl:Show()
	end
end

local function ShareQuest(id)
	if InCombat() then
		print("SexyQuestHelper: " .. T("Im Kampf kann nicht geteilt werden.", "Cannot share while in combat."))
		return
	end
	local index = QuestLogIndex(id)
	if not index then return end
	if C_QuestLog and C_QuestLog.SetSelectedQuest then
		C_QuestLog.SetSelectedQuest(id)
	elseif SelectQuestLogEntry then
		SelectQuestLogEntry(index)
	end
	if not (C_QuestLog and C_QuestLog.IsPushableQuest) and GetQuestLogPushable and not GetQuestLogPushable() then
		print("SexyQuestHelper: " .. T("Diese Quest kann nicht geteilt werden.", "This quest cannot be shared."))
		return
	end
	local ok, err = pcall(QuestLogPushQuest)
	lastShare = { id = id, t = GetTime() }
	-- Erfolg bleibt still (die Quest erscheint beim Mitglied); nur ein Fehler wird gemeldet
	if not ok then
		print("SexyQuestHelper: " .. tostring(err))
	end
end

-- Fehlermeldungen beim Teilen ("X is not eligible for that quest" usw.) merken wir
-- uns: die Quest ist fuer dieses Mitglied nicht annehmbar, der Button und der
-- Unterschied verschwinden. Das greift auch ohne Questie, nach dem ersten Versuch.
local function ToPattern(fmt)
	local p = fmt:gsub("([%%%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
	p = p:gsub("%%%%s", "(.+)")
	return "^" .. p .. "$"
end

local pushErrorPatterns = {}
for _, key in ipairs({ "ERR_QUEST_PUSH_INVALID_S", "ERR_QUEST_PUSH_ALREADY_DONE_S", "ERR_QUEST_PUSH_ONQUEST_S" }) do
	if type(_G[key]) == "string" then pushErrorPatterns[#pushErrorPatterns + 1] = ToPattern(_G[key]) end
end

local function OnSystemMessage(msg)
	if not lastShare or GetTime() - lastShare.t > 15 or type(msg) ~= "string" then return end
	for _, pattern in ipairs(pushErrorPatterns) do
		local who = msg:match(pattern)
		if who then
			local name = who:match("^([^%s%-]+)") or who
			learnedBlocked[name] = learnedBlocked[name] or {}
			learnedBlocked[name][lastShare.id] = true
			Refresh()
			return
		end
	end
end

local function OpenQuest(id)
	if IsShiftKeyDown() then
		if not ChatEdit_InsertLink(QuestLink(id)) then
			print("SexyQuestHelper: " .. QuestLink(id))
		end
		return
	end
	if not myIds[id] then
		print("SexyQuestHelper: " .. QuestLink(id) .. " - " .. T("nicht in deinem Questlog.", "not in your quest log."))
		return
	end
	if QuestMapFrame_OpenToQuestDetails then -- Retail-Stil
		pcall(QuestMapFrame_OpenToQuestDetails, id)
		return
	end
	local index = QuestLogIndex(id)
	if index then -- Classic-Stil
		if QuestLog_SetSelection then pcall(QuestLog_SetSelection, index)
		elseif SelectQuestLogEntry then pcall(SelectQuestLogEntry, index) end
		if QuestLogFrame then ShowUIPanel(QuestLogFrame) elseif ToggleQuestLog then ToggleQuestLog() end
	end
end

-- Vergleicht zwei Versionen "a.b.c": -1, 0 oder 1
local function CompareVersions(x, y)
	local ax, ay = {}, {}
	for n in tostring(x):gmatch("%d+") do ax[#ax + 1] = tonumber(n) end
	for n in tostring(y):gmatch("%d+") do ay[#ay + 1] = tonumber(n) end
	for i = 1, math.max(#ax, #ay) do
		local dx, dy = ax[i] or 0, ay[i] or 0
		if dx ~= dy then return dx < dy and -1 or 1 end
	end
	return 0
end

local unitByName = {}

local function GroupNames()
	wipe(unitByName)
	local names = {}
	local me = UnitName("player")
	local prefix, count = "party", GetNumSubgroupMembers()
	if IsInRaid() then prefix, count = "raid", GetNumGroupMembers() end
	for i = 1, count do
		local name = UnitName(prefix .. i)
		if name and name ~= me then
			names[#names + 1] = name
			unitByName[name] = prefix .. i
		end
	end
	if testMode then names[#names + 1] = "Testmate" end
	return names
end

-- Klassenfarbe eines Mitglieds (weiss, wenn die Klasse unbekannt ist)
local function ClassFile(name)
	local unit = unitByName[name]
	if not unit then return nil end
	-- nicht "unit and UnitClass(unit)": "and" schneidet auf EINEN Rueckgabewert ab
	local _, classFile = UnitClass(unit)
	return classFile
end

local function ClassColor(name)
	local class = ClassFile(name)
	local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if c then return c.r, c.g, c.b end
	return 1, 1, 1
end

-- Setzt ein Klassenicon auf die Textur; ohne Icon-Daten eine Flaeche in Klassenfarbe.
local function SetClassIcon(tex, name)
	local class = ClassFile(name)
	local coords = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
	if coords then
		tex:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
		tex:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
		return
	end
	local atlas = class and ("classicon-" .. class:lower())
	if atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
		tex:SetAtlas(atlas)
		tex:SetTexCoord(0, 1, 0, 1)
		return
	end
	local r, g, b = ClassColor(name)
	tex:SetColorTexture(r, g, b, 1)
	tex:SetTexCoord(0, 1, 0, 1)
end

-- Spielername als Text in Klassenfarbe
local function ColoredName(name)
	local r, g, b = ClassColor(name)
	return ("|cff%02x%02x%02x%s|r"):format(r * 255, g * 255, b * 255, name)
end

-- Schriften: Marcellus fuer den Titel, Inter fuer Text (beide SIL OFL, Lizenzen in
-- media/fonts). Fehlt eine Datei oder braucht die Clientsprache andere Zeichen
-- (Kyrillisch, Asiatisch), gilt die Spielschrift. SetFont meldet false, wenn die
-- Datei nicht geladen werden kann.
local probe = CreateFont("SexyQuestHelperFontProbe")
local function LoadFont(file)
	local loc = GetLocale()
	if loc == "ruRU" or loc == "koKR" or loc == "zhCN" or loc == "zhTW" then return STANDARD_TEXT_FONT end
	local path = "Interface\\AddOns\\SexyQuestHelper\\media\\fonts\\" .. file
	if probe:SetFont(path, 12, "") == false then return STANDARD_TEXT_FONT end
	return path
end

local function MakeFont(name, file, size, r, g, b)
	local f = CreateFont(name)
	f:SetFont(LoadFont(file), size, "")
	f:SetTextColor(r, g, b)
	f:SetShadowColor(0, 0, 0, 1)
	f:SetShadowOffset(1, -1)
end
MakeFont("SexyQuestHelperTitle", "Marcellus-Regular.ttf", 14, 0.91, 0.76, 0.42)
MakeFont("SexyQuestHelperText", "Inter.ttf", 13, 0.95, 0.92, 0.86)
MakeFont("SexyQuestHelperSmall", "Inter.ttf", 11, 0.95, 0.92, 0.86)

-- Farben der Etiketten (Pillen) und Zeilenhoehen. Entwurf "A: Spielerkarten".
local HEADER_H, QUEST_H, INFO_H, CARD_GAP, BAND_H = 30, 24, 20, 8, 30
local TONES = {
	ok = { bg = { 0.082, 0.188, 0.11 }, fg = { 0.48, 0.88, 0.56 } },
	warn = { bg = { 0.227, 0.173, 0.063 }, fg = { 0.94, 0.75, 0.29 } },
	grey = { bg = { 0.16, 0.145, 0.12 }, fg = { 0.66, 0.61, 0.54 } },
	lack = { bg = { 0.231, 0.102, 0.09 }, fg = { 1, 0.6, 0.56 } },
	they = { bg = { 0.078, 0.157, 0.227 }, fg = { 0.53, 0.8, 1 } },
}

local function CountText(n)
	if n == 1 then return T("1 Unterschied", "1 difference") end
	return n .. " " .. T("Unterschiede", "differences")
end

-- Liefert die Eintraege fuers Fenster, ob es Quest-Unterschiede gibt und deren Signatur.
-- Eintrag: { kind = "header"|"quest"|"info", ... }. Automatisch geoeffnet (showAll = false)
-- zeigt nur Spieler mit Unterschieden, manuell geoeffnet (showAll = true) alle Spieler.
local function BuildEntries(showAll)
	local entries, sigParts, hasDiff = {}, {}, false
	local inGroup = GroupChannel() or testMode

	if inGroup then
		for _, name in ipairs(GroupNames()) do
			local m = members[name]
			if m then -- Mitglieder ohne Addon werden nicht angezeigt (siehe /sqh version)
				if m.zone ~= myZoneKey then
					if showAll then
						entries[#entries + 1] = { kind = "header", name = name, tone = "grey",
							status = T("anderes Gebiet", "different zone") .. " (" .. ZoneLabel(m.zone) .. ")" }
					end
				else
					local iLack, theyLack = {}, {}
					local theirDone = completedBy[name]
					for id in pairs(m.ids) do
						-- hat er, ich nicht - aber ich habe sie schon abgegeben oder kann sie nicht annehmen: kein Unterschied
						if not myIds[id] and not IsDone(id) and CanAccept(id) then iLack[#iLack + 1] = id end
					end
					for id in pairs(myIds) do
						-- habe ich, er nicht - aber er hat sie schon abgegeben oder kann sie nicht annehmen: kein Unterschied
						if not m.ids[id] and not (theirDone and theirDone[id])
							and not (blockedBy[name] and blockedBy[name][id])
							and not (learnedBlocked[name] and learnedBlocked[name][id]) then
							theyLack[#theyLack + 1] = id
						end
					end
					table.sort(iLack); table.sort(theyLack)

					if #iLack + #theyLack == 0 then
						if showAll then
							entries[#entries + 1] = { kind = "header", name = name, tone = "ok", status = T("Alles gleich", "In sync") }
						end
					else
						hasDiff = true
						sigParts[#sigParts + 1] = name .. ":" .. table.concat(iLack, ",") .. "/" .. table.concat(theyLack, ",")
						entries[#entries + 1] = { kind = "header", name = name, tone = "warn", status = CountText(#iLack + #theyLack) }
						for _, id in ipairs(iLack) do
							entries[#entries + 1] = { kind = "quest", id = id, tone = "lack", label = T("Dir fehlt", "You lack") }
						end
						for _, id in ipairs(theyLack) do
							entries[#entries + 1] = { kind = "quest", id = id, tone = "they", label = T("Hat nicht", "Lacks"), share = CanShare(id) }
						end
					end
				end
			end
		end
	end

	if #entries == 0 and showAll then
		entries[1] = { kind = "info", text = (not inGroup) and T("Nicht in einer Gruppe.", "Not in a group.")
			or T("Kein Gruppenmitglied mit Addon.", "No group member has the addon.") }
	end
	return entries, hasDiff, table.concat(sigParts, ";")
end

local function MakePill(parent)
	local pill = {}
	pill.tex = parent:CreateTexture(nil, "ARTWORK")
	pill.text = parent:CreateFontString(nil, "OVERLAY", "SexyQuestHelperSmall")
	pill.text:SetPoint("CENTER", pill.tex, "CENTER", 0, 0)
	return pill
end

local function SetPill(pill, tone, text, width, height)
	local t = TONES[tone]
	pill.tex:SetColorTexture(t.bg[1], t.bg[2], t.bg[3], 1)
	pill.text:SetTextColor(t.fg[1], t.fg[2], t.fg[3])
	pill.text:SetText(text)
	pill.tex:SetSize(width or (pill.text:GetStringWidth() + 18), height)
	pill.tex:Show()
	pill.text:Show()
end

local function HidePill(pill)
	pill.tex:Hide()
	pill.text:Hide()
end

local function GetRow(i)
	local row = rowPool[i]
	if row then return row end

	row = CreateFrame("Button", nil, ui)
	row:RegisterForClicks("LeftButtonUp")

	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints()
	row.bg:SetColorTexture(0.145, 0.125, 0.10, 1)
	row.divider = row:CreateTexture(nil, "BORDER")
	row.divider:SetPoint("TOPLEFT")
	row.divider:SetPoint("TOPRIGHT")
	row.divider:SetHeight(1)
	row.divider:SetColorTexture(0.21, 0.19, 0.14, 1)
	row.hl = row:CreateTexture(nil, "HIGHLIGHT")
	row.hl:SetAllPoints()
	row.hl:SetColorTexture(1, 1, 1, 0.08)

	-- Kopfzeile eines Spielers: Klassenicon, Name (Klassenfarbe), Status
	row.avatar = row:CreateTexture(nil, "ARTWORK")
	row.avatar:SetSize(20, 20)
	row.avatar:SetPoint("LEFT", row, "LEFT", 8, 0)
	row.status = MakePill(row)
	row.status.tex:SetPoint("RIGHT", row, "RIGHT", -8, 0)
	row.name = row:CreateFontString(nil, "OVERLAY", "SexyQuestHelperText")
	row.name:SetPoint("LEFT", row.avatar, "RIGHT", 8, 0)
	row.name:SetPoint("RIGHT", row.status.tex, "LEFT", -6, 0)
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)

	-- Questzeile: Etikett, Name, Teilen-Button
	row.kind = MakePill(row)
	row.kind.tex:SetPoint("LEFT", row, "LEFT", 8, 0)
	row.fs = row:CreateFontString(nil, "OVERLAY", "SexyQuestHelperSmall")
	row.fs:SetJustifyH("LEFT")
	row.fs:SetWordWrap(false)

	row.share = CreateFrame("Button", nil, row)
	row.share:SetSize(52, QUEST_H - 6)
	row.share:SetPoint("RIGHT", row, "RIGHT", -8, 0)
	row.share.bg = row.share:CreateTexture(nil, "BACKGROUND")
	row.share.bg:SetAllPoints()
	row.share.bg:SetColorTexture(0.184, 0.42, 0.235, 1)
	row.share.hl = row.share:CreateTexture(nil, "HIGHLIGHT")
	row.share.hl:SetAllPoints()
	row.share.hl:SetColorTexture(1, 1, 1, 0.25)
	row.share.text = row.share:CreateFontString(nil, "OVERLAY", "SexyQuestHelperSmall")
	row.share.text:SetAllPoints()
	row.share.text:SetText(T("Teilen", "Share"))
	row.share:RegisterForClicks("LeftButtonUp")
	row.share:SetScript("OnClick", function()
		if row.questId then ShareQuest(row.questId) end
	end)
	row.share:SetScript("OnEnter", function(self)
		if not self.disabled then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(T("Im Kampf nicht möglich", "Not possible in combat"))
		GameTooltip:Show()
	end)
	row.share:SetScript("OnLeave", function() GameTooltip:Hide() end)
	row.share:Hide()

	row:SetScript("OnEnter", function(self)
		if not self.questId then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, ("quest:%d:%d"):format(self.questId, UnitLevel("player")))
		if not ok then
			GameTooltip:ClearLines()
			GameTooltip:AddLine(QuestName(self.questId))
		end
		GameTooltip:AddLine(T("Klick: im Questlog öffnen", "Click: open in quest log"), 0.6, 0.6, 0.6)
		GameTooltip:AddLine(T("Shift-Klick: Link in den Chat", "Shift-click: link into chat"), 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	row:SetScript("OnClick", function(self)
		if self.questId then OpenQuest(self.questId) end
	end)

	rowPool[i] = row
	return row
end

local function ConfigureRow(row, e)
	local isHeader, isQuest = e.kind == "header", e.kind == "quest"
	row.questId = e.id
	row:EnableMouse(isQuest)
	row.bg:SetShown(e.kind ~= "info")
	row.divider:SetShown(isQuest)

	row.avatar:SetShown(isHeader)
	row.name:SetShown(isHeader)
	if isHeader then
		local r, g, b = ClassColor(e.name)
		SetClassIcon(row.avatar, e.name)
		row.name:SetText(e.name)
		row.name:SetTextColor(r, g, b)
		SetPill(row.status, e.tone, e.status, nil, 18)
	else
		HidePill(row.status)
	end

	if isQuest then
		SetPill(row.kind, e.tone, e.label, 66, 16)
	else
		HidePill(row.kind)
	end

	row.fs:SetShown(not isHeader)
	row.fs:ClearAllPoints()
	if isQuest then
		row.fs:SetText(QuestName(e.id))
		row.fs:SetPoint("LEFT", row, "LEFT", 82, 0)
		row.fs:SetPoint("RIGHT", row, "RIGHT", e.share and -66 or -8, 0)
	elseif e.kind == "info" then
		row.fs:SetText("|cff9b9180" .. e.text .. "|r")
		row.fs:SetPoint("LEFT", row, "LEFT", 8, 0)
		row.fs:SetPoint("RIGHT", row, "RIGHT", -8, 0)
	end
	row.share:SetShown(e.share and true or false)
	UpdateShareButton(row.share)
end

local function CreateUI()
	local f = CreateFrame("Frame", "SexyQuestHelperFrame", UIParent, "BackdropTemplate")
	f:SetSize(WIDTH, 60)
	f:SetFrameStrata("MEDIUM")
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	f:SetBackdropColor(0.08, 0.065, 0.05, 0.96)
	f:SetBackdropBorderColor(0.42, 0.34, 0.15, 1)

	-- Position: SexyEditMode speichert die untere linke Ecke in SexyQuestHelperDB.editMode.
	-- Eine frühere Position (SexyQuestHelperDB.pos, beliebiger Ankerpunkt) wird einmalig umgerechnet,
	-- wobei die Oberkante gleich bleibt (Fensterhöhe damals unbekannt: Starthöhe 60).
	local db = SexyQuestHelperDB.editMode
	if not db then
		db = {}
		SexyQuestHelperDB.editMode = db
		local screenW, screenH = UIParent:GetWidth(), UIParent:GetHeight()
		local pos = SexyQuestHelperDB.pos
		if pos and pos.point then
			local relPoint = pos.relPoint or pos.point
			local ax = relPoint:find("LEFT") and 0 or (relPoint:find("RIGHT") and screenW or screenW / 2)
			local ay = relPoint:find("BOTTOM") and 0 or (relPoint:find("TOP") and screenH or screenH / 2)
			local ox = pos.point:find("LEFT") and 0 or (pos.point:find("RIGHT") and WIDTH or WIDTH / 2)
			local oy = pos.point:find("BOTTOM") and 0 or (pos.point:find("TOP") and 60 or 30)
			db.x, db.y = ax + (pos.x or 0) - ox, ay + (pos.y or 0) - oy
		else
			db.x, db.y = (screenW - WIDTH) / 2, screenH / 2 + 200 - 30
		end
		db.anchoredHeight = 60
		SexyQuestHelperDB.pos = nil
	end
	f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", db.x, db.y)

	-- Das Fenster bleibt jederzeit ziehbar; gespeichert wird über die Bibliothek
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SEM:SetPosition(self, self:GetLeft(), self:GetBottom())
		db.anchoredHeight = self:GetHeight()
	end)

	f.band = f:CreateTexture(nil, "BACKGROUND")
	f.band:SetPoint("TOPLEFT", f, "TOPLEFT", 3, -3)
	f.band:SetPoint("TOPRIGHT", f, "TOPRIGHT", -3, -3)
	f.band:SetHeight(BAND_H - 3)
	f.band:SetColorTexture(0.15, 0.12, 0.07, 1)

	f.title = f:CreateFontString(nil, "OVERLAY", "SexyQuestHelperTitle")
	f.title:SetPoint("TOPLEFT", 12, -9)
	f.title:SetText("SexyQuestHelper")
	-- Gebiet als Badge ganz rechts in der Titelleiste (links vom Schliessen-Kreuz)
	f.zoneBg = f:CreateTexture(nil, "ARTWORK")
	f.zoneBg:SetPoint("TOPRIGHT", f, "TOPRIGHT", -30, -7)
	f.zoneBg:SetHeight(18)
	f.zoneBg:SetColorTexture(0.165, 0.14, 0.10, 1)
	f.zone = f:CreateFontString(nil, "OVERLAY", "SexyQuestHelperSmall")
	f.zone:SetPoint("CENTER", f.zoneBg, "CENTER", 0, 0)
	f.zone:SetTextColor(0.78, 0.73, 0.64)
	f.zone:SetWordWrap(false)

	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)
	close:SetScript("OnClick", function()
		forceShow = false
		dismissedSig = f.sig -- erscheint erst wieder bei neuen Unterschieden
		f:Hide()
	end)

	f:Hide()

	-- Edit Mode: Position, Größe und Sichtbarkeit; im Edit Mode zeigt das Fenster Beispieldaten
	SEM:Register(f, {
		name = "SexyQuestHelper",
		db = db,
		settings = {
			{ type = "link", name = T("Mitspielern helfen", "Help your group"), frame = function() return helpUI end },
			{ type = "check", name = T("Fenster \"Mitspielern helfen\" einschalten", "Turn on the \"Help your group\" window"),
				get = function() return cfg.helpAuto end,
				set = function(v) cfg.helpAuto = v and true or false; Refresh() end },
			{ type = "header", name = T("Erscheinen", "Appearing"), id = "appear" },
			{ type = "slider", name = T("Verzögerung bis zum Erscheinen", "Delay before appearing"),
				min = 1, max = 10, step = 1,
				get = function() return cfg.settleDelay end,
				set = function(v) cfg.settleDelay = v end,
				format = function(v) return v .. " s" end },
			{ type = "slider", name = T("Automatisch schließen nach", "Close automatically after"),
				min = 0, max = 60, step = 5,
				get = function() return cfg.autoClose end,
				set = function(v) cfg.autoClose = v end,
				format = function(v) return v == 0 and T("Aus", "Off") or (v .. " s") end },
			{ type = "check", name = T("Ton beim Erscheinen", "Sound when appearing"),
				get = function() return cfg.sound end,
				set = function(v) cfg.sound = v and true or false end },
			{ type = "check", name = T("Hinweis im Chat, was fehlt", "Chat note about what is missing"),
				get = function() return cfg.chatNotice end,
				set = function(v) cfg.chatNotice = v and true or false end },
			{ type = "header", name = T("Darstellung", "Look"), id = "look", collapsed = true },
			{ type = "check", name = T("Gebiet im Titel ausblenden", "Hide the zone in the title"),
				get = function() return cfg.hideZone end,
				set = function(v) cfg.hideZone = v and true or false; Refresh() end },
		},
		onMoved = function(self) db.anchoredHeight = self:GetHeight() end,
		onEditMode = function(active)
			if active then
				if not testMode then
					editPreview = true
					SetTestMode(true)
				end
			elseif editPreview then
				editPreview = false
				SetTestMode(false)
			end
		end,
	})
	return f
end

-- Das Fenster ging wegen Unterschieden von selbst auf (nicht per /sqh, nicht im Edit Mode)
local closeGen = 0
local function OnAutoOpen(entries)
	if cfg.sound then
		pcall(PlaySound, (SOUNDKIT and SOUNDKIT.IG_QUEST_LIST_OPEN) or 882)
	end
	if cfg.chatNotice then
		local name, lack, they
		local function Flush()
			if not name then return end
			local parts = {}
			if #lack > 0 then parts[#parts + 1] = T("Dir fehlt: ", "You lack: ") .. table.concat(lack, ", ") end
			if #they > 0 then parts[#parts + 1] = T("Hat nicht: ", "Lacks: ") .. table.concat(they, ", ") end
			print("|cffe8c26aSexyQuestHelper|r " .. name .. " - " .. table.concat(parts, "; "))
		end
		for _, e in ipairs(entries) do
			if e.kind == "header" then
				Flush()
				if e.tone == "warn" then name, lack, they = e.name, {}, {} else name = nil end
			elseif e.kind == "quest" and name then
				local list = (e.tone == "lack") and lack or they
				list[#list + 1] = QuestName(e.id)
			end
		end
		Flush()
	end
	if cfg.autoClose > 0 then
		closeGen = closeGen + 1
		local mine = closeGen
		C_Timer.After(cfg.autoClose, function()
			if mine == closeGen and ui and ui:IsShown() and not forceShow then
				dismissedSig = ui.sig -- wie beim Schließen per Kreuz: erst bei neuen Unterschieden wieder
				ui:Hide()
			end
		end)
	end
end

function Refresh()
	if not ui then return end
	local entries, hasDiff, sig = BuildEntries(forceShow)
	ui.sig = sig

	-- Beide Seiten nehmen oft gleichzeitig Quests an: bis die Liste des anderen
	-- angekommen ist, waere das ein Scheinunterschied. Ein Unterschied muss daher
	-- DIFF_SETTLE Sekunden unveraendert bestehen, bevor das Fenster aufgeht.
	local visibleDiff = false
	if hasDiff then
		if sig ~= pendingSig then
			pendingSig, pendingSince = sig, GetTime()
			C_Timer.After(cfg.settleDelay + 0.2, function() Refresh() end)
		end
		visibleDiff = scanReady and (GetTime() - pendingSince >= cfg.settleDelay) and sig ~= dismissedSig
	else
		pendingSig = nil
	end

	if not (forceShow or visibleDiff) then
		ui:Hide()
		return
	end

	ui.zone:SetText(myZone ~= "" and myZone or "?")
	ui.zone:SetWidth(0) -- Breite zuruecksetzen, dann natuerliche Breite messen
	local zoneWidth = math.min(ui.zone:GetStringWidth(), 150)
	ui.zone:SetWidth(zoneWidth)
	ui.zoneBg:SetWidth(zoneWidth + 18)
	ui.zone:SetShown(not cfg.hideZone)
	ui.zoneBg:SetShown(not cfg.hideZone)

	local y = BAND_H + 8
	for i, e in ipairs(entries) do
		local row = GetRow(i)
		local h = (e.kind == "header" and HEADER_H) or (e.kind == "quest" and QUEST_H) or INFO_H
		if e.kind == "header" and i > 1 then y = y + CARD_GAP end
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", ui, "TOPLEFT", 12, -y)
		row:SetSize(WIDTH - 24, h)
		ConfigureRow(row, e)
		row:Show()
		y = y + h
	end
	for i = #entries + 1, #rowPool do rowPool[i]:Hide() end

	-- Die Oberkante bleibt stehen: gespeichert ist die untere Kante, bezogen auf die Höhe,
	-- bei der sie gesetzt wurde (db.anchoredHeight, überdauert /reload)
	local newHeight = y + 12
	local db = SexyQuestHelperDB.editMode
	if db and db.x and db.y and not SEM:IsMoving(ui) then
		SEM:SetPosition(ui, db.x, db.y - (newHeight - (db.anchoredHeight or newHeight)))
		db.anchoredHeight = newHeight
	end
	ui:SetHeight(newHeight)
	local wasShown = ui:IsShown()
	ui:Show()
	if not wasShown and not forceShow then OnAutoOpen(entries) end
end

---------------------------------------------------------------------------
-- Zweites Fenster: Quests, die du schon erledigt hast und ein Mitglied noch hat (mit seinem Fortschritt)
---------------------------------------------------------------------------

local HELP_ROW_H, HELP_HEAD_H, HELP_OBJ_H = 26, 28, 12   -- Fragezeile, Kopfzeile, Hoehe je Zielzeile
local helpRows = {}
local helpForce = false      -- per /sqh help erzwungen
local helpDismissed = nil    -- weggeklickte Zusammenstellung (Mitglieder und Quests)

-- Eintraege: { kind = "header", name, count } / { kind = "quest", id | title, pct, ready } / { kind = "info", text }
local function BuildHelp()
	local entries, parts = {}, {}
	if testMode then
		entries[#entries + 1] = { kind = "header", name = "Testmate", count = 2 }
		entries[#entries + 1] = { kind = "quest", title = T("Beispiel-Quest", "Sample quest"), pct = 60,
			objs = { T("Wölfe getötet: 5/8", "Wolves slain: 5/8"), T("Fell: 1/1", "Pelt: 1/1") } }
		entries[#entries + 1] = { kind = "quest", title = T("Noch eine Quest", "Another quest"), pct = 100, ready = true,
			objs = { T("Beutel gefunden: 1/1", "Pouch found: 1/1") } }
		return entries, "test"
	end
	if not GroupChannel() then return entries, "" end
	for _, name in ipairs(GroupNames()) do
		local m = members[name]
		if m and m.zone == myZoneKey then
			local quests = {}
			for id in pairs(m.ids) do
				-- ich bin damit fertig: abgegeben und nicht mehr im Log (wiederholbare Quests koennen als erledigt
				-- gelten und trotzdem aktiv sein), oder (Option) im Log und nur noch abzugeben
				local mine
				if myIds[id] then
					mine = cfg.helpReady and myProgress[id] and myProgress[id].ready
				else
					mine = IsDone(id)
				end
				if mine then quests[#quests + 1] = id end
			end
			if #quests > 0 then
				table.sort(quests)
				entries[#entries + 1] = { kind = "header", name = name, count = #quests }
				for _, id in ipairs(quests) do
					local p = progressBy[name] and progressBy[name][id]
					entries[#entries + 1] = { kind = "quest", id = id, pct = p and p.pct, ready = p and p.ready,
						objs = detailsBy[name] and detailsBy[name][id] }
				end
				parts[#parts + 1] = name .. ":" .. table.concat(quests, ",")
			end
		end
	end
	return entries, table.concat(parts, ";")
end

local function GetHelpRow(i)
	local row = helpRows[i]
	if row then return row end
	row = CreateFrame("Frame", nil, helpUI)
	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints()
	row.avatar = row:CreateTexture(nil, "ARTWORK")
	row.avatar:SetSize(18, 18)
	row.avatar:SetPoint("LEFT", row, "LEFT", 8, 0)
	row.pill = MakePill(row)
	row.pill.tex:SetPoint("RIGHT", row, "RIGHT", -8, 0)
	row.name = row:CreateFontString(nil, "OVERLAY", "SexyQuestHelperText")
	row.name:SetPoint("LEFT", row.avatar, "RIGHT", 8, 0)
	row.name:SetPoint("RIGHT", row.pill.tex, "LEFT", -6, 0)
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)
	row.fs = row:CreateFontString(nil, "OVERLAY", "SexyQuestHelperSmall")
	row.fs:SetPoint("LEFT", row, "LEFT", 20, 3)
	row.fs:SetPoint("RIGHT", row.pill.tex, "LEFT", -6, 3)
	row.fs:SetJustifyH("LEFT")
	row.fs:SetWordWrap(false)
	-- Einzelne Ziele ("Wolf getoetet: 3/8"), eine Zeile je Ziel unter dem Questnamen
	row.objs = row:CreateFontString(nil, "OVERLAY", "SexyQuestHelperSmall")
	row.objs:SetJustifyH("LEFT")
	row.objs:SetJustifyV("TOP")
	row.objs:SetWordWrap(false)
	-- Kopfzeile eines Mitglieds: Linksklick fluestert, Rechtsklick visiert an
	row:SetScript("OnEnter", function(self)
		if not self.member then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(self.member)
		GameTooltip:AddLine(T("Linksklick: anflüstern", "Left click: whisper"), 0.6, 0.6, 0.6)
		GameTooltip:AddLine(T("Rechtsklick: anvisieren", "Right click: target"), 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	row:SetScript("OnMouseUp", function(self, button)
		local name = self.member
		if not name or name == "Testmate" then return end
		if button == "RightButton" then
			local unit = unitByName[name]
			if not unit then return end
			if InCombatLockdown() then
				print("SexyQuestHelper: " .. T("Im Kampf nicht möglich.", "Not possible in combat."))
			else
				pcall(TargetUnit, unit)
			end
		else
			if ChatFrame_SendTell then ChatFrame_SendTell(name) end
		end
	end)
	-- Fortschrittsbalken am unteren Rand der Questzeile
	row.barBg = row:CreateTexture(nil, "BORDER")
	row.barBg:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 20, 3)
	row.barBg:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -8, 3)
	row.barBg:SetHeight(3)
	row.barBg:SetColorTexture(0.21, 0.19, 0.14, 1)
	row.bar = row:CreateTexture(nil, "ARTWORK")
	row.bar:SetPoint("BOTTOMLEFT", row.barBg, "BOTTOMLEFT")
	row.bar:SetHeight(3)
	helpRows[i] = row
	return row
end

local function ConfigureHelpRow(row, e)
	local isHeader, isQuest = e.kind == "header", e.kind == "quest"
	row.bg:SetShown(e.kind ~= "info")
	row.bg:SetColorTexture(isHeader and 0.165 or 0.145, isHeader and 0.14 or 0.125, isHeader and 0.10 or 0.10, 1)
	row.avatar:SetShown(isHeader)
	row.name:SetShown(isHeader)
	row.fs:SetShown(not isHeader)
	row.barBg:SetShown(isQuest)
	row.bar:SetShown(isQuest)
	row.member = isHeader and e.name or nil
	row:EnableMouse(isHeader)
	row.objs:SetShown(isQuest and e.objs ~= nil and #e.objs > 0)
	row.pill.tex:ClearAllPoints()
	if isQuest and e.objs and #e.objs > 0 then
		row.pill.tex:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -5)
	else
		row.pill.tex:SetPoint("RIGHT", row, "RIGHT", -8, 0)
	end
	if isHeader then
		local r, g, b = ClassColor(e.name)
		SetClassIcon(row.avatar, e.name)
		row.name:SetText(e.name)
		row.name:SetTextColor(r, g, b)
		SetPill(row.pill, "they", e.count .. " " .. T("Quests", "quests"), nil, 18)
	elseif isQuest then
		row.fs:ClearAllPoints()
		if e.objs and #e.objs > 0 then
			-- Name oben, darunter die einzelnen Ziele (erfuellte gruen, offene grau)
			row.fs:SetPoint("TOPLEFT", row, "TOPLEFT", 20, -6)
			row.fs:SetWidth(WIDTH - 24 - 28 - 72)
			row.objs:ClearAllPoints()
			row.objs:SetPoint("TOPLEFT", row, "TOPLEFT", 20, -(6 + 14))
			row.objs:SetWidth(WIDTH - 24 - 28)
			local lines = {}
			for _, text in ipairs(e.objs) do
				local a, b = tostring(text):match("(%d+)/(%d+)")
				local complete = e.ready or (a and b and tonumber(a) >= tonumber(b))
				lines[#lines + 1] = (complete and "|cff7fd88f" or "|cff9b9180") .. text .. "|r"
			end
			row.objs:SetText(table.concat(lines, "\n"))
		else
			row.fs:SetWidth(0)
			row.fs:SetPoint("LEFT", row, "LEFT", 20, 3)
			row.fs:SetPoint("RIGHT", row.pill.tex, "LEFT", -6, 3)
		end
		row.fs:SetText(e.title or QuestName(e.id))
		row.fs:SetTextColor(0.95, 0.92, 0.86)
		if e.ready then
			SetPill(row.pill, "ok", T("Bereit", "Ready"), 60, 16)
		elseif e.pct then
			SetPill(row.pill, "warn", e.pct .. " %", 60, 16)
		else
			SetPill(row.pill, "grey", "?", 60, 16)
		end
		local pct = e.ready and 100 or (e.pct or 0)
		row.bar:SetWidth(math.max(1, (WIDTH - 24 - 28) * pct / 100))
		if e.ready then row.bar:SetColorTexture(0.30, 0.76, 0.42, 1) else row.bar:SetColorTexture(0.94, 0.75, 0.29, 1) end
	else
		row.fs:ClearAllPoints()
		row.fs:SetWidth(0)
		row.fs:SetPoint("LEFT", row, "LEFT", 8, 0)
		row.fs:SetPoint("RIGHT", row, "RIGHT", -8, 0)
		row.fs:SetText("|cff9b9180" .. e.text .. "|r")
		HidePill(row.pill)
	end
end

local function CreateHelpUI()
	local f = CreateFrame("Frame", "SexyQuestHelperHelpFrame", UIParent, "BackdropTemplate")
	f:SetSize(WIDTH, 60)
	f:SetFrameStrata("MEDIUM")
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	f:SetBackdropColor(0.08, 0.065, 0.05, 0.96)
	f:SetBackdropBorderColor(0.42, 0.34, 0.15, 1)

	-- Position: rechts neben dem Hauptfenster (Oberkanten gleich), bei zu wenig Platz links davon
	local db = SexyQuestHelperDB.helpMode
	if not db then
		db = {}
		SexyQuestHelperDB.helpMode = db
		local main = SexyQuestHelperDB.editMode or {}
		local screenW = UIParent:GetWidth()
		local mx, my = main.x or 100, main.y or 300
		local top = my + (main.anchoredHeight or 60)
		db.x = mx + WIDTH + 12
		if db.x + WIDTH > screenW then db.x = math.max(0, mx - WIDTH - 12) end
		db.y = top - 60
		db.anchoredHeight = 60
	end
	f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", db.x, db.y)
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SEM:SetPosition(self, self:GetLeft(), self:GetBottom())
		db.anchoredHeight = self:GetHeight()
	end)

	f.band = f:CreateTexture(nil, "BACKGROUND")
	f.band:SetPoint("TOPLEFT", f, "TOPLEFT", 3, -3)
	f.band:SetPoint("TOPRIGHT", f, "TOPRIGHT", -3, -3)
	f.band:SetHeight(BAND_H - 3)
	f.band:SetColorTexture(0.15, 0.12, 0.07, 1)
	f.title = f:CreateFontString(nil, "OVERLAY", "SexyQuestHelperTitle")
	f.title:SetPoint("TOPLEFT", 12, -9)
	f.title:SetText(T("Mitspielern helfen", "Help your group"))

	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)
	close:SetScript("OnClick", function()
		helpForce = false
		helpDismissed = f.sig -- erscheint erst wieder bei einer anderen Zusammenstellung
		f:Hide()
	end)

	f:Hide()
	SEM:Register(f, {
		name = "SexyQuestHelper: " .. T("Helfen", "Help"),
		db = db,
		settings = {
			{ type = "link", name = "SexyQuestHelper", frame = function() return ui end },
			{ type = "header", name = T("Helfen", "Help"), id = "help" },
			{ type = "check", name = T("Fenster einschalten (öffnet sich von selbst)", "Turn the window on (opens by itself)"),
				get = function() return cfg.helpAuto end,
				set = function(v) cfg.helpAuto = v and true or false; Refresh() end },
			{ type = "check", name = T("Auch Quests zählen, die du noch im Log hast und nur abgeben musst", "Also count quests still in your log that you only have to hand in"),
				get = function() return cfg.helpReady end,
				set = function(v) cfg.helpReady = v and true or false; Refresh() end },
		},
		onMoved = function(self) db.anchoredHeight = self:GetHeight() end,
	})
	return f
end

function RefreshHelp()
	if not helpUI then return end
	local entries, sig = BuildHelp()
	helpUI.sig = sig
	local auto = cfg.helpAuto and scanReady and #entries > 0 and sig ~= helpDismissed
	if not (helpForce or testMode or auto) then
		helpUI:Hide()
		return
	end
	if #entries == 0 then
		entries[1] = { kind = "info", text = T("Niemand braucht gerade Hilfe.", "Nobody needs help right now.") }
	end

	local y = BAND_H + 8
	for i, e in ipairs(entries) do
		local row = GetHelpRow(i)
		local h = (e.kind == "header" and HELP_HEAD_H) or (e.kind == "quest" and HELP_ROW_H) or INFO_H
		if e.kind == "quest" and e.objs and #e.objs > 0 then h = HELP_ROW_H + 6 + #e.objs * HELP_OBJ_H end
		if e.kind == "header" and i > 1 then y = y + CARD_GAP end
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", helpUI, "TOPLEFT", 12, -y)
		row:SetSize(WIDTH - 24, h)
		ConfigureHelpRow(row, e)
		row:Show()
		y = y + h
	end
	for i = #entries + 1, #helpRows do helpRows[i]:Hide() end

	-- Oberkante bleibt stehen (wie beim Hauptfenster)
	local newHeight = y + 12
	local db = SexyQuestHelperDB.helpMode
	if db and db.x and db.y and not SEM:IsMoving(helpUI) then
		SEM:SetPosition(helpUI, db.x, db.y - (newHeight - (db.anchoredHeight or newHeight)))
		db.anchoredHeight = newHeight
	end
	helpUI:SetHeight(newHeight)
	helpUI:Show()
end

-- Beide Fenster zusammen aktualisieren
local RefreshMain = Refresh
function Refresh()
	RefreshMain()
	RefreshHelp()
end

---------------------------------------------------------------------------
-- Scan-Steuerung
---------------------------------------------------------------------------

local function DoScan(forceBroadcast)
	scanTimer = nil
	local ok, zone, ids, titles, key = pcall(ScanQuests)
	if not ok then
		print("|cffff4040SexyQuestHelper:|r Scan-Fehler: " .. tostring(zone))
		return
	end
	myZone, myIds, myTitles, myZoneKey = zone, ids, titles, key
	myProgress = ComputeProgress(ids)
	ignoreUntil = GetTime() + IGNORE_AFTER_SCAN

	local signature = myZoneKey .. ":" .. table.concat(SortedIds(myIds), ",")
	if forceBroadcast or signature ~= mySignature then
		mySignature = signature
		Broadcast()
		-- eigener Stand geaendert (z.B. Vorquest abgegeben): Meldungen an alle neu senden
		for name in pairs(members) do ScheduleDoneReply(name) end
	end
	-- Fortschritt auch dann senden, wenn sich nur er geaendert hat (die Quest-Liste blieb gleich)
	BroadcastProgress()
	if forceBroadcast and GroupChannel() then Send("R|", GroupChannel()) end
	Refresh()
end

local function QueueScan(forceBroadcast)
	if scanTimer and not forceBroadcast then return end
	scanTimer = true
	C_Timer.After(SCAN_DELAY, function() DoScan(forceBroadcast) end)
end

local function PruneMembers()
	local present = {}
	for _, name in ipairs(GroupNames()) do present[name] = true end
	for name in pairs(members) do
		if not present[name] then members[name] = nil; versions[name] = nil; completedBy[name] = nil; blockedBy[name] = nil; learnedBlocked[name] = nil; progressBy[name] = nil; detailsBy[name] = nil end
	end
end

frame:SetScript("OnEvent", function(_, event, ...)
	if event == "CHAT_MSG_ADDON" then
		OnAddonMessage(...)
	elseif event == "QUEST_DATA_LOAD_RESULT" then
		Refresh()
	elseif event == "QUEST_LOG_UPDATE" then
		if GetTime() >= ignoreUntil then QueueScan(false) end
	elseif event == "CHAT_MSG_SYSTEM" then
		OnSystemMessage(...)
	elseif event == "QUEST_ACCEPTED" or event == "QUEST_REMOVED" or event == "QUEST_TURNED_IN" then
		-- echte Aenderungen: immer scannen (QUEST_LOG_UPDATE wird nach einem Scan kurz
		-- ignoriert und koennte sonst eine gleich danach angenommene Quest verschlucken)
		QueueScan(false)
	elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
		-- Kampf beginnt/endet: Teilen-Knöpfe sofort ein- bzw. ausschalten
		for _, row in ipairs(rowPool) do UpdateShareButton(row.share) end
	elseif event == "GROUP_ROSTER_UPDATE" then
		PruneMembers()
		QueueScan(true) -- neue Mitglieder brauchen unsere Liste
		Refresh()
	elseif event == "PLAYER_LOGIN" then
		SexyQuestHelperDB = SexyQuestHelperDB or {}
		SexyQuestHelperDB.cfg = SexyQuestHelperDB.cfg or {}
		cfg = setmetatable(SexyQuestHelperDB.cfg, { __index = DEFAULTS })
		ui = CreateUI() -- zuerst, damit /sqh auch bei spaeteren Fehlern funktioniert
		helpUI = CreateHelpUI()
		local register = (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) or RegisterAddonMessagePrefix
		local regOk, regResult = pcall(register, PREFIX)
		prefixOk = regOk and tostring(regResult) or ("FEHLER: " .. tostring(regResult))
		-- Fehlt von einem Mitglied noch jede Nachricht (z.B. weil beide gleichzeitig
		-- neu geladen haben), fragen wir regelmaessig nach.
		C_Timer.NewTicker(10, function()
			local channel = GroupChannel()
			if not channel then return end
			for _, name in ipairs(GroupNames()) do
				if not members[name] and name ~= "Testmate" then
					Send("R|", channel)
					return
				end
			end
		end)
		QueueScan(true)
		-- Direkt nach Login/Reload ist das Questlog oft noch unvollständig, das Gebiet unbekannt:
		-- die eigene Liste wäre zu klein und das Fenster meldete "Dir fehlt ..." fälschlich. Darum
		-- wird später nochmal gescannt und mit allen abgeglichen (Meldungen werden neu gesendet und
		-- angefragt); bis dahin geht das Fenster nicht von selbst auf.
		C_Timer.After(4, function() QueueScan(true) end)
		C_Timer.After(10, function()
			scanReady = true
			QueueScan(true)
		end)
	else -- Zonenwechsel, Betreten der Welt
		QueueScan(true)
	end
end)

for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "QUEST_LOG_UPDATE",
	"GROUP_ROSTER_UPDATE", "CHAT_MSG_ADDON", "CHAT_MSG_SYSTEM", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
	frame:RegisterEvent(e)
end
for _, e in ipairs({ "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN" }) do
	pcall(frame.RegisterEvent, frame, e) -- nicht in jedem Client vorhanden
end
pcall(frame.RegisterEvent, frame, "QUEST_DATA_LOAD_RESULT") -- nicht in jedem Client vorhanden

-- Testmodus: simuliertes Gruppenmitglied (/sqh test und Vorschau im Edit Mode)
function SetTestMode(on)
	testMode = on and true or false
	if testMode then
		-- Fake-Mitglied: gleiche Zone, eine deiner Quests fehlt, dafuer eine fremde
		local ids = {}
		local skipped = false
		for _, id in ipairs(SortedIds(myIds)) do
			if skipped then ids[id] = true else skipped = true end
		end
		ids[999999] = true
		members.Testmate = { zone = myZoneKey, ids = ids }
		versions.Testmate = VERSION
	else
		members.Testmate = nil
	end
	forceShow = testMode
	Refresh()
end

SLASH_SEXYQUESTHELPER1 = "/sqh"
SLASH_SEXYQUESTHELPER2 = "/sexyquesthelper"
SlashCmdList["SEXYQUESTHELPER"] = function(arg)
	if not ui then
		print("SexyQuestHelper: Oberflaeche nicht initialisiert (Fehler beim Laden?)")
		return
	end
	arg = (arg or ""):lower()
	if arg == "test" then
		editPreview = false
		SetTestMode(not testMode)
		return
	end
	if arg == "debug" or arg == "debug log" then
		local keys = {}
		for name, m in pairs(members) do keys[#keys + 1] = ("%s(%d, v%s)"):format(name, #SortedIds(m.ids), tostring(versions[name] or "?")) end
		print(("SQH v%s | Kanal=%s | Prefix=%s | gesendet=%d (%s) | empfangen=%d | Addon-Msgs gesamt=%d | letzter Sender=%s"):format(
			VERSION, tostring(GroupChannel()),
			tostring(prefixOk), sendCount, tostring(lastSendResult), recvCount, anyAddonMsgs, lastRecv))
		print(("SQH Zone='%s' (%s) | Quests=%d | Log-Eintraege=%d | GetInfo=%s | GetQuestLogTitle=%s"):format(
			myZone, myZoneKey, #SortedIds(myIds), NumEntries(), tostring(C_QuestLog and C_QuestLog.GetInfo ~= nil), tostring(GetQuestLogTitle ~= nil)))
		print("SQH Gruppe: " .. table.concat(GroupNames(), ", ") .. " | Daten von: " .. table.concat(keys, ", "))
		if arg == "debug log" then
			for i = 1, NumEntries() do
				local title, isHeader, _, questID = GetEntry(i)
				print((isHeader and "  [%s]" or "    %s (%s)"):format(tostring(title), tostring(questID)))
			end
		end
		return
	end
	if arg == "version" or arg == "v" then
		local names = GroupNames()
		local newest = VERSION
		for _, name in ipairs(names) do
			if versions[name] and CompareVersions(versions[name], newest) > 0 then newest = versions[name] end
		end
		print(("SexyQuestHelper v%s %s"):format(VERSION,
			CompareVersions(VERSION, newest) < 0 and ("|cffff4040(" .. T("veraltet, neueste in der Gruppe: v", "outdated, newest in group: v") .. newest .. ")|r")
			or ("|cff00ff00(" .. T("aktuell", "up to date") .. ")|r")))
		for _, name in ipairs(names) do
			local v = versions[name]
			local status
			if not members[name] and not v then
				status = "|cff888888" .. T("kein Addon / keine Daten", "no addon / no data") .. "|r"
			elseif not v then
				status = "|cffff4040" .. T("alte Version (vor 1.0.3)", "old version (before 1.0.3)") .. "|r"
			elseif CompareVersions(v, newest) < 0 then
				status = "|cffff4040v" .. v .. " - " .. T("veraltet", "outdated") .. "|r"
			else
				status = "|cff00ff00v" .. v .. " - " .. T("aktuell", "up to date") .. "|r"
			end
			print("  " .. ColoredName(name) .. ": " .. status)
		end
		return
	end
	local checkId = arg:match("^check%s+(%d+)$")
	if checkId then
		local id = tonumber(checkId)
		local function list(v) return type(v) == "table" and table.concat(v, ",") or tostring(v) end
		print(("SQH check %d: QuestDB=%s | annehmbar=%s | erledigt=%s | aktiv=%s"):format(id,
			tostring(_G.QuestDB ~= nil), tostring(CanAccept(id)), tostring(IsDone(id)), tostring(IsActive(id))))
		if _G.QuestDB then
			print(("  preQuestSingle=%s preQuestGroup=%s exclusiveTo=%s nextQuestInChain=%s requiredLevel=%s"):format(
				list(DbField(id, "preQuestSingle")), list(DbField(id, "preQuestGroup")), list(DbField(id, "exclusiveTo")),
				tostring(DbField(id, "nextQuestInChain")), tostring(DbField(id, "requiredLevel"))))
		end
		return
	end
	if arg == "help" or arg == "helfen" then
		helpForce = not (helpUI and helpUI:IsShown())
		if not helpForce then helpDismissed = helpUI and helpUI.sig end
		RefreshHelp()
		return
	end
	if arg == "refresh" or arg == "scan" then
		QueueScan(true)
		return
	end
	if ui:IsShown() then
		forceShow = false
		dismissedSig = ui.sig
	else
		forceShow = true
	end
	Refresh()
end
