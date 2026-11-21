# EverbuffJournal: the pragmatic pass (per-screen spec, revision 2, 2026-11-21)

Status: proposal for approval issue #57. Nothing here is built before the founder's yes.

Built on the draft branch `ux-overhaul` (not pushed to main, not installed), so the founder can judge it on real
shots: the brand and status words of 0.4, sections 1.4, 1.5, 2.1 to 2.3 and section 5, with gate A (the
rebuilt rows from the gold runs, `Everbuff/RunsLegacy.lua`) and gate B (loot source by boss kill timing). Both gates
still need their own yes on #57 before a release; refusing B means one constant (`D.PLACEHOLDER` rows show blank).
Not built: gates C, D, I and J (acked session records, party size, lifetime counters, the boss reference table), so
the 13 older clears and the party of a run are not shown. The expected values of this document for those screens are
asserted by `tests/real_truth.lua` on the save of 21 Nov 2026.

Review round 2 (21 Nov) also built, on the same draft branch: the coin rule of 2.1, the run page without Entered and left (2.2), Leveling as 3.1 has it with exact dates only (a level bound to a day or a range of days by its session records is not built), Home > Now at the level cap as 1.1 has it, the Activity tab hidden with every link to it gone (1.3; its code is deleted with the Activity work), and the two column CAPTURE HEALTH list (5). Not built on Now then (built in Gold and Items review round 2, below): the 5 minute join of logins into one session; the item name on an auction line ("Bought Black Lotus x3"), which needs the auction join of 4.2; and the card list for a leveling character, who keeps the four THIS SESSION cards.

