-- Vorschau im Einstellungsfenster (SexyEditMode-Hub): eigene Fenster mit eigener Logik, keine Abbilder der echten.
-- Jedes der vier Fenster (Gruppenabgleich, Mitspielern helfen, Quests in der Nähe, Quest-Aktionen) zeichnet sich wie das
-- echte (Rahmen, Titelband, Karten, Etiketten, Ziele mit Balken, Gruppenmitglieder-Chips) mit ausgedachten Beispielen und folgt
-- den Einstellungen. Klickbereiche springen zur passenden Einstellung (jump = Name der Einstellung).
-- Die Maße entsprechen SexyQuestHelper.lua (Zeilenhöhen, Abstände, Breite WIDTH).

local S = {}
SexyQuestHelperSamples = S

local BAND_H, HEADER_H, QUEST_H, CARD_GAP = 30, 30, 24, 8
local HELP_ROW_H, HELP_HEAD_H = 26, 28
local GOAL_H, GOAL_TEXT_X, NEAR_ROW_H, CHIP_H = 25, 33, 26, 14

local TONES = {
	ok = { bg = { 0.082, 0.188, 0.11 }, fg = { 0.48, 0.88, 0.56 } },
	warn = { bg = { 0.227, 0.173, 0.063 }, fg = { 0.94, 0.75, 0.29 } },
	grey = { bg = { 0.16, 0.145, 0.12 }, fg = { 0.66, 0.61, 0.54 } },
	lack = { bg = { 0.231, 0.102, 0.09 }, fg = { 1, 0.6, 0.56 } },
	they = { bg = { 0.078, 0.157, 0.227 }, fg = { 0.53, 0.8, 1 } },
}
local CHIP_TONE = { open = "warn", done = "ok", none = "grey" }

local function State()
	local api = SexyQuestHelperAPI
	return api and api.Sample and api.Sample() or nil
end

-- Zeilenhöhen und Abstände nach den Einstellungen (wie MV.ApplySizes in SexyQuestHelper.lua)
local function Sizes(cfg)
	QUEST_H = cfg.rowH
	HEADER_H = cfg.rowH + 6
	HELP_ROW_H = cfg.rowH + 2
	HELP_HEAD_H = cfg.rowH + 4
	NEAR_ROW_H = cfg.rowH + 2
	CARD_GAP = cfg.cardGap
	BAND_H = cfg.bandH
end

-- Name der Mitspieler-Kopfzeile: links am Klassensymbol (oder am Rand), rechts am Etikett (oder am Rand)
local function NameAnchors(row, pill, cfg)
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

-- Platz und Größe eines Teils relativ zum Fenster (nil, solange das Layout noch nicht berechnet ist)
local function Measure(w, region)
	if not (region and region:IsShown()) then return end
	local fl, ft = w:GetLeft(), w:GetTop()
	local l, t, r, b = region:GetLeft(), region:GetTop(), region:GetRight(), region:GetBottom()
	if not (fl and ft and l and t and r and b) then return end
	return l - fl, ft - t, r - l, t - b
end

local function Redraw()
	local SEM = LibStub("SexyEditMode-1.0", true)
	if SEM and SEM.RedrawSample then SEM:RedrawSample() end
end

-- Bausteine -----------------------------------------------------------------------------------

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

local function ClassColor(class)
	local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if c then return c.r, c.g, c.b end
	return 1, 1, 1
end

local function SetClassIcon(tex, class)
	local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
	if coords then
		tex:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
		tex:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
		return
	end
	local r, g, b = ClassColor(class)
	tex:SetColorTexture(r, g, b, 1)
	tex:SetTexCoord(0, 1, 0, 1)
end

-- Fenster: Rahmen, Titelband, Titel, Schließen-Kreuz, optional Gebiets-Badge und "-"-Knopf
local function NewWindow(host, width, title, opts)
	local w = CreateFrame("Frame", nil, host, "BackdropTemplate")
	w:SetSize(width, 60)
	w:SetPoint("TOPLEFT", host, "TOPLEFT")
	w:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	w:SetBackdropColor(0.08, 0.065, 0.05, 0.96)
	w:SetBackdropBorderColor(0.42, 0.34, 0.15, 1)
	w.band = w:CreateTexture(nil, "BACKGROUND")
	w.band:SetPoint("TOPLEFT", w, "TOPLEFT", 3, -3)
	w.band:SetPoint("TOPRIGHT", w, "TOPRIGHT", -3, -3)
	w.band:SetHeight(BAND_H - 3)
	w.band:SetColorTexture(0.15, 0.12, 0.07, 1)
	w.title = w:CreateFontString(nil, "OVERLAY", "SexyQuestHelperTitle")
	w.title:SetPoint("TOPLEFT", 12, -9)
	w.title:SetText(title)
	w.close = CreateFrame("Button", nil, w, "UIPanelCloseButton")
	w.close:SetPoint("TOPRIGHT", 2, 2)
	w.close:EnableMouse(false)

	if opts and opts.minButton then
		local b = CreateFrame("Frame", nil, w)
		b:SetSize(20, 18)
		b:SetPoint("TOPRIGHT", w, "TOPRIGHT", -32, -9)
		b.bg = b:CreateTexture(nil, "BACKGROUND")
		b.bg:SetAllPoints()
		b.bg:SetColorTexture(0.2, 0.16, 0.06, 1)
		b.text = b:CreateFontString(nil, "OVERLAY", "SexyQuestHelperSmall")
		b.text:SetAllPoints()
		b.text:SetText("-")
		w.minFrame = b
	end

	if opts and opts.zone then
		w.zoneBg = w:CreateTexture(nil, "ARTWORK")
		w.zoneBg:SetPoint("TOPRIGHT", w, "TOPRIGHT", -56, -7)
		w.zoneBg:SetHeight(18)
		w.zoneBg:SetColorTexture(0.165, 0.14, 0.10, 1)
		w.zone = w:CreateFontString(nil, "OVERLAY", "SexyQuestHelperSmall")
		w.zone:SetPoint("CENTER", w.zoneBg, "CENTER", 0, 0)
		w.zone:SetTextColor(0.78, 0.73, 0.64)
	end

	w.rows = {}
	return w
end

-- Kopfzeile ein-/ausblenden; liefert den Abstand der Inhalte zur Oberkante
local function Opacity(w, cfg)
	w:SetBackdropColor(cfg.bgColor.r, cfg.bgColor.g, cfg.bgColor.b, cfg.opacity)
	w:SetBackdropBorderColor(cfg.borderColor.r, cfg.borderColor.g, cfg.borderColor.b, 1)
	w.band:SetColorTexture(0.15, 0.12, 0.07, cfg.opacity)   -- Titelband und Karten gehören dazu, sonst wäre nur der Rand durchsichtig
	-- Höhe der Titelleiste: Titel, Gebiets-Badge und "-"-Knopf sitzen mittig im Band
	w.band:SetHeight(BAND_H - 3)
	w.title:ClearAllPoints()
	w.title:SetPoint("LEFT", w.band, "LEFT", 9, 0)
	if w.zoneBg then
		w.zoneBg:ClearAllPoints()
		w.zoneBg:SetPoint("RIGHT", w.band, "RIGHT", -53, 0)
	end
	if w.minFrame then
		w.minFrame:ClearAllPoints()
		w.minFrame:SetPoint("RIGHT", w.band, "RIGHT", -29, 0)
	end
end

local function SetHeader(w, hide, cfg)
	w.band:SetShown(not hide)
	w.title:SetShown(not hide)
	w.close:SetShown(not hide and cfg.showButtons ~= false)
	if w.minFrame then w.minFrame:SetShown(not hide and cfg.showButtons ~= false) end
	if w.zoneBg and hide then w.zoneBg:Hide(); w.zone:Hide() end
	return hide and 6 or BAND_H
end

