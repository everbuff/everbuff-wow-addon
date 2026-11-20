-- The dungeon runs of docs/UX_OVERHAUL.md 4.0, put on the logged-in character for the Dungeons screens:
-- tests/render_html.lua renders its states ("dungeons/runs:empty", ...) and tests/panes/dungeons.lua tests them.
--   F.install(ns, M, state) -> undo()
-- state is one of "" (normal), "empty", "nomatch", "limit4", "limit5", "live" (Runs), "best", "death" (run pages).
-- The runs are built back from the clock the suite is on, so "today" is the suite's today:
--   Ragefire Chasm   today, 34 minutes ago: first run, 2 of 4 bosses, Tessa died, 3 items, lockout 2 of 4
--   Wailing Caverns  4 days ago, party of 5: BEST on its 6-boss route, 28m 41s first pull to last kill
--   Wailing Caverns  12 days ago: the same route, 29m 23s
local F = {}

local WC = { { 585, "Lady Anacondra" }, { 586, "Lord Cobrahn" }, { 587, "Lord Pythas" }, { 588, "Lord Serpentis" }, { 589, "Skum" },
  { 590, "Verdan the Everliving" } }
-- the kills of a Wailing Caverns clear: first pull at 60, the last kill `span` seconds later
local function wcBosses(span)
  local b = {}
  for i, x in ipairs(WC) do
    local at = 60 + math.floor(span * i / #WC)
    b[i] = { enc = x[1], name = x[2], pulls = 1, wipes = 0, resets = 0, unknown = 0, combat = 40 + i * 5, kill = at, dur = 40 + i * 5 }
  end
  return b
end

function F.install(ns, M, state)
  state = state or ""
  local T = ns._test
  local c = ns.char()
  local now = GetServerTime()
  local keep = { runs = c.dungeonRuns, open = c.dungeonRun, stats = c.dungeonStats, locks = c.lockouts, copies = c.dungeonCopies,
    limit = ns.DB.settings.instanceLimit, nFights = #ns.DB.combat.fights, nLoot = #ns.DB.loot.log, read = ns.Runs._read }
  local fights, log = ns.DB.combat.fights, ns.DB.loot.log
  local function undo()
    c.dungeonRuns, c.dungeonRun, c.dungeonStats, c.lockouts, c.dungeonCopies = keep.runs, keep.open, keep.stats, keep.locks, keep.copies
    ns.DB.settings.instanceLimit = keep.limit
    while #fights > keep.nFights do table.remove(fights) end
    while #log > keep.nLoot do table.remove(log) end
    ns.Runs._read = keep.read
    if ns.Runs.statsRebuild then ns.Runs.statsRebuild(c) end
    ns.DB.sessions["fx-wc2-session"] = nil
  end
  if state == "empty" then
    c.dungeonRuns, c.dungeonRun, c.dungeonStats, c.lockouts, c.dungeonCopies = {}, nil, nil, {}, {}
    return undo, {}
  end
  local party = { { name = "Hart", class = "WARRIOR", me = true, level = 17 }, { name = "Tessa", class = "PRIEST", level = 17 },
    { name = "Brakk", class = "ROGUE", level = 18 }, { name = "Ilsa", class = "MAGE", level = 17 }, { name = "Doran", class = "HUNTER", level = 16 } }
  -- the two Wailing Caverns clears on one route
  local wc1 = T.runRecord("Wailing Caverns", now - 12 * 86400 - 9000, 1950, { firstPull = 60, size = 5, diff = 1, map = 43, bosses = wcBosses(1763),
    xp = { gain = 3900, kill = 3900, quest = 0, n = 120, l0 = 16, p0 = 0.5, l1 = 16, p1 = 0.9, need = 9000 },
    gold = { looted = 9400, quests = 0, lootValue = 6200, items = 7, purse = 9400 } })
  local wc2 = T.runRecord("Wailing Caverns", now - 4 * 86400 - 7500, 1872, { firstPull = 60, size = 5, diff = 1, map = 43, bosses = wcBosses(1721),
    xp = { gain = 4210, kill = 3610, quest = 600, n = 131, l0 = 17, p0 = 0.2, l1 = 17, p1 = 0.7, need = 10000 },
    gold = { looted = 10200, quests = 0, lootValue = 8400, items = 9, purse = 10200 } })
  -- Ragefire Chasm today: Oggleflint and Taragaman down, Jergosh and Bazzalan pulled and left up, Tessa died
  local rfcT = now - 34 * 60
  local rfc = T.runRecord("Ragefire Chasm", rfcT, 750, { firstPull = 120, size = 5, diff = 1, map = 389,
    bosses = { { enc = 1443, name = "Oggleflint", pulls = 1, combat = 45, kill = 300, dur = 45 },
      { enc = 1444, name = "Taragaman the Hungerer", pulls = 2, wipes = 1, combat = 120, kill = 725, dur = 70 },
      { enc = 1445, name = "Jergosh the Invoker", pulls = 1, wipes = 0, combat = 10 },
      { enc = 1446, name = "Bazzalan", pulls = 1, wipes = 0, combat = 8 } },
    nDeaths = { me = 0, party = 1 }, deaths = { { o = 610, enc = 1444, foe = "Taragaman the Hungerer", who = "Tessa", back = 45 } },
    xp = { gain = 1840, kill = 1840, quest = 0, n = 41, l0 = 18, p0 = 0.6, l1 = 18, p1 = 0.77, need = 11800 },
    gold = { looted = 1500, quests = 0, lootValue = 2300, items = 3, purse = 1500 } })
  local s = ns.DB.active
  log[#log + 1] = { s = s, t = rfcT + 302, item = "Cavedweller Bracers", count = 1, q = "ff1eff00", src = "Oggleflint", icon = "Interface\\Icons\\INV_Bracer_07" }
  log[#log + 1] = { s = s, t = rfcT + 410, item = "Linen Cloth", count = 4, q = "ffffffff", src = "Ragefire Trogg" }
  log[#log + 1] = { s = s, t = rfcT + 728, item = "Searing Collar", count = 1, q = "ff1eff00", src = "Taragaman the Hungerer", icon = "Interface\\Icons\\INV_Jewelry_Necklace_04" }
  fights[#fights + 1] = { uid = "fx-rfc-1", session = s, startEpoch = rfcT + 255, duration = 45, outcome = "kill", bossName = "Oggleflint", foes = { "Oggleflint" }, zone = "Ragefire Chasm", group = party }
  fights[#fights + 1] = { uid = "fx-rfc-2", session = s, startEpoch = rfcT + 500, duration = 30, outcome = "wipe", bossName = "Taragaman the Hungerer", foes = { "Taragaman the Hungerer" }, zone = "Ragefire Chasm", group = party }
  fights[#fights + 1] = { uid = "fx-rfc-3", session = s, startEpoch = rfcT + 655, duration = 70, outcome = "kill", bossName = "Taragaman the Hungerer", foes = { "Taragaman the Hungerer" }, zone = "Ragefire Chasm", group = party }
  rfc.bosses[1].fight, rfc.bosses[2].fight = "fx-rfc-1", "fx-rfc-3"
  -- (the Wailing Caverns run was 4 days ago, in a session of its own: its loot is not this session's)
  ns.DB.sessions["fx-wc2-session"] = { id = "fx-wc2-session", guid = ns.charGuid(), startedEpoch = wc2.t - 600, endedEpoch = wc2.t + 2400 }
  log[#log + 1] = { s = "fx-wc2-session", t = wc2.t + 420, item = "Serpent's Shoulders", count = 1, q = "ff0070dd", src = "Lord Serpentis", icon = "Interface\\Icons\\INV_Shoulder_09" }
  log[#log + 1] = { s = "fx-wc2-session", t = wc2.t + 1500, item = "Glowing Lizardscale Cloak", count = 1, q = "ff1eff00", src = "Lady Anacondra" }
  fights[#fights + 1] = { uid = "fx-wc-1", session = s, startEpoch = wc2.t + 300, duration = 50, outcome = "kill", bossName = "Lady Anacondra", foes = { "Lady Anacondra" }, zone = "Wailing Caverns", group = party }
  c.dungeonRuns, c.dungeonRun, c.dungeonStats = { wc1, wc2, rfc }, nil, nil
  c.lockouts = { { name = "Ragefire Chasm", resetAt = now + 7140, bosses = 4, down = 2 } }
  -- the instances: Ragefire Chasm this hour, three earlier today (one an estimate)
  c.dungeonCopies = { { t = now - 20 * 3600, key = "The Deadmines", why = "first" }, { t = now - 15 * 3600, key = "The Deadmines", why = "estimate" },
    { t = now - 3 * 3600, key = "Wailing Caverns", why = "first" }, { t = rfcT, key = "Ragefire Chasm", run = rfc.id, why = "first" } }
  ns.DB.settings.instanceLimit = nil
  if state == "limit4" or state == "limit5" then
    ns.DB.settings.instanceLimit = 5
    for i = 1, (state == "limit4" and 3 or 4) do
      table.insert(c.dungeonCopies, #c.dungeonCopies, { t = now - 3000 + i * 300, key = "The Stockade", why = i == 1 and "first" or "estimate" })
    end
  end
  if state == "live" or state == "runlive" then
    -- Ragefire Chasm in progress: 12m 40s inside, Oggleflint down
    table.remove(c.dungeonRuns)
    local t = now - 760
    local rec = T.runRecord("Ragefire Chasm", t, 760, { firstPull = 120, size = 5, diff = 1, map = 389,
      bosses = { { enc = 1443, name = "Oggleflint", pulls = 1, combat = 45, kill = 300, dur = 45 } },
      xp = { gain = 700, kill = 700, quest = 0, n = 15, l0 = 18, p0 = 0.71, l1 = 18, p1 = 0.77, need = 11800 } })
    rec.why, rec.gold = nil, nil
    rec.visits[1].o, rec.visits[1].out = nil, nil
    rec.st, rec.mark, rec.beat = "in", now, now
    rec.nDeaths, rec.deaths, rec.hidden = rec.nDeaths or {}, rec.deaths or {}, rec.hidden or {}
    rec.nDeaths.me, rec.nDeaths.party = rec.nDeaths.me or 0, rec.nDeaths.party or 0
    for _, k in ipairs({ "xp", "rep", "loot" }) do rec.hidden[k] = rec.hidden[k] or 0 end
    for _, k in ipairs(ns.Runs.SECS) do rec.secs[k] = rec.secs[k] or 0 end
    ns.Runs._read = true
    c.dungeonRun = rec
    c.dungeonCopies[#c.dungeonCopies].t, c.dungeonCopies[#c.dungeonCopies].run = t, rec.id
  end
  ns.Runs.statsRebuild(c)
  return undo, { wc1 = wc1, wc2 = wc2, rfc = rfc, open = c.dungeonRun }
end

return F
