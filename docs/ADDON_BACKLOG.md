# Everbuff Addon Backlog

Source: systematic 7-dimension audit of the addon source (capture, existing tabs, correctness,
performance, flag/UX, desktop contract, new tabs). Every item is tagged:

- **Severity**: H (high) / M (medium) / L (low)
- **Effort**: S (small) / M (medium) / L (large)
- **Vertical**: Lvl (leveling) / Dun (dungeons) / Raid / All
- **Phase**: **Now** (leveling + dungeons focus) or **Later** (raids)

Client reality this all assumes: on the Midnight "WoW Forever" beta, CLEU and most numeric combat
stats are Secret Values that taint addon code; the engine combat-log FILE is the source of truth for
damage. A confirmed beta bug means SavedVariables do not persist across a full restart (all addons),
so treat persistence as out of our hands but design as if it will be fixed.

---

## 0. Verticals and phasing

| Vertical | Status | What it needs from the addon |
| --- | --- | --- |
| **Leveling** | Now | XP pace, /played, gold + economy, quests, professions, reputation, deaths, zones, kills, journey overview |
| **Dungeons** | Now | Grouped instance RUNS, party roster over time, bosses/wipes, run loot + deaths, lockouts, encounter correlation |
| **Raids** | Later | Loot council, roster/readiness, boss-attempt tracking, wipe analysis (the deferred `future/` tabs slot here) |

### Target tab bar (information architecture)

`Home (Overview · Timeline · Sessions) · Combat (Dungeons · Fights · Deaths) · Loot (Items · Gold) · Character (Quests · Reputation · Professions) · Settings (General · Capture · Data)`  (2026-09-25, founder decision: five tabs, one question each; the old tabs are panes inside them. Data mirrors it: schema 2 = settings · sessions · combat · loot · character · story.)

The raw feed was renamed **Timeline** (2026-09-25: "Events" read as calendar events) and stays a top-level tab, now with filter chips; demotion no longer needed.
Quests / Reputation / Professions do not each get a tab; they become sections of one **Progress** tab.
Design the IA so raids extend it (add Raids grouping alongside Dungeons) without a rewrite.

---

## 1. Foundations (cross-cutting; mostly prerequisites for the tabs)

### 1a. Capture layer: data we must start recording

> **DONE 2026-09-21** (Emitter.lua / Core.lua): **gold** (`PLAYER_MONEY` diff of `GetMoney`, split
> looted/gained/spent, coin looted in a loot window is attributed to the source and shown in the Loot
> tab), **XP** (`PLAYER_XP_UPDATE` -> cur/max/rested + session gained, level-cross aware), **/played**
> (`TIME_PLAYED_MSG`, requested on login + each ding, stamped per level in `playedAtLevel`). Loot tab now
> shows coin rows + a "Looted: Xg · N items" totals line. These feed Journey + Economy next. STILL OPEN
> here: full sink attribution (repair/vendor/training split) and quest-vs-kill XP split.