-- Zeile mit allen Teilen (jeder Fenstertyp nutzt, was er braucht)
local function MakeRow(w)
	local row = CreateFrame("Frame", nil, w)
	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints()
	row.divider = row:CreateTexture(nil, "BORDER")
	row.divider:SetPoint("TOPLEFT")
	row.divider:SetPoint("TOPRIGHT")
	row.divider:SetHeight(1)
	row.divider:SetColorTexture(0.21, 0.19, 0.14, 1)
	row.accent = row:CreateTexture(nil, "ARTWORK")
	row.accent:SetPoint("TOPLEFT")
	row.accent:SetPoint("BOTTOMLEFT")
	row.accent:SetWidth(3)
	row.avatar = row:CreateTexture(nil, "ARTWORK")
	row.status = MakePill(row)
	row.name = row:CreateFontString(nil, "OVERLAY", "SexyQuestHelperText")
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)
	row.kind = MakePill(row)
	row.fs = row:CreateFontString(nil, "OVERLAY", "SexyQuestHelperSmall")
	row.fs:SetJustifyH("LEFT")
	row.share = CreateFrame("Frame", nil, row)
	row.share:SetSize(52, QUEST_H - 6)
	row.share:SetPoint("RIGHT", row, "RIGHT", -8, 0)
	row.share.bg = row.share:CreateTexture(nil, "BACKGROUND")
	row.share.bg:SetAllPoints()
	row.share.bg:SetColorTexture(0.15, 0.12, 0.07, 1)
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
	row.goals, row.chips = {}, {}
	return row
end

local function ResetRow(row)
	row.bg:Hide(); row.divider:Hide(); row.accent:Hide(); row.avatar:Hide()
	row.name:Hide(); row.fs:Hide(); row.share:Hide()
	HidePill(row.status); HidePill(row.kind)
	for _, g in ipairs(row.goals) do g:Hide() end
	for _, c in ipairs(row.chips) do c:Hide() end
	row.fs:ClearAllPoints()
	row.name:ClearAllPoints()
	row.avatar:ClearAllPoints()
	row.status.tex:ClearAllPoints()
	row.kind.tex:ClearAllPoints()
end

-- Chips mit dem Stand der Mitspieler (Klassensymbol und Stand), rechtsbündig; liefert die belegte Breite
local function LayoutChips(owner, list, right, top)
	local n = list and #list or 0
	local cx = 0
	for i = n, 1, -1 do
		local item = list[i]
		local chip = owner.chips[i]
		if not chip then
			chip = CreateFrame("Frame", nil, owner)
			chip:SetHeight(CHIP_H)
			chip.bg = chip:CreateTexture(nil, "BACKGROUND")
			chip.bg:SetAllPoints()
			chip.icon = chip:CreateTexture(nil, "ARTWORK")
			chip.icon:SetSize(12, 12)
			chip.icon:SetPoint("LEFT", chip, "LEFT", 4, 0)
			chip.text = chip:CreateFontString(nil, "OVERLAY", "SexyQuestHelperSmall")
			chip.text:SetPoint("LEFT", chip.icon, "RIGHT", 4, 0)
			owner.chips[i] = chip
		end
		SetClassIcon(chip.icon, item.class)
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
	for i = n + 1, #owner.chips do owner.chips[i]:Hide() end
	return n > 0 and (cx - 3) or 0
end

-- Ziele einer Quest ab dem Abstand top; liefert die belegte Höhe. goal = { name, count, frac, done, mates }
local function RenderGoals(row, goals, top, rowWidth, bars, barH, cfg)
	local y = top
	for j, goal in ipairs(goals) do
		local g = row.goals[j]
		if not g then
			g = CreateFrame("Frame", nil, row)
			g.icon = g:CreateTexture(nil, "ARTWORK")
			g.icon:SetSize(13, 13)
			g.icon:SetPoint("TOPLEFT", g, "TOPLEFT", 14, -4)
			g.pill = MakePill(g)
			g.pill.tex:SetPoint("TOPRIGHT", g, "TOPRIGHT", -8, -3)
			g.text = g:CreateFontString(nil, "OVERLAY", "SexyQuestHelperSmall")
			g.text:SetPoint("TOPLEFT", g, "TOPLEFT", GOAL_TEXT_X, -5)
			g.text:SetJustifyH("LEFT")
			g.text:SetJustifyV("TOP")
			g.text:SetWordWrap(true)
			g.chips = {}
			g.barBg = g:CreateTexture(nil, "BORDER")
			g.barBg:SetPoint("BOTTOMLEFT", g, "BOTTOMLEFT", GOAL_TEXT_X, 3)
			g.barBg:SetPoint("BOTTOMRIGHT", g, "BOTTOMRIGHT", -8, 3)
			g.barBg:SetHeight(3)
			g.barBg:SetColorTexture(0.21, 0.19, 0.14, 1)
			g.bar = g:CreateTexture(nil, "ARTWORK")
			g.bar:SetPoint("BOTTOMLEFT", g.barBg, "BOTTOMLEFT")
			g.bar:SetHeight(3)
			row.goals[j] = g
		end
		local counts = goal.count and cfg.showCounts ~= false
		local own = counts and (38 + 4) or 0
		local cw = LayoutChips(g, goal.mates, 8 + own, 3)
		g.text:SetWidth(rowWidth - GOAL_TEXT_X - 8 - (counts and (38 + 6) or 0) - ((cw > 0) and (cw + 6) or 0))
		g.text:SetText(goal.name)
		barH = barH or 3
		local h = math.max(GOAL_H, math.ceil(g.text:GetStringHeight()) + 14) + math.max(0, barH - 3)
		g.barBg:SetHeight(barH)
		g.bar:SetHeight(barH)
		g:ClearAllPoints()
		g:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -y)
		g:SetSize(rowWidth, h)
		y = y + h

		g.icon:SetShown(cfg.showChecks ~= false)
		if goal.done then
			g.icon:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
			g.icon:SetVertexColor(0.45, 0.9, 0.55)
			g.text:SetTextColor(0.55, 0.78, 0.6)
		else
			g.icon:SetTexture("Interface\\Buttons\\UI-CheckBox-Up")
			g.icon:SetVertexColor(0.75, 0.7, 0.6)
			g.text:SetTextColor(0.9, 0.87, 0.78)
		end

		if goal.count then
			if counts then
				SetPill(g.pill, goal.done and "ok" or "warn", goal.count, 38, 14)
			else
				HidePill(g.pill)
			end
			g.barBg:SetShown(bars)
			g.bar:SetShown(bars)
			g.bar:SetWidth(math.max(1, (rowWidth - GOAL_TEXT_X - 8) * (goal.frac or 0)))
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

-- Kurzes Aufleuchten einer Zeile
local function Glow(row, cfg)
	local g = row.glowFx
	if not g then
		g = CreateFrame("Frame", nil, row)
		g:SetAllPoints()
		g.tex = g:CreateTexture(nil, "OVERLAY")
		g.tex:SetAllPoints()
		g.tex:SetColorTexture(0.94, 0.75, 0.29, 1)
		g.tex:SetBlendMode("ADD")
		g:Hide()
		g:SetScript("OnUpdate", function(self, dt)
			self.t = self.t + dt
			local p = self.t / 1.3
			if p >= 1 then self:Hide() return end
			self.tex:SetAlpha(self.alpha * math.abs(math.sin(p * math.pi * 2)) * (1 - p))
		end)
		row.glowFx = g
	end
	g.t = 0
	g.alpha = cfg.glowAlpha or 0.4
	g.tex:SetColorTexture(cfg.glowColor.r, cfg.glowColor.g, cfg.glowColor.b, 1)
	g.tex:SetAlpha(0)
	g:Show()
end

-- Gruppenabgleich ---------------------------------------------------------------------------------

