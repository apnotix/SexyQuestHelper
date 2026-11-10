# SexyQuestHelper

**Does your whole group have the same quests? Find out at a glance.**

SexyQuestHelper compares the quests of the zone you are currently in with every party or raid member who also runs the addon. As soon as someone is missing a quest (or has one you don't), a small window pops up and shows exactly what differs. If everyone is in sync, it stays out of your way.

Works on **World of Warcraft: Forever** and **Retail**.

## Features

- **Only shows up when it matters** - the window appears automatically when quests differ and hides itself when everyone is in sync.
- **Clear differences per player** - for each group member you see which quests *you lack* and which quests *they lack*.
- **Quest tooltips** - hover a quest to see its tooltip.
- **Click to jump** - click a quest to open it in your quest log. Shift-click inserts a quest link into the chat.
- **Zone based** - only quests of your current zone are compared, so you don't get flooded.
- **Lightweight** - no library dependencies, tiny addon message traffic (only sent when something changes).
- **Movable window** - drag it wherever you like, the position is saved. Close it to dismiss the current differences; it returns when they change.
- **English and German** localization.

## How it works

Every player running the addon sends the quest IDs of the current zone to the group over hidden addon messages. Each client compares its own list with the received ones. Group members without the addon are shown as "no addon / no data". Only players who have SexyQuestHelper installed can be compared.

## Slash commands

| Command | Description |
|---|---|
| `/sqh` | Show or hide the window (also when there are no differences) |
| `/sqh refresh` | Re-scan your quest log and re-send it to the group |
| `/sqh test` | Toggle a simulated group member to preview the display |
| `/sqh version` | Show the addon version of every group member and whether they are up to date |
| `/sqh check <questID>` | Show whether you can accept a quest and its prerequisite data (needs the QuestieDB addon) |
| `/sqh debug` | Print diagnostics (detected zone, quests, addon message counters) |

## Notes

- Every group member needs the addon to be compared.
- Quests are matched by the quest log category that has the same name as your current zone.
- Please report bugs and feedback via the issue tracker.
