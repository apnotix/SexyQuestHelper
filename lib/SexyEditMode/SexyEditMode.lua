-- SexyEditMode-1.0
--
-- Kleine Bibliothek, mit der ein Addon seine Fenster in Blizzards Edit Mode verschiebbar
-- macht und dort einen eigenen Einstellungsdialog bekommt: aufklappbare Abschnitte mit
-- Checkbox, Regler, Auswahl, Farbe, Knopf und Trennlinie. Der Dialog hat denselben Look
-- wie die Sexy-Addons (dunkelbraune Fläche, Goldrand, Titelband).
--
-- Verwendung:
--   local lib = LibStub("SexyEditMode-1.0")
--   lib:Register(frame, {
--       name = "Mein Fenster",
--       db = MeineDB.frames.fenster,     -- Tabelle für Position und Standardoptionen
--       settings = {                     -- optional, siehe unten
--           { type = "header", name = "Anzeige", id = "view" },
--           { type = "check", name = "Titel ausblenden", get = function() return x end, set = function(v) x = v end },
--           { type = "slider", name = "Breite", min = 100, max = 400, step = 5, get = ..., set = ... },
--           { type = "select", name = "Layout", options = { { value = 1, label = "A" }, ... }, get = ..., set = ... },
--           { type = "color", name = "Farbe", hasAlpha = true, get = function() return r, g, b, a end, set = function(r, g, b, a) end },
--           { type = "button", name = "Test", onClick = function() end },
--           { type = "divider", name = "Gruppe" },
--       },
--       scale = true, visibility = true, -- eingebaute Abschnitte "Position und Größe" / "Sichtbarkeit" (Standard: an)
--       group = "Name", groupName = "Titel", -- Fenster mit gleicher Gruppe teilen sich einen Dialog mit Fensterauswahl
--       category = "Beute", description = "Kurzer Text", -- Zwischenüberschrift in der Seitenleiste des Hubs und Beschreibung über den Einstellungen
--       addon = "SexyLoot",              -- gehört zu diesem Addon (siehe lib:RegisterAddon in Hub.lua): erscheint im gemeinsamen Hub
--       onMoved = function(frame) end,   -- nach dem Verschieben
--       onEditMode = function(active) end, -- Edit Mode betreten (true) oder verlassen (false)
-- hideWhenInvisible = true: "Ausblenden" und "Im Kampf ausblenden" verstecken das Fenster ganz (Hide) statt nur durchsichtig (nur für reine Container)
-- Zeilenart { type = "dynamic", build = function() return { Zeilen mit eindeutigem key } end }: Zeilen, die bei jedem Aufbau neu entstehen
-- Zeilenart { type = "edit", name = "Text", onSubmit = function(text) end }: Eingabefeld mit Knopf
-- Zeilenart { type = "select", ..., options = { { value = "Name", label = "Name", font = "Pfad zur Schrift" }, ... } }: mit `font` wird der Eintrag in dieser Schrift gezeichnet (Schriftauswahl)
-- Einstellung mit behavior = true: erscheint nur im Hub, nicht im kleinen Edit-Mode-Dialog (dort nur Visuelles; ohne Hub gilt das nicht)
-- group / groupName: zusammengehörige Fenster bekommen im Dialog Tabs (mit dem Hub-Look); sonst eine Fensterauswahl
-- lib:RegisterPage({ name, addon, category, description, settings }): Seite ohne Fenster, nur im Hub (ohne Overlay und Position)
-- Zeilenart { type = "input", name = "Text", get = function() return "aktueller Text" end, set = function(text) end, maxLetters = 80 }: Textfeld mit dem aktuellen Wert; Enter oder Verlassen des Felds speichert
-- Zeilenart { type = "buttonrow", name = "Text links", text = "Knopf rechts", onClick = function() end, onEnter = function(frame) end, onLeave = function() end }: Zeile mit Beschriftung und einem Knopf dahinter (z. B. Liste mit "Einblenden")
-- Zeilenart { type = "keybind", name = "Text", get = function() return "Strg + F" oder nil end, waiting = function() return true, wenn gerade eine Taste erwartet wird end, onClick = function() end, onClear = function() end }: Beschriftung mit Knopf, der die gewählte Taste zeigt (Klick startet die Abfrage), optional mit Löschen-Knopf
-- Zeilenart { type = "link", name = "Fenstername", frame = Fenster oder function() return Fenster end }: Verweis auf ein zugehöriges Fenster
--   })
--
-- Gespeichert wird in opts.db: x, y (BOTTOMLEFT, UIParent), scale, hidden, hideInCombat, mouseover.
-- Das Overlay ist frame.Selection (OnDragStart/OnDragStop lassen sich mit HookScript anhängen).

local MAJOR, MINOR = "SexyEditMode-1.0", 23
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

lib.entries = lib.entries or {}   -- [frame] = entry
lib.order = lib.order or {}
lib.byKey = lib.byKey or {}             -- [Schlüssel] = entry (Ziel beim Andocken)
lib.groups = lib.groups or {}           -- [Gruppe] = { entry, ... }
lib.groupCollapsed = lib.groupCollapsed or {}
lib.groupList = lib.groupList or {}
lib.groupNames = lib.groupNames or {}
lib.rowCache = lib.rowCache or {}      -- [spec] = { frame, height }

-- Look -----------------------------------------------------------------------------
local FLAT = "Interface\\Buttons\\WHITE8x8"
local BACKDROP = {
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	edgeSize = 12,
	insets = { left = 3, right = 3, top = 3, bottom = 3 },
}
local BG = { 0.08, 0.065, 0.05, 0.96 }
local EDGE = { 0.42, 0.34, 0.15, 1 }
local BAND = { 0.15, 0.12, 0.07, 0.96 }
local ROWBG = { 0.145, 0.125, 0.10, 1 }
local GOLD = { 0.91, 0.76, 0.42 }
local GREEN = { 0.184, 0.42, 0.235 }

local DIALOG_W = 320
local CONTENT_W = DIALOG_W - 24
local HEAD_H = 30
local MAX_CONTENT_H = 440
-- Maße des Dialogs; mit dem Hub (Hub.lua) breiter und im neuen Look (siehe CreateDialog)
local dlg = { w = DIALOG_W, content = CONTENT_W, head = HEAD_H, maxH = MAX_CONTENT_H }

local function Backdrop(frame, bg, edge)
	if not frame.SetBackdrop then return end
	frame:SetBackdrop(BACKDROP)
	bg = bg or BG
	edge = edge or EDGE
	frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
	frame:SetBackdropBorderColor(edge[1], edge[2], edge[3], edge[4])
end

local function NewFrame(parent, template)
	return CreateFrame("Frame", nil, parent, template or (BackdropTemplateMixin and "BackdropTemplate" or nil))
end

local function Text(parent, font, size)
	local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
	if size then
		local path, _, flags = fs:GetFont()
		fs:SetFont(path, size, flags)
	end
	return fs
end

local function FlatButton(parent, text, width, height)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(width or 100, height or 22)
	b.bg = b:CreateTexture(nil, "BACKGROUND")
	b.bg:SetAllPoints()
	b.bg:SetColorTexture(GREEN[1], GREEN[2], GREEN[3], 1)
	b.hl = b:CreateTexture(nil, "HIGHLIGHT")
	b.hl:SetAllPoints()
	b.hl:SetColorTexture(1, 1, 1, 0.22)
	b.text = Text(b, "GameFontHighlightSmall")
	b.text:SetAllPoints()
	b.text:SetText(text or "")
	b:RegisterForClicks("LeftButtonUp")
	return b
end

-- Daten und Position ---------------------------------------------------------------

local function Layoutkey()
	-- Schlüssel, unter dem EditModeExpanded die Position je Layout ablegte ("0-Modern")
	local m = _G.EditModeManagerFrame
	if m and m.GetActiveLayoutInfo then
		local ok, info = pcall(m.GetActiveLayoutInfo, m)
		if ok and type(info) == "table" and info.layoutType and info.layoutName then
			return info.layoutType .. "-" .. info.layoutName
		end
	end
end