function S.main(host, c)
	local st = State()
	if not st then return nil end
	local T, cfg, WIDTH = st.T, st.cfg, st.WIDTH

	if not c.win then c.win = NewWindow(host, WIDTH, "SexyQuestHelper", { zone = true, minButton = true }) end
	local w = c.win

	Sizes(cfg)
	Opacity(w, cfg)
	local head = SetHeader(w, cfg.hideHeaderMain, cfg)
	local hideZone = cfg.hideZone or cfg.hideHeaderMain
	local pills = cfg.showPills ~= false

	w.zone:SetText(T("Wald von Elwynn", "Elwynn Forest"))
	w.zone:SetWidth(0)
	local zw = math.min(w.zone:GetStringWidth(), 150)
	w.zone:SetWidth(zw)
	w.zoneBg:SetWidth(zw + 18)
	w.zone:SetShown(not hideZone)
	w.zoneBg:SetShown(not hideZone)

	local entries = {
		{ kind = "header", name = "Testmate", class = "MAGE", tone = "warn", status = T("3 Unterschiede", "3 differences") },
		{ kind = "quest", title = T("Wölfe im Wald", "Wolves in the woods"), tone = "lack", label = T("Dir fehlt", "You lack") },
		{ kind = "quest", title = T("Der verlorene Beutel", "The lost pouch"), tone = "they", label = T("Hat nicht", "Lacks"), share = true },
		{ kind = "quest", title = T("Kräuter für den Heiler", "Herbs for the healer"), tone = "they", label = T("Hat nicht", "Lacks"), share = true },
		{ kind = "header", name = "Brom", class = "WARRIOR", tone = "ok", status = T("Alles gleich", "In sync") },
	}

	local y, W = head + 8, WIDTH - 24
	local parts = {}
	local geo = {}   -- je Zeile: Oberkante und Höhe, für die Klickbereiche
	for i, e in ipairs(entries) do
		local row = w.rows[i]
		if not row then row = MakeRow(w); w.rows[i] = row end
		ResetRow(row)
		local h = e.kind == "header" and HEADER_H or QUEST_H
		if e.kind == "header" and i > 1 then y = y + CARD_GAP end
		geo[i] = { y = y, h = h, e = e }
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", w, "TOPLEFT", 12, -y)
		row:SetSize(W, h)
		row.bg:SetColorTexture(0.145, 0.125, 0.10, cfg.opacity)
		row.bg:Show()
		if e.kind == "header" then
			row.avatar:SetSize(cfg.avatarSize or 20, cfg.avatarSize or 20)
			row.avatar:SetPoint("LEFT", row, "LEFT", 8, 0)
			SetClassIcon(row.avatar, e.class)
			row.avatar:SetShown(cfg.showAvatar ~= false)
			if cfg.showStatus ~= false then SetPill(row.status, e.tone, e.status, nil, 18) end
			row.status.tex:SetPoint("RIGHT", row, "RIGHT", -8, 0)
			NameAnchors(row, row.status, cfg)
			row.name:SetText(e.name)
			row.name:SetTextColor(ClassColor(e.class))
			row.name:Show()
		else
			row.divider:SetShown(cfg.showDividers ~= false)
			local share = e.share and cfg.showShare ~= false
			if pills then
				SetPill(row.kind, e.tone, e.label, 66, 16)
				row.kind.tex:SetPoint("LEFT", row, "LEFT", 8, 0)
			end
			row.fs:SetPoint("LEFT", row, "LEFT", pills and 82 or 8, 0)
			row.fs:SetPoint("RIGHT", row, "RIGHT", share and -66 or -8, 0)
			row.fs:SetText(e.title)
			row.fs:SetTextColor(0.95, 0.92, 0.86)
			row.fs:SetWordWrap(false)
			row.fs:Show()
			if share then
				row.share:SetHeight(QUEST_H - 6)
				row.share.text:SetText(T("Teilen", "Share"))
				row.share:Show()
			end
		end
		row:Show()
		y = y + h
	end
	for i = #entries + 1, #w.rows do w.rows[i]:Hide() end

	local H = y + 12
	w:SetSize(WIDTH, H)

	parts[#parts + 1] = { name = "SexyQuestHelper", x = 0, y = 0, w = WIDTH, h = H, jump = "_pos" }
	parts[#parts + 1] = { name = T("Deckkraft der Fenster", "Window opacity"), x = 0, y = 0, w = 6, h = H, jump = T("Deckkraft der Fenster", "Window opacity") }
	parts[#parts + 1] = { name = T("Breite der Fenster", "Width of the windows"), x = WIDTH - 6, y = 0, w = 6, h = H, jump = T("Breite der Fenster", "Width of the windows") }
	parts[#parts + 1] = { name = T("Kopfzeile", "Header"), x = 0, y = 0, w = WIDTH, h = head, jump = T("Kopfzeile ausblenden", "Hide header") }
	if not cfg.hideHeaderMain then
		parts[#parts + 1] = { name = T("Höhe der Titelleiste", "Height of the title band"), x = 0, y = head - 5, w = WIDTH, h = 5, jump = T("Höhe der Titelleiste", "Height of the title band") }
		parts[#parts + 1] = { name = T("Knöpfe", "Buttons"), x = WIDTH - 30, y = 0, w = 30, h = head, jump = T("Knöpfe in der Titelleiste zeigen", "Show the buttons in the title band") }
	end
	parts[#parts + 1] = { name = T("Randfarbe", "Border color"), x = 0, y = H - 5, w = WIDTH, h = 5, jump = T("Randfarbe", "Border color") }
	parts[#parts + 1] = { name = T("Hintergrundfarbe", "Background color"), x = 5, y = H - 12, w = WIDTH - 10, h = 7, jump = T("Hintergrundfarbe", "Background color") }
	for i, g in ipairs(geo) do
		if g.e.kind == "header" then
			if cfg.showAvatar ~= false then
				local sz = cfg.avatarSize or 20
				parts[#parts + 1] = { name = T("Klassensymbol", "Class icon"), x = 20, y = g.y + (g.h - sz) / 2, w = sz, h = sz - 5, jump = T("Klassensymbol der Mitspieler zeigen", "Show the class icon of the members") }
				parts[#parts + 1] = { name = T("Größe", "Size"), x = 20, y = g.y + (g.h + sz) / 2 - 5, w = sz, h = 5, jump = T("Größe des Klassensymbols", "Size of the class icon") }
			end
			if cfg.showStatus ~= false then
				local sx, sy, sw, sh = Measure(w, w.rows[i].status.tex)
				if sx then parts[#parts + 1] = { name = T("Etikett", "Label"), x = sx, y = sy, w = sw, h = sh, jump = T("Etiketten der Mitspieler zeigen", "Show the labels of the members") } end
			end
			local nx, ny, nw, nh = Measure(w, w.rows[i].name)
			if nx then parts[#parts + 1] = { name = T("Schriftgröße", "Font size"), x = nx, y = ny, w = math.min(nw, 120), h = nh, jump = T("Schriftgröße", "Font size") } end
			if i > 1 then
				parts[#parts + 1] = { name = T("Abstand der Karten", "Gap between cards"), x = 12, y = g.y - math.max(CARD_GAP, 4) / 2 - CARD_GAP / 2, w = W, h = math.max(CARD_GAP, 4), jump = T("Abstand der Karten", "Gap between cards") }
			end
		else
			parts[#parts + 1] = { name = T("Zeilenhöhe", "Row height"), x = 12, y = g.y, w = W, h = g.h, jump = T("Zeilenhöhe", "Row height") }
			parts[#parts + 1] = { name = T("Trennlinien", "Dividers"), x = 12, y = g.y - 2, w = W, h = 4, jump = T("Trennlinien zeigen", "Show the dividers") }
			if pills then
				parts[#parts + 1] = { name = T("Etiketten", "Labels"), x = 20, y = g.y + (g.h - 16) / 2, w = 66, h = 16, jump = T("Etiketten bei den Quests zeigen", "Show the labels on the quests") }
			end
			if g.e.share and cfg.showShare ~= false then
				parts[#parts + 1] = { name = T("Teilen", "Share"), x = 12 + W - 8 - 52, y = g.y + 3, w = 52, h = g.h - 6, jump = T("Teilen-Knopf zeigen", "Show the share button") }
			end
		end
	end
	if not hideZone then
		local zx, zy, zw, zh = Measure(w, w.zoneBg)
		if zx then parts[#parts + 1] = { name = T("Gebiet", "Zone"), x = zx, y = zy, w = zw, h = zh, jump = T("Gebiet im Titel ausblenden", "Hide the zone in the title") } end
	end
	if not cfg.hideHeaderMain and cfg.showButtons ~= false then
		local mx, my, mw, mh = Measure(w, w.minFrame)
		if mx then parts[#parts + 1] = { name = T("Im Kampf", "In combat"), x = mx, y = my, w = mw, h = mh, jump = T("Im Kampf", "In combat") } end
	end
	if not c.redrawn then
		c.redrawn = true
		C_Timer.After(0.1, Redraw)
	end
	return { w = WIDTH, h = H, parts = parts }
end

-- Mitspielern helfen ------------------------------------------------------------------------------

function S.help(host, c)
	local st = State()
	if not st then return nil end
	local T, cfg, WIDTH = st.T, st.cfg, st.WIDTH

	if not c.win then c.win = NewWindow(host, WIDTH, T("Mitspielern helfen", "Help your group"), { minButton = true }) end
	local w = c.win
	Sizes(cfg)
	Opacity(w, cfg)
	local head = SetHeader(w, cfg.hideHeaderHelp, cfg)

	local entries = {
		{ kind = "header", name = "Testmate", class = "MAGE", count = 2 },
		{ kind = "quest", title = T("Wölfe im Wald", "Wolves in the woods"), pct = 60,
			goals = { { name = T("Wölfe getötet", "Wolves slain"), count = "5/8", frac = 5 / 8 }, { name = T("Fell gesammelt", "Pelt collected"), count = "1/1", frac = 1, done = true } } },
		{ kind = "quest", title = T("Der verlorene Beutel", "The lost pouch"), pct = 100, ready = true,
			goals = { { name = T("Beutel gefunden", "Pouch found"), count = "1/1", frac = 1, done = true } } },
		-- zweiter Mitspieler: erst damit ist der Abstand der Karten zu sehen
		{ kind = "header", name = "Brom", class = "WARRIOR", count = 1 },
		{ kind = "quest", title = T("Kräuter für den Heiler", "Herbs for the healer"), pct = 30,
			goals = { { name = T("Friedensblumen gesammelt", "Peacebloom gathered"), count = "3/10", frac = 0.3 } } },
	}

	local y, W = head + 8, WIDTH - 24
	local geo = {}
	for i, e in ipairs(entries) do
		local row = w.rows[i]
		if not row then row = MakeRow(w); w.rows[i] = row end
		ResetRow(row)
		if e.kind == "header" and i > 1 then y = y + CARD_GAP end
		geo[i] = { y = y, e = e }
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", w, "TOPLEFT", 12, -y)
		row:SetWidth(W)
		local isHeader = e.kind == "header"
		row.bg:SetColorTexture(isHeader and 0.165 or 0.145, isHeader and 0.14 or 0.125, isHeader and 0.10 or 0.10, cfg.opacity)
		row.bg:Show()
		local h
		if isHeader then
			row.avatar:SetSize((cfg.avatarSize or 20) - 2, (cfg.avatarSize or 20) - 2)
			row.avatar:SetPoint("LEFT", row, "LEFT", 8, 0)
			SetClassIcon(row.avatar, e.class)
			row.avatar:SetShown(cfg.showAvatar ~= false)
			if cfg.showStatus ~= false then SetPill(row.status, "they", e.count .. " " .. T("Quests", "quests"), nil, 18) end
			row.status.tex:SetPoint("RIGHT", row, "RIGHT", -8, 0)
			NameAnchors(row, row.status, cfg)
			row.name:SetText(e.name)
			row.name:SetTextColor(ClassColor(e.class))
			row.name:Show()
			h = HELP_HEAD_H
		else
			row.accent:SetColorTexture(e.ready and 0.30 or 0.94, e.ready and 0.76 or 0.75, e.ready and 0.42 or 0.29, 1)
			row.accent:SetWidth(cfg.accentW or 3)
			row.accent:SetShown(cfg.showAccent ~= false)
			row.fs:SetFontObject("SexyQuestHelperText")
			row.fs:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -6)
			row.fs:SetWidth(W - 10 - 60 - 8 - 6)
			row.fs:SetWordWrap(true)
			row.fs:SetJustifyV("TOP")
			row.fs:SetText(e.title)
			row.fs:SetTextColor(0.95, 0.92, 0.86)
			row.fs:Show()
			if e.ready then SetPill(row.kind, "ok", T("Bereit", "Ready"), 60, 16) else SetPill(row.kind, "warn", e.pct .. " %", 60, 16) end
			row.kind.tex:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -5)
			local top = math.max(HELP_ROW_H, math.ceil(row.fs:GetStringHeight()) + 12)
			local gh = RenderGoals(row, e.goals, top - 2, W, cfg.showBars ~= false, cfg.barH, cfg)
			h = gh > 0 and (top + 4 + gh + 4) or top
		end
		row:SetHeight(h)
		geo[i].h = h
		row:Show()
		y = y + h
	end
	for i = #entries + 1, #w.rows do w.rows[i]:Hide() end

	local H = y + 12
	w:SetSize(WIDTH, H)
	local parts = {
		{ name = T("Mitspielern helfen", "Help your group"), x = 0, y = 0, w = WIDTH, h = H, jump = "_pos" },
		{ name = T("Deckkraft der Fenster", "Window opacity"), x = 0, y = 0, w = 6, h = H, jump = T("Deckkraft der Fenster", "Window opacity") },
		{ name = T("Breite der Fenster", "Width of the windows"), x = WIDTH - 6, y = 0, w = 6, h = H, jump = T("Breite der Fenster", "Width of the windows") },
		{ name = T("Kopfzeile", "Header"), x = 0, y = 0, w = WIDTH, h = head, jump = T("Kopfzeile ausblenden", "Hide header") },
	}
	if not cfg.hideHeaderHelp then
		parts[#parts + 1] = { name = T("Höhe der Titelleiste", "Height of the title band"), x = 0, y = head - 5, w = WIDTH, h = 5, jump = T("Höhe der Titelleiste", "Height of the title band") }
		parts[#parts + 1] = { name = T("Knöpfe", "Buttons"), x = WIDTH - 30, y = 0, w = 30, h = head, jump = T("Knöpfe in der Titelleiste zeigen", "Show the buttons in the title band") }
	end
	parts[#parts + 1] = { name = T("Randfarbe", "Border color"), x = 0, y = H - 5, w = WIDTH, h = 5, jump = T("Randfarbe", "Border color") }
	parts[#parts + 1] = { name = T("Hintergrundfarbe", "Background color"), x = 5, y = H - 12, w = WIDTH - 10, h = 7, jump = T("Hintergrundfarbe", "Background color") }
	local failed = false
	for i, g in ipairs(geo) do
		local row = w.rows[i]
		if g.e.kind == "header" then
			if cfg.showAvatar ~= false then
				local ax, ay, aw, ah = Measure(w, row.avatar)
				if ax then
					parts[#parts + 1] = { name = T("Klassensymbol", "Class icon"), x = ax, y = ay, w = aw, h = ah - 5, jump = T("Klassensymbol der Mitspieler zeigen", "Show the class icon of the members") }
					parts[#parts + 1] = { name = T("Größe", "Size"), x = ax, y = ay + ah - 5, w = aw, h = 5, jump = T("Größe des Klassensymbols", "Size of the class icon") }
				else
					failed = true
				end
			end
			if cfg.showStatus ~= false then
				local sx, sy, sw, sh = Measure(w, row.status.tex)
				if sx then parts[#parts + 1] = { name = T("Etikett", "Label"), x = sx, y = sy, w = sw, h = sh, jump = T("Etiketten der Mitspieler zeigen", "Show the labels of the members") } else failed = true end
			end
			local nx, ny, nw, nh = Measure(w, row.name)
			if nx then parts[#parts + 1] = { name = T("Schriftgröße", "Font size"), x = nx, y = ny, w = math.min(nw, 120), h = nh, jump = T("Schriftgröße", "Font size") } end
		else
			parts[#parts + 1] = { name = T("Zeilenhöhe", "Row height"), x = 12, y = g.y, w = W, h = HELP_ROW_H, jump = T("Zeilenhöhe", "Row height") }
			if cfg.showAccent ~= false then
				parts[#parts + 1] = { name = T("Farbstreifen", "Stripe"), x = 12, y = g.y, w = math.max(cfg.accentW or 3, 4), h = HELP_ROW_H * 0.6, jump = T("Farbstreifen links zeigen", "Show the colored stripe on the left") }
				parts[#parts + 1] = { name = T("Breite", "Width"), x = 12, y = g.y + HELP_ROW_H * 0.6, w = math.max(cfg.accentW or 3, 4), h = HELP_ROW_H * 0.4, jump = T("Breite des Farbstreifens", "Width of the colored stripe") }
			end
			for _, goal in ipairs(row.goals) do
				if goal:IsShown() then
					local cx, cy, cw, ch = Measure(w, goal.icon)
					if cx then parts[#parts + 1] = { name = T("Kästchen", "Box"), x = cx - 1, y = cy - 1, w = cw + 2, h = ch + 2, jump = T("Kästchen vor den Zielen zeigen", "Show the boxes before the goals") } end
					local px, py, pw, ph = Measure(w, goal.pill.tex)
					if px then parts[#parts + 1] = { name = T("Zähler", "Counter"), x = px, y = py, w = pw, h = ph, jump = T("Zähler der Ziele zeigen", "Show the counters of the goals") } end
				end
			end
		end
	end
	for i, g in ipairs(geo) do
		if g.e.kind == "quest" then
			if cfg.showBars ~= false then
				for _, goal in ipairs(w.rows[i].goals) do
					local bx, by, bw, bh = Measure(w, goal.barBg)
					if bx then
						parts[#parts + 1] = { name = T("Fortschrittsbalken", "Progress bar"), x = bx, y = by - 3, w = bw, h = bh + 6, jump = T("Fortschrittsbalken der Ziele zeigen", "Show the progress bars of the goals") }
					elseif goal:IsShown() then
						failed = true
					end
				end
			end
		elseif i > 1 then
			parts[#parts + 1] = { name = T("Abstand der Karten", "Gap between cards"), x = 12, y = g.y - math.max(CARD_GAP, 4) / 2 - CARD_GAP / 2, w = W, h = math.max(CARD_GAP, 4), jump = T("Abstand der Karten", "Gap between cards") }
		end
	end
	if failed and not c.retry then
		c.retry = true
		C_Timer.After(0.1, Redraw)
	elseif not failed then
		c.retry = nil
	end
	if not cfg.hideHeaderHelp and cfg.showButtons ~= false then
		local mx, my, mw, mh = Measure(w, w.minFrame)
		if mx then parts[#parts + 1] = { name = T("Im Kampf", "In combat"), x = mx, y = my, w = mw, h = mh, jump = T("Im Kampf", "In combat") } end
	end
	return { w = WIDTH, h = H, parts = parts }
end

-- Quests in der Nähe ------------------------------------------------------------------------------

local MAX_VIEW_DEFAULT = 400

function S.near(host, c)
	local st = State()
	if not st then return nil end
	local T, cfg, WIDTH = st.T, st.cfg, st.WIDTH

	if not c.win then
		c.win = NewWindow(host, WIDTH, T("Quests in der Nähe", "Quests nearby"), { minButton = true })
		-- Scrollbereich: schneidet ab, wenn die Liste höher ist als die größte Höhe
		c.win.view = CreateFrame("Frame", nil, c.win)
		c.win.view:SetClipsChildren(true)
		c.win.content = CreateFrame("Frame", nil, c.win.view)
		c.win.content:SetPoint("TOPLEFT")
		c.win.track = c.win.view:CreateTexture(nil, "ARTWORK")
		c.win.track:SetWidth(3)
		c.win.track:SetColorTexture(0.21, 0.19, 0.14, 1)
		c.win.thumb = c.win.view:CreateTexture(nil, "OVERLAY")
		c.win.thumb:SetWidth(3)
		c.win.thumb:SetColorTexture(0.91, 0.76, 0.42, 0.9)
		c.t0 = GetTime()
		c.win:SetScript("OnUpdate", function()
			local now = GetTime()
			local row2 = c.win.rows[2]
			if row2 and row2:IsShown() and cfg.showDist ~= false then
				-- Entfernung zählt herunter, alle 8 Sekunden leuchtet die zweite Quest auf ("neu in Reichweite")
				local t = now - c.t0
				local d = math.max(5, 46 - (t * 2) % 40)
				local text = math.floor(d + 0.5) .. " m"
				if c.dist ~= text then
					c.dist = text
					SetPill(row2.kind, "they", text, nil, 16)
				end
				if c.glowAt == nil or now - c.glowAt > 8 then
					c.glowAt = now
					Glow(row2, cfg)
				end
			end
		end)
	end
	local w = c.win
	Sizes(cfg)
	Opacity(w, cfg)
	local band = SetHeader(w, cfg.hideHeaderNear, cfg)
	-- Reiterleiste unter dem Titelband (wie im echten Fenster): Aktiv gewählt, Ausgeblendet mit Anzahl
	local TAB_H = 32
	if not w.tabs then
		w.tabs = {}
		for i, label in ipairs({ T("Aktiv", "Active"), T("Ausgeblendet (2)", "Hidden (2)") }) do
			local t = CreateFrame("Frame", nil, w)
			t:SetSize(i == 1 and 80 or 130, 22)
			t.bg = t:CreateTexture(nil, "BACKGROUND")
			t.bg:SetAllPoints()
			t.text = t:CreateFontString(nil, "OVERLAY", "SexyQuestHelperSmall")
			t.text:SetAllPoints()
			t.text:SetText(label)
			for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
				{ "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
				local x = t:CreateTexture(nil, "BORDER")
				x:SetColorTexture(0.42, 0.34, 0.15, 1)
				x:SetPoint(e[1])
				x:SetPoint(e[2])
				if e[3] then x:SetHeight(1) else x:SetWidth(1) end
			end
			w.tabs[i] = t
		end
		w.tabs[1].bg:SetColorTexture(0.42, 0.34, 0.15, 1)
		w.tabs[1].text:SetTextColor(1, 0.9, 0.7)
		w.tabs[2].bg:SetColorTexture(0.15, 0.12, 0.07, 1)
		w.tabs[2].text:SetTextColor(0.91, 0.76, 0.42)
	end
	for _, t in ipairs(w.tabs) do t:SetWidth(math.max(60, math.ceil(t.text:GetStringWidth()) + 24)) end
	w.tabs[1]:ClearAllPoints()
	w.tabs[1]:SetPoint("TOPLEFT", w, "TOPLEFT", 10, -(band + 7))
	w.tabs[2]:ClearAllPoints()
	w.tabs[2]:SetPoint("LEFT", w.tabs[1], "RIGHT", 4, 0)
	local head = band + TAB_H
	local mates = cfg.nearMates

	local entries = {
		{ title = T("Wölfe im Wald", "Wolves in the woods"), dist = 34,
			questMates = mates and { { class = "MAGE", text = "?", state = "none" } } or nil,
			goals = {
				{ name = T("Wölfe getötet", "Wolves slain"), count = "5/8", frac = 5 / 8,
					mates = mates and { { class = "MAGE", text = "3/8", state = "open" }, { class = "WARRIOR", text = "8/8", state = "done" } } or nil },
				{ name = T("Fell gesammelt", "Pelt collected"), count = "0/1", frac = 0 },
			} },
		{ title = T("Der verlorene Beutel", "The lost pouch"), dist = 41,
			goals = { { name = T("Beutel gefunden", "Pouch found"), count = "0/1", frac = 0,
				mates = mates and { { class = "MAGE", text = "1/1", state = "done" } } or nil } } },
		{ title = T("Kräuter für den Heiler", "Herbs for the healer"), dist = 52,
			goals = { { name = T("Friedensblumen gesammelt", "Peacebloom gathered"), count = "7/10", frac = 0.7 } } },
	}

	local contentW = WIDTH - 24
	local y = 8
	for i, e in ipairs(entries) do
		local row = w.rows[i]
		if not row then
			row = MakeRow(w)
			row:SetParent(w.content)
			w.rows[i] = row
		end
		ResetRow(row)
		local allDone = false
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", w.content, "TOPLEFT", 12, -y)
		row:SetWidth(contentW)
		row.bg:SetColorTexture(0.145, 0.125, 0.10, cfg.opacity)
		row.bg:Show()
		row.divider:SetShown(i > 1 and cfg.showDividers ~= false)
		row.accent:SetColorTexture(0.94, 0.75, 0.29, 1)
		row.accent:SetWidth(cfg.accentW or 3)
		row.accent:SetShown(cfg.showAccent ~= false)
		row.fs:SetFontObject("SexyQuestHelperText")
		row.fs:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -6)
		row.fs:SetWordWrap(false)
		row.fs:SetText(e.title)
		row.fs:SetTextColor(0.95, 0.92, 0.86)
		row.fs:Show()
		local showDist = cfg.showDist ~= false
		if showDist then SetPill(row.kind, "they", e.dist .. " m", nil, 16) end
		row.kind.tex:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -5)
		local qw = LayoutChips(row, e.questMates, 8 + (showDist and (row.kind.tex:GetWidth() + 4) or 0), 6)
		if showDist then
			row.fs:SetPoint("RIGHT", row.kind.tex, "LEFT", -(6 + ((qw > 0) and (qw + 4) or 0)), 0)
		else
			row.fs:SetPoint("RIGHT", row, "RIGHT", -(8 + ((qw > 0) and (qw + 4) or 0)), 0)
		end
		local gh = RenderGoals(row, e.goals, NEAR_ROW_H - 2, contentW, cfg.showBars ~= false, cfg.barH, cfg)
		local h = NEAR_ROW_H + ((gh > 0) and (4 + gh) or 0) + 4
		row:SetHeight(h)
		row:Show()
		y = y + h + 2
		if i == 2 then c.dist = nil end
	end
	for i = #entries + 1, #w.rows do w.rows[i]:Hide() end

	local contentH = y
	local viewH = math.min(contentH, cfg.nearMaxHeight or MAX_VIEW_DEFAULT)
	w.view:ClearAllPoints()
	w.view:SetPoint("TOPLEFT", w, "TOPLEFT", 0, -head)
	w.view:SetSize(WIDTH, viewH)
	w.content:SetSize(WIDTH, contentH)

	if contentH > viewH and cfg.showScroll ~= false then
		local trackH = viewH - 10
		w.track:ClearAllPoints()
		w.track:SetPoint("TOPRIGHT", w.view, "TOPRIGHT", -5, -8)
		w.track:SetPoint("BOTTOMRIGHT", w.view, "BOTTOMRIGHT", -5, 2)
		w.thumb:ClearAllPoints()
		w.thumb:SetPoint("TOPRIGHT", w.track, "TOPRIGHT", 0, 0)
		w.thumb:SetHeight(math.max(16, trackH * viewH / contentH))
		w.track:Show()
		w.thumb:Show()
	else
		w.track:Hide()
		w.thumb:Hide()
	end

	local H = head + viewH + 10
	w:SetSize(WIDTH, H)

	local parts = {
		{ name = T("Quests in der Nähe", "Quests nearby"), x = 0, y = 0, w = WIDTH, h = H, jump = "_pos" },
		{ name = T("Deckkraft der Fenster", "Window opacity"), x = 0, y = 0, w = 6, h = H, jump = T("Deckkraft der Fenster", "Window opacity") },
		{ name = T("Breite der Fenster", "Width of the windows"), x = WIDTH - 6, y = 0, w = 6, h = H, jump = T("Breite der Fenster", "Width of the windows") },
		{ name = T("Kopfzeile", "Header"), x = 0, y = 0, w = WIDTH, h = band, jump = T("Kopfzeile ausblenden", "Hide header") },
		{ name = T("Höhe der Liste", "List height"), x = 4, y = head + viewH, w = WIDTH - 8, h = 10, jump = T("Größte Höhe der Liste (darüber scrollen)", "Largest list height (scroll beyond)") },
	}
	if not cfg.hideHeaderNear then
		parts[#parts + 1] = { name = T("Höhe der Titelleiste", "Height of the title band"), x = 0, y = band - 5, w = WIDTH, h = 5, jump = T("Höhe der Titelleiste", "Height of the title band") }
		parts[#parts + 1] = { name = T("Knöpfe", "Buttons"), x = WIDTH - 30, y = 0, w = 30, h = band, jump = T("Knöpfe in der Titelleiste zeigen", "Show the buttons in the title band") }
	end
	parts[#parts + 1] = { name = T("Randfarbe", "Border color"), x = 0, y = H - 5, w = WIDTH, h = 5, jump = T("Randfarbe", "Border color") }
	parts[#parts + 1] = { name = T("Hintergrundfarbe", "Background color"), x = 5, y = H - 12, w = WIDTH - 10, h = 7, jump = T("Hintergrundfarbe", "Background color") }
	if not cfg.hideHeaderNear and cfg.showButtons ~= false then
		local mx, my, mw, mh = Measure(w, w.minFrame)
		if mx then parts[#parts + 1] = { name = T("Im Kampf", "In combat"), x = mx, y = my, w = mw, h = mh, jump = T("Im Kampf", "In combat") } end
	end
	-- Zeilenhöhe: Kopf jeder Quest; Fortschrittsbalken der Ziele
	local failed = false
	for i = 1, #entries do
		local row = w.rows[i]
		if row and row:IsShown() then
			local rx, rtop, rw, rh = Measure(w, row)
			if rx and rtop >= head and rtop + NEAR_ROW_H <= head + viewH then
				parts[#parts + 1] = { name = T("Zeilenhöhe", "Row height"), x = rx, y = rtop, w = rw, h = NEAR_ROW_H, jump = T("Zeilenhöhe", "Row height") }
				if cfg.showAccent ~= false then
					parts[#parts + 1] = { name = T("Farbstreifen", "Stripe"), x = rx, y = rtop, w = math.max(cfg.accentW or 3, 4), h = NEAR_ROW_H * 0.6, jump = T("Farbstreifen links zeigen", "Show the colored stripe on the left") }
					parts[#parts + 1] = { name = T("Breite", "Width"), x = rx, y = rtop + NEAR_ROW_H * 0.6, w = math.max(cfg.accentW or 3, 4), h = NEAR_ROW_H * 0.4, jump = T("Breite des Farbstreifens", "Width of the colored stripe") }
				end
				if i > 1 then
					parts[#parts + 1] = { name = T("Trennlinien", "Dividers"), x = rx, y = rtop - 2, w = rw, h = 4, jump = T("Trennlinien zeigen", "Show the dividers") }
				end
				if cfg.showDist ~= false then
					local dx, dy, dw, dh = Measure(w, row.kind.tex)
					if dx then parts[#parts + 1] = { name = T("Entfernung", "Distance"), x = dx, y = dy, w = dw, h = dh, jump = T("Entfernung zeigen", "Show the distance") } end
				end
			end
			for _, goal in ipairs(row.goals) do
				if goal:IsShown() then
					local cx, cy, cw, ch = Measure(w, goal.icon)
					if cx and cy + ch <= head + viewH then parts[#parts + 1] = { name = T("Kästchen", "Box"), x = cx - 1, y = cy - 1, w = cw + 2, h = ch + 2, jump = T("Kästchen vor den Zielen zeigen", "Show the boxes before the goals") } end
					local px, py, pw, ph = Measure(w, goal.pill.tex)
					if px and py + ph <= head + viewH then parts[#parts + 1] = { name = T("Zähler", "Counter"), x = px, y = py, w = pw, h = ph, jump = T("Zähler der Ziele zeigen", "Show the counters of the goals") } end
				end
			end
			if cfg.showBars ~= false then
				for _, goal in ipairs(row.goals) do
					local bx, by, bw, bh = Measure(w, goal.barBg)
					if bx and by + bh <= head + viewH then
						parts[#parts + 1] = { name = T("Fortschrittsbalken", "Progress bar"), x = bx, y = by - 3, w = bw, h = bh + 6, jump = T("Fortschrittsbalken der Ziele zeigen", "Show the progress bars of the goals") }
					elseif goal:IsShown() and not bx then
						failed = true
					end
				end
			end
		end
	end
	for i = 1, #entries do
		local row = w.rows[i]
		if row and row:IsShown() then
			local fx, fy, fw, fh = Measure(w, row.fs)
			if fx and fy + fh <= head + viewH then
				parts[#parts + 1] = { name = T("Schriftgröße", "Font size"), x = fx, y = fy, w = math.min(fw, 130), h = fh, jump = T("Schriftgröße", "Font size") }
			end
			if mates then
				local owners = { row }
				for _, goal in ipairs(row.goals) do owners[#owners + 1] = goal end
				for _, owner in ipairs(owners) do
					for _, chip in ipairs(owner.chips) do
						local kx, ky, kw, kh = Measure(w, chip)
						if kx and ky + kh <= head + viewH then
							parts[#parts + 1] = { name = T("Stand der Gruppenmitglieder", "Progress of group members"), x = kx, y = ky, w = kw, h = kh, jump = T("Stand der Gruppenmitglieder zeigen", "Show the progress of group members") }
						elseif not kx and chip:IsShown() then
							failed = true
						end
					end
				end
			end
		end
	end
	do
		-- die zweite Quest leuchtet regelmäßig auf: obere Kante = Stärke, untere Kante = Farbe
		local r2 = w.rows[2]
		local gx, gy, gw, gh = Measure(w, r2)
		if gx and gy + gh <= head + viewH then
			parts[#parts + 1] = { name = T("Stärke des Aufleuchtens", "Strength of the glow"), x = gx, y = gy, w = gw, h = 4, jump = T("Stärke des Aufleuchtens", "Strength of the glow") }
			parts[#parts + 1] = { name = T("Farbe des Aufleuchtens", "Color of the glow"), x = gx, y = gy + gh - 4, w = gw, h = 4, jump = T("Farbe des Aufleuchtens", "Color of the glow") }
		end
	end
	if w.track:IsShown() then
		local tx, ty, tw, th = Measure(w, w.track)
		if tx then parts[#parts + 1] = { name = T("Scrollbalken", "Scroll bar"), x = tx - 3, y = ty, w = tw + 6, h = th, jump = T("Scrollbalken zeigen", "Show the scroll bar") } end
	end
	if failed and not c.retry then
		c.retry = true
		C_Timer.After(0.1, Redraw)
	elseif not failed then
		c.retry = nil
	end
	return { w = WIDTH, h = H, parts = parts }
end

-- Quest-Aktionen --------------------------------------------------------------------------------

function S.targets(host, c)
	local api = SexyQuestHelperAPI
	local SEM = LibStub("SexyEditMode-1.0", true)
	local ui = SEM and SEM.ui
	if not (api and api.Sample and ui) then return nil end
	local st = api.Sample()
	local T = st.T
	local db = SexyQuestHelperDB and SexyQuestHelperDB.targets or {}
	local hide = (db.hideHeader or db.compact) and true or false   -- kompakt: keine Kopfzeile

	local HEAD, PAD = 28, 8
	local size, perRow, gap = db.iconSize or 28, db.perRow or 6, db.gap or 6
	local opacity = db.opacity or ui.BG[4] or 0.96
	local showCount = db.showCount ~= false
	local cc = db.countColor or { r = 0.94, g = 0.75, b = 0.29 }

	if not c.win then
		local w = CreateFrame("Frame", nil, host, BackdropTemplateMixin and "BackdropTemplate" or nil)
		w:SetPoint("TOPLEFT", host, "TOPLEFT")
		ui.Backdrop(w, ui.BG, ui.EDGE)
		w.band = w:CreateTexture(nil, "BACKGROUND", nil, 1)
		w.band:SetPoint("TOPLEFT", 3, -3)
		w.band:SetPoint("TOPRIGHT", -3, -3)
		w.band:SetHeight(HEAD - 3)
		w.band:SetColorTexture(ui.BAND[1], ui.BAND[2], ui.BAND[3], ui.BAND[4] or 1)
		w.title = ui.Text(w, "GameFontNormal", 14)
		w.title:SetPoint("LEFT", w.band, "LEFT", 8, 0)
		w.title:SetTextColor(ui.GOLD[1], ui.GOLD[2], ui.GOLD[3])
		w.title:SetText(T("Quest-Aktionen", "Quest actions"))
		w.icons = {}
		c.win = w
	end
	local w = c.win
	w.band:SetShown(not hide)
	w.title:SetShown(not hide)
	w:SetBackdropColor(ui.BG[1], ui.BG[2], ui.BG[3], opacity)
	w.band:SetColorTexture(ui.BAND[1], ui.BAND[2], ui.BAND[3], opacity)

	local compact = db.compact and true or false
	local groupBy = db.groupByQuest ~= false and not compact and true or false
	if compact then hide = true; gap = math.min(gap, 3) end
	local HEAD_H, SEC_GAP = 22, 8
	local headGap = db.headGap or 6
	-- Gruppenzeile wie in SexyHarvester: dunkles Band über die Breite, links das Etikett (Badge) mit dem Questnamen
	local TONES = {
		{ bg = { 0.082, 0.188, 0.11 }, fg = { 0.48, 0.88, 0.56 } },
		{ bg = { 0.227, 0.173, 0.063 }, fg = { 0.94, 0.75, 0.29 } },
		{ bg = { 0.078, 0.157, 0.227 }, fg = { 0.53, 0.8, 1 } },
	}
	local list = {
		{ name = T("Beispiel-Monster", "Sample mob"), have = 3, need = 8, quest = T("Beispiel-Quest", "Sample quest") },
		{ name = T("Noch ein Monster", "Another mob"), have = 0, need = 5, quest = T("Beispiel-Quest", "Sample quest") },
		{ name = T("Drittes Monster", "Third mob"), have = 5, need = 5, quest = T("Andere Quest", "Other quest") },
		{ name = T("Quest-Gegenstand", "Quest item"), have = 0, need = 0, quest = T("Andere Quest", "Other quest"), icon = 134414 },
	}
	local head = hide and 4 or HEAD
	local fixedW = db.width or 0
	if fixedW > 0 then fixedW = math.max(120, fixedW) end
	local perRowEff = fixedW > 0 and math.max(1, math.floor((fixedW - 2 * PAD + gap) / (size + gap))) or perRow
	local cell = size + ((showCount and not compact) and 15 or 0)

	-- Abschnitte wie im echten Fenster: bei "Nach Quests gruppieren" je Quest eine Überschrift
	local sections, byKey = {}, {}
	for _, g in ipairs(list) do
		local key = groupBy and g.quest or ""
		local sec = byKey[key]
		if not sec then
			sec = { title = groupBy and g.quest or nil, items = {} }
			byKey[key] = sec
			sections[#sections + 1] = sec
		end
		sec.items[#sec.items + 1] = g
	end
	local pos, heads, maxCols, y, idx = {}, {}, 1, head + 4, 0
	for _, sec in ipairs(sections) do
		local cols = math.max(1, math.min(#sec.items, perRowEff))
		maxCols = math.max(maxCols, cols)
		if sec.title then
			heads[#heads + 1] = { title = sec.title, y = y, dist = ({ 24, 51, 88 })[#heads + 1] }
			y = y + HEAD_H + headGap
		end
		for i, g in ipairs(sec.items) do
			idx = idx + 1
			pos[idx] = { g = g, x = PAD + ((i - 1) % cols) * (size + gap), y = y + math.floor((i - 1) / cols) * (cell + gap), last = (i - 1) % cols == cols - 1 or i == #sec.items }
		end
		local lines = math.ceil(#sec.items / cols)
		y = y + lines * cell + (lines - 1) * gap + SEC_GAP
	end
	local n = idx
	local W = fixedW > 0 and fixedW or math.max(2 * PAD + maxCols * size + (maxCols - 1) * gap, hide and 0 or 130)
	local H = math.max(head + 4, y - SEC_GAP) + PAD

	w.heads = w.heads or {}
	for i, h in ipairs(heads) do
		local hf = w.heads[i]
		if not hf then
			hf = CreateFrame("Frame", nil, w)
			hf:SetHeight(HEAD_H)
			hf.bg = hf:CreateTexture(nil, "BACKGROUND", nil, 1)
			hf.bg:SetAllPoints()
			hf.pill = hf:CreateTexture(nil, "ARTWORK")
			hf.pill:SetPoint("LEFT", hf, "LEFT", 6, 0)
			hf.pill:SetHeight(16)
			hf.label = ui.Text(hf, "GameFontHighlightSmall", 12)
			hf.label:SetPoint("CENTER", hf.pill, "CENTER")
			hf.label:SetWordWrap(false)
			hf.distBg = hf:CreateTexture(nil, "ARTWORK")
			hf.distBg:SetHeight(16)
			hf.distBg:SetPoint("RIGHT", hf, "RIGHT", -6, 0)
			hf.distBg:SetColorTexture(0.078, 0.157, 0.227, 1)
			hf.distText = ui.Text(hf, "GameFontHighlightSmall", 11)
			hf.distText:SetPoint("CENTER", hf.distBg, "CENTER")
			hf.distText:SetTextColor(0.53, 0.8, 1)
			w.heads[i] = hf
		end
		local tone = TONES[(i - 1) % #TONES + 1]
		hf:ClearAllPoints()
		hf:SetPoint("TOPLEFT", w, "TOPLEFT", 4, -h.y)
		hf:SetWidth(W - 8)
		hf.bg:SetColorTexture(ui.BAND[1], ui.BAND[2], ui.BAND[3], opacity)
		hf.pill:SetColorTexture(tone.bg[1], tone.bg[2], tone.bg[3], 1)
		hf.label:SetTextColor(tone.fg[1], tone.fg[2], tone.fg[3])
		hf.label:SetText(h.title)
		-- Entfernung als Etikett rechts (Einstellung "Entfernung zeigen")
		local showDist = db.showDist ~= false and h.dist
		hf.distBg:SetShown(showDist and true or false)
		hf.distText:SetShown(showDist and true or false)
		h.distW = 0
		if showDist then
			hf.distText:SetText(h.dist .. " m")
			h.distW = hf.distText:GetStringWidth() + 14
			hf.distBg:SetWidth(h.distW)
		end
		local pw = math.min(hf.label:GetStringWidth() + 18, W - 8 - 12 - (h.distW > 0 and (h.distW + 8) or 0))
		hf.pill:SetWidth(pw)
		hf.label:SetWidth(pw - 10)
		hf:Show()
	end
	for i = #heads + 1, #w.heads do w.heads[i]:Hide() end

	for i, p in ipairs(pos) do
		local g = p.g
		local ic = w.icons[i]
		if not ic then
			ic = CreateFrame("Frame", nil, w)
			ic.edge = ic:CreateTexture(nil, "BACKGROUND")
			ic.edge:SetAllPoints()
			ic.edge:SetColorTexture(ui.EDGE[1], ui.EDGE[2], ui.EDGE[3], 1)
			ic.bg = ic:CreateTexture(nil, "BACKGROUND", nil, 1)
			ic.bg:SetPoint("TOPLEFT", 1, -1)
			ic.bg:SetPoint("BOTTOMRIGHT", -1, 1)
			ic.bg:SetColorTexture(ui.ROWBG[1], ui.ROWBG[2], ui.ROWBG[3], 1)
			ic.icon = ic:CreateTexture(nil, "ARTWORK")
			ic.icon:SetPoint("TOPLEFT", 2, -2)
			ic.icon:SetPoint("BOTTOMRIGHT", -2, 2)
			ic.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
			ic.skull = ic:CreateTexture(nil, "ARTWORK")
			ic.skull:SetPoint("TOPLEFT", 5, -5)
			ic.skull:SetPoint("BOTTOMRIGHT", -5, 5)
			ic.skull:SetTexture("Interface/TargetingFrame/UI-RaidTargetingIcon_8")
			ic.over = CreateFrame("Frame", nil, ic)
			ic.over:SetAllPoints()
			ic.over:SetFrameLevel(ic:GetFrameLevel() + 5)
			ic.count = ui.Text(ic.over, "GameFontHighlightSmall", 12)
			ic.count:SetPoint("TOP", ic, "BOTTOM", 0, -2)
			w.icons[i] = ic
		end
		ic.icon:SetShown(g.icon ~= nil)
		if g.icon then ic.icon:SetTexture(g.icon) end
		ic.skull:SetShown(g.icon == nil)
		ic:ClearAllPoints()
		ic:SetPoint("TOPLEFT", w, "TOPLEFT", p.x, -p.y)
		ic:SetSize(size, size)
		ic.count:SetShown(showCount and g.need > 0)
		ic.count:ClearAllPoints()
		if compact then ic.count:SetPoint("BOTTOMRIGHT", ic, "BOTTOMRIGHT", -3, 3) else ic.count:SetPoint("TOP", ic, "BOTTOM", 0, -2) end
		ic.count:SetTextColor(cc.r, cc.g, cc.b)
		ic.count:SetText(g.have .. "/" .. g.need)
		ic:Show()
	end
	for i = n + 1, #w.icons do w.icons[i]:Hide() end
	w:SetSize(W, H)

	local parts = {
		{ name = T("Quest-Aktionen", "Quest actions"), x = 0, y = 0, w = W, h = H, jump = "_pos" },
		{ name = T("Deckkraft des Fensters", "Window opacity"), x = 0, y = 0, w = 5, h = H, jump = T("Deckkraft des Fensters", "Window opacity") },
		{ name = T("Breite", "Width"), x = W - 5, y = 0, w = 5, h = H, jump = T("Breite", "Width") },
		{ name = T("Kopfzeile", "Header"), x = 0, y = 0, w = W, h = head, jump = T("Kopfzeile ausblenden", "Hide header") },
	}
	for _, h in ipairs(heads) do
		parts[#parts + 1] = { name = T("Nach Quests gruppieren", "Group by quest"), x = 4, y = h.y, w = W - 8, h = HEAD_H, jump = T("Nach Quests gruppieren", "Group by quest") }
		if h.distW and h.distW > 0 then
			parts[#parts + 1] = { name = T("Entfernung zeigen", "Show distance"), x = W - 4 - 6 - h.distW, y = h.y + 3, w = h.distW, h = 16, jump = T("Entfernung zeigen", "Show distance") }
		end
	end
	for _, h in ipairs(heads) do
		parts[#parts + 1] = { name = T("Abstand unter der Gruppenzeile", "Space below the group row"), x = 4, y = h.y + HEAD_H, w = W - 8, h = math.max(headGap, 4), jump = T("Abstand unter der Gruppenzeile", "Space below the group row") }
	end
	for _, p in ipairs(pos) do
		parts[#parts + 1] = { name = T("Symbolgröße", "Icon size"), x = p.x, y = p.y, w = size, h = size, jump = T("Symbolgröße", "Icon size") }
		if showCount then
			local cy = compact and (p.y + size - 15) or (p.y + size)
			parts[#parts + 1] = { name = T("Zähler", "Counter"), x = p.x, y = cy, w = size / 2, h = 15, jump = T("Zähler zeigen", "Show the counter") }
			parts[#parts + 1] = { name = T("Farbe des Zählers", "Counter color"), x = p.x + size / 2, y = cy, w = size / 2, h = 15, jump = T("Farbe des Zählers", "Counter color") }
		end
		if not p.last and gap > 0 then
			parts[#parts + 1] = { name = T("Abstand der Symbole", "Icon spacing"), x = p.x + size, y = p.y, w = gap, h = cell, jump = T("Abstand der Symbole", "Icon spacing") }
		end
	end
	return { w = W, h = H, parts = parts }
end
