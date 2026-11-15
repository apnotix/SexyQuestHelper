# SexyQuestHelper

![WoW Forever](https://img.shields.io/badge/WoW-Forever-e8c26a?style=for-the-badge) ![WoW Retail](https://img.shields.io/badge/WoW-Retail-c8a24a?style=for-the-badge) ![Interface](https://img.shields.io/badge/Interface-120100%20%7C%2016001-3b2b12?style=for-the-badge)

**Does your whole group have the same quests? Find out at a glance.**

SexyQuestHelper compares the quests of your current zone with every party or raid member who also runs the addon. As soon as someone lacks a quest (or has one you don't), a small window shows exactly what differs. When everyone is in sync, it stays out of your way.

Works on **World of Warcraft: Forever** and **Retail**. Styled like the other Sexy addons: dark brown panel, gold frame, title band with the zone as badge.

## Features

- 🔔 **Shows up when it matters** - the window opens when quests differ and closes when everyone is in sync. Close it to dismiss the current differences; it returns when they change.
- 👥 **Differences per player** - which quests *you lack* and which *they lack*.
- 🤝 **Help your group** - a second window shows quests you have already finished that a member still has, with their single goals and progress. Click a member to whisper or target. Optional, switched on in Edit Mode. Handy when you want to help someone along.
- 📍 **Quests nearby** - an optional third window lists your open quests whose goals are within range of where you stand, with the single goals. Uses the QuestieDB addon for the goal positions.
- 📜 **Quest tooltips and links** - hover for the tooltip, click to open the quest in your log, Shift-click to link it in chat.
- 🤝 **Share button** - share a quest with the group right from the list (greyed out in combat).
- 🗺️ **Zone based** - only the quests of your current zone are compared.
- 🪶 **Light** - no dependencies, addon messages only when something changes.

## Edit Mode

Move and scale the window in Edit Mode (it shows sample data there), or simply drag it. Settings:

- Delay before the window appears (1 - 10 s)
- Close automatically after 0 - 60 s
- Sound when the window appears
- Chat note about what is missing
- Hide the zone in the title
- Size (50 - 200 %) and visibility (hide, hide in combat, mouseover)

## Commands

| Command | Description |
|---|---|
| `/sqh` | Show or hide the window |
| `/sqh help` | Show or hide the "Help your group" window |
| `/sqh refresh` | Re-scan your quest log and re-send it to the group |
| `/sqh test` | Toggle a simulated group member to preview the display |
| `/sqh version` | Show every group member's addon version |

Long form: `/sexyquesthelper`

## Notes

- Every group member needs the addon to be compared; others show as "no addon / no data".
- After a login or reload the window waits about 10 seconds and syncs again before it opens by itself.
- Fonts: Marcellus and Inter are bundled (SIL Open Font License).
- Bug reports and ideas are welcome on GitHub.

## Credits

The own SexyEditMode library (embedded). Fonts: Marcellus and Inter (SIL Open Font License 1.1).

## 🇩🇪 Deutsch

**SexyQuestHelper** vergleicht die Quests deines Gebiets mit allen Gruppenmitgliedern, die das Addon nutzen, und zeigt, was abweicht.

- Fenster erscheint nur bei Unterschieden, Quests per Klick im Questlog öffnen oder in den Chat verlinken
- Zweites Fenster „Mitspielern helfen“: zeigt den Fortschritt von Quests, die du schon erledigt hast
- Quest mit einem Klick teilen (nicht im Kampf)
- Im Edit Mode platzierbar, mit Einstellungen für Verzögerung, automatisches Schließen, Ton und Chat-Hinweis
- Funktioniert auf Deutsch und Englisch

Ausführliche deutsche Beschreibung: https://github.com/apnotix/SexyQuestHelper
