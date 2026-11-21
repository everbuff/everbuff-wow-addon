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
check("Runs: the stored run: Blackrock Spire, 1h 9m, worth 19g 20s 11c (11,612 + 180,399 copper)", top and top.run.name == "Blackrock Spire" and not top.run.legacy and top.c.dur.text == "1h 9m"
  and top.c.worth.text == UI.money(192011), top and top.c.worth.text)
local want = { { "Blackrock Spire", 4490, 14926 + 159344 }, { "Blackrock Depths", 2010, 795 + 30204 }, { "Blackrock Depths", 9220, 53083 + 518686 },
  { "Blackrock Depths", 8430, 38404 + 438828 }, { "Maraudon", 4250, 365 + 93437 } }
for i, w in ipairs(want) do
  local r = rows[i + 1]
  check(("Runs: rebuilt row %d: %s, %d s, worth %d copper"):format(i, w[1], w[2], w[3]), r and r.run.legacy and r.run.name == w[1] and r.run.inside == w[2] and (D.worth(r.run)) == w[3]
    and r.c.worth.text == UI.money(w[3]) and strip(r.c.name.text) == w[1] .. " partial", r and (r.run.name .. " " .. tostring(r.run.inside)))
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
eq("Run: WORTH", dv.card.worth.value.text, UI.money(192011))
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
  check("Run: no purse line under the loot (the WORTH card has the coin)", dv.purseLine == nil and page:find("gained inside", 1, true) == nil and page:find("1g 88s", 1, true) == nil, page)
  eq("Run: the XP hover has the split and the levels (30,716 + 31,672 = 62,388; 58.7 to 59.0)", table.concat(dv.xpTip, " | "),
    "XP earned inside, and per hour of the time inside. | 30,716 from kills, 31,672 from quests. | Level 58.7 to 59.0.")
  eq("Run: the WORTH hover has the purse (18,835 copper) beside the looted coin (11,612)", dv.purseTip, "Your purse grew by " .. ns.fmtMoney(18835) .. " inside, quest rewards aside. Looted coin was " .. ns.fmtMoney(11612) .. ".")
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
eq("Run: 8 green or better", #dv.lootItems, 8)
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
do
  local nv = T.journeyRefresh(); M.settle()
  local card = nv.cards.cards[4]
  check("Now: the DEATHS card is not a link while Deaths has no page", card.ebNoClick == true and card.chev.shown == false)
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
  check("Data: row 1 is the status, CAPTURING with its place", items[1] == d.rec and tostring(d.rec.plain):find("^CAPTURING") ~= nil, d.rec.plain)
  check("Data: row 2 is the pickup", items[2] == d.syncStatus)
  eq("Data: the pickup", d.syncStatus.plain, "Saved to everbuff.gg: Sat 21 Nov 11:45, 142 pulls")
  check("Data: row 3 is the pulls waiting", items[3] == d.stored.fights)
  eq("Data: pulls waiting", d.stored.fights.plain, "Pulls waiting \194\183 0")
  check("Data: row 4 is the loot", items[4] == d.stored.loot)
  eq("Data: loot", d.stored.loot.plain, "Loot \194\183 1,539 pickups")
  check("Data: no Events row; the paste box and the Clears are under Advanced, collapsed", d.stored.events == nil and #ns.SettingsView.data.sections == 2
    and d.pasteRow.shown == false and d.clear.fights.shown == false and d.clear.loot.shown == false and d.stored.fights.btn == nil)
  ns.DB.settings.advancedOpen = true; ns.SettingsView.refreshData(); M.settle()
  check("Data: Advanced open: the paste box, a Clear for the loot (1,539 rows), none for the empty pull store", d.pasteRow.shown ~= false and d.clear.loot.shown ~= false and d.clear.fights.shown == false)
  ns.DB.settings.advancedOpen = nil; ns.SettingsView.refreshData(); M.settle()
  eq("Data: the count of pulls ever recorded is untouched", ns.DB.combat.fightSeq, 6879)
else check("Data: the settings page was built", false) end

-- ── Character > Leveling: the dungeon runs card never says all time ──
Real.open(S, "character/leveling"); M.settle()
local card
for _, cd in ipairs(ns.Progress.leveling.cards.cards) do if tostring(cd.label.text) == "DUNGEON RUNS" then card = cd end end
check("Leveling: the dungeon runs card counts the six stored runs and says since when, never all time", card and card.value.text == "6" and card.meta.text == "stored since 18 Nov", card and (tostring(card.value.text) .. " / " .. tostring(card.meta.text)))
say(("real_truth: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
