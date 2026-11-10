-- SexyQuestHelper: vergleicht die Quests des aktuellen Gebiets mit allen
-- Gruppenmitgliedern, die ebenfalls dieses Addon nutzen.
--
-- Ablauf: Jeder Client liest seine Quests des aktuellen Gebiets (Questlog-
-- Kategorie = Gebietsname), sendet die Quest-IDs per Addon-Nachricht an die
-- Gruppe und vergleicht sie mit den empfangenen Listen der anderen.

local PREFIX = "SexyQuestHelper"
local VERSION = "1.0.5" -- bei jedem Release mit ## Version in der .toc anheben (GetAddOnMetadata fehlt auf Forever)
local versions = {} -- [name] = Addon-Version des Mitglieds
local SCAN_DELAY = 1        -- Sekunden Entprellung nach Events
local IGNORE_AFTER_SCAN = 2 -- Sekunden, in denen eigene Auf-/Zuklapp-Events ignoriert werden
local CHUNK_SIZE = 200      -- Zeichen Quest-IDs pro Nachricht (Limit: 255 inkl. Header)

local isDE = GetLocale() == "deDE"
local function T(de, en) return isDE and de or en end

local frame = CreateFrame("Frame")
local ui                      -- Anzeigefenster (lazy)
local myZone, myZoneKey, myIds, myTitles = "", "", {}, {} -- myZone: lokaler Name, myZoneKey: sprachunabhaengiger Vergleichsschluessel
local mySignature = ""
local members = {}            -- [name] = { zone = "", ids = { [id] = true } }
local scanTimer, ignoreUntil = nil, 0
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
	else
		return
	end

	for id in rest:gmatch("%d+") do
		members[name].ids[tonumber(id)] = true
	end
	Refresh()
end

---------------------------------------------------------------------------
-- Anzeige
---------------------------------------------------------------------------

local WIDTH, ROW_H = 330, 16
local forceShow = false     -- per /sqh erzwungen (auch ohne Unterschiede)
local dismissedSig = nil    -- Unterschiede, die der Nutzer weggeklickt hat
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
local function CanShare(id)
	if not myIds[id] or not InGroup() or testMode then return false end
	if C_QuestLog and C_QuestLog.IsPushableQuest then return C_QuestLog.IsPushableQuest(id) and true or false end
	return true
end

local function ShareQuest(id)
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
	if ok then
		print("SexyQuestHelper: " .. T("Quest geteilt: ", "Quest shared: ") .. QuestLink(id))
	else
		print("SexyQuestHelper: " .. tostring(err))
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

-- Versions-Anhang fuer eine Zeile ("" wenn keine Daten vom Mitglied vorliegen)
local function VersionTag(name)
	if not members[name] then return "" end
	local v = versions[name]
	return v and (" |cff888888v" .. v .. "|r") or (" |cff888888(" .. T("alte Version", "old version") .. ")|r")
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

-- Spielername in Klassenfarbe (weiss, wenn die Klasse unbekannt ist)
local function ColoredName(name)
	local unit = unitByName[name]
	local class
	if unit then
		-- nicht "unit and UnitClass(unit)": "and" schneidet auf EINEN Rueckgabewert ab
		local _, classFile = UnitClass(unit)
		class = classFile
	end
	local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if not c then return "|cffffffff" .. name .. "|r" end
	return ("|cff%02x%02x%02x%s|r"):format(c.r * 255, c.g * 255, c.b * 255, name)
end