- **[H·M · Lvl · Now] Gold, income and every sink.** (sink attribution DONE 2026-09-25: repairs / vendor / training / flights / other, vendor sales as income; Economy cards show the breakdown) Untracked entirely. Register `PLAYER_MONEY`, diff `GetMoney()`; attribute deltas by context: repairs (`MERCHANT_SHOW`/`RepairAllItems`/`GetRepairAllCost`), vendor buy/sell (`MERCHANT_UPDATE`), training (`TRAINER_SHOW`/`BuyTrainerService`), flight cost (`TAXIMAP_OPENED`). Persist running totals.
- **[H·M · Lvl · Now] XP (quest vs kill vs rested).** Untracked. `PLAYER_XP_UPDATE` + `UnitXP`/`UnitXPMax`/`GetXPExhaustion`; kill XP via `CHAT_MSG_COMBAT_XP_GAIN`, quest XP via `GetQuestLogRewardXP`. Drives XP/hour and time-to-level, which Warcraft Recorder has no answer for.
- **[H·S · Lvl · Now] /played and per-level played time.** `RequestTimePlayed()` on login and each ding; read `TIME_PLAYED_MSG`. Stamp played-at-ding per level.
- **[H·M · Dun/Raid · Now] Talents / spec / glyphs per fight.** (spec name snapshot DONE 2026-09-25: `fight.spec`; full talent string (Classic tree split `31/20/0` DONE 2026-09-25; retail trait string still open) still open) Not snapshotted. Classic: `GetTalentInfo` serialized + `PLAYER_TALENT_UPDATE`. Retail/Midnight: `C_ClassTalents`/`GetSpecialization` + `TRAIT_CONFIG_UPDATED`. Store a build id per fight so the desktop can correlate performance to spec.
- ~~**[H·M · All · Now] Consumables used.**~~ **DONE 2026-09-25**: UNIT_SPELLCAST_SUCCEEDED for the player whose spell is not a known spell = item use; per-fight `uses` + `db.itemUses` tally; fight detail section + gold scrubber landmarks. Only visible indirectly via auras. Capture actual usage from `UNIT_SPELLCAST_SUCCEEDED` (unit == player), classify potion/flask/food via item class. Per-fight list + session tallies. Headline WR feature.
- ~~**[M·M · Dun/Raid · Now] Group composition over time.**~~ **DONE 2026-09-25**: `GROUP_ROSTER_UPDATE` diff emits ROSTERJOIN / ROSTERLEAVE (recorded, not toasted; login seeds silently). `snapshotGroup()` runs once at pull. Add `GROUP_ROSTER_UPDATE` diffing to emit ROSTER_JOIN/LEAVE and append mid-fight roster markers, so a run with a swap or resummon reads correctly.
- ~~**[M·S · Lvl · Now] First-visit zones (not every re-entry).**~~ **DONE 2026-09-25**: persisted `seenZones`, FIRSTZONE milestone on the first entry only; login zone seeded as seen. ZONE fires on every change. Keep a persisted `seenZones` set and emit a FIRSTZONE milestone only when new. Optional exploration % via `MAP_EXPLORATION_UPDATED`.
- ~~**[M·S · Lvl · Now] Durability / repairs / breakage.**~~ **DONE 2026-09-25**: `UPDATE_INVENTORY_DURABILITY` aggregates gear health (shown on the Journey character card), BROKEN milestone once per break; repair gold attributed via a `RepairAllItems` hook. `UPDATE_INVENTORY_DURABILITY` + `GetInventoryItemDurability`; snapshot aggregate % at fight start/end, warn on a slot hitting 0. Pairs with repair-cost gold.
- ~~**[M·S · Lvl · Now] Profession tiers (structured).**~~ **DONE 2026-09-25**: GetProfessions (retail) / Professions+Secondary skill-line headers (Classic) snapshot into `db.professions`; PROFTIER milestone when a rank crosses 75/150/225/300/375/450/525/600. Replace the chat-regex skill-up with `GetProfessions`/`GetProfessionInfo` on `SKILL_LINES_CHANGED`; emit tier-crossing milestones; persist a professions snapshot.
- ~~**[M·M · Lvl · Now] Collections: mounts / pets / toys.**~~ **DONE 2026-09-25**: NEW_MOUNT_ADDED / COMPANION_LEARNED / NEW_PET_ADDED / NEW_TOY_ADDED emit COLLECT milestones (named where the API allows). `NEW_MOUNT_ADDED`/`NEW_PET_ADDED`/`NEW_TOY_ADDED` (+ Classic `COMPANION_LEARNED`). Emit COLLECT milestones + persisted counters.
- **[M·S · Lvl · Now] Death context is thin.** Add death location (`C_Map`), ghost/corpse-run recovery time (`PLAYER_UNGHOST`), and durability loss across the death.
- ~~**[M·S · Lvl · Now] Flight trips (time/route/cost).**~~ **DONE 2026-09-25**: control lost/gained while on taxi -> FLIGHTTRIP (route + duration) + `db.flightTime`; cost is attributed via the taxi-map gold sink. Only new-path discovery fires today. Detect boarding/landing via `PLAYER_CONTROL_LOST/GAINED` + `UnitOnTaxi`; record route + duration + cost; accumulate total flight time.
- **[L·S · Lvl · Now] Reputation full standings.** Only tier-ups fire. Persist a periodic snapshot of all factions (reaction + barValue) for a reputation dashboard.
- **[L·S · Lvl · Now] Recipes learned.** Distinct event via `NEW_RECIPE_LEARNED` (retail) or the learn-spell path (Classic).
- **[L·S · Dun/Raid · Now] Instance lockouts / saved IDs.** `RequestRaidInfo` + `GetSavedInstanceInfo` on `UPDATE_INSTANCE_INFO`; store difficultyID per session. Needed to group logs by raid ID.
- **[L·S · Lvl · Now] Equipped-ilvl / upgrade milestones.** Hook `PLAYER_EQUIPMENT_CHANGED` out of combat too; emit UPGRADE with slot + new `GetAverageItemLevel`.
- **[M·L · Raid/PvP · Later] PvP capture.** World kills/deaths, honor (`CHAT_MSG_COMBAT_HONOR_GAIN`), battlegrounds (`PVP_MATCH_COMPLETE` + `C_PvP.GetScoreInfo`), duels. Out of current focus; needed to be a complete forever-classic recorder.

### 1b. Correctness bugs (fix before these features ship)

