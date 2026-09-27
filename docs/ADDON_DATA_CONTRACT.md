# Addon data contract (what the desktop parses)

The addon writes ONE SavedVariables file per account:
`WTF/Account/<account>/SavedVariables/EverbuffJournal.lua`, containing the globals `EverbuffDB`
(everything below) and `EverbuffTest` (a load canary, ignore). WoW writes it on `/reload` and logout
only; a disconnect loses everything since the last write. `tests/run_tests.lua` has a contract section
that asserts this shape; change both together.

## Invariants (sanitize)

Every fight is deep-sanitized before storage (`Fights.lua sanitize`):
- strings never contain `|` (item-link escapes are stripped; item names are stored structured instead);
- numbers are finite (NaN/inf dropped) and never Secret Values (dropped);
- tables are at most 12 levels deep; functions/frames never appear.
A **missing field means "not available"**: either the client hid it (Secret Value) or it was not captured.
The parser must treat absence as unknown, not zero.

## Top level (`EverbuffDB.schema = 2`)

The file mirrors the product structure: one area per tab. Facts are stored once; Deaths, dungeon runs
and the Home cards are derived at render time and never duplicated. Every fight, pickup and event
carries `s`, the id of the session it happened in, so the backend can slice everything by play session.
A v1 file (flat keys) is migrated in place on load (`Core.lua ns.migrateDB`); v1 slots are removed.

| key | type | notes |
| --- | --- | --- |
| `schema` | int | 2 |
| `settings` | object | UI prefs only: `emitCorner, autoSave, statSample, flagMute{}, winPos{}, winScale, minimapAngle, welcomed, lootToast, flagScale, flagAlpha, flagHidden, flagPos{point,x,y}, onboarded, winSize{w,h}` |
| `sessions` | map id -> session | HOME. One record per login -> logout (a `/reload` resumes it): identity (`player, realm, class, guild, build, flavor, addonVersion`), `guid` (player GUID), `startedEpoch`, `startedLocal`, `endedEpoch?`, `endedLocal?`, `recovered?` (closed on the next login after a crash), `level0 -> level`, `context`, `logging`, TAB-delimited `segments[]` (Segments.lua beacon), and live counters `xp, gained, spent, kills, deaths, fights, items, dungeons` |
| `active` | id or nil | the session in progress |
| `combat` | object | COMBAT. `fights[]` (below; oldest first, capped at 250), `fightSeq`, `uploadedThrough?`, `lastAck? { at, through?, fights, source }` |
| `loot` | object | LOOT. `log[]` = every pickup, item rows and coin rows (below; capped at 2000); item row `q` is the 8-hex quality color (`ff9d9d9d` poor .. `ffe6cc80` artifact), read from the link's `|cff` color or its `|cnIQ<n>:` named color (11.0+ and Forever), else from `C_Item.GetItemQualityByID`; white rows with an id are backfilled on login (0.8.2); `gold` totals `{ balance, gained, spent, looted, sold, auctionSales, mail, repairs, vendor, training, flights, auctions, mailSpent, other }` in copper; `history`, `reserves` reserved for raid loot council |
| `character` | object | CHARACTER. `xp { cur, max, rested, gained, fromQuests, fromKills, last, lastMax }`, `played { total, level, atEpoch }`, `playedAtLevel { level -> seconds }`, `professions { name -> { rank, max } }`, `reputation { faction -> { standing, label } }`, `durability { pct, at }`, `ilvl`, `seenZones { zone -> epoch }`, `itemUses { name -> count }`, `flightTime`, `lockouts[] { name, id, resetAt (epoch), difficulty, raid?, players, bosses, down, extended? }` |
| `story` | object | the feed behind Home. `events[]` (below; capped at 500), `inInstance?` (dedupe state) |

## Fight record (`schema = 1`)

