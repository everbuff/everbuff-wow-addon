-- The dungeon runs of docs/UX_OVERHAUL.md 4.0, put on the logged-in character for the Dungeons screens:
-- tests/render_html.lua renders its states ("dungeons/runs:empty", ...) and tests/panes/dungeons.lua tests them.
--   F.install(ns, M, state [, long]) -> undo()
-- state is one of "" (normal), "empty", "nomatch", "limit4", "limit5", "live" (Runs), "best", "death" (run pages).
-- long: the same runs with long boss, item, source and party names (the "long" shots), so the run pages are tested
-- with names that do not fit (F.LONG is the suffix).
-- The Ragefire Chasm run is part of this session's story: its pulls, kills, loot and XP are in the session's events
-- and sums (the Now page, Activity and Items read them), and each run's party has its own levels.
-- The runs are built back from the clock the suite is on, so "today" is the suite's today:
--   Ragefire Chasm   today, 34 minutes ago: first run, 2 of 4 bosses, Tessa died, 3 items, lockout 2 of 4
--   Wailing Caverns  4 days ago, party of 5: BEST on its 6-boss route, 28m 41s first pull to last kill
--   Wailing Caverns  12 days ago: the same route, 29m 23s
local F = {}
F.LONG = " of the Scarlet Monastery Cathedral"

local WC = { { 585, "Lady Anacondra" }, { 586, "Lord Cobrahn" }, { 587, "Lord Pythas" }, { 588, "Lord Serpentis" }, { 589, "Skum" },
  { 590, "Verdan the Everliving" } }
