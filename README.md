<div align="center">

# 📜 SexyQuestHelper

**Hat deine ganze Gruppe dieselben Quests? Sieh es auf einen Blick.**
Vergleicht die Quests deines aktuellen Gebiets mit allen Gruppenmitgliedern, die das Addon auch nutzen, und zeigt genau, was bei wem fehlt. Mit einem Klick teilst du eine Quest.

![WoW Forever](https://img.shields.io/badge/WoW-Forever-e8c26a?style=for-the-badge)
![Interface](https://img.shields.io/badge/Interface-120100%20%7C%2016001-3b2b12?style=for-the-badge)

[🇬🇧 English version](README.en.md)

</div>

---

## ✨ Das kann SexyQuestHelper

- 🪟 **Erscheint nur, wenn es nötig ist:** Das Fenster öffnet sich von selbst, sobald sich die Quests unterscheiden (nach ein paar Sekunden, damit Quests, die beide gleichzeitig annehmen, keinen Fehlalarm auslösen). Sind alle gleich, bleibt es weg.
- 👥 **Eine Karte pro Spieler:** Klassenicon, Name in Klassenfarbe und ein Etikett: „Alles gleich“ (grün), „N Unterschiede“ (bernstein) oder „anderes Gebiet“ (grau).
- 🔎 **Klare Unterschiede:** Rot **„Dir fehlt“** für Quests, die der andere hat und du nicht. Blau **„Hat nicht“** für Quests, die du hast und der andere nicht.
- 📤 **Teilen-Knopf:** Bei „Hat nicht“ kannst du die Quest mit einem Klick an die Gruppe schicken.
- 🧠 **Keine Scheinunterschiede:** Quests, die der andere nicht annehmen kann (Vorquest fehlt, zu niedrige Stufe, schon weiter in der Questkette) oder schon abgegeben hat, werden ausgeblendet und bekommen keinen Teilen-Knopf. Das Addon lernt außerdem aus der Fehlermeldung beim Teilen. Mit dem optionalen Addon **QuestieDB** klappt es schon vor dem ersten Versuch.
- 🏷️ **Tooltip und Klick:** Fahr über eine Quest für den Tooltip. Ein Klick öffnet sie im Questlog, Shift-Klick schreibt den Link in den Chat.
- 🗺️ **Gebietsbezogen:** Verglichen werden nur Quests deines aktuellen Gebiets. Das Gebiet steht als Badge im Titelband. Der Vergleich nutzt die Karten-ID statt des Namens und klappt deshalb auch zwischen Clients in verschiedenen Sprachen.
- 🔄 **Versionen im Blick:** `/sqh version` zeigt, wer welche Addon-Version nutzt und ob sie aktuell ist.
- 🎨 **Einheitlicher Look:** dunkelbraune Fläche, Goldrand, Titelband mit Gebiets-Badge. Schrift: **Marcellus** für den Titel, **Inter** für den übrigen Text (mitgeliefert, SIL Open Font License).
- 🖱️ **Verschiebbar:** Ziehe das Fenster, wohin du willst. Die Position wird gespeichert. Schließt du es, kommt es erst bei neuen Unterschieden zurück.
- 🌍 **Deutsch und Englisch.**
- 🪶 **Leicht:** keine Bibliotheken, Addon-Nachrichten nur bei Änderungen.

## 🔧 So funktioniert es

Jeder Spieler mit dem Addon schickt die Quest-IDs seines Gebiets per unsichtbarer Addon-Nachricht an die Gruppe. Jeder Client vergleicht seine Liste mit den empfangenen. Zusätzlich melden sich die Spieler gegenseitig, welche Quests aus der Liste des anderen sie schon abgegeben haben oder nicht annehmen können. Mitglieder ohne das Addon lassen sich nicht vergleichen, `/sqh version` zeigt sie als „kein Addon / keine Daten“.

---

## 📥 Installation

1. Ordner `SexyQuestHelper` in dein `Interface/AddOns`-Verzeichnis des Forever-Clients kopieren.
2. Spiel starten oder `/reload`.
3. Alle Gruppenmitglieder brauchen das Addon, sonst können sie nicht verglichen werden.

## ⌨️ Befehle

| Befehl | Wirkung |
| --- | --- |
| `/sqh` | Fenster ein- oder ausblenden. Manuell geöffnet zeigt es alle Spieler, auch ohne Unterschiede |
| `/sqh refresh` | Questlog neu einlesen und an die Gruppe senden (auch `/sqh scan`) |
| `/sqh test` | Simuliertes Gruppenmitglied ein- oder ausschalten, um die Anzeige zu sehen |
| `/sqh version` | Addon-Version aller Gruppenmitglieder und ob sie aktuell sind (auch `/sqh v`) |
| `/sqh check <QuestID>` | Zeigt, ob du die Quest annehmen kannst, samt Vorquest-Daten (braucht QuestieDB) |
| `/sqh debug` | Diagnose: erkanntes Gebiet, Quests, Zähler der Addon-Nachrichten (`/sqh debug log` listet zusätzlich das Questlog) |

Langform: `/sexyquesthelper`

---

## ⚠️ Gut zu wissen

- 📚 Quests werden über die Questlog-Kategorie zugeordnet, die wie dein aktuelles Gebiet heißt.
- 🧩 Ohne QuestieDB weiß das Addon nicht vorher, ob jemand eine Quest annehmen kann. Der Teilen-Knopf erscheint dann zuerst, und nach einer Fehlermeldung merkt sich das Addon das Ergebnis.
- 🔢 Die Version steht in der `.toc`. Sie wird bei jedem Push auf `main` automatisch erhöht (siehe `.github/workflows/release.yml`).

## 🐞 Fehler melden

Fehler und Wünsche bitte als [Issue auf GitHub](https://github.com/apnotix/SexyQuestHelper/issues) melden. Aktiviere vorher `/console scriptErrors 1` und schick die Lua-Fehlermeldung mit, am besten zusammen mit der Ausgabe von `/sqh debug`.

## 🙏 Danksagung

- Schriften [Marcellus](https://fonts.google.com/specimen/Marcellus) und [Inter](https://fonts.google.com/specimen/Inter) (SIL Open Font License 1.1, Lizenztexte in `media/fonts`)
- Optional: **QuestieDB** für die Prüfung, ob eine Quest annehmbar ist

---

<div align="center">

Gemacht von **apnotix** · Auch von mir: **SexyLoot**, **SexyInterrupter**

</div>
