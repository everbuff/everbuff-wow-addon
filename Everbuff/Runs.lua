-- Everbuff.GG · Runs.lua - the durable dungeon run (0.9.50, everbuff-wow-addon #51).
--
-- Until 0.9.49 a run was rebuilt at view time from the DUNGEON and DUNGEONLEAVE story events, which the 500 row cap
-- and the desktop's acknowledgement remove within hours. From 0.9.50 a run is a stored record of the logged-in
-- character: `characters[guid].dungeonRun` while it is open, `characters[guid].dungeonRuns[]` once closed (oldest
-- first, at most Runs.CAP). The acknowledgement never touches either. Nothing before 0.9.50 is backfilled.
--
-- What a run is made of:
--   visits    one row per stretch inside. Every sum (seconds, XP, coin, items) is kept per visit, so the run's sums
--             are always the sum of its visits.
--   clocks    secs = { inside, ghost, outside, offline, active, combat, boss }; inside + ghost + outside + offline
--             = endT - t, the wall time. A run ends at the moment the character was last inside: the time outside
--             after it is not part of the run.
--   bosses    counted from ENCOUNTER_START and ENCOUNTER_END themselves, never from a fight record. Several
--             encounters can be open at once (run.encs, keyed by encounter id).
-- An open run has every block and every clock. A closed one is lean (Runs.lean): no 0, no empty block, nothing a
-- reader can work out. Nothing is put on a clock before a load is read (Runs._read, set in Runs.loaded).
--
-- Where the character is, for a run ("in", "door" or "out", Runs.where):
--   in        the client says instance (GetInstanceInfo's or IsInInstance's type), or the map is a dungeon map, or
--             only the zone name says so and GetInstanceInfo does not name a continent map.
--   door      only the zone name says dungeon and GetInstanceInfo's map is a continent: the open world in front of
--             the portal (the halls outside Sunken Temple carry the dungeon's name). A door visit is time outside:
--             no inside seconds, no XP, and it opens no run.
--   out       everything else.
-- A boss pull (ENCOUNTER_START) while the detector says door, or says out on a map that is no continent, puts the
-- character inside until the zone or the map changes (run.bossIn): a custom dungeon the name list lacks, or one the
-- client never names an instance. On a continent map with no dungeon name it opens nothing (a world boss).
--
-- Clocks, as decided for this version:
--   a /reload takes 7 to 11 seconds; they stay on the clock the run was on (inside stays inside), since the
--   character never left. Only a login makes offline time.
--   active seconds are counted by this file's own 10 second tick, the same rule as the gold tick (Economy.lua,
--   Gold.tick): the time since the last tick, at most 10 s, nothing while away from the keyboard (Gold._afk).
--   Every rate divides by them.
--
-- Gold. Economy.lua keeps the coin of a dungeon in its own gold run, which has another lifetime (it follows the
-- zone name, closes 20 minutes after leaving even as a ghost, and goes on over a run ended by hand). So a visit
-- takes the difference of the character's gold run counters between its two ends (Runs.goldNow: the open gold run,
-- the closed ones and the evicted sum together, which only ever grow), and the run's gold block is the sum of its
-- visits. `purse` is the change of the purse itself while inside, less quest coin: when it is not the looted coin
-- the page says so.

local ADDON, ns = ...

local Runs = {}
ns.Runs = Runs

Runs.V = 1                 -- record version
Runs.CAP = 100             -- closed runs kept per character
Runs.VISIT_CAP = 20        -- then the last visit row absorbs
Runs.BOSS_CAP = 20
Runs.DEATH_CAP = 40        -- rows; the counters are never capped
Runs.DEATH_FULL = 10       -- a closed run keeps `foe` and `back` on this many death rows
Runs.REENTER = 20 * 60     -- alive outside this long: the run is over (the value of Gold.RUN_REENTER)
Runs.GHOST_CAP = 30 * 60   -- a ghost outside this long is not running back
Runs.MIN_SECS = 60         -- a shorter run with nothing in it is not kept
Runs.TICK = 10
Runs.RATE_WARM = 300       -- a rate needs this many active seconds
Runs.ALIAS_CAP = 40
Runs.CANDIDATE_CAP = 20
-- GetInstanceInfo's map id for the open world
Runs.CONTINENT = { [0] = true, [1] = true, [530] = true, [571] = true, [870] = true, [1116] = true, [1220] = true,
  [1642] = true, [1643] = true, [2222] = true, [2444] = true, [2552] = true }
Runs.SINCE = "Runs are kept from version 0.9.50 on."
Runs.WHY = { left = "left the dungeon", other = "entered another instance", ghost = "did not come back as a ghost",
  manual = "ended by hand", lost = "the game closed without saving" }
Runs.GOLD_KEYS = { "looted", "quests", "lootValue", "items" }
-- the keys only an open run has
Runs.OPEN_KEYS = { "st", "mark", "beat", "left", "ghostAt", "gap", "encs", "deadSince", "m0", "g0", "bossIn", "bossWin", "prov" }
Runs.GAP_CAP = 20          -- gaps kept on the visit row that absorbs past Runs.VISIT_CAP

local floor, max, min = math.floor, math.max, math.min
local function plainNum(v) return ns.plainNum(v) end
local function safeStr(v) return ns.safeStr(v) end
local function num(v) return type(v) == "number" and v or 0 end
Runs.SECS = { "inside", "ghost", "outside", "offline", "active", "combat", "boss" }
local function nowT() return (GetServerTime and GetServerTime()) or time() end
local function canon(name)
  local E = ns.Emitter
  if E and E.canonInstance then return E.canonInstance(name) end
  return name
end
local function me()
  if not (ns.DB and ns.charGuid and ns.charGuid()) then return nil end
  return ns.char()
