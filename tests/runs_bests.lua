-- Bests, statistics, undo, the glance and the hour count of the dungeon run (0.9.51, everbuff-wow-addon #51, the
-- plan's milestone "0.9.50"; Everbuff/Runs.lua). Loaded by tests/run_tests.lua after tests/runs.lua:
--   dofile("tests/runs_bests.lua")({ check = check, M = M, ns = ns })
-- Runs on a save file of its own (the suite's is put aside and put back), with the clock in the test's hands. The
-- runs are played through the real events; the numbers are worked out by hand in the comments beside them.
return function(P)
  local M, ns = P.M, P.ns
  local E, G, R, T = ns.Emitter, ns.Gold, ns.Runs, ns._test
  local ME = "Player-1-000001"
  local SEP = "  ·  "
  local realPrint = print
  local function check(name, cond, detail) local mine = print; print = realPrint; P.check("bests: " .. name, cond, detail); print = mine end
  print = function() end

  local function deepcopy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = deepcopy(x) end
    return out
  end
  local function same(a, b, path)
    path = path or ""
    if type(a) ~= type(b) then return false, path .. " " .. type(a) .. "/" .. type(b) end
    if type(a) ~= "table" then if a == b then return true end return false, path .. " " .. tostring(a) .. "/" .. tostring(b) end
    for k, v in pairs(a) do local ok, w = same(v, b[k], path .. "." .. tostring(k)); if not ok then return false, w end end
    for k in pairs(b) do if a[k] == nil then return false, path .. "." .. tostring(k) .. " missing" end end
    return true
  end

  local main = { db = ns.DB, epoch = M.epoch, now = M.now, money = M.money, zone = M.zone, inst = M.inst, uiMap = M.uiMap, mapType = M.mapType,
    groupN = M.groupN, units = M.units, inCombat = M.inCombat, dead = M.dead, errors = #M.errors, xp = M.xp, xpmax = M.xpmax, level = M.level }
  local real = { msg = ns.msg }
  local said = {}
  ns.msg = function(s) said[#said + 1] = tostring(s) end
  ns.Recorder.pause("logout")
  local function outside()
    M.zone, M.uiMap, M.mapType = "Elwynn Forest", 37, 3
    M.inst = { name = "Eastern Kingdoms", type = "none", diff = 0, mapID = 0 }
  end
  local function me() return ns.DB.characters[ME] end
  local function open() return me() and me().dungeonRun end
  local function closed() return (me() and me().dungeonRuns) or {} end
  local function raw() local l = closed(); return l[#l] end
  local function stats(name) local S = me().dungeonStats; return S and S[name:lower()] end
  local function notes() return (ns.DB.settings.selftest and ns.DB.settings.selftest.runs) or {} end
  local function adv(s) M.epoch, M.now = M.epoch + s, M.now + s end
  local function play(sec)
    for _ = 1, math.floor(sec / 10) do adv(10); R.tick(); G.tick() end
    local rest = sec % 10
    if rest > 0 then adv(rest) end
  end
  local function pew(login, reload) M.fire("PLAYER_ENTERING_WORLD", login and true or false, reload and true or false); M.runTimers() end
  local function fresh()
    if T.currentFight() then M.inCombat = false; M.fire("PLAYER_REGEN_ENABLED") end
    ns.Recorder.discard()
    ns.DB = ns.migrateDB({})
    G._held, G._baseWait, G._flushTimer, G._tickAt, G._afk, G._rateErr, G._placeErr = nil, nil, nil, nil, nil, nil, nil
    T.newLoad()
    M.timers = {}
    M.units, M.groupN, M.inCombat, M.dead = {}, 1, false, false
    M.money, M.xp, M.xpmax, M.level = 500000, 100, 1000, 12
    for _, e in ipairs({ "MERCHANT_CLOSED", "MAIL_CLOSED", "AUCTION_HOUSE_CLOSED", "TRAINER_CLOSED", "TRADE_CLOSED" }) do M.fire(e) end
    outside()
    adv(100)
    pew(true)
    R.tick(); G.tick()
    said = {}
  end
  local function place(zone, o)
    o = o or {}
    M.zone, M.mapType = zone, o.mapType or 3
    M.inst = { name = o.name or zone, type = o.type or "party", diff = 1, mapID = o.map == nil and 349 or o.map }
  end
  local function enter(zone, o)
    place(zone, o)
    if o and o.noLoad then M.fire("ZONE_CHANGED_NEW_AREA") else pew() end
  end
  local function leave(noLoad) outside(); if noLoad then M.fire("ZONE_CHANGED_NEW_AREA") else pew() end end
  local function walk(zone, map)
    M.zone, M.mapType = zone, 3
    M.inst = { name = map == 1 and "Kalimdor" or "Eastern Kingdoms", type = "none", diff = 0, mapID = map or 0 }
    M.fire("ZONE_CHANGED_NEW_AREA")
  end
  local function START(id, name) M.fire("ENCOUNTER_START", id, name, 1, 5) end
  local function END(id, name, ok) M.fire("ENCOUNTER_END", id, name, 1, 5, ok) end
  local function kill(id, name, secs) START(id, name); play(secs or 30); END(id, name, 1) end
  local function die() M.dead = true; M.fire("PLAYER_DEAD") end
  local function rise() M.dead = false; M.fire("PLAYER_UNGHOST") end
  local function combat(on) M.inCombat = on; M.fire(on and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED") end
  local function money(d) M.money = M.money + d; M.fire("PLAYER_MONEY") end
  local function loot(d)
    M.units.target = { name = "Kobold Miner", hostile = true, dead = true, guid = "Creature-0-1-1-1-6-00AA" }
    M.fire("LOOT_OPENED"); money(d)
    M.units.target = nil
    M.now = M.now + 4
  end
  local function expire() play(R.REENTER + 10) end
  local function errs() return #M.errors end
  -- A clear on the run's clock: `fp` seconds inside before the first pull (standing at the entrance), then each kill
  -- at its offset from the run's start (a pull of `dur` seconds, 10 by default, ending at `at`). `leave` on a kill:
  -- out alive for that many seconds before its pull (a time outside, which is on no clock of the run). Ends with
  -- `after` seconds inside, then leaves for good. Returns the stored record.
  local function clear(name, map, fp, kills, o)
    o = o or {}
    enter(name, { map = map })
    play(fp); combat(true)
    local c = fp
    for _, k in ipairs(kills) do
      if k.leave then combat(false); leave(); play(k.leave); enter(name, { map = map }); combat(true) end
      local dur = k.dur or 10
      play(k.at - dur - c)
      START(k.id, k.name or ("Boss " .. k.id)); play(dur); END(k.id, k.name or ("Boss " .. k.id), k.ok or 1)
      c = k.at
    end
    combat(false)
    play(o.after or 30)
    if o.stay then return open() end
    leave(); expire()
    return raw()
  end
  local function boss(run, id) for _, b in ipairs(run.bosses) do if b.enc == id then return b end end end
  -- the invariants of every record after an edit: the four clocks sum to the wall time, the visits to the run
  local nInv = 0
  local function invariants(tag)
    nInv = nInv + 1
    local why
    local function one(r, isOpen)
      local s = r.secs
      local function n(v) return v or 0 end
      local sum = { secs = 0, active = 0, combat = 0, boss = 0, looted = 0, xp = 0 }
      for _, v in ipairs(r.visits) do for k in pairs(sum) do sum[k] = sum[k] + n(v[k]) end end
      if not isOpen and n(s.inside) + n(s.ghost) + n(s.outside) + n(s.offline) ~= r.endT - r.t then why = why or ("clocks of " .. r.id) end
      if sum.secs ~= n(s.inside) or sum.active ~= n(s.active) then why = why or ("inside or active of " .. r.id) end
      if (r.v or 1) >= 2 and (sum.combat ~= n(s.combat) or sum.boss ~= n(s.boss)) then why = why or ("combat or boss of " .. r.id) end
      if not isOpen and sum.looted ~= n(r.gold and r.gold.looted) then why = why or ("gold of " .. r.id) end
      if sum.xp ~= n(r.xp and r.xp.gain) then why = why or ("xp of " .. r.id) end
      if not (isOpen and R.validOpen(r) or R.valid(r)) then why = why or ("not valid: " .. r.id) end
    end
    for _, r in ipairs(closed()) do one(r, false) end
    if open() then one(open(), true) end
    check("invariants after " .. tag, why == nil and R._err == nil, why or R._err)
  end
  local DM, DMAP = "The Deadmines", 36
  -- the Dungeons pane is built the first time it is opened: open it once and close the window again
  if not T.dungeonDetail() then
    local wasShown = ns.UI.frame and ns.UI.frame:IsShown()
    ns.UI.Open("Combat", "Dungeons")
    if not wasShown then ns.UI.Toggle() end
  end
  local K3 = function(a, b, c, o) o = o or {}; return { { id = 644, at = a }, { id = 645, at = b }, { id = 646, at = c, leave = o.leaveC } } end

  -- ── three runs with known offsets: the best, the deltas and the segment keys ─────────────────────────────────
  do
    fresh()
    -- run 1: first pull at 100, kills at 200, 400, 700: 600 s from the first pull to the last kill
    local r1 = clear("Deadmines", DMAP, 100, K3(200, 400, 700))
    local sig = "644.645.646/d1/solo"
    local s = stats(DM)
    check("1: a closed run is counted in its dungeon's statistics", s and s.n == 1 and s.inst == DM and s.routes[sig] and s.routes[sig].best == 600 and s.routes[sig].bestId == r1.id
      and R.isPb(r1), s and s.n)
    check("1: its route is the sorted ids it killed, with the difficulty and solo", R.routeOf(r1) == "644.645.646" and R.sigOf(r1) == sig and r1.size == 1 and r1.route == nil)
    -- the entrance does not count: 100 s stood there, and the best is first pull to last kill
    check("1: standing at the entrance before the first pull is not in the best", R.measure(r1) == 600 and r1.firstPull == 100 and r1.secs.inside > 700)
    -- run 2: first pull at 50, kills at 150, 300, 550: 500 s, a new best
    local r2 = clear("Deadmines", DMAP, 50, K3(150, 300, 550))
    s = stats(DM)
    check("2: a faster run sets the best and says so", s.routes[sig].best == 500 and s.routes[sig].bestId == r2.id and R.isPb(r2) and s.n == 2, s.routes[sig].best)
    -- run 3: first pull at 80, kills at 230, 420, then 5 minutes outside alive, and 646 at 720 on the run's clock
    local r3 = clear("Deadmines", DMAP, 80, K3(230, 420, 720, { leaveC = 300 }))
    s = stats(DM)
    check("3: a slower run sets no best", s.routes[sig].best == 500 and s.routes[sig].bestId == r2.id and not R.isPb(r3) and s.n == 3 and s.routes[sig].n == 3)
    check("3: the 5 minutes outside are in no split: 640 s on the run's clock, not 940", R.measure(r3) == 640 and r3.secs.outside == 300 and #r3.visits == 2
      and R.splits(r3)[646].at == 640, R.measure(r3))
    -- the best run's splits, for VS BEST: 100, 250, 500 from its first pull
    local sp = s.routes[sig].splits
    check("3: the best run's splits are kept, seconds from its first pull", sp[644] == 100 and sp[645] == 250 and sp[646] == 500)
    -- the best segments: start>644 is 100 in run 1 and in run 2 (run 1 had it first), 644>645 150 (run 2), 645>646 250
    local seg = s.routes[sig].seg
    check("3: segment keys run from the group before to the group", seg["start>644"].s == 100 and seg["start>644"].id == r1.id and seg["644>645"].s == 150
      and seg["644>645"].id == r2.id and seg["645>646"].s == 250 and seg["645>646"].id == r2.id)
    local v3 = R.views()[3]
    local cmp = v3.cmp
    check("3: against the best: +140, each boss +50, +90, +140", cmp and cmp.mode == "same" and cmp.delta == 140 and cmp.vs[644] == 50 and cmp.vs[645] == 90 and cmp.vs[646] == 140
      and cmp.isBest == false, cmp and cmp.delta)
    check("3: the sum of the best segments, in this run's own order", cmp.sumBest == 500, cmp.sumBest)
    check("3: the deltas read with a sign and an arrow", R.deltaText(140) == "+2:20 " .. R.UP and R.deltaText(-42) == "-0:42 " .. R.DOWN and R.deltaText(0) == "±0:00"
      and R.deltaText(3729) == "+1:02:09 " .. R.UP and R.signed(41) == "+0:41")
    local v1, v2 = R.views()[1], R.views()[2]
    check("3: run 1 is 100 s behind the best now, run 2 is the best", v1.cmp.delta == 100 and v2.cmp.isBest == true and v2.cmp.runs == 3)
    -- the Pace lines and the TIME tile of the page
    T.renderRun(v3)
    local dv = T.dungeonDetail()
    -- (the line names the measure and gives this run's own value on it: 640 s, not the 1000-odd s of its TIME tile)
    check("3: Pace reads the best, its date, the measure and this run's value and delta", dv.paceLine == ("Best 8m 20s on %s, first pull to last kill"):format(date("%d %b", r2.t)) .. SEP .. "this run 10m 40s (+2:20 " .. R.UP .. ")"
      and dv.paceLine2 == "Sum of best segments 8m 20s", dv.paceLine)
    check("3: the TIME tile carries the delta", dv.deltaText == "+2:20 " .. R.UP, dv.deltaText)
    local vsCells = {}
    for _, fs in ipairs(dv.child.fs) do if fs.shown ~= false and tostring(fs.text):match("^[%+%-]%d+:%d%d") then vsCells[#vsCells + 1] = fs.text end end
    local allMarked = #vsCells >= 3
    for _, t in ipairs(vsCells) do if not (t:find(R.UP, 1, true) or t:find(R.DOWN, 1, true)) then allMarked = false end end
    check("3: every delta on the page has its sign and its arrow (colour never alone)", allMarked, table.concat(vsCells, " | "))
    T.renderRun(v2)
    check("3: the best run's page says it is the best", dv.paceLine == ("Best 8m 20s on %s, first pull to last kill"):format(date("%d %b", r2.t)) .. SEP .. "this run is the best" and dv.deltaText == "best", dv.paceLine)
    -- the list: LENGTH carries the delta, BOSSES the learned list (3 runs, 3 bosses each: 3/3)
    local lv = T.dungeonList()
    local rows = {}
    for _, r in ipairs(lv.tbl.rows) do if r.shown ~= false and r.run then rows[r.run.id] = r end end
    check("3: LENGTH reads the delta after the length", rows[r3.id] and rows[r3.id].c.dur.text == R.fmtDur(v3.duration) .. " · +2:20 " .. R.UP
      and rows[r2.id].c.dur.text:find(" · best$") ~= nil, rows[r3.id] and rows[r3.id].c.dur.text)
    check("3: BOSSES reads 3/3 once the dungeon has a learned list", rows[r3.id].c.boss.text == "3/3" and v3.total == 3, rows[r3.id].c.boss.text)
    check("3: the first run of a dungeon reads 'first run here' while it is the only one", (function()
      fresh(); local r = clear("Deadmines", DMAP, 10, K3(100, 200, 300)); local v = R.views()[1]
      T.renderRun(v); return v.cmp.isBest and T.dungeonDetail().deltaText == "first run here" and R.isPb(r) and r.done == nil
        and T.dungeonDetail().paceLine == nil end)())                -- (and no Pace before the dungeon's first full clear)
    invariants("three runs")
  end

  -- ── a 4-of-5 run sets no full-route best; the learned list and the full clear ─────────────────────────────────
  do
    fresh()
    local SFK = "Shadowfang Keep"
    local five = function(base) return { { id = 1, at = base + 100 }, { id = 2, at = base + 200 }, { id = 3, at = base + 300 }, { id = 4, at = base + 400 }, { id = 5, at = base + 500 } } end
    local a = clear(SFK, 33, 50, five(50))                        -- 500 s
    local b = clear(SFK, 33, 50, five(40))                        -- 490 s
    local full = "1.2.3.4.5/d1/solo"
    local s = stats(SFK)
    check("4of5: the learned list exists from the second run: every boss killed in at least half", R.learned(s) and #R.learned(s) == 5 and s.n == 2)
    -- (the first run closes with no list; the second gives the list and judges the first again: both are full clears)
    check("4of5: two identical clears are two full clears, the first judged once the list exists", a.done == true and b.done == true and s.full == 2, tostring(a.done) .. " " .. tostring(b.done) .. " " .. tostring(s.full))
    local c4 = clear(SFK, 33, 10, { { id = 1, at = 60 }, { id = 2, at = 110 }, { id = 3, at = 160 }, { id = 4, at = 210 } })   -- 200 s, boss 5 never pulled
    s = stats(SFK)
    check("4of5: a 4-of-5 run sets no best on the full route", s.routes[full].best == 490 and s.routes[full].bestId == b.id and s.routes["1.2.3.4/d1/solo"].best == 200
      and R.isPb(c4) and c4.done == nil and s.full == 2)
    local v = R.views()[3]
    check("4of5: it reads 4/5 and lists the boss it never pulled", v.total == 5 and v.bossesDown == 4 and #v.missing == 1 and v.missing[1].enc == 5, v.total)
    T.renderRun(v)
    local nk = 0
    for _, fs in ipairs(T.dungeonDetail().child.fs) do if fs.shown ~= false and fs.text == "Not killed" then nk = nk + 1 end end
    check("4of5: the known boss not pulled reads Not killed on the page", nk == 1, nk)
    check("4of5: the 4-boss run against the full route: the shared start, at boss 4", (function()
      local cmp = R.compare(c4, true)                               -- (as a run in progress would read it)
      return cmp and cmp.mode == "prefix" and cmp.at == 4 end)())
    -- BY DUNGEON
    local rows = R.dungeonRows()
    -- (Average is the Best's own measure over the full route's runs: 500 and 490, not the time inside of all three)
    check("4of5: BY DUNGEON: runs, full clears, average, the full route's best", #rows == 1 and rows[1].n == 3 and rows[1].full == 2 and rows[1].best == 490
      and rows[1].avg == 495 and rows[1].deathsPerRun == 0, rows[1] and rows[1].avg)
    invariants("4of5")
  end

  -- ── partial, unknown and edited runs never set a best ─────────────────────────────────────────────────────────
  do
    fresh()
    local base = clear("Deadmines", DMAP, 50, K3(150, 300, 550))   -- 500 s, the best
    local sig = "644.645.646/d1/solo"
    -- unknown: a boss pulled, the character leaves alive before it ends: Outcome not seen
    enter("Deadmines", { map = DMAP }); play(10); combat(true)
    kill(644, "Rhahk'Zor", 10); START(645, "Sneed"); play(5); combat(false); leave(); play(30)
    enter("Deadmines", { map = DMAP }); combat(true); kill(646, "Gilnid", 10); combat(false); play(10); leave(); expire()
    local unk = raw()
    check("never: a run with an outcome not seen sets no best and is no full clear", not R.isPb(unk) and unk.done == nil and R.unknownBoss(unk) and stats(DM).routes[sig].best == 500
      and stats(DM).n == 2)
    -- resolved: the unseen pull is followed by a kill of the same boss in the same run
    enter("Deadmines", { map = DMAP }); play(10); combat(true)
    kill(644, "Rhahk'Zor", 10); START(645, "Sneed"); play(5); leave(); play(30); enter("Deadmines", { map = DMAP })
    kill(645, "Sneed", 10); kill(646, "Gilnid", 10); combat(false); leave(); expire()
    local res = raw()
    check("never: an unseen pull resolved by a kill of the same boss counts", not R.unknownBoss(res) and R.bestable(res) and boss(res, 645).unknown == 1)
    -- partial: the game closed without saving
    fresh()
    enter("Deadmines", { map = DMAP }); play(20); combat(true); kill(644, "Rhahk'Zor", 10)
    E.reloadAsked(); M.fire("PLAYER_LOGOUT")
    local file = deepcopy(ns.DB)
    ns.Recorder.discard(); ns.DB = ns.migrateDB(file)
    G._tickAt = nil; T.newLoad(); adv(3600); M.inCombat = false
    outside(); pew(true)
    check("never: a partial run is counted nowhere", raw() and raw().partial ~= nil and me().dungeonStats == nil and not R.isPb(raw()), raw() and raw().partial)
    check("never: the close of a partial run writes no second row (the row its entry wrote stays)", #(me().dungeonCopies or {}) == 1, #(me().dungeonCopies or {}))
    -- edited: split by hand
    fresh()
    clear("Deadmines", DMAP, 50, K3(150, 300, 550))
    clear("Deadmines", DMAP, 20, K3(100, 200, 900, { leaveC = 60 }))
    local id = raw().id
    local ok = R.split(id, 2)
    local A, B = closed()[2], closed()[3]
    check("never: an edited run sets no best", ok and A.edited and B.edited and not R.isPb(A) and not R.isPb(B) and stats(DM).routes[sig].best == 500
      and stats(DM).n == 3, tostring(ok))
    invariants("never")
  end

  -- ── evicting the best run keeps the best; a deleted best is taken from the runs still stored ─────────────────
  do
    fresh()
    local best = clear("Deadmines", DMAP, 50, K3(150, 300, 550))
    local sig = "644.645.646/d1/solo"
    local c = me()
    for i = 1, R.CAP - 1 do c.dungeonRuns[#c.dungeonRuns + 1] = T.runRecord("Uldaman", M.epoch + i, 90) end
    clear("Deadmines", DMAP, 50, K3(160, 320, 600))              -- 550 s, the 101st run
    check("evict: the best run is evicted from the list", #c.dungeonRuns == R.CAP and c.dungeonRuns[1].id ~= best.id)
    check("evict: its best stays in the statistics", stats(DM).routes[sig].best == 500 and stats(DM).routes[sig].bestId == best.id and stats(DM).n == 2)
    check("evict: the latest end of an evicted run is kept", c.dungeonEvictedTo == best.endT)
    -- a best whose run was deleted: the next best of the runs still stored
    fresh()
    local b1 = clear("Deadmines", DMAP, 50, K3(150, 300, 550))   -- 500
    local b2 = clear("Deadmines", DMAP, 50, K3(160, 320, 600))   -- 550
    clear("Deadmines", DMAP, 50, K3(170, 340, 650))               -- 600
    local ok = R.delete(b1.id)
    local r = stats(DM).routes[sig]
    check("delete: a deleted best is taken again from the runs still stored", ok and r.best == 550 and r.bestId == b2.id and r.n == 2 and stats(DM).n == 2
      and r.seg["start>644"].id ~= b1.id, r.best)
    -- delete equals a recompute: the statistics after the delete are the ones built from the runs left
    local after = deepcopy(me().dungeonStats)
    local keepRuns = deepcopy(me().dungeonRuns)
    R.statsRebuild(me(), true)
    local ok2, where = same(after, me().dungeonStats)
    check("delete: equals a recompute from the runs left", ok2 and same(keepRuns, me().dungeonRuns), where)
    -- deleting the last run of a dungeon removes its statistics
    for _, x in ipairs(deepcopy(me().dungeonRuns)) do R.delete(x.id) end
    check("delete: the last run of a dungeon gone, its statistics are gone", #closed() == 0 and stats(DM) == nil)
    invariants("delete")
  end

  -- ── split at visit 2 then join returns the original to the copper ───────────────────────────────────────────
  do
    fresh()
    enter("Maraudon"); play(60); combat(true); kill(422, "Noxxion", 30); combat(false); loot(120); M.xp = 300; M.fire("PLAYER_XP_UPDATE")
    play(40); combat(true); play(10); die(); combat(false); play(5); leave()      -- out as a ghost
    play(150); enter("Maraudon"); play(10); rise()
    play(30); combat(true); START(423, "Razorlash"); play(20); END(423, "Razorlash", 0); play(10)
    kill(423, "Razorlash", 25); combat(false); loot(77); M.xp = 600; M.fire("PLAYER_XP_UPDATE")
    play(20); leave(); play(400); enter("Maraudon"); play(30); combat(true); kill(424, "Lord Vyletongue", 40); combat(false)
    loot(5); play(30); leave(); expire()
    local orig = deepcopy(raw())
    check("split: the run has three visits, a ghost gap and an alive gap", #orig.visits == 3 and orig.visits[2].gg == 150 and orig.visits[3].go == 400 and orig.secs.ghost == 150 and orig.secs.outside == 400)
    local ok = R.split(orig.id, 2)
    local A, B = closed()[1], closed()[2]
    check("split: two runs, the first keeps the id, the second opens as a split", ok and #closed() == 2 and A.id == orig.id and B.id ~= orig.id and B.open == "split" and A.why == "split"
      and B.why == orig.why and A.edited and B.edited)
    check("split: the gap between them is no one's time", A.endT == orig.t + orig.visits[1].o and B.t == orig.t + orig.visits[2].i and (A.secs.ghost or 0) == 0
      and (B.secs.ghost or 0) == 0 and B.secs.outside == 400 and B.visits[1].gg == 150)
    check("split: the bosses go whole to the side of their kill, offsets from the new start", #A.bosses == 1 and A.bosses[1].enc == 422 and #B.bosses == 2 and boss(B, 423).pulls == 2
      and boss(B, 423).kill == boss(orig, 423).kill - (orig.visits[1].secs + 150))
    check("split: the death stays with the first, the coin and the XP with their visits", (A.nDeaths and A.nDeaths.me) == 1 and B.nDeaths == nil and A.gold.looted == 120 and B.gold.looted == 82
      and A.xp.gain == 200 and B.xp.gain == 300 and A.gold.looted + B.gold.looted == orig.gold.looted)
    invariants("split")
    local okJ = R.join(B.id)
    local J = closed()[1]
    local cmpJ, cmpO = deepcopy(J), deepcopy(orig)
    for _, x in ipairs({ cmpJ, cmpO }) do x.edited, x.pb, x.done = nil, nil, nil end
    local eq, where = same(cmpJ, cmpO)
    check("split then join returns the original to the copper", okJ and #closed() == 1 and eq and J.edited == true, where)
    check("split then join: the statistics count one run again", stats("Maraudon").n == 1, stats("Maraudon").n)
    invariants("join")
    -- a record of 0.9.50 with two kinds of time outside over three visits cannot say where its gaps were
    local old = T.runRecord("Maraudon", M.epoch + 10, 100)
    old.v = 1
    old.visits = { { i = 0, o = 50, secs = 50, how = "zone", out = "ghost" }, { i = 80, o = 100, secs = 20, how = "ghost", out = "alive" }, { i = 160, o = 190, secs = 30, how = "zone", out = "alive" } }
    old.endT, old.secs = old.t + 190, { inside = 100, ghost = 30, outside = 60 }
    me().dungeonRuns[#me().dungeonRuns + 1] = old
    local okOld, why = R.split(old.id, 2)
    check("split: a record of 0.9.50 with two kinds of gap is refused, and says why", okOld == false and why == "old")
    old.secs = { inside = 100, outside = 90 }
    okOld = R.split(old.id, 3)
    check("split: one with a single kind of gap is split exactly", okOld == true and closed()[#closed()].secs.inside == 30 and closed()[#closed() - 1].secs.outside == 30)
  end

  -- ── Delete, Split, Join and End run now on the open run; Join across an evicted neighbour; Keep at its limit ──
  do
    fresh()
    enter("Maraudon"); play(30); combat(true); kill(422, "Noxxion", 20); combat(false); play(10); leave(); play(60)
    enter("Maraudon"); play(20); combat(true); kill(423, "Razorlash", 20); combat(false)
    local id0 = open().id
    local ok = R.split(id0, 2)
    check("open: Split here on the open run: the first part is stored, the run goes on from visit 2", ok and #closed() == 1 and closed()[1].id == id0 and open() and open().id ~= id0
      and open().st == "in" and #open().visits == 1 and open().edited and boss(open(), 423) and boss(open(), 423).kill == 40, open() and boss(open(), 423) and boss(open(), 423).kill)
    check("open: the open run is still a valid open run, its encounters and clocks go on", R.validOpen(open()) and open().copied == true)
    invariants("open split")
    play(30)
    ok = R.join(open().id)
    check("open: Join with previous run on the open run: one run again, still open", ok and #closed() == 0 and open() and open().id == id0 and #open().visits == 2 and boss(open(), 423).kill == 100,
      open() and boss(open(), 423) and boss(open(), 423).kill)
    invariants("open join")
    ok = R.delete(open().id)
    check("open: Delete run on the open run: not stored; inside, the next run begins at once and is the same copy", ok and #closed() == 0 and open() and open().id ~= id0
      and open().open == "split" and #(me().dungeonCopies or {}) == 1 and next(me().dungeonStats or {}) == nil)
    play(90); R.endNow(); play(10)                               -- (over a minute: a run that is kept)
    check("open: End run now stores it and goes on with a new run", #closed() == 1 and open() and open().open == "split")
    leave(); expire()
    invariants("open delete")
    -- join across an evicted neighbour: the kept run, then one that leaves the list, then the run to join
    fresh()
    local c = me()
    local kept = T.runRecord("Maraudon", M.epoch - 50000, 100, { keep = true })
    c.dungeonRuns = { kept }
    for i = 1, R.CAP do c.dungeonRuns[#c.dungeonRuns + 1] = T.runRecord("Uldaman", M.epoch - 40000 + i * 10, 5) end
    c.dungeonRuns[#c.dungeonRuns] = T.runRecord("Maraudon", M.epoch - 30000, 100)
    R.evict(c.dungeonRuns, c)
    local last = c.dungeonRuns[#c.dungeonRuns]
    -- (the list now holds the kept run and 99 others; the Uldaman run just after the kept one left)
    local list = c.dungeonRuns
    table.remove(list, #list)                                    -- the next run after the kept one is the Maraudon run
    for i = #list, 2, -1 do table.remove(list, i) end
    list[2] = last
    local okE, whyE = R.join(last.id)
    check("join: refused across a run that left the list", okE == false and whyE == "evicted" and c.dungeonEvictedTo > kept.endT, whyE)
    -- keep at its limit of 20
    fresh()
    c = me()
    c.dungeonRuns = {}
    for i = 1, 21 do c.dungeonRuns[i] = T.runRecord("Uldaman", M.epoch - 9000 + i * 100, 50) end
    local n = 0
    for i = 1, 20 do if R.setKeep(c.dungeonRuns[i].id, true) then n = n + 1 end end
    local ok21, why21 = R.setKeep(c.dungeonRuns[21].id, true)
    check("keep: 20 runs can be kept, the 21st is refused", n == 20 and R.KEEP_CAP == 20 and ok21 == false and why21 == "cap" and not c.dungeonRuns[21].keep)
    R.setKeep(c.dungeonRuns[1].id, false)
    check("keep: unkeep one and another can be kept", R.setKeep(c.dungeonRuns[21].id, true) == true and R.keptCount(c) == 20)
  end

  -- ── simultaneous bosses: the Zul'Farrak pair, in both orders ────────────────────────────────────────────────
  do
    fresh()
    local function zf(first, second)
      enter("Zul'Farrak", { map = 209 }); play(20); combat(true)
      kill(600, "Antu'sul", 30)
      play(60)
      START(601, "Shadowpriest Sezz'ziz"); START(602, "Nekrum Gutchewer")
      play(40); END(first, "a", 1); play(5); END(second, "b", 1)
      play(50); kill(603, "Gahz'rilla", 30)
      combat(false); play(10); leave(); expire()
      return raw()
    end
    local x = zf(601, 602)
    local y = zf(602, 601)
    local kx, ky = {}, {}
    for _, sp in pairs(R.splits(x)) do kx[sp.prevKey .. ">" .. sp.key] = sp.seg end
    for _, sp in pairs(R.splits(y)) do ky[sp.prevKey .. ">" .. sp.key] = sp.seg end
    -- (Antu'sul pulled at 20 and down at 50; the pair pulled at 110, down at 150 and 155; Gahz'rilla down at 235)
    check("pair: the pair is one split, whichever died first", kx["600>601+602"] == 105 and ky["600>601+602"] == 105 and kx["start>600"] == 30 and kx["601+602>603"] == 80
      and same(kx, ky), tostring(kx["600>601+602"]))
    local s = stats("Zul'Farrak")
    local sig = "600.601.602.603/d1/solo"
    check("pair: both orders are the same route and share its segments", s.routes[sig].n == 2 and s.routes[sig].seg["600>601+602"] ~= nil and R.compare(y, false).sumBest == 215, R.compare(y, false).sumBest)
    check("pair: both bosses of the pair have the same split against the best", R.compare(y, false).vs[601] == 0 and R.compare(y, false).vs[602] == 0)
  end

  -- ── the learned list without the route's last boss: Maraudon's last kill comes after its last boss ─────────
  do
    fresh()
    local M8 = { 422, 423, 424, 425, 426, 427, 428, 429 }
    local function mara(ids)
      local k = {}
      for i, id in ipairs(ids) do k[#k + 1] = { id = id, at = 100 + i * 100 } end
      return clear("Maraudon", 349, 50, k)
    end
    mara(M8); local two = mara(M8)
    local seven = mara({ 422, 423, 424, 425, 426, 427, 428 })     -- Tinkerer Gizlock skipped
    local s = stats("Maraudon")
    check("full: 8 bosses learned from two clears, Gizlock after Princess Theradras among them", #R.learned(s) == 8 and two.done == true and seven.done == nil and s.full == 2)
    check("full: a run without Gizlock reads 7/8", R.views()[3].total == 8 and R.views()[3].bossesDown == 7)
  end

  -- ── difficulty and group size: a solo farm and a five-player clear never share a best ────────────────────────
  do
    fresh()
    local solo = clear("Deadmines", DMAP, 10, K3(100, 200, 300))
    M.groupN = 5; M.fire("GROUP_ROSTER_UPDATE")
    local grp = clear("Deadmines", DMAP, 10, K3(150, 300, 450))
    M.groupN = 1
    local s = stats(DM)
    check("size: a solo run is marked solo (a group run keeps no size), and solo and group runs are two routes", solo.size == 1 and grp.size == nil and s.routes["644.645.646/d1/solo"].best == 290
      and s.routes["644.645.646/d1"].best == 440 and R.isPb(grp), grp.size)
    -- a group that grows inside the run counts at its largest
    M.groupN = 1
    enter("Deadmines", { map = DMAP }); play(20); M.groupN = 3; M.fire("GROUP_ROSTER_UPDATE"); play(20); M.groupN = 2; M.fire("GROUP_ROSTER_UPDATE")
    check("size: the largest group seen inside", open().size == 3)
    M.groupN = 1; leave(); expire()
  end

  -- ── no merge back: a visit 41 minutes after a clear is a run of its own ──────────────────────────────────────
  do
    fresh()
    clear("Sunken Temple", 109, 30, { { id = 1488, at = 200 } })
    play(41 * 60 - R.REENTER - 10)                               -- (clear already waited 20 minutes and a tick)
    enter("Sunken Temple", { map = 109 }); play(60); loot(250); play(30); leave(); expire()
    check("no merge: the visit 41 minutes after the clear, with loot and no boss, is a run of its own", #closed() == 2 and #closed()[2].bosses == 0 and closed()[2].gold.looted == 250
      and closed()[1].visits[2] == nil)
    local rows = me().dungeonCopies
    check("no merge: and an instance of its own, by the 20 minutes", #rows == 2 and rows[1].why == "first" and rows[2].why == "estimate", rows[2] and rows[2].why)
  end

  -- ── instances this hour ──────────────────────────────────────────────────────────────────────────────────────
  do
    fresh()
    local t0 = M.epoch
    -- four runs in 50 minutes (each short and empty: not kept, its instance still counted)
    for i = 1, 4 do
      enter("Deadmines", { map = DMAP }); play(20); leave(); play(5)
      R.endNow()
      if open() then R.close(me(), open(), "left") end
      if i < 4 then play(math.floor((50 * 60 - 4 * 25) / 3)) end
    end
    local h, d = R.copies()
    check("hour: four entries in 50 minutes count 4", h == 4 and d == 4 and #closed() == 0 and M.epoch - t0 <= 50 * 60, h)
    M.epoch = t0 + 61 * 60
    h, d = R.copies()
    check("hour: and 3 at 61 minutes, 4 in the last 24 hours", h == 3 and d == 4, h)
    check("hour: the line says estimate", R.hourLine() == "Instances this hour: 3 (estimate)" .. SEP .. "last 24 hours: 4", R.hourLine())
    R.instancesSlash("limit 5")
    check("hour: a limit the player set shows beside the count", R.hourLine() == "Instances this hour: 3 of 5 (estimate)" .. SEP .. "last 24 hours: 4" and ns.DB.settings.instanceLimit == 5, R.hourLine())
    R.instancesSlash("limit off")
    check("hour: and goes again", ns.DB.settings.instanceLimit == nil and R.limit() == nil)
    said = {}
    R.instancesSlash("")
    check("hour: /eb instances prints the line to the player's own chat", said[1] == R.hourLine(), said[1])
    local tip = R.hourTip()
    check("hour: the hover lists one row per copy with dungeon, character, time and reason", #tip == 4 and tip[1]:find("^The Deadmines  ·  ") ~= nil and tip[4]:find("first entry$") ~= nil, tip[1])
    M.epoch = t0 + 25 * 3600
    check("hour: rows older than 24 hours are dropped", select(2, R.copies()) == 0)
    -- a re-entry adds no copy; raids add none; the door and a provisional run never confirmed add none
    fresh()
    enter("Deadmines", { map = DMAP }); play(30); leave(); play(60); enter("Deadmines", { map = DMAP }); play(30); leave(); expire()
    check("hour: a re-entry adds no copy", #(me().dungeonCopies or {}) == 1 and #closed()[1].visits == 2)
    enter("Molten Core", { type = "raid", map = 409 }); play(200); combat(true); kill(663, "Lucifron", 30); combat(false); leave(); expire()
    check("hour: a raid adds none, and sets no best and no full clear", #(me().dungeonCopies or {}) == 1 and raw().kind == "raid" and not R.isPb(raw()) and raw().done == nil
      and stats("Molten Core").n == 1 and next(stats("Molten Core").routes) == nil and R.compare(raw(), false) == nil)
    fresh()
    walk("The Temple of Atal'Hakkar"); play(60); walk("Swamp of Sorrows"); play(60); walk("The Temple of Atal'Hakkar"); play(60)
    check("hour: the door of Sunken Temple (the name on a continent map) adds none", open() == nil and me().dungeonCopies == nil)
    enter("Shadowfang Keep", { type = "none", map = 33 }); play(300); leave(); expire()
    check("hour: a run the zone name alone opened and nothing confirmed adds none", me().dungeonCopies == nil and (notes().provisional or 0) == 1)
    enter("Shadowfang Keep", { type = "none", map = 33 }); play(30); combat(true); play(10); combat(false); play(15)
    check("hour: once a fight confirms it, the row is written with the run's start", me().dungeonCopies and #me().dungeonCopies == 1 and me().dungeonCopies[1].t == open().t)
    leave(); expire()
    -- the account's other characters count too
    ns.DB.characters["Player-1-000002"] = { name = "Alt", dungeonCopies = { { t = M.epoch - 100, key = "Uldaman", run = "x", why = "first" } } }
    check("hour: the copies of every character of the account are summed", (R.copies()) == 2 and R.hourTip()[1]:find("Alt", 1, true) ~= nil, R.hourTip()[1])
  end

  -- ── the statistics fold into `other` at 80 dungeons; the route cap ──────────────────────────────────────────
  do
    fresh()
    local c = me()
    c.dungeonRuns = {}
    for i = 1, R.STATS_CAP + 1 do
      local r = T.runRecord("Dungeon " .. i, M.epoch - 100000 + i * 100, 100, { firstPull = 10, bosses = { { enc = 9000 + i, name = "B", combat = 5, kill = 50 } }, size = 1, diff = 1 })
      c.dungeonRuns[#c.dungeonRuns + 1] = r
      R.statsAdd(c, r)
    end
    local n, other = 0, c.dungeonStats.other
    for k in pairs(c.dungeonStats) do if k ~= "other" then n = n + 1 end end
    check("fold: 80 dungeons keep statistics of their own, the least recently run is folded into other", n == R.STATS_CAP and other and other.n == 1 and other.folded == 1
      and c.dungeonStats["dungeon 1"] == nil and c.dungeonStats["dungeon 81"] ~= nil and other.routes == nil)
    check("fold: BY DUNGEON lists other last", R.dungeonRows()[#R.dungeonRows()].other == true)
    R.delete(c.dungeonRuns[1].id)
    check("fold: deleting a run of a folded dungeon takes it out of other", c.dungeonStats.other == nil or c.dungeonStats.other.n == 0, c.dungeonStats.other and c.dungeonStats.other.n)
    -- at most 8 routes per dungeon, the least run goes first
    fresh()
    c = me()
    c.dungeonRuns = {}
    for i = 1, R.ROUTE_CAP + 1 do
      local r = T.runRecord("Deadmines", M.epoch - 10000 + i * 100, 100, { firstPull = 10, bosses = { { enc = 700 + i, combat = 5, kill = 50 } }, size = 1 })
      c.dungeonRuns[#c.dungeonRuns + 1] = r
      R.statsAdd(c, r)
    end
    local nr = 0
    for _ in pairs(c.dungeonStats["deadmines"].routes) do nr = nr + 1 end
    check("routes: at most 8 per dungeon", nr == R.ROUTE_CAP and c.dungeonStats["deadmines"].routes["701/solo"] == nil, nr)
  end

  -- ── a possible second copy: a boss killed before the visit is pulled again ───────────────────────────────────
  do
    fresh()
    enter("Deadmines", { map = DMAP }); play(30); combat(true); kill(644, "Rhahk'Zor", 20); combat(false); play(10); leave(); play(300)
    enter("Deadmines", { map = DMAP }); play(30)
    START(644, "Rhahk'Zor")
    check("repull: a boss killed before this visit pulled again flags the visit, and splits nothing", open().repull == 2 and #closed() == 0 and (notes().repull or 0) == 1)
    play(20); END(644, "Rhahk'Zor", 1)
    local v = R.views()[1]
    T.openRun(v)
    local dv = T.dungeonDetail()
    local said2
    for _, fs in ipairs(dv.child.fs) do if fs.shown ~= false and tostring(fs.text):find("^Possibly two runs") then said2 = fs.text end end
    check("repull: the page says possibly two runs and where to split", said2 ~= nil and said2:find("visit 2", 1, true) ~= nil, said2)
    local split
    for _, b in ipairs(dv.actBtns()) do if b.shown ~= false and b.visit == 2 then split = b end end
    check("repull: Split here sits on that visit; two clicks split it", split ~= nil)
    if split then
      split.scripts.OnClick(split)
      check("repull: the first click asks", dv.questionLine == dv.QUESTION.split and #closed() == 0, dv.questionLine)
      for _, b in ipairs(dv.actBtns()) do if b.shown ~= false and b.visit == 2 then split = b end end
      split.scripts.OnClick(split)
      check("repull: the second click splits: the first part stored, the page on it", #closed() == 1 and open() and open().repull == nil and dv.run.id == closed()[1].id)
      local a, b = boss(closed()[1], 644), boss(open(), 644)
      check("repull: the second kill is the open part's own row, the first part keeps its first pull only", b and b.kill ~= nil and b.pulls == 1 and b.combat == 20
        and a and (a.pulls or 1) == 1 and a.combat == 20 and a.r2 == nil, b and tostring(b.kill))
    end
    leave(); expire()
    -- (the first part killed Rhahk'Zor too: two runs on the route "644")
    check("repull: the second part is counted on its route", R.routeOf(raw()) == "644" and stats(DM).routes[R.sigOf(raw())] ~= nil and stats(DM).routes[R.sigOf(raw())].n == 2)
    invariants("repull")
  end

  -- ── the buttons of the page: Keep, Join, Delete with the in-pane question ────────────────────────────────────
  do
    fresh()
    clear("Deadmines", DMAP, 10, K3(100, 200, 300))
    clear("Deadmines", DMAP, 10, K3(100, 200, 300))
    local v = R.views()[2]
    T.openRun(v)
    local dv = T.dungeonDetail()
    local function btn(key) for _, b in ipairs(dv.actBtns()) do if b.shown ~= false and b.key == key then return b end end end
    check("buttons: Keep, Join with previous run and Delete run on a closed run, no End run now", btn("keep") and btn("join") and btn("delete") and btn("end") == nil)
    btn("keep").scripts.OnClick(btn("keep"))
    check("buttons: Keep keeps at once (it is undone with Unkeep)", raw().keep == true and btn("keep").label == "Unkeep")
    btn("delete").scripts.OnClick(btn("delete"))
    check("buttons: Delete asks first, in the page", dv.questionLine == "Delete this run? Its numbers leave the dungeon totals." and btn("delete").label == "Yes, delete" and #closed() == 2)
    btn("join").scripts.OnClick(btn("join"))
    check("buttons: another button asks its own question", dv.questionLine == dv.QUESTION.join and btn("delete").label == "Delete run")
    btn("join").scripts.OnClick(btn("join"))
    check("buttons: the second click joins, the page shows the joined run", #closed() == 1 and dv.run.id == closed()[1].id and closed()[1].edited == true and closed()[1].keep == true)
    btn("join").scripts.OnClick(btn("join")); btn("join").scripts.OnClick(btn("join"))
    check("buttons: a refused join says why", dv.refusedLine == dv.REFUSED.none and #closed() == 1, dv.refusedLine)
    btn("delete").scripts.OnClick(btn("delete")); btn("delete").scripts.OnClick(btn("delete"))
    check("buttons: the second click deletes and goes back to the list", #closed() == 0 and dv.shown == false and stats(DM) == nil)
  end

  -- ── the glance: the pill and the bar text ────────────────────────────────────────────────────────────────────
  do
    fresh()
    clear("Deadmines", DMAP, 10, K3(100, 200, 300))
    clear("Deadmines", DMAP, 10, K3(100, 200, 300))
    check("glance: no run open reads so", G.glance("dungeon"):find("No dungeon run", 1, true) ~= nil)
    enter("Deadmines", { map = DMAP }); play(10); combat(true); play(90); START(644, "Rhahk'Zor"); play(10); END(644, "Rhahk'Zor", 1); play(41)
    -- 151 s on the clock (2m: the glance reads whole minutes), one of the 3 learned bosses, killed 100 s from the first pull where the best took 90
    check("glance: name, the run's clock, bosses of the learned list, the delta at the last kill", R.glance() == "The Deadmines 2m · 1/3 · +0:10" and G.glance("dungeon") == R.glance(), R.glance())
    -- on the pill, the metric holds the pill's size in combat (turned on out of combat, as a player can only do)
    combat(false)
    G.pillOn(true); G.pillSet(1, "dungeon")
    local p = G.pill
    -- (the stub measures every string at 100 px: this pill's text measures 6 px a character, as a real font would)
    if p then p.text.GetUnboundedStringWidth = function(self) return #tostring(self.text or "") * 6 end end
    G.pillUpdate()
    local w0, sz0 = p and p._wSet, p and p._w
    check("glance: the pill shows the run", p and p._text and p._text:find(R.glance(), 1, true) ~= nil and (w0 or 0) > 0, p and p._text)
    combat(true)
    play(600)                                                    -- 12m on the clock: the text changes in combat
    START(645, "Sneed"); play(10); END(645, "Sneed", 1)          -- and a second kill, so 2/3 and a new delta
    G.pillUpdate()
    check("glance: the pill text changes in combat and the pill keeps its size", p._wSet == w0 and p._w == sz0 and p._text:find("12m", 1, true) ~= nil
      and p._text:find("2/3", 1, true) ~= nil, p._text)
    combat(false); G.pillUpdate()
    check("glance: after the fight the pill fits its text again", p._wSet == #p._text * 6 + 2 * ns.UI.SP.S, p._wSet)
    p.text.GetUnboundedStringWidth = nil                         -- (the stub's measure again for the suites after this one)
    G.pillOn(false)
    check("glance: the bar text has a dungeon object", (function() for _, b in ipairs(G.BROKER) do if b[1] == "dungeon" then return true end end return false end)())
    leave(); expire()
  end

  -- ── /eb run with the learned list; stats built from the runs of 0.9.50 at the first load ─────────────────────
  do
    fresh()
    clear("Deadmines", DMAP, 10, K3(100, 200, 300)); clear("Deadmines", DMAP, 10, K3(100, 200, 300))
    said = {}
    R.slash()
    check("/eb run: bosses read against the learned list", said[1] and said[1]:find(", bosses 3/3, ", 1, true) ~= nil, said[1])
    local c = me()
    local runs = deepcopy(c.dungeonRuns)
    for _, r in ipairs(runs) do r.v, r.done, r.size = 1, nil, nil end
    local file = deepcopy(ns.DB)
    file.characters[ME].dungeonRuns, file.characters[ME].dungeonStats = runs, nil
    ns.Recorder.discard(); ns.DB = ns.migrateDB(file)
    T.newLoad(); adv(60); pew(true)
    local s = stats(DM)
    check("load: the statistics are built once from the runs stored since 0.9.50", s and s.n == 2 and s.full == 2 and s.routes["644.645.646/d1"] and s.routes["644.645.646/d1"].n == 2,
      s and s.n)
  end

  -- ── the "Saved to" line's hover: the other characters' lockouts (plan decision 14) ───────────────────────────
  do
    fresh()
    local nowT = GetServerTime()
    ns.DB.characters["Player-1-000002"] = { name = "Alt", lockouts = { { name = "Scholomance", resetAt = nowT + 90000, bosses = 10, down = 4 }, { name = "Gone", resetAt = nowT - 5 } } }
    me().lockouts = { { name = "Stratholme", resetAt = nowT + 3600 } }
    local lv = T.dungeonList()
    local lines = lv.lockTipLines()
    check("lockouts: the hover lists the other characters' lockouts that have not reset, not this one's", #lines == 1 and lines[1] == "Alt: Scholomance 4/10, resets in 1d 1h", lines[1])
    ns.DB.characters["Player-1-000002"] = nil
    check("lockouts: none says so", lv.lockTipLines()[1] == "No other character of this account is saved to an instance.")
  end

  -- ── review round 1 of 0.9.51 ─────────────────────────────────────────────────────────────────────────────────
  -- wings under one name: each wing's clear is a full clear of its wing, and a visit with no kill moves no list
  do
    fresh()
    local SM, SMAP = "Scarlet Monastery", 189
    local LIB = function() return { { id = 6001, at = 100 }, { id = 6002, at = 200 } } end
    local CAT = function() return { { id = 6003, at = 100 }, { id = 6004, at = 200 }, { id = 6005, at = 300 } } end
    local l1 = clear(SM, SMAP, 20, LIB())
    local c1 = clear(SM, SMAP, 20, CAT())
    local l2 = clear(SM, SMAP, 20, LIB())
    local c2 = clear(SM, SMAP, 20, CAT())
    local s = stats(SM)
    check("wings: two Library and two Cathedral clears are four full clears", l1.done and c1.done and l2.done and c2.done and s.full == 4 and s.n == 4, s.full)
    check("wings: each wing has its own learned list", #R.learned(s, l2) == 2 and #R.learned(s, c2) == 3 and #R.clusters(s) == 2)
    local vs = R.views()
    check("wings: BOSSES reads 2/2 on a Library clear and 3/3 on a Cathedral clear", vs[3].total == 2 and vs[3].bossesDown == 2 and vs[4].total == 3, tostring(vs[3].total))
    -- two quest visits with no kill (each with an item, so they are kept) leave the lists where they were
    for _ = 1, 2 do enter(SM, { map = SMAP }); play(70); loot(10); leave(); expire() end
    s = stats(SM)
    check("wings: visits with no kill leave the lists and the full clears as they were", s.n == 6 and #R.learned(s, l2) == 2 and #R.learned(s, c2) == 3 and s.full == 4)
    check("wings: Pace shows once a wing was cleared", R.views()[4].cleared == true)
    invariants("wings")
  end

  -- the "at least half" boundary of the learned list
  do
    fresh()
    clear("Razorfen Kraul", 47, 10, { { id = 1, at = 50 }, { id = 2, at = 100 }, { id = 3, at = 150 } })
    clear("Razorfen Kraul", 47, 10, { { id = 1, at = 50 }, { id = 2, at = 100 } })
    local s = stats("Razorfen Kraul")
    local L = R.learned(s)
    check("half: a boss killed in exactly half of two runs is on the list", L and #L == 3 and L[3] == 3, L and #L)
    clear("Razorfen Kraul", 47, 10, { { id = 1, at = 50 }, { id = 2, at = 100 } })
    clear("Razorfen Kraul", 47, 10, { { id = 1, at = 50 }, { id = 2, at = 100 } })
    L = R.learned(stats("Razorfen Kraul"))
    check("half: a boss killed in one run of four is not", L and #L == 2, L and #L)
  end

  -- a full clear needs every outcome seen
  do
    fresh()
    clear("Deadmines", DMAP, 10, K3(100, 200, 300)); clear("Deadmines", DMAP, 10, K3(100, 200, 300))
    local before = stats(DM).full
    enter("Deadmines", { map = DMAP }); play(10); combat(true)
    kill(644, "Rhahk'Zor", 10); kill(645, "Sneed", 10); kill(646, "Gilnid", 10)
    START(700, "Mr. Smite"); play(5); combat(false); leave(); expire()   -- (left alive while Mr. Smite was up: not seen)
    local r = raw()
    check("full: every learned boss killed and one outcome not seen is no full clear", r.done == nil and R.unknownBoss(r) and stats(DM).full == before and before == 2)
  end

  -- the kill pull's length stays when the boss is pulled again later in the run
  do
    fresh()
    enter("Deadmines", { map = DMAP }); play(20); combat(true)
    kill(644, "Rhahk'Zor", 10); play(20); kill(645, "Sneed", 60); combat(false)
    local keys = {}
    for _, sp in pairs(R.splits(open())) do keys[#keys + 1] = sp.prevKey .. ">" .. sp.key end
    table.sort(keys)
    leave(); play(300); enter("Deadmines", { map = DMAP }); play(20); combat(true)
    START(645, "Sneed"); play(90); END(645, "Sneed", 1); combat(false)
    local after = {}
    for _, sp in pairs(R.splits(open())) do after[#after + 1] = sp.prevKey .. ">" .. sp.key end
    table.sort(after)
    check("dur: a long repull of a killed boss changes neither its pull nor the segment keys", table.concat(keys, " ") == "644>645 start>644" and table.concat(after, " ") == table.concat(keys, " ")
      and boss(open(), 645).dur == 60 and boss(open(), 645).combat == 150, table.concat(after, " "))
    leave(); expire()
    check("dur: the stored record keeps the kill pull's length", boss(raw(), 645).dur == 60 and R.pullOf(boss(raw(), 645)) == boss(raw(), 645).kill - 60)
  end

  -- "Possibly two runs" stays on the closed run, and moves with its visit
  do
    fresh()
    enter("Deadmines", { map = DMAP }); play(30); combat(true); kill(644, "Rhahk'Zor", 20); combat(false); play(10); leave(); play(60)
    enter("Deadmines", { map = DMAP }); play(30); combat(true); play(10); combat(false); leave(); play(60)
    enter("Deadmines", { map = DMAP }); play(30); START(644, "Rhahk'Zor"); play(20); END(644, "Rhahk'Zor", 1); play(10); leave(); expire()
    local r = raw()
    check("repull: the closed run still says which visit to split at", r.repull == 3 and #r.visits == 3)
    T.renderRun(R.view(r, false, true))
    local said
    for _, fs in ipairs(T.dungeonDetail().child.fs) do if fs.shown ~= false and tostring(fs.text):find("^Possibly two runs") then said = fs.text end end
    check("repull: the page of the closed run says possibly two runs", said ~= nil and said:find("visit 3", 1, true) ~= nil, said)
    R.split(r.id, 2)
    check("repull: a split before that visit moves the mark to its new place", closed()[1].repull == nil and closed()[2].repull == 2)
    R.join(closed()[2].id)
    check("repull: and the join puts it back", closed()[1].repull == 3 and #closed() == 1)
    R.split(closed()[1].id, 3)
    check("repull: a split at that visit clears it", closed()[1].repull == nil and closed()[2].repull == nil)
  end

  -- Split and Join correct the instances counted; split and join back is the original count
  do
    fresh()
    clear("Deadmines", DMAP, 20, K3(100, 200, 900, { leaveC = 60 }))
    local d0 = select(2, R.copies())
    R.split(raw().id, 2)
    local d1 = select(2, R.copies())
    local rows = me().dungeonCopies
    check("copies: Split here counts the second part as a new copy", d1 == d0 + 1 and rows[#rows].run == closed()[2].id and rows[#rows].why == "split"
      and R.hourTip()[1]:find("new copy (split by hand)", 1, true) ~= nil, d1)
    R.join(closed()[2].id)
    check("copies: Join with previous run takes it out again: the original count", select(2, R.copies()) == d0 and d0 == 1)
    clear("Deadmines", DMAP, 20, K3(100, 200, 300))
    check("copies: two runs, two copies", select(2, R.copies()) == 2)
    R.join(raw().id)
    check("copies: joining two runs says they were one copy", select(2, R.copies()) == 1 and #closed() == 1)
    check("copies: the reason of a later copy reads as words", R.COPY_WHY.estimate == "new copy by the 20 minute rule")
    -- `first` and `estimate`: a row of this dungeon on this character in the last 24 hours makes the next one an estimate
    fresh()
    local function entry() enter("Deadmines", { map = DMAP }); play(20); combat(true); play(10); combat(false); leave(); expire() end
    entry(); play(23 * 3600 - R.REENTER); entry()
    local L = me().dungeonCopies
    check("copies: a second entry 23 hours later is an estimate", #L == 2 and L[1].why == "first" and L[2].why == "estimate", L[2] and L[2].why)
    play(25 * 3600); entry()
    L = me().dungeonCopies
    check("copies: one more than 24 hours after the last is a first entry again", L[#L].why == "first" and #L == 1, #L)
  end

  -- the newest run deleted: `last` comes back from the runs left
  do
    fresh()
    clear("Deadmines", DMAP, 50, K3(150, 300, 550))
    local mid = clear("Deadmines", DMAP, 50, K3(160, 320, 600))
    local newest = clear("Deadmines", DMAP, 50, K3(170, 340, 650))
    R.delete(newest.id)
    local s = stats(DM)
    check("last: deleting the newest run puts Last run back on the run before", s.last == mid.t and s.routes["644.645.646/d1/solo"].last == mid.t and R.dungeonRows()[1].last == mid.t, s.last)
    local after = deepcopy(me().dungeonStats)
    R.statsRebuild(me(), true)
    check("last: and equals a recompute from the runs left", (same(after, me().dungeonStats)), select(2, same(after, me().dungeonStats)))
  end

  -- delete equals a recompute: a run that held a best segment but not the best; an edited run never takes the best
  do
    fresh()
    local slow = clear("Deadmines", DMAP, 50, K3(70, 400, 800))   -- start>644 in 20 s, 750 s in all
    local best = clear("Deadmines", DMAP, 50, K3(150, 300, 550))  -- 500 s, start>644 in 100
    local sig = "644.645.646/d1/solo"
    check("seg: the slow run holds the fastest first segment", stats(DM).routes[sig].seg["start>644"].id == slow.id and stats(DM).routes[sig].bestId == best.id)
    R.delete(slow.id)
    local held = false
    for _, x in pairs(stats(DM).routes[sig].seg) do if x.id == slow.id then held = true end end
    check("seg: deleting it leaves no segment that names it, the next one takes its place", not held and stats(DM).routes[sig].seg["start>644"].s == 100)
    local after = deepcopy(me().dungeonStats)
    R.statsRebuild(me(), true)
    check("seg: and equals a recompute from the runs left", (same(after, me().dungeonStats)), select(2, same(after, me().dungeonStats)))
    -- an edited run of the same route, much faster: the best of the deleted run must not go to it
    clear("Deadmines", DMAP, 10, { { id = 644, at = 40 } })
    clear("Deadmines", DMAP, 10, { { id = 645, at = 40 }, { id = 646, at = 60 } })
    local ok = R.join(raw().id)
    local J = raw()
    check("seg: the joined run is edited, on the same route and faster", ok and J.edited and R.sigOf(J) == sig and R.measure(J) < 500, R.measure(J))
    R.delete(best.id)
    local r = stats(DM).routes[sig]
    check("seg: the deleted best is not taken from an edited run", r and r.best == nil and r.bestId == nil and r.n == 1, r and r.bestId)
  end

  -- `exact`: only a close through a loading screen into another map
  do
    fresh()
    enter("Deadmines", { map = DMAP }); play(30); combat(true); play(20); combat(false)
    enter("Shadowfang Keep", { map = 33 })
    check("exact: another instance with another map id is an exact end", closed()[1].exact == true and closed()[1].why == "other")
    play(30); combat(true); play(20); combat(false); leave(); expire()
    check("exact: the 20 minutes are an estimate", closed()[2].exact == nil and closed()[2].why == "left")
    enter("Deadmines", { map = DMAP }); play(30); combat(true); play(20); combat(false)
    enter("Wailing Caverns", { map = false })
    check("exact: another name with no map id to compare is not exact", closed()[3].exact == nil and closed()[3].why == "other")
    leave(); expire()
  end

  -- a difficulty of 0 (the client outside an instance) is no difficulty: such a run meets the /d1 runs of its route
  do
    fresh()
    local SFK = "Shadowfang Keep"
    local two = function() return { { id = 1, at = 100 }, { id = 2, at = 200 } } end
    clear(SFK, 33, 50, two())
    M.zone, M.mapType = SFK, 3
    M.inst = { name = SFK, type = "none", diff = 0, mapID = 33 }
    M.fire("ZONE_CHANGED_NEW_AREA")
    check("diff: a run opened by the name alone has difficulty 0", open() and open().diff == 0 and open().prov == true)
    play(30); combat(true)
    M.inst = { name = SFK, type = "party", diff = 1, mapID = 33 }; M.fire("ZONE_CHANGED_NEW_AREA")
    check("diff: once the client says instance the run takes its difficulty", open().diff == 1)
    play(40); START(1, "Rethilgore"); play(10); END(1, "Rethilgore", 1); play(90); START(2, "Razorclaw"); play(10); END(2, "Razorclaw", 1)
    combat(false); play(30); leave(); expire()
    check("diff: and shares the /d1 best", R.sigOf(raw()) == "1.2/d1/solo" and stats(SFK).routes["1.2/d1/solo"].n == 2, R.sigOf(raw()))
    check("diff: a difficulty of 0 adds nothing to the key", R.sigOf({ bosses = { { enc = 5, kill = 10 } }, diff = 0, size = 1 }) == "5/solo")
  end

  -- a run split off by hand begins at its first combat, trash included, like every run
  do
    fresh()
    enter("Deadmines", { map = DMAP }); play(30); combat(true); kill(644, "Rhahk'Zor", 20); combat(false); play(10); leave(); play(60)
    enter("Deadmines", { map = DMAP }); play(20); combat(true); play(30); combat(false); play(40)   -- trash, then the boss
    combat(true); kill(645, "Sneed", 20); combat(false); play(10); leave(); expire()
    local orig = deepcopy(raw())
    check("fc: each visit after the first keeps its first combat", orig.visits[2].fc ~= nil and orig.visits[1].fc == nil)
    R.split(orig.id, 2)
    local B = closed()[2]
    -- (B's first visit: 20 s in, the trash; Sneed pulled 90 s in and down at 110)
    check("fc: the second part's measure starts at its trash, not at its boss", B.firstPull == 20 and R.measure(B) == 90, B.firstPull)
    R.join(B.id)
    local J = deepcopy(closed()[1])
    for _, x in ipairs({ J, orig }) do x.edited, x.pb, x.done = nil, nil, nil end
    check("fc: split then join gives the first combat of each visit back", (same(J, orig)), select(2, same(J, orig)))
  end

  -- "first run" only on the only run of a dungeon
  do
    fresh()
    for _ = 1, 3 do enter("Uldaman", { map = 70 }); play(70); loot(10); leave(); expire() end
    local n = 0
    for _, v in ipairs(R.views()) do T.renderRun(v); if T.dungeonDetail().deltaText ~= "" then n = n + 1 end end
    check("first: runs that cannot set a best do not read first run", n == 0, n)
    fresh()
    enter("Uldaman", { map = 70 }); play(70); loot(10); leave(); expire()
    T.renderRun(R.views()[1])
    check("first: the only run of a dungeon does", T.dungeonDetail().deltaText == "first run here")
    clear("Uldaman", 70, 10, { { id = 9, at = 50 } })
    T.renderRun(R.views()[2])
    check("first: the first run of a new route in a dungeon run before reads best", T.dungeonDetail().deltaText == "best", T.dungeonDetail().deltaText)
  end

  -- the two-click question ends with its 8 seconds, on the page too
  do
    fresh()
    clear("Deadmines", DMAP, 10, K3(100, 200, 300))
    T.openRun(R.views()[1])
    local dv = T.dungeonDetail()
    local function btn(key) for _, b in ipairs(dv.actBtns()) do if b.shown ~= false and b.key == key then return b end end end
    M.timers = {}
    btn("delete").scripts.OnClick(btn("delete"))
    check("ask: the question shows", dv.questionLine ~= nil and btn("delete").label == "Yes, delete")
    adv(9); M.runTimers()
    check("ask: after 8 seconds the button and the question are back to rest", dv.questionLine == nil and btn("delete").label == "Delete run" and #closed() == 1)
    dv:Hide()
  end

  -- BY DUNGEON follows the tabs; a click on a row shows that dungeon's runs
  do
    fresh()
    clear("Deadmines", DMAP, 10, K3(100, 200, 300))
    enter("Molten Core", { type = "raid", map = 409 }); play(200); combat(true); kill(663, "Lucifron", 30); combat(false); leave(); expire()
    local lv = T.dungeonList()
    lv.setView("dungeons")
    lv.tabs.select("raid")
    check("filter: the Raids tab lists the raids only", #lv.dshown == 1 and lv.dshown[1].name == "Molten Core")
    lv.tabs.select("party")
    check("filter: the Dungeons tab lists the dungeons only", #lv.dshown == 1 and lv.dshown[1].name == DM)
    lv.tabs.select("all")
    local mc
    for _, r in ipairs(lv.dtbl.rows) do if r.shown ~= false and r.drow and r.drow.name == "Molten Core" then mc = r end end
    lv.st.kind = "party"                                          -- (a tab that does not hold the clicked row)
    mc:GetScript("OnClick")(mc, "LeftButton")
    check("filter: a click on a raid shows its runs, on the Raids tab", lv.st.view == "runs" and lv.st.kind == "raid" and #lv.shown == 1, #lv.shown)
    lv.pickInst(nil); lv.tabs.select("all"); lv.setView("runs")
  end

  -- an evicted best stays across a /reload, and the statistics are never built again once they exist
  do
    fresh()
    local best = clear("Deadmines", DMAP, 50, K3(150, 300, 550))
    local sig = "644.645.646/d1/solo"
    local c = me()
    for i = 1, R.CAP - 1 do c.dungeonRuns[#c.dungeonRuns + 1] = T.runRecord("Uldaman", M.epoch + i, 90) end
    clear("Deadmines", DMAP, 50, K3(160, 320, 600))
    check("reload: the best run left the list", c.dungeonRuns[1].id ~= best.id and stats(DM).routes[sig].bestId == best.id)
    local held = false
    for _, x in pairs(stats(DM).routes[sig].seg) do if x.id == best.id then held = true end end
    check("reload: its best segments keep their seconds, not its id", not held and stats(DM).routes[sig].seg["start>644"].s == 100)
    stats(DM).probe = 7
    E.reloadAsked(); M.fire("PLAYER_LOGOUT")
    local file = deepcopy(ns.DB)
    ns.Recorder.discard(); ns.DB = ns.migrateDB(file)
    G._tickAt = nil; T.newLoad(); adv(60); pew(true)
    check("reload: the evicted best is still the best after a reload", stats(DM).routes[sig].best == 500 and stats(DM).routes[sig].bestId == best.id)
    check("reload: the statistics were not built again", stats(DM).probe == 7)
    stats(DM).probe = nil
  end

  -- the statistics have caps of their own: bosses per dungeon, segments per route
  do
    fresh()
    local c = me()
    c.dungeonRuns = {}
    for i = 1, R.STATS_BOSS_CAP + 6 do
      local r = T.runRecord("Blackrock Depths", M.epoch - 100000 + i * 100, 100, { firstPull = 10, size = 1, diff = 1, bosses = { { enc = 3000 + i, name = "B", combat = 5, kill = 50 } } })
      c.dungeonRuns[#c.dungeonRuns + 1] = r; R.statsAdd(c, r)
    end
    local nb = 0
    for _ in pairs(stats("Blackrock Depths").bosses) do nb = nb + 1 end
    check("caps: at most Runs.STATS_BOSS_CAP bosses per dungeon", nb == R.STATS_BOSS_CAP, nb)
    -- six orders of the same three kills on one route: at most its 3 bosses plus Runs.SEG_EXTRA segments
    fresh()
    c = me()
    c.dungeonRuns = {}
    local orders = { { 1, 2, 3 }, { 1, 3, 2 }, { 2, 1, 3 }, { 2, 3, 1 }, { 3, 1, 2 }, { 3, 2, 1 } }
    for i, o in ipairs(orders) do
      local b = {}
      for j, e in ipairs(o) do b[j] = { enc = e, combat = 5, kill = 50 * j } end
      local r = T.runRecord("Uldaman", M.epoch - 10000 + i * 100, 200, { firstPull = 10, size = 1, diff = 1, bosses = b })
      c.dungeonRuns[#c.dungeonRuns + 1] = r; R.statsAdd(c, r)
    end
    local ns0 = 0
    for _ in pairs(stats("Uldaman").routes["1.2.3/d1/solo"].seg) do ns0 = ns0 + 1 end
    check("caps: a route keeps at most its bosses plus 2 best segments", ns0 == 3 + R.SEG_EXTRA, ns0)
  end

  -- ── review round 2: Split here at a repull, taking a run out of entries it was never in, the light read ───────
  -- a boss killed in visit 1 and pulled and killed again in visit 2: Split here at visit 2 gives the second kill to
  -- the second part, and the join gives the original record back
  do
    fresh()
    enter("Deadmines", { map = DMAP }); play(30); combat(true); kill(644, "Rhahk'Zor", 20); play(10); kill(645, "Sneed", 30); combat(false); play(10); leave(); play(300)
    enter("Deadmines", { map = DMAP }); play(30); combat(true)
    START(644, "Rhahk'Zor"); play(15); die(); play(10); END(644, "Rhahk'Zor", 0); rise(); play(20)   -- (a wipe in the second copy)
    kill(644, "Rhahk'Zor", 25); combat(false); play(10); leave(); expire()
    local orig = deepcopy(raw())
    local b0 = boss(orig, 644)
    -- (the row: 3 pulls, 20 + 25 + 25 = 70 s, one wipe; the second copy's part: 2 pulls, 50 s, the wipe and its kill)
    check("repull2: the row keeps the second copy's part apart, the sums of both on the row", orig.repull == 2 and b0.pulls == 3 and b0.combat == 70 and b0.wipes == 1
      and type(b0.r2) == "table" and b0.r2.pulls == 2 and b0.r2.combat == 50 and b0.r2.wipes == 1 and b0.r2.kill ~= nil and b0.r2.kill > b0.kill and b0.kill ~= nil,
      b0 and (tostring(b0.pulls) .. " " .. tostring(b0.combat)))
    R.split(orig.id, 2)
    local A, B = closed()[1], closed()[2]
    local a, b = boss(A, 644), boss(B, 644)
    local cB = orig.visits[1].secs + (orig.visits[2].gg or 0)
    check("repull2: the first part keeps its own pull and kill only", a and (a.pulls or 1) == 1 and a.combat == 20 and a.wipes == nil and a.r2 == nil and a.kill == b0.kill, a and a.combat)
    check("repull2: the second part has the second kill, its wipe and its pulls, on its own clock", b and b.pulls == 2 and b.combat == 50 and b.wipes == 1 and b.r2 == nil
      and b.kill == b0.r2.kill - cB and R.pullOf(b) >= 0, b and b.kill)
    check("repull2: the second part has a route and is counted on it", R.routeOf(B) == "644" and stats(DM).routes[R.sigOf(B)] ~= nil and stats(DM).routes[R.sigOf(B)].n == 1
      and R.routeOf(A) == "644.645", R.routeOf(B))
    check("repull2: the second part's boss seconds have their boss behind them", (B.secs.boss or 0) == 50 and (A.secs.boss or 0) == 50, tostring(B.secs.boss) .. " " .. tostring(A.secs.boss))
    invariants("repull2 split")
    R.join(B.id)
    local J = deepcopy(closed()[1])
    -- (the mark "possibly two runs" goes with Split here at its visit, and a join by hand does not bring it back)
    for _, x in ipairs({ J, orig }) do x.edited, x.pb, x.done, x.repull = nil, nil, nil, nil end
    check("repull2: split then join gives the original record back", #closed() == 1 and (same(J, orig)), select(2, same(J, orig)))
  end
  -- two runs joined, a boss killed in the first and pulled again in the second: the kill pull stays the first's
  do
    fresh()
    enter("Deadmines", { map = DMAP }); play(20); combat(true)
    kill(644, "Rhahk'Zor", 10); play(20); kill(645, "Sneed", 60); combat(false); play(10); leave(); expire()
    local A = deepcopy(raw())
    local keysA = {}
    for _, sp in pairs(R.splits(A)) do keysA[#keysA + 1] = sp.prevKey .. ">" .. sp.key end
    table.sort(keysA)
    enter("Deadmines", { map = DMAP }); play(20); combat(true); START(645, "Sneed"); play(90); END(645, "Sneed", 1); combat(false); play(10); leave(); expire()
    local ok = R.join(raw().id)
    local J = closed()[1]
    local x = boss(J, 645)
    local keysJ = {}
    for _, sp in pairs(R.splits(J)) do keysJ[#keysJ + 1] = sp.prevKey .. ">" .. sp.key end
    table.sort(keysJ)
    check("join: a boss killed in the first run keeps its kill pull's length and start", ok and #closed() == 1 and x.dur == 60 and x.kill == boss(A, 645).kill
      and R.pullOf(x) == boss(A, 645).kill - 60 and x.combat == 150 and x.pulls == 2, x and x.dur)
    check("join: the segment keys are the first run's", table.concat(keysJ, " ") == table.concat(keysA, " ") and table.concat(keysA, " ") == "644>645 start>644", table.concat(keysJ, " "))
    check("join: the later pull is the second copy's part of the row", type(x.r2) == "table" and x.r2.kill ~= nil and x.r2.combat == 90)
  end

  -- a run taken out subtracts only from what it was counted in: a route dropped at the cap and made again
  do
    fresh()
    local c = me()
    c.dungeonRuns = {}
    local function add(t, enc, kill)
      local r = T.runRecord("Deadmines", t, 200, { firstPull = 10, bosses = { { enc = enc, combat = 5, kill = kill or 50 } }, size = 1 })
      c.dungeonRuns[#c.dungeonRuns + 1] = r; R.statsAdd(c, r)
      return r
    end
    -- the most run route first: three runs of 700, then eight routes of one run each
    for i = 1, 3 do add(M.epoch - 20000 + i * 100, 700, 60 + i) end
    local old = add(M.epoch - 19000, 701)
    for i = 2, R.ROUTE_CAP do add(M.epoch - 19000 + i * 100, 700 + i) end
    local RT = stats("Deadmines").routes
    check("routes: the least run route goes first, never the most run one", RT["700/solo"] and RT["700/solo"].n == 3 and RT["700/solo"].best == 51 and RT["701/solo"] == nil
      and RT["708/solo"] ~= nil and old.notIn and old.notIn.route == true, RT["700/solo"] and RT["700/solo"].n)
    -- route 701 again, by a later run with its own best; the old run of 701 deleted
    local new = add(M.epoch - 10000, 701, 30)
    check("routes: a route made again holds the later run", stats("Deadmines").routes["701/solo"].bestId == new.id and stats("Deadmines").routes["702/solo"] == nil)
    R.delete(old.id)
    local r = stats("Deadmines").routes["701/solo"]
    check("routes: deleting the run of the dropped route leaves the route made again", r and r.n == 1 and r.best == 20 and r.bestId == new.id and r.k == 1 and r.tot == 20, r and r.n)
    local after = deepcopy(me().dungeonStats)
    R.statsRebuild(me(), true)
    check("routes: and equals a recompute from the runs left", (same(after, me().dungeonStats)), select(2, same(after, me().dungeonStats)))
  end
  -- the same for a boss skipped at the boss cap and made later by another run
  do
    fresh()
    local c = me()
    c.dungeonRuns = {}
    local function add(t, enc)
      local r = T.runRecord("Blackrock Depths", t, 100, { firstPull = 10, size = 1, diff = 1, bosses = { { enc = enc, name = "B", combat = 5, kill = 50 } } })
      c.dungeonRuns[#c.dungeonRuns + 1] = r; R.statsAdd(c, r)
      return r
    end
    for i = 1, R.STATS_BOSS_CAP do add(M.epoch - 100000 + i * 100, 3000 + i) end
    local skipped = add(M.epoch - 50000, 3999)
    check("bosscap: a boss past the cap is not counted, and the run says so", stats("Blackrock Depths").bosses[3999] == nil and skipped.notIn and skipped.notIn.bosses and skipped.notIn.bosses[3999] == true)
    R.delete(c.dungeonRuns[1].id)                                 -- (boss 3001's only run: its row goes, a place is free)
    add(M.epoch - 40000, 3999)
    check("bosscap: a later run makes the row", stats("Blackrock Depths").bosses[3999] and stats("Blackrock Depths").bosses[3999].seenIn == 1)
    R.delete(skipped.id)
    local x = stats("Blackrock Depths").bosses[3999]
    check("bosscap: deleting the run that was never counted in it leaves the row", x and x.seenIn == 1 and x.kills == 1, x and x.seenIn)
    local after = deepcopy(me().dungeonStats)
    R.statsRebuild(me(), true)
    check("bosscap: and equals a recompute from the runs left", (same(after, me().dungeonStats)), select(2, same(after, me().dungeonStats)))
  end
  -- and for a dungeon folded into `other` and run again later
  do
    fresh()
    local c = me()
    c.dungeonRuns = {}
    for i = 1, R.STATS_CAP + 1 do
      local r = T.runRecord("Dungeon " .. i, M.epoch - 100000 + i * 100, 100, { firstPull = 10, bosses = { { enc = 9000 + i, name = "B", combat = 5, kill = 50 } }, size = 1, diff = 1 })
      c.dungeonRuns[#c.dungeonRuns + 1] = r; R.statsAdd(c, r)
    end
    local first = c.dungeonRuns[1]
    check("fold: the folded dungeon's run says it is counted in other", first.notIn and first.notIn.dungeon == true and c.dungeonStats.other.n == 1)
    local again = T.runRecord("Dungeon 1", M.epoch - 1000, 300, { firstPull = 10, bosses = { { enc = 9001, name = "B", combat = 5, kill = 70 } }, size = 1, diff = 1 })
    c.dungeonRuns[#c.dungeonRuns + 1] = again; R.statsAdd(c, again)
    check("fold: run again, the dungeon has statistics of its own again (and the next least recent folds)", c.dungeonStats["dungeon 1"] and c.dungeonStats["dungeon 1"].n == 1
      and c.dungeonStats.other.n == 2 and c.dungeonStats["dungeon 2"] == nil)
    R.delete(first.id)
    local s1 = c.dungeonStats["dungeon 1"]
    check("fold: deleting the old run takes it out of other, not out of the dungeon run again", s1 and s1.n == 1 and s1.secs == 300 and s1.routes["9001/d1/solo"] and s1.routes["9001/d1/solo"].best == 60
      and c.dungeonStats.other.n == 1 and c.dungeonStats.other.secs == 100, s1 and s1.n)
  end

  -- BY DUNGEON: the sums and the rates worked out by hand
  do
    fresh()
    local c = me()
    c.dungeonRuns = {}
    local function secs(inside, active) return { inside = inside, ghost = 0, outside = 0, offline = 0, active = active, combat = 0, boss = 0 } end
    -- run 1: 600 s inside, 400 active, 2 own deaths (and 1 of the party), 3000 XP, 1g 20s looted and 30s from quests
    local r1 = T.runRecord("Razorfen Kraul", M.epoch - 5000, 600, { firstPull = 10, size = 1, diff = 1, secs = secs(600, 400), nDeaths = { me = 2, party = 1 },
      xp = { gain = 3000 }, gold = { looted = 12000, quests = 3000, lootValue = 5000, items = 4 }, bosses = { { enc = 1, combat = 5, kill = 50, wipes = 1 } } })
    -- run 2: 900 s inside, 500 active, 1 own death, 2000 XP, 60s looted
    local r2 = T.runRecord("Razorfen Kraul", M.epoch - 3000, 900, { firstPull = 10, size = 1, diff = 1, secs = secs(900, 500), nDeaths = { me = 1 },
      xp = { gain = 2000 }, gold = { looted = 6000 }, bosses = { { enc = 1, combat = 5, kill = 70 } } })
    -- a dungeon with 200 active seconds: under Runs.RATE_WARM, no rate yet
    local r3 = T.runRecord("Wailing Caverns", M.epoch - 2000, 250, { firstPull = 10, size = 1, diff = 1, secs = secs(250, 200), nDeaths = { me = 1 },
      xp = { gain = 900 }, gold = { looted = 900 }, bosses = { { enc = 2, combat = 5, kill = 50 } } })
    for _, r in ipairs({ r1, r2, r3 }) do c.dungeonRuns[#c.dungeonRuns + 1] = r; R.statsAdd(c, r) end
    local s = stats("Razorfen Kraul")
    check("bydungeon: the sums of the dungeon", s.n == 2 and s.deaths == 3 and s.xp == 5000 and s.looted == 18000 and s.quests == 3000 and s.lootValue == 5000
      and s.active == 900 and s.secs == 1500 and s.wipes == 1, ("%s %s %s %s %s"):format(s.deaths, s.xp, s.looted, s.active, s.secs))
    local rows = R.dungeonRows()
    local rk, wc
    for _, d in ipairs(rows) do if d.name == "Razorfen Kraul" then rk = d elseif d.name == "Wailing Caverns" then wc = d end end
    -- (coin: (18000 + 3000) * 3600 / 900 = 84000 an hour; XP: 5000 * 3600 / 900 = 20000; deaths 3 / 2 runs; best 40 s
    -- and average (40 + 60) / 2 = 50 s, first pull to last kill)
    check("bydungeon: coin and XP per active hour, deaths per run", rk and rk.coinPerHour == 84000 and rk.xpPerHour == 20000 and rk.deathsPerRun == 1.5
      and rk.best == 40 and rk.avg == 50, rk and rk.coinPerHour)
    check("bydungeon: under 5 active minutes a dungeon has no rate", wc and wc.coinPerHour == nil and wc.xpPerHour == nil and wc.deathsPerRun == 1)
    local lv = T.dungeonList()
    lv.setView("dungeons")
    local cells, rowOf = {}, {}
    for _, r in ipairs(lv.dtbl.rows) do if r.shown ~= false and r.drow then cells[r.drow.name] = r.c; rowOf[r.drow.name] = r end end
    local k, w = cells["Razorfen Kraul"], cells["Wailing Caverns"]
    check("bydungeon: the cells read the rates and the deaths", k and k.xp.text == "20,000" and k.dpr.text == "1.5" and k.coin.text ~= "-" and k.best.text == R.fmtDur(40) and k.avg.text == R.fmtDur(50), k and k.xp.text)
    check("bydungeon: a dungeon under 5 active minutes reads - for coin and XP, its deaths per run as a number", w and w.coin.text == "-" and w.xp.text == "-" and w.dpr.text == "1.0", w and w.coin.text)
    local tl = {}
    local tr = rowOf["Razorfen Kraul"]
    if tr and tr.GetScript and tr:GetScript("OnEnter") then
      tr:GetScript("OnEnter")(tr)
      for _, l in ipairs(GameTooltip.lines or {}) do tl[#tl + 1] = tostring(l) end
      if tr:GetScript("OnLeave") then tr:GetScript("OnLeave")(tr) end
    end
    check("bydungeon: the row's hover says what Best and Average measure", table.concat(tl, "|"):find("first pull to last boss kill", 1, true) ~= nil, table.concat(tl, "|"))
    lv.setView("runs")
  end

  -- the segment cap keeps the newest runs' segments, and never the one a run just set
  do
    fresh()
    local c = me()
    c.dungeonRuns = {}
    local orders = { { 1, 2, 3 }, { 1, 3, 2 }, { 2, 1, 3 }, { 2, 3, 1 }, { 3, 1, 2 }, { 3, 2, 1 } }
    local ids = {}
    local function run(t, o)
      local b = {}
      for j, e in ipairs(o) do b[j] = { enc = e, combat = 5, kill = 50 * j } end
      local r = T.runRecord("Uldaman", t, 200, { firstPull = 10, size = 1, diff = 1, bosses = b })
      c.dungeonRuns[#c.dungeonRuns + 1] = r; R.statsAdd(c, r)
      return r
    end
    for i, o in ipairs(orders) do ids[i] = run(M.epoch - 10000 + i * 100, o).id end
    local function segs()
      local out = {}
      for k, x in pairs(stats("Uldaman").routes["1.2.3/d1/solo"].seg) do
        local who = "?"
        for i, id in pairs(ids) do if x.id == id then who = tostring(i) end end
        out[#out + 1] = k .. "=" .. who
      end
      table.sort(out)
      return table.concat(out, " ")
    end
    -- (worked out by hand: every start is 40 s, every later segment 50 s; a tie keeps the older entry, and past the
    -- cap of 5 the oldest run's entries go first, the lower key first among one run's)
    check("segcap: the segments of the newest orders stay, those of the oldest runs go", segs() == "1>2=5 2>1=6 3>1=4 3>2=6 start>3=5", segs())
    -- a run with an older start (a join keeps the first run's id) adds two segments over the cap: they stay
    ids[7] = run(M.epoch - 20000, { 2, 3, 1 }).id
    check("segcap: a segment the run just set is never dropped in the same call", segs() == "2>1=6 2>3=7 3>2=6 start>2=7 start>3=5", segs())
  end

  -- the copy rows: the cap, a raid split, a split of a run older than a day
  do
    fresh()
    local c = me()
    for i = 1, R.COPY_CAP + 1 do R.copyCheck(c, { t = M.epoch - 5000 + i, inst = "Dungeon " .. i, id = "copy-" .. i, kind = "party" }) end
    check("copies: at most Runs.COPY_CAP rows, the oldest goes", #c.dungeonCopies == R.COPY_CAP and c.dungeonCopies[1].run == "copy-2" and c.dungeonCopies[R.COPY_CAP].run == "copy-" .. (R.COPY_CAP + 1))
    fresh()
    c = me()
    enter("Molten Core", { type = "raid", map = 409 }); play(200); combat(true); kill(663, "Lucifron", 30); combat(false); leave(); play(60)
    enter("Molten Core", { type = "raid", map = 409 }); play(100); combat(true); kill(664, "Magmadar", 30); combat(false); leave(); expire()
    local n0 = #(c.dungeonCopies or {})
    local okR = R.split(raw().id, 2)
    check("copies: Split here on a raid adds no row", okR and #closed() == 2 and #(c.dungeonCopies or {}) == n0 and n0 == 0, #(c.dungeonCopies or {}))
    fresh()
    c = me()
    clear("Deadmines", DMAP, 20, K3(100, 200, 900, { leaveC = 60 }))
    adv(R.COPY_WINDOW + 3600)
    local before = #R.copiesOf(c, M.epoch)
    local okO = R.split(raw().id, 2)
    -- (the rows as stored, not read through Runs.copiesOf, which would let an old row go again at once)
    check("copies: Split here on a run older than a day adds no row", okO and #closed() == 2 and #(c.dungeonCopies or {}) == before and before == 0, #(c.dungeonCopies or {}))
  end

  -- the Fights list reads the runs lightly, and only while it is on screen; the Dungeons list keeps what it read
  do
    fresh()
    clear("Deadmines", DMAP, 10, K3(100, 200, 300))
    clear("Deadmines", DMAP, 10, K3(90, 200, 280))
    local lite = ns.DungeonRuns()
    check("light: the Fights list's read has the run headers' fields, nothing from the statistics", #lite == 2 and lite[1].rec ~= nil and lite[1].bossesDown == 3 and lite[1].name == DM
      and lite[1].startT ~= nil and lite[1].cmp == nil and lite[1].total == nil and lite[1].splits == nil)
    local v1, v2 = R.views(), R.views()
    check("cache: the full read keeps the comparison while nothing changed", v1[1].cmp ~= nil and v1[1].cmp == v2[1].cmp and v1[2].cmp == v2[2].cmp and v1[1].total == 3)
    local hov = table.concat(T.dungeonList().tipLines(v1[1]), "|")
    -- (run 1: 290 s from its first pull to its last kill, the best 270 s)
    check("length: the hover of LENGTH says the delta is first pull to last kill, with this run's value", hov:find("Against the best: first pull to last boss kill, 4m 50s here, best 4m 30s", 1, true) ~= nil, hov)
    clear("Deadmines", DMAP, 10, K3(80, 150, 200))
    local v3 = R.views()
    check("cache: and reads it again once the statistics change", v3[1].cmp ~= v1[1].cmp and v3[1].cmp.delta == R.measure(closed()[1]) - 190, v3[1].cmp.delta)
    -- the Fights pane opened once, then the window closed: its 2 s ticker draws nothing
    local root = _G.EverbuffFrame
    local wasShown = root and root:IsShown()
    ns.UI.Open("Combat", "fights")
    root = _G.EverbuffFrame
    local real0, calls = ns.DungeonRuns, 0
    ns.DungeonRuns = function() calls = calls + 1; return real0() end
    M.tick()
    local onScreen = calls
    if root:IsShown() then ns.UI.Toggle() end
    calls = 0
    M.tick(); M.tick()
    check("ticker: the Fights list is drawn again on screen, never with the window closed", onScreen >= 1 and calls == 0, onScreen .. " " .. calls)
    ns.DungeonRuns = real0
    if wasShown and not root:IsShown() then ns.UI.Toggle() end
  end

  -- ── the contract of the new keys ─────────────────────────────────────────────────────────────────────────────
  do
    fresh()
    clear("Deadmines", DMAP, 10, K3(100, 200, 300)); clear("Deadmines", DMAP, 10, K3(90, 200, 300))
    local function typed(t, spec, where)
      if type(t) ~= "table" then return where .. " is a " .. type(t) end
      for k, x in pairs(t) do
        local want = spec[k]
        if not want then return where .. "." .. tostring(k) .. " is not in the contract" end
        if type(x) ~= want then return where .. "." .. tostring(k) .. " is a " .. type(x) end
      end
    end
    local STAT = { inst = "string", kind = "string", n = "number", full = "number", secs = "number", active = "number", deaths = "number", wipes = "number", xp = "number",
      looted = "number", quests = "number", lootValue = "number", last = "number", bosses = "table", routes = "table", folded = "number" }
    local why
    for key, s in pairs(me().dungeonStats) do
      why = why or (type(key) ~= "string" and "stats key") or typed(s, STAT, "stats")
      for enc, b in pairs(s.bosses or {}) do why = why or (type(enc) ~= "number" and "boss key") or typed(b, { name = "string", kills = "number", wipes = "number", seenIn = "number" }, "stats.bosses") end
      for sig, r in pairs(s.routes or {}) do
        why = why or (type(sig) ~= "string" and "route key") or typed(r, { n = "number", last = "number", best = "number", bestId = "string", bestAt = "number", splits = "table", seg = "table", tot = "number", k = "number" }, "route")
        for enc, x in pairs(r.splits or {}) do if type(enc) ~= "number" or type(x) ~= "number" then why = why or "splits" end end
        for k, x in pairs(r.seg or {}) do why = why or (type(k) ~= "string" and "seg key") or typed(x, { s = "number", id = "string" }, "seg") end
      end
    end
    for _, r in ipairs(me().dungeonCopies or {}) do why = why or typed(r, { t = "number", key = "string", run = "string", why = "string" }, "copy") end
    check("contract: dungeonStats and dungeonCopies, every key typed", why == nil and me().dungeonStats and me().dungeonCopies, why)
  end

  check("the invariants were asked after the scenarios", nInv >= 9, nInv)
  check("no handler threw anywhere in this suite", errs() == main.errors and R._err == nil, M.errors[#M.errors] or R._err)

  -- ── the suite's save file and client back in place ──────────────────────────────────────────────────────────
  M.units, M.groupN, M.inCombat, M.dead = main.units, main.groupN, main.inCombat, main.dead
  M.xp, M.xpmax, M.level = main.xp, main.xpmax, main.level
  ns.msg = real.msg
  M.timers = {}
  ns.Recorder.discard()
  ns.DB = main.db
  G._held, G._baseWait, G._flushTimer, G._tickAt, G._afk, G._placeErr = nil, nil, nil, nil, nil, nil
  M.zone, M.inst, M.uiMap, M.mapType = main.zone, main.inst, main.uiMap, main.mapType
  M.epoch, M.now, M.money = main.epoch, M.now + 100, main.money
  for _, e in ipairs({ "MERCHANT_CLOSED", "MAIL_CLOSED", "AUCTION_HOUSE_CLOSED", "TRAINER_CLOSED", "TRADE_CLOSED" }) do M.fire(e) end
  T.newLoad()
  M.fire("PLAYER_ENTERING_WORLD", false, true); M.runTimers()
  print = realPrint
  P.check("bests: the suite's save file is back, its session resumed", ns.DB == main.db and ns.Recorder.current() ~= nil)
end
