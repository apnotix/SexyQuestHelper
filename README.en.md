<div align="center">

# 📜 SexyQuestHelper

**Does your whole group have the same quests? Find out at a glance.**
Compares the quests of your current zone with every group member who also runs the addon and shows exactly what is missing for whom. Share a quest with one click.

![WoW Forever](https://img.shields.io/badge/WoW-Forever-e8c26a?style=for-the-badge)
![Interface](https://img.shields.io/badge/Interface-120100%20%7C%2016001-3b2b12?style=for-the-badge)

[🇩🇪 Deutsche Version](README.md)

</div>

---

## ✨ What SexyQuestHelper does

- 🪟 **Only shows up when it matters:** the window opens by itself as soon as quests differ (after a few seconds, so quests both players accept at the same time don't cause a false alarm). If everyone is in sync, it stays away.
- 👥 **One card per player:** class icon, class-colored name and a label: "In sync" (green), "N differences" (amber) or "different zone" (grey).
- 🔎 **Clear differences:** red **"You lack"** for quests the other player has and you don't. Blue **"Lacks"** for quests you have and the other player doesn't.
- 📤 **Share button:** on "Lacks" rows you can send the quest to the group with one click.
- 🧠 **No false differences:** quests the other player cannot accept (missing prerequisite, level too low, already further in the quest chain) or has already turned in are hidden and get no Share button. The addon also learns from the error message after a share attempt. With the optional **QuestieDB** addon it works before the first attempt.
- 🏷️ **Tooltip and click:** hover a quest for its tooltip. Click opens it in your quest log, Shift-click puts the link in chat.
- 🗺️ **Zone based:** only quests of your current zone are compared. The zone is shown as a badge in the title band. The comparison uses the map ID instead of the name, so it also works between clients in different languages.
- 🔄 **Versions at a glance:** `/sqh version` shows who runs which addon version and whether it is up to date.
- 🎨 **Consistent look:** dark brown surface, gold frame, title band with a zone badge. Fonts: **Marcellus** for the title, **Inter** for all other text (bundled, SIL Open Font License).
- 🖱️ **Movable:** drag the window wherever you like, the position is saved. Close it and it only returns when the differences change.
- 🌍 **English and German.**
- 🪶 **Lightweight:** no libraries, addon messages only when something changes.

## 🔧 How it works

Every player running the addon sends the quest IDs of the current zone to the group over hidden addon messages. Each client compares its own list with the received ones. In addition, players tell each other which quests from the other's list they have already turned in or cannot accept. Group members without the addon cannot be compared, `/sqh version` lists them as "no addon / no data".

---

## 📥 Installation

1. Copy the `SexyQuestHelper` folder into your `Interface/AddOns` directory of the Forever client.
2. Start the game or `/reload`.
3. Every group member needs the addon, otherwise they cannot be compared.

## ⌨️ Commands

| Command | Effect |
| --- | --- |
| `/sqh` | Show or hide the window. Opened manually it shows all players, even without differences |
| `/sqh refresh` | Re-scan your quest log and send it to the group (also `/sqh scan`) |
| `/sqh test` | Toggle a simulated group member to preview the display |
| `/sqh version` | Addon version of every group member and whether they are up to date (also `/sqh v`) |
| `/sqh check <questID>` | Show whether you can accept a quest, with its prerequisite data (needs QuestieDB) |
| `/sqh debug` | Diagnostics: detected zone, quests, addon message counters (`/sqh debug log` also lists the quest log) |

Long form: `/sexyquesthelper`

---

## ⚠️ Good to know

- 📚 Quests are matched by the quest log category that has the same name as your current zone.
- 🧩 Without QuestieDB the addon cannot know in advance whether someone can accept a quest. The Share button then appears first, and after an error message the addon remembers the result.
- 🔢 The version lives in the `.toc`. It is raised automatically on every push to `main` (see `.github/workflows/release.yml`).

## 🐞 Reporting bugs

Please report bugs and requests as an [issue on GitHub](https://github.com/apnotix/SexyQuestHelper/issues). Enable `/console scriptErrors 1` first and include the Lua error message, ideally together with the output of `/sqh debug`.

## 🙏 Credits

- Fonts [Marcellus](https://fonts.google.com/specimen/Marcellus) and [Inter](https://fonts.google.com/specimen/Inter) (SIL Open Font License 1.1, license texts in `media/fonts`)
- Optional: **QuestieDB** to check whether a quest can be accepted

---

<div align="center">

Made by **apnotix** · Also by me: **SexyLoot**, **SexyInterrupter**

</div>