end
local function cur(c) local r = c and c.dungeonRun; return type(r) == "table" and r or nil end
local function visit(run) return run.visits[#run.visits] end
-- a counter of the diagnostics (settings.selftest.runs), nothing shown
function Runs.note(key)
  local st = ns.DB and ns.DB.settings
  if type(st) ~= "table" then return end
  if type(st.selftest) ~= "table" then st.selftest = {} end
  local r = st.selftest.runs
  if type(r) ~= "table" then r = {}; st.selftest.runs = r end
  r[key] = num(r[key]) + 1
end
local function rd(fn, a)
  if type(fn) ~= "function" then return nil end
  local ok, v = pcall(fn, a)
  if ok then return v end
  return nil
end
local function isDead()
  local v = rd(UnitIsDeadOrGhost, "player")
  if type(v) ~= "boolean" or (issecretvalue and issecretvalue(v)) then return false end
  return v
end
-- whether the client says the character is in combat now (a combat already running sends no PLAYER_REGEN_DISABLED)
local function fighting()
  local v = rd(UnitAffectingCombat, "player")
  if type(v) ~= "boolean" or (issecretvalue and issecretvalue(v)) then return false end
  return v
end
-- The purse, or nil while it cannot be trusted: at a load the client can answer 0 for a purse that holds gold. A 0
-- while the character's saved balance is above 0 is not read until Emitter's money code has taken it (it waits up
-- to 15 s for a real answer, Emitter.lua onMoney, 0.9.44), which sets the saved balance to 0.
local function purse()
  local m = plainNum(rd(GetMoney))
  if m ~= 0 then return m end
  local c = me()
  local g = c and type(c.gold) == "table" and c.gold or nil
  if g and num(plainNum(g.balance)) > 0 then return nil end
  return m
end
local function xpRead()
  local xp, mx = plainNum(rd(UnitXP, "player")), plainNum(rd(UnitXPMax, "player"))
  if xp and mx and mx > 0 then return xp, mx end
  return nil
end

-- ── where the character is ──────────────────────────────────────────────────────────────────────────────────────
-- the detector's last answer (Emitter.instanceNow leaves it in Emitter._det); `fresh` asks again
function Runs.detect(fresh)
  local E = ns.Emitter
  if not E then return {} end
  if fresh and E.instanceNow then pcall(E.instanceNow) end
  return type(E._det) == "table" and E._det or {}
end
-- "in", name, kind · "door", name, kind · "out"
function Runs.where(det, run)
  local door = det.kind and det.sig == "name" and det.map ~= nil and Runs.CONTINENT[det.map] == true
  if det.kind and not door then return "in", canon(det.name), det.kind end
  local b = run and run.bossIn
  if type(b) == "table" and det.zone == b.zone and det.map == b.map then return "in", run.inst, run.kind end
  if door then return "door", canon(det.name), det.kind end
  return "out"
end

-- ── gold: the character's gold run counters, all lifetimes together ───────────────────────────────────────────
function Runs.goldNow(c)
  local s = { looted = 0, quests = 0, lootValue = 0, items = 0, unpriced = 0 }
  local function add(r, open)
    if type(r) ~= "table" then return end
    for _, k in ipairs(Runs.GOLD_KEYS) do s[k] = s[k] + num(r[k]) end
    s.unpriced = s.unpriced + num(r.unpriced)
    if open and type(r.wait) == "table" then for _, n in pairs(r.wait) do s.unpriced = s.unpriced + num(n) end end
  end
  add(c.goldRunsEvicted)
  for _, r in ipairs(type(c.goldRuns) == "table" and c.goldRuns or {}) do add(r) end
  add(c.goldRun, true)
  return s
end
-- what the counters and the purse gained since the visit's last reading goes onto the visit
function Runs.goldTake(c, run, noPurse)
  local v = visit(run)
  if not v then return end
  -- (an item still waiting for its vendor price is asked again first, Economy.lua Gold.runPrice)
  if ns.Gold and ns.Gold.runPrice and type(c.goldRun) == "table" then pcall(ns.Gold.runPrice, c.goldRun) end
  local now, g0 = Runs.goldNow(c), type(run.g0) == "table" and run.g0 or nil
  if g0 then
    for _, k in ipairs(Runs.GOLD_KEYS) do
      local d = now[k] - num(g0[k])
      if d > 0 then v[k] = num(v[k]) + d end
    end
    local u = num(v.unpriced) + now.unpriced - num(g0.unpriced)
    v.unpriced = u > 0 and u or nil
  end
  run.g0 = now
  -- looted coin or an item confirms a run the zone name alone opened
  if g0 and (now.looted > num(g0.looted) or now.items > num(g0.items)) then run.prov = nil end
  -- (a purse not to be trusted yet takes nothing and keeps the last trusted reading; with none, the first trusted
  -- one is the baseline and adds nothing)
  if noPurse then run.m0 = nil; return end
  local m1 = purse()
  if m1 == nil then return end
  if plainNum(run.m0) then v.purse = num(v.purse) + (m1 - run.m0) end
  run.m0 = m1
end
-- the gold block of a run: the sum of its visits; purse is the purse's change inside less quest coin
function Runs.goldOf(run)
  local g = { looted = 0, quests = 0, lootValue = 0, items = 0, purse = 0 }
  local unpriced = 0
  for _, v in ipairs(run.visits) do
    for _, k in ipairs(Runs.GOLD_KEYS) do g[k] = g[k] + num(v[k]) end
    g.purse = g.purse + num(v.purse)
    unpriced = unpriced + num(v.unpriced)
  end
  g.purse = g.purse - g.quests
  g.unpriced = unpriced > 0 and unpriced or nil
  return g
end

-- ── clocks ──────────────────────────────────────────────────────────────────────────────────────────────────────
-- the time since the last reading goes onto the clock the run is on
function Runs.flush(run, at)
  at = at or nowT()
  local d = at - num(run.mark)
  if not plainNum(run.mark) or d < 0 then d = 0 end
  run.mark, run.beat = at, at
  if d == 0 then return end
  if run.st == "in" then
    run.secs.inside = run.secs.inside + d
    local v = visit(run); v.secs = num(v.secs) + d
  else
    local g = run.gap
    if type(g) ~= "table" then g = { ghost = 0, outside = 0, offline = 0 }; run.gap = g end
    local k = (run.st == "ghost" and "ghost") or (run.st == "off" and "offline") or "outside"
    g[k] = num(g[k]) + d
  end
end
-- seconds on the run's own clock (inside plus running back as a ghost) at `at`
function Runs.clock(run, at)
  local s = run.secs.inside + run.secs.ghost
  if type(run.gap) == "table" then s = s + num(run.gap.ghost) end
  if (run.st == "in" or run.st == "ghost") and plainNum(run.mark) then s = s + max(0, (at or nowT()) - run.mark) end
  return s
end

-- ── encounters ──────────────────────────────────────────────────────────────────────────────────────────────────
local function bossRow(run, id, name, make)
  for _, b in ipairs(run.bosses) do if b.enc == id then if name and not b.name then b.name = name end; return b end end
  if not make or #run.bosses >= Runs.BOSS_CAP then return nil end
  local b = { enc = id, name = name, pulls = 0, wipes = 0, resets = 0, unknown = 0, combat = 0 }
  run.bosses[#run.bosses + 1] = b
  return b
end
-- every encounter still open ends unseen
function Runs.closeEncs(run)
  if type(run.encs) ~= "table" then run.encs = nil; return 0 end
  local n = 0
  for id in pairs(run.encs) do
    local b = bossRow(run, id)
    if b then b.unknown = num(b.unknown) + 1 end
    n = n + 1
  end
  run.encs = nil
  return n
end
-- A boss's segment: the seconds on the run's clock from the kill before it (or from the first pull) to its own kill,
-- and the encounter killed before it. Worked out from the kills, never stored: { [enc] = { seg, prev } }.
function Runs.splits(rec)
  local killed = {}
  for i, b in ipairs(rec.bosses) do if plainNum(b.kill) then killed[#killed + 1] = { b = b, i = i } end end
  table.sort(killed, function(x, y) if x.b.kill ~= y.b.kill then return x.b.kill < y.b.kill end return x.i < y.i end)
  local out, prevO, prevEnc = {}, num(rec.firstPull), nil
  for _, k in ipairs(killed) do
    out[k.b.enc] = { seg = max(0, k.b.kill - prevO), prev = prevEnc }
    prevO, prevEnc = k.b.kill, k.b.enc
  end
  return out
end
-- the uid of the fight that overlaps an encounter's window: the one running, else the last stored one that ended
-- inside it
function Runs.fightUid(from)
  local F = ns.Fights
  if not F then return nil end
  local uid = F.currentUid and F.currentUid() or nil
  if uid then return uid end
  local list = F.list and F.list() or {}
  for i = #list, max(1, #list - 5), -1 do
    local f = list[i]
    if type(f) == "table" and ns.isMine and ns.isMine(f) and num(f.startEpoch) + num(f.duration) >= from then return safeStr(f.uid) end
  end
  return nil
end

-- ── visits ──────────────────────────────────────────────────────────────────────────────────────────────────────
local xpMark
local function beginVisit(c, run, at, how)
  local g = run.gap
  if type(g) == "table" then
    run.secs.ghost, run.secs.outside, run.secs.offline = run.secs.ghost + num(g.ghost), run.secs.outside + num(g.outside), run.secs.offline + num(g.offline)
  end
  run.gap = nil
  if #run.visits >= Runs.VISIT_CAP then
    -- The cap: the last row takes every later stretch. The time between two of its stretches is kept in its `gaps`
    -- (flat pairs of offsets from `t`, from and to), so a moment outside between them is never of the run
    -- (Runs.inRun). Past Runs.GAP_CAP gaps a later one is not kept: the row then reads it as inside.
    local last = visit(run)
    if plainNum(last.o) then
      local gp = type(last.gaps) == "table" and last.gaps or {}
      if #gp < 2 * Runs.GAP_CAP then gp[#gp + 1] = last.o; gp[#gp + 1] = at - run.t; last.gaps = gp
      else Runs.note("gapCap") end
    end
    last.o, last.out, last.n = nil, nil, num(last.n) + 1
  else
    run.visits[#run.visits + 1] = { i = at - run.t, how = how, secs = 0, active = 0, xp = 0, xpKill = 0, xpQuest = 0, kills = 0,
      looted = 0, quests = 0, lootValue = 0, items = 0, purse = 0 }
  end
  run.st, run.mark, run.beat, run.left, run.ghostAt = "in", at, at, nil, nil
  run.m0, run.g0 = purse(), Runs.goldNow(c)
  -- a combat already running when the visit begins (walked in fighting, or the next run of a split) counts from here
  Runs._combatAt = nil
  if fighting() then
    Runs._combatAt = GetTime()
    if not run.firstPull then run.firstPull = Runs.clock(run, at) end
    run.prov = nil
  end
end
local function combatEnd(run)
  if not Runs._combatAt then return end
  local d = floor(max(0, GetTime() - Runs._combatAt) + 0.5)
  Runs._combatAt = nil
  run.secs.combat = run.secs.combat + d
end
-- `out`: "alive", "ghost", "offline", or the reason the run closed while inside ("other", "manual")
local function endVisit(c, run, at, out)
  Runs.flush(run, at)
  Runs.goldTake(c, run, out == "offline")
  combatEnd(run)
  if out ~= "offline" then xpMark(run) end                       -- (a visit found ended at a login was marked while inside)
  local v = visit(run)
  v.o, v.out = at - run.t, out
  run.endT = at
  run.st = (out == "ghost" and "ghost") or (out == "offline" and "off") or "out"
  run.left = run.st == "out" and at or nil
  run.ghostAt = run.st == "ghost" and at or nil
  run.gap = { ghost = 0, outside = 0, offline = 0 }
  run.bossIn = nil
end

-- ── open and close ──────────────────────────────────────────────────────────────────────────────────────────────
local function newId(at)
  local guid = tostring(ns.charGuid() or "")
  return ("%s-%d-%04x"):format(guid:sub(-8), at, math.random(0, 0xFFFF))
end
local function frac(xp, mx) return floor(xp / mx * 1000 + 0.5) / 1000 end
-- where the level stands now, kept on the run while the character is inside: the end of the run's XP block is the
-- last reading inside, never one taken after the character left
function xpMark(run)
  local x = run.xp
  if type(x) ~= "table" then return end
  local xp, mx = xpRead()
  local lvl = plainNum(rd(UnitLevel, "player"))
  if lvl then x.l1 = lvl end
  if xp then x.p1, x.need = frac(xp, mx), mx end
end
local function openRun(c, at, name, kind, det, how)
  local run = { id = newId(at), v = Runs.V, inst = name, kind = kind, map = det.map, diff = det.diff, uiMap = det.uiMap,
    t = at, endT = at, open = (how == "reload" and "login") or how, visits = {},
    secs = { inside = 0, ghost = 0, outside = 0, offline = 0, active = 0, combat = 0, boss = 0 },
    bosses = {}, nDeaths = { me = 0, party = 0 }, deaths = {}, hidden = { xp = 0, rep = 0, loot = 0 } }
  local xp, mx = xpRead()
  if xp then
    run.xp = { gain = 0, kill = 0, quest = 0, n = 0, l0 = plainNum(rd(UnitLevel, "player")), p0 = frac(xp, mx) }
    run.xp.l1, run.xp.p1, run.xp.need = run.xp.l0, run.xp.p0, mx
    Runs._xp = { xp = xp, mx = mx }
  end
  if how == "login" and Runs._lost then run.partial = "state lost before this login" end
  -- Opened by the zone name alone (no instance type, no dungeon map): provisional until a fight, a boss, a death, XP,
  -- loot or a stronger signal confirms it (plan section 6). One never confirmed is discarded when it closes.
  if det.sig == "name" and how ~= "boss" then run.prov = true end
  c.dungeonRun = run
  beginVisit(c, run, at, how)
  -- one more dungeon run on the session (0.9.50: the session counted DUNGEON events before, 22 in one evening)
  if ns.Recorder and ns.Recorder.bump then pcall(ns.Recorder.bump, "dungeons") end
  return run
end
-- a run with nothing in it is not kept
local function empty(run)
  if run.partial or run.secs.inside >= Runs.MIN_SECS then return false end
  local g = run.gold or {}
  return #run.bosses == 0 and run.secs.combat == 0 and run.nDeaths.me == 0 and not run.xp
    and num(g.looted) == 0 and num(g.quests) == 0 and num(g.items) == 0
end
function Runs.evict(list)
  while #list > Runs.CAP do
    local drop = 1
    for i = 1, #list do if not list[i].keep then drop = i; break end end
    table.remove(list, drop)
  end
end
-- A closed record is lean: a visit or a boss row keeps a counter only when it is not 0 (the whole save file is
-- uploaded at every /reload and logout, and a run is kept for a long time). Readers take a missing counter as 0.
Runs.LEAN_VISIT = { "active", "xp", "xpKill", "xpQuest", "kills", "looted", "quests", "lootValue", "items", "purse" }
Runs.LEAN_BOSS = { "wipes", "resets", "unknown" }
-- Also gone from a closed record, because a reader can work it out: a clock that is 0 (`secs.inside` always stays;
-- the wall time is endT - t), a 0 in `hidden`, `nDeaths` and `gold` (and the block with nothing left in it), an empty
-- `deaths`, a boss row's `pulls` when it is 1 (the one count a reader takes as 1 when missing), its `ok` beside its
-- `kill` and its `dur` when the last pull was the only one. Past Runs.DEATH_FULL death rows a row keeps when and
-- where, not `foe` and `back`.
local function leanBlock(run, key)
  local t = run[key]
  if type(t) ~= "table" then return end
  for k, x in pairs(t) do if x == 0 then t[k] = nil end end
  if next(t) == nil then run[key] = nil end
end
function Runs.lean(run)
  local s = run.secs
  for _, k in ipairs(Runs.SECS) do if k ~= "inside" and s[k] == 0 then s[k] = nil end end
  for _, v in ipairs(run.visits) do
    for _, k in ipairs(Runs.LEAN_VISIT) do if v[k] == 0 then v[k] = nil end end
  end
  for _, b in ipairs(run.bosses) do
    for _, k in ipairs(Runs.LEAN_BOSS) do if b[k] == 0 then b[k] = nil end end
    if b.pulls == 1 then b.pulls = nil end
    if b.kill then b.ok = nil end
    if b.dur == b.combat then b.dur = nil end
  end
  leanBlock(run, "hidden"); leanBlock(run, "nDeaths"); leanBlock(run, "gold")
  for i = Runs.DEATH_FULL + 1, #run.deaths do run.deaths[i].foe, run.deaths[i].back = nil, nil end
  if #run.deaths == 0 then run.deaths = nil end
end
-- Close the open run. Returns the stored record, or nil when the run was not kept.
function Runs.close(c, run, why, at)
  at = at or nowT()
  local bossOpen = false                                         -- an encounter that began in this load and has not ended
  for _, e in pairs(type(run.encs) == "table" and run.encs or {}) do if type(e) == "table" and not e.r then bossOpen = true end end
  if run.st == "in" then
    if bossOpen and not run.partial then run.partial = "ended while a boss was in progress" end
    endVisit(c, run, at, (why == "left" or why == "ghost") and "alive" or (why == "lost" and "offline") or why)
  end
  Runs.closeEncs(run)
  run.why = why
  run.gold = Runs.goldOf(run)                                    -- (the gap after the last visit is not the run's)
  if not (type(run.xp) == "table" and num(run.xp.gain) > 0) then run.xp = nil end
  local prov = run.prov == true
  for _, k in ipairs(Runs.OPEN_KEYS) do run[k] = nil end
  c.dungeonRun = nil
  if prov then Runs.note("provisional"); return nil end         -- only the zone name ever said dungeon
  if empty(run) then Runs.note("discarded"); return nil end
  Runs.lean(run)
  local list = type(c.dungeonRuns) == "table" and c.dungeonRuns or {}
  c.dungeonRuns = list
  list[#list + 1] = run
  Runs.evict(list)
  return run
end
-- alive outside for 20 minutes, or a ghost outside for 30: the run is over
function Runs.expire(c, run, at)
  if run.st == "out" and plainNum(run.left) and at - run.left > Runs.REENTER then Runs.close(c, run, "left", at); return true end
  if run.st == "ghost" and plainNum(run.ghostAt) and at - run.ghostAt > Runs.GHOST_CAP then Runs.close(c, run, "ghost", at); return true end
  return false
end
-- End the open run now (the button comes with 0.9.51). Returns the record, or nil. While the character is still
-- inside, what comes next is the next run and opens in the same second (`open = "split"`), so no second, XP, death or
-- coin inside belongs to no run.
function Runs.endNow()
  local c = me(); local run = cur(c)
  if not (run and Runs._read) then return nil end
  local at = nowT()
  local det = Runs.detect(true)
  local w, name, kind = Runs.where(det, run)
  local bossIn, prov = run.bossIn, run.prov
  -- the encounters still open go on in the next run: the old one never sees them end (it says so), and their END,
  -- a kill right after the cut, lands on the next one. Their window there begins at the cut.
  local carry = {}
  for id, e in pairs(type(run.encs) == "table" and run.encs or {}) do
    if type(e) == "table" then local b = bossRow(run, id); carry[#carry + 1] = { id = id, name = b and b.name, d = num(e.d), r = e.r } end
  end
  local rec = Runs.close(c, run, "manual", at)
  if w == "in" then
    local nxt = openRun(c, at, safeStr(name) or "Dungeon", kind or "party", det, "split")
    if type(bossIn) == "table" then nxt.bossIn = bossIn end
    nxt.prov = prov or nil                                       -- (the same place: confirmed when the old run was)
    for _, x in ipairs(carry) do
      local b = bossRow(nxt, x.id, x.name, true)
      if b then
        if type(nxt.encs) ~= "table" then nxt.encs = {} end
        local o = Runs.clock(nxt, at)
        nxt.encs[x.id] = { t = at, o = o, d = x.d, r = x.r }
        b.pulls = num(b.pulls) + 1
        if not nxt.firstPull then nxt.firstPull = o end
      end
    end
  end
  return rec
end

-- ── two names, one dungeon ──────────────────────────────────────────────────────────────────────────────────────
-- The client gives some dungeons two names (Alcaz Prison made three DUNGEON events in one visit). When the name
-- changes while the character is inside and GetInstanceInfo's map id stays the same, the new name is learned as an
-- alias of the run's name (settings.instanceAlias, read by Emitter.canonInstance). Called by Emitter.checkInstance
-- before it compares names, so the flip raises nothing.
function Runs.alias()
  local c = me(); local run = cur(c)
  if not run or run.st ~= "in" or not Runs._read then return false end
  local det = Runs.detect()
  local name = safeStr(det.name)
  if not (det.kind and name and name ~= "" and plainNum(det.map) and det.map == run.map and not Runs.CONTINENT[det.map]) then return false end
  if canon(name) == run.inst then return false end
  local st = ns.DB.settings
  if type(st) ~= "table" then return false end
  local A = st.instanceAlias
  if type(A) ~= "table" then A = {}; st.instanceAlias = A end
  local n = 0
  for _ in pairs(A) do n = n + 1 end
  if n >= Runs.ALIAS_CAP then return false end
  A[name:lower()] = run.inst
  Runs.note("alias")
  return true
end
-- a name change with no loading screen that is no learned alias: kept as a question for the next look, no close
function Runs.candidate(run, name, det, at)
  local st = ns.DB.settings
  if type(st) ~= "table" then return end
  if type(st.selftest) ~= "table" then st.selftest = {} end
  local L = st.selftest.aliasCandidates
  if type(L) ~= "table" then L = {}; st.selftest.aliasCandidates = L end
  for _, r in ipairs(L) do if r.from == run.inst and r.to == name then r.at = at; r.n = num(r.n) + 1; return end end
  L[#L + 1] = { from = run.inst, to = name, map0 = run.map, map1 = det.map, at = at, n = 1 }
  while #L > Runs.CANDIDATE_CAP do table.remove(L, 1) end
end

-- ── the dungeon check changed, or was asked again (Emitter.checkInstance) ─────────────────────────────────────
function Runs.sync(at)
  local c = me()
  if not c then return nil end
  if Runs._pendLoad then local p = Runs._pendLoad; Runs._pendLoad = nil; Runs.loaded(p[1], p[2]) end
  if not Runs._read then return nil end                          -- (nothing is put on a clock before the load is read)
  at = plainNum(at) or nowT()
  local det = Runs.detect()
  local viaLoad, loadHow = Runs._viaLoad, Runs._loadHow
  Runs._viaLoad, Runs._loadHow = nil, nil
  local run = cur(c)
  if run and Runs.expire(c, run, at) then run = nil end
  local w, name, kind = Runs.where(det, run)
  if w == "in" then
    name = safeStr(name) or "Dungeon"
    if run and run.st == "in" then
      if name ~= run.inst then
        if viaLoad then Runs.close(c, run, "other", at); run = nil
        else Runs.candidate(run, name, det, at) end
      end
      if run then Runs.flush(run, at) end
    elseif run then
      if name ~= run.inst then Runs.close(c, run, "other", at); run = nil
      else
        local how = loadHow or (run.st == "ghost" and "ghost") or "zone"
        if run.st == "ghost" or run.st == "out" or run.st == "off" then Runs.flush(run, at) end
        beginVisit(c, run, at, how)
      end
    end
    if not run then run = openRun(c, at, name, kind or "party", det, loadHow or "zone") end
    if det.kind and det.sig ~= "name" then run.prov = nil end     -- a stronger signal than the zone name
  elseif run then
    if run.st == "in" then
      local ghost = isDead()
      endVisit(c, run, at, ghost and "ghost" or "alive")
      if not ghost then Runs.closeEncs(run) end
    elseif run.st == "off" then
      Runs.flush(run, at)
      if isDead() then run.st = "ghost"; run.ghostAt = plainNum(run.ghostAt) or at
      else run.st, run.left = "out", at; Runs.closeEncs(run) end
    else Runs.flush(run, at) end
  end
  if w == "door" and Runs._where ~= "door" then Runs.note("door") end
  Runs._where = w
  Runs._lost = nil
  return cur(c)
end

-- ── a load: login, /reload or a loading screen (Emitter's PLAYER_ENTERING_WORLD, just before its dungeon check) ──
function Runs.loaded(isLogin, isReload)
  Runs._viaLoad = true
  Runs._loadHow = (isLogin == true and "login") or (isReload == true and "reload") or nil
  local c = me()
  -- the client has not named the character yet (its GUID arrives a moment after a login): the load is read when
  -- it has, by the next dungeon check or the next tick, before any second is put on a clock
  if not c then Runs._pendLoad = { isLogin, isReload }; return end
  if not Runs._checked then Runs._checked = true; Runs.validate(c) end
  -- From here on this load may put time on a clock. Until here nothing does: the stored run still carries the mark of
  -- the last load, and a tick, a zone event or a look at the pane before this point would book the whole time since
  -- (a night offline) as seconds inside.
  Runs._read = true
  local xp, mx = xpRead()
  Runs._xp = xp and { xp = xp, mx = mx } or nil
  local run = cur(c)
  if isLogin ~= true then
    -- an encounter open across a /reload may have ended during the loading screen: it is carried, not in progress
    if isReload == true and run and type(run.encs) == "table" then
      for _, e in pairs(run.encs) do if type(e) == "table" then e.r = 1 end end
    end
    -- A combat running across a /reload: the logout booked it up to there, the rest counts from the logout's reading
    -- on, so the seconds of the loading screen are in combat as they are inside (at most a minute of them)
    if isReload == true and run and run.st == "in" and fighting() then
      local gap = plainNum(run.mark) and min(60, max(0, nowT() - run.mark)) or 0
      Runs._combatAt = GetTime() - gap
    end
    return
  end
  -- the game closed without saving since the file was written (Emitter.loadKind, 0.9.46): what the file holds of
  -- the run is all there is. It ends where the file last saw it and says so.
  local crashed = (ns.Emitter and ns.Emitter._crashed == true) or c.goldOpen ~= nil
  Runs._lost = crashed or nil
  if not run then return end
  local at = nowT()
  if crashed then
    Runs.note("lost")
    run.partial = "state lost before this login"
    Runs.close(c, run, "lost", plainNum(run.beat) or plainNum(run.endT) or at)
    return
  end
  -- a clean logout: the time since is offline, on no other clock. Encounters open at the logout were not seen ending.
  local beat = plainNum(run.beat) or at
  if run.st == "in" then endVisit(c, run, min(beat, at), "offline")
  else
    local g = type(run.gap) == "table" and run.gap or { ghost = 0, outside = 0, offline = 0 }
    run.gap = g
    local off = max(0, at - num(run.mark))
    g.offline = num(g.offline) + off; run.mark = at
    -- offline runs neither the 20 minutes alive outside nor the 30 as a ghost: both go on where the logout left them
    if plainNum(run.left) then run.left = run.left + off end
    if plainNum(run.ghostAt) then run.ghostAt = run.ghostAt + off end
  end
  Runs.flush(run, at)
  run.deadSince = nil
  Runs.closeEncs(run)
end
-- drop what this version cannot read: a record of a later version or of another shape
local function tableOrNone(v) return v == nil or type(v) == "table" end
function Runs.valid(r)
  return type(r) == "table" and plainNum(r.v) ~= nil and r.v <= Runs.V and type(r.id) == "string" and type(r.inst) == "string"
    and plainNum(r.t) ~= nil and plainNum(r.endT) ~= nil and type(r.secs) == "table" and type(r.visits) == "table" and #r.visits > 0
    and type(r.bosses) == "table" and tableOrNone(r.nDeaths) and tableOrNone(r.deaths) and tableOrNone(r.hidden) and tableOrNone(r.gold)
    and plainNum(r.secs.inside) ~= nil
end
-- an open run is written to all the time: it has every block and every clock
function Runs.validOpen(r)
  if not (Runs.valid(r) and type(r.st) == "string" and type(r.nDeaths) == "table" and type(r.deaths) == "table" and type(r.hidden) == "table") then return false end
  for _, k in ipairs(Runs.SECS) do if plainNum(r.secs[k]) == nil then return false end end
  return true
end
function Runs.validate(c)
  if c.dungeonRun ~= nil and not Runs.validOpen(c.dungeonRun) then c.dungeonRun = nil; Runs.note("dropped") end
  if c.dungeonRuns ~= nil and type(c.dungeonRuns) ~= "table" then c.dungeonRuns = nil end
  local list = c.dungeonRuns
  if not list then return end
  for i = #list, 1, -1 do
    if not Runs.valid(list[i]) then table.remove(list, i); Runs.note("dropped") end
  end
end

-- ── events ──────────────────────────────────────────────────────────────────────────────────────────────────────
function Runs.encStart(id, name)
  id = plainNum(id)
  local c = me()
  if not (c and id) then return end
  name = safeStr(name)
  local at = nowT()
  local run = cur(c)
  if not run or run.st ~= "in" then
    local det = Runs.detect(true)
    if run and Runs.expire(c, run, at) then run = nil end
    local w, wname, wkind = Runs.where(det, run)
    if w == "in" then run = Runs.sync(at)                       -- the detector says inside and had not been asked yet
    elseif w == "door" or (plainNum(det.map) and not Runs.CONTINENT[det.map]) then
      -- a boss pull where the detector does not say inside: inside until the zone or the map changes
      local zone = safeStr(det.zone)
      local inst = (w == "door" and safeStr(wname)) or (zone and zone ~= "" and canon(zone)) or "Dungeon"
      if run and run.inst ~= inst then Runs.close(c, run, "other", at); run = nil end
      if run then
        Runs.flush(run, at)
        beginVisit(c, run, at, "boss")
      else run = openRun(c, at, inst, wkind or "party", det, "boss") end
      run.bossIn = { zone = det.zone, map = det.map }
    else Runs.note("outdoorBoss"); return end                   -- a world boss: nothing opens
  end
  if not run or run.st ~= "in" then return end
  run.prov = nil
  local b = bossRow(run, id, name, true)
  if not b then return end
  if type(run.encs) ~= "table" then run.encs = {} end
  if run.encs[id] then b.unknown = num(b.unknown) + 1; Runs.note("restart") end   -- its END was never seen
  local o = Runs.clock(run, at)
  run.encs[id] = { t = at, o = o, d = 0 }
  b.pulls = num(b.pulls) + 1
  if not run.firstPull then run.firstPull = o end
end
-- Seconds with a boss up are the union of the windows of the encounters seen ending, in any order (one can end
-- inside another). run.bossWin holds the windows counted so far, merged and in order, as { from, to } epochs; this one
-- adds the part of [a, z] none of them holds. An encounter whose END is never seen adds nothing and holds nothing up.
-- A window that ends before the earliest encounter still open can meet no later one and is let go.
Runs.BOSS_WIN_CAP = 20
function Runs.bossAdd(run, a, z)
  if z <= a then return end
  local W = type(run.bossWin) == "table" and run.bossWin or {}
  local add = z - a
  for _, w in ipairs(W) do
    local lo, hi = max(a, w[1]), min(z, w[2])
    if hi > lo then add = add - (hi - lo) end
  end
  run.secs.boss = run.secs.boss + add
  local out, lo, hi, placed = {}, a, z, false
  for _, w in ipairs(W) do
    if w[2] < lo then out[#out + 1] = w
    elseif w[1] > hi then
      if not placed then out[#out + 1] = { lo, hi }; placed = true end
      out[#out + 1] = w
    else lo, hi = min(lo, w[1]), max(hi, w[2]) end
  end
  if not placed then out[#out + 1] = { lo, hi } end
  local first
  for _, e in pairs(type(run.encs) == "table" and run.encs or {}) do
    if type(e) == "table" and (not first or num(e.t) < first) then first = num(e.t) end
  end
  local keep = {}
  if first then for _, w in ipairs(out) do if w[2] > first then keep[#keep + 1] = w end end end
  while #keep > Runs.BOSS_WIN_CAP do table.remove(keep, 1) end
  run.bossWin = #keep > 0 and keep or nil
end
function Runs.encEnd(id, name, success)
  id = plainNum(id)
  local c = me(); local run = cur(c)
  if not (run and id) then return end
  local e = type(run.encs) == "table" and run.encs[id] or nil
  if type(e) ~= "table" then Runs.note("endNoStart"); return end   -- an END with no START, or a second END
  local at = nowT()
  run.encs[id] = nil
  if next(run.encs) == nil then run.encs = nil end
  Runs.bossAdd(run, num(e.t), at)
  local b = bossRow(run, id, safeStr(name))
  if not b then return end
  local dur = max(0, at - num(e.t))
  b.combat = num(b.combat) + dur
  -- the raw answer and the length of this pull, kept for the next look (what does the client send on a wipe?)
  local ok = plainNum(success)
  b.ok, b.dur = ok, dur
  if ok == 1 then
    if not b.kill then                                           -- (stored once: a later kill of the same boss changes nothing)
      b.kill = Runs.clock(run, at)
      b.fight = Runs.fightUid(num(e.t))
    end
  elseif ok == nil then b.unknown = num(b.unknown) + 1
  -- not a kill: a wipe only when the character died in the pull; else the encounter reset (the Avatar of Hakkar
  -- ends unkilled 1.2 s after its START in every clear, and nobody dies)
  elseif num(e.d) > 0 then b.wipes = num(b.wipes) + 1
  else b.resets = num(b.resets) + 1 end
end
function Runs.died()
  local c = me(); local run = cur(c)
  if not run or run.st ~= "in" then return end
  local at = nowT()
  run.nDeaths.me = num(run.nDeaths.me) + 1
  run.deadSince = at
  run.prov = nil
  local enc, encT
  for id, e in pairs(type(run.encs) == "table" and run.encs or {}) do
    e.d = num(e.d) + 1
    if not encT or num(e.t) > encT then enc, encT = id, num(e.t) end
  end
  -- (a row is the character's own death: the party's rows, from a later version, carry `who`)
  if #run.deaths < Runs.DEATH_CAP then run.deaths[#run.deaths + 1] = { o = Runs.clock(run, at), enc = enc } end
end
-- who killed the character, when the client says (Emitter's PLAYER_DEAD knows; plain or nil)
function Runs.deathFoe(foe)
  local run = cur(me())
  foe = safeStr(foe)
  if not (run and foe and run.deadSince) then return end
  local d = run.deaths[#run.deaths]
  if d and not d.who and not d.foe then d.foe = foe end
end
function Runs.alive()
  local c = me(); local run = cur(c)
  if not run or isDead() then return end
  local at = nowT()
  if plainNum(run.deadSince) then
    local d = run.deaths[#run.deaths]
    if d and not d.who and not d.back then d.back = max(0, at - run.deadSince) end
    run.deadSince = nil
  end
  if run.st == "ghost" then
    -- Walking into the instance as a ghost resurrects the character too, and this event can come before the dungeon
    -- check of that loading screen: where the character is gets asked first. Inside, the visit begins here and the
    -- encounters the party is still fighting stay open.
    if Runs.where(Runs.detect(true), run) == "in" then Runs.sync(at); return end
    -- resurrected outside (a spirit healer): the running back is over, the 20 minutes begin
    Runs.flush(run, at)
    run.st, run.left, run.ghostAt = "out", at, nil
    Runs.closeEncs(run)
  end
end
function Runs.onXP()
  local xp, mx = xpRead()
  local L = Runs._xp
  Runs._xp = xp and { xp = xp, mx = mx } or nil
  local run = cur(me())
  if not (xp and L and run and run.st == "in" and type(run.xp) == "table") then return end
  local d = xp - L.xp
  if d < 0 then d = (L.mx - L.xp) + xp end                      -- a level-up: the rest of the old bar, then the new one
  if d <= 0 or d > L.mx + mx then return end
  local v = visit(run)
  v.xp, run.xp.gain = num(v.xp) + d, num(run.xp.gain) + d
  run.prov = nil
  xpMark(run)
end
-- a kill XP line: the named form counts one kill ("<mob> dies, you gain 85 experience.")
function Runs.onXPLine(msg)
  local run = cur(me())
  if not run or run.st ~= "in" or type(msg) == "nil" then return end
  local s = safeStr(msg)
  if not s then run.hidden.xp = num(run.hidden.xp) + 1; return end
  local pats = ns.Emitter and ns.Emitter.XP_PATS
  if type(pats) ~= "table" or type(run.xp) ~= "table" then return end
  for _, pp in ipairs(pats) do
    if pp[2] == 2 then                                          -- the named forms carry the mob first, the XP second
      local caps = { s:match(pp[1]) }
      local n = caps[1] and tonumber(caps[2])
      if n then
        local v = visit(run)
        v.kills, v.xpKill = num(v.kills) + 1, num(v.xpKill) + n
        run.xp.n, run.xp.kill = num(run.xp.n) + 1, num(run.xp.kill) + n
        run.prov = nil
        return
      end
    end
  end
end
function Runs.onQuest(xp)
  local run = cur(me())
  xp = plainNum(xp)
  if not (run and run.st == "in" and xp and xp > 0 and type(run.xp) == "table") then return end
  local v = visit(run)
  v.xpQuest, run.xp.quest = num(v.xpQuest) + xp, num(run.xp.quest) + xp
end
-- a chat line the client hides while inside is counted, never read
function Runs.onHidden(kind, msg)
  local run = cur(me())
  if not run or run.st ~= "in" or type(msg) == "nil" or safeStr(msg) then return end
  run.hidden[kind] = num(run.hidden[kind]) + 1
end
function Runs.onCombat(on)
  local run = cur(me())
  if not run or run.st ~= "in" then Runs._combatAt = nil; return end
  if on then
    run.prov = nil
    if not Runs._combatAt then Runs._combatAt = GetTime() end
    if not run.firstPull then run.firstPull = Runs.clock(run) end
  else combatEnd(run) end
end
-- the 10 second tick: clocks, active seconds, the 20 and 30 minute rules, the coin of the visit so far
function Runs.tick()
  local now = GetTime()
  local last = Runs._tickAt
  Runs._tickAt = now
  local c = me()
  if c and Runs._pendLoad then Runs.detect(true); Runs.sync(); return end   -- (the load is read first; this tick counts nothing)
  if not Runs._read then return end
  local run = cur(c)
  if not run then return end
  local at = nowT()
  if run.st == "ghost" and not isDead() then
    Runs.alive()
    run = cur(c)                                                 -- (alive back inside is a dungeon check: the run may be another now)
    if not run then return end
  end
  if Runs.expire(c, run, at) then return end
  Runs.flush(run, at)
  if run.st ~= "in" then return end
  Runs.goldTake(c, run)
  if not last or (ns.Gold and ns.Gold._afk) then return end
  local v = visit(run)
  -- never more than the visit has been open: a visit that began inside this interval takes only its own seconds
  local add = min(floor(min(Runs.TICK, now - last) + 0.5), num(v.secs) - num(v.active))
  if add <= 0 then return end
  v.active, run.secs.active = num(v.active) + add, run.secs.active + add
end
function Runs.logout()
  local c = me(); local run = cur(c)
  if not run then return end
  local at = nowT()
  Runs.flush(run, at)
  if run.st == "in" then Runs.goldTake(c, run); combatEnd(run) end
end
-- what a fresh load starts with (the tests' /reload)
function Runs.newLoad()
  Runs._tickAt, Runs._xp, Runs._combatAt, Runs._viaLoad, Runs._loadHow, Runs._lost, Runs._checked, Runs._where = nil, nil, nil, nil, nil, nil, nil, nil
  Runs._pendLoad, Runs._read = nil, nil
end

local ef = CreateFrame("Frame")
ns.eventFrames = ns.eventFrames or {}
ns.eventFrames[#ns.eventFrames + 1] = ef
for _, e in ipairs({ "ENCOUNTER_START", "ENCOUNTER_END", "PLAYER_DEAD", "PLAYER_UNGHOST", "PLAYER_ALIVE", "PLAYER_XP_UPDATE",
  "CHAT_MSG_COMBAT_XP_GAIN", "CHAT_MSG_LOOT", "CHAT_MSG_COMBAT_FACTION_CHANGE", "QUEST_TURNED_IN", "PLAYER_REGEN_DISABLED",
  "PLAYER_REGEN_ENABLED", "PLAYER_LOGOUT" }) do pcall(ef.RegisterEvent, ef, e) end
Runs.HANDLERS = {
  ENCOUNTER_START = function(id, name) Runs.encStart(id, name) end,
  ENCOUNTER_END = function(id, name, _, _, success) Runs.encEnd(id, name, success) end,
  PLAYER_DEAD = function() Runs.died() end,
  PLAYER_UNGHOST = function() Runs.alive() end,
  PLAYER_ALIVE = function() Runs.alive() end,
  PLAYER_XP_UPDATE = function() Runs.onXP() end,
  CHAT_MSG_COMBAT_XP_GAIN = function(msg) Runs.onXPLine(msg) end,
  CHAT_MSG_LOOT = function(msg) Runs.onHidden("loot", msg) end,
  CHAT_MSG_COMBAT_FACTION_CHANGE = function(msg) Runs.onHidden("rep", msg) end,
  QUEST_TURNED_IN = function(_, xp) Runs.onQuest(xp) end,
  PLAYER_REGEN_DISABLED = function() Runs.onCombat(true) end,
  PLAYER_REGEN_ENABLED = function() Runs.onCombat(false) end,
  PLAYER_LOGOUT = function() Runs.logout() end,
}
ef:SetScript("OnEvent", function(_, event, ...)
  local h = Runs.HANDLERS[event]
  if not h then return end
  if Runs._pendLoad and me() then Runs.detect(true); Runs.sync() end   -- the client named the character: the load is read first
  if not Runs._read then return end                              -- no event of a load is taken before the load is read
  local ok, err = pcall(h, ...)
  if not ok then Runs._err = err end
end)
if C_Timer and C_Timer.NewTicker then
  Runs._ticker = C_Timer.NewTicker(Runs.TICK, function()
    local ok, err = pcall(Runs.tick)
    if not ok then Runs._err = err end
  end)
end

-- ── views (Combat > Dungeons, /eb run) ──────────────────────────────────────────────────────────────────────────
local function fmtDur(sec)
  sec = floor(num(sec) + 0.5)
  if sec >= 3600 then return ("%dh %dm"):format(floor(sec / 3600), floor((sec % 3600) / 60)) end
  if sec >= 60 then return ("%dm %ds"):format(floor(sec / 60), sec % 60) end
  return sec .. "s"
end
Runs.fmtDur = fmtDur
function Runs.commas(n)
  local s = tostring(floor(num(n) + 0.5))
  local out, k = s:reverse():gsub("(%d%d%d)", "%1,")
  out = out:reverse()
  if out:sub(1, 1) == "," then out = out:sub(2) end
  return out
end
-- a boss row's result, as the page says it
function Runs.bossResult(b)
  if b.kill then return "Killed", "kill" end
  if num(b.wipes) > 0 then return "Wiped", "wipe" end
  if num(b.unknown) > 0 then return "Outcome not seen", "unknown" end
  if num(b.resets) > 0 then return "Reset", "reset" end
  return "Not killed", "none"
end
-- One run as the pane reads it. The record is never changed by a view, except that an open run is brought up to
-- the second first. `full`: also the fights and the rare-or-better loot rows still stored, by the time of the
-- run's visits (never by a row's zone: a loot row's zone is the one of the last loot window, often another place).
function Runs.view(rec, isOpen, full)
  local c = me()
  local at = nowT()
  if isOpen and c and Runs._read then
    Runs.flush(rec, at)
    if rec.st == "in" then Runs.goldTake(c, rec) end
  end
  local s = rec.secs
  local gap = isOpen and type(rec.gap) == "table" and rec.gap or nil
  local nD = type(rec.nDeaths) == "table" and rec.nDeaths or {}
  -- (a closed record leaves out what is 0 or empty, Runs.lean)
  local v = { rec = rec, id = rec.id, name = rec.inst, kind = rec.kind, startT = rec.t, endT = (not isOpen) and rec.endT or nil,
    inProgress = isOpen and true or false, why = rec.why, partial = rec.partial, opened = rec.open,
    inside = num(s.inside), ghost = num(s.ghost) + num(gap and gap.ghost), outside = num(s.outside) + num(gap and gap.outside),
    offline = num(s.offline) + num(gap and gap.offline), active = num(s.active), combat = num(s.combat), boss = num(s.boss),
    visits = rec.visits, bosses = rec.bosses, deathRows = type(rec.deaths) == "table" and rec.deaths or {}, deaths = num(nD.me), partyDeaths = num(nD.party),
    hidden = rec.hidden, xp = rec.xp, state = isOpen and rec.st or nil }
  v.duration = v.inside + v.ghost                                -- the run's clock: inside and running back
  v.splits = Runs.splits(rec)
  v.reentries = max(0, #rec.visits - 1)
  for _, x in ipairs(rec.visits) do v.reentries = v.reentries + num(x.n) end
  v.gold = isOpen and Runs.goldOf(rec) or (type(rec.gold) == "table" and rec.gold) or Runs.goldOf(rec)
  v.items, v.coin = num(v.gold.items), num(v.gold.looted) + num(v.gold.quests)
  local down, pulls, wipes, unseen = 0, 0, 0, 0
  for _, b in ipairs(rec.bosses) do
    pulls, wipes = pulls + (b.pulls or 1), wipes + num(b.wipes)
    if b.kill then down = down + 1 elseif num(b.unknown) > 0 then unseen = unseen + 1 end
  end
  v.bossesDown, v.pulls, v.wipes, v.unseen = down, pulls, wipes, unseen
  local warm = v.active >= Runs.RATE_WARM
  v.xpGain = type(rec.xp) == "table" and num(rec.xp.gain) or 0
  v.xpPerHour = (warm and v.xpGain > 0) and v.xpGain * 3600 / v.active or nil
  v.coinPerHour = warm and v.coin * 3600 / v.active or nil
  if full then
    v.fights = Runs.rowsOf(rec, ns.Fights and ns.Fights.list and ns.Fights.list(), "startEpoch")
    local grp
    for _, f in ipairs(v.fights) do
      if type(f.group) == "table" and (not grp or #f.group > #grp) then grp = f.group end
    end
    v.group = grp
    v.notable = Runs.rowsOf(rec, ns.DB and ns.DB.loot and ns.DB.loot.log, "t", function(l) return not l.money and Runs.qRank(l.q) >= 3 end)
  end
  return v
end
-- whether a moment lies in one of the run's visits (a visit with no end is the one the character is in now). The
-- one test for "of this run", for the run page and for the run headers of the Fights list alike.
function Runs.inRun(rec, t)
  t = plainNum(t)
  if not t then return false end
  t = t - rec.t
  for _, x in ipairs(rec.visits) do
    if t >= num(x.i) and t <= (x.o or math.huge) then
      -- (a row that absorbed later stretches: the time between them was outside)
      local gp, out = type(x.gaps) == "table" and x.gaps or nil, false
      if gp then for k = 1, #gp - 1, 2 do if t > num(gp[k]) and t < num(gp[k + 1]) then out = true; break end end end
      if not out then return true end
    end
  end
  return false
end
-- the stored run of the logged-in character a moment belongs to (newest first, the open one before the closed), or nil
function Runs.runAt(t)
  local c = me()
  if not (c and plainNum(t)) then return nil end
  local run = cur(c)
  if run and Runs.valid(run) and Runs.inRun(run, t) then return run end
  local list = type(c.dungeonRuns) == "table" and c.dungeonRuns or {}
  for i = #list, 1, -1 do
    local r = list[i]
    if Runs.valid(r) then
      if Runs.inRun(r, t) then return r end
      if r.endT < t - 86400 then return nil end                  -- (the list is oldest first: nothing older can hold it)
    end
  end
  return nil
end
-- The logged-in character's rows of a stored list (fights, loot rows) that lie in the run's visits, oldest first.
-- Both lists are written in time order, so they are read from their end and the reading stops once it is past the
-- run's start (Runs.TAIL_SLACK rows in a row from before it: a row can sit a little out of order), never the whole
-- list of up to 5000 fights or 2000 loot rows.
Runs.TAIL_SLACK = 20
function Runs.rowsOf(rec, list, tkey, want)
  local rev, older = {}, 0
  if type(list) ~= "table" then return rev end
  for i = #list, 1, -1 do
    local r = list[i]
    local t = type(r) == "table" and plainNum(r[tkey]) or nil
    if t then
      if t < rec.t then
        older = older + 1
        if older >= Runs.TAIL_SLACK then break end
      else
        older = 0
        if Runs.inRun(rec, t) and (not want or want(r)) and ns.isMine(r) then rev[#rev + 1] = r end
      end
    end
  end
  local out = {}
  for i = #rev, 1, -1 do out[#out + 1] = rev[i] end
  return out
end
Runs.Q_RANK = { ff9d9d9d = 0, ffffffff = 1, ff1eff00 = 2, ff0070dd = 3, ffa335ee = 4, ffff8000 = 5, ffe6cc80 = 6 }
function Runs.qRank(q) return Runs.Q_RANK[type(q) == "string" and q:lower() or ""] or 1 end
-- the runs of the logged-in character, oldest first, the open one last
function Runs.views(full)
  local out = {}
  local c = me()
  if not c then return out end
  for _, r in ipairs(type(c.dungeonRuns) == "table" and c.dungeonRuns or {}) do
    if Runs.valid(r) then out[#out + 1] = Runs.view(r, false, full) end
  end
  local run = cur(c)
  if run and Runs.valid(run) then out[#out + 1] = Runs.view(run, true, full) end
  return out
end
-- Two lines, so that no clock is cut at the narrowest window:
--   "Inside 31m 10s · running back 2m 05s · outside 4m 30s · offline 1h 56m"   where the wall time went
--   "Active 28m 40s · in combat 14m 2s (bosses 3m 10s)"                        what was done inside
function Runs.timeLine(v)
  local SEP = "  ·  "
  local a = { "Inside " .. fmtDur(v.inside) }
  if v.ghost > 0 then a[#a + 1] = "running back " .. fmtDur(v.ghost) end
  if v.outside > 0 then a[#a + 1] = "outside " .. fmtDur(v.outside) end
  if v.offline > 0 then a[#a + 1] = "offline " .. fmtDur(v.offline) end
  local b = { "Active " .. fmtDur(v.active) }
  if v.combat > 0 or v.boss > 0 then
    b[#b + 1] = "in combat " .. fmtDur(v.combat) .. (v.boss > 0 and (" (bosses " .. fmtDur(v.boss) .. ")") or "")
  end
  return table.concat(a, SEP), table.concat(b, SEP)
end
-- How many more runs like this one reach the next level, from the XP of its kills alone (a quest is handed in
-- once). Only for a run that is over, and only when the bar it ended on is known.
function Runs.runsToLevel(v)
  local x = v.xp
  if v.inProgress or type(x) ~= "table" or num(x.kill) <= 0 or not (plainNum(x.need) and plainNum(x.p1) and plainNum(x.l1)) then return nil end
  local n = math.ceil(x.need * (1 - x.p1) / x.kill)
  if n < 1 or n > 999 then return nil end
  return n, x.l1 + 1
end
-- "12,300 XP · 23,000 per hour · level 23.4 to 24.1 · about 6 more runs to level 25", then on a line of their own
-- the quest XP and the kills the client let the addon read, then what it hid. Returns the three (the last two or nil).
function Runs.xpLine(v)
  local x = v.xp
  if type(x) ~= "table" or v.xpGain <= 0 then return nil end
  local SEP = "  ·  "
  local parts = { Runs.commas(v.xpGain) .. " XP" }
  if v.xpPerHour then parts[#parts + 1] = Runs.commas(v.xpPerHour) .. " per hour" end
  if x.l0 and x.p0 and x.l1 and x.p1 then parts[#parts + 1] = ("level %.1f to %.1f"):format(x.l0 + floor(x.p0 * 10) / 10, x.l1 + floor(x.p1 * 10) / 10) end
  local more, lvl = Runs.runsToLevel(v)
  if more then parts[#parts + 1] = ("about %d more run%s to level %d"):format(more, more == 1 and "" or "s", lvl) end
  local second = {}
  if num(x.quest) > 0 then second[#second + 1] = Runs.commas(x.quest) .. " XP from quests" end
  local hid = num(v.hidden and v.hidden.xp)
  if num(x.n) > 0 then
    second[#second + 1] = hid > 0 and ("at least %s kills"):format(Runs.commas(x.n)) or ("%s kill%s"):format(Runs.commas(x.n), x.n == 1 and "" or "s")
  end
  -- (the addon cannot read a hidden line, so it does not say what kind of XP line it was)
  return table.concat(parts, SEP), #second > 0 and table.concat(second, SEP) or nil,
    hid > 0 and ("%d XP line%s hidden by the client."):format(hid, hid == 1 and " was" or "s were") or nil
end
-- The looted coin beside what the purse itself gained inside (less quest coin), when the two differ:
--   "Coin 3s 65c of 1g 12s gained inside"   the purse gained more: group shares, a trade, coin booked elsewhere
--   "Looted 50s, purse up 30s inside"       the purse gained less: coin was spent inside (a repair, a vendor)
-- Nothing when the purse did not grow.
function Runs.purseLine(v)
  local g = v.gold
  local looted, purse = num(g and g.looted), num(g and g.purse)
  if not g or purse == looted or purse <= 0 then return nil end
  if purse > looted then return ("Coin %s of %s gained inside"):format(ns.fmtMoney(looted), ns.fmtMoney(purse)) end
  return ("Looted %s, purse up %s inside"):format(ns.fmtMoney(looted), ns.fmtMoney(purse))
end
function Runs.endedLine(v)
  if v.inProgress then return nil end
  return "Ended: " .. (Runs.WHY[v.why] or "left the dungeon")
end
function Runs.partialLine(v)
  if not v.partial then return nil end
  if v.partial == "ended while a boss was in progress" then return "Part of this run is missing: it ended while a boss was in progress." end
  return "Part of this run was lost: the game closed without saving."
end
-- /eb run: the open run, else the last, in the player's own chat. Opens, moves and sends nothing, so it also answers
-- in combat. "The Deadmines, 32m 10s, bosses 5, 2 deaths, 12,300 XP (23,000 per hour), 2g 30s 5c."
function Runs.line(v)
  local parts = { v.name .. (v.inProgress and " (in progress)" or ""), fmtDur(v.duration), "bosses " .. v.bossesDown,
    ("%d death%s"):format(v.deaths, v.deaths == 1 and "" or "s") }
  if v.xpGain > 0 then
    parts[#parts + 1] = Runs.commas(v.xpGain) .. " XP" .. (v.xpPerHour and (" (" .. Runs.commas(v.xpPerHour) .. " per hour)") or "")
  end
  parts[#parts + 1] = ns.fmtMoney(v.coin)
  return table.concat(parts, ", ") .. "."
end
function Runs.slash()
  if not me() then ns.msg("run: the character is not known yet, try again in a moment"); return true end
  local list = Runs.views()
  local v = list[#list]
  if not v then ns.msg("run: no dungeon run yet. " .. Runs.SINCE); return true end
  ns.msg(Runs.line(v))
  return true
end

ns._test = ns._test or {}
ns._test.Runs = Runs
-- a closed record of the smallest valid shape, lean as a stored one is: `inside` seconds in one visit, `over` laid
-- on top (tests, fixtures)
ns._test.runRecord = function(inst, t, inside, over)
  local r = { id = ("test-%d-%04x"):format(t, math.random(0, 0xFFFF)), v = Runs.V, inst = inst, kind = "party", t = t, endT = t + inside,
    open = "zone", why = "left",
    visits = { { i = 0, o = inside, how = "zone", out = "alive", secs = inside, active = inside, xp = 0, xpKill = 0, xpQuest = 0, kills = 0,
      looted = 0, quests = 0, lootValue = 0, items = 0, purse = 0 } },
    secs = { inside = inside, ghost = 0, outside = 0, offline = 0, active = inside, combat = 0, boss = 0 },
    bosses = {}, nDeaths = { me = 0, party = 0 }, deaths = {}, hidden = { xp = 0, rep = 0, loot = 0 },
    gold = { looted = 0, quests = 0, lootValue = 0, items = 0, purse = 0 } }
  for k, v in pairs(over or {}) do r[k] = v end
  Runs.lean(r)
  return r
end