> **DONE 2026-09-20** (Emitter.lua / Fights.lua / Recording.lua): party-loot-as-yours (self-loot gate),
> skill-up + discovery + craft localization (patterns derived from client format strings), aura-cap now
> preserves pull seeds (`trimAura`), kill over-count guard (skip if foe still alive), loot-source guard
> (only dead/attackable target), duplicate-DUNGEON-on-reload dedupe, and the member-drilldown dead code
> is wired back (party names clickable). STILL OPEN: loot-quantity locale (`x%d`) and death-killer are
> inherent best-effort, left as-is.

- **[H·M · Dun · Now] Party/raid loot logged as your own.** `CHAT_MSG_LOOT` matches any item link, including "Dave receives loot: [Item]". In a dungeon every groupmate's drop lands in your Loot tab tagged to your current target. Gate on the localized self prefixes (`LOOT_ITEM_SELF`/`LOOT_ITEM_PUSHED_SELF`).
- **[H·S · All · Now] Localization: skill-up parse is English-only.** `match("skill in (.+) has increased to (%d+)")` never fires on non-English clients. Derive from a localized global.
- **[H·S · All · Now] Localization: "Discovered X:" is English-only.** Build the matcher from localized `ERR_ZONE_EXPLORED_XP`.
- **[M·S · All · Now] Localization: craft prefix + loot quantity.** `CREATE_PREFIX` breaks where the item link is first (empty string is truthy, disables craft detection); `x%d` stack parse undercounts on locales without that format.
- **[M·M · Dun · Now] Dead code: member drilldown is unreachable.** After the Fights rewrite, `buildMemberView`/`openMember`/`memberRow` are orphaned; clicking a party member does nothing. Either wire `combatantRow` to `openMember` or remove it.
- **[M·M · All · Now] Aura cap prunes pull-time auras.** `AURA_CAP=150` trims oldest-first, so in long fights the t=0 "gain" seeds vanish with no matching "lose" and the scrubber reconstructs the wrong state. Preserve pull entries (or trim by pairs).
- **[M·M · Lvl · Now] Kill inference over-counts.** Leaving combat alive always logs a KILL of the last target; mob evades, flees, feigns, group-mate kills, or a live tabbed target all register as your kill. Best-effort on the Secret-Values client; tighten the heuristic (require the foe to be dead/gone).
- ~~**[M·M · Lvl · Now] Loot source = current target is wrong for nodes/chests/AoE.**~~ **DONE 2026-09-25**: every loot window is attributed with coordinates; gathering casts (herb/mine/skin/fish, locale-safe via spell ids) label nodes, corpses keep their name when readable, GUID type (object/creature) is the fallback; loot rows carry x/y/zone. Skip attribution when the target is not a dead/attackable unit.
- **[L·S · Dun · Now] Duplicate DUNGEON event on reload inside an instance.** `wasInstance` resets to false each load. Persist "currently in instance" or dedupe.
- **[L·S · Lvl · Now] Death killer can be wrong.** Current-target-at-death may be a fleeing add or cleared. Best-effort; note it as such.

### 1c. Performance and SavedVariables size

> **DONE 2026-09-21** (Fights.lua): UNIT_AURA now rate-limited per unit (~4 scans/sec) so an aura storm
> can't run full scans hundreds of times a second; enemy nameplate sweep decoupled to every 2s (not the
> 1s stat tick); per-member aura timelines skipped in raids (>6 group) - the big SV multiplier; diffMember
> is now an O(1) unit->member map lookup; gear swaps capped at 60. scanAuras allocation churn DONE 2026-09-25 (entries reused across scans, one stat table). Tickers already
> check IsShown. STILL OPEN below: incremental sanitize on combat exit (low value: entries are already plain).

- **[H·M · Raid · Now] UNIT_AURA storm.** Every UNIT_AURA re-scans a unit with up to 80 pcalls; in a busy pull thousands/sec on the main thread. Coalesce into a dirty GUID set drained on a ~0.3s throttle (or rely on the sample tick).
- **[H·M · Raid · Now] Enemy sweep re-scans everything every second.** `sampleTick` sweeps target + boss1-5 + all nameplates (20-40) at full 2x40 scan each, every 1s. Decouple to a slower cadence, stop enumerating nameplates once cap is hit, cap nameplates per sweep.
- **[H·M · Raid · Now] Per-fight aura data can explode.** Worst case ~8.6k aura-event tables per raid fight (self + 16 enemies + 40 members, each 150). Add a per-fight aggregate cap, skip member-aura timelines in 25/40-man (self + a few), consider lowering `AURA_CAP`.
- **[M·S · All · Now] Events ticker never cancels.** After opening Events once, it rebuilds up to 500 rows every 2s forever, even hidden. Cancel on hide + dirty flag. (Same pattern for the Fights list 2s rebuild.)
- **[M·M · Raid · Now] `sanitize()` deep-copies the whole fight on combat exit.** Thousands of pcalls + full allocation right as the pull ends -> hitch. Sanitize incrementally at capture instead.
- ~~**[M·M · Raid · Now] `scanAuras` GC churn.**~~ **DONE 2026-09-25**: scan loop hoisted (no closure per call), one pcall per filter instead of per index, and safeKey/plain/plainSum/safeStr no longer allocate a closure or table per call. Covered by new end-to-end aura-timeline tests. Allocates a set table, a closure, and a table per aura on every call. Hoist the closure, reuse scratch tables, single pcall around the loop.
- **[M·S · Raid · Now] `diffMember` O(group) lookup per friendly aura.** Build a unit-token to member map at pull.
- **[L·S · All · Now] `cur.gear.swaps` has no cap; `table.remove(log,1)` is O(n).** Cap swaps; batch-trim aura logs.

