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
Data per character, always (#23): everything that belongs to one character lives in `characters[guid]`; the only
account-wide areas are `settings`, `debug`, the session map and the session-stamped rows. A file written before
0.9.30 keeps its old `character` block and `loot.gold` once, untouched, as `characterLegacy` (schema stays 2).
A row without its session never uploads, so none is kept (#17): the load drops loot rows with no `s` (the rows
from before schema 2), `/eb export` closes the session and opens a new one at once, and `/eb wipe` removes the
fights, loot rows and events of the sessions it clears and opens a new session when one was running.

| key | type | notes |
| --- | --- | --- |
| `schema` | int | 2 |
| `settings` | object | UI prefs only: `emitCorner, autoSave, statSample, flagMute{}, winPos{}, winScale, minimapAngle, welcomed, lootToast, flagScale (1.0 to 1.5), flagPos{point,x,y}, onboarded, winSize{w,h}`. From 0.9.19 the flag cannot be hidden or faded (desktop #90): an older `flagHidden` or `flagAlpha` is dropped on load. Diagnostics, not settings: `blocked[]` (0.9.22, the last 10 `ADDON_ACTION_BLOCKED` / `ADDON_ACTION_FORBIDDEN` the client raised, `{ t, kind, addon, func, combat, stack }`) and `selftest` (0.9.24, the client self-test, below) |
| `debug` | object or nil | diagnostics: `errors[]` (the last 50 Lua errors the client raised, any addon's, `{ at, err, stack?, n?, last? }`; from 0.9.23 a repeat of the row before it counts up in `n` and `last` instead of adding a row), `snapshot` (`/eb debug`) |
| `sessions` | map id -> session | HOME. One record per login -> logout (a `/reload` resumes it: PLAYER_LOGOUT, which a reload also fires, writes `endedEpoch` and `endedBy = "logout"` into the save file, and the reload clears them again and adds a RESUME row; a real login leaves them; everbuff-wow-addon #14, 0.9.20): identity (`player, realm, class, guild, build, flavor, addonVersion`), `surname?` (the second name of a WoW Forever character, "Hammershield" for Hart Hammershield; from 0.9.17, absent where the client shows no surname; everbuff-backend #85), `guid` (player GUID), `schema` (4, the session record's own version), `project` (`WOW_PROJECT_ID`), `startedEpoch`, `startedLocal`, `startedMono` (the client's `GetTime()` at the start), `endedEpoch?`, `endedLocal?`, `endedMono?`, `endedBy?` (`"logout"`, written at PLAYER_LOGOUT, which a /reload also fires; absent on a session `/eb export` closed), `recovered?` (closed on the next login after a crash), `level0 -> level`, `context`, `logging`, TAB-delimited `segments[]` (Segments.lua beacon), live counters `xp, gained, spent, kills, deaths, fights, items, dungeons`, and `gold?` (0.9.23, everbuff-backend #46): this session's own gold ledger in copper, `{ gained, spent, looted, sold, quests, auctionSales, mail, repairs, vendor, training, flights, auctions, mailSpent, other }`, the keys of the character's `gold` ledger (`characters[guid].gold`) without `balance`, every key present from the session's start and credited at the same moment as the lifetime totals. Absent on a session that began before 0.9.23 (a /reload into 0.9.23 does not add a partial one) |
| `active` | id or nil | the session in progress |
| `combat` | object | COMBAT. `fights[]` (below; oldest first, capped at 1000; at the cap an uploaded fight goes first, an unread one only as a last resort and said in chat, everbuff-business #38), `fightSeq`, `uploadedThrough?`, `lastAck? { at, through?, fights, source }` |
| `loot` | object | LOOT. `log[]` = every pickup, item rows and coin rows (below; capped at 2000); item row `q` is the 8-hex quality color (`ff9d9d9d` poor .. `ffe6cc80` artifact), read from the link's `|cff` color or its `|cnIQ<n>:` named color (11.0+ and Forever), else from `C_Item.GetItemQualityByID`; white rows with an id are backfilled on login (0.8.2); the gold totals moved to `characters[guid].gold` (0.9.30, #23); `history`, `reserves` reserved for raid loot council; `ah` (0.9.0) `{ posted[] { s, t, item, id, icon, count, bid, buyout, unit, hours, kind }, bought[] { s, t, item, id, count, price, unit, auctionId, seller, kind }, sold[] { s, t, item, buyer, bid, buyout, deposit, cut, net }, returned[] { s, t, item, id, count, reason } }` in copper, from the auction house hooks and the mail invoices |
| `characters` | map GUID -> block | CHARACTER, one block per character (0.9.30, everbuff-wow-addon #23, approved 2026-10-04, option A). The key is the player GUID (`UnitGUID("player")`, the same value as the session records' `guid`); the addon writes only the block of the character logged in, and a GUID the client hides or has not given yet writes nothing. Each block: `name`, `realm` (when the block was created); `crafts[]` `{ s, t, item, id, icon, count, prof, zone, x, y }` and `recipes[]` `{ s, t, name, prof }` (0.9.0); `xp { cur, max, rested, gained, fromQuests, fromKills, last, lastMax }`, `played { total, level, atEpoch }`, `playedAtLevel { level -> seconds }`, `professions { name -> { rank, max } }`, `reputation { faction -> { standing, label } }`, `durability { pct, at }`, `ilvl`, `seenZones { zone -> epoch }`, `itemUses { name -> count }` (the client's internal all-caps effects such as LOGINEFFECT are not counted, 0.9.3), `flightTime` (seconds on taxis), `lockouts[] { name, id, resetAt (epoch), difficulty, raid?, players, bosses, down, extended? }`, `gold` totals `{ balance, gained, spent, looted, sold, quests, auctionSales, mail, repairs, vendor, training, flights, auctions, mailSpent, other }` in copper (`quests`, 0.9.3: a quest's money reward, matched to QUEST_TURNED_IN in either order within 3 s, exact amount only), `inInstance?` (the DUNGEON / DUNGEONLEAVE dedupe state) |
| `characterLegacy` | object or nil | the account-wide `character` block of a file written before 0.9.30, with the old `loot.gold` ledger as its `gold`. It mixes every character of the account, so it is kept once as it was, never written again and never attributed to a character; the backend ignores it. Absent on a file that never had the old block |
| `story` | object | the feed behind Home. `events[]` (below; capped at 500), `rep[]` (0.9.10: every reputation gain `{ t, s, faction, amount, src?, zone?, sub?, map?, x?, y? }`, `src` is "Quest: <name>" when a quest was turned in within 5 s or "Kill: <name>" after a kill; capped at 2000) (`inInstance` moved to the character block, 0.9.30) |

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
| `startMono`, `endMono` | float | the client's `GetTime()` at the pull and at the end; `duration` is their difference |
| `startLocalHi`, `endLocalHi` | float | fractional local wall-clock from a one-time time()/GetTime() calibration: **video anchor** |
| `duration` | float | seconds |
| `zone` | string | `GetRealZoneText` at pull |
| `map`, `x`, `y` | int, float, float | map id + 0..1 coordinates at the pull. Never joined into a string: `zone` is the Location column, `x`/`y` the Coords column, so the backend indexes them as numbers |
| `level` | int | player level |
| `spec` | string or nil | specialization (retail and WoW Forever) or the talent tab with most points (Classic; nil while no point is spent). WoW Forever has no global `GetSpecialization`; it is read from `C_SpecializationInfo` (0.9.23; before, neither `spec` nor `talents` was written on Forever). A client that has `GetSpecialization` but answers nothing falls through to the talent tabs (0.9.3) |
| `instanceType`, `difficultyID`, `instanceMapID` | string, int, int | from `GetInstanceInfo` |
| `encounterID` | int or nil | numeric id from ENCOUNTER_START: joins to the log file's ENCOUNTER_START line |
| `bossName` | string or nil | encounter name |
| `foes` | array of string | mobs faced (names may be missing on the Secret-Values client) |
| `outcome` | `kill` / `wipe` / `death` / `fled` or nil | `fled` = left combat with no foe; nil on an `interrupted` fight whose result was not known yet |
| `interrupted` | string or nil | `"logout"` (0.9.23, #18): the fight was still running at a /reload or a logout (PLAYER_LOGOUT fires on both) and is stored as far as it got; the end of that combat after a reload is not recorded |
| `group` | array or nil | `{ name, class, race, level, unit, me, deadT?, deaths? }` at pull (nil when solo); `deadT` = seconds into the fight that member first died; `deaths[]` (0.9.3) = every death in seconds, so a member resurrected and killed again dies twice |
| `talents` | string or nil | Classic: talent points per tree at the pull, e.g. `"31/20/0"` (order = talent tabs). Retail / Midnight: the game's talent import string (loadout code) |
| `uses` | array or nil | items used during the fight: `{ t (s into fight), name, sid (spell id), icon }`; a cast that is not a known spell |
| `memberDeaths` | int or nil | how many groupmate deaths happened in this fight, a second death after a resurrection included (your own death is `outcome = "death"`) |
| `auras` | array | player buff/debuff timeline, see below |
| `memberAuras` | map name -> array | per party member (party-sized groups only, not raids) |
| `enemies` | array | `{ name, guid?, firstT, auras[] }` (guid only when not secret; same-named mobs merge when it is) |
| `gear` | `{ initial{ slot -> item }, swaps[] }` | item = `{ name, id, icon, quality, enchant?, gems? }`; `enchant` (enchant id) and `gems[]` (gem item ids) come from the link's item string and are left out when empty (0.9.3); swap = `{ t, slot, name, from, to }` |
| `stats` | array | readable character snapshots `{ t, level, ilvl, hp, mana, prim[5], ap, rap, crit, spellCrit, haste, mastery, hit, spellPower, weapon{}, armor, defense, dodge, parry, block, resist{} }`; mostly absent on the Secret-Values client |
| `uploaded` | bool | reserved for the ack channel |
| `auraHidden`, `auraBlind` | int or nil | diagnostics: aura reads with a hidden name / scans skipped as unreadable during this fight |

**Aura entry**: `{ t, gain, name, icon, debuff, inst?, sid?, atPull }`. `inst` (aura instance id) is the identity
when present; `name` may be nil if the client hid it and no spell id was readable (show as unknown).
The recorder skips scans the client returns as unreadable (see `auraBlind`), so the active set is
carried across those windows rather than recorded as lost. `t` is seconds since pull; `gain=false` is a loss;
`atPull=true` marks the seed set. Replay in order to reconstruct the active set at any `t`.

## Event log entry

`{ t (server epoch), s (session id), kind, text, combat?, foe?, prof?, craft?, crafted?, standing?, guid?, zone?, sub?, map?, x?, y?, downtime?, shown?, duration? }`
(`duration`, 0.9.27: on FLIGHTTRIP, the seconds on the taxi to a tenth, the per-trip value behind the catalog's T-2 and T-5; the text keeps the rounded "(2m 38s)". `characters[guid].flightTime` is the character's lifetime sum.)
(One row per fact, 0.9.27, #11: a recipe learned is one RECIPE row although WoW Forever both prints the system line and fires `NEW_RECIPE_LEARNED` for it, and a quest reward choice is one REWARD row per reward panel although the client can call `GetQuestReward` twice for one turn-in. Both were seen twice in the save file of 2026-10-02.)
(`shown`, 0.9.5: the client's `GetTime()` in seconds with milliseconds when the notification for this row reached the screen; absent when it was quiet, muted, hidden or dropped from the queue. With the session's `startedMono` it is the addon side of an alignment anchor, matched to the desktop's OCR of the same notification, everbuff-desktop #72. `downtime` is stamped on a DEATH row once you are back on your feet: seconds from death to revive, the corpse run; `durLoss` is the gear durability percentage lost across that death.)
(`x`,`y` are 0..1 map fractions.) Kinds: `LEVELUP ZONE FIRSTZONE DUNGEON DUNGEONLEAVE QUESTACCEPT QUESTDONE
REWARD BOSS KILL WIPE DEATH ALIVE SKILLUP DISCOVERY FLIGHT FLIGHTTRIP LOOT ACHIEV SPELL REP ROSTERJOIN
ROSTERLEAVE BROKEN COLLECT PROFTIER RECIPE UPGRADE`. Only rare+ LOOT lands here (all loot is in `loot.log`).

### Town visits and the chat log (everbuff-business #39, approved 2026-09-29, shipped in 0.9.13)

- Visit events: one row per visit, written when the window closes: `{ t (opened), s, kind, closed, zone, sub?, map?, x?, y? }` plus
  `AUCTION` (`searches`, `posts`, `bids`, `buys`; the trades stay in `loot.ah`), `MAIL` (`items`, `money`; the rows stay in `loot`),
  `VENDOR` (`sold`, `bought`, `repair`; `sold` counts the stacks sold, by hand or by the client's "sell all junk" call, also when another addon makes the sale in its own MERCHANT_SHOW handler before the visit opens, 0.9.28, #22; from 0.9.29 a stack counts once the server has taken it from the bags, so a stack sold by hand after a sell-all call counts once and a refused sale not at all), `BANK` (no extra fields) and `TRAINER` (`learned`). They count as gameplay for V5.
- Chat logging guardian: the addon keeps `LoggingChat(true)` on, with the same guardian as advanced combat logging,
  so WoW writes `Logs/WoWChatLog.txt` continuously. The desktop uploads only its system lines.

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

## Client self-test (`settings.selftest`, 0.9.24, everbuff-business #45 layer L5)

At the first world entry on a client build or addon version it has not recorded, the addon checks everything it
takes from the client: the functions, values and events in `Everbuff/Deps.lua` (generated from the source by
`tools/deps.lua`; `luajit tools/deps.lua --json` prints the same list for the L1 API diff), that `issecretvalue` exists
and answers false for plain values, and that none of its event frames holds an event the client forbids
(`COMBAT_LOG_EVENT_UNFILTERED` on WoW Forever). One record, replaced on the next new build:

| field | type | notes |
| --- | --- | --- |
| `build` | string | `GetBuildInfo` version and build, `"1.60.1.70170"` |
| `interface` | int | the interface number `GetBuildInfo` reports |
| `addon` | string | the addon version that ran the check |
| `at` | epoch | server time of the check |
| `ok` | bool | true when `missing` and `forbidden` are empty and the check ran to the end |
| `missing[]` | string | names that changed: a required dependency that is gone, a guarded one the previous record had (on another build, by the same addon version), an event the client no longer knows, or `issecretvalue` |
| `forbidden[]` | string | forbidden events one of the addon's frames has registered |
| `absent[]` | string | guarded dependencies this client lacks (the baseline for the next build; on the first record ever, and on the first record of a new addon version, these are not failures) |
| `secrets` | bool | `issecretvalue` exists and behaves |
| `events` | string | `checked` (`C_EventUtils.IsEventValid`), or `unchecked` when the client cannot say |
| `skipped?` | string | `classic`: a Classic client is not checked (WoW Forever only) |
| `error?` | string | the check itself failed; `ok` is false and nothing is said in chat |

Silent when `ok`. When it fails the player sees exactly one chat line (founder decision 3, option B):
`everbuff.gg: this WoW build changed <first item> (and N more); recording continues.` The backend's live canary
(L4) reads the record from the save file.

## Not available on this client, or different by design (#11)

| Fact | Why | What the product does |
| --- | --- | --- |
| Party gear, enchants and gems of other players | This client never writes `COMBATANT_INFO` to the combat log, and the addon reads gear only for the player (inspecting others needs a click per member) | Party gear cells show NOT IN LOG; the player's own gear carries `enchant` and `gems` |
| The kill count differs from the log's `PARTY_KILL` | By design: the addon counts kills the player's fights recorded; `PARTY_KILL` also counts every killing blow of party members and pets, and mobs killed outside a recorded fight. 26 Sep evening: addon 103, log 123 | G3 settled "kills from the addon" (catalog section 8 item 6); the log count is not shown as kills |
| Enemy names and GUIDs, aura fields, combat stats on the Secret-Values clients | The client hides them (see Invariants) | Guarded reads; missing values show as not recorded |
| The quest reward choice when the panel is closed before the hook runs | The client can close the reward panel before the `GetQuestReward` hook reads it | 0.9.3 reads the choices when the panel opens (QUEST_COMPLETE) and uses them when the choice is confirmed |

## Kept for the addon's own panes, not read by the backend (ADDON-8, #11)

These four lists back the addon's in-game panes and are uploaded with the save file like everything else, archived
in `save_versions` (A20), but ingest does not read them. Nothing in the approved question catalog reads them: the web
takes the same facts from rows it does ingest. Measured on the save file of 2026-10-02 (2,062,707 bytes as data):

| List | Rows | Size | Pane in game | What the backend reads instead |
| --- | ---: | ---: | --- | --- |
| `story.rep` | 76 | 11.5 KB | Progress, reputation history per faction | `story.events` REP (tier reached) and `characters[guid].reputation` (standings, `character_snapshots.reputation`) |
| `loot.ah` | 24 | 2.7 KB | Loot, Auctions | `loot.log` mail rows (Auction sale, Auction won, Auction returned, with `mail{}`), the AUCTION visit and the gold ledger (`auctions`, `auctionSales`) |
| `characters[guid].crafts` | 0 | 0 KB | Character, Crafting | `story.events` SKILLUP with `craft` and `crafted` |
| `characters[guid].recipes` | 2 | 0.1 KB | Character, Crafting | `story.events` RECIPE |

Together 14.4 KB, 0.7 % of the file; the fights are 1.47 MB (71 %). Dropping them would remove in-game panes and save
almost nothing, so they stay. Reading them on the backend (per-gain reputation, auction postings) needs a place in
the data model and a catalog question first, and goes through a gate.

## Correlating to the combat-log file and video

1. Window: `startLocal .. startLocal + duration` (local time, like the log) or `startLocalHi` for frames.
2. Encounters: match `encounterID` to the log's `ENCOUNTER_START` line.
3. Identity: `player`/`realm`; enemies by `guid` when present.
4. Ack (once the channel exists): mark `uploaded=true` per `uid`, or set `uploadedThrough`; the addon
   prunes on next load (`pruneUploaded`). The addon warns in chat when history is within 25 of the cap.

## Upload ack channel (desktop -> addon)

Two inbound paths, both consumed by `ns.applyAck` on the addon side:

1. **Companion SavedVariable, automatic.** While NO WoW client is running, the desktop replaces the top-level
   `EverbuffAck` statement in the addon's own save file `WTF/Account/<account>/SavedVariables/EverbuffJournal.lua`
   (WoW reads an addon's SavedVariables only from the file named after the addon; a separate `EverbuffAck.lua` is
   never read, #5) with
   `EverbuffAck = { uids = { ["<fight uid>"] = true, ... }, through = <server epoch> }`. The rest of the file is
   kept byte for byte and keeps its write time.
   On the next `ADDON_LOADED` the addon marks fights with those uids, and every fight that started at or before
   `through`, as uploaded and prunes them; loot rows, events and finished sessions with `t <= through` are pruned
   too. The addon then empties `uids` and stamps `applied`, so the file never grows and is never applied twice.
   Writing while the game runs is useless: WoW rewrites SavedVariables wholesale on `/reload` and logout.
2. **Paste code, manual.** The desktop shows `EB-ACK-<epoch>` (optionally `:<uid>,<uid>,...`) after an upload;
   the player pastes it in Settings > Data or types `/eb ack <code>`. Same effect, applied immediately.

`combat.lastAck` records the last applied ack; Settings > Capture shows "Desktop sync: last synced ...".
Ack on `fight.uid` (globally unique), never on `fight.id`.
