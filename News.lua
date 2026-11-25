-- Neuigkeiten für das gemeinsame Fenster (SexyEditMode, /sem news). Neueste Version zuerst.
-- Eintrag: { deutscher Titel, deutscher Text, englischer Titel, englischer Text }
local SEM = LibStub and LibStub("SexyEditMode-1.0", true)
if not (SEM and SEM.RegisterNews) then return end

SEM:RegisterNews("SexyQuestHelper", {
	color = { 0.42, 0.71, 1 },
	{ v = "1.0.30",
		{ "Quests in der Nähe", "Zwei Reiter unter dem Titel: „Aktiv“ und „Ausgeblendet“. Der zweite zeigt ausgeblendete Quests wie die normalen Zeilen; Rechtsklick blendet sie wieder ein. Quests, die nicht mehr im Questlog stehen, verschwinden aus der Liste.",
		  "Quests nearby", "Two tabs under the title: \"Active\" and \"Hidden\". The second shows hidden quests as normal rows; right-click shows them again. Quests that are no longer in the quest log drop out of the list." },
		{ "Mitspielern helfen", "Die kleine Ansicht zeigt jetzt, wer was braucht: je Mitspieler eine Zeile mit seinen Quests und dem Stand.",
		  "Help your group", "The small view now shows who needs what: one line per member with his quests and progress." },
		{ "Quest-Aktionen", "Nur Quests in Reichweite von „Quests in der Nähe“ (bis 300 m), höchstens 6 Symbole je Quest, graue Symbole solange der Mob nicht da ist, Mobs in der Nähe zuerst. Rechtsklick postet „Brauche: Mob 6/10“ in den Gruppenchat. Ausgeblendete Quests erscheinen nicht mehr.",
		  "Quest actions", "Only quests within the range of \"Quests nearby\" (up to 300 m), at most 6 icons per quest, gray icons while the mob is not nearby, nearby mobs first. A right-click posts \"Need: mob 6/10\" to the group chat. Hidden quests no longer show up." },
		{ "Chat-Meldungen", "Questfortschritt melden: Aus, Zwischenziele oder Alle, dazu Zusammenfassen mehrerer Änderungen in eine Zeile.",
		  "Chat messages", "Report quest progress: Off, Intermediate goals or All, plus combining several changes into one line." },
		{ "Teilen", "Neu: „Fehlende Quests automatisch teilen“ (aus, sparsam und nie im Kampf). Wer eine Quest abgibt, meldet das sofort, damit sie bei ihm nicht mehr als „Hat nicht“ erscheint.",
		  "Sharing", "New: \"Share missing quests automatically\" (off by default, sparing, never in combat). Whoever turns in a quest reports it at once so it no longer shows as \"Lacks\"." },
		{ "Einstellungen", "Die Fenster stehen in der Seitenleiste unter Gruppe, Quests und Verwaltung.",
		  "Settings", "The windows are grouped in the sidebar under Group, Quests and Manage." },
		{ "Quest-Aktionen", "Das frühere Fenster „Ziel-Mobs“ zeigt die Monster deiner Quests als Symbole. Ein Klick visiert an und markiert mit dem Totenkopf; benutzbare Quest-Items erscheinen ebenfalls.",
		  "Quest actions", "The former \"Target mobs\" window shows the mobs of your quests as icons. A click targets and marks with the skull; usable quest items show up as well." },
		{ "Gruppieren und sortieren", "Nach Quests gruppieren, nach Entfernung sortieren, Gruppen einklappen, maximale Höhe mit Scrollen, einstellbare Breite und ein kompakter Modus.",
		  "Grouping and sorting", "Group by quest, sort by distance, collapse groups, maximum height with scrolling, adjustable width and a compact mode." },
		{ "Gruppenziele", "Texte von Gruppenmitgliedern erscheinen in deiner Sprache. Dafür brauchen die anderen die neue Version.",
		  "Group goals", "Goal texts of group members appear in your language. The others need the new version for this." },
		{ "Korrekturen", "Lange Zieltexte verdecken Gruppenmitglieder in „Quests in der Nähe“ nicht mehr; der Fehler mit geheimen Werten beim Wechsel des Ziels ist behoben.",
		  "Fixes", "Long goal texts no longer hide group members in \"Quests nearby\"; the secret value error when changing the target is fixed." },
	},
})
