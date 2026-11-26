-- SexyQuestHelper: vergleicht die Quests des aktuellen Gebiets mit allen
-- Gruppenmitgliedern, die ebenfalls dieses Addon nutzen.
--
-- Ablauf: Jeder Client liest seine Quests des aktuellen Gebiets (Questlog-
-- Kategorie = Gebietsname), sendet die Quest-IDs per Addon-Nachricht an die
-- Gruppe und vergleicht sie mit den empfangenen Listen der anderen.

local ST = {}   -- gemeinsamer Zustand statt vieler einzelner lokaler Variablen (Lua erlaubt höchstens 200 pro Funktion)
local PREFIX = "SexyQuestHelper"
local VERSION = "1.0.35" -- wird vom Release-Workflow zusammen mit ## Version in der .toc angehoben (GetAddOnMetadata fehlt auf Forever)
ST.versions = {} -- [name] = Addon-Version des Mitglieds
ST.blockedBy = {}      -- [name] = { [questID] = true }: Quests aus MEINER Liste, die das Mitglied laut seiner Meldung nicht annehmen kann
ST.learnedBlocked = {} -- wie blockedBy, aber aus Fehlermeldungen beim Teilen gelernt
ST.completedBy = {} -- [name] = { [questID] = true }: Quests aus MEINER Liste, die das Mitglied schon abgeschlossen hat
ST.SCAN_DELAY = 1        -- Sekunden Entprellung nach Events
ST.DIFF_SETTLE = 4       -- Sekunden, die ein Unterschied bestehen muss, bevor das Fenster erscheint
ST.IGNORE_AFTER_SCAN = 2 -- Sekunden, in denen eigene Auf-/Zuklapp-Events ignoriert werden
ST.CHUNK_SIZE = 200      -- Zeichen Quest-IDs pro Nachricht (Limit: 255 inkl. Header)

-- Einstellungen (Edit Mode); gespeichert wird nur, was vom Standard abweicht
local DEFAULTS = {
	settleDelay = ST.DIFF_SETTLE, -- Sekunden, die ein Unterschied bestehen muss, bevor das Fenster erscheint
	autoClose = 0,             -- Sekunden bis das Fenster von selbst zugeht (0 = aus)
	autoShare = false,         -- Quests, die ein Mitglied im selben Gebiet nicht hat, automatisch teilen
	sound = false,             -- Ton beim Erscheinen
	hideZone = false,          -- Gebiets-Etikett im Titel ausblenden
	helpAuto = false,          -- zweites Fenster (Mitspielern helfen) einschalten: es geht dann von selbst auf
	nearEnabled = false,       -- drittes Fenster (Quests in der Naehe) einschalten
	nearRadius = 60,           -- Reichweite in Yards um eine Zielstelle
	nearSound = false,         -- Ton, wenn eine Quest neu in Reichweite kommt
	nearGlow = true,           -- kurzes Aufleuchten der Zeile, wenn eine Quest neu in Reichweite kommt
	nearSoundKey = "IG_QUEST_LIST_OPEN", -- welcher Ton: Name in SOUNDKIT oder "lsm:Name" (LibSharedMedia)
	nearSoundChannel = "Master",         -- Tonkanal: bestimmt die Lautstärke ("Master", "SFX", "Dialog", "Ambience")
	nearHold = 3,              -- Minuten, die eine Quest ohne festen Ort nach einem Fortschritt gelistet bleibt
	nearMates = true,          -- "Quests in der Nähe": Stand der Gruppenmitglieder unter den Zielen zeigen
	nearMaxHeight = 400,       -- größte Höhe der Liste (Pixel); darüber wird mit dem Mausrad gescrollt
	minMain = false,           -- Gruppenabgleich eingeklappt (kleine Ansicht)
	minHelp = false,           -- Mitspielern helfen eingeklappt
	minNear = false,           -- Quests in der Nähe eingeklappt
	hideHeaderMain = false,    -- Kopfzeile des Fensters Gruppenabgleich ausblenden
	hideHeaderHelp = false,    -- ... des Fensters Mitspielern helfen
	hideHeaderNear = false,    -- ... des Fensters Quests in der Nähe
	helpReady = true,          -- Quests, die ich noch im Log habe und nur noch abgeben muss, zaehlen als erledigt
	width = 376,               -- Breite der drei Fenster (Pixel)
	rowH = 24,                 -- Zeilenhöhe der Quests; Kopfzeilen und Kartenköpfe richten sich danach
	cardGap = 8,               -- Abstand zwischen den Karten der Mitspieler
	opacity = 0.96,            -- Deckkraft des Fensterhintergrunds
	showShare = true,          -- Teilen-Knopf in den Quest-Zeilen (Gruppenabgleich)
	showPills = true,          -- Etiketten "Dir fehlt" / "Hat nicht" (Gruppenabgleich)
	showBars = true,           -- Fortschrittsbalken unter den Zielen (Mitspielern helfen, Quests in der Nähe)
	barH = 3,                  -- Höhe dieser Balken (Pixel)
	fontDelta = 0,             -- Schriftgröße: Unterschied zu den Standardgrößen (Titel 14, Text 13, klein 11)
	bandH = 30,                -- Höhe der Titelleiste
	bgColor = { r = 0.08, g = 0.065, b = 0.05 },       -- Hintergrund der Fenster
	borderColor = { r = 0.42, g = 0.34, b = 0.15 },    -- Rand der Fenster
	showAvatar = true,         -- Klassensymbol der Mitspieler
	avatarSize = 20,
	showStatus = true,         -- Etiketten der Mitspieler ("3 Unterschiede", "2 Quests")
	showAccent = true,         -- Farbstreifen links an den Quests (Mitspielern helfen, Quests in der Nähe)
	accentW = 3,
	showDividers = true,       -- Trennlinien zwischen den Zeilen
	showDist = true,           -- Entfernung in "Quests in der Nähe"
	showChecks = true,         -- Kästchen vor den Zielen
	showCounts = true,         -- Zähler ("3/8") der Ziele
	showButtons = true,        -- Knöpfe in der Titelleiste (Schließen, "-")
	showScroll = true,         -- Scrollbalken in "Quests in der Nähe"
	glowColor = { r = 0.94, g = 0.75, b = 0.29 },      -- Aufleuchten einer neuen Quest
	glowAlpha = 0.4,
}
local cfg = setmetatable({}, { __index = DEFAULTS })

local isDE = GetLocale() == "deDE"
local function T(de, en) return isDE and de or en end

local SEM = LibStub("SexyEditMode-1.0")
local frame = CreateFrame("Frame")
local ui                      -- Anzeigefenster (lazy)
local helpUI                  -- zweites Fenster: Mitspielern helfen
local nearUI                  -- drittes Fenster: Quests in der Naehe
local RefreshHelp, RefreshNear
local myLogIds = {} -- alle Quests im Log (fuer "Quests in der Naehe" in Dungeons, egal unter welcher Ueberschrift)
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

-- Gebiete, die für Quests als ein anderes Gebiet zählen (UiMapID -> UiMapID): Die Quests stehen im Questlog unter
-- dem Namen des Zielgebiets. 1416 Alterac-Gebirge zählt zum Vorgebirge von Hillsbrad (1424).
SexyQuestHelperZoneAlias = { [1416] = 1424 }   -- global statt local: die Hauptdatei ist nah am Limit von 200 lokalen Variablen

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
			return "m" .. (SexyQuestHelperZoneAlias[id] or id)
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
	local all = {}
	local header
	for i = 1, NumEntries() do
		local title, isHeader, _, questID = GetEntry(i)
		if isHeader then
			inZone = (title == zone or title == mapName)
			header = title
		elseif questID and questID > 0 then
			all[questID] = header or true   -- Überschrift im Questlog (bei Dungeon-Quests der Name des Dungeons)
			if inZone then
				ids[questID] = true
				titles[questID] = title
			end
		end
	end
	myLogIds = all

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
		if #chunk + #s + 1 > ST.CHUNK_SIZE then flush() end
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
		if #chunk + #s + 1 > ST.CHUNK_SIZE then flush() end
		chunk = (chunk == "") and s or (chunk .. "," .. s)
	end
	if isFirst or chunk ~= "" then flush() end -- auch leer senden: setzt alte Meldungen zurueck
end

-- Zieltexte meiner Quests ("Id=Ziel~Ziel", Quests durch ^ getrennt). Die Trennzeichen kommen in Zieltexten
-- nicht vor (werden sonst entfernt), Kommas dagegen schon, darum nicht wie die Id-Listen mit Komma getrennt.
local function SendDetails(channel)
	local list = { "L=" .. GetLocale() }   -- Sprache der Zieltexte; ältere Versionen überspringen den Eintrag (keine Quest-ID)
	for _, id in ipairs(SortedIds(myIds)) do
		local p = myProgress[id]
		if p and p.objs and #p.objs > 0 then
			local parts = {}
			for i = 1, math.min(#p.objs, 4) do
				local text = tostring(p.objs[i]):gsub("[|~%^=]", "")
				-- Zähler zuerst ("3/8 Wolf"), dann wird nur der Name gekürzt: bei langen Zielen würde ein Kürzen am Ende den
				-- Zähler abschneiden, und die Empfänger könnten den Stand nicht mehr lesen (der Mitspieler bliebe unsichtbar)
				local ha, hb, hrest = text:match("^%s*(%d+)/(%d+)%s+(.-)%s*$")
				if not ha then
					local nm, ca, cb = text:match("^(.-)%s*:?%s*(%d+)/(%d+)%s*$")
					if nm and nm ~= "" then ha, hb, hrest = ca, cb, nm end
				end
				if ha then
					local count = ha .. "/" .. hb
					text = count .. " " .. hrest:sub(1, math.max(8, 44 - #count - 1))
				else
					text = text:sub(1, 44)
				end
				parts[#parts + 1] = text
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
		if chunk ~= "" and #chunk + #entry + 1 > ST.CHUNK_SIZE then flush() end
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
		ST.versions[name] = rest
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
			local loc = entry:match("^L=(%a+)$")
			if loc then detailsBy[name].locale = loc end
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
		local store = (kind == "C" or kind == "E") and ST.completedBy or ST.blockedBy
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

-- Ausgeblendete Quests (Rechtsklick auf eine Quest in einem der drei Fenster), gespeichert in
-- SexyQuestHelperDB.nearHidden: [Quest] = Name. Eine Liste für alle Fenster (der Name des Schlüssels stammt aus der
-- Zeit, als nur "Quests in der Nähe" ausblenden konnte). Der Name wird mitgespeichert, damit die Liste auch Quests
-- zeigen kann, die nicht mehr im Log sind.
local function IsQuestHidden(id)
	local hidden = SexyQuestHelperDB.nearHidden
	return hidden and hidden[id] ~= nil
end

local function HiddenCount()
	local n = 0
	for _ in pairs(SexyQuestHelperDB.nearHidden or {}) do n = n + 1 end
	return n
end

-- Ausgeblendete Quests nach Namen sortiert: { { id, name }, ... }
local function HiddenList()
	local list = {}
	for id, name in pairs(SexyQuestHelperDB.nearHidden or {}) do
		list[#list + 1] = { id = id, name = myTitles[id] or (type(name) == "string" and name) or QuestName(id) }
	end
	table.sort(list, function(a, b) return a.name < b.name end)
	return list
end

-- Ausgeblendete Quests, die nicht (mehr) im Questlog stehen (abgegeben, abgebrochen), fallen aus der Liste. Erst, wenn der
-- Questlog gelesen ist: beim Laden wäre er sonst leer und alles würde gelöscht.
local function PruneHidden()
	local hidden = SexyQuestHelperDB.nearHidden
	if not (hidden and scanReady and next(myLogIds)) then return end
	for id in pairs(hidden) do
		if not myLogIds[id] then hidden[id] = nil end
	end
end

local hiddenFrame              -- eigener Dialog "Ausgeblendete Quests" (Knopf oben in "Quests in der Nähe")
local RefreshHiddenFrame

local function RefreshHiddenDialog()
	if (SEM.dialog and SEM.dialog:IsShown()) or (SEM.HubIsShown and SEM:HubIsShown()) then SEM:RebuildDialog() end
	if hiddenFrame and hiddenFrame:IsShown() then RefreshHiddenFrame() end
end

local function HideQuest(id)
	if not id then return end
	GameTooltip:Hide()
	SexyQuestHelperDB.nearHidden = SexyQuestHelperDB.nearHidden or {}
	SexyQuestHelperDB.nearHidden[id] = QuestName(id)
	print("|cffe8c26a[SQH]|r " .. T("ausgeblendet: ", "hidden: ") .. QuestName(id) .. " |cff9b9180("
		.. T("wieder einblenden im Edit Mode oder mit /sqh hidden", "show again in Edit Mode or with /sqh hidden") .. ")|r")
	Refresh()
	RefreshHiddenDialog()
	if SexyQuestHelperAPI.RefreshTargets then SexyQuestHelperAPI.RefreshTargets() end   -- Quest-Aktionen neu aufbauen
end

-- id = nil: alle wieder einblenden
local function UnhideQuest(id)
	if id then
		if SexyQuestHelperDB.nearHidden then SexyQuestHelperDB.nearHidden[id] = nil end
	else
		SexyQuestHelperDB.nearHidden = {}
	end
	Refresh()
	RefreshHiddenDialog()
	if SexyQuestHelperAPI.RefreshTargets then SexyQuestHelperAPI.RefreshTargets() end   -- Quest-Aktionen neu aufbauen
end

-- Abschnitt "Ausgeblendete Quests" für den Dialog im Edit Mode (in allen drei Fenstern gleich)
local function HiddenSettings()
	return { type = "header", name = T("Ausgeblendete Quests", "Hidden quests"), id = "nearHidden" },
		{ type = "dynamic", build = function()
			local list = HiddenList()
			if #list == 0 then
				return { { type = "divider", key = "sqh-hidden-none",
					name = T("Keine. Rechtsklick auf eine Quest blendet sie aus.", "None. Right-click a quest to hide it.") } }
			end
			-- ganz oben "Alle einblenden", darunter je Quest eine Zeile: Name links, "Einblenden" rechts
			local rows = { { type = "button", key = "sqh-unhide-all",
				name = T("Alle einblenden", "Show all"), onClick = function() UnhideQuest(nil) end } }
			for _, h in ipairs(list) do
				local id = h.id
				rows[#rows + 1] = { type = "buttonrow", key = "sqh-unhide-" .. id .. "-" .. h.name,
					name = h.name, text = T("Einblenden", "Show"), onClick = function() UnhideQuest(id) end,
					-- Mouseover über dem Namen zeigt die Quest wie in den Fenstern
					onEnter = function(frame)
						GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
						local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, ("quest:%d:%d"):format(id, UnitLevel("player")))
						if not ok then
							GameTooltip:ClearLines()
							GameTooltip:AddLine(h.name)
						end
						GameTooltip:Show()
					end }
			end
			return rows
		end }
end

-- Dialog "Ausgeblendete Quests": je Quest eine Zeile mit "Einblenden", unten "Alle einblenden".
-- Entsteht beim ersten Öffnen; ESC schließt ihn.
local HIDDEN_ROW_H, HIDDEN_MAX_ROWS = 24, 12

local function FlatButton(parent, text, width, height, r, g, b)
	local btn = CreateFrame("Button", nil, parent)
	btn:SetSize(width, height)
	btn.bg = btn:CreateTexture(nil, "BACKGROUND")
	btn.bg:SetAllPoints()
	-- Look wie im Einstellungsfenster (SexyEditMode): Bandfarbe, goldene Schrift, Tooltip-Rand; r, g, b setzen eine eigene Fläche
	btn.bg:SetColorTexture(r or 0.15, g or 0.12, b or 0.07, 1)
	btn.hl = btn:CreateTexture(nil, "HIGHLIGHT")
	btn.hl:SetAllPoints()
	btn.hl:SetColorTexture(1, 1, 1, 0.12)
	btn.text = btn:CreateFontString(nil, "OVERLAY", "SexyQuestHelperSmall")
	btn.text:SetAllPoints()
	btn.text:SetText(text)
	btn.text:SetTextColor(0.91, 0.76, 0.42)
	btn:RegisterForClicks("LeftButtonUp")
	if BackdropTemplateMixin then
		local rim = CreateFrame("Frame", nil, btn, "BackdropTemplate")
		rim:SetAllPoints(btn)
		rim:SetFrameLevel(btn:GetFrameLevel() + 2)
		rim:SetBackdrop({ edgeFile = "Interface/Tooltips/UI-Tooltip-Border", edgeSize = 10 })
		rim:SetBackdropBorderColor(0.42, 0.34, 0.15, 1)
	end
	return btn
end

local function CreateHiddenFrame()
	local f = CreateFrame("Frame", "SexyQuestHelperHiddenFrame", UIParent, "BackdropTemplate")
	f:SetSize(320, 100)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	f:SetBackdropColor(0.08, 0.065, 0.05, 0.96)
	f:SetBackdropBorderColor(0.42, 0.34, 0.15, 1)

	f.band = f:CreateTexture(nil, "BACKGROUND")
	f.band:SetPoint("TOPLEFT", f, "TOPLEFT", 3, -3)
	f.band:SetPoint("TOPRIGHT", f, "TOPRIGHT", -3, -3)
	f.band:SetHeight(27)
	f.band:SetColorTexture(0.15, 0.12, 0.07, 1)
	f.title = f:CreateFontString(nil, "OVERLAY", "SexyQuestHelperTitle")
	f.title:SetPoint("TOPLEFT", 12, -9)
	f.title:SetText(T("Ausgeblendete Quests", "Hidden quests"))

	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)
	f.closeBtn = close
	close:SetScript("OnClick", function() f:Hide() end)

	-- Liste im Scrollbereich (Mausrad)
	f.scroll = CreateFrame("ScrollFrame", nil, f)
	f.scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -38)
	f.scroll:SetSize(300, HIDDEN_ROW_H)
	f.content = CreateFrame("Frame", nil, f.scroll)
	f.content:SetSize(300, HIDDEN_ROW_H)
	f.scroll:SetScrollChild(f.content)
	f.scroll:EnableMouseWheel(true)
	f.scroll:SetScript("OnMouseWheel", function(self, delta)
		local range = math.max(0, f.content:GetHeight() - self:GetHeight())
		self:SetVerticalScroll(math.min(math.max(self:GetVerticalScroll() - delta * HIDDEN_ROW_H * 2, 0), range))
	end)

	f.empty = f:CreateFontString(nil, "OVERLAY", "SexyQuestHelperText")
	f.empty:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -42)
	f.empty:SetPoint("RIGHT", f, "RIGHT", -14, 0)
	f.empty:SetJustifyH("LEFT")
	f.empty:SetTextColor(0.61, 0.57, 0.50)
	f.empty:SetText(T("Keine Quests ausgeblendet. Rechtsklick auf eine Quest blendet sie aus.",
		"No hidden quests. Right-click a quest to hide it."))

	f.all = FlatButton(f, T("Alle einblenden", "Show all"), 110, 20)
	f.all:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 10)
	f.all:SetScript("OnClick", function() UnhideQuest(nil) end)

	f.rows = {}
	f:Hide()
	tinsert(UISpecialFrames, "SexyQuestHelperHiddenFrame")
	return f
