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
  local function last() local l = closed(); return l[#l] end
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
  local function enter(zone, o)
    o = o or {}
    M.zone, M.mapType = zone, o.mapType or 3
    M.inst = { name = o.name or zone, type = o.type or "party", diff = 1, mapID = o.map == nil and 349 or o.map }
    if o.noLoad then M.fire("ZONE_CHANGED_NEW_AREA") else pew() end
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
  local function errs() return #M.errors end

  -- ── the invariants, asked at the end of every scenario ─────────────────────────────────────────────────────────
  local nInv = 0
  local function invariants(tag)
    nInv = nInv + 1
    local why
    local c = me()
    local function one(run, isOpen)
      local s = run.secs
      local vs = { secs = 0, active = 0, xp = 0, looted = 0, quests = 0, lootValue = 0, items = 0 }
      for _, v in ipairs(run.visits) do for k in pairs(vs) do vs[k] = vs[k] + (v[k] or 0) end end
      if not isOpen then
        if s.inside + s.ghost + s.outside + s.offline ~= s.wall then why = "clocks do not sum to wall" end
        if run.endT - run.t ~= s.wall then why = ("wall %d is not endT - t %d"):format(s.wall, run.endT - run.t) end
        for _, k in ipairs({ "looted", "quests", "lootValue", "items" }) do if run.gold[k] ~= vs[k] then why = "gold." .. k .. " is not the sum of the visits" end end
        for _, k in ipairs(R.OPEN_KEYS) do if run[k] ~= nil then why = "a closed run keeps " .. k end end
        if run.visits[#run.visits].o == nil then why = "the last visit of a closed run has no end" end
      end
      if vs.secs ~= s.inside then why = ("inside %d is not the sum of the visits %d"):format(s.inside, vs.secs) end
      if vs.active ~= s.active then why = "active is not the sum of the visits" end
      if s.active > s.inside then why = "more active seconds than seconds inside" end
      if vs.xp ~= (run.xp and run.xp.gain or 0) then why = "xp is not the sum of the visits" end
      if not R.valid(run) then why = "not a valid record" end
    end
    for _, r in ipairs(c.dungeonRuns or {}) do one(r, false) end
    if c.dungeonRun then one(c.dungeonRun, true) end
    if c.dungeonRun ~= nil and type(c.dungeonRun) ~= "table" then why = "more than one open run" end
    check("invariants after " .. tag, why == nil and R._err == nil, why or R._err)
  end

  -- ── 1. enter, two bosses, leave, 21 minutes: one record ───────────────────────────────────────────────────────
  do
    fresh()
    local t0 = M.epoch
    enter("Deadmines", { map = 36 })
    local id = open() and open().id
    check("1: entering opens a run named canonical, with its attributes", open() and open().inst == "The Deadmines" and open().key == "the deadmines" and open().kind == "party"
      and open().map == 36 and open().diff == 1 and open().t == t0 and open().open == "zone" and open().v == 1 and open().st == "in", open() and open().inst)
    check("1: the id is the last 8 of the GUID, the time and four hex digits", type(id) == "string" and id:match("^" .. ME:sub(-8):gsub("%-", "%%-") .. "%-" .. t0 .. "%-%x%x%x%x$") ~= nil, id)
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
    check("1: a segment runs from the first pull, then from the kill before", a and a.seg == 40 and a.prev == nil and b.seg == 130 and b.prev == 644 and r.firstPull == 120, b and b.seg)
    check("1: boss combat is END minus START, the pull's wall time is the START", a and a.combat == 40 and b.combat == 30 and a.at == t0 + 120 and b.at == t0 + 260 and r.secs.boss == 70 and a.ok == 1 and a.dur == 40)
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
    check("4: the death carries how long it took to be back", run.nDeaths.me == 1 and #run.deaths == 1 and run.deaths[1].back == 1520 and run.deaths[1].o == 100 and run.deaths[1].me == true and run.deadSince == nil, run.deaths[1] and run.deaths[1].back)
    play(60)
    -- dies again and logs out as a ghost for the night
    die(); play(10); leave()
    local endT = open().endT
    relog(8 * 3600)
    local r = last()
    check("4: logged out as a ghost overnight: closed at the cap, why ghost", open() == nil and r and r.why == "ghost", r and r.why)
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
    check("7: a dungeon whose strong signal never fires still opens (the zone name, a dungeon's map id)", open() and open().inst == "Shadowfang Keep" and open().st == "in" and E._det.sig == "name")
    play(120); leave(); expire()
    check("7: and its time counts as inside", #closed() == 1 and last().secs.inside == 120)
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
    invariants("9")

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
    check("10: the pull time is the START, never the start of the fight", b and b.at == t0 + 321 and b.combat == 52 and b.kill == 373, b and b.at - t0)
    check("10: the first pull of the run is the first combat", open().firstPull == 288 and b.seg == 85 and open().secs.combat == 85 and open().secs.boss == 52, open().firstPull)
    check("10: the boss links the fight that was running at its END", uid ~= nil and b.fight == uid, tostring(b.fight))
    invariants("10")

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
    check("11: the END of the second, 5 s after the first, is kept", c2.seg == 5 and c2.prev == 601 and a.prev == 600 and a.seg == 90 and c2.combat == 35)
    check("11: time with a boss up is counted once while two are up", open().secs.boss == 40 + 35 and open().encs == nil and open().bossFrom == nil, open().secs.boss)
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
    check("gold: End run now closes the run with its coin, why manual", rec and rec.why == "manual" and rec.gold.looted == 500 and rec.visits[1].out == "manual" and open() == nil)
    enter("Maraudon", { noLoad = true })
    loot(200); play(60)
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
  local function svSize(v) local out = {}; svText(v, 2, out); return #table.concat(out) end
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
    check("Maraudon: the first boss: 52 s of encounter inside 85 s of fight, pulled 20:38:19", r.bosses[1].combat == 52 and r.bosses[1].at == t0 + 321 and r.firstPull == 288)
    check("Maraudon: its XP and its coin are on it", r.xp and r.xp.gain == 800 and r.xp.n == 1 and r.xp.kill == 800 and r.gold.looted == 365 and r.gold.items == 5, r.xp and r.xp.gain)
    local size = svSize(r)
    check("15: the real Maraudon shape is under 4.5 KB in the save file (budget of 0.9.50)", size < 4.5 * 1024, size)
    realPrint(("dungeon run size: the Maraudon shape (2 visits, 8 bosses, 1 death) is %.1f KB in SavedVariables format"):format(size / 1024))
    invariants("Maraudon")
    -- the worst case at the caps of this version: 20 visits, 20 bosses, 40 death rows
    local worst = deepcopy(r)
    worst.partial = "ended while a boss was in progress"
    for i = 1, R.VISIT_CAP do local v = deepcopy(r.visits[1]); v.unpriced, v.n = 3, 2; worst.visits[i] = v end
    for i = 1, R.BOSS_CAP do local b = deepcopy(r.bosses[2]); b.fight = "Hart-Realm-1795033978-216-a1b2"; b.prev = 422; worst.bosses[i] = b end
    for i = 1, R.DEATH_CAP do worst.deaths[i] = { o = 4000 + i, me = true, enc = 426, foe = "Princess Theradras", back = 216 } end
    local wsize = svSize(worst)
    check("15: the worst case at the caps is under 18 KB (budget of 0.9.50)", wsize < 18 * 1024, wsize)
    check("15: 100 runs of the real shape stay under 500 KB per character", size * R.CAP < 500 * 1024, size * R.CAP)
    realPrint(("dungeon run size: worst case at the caps (20 visits, 20 bosses, 40 deaths) %.1f KB; 100 runs of the real shape %.0f KB"):format(wsize / 1024, size * R.CAP / 1024))
    -- the caps themselves
    fresh()
    enter("Maraudon")
    for i = 1, 25 do play(10); leave(true); play(10); enter("Maraudon", { noLoad = true }) end
    check("caps: after 20 visits the last row takes every later stretch", #open().visits == R.VISIT_CAP and open().visits[R.VISIT_CAP].n == 6 and open().secs.inside == 250 and open().secs.outside == 250, #open().visits)
    for i = 1, 25 do START(5000 + i, "Boss " .. i); END(5000 + i, "Boss " .. i, 1) end
    check("caps: at most 20 boss rows", #open().bosses == R.BOSS_CAP)
    for i = 1, 45 do die(); M.dead = false; M.fire("PLAYER_UNGHOST") end
    check("caps: at most 40 death rows, the counter is never capped", #open().deaths == R.DEATH_CAP and open().nDeaths.me == 45)
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
    local good = last()
    local later = T.runRecord("Uldaman", M.epoch - 500, 100, { v = 2 })
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
    check("17: the closed run keeps the levels at both ends and the bar it ended on", r.xp.gain == 950 and r.xp.l0 == 12 and r.xp.l1 == 13 and r.xp.p1 == 0.458 and r.xp.need == 1200, r.xp.p1)
    invariants("17")
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
    expire()
    check("18: no handler threw on any of it", errs() == e0 and R._err == nil, M.errors[#M.errors] or R._err)
    check("18: the hidden lines end up on the record and in the page's wording", last().hidden.xp == 1 and last().hidden.loot == 1 and last().hidden.rep == 1)
    S[777001], S[424242], S["Hidden Boss"], S["Hidden line"], S[31337] = nil, nil, nil, nil, nil
    invariants("18")
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

  -- ── 21. what the pane says; the contract of every key ────────────────────────────────────────────────────────
  do
    fresh()
    local lv = T.dungeonList and T.dungeonList()
    if lv then
      check("21: the empty list says how runs get there and since when they are kept", lv.emptyText == "No dungeon runs yet. Enter a dungeon and it shows up here.\nRuns are kept from version 0.9.50 on."
        and R.SINCE == "Runs are kept from version 0.9.50 on.")
    end
    enter("Maraudon", { type = "raid" }); play(100)
    kill(422, "Noxxion", 30); die(); play(10); leave(); play(120); enter("Maraudon"); rise(); play(400)
    loot(250); item(9001)
    M.xp = M.xp + 300; M.fire("PLAYER_XP_UPDATE")
    local v = R.views()[1]
    check("21: the open run is a row in progress, with its clocks", v.inProgress == true and v.endT == nil and v.state == "in" and v.duration == 660 and v.inside == 540 and v.ghost == 120 and v.kind == "raid", v.duration)
    check("21: the time line reads the clocks in words", R.timeLine(v) == ("Inside 9m 0s%srunning back 2m 0s%sactive 9m 0s%sin combat 0s (bosses 30s)"):format(SEP, SEP, SEP), R.timeLine(v))
    if lv then
      local tips = lv.tipLines(v)
      check("21: the row's tooltip lists inside, run back, active and the state", tips[1] == "Inside 9m 0s" and tips[2] == "Run back 2m 0s" and tips[3] == "Active 9m 0s" and tips[4] == "In progress"
        and tips[5] == "Re-entered 1 time", table.concat(tips, " | "))
    end
    -- the contract: every key of an open run and of a closed one, typed
    local function typed(t, spec, where)
      for k, x in pairs(t) do
        local want = spec[k]
        if not want then return where .. "." .. tostring(k) .. " is not in the contract" end
        if type(x) ~= want then return where .. "." .. tostring(k) .. " is a " .. type(x) end
      end
    end
    local RUN = { id = "string", v = "number", inst = "string", key = "string", kind = "string", map = "number", diff = "number", uiMap = "number", t = "number", endT = "number",
      open = "string", why = "string", partial = "string", visits = "table", secs = "table", firstPull = "number", bosses = "table", nDeaths = "table", deaths = "table", xp = "table",
      gold = "table", hidden = "table", keep = "boolean",
      st = "string", mark = "number", beat = "number", left = "number", ghostAt = "number", gap = "table", encs = "table", deadSince = "number", m0 = "number", g0 = "table", bossIn = "table", bossFrom = "number" }
    local VISIT = { i = "number", o = "number", how = "string", out = "string", n = "number", secs = "number", active = "number", xp = "number", xpKill = "number", xpQuest = "number", kills = "number",
      looted = "number", quests = "number", lootValue = "number", items = "number", unpriced = "number", purse = "number" }
    local BOSS = { enc = "number", name = "string", pulls = "number", wipes = "number", resets = "number", unknown = "number", combat = "number", kill = "number", seg = "number", prev = "number",
      fight = "string", at = "number", ok = "number", dur = "number" }
    local SECS = { wall = "number", inside = "number", ghost = "number", outside = "number", offline = "number", active = "number", combat = "number", boss = "number" }
    local function contract(run, isOpen)
      local why = typed(run, RUN, "run")
        or typed(run.secs, SECS, "secs") or typed(run.nDeaths, { me = "number", party = "number" }, "nDeaths") or typed(run.hidden, { xp = "number", rep = "number", loot = "number" }, "hidden")
        or (run.xp and typed(run.xp, { gain = "number", kill = "number", quest = "number", n = "number", l0 = "number", l1 = "number", p0 = "number", p1 = "number", need = "number" }, "xp"))
        or (run.gold and typed(run.gold, { looted = "number", quests = "number", lootValue = "number", items = "number", unpriced = "number", purse = "number" }, "gold"))
      for _, x in ipairs(run.visits) do why = why or typed(x, VISIT, "visit") end
      for _, x in ipairs(run.bosses) do why = why or typed(x, BOSS, "boss") end
      for _, x in ipairs(run.deaths) do why = why or typed(x, { o = "number", me = "boolean", enc = "number", foe = "string", back = "number" }, "death") end
      if not isOpen then
        for _, k in ipairs(R.OPEN_KEYS) do if run[k] ~= nil then why = why or ("closed run keeps " .. k) end end
        if not (R.WHY[run.why] and run.gold) then why = why or "closed run without why or gold" end
      else
        if not ({ ["in"] = true, ghost = true, out = true, off = true })[run.st] then why = why or "st" end
      end
      local HOW, OUT = { zone = 1, login = 1, reload = 1, ghost = 1, boss = 1 }, { alive = 1, ghost = 1, offline = 1, other = 1, manual = 1 }
      for _, x in ipairs(run.visits) do if not HOW[x.how] or (x.out and not OUT[x.out]) then why = why or "visit how/out" end end
      if not ({ zone = 1, login = 1, boss = 1 })[run.open] or not ({ party = 1, raid = 1 })[run.kind] then why = why or "open/kind" end
      return why
    end
    check("contract: characters[guid].dungeonRun, every key typed, the open-only keys present only here", contract(open(), true) == nil and open().st == "in" and open().mark and open().beat and open().g0 and open().m0, contract(open(), true))
    leave()
    check("contract: an open run outside carries left and gap", contract(open(), true) == nil and type(open().gap) == "table" and open().left ~= nil, contract(open(), true))
    expire()
    check("contract: characters[guid].dungeonRuns[], every key typed, no open-only key", contract(last(), false) == nil and last().kind == "raid", contract(last(), false))
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
    check("contract: nothing new on fights, story rows, loot rows or gold records", (function()
      for _, f in ipairs(ns.DB.combat.fights) do if f.run ~= nil then return false end end
      for _, e in ipairs(ns.DB.story.events) do if e.run ~= nil then return false end end
      for _, l in ipairs(ns.DB.loot.log) do if l.run ~= nil then return false end end
      return true
    end)())
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