-- Position früherer Versionen (EditModeExpanded: db.profiles[Layout].x/y) übernehmen. Der
-- Layoutname steht beim Laden des Addons oft noch nicht bereit: dann bleibt die Migration
-- offen (entry.pendingMigration) und läuft später erneut (siehe RetryMigrations).
local function MigrateOldPosition(entry, final)
	local db = entry.db
	if db.migrated then entry.pendingMigration = nil return false end
	local profiles = db.profiles
	if type(profiles) ~= "table" then
		db.migrated = true
		entry.pendingMigration = nil
		return false
	end
	local p = profiles[Layoutkey() or ""]
	if not (type(p) == "table" and p.x and p.y) and final then
		-- aktives Layout unbekannt oder ohne Eintrag: irgendein gespeichertes Layout nehmen
		-- bevorzugt ein Layout, in dem der Spieler das Fenster wirklich verschoben hat (Position
		-- weicht vom Standard ab), sonst das zuletzt sortierte (eigene Layouts stehen hinter "0-Modern")
		local moved, any = {}, {}
		for k, v in pairs(profiles) do
			if type(v) == "table" and v.x and v.y then
				any[#any + 1] = k
				if v.defaultX ~= v.x or v.defaultY ~= v.y then moved[#moved + 1] = k end
			end
		end
		local keys = #moved > 0 and moved or any
		table.sort(keys, function(x, y) return x > y end)
		p = keys[1] and profiles[keys[1]]
	end
	if type(p) == "table" and p.x and p.y then
		db.x, db.y = p.x, p.y
		db.migrated = true
		-- Die vom Addon vorab berechnete Startposition (autoSeeded) darf die übernommene nicht überschreiben.
		-- Die alten Daten (db.profiles) bleiben liegen: so geht bei einem Fehler nichts verloren.
		db.autoSeeded = nil
		entry.pendingMigration = nil
		return true
	end
	if final then
		db.migrated = true
		entry.pendingMigration = nil
	else
		entry.pendingMigration = true
	end
	return false
end

-- Andocken: Ein Fenster hängt mit festem Abstand an einer Seite eines anderen Fensters (auch eines anderen Addons) und
-- wandert mit. Gespeichert in der db des Fensters: dock = { target = Schlüssel des Ziels }, dockSide, dockAlign.
-- Die freie Position (db.x, db.y) bleibt erhalten und kommt beim Abdocken zurück.
local DOCK_GAP = 6
local DOCK = {
	BOTTOM = { START = { "TOPLEFT", "BOTTOMLEFT" }, CENTER = { "TOP", "BOTTOM" }, END = { "TOPRIGHT", "BOTTOMRIGHT" }, x = 0, y = -DOCK_GAP },
	TOP    = { START = { "BOTTOMLEFT", "TOPLEFT" }, CENTER = { "BOTTOM", "TOP" }, END = { "BOTTOMRIGHT", "TOPRIGHT" }, x = 0, y = DOCK_GAP },
	LEFT   = { START = { "TOPRIGHT", "TOPLEFT" }, CENTER = { "RIGHT", "LEFT" }, END = { "BOTTOMRIGHT", "BOTTOMLEFT" }, x = -DOCK_GAP, y = 0 },
	RIGHT  = { START = { "TOPLEFT", "TOPRIGHT" }, CENTER = { "LEFT", "RIGHT" }, END = { "BOTTOMLEFT", "BOTTOMRIGHT" }, x = DOCK_GAP, y = 0 },
}
local DOCK_SIDES = { "BOTTOM", "TOP", "LEFT", "RIGHT" }

-- Das Ziel, an dem das Fenster hängt (nil: nicht angedockt oder Ziel nicht geladen)
local function DockTarget(entry)
	local d = entry.db.dock
	local t = d and d.target and lib.byKey[d.target]
	if t and t ~= entry and t.frame then return t end
end

-- Hinge target (über Ketten) an entry? Dann entstünde ein Ring.
local function DockLeads(target, entry)
	local seen = {}
	while target and not seen[target] do
		if target == entry then return true end
		seen[target] = true
		target = DockTarget(target)
	end
	return false
end

local function DockGeom(entry)
	local g = DOCK[entry.db.dockSide or "BOTTOM"] or DOCK.BOTTOM
	local p = g[entry.db.dockAlign or "START"] or g.START
	return p[1], p[2], g.x, g.y
end

local function DockPlace(entry)
	local t = DockTarget(entry)
	if not t then return false end
	local f = entry.frame
	if InCombatLockdown() and f:IsProtected() then return true end
	local point, rel, x, y = DockGeom(entry)
	f:ClearAllPoints()
	f:SetPoint(point, t.frame, rel, x, y)
	return true
end

-- Steht das Fenster schon richtig? (sonst wird es neu gesetzt, falls das Addon den Anker verändert hat)
local function DockInPlace(entry)
	local t, f = DockTarget(entry), entry.frame
	if not t or f:GetNumPoints() ~= 1 then return false end
	local point, relTo, relPoint, x, y = f:GetPoint(1)
	local gp, grel, gx, gy = DockGeom(entry)
	return point == gp and relTo == t.frame and relPoint == grel
		and math.abs((x or 0) - gx) < 0.01 and math.abs((y or 0) - gy) < 0.01
end

local function ApplyPosition(entry)
	local db, f = entry.db, entry.frame
	if InCombatLockdown() and f:IsProtected() then return end
	if DockPlace(entry) then return end
	if not (db.x and db.y) then return end
	f:ClearAllPoints()
	f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", db.x, db.y)
end

local function SavePosition(entry)
	local f, db = entry.frame, entry.db
	local left, bottom = f:GetLeft(), f:GetBottom()
	if left and bottom then db.x, db.y = left, bottom end
end

function lib:GetPosition(frame)
	local e = self.entries[frame]
	return e and e.db.x, e and e.db.y
end

-- Position setzen und speichern (z. B. nach einer eigenen Verschiebung des Addons)
function lib:SetPosition(frame, x, y)
	local e = self.entries[frame]
	if not e then return end
	e.db.x, e.db.y = x, y
	ApplyPosition(e)
end

-- Sichtbarkeit: ausgeblendet, im Kampf ausgeblendet, nur bei Mouseover. Alles über die
-- Transparenz, damit Show/Hide des Addons nicht in die Quere kommt.
-- Läuft der Edit Mode für dieses Fenster? Mit lib.editFilter (siehe lib:ToggleEditMode) nur für die Fenster eines Addons.
local function EntryEditing(entry)
	return lib.editing and (not lib.editFilter or entry.addon == lib.editFilter) and true or false
end

local function UpdateVisibility(entry)
	if not entry.visibility then return end
	local db, f = entry.db, entry.frame
	local alpha, canHide = 1, false
	if EntryEditing(entry) then
		alpha = 1
	elseif db.hidden then
		alpha, canHide = 0, true
	elseif db.hideInCombat and (InCombatLockdown() or UnitAffectingCombat("player")) then
		alpha, canHide = 0, true
	elseif db.mouseover and not MouseIsOver(f) then
		alpha = 0   -- hier muss die Maus das Fenster noch erreichen, also nicht verstecken
	end
	local hide = entry.hideWhenInvisible and canHide
	if entry.lastAlpha ~= alpha or entry.lastHide ~= hide then
		entry.lastAlpha, entry.lastHide = alpha, hide
		f:SetAlpha(alpha)
		-- Ein nur durchsichtiges Fenster fängt weiter Mausklicks ab: ein Container, dessen Inhalt das
		-- Addon selbst zeigt und versteckt, wird darum ganz versteckt (hideWhenInvisible).
		if entry.hideWhenInvisible then f:SetShown(not hide) end
	end
end

local function ApplyScale(entry)
	local db, f = entry.db, entry.frame
	local scale = db.scale or 1
	if math.abs(f:GetScale() - scale) < 0.001 then return end
	-- sichtbare Position halten: Offsets sind in der Skalierung des Fensters angegeben
	local left, bottom = f:GetLeft(), f:GetBottom()
	local old = f:GetScale()
	f:SetScale(scale)
	if left and bottom and db.x and db.y and not DockTarget(entry) then
		db.x, db.y = left * old / scale, bottom * old / scale
		ApplyPosition(entry)
	end
end

-- Overlay (Auswahl im Edit Mode) ------------------------------------------------------

local function UpdateOverlayLook(entry)
	local o = entry.overlay
	if not o.SetBackdropColor then return end
	if entry == lib.selected then
		o:SetBackdropColor(0.91, 0.76, 0.42, 0.30)
		o:SetBackdropBorderColor(1, 0.9, 0.5, 1)
	else
		o:SetBackdropColor(0.91, 0.76, 0.42, 0.14)
		o:SetBackdropBorderColor(0.91, 0.76, 0.42, 0.8)
	end
end

local function CreateOverlay(entry)
	local f = entry.frame
	local o = CreateFrame("Frame", nil, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	o:SetFrameStrata("DIALOG")
	o:SetFrameLevel(20)
	o:SetPoint("TOPLEFT", f, "TOPLEFT", -2, 2)
	o:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 2, -2)
	if o.SetBackdrop then
		o:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
	end
	o.label = Text(o, "GameFontNormalSmall")
	o.label:SetPoint("TOPLEFT", 5, -4)
	o.label:SetJustifyH("LEFT")
	o.label:SetText(entry.name)
	o:EnableMouse(true)
	o:RegisterForDrag("LeftButton")
	o:Hide()

	o:SetScript("OnMouseDown", function() lib:Select(entry) end)
	o:SetScript("OnDragStart", function()
		if InCombatLockdown() then return end
		lib:Select(entry)
		f:SetMovable(true)
		f:StartMoving()
		entry.moving = true
	end)
	o:SetScript("OnDragStop", function()
		if not entry.moving then return end
		entry.moving = nil
		f:StopMovingOrSizing()
		SavePosition(entry)
		entry.db.dock = nil   -- selbst verschoben: abgedockt
		ApplyPosition(entry)
		if entry.onMoved then entry.onMoved(f) end
		lib:RefreshDialog()
	end)
	-- Pfeiltasten verschieben um 1, mit Umschalt um 10 Pixel
	o:EnableKeyboard(false)
	f.Selection = o
	entry.overlay = o
	UpdateOverlayLook(entry)
end

-- Dialog ---------------------------------------------------------------------------

local Dialog = {}
lib.Dialog = Dialog

local function Collapsed(entry, id, default)
	entry.collapsed = entry.collapsed or {}
	local v = entry.collapsed[id]
	if v == nil then return default and true or false end
	return v
end

-- Reihen: jede Art liefert beim Aufbau { frame, height } und ein :Update() zum Auffrischen

local ROWS = {}

function ROWS.header(parent, spec, entry, rebuild)
	local b = CreateFrame("Button", nil, parent)
	b.bg = b:CreateTexture(nil, "BACKGROUND")
	b.bg:SetAllPoints()
	b.bg:SetColorTexture(BAND[1], BAND[2], BAND[3], 1)
	b.sign = Text(b, "GameFontNormal")
	b.sign:SetPoint("LEFT", 8, 0)
	b.label = Text(b, "GameFontNormal")
	b.label:SetPoint("LEFT", 24, 0)
	b.label:SetText(spec.name or "")
	b.hl = b:CreateTexture(nil, "HIGHLIGHT")
	b.hl:SetAllPoints()
	b.hl:SetColorTexture(1, 1, 1, 0.08)
	local id = spec.id or spec.name
	local function Refresh()
		b.sign:SetText(Collapsed(entry, id, spec.collapsed) and "+" or "-")
	end
	b:SetScript("OnClick", function()
		entry.collapsed[id] = not Collapsed(entry, id, spec.collapsed)
		rebuild()
	end)
	b.Update = Refresh
	Refresh()
	return b, 26
end

function ROWS.divider(parent, spec)
	local d = CreateFrame("Frame", nil, parent)
	d.line = d:CreateTexture(nil, "ARTWORK")
	d.line:SetColorTexture(0.42, 0.34, 0.15, 0.7)
	d.line:SetHeight(1)
	if spec.name and spec.name ~= "" then
		d.label = Text(d, "GameFontHighlightSmall")
		d.label:SetPoint("LEFT", 6, 0)
		d.label:SetText(spec.name)
		d.label:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
		d.line:SetPoint("LEFT", d.label, "RIGHT", 8, 0)
		d.line:SetPoint("RIGHT", -6, 0)
	else
		d.line:SetPoint("LEFT", 6, 0)
		d.line:SetPoint("RIGHT", -6, 0)
	end
	return d, 20
end

function ROWS.check(parent, spec)
	local row = CreateFrame("Button", nil, parent)
	row.box = row:CreateTexture(nil, "ARTWORK")
	row.box:SetSize(16, 16)
	row.box:SetPoint("LEFT", 8, 0)
	row.box:SetColorTexture(EDGE[1], EDGE[2], EDGE[3], 1)
	row.inner = row:CreateTexture(nil, "OVERLAY")
	row.inner:SetPoint("TOPLEFT", row.box, "TOPLEFT", 1, -1)
	row.inner:SetPoint("BOTTOMRIGHT", row.box, "BOTTOMRIGHT", -1, 1)
	row.inner:SetColorTexture(0.06, 0.05, 0.04, 1)
	row.check = row:CreateTexture(nil, "OVERLAY", nil, 2)
	row.check:SetPoint("TOPLEFT", row.box, "TOPLEFT", 3, -3)
	row.check:SetPoint("BOTTOMRIGHT", row.box, "BOTTOMRIGHT", -3, 3)
	row.check:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
	row.label = Text(row, "GameFontHighlightSmall")
	row.label:SetPoint("LEFT", row.box, "RIGHT", 8, 0)
	row.label:SetPoint("RIGHT", -8, 0)
	row.label:SetJustifyH("LEFT")
	row.label:SetText(spec.name or "")
	row.hl = row:CreateTexture(nil, "HIGHLIGHT")
	row.hl:SetAllPoints()
	row.hl:SetColorTexture(1, 1, 1, 0.06)
	function row:Update()
		self.check:SetShown(spec.get() and true or false)
	end
	row:SetScript("OnClick", function(self)
		spec.set(not spec.get())
		lib:RefreshDialog()
	end)
	if spec.tooltip then
		row:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(spec.tooltip, 1, 1, 1, 1, true)
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", GameTooltip_Hide)
	end
	row:Update()
	return row, 24
end

local function Round(value, step)
	if step and step > 0 then return math.floor(value / step + 0.5) * step end
	return value
end

function ROWS.slider(parent, spec)
	local row = CreateFrame("Frame", nil, parent)
	row.label = Text(row, "GameFontHighlightSmall")
	row.label:SetPoint("TOPLEFT", 8, -4)
	row.label:SetText(spec.name or "")
	row.value = Text(row, "GameFontHighlightSmall")
	row.value:SetPoint("TOPRIGHT", -8, -4)
	row.value:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
	local s = CreateFrame("Slider", nil, row)
	s:SetOrientation("HORIZONTAL")
	s:SetPoint("TOPLEFT", 10, -22)
	s:SetPoint("TOPRIGHT", -10, -22)
	s:SetHeight(14)
	local track = s:CreateTexture(nil, "BACKGROUND")
	track:SetPoint("LEFT")
	track:SetPoint("RIGHT")
	track:SetHeight(4)
	track:SetColorTexture(0, 0, 0, 0.6)
	s:SetThumbTexture(FLAT)
	local thumb = s:GetThumbTexture()
	thumb:SetSize(8, 14)
	thumb:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
	s:SetMinMaxValues(spec.min, spec.max)
	s:SetValueStep(spec.step or 1)
	if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
	local fmt = spec.format or function(v)
		if spec.step and spec.step < 1 then return string.format("%.2f", v) end
		return tostring(math.floor(v + 0.5))
	end
	local updating = false
	function row:Update()
		local v = spec.get() or spec.min
		updating = true
		s:SetValue(v)
		updating = false
		self.value:SetText(fmt(v))
	end
	s:SetScript("OnValueChanged", function(_, v)
		if updating then return end
		v = Round(v, spec.step)
		row.value:SetText(fmt(v))
		spec.set(v)
	end)
	row:Update()
	return row, 40
end

-- Schreibt den Text einer Auswahl in der Schrift der Option (option.font = Dateipfad), sonst in der Standardschrift
local function ApplyOptionFont(fs, option, object, size)
	if option and option.font then
		local ok = fs:SetFont(option.font, size or 12, "")
		if ok ~= false then return end
	end
	fs:SetFontObject(object)
end

-- Auswahlliste: ein Knopf, darunter eine scrollbare Liste (kein Blizzard-Dropdown)
local ITEM_H, MENU_ROWS = 20, 12

local function CloseMenu()
	if lib.menu then
		lib.menu:Hide()
		lib.menuCatcher:Hide()
	end
end

local function EnsureMenu()
	if lib.menu then return lib.menu end
	local catcher = CreateFrame("Frame", nil, UIParent)
	catcher:SetFrameStrata("FULLSCREEN_DIALOG")
	catcher:SetFrameLevel(150)
	catcher:SetAllPoints(UIParent)
	catcher:EnableMouse(true)
	catcher:SetScript("OnMouseDown", CloseMenu)
	catcher:Hide()
	lib.menuCatcher = catcher

	local m = NewFrame(UIParent)
	m:SetFrameStrata("FULLSCREEN_DIALOG")
	m:SetFrameLevel(160)
	Backdrop(m)
	m:EnableMouse(true)
	m:EnableMouseWheel(true)
	m:Hide()
	m.buttons = {}
	for i = 1, MENU_ROWS do
		local b = CreateFrame("Button", nil, m)
		b:SetHeight(ITEM_H)
		b:SetPoint("TOPLEFT", 6, -6 - (i - 1) * ITEM_H)
		b:SetPoint("TOPRIGHT", -6, -6 - (i - 1) * ITEM_H)
		b.hl = b:CreateTexture(nil, "HIGHLIGHT")
		b.hl:SetAllPoints()
		b.hl:SetColorTexture(1, 1, 1, 0.12)
		b.sel = b:CreateTexture(nil, "BACKGROUND")
		b.sel:SetAllPoints()
		b.sel:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.18)
		b.text = Text(b, "GameFontHighlightSmall")
		b.text:SetPoint("LEFT", 6, 0)
		b.text:SetPoint("RIGHT", -6, 0)
		b.text:SetJustifyH("LEFT")
		b.text:SetWordWrap(false)
		b:SetScript("OnClick", function(self)
			local o = self.option
			if not o then return end
			CloseMenu()
			if m.onPick then m.onPick(o) end
		end)
		m.buttons[i] = b
	end
	function m:Fill()
		local list, offset = self.list, self.offset
		for i, b in ipairs(self.buttons) do
			local o = list[offset + i]
			b.option = o
			if o then
				b.text:SetText(o.label or tostring(o.value))
				ApplyOptionFont(b.text, o, "GameFontHighlightSmall", 12)
				b.sel:SetShown(self.current ~= nil and o.value == self.current)
				b:Show()
			else
				b:Hide()
			end
		end
	end
	m:SetScript("OnMouseWheel", function(self, delta)
		local maxOffset = math.max(0, #self.list - MENU_ROWS)
		self.offset = math.max(0, math.min(maxOffset, self.offset - delta * 3))
		self:Fill()
	end)
	lib.menu = m
	return m
end

-- Öffnet die Auswahlliste einer select-Zeile unter dem Knopf b (Edit-Mode-Dialog und Hub)
local function OpenSelectMenu(b, spec)
	local m = EnsureMenu()
	if m:IsShown() then CloseMenu() return end
	local o = spec.options
	if type(o) == "function" then o = o() end
	local list = o or {}
	m.list, m.current, m.offset = list, spec.get(), 0
	-- zur aktuellen Auswahl scrollen
	for i, opt in ipairs(list) do
		if opt.value == m.current then m.offset = math.max(0, math.min(i - 1, #list - MENU_ROWS)) break end
	end
	m.onPick = function(opt)
		spec.set(opt.value)
		lib:RefreshDialog()
	end
	local shown = math.min(#list, MENU_ROWS)
	m.probe = m.probe or m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	m.probe:SetAlpha(0)
	local widest = 0
	for _, opt in ipairs(list) do
		m.probe:SetText(opt.label or tostring(opt.value))
		widest = math.max(widest, m.probe:GetStringWidth())
	end
	m:SetSize(math.min(420, math.max(b:GetWidth(), 140, widest + 28)), 12 + shown * ITEM_H)
	m:ClearAllPoints()
	m:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, -2)
	for i, btn in ipairs(m.buttons) do btn:SetShown(i <= shown) end
	m:Fill()
	lib.menuCatcher:Show()
	m:Show()
end

function ROWS.select(parent, spec)
	local row = CreateFrame("Frame", nil, parent)
	row.label = Text(row, "GameFontHighlightSmall")
	row.label:SetPoint("LEFT", 8, 0)
	row.label:SetWidth(110)
	row.label:SetJustifyH("LEFT")
	row.label:SetText(spec.name or "")
	local b = CreateFrame("Button", nil, row)
	b:SetPoint("LEFT", row.label, "RIGHT", 4, 0)
	b:SetPoint("RIGHT", -8, 0)
	b:SetHeight(22)
	b.bg = b:CreateTexture(nil, "BACKGROUND")
	b.bg:SetAllPoints()
	b.bg:SetColorTexture(0.06, 0.05, 0.04, 1)
	b.edge = b:CreateTexture(nil, "BORDER")
	b.edge:SetPoint("TOPLEFT", -1, 1)
	b.edge:SetPoint("BOTTOMRIGHT", 1, -1)
	b.edge:SetColorTexture(EDGE[1], EDGE[2], EDGE[3], 1)
	b.hl = b:CreateTexture(nil, "HIGHLIGHT")
	b.hl:SetAllPoints()
	b.hl:SetColorTexture(1, 1, 1, 0.1)
	b.text = Text(b, "GameFontHighlightSmall")
	b.text:SetPoint("LEFT", 6, 0)
	b.text:SetPoint("RIGHT", -16, 0)
	b.text:SetJustifyH("LEFT")
	b.text:SetWordWrap(false)
	b.arrow = Text(b, "GameFontNormalSmall")
	b.arrow:SetPoint("RIGHT", -5, 0)
	b.arrow:SetText("v")
	row.button = b
	local function Options()
		local o = spec.options
		if type(o) == "function" then o = o() end
		return o or {}
	end
	function row:Update()
		local current = spec.get()
		local label, shown = tostring(current), nil
		for _, o in ipairs(Options()) do
			if o.value == current then label, shown = o.label or tostring(o.value), o break end
		end
		b.text:SetText(label)
		ApplyOptionFont(b.text, shown, "GameFontHighlightSmall", 11)
	end
	b:SetScript("OnClick", function(self) OpenSelectMenu(b, spec) end)
	row:Update()
	return row, 30
end

function ROWS.color(parent, spec)
	local row = CreateFrame("Frame", nil, parent)
	row.label = Text(row, "GameFontHighlightSmall")
	row.label:SetPoint("LEFT", 8, 0)
	row.label:SetText(spec.name or "")
	local b = CreateFrame("Button", nil, row)
	b:SetSize(36, 18)
	b:SetPoint("RIGHT", -8, 0)
	b.edge = b:CreateTexture(nil, "BACKGROUND")
	b.edge:SetPoint("TOPLEFT", -1, 1)
	b.edge:SetPoint("BOTTOMRIGHT", 1, -1)
	b.edge:SetColorTexture(EDGE[1], EDGE[2], EDGE[3], 1)
	b.swatch = b:CreateTexture(nil, "ARTWORK")
	b.swatch:SetAllPoints()
	function row:Update()
		local r, g, bl = spec.get()
		b.swatch:SetColorTexture(r or 1, g or 1, bl or 1, 1)
	end
	b:SetScript("OnClick", function()
		local r, g, bl, a = spec.get()
		local function Apply()
			local nr, ng, nb = ColorPickerFrame:GetColorRGB()
			local na = spec.hasAlpha and ColorPickerFrame:GetColorAlpha() or 1
			spec.set(nr, ng, nb, na)
			lib:RefreshDialog()
		end
		ColorPickerFrame:SetupColorPickerAndShow({
			r = r or 1, g = g or 1, b = bl or 1, opacity = a or 1, hasOpacity = spec.hasAlpha and true or false,
			swatchFunc = Apply, opacityFunc = Apply,
			cancelFunc = function()
				spec.set(r or 1, g or 1, bl or 1, a or 1)
				lib:RefreshDialog()
			end,
		})
	end)
	row:Update()
	return row, 26
end

-- Verweis auf ein zugehöriges Fenster: Klick wählt es aus und zeigt dessen Einstellungen.
-- spec.frame ist das Fenster oder eine Funktion, die es liefert (es muss nicht schon angemeldet sein).
function ROWS.link(parent, spec)
	local row = CreateFrame("Frame", nil, parent)
	local b = CreateFrame("Button", nil, row)
	b:SetPoint("TOPLEFT", 8, -2)
	b:SetPoint("TOPRIGHT", -8, -2)
	b:SetHeight(24)
	-- Fläche wie die Abschnittsköpfe (BAND) mit schmalem Rand, goldene Schrift und Pfeil rechts:
	-- unterscheidet sich von Schaltern (grün) und Auswahllisten
	b.edge = b:CreateTexture(nil, "BACKGROUND")
	b.edge:SetPoint("TOPLEFT", -1, 1)
	b.edge:SetPoint("BOTTOMRIGHT", 1, -1)
	b.edge:SetColorTexture(EDGE[1], EDGE[2], EDGE[3], 1)
	b.bg = b:CreateTexture(nil, "BORDER")
	b.bg:SetAllPoints()
	b.bg:SetColorTexture(BAND[1], BAND[2], BAND[3], 1)
	b.hl = b:CreateTexture(nil, "HIGHLIGHT")
	b.hl:SetAllPoints()
	b.hl:SetColorTexture(1, 1, 1, 0.08)
	b.text = Text(b, "GameFontNormalSmall")
	b.text:SetPoint("LEFT", 8, 0)
	b.text:SetText((spec.name or ""))
	b.arrow = Text(b, "GameFontNormal")
	b.arrow:SetPoint("RIGHT", -8, 0)
	b.arrow:SetText(">>")
	local function Target()
		local f = spec.frame
		if type(f) == "function" then f = f() end
		return f and lib.entries[f]
	end
	b:SetScript("OnClick", function()
		local e = Target()
		if e then lib:Navigate(e) end
	end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(string.format(lib.L.openSettings, spec.name or ""))
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	function row:Update() end
	return row, 30
end

-- Textfeld mit aktuellem Wert: Enter oder Verlassen des Felds übernimmt ihn, Esc verwirft
function ROWS.input(parent, spec)
	local row = CreateFrame("Frame", nil, parent)
	row.label = Text(row, "GameFontHighlightSmall")
	row.label:SetPoint("TOPLEFT", 8, -2)
	row.label:SetText(spec.name or "")
	local box = CreateFrame("EditBox", nil, row)
	box:SetAutoFocus(false)
	box:SetFontObject("GameFontHighlightSmall")
	box:SetHeight(20)
	box:SetPoint("TOPLEFT", 8, -18)
	box:SetPoint("TOPRIGHT", -8, -18)
	box:SetTextInsets(5, 5, 0, 0)
	box:SetMaxLetters(spec.maxLetters or 120)
	box.edge = box:CreateTexture(nil, "BACKGROUND")
	box.edge:SetPoint("TOPLEFT", -1, 1)
	box.edge:SetPoint("BOTTOMRIGHT", 1, -1)
	box.edge:SetColorTexture(EDGE[1], EDGE[2], EDGE[3], 1)
	box.bg = box:CreateTexture(nil, "BORDER")
	box.bg:SetAllPoints()
	box.bg:SetColorTexture(0.06, 0.05, 0.04, 1)
	local function Commit()
		spec.set(box:GetText() or "")
		lib:RefreshDialog()
	end
	box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	box:SetScript("OnEscapePressed", function(self) self.cancel = true; self:ClearFocus() end)
	box:SetScript("OnEditFocusLost", function(self)
		if self.cancel then self.cancel = nil else Commit() end
		row:Update()
	end)
	function row:Update()
		if not box:HasFocus() then box:SetText(spec.get() or "") end
	end
	row:Update()
	return row, 46
end

-- Zeile mit Beschriftung links und einem Knopf rechts
function ROWS.buttonrow(parent, spec)
	local row = CreateFrame("Frame", nil, parent)
	local b = FlatButton(row, spec.text or "", 70, 20)
	b:SetPoint("RIGHT", -8, 0)
	b:SetScript("OnClick", function()
		if spec.onClick then spec.onClick() end
		lib:RefreshDialog()
	end)
	row.label = Text(row, "GameFontHighlightSmall")
	row.label:SetPoint("LEFT", 8, 0)
	row.label:SetPoint("RIGHT", b, "LEFT", -8, 0)
	row.label:SetJustifyH("LEFT")
	row.label:SetWordWrap(false)
	row.label:SetText(spec.name or "")
	-- Mouseover: spec.onEnter(frame) zeigt z. B. einen Tooltip, spec.onLeave() räumt ihn weg (Standard: GameTooltip ausblenden)
	if spec.onEnter then
		row:EnableMouse(true)
		row:SetScript("OnEnter", function(self) spec.onEnter(self) end)
		row:SetScript("OnLeave", function()
			if spec.onLeave then spec.onLeave() else GameTooltip:Hide() end
		end)
	end
	function row:Update() end
	return row, 26
end

-- Tastenwahl: Beschriftung, darunter ein Knopf mit der gewählten Taste (Klick startet die Abfrage),
-- daneben optional ein Knopf zum Löschen
function ROWS.keybind(parent, spec)
	local row = CreateFrame("Frame", nil, parent)
	row.label = Text(row, "GameFontHighlightSmall")
	row.label:SetPoint("TOPLEFT", 8, -2)
	row.label:SetText(spec.name or "")
	local b = CreateFrame("Button", nil, row)
	b:SetHeight(22)
	b:SetPoint("TOPLEFT", 8, -18)
	b:SetPoint("TOPRIGHT", spec.onClear and -40 or -8, -18)
	b.edge = b:CreateTexture(nil, "BACKGROUND")
	b.edge:SetPoint("TOPLEFT", -1, 1)
	b.edge:SetPoint("BOTTOMRIGHT", 1, -1)
	b.edge:SetColorTexture(EDGE[1], EDGE[2], EDGE[3], 1)
	b.bg = b:CreateTexture(nil, "BORDER")
	b.bg:SetAllPoints()
	b.bg:SetColorTexture(0.06, 0.05, 0.04, 1)
	b.hl = b:CreateTexture(nil, "HIGHLIGHT")
	b.hl:SetAllPoints()
	b.hl:SetColorTexture(1, 1, 1, 0.1)
	b.text = Text(b, "GameFontHighlightSmall")
	b.text:SetPoint("CENTER")
	b:SetScript("OnClick", function()
		if spec.onClick then spec.onClick() end
		lib:RefreshDialog()
	end)
	if spec.onClear then
		local x = FlatButton(row, "X", 24, 22)
		x:SetPoint("LEFT", b, "RIGHT", 6, 0)
		x:SetScript("OnClick", function()
			spec.onClear()
			lib:RefreshDialog()
		end)
	end
	function row:Update()
		local waiting = spec.waiting and spec.waiting()
		local key = spec.get and spec.get()
		if waiting then
			b.text:SetText(lib.L.pressKey)
			b.text:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
		elseif key and key ~= "" then
			b.text:SetText(key)
			b.text:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
		else
			b.text:SetText(lib.L.unbound)
			b.text:SetTextColor(0.62, 0.58, 0.5)
		end
	end
	row:Update()
	return row, 46
end

-- Eingabefeld mit Knopf: spec.onSubmit(text) bekommt den eingegebenen Text
function ROWS.edit(parent, spec)
	local row = CreateFrame("Frame", nil, parent)
	row.label = Text(row, "GameFontHighlightSmall")
	row.label:SetPoint("TOPLEFT", 8, -2)
	row.label:SetText(spec.name or "")
	local box = CreateFrame("EditBox", nil, row)
	box:SetAutoFocus(false)
	box:SetFontObject("GameFontHighlightSmall")
	box:SetHeight(20)
	box:SetPoint("TOPLEFT", 8, -18)
	box:SetPoint("TOPRIGHT", -52, -18)
	box:SetTextInsets(5, 5, 0, 0)
	box:SetMaxLetters(80)
	box.edge = box:CreateTexture(nil, "BACKGROUND")
	box.edge:SetPoint("TOPLEFT", -1, 1)
	box.edge:SetPoint("BOTTOMRIGHT", 1, -1)
	box.edge:SetColorTexture(EDGE[1], EDGE[2], EDGE[3], 1)
	box.bg = box:CreateTexture(nil, "BORDER")
	box.bg:SetAllPoints()
	box.bg:SetColorTexture(0.06, 0.05, 0.04, 1)
	local add = FlatButton(row, "+", 36, 20)
	add:SetPoint("LEFT", box, "RIGHT", 8, 0)
	local function submit()
		local text = (box:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
		box:ClearFocus()
		if text ~= "" and spec.onSubmit then
			box:SetText("")
			spec.onSubmit(text)
			lib:RebuildDialog()
		end
	end
	box:SetScript("OnEnterPressed", submit)
	box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	add:SetScript("OnClick", submit)
	function row:Update() end
	return row, 46
end

function ROWS.button(parent, spec)
	local row = CreateFrame("Frame", nil, parent)
	local b = FlatButton(row, spec.name, 100, 22)
	b:SetPoint("TOPLEFT", 8, -2)
	b:SetPoint("TOPRIGHT", -8, -2)
	b:SetScript("OnClick", function()
		if spec.onClick then spec.onClick() end
		lib:RefreshDialog()
	end)
	function row:Update() end
	return row, 28
end

-- X und Y der Position als Zahlenfelder
function ROWS.position(parent, spec, entry)
	local row = CreateFrame("Frame", nil, parent)
	row.boxes = {}
	local function Make(label, key, anchorX)
		local fs = Text(row, "GameFontHighlightSmall")
		fs:SetPoint("LEFT", anchorX, 0)
		fs:SetText(label)
		local e = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
		e:SetSize(70, 20)
		e:SetPoint("LEFT", fs, "RIGHT", 8, 0)
		e:SetAutoFocus(false)
		e:SetJustifyH("CENTER")
		e:SetScript("OnEnterPressed", function(self)
			local v = tonumber(self:GetText())
			self:ClearFocus()
			if v then
				entry.db[key] = v
				ApplyPosition(entry)
				if entry.onMoved then entry.onMoved(entry.frame) end
			end
			lib:RefreshDialog()
		end)
		e:SetScript("OnEscapePressed", function(self) self:ClearFocus() lib:RefreshDialog() end)
		row.boxes[key] = e
	end
	Make("X", "x", 12)
	Make("Y", "y", 130)
	function row:Update()
		local x, y = entry.db.x, entry.db.y
		if not (x and y) then
			x, y = entry.frame:GetLeft(), entry.frame:GetBottom()
		end
		if not self.boxes.x:HasFocus() then self.boxes.x:SetText(x and string.format("%d", x + 0.5) or "") end
		if not self.boxes.y:HasFocus() then self.boxes.y:SetText(y and string.format("%d", y + 0.5) or "") end
	end
	row:Update()
	return row, 28
end

-- Eingebaute Abschnitte, hinter den Einstellungen des Addons
local function BuiltinSpecs(entry)
	local db = entry.db
	local specs = {}
	if entry.scale then
		specs[#specs + 1] = { type = "header", name = lib.L.position, id = "_pos", collapsed = true }
		specs[#specs + 1] = { type = "position" }
		specs[#specs + 1] = {
			type = "slider", name = lib.L.scale, min = 50, max = 200, step = 5,
			get = function() return math.floor((db.scale or 1) * 100 + 0.5) end,
			set = function(v) db.scale = v / 100; ApplyScale(entry) end,
			format = function(v) return v .. " %" end,
		}
	end
	if entry.dock then
		local function Refresh() lib:RefreshDialog() end
		specs[#specs + 1] = { type = "header", name = lib.L.dock, id = "_dock", collapsed = true }
		specs[#specs + 1] = { type = "select", name = lib.L.dockTo,
			options = function()
				local list = { { value = "", label = lib.L.dockNone } }
				for _, e in ipairs(lib.order) do
					if not e.page and e ~= entry and e.key and not DockLeads(e, entry) then
						list[#list + 1] = { value = e.key, label = e.name }
					end
				end
				return list
			end,
			get = function() local t = DockTarget(entry); return t and t.key or "" end,
			set = function(v)
				if not v or v == "" then
					db.dock = nil
					ApplyPosition(entry)
				else
					if not db.dock then SavePosition(entry) end   -- freie Position merken
					db.dock = { target = v }
					DockPlace(entry)
				end
				Refresh()
			end }
		specs[#specs + 1] = { type = "select", name = lib.L.dockSide,
			options = function()
				local names = { BOTTOM = lib.L.below, TOP = lib.L.above, LEFT = lib.L.leftOf, RIGHT = lib.L.rightOf }
				local list = {}
				for _, side in ipairs(DOCK_SIDES) do list[#list + 1] = { value = side, label = names[side] } end
				return list
			end,
			get = function() return db.dockSide or "BOTTOM" end,
			set = function(v) db.dockSide = v; DockPlace(entry); Refresh() end }
		specs[#specs + 1] = { type = "select", name = lib.L.dockAlign,
			options = function()
				local side = db.dockSide or "BOTTOM"
				local horizontal = side == "BOTTOM" or side == "TOP"
				return {
					{ value = "START", label = horizontal and lib.L.edgeLeft or lib.L.edgeTop },
					{ value = "CENTER", label = lib.L.centered },
					{ value = "END", label = horizontal and lib.L.edgeRight or lib.L.edgeBottom },
				}
			end,
			get = function() return db.dockAlign or "START" end,
			set = function(v) db.dockAlign = v; DockPlace(entry); Refresh() end }
	end
	if entry.visibility then
		specs[#specs + 1] = { type = "header", name = lib.L.visibility, id = "_vis", collapsed = true }
		specs[#specs + 1] = { type = "check", name = lib.L.hidden, get = function() return db.hidden end,
			set = function(v) db.hidden = v and true or false; UpdateVisibility(entry) end }
		specs[#specs + 1] = { type = "check", name = lib.L.hideInCombat, get = function() return db.hideInCombat end,
			set = function(v) db.hideInCombat = v and true or false; UpdateVisibility(entry) end }
		specs[#specs + 1] = { type = "check", name = lib.L.mouseover, get = function() return db.mouseover end,
			set = function(v) db.mouseover = v and true or false; UpdateVisibility(entry) end }
	end
	return specs
end

-- Texte des Dialogs (Deutsch auf deutschen Clients, sonst Englisch)
local de = GetLocale() == "deDE"
lib.L = {
	position = de and "Position und Größe" or "Position and size",
	scale = de and "Größe" or "Size",
	visibility = de and "Sichtbarkeit" or "Visibility",
	hidden = de and "Ausblenden" or "Hide",
	hideInCombat = de and "Im Kampf ausblenden" or "Hide in combat",
	mouseover = de and "Nur bei Mouseover anzeigen" or "Show only on mouseover",
	allWindows = de and "Alle Fenster" or "All windows",
	dock = de and "Andocken" or "Docking",
	dockTo = de and "Andocken an" or "Dock to",
	dockNone = de and "Nicht angedockt" or "Not docked",
	dockSide = de and "Seite" or "Side",
	dockAlign = de and "Ausrichtung" or "Alignment",
	below = de and "Unten" or "Below",
	above = de and "Oben" or "Above",
	leftOf = de and "Links" or "Left",
	rightOf = de and "Rechts" or "Right",
	edgeLeft = de and "Links bündig" or "Left edge",
	edgeRight = de and "Rechts bündig" or "Right edge",
	edgeTop = de and "Oben bündig" or "Top edge",
	edgeBottom = de and "Unten bündig" or "Bottom edge",
	centered = de and "Zentriert" or "Centered",
	unbound = de and "Nicht belegt" or "Not set",
	pressKey = de and "Taste drücken …" or "Press a key …",
	openSettings = de and "Einstellungen von %s öffnen" or "Open settings of %s",
}

local function CreateDialog()
	-- Ist der Hub da (Addon SexyEditMode), bekommt der Dialog denselben Look wie das Einstellungsfenster
	local style = lib.HubStyle
	if style then dlg.w, dlg.content, dlg.head, dlg.maxH = 580, 580 - 28, 40, 520 end
	local d = NewFrame(UIParent)
	d:SetSize(dlg.w, 200)
	d:SetFrameStrata("FULLSCREEN_DIALOG")   -- über Blizzards Edit-Mode-Fenster samt X-Knopf
	d:SetFrameLevel(100)
	d:SetClampedToScreen(true)
	d:SetMovable(true)
	d:EnableMouse(true)
	d:RegisterForDrag("LeftButton")
	d:SetScript("OnDragStart", d.StartMoving)
	d:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local l, b = self:GetLeft(), self:GetBottom()
		lib.dialogPos = { l, b }
	end)
	Backdrop(d, style and style.C.bg, style and style.C.edge)
	d:Hide()

	local band = style and style.C.band or BAND
	d.band = d:CreateTexture(nil, "BACKGROUND", nil, 1)
	d.band:SetPoint("TOPLEFT", 3, -3)
	d.band:SetPoint("TOPRIGHT", -3, -3)
	d.band:SetHeight(dlg.head - 3)
	d.band:SetColorTexture(band[1], band[2], band[3], band[4] or 1)
	if style then
		local line = d:CreateTexture(nil, "ARTWORK")
		line:SetColorTexture(style.C.edge[1], style.C.edge[2], style.C.edge[3], 1)
		line:SetPoint("TOPLEFT", d.band, "BOTTOMLEFT")
		line:SetPoint("TOPRIGHT", d.band, "BOTTOMRIGHT")
		line:SetHeight(1)
	end
	d.title = Text(d, "GameFontNormalLarge", style and 18 or nil)
	d.title:SetPoint("LEFT", d.band, "LEFT", 14, 0)
	d.title:SetPoint("RIGHT", d.band, "RIGHT", -34, 0)
	d.title:SetJustifyH("LEFT")
	local tc = style and style.C.title or GOLD
	d.title:SetTextColor(tc[1], tc[2], tc[3])
	local close = CreateFrame("Button", nil, d, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 1, 1)
	close:SetScale(0.8)
	close:SetScript("OnClick", function() lib:Select(nil) end)

	d.scroll = CreateFrame("ScrollFrame", nil, d)
	d.scroll:SetPoint("TOPLEFT", 14, -dlg.head - 8)
	d.scroll:SetWidth(dlg.content)
	d.content = CreateFrame("Frame", nil, d.scroll)
	d.content:SetSize(dlg.content, 10)
	d.scroll:SetScrollChild(d.content)
	d.scroll:EnableMouseWheel(true)
	d.scroll:SetScript("OnMouseWheel", function(self, delta)
		local maxScroll = math.max(0, d.content:GetHeight() - self:GetHeight())
		self:SetVerticalScroll(math.max(0, math.min(maxScroll, self:GetVerticalScroll() - delta * 30)))
	end)
	d.rows = {}
	return d
end

local function ClearRows(d)
	for _, r in ipairs(d.rows) do
		r:Hide()
		r:ClearAllPoints()
	end
	wipe(d.rows)
end

-- Stellt Zeilen aus Spezifikationen in `parent` untereinander auf (Dialog und Hub nutzen dasselbe).
-- cache: [spec] = { frame, height }, je Ziel eigen; liefert die Gesamthöhe und die sichtbaren Zeilen.
-- Dynamische Abschnitte ({ type = "dynamic", build = function() return { Zeilen } end }) werden bei jedem
-- Aufbau neu erzeugt; Zeilen mit gleichem spec.key teilen sich eine bereits gebaute Reihe.
function lib:BuildRows(parent, cache, specs, entry, width, makers, flat)
	makers = makers or ROWS
	local expanded = {}
	for _, spec in ipairs(specs) do
		if spec.type == "dynamic" then
			for _, sub in ipairs(spec.build() or {}) do expanded[#expanded + 1] = sub end
		else
			expanded[#expanded + 1] = spec
		end
	end

	local y, hidden, rows = 0, false, {}
	local function Rebuild() lib:RebuildDialog() end
	for _, spec in ipairs(expanded) do
		local make = makers[spec.type]
		if make then
			local isHeader = spec.type == "header"
			if isHeader and not flat then hidden = Collapsed(entry, spec.id or spec.name, spec.collapsed) end
			if isHeader or not hidden then
				local cacheKey = spec.key or spec
				local cached = cache[cacheKey]
				if not cached then
					local frame, h = make(parent, spec, entry, Rebuild)
					cached = { frame = frame, height = h }
					cache[cacheKey] = cached
				end
				local frame, h = cached.frame, cached.height
				frame:ClearAllPoints()
				frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
				frame:SetSize(width, h)
				frame:Show()
				if frame.Update then frame:Update() end
				rows[#rows + 1] = frame
				y = y + h + (isHeader and 2 or 0)
			end
		end
	end
	return y, rows
end

-- Die Einstellungen eines Fensters samt den eingebauten Abschnitten (Position, Sichtbarkeit)
function lib:EntrySpecs(entry)
	if not entry.hubSpecs then
		entry.hubSpecs = {}
		for _, s in ipairs(entry.settings or {}) do entry.hubSpecs[#entry.hubSpecs + 1] = s end
		for _, s in ipairs(BuiltinSpecs(entry)) do entry.hubSpecs[#entry.hubSpecs + 1] = s end
	end
	return entry.hubSpecs
end

-- Nur Visuelles: Einstellungen mit behavior = true entfallen, ebenso Überschriften, unter denen nichts übrig bleibt;
-- skipLinks: Verweise auf andere Fenster entfallen auch (mit Tabs führen diese dorthin)
local function VisualOnly(specs, skipLinks)
	local out, header = {}, nil
	for _, s in ipairs(specs) do
		if s.behavior or (skipLinks and s.type == "link") then
			-- nur im Hub bzw. über die Tabs
		elseif s.type == "header" then
			header = s
		else
			if header then out[#out + 1] = header; header = nil end
			out[#out + 1] = s
		end
	end
	return out
end

-- Tabs: Fenster mit gleicher group (siehe Register) zeigen oben im Dialog eine Leiste mit allen Fenstern der Gruppe.
-- Ein Klick wählt das Fenster; auch ein Klick auf ein Fenster im Edit Mode wählt den passenden Tab.
local TAB_H, TABS_PER_ROW = 28, 4

local function TabLabel(entry)
	local a = lib.addons and lib.addons[entry.addon or ""]
	if a and lib.ShortName then return lib.ShortName(entry, a.title) end
	return entry.name
end

-- Zeichnet die Leiste und liefert die Höhe, die sie über den Einstellungen braucht (0 = keine Tabs)
local function UpdateTabs(d, entry, style)
	local members = style and entry.group and lib.groups[entry.group]
	if not members or #members < 2 then
		if d.tabStrip then d.tabStrip:Hide() end
		return 0
	end
	local C = style.C
	if not d.tabStrip then
		d.tabStrip = CreateFrame("Frame", nil, d)
		d.tabStrip:SetPoint("TOPLEFT", d, "TOPLEFT", 14, -(dlg.head + 6))
		d.tabBtns = {}
	end
	local perRow = math.min(TABS_PER_ROW, #members)
	local w = dlg.content / perRow
	for i, m in ipairs(members) do
		local b = d.tabBtns[i]
		if not b then
			b = CreateFrame("Button", nil, d.tabStrip)
			b.bg = b:CreateTexture(nil, "BACKGROUND")
			b.bg:SetAllPoints()
			b.bar = b:CreateTexture(nil, "ARTWORK")
			b.bar:SetPoint("BOTTOMLEFT")
			b.bar:SetPoint("BOTTOMRIGHT")
			b.bar:SetHeight(2)
			b.hl = b:CreateTexture(nil, "HIGHLIGHT")
			b.hl:SetAllPoints()
			b.hl:SetColorTexture(1, 1, 1, 0.06)
			b.text = Text(b, "GameFontHighlightSmall", 12)
			b.text:SetPoint("CENTER")
			b.text:SetWordWrap(false)
			b:SetScript("OnClick", function(self) lib:Select(self.entry) end)
			d.tabBtns[i] = b
		end
		local row, col = math.floor((i - 1) / TABS_PER_ROW), (i - 1) % TABS_PER_ROW
		local on = m == entry
		b.entry = m
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", d.tabStrip, "TOPLEFT", col * w, -row * TAB_H)
		b:SetSize(w - 2, TAB_H - 2)
		b.text:SetWidth(w - 12)
		b.text:SetText(TabLabel(m))
		local bg = on and C.sel or C.side
		b.bg:SetColorTexture(bg[1], bg[2], bg[3], 1)
		b.bar:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
		b.bar:SetShown(on)
		local tc = on and C.title or C.text
		b.text:SetTextColor(tc[1], tc[2], tc[3])
		b:Show()
	end
	for i = #members + 1, #d.tabBtns do d.tabBtns[i]:Hide() end
	local rows = math.ceil(#members / TABS_PER_ROW)
	d.tabStrip:SetSize(dlg.content, rows * TAB_H)
	d.tabStrip:Show()
	return rows * TAB_H + 6
end

function lib:RebuildDialog()
	if self.RebuildHub then self:RebuildHub() end
	local d, entry = self.dialog, self.selected
	if not (d and entry) then return end
	CloseMenu()
	ClearRows(d)
	d.title:SetText(entry.name)

	-- Einstellungen des Addons plus die eingebauten Abschnitte, einmal zusammengestellt;
	-- die Reihen werden je Eintrag wiederverwendet (kein Neuerzeugen bei jedem Aufklappen)
	-- Gruppe: alle Fenster der Gruppe teilen sich einen Dialog mit vorgeschalteter Fensterauswahl.
	-- Ein Klick auf ein Fenster zeigt direkt dessen Einstellungen, "Alle Fenster" führt zur Auswahl.
	local style = lib.HubStyle
	local tabs = style and entry.group and self.groups[entry.group] and #self.groups[entry.group] > 1
	local specs
	if entry.group and self.listMode and not tabs then
		local members = self.groups[entry.group]
		local list = self.groupList[entry.group]
		if not list or list.count ~= #members then
			list = { count = #members }
			for _, m in ipairs(members) do
				m.pickSpec = m.pickSpec or { type = "button", name = m.name,
					onClick = function() lib:Select(m) end }
				list[#list + 1] = m.pickSpec
			end
			self.groupList[entry.group] = list
		end
		specs = list
		d.title:SetText(self.groupNames[entry.group] or entry.group)
	else
		if not entry.allSpecs then
			entry.allSpecs = {}
			if entry.group and not lib.HubStyle then
				entry.allSpecs[1] = { type = "button", name = "< " .. lib.L.allWindows,
					onClick = function() lib.listMode = true; lib:RebuildDialog() end }
			end
			for _, s in ipairs(entry.settings or {}) do entry.allSpecs[#entry.allSpecs + 1] = s end
			for _, s in ipairs(BuiltinSpecs(entry)) do entry.allSpecs[#entry.allSpecs + 1] = s end
		end
		specs = entry.allSpecs
	end
	local y
	-- Mit dem Hub zeigt der Dialog nur Visuelles; Einstellungen mit behavior = true gibt es dort (Abschnitte
	-- ohne Rest verschwinden), und die Zeilen haben den Look des Einstellungsfensters
	if style then specs = VisualOnly(specs, tabs) end
	local tabH = UpdateTabs(d, entry, style)
	d.scroll:ClearAllPoints()
	d.scroll:SetPoint("TOPLEFT", 14, -(dlg.head + 8 + tabH))
	y, d.rows = self:BuildRows(d.content, self.rowCache, specs, entry, dlg.content, style and style.rows, style and true)

	local contentH = math.max(1, y)
	local viewH = math.min(contentH, dlg.maxH)
	d.content:SetHeight(contentH)
	d.scroll:SetHeight(viewH)
	d.scroll:SetVerticalScroll(0)
	d:SetHeight(viewH + dlg.head + tabH + 22)
end

function lib:RefreshDialog()
	if self.RefreshHub then self:RefreshHub() end
	local d = self.dialog
	if not (d and d:IsShown()) then return end
	for _, r in ipairs(d.rows) do
		if r.Update then r:Update() end
	end
end

-- Auswahl --------------------------------------------------------------------------

function lib:Select(entry)
	self.listMode = false
	local previous = self.selected
	self.selected = entry
	if previous and previous.overlay then UpdateOverlayLook(previous) end
	if not entry then
		if self.dialog then self.dialog:Hide() end
		CloseMenu()
		return
	end
	UpdateOverlayLook(entry)
	if not self.dialog then self.dialog = CreateDialog() end
	local d = self.dialog
	if not d:IsShown() then
		d:ClearAllPoints()
		if self.dialogPos then
			d:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", self.dialogPos[1], self.dialogPos[2])
		else
			d:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
		end
	end
	self:RebuildDialog()
	d:Show()
end

-- Edit Mode -----------------------------------------------------------------------------

local function SetEditing(active)
	lib.editing = active and true or false
	for _, entry in pairs(lib.entries) do
		local on = EntryEditing(entry)
		entry.overlay:SetShown(on)
		entry.lastAlpha = nil
		if entry.onEditMode then entry.onEditMode(on) end
		UpdateVisibility(entry)
	end
	if not lib.editing then
		lib.editFilter = nil   -- der Filter gilt nur für diesen einen Edit Mode
		lib:Select(nil)
	end
end

-- Offene Migrationen wiederholen (final = true: notfalls ein beliebiges altes Layout nehmen)
local function RetryMigrations(final)
	for _, entry in pairs(lib.entries) do
		if entry.pendingMigration and MigrateOldPosition(entry, final) then
			ApplyPosition(entry)
		end
	end
end

local hooked
local function EnsureHooks()
	if hooked or not _G.EditModeManagerFrame then return end
	hooked = true
	hooksecurefunc(EditModeManagerFrame, "EnterEditMode", function() SetEditing(true) end)
	hooksecurefunc(EditModeManagerFrame, "ExitEditMode", function() SetEditing(false) end)
	if EditModeManagerFrame.IsEditModeActive and EditModeManagerFrame:IsEditModeActive() then SetEditing(true) end
end

-- addonId: gehört der Aufrufer zu einem Addon, zählt der Edit Mode nur, wenn er für dieses Addon läuft
function lib:IsEditing(addonId)
	if not self.editing then return false end
	if addonId and self.editFilter and self.editFilter ~= addonId then return false end
	return true
end

-- Öffnet Blizzards Edit Mode (oder schließt ihn). Mit addonId zeigen nur die Fenster dieses Addons ihr Rechteck
-- zum Verschieben und ihre Vorschau; ohne addonId alle. Blizzards eigene Elemente erscheinen immer.
function lib:ToggleEditMode(addonId)
	local m = _G.EditModeManagerFrame
	if not m then return end
	if m:IsShown() then
		HideUIPanel(m)
		return
	end
	self.editFilter = addonId
	ShowUIPanel(m)
end

-- Zieht der Spieler das Fenster gerade? (dann nicht umpositionieren)
function lib:IsMoving(frame)
	local e = self.entries[frame]
	return e and e.moving and true or false
end

-- Sichtbarkeitsregeln laufend prüfen (Kampf, Mouseover)
local ticker = lib.ticker
if not ticker then
	ticker = CreateFrame("Frame")
	lib.ticker = ticker
	local acc = 0
	ticker:SetScript("OnUpdate", function(_, elapsed)
		acc = acc + elapsed
		if acc < 0.1 then return end
		acc = 0
		for _, entry in pairs(lib.entries) do
			UpdateVisibility(entry)
			-- angedockte Fenster nachziehen, falls das Addon oder eine Größenänderung den Anker verändert hat
			if entry.db.dock and not entry.moving and DockTarget(entry) and not DockInPlace(entry) then DockPlace(entry) end
		end
	end)
	ticker:RegisterEvent("PLAYER_LOGIN")
	ticker:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
	ticker:RegisterEvent("PLAYER_ENTERING_WORLD")
	ticker:SetScript("OnEvent", function(_, event)
		EnsureHooks()
		-- erst beim Betreten der Welt endgültig entscheiden
		RetryMigrations(event == "PLAYER_ENTERING_WORLD")
	end)
end

-- Registrieren ----------------------------------------------------------------------------

function lib:Register(frame, opts)
	assert(frame and opts and opts.db, "SexyEditMode:Register(frame, { db = ..., name = ... })")
	local entry = self.entries[frame]
	if entry then return entry end
	entry = {
		frame = frame,
		db = opts.db,
		name = opts.name or (frame.GetName and frame:GetName()) or "?",
		settings = opts.settings,
		scale = opts.scale ~= false,
		visibility = opts.visibility ~= false,
		onMoved = opts.onMoved,
		onEditMode = opts.onEditMode,
		hideWhenInvisible = opts.hideWhenInvisible,
		group = opts.group,
		addon = opts.addon,
		category = opts.category,
		description = opts.description,
		collapsed = {},
		dock = opts.dock ~= false,   -- false: das Addon bringt eigenes Andocken mit
	}
	entry.key = opts.id or ((opts.addon or "") .. ":" .. entry.name)
	self.byKey[entry.key] = entry
	if opts.group then
		-- Auf-/Zuklappen gilt für die ganze Gruppe
		self.groupCollapsed[opts.group] = self.groupCollapsed[opts.group] or {}
		entry.collapsed = self.groupCollapsed[opts.group]
		self.groups[opts.group] = self.groups[opts.group] or {}
		if opts.groupName then self.groupNames[opts.group] = opts.groupName end
		table.insert(self.groups[opts.group], entry)
	end
	self.entries[frame] = entry
	self.order[#self.order + 1] = entry

	MigrateOldPosition(entry)
	CreateOverlay(entry)
	-- Skalierung zuerst ohne Positionsumrechnung setzen (die gespeicherte Position gilt schon in
	-- dieser Skalierung); erst danach die Position anwenden
	if entry.scale then entry.frame:SetScale(entry.db.scale or 1) end
	ApplyPosition(entry)
	EnsureHooks()
	if EntryEditing(entry) then entry.overlay:Show() end
	return entry
end

-- Seite ohne Fenster, die nur im gemeinsamen Hub erscheint (z. B. eine Liste ausgeblendeter Einträge).
-- opts: name, addon, category, description, settings (wie bei Register, ohne Position und Sichtbarkeit)
function lib:RegisterPage(opts)
	local entry = {
		page = true, db = {}, collapsed = {},
		name = opts.name or "?", settings = opts.settings, addon = opts.addon,
		category = opts.category, description = opts.description,
		scale = false, visibility = false,
	}
	self.order[#self.order + 1] = entry
	return entry
end

-- Nach eigenen Änderungen der Einstellungen den Dialog auffrischen
function lib:Refresh() self:RefreshDialog() end

-- Verweise zwischen Fenstern: im Hub bleibt man im Hub, sonst öffnet der kleine Edit-Mode-Dialog
function lib:Navigate(entry)
	if self.HubSelect and self:HubIsShown() then self:HubSelect(entry) else self:Select(entry) end
end

-- Für Hub.lua
lib.ui = {
	Backdrop = Backdrop, NewFrame = NewFrame, Text = Text, FlatButton = FlatButton,
	ApplyPosition = ApplyPosition, OpenSelectMenu = OpenSelectMenu, ApplyOptionFont = ApplyOptionFont,
	BG = BG, EDGE = EDGE, BAND = BAND, ROWBG = ROWBG, GOLD = GOLD, GREEN = GREEN,
}
