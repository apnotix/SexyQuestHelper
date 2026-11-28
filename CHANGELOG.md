# Changelog

## 1.0.35
- Item and sword icons in the goal lists get a thin light frame like the icons in SexyHarvester (big and small view, and in the previews).
- "Quests nearby": finished goals are gray and struck through (big and small view). A goal that wraps onto a second line is only grayed. The preview shows a finished goal.
- New setting "In dungeons and raids" for every window (Quest actions, Quests nearby, Help your group, the main window): show normally, small view (compact mode for the quest actions) or hide. Next to "In combat" in the behavior section. It follows the instance type (dungeon and raid, not battlegrounds or arenas).
- Kill goals ("Wolves slain: 3/8") show a sword icon in place of the check box in "Quests nearby" (big and small view) and "Help your group", like item goals show their item. Finished goals are grayed out. The previews show it too.
- Item icons in the big views are as tall as the goal text plus its progress bar (up to 18 px), no longer the size of a check box. The small view keeps its icon size.
- "Help your group": the small view lists every goal of a member's quest with its progress (like "Quests nearby") instead of one percentage per quest, and the big view no longer shows the percentage badge on a quest (only "Ready"). The preview follows.
- "Quests nearby": goals that ask for an item ("Wolf pelt: 3/8") show the item's icon in place of the check box. The icon comes from QuestieDB (item IDs of the quest, matched by the name in the goal text), without it through the item name when the game knows the item (e.g. in your bags). A finished goal is grayed out. The preview in the settings window shows it too. The small view shows the icon in front of the goal as well, and so does "Help your group" (matched through QuestieDB there) and its preview.
- "Quests nearby": group members no longer show only a percentage when their goals are known: if the number of goals differs from yours (for example your quest log is not loaded yet right after a reload) the goals are matched by name, otherwise the sum of all goals ("7/16") is shown. After a reload the addon also asks members whose goals are still missing (up to three times each).
- "Quest actions": the window width is 200 px by default (before: automatic). A width you set yourself stays; 0 still means automatic.
- "Quest actions": the mob avatars are still 2D pictures by default now (before: moving 3D models). The picture is drawn once from the creature, like the Dungeon Journal does: the addon looks up the creature's display ID with a hidden model (one at a time, remembered), draws the picture off screen and puts it into the icon after a few seconds; until then the skull stays. A mob you target, mouse over or see on a nameplate gets its picture at once from that unit (like RestedXP's "Active Targets"). That saves the graphics card the many 3D models. New option "Moving 3D models instead of still pictures" (off by default) brings the old look back.
- "Quest actions": with "Hide" or "Hide in combat" the window is hidden completely now. Before it was only transparent, so the icons still took mouse clicks (and ran their macro) where nothing was visible.

## 1.0.33
- "Quest actions": new option "Ping the targeted mob (Blizzard ping)" (on by default). Clicking an icon or using a hotkey then also sends the game's ping to the mob, so the group sees where it is. Needs the client's ping command; in a raid only for the leader and assistants.
- "Quest actions": new defaults: "Group by quest" and the ping are on, the icon size is 28 px. Settings you already changed stay.
- "Quest actions": up to 5 keys, set in the settings (section "Hotkeys"). Key n targets the next free mob of the nth quest in the window; every further press goes to the next one. Mobs already tagged by others are skipped (checked on the nameplates, so it only covers mobs within nameplate range). Out of combat only; in combat the key keeps the last target. No default keys.
- Icons stay gray while the only mobs nearby are tagged by others.
- Chat messages: without a group (channel "Group") or guild (channel "Guild") nothing is reported any more, so progress and turn-in lines no longer appear in your own chat window.