-- Liefert Zeilen { text, questID, teilbar }, ob es Quest-Unterschiede gibt und deren Signatur.
local function BuildRows()
	local rows, sameRows, sigParts, hasDiff = {}, {}, {}, false
	local inGroup = GroupChannel() or testMode

	if inGroup then
		for _, name in ipairs(GroupNames()) do
			local m = members[name]
			if not m then
				rows[#rows + 1] = { ("%s|cff888888: %s|r"):format(ColoredName(name), T("kein Addon / keine Daten", "no addon / no data")) }
			elseif m.zone ~= myZoneKey then
				rows[#rows + 1] = { ("%s|cff888888: %s (%s)|r%s"):format(ColoredName(name), T("anderes Gebiet", "different zone"), ZoneLabel(m.zone), VersionTag(name)) }
			else
				local iLack, theyLack = {}, {}
				for id in pairs(m.ids) do
					if not myIds[id] then iLack[#iLack + 1] = id end
				end
				for id in pairs(myIds) do
					if not m.ids[id] then theyLack[#theyLack + 1] = id end
				end
				table.sort(iLack); table.sort(theyLack)

				if #iLack + #theyLack == 0 then
					sameRows[#sameRows + 1] = { ("%s%s"):format(ColoredName(name), VersionTag(name)) }
				else
					hasDiff = true
					sigParts[#sigParts + 1] = name .. ":" .. table.concat(iLack, ",") .. "/" .. table.concat(theyLack, ",")
					rows[#rows + 1] = { ("%s%s"):format(ColoredName(name), VersionTag(name)) }
					for _, id in ipairs(iLack) do
						rows[#rows + 1] = { ("  |cffff6060%s|r %s"):format(T("Dir fehlt:", "You lack:"), QuestName(id)), id }
					end
					for _, id in ipairs(theyLack) do
						rows[#rows + 1] = { ("  |cff60c0ff%s|r %s"):format(T("Hat nicht:", "Lacks:"), QuestName(id)), id, CanShare(id) }
					end
				end
			end
		end
	end

	if not hasDiff then
		local msg = inGroup and T("Alle haben die gleichen Quests", "Everyone has the same quests")
			or T("Nicht in einer Gruppe.", "Not in a group.")
		table.insert(rows, 1, { "|cff00ff00" .. msg .. "|r" })
		for i, r in ipairs(sameRows) do table.insert(rows, 1 + i, r) end
	end
	return rows, hasDiff, table.concat(sigParts, ";")
end

local function GetRow(i)
	local row = rowPool[i]
	if row then return row end

	row = CreateFrame("Button", nil, ui)
	row:SetSize(WIDTH - 16, ROW_H)
	row:SetPoint("TOPLEFT", ui, "TOPLEFT", 8, -26 - (i - 1) * ROW_H)
	row:RegisterForClicks("LeftButtonUp")
	row.hl = row:CreateTexture(nil, "HIGHLIGHT")
	row.hl:SetAllPoints()
	row.hl:SetColorTexture(1, 1, 1, 0.15)
	row.fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.fs:SetAllPoints()
	row.fs:SetJustifyH("LEFT")
	row.fs:SetWordWrap(false)

	row.share = CreateFrame("Button", nil, row)
	row.share:SetSize(52, ROW_H - 2)
	row.share:SetPoint("RIGHT", row, "RIGHT", -2, 0)
	row.share.bg = row.share:CreateTexture(nil, "BACKGROUND")
	row.share.bg:SetAllPoints()
	row.share.bg:SetColorTexture(0.2, 0.6, 0.25, 0.8)
	row.share.hl = row.share:CreateTexture(nil, "HIGHLIGHT")
	row.share.hl:SetAllPoints()
	row.share.hl:SetColorTexture(1, 1, 1, 0.25)
	row.share.text = row.share:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.share.text:SetAllPoints()
	row.share.text:SetText(T("Teilen", "Share"))
	row.share:RegisterForClicks("LeftButtonUp")
	row.share:SetScript("OnClick", function()
		if row.questId then ShareQuest(row.questId) end
	end)
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
	f:SetBackdropColor(0, 0, 0, 0.8)

	local pos = SexyQuestHelperDB.pos
	if pos then
		f:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
	else
		f:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
	end

	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		SexyQuestHelperDB.pos = { point = point, relPoint = relPoint, x = x, y = y }
	end)

	f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.title:SetPoint("TOPLEFT", 8, -8)

	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)
	close:SetScript("OnClick", function()
		forceShow = false
		dismissedSig = f.sig -- erscheint erst wieder bei neuen Unterschieden
		f:Hide()
	end)

	f:Hide()
	return f
end

function Refresh()
	if not ui then return end
	local rows, hasDiff, sig = BuildRows()
	ui.sig = sig

	if not (forceShow or (hasDiff and sig ~= dismissedSig)) then
		ui:Hide()
		return
	end

	ui.title:SetText(("SexyQuestHelper |cffaaaaaav%s - %s|r"):format(VERSION, myZone ~= "" and myZone or "?"))
	for i, data in ipairs(rows) do
		local row = GetRow(i)
		row.questId = data[2]
		row:EnableMouse(data[2] ~= nil)
		row.fs:SetText(data[1])
		row.share:SetShown(data[3] and true or false)
		row.fs:ClearAllPoints()
		row.fs:SetPoint("LEFT", row, "LEFT", 0, 0)
		row.fs:SetPoint("RIGHT", row, "RIGHT", data[3] and -56 or 0, 0)
		row:Show()
	end
	for i = #rows + 1, #rowPool do rowPool[i]:Hide() end

	ui:SetHeight(34 + #rows * ROW_H)
	ui:Show()
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
	ignoreUntil = GetTime() + IGNORE_AFTER_SCAN

	local signature = myZoneKey .. ":" .. table.concat(SortedIds(myIds), ",")
	if forceBroadcast or signature ~= mySignature then
		mySignature = signature
		Broadcast()
	end
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
		if not present[name] then members[name] = nil; versions[name] = nil end
	end
end

frame:SetScript("OnEvent", function(_, event, ...)
	if event == "CHAT_MSG_ADDON" then
		OnAddonMessage(...)
	elseif event == "QUEST_DATA_LOAD_RESULT" then
		Refresh()
	elseif event == "QUEST_LOG_UPDATE" then
		if GetTime() >= ignoreUntil then QueueScan(false) end
	elseif event == "GROUP_ROSTER_UPDATE" then
		PruneMembers()
		QueueScan(true) -- neue Mitglieder brauchen unsere Liste
		Refresh()
	elseif event == "PLAYER_LOGIN" then
		SexyQuestHelperDB = SexyQuestHelperDB or {}
		ui = CreateUI() -- zuerst, damit /sqh auch bei spaeteren Fehlern funktioniert
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
	else -- Zonenwechsel, Betreten der Welt
		QueueScan(true)
	end
end)

for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "QUEST_LOG_UPDATE",
	"GROUP_ROSTER_UPDATE", "CHAT_MSG_ADDON" }) do
	frame:RegisterEvent(e)
end
pcall(frame.RegisterEvent, frame, "QUEST_DATA_LOAD_RESULT") -- nicht in jedem Client vorhanden

SLASH_SEXYQUESTHELPER1 = "/sqh"
SLASH_SEXYQUESTHELPER2 = "/sexyquesthelper"
SlashCmdList["SEXYQUESTHELPER"] = function(arg)
	if not ui then
		print("SexyQuestHelper: Oberflaeche nicht initialisiert (Fehler beim Laden?)")
		return
	end
	arg = (arg or ""):lower()
	if arg == "test" then
		testMode = not testMode
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