Gold and Items round (21 Nov) also built, on the same draft branch: section 4.1 and section 4.2 whole, with gates G (loot rows: place at pickup, `map`, `pushed`, no placeholder source stored, "Container") and H (#52: the mailbox flag is cleared by a loading screen and never used inside an instance; one group share paid in two to four purse changes is matched to its coin line by the exact sum). Both gates still need their own yes before a release; rows already stored are not rewritten. With the join of 4.2 Home > Now reads "Bought Black Lotus x3". The expected values of both sections are asserted by `tests/real_truth.lua`. Where the build differs from the text below: the Items header meta is "89 green or better" on the save, not 91 (2 of the 91 are auction purchases, which 4.1 cuts); the Auction house answer is three segments, "Spent 30g 98s · Received 5g 97s · Net -25g 0s", because a comma after a coin icon reads badly; a deposit names its item only when one posting and one deposit are within 5 s of each other (the two clocks differ, and on the save a nearest-in-time join named the wrong formula); the Journal header may carry one remark ("newest 500 of 767", "entries since <day>", "not every entry is kept"); the BALANCE card says "records do not add up" when the audit finds a break. The two unit money rule of 0.3 ("12g 0s", never "12g 78c") is now in the one formatter, so it holds on every screen. Not built: the durable owner mark on auction rows, so auction rows of sessions the desktop picked up stay hidden (the answer line is the ledger's and is not affected); naming the dungeon on gold places (`goldZones[0]`), since the Zones view is cut.

Gold and Items review round 1 (21 Nov), on the same draft branch. Everything here is display unless marked; the marked points extend gate G or change the 4.2 rule and need the founder's yes on #57 with the rest:

- Items, From: a name is shown only when the loot window named it (the row carries the window's loot GUID; from 0.9.52 a row that is not `pushed`) or an opened world object did. A name that is only the last kill before the pickup reads "Enemy", hover "Name not recorded": on the save that was a party member (Pebbles, Equi) and a totem (Healing Ward). For rows before 0.9.52 the kill is found in the session record's KILL rows, up to 20 s before the row. **[gate G]** the capture marks how a pushed row was named (`srcBy` = "kill" or "object").
- Items, Place and Coords: shown only when the stamp is the row's own. Rows before 0.9.52 carried the stamp of the last loot window, however old (161 rows at Mount Hyjal 69.0, 69.8 over 33 minutes), so their place counts only with the window's loot GUID or within 15 s of the first row of the session with that exact stamp. Coords are never shown without Place. On the save 26 of 929 rows keep a place, so neither column shows. **[gate G]** the capture stamps every row when the item arrives, not when the loot window opened.
- Items, "Quest: <name>" only when one turn-in of the session lies within 5 s; with two the cell reads "Quest".
- Items header: "89 pickups green or better, not every item is kept" (a row is a pickup; By item says "83 items green or better"). The remark shows when a dungeon run after the list's start stored more items than the list holds for its span; the reason is on its hover.
- Journal header: the cut and the coverage are said together, "newest 500 of 767, not every entry is kept". For All the header is "ENTRIES SINCE WED 18 NOV" (ALL TIME is the cards' word). When the remark does not fit beside the controls it has a line of its own under the header.
- Journal, a mail row with no sender: blank Detail, hover "Sender not recorded", never "mailbox". When the stored records place the coin away from every mailbox (its coin row is in another zone than the mailbox visit of that moment, or the event list covers the moment and holds no visit) the Source cell reads "Source not seen". The ledger and the Sources view still count it as stored.
- Auction house, All: header "AUCTIONS SINCE SAT 7 NOV", remark "not every row is kept" while stored rows belong to sessions whose record is gone (298 of 556 on the save).
- Auction house, a sale's "Mail paid" shows only when the stored net is the invoice's sum (bid - cut + deposit); 26 of 61 stored nets are not. A sale takes its count from a posting only when that posting is one lot sold whole; several auctions posted in one call show the price of one and divide nothing.
- **[changes the 4.2 rule]** a delivery mail is absorbed by a priced row of the same item bought in the same session, whatever the delay, or within the hour (Tender Wolf Meat x40, mails 96 minutes later). Deliveries with no purchase read "Collected" (was "Won"), and the mails of one item taken within 60 s are one row ("Wool Cloth x60"). A bid named at bid time takes up its won mail by the invoice's amount, with the mail's count.
- The Auction house answer's dots are centred glyphs; the Home > Now hero centres its two lines on the portrait when no rate line stands under them.

Not solved, raised: inside dungeons the KILL row can carry a party member's name (session of 17 Nov, "KILL Pebbles" at 23:00:22 where the combat log has Deep Lurker).

Gold and Items review round 2 (21 Nov), on the same draft branch. Display only, no stored row is rewritten. Where it changes a rule of this document the section below is changed with it:

- "This session" is built as 0.2.4 has it: logins of the character less than 5 minutes apart are one session (`Gold.joined`, the one definition). The hero and PLAYED of Home > Now, WORTH A LOOK, and the Session period of Loot > Gold (cards, Sources, Journal, Auction house) read it. On the save the logins of 11:45:25 and 11:47:01 are one session: +8g 47s, -30g 99s, net -22g 51s, as Today. PLAYED is the time logged in, the lengths of the joined logins added up (changed in review round 3, below): 66 s + 561 s = 10m 27s at the save's last second, which reads "10m" (a played time is said to the nearest minute everywhere). Not built: the Sessions list still has one row per stored record (1.2: 45 rows, not 41).
- The brand stays lower case inside a label drawn in capitals: "SAVED TO everbuff.gg" (`UI.upper` keeps it, on every screen).
- Journal day rows are calendar days, as on Items and Auction house, so a row at 01:29 stands under the day it happened on (before: under the gold day, one day early for every row between midnight and the daily reset). A day row carries the day's net only when the stored data proves it (rule replaced in review round 3, below; the round 2 rule read a missing session record as proof that nobody played). "FROM 20:35" only when no listed entry of that day is older. On the save no day row carries a net; Wed 18 Nov (rows at 01:14 to 01:36 and from before 20:35) is the bare day.
- Journal Detail never prints a number or a placeholder for a name: a quest with no stored name is blank (hover "Quest: Not recorded"), a vendor sale of an item the client does not name reads "to Kaja", "Creature" is "Coin" or "Group share", and a count shows only above 1 ("Acolyte Blade to Kaja").
- Auction house, one row per auction: a posting whose outcome is stored (sold at its buyout, expired, cancelled) is only its outcome row, which carries when it was posted in the hover. A posting with no outcome is a row only while its time has not run out; after that its outcome is not recorded and it is not listed (56 of the 98 kept postings on the save; no posting is open on 21 Nov, so the list has no Posted row). The duration is in the hover, and in the Result cell only when the listed postings differ in it.
- Auction house, no row without an item: a purchase row with no item of its own (`C_AuctionHouse.PlaceBid` knows the auction, not the item; older rows carry a guessed name) is named by the invoice of an "Auction won" mail of the same session with exactly its price. On the save the session of 17 Nov has 5 such mails for Red Mageweave Bag (16,046 and 4 times 16,499) and bids of 16,046 (3), 16,047 (2) and 16,499 (3): four rows read Red Mageweave Bag. A bid nothing names is not a row and not counted as bought (8 on the save, two of them on the same auction id): nothing says it completed. The session's own ledger (auctions 67,391 copper) is below the 82,042 of the five invoices, so it could not settle which bids completed. Raised: the fifth bag mail (a fourth 16,499) has no bid row left and is not listed.
- The Auction house remark is "not every row is listed"; its hover names each reason that applies with its count (sessions the desktop saved, bids with no item, postings with no recorded outcome).
- Items, From: "Enemy" is no value. A row whose source is hidden or only a kill by timing has a blank cell, hover "From: Name not recorded". A source that repeats the item's name (a gathered node) is blank. With that, 14 of 86 rows have a value in the default view, so From is left out by rule 0.3; the hover of a row has what the column would say.
- Items, one row for the pickups of one item in one minute that read the same: "Iron Ore x3", "Hyjal Silphium x8" (22:44) and "x4" (22:43). The header still counts pickups (89, 929); the hover says how many pickups a row holds.
- Items, "not every item is kept" no longer uses a run's active seconds as a clock (they leave out time away): a run's span is from its start to the start of the next run. On the save the remark is unchanged (three runs have no row left).

Gold and Items review round 3 (21 Nov), on the same draft branch. Display only, no stored row is rewritten:

- PLAYED and every per hour figure of "this session" count the time logged in: the length of each joined login added up (`Gold.scope("session").elapsed`, read by Home > Now and Loot > Gold). Before, it was the span from the first login to now, which counted the time logged out between two logins as played (up to 5 minutes per relog). On the save: 11:45:25 to 11:46:31 is 66 s, 11:47:01 to 11:56:22 is 561 s, together 627 s, "10m" (the span was 657 s, "11m"). The gold day row of 21 Nov holds 610 active seconds, also 10m. The hover says "Time logged in this session, its 2 logins added up."
- A Journal day row carries a net only when the stored rows prove it. A gold day row (05:00 to 05:00 on the save) stores no time of day, so a calendar day is parts of two gold days. The proof: for each gold day that overlaps the calendar day, the kept journal rows of that gold day add up exactly to its day row, earned and spent each. Then no change is missing and the net is the sum of the kept rows of the calendar day (so a night before the reset is counted in its own calendar day). If the rows of either gold day do not add up (a session record is gone: the desktop app deletes them when it picks a session up), the day row is the bare day. A missing session record is never read as "nobody played". On the save: no day row carries a net. The kept rows add up for 21 Nov only (84,773 and 309,910); for 20 Nov they are 725,040 of 845,791 earned, so nothing says whether the missing rows fell before or after midnight of the 21st. The round 2 rule showed "THURSDAY 19 NOV · +57g 7s", which is the net of Thu 05:00 to Fri 05:00: the 19 Nov snapshot still holds 115 rows of Thu 00:00 to 05:00 (net -23g 1s), booked on the day row of the 18th, whose session record the 21 Nov save no longer has. Raised, a capture gate: with the time of the first and last change stored on a gold day row, a day row could carry its net without the kept rows. Until then most past days of a player who runs the desktop app read bare.
- Sources, MOSTLY FROM is as wide as its longest name (to 360 px) and Source takes the rest, so a name is whole whenever the row has room: "Formula: Enchant Boots - Greater Stamina" is whole at 900, 1104 and 1600 wide (before: cut at 220 px at every size).
- Sources, the amount beside MOSTLY FROM shows only when the largest group is a part of the source ("Formula: Enchant Boots - Greater Stamina 2g 81s" of +5g 97s). When the group is the whole source the cell is empty: "Mail received, Yoco Ratnik, +2g 50s", "Flights, Tal, -45c" (before: the same amount twice, side by side).
- Auction house, a bid is not a purchase until a mail confirms it. A row named when the bid was placed (`C_AuctionHouse.PlaceBid`, `named = "bid"`) with no "Auction won" mail whose invoice names its amount reads "Bid" with its amount, is not counted as bought and its amount is not in the Auction house view's spent (a bid can be outbid or refused). The Journal and Sources say "Bid: Felcloth", never "Bought Felcloth". A won mail of the same item that names another amount, or whose invoice cannot be read, confirms nothing and is its own "Collected" row. The mail whose invoice names the bid's amount makes it a "Bought" row with the mail's count and seller. No such row exists on the save (the capture is new on this branch). Raised: the Classic hook (`PlaceAuctionBid`) stores a bid below the buyout the same way as a buyout, with no confirmation either; the save has no such row, and it is not changed here.

Character round (21 Nov), on the same draft branch: sections 3.1 to 3.3, with gate E (`levelAt`, the played stamp fix, the stamps of before 0.9.52 discarded at load) and the parts of gate F that need no client read (the character id `g` on new reputation rows, craft batches at write with `t1`). Both gates still need their own yes on #57 before a release. The expected values of section 3 are asserted by `tests/real_truth.lua`. Where the build differs from the first text of section 3, the section is changed with it:

- Leveling: levels that share one bound are one row ("30 to 37 · 8 to 11 Nov"), so the save's 38 levels without an exact date are 9 rows, not 38. On the save every level from 2 to 60 is then in a row and the muted line does not show.
- Reputation: the column "Last day gained" is the sum of what the faction gained on the calendar day of its newest stored gain, with that day ("+1,005 · Yesterday"; 25 gains on the save, the last single one +150 at 22:53). It is never called one gain. The order within a day is by that sum, largest first, so the first row and the answer are Barkskin Burrow +1,005. By time alone the newest stored gain is Gadgetzan +1 at 23:29, which says less. Progress is left out while the client answers for no faction, and the section header carries the faction count.
- Reputation, review round 1: none of the 2,000 stored gains carries its character in the save, and 559 of them belong to 15 sessions whose record the desktop picked up. The load now writes the character on every row it can prove (`ns.Rep.harvest`, at load and before a pickup is applied): 1,441 by their session record, 189 by a craft or recipe of this character that carries the same session id (3 of the 15 sessions). So the next pickup no longer empties the page. 370 rows of 12 sessions name no character and are never guessed. A faction with such a row on its last day or later has a blank cell (hover "Last day gained: Not recorded"), never a smaller number or an older day: Orgrimmar (450 stored on Fri 20 Nov, 250 of them with no character), Undercity, Darkspear Trolls, Thunder Bluff, Gadgetzan, Booty Bay, Everlook, Powderfuse and Ratchet on the save. Their pages still list the counted gains, under "GAINS" with no start and no sum. Timbermaw Hold reads "+505 · Thu 19 Nov" (32 gains of a proven session; its 35 unproven rows are of Wed 18 Nov, a day earlier).
- Professions: the Crafted day of a batch is the day of its last craft.
- Professions, review round 1: the craft list is at its cap (1,000 rows), which cut through Wed 11 Nov (25 of 148 crafts left), so that day is left out and the header names the first whole day. A batch is keyed on spell id and session, not on the profession of the row: the first craft of a round is often stored with no profession ("Tin Bar" 15:46 on 12 Nov, "Tender Wolf Steak" 19:26 on 17 Nov) and now stands in its batch, with the profession the other rows of that spell name. New crafts merge the same way at write time. A craft whose spell no stored row gives a profession ("Courier's Shipment", an item a quest made) is not listed and not counted.
- Not built: `recipeBook` (gate F). The profession window lists what its filters show, so a count read from it can be short; it needs a check in the game first. No recipe count and no recipe list is shown until then.
- Home > Now, "Reached level N": the time at the level before is read only from stamps of the new kind.

Revision 2 answers the founder review of revision 1. The short version: fewer screens, fewer columns, no sentences about why data is missing, and the fix for missing history (gates C and I) is built before anything is worded around it. Section 7 lists the few points where this document does not follow the review, and why.

This document sits on top of `docs/UX_OVERHAUL.md`. The design system there (section 2) and the navigation pattern (sub-tab row, detail page with Back) stay. This document decides, per screen, what is shown and what is cut. Where the two disagree on content, this one wins and `UX_OVERHAUL.md` sections 3 and 4 are updated in the same change that builds it.

Example numbers come from the founder's save of 21 Nov 2026 (Iron Hart, level 60), derived with throwaway scripts and not through addon code. They are the expected values for `tests/real_save.lua`. Examples marked "illustrative" show wording only.

---

## 0. Rules for every screen

### 0.1 Who looks

| Player | Wants at a glance |
|---|---|
| Level 60, farming gold | What did I make and spend, from what, what sold |
| Level 60, running dungeons | How long, how it compares, what dropped |
| Level 60, leveling professions | Skill now, what I crafted |
| Leveling alt | When do I ding, how fast |

A screen that answers none of these for the logged-in character is not shown.

### 0.2 Data accuracy (founder rule: data accuracy is crucial)

1. A number is shown only when it can be derived from stored data or a live client read. No estimate, no timing guess, no name matching, unless the founder approved that exact inference and the tooltip says how it was derived.
2. Missing data, two phrases only:

   | Where | What shows |
   |---|---|
   | A table cell | Blank. Tooltip "Not recorded". Never "0", never "-". |
   | A cell in a column whose other rows name a confirmed fact (From on a run's Loot table) | "Not recorded", muted: a blank there would read as one more confirmed row |
   | A hero, card or single line | "Not recorded", muted. Or the element is hidden when it has nothing else to say. |
   | A value the client has not answered yet (live reputation) | "Not known yet", muted |
   | A true stored zero | "0" |

   The reason data is missing (desktop pickup, addon version, list cap) is never screen text. It goes in a tooltip, and at most one muted line per screen may exist for it. Missing is never coloured `bad` or `warn`.
3. A list states where it starts once per screen, in its section header ("ITEMS SINCE TUE 17 NOV"). Cards and answer lines do not repeat it. "All time" is allowed only for a stored lifetime field.
4. Two counts of the same word on two screens come from the same function. "This session" means the same span everywhere: logins less than 5 minutes apart are one session (1.2).
5. Stored rows are never rewritten. Invalid stored values are discarded, not shown as legacy (founder rule 2026-10-05).

### 0.3 Layout

- Order on every page: hero or cards (at most 4), then one table. No answer line that repeats a card.
- A column is hidden when no row of the list (after filters) has a value, and also when fewer than a third of the rows have one. The few values it had stay reachable on the row's detail page or tooltip.
- A column whose value is the same on every row is hidden (Level at 60, Place when every row is Orgrimmar).
- A section with no rows is hidden. No sentence takes its place unless the whole screen is empty.
- A total row is never a list row. Totals go in the section header meta.
- Source, Place and Coords are separate columns (house rule). Coords only at WIDE.
- Quantity is "x3" after the item name, not a column.
- Durations: under 10 minutes with seconds ("7m 59s"), from 10 minutes in minutes ("33m", "1h 9m"), from a day "6d 20h". Exception: boss splits and kill clocks keep seconds (section 7).
- Amounts: from 1g the copper is dropped, cut and not rounded ("-22g 51s"); under 1g it stays ("12s 19c"). The tooltip has the exact amount.
- Words: "pull" for a fight, CAPTURING for the status, everbuff.gg for the brand. No em dashes in any string.

### 0.4 Window chrome (build items, were only a rule before)

| Item | Now in game | Becomes |
|---|---|---|
| Title bar brand | "everbuff" | "everbuff.gg" |
| Title bar status | "Recording" | "CAPTURING" |
| Settings section and row | "RECORDING HEALTH", "Recording: on in Orgrimmar" | "CAPTURE HEALTH", "CAPTURING in Orgrimmar" |
| Stray "0:00" in the middle of the window (screenshots 02, 04, 06, 08, 09, 12, 13) | origin not found | see below |

The "0:00": a search of `Everbuff/*.lua` finds no frame that draws a bare clock (the only clock text is the run delta, "±0:00", inside the Runs table). In screenshot 05 it sits behind the list rows, so it may be a game or desktop element showing through. This is not proven. First build item: reproduce it with `shoot.sh` and in the next recording with the window moved; if it is ours it is removed, if not it is reported on everbuff-desktop.

### 0.5 Navigation after this pass

| Main tab | Sub-tabs |
|---|---|
| Home | Now, Sessions. Fights only while pulls are stored. Deaths only while a stored death names its killer. |
| Dungeons | Runs. By dungeon only when 2 dungeons have 2 runs each. |
| Character | Leveling, Reputation, Professions |
| Loot | Items, Gold |
| Settings | General, Gold display, Data and sync |

Home > Activity is removed.

### 0.6 What needs the founder's yes

Items marked **[gate]** change stored data, capture behaviour or wording by inference (section 6). Everything else is display only.

---

## 1. Home

### 1.1 Home > Now

**Why I open it.** How is my gold, and is the desktop app picking my data up.

**Title.** "Iron Hart", then "Level 60 Undead Paladin · Orgrimmar". Name from `UnitName` plus `ns.surname()`, fallback the stored `surname` (the save has "Hart"). When no surname is known the name line is left out and the title is the class line. A half name is never shown.

**Hero.**

| Character | Hero | Meta |
|---|---|---|
| Max level, gold moved this session | "-22g 51s this session" | "+Xg per hour" only after 30 minutes of play; nothing before |
| Max level, no gold moved | the balance, "12s 19c" | none |
| Leveling | "42m to level 42" (illustrative) | XP line and bar, as `UX_OVERHAUL.md` 4.1 |

On the save: session of 21 Nov 11:45 (two logins, 11:45 and 11:47, joined): +8g 47s in, -30g 99s out, net -22g 51s.

**Cards.** Each only when it has a value.

| Card | Value | Meta | Source |
|---|---|---|---|
| BALANCE | "12s 19c" | "all characters 12g 0s" | `characters[guid].gold.balance` (1,219 and 118,859 copper on the save). Not shown when the hero already is the balance; then only the meta moves to the hero. |
| PLAYED | "10m" | none | the lengths of the session's logins added up, the running one to now (66 s + 561 s = 10m 27s at the save's last second; a played time is said to the nearest minute). Time logged out between two logins is not played. |
| LAST RUN | "Blackrock Spire" | "Fri 20 Nov · 1h 9m · 7 bosses · 2 deaths" | newest `dungeonRuns` record; click opens the run page |
| SAVED TO everbuff.gg | "142 pulls" | "confirmed Sat 21 Nov 11:45" | `combat.lastAck.fights`, `.at` |
| DEATHS | count | none | `sessions[id].deaths`; only when above 0 |
| XP PER HOUR | leveling only | "last 30m of play" | `ns.Pace` |

`combat.lastAck.at` is when the addon applied the desktop app's confirmation (at the next login, or when a code was pasted), never when the app saved the data: the confirmation file carries no time. On the save it is 21 Nov 11:45:11, 14 s before the session starts; the desktop's copy with those 142 pulls is from 20 Nov 23:54. So the count leads, the time is always worded "confirmed", and the hover says "The desktop app saved this data earlier. The time is when the addon saw its confirmation, not when it was saved." The real time of the save needs the desktop to write it into the confirmation (a contract change, not made).

At most 4 cards, in this order of priority. SAVED TO everbuff.gg with no pickup ever seen reads "Not seen yet", tooltip "Install the desktop app from everbuff.gg to keep your history and watch your recordings."

**NEXT.** Bags, repair, instance limit, quests ready. Hidden when nothing needs attention.

**WORTH A LOOK.** At max level: the up to 3 largest gold lines of the session, "Bought Black Lotus x3" / "-28g 19s · Auction house · 11:48" (session `goldLog` joined to `loot.ah`). Hidden when the session has none. Leveling characters keep ranks 1 to 6 of `UX_OVERHAUL.md`.

**Cut.** "Level 60" as hero and "Reached ... played at 60" (Leveling owns it). PLAYED meta. "rate shows after 30 minutes". The kills and items line. "Nothing needs you. Go have fun." Professions below their cap. "No deaths and no level yet. Keep going." The whole-screen empty sentence: a fresh session at 60 shows title, balance, pickup and nothing else.

### 1.2 Home > Sessions

**Why I open it.** What did each play session give me.

**The answer.** One line for the last 7 days, each part only when it can be derived:

| Part | Example | Shown when |
|---|---|---|
| Net gold | "net -80g 88s" | always (`goldDays`) |
| Runs | "6 runs" | from the run store (1 record plus 5 rebuilt rows after gate A; before A this part is left out) |
| Played | "14h played" (illustrative) | only when every session of the range is still stored, which gate C guarantees |

When history starts inside the 7 days the line says the real range: "Since Wed 18 Nov: net -80g 88s · 6 runs". Otherwise "This week: ...".

**Columns.**

| Column | Content | Source |
|---|---|---|
| When | "20:01", under day rows | `startedEpoch` |
| Length | "3h 53m" | start to end |
| Level | "59 to 60" | `level0`, `level`; hidden when every listed row has the same single level |
| XP | number | `sess.xp`; hidden when every listed row started at the cap |
| Gold | signed net | `sess.gold` |
| Deaths | number | `sess.deaths` |
| Runs | runs of the run store that start in the session | `Feed.sessionRuns` |

The old per-session run counter is never printed (it counted door entries: 22 on 17 Nov for a night with 2 runs). A session from before the run store whose runs were not rebuilt has a blank Runs cell, and rule 0.3 hides the column while most rows are blank.

**Grouping.**
- A session that starts within 5 minutes of the previous one ending (same character) is the same row. Tooltip "2 logins". On the save: 45 records become 41 rows; 21 Nov 11:45 reads 10m (the two logins added up), -22g 51s.
- A row under 5 minutes with nothing in it (no XP, gold, death, loot) is not listed. No line, no link, no setting.
- Day rows carry the day's net gold and played time once gate C keeps the session counters. Before C lands day rows carry no totals (a day total over deleted sessions would be wrong).

**Cut.** Kills (it disagrees with pulls and the combat log, and a number that needs a disclaimer is not shown). Both strips. The "45 sessions stored" line and every sentence about pickups. `sessionsShowShort`.

**Empty.** "No session stored yet."

### 1.3 Home > Activity

Removed. Gold lines are on Loot > Gold > Journal, drops on Loot > Items, the session's largest gold lines on Now. The grouping rules of revision 1 are not built. `story.events` capture is unchanged (the backend reads it).

### 1.4 Home > Fights

The tab exists only while this character has pulls in `combat.fights`. With the desktop app running that is the time between two pickups; the rest of the time there is no tab and no sentence. The pickup itself is confirmed on Now and in Settings.

When shown: section header "PULLS SINCE FRI 20 NOV 15:08" (illustrative), the pull table, and the filter "Bosses, wipes and deaths · All pulls" (was "Important · All"). The answer line "58 pulls · 0 wipes · 2 deaths · 22m in combat" is illustrative: this save has no stored pull, so the test for this screen runs on the per-session copy `recordings/<id>/saves` of 20 Nov, and its numbers are pinned there before the build.

**Cut.** "ALL FIGHTS". The four-clause pickup sentence. The Sessions link row. Any wipes, deaths or combat-time text derived from an empty list ("you did not die").

### 1.5 Home > Deaths

The tab exists only while at least one stored death of this character has a recorded killer (open-world deaths; the game hides enemy names in dungeons). Otherwise no tab.

When shown: columns When, Level, Killed by, Place, Coords (WIDE), Downtime. Section header "DEATHS SINCE <date>". "Most in <place>" is added only with at least 3 deaths in at least 2 places. A row opens its pull only while that pull is stored; otherwise no chevron.

Deaths inside a dungeon are listed on the run page (2.2). Death counts per session are on Sessions.

**Cut.** The Gear "-10%" column (constant). "Killed by: Not recorded" rows as a list. The line about older deaths. "You have not died." unless stored sessions also sum to 0 deaths. Lifetime death and pull counts come back as one number each with gate I, on Leveling (3.1), not here.

---

## 2. Dungeons

### 2.1 Dungeons > Runs

**Why I open it.** How did my last runs go.

**Hero card (the answer).** "LAST RUN" / "Blackrock Spire" / "7 bosses in 1h 9m" / "Fri 20 Nov 15:14 · 2 deaths · best drop Rhombeard Protector" / button "Open run". "7 of 7" is never shown without a real total (below). "You died" becomes the death count. No "1 run" headline anywhere.

Under the hero, one line only when it has something to say: "2 instances this hour" (`dungeonCopies`, when above 0 or a limit is set) and "Saved in 1 dungeon" (`lockouts`).

**One table**, full and rebuilt runs together.

| Column | Content | Source |
|---|---|---|
| When | "Fri 20 Nov, 15:14" | `rec.t` |
| Dungeon | name; rebuilt rows carry a muted "partial" tag, tooltip "Time and loot only", then how its time was counted (below) | `rec.inst` |
| Time | "1h 9m" inside | `secs.inside` (4,148 s) |
| Vs best | `fmtDelta` on the boss clock; shown only for a dungeon with 2 or more full runs; tooltip "Compared from first pull to last kill" | `dungeonStats` |
| Bosses | "7", or "7 of 9" with a real total | `rec.bosses` |
| Deaths | "2" | record |
| Worth | "19g 92s"; tooltip "1g 88s coin plus 18g 3s of items at vendor prices" | the run's coin (below) + `gold.lootValue` (18,835 + 180,399 copper) |
| Best drop | item name in its quality colour (WIDE) | highest quality looted row of the run, green or better |

**The coin of a run.** `gold.looted` misses the shares of group loot the client pays without a loot window: on the stored run 11,612 copper was booked and 18,835 was paid (the 97 "Your share of the loot is" lines of the chat log; the same figure as `gold.purse`, what the purse gained inside less quest coin). So the coin of a run record is `gold.purse` when it is more than `gold.looted`, else `gold.looted`; the hover says which and names both figures. A rebuilt row stores the booked coin only and no purse figure (Maraudon: 3s 65c booked, 1g 14s paid), so its coin is not known: its Worth is the vendor value of its items alone, the card says "items at vendor prices" and the hover "The coin of this run was not recorded in full, so it is not counted." The other wording, the booked coin as a lower bound ("at least"), is one constant (`D.PARTIAL_COIN`) and the founder's pick. By dungeon's Worth per run is on the same coin: `dungeonStats` sums the booked coin, and every stored run it counts adds what its purse gained beyond that (`D.worthPerRun`), so a dungeon whose runs are all stored reads the mean of its Worth cells on Runs (Blackrock Spire, one run: 19g 92s on both, not 19g 20s). A run no longer stored stays at its booked coin. Limits: the purse figure also holds a trade or a vendor sale made inside; gate H (group shares booked as looted at capture) is the fix for it and for new runs. The item value counts every item that reached the bags inside, a quest's reward item too (Prismcharm on the stored run); the WORTH hover says so.

Rule 0.3 applies: while most rows are partial (1 full and 5 rebuilt on the save), Vs best, Bosses and Deaths are hidden and live on the hero and the run page. They appear on their own once a third of the rows are full runs.

**Boss total [gate J].** "N of M" needs M from the boss to dungeon reference table (J) or a lockout count. Until J lands the cell is "7". With one run "7 of 7" is a circle: the same dungeon gave 9 kills that morning.

**Rebuilt runs [gate A].** Rows from `characters[guid].dungeonLegacy` (built from `goldRuns`; never from timing or gaps). They never enter bests or averages. On the save: 5 rows (Maraudon 18 Nov, Blackrock Depths x3 19 Nov, Blackrock Spire 20 Nov 10:06). Gate J adds the 13 older clears by name. Until A lands the table lists the 1 stored run and the screen claims no count.

**The time of a rebuilt run.** The gold run counted by the zone's name, in steps of 10 s, and the land in front of some dungeons carries the dungeon's name. Maraudon, 18 Nov: stored start 21:32:58 and 4,250 s; by the combat log the character entered the instance at 21:34:20 and was inside 4,096 s (the rest was 146 s at the entrance). The addon cannot correct a stored row, so every partial row says what its figures are: the TIME card's meta is "in the dungeon's zone", never "in the dungeon"; the line under the title is "Wed 18 Nov 21:32 · reached the dungeon's zone"; the PARTIAL badge, the TIME hover and the row's hover on Runs carry "Counted by zone name to 10 s, so it can include time at the entrance."

**Cut.** The "BEFORE RUN TRACKING (VERSION ...)" section and title. The footer about unrecorded runs. The Items count (it counted 29 whites and greys). "first run" as a Vs best value. Coin as its own column.

**Empty.** "No run stored yet."

### 2.2 Dungeons > Run page

**Why I open it.** How this run went, boss by boss, and what dropped.

**Hero.** "Blackrock Spire · 1h 9m", with `fmtDelta` against the best once the dungeon has 2 full runs.

**Meta.** "Fri 20 Nov 15:14 to 16:31 · level 58". Then, each only when known: "party of 5" (only from a stored size, gate D), "solo" (only when `rec.size == 1`, never inferred from a missing size; today `Dungeons.lua` prints "solo" whenever the size is unknown, which is the lie in the screenshot). No word "group". No re-entry count. No quest coin.

**Two clocks, both named.**

| Clock | Value | Used for |
|---|---|---|
| Time inside | 1h 9m (`secs.inside`) | hero, TIME card, XP per hour, Worth |
| Boss clock | 1h 3m, first pull to last kill | bests and Vs best only, always labelled "boss clock" |

**Cards.**

| Card | Value | Meta | Source |
|---|---|---|---|
| TIME | "1h 9m" | "7m 59s dead or outside" | `secs.inside`; `secs.ghost` + `secs.outside` (158 + 321 s) |
| BOSSES | "7" | "boss clock 1h 3m" | `rec.bosses` |
| XP | "62,388" | "54,146 per hour" on time inside | `xp.gain`, `secs.inside`; hidden when the run started at the cap |
| WORTH | "19g 92s" | "1g 88s coin · 18g 3s items at vendor prices" | the run's coin (2.1), `gold.lootValue` |

Revision 1 showed 54,686 XP per hour on a third clock (`secs.active`). It is now 62,388 over 4,148 s.

**Bosses table.** Boss, Killed at, Split, Fight. Killed at and Split are on the run's clock (the stored `kill`): it runs inside and while running back dead, and stands still while the character is outside alive or offline. It is not the time since entering on a run that was left and entered again: on the save Highlord Omokk died 25m 0s after entering (15:39:01) and reads 19m 39s, because 5m 21s outside came before him. The headers say so. Killed at tip: "The run's clock when the boss died. It stops while you are outside the dungeon alive or offline, so it can be less than the time since you entered." Split tip: "Boss 1: the run's clock at its kill. Others: since the previous kill. Time outside the dungeon alive or offline is not counted." Boss 1 split equals its kill clock: Highlord Omokk 19m 39s, 19m 39s, 43s. Bests keep measuring from the first pull. Open founder decision: show Killed at as the time since entering instead (`Runs.wallOf(rec, kill) - rec.t`, Omokk 25m 0s), which would agree with the header and the Loot table's When. The TIME hover's "first pull" and "last kill" times of day go through `Runs.wallOf` (last kill 16:28, not entry plus the run's clock, 16:23).

**Deaths line** under the Bosses table when the run has deaths: "Deaths: 16:12 (2m 45s down) · 16:30 (1m 13s down)". No killer, no gear column.

**Loot table.** Item (with "x3"), From, When. Header meta "6 drops green or better, 2 with no recorded source" on the save ("8 green or better" when every row has a source). One muted line under it: "29 more: 21 white, 8 grey".
- From **[gate B, inference]**: a stored name is shown as stored. A row whose stored source is a placeholder gets the boss of this run killed at most 90 s before it, tooltip "Looted 13s after Gizrul the Slavener died. The game hides enemy names in dungeons." "Trash" is the same kind of inference (an enemy placeholder with no boss kill in range) and carries the tooltip "No boss died in the 90s before this. The game hides enemy names in dungeons." Every other placeholder reads "Not recorded", muted, tooltip "Where this item came from was not recorded, so it is not counted as a drop.", and the header counts it apart. If the founder refuses the inference, every placeholder reads so.
- On the save: Slamshot Shoulders Highlord Omokk, Talisman of Evasion War Master Voone, Slashclaw Bracers Halycon, Rhombeard Protector Gizrul the Slavener, 2 Trash, 2 "Not recorded". The two are Prismcharm (15:29, by the chat log the reward of the quest "Urok Doomhowl": "You receive item:", not a drop) and Engraved Cape of the Gorilla (16:01, a drop won by roll 14 s after the loot window). Both are stored "Picked up", and the save cannot tell them apart.
- Capture, from this version on: an item pushed into the bags ("You receive item:") in the 3 s before `QUEST_TURNED_IN` that named no world object becomes "Quest reward" (the reward reached the bags before the event on 20 Nov). Rows already stored are not changed.

**Entered and left.** Not on the page: no visit count, no third clock ("Active"), no combat totals. The split of the TIME card's "dead or outside" (running back, outside) is in its hover. One exception: a run marked "possibly two runs" lists its visits, because its note points at Split here on one of them.

**Pulls section.** Shown only while pulls of this run are stored. Otherwise hidden, no sentence.

**Group and who got the loot.** Not captured today. Party names and classes on the run record are gate D; other players' loot is gate K. Neither is shown or hinted at before its gate lands.

**Rebuilt run page [gate A].** Time, Worth, the loot table, bosses when attached. Nothing else, no sentence about what is absent.

### 2.3 Dungeons > By dungeon

Hidden until 2 dungeons have 2 full runs each. On the save that is not the case, so the tab does not exist.

When shown: only dungeons with full runs. Columns Dungeon, Runs, Best (boss clock), Average (only with 2 or more runs), Deaths per run (one decimal from 2 runs, a plain count for 1), Worth per run. No first visit, no per hour rate, no rows for dungeons without runs, no line about them.

---

## 3. Character

### 3.1 Character > Leveling

**At max level: short.**

- Hero: "Level 60", meta "Reached Fri 20 Nov 22:49 in Mount Hyjal". Date from `levelAt[60]` **[gate E]**; until then the LEVELUP event or the session LEVEL_UP row; with none stored the meta is left out.
- One line: "6d 20h played, 1h 15m at 60" (`played.total` and `played.level`, each plus seconds since `played.atEpoch`).
- With gate I, a second line: lifetime pulls, deaths and wipes of the character.
- Levels table: Level, Reached, Zone. Only rows with a date. Exact: "Fri 20 Nov, 22:49". Bound within a day: "Tue 17 Nov", tooltip "Between 17:02 and 20:06". Bound over days: "18 to 19 Nov". Levels that share one bound are one row: "30 to 37". One muted line under the table: "N levels have no recorded date."
- A bound comes from the stored session records: a level was reached after every stored moment the character was still below it (the start and the end of a session, an exact date of a lower level) and before every stored moment it was already on it. A record whose level was not read says nothing.
- On the save: 21 exact dates (60, 59, 58, 57, 54, 53, 51, 50, 49, 47, 46, 45, 44, 41, 40, 39, 29, 28, 27, 3, 2) and 9 bound rows: 55 to 56 (18 to 19 Nov), 52 (Tue 17 Nov, between 17:02 and 20:06), 48 (15 to 16 Nov), 42 to 43 (12 to 13 Nov), 38 (Wed 11 Nov), 30 to 37 (8 to 11 Nov), 18 to 26 (5 to 7 Nov), 6 to 17 and 4 to 5 (Thu 5 Nov). No level is without a row.
- `levelAt` **[gate E]** keeps both kinds, copied at every load and before a pickup deletes session records, so a row does not fade with the next pickup.

**Removed in the very next build, before anything else:** the columns Time at level, Played by then and Vs previous with their green and red faster/slower deltas. The stored played stamps are overwritten at every login, so every one of those values is wrong except level 60. Gate E fixes the stamp and discards the wrong ones; the columns return only when a third of the rows have an exact stamp (rule 0.3), with no version sentence in between.

**Cut at max level.** All cards (PLAYED, TIME AT 60, QUESTS, Gold per hour, Dungeon runs). The Quests table. Any "all time" label. "Level 60" twice.

**Leveling character.** Hero and XP bar as Now. Cards PLAYED and TIME AT LEVEL. The Levels table as above. The Quests table with header "QUESTS SINCE <oldest stored date>", never "all time".

### 3.2 Character > Reputation

**Why I open it.** How far to the next standing, and what moved.

**The answer.** "Barkskin Burrow +1,005 yesterday" (`story.rep`): the first row of the list, the faction and the sum of its gains on the last day it gained ("on Thu 19 Nov" for an older day). The number is a day's sum, so the line never says "last gain". Left out when no row shows a gain.

**Columns.**

| Column | Content |
|---|---|
| Faction | name |
| Standing | "Revered" |
| Progress | bar and what is left: "16,072 to Exalted" (21,000 minus 4,928). Tooltip "4,928 / 21,000". At the top standing: "Exalted" and a full bar. "Not known yet" when the client does not answer for the faction; the column is left out while it answers for none. |
| Last day gained | "+1,005 · Yesterday": the sum of what the faction gained on the calendar day of its newest stored gain, and that day. Blank when none is stored. Also blank (hover "Last day gained: Not recorded", rule 0.2) when a stored gain of the faction names no character and lies on that day or later: the day's total cannot be said, and neither a smaller number nor an older day is shown. |
| This session | only when a faction gained this session (rule 0.3) |

**Order.** Factions with a shown gain first: by the day of the last gain, newest first, then by what that day brought, largest first. Then the rest by standing (a faction whose cell is blank stands here). Neutral factions with no stored gain go last, muted. No fold row.

**Chevron.** Only on a faction with stored gains; it opens the gain history ("GAINS SINCE THU 19 NOV", the sum on the right; When, Source, Amount; a gain with no stored source has a blank Source cell). When a stored gain of the faction that names no character lies on the first listed day or later, the header is "GAINS" alone: no start and no sum. Other rows do not open.

Rows count only gains that carry this character's id **[gate F: `g`]**. New rows are written with it. On older rows the load writes it, and so does every pickup before it deletes session records, from the row's session record or, with the record gone, from a craft or recipe in the character's own block with the same session id. A row neither proves is counted for no character.

**Empty.** "No faction met yet."

### 3.3 Character > Professions

**Why I open it.** Skill now, and what my last crafting rounds made.

**Profession rows.** Name, "297 / 300", rank, bar. No headline above them. Recipes per profession appear only when read from the open profession window **[gate F: `recipeBook`]**. Never "0 recipes learned".

**Crafted table.** Header "CRAFTED SINCE THU 12 NOV", meta "1,012 items" (units only; crafts and caps are not mentioned). Columns When, Item (with "x49"), Profession. The stored list holds 1,000 rows; once it is full its oldest day is cut (on the save Wed 11 Nov: 25 of 148 crafts left), so that day is not listed and not counted, and the header names the first whole day. A craft whose spell no stored row gives a profession is no profession craft ("Courier's Shipment") and is not listed either. 1,038 stored items less 25 less 1 are 1,012.

One row per batch: consecutive crafts of the same spell and session at most 60 s apart. The profession is the one a stored row of that spell names, so the first craft of a round, often stored with none, stands in its batch ("15:46 to 15:47 Tin Bar x29 Mining"), never as a row of its own with a blank cell. When "23:46 to 23:48" or one time. Day rows count items: "YESTERDAY · 111 ITEMS" (a batch counts on the day of its last craft). On the save: 52 batches; newest: Truesilver Bar x6 23:50, Gold Bar x3 23:49, Mithril Bar x49 23:46 to 23:48; day rows 111, 72, 47, 257, 29, 20, 44, 28, 404. New crafts are merged at write time **[gate F: `t1`]** so the list holds months.

**Cut.** The "137 recipes learned" headline. The Recipes learned table (126 of 137 rows have no profession; it returns with `recipeBook`). "N from other professions". "Other" for a missing profession. "(older crafts no longer stored)".

**Not in this pass.** What a skill-up cost and what to learn next: both need trainer and recipe reference data. Noted for a later proposal.

**Empty.** "No profession learned yet." With nothing crafted the Crafted section is left out.

---

## 4. Loot

### 4.1 Loot > Items

**Why I open it.** What dropped, from whom, where.

**Header.** "ITEMS SINCE TUE 17 NOV", meta "89 pickups green or better, not every item is kept" (review round 1; was "91 green or better"). That is the only place the date and the count appear. No answer line.

**Controls.** Quality filter (default green and better), search, and List / By item. By item stays: one row per item with Item, Count and Last looted, for "how many of these did I farm".

**Columns.** When, Item (with "x3"), From, Place, Coords (WIDE). The pickups of one item in one minute that read the same are one row with the counts summed (display only).

| Cell | Rule |
|---|---|
| From, named | as stored |
| From, quest | "Quest: <name>" |
| From, container | "Container" (stored guid starts with `Item-`; 9 rows on the save, all opened containers such as Linken's Training Sword and the Hakkari pieces, no ore or herb) |
| From, Creature or an enemy | blank, tooltip "From: Name not recorded" (review round 2; was "Enemy") |
| From, the item's own name (a gathered node) | blank |
| From, Picked up or Unknown source | blank |
| Place | the zone stamped with the row. Blank for a row that arrived without a loot window before the capture fix: its stored place came from the previous loot window and can be wrong, so it is not shown at all. |

Inside a run page the From rule of 2.2 applies; this list does not infer bosses.

**Cut.** Auction and mail rows (they are purchases and deliveries; Loot > Gold > Auction house owns them). The Value column, vendor price and "paid" alike. The Qty column. The shown words "an enemy", "Creature", "Picked up", "Unknown source". "nothing green or better yet" when the list has rows. "ALL ITEMS".

**Capture [gate G].** New rows stamp the place at pickup when no loot window was open, carry `map`, and are marked `pushed`. Old rows stay as written.

**Empty.** "No item stored yet." No match: "No item matches this filter."

### 4.2 Loot > Gold

**Why I open it.** Am I up or down, and from what.

**Controls.** Period: Session, Today, Week, All. View: Sources (default), Auction house, Journal. Three views, no dropdown.

When gold history starts inside the chosen period, the section header carries the real range instead of the period word: "SINCE WED 18 NOV 20:35", not "WEEK". On the save, Week is 2.5 days.

**Cards.** No answer line above them; NET is the answer.

| Card | Value | Meta | Source |
|---|---|---|---|
| BALANCE | "12s 19c" | "all characters 12g 0s" | `gold.balance` (1,219 and 118,859 copper) |
| EARNED | "+8g 47s" | "X not traced" when above 0, else "mostly <source>" | day rows, `goldLog` |
| SPENT | "-30g 99s" | "X not traced" when above 0, else "mostly Auction house" | same |
| NET | "-22g 51s" | per hour only after 30 minutes of play in the period | same |

"Not traced" is gold that moved with no source seen (`unexplained`, `other`). It sits on the cards because it decides how far the rest can be trusted. The earlier derivation gives +13g 41s in and -50g 36s out; the period those belong to is pinned in `tests/real_save.lua` before the build, and the cards show the figure of the chosen period only. Gate H is what shrinks it. No entry counts on any card. No notes under the cards.

**Sources view.** Columns Source, Mostly from (largest group of the source, with its amount only when it is a part of the source's total; for Auction house the item, "Black Lotus x3", from `loot.ah`; blank when the kept journal rows do not add up to the total), Amount. Labels "Source not seen" (in) and "Spending not explained" (out).

Until gate H is built, group coin in dungeons can be booked as mail or with no source. So a period that contains time inside a dungeon from before the H fix does not offer Sources: the view opens on Journal and the Sources button is disabled with the tooltip "Sources are not reliable for dungeon time before <date>". This is the screen's one history line. It is the reason H is recommended for the first batch (section 6).

**Journal view.** Auction rows read "Bought Black Lotus x3" / "Deposit: Iron Bar x17". Day headers are calendar days and carry the day's net ("YESTERDAY · -114g 54s") only when the kept rows add up to the day rows of both gold days the calendar day lies in (review round 3, above); else the bare day. A first day that starts mid-day says "WED 18 NOV, FROM 20:35" when no listed row of the day is older. Detail never shows a raw id or a placeholder word.

**Auction house view.**
- Answer: "Spent 30g 98s, received 5g 97s, net -25g 0s".

  | Word | Definition | Save (session) |
  |---|---|---|
  | Spent | everything paid at the auction house, `ledger.auctions` | 309,865 copper |
  | Received | what auction mail paid out, `ledger.auctionSales`: sale prices minus the house cut plus deposits returned | 59,773 copper (5g 87s sold, minus 29s cut, plus 39s deposits) |
  | Net | Received minus Spent | -250,092 copper |

  The line uses Received and not the gross "sold 5g 87s", so the three figures add up on sight. The tooltip has sold, cut and deposits. `tests/real_save.lua` asserts both identities in copper.
- Columns When, Item (with "x3"), Result, Price. Player appears only by rule 0.3.
- One auction is one row: Sold, Expired or Cancelled stands for its posting. "Posted" only while the auction can still be open; the duration is in the hover (review round 2).
- No row without an item: a purchase with no item of its own is named by the invoice of an auction mail of its session with exactly its price, else it is not listed (review round 2).
- One purchase is one row. A delivery mail is absorbed by the priced row of the same item (earlier, in the same session or within 1 hour, enough count left). A delivery with no priced row reads "Collected" with a blank Price, the mails of one item taken together as one row (review round 1; was "within 1 hour" and "Won").
- Sold rows: Price is what the buyer paid. A sold row is named by its invoice. A stored row whose item was guessed the old way ("the newest unnamed row") shows a blank Item cell, tooltip "Not recorded": a guess is not shown as a fact.

**Cut.** The Zones, Days and Runs views (Zones: per hour figures from single quest turn-ins mean nothing; Days: folded into Journal day headers; Runs: Dungeons owns it as Worth). The "More / Break down by" dropdown. The answer line above the cards. Entry counts. The Times and Share columns. The review chip (it offered no action). The Duration and Qty columns. The caption about uploaded sessions. All three under-card notes.

**Empty.** "No gold has moved in this period."

---

## 5. Settings

General and Gold display: unchanged from `UX_OVERHAUL.md` 4.12.

**Data and sync**, section "CAPTURE HEALTH", in this order:

| Row | Text | Source |
|---|---|---|
| Status | "CAPTURING in Orgrimmar" | live |
| Saved to everbuff.gg | "142 pulls, confirmed Sat 21 Nov 11:45" (the same fact and the same hover as the card on Now, 1.1: the time is the confirmation's, never the save's) | `combat.lastAck` |
| Pulls waiting | "0" | `combat.fights` not yet picked up |
| Loot | "1,539 pickups" | `loot.log` |

The rows are a two column list: the label at the left, every value on one shared x. No row carries a separator of its own. Combat log and Advanced combat logging follow in the same form ("on", "off").

Never seen a pickup: "Not seen yet", tooltip as on Now.

**Advanced** (collapsed): the "Paste the code from the desktop app" box (a fallback, the pickup is automatic) and the Clear buttons. Clear is hidden for a store with nothing in it and never resets the pull counter (`combat.fightSeq` stays monotonic).

**Cut.** The Events row and its Clear. The Sessions row. The words Recording and RECORDING.

---

## 6. Gates and build order for issue #57

Display-only work can be built on approval of this document. Each gate needs its own yes, the data contract document and the contract tests.

| # | Item | Screens | Kind | Batch |
|---|---|---|---|---|
| C | Keep acked session records (counters only) instead of deleting them | 1.2 | ack behaviour, backend contract | 1 |
| I | Lifetime counters per character (pulls, deaths, wipes) and pickup history | 1.1, 3.1 | new fields | 1 |
| A | `dungeonLegacy`: rebuilt runs in the one Runs table | 2.1, 2.2, 1.2 | new save key | 1 |
| J | Boss to dungeon reference table: real boss totals, 13 older clears by name | 2.1 | reference data | 1 |
| B | Loot source by boss kill timing (90 s), "Trash" included, or blank | 2.2 | inference wording | 1 |
| E | `levelAt`, the played stamp fix, discarding the wrong stamps | 3.1 | new field, migration | 1 |
| H | Gold capture: #52 mail fallback and split group shares | 4.2 | capture | 1 (recommended, see 7) |
| D | Group size and party names with classes on every run | 2.2 | capture | 2 |
| F | Character id on reputation rows; `recipeBook`; craft batches at write (`t1`) | 3.2, 3.3 | new fields | 2 |
| G | Loot rows: place at pickup, `map`, `pushed`; no placeholder source stored | 4.1 | capture | 2 |
| K | Who in the group got which item (other players' loot lines) | 2.2 | capture, new | 2, needs its own proposal |

**Order.**

1. Trust killers, display only, one build (table below).
2. Gates C and I. No wording about missing history is written before they are in.
3. Chrome (0.4), cuts and column rules of sections 1 to 5.
4. Gates A, J, B, E, then H.
5. Batch 2.

**Must not ship again (step 1).**

| Visible today | Fix |
|---|---|
| Leveling "Time at level / Played by then / faster, slower" | columns removed (3.1) |
| "solo" on the Blackrock Spire run | size shown only when stored (2.2) |
| "7 of 7 bosses" | "7 bosses" until a real total (2.1) |
| Runs "22" on 17 Nov | old counter never printed (1.2) |
| "Dungeon runs 1, all time", "Quests 37, all time" | cards cut (3.1) |
| "0 recipes learned" | recipe text only from `recipeBook` (3.3) |
| "you did not die" from an empty list | tab hidden when empty (1.4, 1.5) |
| Gold per hour from under 30 minutes | 30 minute floor (1.1, 4.2) |
| Loot place taken from the last loot window | cell blank (4.1) |

Each row gets a test in `tests/real_save.lua` that fails on the old text.

Open thresholds for the founder: the 5 minute session join; the 30 minute floor for per hour figures; the one-third column rule; the 90 s boss window of gate B.

---

## 7. Where this revision does not follow the review

| Review point | What this document does | Why |
|---|---|---|
| Durations over 10 minutes in minutes, everywhere | Boss splits and kill clocks keep seconds ("19m 39s") | Splits are compared run against run; a 40 second gain is the point of the column. Sums and lengths follow the rule. |
| Hide a column when under a third of visible rows have a value | Counted over the rows of the list after filters, not the rows in view | Counting the scroll viewport would make columns appear and vanish while scrolling. |
| Auction answer "Spent 30g 98s, sold 5g 87s, net -25g" | "Spent 30g 98s, received 5g 97s, net -25g 0s" | With the gross sale price the line does not add up (the gap is the house cut and returned deposits). Received is what the mail paid, and the identity is tested in copper. |
| Fold Fights into Sessions and the run page | Run page yes; otherwise the tab simply disappears while the store is empty | Sessions has no detail page today; adding one is a new screen. The review offers hiding as the alternative. |
| Cut the Deaths tab until the killer can be named | Tab hidden unless a stored death names its killer | Open-world deaths do name the killer, which is what a leveling alt wants. At 60 in dungeons the tab is gone, as asked. |
| "Do not show Sources for periods before the fix" with H to follow later | Same rule, but H moved into batch 1 | Until H is built the rule disables the default view of the most important screen for any period with dungeon time. |
| Items "Value: keep only at WIDE, or cut" | Cut | One meaning could not be kept once auction rows leave, and vendor price on greens and blues is noise at 60. |
| "0:00" overlay is a bug nobody listed | Listed as the first build item, origin not yet proven | No addon code draws a bare clock; it has to be reproduced before it is called ours. |
| "What the run was worth: coin plus vendor value plus the best drop" | Worth is coin plus vendor value; the best drop is its own cell | A blue has no stored market price, so it cannot be added into a sum. |
