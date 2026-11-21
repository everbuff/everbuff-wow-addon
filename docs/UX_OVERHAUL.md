# EverbuffJournal UX overhaul: design spec (v2, 2026-11-20)

This is the lead product designer spec for the addon window. It revises v1 with the critics' changes I agree with. The rejected changes are listed in §7.

It is based on the Mastercraft research, audit A (Home/Combat), audit B (Loot/Character/Settings/chrome), the player-needs analysis, and the code on `origin/main` 21d3a4b (0.9.51). Code facts were checked against that tree. Wherever a code fact changed a critic's request, the section says so.

**Normative order.** When parts of this spec disagree, the numbers win in this order:
1. the constant tables in §2;
2. the y lists and column budgets in §4;
3. the wireframes, which are indicative (±8 px).

**What stays.** The founder-approved look stays:
- Quiet Precision tokens (`Theme.lua`);
- charcoal surfaces and one mint accent;
- Inter and Chakra Petch;
- flat square panels;
- a mint underline on the active tab.

Mastercraft is the model for structure, hierarchy, copy, empty states and polish. Its brown/gold palette is not adopted.

---

## 0. Scope tonight, phase 2, and the approval gate

### 0.1 Tranche 1 (tonight)

Branch `ux-overhaul` from `origin/main` 21d3a4b. It contains:
- foundation: tokens, fonts, formatters and glyph textures;
- the kit pieces listed in §5 step 2;
- chrome and navigation, including the alias table and settings keys;
- display-only honesty fixes;
- **Home > Now**;
- the whole **Dungeons** group: Runs, By dungeon and the run page.

The night ends with a **draft PR** and a **`needs approval` issue**. There is no merge, no version bump, no tag and no CurseForge or Wago package.

### 0.2 Phase 2 (later, in this order)

1. Sessions plus the session page plus Activity.
2. Fights restyle and collapse.
3. Deaths with Mine/Everyone.
4. Loot (Items, Gold, Auction house).
5. Character (Leveling, Reputation, Professions).
6. The Settings rewrite.
7. First run and What's new.
8. Every WIDE rail.
9. Moving Settings, Timeline and Items out of `Emitter.lua`.
10. Stored-data changes (§5 step 3b).
11. Removing the shims and bumping the version.

### 0.3 Unconverted panes tonight

Every pane not rebuilt tonight keeps working through the `FONT_ROLE`, `UI.SP`, `C.gold` and `UI.Tabs` shims, inside the new chrome. It must render with 0 spill, 0 overlap and 0 cut. It is not redesigned yet. The approval issue labels these screenshots "not yet redesigned".

**Temporary sub-tabs tonight**, so that nothing is lost before phase 2:

| Host | Sub-tabs tonight |
|---|---|
| Home | Now · Sessions · Activity (the old Timeline, unchanged) · Fights · Deaths |
| Loot | Items · Gold · Auctions (unchanged) |
| Character | today's sub-tabs (Quests, Reputation, Professions, Crafting) |
| Settings | today's sub-tabs |

### 0.4 Approval gate

Founder rule: no product decision is made alone. Everything the player sees goes to the founder as one `needs approval` issue on everbuff/everbuff-wow-addon, with before and after shots at 900x580 and 1600x1000, normal and long. These items need his explicit OK:

1. Combat is renamed Dungeons and moves to second in the nav.
2. Fights and Deaths move under Home.
3. Overview is renamed Now.
4. Timeline becomes the session Activity section (phase 2; a temporary Activity sub-tab tonight).
5. Auctions becomes a Gold breakdown "Auction house" (phase 2).
6. Crafting folds into Professions, and Quests fold into Leveling (phase 2).
7. The title-bar status reads "Recording" (no CAPTURING, no zone).
8. The version leaves the title bar.
9. Coords columns show only at WIDE (window 1260 px wide or more) and on detail pages.
10. The GOLD PER SESSION chart moves to the Sessions rail at WIDE. The XP PER SESSION chart is cut.
11. Short empty sessions are hidden by default. Fights defaults to Important. Items defaults to Green and better.
12. The fixed page subtitles are cut. Each page opens on a live answer line instead.
13. The first-run guide, the What's new strip, and the in-window combat-log notice. Needs §6.4 says "No new in-game notifications". These live inside the window, but he decides.
14. Money in the window shows game coin icons instead of the letters g, s and c.
15. Durations and deltas use words ("42s faster"), with no mm:ss.
16. The window scale minimum rises to 90%.

**Order of work:**
1. The issue opens at the start with this spec and the before shots.
2. After shots are added as comments when steps 4, 5 and 6 land.
3. The PR stays a draft and links the issue.
4. Nothing merges before he replies.

Every issue and PR text ends with `<!-- claude -->`, uses no em dashes, and carries no Claude trailer.

---

## 1. Principles

1. **Answer first, data second.** Every screen opens with a live answer: the `UI.Summary` line, a hero, or a NEXT list. Only then comes the list. A static description never takes that place. Descriptions live in the nav and sub-tab tooltips and in empty states.
2. **Now before lifetime, and every number states its period.** The defaults are this session (Home) and this run (Dungeons). Every number's period is named on its card, on its group header, or on its column header. Lifetime numbers sit one click or one hover away.
3. **Two edges, named and measured.**
   - Boxes (cards, strips, row bands, hover bands, button boxes) start at x 192 (`BOX_L`) and end at `BOX_R` (`W-24`).
   - Text starts at x 204 (`TEXT_L`) and ends at `TEXT_R` (`W-36`). That covers sub-tab labels, section headers, summary lines, table cells, card text and empty text.
   - One vertical rhythm: control row at y 52, content at y 92.
   - All numbers are named constants in `UI.G`. No pane uses literal offsets.
   - The Settings column (§4.12) follows the same edges at 900.
4. **One level of sub-tabs, then a detail page with Back.**
   - The levels are: sidebar, one sub-tab row, then in-page controls or a detail page with "‹ Back". Tabs never nest.
   - A view has at most one segmented control (with an optional "More ▾" overflow that belongs to it), one filter button and one search.
   - The filter button and the search may sit on the list's section header instead of in the control row.
   - A segmented control inside a setting row does not count toward this limit.
5. **Colour carries one meaning each.**
   - Mint means selected, clickable or live.
   - `good`, `warn` and `bad` appear only on deltas, event results and fixed thresholds. `warn` and `bad` text always has a leading 6 px dot of the same colour, so state is never carried by hue alone.
   - Item quality and class colours appear only on item and character names.
   - Money uses coin icons.
   - Red never means "unusual bookkeeping".
6. **Never contradict yourself, never guess, and say where a number comes from.**
   - Two numbers on one screen share a period and a rate, or say that they don't.
   - Unknown values show "-" with a tooltip.
   - Placeholder strings ("quest", "Unknown", "[link]") never reach the screen.
   - A number the addon cannot read in game is not shown. It is never shown as "-" either.
7. **Every empty state says how to fill it, right where the data would be.**
   - One sentence, placed directly under its header.
   - Loading, empty and no-match are three different messages.
   - An all-clear message is positive.
8. **Plain player words; internals live in tooltips or Advanced.**
   - Banned unless explained: "Saved to", "estimate", "Notable", "Strangers", "SavedVariables", "beacon", "toast", "flag", "rows", "segments", "split".
   - One date dialect, one duration dialect (deltas included), one money dialect.
   - The word for a fight in copy is "pull". The tab may stay "Fights".

---

## 2. Design system

All of this lives in `UI.lua`, as constants plus kit functions. Converted pages call kit functions only. They never:
- call `SetColorTexture` with literal RGB;
- hard-code offsets;
- use Blizzard templates (checkbox, slider and close button are all replaced).

### 2.1 Spacing scale (`UI.S`, from `Theme.space`)

| Token | px | Use |
|---|---|---|
| S1 | 4 | icon to text inside a badge, the menu's gap below its button |
| S2 | 8 | gap between controls in a row, icon to label |
| S3 | 12 | card padding, table inset, column gap, gap between cards, the text inset from a box edge |
| S4 | 16 | window bottom margin, sidebar icon x |
| S5 | 24 | the gap between sections, sub-tab label gap, content side margin |
| S6 | 32 | big empty state padding |
| S7 | 48 | big empty state offset from content top |

Rule: every offset is a sum of tokens. `UI.SP` stays as an alias until phase 2.

### 2.2 Window grid (`UI.G`), in window units at scale 1.0

| Constant | Value | Notes |
|---|---|---|
| `WIN_MIN` / `WIN_MAX` | 900x580 / 1600x1000 | unchanged |
| `BORDER` | 1 | black edge; the old 12 px `#111` band is removed |
| `TITLE_H` | 40 | y 0 to 40; 1 px `line` rule at y 39 |
| `SIDEBAR_W` | 168 | x 0 to 168; 1 px `line` rule at x 167 |
| `BOX_L` | 192 | left edge of every content box |
| `TEXT_L` | 204 | `BOX_L + S3`; left edge of every content text |
| `BOX_R` | `W - 24` | 876 at 900, 1576 at 1600; the scroll thumb lives in the 24 px margin |
| `TEXT_R` | `W - 36` | 864 at 900; right edge of right-aligned text and numbers |
| `CW` | `W - 216` | content box width: 684 at 900, 1384 at 1600 |
| `CTRL_Y` | 52 | control row, h 28 (52 to 80); 1 px `line` rule at y 80 across `CW` |
| `CONTENT_TOP` | 92 | `CTRL_Y + 28 + S3`; first content pixel on every page |
| `CONTENT_BOTTOM` | `H - 16` | 564 at 580, 984 at 1000 |
| `CH` | `H - 108` | content height: 472 at 580, 892 at 1000 |
| `RAIL_W` | 336 | right rail width (phase 2) |
| `MAIN_MAX` | 1024 | main column and tables are never wider |
| `WIDE` | `CW >= 1044` | window width 1260 or more (`684 + 24 + 336`) |
| `MAIN_W` | WIDE: `min(CW - 360, 1024)`; else `CW` | main column width; 1024 at 1600 |
| `TABLE_MAX` | 1024 | tables are capped and left-aligned |

**No-rail behaviour (tonight, and any page without a rail).** The main column is `min(CW, MAIN_MAX)`, left-aligned at `BOX_L`. The spare width to the right stays empty `canvas`. Coords columns and WIDE-only columns key off the same `WIDE` constant.

**Control row edge (UX polish round 1).** The control row ends where the page's content ends: at `BOX_L + MAIN_W`. The right-aligned page controls (filter, segmented control, search, More, Older and Newer) and the control-row rule end on that edge, the same edge as the hero, the cards and the tables. At 900 it is `BOX_R` (876); at 1600 it is window x 1216. So a filter sits over the list it filters, never 360 px to its right.

**Scroll model.** Each page is one `UI.ScrollChild`. The hero, the summary and the table scroll together, so a page never stacks two scroll regions. The thumb is a custom slim one:
- 4 px wide, `lineControl` (hover `fgFaint`);
- at x `BOX_R + 10`;
- shown only when the content overflows.

`UI.SCROLLBAR` becomes 0 for kit tables.

**Resize grip.** 16 px at bottom-right, inset 4.

### 2.3 Row heights (`UI.H`)

