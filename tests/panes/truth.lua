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
  -- (the purse gained 18,835 inside, quest coin aside; 11,612 of it was booked as looted. The coin is the 18,835.)
  eq("Runs: Worth is the run's coin plus the items' vendor value, without the quest coin", row and row.c.worth.text, UI.money(18835 + 180399))
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
  eq("Run: WORTH (19g 92s)", dv.card.worth.value.text, UI.money(199234))
  eq("Run: WORTH names its two parts, the coin 1g 88s", D.worthParts(rec and R.view(rec, false, false)), ("%s coin \194\183 %s items at vendor prices"):format(UI.money(18835), UI.money(180399)))
  check("Run: no card says Coin looted 3g (looted and quest coin together)", (function() for _, cd in ipairs(dv.cards) do if tostring(cd.value.text) == UI.money(11612 + 18400) then return false end end return true end)())
  -- bosses: Killed at and Split are on the run's clock (the stored kill), boss 1 its kill clock, the others since the
  -- kill before. The clock stood still for the 321 s outside, so Omokk's 19m 39s is not the 25m 0s since entering:
  -- the headers say which clock it is and never "since entering".
  local br = shown(dv.tables.bosses)
  eq("Run: seven boss rows", #br, 7)
  eq("Run: boss 1 Killed at", br[1] and br[1].c.at.text, "19m 39s")
  eq("Run: boss 1 Split is its kill clock, the same clock as Killed at (not 13m 51s from the first pull)", br[1] and br[1].c.since.text, "19m 39s")
  eq("Run: that kill was 25m 0s after entering by the wall clock (321 s outside are not on the run's clock)", R.wallOf(rec, 1179) - T0, 1500)
  eq("Run: boss 2 Split is since the kill before (1430 - 1179 s)", br[2] and br[2].c.since.text, "4m 11s")
  eq("Run: boss 6 Split", br[6] and br[6].c.since.text, "51s")
  eq("Run: a kill clock past the hour keeps its seconds (3884 s)", br[5] and br[5].c.at.text, "1h 4m 44s")
  eq("Run: boss 5 fight length", br[5] and br[5].c.len.text, "27s")
  eq("Run: the column is named Split", dv.tables.bosses.spec[4].label, "Split")
  eq("Run: its header says what it measures", dv.tables.bosses.spec[4].tip, "Boss 1: the run's clock at its kill. Others: since the previous kill. Time outside the dungeon alive or offline is not counted.")
  eq("Run: Killed at says which clock it is on", dv.tables.bosses.spec[3].tip, "The run's clock when the boss died. It stops while you are outside the dungeon alive or offline, so it can be less than the time since you entered.")
  check("Run: neither header claims a time since entering as its value", dv.tables.bosses.spec[4].tip:find("since entering", 1, true) == nil and dv.tables.bosses.spec[3].label == "Killed at")
  -- (the TIME hover's times of day go through the visits: first pull clock 348 is T + 669, last kill clock 4143 is T + 4464)
  check("Run: the TIME hover places the first pull and the last kill on the wall clock, not at entry plus the run's clock",
    dv.clockSentence == ("Your clocks: entered %s, first pull %s, last kill %s, left %s."):format(UI.fmtClock(T0), UI.fmtClock(T0 + 669), UI.fmtClock(T0 + 4464), UI.fmtClock(T0 + 4627)), dv.clockSentence)
  check("Run: no Vs best column with nothing to compare", dv.bossVsShown == false)
  check("Run: the bests still measure from the first pull", R.splits(rec)[267].seg == 1179 - 348 and R.measure(rec) == 4143 - 348)
  eq("Run: the deaths are one line, each at its wall time with the time down",
    dv.deathLine, ("Deaths: %s (2m 45s down) \194\183 %s (1m 14s down)"):format(UI.fmtClock(T0 + 3533), UI.fmtClock(T0 + 4577)))
  check("Run: no Deaths table when no row names a killer", dv.sections.deaths.shown == false)
  -- loot: green and better as rows, the rest one line, no vendor price column
  eq("Run: the Loot table lists the 8 green and better drops (no quest reward, no white, no grey)", #dv.lootItems, 8)
  -- (Prismcharm and Engraved Cape of the Gorilla are stored "Picked up" with no boss kill near: one was a quest
  -- reward and one a drop won by roll, and the save cannot say which. Neither is counted as a drop.)
  eq("Run: the section counts as drops only the rows with a source", dv.sections.loot.meta.text, "6 drops green or better, 2 with no recorded source")
  eq("lootMeta: every row sourced", D.lootMeta({ { from = "Trash", row = { src = "Creature" } }, { from = "Halycon", row = { src = "Picked up" } } }), "2 green or better")
  eq("lootMeta: one drop", D.lootMeta({ { from = "Trash", row = { src = "Creature" } }, { row = { src = "Picked up" } } }), "1 drop green or better, 1 with no recorded source")
  eq("lootMeta: none sourced claims no drop", D.lootMeta({ { row = { src = "Picked up" } }, { row = {} } }), "2 green or better with no recorded source")
  eq("lootMeta: an enemy's drop whose enemy cannot be named is still a drop", D.lootMeta({ { row = { src = "Creature" } } }), "1 green or better")
  eq("lootMeta: no row, no meta", D.lootMeta({}), nil)
  eq("Run: the rest is one line", dv.lootMore, "3 more: 2 white, 1 grey")
  check("Run: the Loot table has no vendor price column", dv.tables.loot.cols.price == nil and dv.tables.loot.cols.src ~= nil and dv.tables.loot.cols.at ~= nil)
  local from, tip = {}, {}
  for _, it in ipairs(dv.lootItems) do from[it.row.item] = it.from or ""; tip[it.row.item] = it.fromTip end
  local want = { ["Slamshot Shoulders"] = "Highlord Omokk", ["Talisman of Evasion"] = "War Master Voone", ["Slashclaw Bracers"] = "Halycon",
    ["Rhombeard Protector"] = "Gizrul the Slavener", ["Bracers of Valor"] = "Trash", ["Nightshade Cloak of the Gorilla"] = "Trash",
    ["Prismcharm"] = "", ["Engraved Cape of the Gorilla"] = "" }
  local bad = {}
  for item, src in pairs(want) do if from[item] ~= src then bad[#bad + 1] = item .. "=" .. tostring(from[item]) end end
  check("Run: From names the boss killed at most 90 s before the row, Trash for an enemy with none, nothing otherwise", #bad == 0, table.concat(bad, " | "))
  do
    local cell = {}
    for _, r in ipairs(shown(dv.tables.loot)) do cell[r.item.row.item] = r.c.src end
    local pc, ec, sc = cell["Prismcharm"], cell["Engraved Cape of the Gorilla"], cell["Slamshot Shoulders"]
    check("Run: a row with no recorded source says so in From, muted, never a blank among the drops", pc and pc.text == "Not recorded" and ec and ec.text == "Not recorded"
      and math.abs(pc._color[1] - UI.C.fgMuted[1]) < 0.01 and sc and math.abs(sc._color[1] - UI.C.fgMuted[1]) > 0.01, pc and pc.text)
    eq("Run: its hover says it is not counted as a drop", tip["Prismcharm"], "Where this item came from was not recorded, so it is not counted as a drop.")
  end
  -- the WORTH hover says what the item value holds (the capture prices a quest's reward item too)
  do
    local tipW = _G.GameTooltip
    dv.card.worth:GetScript("OnEnter")(dv.card.worth)
    local tl = table.concat(tipW.lines or {}, " | ")
    dv.card.worth:GetScript("OnLeave")(dv.card.worth)
    check("Run: the WORTH hover says the item value includes quest reward items, and that quest coin is not counted",
      tl:find("Item value counts every item that reached your bags inside, quest reward items too.", 1, true) ~= nil and tl:find("more coin. It is not loot and is not counted here.", 1, true) ~= nil, tl)
  end
  -- a quest reward pushed into the bags before its turn-in event (the real handlers): the turn-in names it, so the
  -- run's LOOT section never lists it
  do
    local log = ns.DB.loot.log
    local keepNow, keepEpoch = M.now, M.epoch
    local xpQ = c.xp and c.xp.fromQuests
    M.now = M.now + 120
    M.fire("CHAT_MSG_LOOT", "You receive item: |cff1eff00|Hitem:15867::::::::58:::::|h[Prismcharm]|h|r.")
    local row = log[#log]
    check("capture: a pushed item with nothing to name it is stored Picked up", row.item == "Prismcharm" and row.src == "Picked up", tostring(row.src))
    M.now = M.now + 1
    M.fire("QUEST_TURNED_IN", 4867, 0, 0)
    eq("capture: the turn-in a second later makes it a quest reward", row.src, "Quest reward")
    row.t = T0 + 945
    R._gen = (R._gen or 0) + 1
    T.openRun(rec); M.settle()
    local listed = false
    for _, it in ipairs(dv.lootItems) do if it.row == row then listed = true end end
    check("capture: and the run page does not list it as loot", listed == false and #dv.lootItems == 8)
    table.remove(log)
    if c.xp then c.xp.fromQuests = xpQ end
    M.now, M.epoch = keepNow, keepEpoch
    R._gen = (R._gen or 0) + 1
    T.openRun(rec); M.settle()
  end
  -- Worth per run of By dungeon is on the coin the Runs list shows: the statistics hold the booked 11,612, the run
  -- paid 18,835 by its purse
  do
    local drows = R.dungeonRows()
    local brs
    for _, d in ipairs(drows) do if d.name == "Blackrock Spire" then brs = d end end
    eq("By dungeon: the statistics alone give the booked coin plus the items", brs and brs.worthPerRun, 11612 + 180399)
    local wpr = D.worthPerRun(drows)
    eq("By dungeon: Worth per run of a dungeon with one stored run is that run's Worth", brs and wpr[brs.key], (D.worth(R.view(rec, false, false))))
    -- two more stored runs, one whose purse gained more than was booked and one whose purse gained less
    local a = T.runRecord("Blackrock Spire", T0 - 30000, 3000, { v = 2, gold = { looted = 5000, quests = 0, lootValue = 20000, items = 4, purse = 9000 } })
    local b = T.runRecord("Blackrock Spire", T0 - 60000, 3000, { v = 2, gold = { looted = 7000, quests = 0, lootValue = 1000, items = 2, purse = 6000 } })
    table.insert(c.dungeonRuns, 1, a); table.insert(c.dungeonRuns, 1, b)
    R.statsRebuild(c)
    drows = R.dungeonRows()
    for _, d in ipairs(drows) do if d.name == "Blackrock Spire" then brs = d end end
    wpr = D.worthPerRun(drows)
    local sum = 0
    for _, v in ipairs(R.views()) do if v.name == "Blackrock Spire" then sum = sum + (D.worth(v)) end end
    eq("By dungeon: three stored runs", brs and brs.n, 3)
    eq("By dungeon: the sum of the Worth cells of Runs (199,234 + 29,000 + 8,000)", sum, 199234 + 29000 + 8000)
    check("By dungeon: Worth per run times the runs is that sum", brs and math.abs(wpr[brs.key] * brs.n - sum) < 0.001, brs and wpr[brs.key])
    -- a run no longer stored stays at its booked coin: only what is stored can be corrected
    table.remove(c.dungeonRuns, 2)
    R._gen = (R._gen or 0) + 1
    wpr = D.worthPerRun(drows)
    check("By dungeon: a run no longer stored counts with its booked coin", brs and math.abs(wpr[brs.key] * 3 - (199234 + 25000 + 8000)) < 0.001, brs and wpr[brs.key])
    table.remove(c.dungeonRuns, 1)
    R.statsRebuild(c)
  end
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
  -- A record whose kills cannot be placed on the wall clock (0.9.50: no version, three visits, a ghost gap and an
  -- outside gap, so Runs.visitClocks cannot say): a boss may have died right before the row, so nothing is claimed.
  do
    local old = { t = T0, inst = "Blackrock Spire", secs = { ghost = 100, outside = 200, inside = 3000 },
      visits = { { i = 0, o = 1000, secs = 1000 }, { i = 1100, o = 2100, secs = 1000 }, { i = 2300, o = 3300, secs = 1000 } },
      bosses = { { name = "Highlord Omokk", enc = 267, kill = 500 } } }
    eq("sourceOf: the fixture is a record that cannot place its kills", R.wallOf(old, 500), nil)
    local a, b = D.sourceOf({ rec = old }, { t = T0 + 510, src = "Creature" })
    check("sourceOf: with a kill that cannot be placed an enemy row is neither a boss nor Trash", a == nil and b == "Not recorded", tostring(a) .. " | " .. tostring(b))
    a, b = D.sourceOf({ rec = old }, { t = T0 + 3000, src = "an enemy" })
    check("sourceOf: and so is every other enemy row of that run", a == nil and b == "Not recorded", tostring(a) .. " | " .. tostring(b))
    eq("sourceOf: a stored name is still shown as stored there", (D.sourceOf({ rec = old }, { t = T0 + 510, src = "Scarshield Legionnaire" })), "Scarshield Legionnaire")
    a, b = D.sourceOf({ rec = rec }, { src = "Creature" })
    check("sourceOf: a row with no time of its own claims nothing", a == nil and b == "Not recorded", tostring(a))
    local noName = copy(rec); noName.bosses[1].name = nil
    a, b = D.sourceOf({ rec = noName }, { t = T0 + 1510, src = "Creature" })
    check("sourceOf: a kill in range whose name is not stored is not called Trash", a == nil and b == "Not recorded", tostring(a))
  end
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
  -- A record covers every gold run that began inside its span. More than 20 minutes outside closes the gold run and
  -- opens a second one for the same record; so do two records joined by hand. Neither second gold run is a row.
  do
    local gap = { dungeonRuns = { { id = "a", inst = "Blackrock Depths", t = 1000, endT = 6000, visits = { { i = 0, o = 1800, secs = 1800 }, { i = 3300, o = 5000, secs = 1700 } } } },
      goldRuns = { { t = 1000, inst = "Blackrock Depths", secs = 1800, looted = 500, items = 3, lootValue = 100, quests = 0 },
        { t = 4300, inst = "Blackrock Depths", secs = 1700, looted = 700, items = 5, lootValue = 100, quests = 0 } } }
    eq("legacy: a record with 25 minutes outside owns both of its gold runs, no row", L.harvest(gap), 0)
    local joined = { dungeonRuns = { { id = "a", inst = "Scholomance", t = 1000, visits = { { i = 0, o = 1800, secs = 1800 }, { i = 4000, o = 5000, secs = 1000 } } } },
      goldRuns = { { t = 1000, inst = "Scholomance", secs = 1800, looted = 500, items = 3 }, { t = 5000, inst = "Scholomance", secs = 1000, looted = 700, items = 5 } } }
    eq("legacy: a joined record (no stored end: its last visit ends it) owns both gold runs, no row", L.harvest(joined), 0)
    local after = { dungeonRuns = { { id = "a", inst = "Scholomance", t = 1000, endT = 3000, visits = { { i = 0, o = 2000, secs = 2000 } } } },
      goldRuns = { { t = 3000 + L.MATCH + 1, inst = "Scholomance", secs = 900, looted = 5 }, { t = 1000 - L.MATCH - 1, inst = "Scholomance", secs = 100, looted = 5 },
        { t = 2000, inst = "Stratholme", secs = 900, looted = 5 } } }
    eq("legacy: a gold run after the record's end, one before its start and one of another dungeon are rows", L.harvest(after), 3)
    local open = { dungeonRuns = {}, dungeonRun = { id = "o", inst = "Stratholme", t = 1000, visits = { { i = 0, o = 600, secs = 600 }, { i = 2400 } } },
      goldRuns = { { t = 1000, inst = "Stratholme", secs = 600, looted = 5 }, { t = 500, inst = "Stratholme", secs = 100, looted = 5 } } }
    eq("legacy: the open record owns its gold run; one from before it is a row", L.harvest(open), 1)
  end
  lv = T.dungeonList(); M.settle()
  rows = shown(lv.tbl)
  eq("Runs: the list holds the stored run and the five rebuilt rows", #rows, 6)
  local part, full = 0, 0
  for _, r in ipairs(rows) do if r.run.legacy then part = part + 1 else full = full + 1 end end
  check("Runs: five of them are partial", part == 5 and full == 1)
  -- (the list is not the character's history: its header names the day of the oldest row, once, and nothing else does)
  eq("Runs: the section header says where the list starts", lv.section.label.text, UI.upper("Runs since " .. UI.fmtSince(G0)))
  eq("Runs: the start is the oldest listed row's", lv.since, G0)
  check("Runs: the day has no \"Today\" in it", UI.fmtSince(now) == date("%a ", now) .. tostring(tonumber(date("%d", now))) .. date(" %b", now), UI.fmtSince(now))
  do
    local times = {}
    for _, r in ipairs(rows) do times[#times + 1] = r.c.dur.text end
    local short
    for _, r in ipairs(rows) do if r.run.id == ("g%d"):format(G0 + 84491) then short = r end end
    eq("Runs: a rebuilt row of 2,010 s reads in minutes like every other row, the seconds cut", short and short.c.dur.text, "33m")
    check("Runs: no Time cell from 10 minutes on carries seconds", table.concat(times, "|"):find("%ds") == nil, table.concat(times, "|"))
    eq("fmtLen: under 10 minutes the seconds stay", D.fmtLen(479), "7m 59s")
    eq("fmtLen: from 10 minutes they are cut, not rounded", D.fmtLen(659), "10m")
    eq("fmtLen: hours", D.fmtLen(4148), "1h 9m")
    lv.st.inst = "Blackrock Depths"; T.dungeonList(); M.settle()
    eq("Runs: filtered to one dungeon the header is that dungeon and its own oldest row", lv.sectionLabel, "Blackrock Depths since " .. UI.fmtSince(G0 + 48942))
    lv.st.inst = nil; T.dungeonList(); M.settle()
  end
  local brd
  for _, r in ipairs(rows) do if r.run.id == ("g%d"):format(G0 + 65059) then brd = r end end
  check("Runs: a rebuilt row is marked partial after its name", brd and strip(brd.c.name.text) == "Blackrock Depths partial", brd and brd.c.name.text)
  eq("Runs: its Time is the gold run's seconds", brd and brd.c.dur.text, "2h 33m")
  -- (a rebuilt row stores the booked coin, 53,083, and no purse figure; the run paid 75,411 by the chat log. The coin is
  -- not known from the save, so Worth is the items' vendor value and no coin amount is printed anywhere.)
  eq("Runs: a rebuilt row's Worth is its items' vendor value alone", brd and brd.c.worth.text, UI.money(518686))
  do
    local tips = brd and table.concat(lv.tipLines(brd.run), " | ") or ""
    check("Runs: its hover says the coin is not counted and names no coin amount", tips:find(D.NO_COIN, 1, true) ~= nil and tips:find(UI.money(53083), 1, true) == nil
      and select(2, D.coinOf(brd.run)) == "none", tips)
    check("Runs: its hover says the time and the start are counted by zone name", tips:find("Time 2h 33m in the dungeon's zone, from when you reached the dungeon's zone", 1, true) ~= nil
      and tips:find("Counted by zone name to 10 s, so it can include time at the entrance.", 1, true) ~= nil, tips)
  end
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
    -- (the gold run counted by the zone's name to its 10 s tick: Maraudon, 18 Nov, stored 1h 10m for 1h 8m 16s inside)
    eq("Rebuilt run: the card does not say the time was all in the dungeon", dv.cards[1].meta.text, "in the dungeon's zone")
    eq("Rebuilt run: the Time hover says how it was counted", dv.timeTip, "Time in the dungeon's zone. Counted by zone name to 10 s, so it can include time at the entrance.")
    eq("Rebuilt run: the PARTIAL hover says so too", dv.badges[1].ebTip and dv.badges[1].ebTip.text, "Time and loot only. Counted by zone name to 10 s, so it can include time at the entrance.")
    eq("Rebuilt run: the line under the title says what its time of day is", dv.metaText, UI.fmtWhen(G0 + 65059) .. " \194\183 reached the dungeon's zone")
    check("Rebuilt run: nothing on the page says \"in the dungeon\" as a fact", (function()
      for _, fs in ipairs(P.descendants(dv)) do if P.visible(fs) and type(fs.text) == "string" and fs.text:find("in the dungeon", 1, true) and not fs.text:find("in the dungeon's zone", 1, true) then return false end end
      return true
    end)())
    eq("Rebuilt run: Worth", dv.cards[2].value.text, UI.money(518686))
    eq("Rebuilt run: the card says what the figure is, and no coin", dv.cards[2].meta.text, "items at vendor prices")
    eq("Rebuilt run: the hover says the coin is not counted", dv.coinTip, D.NO_COIN)
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
  -- Home > Now links to Deaths in three places (the DEATHS card, the "You died" rows, "N more deaths"). With the tab
  -- gone none of them may be a dead click: a link opens a page that exists, or it is not a link.
  do
    eq("Open: a hidden sub-tab is reported, not silently skipped", UI.Open("Home", "deaths"), false)
    eq("Open: and the host shows its first sub-tab, whatever was open before", home.ctl.active, "now")
    UI.Open("Home", "sessions"); M.settle()
    UI.Open("Home", "deaths"); M.settle()
    eq("Open: the same from Sessions", home.ctl.active, "now")
    eq("Open: a page that exists reports true", UI.Open("Home", "sessions"), true)
    eq("SubVisible: Deaths has no page now", UI.SubVisible("Home", "deaths"), false)
    eq("SubVisible: Now always has", UI.SubVisible("Home", "now"), true)
    -- (three deaths of the session that is running, none with a killer: Now lists two and links the rest)
    -- (the harness's running session has no stored record at this point: it gets one for these checks, as in game)
    local curRec = ns.Recorder.current()
    local cur = curRec.id
    local keepRec, keepGuid = ns.DB.sessions[cur], curRec.guid
    ns.DB.sessions[cur], curRec.guid = curRec, ns.charGuid()
    local nBefore = #evs
    for i = 1, 3 do evs[#evs + 1] = { kind = "DEATH", t = now - 300 + i, s = cur, zone = "Blackrock Spire", text = "You died  \194\183  Level 59", downtime = 50 } end
    UI.Open("Home", "now"); M.settle()
    local nv = T.journeyRefresh(); M.settle()
    local card = nv.cards.cards[4]
    check("Now: the DEATHS card has no chevron and opens nothing while Deaths has no page", nv.deathsOpen == false and card.ebNoClick == true and card.chev.shown == false)
    card:GetScript("OnClick")(card); M.settle()
    eq("Now: a click on it leaves the page where it is", home.ctl.active, "now")
    local deathRows, dead = 0, 0
    for _, it in ipairs(nv.lookList) do
      if it.kind == "death" then
        deathRows = deathRows + 1
        if it.onClick then
          UI.Open("Home", "now"); M.settle()
          it.onClick(); M.settle()
          local t = ns.DB.settings.lastTab
          if t == "Home" and home.ctl.active == "now" then dead = dead + 1 end
        end
      end
    end
    check("Now: the death rows are listed, and none is a dead click", deathRows == 2 and dead == 0, deathRows .. " rows, " .. dead .. " dead")
    UI.Open("Home", "now"); M.settle()
    nv = T.journeyRefresh(); M.settle()
    check("Now: the third death is behind the more link", nv.moreDeaths.shown ~= false and nv.moreDeaths.link.ebOnClick ~= nil)
    nv.moreDeaths.link.ebOnClick(nv.moreDeaths.link); M.settle()
    eq("Now: the more link opens Sessions (its Deaths column) while Deaths has no page", home.ctl.active, "sessions")
    while #evs > nBefore do table.remove(evs) end
    -- a death inside a stored run opens that run's page (it lists the run's deaths); one outside any run opens nothing
    local rv
    for _, v in ipairs(R.views(false)) do if not v.inProgress and v.rec and v.endT then rv = v end end
    check("Now: a moment inside a stored run finds that run, one long before it finds none", rv ~= nil and ns.Now.runRecAt(rv.startT + 1) == rv.rec and ns.Now.runRecAt(rv.startT - 10000000) == nil and ns.Now.runRecAt(nil) == nil)
    -- with a killer stored the tab is back, and so are the links
    evs[#evs + 1] = { kind = "DEATH", t = now - 3400, s = ns.DB.active, zone = "Burning Steppes", text = "You died  \194\183  Level 59", foe = "Blackrock Slayer", downtime = 40 }
    UI.Open("Home", "now"); M.settle()
    nv = T.journeyRefresh(); M.settle()
    card = nv.cards.cards[4]
    check("Now: with a named killer stored the DEATHS card is a link again", nv.deathsOpen == true and card.ebNoClick == nil and card.chev.shown ~= false)
    card:GetScript("OnClick")(card); M.settle()
    eq("Now: and it opens Deaths", home.ctl.active, "deaths")
    table.remove(evs)
    ns.DB.sessions[cur], curRec.guid = keepRec, keepGuid
    UI.Open("Home", "now"); M.settle()
  end
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