| field | type | notes |
| --- | --- | --- |
| `id` | int | `fightSeq` at store time (per file) |
| `uid` | string | `player-realm-startEpoch-hex4`, globally unique: **use this as the ack key** |
| `schema` | int | 1 |
| `player`, `realm` | string | who fought (the file is account-wide) |
| `session` | string or nil | owning session id (same value as `s` on events and loot rows) |
| `startEpoch`, `endEpoch` | int | server time (whole seconds) |
| `startLocal` | int | client local time at pull (the combat-log FILE is stamped in local time) |
| `startLocalHi`, `endLocalHi` | float | fractional local wall-clock from a one-time time()/GetTime() calibration: **video anchor** |
| `duration` | float | seconds |
| `zone` | string | `GetRealZoneText` at pull |
| `map`, `x`, `y` | int, float, float | map id + 0..1 coordinates at the pull. Never joined into a string: `zone` is the Location column, `x`/`y` the Coords column, so the backend indexes them as numbers |
| `level` | int | player level |
| `spec` | string or nil | specialization (retail) or the talent tab with most points (Classic) |
| `instanceType`, `difficultyID`, `instanceMapID` | string, int, int | from `GetInstanceInfo` |
| `encounterID` | int or nil | numeric id from ENCOUNTER_START: joins to the log file's ENCOUNTER_START line |
| `bossName` | string or nil | encounter name |
| `foes` | array of string | mobs faced (names may be missing on the Secret-Values client) |
| `outcome` | `kill` / `wipe` / `death` / `fled` | `fled` = left combat with no foe |
| `group` | array or nil | `{ name, class, race, level, unit, me, deadT? }` at pull (nil when solo); `deadT` = seconds into the fight that member died |
| `talents` | string or nil | Classic: talent points per tree at the pull, e.g. `"31/20/0"` (order = talent tabs). Retail / Midnight: the game's talent import string (loadout code) |
| `uses` | array or nil | items used during the fight: `{ t (s into fight), name, sid (spell id), icon }`; a cast that is not a known spell |
| `memberDeaths` | int or nil | how many groupmates died in this fight (your own death is `outcome = "death"`) |
| `auras` | array | player buff/debuff timeline, see below |
| `memberAuras` | map name -> array | per party member (party-sized groups only, not raids) |
| `enemies` | array | `{ name, guid?, firstT, auras[] }` (guid only when not secret; same-named mobs merge when it is) |
| `gear` | `{ initial{ slot -> item }, swaps[] }` | item = `{ name, id, icon, quality }`; swap = `{ t, slot, name, from, to }` |
| `stats` | array | readable character snapshots `{ t, level, ilvl, hp, mana, prim[5], ap, rap, crit, spellCrit, haste, mastery, hit, spellPower, weapon{}, armor, defense, dodge, parry, block, resist{} }`; mostly absent on the Secret-Values client |
| `uploaded` | bool | reserved for the ack channel |
| `auraHidden`, `auraBlind` | int or nil | diagnostics: aura reads with a hidden name / scans skipped as unreadable during this fight |

**Aura entry**: `{ t, gain, name, icon, debuff, inst?, sid?, atPull }`. `inst` (aura instance id) is the identity
when present; `name` may be nil if the client hid it and no spell id was readable (show as unknown).
The recorder skips scans the client returns as unreadable (see `auraBlind`), so the active set is
carried across those windows rather than recorded as lost. `t` is seconds since pull; `gain=false` is a loss;
`atPull=true` marks the seed set. Replay in order to reconstruct the active set at any `t`.

## Event log entry

`{ t (server epoch), s (session id), kind, text, combat?, foe?, prof?, craft?, crafted?, standing?, guid?, zone?, sub?, map?, x?, y?, downtime? }`
(`downtime` is stamped on a DEATH row once you are back on your feet: seconds from death to revive, the corpse run; `durLoss` is the gear durability percentage lost across that death.)
(`x`,`y` are 0..1 map fractions.) Kinds: `LEVELUP ZONE FIRSTZONE DUNGEON DUNGEONLEAVE QUESTACCEPT QUESTDONE
REWARD BOSS KILL WIPE DEATH ALIVE SKILLUP DISCOVERY FLIGHT FLIGHTTRIP LOOT ACHIEV SPELL REP ROSTERJOIN
ROSTERLEAVE BROKEN COLLECT PROFTIER RECIPE UPGRADE`. Only rare+ LOOT lands here (all loot is in `loot.log`).

## Loot log entry

