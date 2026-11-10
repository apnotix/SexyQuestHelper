# Changelog

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