### 1d. Desktop / backend contract (the handoff)

> **DONE 2026-09-25** (Fights.lua): every fight now carries `schema=1`, a globally unique `uid`
> (player-realm-startEpoch-random, survives a fightSeq reset), `player` + `realm` (SV is account-wide),
> `session` id, `startLocal` (client wall-clock; the combat-log FILE is stamped in local time), and
> `instanceType` / `difficultyID` / `instanceMapID` + the numeric `encounterID` from ENCOUNTER_START.
> Enemy GUIDs already persist when plain. STILL OPEN below: the ACK channel itself (needs a desktop-side
> design), FIFO cap dropping un-acked fights, sub-second video anchor, session prune, wire-contract doc.

- **[H·L · All · Now] Upload ACK channel does not exist.** `pruneUploaded` reads `uploaded`/`uploadedThrough` but nothing can ever set them (WoW rewrites the SV file wholesale on logout; the desktop can only safely write while WoW is closed, or via a copy-paste import string). This is the single biggest TBD; design it before cleanup works at all. Recommend a sibling companion SavedVariables the desktop writes only while WoW is closed, applied on next `ADDON_LOADED`.
- **[H·M · All · Now] Fight id is not globally unique.** `fightSeq` resets to 0 when SV is lost (the beta bug), so ids collide across the ack boundary. Mint a UUID per fight (session id + seq or random) and ack on that.
- **[H·S · All · Now] Fights carry no character/realm/account identity.** SV is account-wide, so multiple characters' fights mix indistinguishably. Add player + realm (or a stable owner key) and the session id to each fight.
- **[H·M · Dun · Now] No log-file correlation keys.** Store both `time()` (local) and `GetServerTime()` at pull (log file is local time), keep the numeric `encounterID`, `instanceMapID`, and `difficultyID` (only bossName text is kept today).
- **[H·S · All · Now] FIFO cap drops fights before consumption.** (mitigated 2026-09-25: one chat warning per session within 25 of the cap + Sync shows N of 250; true fix is the ack channel) With no working ack, `FIGHT_CAP=250` permanently discards the oldest unuploaded fights on a >250-pull day. Same risk for `lootlog` (2000) and `eventlog` (500). Block prune of un-acked records or warn.
- ~~**[M·M · All · Now] No video correlation anchor.**~~ **DONE 2026-09-25**: `startLocalHi` / `endLocalHi` = fractional local wall-clock from a one-time time()/GetTime() calibration. Whole-second `GetServerTime` plus monotonic `GetTime` duration gives no fractional wall-clock to align a fight boundary to a video frame. Emit a high-res local timestamp + a one-time GetTime->epoch calibration per session.
- **[M·S · All · Now] No SV schema version on fights + no migration.** Sessions have `schema=4`; fights have none. Add a per-fight schema int and a documented compat rule.
- **[M·S · Dun · Now] Enemy GUIDs tracked internally but dropped before storage.** The log identifies units by GUID; persist enemy/boss GUIDs so the fight's enemy timeline joins to the file.
- ~~**[M·M · All · Now] No documented serialization contract.**~~ **DONE 2026-09-25**: `docs/ADDON_DATA_CONTRACT.md` + a contract section in the test suite asserting the shape (top-level keys, fight fields, no pipes). Sessions are TAB-delimited pipe-stripped strings; fights are sanitized nested tables (pipes stripped, secret/NaN dropped, depth-12 cap). The desktop cannot tell "hidden by taint" from "not captured". Define the wire contract + an explicit missing-because-secret marker.
- **[M·S · All · Now] No integrity manifest.** Add `UnitGUID('player')` + server/local start/end to each session so the desktop can bind SV to the exact combat-log slice.
- **[M·M · All · Now] Sessions grow unbounded.** `pruneUploaded` only touches fights; add a symmetric session ack/prune.
- **[L·M · Raid · Later] `db.loot` is initialized but never captured/versioned.** When loot-council lands it needs the same identity + correlation + ack design; build the contract once.

---

## 2. Existing tabs: fixes and additions