-- the kills of a Wailing Caverns clear: first pull at 60, the last kill `span` seconds later
local function wcBosses(span)
  local b = {}
  for i, x in ipairs(WC) do
    local at = 60 + math.floor(span * i / #WC)
    b[i] = { enc = x[1], name = x[2], pulls = 1, wipes = 0, resets = 0, unknown = 0, combat = 40 + i * 5, kill = at, dur = 40 + i * 5 }
  end
  -- (Kresh and Mutanus pulled and left up: the run met 8 encounters and killed 6, "6 of 8", no full clear, B1)
  b[#b + 1] = { enc = 584, name = "Kresh", pulls = 1, wipes = 0, resets = 0, unknown = 0, combat = 12 }
  b[#b + 1] = { enc = 591, name = "Mutanus the Devourer", pulls = 1, wipes = 0, resets = 0, unknown = 0, combat = 15 }
  return b
end

function F.install(ns, M, state, long)
  state = state or ""
  local function L(s) return long and (s .. F.LONG) or s end
  -- (WoW names are at most 12 letters: the long party is the longest names the game allows)
  local function P(s, l) return long and l or s end
  local T = ns._test
  local c = ns.char()
  local now = GetServerTime()
  ns.DB.story = ns.DB.story or {}
  ns.DB.story.events = ns.DB.story.events or {}
  local evs = ns.DB.story.events
  local ses = ns.Recorder and ns.Recorder.current and ns.Recorder.current() or nil
  local keep = { runs = c.dungeonRuns, open = c.dungeonRun, stats = c.dungeonStats, locks = c.lockouts, copies = c.dungeonCopies,
    limit = ns.DB.settings.instanceLimit, nFights = #ns.DB.combat.fights, nLoot = #ns.DB.loot.log, read = ns.Runs._read, nEv = #evs, evOrder = { unpack(evs) },
    ses = ses and { xp = ses.xp, kills = ses.kills, items = ses.items, dungeons = ses.dungeons } or nil, price = {} }
  local fights, log = ns.DB.combat.fights, ns.DB.loot.log
  local function undo()
    for i = #(keep.retimed or {}), 1, -1 do local r = keep.retimed[i]; r[1][r[2]] = r[3] end
    if ses and keep.sesStart then ses.startedEpoch = keep.sesStart end
    c.dungeonRuns, c.dungeonRun, c.dungeonStats, c.lockouts, c.dungeonCopies = keep.runs, keep.open, keep.stats, keep.locks, keep.copies
    ns.DB.settings.instanceLimit = keep.limit
    while #fights > keep.nFights do table.remove(fights) end
    while #log > keep.nLoot do table.remove(log) end
    while #evs > keep.nEv do table.remove(evs) end
    for i = 1, keep.nEv do evs[i] = keep.evOrder[i] end
    if ses and keep.ses then ses.xp, ses.kills, ses.items, ses.dungeons = keep.ses.xp, keep.ses.kills, keep.ses.items, keep.ses.dungeons end
    for id, p in pairs(keep.price) do M.sellPrice[id] = p ~= false and p or nil end
    ns.Runs._read = keep.read
    if ns.Runs.statsRebuild then ns.Runs.statsRebuild(c) end
    ns.DB.sessions["fx-wc2-session"], ns.DB.sessions["fx-wc1-session"] = nil, nil
    if keep.ding17 then keep.ding17[1].t, keep.ding17[1].s = keep.ding17[2], keep.ding17[3] end
  end
  if state == "empty" then
    c.dungeonRuns, c.dungeonRun, c.dungeonStats, c.lockouts, c.dungeonCopies = {}, nil, nil, {}, {}
    return undo, {}
  end
  -- a party of five at a run's level `lv`: yours is the run's own, the others around it
  local function party(lv)
    return { { name = "Hart", class = "WARRIOR", me = true, level = lv }, { name = P("Tessa", "Tessamarinda"), class = "PRIEST", level = lv },
      { name = P("Brakk", "Brakkenhowle"), class = "ROGUE", level = lv + 1 }, { name = P("Ilsa", "Ilsabethwyne"), class = "MAGE", level = lv },
      { name = P("Doran", "Doranthielle"), class = "HUNTER", level = lv - 1 } }
  end
  -- every item of the runs with its id and its vendor price, so a row's price and the footer add up
  local function price(id, p) if keep.price[id] == nil then keep.price[id] = M.sellPrice[id] or false end; M.sellPrice[id] = p end
  price(6077, 102); price(2589, 13); price(6078, 0); price(5404, 245); price(6087, 310); price(6449, 188)
  -- the two Wailing Caverns clears on one route
  local wc1 = T.runRecord("Wailing Caverns", now - 12 * 86400 - 9000, 1950, { firstPull = 60, size = 5, diff = 1, map = 43, bosses = wcBosses(1763),
    xp = { gain = 3900, kill = 3900, quest = 0, n = 120, l0 = 16, p0 = 0.5, l1 = 16, p1 = 0.9, need = 9000 },
    gold = { looted = 9400, quests = 0, lootValue = 6200, items = 7, purse = 9400 } })
  local wc2 = T.runRecord("Wailing Caverns", now - 4 * 86400 - 7500, 1872, { firstPull = 60, size = 5, diff = 1, map = 43, bosses = wcBosses(1721),
    xp = { gain = 4210, kill = 3610, quest = 600, n = 131, l0 = 17, p0 = 0.2, l1 = 17, p1 = 0.7, need = 10000 },
    gold = { looted = 10200, quests = 0, lootValue = 8400, items = 9, purse = 10200 } })
  -- Ragefire Chasm today: Oggleflint and Taragaman down, Jergosh and Bazzalan pulled and left up, Tessa died
  local rfcT = now - 34 * 60
  local OGG, TARA, JER, BAZ = L("Oggleflint"), L("Taragaman the Hungerer"), L("Jergosh the Invoker"), L("Bazzalan")
  local TESSA = P("Tessa", "Tessamarinda")
  local rfc = T.runRecord("Ragefire Chasm", rfcT, 750, { firstPull = 120, size = 5, diff = 1, map = 389,
    bosses = { { enc = 1443, name = OGG, pulls = 1, combat = 45, kill = 300, dur = 45 },
      { enc = 1444, name = TARA, pulls = 2, wipes = 1, combat = 100, kill = 725, dur = 70 },
      { enc = 1445, name = JER, pulls = 1, wipes = 0, combat = 10 },
      { enc = 1446, name = BAZ, pulls = 1, wipes = 0, combat = 8 } },
    nDeaths = { me = 0, party = 1 }, deaths = { { o = 610, enc = 1444, foe = TARA, who = TESSA, back = 45 } },
    xp = { gain = 1840, kill = 1840, quest = 0, n = 41, l0 = 18, p0 = 0.6, l1 = 18, p1 = 0.77, need = 11800 },
    gold = { looted = 1500, quests = 0, lootValue = 2300, items = 3, purse = 1500 } })
  local s = ns.DB.active
  local RFC = "Ragefire Chasm"
  -- (B4: the run's window holds only its own fights. The session's open-world fights, events and loot from the run's
  -- start on move after it, in their order; with a run in progress they end before it begins. The session starts
  -- before the run, so every run lies inside a session, B10.)
  local live = state == "live" or state == "runlive"
  keep.retimed = {}
  do
    local w0, w1 = rfcT, now
    local a, b = rfcT + 750 + 60, live and (now - 760 - 60) or (now - 30)
    local function remap(obj, key)
      local t = tonumber(obj[key])
      if t and t >= w0 and t <= w1 then
        keep.retimed[#keep.retimed + 1] = { obj, key, obj[key] }
        obj[key] = math.floor(a + (t - w0) * (b - a) / (w1 - w0))
      end
    end
    for _, f in ipairs(fights) do remap(f, "startEpoch") end
    for _, e in ipairs(evs) do remap(e, "t") end
    for _, l in ipairs(log) do remap(l, "t") end
  end
  if ses and tonumber(ses.startedEpoch) and ses.startedEpoch > rfcT - 240 then keep.sesStart = ses.startedEpoch; ses.startedEpoch = rfcT - 240 end
  local rfcParty, wcParty = party(18), party(17)
  -- (the run's loot is in the loot log Loot > Items reads, with ids, so Now's best drop, the run's LOOT and Items agree)
  log[#log + 1] = { s = s, t = rfcT + 302, id = 6077, item = L("Cavedweller Bracers"), count = 1, q = "ff1eff00", src = OGG, zone = RFC, icon = "Interface\\Icons\\INV_Bracer_07" }
  log[#log + 1] = { s = s, t = rfcT + 410, id = 2589, item = "Linen Cloth", count = 4, q = "ffffffff", src = L("Ragefire Trogg"), zone = RFC, icon = "Interface\\Icons\\INV_Fabric_Linen_01" }
  log[#log + 1] = { s = s, t = rfcT + 728, id = 5404, item = L("Searing Collar"), count = 1, q = "ff1eff00", src = TARA, zone = RFC, icon = "Interface\\Icons\\INV_Jewelry_Necklace_04" }
  fights[#fights + 1] = { uid = "fx-rfc-1", session = s, startEpoch = rfcT + 255, duration = 45, outcome = "kill", bossName = OGG, foes = { OGG }, zone = RFC, group = rfcParty }
  fights[#fights + 1] = { uid = "fx-rfc-2", session = s, startEpoch = rfcT + 500, duration = 30, outcome = "wipe", bossName = TARA, foes = { TARA }, zone = RFC, group = rfcParty }
  fights[#fights + 1] = { uid = "fx-rfc-3", session = s, startEpoch = rfcT + 655, duration = 70, outcome = "kill", bossName = TARA, foes = { TARA }, zone = RFC, group = rfcParty }
  rfc.bosses[1].fight, rfc.bosses[2].fight = "fx-rfc-1", "fx-rfc-3"
  -- (the run's trash: a fight per kill, ending at the kill, in the instance; Jergosh and Bazzalan were pulled on the
  -- way out and left up)
  local TRASH = { { 140, "Ragefire Trogg", 18 }, { 170, "Ragefire Shaman", 16 }, { 210, "Searing Blade Cultist", 22 }, { 380, "Earthborer", 14 }, { 440, "Molten Elemental", 20 } }
  for i, tr in ipairs(TRASH) do
    fights[#fights + 1] = { uid = "fx-rfc-t" .. i, session = s, startEpoch = rfcT + tr[1] - tr[3], duration = tr[3], outcome = "kill", foes = { L(tr[2]) }, zone = RFC, group = rfcParty }
  end
  fights[#fights + 1] = { uid = "fx-rfc-4", session = s, startEpoch = rfcT + 738, duration = 10, outcome = "fled", bossName = JER, foes = { JER }, zone = RFC, group = rfcParty }
  fights[#fights + 1] = { uid = "fx-rfc-5", session = s, startEpoch = rfcT + 742, duration = 8, outcome = "fled", bossName = BAZ, foes = { BAZ }, zone = RFC, group = rfcParty }
  -- the run in the session's events and sums: its boss pulls, its kills (bosses and trash), its loot, its XP
  local function ev(t, kind, text, extra)
    local e = { t = t, kind = kind, text = text, s = s, zone = RFC }
    for k, v in pairs(extra or {}) do e[k] = v end
    evs[#evs + 1] = e
  end
  ev(rfcT, "DUNGEON", RFC)
  local kills = 0
  for i, tr in ipairs(TRASH) do
    ev(rfcT + tr[1], "KILL", L(tr[2]) .. " down!", { foe = L(tr[2]) }); kills = kills + 1
    if i == 3 then ev(rfcT + tr[1] + 4, "LOOT", "Linen Cloth x4") end
  end
  ev(rfcT + 255, "BOSS", "Pull:  " .. OGG); ev(rfcT + 300, "KILL", OGG .. " down!", { foe = OGG }); kills = kills + 1
  ev(rfcT + 302, "LOOT", L("Cavedweller Bracers"))
  ev(rfcT + 500, "BOSS", "Pull:  " .. TARA); ev(rfcT + 530, "WIPE", "Wiped:  " .. TARA)
  -- (Tessa's death is the run's, in rec.deaths: a DEATH event is only ever the player's own, as the addon writes it)
  ev(rfcT + 655, "BOSS", "Pull:  " .. TARA); ev(rfcT + 725, "KILL", TARA .. " down!", { foe = TARA }); kills = kills + 1
  ev(rfcT + 728, "LOOT", L("Searing Collar"))
  ev(rfcT + 738, "BOSS", "Pull:  " .. JER); ev(rfcT + 742, "BOSS", "Pull:  " .. BAZ)
  ev(rfcT + 750, "DUNGEONLEAVE", "Left  " .. RFC)
  if ses then
    ses.xp = math.max(tonumber(ses.xp) or 0, 0) + 1840
    ses.kills = (tonumber(ses.kills) or 0) + kills
    ses.items = (tonumber(ses.items) or 0) + 3
    ses.dungeons = 1
  end
  -- (each Wailing Caverns run lies inside a session of its own, with its level and its XP: its loot is not this
  -- session's, B10. The ding to 17 happened in the later one, just before the run)
  ns.DB.sessions["fx-wc2-session"] = { id = "fx-wc2-session", guid = ns.charGuid(), startedEpoch = wc2.t - 900, endedEpoch = wc2.t + 2400,
    level0 = 16, level = 17, xp = 5350, kills = 138, items = 9, dungeons = 1, gained = 10200, spent = 0 }
  ns.DB.sessions["fx-wc1-session"] = { id = "fx-wc1-session", guid = ns.charGuid(), startedEpoch = wc1.t - 1200, endedEpoch = wc1.t + 2700,
    level0 = 16, level = 16, xp = 4620, kills = 121, items = 7, dungeons = 1, gained = 9400, spent = 0 }
  for _, e in ipairs(evs) do
    if e.kind == "LEVELUP" and tostring(e.text or ""):match("(%d+)") == "17" then
      keep.ding17 = { e, e.t, e.s }
      e.t, e.s = wc2.t - 300, "fx-wc2-session"
    end
  end
  log[#log + 1] = { s = "fx-wc2-session", t = wc2.t + 420, id = 6087, item = L("Serpent's Shoulders"), count = 1, q = "ff0070dd", src = L("Lord Serpentis"), zone = "Wailing Caverns", icon = "Interface\\Icons\\INV_Shoulder_09" }
  log[#log + 1] = { s = "fx-wc2-session", t = wc2.t + 1500, id = 6449, item = L("Glowing Lizardscale Cloak"), count = 1, q = "ff1eff00", src = L("Lady Anacondra"), zone = "Wailing Caverns", icon = "Interface\\Icons\\INV_Misc_Cape_18" }
  fights[#fights + 1] = { uid = "fx-wc-1", session = s, startEpoch = wc2.t + 300, duration = 50, outcome = "kill", bossName = L("Lady Anacondra"), foes = { L("Lady Anacondra") }, zone = "Wailing Caverns", group = wcParty }
  if long then for _, r in ipairs({ wc1, wc2 }) do for _, b in ipairs(r.bosses or {}) do b.name = L(b.name) end end end
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
    -- Ragefire Chasm in progress: 12m 40s inside, Oggleflint down. The run at 21:39 stays (B2): two runs this hour,
    -- and the live one compares at boss 1 against it
    local t = now - 760
    local rec = T.runRecord("Ragefire Chasm", t, 760, { firstPull = 120, size = 5, diff = 1, map = 389,
      bosses = { { enc = 1443, name = OGG, pulls = 1, combat = 45, kill = 300, dur = 45 } },
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
    c.dungeonCopies[#c.dungeonCopies + 1] = { t = t, key = "Ragefire Chasm", run = rec.id, why = "first" }
  end
  -- (the event log in time order, as the addon writes it: the runs' events go in among the session's own, so
  -- Activity reads them in the order they happened)
  local pos = {}
  for i, e in ipairs(evs) do pos[e] = i end
  table.sort(evs, function(a, b) local ta, tb = tonumber(a.t) or 0, tonumber(b.t) or 0; if ta ~= tb then return ta < tb end return pos[a] < pos[b] end)
  ns.Runs.statsRebuild(c)
  return undo, { wc1 = wc1, wc2 = wc2, rfc = rfc, open = c.dungeonRun }
end

return F
