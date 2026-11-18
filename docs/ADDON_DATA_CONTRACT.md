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
account-wide areas are `settings`, `debug`, the session map and the session-stamped rows. The save has no
`character`, `loot.gold` or `characterLegacy` key (0.9.33): the old account-wide block and gold ledger mixed every
character of the account, so the load deletes them and the `characterLegacy` copy that 0.9.30 and 0.9.31 kept; the
addon never reads or attributes them (founder rule, 2026-10-05, #23: data that is invalid or does not fit the current system is
discarded). Each character's block starts from what that character writes (schema stays 2).
The panel shows the logged-in character only (0.9.32): every pane lists the sessions whose `guid` is the player's
GUID and the rows of those sessions (a fight names its session in `session`, every other row in `s`). This is a
view: the file keeps every character's sessions and rows, and the desktop and the backend read all of them as before.
A row without its session never uploads, so none is kept (#17): the load drops loot rows with no `s` (the rows
from before schema 2), `/eb export` closes the session and opens a new one at once, and `/eb wipe` removes the
fights, loot rows and events of the sessions it clears and opens a new session when one was running.

| key | type | notes |
| --- | --- | --- |
| `schema` | int | 2 |
| `settings` | object | UI prefs only: `emitCorner, autoSave, statSample, flagMute{}, winPos{}, winScale, minimapAngle, welcomed, lootToast, flagScale (1.0 to 1.5), flagPos{point,x,y}, onboarded, winSize{w,h}`. From 0.9.19 the flag cannot be hidden or faded (desktop #90): an older `flagHidden` or `flagAlpha` is dropped on load. Diagnostics, not settings: `blocked[]` (0.9.22, the last 10 `ADDON_ACTION_BLOCKED` / `ADDON_ACTION_FORBIDDEN` the client raised, `{ t, kind, addon, func, combat, stack }`) and `selftest` (0.9.24, the client self-test, below). `gold?` (0.9.44, everbuff-wow-addon #43, created on first use): the day base and week anchor of the gold history and the gold display settings, see "Gold history" below |
| `debug` | object or nil | diagnostics: `errors[]` (the last 50 Lua errors the client raised, any addon's, `{ at, err, stack?, n?, last? }`; from 0.9.23 a repeat of the row before it counts up in `n` and `last` instead of adding a row), `snapshot` (`/eb debug`) |
| `sessions` | map id -> session | HOME. One record per login -> logout (a `/reload` resumes it: PLAYER_LOGOUT, which a reload also fires, writes `endedEpoch` and `endedBy = "logout"` into the save file, and the reload clears them again and adds a RESUME row; a real login leaves them; everbuff-wow-addon #14, 0.9.20): identity (`player, realm, class, guild, build, flavor, addonVersion`), `surname?` (the second name of a WoW Forever character, "Hammershield" for Hart Hammershield; from 0.9.17, absent where the client shows no surname; everbuff-backend #85), `guid` (player GUID), `schema` (4, the session record's own version), `project` (`WOW_PROJECT_ID`), `startedEpoch`, `startedLocal`, `startedMono` (the client's `GetTime()` at the start), `endedEpoch?`, `endedLocal?`, `endedMono?`, `endedBy?` (`"logout"`, written at PLAYER_LOGOUT, which a /reload also fires; absent on a session `/eb export` closed), `recovered?` (closed on the next login after a crash), `level0 -> level`, `context`, `logging`, TAB-delimited `segments[]` (Segments.lua beacon), live counters `xp, gained, spent, kills, deaths, fights, items, dungeons`, and `gold?` (0.9.23, everbuff-backend #46): this session's own gold ledger in copper, `{ gained, spent, looted, sold, quests, auctionSales, mail, repairs, vendor, training, flights, auctions, mailSpent, other, trade, tradeSpent, away, awayIn, awayOut }` (`trade` to `awayOut` from 0.9.37, everbuff-wow-addon #31; a session resumed by a /reload into 0.9.37 gets them on first use), the keys of the character's `gold` ledger (`characters[guid].gold`) without `balance`, every key present from the session's start and credited at the same moment as the lifetime totals. Absent on a session that began before 0.9.23 (a /reload into 0.9.23 does not add a partial one). `goldLog?`, `trades?` and `goldLogDropped?` (0.9.40, everbuff-wow-addon #36): the gold journal, below; absent on a session that began before 0.9.40 (a /reload into 0.9.40 does not add a partial one) |
| `active` | id or nil | the session in progress |
| `combat` | object | COMBAT. `fights[]` (below; oldest first, capped at 5000 since 0.9.38, 1000 before (founder, 2026-11-11); at the cap an uploaded fight goes first, an unread one only as a last resort, counted and said in chat on the first loss and every 50th, everbuff-business #38), `fightSeq`, `uploadedThrough?`, `lastAck? { at, through?, fights, sessions?, source }` |
| `loot` | object | LOOT. `log[]` = every pickup, item rows and coin rows (below; capped at 2000); item row `q` is the 8-hex quality color (`ff9d9d9d` poor .. `ffe6cc80` artifact), read from the link's `|cff` color or its `|cnIQ<n>:` named color (11.0+ and Forever), else from `C_Item.GetItemQualityByID`; white rows with an id are backfilled on login (0.8.2); the gold totals live in `characters[guid].gold` (0.9.30, #23; the old account-wide `loot.gold` is deleted on load, 0.9.33); `history`, `reserves` reserved for raid loot council; `ah` (0.9.0) `{ posted[] { s, t, item, id, icon, count, bid, buyout, unit, hours, kind }, bought[] { s, t, item, id, count, price, unit, auctionId, seller, kind }, sold[] { s, t, item, buyer, bid, buyout, deposit, cut, net }, returned[] { s, t, item, id, count, reason } }` in copper, from the auction house hooks and the mail invoices |
| `characters` | map GUID -> block | CHARACTER, one block per character (0.9.30, everbuff-wow-addon #23, approved 2026-10-04, option A). The key is the player GUID (`UnitGUID("player")`, the same value as the session records' `guid`); the addon writes only the block of the character logged in, and a GUID the client hides or has not given yet writes nothing. Each block: `name`, `realm` (written when the block is created and, from 0.9.44, refreshed at every login); `surname?`, `class?` (class token, `WARRIOR`), `faction?` (`Alliance`, `Horde` or `Neutral`), `level?`, `seen?` (server epoch of the last login, level-up or logout), written from 0.9.44 (#43) at PLAYER_ENTERING_WORLD, PLAYER_LEVEL_UP and PLAYER_LOGOUT, each read tested and protected, a value the client hides leaves the stored one; a block that has none of them is a character not logged in since the update; `goldDays?` and `goldSince?` (0.9.44, the gold history, below; siblings of `gold`, never inside it); `goldRate?` and `goldTimer?` (0.9.45, the rate window and the farm timer, "Gold rate and farm timer" below; siblings of `gold` too); `crafts[]` `{ s, t, item, id, icon, count, prof, zone, x, y }` and `recipes[]` `{ s, t, name, prof }` (0.9.0); `xp { cur, max, rested, gained, fromQuests, fromKills, last, lastMax }`, `played { total, level, atEpoch }`, `playedAtLevel { level -> seconds }`, `professions { name -> { rank, max } }`, `reputation { faction -> { standing, label } }`, `durability { pct, at }`, `ilvl`, `seenZones { zone -> epoch }`, `itemUses { name -> count }` (the client's internal all-caps effects such as LOGINEFFECT are not counted, 0.9.3), `flightTime` (seconds on taxis), `lockouts[] { name, id, resetAt (epoch), difficulty, raid?, players, bosses, down, extended? }`, `gold` totals `{ balance, gained, spent, looted, sold, quests, auctionSales, mail, repairs, vendor, training, flights, auctions, mailSpent, other, trade, tradeSpent, away, awayIn, awayOut }` in copper (`quests`, 0.9.3: a quest's money reward, matched to QUEST_TURNED_IN in either order within 3 s, exact amount only; 0.9.37, everbuff-wow-addon #31: `trade` and `tradeSpent` are coin received and given while the trade window was open or closed under 3 s ago, part of `gained` and `spent`; `away` is gold that changed while the addon did not see it, signed, booked at the first read of a load as the purse minus the `balance` the save file kept, with its size in `awayIn` or `awayOut`, never part of `gained` or `spent`, so `balance = gained - spent + away` holds from the first 0.9.37 load on; from 0.9.44 (#43) a 0 read at load with gold saved is not trusted until a PLAYER_MONEY brings a read that is not 0 or 15 s have passed (read again after 3 s and 15 s), and when a 0 was booked and the very next read brings the saved balance back, the booking is taken back by a second `away` row the other way, taken out of `awayIn` or `awayOut` again, so `away`, `awayIn` and `awayOut` end where they were; while the GUID is not known no baseline is seeded, so the comparison with the saved balance is still made; a block without a `balance` is seeded silently; "Clear loot" in Settings no longer zeroes `looted`), `inInstance?` (the DUNGEON / DUNGEONLEAVE dedupe state) |
| `story` | object | the feed behind Home. `events[]` (below; capped at 500), `rep[]` (0.9.10: every reputation gain `{ t, s, faction, amount, src?, zone?, sub?, map?, x?, y? }`, `src` is "Quest: <name>" when a quest was turned in within 5 s or "Kill: <name>" after a kill; capped at 2000) (`inInstance` moved to the character block, 0.9.30) |

## Gold journal (session `goldLog`, `trades`, 0.9.40, everbuff-wow-addon #36, option A, approved 2026-11-17)

Written into the running session record at the same moment as the ledger credit (`session.gold`). All fields are
optional; nothing is drawn in game, nothing goes to chat, no new story kind.

`goldLog[]`: one TAB-separated string per purse change, `mono TAB delta TAB source TAB balance TAB ref`.

| Field | Meaning |
| --- | --- |
| `mono` | `GetTime()` at the change, one decimal (`"831042.5"`) |
| `delta` | signed copper: income positive, spending negative, `away` signed |
| `source` | the ledger key credited. Income: `looted`, `quests`, `sold`, `auctionSales`, `mail`, `trade`, `unexplained` (income no source claimed; counted in `gained` only). Spending: `repairs`, `vendor`, `training`, `flights`, `auctions`, `mailSpent`, `tradeSpent`, `other`. And `away`. Never `gained`, `spent`, `awayIn`, `awayOut` |
| `balance` | `GetMoney()` after the change |
| `ref` | `k=v` pairs joined by `;`, empty when nothing is known. TAB, `;`, `=`, `\|` and line breaks are stripped from values; a value the client hides is left out |

`ref` keys, in this order when present: `item` (item id), `n` (count), `unit` (the item's vendor sell price per unit,
`GetItemInfo`'s 11th value, on `sold` rows), `npc` (the merchant on `sold`, `vendor` and `repairs`, the trainer on
`training`, the flight master on `flights`, read from the `NPC` unit when the window opened), `sender`, `partner`,
`guild` (the trade partner's guild, `GetGuildInfo("NPC")`), `rel`, `cod` (copper, 0 when none), `trade` (1-based
index into this session's `trades[]`), `quest` (quest id), `mailWaiting` (1 when `HasNewMail()` was true at the first
read of the load, on `away` rows), `x` (rows merged past the cap), `gap` (0.9.44, #43: on `away` rows, the seconds
since the character was last seen, `characters[guid].seen` before this load; absent when that is not known).

Which source an income is, in this order (0.9.44, #43; the order matters because day rows are kept): a quest reward
of exactly this amount (QUEST_TURNED_IN within 3 s), an open trade (or one closed under 3 s ago), a sale asked for at
a merchant in the last 5 s, a mail taken in the last 3 s, the loot window (3 s from LOOT_OPENED), any gain while a
merchant window is open, any gain while the mailbox is open, else `unexplained`. Before 0.9.44 the loot window came
first, so a quest reward or a sale within 3 s of a corpse loot was booked as `looted`. Spending is unchanged.

| Source | ref |
| --- | --- |
| `sold` | `item, n, unit, npc`; the item is the stack the player sold (a right click, or one of the junk stacks of "sell all junk") whose `unit * n` equals the delta, else the oldest sale of the last 5 s; a sale the addon did not see asked for carries `npc` only. A delta above `unit * n` is a sale above the vendor price |
| `vendor` | `item, n, npc` (`BuyMerchantItem`, `BuybackItem`) |
| `repairs`, `training`, `flights` | `npc` |
| `quests` | `quest`. An income first seen with no source is written `unexplained` and rewritten in place to `quests` when QUEST_TURNED_IN names that amount within 3 s (one row per purse change either way) |
| `mail`, `auctionSales` | `sender, rel, cod` of the mail the coin came from (absent when the mailbox was open but no take was seen) |
| `mailSpent` | `sender, rel, cod` for a COD payment (the item taken in the 3 s before); empty for postage |
| `trade`, `tradeSpent` | `partner, guild?, rel, trade` |
| `away` | `mailWaiting` when true, `gap` when known. From 0.9.44 a 0 the client answered at login and then corrected is two `away` rows that cancel (the booking and its taking back), both kept |
| `looted`, `auctions`, `other`, `unexplained` | empty |

`rel`, who the player is to this character: `alt` (a `characters[guid]` block of this save file with that `name` on the
same realm; a `Name-Realm` name compares its own realm), `guild` (the guild roster, cached on GUILD_ROSTER_UPDATE),
`friend` (the friends list, cached on FRIENDLIST_UPDATE, or `C_FriendList.IsFriend` / `GetFriendInfo`), `stranger`,
and on mail only `system` (auction house invoices and subjects, and any mail the client says cannot be answered).

Cap: 4000 rows per session. Past it a `looted`, `sold` or `vendor` row with no `partner` or `sender` merges into the
row before it when that row has the same source: deltas summed, the newest `mono` and `balance`, the `ref` keys both
rows share kept (`n` summed when the item is the same), `x` = rows merged. Anything else past the cap is counted in
`goldLogDropped` (0 from the session's start), except `trade`, `tradeSpent`, `mail`, `mailSpent`, `auctionSales`,
`away` and `unexplained` rows, which are always written. While nothing is dropped, each `balance` minus the one
before is that row's `delta`, and the rows of each source sum to `session.gold[source]`.

`trades[]`: `{ t (server epoch), mono, partner, guild?, rel, gaveMoney, gotMoney, gave = { "id:count", ... }, got = {
"id:count", ... } }`, copper. Both sides are read from the trade window (`GetPlayerTradeMoney`, `GetTargetTradeMoney`,
`GetTradePlayerItemLink/Info`, `GetTradeTargetItemLink/Info`, slots 1 to 6) on every TRADE_MONEY_CHANGED,
TRADE_PLAYER_ITEM_CHANGED, TRADE_TARGET_ITEM_CHANGED and TRADE_ACCEPT_UPDATE; the last snapshot is kept (an empty
read as the client clears the window never replaces it). An item the client names without a link is `"0:count"`.
A trade is written once it completed: a purse change while the window is open or under 3 s after it closed, or the
client's `ERR_TRADE_COMPLETE` (UI_INFO_MESSAGE), so an items-only trade is written too. When gold moved but no
snapshot was taken the money comes from the purse change. A cancelled trade (closed with nothing moved, or
`ERR_TRADE_CANCELLED`) is not written. The `trade` ref of the gold row is the entry's index.

## Gold history (`characters[guid].goldDays`, `goldSince`, `settings.gold`, 0.9.44, everbuff-wow-addon #43)

Approved 2026-11-18 with every recommended decision of the plan in #43. All keys are optional and created on first
use; there is no schema bump. The backend ignores these keys until its own gate: no `sessions.gold` key changes, and
the new keys ride along in the uploaded save file.

`characters[guid].goldDays`: map `dayKey -> row`, written at the moment of the ledger credit, into the block of the
character logged in and no other (the rule of the `characters` row above). Nothing is reconstructed: the history
starts at the first purse change, or the first minute played, after the update.

| Field | Meaning |
| --- | --- |
| `dayKey` | `'YYYYMMDD'`: the UTC date of the day's start, `date('!%Y%m%d', dayStart)`, so the PC's time zone cannot move it. `dayStart = floor((now - offset) / 86400) * 86400 + offset` with the stored `settings.gold.dayBase.offset` |
| `g`, `s` | copper gained and spent on the day (the raw purse flow, as `gained` and `spent` of the ledger) |
| `o`, `c` | the balance before the day's first change and after its last, written by a purse change only. Absent on a row with no purse change (a day that was only played: the 10 s ticker adds `t` and invents no balance) and on a row that never saw a balance. A reader takes the close of the last row before it (`Gold.period` does) |
| `t` | active seconds: every 10 s the time since the last tick, capped at 10 s, while the character is logged in. From 0.9.45 time away from the keyboard is not counted: the AFK flag is read on PLAYER_FLAGS_CHANGED and at login, and a missing, blocked or hidden answer counts as active |
| `n` | purse changes on the day. A change while away counts as one |
| source keys | the non-zero ledger sources by their ledger name: `looted`, `quests`, `sold`, `auctionSales`, `mail`, `trade`, `unexplained`, `repairs`, `vendor`, `training`, `flights`, `auctions`, `mailSpent`, `tradeSpent`, `other`. A source with 0 is absent |
| `unexplained` | income no source claimed, credited on the row itself (the session and lifetime ledgers still derive it). A quest that claims it within 3 s moves it to `quests` on the row of the day the income was booked on, also after a rollover |
| `away` | signed copper that changed while the addon did not see it, written into the day it was discovered on. Neither `g` nor `s`. Absent when 0 |

Every amount is an integer, floored at the write. On every row the income keys sum to `g`, the spend keys sum to `s`,
and, on a row with a purse change, `c - o = g - s + away`; such a row opens on the close of the last row before it
that has one. The rows of a character sum to its lifetime ledger since `goldSince`. `tests/gold_days.lua` holds these
over 10,000 random purse changes.

One purse change is one moment: the clock is read once per change (`Emitter._dayAt`) and every credit of it (the
gained or spent credit, its source, the time a late quest claim moves on) uses that reading, so a change at the
reset second is never split over two rows.

The 0 read at login: with a positive saved balance a 0 is not booked until a non-zero read arrives or 14.5 s have
passed (re-read after 3 s and after 15.5 s). A non-zero read while the 0 waits seeds the baseline (the difference to
the saved balance is `away`), unless something explains it as income (a quest reward of that amount, an open trade,
merchant or mailbox, a mail just taken, a loot window): then the 0 is booked against the saved balance first and the
read is an ordinary gain. A booked 0 is taken back only when the next read of the same load, within 60 s, restores
the saved balance and nothing explains it as income.

`characters[guid].goldSince`: server epoch of the first day row. The Gold pane says "History starts <date>".

Cap: 400 day rows per character (`Gold.DAY_CAP`). No row can reach that age before late 2027 and nothing is dropped
before the fold into month rows exists (planned for 0.9.48), so the cap is not enforced yet. The acknowledgement
prune (`applyAck`) never touches `characters`, so the history outlives the sessions it came from.

`settings.gold` (account-wide, nothing per character is stored in it):

| Key | Meaning |
| --- | --- |
| `dayBase` | `{ kind = "server" or "local", offset, since, changes? }`, written once, so every character's day keys line up when summed. `offset = (GetServerTime() + secs) % 86400` rounded to the nearest 900 s, where `secs` is `C_DateAndTime.GetSecondsUntilDailyReset()` (or the legacy `GetQuestResetTime()`), accepted only as a plain number with `0 < secs <= 86400`. When no valid reading arrives within 30 s of the first credit ever (or by the logout), the base is the PC's midnight and `kind = "local"`; credits before that are held in memory and written once the base is known, on the day they happened. A later reading more than 900 s away appends `{ at, offset }` to `changes` (at most 50); the stored `offset` and every existing key stay |
| `weekAnchor` | server epoch of one weekly reset, written once: `C_DateAndTime.GetWeeklyResetStartTime()`, else now plus `GetSecondsUntilWeeklyReset()`. A week is 7 day keys from it. Without it a week starts on a Monday of the day base |
| `filter` | which characters the Characters view and the tooltip list: `all` (default), `realm`, `faction`, `realmFaction`, relative to the character logged in |
| `hidden` | `{ [guid] = true }`: characters left out of every total ("Hide from totals"). A display setting, never a flag on the character's block; absent when empty |
| `tips` | `false` turns the gold block of the tooltips off (default on) |
| `rateMode` | 0.9.45: what "per hour" means on every surface: `farm` (default), `earned` or `net`, see "Gold rate and farm timer" |
| `icons` | 0.9.45: `true` draws the coin icons instead of the letters g, s and c on the pill, the bar texts and the tooltips (default off) |
| `compact` | 0.9.45: `true` writes amounts from 100,000g as `123.4k` and from 1,000,000g as `1.2M` on the pill and the bar texts (the tenth is floored; default off) |
| `pill` | 0.9.45: the gold pill, `{ on, metrics, label?, corner?, x?, y?, locked?, scale?, alpha?, asked? }`. `on` (default `false`): the pill is on screen. `metrics`: one or two of `balance`, `total`, `session`, `today`, `rate`, `timer`. `label`: each value names itself. `corner`, `x`, `y`: its place as offsets in screen units from the nearest screen corner (`TOPLEFT`, `TOPRIGHT`, `BOTTOMLEFT`, `BOTTOMRIGHT`), written the moment the pill is created and whenever it is moved or pushed back inside the screen or off the flag. `locked`: a drag does not move it. `scale` 0.5 to 2, `alpha` 0.2 to 1. `asked`: the first-run question "Show your gold on screen?" was answered. Created on the first write, never by a read |
| `tip` | 0.9.45: the tooltip block, `{ limit, week, month }`. `limit` 5 to 30 characters listed (default 8), `week` and `month` add a line each (default off). No key turns on the gold block of the flag's tooltip (see "Gold display") |

Never stored: week, month, last 7 and last 30 days, realm and account sums, the total of all characters, shares and
rates. They are sums over the character blocks at read time (`Gold.period`, `Gold.roster`, `Gold.metric` in
`Everbuff/Economy.lua`), so hiding a character corrects every figure at once. A realm or account sum is over the
characters its total counts and no others: not hidden, and seen within 90 days unless the "Not seen in 90 days"
toggle of the Characters view is on. The status line names how many are left out.

Size, measured on `tests/export/EverbuffJournal.lua` (0.9.44): the file grows from 14,656 to 15,234 bytes. The one
day row with two sources is 178 bytes in the save file's layout and each further source adds about 22, so a row is
180 to 250 bytes and 400 rows are 70 to 100 KB per character (the plan estimated 50 KB).

## Gold rate and farm timer (`characters[guid].goldRate`, `goldTimer`, 0.9.45, everbuff-wow-addon #43)

Milestone 2 of the plan approved in #43. Both keys are optional, created on first use, written only into the block
of the character logged in, and ignored by the backend until its own gate. No `sessions.gold` key changes.

`characters[guid].goldRate`: `{ m = { [epochMinute] = { e, s, f, a, x? } }, last }`.

| Field | Meaning |
| --- | --- |
| `epochMinute` | `floor(serverTime / 60)`, a number key. At most 91 buckets: on every write the minutes older than 90 minutes are dropped |
| `e` | earned in that minute, copper: every gain of the purse except `mail` and `auctionSales` (they are added with `gained` and taken out again in the same purse change). A change while away is never in it |
| `s` | spent in that minute, copper |
| `f` | farmed in that minute, copper: `looted` + `sold` + `quests`. A quest that claims an unexplained income within 3 s is added to the minute the income was booked in |
| `x` | optional, only in a minute that had one: the `mail` and `auctionSales` gains of that minute, copper, the amount left out of `e`. It is what makes Net the purse's own net (the NET card's figure) while Farming and Earned stay without mail and auction payouts |
| `a` | active seconds of that minute, at most 60: the 10 s ticker of the day rows, so time away from the keyboard and time logged out are not in it. A credit is booked whether or not the character is away |
| `last` | server epoch of the last write. A write more than 1800 s after it empties `m` first (the window starts over); a read past that gap sees an empty window and changes nothing |

A rate is `sum * 3600 / active seconds` over the buckets of the last 90 minutes, rounded half away from zero:
Farming sums `f`, Earned sums `e`, Net sums `e + x - s` (everything gained minus everything spent). Under 300 active seconds it is shown dimmed with "warming up
m:ss". The label always names the definition and the window ("Farming 44g 20s/h · last 37 min"). The window is the
character's own: a second character starts its own, a /reload and a relog inside 30 minutes continue it.
`tests/gold_rate.lua` holds these.

`characters[guid].goldTimer`: `{ at, ledger }`. `at` is the server epoch the farm timer was started (`/eb gold
timer`, or "Start farm timer" in the menu), `ledger` a copy of every key of `characters[guid].gold` except
`balance` at that moment. The timer's figures are the lifetime ledger minus the snapshot over the wall time since
`at`, by the per hour setting (Farming: `looted + sold + quests`; Earned: `gained - mail - auctionSales`; Net:
`gained - spent`). These are the figures the resolver gives for every period (`Gold.metric` ids `farmed`,
`earnedOwn`, `net`, and `byMode` for the one the setting picks; `earned` is always everything gained). It survives
a /reload and a relog, and it is not part of any session record.

Reset gold history (Settings, Gold, More; two clicks) removes `goldDays`, `goldMonths`, `goldRate` and `goldTimer`
of the character logged in and sets `goldSince` to now. `gold` (the lifetime ledger and the balance) is never
reset, because the backend reads it, and no other character's block is touched. "Reset per hour" removes
`goldRate` alone.

Size, measured on `tests/export/EverbuffJournal.lua` (0.9.45): the file grows from 15,234 to 15,597 bytes with a
rate window of two buckets (about 110 bytes a bucket in the save file's layout, so a full window of 91 is about
10 KB per character). The export changed shape by `goldRate` only; the backend's copy of the fixture follows.

## Gold display (0.9.44 and 0.9.45, everbuff-wow-addon #43, decision 5)

The sentence "nothing is drawn in game, nothing goes to chat" above scopes the gold journal of #36. What the addon
draws and says about gold, and nothing else (the pill, the bar texts, the menu and Settings from 0.9.45):

| Surface | When | What |
| --- | --- | --- |
| Loot > Gold pane | the addon window is open | periods by server day, who (character, realm, account), the Days and Characters views. Other characters' names and balances are shown here, and so in recordings |
| Home > Overview, GOLD card | the addon window is open | today's net and today's pace (the day's net over the time played that day, after 5 minutes), and on a second line the total of all characters when more than one is known |
| Minimap button tooltip | while the mouse is over the button | the gold block (at most 18 lines) under the two help lines; it follows the purse while it is open. Off with `settings.gold.tips = false` |
| Chat | only as the direct reply to a typed `/eb gold` (four lines, a fifth while a farm timer runs), `/eb gold chars` (the roster), `/eb gold stats` (0.9.45: today, week and month in, out and net for the character, its realm and the account, three lines) or `/eb gold timer` (0.9.45: starts the farm timer, "Farm timer started.") | never a login summary. These replies also answer in combat: they open, move and change nothing on screen |
| Loot > Gold pane, PER HOUR card | the addon window is open | 0.9.45: for today and the running session of the character logged in, the rolling rate by the per hour setting ("FARMING PER HOUR"), dimmed while it warms up, its window in the status line. Every other period keeps its net over the time played |
| Loot > Gold pane, first-run question | the addon window is open, until answered | 0.9.45 (decision 4): one row above the cards, "Show your gold on screen?" with Yes and No. Yes turns the pill on. Asked once per account (`settings.gold.pill.asked`) |
| Gold pill | only when `settings.gold.pill.on` is true (default off; no frame exists while it is off) | 0.9.45: one line of text, one or two of Balance, Account total, Session net, Today net, Per hour, Farm timer. Its text follows the purse in the frame of the change, in combat too. It is kept inside the screen and at least 8 px clear of the flag and of its notification line at its widest (600 x 40 at the flag's scale, growing inward from the flag's corner; the 600 is the Emitter's own cap on the line, `Emitter.TOAST_MAX_W`), wherever the flag is, and it is placed again when the flag is dragged, snapped to a corner or resized. A new pill sits under the flag's row. Left-click opens Loot > Gold (after the fight when in combat), right-click opens the menu, a drag moves it. In combat nothing about it is moved, resized, scaled, shown or hidden; a text that gets longer than the pill during a fight is cut short inside it until the fight ends |
| Pill and bar text menu | on a right-click, never in combat | 0.9.45: the client's `MenuUtil.CreateContextMenu` when it exists and works (its entries built during the call, or a menu handed back), else the addon's own list frame. The own list closes when what it hangs under is hidden (the window, a Settings page, the pill) and when a fight starts. Never UIDropDownMenu |
| Bar text | only when another addon loaded LibDataBroker-1.1 (it is not embedded, decision 18) | 0.9.45: four data sources registered at PLAYER_LOGIN, "everbuff.gg Balance", "everbuff.gg Account total", "everbuff.gg Today", "everbuff.gg Per hour". Their tooltip is the gold block |
| Pill tooltip | while the mouse is over the pill | 0.9.45: two help lines and the gold block |
| Flag tooltip | never in 0.9.45 | the gold block under the flag's four help lines is built and switched off in code (`Gold.FLAG_TIP = false`); no setting and no control turns it on. The flag is what the desktop app reads, and the taller tooltip ships with the release that carries the desktop's replay of its fixtures (decision 3c) |
| Settings > Gold | the addon window is open | 0.9.45: the controls of `settings.gold`, hidden characters with "Show again", and behind "More" the pill's lock, size and opacity, the tooltip's row count, week and month, and the resets |

A rate on screen is drawn again every 10 s, by one ticker that exists only while the pill shows a rate or the farm
timer, a bar text exists, one of the addon's tooltips is open or the Gold pane is showing.

Nothing is drawn on or beside the flag for a machine to read, and the flag's tooltip is unchanged.

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

`{ t (server epoch), s (session id), kind, text, combat?, foe?, prof?, craft?, crafted?, standing?, guid?, zone?, sub?, map?, x?, y?, downtime?, shown?, duration?, money? }`
(`duration`, 0.9.27: on FLIGHTTRIP, the seconds on the taxi to a tenth, the per-trip value behind the catalog's T-2 and T-5; the text keeps the rounded "(2m 38s)". `characters[guid].flightTime` is the character's lifetime sum.)
(One row per fact, 0.9.27, #11: a recipe learned is one RECIPE row although WoW Forever both prints the system line and fires `NEW_RECIPE_LEARNED` for it, and a quest reward choice is one REWARD row per reward panel although the client can call `GetQuestReward` twice for one turn-in. Both were seen twice in the save file of 2026-10-02.)
(`shown`, 0.9.5: the client's `GetTime()` in seconds with milliseconds when the notification for this row reached the screen; absent when it was quiet, muted, hidden or dropped from the queue. With the session's `startedMono` it is the addon side of an alignment anchor, matched to the desktop's OCR of the same notification, everbuff-desktop #72. `downtime` is stamped on a DEATH row once you are back on your feet: seconds from death to revive, the corpse run; `durLoss` is the gear durability percentage lost across that death.)
(`x`,`y` are 0..1 map fractions.) Kinds: `LEVELUP ZONE FIRSTZONE DUNGEON DUNGEONLEAVE QUESTACCEPT QUESTDONE
REWARD BOSS KILL WIPE DEATH ALIVE SKILLUP DISCOVERY FLIGHT FLIGHTTRIP LOOT ACHIEV SPELL REP ROSTERJOIN
ROSTERLEAVE BROKEN COLLECT PROFTIER RECIPE UPGRADE GOLDAWAY TRADE`. (`money`, 0.9.37, #31: signed copper on GOLDAWAY, gold changed outside the addon's view, and TRADE, coin received or given in one purse change of a trade, whose text names the partner ("Gold elsewhere +5g 65s 70c", "Trade +25s with Kristijan"); both are quiet, never shown in game.) Only rare+ LOOT lands here (all loot is in `loot.log`).

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
`"Mail from <sender>"`, with `mail = { sender, subject, item?, buyer?, seller?, cod?, rel? }` (`rel` from 0.9.40, #36: `alt`, `guild`, `friend`, `stranger` or `system`, as in the gold journal). Location is the mailbox.
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
| `instance?` | object | 0.9.41: the client's raw answers at the last dungeon check (world entry and zone change): `zone`, `name`, `type`, `diff`, `map` (GetInstanceInfo), `inInstance`, `ptype` (IsInInstance), `uiMap`, `mapType` (C_Map), `verdict` (`party`, `raid` or `none`). Diagnostics only; WoW Forever answers instance type `none` inside Shadowfang Keep, so the addon also reads the dungeon map type and a list of instance names |

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

From 0.9.44 `characters[guid].goldDays`, `goldSince`, the roster facts and `settings.gold` are a fifth such store
(the Gold pane's periods, Days and Characters), and from 0.9.45 `goldRate` and `goldTimer` belong to it (the rate
and the farm timer): uploaded with the save file, not read by ingest until a backend gate of its own. They were not
in the file measured here.

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
   `EverbuffAck = { uids = { ["<fight uid>"] = true, ... }, sessions = { ["<session id>"] = true, ... } }`. The rest
   of the file is kept byte for byte and keeps its write time.
   On the next `ADDON_LOADED` the addon marks fights with those uids, and every fight of those sessions, as uploaded
   and prunes them; the loot rows, story events and session record of those sessions are pruned too. `sessions`
   names exactly the addon sessions the backend stored (`storedAddonSessions` of `complete`, everbuff-business #46,
   0.9.36), so data the backend does not have is never pruned; the running session is never pruned. The older
   `through = <server epoch>` (every fight, row and finished session at or before it) is still applied when a
   desktop sends it. The addon then empties `uids` and `sessions` and stamps `applied`, so the file never grows and
   is never applied twice.
   Writing while the game runs is useless: WoW rewrites SavedVariables wholesale on `/reload` and logout.
2. **Paste code, manual.** The desktop shows `EB-ACK-<epoch>` (optionally `:<uid>,<uid>,...`) after an upload;
   the player pastes it in Settings > Data or types `/eb ack <code>`. Same effect, applied immediately.

`combat.lastAck` records the last applied ack; Settings > Capture shows "Desktop sync: last synced ...".
Ack on `fight.uid` (globally unique), never on `fight.id`.