### Fights
> **DONE 2026-09-21** (Recording.lua): filter chips (All / Notable / Kills / Wipes / Deaths — Notable =
> bosses + wipes + your deaths, the flood-control cut), an aggregate summary line (fights · kills · wipes ·
> deaths · time in combat), and the When column now shows the date. Inline loot in the fight detail DONE 2026-09-25. Party deaths DONE 2026-09-25 (UNIT_HEALTH/UNIT_FLAGS boolean read; deadT per member, memberDeaths per fight; shown in the list, detail rows and dungeon boss rows). Day separators (Fights + Timeline, Today/Yesterday/weekday) and per-fight Delete with two-click confirm DONE 2026-09-25. STILL OPEN below: run grouping.

- **[H·M · All · Now] No filtering / search / sort.** (filters, text search and clickable column sort all DONE 2026-09-25) Add filter by result (kill/wipe/death/fled), by zone/dungeon, boss vs trash; search foe; sortable columns.
- **[H·M · All · Now] No aggregates or run/day grouping.** Add a summary header (total fights, kills/wipes/deaths, win rate, time in combat, longest fight) and grouping by dungeon run / zone / day. This is the flood-control fix: trash fights currently bury everything.
- ~~**[H·M · All · Now] Scrubber has no landmarks.**~~ **DONE 2026-09-25**: clickable ticks above the scrubber for your death/wipe (red), gear swaps (cyan), and each enemy joining (dim); click jumps the scrubber, hover names it. Overlay tick marks / jump buttons for pull, your death, gear swaps, add appearances, aura changes (derivable from `enemies.firstT`, `gear.swaps.t`, aura logs, death time).
- **[M·S · All · Now] List row lacks date, zone, group size.** Add a day header/column, a Zone column, a solo/N-player indicator (all already known).
- **[M·M · All · Now] No inline loot or party deaths in the fight recap.** Correlate `lootlog` by the fight's time window; show who else died, not just you.
- **[M·M · All · Now] No delete/clear, no row tooltip.** Per-fight delete + clear-all; hover tooltip (roster preview, zone, exact start).
- **[L·M · All · Now] Detail has no click-through to Events/Loot for the fight window.**

### Events
> **DONE 2026-09-25** (Emitter.lua): filter chips (All / Journey / Combat / Travel / Loot), a Where column
> showing subzone, zone and the captured coordinates, click-through (combat rows open their fight via
> `ns.OpenFightDetail`, loot rows open the Loot tab), and the rebuild ticker now only runs while the tab
> is visible. STILL OPEN below: day grouping, surfacing standing/craft fields in a tooltip. Text search DONE 2026-09-25 (Timeline + Loot).

- **[H·M · Lvl · Now] Captured coordinates are never shown.** Every entry stores zone/sub/x/y and it is invisible. Add a Where column or hover tooltip (the map-correlation payload).
- **[M·M · All · Now] No filter / search / grouping.** Type filter (LABELS/COLORS already key off kind), text search, session/day/zone grouping.
- **[M·M · All · Now] Rows not clickable.** KILL/BOSS/WIPE/DEATH should jump to the fight; LOOT should jump to Loot (`UI.Open` exists, unused between tabs).
- **[L·S · All · Now] Extra captured fields never surfaced.** standing (REP), craft/crafted (SKILLUP), guid, could show in a tooltip.
- Note: per the IA, Events is ultimately demoted to a raw "Activity log" drawer.

### Loot

- DONE 2026-09-25: mailbox capture. Auction proceeds, auction wins/returns, and items or gold a player mailed
  land in the Loot tab with the mail's origin as source; auction house and mailbox gold sinks in Economy.
- **[H·M · Lvl · Now] No gold capture or totals.** No `CHAT_MSG_MONEY` handler exists; coin is never captured. Add money + a running gold total and an item-count total to the header. (Your original catch.)
- **[M·M · Lvl · Now] Claims aggregation but shows a flat log.** Add an aggregated mode (item -> total qty, drop count, best source) + a Totals row, or fix the misleading comment.
- **[M·S · All · Now] No item tooltip / shift-link.** Rows are non-interactive. Store the itemID/link, wire `GameTooltip:SetHyperlink` on hover + chat-link on click.
- **[M·M · All · Now] No quality filter / search / sort / source grouping.** Quality and source are already captured, so filtering is cheap.
- **[L·S · All · Now] Empty-state copy contradicts persistence.** "No loot yet this session" vs "Persists across reloads"; render lootlog consistently and fix copy.

### Settings
> **DONE 2026-09-21** (Emitter.lua): stat-sampling slider (writes `settings.statSample`, 1-10s, applies
> next fight) and data management (stored counts + Clear fights/loot/events with a two-click confirm).
> Capture-health now lives in the Sync tab. Per-kind flag toggles and loot-toast threshold (Uncommon+/Rare+/Epic+/Off) DONE 2026-09-25. STILL OPEN below:
> manual Save-now button, multi-style preview.

