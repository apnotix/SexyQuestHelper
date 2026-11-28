-- Quest-Aktionen (früher "Ziele anvisieren"): ein kleines Fenster mit den Monstern deiner offenen Töten-Quests, wie "Active Targets" in Rested XP:
-- je Monster ein Symbol (3D-Bild des Monsters, sobald es einmal angeklickt/überfahren wurde, sonst ein Totenkopf) mit
-- dem Zähler. Ein Klick auf ein Symbol visiert das Monster an (/targetexact <Name>). Aus dem Questlog gelesen: Quests des
-- aktuellen Gebiets (einstellbar), Ziele vom Typ "Monster", die noch nicht fertig sind.
-- Die Knöpfe sind gesicherte Knöpfe (SecureActionButtonTemplate): sie lassen sich im Kampf weder anlegen noch ändern.
-- Darum wird die Liste nur außerhalb des Kampfs aufgebaut; im Kampf bleibt der letzte Stand stehen.
-- Eigene Datei, damit die Hauptdatei nicht noch mehr lokale Variablen braucht (Lua erlaubt höchstens 200 je Block).

local SEM = LibStub("SexyEditMode-1.0", true)
if not (SEM and SEM.ui) then return end

local ui = SEM.ui
local de = GetLocale() == "deDE"
local function T(d, e) return de and d or e end

local HEAD, MAX_ICONS, PAD = 28, 40, 8
local HEAD_H, SEC_GAP = 22, 8   -- Höhe der Quest-Zeile, Abstand zwischen den Abschnitten
-- Gruppenzeile wie in SexyHarvester: dunkles Band über die Breite, links das Etikett (Badge) mit dem Questnamen
local TONES = {
	{ bg = { 0.082, 0.188, 0.11 }, fg = { 0.48, 0.88, 0.56 } },
	{ bg = { 0.227, 0.173, 0.063 }, fg = { 0.94, 0.75, 0.29 } },
	{ bg = { 0.078, 0.157, 0.227 }, fg = { 0.53, 0.8, 1 } },
}
local SKULL = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"

local function Cfg()
	SexyQuestHelperDB = SexyQuestHelperDB or {}
	SexyQuestHelperDB.targets = SexyQuestHelperDB.targets or {}
	return SexyQuestHelperDB.targets
end

-- Geheime Werte (issecretvalue) lassen sich nicht vergleichen oder umwandeln: dafür nil
local function Public(v)
	if v ~= nil and issecretvalue and issecretvalue(v) then return nil end
	return v
end

local function Get(key, default)
	local v = Cfg()[key]
	if v == nil then return default end
	return v
end

-- Entfernungsgrenze für Quests: die Reichweite von "Quests in der Nähe" (Meter zum nächsten Zielort); 0 = keine Grenze
local function MaxDist()
	if not Get("limitRange", true) then return 0 end
	return SexyQuestHelperAPI and SexyQuestHelperAPI.NearRadius and SexyQuestHelperAPI.NearRadius() or 0
end

-- Monstername aus dem Zieltext: "Wolf getötet: 3/8" -> "Wolf". Das Muster kommt aus Blizzards Text
-- (QUEST_MONSTERS_KILLED, in jeder Sprache anders); sonst wird einfach der Zähler hinten abgeschnitten.
local killPattern
local function MonsterName(text)
	if type(text) ~= "string" then return nil end
	if QUEST_MONSTERS_KILLED and killPattern == nil then
		local p = QUEST_MONSTERS_KILLED:gsub("([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1"):gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
		-- Sprachen mit nummerierten Platzhaltern (%1$s) lassen sich so nicht lesen: dann gilt der Rückfall
		if QUEST_MONSTERS_KILLED:find("%%%d%$") then killPattern = false else killPattern = "^" .. p .. "$" end
	end
	local okMatch, name = pcall(function() return killPattern and text:match(killPattern) end)
	if okMatch and name then return name, true end
	-- Rückfall: Zähler vorn ("3/6 Wolf slain") oder hinten ("Wolf getötet: 3/6") und das Wort "slain/getötet" entfernen
	text = text:gsub("^%s*%d+%s*/%s*%d+%s*", ""):gsub("%s*:?%s*%d+%s*/%s*%d+%s*$", "")
	-- "slain/killed/getötet" am Ende kennzeichnet ein echtes Tötenziel (zweiter Rückgabewert)
	local killed
	for _, word in ipairs({ "slain", "killed", "getötet" }) do
		local cut, n = text:gsub("%s+" .. word .. "$", "")
		if n > 0 then text, killed = cut, true end
	end
	text = text:gsub("%s*:$", "")
	return text, killed
end

local function LogEntry(i)
	if C_QuestLog and C_QuestLog.GetInfo then
		local info = C_QuestLog.GetInfo(i)
		if info then return info.title, info.isHeader, info.questID end
	elseif GetQuestLogTitle then
		local title, _, _, isHeader, _, _, _, questID = GetQuestLogTitle(i)
		return title, isHeader, questID
	end
end

