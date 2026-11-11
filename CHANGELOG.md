# Changelog

## 1.0.13
- New fonts: Marcellus for the title, Inter for all other text (bundled, SIL Open Font License). Clients in Russian, Korean and Chinese keep the game font

## 1.0.12
- New window design with player cards (class-colored avatar, status label, quest labels, Share button)
- When the window opens automatically only players with differences are shown; opening it manually with /sqh shows all players

## 1.0.11
- Optional dependency on the QuestieDB addon: prerequisite quests, exclusive quests, quest-chain progress and minimum level are checked from its data, so quests a member cannot accept are no longer reported

## 1.0.10
- Quests a member cannot accept (e.g. missing prerequisite quest) are no longer reported as differences and get no Share button. Uses the Questie database when installed; otherwise the addon learns from the "not eligible" message after the first share attempt

## 1.0.9
- Group members without the addon are no longer listed in the window (`/sqh version` still shows them)

## 1.0.8
- Versions are no longer shown in the window; new command `/sqh version` lists the addon version of every group member and whether they are up to date

## 1.0.7
- Fix: quests accepted at the same time were briefly (or permanently) reported as missing. Differences must now persist for 4 seconds before the window opens, and quest accept/remove/turn-in always trigger a scan

## 1.0.6
- Quests that a member already turned in (e.g. because they hold the follow-up quest) are no longer reported as differences; clients tell each other which quests they have already completed

## 1.0.5
- Player names are shown in class colors
- New "Share" button on quests you have and others lack (only when the quest can be shared)

## 1.0.4
- Fix: zones are now compared by map ID instead of the (localized) zone name, so players with different client languages match

## 1.0.3
- Addon users now broadcast their addon version; it is shown next to each group member (members on older versions are marked "old version")
- The window title shows your own version

## 1.0.2
- Fix: sender names on WoW Forever use "Name Realm" (space instead of dash), so group members were never matched
- `/sqh debug` now prints a compact 3-line summary (`/sqh debug log` lists the quest log)

## 1.0.1
- Fix: group channel detection (addon messages were sent to INSTANCE_CHAT and never arrived, so everyone showed as "no addon")
- Request/reply sync so members who reload at the same time still find each other
- Startup errors and scan errors are now reported; `/sqh debug` shows message counters

## 1.0.0
- Initial release
- Compares the quests of your current zone with all group members running the addon
- Window appears only when quests differ, listing what you lack and what they lack
- Quest tooltips, click to open in quest log, shift-click to link in chat
- English and German localization
