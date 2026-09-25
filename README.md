# everbuff.gg WoW addon

**Gameplay recording for data nerds.**

The in-game half of **[everbuff.gg](https://everbuff.gg)**. It records your WoW run the way a flight
recorder records a flight: every fight with a replay you can scrub, every pickup with where it came from,
every death with what killed you, every quest, standing and skill point, and where your gold went. Nothing
to start or stop. Play, and it fills in.

## What you get

Five tabs, one question each. No tab is named after a data type.

| Tab | The question | What is in it |
| --- | --- | --- |
| **Home** | How is my run going? | Level, XP per hour and time to level, gold per hour, time played, the story of this session, and one row per play session with XP and gold bars |
| **Combat** | What happened when I fought? | Dungeon runs boss by boss, every fight with a scrubber that shows your buffs, your group's buffs, the monsters' buffs, gear and items used at any second, and every death with the corpse run and gear lost |
| **Loot** | What did I get? | Every pickup with its source (the mob, the node, the object, the mail, the auction) and the map coordinates, a by-item view, and gold in and out down to repairs, flights and postage |
| **Character** | How is my character growing? | Quests done and in progress with where you did them, standing with every faction, professions with skill bars and milestones |
| **Settings** | | The on-screen flag, notifications, capture health, disconnect protection, stored data |

The **flag** in the corner is the part the everbuff desktop app reads: it marks the moments in your video
recording. Drag it anywhere, right-click to snap it to a corner, size and fade it in Settings.

## Why an addon and not just a combat log

The combat log knows damage. It does not know your level, your gold, what you looted or from where, what
you were wearing, which potion you drank, what your party's buffs were at the second the tank died, or
where on the map any of it happened. This addon records all of that, timestamped to the same clock as the
combat log and the video, so the desktop app can put the three together.

It also handles the awkward client. On the Midnight and "WoW Forever" builds most combat values are
Secret Values that addons cannot read, and the client hides your own buffs a few seconds into every fight.
The recorder is built around that: identities that survive hiding, guards that never record a phantom buff
loss, and a replay that bridges any gap. Verified against real fights.

## Install

The **everbuff desktop app** installs and updates the addon for you. Manual install:

1. Download `EverbuffJournal-<version>.zip` from [Releases](../../releases/latest).
2. Extract so that `Interface/AddOns/EverbuffJournal/EverbuffJournal.toc` exists in each WoW flavor you play.
3. Start WoW. Upgrading from an earlier version needs a full client restart, not `/reload`.

Works on the Midnight beta, Anniversary and Classic Era clients. Open the panel with `/eb`, or click the flag.

Known beta issue: the WoW Forever beta does not persist any addon's SavedVariables across a full restart
(a Blizzard bug that affects every addon). `/reload` keeps your data warm; a restart loses it on that client only.

## Layout

- `Everbuff/` is the addon source, packaged as `EverbuffJournal/` in a release.
- Five host tabs, each built from panes: `Home` (Journey.lua: Overview and Sessions; the Timeline pane lives
  in Emitter.lua), `Combat` (Dungeons.lua, Recording.lua for Fights, Deaths.lua), `Loot` (Emitter.lua Items,
  Economy.lua Gold), `Character` (Progress.lua), `Settings` (Emitter.lua; Capture pane from Sync.lua).
  `Fights.lua` is the per-fight recorder, `UI.lua` the framework (`UI.registerHost`, `UI.registerPane`).
- `tests/` is the headless LuaJIT harness. Run it before every install.
- `docs/` holds the engineering notes: the data contract the desktop parses, the roadmap checklist, the
  audit backlog, the ack channel design, and the Midnight client notes. **Read
  [`docs/MIDNIGHT_ADDON.md`](docs/MIDNIGHT_ADDON.md) before touching the TOC, SavedVariables, or any
  Secret-Value read.**

SavedVariables: `EverbuffDB` (schema 2, mirrors the five tabs: `settings`, `sessions`, `combat`, `loot`,
`character`, `story`), `EverbuffAck` (written by the desktop app while WoW is closed to ack uploads),
`EverbuffTest` (a load canary). The full shape is in [`docs/ADDON_DATA_CONTRACT.md`](docs/ADDON_DATA_CONTRACT.md).

## Client notes and gotchas

- **Secret Values.** On Midnight, enemy names and GUIDs, aura fields and every combat stat can be secret.
  They throw on arithmetic, comparison, concatenation, formatting and as table keys. Guard with the
  `plain`, `safeStr` and `safeKey` helpers and sanitize before saving, or the whole SavedVariables file is
  rejected on load.
- **Your own buffs hide in combat** a few seconds after the pull. The recorder keys auras by instance id,
  skips blind scans, never records a whole-set loss on a living unit, and backfills names after combat.
- **A tainted addon cannot call `ReloadUI()`.** The disconnect-protection reminder uses a secure `/reload`
  button, hides the instant combat starts, and returns once it is safe.
- **TOC changes need a full client relaunch**, not `/reload`. New files too.
- **A wedged addon folder identity** can write SavedVariables but never load them back. Rebuilding under a
  fresh folder name fixed it; the shipped folder is `EverbuffJournal`.
- **Emitter.lua's event handler sits at Lua's 60-upvalue limit.** New module state goes into tables, not
  bare locals, or the file fails to parse.

## Tests

```
luajit tests/run_tests.lua
```

`tests/wow_stub.lua` fakes enough of the WoW API for every file to load in TOC order under plain LuaJIT.
Frames record their handlers and event registrations, so the suite fires real events into the addon's actual
code and asserts on the resulting state: the fight lifecycle, aura guards, loot attribution, mailbox capture,
the ack channel, the schema migration, every tab and pane building and refreshing, and the data contract.
Secret Values cannot be simulated outside the client; their guards' type gates and positive paths are covered.

## Roadmap

[`docs/ADDON_ROADMAP.md`](docs/ADDON_ROADMAP.md) is the checklist of everything planned, done and open, with
per-area progress. [`docs/ADDON_BACKLOG.md`](docs/ADDON_BACKLOG.md) holds the audit detail behind each item.

## Typography and brand

The panel is set in **Chakra Petch** (bundled, SIL OFL), the same face the desktop app uses, so addon and
desktop read as one product. Page titles keep WoW's Morpheus as the single game-voice note. The palette and
component rules are the everbuff design system shared with the desktop and web apps.
