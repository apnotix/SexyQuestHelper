# Changelog

## 1.0.15
- "Help your group": each quest now lists the individual goals ("Wolves slain: 5/8") of the member, finished ones in green. Click a member's header: left click whispers, right click targets (not in combat). The goal texts travel in two new message types (older versions ignore them)- Sharing a quest no longer prints "Quest shared" to chat; only errors are reported
- New second window "Help your group": lists quests you have already finished (handed in, or only waiting to be handed in) that a group member in your zone still has, with their progress per quest (percent, or "Ready"). It is off by default: turn it on in the Edit Mode dialog, then it opens by itself. It can be placed and scaled in Edit Mode, is toggled with /sqh help and sends progress over a new message type. Quests you still have in your log are not listed (unless you turn on "also count quests you only have to hand in"); older versions simply ignore it.

## 1.0.14
- After a login or /reload the window no longer reports "You lack ..." for quests you already have: the quest log is still incomplete right then, so the window waits about 10 s and syncs with the group again (re-scan, resend, re-request) before it may open on its own
- New options in the Edit Mode dialog: delay before the window appears (1-10 s, was fixed 4 s), close automatically after 0-60 s, sound when appearing, chat note about what is missing, hide the zone in the title
- In combat the Share button is greyed out and reads "Combat" (hover for a hint); it re-enables when the fight ends
- Edit Mode: The window can now be selected, moved and scaled in Edit Mode (dialog with "Position and size" and "Visibility" from the own SexyEditMode library) and shows sample data while editing. The saved position is carried over; dragging the window still works anytime. The top edge stays put when the window grows.

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