-- Ziele einer Quest als { { type, text, finished, numFulfilled, numRequired }, ... }; ältere Clients ohne
-- C_QuestLog.GetQuestObjectives lesen die Zeilen des Questlogs
local function Objectives(id, index)
	if C_QuestLog and C_QuestLog.GetQuestObjectives then
		local ok, objs = pcall(C_QuestLog.GetQuestObjectives, id)
		if ok and type(objs) == "table" then return objs end
	end
	local out = {}
	if index and GetNumQuestLeaderBoards and GetQuestLogLeaderBoard then
		for i = 1, GetNumQuestLeaderBoards(index) do
			local text, kind, finished = GetQuestLogLeaderBoard(i, index)
			local a, b = tostring(text or ""):match("(%d+)/(%d+)")
			out[#out + 1] = { type = kind, text = text, finished = finished, numFulfilled = tonumber(a), numRequired = tonumber(b) }
		end
	end
	return out
end

-- Liste { { name, have, need }, ... } der noch offenen Monsterziele; debug schreibt jeden Schritt in den Chat (/sqhtargets)
local function Gather(debug)
	local out, seen = {}, {}
	local zoneOnly = Get("zoneOnly", true)
	local group = Get("groupByQuest", true)
	local zones = { strlower(GetZoneText() or ""), strlower(GetRealZoneText and GetRealZoneText() or "") }
	-- Gebiete, die im Questlog unter einem anderen Namen stehen (Alteracgebirge = Vorgebirge von Hillsbrad)
	local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	local alias = mapID and SexyQuestHelperZoneAlias and SexyQuestHelperZoneAlias[mapID]
	local info = alias and C_Map.GetMapInfo(alias)
	if info and info.name then zones[3] = strlower(info.name) end
	local n = (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and (C_QuestLog.GetNumQuestLogEntries()))
		or (GetNumQuestLogEntries and (GetNumQuestLogEntries())) or 0
	local header
	for i = 1, n do
		local title, isHeader, id = LogEntry(i)
		if isHeader then
			header = title and strlower(title)
		elseif id and id > 0 and not (SexyQuestHelperDB.nearHidden and SexyQuestHelperDB.nearHidden[id]) then   -- ausgeblendete Quests zählen nicht
			local inZone = not zoneOnly or not header or header == zones[1] or header == zones[2] or header == zones[3]
			-- Der Kopf im Questlog ist der Ort der Annahme: liegen die Ziele laut QuestieDB hier, zählt die Quest auch
			if not inZone and SexyQuestHelperAPI and SexyQuestHelperAPI.QuestHere then inZone = SexyQuestHelperAPI.QuestHere(id) end
			if debug then print(("|cffe8c26a[SQH]|r %s | Gebiet im Log: %s | passt: %s"):format(tostring(title), tostring(header), tostring(inZone))) end
			if inZone then
				-- Gegenstand, den die Quest benutzen lässt (Knopf im Questlog): erscheint im Fenster, solange man im Questgebiet ist
				if Get("showItems", true) then
					local okItem, link, icon, _, showComplete = pcall(function()
						if GetQuestLogSpecialItemInfo then return GetQuestLogSpecialItemInfo(i) end
						if C_QuestLog and C_QuestLog.GetQuestLogSpecialItemInfo then return C_QuestLog.GetQuestLogSpecialItemInfo(i) end
					end)
					local complete = C_QuestLog and C_QuestLog.IsComplete and C_QuestLog.IsComplete(id)
					if okItem and type(link) == "string" and (not complete or showComplete) then
						local itemID = tonumber(link:match("item:(%d+)"))
						if itemID then
							if debug then print("   Questgegenstand: " .. link) end
							out[#out + 1] = { name = link:match("%[(.-)%]") or ("item:" .. itemID), have = 0, need = 0, quest = title, questId = id, item = itemID, icon = icon }
						end
					end
				end
				local npcIds = SexyQuestHelperAPI and SexyQuestHelperAPI.MobIds and SexyQuestHelperAPI.MobIds(id) or {}
				local itemObj = 0   -- Zähler der Gegenstandsziele dieser Quest (ordnet sie den Dropquellen zu)
				for _, o in ipairs(Objectives(id, i)) do
					if o.type == "item" then itemObj = itemObj + 1 end
					if debug then print(("   Ziel: Art=%s fertig=%s Text=%s"):format(tostring(o.type), tostring(o.finished), tostring(o.text))) end
					-- Art "monster"; Clients ohne Art erkennt man am Text "Name getötet: 3/8"
					local isMob = o.type == "monster"
						or ((o.type == nil or o.type == "") and killPattern and type(o.text) == "string" and o.text:match(killPattern) ~= nil)
					if isMob and not o.finished then
						local okName, name, killed = pcall(MonsterName, o.text)
						if not okName then
							if debug then print("   Fehler im Namen: " .. tostring(name)) end
							name = type(o.text) == "string" and o.text or nil
						end
						-- Kennt QuestieDB eine Kreatur dieser Quest, deren Name im Zieltext steht, gilt ihr Name; lebt sie nicht
						-- in diesem Gebiet (Beschwörung, Ereignisziel wie "Auge von Kilrogg zur Straße geführt"), gibt es keinen Knopf
						local npc, skip
						local low = type(o.text) == "string" and strlower(o.text) or ""
						local best
						for nm, nid in pairs(npcIds) do
							if low:find(strlower(nm), 1, true) and (not best or #nm > #best) then best, npc = nm, nid end
						end
						if best then
							name = best
							if SexyQuestHelperAPI.MobHere and not SexyQuestHelperAPI.MobHere(npc) then skip = true end
						end
						-- Ereignisziele ("Auge zur Straße geführt") enden nicht auf "slain/getötet": in Sprachen, deren Text bekannt ist, kein Knopf
						if not killed and not best and (GetLocale() == "enUS" or GetLocale() == "enGB" or GetLocale() == "deDE") then
							skip = true
						end
						if debug then print("   Name: " .. tostring(name) .. (skip and " (übersprungen: kein Tötenziel oder lebt nicht in diesem Gebiet)" or "")) end
						local key = group and (id .. ":" .. (name or "")) or name
						if not skip and name and name ~= "" and not seen[key] then
							seen[key] = true
							out[#out + 1] = { name = name, have = o.numFulfilled or 0, need = o.numRequired or 0, npc = npc, quest = title, questId = id }
						end
					elseif o.type == "item" and not o.finished and SexyQuestHelperAPI and SexyQuestHelperAPI.DropMobs then
						-- Gegenstandsziel: Kreaturen, die ihn fallen lassen (aus QuestieDB, nur hier im Gebiet)
						local dropNames, dropIds = SexyQuestHelperAPI.DropMobs(id, 16, itemObj, o.text)
						for _, name in ipairs(dropNames) do
							local key = group and (id .. ":" .. name) or name
							if not seen[key] then
								seen[key] = true
								out[#out + 1] = { name = name, have = o.numFulfilled or 0, need = o.numRequired or 0, drop = true, quest = title, questId = id, npc = dropIds[name] }
							end
						end
					end
				end
			end
		end
	end
	return out
end

-- Fenster -----------------------------------------------------------------------------

local frame = CreateFrame("Frame", "SexyQuestHelperTargets", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
frame:SetSize(160, HEAD + 8)
frame:SetPoint("CENTER", UIParent, "CENTER", 320, 0)
frame:SetFrameStrata("MEDIUM")
frame:Hide()
ui.Backdrop(frame, ui.BG, ui.EDGE)

frame.band = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
frame.band:SetPoint("TOPLEFT", 3, -3)
frame.band:SetPoint("TOPRIGHT", -3, -3)
frame.band:SetHeight(HEAD - 3)
frame.band:SetColorTexture(ui.BAND[1], ui.BAND[2], ui.BAND[3], ui.BAND[4] or 1)
frame.title = ui.Text(frame, "GameFontNormal", 14)
frame.title:SetPoint("LEFT", frame.band, "LEFT", 8, 0)
frame.title:SetTextColor(ui.GOLD[1], ui.GOLD[2], ui.GOLD[3])
frame.title:SetText(T("Quest-Aktionen", "Quest actions"))

local rows = {}
frame.heads = {}   -- Überschriften der Quests (bei "Nach Quests gruppieren")
local editing, pending = false, false

-- Scrollbereich unter der Kopfzeile: ist die Liste höher als "Maximale Höhe", scrollt sie mit dem Mausrad
frame.scroll = CreateFrame("ScrollFrame", nil, frame)
frame.content = CreateFrame("Frame", nil, frame.scroll)
frame.content:SetSize(1, 1)
frame.scroll:SetScrollChild(frame.content)
frame.track = frame:CreateTexture(nil, "ARTWORK")
frame.track:SetWidth(4)
frame.track:SetColorTexture(0.15, 0.12, 0.07, 1)
frame.thumb = frame:CreateTexture(nil, "OVERLAY")
frame.thumb:SetWidth(4)
frame.thumb:SetColorTexture(0.42, 0.34, 0.15, 1)

local function UpdateScroll()
	local viewH, contentH = frame.scroll:GetHeight(), frame.content:GetHeight()
	local maxScroll = math.max(0, contentH - viewH)
	local cur = math.min(frame.scroll:GetVerticalScroll(), maxScroll)
	frame.scroll:SetVerticalScroll(cur)
	frame.thumb:SetShown(maxScroll > 0)
	frame.track:SetShown(maxScroll > 0)
	if maxScroll > 0 then
		local h = math.max(20, viewH * viewH / contentH)
		frame.thumb:SetHeight(h)
		frame.thumb:ClearAllPoints()
		frame.thumb:SetPoint("TOP", frame.track, "TOP", 0, -(viewH - h) * (cur / maxScroll))
	end
end

local function ScrollBy(delta)
	-- im Kampf bleiben die gesicherten Knöpfe, wo sie sind
	if InCombatLockdown() then return end
	local maxScroll = math.max(0, frame.content:GetHeight() - frame.scroll:GetHeight())
	frame.scroll:SetVerticalScroll(math.max(0, math.min(maxScroll, frame.scroll:GetVerticalScroll() - delta * 40)))
	UpdateScroll()
end
frame.scroll:EnableMouseWheel(true)
frame.scroll:SetScript("OnMouseWheel", function(_, delta) ScrollBy(delta) end)
frame:EnableMouseWheel(true)
frame:SetScript("OnMouseWheel", function(_, delta) ScrollBy(delta) end)

-- gelernte Kreatur-IDs (Name -> ID) für das 3D-Bild; stammen aus Ziel und Maus-Über
local function Ids()
	local c = Cfg()
	c.ids = c.ids or {}
	return c.ids
end

local RebuildSoon   -- wird unten gesetzt (Soon)

-- Option "Standbild": statt eines bewegten 3D-Modells ein ruhendes 2D-Bild, wie es auch das Dungeon Journal macht:
-- SetPortraitTextureFromCreatureDisplayID zeichnet das Modell einmal in eine Textur. Dafür braucht es die DisplayID der Kreatur; ein
-- verstecktes Modell (1x1, durchsichtig) lädt nacheinander jede Kreatur-ID und liefert sie mit GetDisplayInfo (gemerkt in
-- Cfg().displays). Auf dem Forever-Client ist ein neu gezeichnetes Bild bis zum Laden ein schwarzes Quadrat, das über allem liegt:
-- darum wird es zuerst außerhalb des Bildschirms gezeichnet und erst nach einigen Sekunden ins Symbol gesetzt.
local STILL_WAIT = 3
-- Standbild ist der Standard; bewegte 3D-Modelle nur mit der Option "animatedAvatar"
local function StaticOn() return not Get("animatedAvatar", false) end
local still = { queue = {}, queued = {} }

local function StillAvailable() return type(SetPortraitTextureFromCreatureDisplayID) == "function" end

local function Displays()
	local c = Cfg()
	c.displays = c.displays or {}
	return c.displays
end

local function StillStage()
	if not still.stage then
		still.stage = CreateFrame("Frame", nil, UIParent)
		still.stage:SetSize(64, 64)
		still.stage:SetPoint("TOPLEFT", UIParent, "TOPRIGHT", 10000, 0)   -- weit außerhalb, auch auf Ultrawide-Bildschirmen
		still.stage:Show()
	end
	return still.stage
end

-- Textur aus dem Symbol nehmen und wegstellen (die Textur wird geleert: das gibt den Render-Slot der Grafikkarte frei)
local function ClearStill(row)
	local tex = row.still
	if not tex then return end
	pcall(tex.SetTexture, tex, nil)
	tex:SetParent(StillStage())
	tex:Hide()
	row.stillDisplay, row.stillSource, row.stillName = nil, nil, nil
end

-- Bild aus einer Einheit, die du gerade hast (Ziel, Maus-Über, Namensschild), wie RestedXP in "Active Targets": SetPortraitTexture
-- zeichnet sofort, das Modell ist ja geladen; kein Warten, keine DisplayID. Das Bild bleibt in der Textur, auch wenn die Einheit weg ist.
local function DrawUnitStill(row, unit)
	local tex = row.still
	if not tex then
		tex = StillStage():CreateTexture(nil, "ARTWORK")
		row.still = tex
	end
	row.model:Hide()
	row.portraitId = nil
	tex:SetParent(row)
	tex:ClearAllPoints()
	tex:SetPoint("TOPLEFT", row, "TOPLEFT", 1, -1)
	tex:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -1, 1)
	tex:SetDrawLayer("ARTWORK", 1)
	tex:SetTexCoord(0, 1, 0, 1)
	pcall(SetPortraitTexture, tex, unit)
	tex:Show()
	row.skull:Hide()
	row.stillSource, row.stillName, row.stillDisplay = "unit", row.mob, nil
	tex:SetDesaturated(row.dim and true or false)
	tex:SetAlpha(row.dim and 0.4 or 1)
end

-- Kreatur-ID -> DisplayID über das versteckte Modell, eine nach der anderen
local function ResolveNext()
	if still.current then return end
	local id = table.remove(still.queue, 1)
	if not id then return end
	still.current = id
	local m = still.model
	if not m then
		m = CreateFrame("PlayerModel", nil, UIParent)
		m:SetSize(1, 1)
		m:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
		m:SetAlpha(0)
		still.model = m
	end
	local function finish(display)
		if still.current ~= id then return end
		still.current = nil
		still.queued[id] = nil
		m:SetScript("OnModelLoaded", nil)
		m:Hide()
		if type(display) == "number" and display > 0 then
			Displays()[id] = display
			if RebuildSoon then RebuildSoon() end
		end
		C_Timer.After(0.2, ResolveNext)
	end
	m:Show()
	if m.ClearModel then pcall(m.ClearModel, m) end
	m:SetScript("OnModelLoaded", function()
		local ok, display = pcall(m.GetDisplayInfo, m)
		finish(ok and display or nil)
	end)
	if not pcall(m.SetCreature, m, id) then finish(nil) return end
	C_Timer.After(STILL_WAIT, function() finish(nil) end)   -- lädt das Modell nicht, geht es mit der nächsten ID weiter
end

local function QueueResolve(id)
	if still.queued[id] or Displays()[id] == false then return end
	still.queued[id] = true
	still.queue[#still.queue + 1] = id
	ResolveNext()
end

-- Standbild im Symbol: ohne bekannte DisplayID bleibt der Totenkopf, bis sie aufgelöst ist
local function StillPortrait(row, id)
	row.model:Hide()
	row.portraitId = nil
	-- schon aus einer Einheit gezeichnet (für denselben Mob): bleibt
	if row.stillSource == "unit" and row.stillName == row.mob and row.still and row.still:IsShown() then return end
	local display = id and Displays()[id]
	if not display then
		ClearStill(row)
		row.skull:Show()
		if id then QueueResolve(id) end
		return
	end
	if row.stillDisplay == display and row.still and row.still:IsShown() then return end
	local tex = row.still
	if not tex then
		tex = StillStage():CreateTexture(nil, "ARTWORK")
		row.still = tex
	end
	row.stillDisplay, row.stillSource, row.stillName = display, "display", nil
	pcall(tex.SetTexture, tex, nil)
	tex:SetParent(StillStage())
	tex:ClearAllPoints()
	tex:SetAllPoints(StillStage())
	tex:SetTexCoord(0, 1, 0, 1)
	tex:Show()
	pcall(SetPortraitTextureFromCreatureDisplayID, tex, display)
	local shown = tex:GetTexture()
	if shown == nil or shown == 0 or shown == "" then   -- der Client kennt kein Bild für diese DisplayID
		ClearStill(row)
		row.skull:Show()
		return
	end
	row.skull:Show()   -- bis das Bild geladen ist
	C_Timer.After(STILL_WAIT, function()
		if row.still ~= tex or row.stillDisplay ~= display or not StaticOn() then return end
		tex:SetParent(row)
		tex:ClearAllPoints()
		tex:SetPoint("TOPLEFT", row, "TOPLEFT", 1, -1)
		tex:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -1, 1)
		tex:SetDrawLayer("ARTWORK", 1)
		tex:SetTexCoord(0, 1, 0, 1)
		tex:Show()
		row.skull:Hide()
		-- grau wie das Symbol (siehe UpdateNear)
		tex:SetDesaturated(row.dim and true or false)
		tex:SetAlpha(row.dim and 0.4 or 1)
	end)
end

local function UnitStill(unit)
	if not (StaticOn() and StillAvailable()) then return end
	local ok, name = pcall(function()
		if UnitExists(unit) and not UnitIsPlayer(unit) then return Public(UnitName(unit)) end
	end)
	if not ok or type(name) ~= "string" then return end
	for _, row in ipairs(rows) do
		if row:IsShown() and not row.itemID and row.mob == name and not (row.stillSource == "unit" and row.stillName == name) then
			DrawUnitStill(row, unit)
		end
	end
end

local function Portrait(row, id)
	if StaticOn() and StillAvailable() then
		StillPortrait(row, id)
		return
	end
	if row.still then ClearStill(row) end
	if row.portraitId == id then return end
	row.portraitId = id
	row.skull:SetShown(not id)
	row.model:SetShown(id and true or false)
	if id then
		row.model:ClearModel()
		local ok = pcall(row.model.SetCreature, row.model, id)
		if row.model.SetPortraitZoom then pcall(row.model.SetPortraitZoom, row.model, 1) end
		if not ok then row.skull:Show(); row.model:Hide() end
	end
end

local function GetRow(i)
	local row = rows[i]
	if row then return row end
	row = CreateFrame("Button", nil, frame.content, "SecureActionButtonTemplate")
	row:RegisterForClicks("AnyUp")
	row:SetAttribute("useOnKeyDown", false)
	row.edge = row:CreateTexture(nil, "BACKGROUND")
	row.edge:SetAllPoints()
	row.edge:SetColorTexture(ui.EDGE[1], ui.EDGE[2], ui.EDGE[3], 1)
	row.bg = row:CreateTexture(nil, "BACKGROUND", nil, 1)
	row.bg:SetPoint("TOPLEFT", 1, -1)
	row.bg:SetPoint("BOTTOMRIGHT", -1, 1)
	row.bg:SetColorTexture(ui.ROWBG[1], ui.ROWBG[2], ui.ROWBG[3], 1)
	row.skull = row:CreateTexture(nil, "ARTWORK")
	row.skull:SetPoint("TOPLEFT", 5, -5)
	row.skull:SetPoint("BOTTOMRIGHT", -5, 5)
	row.skull:SetTexture(SKULL)
	row.icon = row:CreateTexture(nil, "ARTWORK")   -- Symbol eines Questgegenstands
	row.icon:SetPoint("TOPLEFT", 2, -2)
	row.icon:SetPoint("BOTTOMRIGHT", -2, 2)
	row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	row.icon:Hide()
	row.model = CreateFrame("PlayerModel", nil, row)
	row.model:SetPoint("TOPLEFT", 1, -1)
	row.model:SetPoint("BOTTOMRIGHT", -1, 1)
	row.model:Hide()
	row.over = CreateFrame("Frame", nil, row)
	row.over:SetAllPoints()
	row.over:SetFrameLevel(row:GetFrameLevel() + 5)
	row.hl = row.over:CreateTexture(nil, "HIGHLIGHT")
	row.hl:SetAllPoints()
	row.hl:SetColorTexture(1, 1, 1, 0.12)
	row.countBg = row.over:CreateTexture(nil, "BACKGROUND")   -- dunkle Fläche hinter dem Zähler im kompakten Modus
	row.countBg:SetColorTexture(0, 0, 0, 0.65)
	row.count = ui.Text(row.over, "GameFontHighlightSmall", 12)
	row.countBg:SetPoint("TOPLEFT", row.count, "TOPLEFT", -2, 1)
	row.countBg:SetPoint("BOTTOMRIGHT", row.count, "BOTTOMRIGHT", 2, -1)
	row.count:SetPoint("TOP", row, "BOTTOM", 0, -2)   -- Zähler mittig unter dem Symbol
	row.count:SetTextColor(0.94, 0.75, 0.29)
	row:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if self.itemID then
			local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. self.itemID)
			if not ok then GameTooltip:SetText(self.mob or "", 1, 1, 1) end
			GameTooltip:AddLine(T("Klick: Gegenstand benutzen", "Click: use the item"), 0.6, 0.6, 0.6)
			GameTooltip:Show()
			return
		end
		GameTooltip:SetText(self.mob or "", 1, 1, 1)
		if self.quest then GameTooltip:AddLine(self.quest, 0.91, 0.76, 0.42) end
		if self.need and self.need > 0 then GameTooltip:AddLine(self.have .. "/" .. self.need, 0.94, 0.75, 0.29) end
		if not editing then
			GameTooltip:AddLine(T("Klick: anvisieren (das Monster muss in Sichtweite sein)", "Click: target (the mob must be in sight)"), 0.6, 0.6, 0.6)
			GameTooltip:AddLine(T("Rechtsklick: in den Gruppenchat schreiben", "Right click: post to group chat"), 0.6, 0.6, 0.6)
		end
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", GameTooltip_Hide)
	row.model:SetAlpha(frame:GetAlpha())
	rows[i] = row
	return row
end

-- 3D-Modelle übernehmen die Transparenz des Fensters nicht: "Im Kampf ausblenden" (SexyEditMode setzt nur die Alpha) ließe die
-- Avatare sichtbar. Darum die Alpha des Fensters an die Modelle weitergeben.
local DIM = 0.4   -- Deckkraft eines grauen Symbols (kein Monster in der Nähe)
local function ModelAlpha(row, a)
	row.model:SetAlpha((a or frame:GetAlpha()) * (row.dim and DIM or 1))
	if row.still then   -- Standbild: erbt die Deckkraft des Fensters, nur das Grau kommt dazu
		row.still:SetAlpha(row.dim and DIM or 1)
		row.still:SetDesaturated(row.dim and true or false)
	end
end
-- "Ausblenden" und "Im Kampf ausblenden" setzen von SexyEditMode aus nur die Transparenz: ein durchsichtiges Fenster fängt aber weiter
-- Mausklicks ab, und die Symbole (gesicherte Knöpfe) lösen ihr Makro aus. Darum wird das Fenster dann ganz versteckt (Hide
-- am Fenster selbst ist auch im Kampf erlaubt, die Knöpfe sind nicht betroffen). "Nur bei Mouseover" bleibt durchsichtig: dort
-- muss die Maus das Fenster erreichen.
-- In einem Dungeon oder Schlachtzug? (Einstellung "In Dungeons und Schlachtzügen")
local function InDungeon()
	local inInstance, kind = IsInInstance()
	return inInstance and (kind == "party" or kind == "raid") and true or false
end

local function HiddenBySetting()
	local d = Cfg().editMode
	if editing then return false end
	if Get("instance", "show") == "hide" and InDungeon() then return true end
	if not d then return false end
	return (d.hidden or (d.hideInCombat and (InCombatLockdown() or UnitAffectingCombat("player")))) and true or false
end

local function SyncShown()
	frame:SetShown(frame.hasContent and not HiddenBySetting() and true or false)
end

hooksecurefunc(frame, "SetAlpha", function(self, a)
	for _, row in ipairs(rows) do ModelAlpha(row, a) end
	SyncShown()
end)

-- Nähe: Ein Monster gilt als nah, wenn sein Namensschild (Nameplate) da ist, also im Sichtbereich der Schilder (etwa 40 Meter,
-- Feinde müssen Schilder anzeigen). Solange keins da ist, ist sein Symbol grau; sobald eins auftaucht, bunt.
local near = {}
local function UpdateNear()
	local on = Get("grayAway", true) and not editing
	for _, row in ipairs(rows) do
		if row:IsShown() and not row.itemID then
			local dim = on and not near[row.mob]
			row.dim = dim and true or false
			row.skull:SetDesaturated(dim)
			if row.model.SetDesaturation then row.model:SetDesaturation(dim and 1 or 0) end
			ModelAlpha(row)
		end
	end
end

local nearDebug = {}

-- Von anderen getaggt (graue Namensschild-Leiste). Fehlt die Funktion oder liefert sie einen geheimen Wert, gilt der Mob als frei:
-- ein Fehler hier würde sonst die ganze Prüfung des Mobs abbrechen (und ihn grau lassen).
local function Tapped(unit)
	if not UnitIsTapDenied then return false end
	local ok, v = pcall(UnitIsTapDenied, unit)
	if not ok then nearDebug.tapErr = tostring(v) return false end
	v = Public(v)
	if v == true then nearDebug.tapped = (nearDebug.tapped or 0) + 1 end
	return v == true
end
local function ScanNear()
	local seen = {}
	local plates, secret, units = 0, 0, {}
	nearDebug.tapped = 0
	if C_NamePlate and C_NamePlate.GetNamePlates then
		for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
			plates = plates + 1
			units[#units + 1] = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
		end
	end
	units[#units + 1] = "target"
	units[#units + 1] = "mouseover"
	for _, unit in ipairs(units) do
		UnitStill(unit)
		pcall(function()
			if UnitExists(unit) and UnitCanAttack("player", unit) and not UnitIsPlayer(unit) and not UnitIsDead(unit)
				and not Tapped(unit) then   -- von anderen getaggte Mobs zählen nicht
				local name = Public(UnitName(unit))
				if type(name) == "string" then seen[name] = true else secret = secret + 1 end
			end
		end)
	end
	nearDebug.plates, nearDebug.secret = plates, secret
	nearDebug.names = {}
	for k in pairs(seen) do nearDebug.names[#nearDebug.names + 1] = k end
	local changed = false
	for k in pairs(seen) do if not near[k] then changed = true end end
	for k in pairs(near) do if not seen[k] then changed = true end end
	near = seen
	if changed then
		UpdateNear()
		-- Reihenfolge ändert sich (Monster in der Nähe zuerst): neu aufbauen, nicht im Kampf (gesicherte Knöpfe)
		if Get("sortNear", true) and not InCombatLockdown() and RebuildSoon then RebuildSoon() end
	end
end
C_Timer.NewTicker(0.5, function()
	if frame:IsShown() and Get("grayAway", true) and not editing then ScanNear() end
end)

-- Das Symbol des gerade anvisierten Monsters bekommt einen goldenen, dickeren Rand
local function Highlight()
	local okName, target = pcall(function() return UnitExists("target") and Public(UnitName("target")) or nil end)
	if not okName then target = nil end
	for _, row in ipairs(rows) do
		local on = row:IsShown() and target ~= nil and row.mob == target and not row.itemID
		local c = on and ui.GOLD or ui.EDGE
		row.edge:SetColorTexture(c[1], c[2], c[3], 1)
		local inset = on and 2 or 1
		row.bg:ClearAllPoints()
		row.bg:SetPoint("TOPLEFT", inset, -inset)
		row.bg:SetPoint("BOTTOMRIGHT", -inset, inset)
	end
end

-- Makro eines Knopfs: Monster anvisieren, danach (einstellbar, standardmäßig aus) mit dem Totenkopf markieren.
-- Markiert wird mit dem Slash-Befehl /tm (Blizzards eigener, sicherer Befehl): ein /script mit SetRaidTarget würde
-- den Knopf unsicher machen ("ForceTaint_Strong ... blocked from an action only available to the Blizzard UI").
local NL = string.char(10)
-- aliveOnly: ist das gefundene Ziel tot ([dead] prüft das aktuelle Ziel), nochmal anvisieren (Wiederholen springt zum nächsten
-- Monster gleichen Namens); bleibt am Ende nur ein Toter, wird die Auswahl aufgehoben. Markiert wird nur, wenn ein Ziel da ist.
-- Ping von Blizzard auf den anvisierten Mob (Option "pingMark"): der Befehl des Clients (SLASH_PING1, je Sprache anders) mit
-- [@target]. Ohne Ziel sendet der Client nichts. Im Schlachtzug nur als Leiter oder Assistent. nil, wenn der Client den Befehl nicht kennt.
local function PingLine()
	if not Get("pingMark", true) then return nil end
	local cmd = SLASH_PING1
	if type(cmd) ~= "string" or not cmd:find("^/[^%s%c]+$") then return nil end
	if IsInRaid() and not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then return nil end
	return cmd .. " [@target,nodead]"
end

local function MacroFor(name, mark, aliveOnly)
	local m
	if aliveOnly then
		m = "/targetexact " .. name .. NL .. "/targetexact [dead] " .. name .. NL .. "/targetexact [dead] " .. name
			.. NL .. "/cleartarget [dead]"
	else
		m = "/targetexact " .. name .. NL .. "/target " .. name
	end
	local ping = PingLine()
	if ping then m = m .. NL .. ping end
	if mark then m = m .. NL .. (aliveOnly and "/tm [exists] 8" or "/tm 8") end
	return m
end

-- Rechtsklick-Makro: Gruppenchat (im Schlachtzug der Schlachtzugschat); ohne Gruppe geht nichts hinaus
local function ChatMacro(g)
	local text = T("Brauche: ", "Need: ") .. g.name
	if g.quest then text = text .. " (" .. g.quest .. ")" end
	if g.need and g.need > 0 then text = text .. " " .. g.have .. "/" .. g.need end
	text = text:gsub("[%c|]", ""):sub(1, 200)
	-- Der Kanal steht beim Aufbau fest (Bedingungen wie [group:party] kennt /p nicht: sie landeten als Text im Chat); bei
	-- Änderungen der Gruppe wird das Fenster neu aufgebaut. Allein: kein Makro, es geht nichts hinaus.
	if IsInRaid() then return "/raid " .. text end
	if IsInGroup() then return ((IsInGroup(LE_PARTY_CATEGORY_INSTANCE or 2) and "/i ") or "/p ") .. text end
	return ""
end

-- Tasten: bis zu 5 Belegungen, die n-te Taste visiert den nächsten freien Mob der n-ten Quest im Fenster an. Jede Taste hängt (per
-- Override-Bindung) an einem gesicherten Knopf, der vor dem Klick (PreClick, nur außerhalb des Kampfs) ein Symbol der Quest wählt und
-- anklickt. Weitere Drücke gehen zum jeweils nächsten Symbol.
local HK = { quests = {}, MAX = 5, MODS = { LSHIFT = 1, RSHIFT = 1, LCTRL = 1, RCTRL = 1, LALT = 1, RALT = 1, LMETA = 1, RMETA = 1 } }

function HK.Keys()
	local c = Cfg()
	c.hotkeys = c.hotkeys or {}
	return c.hotkeys
end

-- "CTRL-F1" wird zu "Strg + F1" (Namen der Spieltasten, in der Sprache des Clients)
function HK.Pretty(hk)
	if not hk then return nil end
	local mods, rest = "", hk
	for _, m in ipairs({ { "ALT-", ALT_KEY_TEXT or "Alt" }, { "CTRL-", CTRL_KEY_TEXT or "Ctrl" }, { "SHIFT-", SHIFT_KEY_TEXT or "Shift" } }) do
		if rest:sub(1, #m[1]) == m[1] then mods = mods .. m[2] .. " + "; rest = rest:sub(#m[1] + 1) end
	end
	return mods .. (_G["KEY_" .. rest] or rest)
end

local hotOwner = CreateFrame("Frame")   -- Besitzer der Override-Bindungen
function HK.Bind()
	if InCombatLockdown() then HK.pendingBind = true return end
	HK.pendingBind = nil
	ClearOverrideBindings(hotOwner)
	for i = 1, HK.MAX do
		local key = HK.Keys()[i]
		if key then SetOverrideBindingClick(hotOwner, false, key, "SexyQuestHelperHot" .. i, "LeftButton") end
	end
end

-- Symbol der Quest auf Platz i, das der Hotkey anklickt: genau die Symbole, die das Fenster zeigt (eingeklappte und graue, also
-- ohne freien Mob in der Nähe, fallen weg). Ist das aktuelle Ziel eins davon, kommt das nächste, nach dem letzten das erste.
-- Der Klick läuft über den Knopf des Symbols selbst: dasselbe Makro (anvisieren, Ping, Totenkopf) wie bei einem Mausklick.
function HK.Pick(i)
	local q = HK.quests[i]
	if not q then return nil end
	local list = {}
	for _, row in ipairs(rows) do
		if row:IsShown() and row.questId == q.id and not row.itemID and not row.dim then list[#list + 1] = row end
	end
	if #list == 0 then return nil end
	local okT, target = pcall(function() return UnitExists("target") and Public(UnitName("target")) or nil end)
	if okT and target then
		for k, row in ipairs(list) do
			if row.mob == target then return list[k % #list + 1] end
		end
	end
	return list[1]
end

for i = 1, HK.MAX do
	local b = CreateFrame("Button", "SexyQuestHelperHot" .. i, UIParent, "SecureActionButtonTemplate")
	b:RegisterForClicks("AnyUp")
	b:SetAttribute("useOnKeyDown", false)
	b:SetAttribute("type", "macro")
	b:SetAttribute("macrotext", "")
	b:SetScript("PreClick", function(self, _, down)
		if down or InCombatLockdown() then return end   -- im Kampf bleibt das zuletzt gesetzte Ziel
		local row = HK.Pick(i)
		if row then
			self:SetAttribute("type", "click")
			self:SetAttribute("clickbutton", row)
		else
			self:SetAttribute("type", "macro")
			self:SetAttribute("macrotext", "")
		end
	end)
end

-- Taste abfragen (Esc bricht ab, nach 10 Sekunden gibt die Abfrage auf)
function HK.Capture(i)
	if not HK.capture then
		local c = CreateFrame("Frame", nil, UIParent)
		c:SetFrameStrata("TOOLTIP")
		c:SetScript("OnKeyDown", function(self, key)
			self:SetPropagateKeyboardInput(false)
			if HK.MODS[key] then return end
			self:EnableKeyboard(false)
			self:Hide()
			HK.capturing = nil
			local slot = self.slot
			if key ~= "ESCAPE" and slot then
				HK.Keys()[slot] = (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "")
					.. (IsShiftKeyDown() and "SHIFT-" or "") .. key
				HK.Bind()
			end
			if SEM.RefreshDialog then SEM:RefreshDialog() end
		end)
		HK.capture = c
	end
	HK.capture.slot = i
	HK.capturing = i
	HK.capture:Show()
	HK.capture:EnableKeyboard(true)
	C_Timer.After(10, function()
		if HK.capturing == i then
			HK.capture:EnableKeyboard(false)
			HK.capture:Hide()
			HK.capturing = nil
			if SEM.RefreshDialog then SEM:RefreshDialog() end
		end
	end)
end

function HK.Row(i)
	return { type = "keybind",
		name = T("Taste für Quest ", "Key for quest ") .. i .. T(" im Fenster", " in the window"),
		get = function() return HK.Pretty(HK.Keys()[i]) end,
		waiting = function() return HK.capturing == i end,
		onClick = function() HK.Capture(i) end,
		onClear = function() HK.Keys()[i] = nil; HK.Bind() end }
end

-- Symbole neu aufbauen (nur außerhalb des Kampfs: gesicherte Knöpfe)
local function Apply()
	if InCombatLockdown() then
		pending = true
		return
	end
	pending = false

	local list
	if editing then
		list = {
			{ name = T("Beispiel-Monster", "Sample mob"), have = 3, need = 8, quest = T("Beispiel-Quest", "Sample quest") },
			{ name = T("Noch ein Monster", "Another mob"), have = 0, need = 5, quest = T("Beispiel-Quest", "Sample quest") },
			{ name = T("Drittes Monster", "Third mob"), have = 5, need = 5, quest = T("Andere Quest", "Other quest") },
			{ name = T("Quest-Gegenstand", "Quest item"), have = 0, need = 0, quest = T("Andere Quest", "Other quest"), item = 6948, icon = 134414 },
		}
	elseif Get("enabled", true) then
		list = Gather()
	else
		list = {}
	end

	-- Nach Entfernung sortieren: Quests mit dem nächsten Zielort zuerst (Entfernung aus QuestieDB), Quests ohne bekannten Ort
	-- dahinter in ihrer bisherigen Reihenfolge. Die Reihenfolge innerhalb einer Quest bleibt.
	local distOf = {}
	local maxDist = MaxDist()
	local haveDist = not editing and SexyQuestHelperAPI and SexyQuestHelperAPI.QuestDistance
	frame.allQuests = {}
	if haveDist and (Get("sortDistance", true) or maxDist > 0) then
		for _, g in ipairs(list) do
			if g.questId and distOf[g.questId] == nil then
				distOf[g.questId] = SexyQuestHelperAPI.QuestDistance(g.questId) or false
				frame.allQuests[#frame.allQuests + 1] = g.questId
			end
		end
	end
	-- Entfernungsgrenze: Quests, deren nächster Zielort weiter weg liegt, erscheinen noch nicht (unbekannter Ort: immer sichtbar)
	if haveDist and maxDist > 0 then
		local kept = {}
		for _, g in ipairs(list) do
			local d = g.questId and distOf[g.questId]
			if not (d and d > maxDist) then kept[#kept + 1] = g end
		end
		list = kept
	end
	if Get("sortDistance", true) and haveDist then
		local order = {}
		for i, g in ipairs(list) do order[g] = i end
		table.sort(list, function(a, b)
			local da, db = a.questId and distOf[a.questId], b.questId and distOf[b.questId]
			if da and db and da ~= db then return da < db end
			if (da and true or false) ~= (db and true or false) then return da and true or false end
			return order[a] < order[b]
		end)
	end
	-- Innerhalb einer Quest zuerst die Monster in der Nähe (und Gegenstände), die Reihenfolge der Quests bleibt
	if Get("sortNear", true) and Get("grayAway", true) and not editing then
		local qpos, order = {}, {}
		for i, g in ipairs(list) do
			order[g] = i
			if g.questId and not qpos[g.questId] then qpos[g.questId] = i end
		end
		table.sort(list, function(a, b)
			local qa, qb = a.questId and qpos[a.questId] or 0, b.questId and qpos[b.questId] or 0
			if qa ~= qb then return qa < qb end
			local na, nb = (a.item or near[a.name]) and 0 or 1, (b.item or near[b.name]) and 0 or 1
			if na ~= nb then return na < nb end
			return order[a] < order[b]
		end)
	end
	frame.orderSig = nil   -- wird unten aus den Quest-IDs der Reihenfolge gebildet (siehe Ticker)

	-- Aussehen nach Einstellung: Symbolgröße, Symbole je Zeile, Abstand, Deckkraft, Zähler
	local size = Get("iconSize", 28)
	local perRow = Get("perRow", 6)
	local gap = Get("gap", 6)
	local opacity = Get("opacity", ui.BG[4] or 0.96)
	local showCount = Get("showCount", true)
	local cc = Get("countColor", nil) or { r = 0.94, g = 0.75, b = 0.29 }
	frame:SetBackdropColor(ui.BG[1], ui.BG[2], ui.BG[3], opacity)
	frame.band:SetColorTexture(ui.BAND[1], ui.BAND[2], ui.BAND[3], opacity)

	-- Kompakter Modus: keine Kopfzeile, keine Gruppen, enge Abstände, der Zähler sitzt im Symbol
	local compact = Get("compact", false) or (Get("instance", "show") == "mini" and InDungeon())   -- kompakt auch in der Instanz, wenn so eingestellt
	local groupBy = Get("groupByQuest", true) and not compact
	if compact then gap = math.min(gap, 3) end

	-- Kopfzeile ausblenden: Band und Titel weg, die Symbole rücken nach oben
	local hide = Get("hideHeader", false) or compact
	local head = hide and 4 or HEAD
	frame.band:SetShown(not hide)
	frame.title:SetShown(not hide)

	-- Abschnitte: bei "Nach Quests gruppieren" je Quest eine Überschrift mit ihren Monstern, sonst ein Abschnitt ohne Überschrift
	local sections, byKey = {}, {}
	local count = 0
	local perQuest, maxPerQuest = {}, Get("maxPerQuest", 6)
	for _, g in ipairs(list) do
		if count >= MAX_ICONS then break end
		-- höchstens so viele Symbole je Quest (Quests mit vielen Dropquellen verdrängen sonst die anderen); die Monster in
		-- der Nähe stehen durch die Sortierung vorn und bleiben sichtbar. Questgegenstände zählen nicht mit.
		local qk = g.questId
		local skip = false
		if qk and not g.item then
			perQuest[qk] = (perQuest[qk] or 0) + 1
			skip = perQuest[qk] > maxPerQuest
		end
		if not skip then
			count = count + 1
			local key = groupBy and (g.quest or "?") or ""
			local sec = byKey[key]
			if not sec then
				sec = { title = groupBy and (g.quest or "?") or nil, questId = g.questId, items = {} }
				sec.collapseKey = sec.questId and tostring(sec.questId) or sec.title
				byKey[key] = sec
				sections[#sections + 1] = sec
			end
			sec.items[#sec.items + 1] = g
		end
	end

	-- feste Breite (0 = automatisch): bestimmt, wie viele Symbole in eine Reihe passen; "Symbole pro Zeile" gilt dann nicht
	local fixedW = Get("width", 200)
	if fixedW > 0 then fixedW = math.max(120, fixedW) end
	local perRowEff = fixedW > 0 and math.max(1, math.floor((fixedW - 2 * PAD + gap) / (size + gap))) or perRow

	local counterBelow = showCount and not compact
	local cell = size + (counterBelow and 15 or 0)   -- Höhe einer Zelle: Symbol plus Zähler darunter
	local ids = Ids()
	local mark = Get("markSkull", true)
	local aliveOnly = Get("aliveOnly", true)
	local collapsed = Cfg().collapsed or {}
	-- y zählt im Scrollbereich (frame.content) ab dessen Oberkante
	local maxCols, y, used, heads = 1, 4, 0, 0
	for _, sec in ipairs(sections) do
		local cols = math.max(1, math.min(#sec.items, perRowEff))
		maxCols = math.max(maxCols, cols)
		local folded = sec.title and collapsed[sec.collapseKey]
		if sec.title then
			heads = heads + 1
			local h = frame.heads[heads]
			if not h then
				h = CreateFrame("Frame", nil, frame.content)
				h:SetHeight(HEAD_H)
				-- Quest-Tooltip beim Überfahren der Gruppenzeile (wie in "Quests in der Nähe"), Klick klappt die Gruppe ein oder aus
				h:EnableMouse(true)
				h:SetScript("OnEnter", function(self)
					GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
					local ok = self.questId and pcall(GameTooltip.SetHyperlink, GameTooltip, ("quest:%d:%d"):format(self.questId, UnitLevel("player")))
					if not ok then
						GameTooltip:ClearLines()
						GameTooltip:AddLine(self.sectionTitle or "")
					end
					GameTooltip:AddLine(T("Klick: ein- oder ausklappen", "Click: collapse or expand"), 0.6, 0.6, 0.6)
					GameTooltip:Show()
				end)
				h:SetScript("OnLeave", GameTooltip_Hide)
				h:SetScript("OnMouseUp", function(self, button)
					if button ~= "LeftButton" or not self.collapseKey then return end
					local c = Cfg()
					c.collapsed = c.collapsed or {}
					c.collapsed[self.collapseKey] = (not c.collapsed[self.collapseKey]) or nil
					GameTooltip:Hide()
					Apply()   -- im Kampf wartet das Umbauen bis nach dem Kampf
				end)
				h.bg = h:CreateTexture(nil, "BACKGROUND", nil, 1)
				h.bg:SetAllPoints()
				h.pill = h:CreateTexture(nil, "ARTWORK")
				h.pill:SetPoint("LEFT", h, "LEFT", 6, 0)
				h.pill:SetHeight(16)
				h.label = ui.Text(h, "GameFontHighlightSmall", 12)
				h.label:SetPoint("CENTER", h.pill, "CENTER")
				h.label:SetWordWrap(false)
				-- Entfernung als Etikett rechts, im Ton "they" wie bei "Quests in der Nähe"
				h.distBg = h:CreateTexture(nil, "ARTWORK")
				h.distBg:SetHeight(16)
				h.distBg:SetPoint("RIGHT", h, "RIGHT", -6, 0)
				h.distBg:SetColorTexture(0.078, 0.157, 0.227, 1)
				h.distText = ui.Text(h, "GameFontHighlightSmall", 11)
				h.distText:SetPoint("CENTER", h.distBg, "CENTER")
				h.distText:SetTextColor(0.53, 0.8, 1)
				frame.heads[heads] = h
			end
			local tone = TONES[(heads - 1) % #TONES + 1]
			h:ClearAllPoints()
			h:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 4, -y)
			h.bg:SetColorTexture(ui.BAND[1], ui.BAND[2], ui.BAND[3], opacity)
			h.pill:SetColorTexture(tone.bg[1], tone.bg[2], tone.bg[3], 1)
			h.label:SetTextColor(tone.fg[1], tone.fg[2], tone.fg[3])
			h.label:SetText(sec.title)
			local dist = Get("showDist", true) and sec.questId and distOf[sec.questId]
			h.distBg:SetShown(dist and true or false)
			h.distText:SetShown(dist and true or false)
			if dist then
				h.distText:SetText(math.floor(dist + 0.5) .. " m")
				h.distW = h.distText:GetStringWidth() + 14
				h.distBg:SetWidth(h.distW)
			else
				h.distW = 0
			end
			-- eingeklappte Gruppen wirken gedämpft
			h.label:SetAlpha(folded and 0.55 or 1)
			h.pill:SetAlpha(folded and 0.55 or 1)
			h.sectionTitle = sec.title
			h.questId = sec.questId
			h.collapseKey = sec.collapseKey
			h:Show()
			sec.head = h
			y = y + HEAD_H + (folded and 0 or Get("headGap", 6))   -- Luft zwischen Gruppenzeile und Symbolen
		end
		if not folded then
			for i, g in ipairs(sec.items) do
				used = used + 1
				local row = GetRow(used)
				local col, line = (i - 1) % cols, math.floor((i - 1) / cols)
				row:ClearAllPoints()
				row:SetPoint("TOPLEFT", frame.content, "TOPLEFT", PAD + col * (size + gap), -(y + line * (cell + gap)))
				row:SetSize(size, size)
				row.mob, row.have, row.need = g.name, g.have, g.need
				row.quest, row.questId = g.quest, g.questId
				row.count:SetShown(showCount and g.need > 0)
				row.countBg:SetShown(compact and showCount and g.need > 0)
				row.count:ClearAllPoints()
				if compact then row.count:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -3, 3) else row.count:SetPoint("TOP", row, "BOTTOM", 0, -2) end
				row.count:SetText(g.have .. "/" .. g.need)
				if g.drop then row.count:SetTextColor(0.6, 0.8, 1) else row.count:SetTextColor(cc.r, cc.g, cc.b) end
				row.itemID = g.item
				if g.item then
					-- Questgegenstand: Symbol des Gegenstands, Klick benutzt ihn
					row.icon:SetTexture(g.icon)
					row.icon:Show()
					row.skull:Hide()
					row.model:Hide()
					row.portraitId = false
				else
					row.icon:Hide()
					if g.npc then ids[g.name] = g.npc end   -- aus QuestieDB; bleibt gespeichert
					Portrait(row, not editing and ids[g.name] or nil)
				end
				row:SetAttribute("type1", "macro")
				row:SetAttribute("macrotext1", editing and "" or (g.item and ("/use item:" .. g.item) or MacroFor(g.name, mark, aliveOnly)))
				-- Rechtsklick: ins Gruppen-/Schlachtzugsgespräch schreiben, was man braucht (zum Absprechen); allein passiert nichts
				row:SetAttribute("type2", "macro")
				row:SetAttribute("macrotext2", (editing or g.item) and "" or ChatMacro(g))
				row:Show()
			end
			local lines = math.ceil(#sec.items / cols)
			y = y + lines * cell + (lines - 1) * gap
		end
		y = y + SEC_GAP
	end
	for i = used + 1, #rows do rows[i]:Hide() end
	for i = heads + 1, #frame.heads do frame.heads[i]:Hide() end
	UpdateNear()
	Highlight()

	-- Größe: Breite nach den Symbolen, Höhe bis "Maximale Höhe", darüber scrollt der Bereich
	local w = fixedW > 0 and fixedW or math.max(2 * PAD + maxCols * size + (maxCols - 1) * gap, hide and 0 or 130)
	local contentH = math.max(4, y - SEC_GAP) + PAD
	local maxView = math.max(80, Get("maxHeight", 360) - head)
	local viewH = math.min(contentH, maxView)
	local overflow = contentH > maxView
	frame:SetWidth(w + (overflow and 8 or 0))
	frame.content:SetSize(w, contentH)
	frame.scroll:ClearAllPoints()
	frame.scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -head)
	frame.scroll:SetSize(w, viewH)
	frame.track:ClearAllPoints()
	frame.track:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -3, -(head + 2))
	frame.track:SetHeight(math.max(1, viewH - 4))
	for _, sec in ipairs(sections) do
		local h = sec.head
		if h then
			h:SetWidth(w - 8)
			local pw = math.min(h.label:GetStringWidth() + 18, w - 8 - 12 - ((h.distW or 0) > 0 and (h.distW + 8) or 0))
			h.pill:SetWidth(pw)
			h.label:SetWidth(pw - 10)
		end
	end
	frame:SetHeight(head + viewH)
	frame.hasContent = #sections > 0
	SyncShown()
	UpdateScroll()

	-- Reihenfolge der Quests merken: der Ticker baut neu auf, wenn sie sich durch Laufen ändert
	local sig = {}
	for _, g in ipairs(list) do
		if g.questId and sig[#sig] ~= g.questId then sig[#sig + 1] = g.questId end
	end
	frame.questOrder, frame.orderSig = sig, table.concat(sig, ",")

	-- Quests in der Reihenfolge des Fensters samt ihren Mobs: die Tasten (HK) beziehen sich darauf
	HK.quests = {}
	local byQuest = {}
	for _, sec in ipairs(sections) do
		for _, g in ipairs(sec.items) do
			if g.questId and not g.item then
				local q = byQuest[g.questId]
				if not q then
					q = { id = g.questId, title = g.quest, names = {} }
					byQuest[g.questId] = q
					HK.quests[#HK.quests + 1] = q
				end
				q.names[g.name] = true
			end
		end
	end
end

-- Beim Laufen ändert sich die Entfernung: alle paar Sekunden prüfen, ob die Quests anders sortiert wären, und nur dann neu
-- aufbauen (nicht im Kampf; sonst würden Symbole unter der Maus wegspringen)
C_Timer.NewTicker(2, function()
	if editing or not frame.questOrder then return end
	if not (SexyQuestHelperAPI and SexyQuestHelperAPI.QuestDistance) then return end
	local maxDist = MaxDist()
	-- ausgeblendete Quests (Entfernungsgrenze) müssen weiter geprüft werden, damit sie beim Näherkommen erscheinen
	if not frame:IsShown() and not (maxDist > 0 and frame.allQuests and #frame.allQuests > 0) then return end
	local ids, dist = {}, {}
	for _, id in ipairs((maxDist > 0 and frame.allQuests and #frame.allQuests > 0) and frame.allQuests or frame.questOrder) do
		dist[id] = SexyQuestHelperAPI.QuestDistance(id) or false
		if not (maxDist > 0 and dist[id] and dist[id] > maxDist) then ids[#ids + 1] = id end
	end
	-- Entfernung in den Etiketten der Gruppenzeilen laufend auffrischen (ohne neu aufzubauen)
	if Get("showDist", true) then
		for _, h in ipairs(frame.heads) do
			local d = h:IsShown() and h.questId and dist[h.questId]
			if d then
				h.distBg:Show()
				h.distText:Show()
				h.distText:SetText(math.floor(d + 0.5) .. " m")
				h.distW = h.distText:GetStringWidth() + 14
				h.distBg:SetWidth(h.distW)
			end
		end
	end
	-- neu aufbauen (nur außerhalb des Kampfs) nur, wenn die Sortierung sich ändern würde
	if (not Get("sortDistance", true) and maxDist <= 0) or InCombatLockdown() then return end
	local pos = {}
	for i, id in ipairs(ids) do pos[id] = i end
	if Get("sortDistance", true) then
		table.sort(ids, function(a, b)
			local da, db = dist[a], dist[b]
			if da and db and da ~= db then return da < db end
			if (da and true or false) ~= (db and true or false) then return da and true or false end
			return pos[a] < pos[b]
		end)
	end
	if table.concat(ids, ",") ~= frame.orderSig then Apply() end
end)

local timer
local function Soon()
	if timer then return end
	timer = true
	C_Timer.After(0.5, function()
		timer = nil
		Apply()
	end)
end

RebuildSoon = Soon
-- Für SexyQuestHelper.lua: Quest aus- oder eingeblendet, das Fenster neu aufbauen
if SexyQuestHelperAPI then SexyQuestHelperAPI.RefreshTargets = Soon end

-- Kreatur-ID aus Ziel oder Maus-Über merken: daraus wird das 3D-Bild des Symbols.
-- GUID und Name können "geheime" Werte sein (z. B. beim Zielwechsel per Tab): die lassen sich nicht umwandeln,
-- dann wird nichts gemerkt.
local function Learn(unit)
	local ok, guid, name = pcall(function()
		if not UnitExists(unit) or UnitIsPlayer(unit) then return end
		return Public(UnitGUID(unit)), Public(UnitName(unit))
	end)
	if not (ok and type(guid) == "string" and type(name) == "string") then return end
	local kind, _, _, _, _, id = strsplit("-", guid)
	if kind == "Creature" and tonumber(id) and Ids()[name] ~= tonumber(id) then
		Ids()[name] = tonumber(id)
		Soon()
	end
end

SLASH_SQHTARGETS1 = "/sqhtargets"
SlashCmdList["SQHTARGETS"] = function()
	local function say(text) print("|cffe8c26a[SQH]|r " .. text) end
	say(T("Quest-Aktionen", "Quest actions") .. ": " .. (Get("enabled", true) and "on" or "off") .. ", " .. tostring(GetZoneText()))
	-- jeder Schritt einzeln geschützt: ein Fehler erscheint im Chat statt still zu enden
	local ok, list = pcall(Gather, true)
	if not ok then say("Fehler beim Lesen: " .. tostring(list)); return end
	say(#list .. " " .. T("Monster gefunden", "mobs found"))
	ScanNear()
	say(T("Nähe", "Nearby") .. ": " .. (nearDebug.plates or 0) .. " " .. T("Namensschilder", "nameplates") .. ", "
		.. (nearDebug.secret or 0) .. " " .. T("geheime Namen", "secret names") .. ", " .. T("erkannt", "found") .. ": "
		.. table.concat(nearDebug.names or {}, ", ") .. " | enemy plates CVar: " .. tostring(GetCVar and GetCVar("nameplateShowEnemies"))
		.. " | " .. T("getaggt", "tagged") .. ": " .. (nearDebug.tapped or 0) .. (nearDebug.tapErr and (" | " .. nearDebug.tapErr) or ""))
	for _, g in ipairs(list) do say("  " .. g.name .. " " .. g.have .. "/" .. g.need) end
	local ok2, err = pcall(Apply)
	say(T("Fenster", "Window") .. ": " .. (ok2 and "ok" or ("Fehler: " .. tostring(err)))
		.. ", " .. (frame:IsShown() and "sichtbar" or "versteckt") .. ", " .. #rows .. " Symbole, Kampf=" .. tostring(InCombatLockdown()))
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "QUEST_LOG_UPDATE",
	"QUEST_ACCEPTED", "QUEST_REMOVED", "PLAYER_REGEN_ENABLED", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "GROUP_ROSTER_UPDATE" }) do
	ev:RegisterEvent(e)
end
ev:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_TARGET_CHANGED" then
		Learn("target")
		UnitStill("target")
		Highlight()
	elseif event == "GROUP_ROSTER_UPDATE" then
		if not InCombatLockdown() then Soon() end   -- Kanal des Rechtsklick-Makros nachziehen
	elseif event == "UPDATE_MOUSEOVER_UNIT" then
		Learn("mouseover")
		UnitStill("mouseover")
	elseif event == "PLAYER_LOGIN" then
		local db = Cfg()
		db.editMode = db.editMode or {}
		-- Profildaten fuer SexyEditMode (Einstellungen und Fensterpositionen; ohne die gelernten Orte und ausgeblendeten Quests)
		if SEM.RegisterProfile then
			SEM:RegisterProfile("SexyQuestHelper", { db = function() return SexyQuestHelperDB end,
				keys = { "cfg", "editMode", "helpMode", "nearMode", "targets", "notes", "pos", "minimap" } })
		end
		SEM:Register(frame, {
			name = "SexyQuestHelper: " .. T("Quest-Aktionen", "Quest actions"),
			category = T("Quests", "Quests"),   -- Zwischenüberschrift in der Seitenleiste des Einstellungsfensters
			addon = "SexyQuestHelper", group = "sqh", groupName = "SexyQuestHelper",
			description = T("Mobs und Questgegenstände deiner Quests als Klick-Symbole.", "Mobs and quest items of your quests as click icons."),
			db = db.editMode,
			sample = SexyQuestHelperSamples and SexyQuestHelperSamples.targets,   -- Vorschau im Einstellungsfenster: eigenes Fenster mit eigener Logik (Samples.lua)
			onEditMode = function(active)
				editing = active and true or false
				Apply()
			end,
			settings = {
				{ type = "header", name = T("Darstellung", "Look"), id = "look" },
				{ type = "check", name = T("Kopfzeile ausblenden", "Hide header"),
					get = function() return Get("hideHeader", false) end,
					set = function(v) Cfg().hideHeader = v and true or false; Apply() end },
				{ type = "check", name = T("Entfernung zeigen", "Show distance"),
					get = function() return Get("showDist", true) end,
					set = function(v) Cfg().showDist = v and true or false; Apply() end },
				{ type = "check", name = T("Bewegte 3D-Modelle statt Standbildern", "Moving 3D models instead of still pictures"),
					get = function() return Get("animatedAvatar", false) end,
					set = function(v)
						Cfg().animatedAvatar = v and true or false
						for _, row in ipairs(rows) do row.portraitId = nil end   -- Modelle neu laden, damit die Wahl gleich greift
						Apply()
					end },
				{ type = "check", name = T("Kompakter Modus", "Compact mode"),
					get = function() return Get("compact", false) end,
					set = function(v) Cfg().compact = v and true or false; Apply() end },
				{ type = "slider", name = T("Maximale Höhe", "Maximum height"), min = 120, max = 800, step = 20,
					get = function() return Get("maxHeight", 360) end,
					set = function(v) Cfg().maxHeight = v; Apply() end,
					format = function(v) return v .. " px" end },
				{ type = "check", name = T("Nach Quests gruppieren", "Group by quest"),
					get = function() return Get("groupByQuest", true) end,
					relayout = true,
					set = function(v) Cfg().groupByQuest = v and true or false; Apply() end },
				{ type = "slider", name = T("Abstand unter der Gruppenzeile", "Space below the group row"), min = 0, max = 16, step = 1,
					hidden = function() return not Get("groupByQuest", true) end,
					get = function() return Get("headGap", 6) end,
					set = function(v) Cfg().headGap = v; Apply() end,
					format = function(v) return v .. " px" end },
				{ type = "check", name = T("Nur Quests in Reichweite von „Quests in der Nähe“", "Only quests within the range of \"Quests nearby\""),
					get = function() return Get("limitRange", true) end,
					set = function(v) Cfg().limitRange = v and true or false; Apply() end },
				{ type = "slider", name = T("Maximale Symbole pro Quest", "Maximum icons per quest"), min = 2, max = 16, step = 1,
					get = function() return Get("maxPerQuest", 6) end,
					set = function(v) Cfg().maxPerQuest = v; Apply() end },
				{ type = "slider", name = T("Symbolgröße", "Icon size"), min = 28, max = 72, step = 2,
					get = function() return Get("iconSize", 28) end,
					set = function(v) Cfg().iconSize = v; Apply() end,
					format = function(v) return v .. " px" end },
				{ type = "slider", name = T("Breite", "Width"), min = 0, max = 600, step = 10,
					get = function() return Get("width", 200) end,
					set = function(v) Cfg().width = v; Apply() end,
					format = function(v) return v == 0 and T("Automatisch", "Automatic") or (v .. " px") end },
				{ type = "slider", name = T("Symbole pro Zeile", "Icons per row"), min = 2, max = 10, step = 1,
					get = function() return Get("perRow", 6) end,
					set = function(v) Cfg().perRow = v; Apply() end },
				{ type = "slider", name = T("Abstand der Symbole", "Icon spacing"), min = 0, max = 16, step = 1,
					get = function() return Get("gap", 6) end,
					set = function(v) Cfg().gap = v; Apply() end,
					format = function(v) return v .. " px" end },
				{ type = "slider", name = T("Deckkraft des Fensters", "Window opacity"), min = 30, max = 100, step = 2,
					get = function() return math.floor(Get("opacity", ui.BG[4] or 0.96) * 100 + 0.5) end,
					set = function(v) Cfg().opacity = v / 100; Apply() end,
					format = function(v) return v .. " %" end },
				{ type = "check", name = T("Zähler zeigen", "Show the counter"),
					get = function() return Get("showCount", true) end,
					set = function(v) Cfg().showCount = v and true or false; Apply() end },
				{ type = "color", name = T("Farbe des Zählers", "Counter color"),
					get = function() local c = Get("countColor", nil) or { r = 0.94, g = 0.75, b = 0.29 }; return c.r, c.g, c.b, 1 end,
					set = function(r, g, b) Cfg().countColor = { r = r, g = g, b = b }; Apply() end },
				{ type = "header", name = T("Verhalten", "Behavior"), id = "targets" },
				{ type = "check", name = T("Fenster einschalten", "Turn the window on"),
					get = function() return Get("enabled", true) end,
					set = function(v) Cfg().enabled = v and true or false; Apply() end },
				{ type = "select", name = T("In Dungeons und Schlachtzügen", "In dungeons and raids"),
					options = {
						{ value = "show", label = T("Normal anzeigen", "Show normally") },
						{ value = "mini", label = T("Kompakter Modus", "Compact mode") },
						{ value = "hide", label = T("Ausblenden", "Hide") },
					},
					get = function() return Get("instance", "show") end,
					set = function(v) Cfg().instance = v; Apply() end },
				{ type = "check", name = T("Nur lebende Monster anvisieren", "Only target living mobs"),
					get = function() return Get("aliveOnly", true) end,
					set = function(v) Cfg().aliveOnly = v and true or false; Apply() end },
				{ type = "check", name = T("Anvisiertes Monster mit Totenkopf markieren", "Mark the targeted mob with the skull"),
					get = function() return Get("markSkull", true) end,
					set = function(v) Cfg().markSkull = v and true or false; Apply() end },
				{ type = "check", name = T("Anvisiertes Monster anpingen (Blizzard-Ping)", "Ping the targeted mob (Blizzard ping)"),
					get = function() return Get("pingMark", true) end,
					set = function(v) Cfg().pingMark = v and true or false; Apply() end },
				{ type = "check", name = T("Symbole grau, solange das Monster nicht in der Nähe ist", "Gray icons while the mob is not nearby"),
					get = function() return Get("grayAway", true) end,
					set = function(v) Cfg().grayAway = v and true or false; near = {}; UpdateNear() end },
				{ type = "check", name = T("Monster in der Nähe zuerst", "Nearby mobs first"),
					get = function() return Get("sortNear", true) end,
					set = function(v) Cfg().sortNear = v and true or false; Apply() end },
				{ type = "check", name = T("Benutzbare Questgegenstände zeigen", "Show usable quest items"),
					get = function() return Get("showItems", true) end,
					set = function(v) Cfg().showItems = v and true or false; Apply() end },
				{ type = "check", name = T("Nach Entfernung sortieren", "Sort by distance"),
					get = function() return Get("sortDistance", true) end,
					set = function(v) Cfg().sortDistance = v and true or false; Apply() end },
				{ type = "check", name = T("Nur Quests dieses Gebiets", "Only quests of this zone"),
					get = function() return Get("zoneOnly", true) end,
					set = function(v) Cfg().zoneOnly = v and true or false; Apply() end },
				{ type = "header", name = "Hotkeys", id = "keys" },
				HK.Row(1), HK.Row(2), HK.Row(3), HK.Row(4), HK.Row(5),
			},
		})
		HK.Bind()
		Soon()
	elseif event == "PLAYER_REGEN_ENABLED" then
		if HK.pendingBind then HK.Bind() end
		if pending then Apply() end
	else
		Soon()
	end
end)
