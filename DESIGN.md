# Epoch Design System

This file is the source of truth for how Epoch looks and behaves. Follow it whenever you build or change UI. If a mockup and this file disagree, this file wins.

- Platform: iOS (SwiftUI), dark appearance only.
- Visual reference: the "Epoch iOS UI" design canvas (https://claude.ai/artifact/CiFX4ASXDNdrw9BvEjsK5D).
- Product: an RPG text adventure. An LLM narrates the story and makes tool calls (stats, inventory, checks, quests) that the app renders as game events.

---

## 1. Principles

1. **Narration leads.** Story text is the hero of the app. It is never boxed, carded or bordered. Everything else steps back from it.
2. **Game events are quiet.** Tool-call results show as one muted line beneath the passage they belong to, not as cards.
3. **Fill, not lines.** No borders, dividers, hairlines or drop shadows. Layers are separated only by steps of surface fill and by spacing.
4. **Soft geometry.** Generous, continuous (squircle) corner radii. Buttons and chips are capsules.
5. **Amber means "you."** The amber accent is reserved for primary actions and for moments that need the player (a roll, a level-up, a new objective).
6. **Color never works alone.** Every colored meaning (gain, loss, condition) also carries a sign, word or icon.

---

## 2. Color

All values are sRGB. Use them as named tokens in an asset catalog or a `Color` extension; never hard-code hex values in views.

### Surfaces (darkest to lightest)

| Token | Hex | RGB | Use |
|---|---|---|---|
| `scrim` | `#07080A` | 7, 8, 10 | Area behind a presented sheet |
| `base` | `#0E1014` | 14, 16, 20 | Screen background |
| `sheet` | `#13161B` | 19, 22, 27 | Sheet background |
| `card` | `#15181D` | 21, 24, 29 | Story cards, world cards, illustration placeholder |
| `control` | `#1A1D23` | 26, 29, 35 | Chips, composer field, secondary buttons, segmented-control track |
| `player` | `#1B1E24` | 27, 30, 36 | Player message bubble |
| `raised` | `#20242C` | 32, 36, 44 | Avatars, tiles inside cards, item rows in sheets |
| `track` | `#23272F` | 35, 39, 47 | Empty part of progress bars |
| `selected` | `#2C313B` | 44, 49, 59 | Selected segment |
| `grabber` | `#3A404C` | 58, 64, 76 | Sheet grabber |

### Text

| Token | Hex | RGB | Use |
|---|---|---|---|
| `textPrimary` | `#EDE7DB` | 237, 231, 219 | Narration, titles, primary labels |
| `textSecondary` | `#CFC8BB` | 207, 200, 187 | Descriptions, player text, secondary labels |
| `textMuted` | `#8E887D` | 142, 136, 125 | Event lines, captions, metadata. Lowest color allowed for readable text (5.4:1 on `base`) |
| `textFaint` | `#6E6A62` | 110, 106, 98 | Chevrons and decoration only, never for text a player must read |

### Accent

| Token | Hex | RGB | Use |
|---|---|---|---|
| `amber` | `#E5A85A` | 229, 168, 90 | Primary buttons, links, text buttons, unread dots |
| `amberLight` | `#F2C287` | 242, 194, 135 | Pressed state, text on amber tints |
| `onAmber` | `#1A1206` | 26, 18, 6 | Text and icons on amber fills |
| `amberWash` | `#1E1A14` | 30, 26, 20 | Surfaces that need the player (roll card, level-up, active quest) |
| `amberTint` | `#2A2116` | 42, 33, 22 | Icon wells, secondary amber buttons |
| `amberSelected` | `#3A2C17` | 58, 44, 23 | Selected chip, tile or option |

### Game meaning

| Token | Hex | RGB | Use |
|---|---|---|---|
| `gain` | `#7CC4B4` | 124, 196, 180 | Healing, items gained, passed checks |
| `gainTint` | `#1E2A28` | 30, 42, 40 | "New" badge background |
| `loss` | `#E07A6E` | 224, 122, 110 | Damage, failed checks, combat, player HP bar |
| `enemy` | `#B9665C` | 185, 102, 92 | Enemy HP bar |
| `condition` | `#9CC0E8` | 156, 192, 232 | Status effects (Soaked, Poisoned…) |
| `conditionTint` | `#161D26` | 22, 29, 38 | Condition card background |
| `gold` | `#D9C38A` | 217, 195, 138 | Currency icon |
| `entityLink` | `#4F6E67` | 79, 110, 103 | Underline on item/person names inside narration |

Stamina bars use `amber`. Health bars use `loss`.

---

## 3. Typography

Two families:
- **Literata** (serif, SIL Open Font License; bundle the variable font with the optical-size axis) for anything the narrator or the world says: narration, story and item names, descriptions, captions.
- **SF Pro** (system font) for all interface text. The mockups use Figtree as a stand-in; ship SF Pro.

Every style must scale with Dynamic Type. Use `Font.custom(_:size:relativeTo:)` for Literata with the text style listed.

| Style | Font | Size / line height | Dynamic Type base | Use |
|---|---|---|---|---|
| `largeTitle` | SF Pro Bold, tracking −0.01em | 34 / 41 | `.largeTitle` | Screen title ("Stories") |
| `storyTitle` | Literata Semibold | 23 / 28 | `.title2` | Story card title, hero name |
| `itemTitle` | Literata Semibold | 19 / 24 | `.title3` | Item, quest and roll names |
| `narration` | Literata Regular | 18 / 30 (1.65) | `.body` | Narrator text in the feed |
| `description` | Literata Regular | 15 / 22 | `.subheadline` | Story descriptions, recaps, item flavor text |
| `caption` | Literata Italic | 13 / 18 | `.footnote` | Illustration captions, "narrator is writing" |
| `headline` | SF Pro Semibold | 17 / 22 | `.headline` | Buttons; nav titles use 16 |
| `uiBody` | SF Pro Regular | 15 / 22 | `.subheadline` | Player messages, list rows, UI body |
| `eventLine` | SF Pro Regular, tabular figures | 13 / 18 | `.footnote` | Game event lines |
| `eyebrow` | SF Pro Semibold, uppercase, tracking +0.06em | 12 / 16 | `.caption` | Section labels, world/chapter labels |

Rules:
- Narration is always `narration` in `textPrimary`. Do not bold or color narration, except for entity links (section 7).
- All numbers that change (HP, gold, rolls) use monospaced digits (`.monospacedDigit()`).

---

## 4. Corner radius

Always use continuous corners (`RoundedRectangle(cornerRadius:style: .continuous)`). A shape nested inside another uses about 6 pt less radius per level of inset.

| Token | Value | Use |
|---|---|---|
| `sm` | 10 | Segmented-control track (segments inside use 8) |
| `md` | 18 | Bag tiles, rows and toggles inside cards |
| `lg` | 22 | Feed illustrations, info cards, roll card, condition card |
| `xl` | 28 | Story cards, world cards, top corners of sheets |
| `capsule` | height ÷ 2 | Buttons, chips, composer, progress bars, status tags |
| `bubble` | 20, with a 6 bottom-trailing corner | Player message |

---

## 5. Spacing and layout

A 4-point scale: **4, 8, 12, 16, 20, 24, 32, 40**.

| Context | Value |
|---|---|
| Screen edge for cards and lists | 16 |
| Screen edge for headers and forms | 20 |
| Screen edge for narration | 22 |
| Between story passages | 18 |
| Passage to its event line | 10 |
| Between cards | 18 |
| Between sections | 28 |
| Card inner padding | 16–18 |

Layout rules:
- Respect safe areas. Do not draw fake status bars.
- The story feed is anchored to the bottom (newest at the bottom) and scrolls up.
- No tab bar. In-game panels (Bag, Character, Journal) are sheets, so the player never loses their place in the story.

---

## 6. Sizes

| Element | Size |
|---|---|
| Minimum tap target | 44 × 44 |
| Primary and secondary buttons | 50 tall |
| Composer field, bag button | 44 tall |
| Suggestion chip, send button | 36 tall |
| Roll button | 108 circle |
| Avatar: nav bar / card / sheet header | 30 / 34 / 64 |
| Icon: nav bar / inline / event line | 22 / 18 / 13 |
| Progress bar height | 4 (6 in sheets) |
| Story card illustration | full card width × 184 |
| Feed illustration | screen width − 24 × 210 |
| Sheet grabber | 36 × 5, `grabber` |

---

## 7. The story feed

The feed has three voices that must never look alike:

| Voice | Treatment |
|---|---|
| **Narrator** | `narration` style in `textPrimary`, no container, full width inside the 22 pt margin |
| **Player** | Right-aligned bubble, `player` fill, `bubble` radius, `uiBody` in `textSecondary`, max width about 270 |
| **Game** (tool calls) | One `eventLine` under the passage, `textMuted`, with 13 pt tinted icons, no container |

### Event line
- Shows every event from one narrator turn in a single wrapping row, in the order they happened, separated by 14 pt.
- Each event is a 13 pt SF Symbol tinted with its meaning color, followed by short muted text. Only the changed number (e.g. "−6 HP") may take the meaning color and semibold weight.
- Tapping the line expands the detail (dice math, item description).
- Fades in 200 ms after its passage finishes streaming.

### Entity links in narration
Items, people and places the narrator names that exist in game state are tappable: text in `#F4E6CB`, underline in `entityLink`, 1.5 pt thick, offset 4 pt. Tapping opens the item in the Bag or the entry in the Journal.

### Illustrations
Generated images for key story moments are part of the narrator message:
- Sit above the passage they illustrate, with 12 pt bleed past the narration margin on each side (`lg` radius, no frame).
- Optional `caption` below, inset to the narration margin.
- **Generating:** reserve the full 210 pt height with a `card` fill and a three-dot amber indicator with "Illustrating" in `caption` style, so text never jumps.
- **Failed:** collapse the slot silently. Never show an error for a missing image.
- **Ready:** fade in over 300 ms. Tap opens full screen.

### Moments that need the player
These are the only events that get a surface (`amberWash` fill, `lg` radius):
- **Roll requested:** the composer is replaced by a roll panel (`card` fill, `xl` top corners) with the roll name, formula and target, a 108 pt amber Roll button, optional modifiers (e.g. Lucky Coin), and "Change my action". If the player scrolls away, show a compact roll card inline in the feed.
- **Level up:** an inline card with the new level, gains, and a "Choose" button.

### Narrator states
- **Writing:** three amber dots plus "The narrator is writing" in `caption` style.
- **Error:** muted line "The narrator lost the thread. Your turn was not spent." with a Retry chip.

### Top of the feed
- Nav bar: back to Stories, centered story name with chapter/time below (in combat: "In combat · Round N" in `loss`), then Journal (with an amber dot when updated) and the Character avatar.
- Vitals strip: borderless, centered row of HP bar, stamina bar, gold and active conditions in 12 pt semibold. Tap opens Character.

### Composer
- A horizontal row of suggested-action chips above.
- Bag button (44 circle, `control`), a capsule text field ("What do you do?", `control`), and a 36 pt amber send button inside the field.

---

## 8. Tool call → UI mapping

Tool names are suggestions; match them to the real tool schema.

| Tool | Event line | Icon / color | Also updates |
|---|---|---|---|
| `modify_stat` (HP down) | "−6 HP" | `heart`, `loss` | Vitals strip |
| `modify_stat` (HP up) | "+7 HP" | `heart`, `gain` | Vitals strip |
| `add_item` | "Rusted Abbey Key" | `plus`, `gain` | Bag ("New" badge) |
| `remove_item` | "Healing Draught, 1 left" | `minus`, `textSecondary` | Bag |
| `roll_check` (resolved) | "Perception 15 vs 12, passed" | `dice`, `gain` / `loss` | — |
| `request_roll` | — (roll panel, see section 7) | amber | Composer |
| `apply_condition` | "Soaked: −1 Stealth" | `drop`, `condition` | Vitals strip, Character |
| `update_quest` | "Journal: new objective" | `book.closed`, `amber` | Journal dot |
| `move_location` | "Now at The Crypt Stair" | `mappin`, `textSecondary` | Nav subtitle |
| `start_combat` / `end_combat` | "Combat begins" / "Victory · +80 XP" | sword glyph, `loss` / `gain` | Combat vitals |
| `modify_gold`, `grant_xp` | "+12 gold · +25 XP" | `circle` coin, `gold` / `amber` | Character |
| `grant_xp` crossing a level | Level-up card | amber | Character |
| `generate_image` | Illustration in the message | — | Story card cover (optional) |

---

## 9. Screens

| Screen | Key points |
|---|---|
| **Stories** | Large title, Settings and + in the nav bar. Vertical list of story cards (`card`, `xl`): illustration on top with a status tag (capsule on `base`, e.g. "In combat", "Chapter 4"), then eyebrow (world · chapter), `storyTitle`, `description`, and a footer with the hero's avatar, name, level, class, HP and last played time. Tapping a card resumes the story. Missing illustration falls back to the world's cover art. |
| **Stories, first run** | Large title, a welcome line in Literata 20, a swipeable row of 270 pt world cards (illustration, genre eyebrow, name, one-line pitch, "Begin here"), page dots, then "Describe your own world" and "Surprise me with a ready-made hero." Picking a world opens hero creation with that world preselected. |
| **New chronicle** | Steps: World → Hero → Opening scene. Tone segmented control, name field, calling chips, attribute steppers with points left. Pinned bottom bar with Back and the primary action. |
| **Story feed** | See section 7. |
| **Combat** | Same feed plus a two-column vitals row (player HP and enemy HP) and the enemy's intent in muted text. |
| **Bag (sheet)** | Medium/large detents. Title, slot count, close. Segmented filter (All, Gear, Consumable, Quest). 4-column tile grid (`raised`, `md`); selected tile in `amberSelected`; equipped badge "E"; "NEW" badge in `gainTint`/`gain`; empty slots in a slightly darker fill. Detail panel with item art, name, type, flavor text and actions (primary Use/Drink, then Give, Drop). Using an item takes the player's turn and sends the action to the narrator. |
| **Character (sheet)** | Large detent. Avatar, name, level and class, XP bar, vitals tiles (Health, Stamina, Armor/Gold), 3 × 2 attribute grid (highlight the class's key stat in amber), conditions, equipped slots. |
| **Journal (sheet)** | Segmented: Quests, People, Places, Lore. "The story so far" recap card, active quest on `amberWash` with checked, current and upcoming objectives, then other quests and "Completed (n)". |

---

## 10. Components

- **Primary button:** 50 tall, capsule, `amber` fill, `onAmber` text, `headline`.
- **Secondary button:** 50 tall, capsule, `control` fill, `textPrimary` text.
- **Text button:** `amber` text, semibold 15, at least 44 tall.
- **Chip:** 36 tall, capsule, `control` fill, `textSecondary` 14. Selected: `amberSelected` fill, `amberLight` text.
- **Segmented control:** `control` track, `sm` radius, 2 pt inset; selected segment `selected` fill, radius 8, 32 tall.
- **Progress bar:** 4 tall capsule, `track` background, meaning color fill.
- **Sheet:** `sheet` fill, `xl` top corners, grabber 36 × 5, over a `scrim` backdrop. Close with "Done" (amber text) or a 32 pt circular close button on `raised`.
- **Icons:** SF Symbols, regular weight, outline style (`heart`, `bolt`, `bag`, `book.closed`, `dice`, `key`, `mappin`, `drop`, `shield`, `flask`, `plus`, `minus`, `chevron.left`, `arrow.up`, `slider.horizontal.3`, `pencil`, `eye`). Never emoji.

---

## 11. Motion and haptics

| What | Behavior |
|---|---|
| Narration | Streams in as it is generated |
| Event line | Fades in 200 ms after its passage completes |
| Vitals | Count to the new value over 400 ms |
| Illustration | Fades in over 300 ms into its reserved space |
| Roll | Die tumbles for 600 ms; light haptic on landing |

With Reduce Motion on, replace all of these with simple cross-fades.

---

## 12. Accessibility

- Text contrast at least 4.5:1 (3:1 for 24 pt and larger). Nothing readable below `textMuted`.
- Tap targets at least 44 × 44.
- Icon-only buttons need an accessibility label ("Open bag", "Send", "Journal").
- Event lines read as one VoiceOver element per event, e.g. "Health down 6, now 18 of 30."
- Illustrations need an accessibility label describing the scene (ask the image tool for alt text).
- Support Dynamic Type up to the accessibility sizes; the feed must reflow, not truncate.

---

## 13. Don'ts

- Don't put borders, dividers, outlines or shadows on anything.
- Don't box, card or tint narration.
- Don't turn game events into cards (except the two moments in section 7).
- Don't use amber for decoration or for anything that doesn't need the player.
- Don't convey meaning with color alone.
- Don't add a tab bar or move in-game panels out of sheets.
- Don't use emoji as icons.
- Don't introduce new colors, radii or font sizes; extend this file first.

---

## 14. SwiftUI token sketch

A starting point for the token layer. Keep views referring to tokens only.

```swift
import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

enum EpochColor {
    // Surfaces
    static let scrim        = Color(hex: 0x07080A)
    static let base         = Color(hex: 0x0E1014)
    static let sheet        = Color(hex: 0x13161B)
    static let card         = Color(hex: 0x15181D)
    static let control      = Color(hex: 0x1A1D23)
    static let player       = Color(hex: 0x1B1E24)
    static let raised       = Color(hex: 0x20242C)
    static let track        = Color(hex: 0x23272F)
    static let selected     = Color(hex: 0x2C313B)
    static let grabber      = Color(hex: 0x3A404C)
    // Text
    static let textPrimary   = Color(hex: 0xEDE7DB)
    static let textSecondary = Color(hex: 0xCFC8BB)
    static let textMuted     = Color(hex: 0x8E887D)
    static let textFaint     = Color(hex: 0x6E6A62)
    // Accent
    static let amber         = Color(hex: 0xE5A85A)
    static let amberLight    = Color(hex: 0xF2C287)
    static let onAmber       = Color(hex: 0x1A1206)
    static let amberWash     = Color(hex: 0x1E1A14)
    static let amberTint     = Color(hex: 0x2A2116)
    static let amberSelected = Color(hex: 0x3A2C17)
    // Game meaning
    static let gain          = Color(hex: 0x7CC4B4)
    static let gainTint      = Color(hex: 0x1E2A28)
    static let loss          = Color(hex: 0xE07A6E)
    static let enemy         = Color(hex: 0xB9665C)
    static let condition     = Color(hex: 0x9CC0E8)
    static let conditionTint = Color(hex: 0x161D26)
    static let gold          = Color(hex: 0xD9C38A)
    static let entityLink    = Color(hex: 0x4F6E67)
    static let entityText    = Color(hex: 0xF4E6CB)
}

enum EpochRadius {
    static let sm: CGFloat = 10
    static let md: CGFloat = 18
    static let lg: CGFloat = 22
    static let xl: CGFloat = 28
}

enum EpochSpace {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 40
    static let narrationMargin: CGFloat = 22
}

enum EpochFont {
    // SF Pro styles use system text styles so they scale with Dynamic Type
    // (default sizes match the table: 34, 17, 15, 13, 12).
    static let largeTitle  = Font.largeTitle.bold()
    static let storyTitle  = Font.custom("Literata", size: 23, relativeTo: .title2).weight(.semibold)
    static let itemTitle   = Font.custom("Literata", size: 19, relativeTo: .title3).weight(.semibold)
    static let narration   = Font.custom("Literata", size: 18, relativeTo: .body)   // line spacing ≈ 12
    static let description = Font.custom("Literata", size: 15, relativeTo: .subheadline)
    static let caption     = Font.custom("Literata", size: 13, relativeTo: .footnote).italic()
    static let headline    = Font.headline
    static let uiBody      = Font.subheadline
    static let eventLine   = Font.footnote.monospacedDigit()
    static let eyebrow     = Font.caption.weight(.semibold)  // uppercase, tracking 0.72
}
```
