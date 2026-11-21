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
  eq("Data: the pickup", d.syncStatus.text.text, "Saved to everbuff.gg: Sat 21 Nov 11:45, 142 pulls")
  eq("Data: pulls waiting", d.stored.fights.label.text, "Pulls waiting \194\183 0")
  eq("Data: loot", d.stored.loot.label.text, "Loot \194\183 1,539 pickups")
  check("Data: no Clear on an empty store, no Events row", d.stored.fights.btn.shown == false and d.stored.events == nil)
  eq("Data: the count of pulls ever recorded is untouched", ns.DB.combat.fightSeq, 6879)
else check("Data: the settings page was built", false) end

-- ── Character > Leveling: the dungeon runs card never says all time ──
Real.open(S, "character/leveling"); M.settle()
local card
for _, cd in ipairs(ns.Progress.leveling.cards.cards) do if tostring(cd.label.text) == "DUNGEON RUNS" then card = cd end end
check("Leveling: the dungeon runs card counts the six stored runs and says since when, never all time", card and card.value.text == "6" and card.meta.text == "stored since 18 Nov", card and (tostring(card.value.text) .. " / " .. tostring(card.meta.text)))
say(("real_truth: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
