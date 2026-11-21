-- Everbuff.GG · Runs.lua - the durable dungeon run (0.9.50, everbuff-wow-addon #51).
--
-- Until 0.9.49 a run was rebuilt at view time from the DUNGEON and DUNGEONLEAVE story events, which the 500 row cap
-- and the desktop's acknowledgement remove within hours. From 0.9.50 a run is a stored record of the logged-in
-- character: `characters[guid].dungeonRun` while it is open, `characters[guid].dungeonRuns[]` once closed (oldest
-- first, at most Runs.CAP). The acknowledgement never touches either. Of the time before 0.9.50 only
-- what the character's gold runs still hold is kept, as partial rows of their own (RunsLegacy.lua).
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
--
-- From 0.9.51 (record version 2): bests, statistics and undo. A closed run is added to the character's statistics
-- of its dungeon (characters[guid].dungeonStats, never evicted), which keep a best per route (the set of bosses
-- killed, with the difficulty and solo or group), the best segments and a learned boss list. A visit row keeps the
-- gap before it (gg, go, gf) and its own combat and boss seconds, and a boss row its first pull (p) when that is not
-- where its kill pull began, so a run can be split at a visit and joined again to the copper (Runs.splitRec,
-- Runs.joinRec). characters[guid].dungeonCopies[] counts the instances entered in the last 24 hours.

local ADDON, ns = ...

local Runs = {}
ns.Runs = Runs

Runs.V = 2                 -- record version (2 from 0.9.51: the gap before a visit, per visit combat and boss seconds)
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
Runs.OPEN_KEYS = { "st", "mark", "beat", "left", "ghostAt", "gap", "encs", "deadSince", "m0", "g0", "bossIn", "bossWin", "prov", "copied" }
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
  for id, e in pairs(run.encs) do
    local b = bossRow(run, id)
    if b then
      b.unknown = num(b.unknown) + 1
      local L = Runs.levels(b, type(e) == "table" and plainNum(e.rp) or 0)
      for i = 2, #L do L[i].unknown = num(L[i].unknown) + 1 end
    end
    n = n + 1
  end
  run.encs = nil
  return n
end
-- Where a boss row was first pulled, on the run's clock: `p` when stored, else where its kill pull began (the kill
-- less the length of its last pull), else 0 (a row of 0.9.50 never killed).
function Runs.pullOf(b)
  if plainNum(b.p) then return b.p end
  if plainNum(b.kill) then return b.kill - num(b.dur or b.combat) end
  return 0
end
-- The copies of a boss row. A boss killed in an earlier visit and pulled again keeps those pulls apart on its row
-- (`r2`, Runs.encStart), and once that part has a kill and the boss is pulled in a later visit still, a part of its
-- own inside it (`r2.r2`): each part holds its copy and every later one, `v` the visit of its first pull, at most
-- Runs.PART_CAP parts (later pulls go to the last). Runs.levels: the row and its parts, outermost first, at most `d`
-- parts when given. Runs.parts: the copies one by one (each part less the one inside it), every field explicit.
-- Runs.stack: the row again from such a list, the fields of `base` (enc, name) on the outermost.
Runs.PART_CAP = 2
Runs.PART_SUM = { "wipes", "resets", "unknown", "combat" }
function Runs.levels(b, d)
  local out, x = { b }, b
  while type(x.r2) == "table" and #out <= (d or Runs.PART_CAP) do x = x.r2; out[#out + 1] = x end
  return out
end
function Runs.parts(b)
  local L, out = Runs.levels(b), {}
  for i, x in ipairs(L) do
    local nx = L[i + 1]
    local y = { p = Runs.pullOf(x), kill = plainNum(x.kill), fight = x.fight, ok = x.ok, dur = num(x.dur or x.combat), v = i > 1 and plainNum(x.v) or nil }
    y.pulls = max(1, (x.pulls or 1) - (nx and (nx.pulls or 1) or 0))
    for _, k in ipairs(Runs.PART_SUM) do y[k] = max(0, num(x[k]) - (nx and num(nx[k]) or 0)) end
    out[i] = y
  end
  return out