- **[H·M · All · Now] Missing stat-sampling slider.** You explicitly asked for this; `settings.statSample` is read by Fights.lua but there is no control. Add a cadence slider (fidelity vs SV size) + on/off.
- **[H·M · All · Now] No data management.** No clear (fights / eventlog / lootlog), no SV size / per-list counts display. Add per-list clear + clear-all with confirm + storage usage.
- **[M·M · All · Now] No capture-health / version panel.** Surface recording state, ACL on, secret-values client detected, last save, version, client mode.
- **[M·M · All · Now] No control over what flags on-screen or the loot-toast threshold.** Per-kind flag toggles (travel / quests / loot / kills) + rare-only vs everything loot toast; SHOW_SECS / scale / opacity.
- **[L·S · All · Now] Reminder-only save; preview shows one style.** Add a manual "Save now (/reload)" button; cycle preview kinds (Death/Loot/Boss).

### UI framework (shared)
- **[M·L · All · Now] Fixed 900x580 window, tabs hardcode narrow widths, no shared filter/sort widgets.** Add dropdown/search/sortable-header helpers (this is why every tab lacks filtering) and make tab layouts fill the host.

---

## 2b. Visual redesign (DONE 2026-09-25, UI.lua framework)

Every tab draws through the shared framework, so restyling UI.lua lifted the whole addon: everbuff.gg
brand palette (ink / tan / lagoon / ember / bone), WoW's Morpheus face for titles via `UI.TITLE_FONT`,
the game's ornate gold dialog frame on a dark textured ground, tooltip-textured cards and buttons with
a lagoon hover glow, a flat tab rail with a gold accent bar + icon tint. Also: the disconnect reminder
now hides the instant combat starts and only reappears once out of combat for 8s and alive
(`safeToReload`), and the toast is presentation-only (`pcall(show)`, state written first).

## 2c. Type kit (DONE 2026-09-25)

Investigation: brand tokens say Bricolage Grotesque / IBM Plex, but the SHIPPED desktop CSS resolves
`--disp`, `--sans` and `--mono` all to **Chakra Petch**, so that is the real product face. Bundled the
OFL TTFs (Regular/SemiBold/Bold) in `media/fonts/`; `UI.Font()` maps every Blizzard template to a
role font (TITLE = Morpheus 20 kept as the one game-voice note; VALUE = Chakra Bold 18 for dashboard
numbers; HEAD 13 / LABEL 10 SemiBold; BODY 12 / BODY_SM 11 / DIM_SM Regular). All 43 direct
CreateFontString sites now go through `UI.FS`; pooled cells no longer reset to Blizzard fonts. Title-bar
status line restyled (label face, brand colors, uppercase). Secure reload buttons + disconnect modal
match the tooltip-trim style. Native `ARIALN` fallback if a font file is missing.

## 2d. Honest capture wording (DONE 2026-09-25)

The header said RECORDING, but the addon only knows its own session beacon + combat-log switch; it has no
inbound channel from the desktop, so it cannot know whether video is recording. Header now shows one
indicator: CAPTURING / CAPTURING (basic log) / CAPTURING, COMBAT LOG OFF / STARTING / STANDING BY. Sync
tab says "Capture" and states that video recording is shown in the desktop app. "Recording" is reserved
for the desktop. If a real desktop->addon channel ever exists (companion SavedVariables written while
WoW is closed, or a paste-import), a "desktop linked" state can be added then, never before.

## 2e. Tabs everywhere + Source/Location split (DONE 2026-09-25)

`UI.Tabs` (bordered pane, tabs on its edge) is now the ONLY switching/filtering control: Settings sub-tabs
(pane mode) and the Fights + Timeline filters (shared-pane mode, list inside the pane). Chip/button rows
are gone. Source (who/what) and Location (zone + coords) are separate columns in every tab: Loot
(Dropped by | Location; `src` no longer embeds coords, legacy rows split on display), Fights (new
Location column; fights now capture map/x/y at the pull), Deaths (Location with coords | Slain by),
Timeline ("Where" renamed Location), fight detail + death recap show coords. Coordinates are their OWN column (Coords, bare "42.1, 63.7") next to Location (name) in Timeline, Loot,
Fights and Deaths (2026-09-25): `UI.fmtPlace` + `UI.fmtCoords`; `UI.fmtLocation` only for prose lines.

## 2f. In-combat aura hiding on the beta (DONE 2026-09-25, verified from SV data)