| Token | px | Role |
|---|---|---|
| `CONTROL` | 24 | buttons, segmented controls, filter buttons and search inputs in rows and section headers |
| `TABLE_HEAD` | 24 | table header band |
| `DAY_ROW` | 24 | day group row inside a list, also an in-table group label ("EARNED") |
| `SECTION` | 24 | section header |
| `SUMMARY` | 24 | the `UI.Summary` answer line |
| `ROW` | 32 | standard one-line list row; item icon 20 |
| `SETTING` | 32 | one setting; 48 with a one-line description |
| `NOTICE` | 40 | notice strip |
| `ROW2` | 48 | two-line row (NEXT, WORTH A LOOK, professions, What's new): icon 24, title 13, meta 11 |
| `STAT` | 80 | stat card |
| `HERO` | 104 | the single hero card of a page |
| `NAV` | 36 | sidebar row |

Height follows importance. A page has only one hero. Finished or empty things never get the hero.

### 2.4 Type scale (font objects in `UI.lua`)

All text has a 1,-1 black shadow at 0.85 alpha (1.0 on HERO, DISPLAY and TITLE). The measured heights go into `tests/fontmetrics.lua`, and stacked text in cards and heroes is asserted not to overlap.

| Role | Font object | Face, size | Line h | Default colour | Used for |
|---|---|---|---|---|---|
| WORDMARK | `EverbuffWordmark` | Chakra Petch SemiBold 15 | 19 | `fg` | title bar "everbuff" only |
| HERO | `EverbuffHero` | Chakra Petch Bold 24 | 30 | `fg` | the single answer of a hero card |
| DISPLAY | `EverbuffDisplay` | Chakra Petch Bold 20 | 25 | `fg` | stat card values |
| TITLE | `EverbuffTitle` | Inter SemiBold 15 | 19 | `fg` (class colour for a character) | hero name, detail page title, first-run step title |
| ROW_TITLE | `EverbuffRowTitle` | Inter SemiBold 13 | 16 | `fg` | nav labels, sub-tab labels, ROW2 titles, setting labels, big-empty title |
| BODY | `EverbuffBody` | Inter Medium 12 | 15 | `fg` | table cells, summary line (`fgSubtle`), sentences |
| BODY_STRONG | `EverbuffBodyStrong` | Inter SemiBold 12 | 15 | `fg` | button labels, the figures in a summary line, numbers that matter |
| META | `EverbuffMeta` | Inter Medium 11 | 14 | `fgMuted` | second lines, card meta, descriptions |
| LABEL | `EverbuffLabel` | Inter SemiBold 10, UPPERCASE | 13 | `fgMuted` | section headers, column headers, stat labels, day rows |
| BADGE | `EverbuffBadge` | Inter SemiBold 9, UPPERCASE | 11 | per badge | badges |

**Fitting rules:**
- A name that does not fit steps down 1 px at a time to 10 (`UI.Fit(fs, min)`). Only then does it shorten with "...", and the full text goes in the tooltip.
- Numbers never shorten. Columns are measured from their widest value (the existing `measure` mechanism in `UI.Table`).
- Zone and name lists show whole items plus "+N".
- Labels in fixed-width boxes (card labels) must fit at their size at 900 with no truncation. `tests/panes/kit.lua` measures every card label.

**Scale floor.** The window scale minimum is 90%. A stored value below that is clamped on load. That keeps LABEL at 9 px and BADGE at 8.1 px effective at the floor.

`FONT_ROLE` keeps mapping the old Blizzard template names, so unconverted panes keep working.

**Glyph coverage.** The bundled Inter has 230 glyphs. It has "›", "‹", "↓", "↑", "·" and NBSP. It has no "▾", "✕", "ⓘ" or "→", and Chakra Petch lacks ▾, ✕ and ⓘ too. So:
- `UI.Glyph(name, size, colour)` draws `chevronDown`, `clear`, `info`, `dot` and `check` from WHITE8x8 strokes.
- The string "→" is never shown; use "to" or "›".
- `tests/glyphs.lua` scans every string literal a pane shows (kit text calls and `SetText` literals in converted panes) against the font cmap, and fails on a missing codepoint.

### 2.5 Colour tokens (`UI.C`, keyed by role; the old keys stay as aliases)

| Token | Theme key | Hex | Meaning |
|---|---|---|---|
| `canvas` | bg-canvas | #111111 | window and content background |
| `sunken` | bg-sunken | #0B0B0C | title bar, sidebar, inputs, bar tracks |
| `panel` | bg-panel | #19191B | cards, strips, table stripes (alpha 0.5) |
| `raised` | bg-raised | #222225 | selected nav row, pressed ghost, neutral badges |
| `hover` | bg-hover-raised | #2A2A2E | hover band (alpha 0.6), button hover |
| `line` | line | #2E2E33 | hairlines, card edges, table head rule |
| `lineStrong` | line-strong | #3A3A40 | ghost button and input edges |
| `lineControl` | line-control | #6E737A | hovered edges, checkbox edge, scroll thumb |
| `fg` | fg | #F3F4F5 | primary text |
| `fgSubtle` | fg-subtle | #C7CACD | secondary values |
| `fgMuted` | fg-muted | #8C9197 | labels, meta |
| `fgFaint` | fg-faint | #6E737A | placeholders, disabled, chevrons at rest |
| `accent` | accent | #0CD29D | see the accent rules |
| `accentFg` | accent-fg | #35EEBB | link text, selected segment text |
| `accentTint` | accent-tint-n2 | #17332D | selected segment fill, active filter fill, live badge fill, rested XP overlay |
| `good` | success-fg | #4CC38A | faster than best, all-clear |
| `warn` | warning-fg | #F1C15B | slower than best, threshold reached |
| `bad` | danger-fg | #FF6B6F | deaths and wipes as events, threshold exceeded, destructive confirm |
| quality / class | q-* / c-* | | item names and character names only |

**Accent rules**
1. Mint appears only on:
   - the selected sub-tab underline (2 px);
   - the selected nav bar (3 px);
   - the one primary button;
   - link text;
   - the live dot (title-bar chip, IN PROGRESS badge);
   - selected segment text and fill;
   - an active filter button;
   - the selected table row mark (3 px);
   - the XP bar fill.
2. Mint never appears on a value. Values are `fg` or `fgSubtle`.
3. `good`, `warn` and `bad` appear only on deltas, on event results (Kill, Wipe, Died), and on these thresholds:

   | Threshold | `warn` | `bad` |
   |---|---|---|
   | Durability, the lowest equipped slot from `GetInventoryItemDurability` over slots 1 to 18, read on show | 45% or below | 20% or below |
   | Free bag slots | | 2 or fewer |
   | Instances this hour, only when the player set a limit (`Runs.limit()`) | 1 left | 0 left |
   | Reputation standing | | Hated or Hostile |

   `warn` and `bad` text always has a leading `UI.Glyph("dot", 6)` in the same colour. Buttons (danger ghost) and result words that already have their own glyph are exempt.
4. **Money** uses `ns.fmtMoney(c, {icons=true, units=2})`:
   - digits in the row's text colour, each followed by NBSP and the game coin icon at 12x12 (`Interface\MoneyFrame\UI-GoldIcon`, `UI-SilverIcon`, `UI-CopperIcon`, the `GetCoinTextureString` style);
   - units are joined with a space;
   - list cells, cards, meta lines and summary lines show at most the two largest non-zero units, with the full amount in the tooltip;
   - only the Gold Journal and the BALANCE tooltip always show copper;
   - money columns are measured from their widest two-unit value;
   - a signed value always carries "+" or "-";
   - a rate is always signed and its basis is named once on its card, header or line ("per hour of play");
   - money cells never carry a "/h" suffix (the column header says "per hour").

   In this spec's wireframes, money is written as "26g 99s" for readability. On screen it is digits plus icons.
5. `C.gold` (today grey #C7CACD) is retired as a meaning. Its callers move to `fgSubtle` or LABEL.

### 2.6 Shared formatters (one dialect everywhere)

| Function | Output |
|---|---|
| `UI.fmtClock(t)` | `21:35`, only inside a list grouped by day |
| `UI.fmtWhen(t)` | `Today 21:35`; `Yesterday 21:35`; this year `Mon 16 Nov, 21:35`; older `16 Nov 2025`. No full weekday names outside day rows. |
| `UI.fmtDate(t)` | the same without the time: `Today`, `Yesterday`, `Mon 16 Nov`, `16 Nov 2025` |
| `UI.fmtDay(t)` | day rows: `TODAY`, `YESTERDAY`, `MONDAY 16 NOV` |
| `UI.fmtDur(s)` | `45s`, `10m 5s`, `1h 39m`, `2d 4h`. Never mm:ss |
| `UI.fmtDelta(s)` | `42s faster` (`good`), `3m 29s slower` (`warn`, with dot), `same as best`, `best`, `first run`; no arrows. Replaces `Runs.deltaText` for display; `Runs.signed` stays for chat and the slash output. |
| `UI.fmtNum(n)` | `116,310` |
| `UI.fmtRange(a, b, live)` | `21:35 to 22:13`; live `21:35 to now` |
| `UI.plural(n, "item")` | `1 item`, `2 items`; also faction, profession, pull, run, quest, entry |
| `UI.fmtPlace(zone, sub)` / `UI.fmtCoords(x, y)` | unchanged; always two columns (house rule) |

### 2.7 Component catalog

All measurements are in window units. "y" is relative to the component's own top, and "x" is relative to the component's own left unless it is marked as a window x.

**Chrome**
- **Title bar** (h 40, `sunken`):
  - mark 20x20 at x 16, centred at y 20;
  - WORDMARK "everbuff" at x 44;
  - its tooltip: "Everbuff 0.9.51 · type /eb help for every command".
- **Close button:**
  - 24x24 flat at window x `W-48` to `W-24` (its box edge sits on `BOX_R`), y 8;
  - glyph `clear` 10 px `fgMuted`; hover `hover` fill and glyph `fg`;
  - replaces `UIPanelCloseButton`.
- **Status chip:**
  - h 24, right edge at x `W-56`, pad 8, no fill; hover `hover` fill;
  - click opens Settings > Data and sync (tonight: today's Capture sub-tab);
  - content: an 8 px dot, then META sentence case in `fgSubtle`.
  - States:

    | State | Text | Colour |
    |---|---|---|
    | Recording | "Recording" | dot `accent` |
    | Combat log off | "Recording, combat log off" | dot and text `warn` |
    | Desktop app stale | "Recording, desktop app not seen" | dot and text `warn` |
    | Starting | "Starting" | dot `warn` |
    | Standing by | "Standing by" | dot `fgFaint` |

    "Desktop app not seen" shows only when `ns.DB.combat.lastAck` exists, its time is more than 3 days old, and at least 1 fight is waiting. A player who never installed the app sees plain "Recording".
  - Tooltip, three lines:
    - "Recording · The Barrens · session 38m";
    - "Desktop app's save confirmed 2m ago" (or "Desktop app: not seen yet");
    - "4 fights not yet saved by the desktop app".

    The count comes from the one `Sync` function (§5 step 3a).
- **Nav row** (h 36, x 8 to 160; first row top at y 48, pitch 36, no gap; the label centre of the first row is y 66, equal to the sub-tab label centre):
  - icon 16 at x 16; ROW_TITLE label at x 44;
  - selected: `raised` fill, 3 px `accent` bar at x 8, label `fg`;
  - hover: `hover` fill at 0.6, label `fg`;
  - the tooltip is the host's description (§3.1);
  - Settings is pinned with its bottom at y `H-16` (528 to 564 at 580).
  - Tonight the icons are today's textures, desaturated with a `fgMuted` vertex tint (`fg` when selected). Custom glyph TGAs come in phase 2 and are an in-game check.

**Control row** (y 52, h 28, rule at y 80)
- **Sub-tabs, left:**
  - ROW_TITLE labels, the first at window x `TEXT_L` (204), 24 px between labels;
  - active: label `fg` with a 2 px `accent` underline as wide as the label, at y 78 to 80;
  - inactive `fgMuted`; hover `fg`;
  - each tab's tooltip is its description sentence (§4);
  - no boxes, no fixed slots, no inner pane: the `UI.Tabs` bordered pane is deleted for converted hosts.
- **Page controls, right:** right-aligned so the last control's box edge is at `BOX_L + MAIN_W` (`BOX_R` at 900, x 1216 at 1600, §2.2); h 24 at y 54; S2 apart. The control-row rule ends on the same edge.
- **Detail pages** replace the sub-tabs with the Back button. There is no breadcrumb line.

**Summary line** (`UI.Summary`, h 24, at `CONTENT_TOP`, then S3 to the next block)
- BODY in `fgSubtle`, with the figures in BODY_STRONG `fg`, at window x `TEXT_L`, y 4; one line.
- Segments are joined with " · ". Each segment may carry its own tooltip and click (a link segment is `accentFg`).
- It holds data, never a description. Example: "1 instance this hour · Ragefire Chasm: 2 of 4 bosses down, resets in 1h 59m".

**Section header** (h 24)
- LABEL `fgMuted` at x 12 (window x 204), y 7.
- Optional right side, right-aligned at `w-12`, in this order:
  - a META summary in `fgSubtle`;
  - a link in META `accentFg`, with hover `accent` and an underline;
  - or, for lists, the list's filter button and search (h 24, at y 0).
- No rule, no box. Content starts at +24. Sections are S5 apart.

**Stat card** (h 80, `panel` fill, 1 px `line` edge, pad 12)
- `UI.StatRow(parent, n, width)` sets card width to `floor((width - S3*(n-1)) / n)`, and the last card takes the remainder.
- LABEL at y 12 (to 25); DISPLAY value at y 29 (to 54); META at y 58 (to 72), one line; bottom pad 8.
- The label fits without truncation (measured at 900).
- A clickable card shows chevron "›" (META `fgFaint`; `fg` on hover) at x `w-20`, y 12, and its label ends by `w-24`. Hover: edge `lineControl`, fill `hover` at 0.4.
- The value shrinks from 20 to 14 before money drops to one unit. The full value is in the tooltip.

**Hero card** (h 104, `panel` fill, 1 px `line` edge, pad 12)
- Optional image 56x56 at x 12, y 24 (square, 1 px `line` edge, never masked). When the image is present, text starts at x 80; otherwise at x 12.
- Slots:

  | y | Slot |
  |---|---|
  | 12 to 31 | TITLE (an optional LABEL before it on the same line, S2 apart; badges inline) |
  | 34 to 64 | HERO: the one answer |
  | 68 to 82 | META line 1; optional right-aligned META at `w-12` |
  | 86 to 92 | slot 4 is either a bar (h 6, track `sunken`, fill `accent`, a minimum 4 px sliver once there is any progress) ... |
  | 86 to 100 | ... or META line 2 |

- The bar's labels sit on META line 1, above the bar. The label font string is a child of the hero frame, at a higher frame level than the bar.
- Optional single primary button, h 28, right-aligned at `w-12`, vertically centred (y 38). When present, the text slots end at `button left - S3`.

**List / table** (`UI.Table`, restyled)
- Header band h 24, no fill, LABEL `fgMuted`, 1 px `line` rule under it. Numeric headers are right-aligned at their column's right edge.
- Rows h 32. Inset S3 left and right, column gap S3. Width budget: `insets 24 + sum(widths) + 12*(columns-1) + 12*(right-then-left boundaries) = table width`.
- A left-aligned column right after a right-aligned one is S5 (24) from it, not S3: at S3 two headers read as one label ("TIME VS BEST") and two values as one ("4m 47s -"). Status-word columns that follow numbers ("Vs best", "Vs previous", "Last gain") are right-aligned. `tests/panes/columns.lua` flags any right-then-left pair under 24.
- A text column other than the first may carry `max` (for example From and Place at 160): it stops growing there and shortens, so the first text column always gets the flex space.
- Cells:
  - first text column BODY `fg`;
  - other columns BODY `fgSubtle`;
  - numbers that matter BODY_STRONG `fg`;
  - status words in cells are sentence case ("first run", "best"); badges appear only after titles and in the first column.
- Stripes: odd absolute index gets `panel` at 0.5. The contrast against `canvas` is asserted at 3 L* or more.
- Hover: `hover` band at 0.6. Selected: a 3 px `accent` bar at x 0 plus `raised` fill.
- A row that opens something has a last column "›" 12 px wide (`fgFaint`, `fg` on hover). A row that opens nothing has no chevron and no hover band.
- Day rows: h 24, LABEL `fgMuted` at x 12, "TODAY · 3 RUNS". Rows under a day row show `fmtClock` only.
- Options:
  - `max` (px) for flex columns; with every flex column at its max, the table shrinks and stays left-aligned;
  - `group` (day rows);
  - `collapse` (fold consecutive like rows into one row; expand on click);
  - `wide = true` on a column shows it only at WIDE.
- **Inline text** (BODY `fgMuted`, at y +12 under the header band, x 12, wrapping at `min(w-24, 520)`). The header stays visible.
  - Loading: "Loading..."
  - Empty: the page's sentence.
  - No match: `No run matches "rag". ` plus the link "Clear search".

**Segmented control** (h 24)
- Segments share one width: the longest label plus 24, min 64.
- 1 px `lineStrong` outline around the group, 1 px dividers.
- Selected: `accentTint` fill, BODY_STRONG `accentFg`. Unselected: BODY_STRONG `fgMuted`. Hover: `fg`.
- Used for exclusive choices only. An attached "More ▾" overflow is a filter button that sits S2 to its right.

**Filter button** (h 24, ghost)
- 1 px `lineStrong` edge, pad 12, BODY_STRONG `fgSubtle` label, then `UI.Glyph("chevronDown", 8)` at right pad 8.
- Width: the current label plus 44 (it resizes when the label changes; the row re-anchors from the right).
- Active (not the default): `accentTint` fill, label `accentFg`; the chevron becomes `UI.Glyph("clear", 8)`, and clicking the glyph clears the filter.
- **Menu** (`UI.Menu`, restyled):
  - anchored S1 below the button, left edges aligned, width `max(button width, longest item + 48)`;
  - rows h 24, BODY;
  - the selected item has a 3 px accent bar;
  - at most 10 rows, then it scrolls;
  - a greyed item carries its reason: "Raids · coming soon".

**Search input** (`UI.Search`, phase 2 except where a tonight page needs it)
- 176x24, `sunken` fill, 1 px `lineStrong` edge; focus edge `accent`.
- `UI.Glyph` magnifier 12 at x 8; text inset 26; placeholder `fgFaint`.
- A `clear` glyph button 16 at `w-20` while text is present. Esc clears the text and drops focus.
- 176 is the only search width.

**Buttons** (h 24; 28 in heroes and empty states; pad 12; BODY_STRONG; pressed shifts the label 1 px down; disabled alpha 0.4 with no hover; every kit button plays `PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)` on click, through a guarded call)
- **Primary:** `accent` fill, `on-accent` text; hover `accent-hover`; pressed `accent-pressed`.
  - At most one per view, across the page, notices and rails.
  - A notice's button is primary only when the view has no other primary; otherwise it is a ghost.
- **Ghost:** no fill, 1 px `lineStrong`, text `fgSubtle`; hover edge `lineControl` and text `fg`; pressed `raised` fill.
- **Danger ghost:** a ghost with text `bad`.
  - The first click arms it: the label becomes "Click again to clear 78 pulls", and it disarms after 4 s.
  - Under it, in META `fgMuted`: "Cannot be undone."
- **Back:** a ghost "‹ Runs" (the label names the list it returns to). Its box sits at window x 192, so its label lands on 204. The list keeps its scroll offset and selection. Esc keeps its current meaning (it closes the window through `UISpecialFrames`).
- **Link:** META or BODY `accentFg`, no box.

**Badge** (h 16, pad 6, BADGE caps, tint fill plus matching fg; S2 after the title, vertically centred on the title line)

| Badge | Fill | Text | Note |
|---|---|---|---|
| BEST | success-tint-n2 | `good` | tooltip "Fastest run with these 6 bosses, first pull to last kill" |
| IN PROGRESS | `accentTint` | `accentFg` | 6 px `accent` dot |
| WIPE | warning-tint-n2 | `warn` | |
| DIED | danger-tint-n2 | `bad` | |
| FIRST RUN, KEPT, BOSS, ELITE, COMING SOON | `raised` | `fgSubtle` | neutral |

**Notice strip** (h 40, `panel` fill with a 3 px left bar in `warn`, or `accent` for What's new)
- `UI.Glyph` icon 16 at x 12; BODY `fg` sentence at x 36.
- One button (h 24) right-aligned at `w-40`; dismiss `clear` glyph 16 at `w-24`.
- Placed at `CONTENT_TOP`; the page moves down 52 (40 plus S3).
- Used only for something the player can fix, or for What's new.

**Empty state, big** (a whole page with no data)
- The block is centred in the content box, top at `CONTENT_TOP + 48`.
- Icon 32 (`fgFaint`) at y 0; ROW_TITLE `fg` title at y 44; BODY `fgMuted` sentence at y 64, max width 420, centred.
- At most two buttons, S5 under the text (at most one primary).

**Inline empty:** a section with no rows shows its sentence directly under its header and takes 24 px.

**Detail page** (`UI.Detail(host, items, index, render)`)
- `items` is the list's current sorted and filtered order. `render(item, content)` draws the page.
- The host keeps the list's scroll offset and selection and restores them on Back.
- Control row:
  - Back at window x 192;
  - right-aligned ghosts "‹ Older" and "Newer ›" (h 24), each disabled at its end of `items`.
- Content:

  | y | Element |
  |---|---|
  | 92 to 111 | TITLE with badges inline |
  | 114 to 128 | META line |
  | 140 to 220 | stat card row |
  | 244 onward | sections, S5 apart |

- One scroll at every size. Rails come in phase 2.

**Setting row, checkbox, slider:** phase 2, §4.12.

**Tooltip** (GameTooltip, one format everywhere)
- Line 1: name, white (1,1,1).
- Line 2: one sentence, wrapped, (0.78, 0.79, 0.80).
- Then optional `AddDoubleLine` pairs: the label in `fgMuted`, the value white.
- At most 8 lines.
- Every button, card, badge, nav row, sub-tab and meaningful column header has one. Truncated text shows its full text (the existing `cellTip`).

---

## 3. Information architecture

### 3.1 Navigation (end state after phase 2)

| Sidebar | Sub-tabs | Nav tooltip (the description) |
|---|---|---|
| **Home** | Now · Sessions · Fights · Deaths | How this session is going, and every session, pull and death before it. |
| **Dungeons** | Runs · By dungeon | Every dungeon run against your best, and which dungeon is worth your time. |
| **Character** | Leveling · Reputation · Professions | Your level, your standing, and your skills. |
| **Loot** | Items · Gold | What you picked up, and where every copper came from and went. |
| **Settings** (pinned bottom) | General · Gold display · Data and sync | How the window and notifications behave, and whether your data reaches everbuff.gg. |

Tonight's temporary sub-tabs are listed in §0.3.

**Settings keys** (all in `EverbuffDB.settings`; defaults in brackets)

| Key | Default |
|---|---|
| `lastTab`, `lastSub` | Home / now |
| `fightsView` | `"important"` |
| `itemsQuality` | `"green"` |
| `itemsMode` | `"newest"` |
| `sessionsShowShort` | false |
| `goldPeriod` | `"session"` |
| `welcomeDone` | false |
| `whatsNewSeen` | nil (a version string) |
| `advancedOpen` | false |

- The window reopens on `lastTab` and `lastSub`. Detail pages are not restored; their list is.
- Migration on load: `lastTab` and `lastSub` pass through the alias table. An unknown value falls back to Home / now. `scale` is clamped to 0.9 or more.
- Test: a fresh `EverbuffDB` and a 0.9.51 `EverbuffDB` both open on a valid page.

**`UI.Open` aliases** (old key → new key; marked T when active tonight)

| Old key | New key | |
|---|---|---|
| `Combat/dungeons` | `Dungeons/runs` | T |
| `Combat/fights` | `Home/fights` | T |
| `Combat/deaths` | `Home/deaths` | T |
| `Home/overview` | `Home/now` | T |
| `Home/timeline` | `Home/activity` tonight; in phase 2, `Home/sessions` with the live session page open at its Activity section | T |
| `Loot/auctions` | `Loot/gold` with breakdown Auction house | phase 2 |
| `Character/quests` | `Character/leveling` | phase 2 |
| `Character/crafting` | `Character/professions` | phase 2 |
| `Settings/capture` | `Settings/data` | phase 2 |
| `Settings/gold` | `Settings/golddisplay` | phase 2 |

### 3.2 Merged, renamed, moved, cut

| Change | Why |
|---|---|
| Combat renamed **Dungeons**, promoted to second | flagship; removes "Combat > Dungeons > Dungeons" |
| Dungeons' All / Dungeons / Raids tabs removed | Raids becomes "Raids · coming soon" (greyed) in the dungeon filter menu |
| Runs / By dungeon toggles become **sub-tabs** | one level; the dungeon dropdown becomes a filter button on Runs |
| Instance and lockout strip becomes the Dungeons **summary line** | saves 44 px and states the answer |
| Fights and Deaths move to **Home** | they are the story of your sessions |
| Overview renamed **Now** | session-scoped; lifetime moves to tooltips (rail in phase 2) |
| Timeline becomes **Activity** (phase 2: a section of the session page) | needs §5 "Activity log drawer", decided 2026-09-20. All-history search stays: "Search everything you did" on Sessions |
| Timeline's 6 filter tabs become one filter button | groups in §4.2 |
| Fights filters become **Important · All** | "Notable" renamed; Deaths lives in Deaths |
| Auctions becomes a Gold breakdown | it is a gold source |
| Quests fold into Leveling; Crafting folds into Professions | one subject each |
| Settings > Capture splits | health → chip plus Data and sync; diagnostics → Advanced |
| Settings > Gold renamed **Gold display** | says what it sets |
| "Show your gold on screen?" prompt leaves the Gold page | first-run step 2 plus Gold display |
| XP PER SESSION chart: cut | always empty |
| GOLD PER SESSION chart: Sessions rail at WIDE | founder kept it 2026-11-18 |
| Page titles, subtitles and the v1 "value statement" row: cut | the nav row plus the sub-tab are the title; the Summary line, hero or NEXT is the answer |
| Detail-page breadcrumb: cut | repeats the Back label and the title |
| Version in the title bar | moves to the wordmark tooltip and Settings |

### 3.3 Where every existing feature lands (nothing lost)

| Today | Lands in |
|---|---|
| Overview CHARACTER card (level, race and class, gear %) | Now hero (portrait, name, level, race, class, zone); durability becomes a NEXT row at 45% or below |
| EXPERIENCE card, quests/kills split | Now hero XP bar plus rested; split → Leveling "Where your XP comes from" |
| TIME PLAYED card | hero tooltip ("Played in all 1d 1h · at this level 1h 0m"); Leveling card TIME AT LEVEL 18 |
| GOLD card (balance, today, all characters) | Now card GOLD (balance and all characters in the tooltip); Gold page BALANCE |
| COMBAT card (kills, fights) | Now card DEATHS (meta: kills, items); lifetime in its tooltip |
| LEVELING PACE card | Now hero "42m to level 19"; Leveling Levels table |
| "This session" strip and feed | Now WORTH A LOOK (fed by every kind) |
| Home > Timeline | tonight: Home > Activity (unchanged); phase 2: session page Activity plus Sessions search |
| Home > Sessions, live dot | Home > Sessions (IN PROGRESS badge) |
| Sessions gold band | session page GOLD section plus "Open in Gold ›" |
| Combat > Dungeons Runs table, sort, delta, in-progress, kept | Dungeons > Runs (KEPT and IN PROGRESS badges) |
| By dungeon statistics, click to filter | Dungeons > By dungeon |
| Dungeon pick dropdown | Runs filter button |
| Lockouts line and the other characters' tooltip | the Dungeons summary line, lockout segment, same tooltip |
| Instances this hour and day, `/eb instances limit` | the Dungeons summary line, instance segment; tooltip = `Runs.hourTip` |
| Run page tiles and sections | run detail page, all kept (§4.6) |
| Combat > Fights, filters, replay | Home > Fights, fight detail page |
| Combat > Deaths, recap | Home > Deaths, death detail page |
| Loot > Items, quality chips, By item, search | Loot > Items |
| Gold periods, WHO, views, roster filters, flagged toggle, five cards | Gold (§4.9) |
| Loot > Auctions | Gold breakdown Auction house |
| Character tabs | Leveling, Reputation, Professions |
| Settings > General, Gold, Capture, Data | Settings (§4.12) |
| Title-bar capture indicator | status chip |
| Close, ESC, drag, resize grip, position, size, scale | unchanged (custom close; scale floor 90%) |
| Minimap button, gold pill, broker objects, flag, toasts, every slash command | unchanged |

---

## 4. Screens

### 4.0 Fixture (one for every wireframe and every `shoot.sh` run)

Illustrative values. The build uses the values that `tests/export_fixture.lua` produces, and that fixture is changed to match this story.

**Time and character**
- Now is **Fri 20 Nov 2026, 22:13**.
- Character "Hart", level 18 Orc Warrior, Horde, The Barrens. Rested 1,200 XP.
- XP 9,100 / 11,800 (77%). The rate over the last 30 minutes of active play is 3,860 XP per hour, so 2,700 / 3,860 h = **42m to level 19**.
- Played in all 1d 1h. Reached level 18 Thu 19 Nov at 23:12, so time at level 18 is 22m that night plus 38m today = 1h 0m so far.

**Live session**
- Started today 21:35 (38m so far).
- +2,450 XP. +26g 99s, which is +42g 61s per hour of play.
- 26 kills, 3 items. 0 deaths of mine. Durability lowest slot 38%. 8 free bag slots. 2 quests in the log are complete.

**Runs**

| Run | When | Facts |
|---|---|---|
| Ragefire Chasm | today 21:41 to 21:51, entered 21:39 | first run. First pull to last kill 10m 5s; inside 12m 30s. 2 of 4 bosses (Oggleflint, Taragaman the Hungerer killed; Jergosh the Invoker, Bazzalan missed). Tessa died. +1,840 XP. 15s coin. 3 items, best Cavedweller Bracers (green). Lockout 2 of 4, resets in 1h 59m. |
| Wailing Caverns | Mon 16 Nov 20:10 to 20:39, level 17, party of 5 | BEST on its 6-boss route. 28m 41s first pull to last kill, 31m 12s inside. 6 of 8 bosses. 0 deaths. +4,210 XP. 1g 2s coin. |
| Wailing Caverns | Sun 8 Nov 19:30 | same 6-boss route. 29m 23s. |

- Instances this hour: 1 (Ragefire Chasm at 21:39). Last 24 hours: 4. The player has set no limit. One copy row has `why = "estimate"`.

**Earlier sessions**
- Thu 19 Nov 22:04 to 23:34: 1h 30m, level 17 to 18.
- Thu 19 Nov 19:10: 52m.
- Mon 16 Nov 20:00: 1h 12m, the Wailing Caverns run.

**Fixture states**

Each state has a page key in `tests/render_shot.js`, and the `shoot.sh` page list uses these keys.

| Page key | State |
|---|---|
| `home/now` | normal |
| `home/now-empty` | zero sessions, first open with `welcomeDone = true` |
| `home/now-logoff` | combat log off |
| `home/now-max` | max level |
| `home/now-next` | durability 18%, 2 free bag slots, limit 5 with 0 left |
| `dungeons/runs` | normal |
| `dungeons/runs-empty` | no runs |
| `dungeons/runs-nomatch` | filter Shadowfang Keep |
| `dungeons/runs-limit4` | limit 5, 4 used |
| `dungeons/runs-limit5` | limit 5, 5 used |
| `dungeons/runs-live` | Ragefire Chasm in progress at boss 1 |
| `dungeons/bydungeon` | normal |
| `dungeons/run` | the Wailing Caverns BEST run |
| `dungeons/run-live` | the in-progress run |
| `dungeons/run-death` | the Ragefire Chasm run with Tessa's death |

Phase 2 keys are added with their screens.

### Wireframe scale

One character is 8 px and one line is 16 px. Each line is prefixed with its window y. Content wireframes show x 192 to 876 (85 characters). `[ ]` is a button, `[x v]` a filter button, `( | )` a segmented control, `====` the active tab underline, `>` a row chevron, `*` a coloured dot. Money is written as letters; on screen it is coin icons.

### 4.1 Home > Now (tonight)

**Sub-tab tooltip:** "How this session is going, and what needs you."

**It answers** Q1 to Q4: am I recorded (chip), how is this session going (cards), when do I ding (hero), what needs me (NEXT), and what happened worth a look. No click is needed for any of them.

**Layout at 900x580 (window y)**

| y | Element |
|---|---|
| 52 to 80 | control row: Now · Sessions · Activity · Fights · Deaths; no page controls |
| 92 to 196 | hero (h 104) |
| 208 to 232 | section header `THIS SESSION`, right META `fgSubtle` "since 21:35" |
| 232 to 312 | 4 stat cards, each `(684-36)/4 = 162` wide |
| 336 to 360 | section header `NEXT` |
| 360 onward | NEXT rows (ROW2, at most 3), or a 24 px all-clear line |
| +24 | section header `WORTH A LOOK`, right link "See all activity ›" |
| +24 | WORTH A LOOK rows (ROW2), at most 4 at COMPACT and 12 at WIDE, then a 24 px link row "+3 more ›" |

The page scrolls as one. With the combat-log notice, everything from the hero down moves 52 px lower.

```
     y +--------------------+-------------------------------------------------------------------------------------+
     0 | [#] everbuff                                                                       o Recording   [X] |
    40 |--------------------+-------------------------------------------------------------------------------------|
    48 | |[^] Home           |                                                                                     |
    52 | |                   |  Now   Sessions   Activity   Fights   Deaths                                        |
    78 |                    |  ===--------------------------------------------------------------------------------|
    84 |  [=] Dungeons      |                                                                                     |
    92 |                    | +-------------------------------------------------------------------------------+   |
   104 |                    | | [port]  Hart  Level 18 Orc Warrior · The Barrens                              |   |
   126 |                    | | [rait]  42m to level 19                                                       |   |
   160 |                    | |         XP 9,100 / 11,800 · 77% · rested 1,200          at 3,860 XP per hour  |   |
   178 |                    | |         [#######################################::::::::-----------]          |   |
   196 |                    | +-------------------------------------------------------------------------------+   |
   208 |                    |  THIS SESSION                                                       since 21:35     |
   232 |                    | +------------------+ +------------------+ +------------------+ +------------------+ |
   244 |                    | | PLAYED         > | | XP PER HOUR    > | | GOLD           > | | DEATHS         > | |
   261 |                    | | 38m              | | 3,860            | | +26g 99s         | | 0                | |
   290 |                    | | since 21:35      | | last 30m of play | | +42g 61s per hour| | 26 kills · 3 item| |
   312 |                    | +------------------+ +------------------+ +------------------+ +------------------+ |
   336 |                    |  NEXT                                                                               |
   360 |                    |  [anvil] * Repair soon: your lowest item is at 38%                                  |
   378 |                    |            The Barrens has repair vendors in Crossroads                             |
   408 |                    |  [note]  2 quests ready to turn in                                                  |
   426 |                    |          Wanted: Kolkar Leaders, Plainstrider Menace                                |
   480 |                    |  WORTH A LOOK                                                    See all activity > |
   528 |  [*] Settings      |  ...  (page scrolls)                                                                |
   564 +--------------------+-------------------------------------------------------------------------------------+
```

The DEATHS meta in the wireframe is cut only by the ASCII width. On screen "26 kills · 3 items" is about 96 px and fits the 138 px text width.

**Hero (image variant)**
- Image: `SetPortraitTexture(tex, "player")`, 56x56. Renderer shots show a grey square; the portrait is an in-game check.
- TITLE: the name in its class colour, then S2 and META `fgMuted` "Level 18 Orc Warrior · The Barrens".
- HERO: "42m to level 19". The colour is `fg`.
- META line 1: left "XP 9,100 / 11,800 · 77% · rested 1,200"; right-aligned "at 3,860 XP per hour".
- Bar:
  - fill `accent` to 77%;
  - rested overlay `accentTint` from 77% to `min(100%, (9,100 + 1,200) / 11,800)`;
  - no rested overlay when rested is 0, and then "· rested ..." is omitted from the label.
- Under 10 minutes of active play:
  - HERO reads "Level 18";
  - the META right side reads "Pace shows after 10 minutes of play";
  - the XP PER HOUR card reads "-" with the tooltip "Shows after 10 minutes of play".
- At max level: HERO "Level 60", META line 1 "Max level", no bar.
- Tooltip:
  - "Hart";
  - "At your XP per hour over the last 30 minutes of active play. It already includes the rested bonus you earned in that time.";
  - "Played in all 1d 1h";
  - "At this level 1h 0m";
  - "About 38 more Bristleback Quilboar kills", using the XP of your last kill. Omitted when there are no kills this session.

**Pace definition** (`ns.Pace`, one function for the hero, the XP PER HOUR card and the Leveling tooltip; tested)
- Active play: a minute counts when the player is not AFK (`UnitIsAFK("player")` false) and has an XP, kill or loot event within the last 5 minutes.
- Rate = XP gained in the last 30 active minutes, divided by those minutes, times 60. Under 30 active minutes, all active minutes this session are used.
- The rate shows after 10 active minutes.
- Remaining time = `(max - current) / rate`, rounded with `fmtDur` to the minute. Rested XP is shown, not modelled.
- Until session XP is stored (§5 step 3b), XP comes from live `UnitXP` deltas since session start. It never comes from `ses.xp`.
- Test: `remaining / shown rate` equals the shown estimate within 1 minute.

**Cards** (group header `THIS SESSION`)

| Label | Value | Meta | Click | Tooltip |
|---|---|---|---|---|
| PLAYED | "38m" | "since 21:35" | the live session page (tonight: Home > Sessions) | |
| XP PER HOUR | "3,860" | "last 30m of play" | Character (tonight: the Quests sub-tab; phase 2: Leveling) | "+2,450 XP this session" |
| GOLD | "+26g 99s" | "+42g 61s per hour" | Loot > Gold, period Session | "Balance 12,383g 78s 47c · all characters 12,393g 1s 81c" |
| DEATHS | "0" | "26 kills · 3 items" | Home > Deaths | "Lifetime: 104 kills · 2 deaths" |

The per-hour gold rate is `ns.Economy` session net divided by session hours (the same function Gold uses), so 26g 99s over 38m gives +42g 61s.

**NEXT** (things to do; at most 3, in this rank order)

| Rank | Row | Title | Meta | Link | Tooltip |
|---|---|---|---|---|---|
| 1 | Bags | `bad` dot, "Bags almost full: 2 free slots" | "Sell grey items at a vendor" | none | |
| 2 | Repair | dot (`warn` at 45% or below, `bad` at 20% or below), "Repair soon: your lowest item is at 38%" | "Any repair vendor fixes it" | none | the slot name and percent of each item at 45% or below |
| 3 | Instance limit (only with a limit set) | 1 left: `warn` dot, "1 instance left this hour". 0 left: `bad` dot, "No instances left this hour" | "Next free in 26m" | → Dungeons > Runs | |
| 4 | Quests ready | "2 quests ready to turn in" | the quest names, whole names plus "+N" | none | |

- Quests ready is the count of quest log entries whose `isComplete` (6th return of `GetQuestLogTitle(i)`) is 1, read on show. Add `GetQuestLogTitle` to `Deps.lua` as guarded and to `tests/api_restricted.lua`. If the call is absent, the row is never shown.
- "Next free in" is the oldest copy time in the hour plus 60 minutes, from `Runs.copies`.
- Rows with no link have no chevron and no hover.
- With nothing to do, the header is followed by a 24 px line in BODY `good`: "Nothing needs you. Go have fun."

**WORTH A LOOK** (what happened; the window is the live session; within a rank, newest first)

| Rank | Row | Title | Meta | Opens |
|---|---|---|---|---|
| 1 | Deaths (mine), at most 2 | "Died to Razormane Hunter" | "22:04 · The Barrens · in a 14s pull" | the death page (tonight: the death recap in Home > Deaths) |
| 2 | Dungeon runs, one per run, at most 2 | "Ragefire Chasm: first run, 2 of 4 bosses" | "21:41 · 10m 5s · Tessa died · +1,840 XP" | the run page |
| 3 | Level-ups | "Reached level 18" | "1h 12m at level 17 · 4m faster than level 16" | |
| 4 | Best drop (green and better only) | "Best drop: Cavedweller Bracers" (quality colour) | "From Ragefire Chasm · vendor price 1s 2c" | Loot > Items |
| 5 | Quests turned in, one row | "3 quests turned in" | "+1,950 XP · 1g 20s · last: Wanted: Kolkar Leaders" | Character |
| 6 | Lockouts (only when at least one save exists) | "Ragefire Chasm: 2 of 4 bosses down" | "Resets in 1h 59m" | see below |

- A third death adds a link row "3 more deaths ›" that opens Home > Deaths.
- A run that set a new best gets a BEST badge after its title, a 3 px `good` left bar on the row, and the title "Wailing Caverns: 42s faster than your best".
- Best drop picks the highest quality, then the highest vendor price (a missing price counts as 0). The meta omits "vendor price" when it is unknown.
- Lockout link: the › opens the run whose dungeon matches and whose time falls within the lockout's life. With no matching run there is no chevron, and the tooltip reads "Saved before everbuff.gg captured this dungeon on this character."
- Icons (`UI.KIND_ICON`, Blizzard icon paths; tested that every row kind has one; the paths are an in-game check):

  | Kind | Icon |
  |---|---|
  | death | `Interface\Icons\INV_Misc_Bone_HumanSkull_01` |
  | run | `Interface\Icons\INV_Misc_Map_01` |
  | level | `Interface\Icons\Spell_Holy_SurgeOfLight` |
  | loot | the item icon |
  | quest | `Interface\Icons\INV_Misc_Note_01` |
  | lockout | `Interface\Icons\INV_Misc_Key_04` |
  | repair | `Interface\Icons\Trade_BlackSmithing` |
  | bags | `Interface\Icons\INV_Misc_Bag_08` |
  | instance | `Interface\Icons\INV_Misc_PocketWatch_01` |

- Fallback: when the session has events but no row qualifies, show one neutral ROW2, "26 kills and 3 items so far" / "No deaths and no level yet. Keep going.", with no chevron.
- "See all activity ›" opens tonight's Home > Activity filtered to this session. In phase 2 it opens the live session page scrolled to its ACTIVITY section.

**Notice:** when the combat log is off, the strip reads "Combat log is off, so pulls, deaths and replays are not recorded." with [Turn on] (primary, since Now has no other primary), which runs the existing logging toggle, and the dismiss glyph.

**Empty states**
- No events yet this session: the WORTH A LOOK header is followed by "Nothing yet. Run a dungeon, ding, or loot something green and it shows here."
- First ever open: in phase 2 the first-run guide (§4.13) replaces Now. Tonight Now shows normally.

**At 1600x1000 tonight:** the main column is 1024 wide at x 192; the spare 360 px stays empty. Cards are `(1024-36)/4 = 247`. WORTH A LOOK shows up to 12 rows.

**Phase 2 rail (`RAIL_W` 336):**
- `THIS CHARACTER`: 2-up cards (`(336-12)/2 = 162` wide), PLAYED / BALANCE, KILLS / DEATHS;
- then `LAST RUN` as a ROW2 link (no primary).

### 4.2 Home > Sessions, the session page, and Activity (phase 2)

**Tooltip:** "Every play session: how long, what you earned, and how far you got."

**Summary line:** "Today: 38m · +2,450 XP · +26g 99s · your 3rd longest session this week". The last segment appears only when a week has 3 or more sessions.

**Control row right:** search input 176, placeholder "Search everything you did". Typing replaces the table with Activity results across all history:
- the summary line reads `34 events match "gnoll" · Back to sessions` (the second segment is a link);
- the results use the Activity columns plus a Session column (`fmtDate` 72).

**Columns at 900** (684 = 24 insets + 524 fixed + 8 gaps of 12 (96) + When 160)

| Column | Width | Content |
|---|---|---|
| When | flex (min 120, max 240) | clock under day rows, plus IN PROGRESS on the live row |
| Length | 56 | |
| XP | 64 | signed |
| Levels | 48 | "1" or "-" |
| Gold | 88 | signed, two units; tooltip adds "per hour of play" |
| Kills | 48 | |
| Deaths | 48 | |
| Runs | 40 | |
| › | 12 | |

**Hidden sessions:** sessions under 2 minutes with no XP, gold, kills or items are hidden unless `sessionsShowShort` is true. The footer row (24) reads "8 short sessions with nothing in them are hidden. Show them" (link; it toggles the key).

**Empty:** "Your first session is being recorded now. It shows up here with its XP, gold and runs."

**Session page** (`UI.Detail`)
- Back "‹ Sessions".
- TITLE "Today, 21:35 to now" with IN PROGRESS, or `fmtWhen` plus `fmtRange` for an ended session ("Thu 19 Nov, 22:04 to 23:34").
- META "38m · level 18 · The Barrens, Orgrimmar +1".
- Cards:

  | Label | Value | Meta |
  |---|---|---|
  | XP | "+2,450" | "3,860 per hour" |
  | GOLD | "+26g 99s" | "+42g 61s per hour" |
  | KILLS | "26" | "0 deaths" |
  | RUNS | "1" | "Ragefire Chasm" |

- Sections:
  1. `DUNGEON RUNS`: run rows that open the run page.
  2. `GOLD`, as a two-column mini table:
     - "Earned +30g 6s · top: Looted coin 18g 2s, Quest rewards 9g";
     - "Spent -3g 7s · top: Repairs 2g";
     - then the link "Open in Gold ›";
     - untraced money becomes the META line "While you were away (in): 3s 35c. Hover for details." It is never red;
     - "Recorded before addon 0.9.40" becomes "Gold details start from 15 Nov.";
     - "Strangers" becomes "Players you traded with".
  3. `ACTIVITY`: the old Timeline for this session.
     - Section header right: filter button "Everything ▾".
     - Columns at 900 (24 + 264 + 4 gaps of 12 (48) + Event 348):

       | Column | Width |
       |---|---|
       | Time | 40 |
       | Type | 72 |
       | Event | flex |
       | Place | 140 |
       | › | 12 |
       | Coords | 72, WIDE only |

     - Kill rows open the fight page.
     - Event copy has amounts: "Sold 3 items for 45s", "Mail: 1 item, 2g taken", "Quest done: Wanted: Kolkar Leaders (+450 XP, 1g)".
     - The WHILE FIGHTING column is cut.

**Activity groups** (every kind on `origin/main` in exactly one group; tested; a future kind without a group fails the test)

| Group | Kinds |
|---|---|
| Everything | all |
| Quests and levels | QUESTACCEPT, QUESTDONE, REWARD, LEVELUP, REP, ACHIEV, SPELL |
| Fights | KILL, BOSS, WIPE, DEATH, ALIVE, ROSTERJOIN, ROSTERLEAVE |
| Travel | ZONE, FIRSTZONE, DISCOVERY, FLIGHT, FLIGHTTRIP, DUNGEON, DUNGEONLEAVE |
| Loot and gear | LOOT, COLLECT, UPGRADE, BROKEN, GOLDAWAY |
| Town visits | VENDOR, TRAINER, MAIL, AUCTION, TRADE |
| Professions | SKILLUP, RECIPE, PROFTIER |

Type labels are sentence case words per kind (Quest, Kill, Level, Loot, Merchant, Trainer, Mail, Auction, Trade, and so on), listed in one `UI.KIND_LABEL` table.

**Rail at WIDE:**
- `GOLD PER SESSION`: the kept chart, one bar per session; today in `accent`, the others `data-single`; the value on hover; day labels under the bars.
- `THIS WEEK`: 2-up cards PLAYED / XP and GOLD / RUNS.

### 4.3 Home > Fights, and the fight page (tonight: registration only; restyle in phase 2)

> Revised by `docs/UX_PRAGMATIC.md` 1.4 (built on the draft branch): the sub-tab exists only while the character has
> pulls stored. The addon removes a pull once the desktop app has saved it, so the list is the stretch since the
> last pickup and never the character's history. The section header reads "PULLS SINCE <oldest stored pull>", the
> line under it counts only what is listed ("58 pulls · 0 wipes · 2 deaths · 22m in combat"), the filter reads
> "All pulls · Bosses, wipes and deaths · Kills · Wipes · Deaths", and an empty filter is scoped ("No wipe among the
> stored pulls."). The copy below that differs from this is superseded.

**Tooltip:** "Every pull: bosses, wipes and deaths first, with a replay of each."

**Segmented control:** `Important · All`, default from `fightsView`. Important means bosses, elites, wipes and any death.

**Summary line:**
- Important: "2 important of 78 pulls this session · 0 wipes · 18m 3s in combat · Show all" (the last segment is a link to All);
- All: "78 pulls this session · 0 wipes · 18m 3s in combat".

**Collapse:** in All only, consecutive trash kills in one zone fold into "12 pulls: Bristleback Quilboar x7, Razormane Scout x5"; a click expands them.

**Columns at 900** (24 + 332 + 5 gaps (60) + Enemy 268)

| Column | Width | Content |
|---|---|---|
| When | 40 | |
| Enemy | flex (max 360) | the name plus a BOSS or ELITE badge |
| Place | 160 | |
| Length | 56 | |
| Result | 64 | glyph plus word: Kill `fg`, Wipe `warn`, Died `bad` |
| › | 12 | |
| Coords | 72, WIDE only | |

**Empty:**
- Important: "No bosses, wipes or deaths yet. Every pull is under All." plus the link "Show all pulls".
- All: "Fight anything and the pull shows up here, with a replay you can scrub."

**Fight page:**
- Back "‹ Fights"; TITLE the enemy plus a WIPE or DIED badge; META "Today 22:04 · The Barrens 55.8, 64.7 · 14s".
- **What the addon can read.** Per `Fights.lua`, damage and DPS are not readable in game; they come from the combat-log file. So there are no damage or healing cards. Cards:

  | Label | Value | Meta |
  |---|---|---|
  | LENGTH | "14s" | |
  | RESULT | "Kill" | |
  | ENEMIES | "3" | "Razormane Hunter +2" |
  | PARTY | "Solo" or "5" | |

- Sections: `REPLAY` (the existing scrubber), `TIMELINE`, `AURAS`, `GEAR AND STATS`.
- Footer META: "Damage and healing for this pull are on everbuff.gg once the desktop app saves your combat log."

### 4.4 Home > Deaths, and the death page (tonight: registration only)

> Revised by `docs/UX_PRAGMATIC.md` 1.5 (built on the draft branch): the sub-tab exists only while a stored death of
> the character names its killer. Columns When, Level, Killed by, Place, Coords, Downtime; no gear column. A killer
> the game hid is a blank cell. The line over the list reads "Deaths since <oldest stored event>", with "most in
> <place>" only from 3 deaths in 2 places. The copy below that differs from this is superseded.

**Tooltip:** "Every death: what killed you, and the moments before it."

**Segmented control:** `Mine · Everyone`. Default Mine. Everyone adds party members' deaths in your dungeon runs.

**Columns at 900** (24 + 308 + 4 gaps (48) + Killed by 304; in Mine the Who column and its gap are dropped and Killed by takes the space)

| Column | Width | Content |
|---|---|---|
| When | 40 | |
| Who | 96, Everyone only | class colour |
| Killed by | flex (max 360) | |
| Where | 160 | |
| › | 12 | tooltip "Opens the death, from your Ragefire Chasm run" |

The IN column is cut.

**Empty:**
- Mine empty, Everyone has rows: inline "You have not died. 1 party member died in your runs." plus the link "Show everyone".
- Mine and Everyone both empty: big empty state, title "No deaths yet", sentence "When you die, this page shows what killed you and the pull to replay."
- Everyone empty: inline "Nobody in your dungeon runs has died yet."

**Death page:**
- Back "‹ Deaths"; TITLE "Died to Razormane Hunter" plus DIED; META "Today 22:04 · The Barrens 52.1, 47.9 · level 18".
- Cards:

  | Label | Value |
  |---|---|
  | KILLED BY | the name |
  | PULL LENGTH | |
  | ENEMIES | |
  | IN | the run name or "Open world" |

- Sections: `THE LAST MOMENTS` (the existing slain-by recap and the aura timeline of the linked pull, with no damage amounts), then the links "Open the pull ›" and "Open the run ›".

### 4.5 Dungeons > Runs (tonight)

> Revised by `docs/UX_PRAGMATIC.md` 2.1 (built on the draft branch). The hero's answer is the result ("7 bosses in
> 1h 9m"; a comparison leads only when there is a best to compare with), its META the day and the bosses missed, then
> the deaths and the best drop. The line with the instances this hour and the lockouts shows only with something to
> say. One table: When, Dungeon, Time, Vs best, Bosses, Deaths, Worth, Best drop (WIDE). Worth is the looted coin
> plus the vendor value of the items, never quest coin. A boss total ("2/4") only from the dungeon's learned list or a
> lockout; otherwise the kills alone. "first run" is not said. The runs from before the run store are rows of the
> same table, marked "partial" (time and worth only, `characters[guid].dungeonLegacy`), and a column is left out while
> fewer than a third of the listed rows have a value for it. Day rows and the section carry no run count. No cell is
> a "-". Empty: "No run stored yet". The wireframes below that differ from this are superseded.

**Tooltip:** "Your dungeon runs against your best: time, bosses, deaths, loot and XP."

**Layout at 900x580 (window y)**

| y | Element |
|---|---|
| 52 to 80 | Runs · By dungeon; right: filter "All dungeons ▾" |
| 92 to 116 | summary line |
| 128 to 232 | Last run hero (h 104) |
| 256 to 280 | section header `ALL RUNS`, right META "3 runs" |
| 280 to 304 | table header |
| 304 onward | day row, then rows at 32; the first run row at 328; 7 whole rows are visible above 564 |

The page scrolls as one.

```
    52 |  Runs   By dungeon                                                [All dungeons      v] |
    78 |  ====--------------------------------------------------------------------------------- |
    92 |  1 instance this hour · Ragefire Chasm: 2 of 4 bosses down, resets in 1h 59m          |
   128 | +-----------------------------------------------------------------------------------+ |
   140 | |  LAST RUN  Ragefire Chasm                                                         | |
   162 | |  2 bosses in 10m 5s                                                  [ Open run ] | |
   196 | |  Today 21:41 · first run · missed Jergosh the Invoker, Bazzalan                    | |
   214 | |  Best drop: [ic] Cavedweller Bracers · 3 items · Tessa died                        | |
   232 | +-----------------------------------------------------------------------------------+ |
   256 |  ALL RUNS                                                                    3 runs  |
   280 |  WHEN DUNGEON              TIME   VS BEST        BOSSES DEATHS    XP  LOOT           |
   304 |  TODAY · 1 RUN                                                                       |
   328 |  21:41 Ragefire Chasm     12m 30s first run         2/4      1 1,840 [ic] 3 items  > |
   360 |  MONDAY 16 NOV · 1 RUN                                                               |
   384 |  20:10 Wailing Caverns    31m 12s 42s faster [BEST] 6/8      0 4,210 [ic] 5 items  > |
```

The BEST badge belongs in the first column only. The wireframe's placement is indicative, and the badge sits after the dungeon name.

**Filter button:** "All dungeons ▾".
- The menu lists dungeons with runs, in alphabetical order, then "Raids · coming soon" (greyed).
- With a dungeon picked it reads "Wailing Caverns" in the active style with the clear glyph.

**Summary line segments**

1. **Instances.** No limit set: "1 instance this hour". No "(about)" on the line: a copy counted by estimate is said in the tooltip, and the line's count is the same one the run rows and the live hero show. With a limit:

   | Used | Copy | Colour |
   |---|---|---|
   | fewer than limit-1 | "4 of 5 instances left this hour" | count `fg` |
   | limit-1 | "1 instance left this hour, next free in 26m" | `warn` dot |
   | limit | "No instances left this hour, next free in 26m" | `bad` dot |

   Tooltip: line 2 "Counted from your characters' dungeon entries this hour. A new copy within 20 minutes of the last is a guess.", then the `Runs.hourTip` rows, then "Last 24 hours: 4". Without a limit it adds "Set your own limit with /eb instances limit 5 (or 10)." The code fact behind this: the limit is the player's own (`Runs.limit()`), unset by default, so "of 5" never shows unless the player set it.

2. **Lockouts.** One lockout: "Ragefire Chasm: 2 of 4 bosses down, resets in 1h 59m". It is a link to the matching run, or plain text with the "Saved before everbuff.gg captured..." tooltip. Several lockouts: "2 lockouts, next reset in 1h 59m". None: "No lockouts". The tooltip lists every lockout plus the other characters' lockouts (existing `otherLockouts`).

**Last run hero (text variant, no image)**
- TITLE: LABEL "LAST RUN", then TITLE dungeon name, then badges (BEST, IN PROGRESS). A first run has no badge: META says "first run".
- HERO, the verdict that the row cannot hold:
  - a first run: "2 bosses in 10m 5s" (`fg`), or "No boss killed in 10m 5s"; its META line 1 is "Today 21:41 · first run · missed Jergosh the Invoker, Bazzalan" (or "· full clear"), so the time is never said twice;
  - "42s faster than your best" (`good`);
  - "1m 20s slower than your best" (`warn` with dot);
  - "Same as your best";
  - "No best for these bosses yet" (`fg`). This shows when the run's route has no other run, but the dungeon has runs.
- META line 1: "Today 21:41 · 10m 5s · 2 of 4 bosses, missed Jergosh the Invoker, Bazzalan". A full clear reads "4 of 4 bosses, full clear". Missed names are whole names plus "+N".
- META line 2: "Best drop: " plus a 12 px item icon, the name in its quality colour, then "· 3 items" and "· Tessa died" (or "· nobody died"). Without loot: "Nothing looted · nobody died".
- Primary button [Open run] for a finished run. A run in progress shows no button:
  - TITLE "Ragefire Chasm" plus IN PROGRESS;
  - HERO "21s faster than your best at boss 1" (compared with the best run of the same route's split at that boss index; omitted when no route shares this start, and the HERO then reads "12m 40s so far");
  - META 1 "12m 40s so far · 1 of 4 bosses";
  - TIME and the HERO refresh every second.
- Hero click (outside the button) does nothing. The button is the one primary on the view.

**Columns at 900** (24 insets + 388 fixed + 8 gaps of 12 (96) = 508; Dungeon = 684 - 508 = **176**)

| Column | Width | Content |
|---|---|---|
| When | 40 | clock under day rows |
| Dungeon | flex (min 140, max 360) | name plus KEPT, IN PROGRESS or BEST badge |
| Time | 56 | the run's clock inside (`fmtDur`); header tooltip "Time inside the dungeon, entrance to exit" |
| Vs best | 88 | `fmtDelta` on first pull to last kill, against the best of the same route; header tooltip "Against your fastest run with the same bosses, first pull to last kill" |
| Bosses | 40 | "2/4", always with the total |
| Deaths | 48 | the party's deaths; cell tooltip names them |
| XP | 56 | tooltip "1,840 XP · 11,040 XP per hour" |
| Loot | 72 | best drop icon 20, S1, then "3 items" (every item of the run, the same count as the run page's LOOT card and section); "-" when nothing; tooltip lists every item plus "Coin looted 15s" |
| › | 12 | |

**WIDE columns** (`wide = true`; at 1024: 24 + 524 fixed + 10 gaps (120) = 668, Dungeon 356): Coin looted 72 and XP per hour 64, inserted before Loot.

**Sort:** newest first by default. Clicking a header sorts, as today, and the sorted header shows `UI.Glyph("chevronDown")` or its flipped form.

**BEST definition** (from `Runs.lua`): a best is kept per route key (`Runs.routeOf`: the sorted killed encounter ids, plus difficulty and solo) on the measure first pull to last kill.
- A run is BEST when it holds its route's best.
- A later run that kills more bosses is on a different route. It gets its own best and is never compared with the shorter route.
- "first run" means no earlier run of that dungeon by this character.

**Empty:**
- No runs: big empty state under the summary line. Gate icon; title "No dungeon runs yet"; sentence "Enter any dungeon and your run is recorded: time, bosses, deaths, loot and XP, against your best." No buttons.
- No match: inline "No run of Shadowfang Keep yet." plus the link "Show all dungeons".

### 4.6 Dungeons > Run page (tonight)

> Revised by `docs/UX_PRAGMATIC.md` 2.2 (built on the draft branch). META: the day and clock span, the level, "party
> of N" only from a stored pull's group, "solo" only from a stored size of 1, the comparison when there is one. Cards,
> each only with a value: TIME (meta "7m 59s dead or outside"), BOSSES (meta "boss clock 1h 3m"), XP (per hour of
> time inside), WORTH ("1g 16s coin · 18g 3s items at vendor prices"; quest coin only in the hover). Bosses table:
> Boss, Killed at, Split, Fight length; boss 1's split is its kill clock (the run's clock, which stands still outside: UX_PRAGMATIC.md 2.2), the others since the kill before, and kill
> clocks keep their seconds past the hour. The deaths are one line under the table ("Deaths: 16:12 (2m 45s down) ·
> 16:30 (1m 14s down)") unless a row names a killer or a party member. Loot: green and better as rows (Item, From,
> When), then "29 more: 21 white, 8 grey"; From names the boss of the run killed at most 90 s before a row whose
> stored source is a placeholder, "Trash" for an enemy placeholder with none, blank otherwise, and the hover says how
> it was derived. A section with nothing in it is not on the page. A partial row's page is its Time and its Worth.
> The wireframes below that differ from this are superseded.

The page uses `UI.Detail(host, items, index, render)` with the Runs list's current order.

```
    52 |[< Runs]                                                         [< Older] [Newer >] |
    92 |  Wailing Caverns  [BEST]                                                            |
   114 |  Mon 16 Nov, 20:10 to 20:39 · level 17 · party of 5                                 |
   140 | +-------------------+ +-------------------+ +-------------------+ +-------------------+ |
   152 | | TIME              | | VS YOUR BEST      | | BOSSES            | | DEATHS            | |
   169 | | 31m 12s           | | 42s faster        | | 6 / 8             | | 0                 | |
   198 | | inside            | | 28m 41s first pull| | missed 2          | | clean run         | |
   220 | +-------------------+ +-------------------+ +-------------------+ +-------------------+ |
   244 |  BOSSES                                                                    6 of 8   |
   268 |  #  BOSS                 KILLED AT  SINCE LAST BOSS  VS BEST     FIGHT LENGTH        |
   292 |  1  Lady Anacondra          4m 2s           4m 2s    12s faster          48s       > |
   324 |  2  Lord Cobrahn           9m 40s          5m 38s  * 20s slower        1m 5s       > |
```

**Cards at 900** (4, each 162)

| Label | Value | Meta |
|---|---|---|
| TIME | the inside clock | "inside" |
| VS YOUR BEST | `fmtDelta` | "28m 41s first pull to last kill" |
| BOSSES | "6 / 8" | "full clear" or "missed 2" |
| DEATHS | | "clean run", or the names ("Tessa, you") |

At WIDE (tonight too, since it only adds cards): 6 cards, adding XP ("4,210" / "8,800 per hour") and LOOT ("1g 2s" / "4 items").

**Sections at 900, in order** (each is an existing `heading(...)` block, restyled with the kit; an empty section shows its sentence in 24 px and is never hidden)

1. `BOSSES` (section right "6 of 8")
   - Columns (24 + 380 fixed + 6 gaps (72) + Boss 208):

     | Column | Width |
     |---|---|
     | # | 24 |
     | Boss | flex |
     | Killed at | 64 |
     | Since last boss | 104 |
     | Vs best | 88 |
     | Fight length | 88 |
     | › | 12 |

   - A boss row opens that boss's fight page. A boss not killed shows "-" in `fgMuted` and has no chevron.
2. `LOOT`
   - Item rows (ROW): icon 20, quality-coloured name, "x2" muted, from, vendor price.
   - Then the META line "Coin looted 1g 2s · vendor price of items 3s".
   - Empty: "Nothing looted."
3. `DEATHS`
   - Rows: time into the run, who (class colour), killed by, ›.
   - Empty: "Nobody died. Clean run."
4. `XP`: "4,210 XP: 3,100 from kills, 1,110 from quests". At max level: "Max level: no XP to earn."
5. `PARTY`: names in class colour, level, role.
6. `PACE` (from `paceLines`)
   - "Your best for these 6 bosses: 28m 41s on 16 Nov, first pull to last kill. This run is your best." No colour; the BEST badge already says it.
   - "If you matched your best on every boss: 27m 50s".
   - Shown only when the existing `paceLines` returns lines; else "Kill the same bosses twice to see your pace."
7. `ENTERED AND LEFT`: entries and exits with times, explaining a split run.
8. `ALL PULLS IN THIS RUN`: stored pulls, ›.

**Copy:** the TIME card tooltip reads "Time inside the dungeon. Your clocks: entered 20:08, first pull 20:10, last kill 20:39, left 20:41." The VS YOUR BEST tooltip names the route: "Against your fastest run that killed these 6 bosses: Lady Anacondra, Lord Cobrahn, +4."

### 4.7 Dungeons > By dungeon (tonight)

> Revised by `docs/UX_PRAGMATIC.md` 2.3 (built on the draft branch): the sub-tab exists only once two dungeons have
> two stored runs each. Columns Dungeon, Runs, Best, Average (from two runs), Deaths per run, Worth per run. No
> summary line, no per hour rates, no level, no full clears. The copy below that differs from this is superseded.

**Tooltip:** "Which dungeon is worth your time: your best, your average, and what each pays."

**Summary line:**
- below max level: "Best XP per hour: Ragefire Chasm, 11,040";
- at max level: "Best gold per hour: Wailing Caverns, +1g 30s";
- then the instance and lockout segments as on Runs.

**Default sort:** XP/h below max level, Gold/h at max level, descending. The sorted header has the glyph.

**Columns at 900** (24 + 412 fixed + 8 gaps (96) = 532; Dungeon **152**)

| Column | Width | Content |
|---|---|---|
| Dungeon | flex (min 140, max 360) | |
| Runs | 40 | |
| Best | 56 | |
| Average | 56 | |
| XP/h | 64 | |
| Gold/h | 72 | |
| Deaths/run | 64 | |
| Level | 48 | your level on your last run |
| › | 12 | |

- WIDE adds Full clears 64 and Last 72 (`fmtDate`).
- Header tooltip on Best and Average: "First pull to last kill, on the route of your best."
- A click opens Runs filtered to that dungeon.

**Empty:** "Run a dungeon and its best, average and pay show here." With one run, the row shows and Average equals Best.

### 4.8 Loot > Items (phase 2; content from `docs/UX_PRAGMATIC.md` 4.1)

**Tooltip:** "What dropped, from whom and where."

**Control row right:** segmented `List · By item` (from `itemsMode`), quality filter, search 176.

**Quality filter:** "Green and better ▾" by default (from `itemsQuality`). Menu: Everything, White and better, Green and better, Blue and better, Purple and better. Item names are in their quality colours. Settings uses the same labels.

**No summary line.** The section header opens the page: label "ITEMS SINCE TUE 17 NOV" (the oldest item row the save still holds for the character, at any quality), meta at the right "89 green or better" (the looted rows the filter shows, the same count in both modes; "N items" at Everything or while a search narrows the list).

**Columns**

| Column | Width | Content |
|---|---|---|
| When | 40 | |
| Item | flex | icon 20, quality name, muted "x2", the QUEST badge |
| From | 160 (max 240) | a named source as stored; "Quest: <name>" ("Quest" when the turn-in is no longer stored); "Container" (stored loot GUID starts with `Item-`); blank for the stored words `Creature` and `an enemy` and for a name that is only a kill by timing, hover "From: Name not recorded"; blank for `Picked up` and `Unknown source`, hover "From: Not recorded"; blank for a source that repeats the item's name |
| Place | 120 | the zone stamped with the row. Blank, hover "Place: Not recorded", for a row that came with no loot window before the capture of 0.9.52 (`Picked up`, `an enemy`, `Quest reward` without `pushed`): its stored place is the last loot window's and can be another zone |
| Coords | 72, WIDE only | blank whenever Place is |

- From and Place show only while a third of the listed rows have a value; Place is also left out when it is the same on every row (rule 0.3 of the pragmatic pass). The hover keeps what a hidden column held.
- Not listed: coin (Loot > Gold), auction and mail rows (`Auction won`, `Auction returned`, `Mail from ...`: purchases and deliveries, Gold > Auction house owns them).
- No Value, Vendor price, Times, First seen or Qty column. No stored placeholder word and no "-" in any cell.
- Rows open nothing; the item tooltip shows on hover; shift-click links the item in chat.
- By item columns: Item flex · Count 56 · Last looted 96.
- Day rows are the day only ("YESTERDAY"), no count.

**Empty:** "No item stored yet." A filter with no row: "No item matches this filter." A search with no row: `No item matches "saber". ` plus "Clear search".

### 4.9 Loot > Gold (phase 2; content from `docs/UX_PRAGMATIC.md` 4.2)

**Tooltip:** "Where your gold came from and where it went, traced to every copper."

**Control row right:** period segmented `Session · Today · Week · All` (from `goldPeriod`). No overflow. A session or a day opened from another page (the Sessions gold band) lights no segment and is named in the section header ("SESSION OF FRI 20 NOV 15:08").

**No summary line above the cards and no note under them.**

**Cards** (4 at every width)

| Label | Value | Meta |
|---|---|---|
| BALANCE | "12s 19c" | "all characters 12g 0s"; "records do not add up" when the audit of the period finds a break (the hover names it) |
| EARNED | "+8g 47s" | "13g 41s not traced" when gold came in with no source seen, else "mostly auction sales" |
| SPENT | "-30g 99s" | "50g 36s not traced" when gold went out with no source seen, else "mostly auction house" |
| NET | "-22g 51s" | "-3g 42s per hour" only when the period holds 30 minutes of play (`Gold.RATE_MIN_S`); never for all time |

- Values are `fg`, never dimmed. No entry counts.
- The hovers hold the detail: the full balance and the audit on BALANCE, the untraced amount with its sentence on EARNED and SPENT, the gold a crash left unattributed and what changed while the addon was not running on NET.
- Money shows two neighbouring units: 12g 0s 78c reads "12g 0s", never "12g 78c"; a flat 12g reads "12g".

**List:**
- Section header label = the period: "THIS SESSION", "TODAY", "WEEK", "ALL TIME". When the gold history (`goldSince`) starts inside the period the real range takes its place: "SINCE WED 18 NOV 20:35".
- Right side: the view segmented `Sources · Auction house · Journal`, and on Journal the search 176 before it.
- The header's one remark follows the label: "newest 500 of 767", "entries since Wed 18 Nov" and "rows since Sat 7 Nov" (all time: where the kept rows start), "not every entry is kept".
- Until the coin capture of 0.9.52 (gate H) group coin in dungeons could be booked as mail or with no source. A period that holds time inside a dungeon from before the character's first load with it (`goldShareSince`) does not offer Sources: the page opens on Journal, the Sources segment is greyed and its hover says "Sources are not reliable for dungeon time before <date>."

**Sources view:**
- Group rows are words only: "EARNED", "SPENT", and "NOT EARNED OR SPENT" for what changed while the addon was not running ("While you were away") and gold moved between the player's own characters and the bank.
- Columns: Source flex · Mostly from (the largest group of the source and, in a cell of its own, its amount; for Auction house the item with its units, "Black Lotus x3"; blank when the journal rows kept do not add up to the source's amount) · Amount 88 · ›.
- Gold that moved with no source seen reads "Source not seen" (in) and "Spending not explained" (out) in `fgSubtle`, with the tooltip "Gold that moved while you played and the addon saw no source for it." Only `away` is "While you were away".
- A source row opens a detail page of its Journal entries: Back "‹ Sources", TITLE "Looted coin", META "This session · 31 times · +18g 2s".

**Journal view:**
- Columns When, Source, Detail, Place, Coords (WIDE), Amount, Balance (WIDE). A missing place is blank (hover "Place: Not recorded").
- Auction rows name their item when the purchase or posting is stored: "Bought Black Lotus x3", "Deposit: Iron Bar x17". A purchase is found by its exact price within 5 s; a deposit only when one posting and one deposit are that near (postings a few seconds apart keep "Deposit").
- Day rows are calendar days. On a day period or all time they carry the day's net from the gold day row of that date, "YESTERDAY · -114g 54s", only when that row counts exactly the calendar day (no kept entry and no stored session between midnight and the daily reset on either end). A day the history starts in says from when, "WEDNESDAY 18 NOV, FROM 20:35", when no listed entry of the day is older.

**Auction house view:**
- Answer line under the section header, three segments: "Spent 30g 98s · Received 5g 97s · Net -25g 0s". Spent is `ledger.auctions`, Received `ledger.auctionSales`, Net the difference; the hover has sold, house cut and deposits returned when the kept sale rows add up to Received.
- Columns When · Item (icon, name, "x3") · Result · Price. One auction is one row: a posting with a stored outcome is its Sold, Expired or Cancelled row; "Posted" only while its time has not run out (the duration is in the hover). Player (the buyer of a sale, the seller of a purchase) only while a third of the rows name one.
- One purchase is one row: a delivery mail is taken up by the priced row of the same item id bought at most an hour before it with that many units still to come. A delivery with no purchase reads "Won" with a blank Price.
- A sale's Price is what the buyer paid (the invoice's bid), its count the posting's (same item, buyout equal to the bid).
- A purchase with no item of its own (or one named by the old "newest row without a name" rule) takes the item of the auction mail of its session whose invoice names exactly its price; with none it is not listed. No row has a blank Item.

**Empty:** "No gold has moved in this period." Auction house: "No auction in this period."

**Cut by the pragmatic pass:** the Days, Characters, Zones and Runs views with their charts, the "More" and "Break down by" dropdowns, the scope filter, the review button, the PER HOUR card, the Times, Share, Buyer and Duration columns, the untraced line. The stored data behind Zones and Runs (`goldZones`, `goldRuns`) is still written; Dungeons reads the runs.

### 4.10 Character > Leveling (phase 2; Quests folded in)

Content as `docs/UX_PRAGMATIC.md` 3.1 has it (the pragmatic pass replaced the pace comparison, the four cards and the time columns of this section: the stored played stamps were overwritten at every login).

**Tooltip:** "Your level, when you reached each one, and the time played."

**Hero:**
- TITLE: the character's full name.
- At the level cap: HERO "Level 60"; META 1 "Reached Fri 20 Nov 22:49 in Mount Hyjal" (left out unless the exact moment is stored); META 2 "6d 20h played, 1h 15m at 60". No bar, no cards, no Quests table.
- Leveling: HERO "42m to level 19" (before 10 active minutes: "Level 18"); META 1 "XP 9,100 / 11,800 · 77% · rested 1,200", right "at 12,400 XP per hour"; the bar with the rested overlay, as on Now.

**Cards (leveling only, each once /played has answered):**

| Label | Value | Meta |
|---|---|---|
| PLAYED | "4h 17m" | "on this character" |
| TIME AT LEVEL 18 | "30m" | "so far" |

**`LEVELS` table**

| Column | Width | Content |
|---|---|---|
| Level | 48, right | "53", or "30 to 37" for levels that share one bound |
| Reached | 136 | exact: "Fri 20 Nov, 22:49". A level known only between two stored moments: "Tue 17 Nov" (hover "Between 17:02 and 20:06"), or "18 to 19 Nov" over days |
| Zone | flex | only on an exact row |

- A level with nothing stored has no row. One muted line under the table counts them: "12 levels have no recorded date."
- No Time at level, Played by then or Vs previous column.

**`QUESTS SINCE <day>` table** (leveling only; the header names the day of the oldest stored quest, no count)

| Column | Width |
|---|---|
| When | 40 |
| Quest | flex |
| Place | 140 |
| Gold | 72 |
| Coords | 72, WIDE only |

- An uncached title reads "Quest 1234" in `fgMuted`, with the tooltip "The game did not give the quest name when you turned it in."
- A quest with no gold recorded has a blank Gold cell.

**Empty:** a table with no rows is left out; no sentence takes its place.

### 4.11 Character > Reputation and Professions (phase 2)

Content as `docs/UX_PRAGMATIC.md` 3.2 and 3.3 have it.

**Reputation**
- Tooltip: "Your standing with every faction, what is left to the next one, and the last day it gained."
- Answer line: "**Barkskin Burrow +1,005** yesterday" (the first row of the list; "on Thu 19 Nov" for an older day). Left out when no row shows a gain.
- Section header "FACTIONS", right "19 factions".
- Columns:

  | Column | Width | Content |
  |---|---|---|
  | Faction | flex | `fgMuted` for a Neutral faction with no stored gain |
  | Standing | 88 | `fgSubtle`; Hated and Hostile in `bad` with the dot |
  | Progress | bar + S2 + the widest text shown | bar 120x6 and what is left: "16,072 to Exalted"; "Exalted" with a full bar at the top; "Not known yet" (`fgMuted`) and no track for a faction the client does not answer for. The column is left out while the client answers for no faction. In a window too narrow for the longest faction name the bar shrinks (40 px at least) and is then left out. |
  | Last day gained | 96, right | "+1,005 · Yesterday": the sum of what the faction gained on the day of its newest stored gain, and that day. Blank only with no stored gain (hover "Last day gained: Not recorded"). "at least +200 · Yesterday" when a stored gain that names no character lies on that day; "Not certain" (`fgMuted`) when one lies on a later day. Left out when no faction shows one. |
  | This session | 88 | "+75"; a column only while a faction gained this session |
  | › | 12 | only on a faction with stored gains |

- Order: factions with a shown gain first, by the day of the last gain (newest first), then by that day's gain (largest first); then the rest by standing; a Neutral faction with no stored gain last.
- Only a faction with stored gains opens. Its page: the name, "Revered · 16,072 to Exalted", section "GAINS SINCE <day>" with the sum on the right ("GAINS" alone, no sum, when a stored gain of the faction that names no character lies on the first listed day or later), table When · Source · Amount. A gain with no stored source has a blank Source cell (hover "Source: Not recorded"); Source is a column only while a third of the rows name one.
- Empty (inline): "No faction met yet."

**Professions**
- Tooltip: "Your skills and what you crafted."
- No headline above the rows.
- Profession rows (ROW2):
  - icon 24; title "Tailoring"; meta "Journeyman" (no recipe count: the stored recipe rows rarely name their profession);
  - bar 160x6 at x 320; "118 / 150" right-aligned at `w-12`;
  - training line (META `fgSubtle`, no accent; rank thresholds Journeyman 50, Expert 125, Artisan 200):
    - from 10 below the next rank's threshold up to the threshold: "Expert training opens at 125";
    - at or past the threshold while the rank is untrained: "Expert training is open at any Tailoring trainer".
  - Learned primary and secondary professions are listed. The list is the game's skill lines plus any crafted or learned recipe's profession; one the game has not listed yet reads "Not known yet" (`fgMuted`) where the number stands and has no bar.
- `CRAFTED SINCE <day>` table, right "1,012 items" (the header names the first day the list holds whole: the oldest day of a list at its cap is cut and left out):

  | Column | Width | Content |
  |---|---|---|
  | When | 40 | "23:50", or "23:46 to 23:48" for a batch |
  | Item | flex | quality colour, no brackets, "x49" after the name when more than one |
  | Profession | 104 | the profession a stored row of the craft's spell names; a craft whose spell has none is not listed |

  One row per batch: crafts that follow each other with the same spell and session, each at most 60 s after the one before. Day rows count items: "YESTERDAY · 111 ITEMS".
- Cut: the headline, the recipe count on a row, the `RECIPES LEARNED` table, the Qty column, "Other", "+12 this session".
- Empty:
  - Professions: "No profession learned yet."
  - Crafted: the section is left out.

### 4.12 Settings (phase 2)

**Layout.**
- One settings column, `min(CW, 684)` wide (the whole content width at 900), box at x 192.
- Labels at 204. Controls are right-aligned to the column's text edge, `TEXT_R` (864) at 900, like every other page. A text input stretches so its button ends on that edge.
- At WIDE: two columns of 500, S5 apart (1024 total).

**Setting row:**
- h 32, or 48 with a description;
- ROW_TITLE label at x 12, vertically centred (y 8 when described);
- META description at y 28, wrapping at `min(w - 24, 520)` (the Table inline-text rule);
- the control right-aligned.

**Checkbox:**
- 16x16, 1 px `lineControl` edge;
- checked: `accent` fill with `UI.Glyph("check")` in `on-accent`.

**Slider:**
- track 200x4 `sunken` with an `accent` fill;
- thumb 12x12 `fg`;
- value BODY_STRONG 40 wide, right of the track.

These controls are built from WHITE8x8 and text only, so the renderer shows them.

**General** (tooltip "How the window and on-screen notifications behave")
- `CAPTURE FLAG`
  - Description: "The small square the desktop app reads to line up your video. It is always shown."
  - Position: segmented "Top left | Top right | Bottom left | Bottom right" (4 x 100 = 400).
  - Size: slider.
- `WINDOW`
  - "Window scale": slider, 90% to the current maximum.
  - "Reset window size and position": [Reset].
- `ON-SCREEN NOTIFICATIONS` (section right [Preview])
  - Description: "Level-ups, deaths and wipes always show. Everything else is recorded either way."
  - Loot: checkbox.
  - "Show loot from": filter button with the Items quality labels.
- Last row: "Show the welcome guide again" [Show].

**Gold display:**
- the existing `ns.BuildGoldSettings` content, restyled with setting rows, with no logic change;
- the first row gains the "Show your gold on screen" checkbox (the moved prompt).

**Data and sync** (tooltip "Whether your data reaches everbuff.gg, and what is stored")

> Revised by `docs/UX_PRAGMATIC.md` 5 (built on the draft branch); the copy below replaces the 0.9.51 one.

- `CAPTURE HEALTH`, one block, the four facts first:
  - Dot rows in this order: "CAPTURING in Orgrimmar" ("Standing by" with no session); "Saved to everbuff.gg: 142 pulls, confirmed Sat 21 Nov 11:45" (how many pulls the desktop app saved and when the addon saw its confirmation, which is not when they were saved; never seen: "Saved to everbuff.gg: not seen yet", and what to do about it is the row's tooltip); "Pulls waiting · 0"; "Loot · 1,539 pickups". No sentence under a row.
  - Then "Combat log: on" and "Advanced combat logging: on", each with a [Turn on] ghost button only when off.
  - Setting row "Remind me to /reload before I log out", with "Saves your data even if the game disconnects you.", and "Save now".
- `ADVANCED` (collapsed by default via `advancedOpen`; header "ADVANCED ›")
  - "Replay detail": segmented `Fine · Normal · Coarse`, with "Finer detail makes replays smoother and the save file larger. Applies from your next pull."
  - Paste box, placeholder "Paste the code from the desktop app", with "Only if the desktop app asks for it: the pickup is automatic." The error shows only after a paste attempt.
  - "Clear the pulls waiting" and "Clear the loot list": a danger ghost "Clear" (two-step) and "Cannot be undone.", each there only while its store holds something. Clear never resets `combat.fightSeq`. The story events have no row.
  - Diagnostics (aura names, UI health, video note) as status lines.
  - [Copy errors] (`/eb errors`).
- Footer: "everbuff.gg 0.9.51 · type /eb help for every command".

### 4.13 First run and What's new (phase 2)

**First run**
- Trigger: the first time the player opens the window (`/eb` or the minimap button). The window is never auto-opened.
- It replaces Now's content until it is finished or skipped. The sidebar works throughout. On Skip or Finish it sets `welcomeDone`.

**Shape**

| y | Element |
|---|---|
| 92 | step bar: three 8 px dots, S2 apart (current `accent`, done `fgSubtle`, ahead `lineControl`), then META "Step 1 of 3" |
| 124 | TITLE |
| 148 | BODY, max 520 wide |
| below | the step's content block |
| `CONTENT_BOTTOM - 28` | footer, right-aligned to `BOX_R`: Back (ghost, hidden on step 1), the "Skip" link, primary Next (Finish on step 3) |

**Steps**
1. **"Welcome to everbuff.gg"**
   - Body: "The addon captures your pulls, loot, deaths and leveling while you play, so you can see how you are doing here and watch it back on everbuff.gg. You can change everything later in Settings."
   - Three dot rows: "CAPTURING"; "Combat log: off" [Turn on]; "Desktop app: not seen yet" with "Install it from everbuff.gg to record video".
2. **"Show your gold on screen?"**
   - Body: "A small line near the flag shows your gold and how much you made this session. It never covers your game."
   - A preview of the pill, then ghost [No thanks] and primary [Show it].
   - On this step the Next button is hidden. Picking No thanks or Show it moves to step 3.
3. **"Three things to get started"**
   - Three ROW2 rows:
     - "Run a dungeon" / "Your time, bosses and loot show under Dungeons, against your best."
     - "Play as usual" / "Home shows this session at a glance."
     - "Open this window any time" / "Type /eb or click the minimap button."
   - Finish lands on Home > Now.

**What's new**
- Shown once per version (`whatsNewSeen`) as an `accent` notice at the top of Now: "Everbuff has a new look: every run against your best, and what needs you right now." with [See what's new] (primary only when Now has no other primary) and dismiss.
- The detail page "What's new" has up to 5 ROW2 rows, each leading with value and opening the place:
  - "Every run against your best" / "Open Dungeons";
  - "What needs you, on Home" / "Repairs, bags and instances left";
  - "Death recap with the moments before it" / "Home > Deaths";
  - "Every copper traced" / "Loot > Gold".
- The bottom META line: "Combat is now Dungeons. Fights and Deaths moved to Home."

---

## 5. Build plan

Rules for every step:
- `luajit tests/run_tests.lua` stays green.
- `tests/layout.lua` reports 0 spill, 0 overlap and 0 cut.
- Shots come from `shoot.sh` at both sizes, normal and long, and each PNG is read and reviewed before the next step.
- No file-level locals are added to `Emitter.lua`. The 60-upvalue limit is per function, so restyling inside existing functions through `ns.UI` calls is fine.
- Commits use `git -c user.name=jsam -c user.email=samhart.inbox@gmail.com commit`, with no trailer.
- No em dashes. No force-push. Worktrees are removed with `git worktree remove`.

### Tranche 1 (tonight)

0. **Approval issue.** Open it with this spec, the §0.4 list and the before shots. Add the after shots as comments when steps 4, 5 and 6 land. The text ends with `<!-- claude -->`.

1. **Foundation** (`UI.lua`)
   - `UI.S`, `UI.G` (§2.2, including `BOX_L`, `TEXT_L`, `BOX_R`, `TEXT_R`, `WIDE`, `MAIN_W`), `UI.H`, and `UI.C` re-keyed with aliases.
   - The font objects, including HERO, with shadows.
   - `UI.fmtClock`, `fmtWhen`, `fmtDate`, `fmtDay`, `fmtDur`, `fmtDelta`, `fmtNum`, `fmtRange`; `UI.plural`; `UI.Fit`.
   - `ns.fmtMoney{icons=true, units=2}`; `UI.Glyph`.
   - Tests:
     - new `tests/formatters.lua`;
     - new `tests/glyphs.lua` (the cmap scan);
     - update `tests/coin_locales.lua`, `tests/gold_glance.lua`, `tests/fontmetrics.lua` (heights and the no-overlap stacks) and `tests/geometry.lua`.

2. **Kit, tonight's subset**
   - Components: `UI.SubTabs` (with `UI.Tabs` kept as a shim), `UI.Summary`, `UI.Section`, `UI.StatCard` and `UI.StatRow` (with rounding), `UI.Hero` (image and text variants), `UI.FilterButton`, `UI.Menu` (restyle), the `UI.Button` styles (with the click sound and the press shift), `UI.Badge`, `UI.Notice`, `UI.Empty`, `UI.Detail`, the slim scroll thumb.
   - `UI.Table` changes: rows 32, header 24, stripes `panel` 0.5, hover band, selected mark, chevron, `max`, `group`, `wide`, inline loading, empty and no-match text, `TABLE_MAX`.
   - Tests:
     - new `tests/panes/kit.lua`: measurements, states, stripe contrast at 3 L* or more, card labels fit at 900, at most one primary per view;
     - update `tests/panes/framework.lua` and `tests/panes/columns.lua` (`max`, `wide`, cap, width budgets).

3. **Display-only honesty fixes (3a)**
   - The session feed reads all kinds (`Journey.lua` `MILE`).
   - Plurals.
   - Link brackets stripped.
   - "quest" and "Unknown" become muted "Quest 1234" and "Other" with tooltips.
   - One `Sync` function for the "waiting" count, used by the chip and Settings, read on show.
   - Kill counts labelled by period.
   - `ns.Pace` (§4.1).
   - Session XP from live `UnitXP` deltas.
   - Tests: `tests/play_session.lua`, `tests/panes/market.lua`, the main suite.

4. **Chrome and navigation**
   - `buildFrame`: border, title bar, status chip, custom close, sidebar 168 (pitch 36 from y 48; desaturated current icons), Settings pinned.
   - `buildHost`: SubTabs, with no title or subtitle.
   - The alias table, the settings keys and the migration.
   - Host registrations per §0.3.
   - Tests:
     - `tests/panes/others.lua` (hosts, aliases, a fresh DB and a 0.9.51 DB);
     - `tests/render_html.lua` and `tests/render_shot.js` (the §4.0 page keys);
     - update the scratchpad `shoot.sh` page list.

5. **Home > Now** (`Journey.lua`)
   - Hero, cards, NEXT, WORTH A LOOK, the combat-log notice, empty states.
   - New `tests/panes/home.lua`:
     - the ranking and caps;
     - every row kind has an icon;
     - the best drop is green or better;
     - no "Nothing yet" text while the session has events;
     - the XP label sits above the bar's frame level;
     - every card's period is on its card or group header;
     - the pace check;
     - one primary with and without the notice.

6. **Dungeons** (`Dungeons.lua`)
   - Summary line with the instance and lockout segments.
   - Last run hero (verdict, missed bosses, best drop, deaths).
   - Runs columns (§4.5), filter button with "Raids · coming soon", By dungeon (default sort, Level column).
   - Run page via `UI.Detail` with Older/Newer, the cards, and the section order.
   - Fixture states (§4.0) in `tests/export_fixture.lua`.
   - New `tests/panes/dungeons.lua`:
     - every Bosses cell contains "/";
     - every delta is a `fmtDelta` word;
     - one primary button, and none when in progress;
     - the filter clears with its glyph;
     - every run page section is present with its empty sentence;
     - Back restores the scroll offset and selection;
     - "of N" appears only with a limit set.
   - Update `tests/runs.lua` and `tests/runs_bests.lua` for the display text (`Runs.signed` stays for chat).

7. **Acceptance and hand-off**
   - Extend `tests/layout.lua` on rebuilt pages:
     - text left edges are exactly 204 and box edges exactly 192 (right: 864 and 876), with an allowlist for unconverted panes that shrinks as panes convert;
     - the first content top is `CONTENT_TOP` (or +52 under a notice);
     - 0 or 1 primary per view;
     - no `bad`-coloured text on Now or Runs in the normal fixture;
     - each empty sentence's top is within 24 px of its header.
   - Run the full `shoot.sh` (all keys, both sizes, normal and long), read every PNG, and fix every misalignment.
   - Open the **draft** PR linked to the issue, ending with `<!-- claude -->`, listing the in-game checks: portrait, Blizzard icon paths, coin icons, desaturated nav icons, GameTooltip format, sounds.
   - No version bump.

### Phase 2

| Step | Work |
|---|---|
| P1 | Sessions, session page, Activity groups, all-history search; then remove the temporary Activity sub-tab |
| P2 | Fights restyle (Important/All, collapse, fight page with no damage cards) |
| P3 | Deaths (Mine/Everyone, the empty-with-party copy, death page) |
| P4 | Loot: Items; Gold (period plus More, 4 or 5 cards, Break down by, source detail, untraced wording, "6 to review"); Auction house moved from `Market.lua`. Update `tests/panes/items.lua`, `gold*.lua`, `market.lua`, `tests/gold_*.lua`, `tests/play_gold.lua`. Assert no `bad` text on the default Gold view. |
| P5 | Character: Leveling, Reputation, Professions; Crafting removed from `Market.lua`. New `tests/panes/character.lua`. |
| P6 | Settings: setting rows, checkbox, slider, two-step clears, Advanced, footer, scale floor. Update `tests/panes/settings.lua` (no Blizzard templates in `M.frames`). |
| P7 | First run, What's new. New `tests/panes/firstrun.lua`. |
| P8 | WIDE rails on every page (2-up 162 cards or ROW label/value pairs; no primary in a rail). |
| P9 | Move Settings, Timeline and Items out of `Emitter.lua` into `Settings.lua`, `Activity.lua` and `Items.lua`; TOC order, the `tests/run_tests.lua` load list and `tests/export`. A new file needs a full game restart: note it in the release text. |
| P10 (3b) | Stored-data changes. Each needs a named field, an additive `ADDON_DATA_CONTRACT.md` entry, a `tests/export` update and a check that the backend ignores unknown fields. The changes: session XP per session; party deaths per run with names; craft profession at craft time (`Market.lua`); the quest title resolved by id on the next login. |
| P11 | Retire the `UI.SP`, `C.gold`, `UI.Tabs` and `FONT_ROLE` shims; custom nav glyph TGAs; version bump, after founder approval. |

---

## 6. Rule conflicts resolved

- **Gold controls:** a period segmented control plus "More" in the control row, and one filter plus search on the list's section header (Principle 4 allows this).
- **Settings segmented controls** inside setting rows do not count toward Principle 4.
- **Settings column:** since UX polish round 1 it spans the content width at 900, so its controls end on `TEXT_R` like every other page; at WIDE its two 500 px columns stay.
- **One primary per view:** this counts notices and rails. A notice button turns ghost when the view already has a primary.
- **Runs table time vs best:** TIME is the clock inside; VS BEST is first pull to last kill. Both header tooltips say so, matching `paceLines`.

---

## 7. Critic changes rejected or changed

- **Home never scrolls, showing `floor(available/48)` rows** (critic 1, #12). Rejected. One page-level scroll everywhere (critic 3, #6) is simpler, and the row counts would change with every window height. Caps of 4 at COMPACT and 12 at WIDE, plus a "+N more" row, keep Home short.
- **Hero stays 88** (critic 1, #13). Changed to 104. HERO 24, a name line, a label line and a bar or second meta line do not fit in 88 with the measured heights.
- **Round-masked portrait** (critic 1, #13). Changed to square with a 1 px edge, to keep the flat square house style.
- **One-time accent pulse on a best run** (critic 1, #28). Rejected. The renderer cannot verify it, and it adds motion for little value. The BEST badge, the good bar and the HERO verdict carry it.
- **"-42s ↓" deltas** (critic 1, #3). Superseded by critic 2, #5's words ("42s faster"). Arrows are dropped; the words make them unnecessary.
- **Ding estimate models rested XP** (critic 2, #25). Partly rejected. Rested is shown on the bar and label. The estimate uses the measured rate, which already includes the rested bonus earned, because modelling rested on kill XP only would be a guess.
- **Game faction-bar colours for standings** (critic 2, #35). Rejected in favour of critic 1, #16. A neutral yellow would read as `warn`. Only Hated and Hostile are red, because they block vendors and quests.
- **"Desktop app not seen" warn chip for everyone** (critic 2, #10). Narrowed. It warns only when the app was seen before and has gone quiet, so players who never installed it are not nagged.
- **"MOVED BETWEEN YOUR CHARACTERS"** (critic 2, #29). Changed to "MOVED BETWEEN CHARACTERS AND BANK", because bank moves are in it too.
- **Cut ALL PULLS IN THIS RUN at 900** (critic 2, #15). Rejected. It is an existing feature (nothing is lost), and it is last in the order.
- **"Town visits" includes Bank** (critic 2, #24). Bank is dropped: there is no BANK kind on `origin/main`.
- **Instance copy "3 of 5 left"** (critics 1, #10 and 2, #9). Applied only when the player set a limit. The code shows the limit is the player's own (`Runs.limit()`, unset by default), so "of 5" would otherwise be invented.
- **Instance strip folded into the hero** (critic 1, #10). It is folded into the Summary line instead, which every page now has and which holds Q5's answer.
- **COIN LOOTED column at 900** (critic 2, #13). WIDE only, plus the Loot cell tooltip. At 900 the budget fits a LOOT column or a coin column, not both, and players run for drops.
- **Search width 176 for the paste box too** (critic 1, #18). The paste box stays 400: it is a code input, not a search.
- **Static mock renders in step 0** (v1). Replaced by after shots added to the issue as steps land (critic 1, #29).

<!-- claude -->