Item: `{ t, s (session id), item, count, q (hex color), icon, src, guid?, quest?, x?, y?, zone? }`. `quest = true` marks a quest item (item class 12).
Coin: `{ t, s (session id), money (copper), src, guid?, x?, y?, zone? }`.
`src` is the SOURCE only: the mob name when readable, else `"Mining node"` / `"Herb node"` / `"Fishing spot"` /
`"Skinned creature"` / `"Object"` / `"Creature"` / `"Unknown source"`; items pushed without a loot window use the world object just clicked (its name), the mob just killed, `"Quest reward"`, or `"Picked up"`. Location is separate: `zone` (name) and `x`, `y` (numeric coordinates), each its own field and its own UI column.
(Rows written before 2026-09-25 embedded " at (x, y)" in `src`; the UI splits those on display.)
Mailbox rows (2026-09-25): `src` is `"Auction sale"` (coin row), `"Auction won"`, `"Auction returned"` or
`"Mail from <sender>"`, with `mail = { sender, subject, item?, buyer?, seller?, cod? }`. Location is the mailbox.
Classic prints no chat line for mail pickups, so these come from hooks on `TakeInboxItem` / `TakeInboxMoney` /
`AutoLootMailItem`. Gold breakdown fields: `auctionSales`, `mail` (income); `auctions`, `mailSpent` (sinks).

## Correlating to the combat-log file and video

1. Window: `startLocal .. startLocal + duration` (local time, like the log) or `startLocalHi` for frames.
2. Encounters: match `encounterID` to the log's `ENCOUNTER_START` line.
3. Identity: `player`/`realm`; enemies by `guid` when present.
4. Ack (once the channel exists): mark `uploaded=true` per `uid`, or set `uploadedThrough`; the addon
   prunes on next load (`pruneUploaded`). The addon warns in chat when history is within 25 of the cap.

## Upload ack channel (desktop -> addon)

Two inbound paths, both consumed by `ns.applyAck` on the addon side:

1. **Companion SavedVariable, automatic.** While NO WoW client is running, the desktop writes
   `WTF/Account/<account>/SavedVariables/EverbuffAck.lua` containing
   `EverbuffAck = { uids = { ["<fight uid>"] = true, ... }, through = <server epoch> }`.
   On the next `ADDON_LOADED` the addon marks fights with those uids, and every fight that started at or before
   `through`, as uploaded and prunes them; loot rows, events and finished sessions with `t <= through` are pruned
   too. The addon then empties `uids` and stamps `applied`, so the file never grows and is never applied twice.
   Writing while the game runs is useless: WoW rewrites SavedVariables wholesale on `/reload` and logout.
2. **Paste code, manual.** The desktop shows `EB-ACK-<epoch>` (optionally `:<uid>,<uid>,...`) after an upload;
   the player pastes it in Settings > Data or types `/eb ack <code>`. Same effect, applied immediately.

`combat.lastAck` records the last applied ack; Settings > Capture shows "Desktop sync: last synced ...".
Ack on `fight.uid` (globally unique), never on `fight.id`.

## Signal strip (video-side markers, `Signal.lua`, loaded since 0.8.3)

Ten square cells at the absolute top-left of the screen, 16 UI units each, shown for 12 seconds per event,
never blinking. Two bits per cell (black 00, white 01, magenta 10, cyan 11): cells 1 to 2 are the sentinel
magenta, cyan (they also give the decoder the cell size), then type, sequence, payload and checksum as four
nibbles, checksum = (type + sequence + payload) % 16. The desktop's frame sampler (`recorder/src/main.rs`,
`decode_signal`) writes each new (type, sequence) as a `CVEVENT` with the capture time; that time is the
video-side anchor of the moment (architecture 5.2). Payload is 4 bits, a marker, not a data channel.

| Type | Moment | Payload |
| --- | --- | --- |
| 1 | world enter | 0 |
| 2 | quest accepted | quest id % 16 |
| 3 | quest turned in | quest id % 16 |
| 4 | encounter start | encounter id % 16 |
| 5 | encounter end | encounter id % 16 |
| 6 | level up | level % 16 |
| 7 | fight start (every fight, not only encounters) | fight seq % 16 (`combat.fights[].id`) |
| 8 | fight end | 1 kill, 2 wipe, 3 death, 4 fled |
| 9 | player death | level % 16 |
| 10 | rare or better pickup | quality rank 3 to 6 |
| 11 | zone change | 0 |
| 12 | addon session record started | last hex digit of the session id |