end

local function GetHiddenRow(i)
	local row = hiddenFrame.rows[i]
	if row then return row end

	row = CreateFrame("Frame", nil, hiddenFrame.content)
	row:SetSize(300, HIDDEN_ROW_H - 2)
	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints()
	row.bg:SetColorTexture(0.145, 0.125, 0.10, 1)
	row.show = FlatButton(row, T("Einblenden", "Show"), 76, HIDDEN_ROW_H - 8)
	row.show:SetPoint("RIGHT", row, "RIGHT", -4, 0)
	row.show:SetScript("OnClick", function() if row.questId then UnhideQuest(row.questId) end end)
	row.fs = row:CreateFontString(nil, "OVERLAY", "SexyQuestHelperSmall")
	row.fs:SetPoint("LEFT", row, "LEFT", 8, 0)
	row.fs:SetPoint("RIGHT", row.show, "LEFT", -6, 0)
	row.fs:SetJustifyH("LEFT")
	row.fs:SetWordWrap(false)
	hiddenFrame.rows[i] = row
	return row
end

function RefreshHiddenFrame()
	local f = hiddenFrame
	local list = HiddenList()

	for i, h in ipairs(list) do
		local row = GetHiddenRow(i)
		row.questId = h.id
		row.fs:SetText(h.name)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, -(i - 1) * HIDDEN_ROW_H)
		row:Show()
	end
	for i = #list + 1, #f.rows do f.rows[i]:Hide() end

	local listH = math.max(1, #list * HIDDEN_ROW_H)
	local viewH = math.min(listH, HIDDEN_MAX_ROWS * HIDDEN_ROW_H)
	f.content:SetHeight(listH)
	f.scroll:SetHeight(viewH)
	f.scroll:SetVerticalScroll(math.min(f.scroll:GetVerticalScroll(), math.max(0, listH - viewH)))

	f.empty:SetShown(#list == 0)
	f.scroll:SetShown(#list > 0)
	f.all:SetShown(#list > 0)
	if #list == 0 then
		f:SetHeight(38 + 40)
	else
		f:SetHeight(38 + viewH + 8 + 20 + 10)
	end
end

local function ToggleHiddenFrame()
	hiddenFrame = hiddenFrame or CreateHiddenFrame()
	if hiddenFrame:IsShown() then
		hiddenFrame:Hide()
	else
		RefreshHiddenFrame()
		hiddenFrame:Show()
	end
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
	local data = {}   -- { text, have, need, finished } je Ziel
	if C_QuestLog and C_QuestLog.GetQuestObjectives then
		local ok, objectives = pcall(C_QuestLog.GetQuestObjectives, id)
		if ok and type(objectives) == "table" then
			for _, o in ipairs(objectives) do
				local required = tonumber(o.numRequired) or 0
				if required > 0 then
					need = need + required
					done = done + math.min(tonumber(o.numFulfilled) or 0, required)
				end
				if type(o.text) == "string" and o.text ~= "" then
					texts[#texts + 1] = o.text
					data[#data + 1] = { text = o.text, have = tonumber(o.numFulfilled) or 0, need = required, finished = o.finished and true or false }
				end
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
				if text ~= "" then
					texts[#texts + 1] = text
					data[#data + 1] = { text = text, have = tonumber(a) or 0, need = tonumber(b) or 0 }
				end
			end
		end
	end
	if ready then return 100, true, texts, data end
	if need > 0 then return math.floor(done * 100 / need), false, texts, data end
	return 0, false, texts, data
end

local function ComputeProgress(ids)
	local result = {}
	for id in pairs(ids) do
		local pct, ready, texts, data = QuestProgress(id)
		result[id] = { pct = pct, ready = ready, objs = texts, goals = data }
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
		btn.bg:SetColorTexture(0.15, 0.12, 0.07, 1)
		btn.text:SetTextColor(0.91, 0.76, 0.42)
		btn.text:SetText(T("Teilen", "Share"))
		btn.hl:Show()
	end
end

local function ShareQuest(id)
	if InCombat() then
		print("|cffe8c26a[SQH]|r " .. T("Im Kampf kann nicht geteilt werden.", "Cannot share while in combat."))
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
		print("|cffe8c26a[SQH]|r " .. T("Diese Quest kann nicht geteilt werden.", "This quest cannot be shared."))
		return
	end
	local ok, err = pcall(QuestLogPushQuest)
	lastShare = { id = id, t = GetTime() }
	-- Erfolg bleibt still (die Quest erscheint beim Mitglied); nur ein Fehler wird gemeldet
	if not ok then
		print("|cffe8c26a[SQH]|r " .. tostring(err))
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
			ST.learnedBlocked[name] = ST.learnedBlocked[name] or {}
			ST.learnedBlocked[name][lastShare.id] = true
			Refresh()
			return
		end
	end
end

local function OpenQuest(id)
	if IsShiftKeyDown() then
		if not ChatEdit_InsertLink(QuestLink(id)) then
			print("|cffe8c26a[SQH]|r " .. QuestLink(id))
		end
		return
	end
	if not myIds[id] then
		print("|cffe8c26a[SQH]|r " .. QuestLink(id) .. " - " .. T("nicht in deinem Questlog.", "not in your quest log."))
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

-- Automatisch teilen (Einstellung cfg.autoShare): Quests, die ein Mitglied im selben Gebiet nicht hat, wie in der Liste "Hat nicht".
-- Geteilt wird nie im Kampf, höchstens eine Quest je Durchlauf (alle 4 Sekunden) und dieselbe Quest frühestens nach 10 Minuten wieder,
-- damit bei den Mitspielern nicht dauernd Fenster aufgehen. Verworfene oder unmögliche Quests (blockedBy, learnedBlocked) bleiben draußen.
function ST.AutoShareTick()
	if not (cfg and cfg.autoShare) or testMode or InCombat() or not GroupChannel() then return end
	local now = GetTime()
	ST.autoShared = ST.autoShared or {}
	for _, name in ipairs(GroupNames()) do
		local m = members[name]
		if m and m.zone == myZoneKey then
			local theirDone = ST.completedBy[name]
			for id in pairs(myIds) do
				if not m.ids[id] and not (theirDone and theirDone[id]) and not IsQuestHidden(id)
					and not (ST.blockedBy[name] and ST.blockedBy[name][id])
					and not (ST.learnedBlocked[name] and ST.learnedBlocked[name][id])
					and CanShare(id) and now - (ST.autoShared[id] or -1e9) > 600 then   -- Sekunden bis dieselbe Quest wieder geteilt wird
					ST.autoShared[id] = now
					ShareQuest(id)
					return
				end
			end
		end
	end
end
C_Timer.NewTicker(4, function() ST.AutoShareTick() end)

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
					local theirDone = ST.completedBy[name]
					for id in pairs(m.ids) do
						-- hat er, ich nicht - aber ich habe sie schon abgegeben oder kann sie nicht annehmen: kein Unterschied
						if not myIds[id] and not IsDone(id) and CanAccept(id) and not IsQuestHidden(id) then iLack[#iLack + 1] = id end
					end
					for id in pairs(myIds) do
						-- habe ich, er nicht - aber er hat sie schon abgegeben oder kann sie nicht annehmen: kein Unterschied
						if not m.ids[id] and not (theirDone and theirDone[id]) and not IsQuestHidden(id)
							and not (ST.blockedBy[name] and ST.blockedBy[name][id])
							and not (ST.learnedBlocked[name] and ST.learnedBlocked[name][id]) then
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
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

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
	row.share.bg:SetColorTexture(0.15, 0.12, 0.07, 1)   -- Stil wie der Reset-Knopf in SexyHarvester
	row.share.hl = row.share:CreateTexture(nil, "HIGHLIGHT")
	row.share.hl:SetAllPoints()
	row.share.hl:SetColorTexture(1, 1, 1, 0.12)
	row.share.text = row.share:CreateFontString(nil, "OVERLAY", "SexyQuestHelperSmall")
	row.share.text:SetAllPoints()
	row.share.text:SetTextColor(0.91, 0.76, 0.42)
	-- dünner goldener Rand, immer genau ein Bildschirmpixel stark
	do
		local btn, edges = row.share, {}
		for i, e in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
			{ "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
			local t = btn:CreateTexture(nil, "BORDER")
			t:SetColorTexture(0.6, 0.49, 0.22, 1)
			t:SetPoint(e[1])
			t:SetPoint(e[2])
			edges[i] = { tex = t, horizontal = e[3] }
		end
		local function Pixel()
			local px = 1 / math.max(0.2, btn:GetEffectiveScale())
			for _, e in ipairs(edges) do
				if e.horizontal then e.tex:SetHeight(px) else e.tex:SetWidth(px) end
			end
		end
		Pixel()
		btn:HookScript("OnShow", Pixel)
	end
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
		GameTooltip:AddLine(T("Rechtsklick: ausblenden", "Right-click: hide"), 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	row:SetScript("OnClick", function(self, button)
		if not self.questId then return end
		if button == "RightButton" then
			if not testMode then HideQuest(self.questId) end
		else
			OpenQuest(self.questId)
		end
	end)

	rowPool[i] = row
	return row
end

-- MV (Sammeltabelle statt lokaler Variablen, Lua erlaubt höchstens 200) muss vor ihrer ersten Benutzung stehen
local MV = { SUM_H = 26, nearTab = "active", NEAR_TAB_H = 32 }   -- nearTab: Reiter in "Quests in der Nähe" ("active" oder "hidden"); in MV statt als eigene Variablen (Grenze von 200 lokalen Variablen)

-- Zieltexte eines Mitspielers zu einer Quest. Stammen sie aus einem Client in einer anderen Sprache (der Absender schickt seine
-- Sprache mit), stünden sie in dieser Sprache im eigenen Fenster: dann nur der Zähler unter einem neutralen Namen ("Ziel 1: 3/8").
function MV.Details(name, id)
	local det = detailsBy[name] and detailsBy[name][id]
	if not det then return nil end
	local theirs, mine = detailsBy[name].locale, GetLocale()
	if not theirs or theirs == mine or (theirs:sub(1, 2) == "en" and mine:sub(1, 2) == "en") then return det end
	local out = {}
	for j, text in ipairs(det) do
		local a, b = tostring(text):match("(%d+)/(%d+)")
		out[j] = T("Ziel ", "Goal ") .. j .. (a and (": " .. a .. "/" .. b) or "")
	end
	return out
end

local function ConfigureRow(row, e)
	local isHeader, isQuest = e.kind == "header", e.kind == "quest"
	row.questId = e.id
	row:EnableMouse(isQuest)
	row.bg:SetShown(e.kind ~= "info")
	row.bg:SetColorTexture(0.145, 0.125, 0.10, cfg.opacity)
	row.divider:SetShown(isQuest and cfg.showDividers ~= false)

	row.avatar:SetShown(isHeader and cfg.showAvatar ~= false)
	row.name:SetShown(isHeader)
	if isHeader then
		local r, g, b = ClassColor(e.name)
		SetClassIcon(row.avatar, e.name)
		row.avatar:SetSize(cfg.avatarSize or 20, cfg.avatarSize or 20)
		row.name:SetText(e.name)
		row.name:SetTextColor(r, g, b)
		if cfg.showStatus ~= false then
			SetPill(row.status, e.tone, e.status, nil, 18)
		else
			HidePill(row.status)
		end
		MV.NameAnchors(row, row.status)
	else
		HidePill(row.status)
	end

	local pills = cfg.showPills ~= false
	local share = e.share and cfg.showShare ~= false
	if isQuest and pills then
		SetPill(row.kind, e.tone, e.label, 66, 16)
	else
		HidePill(row.kind)
	end

	row.fs:SetShown(not isHeader)
	row.fs:ClearAllPoints()
	if isQuest then
		row.fs:SetText(QuestName(e.id))
		row.fs:SetPoint("LEFT", row, "LEFT", pills and 82 or 8, 0)
		row.fs:SetPoint("RIGHT", row, "RIGHT", share and -66 or -8, 0)
	elseif e.kind == "info" then
		row.fs:SetText("|cff9b9180" .. e.text .. "|r")
		row.fs:SetPoint("LEFT", row, "LEFT", 8, 0)
		row.fs:SetPoint("RIGHT", row, "RIGHT", -8, 0)
	end
	row.share:SetShown(share and true or false)
	row.share:SetHeight(QUEST_H - 6)
	UpdateShareButton(row.share)
end

---------------------------------------------------------------------------
-- Kleine Ansicht: Titelband plus eine Zeile mit dem Wichtigsten (Zusammenfassung).
-- Jedes der drei Fenster hat im Titelband einen Knopf "-" / "+"; der Zustand steht in cfg.minMain / minHelp / minNear.
---------------------------------------------------------------------------
-- (alles in einer Tabelle: Lua erlaubt höchstens 200 lokale Variablen je Block)

function MV.AddMinButton(f, key, refresh)
	local b = FlatButton(f, "", 20, 18, 0.2, 0.16, 0.06)
	f.minFrame = b
	b:SetPoint("TOPRIGHT", f, "TOPRIGHT", -32, -9)
	local function Update() b.text:SetText(cfg[key] and "+" or "-") end
	b:SetScript("OnClick", function()
		cfg[key] = not cfg[key]
		Update()
		refresh()
	end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(cfg[key] and T("Ausklappen", "Expand") or T("Einklappen", "Collapse"))
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	f.minButton = { Update = Update }
	Update()
end

-- Im Kampf: normal anzeigen, kleine Ansicht oder ausblenden (je Fenster). Ausblenden läuft über die Regel
-- "Im Kampf ausblenden" von SexyEditMode (db.hideInCombat des Fensters), die kleine Ansicht über cfg.combatMain/Help/Near.
MV.COMBAT = { minMain = "combatMain", minHelp = "combatHelp", minNear = "combatNear" }
MV.DB = { minMain = "editMode", minHelp = "helpMode", minNear = "nearMode" }

-- Zeigt das Fenster gerade die kleine Ansicht? (selbst eingeklappt, oder im Kampf eingestellt)
function MV.IsMin(key)
	if cfg[key] then return true end
	return cfg[MV.COMBAT[key]] == "mini" and InCombat() and true or false
end

function MV.CombatRefresh()
	Refresh()
	RefreshHelp()
	RefreshNear()
end

function MV.CombatSpec(minKey)
	local ck, dbk = MV.COMBAT[minKey], MV.DB[minKey]
	return { type = "select", name = T("Im Kampf", "In combat"),
		options = {
			{ value = "show", label = T("Normal anzeigen", "Show normally") },
			{ value = "mini", label = T("Kleine Ansicht", "Small view") },
			{ value = "hide", label = T("Ausblenden", "Hide") },
		},
		get = function()
			local d = SexyQuestHelperDB[dbk]
			if d and d.hideInCombat then return "hide" end
			return cfg[ck] == "mini" and "mini" or "show"
		end,
		set = function(v)
			local d = SexyQuestHelperDB[dbk]
			if d then d.hideInCombat = (v == "hide") or nil end
			cfg[ck] = (v == "mini") and "mini" or "show"
			MV.CombatRefresh()
		end }
end

-- Kurzes Aufleuchten einer Zeile (zwei goldene Pulse, die abklingen), z. B. für eine neu in Reichweite gekommene Quest
function MV.Glow(row)
	local g = row.glowFx
	if not g then
		g = CreateFrame("Frame", nil, row)
		g:SetAllPoints()
		g:EnableMouse(false)
		g.tex = g:CreateTexture(nil, "OVERLAY")
		g.tex:SetAllPoints()
		g.tex:SetColorTexture(0.94, 0.75, 0.29, 1)
		g.tex:SetBlendMode("ADD")
		g:Hide()
		g:SetScript("OnUpdate", function(self, dt)
			self.t = self.t + dt
			local p = self.t / 1.3
			if p >= 1 then
				self:Hide()
				return
			end
			self.tex:SetAlpha((cfg.glowAlpha or 0.4) * math.abs(math.sin(p * math.pi * 2)) * (1 - p))
		end)
		row.glowFx = g
	end
	g.t = 0
	g.tex:SetColorTexture(cfg.glowColor.r, cfg.glowColor.g, cfg.glowColor.b, 1)
	g.tex:SetAlpha(0)
	g:Show()
end

-- Kopfzeile ein-/ausblenden (cfg.hideHeaderMain/Help/Near): Band, Titel, Gebiets-Badge und die Knöpfe im Band verschwinden,
-- die Inhalte rücken nach oben (MV.Head liefert den Abstand der Inhalte zur Oberkante).
function MV.Head(f) return f.headerHidden and 6 or BAND_H end

function MV.SetHeader(f, hide)
	hide = hide and true or false
	f.headerHidden = hide
	f.band:SetShown(not hide)
	f.title:SetShown(not hide)
	if f.closeBtn then f.closeBtn:SetShown(not hide and cfg.showButtons ~= false) end
	if f.minFrame then f.minFrame:SetShown(not hide and cfg.showButtons ~= false) end
	if hide and f.zoneBg then
		f.zoneBg:Hide()
		f.zone:Hide()
	end
end

function MV.EnsureSummary(f)
	if f.sum then return f.sum end
	local sum = CreateFrame("Frame", nil, f)
	sum:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -BAND_H - 2)
	sum:SetSize(WIDTH - 24, MV.SUM_H)
	sum.text = sum:CreateFontString(nil, "OVERLAY", "SexyQuestHelperSmall")
	sum.text:SetPoint("LEFT", 0, 2)
	sum.text:SetPoint("RIGHT", -60, 2)
	sum.text:SetJustifyH("LEFT")
	sum.text:SetWordWrap(false)
	sum.text:SetTextColor(0.91, 0.86, 0.75)
	sum.value = sum:CreateFontString(nil, "OVERLAY", "SexyQuestHelperSmall")
	sum.value:SetPoint("RIGHT", 0, 2)
	sum.value:SetTextColor(0.94, 0.75, 0.29)
	sum.barBg = sum:CreateTexture(nil, "BACKGROUND")
	sum.barBg:SetPoint("BOTTOMLEFT", 0, 2)
	sum.barBg:SetSize(WIDTH - 24, 3)
	sum.barBg:SetColorTexture(0.04, 0.03, 0.02, 1)
	sum.bar = sum:CreateTexture(nil, "ARTWORK")
	sum.bar:SetPoint("BOTTOMLEFT", 0, 2)
	sum.bar:SetHeight(3)
	sum.bar:SetColorTexture(0.78, 0.64, 0.29, 1)
	if SEM.ShineBar then SEM:ShineBar(sum.bar) end   -- plastischer Glanz
	f.sum = sum
	return sum
end

-- Zeigt die Zusammenfassung (frac = Fortschritt von 0 bis 1 oder nil) und liefert die Höhe, die sie braucht
function MV.ShowSummary(f, text, value, frac)
	local sum = MV.EnsureSummary(f)
	sum:ClearAllPoints()
	sum:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -MV.Head(f) - 2)
	sum:SetSize(WIDTH - 24, MV.SUM_H)
	sum.barBg:SetWidth(WIDTH - 24)
	sum.text:SetText(text or "")
	sum.value:SetText(value or "")
	sum.barBg:SetShown(frac ~= nil)
	sum.bar:SetShown(frac ~= nil)
	if frac then sum.bar:SetWidth(math.max(1, (WIDTH - 24) * math.min(1, math.max(0, frac)))) end
	sum:Show()
	return MV.SUM_H
end

function MV.HideSummary(f)
	if f.sum then f.sum:Hide() end
end

-- Höhe eines Fensters setzen; die Oberkante bleibt stehen (wie in den Refresh-Funktionen)
function MV.ApplyHeight(f, dbKey, newHeight)
	local db = SexyQuestHelperDB[dbKey]
	if db and db.x and db.y and not SEM:IsMoving(f) then
		SEM:SetPosition(f, db.x, db.y - (newHeight - (db.anchoredHeight or newHeight)))
		db.anchoredHeight = newHeight
	end
	f:SetHeight(newHeight)
end

-- Zusammenfassungen der Fenster
function MV.MainSummary(entries)
	local warn, count, quests = nil, 0, 0
	for _, e in ipairs(entries) do
		if e.kind == "header" and e.tone == "warn" then warn = warn or e; count = count + 1 end
		if e.kind == "quest" then quests = quests + 1 end
	end
	if warn then
		local text = count == 1 and (warn.name .. ": " .. (warn.status or ""))
			or T(count .. " Mitspieler weichen ab", count .. " members differ")
		return text, quests > 0 and tostring(quests) or ""
	end
	return (entries[1] and entries[1].kind == "info" and entries[1].text) or T("Alle auf demselben Stand", "Everyone in sync"), ""
end

function MV.HelpSummary(entries)
	local members, quests, firstQuest, firstName = 0, 0, nil, nil
	for _, e in ipairs(entries) do
		if e.kind == "header" then members = members + 1; firstName = firstName or e.name end
		if e.kind == "quest" then quests = quests + 1; firstQuest = firstQuest or e end
	end
	if quests == 0 then
		return (entries[1] and entries[1].text) or T("Niemand braucht gerade Hilfe.", "Nobody needs help right now."), "", nil
	end
	if members == 1 and quests == 1 then
		local pct = firstQuest.ready and 100 or firstQuest.pct
		return firstName .. ": " .. (firstQuest.title or QuestName(firstQuest.id)), pct and (pct .. " %") or "", pct and pct / 100 or nil
	end
	return T(members .. " Mitspieler, " .. quests .. " Quests", members .. " members, " .. quests .. " quests"), "", nil
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
	f.zoneBg:SetPoint("TOPRIGHT", f, "TOPRIGHT", -56, -7)
	f.zoneBg:SetHeight(18)
	f.zoneBg:SetColorTexture(0.165, 0.14, 0.10, 1)
	f.zone = f:CreateFontString(nil, "OVERLAY", "SexyQuestHelperSmall")
	f.zone:SetPoint("CENTER", f.zoneBg, "CENTER", 0, 0)
	f.zone:SetTextColor(0.78, 0.73, 0.64)
	f.zone:SetWordWrap(false)

	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)
	f.closeBtn = close
	close:SetScript("OnClick", function()
		forceShow = false
		dismissedSig = f.sig -- erscheint erst wieder bei neuen Unterschieden
		f:Hide()
	end)
	MV.AddMinButton(f, "minMain", function() Refresh() end)

	f:Hide()

	-- Edit Mode: Position, Größe und Sichtbarkeit; im Edit Mode zeigt das Fenster Beispieldaten
	if SEM.RegisterAddon then SEM:RegisterAddon("SexyQuestHelper", { title = "SexyQuestHelper" }) end
	SEM:Register(f, {
		name = "SexyQuestHelper: " .. T("Gruppenabgleich", "Group sync"),
		category = T("Gruppe", "Group"),   -- Zwischenüberschrift in der Seitenleiste des Einstellungsfensters
		addon = "SexyQuestHelper",
		group = "sqh", groupName = "SexyQuestHelper",   -- Tabs im Edit-Mode-Dialog
		description = T("Vergleicht die Quests deines Gebiets mit der Gruppe und zeigt, was abweicht.", "Compares the quests of your zone with your group and shows what differs."),
		sample = SexyQuestHelperSamples and SexyQuestHelperSamples.main,   -- Vorschau im Einstellungsfenster: eigenes Fenster mit eigener Logik (Samples.lua)
		db = db,
		settings = {
			-- Gruppe 1: was die Vorschau verändert; Gruppe 2: Verhalten; Gruppe 3: Erscheinen
			{ type = "header", name = T("Darstellung", "Look"), id = "look" },
			{ type = "check", name = T("Kopfzeile ausblenden", "Hide header"),
				get = function() return cfg.hideHeaderMain end,
				set = function(v) cfg.hideHeaderMain = v and true or false; Refresh() end },
			{ type = "check", name = T("Gebiet im Titel ausblenden", "Hide the zone in the title"),
				get = function() return cfg.hideZone end,
				set = function(v) cfg.hideZone = v and true or false; Refresh() end },
			MV.Spec("width"), MV.Spec("rowH"), MV.Spec("cardGap"), MV.Spec("opacity"), MV.Spec("showShare"), MV.Spec("showPills"),
			MV.Spec("fontDelta"), MV.Spec("bandH"), MV.Spec("bgColor"), MV.Spec("borderColor"), MV.Spec("showAvatar"), MV.Spec("avatarSize"),
			MV.Spec("showStatus"), MV.Spec("showDividers"), MV.Spec("showButtons"),
			{ type = "header", name = T("Verhalten", "Behavior"), id = "behavior" },
			MV.CombatSpec("minMain"),
			{ type = "check", behavior = true, name = T("Fenster \"Mitspielern helfen\" einschalten", "Turn on the \"Help your group\" window"),
				get = function() return cfg.helpAuto end,
				set = function(v) cfg.helpAuto = v and true or false; Refresh() end },
			{ type = "check", behavior = true, name = T("Fehlende Quests automatisch teilen", "Share missing quests automatically"),
				get = function() return cfg.autoShare end,
				set = function(v) cfg.autoShare = v and true or false end },
			{ type = "link", name = T("Mitspielern helfen", "Help your group"), frame = function() return helpUI end },
			{ type = "link", name = T("Quests in der Nähe", "Quests nearby"), frame = function() return nearUI end },
			{ type = "header", name = T("Erscheinen", "Appearing"), id = "appear" },
			{ type = "slider", behavior = true, name = T("Verzögerung bis zum Erscheinen", "Delay before appearing"),
				min = 1, max = 10, step = 1,
				get = function() return cfg.settleDelay end,
				set = function(v) cfg.settleDelay = v end,
				format = function(v) return v .. " s" end },
			{ type = "slider", behavior = true, name = T("Automatisch schließen nach", "Close automatically after"),
				min = 0, max = 60, step = 5,
				get = function() return cfg.autoClose end,
				set = function(v) cfg.autoClose = v end,
				format = function(v) return v == 0 and T("Aus", "Off") or (v .. " s") end },
			{ type = "check", behavior = true, name = T("Ton beim Erscheinen", "Sound when appearing"),
				get = function() return cfg.sound end,
				set = function(v) cfg.sound = v and true or false end },
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

	MV.SetHeader(ui, cfg.hideHeaderMain)
	ui.zone:SetText(myZone ~= "" and myZone or "?")
	ui.zone:SetWidth(0) -- Breite zuruecksetzen, dann natuerliche Breite messen
	local zoneWidth = math.min(ui.zone:GetStringWidth(), 150)
	ui.zone:SetWidth(zoneWidth)
	ui.zoneBg:SetWidth(zoneWidth + 18)
	ui.zone:SetShown(not cfg.hideZone and not ui.headerHidden)
	ui.zoneBg:SetShown(not cfg.hideZone and not ui.headerHidden)

	local y = MV.Head(ui) + 8
	-- Kleine Ansicht: nur Titelband und eine Zeile
	local shown = entries
	if MV.IsMin("minMain") then
		shown = {}
		local text, value = MV.MainSummary(entries)
		y = MV.Head(ui) - 4 + MV.ShowSummary(ui, text, value)
	else
		MV.HideSummary(ui)
	end
	for i, e in ipairs(shown) do
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
	for i = #shown + 1, #rowPool do rowPool[i]:Hide() end

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

---------------------------------------------------------------------------
-- Gemeinsame Darstellung der Ziele einer Quest (Fenster "Quests in der Nähe" und "Mitspielern helfen"):
-- jedes Ziel eine kleine Zeile mit Kästchen, Text, Etikett mit dem Stand und einem Fortschrittsbalken
---------------------------------------------------------------------------

local GOAL_H = 25   -- Mindesthöhe je Ziel (eine Textzeile); lange Ziele brechen um und werden höher
local GOAL_TEXT_X = 33  -- linker Rand des Zieltexts (Kästchen 14 + 13 + 6)

local function HasQuestieDB()
	return _G.QuestDB and _G.NpcDB and _G.ObjectDB and _G.ItemDB
end

-- Ein Ziel: Kästchen, Text und rechts ein Etikett mit dem Stand ("3/8")
-- Kleine Etiketten ("Chips") für den Stand der Gruppenmitglieder: Klassensymbol und Stand ("3/8", Haken, "45 %")
-- auf dunkler Pille wie die übrigen Etiketten. Maus darüber zeigt Name und Stand im Tooltip.
local CHIP_H = 14   -- so hoch wie das eigene Stand-Etikett eines Ziels
-- Farben wie beim eigenen Stand-Etikett (TONES): offen gelb, erledigt grün, unbekannt grau, jeweils mit eigenem Hintergrund
local CHIP_TONE = { open = "warn", done = "ok", none = "grey" }

local function GetChip(owner, pool, i)
	local chip = pool[i]
	if chip then return chip end

	chip = CreateFrame("Frame", nil, owner)
	chip:SetHeight(CHIP_H)
	chip.bg = chip:CreateTexture(nil, "BACKGROUND")
	chip.bg:SetAllPoints()
	chip.bg:SetColorTexture(0.16, 0.145, 0.12, 1)
	chip.icon = chip:CreateTexture(nil, "ARTWORK")
	chip.icon:SetSize(12, 12)
	chip.icon:SetPoint("LEFT", chip, "LEFT", 4, 0)
	chip.text = chip:CreateFontString(nil, "OVERLAY", "SexyQuestHelperSmall")
	chip.text:SetPoint("LEFT", chip.icon, "RIGHT", 4, 0)
	chip:EnableMouse(true)
	if chip.SetPropagateMouseClicks then pcall(chip.SetPropagateMouseClicks, chip, true) end
	chip:SetScript("OnEnter", function(self)
		if not self.item then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(ColoredName(self.item.name))
		if self.item.tip then GameTooltip:AddLine(self.item.tip, 0.85, 0.82, 0.75) end
		GameTooltip:Show()
	end)
	chip:SetScript("OnLeave", function() GameTooltip:Hide() end)
	pool[i] = chip
	return chip
end

-- Legt die Chips (list = { { name, text, state, tip }, ... }) als Badges in eine Reihe, rechtsbündig: der rechte Rand
-- liegt right Pixel vor dem rechten Rand von owner, die Oberkante top Pixel unter dessen Oberkante (also direkt links
-- neben dem eigenen Stand-Etikett). Gibt die belegte Breite zurück (0 ohne Chips).
local function LayoutChips(owner, pool, list, right, top)
	local n = list and #list or 0
	local cx = 0
	for i = n, 1, -1 do
		local item = list[i]
		local chip = GetChip(owner, pool, i)
		chip.item = item
		SetClassIcon(chip.icon, item.name)
		chip.text:SetText(item.text)
		local tone = TONES[CHIP_TONE[item.state] or "grey"]
		chip.bg:SetColorTexture(tone.bg[1], tone.bg[2], tone.bg[3], 1)
		chip.text:SetTextColor(tone.fg[1], tone.fg[2], tone.fg[3])
		local w = 4 + 12 + 4 + math.ceil(chip.text:GetStringWidth()) + 7
		chip:SetWidth(w)
		chip:ClearAllPoints()
		chip:SetPoint("TOPRIGHT", owner, "TOPRIGHT", -(right + cx), -top)
		chip:Show()
		cx = cx + w + 3
	end
	for i = n + 1, #pool do pool[i]:Hide() end
	return n > 0 and (cx - 3) or 0
end

local function GetGoal(row, j)
	local g = row.goals[j]
	if g then return g end

	g = CreateFrame("Frame", nil, row)
	g:SetHeight(GOAL_H)
	g.icon = g:CreateTexture(nil, "ARTWORK")
	g.icon:SetSize(13, 13)
	-- Kästchen, Text und Etikett hängen oben, damit lange Ziele nach unten umbrechen und der Balken darunter Abstand hat
	g.icon:SetPoint("TOPLEFT", g, "TOPLEFT", 14, -4)
	g.pill = MakePill(g)
	g.pill.tex:SetPoint("TOPRIGHT", g, "TOPRIGHT", -8, -3)
	g.text = g:CreateFontString(nil, "OVERLAY", "SexyQuestHelperSmall")
	g.text:SetPoint("TOPLEFT", g, "TOPLEFT", GOAL_TEXT_X, -5)
	g.text:SetJustifyH("LEFT")
	g.text:SetJustifyV("TOP")
	g.text:SetWordWrap(true)
	g.chips = {}   -- Stand der Gruppenmitglieder (nur "Quests in der Nähe"), siehe LayoutChips
	-- Fortschrittsbalken unter dem Ziel, wie im Fenster "Mitspielern helfen"
	g.barBg = g:CreateTexture(nil, "BORDER")
	g.barBg:SetPoint("BOTTOMLEFT", g, "BOTTOMLEFT", GOAL_TEXT_X, 3)
	g.barBg:SetPoint("BOTTOMRIGHT", g, "BOTTOMRIGHT", -8, 3)
	g.barBg:SetHeight(3)
	g.barBg:SetColorTexture(0.21, 0.19, 0.14, 1)
	g.bar = g:CreateTexture(nil, "ARTWORK")
	g.bar:SetPoint("BOTTOMLEFT", g.barBg, "BOTTOMLEFT")
	g.bar:SetHeight(3)
	if SEM.ShineBar then SEM:ShineBar(g.bar) end
	row.goals[j] = g
	return g
end

-- Ziele einer Quest als Liste { name, count, done, hint }: aus dem Questlog ("Wölfe getötet: 3/8" wird zu
-- Name und Stand). Kennt das Questlog keine Ziele (noch nicht geladen), stehen stattdessen die Zielbeschreibungen
-- aus QuestieDB (hint = true, ohne Stand).
-- Stand aus einem Zieltext lesen: "0/1 Hauptmann getötet" (Stand vorn) oder "Wölfe getötet: 3/8" (Stand hinten).
-- Liefert Name ohne Stand, Stand und Ziel (nil, wenn keine Zahl im Text steht).
local function SplitGoalText(text)
	text = tostring(text)
	local a, b, rest = text:match("^%s*(%d+)/(%d+)%s+(.-)%s*$")
	if a then return rest, tonumber(a), tonumber(b) end
	local name, c, d = text:match("^(.-)%s*:?%s*(%d+)/(%d+)%s*$")
	if name and name ~= "" then return name, tonumber(c), tonumber(d) end
	return text
end

local function GoalList(id, objs, data)
	local goals = {}

	-- Bevorzugt die Zieldaten des Questlogs (Stand und Ziel als Zahlen): der Balken braucht keine Zahl im Text
	for _, d in ipairs(data or {}) do
		local name, ta, tb = SplitGoalText(d.text)
		local have, need = d.have or 0, d.need or 0

		-- Liefert das Questlog keine Zielzahl, gilt die Zahl aus dem Text
		if need <= 0 and tb and tb > 0 then
			have, need = ta, tb
		end

		local goal = { name = name, done = d.finished or (need > 0 and have >= need) or false }

		if need > 0 then
			goal.count = math.min(have, need) .. "/" .. need
			goal.frac = math.min(1, have / need)
		end

		goals[#goals + 1] = goal
	end

	if #goals > 0 then return goals end

	for _, text in ipairs(objs or {}) do
		local name, a, b = SplitGoalText(text)

		if a and b and b > 0 then
			goals[#goals + 1] = { name = name, count = math.min(a, b) .. "/" .. b, done = a >= b, frac = math.min(1, a / b) }
		else
			goals[#goals + 1] = { name = name, done = false }
		end
	end

	if #goals == 0 and id and HasQuestieDB() then
		local ok, hints = pcall(QuestDB.Get, id, "objectivesText")

		if ok and type(hints) == "table" then
			for i = 1, math.min(#hints, 3) do
				if type(hints[i]) == "string" and hints[i] ~= "" then
					goals[#goals + 1] = { name = hints[i], done = false, hint = true }
				end
			end
		end
	end

	return goals
end

-- Zeigt die Ziele einer Quest in der Zeile row ab dem Abstand top (Pixel von oben) und gibt die belegte Höhe zurück.
-- Der Zieltext hat eine feste Breite (bis vor das Etikett) und bricht um, statt über den Fensterrand zu laufen.
local function RenderGoals(row, goals, top)
	local y = top
	for j, goal in ipairs(goals) do
		local g = GetGoal(row, j)
		local counts = goal.count and cfg.showCounts ~= false
		-- Badges der Gruppenmitglieder rechts, direkt vor dem eigenen Stand; der Zieltext endet davor
		local own = counts and (38 + 4) or 0
		local cw = LayoutChips(g, g.chips, goal.mates, 8 + own, 3)
		g.text:SetWidth(WIDTH - 24 - GOAL_TEXT_X - 8 - (counts and (38 + 6) or 0) - ((cw > 0) and (cw + 6) or 0))
		g.text:SetText(goal.name)
		local barH = cfg.barH or 3
		local h = math.max(GOAL_H, math.ceil(g.text:GetStringHeight()) + 14) + math.max(0, barH - 3)
		g.barBg:SetHeight(barH)
		g.bar:SetHeight(barH)
		g:ClearAllPoints()
		g:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -y)
		g:SetSize(WIDTH - 24, h)
		y = y + h

		g.icon:SetShown(cfg.showChecks ~= false)
		if goal.done then
			g.icon:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
			g.icon:SetVertexColor(0.45, 0.9, 0.55)
			g.text:SetTextColor(0.55, 0.78, 0.6)
		else
			g.icon:SetTexture("Interface\\Buttons\\UI-CheckBox-Up")
			g.icon:SetVertexColor(0.75, 0.7, 0.6)
			g.text:SetTextColor(goal.hint and 0.61 or 0.9, goal.hint and 0.57 or 0.87, goal.hint and 0.5 or 0.78)
		end

		if goal.count then
			if counts then
				SetPill(g.pill, goal.done and "ok" or "warn", goal.count, 38, 14)
			else
				HidePill(g.pill)
			end
			local bars = cfg.showBars ~= false
			g.barBg:SetShown(bars)
			g.bar:SetShown(bars)
			g.bar:SetWidth(math.max(1, (WIDTH - 24 - GOAL_TEXT_X - 8) * (goal.frac or 0)))
			if goal.done then g.bar:SetColorTexture(0.30, 0.76, 0.42, 1) else g.bar:SetColorTexture(0.94, 0.75, 0.29, 1) end
		else
			HidePill(g.pill)
			g.barBg:Hide()
			g.bar:Hide()
		end

		g:Show()
	end

	for j = #goals + 1, #row.goals do row.goals[j]:Hide() end

	return y - top
end

local HELP_ROW_H, HELP_HEAD_H = 26, 28   -- Questzeile, Kopfzeile
ST.helpRows = {}
ST.helpForce = false      -- per /sqh help erzwungen
ST.helpDismissed = nil    -- weggeklickte Zusammenstellung (Mitglieder und Quests)

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
				-- Hat der Mitspieler die Quest selbst schon fertig (bereit zur Abgabe), braucht er keine Hilfe mehr
				local theirs = progressBy[name] and progressBy[name][id]
				if mine and not (theirs and theirs.ready) and not IsQuestHidden(id) then quests[#quests + 1] = id end
			end
			if #quests > 0 then
				table.sort(quests)
				entries[#entries + 1] = { kind = "header", name = name, count = #quests }
				for _, id in ipairs(quests) do
					local p = progressBy[name] and progressBy[name][id]
					entries[#entries + 1] = { kind = "quest", id = id, pct = p and p.pct, ready = p and p.ready,
						objs = MV.Details(name, id) }
				end
				parts[#parts + 1] = name .. ":" .. table.concat(quests, ",")
			end
		end
	end
	return entries, table.concat(parts, ";")
end

-- Quest aus dem Fenster "Mitspielern helfen" öffnen: im eigenen Questlog wie gewohnt, sonst (meist schon
-- abgegeben) als angeheftetes Quest-Fenster, so wie beim Klick auf einen Quest-Link im Chat
local function OpenHelpQuest(id)
	if IsShiftKeyDown() or myIds[id] then
		OpenQuest(id)
		return
	end
	if SetItemRef then
		pcall(SetItemRef, ("quest:%d:%d"):format(id, UnitLevel("player")), QuestLink(id), "LeftButton")
	end
end

local function GetHelpRow(i)
	local row = ST.helpRows[i]
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
	-- Questzeile: Tooltip mit dem Questtext wie in den anderen Fenstern; Klick öffnet die Quest
	-- (im Questlog, sonst als angeheftetes Quest-Fenster wie ein Link im Chat), Umschalt-Klick verlinkt sie.
	-- Kopfzeile eines Mitglieds: Linksklick fluestert, Rechtsklick visiert an
	row.hl = row:CreateTexture(nil, "HIGHLIGHT")
	row.hl:SetAllPoints()
	row.hl:SetColorTexture(1, 1, 1, 0.08)
	row:SetScript("OnEnter", function(self)
		if self.questId then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, ("quest:%d:%d"):format(self.questId, UnitLevel("player")))
			if not ok then
				GameTooltip:ClearLines()
				GameTooltip:AddLine(QuestName(self.questId))
			end
			if myIds[self.questId] then
				GameTooltip:AddLine(T("Klick: im Questlog öffnen", "Click: open in quest log"), 0.6, 0.6, 0.6)
			else
				GameTooltip:AddLine(T("Klick: Quest anzeigen", "Click: show quest"), 0.6, 0.6, 0.6)
			end
			GameTooltip:AddLine(T("Shift-Klick: Link in den Chat", "Shift-click: link into chat"), 0.6, 0.6, 0.6)
			GameTooltip:AddLine(T("Rechtsklick: ausblenden", "Right-click: hide"), 0.6, 0.6, 0.6)
			GameTooltip:Show()
			return
		end
		if not self.member then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(self.member)
		GameTooltip:AddLine(T("Linksklick: anflüstern", "Left click: whisper"), 0.6, 0.6, 0.6)
		GameTooltip:AddLine(T("Rechtsklick: anvisieren", "Right click: target"), 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	row:SetScript("OnMouseUp", function(self, button)
		if self.questId then
			if not self:IsMouseOver() then return end
			if button == "RightButton" then
				HideQuest(self.questId)
			elseif button == "LeftButton" then
				OpenHelpQuest(self.questId)
			end
			return
		end
		local name = self.member
		if not name or name == "Testmate" then return end
		if button == "RightButton" then
			local unit = unitByName[name]
			if not unit then return end
			if InCombatLockdown() then
				print("|cffe8c26a[SQH]|r " .. T("Im Kampf nicht möglich.", "Not possible in combat."))
			else
				pcall(TargetUnit, unit)
			end
		else
			if ChatFrame_SendTell then ChatFrame_SendTell(name) end
		end
	end)
	-- Streifen am linken Rand und Trennlinie wie im Fenster "Quests in der Nähe"
	row.accent = row:CreateTexture(nil, "ARTWORK")
	row.accent:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
	row.accent:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
	row.accent:SetWidth(3)
	row.divider = row:CreateTexture(nil, "BORDER")
	row.divider:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
	row.divider:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
	row.divider:SetHeight(1)
	row.divider:SetColorTexture(0.21, 0.19, 0.14, 1)
	row.goals = {}
	ST.helpRows[i] = row
	return row
end

-- Ziele einer Quest des Mitglieds: aus dem übermittelten Stand; ohne Einzelziele ein Balken mit dem Gesamtfortschritt
local function HelpGoals(e)
	local goals = GoalList(e.id, e.objs, nil)

	if #goals == 0 then
		local pct = e.ready and 100 or e.pct

		if pct then
			goals = { { name = T("Fortschritt", "Progress"), count = pct .. " %", frac = pct / 100, done = e.ready and true or false } }
		end
	elseif e.ready then
		for _, goal in ipairs(goals) do
			goal.done = true
			if goal.count then goal.frac = 1 end
		end
	end

	return goals
end

-- Richtet die Zeile ein und gibt ihre Höhe zurück (Questtitel und Ziele brechen um)
local function ConfigureHelpRow(row, e, goals)
	local isHeader, isQuest = e.kind == "header", e.kind == "quest"
	row.bg:SetShown(e.kind ~= "info")
	row.bg:SetColorTexture(isHeader and 0.165 or 0.145, isHeader and 0.14 or 0.125, isHeader and 0.10 or 0.10, cfg.opacity)
	row.avatar:SetShown(isHeader and cfg.showAvatar ~= false)
	row.name:SetShown(isHeader)
	row.fs:SetShown(not isHeader)
	row.member = isHeader and e.name or nil
	row.questId = isQuest and e.id or nil
	row:EnableMouse(isHeader or row.questId ~= nil)
	row.hl:SetShown(row.questId ~= nil)
	row.accent:SetShown(isQuest and cfg.showAccent ~= false)
	row.accent:SetWidth(cfg.accentW or 3)
	row.divider:SetShown(false)
	row.pill.tex:ClearAllPoints()

	if isQuest then
		row.pill.tex:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -5)
	else
		row.pill.tex:SetPoint("RIGHT", row, "RIGHT", -8, 0)
	end

	if isHeader then
		local r, g, b = ClassColor(e.name)
		SetClassIcon(row.avatar, e.name)
		row.avatar:SetSize((cfg.avatarSize or 20) - 2, (cfg.avatarSize or 20) - 2)
		row.name:SetText(e.name)
		row.name:SetTextColor(r, g, b)
		if cfg.showStatus ~= false then
			SetPill(row.pill, "they", e.count .. " " .. T("Quests", "quests"), nil, 18)
		else
			HidePill(row.pill)
		end
		MV.NameAnchors(row, row.pill)
		for _, g2 in ipairs(row.goals) do g2:Hide() end
	elseif isQuest then
		row.fs:SetFontObject("SexyQuestHelperText")
		row.fs:ClearAllPoints()
		row.fs:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -6)
		row.fs:SetWidth(WIDTH - 24 - 10 - 60 - 8 - 6)
		row.fs:SetWordWrap(true)
		row.fs:SetJustifyV("TOP")
		row.fs:SetText(e.title or QuestName(e.id))
		row.fs:SetTextColor(0.95, 0.92, 0.86)
		row.accent:SetColorTexture(e.ready and 0.30 or 0.94, e.ready and 0.76 or 0.75, e.ready and 0.42 or 0.29, 1)

		if e.ready then
			SetPill(row.pill, "ok", T("Bereit", "Ready"), 60, 16)
		elseif e.pct then
			SetPill(row.pill, "warn", e.pct .. " %", 60, 16)
		else
			SetPill(row.pill, "grey", "?", 60, 16)
		end

		local top = math.max(HELP_ROW_H, math.ceil(row.fs:GetStringHeight()) + 12)
		local gh = RenderGoals(row, goals or {}, top - 2)
		return gh > 0 and (top + 4 + gh + 4) or top
	else
		row.fs:SetFontObject("SexyQuestHelperSmall")
		row.fs:ClearAllPoints()
		row.fs:SetPoint("LEFT", row, "LEFT", 8, 0)
		row.fs:SetWidth(WIDTH - 24 - 16)
		row.fs:SetWordWrap(true)
		row.fs:SetText("|cff9b9180" .. e.text .. "|r")
		HidePill(row.pill)
		for _, g2 in ipairs(row.goals) do g2:Hide() end
		return math.max(INFO_H, math.ceil(row.fs:GetStringHeight()) + 6)
	end
	return HELP_HEAD_H
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
	f.closeBtn = close
	close:SetScript("OnClick", function()
		ST.helpForce = false
		ST.helpDismissed = f.sig -- erscheint erst wieder bei einer anderen Zusammenstellung
		f:Hide()
	end)
	MV.AddMinButton(f, "minHelp", function() RefreshHelp() end)

	f:Hide()
	SEM:Register(f, {
		name = "SexyQuestHelper: " .. T("Mitspielern helfen", "Help your group"),
		category = T("Gruppe", "Group"),   -- Zwischenüberschrift in der Seitenleiste des Einstellungsfensters
		addon = "SexyQuestHelper",
		group = "sqh", groupName = "SexyQuestHelper",   -- Tabs im Edit-Mode-Dialog
		description = T("Quests, die du schon erledigt hast und Mitspieler noch haben, mit deren Einzelzielen.", "Quests you have finished that group members still have, with their single goals."),
		sample = SexyQuestHelperSamples and SexyQuestHelperSamples.help,   -- Vorschau im Einstellungsfenster: eigenes Fenster mit eigener Logik (Samples.lua)
		db = db,
		settings = {
			{ type = "header", name = T("Darstellung", "Look"), id = "look" },
			{ type = "check", name = T("Kopfzeile ausblenden", "Hide header"),
				get = function() return cfg.hideHeaderHelp end,
				set = function(v) cfg.hideHeaderHelp = v and true or false; RefreshHelp() end },
			MV.Spec("width"), MV.Spec("rowH"), MV.Spec("cardGap"), MV.Spec("opacity"), MV.Spec("showBars"), MV.Spec("barH"),
			MV.Spec("fontDelta"), MV.Spec("bandH"), MV.Spec("bgColor"), MV.Spec("borderColor"), MV.Spec("showAvatar"), MV.Spec("avatarSize"),
			MV.Spec("showStatus"), MV.Spec("showAccent"), MV.Spec("accentW"), MV.Spec("showChecks"), MV.Spec("showCounts"), MV.Spec("showButtons"),
			{ type = "header", name = T("Verhalten", "Behavior"), id = "help" },
			MV.CombatSpec("minHelp"),
			{ type = "check", behavior = true, name = T("Fenster einschalten (öffnet sich von selbst)", "Turn the window on (opens by itself)"),
				get = function() return cfg.helpAuto end,
				set = function(v) cfg.helpAuto = v and true or false; Refresh() end },
			{ type = "check", behavior = true, name = T("Auch Quests zählen, die du noch im Log hast und nur abgeben musst", "Also count quests still in your log that you only have to hand in"),
				get = function() return cfg.helpReady end,
				set = function(v) cfg.helpReady = v and true or false; Refresh() end },
			{ type = "link", name = "SexyQuestHelper", frame = function() return ui end },
		},
		onMoved = function(self) db.anchoredHeight = self:GetHeight() end,
	})
	return f
end

function RefreshHelp()
	if not helpUI then return end
	local entries, sig = BuildHelp()
	helpUI.sig = sig
	local auto = cfg.helpAuto and scanReady and #entries > 0 and sig ~= ST.helpDismissed
	if not (ST.helpForce or testMode or auto) then
		helpUI:Hide()
		return
	end
	if #entries == 0 then
		entries[1] = { kind = "info", text = T("Niemand braucht gerade Hilfe.", "Nobody needs help right now.") }
	end

	MV.SetHeader(helpUI, cfg.hideHeaderHelp)
	local y = MV.Head(helpUI) + 8
	-- Kleine Ansicht: nur Titelband und eine Zeile
	local shown = entries
	if MV.IsMin("minHelp") then
		shown = {}
		MV.HideSummary(helpUI)
		-- wer braucht was: je Mitspieler eine Zeile, darunter seine Quests (wie die Zielzeilen in "Quests in der Nähe")
		local custom = {}
		for _, e in ipairs(entries) do
			if e.kind == "header" then custom[#custom + 1] = { member = true, name = e.name, count = e.count }
			elseif e.kind == "quest" then custom[#custom + 1] = { help = true, id = e.id, title = e.title, pct = e.pct, ready = e.ready }
			elseif e.text then custom[#custom + 1] = { none = true, text = e.text } end
		end
		y = MV.Head(helpUI) + MV.ShowMiniList(helpUI, nil, nil, custom) - 1
	else
		MV.HideSummary(helpUI)
		if helpUI.mini then helpUI.mini:Hide() end
	end
	for i, e in ipairs(shown) do
		local row = GetHelpRow(i)
		local goals = e.kind == "quest" and HelpGoals(e) or nil
		if e.kind == "header" and i > 1 then y = y + CARD_GAP end
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", helpUI, "TOPLEFT", 12, -y)
		row:SetWidth(WIDTH - 24)
		row:Show()
		local h = ConfigureHelpRow(row, e, goals)
		row:SetHeight(h)
		y = y + h
	end
	for i = #shown + 1, #ST.helpRows do ST.helpRows[i]:Hide() end

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

---------------------------------------------------------------------------
-- Drittes Fenster: Quests in der Naehe. Aus den Zielen deiner offenen Quests (QuestieDB: Kreaturen, Objekte,
-- Gegenstaende ueber ihre Droppquellen, Erkundungsbereiche) und deren Spawn-Punkten im aktuellen Gebiet wird
-- bestimmt, welche Quests gerade in Reichweite einer Zielstelle liegen.
---------------------------------------------------------------------------

local NEAR_ROW_H = 26   -- Kopfzeile einer Quest

-- Größen und Aussehen nach den Einstellungen (Breite, Zeilenhöhe, Kartenabstand, Deckkraft); wirkt auf alle drei Fenster
function MV.ApplySizes()
	WIDTH = cfg.width
	QUEST_H = cfg.rowH
	HEADER_H = cfg.rowH + 6
	HELP_ROW_H = cfg.rowH + 2
	HELP_HEAD_H = cfg.rowH + 4
	NEAR_ROW_H = cfg.rowH + 2
	CARD_GAP = cfg.cardGap
	MV.MINI_W = WIDTH
	BAND_H = cfg.bandH
	-- Schriftgrößen (die drei Schriftobjekte gelten für alle Texte der Fenster)
	local d = cfg.fontDelta or 0
	if SexyQuestHelperTitle then SexyQuestHelperTitle:SetFont(LoadFont("Marcellus-Regular.ttf"), 14 + d, "") end
	if SexyQuestHelperText then SexyQuestHelperText:SetFont(LoadFont("Inter.ttf"), 13 + d, "") end
	if SexyQuestHelperSmall then SexyQuestHelperSmall:SetFont(LoadFont("Inter.ttf"), 11 + d, "") end
	for _, f in ipairs({ ui, helpUI, nearUI }) do
		if f then
			f:SetWidth(WIDTH)
			f:SetBackdropColor(cfg.bgColor.r, cfg.bgColor.g, cfg.bgColor.b, cfg.opacity)
			f:SetBackdropBorderColor(cfg.borderColor.r, cfg.borderColor.g, cfg.borderColor.b, 1)
			if f.band then
				f.band:SetHeight(BAND_H - 3)
				f.band:SetColorTexture(0.15, 0.12, 0.07, cfg.opacity)
				f.title:ClearAllPoints()
				f.title:SetPoint("LEFT", f.band, "LEFT", 9, 0)
				if f.zoneBg then
					f.zoneBg:ClearAllPoints()
					f.zoneBg:SetPoint("RIGHT", f.band, "RIGHT", -53, 0)
				end
				if f.minFrame then
					f.minFrame:ClearAllPoints()
					f.minFrame:SetPoint("RIGHT", f.band, "RIGHT", -29, 0)
				end
			end
		end
	end
	if nearUI then
		nearUI.scroll:SetWidth(WIDTH)
		nearUI.content:SetWidth(WIDTH)
	end
end

-- Name der Mitspieler-Kopfzeile: links am Klassensymbol (oder am Rand), rechts am Etikett (oder am Rand)
function MV.NameAnchors(row, pill)
	row.name:ClearAllPoints()
	if cfg.showAvatar ~= false then
		row.name:SetPoint("LEFT", row.avatar, "RIGHT", 8, 0)
	else
		row.name:SetPoint("LEFT", row, "LEFT", 8, 0)
	end
	if cfg.showStatus ~= false then
		row.name:SetPoint("RIGHT", pill.tex, "LEFT", -6, 0)
	else
		row.name:SetPoint("RIGHT", row, "RIGHT", -8, 0)
	end
end

-- weitere Aussehen-Werte: key = { Art, Name de, Name en, [min, max, Schritt, Faktor, Format] }
MV.NEW = {
	fontDelta = { "slider", "Schriftgröße", "Font size", -2, 4, 1, 1, function(v) return (v > 0 and "+" or "") .. v end },
	bandH = { "slider", "Höhe der Titelleiste", "Height of the title band", 26, 40, 1, 1, function(v) return v .. " px" end },
	avatarSize = { "slider", "Größe des Klassensymbols", "Size of the class icon", 14, 28, 1, 1, function(v) return v .. " px" end },
	accentW = { "slider", "Breite des Farbstreifens", "Width of the colored stripe", 2, 8, 1, 1, function(v) return v .. " px" end },
	glowAlpha = { "slider", "Stärke des Aufleuchtens", "Strength of the glow", 10, 80, 5, 100, function(v) return v .. " %" end },
	showAvatar = { "check", "Klassensymbol der Mitspieler zeigen", "Show the class icon of the members" },
	showStatus = { "check", "Etiketten der Mitspieler zeigen", "Show the labels of the members" },
	showAccent = { "check", "Farbstreifen links zeigen", "Show the colored stripe on the left" },
	showDividers = { "check", "Trennlinien zeigen", "Show the dividers" },
	showDist = { "check", "Entfernung zeigen", "Show the distance" },
	showChecks = { "check", "Kästchen vor den Zielen zeigen", "Show the boxes before the goals" },
	showCounts = { "check", "Zähler der Ziele zeigen", "Show the counters of the goals" },
	showButtons = { "check", "Knöpfe in der Titelleiste zeigen", "Show the buttons in the title band" },
	showScroll = { "check", "Scrollbalken zeigen", "Show the scroll bar" },
	bgColor = { "color", "Hintergrundfarbe", "Background color" },
	borderColor = { "color", "Randfarbe", "Border color" },
	glowColor = { "color", "Farbe des Aufleuchtens", "Color of the glow", },
}

-- Einstellungszeile zu einem Aussehen-Wert (key: width, rowH, cardGap, opacity, showShare, showPills, showBars, barH und MV.NEW)
function MV.Spec(key)
	local function Apply()
		MV.ApplySizes()
		Refresh()
	end
	local d = MV.NEW[key]
	if d then
		local name = T(d[2], d[3])
		if d[1] == "slider" then
			local scale = d[7]
			return { type = "slider", name = name, min = d[4], max = d[5], step = d[6], format = d[8],
				get = function() return math.floor((cfg[key] or 0) * scale + 0.5) end,
				set = function(v) cfg[key] = v / scale; Apply() end }
		elseif d[1] == "check" then
			return { type = "check", name = name,
				get = function() return cfg[key] ~= false end,
				set = function(v) cfg[key] = v and true or false; Apply() end }
		else
			return { type = "color", name = name,
				get = function() local c = cfg[key]; return c.r, c.g, c.b, 1 end,
				set = function(r, g, b) cfg[key] = { r = r, g = g, b = b }; Apply() end }
		end
	end
	if key == "width" then
		return { type = "slider", name = T("Breite der Fenster", "Width of the windows"), min = 280, max = 560, step = 4,
			get = function() return cfg.width end, set = function(v) cfg.width = v; Apply() end,
			format = function(v) return v .. " px" end }
	elseif key == "rowH" then
		return { type = "slider", name = T("Zeilenhöhe", "Row height"), min = 18, max = 40, step = 1,
			get = function() return cfg.rowH end, set = function(v) cfg.rowH = v; Apply() end,
			format = function(v) return v .. " px" end }
	elseif key == "cardGap" then
		return { type = "slider", name = T("Abstand der Karten", "Gap between cards"), min = 0, max = 16, step = 1,
			get = function() return cfg.cardGap end, set = function(v) cfg.cardGap = v; Apply() end,
			format = function(v) return v .. " px" end }
	elseif key == "opacity" then
		return { type = "slider", name = T("Deckkraft der Fenster", "Window opacity"), min = 30, max = 100, step = 2,
			get = function() return math.floor(cfg.opacity * 100 + 0.5) end, set = function(v) cfg.opacity = v / 100; Apply() end,
			format = function(v) return v .. " %" end }
	elseif key == "barH" then
		return { type = "slider", name = T("Höhe der Fortschrittsbalken", "Height of the progress bars"), min = 2, max = 10, step = 1,
			get = function() return cfg.barH or 3 end, set = function(v) cfg.barH = v; Apply() end,
			format = function(v) return v .. " px" end }
	elseif key == "showShare" then
		return { type = "check", name = T("Teilen-Knopf zeigen", "Show the share button"),
			get = function() return cfg.showShare ~= false end, set = function(v) cfg.showShare = v and true or false; Apply() end }
	elseif key == "showPills" then
		return { type = "check", name = T("Etiketten bei den Quests zeigen", "Show the labels on the quests"),
			get = function() return cfg.showPills ~= false end, set = function(v) cfg.showPills = v and true or false; Apply() end }
	else
		return { type = "check", name = T("Fortschrittsbalken der Ziele zeigen", "Show the progress bars of the goals"),
			get = function() return cfg.showBars ~= false end, set = function(v) cfg.showBars = v and true or false; Apply() end }
	end
end
ST.nearRows = {}
ST.nearForce = false       -- per /sqh near erzwungen
ST.nearDismissed = nil     -- weggeklickte Zusammenstellung
ST.nearKnown = {}          -- Quests, die beim letzten Durchlauf schon in der Naehe waren (fuer den Ton)
ST.nearSeen = {}           -- Quest -> Zeitpunkt, zu dem sie zuletzt in der Naehe war
ST.NEAR_AGAIN = 120        -- Sekunden: eine Quest, die so kurz zuvor schon da war (Grenze der Reichweite), zaehlt nicht als neu
ST.pointsCache = {}        -- [Quest] = { zoneKey, points = { {x, y}, ... }, known = Zahl der Punkte aus QuestieDB }
ST.progressAt = {}         -- [Quest] = GetTime() des letzten Fortschritts (für Quests ohne festen Ort)
ST.areaNames = {}          -- [AreaId] = Name oder false

ST.areaMaps = {}           -- [AreaId] = UiMapID (aus Questies ZoneDB) oder false

local debugAreas              -- nur fuer /sqh near debug: [AreaId] = true, alle gesehenen Gebiete

-- Namen sprachneutral vergleichbar machen (Gross/Klein, Leerzeichen am Rand)
local function NormName(name)
	if type(name) ~= "string" then return nil end
	name = name:lower():gsub("^%s+", ""):gsub("%s+$", "")
	return name ~= "" and name or nil
end

-- Gesuchtes Gebiet: Zonenkarte (ID) und ihre Namen in der Sprache des Clients
local function Wanted(mapID, ...)
	local wanted = { mapID = mapID, names = {} }
	for i = 1, select("#", ...) do
		local n = NormName((select(i, ...)))
		if n then wanted.names[n] = true end
	end
	-- Gebiet mit Ersatz (z. B. Alterac-Gebirge -> Hillsbrad): Ziele im Ersatzgebiet zählen mit
	local alias = mapID and SexyQuestHelperZoneAlias[mapID]
	if alias then
		wanted.aliasMapID = alias
		local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(alias)
		local n = info and NormName(info.name)
		if n then wanted.names[n] = true end
	end
	return wanted
end

-- Questie (falls geladen) kennt die Zuordnung AreaId -> UiMapID; damit ist der Vergleich unabhaengig
-- von der Client-Sprache. Nil = keine Zuordnung bekannt.
local function AreaToMap(areaId)
	local m = ST.areaMaps[areaId]
	if m == nil then
		m = false
		local loader = _G.QuestieLoader
		if loader and loader.ImportModule then
			local ok, zoneDB = pcall(loader.ImportModule, loader, "ZoneDB")
			if ok and zoneDB and zoneDB.GetUiMapIdByAreaId then
				local ok2, id = pcall(zoneDB.GetUiMapIdByAreaId, zoneDB, areaId)
				if ok2 and type(id) == "number" and id > 0 then m = id end
			end
		end
		ST.areaMaps[areaId] = m
	end
	return m or nil
end

local function AreaName(areaId)
	local name = ST.areaNames[areaId]
	if name == nil then
		local ok, value = pcall(function()
			if C_Map and C_Map.GetAreaInfo then return C_Map.GetAreaInfo(areaId) end
		end)
		name = ok and value or false
		ST.areaNames[areaId] = name
	end
	return name or nil
end

local function AreaMatches(areaId, wanted)
	if debugAreas then debugAreas[areaId] = true end

	if wanted.areaId and areaId == wanted.areaId then return true end

	local m = AreaToMap(areaId)
	if m and (m == wanted.mapID or m == wanted.aliasMapID) then return true end

	local n = NormName(AreaName(areaId))
	return n and wanted.names[n] and true or false
end

-- Spawn-Punkte (Prozent der Zonenkarte) im gesuchten Gebiet sammeln; mit Obergrenze gegen riesige Droplisten
local function AddSpawns(points, spawns, wanted)
	if type(spawns) ~= "table" then return end

	for areaId, list in pairs(spawns) do
		if #points < 1500 and AreaMatches(areaId, wanted) then
			for _, c in ipairs(list) do
				if type(c) == "table" and c[1] and c[2] then points[#points + 1] = c end
			end
		end
	end
end

local function QuestPoints(id, wanted, zoneKey)
	local cached = ST.pointsCache[id]
	if cached and cached.zoneKey == zoneKey then return cached.points, cached.known end

	local points = {}
	local notes = {}          -- nur für /sqh near debug: warum eine Quest in der Instanz fehlt
	local belongsHere = false -- die Quest selbst gehört laut QuestieDB zu dieser Instanz

	if HasQuestieDB() then pcall(function()
		local obj = QuestDB.Get(id, "objectives") or {}
		if wanted.areaId and QuestDB.Get(id, "zoneOrSort") == wanted.areaId then belongsHere = true end
		local function npc(npcId) AddSpawns(points, NpcDB.Get(npcId, "spawns"), wanted) end
		local function object(objectId) AddSpawns(points, ObjectDB.Get(objectId, "spawns"), wanted) end

		for _, e in ipairs(obj[1] or {}) do npc(e[1]) end            -- Kreaturen
		for _, e in ipairs(obj[2] or {}) do object(e[1]) end         -- Objekte

		-- In einer Instanz zählt ein Gegenstand nur, wenn mindestens die Hälfte seiner Droppquellen (mit bekannten
		-- Spawns) dort lebt oder er nur wenige Quellen hat und eine davon dort. Sonst käme jede Quest in die Liste, deren Gegenstand irgendwo auch in der Instanz fällt
		-- (z. B. Fleisch, das viele Kreaturen in der ganzen Welt fallen lassen).
		local function ItemMostlyHere(npcs, itemId)
			local inside, total = 0, 0
			for i = 1, math.min(#npcs, 40) do
				local spawns = NpcDB.Get(npcs[i], "spawns")
				if spawns and next(spawns) then
					total = total + 1
					local probe = {}
					AddSpawns(probe, spawns, wanted)
					if #probe > 0 then inside = inside + 1 end
				end
			end
			notes[#notes + 1] = ("Item %s: %d of %d drop sources are in the instance"):format(tostring(itemId), inside, total)
			-- mindestens die Hälfte der Quellen in der Instanz, oder wenige Quellen insgesamt und eine davon dort
			-- (Instanz-Quests, deren Gegenstand auch vor dem Eingang fällt)
			return total > 0 and (inside * 2 >= total or (inside > 0 and total <= 8))
		end

		for _, e in ipairs(obj[3] or {}) do                          -- Gegenstaende: ueber ihre Droppquellen
			local npcs = ItemDB.Get(e[1], "npcDrops") or {}
			if not wanted.instanceID or ItemMostlyHere(npcs, e[1]) then
				for i = 1, math.min(#npcs, 40) do npc(npcs[i]) end
				local objects = ItemDB.Get(e[1], "objectDrops") or {}
				for i = 1, math.min(#objects, 20) do object(objects[i]) end
			end
		end

		for _, e in ipairs(obj[5] or {}) do                          -- Sammel-Kreaturen (Kill Credit)
			for _, n in ipairs(e[1] or {}) do npc(n) end
		end

		local trigger = QuestDB.Get(id, "triggerEnd")                -- Erkundungsbereich
		if type(trigger) == "table" then AddSpawns(points, trigger[2], wanted) end
	end) end

	local known = #points   -- Orte aus QuestieDB; 0 heißt: kein richtiger Ort bekannt
	-- Quests, die QuestieDB selbst dieser Instanz zuordnet, gehören auch ohne passende Ziele in die Liste
	if belongsHere and known == 0 then known = 1 end

	-- Gelernte Orte: dort, wo der Fortschritt dieser Quest gestiegen ist (z. B. nach dem ersten Kill)
	local learned = SexyQuestHelperDB.learned and SexyQuestHelperDB.learned[id]
	if learned and learned[zoneKey] then
		for _, c in ipairs(learned[zoneKey]) do points[#points + 1] = c end
	end

	ST.pointsCache[id] = { zoneKey = zoneKey, points = points, known = known, notes = notes }
	return points, known
end

-- Zonenkarte des Spielers (von einer Unterkarte aus nach oben) und ihr Name
local function ZoneMap()
	if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetMapInfo) then return end
	local mapID = C_Map.GetBestMapForUnit("player")
	local zoneType = (Enum and Enum.UIMapType and Enum.UIMapType.Zone) or 3

	for _ = 1, 5 do
		if not mapID then return end
		local info = C_Map.GetMapInfo(mapID)
		if not info then return end
		if info.mapType == zoneType then return mapID, info.name end
		mapID = info.parentMapID
	end
end

-- Für QuestTargets.lua: Namen der Kreaturen, die im aktuellen Gebiet leben und einen Gegenstand dieser Quest fallen lassen
-- (Droppquellen aus QuestieDB, nur solche mit Spawns hier). Ohne QuestieDB leer.
_G.SexyQuestHelperAPI = _G.SexyQuestHelperAPI or {}
-- Zustand für die Vorschau im Einstellungsfenster (Samples.lua zeichnet eigene Fenster damit)
function SexyQuestHelperAPI.Sample()
	return { cfg = cfg, WIDTH = WIDTH, T = T }
end
-- Für QuestTargets.lua: hat die Quest (laut QuestieDB) Ziele im aktuellen Gebiet? Der Kopf im Questlog zeigt nur, wo man
-- sie angenommen hat (z. B. Donnerfels), die Ziele können woanders liegen (Eschental).
function SexyQuestHelperAPI.QuestHere(questId)
	local ok, here = pcall(function()
		local mapID, mapName = ZoneMap()
		if not mapID then return false end
		local _, known = QuestPoints(questId, Wanted(mapID, GetRealZoneText(), mapName), mapID)
		return (known or 0) > 0
	end)
	return ok and here or false
end
-- Für QuestTargets.lua: Entfernung (in Metern) von dir zum nächsten Zielort der Quest im aktuellen Gebiet, aus den Orten
-- von QuestieDB (wie in "Quests in der Nähe"); nil, wenn keine Position oder kein Ort bekannt ist.
function SexyQuestHelperAPI.QuestDistance(questId)
	local ok, dist = pcall(function()
		local mapID, mapName = ZoneMap()
		if not mapID then return nil end
		local pos = C_Map.GetPlayerMapPosition(mapID, "player")
		if not pos then return nil end
		local px, py = pos:GetXY()
		if not (px and py) or (px == 0 and py == 0) then return nil end
		local width, height = 4000, 3000
		if C_Map.GetMapWorldSize then
			local w, h = C_Map.GetMapWorldSize(mapID)
			if w and h and w > 0 and h > 0 then width, height = w, h end
		end
		local points = QuestPoints(questId, Wanted(mapID, GetRealZoneText(), mapName), mapID)
		local best
		for _, c in ipairs(points or {}) do
			local dx, dy = (px - c[1] / 100) * width, (py - c[2] / 100) * height
			local d = math.sqrt(dx * dx + dy * dy)
			if not best or d < best then best = d end
		end
		return best
	end)
	return ok and dist or nil
end
-- Für QuestTargets.lua: Reichweite von "Quests in der Nähe" in Metern (gleiche Grenze für die Quest-Aktionen)
function SexyQuestHelperAPI.NearRadius() return cfg.nearRadius end
-- Für QuestTargets.lua: { [Monstername] = Kreatur-ID } der Ziele einer Quest aus QuestieDB (für das 3D-Bild). Ohne QuestieDB leer.
function SexyQuestHelperAPI.MobIds(questId)
	local ids = {}
	if not HasQuestieDB() then return ids end
	pcall(function()
		local obj = QuestDB.Get(questId, "objectives") or {}
		local function add(npcId)
			local name = npcId and NpcDB.Get(npcId, "name")
			if type(name) == "string" and name ~= "" and not ids[name] then ids[name] = npcId end
		end
		for _, e in ipairs(obj[1] or {}) do add(e[1]) end
		for _, e in ipairs(obj[5] or {}) do for _, n in ipairs(e[1] or {}) do add(n) end end
	end)
	return ids
end
-- Für QuestTargets.lua: lebt die Kreatur laut QuestieDB im aktuellen Gebiet? Beschworene Wesen und Ereignisziele
-- (z. B. "Auge von Kilrogg zur Straße geführt") haben keine Spawns in der Welt.
function SexyQuestHelperAPI.MobHere(npcId)
	local ok, here = pcall(function()
		local mapID, mapName = ZoneMap()
		if not (mapID and npcId) then return false end
		local spawns = NpcDB.Get(npcId, "spawns")
		-- Kennt QuestieDB gar keine Spawns (Lücke in den Daten), wird das Monster nicht ausgeblendet; nur "lebt woanders" blendet aus
		if type(spawns) ~= "table" or next(spawns) == nil then return true end
		local probe = {}
		AddSpawns(probe, spawns, Wanted(mapID, GetRealZoneText(), mapName))
		return #probe > 0
	end)
	return ok and here or false
end
-- itemIndex/objText (optional): nur die Gegenstandsziele, die zu diesem Eintrag im Questlog gehören (Zieltext oder n-tes Gegenstandsziel);
-- ohne sie zählen alle Gegenstände der Quest. Sonst bekäme jede Kreatur die Zahl des ersten Ziels ("7/10" auch für die Spinne mit 0/1).
function SexyQuestHelperAPI.DropMobs(questId, limit, itemIndex, objText)
	local names, ids = {}, {}   -- zweiter Rückgabewert: { [Name] = Kreatur-ID } für das 3D-Bild
	if not HasQuestieDB() then return names, ids end
	pcall(function()
		local mapID, mapName = ZoneMap()
		local wanted = Wanted(mapID, GetRealZoneText(), mapName)
		local obj = QuestDB.Get(questId, "objectives") or {}
		local items = obj[3] or {}
		if objText or itemIndex then
			local low = type(objText) == "string" and strlower(objText) or nil
			local picked = {}
			for _, e in ipairs(items) do
				local iname = low and ItemDB.Get(e[1], "name")
				if type(iname) == "string" and iname ~= "" and low:find(strlower(iname), 1, true) then picked[#picked + 1] = e end
			end
			if #picked == 0 and itemIndex and items[itemIndex] then picked[1] = items[itemIndex] end
			if #picked > 0 then items = picked end
		end
		for _, e in ipairs(items) do
			local npcs = ItemDB.Get(e[1], "npcDrops") or {}
			for i = 1, math.min(#npcs, 200) do
				local probe = {}
				AddSpawns(probe, NpcDB.Get(npcs[i], "spawns"), wanted)
				if #probe > 0 then
					local name = NpcDB.Get(npcs[i], "name")
					if type(name) == "string" and name ~= "" then
						names[#names + 1] = name
						ids[name] = npcs[i]
						if limit and #names >= limit then return end
					end
				end
			end
		end
	end)
	return names, ids
end

-- Dungeons und Schlachtzuege haben in Classic keine Karte: GetBestMapForUnit liefert nil, eine Position gibt es nicht.
-- Instanz-ID (GetInstanceInfo) -> AreaId, unter der QuestieDB die Spawns der Instanz fuehrt (sprachunabhaengig);
-- fehlt eine Instanz hier, wird ueber den Namen verglichen.
local INSTANCE_AREAS = {
	[33] = 209,   [36] = 1581,  [34] = 717,   [43] = 718,   [47] = 491,   [48] = 719,   [70] = 1337,  [90] = 721,
	[109] = 1477, [129] = 722,  [189] = 796,  [209] = 1176, [229] = 1583, [230] = 1584, [249] = 2159, [289] = 2057,
	[309] = 1977, [329] = 2017, [349] = 2100, [389] = 2437, [409] = 2717, [429] = 2557, [469] = 2677, [509] = 3429,
	[531] = 3428, [533] = 3456,
}

-- Gesuchtes Gebiet in einer Instanz (Dungeon/Schlachtzug) oder nil, wenn man nicht in einer ist
local function InstanceWanted()
	if not IsInInstance then return end
	local inInstance, instanceType = IsInInstance()
	if not inInstance or (instanceType ~= "party" and instanceType ~= "raid") then return end

	local name, instanceID
	if GetInstanceInfo then
		local n, _, _, _, _, _, _, id = GetInstanceInfo()
		name, instanceID = n, id
	end
	local wanted = Wanted(nil, GetRealZoneText(), name)
	wanted.areaId = instanceID and INSTANCE_AREAS[instanceID]
	wanted.instanceID = instanceID
	return wanted, "i" .. tostring(instanceID or GetRealZoneText())
end

-- In einer Instanz: alle Quests aus dem Log, deren Ziele (laut QuestieDB) in dieser Instanz liegen. Ohne Position
-- gibt es keine Entfernung, die Quests stehen einfach in der Liste, solange man in der Instanz ist.
local function ComputeNearInstance(wanted, zoneKey)
	local list = {}
	for id in pairs(myLogIds) do
		if not IsQuestHidden(id) then
			local _, known = QuestPoints(id, wanted, zoneKey)
			-- Auch Quests, die das Questlog unter dem Namen dieser Instanz führt: ihre Ziele liegen oft draußen vor dem Eingang
			local header = myLogIds[id]
			local listedHere = type(header) == "string" and wanted.names[NormName(header)]
			if known > 0 or listedHere then
				local p = myProgress[id]
				if not p then
					local pct, ready, texts, data = QuestProgress(id)
					p = { pct = pct, ready = ready, objs = texts, goals = data }
				end
				if not p.ready then
					list[#list + 1] = { id = id, instance = true, objs = p.objs, goals = p.goals }
				end
			end
		end
	end
	table.sort(list, function(a, b) return QuestName(a.id) < QuestName(b.id) end)
	return list
end

-- Quests, deren Zielstellen im Umkreis liegen: { { id, dist }, ... } nach Entfernung sortiert
local function ComputeNear()
	local list = {}

	local mapID, mapName = ZoneMap()
	if not mapID then
		local wanted, zoneKey = InstanceWanted()
		if wanted then return ComputeNearInstance(wanted, zoneKey) end
		return list
	end

	local pos = C_Map.GetPlayerMapPosition(mapID, "player")
	local px, py
	if pos then px, py = pos:GetXY() end

	-- Keine Position (z. B. in Dalaran, wo es für diese Karte keine gibt): keine Entfernung möglich. Dann stehen die
	-- offenen Quests des Gebiets einfach in der Liste, wie in einer Instanz ("Dungeon"); fertige bleiben draußen.
	if not (px and py) or (px == 0 and py == 0) then
		-- Nur Quests, die das Questlog unter dem Namen genau dieses Ortes führt (nicht die des Ersatzgebiets, z. B. Hillsbrad)
		local here = { [NormName(GetRealZoneText()) or ""] = true, [NormName(GetZoneText()) or ""] = true }
		for id in pairs(myIds) do
			local header = myLogIds[id]
			if not IsQuestHidden(id) and type(header) == "string" and here[NormName(header) or ""] then
				local p = myProgress[id]
				if not (p and p.ready) then
					list[#list + 1] = { id = id, instance = true, objs = p and p.objs, goals = p and p.goals }
				end
			end
		end
		table.sort(list, function(a, b) return QuestName(a.id) < QuestName(b.id) end)
		return list
	end

	local width, height = 4000, 3000
	if C_Map.GetMapWorldSize then
		local w, h = C_Map.GetMapWorldSize(mapID)
		if w and h and w > 0 and h > 0 then width, height = w, h end
	end

	local wanted = Wanted(mapID, GetRealZoneText(), mapName)
	local radius = cfg.nearRadius

	local now = GetTime()
	local hold = (cfg.nearHold or 3) * 60

	-- alle Quests im Log, egal unter welcher Überschrift: sie zeigt den Ort der Annahme, die Ziele liegen oft woanders
	for id in pairs(myLogIds) do
		if not IsQuestHidden(id) then
			local p = myProgress[id] or ComputeProgress({ [id] = true })[id]
			local points, known = QuestPoints(id, wanted, mapID)
			local best

			for _, c in ipairs(points) do
				local dx, dy = (px - c[1] / 100) * width, (py - c[2] / 100) * height
				local d = math.sqrt(dx * dx + dy * dy)
				if not best or d < best then best = d end
			end

			-- Quest ohne richtigen Ort (QuestieDB kennt keinen): nach einem Fortschritt bleibt sie ein paar Minuten
			-- in der Liste, egal wo man steht; danach verschwindet sie
			local held = known == 0 and ST.progressAt[id] and (now - ST.progressAt[id]) < hold

			if best and best <= radius and not (p and p.ready) then
				list[#list + 1] = { id = id, dist = best, objs = p and p.objs, goals = p and p.goals }
			elseif held then
				list[#list + 1] = { id = id, dist = best, held = true, age = now - ST.progressAt[id], objs = p and p.objs, goals = p and p.goals }
			end
		end
	end

	table.sort(list, function(a, b)
		if a.held ~= b.held then return not a.held end   -- Quests in Reichweite zuerst
		return (a.dist or 1e9) < (b.dist or 1e9)
	end)
	return list
end

-- Beim Spielen lernen: Steigt der Fortschritt einer Quest, ist man in ihrem Bereich. Position (in Prozent der
-- Zonenkarte) merken, je Quest und Karte höchstens 40 Punkte, nahe Punkte werden zusammengefasst.
local function LearnQuestPoint(id)
	local mapID = ZoneMap()
	if not mapID then return end
	local pos = C_Map.GetPlayerMapPosition(mapID, "player")
	if not pos then return end
	local x, y = pos:GetXY()
	if not (x and y) or (x == 0 and y == 0) then return end
	x, y = x * 100, y * 100

	SexyQuestHelperDB.learned = SexyQuestHelperDB.learned or {}
	local byMap = SexyQuestHelperDB.learned[id] or {}
	SexyQuestHelperDB.learned[id] = byMap
	local list = byMap[mapID] or {}
	byMap[mapID] = list

	for _, c in ipairs(list) do
		if math.abs(c[1] - x) < 0.4 and math.abs(c[2] - y) < 0.4 then return end
	end

	if #list >= 40 then table.remove(list, 1) end
	list[#list + 1] = { x, y }
end

local function GetNearRow(i)
	local row = ST.nearRows[i]
	if row then return row end

	row = CreateFrame("Button", nil, nearUI.content)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints()
	row.bg:SetColorTexture(0.145, 0.125, 0.10, 1)
	row.hl = row:CreateTexture(nil, "HIGHLIGHT")
	row.hl:SetAllPoints()
	row.hl:SetColorTexture(1, 1, 1, 0.08)
	-- Wie im Hauptfenster: Tooltip mit dem Questtext, Klick öffnet die Quest im Questlog, Umschalt-Klick verlinkt sie
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
		GameTooltip:AddLine(self.hiddenView and T("Rechtsklick: wieder einblenden", "Right-click: show again")
			or T("Rechtsklick: hier ausblenden", "Right-click: hide here"), 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	row:SetScript("OnClick", function(self, button)
		if not self.questId then return end
		if button == "RightButton" then
			if self.hiddenView then UnhideQuest(self.questId) else HideQuest(self.questId) end
		else
			OpenQuest(self.questId)
		end
	end)
	row.pill = MakePill(row)
	row.pill.tex:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -5)
	row.fs = row:CreateFontString(nil, "OVERLAY", "SexyQuestHelperText")
	row.fs:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -6)
	row.fs:SetPoint("RIGHT", row.pill.tex, "LEFT", -6, 0)
	row.fs:SetJustifyH("LEFT")
	row.fs:SetWordWrap(false)
	row.chips = {}   -- Stand der Gruppenmitglieder zur ganzen Quest, unter dem Titel
	-- Streifen am linken Rand: gelb, solange Ziele offen sind, grün, wenn alle erledigt sind
	row.accent = row:CreateTexture(nil, "ARTWORK")
	row.accent:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
	row.accent:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
	row.accent:SetWidth(3)
	-- dünne Trennlinie oben
	row.divider = row:CreateTexture(nil, "BORDER")
	row.divider:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
	row.divider:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
	row.divider:SetHeight(1)
	row.divider:SetColorTexture(0.21, 0.19, 0.14, 1)
	row.goals = {}
	ST.nearRows[i] = row
	return row
end

-- Stand der Gruppenmitglieder zu einer Quest für "Quests in der Nähe" als Chips (siehe LayoutChips).
-- perGoal[j] = Chips für Ziel j (nur wenn die Zahl der Ziele passt), quest = Chips für die ganze Quest
-- (ohne passende Einzelziele: Prozent; fertig/abgegeben; ohne Addon nur "?" über die Blizzard-API).
local CHECK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:11|t"

local function NearMates(id, goalCount)
	local perGoal, quest = {}, {}
	if not (cfg.nearMates and id) then return perGoal, quest end

	for _, name in ipairs(GroupNames()) do
		local prog = progressBy[name] and progressBy[name][id]
		local det = MV.Details(name, id)

		if ST.completedBy[name] and ST.completedBy[name][id] then
			quest[#quest + 1] = { name = name, text = CHECK, state = "done", tip = T("Quest abgegeben", "Quest turned in") }
		elseif prog and prog.ready then
			quest[#quest + 1] = { name = name, text = CHECK, state = "done", tip = T("Alle Ziele erledigt", "All goals done") }
		elseif det and goalCount > 0 and #det == goalCount then
			for j, text in ipairs(det) do
				local goalName, a, b = SplitGoalText(text)
				if a and b and b > 0 then
					perGoal[j] = perGoal[j] or {}
					local done = a >= b
					perGoal[j][#perGoal[j] + 1] = { name = name, text = done and CHECK or (math.min(a, b) .. "/" .. b),
						state = done and "done" or "open", tip = goalName .. ": " .. math.min(a, b) .. "/" .. b }
				end
			end
		elseif prog then
			quest[#quest + 1] = { name = name, text = prog.pct .. " %", state = "open", tip = T("Fortschritt ", "Progress ") .. prog.pct .. " %" }
		elseif not members[name] then
			-- ohne Addon: Blizzard verrät nur, ob das Mitglied die Quest hat
			local unit = unitByName[name]
			if unit and C_QuestLog and C_QuestLog.IsUnitOnQuest then
				local ok, on = pcall(C_QuestLog.IsUnitOnQuest, unit, id)
				if ok and on then
					quest[#quest + 1] = { name = name, text = "?", state = "none",
						tip = T("Hat die Quest (ohne Addon, Stand unbekannt)", "Has the quest (no addon, progress unknown)") }
				end
			end
		end
	end

	return perGoal, quest
end

local function BuildNear()
	if testMode then
		return {
			{ title = T("Beispiel-Quest", "Sample quest"), dist = 24,
				objs = { T("Wölfe getötet: 8/8", "Wolves slain: 8/8"), T("Fell: 0/1", "Pelt: 0/1") },
				testMates = { { { name = "Testmate", text = "5/8", state = "open" } }, { { name = "Testmate", text = CHECK, state = "done" } } } },
			{ title = T("Noch eine Quest", "Another quest"), dist = 51, objs = { T("Beutel gefunden: 0/1", "Pouch found: 0/1") },
				testQuestMates = { { name = "Testmate", text = "?", state = "none" } } },
		}, "test"
	end

	local entries, ids = {}, {}

	for _, n in ipairs(ComputeNear()) do
		local p = myProgress[n.id]
		entries[#entries + 1] = { id = n.id, dist = n.dist, held = n.held, age = n.age, instance = n.instance,
			objs = n.objs or (p and p.objs), goals = n.goals or (p and p.goals) }
		ids[#ids + 1] = n.id
	end

	return entries, table.concat(ids, ",")
end

-- Reiter "Ausgeblendet": die ausgeblendeten Quests wie im Reiter "Aktiv" (mit Zielen und Fortschritt, soweit sie im Questlog stehen)
local function BuildHidden()
	local entries = {}
	for _, h in ipairs(HiddenList()) do
		local p = myProgress[h.id]
		if not p and myLogIds[h.id] then p = ComputeProgress({ [h.id] = true })[h.id] end
		entries[#entries + 1] = { id = h.id, title = h.name, hidden = true, objs = p and p.objs, goals = p and p.goals }
	end
	return entries
end

-- /sqh near debug: zeigt, warum das Fenster erscheint oder nicht
local function DebugNear()
	local function say(text) print("|cffe8c26a[SQH near]|r " .. text) end
	say("Window enabled: " .. tostring(cfg.nearEnabled) .. ", range " .. cfg.nearRadius .. " yd, scanReady " .. tostring(scanReady))
	say("QuestieDB loaded: " .. tostring(HasQuestieDB() and true or false))
	local mapID, mapName = ZoneMap()
	say("Zone map: " .. tostring(mapID) .. " (" .. tostring(mapName) .. "), GetRealZoneText: " .. tostring(GetRealZoneText()))
	if not mapID then
		local iw, zoneKey = InstanceWanted()
		if not iw then return end
		say(("Instance: ID %s, AreaId %s (no map/position, dungeon mode)"):format(tostring(iw.instanceID), tostring(iw.areaId)))
		local count = 0
		for id in pairs(myLogIds) do
			count = count + 1
			ST.pointsCache[id] = nil
			local _, known = QuestPoints(id, iw, zoneKey)
			if known > 0 then
				say(("%s [%d]: %d goals in this instance"):format(QuestName(id), id, known))
			else
				say(("%s [%d]: no goals in this instance (log header: %s)"):format(QuestName(id), id, tostring(type(myLogIds[id]) == "string" and myLogIds[id] or "?")))
				for _, note in ipairs((ST.pointsCache[id] and ST.pointsCache[id].notes) or {}) do say("    " .. note) end
			end
		end
		if count == 0 then say("Quest log is empty.") end
		return
	end
	local pos = C_Map.GetPlayerMapPosition(mapID, "player")
	local px, py
	if pos then px, py = pos:GetXY() end
	say("Position: " .. tostring(px and (px * 100)) .. " / " .. tostring(py and (py * 100)))
	local w, h
	if C_Map.GetMapWorldSize then w, h = C_Map.GetMapWorldSize(mapID) end
	say("Map size (yards): " .. tostring(w) .. " x " .. tostring(h))
	local wanted = Wanted(mapID, GetRealZoneText(), mapName)
	local count = 0
	for id in pairs(myIds) do
		count = count + 1
		ST.pointsCache[id] = nil
		debugAreas = {}
		local points = QuestPoints(id, wanted, mapID)
		local seen = debugAreas
		debugAreas = nil
		local best
		if px and py then
			for _, c in ipairs(points) do
				local d = math.sqrt(((px - c[1] / 100) * (w or 4000)) ^ 2 + ((py - c[2] / 100) * (h or 3000)) ^ 2)
				if not best or d < best then best = d end
			end
		end
		say(("%s [%d]: %d points, nearest %s"):format(QuestName(id), id, #points, best and (math.floor(best) .. " yd") or "-"))
		if #points == 0 then
			local parts = {}
			for areaId in pairs(seen) do
				if #parts >= 6 then break end
				parts[#parts + 1] = ("%s=%s/m%s"):format(tostring(areaId), tostring(AreaName(areaId)), tostring(AreaToMap(areaId)))
			end
			say("    Goal areas: " .. (#parts > 0 and table.concat(parts, ", ") or "none (QuestieDB knows no places)"))
		end
	end
	if count == 0 then say("No quests of your zone in the log (myIds empty).") end
end

-- Töne für "Quest in Reichweite": Spielsounds (SOUNDKIT) und, wenn ein anderes Addon LibSharedMedia lädt, dessen Töne.
-- Die Lautstärke eines einzelnen Tons lässt sich in WoW nicht setzen; sie folgt dem gewählten Tonkanal.
-- Niedrige Ansicht von "Quests in der Nähe" (volle Breite): je Quest eine Zeile mit Name und einer Zahl (Stand aller Ziele zusammen,
-- sonst Prozent). Liefert die Höhe der Liste.
MV.MINI_W = WIDTH

function MV.NearNumber(e)
	local have, need = 0, 0
	for _, g in ipairs(GoalList(e.id, e.objs, e.goals)) do
		local a, b = tostring(g.count or ""):match("^(%d+)/(%d+)$")
		if a then have, need = have + tonumber(a), need + tonumber(b) end
	end
	if need > 0 then return have .. "/" .. need, have >= need end
	local p = e.id and myProgress[e.id]
	if p then return ((p.ready and 100) or p.pct or 0) .. "%", p.ready and true or false end
	return "", false
end

-- custom: fertige Zeilenliste statt der Zeilen aus den Quests (z. B. für "Mitspielern helfen": Mitspieler und ihre Quests)
function MV.ShowMiniList(f, entries, fresh, custom)
	local mini = f.mini
	if not mini then
		mini = CreateFrame("Frame", nil, f)
		mini:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -(BAND_H + 4))
		mini.rows = {}
		f.mini = mini
	end
	mini:Show()
	mini:ClearAllPoints()
	mini:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -(MV.Head(f) + 4))

	-- Eine Zeile je Questziel (nicht je Quest): Zielname links, Stand hinten. Quests ohne bekannte Ziele bleiben eine Zeile.
	local list = custom or {}
	for _, e in ipairs(custom and {} or entries) do
		local goals = GoalList(e.id, e.objs, e.goals)
		if #goals == 0 then
			list[#list + 1] = e
		else
			for _, g in ipairs(goals) do
				list[#list + 1] = { id = e.id, goal = true, name = g.name, count = g.count or "", done = g.done }
			end
		end
	end
	if #list == 0 then list = { { none = true } } end
	local y = 0
	for i, e in ipairs(list) do
		local row = mini.rows[i]
		if not row then
			row = CreateFrame("Button", nil, mini)
			row.num = row:CreateFontString(nil, "OVERLAY", "SexyQuestHelperSmall")
			row.num:SetPoint("RIGHT", 0, 0)
			row.name = row:CreateFontString(nil, "OVERLAY", "SexyQuestHelperSmall")
			row.name:SetPoint("LEFT", 0, 0)
			row.name:SetPoint("RIGHT", row.num, "LEFT", -6, 0)
			row.name:SetJustifyH("LEFT")
			row.name:SetWordWrap(false)
			row:SetScript("OnEnter", function(self)
				if not self.questId then return end
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, ("quest:%d:%d"):format(self.questId, UnitLevel("player")))
				if not ok then
					GameTooltip:ClearLines()
					GameTooltip:AddLine(QuestName(self.questId))
				end
				GameTooltip:Show()
			end)
			row:SetScript("OnLeave", function() GameTooltip:Hide() end)
			mini.rows[i] = row
		end
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", mini, "TOPLEFT", 0, -y)
		row:SetSize(MV.MINI_W - 16, 16)
		row.questId = e.id
		if e.none then
			row.name:SetText(e.text or "-")
			row.name:SetTextColor(0.6, 0.57, 0.5)
			row.num:SetText("")
		elseif e.member then
			-- Mitspieler (Klassenfarbe), hinten die Zahl seiner Quests
			row.name:SetText(ColoredName(e.name))
			row.num:SetText("(" .. (e.count or 0) .. ")")
			row.num:SetTextColor(0.61, 0.57, 0.50)
		elseif e.help then
			-- Quest des Mitspielers, leicht eingerückt, hinten sein Stand
			row.name:SetText("  " .. (e.title or QuestName(e.id)))
			row.name:SetTextColor(0.95, 0.92, 0.86)
			local pct = e.ready and 100 or e.pct
			row.num:SetText(pct and (pct .. "%") or "")
			if e.ready then row.num:SetTextColor(0.30, 0.76, 0.42) else row.num:SetTextColor(0.94, 0.75, 0.29) end
		else
			local num, done
			if e.goal then
				num, done = e.count, e.done
				row.name:SetText(e.name or "")
			else
				num, done = MV.NearNumber(e)
				row.name:SetText(e.title or QuestName(e.id))
			end
			row.name:SetTextColor(0.95, 0.92, 0.86)
			row.num:SetText(num)
			if done then row.num:SetTextColor(0.30, 0.76, 0.42) else row.num:SetTextColor(0.94, 0.75, 0.29) end
			if fresh and e.id and fresh[e.id] then MV.Glow(row) end
		end
		row:Show()
		y = y + 16
	end
	for i = #list + 1, #mini.rows do mini.rows[i]:Hide() end
	mini:SetSize(MV.MINI_W - 16, math.max(1, y))
	return y
end

local NearSound = {}
do
local SOUND_NAMES = {
	{ "IG_QUEST_LIST_OPEN", T("Questliste öffnen", "Quest list open") },
	{ "READY_CHECK", T("Bereitschaftscheck", "Ready check") },
	{ "RAID_WARNING", T("Schlachtzugswarnung", "Raid warning") },
	{ "ALARM_CLOCK_WARNING_3", T("Wecker", "Alarm clock") },
	{ "MAP_PING", T("Kartenping", "Map ping") },
	{ "UI_QUEST_ROLLING_FORWARD_01", T("Quest abgegeben", "Quest turned in") },
	{ "TELL_MESSAGE", T("Flüstern", "Whisper") },
	{ "AUCTION_WINDOW_OPEN", T("Auktionshaus", "Auction house") },
	{ "UI_EPICLOOT_TOAST", T("Epische Beute", "Epic loot") },
	{ "IG_PLAYER_INVITE", T("Einladung", "Invitation") },
}

function NearSound.Options()
	local list = {}
	for _, s in ipairs(SOUND_NAMES) do
		if SOUNDKIT and SOUNDKIT[s[1]] then list[#list + 1] = { value = s[1], label = s[2] } end
	end
	local LSM = LibStub("LibSharedMedia-3.0", true)
	if LSM then
		local names = {}
		for name in pairs(LSM:HashTable("sound")) do names[#names + 1] = name end
		table.sort(names)
		for _, name in ipairs(names) do
			if name ~= "None" then list[#list + 1] = { value = "lsm:" .. name, label = name } end
		end
	end
	return list
end

function NearSound.Play()
	local key, channel = cfg.nearSoundKey or "IG_QUEST_LIST_OPEN", cfg.nearSoundChannel or "Master"
	local played
	if key:sub(1, 4) == "lsm:" then
		local LSM = LibStub("LibSharedMedia-3.0", true)
		local path = LSM and LSM:Fetch("sound", key:sub(5), true)
		if path then played = PlaySoundFile(path, channel) end
	elseif SOUNDKIT and SOUNDKIT[key] then
		played = PlaySound(SOUNDKIT[key], channel)
	end
	-- gewählter Ton nicht vorhanden oder nicht abspielbar: Standardton
	if not played then PlaySound((SOUNDKIT and SOUNDKIT.IG_QUEST_LIST_OPEN) or 882, channel) end
end

end

function RefreshNear()
	if not nearUI then return end

	MV.SetHeader(nearUI, cfg.hideHeaderNear)
	PruneHidden()
	if MV.nearTab == "hidden" and HiddenCount() == 0 then MV.nearTab = "active" end   -- nichts mehr ausgeblendet: zurück zu "Aktiv"
	local entries, sig = BuildNear()
	nearUI.sig = sig
	local wanted = cfg.nearEnabled and scanReady

	-- Ton, wenn eine Quest neu in Reichweite kommt
	-- (nicht im Flug, auch nicht auf einem Flugpunkt-Flug: dort fliegt man an vielen Quests vorbei)
	-- Neu heisst: nicht beim letzten Durchlauf da UND nicht erst kurz zuvor da. Sonst wuerde eine Quest am Rand der
	-- Reichweite (kleines Gebiet) beim Hin- und Herlaufen jedes Mal Ton und Leuchten ausloesen.
	local now = GetTime()
	local fresh, anyFresh = {}, false
	for _, e in ipairs(entries) do
		if e.id and not ST.nearKnown[e.id] and now - (ST.nearSeen[e.id] or -1e9) > ST.NEAR_AGAIN then
			fresh[e.id] = true
			anyFresh = true
		end
	end
	for _, e in ipairs(entries) do if e.id then ST.nearSeen[e.id] = now end end

	local flying = (IsFlying and IsFlying()) or (UnitOnTaxi and UnitOnTaxi("player"))
	if wanted and cfg.nearSound and not testMode and not flying and anyFresh then
		pcall(NearSound.Play)
	end
	if not (wanted and cfg.nearGlow ~= false and not testMode) then wipe(fresh) end   -- Leuchten abgeschaltet

	wipe(ST.nearKnown)
	for _, e in ipairs(entries) do if e.id then ST.nearKnown[e.id] = true end end

	local auto = wanted and #entries > 0 and sig ~= ST.nearDismissed
	if not (ST.nearForce or testMode or auto or MV.nearTab == "hidden") then
		nearUI:Hide()
		return
	end

	-- Reiter "Aktiv" / "Ausgeblendet (n)": Gruppe aus zwei Knöpfen unter dem Titelband (in der kleinen Ansicht ohne Reiter)
	local tabs = nearUI.tabs
	local showTabs = not MV.IsMin("minNear")
	for key, btn in pairs(tabs) do
		btn:SetShown(showTabs)
		local on = key == MV.nearTab
		btn.bg:SetColorTexture(on and 0.42 or 0.15, on and 0.34 or 0.12, on and 0.15 or 0.07, 1)
		btn.text:SetTextColor(on and 1 or 0.91, on and 0.9 or 0.76, on and 0.7 or 0.42)
		btn:ClearAllPoints()
	end
	-- Ohne ausgeblendete Quests ist "Ausgeblendet" ausgegraut und nicht anklickbar
	local noHidden = HiddenCount() == 0
	tabs.hidden:SetEnabled(not noHidden)
	tabs.hidden.hl:SetShown(not noHidden)
	if noHidden then
		tabs.hidden.bg:SetColorTexture(0.1, 0.085, 0.06, 1)
		tabs.hidden.text:SetTextColor(0.45, 0.42, 0.36)
	end
	tabs.active:SetPoint("TOPLEFT", nearUI, "TOPLEFT", 10, -(MV.Head(nearUI) + 7))
	tabs.hidden:SetPoint("LEFT", tabs.active, "RIGHT", 4, 0)
	tabs.hidden.text:SetText(T("Ausgeblendet", "Hidden") .. (HiddenCount() > 0 and (" (" .. HiddenCount() .. ")") or ""))
	-- Breite folgt dem Text (mit der Anzahl wird der Reiter breiter)
	for _, btn in pairs(tabs) do btn:SetWidth(math.max(60, math.ceil(btn.text:GetStringWidth()) + 24)) end
	local tabH = showTabs and MV.NEAR_TAB_H or 0

	-- Kleine Ansicht: sehr schmal, je Quest eine Zeile mit dem Namen und hinten einer Zahl, sonst nichts
	if MV.IsMin("minNear") then
		nearUI.scroll:Hide()
		MV.HideSummary(nearUI)
		local h = MV.ShowMiniList(nearUI, entries, fresh)
		-- oben 4 px unter dem Titelband, unten 4 px plus Rand: der Text sitzt mittig
		MV.ApplyHeight(nearUI, "nearMode", MV.Head(nearUI) + 4 + h + 4 + 3)
		nearUI:Show()
		return
	end
	if nearUI.mini then nearUI.mini:Hide() end
	nearUI.scroll:ClearAllPoints()
	nearUI.scroll:SetPoint("TOPLEFT", nearUI, "TOPLEFT", 0, -(MV.Head(nearUI) + tabH))
	nearUI.scroll:Show()
	MV.HideSummary(nearUI)

	-- Zeilen liegen im Scrollbereich (Koordinaten ab dessen Oberkante)
	local y = 8

	-- Reiter "Ausgeblendet": dieselben Zeilen wie bei "Aktiv", nur mit den ausgeblendeten Quests (Rechtsklick blendet sie wieder ein)
	local view = MV.nearTab == "hidden" and BuildHidden() or entries
	if #view == 0 then
		local row = GetNearRow(1)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", nearUI.content, "TOPLEFT", 12, -y)
		row:SetSize(WIDTH - 24, INFO_H)
		row.bg:Hide()
		row.questId = nil
		row:EnableMouse(false)
		HidePill(row.pill)
		row.accent:Hide()
		row.divider:Hide()
		for _, g in ipairs(row.goals) do g:Hide() end
		LayoutChips(row, row.chips, nil, 0, 0)
		row.fs:SetPoint("RIGHT", row.pill.tex, "LEFT", -6, 0)
		row.hiddenView = nil
		row.fs:SetText("|cff9b9180" .. (MV.nearTab == "hidden" and T("Keine ausgeblendeten Quests.", "No hidden quests.")
			or HasQuestieDB() and T("Keine Quest-Ziele in der Nähe.", "No quest goals nearby.")
			or T("Keine Ziele bekannt. Ohne QuestieDB lernt das Addon die Orte beim Spielen.", "No goals known. Without QuestieDB the addon learns the places while you play.")) .. "|r")
		row:Show()
		y = y + INFO_H

		for i = 2, #ST.nearRows do ST.nearRows[i]:Hide() end
	else
		for i, e in ipairs(view) do
			local row = GetNearRow(i)
			row.hiddenView = e.hidden
			local goals = GoalList(e.id, e.objs, e.goals)
			local allDone = (#goals > 0) or (e.id and myProgress[e.id] and myProgress[e.id].ready)

			for _, goal in ipairs(goals) do
				if not goal.done then allDone = false end
			end

			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", nearUI.content, "TOPLEFT", 12, -y)
			row:SetWidth(WIDTH - 24)
			row.bg:SetColorTexture(0.145, 0.125, 0.10, cfg.opacity)
			row.bg:Show()
			row.divider:SetShown(i > 1 and cfg.showDividers ~= false)
			row.accent:SetShown(cfg.showAccent ~= false)
			row.accent:SetWidth(cfg.accentW or 3)
			if allDone then row.accent:SetColorTexture(0.30, 0.76, 0.42, 1) else row.accent:SetColorTexture(0.94, 0.75, 0.29, 1) end
			row.questId = e.id
			row:EnableMouse(e.id ~= nil)
			row.fs:SetText(e.title or QuestName(e.id))
			row.fs:SetTextColor(0.95, 0.92, 0.86)
			if e.hidden then
				SetPill(row.pill, "grey", myLogIds[e.id] and T("ausgeblendet", "hidden") or T("nicht im Log", "not in log"), nil, 16)
			elseif e.instance then
				-- in Dungeons gibt es keine Position und damit keine Entfernung
				SetPill(row.pill, "they", T("Dungeon", "Dungeon"), nil, 16)
			elseif e.held and not (e.dist and e.dist <= cfg.nearRadius) then
				-- ohne festen Ort: wie lange der Fortschritt her ist
				local minutes = math.floor((e.age or 0) / 60)
				SetPill(row.pill, "grey", minutes < 1 and T("gerade eben", "just now") or T(minutes .. " min", minutes .. " min ago"), nil, 16)
			else
				SetPill(row.pill, "they", math.floor(e.dist + 0.5) .. " m", nil, 16)
			end
			local showDist = cfg.showDist ~= false
			if not showDist then HidePill(row.pill) end

			-- Stand der Gruppenmitglieder: je Ziel unter dem Ziel, sonst eine Zeile unter dem Titel
			local perGoal, questMates
			if testMode then
				perGoal, questMates = e.testMates or {}, e.testQuestMates
			else
				perGoal, questMates = NearMates(e.id, #goals)
			end
			for j, goal in ipairs(goals) do goal.mates = perGoal[j] end
			-- Badges zur ganzen Quest rechts im Titel, direkt vor der Entfernung; der Titel endet davor
			local qw = LayoutChips(row, row.chips, questMates, 8 + (showDist and (row.pill.tex:GetWidth() + 4) or 0), 6)
			if showDist then
				row.fs:SetPoint("RIGHT", row.pill.tex, "LEFT", -(6 + ((qw > 0) and (qw + 4) or 0)), 0)
			else
				row.fs:SetPoint("RIGHT", row, "RIGHT", -(8 + ((qw > 0) and (qw + 4) or 0)), 0)
			end
			local mh = 0

			local gh = RenderGoals(row, goals, NEAR_ROW_H - 2 + mh)
			local h = NEAR_ROW_H + mh + ((gh > 0) and (4 + gh) or 0) + 4
			row:SetHeight(h)
			row:Show()
			if e.id and fresh[e.id] then MV.Glow(row) end
			y = y + h + 2
		end

		for i = #view + 1, #ST.nearRows do ST.nearRows[i]:Hide() end
	end

	-- Scrollbereich: so hoch wie die Liste, höchstens nearMaxHeight; darüber scrollt das Mausrad
	local contentH = y
	local viewH = math.min(contentH, cfg.nearMaxHeight or 400)
	nearUI.content:SetHeight(contentH)
	nearUI.scroll:SetHeight(viewH)
	nearUI:UpdateScroll()
	y = MV.Head(nearUI) + tabH + viewH

	local newHeight = y + 10
	local db = SexyQuestHelperDB.nearMode

	if db and db.x and db.y and not SEM:IsMoving(nearUI) then
		SEM:SetPosition(nearUI, db.x, db.y - (newHeight - (db.anchoredHeight or newHeight)))
		db.anchoredHeight = newHeight
	end

	nearUI:SetHeight(newHeight)
	nearUI:Show()
end

local function CreateNearUI()
	local f = CreateFrame("Frame", "SexyQuestHelperNearFrame", UIParent, "BackdropTemplate")
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

	-- Standardposition: links neben dem Hauptfenster (Oberkanten gleich)
	local db = SexyQuestHelperDB.nearMode

	if not db then
		db = {}
		SexyQuestHelperDB.nearMode = db
		local main = SexyQuestHelperDB.editMode or {}
		local mx, my = main.x or 400, main.y or 300
		local top = my + (main.anchoredHeight or 60)
		db.x = math.max(0, mx - WIDTH - 12)
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
	f.title:SetText(T("Quests in der Nähe", "Quests nearby"))
	-- Scrollbereich für die Quest-Zeilen (Mausrad), mit schmalem Balken rechts, wenn die Liste länger ist
	f.scroll = CreateFrame("ScrollFrame", nil, f)
	f.scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -BAND_H)
	f.scroll:SetSize(WIDTH, 1)
	f.content = CreateFrame("Frame", nil, f.scroll)
	f.content:SetSize(WIDTH, 1)
	f.scroll:SetScrollChild(f.content)
	f.scroll:EnableMouseWheel(true)
	f.track = f.scroll:CreateTexture(nil, "ARTWORK")
	f.track:SetPoint("TOPRIGHT", f.scroll, "TOPRIGHT", -5, -8)
	f.track:SetPoint("BOTTOMRIGHT", f.scroll, "BOTTOMRIGHT", -5, 2)
	f.track:SetWidth(3)
	f.track:SetColorTexture(0.21, 0.19, 0.14, 1)
	f.thumb = f.scroll:CreateTexture(nil, "OVERLAY")
	f.thumb:SetWidth(3)
	f.thumb:SetColorTexture(0.91, 0.76, 0.42, 0.9)

	function f:UpdateScroll()
		local viewH, contentH = self.scroll:GetHeight(), self.content:GetHeight()
		local range = math.max(0, contentH - viewH)
		local offset = math.min(math.max(self.scroll:GetVerticalScroll(), 0), range)
		self.scroll:SetVerticalScroll(offset)
		if range <= 0 or cfg.showScroll == false then
			self.track:Hide()
			self.thumb:Hide()
			return
		end
		local trackH = viewH - 10
		local thumbH = math.max(16, trackH * viewH / contentH)
		self.thumb:ClearAllPoints()
		self.thumb:SetPoint("TOPRIGHT", self.track, "TOPRIGHT", 0, -(trackH - thumbH) * offset / range)
		self.thumb:SetHeight(thumbH)
		self.track:Show()
		self.thumb:Show()
	end

	f.scroll:SetScript("OnMouseWheel", function(self, delta)
		self:SetVerticalScroll(self:GetVerticalScroll() - delta * 40)
		f:UpdateScroll()
	end)

	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)
	f.closeBtn = close
	close:SetScript("OnClick", function()
		ST.nearForce = false
		MV.nearTab = "active"
		ST.nearDismissed = f.sig
		f:Hide()
	end)

	-- Reiter unter dem Titelband: Aktiv / Ausgeblendet (derselbe Aufbau der Zeilen, nur andere Quests)
	-- Reiter wie in der Vorschau (Samples.lua): flache Fläche mit dünnem goldenem Rand statt des abgerundeten Knopfrands
	local function MakeTab(label, width)
		local b = CreateFrame("Button", nil, f)
		b:SetSize(width, 22)
		b.bg = b:CreateTexture(nil, "BACKGROUND")
		b.bg:SetAllPoints()
		b.bg:SetColorTexture(0.15, 0.12, 0.07, 1)
		b.hl = b:CreateTexture(nil, "HIGHLIGHT")
		b.hl:SetAllPoints()
		b.hl:SetColorTexture(1, 1, 1, 0.12)
		b.text = b:CreateFontString(nil, "OVERLAY", "SexyQuestHelperSmall")
		b.text:SetAllPoints()
		b.text:SetText(label)
		b.text:SetTextColor(0.91, 0.76, 0.42)
		b:RegisterForClicks("LeftButtonUp")
		for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
			{ "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
			local t = b:CreateTexture(nil, "BORDER")
			t:SetColorTexture(0.42, 0.34, 0.15, 1)
			t:SetPoint(e[1])
			t:SetPoint(e[2])
			if e[3] then t:SetHeight(1) else t:SetWidth(1) end
		end
		return b
	end
	f.tabs = {
		active = MakeTab(T("Aktiv", "Active"), 80),
		hidden = MakeTab(T("Ausgeblendet", "Hidden"), 130),
	}
	for key, btn in pairs(f.tabs) do
		btn:SetScript("OnClick", function()
			MV.nearTab = key
			RefreshNear()
		end)
	end

	MV.AddMinButton(f, "minNear", function() RefreshNear() end)

	f:Hide()
	SEM:Register(f, {
		name = "SexyQuestHelper: " .. T("Quests in der Nähe", "Quests nearby"),
		category = T("Quests", "Quests"),   -- Zwischenüberschrift in der Seitenleiste des Einstellungsfensters
		addon = "SexyQuestHelper",
		group = "sqh", groupName = "SexyQuestHelper",   -- Tabs im Edit-Mode-Dialog
		description = T("Deine offenen Quests, deren Ziele in Reichweite liegen, mit den Einzelzielen.", "Your open quests whose goals are in range, with the single goals."),
		sample = SexyQuestHelperSamples and SexyQuestHelperSamples.near,   -- Vorschau im Einstellungsfenster: eigenes Fenster mit eigener Logik (Samples.lua)
		db = db,
		settings = {
			{ type = "header", name = T("Darstellung", "Look"), id = "look" },
			{ type = "check", name = T("Kopfzeile ausblenden", "Hide header"),
				get = function() return cfg.hideHeaderNear end,
				set = function(v) cfg.hideHeaderNear = v and true or false; RefreshNear() end },
			{ type = "slider", name = T("Größte Höhe der Liste (darüber scrollen)", "Largest list height (scroll beyond)"), min = 150, max = 900, step = 25,
				get = function() return cfg.nearMaxHeight end,
				set = function(v) cfg.nearMaxHeight = v; RefreshNear() end,
				format = function(v) return v .. " px" end },
			{ type = "check", name = T("Stand der Gruppenmitglieder zeigen", "Show the progress of group members"),
				get = function() return cfg.nearMates end,
				set = function(v) cfg.nearMates = v and true or false; RefreshNear() end },
			MV.Spec("width"), MV.Spec("rowH"), MV.Spec("opacity"), MV.Spec("showBars"), MV.Spec("barH"),
			MV.Spec("fontDelta"), MV.Spec("bandH"), MV.Spec("bgColor"), MV.Spec("borderColor"), MV.Spec("showAccent"), MV.Spec("accentW"),
			MV.Spec("showDividers"), MV.Spec("showDist"), MV.Spec("showChecks"), MV.Spec("showCounts"), MV.Spec("showButtons"), MV.Spec("showScroll"),
			MV.Spec("glowColor"), MV.Spec("glowAlpha"),
			{ type = "header", name = T("Verhalten", "Behavior"), id = "near" },
			MV.CombatSpec("minNear"),
			{ type = "check", behavior = true, name = T("Fenster einschalten (öffnet sich in Zielnähe)", "Turn the window on (opens near goals)"),
				get = function() return cfg.nearEnabled end,
				set = function(v) cfg.nearEnabled = v and true or false; RefreshNear() end },
			{ type = "slider", behavior = true, name = T("Reichweite", "Range"), min = 20, max = 300, step = 10,
				get = function() return cfg.nearRadius end,
				set = function(v) cfg.nearRadius = v; RefreshNear() end,
				format = function(v) return v .. " m" end },
			{ type = "slider", behavior = true, name = T("Quest ohne festen Ort bleibt (Minuten)", "Quest without a fixed place stays (minutes)"), min = 1, max = 10, step = 1,
				get = function() return cfg.nearHold end,
				set = function(v) cfg.nearHold = v; RefreshNear() end },
			{ type = "check", behavior = true, name = T("Kurz aufleuchten, wenn eine Quest neu in Reichweite kommt", "Brief glow when a quest comes into range"),
				get = function() return cfg.nearGlow ~= false end,
				set = function(v) cfg.nearGlow = v and true or false end },
			{ type = "check", behavior = true, name = T("Ton, wenn eine Quest neu in Reichweite kommt", "Sound when a quest comes into range"),
				get = function() return cfg.nearSound end,
				set = function(v) cfg.nearSound = v and true or false end },
			{ type = "select", behavior = true, name = T("Ton", "Sound"), options = NearSound.Options,
				get = function() return cfg.nearSoundKey end,
				set = function(v) cfg.nearSoundKey = v; pcall(NearSound.Play) end },
			{ type = "select", behavior = true, name = T("Lautstärke (Tonkanal)", "Volume (sound channel)"),
				options = {
					{ value = "Master", label = T("Gesamt", "Master") },
					{ value = "SFX", label = T("Effekte", "Effects") },
					{ value = "Dialog", label = T("Dialog", "Dialog") },
					{ value = "Ambience", label = T("Umgebung", "Ambience") },
				},
				get = function() return cfg.nearSoundChannel end,
				set = function(v) cfg.nearSoundChannel = v; pcall(NearSound.Play) end },
			{ type = "link", name = "SexyQuestHelper", frame = function() return ui end },
		},
		onMoved = function(self) db.anchoredHeight = self:GetHeight() end,
	})
	return f
end

-- Alle Fenster zusammen aktualisieren
local RefreshMain = Refresh
function Refresh()
	RefreshMain()
	RefreshHelp()
	RefreshNear()
end

---------------------------------------------------------------------------
-- Scan-Steuerung
---------------------------------------------------------------------------

local function DoScan(forceBroadcast)
	scanTimer = nil
	local ok, zone, ids, titles, key = pcall(ScanQuests)
	if not ok then
		print("|cffff4040[SQH]|r Scan-Fehler: " .. tostring(zone))
		return
	end
	myZone, myIds, myTitles, myZoneKey = zone, ids, titles, key
	local previous = myProgress
	myProgress = ComputeProgress(ids)
	-- Fortschritt gestiegen (z. B. erster Kill): Ort als Bereich dieser Quest merken
	for id, p in pairs(myProgress) do
		local o = previous[id]
		if o and p.pct > o.pct then
			ST.progressAt[id] = GetTime()
			pcall(LearnQuestPoint, id)
		end
	end
	wipe(ST.pointsCache)
	ignoreUntil = GetTime() + ST.IGNORE_AFTER_SCAN

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
	C_Timer.After(ST.SCAN_DELAY, function() DoScan(forceBroadcast) end)
end

local function PruneMembers()
	local present = {}
	for _, name in ipairs(GroupNames()) do present[name] = true end
	for name in pairs(members) do
		if not present[name] then members[name] = nil; ST.versions[name] = nil; ST.completedBy[name] = nil; ST.blockedBy[name] = nil; ST.learnedBlocked[name] = nil; progressBy[name] = nil; detailsBy[name] = nil end
	end
end

-- Direkt nach einem Scan werden QUEST_LOG_UPDATE-Events ignoriert (Auf-/Zuklappen im Questlog). Ein echter
-- Fortschritt (z. B. der nächste Kill) soll trotzdem sofort zählen: dann hat sich der Stand einer Quest geändert
local function ProgressChanged()
	local ok, now = pcall(ComputeProgress, myIds)
	if not ok then return false end
	for id, p in pairs(now) do
		local o = myProgress[id]
		if not o or o.pct ~= p.pct or o.ready ~= p.ready then return true end
	end
	return false
end

frame:SetScript("OnEvent", function(_, event, ...)
	if event == "CHAT_MSG_ADDON" then
		OnAddonMessage(...)
	elseif event == "QUEST_DATA_LOAD_RESULT" then
		Refresh()
	elseif event == "QUEST_LOG_UPDATE" then
		if GetTime() >= ignoreUntil or ProgressChanged() then QueueScan(false) end
	elseif event == "CHAT_MSG_SYSTEM" then
		OnSystemMessage(...)
	elseif event == "QUEST_ACCEPTED" or event == "QUEST_REMOVED" or event == "QUEST_TURNED_IN" then
		-- echte Aenderungen: immer scannen (QUEST_LOG_UPDATE wird nach einem Scan kurz
		-- ignoriert und koennte sonst eine gleich danach angenommene Quest verschlucken)
		QueueScan(false)
		-- Quest abgegeben: den anderen sofort melden (Typ "E" haengt an). Sonst erfahren sie es erst bei der naechsten Liste, die sie
		-- schicken, und zeigen "Hat nicht" samt Teilen-Knopf, obwohl die Quest laengst abgegeben ist.
		if event == "QUEST_TURNED_IN" then
			local qid = ...
			local channel = GroupChannel()
			if qid and channel then SendIdList("E", "E", { qid }, channel) end
		end
	elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
		-- Kampf beginnt/endet: Teilen-Knöpfe sofort ein- bzw. ausschalten
		for _, row in ipairs(rowPool) do UpdateShareButton(row.share) end
		-- Fenster mit "Im Kampf: Kleine Ansicht" wechseln jetzt; nach dem Kampf noch einmal (UnitAffectingCombat hängt kurz nach)
		if cfg.combatMain == "mini" or cfg.combatHelp == "mini" or cfg.combatNear == "mini" then
			MV.CombatRefresh()
			C_Timer.After(1, MV.CombatRefresh)
		end
	elseif event == "GROUP_ROSTER_UPDATE" then
		PruneMembers()
		QueueScan(true) -- neue Mitglieder brauchen unsere Liste
		Refresh()
	elseif event == "PLAYER_LOGIN" then
		SexyQuestHelperDB = SexyQuestHelperDB or {}
		SexyQuestHelperDB.cfg = SexyQuestHelperDB.cfg or {}
		cfg = setmetatable(SexyQuestHelperDB.cfg, { __index = DEFAULTS })
		MV.ApplySizes()
		ui = CreateUI() -- zuerst, damit /sqh auch bei spaeteren Fehlern funktioniert
		helpUI = CreateHelpUI()
		nearUI = CreateNearUI()
		MV.ApplySizes()   -- jetzt gibt es die Fenster: Titelleiste, Farben und Schrift nach den Einstellungen
		-- Ausgeblendete Quests: eigene Seite im gemeinsamen Einstellungsfenster (kein Fenster, kein Edit Mode)
		if SEM.RegisterPage then
			SEM:RegisterPage({
				name = "SexyQuestHelper: " .. T("Ausgeblendete Quests", "Hidden quests"),
				category = T("Verwaltung", "Manage"),   -- Zwischenüberschrift in der Seitenleiste des Einstellungsfensters
				addon = "SexyQuestHelper",
		group = "sqh", groupName = "SexyQuestHelper",   -- Tabs im Edit-Mode-Dialog
				description = T("Quests, die du im Fenster \"Quests in der Nähe\" per Rechtsklick ausgeblendet hast.", "Quests you hid with a right-click in the \"Quests nearby\" window."),
				settings = { select(2, HiddenSettings()) },
			})
		end
		-- Position ändert sich laufend: regelmäßig prüfen (nur, wenn das Fenster an ist oder offen steht)
		C_Timer.NewTicker(1.5, function()
			if cfg.nearEnabled or ST.nearForce or testMode or (nearUI and nearUI:IsShown()) then RefreshNear() end
		end)
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
		ST.versions.Testmate = VERSION
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
		print("|cffe8c26a[SQH]|r Oberflaeche nicht initialisiert (Fehler beim Laden?)")
		return
	end
	arg = (arg or ""):lower()
	if arg == "minimap" then
		SexyQuestHelper_ToggleMinimapButton()
		return
	end
	if arg == "test" then
		editPreview = false
		SetTestMode(not testMode)
		return
	end
	if arg == "debug" or arg == "debug log" then
		local keys = {}
		for name, m in pairs(members) do keys[#keys + 1] = ("%s(%d, v%s)"):format(name, #SortedIds(m.ids), tostring(ST.versions[name] or "?")) end
		print(("|cffe8c26a[SQH]|r v%s | Kanal=%s | Prefix=%s | gesendet=%d (%s) | empfangen=%d | Addon-Msgs gesamt=%d | letzter Sender=%s"):format(
			VERSION, tostring(GroupChannel()),
			tostring(prefixOk), sendCount, tostring(lastSendResult), recvCount, anyAddonMsgs, lastRecv))
		print(("|cffe8c26a[SQH]|r Zone='%s' (%s) | Quests=%d | Log-Eintraege=%d | GetInfo=%s | GetQuestLogTitle=%s"):format(
			myZone, myZoneKey, #SortedIds(myIds), NumEntries(), tostring(C_QuestLog and C_QuestLog.GetInfo ~= nil), tostring(GetQuestLogTitle ~= nil)))
		print("|cffe8c26a[SQH]|r Gruppe: " .. table.concat(GroupNames(), ", ") .. " | Daten von: " .. table.concat(keys, ", "))
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
			if ST.versions[name] and CompareVersions(ST.versions[name], newest) > 0 then newest = ST.versions[name] end
		end
		print(("SexyQuestHelper v%s %s"):format(VERSION,
			CompareVersions(VERSION, newest) < 0 and ("|cffff4040(" .. T("veraltet, neueste in der Gruppe: v", "outdated, newest in group: v") .. newest .. ")|r")
			or ("|cff00ff00(" .. T("aktuell", "up to date") .. ")|r")))
		for _, name in ipairs(names) do
			local v = ST.versions[name]
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
		print(("|cffe8c26a[SQH]|r check %d: QuestDB=%s | annehmbar=%s | erledigt=%s | aktiv=%s"):format(id,
			tostring(_G.QuestDB ~= nil), tostring(CanAccept(id)), tostring(IsDone(id)), tostring(IsActive(id))))
		if _G.QuestDB then
			print(("  preQuestSingle=%s preQuestGroup=%s exclusiveTo=%s nextQuestInChain=%s requiredLevel=%s"):format(
				list(DbField(id, "preQuestSingle")), list(DbField(id, "preQuestGroup")), list(DbField(id, "exclusiveTo")),
				tostring(DbField(id, "nextQuestInChain")), tostring(DbField(id, "requiredLevel"))))
		end
		return
	end
	if arg == "near debug" then
		DebugNear()
		return
	end
	if arg == "hidden" or arg == "ausgeblendet" or arg == "near hidden" or arg == "near ausgeblendet" then
		local list = HiddenList()
		if #list == 0 then
			print("|cffe8c26a[SQH]|r " .. T("Keine Quests ausgeblendet.", "No hidden quests."))
		else
			print("|cffe8c26a[SQH]|r " .. T("Ausgeblendete Quests:", "Hidden quests:"))
			for _, h in ipairs(list) do print(("  [%d] %s"):format(h.id, h.name)) end
			print("  " .. T("Einblenden: /sqh show <ID> oder /sqh show all", "Show again: /sqh show <ID> or /sqh show all"))
		end
		return
	end
	local showId = arg:match("^show%s+(%S+)$") or arg:match("^near show%s+(%S+)$")
	if showId then
		local id = tonumber(showId)
		if showId == "all" or showId == "alle" then
			UnhideQuest(nil)
			print("|cffe8c26a[SQH]|r " .. T("Alle Quests wieder eingeblendet.", "All quests shown again."))
		elseif id and IsQuestHidden(id) then
			UnhideQuest(id)
			print("|cffe8c26a[SQH]|r " .. T("wieder eingeblendet: ", "shown again: ") .. QuestName(id))
		else
			print("|cffe8c26a[SQH]|r " .. T("Diese Quest ist nicht ausgeblendet.", "This quest is not hidden."))
		end
		return
	end
	if arg == "near" or arg == "nähe" then
		ST.nearForce = not (nearUI and nearUI:IsShown())
		if not ST.nearForce then ST.nearDismissed = nearUI and nearUI.sig end
		RefreshNear()
		return
	end
	if arg == "help" or arg == "helfen" then
		ST.helpForce = not (helpUI and helpUI:IsShown())
		if not ST.helpForce then ST.helpDismissed = helpUI and helpUI.sig end
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