end
function Runs.stack(P, base)
  -- (past the cap, the later copies go to the last part kept, as Runs.encStart puts them)
  while #P > Runs.PART_CAP + 1 do
    local z, y = table.remove(P), P[#P]
    y.pulls = y.pulls + z.pulls
    for _, k in ipairs(Runs.PART_SUM) do y[k] = y[k] + z[k] end
  end
  local below
  for i = #P, 1, -1 do
    local s = P[i]
    local x = i == 1 and Runs.copy(base) or {}
    x.p, x.kill, x.fight, x.ok, x.dur, x.v = s.p, s.kill, s.fight, s.ok, s.dur, i > 1 and s.v or nil
    x.pulls = s.pulls + (below and below.pulls or 0)
    for _, k in ipairs(Runs.PART_SUM) do x[k] = s[k] + (below and below[k] or 0) end
    x.r2 = below
    below = x
  end
  return below
end
-- the visit "Possibly two runs" points at: the first visit of a part of a copy after the first, on any boss row (nil
-- when no part says which visit it began in: a record of 0.9.51's review round 2 keeps its own mark)
function Runs.repullOf(rec)
  local v
  for _, b in ipairs(type(rec.bosses) == "table" and rec.bosses or {}) do
    local L = Runs.levels(b)
    for i = 2, #L do local x = plainNum(L[i].v); if x and x >= 2 and (not v or x < v) then v = x end end
  end
  return v
end
function Runs.hasParts(rec)
  for _, b in ipairs(type(rec.bosses) == "table" and rec.bosses or {}) do if type(b.r2) == "table" and plainNum(b.r2.v) then return true end end
  return false
end
-- A run's route against its dungeon's learned list (`v`, a view): the kills and the list's size when the route
-- skipped bosses of the list, so a best on it is named "best (5/12)" or "the best for these 5 bosses"; nil for a full
-- clear, or while the dungeon has no list
function Runs.routePart(v)
  if type(v) ~= "table" or v.done or not plainNum(v.total) then return nil end
  local n = num(v.bossesDown)
  if n >= v.total then return nil end
  return n, v.total
end
-- the visit of a record a clock offset lies in (`starts`, Runs.visitClocks)
function Runs.visitAt(starts, o)
  local j = 1
  for q = 2, #starts do if starts[q] <= o then j = q end end
  return j
end
-- The kills of a run in groups, in kill order: kills whose pulls overlapped (the Zul'Farrak pair, two bosses pulled
-- 17 ms apart and killed 5 s apart) are one group, so a split and a segment never depend on which of the two died
-- first. Each group: `ids` (encounter ids, sorted), `key` (the ids joined with "+"), `z` (the last kill of the group).
function Runs.groups(rec)
  local ks = {}
  for i, b in ipairs(rec.bosses or {}) do
    if plainNum(b.kill) and plainNum(b.enc) then ks[#ks + 1] = { b = b, i = i, a = b.kill - num(b.dur or b.combat) } end
  end
  table.sort(ks, function(x, y) if x.b.kill ~= y.b.kill then return x.b.kill < y.b.kill end return x.i < y.i end)
  local out, g = {}, nil
  for _, k in ipairs(ks) do
    if g and k.a < g.z then g.ids[#g.ids + 1] = k.b.enc; g.z = max(g.z, k.b.kill)
    else g = { ids = { k.b.enc }, z = k.b.kill }; out[#out + 1] = g end
  end
  for _, x in ipairs(out) do table.sort(x.ids); x.key = table.concat(x.ids, "+") end
  return out
end
-- A boss's segment: the seconds on the run's clock from the kill (group) before it, or from the first pull, to its
-- own kill (group), and the encounter killed before it. Worked out from the kills, never stored:
-- { [enc] = { seg, prev, at, key, prevKey } }, `at` the seconds from the first pull, `key` its group, `prevKey` the
-- group before ("start" for the first).
function Runs.splits(rec)
  local out, fp = {}, num(rec.firstPull)
  local prevZ, prevEnc, prevKey = fp, nil, "start"
  for _, g in ipairs(Runs.groups(rec)) do
    for _, id in ipairs(g.ids) do out[id] = { seg = max(0, g.z - prevZ), prev = prevEnc, at = g.z - fp, key = g.key, prevKey = prevKey } end
    local lastEnc
    for _, b in ipairs(rec.bosses) do if b.kill == g.z then lastEnc = b.enc end end
    prevZ, prevEnc, prevKey = g.z, lastEnc, g.key
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
-- The first combat or encounter start of the run (`firstPull`) and of the visit (`fc`, from 0.9.51), both on the
-- run's clock: a run split at a visit begins its measure at that visit's first combat, trash included.
local function pulled(run, o)
  if not run.firstPull then run.firstPull = o end
  local v = visit(run)
  if v and not plainNum(v.fc) then v.fc = o end
end
Runs.pulled = pulled
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
    local row = { i = at - run.t, how = how, secs = 0, active = 0, xp = 0, xpKill = 0, xpQuest = 0, kills = 0,
      looted = 0, quests = 0, lootValue = 0, items = 0, purse = 0, combat = 0, boss = 0 }
    -- the gap before this visit, by kind (0.9.51): a split and a join put it where it belongs, to the second
    if type(g) == "table" and #run.visits > 0 then
      if num(g.ghost) > 0 then row.gg = g.ghost end
      if num(g.outside) > 0 then row.go = g.outside end
      if num(g.offline) > 0 then row.gf = g.offline end
    end
    run.visits[#run.visits + 1] = row
  end
  run.st, run.mark, run.beat, run.left, run.ghostAt = "in", at, at, nil, nil
  run.m0, run.g0 = purse(), Runs.goldNow(c)
  -- a combat already running when the visit begins (walked in fighting, or the next run of a split) counts from here
  Runs._combatAt = nil
  if fighting() then
    Runs._combatAt = GetTime()
    pulled(run, Runs.clock(run, at))
    run.prov = nil
  end
end
local function combatEnd(run)
  if not Runs._combatAt then return end
  local d = floor(max(0, GetTime() - Runs._combatAt) + 0.5)
  Runs._combatAt = nil
  run.secs.combat = run.secs.combat + d
  local v = visit(run)
  if v then v.combat = num(v.combat) + d end
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
  run.size = Runs.groupSize()
  c.dungeonRun = run
  beginVisit(c, run, at, how)
  Runs.copyCheck(c, run)
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
-- The oldest run without `keep` goes. Its numbers stay in the statistics (they are never evicted); the latest end of
-- an evicted run is kept (`dungeonEvictedTo`), so a join never skips over a run that is no longer listed.
function Runs.evict(list, c)
  Runs._gen = num(Runs._gen) + 1
  while #list > Runs.CAP do
    local drop = 1
    for i = 1, #list do if not list[i].keep then drop = i; break end end
    local gone = table.remove(list, drop)
    if c and type(gone) == "table" and plainNum(gone.endT) then c.dungeonEvictedTo = max(num(c.dungeonEvictedTo), gone.endT) end
    -- (a best segment it held keeps its seconds and drops the id: no Delete can reach the run any more, and the id is
    -- most of the entry's size in the save file)
    local st = c and type(gone) == "table" and type(c.dungeonStats) == "table" and c.dungeonStats[Runs.keyOf(gone)]
    for _, r in pairs(type(st) == "table" and type(st.routes) == "table" and st.routes or {}) do
      for _, x in pairs(type(r.seg) == "table" and r.seg or {}) do if type(x) == "table" and x.id == gone.id then x.id = nil end end
    end
  end
end
-- A closed record is lean: a visit or a boss row keeps a counter only when it is not 0 (the whole save file is
-- uploaded at every /reload and logout, and a run is kept for a long time). Readers take a missing counter as 0.
Runs.LEAN_VISIT = { "active", "xp", "xpKill", "xpQuest", "kills", "looted", "quests", "lootValue", "items", "purse", "combat", "boss" }
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
-- (a boss row, and the second copy's part of one, `r2`, by the same rules)
function Runs.leanBoss(b)
  for _, k in ipairs(Runs.LEAN_BOSS) do if b[k] == 0 then b[k] = nil end end
  if b.pulls == 1 then b.pulls = nil end
  -- (the first pull is stored only where a reader cannot take it from the kill: kill less the last pull's length)
  if b.kill and b.p == b.kill - num(b.dur or b.combat) then b.p = nil end
  if b.kill then b.ok = nil end
  if b.dur == b.combat then b.dur = nil end
end
function Runs.lean(run)
  local s = run.secs
  for _, k in ipairs(Runs.SECS) do if k ~= "inside" and s[k] == 0 then s[k] = nil end end
  for _, v in ipairs(run.visits) do
    for _, k in ipairs(Runs.LEAN_VISIT) do if v[k] == 0 then v[k] = nil end end
  end
  for _, b in ipairs(run.bosses) do for _, x in ipairs(Runs.levels(b)) do Runs.leanBoss(x) end end
  -- (the first visit's first combat is the run's own `firstPull`; XP counts of 0 a reader takes as 0)
  local v1 = run.visits[1]
  if v1 and v1.fc ~= nil and v1.fc == run.firstPull then v1.fc = nil end
  if run.size ~= 1 then run.size = nil end                      -- (the one value a reader asks: solo or not, Runs.sigOf)
  if type(run.xp) == "table" then for _, k in ipairs({ "kill", "quest", "n" }) do if run.xp[k] == 0 then run.xp[k] = nil end end end
  leanBlock(run, "hidden"); leanBlock(run, "nDeaths"); leanBlock(run, "gold")
  for i = Runs.DEATH_FULL + 1, #run.deaths do run.deaths[i].foe, run.deaths[i].back = nil, nil end
  if #run.deaths == 0 then run.deaths = nil end
end
-- Close the open run. Returns the stored record, or nil when the run was not kept. `drop`: not stored at all (the
-- open run deleted by hand). `exact`: the close is proven, not the 20 minute estimate (another map id).
function Runs.close(c, run, why, at, drop, exact)
  at = at or nowT()
  if not drop then Runs.copyCheck(c, run) end
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
  if drop then Runs.note("deleted"); return nil end
  if prov then Runs.note("provisional"); return nil end         -- only the zone name ever said dungeon
  if empty(run) then Runs.note("discarded"); return nil end
  if exact then run.exact = true end
  Runs.lean(run)
  local list = type(c.dungeonRuns) == "table" and c.dungeonRuns or {}
  c.dungeonRuns = list
  list[#list + 1] = run
  Runs.statsAdd(c, run)
  Runs.evict(list, c)
  return run
end
-- alive outside for 20 minutes, or a ghost outside for 30: the run is over
function Runs.expire(c, run, at)
  if run.st == "out" and plainNum(run.left) and at - run.left > Runs.REENTER then Runs.close(c, run, "left", at); return true end
  if run.st == "ghost" and plainNum(run.ghostAt) and at - run.ghostAt > Runs.GHOST_CAP then Runs.close(c, run, "ghost", at); return true end
  return false
end
-- another instance with another map id: proven, not estimated
function Runs.mapChanged(run, det)
  return (plainNum(det.map) and plainNum(run.map) and det.map ~= run.map) and true or false
end
-- End the open run now (the End run now button). Returns the record, or nil. While the character is still inside,
-- what comes next is the next run and opens in the same second (`open = "split"`), so no second, XP, death or coin
-- inside belongs to no run. `drop`: the open run is deleted, not stored (Delete run on the open run).
function Runs.endNow(drop)
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
  local rec = Runs.close(c, run, "manual", at, drop)
  if w == "in" then
    local nxt = openRun(c, at, safeStr(name) or "Dungeon", kind or "party", det, "split")
    nxt.copied = true                                            -- (the same copy of the dungeon: no new instance)
    if type(bossIn) == "table" then nxt.bossIn = bossIn end
    nxt.prov = prov or nil                                       -- (the same place: confirmed when the old run was)
    for _, x in ipairs(carry) do
      local b = bossRow(nxt, x.id, x.name, true)
      if b then
        if type(nxt.encs) ~= "table" then nxt.encs = {} end
        local o = Runs.clock(nxt, at)
        nxt.encs[x.id] = { t = at, o = o, d = x.d, r = x.r }
        if num(b.pulls) == 0 then b.p = o end
        b.pulls = num(b.pulls) + 1
        pulled(nxt, o)
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
        if viaLoad then Runs.close(c, run, "other", at, false, Runs.mapChanged(run, det)); run = nil
        else Runs.candidate(run, name, det, at) end
      end
      if run then Runs.flush(run, at) end
    elseif run then
      if name ~= run.inst then Runs.close(c, run, "other", at, false, Runs.mapChanged(run, det)); run = nil
      else
        local how = loadHow or (run.st == "ghost" and "ghost") or "zone"
        if run.st == "ghost" or run.st == "out" or run.st == "off" then Runs.flush(run, at) end
        beginVisit(c, run, at, how)
      end
    end
    if not run then run = openRun(c, at, name, kind or "party", det, loadHow or "zone") end
    if det.kind and det.sig ~= "name" then run.prov = nil end     -- a stronger signal than the zone name
    -- the difficulty, once the client names one inside (a run opened before it said instance has 0 or none)
    if (det.sig == "type" or det.sig == "ptype") and plainNum(det.diff) and det.diff > 0 and not (plainNum(run.diff) and run.diff > 0) then run.diff = det.diff end
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
  -- an open run of 0.9.50 with one visit has had no gap yet: it is a record of this version from here on
  local o = c.dungeonRun
  if o and o.v == 1 and #o.visits == 1 then o.v = Runs.V end
  if c.dungeonRuns ~= nil and type(c.dungeonRuns) ~= "table" then c.dungeonRuns = nil end
  if c.dungeonStats ~= nil and type(c.dungeonStats) ~= "table" then c.dungeonStats = nil end
  if c.dungeonCopies ~= nil and type(c.dungeonCopies) ~= "table" then c.dungeonCopies = nil end
  local list = c.dungeonRuns
  if not list then return end
  for i = #list, 1, -1 do
    if not Runs.valid(list[i]) then table.remove(list, i); Runs.note("dropped")
    else
      list[i].pb = nil                                           -- (a mark the first builds of 0.9.51 stored: worked out now)
      if list[i].notIn ~= nil and type(list[i].notIn) ~= "table" then list[i].notIn = nil end
    end
  end
  -- the statistics begin with the runs stored since 0.9.50 (stored records, not rebuilt from story events)
  if c.dungeonStats == nil and #list > 0 then Runs.statsRebuild(c) end
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
  local was = run.encs[id]
  if was then                                                    -- its END was never seen
    b.unknown = num(b.unknown) + 1; Runs.note("restart")
    local L = Runs.levels(b, type(was) == "table" and plainNum(was.rp) or 0)
    for i = 2, #L do L[i].unknown = num(L[i].unknown) + 1 end
  end
  local o = Runs.clock(run, at)
  -- A boss killed before this visit began is pulled again: possibly a new copy of the dungeon (plan section 6, rule
  -- 3). Only a flag and the Split button at that visit; never a split by itself. The pulls of that copy, in this
  -- visit and any later one, are also kept apart on the row (a part, Runs.levels), so Split here at the visit the
  -- copy began in gives them to the second part as a row of its own (Runs.splitRec) and a join puts them back. The
  -- part of the newest copy takes every later pull until it has a kill and the boss is pulled in a later visit
  -- still: then a part of its own begins there. The mark stays on the first visit a copy began in.
  local L = Runs.levels(b)
  local tail = L[#L]
  if plainNum(tail.kill) and #run.visits > 1 and #L <= Runs.PART_CAP then
    local starts = Runs.visitClocks(run)
    local n = #run.visits
    if starts and tail.kill < num(starts[n]) then
      tail.r2 = { pulls = 0, wipes = 0, resets = 0, unknown = 0, combat = 0, p = o, v = n }
      L[#L + 1] = tail.r2
      if not (plainNum(run.repull) and run.repull <= n) then run.repull = n end
      Runs.note("repull")
    end
  end
  run.encs[id] = { t = at, o = o, d = 0, rp = #L > 1 and (#L - 1) or nil }
  for _, x in ipairs(L) do
    if num(x.pulls) == 0 then x.p = o end
    x.pulls = num(x.pulls) + 1
  end
  pulled(run, o)
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
  local v = visit(run)
  if v and add > 0 then v.boss = num(v.boss) + add end
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
  -- (once killed, `dur` stays the kill pull's length: a later pull of the same boss, a farm reset in the same run,
  -- must not move where the kill pull began, Runs.pullOf and Runs.groups)
  -- (the second copy's part of a row, Runs.encStart, gets the same: its own kill, pull length and counts, and the
  -- row keeps the sums of both)
  for i, x in ipairs(Runs.levels(b, plainNum(e.rp) or 0)) do
    if i > 1 then x.combat = num(x.combat) + dur end
    if not x.kill then x.ok, x.dur = ok, dur end
    if ok == 1 then
      if not x.kill then                                         -- (stored once: a later kill of the same boss changes nothing)
        x.kill = Runs.clock(run, at)
        x.fight = Runs.fightUid(num(e.t))
      end
    elseif ok == nil then x.unknown = num(x.unknown) + 1
    -- not a kill: a wipe only when the character died in the pull; else the encounter reset (the Avatar of Hakkar
    -- ends unkilled 1.2 s after its START in every clear, and nobody dies)
    elseif num(e.d) > 0 then x.wipes = num(x.wipes) + 1
    else x.resets = num(x.resets) + 1 end
  end
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
    pulled(run, Runs.clock(run))
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
  run.size = max(num(run.size), Runs.groupSize())
  Runs.copyCheck(c, run)
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
  "PLAYER_REGEN_ENABLED", "PLAYER_LOGOUT", "GROUP_ROSTER_UPDATE" }) do pcall(ef.RegisterEvent, ef, e) end
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
  -- the largest group the run was played in (a solo run and a group run never share a best)
  GROUP_ROSTER_UPDATE = function()
    local run = cur(me())
    if run and run.st == "in" then run.size = max(num(run.size), Runs.groupSize()) end
  end,
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

-- ── bests, statistics, undo, instances this hour (0.9.51) ─────────────────────────────────────────────────────
-- characters[guid].dungeonStats[key] (key: the dungeon's name, lowercase; never evicted): the sums of the runs
-- counted, the bosses seen and how often killed, and per route its best, the splits of the best run and the best
-- segments. A partial run is never counted. An edited run (split or joined by hand), a raid, a run with a boss whose
-- outcome was never seen and a run without a kill set no best. characters[guid].dungeonCopies[]: one row per
-- instance entered, for "Instances this hour".
Runs.STATS_CAP = 80        -- dungeons with statistics of their own; the least recently run is folded into `other`
Runs.ROUTE_CAP = 8         -- routes per dungeon; the least run goes first
Runs.KEEP_CAP = 20         -- runs protected from eviction
Runs.COPY_CAP = 40
Runs.SEG_EXTRA = 2         -- best segments per route: its boss count plus this many
Runs.STATS_BOSS_CAP = 20   -- bosses with counts per dungeon (the boss rows of one run: Runs.BOSS_CAP)
Runs.COPY_WINDOW = 86400   -- copy rows older than this are dropped
Runs.HOUR = 3600
Runs.OTHER = "other"
Runs.ADD = { "n", "full", "secs", "active", "deaths", "wipes", "xp", "looted", "quests", "lootValue" }
Runs.WHY.split = "split by hand"
Runs.HOUR_TIP = "Counted by the addon from your own entries. The server does not tell addons the real number."

local function copyT(v)
  if type(v) ~= "table" then return v end
  local o = {}
  for k, x in pairs(v) do o[k] = copyT(x) end
  return o
end
Runs.copy = copyT
-- the largest group the character is in now (1 alone)
function Runs.groupSize()
  local n = plainNum(rd(GetNumGroupMembers))
  if not n or n < 1 then return 1 end
  return floor(n)
end
function Runs.keyOf(rec) return (type(rec.inst) == "string" and rec.inst or ""):lower() end
-- the route of a run: the encounter ids it killed, sorted, joined with "." (worked out from the bosses, never stored)
function Runs.routeOf(rec)
  local ids = {}
  for _, b in ipairs(rec.bosses or {}) do if plainNum(b.kill) and plainNum(b.enc) then ids[#ids + 1] = b.enc end end
  table.sort(ids)
  if #ids == 0 then return nil, 0 end
  return table.concat(ids, "."), #ids
end
-- The key of a best: the route, the difficulty when the client named it, and "solo" for a run the character played
-- alone, so a solo farm and a five-player clear never share a best. A run of 0.9.50 has no `size`: a group run.
function Runs.sigOf(rec)
  local route = Runs.routeOf(rec)
  if not route then return nil end
  local s = route
  -- (a difficulty of 0 is the client's answer outside an instance: a run opened by the zone name, the map type or a
  -- boss pull before the client said instance; it is no difficulty and never splits a best off its route)
  if plainNum(rec.diff) and rec.diff > 0 then s = s .. "/d" .. rec.diff end
  if rec.size == 1 then s = s .. "/solo" end
  return s
end
local function sigClass(sig) return (type(sig) == "string" and sig:match("(/.*)$")) or "" end
-- first pull to the last boss kill, on the run's clock (the measure of a best, plan decision 5)
function Runs.measure(rec)
  local fp, last = plainNum(rec.firstPull), nil
  for _, b in ipairs(rec.bosses or {}) do if plainNum(b.kill) and (not last or b.kill > last) then last = b.kill end end
  if not (fp and last) then return nil end
  return max(0, last - fp)
end
-- a boss whose outcome was never seen and that was not killed later in the run
local function unknownBoss(rec)
  for _, b in ipairs(rec.bosses or {}) do if num(b.unknown) > 0 and not b.kill then return true end end
  return false
end
Runs.unknownBoss = unknownBoss
-- Whether a closed run may set a best: whole (not partial), as played (not edited), every outcome seen, a dungeon
-- (a raid over two nights is two runs, so raids get no bests and no full clear in this version), and a kill.
function Runs.bestable(rec)
  return not rec.partial and not rec.edited and rec.kind ~= "raid" and not unknownBoss(rec) and Runs.measure(rec) ~= nil
end
local function statsOf(c, create)
  local S = c and c.dungeonStats
  if type(S) ~= "table" then
    if not create or not c then return nil end
    S = {}; c.dungeonStats = S
  end
  return S
end
Runs.statsOf = statsOf
local function sums(inst, kind)
  return { inst = inst, kind = kind, n = 0, full = 0, secs = 0, active = 0, deaths = 0, wipes = 0, xp = 0, looted = 0, quests = 0, lootValue = 0, last = 0 }
end
-- A closed run says which entries of the statistics it is not counted in (`notIn`), so that taking it out (a delete,
-- a split, a join) subtracts only from what it was added to: `dungeon` (its dungeon was folded into `other` since),
-- `route` (its route was dropped at Runs.ROUTE_CAP since; a route of the same key made later holds other runs),
-- `bosses[enc]` (the boss had no row of its own at Runs.STATS_BOSS_CAP when the run was counted).
local function notIn(rec, make)
  local x = rec.notIn
  if type(x) ~= "table" then
    if not make then return nil end
    x = {}; rec.notIn = x
  end
  return x
end
Runs.notIn = notIn
-- the stored runs counted in an entry that goes: marked (`what`), so they are not taken out of a later one
local function markOut(c, key, sig, what)
  for _, rec in ipairs(type(c) == "table" and type(c.dungeonRuns) == "table" and c.dungeonRuns or {}) do
    if Runs.valid(rec) and not rec.partial and Runs.keyOf(rec) == key and (not sig or (rec.kind ~= "raid" and Runs.sigOf(rec) == sig)) then
      notIn(rec, true)[what] = true
    end
  end
end
-- whether a run is counted in its dungeon's own entry (else in `other`), and in its route's
local function inDungeon(rec) local x = notIn(rec); return not (x and x.dungeon) end
local function inRoute(rec) local x = notIn(rec); return not (x and (x.dungeon or x.route)) end
Runs.inRoute = inRoute
-- at most Runs.STATS_CAP dungeons keep statistics of their own: the least recently run goes into `other` (its sums
-- only: no bosses, no routes)
local function fold(S, c)
  local n, oldK, oldT = 0, nil, nil
  for k, s in pairs(S) do
    if k ~= Runs.OTHER and type(s) == "table" then
      n = n + 1
      if not oldT or num(s.last) < oldT or (num(s.last) == oldT and k < oldK) then oldK, oldT = k, num(s.last) end
    end
  end
  if n < Runs.STATS_CAP or not oldK then return end
  local s, o = S[oldK], S[Runs.OTHER]
  if type(o) ~= "table" then o = sums("Other dungeons", "party"); S[Runs.OTHER] = o end
  for _, k in ipairs(Runs.ADD) do o[k] = num(o[k]) + num(s[k]) end
  o.last = max(num(o.last), num(s.last))
  o.folded = num(o.folded) + 1
  S[oldK] = nil
  markOut(c, oldK, nil, "dungeon")
  Runs.note("folded")
end
-- `rec` as a candidate for the best of `route`: the best itself (first pull to last kill), the splits of the best run
-- (each boss's group, seconds from the first pull, for VS BEST) and the best segment between two groups of kills
-- ("<group before>><group>" -> { s, id }, "start" before the first). Returns whether it set the best.
local function offer(route, rec)
  local m = Runs.measure(rec)
  if not m then return false end
  local sp = Runs.splits(rec)
  local pb = false
  if not plainNum(route.best) or m < route.best then
    route.best, route.bestId, route.bestAt = m, rec.id, rec.t
    local splits = {}
    for enc, x in pairs(sp) do splits[enc] = x.at end
    route.splits = splits
    pb = true
  end
  local seg = type(route.seg) == "table" and route.seg or {}
  route.seg = seg
  local fresh = {}
  for _, x in pairs(sp) do
    local k = x.prevKey .. ">" .. x.key
    local cur0 = seg[k]
    if type(cur0) ~= "table" or x.seg < num(cur0.s) then seg[k] = { s = x.seg, id = rec.id }; fresh[k] = true end
  end
  -- at most the route's boss count plus Runs.SEG_EXTRA segments (every new order of kills adds some): the entry of
  -- the oldest run goes first, one whose run left the list (no id) before any
  local cap = select(2, Runs.routeOf(rec)) + Runs.SEG_EXTRA
  local n = 0
  for _ in pairs(seg) do n = n + 1 end
  while n > cap do
    local dropK, dropT
    for k, x in pairs(seg) do
      if not fresh[k] then
        local t = Runs.idTime(type(x) == "table" and x.id)
        if not dropT or t < dropT or (t == dropT and k < dropK) then dropK, dropT = k, t end
      end
    end
    if not dropK then break end
    seg[dropK] = nil; n = n - 1
    Runs.note("segCap")
  end
  return pb
end
-- the start of the run an id names (`<guid>-<t>-<hex>`), 0 for none
function Runs.idTime(id)
  return (type(id) == "string" and tonumber(id:match("%-(%d+)%-%x+$"))) or 0
end
local function routeFor(s, sig, create, c, key)
  local R = s.routes
  if type(R) ~= "table" then R = {}; s.routes = R end
  if R[sig] or not create then return R[sig] end
  local n, dropK, dropN, dropT = 0, nil, nil, nil
  for k, r in pairs(R) do
    n = n + 1
    if not dropN or num(r.n) < dropN or (num(r.n) == dropN and (num(r.last) < dropT or (num(r.last) == dropT and k < dropK))) then dropK, dropN, dropT = k, num(r.n), num(r.last) end
  end
  if n >= Runs.ROUTE_CAP and dropK then R[dropK] = nil; markOut(c, key, dropK, "route"); Runs.note("routeCap") end
  local r = { n = 0 }
  R[sig] = r
  return r
end
function Runs.refers(r, id)
  if r.bestId == id then return true end
  for _, x in pairs(type(r.seg) == "table" and r.seg or {}) do if type(x) == "table" and x.id == id then return true end end
  return false
end
-- A run that held the best or a best segment of a route left the list (deleted, split or joined): what it held is
-- taken again from the runs still stored. What the other runs hold stays, also when their run was evicted since.
function Runs.routeRecompute(c, key, sig, r, id)
  if r.bestId == id then r.best, r.bestId, r.bestAt, r.splits = nil, nil, nil, nil end
  for k, x in pairs(type(r.seg) == "table" and r.seg or {}) do if type(x) == "table" and x.id == id then r.seg[k] = nil end end
  for _, rec in ipairs(type(c.dungeonRuns) == "table" and c.dungeonRuns or {}) do
    if Runs.valid(rec) and rec.id ~= id and Runs.keyOf(rec) == key and rec.kind ~= "raid" and inRoute(rec) and Runs.sigOf(rec) == sig and Runs.bestable(rec) then offer(r, rec) end
  end
end
-- One closed run's numbers into (sign 1) or out of (sign -1) the statistics of its dungeon. A partial run is never
-- counted. Returns the dungeon's statistics.
function Runs.statsApply(c, rec, sign)
  Runs._gen = num(Runs._gen) + 1                                 -- (what Runs.view keeps of a run is read again)
  if rec.partial then return nil end
  local S = statsOf(c, sign > 0)
  if not S then return nil end
  local key = Runs.keyOf(rec)
  if sign > 0 then rec.notIn = nil end                           -- (counted now: what it is in is worked out again)
  local out = notIn(rec) or {}
  local s = S[key]
  if sign < 0 and out.dungeon then s = nil end                   -- (counted in `other`: a later entry of its name is not its)
  if type(s) ~= "table" then
    if sign < 0 then s = S[Runs.OTHER]; if type(s) ~= "table" then return nil end   -- (its dungeon was folded)
    else
      fold(S, c)
      s = sums(rec.inst, rec.kind); s.bosses, s.routes = {}, {}
      S[key] = s
    end
  end
  local g = type(rec.gold) == "table" and rec.gold or {}
  local wipes = 0
  for _, b in ipairs(rec.bosses or {}) do wipes = wipes + num(b.wipes) end
  local add = { n = 1, full = rec.done and 1 or 0, secs = num(rec.secs.inside) + num(rec.secs.ghost), active = num(rec.secs.active),
    deaths = num(type(rec.nDeaths) == "table" and rec.nDeaths.me), wipes = wipes, xp = num(type(rec.xp) == "table" and rec.xp.gain),
    looted = num(g.looted), quests = num(g.quests), lootValue = num(g.lootValue) }
  for _, k in ipairs(Runs.ADD) do s[k] = max(0, num(s[k]) + sign * add[k]) end
  if sign > 0 then s.last = max(num(s.last), num(rec.t))
  elseif S[key] == s and num(rec.t) >= num(s.last) then s.last = Runs.lastOf(c, key, nil, rec.id) or s.last end
  if type(s.bosses) == "table" then
    for _, b in ipairs(rec.bosses or {}) do
      if plainNum(b.enc) then
        local x = s.bosses[b.enc]
        if sign < 0 and type(out.bosses) == "table" and out.bosses[b.enc] then x = nil end   -- (never counted in it)
        if not x and sign > 0 then
          local nb = 0
          for _ in pairs(s.bosses) do nb = nb + 1 end
          if nb < Runs.STATS_BOSS_CAP then x = { kills = 0, wipes = 0, seenIn = 0 }; s.bosses[b.enc] = x
          else
            local o = notIn(rec, true)
            o.bosses = type(o.bosses) == "table" and o.bosses or {}
            o.bosses[b.enc] = true
            Runs.note("statsBossCap")
          end
        end
        if x then
          if b.name then x.name = b.name end
          x.kills = max(0, num(x.kills) + sign * (b.kill and 1 or 0))
          x.wipes = max(0, num(x.wipes) + sign * num(b.wipes))
          x.seenIn = max(0, num(x.seenIn) + sign)
          if x.seenIn == 0 then s.bosses[b.enc] = nil end
        end
      end
    end
    local sig = rec.kind ~= "raid" and Runs.sigOf(rec) or nil
    if sign < 0 and out.route then sig = nil end                 -- (its route was dropped since: never this one)
    local r = sig and routeFor(s, sig, sign > 0, c, key) or nil
    if r then
      r.n = max(0, num(r.n) + sign)
      -- the measure of every run that could set a best, summed: the Average of BY DUNGEON is the Best's measure
      local m = Runs.bestable(rec) and Runs.measure(rec) or nil
      if m then
        r.tot, r.k = max(0, num(r.tot) + sign * m), max(0, num(r.k) + sign)
        if r.k == 0 then r.tot, r.k = nil, nil end
      end
      if sign > 0 then
        r.last = max(num(r.last), num(rec.t))
        if m then offer(r, rec) end
      elseif r.n == 0 then s.routes[sig] = nil
      else
        if num(rec.t) >= num(r.last) then r.last = Runs.lastOf(c, key, sig, rec.id) or r.last end
        if Runs.refers(r, rec.id) then Runs.routeRecompute(c, key, sig, r, rec.id) end
      end
    end
  end
  if s.n == 0 and S[key] == s then S[key] = nil end
  return s
end
-- The newest start among the stored runs of a dungeon (and of one route, with `sig`) that count, leaving out `skip`:
-- what `last` falls back to when the newest run is taken out. nil when none is stored.
function Runs.lastOf(c, key, sig, skip)
  local t
  for _, rec in ipairs(type(c.dungeonRuns) == "table" and c.dungeonRuns or {}) do
    if Runs.valid(rec) and rec.id ~= skip and not rec.partial and Runs.keyOf(rec) == key and inDungeon(rec)
      and (not sig or (rec.kind ~= "raid" and inRoute(rec) and Runs.sigOf(rec) == sig)) and (not t or rec.t > t) then t = rec.t end
  end
  return t
end
-- The boss sets of a dungeon, from its routes: routes that share a boss are one set (one wing, or the whole dungeon),
-- routes that share none are sets of their own (the wings of Scarlet Monastery, Dire Maul, Stratholme or Maraudon
-- under one name). Each: `n` the runs with a kill in it, `kills[enc]` those that killed that boss. Most runs first.
local function sigIds(sig)
  local ids = {}
  for x in ((type(sig) == "string" and sig:match("^([^/]*)")) or ""):gmatch("[^%.]+") do local e = tonumber(x); if e then ids[#ids + 1] = e end end
  return ids
end
function Runs.clusters(s)
  local parent = {}
  local function find(x) while parent[x] ~= x do x = parent[x] end return x end
  local entries = {}
  for sig, r in pairs(type(s) == "table" and type(s.routes) == "table" and s.routes or {}) do
    local ids = sigIds(sig)
    if #ids > 0 and num(r.n) > 0 then
      entries[#entries + 1] = { ids = ids, n = num(r.n) }
      for _, e in ipairs(ids) do if parent[e] == nil then parent[e] = e end end
      for i = 2, #ids do local a, b = find(ids[1]), find(ids[i]); if a ~= b then parent[max(a, b)] = min(a, b) end end
    end
  end
  local byRoot, out = {}, {}
  for _, en in ipairs(entries) do
    local root = find(en.ids[1])
    local cl = byRoot[root]
    if not cl then cl = { n = 0, kills = {}, root = root }; byRoot[root] = cl; out[#out + 1] = cl end
    cl.n = cl.n + en.n
    for _, e in ipairs(en.ids) do cl.kills[e] = num(cl.kills[e]) + en.n end
  end
  table.sort(out, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.root < b.root end)
  return out
end
-- The boss set a run belongs to: the one it shares most kills with, else most bosses pulled, else the only one; with
-- no run, the set run most often. Sets are compared by their root (the lowest encounter id), so two reads agree.
function Runs.clusterOf(s, rec)
  local CL = Runs.clusters(s)
  if #CL == 0 then return nil end
  if not rec then return CL[1] end
  local function most(killsOnly)
    local bo, bc = 0, nil
    for _, cl in ipairs(CL) do
      local o = 0
      for _, b in ipairs(rec.bosses or {}) do if plainNum(b.enc) and (b.kill or not killsOnly) and cl.kills[b.enc] then o = o + 1 end end
      if o > bo then bo, bc = o, cl end
    end
    return bc
  end
  return most(true) or most(false) or (#CL == 1 and CL[1]) or nil
end
-- The learned boss list of a run's dungeon: the bosses killed in at least half of the runs of its boss set (above),
-- once that set has two. Counted from the runs with a kill (a quest visit or a trash run moves nothing), per set, so
-- a wing clear is a full clear of its wing. The route's last boss is not needed for it (Maraudon's last kill comes
-- after its "last boss"). nil before; raids none. Without `rec`: the set run most often.
function Runs.learned(s, rec)
  if type(s) ~= "table" or s.kind == "raid" or type(s.routes) ~= "table" then return nil end
  local cl = Runs.clusterOf(s, rec)
  if not cl or cl.n < 2 then return nil end
  local out = {}
  for enc, k in pairs(cl.kills) do if k * 2 >= cl.n then out[#out + 1] = enc end end
  table.sort(out)
  return #out > 0 and out or nil
end
function Runs.isFull(s, rec)
  if rec.kind == "raid" or unknownBoss(rec) then return false end
  local L = Runs.learned(s, rec)
  if not L then return false end
  local killed = {}
  for _, b in ipairs(rec.bosses or {}) do if b.kill then killed[b.enc] = true end end
  for _, enc in ipairs(L) do if not killed[enc] then return false end end
  -- (a boss the run met and left up is not cleared: the run is no full clear, B1)
  for _, b in ipairs(rec.bosses or {}) do if not b.kill and b.enc ~= nil then return false end end
  return true
end
-- Whether a run holds the best of its route now (worked out from `bestId`, never stored: 0.9.51's review)
function Runs.isPb(rec)
  local S = statsOf(me())
  local s = S and S[Runs.keyOf(rec)]
  local sig = rec.kind ~= "raid" and Runs.sigOf(rec) or nil
  local r = sig and type(s) == "table" and type(s.routes) == "table" and s.routes[sig] or nil
  return (r and r.bestId ~= nil and r.bestId == rec.id) and true or false
end
-- a closed run joins the statistics: its numbers, its route's best when it sets one, and whether it was a full
-- clear (`done`: every boss of the learned list killed), counted too
-- With `keep` the run's own marks stay as they were set at its close (a full clear is a fact of the run, fixed
-- when it ended against the list known then), and only the sums are counted again. The one exception: the run that
-- gives a boss set its learned list (its second run) judges the runs counted before it too, which closed with none.
function Runs.statsAdd(c, rec, keep)
  local done = rec.done
  rec.done = nil
  local s = Runs.statsApply(c, rec, 1)
  if keep then
    rec.done = done
    if s and done then s.full = num(s.full) + 1 end
  elseif s and type(s.bosses) == "table" then
    if Runs.isFull(s, rec) then rec.done = true; s.full = num(s.full) + 1 end
    local cl = rec.kind ~= "raid" and Runs.clusterOf(s, rec) or nil
    if cl and cl.n == 2 then
      local key = Runs.keyOf(rec)
      for _, o in ipairs(type(c.dungeonRuns) == "table" and c.dungeonRuns or {}) do
        if o == rec or o.id == rec.id then break end                -- (only runs counted before this one)
        local oc = Runs.valid(o) and not o.partial and not o.done and Runs.keyOf(o) == key and Runs.clusterOf(s, o) or nil
        if oc and oc.root == cl.root and Runs.isFull(s, o) then o.done = true; s.full = num(s.full) + 1 end
      end
    end
  end
  return s
end
-- the statistics again from the runs stored, oldest first: at the first load of 0.9.51 (a save without them, the
-- marks worked out) and, with `keep`, from the runs as they are (what a delete has to equal)
function Runs.statsRebuild(c, keep)
  Runs._gen = num(Runs._gen) + 1
  c.dungeonStats = nil
  for _, rec in ipairs(type(c.dungeonRuns) == "table" and c.dungeonRuns or {}) do if Runs.valid(rec) then Runs.statsAdd(c, rec, keep) end end
end

-- ── instances this hour ────────────────────────────────────────────────────────────────────────────────────────
-- A copy row is written for the first entry of a run: not for a re-entry (a visit), a run the zone name alone
-- opened until something confirms it (the door of Sunken Temple never writes one), a run opened by End run now
-- (the same copy), a run partial from its start (opened at a login after the game closed without saving) or a raid.
-- A run that becomes partial later keeps the row its entry wrote, and a run too short to be kept keeps its row: the
-- entry made a copy either way. `why`: `first` when this character has no row of the dungeon in the last 24 hours,
-- else `estimate` (a new copy by the 20 minute rule); `split` for the second part of Split here (Runs.copyAdd).
function Runs.copiesOf(c, at)
  local L = type(c.dungeonCopies) == "table" and c.dungeonCopies or {}
  for i = #L, 1, -1 do
    local r = L[i]
    if type(r) ~= "table" or not plainNum(r.t) or r.t < at - Runs.COPY_WINDOW then table.remove(L, i) end
  end
  return L
end
function Runs.copyCheck(c, run)
  if run.copied or run.prov or run.partial or run.open == "split" or run.kind == "raid" then return end
  run.copied = true
  local L = Runs.copiesOf(c, nowT())
  local why = "first"                                            -- the first run of this dungeon in the window
  for _, r in ipairs(L) do if r.key == run.inst then why = "estimate" end end   -- a new copy by the 20 minute rule
  L[#L + 1] = { t = run.t, key = run.inst, run = run.id, why = why }
  while #L > Runs.COPY_CAP do table.remove(L, 1) end
  c.dungeonCopies = L
end
-- the account's instances in the last hour and the last 24 hours, from every character's rows, newest first
function Runs.copies(at)
  at = at or nowT()
  local rows = {}
  for guid, ch in pairs(ns.DB and type(ns.DB.characters) == "table" and ns.DB.characters or {}) do
    if type(ch) == "table" and type(ch.dungeonCopies) == "table" then
      for _, r in ipairs(ch.dungeonCopies) do
        if type(r) == "table" and plainNum(r.t) and r.t >= at - Runs.COPY_WINDOW and r.t <= at then
          rows[#rows + 1] = { t = r.t, key = r.key, why = r.why, who = ch.name, guid = guid }
        end
      end
    end
  end
  table.sort(rows, function(a, b) if a.t ~= b.t then return a.t > b.t end return tostring(a.key) < tostring(b.key) end)
  local hour = 0
  for _, r in ipairs(rows) do if r.t > at - Runs.HOUR then hour = hour + 1 end end
  return hour, #rows, rows
end
function Runs.limit()
  local v = ns.DB and type(ns.DB.settings) == "table" and plainNum(ns.DB.settings.instanceLimit)
  return (v and v > 0) and v or nil
end
-- "Instances this hour: 3 (estimate)  ·  last 24 hours: 11", with "3 of 5" when the player set a limit
function Runs.hourLine(at)
  local h, d = Runs.copies(at)
  local lim = Runs.limit()
  local first = lim and ("Instances this hour: %d of %d (estimate)"):format(h, lim) or ("Instances this hour: %d (estimate)"):format(h)
  return first .. "  ·  last 24 hours: " .. d
end
Runs.COPY_WHY = { first = "first entry", estimate = "new copy by the 20 minute rule", split = "new copy (split by hand)" }
-- Split here says the second part was a new copy: a row at its start (not for a raid or a partial run). Join with
-- previous run says the two were one copy: the joined-away run's row goes.
function Runs.copyAdd(c, rec, why)
  if rec.partial or rec.kind == "raid" or not plainNum(rec.t) then return end
  local L = Runs.copiesOf(c, nowT())
  if rec.t < nowT() - Runs.COPY_WINDOW then return end
  local at = #L + 1
  for i = #L, 1, -1 do if num(L[i].t) > rec.t then at = i end end
  table.insert(L, at, { t = rec.t, key = rec.inst, run = rec.id, why = why })
  while #L > Runs.COPY_CAP do table.remove(L, 1) end
  c.dungeonCopies = L
end
function Runs.copyDrop(c, id)
  local L = type(c.dungeonCopies) == "table" and c.dungeonCopies or nil
  if not L then return end
  for i = #L, 1, -1 do if type(L[i]) == "table" and L[i].run == id then table.remove(L, i) end end
end
-- the hover of the hour line: one row per copy (dungeon, character, time, reason)
function Runs.hourTip(at)
  local _, _, rows = Runs.copies(at)
  local out = {}
  for _, r in ipairs(rows) do
    out[#out + 1] = ("%s  ·  %s  ·  %s  ·  %s"):format(tostring(r.key or "?"), tostring(r.who or "?"), date("%H:%M", r.t), Runs.COPY_WHY[r.why] or tostring(r.why or ""))
  end
  return out
end

-- ── where a run stands against the best ────────────────────────────────────────────────────────────────────────
local function clockText(sec)
  local neg = sec < 0
  sec = floor(math.abs(sec) + 0.5)
  local s
  if sec >= 3600 then s = ("%d:%02d:%02d"):format(floor(sec / 3600), floor((sec % 3600) / 60), sec % 60)
  else s = ("%d:%02d"):format(floor(sec / 60), sec % 60) end
  return neg and ("-" .. s) or s
end
Runs.clockText = clockText
-- a delta with its sign: "+0:41", "-0:42", "±0:00"
function Runs.signed(d)
  d = num(d)
  d = d >= 0 and floor(d + 0.5) or -floor(-d + 0.5)
  if d == 0 then return "±0:00" end
  if d > 0 then return "+" .. clockText(d) end
  return clockText(d)
end
-- and with its arrow (the colour is never alone): "+3:29 ↑" slower than the best, "-0:42 ↓" faster
Runs.UP, Runs.DOWN = "↑", "↓"
function Runs.deltaText(d)
  local s = Runs.signed(d)
  if s:sub(1, 1) == "+" then return s .. " " .. Runs.UP end
  if s:sub(1, 1) == "-" then return s .. " " .. Runs.DOWN end
  return s
end
-- How a run stands against the best, or nil:
--   mode "same"    a closed run whose route has a best: `delta` (its measure less the best), `isBest`, `vs[enc]`
--                  (each boss against the best run's split), `sumBest` (the best segments in this run's own order of
--                  kills, only when every one of them is known)
--   mode "prefix"  otherwise (and always for the run in progress): against the best of the route that shares the
--                  longest start with this run (the same bosses in the first `at` kills, in any order inside a group):
--                  `delta` and `best` at boss `at`, `vs[enc]` for the shared bosses
-- `first` is true when the run is the character's only run of this dungeon (Runs.onlyRun).
-- Whether a run is the only one of its dungeon: no other stored run of it, and no counted run beyond itself in the
-- statistics (which also hold the runs evicted from the list). "first run" says exactly that.
function Runs.onlyRun(c, rec, isOpen, s)
  local key = Runs.keyOf(rec)
  if type(s) == "table" and num(s.n) > ((isOpen or rec.partial) and 0 or 1) then return false end
  for _, o in ipairs(c and type(c.dungeonRuns) == "table" and c.dungeonRuns or {}) do
    if type(o) == "table" and o.id ~= rec.id and Runs.keyOf(o) == key then return false end
  end
  return true
end
function Runs.compare(rec, isOpen)
  if rec.kind == "raid" then return nil end
  local c = me()
  local S = statsOf(c)
  local s = S and S[Runs.keyOf(rec)]
  local routes = type(s) == "table" and type(s.routes) == "table" and s.routes or {}
  local sp, groups = Runs.splits(rec), Runs.groups(rec)
  local sig = Runs.sigOf(rec)
  local out = { vs = {}, first = Runs.onlyRun(c, rec, isOpen, s) }
  local r = sig and routes[sig]
  local m = Runs.measure(rec)
  if not isOpen and r and plainNum(r.best) and m then
    out.mode, out.best, out.bestAt, out.bestId = "same", r.best, r.bestAt, r.bestId
    out.isBest, out.delta, out.runs = r.bestId == rec.id, m - r.best, num(r.n)
    for enc, x in pairs(sp) do
      local b = type(r.splits) == "table" and plainNum(r.splits[enc]) or nil
      if b then out.vs[enc] = x.at - b end
    end
    local seg = type(r.seg) == "table" and r.seg or nil
    if seg and #groups > 0 then
      local sum, prevKey, ok = 0, "start", true
      for _, g in ipairs(groups) do
        local x = seg[prevKey .. ">" .. g.key]
        if type(x) ~= "table" then ok = false; break end
        sum, prevKey = sum + num(x.s), g.key
      end
      if ok then out.sumBest = sum end
    end
    return out
  end
  local mine = {}
  for _, g in ipairs(groups) do for _, id in ipairs(g.ids) do mine[#mine + 1] = id end end
  if #mine == 0 or not plainNum(rec.firstPull) then return out end
  local cls = sigClass(sig)
  local pick
  for rs, rr in pairs(routes) do
    if plainNum(rr.best) and type(rr.splits) == "table" and sigClass(rs) == cls then
      local ref = {}
      for enc, t in pairs(rr.splits) do if plainNum(t) and tonumber(enc) then ref[#ref + 1] = { enc = tonumber(enc), t = t } end end
      table.sort(ref, function(a, b) if a.t ~= b.t then return a.t < b.t end return a.enc < b.enc end)
      local L, diff, nz = 0, {}, 0
      for i = 1, min(#mine, #ref) do
        for _, e in ipairs({ { mine[i], 1 }, { ref[i].enc, -1 } }) do
          local was = diff[e[1]] or 0
          local now = was + e[2]
          diff[e[1]] = now
          if was == 0 and now ~= 0 then nz = nz + 1 elseif was ~= 0 and now == 0 then nz = nz - 1 end
        end
        if nz == 0 then L = i end
      end
      if L > 0 and (not pick or L > pick.L or (L == pick.L and (#ref > #pick.ref or (#ref == #pick.ref and rr.best < pick.r.best)))) then
        pick = { r = rr, ref = ref, L = L }
      end
    end
  end
  if not pick then return out end
  out.mode, out.at, out.bestAt, out.bestId, out.of = "prefix", pick.L, pick.r.bestAt, pick.r.bestId, #pick.ref
  for i = 1, pick.L do
    local enc = mine[i]
    if sp[enc] and plainNum(pick.r.splits[enc]) then out.vs[enc] = sp[enc].at - pick.r.splits[enc] end
  end
  out.best = pick.ref[pick.L].t
  out.delta = sp[mine[pick.L]].at - out.best
  return out
end
-- The bosses of a run against its dungeon's learned list: down, and the size of the list with the run's own kills
-- (nil while the dungeon has no list yet: the page says "Bosses 5" then), and the known bosses not killed.
function Runs.bossTotal(rec)
  if rec.kind == "raid" then return nil end
  local S = statsOf(me())
  local L = Runs.learned(S and S[Runs.keyOf(rec)], rec)
  if not L then return nil end
  local set, n, missing = {}, 0, {}
  for _, enc in ipairs(L) do set[enc] = true; n = n + 1 end
  local pulled = {}
  -- (every encounter the run met counts, killed or left up: 6 of 8 with two missed, never 6 of 6, B1)
  for _, b in ipairs(rec.bosses or {}) do
    pulled[b.enc] = true
    if b.enc ~= nil and not set[b.enc] then set[b.enc] = true; n = n + 1 end
  end
  local s = S[Runs.keyOf(rec)]
  for _, enc in ipairs(L) do
    if not pulled[enc] then missing[#missing + 1] = { enc = enc, name = s.bosses[enc] and s.bosses[enc].name } end
  end
  return n, missing
end
-- The best of a dungeon for its row in BY DUNGEON: the full route's when one has a best (its bosses are the learned
-- list of the boss set run most often), else the best of the route with the most bosses. Returns the seconds and
-- the route.
function Runs.dungeonBest(s)
  local L = Runs.learned(s)
  local full = L and table.concat(L, ".") or nil
  local best, bestN, isFull, bestR
  for sig, r in pairs(type(s.routes) == "table" and s.routes or {}) do
    if plainNum(r.best) then
      local route = sig:match("^([^/]*)") or sig
      local n = select(2, route:gsub("%.", "")) + 1
      local f = route == full
      if (f and not isFull) or (f == (isFull or false) and (not bestN or n > bestN or (n == bestN and r.best < best))) then
        best, bestN, isFull, bestR = r.best, n, f, r
      end
    end
  end
  return best, bestR
end
-- the rows of BY DUNGEON: one per dungeon with statistics, the most recently run first, `other` last
function Runs.dungeonRows()
  local c = me()
  local S = statsOf(c) or {}
  local out = {}
  for key, s in pairs(S) do
    if type(s) == "table" and num(s.n) > 0 then
      local row = { key = key, name = s.inst or key, kind = s.kind, n = s.n, full = num(s.full), last = num(s.last), other = key == Runs.OTHER }
      -- Average is the Best's own measure (first pull to last kill) over the runs of the Best's route that could set
      -- one, so the two columns compare; nil while there is no best
      if not row.other then
        local best, r = Runs.dungeonBest(s)
        row.best = best
        if r and num(r.k) > 0 then row.avg = num(r.tot) / r.k end
      end
      local warm = num(s.active) >= Runs.RATE_WARM
      row.coinPerHour = warm and (num(s.looted) + num(s.quests)) * 3600 / s.active or nil
      row.xpPerHour = (warm and num(s.xp) > 0) and s.xp * 3600 / s.active or nil
      row.deathsPerRun = num(s.deaths) / s.n
      -- (what a run of the dungeon was worth: looted coin and the vendor value of its items, never quest coin)
      row.worthPerRun = (num(s.looted) + num(s.lootValue)) / s.n
      out[#out + 1] = row
    end
  end
  table.sort(out, function(a, b)
    if a.other ~= b.other then return b.other end
    if a.last ~= b.last then return a.last > b.last end
    return a.key < b.key
  end)
  return out
end

-- ── undo: keep, split, join, delete ────────────────────────────────────────────────────────────────────────────
-- the record of an id: the open run, or a closed one with its place in the list
function Runs.find(c, id)
  local run = cur(c)
  if run and run.id == id then return run, nil, true end
  local list = type(c.dungeonRuns) == "table" and c.dungeonRuns or {}
  for i = #list, 1, -1 do if type(list[i]) == "table" and list[i].id == id then return list[i], i, false end end
  return nil
end
function Runs.keptCount(c)
  local n = 0
  for _, r in ipairs(type(c.dungeonRuns) == "table" and c.dungeonRuns or {}) do if type(r) == "table" and r.keep then n = n + 1 end end
  local run = cur(c)
  if run and run.keep then n = n + 1 end
  return n
end
-- Keep: the run is never evicted. At most Runs.KEEP_CAP. Returns true, or false and why ("cap", "gone").
function Runs.setKeep(id, on)
  local c = me()
  if not c then return false, "char" end
  local rec = Runs.find(c, id)
  if not rec then return false, "gone" end
  if on and not rec.keep and Runs.keptCount(c) >= Runs.KEEP_CAP then return false, "cap" end
  rec.keep = on and true or nil
  return true
end
-- Delete: the run goes and its numbers leave the statistics (a best it held is taken from the runs still stored).
-- The open run is ended unstored; while the character stays inside, the next run begins in the same second.
function Runs.delete(id)
  local c = me()
  if not (c and Runs._read) then return false, "char" end
  local rec, i, isOpen = Runs.find(c, id)
  if not rec then return false, "gone" end
  if isOpen then Runs.endNow(true); return true end
  table.remove(c.dungeonRuns, i)
  Runs.statsApply(c, rec, -1)
  Runs.note("deleted")
  return true
end
local function sumV(L, key)
  local s = 0
  for _, x in ipairs(L) do s = s + num(x[key]) end
  return s
end
local GAP_KEYS = { "gg", "go", "gf" }
local SECS_GAP = { "ghost", "outside", "offline" }
local function setGap(x, g)
  for q = 1, 3 do x[GAP_KEYS[q]] = (g and g[q] > 0) and g[q] or nil end
end
local function nDeathsOf(rows)
  local me0, party = 0, 0
  for _, d in ipairs(rows) do if d.who then party = party + 1 else me0 = me0 + 1 end end
  return me0, party
end
local function openBlocks(r)
  r.nDeaths = type(r.nDeaths) == "table" and r.nDeaths or {}
  r.nDeaths.me, r.nDeaths.party = num(r.nDeaths.me), num(r.nDeaths.party)
  r.deaths = type(r.deaths) == "table" and r.deaths or {}
  r.hidden = type(r.hidden) == "table" and r.hidden or {}
  for _, k in ipairs({ "xp", "rep", "loot" }) do r.hidden[k] = num(r.hidden[k]) end
  for _, k in ipairs(Runs.SECS) do r.secs[k] = num(r.secs[k]) end
  for _, b in ipairs(r.bosses) do
    for _, x in ipairs(Runs.levels(b)) do
      x.pulls = x.pulls or 1
      for _, k in ipairs(Runs.LEAN_BOSS) do x[k] = num(x[k]) end
      x.combat = num(x.combat)
    end
  end
  for _, v in ipairs(r.visits) do for _, k in ipairs(Runs.LEAN_VISIT) do v[k] = num(v[k]) end end
end
-- The seconds on the run's clock at the start of each visit and the gap before each by kind ({ ghost, outside,
-- offline }), or nil when the record cannot say: a record of 0.9.50 keeps no gap kinds, so it can say only when it
-- has one gap, or when all its gaps were of one kind.
function Runs.visitClocks(rec)
  local V = rec.visits
  if type(V) ~= "table" or #V == 0 then return nil end
  local n, gaps = #V, {}
  if num(rec.v) >= 2 then
    for k = 2, n do gaps[k] = { num(V[k].gg), num(V[k].go), num(V[k].gf) } end
  else
    local s = rec.secs or {}
    local tot = { num(s.ghost), num(s.outside), num(s.offline) }
    local kinds, which = 0, 2
    for q = 1, 3 do if tot[q] > 0 then kinds = kinds + 1; which = q end end
    if n == 2 then gaps[2] = tot
    elseif kinds > 1 then return nil
    else
      for k = 2, n do
        local g = { 0, 0, 0 }
        g[which] = max(0, num(V[k].i) - num(V[k - 1].o))
        gaps[k] = g
      end
    end
  end
  local starts = { 0 }
  for k = 2, n do starts[k] = starts[k - 1] + num(V[k - 1].secs) + gaps[k][1] end
  return starts, gaps
end
-- The wall time (epoch) of a moment on the run's clock, through the visits: the clock stands still while the
-- character is outside alive or offline. nil when the record cannot say (Runs.visitClocks).
function Runs.wallOf(rec, clock)
  clock = plainNum(clock)
  if type(rec) ~= "table" or not clock or not plainNum(rec.t) then return nil end
  local starts = Runs.visitClocks(rec)
  if not starts then return nil end
  local j = Runs.visitAt(starts, clock)
  return rec.t + num(rec.visits[j].i) + (clock - starts[j])
end
-- Split a run at visit k (2 or later) into two: A, the visits before, keeps the id; B, from visit k on, is a run of
-- its own (`open = "split"`). Every sum lives per visit, so the two add up to the run. What no visit row holds goes to
-- one side: a boss row whole to the side of its kill (else of its first pull), the gaps inside the row that absorbed
-- past the visit cap to B, the combat and boss seconds and hidden lines a record of 0.9.50 kept on the run only to A.
-- The gap between them is no one's time; B's first visit keeps it (gg, go, gf), so a join puts it back. Both are
-- `edited` and set no best. `isOpen`: B goes on as the open run. Returns A, B, or nil and why.
function Runs.splitRec(rec, k, isOpen)
  local V = rec.visits
  if not (plainNum(k) and k >= 2 and k <= #V and plainNum(V[k - 1].o)) then return nil, "visit" end
  local starts, gaps = Runs.visitClocks(rec)
  if not starts then return nil, "old" end
  local cB, wB = starts[k], num(V[k].i)
  local base = { v = Runs.V, inst = rec.inst, kind = rec.kind, map = rec.map, diff = rec.diff, uiMap = rec.uiMap, size = rec.size, partial = rec.partial, edited = true }
  local A, B = copyT(base), copyT(base)
  A.id, A.t, A.endT, A.open, A.why, A.keep = rec.id, rec.t, rec.t + num(V[k - 1].o), rec.open, "split", rec.keep
  B.id, B.t, B.endT, B.open, B.why, B.exact = newId(rec.t + wB), rec.t + wB, rec.endT, "split", rec.why, rec.exact
  A.visits, B.visits = {}, {}
  for j = 1, #V do
    local x = copyT(V[j])
    if j >= 2 then setGap(x, gaps[j]) end
    if j < k then A.visits[#A.visits + 1] = x
    else
      x.i = num(x.i) - wB
      if plainNum(x.o) then x.o = x.o - wB end
      if type(x.gaps) == "table" then for q = 1, #x.gaps do x.gaps[q] = x.gaps[q] - wB end end
      if plainNum(x.fc) then x.fc = x.fc - cB end
      B.visits[#B.visits + 1] = x
    end
  end
  local function secsOf(H, from, to)
    local s = { inside = sumV(H.visits, "secs"), active = sumV(H.visits, "active"), combat = sumV(H.visits, "combat"), boss = sumV(H.visits, "boss"), ghost = 0, outside = 0, offline = 0 }
    for j = from + 1, to do for q = 1, 3 do s[SECS_GAP[q]] = s[SECS_GAP[q]] + gaps[j][q] end end
    return s
  end
  A.secs, B.secs = secsOf(A, 1, k - 1), secsOf(B, k, #V)
  for q = 1, 3 do
    local key = SECS_GAP[q]
    local rest = num(rec.secs[key]) - (A.secs[key] + B.secs[key] + gaps[k][q])
    if rest > 0 then B.secs[key] = B.secs[key] + rest end
  end
  for _, key in ipairs({ "combat", "boss" }) do
    local rest = num(rec.secs[key]) - (A.secs[key] + B.secs[key])
    if rest > 0 then A.secs[key] = A.secs[key] + rest end
  end
  A.bosses, B.bosses = {}, {}
  local function rebase(x, d)
    if x.kill then x.kill = x.kill + d end
    if plainNum(x.p) then x.p = x.p + d end                      -- (below 0: first pulled before the cut)
  end
  -- each copy of a boss row (Runs.parts: a boss killed before the cut and pulled again after it) goes whole to the
  -- side of its kill, else of its first pull; the copies of one side are that side's row again
  for _, b in ipairs(rec.bosses) do
    local pa, pb = {}, {}
    for _, s in ipairs(Runs.parts(b)) do
      if #pb > 0 or (s.kill or s.p) >= cB then
        rebase(s, -cB)
        if s.v then s.v = s.v - k + 1 end
        pb[#pb + 1] = s
      else pa[#pa + 1] = s end
    end
    if #pa > 0 then A.bosses[#A.bosses + 1] = Runs.stack(pa, b) end
    if #pb > 0 then B.bosses[#B.bosses + 1] = Runs.stack(pb, b) end
  end
  A.deaths, B.deaths = {}, {}
  for _, d in ipairs(type(rec.deaths) == "table" and rec.deaths or {}) do
    local x = copyT(d)
    if num(d.o) >= cB then x.o = num(x.o) - cB; B.deaths[#B.deaths + 1] = x else A.deaths[#A.deaths + 1] = x end
  end
  local nD = type(rec.nDeaths) == "table" and rec.nDeaths or {}
  local am, ap = nDeathsOf(A.deaths)
  A.nDeaths = { me = am, party = ap }
  B.nDeaths = { me = max(0, num(nD.me) - am), party = max(0, num(nD.party) - ap) }
  local fp = plainNum(rec.firstPull)
  if fp and fp < cB then A.firstPull = fp end
  if fp and fp >= cB then B.firstPull = fp - cB
  else
    -- B's measure begins at the first combat of its first visit that had one (trash included), as every run's does;
    -- a record without the visits' first combat (0.9.50, or a row written before 0.9.51's review) at its first boss pull
    for _, x in ipairs(B.visits) do if plainNum(x.fc) then B.firstPull = max(0, x.fc); break end end
    if not B.firstPull then
      for _, b in ipairs(B.bosses) do local p0 = Runs.pullOf(b); if not B.firstPull or p0 < B.firstPull then B.firstPull = max(0, p0) end end
    end
  end
  -- "Possibly two runs" goes with the copies: each side's mark is the first visit a later copy of a boss began in
  -- on that side (gone on a side that holds one copy of each boss); a record whose parts do not say which visit
  -- moves its mark with its visit, gone when the cut is at it
  local rp = plainNum(rec.repull)
  if Runs.hasParts(rec) then A.repull, B.repull = Runs.repullOf(A), Runs.repullOf(B)
  elseif rp and rp < k then A.repull = rp elseif rp and rp > k then B.repull = rp - k + 1 end
  if type(rec.xp) == "table" then
    local function xpOf(H)
      return { gain = sumV(H.visits, "xp"), kill = sumV(H.visits, "xpKill"), quest = sumV(H.visits, "xpQuest"), n = sumV(H.visits, "kills") }
    end
    local xa, xb = xpOf(A), xpOf(B)
    for _, q in ipairs({ { "gain", "gain" }, { "kill", "kill" }, { "quest", "quest" }, { "n", "n" } }) do
      local rest = num(rec.xp[q[1]]) - (xa[q[2]] + xb[q[2]])
      if rest > 0 then xa[q[2]] = xa[q[2]] + rest end
    end
    xa.l0, xa.p0 = rec.xp.l0, rec.xp.p0
    xb.l1, xb.p1, xb.need = rec.xp.l1, rec.xp.p1, rec.xp.need
    -- (a side with no XP keeps no block: the other side takes its end of the bar, so a join gets both back)
    if xa.gain <= 0 then xb.l0, xb.p0 = xa.l0, xa.p0 end
    if xb.gain <= 0 and not isOpen then xa.l1, xa.p1, xa.need = xb.l1, xb.p1, xb.need end
    A.xp, B.xp = xa, xb
  end
  A.hidden = copyT(type(rec.hidden) == "table" and rec.hidden or {})
  B.hidden = { xp = 0, rep = 0, loot = 0 }
  if isOpen then
    for _, key in ipairs(Runs.OPEN_KEYS) do B[key] = copyT(rec[key]) end
    for id, e in pairs(type(B.encs) == "table" and B.encs or {}) do
      if type(e) == "table" then
        e.o = num(e.o) - cB
        -- (a pull still open belongs to the newest copy of its row, which is B's when B has the row)
        local n
        for _, x in ipairs(B.bosses) do if x.enc == id then n = #Runs.levels(x) - 1 end end
        e.rp = (n and n > 0) and n or nil
      end
    end
    openBlocks(B)
  end
  return Runs.closeRec(A), isOpen and B or Runs.closeRec(B)
end
-- what a closed record of an edit ends as: the gold of its visits, no empty XP, lean
function Runs.closeRec(r)
  r.gold = Runs.goldOf(r)
  if not (type(r.xp) == "table" and num(r.xp.gain) > 0) then r.xp = nil end
  if r.deaths and #r.deaths > Runs.DEATH_CAP then for i = #r.deaths, Runs.DEATH_CAP + 1, -1 do r.deaths[i] = nil end end
  Runs.lean(r)
  return r
end
-- Join run B onto the run A before it: one run again, the time between them put back as the gap before B's first
-- visit (the kinds B's first visit keeps from a split, else all of it as time outside). Rows of the same boss are
-- one row. `isOpen`: B is the open run and the joined run goes on as it. Returns the run, or nil and why.
function Runs.joinRec(A, B, isOpen)
  if A.inst ~= B.inst or A.kind ~= B.kind then return nil, "other" end
  if #A.visits + #B.visits > Runs.VISIT_CAP then return nil, "visits" end
  local _, gA = Runs.visitClocks(A)
  local sB, gB = Runs.visitClocks(B)
  if not (gA and gB) then return nil, "old" end
  local wJ, gapW = B.t - A.t, B.t - A.endT
  if gapW < 0 then return nil, "order" end
  local f = B.visits[1]
  local tri = { num(f.gg), num(f.go), num(f.gf) }
  if tri[1] + tri[2] + tri[3] ~= gapW then tri = { 0, gapW, 0 } end
  local cJ = num(A.secs.inside) + num(A.secs.ghost) + tri[1]
  local J = { id = A.id, v = Runs.V, inst = A.inst, kind = A.kind, map = A.map or B.map, diff = A.diff or B.diff, uiMap = A.uiMap or B.uiMap,
    t = A.t, endT = B.endT, open = A.open, why = B.why, partial = A.partial or B.partial, keep = (A.keep or B.keep) or nil, edited = true, exact = B.exact }
  -- (a closed record keeps `size` only for a run played alone: no size is a group; the joined run is alone only
  -- when both were)
  if A.size or B.size then J.size = max(plainNum(A.size) or 2, plainNum(B.size) or 2) end
  J.visits = {}
  for j, x in ipairs(A.visits) do local y = copyT(x); if j >= 2 then setGap(y, gA[j]) end; J.visits[#J.visits + 1] = y end
  for j, x in ipairs(B.visits) do
    local y = copyT(x)
    y.i = num(y.i) + wJ
    if plainNum(y.o) then y.o = y.o + wJ end
    if type(y.gaps) == "table" then for q = 1, #y.gaps do y.gaps[q] = y.gaps[q] + wJ end end
    if plainNum(y.fc) then y.fc = y.fc + cJ end
    setGap(y, j == 1 and tri or gB[j])
    J.visits[#J.visits + 1] = y
  end
  J.secs = {}
  for _, k in ipairs(Runs.SECS) do J.secs[k] = num(A.secs[k]) + num(B.secs[k]) end
  for q = 1, 3 do J.secs[SECS_GAP[q]] = J.secs[SECS_GAP[q]] + tri[q] end
  if plainNum(A.firstPull) then J.firstPull = A.firstPull elseif plainNum(B.firstPull) then J.firstPull = B.firstPull + cJ end
  -- B's first visit gave its first combat to B's `firstPull` (Runs.lean): it is that visit's again
  local bf = J.visits[#A.visits + 1]
  if bf and not plainNum(bf.fc) and plainNum(B.firstPull) then
    local other = false
    for j = 2, #B.visits do if B.visits[j].fc == B.firstPull then other = true end end
    if not other then bf.fc = B.firstPull + cJ end
  end
  -- Rows of the same boss are one row again: the copies of A's row, then B's (Runs.parts). B's first copy goes on
  -- A's last when that one has no kill (the same copy, pulled again after the gap); else it is a copy of its own,
  -- a boss killed before pulled again (Runs.encStart), in the visit it began in.
  local rows, byEnc = {}, {}
  for i, b in ipairs(A.bosses) do local r = { b = copyT(b), i = i }; rows[#rows + 1] = r; byEnc[b.enc] = r end
  for i, b in ipairs(B.bosses) do
    local P = Runs.parts(b)
    for q, s in ipairs(P) do
      local v = (q > 1 and s.v) or Runs.visitAt(sB, s.p)
      if s.kill then s.kill = s.kill + cJ end
      s.p, s.v = s.p + cJ, v + #A.visits
    end
    local r = byEnc[b.enc]
    if r then
      local PA = Runs.parts(r.b)
      local last = PA[#PA]
      local from = 1
      if not last.kill then
        local f = P[1]
        last.pulls = last.pulls + f.pulls
        for _, k in ipairs(Runs.PART_SUM) do last[k] = last[k] + f[k] end
        last.kill, last.fight, last.ok, last.dur = f.kill, f.fight, f.ok, f.dur
        from = 2
      end
      for q = from, #P do PA[#PA + 1] = P[q] end
      local name = r.b.name or b.name
      r.b = Runs.stack(PA, r.b)
      r.b.name = name
    else r = { b = Runs.stack(P, b), i = 1000 + i }; rows[#rows + 1] = r; byEnc[b.enc] = r end
  end
  if #rows > Runs.BOSS_CAP then return nil, "bosses" end
  table.sort(rows, function(x, y)
    local px, py = Runs.pullOf(x.b), Runs.pullOf(y.b)
    if px ~= py then return px < py end
    return x.i < y.i
  end)
  J.bosses = {}
  for _, r in ipairs(rows) do J.bosses[#J.bosses + 1] = r.b end
  -- (the mark of the copies, as Runs.splitRec gives it; a record whose parts do not say which visit keeps its own)
  if Runs.hasParts(J) then J.repull = Runs.repullOf(J)
  else J.repull = plainNum(A.repull) or (plainNum(B.repull) and B.repull + #A.visits) or nil end
  J.deaths = {}
  for _, d in ipairs(type(A.deaths) == "table" and A.deaths or {}) do J.deaths[#J.deaths + 1] = copyT(d) end
  for _, d in ipairs(type(B.deaths) == "table" and B.deaths or {}) do local x = copyT(d); x.o = num(x.o) + cJ; J.deaths[#J.deaths + 1] = x end
  local nA, nB = type(A.nDeaths) == "table" and A.nDeaths or {}, type(B.nDeaths) == "table" and B.nDeaths or {}
  J.nDeaths = { me = num(nA.me) + num(nB.me), party = num(nA.party) + num(nB.party) }
  local hA, hB = type(A.hidden) == "table" and A.hidden or {}, type(B.hidden) == "table" and B.hidden or {}
  J.hidden = { xp = num(hA.xp) + num(hB.xp), rep = num(hA.rep) + num(hB.rep), loot = num(hA.loot) + num(hB.loot) }
  local xA, xB = type(A.xp) == "table" and A.xp or nil, type(B.xp) == "table" and B.xp or nil
  if xA or xB then
    xA, xB = xA or {}, xB or {}
    J.xp = { gain = num(xA.gain) + num(xB.gain), kill = num(xA.kill) + num(xB.kill), quest = num(xA.quest) + num(xB.quest), n = num(xA.n) + num(xB.n) }
    J.xp.l0, J.xp.p0 = xA.l0 or xB.l0, xA.p0 or xB.p0
    if xB.l1 or xB.p1 then J.xp.l1, J.xp.p1, J.xp.need = xB.l1, xB.p1, xB.need else J.xp.l1, J.xp.p1, J.xp.need = xA.l1, xA.p1, xA.need end
  end
  if isOpen then
    for _, key in ipairs(Runs.OPEN_KEYS) do J[key] = copyT(B[key]) end
    for id, e in pairs(type(J.encs) == "table" and J.encs or {}) do
      if type(e) == "table" then
        e.o = num(e.o) + cJ
        -- (a pull still open belongs to the newest copy of its row: a boss the run before killed is a copy more)
        local r = byEnc[id]
        local n = r and (#Runs.levels(r.b) - 1) or 0
        e.rp = n > 0 and n or nil
      end
    end
    openBlocks(J)
    return J
  end
  return Runs.closeRec(J)
end
-- Split here: the run at visit k. Returns true, or false and why ("visit", "old", "gone").
function Runs.split(id, k)
  local c = me()
  if not (c and Runs._read) then return false, "char" end
  local rec, i, isOpen = Runs.find(c, id)
  if not rec then return false, "gone" end
  if isOpen then Runs.flush(rec); if rec.st == "in" then Runs.goldTake(c, rec) end end
  local A, B = Runs.splitRec(rec, k, isOpen)
  if not A then return false, B end
  local list = type(c.dungeonRuns) == "table" and c.dungeonRuns or {}
  c.dungeonRuns = list
  if isOpen then
    c.dungeonRun = B
    list[#list + 1] = A
    Runs.statsAdd(c, A)
  else
    list[i] = A
    table.insert(list, i + 1, B)
    Runs.statsApply(c, rec, -1)
    Runs.statsAdd(c, A); Runs.statsAdd(c, B)
  end
  Runs.copyAdd(c, B, "split")
  Runs.evict(list, c)
  Runs.note("split")
  return true
end
-- Join with previous run: the run and the stored run just before it (of the same dungeon). Refused when a run that
-- lay between them was evicted from the list. Returns true and the joined run's id, or false and why ("none", "other", "evicted", "visits",
-- "bosses", "old").
function Runs.join(id)
  local c = me()
  if not (c and Runs._read) then return false, "char" end
  local rec, i, isOpen = Runs.find(c, id)
  if not rec then return false, "gone" end
  local list = type(c.dungeonRuns) == "table" and c.dungeonRuns or {}
  local ai = isOpen and #list or ((i or 1) - 1)
  local A = list[ai]
  if not (ai >= 1 and type(A) == "table" and Runs.valid(A)) then return false, "none" end
  if num(c.dungeonEvictedTo) > A.endT then return false, "evicted" end
  if isOpen then Runs.flush(rec); if rec.st == "in" then Runs.goldTake(c, rec) end end
  local J, why = Runs.joinRec(A, rec, isOpen)
  if not J then return false, why end
  Runs.copyDrop(c, rec.id)
  table.remove(list, ai)
  if isOpen then
    c.dungeonRun = J
    Runs.statsApply(c, A, -1)
  else
    list[ai] = J
    Runs.statsApply(c, A, -1); Runs.statsApply(c, rec, -1)
    Runs.statsAdd(c, J)
  end
  Runs.note("join")
  return true, J.id                                              -- (the joined run keeps the id of the first)
end
-- the run in the pill and the bar text: "Deadmines 18m · 3/7 · +0:41" (nil when no run is open)
-- It is drawn again every 10 s (Gold.rateWatch), so the clock reads whole minutes, never a second that is already
-- stale; it reads the record without changing it, and the list and the best are worked out once per kill.
function Runs.glanceClock(sec)
  sec = floor(max(0, num(sec)))
  if sec >= 3600 then return ("%dh %02dm"):format(floor(sec / 3600), floor((sec % 3600) / 60)) end
  return floor(sec / 60) .. "m"
end
function Runs.glance()
  local c = me()
  local run = cur(c)
  if not (run and Runs.valid(run)) then return nil end
  local down = 0
  for _, b in ipairs(run.bosses) do if b.kill then down = down + 1 end end
  local S = statsOf(c)
  local s = S and S[Runs.keyOf(run)]
  local key = ("%s:%d:%d:%d"):format(run.id, down, num(type(s) == "table" and s.n), num(run.firstPull))
  local g = Runs._glance
  if not (g and g.key == key) then
    local cmp = Runs.compare(run, true)
    g = { key = key, total = (Runs.bossTotal(run)), delta = cmp and cmp.delta }
    Runs._glance = g
  end
  local parts = { run.inst .. " " .. Runs.glanceClock(Runs.clock(run)), g.total and (down .. "/" .. g.total) or tostring(down) }
  if g.delta then parts[#parts + 1] = Runs.signed(g.delta) end
  return table.concat(parts, " · ")
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
-- What a view reads from the statistics (the learned list, the best, whether it is the run's), kept per record until
-- the statistics or the run's bosses change: the Dungeons list draws every run again every 3 s. Weak keys: a record
-- that leaves the save leaves this too.
Runs._vc = setmetatable({}, { __mode = "k" })
function Runs.viewStats(rec, isOpen)
  local S = statsOf(me())
  local kills = 0
  for _, b in ipairs(rec.bosses) do if b.kill then kills = kills + 1 end end
  local key = ("%d:%s:%d:%d:%s:%s"):format(num(Runs._gen), tostring(S), #rec.bosses, kills, num(rec.firstPull), isOpen and "o" or "c")
  local x = Runs._vc[rec]
  if not (x and x.key == key) then
    local total, missing = Runs.bossTotal(rec)
    x = { key = key, total = total, missing = missing, cmp = Runs.compare(rec, isOpen), pb = Runs.isPb(rec) }
    Runs._vc[rec] = x
  end
  return x
end
-- One run as the pane reads it. The record is never changed by a view, except that an open run is brought up to
-- the second first. `full`: also the fights and the rare-or-better loot rows still stored, by the time of the
-- run's visits (never by a row's zone: a loot row's zone is the one of the last loot window, often another place).
-- `light`: only what the run headers of the Fights list read (name, start, bosses down, deaths, the record), nothing
-- from the statistics.
function Runs.view(rec, isOpen, full, light)
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
  -- (the run's fights, the one list the run page and the Fights list's group rows count, B23)
  if full then v.fights = Runs.fightsOf(rec) end
  if light then return v end
  v.splits = Runs.splits(rec)
  -- (0.9.51) the learned boss list, the best, the marks an edit and a repeated pull leave
  local vs = Runs.viewStats(rec, isOpen)
  v.total, v.missing, v.cmp = vs.total, vs.missing, vs.cmp
  -- the Pace section waits for the dungeon's first full clear (plan 5.B)
  local S = statsOf(me())
  local st = S and S[Runs.keyOf(rec)]
  -- (the Pace section asks for the same bosses killed twice, as its empty sentence says: a full clear, or a route run
  -- twice; a dungeon with a boss always left up has no full clear and still has a pace)
  local sig = Runs.sigOf(rec)
  local route = sig and type(st) == "table" and type(st.routes) == "table" and st.routes[sig] or nil
  v.cleared = (type(st) == "table" and (num(st.full) > 0 or (route and num(route.n) >= 2))) or nil
  v.done, v.pb, v.edited, v.repull, v.exact, v.keep, v.size = rec.done, vs.pb, rec.edited, rec.repull, rec.exact, rec.keep, rec.size
  local warm = v.active >= Runs.RATE_WARM
  v.xpGain = type(rec.xp) == "table" and num(rec.xp.gain) or 0
  v.xpPerHour = (warm and v.xpGain > 0) and v.xpGain * 3600 / v.active or nil
  v.coinPerHour = warm and v.coin * 3600 / v.active or nil
  if full then
    v.fights = v.fights or Runs.fightsOf(rec)
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
-- a fight is the run's only in the run's instance (B3): its instance map id (GetInstanceInfo, as the run's) when both
-- know one, else its zone by name. A fight that names neither cannot be placed and is not counted (the open world
-- between two visits must never be).
function Runs.inInstance(rec, f)
  if type(f) ~= "table" or type(rec) ~= "table" then return false end
  local fm, rm = plainNum(f.instanceMapID), plainNum(rec.map)
  if fm and rm then return fm == rm end
  local z, n = f.zone, rec.inst
  if type(z) ~= "string" or type(n) ~= "string" then return false end
  return z:lower() == n:lower()
end
-- the fights of a run: the stored fights that began inside one of its visits, in its instance
function Runs.fightsOf(rec)
  return Runs.rowsOf(rec, ns.Fights and ns.Fights.list and ns.Fights.list(), "startEpoch", function(f) return Runs.inInstance(rec, f) end)
end
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
-- the runs of the logged-in character, oldest first, the open one last (`light`: Runs.view)
function Runs.views(full, light)
  local out = {}
  local c = me()
  if not c then return out end
  for _, r in ipairs(type(c.dungeonRuns) == "table" and c.dungeonRuns or {}) do
    if Runs.valid(r) then out[#out + 1] = Runs.view(r, false, full, light) end
  end
  local run = cur(c)
  if run and Runs.valid(run) then out[#out + 1] = Runs.view(run, true, full, light) end
  return out
end
-- "12,300 XP · 23,000 per hour · level 23.4 to 24.1", then on a line of their own the quest XP and the kills the
-- client let the addon read, then what it hid. Returns the three (the last two or nil). Stored facts only: there is
-- no "about N more runs to level L" (a forecast from kill XP, false the moment the character levels another way).
function Runs.xpLine(v)
  local x = v.xp
  if type(x) ~= "table" or v.xpGain <= 0 then return nil end
  local SEP = "  ·  "
  local parts = { Runs.commas(v.xpGain) .. " XP" }
  if v.xpPerHour then parts[#parts + 1] = Runs.commas(v.xpPerHour) .. " per hour" end
  if x.l0 and x.p0 and x.l1 and x.p1 then
    -- (one decimal, two when the run moved the level less than a tenth: "level 18.71 to 18.77", never "18.7 to 18.7";
    -- left out when even two decimals show no change)
    local a1, b1 = floor(x.p0 * 10), floor(x.p1 * 10)
    local a2, b2 = floor(x.p0 * 100), floor(x.p1 * 100)
    if x.l0 ~= x.l1 or a1 ~= b1 then parts[#parts + 1] = ("level %.1f to %.1f"):format(x.l0 + a1 / 10, x.l1 + b1 / 10)
    elseif a2 ~= b2 then parts[#parts + 1] = ("level %.2f to %.2f"):format(x.l0 + a2 / 100, x.l1 + b2 / 100) end
  end
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
  local parts = { v.name .. (v.inProgress and " (in progress)" or ""), fmtDur(v.duration), "bosses " .. v.bossesDown .. (v.total and ("/" .. v.total) or ""),
    ("%d death%s"):format(v.deaths, v.deaths == 1 and "" or "s") }
  if v.xpGain > 0 then
    parts[#parts + 1] = Runs.commas(v.xpGain) .. " XP" .. (v.xpPerHour and (" (" .. Runs.commas(v.xpPerHour) .. " per hour)") or "")
  end
  parts[#parts + 1] = ns.fmtMoney(v.coin)
  return table.concat(parts, ", ") .. "."
end
-- /eb instances: the hour line in the player's own chat. /eb instances limit 5 (or 10, or off): the limit the
-- player plays by, shown beside the count ("3 of 5"); unset by default, since nobody knows the server's.
function Runs.instancesSlash(rest)
  local arg = tostring(rest or ""):lower()
  local lim = arg:match("^limit%s*(%S*)$")
  if lim then
    local st = ns.DB and ns.DB.settings
    if type(st) ~= "table" then ns.msg("instances: settings are not loaded yet"); return true end
    local n = tonumber(lim)
    if lim == "off" or lim == "" or n == 0 then st.instanceLimit = nil; ns.msg("instances: no limit is shown")
    elseif n and n >= 1 and n <= 99 and n == floor(n) then st.instanceLimit = n; ns.msg(("instances: shown against your limit of %d"):format(n))
    else ns.msg("usage: /eb instances limit 5  (or 10, or off)") end
    return true
  end
  ns.msg(Runs.hourLine())
  return true
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