Real fights showed all buffs seeded at the pull, then ALL lost at t~4-5s and all re-gained at fight end:
the client hides your own aura data a few seconds into combat, sometimes returning no auras at all.
Fixes in Fights.lua: identity by `auraInstanceID` (+ spell-id name resolution + post-combat backfill),
a blind-scan guard (auras visible but unidentifiable -> no diff) and a vanish guard (>=2 auras -> 0
while alive -> no diff). Per-fight `auraHidden`/`auraBlind` counters persist for verification.
Settings > Capture shows the counts. A scrubber-side `repairAuraLog` (Recording.lua) additionally bridges any hidden window at render time (only-losses cluster that empties the active set mid-fight and is fully re-gained later), so old recordings and unseen client behaviors cannot show a phantom wipe-and-return; the detail notes when a gap was bridged. XP quest/kill split, reputation snapshot, RECIPE and UPGRADE
milestones also landed in this pass; `docs/ACK_CHANNEL_DESIGN.md` written for the founder's decision.

## 3. On-screen flag / toast (the desktop OCR channel)

- **[H·M · All · Now] Machine-readable OCR line is computed but never rendered.** `Emitter.event` builds a clean `machine` string ("LEVELUP 40 Duskwood") but `show()` only draws the styled `human` text. Either render `machine` as a second line (as the header promises) or officially make `human` the OCR contract and verify it against the desktop parser. This is the addon's core reason to exist; resolve the contract with the desktop.
- **[H·M · All · Now] No dedup / throttle / coalescing.** Sequential 2.6s toasts, queue caps at 12 and silently drops. A leveling/dungeon burst backs the real-time channel up ~31s and loses events past 12. Add per-kind throttle/dedup + collapse repeats.
- **[M·M · All · Now] Flag-vs-silent split is hardcoded.** Constant zone/quest toast spam with no user control and no way to opt trash loot/kills in. Ties to Settings per-category toggles.
- **[M·M · All · Now] Flag is corner-only, not free-drag, not hideable, fixed scale.** Overlaps default minimap; no opt-out; OCR may want a known size. Add X/Y nudge or free-drag, size slider, hide toggle (with a "desktop capture needs this" warning).
- ~~**[M·M · All · Now] No minimap / LibDBIcon button.**~~ **DONE 2026-09-25**: native draggable minimap button (angle persisted), left-click open, right-click Settings. Only entry points are `/eb` and the flag. Add a discoverable launcher that mirrors recording status.
- **[M·M · All · Now] Window is fixed-size and position not saved.** (position persisted in `settings.winPos`; scale slider 70-130% in Settings, 2026-09-25; true resize still open) Persist point/size/scale; add resize grip.
- **[M·M · All · Now] No first-run onboarding.** (a welcome line on Journey while there is no data yet, 2026-09-25; a proper pairing walkthrough still open) Explain the flag, that it must stay visible for OCR, and how to pair the desktop app.
- **[L·S · All · Now] Colorblind: kill/wipe/death conveyed by color only.** Add a per-kind glyph.
- **[L·S · All · Now] Tooltips inconsistent; corner-cycle order differs from Settings; flag strata is TOOLTIP.** Minor polish.

Verified NOT a bug: the brand emblem path (`Interface\AddOns\EverbuffJournal\media\mark`) is correct; the installed folder is `EverbuffJournal` and the media exists. (Housekeeping: the repo has 5 stale `.toc` files; keep only `EverbuffJournal.toc`.)

---

## 4. New tabs to add

### Journey / Overview  [H·M · Lvl · Now]  <- new landing tab   ✅ DONE 2026-09-21 (Journey.lua)
Built: new `Journey.lua` (order 0, landing tab; flag left-click + default open now go here). Cards for
Character/level, Experience (% + rested + full-width XP bar), Time played, Gold (balance/looted/spent),
Combat (kills/deaths/fights), Leveling pace (played per last level), and a recent-milestones ribbon.
Reads existing eventlog/gold/xp/played data; live-refreshes every 3s while shown. STILL OPEN: quest-vs-kill
XP split (DONE), XP/hr + time-to-level on the pace card (DONE 2026-09-25), richer pace chart, per-session grouping.

Original spec below.

The glanceable "how is my run going?" screen; the thing a per-pull recorder cannot do. Mostly already
in `eventlog`: level + XP pace (diff LEVELUP timestamps), deaths, kills, milestone ribbon (ACHIEV /
DISCOVERY / FLIGHT / SPELL / REP). Needs the small new captures /played and gold. Effort is layout.

### Dungeons  [H·M · Dun · Now]  <- flagship of the current milestone   ✅ DONE 2026-09-21 (Dungeons.lua)
Built: new `Dungeons.lua` (order 1). List of runs (window between DUNGEON and DUNGEONLEAVE) with time,
name, length, bosses, deaths, loot; in-progress marker. Click a run -> detail with party, loot summary,
and a clickable Encounters list that deep-links into the Fights detail (`ns.OpenFightDetail`). Fights tab
moved to order 3. Boss-by-boss breakdown (attempts, wipes, time in combat, down-at offset), run deaths with downtime and rare+ loot list DONE 2026-09-25. STILL OPEN: per-run combat-log-file correlation, lockout tie-in.

