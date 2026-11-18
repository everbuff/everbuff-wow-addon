-- Gold showcase: zones, runs, months, records, the balance line and the audit (everbuff-wow-addon #43, 0.9.47).
-- Loaded by tests/run_tests.lua after tests/gold_sources.lua:
--   dofile("tests/gold_show.lua")({ check = check, M = M, ns = ns })
-- Runs on a save file of its own (the suite's is put aside and put back), with the clock and the map in the test's
-- hands: coin lands on the map the player stands on, the place cap keeps its sums, a dungeon run opens and closes
-- where the addon's own detection says so (instance type "none", no English name list), the run ring wraps at 50 and
-- outlives the acknowledgement, an item with no price counts 0 and reads "so far", the fold after 400 days keeps
-- every sum and touches one block, the records, the balance line, the three states of the audit, and a soak (10,000
-- purse changes over 200 days and 6 characters) with the time a refresh takes and the size of what is saved.
return function(P)
  local M, ns = P.M, P.ns
  local E, G = ns.Emitter, ns.Gold
  local DAY = 86400
  local ME = "Player-1-000001"
  local fmt = ns.fmtMoney
  local realPrint, realDate = print, _G.date
  local function check(name, cond, detail) local mine = print; print = realPrint; P.check(name, cond, detail); print = mine end
  print = function() end

  local function deepcopy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = deepcopy(x) end
    return out
  end
  local function same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not same(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
  end
  local function count(t) local n = 0; for _ in pairs(t or {}) do n = n + 1 end return n end

  -- the suite's state, put aside
  local main = { db = ns.DB, epoch = M.epoch, now = M.now, money = M.money, zone = M.zone, inst = M.inst, uiMap = M.uiMap, mapType = M.mapType,
    resetSecs = M.resetSecs, weekStart = M.weekStart }
  local real = { guid = _G.UnitGUID, msg = ns.msg, cmap = _G.C_Map, instances = E.INSTANCES, cap = E.GOLD_CAP, zoneCap = G.ZONE_CAP,
    frameShown = _G.EverbuffFrame and _G.EverbuffFrame.shown, current = ns.Recorder.current }
  ns.Recorder.pause("logout")
  local function outside()
    M.zone, M.uiMap, M.mapType = "Elwynn Forest", 37, 3
    M.inst = { name = "Elwynn Forest", type = "none", diff = 0, mapID = 0 }
  end
  local function fresh(db)
    ns.Recorder.discard()
    ns.DB = ns.migrateDB(db or {})
    G._held, G._baseWait, G._flushTimer, G._tickAt, G._afk, G._rateErr, G._placeErr = nil, nil, nil, nil, nil, nil, nil
    E._openGain, E._questMoney, E._dayErr = nil, nil, nil
    ns._test.newLoad()
    M.timers = {}
    M.resetSecs, M.weekStart = nil, nil
    for _, e in ipairs({ "MERCHANT_CLOSED", "MAIL_CLOSED", "AUCTION_HOUSE_CLOSED", "TRAINER_CLOSED", "TRADE_CLOSED" }) do M.fire(e) end
    M.units.NPC = nil
    outside()
    M.now = M.now + 100
  end
  local function login(reload) M.fire("PLAYER_ENTERING_WORLD", not reload, reload and true or false); M.runTimers() end
  local function money(d) M.money = M.money + d; M.fire("PLAYER_MONEY") end
  local function loot(d)
    M.units.target = { name = "Kobold Miner", hostile = true, dead = true, guid = "Creature-0-1-1-1-6-00AA" }
    M.fire("LOOT_OPENED"); money(d)
    M.units.target = nil
    M.now = M.now + 4   -- past the loot window
  end
  local function quest(d) E.questMoney(d, 4242); money(d); M.now = M.now + 4 end
  local function item(id, n) M.fire("CHAT_MSG_LOOT", ("You receive loot: |cffffffff|Hitem:%d::::::::12:::::|h[Item %d]|h|r%s."):format(id, id, n and n > 1 and ("x" .. n) or "")) end
  local function play(sec)
    for _ = 1, math.floor(sec / 10) do M.now = M.now + 10; M.epoch = M.epoch + 10; G.tick() end
  end
  local function me() return ns.DB.characters[ME] end
  local function enter(name, zoneText)
    -- WoW Forever inside a dungeon: GetInstanceInfo says "none"; the map the player stands on is a dungeon map
    M.zone, M.mapType = zoneText or name, 4
    M.inst = { name = name, type = "none", diff = 0, mapID = 0 }
    E.checkInstance()
  end
  local function leave() outside(); E.checkInstance() end
  local said = {}
  ns.msg = function(s) said[#said + 1] = tostring(s) end
  if _G.EverbuffFrame then _G.EverbuffFrame.shown = false end   -- no pane on screen in this file

  local T0 = math.floor(1797000000 / DAY) * DAY + M.resetAt + 3600   -- an hour after a reset

  -- ── zones: coin lands on the map the player stands on ───────────────────────────────────────────────────────
  fresh()
  M.epoch, M.money = T0, 10000
  login(); G.tick()
  check("zones: nothing is stored before the first credit or tick", me().goldZones == nil and me().goldRuns == nil and me().goldRun == nil)
  loot(300)
  check("zones: looted coin lands on the map id current at the purse change", me().goldZones[37] and me().goldZones[37].looted == 300, me().goldZones and count(me().goldZones))
  check("zones: the row carries the zone's name and the time, the key is the map id", me().goldZones[37].name == "Elwynn Forest" and me().goldZones[37].last == M.epoch and me().goldZones["Elwynn Forest"] == nil)
  M.zone, M.uiMap = "Westfall", 52
  loot(120); quest(900)
  check("zones: a new map gets its own row; a quest reward is counted there too", me().goldZones[52].looted == 120 and me().goldZones[52].quests == 900 and me().goldZones[37].looted == 300)
  money(700)        -- a gain nothing explains
  money(-250)       -- a spend
  check("zones: income of another source and spending are not counted by place", me().goldZones[52].looted == 120 and me().goldZones[52].quests == 900)
  play(120)
  check("zones: active seconds go to the place the player stands on", me().goldZones[52].secs == 120 and me().goldZones[37].secs == 0, me().goldZones[52].secs)
  G._afk = true; play(60); G._afk = nil
  check("zones: time away from the keyboard is not time played there", me().goldZones[52].secs == 120)
  do
    local zs = G.zones()
    check("zones: the view lists the places with their coin, the total is the ledger's looted coin and quest rewards",
      #zs.rows == 2 and zs.total.looted == me().gold.looted and zs.total.quests == me().gold.quests and zs.total.coin == 1320 and zs.total.n == 2, zs.total.coin)
    check("zones: no rate under 5 minutes played in a place", zs.rows[1].id == 52 and zs.rows[1].perHour == nil)
    play(180)
    zs = G.zones()
    check("zones: coin per hour played in the place from 5 minutes on", zs.rows[1].secs == 300 and zs.rows[1].perHour == 1020 * 12, zs.rows[1].perHour)
  end
  -- the client names no map, or hides it
  do
    local cm = _G.C_Map
    _G.C_Map = { GetBestMapForUnit = function() return nil end, GetMapInfo = cm.GetMapInfo, GetPlayerMapPosition = cm.GetPlayerMapPosition }
    M.zone = "Somewhere"
    loot(40)
    check("zones: with no map id the coin is kept under 0 with the zone text", me().goldZones[0] and me().goldZones[0].looted == 40 and me().goldZones[0].name == "Somewhere")
    local secret = 987654
    M.secrets[secret] = true
    _G.C_Map.GetBestMapForUnit = function() return secret end
    loot(10)
    check("zones: a hidden map id is not read: the coin goes to 0", me().goldZones[0].looted == 50 and me().goldZones[secret] == nil)
    M.secrets[secret] = nil
    _G.C_Map.GetBestMapForUnit = function() error("blocked") end
    loot(5)
    check("zones: a throwing client function is contained", me().goldZones[0].looted == 55 and G._placeErr == nil, G._placeErr)
    _G.C_Map = nil
    loot(5)
    check("zones: a client with no C_Map still counts the coin", me().goldZones[0].looted == 60 and G._placeErr == nil, G._placeErr)
    _G.C_Map = cm
    check("zones: the total still is the ledger's", G.zones().total.looted == me().gold.looted and G.zones().total.quests == me().gold.quests)
    check("zones: the place without a map is named", (function() for _, r in ipairs(G.zones().rows) do if r.id == 0 then return r.name == "Somewhere" end end end)())
  end

  -- ── zones: the cap moves the place visited longest ago into the evicted sums ────────────────────────────────
  do
    fresh()
    M.epoch, M.money = T0, 10000
    login(); G.tick()
    G.ZONE_CAP = 5
    for i = 1, 8 do
      M.uiMap, M.zone = 1000 + i, "Zone " .. i
      loot(100 * i); quest(10 * i); play(20)
    end
    local c = me()
    local ev = c.goldZonesEvicted
    check("zone cap: the list holds the cap", count(c.goldZones) == 5, count(c.goldZones))
    check("zone cap: the three places visited longest ago left the list", c.goldZones[1001] == nil and c.goldZones[1002] == nil and c.goldZones[1003] == nil and c.goldZones[1004] ~= nil)
    check("zone cap: their coin and time are kept as one sum", ev and ev.n == 3 and ev.looted == 600 and ev.quests == 60 and ev.secs == 60, ev and ev.looted)
    local zs = G.zones()
    check("zone cap: the table still sums to the ledger through the evicted row", zs.total.looted == c.gold.looted and zs.total.quests == c.gold.quests and zs.total.secs == 160 and zs.total.n == 8, zs.total.looted)
    check("zone cap: the evicted places are one named row of the view", zs.evicted and zs.evicted.name == "3 earlier places" and zs.evicted.coin == 660)
    -- a place visited again is recent again
    M.uiMap, M.zone = 1004, "Zone 4"; loot(1)
    M.uiMap, M.zone = 1009, "Zone 9"; loot(1)
    check("zone cap: a place visited again is not the next to go", c.goldZones[1004] ~= nil and c.goldZones[1005] == nil and c.goldZonesEvicted.n == 4)
    check("zone cap: the sums hold after it", G.zones().total.looted == c.gold.looted)
    G.ZONE_CAP = real.zoneCap
  end

  -- ── runs: a dungeon run opens and closes where the addon's detection says so ────────────────────────────────
  fresh()
  M.epoch, M.money = T0, 50000
  login(); G.tick()
  loot(77)                                      -- before the dungeon
  enter("Shadowfang Keep")
  do
    local run = me().goldRun
    check("runs: a dungeon whose instance type is \"none\" is detected and opens a run", run ~= nil and run.inst == "Shadowfang Keep" and run.t == M.epoch and me().inInstance == "Shadowfang Keep")
    loot(2000); quest(1200)
    check("runs: looted coin and quest rewards inside go to the run", run.looted == 2000 and run.quests == 1200)
    -- a vendor sale and a repair inside the run are not the run's
    money(900); money(-400)
    check("runs: other income and spending are never given to a run", run.looted == 2000 and run.quests == 1200)
    M.sellPrice[9001], M.sellPrice[9002], M.sellPrice[9003] = 250, 0, nil
    item(9001, 3); item(9002)
    check("runs: an item looted in the run counts once, its vendor price times its count is the loot value", run.items == 2 and run.lootValue == 750 and run.wait == nil, run.lootValue)
    item(9003, 2)
    check("runs: an item with no cached sell price counts 0 and waits for its price", run.items == 3 and run.lootValue == 750 and run.wait and run.wait[9003] == 2)
    local v = G.runs().rows[1]
    check("runs: the value then reads \"so far\"", v.open == true and v.unpriced == 2 and G.lootValueText(v) == "so far about " .. fmt(750), G.lootValueText(v))
    play(600)
    v = G.runs().rows[1]
    check("runs: time played inside is the run's, coin per hour is coin over it", v.secs == 600 and v.coin == 3200 and v.perHour == 3200 * 6, v.perHour)
    check("runs: the line names items, coin, the loot value as an estimate and the rate",
      G.runLine(v) == ("3 items  ·  %s coin  ·  loot value so far about %s  ·  %s/h"):format(fmt(3200), fmt(750), G.fmt(19200, { rate = true })), G.runLine(v))
    check("runs: the rate never counts the loot value", v.perHour * 600 / 3600 == v.coin)
    -- the price arrives: the next look prices what waited
    M.sellPrice[9003] = 100
    item(9001)
    check("runs: a price that arrives later is counted then", run.wait == nil and run.lootValue == 750 + 200 + 250 and run.items == 4, run.lootValue)
    check("runs: and the value no longer reads \"so far\"", G.lootValueText(G.runs().rows[1]) == "about " .. fmt(1200))
    -- a wipe and the run back: leaving marks the run, going back in within 20 minutes continues it
    local t0 = run.t
    leave()
    check("runs: leaving marks the run, it stays open", me().goldRun == run and run.left == M.epoch and me().inInstance == nil)
    loot(55)
    check("runs: coin looted outside is not the run's", run.looted == 2000)
    M.epoch, M.now = M.epoch + 600, M.now + 600
    enter("Shadowfang Keep")
    check("runs: back in within 20 minutes continues the run", me().goldRun == run and run.left == nil and run.t == t0 and #(me().goldRuns or {}) == 0)
    loot(100)
    leave()
    M.epoch, M.now = M.epoch + 21 * 60, M.now + 21 * 60
    G.tick()
    local list = me().goldRuns
    check("runs: 20 minutes outside close the run into the list", me().goldRun == nil and list and #list == 1)
    local r = list[1]
    check("runs: the closed run keeps t, inst, secs, looted, quests, lootValue and items", r.t == t0 and r.inst == "Shadowfang Keep" and r.secs == 600 and r.looted == 2100
      and r.quests == 1200 and r.lootValue == 1200 and r.items == 4 and r.unpriced == nil and r.wait == nil and r.left == nil, r.secs)
    check("runs: every stored value of a run is a number or its name", (function()
      for k, x in pairs(r) do if not (type(x) == "number" or k == "inst") then return false end end
      return true
    end)())
  end
  -- an item still without a price when the run closes
  do
    M.sellPrice[9004] = nil
    enter("The Temple of Atal'Hakkar", "The Temple of Atal'Hakkar")
    check("runs: the two names the client gives one dungeon are one run name (Emitter.canonInstance)", me().goldRun.inst == "Sunken Temple")
    item(9004, 5); loot(10)
    -- the client flips to its other name for the same dungeon: no new run
    local run = me().goldRun
    enter("Sunken Temple", "Sunken Temple")
    check("runs: the other name of the same dungeon does not split the run", me().goldRun == run and #me().goldRuns == 1)
    -- straight into another dungeon closes the first
    enter("Scarlet Monastery")
    local closed = me().goldRuns[2]
    check("runs: going straight into another dungeon closes the run and opens the next", #me().goldRuns == 2 and closed.inst == "Sunken Temple" and me().goldRun.inst == "Scarlet Monastery")
    check("runs: an item never priced counts 0 and the closed run says how many", closed.lootValue == 0 and closed.items == 1 and closed.unpriced == 5)
    local v
    for _, x in ipairs(G.runs().rows) do if x.inst == "Sunken Temple" then v = x end end
    check("runs: its value reads \"so far\" for good", v and G.lootValueText(v) == "so far about " .. fmt(0) and G.runLine(v):find("loot value so far about", 1, true) ~= nil)
    leave()
    M.epoch, M.now = M.epoch + 21 * 60, M.now + 21 * 60
    G.runSync()
    check("runs: three closed runs, none open", #me().goldRuns == 3 and me().goldRun == nil)
  end
  -- detection with the English name list emptied (a client in another language): the dungeon map alone says so
  do
    E.INSTANCES = { party = {}, raid = {} }
    E._instByName = nil
    enter("Burg Schattenfang")
    check("runs: detection works with the English name list emptied", me().goldRun ~= nil and me().goldRun.inst == "Burg Schattenfang")
    loot(30)
    leave()
    M.epoch, M.now = M.epoch + 21 * 60, M.now + 21 * 60
    G.runSync()
    check("runs: that run closes like any other", #me().goldRuns == 4 and me().goldRuns[4].inst == "Burg Schattenfang" and me().goldRuns[4].looted == 30)
    E.INSTANCES = real.instances
    E._instByName = nil
  end
  -- Combat > Dungeons reads the run's own record
  do
    local runs = ns.DungeonRuns()
    local first
    for _, r in ipairs(runs) do if r.name == "Shadowfang Keep" then first = r; break end end
    local rec = first and G.runFor(first.name, first.startT, first.endT)
    check("dungeons: a run of Combat > Dungeons finds its gold record", rec ~= nil and rec.looted == 2100 and rec.quests == 1200, first and first.startT)
    check("dungeons: the line reads items, coin, loot value, coin per hour",
      rec and G.runLine(rec) == ("4 items  ·  %s coin  ·  loot value about %s  ·  %s/h"):format(fmt(3300), fmt(1200), G.fmt(3300 * 6, { rate = true })), rec and G.runLine(rec))
    check("dungeons: a run with no record keeps the loot log's line", G.runFor("Uldaman", 5, 10) == nil and G.runFor(nil, 5, 10) == nil)
    if first and ns._test.dungeonDetail() then
      ns._test.renderRun(first)
      local dv = ns._test.dungeonDetail()
      check("dungeons: the open run's page shows that line", dv and dv.lootLine == G.runLine(rec), dv and dv.lootLine)
    end
  end
  -- a /reload and a relog inside a run keep it
  do
    enter("Shadowfang Keep")
    loot(500)
    local snap = deepcopy(me().goldRun)
    M.fire("PLAYER_LOGOUT"); G._tickAt = nil; ns._test.newLoad()
    login(true); G.tick()
    check("runs: a /reload inside a run keeps the open run", same(me().goldRun, snap))
    loot(250)
    check("runs: and coin goes on counting on it", me().goldRun.looted == 750)
    leave()
    M.epoch, M.now = M.epoch + 21 * 60, M.now + 21 * 60
    G.runSync()
  end

  -- ── runs: the ring of the last 50, and the acknowledgement ──────────────────────────────────────────────────
  do
    local c = me()
    local had = #c.goldRuns
    local sumBefore = G.runs().total
    for i = 1, 53 do
      enter("Deadmines")                       -- (canonical: The Deadmines)
      loot(10 + i)
      leave()
      M.epoch, M.now = M.epoch + 21 * 60, M.now + 21 * 60
      G.runSync()
    end
    check("run ring: the list wraps at 50", #c.goldRuns == 50 and G.RUN_CAP == 50, #c.goldRuns)
    check("run ring: the newest run is last, the oldest kept is the one after the evicted", c.goldRuns[50].looted == 63 and c.goldRuns[50].inst == "The Deadmines" and c.goldRuns[1].looted == 10 + (had + 53 - 50 + 1 - had))
    local ev = c.goldRunsEvicted
    check("run ring: the runs past the ring are kept as one sum", ev and ev.n == had + 3, ev and ev.n)
    local t = G.runs().total
    local want = sumBefore.looted
    for i = 1, 53 do want = want + 10 + i end
    check("run ring: the table still sums to every run through the evicted row", t.looted == want and t.n == had + 53 and t.quests == sumBefore.quests and t.items == sumBefore.items, t.looted .. " " .. want)
    check("run ring: the view lists newest first with the evicted row named", G.runs().rows[1].looted == 63 and G.runs().evicted.inst == (had + 3) .. " earlier runs")
    -- the acknowledgement prunes sessions, loot rows and story events, never the runs
    local before, zonesBefore, bestBefore = deepcopy(c.goldRuns), deepcopy(c.goldZones), deepcopy(c.goldBest)
    local evBefore = deepcopy(c.goldRunsEvicted)
    local ack = { sessions = {}, through = M.epoch + 10 * DAY }
    for id in pairs(ns.DB.sessions) do ack.sessions[id] = true end
    M.fire("PLAYER_LOGOUT")
    ns.applyAck(ack, "file")
    check("ack: the story events of the runs are gone", #ns.DungeonRuns() == 0)
    check("ack: goldRuns, its evicted sum, goldZones and goldBest stay", same(c.goldRuns, before) and same(c.goldRunsEvicted, evBefore) and same(c.goldZones, zonesBefore) and same(c.goldBest, bestBefore))
    check("ack: the Runs view still lists them", #G.runs().rows == 50)
  end
  check("showcase: no error in the place and run writer", G._placeErr == nil and E._dayErr == nil, tostring(G._placeErr) .. tostring(E._dayErr))

  -- ── the month fold ──────────────────────────────────────────────────────────────────────────────────────────
  do
    fresh()
    M.epoch, M.money = T0, 5000
    login(); G.tick()
    money(100)                                  -- today's row, and the day base
    local c = me()
    local base = G.baseStored()
    local todayK = G.dayKey(M.epoch, base)
    local today = c.goldDays[todayK]
    -- 430 earlier days, oldest first, each opening where the one before closed and ending where today opens
    local N = 430
    local bal = today.o
    local rows = {}
    for i = 1, N do
      local g, s = 100 + i, i % 7 == 0 and 60 or 20
      local k = G.dayKey(M.epoch - i * DAY, base)
      local r = { g = g, s = s, t = 600 + i, n = 3, c = bal, looted = g - 10, quests = 10, repairs = s }
      if i % 50 == 0 then r.away = -5 end
      bal = bal - (g - s + (r.away or 0))
      r.o = bal
      if i % 9 == 0 then r.unexplained = 4; r.looted = r.looted - 4 end
      rows[k] = r
    end
    for k, r in pairs(rows) do c.goldDays[k] = r end
    c.goldSince = M.epoch - N * DAY
    -- another character with more than 400 rows of its own
    local OTHER = "Player-1-000002"
    ns.DB.characters[OTHER] = { name = "Mira", realm = "Stub", class = "MAGE", faction = "Alliance", level = 21, seen = M.epoch - 100,
      gold = { balance = 777, gained = 0, spent = 0 }, goldDays = deepcopy(rows) }
    local otherBefore = deepcopy(ns.DB.characters[OTHER])
    local settingsBefore = deepcopy(ns.DB.settings)
    local before = G.period("history", "char")
    local auditBefore = G.audit("history")
    check("fold: 431 day rows before it", count(c.goldDays) == 431 and c.goldMonths == nil)
    check("fold: the history adds up before it (changes while away make it not checkable, never broken)", auditBefore.state == "unknown" and auditBefore.text == nil, tostring(auditBefore.text))
    local folded = G.fold()
    check("fold: the days past the 400 newest are folded", folded == 31 and count(c.goldDays) == 400 and G.DAY_CAP == 400, folded)
    check("fold: today and the 399 days before it stay day rows", c.goldDays[todayK] == today and c.goldDays[G.dayKey(M.epoch - 399 * DAY, base)] ~= nil and c.goldDays[G.dayKey(M.epoch - 400 * DAY, base)] == nil)
    local nM, nD = 0, 0
    for k, m in pairs(c.goldMonths) do nM = nM + 1; nD = nD + m.d; if not k:match("^%d%d%d%d%d%d$") then nM = -99 end end
    check("fold: the folded days are in rows keyed YYYYMM that say how many days they hold", nM >= 1 and nM <= 3 and nD == 31, nM .. " " .. nD)
    local after = G.period("history", "char")
    check("fold: every sum of the history is what it was", same(after.ledger, before.ledger) and after.t == before.t and after.n == before.n, after.ledger.gained .. " " .. before.ledger.gained)
    check("fold: the history opens and closes on the same balances", after.open == before.open and after.close == before.close, tostring(after.open) .. " " .. tostring(before.open))
    check("fold: the month rows are the oldest rows of the history", after.days[#after.days].folded == true and after.days[1].key == todayK and #after.days == 400 + nM)
    do
      -- a month row has the shape of a day row: its sources sum to g and s, and it links into the chain
      local ok = true
      for _, m in pairs(c.goldMonths) do
        if (m.looted or 0) + (m.quests or 0) + (m.unexplained or 0) ~= m.g or (m.repairs or 0) ~= m.s then ok = false end
        if m.c - m.o ~= m.g - m.s + (m.away or 0) then ok = false end
      end
      check("fold: a month row keeps the identities of a day row", ok)
    end
    local auditAfter = G.audit("history")
    check("fold: the audit reads the same after it", auditAfter.state == auditBefore.state and auditAfter.text == nil and auditAfter.away == auditBefore.away, tostring(auditAfter.text))
    check("fold: only the logged-in character's block is folded", same(ns.DB.characters[OTHER], otherBefore) and count(ns.DB.characters[OTHER].goldDays) == 430)
    check("fold: no setting is written", same(ns.DB.settings, settingsBefore))
    check("fold: a second fold does nothing", G.fold() == 0 and count(c.goldDays) == 400)
    check("fold: a month reads as its name", G.monthLabel("202511") == "Nov 2025")
    -- the periods that sum days are untouched; the account still reads the other character's days
    check("fold: the last 30 days still sum their day rows", G.period("last30", "char").ledger.gained > 0 and #G.period("last30", "char").days == 30)
    check("fold: the account history counts both characters", G.period("history", "account").chars == 2)
    -- the fold runs at the character's own login: the other character's rows wait for theirs
    for i = 431, 440 do
      local k = G.dayKey(M.epoch - i * DAY, base)
      c.goldDays[k] = { g = 5, s = 0, t = 60, n = 1, looted = 5 }
    end
    local hist = G.period("history", "char").ledger.gained
    M.fire("PLAYER_LOGOUT"); G._tickAt = nil; ns._test.newLoad()
    login()
    check("fold: a login folds what is past the cap", count(c.goldDays) == 400 and G.period("history", "char").ledger.gained == hist)
    check("fold: and still leaves the other character alone", count(ns.DB.characters[OTHER].goldDays) == 430)
    -- Reset gold history takes the months too
    G.resetHistory(M.epoch)
    check("fold: Reset gold history removes the month rows with the day rows", c.goldMonths == nil and c.goldDays == nil)
  end

  -- ── records ─────────────────────────────────────────────────────────────────────────────────────────────────
  do
    fresh()
    M.epoch, M.money = T0, 100000
    login(); G.tick()
    check("records: none before gold moved", me().goldBest == nil and G.bestText() == nil)
    loot(5000)
    local base = G.baseStored()
    local k1 = G.dayKey(M.epoch, base)
    local b = me().goldBest
    local ses = ns.Recorder.current()
    check("records: the first day with a gain is the best day, the running session the best session", b and b.day.key == k1 and b.day.net == 5000 and b.session.at == ses.startedEpoch and b.session.net == 5000)
    money(-2000)
    check("records: the day that holds the record follows its own net", b.day.net == 3000 and me().goldBest.session.net == 3000)
    -- the next day beats it, then falls under it again: the record goes back to the first day
    M.epoch, M.now = M.epoch + DAY, M.now + DAY
    local k2 = G.dayKey(M.epoch, base)
    loot(4000)
    b = me().goldBest
    check("records: a better day takes the record and remembers the one it took it from", b.day.key == k2 and b.day.net == 4000 and b.day.was and b.day.was.key == k1 and b.day.was.net == 3000)
    money(-2500)
    b = me().goldBest
    check("records: when it falls under that one, the record goes back", b.day.key == k1 and b.day.net == 3000 and b.day.was == nil, b.day.key)
    local text = G.bestText()
    check("records: the text names the best day and the best session", text and text:find("^Best day " .. G.dayLabel(k1) .. " %+") ~= nil and text:find("best session", 1, true) ~= nil, text)
    check("records: a day with a loss is no record", (function() money(-90000); return me().goldBest.day.key == k1 end)())
    -- the fold cannot change a record: the record stays when its day row is gone
    me().goldDays[k1] = nil
    money(10)
    check("records: a record outlives its day row", me().goldBest.day.key == k1 and me().goldBest.day.net == 3000)
    -- a save file from before 0.9.47: the first note reads the day rows already kept
    me().goldBest = nil
    me().goldDays["20200101"] = { g = 99999, s = 9, t = 0, n = 1 }
    money(10)
    check("records: the first note reads the day rows already kept", me().goldBest.day.key == "20200101" and me().goldBest.day.net == 99990)
  end

  -- ── the balance line ────────────────────────────────────────────────────────────────────────────────────────
  do
    fresh()
    M.epoch, M.money = T0, 1000
    login(); G.tick()
    loot(100)                                   -- day 0 closes on 1100
    M.epoch, M.now = M.epoch + 3 * DAY, M.now + 3 * DAY
    money(-300)                                 -- day 3 closes on 800
    M.epoch, M.now = M.epoch + 2 * DAY, M.now + 2 * DAY   -- today is day 5, nothing moved
    local line = G.balanceLine("char", M.epoch)
    local n = G.STRIP_DAYS
    check("line: 30 day slots, today last", #line == n and line[n].live == true and line[n].key == G.dayKey(M.epoch, G.baseStored()))
    check("line: before the first row the opening balance of that row is carried back, marked stale", line[1] and line[1].v == 1000 and line[1].stale == true and line[n - 6].v == 1000)
    check("line: a day with a row shows its closing balance, not stale", line[n - 5].v == 1100 and line[n - 5].stale == false and line[n - 2].v == 800 and line[n - 2].stale == false)
    check("line: the days between two rows carry the balance forward, marked stale", line[n - 4].v == 1100 and line[n - 4].stale == true and line[n - 3].v == 1100 and line[n - 3].stale == true)
    check("line: a day after the last row carries it forward too", line[n - 1].v == 800 and line[n - 1].stale == true)
    check("line: today is the balance of the logged-in character, never stale", line[n].v == 800 and line[n].stale == false)
    -- a second character: the account line sums each character's own carried balance
    ns.DB.characters["Player-1-000002"] = { name = "Mira", realm = me().realm, class = "MAGE", faction = me().faction, level = 21, seen = M.epoch - 100,
      gold = { balance = 5000, gained = 0, spent = 0 } }
    local acct = G.balanceLine("account", M.epoch)
    check("line: the account line adds a character with no row at its stored balance", acct[n].v == 5800 and acct[1].v == 6000 and acct[n - 5].v == 6100)
    check("line: an account slot is stale when no character has a row that day", acct[n - 4].stale == true and acct[n - 5].stale == false)
    ns.DB.characters["Player-1-000002"] = nil
    -- no day base, no line
    local keep = ns.DB.settings.gold.dayBase
    ns.DB.settings.gold.dayBase = nil
    check("line: with no day base there is no line", #G.balanceLine("char", M.epoch) == 0)
    ns.DB.settings.gold.dayBase = keep
    -- the widget: one solid step per day with a row, dashes for a carried day, a riser where the balance moved
    local st = G.lineBuild(UIParent, "Balance, last 30 days", n)
    st.slot = 28
    G.lineRender(st, line)
    check("line widget: a solid step for each day with a row and for today", st.solid == 3, st.solid)
    check("line widget: carried days are drawn dashed", st.dashes == 27 * 4, st.dashes)
    check("line widget: a riser where the balance moved", st.risers == 2, st.risers)
    local shownSegs = 0
    for _, t in ipairs(st.segs) do if t.shown ~= false then shownSegs = shownSegs + 1 end end
    check("line widget: every segment drawn is shown, none left over from a wider draw", shownSegs == st.solid + st.dashes + st.risers, shownSegs)
    check("line widget: the title says the range", st.range.text == fmt(800) .. " to " .. fmt(1100), st.range.text)
    check("line widget: a slot's hover names the day and the balance, and says when it is carried", st.hits[n].tip == line[n].label .. "  ·  " .. fmt(800) and st.hits[n].tip2 == nil and st.hits[1].tip2 ~= nil)
    local empty = {}
    for i = 1, n do empty[i] = false end
    G.lineRender(st, empty)
    local left = 0
    for _, t in ipairs(st.segs) do if t.shown ~= false then left = left + 1 end end
    check("line widget: no balance known draws nothing", left == 0 and st.range.text == "")
  end

  -- ── the audit: reconciled, broken, not checkable ────────────────────────────────────────────────────────────
  do
    fresh()
    M.epoch, M.money = T0, 0
    login(); G.tick()
    local a0 = G.audit()
    check("audit: with nothing recorded it is not checkable, and says so", a0.state == "unknown" and a0.reason == "nothing is recorded yet" and G.auditText(a0) == "Not checkable: nothing is recorded yet")
    loot(1500); quest(800); money(-300); money(40)
    M.sellPrice[2589] = 13
    M.epoch, M.now = M.epoch + DAY, M.now + DAY
    loot(200); money(-150)
    local c = me()
    local a = G.audit()
    check("audit: a character played from zero reconciles", a.state == "ok" and a.text == nil and #a.notes == 0, tostring(a.text or a.reason))
    check("audit: every check ran: the journal, two days, the character", a.checks == 4, a.checks)
    check("audit: the reply of the command", G.auditText(a) == "Gold ledger reconciled.")
    check("audit: today, this week and the running session reconcile too", G.audit("today").state == "ok" and G.audit("session").state == "ok" and G.audit("yesterday").state == "ok",
      tostring(G.audit("today").reason or G.audit("today").text))
    said = {}
    SlashCmdList.EVERBUFF("gold audit")
    check("audit: /eb gold audit answers in chat", #said == 1 and said[1] == "Gold ledger reconciled.", said[1])
    said = {}
    SlashCmdList.EVERBUFF("gold audit today")
    SlashCmdList.EVERBUFF("gold audit nonsense")
    check("audit: /eb gold audit takes a period, and says which when it is none", said[1] == "Gold ledger reconciled." and said[2] and said[2]:find("^gold audit: ") ~= nil, said[2])
    said = {}
    SlashCmdList.EVERBUFF("gold help")
    check("audit: the command is in the list of gold commands", said[1] and said[1]:find("/eb gold audit", 1, true) ~= nil, said[1])
    do
      local inCombat = _G.InCombatLockdown
      _G.InCombatLockdown = function() return true end
      said = {}
      SlashCmdList.EVERBUFF("gold audit")
      _G.InCombatLockdown = inCombat
      check("audit: it answers in combat (it opens, moves and changes nothing)", said[1] == "Gold ledger reconciled.", said[1])
    end
    -- a read changes nothing
    do
      local snap = deepcopy(ns.DB)
      G.audit(); G.audit("today"); G.zones(); G.runs(); G.balanceLine("account"); G.bestText()
      check("audit: reading writes nothing into the save file", same(ns.DB, snap))
    end
    -- broken: a journal row whose balance does not follow
    local ses = ns.Recorder.current()
    local keepRow = ses.goldLog[2]
    do
      local mono, d, src, bal, ref = E.rowParse(keepRow)
      ses.goldLog[2] = ("%s\t%d\t%s\t%d\t%s"):format(mono, d, src, bal + 7, ref)
      local b = G.audit()
      check("audit: a journal row whose balance does not follow is a break, named by its row", b.state == "broken" and b.text:find("row 2", 1, true) ~= nil and b.reason == nil, b.text)
      check("audit: the reply names the break", G.auditText(b):find("^Gold ledger does not add up: session of ") ~= nil, G.auditText(b))
      check("audit: the session's own audit breaks with it", G.audit("session").state == "broken")
      ses.goldLog[2] = keepRow
    end
    -- broken: the rows of a source no longer sum to the session's ledger
    do
      ses.gold.other = ses.gold.other + 1
      local b = G.audit()
      check("audit: rows that do not sum to the session's ledger are a break, named by the source", b.state == "broken" and b.text:find("Unexplained spending", 1, true) ~= nil, b.text)
      ses.gold.other = ses.gold.other - 1
    end
    -- broken: a day row whose sources do not sum, and one whose balances do not follow
    do
      local base = G.baseStored()
      local kT = G.dayKey(M.epoch, base)
      local kY = G.dayKey(M.epoch - DAY, base)
      local r = c.goldDays[kT]
      r.looted = r.looted + 5
      local b = G.audit("today")
      check("audit: a day whose income sources do not sum to its gain is a break, named by the day", b.state == "broken" and b.text:find(G.dayLabel(kT), 1, true) ~= nil and b.text:find("income", 1, true) ~= nil, b.text)
      r.looted = r.looted - 5
      r.c = r.c + 3
      b = G.audit("today")
      check("audit: a day whose closing balance does not follow is a break", b.state == "broken" and b.text:find("the balance went from", 1, true) ~= nil, b.text)
      r.c = r.c - 3
      c.goldDays[kY].c = c.goldDays[kY].c + 9; c.goldDays[kY].g = c.goldDays[kY].g + 9; c.goldDays[kY].looted = c.goldDays[kY].looted + 9
      b = G.audit()
      check("audit: a day that does not open where the day before closed is a break", b.state == "broken" and b.text:find("opens on", 1, true) ~= nil, b.text)
      c.goldDays[kY].c = c.goldDays[kY].c - 9; c.goldDays[kY].g = c.goldDays[kY].g - 9; c.goldDays[kY].looted = c.goldDays[kY].looted - 9
      c.gold.balance = c.gold.balance + 1
      b = G.audit()
      check("audit: a balance the newest day did not close on is a break", b.state == "broken" and b.text:find("the balance is", 1, true) ~= nil, b.text)
      c.gold.balance = c.gold.balance - 1
      check("audit: put back, it reconciles again", G.audit().state == "ok", tostring(G.audit().text))
    end
    -- not checkable: the journal reached its cap (rows merged or not kept)
    do
      E.GOLD_CAP = #ses.goldLog + 3
      for _ = 1, 8 do loot(10) end
      local u = G.audit()
      check("audit: the journal cap reached gives not checkable, not broken", u.state == "unknown" and u.text == nil and u.reason:find("reached its cap", 1, true) ~= nil, tostring(u.text or u.reason))
      check("audit: its reply says so", G.auditText(u):find("^Not checkable: the journal of the session of ") ~= nil, G.auditText(u))
      check("audit: rows were merged, none read as a break", #ses.goldLog == E.GOLD_CAP and G.audit("session").state == "unknown")
      E.GOLD_CAP = real.cap
    end
    -- not checkable: a change while away in the period; everything recorded still adds up
    do
      fresh()
      M.epoch, M.money = T0, 0
      login(); G.tick()
      loot(1000)
      M.fire("PLAYER_LOGOUT"); G._tickAt = nil; ns._test.newLoad()
      M.epoch, M.now = M.epoch + DAY, M.now + DAY
      M.money = 700                             -- 300 spent on another PC
      login(); G.tick()
      loot(50)
      local u = G.audit()
      check("audit: a change while away makes the history not checkable, not broken", u.state == "unknown" and u.text == nil and u.away == -300 and u.reason:find("changed while away", 1, true) ~= nil, tostring(u.text or u.reason))
      check("audit: yesterday, with no gap, reconciles", G.audit("yesterday").state == "ok", tostring(G.audit("yesterday").reason))
      check("audit: today, with the gap, does not", G.audit("today").state == "unknown")
    end
    -- a character that had gold before the addon first saw it: noted, never judged
    do
      fresh()
      M.epoch, M.money = T0, 123456
      login(); G.tick()
      loot(100)
      local k = G.audit()
      check("audit: gold from before the addon is noted and not a break", k.state == "ok" and #k.notes == 1 and k.notes[1]:find(fmt(123456), 1, true) ~= nil, tostring(k.text or k.reason))
    end
    -- a period that begins before the history
    do
      M.epoch, M.now = M.epoch + 2 * DAY, M.now + 2 * DAY
      loot(100)
      local u = G.audit("last30")
      check("audit: a period that begins before the history is not checkable", u.state == "unknown" and u.reason:find("the history starts", 1, true) ~= nil, tostring(u.text or u.reason))
      check("audit: a day inside the history is", G.audit("today").state == "ok")
    end
    -- the character is not known yet
    do
      _G.UnitGUID = function() return nil end
      local u = G.audit()
      _G.UnitGUID = real.guid
      check("audit: before the character is known it is not checkable", u.state == "unknown" and u.reason == "the character is not known yet")
    end
  end

  -- ── soak: 10,000 purse changes over 200 days and 6 characters ───────────────────────────────────────────────
  do
    fresh()
    local seed = 20261118
    local function rnd(n) seed = (seed * 1103515245 + 12345) % 2147483648; return seed % n end
    local CHARS, DAYS, CHANGES = 6, 200, 10000
    local perDay = CHANGES / DAYS                -- 50 a day, each day one character's
    local start = T0 - DAYS * DAY
    local guids = {}
    for i = 1, CHARS do guids[i] = ("Player-1-0000%02d"):format(i) end
    local purse = {}
    local made = 0
    local current
    local function switch(i)
      if current then M.fire("PLAYER_LOGOUT") end
      current = i
      _G.UnitGUID = function(u) if u == "player" then return guids[i] end return real.guid(u) end
      G._tickAt = nil
      ns._test.newLoad()
      M.money = purse[i] or 0
      login(); G.tick()
    end
    local t0 = os.clock()
    for d = 0, DAYS - 1 do
      M.epoch = start + d * DAY
      M.now = M.now + 3600
      local i = d % CHARS + 1
      switch(i)
      M.uiMap, M.zone = 2000 + rnd(40), "Soak zone"
      if d % 10 == 3 then enter("Shadowfang Keep") end
      for _ = 1, perDay do
        local kind = rnd(10)
        if kind < 5 then loot(1 + rnd(900))
        elseif kind < 6 then quest(100 + rnd(5000))
        elseif kind < 8 then money(1 + rnd(400))
        elseif M.money > 500 then money(-(1 + rnd(400)))
        else loot(50) end
        made = made + 1
        M.epoch = M.epoch + 30
      end
      play(60)
      if me().inInstance or ns.char().inInstance then leave() end
      purse[i] = M.money
    end
    local built = os.clock() - t0
    check("soak: 10,000 purse changes were played", made == CHANGES, made)
    local rows, sessions = 0, 0
    for _, g in ipairs(guids) do rows = rows + count(ns.DB.characters[g].goldDays) end
    for _ in pairs(ns.DB.sessions) do sessions = sessions + 1 end
    check("soak: 200 day rows over 6 characters", rows == DAYS, rows)
    -- every character adds up; the logged-in one through the audit
    local okSum = true
    for _, g in ipairs(guids) do
      local c = ns.DB.characters[g]
      local gsum, ssum = 0, 0
      for _, r in pairs(c.goldDays) do gsum, ssum = gsum + r.g, ssum + r.s end
      if gsum ~= c.gold.gained or ssum ~= c.gold.spent or c.gold.balance ~= c.gold.gained - c.gold.spent then okSum = false end
      local z = 0
      for _, r in pairs(c.goldZones or {}) do z = z + r.looted + r.quests end
      if z ~= (c.gold.looted or 0) + (c.gold.quests or 0) then okSum = false end
    end
    check("soak: every character's days sum to its ledger and its places to its looted coin and quest rewards", okSum)
    local ta = os.clock()
    local a = G.audit()
    local auditMs = (os.clock() - ta) * 1000
    check("soak: the logged-in character reconciles", a.state == "ok", tostring(a.text or a.reason))
    check("soak: no error in any writer", G._placeErr == nil and E._dayErr == nil and G._rateErr == nil)
    -- the render: the Gold pane on each view, for the account's whole history
    ns.Recorder.current = function() return ns.DB.active and ns.DB.sessions[ns.DB.active] or nil end
    if _G.EverbuffFrame then _G.EverbuffFrame.shown = true end
    local worst, worstView, rendered = 0, "?", 0
    local okRender, errRender = pcall(function()
      ns.UI.Open("Loot", "gold")
      for _, v in ipairs(G.VIEWS) do
        for _, who in ipairs({ "char", "account" }) do
          local tr = os.clock()
          G.open("all", v[1]); M.settle()
          local c = ns._test.goldPane and ns._test.goldPane()
          if c and c.setWho then c.setWho(who); M.settle(); rendered = rendered + 1 end
          local ms = (os.clock() - tr) * 1000
          if ms > worst then worst, worstView = ms, v[1] .. "/" .. who end
        end
      end
    end)
    check("soak: every view of the Gold pane renders", okRender and rendered == 2 * #G.VIEWS and #M.errors == 0 and #ns.UI.paneErrors() == 0, tostring(errRender) .. " " .. table.concat(ns.UI.paneErrors(), " || "))
    check("soak: the slowest view renders within the budget (1.5 s)", worst < 1500, ("%s %.0f ms"):format(worstView, worst))
    check("soak: the audit of a character runs within the budget (0.5 s)", auditMs < 500, auditMs)
    -- the size of what the showcase and the history store, as the client would write it
    local function size(v, depth)
      if type(v) == "table" then
        local n = 4
        for k, x in pairs(v) do n = n + #tostring(k) + 8 + size(x, (depth or 0) + 1) + 2 * ((depth or 0) + 1) end
        return n
      elseif type(v) == "string" then return #v + 3 end
      return #tostring(v) + 1
    end
    local hist, show, all = 0, 0, 0
    for _, g in ipairs(guids) do
      local c = ns.DB.characters[g]
      hist = hist + size(c.goldDays) + size(c.goldRate)
      show = show + size(c.goldZones) + size(c.goldRuns) + size(c.goldRun) + size(c.goldBest) + size(c.goldZonesEvicted) + size(c.goldRunsEvicted)
      all = all + size(c)
    end
    check("soak: what the showcase stores for 6 characters stays under 100 KB", show < 100 * 1024, show)
    realPrint(("gold soak: %d purse changes, %d days, %d characters, %d sessions: played in %.1f s, slowest view %s %.0f ms, audit %.0f ms; saved %.1f KB for the character blocks (day rows and rate %.1f KB, zones, runs and records %.1f KB)")
      :format(made, DAYS, CHARS, sessions, built, worstView, worst, auditMs, all / 1024, hist / 1024, show / 1024))
    if ns.UI.Close then pcall(ns.UI.Close) end
    if _G.EverbuffFrame and _G.EverbuffFrame.Hide then pcall(_G.EverbuffFrame.Hide, _G.EverbuffFrame) end
    M.fire("PLAYER_LOGOUT")
  end

  -- ── the suite's save file and client back in place ──────────────────────────────────────────────────────────
  _G.UnitGUID, ns.msg, _G.C_Map = real.guid, real.msg, real.cmap
  E.INSTANCES, E._instByName, E.GOLD_CAP, G.ZONE_CAP = real.instances, nil, real.cap, real.zoneCap
  ns.Recorder.current = real.current
  if _G.EverbuffFrame then _G.EverbuffFrame.shown = real.frameShown end
  ns.Recorder.discard()
  ns.DB = main.db
  G._held, G._baseWait, G._flushTimer, G._tickAt, G._afk, G._placeErr = nil, nil, nil, nil, nil, nil
  E._openGain, E._questMoney = nil, nil
  M.timers = {}
  M.zone, M.inst, M.uiMap, M.mapType = main.zone, main.inst, main.uiMap, main.mapType
  M.resetSecs, M.weekStart = main.resetSecs, main.weekStart
  M.epoch, M.now, M.money = main.epoch, M.now + 100, main.money
  for _, e in ipairs({ "MERCHANT_CLOSED", "MAIL_CLOSED", "AUCTION_HOUSE_CLOSED", "TRAINER_CLOSED", "TRADE_CLOSED" }) do M.fire(e) end
  ns._test.newLoad()
  M.fire("PLAYER_ENTERING_WORLD", false, true); M.runTimers()
  print = realPrint
  check("showcase: the suite's save file is back, its session resumed", ns.DB == main.db and ns.Recorder.current() ~= nil and ns.DB.characters[ME].gold.balance == main.money)
end
