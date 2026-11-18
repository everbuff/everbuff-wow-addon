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
| `characters` | map GUID -> block | CHARACTER, one block per character (0.9.30, everbuff-wow-addon #23, approved 2026-10-04, option A). The key is the player GUID (`UnitGUID("player")`, the same value as the session records' `guid`); the addon writes only the block of the character logged in, and a GUID the client hides or has not given yet writes nothing. Each block: `name`, `realm` (written when the block is created and, from 0.9.44, refreshed at every login); `surname?`, `class?` (class token, `WARRIOR`), `faction?` (`Alliance`, `Horde` or `Neutral`), `level?`, `seen?` (server epoch of the last login, level-up or logout), written from 0.9.44 (#43) at PLAYER_ENTERING_WORLD, PLAYER_LEVEL_UP and PLAYER_LOGOUT, each read tested and protected, a value the client hides leaves the stored one; a block that has none of them is a character not logged in since the update; `goldDays?` and `goldSince?` (0.9.44, the gold history, below; siblings of `gold`, never inside it); `goldRate?` and `goldTimer?` (0.9.45, the rate window and the farm timer, "Gold rate and farm timer" below; siblings of `gold` too); `goldOpen?` (0.9.46, #43: the server epoch of a save made by a `/reload`, removed by a real logout or exit and by the login that reads it; "Honest sources" below); `crafts[]` `{ s, t, item, id, icon, count, prof, zone, x, y }` and `recipes[]` `{ s, t, name, prof }` (0.9.0); `xp { cur, max, rested, gained, fromQuests, fromKills, last, lastMax }`, `played { total, level, atEpoch }`, `playedAtLevel { level -> seconds }`, `professions { name -> { rank, max } }`, `reputation { faction -> { standing, label } }`, `durability { pct, at }`, `ilvl`, `seenZones { zone -> epoch }`, `itemUses { name -> count }` (the client's internal all-caps effects such as LOGINEFFECT are not counted, 0.9.3), `flightTime` (seconds on taxis), `lockouts[] { name, id, resetAt (epoch), difficulty, raid?, players, bosses, down, extended? }`, `gold` totals `{ balance, gained, spent, looted, sold, quests, auctionSales, mail, repairs, vendor, training, flights, auctions, mailSpent, other, trade, tradeSpent, away, awayIn, awayOut }` in copper (`quests`, 0.9.3: a quest's money reward, matched to QUEST_TURNED_IN in either order within 3 s, exact amount only; 0.9.37, everbuff-wow-addon #31: `trade` and `tradeSpent` are coin received and given while the trade window was open or closed under 3 s ago, part of `gained` and `spent`; `away` is gold that changed while the addon did not see it, signed, booked at the first read of a load as the purse minus the `balance` the save file kept, with its size in `awayIn` or `awayOut`, never part of `gained` or `spent`, so `balance = gained - spent + away` holds from the first 0.9.37 load on; from 0.9.44 (#43) a 0 read at load with gold saved is not trusted until a PLAYER_MONEY brings a read that is not 0 or 15 s have passed (read again after 3 s and 15 s), and when a 0 was booked and the very next read brings the saved balance back, the booking is taken back by a second `away` row the other way, taken out of `awayIn` or `awayOut` again, so `away`, `awayIn` and `awayOut` end where they were; while the GUID is not known no baseline is seeded, so the comparison with the saved balance is still made; a block without a `balance` is seeded silently; "Clear loot" in Settings no longer zeroes `looted`), `inInstance?` (the DUNGEON / DUNGEONLEAVE dedupe state) |
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
read of the load, on `away` rows), `x` (rows merged past the cap; from 0.9.46 the word `unmatched` on a `mail`, `sold`
or `vendor` row whose amount matched nothing that was waiting), `gap` (0.9.44, #43: on `away` rows, the seconds
since the character was last seen, `characters[guid].seen` before this load; absent when that is not known), and
from 0.9.46 (#43, "Honest sources" below) `kind`, `share`, `bank`, `crash`, `to`, `drift`.

Which source an income is, in this order (0.9.44, #43; the order matters because day rows are kept): a quest reward
of exactly this amount (QUEST_TURNED_IN within 3 s), an open trade (or one closed under 3 s ago), a sale asked for at
a merchant in the last 5 s, a mail taken in the last 3 s, the loot window (3 s from LOOT_OPENED), any gain while a
merchant window is open, any gain while the mailbox is open, else `unexplained`. Before 0.9.44 the loot window came
first, so a quest reward or a sale within 3 s of a corpse loot was booked as `looted`. Spending is unchanged.
0.9.46 changes this order and the spending rules: see "Honest sources" below, which is the current rule.

| Source | ref |
| --- | --- |
| `sold` | `item, n, unit, npc`; the item is the stack the player sold (a right click, or one of the junk stacks of "sell all junk") whose `unit * n` equals the delta, else the oldest sale of the last 5 s; a sale the addon did not see asked for carried `npc` only until 0.9.45 (from 0.9.46 such a gain is `unexplained`). A delta above `unit * n` is a sale above the vendor price |
| `vendor` | `item, n, npc` (`BuyMerchantItem`, `BuybackItem`) |
| `repairs`, `training`, `flights` | `npc` (from 0.9.46 also `kind` on `repairs` and `training`) |
| `quests` | `quest`. An income first seen with no source is written `unexplained` and rewritten in place to `quests` when QUEST_TURNED_IN names that amount within 3 s (one row per purse change either way) |
| `mail`, `auctionSales` | `sender, rel, cod` of the mail the coin came from (absent when the mailbox was open but no take was seen) |
| `mailSpent` | `sender, rel, cod` for a COD payment (the item taken in the 3 s before); empty for postage |
| `trade`, `tradeSpent` | `partner, guild?, rel, trade` |
| `away` | `mailWaiting` when true, `gap` when known, `crash` (0.9.46) when the login found the open mark of a `/reload` save (`goldOpen`, below). From 0.9.44 a 0 the client answered at login and then corrected is two `away` rows that cancel (the booking and its taking back), both kept; from 0.9.46 both carry the same `crash` |
| `looted`, `auctions`, `other`, `unexplained` | empty (from 0.9.46: `share` on `looted`, `kind` on `auctions`, `drift` on `other` and `unexplained`) |

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

### Honest sources (0.9.46, everbuff-wow-addon #43 milestone 3)

No new ledger key. Amounts move between the existing sources, and `ref` gains keys. One new SavedVariables key,
`characters[guid].goldOpen` (below, "The open mark"), which the crash tag needs. Day rows and journal rows written
before 0.9.46 keep the attribution they were written with.

New `ref` keys, written after the older ones in this order: `kind`, `share`, `bank`, `crash`, `to`, `drift`.

| Key | On | Meaning |
| --- | --- | --- |
| `kind` | `auctions` | `deposit`, `bid`, `buyout` or `cancel`: the spend equals, to the copper, an amount the client's own auction call named in the 30 s before (`C_AuctionHouse.CalculateItemDeposit` / `CalculateCommodityDeposit` on the arguments of `PostItem` / `PostCommodity`, the amount of `PlaceBid`, the total of COMMODITY_PRICE_UPDATED at `ConfirmCommoditiesPurchase`, `GetCancelCost` at `CancelAuction`). A deposit the client does not answer leaves no claim; a spend that equals no claim has no `kind`. `bid` is every `PlaceBid` amount, and the client buys an item out through `PlaceBid` too, so `bid` means "bid or item buyout" (the Gold pane says "Bid or buyout"); `buyout` is a commodity purchase. A claim also ends 2 s after the client says its action is over: AUCTION_HOUSE_AUCTION_CREATED (`deposit`), AUCTION_HOUSE_PURCHASE_COMPLETED (`bid`), COMMODITY_PURCHASE_SUCCEEDED / COMMODITY_PURCHASE_FAILED (`buyout`), AUCTION_CANCELED (`cancel`), AUCTION_HOUSE_SHOW_ERROR (every kind) |
| `kind` | `repairs` | `repairOne`: the repair cost dropped by the spend and did not reach 0 (one item repaired) |
| `kind` | `training` | `respec`: the spend equals the cost CONFIRM_TALENT_WIPE named in the 20 s before, or in the 60 s before while a trainer window is open (`npc` only when one is open). The client sends no event when the question is declined, so the wait is short away from a trainer |
| `kind` | `sold` | `buyback`: see the sign rule below |
| `share` | `looted` | `1`: the client's coin line said this coin is the player's share of what a group member looted |
| `crash` | `away` | `1`: the login found `characters[guid].goldOpen` in the save file (the last save was a `/reload` and the client then ended without saving), so what the purse did after that save was never seen. Also on the row that takes back a 0 read booked with it, so the pair cancels in every sum |
| `drift` | `unexplained`, `other` | `1`: the purse differed from the last read and the client sent no PLAYER_MONEY for it. Looked for on PLAYER_ENTERING_WORLD (booked at once) and one frame after MERCHANT_CLOSED, MAIL_CLOSED, AUCTION_HOUSE_CLOSED and TRAINER_CLOSED (a purse event of the same frame is read first and keeps its source). A quest never claims such a row |
| `bank`, `to` | | reserved for 0.9.47 (the bank a transfer went through, the recipient of a mail); never written by 0.9.46 |

**The open mark (`characters[guid].goldOpen`, the crash tag).** The client writes the save file only after
PLAYER_LOGOUT, which a `/reload` fires as well as a logout or an exit, and the session is closed there with
`endedBy = "logout"` either way. A session record therefore cannot say that the client died later. The mark can: a
hook on `ReloadUI` and `C_UI.Reload` (each feature-tested) says a reload is coming, and that save writes
`goldOpen = <server epoch>` into the character's block; a save with no reload asked for removes it. A login
(PLAYER_ENTERING_WORLD with `isInitialLogin`) that finds the mark books its away row with `crash=1` and removes the
mark; a reload keeps it. Two limits, both falling back to the plain `away` row of 0.9.45: a crash in a session with
no `/reload` before it leaves nothing in the save file, and a client that saves before the hooks run never writes
the mark (not checkable without the game). The backend can ignore the key.

**Sign rule for `sold` (a contract note, needs the backend's nod).** A buyback whose price the client gives
(`GetBuybackItemInfo`, at `BuybackItem`), whose price the next spend at the merchant equals, and which a sale of
that item booked as `sold` in the running session covers, is that sale taken back: `gained` and `sold` are both
credited the negative amount (lifetime, session, day row and rate bucket), `spent` is not touched, and the journal
row is a `sold` row with a negative `delta` and `ref` `item, n, npc, kind=buyback`. So `gained` is the purse's
inflow less the sales of the session taken back, and a `sold` row can be negative. Because a buyback is only booked
this way against a sale of the same session, a session's `sold` and `gained` and the lifetime keys never go below
0; a day row's `g` or `sold` and a rate bucket's `e` or `f` can be negative only when the sale and its buyback fall
on two sides of the day reset or in two different minutes. `balance = gained - spent + away` still holds, the
income keys still sum to `gained` and the spend keys to `spent`, and sell, buy back, sell again counts one sale.
Every other buyback is a `vendor` purchase as before 0.9.46 (`spent` and `vendor` up, `ref` `item, n, npc`): no
price known, the item sold in an earlier session or before a `/reload` (the sales are remembered in memory), or a
sale the addon did not see asked for. This departs from the plan's "gained and spent stay the raw purse flow" for
this one case, to keep the two sums above; the alternative (raw flow, the reversal in `sold` only) breaks them.

**More than one row for one purse change.** Until 0.9.45 a purse change was one row. From 0.9.46 a change the server
sends for several things at once is one row per thing, each with the balance after it (the last one carries
`GetMoney()`), so the balance chain still holds row by row: several mails taken (Open All), several sales or several
purchases asked for at a merchant. `gained` or `spent` is credited once with the whole change.

Which source an income is, in this order: a quest reward of exactly this amount (QUEST_TURNED_IN within 3 s); an
open trade (or one closed under 3 s ago); a sale asked for at a merchant in the last 5 s; a mail's coin taken in
the last 3 s (at the mailbox any gain, away from it only a gain of a waiting mail's amount); the client's coin line
of the last 3 s whose digits are this amount; the loot window (3 s from LOOT_OPENED); any gain while the mailbox is
open; else `unexplained`. A gain at a merchant with no sale asked for is no longer `sold`: it stays `unexplained`.
That includes a sale the hooks do not see: only `UseContainerItem` (right click) and `SellAllJunkItems` are hooked,
so an item dragged onto the merchant window is `unexplained` (a known case). An income found by the drift check is
`unexplained` with `drift=1`.

| Rule | What is written |
| --- | --- |
| Mail (`mail`, `auctionSales`) | Every `TakeInboxMoney` / `AutoLootMailItem` of a mail with money queues `{ sender, rel, cod, money }` for 3 s (each matched change restarts the wait of the rest). A gain takes the mail whose money it equals; else the oldest k mails whose money sums to it, one row each; else one `mail` row with `x=unmatched` (takes were waiting) or an empty ref (the mailbox is open, no take seen) |
| Coin line (`looted`) | CHAT_MSG_MONEY, as a classifier only. The text before the first `%s` of `LOOT_MONEY_SPLIT` (share), `YOU_LOOT_MONEY` and `YOU_LOOT_MONEY_GUILD` says what the line is, in any locale; a format with no text before its `%s` is skipped, a share prefix equal to a loot prefix is skipped, the longest prefix that fits wins. The line's figures must be the purse change. Where each figure names its coin (the word after it is the one of `GOLD_AMOUNT`, `SILVER_AMOUNT` or `COPPER_AMOUNT`, in any of the forms of a `|4one:few:many;` escape, or a coin icon follows it) the amount is compared exactly, so "1 Gold, 5 Silver" is never a change of 1g 5c; a figure with no coin followed by a group of three digits is a thousands separator. Where the line does not say (no amount formats on the client, other words) the digit groups must be the gold, silver and copper of the change in order (a 0 may be left out). The guild form counts the first amount only; color escapes are stripped, and the grammar escapes `|4...;`, `|1a;b;`, `|2`, `|3-n(...)` are taken out first, so an event text that carries them unresolved reads the same as a resolved one. Lines and purse changes come in either order and several at a time (a pull of several mobs): up to 20 lines, 20 unexplained gains and 20 looted rows wait 3 s each for their other half. An `unexplained` row of a line's amount is rewritten in place to `looted` (the day row moves it too), and a `looted` row learns `share=1`. Figures that fit nothing change nothing; a text the client hides is skipped. Coin with no loot window of the player's own gets a loot log row with `src` `Group share` or `Coin` (see "Loot log entry") |
| Repairs | `Emitter._repair.cost` is the last `GetRepairAllCost()` read while the purse was unchanged (MERCHANT_SHOW, UPDATE_INVENTORY_DURABILITY, after each purse change at the merchant). A spend at a merchant equal to the drop of the cost is `repairs` (a drop the client showed up to 2 s before the change counts). When the cost has not moved and the merchant can repair, the row waits for the next UPDATE_INVENTORY_DURABILITY, 0.3 s (its own timer: the timer of an earlier wait never ends a later one), the next purse change, MERCHANT_SHOW, MERCHANT_CLOSED or PLAYER_LOGOUT, then is a repair or a purchase; it keeps its own balance, so the chain holds, and a waiting spend always gets its row. A purchase asked for whose price equals the spend wins over the repair rule. `RepairAllItems(true)` (guild bank) arms nothing and the cost it clears is forgotten. A client without `GetRepairAllCost` keeps the rule of before: a spend within 2 s of `RepairAllItems()` |
| Flights | `TakeTaxiNode` arms the next spend, however long the map was open, until the character is on the taxi: the wait ends 2 s after boarding (the fare may reach the purse just after the taxi flag), at once when the client prints one of its `ERR_TAXI...` reasons (UI_ERROR_MESSAGE) or the taxi has not left after 10 s, and after 15 s at the latest. The 5 s window from TAXIMAP_OPENED stays. The fare is taken once |
| Sales and purchases | A purchase's amount is `C_MerchantFrame.GetItemInfo(index).price` (legacy `GetMerchantItemInfo` as fallback) times the quantity over the stack count. A change takes the waiting entry whose amount it equals; else the entries (searched over the 8 oldest with a known amount) that sum to it, one row each; else the oldest entry is used up as before, and when several were waiting and every amount was known the row names no item and carries `x=unmatched`. An entry waits 5 s, and every purse change that takes one restarts the wait of the rest (sell all junk, a slow server) |
| Context | Where the client has `C_PlayerInteractionManager.IsInteractingWithNpcOfType`, a merchant, trainer, mailbox or auctioneer it reports open counts as open even when the window event was not seen. It never closes a window the events say is open |

Every function and event above is feature-tested (`type(x) == "function"`) or registered through pcall, and each
rule keeps the behavior of 0.9.45 as its fallback on a client that lacks it. `tests/gold_sources.lua` holds these
(with `tests/coin_locales.lua`, the coin lines of the 13 locales mined from the client), and `tests/gold_profile.lua`
runs the journal and the sources suites on a WoW Forever stub profile and on a bare client.

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

Cap: 400 day rows per character (`Gold.DAY_CAP`). From 0.9.47 the rows past the 400 newest are folded into
`goldMonths` at the character's own login (below, "Gold showcase"); no row can reach that age before late 2027. The
acknowledgement prune (`applyAck`) never touches `characters`, so the history outlives the sessions it came from.

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

Reset gold history (Settings, Gold, More; two clicks) removes `goldDays`, `goldMonths`, `goldRate`, `goldTimer`
and, from 0.9.47, `goldBest` of the character logged in and sets `goldSince` to now. The records go because they
are read from the day rows: a record of a day whose row is gone would be rewritten by the first purse change of
that day. `gold` (the lifetime ledger and the balance) is never reset, because the backend reads it. The places
and the dungeon runs (`goldZones`, `goldZonesEvicted`, `goldRun`, `goldRuns`, `goldRunsEvicted`) stay: they are
counted on their own and are not part of the day history, and the note under the button says so. No other
character's block is touched. "Reset per hour" removes `goldRate` alone.

Size, measured on `tests/export/EverbuffJournal.lua` (0.9.45): the file grows from 15,234 to 15,597 bytes with a
rate window of two buckets (about 110 bytes a bucket in the save file's layout, so a full window of 91 is about
10 KB per character). The export changed shape by `goldRate` only; the backend's copy of the fixture follows.

## Gold showcase (`characters[guid].goldZones`, `goldRun`, `goldRuns`, `goldMonths`, `goldBest`, 0.9.47, everbuff-wow-addon #43)

Milestone 4 of 5 of #43 (the plan's "Showcase"; the transfers milestone waits on an everbuff-backend note and is
not part of it). Every key is optional, created on its first write, written into the block of the character logged
in only, and ignored by the backend until its own gate. No `sessions.gold` key, no ledger key and no journal `ref`
changes; there is no schema bump. Amounts are integer copper, times are server epoch seconds, durations are
seconds, all stored as numbers.

`characters[guid].goldZones`: map `uiMapID -> { looted, quests, secs, last, name }`, coin by place.

| Field | Meaning |
| --- | --- |
| key | the number `C_Map.GetBestMapForUnit("player")` answers at the purse change, never the zone's name. `0` when the client names no map, hides the answer or lacks the function |
| `looted`, `quests` | looted coin and quest rewards credited while the player stood there: the same credits as the ledger's `looted` and `quests`, at the same moment. No other source is counted by place: a vendor sale or a repair is never given to a place by time proximity (#43 rule 45) |
| `secs` | active seconds there, from the 10 s ticker of the rate (AFK and logged-out time are not counted) |
| `last` | server epoch of the last credit or tick there |
| `name` | the map's name (`C_Map.GetMapInfo(id).name`), else the zone text; for display only. Never stored on row `0`: every place with no map id shares that row, so it reads "Unknown place" and not the name of the last of them (a name an earlier build stored there is removed at the next credit or tick) |

Cap: 300 places (`Gold.ZONE_CAP`). A new place past the cap moves the one with the oldest `last` into
`characters[guid].goldZonesEvicted = { n, looted, quests, secs }` (the count of places moved and their sums), so
the places plus the evicted sums still equal what was counted: nothing is dropped silently.

`characters[guid].goldRun`: the dungeon run that is open, `{ t, inst, secs, looted, quests, lootValue, items,
wait?, unpriced?, left? }`; absent when none is. `characters[guid].goldRuns[]`: the last 50 closed runs
(`Gold.RUN_CAP`), oldest first, each `{ t, inst, secs, looted, quests, lootValue, items, unpriced? }`. A run past
the 50 is summed into `characters[guid].goldRunsEvicted = { n, looted, quests, secs, lootValue, items, unpriced? }`
(`unpriced`: the items of those runs that never got a price, so the summed loot value still reads "so far").

| Field | Meaning |
| --- | --- |
| `t` | server epoch the run began |
| `inst` | the dungeon's name as the addon's own detection names it, through `Emitter.canonInstance` (the two names the client gives one dungeon are one name). The run begins and ends where `characters[guid].inInstance` changes (`Emitter.checkInstance`: instance type, `IsInInstance`, a dungeon map, the name list), not on `GetInstanceInfo`'s type alone |
| `secs` | active seconds inside the dungeon |
| `looted`, `quests` | looted coin and quest rewards credited while inside. Vendor sales and repairs are never given to a run |
| `items` | item rows the player looted inside (one per loot line, as Combat > Dungeons counts them) |
| `lootValue` | an estimate: the vendor price of those items times their count. Never added to coin, never part of a rate |
| `wait` | open run only: `itemID -> count` of items whose price the client had not loaded. They count 0 and are asked again at every later item and at the close |
| `unpriced` | the count of items that never got a price (also items with no id). While `wait` or `unpriced` is there the value reads "so far" |
| `left` | open run only: server epoch the character left the dungeon. Going back in within 20 minutes (`Gold.RUN_REENTER`) continues the run, as on Combat > Dungeons; after that, or on entering another dungeon, the run closes |

`characters[guid].goldMonths`: map `'YYYYMM' -> row`, the row shape of a day row (`g, s, o, c, t, n`, the source
keys, `away`, `unexplained`) plus `d`, the number of days folded in. At the login of the character, its day rows
past the 400 newest are added to the row of their month, oldest first, and removed from `goldDays`: `o` is the
opening balance of the first day folded into the month, `c` the closing balance of the last. Month rows are never
dropped. Every sum over days and months is what it was before the fold, and only the block of the character logged
in is folded. `Gold.period("history")` and the All time Days view read them; "Reset gold history" removes them.

`characters[guid].goldBest`: `{ day = { key, net, was? }, session = { at, net, was? } }`, the best day (`key` a day
key) and the best session (`at` its `startedEpoch`) by net (gained minus spent), stored when set, so a fold or an
upload cannot change a record. "Reset gold history" removes it with the day rows; the records begin again from
the rows written after the reset. While the running day or session holds the record it follows its own net, and `was`
(`{ key | at, net }`, the record it took over) gets the record back when it falls under it. The first write reads
the day rows already kept.

Reconciliation (`Gold.audit(key)`, read only, stores nothing): for the character logged in, over the whole history
(default) or one period. It answers one of three states.

| State | When |
| --- | --- |
| reconciled | every identity that could be checked holds |
| broken | one does not; the first break is named (the session and row, the day, or the two days that do not link) |
| not checkable | a journal in the scope reached its cap (rows merged or not kept), a session has no journal (before 0.9.40), the period begins before `goldSince`, a change while away falls in it (any row with an away amount: two gaps that cancel are still two gaps), nothing is recorded, or a purse change is still being booked (a merchant spend waiting up to 0.3 s for its repair cost, or the change while away read at login, booked one frame later: "a purse change is still being booked"). What could be checked did hold |

The identities: (1) in a journal, a row's balance minus the balance of the row before it is the row's `delta`; (2)
the rows of each source sum to `session.gold[source]`, unexplained income to `gained` minus the income sources;
(3) on a day or month row `c - o = g - s + away`, the income keys sum to `g` and the spending keys to `s`; (4) for
the character `balance = gained - spent + away`; (5) each row opens on the balance the row before it closed on, and
the newest closes on `gold.balance`. Deviation from the plan, stated: a character that had gold before the addon
first saw it differs in (4) by that fixed amount, which no save file can tell from a break, so a difference in (4)
is noted and never judged; and (5) is checked on the chain of balances, because no ledger snapshot at `goldSince`
is stored. `tests/gold_show.lua` holds these, with the zones, the runs, the fold, the records and a soak.

Size, measured by the soak in `tests/gold_show.lua` (10,000 purse changes over 200 days and 6 characters, as the
save file lays tables out): zones, runs and records are about 9 KB for the six characters together, day rows and
the rate window about 56 KB. A full list of 300 places is about 20 KB and 50 runs about 5 KB per character.

## Gold display (0.9.44 and 0.9.45, everbuff-wow-addon #43, decision 5)

The sentence "nothing is drawn in game, nothing goes to chat" above scopes the gold journal of #36. What the addon
draws and says about gold, and nothing else (the pill, the bar texts, the menu and Settings from 0.9.45):

| Surface | When | What |
| --- | --- | --- |
| Loot > Gold pane | the addon window is open | periods by server day, who (character, realm, account), the Days and Characters views. Other characters' names and balances are shown here, and so in recordings |
| Home > Overview, GOLD card | the addon window is open | today's net and today's pace (the day's net over the time played that day, after 5 minutes), and on a second line the total of all characters when more than one is known |
| Minimap button tooltip | while the mouse is over the button | the gold block (at most 18 lines) under the two help lines; it follows the purse while it is open. Off with `settings.gold.tips = false` |
| Chat | only as the direct reply to a typed `/eb gold` (four lines, a fifth while a farm timer runs), `/eb gold chars` (the roster), `/eb gold stats` (0.9.45: today, week and month in, out and net for the character, its realm and the account, three lines) or `/eb gold timer` (0.9.45: starts the farm timer, "Farm timer started.") | never a login summary. These replies also answer in combat: they open, move and change nothing on screen |
| Loot > Gold pane, NET card and status line | the addon window is open | 0.9.46: `away` rows with `crash=1` in the period are counted in the NET card of this pane (`Gold.netCard`), and the status line says "Unattributed (game closed without saving): <amount>, counted in the net of this pane"; "Not seen: ... changed while away" then names only the rest. Only here: the glance figures (the pill, the bar text, the tooltip, `/eb gold`, the Days view) stay gained minus spent, because a day row carries no crash amount, and a realm or account period has no journal rows, so there the amount stays in "changed while away". The journal's Detail column says "Group share", "Repair", "Repair, one item", "Deposit", "Bid or buyout", "Buyout", "Auction cancelled", "Bought back: ...", "Talent reset" and "Unattributed (game closed without saving)" for the rows that carry those refs |
| Loot > Gold pane, PER HOUR card | the addon window is open | 0.9.45: for today and the running session of the character logged in, the rolling rate by the per hour setting ("FARMING PER HOUR"), dimmed while it warms up, its window in the status line. Every other period keeps its net over the time played |
| Loot > Gold pane, first-run question | the addon window is open, until answered | 0.9.45 (decision 4): one row above the cards, "Show your gold on screen?" with Yes and No. Yes turns the pill on. Asked once per account (`settings.gold.pill.asked`) |
| Gold pill | only when `settings.gold.pill.on` is true (default off; no frame exists while it is off) | 0.9.45: one line of text, one or two of Balance, Account total, Session net, Today net, Per hour, Farm timer. Its text follows the purse in the frame of the change, in combat too. It is kept inside the screen and at least 8 px clear of the flag and of its notification line at its widest (600 x 40 at the flag's scale, growing inward from the flag's corner; the 600 is the Emitter's own cap on the line, `Emitter.TOAST_MAX_W`), wherever the flag is, and it is placed again when the flag is dragged, snapped to a corner or resized. A new pill sits under the flag's row. Left-click opens Loot > Gold (after the fight when in combat), right-click opens the menu, a drag moves it. In combat nothing about it is moved, resized, scaled, shown or hidden; a text that gets longer than the pill during a fight is cut short inside it until the fight ends |
| Pill and bar text menu | on a right-click, never in combat | 0.9.45: the client's `MenuUtil.CreateContextMenu` when it exists and works (its entries built during the call, or a menu handed back), else the addon's own list frame. The own list closes when what it hangs under is hidden (the window, a Settings page, the pill) and when a fight starts. Never UIDropDownMenu |
| Bar text | only when another addon loaded LibDataBroker-1.1 (it is not embedded, decision 18) | 0.9.45: four data sources registered at PLAYER_LOGIN, "everbuff.gg Balance", "everbuff.gg Account total", "everbuff.gg Today", "everbuff.gg Per hour". Their tooltip is the gold block |
| Pill tooltip | while the mouse is over the pill | 0.9.45: two help lines and the gold block |
| Flag tooltip | never in 0.9.45 | the gold block under the flag's four help lines is built and switched off in code (`Gold.FLAG_TIP = false`); no setting and no control turns it on. The flag is what the desktop app reads, and the taller tooltip ships with the release that carries the desktop's replay of its fixtures (decision 3c) |
| Settings > Gold | the addon window is open | 0.9.45: the controls of `settings.gold`, hidden characters with "Show again", and behind "More" the pill's lock, size and opacity, the tooltip's row count, week and month, and the resets |
| Loot > Gold pane, Zones and Runs views | the addon window is open | 0.9.47: the places and the dungeon runs of the character logged in (whatever "who" is picked): looted coin and quest rewards, time played, coin per hour played, last visit; a run also its items and "Loot value (est.)" in a column of its own, "so far" while an item has no price. Coin per hour and Items are left out of a narrow list |
| Loot > Gold pane, Days view | the addon window is open | 0.9.47: a button in the caption row ("Balance line" / "Net per day") puts a 30 day balance line in the strip's place (one step per day from the day row's closing balance, a day with no row carried forward and drawn dashed); folded months are rows under the days; the status line names the best day and the best session |
| Loot > Gold pane, status line | the addon window is open | 0.9.47: for a period of the character logged in that reconciles, a check mark and "Reconciled" at the end of the line, the identities on hover; when the records do not add up, "The gold records do not add up: hover for where" in red; nothing more when the period cannot be checked |
| Combat > Dungeons, a run's Loot line | the addon window is open | 0.9.47: "N items · coin · loot value about X · Y/h" from the run's gold record when it has one (coin is looted coin and quest rewards, the rate is coin per hour played and never counts the loot value), else the loot log's counts as before. The record stands for the run only when it began with it (within 90 s of the run's start: a record opened later, by an update in the middle of a run, counted a part of it). The run's row in the list reads its items and coin from the same record, so list and page agree |
| Chat, `/eb gold audit` | only as the direct reply to the typed command | 0.9.47: one line, "Gold ledger reconciled.", "Gold ledger does not add up: <the first break>" or "Not checkable: <reason>"; with a period (`today`, `yesterday`, `week`, `month`, `last30`, `session`) for that period. It answers in combat like the other gold replies |

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
Coin: `{ t, s (session id), money (copper), src, guid?, x?, y?, zone? }`. From 0.9.46 (#43) coin that reached the purse with no loot window of the player's own, named by the client's coin line, is a coin row too, with `src` `"Group share"` (the line said it is the player's share of what a group member looted) or `"Coin"` (the player's own loot line, no window seen), no `guid`, and the place the player stood.
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
and the farm timer), and from 0.9.47 `goldZones`, `goldZonesEvicted`, `goldRun`, `goldRuns`, `goldRunsEvicted`,
`goldMonths` and `goldBest` (places, dungeon runs, folded months, records): uploaded with the save file, not read by
ingest until a backend gate of its own. They were not in the file measured here.

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