Original spec below.

Group instance RUNS, not per-encounter fights: a run = the window between a DUNGEON and its
DUNGEONLEAVE event. Card per run (instance, date, duration, bosses X/Y, deaths, wipes, party) that
expands to its encounters, each linking into the existing Fights detail/scrubber. Draw from the
deferred `future/Runs.lua` scaffold. This is the clearest head-to-head win vs Warcraft Recorder.

### Deaths  [H·M · Lvl · Now]   ✅ DONE 2026-09-21 (Deaths.lua)
Built: new `Deaths.lua` (order 2). Every death from the eventlog, matched to its fight when there is one
(click deep-links into the Fights recap at the death moment). Summary line aggregates cause of death
(most frequent killer, deadliest zone). STILL OPEN: dedicated hardcore final-clip framing. Corpse-run downtime column DONE 2026-09-25.

Original spec below.

A hardcore-style recap gallery. Mostly a filtered view: `eventlog` DEATH entries give the one-line list
with coords; fights with `outcome=='death'` already hold the full forensic recap (the detail view
already renders the red "You were slain by..." headline at the death moment). Add cause-of-death
aggregation (which mobs/zones kill you most).

### Economy  [M·M · Lvl · Now]   ✅ DONE 2026-09-21 (Economy.lua)
Built: new `Economy.lua` (order 41). Cards for balance / looted / gained / spent / net (session). STILL
Per-sink split and gold-per-hour DONE 2026-09-25.

Original spec below.

Gold in/out over time + loot value. Primary data (gold) is the one strong-candidate tab not yet
captured, but capture is cheap and taint-free (`GetMoney` is a plain number). Loot value joins
`lootlog` quality/count to vendor price desktop-side.

### Sync / Capture status  [M·S · All · Now]   ✅ DONE 2026-09-21 (Sync.lua)
Built: new `Sync.lua` (order 45). Recording state, combat/advanced logging, client mode (Secret Values
note), stored counts + pending-upload count, a SecureActionButton "Reload & save", and the overlay flag
preview. STILL OPEN: real "last synced" once the ack channel exists; move disconnect controls fully here.

Original spec below.

The trust surface for a recorder. Mostly presents values that already exist: unsaved-fights count +
Reload & save (the SecureActionButton path exists), the beta persistence caveat stated plainly,
uploaded vs pending (once the ack channel lands), client mode (`ns.hasSecretValues` -> "DPS comes from
the log file"), and a live flag/OCR preview. Also the natural home for disconnect-protection controls.

### Progress (Quests / Reputation / Professions)  [M·S · Lvl · Now]   ✅ DONE 2026-09-25 (Progress.lua, order 42; sub-tabs Quests · Reputation · Professions; needs a full client restart once for the new file)
One themed tab with three sections, all from `eventlog`: Quests (QUESTACCEPT/QUESTDONE/REWARD with
locations), Reputation (REP tier-ups; full standings once captured), Professions (SKILLUP with
craft/crafted). Avoids over-fragmenting the tab bar for a leveling product.

### Raids grouping  [ · Later]
Extend the Dungeons run-grouping to raids and light up the deferred `future/` tabs (Crew, Loot council,
Readiness) when the raid vertical opens.

---

## 5. Suggested order of execution (Now phase)

1. **Correctness bugs that corrupt current data first** (1b): party-loot-as-yours, localization parses, aura-cap pruning, kill over-count. These poison the data every other feature displays.
2. **Cheap high-value captures** (1a): gold, XP, /played. Unlocks Journey + Economy + Loot totals.
3. **Fights list flood-control** (Section 2): filter + group + aggregate header. Biggest existing-tab usability win.
4. **Journey (landing) + Dungeons runs** (Section 4): the two flagship new tabs; reuse the data above.
5. **Settings depth** (Section 2): sampling slider + data management.
6. **Performance pass** (1c) before enabling heavy raid capture.
7. **Desktop contract** (1d): ack channel + unique ids + correlation keys. Required before real cleanup/upload.
8. **Deaths, Economy, Sync, Progress** tabs; demote Events.
9. **Raids vertical** (Later): PvP capture, raid grouping, `future/` tabs.

---

## Test harness (added 2026-09-25; UI smoke added same day: every tab is built + refreshed against real data, tickers run, a fight detail is rendered with the scrubber; selectTab now records build/refresh errors, shown in Sync as UI health)

`tests/run_tests.lua` + `tests/wow_stub.lua`: 89 assertions covering module load, DB boot, localization
pattern builder, self-loot gating, craft detection, gold/XP//played capture, fight lifecycle + identity
keys, kill over-count guard, dungeon dedupe, run grouping, death matching, aura cap/replay, sanitize, and
formatters. First catch: recording state was gated on toast rendering (fixed: state first, toast in pcall).
