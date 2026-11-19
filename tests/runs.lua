-- The durable dungeon run (0.9.50, everbuff-wow-addon #51; Everbuff/Runs.lua).
-- Loaded by tests/run_tests.lua after tests/guards.lua:
--   dofile("tests/runs.lua")({ check = check, M = M, ns = ns })
-- Runs on a save file of its own (the suite's is put aside and put back), with the clock in the test's hands. Every
-- scenario plays the real events into the real handlers and ends on the invariants: the four clocks sum to the wall
-- time, the run's sums are the sums of its visits, and at most one run is open. Fixtures from the founder's save of
-- 2026-11-19 are named where they are used (the Maraudon run of 11-18, the Avatar of Hakkar, the Zul'Farrak pair,
-- the halls outside Sunken Temple, the group shares booked as mail).
return function(P)
  local M, ns = P.M, P.ns
  local E, G, R, T = ns.Emitter, ns.Gold, ns.Runs, ns._test
  local ME = "Player-1-000001"
  local fmt = ns.fmtMoney
  local SEP = "  ·  "
  local realPrint = print
  local function check(name, cond, detail) local mine = print; print = realPrint; P.check("runs: " .. name, cond, detail); print = mine end
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

  -- ── the suite's state, put aside ──────────────────────────────────────────────────────────────────────────────
  local main = { db = ns.DB, epoch = M.epoch, now = M.now, money = M.money, zone = M.zone, inst = M.inst, uiMap = M.uiMap, mapType = M.mapType,
    groupN = M.groupN, units = M.units, inCombat = M.inCombat, dead = M.dead, errors = #M.errors, xp = M.xp, xpmax = M.xpmax, level = M.level }
  local real = { msg = ns.msg, guid = _G.UnitGUID, send = rawget(_G, "SendChatMessage"), sell = M.sellPrice }
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
  -- A closed record as a reader takes it: what Runs.lean left out (a 0, an empty block) read as 0 or empty, and the
  -- wall time as the sum of the four clocks. `raw` is the stored record itself.
  local function norm(r)
    if type(r) ~= "table" then return r end
    local n = deepcopy(r)
    for _, k in ipairs(R.SECS) do n.secs[k] = n.secs[k] or 0 end
    n.secs.wall = n.secs.inside + n.secs.ghost + n.secs.outside + n.secs.offline
    n.nDeaths, n.deaths, n.hidden, n.gold = n.nDeaths or {}, n.deaths or {}, n.hidden or {}, n.gold or {}
    for _, k in ipairs({ "me", "party" }) do n.nDeaths[k] = n.nDeaths[k] or 0 end
    for _, k in ipairs({ "xp", "rep", "loot" }) do n.hidden[k] = n.hidden[k] or 0 end
    for _, k in ipairs({ "looted", "quests", "lootValue", "items", "purse" }) do n.gold[k] = n.gold[k] or 0 end
    for _, b in ipairs(n.bosses) do b.pulls = b.pulls or 1 end
    return n
  end
  local function raw() local l = closed(); return l[#l] end
  local function last() return norm(raw()) end
  local function notes() return (ns.DB.settings.selftest and ns.DB.settings.selftest.runs) or {} end
  local function adv(s) M.epoch, M.now = M.epoch + s, M.now + s end
  -- time passes with both 10 second ticks running (the run's and the gold tick)
  local function play(sec)
    for _ = 1, math.floor(sec / 10) do adv(10); R.tick(); G.tick() end
    local rest = sec % 10
    if rest > 0 then adv(rest) end
  end
  local function pew(login, reload) M.fire("PLAYER_ENTERING_WORLD", login and true or false, reload and true or false); M.runTimers() end
  local function fresh()
    -- (a boss pulled with no combat opens a fight that only the end of combat closes: none stays open between scenarios)
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
  -- a dungeon the client names an instance (Maraudon on WoW Forever: type "party", map 349)
  -- (`place`: the client's answers only, no event yet)
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
  -- the open world under a zone name (no loading screen): the halls in front of a portal, or anywhere else
  local function walk(zone, map)
    M.zone, M.mapType = zone, 3
    M.inst = { name = map == 1 and "Kalimdor" or "Eastern Kingdoms", type = "none", diff = 0, mapID = map or 0 }
    M.fire("ZONE_CHANGED_NEW_AREA")
  end
  local function reload(gap)
    M.fire("PLAYER_LOGOUT"); G._tickAt = nil; T.newLoad()
    adv(gap or 9)
    pew(false, true); R.tick(); G.tick()
  end
  local function relog(gap)
    M.fire("PLAYER_LOGOUT"); G._tickAt = nil; T.newLoad()
    adv(gap)
    pew(true); R.tick(); G.tick()
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
    M.now = M.now + 4   -- past the loot window
  end
  local function quest(d) E.questMoney(d, 4242); money(d); M.now = M.now + 4 end
  local function item(id, n) M.fire("CHAT_MSG_LOOT", ("You receive loot: |cffffffff|Hitem:%d::::::::12:::::|h[Item %d]|h|r%s."):format(id, id, n and n > 1 and ("x" .. n) or "")) end
  -- the run is over: 20 minutes and a tick alive outside
  local function expire() play(R.REENTER + 10) end
  local function boss(run, id) for _, b in ipairs(run.bosses) do if b.enc == id then return b end end end
  -- a boss's segment and the boss killed before it, as every reader works them out from the kills
  local function seg(run, id) local sp = R.splits(run)[id]; return sp and sp.seg end
  local function prev(run, id) local sp = R.splits(run)[id]; return sp and sp.prev end
  local function errs() return #M.errors end

  -- ── the contract: every key of an open run and of a closed one, typed (docs/ADDON_DATA_CONTRACT.md) ───────────
  local function typed(t, spec, where)
    if type(t) ~= "table" then return where .. " is a " .. type(t) end
    for k, x in pairs(t) do
      local want = spec[k]
      if not want then return where .. "." .. tostring(k) .. " is not in the contract" end
      if type(x) ~= want then return where .. "." .. tostring(k) .. " is a " .. type(x) end
    end
  end
  local RUN = { id = "string", v = "number", inst = "string", kind = "string", map = "number", diff = "number", uiMap = "number", t = "number", endT = "number",
    open = "string", why = "string", partial = "string", visits = "table", secs = "table", firstPull = "number", bosses = "table", nDeaths = "table", deaths = "table", xp = "table",
    gold = "table", hidden = "table", keep = "boolean", size = "number", done = "boolean", pb = "boolean", exact = "boolean", edited = "boolean", repull = "number", copied = "boolean",
    st = "string", mark = "number", beat = "number", left = "number", ghostAt = "number", gap = "table", encs = "table", deadSince = "number", m0 = "number", g0 = "table", bossIn = "table", bossWin = "table", prov = "boolean" }
  local VISIT = { i = "number", o = "number", how = "string", out = "string", n = "number", secs = "number", active = "number", xp = "number", xpKill = "number", xpQuest = "number", kills = "number",
    looted = "number", quests = "number", lootValue = "number", items = "number", unpriced = "number", purse = "number", gaps = "table",
    gg = "number", go = "number", gf = "number", combat = "number", boss = "number" }
  local BOSS = { enc = "number", name = "string", pulls = "number", wipes = "number", resets = "number", unknown = "number", combat = "number", kill = "number",
    fight = "string", ok = "number", dur = "number", p = "number" }
  local SECS = { inside = "number", ghost = "number", outside = "number", offline = "number", active = "number", combat = "number", boss = "number" }
  local GOLD = { looted = "number", quests = "number", lootValue = "number", items = "number", unpriced = "number", purse = "number" }
  local function contract(run, isOpen)
    local why = typed(run, RUN, "run") or typed(run.secs, SECS, "secs")
      or (run.nDeaths and typed(run.nDeaths, { me = "number", party = "number" }, "nDeaths")) or (run.hidden and typed(run.hidden, { xp = "number", rep = "number", loot = "number" }, "hidden"))
      or (run.xp and typed(run.xp, { gain = "number", kill = "number", quest = "number", n = "number", l0 = "number", l1 = "number", p0 = "number", p1 = "number", need = "number" }, "xp"))
      or (run.gold and typed(run.gold, GOLD, "gold"))
    for _, x in ipairs(run.visits) do
      why = why or typed(x, VISIT, "visit")
      if type(x.gaps) == "table" then
        if #x.gaps % 2 ~= 0 or #x.gaps > 2 * R.GAP_CAP then why = why or "visit.gaps is no list of pairs under the cap" end
        for k, g in ipairs(x.gaps) do if type(g) ~= "number" or (k > 1 and g < x.gaps[k - 1]) then why = why or "visit.gaps is not in order" end end
      end
    end
    for _, x in ipairs(run.bosses) do why = why or typed(x, BOSS, "boss") end
    for _, x in ipairs(run.deaths or {}) do why = why or typed(x, { o = "number", enc = "number", foe = "string", back = "number" }, "death") end
    if not isOpen then
      for _, k in ipairs(R.OPEN_KEYS) do if run[k] ~= nil then why = why or ("closed run keeps " .. k) end end
      if not R.WHY[run.why] then why = why or "closed run without why" end
      -- lean: nothing that is 0, no empty block
      for _, blk in ipairs({ "secs", "nDeaths", "hidden", "gold" }) do
        for k, x in pairs(run[blk] or {}) do if x == 0 and not (blk == "secs" and k == "inside") then why = why or ("closed run stores a 0 in " .. blk .. "." .. k) end end
        if run[blk] and next(run[blk]) == nil then why = why or ("closed run stores an empty " .. blk) end
      end
      if run.deaths and #run.deaths == 0 then why = why or "closed run stores an empty deaths" end
    else
      if not ({ ["in"] = true, ghost = true, out = true, off = true })[run.st] then why = why or "st" end
      -- the open-only tables, typed
      for id, e in pairs(run.encs or {}) do why = why or (type(id) ~= "number" and "encs key") or typed(e, { t = "number", o = "number", d = "number", r = "number" }, "encs[]") end
      if run.gap then why = why or typed(run.gap, { ghost = "number", outside = "number", offline = "number" }, "gap") end
      if run.g0 then why = why or typed(run.g0, { looted = "number", quests = "number", lootValue = "number", items = "number", unpriced = "number" }, "g0") end
      if run.bossIn then why = why or typed(run.bossIn, { zone = "string", map = "number" }, "bossIn") end
      why = why or (not R.validOpen(run) and "not a valid open run") or nil
    end
    local HOW, OUT = { zone = 1, login = 1, reload = 1, ghost = 1, boss = 1, split = 1 }, { alive = 1, ghost = 1, offline = 1, other = 1, manual = 1 }
    for _, x in ipairs(run.visits) do if not HOW[x.how] or (x.out and not OUT[x.out]) then why = why or "visit how/out" end end
    if not ({ zone = 1, login = 1, boss = 1, split = 1 })[run.open] or not ({ party = 1, raid = 1 })[run.kind] then why = why or "open/kind" end
    return why
  end

  -- ── the invariants, asked at the end of every scenario ─────────────────────────────────────────────────────────
  local nInv = 0
  local function invariants(tag)
    nInv = nInv + 1
    local why
    local c = me()
    local ids = {}
    local function one(stored, isOpen)
      why = why or contract(stored, isOpen)
      if ids[stored.id] then why = "two runs carry the id " .. tostring(stored.id) end
      ids[stored.id] = true
      local run = isOpen and stored or norm(stored)
      local s = run.secs
      local vs = { secs = 0, active = 0, xp = 0, looted = 0, quests = 0, lootValue = 0, items = 0, combat = 0, boss = 0, gg = 0, go = 0, gf = 0 }
      for _, v in ipairs(run.visits) do
        for k in pairs(vs) do vs[k] = vs[k] + (v[k] or 0) end
        if (v.active or 0) > (v.secs or 0) then why = "a visit with more active seconds than seconds" end
      end
      if not isOpen then
        if run.endT - run.t ~= s.wall then why = ("the four clocks sum to %d, endT - t is %d"):format(s.wall, run.endT - run.t) end
        for _, k in ipairs({ "looted", "quests", "lootValue", "items" }) do if run.gold[k] ~= vs[k] then why = "gold." .. k .. " is not the sum of the visits" end end
        if run.visits[#run.visits].o == nil then why = "the last visit of a closed run has no end" end
      end
      if vs.secs ~= s.inside then why = ("inside %d is not the sum of the visits %d"):format(s.inside, vs.secs) end
      -- (0.9.51, record version 2) the visits hold the combat and boss seconds, and the gaps before them by kind
      if (stored.v or 1) >= 2 then
        if vs.combat ~= s.combat then why = ("combat %d is not the sum of the visits %d"):format(s.combat, vs.combat) end
        if vs.boss ~= s.boss then why = ("boss %d is not the sum of the visits %d"):format(s.boss, vs.boss) end
        local absorbed = (run.visits[#run.visits].n or 0) > 0
        local first = run.visits[1]
        local g1 = (first.gg or 0) + (first.go or 0) + (first.gf or 0)
        if not absorbed and (vs.gg - (first.gg or 0) ~= s.ghost or vs.go - (first.go or 0) ~= s.outside or vs.gf - (first.gf or 0) ~= s.offline) then
          why = "the gaps before the visits are not the ghost, outside and offline clocks"
        end
        if g1 > 0 and not stored.edited then why = "a first visit with a gap before it on a run that was never split" end
      end
      if vs.active ~= s.active then why = "active is not the sum of the visits" end
      if s.active > s.inside then why = "more active seconds than seconds inside" end
      if vs.xp ~= (run.xp and run.xp.gain or 0) then why = "xp is not the sum of the visits" end
      if not R.valid(stored) then why = "not a valid record" end
    end
    for _, r in ipairs(c.dungeonRuns or {}) do one(r, false) end
    -- at most one run is open, and it is not also in the list of the closed ones (the ids are all different)
    if c.dungeonRun ~= nil then
      if type(c.dungeonRun) ~= "table" then why = "the open run is no record" else one(c.dungeonRun, true) end
    end
    check("invariants after " .. tag, why == nil and R._err == nil, why or R._err)
  end

  -- ── 1. enter, two bosses, leave, 21 minutes: one record ───────────────────────────────────────────────────────
  do
    fresh()
    local t0 = M.epoch
    enter("Deadmines", { map = 36 })
    local id = open() and open().id
    check("1: entering opens a run named canonical, with its attributes", open() and open().inst == "The Deadmines" and open().kind == "party"
      and open().map == 36 and open().diff == 1 and open().t == t0 and open().open == "zone" and open().v == R.V and R.V == 2 and open().st == "in", open() and open().inst)
    check("1: the id is the last 8 of the GUID, the time and four hex digits", type(id) == "string" and id:match("^" .. ME:sub(-8):gsub("%-", "%%-") .. "%-" .. t0 .. "%-%x%x%x%x$") ~= nil, id)
    -- the four hex digits come from the random source (a counter would start again when the save file is lost)
    local realRandom = math.random
    math.random = function() return 0xBEEF end
    fresh(); enter("Deadmines", { map = 36 })
    math.random = realRandom
    check("1: the id's last four digits are random, not counted", open() and open().id:match("%-beef$") ~= nil, open() and open().id)
    fresh()
    t0 = M.epoch
    enter("Deadmines", { map = 36 })
    id = open() and open().id
    play(120)
    kill(644, "Rhahk'Zor", 40)
    play(100)
    kill(645, "Sneed", 30)
    play(60)
    leave()
    check("1: leaving alive keeps the run open and starts the 20 minutes", open() and open().st == "out" and open().left == M.epoch and #closed() == 0)
    play(R.REENTER)
    check("1: 20 minutes outside to the second are not over yet", open() ~= nil)
    play(10)
    local r = last()
    check("1: 21 minutes outside: one record, why left", open() == nil and #closed() == 1 and r.why == "left" and r.id == id, r and r.why)
    check("1: the run ends at the moment last inside, the time outside after it is not its time", r and r.endT == t0 + 350 and r.secs.wall == 350 and r.secs.inside == 350
      and r.secs.outside == 0 and r.secs.ghost == 0 and r.secs.offline == 0, r and r.secs.wall)
    check("1: every second inside was active (the tick ran, the player was there)", r and r.secs.active == 350 and r.visits[1].active == 350, r and r.secs.active)
    local a, b = r and boss(r, 644), r and boss(r, 645)
    check("1: two bosses in pull order, each killed once on the run's clock", r and #r.bosses == 2 and r.bosses[1] == a and a.kill == 160 and b.kill == 290 and a.pulls == 1 and b.pulls == 1
      and a.wipes == nil and a.unknown == nil and a.resets == nil, a and a.kill)
    check("1: a closed record is lean: a counter that is 0 is not stored", r and r.visits[1].xp == nil and r.visits[1].looted == nil and r.visits[1].purse == nil and r.visits[1].secs == 350 and a.pulls == 1)
    local st = raw()
    check("1: nor a clock that is 0, an empty block, or what a reader can work out", st.secs.inside == 350 and st.secs.wall == nil and st.secs.ghost == nil and st.secs.outside == nil
      and st.secs.offline == nil and st.hidden == nil and st.nDeaths == nil and st.deaths == nil and st.gold == nil and st.key == nil and st.bosses[1].ok == nil and st.bosses[1].dur == nil
      and st.bosses[1].pulls == nil and st.bosses[1].seg == nil and st.bosses[1].prev == nil and st.bosses[1].at == nil)
    check("1: a segment runs from the first pull, then from the kill before", a and seg(r, 644) == 40 and prev(r, 644) == nil and seg(r, 645) == 130 and prev(r, 645) == 644 and r.firstPull == 120, seg(r, 645))
    check("1: boss combat is END minus START, the kill less the pull is where the pull began", a and a.combat == 40 and b.combat == 30 and a.kill - a.combat == 120 and b.kill - b.combat == 260 and r.secs.boss == 70)
    check("1: one visit, closed alive", r and #r.visits == 1 and r.visits[1].i == 0 and r.visits[1].o == 350 and r.visits[1].how == "zone" and r.visits[1].out == "alive")
    check("1: the session counts one dungeon run", ns.Recorder.current() and ns.Recorder.current().dungeons == 1, ns.Recorder.current() and ns.Recorder.current().dungeons)
    local v = R.views()[1]
    check("1: the view reads length, bosses, pulls and deaths", v and v.duration == 350 and v.bossesDown == 2 and v.pulls == 2 and v.wipes == 0 and v.deaths == 0 and v.inProgress == false
      and v.name == "The Deadmines" and v.startT == t0 and v.endT == t0 + 350 and R.endedLine(v) == "Ended: left the dungeon")
    check("1: the 20 minutes are the gold run's 20 minutes", R.REENTER == G.RUN_REENTER and R.REENTER == 1200)
    invariants("1")
  end

  -- ── 2. /reload inside: the same run ────────────────────────────────────────────────────────────────────────
  do
    fresh()
    enter("Maraudon")
    play(100)
    local id = open().id
    reload(9)
    check("2: a /reload inside keeps the run: same id, same visit, no record", open() and open().id == id and #open().visits == 1 and #closed() == 0, open() and #open().visits)
    check("2: the seconds of the /reload stay on the clock the run was on (inside)", open().secs.inside == 109 and open().secs.offline == 0, open().secs.inside)
    play(41)
    leave(); expire()
    local r = last()
    check("2: and it closes as one run of one visit", #closed() == 1 and r.secs.inside == 150 and r.secs.wall == 150 and #r.visits == 1)
    check("2: the active seconds of a /reload are not counted (no tick ran)", r.secs.active == 140, r.secs.active)
    invariants("2")
    -- a run found at a /reload with no run stored (the update was installed in the middle of a dungeon)
    fresh()
    M.zone = "Maraudon"; M.inst = { name = "Maraudon", type = "party", diff = 1, mapID = 349 }
    reload(9)
    check("2: a run that begins at a /reload inside says so on its visit", open() and open().open == "login" and open().visits[1].how == "reload" and open().partial == nil)
    invariants("2b")
  end

  -- ── 3. leave alive 19 minutes and re-enter; 21 minutes make two runs ──────────────────────────────────────────
  do
    fresh()
    local t0 = M.epoch
    enter("Maraudon")
    play(100)
    leave()
    play(19 * 60)
    enter("Maraudon")
    local run = open()
    check("3: back in after 19 minutes: one run, two visits, 1140 s outside", run and #closed() == 0 and #run.visits == 2 and run.secs.outside == 1140 and run.t == t0, run and run.secs.outside)
    check("3: the visits carry their wall offsets and how they began and ended", run.visits[1].o == 100 and run.visits[1].out == "alive" and run.visits[2].i == 1240 and run.visits[2].how == "zone")
    play(50)
    leave()
    play(21 * 60)
    enter("Maraudon")
    check("3: back in after 21 minutes: two runs", #closed() == 1 and open() and open().id ~= run.id and open().t == M.epoch)
    local r = last()
    check("3: the first holds its two visits and the gap between them, not the 21 minutes after", r.secs.inside == 150 and r.secs.outside == 1140 and r.secs.wall == 1290 and r.endT == t0 + 1290, r.secs.wall)
    check("3: a time outside is in no boss offset: the run's clock is inside plus running back", R.views()[1].duration == 150)
    invariants("3")
  end

  -- ── 4. ghost: the run back, the cap, the logout as a ghost, the spirit healer ─────────────────────────────────
  do
    fresh()
    enter("Maraudon")
    play(100)
    die(); play(20)
    leave()
    check("4: leaving as a ghost is a ghost gap, the 20 minutes do not run", open() and open().st == "ghost" and open().left == nil and open().visits[1].out == "ghost")
    play(25 * 60)
    check("4: 25 minutes as a ghost: still the run", open() ~= nil and #closed() == 0)
    enter("Maraudon"); rise()
    local run = open()
    check("4: back in as a ghost: one run, the gap is running back, on the run's clock", run and #run.visits == 2 and run.secs.ghost == 1500 and run.secs.outside == 0 and run.visits[2].how == "ghost", run and run.secs.ghost)
    check("4: the death carries how long it took to be back", run.nDeaths.me == 1 and #run.deaths == 1 and run.deaths[1].back == 1520 and run.deaths[1].o == 100 and run.deaths[1].who == nil and run.deadSince == nil, run.deaths[1] and run.deaths[1].back)
    play(60)
    -- dies again and logs out as a ghost for the night
    die(); play(10); leave()
    local endT = open().endT
    relog(8 * 3600)
    -- (the night offline runs no clock: the 30 minutes go on from the login, where the logout left them)
    check("4: logged out as a ghost overnight: at the login still running back, the night on no ghost clock", open() and open().st == "ghost" and #closed() == 0
      and open().ghostAt == M.epoch and open().gap.offline == 8 * 3600 and open().gap.ghost == 0, open() and (open().ghostAt - M.epoch .. " " .. open().gap.offline .. " " .. open().gap.ghost))
    play(R.GHOST_CAP)
    check("4: 30 minutes as a ghost after the login to the second are not over", open() ~= nil)
    play(10)
    local r = last()
    check("4: then closed at the cap, why ghost", open() == nil and r and r.why == "ghost", r and r.why)
    check("4: and not hours long: it ends where the character was last inside", r.endT == endT and r.secs.wall == 120 + 1500 + 70 and r.secs.offline == 0, r.secs.wall)
    invariants("4")
    -- past the cap without a logout
    fresh()
    enter("Maraudon"); play(100); die(); leave()
    play(R.GHOST_CAP); check("4: 30 minutes as a ghost to the second are not over", open() ~= nil)
    play(10)
    check("4: a ghost outside past 30 minutes ends the run", open() == nil and last().why == "ghost" and last().secs.wall == 100)
    invariants("4b")
    -- a spirit healer: resurrected outside, the running back is over and the 20 minutes begin (real run: death
    -- 20:47:21, alive 20:50:57)
    fresh()
    enter("Maraudon"); play(100); die(); play(10); leave()
    play(200)
    M.dead = false; M.fire("PLAYER_ALIVE")
    check("4: a resurrect outside turns the ghost gap into alive outside", open() and open().st == "out" and open().left == M.epoch and open().ghostAt == nil and open().deaths[1].back == 210)
    play(R.REENTER); check("4: the 20 minutes count from the resurrect", open() ~= nil)
    play(10)
    check("4: and close the run 20 minutes after it", open() == nil and last().why == "left" and last().secs.wall == 110 and last().secs.ghost == 0)
    invariants("4c")
    -- the same, and back in within the 20 minutes: both gaps are typed
    fresh()
    enter("Maraudon"); play(100); die(); leave()
    play(200); M.dead = false
    R.tick()                                                     -- no event reached the addon: the tick sees the character alive
    check("4: the tick notices a resurrect no event announced", open().st == "out")
    play(600); enter("Maraudon")
    check("4: ghost and alive seconds of one gap are kept apart", open().secs.ghost == 200 and open().secs.outside == 600 and #open().visits == 2 and open().visits[2].how == "zone")
    invariants("4d")
  end

  -- ── 5. logout inside for 8 hours, login inside ───────────────────────────────────────────────────────────────
  do
    fresh()
    enter("Maraudon"); play(300)
    local id = open().id
    relog(8 * 3600)
    local run = open()
    check("5: logged out inside and back inside: the same run", run and run.id == id and #closed() == 0)
    check("5: offline time is never inside", run.secs.inside == 300 and run.secs.offline == 8 * 3600 and run.secs.outside == 0, run.secs.inside)
    check("5: the visit ended offline and the next began at the login", #run.visits == 2 and run.visits[1].out == "offline" and run.visits[1].o == 300 and run.visits[2].how == "login")
    play(60); leave(); expire()
    check("5: the closed run sums to its wall time", last().secs.wall == 360 + 8 * 3600 and last().secs.inside == 360)
    invariants("5")
    -- logged out inside, back outside (hearthed at the login screen or reset): the 20 minutes start at the login
    fresh()
    enter("Maraudon"); play(300)
    M.fire("PLAYER_LOGOUT"); T.newLoad(); adv(3600); outside(); pew(true)
    check("5: logged out inside, back outside: the run waits its 20 minutes from the login", open() and open().st == "out" and open().left == M.epoch)
    expire()
    check("5: then closes where it was last inside", open() == nil and last().secs.wall == 300 and last().why == "left")
    invariants("5b")
    -- the character's GUID is not known yet at the login (the client names it a moment later): the offline hours
    -- still land on no other clock
    fresh()
    enter("Maraudon"); play(300)
    M.fire("PLAYER_LOGOUT"); G._tickAt = nil; T.newLoad(); adv(8 * 3600)
    _G.UnitGUID = function(u) if u == "player" then return nil end return real.guid(u) end
    pew(true); R.tick()
    _G.UnitGUID = real.guid
    adv(10); R.tick()
    check("5: a login before the client names the character reads the load once it does", open() and open().secs.inside == 300 and open().secs.offline == 8 * 3600 + 10 and open().secs.active == 300
      and #open().visits == 2 and open().visits[2].how == "login", open() and open().secs.inside)
    invariants("5c")
  end

  -- ── 6. the game closed without saving: the file's run ends where the file last saw it ───────────────────────
  do
    fresh()
    local t0 = M.epoch
    enter("Maraudon"); play(200)
    kill(422, "Noxxion", 30)
    -- a /reload writes the file; everything after it is lost with the crash
    E.reloadAsked(); M.fire("PLAYER_LOGOUT")
    local file = deepcopy(ns.DB)
    G._tickAt = nil; T.newLoad(); adv(9); pew(false, true)
    play(300); kill(423, "Razorlash", 30)
    check("6: (before the crash the run had two kills)", #open().bosses == 2)
    ns.Recorder.discard()
    ns.DB = ns.migrateDB(file)
    G._tickAt = nil; T.newLoad(); adv(3600)
    outside(); pew(true)
    local r = last()
    check("6: a login after an unsaved stretch closes the file's run at its last beat", open() == nil and r and r.why == "lost" and r.endT == t0 + 230 and r.secs.wall == 230, r and r.endT - t0)
    check("6: and marks it partial, with only what the file holds", r.partial == "state lost before this login" and #r.bosses == 1 and R.views()[1].partial ~= nil)
    check("6: the page and the row say so in words", R.partialLine(R.views()[1]) == "Part of this run was lost: the game closed without saving." and R.endedLine(R.views()[1]) == "Ended: the game closed without saving")
    check("6: it is counted for the next look", notes().lost == 1)
    invariants("6")
    -- the same crash, and the login is inside: the new run cannot know what came before
    fresh()
    enter("Maraudon"); play(200)
    E.reloadAsked(); M.fire("PLAYER_LOGOUT")
    file = deepcopy(ns.DB)
    ns.Recorder.discard(); ns.DB = ns.migrateDB(file)
    G._tickAt = nil; T.newLoad(); adv(3600)
    pew(true)
    check("6: a login inside after an unsaved stretch: the old run is closed partial, the new one is partial too", #closed() == 1 and last().why == "lost"
      and open() and open().open == "login" and open().partial == "state lost before this login" and open().visits[1].how == "login")
    invariants("6b")
  end

  -- ── 7. two names, one dungeon; the halls outside; the dungeon the client never names an instance ────────────
  do
    fresh()
    enter("Sunken Temple", { map = 109 })
    local d0 = 0
    for _, e in ipairs(ns.DB.story.events) do if e.kind == "DUNGEON" then d0 = d0 + 1 end end
    for i = 1, 12 do
      play(30)
      local nm = i % 2 == 1 and "The Temple of Atal'Hakkar" or "Sunken Temple"
      enter(nm, { map = 109, noLoad = true })
    end
    local d1 = 0
    for _, e in ipairs(ns.DB.story.events) do if e.kind == "DUNGEON" then d1 = d1 + 1 end end
    check("7: twelve flips between the two names of Sunken Temple: one run, one visit", open() and open().inst == "Sunken Temple" and #open().visits == 1 and #closed() == 0 and d1 == d0, d1 - d0)
    -- the clear is over. The character walks out into the halls in front of the portal and farms there for an hour:
    -- the zone flips between "Swamp of Sorrows" and "The Temple of Atal'Hakkar", GetInstanceInfo names the continent
    kill(1488, "Shade of Eranikus", 40)
    play(200)
    local inside = open().secs.inside
    local endT = M.epoch
    M.xp = 100; M.fire("PLAYER_XP_UPDATE")
    local xpIn = open().xp and open().xp.gain or 0
    for i = 1, 60 do
      walk(i % 2 == 1 and "The Temple of Atal'Hakkar" or "Swamp of Sorrows")
      combat(true); play(30); combat(false)                      -- a fight in the halls confirms nothing
      M.xp = M.xp + 5; M.fire("PLAYER_XP_UPDATE")
      play(30)
    end
    local r = last()
    check("7: an hour in the halls after the clear: one run, closed by the 20 minutes", open() == nil and #closed() == 1 and r.why == "left", #closed())
    check("7: no inside time after the exit, no second visit", r.secs.inside == inside and r.endT == endT and #r.visits == 1 and r.secs.wall == inside, r.secs.inside - inside)
    check("7: XP and combat in the halls are not the run's", (r.xp and r.xp.gain or 0) == xpIn and r.secs.combat == 0, r.xp and r.xp.gain)
    check("7: the door visits are counted for the next look, and opened nothing", (notes().door or 0) >= 1 and ns.Recorder.current().dungeons == 1, notes().door)
    walk("The Temple of Atal'Hakkar"); play(120)
    check("7: standing at the door with no run open opens none", open() == nil and #closed() == 1)
    invariants("7")
    -- Shadowfang Keep: the client says type "none" inside; only the zone name tells. With a map that is no continent,
    -- or none readable, the character is inside.
    fresh()
    enter("Shadowfang Keep", { type = "none", map = 33 })
    check("7: a dungeon whose strong signal never fires still opens (the zone name, a dungeon's map id), provisional", open() and open().inst == "Shadowfang Keep" and open().st == "in"
      and E._det.sig == "name" and open().prov == true)
    play(60); combat(true); play(10); combat(false); play(50); leave(); expire()
    check("7: once a fight confirms it, its time counts as inside", #closed() == 1 and last().secs.inside == 120)
    fresh()
    M.secrets[987654] = true
    enter("Shadowfang Keep", { type = "none", map = 987654 })
    check("7: the same with a map id the client hides", open() and open().st == "in" and open().map == nil)
    M.secrets[987654] = nil
    invariants("7b")
    -- the zone name on a continent map (what the halls answer): no run until a boss is pulled there
    fresh()
    walk("Shadowfang Keep")
    play(60)
    check("7: the zone name on a continent map is the door: no run", open() == nil and R._where == "door")
    START(1069, "Rethilgore")
    check("7: a boss pulled there puts the character inside (the zone name and an encounter)", open() and open().open == "boss" and open().st == "in" and open().inst == "Shadowfang Keep"
      and open().visits[1].how == "boss" and type(open().bossIn) == "table")
    play(40); END(1069, "Rethilgore", 1); play(60)
    check("7: and it stays inside while the zone and the map stay", open().st == "in" and open().secs.inside == 100 and boss(open(), 1069).kill == 40, open().secs.inside)
    walk("Silverpine Forest")
    check("7: until the zone changes", open().st == "out" and open().bossIn == nil and open().visits[1].o == 100)
    invariants("7c")
  end

  -- ── runs opened by a boss: a dungeon no signal names, and the world boss that opens nothing ──────────────────
  do
    fresh()
    walk("Azshara", 1)
    START(9001, "Azuregos")
    check("boss: an outdoor encounter (a continent map, no dungeon name) opens nothing", open() == nil and #closed() == 0 and notes().outdoorBoss == 1)
    END(9001, "Azuregos", 1)
    check("boss: and its END changes nothing", open() == nil and #closed() == 0)
    -- a custom dungeon the name list lacks and the client does not type: its map is no continent
    walk("Alcaz Island", 4500)
    check("boss: (the detector says outside there)", E._det.kind == nil and open() == nil and me().inInstance == nil)
    START(3360, "Warden Krix")
    local run = open()
    check("boss: an encounter on a map that is no continent opens a run", run and run.open == "boss" and run.inst == "Alcaz Island" and run.map == 4500 and run.st == "in" and boss(run, 3360).pulls == 1)
    play(30); END(3360, "Warden Krix", 1)
    -- no gold run exists for it (the gold run follows the zone name): the coin is still seen on the purse
    loot(400)
    check("boss: such a run has no gold run beside it", me().goldRun == nil)
    play(60)
    walk("Dustwallow Marsh", 1)
    expire()
    local r = last()
    check("boss: it closes like any other", r and r.why == "left" and r.secs.inside == 90 and boss(r, 3360).kill == 30)
    check("boss: with no gold run its looted coin reads 0 and the purse check shows the 400 c", r.gold.looted == 0 and r.gold.items == 0 and r.gold.purse == 400
      and R.purseLine(R.views()[1]) == ("Coin %s of %s gained inside"):format(fmt(0), fmt(400)), r.gold.purse)
    invariants("boss")
  end

  -- ── 8 to 12. the encounter state machine ─────────────────────────────────────────────────────────────────────
  do
    -- 8. own death, then the party kills the boss: one kill (real: the fight closes on the player's death at 17 s)
    fresh()
    enter("Maraudon"); play(60)
    combat(true); START(425, "Landslide"); play(17)
    die(); combat(false)
    check("8: (the fight closed on the death, no fight is open)", T.currentFight() == nil)
    play(20)
    END(425, "Landslide", 1)
    local b = boss(open(), 425)
    check("8: own death, then END success with no open fight: one kill", b and b.kill == 97 and b.pulls == 1 and b.wipes == 0 and b.unknown == 0 and b.combat == 37, b and b.kill)
    check("8: the death is the run's, inside that boss's pull", open().nDeaths.me == 1 and open().deaths[1].enc == 425 and open().deaths[1].o == 77)
    check("8: the kill links the fight that ended inside the pull", type(b.fight) == "string" and b.fight == ns.Fights.list()[#ns.Fights.list()].uid, b.fight)
    rise()
    invariants("8")

    -- 9. an END that is not a success: a reset without a death, a wipe with one
    fresh()
    enter("Sunken Temple", { map = 109 }); play(60)
    START(492, "Avatar of Hakkar"); play(1); END(492, "Avatar of Hakkar", 0)
    b = boss(open(), 492)
    check("9: a non-success END with nobody dead is a reset, not a wipe and not a kill", b and b.kill == nil and b.resets == 1 and b.wipes == 0 and b.unknown == 0 and b.ok == 0 and b.dur == 1
      and R.bossResult(b) == "Reset", b and b.resets)
    play(9)
    START(492, "Avatar of Hakkar"); play(50); END(492, "Avatar of Hakkar", 1)
    check("9: START, END 0 after 1 s, START, END 1: one kill, two pulls, no wipe", b.kill == 120 and b.pulls == 2 and b.wipes == 0 and b.resets == 1 and b.combat == 51, b.kill)
    check("9: the reset is resolved by the kill: nothing unseen stands against a full clear", R.views()[1].unseen == 0 and R.views()[1].bossesDown == 1 and R.bossResult(b) == "Killed")
    -- a survived wipe is not a kill; the death in the pull makes it a wipe
    START(493, "Shade of Eranikus"); play(20); die(); play(5); END(493, "Shade of Eranikus", 0)
    local s = boss(open(), 493)
    check("9: a non-success END with the character dead in the pull is a wipe", s and s.kill == nil and s.wipes == 1 and s.resets == 0 and R.bossResult(s) == "Wiped", s and s.wipes)
    rise()
    -- a boss reset twice and never killed: its last pull is shorter than its time in combat
    play(30); START(494, "Morphaz"); play(2); END(494, "Morphaz", 0); play(5); START(494, "Morphaz"); play(1); END(494, "Morphaz", 0)
    invariants("9")
    -- the raw answer of an END that was no kill is what the wipe probe reads (plan section 10): it stays on the
    -- stored record, beside `dur`, and only a kill drops it
    leave(); expire()
    local rr = raw()
    local k, w, z = boss(rr, 492), boss(rr, 493), boss(rr, 494)
    check("9: closed: the killed row keeps no ok, the wipe and the reset rows keep ok 0", k and k.kill and k.ok == nil and w and w.ok == 0 and z and z.ok == 0, tostring(w and w.ok) .. " " .. tostring(z and z.ok))
    check("9: closed: dur stays where it is not the time in combat, and reads as it where it is", z.dur == 1 and z.combat == 3 and z.resets == 2 and w.dur == nil and w.combat == 25
      and (w.dur or w.combat) == 25, tostring(z.dur) .. " " .. tostring(w.dur))
    invariants("9 closed")

    -- 10. a boss pulled out of trash combat (real: fight 216 opens 20:37:46, the START is 20:38:19; 85 s of fight,
    -- 52 s of encounter)
    fresh()
    local t0 = M.epoch
    enter("Maraudon"); play(288)
    M.units.target = { name = "Noxxion", hostile = true, guid = "Creature-0-1-1-1-13282-00AB" }
    combat(true)
    local uid = T.currentFight() and T.currentFight().uid
    play(33)
    START(422, "Noxxion"); play(52); END(422, "Noxxion", 1)
    combat(false); M.units.target = nil
    b = boss(open(), 422)
    check("10: the pull time is the START, never the start of the fight", b and b.kill - b.dur == 321 and b.combat == 52 and b.kill == 373, b and b.kill - b.dur)
    check("10: the first pull of the run is the first combat", open().firstPull == 288 and seg(open(), 422) == 85 and open().secs.combat == 85 and open().secs.boss == 52, open().firstPull)
    check("10: the boss links the fight that was running at its END", uid ~= nil and b.fight == uid, tostring(b.fight))
    invariants("10")
    -- the link refuses a fight that ended before the pull (a trash fight, then a boss with no fight of its own:
    -- the client opened none, or it was not kept), and takes one that ended inside it
    do
      local F = ns.Fights
      local realCur, realList = F.currentUid, F.list
      local trash = { uid = "trash-1", startEpoch = 1000, duration = 40 }
      local stub = { trash }
      F.currentUid, F.list = function() return nil end, function() return stub end
      local realMine = ns.isMine
      ns.isMine = function() return true end
      local refuse = R.fightUid(1041)
      local touch = R.fightUid(1040)
      local inside = R.fightUid(1020)
      stub[2] = { uid = "pull-1", startEpoch = 1050, duration = 30 }
      local later = R.fightUid(1060)
      F.currentUid, F.list, ns.isMine = realCur, realList, realMine
      check("10: a fight that ended before the pull is no link of the kill", refuse == nil, tostring(refuse))
      check("10: one that ended inside the pull, or at its first second, is", touch == "trash-1" and inside == "trash-1" and later == "pull-1", tostring(touch) .. " " .. tostring(later))
    end

    -- 11. END twice, END without START, and two encounters open at once (Zul'Farrak: Sezz'ziz and Nekrum start 17 ms
    -- apart and end 5 s apart)
    fresh()
    enter("Zul'Farrak", { map = 209 }); play(100)
    local n0 = notes().endNoStart or 0
    START(600, "Antu'sul"); play(40); END(600, "Antu'sul", 1); play(5); END(600, "Antu'sul", 1)
    b = boss(open(), 600)
    check("11: END twice within 15 s: one kill, one split", b.kill == 140 and b.pulls == 1 and b.combat == 40 and (notes().endNoStart or 0) == n0 + 1, b.kill)
    END(777, "Nobody", 1)
    check("11: an END without a START is ignored", boss(open(), 777) == nil and #open().bosses == 1 and (notes().endNoStart or 0) == n0 + 2)
    play(55)
    START(601, "Shadowpriest Sezz'ziz"); START(602, "Nekrum Gutchewer")
    check("11: two encounters are open at once", open().encs[601] ~= nil and open().encs[602] ~= nil)
    play(30); END(601, "Shadowpriest Sezz'ziz", 1); play(5); END(602, "Nekrum Gutchewer", 1)
    local a, c2 = boss(open(), 601), boss(open(), 602)
    check("11: two overlapping encounters give two kills", a.kill == 230 and c2.kill == 235 and #open().bosses == 3 and R.views()[1].bossesDown == 3, tostring(a.kill) .. " " .. tostring(c2.kill))
    -- (0.9.51: kills whose pulls overlapped are one split, so the order the pair died in never changes a segment)
    check("11: the END of the second, 5 s after the first, is kept, and the pair is one split", seg(open(), 602) == 95 and seg(open(), 601) == 95 and prev(open(), 602) == 600
      and prev(open(), 601) == 600 and R.splits(open())[601].key == "601+602" and c2.combat == 35)
    check("11: time with a boss up is counted once while two are up", open().secs.boss == 40 + 35 and open().encs == nil, open().secs.boss)
    invariants("11")

    -- 12. an encounter still open when the character leaves, and across a /reload
    fresh()
    enter("Maraudon"); play(100)
    START(426, "Princess Theradras"); play(20)
    leave()
    b = boss(open(), 426)
    check("12: an encounter open at the leave ends unseen", b.unknown == 1 and b.kill == nil and open().encs == nil and R.bossResult(b) == "Outcome not seen", b.unknown)
    check("12: a boss with an unseen outcome stands against a full clear", R.views()[1].unseen == 1 and R.views()[1].bossesDown == 0)
    enter("Maraudon"); play(30)
    START(426, "Princess Theradras"); play(60); END(426, "Princess Theradras", 1)
    check("12: killed later in the same run, the unseen pull is resolved", b.kill ~= nil and b.pulls == 2 and R.views()[1].unseen == 0 and R.views()[1].bossesDown == 1)
    -- across a /reload: the END arrives after it
    START(427, "Rotgrip"); play(10)
    reload(9)
    check("12: an encounter stays open across a /reload", open().encs and open().encs[427] ~= nil)
    play(11); END(427, "Rotgrip", 1)
    check("12: and its END after the /reload is a kill of the full length", boss(open(), 427).kill ~= nil and boss(open(), 427).combat == 30, boss(open(), 427).combat)
    -- across a /reload with the END missed (it fired during the loading screen)
    START(428, "Tinkerer Gizlock"); play(10)
    reload(9)
    play(60)
    check("12: an END missed in a /reload leaves the encounter open, nothing is guessed", open().encs and open().encs[428] ~= nil and boss(open(), 428).kill == nil)
    START(428, "Tinkerer Gizlock")
    check("12: a new START of it closes the old pull as unseen", boss(open(), 428).unknown == 1 and boss(open(), 428).pulls == 2 and notes().restart == 1)
    R.endNow()
    local r = last()
    check("12: a run ended while a boss is in progress says so", r.why == "manual" and r.partial == "ended while a boss was in progress" and boss(r, 428).unknown == 2
      and R.partialLine(R.views()[#R.views() - (open() and 1 or 0)]) ~= nil, r.partial)
    -- a ghost outside still hears the END: died, released, the party killed it
    fresh()
    enter("Maraudon"); play(100)
    START(429, "Celebras the Cursed"); play(20); die(); play(5); leave()
    check("12: released during a boss: the encounter stays open while running back", open().st == "ghost" and open().encs and open().encs[429] ~= nil)
    play(30); END(429, "Celebras the Cursed", 1)
    check("12: the kill the party made counts, on the run's clock", boss(open(), 429).kill == 155 and boss(open(), 429).wipes == 0, boss(open(), 429).kill)
    enter("Maraudon"); rise()
    invariants("12")
  end

  -- ── gold per visit: the difference of the gold run counters, over every way the two lifetimes differ ───────
  do
    -- a ghost gap between 20 and 30 minutes: the gold run closes at 20, the dungeon run goes on
    fresh()
    enter("Maraudon"); play(60)
    loot(500); item(9001)
    die(); leave()
    play(25 * 60)
    enter("Maraudon"); rise()
    check("gold: after 25 minutes as a ghost the gold run was closed and a new one opened, the dungeon run is the same", #(me().goldRuns or {}) == 1 and me().goldRun ~= nil and #closed() == 0 and #open().visits == 2)
    loot(300)
    leave(); expire()
    local r = last()
    check("gold: the run's coin is that of both gold runs, per visit", r.gold.looted == 800 and r.visits[1].looted == 500 and r.visits[2].looted == 300 and r.gold.items == 1, r.gold.looted)
    invariants("gold ghost")

    -- End run now, then re-entry: the gold run goes on, the new run takes only what came after
    fresh()
    enter("Maraudon"); play(60)
    loot(500)
    local rec = R.endNow()
    check("gold: End run now closes the run with its coin, why manual", rec and rec.why == "manual" and rec.gold.looted == 500 and rec.visits[1].out == "manual" and raw() == rec)
    local nxt = open()
    check("manual: still inside, the next run opens in the same second, as a split", nxt and nxt.id ~= rec.id and nxt.open == "split" and nxt.visits[1].how == "split" and nxt.st == "in"
      and nxt.t == rec.endT and nxt.inst == rec.inst and nxt.secs.inside == 0, nxt and nxt.open)
    loot(200); play(60)
    check("manual: the 60 s after the cut are the next run's, none belongs to no run", open() == nxt and nxt.secs.inside == 60 and rec.secs.inside + nxt.secs.inside == M.epoch - rec.t, nxt.secs.inside)
    check("gold: the gold run went on over the cut", me().goldRun and me().goldRun.looted == 700 and #(me().goldRuns or {}) == 0)
    leave(); expire()
    check("gold: the run after the cut holds only its own coin", #closed() == 2 and last().gold.looted == 200 and closed()[1].gold.looted == 500, last().gold.looted)
    invariants("gold manual")

    -- an item priced late: its vendor price arrives before the visit ends
    fresh()
    M.sellPrice = { [9001] = 250 }
    enter("Maraudon"); play(60)
    item(9001, 2); item(9003, 2)
    check("gold: (an item without a price waits on the gold run)", me().goldRun.wait and me().goldRun.wait[9003] == 2)
    M.sellPrice[9003] = 100
    leave()
    check("gold: a price that arrives before the visit ends is in the visit", open().visits[1].lootValue == 700 and open().visits[1].items == 2 and open().visits[1].unpriced == nil, open().visits[1].lootValue)
    -- and one that never arrives is counted as unpriced
    enter("Maraudon"); item(9004, 3); leave(); expire()
    r = last()
    check("gold: an item never priced counts 0 and the run says how many", r.gold.lootValue == 700 and r.gold.items == 3 and r.gold.unpriced == 3 and r.visits[2].unpriced == 3, r.gold.unpriced)
    M.sellPrice = real.sell
    invariants("gold wait")

    -- the purse check (2026-11-18: 365 c booked as looted, 10,888 c more arrived as group shares booked as mail)
    fresh()
    enter("Maraudon"); play(600)
    loot(365)
    for _ = 1, 7 do money(1555) end
    money(3)
    quest(1200)
    leave(); expire()
    r = last()
    check("purse: the looted coin is what the gold run booked", r.gold.looted == 365 and r.gold.quests == 1200)
    check("purse: the purse's own change inside, less quest coin, is kept beside it", r.gold.purse == 365 + 10888 and r.visits[1].purse == 365 + 10888 + 1200, r.gold.purse)
    check("purse: the page says both when they differ", R.purseLine(R.views()[1]) == ("Coin %s of %s gained inside"):format(fmt(365), fmt(11253)), R.purseLine(R.views()[1]))
    check("purse: 19 of the active minutes give a rate, coin over active seconds", R.views()[1].coinPerHour == (365 + 1200) * 3600 / 600)
    invariants("purse")
    -- coin gained outside between two visits is in neither
    fresh()
    enter("Maraudon"); play(60); loot(100); leave()
    loot(5000); money(-300)
    enter("Maraudon"); play(60); loot(50); leave(); expire()
    r = last()
    check("purse: the purse outside between two visits is not the run's", r.gold.purse == 150 and r.gold.looted == 150 and R.purseLine(R.views()[1]) == nil, r.gold.purse)
    invariants("purse outside")
  end

  -- ── one active clock ─────────────────────────────────────────────────────────────────────────────────────────
  do
    fresh()
    enter("Maraudon")
    play(300)
    G._afk = true; play(120); G._afk = false                      -- away from the keyboard: not active, still inside
    play(180)
    local run, gr = open(), me().goldRun
    check("active: the run's active seconds and the gold run's agree within 10 s on the same visit", gr and math.abs(run.secs.active - gr.secs) <= 10 and run.secs.active == 480, run.secs.active .. " " .. tostring(gr and gr.secs))
    check("active: time away from the keyboard is inside, not active", run.secs.inside == 600 and run.visits[1].active == 480)
    -- 19: the gold run of 0.9.47 keeps its coin per hour with the dungeon run beside it
    loot(800)
    local v = G.runs().rows[1]
    check("19: the gold run's coin per hour is unchanged: coin over its own active seconds", v and v.secs == gr.secs and v.perHour == 800 * 3600 / gr.secs, v and v.perHour)
    invariants("active")
  end

  -- ── a dungeon with two names the alias list lacks (Alcaz Prison: one visit made 3 DUNGEON events) ──────────
  do
    fresh()
    local function nDungeon() local n = 0; for _, e in ipairs(ns.DB.story.events) do if e.kind == "DUNGEON" then n = n + 1 end end return n end
    enter("Alcaz Island", { name = "Alcaz Prison", map = 4500 })
    local d0, gr = nDungeon(), me().goldRun
    play(60)
    enter("Alcaz Island", { name = "Alcaz Island Prison", map = 4500, noLoad = true })
    check("alias: a name flip inside with the instance map unchanged is learned as an alias", ns.DB.settings.instanceAlias and ns.DB.settings.instanceAlias["alcaz island prison"] == "Alcaz Prison"
      and E.canonInstance("Alcaz Island Prison") == "Alcaz Prison" and notes().alias == 1)
    check("alias: the flip raises no DUNGEON event, splits no run and no gold run", nDungeon() == d0 and me().goldRun == gr and #(me().goldRuns or {}) == 0 and me().inInstance == "Alcaz Prison"
      and open().inst == "Alcaz Prison" and #open().visits == 1 and #closed() == 0, nDungeon() - d0)
    play(30)
    enter("Alcaz Island", { name = "Alcaz Prison", map = 4500, noLoad = true })
    enter("Alcaz Island", { name = "Alcaz Island Prison", map = 4500 })    -- and through a loading screen
    check("alias: both names are the one run from then on", #open().visits == 1 and #closed() == 0 and nDungeon() == d0)
    -- a new load keeps what was learned (it is in the save file)
    reload(9)
    check("alias: the learned name is kept across a /reload", E.canonInstance("alcaz island prison") == "Alcaz Prison" and #open().visits == 1)
    -- another name on another map with no loading screen: no close, kept as a question
    play(30)
    enter("Alcaz Island", { name = "Alcaz Vault", map = 4501, noLoad = true })
    local cands = ns.DB.settings.selftest.aliasCandidates
    check("alias: a name change with no loading screen and another map closes nothing and is noted", #open().visits == 1 and #closed() == 0 and open().inst == "Alcaz Prison"
      and cands and #cands == 1 and cands[1].from == "Alcaz Prison" and cands[1].to == "Alcaz Vault" and cands[1].map0 == 4500 and cands[1].map1 == 4501
      and ns.DB.settings.instanceAlias["alcaz vault"] == nil, cands and #cands)
    -- another instance through a loading screen: the run closes, why other
    play(30)
    enter("Zul'Farrak", { map = 209 })
    check("alias: another instance through a loading screen closes the run, why other", #closed() == 1 and last().why == "other" and last().visits[1].out == "other" and open().inst == "Zul'Farrak", last() and last().why)
    invariants("alias")
  end

  -- ── 14. the acknowledgement ──────────────────────────────────────────────────────────────────────────────────
  do
    fresh()
    enter("Maraudon"); play(100); kill(422, "Noxxion", 30); leave(); expire()
    enter("Maraudon"); play(50)
    local c = me()
    local before, openBefore = deepcopy(c.dungeonRuns), deepcopy(c.dungeonRun)
    local ack = { sessions = {}, through = M.epoch + 10 * 86400 }
    for id in pairs(ns.DB.sessions) do ack.sessions[id] = true end
    ns.applyAck(ack, "file")
    local left = 0
    for _, e in ipairs(ns.DB.story.events) do if e.kind == "DUNGEON" or e.kind == "KILL" or e.kind == "BOSS" then left = left + 1 end end
    check("14: an ack that empties story events and fights leaves the runs untouched", left == 0 and #ns.DB.combat.fights == 0 and same(c.dungeonRuns, before) and same(c.dungeonRun, openBefore), left)
    check("14: the list still shows them", #R.views() == 2 and R.views()[1].bossesDown == 1 and R.views()[2].inProgress == true)
    invariants("14")
  end

  -- ── 15. the cap, and the size of a record ────────────────────────────────────────────────────────────────────
  local function svText(v, depth, out)
    -- the client's SavedVariables layout: one value per line, tab indented, ["key"] = value, array items with -- [i]
    local t = type(v)
    if t == "table" then
      local n = 0
      while v[n + 1] ~= nil do n = n + 1 end
      local pad = ("\t"):rep(depth + 1)
      out[#out + 1] = "{\n"
      for i = 1, n do out[#out + 1] = pad; svText(v[i], depth + 1, out); out[#out + 1] = (", -- [%d]\n"):format(i) end
      for k, x in pairs(v) do
        if not (type(k) == "number" and k >= 1 and k <= n) then
          out[#out + 1] = pad .. "[" .. (type(k) == "string" and ('"' .. k .. '"') or tostring(k)) .. "] = "
          svText(x, depth + 1, out); out[#out + 1] = ",\n"
        end
      end
      out[#out + 1] = ("\t"):rep(depth) .. "}"
    elseif t == "string" then out[#out + 1] = '"' .. v .. '"'
    else out[#out + 1] = tostring(v) end
  end
  local function svSize(v) local out = {}; svText(v, 4, out); return #table.concat(out) end
  do
    fresh()
    local c = me()
    c.dungeonRuns = {}
    for i = 1, R.CAP do c.dungeonRuns[i] = T.runRecord("Maraudon", M.epoch - 100000 + i * 100, 90) end
    c.dungeonRuns[1].keep = true
    local second, third = c.dungeonRuns[2].id, c.dungeonRuns[3].id
    local first = c.dungeonRuns[1].id
    enter("Maraudon"); play(100); leave(); expire()
    check("15: the 101st run evicts the oldest without keep", #c.dungeonRuns == R.CAP and R.CAP == 100 and c.dungeonRuns[1].id == first and c.dungeonRuns[2].id == third and c.dungeonRuns[2].id ~= second
      and c.dungeonRuns[R.CAP].secs.inside == 100, #c.dungeonRuns)
    invariants("15")
  end

  -- ── the real shape: Maraudon, 2026-11-18 20:32, two visits around a ghost run, 8 bosses, 1 death ─────────────
  do
    fresh()
    M.epoch = 1795033978
    local t0 = M.epoch
    local function dungeonEvents() local n = 0; for _, e in ipairs(ns.DB.story.events) do if e.kind == "DUNGEON" then n = n + 1 end end return n end
    enter("Maraudon")
    play(288)
    combat(true); play(33)                                       -- fight 216 opens 20:37:46
    START(422, "Noxxion"); play(52); END(422, "Noxxion", 1)      -- START 20:38:19
    combat(false)
    play(127); kill(423, "Razorlash", 40)
    play(110); kill(424, "Lord Vyletongue", 50)
    play(150)
    combat(true); play(13); die(); combat(false)                 -- 20:47:21
    play(17); leave()                                            -- released: out as a ghost
    play(180)
    enter("Maraudon"); play(19); rise()                          -- alive 20:50:57
    for i, nm in ipairs({ "Meshlok the Harvester", "Celebras the Cursed", "Landslide", "Princess Theradras", "Tinkerer Gizlock" }) do
      play(500); loot(73); item(9001); kill(424 + i, nm, 60)
    end
    M.xp = 900; M.fire("PLAYER_XP_UPDATE")
    M.fire("CHAT_MSG_COMBAT_XP_GAIN", "Theradrim Guardian dies, you gain 800 experience.")
    play(120)
    leave(); expire()
    local r = last()
    check("Maraudon: one run for the evening's clear, two visits around the ghost run", #closed() == 1 and r.t == t0 and #r.visits == 2 and r.visits[1].out == "ghost" and r.visits[2].how == "ghost", #closed())
    check("Maraudon: the session counts one dungeon run where it counted two DUNGEON events", ns.Recorder.current().dungeons == 1 and dungeonEvents() == 2, dungeonEvents())
    check("Maraudon: 8 bosses killed, one death with the time back on its feet", #r.bosses == 8 and R.views()[1].bossesDown == 8 and r.nDeaths.me == 1 and r.deaths[1].back == 216 and r.deaths[1].enc == nil, #r.bosses)
    check("Maraudon: three minutes of running back, on the run's clock and apart from inside", r.secs.ghost == 180 and r.secs.outside == 0 and r.secs.wall == r.secs.inside + 180)
    check("Maraudon: the first boss: 52 s of encounter inside 85 s of fight, pulled 20:38:19", r.bosses[1].combat == 52 and r.bosses[1].kill - r.bosses[1].combat == 321 and r.firstPull == 288)
    check("Maraudon: its XP and its coin are on it", r.xp and r.xp.gain == 800 and r.xp.n == 1 and r.xp.kill == 800 and r.gold.looted == 365 and r.gold.items == 5, r.xp and r.xp.gain)
    -- Size (plan 4.6: the whole save file is uploaded at every /reload and logout). Measured as the client writes
    -- it, at the depth a run sits at in the file (EverbuffDB.characters[guid].dungeonRuns[i]).
    local stored = raw()
    local size = svSize(stored)
    -- (budget per milestone: 0.9.50 measured 2903 bytes; 0.9.51 adds the gap before a visit, per visit combat and boss
    -- seconds, the group size and the best mark, 3025 bytes measured)
    check("15: the real Maraudon shape is under 3 KB in the save file (0.9.51 budget)", size < 3 * 1024, size)
    local hundred = {}
    for i = 1, R.CAP do hundred[i] = deepcopy(stored) end
    local all = svSize(hundred)
    check("15: 100 stored runs of the real shape, serialised together, are under 320 KB per character (0.9.51 budget, 310 KB measured)", all < 320 * 1024, all)
    realPrint(("dungeon run size: the Maraudon shape (2 visits, 8 bosses, 1 death) is %d bytes in SavedVariables format; 100 of them %.0f KB"):format(size, all / 1024))
    invariants("Maraudon")
    -- The worst case at the caps of this version, every optional key present and not 0: 20 visits with every
    -- counter, 20 bosses with every count and a long name, 40 death rows, XP, the partial mark. Built full and
    -- closed the way a run is (Runs.lean), so the rows past Runs.DEATH_FULL keep no `foe` and `back`.
    local worst = deepcopy(stored)
    worst.partial, worst.firstPull, worst.keep = "ended while a boss was in progress", 12345, true
    worst.size, worst.done, worst.pb, worst.exact, worst.edited = 40, true, true, true, true
    worst.secs = { inside = 86399, ghost = 12345, outside = 23456, offline = 34567, active = 45678, combat = 23456, boss = 12345 }
    worst.xp = { gain = 123456, kill = 98765, quest = 23456, n = 1234, l0 = 59, l1 = 60, p0 = 0.123, p1 = 0.987, need = 209800 }
    worst.hidden, worst.nDeaths = { xp = 1234, rep = 1234, loot = 1234 }, { me = 45, party = 45 }
    worst.gold = { looted = 1234567, quests = 123456, lootValue = 1234567, items = 123, unpriced = 12, purse = 1234567 }
    worst.visits, worst.bosses, worst.deaths = {}, {}, {}
    for i = 1, R.VISIT_CAP do
      worst.visits[i] = { i = 80000 + i, o = 80100 + i, how = "reload", out = "offline", n = 12, secs = 12345, active = 12345, xp = 12345, xpKill = 12345, xpQuest = 12345, kills = 123,
        looted = 12345, quests = 12345, lootValue = 12345, items = 123, unpriced = 12, purse = 12345, combat = 12345, boss = 12345, gg = 1234, go = 1234, gf = 1234 }
    end
    for i = 1, R.BOSS_CAP do
      worst.bosses[i] = { enc = 12345 + i, name = "High Interrogator Gerstahn the Unseen", pulls = 12, wipes = 11, resets = 10, unknown = 10, combat = 12345, kill = 12345 + i, ok = 1, dur = 123,
        fight = "Hart-Realm-1795033978-216-a1b2", p = 1234 }
    end
    for i = 1, R.DEATH_CAP do worst.deaths[i] = { o = 40000 + i, enc = 12345, foe = "High Interrogator Gerstahn", back = 1234 } end
    worst.visits[R.VISIT_CAP].gaps = {}
    for k = 1, R.GAP_CAP do local g = worst.visits[R.VISIT_CAP].gaps; g[#g + 1] = 81000 + 20 * k; g[#g + 1] = 81010 + 20 * k end
    R.lean(worst)
    local missing = {}
    for _, k in ipairs(R.LEAN_VISIT) do if worst.visits[R.VISIT_CAP][k] == nil then missing[#missing + 1] = k end end
    if #(worst.visits[R.VISIT_CAP].gaps or {}) ~= 2 * R.GAP_CAP then missing[#missing + 1] = "gaps" end
    for _, k in ipairs({ "pulls", "wipes", "resets", "unknown", "kill", "dur", "fight", "name", "p" }) do if worst.bosses[R.BOSS_CAP][k] == nil then missing[#missing + 1] = k end end
    for _, k in ipairs({ "gg", "go", "gf" }) do if worst.visits[R.VISIT_CAP][k] == nil then missing[#missing + 1] = k end end
    check("15: the worst case carries every optional key on every row, and is a record of the contract", #missing == 0 and contract(worst, false) == nil and R.valid(worst)
      and worst.deaths[R.DEATH_FULL].foe ~= nil and worst.deaths[R.DEATH_FULL + 1].foe == nil and worst.deaths[R.DEATH_CAP].back == nil and worst.deaths[R.DEATH_CAP].enc == 12345,
      table.concat(missing, ",") .. " " .. tostring(contract(worst, false)))
    -- a boss row never killed keeps the raw answer of its END on the stored record (what the wipe probe reads)
    local unk = T.runRecord("The Deadmines", 1000, 100, { bosses = { { enc = 1, name = "Rhahk'Zor", pulls = 2, wipes = 1, resets = 0, unknown = 0, combat = 50, ok = 0, dur = 20 } } }).bosses[1]
    check("15: lean keeps ok and dur on a boss row with no kill", unk.ok == 0 and unk.dur == 20 and unk.wipes == 1 and unk.resets == nil, tostring(unk.ok))
    local wsize = svSize(worst)
    check("15: the worst case at the caps is under 25 KB (0.9.51 budget: measured 23.8 KB with 20 gaps and the keys of 0.9.51; plan 4.6 names 3 KB as a target to be measured)", wsize < 25 * 1024, wsize)
    realPrint(("dungeon run size: worst case at the caps (20 visits, 20 gaps, 20 bosses, 40 deaths, every key) is %d bytes"):format(wsize))
    -- the caps themselves
    fresh()
    enter("Maraudon")
    for i = 1, 25 do play(10); leave(true); play(10); enter("Maraudon", { noLoad = true }) end
    check("caps: after 20 visits the last row takes every later stretch", #open().visits == R.VISIT_CAP and open().visits[R.VISIT_CAP].n == 6 and open().secs.inside == 250 and open().secs.outside == 250, #open().visits)
    for i = 1, 25 do START(5000 + i, "Boss " .. i); END(5000 + i, "Boss " .. i, 1) end
    check("caps: at most 20 boss rows", #open().bosses == R.BOSS_CAP)
    for i = 1, 45 do die(); M.dead = false; M.fire("PLAYER_UNGHOST") end
    check("caps: at most 40 death rows, the counter is never capped", #open().deaths == R.DEATH_CAP and open().nDeaths.me == 45 and R.DEATH_CAP == 40 and R.VISIT_CAP == 20 and R.BOSS_CAP == 20)
    invariants("caps")
  end

  -- ── a run with nothing in it; a record this version cannot read ──────────────────────────────────────────────
  do
    fresh()
    enter("Maraudon"); play(30); leave(); expire()
    check("empty: under 60 s with no fight, loot or XP is not kept", open() == nil and #closed() == 0 and notes().discarded == 1)
    enter("Maraudon"); play(30); loot(5); leave(); expire()
    check("empty: under 60 s with coin in it is kept", #closed() == 1 and last().gold.looted == 5)
    -- on load, a record of a later version or of another shape is dropped
    local c = me()
    local good = raw()
    local later = T.runRecord("Uldaman", M.epoch - 500, 100, { v = R.V + 1 })
    local broken = T.runRecord("Uldaman", M.epoch - 400, 100); broken.secs = nil
    c.dungeonRuns = { later, good, "junk", broken }
    c.dungeonRun = { v = 1, id = "x", inst = "Uldaman" }
    reload(9)
    check("load: a record with a higher version or a wrong shape is dropped, the rest stays", #c.dungeonRuns == 1 and c.dungeonRuns[1] == good and c.dungeonRun == nil and notes().dropped == 4, #c.dungeonRuns)
    invariants("empty")
  end

  -- ── 16. two characters ───────────────────────────────────────────────────────────────────────────────────────
  do
    fresh()
    enter("Maraudon"); play(100); kill(422, "Noxxion", 30)
    local hart = deepcopy(me())
    local UT = "Player-1-0000UT"
    _G.UnitGUID = function(u) if u == "player" then return UT end return real.guid(u) end
    check("16: another character sees none of the first one's runs", #R.views() == 0 and (ns.char().dungeonRun == nil) and ns.char().dungeonRuns == nil)
    T.newLoad(); pew(true); play(50)
    check("16: and opens its own in its own block", ns.DB.characters[UT].dungeonRun ~= nil and ns.DB.characters[UT].dungeonRun.id ~= hart.dungeonRun.id and #R.views() == 1)
    check("16: the first character's run is untouched by it", same(ns.DB.characters[ME].dungeonRun, hart.dungeonRun))
    _G.UnitGUID = real.guid
    ns.DB.characters[UT] = nil
    T.newLoad()
    invariants("16")
  end

  -- ── 17. XP ───────────────────────────────────────────────────────────────────────────────────────────────────
  do
    fresh()
    M.xp, M.xpmax, M.level = 100, 1000, 12
    M.fire("PLAYER_XP_UPDATE")
    enter("Maraudon")
    check("17: the run notes where the level stood", open().xp and open().xp.l0 == 12 and open().xp.p0 == 0.1 and open().xp.gain == 0)
    play(60)
    M.xp = 400; M.fire("PLAYER_XP_UPDATE")
    M.fire("CHAT_MSG_COMBAT_XP_GAIN", "Defias Thug dies, you gain 85 experience.")
    M.fire("CHAT_MSG_COMBAT_XP_GAIN", "You gain 40 experience.")
    M.xp, M.xpmax, M.level = 50, 1200, 13; M.fire("PLAYER_XP_UPDATE")       -- a level-up: 600 of the old bar, 50 of the new
    M.fire("QUEST_TURNED_IN", 4242, 200, 0)
    check("17: XP across a level-up is the rest of the old bar plus the new one", open().xp.gain == 950 and open().visits[1].xp == 950, open().xp.gain)
    check("17: a named kill line is one kill and its XP; the unnamed form counts no kill", open().xp.n == 1 and open().xp.kill == 85 and open().visits[1].kills == 1 and open().visits[1].xpKill == 85)
    check("17: quest XP inside is kept apart", open().xp.quest == 200 and open().visits[1].xpQuest == 200)
    leave()
    M.xp = 550; M.fire("PLAYER_XP_UPDATE")
    M.fire("QUEST_TURNED_IN", 4243, 500, 0)
    M.fire("CHAT_MSG_COMBAT_XP_GAIN", "Kobold Miner dies, you gain 30 experience.")
    check("17: XP, quests and kills outside are not in the run", open().xp.gain == 950 and open().xp.quest == 200 and open().xp.n == 1)
    expire()
    local r = last()
    check("17: the closed run keeps the levels at both ends and the bar it ended on: the last reading inside", r.xp.gain == 950 and r.xp.l0 == 12 and r.xp.l1 == 13 and r.xp.p1 == 0.042
      and r.xp.need == 1200, r.xp.p1)
    invariants("17")
    -- XP and a level-up outside, inside the 20 minutes before the run closes, do not move the end of the block
    fresh()
    M.xp, M.xpmax, M.level = 100, 1000, 12
    M.fire("PLAYER_XP_UPDATE")
    enter("Maraudon"); play(60)
    M.xp = 300; M.fire("PLAYER_XP_UPDATE")
    check("17: an open run carries where the level stands", open().xp.l1 == 12 and open().xp.p1 == 0.3 and open().xp.need == 1000)
    leave()
    play(300)
    M.xp, M.xpmax, M.level = 50, 1200, 13; M.fire("PLAYER_XP_UPDATE")
    expire()
    r = last()
    check("17: a level-up outside after leaving does not move the run's end level", r.xp.gain == 200 and r.xp.l0 == 12 and r.xp.l1 == 12 and r.xp.p1 == 0.3 and r.xp.need == 1000, r.xp.l1 .. " " .. r.xp.p1)
    check("17: the page reads the levels inside, and how many such runs the level still takes", select(1, R.xpLine(R.views()[1])) == "200 XP" .. SEP .. "level 12.1 to 12.3", (R.xpLine(R.views()[1])))
    M.xp, M.xpmax, M.level = 100, 1000, 12
    invariants("17 outside")
    -- no XP block when the maximum is not a plain positive number (level cap, or hidden)
    fresh()
    M.xpmax = 0
    enter("Maraudon"); play(60)
    M.xp = 400; M.fire("PLAYER_XP_UPDATE")
    M.fire("CHAT_MSG_COMBAT_XP_GAIN", "Defias Thug dies, you gain 85 experience.")
    check("17: no XP block when the XP maximum is not a plain positive number", open().xp == nil and open().visits[1].xp == 0 and R._err == nil)
    check("17: (and the view reads no XP)", R.views()[1].xpGain == 0 and R.views()[1].xpPerHour == nil)
    loot(10); leave(); expire()
    check("17: and none on the record", last().xp == nil and R.xpLine(R.views()[1]) == nil)
    fresh()
    enter("Maraudon"); play(60); loot(10); leave(); expire()
    check("17: a run in which nothing was gained carries no XP block", last().xp == nil)
    M.xpmax = 1000
    invariants("17b")
  end

  -- ── 18. secret values at every entry point ───────────────────────────────────────────────────────────────────
  do
    fresh()
    enter("Maraudon"); play(60)
    local e0 = errs()
    local S = M.secrets
    S[777001], S[424242], S["Hidden Boss"], S["Hidden line"], S[31337] = true, true, true, true, true
    START(777001, "Noxxion")
    check("18: an encounter whose id is hidden is not recorded", #open().bosses == 0 and open().encs == nil and errs() == e0 and R._err == nil, R._err)
    END(777001, "Noxxion", 1)
    START(5001, "Hidden Boss")
    check("18: an encounter whose name is hidden is recorded without a name", #open().bosses == 1 and open().bosses[1].name == nil and open().bosses[1].pulls == 1)
    END(5001, "Hidden Boss", 424242)
    check("18: an END whose success is hidden is an unseen outcome, never compared", open().bosses[1].unknown == 1 and open().bosses[1].kill == nil and open().bosses[1].ok == nil)
    M.fire("CHAT_MSG_COMBAT_XP_GAIN", "Hidden line")
    M.fire("CHAT_MSG_LOOT", "Hidden line")
    M.fire("CHAT_MSG_COMBAT_FACTION_CHANGE", "Hidden line")
    M.fire("CHAT_MSG_COMBAT_FACTION_CHANGE", "Reputation with Stormwind increased by 25.")
    check("18: chat lines the client hides inside are counted by kind, never read", open().hidden.xp == 1 and open().hidden.loot == 1 and open().hidden.rep == 1, open().hidden.xp)
    M.fire("QUEST_TURNED_IN", 4242, 424242, 0)
    local xp0, max0 = M.xp, M.xpmax
    M.xp = 777001; M.fire("PLAYER_XP_UPDATE")
    check("18: hidden XP values are skipped", open().xp.gain == 0 and open().xp.quest == 0)
    M.xp = xp0; M.fire("PLAYER_XP_UPDATE")
    local m0 = M.money
    M.money = 31337
    leave()
    check("18: a hidden purse leaves the purse check at 0", open().visits[1].purse == 0)
    M.money = m0
    enter("Maraudon"); play(30)
    local realDead = _G.UnitIsDeadOrGhost
    _G.UnitIsDeadOrGhost = function() return "Hidden line" end      -- an answer that is no plain boolean
    leave()
    _G.UnitIsDeadOrGhost = realDead
    check("18: a dead-or-ghost answer the addon may not test counts as alive", open().st == "out")
    -- hidden lines outside, in the 20 minutes the run waits: none is the run's
    local h0 = deepcopy(open().hidden)
    M.fire("CHAT_MSG_LOOT", "Hidden line"); M.fire("CHAT_MSG_COMBAT_FACTION_CHANGE", "Hidden line"); M.fire("CHAT_MSG_COMBAT_XP_GAIN", "Hidden line")
    check("18: chat lines hidden outside are not counted on the run", same(open().hidden, h0), open().hidden.loot)
    enter("Maraudon")
    M.fire("CHAT_MSG_LOOT", "Hidden line")
    check("18: back inside, the next one is", open().hidden.loot == h0.loot + 1 and open().hidden.rep == h0.rep and open().hidden.xp == h0.xp, open().hidden.loot)
    leave()
    expire()
    check("18: no handler threw on any of it", errs() == e0 and R._err == nil, M.errors[#M.errors] or R._err)
    check("18: the hidden lines end up on the record and in the page's wording", last().hidden.xp == 1 and last().hidden.loot == 2 and last().hidden.rep == 1)
    S[777001], S[424242], S["Hidden Boss"], S["Hidden line"], S[31337] = nil, nil, nil, nil, nil
    invariants("18")
  end

  -- ── a load is read before anything is put on a clock ─────────────────────────────────────────────────────────
  do
    -- logged out inside after 100 s, back 8 hours later: whatever reaches the addon before the login's world entry
    -- (a tick, a zone event, a look at the pane, a boss event, a second logout) books nothing
    for _, how in ipairs({ "tick", "zone", "view", "boss", "logout" }) do
      fresh()
      enter("Maraudon"); play(100)
      M.fire("PLAYER_LOGOUT"); G._tickAt = nil; T.newLoad(); adv(8 * 3600)
      if how == "tick" then R.tick()
      elseif how == "zone" then M.fire("ZONE_CHANGED_NEW_AREA")
      elseif how == "view" then R.views(true); R.view(open(), true, true)
      elseif how == "boss" then START(422, "Noxxion")
      else M.fire("PLAYER_LOGOUT") end
      check("load: a " .. how .. " before the login's world entry puts nothing on a clock", open() and open().secs.inside == 100 and open().visits[1].secs == 100 and #open().bosses == 0
        and open().st == "in" and open().gap == nil, open() and open().secs.inside)
      pew(true); R.tick()
      check("load: after a " .. how .. " the hours are offline, never inside", open() and open().secs.inside == 100 and open().secs.offline == 8 * 3600 and #open().visits == 2
        and open().visits[1].secs == 100 and open().visits[1].out == "offline", open() and open().secs.inside)
      invariants("load " .. how)
    end
  end

  -- ── alive again as a ghost: inside or outside is asked, never assumed ─────────────────────────────────────────
  do
    -- died on a boss, released, ran back 60 s. Walking in resurrects the character, and the event (or the tick that
    -- sees the character alive) comes before the dungeon check of the loading screen; the party kills 20 s later.
    for _, how in ipairs({ "event", "tick" }) do
      fresh()
      enter("Maraudon"); play(100)
      START(429, "Celebras the Cursed"); play(20); die(); play(5); leave()
      play(60)
      place("Maraudon"); M.dead = false
      if how == "event" then M.fire("PLAYER_UNGHOST") else R.tick() end
      local run = open()
      check("ghost: alive inside before the loading screen's check (" .. how .. ") begins the visit and keeps the encounter open", run.st == "in" and #run.visits == 2 and run.visits[2].how == "ghost"
        and run.left == nil and run.encs and run.encs[429] ~= nil and boss(run, 429).unknown == 0 and run.deaths[1].back == 65, run.st)
      pew()
      check("ghost: the check that follows (" .. how .. ") changes nothing", #open().visits == 2 and open().encs and open().encs[429] ~= nil)
      play(20); END(429, "Celebras the Cursed", 1)
      local b = boss(open(), 429)
      check("ghost: the kill the party made counts (" .. how .. ")", b.kill == 205 and b.unknown == 0 and b.pulls == 1 and open().secs.boss == 105 and open().secs.ghost == 60
        and (notes().endNoStart or 0) == 0, tostring(b.kill))
      invariants("ghost " .. how)
    end
    -- the 30 minutes, to the letter
    check("ghost: the cap is 30 minutes", R.GHOST_CAP == 1800)
    fresh()
    enter("Maraudon"); play(100); die(); leave()
    play(29 * 60)
    check("ghost: 29 minutes as a ghost outside: still the run", open() ~= nil and #closed() == 0)
    play(2 * 60)
    check("ghost: 31 minutes: over", open() == nil and last().why == "ghost")
    M.dead = false
    invariants("ghost cap")
  end

  -- ── the boss clock and the encounter state machine, the cases a favourable order hides ─────────────────────────
  do
    -- an encounter whose END fired during the loading screen of a /reload stays open, and holds nothing up
    fresh()
    enter("Maraudon"); play(100)
    START(428, "Tinkerer Gizlock"); play(10)
    reload(9)
    check("boss clock: an encounter open across a /reload is carried", open().encs[428] ~= nil and open().encs[428].r == 1)
    play(21); kill(422, "Noxxion", 40); play(30); kill(423, "Razorlash", 30)
    check("boss clock: an encounter whose END was missed does not freeze the clock", open().secs.boss == 70 and open().encs[428] ~= nil, open().secs.boss)
    -- two encounters that overlap in part: the union of their windows, counted once
    START(601, "Shadowpriest Sezz'ziz"); play(10); START(602, "Nekrum Gutchewer"); END(601, "Shadowpriest Sezz'ziz", 1); play(5); END(602, "Nekrum Gutchewer", 1)
    check("boss clock: two staggered encounters count the union of their windows", open().secs.boss == 70 + 15 and boss(open(), 601).combat == 10 and boss(open(), 602).combat == 5, open().secs.boss)
    -- one encounter inside another, the inner one ending first: still the union (50 + 30 + 20, not 50)
    START(603, "Hydromancer Velratha"); play(50); START(604, "Gahz'rilla"); play(30); END(604, "Gahz'rilla", 1); play(20); END(603, "Hydromancer Velratha", 1)
    check("boss clock: an encounter that ends inside another counts the union of their windows", open().secs.boss == 85 + 100 and boss(open(), 603).combat == 100 and boss(open(), 604).combat == 30, open().secs.boss)
    START(605, "Witch Doctor Zum'rah"); play(10); END(605, "Witch Doctor Zum'rah", 1)
    check("boss clock: a later pull counts its own window, nothing of the earlier ones", open().secs.boss == 85 + 110, open().secs.boss)
    check("boss clock: the windows kept are only those an open encounter can still meet", open().bossWin ~= nil and #open().bossWin >= 1 and open().encs[428] ~= nil, open().bossWin and #open().bossWin)
    R.endNow()
    local r = last()
    check("boss clock: a run ended from inside with only a carried encounter open did not end mid-boss", r.why == "manual" and r.partial == nil and boss(r, 428).unknown == 1 and r.secs.boss == 195, tostring(r.partial))
    invariants("boss clock")

    -- a kill is stored once
    fresh()
    enter("Maraudon"); play(100)
    kill(422, "Noxxion", 30)
    combat(false)                                               -- (the fight the pull opened ends: the next pull is another fight)
    local first = deepcopy(boss(open(), 422))
    play(100); kill(422, "Noxxion", 20)
    local b = boss(open(), 422)
    check("kill: a second kill of the same boss changes neither the kill nor its fight", first.kill == 130 and b.kill == 130 and first.fight ~= nil and b.fight == first.fight and seg(open(), 422) == 30, tostring(b.kill))
    check("kill: it counts the pull and its combat", b.pulls == 2 and b.combat == 50 and b.dur == 20)
    -- a death outside is no death of the run
    leave(); die()
    check("death: dying outside while the run is still open is not a death of the run", open().nDeaths.me == 0 and #open().deaths == 0 and open().st == "out")
    rise()
    invariants("kill once")

    -- a boss pulled where the detector does not say inside, with a run still open
    fresh()
    enter("Maraudon"); play(100)
    local id = open().id
    walk("Maraudon", 1)                                         -- out through the portal with no loading screen event: the door
    check("expire: (at the door the run waits its 20 minutes)", open() and open().st == "out" and R._where == "door")
    adv(21 * 60)                                                -- no tick and no zone event in that time
    START(426, "Princess Theradras")
    check("expire: a boss pulled 21 minutes after leaving is a new run, the old one closed as left", #closed() == 1 and last().why == "left" and last().id == id and open() and open().id ~= id
      and open().open == "boss" and open().inst == "Maraudon" and #open().visits == 1, #closed())
    invariants("expire at a pull")
    fresh()
    enter("Maraudon"); play(100); leave()
    walk("Shadowfang Keep")
    START(1069, "Rethilgore")
    check("expire: a boss pulled at another dungeon's door closes the open run, why other", #closed() == 1 and last().why == "other" and last().inst == "Maraudon" and open() and open().inst == "Shadowfang Keep"
      and open().open == "boss", last() and last().why)
    invariants("another door")

    -- active seconds of a visit that began inside the tick's interval
    fresh()
    enter("Maraudon"); play(100); leave(true)
    adv(57); enter("Maraudon", { noLoad = true }); adv(3); R.tick(); G.tick(); leave(true)
    check("active: a visit of 3 s takes 3 active seconds from the tick, not the tick's 10", open().visits[2].secs == 3 and open().visits[2].active == 3 and open().secs.inside == 103 and open().secs.active == 103,
      open().visits[2].active)
    invariants("short visit")
  end

  -- ── the logout itself, and what a login finds ───────────────────────────────────────────────────────────────
  do
    -- 7 s after the last tick, in combat, with coin looted since
    fresh()
    enter("Maraudon"); play(300)
    combat(true); adv(7); loot(40)
    M.inCombat = false
    relog(8 * 3600)
    local run = open()
    check("logout: the seconds, the combat and the purse since the last tick are booked at the logout", run and run.secs.inside == 307 and run.visits[1].secs == 307 and run.visits[1].o == 307
      and run.secs.combat == 11 and run.visits[1].purse == 40 and run.visits[1].looted == 40 and run.secs.offline == 8 * 3600, run and (run.secs.inside .. " " .. run.secs.combat))
    invariants("logout between ticks")
    -- a boss in progress at a clean logout was not seen ending
    fresh()
    enter("Maraudon"); play(100)
    START(426, "Princess Theradras"); play(20)
    relog(600)
    check("logout: an encounter open at a clean logout is unseen at the login", open() and boss(open(), 426).unknown == 1 and boss(open(), 426).kill == nil and open().encs == nil and #open().visits == 2,
      open() and boss(open(), 426).unknown)
    invariants("logout mid boss")
    -- logged out inside, dead; back outside, still dead: running back, with its 30 minutes
    fresh()
    enter("Maraudon"); play(100); die()
    M.fire("PLAYER_LOGOUT"); G._tickAt = nil; T.newLoad(); adv(3600); outside(); pew(true); R.tick()
    check("logout: logged out inside, back outside as a ghost: the run is running back from the login", open() and open().st == "ghost" and open().ghostAt == M.epoch and open().left == nil)
    play(R.GHOST_CAP)
    check("logout: the ghost's 30 minutes count from that login", open() ~= nil)
    play(10)
    check("logout: and end the run where it was last inside", open() == nil and last().why == "ghost" and last().secs.wall == 100 and last().secs.offline == 0)
    M.dead = false
    invariants("logout dead")
    -- the purse moved while offline (mail taken on another login is not this run's)
    fresh()
    enter("Maraudon"); play(100)
    M.fire("PLAYER_LOGOUT"); G._tickAt = nil; T.newLoad(); adv(3600); M.money = M.money + 5000; pew(true); R.tick()
    play(20); leave()
    check("logout: a purse that changed while offline is in no visit", #open().visits == 2 and open().visits[1].purse == 0 and open().visits[2].purse == 0, open().visits[1].purse)
    invariants("logout purse")
    -- the crash is known only by the mark on the character (the load was read late: Emitter had not said so)
    fresh()
    enter("Maraudon"); play(200)
    M.fire("PLAYER_LOGOUT"); G._tickAt = nil; T.newLoad(); adv(3600)
    me().goldOpen = M.epoch - 3600
    E._crashed = nil
    R.loaded(true, false)
    check("crash: the mark of an unsaved stretch on the character alone closes the run as lost", open() == nil and last() and last().why == "lost" and last().partial == "state lost before this login",
      last() and last().why)
    me().goldOpen = nil
    invariants("crash mark")
  end

  -- ── gold: the counters of every gold run together, not the open one alone ────────────────────────────────────
  do
    -- the gold run closes in the middle of one visit: the dungeon's name flips to one the addon does not know, on
    -- another map, with no loading screen (the gold run follows the name, the dungeon run keeps its visit)
    fresh()
    enter("Alcaz Island", { name = "Alcaz Prison", map = 4500 }); play(60)
    loot(500)
    local gr = me().goldRun
    enter("Alcaz Island", { name = "Alcaz Vault", map = 4501, noLoad = true })
    check("gold: (the name flip closed the gold run and opened another, the dungeon run kept its visit)", gr ~= nil and me().goldRun ~= gr and #(me().goldRuns or {}) == 1 and #open().visits == 1 and #closed() == 0)
    loot(300); play(60)
    leave(); expire()
    local r = last()
    check("gold: a visit holds the coin of a gold run that closed inside it and of the one after", r.gold.looted == 800 and #r.visits == 1 and r.visits[1].looted == 800, r.gold.looted)
    invariants("gold closed inside")
    -- the same, and the close pushes the oldest stored gold run into the evicted sum
    fresh()
    local c = me()
    c.goldRuns = {}
    for i = 1, G.RUN_CAP do c.goldRuns[i] = { t = M.epoch - 100000 + i, inst = "Old Run", secs = 100, looted = 1000, quests = 0, lootValue = 0, items = 0 } end
    enter("Alcaz Island", { name = "Alcaz Prison", map = 4500 }); play(60)
    loot(500)
    enter("Alcaz Island", { name = "Alcaz Vault", map = 4501, noLoad = true })
    check("gold: (the close evicted the oldest gold run into the sum)", #c.goldRuns == G.RUN_CAP and type(c.goldRunsEvicted) == "table" and c.goldRunsEvicted.looted == 1000, c.goldRunsEvicted and c.goldRunsEvicted.looted)
    loot(300); play(60)
    leave(); expire()
    r = last()
    check("gold: a gold run evicted during the visit takes no coin out of it", r.gold.looted == 800 and r.visits[1].looted == 800, r.gold.looted)
    invariants("gold evicted inside")

    -- the purse gained less than was looted: coin was spent inside
    fresh()
    enter("Maraudon"); play(60); loot(5000); money(-2000); leave(); expire()
    r = last()
    check("purse: looted more than the purse gained reads as that, never as 50 of 30", r.gold.looted == 5000 and r.gold.purse == 3000
      and R.purseLine(R.views()[1]) == ("Looted %s, purse up %s inside"):format(fmt(5000), fmt(3000)), R.purseLine(R.views()[1]))
    fresh()
    enter("Maraudon"); play(60); loot(50); money(-80); leave(); expire()
    r = last()
    check("purse: a purse that did not grow inside says nothing", r.gold.looted == 50 and r.gold.purse == -30 and R.purseLine(R.views()[1]) == nil, R.purseLine(R.views()[1]))
    invariants("purse spent")
  end

  -- ── of this run: by its visits, for the page and for the Fights list alike ───────────────────────────────────
  do
    fresh()
    enter("Maraudon"); play(100); leave(); play(60)
    local inT, gapT = M.epoch - 100, M.epoch - 10
    check("inRun: a moment after the leave is not the open run's, though the run stays open 20 minutes", open() and R.inRun(open(), M.epoch) == false and R.inRun(open(), inT) == true
      and R.runAt(M.epoch) == nil and R.runAt(inT) == open())
    enter("Maraudon"); play(50)
    check("inRun: back inside, now is the run's and the gap is not", R.inRun(open(), M.epoch) == true and R.inRun(open(), gapT) == false and R.runAt(gapT) == nil)
    local in2 = M.epoch
    leave(); expire()
    check("inRun: the same for the closed run", R.runAt(gapT) == nil and R.runAt(inT) == raw() and R.runAt(in2) == raw() and R.runAt(M.epoch) == nil and R.inRun(raw(), nil) == false)
    invariants("inRun")
  end

  -- ── the caps of what the addon learns about names ────────────────────────────────────────────────────────────
  do
    fresh()
    enter("Alcaz Island", { name = "Alcaz Prison", map = 4500 }); play(60)
    local A = {}
    for i = 1, R.ALIAS_CAP do A["some name " .. i] = "Some Dungeon" end
    ns.DB.settings.instanceAlias = A
    enter("Alcaz Island", { name = "Alcaz Island Prison", map = 4500, noLoad = true })
    local n = 0
    for _ in pairs(A) do n = n + 1 end
    check("caps: at most 40 learned names, the 41st is not learned", R.ALIAS_CAP == 40 and n == 40 and A["alcaz island prison"] == nil and ns.DB.settings.instanceAlias == A, n)
    for i = 1, R.CANDIDATE_CAP + 1 do enter("Alcaz Island", { name = "Vault " .. i, map = 4500 + i, noLoad = true }) end
    local L = ns.DB.settings.selftest.aliasCandidates
    local mine = {}
    for _, x in ipairs(L) do if tostring(x.to):find("^Vault ") then mine[#mine + 1] = x.to end end
    check("caps: at most 20 name questions, the oldest goes first", R.CANDIDATE_CAP == 20 and #L == 20 and mine[#mine] == "Vault 21" and L[#L].to == "Vault 21" and L[1].to ~= "Vault 1", #L)
    invariants("name caps")
  end

  -- ── 18b. the guards one at a time: each value hidden alone, with a result that tells ─────────────────────────
  do
    local S = M.secrets
    local e0 = errs()
    -- the XP maximum, then the level, hidden when the run opens
    fresh()
    S[987001] = true; M.xpmax = 987001
    enter("Maraudon")
    check("18: a hidden XP maximum when the run opens: no XP block", open() and open().xp == nil)
    M.xpmax = 1000; S[987001] = nil
    fresh()
    S[61] = true; M.level = 61
    enter("Maraudon"); play(60)
    check("18: a hidden level when the run opens is not stored", open().xp ~= nil and open().xp.l0 == nil and open().xp.l1 == nil and open().xp.p0 == 0.1)
    -- a hidden XP value small enough to pass for a gain
    S[150] = true; M.xp = 150; M.fire("PLAYER_XP_UPDATE")
    check("18: a hidden XP value that would pass for a gain of 50 is not counted", open().xp.gain == 0 and open().visits[1].xp == 0, open().xp.gain)
    S[150] = nil; M.xp = 100; M.fire("PLAYER_XP_UPDATE")
    M.xp = 160; M.fire("PLAYER_XP_UPDATE")
    check("18: and the next plain reading counts from the last plain one", open().xp.gain == 60 and open().xp.p1 == 0.16 and open().xp.l1 == nil, open().xp.gain)
    M.level = 12; S[61] = nil
    -- an END with a hidden name on a row that has none; an END with a hidden id while that encounter is open
    S["Hidden Boss"] = true
    START(5001, "Hidden Boss"); play(5); END(5001, "Hidden Boss", 1)
    check("18: an END whose name is hidden leaves the row without a name", boss(open(), 5001) and boss(open(), 5001).name == nil and boss(open(), 5001).kill ~= nil)
    START(5002, "Plain Boss"); play(5)
    S[5002] = true
    END(5002, "Plain Boss", 1)
    check("18: an END whose id is hidden ends nothing", open().encs and open().encs[5002] ~= nil and boss(open(), 5002).kill == nil)
    S[5002] = nil
    END(5002, "Plain Boss", 1)
    check("18: (the plain END does)", open().encs == nil and boss(open(), 5002).kill ~= nil)
    -- the detector's name hidden while a second name would be learned
    S["Maraudon Depths"] = true
    local det0 = E._det
    E._det = { kind = "party", name = "Maraudon Depths", sig = "type", zone = "Maraudon", map = open().map }
    local learned = R.alias()
    E._det = det0
    check("18: a hidden name is never learned as a second name", learned == false and (ns.DB.settings.instanceAlias or {})["maraudon depths"] == nil)
    S["Maraudon Depths"] = nil
    -- a hidden time handed to the dungeon check
    S[5] = true
    R.sync(5)
    S[5] = nil
    check("18: a hidden time is not put on the clock", open().mark == M.epoch and open().beat == M.epoch, open().mark)
    -- who killed the character: hidden, then plain, then through the client's own events
    die()
    R.deathFoe("Hidden Boss")
    check("18: a hidden killer is not stored", #open().deaths == 1 and open().deaths[1].foe == nil)
    R.deathFoe("Noxxion")
    check("18: a plain one is", open().deaths[1].foe == "Noxxion")
    rise()
    local ef = T.emitterFrame
    local had = ef.events.COMBAT_LOG_EVENT_UNFILTERED
    ef:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    M.cleu = { 0, "SWING_DAMAGE", false, "Creature-0-1-1-1-6-0077", "Lord Vyletongue", 0, 0, ME, "Hart" }
    M.fire("COMBAT_LOG_EVENT_UNFILTERED")
    die()
    check("18: the death event names the killer on the run's death row", #open().deaths == 2 and open().deaths[2].foe == "Lord Vyletongue", open().deaths[2] and open().deaths[2].foe)
    rise()
    M.cleu = nil
    if not had then ef:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED") end
    S["Hidden Boss"] = nil
    -- a dead-or-ghost answer that is a hidden boolean
    S[true] = true; M.dead = true
    local okLeave = pcall(leave)
    S[true] = nil; M.dead = false
    check("18: a hidden dead-or-ghost answer counts as alive", okLeave and open().st == "out" and open().left ~= nil, open().st)
    check("18: none of it threw", errs() == e0 and R._err == nil, M.errors[#M.errors] or R._err)
    invariants("18b")
  end

  -- ── 20. /eb run ──────────────────────────────────────────────────────────────────────────────────────────────
  do
    fresh()
    local sent = 0
    _G.SendChatMessage = function() sent = sent + 1 end
    said = {}
    SlashCmdList.EVERBUFF("run")
    check("20: /eb run with no run says so, and since when runs are kept", #said == 1 and said[1] == "run: no dungeon run yet. Runs are kept from version 0.9.50 on.", said[1])
    M.xp, M.xpmax = 100, 100000
    enter("Deadmines", { map = 36 })
    play(300); kill(644, "Rhahk'Zor", 30); die(); rise(); loot(23005)
    M.xp = 12400; M.fire("PLAYER_XP_UPDATE")
    play(270)
    said = {}
    M.inCombat = true
    SlashCmdList.EVERBUFF("run")
    M.inCombat = false
    local want = ("The Deadmines (in progress), 10m 0s, bosses 1, 1 death, 12,300 XP (73,800 per hour), %s."):format(fmt(23005))
    check("20: /eb run answers in combat with the open run", #said == 1 and said[1] == want, said[1])
    leave(); expire()
    said = {}
    SlashCmdList.EVERBUFF(" RUN ")
    check("20: with none open it reads the last run", #said == 1 and said[1] == want:gsub(" %(in progress%)", ""), said[1])
    check("20: it never calls a chat-sending function", sent == 0)
    _G.SendChatMessage = real.send
    M.xpmax = 1000
    invariants("20")
  end

  -- ── offline runs no clock outside; combat and a boss go on over a /reload and a split ──────────────────────────
  do
    -- left alive, 60 s outside, logged out 25 minutes, back outside: only the 90 s alive outside run the 20 minutes
    fresh()
    enter("Maraudon"); play(300)
    local id = open().id
    leave(); play(60)
    relog(25 * 60)
    check("offline: logged out outside, the run waits at the login with its 20 minutes where the logout left them", open() and open().id == id and open().st == "out"
      and open().left == M.epoch - 60 and #closed() == 0, open() and open().left)
    play(30); enter("Maraudon")
    local run = open()
    check("offline: back in: one run, two visits, the night offline and only the time alive outside outside", run and run.id == id and #closed() == 0 and #run.visits == 2
      and run.secs.offline == 1500 and run.secs.outside == 90 and run.secs.inside == 300, run and (run.secs.offline .. " " .. run.secs.outside))
    invariants("offline outside")
    -- the reviewer's shape: 2 minutes alive outside, 30 minutes offline, straight back in
    fresh()
    enter("Maraudon"); play(300); leave(); play(120)
    relog(30 * 60); enter("Maraudon")
    check("offline: 2 minutes outside and 30 offline is one run", #closed() == 0 and open() and #open().visits == 2 and open().secs.outside == 120 and open().secs.offline == 1800,
      open() and #open().visits)
    -- and the 20 minutes still end it, counted alive outside only
    leave(); play(R.REENTER - 120)
    relog(3600)
    check("offline: the 20 minutes alive outside are not over with an hour offline in them", open() ~= nil and #closed() == 0)
    play(130)
    check("offline: they end once 20 minutes alive outside are spent", open() == nil and last().why == "left" and last().secs.offline == 1800, open() and open().st)
    invariants("offline 20 minutes")
    -- logged out outside 10 minutes, back in, out, over: the closed run sums to its wall time
    fresh()
    enter("Maraudon"); play(100); leave(); play(30)
    relog(600); enter("Maraudon"); play(50); leave(); expire()
    check("offline: a closed run with an offline gap outside sums to its wall time", last().secs.wall == last().endT - last().t and last().secs.offline == 600 and last().secs.outside == 30
      and last().secs.inside == 150, last().secs.wall)
    invariants("offline wall")
    -- a ghost: 20 minutes running back, 15 offline, then in: one run, the ghost clock without the night
    fresh()
    enter("Maraudon"); play(100); die(); leave(); play(20 * 60)
    relog(15 * 60)
    check("offline: a ghost logged out 15 minutes after 20 running back is still running back", open() and open().st == "ghost" and #closed() == 0)
    enter("Maraudon"); rise()
    check("offline: back in: one run, 20 minutes running back, 15 offline", open() and #open().visits == 2 and open().secs.ghost == 1200 and open().secs.offline == 900 and #closed() == 0,
      open() and open().secs.ghost)
    invariants("offline ghost")
    -- the 30 minutes as a ghost are counted without the time offline
    fresh()
    enter("Maraudon"); play(100); die(); leave(); play(20 * 60)
    relog(15 * 60)
    play(10 * 60)
    check("offline: 20 + 10 minutes as a ghost around 15 offline: not over yet", open() ~= nil)
    play(20)
    check("offline: past 30 minutes as a ghost: over", open() == nil and last().why == "ghost" and last().secs.wall == 100)
    M.dead = false
    invariants("offline ghost cap")

    -- combat across a /reload: the logout books it to there, the load counts the rest, the reload's seconds included
    fresh()
    enter("Maraudon"); play(60)
    combat(true); play(30)
    reload(9)
    play(30); combat(false)
    check("combat: a combat over a /reload counts whole, as inside does", open().secs.combat == 69 and open().secs.inside == 129, open().secs.combat)
    invariants("combat reload")
    -- combat over a split: each run takes its own part
    fresh()
    enter("Maraudon"); play(60)
    combat(true); play(30)
    local rec = R.endNow()
    play(30); combat(false)
    check("combat: a combat over a split: 30 s on the old run, 30 s on the next", rec and rec.secs.combat == 30 and open() and open().secs.combat == 30 and open().firstPull == 0,
      open() and open().secs.combat)
    invariants("combat split")
    -- a boss over a split: the old run did not see it end, the kill lands on the next
    fresh()
    enter("Maraudon"); play(60)
    combat(true); START(422, "Noxxion"); play(20)
    rec = R.endNow()
    play(10); END(422, "Noxxion", 1); combat(false)
    local b = boss(open(), 422)
    check("boss: a run ended mid-boss says so and does not see the end", rec and rec.partial == "ended while a boss was in progress" and boss(rec, 422).unknown == 1 and boss(rec, 422).kill == nil)
    check("boss: the kill right after the split counts on the next run, its window from the cut", b and b.kill == 10 and (b.pulls or 1) == 1 and b.combat == 10 and open().secs.boss == 10
      and open().encs == nil and (notes().endNoStart or 0) == 0, b and b.kill)
    -- a death in the pull before the cut still makes a non-success END a wipe on the next run
    START(423, "Razorlash"); play(10); die(); play(2)
    R.endNow()
    rise(); play(5); END(423, "Razorlash", 0)
    check("boss: a death in the pull before the cut is carried with it", boss(open(), 423) and boss(open(), 423).wipes == 1, boss(open(), 423) and boss(open(), 423).wipes)
    invariants("boss split")
  end

  -- ── the list: All, Dungeons, Raids, one dungeon, and a sort on every column (plan 5.A) ────────────────────────
  do
    fresh()
    local lv = T.dungeonList and T.dungeonList()
    if lv then
      enter("Deadmines", { map = 36 }); play(300); kill(644, "Rhahk'Zor", 30); leave(); expire()
      enter("Molten Core", { type = "raid", map = 409 }); play(900); die(); rise(); leave(); expire()
      enter("Maraudon"); play(120); kill(422, "Noxxion", 20); kill(423, "Razorlash", 20); leave(); expire()
      enter("Deadmines", { map = 36 }); play(600); leave(); expire()
      local function names() local o = {}; T.dungeonList(); for _, r in ipairs(lv.shown) do o[#o + 1] = r.name .. ":" .. r.duration end; return table.concat(o, " ") end
      check("list: newest first by default", names() == "The Deadmines:600 Maraudon:160 Molten Core:900 The Deadmines:330", names())
      lv.tabs.select("raid")
      check("list: Raids keeps the raids only", names() == "Molten Core:900", names())
      lv.tabs.select("party")
      check("list: Dungeons leaves the raids out", names() == "The Deadmines:600 Maraudon:160 The Deadmines:330", names())
      lv.tabs.select("all")
      lv.pick:GetScript("OnClick")(lv.pick)
      local items = lv.menu.items or {}
      check("list: the dungeon list names every dungeon once, after All dungeons", #items == 4 and items[1][2] == "All dungeons" and items[1][3] == true and items[2][1] == "Maraudon"
        and items[3][1] == "Molten Core" and items[4][1] == "The Deadmines", #items)
      lv.menu.btns[4]:GetScript("OnClick")(lv.menu.btns[4])
      check("list: a dungeon picked keeps its runs only, and the button says which", names() == "The Deadmines:600 The Deadmines:330" and lv.pick.text:GetText() == "The Deadmines", names())
      lv.tabs.select("raid")
      check("list: a filter that keeps nothing says so, not that there are no runs", #lv.shown == 0 and lv.tbl.empty and lv.tbl.empty:GetText() == "No run matches this filter.",
        lv.tbl.empty and lv.tbl.empty:GetText())
      lv.tabs.select("all"); lv.pickInst(nil)
      local head = lv.tbl.head
      head.dur:GetScript("OnClick")(head.dur)
      check("list: Length sorts longest first, then shortest first on a second click", names() == "Molten Core:900 The Deadmines:600 The Deadmines:330 Maraudon:160", names())
      head.dur:GetScript("OnClick")(head.dur)
      check("list: (shortest first)", names() == "Maraudon:160 The Deadmines:330 The Deadmines:600 Molten Core:900", names())
      head.name:GetScript("OnClick")(head.name)
      check("list: Dungeon sorts A to Z, ties newest first", names() == "Maraudon:160 Molten Core:900 The Deadmines:600 The Deadmines:330", names())
      head.boss:GetScript("OnClick")(head.boss)
      check("list: Bosses sorts most first, ties newest first", names() == "Maraudon:160 The Deadmines:330 The Deadmines:600 Molten Core:900", names())
      head.death:GetScript("OnClick")(head.death)
      check("list: Deaths sorts most first", lv.shown[1].name == "Molten Core", names())
      for _, k in ipairs({ "time", "rate", "loot" }) do check("list: " .. k .. " is a sortable column", head[k] and head[k]:GetScript("OnClick") ~= nil) end
      head.time:GetScript("OnClick")(head.time)
      check("list: back on Time: newest first", names() == "The Deadmines:600 Maraudon:160 Molten Core:900 The Deadmines:330", names())
      invariants("list")
    end
  end

  -- ── review round 3: a run the zone name alone opened, the visit cap's gaps, a purse at load, another dungeon ────
  do
    -- the zone name alone (type "none", a map that is no continent): provisional, and 5 minutes with nothing in it
    -- are not kept, whatever their length (plan section 6)
    fresh()
    enter("Shadowfang Keep", { type = "none", map = 33 })
    check("prov: a run the zone name alone opened is provisional", open() and open().prov == true and E._det.sig == "name")
    play(300); leave(); expire()
    check("prov: 5 minutes with nothing in it are not kept, and noted", open() == nil and #closed() == 0 and (notes().provisional or 0) == 1, notes().provisional)
    -- a fight confirms it
    fresh()
    enter("Shadowfang Keep", { type = "none", map = 33 })
    play(60); combat(true); play(20); combat(false)
    check("prov: a fight confirms it", open() and open().prov == nil)
    play(220); leave(); expire()
    check("prov: and the run is kept", #closed() == 1 and last().secs.inside == 300 and last().secs.combat == 20 and raw().prov == nil, #closed())
    invariants("prov fight")
    -- so do a boss, XP, a death, looted coin and a stronger signal
    for _, how in ipairs({ "boss", "xp", "death", "loot", "signal" }) do
      fresh()
      enter("Shadowfang Keep", { type = "none", map = 33 }); play(30)
      if how == "boss" then kill(1069, "Rethilgore", 20)
      elseif how == "xp" then M.xp = M.xp + 50; M.fire("PLAYER_XP_UPDATE")
      elseif how == "death" then die(); play(5); rise()
      elseif how == "loot" then loot(250)
      else enter("Shadowfang Keep", { map = 33 }) end                -- the client names it an instance now
      play(30)
      check("prov: " .. how .. " confirms it", open() and open().prov == nil, open() and tostring(open().prov))
      leave(); expire()
      check("prov: " .. how .. ": the run is kept", #closed() == 1, #closed())
      invariants("prov " .. how)
    end
    -- a run opened by a strong signal is never provisional
    fresh()
    enter("Maraudon")
    check("prov: a run the client names an instance is not provisional", open() and open().prov == nil)
    -- ended by hand: unconfirmed, not kept and the next run is provisional too; confirmed, the next one is as well
    fresh()
    enter("Shadowfang Keep", { type = "none", map = 33 }); play(100)
    local rec = R.endNow()
    check("prov: ended by hand unconfirmed: not kept, the next run is provisional", rec == nil and #closed() == 0 and open() and open().prov == true and open().open == "split")
    combat(true); play(10); combat(false); play(60)
    rec = R.endNow()
    check("prov: ended by hand once confirmed: kept, and the next run in the same place is confirmed", rec ~= nil and #closed() == 1 and open() and open().prov == nil)
    invariants("prov split")

    -- the visit cap: 22 visits, the last row absorbs 21 and 22, the time between them stays outside
    fresh()
    enter("Maraudon")
    for _ = 1, 20 do play(10); leave(true); play(100); enter("Maraudon", { noLoad = true }) end
    local tIn21 = M.epoch + 5
    play(10); leave(true); play(30)
    local tOut = M.epoch
    combat(true); play(10); combat(false)                          -- a fight outside, between visits 21 and 22
    play(60); enter("Maraudon", { noLoad = true })
    local run = open()
    local last20 = run.visits[R.VISIT_CAP]
    check("caps: 22 visits keep 20 rows, the last one with its two gaps", #run.visits == R.VISIT_CAP and last20.n == 2 and last20.gaps and #last20.gaps == 4
      and last20.gaps[3] == tOut - 30 - run.t and last20.gaps[4] == M.epoch - run.t, last20.gaps and table.concat(last20.gaps, ","))
    check("caps: a moment outside between visits 21 and 22 is not of the run", R.inRun(run, tOut) == false and R.runAt(tOut) == nil and R.inRun(run, tOut + 20) == false)
    check("caps: moments inside visits 20, 21 and 22 are", R.inRun(run, run.t + last20.i + 5) and R.inRun(run, tIn21) and R.inRun(run, M.epoch) and R.runAt(tIn21) == run)
    local realMine = ns.isMine
    ns.isMine = function() return true end
    local rows = R.rowsOf(run, { { startEpoch = tIn21, uid = "f-in" }, { startEpoch = tOut, uid = "f-out" } }, "startEpoch")
    ns.isMine = realMine
    check("caps: the fight outside is not in the run's rows", #rows == 1 and rows[1].uid == "f-in", #rows)
    play(10); leave(); expire()
    local r = raw()
    check("caps: the closed run keeps the gaps, and still sums to its wall time", r and r.visits[R.VISIT_CAP].gaps and #r.visits[R.VISIT_CAP].gaps == 4 and R.inRun(r, tOut) == false
      and R.inRun(r, tIn21) == true and last().secs.wall == last().endT - last().t, r and #r.visits)
    invariants("caps gaps")
    -- past R.GAP_CAP gaps a later one is not kept: the row reads it as inside, and says so in the notes
    fresh()
    enter("Maraudon")
    for _ = 1, R.VISIT_CAP - 1 + R.GAP_CAP + 2 do play(10); leave(true); play(20); enter("Maraudon", { noLoad = true }) end
    check("caps: at most R.GAP_CAP gaps on the row", #open().visits[R.VISIT_CAP].gaps == 2 * R.GAP_CAP and (notes().gapCap or 0) == 2, notes().gapCap)
    invariants("caps gap cap")

    -- a login inside with the client's 0 for the purse at the world entry, the real balance right after: nothing of
    -- the balance is the visit's
    fresh()
    enter("Maraudon"); play(300)
    M.fire("PLAYER_LOGOUT"); G._tickAt = nil; T.newLoad(); adv(3600)
    local bal = M.money
    M.money = 0
    pew(true); R.tick(); G.tick()
    check("purse: logged in inside on a 0 that cannot be trusted: a visit with no purse baseline yet", open() and #open().visits == 2 and open().visits[2].how == "login"
      and open().m0 == nil and open().visits[2].purse == 0, open() and tostring(open().m0))
    M.money = bal; M.fire("PLAYER_MONEY")
    play(60); leave(); expire()
    r = raw()
    check("purse: the login's 0 put nothing on the visit and nothing on the run", r and r.visits[2].how == "login" and r.visits[2].purse == nil and (r.gold == nil or r.gold.purse == nil)
      and R.purseLine(R.view(r, false)) == nil, r and tostring(r.visits[2].purse))
    invariants("purse login")
    -- the same on a /reload: the reading before it stays the baseline
    fresh()
    enter("Maraudon"); play(300)
    bal = M.money
    M.fire("PLAYER_LOGOUT"); G._tickAt = nil; T.newLoad(); adv(9)
    M.money = 0
    pew(false, true); R.tick(); G.tick(); R.tick()
    check("purse: a /reload on a 0 that cannot be trusted keeps the baseline from before", open() and open().m0 == bal and open().visits[1].purse == 0, open() and tostring(open().m0))
    M.money = bal; M.fire("PLAYER_MONEY"); play(20)
    leave()
    check("purse: and the visit's purse is 0", open().visits[1].purse == 0, open().visits[1].purse)
    invariants("purse reload")
    -- a purse that really is 0 is read once the money code took it (the saved balance is 0)
    fresh()
    M.money = 0; me().gold.balance = 0
    enter("Maraudon"); play(20)
    check("purse: a real 0 is a baseline", open().m0 == 0, tostring(open().m0))
    M.money = 500000

    -- left alive (or as a ghost), 5 minutes outside, then another dungeon: the first run closes as "other", the
    -- second opens with one visit
    for _, ghost in ipairs({ false, true }) do
      local tag = ghost and "as a ghost" or "alive"
      fresh()
      enter("Deadmines", { map = 36 }); play(60); kill(644, "Rhahk'Zor", 30)
      if ghost then die() end
      leave(); play(300)
      enter("Wailing Caverns", { map = 43 })
      local lr = last()
      check("other " .. tag .. ": the run left closes as entered another instance", #closed() == 1 and lr.why == "other" and lr.inst == "The Deadmines"
        and lr.visits[1].out == (ghost and "ghost" or "alive") and lr.secs.inside == 90, lr and lr.why)
      check("other " .. tag .. ": and the other dungeon is a run of its own with one visit", open() and open().inst == "Wailing Caverns" and #open().visits == 1 and open().st == "in",
        open() and open().inst)
      if ghost then rise() end
      play(30); leave(); expire()
      invariants("other " .. tag)
    end
  end

  -- ── 21. what the pane says; the contract of every key ────────────────────────────────────────────────────────
  do
    fresh()
    local lv = T.dungeonList and T.dungeonList()
    if lv then
      check("21: the empty list says how runs get there and since when they are kept", lv.emptyText == "No dungeon runs yet. Enter a dungeon and it shows up here.\nRuns are kept from version 0.9.50 on."
        and R.SINCE == "Runs are kept from version 0.9.50 on.")
    end
    enter("Maraudon", { type = "raid" }); play(100)
    kill(422, "Noxxion", 30); combat(false); die(); play(10); leave(); play(120); enter("Maraudon"); rise(); play(400)
    loot(250); item(9001)
    M.xp = M.xp + 300; M.fire("PLAYER_XP_UPDATE")
    local v = R.views()[1]
    check("21: the open run is a row in progress, with its clocks", v.inProgress == true and v.endT == nil and v.state == "in" and v.duration == 660 and v.inside == 540 and v.ghost == 120 and v.kind == "raid", v.duration)
    local tl1, tl2 = R.timeLine(v)
    check("21: the time lines read the clocks in words: where the time went, then what was done inside", tl1 == ("Inside 9m 0s%srunning back 2m 0s"):format(SEP)
      and tl2 == ("Active 9m 0s%sin combat 0s (bosses 30s)"):format(SEP), tl1 .. " | " .. tl2)
    if lv then
      local tips = lv.tipLines(v)
      check("21: the row's tooltip lists inside, run back, active and the state", tips[1] == "Inside 9m 0s" and tips[2] == "Run back 2m 0s" and tips[3] == "Active 9m 0s" and tips[4] == "In progress"
        and tips[5] == "Re-entered 1 time", table.concat(tips, " | "))
    end
    check("contract: characters[guid].dungeonRun, every key typed, the open-only keys present only here", contract(open(), true) == nil and open().st == "in" and open().mark and open().beat and open().g0 and open().m0, contract(open(), true))
    leave()
    check("contract: an open run outside carries left and gap", contract(open(), true) == nil and type(open().gap) == "table" and open().left ~= nil, contract(open(), true))
    expire()
    check("contract: characters[guid].dungeonRuns[], every key typed, no open-only key", contract(raw(), false) == nil and raw().kind == "raid", contract(raw(), false))
    local st = ns.DB.settings.selftest
    check("contract: a new self-test record keeps the run notes (SelfTest.KEEP)", (function()
      local has = {}
      for _, k in ipairs(ns.SelfTest.KEEP) do has[k] = true end
      return has.runs and has.aliasCandidates and has.instances
    end)())
    check("contract: settings.selftest.runs holds whole-number counters only", (function()
      for k, x in pairs(st.runs or {}) do if type(k) ~= "string" or type(x) ~= "number" or x ~= math.floor(x) then return false end end
      return true
    end)())
    -- the XP lines of the page, with kills the client hid
    local xv = { inProgress = false, xpGain = 5000, xpPerHour = 23000.4, hidden = { xp = 2 }, xp = { gain = 5000, kill = 350, quest = 1200, n = 1450, l0 = 12, p0 = 0.1, l1 = 12, p1 = 0.3, need = 1000 } }
    local x1, x2, x3 = R.xpLine(xv)
    check("21: the XP line reads gain, rate, levels and the runs the level still takes (from kill XP)", x1 == table.concat({ "5,000 XP", "23,000 per hour", "level 12.1 to 12.3", "about 2 more runs to level 13" }, SEP), x1)
    check("21: quest XP and the kills read are a line of their own, the count with its separator", x2 == "1,200 XP from quests" .. SEP .. "at least 1,450 kills", x2)
    check("21: a hidden line is called an XP line, never a kill line", x3 == "2 XP lines were hidden by the client.", x3)
    xv.hidden, xv.xp.n, xv.inProgress = { xp = 1 }, 1, true
    x1, x2, x3 = R.xpLine(xv)
    check("21: one hidden line; a run in progress makes no promise about the level", x3 == "1 XP line was hidden by the client." and x2 == "1,200 XP from quests" .. SEP .. "at least 1 kills"
      and x1:find("more run", 1, true) == nil, x1 .. " | " .. tostring(x2) .. " | " .. tostring(x3))
    xv.hidden = nil
    x1, x2, x3 = R.xpLine(xv)
    check("21: with nothing hidden the kills are counted plainly", x2 == "1,200 XP from quests" .. SEP .. "1 kill" and x3 == nil, tostring(x2))
    -- the rows the backend already ingests carry the keys they carried before 0.9.50 and no other (plan 4.5)
    local function keysOf(rows)
      local set, out = {}, {}
      for _, row in ipairs(rows) do if type(row) == "table" then for k in pairs(row) do set[tostring(k)] = true end end end
      for k in pairs(set) do out[#out + 1] = k end
      table.sort(out)
      return table.concat(out, " ")
    end
    local goldRecs = { me().goldRun, me().goldRunsEvicted }
    for _, g in ipairs(me().goldRuns or {}) do goldRecs[#goldRecs + 1] = g end
    local got = { fights = keysOf(ns.DB.combat.fights), story = keysOf(ns.DB.story.events), loot = keysOf(ns.DB.loot.log), gold = keysOf(goldRecs) }
    local WANT = {
      fights = "auras bossName difficultyID duration encounterID endEpoch endLocalHi endMono enemies foes gear id instanceMapID instanceType level map outcome player realm schema session spec startEpoch startLocal startLocalHi startMono stats uid uploaded x y zone",
      story = "downtime kind map s shown t text x y zone",
      loot = "count guid icon id item money q s src t x y zone",
      gold = "inst items lootValue looted quests secs t",
    }
    for _, k in ipairs({ "fights", "story", "loot", "gold" }) do
      check("contract: nothing new on the " .. k .. " rows (the keys of 0.9.49, no other)", got[k] == WANT[k] and got[k] ~= "", got[k])
    end
    check("contract: no schema bump", ns.DB.schema == 2)
    -- the limits
    local ef
    for _, fr in ipairs(ns.eventFrames) do if fr.events.ENCOUNTER_START and not fr.events.PLAYER_MONEY and fr.events.PLAYER_LOGOUT and not fr.events.MAIL_CLOSED then ef = fr end end
    check("limits: Runs.lua has its own event frame, known to the self-test", ef ~= nil)
    check("limits: Emitter.lua still loads and took no file-level local for the run (state is on the tables)", loadfile("Everbuff/Emitter.lua") ~= nil and type(E._det) == "table" and type(E.XP_PATS) == "table")
    check("limits: the invariants were asked after every scenario", nInv >= 30, nInv)
    check("no handler threw anywhere in this suite", errs() == main.errors and R._err == nil, M.errors[#M.errors] or R._err)
  end

  -- ── the suite's save file and client back in place ──────────────────────────────────────────────────────────
  M.units, M.groupN, M.inCombat, M.dead = main.units, main.groupN, main.inCombat, main.dead
  M.xp, M.xpmax, M.level = main.xp, main.xpmax, main.level
  _G.UnitGUID, ns.msg, _G.SendChatMessage = real.guid, real.msg, real.send
  M.sellPrice = real.sell
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
  P.check("runs: the suite's save file is back, its session resumed", ns.DB == main.db and ns.Recorder.current() ~= nil)
end