## 1.0.30
- "Quests nearby": two tabs under the title band, "Active" and "Hidden (n)". The tab "Hidden" lists the hidden quests as normal rows (goals, counters, bars, group progress) with the label "hidden" or "not in log"; a right-click shows a quest again. The window stays open on that tab until you close it. In the small view there are no tabs. The preview in the settings window shows the tabs too.
- Hidden quests that are not in your quest log any more (turned in, abandoned) are removed from the list automatically, once the quest log has been read.
- Hidden quests do not show up in "Quest actions" any more; hiding or showing a quest rebuilds that window right away.
- "Help your group": the small view lists who needs what now, like "Quests nearby": one line per member (class color, number of quests) and below it his quests with the progress; "Nobody needs help right now." as before.
- "Quest actions": only quests whose nearest goal is within the range of "Quests nearby" are shown (switch "Only quests within the range of \"Quests nearby\"", on by default; unknown locations always show). The range slider of "Quests nearby" goes up to 300 m now. The check runs every 2 seconds while you walk.
- "Quest actions": new setting "Maximum icons per quest" (2 to 16, default 6) so a quest with many drop sources does not push out the others; the window itself shows up to 40 icons (was 16).
- "Quest actions": icons are gray while the mob is not nearby and turn colored as soon as it has a nameplate (enemy nameplates must be on); a targeted or moused-over mob counts as nearby too. Setting "Gray icons while the mob is not nearby" (on by default). Use /sqhtargets to see how many nameplates and names were read.
- "Quest actions": new setting "Nearby mobs first" (on by default): within a quest the mobs that are nearby come first; the window rebuilds when that changes (not in combat).
- "Quest actions": a right-click on a mob icon posts "Need: mob (quest) 6/10" into the party, raid or instance chat (nothing happens when you are alone). The chat channel is chosen when the window is built and follows group changes.
- "Quest actions": the 3D pictures of the mobs follow the window opacity now, so "Hide in combat" hides them as well.
- Fix "Quest actions": a goal that needs several items (e.g. 10 from bears and 1 from a spider) showed the count of the first goal for every mob. Each mob now gets the count of its own goal. The sources of one item goal go up to 16 mobs (was 6, read from the first 60 database entries; now 200), and a mob without any spawn data in QuestieDB is no longer hidden.
- "Quest actions": the description in the settings window is one line now.
- Chat messages: the two switches for quest progress are one choice now, "Report quest progress": Off, Intermediate goals (only when a goal of a quest is completed) or All (every count). Your old settings carry over. Fix: "Only completed goals" did nothing while "every goal" was off. New switch "Combine the changes of a quest into one line" (on by default, collects for 2 seconds). If sending fails the message appears in your own chat window.
- Group sync: new setting "Share missing quests automatically" (off by default). It shares what a group member in your zone lacks, never in combat, one quest every 4 seconds and the same quest again only after 10 minutes. Quests the member turned in, cannot accept or that you hid are left out.
- Group sync: when someone turns in a quest the group is told at once (message "turned in"), so a friend who already finished a quest no longer shows as "Lacks" with a Share button. Needs the new version on both sides.
- Settings window: the windows are grouped in the sidebar under "Group" (group sync, help your group), "Quests" (quests nearby, quest actions) and "Manage" (chat messages, hidden quests).
- Share button and the buttons of "Hidden quests" look like the buttons of the other Sexy addons: title band color, gold text, thin gold border (one screen pixel).
- Internal: state variables moved into one table (Lua allows 200 locals per file; the file hit the limit and the addon failed to load).
- "Quest actions": new setting "Only target living mobs" (on by default). If the click finds a dead mob (corpse), the macro targets again to jump to the next mob with the same name; if only corpses are left, the target is cleared and nothing is marked.
- Fix "Quest actions": the distance on the quest rows now updates every 2 seconds while you walk (before, it only changed when the window was rebuilt).
- "Quest actions": the distance is a label on the quest row like in "Quests nearby" (blue, "24 m"), can be switched off with "Show distance" and is shown in the preview too (click area; it only shows with "Group by quest"). The collapse mark "[-]" is gone (collapsed groups look dimmed).
- "Help your group" and "Quests nearby": goal texts of group members come from their client and were shown in their language (German text on an English client). The language is sent along now (new entry, older versions ignore it); texts in another language are replaced by "Goal 1: 3/8" (counts only). Quest names always came from the quest ID and were already in your language. The other members need the new version for this.
- "Quest actions": the width can be set ("Width", 120 to 600 px, 0 = automatic). With a fixed width the number of icons per row follows from it ("Icons per row" then does not apply); the right edge of the window is a click area in the preview.
- "Quest actions": the quests are sorted by distance now (nearest goal first, distance from the QuestieDB locations as in "Quests nearby"; quests without a known location come last). The quest row shows the distance in meters. While you walk the window rebuilds only when the order changes, and never in combat. Can be turned off with "Sort by distance".
- "Quest actions" grows less: new setting "Maximum height" (the list scrolls with the mouse wheel above it, scroll bar on the right), click on a quest row ("Group by quest") collapses or expands the group (shows the number of mobs, remembered), and a new "Compact mode" (no title band, no quest rows, tight spacing, the counter sits in the icon). Collapsing and scrolling wait until after combat because the buttons are secure.
- "Quest actions": the window title is left aligned again (it was centered); hovering the quest row ("Group by quest") shows the quest tooltip, and the tooltip of a mob icon names its quest.
- Fix "Quests nearby": a group member with the addon was not shown when a goal text was long. The goal texts sent to the group were cut at 44 characters, which cut off the count ("... 0/1") and made the progress unreadable for the others. Now the count stays and only the name is shortened. The other members need the new version too.
- Fix: error "attempt to perform string conversion on a secret string value" when changing the target (Tab targeting): the creature ID is only learned from values that are not secret; the target highlight is guarded the same way.
- "Quest actions": the icon of the mob you currently have targeted gets a gold, thicker border.
- "Target mobs" / "Quest actions": the skull marking uses the slash command /tm 8 now instead of a script (a script made the button insecure: "ForceTaint_Strong ... blocked"); it is on by default and can be turned off with "Mark the targeted mob with the skull".
- The window "Target mobs" is now called "Quest actions" (it also shows usable quest items). Your settings stay.
- "Target mobs": a quest item that your quest log lets you use (the button in the quest log) shows up as an icon in the window while you are in the quest zone; a click uses it (setting "Show usable quest items", on by default). The count is not shown for these.
- "Target mobs": after a click targets the mob it is marked with the skull (setting "Mark the targeted mob with the skull", on by default). Only hostile targets that do not carry the skull yet are marked.
- "Target mobs": the space below the group row (with "Group by quest") is a setting now and a click area in the preview.
- "Target mobs": mobs that drop a quest item now get their 3D picture right away (creature ID from QuestieDB), not only after you targeted them once.
- "Target mobs": new checkbox "Group by quest": each quest gets a small heading with its mobs below it (a mob needed for two quests appears under both). The preview shows it with its own click area.
- "Target mobs": goals that are not real mobs of the zone (summoned pets, event goals such as "Eye of Kilrogg guided to the road") get no button any more (checked against QuestieDB spawns).
- "Quests nearby": also lists quests that the quest log files under another zone (accepted elsewhere, e.g. in a city, with goals in the zone you are in).
- "Target mobs": a quest that you accepted in another zone (listed there in the quest log, e.g. Thunder Bluff) now shows up when its goals are in the zone you are in (needs QuestieDB). Without QuestieDB, turn off "Only quests of this zone".
- "Target mobs" now looks like "Active Targets" in Rested XP: one icon per mob (3D picture of the mob once you have targeted or moused over it, a skull before that) with the counter; a click on an icon targets the mob. New settings: icon size, icons per row, icon spacing. /sqhtargets prints what the window found in your quest log (for debugging).
- "Target mobs" is now on by default (it never appeared because it had to be switched on first); the zone check also knows zones with a different log name (Alterac Mountains = Hillsbrad).
- Settings window: all four windows have their own preview window with its own logic (new file Samples.lua: needs a full client restart): the window as it looks with invented members, quests, goals and group chips; hover a part, click to jump to its setting. The look settings sit in the first group, behavior in the next ones.
- New look settings: width of the windows, row height, gap between the cards, window opacity (all three list windows), the share button and the labels on the quests (group sync), the progress bars of the goals (help your group, quests nearby). Each one has its own spot in the preview.
- More look settings: font size, height of the title band, background and border color, the class icon (show, size), the labels of the members, the colored stripe (show, width), the dividers, the distance, the boxes and counters of the goals, the buttons in the title band, the scroll bar, color and strength of the glow of a new quest. "Target mobs": width, row height, window opacity, counter (show, color).
- New checkbox "Hide header" for each window (group sync, help your group, quests nearby, target mobs): the title band, title, zone badge and the buttons in it disappear and the content moves up
- "Target mobs" also lists mobs that drop an item of your open quests (this zone, from QuestieDB; the count is the item count, shown in blue)
- New window "Target mobs": lists the mobs of your open kill quests (this zone, can be switched to all); a click on a row targets the mob with /targetexact. Turn it on in the settings. New file QuestTargets.lua: needs a full client restart.
- "Help your group": a quest that the group member has already finished (ready to turn in) is no longer listed, he does not need help with it
- "Help your group": quests that you finished but have not handed in yet now count as done by default (the option "Also count quests still in your log that you only have to hand in" is on), so a group member who still lacks them stays in the list. Existing settings keep their value.
- New: chat messages for your quests (page "Chat messages" in the settings window, /sem): quest accepted, progress of every goal, ready to turn in, turned in. Each one can be switched on or off; the channel is your own chat window, the group chat or the guild chat. New file QuestNotes.lua: needs a full client restart.
- "Quests nearby", small view: one row per quest goal (goal name, count at the end) instead of one row per quest; quests without known goals stay one row
- Progress bars have a plastic gloss like the XP bar
- SexyEditMode is now a required dependency (CurseForge installs it automatically)
- "Quests nearby": a quest that was in range less than two minutes ago and comes back (small area, standing at the edge of the range) no longer plays the sound or glows again
- "Quests nearby": a quest that comes into range glows briefly in the list (also in the small view); can be turned off in the settings
- Removed the chat note "You lack: ..." (and its setting): the window itself shows what is missing
- Each window has a new setting "In combat": show normally, small view or hide (settings window)
- Docking: every window can be docked to another window (also of other Sexy addons), with side and alignment (needs the SexyEditMode addon)
- "Quests nearby": no sound while flying (mounted, in flight form or on a flight path)
- Minimap button, right click: Edit Mode only for the windows of SexyQuestHelper (needs the SexyEditMode addon)
- Edit Mode: the three windows have tabs at the top of their dialog (needs the SexyEditMode addon)
- "Quests nearby" in dungeons and raids: quests that your quest log lists under the name of the instance are always shown, even if their goals are outside before the entrance (e.g. The Essence of Aku'Mai)
- "Quests nearby" in dungeons and raids: quests that QuestieDB itself assigns to the instance are always listed. /sqh near debug now also lists the quests that are not shown and why (share of drop sources inside the instance)
- "Quests nearby" in dungeons and raids: a quest whose item drops from many creatures all over the world no longer shows up just because one of them also lives in the instance. An item counts if at least half of its known drop sources are in the instance, or if it has only a few sources (8 or fewer) and one of them is there (e.g. The Essence of Aku'Mai)
- Small view: every window has a "-" button in its title band that collapses it to the title band plus one summary line (group sync: who differs and how many quests; help: member and quest with progress; nearby: low, one line per quest with its name and one number at the end, e.g. 4/10, nothing else). "+" expands it again; each window remembers its state
- "Quests nearby": the "Hidden: N" button in the title band is gone (the list is on its own page in the shared settings window, and /sqh hidden still opens it)
- Edit Mode: with SexyEditMode the dialogs of the windows show only visual options; behavior (delay, auto close, sounds, range, turning windows on, ...) is in the shared settings window (/sem)
- Minimap button: left click opens the settings window (SexyEditMode) at the first area of SexyQuestHelper, right click toggles Edit Mode
- LibSharedMedia is now embedded, so the sound list of "Quests nearby" shows all sounds of your LibSharedMedia addons (SexyInterrupter, SharedMedia packs, ...) without needing another addon to load it
- "Quests nearby": the sound for a quest coming into range can be chosen (game sounds, plus the sounds of LibSharedMedia if another addon loads it); picking a sound or channel plays it. The volume follows the chosen sound channel (Master, Effects, Dialog, Ambience): WoW cannot set the volume of a single sound. The sound plays on the Master channel by default now and falls back to the standard sound if the chosen one is not available
- Hidden quests page: hovering over a quest name shows the quest tooltip
- Hidden quests page: the quest name on the left, a "Show" button behind it, and "Show all" at the very top
- "Hidden quests" is its own page in the shared settings window (SexyEditMode, /sem) instead of a section in every window's settings. The list can still be opened with the "Hidden" button in "Quests nearby" and with /sqh hidden
- The "Help" window is now called "Help your group" everywhere (window title, settings section, shared settings window)
- Registers with the new SexyEditMode addon: if it is installed, the three windows also appear in its shared settings window (/sem). Nothing changes without it
- Quest progress (e.g. a second mob kill within two seconds of the previous scan) is now picked up immediately instead of waiting for the next quest log event
- New minimap button: left click opens/closes Edit Mode. Hide it with `/sqh minimap`
- "Quests nearby": the group members' chips are now real badges like your own progress badge: gold text on a dark gold badge while open, green on dark green when done, grey for members without the addon, with a bit more padding around class icon and text
- `/sqh near debug` now prints all its output in English
- "Quests nearby": the "Hidden: N" button now sits at the right of the title bar, next to the close button, vertically centered in the bar
- "Quests nearby" now works in dungeons and raids: the game has no map or position there, so the window lists every quest in your log (whatever its header) whose goals QuestieDB places in this instance, with a "Dungeon" label instead of a distance. Finished quests are left out. `/sqh near debug` shows the instance and the matching quests
- "Quests nearby": the group members' badges now sit on the right of each goal, directly before your own progress badge, in the same size (quest-level badges in the title, before the distance); the goal text ends before them
- "Quests nearby": the progress of group members is now shown as small chips in the window's style (class icon plus "3/8", a check mark or "45 %" on a dark pill, gold while open, green when done, grey "?" for members without the addon), aligned under the goal text; hover a chip for the name and the exact state. The "Hidden: N" button now sits in the middle of the title bar
- "Quests nearby" shows the progress of your group members: under each goal small labels in class color with their state ("Anna 3/8", a check mark when done); members without single goals show percent under the quest title, finished or turned in with a check mark. Members without the addon show a grey "has the quest" when the game knows it (C_QuestLog.IsUnitOnQuest). Uses the data the addon already sends for "Help your group" (no new messages). Can be turned off in the Edit Mode dialog ("Show the progress of group members")
- "Quests nearby": a small button "Hidden: N" in the header opens a dialog that lists all hidden quests, each with a "Show" button, plus "Show all" (scrolls with the mouse wheel, Esc closes it). It replaces the grey "N hidden" line at the bottom of the window
- "Help your group": long quest titles, goal texts and notes now wrap onto further lines inside the window instead of running past its right edge; the rows grow with the text. Long goal texts in "Quests nearby" wrap the same way
- Right-click a quest to hide it now also works in the main window and in "Help your group", not only in "Quests nearby". There is one shared list of hidden quests for all three windows; each window's Edit Mode dialog has the "Hidden quests" section to show them again. In chat: `/sqh hidden` and `/sqh show <ID|all>` (the old `/sqh near hidden` / `/sqh near show` still work)
- "Help your group": hover a quest for its tooltip with the quest text; click opens it in the quest log if you still have it, otherwise it opens as a pinned quest window like a quest link in chat. Shift-click links it into the chat
- "Quests nearby": the list scrolls with the mouse wheel once it is taller than a set height (default 400 px, 150-900 in the Edit Mode dialog), with a thin bar at the right showing the position; the window no longer runs off the screen
- "Quests nearby": right-click a quest to hide it from the window (saved across sessions, for all characters), for quests that are "nearby" everywhere such as the pages of "The Green Hills of Stranglethorn". A grey line at the bottom of the window shows how many are hidden; the Edit Mode dialog has a section "Hidden quests" with a button per quest to show it again and "Show all again". In chat: `/sqh near hidden` lists them, `/sqh near show <ID>` or `/sqh near show all` brings them back
- "Quests nearby" on non-English clients (e.g. German): goal areas are now matched to your zone by map ID via Questie's zone data when Questie is loaded, instead of only by the localized zone name; name matching ignores case and stray spaces. `/sqh near debug` also lists the goal areas (ID, name, map) of quests that found no points

## 1.0.16
- "Quests nearby": a quest for which QuestieDB knows no real place stays in the list for a few minutes (default 3, 1-10 in the dialog) after its progress rose, wherever you stand, with a grey label showing how long ago; then it disappears. Quests with a known place still follow the range
- "Help your group" uses the same look as "Quests nearby": every goal a row of its own with check box, state label and a progress bar, a colored stripe per quest; without single goals one bar shows the overall progress
- "Quests nearby": goals as small rows of their own (check box, goal text, state label such as 3/8, plus a thin progress bar with some space under each goal; the count is shown in the label only, not in the goal text), a colored stripe at the left of each quest (yellow while goals are open, green when all are done) and thin dividers between quests
- Goals in the "Quests nearby" and "Help your group" windows are listed one per line again (they ran together into one line)
- "Quests nearby": hover a quest for its tooltip with the quest text, click opens it in the quest log, Shift-click links it into the chat
- "Quests nearby": every goal of a quest is listed with a check box, finished goals ticked and green, open ones with an empty box; quests without numbered goals show the goal description from QuestieDB instead
- New third window "Quests nearby": lists your open quests whose goals are within range (default 60 yards, 20-200) of where you stand, with the single goals and the distance. The goal positions come from the QuestieDB addon (creatures, objects, items via their drop sources, explore areas) in your current zone. In addition the addon learns places while you play: whenever the progress of a quest rises (for example after the first kill) your position counts as an area of that quest, so the window also works without QuestieDB. Optional, off by default (Edit Mode), optional sound when a quest comes into range, /sqh near toggles it

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
