# Epoch Design System: Paper

This file is the source of truth for how Epoch looks and behaves. Follow it whenever you build or change UI. If a mockup and this file disagree, this file wins.

- Visual reference: the design sheet [Paper direction.webp](docs/design/Paper%20direction.webp) and the "Epoch Paper Direction" canvas (https://claude.ai/artifact/ETxeb6vmhzFzGrSXfLmBJE).
- Platform: iOS (SwiftUI). Light "Paper" appearance by default, with a "Lamplight" dark appearance.
- Product: an RPG text adventure. An LLM narrates the story and makes tool calls (stats, inventory, checks, quests) that the app renders as game events.
- Goal: the app should feel like reading a book. Few UI elements, no unnecessary containers, context one tap away.
- Tokens live in [ThemeManager.swift](epoch/Shared/Managers/ThemeManager.swift). Views refer to tokens only; never hard-code hex values, sizes or fonts.

## 1. Principles

1. **Set it like a book.** Narration runs full measure inside 28 pt margins. No boxes, bubbles or cards around any voice.
2. **Rules mean something.** A hairline appears only to separate rows you can act on, or as a meter. Never as decoration.
3. **Color is ink, not paint.** Meaning colors tint words and thin lines. They never fill a surface. Every color also carries a sign or word.
4. **Your words, in quill.** Quill blue is the reader's ink: player turns, suggested actions, and anything waiting on the player.
5. **Context, one tap away.** The folio at the foot of the page shows health, gold and conditions as text. Names in narration open margin notes. The Codex (Hero, Pack, Journal) is one sheet.
6. **One real container.** Sheets (Codex, margin note) are the only raised surface. The only filled button is Roll.

## 2. Color

| Token | Paper | Lamplight | Use |
|---|---|---|---|
| `paper` | `#F4EFE4` | `#1C1A17` | Screen ground |
| `leaf` | `#ECE5D6` | `#24211D` | Sheets |
| `press` | `#E4DBC6` | `#2E2A25` | Pressed state, highlighted word, plate while drawing |
| `rule` | `#D6CBB7` | `#3A352E` | Hairlines, meter tracks |
| `grain` | `#C9BDA7` | `#4A443B` | Grabber, ornaments, dotted leaders (decoration only) |
| `ink` | `#29241E` | `#E6DED0` | Narration, titles (13.4:1) |
| `inkSoft` | `#4F473E` | `#C6BDAE` | Descriptions, icons, secondary text (8.0:1) |
| `inkMuted` | `#6B6155` | `#A39886` | Event lines, eyebrows, meta. Floor for readable text (5.3:1) |
| `inkFaint` | `#9A8F80` | `#6E665A` | Separators, entity underline. Never readable text |
| `quill` | `#2E4A6E` | `#9DB5D6` | Player text, story actions, primary button, unread dots |
| `rubric` | `#9B3A2A` | `#D98B78` | Health, damage, failed checks |
| `moss` | `#4D6A3F` | `#9DB98A` | Healing, items gained, passed checks, "New" |
| `plum` | `#6E4A6B` | `#C29BBE` | Conditions |
| `ochre` | `#85641F` | `#D2B270` | Gold, XP |

Lamplight values are a starting point and need a contrast pass before shipping.

## 3. Typography

- **Newsreader** (variable, optical size; SIL OFL) for everything the world says.
- **SF Pro** for machinery (mockups use Figtree as a stand-in).

| Style | Font | Size / leading | Use |
|---|---|---|---|
| `display` | Newsreader 500 | 38 / 42 | Screen titles |
| `title` | Newsreader 500 | 25 / 30 | Story, quest, item titles (22–24 in sheets) |
| `narration` | Newsreader 400 | 18 / 29 | Narrator |
| `player` | Newsreader Italic, `quill` | 17 / 26 | Player turns, suggestions (15), story actions |
| `description` | Newsreader 400 | 15.5 / 23 | Descriptions, recaps, flavor (italic) |
| `caption` | Newsreader Italic | 12.5 / 18 | Plate captions, helper lines |
| `eyebrow` | SF Pro Semibold, uppercase, +0.14em | 10.5 | Section labels, chapter labels |
| `event` | SF Pro Medium, uppercase, +0.08em, tabular | 11 | Game event lines |
| `ui` | SF Pro Medium | 12–15 | Folio, filters, Done, utility actions |

All styles scale with Dynamic Type. Changing numbers use monospaced digits.

## 4. The reading view

Three voices that must never look alike:

| Voice | Treatment |
|---|---|
| **Narrator** | Printed ink, full measure, 28 pt margins. Names the game knows are dotted underlines. |
| **Player** | Quill italic, indented 22 pt. No bubble, no name. |
| **Game** | A marginal note under the passage, 10 pt below it. Only the changed value takes a meaning ink. |

- **Running head:** back, centered story name (eyebrow) over chapter and place (italic 14), Journal ribbon with a quill dot when updated. No nav bar fill.
- **Feed:** bottom-anchored, top edge fades into the paper (56 pt mask).
- **Narrator:** `narration` in `ink`. Known names get a dotted underline in `inkFaint` (1.5 pt, offset 4). Tap opens a margin note.
- **Player:** `player` style, indented 22 pt. No bubble, no label.
- **Game events:** one `event` line 10 pt under the passage, `inkMuted`, events 14 pt apart. Only the changed value or sign takes a meaning ink. Tap expands the detail.
- **Plates (illustrations):** part of the narrator's message, above the passage, bleeding 12 pt past the margin, square corners. Caption "Plate III. …" centered. Drawing: hold the full height in `press` with three dots and "The illustrator is at work". Failed: collapse silently. Ready: fade in over 300 ms. Prompt the image model for a muted sepia aquatint style.
- **Folio:** a 1 pt `rule` across the page whose 2 pt `rubric` fill is the health meter. Below it, "18/30 · 42 gold · Soaked" (opens Hero) and three icon buttons: Hero, Pack (moss dot for new items), Journal.
- **Composer:** suggestion line in quill italic, then a writing line: italic placeholder "What do you do?" over a hairline, with a 32 pt outlined quill send button. Suggestions read as choices in a gamebook.

## 5. Tool calls, as notes

Tool names are suggestions; match them to the real tool schema. Event text is set in the `event` style; only the value or sign takes the listed ink.

| Tool | Event line | Ink |
|---|---|---|
| `modify_stat` | "−6 HEALTH" / "+7 HEALTH" | `rubric` / `moss` |
| `add_item` / `remove_item` | "+ RUSTED ABBEY KEY" / "− HEALING DRAUGHT, 1 LEFT" | `moss` / `inkMuted` |
| `roll_check` | "PERCEPTION 15 VS 12, PASSED" | `moss` passed, `rubric` failed |
| `apply_condition` | "SOAKED −1 STEALTH" | `plum` |
| `modify_gold`, `grant_xp` | "+12 GOLD · +25 XP" | `ochre` |
| `update_quest` | "JOURNAL: NEW OBJECTIVE" with a quill dot | `quill` dot |
| `move_location` | "NOW AT THE CRYPT STAIR" | `inkMuted` |
| `request_roll` | Replaces the composer (section 6) | `quill` |

## 6. Moments that need the player

- **Roll requested:** replaces the composer. Eyebrow "A test of Perception" in quill, italic formula ("Roll a d20, add 2. You need 12."), line-drawn d20, the one filled button (180 × 50, quill, paper text), optional Lucky Coin checkbox, "Change my action" text link.
- **Level up:** same pattern: centered eyebrow, italic summary, one filled "Choose" button. (Not drawn yet.)

## 7. Pieces

- **Actions:** one filled button per screen at most, and only for a moment that waits on you (capsule, `quill` fill, `paper` text). Story actions are quill italic. Utility actions are small sans in `inkSoft`.
- **Meter rule:** a 1 pt `rule` track with a 2 pt meaning-ink fill. The rule above the composer is the health line.
- **Tabs:** section tabs are serif words with a 1.5 pt underline on the current one. Filters are sans words set in weight (semibold marks current). No segmented tracks.
- **Lists and leaders:** stats use dotted leaders in `grain`, like a table of contents. Lists of things you can act on get hairlines between rows.
- **Sheets:** the one real container: `leaf` laid over the page, 16 pt top corners, grabber, no shadow; the page behind dims 16%.
- **Icons:** 20 pt line icons, 1.5 stroke (SF Symbols, regular weight, outline). Never emoji.

## 8. Codex sheet

Large detent, `leaf`, 16 pt top corners, grabber, page behind dims 16%. Serif tabs Hero / Pack / Journal with a 1.5 pt underline on the current one, and "Done" in quill.

- **Hero:** name, class line, XP meter rule (quill), vitals as numbers with meter rules (Health rubric, Stamina inkSoft), Armor and Gold as numbers. Attributes in two columns with dotted leaders; calling stat in quill. Conditions as a sentence. "Carrying in hand" as a sentence.
- **Pack:** sans filters (weight marks current), "12 of 20". Rows divided by hairlines: line-drawn glyph, name, italic type, count or a small tag ("New" in moss, "In hand"). The selected row expands in place with flavor text, quill "Drink it", sans Give and Drop, and "Using an item takes your turn."
- **Journal:** filters Quests / People / Places / Lore. "The story so far" in italic. Followed quest with drawn checks (moss), current (quill dot), upcoming (hollow). Other quests as hairline rows. "Finished, 3".

## 9. Margin note

Tapping a dotted name highlights it in `press` and raises a short sheet: line sketch, eyebrow (kind and status), title, italic description, dotted-leader facts (Found, Mentioned), a quill story action ("Try it on the iron door") and "Open in Pack/Journal".

## 10. Stories home and first run

- **Stories:** small icon buttons (settings, new story in quill), `display` title, italic subtitle. Each story is a plate (150 tall), eyebrow (chapter, with state in a meaning ink), title, description, sans meta line. Stories are separated by a small rule-diamond-rule ornament, not cards.
- **First run:** the same layout as Stories, so a new player learns one list. Title "Stories", italic line "Choose one to begin, or describe your own" (the last words a quill link). Each world is a plate, genre eyebrow, title and one-line pitch, with the same ornament between them. No hero, progress or meta line. Tapping a world opens Story details.
- **Story details:** a scrolling page that tells the player what they are getting into before they start. Back button, full-width plate (240 tall), genre eyebrow, `display` title, premise in `narration` style, then dotted-leader facts (Length, Mood, Begins in). Sections, each with an eyebrow: "You begin as" (line-sketch portrait, pre-made hero name, class, one sentence, key stats, quill "Make your own hero instead"), "Your first quest" (title and italic objective), "People you may meet" and "From the archive" (pre-generated people and lore as hairline rows with an italic line each; "Others stay unnamed until you meet them"), "You set out with" (starting items as a sentence). The page ends with the filled quill button "Begin as Wren". All of this content is pre-generated with the world and seeds the Journal and Pack once play begins.

## 11. Spacing and sizes

- 4 pt scale. Margins: 28 for narration and lists, 20 for the folio and composer, 12 for edge icon buttons.
- 22 pt between passages, 10 pt passage to event line, 14 pt between events, 22 pt player indent.
- Tap targets 44 × 44. Icons are 20 pt line icons, 1.5 stroke. Never emoji.

## 12. Motion and haptics

| What | Behavior |
|---|---|
| Narration | Streams in as it is generated |
| Event line | Fades in 200 ms after its passage completes |
| Vitals | Count to the new value over 400 ms |
| Plate | Fades in over 300 ms into its reserved space |
| Roll | Die tumbles for 600 ms; light haptic on landing |

With Reduce Motion on, replace all of these with simple cross-fades.

## 13. Accessibility

- Readable text no lighter than `inkMuted` (4.5:1 or better on `paper` and `leaf`).
- Tap targets at least 44 × 44.
- Icon-only buttons need an accessibility label ("Hero", "Pack", "Journal", "Send").
- Event lines read as one VoiceOver element per event, e.g. "Health down 6, now 18 of 30."
- Plates need an accessibility label describing the scene (ask the image tool for alt text).
- Support Dynamic Type up to the accessibility sizes; the feed must reflow, not truncate.

## 14. Don'ts

- Don't put narration, player turns or events in bubbles, cards or tinted panels.
- Don't fill a surface with a meaning color.
- Don't use quill for anything that isn't the reader or waiting on the reader.
- Don't draw decorative rules or add drop shadows.
- Don't add a tab bar. The Codex is a sheet so the reader never loses the page.
- Don't set readable text lighter than `inkMuted`, or rely on color alone.
- Don't introduce new colors, sizes or font styles; extend this file first.
