-- Pane tests for data accuracy (docs/UX_PRAGMATIC.md 0.2, 1.4, 1.5, 2.1 to 2.3): the screens of Dungeons, Fights and
-- Deaths on a small fixture with the shapes of a real save taken on 21 Nov 2026 (a level 58 Blackrock Spire run of a
-- party whose size the record does not hold, pulls already picked up by the desktop app, deaths with no killer).
-- Every expected number below was worked out from the stored values by hand, not through the addon:
--   the run entered at T, was inside 0 to 283 s, outside 321 s, inside 604 to 3539 s, a ghost 158 s, inside 3697 to
--   4627 s. Its clock (inside plus running back) is 283 s at the second visit and 3376 s at the third.
--   Highlord Omokk died at clock 1179, which is wall T + 1500; the first pull was at clock 348.
return function(P)
  local check, eq, M, ns, T = P.check, P.eq, P.M, P.ns, P.T
  local UI, R, L = ns.UI, ns.Runs, ns.RunsLegacy
  local D = ns.Dungeons.D
  local function strip(s) return (tostring(s or ""):gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%s+", ""):gsub("%s+$", "")) end
  local function shown(tbl) local out = {}; for i = 1, tbl.shownN or 0 do local r = tbl.rows[i]; if not (r.item and r.item.ebSection) then out[#out + 1] = r end end return out end
  local function hostOf(name) for _, tab in ipairs(T.tabs) do if tab.name == name then return tab end end end
  local function copy(v) if type(v) ~= "table" then return v end local o = {}; for k, x in pairs(v) do o[k] = copy(x) end return o end

  P.open("dungeons", "runs", 1104, 697, "normal")
  local c = ns.char()
  local dv = T.dungeonDetail(); if dv:IsShown() then dv.d.Close() end
  local now = GetServerTime()
  local T0 = now - 90000                       -- yesterday: no instance of this hour
  local keep = { runs = c.dungeonRuns, open = c.dungeonRun, stats = c.dungeonStats, locks = c.lockouts, copies = c.dungeonCopies,
    legacy = c.dungeonLegacy, gold = c.goldRuns, nLoot = #ns.DB.loot.log, fights = ns.DB.combat.fights, ack = ns.DB.combat.lastAck,
    nEv = #ns.DB.story.events }
  local function restore()
    c.dungeonRuns, c.dungeonRun, c.dungeonStats, c.lockouts, c.dungeonCopies = keep.runs, keep.open, keep.stats, keep.locks, keep.copies
    c.dungeonLegacy, c.goldRuns = keep.legacy, keep.gold
    local log = ns.DB.loot.log
    while #log > keep.nLoot do table.remove(log) end
    while #ns.DB.story.events > keep.nEv do table.remove(ns.DB.story.events) end
    ns.DB.combat.fights, ns.DB.combat.lastAck = keep.fights, keep.ack
    R.statsRebuild(c)
  end

  -- ── the stored run, as the save holds it (no size, no fight left) ──
  local BOSSES = { { 267, "Highlord Omokk", 1179, 43 }, { 269, "War Master Voone", 1430, 28 }, { 268, "Shadow Hunter Vosh'gajin", 1716, 86 },
    { 270, "Mother Smolderweb", 2572, 35 }, { 274, "Halycon", 3884, 27 }, { 273, "Gizrul the Slavener", 3935, 42 }, { 272, "Quartermaster Zigris", 4143, 37 } }
  local bosses = {}
  for i, b in ipairs(BOSSES) do bosses[i] = { enc = b[1], name = b[2], kill = b[3], combat = b[4] } end
  local rec = T.runRecord("Blackrock Spire", T0, 4148, { v = 2, endT = T0 + 4627, firstPull = 348, map = 229, diff = 1, bosses = bosses,
    secs = { inside = 4148, ghost = 158, outside = 321, offline = 0, active = 4107, combat = 1856, boss = 298 },
    visits = { { i = 0, o = 283, how = "zone", out = "alive", secs = 283, active = 278 },
      { i = 604, o = 3539, how = "zone", out = "ghost", secs = 2935, active = 2904, go = 321, fc = 348, looted = 10406, quests = 18400, lootValue = 118822, items = 30, xp = 58353 },
      { i = 3697, o = 4627, how = "ghost", out = "ghost", secs = 930, active = 925, gg = 158, fc = 3659, looted = 1206, lootValue = 61577, items = 8, xp = 4035 } },
    deaths = { { o = 3212, back = 165 }, { o = 4256, back = 74 } }, nDeaths = { me = 2, party = 0 },
    gold = { looted = 11612, quests = 18400, lootValue = 180399, items = 38, purse = 18835 },
    xp = { gain = 62388, kill = 30716, quest = 31672, n = 243, l0 = 58, p0 = 0.721, l1 = 59, p1 = 0.029, need = 209800 } })
  c.dungeonRuns, c.dungeonRun, c.dungeonStats, c.lockouts, c.dungeonCopies, c.dungeonLegacy = { rec }, nil, nil, {}, {}, {}
  R.statsRebuild(c)
  ns.DB.combat.fights = {}
  -- the loot of the run as the loot log holds it: the game hid every enemy name, so the source is a placeholder
  local LOOT = { { 941, "Prismcharm", "ff1eff00", "Picked up" }, { 1529, "Slamshot Shoulders", "ff0070dd", "Picked up" },
    { 1770, "Talisman of Evasion", "ff0070dd", "Creature" }, { 2451, "Bracers of Valor", "ff0070dd", "Creature" },
    { 2762, "Nightshade Cloak of the Gorilla", "ff1eff00", "an enemy" }, { 2857, "Engraved Cape of the Gorilla", "ff1eff00", "Picked up" },
    { 4231, "Slashclaw Bracers", "ff0070dd", "Picked up" }, { 4269, "Rhombeard Protector", "ff0070dd", "Creature" },
    { 700, "Runecloth", "ffffffff", "Creature" }, { 705, "Dense Stone", "ffffffff", "Picked up" }, { 710, "Broken Fang", "ff9d9d9d", "Creature" },
    { 1600, "Mark of the Dragon Lord", "ff0070dd", "Quest reward" } }
  table.sort(LOOT, function(a, b) return a[1] < b[1] end)
  for i, l in ipairs(LOOT) do ns.DB.loot.log[#ns.DB.loot.log + 1] = { t = T0 + l[1], item = l[2], q = l[3], src = l[4], count = l[2] == "Runecloth" and 3 or 1, id = 900000 + i, s = ns.DB.active } end

  -- ── Runs.wallOf: a moment on the run's clock is a wall time through the visits ──
  eq("wallOf: a clock in the first visit is T + clock", R.wallOf(rec, 100), T0 + 100)
  eq("wallOf: the time outside between two visits is not on the clock (Omokk: clock 1179 is T + 1500)", R.wallOf(rec, 1179), T0 + 1500)
  eq("wallOf: the run back as a ghost is on the clock (Halycon: clock 3884 is T + 4205)", R.wallOf(rec, 3884), T0 + 4205)
  eq("wallOf: no clock, no time", R.wallOf(rec, nil), nil)

  -- ── Dungeons > Runs with one stored run ──
  local lv = T.dungeonList(); M.settle()
  local rows = shown(lv.tbl)
  local row = rows[1]
  eq("Runs: the one stored run is the one row", #rows, 1)
  eq("Runs: Time is the time inside", row and row.c.dur.text, "1h 9m")
  eq("Runs: Bosses is the kills alone, never \"7/7\" from one run", row and row.c.boss.text, "7")
  eq("Runs: Deaths", row and row.c.death.text, "2")
  eq("Runs: Worth is the looted coin plus the items' vendor value, without the quest coin", row and row.c.worth.text, UI.money(11612 + 180399))
  check("Runs: Vs best is left out with nothing to compare", lv.colHidden.vs == true and lv.tbl.cols.vs == nil)
  eq("Runs: the hero's answer is the result", lv.heroVerdict, "7 bosses in 1h 9m")
  check("Runs: no summary line with no instance this hour and no lockout", lv.summaryN == 0 and lv.summary.shown == false, tostring(lv.summaryN))
  check("Runs: the instance and lockout segments are nil then", D.instanceSegment() == nil and D.lockSegment() == nil)
  check("Runs: the section claims no count of runs", lv.section.meta == nil or lv.section.meta.shown == false or (lv.section.meta.text or "") == "", lv.section.meta and lv.section.meta.text)
  check("Runs: By dungeon does not exist with one dungeon", D.byVisible() == false)
  c.dungeonCopies = { { t = now - 600, id = rec.id, why = "first" } }
  R._gen = (R._gen or 0) + 1
  local seg = D.instanceSegment()
  check("Runs: an instance entered this hour is said", seg ~= nil and strip(seg.text):gsub("%*", "") == "1 instance this hour", seg and seg.text)
  c.dungeonCopies = {}

  -- ── the run page ──
  T.openRun(rec); M.settle()
  local meta = dv.metaText
  check("Run: the META has the day, the clock span and the level", meta:find(UI.fmtClock(T0) .. " to " .. UI.fmtClock(T0 + 4627), 1, true) ~= nil and meta:find("level 58", 1, true) ~= nil, meta)
  check("Run: a record with no size is not called solo, a group or a party, and no re-entry count", meta:find("solo", 1, true) == nil and meta:find("group", 1, true) == nil
    and meta:find("party", 1, true) == nil and meta:find("re-entered", 1, true) == nil, meta)
  eq("Run: four cards", #dv.cards, 4)
  eq("Run: TIME", dv.card.time.value.text, "1h 9m")
  eq("Run: TIME meta is the time dead or outside (158 + 321 s)", dv.card.time.meta.text, "7m 59s dead or outside")
  eq("Run: BOSSES has no total", dv.card.bosses.value.text, "7")
  eq("Run: BOSSES meta is the boss clock, first pull to last kill (4143 - 348 s)", dv.card.bosses.meta.text, "boss clock 1h 3m")
  eq("Run: XP", dv.card.xp.value.text, "62,388")
  eq("Run: XP per hour of the 4148 s inside", dv.card.xp.meta.text, "54,146 per hour")
  eq("Run: WORTH", dv.card.worth.value.text, UI.money(192011))
  eq("Run: WORTH names its two parts", D.worthParts(rec and R.view(rec, false, false)), ("%s coin \194\183 %s items at vendor prices"):format(UI.money(11612), UI.money(180399)))
  check("Run: no card says Coin looted 3g (looted and quest coin together)", (function() for _, cd in ipairs(dv.cards) do if tostring(cd.value.text) == UI.money(11612 + 18400) then return false end end return true end)())
  -- bosses: boss 1 since entering, the others since the kill before
  local br = shown(dv.tables.bosses)
  eq("Run: seven boss rows", #br, 7)
  eq("Run: boss 1 Killed at", br[1] and br[1].c.at.text, "19m 39s")
  eq("Run: boss 1 Split is since entering, the same clock as Killed at (not 13m 51s from the first pull)", br[1] and br[1].c.since.text, "19m 39s")
  eq("Run: boss 2 Split is since the kill before (1430 - 1179 s)", br[2] and br[2].c.since.text, "4m 11s")
  eq("Run: boss 6 Split", br[6] and br[6].c.since.text, "51s")
  eq("Run: a kill clock past the hour keeps its seconds (3884 s)", br[5] and br[5].c.at.text, "1h 4m 44s")
  eq("Run: boss 5 fight length", br[5] and br[5].c.len.text, "27s")
  eq("Run: the column is named Split", dv.tables.bosses.spec[4].label, "Split")
  eq("Run: its header says what it measures", dv.tables.bosses.spec[4].tip, "Boss 1: since entering. Others: since the previous kill.")
  check("Run: no Vs best column with nothing to compare", dv.bossVsShown == false)
  check("Run: the bests still measure from the first pull", R.splits(rec)[267].seg == 1179 - 348 and R.measure(rec) == 4143 - 348)
  eq("Run: the deaths are one line, each at its wall time with the time down",
    dv.deathLine, ("Deaths: %s (2m 45s down) \194\183 %s (1m 14s down)"):format(UI.fmtClock(T0 + 3533), UI.fmtClock(T0 + 4577)))
  check("Run: no Deaths table when no row names a killer", dv.sections.deaths.shown == false)
  -- loot: green and better as rows, the rest one line, no vendor price column
  eq("Run: the Loot table lists the 8 green and better drops (no quest reward, no white, no grey)", #dv.lootItems, 8)
  eq("Run: the section says so", dv.sections.loot.meta.text, "8 green or better")
  eq("Run: the rest is one line", dv.lootMore, "3 more: 2 white, 1 grey")
  check("Run: the Loot table has no vendor price column", dv.tables.loot.cols.price == nil and dv.tables.loot.cols.src ~= nil and dv.tables.loot.cols.at ~= nil)
  local from, tip = {}, {}
  for _, it in ipairs(dv.lootItems) do from[it.row.item] = it.from or ""; tip[it.row.item] = it.fromTip end
  local want = { ["Slamshot Shoulders"] = "Highlord Omokk", ["Talisman of Evasion"] = "War Master Voone", ["Slashclaw Bracers"] = "Halycon",
    ["Rhombeard Protector"] = "Gizrul the Slavener", ["Bracers of Valor"] = "Trash", ["Nightshade Cloak of the Gorilla"] = "Trash",
    ["Prismcharm"] = "", ["Engraved Cape of the Gorilla"] = "" }
  local bad = {}
  for item, src in pairs(want) do if from[item] ~= src then bad[#bad + 1] = item .. "=" .. tostring(from[item]) end end
  check("Run: From names the boss killed at most 90 s before the row, Trash for an enemy with none, blank otherwise", #bad == 0, table.concat(bad, " | "))
  eq("Run: the hover says how a boss was derived (the row is 29 s after his death at T + 1500)", tip["Slamshot Shoulders"], "Looted 29s after Highlord Omokk died. The game hides enemy names in dungeons.")
  eq("Run: and how Trash was", tip["Bracers of Valor"], "No boss died in the 90s before this. The game hides enemy names in dungeons.")
  local words = {}
  for _, r in ipairs(shown(dv.tables.loot)) do words[#words + 1] = r.c.src.text end
  local all = "|" .. table.concat(words, "|") .. "|"
  check("Run: no placeholder word is shown as a source", all:find("|Creature|", 1, true) == nil and all:find("|an enemy|", 1, true) == nil and all:find("|Picked up|", 1, true) == nil
    and all:find("|Unknown source|", 1, true) == nil, all)
  -- a named source is shown as stored, and a boss 91 s before is not named
  eq("sourceOf: a stored name is shown as stored", (D.sourceOf(R.view(rec, false, false), { t = T0 + 1510, src = "Scarshield Legionnaire" })), "Scarshield Legionnaire")
  eq("sourceOf: 90 s after the kill is the boss", (D.sourceOf(R.view(rec, false, false), { t = T0 + 1590, src = "Creature" })), "Highlord Omokk")
  eq("sourceOf: 91 s after it is not", (D.sourceOf(R.view(rec, false, false), { t = T0 + 1591, src = "Creature" })), "Trash")
  eq("sourceOf: a row before the kill is not his", (D.sourceOf(R.view(rec, false, false), { t = T0 + 1499, src = "Picked up" })), nil)
  -- sections with nothing in them are not on the page
  check("Run: no Party, Pace or Pulls section when the save holds none of it", dv.sections.party.shown == false and dv.sections.pace.shown == false and dv.sections.pulls.shown == false)
  local lines = {}
  for _, fs in ipairs(P.descendants(dv)) do if P.visible(fs) and type(fs.text) == "string" then lines[#lines + 1] = strip(fs.text) end end
  local page = "\n" .. table.concat(lines, "\n") .. "\n"
  check("Run: nothing on the page is a lone dash, \"7 of 7\", \"first run\" or \"solo\"", page:find("\n-\n", 1, true) == nil and page:find("7 of 7", 1, true) == nil
    and page:lower():find("first run", 1, true) == nil and page:find("solo", 1, true) == nil)
  check("Run: the desktop pickup is not a sentence on the page", page:find("desktop app", 1, true) == nil)
  dv.d.Close()
  -- solo only from a stored size of 1
  local solo = T.runRecord("Ragefire Chasm", T0 - 9000, 600, { size = 1 })
  c.dungeonRuns[#c.dungeonRuns + 1] = solo
  T.openRun(solo); M.settle()
  check("Run: a record whose size is 1 says solo", dv.metaText:find("solo", 1, true) ~= nil, dv.metaText)
  dv.d.Close()
  table.remove(c.dungeonRuns)

  -- ── a second run of the same bosses: now there is a total and a comparison ──
  local b2 = copy(bosses)
  b2[#b2 + 1] = { enc = 275, name = "Overlord Wyrmthalak", kill = 4300, combat = 60 }
  local rec2 = T.runRecord("Blackrock Spire", T0 - 30000, 4400, { v = 2, firstPull = 348, map = 229, diff = 1, bosses = b2 })
  table.insert(c.dungeonRuns, 1, rec2)
  R.statsRebuild(c)
  T.openRun(rec); M.settle()
  check("Run: with a second stored run the dungeon has a learned total", dv.card.bosses.value.text:find(" of ", 1, true) ~= nil, dv.card.bosses.value.text)
  dv.d.Close()
  table.remove(c.dungeonRuns, 1)
  R.statsRebuild(c)

  -- ── the runs from before the run store: copied once from the gold runs, listed as partial rows ──
  local G0 = T0 - 150000
  c.goldRuns = { { inst = "Maraudon", items = 36, lootValue = 93437, looted = 365, quests = 0, secs = 4250, t = G0 },
    { inst = "Blackrock Depths", items = 109, lootValue = 438828, looted = 38404, quests = 0, secs = 8430, t = G0 + 48942 },
    { inst = "Blackrock Depths", items = 145, lootValue = 518686, looted = 53083, quests = 45463, secs = 9220, t = G0 + 65059 },
    { inst = "Blackrock Depths", items = 12, lootValue = 30204, looted = 795, quests = 23144, secs = 2010, t = G0 + 84491 },
    { inst = "Blackrock Spire", items = 72, lootValue = 159344, looted = 14926, quests = 18400, secs = 4490, t = G0 + 131633 },
    { inst = "Blackrock Spire", items = 38, lootValue = 180399, looted = 11612, quests = 18400, secs = 4120, t = T0 },
    { inst = "Razorfen Kraul", items = 0, lootValue = 0, looted = 0, quests = 0, secs = 30, t = G0 + 500 } }
  c.dungeonLegacy = nil
  eq("legacy: five gold runs have no run record and become rows; the stored run's own gold run and a 30 s peek do not", L.harvest(c), 5)
  local ids = {}
  for _, r in ipairs(c.dungeonLegacy) do ids[#ids + 1] = r.id end
  eq("legacy: the rows are oldest first, with the gold run's start as their id", table.concat(ids, " "), ("g%d g%d g%d g%d g%d"):format(G0, G0 + 48942, G0 + 65059, G0 + 84491, G0 + 131633))
  local r3 = c.dungeonLegacy[3]
  check("legacy: a row holds what the gold run stored and nothing else", r3.inst == "Blackrock Depths" and r3.secs == 9220 and r3.looted == 53083 and r3.quests == 45463
    and r3.items == 145 and r3.lootValue == 518686 and r3.src == "gold" and r3.bosses == nil and r3.deaths == nil and r3.xp == nil and r3.endT == nil)
  check("legacy: a row with no quest coin stores no 0", c.dungeonLegacy[1].quests == nil)
  eq("legacy: a second load copies nothing", L.harvest(c), nil)
  eq("legacy: and the list is as it was", #c.dungeonLegacy, 5)
  local before = c.dungeonRuns
  c.dungeonRuns = {}
  L.harvest(c)
  eq("legacy: a run record deleted by hand does not come back as a row", #c.dungeonLegacy, 5)
  c.dungeonRuns = before
  check("legacy: the rows never enter the statistics", c.dungeonStats["blackrock depths"] == nil and c.dungeonStats["maraudon"] == nil and c.dungeonStats["blackrock spire"].n == 1)
  eq("legacy: a session holds the runs that began in it, a record and a row alike", L.inSession({ startedEpoch = G0 + 131000, endedEpoch = T0 + 9000, dungeons = 22 }), 2)
  eq("legacy: a session with no stored run counts none, whatever its old entry counter says", L.inSession({ startedEpoch = G0 - 9000, endedEpoch = G0 - 100, dungeons = 22 }), 0)
  lv = T.dungeonList(); M.settle()
  rows = shown(lv.tbl)
  eq("Runs: the list holds the stored run and the five rebuilt rows", #rows, 6)
  local part, full = 0, 0
  for _, r in ipairs(rows) do if r.run.legacy then part = part + 1 else full = full + 1 end end
  check("Runs: five of them are partial", part == 5 and full == 1)
  local brd
  for _, r in ipairs(rows) do if r.run.id == ("g%d"):format(G0 + 65059) then brd = r end end
  check("Runs: a rebuilt row is marked partial after its name", brd and strip(brd.c.name.text) == "Blackrock Depths partial", brd and brd.c.name.text)
  eq("Runs: its Time is the gold run's seconds", brd and brd.c.dur.text, "2h 33m")
  eq("Runs: its Worth is coin plus item value (the quest coin is not loot)", brd and brd.c.worth.text, UI.money(53083 + 518686))
  check("Runs: with one full run in six, Vs best, Bosses and Deaths are left out (under a third of the rows have a value)", lv.colHidden.vs == true and lv.colHidden.boss == true
    and lv.colHidden.death == true and lv.tbl.cols.boss == nil and lv.tbl.cols.death == nil and lv.tbl.cols.worth ~= nil)
  eq("Runs: the hero is the newest run record, not a partial row", lv.heroRun and lv.heroRun.id, rec.id)
  if brd then
    brd:GetScript("OnEnter")(brd)
    check("Runs: the row's hover says what partial means", table.concat(_G.GameTooltip.lines or {}, "|"):find("Time and loot only", 1, true) ~= nil, table.concat(_G.GameTooltip.lines or {}, "|"))
    brd:GetScript("OnLeave")(brd)
    brd:GetScript("OnClick")(brd, "LeftButton"); M.settle()
    check("Rebuilt run: its page opens", dv:IsShown() and dv.run.legacy == true)
    eq("Rebuilt run: two cards", #dv.cards, 2)
    eq("Rebuilt run: Time", dv.cards[1].value.text, "2h 33m")
    eq("Rebuilt run: Worth", dv.cards[2].value.text, UI.money(53083 + 518686))
    local any = {}
    for k, sec in pairs(dv.sections) do if sec.shown ~= false then any[#any + 1] = k end end
    check("Rebuilt run: nothing else is on the page, and no sentence says what is absent", #any == 0 and #dv.actBtns() == 0 and dv.deathLine == nil and dv.lootMore == nil, table.concat(any, ","))
    check("Rebuilt run: the title carries PARTIAL", dv.badges[1] and dv.badges[1].shown ~= false and dv.badges[1].ebText == "PARTIAL")
    dv.d.Close()
  end
  -- ── the load: every character is read once, before the acknowledgement prunes anything; the ack never touches the rows ──
  do
    local src = assert(io.open("Everbuff/Core.lua", "rb")):read("*a")
    local h, a = src:find("ns.RunsLegacy.harvestAll, db", 1, true), src:find('ns.applyAck(EverbuffAck, "file")', 1, true)
    check("load: Core.lua copies the old runs before it applies the desktop's acknowledgement", h and a and h < a)
    local other = { goldRuns = { { inst = "Wailing Caverns", t = 1000, secs = 2913, looted = 40, items = 3, lootValue = 900, quests = 0 } } }
    local fresh = { name = "new" }
    local db = { characters = { a = other, b = fresh, c = c } }
    eq("load: every character of the save is read (one row here; the character read before gives none)", L.harvestAll(db), 1)
    check("load: a character with no gold run gets an empty list, so a later load copies nothing for it", type(fresh.dungeonLegacy) == "table" and #fresh.dungeonLegacy == 0)
    fresh.goldRuns = { { inst = "Ragefire Chasm", t = 5000, secs = 900, looted = 10 } }
    eq("load: a gold run that closes after the first load is not copied (from then on every run has its own record)", L.harvestAll(db), 0)
    check("load: an invalid row is dropped on load", (function()
      other.dungeonLegacy[2] = { id = 7, inst = "x" }
      L.harvest(other)
      return #other.dungeonLegacy == 1 and other.dungeonLegacy[1].id == "g1000"
    end)())
    -- the acknowledgement prunes sessions, fights, loot rows and events; the runs and the rebuilt rows stay
    local sid = "truth-acked-session"
    ns.DB.sessions[sid] = { id = sid, guid = ns.charGuid(), startedEpoch = now - 50000, endedEpoch = now - 40000, fights = 2, dungeons = 22 }
    local keepFights = ns.DB.combat.fights
    ns.DB.combat.fights = { { uid = "ack-1", session = sid, startEpoch = now - 45000, duration = 10, outcome = "kill" }, { uid = "ack-2", session = sid, startEpoch = now - 44000, duration = 10, outcome = "kill" } }
    local nLegacy, nRuns = #c.dungeonLegacy, #c.dungeonRuns
    local keepAckT = ns.DB.combat.lastAck
    local marked = ns.applyAck({ uids = { ["ack-1"] = true, ["ack-2"] = true }, sessions = { [sid] = true } }, "file")
    local sync = ns.SyncState()
    check("ack: the acked pulls leave the addon, and the pickup records how many it took", marked == 2 and #ns.DB.combat.fights == 0 and sync.stored == 0 and sync.ackFights == 2 and sync.ackAt ~= nil, marked)
    check("ack: the session record is gone, the run records and the rebuilt rows are untouched", ns.DB.sessions[sid] == nil and #c.dungeonLegacy == nLegacy and #c.dungeonRuns == nRuns)
    ns.DB.combat.fights, ns.DB.combat.lastAck = keepFights, keepAckT
  end
  restore()

  -- ── Home > Fights: the tab exists only while pulls are stored ──
  P.open("home", "now", 1104, 697, "normal")
  local home = hostOf("Home")
  local keepF, keepAck = ns.DB.combat.fights, ns.DB.combat.lastAck
  ns.DB.combat.fights = {}
  ns.DB.combat.lastAck = { at = now - 3600, fights = 142, source = "file" }
  UI.Open("Home", "fights"); M.settle()
  check("Fights: with no pull stored there is no Fights tab, and opening it stays where the window was", home.ctl.hidden.fights == true and home.ctl.active ~= "fights", tostring(home.ctl.active))
  local sync = ns.SyncState()
  check("Fights: the one sync read says what is stored and what the last pickup took", sync.stored == 0 and sync.waiting == 0 and sync.ackFights == 142 and sync.ackAt == now - 3600)
  local fl = T.fightsList()
  if fl then
    ns.DB.combat.fights = {}
    UI.Open("Home", "fights"); M.settle()
    -- (the list itself, drawn although its tab is hidden: it must claim nothing from an empty store)
    fl.setFilter("all"); M.settle()
    local sum = fl.summary.Text and fl.summary.Text() or ""
    check("Fights: an empty store counts nothing: no wipes, no \"did not die\", no time in combat", sum == "" or (sum:find("wipe", 1, true) == nil and sum:find("did not die", 1, true) == nil and sum:find("in combat", 1, true) == nil), sum)
    check("Fights: and does not say that nothing ever happened", tostring(fl.tbl.state or ""):find("Fight anything", 1, true) == nil and fl.tbl.state == "No pull stored.", tostring(fl.tbl.state))
  end
  -- two pulls of this character and one of another: the tab is back, scoped to what is stored
  local other = "truth-other-session"
  ns.DB.sessions[other] = { id = other, guid = "Player-1-0000FFFF", startedEpoch = now - 5000 }
  ns.DB.combat.fights = {
    { uid = "t-1", session = ns.DB.active, startEpoch = now - 1800, duration = 40, outcome = "kill", foes = { "Scarshield Legionnaire" }, zone = "Burning Steppes" },
    { uid = "t-2", session = ns.DB.active, startEpoch = now - 1200, duration = 25, outcome = "death", foes = { "Blackrock Slayer" }, zone = "Burning Steppes" },
    { uid = "t-3", session = other, startEpoch = now - 1500, duration = 99, outcome = "wipe", foes = { "Someone else's foe" }, zone = "Elwynn Forest" } }
  UI.Open("Home", "fights"); M.settle()
  check("Fights: with pulls stored the tab is there and opens", not home.ctl.hidden.fights and home.ctl.active == "fights", tostring(home.ctl.active))
  fl = T.fightsList()
  fl.setFilter("all"); M.settle()
  local sum = fl.summary.Text()
  check("Fights: the line counts the stored pulls of this character only", sum:find("2 pulls", 1, true) ~= nil and sum:find("0 wipes", 1, true) ~= nil and sum:find("1 death", 1, true) ~= nil
    and sum:find("1m 5s in combat", 1, true) ~= nil, sum)
  eq("Fights: the section says where the stored pulls start", fl.section.label.text, ("Pulls since " .. UI.fmtStamp(now - 1800)):upper())
  fl.setFilter("wipe"); M.settle()
  eq("Fights: an empty filter is scoped to the stored pulls", fl.tbl.state, "No wipe among the stored pulls.")
  fl.setFilter("all"); M.settle()
  ns.DB.sessions[other] = nil
  ns.DB.combat.fights, ns.DB.combat.lastAck = keepF, keepAck

  -- ── Home > Deaths: only while a stored death names its killer; a missing killer is blank ──
  local evs = ns.DB.story.events
  local keepEv = { unpack(evs) }
  for i = #evs, 1, -1 do if evs[i].kind == "DEATH" then table.remove(evs, i) end end
  local sesRec = ns.DB.sessions[ns.DB.active]
  local keepDeaths = sesRec and sesRec.deaths
  evs[#evs + 1] = { kind = "DEATH", t = now - 5000, s = ns.DB.active, zone = "Blackrock Spire", sub = "Hordemar City", text = "You died  \194\183  Level 59", durLoss = 10, downtime = 165 }
  evs[#evs + 1] = { kind = "DEATH", t = now - 4000, s = ns.DB.active, zone = "Blackrock Spire", sub = "Hordemar City", text = "You died  \194\183  Level 59", durLoss = 10, downtime = 73 }
  ns.DB.combat.fights = {}
  UI.Open("Home", "deaths"); M.settle()
  check("Deaths: two dungeon deaths with no killer recorded make no tab", home.ctl.hidden.deaths == true and home.ctl.active ~= "deaths", tostring(home.ctl.active))
  local dd = T.collectDeaths()
  check("Deaths: the two are still read from the events, with no killer and no coordinates", #dd == 2 and dd[1].killer == nil and dd[2].killer == nil and dd[1].x == nil and dd[1].level == 59 and dd[2].downtime == 73)
  evs[#evs + 1] = { kind = "DEATH", t = now - 3000, s = ns.DB.active, zone = "Burning Steppes", text = "You died  \194\183  Level 59", foe = "Blackrock Slayer", downtime = 40, x = 0.5, y = 0.5 }
  UI.Open("Home", "deaths"); M.settle()
  check("Deaths: a death that names its killer brings the tab", not home.ctl.hidden.deaths and home.ctl.active == "deaths", tostring(home.ctl.active))
  local view = T.deathsView(); M.settle()
  local drows = {}
  for i = 1, #view.tbl.rows do local r = view.tbl.rows[i]; if r.shown ~= false and r.c and r.c.by then drows[#drows + 1] = r end end
  check("Deaths: three rows, newest first", #drows == 3 and drows[1].c.by.text == "Blackrock Slayer", #drows)
  check("Deaths: a killer the game hid is a blank cell, never \"unknown\"", drows[2] and drows[2].c.by.text == "" and drows[3].c.by.text == "", drows[2] and drows[2].c.by.text)
  check("Deaths: the place is the zone, not the stale subzone", drows[2] and drows[2].c.zone.text == "Blackrock Spire")
  check("Deaths: no gear column", drows[1].c.gear == nil)
  check("Deaths: downtime in the one dialect", drows[2].c.down.text == "1m 13s" and drows[3].c.down.text == "2m 45s", drows[2].c.down.text)
  local stext = tostring(view.summary.text or (view.summary.GetText and view.summary:GetText()) or "")
  check("Deaths: the line says where the stored history starts, and names no \"most often\" killer", stext:find("^Deaths since ") ~= nil and stext:find("most often", 1, true) == nil
    and stext:find("deadliest", 1, true) == nil, stext)
  check("Deaths: \"most in\" needs 3 deaths in 2 places", stext:find("most in Blackrock Spire (2)", 1, true) ~= nil, stext)
  for i = #evs, 1, -1 do evs[i] = nil end
  for i, e in ipairs(keepEv) do evs[i] = e end
  ns.DB.combat.fights = keepF
  if sesRec then sesRec.deaths = keepDeaths end
  UI.Open("Home", "now"); M.settle()
end
