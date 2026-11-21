-- The Dungeons, Fights, Deaths and Data and sync screens on a real save, against numbers worked out from that save by
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
eq("Home: no Activity tab (0.5, 1.3)", home.ctl.hidden.activity, true)
eq("Home: Open on Activity reports false and lands on Now", UI.Open("Home", "activity"), false); M.settle()
eq("Home: Activity falls back to Now", home.ctl.active, "now")
-- ── Home > Now at the level cap (1.1) ──
do
  local nv = T.journeyRefresh(); M.settle()
  eq("Now: the title is the whole name", nv.hero.title.text, "Iron Hart")
  check("Now: who that is, beside the name", tostring(nv.hero.titleMeta.text):find("^Level 60 ") ~= nil and tostring(nv.hero.titleMeta.text):find("Orgrimmar", 1, true) ~= nil, nv.hero.titleMeta.text)
  -- (the session of 11:47: 281,985 + 27,880 + 45 = 309,910 copper spent, nothing earned)
  eq("Now: the hero is the session's gold, -30g 99s", nv.hero.hero.text, UI.money(-309910, true) .. " this session")
  eq("Now: no per hour figure 9 minutes into the session", strip(nv.hero.meta1.text), "")
  check("Now: the session ledger behind it", nv.sessionGold.gained == 0 and nv.sessionGold.spent == 309910 and nv.sessionGold.played < 1800 and nv.sessionGold.perHour == nil, nv.sessionGold.played)
  local labels, byKey = {}, {}
  for i, d in ipairs(nv.cardDefs) do labels[i] = d.label; byKey[d.key] = nv.cardRow.cards[i] end
  eq("Now: the cards, each with a value: no XP per hour, no DEATHS at 0", table.concat(labels, " | "), "Balance | Played | Last run | Saved to everbuff.gg")
  check("Now: BALANCE 12s 19c of 1,219 copper, all characters 120,078", byKey.balance.value.text == UI.money(1219) and byKey.balance.meta.text == "all characters " .. UI.money(120078), byKey.balance.meta.text)
  check("Now: PLAYED has no second line", strip(byKey.played.meta.text) == "" and tostring(byKey.played.value.text):find("^%d+m$") ~= nil, byKey.played.value.text)
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
  check("Now: the largest is the 28g 19s buyout at 11:48", nv.lookList[1].title == "Buyout" and nv.lookList[1].meta == UI.money(-281985, true) .. " \194\183 Auction house \194\183 11:48", titles[1])
  check("Now: the flight names what it is", nv.lookList[3].title == "Flight: Tal", titles[3])
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
  eq("Data: loot", d.stored.loot.plain, "Loot: 1,539 pickups")
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
  for _, r in ipairs(shown(v.levels.tbl)) do got[#got + 1] = r.c.level.text .. " " .. r.c.reached.text .. " " .. r.c.zone.text end
  eq("Leveling: 21 levels have a recorded moment, and only they are listed", #got, 21)
  local lv2 = {}
  for _, r in ipairs(v.levelRows) do lv2[#lv2 + 1] = r.level end
  eq("Leveling: which levels", table.concat(lv2, " "), "60 59 58 57 54 53 51 50 49 47 46 45 44 41 40 39 29 28 27 3 2")
  eq("Leveling: row 1", got[1], "60 Fri 20 Nov, 22:49 Mount Hyjal")
  eq("Leveling: row 2", got[2], "59 Fri 20 Nov, 16:05 Blackrock Spire")
  eq("Leveling: row 3 (58, from a session record: the event list no longer has it)", got[3], "58 Thu 19 Nov, 21:58 Mulgore")
  eq("Leveling: the last row", got[21], "2 Thu 5 Nov, 03:13 Tirisfal Glades")
  eq("Leveling: one muted line counts the 38 other levels", v.noteText, "38 levels have no recorded date.")
  check("Leveling: no dash stands for a date", (table.concat(got, "\n") .. "\n"):find(" %- ") == nil)
end
say(("real_truth: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
