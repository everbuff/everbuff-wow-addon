-- The Dungeons, Fights, Deaths, Character, Gold, Items and Data and sync screens on a real save, against numbers worked out from that save by
-- hand (docs/UX_PRAGMATIC.md: "Example numbers come from the founder's save of 21 Nov 2026 ... derived with throwaway
-- scripts and not through addon code"). A player's save is private, so this is not part of tests/run_tests.lua:
--
--   EB_SAVE=<EverbuffJournal.lua of 21 Nov 2026> luajit tests/real_truth.lua
--
-- It boots the addon on the save as tests/dump_real.lua does (tests/real_save.lua), opens the pages and compares.
-- Without EB_SAVE it says so and passes: nothing to check. The expected values below are for that one save; another
-- save fails them by design.
package.path = "tests/?.lua;" .. package.path
local SAVE = os.getenv("EB_SAVE")
if not SAVE or SAVE == "" then print("real_truth: EB_SAVE is not set, nothing checked"); os.exit(0) end
local M = require("wow_stub")
local G = dofile("tests/geometry.lua")
local Real = dofile("tests/real_save.lua")
G.install(M, {})
local S = Real.boot(M, { save = SAVE, now = os.getenv("EB_NOW"), char = os.getenv("EB_CHAR") or "Iron", boot = os.getenv("EB_BOOT") })
local ns = S.ns
local say = print
print = function() end
local UI, T, R, D = ns.UI, ns._test, ns.Runs, ns.Dungeons.D
local pass, fail = 0, 0
local function check(name, cond, detail)
  if cond then pass = pass + 1 else fail = fail + 1; say("FAIL  " .. name .. (detail ~= nil and ("   -> " .. tostring(detail)) or "")) end
end
local function eq(name, got, want) check(name, got == want, ("got %s, want %s"):format(tostring(got), tostring(want))) end
local function strip(s) return (tostring(s or ""):gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%s+", ""):gsub("%s+$", "")) end
local function shown(tbl) local out = {}; for i = 1, tbl.shownN or 0 do local r = tbl.rows[i]; if not (r.item and r.item.ebSection) then out[#out + 1] = r end end return out end
local function hostOf(name) for _, tab in ipairs(T.tabs) do if tab.name == name then return tab end end end
UI.SetWindowSize(1104, 697)

local c = ns.char()
-- ── the stored data itself (the boot copies the gold runs with no run record, once) ──
eq("save: one run record", #c.dungeonRuns, 1)
eq("save: five rebuilt rows", #c.dungeonLegacy, 5)
local ids = {}
for _, r in ipairs(c.dungeonLegacy) do ids[#ids + 1] = r.inst .. "@" .. r.t end
eq("save: the rebuilt rows", table.concat(ids, " | "), "Maraudon@1795033978 | Blackrock Depths@1795082920 | Blackrock Depths@1795099037 | Blackrock Depths@1795118469 | Blackrock Spire@1795165611")
check("save: no pull is stored, and the last pickup took 142", #ns.DB.combat.fights == 0 and ns.SyncState().ackFights == 142 and ns.SyncState().ackAt == 1795257911)

-- ── Dungeons > Runs ──
Real.open(S, "dungeons/runs"); M.settle()
local lv = T.dungeonList(); M.settle()
local rows = shown(lv.tbl)
eq("Runs: six rows", #rows, 6)
eq("Runs: the hero", lv.heroVerdict, "7 bosses in 1h 9m")
check("Runs: no summary line (0 instances this hour, no lockout)", lv.summaryN == 0)
-- (the oldest stored run is the rebuilt Maraudon row, t = 1795033978, Wed 18 Nov 21:32; the header says so once)
eq("Runs: the section header says where the list starts", lv.section.label.text, "RUNS SINCE WED 18 NOV")
eq("Runs: from the oldest listed row", lv.since, 1795033978)
do
  local cells = {}
  for _, r in ipairs(rows) do cells[#cells + 1] = r.c.dur.text end
  eq("Runs: the Time column, every cell in minutes (2,010 s is 33m, never 33m 30s)", table.concat(cells, " | "), "1h 9m | 1h 14m | 33m | 2h 33m | 2h 20m | 1h 10m")
end
local top = rows[1]
-- (the coin of the stored run is what the purse gained inside, quest coin aside: 18,835 copper, which is the sum of
-- the 97 "Your share of the loot is" lines of the chat log in the run's window. The addon booked 11,612 as looted.)
check("Runs: the stored run: Blackrock Spire, 1h 9m, worth 19g 92s 34c (18,835 + 180,399 copper)", top and top.run.name == "Blackrock Spire" and not top.run.legacy and top.c.dur.text == "1h 9m"
  and top.c.worth.text == UI.money(199234) and UI.money(199234) == UI.money(199200) and UI.money(199234) ~= UI.money(192011), top and top.c.worth.text)
-- (a rebuilt row stores the booked coin only and no purse figure. The chat log says the runs paid 23,469, 7,930,
-- 75,411, 58,655 and 11,421 copper where 14,926, 795, 53,083, 38,404 and 365 were booked: the coin is not known from
-- the save, so Worth is the vendor value of the items alone and the hover says the coin is not counted.)
local want = { { "Blackrock Spire", 4490, 159344 }, { "Blackrock Depths", 2010, 30204 }, { "Blackrock Depths", 9220, 518686 },
  { "Blackrock Depths", 8430, 438828 }, { "Maraudon", 4250, 93437 } }
for i, w in ipairs(want) do
  local r = rows[i + 1]
  check(("Runs: rebuilt row %d: %s, %d s, worth %d copper"):format(i, w[1], w[2], w[3]), r and r.run.legacy and r.run.name == w[1] and r.run.inside == w[2] and (D.worth(r.run)) == w[3]
    and r.c.worth.text == UI.money(w[3]) and strip(r.c.name.text) == w[1] .. " partial", r and (r.run.name .. " " .. tostring(r.run.inside)))
  local tips = r and table.concat(lv.tipLines(r.run), " | ") or ""
  check(("Runs: rebuilt row %d: the hover names no coin amount and says the coin is not counted"):format(i), tips:find(D.NO_COIN, 1, true) ~= nil and tips:find(" coin \194\183", 1, true) == nil
    and tips:find("Worth: " .. UI.money(w[3]) .. " items at vendor prices", 1, true) ~= nil, tips)
end
do
  local m = rows[6] and rows[6].run
  check("Runs: Maraudon never prints its booked 3s 65c as the run's coin", m and select(2, D.coinOf(m)) == "none" and D.worthParts(m) == UI.money(93437) .. " items at vendor prices", m and D.worthParts(m))
end
check("Runs: Vs best, Bosses and Deaths are left out while five of six rows are partial", lv.colHidden.vs and lv.colHidden.boss and lv.colHidden.death)
check("Runs: there is no By dungeon tab", D.byVisible() == false and hostOf("Dungeons").ctl.hidden.bydungeon == true)

-- ── the run page ──
local dv = T.dungeonDetail()
T.openRun(c.dungeonRuns[1]); M.settle()
check("Run: META: level 58, no solo, no group, no party", dv.metaText:find("15:14 to 16:31", 1, true) ~= nil and dv.metaText:find("level 58", 1, true) ~= nil and dv.metaText:find("solo", 1, true) == nil
  and dv.metaText:find("group", 1, true) == nil and dv.metaText:find("party", 1, true) == nil, dv.metaText)
eq("Run: TIME", dv.card.time.value.text, "1h 9m")
eq("Run: TIME meta", dv.card.time.meta.text, "7m 59s dead or outside")
eq("Run: BOSSES", dv.card.bosses.value.text, "7")
eq("Run: BOSSES meta", dv.card.bosses.meta.text, "boss clock 1h 3m")
eq("Run: XP", dv.card.xp.value.text, "62,388")
eq("Run: XP meta", dv.card.xp.meta.text, "54,146 per hour")
eq("Run: WORTH is 19g 92s (18,835 + 180,399 copper)", dv.card.worth.value.text, UI.money(199234))
-- The page under the cards: no XP section, no purse line. The character is level 60 on this save: "about 7 more runs
-- to level 60" was a forecast from the kill XP (ceil(209,800 x (1 - 0.029) / 30,716) = 7), false since 20 Nov 22:49.
do
  local words = {}
  for _, fs in ipairs(dv.lines) do if fs.shown ~= false and type(fs.text) == "string" then words[#words + 1] = strip(fs.text) end end
  for _, k in ipairs({ "time", "bosses", "xp", "worth" }) do words[#words + 1] = tostring(dv.card[k].value.text) .. " " .. tostring(dv.card[k].meta.text) end
  for k, sec in pairs(dv.sections) do if sec.shown ~= false then words[#words + 1] = "[" .. k .. "]" end end
  local page = table.concat(words, "\n")
  check("Run: the page forecasts no runs to a level", page:find("more run", 1, true) == nil, page)
  check("Run: no XP section, no kill count, no second XP figure", dv.sections.xp == nil and page:find("[xp]", 1, true) == nil and page:find("243", 1, true) == nil
    and page:find("from kills", 1, true) == nil and select(2, page:gsub("62,388", "")) == 1, page)
  check("Run: no purse line under the loot (the WORTH card has the coin)", dv.purseLine == nil and page:find("gained inside", 1, true) == nil, page)
  check("Run: the WORTH card's coin is 1g 88s, never the booked 1g 16s", tostring(dv.card.worth.meta.text):find(UI.money(18835) .. " coin", 1, true) == 1 and page:find(UI.money(11612), 1, true) == nil, dv.card.worth.meta.text)
  eq("Run: the coin is the purse figure", select(2, D.coinOf(dv.run)), "purse")
  check("Run: no ENTERED AND LEFT section, no visit count, no third clock, no combat total", dv.sections.visits.shown == false and dv.visitsShown == false and dv.tables.visits.frame.shown == false
    and page:find("[visits]", 1, true) == nil and page:find("Active", 1, true) == nil and page:find("in combat", 1, true) == nil and page:find("visit", 1, true) == nil
    and page:find("running back", 1, true) == nil, page)
  do
    local tl = table.concat(lv.tipLines(dv.run), " | ")
    check("Run: the TIME hover splits the 7m 59s (running back 2m 38s, outside 5m 21s) and names no Active clock or re-entry count",
      tl:find("Inside 1h 9m | Run back 2m 38s | Outside 5m 21s | Ended", 1, true) == 1 and tl:find("Active", 1, true) == nil and tl:find("Re-entered", 1, true) == nil, tl)
  end
  eq("Run: the XP hover has the split and the levels (30,716 + 31,672 = 62,388; 58.7 to 59.0)", table.concat(dv.xpTip, " | "),
    "XP earned inside, and per hour of the time inside. | 30,716 from kills, 31,672 from quests. | Level 58.7 to 59.0.")
  eq("Run: the WORTH hover says where the coin comes from (18,835 copper) and what was booked as loot (11,612)", dv.purseTip,
    "Coin is what your purse gained inside, quest rewards aside: " .. ns.fmtMoney(18835) .. ". Of it " .. ns.fmtMoney(11612) .. " was seen as loot when it was picked up.")
end
local br = shown(dv.tables.bosses)
local BOSS = { { "Highlord Omokk", "19m 39s", "19m 39s", "43s" }, { "War Master Voone", "23m 50s", "4m 11s", "28s" }, { "Shadow Hunter Vosh'gajin", "28m 36s", "4m 46s", "1m 26s" },
  { "Mother Smolderweb", "42m 52s", "14m 16s", "35s" }, { "Halycon", "1h 4m 44s", "21m 52s", "27s" }, { "Gizrul the Slavener", "1h 5m 35s", "51s", "42s" },
  { "Quartermaster Zigris", "1h 9m 3s", "3m 28s", "37s" } }
eq("Run: seven boss rows", #br, 7)
for i, b in ipairs(BOSS) do
  local r = br[i]
  check(("Run: boss %d: %s, killed at %s, split %s, fight %s"):format(i, b[1], b[2], b[3], b[4]), r and r.c.boss.text == b[1] and r.c.at.text == b[2] and r.c.since.text == b[3] and r.c.len.text == b[4],
    r and (r.c.boss.text .. " | " .. r.c.at.text .. " | " .. r.c.since.text .. " | " .. r.c.len.text))
end
-- (the run record's own times down are 165 s and 74 s; the story event of the second death says 73 s)
eq("Run: the deaths line", dv.deathLine, "Deaths: 16:12 (2m 45s down) \194\183 16:30 (1m 14s down)")
-- (8 rows green or better: 6 with a source, and Prismcharm and Engraved Cape of the Gorilla stored "Picked up" with no
-- boss kill near. By the chat log the first was the reward of "Urok Doomhowl" at 15:29:43 and the second a drop won
-- by roll at 16:01:39; the save cannot tell them apart, so the header counts neither as a drop.)
eq("Run: 8 rows green or better", #dv.lootItems, 8)
eq("Run: the LOOT header claims 6 drops and names the 2 it cannot source", dv.sections.loot.meta.text, "6 drops green or better, 2 with no recorded source")
eq("Run: Killed at says it is on the run's clock, which stood still for the 5m 21s outside (Omokk: 25m 0s after entering)", dv.tables.bosses.spec[3].tip, D.KILL_TIP)
eq("Run: the wall time of Omokk's kill is 15:39:01", ns.Runs.wallOf(c.dungeonRuns[1], c.dungeonRuns[1].bosses[1].kill), 1795184041 + 1500)
check("Run: the TIME hover's last kill is 16:28 on the wall clock, not 16:23 (entry plus the run's clock)", tostring(dv.clockSentence):find("last kill 16:28", 1, true) ~= nil
  and tostring(dv.clockSentence):find("first pull 15:25", 1, true) ~= nil, dv.clockSentence)
eq("Run: the rest is one line", dv.lootMore, "29 more: 21 white, 8 grey")
local from = {}
for _, it in ipairs(dv.lootItems) do from[strip(ns.Now.stripLink(it.row.item))] = it.from or "" end
local FROM = { ["Slamshot Shoulders"] = "Highlord Omokk", ["Talisman of Evasion"] = "War Master Voone", ["Slashclaw Bracers"] = "Halycon", ["Rhombeard Protector"] = "Gizrul the Slavener",
  ["Bracers of Valor"] = "Trash", ["Nightshade Cloak of the Gorilla"] = "Trash", ["Prismcharm"] = "", ["Engraved Cape of the Gorilla"] = "" }
for item, src in pairs(FROM) do eq("Run: From of " .. item, from[item], src) end
dv.d.Close()

-- ── Home: no Fights tab, no Deaths tab ──
UI.Open("Home", "fights"); M.settle()
local home = hostOf("Home")
check("Home: no Fights tab while no pull is stored", home.ctl.hidden.fights == true and home.ctl.active ~= "fights", tostring(home.ctl.active))
UI.Open("Home", "deaths"); M.settle()
check("Home: no Deaths tab while no stored death names its killer", home.ctl.hidden.deaths == true and home.ctl.active ~= "deaths", tostring(home.ctl.active))
eq("Home: a hidden tab falls back to Now, whatever was open", home.ctl.active, "now")
UI.Open("Home", "sessions"); M.settle()
eq("Home: Open on the hidden Deaths tab reports false", UI.Open("Home", "deaths"), false); M.settle()
eq("Home: and lands on Now from Sessions too", home.ctl.active, "now")
eq("Home: no Activity pane (0.5, 1.3)", home.paneByKey.activity, nil)
UI.Open("Home", "activity"); M.settle()
eq("Home: the old Activity key opens Now", home.ctl.active, "now")
-- ── Home > Now at the level cap (1.1) ──
do
  local nv = T.journeyRefresh(); M.settle()
  eq("Now: the title is the whole name", nv.hero.title.text, "Iron Hart")
  check("Now: who that is, beside the name", tostring(nv.hero.titleMeta.text):find("^Level 60 ") ~= nil and tostring(nv.hero.titleMeta.text):find("Orgrimmar", 1, true) ~= nil, nv.hero.titleMeta.text)
  -- (this session is two logins, 11:45:25 to 11:46:31 and 11:47:01 on, 30 s apart: one session, docs 0.2.4 and 1.1.
  -- The first earned 84,773 copper (8 auction sales and a mail), the second spent 281,985 + 27,880 + 45 = 309,910.)
  eq("Now: this session is its two logins", #ns.Gold.joined(), 2)
  eq("Now: the hero is the session's gold, -22g 51s", nv.hero.hero.text, UI.money(-225137, true) .. " this session")
  eq("Now: no per hour figure 11 minutes into the session", strip(nv.hero.meta1.text), "")
  -- (played: 66 s of the first login, 1795257925 to 1795257991, and the second from 1795258021 on: 627 s at the
  -- save's last second. The 30 s logged out between them are not played.)
  check("Now: the session ledger behind it: +84,773, -309,910, played 66 s + the second login so far", nv.sessionGold.gained == 84773 and nv.sessionGold.spent == 309910 and nv.sessionGold.net == -225137
    and nv.sessionGold.played == 66 + (S.now - 1795258021) and nv.sessionGold.played < 1800 and nv.sessionGold.perHour == nil, nv.sessionGold.played)
  local labels, byKey = {}, {}
  for i, d in ipairs(nv.cardDefs) do labels[i] = d.label; byKey[d.key] = nv.cardRow.cards[i] end
  eq("Now: the cards, each with a value: no XP per hour, no DEATHS at 0", table.concat(labels, " | "), "Balance | Played | Last run | Saved to everbuff.gg")
  check("Now: BALANCE 12s 19c of 1,219 copper, all characters 120,078", byKey.balance.value.text == UI.money(1219) and byKey.balance.meta.text == "all characters " .. UI.money(120078), byKey.balance.meta.text)
  check("Now: PLAYED has no second line", strip(byKey.played.meta.text) == "" and tostring(byKey.played.value.text):find("^%d+m$") ~= nil, byKey.played.value.text)
  -- (66 s + 561 s = 627 s = 10m 27s at 11:56:22, the save's last second: "10m". The span from the first login,
  -- 657 s, would read "11m" and count the 30 s logged out as played.)
  eq("Now: PLAYED is the two logins added up", byKey.played.value.text, UI.fmtPlayed(66 + (S.now - 1795258021)))
  eq("Now: 10m 27s at the save's last second reads 10m", UI.fmtPlayed((1795257991 - 1795257925) + (1795258582 - 1795258021)), "10m")
  if S.now == 1795258582 then eq("Now: the card says 10m on the save", byKey.played.value.text, "10m") end
  do
    local tipText = type(nv.cardDefs[2].tip) == "table" and nv.cardDefs[2].tip.text or ""
    check("Now: the PLAYED hover says the logins are added up, not a span", tipText:find("its 2 logins added up", 1, true) ~= nil and tipText:find("from the first", 1, true) == nil, tipText)
  end
  check("Now: LAST RUN is the stored Blackrock Spire run", byKey.run.value.text == "Blackrock Spire" and ns.Now.lastRun().meta == "Fri 20 Nov \194\183 1h 9m \194\183 7 bosses \194\183 2 deaths", ns.Now.lastRun().meta)
  check("Now: the card's line is never cut: it fits the card or drops the day", not byKey.run.meta:IsTruncated(), byKey.run.meta.text)
  -- (lastAck.at = 1795257911 is when the addon applied the confirmation at the 11:45 login. The desktop's copy of
  -- the save with these 142 pulls is from 20 Nov 23:54, a time the save does not hold: the card never calls 11:45
  -- the time of the save.)
  check("Now: SAVED TO EVERBUFF.GG is the 142 pulls, and 11:45 is when that was confirmed", byKey.saved.value.text == "142 pulls" and byKey.saved.meta.text == "confirmed Sat 21 Nov 11:45"
    and not byKey.saved.meta:IsTruncated(), tostring(byKey.saved.value.text) .. " / " .. tostring(byKey.saved.meta.text))
  check("Now: no NEXT section with nothing to do", nv.nextHead.shown == false)
  local titles = {}
  for i, it in ipairs(nv.lookList) do titles[i] = it.title .. " / " .. strip(it.meta) end
  eq("Now: WORTH A LOOK is the session's three gold lines, largest first", #nv.lookList, 3)
  check("Now: the largest is the 28g 19s purchase at 11:48, named by its auction row", nv.lookList[1].title == "Bought Black Lotus x3" and nv.lookList[1].meta == UI.money(-281985, true) .. " \194\183 Auction house \194\183 11:48", titles[1])
  -- (the second largest is a sale collected at the first login: the mail paid 28,150 for the 29,000 sale)
  check("Now: the second is the Formula sale collected at 11:45, the third the 2g 78s purchase", nv.lookList[2].title:find("^Sold Formula: Enchant Boots %- Greater Stamina") ~= nil
    and nv.lookList[2].meta == UI.money(28150, true) .. " \194\183 Auction sales \194\183 11:45" and nv.lookList[3].title == "Bought Golden Sansam x20", tostring(titles[2]) .. " ; " .. tostring(titles[3]))
  check("Now: SAVED TO everbuff.gg keeps the brand in lower case inside the label", byKey.saved.label.text == "SAVED TO everbuff.gg", byKey.saved.label.text)
  local words = {}
  for _, r in ipairs(nv.lookRows) do if r.shown ~= false then words[#words + 1] = tostring(r.title.text) .. " " .. tostring(r.meta.text) end end
  local page = table.concat(words, "\n") .. "\n" .. tostring(nv.hero.hero.text) .. "\n" .. tostring(nv.hero.meta1.text)
  check("Now: none of the lines the founder listed", page:find("Keep going", 1, true) == nil and page:find("kills", 1, true) == nil and page:find("Max level", 1, true) == nil
    and page:find("per hour", 1, true) == nil and page:find("Go have fun", 1, true) == nil, page)
end
-- ── the window chrome: the brand and the status word ──
do
  local f = _G.EverbuffFrame
  eq("Chrome: the brand", f.wordmark.text, "everbuff.gg")
  local st = UI.StatusState()
  check("Chrome: the status is CAPTURING (with its warning when there is one), never Recording", st.text:find("^CAPTURING") ~= nil or st.text == "Starting" or st.text == "Standing by", st.text)
end
local dd = T.collectDeaths()
check("Deaths: the save holds exactly the two Blackrock Spire deaths, level 59, 2m 45s and 1m 13s down, no killer", #dd == 2 and dd[1].t == 1795187574 and dd[2].t == 1795188618
  and dd[1].zone == "Blackrock Spire" and dd[1].level == 59 and dd[1].downtime == 165 and dd[2].downtime == 73 and dd[1].killer == nil and dd[2].killer == nil, #dd)

-- ── Home > Sessions: the Runs cell is the run store's, never the old entry counter ──
local L = ns.RunsLegacy
local function sess(id) return ns.DB.sessions[id] end
eq("Sessions: 20 Nov 15:08 holds 1 run", L.inSession(sess("261120150804-41c5")), 1)
eq("Sessions: 19 Nov 15:29 holds 1 run (the rebuilt Blackrock Depths row)", L.inSession(sess("261119152922-c4ed")), 1)
eq("Sessions: 17 Nov 20:34 holds none stored (its old counter said 22)", L.inSession(sess("261117203427-8c86")), 0)

-- ── Home > Sessions (1.2). 45 stored records of the character; 4 start under 5 minutes after the one before ended
-- (21 Nov 11:45 and 11:47, 16 Nov 17:01 and 17:48, 11 Nov 10:46 and 11:19, 5 Nov 03:05 and 03:11), so 41 sessions;
-- 3 of them are under 5 minutes with nothing in them (16 Nov 09:08 76 s, 11 Nov 08:23 17 s, 5 Nov 20:06 131 s).
do
  local Sess = ns.Sessions
  local rows, hidden = Sess.rows()
  eq("Sessions: 38 rows listed, 3 empty ones left out (45 records, 41 sessions)", #rows .. " " .. hidden, "38 3")
  local by = {}
  for _, r in ipairs(rows) do by[r.startedEpoch] = r end
  local top = rows[1]
  eq("Sessions: the newest row is the two logins of 21 Nov, from 11:45:25: 627 s logged in, net -225,137 copper, 0 deaths",
    ("%d %d %d %d %d"):format(top.logins, top.startedEpoch, top.secs, top.net, top.deaths), "2 1795257925 627 -225137 0")
  local r16
  for _, r in ipairs(rows) do if r.logins == 2 and r.level0 == 48 then r16 = r end end
  check("Sessions: 16 Nov 17:01 joins two logins: 4,176 s, 48 to 49, 57,878 XP, +50,725 copper", r16 and r16.logins == 2 and r16.secs == 4176 and r16.level0 == 48 and r16.level == 49
    and r16.xp == 57878 and r16.net == 50725, r16 and (r16.secs .. " " .. r16.xp .. " " .. r16.net))
  local runs, sum = {}, { xp = 0, deaths = 0 }
  for _, r in ipairs(rows) do
    if r.runs and r.runs > 0 then runs[#runs + 1] = UI.fmtStamp(r.startedEpoch) .. "=" .. r.runs end
    sum.xp, sum.deaths = sum.xp + (r.xp or 0), sum.deaths + (r.deaths or 0)
  end
  eq("Sessions: runs only where the run store has one (never the old counters 22, 12, 6, 6, 5, 4, 3)", table.concat(runs, " | "), "Fri 20 Nov 15:08=1 | Thu 19 Nov 15:29=1")
  eq("Sessions: the listed rows hold the 25 deaths and 1,904,466 XP of the stored records", sum.deaths .. " " .. sum.xp, "25 1904466")
  eq("Sessions: the character's totals are above the stored sessions (6,627,648 earned against 3,288,448): a proven gap", Sess.gaps(), true)
  local a = Sess.answer()
  check("Sessions: the answer is the gold history's range: since Wed 18 Nov 20:35, net -808,803 copper, 6 runs", a and a.since == 1795030532 and a.net == -808803 and a.runs == 6,
    a and (tostring(a.since) .. " " .. a.net .. " " .. a.runs))
  UI.Open("Home", "sessions"); M.settle()
  local v = home.paneByKey.sessions.content
  local segs = {}
  for _, sg in ipairs(v.summary.segs or {}) do segs[#segs + 1] = strip(sg.text) end
  eq("Sessions: the answer line", (table.concat(segs, " | "):gsub("%*%*", ""):gsub("\194\160", " "):gsub("%s+", " "):gsub(" | ", "|"):gsub(" |", "|")), "Since Wed 18 Nov 20:35: net -80 88|6 runs")
  eq("Sessions: the header says where the list starts and that it has gaps", v.section.label.text .. " | " .. v.section.meta.text, "SESSIONS SINCE THU 5 NOV | not every session is kept")
  local cols = {}
  for _, col in ipairs(v.tbl.full) do if v.tbl.cols[col.key] and col.key ~= "_chev" then cols[#cols + 1] = col.key end end
  eq("Sessions: columns When, Length, Level, XP, Gold, Deaths (Runs has 4 counts in 38 rows; no Kills)", table.concat(cols, ","), "date,len,lvl,xp,gold,deaths")
  local trs = shown(v.tbl)
  local function line(r) local o = {}; for _, k in ipairs(cols) do o[#o + 1] = strip((strip(r.c[k].text):gsub("\194\160", " "):gsub("%s+", " "))) end return table.concat(o, " | ") end
  eq("Sessions: 38 table rows", #trs, 38)
  eq("Sessions: today's row", line(trs[1]), "11:45 | 10m | 60 |  | -22 51 | 0")
  eq("Sessions: yesterday evening", line(trs[2]), "20:01 | 3h 53m | 59 to 60 | 191,592 | -126 58 | 0")
  eq("Sessions: yesterday afternoon", line(trs[3]), "15:08 | 1h 38m | 58 to 59 | 74,593 | +3 52 | 2")
  local all = {}
  for _, r in ipairs(trs) do all[#all + 1] = line(r) end
  local text = table.concat(all, " / ")
  check("Sessions: no row for the empty logins, and none reads a dash or the old counter", not text:find(" | - ", 1, true) and not text:find("| 22$"), text:sub(1, 200))
  check("Sessions: a level 41 session that earned nothing reads 0 XP (12 Nov 21:22)", text:find("21:22 | 18m | 41 | 0 | -2 56 | 0", 1, true) ~= nil)
  check("Sessions: the joined rows of 16, 11 and 5 Nov", text:find("17:01 | 1h 10m | 48 to 49 | 57,878 | +5 7 | 0", 1, true) ~= nil and text:find("10:46 | 33m | 37 | 19,341 | +6 25 | 1", 1, true) ~= nil
    and text:find("03:05 | 25m | 1 to 3 | 2,604 | +2 53 | 0", 1, true) ~= nil)
end

-- ── Settings > Data and sync ──
UI.Open("Settings"); M.settle()
local d = ns.SettingsView and ns.SettingsView.data
if d then
  ns.SettingsView.refreshData()
  -- one CAPTURE HEALTH block, the four facts first and in this order (docs/UX_PRAGMATIC.md 5)
  local items = ns.SettingsView.data.sections[1].items
  eq("Data: the first section", ns.SettingsView.data.sections[1].head.label.text, "CAPTURE HEALTH")
  check("Data: row 1 is the status, CAPTURING with its place", items[1] == d.rec and d.rec.pairLabel == "Status" and tostring(d.rec.pairValue):find("^CAPTURING") ~= nil, d.rec.plain)
  check("Data: row 2 is the pickup", items[2] == d.syncStatus)
  eq("Data: the pickup", d.syncStatus.plain, "Saved to everbuff.gg: 142 pulls, confirmed Sat 21 Nov 11:45")
  check("Data: row 3 is the pulls waiting", items[3] == d.stored.fights)
  eq("Data: pulls waiting", d.stored.fights.plain, "Pulls waiting: 0")
  check("Data: row 4 is the loot", items[4] == d.stored.loot)
  -- (the size of the store Clear empties, not a count of pickups: of the 1,539 rows 18 are another character's,
  -- 453 are coin, 139 are auction or mail rows, and 929 are the item pickups Loot > Items counts)
  eq("Data: loot", d.stored.loot.plain, "Loot: 1,539 rows stored")
  check("Data: the loot row never says pickups", not tostring(d.stored.loot.plain):find("pickup", 1, true), d.stored.loot.plain)
  eq("Data: the loot row is the raw size of loot.log", d.stored.loot.count, #ns.DB.loot.log)
  do
    -- one format for the six rows: label left, every value on one shared x, no separator mixed with another
    local rowsD = { d.rec, d.syncStatus, d.stored.fights, d.stored.loot, d.combat, d.acl }
    local x0, same, clean = nil, true, true
    for _, r in ipairs(rowsD) do
      local bx = G.resolve(r.value).l - G.resolve(r).l
      x0 = x0 or bx
      if math.abs(bx - x0) > 0.5 then same = false end
      if tostring(r.pairLabel):find("\194\183", 1, true) or tostring(r.pairLabel):find(":", 1, true) or r.value.shown == false then clean = false end
    end
    check("Data: the six CAPTURE HEALTH values start on one x", same, x0)
    check("Data: no label carries a separator", clean)
    eq("Data: the combat log rows read on", d.combat.pairValue .. " | " .. d.acl.pairValue, "on | on")
  end
  check("Data: no Events row; the paste box and the Clears are under Advanced, collapsed", d.stored.events == nil and #ns.SettingsView.data.sections == 2
    and d.pasteRow.shown == false and d.clear.fights.shown == false and d.clear.loot.shown == false and d.stored.fights.btn == nil)
  ns.DB.settings.advancedOpen = true; ns.SettingsView.refreshData(); M.settle()
  check("Data: Advanced open: the paste box, a Clear for the loot (1,539 rows), none for the empty pull store", d.pasteRow.shown ~= false and d.clear.loot.shown ~= false and d.clear.fights.shown == false)
  ns.DB.settings.advancedOpen = nil; ns.SettingsView.refreshData(); M.settle()
  eq("Data: the count of pulls ever recorded is untouched", ns.DB.combat.fightSeq, 6879)
else check("Data: the settings page was built", false) end

-- ── Character > Leveling at the level cap (3.1) ──
Real.open(S, "character/leveling"); M.settle()
do
  local v = ns.Progress.leveling
  eq("Leveling: the title is the whole name", v.hero.title.text, "Iron Hart")
  eq("Leveling: Level 60, once", v.hero.hero.text, "Level 60")
  eq("Leveling: when and where it was reached (session LEVEL_UP row, t = 1795211357)", v.hero.meta1.text, "Reached Fri 20 Nov 22:49 in Mount Hyjal")
  -- (played.total 589,870 and played.level 3,968 answered at 1795258032; the clock of the save is 550 s later:
  -- 590,420 s is 6d 20h, 4,518 s is 1h 15m)
  eq("Leveling: the played time, total and at 60, each plus the time since /played answered", v.hero.meta2.text, "6d 20h played, 1h 15m at 60")
  check("Leveling: no cards and no Quests table at the level cap", v.cardsShown == false and v.cards.shown == false and v.questsShown == false and v.quests.head.shown == false and v.quests.tbl.frame.shown == false)
  local cols = {}
  for _, c in ipairs(v.levels.tbl.spec) do cols[#cols + 1] = c.label end
  eq("Leveling: the Levels columns: no Time at level, Played by then or Vs previous", table.concat(cols, " | "), "Level | Reached | Zone")
  local got = {}
  for _, r in ipairs(shown(v.levels.tbl)) do got[#got + 1] = r.c.level.text .. " | " .. r.c.reached.text .. " | " .. r.c.zone.text end
  local exact, bound = {}, {}
  for _, r in ipairs(v.levelRows) do
    if r.t then exact[#exact + 1] = r.level
    else bound[#bound + 1] = ("%s %d..%d"):format(r.lo < r.level and (r.lo .. "-" .. r.level) or tostring(r.level), r.from, r.to) end
  end
  eq("Leveling: 21 levels have a recorded moment", #exact, 21)
  eq("Leveling: which levels", table.concat(exact, " "), "60 59 58 57 54 53 51 50 49 47 46 45 44 41 40 39 29 28 27 3 2")
  -- (the other 38 levels: each between the end of the last stored session below it and the start of the first one
  -- on it, or inside the stored session that crossed it; levels with the same two moments are one row. The recordings'
  -- own saves confirm the ones they still hold: 52 on 17 Nov 19:21:59, 56 on 19 Nov 01:58:13, 48 on 15 Nov 22:55:29,
  -- 43 on 13 Nov 14:09:56, 38 on 11 Nov 13:32:33.)
  eq("Leveling: the levels known between two stored moments, and those moments", table.concat(bound, " | "),
    "55-56 1795001005..1795098562 | 52 1794931373..1794942362 | 48 1794771363..1794787058 | 42-43 1794516049..1794594976"
    .. " | 38 1794392571..1794402267 | 30-37 1794162027..1794381796 | 18-26 1793905715..1794076317 | 6-17 1793847731..1793905584 | 4-5 1793845932..1793847427")
  eq("Leveling: 30 rows: 21 exact, 9 bounds", #got, 30)
  eq("Leveling: row 1", got[1], "60 | Fri 20 Nov, 22:49 | Mount Hyjal")
  eq("Leveling: row 2", got[2], "59 | Fri 20 Nov, 16:05 | Blackrock Spire")
  eq("Leveling: row 3 (58, from a session record: the event list no longer has it)", got[3], "58 | Thu 19 Nov, 21:58 | Mulgore")
  eq("Leveling: 55 and 56, between Wed 18 Nov 12:23 and Thu 19 Nov 15:29", got[5], "55 to 56 | 18 to 19 Nov | ")
  eq("Leveling: 52, on Tue 17 Nov between 17:02 and 20:06", got[8], "52 | Tue 17 Nov | ")
  eq("Leveling: its hover", ns.Progress.boundTip(1794931373, 1794942362, 1795258582), "Between 17:02 and 20:06")
  eq("Leveling: 30 to 37", got[22], "30 to 37 | 8 to 11 Nov | ")
  eq("Leveling: 6 to 17, all on Thu 5 Nov", got[27], "6 to 17 | Thu 5 Nov | ")
  eq("Leveling: the last row", got[30], "2 | Thu 5 Nov, 03:13 | Tirisfal Glades")
  check("Leveling: every level from 2 to 60 is in a row, so no line counts missing ones", v.noteText == nil and v.levelsMissing == 0, v.noteText)
  check("Leveling: no dash stands for a date", (table.concat(got, "\n") .. "\n"):find("| %- ") == nil and (table.concat(got, "\n") .. "\n"):find("| %-\n") == nil)
  -- gate E: the load copied the moments into the character's block and discarded the played stamps of before 0.9.52
  local c2 = ns.char()
  local nAt, nExact = 0, 0
  for _, r in pairs(c2.levelAt or {}) do nAt = nAt + 1; if r.t then nExact = nExact + 1 end end
  check("save: levelAt holds all 59 levels, 21 of them exact", nAt == 59 and nExact == 21 and c2.levelAt[60].t == 1795211357 and c2.levelAt[60].zone == "Mount Hyjal" and c2.levelAt[58].t == 1795121928, nAt .. "/" .. nExact)
  check("save: the 59 played stamps written before 0.9.52 are gone (each was overwritten at every login)", c2.playedAtLevel == nil and c2.played.total == 589870 and c2.played.level == 3968)
end

-- ── Character > Reputation (3.2). Of the 2,000 stored gains none carries its character in the save. The load
-- writes it on 1,630: 1,441 by their session record, 189 by a craft or recipe of this character that carries the
-- session id of a record the desktop picked up (sessions 261115123253-71eb, 261117184759-c754, 261118202156-96b7).
-- 370 rows of 12 picked-up sessions name no character. Where one of them lies on the faction's last day or after
-- it the cell is blank: Orgrimmar holds 200 counted and 250 uncounted on Fri 20 Nov and is never "+200", Booty Bay
-- has an uncounted +100 on 20 Nov and is never dated 19 Nov. Timbermaw Hold: its 32 gains of Thu 19 Nov are of a
-- proven session (505); the 35 of Wed 18 Nov (330) name no character, a day earlier, so the cell is exact. ──
do
  local withG, mine = 0, 0
  for _, r in ipairs(ns.DB.story.rep) do if r.g ~= nil then withG = withG + 1 end; if r.g == S.guid then mine = mine + 1 end end
  eq("save: the load wrote the character on 1,630 of the 2,000 stored reputation gains, all this character's", withG .. " " .. mine .. " " .. #ns.DB.story.rep, "1630 1630 2000")
end
Real.open(S, "character/reputation"); M.settle()
do
  local v = ns.Progress.rep
  eq("Reputation: the answer", v.answer, "Barkskin Burrow +1,005 yesterday")
  local rows = shown(v.tbl)
  eq("Reputation: 19 factions", #rows, 19)
  eq("Reputation: the header counts them", v.head.meta.text, "19 factions")
  local cols = {}
  for _, col in ipairs(v.tbl.full) do if v.tbl.cols[col.key] and col.label ~= "" then cols[#cols + 1] = col.label end end
  -- (the save holds standings, not the progress inside one, and nothing was gained in the session of 11:45 to 11:56)
  eq("Reputation: no Progress column outside the game, and no This session column with no gain this session", table.concat(cols, " | "), "Faction | Standing | Last day gained")
  local function line()
    local got = {}
    for _, r in ipairs(shown(v.tbl)) do got[#got + 1] = r.c.name.text .. " " .. strip(r.c.standing.text) .. " " .. r.c.last.text end
    return table.concat(got, " | ")
  end
  -- Five factions gained on Fri 20 Nov in session 261120200117-8ce2, whose record names Iron (Gadgetzan's newest
  -- gain is 23:29:32, the others' 21:30:57). Earlier that day (10:31 to 11:26) the save holds gains of the deleted
  -- session 261120094227-2d1c with no character: the day is certain, the day's sum is only a lower bound.
  -- Booty Bay, Everlook, Powderfuse and Ratchet: the newest gain of Iron is Thu 19 Nov 22:55:50 and a gain with no
  -- character is stored on 20 Nov 10:31:39, so the last day cannot be said.
  local WANT = "Barkskin Burrow Unfriendly +1,005 \194\183 Yesterday | Orgrimmar Honored at least +200 \194\183 Yesterday | Argent Dawn Neutral +95 \194\183 Yesterday"
    .. " | Darkspear Trolls Honored at least +50 \194\183 Yesterday | Thunder Bluff Honored at least +50 \194\183 Yesterday | Undercity Revered at least +50 \194\183 Yesterday"
    .. " | Gadgetzan Friendly at least +1 \194\183 Yesterday"
    .. " | Windshapers Neutral +600 \194\183 Thu 19 Nov | Timbermaw Hold Unfriendly +505 \194\183 Thu 19 Nov | Frostwolf Clan Neutral +100 \194\183 Wed 18 Nov"
    .. " | Earthen Ring Neutral +600 \194\183 Mon 16 Nov | Cenarion Circle Neutral +300 \194\183 Mon 16 Nov"
    .. " | Booty Bay Friendly Not certain | Everlook Friendly Not certain | Powderfuse Friendly Not certain | Ratchet Friendly Not certain"
    .. " | Bloodsail Buccaneers Hated  | Darkmoon Faire Neutral  | Durotar Supply and Logistics Neutral "
  eq("Reputation: the rows, factions with a certain last day first (newest day, then the day's gain), then by standing, Neutral with no gain last", line(), WANT)
  local by = {}
  for _, r in ipairs(rows) do by[r.c.name.text] = r end
  check("Reputation: Orgrimmar is never a bare +200 for 20 Nov (450 are stored that day, 250 of them with no character): at least +200",
    by.Orgrimmar.c.last.text == "at least +200 \194\183 Yesterday" and by.Orgrimmar.item.atLeast == true and by.Orgrimmar.item.partial == true, by.Orgrimmar.c.last.text)
  check("Reputation: Booty Bay is never dated 19 Nov (a gain of 20 Nov 10:31 is stored, with no character): Not certain, muted",
    by["Booty Bay"].c.last.text == "Not certain" and by["Booty Bay"].item.uncertain == true and math.abs(by["Booty Bay"].c.last._color[1] - UI.C.fgMuted[1]) < 0.01, by["Booty Bay"].c.last.text)
  do
    local function tipOf(name) return table.concat(ns.Progress.repLastTip(by[name].item), " ") end
    local n, blank = 0, {}
    for _, r in ipairs(rows) do
      if tipOf(r.c.name.text) == "Last day gained: Not recorded" then n = n + 1; blank[#blank + 1] = r.c.name.text end
      check("Reputation: " .. r.c.name.text .. " has an empty Last day gained cell only with no stored gain", (r.c.last.text == "") == (r.item.ownLast == nil and not r.item.uncertain), r.c.last.text)
    end
    eq("Reputation: Not recorded is the hover of the three factions with no stored gain, and of no other", table.concat(blank, ", "), "Bloodsail Buccaneers, Darkmoon Faire, Durotar Supply and Logistics")
    eq("Reputation: Undercity's newest own gain is Fri 20 Nov 21:30:57", date("%Y-%m-%d %H:%M:%S", by.Undercity.item.ownLast), "2026-11-20 21:30:57")
    eq("Reputation: Gadgetzan's newest own gain is Fri 20 Nov 23:29:32", date("%Y-%m-%d %H:%M:%S", by.Gadgetzan.item.ownLast), "2026-11-20 23:29:32")
    eq("Reputation: Booty Bay's newest own gain is Thu 19 Nov 22:55:50", date("%Y-%m-%d %H:%M:%S", by["Booty Bay"].item.ownLast), "2026-11-19 22:55:50")
    eq("Reputation: Undercity's hover", tipOf("Undercity"), "Newest gain of this character: " .. UI.fmtStamp(by.Undercity.item.ownLast)
      .. ". Some stored gains of this faction on that day name no character, so the day's total cannot be said: it is at least +50.")
    eq("Reputation: Booty Bay's hover", tipOf("Booty Bay"), "Newest gain of this character: " .. UI.fmtStamp(by["Booty Bay"].item.ownLast)
      .. ". A stored gain of this faction on a later day names no character, so the last day it gained cannot be said.")
    eq("Reputation: Barkskin Burrow's hover (exact)", tipOf("Barkskin Burrow"), "+1,005 in all on that day. Newest gain " .. UI.fmtStamp(by["Barkskin Burrow"].item.lastGain) .. ".")
  end
  eq("Reputation: Timbermaw Hold, the 32 gains of 19 Nov by the session a craft proves", by["Timbermaw Hold"].c.last.text, "+505 \194\183 Thu 19 Nov")
  local standings = {}
  for _, r in ipairs(v.rows) do standings[r.label] = (standings[r.label] or 0) + 1 end
  eq("Reputation: the standings: 1 Revered, 3 Honored, 5 Friendly, 7 Neutral, 2 Unfriendly, 1 Hated",
    ("%d %d %d %d %d %d"):format(standings.Revered, standings.Honored, standings.Friendly, standings.Neutral, standings.Unfriendly, standings.Hated), "1 3 5 7 2 1")
  local opens = 0
  for _, r in ipairs(rows) do if r.c._chev.text ~= "" then opens = opens + 1 end end
  eq("Reputation: the 16 factions with stored gains open, the other 3 do not", opens, 16)
  local dash = false
  for _, r in ipairs(rows) do for _, cell in pairs(r.c) do if cell.text == "-" then dash = true end end end
  check("Reputation: no cell is a dash", not dash)
  -- the faction page of Barkskin Burrow: 26 stored gains from Thu 19 Nov 22:43, 1,205 in all, and one new standing
  ns.Progress.openFaction(v.rows[1]); M.settle()
  local f = ns.Progress.FACTION
  eq("Reputation: Barkskin Burrow opens its gains", f.title.text .. " | " .. f.head.label.text .. " | " .. f.head.meta.text .. " | " .. #f.hist, "Barkskin Burrow | GAINS SINCE THU 19 NOV | +1,205 | 27")
  local stand = {}
  for _, h in ipairs(f.hist) do if h.milestone then stand[#stand + 1] = h.change end end
  eq("Reputation: the one row that is not a gain is the new standing", table.concat(stand, ","), "Now Unfriendly")
  v.detail.Close(); M.settle()
  -- Orgrimmar's page lists its 86 counted rows, and says neither a start nor a sum (stored rows with no character)
  ns.Progress.openFaction(by.Orgrimmar.item); M.settle()
  check("Reputation: Orgrimmar's page says no start and no sum", f.title.text == "Orgrimmar" and f.head.label.text == "GAINS" and f.head.meta.shown == false and f.partial == true, f.head.label.text)
  v.detail.Close(); M.settle()
  -- the next pickup: every ended session record is deleted, and the page reads the same (on a copy of the store)
  local keep = { sessions = {}, lastAck = ns.DB.combat.lastAck }
  for id, sess in pairs(ns.DB.sessions) do keep.sessions[id] = sess end
  local ack, n = { sessions = {} }, 0
  for id, sess in pairs(ns.DB.sessions) do if sess.endedEpoch and id ~= ns.DB.active then ack.sessions[id] = true; n = n + 1 end end
  local records = {}
  for id in pairs(ack.sessions) do records[id] = ns.DB.sessions[id] end
  for id in pairs(ack.sessions) do ns.DB.sessions[id] = nil end
  ns.Progress.renderRep(); M.settle()
  local counted = 0
  for _, r in ipairs(ns.DB.story.rep) do if r.g == S.guid then counted = counted + 1 end end
  check("Reputation: with every ended session record gone (" .. n .. "), the 1,630 gains still count and the list reads the same", n > 0 and counted == 1630 and line() == WANT and v.answer == "Barkskin Burrow +1,005 yesterday", line())
  for id, sess in pairs(records) do ns.DB.sessions[id] = sess end
  ns.Progress.renderRep(); M.settle()
  -- The live bars are no part of a save. Without EB_REP the state is refused; with the bars read off the in-game
  -- screenshot (docs/mockups/ux-overhaul/ingame/05-reputation.bars.txt) the page has its four columns, and at the
  -- smallest window every cell is whole: the bar gives way before "Durotar Supply and Logistics" is cut.
  Real.close(S)
  local okOpen, why = Real.open(S, "character/reputation:bars")
  check("Reputation: the bars state is refused without bars (no number the save does not hold)", okOpen == false and tostring(why):find("EB_REP", 1, true) ~= nil and _G.C_Reputation == nil, why)
  S.repBars = Real.readBars("docs/mockups/ux-overhaul/ingame/05-reputation.bars.txt")
  eq("Reputation bars: the 16 rows the screenshot shows", #S.repBars, 16)
  for _, size in ipairs({ { 900, 580 }, { 1104, 697 } }) do
    local tag = ("Reputation bars %dx%d"):format(size[1], size[2])
    UI.SetWindowSize(size[1], size[2])
    check(tag .. ": opens", Real.open(S, "character/reputation:bars") == true)
    cols = {}
    for _, col in ipairs(v.tbl.full) do if v.tbl.cols[col.key] and col.label ~= "" then cols[#cols + 1] = col.label end end
    eq(tag .. ": the columns", table.concat(cols, " | "), "Faction | Standing | Progress | Last day gained")
    local byB, cut, right = {}, {}, 0
    for _, cw in pairs(v.tbl.cols) do right = math.max(right, cw.x + cw.w) end
    for _, r in ipairs(shown(v.tbl)) do
      byB[r.c.name.text] = r
      for _, key in ipairs({ "name", "standing", "last" }) do
        if UI.TextWidth("BODY", strip(r.c[key].text)) > v.tbl.cols[key].w + 0.5 then cut[#cut + 1] = r.c.name.text .. " " .. key end
      end
      local lead = v.barW > 0 and (v.barW + UI.S.S2) or 0
      if UI.TextWidth("BODY", r.c.prog.text) > v.tbl.cols.prog.w - lead + 0.5 then cut[#cut + 1] = r.c.name.text .. " prog" end
    end
    eq(tag .. ": no cell is cut", table.concat(cut, ", "), "")
    check(tag .. ": the table ends inside the page", right + UI.S.S3 <= UI.G.mainW(size[1]) + 0.5, right)
    check(tag .. ": the bar is " .. (size[1] == 900 and "narrower than 120 px and at least 40" or "120 px"), size[1] == 900 and (v.barW >= 40 and v.barW < 120) or v.barW == 120, v.barW)
    eq(tag .. ": Undercity, 4,928 of 21,000 in Revered", byB.Undercity.c.prog.text, "16,072 to Exalted")
    eq(tag .. ": Durotar Supply and Logistics, 150 of 3,000 in Neutral", byB["Durotar Supply and Logistics"].c.prog.text, "2,850 to Friendly")
    check(tag .. ": a faction below the screenshot's fold reads Not known yet, with no empty track", byB["Barkskin Burrow"].c.prog.text == "Not known yet" and not byB["Barkskin Burrow"].bar:IsShown())
    eq(tag .. ": the rows keep their order and their Last day gained", line(), WANT)
    Real.close(S)
    check(tag .. ": the bars are gone once the page is left", _G.C_Reputation == nil)
  end
  S.repBars = nil
  UI.SetWindowSize(1104, 697)
  Real.open(S, "character/reputation"); M.settle()
  cols = {}
  for _, col in ipairs(v.tbl.full) do if v.tbl.cols[col.key] and col.label ~= "" then cols[#cols + 1] = col.label end end
  eq("Reputation: after the bars state the plain page has no Progress column again", table.concat(cols, " | "), "Faction | Standing | Last day gained")
end

-- ── Character > Professions (3.3). The stored list is at its cap, the last 1,000 crafts, from Wed 11 Nov 11:56:59.
-- That day is cut (25 rows of it are left; the save of 19 Nov still holds 148 crafts and 154 items for it), so the
-- list starts on Thu 12 Nov. One row is no profession craft (Courier's Shipment, Fri 13 Nov 13:04, spell 260452,
-- no profession on any row of that spell). 1,038 stored items less 25 less 1 are 1,012, in 52 batches: the first
-- Tin Bar of Thu 12 Nov 15:46 and the first Tender Wolf Steak of Tue 17 Nov 19:26 were stored with no profession
-- and belong to the batch that follows them 3 s later. ──
Real.open(S, "character/professions"); M.settle()
do
  local v = ns.Progress.prof
  local profs = {}
  for _, r in ipairs(v.profRows) do if r.shown ~= false and r:IsShown() then profs[#profs + 1] = r.title.text .. " " .. r.count.text .. " " .. r.meta.text end end
  eq("Professions: the rows: skill, rank, and no recipe count (137 stored recipes, 10 with a profession)", table.concat(profs, " | "),
    "Cooking 297 / 300 Artisan | Mining 255 / 300 Artisan | First Aid 246 / 300 Artisan | Blacksmithing 185 / 225 Expert | Fishing 1 / 75 Apprentice")
  check("Professions: no headline and no recipe list", v.summary == nil and v.recipes == nil)
  eq("save: the craft list is at its cap", #ns.char().crafts, ns.Market.CRAFT_CAP)
  eq("Professions: the Crafted header names the first whole day (Wed 11 Nov is cut by the cap)", v.crafted.head.label.text, "CRAFTED SINCE THU 12 NOV")
  eq("Professions: its meta is the items listed", v.crafted.head.meta.text, "1,012 items")
  eq("Professions: 52 batches", #v.batches, 52)
  local days, lines = {}, {}
  for i = 1, v.crafted.tbl.shownN do
    local r = v.crafted.tbl.rows[i]
    if r.item.ebSection then days[#days + 1] = r.item.ebSection
    else lines[#lines + 1] = r.c.when.text .. " " .. r.c.item.text .. " " .. r.c.prof.text end
  end
  eq("Professions: the day rows count items (batches per day: 8, 3, 2, 7, 3, 1, 4, 3, 21); no row for Wed 11 Nov", table.concat(days, " | "),
    "YESTERDAY \194\183 111 items | THURSDAY 19 NOV \194\183 72 items | WEDNESDAY 18 NOV \194\183 47 items | TUESDAY 17 NOV \194\183 257 items | MONDAY 16 NOV \194\183 29 items"
    .. " | SUNDAY 15 NOV \194\183 20 items | SATURDAY 14 NOV \194\183 44 items | FRIDAY 13 NOV \194\183 28 items | THURSDAY 12 NOV \194\183 404 items")
  eq("Professions: the newest batches", table.concat(lines, " | ", 1, 8),
    "23:50 Truesilver Bar x6 Mining | 23:49 Gold Bar x3 Mining | 23:46 to 23:48 Mithril Bar x49 Mining | 23:46 Steel Bar x2 Mining"
    .. " | 23:45 to 23:46 Iron Bar x8 Mining | 23:45 Tin Bar x3 Mining | 23:03 to 23:05 Mageweave Bandage x29 First Aid | 20:05 Solid Weightstone x11 Blacksmithing")
  eq("Professions: Thursday's batches", table.concat(lines, " | ", 9, 11), "22:22 to 22:23 Tender Wolf Steak x14 Cooking | 22:13 to 22:16 Basic Campfire Kit x18 Cooking | 22:11 to 22:13 Tender Wolf Steak x40 Cooking")
  local all = " | " .. table.concat(lines, " | ") .. " | "
  check("Professions: Tin Bar of 12 Nov 15:46 is one batch of 29, Mining (the first craft was stored with no profession)",
    all:find(" | 15:46 to 15:47 Tin Bar x29 Mining | ", 1, true) ~= nil and all:find(" | 15:46 Tin Bar ", 1, true) == nil)
  check("Professions: Tender Wolf Steak of 17 Nov 19:26 is one batch of 15, Cooking",
    all:find(" | 19:26 to 19:27 Tender Wolf Steak x15 Cooking | ", 1, true) ~= nil and all:find(" | 19:26 Tender Wolf Steak ", 1, true) == nil)
  check("Professions: Courier's Shipment (no profession craft) is not listed", all:find("Courier", 1, true) == nil)
  check("Professions: nothing of the cut day (Roast Raptor of Wed 11 Nov 11:56) is listed", lines[#lines] == "12:44 to 12:46 Heavy Silk Bandage x46 First Aid", lines[#lines])
  local blank = false
  for _, l in ipairs(lines) do if l:find("Other", 1, true) or l:find(" %-$") or l:find(" $") then blank = true end end
  check("Professions: every batch names its profession: no Other, no dash, no blank", not blank)
end
-- ── Loot > Gold (docs/UX_PRAGMATIC.md 4.2). Copper values worked out from the save's ledgers, day rows and journals
-- by throwaway scripts. The boot stamps the coin capture of 0.9.52 as starting now, so every stored run is before it. ──
do
  local Gold = ns.Gold
  local GP = Gold.GP
  local money = GP.money
  local function gold() for _, tab in ipairs(T.tabs) do if tab.name == "Loot" then return tab.paneByKey.gold.content end end end
  local function tip(f) local t = _G.GameTooltip; t:ClearLines(); f.scripts.OnEnter(f); local s = table.concat(t.lines or {}, "\n"); f.scripts.OnLeave(f); return s end
  local function cardsOf(c) local o = {}; for i, cd in ipairs(c.shownCards) do o[i] = strip(cd.value.text) .. " [" .. strip(cd.meta.text) .. "]" end return table.concat(o, " | ") end
  local function plain(s) return (strip(s):gsub("\194\160", " ")) end
  -- Session: 3 journal rows, all spending
  Gold.open("session"); M.settle()
  local c = gold()
  eq("Gold session: the header", c.section.label.text, "THIS SESSION")
  check("Gold session: BALANCE 12s 19c, all characters 12g 0s (120,078 copper, never 12g 78c)", c.shownCards[1].value.text == money(1219) and c.shownCards[1].meta.text == "all characters " .. money(120078)
    and plain(ns.fmtMoney(120078, { units = 2 })) == "12g 0s", c.shownCards[1].meta.text)
  check("Gold session: the two logins of 11:45 and 11:47: earned 84,773 (+8g 47s), spent 309,910 (-30g 99s), net -225,137 (-22g 51s), as Today", c.scopeData.ledger.gained == 84773 and c.scopeData.ledger.spent == 309910
    and c.scopeData.logins == 2 and c.shownCards[2].value.text == money(84773, true) and c.shownCards[3].value.text == money(-309910, true) and c.shownCards[4].value.text == money(-225137, true), cardsOf(c))
  check("Gold session: no per hour figure 11 minutes in, no entry count, nothing untraced", c.rate == nil and strip(c.shownCards[4].meta.text) == "" and c.shownCards[3].meta.text == "mostly auction house" and not cardsOf(c):find("entr"), cardsOf(c))
  check("Gold session: Sources is offered (no dungeon time in the session)", c.srcOff == nil and c.view == "sources")
  do
    local rows = shown(c.tbl.sources)
    local got = {}
    for i, r in ipairs(rows) do got[i] = strip(r.c.src.text) .. "|" .. strip(r.c.what.text) .. "|" .. r.c.whatAmt.text .. "|" .. r.c.amount.text end
    -- (auction sales 59,773 and mail 25,000 make the 84,773 earned)
    eq("Gold session: the four sources, each with what it mostly came from", table.concat(got, " ; "),
      ("Auction sales|Formula: Enchant Boots - Greater Stamina|%s|%s ; Mail received|Yoco Ratnik||%s ; Flights|Tal||%s ; Auction house|Black Lotus x3|%s|%s"):format(
        money(28150), money(59773, true), money(25000, true), money(-45, true), money(281985), money(-309865, true)))
    -- (the mail of 2g 50s and the flight of 45c are each the whole of their source: the amount is not said twice)
    local cut = {}
    for _, r in ipairs(rows) do if r.c.what.IsTruncated and r.c.what:IsTruncated() then cut[#cut + 1] = strip(r.c.what.text) end end
    eq("Gold session: no MOSTLY FROM name is cut at 1104 wide", table.concat(cut, ","), "")
    check("Gold session: no Times and no Share column (the flight was 0% of 30g 99s)", c.tbl.sources.head.n == nil and c.tbl.sources.head.share == nil)
  end
  -- Session, Journal: the auction rows name their item
  Gold.open("session", "journal"); M.settle()
  do
    local got = {}
    for i, r in ipairs(shown(c.tbl.journal)) do got[i] = r.c.time.text .. " " .. strip(r.c.detail.text) .. " " .. r.c.amount.text end
    eq("Gold session journal: 12 rows, the 3 of the second login over the 9 of the first", #got, 12)
    eq("Gold session journal: the newest three", table.concat(got, " ; ", 1, 3),
      ("11:50 Tal %s ; 11:49 Bought Golden Sansam x20 %s ; 11:48 Bought Black Lotus x3 %s"):format(money(-45, true), money(-27880, true), money(-281985, true)))
    local sum = 0
    for _, r in ipairs(shown(c.tbl.journal)) do sum = sum + r.item.delta end
    eq("Gold session journal: the rows add up to the net", sum, -225137)
  end
  -- Today: the day row 20261121
  Gold.open("today"); M.settle()
  check("Gold today: earned 84,773, spent 309,910, net -225,137 (-22g 51s)", c.scopeData.ledger.gained == 84773 and c.scopeData.ledger.spent == 309910 and c.shownCards[2].value.text == money(84773, true)
    and c.shownCards[4].value.text == money(-225137, true) and c.section.label.text == "TODAY", cardsOf(c))
  check("Gold today: auction sales 59,773 and mail 25,000 make the 84,773", c.scopeData.ledger.auctionSales == 59773 and c.scopeData.ledger.mail == 25000)
  check("Gold today: 610 s played, so no per hour figure", c.scopeData.elapsed < 1800 and c.rate == nil and strip(c.shownCards[4].meta.text) == "", c.scopeData.elapsed)
  -- Today, Auction house: 10 rows, not 12
  Gold.open("today", "auctions"); M.settle()
  do
    eq("Auctions today: the answer", table.concat(c.answerData.segs, " | "), ("Spent **%s** | Received **%s** | Net **%s**"):format(money(309865), money(59773), money(-250092, true)))
    check("Auctions today: Spent 309,865 = the ledger's auctions; Received 59,773 = sold 58,768 - cut 2,935 + deposits 3,940; Net -250,092",
      c.answerData.spent == 309865 and c.answerData.received == 59773 and c.answerData.net == -250092 and c.auctionSum.sales == 58768 and c.auctionSum.cut == 2935 and c.auctionSum.deposit == 3940
      and c.auctionSum.sales - c.auctionSum.cut + c.auctionSum.deposit == c.answerData.received and c.auctionSum.spent == c.answerData.spent, c.auctionSum.sales)
    eq("Auctions today: net reads -25g 0s", plain(ns.fmtMoney(-250092, { units = 2, signed = true })), "-25g 0s")
    local rows = shown(c.tbl.auctions)
    local got = {}
    for i, r in ipairs(rows) do got[i] = plain(r.c.item.text) .. "|" .. r.c.result.text .. "|" .. r.c.price.text end
    eq("Auctions today: 10 rows: 2 purchases (their delivery mails are not rows), 8 sales at what the buyer paid, with the posted count", table.concat(got, " ; "), table.concat({
      "Golden Sansam x20|Bought|" .. money(27880), "Black Lotus x3|Bought|" .. money(281985),
      "Formula: Enchant Bracer - Superior Stamina|Sold|" .. money(9077), "Formula: Enchant Boots - Greater Stamina|Sold|" .. money(29000),
      "Ironweb Spider Silk x3|Sold|" .. money(16500), "Red Wolf Meat x3|Sold|" .. money(759), "Tender Wolf Meat x2|Sold|" .. money(398),
      "White Spider Meat x7|Sold|" .. money(1043), "Mystery Meat x3|Sold|" .. money(780), "Golden Sansam|Sold|" .. money(1211) }, " ; "))
    check("Auctions today: bought 2, sold 8, no delivery left over", c.auctionSum.bought == 2 and c.auctionSum.sold == 8 and c.auctionSum.won == 0)
    check("Auctions today: the Black Lotus row knows its seller from the delivery mail", tip(rows[2]):find("Acornelius Thost", 1, true) ~= nil)
    local cols = {}
    for _, sp in ipairs(c.tbl.auctions.spec) do if c.tbl.auctions.cols[sp.key] then cols[#cols + 1] = sp.label end end
    eq("Auctions today: columns (1 of 10 rows names a player: no Player column)", table.concat(cols, "|"), "When||Item|Result|Price")
  end
  -- Week: counted from where the day rows start, and it holds dungeon time from before the capture fix
  Gold.open("week"); M.settle()
  eq("Gold week: the header is the real range (goldSince 1795030532), not WEEK", c.section.label.text, "SINCE WED 18 NOV 20:35")
  check("Gold week: earned 2,538,223, spent 3,347,026, net -808,803", c.scopeData.ledger.gained == 2538223 and c.scopeData.ledger.spent == 3347026 and c.shownCards[4].value.text == money(-808803, true), cardsOf(c))
  check("Gold week: 134,194 in and 503,600 out with no source seen, said on the cards, never as away", c.shownCards[2].meta.text == money(134194) .. " not traced" and c.shownCards[3].meta.text == money(503600) .. " not traced"
    and not cardsOf(c):lower():find("away"), cardsOf(c))
  check("Gold week: 85,100 s played, so NET carries the rate", c.scopeData.elapsed == 85100 and c.shownCards[4].meta.text == money(-808803 * 3600 / 85100, true) .. " per hour", c.shownCards[4].meta.text)
  check("Gold week: Sources is not offered (the Maraudon and Blackrock runs are in it): the page opens on Journal", c.srcOff ~= nil and c.view == "journal" and c.st.view == "sources"
    and tip(c.viewSeg.segs[1]):find("Sources are not reliable for dungeon time before Sat 21 Nov.", 1, true) ~= nil, tip(c.viewSeg.segs[1]))
  do
    local secs = c.tbl.journal.sections()
    -- (review round 3: neither carries a net. The day row of Fri 20 Nov, -114g 54s, is Fri 05:00 to Sat 05:00 and
    -- the kept rows do not add up to it, so the save cannot split it at midnight; see the day rows check below.)
    eq("Gold week journal: today's day row is the bare day", secs[1].text, "TODAY")
    eq("Gold week journal: yesterday's is the bare day, not the gold day row's -114g 54s", secs[2].text, "YESTERDAY")
    -- (1,711 rows were written since 18 Nov 20:35, the day rows' n: 297 + 895 + 502 + 12 + 5 of today; 767 are kept.
    -- The cut at 500 never takes the place of the coverage remark.)
    eq("Gold week journal: 767 entries are kept from 20:35 on, the newest 500 listed, and the header says both", c.journalCount .. " " .. tostring(c.section.meta.text), "767 newest 500 of 767, not every entry is kept")
    check("Gold week journal: the header says kept, and its hover why", tostring(c.section.meta.text):find("kept", 1, true) ~= nil and c.journalPartial == true and tip(c.section.metaHit):find("desktop app", 1, true) ~= nil)
    -- the remark is never under the search box: at 1104 and 900 px it has a line of its own, at 1600 it follows the label
    for _, w in ipairs({ 900, 1104, 1600 }) do
      UI.SetWindowSize(w, w == 1600 and 1000 or 697); M.settle()
      local mb, sb = G.resolve(c.section.meta), G.resolve(c.search)
      local clash = mb and sb and mb.l < sb.l + sb.w and sb.l < mb.l + mb.w and mb.t < sb.t + sb.h and sb.t < mb.t + mb.h
      check("Gold week journal at " .. w .. " px: the remark is whole and clear of the search box", mb ~= nil and sb ~= nil and not clash and c.section.meta:IsTruncated() ~= true and (c.metaBelow == true) == (w < 1600),
        tostring(c.metaBelow) .. " " .. tostring(mb and mb.l) .. " " .. tostring(mb and mb.w) .. " " .. tostring(sb and sb.l))
    end
    UI.SetWindowSize(1104, 697); M.settle()
    -- the two rows of Fri 20 Nov 23:29 booked as mail in Tanaris (a kill at 23:29:32, the only mailbox visit of that
    -- time is in Orgrimmar): no invented "mailbox", and the Source cell does not say Mail
    do
      local got, anyBox = {}, 0
      for _, r in ipairs(shown(c.tbl.journal)) do
        local e = r.item
        if strip(r.c.detail.text) == "mailbox" then anyBox = anyBox + 1 end
        if e.src == "mail" and not e.ref.sender then got[#got + 1] = r.c.time.text .. " " .. r.c.src.text .. " [" .. strip(r.c.detail.text) .. "] " .. r.c.loc.text .. " " .. r.c.amount.text end
      end
      eq("Gold week journal: the two mail rows with no sender", table.concat(got, " ; "), ("23:29 Source not seen [] Tanaris %s ; 23:29 Source not seen [] Tanaris %s"):format(money(458, true), money(312, true)))
      eq("Gold week journal: no row says mailbox", anyBox, 0)
    end
    -- (day rows are calendar days. The day row 20261118 starts at 20:35 and no entry of Wed 18 Nov from then on is
    -- kept, so Week lists no row of that day: its oldest day row is Thursday. No day row carries a net: a gold day
    -- runs 05:00 to 05:00 and the kept rows do not add up to the day rows of 18, 19 and 20 Nov (session records
    -- are gone), so nothing stored says how much of each fell before or after midnight. The 19 Nov snapshot
    -- proves it for Thursday: 115 rows of Thu 00:00 to 05:00, net -230,173, booked on the day row of the 18th,
    -- whose session record the 21 Nov save no longer holds. "+57g 7s" for Thursday was the net of Thu 05:00 to
    -- Fri 05:00. Today's day row is whole (84,773 and 309,910), but yesterday's is not (kept 725,040 of 845,791
    -- earned), so the save cannot say that none of yesterday's missing rows fell after midnight.)
    local secs2 = {}
    for i, s in ipairs(secs) do secs2[i] = s.text end
    eq("Gold week journal: the day rows are bare days", table.concat(secs2, " | "), UI.upper(table.concat({ "TODAY", "YESTERDAY", "THURSDAY 19 NOV" }, " | ")))
    do
      local byKey = GP.keptSums(Gold.baseStored(), ns.char().goldSince)
      local d = ns.char().goldDays
      check("Gold week journal: the kept rows add up to the day row of 21 Nov only", byKey["20261121"].g == d["20261121"].g and byKey["20261121"].s == d["20261121"].s
        and byKey["20261120"].g == 725040 and d["20261120"].g == 845791 and byKey["20261119"].g ~= d["20261119"].g and (byKey["20261118"] or { g = 0 }).g ~= d["20261118"].g, byKey["20261120"].g)
    end
  end
  -- All time: the lifetime ledger
  Gold.open("all"); M.settle()
  check("Gold all: earned 6,627,648, spent 6,626,453, net +1,195; 571,606 and 517,784 not traced; no rate", c.scopeData.ledger.gained == 6627648 and c.scopeData.ledger.spent == 6626453
    and c.shownCards[4].value.text == money(1195, true) and c.shownCards[2].meta.text == money(571606) .. " not traced" and c.shownCards[3].meta.text == money(517784) .. " not traced"
    and strip(c.shownCards[4].meta.text) == "", cardsOf(c))
  -- (the list is the Journal: 901 kept rows, the oldest of 18 Nov 01:14. ALL TIME is the cards' word, not the list's.)
  eq("Gold all journal: the header says where the kept entries start, the cut and that not every entry is kept", c.view .. " / " .. c.section.label.text .. " / " .. tostring(c.section.meta.text),
    "journal / ENTRIES SINCE WED 18 NOV / newest 500 of 901, not every entry is kept")
  -- A row stands under the calendar day it happened on. goldLog "145405.1 -14939 repairs 319440 npc=Kaja" of the
  -- session started Wed 18 Nov 01:14:46 is Wed 18 Nov 01:29:15: before the daily reset (05:00), so in the gold day
  -- of Tuesday, and it must not read "TUESDAY 17 NOV 01:29". The same day holds rows from before goldSince (20:35),
  -- so its day row says neither "FROM 20:35" nor a net.
  do
    c.search:SetText("repair"); c.search.scripts.OnTextChanged(c.search); M.settle()
    local head, found, n, wed = nil, nil, 0, nil
    for i = 1, c.tbl.journal.shownN or 0 do
      local r = c.tbl.journal.rows[i]
      if r.item and r.item.ebSection then head = r.item.ebSection; wed = head
      elseif r.item and r.item.src == "repairs" and r.item.delta == -14939 and os.date("%a %d %b %H:%M:%S", r.item.t) == "Wed 18 Nov 01:29:15" then found = head .. " / " .. r.c.time.text .. " / " .. strip(r.c.detail.text) .. " / " .. r.c.amount.text; n = n + 1 end
    end
    eq("Gold all journal: the repair of Wed 18 Nov 01:29 stands under Wednesday", found, "WEDNESDAY 18 NOV / 01:29 / Repair at Kaja / " .. money(-14939, true))
    c.search:SetText(""); c.search.scripts.OnTextChanged(c.search); M.settle()
    local late = 0
    for i = 1, c.tbl.journal.shownN or 0 do
      local r = c.tbl.journal.rows[i]
      if r.item and r.item.ebSection then head = r.item.ebSection
      elseif r.item and r.item.t and head:find("^TUESDAY") then late = late + 1 end
    end
    local facts = GP.dayFacts(c.entries, true)
    local from, net = facts(1794961755)
    eq("Gold all journal: Wednesday's day row is the bare day", wed, "WEDNESDAY 18 NOV")
    check("Gold all journal: Wed 18 Nov holds rows from before 20:35 and rows of two gold days: no FROM, no net", from == nil and net == nil, tostring(from) .. " " .. tostring(net))
    -- (Thu 19 Nov: the day row 20261119 is 05:00 to 05:00 and the rows of Thu 00:00 to 05:00 are gone with their
    -- session record: 1,069,152 - 498,444 is not the net of the calendar day and is not shown)
    local _, netThu = facts(1795099037)
    eq("Gold all journal: Thu 19 Nov has no net: the day row 20261119 is not the calendar day", netThu, nil)
    local _, netSat = facts(1795258000)
    eq("Gold all journal: nor has Sat 21 Nov, while the day row of the 20th is not whole in the kept rows", netSat, nil)
    eq("Gold all journal: no row is listed under a Tuesday (the oldest kept entry is of Wed 18 Nov 01:14)", late, 0)
  end
  Gold.open("all", "auctions"); M.settle()
  do
    local n = { Bought = 0, Collected = 0, Sold = 0, Posted = 0, Expired = 0, Cancelled = 0 }
    for _, r in ipairs(shown(c.tbl.auctions)) do n[r.item.what] = n[r.item.what] + 1 end
    -- (55 delivery mails are kept for this character. 51 belong to a priced purchase of the same item in the same
    -- session with units still to come, among them the two Tender Wolf Meat x20 of 18 Nov 12:19, 96 minutes after the
    -- purchase of 40. 4 have none: three Wool Cloth x20 of 19 Nov 21:54, one row "x60", and a Dark Leather Tunic.)
    -- (42 purchase rows carry a price. 12 of them have no item of their own: C_AuctionHouse.PlaceBid rows whose
    -- stored name was a guess. Four are named by a fact: 5 "Auction won: Red Mageweave Bag" mails of the session of
    -- 17 Nov carry the invoices 16,046 and 4 x 16,499, and that session holds bids of 16,046 (3) and 16,499 (3), so
    -- one bid of 16,046 and the three of 16,499 are Red Mageweave Bag. The other 8 (4 of 17 Nov, among them two bids
    -- on the same auction 142300059, and the bids of 7 and 12 Nov, whose sessions keep no won mail) are named by
    -- nothing and are not rows: 34 purchases, 2,384,440 - 2 x 16,046 - 2 x 16,047 - 3,500 - 1,100 - 2 x 45,800
    -- = 2,224,054 copper. The 5th bag mail has no bid row left and is not a row either.)
    -- (98 postings are kept. 42 have their outcome: 40 Sold rows at their buyout and the 2 returned items. The other
    -- 56 ran out before 21 Nov 11:56 (the newest of them was posted 19 Nov 22:18 for 24 h) with no outcome recorded,
    -- so no posting is listed: every row is something that was bought, sold, collected or came back.)
    eq("Auctions all: 34 purchases with an item (2,224,054 copper), no open posting, 61 sold, 2 returned; 51 of the 55 delivery mails are taken up, 4 have no purchase and make 2 rows",
      ("%d %d %d %d %d %d %d %d"):format(n.Bought, c.auctionSum.spent, n.Posted, n.Sold, n.Expired + n.Cancelled, n.Collected, c.auctionSum.won, 55 - c.auctionSum.won), "34 2224054 0 61 2 2 4 51")
    eq("Auctions all: 8 bids nothing names and 56 postings with no recorded outcome are not rows", c.auctionSum.bids .. " " .. c.auctionSum.ended, "8 56")
    do
      local bags, blank, twice, withPosted = {}, 0, 0, 0
      for _, r in ipairs(shown(c.tbl.auctions)) do
        local e = r.item
        if e.item == "Red Mageweave Bag" then bags[#bags + 1] = r.c.when.text .. " " .. r.c.result.text .. " " .. r.c.price.text .. (e.byInvoice and " invoice" or "") end
        if strip(r.c.item.text) == "" then blank = blank + 1 end
        if r.c.result.text:find("Posted", 1, true) then twice = twice + 1 end
        if e.what == "Sold" and e.postedAt then withPosted = withPosted + 1 end
      end
      eq("Auctions all: the four Red Mageweave Bags of Tue 17 Nov, named by their invoices", table.concat(bags, " ; "),
        ("21:15 Bought %s invoice ; 21:15 Bought %s invoice ; 21:15 Bought %s invoice ; 21:15 Bought %s invoice"):format(money(16499), money(16499), money(16499), money(16046)))
      eq("Auctions all: no row has an empty Item cell", blank, 0)
      eq("Auctions all: no auction is listed twice (no Posted row beside its Sold row)", twice, 0)
      eq("Auctions all: 40 Sold rows know when they were posted (hover)", withPosted, 40)
    end
    do
      local got, meat, bad, paid = {}, 0, {}, 0
      for _, r in ipairs(shown(c.tbl.auctions)) do
        local e = r.item
        if e.what == "Collected" then got[#got + 1] = plain(r.c.item.text) .. "|" .. r.c.result.text .. "|" .. r.c.price.text end
        if e.item == "Tender Wolf Meat" and e.what ~= "Bought" and e.what ~= "Sold" and e.what ~= "Posted" then meat = meat + 1 end
        if e.what == "Sold" then
          local tp = tip(r)
          if tp:find("Mail paid", 1, true) then paid = paid + 1 end
          -- (every figure of a Sold hover is the invoice's: a Mail paid line is there only as bid - cut + deposit)
          if e.net and e.net ~= e.price - (e.cut or 0) + (e.deposit or 0) then bad[#bad + 1] = tostring(e.item) end
          if e.item == "Azora's Will" and tp:find("Mail paid", 1, true) then bad[#bad + 1] = "Azora's Will: " .. tp end
        end
      end
      eq("Auctions all: the deliveries with no purchase, in plain words and folded", table.concat(got, " ; "), "Wool Cloth x60|Collected| ; Dark Leather Tunic|Collected|")
      eq("Auctions all: no delivery row of Tender Wolf Meat beside its purchase", meat, 0)
      eq("Auctions all: no Sold hover shows a stored net that is not its invoice's sum (26 of the 61 stored nets are not)", table.concat(bad, ","), "")
      eq("Auctions all: 35 of the 61 Sold hovers carry Mail paid", paid, 35)
    end
    local dash = 0
    for _, r in ipairs(shown(c.tbl.auctions)) do for _, cell in pairs(r.c) do if cell.text == "-" then dash = dash + 1 end end end
    eq("Auctions all: no cell is a dash", dash, 0)
    -- (loot.ah holds 556 rows; 298 of them belong to sessions whose record the desktop pickup deleted, so no list
    -- shows them: 105 posted, 92 bought, 77 sold, 24 returned)
    eq("Auctions all: the header says where the listed rows start and that not every row is listed", c.section.label.text .. " / " .. tostring(c.section.meta.text), "AUCTIONS SINCE SAT 7 NOV / not every row is listed")
    check("Auctions all: the hover says what is left out, each with its count", tip(c.section.metaHit):find("8 bids with no item recorded", 1, true) ~= nil and tip(c.section.metaHit):find("56 postings whose time ran out", 1, true) ~= nil
      and tip(c.section.metaHit):find("desktop app has already saved", 1, true) ~= nil, tip(c.section.metaHit))
    eq("Auctions all: 298 stored rows are not listed", c.auctionSum.unowned, 298)
  end
  Gold.open("session"); M.settle()
end
-- ── Loot > Items (docs/UX_PRAGMATIC.md 4.1) ──
do
  Real.open(S, "loot/items"); M.settle()
  local ic = T.lootContent()
  ic.setLootMode("newest"); ic.setLootQuality("green"); M.settle()
  local tbl = ic.lootTables.newest
  local rows = shown(tbl)
  eq("Items: the header says where the list starts (the oldest item row kept, 17 Nov 11:28)", ic.lootSection.label.text, "ITEMS SINCE TUE 17 NOV")
  -- (91 rows are green or better; 2 of them are auction purchases, Black Lotus and Death Lotus, which are not loot)
  -- (goldRuns still counts items for runs with no row left in the list: Maraudon 18 Nov 21:32 (36), Blackrock Depths
  -- 19 Nov 11:08 (109), Blackrock Spire 20 Nov 10:06 (72); Blackrock Depths 19 Nov 21:01 has 7 of 12. So the list is
  -- not complete from 17 Nov on, and the header says so. A row is a pickup, of one item or a stack.)
  -- (89 pickups are 86 rows: the three Gold Ore of 18 Nov 10:17 are one row "x3", the two Iridescent Pearl of 17 Nov
  -- 14:01 one row "x2")
  eq("Items: 89 pickups green or better in 86 rows, and not every item is kept", #rows .. " / " .. tostring(ic.lootSection.meta.text), "86 / 89 pickups green or better, not every item is kept")
  do
    local merged = {}
    for _, r in ipairs(rows) do if r.item.ebMerged then merged[#merged + 1] = r.item.item .. " " .. tostring(r.ebCount.text) .. " of " .. r.item.ebMerged end end
    eq("Items: the pickups of one item in one minute are one row with the summed count", table.concat(merged, " ; "), "Gold Ore x3 of 3 ; Iridescent Pearl x2 of 2")
  end
  check("Items: no line above the list", ic.lootSummary == nil)
  local days = {}
  for _, s in ipairs(tbl.sections()) do days[#days + 1] = s.text end
  eq("Items: the day rows, with no count and no Today (nothing was looted on 21 Nov)", table.concat(days, " | "), "YESTERDAY | THURSDAY 19 NOV | WEDNESDAY 18 NOV | TUESDAY 17 NOV")
  local per, from, place, bad = {}, { named = 0, quest = 0, questBare = 0, container = 0, enemy = 0, blank = 0 }, 0, {}
  local guessed = {}
  for _, r in ipairs(rows) do
    local e = r.item
    local d = os.date("%d", e.t); per[d] = (per[d] or 0) + 1
    local f = T.lootFrom(e)
    if f == nil then from.blank = from.blank + 1 elseif f == "Enemy" then from.enemy = from.enemy + 1 elseif f == "Container" then from.container = from.container + 1
    elseif f == "Quest" then from.questBare = from.questBare + 1
    elseif f:find("^Quest") then from.quest = from.quest + 1 else from.named = from.named + 1 end
    -- (a name is shown only with the loot window's GUID behind it: never the last kill before the pickup)
    if f and f == e.src and not e.guid then guessed[#guessed + 1] = f end
    if T.lootPlace(e) then place = place + 1 end
    for k, cell in pairs(r.c) do
      local t = cell.text
      if t == "-" or t == "an enemy" or t == "Creature" or t == "Picked up" or t == "Unknown source" or t == "Auction won" then bad[#bad + 1] = k .. "=" .. t end
    end
    if r.c.from and r.c.from.text ~= (f or "") then bad[#bad + 1] = "from cell" end
  end
  eq("Items: rows per day, 20 Nov / 19 / 18 / 17", ("%d %d %d %d"):format(per["20"] or 0, per["19"] or 0, per["18"] or 0, per["17"] or 0), "20 25 18 23")
  -- (8 rows store a name. 3 carry the loot window's GUID, Vilebranch Warrior, Vilebranch Shadow Hunter and Mummified
  -- Atal'ai. The other 5 were named by the last kill before the pickup, a kill of that name is in the session record
  -- up to 20 s before each: they read Enemy. Of the 8 quest rewards, 5 are older than the event list (it starts 20 Nov
  -- 15:31) and name no quest; Lichbane and Plaguecrusher Greaves of 20 Nov 22:48 have two turn-ins within 5 s, Final
  -- Death and Blight No More, so they name none either; the Manual of 22:51 has one, A Rest Without Pain.)
  -- ("Enemy" is no value: the rows whose name is hidden or only a kill by timing are blank, hover "Name not recorded")
  eq("Items: From: 3 named by their loot window, 1 quest named, 7 quest rewards with no single turn-in stored, 3 opened containers, no cell says Enemy, 72 blank",
    ("%d %d %d %d %d %d"):format(from.named, from.quest, from.questBare, from.container, from.enemy, from.blank), "3 1 7 3 0 72")
  check("Items: 14 of 86 rows have a From value, under a third, so the column is left out and the value is in the hover", ic.lootCols.from == true and tbl.cols.from == nil)
  eq("Items: no name is shown without its loot window", table.concat(guessed, ","), "")
  eq("Items: no dash and no stored placeholder in any cell", table.concat(bad, ","), "")
  check("Items: no Value or Vendor price column", tbl.head.price == nil)
  check("Items: Place shows on " .. place .. " of 89 rows, under a third, so the column is left out and the place is in the hover", (place * 3 < 89) == (ic.lootCols.loc == true) and (ic.lootCols.loc and tbl.cols.loc == nil or tbl.cols.loc ~= nil), place)
  -- the two greens stamped "Orgrimmar" while the character was in Blackrock Depths (19 Nov 18:01 and 18:03)
  local stale = 0
  for _, r in ipairs(rows) do
    if r.item.item == "Hibernal Armor" or r.item.item == "Champion's Armor of Nature's Wrath" then
      if r.item.zone == "Orgrimmar" and T.lootPlace(r.item) == nil then stale = stale + 1 end
    end
  end
  eq("Items: the two rows stored with Orgrimmar while in Blackrock Depths show no place", stale, 2)
  check("Items: no Coords column without the Place column", ic.lootCols.loc == true and ic.lootCols.coords == true and tbl.cols.coords == nil)
  -- Everything, at the widest size: the rows the reviews named, and the rule for every row of the save
  UI.SetWindowSize(1600, 1000); M.settle()
  ic.setLootQuality("all"); M.settle()
  do
    local all = shown(tbl)
    eq("Items, everything: 929 pickups in 781 rows", #all .. " / " .. tostring(ic.lootSection.meta.text), "781 / 929 pickups, not every item is kept")
    do
      -- (20 Nov 23:33: three Iron Ore with a Lesser Moonstone between them; Hyjal Silphium x3 x3 x2 in 22:44 and
      -- x2 x2 in 22:43. A minute is the unit: 8 and 4, never 12.)
      local got, twice, seen = {}, {}, {}
      for _, r in ipairs(all) do
        local e = r.item
        local k = e.item .. "@" .. os.date("%d %H:%M", e.t)
        local cells = tostring(T.lootFrom(e)) .. "|" .. tostring(T.lootPlace(e)) .. "|" .. tostring(e.q) .. "|" .. tostring(e.quest)
        if (e.item == "Iron Ore" and os.date("%d %H:%M", e.t) == "20 23:33") or (e.item == "Hyjal Silphium" and os.date("%d %H", e.t) == "20 22") then got[#got + 1] = os.date("%H:%M", e.t) .. " " .. e.item .. " x" .. e.count end
        if seen[k] and seen[k][cells] then twice[#twice + 1] = k end
        seen[k] = seen[k] or {}; seen[k][cells] = true
      end
      eq("Items, everything: Iron Ore x3 and Hyjal Silphium x8, x4", table.concat(got, " ; "), "23:33 Iron Ore x3 ; 22:44 Hyjal Silphium x8 ; 22:43 Hyjal Silphium x4")
      eq("Items, everything: no item is listed twice in one minute with the same cells", table.concat(twice, ","), "")
      local same = 0
      for _, r in ipairs(all) do if r.c.from and r.c.from.text ~= "" and r.c.from.text == r.item.item then same = same + 1 end end
      eq("Items, everything: no From cell repeats the item's name", same, 0)
    end
    local units = 0
    for _, r in ipairs(all) do units = units + (tonumber(r.item.count) or 1) end
    eq("Items, everything: the 929 pickups hold 1,795 units, so the header does not call them items", units, 1795)
    local byKey, far, noPlace, hyjal, form, names, quests = {}, {}, 0, 0, nil, {}, {}
    for _, r in ipairs(all) do
      local e = r.item
      local xy, pl = T.lootCoords(e), T.lootPlace(e)
      if xy and not pl then noPlace = noPlace + 1 end
      if e.x == 0.6903 and e.y == 0.6981 and (pl or xy) then hyjal = hyjal + 1 end
      if e.item == "Formula: Enchant Bracer - Superior Stamina" then form = tostring(T.lootFrom(e)) .. "/" .. tostring(pl) .. "/" .. tostring(xy) end
      if xy and e.x then
        local k = tostring(e.zone) .. "|" .. e.x .. "|" .. e.y
        if byKey[k] and math.abs(e.t - byKey[k]) > 15 and not e.guid then far[#far + 1] = e.item end
        byKey[k] = byKey[k] or e.t
      end
      local f = T.lootFrom(e)
      if e.src == "Pebbles" or e.src == "Equi" or e.src == "Healing Ward" then names[#names + 1] = tostring(f) end
      if e.item == "Bag of Ashen Warlock Bones" or e.item == "Slimy Pinecone" or e.item == "Herbal Soil Poultice" or e.item == "Lichbane" or e.item == "Plaguecrusher Greaves" then
        if e.src == "Quest reward" then quests[#quests + 1] = tostring(f) end
      end
      for k, cell in pairs(r.c) do
        if k == "from" and (cell.text == "Pebbles" or cell.text == "Equi" or cell.text == "Healing Ward" or cell.text == "Forgotten Soldier") then bad[#bad + 1] = "from=" .. cell.text end
      end
    end
    -- (20 Nov 22:30:47: stored "Forgotten Soldier", Mount Hyjal 0.6903, 0.6981; the coin row of the same kill at
    -- 22:30:49 is at 0.2225, 0.5418. The stamp was the last loot window's, first written at 22:22.)
    eq("Items, everything: the Formula of 20 Nov 22:30 shows no source, no place and no coordinates", form, "nil/nil/nil")
    eq("Items, everything: none of the 161 rows stamped 69.0, 69.8 over 33 minutes shows a place or coordinates", hyjal, 0)
    eq("Items, everything: no coordinates without a place", noPlace, 0)
    eq("Items, everything: no two shown rows more than 15 s apart share an exact stamp, unless each has its own loot window", table.concat(far, ","), "")
    -- (Pebbles and Equi are party members of the Sunken Temple run of 17 Nov, Healing Ward a totem)
    eq("Items, everything: a party member or a totem is never the source", table.concat(names, " "), "nil nil nil nil nil nil")
    eq("Items, everything: the 5 rewards turned in beside another quest name none", table.concat(quests, " "), "Quest Quest Quest Quest Quest")
    eq("Items, everything: no cell names a kill by timing", table.concat(bad, ","), "")
    check("Items, everything: 26 of 929 rows have their own place, under a third: no Place and no Coords column at 1600 px", ic.lootCols.loc == true and ic.lootCols.coords == true and tbl.cols.loc == nil and tbl.cols.coords == nil)
  end
  ic.setLootQuality("green"); M.settle()
  UI.SetWindowSize(1104, 697); M.settle()
  ic.setLootMode("byitem"); M.settle()
  -- (By item counts its own rows, items: 83 of them, their Count column sums to the 91 units of the 89 pickups)
  do
    local items, units = shown(ic.lootTables.byitem), 0
    for _, r in ipairs(items) do units = units + (tonumber(r.item.count) or 0) end
    eq("Items by item: 83 items green or better, 91 units in the Count column", #items .. " / " .. units .. " / " .. tostring(ic.lootSection.meta.text), "83 / 91 / 83 items green or better, not every item is kept")
  end
  local cols = {}
  for _, sp in ipairs(ic.lootTables.byitem.spec) do cols[#cols + 1] = sp.label end
  eq("Items by item: Item, Count, Last looted", table.concat(cols, "|"), "|Item|Count|Last looted")
  ic.setLootMode("newest"); M.settle()
end
say(("real_truth: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
