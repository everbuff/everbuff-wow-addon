-- Everbuff.GG · Progress.lua - the CHARACTER host: Leveling, Reputation and Professions (docs/UX_OVERHAUL.md 4.10, 4.11).
--
-- Leveling is the level (or the time to the next one), the played time and when each level was reached; a leveling
-- character also has the quests turned in. Reputation lists every faction with its standing, what is left to the
-- next one and the last day it gained; a faction with stored gains opens them. Professions lists the skills with
-- their bar and when to train next, then what was crafted, one row per batch (docs/UX_PRAGMATIC.md 3.1 to 3.3).
-- The data is what other modules capture (the story events, the session records, the reputation gains, the
-- professions snapshot, the crafts Market keeps, the gold journal), plus the live reputation bars and the leveling
-- pace (ns.Pace). Every list reads the logged-in character's rows only (#23). Built from the kit (UI.lua) only.

local ADDON, ns = ...
local UI = ns.UI
local C = ns.UI.C
local S, G, H = UI.S, UI.G, UI.H

local function num(v) return (type(v) == "number" and v == v) and v or 0 end
local function plain(v) if type(v) == "number" and not (issecretvalue and issecretvalue(v)) then return v end return nil end
local function plainStr(v) if type(v) == "string" and not (issecretvalue and issecretvalue(v)) then return v end return nil end
local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c, d, e, f, g, h, i = pcall(fn, ...)
  if not ok then return nil end
  return a, b, c, d, e, f, g, h, i
end
local function nowT() return (GetServerTime and GetServerTime()) or time() end
local function stripPrefix(text, prefix)
  text = text or ""
  if text:sub(1, #prefix) == prefix then return (text:sub(#prefix + 1):gsub("^%s+", "")) end
  return text
end
local function curSession() return (ns.Recorder and ns.Recorder.current and ns.Recorder.current()) or nil end
local function sid() local s = curSession(); return (ns.DB and ns.DB.active) or (s and s.id) end   -- this session
local function events() return ns.mine(ns.DB and ns.DB.story and ns.DB.story.events) end
local function charDB() return (ns.DB and ns.char()) or {} end

-- ══ data: pure builders (also exported for the headless tests) ═════════════════════════════════════════════════
-- a quest's name from the game by its id, nil when the client has none
local function questName(id)
  id = tonumber(id)
  if id and C_QuestLog and C_QuestLog.GetTitleForQuestID then
    local ok, v = pcall(C_QuestLog.GetTitleForQuestID, id)
    if ok and plainStr(v) and v ~= "" then return v end
  end
  return nil
end
-- the quest money of the gold journal: { t, amount, quest id } of every "quests" row of the character's sessions
local function questMoney()
  local out = {}
  local Gold = ns.Gold
  if not (Gold and Gold.sessions and Gold.entries) then return out end
  local okI, ix = pcall(Gold.index)
  local okS, list = pcall(Gold.sessions)
  if not (okS and type(list) == "table") then return out end
  for _, sess in ipairs(list) do
    local ok, rows = pcall(Gold.entries, sess, okI and ix or nil)
    if ok and type(rows) == "table" then
      for _, e in ipairs(rows) do
        if e.src == "quests" then out[#out + 1] = { t = num(e.t), amount = num(e.delta), quest = e.ref and tonumber(e.ref.quest) } end
      end
    end
  end
  return out
end
-- QUESTS TURNED IN: every QUESTDONE row newest first, each with the gold the journal booked for it (within 5 s)
local function buildQuests()
  local money = questMoney()
  local taken = {}
  local rows = {}
  for _, e in ipairs(events()) do
    if e.kind == "QUESTDONE" then
      local nm = stripPrefix(e.text, "Complete:")
      local r = { t = num(e.t), zone = e.zone, sub = e.sub, x = e.x, y = e.y }
      local best, bi
      for i, m in ipairs(money) do
        if not taken[i] and math.abs(m.t - r.t) <= 5 and (not best or math.abs(m.t - r.t) < math.abs(best.t - r.t)) then best, bi = m, i end
      end
      if best then taken[bi] = true; r.gold, r.questId = best.amount, best.quest end
      -- a name the client did not give at turn-in ("quest") is resolved by id, else shown as "Quest 1234"
      if nm == "" or nm == "quest" then
        local byId = questName(r.questId)
        if byId then r.name = byId
        else r.unnamed = true; r.name = r.questId and ("Quest " .. r.questId) or "Unnamed quest" end
      else r.name = nm end
      rows[#rows + 1] = r
    end
  end
  table.sort(rows, function(a, b) return a.t > b.t end)
  local x = charDB().xp or {}
  return rows, { done = #rows, xp = num(x.fromQuests), kills = num(x.fromKills) }
end

-- LEVELS: when each level was reached (docs/UX_PRAGMATIC.md 3.1, gate E). Three stored sources, none worked out
-- from the /played stamps:
--   exact: the LEVELUP story event, and the LEVEL_UP row of a stored session record ("seq, server time, clock,
--     LEVEL_UP, level, zone"), which outlives the event list;
--   a bound: the levels a stored session record started and ended on, with its start and end, say between which two
--     moments a level was reached when its own row is gone ("between 17:02 and 20:06");
--   characters[guid].levelAt, where both are kept ({ t, zone } or { from, to } per level): the event list holds 500
--     rows and the desktop's pickup deletes session records, so ns.Levels.harvest copies what they say on every load
--     and before every pickup is applied (Core.lua). A stored moment is never replaced by a later one, and a bound
--     only ever narrows.
local Levels = {}
ns.Levels = Levels
local function levelOf(e) return tonumber(tostring(e.text or ""):match("(%d+)")) end
local function wholeLevel(L) L = tonumber(L); return (L and L >= 1 and L == math.floor(L)) and L or nil end
-- What a set of session records and story events says: { [level] = { t, zone } or { from, to } } for the levels 2
-- to `cur` (default: the highest level the records name).
function Levels.derive(sessions, events, cur)
  local exact, spans, top = {}, {}, 0
  local function note(L, t, zone)
    L, t = wholeLevel(L), tonumber(t)
    if not (L and L >= 2 and t and t > 0) then return end
    zone = (type(zone) == "string" and zone ~= "" and zone ~= "?") and zone or nil
    local r = exact[L]
    if not r or t < r.t then exact[L] = { t = t, zone = zone or (r and r.zone) or nil }
    elseif not r.zone then r.zone = zone end
    if L > top then top = L end
  end
  for _, e in ipairs(events or {}) do
    if type(e) == "table" and e.kind == "LEVELUP" then note(levelOf(e), e.t, e.zone) end
  end
  for _, sess in ipairs(sessions or {}) do
    if type(sess.segments) == "table" then
      for _, seg in ipairs(sess.segments) do
        if type(seg) == "string" and seg:find("\tLEVEL_UP\t", 1, true) then
          local t, L, zone = seg:match("^%d+\t(%d+)\t[%d%.]+\tLEVEL_UP\t(%d+)\t?(.*)$")
          note(L, t, zone)
        end
      end
    end
    -- (a record whose levels were not read, 0, says nothing)
    local l0, l1, a, z = wholeLevel(sess.level0), wholeLevel(sess.level), tonumber(sess.startedEpoch), tonumber(sess.endedEpoch)
    if l0 and l1 and l1 >= l0 and a and a > 0 then
      spans[#spans + 1] = { l0 = l0, l1 = l1, a = a, z = (z and z >= a) and z or nil }
      if l1 > top then top = l1 end
    end
  end
  cur = wholeLevel(cur) or top
  local out = {}
  for L = 2, cur do
    if exact[L] then out[L] = exact[L]
    else
      -- reached after every moment the character was still below L, and before every moment it was already on it
      local from, to
      local function after(t) if t and (not from or t > from) then from = t end end
      local function before(t) if t and (not to or t < to) then to = t end end
      for _, sp in ipairs(spans) do
        if sp.l0 < L then after(sp.a) end
        if sp.l1 < L then after(sp.z) end
        if sp.l0 >= L then before(sp.a) end
        if sp.l1 >= L then before(sp.z) end
      end
      for k, r in pairs(exact) do
        if k < L then after(r.t) elseif k > L and k <= cur then before(r.t) end
      end
      if from and to and from <= to then out[L] = { from = from, to = to } end
    end
  end
  return out
end
-- `fresh` laid over `stored`: the earliest exact moment wins, an exact moment replaces a bound, two bounds narrow.
function Levels.merge(stored, fresh)
  local out = {}
  local function valid(r)
    if type(r) ~= "table" then return nil end
    if tonumber(r.t) and r.t > 0 then return "t" end
    if tonumber(r.from) and tonumber(r.to) and r.from > 0 and r.from <= r.to then return "b" end
    return nil
  end
  for _, src in ipairs({ type(stored) == "table" and stored or {}, type(fresh) == "table" and fresh or {} }) do
    for L, r in pairs(src) do
      local kind = valid(r)
      L = wholeLevel(L)
      if L and kind then
        local have = out[L]
        local hk = valid(have)
        if kind == "t" then
          if hk ~= "t" or r.t < have.t then out[L] = { t = r.t, zone = r.zone or (hk == "t" and have.zone or nil) }
          elseif not have.zone then have.zone = r.zone end
        elseif hk == nil then out[L] = { from = r.from, to = r.to }
        elseif hk == "b" then
          local from, to = math.max(have.from, r.from), math.min(have.to, r.to)
          if from <= to then have.from, have.to = from, to end
        end
      end
    end
  end
  return out
end
-- Copies what the save's session records and events say into each character's block (never creates a block).
-- Returns how many characters were read.
function Levels.harvest(db)
  if not (type(db) == "table" and type(db.characters) == "table") then return 0 end
  local by = {}
  local function of(guid)
    if type(guid) ~= "string" or not db.characters[guid] then return nil end
    by[guid] = by[guid] or { sessions = {}, events = {} }
    return by[guid]
  end
  for _, sess in pairs(type(db.sessions) == "table" and db.sessions or {}) do
    if type(sess) == "table" then local b = of(sess.guid); if b then b.sessions[#b.sessions + 1] = sess end end
  end
  for _, e in ipairs(type(db.story) == "table" and type(db.story.events) == "table" and db.story.events or {}) do
    if type(e) == "table" and e.kind == "LEVELUP" then
      local sess = db.sessions and db.sessions[e.s]
      local b = type(sess) == "table" and of(sess.guid)
      if b then b.events[#b.events + 1] = e end
    end
  end
  local n = 0
  for guid, b in pairs(by) do
    local c = db.characters[guid]
    local merged = Levels.merge(c.levelAt, Levels.derive(b.sessions, b.events))
    if next(merged) then c.levelAt = merged end
    n = n + 1
  end
  return n
end
-- seconds played since /played last answered, counted only while that answer is of this login (never time logged out)
local function sinceAnswer(pl, now)
  local ses = curSession()
  local st = ses and tonumber(ses.startedEpoch)
  return (st and num(pl.atEpoch) >= st) and math.max(0, (now or nowT()) - num(pl.atEpoch)) or 0
end
-- the played time at the level the character is on, nil while the game has not answered /played
local function timeAtLevel(now)
  local db = charDB()
  local pl = type(db.played) == "table" and db.played or {}
  if num(pl.level) <= 0 then return nil end
  return num(pl.level) + sinceAnswer(pl, now)
end
-- the character's played time in all, nil while the game has not answered /played
local function playedTotal(now)
  local db = charDB()
  local pl = type(db.played) == "table" and db.played or {}
  if num(pl.total) <= 0 then return nil end
  return num(pl.total) + sinceAnswer(pl, now)
end
-- The rows of the Levels table, highest level first, and how many of the levels 2 to `cur` have nothing recorded.
-- An exact row is { level, t, zone }. Levels that share one bound are one row { level (the highest), lo (the
-- lowest), from, to }: "30 to 37" were all reached between the same two stored moments.
local function buildLevels(cur)
  local mine = {}
  for _, sess in pairs((ns.DB and ns.DB.sessions) or {}) do
    if type(sess) == "table" and ns.isMySession(sess) then mine[#mine + 1] = sess end
  end
  local at = Levels.merge(charDB().levelAt, Levels.derive(mine, events(), cur))
  local top = 0
  for L in pairs(at) do if L > top then top = L end end
  if cur then top = math.min(top, cur) end
  local rows, known = {}, 0
  local open
  for L = top, 2, -1 do
    local r = at[L]
    if r then known = known + 1 end
    if r and r.t then rows[#rows + 1] = { level = L, t = r.t, zone = r.zone }; open = nil
    elseif r then
      if open and open.from == r.from and open.to == r.to and open.lo == L + 1 then open.lo = L
      else open = { level = L, lo = L, from = r.from, to = r.to }; rows[#rows + 1] = open end
    else open = nil end
  end
  local missing = (cur and cur >= 2) and math.max(0, (cur - 1) - known) or 0
  return rows, missing
end

-- reputation: the snapshot Emitter keeps (faction -> standing) merged with the live bars the client answers now
local STANDINGS = { "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted" }
local function readFactions()
  local out = {}
  pcall(function()
    if C_Reputation and C_Reputation.GetNumFactions and C_Reputation.GetFactionDataByIndex then
      for i = 1, num(plain(call(C_Reputation.GetNumFactions))) do
        local d = call(C_Reputation.GetFactionDataByIndex, i)
        if type(d) == "table" and plainStr(d.name) and not d.isHeader then
          out[d.name] = { standing = plain(d.reaction), min = plain(d.currentReactionThreshold), max = plain(d.nextReactionThreshold), value = plain(d.currentStanding) }
        end
      end
    elseif GetNumFactions and GetFactionInfo then
      for i = 1, num(plain(call(GetNumFactions))) do
        local name, _, standingID, barMin, barMax, barValue, _, _, isHeader = call(GetFactionInfo, i)
        name = plainStr(name)
        if name and not isHeader then out[name] = { standing = plain(standingID), min = plain(barMin), max = plain(barMax), value = plain(barValue) } end
      end
    end
  end)
  return out
end
-- Whose a stored reputation gain is (docs/UX_PRAGMATIC.md 3.2, gate F). A row written from 0.9.52 carries its
-- character (`g`). An older row has only its session id, and the desktop's pickup deletes session records, so
-- ns.Rep.harvest writes `g` on every row it can prove, at every load and before every pickup is applied (Core.lua,
-- beside ns.Levels.harvest). Two proofs, both stored facts:
--   the session record of the row (sessions[s].guid), while it is still in the save;
--   a row inside one character's own block that carries the same session id (characters[guid].crafts[].s,
--     recipes[].s), when the record is gone. A session id that two characters' blocks name proves nothing.
-- A row neither proves stays without `g`: it is shown for no character (never attributed by guesswork).
local Rep = {}
ns.Rep = Rep
local function recordGuid(sessions, s)
  local rec = s ~= nil and sessions[s] or nil
  local g = type(rec) == "table" and rec.guid or nil
  return (type(g) == "string" and g ~= "") and g or nil
end
-- Returns how many rows got their character.
function Rep.harvest(db)
  local list = type(db) == "table" and type(db.story) == "table" and db.story.rep
  if type(list) ~= "table" then return 0 end
  local sessions = type(db.sessions) == "table" and db.sessions or {}
  local proof    -- session id -> guid, or false when two characters name it; built on the first row that needs it
  local function proven(s)
    if not proof then
      proof = {}
      for guid, c in pairs(type(db.characters) == "table" and db.characters or {}) do
        if type(guid) == "string" and type(c) == "table" then
          for _, key in ipairs({ "crafts", "recipes" }) do
            for _, r in ipairs(type(c[key]) == "table" and c[key] or {}) do
              local id = type(r) == "table" and r.s or nil
              if id ~= nil then
                if proof[id] == nil then proof[id] = guid elseif proof[id] ~= guid then proof[id] = false end
              end
            end
          end
        end
      end
    end
    return proof[s] or nil
  end
  local n = 0
  for _, r in ipairs(list) do
    if type(r) == "table" and r.g == nil and r.s ~= nil then
      local g = recordGuid(sessions, r.s) or (sessions[r.s] == nil and proven(r.s)) or nil
      if g then r.g = g; n = n + 1 end
    end
  end
  return n
end
-- The stored reputation gains of the logged-in character, in stored order, and `loose`: per faction the time of
-- the newest stored gain that names no character at all (no `g`, and no session record that names one). A loose
-- row may be this character's or another's, so a figure that would have to include it is not shown.
local function repGains()
  local list = ns.DB and ns.DB.story and ns.DB.story.rep
  local me = ns.charGuid()
  local loose = {}
  if not (list and me) then return ns.mine(list), loose end
  local sessions = (ns.DB and ns.DB.sessions) or {}
  local out = {}
  for _, r in ipairs(list) do
    if type(r) == "table" then
      local g = r.g
      if g == nil then g = recordGuid(sessions, r.s) end
      if g == me then out[#out + 1] = r
      elseif g == nil and r.faction then
        local t = num(r.t)
        if not loose[r.faction] or t > loose[r.faction] then loose[r.faction] = t end
      end
    end
  end
  return out, loose
end
-- the session ids of "this session": logins less than 5 minutes apart are one (Gold.joined, the one definition)
local function sessionIds()
  local ids = {}
  local ok, list = pcall(function() return ns.Gold and ns.Gold.joined and ns.Gold.joined() end)
  if ok and type(list) == "table" then for _, s in ipairs(list) do if s.id then ids[s.id] = true end end end
  local s = sid()
  if s then ids[s] = true end
  return ids
end
local function dayKey(t) return date("%Y%m%d", t) end
-- story.rep is one list for every character and holds Rep.CAP rows: Emitter.repGain drops the oldest row for every
-- row past that. A list that has reached the cap has therefore lost rows, all of them older than its first row or
-- of the same moment. Rep.cut() is nil while the list is under the cap, else the time of its first row and the day
-- of that time: the stored gains of that day (and of any day before it) are not all there, so a sum over them is a
-- lower bound, never the day's sum. Every gain after that moment is stored.
Rep.CAP = 2000
function Rep.cut()
  local list = ns.DB and ns.DB.story and ns.DB.story.rep
  if type(list) ~= "table" or #list < Rep.CAP then return nil end
  for _, r in ipairs(list) do
    local t = type(r) == "table" and tonumber(r.t) or nil
    if t and t > 0 then return t, dayKey(t) end
  end
  return nil
end
-- Rows { name, standing, label, progress, need (live, nil when the client has not answered), hasGains (a stored
-- gain of this character: the row opens), ownLast (the time of this character's newest stored gain), lastGain (the
-- same time, only while its day is certainly the last day the faction gained), dayGain (this character's stored
-- gains on that day), atLeast, uncertain, partial, cut, session (what it gained this session, nil when nothing),
-- sessionAtLeast }.
-- A stored gain of the faction that names no character (a loose row) may be this character's or another's. Two
-- facts are kept apart, the day and the day's sum:
--   no loose row on the day of ownLast or later: the day and its sum are exact;
--   a loose row on that same day, none later: the day is certain, the sum is a lower bound (`atLeast`);
--   a loose row on a later day, or no gain of this character at all: the last day cannot be said (`uncertain`),
--     lastGain and dayGain are nil.
-- The list is capped (Rep.cut): when it is full and the day of ownLast is the day of its first row or an earlier
-- one, rows of that day were dropped, so the day's sum is a lower bound too (`atLeast`, and `cut` names the reason).
-- The same holds for this session: when the full list starts at or after the start of the session (or the start is
-- not stored, or the first row is a row of the session), `sessionAtLeast` is set on every row with a session sum.
-- `partial` is true in the last two cases and in the lower-bound cases. Order: factions with a certain last day
-- first, by that day (newest first), then by what the day brought, largest first; then the rest by standing, and a
-- Neutral faction with no stored gain last.
local function buildReputation()
  local snap = charDB().reputation or {}
  local live = readFactions()
  local session, last, day = {}, {}, {}
  local ids = sessionIds()
  local gains, loose = repGains()
  local cutT, cutDay = Rep.cut()
  local sesCut = false
  if cutT then
    local ok, start = pcall(function() return ns.Gold and ns.Gold.joinedStart and ns.Gold.joinedStart() end)
    start = ok and tonumber(start) or nil
    local first = ns.DB.story.rep[1]
    sesCut = start == nil or start <= cutT or (type(first) == "table" and first.s ~= nil and ids[first.s] == true)
  end
  local oldest
  for _, g in ipairs(gains) do
    if g.faction then
      local t = num(g.t)
      if g.s ~= nil and ids[g.s] then session[g.faction] = (session[g.faction] or 0) + num(g.amount) end
      if not last[g.faction] or t > last[g.faction] then last[g.faction] = t end
      if t > 0 and (not oldest or t < oldest) then oldest = t end
    end
  end
  for _, g in ipairs(gains) do
    if g.faction and last[g.faction] and dayKey(num(g.t)) == dayKey(last[g.faction]) then day[g.faction] = (day[g.faction] or 0) + num(g.amount) end
  end
  local names = {}
  for name in pairs(snap) do names[name] = true end
  for name in pairs(live) do names[name] = true end
  local rows, gained = {}, 0
  for name in pairs(names) do
    local sr, lr = snap[name] or {}, live[name] or {}
    local st = tonumber(lr.standing) or tonumber(sr.standing) or 0
    local own, lt = last[name], loose[name]
    local uncertain = lt ~= nil and (own == nil or dayKey(lt) > dayKey(own))
    local cut = (not uncertain) and cutDay ~= nil and own ~= nil and dayKey(own) <= cutDay
    local atLeast = cut or (lt ~= nil and own ~= nil and dayKey(lt) == dayKey(own))
    local shown = (not uncertain) and own or nil
    local ses = (num(session[name]) > 0) and session[name] or nil
    local r = { name = name, standing = st, label = STANDINGS[st] or sr.label or _G["FACTION_STANDING_LABEL" .. st] or "Neutral",
      session = ses, sessionAtLeast = (ses and sesCut) or nil, hasGains = own ~= nil, ownLast = own,
      partial = (uncertain or atLeast) or nil, uncertain = uncertain or nil, atLeast = atLeast or nil, cut = cut or nil,
      lastGain = shown, dayGain = shown and day[name] or nil }
    if lr.min and lr.max and lr.value and lr.max > lr.min then r.progress, r.need = lr.value - lr.min, lr.max - lr.min end
    gained = gained + num(r.session)
    rows[#rows + 1] = r
  end
  local function rank(r) if r.lastGain then return 0 end return (r.standing == 4 and not r.hasGains and not r.partial) and 2 or 1 end
  table.sort(rows, function(a, b)
    local ra, rb = rank(a), rank(b)
    if ra ~= rb then return ra < rb end
    if ra == 0 then
      local da, dbk = dayKey(a.lastGain), dayKey(b.lastGain)
      if da ~= dbk then return da > dbk end
      if num(a.dayGain) ~= num(b.dayGain) then return num(a.dayGain) > num(b.dayGain) end
    elseif a.standing ~= b.standing then return a.standing > b.standing end
    return a.name < b.name
  end)
  return rows, { factions = #rows, gained = gained, gainedAtLeast = (sesCut and gained > 0) or nil, since = oldest }
end
-- every reputation gain and every new standing, newest first; `only` limits it to one faction
local function buildRepHistory(only)
  local rows = {}
  for _, g in ipairs(repGains()) do
    if not only or only == g.faction then
      rows[#rows + 1] = { t = num(g.t), faction = g.faction, amount = num(g.amount), change = ("+%s"):format(UI.fmtNum(num(g.amount))), source = g.src or "", zone = g.zone, sub = g.sub, x = g.x, y = g.y }
    end
  end
  for _, e in ipairs(events()) do
    if e.kind == "REP" then
      local nm = (e.text or ""):match("^(.-):%s") or e.text
      if nm and (not only or only == nm) then
        local now = (e.text or ""):match("now%s+(.+)$") or e.standing
        rows[#rows + 1] = { t = num(e.t), faction = nm, change = now and ("Now " .. now) or "New standing", source = "New standing", zone = e.zone, sub = e.sub, x = e.x, y = e.y, milestone = true }
      end
    end
  end
  table.sort(rows, function(a, b) return a.t > b.t end)
  return rows
end

-- professions: the snapshot (name -> rank / max) with the rank it is, the skill-ups this session and the next
-- training. No recipe count: a recipe is learned at a trainer with no profession window open, so the stored recipe
-- rows rarely name their profession (10 of 137 on the save of 21 Nov 2026), and a count from them is wrong.
local skillOf
local RANKS = { { 75, "Apprentice" }, { 150, "Journeyman" }, { 225, "Expert" }, { 300, "Artisan" } }
local NEXT_RANK = { [75] = { "Journeyman", 50 }, [150] = { "Expert", 125 }, [225] = { "Artisan", 200 } }
local function rankName(max) for _, r in ipairs(RANKS) do if max <= r[1] then return r[2] end end return "Artisan" end
-- the training line of a profession, nil when no training is near (rank thresholds 50, 125, 200)
local function trainingLine(name, rank, max)
  local nx = NEXT_RANK[max]
  if not nx then return nil end
  if rank >= nx[2] then return ("%s training is open at any %s trainer"):format(nx[1], name) end
  if rank >= nx[2] - 10 then return ("%s training opens at %d"):format(nx[1], nx[2]) end
  return nil
end
local function buildProfessions()
  local snap = charDB().professions or {}
  local c = charDB()
  local session = {}
  local s = sid()
  for _, e in ipairs(events()) do
    if e.kind == "SKILLUP" and s and e.s == s then local p = skillOf(e); if p then session[p] = (session[p] or 0) + 1 end end
  end
  local rows = {}
  for name, pr in pairs(snap) do
    local rank, max = num(tonumber(pr.rank)), num(tonumber(pr.max))
    rows[#rows + 1] = { name = name, rank = rank, max = max, rankName = rankName(max), session = session[name] or 0, training = trainingLine(name, rank, max) }
  end
  -- a profession a craft or a recipe names that the skill lines do not (not read yet): listed, its rank unknown
  local seen = {}
  for _, r in ipairs(rows) do seen[r.name] = true end
  local named = {}
  for _, l in ipairs({ type(c.crafts) == "table" and c.crafts or {}, type(c.recipes) == "table" and c.recipes or {} }) do
    for _, x in ipairs(l) do if type(x.prof) == "string" and x.prof ~= "" and not seen[x.prof] then named[x.prof] = true end end
  end
  for name in pairs(named) do rows[#rows + 1] = { name = name, rank = -1, max = 0, session = session[name] or 0 } end
  table.sort(rows, function(a, b) if a.rank ~= b.rank then return a.rank > b.rank end return a.name < b.name end)
  return rows, { professions = #rows }
end
-- the profession and rank of a SKILLUP row: its own prof field (crafts), else its text ("Skill up:  Herbalism 7")
function skillOf(e)
  local text = stripPrefix(e.text or "", "Skill up:")
  local nm, rank = text:match("^(.-)%s+(%d+)")
  return e.prof or nm, tonumber(rank)
end
-- CRAFTED (docs/UX_PRAGMATIC.md 3.3): one row per batch, newest first. A batch is the crafts that follow each other
-- in the stored list with the same spell id and session, each at most BATCH_GAP seconds after the one before:
-- { t (the first craft), t1 (the last), item, id, prof, count (items), crafts }. A stored row that is already a
-- batch (merged at write time from 0.9.52, with its own t1) reads the same way.
--   The profession of a batch is the one a stored row of the same spell id names (one spell belongs to one
--   profession; the first craft of a round is often stored without it). A craft whose spell no stored row gives a
--   profession is not a profession craft (an item a quest makes) and is left out, with its items.
--   A list that has reached Market.CRAFT_CAP has lost its oldest rows, so the day its oldest batch stands under is
--   cut: its batches and items are left out and the list starts at the first whole day.
-- The sum says how many items are listed and when they start; it is never the character's whole history.
local BATCH_GAP = 60
local function profOf(v) return (type(v) == "string" and v ~= "") and v or nil end
local function buildCrafts()
  local c = charDB()
  local list = {}
  for _, r in ipairs(type(c.crafts) == "table" and c.crafts or {}) do if type(r) == "table" then list[#list + 1] = r end end
  local full = #list >= ((ns.Market and ns.Market.CRAFT_CAP) or math.huge)
  -- (the list is written in time order; a stable sort keeps the stored order of crafts of one second)
  local ordered = true
  for i = 2, #list do if num(list[i].t) < num(list[i - 1].t) then ordered = false; break end end
  if not ordered then
    for i, r in ipairs(list) do list[i] = { r = r, i = i } end
    table.sort(list, function(a, b) if num(a.r.t) ~= num(b.r.t) then return num(a.r.t) < num(b.r.t) end return a.i < b.i end)
    for i, w in ipairs(list) do list[i] = w.r end
  end
  -- (a row with no spell id is told apart by its item name)
  local function spell(r) if r.id ~= nil then return r.id end return r.item end
  local profBy = {}
  for _, r in ipairs(list) do
    local k, prof = spell(r), profOf(r.prof)
    if k ~= nil and prof and not profBy[k] then profBy[k] = prof end
  end
  local all, last = {}, nil
  for _, r in ipairs(list) do
    local t, n, k = num(r.t), (num(r.count) > 0 and r.count or 1), spell(r)
    local t1 = math.max(t, num(r.t1))
    if last and k ~= nil and last.key == k and last.item == r.item and last.s == r.s and t - last.t1 <= BATCH_GAP then
      last.count, last.t1, last.crafts = last.count + n, t1, last.crafts + 1
    else
      last = { t = t, t1 = t1, item = r.item, id = r.id, key = k, prof = k ~= nil and profBy[k] or nil, s = r.s, count = n, crafts = 1 }
      all[#all + 1] = last
    end
  end
  local cut = (full and all[1]) and dayKey(all[1].t1) or nil
  local batches, items, since = {}, 0, nil
  for _, b in ipairs(all) do
    if b.prof and dayKey(b.t1) ~= cut then
      batches[#batches + 1] = b
      items = items + b.count
      if b.t > 0 and (not since or b.t < since) then since = b.t end
    end
  end
  local out = {}
  for i = #batches, 1, -1 do out[#out + 1] = batches[i] end
  return out, { batches = #batches, items = items, since = since }
end

-- day rows over a newest-first list (a "TODAY · 3 QUESTS" row whenever the date changes). `tkey`: the row's time
-- (default "t"); `nkey`: the row field the day row adds up (default: it counts the rows).
local function withDays(rows, word, tkey, nkey)
  tkey = tkey or "t"
  local out, lastDay, head = {}, nil, nil
  for _, r in ipairs(rows) do
    local t = num(r[tkey])
    local day = t > 0 and date("%Y-%m-%d", t) or "?"
    if day ~= lastDay then
      lastDay = day
      head = { ebSection = "", n = 0, t = t }
      out[#out + 1] = head
    end
    head.n = head.n + (nkey and num(r[nkey]) or 1)
    out[#out + 1] = r
  end
  for _, r in ipairs(out) do
    if r.ebSection then r.ebSection = (r.t > 0 and UI.fmtDay(r.t) or "EARLIER") .. " \194\183 " .. UI.plural(r.n, word) end
  end
  return out
end

-- ══ view ═══════════════════════════════════════════════════════════════════════════════════════════════════════
UI.registerHost(2, "Character", "Your level, your standing, and your skills.")
local V = {}           -- the three pages, built on first select
ns.Progress = V

-- a kit table with its section header and inline empty line, placed on a page
local function block(col, label, spec, opts)
  local b = { head = UI.Section(col, label) }
  b.tbl = UI.KitTable(col, spec, opts or {})
  return b
end
local COORDS = { key = "coords", label = "Coords", kind = "num", min = 72, measure = { "100.0, 100.0" }, wide = true }
local function relayout(tbl) tbl.relayout(G.mainW(G.winW())) end

-- ── Leveling ── (docs/UX_PRAGMATIC.md 3.1)
-- At the level cap the page is short: the level, when and where it was reached, the played time, and the levels
-- that have a recorded moment. A leveling character has the time to the next level with the XP bar, the cards
-- PLAYED and TIME AT LEVEL, the same Levels table and the quests turned in.
-- "Fri 20 Nov, 22:49": a fixed moment in a table cell (never "Yesterday": the row is read days later too)
local function fmtReached(t, now)
  if date("%Y", t) == date("%Y", now) then return UI.fmtSince(t, now) .. ", " .. UI.fmtClock(t) end
  return UI.fmtStamp(t, now)
end
-- a level known only between two stored moments: "Tue 17 Nov" within one day, "18 to 19 Nov" over days
local function fmtBound(from, to, now)
  if date("%Y%m%d", from) == date("%Y%m%d", to) then return UI.fmtSince(from, now) end
  local d0, d1 = tostring(tonumber(date("%d", from))), tostring(tonumber(date("%d", to)))
  local year = date("%Y", to) ~= date("%Y", now) and date(" %Y", to) or ""
  if date("%Y%m", from) == date("%Y%m", to) then return d0 .. " to " .. d1 .. date(" %b", to) .. year end
  return d0 .. date(" %b", from) .. (date("%Y", from) ~= date("%Y", to) and date(" %Y", from) or "") .. " to " .. d1 .. date(" %b", to) .. year
end
local function boundTip(from, to, now)
  if date("%Y%m%d", from) == date("%Y%m%d", to) then return ("Between %s and %s"):format(UI.fmtClock(from), UI.fmtClock(to)) end
  return ("Between %s and %s"):format(UI.fmtStamp(from, now), UI.fmtStamp(to, now))
end
V.fmtBound, V.boundTip = fmtBound, boundTip
local function levelText(r) return (r.lo and r.lo < r.level) and ("%d to %d"):format(r.lo, r.level) or tostring(r.level) end
local function buildLeveling(content)
  local v = { content = content }
  V.leveling = v
  v.pg = UI.Page(content)
  local col = v.pg.col
  v.hero = UI.Hero(col, {})
  v.cards = UI.StatRow(col, 2)
  v.levels = block(col, "Levels", {
    { key = "level", label = "Level", kind = "num", min = 48, measure = { "50 to 59" } },
    { key = "reached", label = "Reached", kind = "tag", min = 136, measure = { "Wed 28 Nov, 23:59", "28 Sep to 28 Nov" } },
    { key = "zone", label = "Zone", flex = 1, min = 120 },
  }, { tooltip = function(row, item, tip)
      local now = nowT()
      if item.t then
        tip:AddLine(("Level %d"):format(item.level), 1, 1, 1)
        tip:AddLine("Reached " .. UI.fmtStamp(item.t, now) .. (item.zone and (" in " .. item.zone) or ""), 0.78, 0.79, 0.80, true)
      else
        tip:AddLine((item.lo < item.level and "Levels " or "Level ") .. levelText(item), 1, 1, 1)
        tip:AddLine(boundTip(item.from, item.to, now), 0.78, 0.79, 0.80, true)
        tip:AddLine("The level-up itself is not stored any more; a session before it and one after it are.", 0.78, 0.79, 0.80, true)
      end
    end })
  -- (the one muted line of the screen about what is not stored, 0.2.2)
  v.levelNote = UI.EmptyLine(col)
  v.quests = block(col, "Quests", {
    { key = "when", label = "When", kind = "tag", min = 40, measure = { "23:59" } },
    { key = "name", label = "Quest", flex = 1, min = 120 },
    { key = "place", label = "Place", kind = "tag", min = 140, max = 160 },
    { key = "gold", label = "Gold", kind = "money", min = 72 },
    COORDS,
  }, { tooltip = function(row, item, tip)
      tip:AddLine(item.name or "Quest", 1, 1, 1)
      if item.unnamed then tip:AddLine("The game did not give the quest name when you turned it in.", 0.78, 0.79, 0.80, true) end
      tip:AddLine(UI.fmtWhen(item.t), 0.78, 0.79, 0.80)
      if item.gold then tip:AddDoubleLine("Gold", ns.fmtMoney(item.gold, { icons = true }), C.fgMuted[1], C.fgMuted[2], C.fgMuted[3], 1, 1, 1)
      else tip:AddLine("Gold: Not recorded", 0.78, 0.79, 0.80, true) end
    end })
  UI.SetTip(v.hero, function(tip) if v.heroTip then v.heroTip(tip) end end)
  content:HookScript("OnSizeChanged", function() pcall(V.placeLeveling) end)
  V.renderLeveling()
end
function V.placeLeveling()
  local v = V.leveling; if not v then return end
  local items = { { v.hero, H.HERO, gap = v.cardsShown and S.S3 or S.S5 } }
  if v.cardsShown then items[#items + 1] = { v.cards, H.STAT, gap = S.S5 } end
  if v.levelsShown then
    items[#items + 1] = { v.levels.head, H.SECTION }
    items[#items + 1] = { v.levels.tbl.frame, v.levels.tbl.height, gap = v.noteShown and 0 or S.S5 }
  end
  if v.noteShown then items[#items + 1] = { v.levelNote, H.SECTION, gap = S.S5 } end
  if v.questsShown then
    items[#items + 1] = { v.quests.head, H.SECTION }
    items[#items + 1] = { v.quests.tbl.frame, v.quests.tbl.height }
  end
  v.pg.place(items)
  pcall(v.cards.layout); pcall(v.hero.layout)
end
function V.renderLeveling()
  local v = V.leveling; if not v then return end
  local now = nowT()
  local db = charDB()
  local lvl = plain(call(UnitLevel, "player")) or 0
  local maxLvl = plain(call(GetMaxPlayerLevel)) or 60
  local atMax = lvl >= maxLvl
  local cur, mx = plain(call(UnitXP, "player")), plain(call(UnitXPMax, "player"))
  if not (cur and mx) then local x = type(db.xp) == "table" and db.xp or {}; cur, mx = num(x.cur), num(x.max) end
  local rested = plain(call(GetXPExhaustion)) or 0
  local pace = ns.Pace and ns.Pace.compute(now) or {}
  local remaining = (not atMax and ns.Pace) and ns.Pace.remaining(cur, mx, pace.rate) or nil
  local levels, missing = buildLevels(lvl)
  local atLevel = timeAtLevel(now)
  local played = playedTotal(now)
  v.atLevel, v.remaining, v.pace, v.atMax = atLevel, remaining, pace, atMax
  v.levelRows, v.levelsMissing = levels, missing
  local hero = v.hero
  hero:SetKicker(nil); hero:SetTitleMeta(nil)
  -- (the title line is who this is: the full name, else the class; the level is said once, as the hero)
  local classN = plainStr((call(UnitClass, "player")))
  hero:SetTitle((ns.fullName and ns.fullName()) or classN or "")
  if atMax then
    -- the level once, when and where it was reached (left out unless its exact moment is stored), and the played time
    local top = levels[1] and levels[1].level == lvl and levels[1].t and levels[1] or nil
    hero:SetHero("Level " .. lvl)
    v.reachedLine = top and ("Reached " .. UI.fmtStamp(top.t, now) .. (top.zone and (" in " .. top.zone) or "")) or nil
    local pl = {}
    if played then pl[#pl + 1] = UI.fmtDur(played, { minutes = true }) .. " played" end
    if atLevel then pl[#pl + 1] = UI.fmtDur(atLevel, { minutes = true }) .. " at " .. lvl end
    v.playedLine = #pl > 0 and table.concat(pl, ", ") or nil
    hero:SetBar(nil)
    -- (two lines when both are known; one known line sits right under the level)
    hero:SetMeta(v.reachedLine or v.playedLine or "", nil)
    hero:SetMeta2(v.reachedLine and v.playedLine or nil)
    v.verdict = nil
  else
    v.reachedLine, v.playedLine = nil, nil
    hero:SetMeta2(nil)
    local pct = mx > 0 and math.floor(cur / mx * 100) or 0
    local left = ("XP %s / %s \194\183 %d%%"):format(UI.fmtNum(cur), UI.fmtNum(mx), pct)
    if rested > 0 then left = left .. " \194\183 rested " .. UI.fmtNum(rested) end
    if remaining then
      v.verdict = UI.fmtDur(remaining, { minutes = true }) .. " to level " .. (lvl + 1)
      hero:SetHero(v.verdict, "fg")
      hero:SetMeta(left, pace.rate and ("at " .. UI.fmtNum(pace.rate) .. " XP per hour") or nil)
    else
      v.verdict = "Level " .. lvl
      hero:SetHero(v.verdict, "fg")
      hero:SetMeta(left, "Pace shows after 10 minutes of play")
    end
    hero:SetBar(mx > 0 and cur / mx or 0, (mx > 0 and rested > 0) and math.min(1, (cur + rested) / mx) or nil)
  end
  v.heroTip = function(tip)
    tip:AddLine("Level " .. lvl, 1, 1, 1)
    if atMax then
      tip:AddLine("Played time is the game's own /played, plus the time since it last answered in this login.", 0.78, 0.79, 0.80, true)
    else
      tip:AddLine("The time left at your XP per hour over the last 30 minutes of active play.", 0.78, 0.79, 0.80, true)
      if pace.rate then tip:AddDoubleLine("XP per hour", UI.fmtNum(pace.rate), C.fgMuted[1], C.fgMuted[2], C.fgMuted[3], 1, 1, 1) end
    end
  end

  -- the cards: none at the level cap (the hero has the played time); PLAYED and TIME AT LEVEL while leveling, each
  -- only once the game has answered /played
  local cards = v.cards.cards
  v.cardsShown = false
  if not atMax and (played or atLevel) then
    v.cardsShown = true
    if played then cards[1]:Set("Played", UI.fmtDur(played, { minutes = true }), "on this character")
    else cards[1]:Set("Played", "Not known yet", "") end
    if atLevel then cards[2]:Set("Time at level " .. lvl, UI.fmtDur(atLevel, { minutes = true }), "so far")
    else cards[2]:Set("Time at level " .. lvl, "Not known yet", "") end
    UI.SetTip(cards[1], { title = "Played", text = "Played time on this character, from the game's /played." })
    UI.SetTip(cards[2], { title = "Time at level " .. lvl, text = "Played time at this level, from the game's /played." })
    v.cards:Show()
  else v.cards:Hide() end

  -- LEVELS: the levels with a recorded moment, and the levels known between two stored moments; one muted line
  -- counts the rest
  v.levelsShown = #levels > 0
  if v.levelsShown then
    v.levels.head:Show(); v.levels.tbl.frame:Show()
    v.levels.tbl.setRows(levels, function(row, r)
      row.c.level:SetText(levelText(r))
      row.c.reached:SetText(r.t and fmtReached(r.t, now) or fmtBound(r.from, r.to, now))
      row.c.zone:SetText(r.zone or "")
    end)
  else v.levels.head:Hide(); v.levels.tbl.frame:Hide() end
  v.noteShown = missing > 0
  v.noteText = v.noteShown and (missing == 1 and "1 level has no recorded date." or ("%d levels have no recorded date."):format(missing)) or nil
  if v.noteShown then
    v.levelNote:Set(v.noteText); v.levelNote:Show()
    UI.SetTip(v.levelNote, { title = "Not recorded", text = "A level is listed when its level-up, or a session before and after it, is still stored." })
  else v.levelNote:Hide() end

  -- QUESTS: a leveling character's list, named after where it starts (the list is capped: never "all time")
  local quests = atMax and {} or (buildQuests())
  v.questsShown = #quests > 0
  v.questRows = quests
  if v.questsShown then
    local first
    for _, q in ipairs(quests) do if q.t > 0 and (not first or q.t < first) then first = q.t end end
    v.questLabel = "Quests" .. (first and (" since " .. UI.fmtSince(first, now)) or "")
    v.quests.head:SetLabel(v.questLabel)
    v.quests.head:SetMeta(nil)
    v.quests.head:Show(); v.quests.tbl.frame:Show()
    v.quests.tbl.setRows(withDays(quests, "quest"), function(row, r)
      row.c.when:SetText(UI.fmtClock(r.t))
      row.c.name:SetText(r.name or "")
      if r.unnamed then row.c.name:SetTextColor(C.fgMuted[1], C.fgMuted[2], C.fgMuted[3]) end
      row.c.place:SetText(UI.fmtPlace(r.zone, r.sub))
      row.c.gold:SetText(r.gold and UI.money(r.gold) or "")
      row.c.coords:SetText(UI.fmtCoords(r.x, r.y))
    end)
  else v.questLabel = nil; v.quests.head:Hide(); v.quests.tbl.frame:Hide() end
  V.placeLeveling()
end

-- ── Reputation ── (docs/UX_PRAGMATIC.md 3.2)
-- The answer is the first row: what that faction gained on the last day it gained. The list: Faction, Standing,
-- Progress (the bar and what is left to the next standing), Last day gained (the sum of the faction's gains on the
-- day of its newest stored gain, and that day; "at least" before the sum when a stored gain of that day names no
-- character; "Not certain", muted, when such a gain lies on a later day; blank only with no stored gain at all)
-- and This session (only while a faction gained this session). A faction with stored gains opens them.
-- The bar is 120 px wherever the row has the room. In a narrow window it gives way before a faction name is cut:
-- it shrinks to what is left, and under 40 px it is left out (what is left to the next standing is the text).
local REP_BAR, REP_BAR_MIN = 120, 40
-- "16,072 to Exalted": what is left in the standing, nil when the client has not answered or there is no next one
local function repLeft(r)
  if not r.need or r.standing >= #STANDINGS then return nil end
  return ("%s to %s"):format(UI.fmtNum(math.max(0, r.need - r.progress)), STANDINGS[r.standing + 1] or "the next standing")
end
-- "+1,005 · Yesterday", "at least +50 · Yesterday" (a lower bound), "Not certain", "" (no stored gain at all)
local REP_UNCERTAIN = "Not certain"
local function repSum(r) return (r.atLeast and "at least +" or "+") .. UI.fmtNum(num(r.dayGain)) end
-- "+75", "at least +75" (the full list starts inside this session), nil when the faction gained nothing this session
local function repSession(r)
  if not r.session then return nil end
  return (r.sessionAtLeast and "at least +" or "+") .. UI.fmtNum(r.session)
end
V.REP_CUT = "The list of stored gains is full and has dropped its oldest ones"
local function repLast(r, now)
  if r.lastGain then return ("%s \194\183 %s"):format(repSum(r), UI.fmtDate(r.lastGain, now)) end
  return r.uncertain and REP_UNCERTAIN or ""
end
-- the lines of the row hover about the last day gained ("Not recorded" only with no stored gain of the faction)
function V.repLastTip(r)
  if r.lastGain and not r.atLeast then
    return { ("+%s in all on that day. Newest gain %s."):format(UI.fmtNum(num(r.dayGain)), UI.fmtStamp(r.lastGain)) }
  end
  if r.lastGain and r.cut then
    return { ("Newest gain of this character: %s."):format(UI.fmtStamp(r.ownLast)),
      ("%s, some of that day among them, so the day's total cannot be said: it is at least +%s."):format(V.REP_CUT, UI.fmtNum(num(r.dayGain))) }
  end
  if r.lastGain then
    return { ("Newest gain of this character: %s."):format(UI.fmtStamp(r.ownLast)),
      ("Some stored gains of this faction on that day name no character, so the day's total cannot be said: it is at least +%s."):format(UI.fmtNum(num(r.dayGain))) }
  end
  if r.ownLast then
    return { ("Newest gain of this character: %s."):format(UI.fmtStamp(r.ownLast)),
      "A stored gain of this faction on a later day names no character, so the last day it gained cannot be said." }
  end
  if r.uncertain then return { "The stored gains of this faction name no character, so it cannot be said whether they are this character's." } end
  return { "Last day gained: Not recorded" }
end
local function buildRep(content)
  local v = { content = content }
  V.rep = v
  local list = CreateFrame("Frame", nil, content); list:SetAllPoints(content)
  v.list = list
  v.pg = UI.Page(list)
  local col = v.pg.col
  v.summary = UI.Summary(col)
  UI.SetTip(v.summary, { title = "Last day gained", text = "The first row of the list: the newest day with a counted reputation gain, and the faction with the largest counted gain that day. The number is the sum of its counted gains that day." })
  v.head = UI.Section(col, "Factions")
  v.spec = {
    -- (min: the longest shown name, set at every render, so a long name is whole wherever the window has the room)
    name = { key = "name", label = "Faction", flex = 1, min = 140 },
    standing = { key = "standing", label = "Standing", kind = "tag", min = 88, measure = STANDINGS },
    -- (PROGRESS heads both: the bar at the column's left, S2, then what is left, left-aligned under the header)
    -- (min: the bar and the widest text of the rows shown, set by V.fitRep)
    prog = { key = "prog", label = "Progress", kind = "tag", justify = "LEFT", lead = REP_BAR + S.S2, min = REP_BAR + S.S2,
      tip = "What is left to the next standing. The numbers come from the game while you are logged in." },
    last = { key = "last", label = "Last day gained", kind = "tag", min = 96, justify = "RIGHT", measure = { "+10,005 \194\183 Wed 28 Nov" },
      tip = "The sum of the faction's gains on the last day it gained, and that day. \"At least\" when a stored gain of that day names no character, or when the list of stored gains is full and has dropped gains of that day. \"Not certain\" when such a gain lies on a later day. Blank with no stored gain." },
    ses = { key = "ses", label = "This session", kind = "num", min = 88, hide = true,
      tip = "What the faction gained this session. \"At least\" when the list of stored gains is full and has dropped gains of this session." },
  }
  v.tbl = UI.KitTable(col, { v.spec.name, v.spec.standing, v.spec.prog, v.spec.last, v.spec.ses },
    { onClick = function(row) if row.item and row.item.hasGains then V.openFaction(row.item) end end,
    onLayout = function(t) for i = 1, t.shownN do pcall(V.placeRepBar, t.rows[i]) end end,
    tooltip = function(row, item, tip)
      tip:AddLine(item.name, 1, 1, 1)
      if item.need then tip:AddDoubleLine(item.label, ("%s / %s"):format(UI.fmtNum(item.progress), UI.fmtNum(item.need)), C.fgMuted[1], C.fgMuted[2], C.fgMuted[3], 1, 1, 1) end
      for _, line in ipairs(V.repLastTip(item)) do tip:AddLine(line, 0.78, 0.79, 0.80, true) end
      if item.hasGains then tip:AddLine("Opens the stored gains.", 0.78, 0.79, 0.80, true) end
    end })
  v.detail = UI.Detail(content, { list = list, back = "\226\128\185 Reputation", render = function(item, child, d) V.renderFaction(item, child) end,
    onBack = function(item) if v.tbl.setSelected then v.tbl.setSelected(nil) end end })
  content:HookScript("OnSizeChanged", function() pcall(V.placeRep) end)
  V.renderRep()
end
function V.placeRep()
  local v = V.rep; if not v then return end
  local items = {}
  if v.summaryShown then items[#items + 1] = { v.summary, H.SUMMARY, gap = S.S3 } end
  items[#items + 1] = { v.head, H.SECTION }
  items[#items + 1] = { v.tbl.frame, v.tbl.height }
  v.pg.place(items)
  V.fitRep()
end
-- The widths of the list for the rows shown and the window: the Faction column asks for its longest name, the
-- Progress column for the bar and its widest text. When the table is too narrow for that, the bar gives the
-- missing width (down to REP_BAR_MIN, then it is left out), so a name is cut only when even that is not enough.
function V.fitRep()
  local v = V.rep
  local tbl = v and v.tbl
  if not (tbl and tbl.width and v.nameW) then return end
  local function apply(bar)
    v.barW = bar
    v.spec.name.min = v.nameW
    -- (`lead`: where the cell's text starts inside its column, after the bar)
    v.spec.prog.lead = bar > 0 and (bar + S.S2) or 0
    v.spec.prog.min = v.spec.prog.lead + (v.progW or 0)
    tbl.remeasure()
  end
  apply(REP_BAR)
  local c = tbl.cols
  if not (c.prog and c.name) then return end
  local right = 0
  for _, cw in pairs(c) do right = math.max(right, cw.x + cw.w) end
  local short = math.max(0, v.nameW - c.name.w) + math.max(0, right + S.S3 - tbl.width)
  if short > 0 then
    local bar = REP_BAR - math.ceil(short)
    apply(bar >= REP_BAR_MIN and bar or 0)
  end
end
function V.renderRep()
  local v = V.rep; if not v then return end
  local now = nowT()
  local rows, sum = buildReputation()
  v.rows = rows
  -- the answer: the first row of the list when it shows a gain (left out when none does). The number is a day's
  -- sum, so the line names the day and never calls it one gain: "Barkskin Burrow +1,005 yesterday".
  local top = rows[1] and rows[1].lastGain and rows[1] or nil
  v.summaryShown = top ~= nil
  if top then
    local day = UI.fmtDate(top.lastGain, now)
    if day == "Today" or day == "Yesterday" then day = day:lower() else day = "on " .. day end
    v.answer = ("%s %s %s"):format(top.name, repSum(top), day)
    v.summary:SetSegments({ { text = ("**%s %s** %s"):format(top.name, repSum(top), day) } })
    v.summary:Show()
  else v.answer = nil; v.summary:SetSegments({}); v.summary:Hide() end
  v.head:SetMeta(#rows > 0 and UI.plural(#rows, "faction") or nil)
  -- (rule 0.3: a column with no value in any row is left out. Progress is a live read; This session is a column
  -- only while a faction gained this session)
  local anyProg, anySes, anyLast = false, false, false
  for _, r in ipairs(rows) do
    if r.need or r.standing >= #STANDINGS then anyProg = true end
    if r.session then anySes = true end
    if r.lastGain or r.uncertain then anyLast = true end
  end
  -- (the widths the rows shown need: the longest name, and the bar with the widest Progress text)
  local nameW, progW = 140, 0
  for _, r in ipairs(rows) do
    nameW = math.max(nameW, math.ceil(UI.TextWidth("BODY", r.name)))
    if anyProg then progW = math.max(progW, math.ceil(UI.TextWidth("BODY", (r.standing >= #STANDINGS and r.label) or repLeft(r) or "Not known yet"))) end
  end
  v.nameW, v.progW = nameW, progW
  local changed = false
  for key, hide in pairs({ prog = not anyProg, ses = not anySes, last = not anyLast }) do
    if (v.spec[key].hide or false) ~= hide then v.spec[key].hide = hide; changed = true end
  end
  if changed then relayout(v.tbl) end
  v.tbl.setRows(rows, function(row, r)
    row.c.name:SetText(r.name)
    local bad = r.standing == 1 or r.standing == 2
    row.c.standing:SetText((bad and UI.dot("bad") or "") .. r.label)
    -- (a Neutral faction with no stored gain is the quiet end of the list)
    local quiet = r.standing == 4 and not r.hasGains and not r.partial
    local col = bad and C.bad or C.fgSubtle
    row.c.standing:SetTextColor(col[1], col[2], col[3])
    if quiet then UI.SetColor(row.c.name, "fgMuted"); UI.SetColor(row.c.standing, "fgMuted") end
    if not row.bar then row.bar = UI.Bar(row, REP_BAR) end
    local left = repLeft(r)
    if r.standing >= #STANDINGS then row.ebFrac = 1; row.c.prog:SetText(r.label)
    elseif left then row.ebFrac = r.progress / r.need; row.c.prog:SetText(left)
    -- (the client has not answered for this faction: no track, an empty one reads as no progress, and the one phrase
    -- for it, muted, where the other rows have their text)
    else row.ebFrac = nil; row.c.prog:SetText("Not known yet"); UI.SetColor(row.c.prog, "fgMuted") end
    V.placeRepBar(row)
    row.c.last:SetText(repLast(r, now))
    if not r.lastGain then UI.SetColor(row.c.last, "fgMuted") end
    row.c.ses:SetText(repSession(r) or "")
    -- (only a faction with stored gains opens)
    row.ebNoOpen = not r.hasGains
  end)
  if #rows == 0 then v.tbl.setState("No faction met yet.") end
  V.placeRep()
end
-- the progress bar sits at the left of the Progress column, what is left after it; no bar while the column is out,
-- on a row the client has not answered for, or when V.fitRep found no room for one
function V.placeRepBar(row)
  local cw = V.rep and V.rep.tbl.cols.prog
  if not (row and row.bar) then return end
  if not cw then row.bar:Hide(); return end
  local bar = V.rep.barW or REP_BAR
  local lead = bar > 0 and (bar + S.S2) or 0
  if bar > 0 and row.ebFrac then
    row.bar:ClearAllPoints(); row.bar:SetPoint("LEFT", row, "LEFT", cw.x, 0)
    row.bar:SetSize(bar, 6); row.bar:SetFrac(row.ebFrac)
  else row.bar:Hide() end
  local fs = row.c and row.c.prog
  if fs then
    fs:ClearAllPoints(); fs:SetPoint("LEFT", row, "LEFT", cw.x + lead, 0)
    fs:SetWidth(math.max(1, cw.w - lead)); fs:SetJustifyH("LEFT")
  end
end
function V.openFaction(item)
  local v = V.rep; if not v then return end
  -- (Older and Newer step through the factions that open: the ones with stored gains)
  local open, idx = {}, 1
  for _, r in ipairs(v.rows or {}) do
    if r.hasGains then open[#open + 1] = r; if r.name == item.name then idx = #open end end
  end
  if v.tbl.setSelected then v.tbl.setSelected(item) end
  v.detail:Open(open, idx)
end
V.FACTION = {}
function V.renderFaction(item, child)
  local f = V.FACTION
  if not f.title then
    f.col = CreateFrame("Frame", nil, child); f.col:SetPoint("TOPLEFT", child, "TOPLEFT", 0, 0)
    f.title = UI.Text(f.col, "TITLE", "fg"); f.title:SetPoint("TOPLEFT", f.col, "TOPLEFT", S.S3, 0)
    f.meta = UI.Text(f.col, "META", "fgMuted"); f.meta:SetPoint("TOPLEFT", f.col, "TOPLEFT", S.S3, -22)
    f.head = UI.Section(f.col, "Gains")
    f.spec = {
      { key = "when", label = "When", kind = "tag", min = 96, measure = { "Mon 16 Nov, 23:59" } },
      { key = "source", label = "Source", flex = 1, min = 120 },
      { key = "amount", label = "Amount", kind = "num", min = 88, measure = { "Now Unfriendly" } },
    }
    f.tbl = UI.KitTable(f.col, f.spec, { tooltip = function(row, h, tip)
        tip:AddLine(h.change, 1, 1, 1)
        tip:AddLine(UI.fmtWhen(h.t), 0.78, 0.79, 0.80)
        if h.source == "" then tip:AddLine("Source: Not recorded", 0.78, 0.79, 0.80, true) end
      end })
  end
  local w = G.mainW(G.winW())
  f.col:SetWidth(w)
  f.title:SetText(item.name); f.title:SetWidth(w - 2 * S.S3)
  local parts = { (item.standing == 1 or item.standing == 2) and (UI.dot("bad") .. item.label) or item.label }
  local left = repLeft(item)
  if left then parts[#parts + 1] = left end
  if item.session then parts[#parts + 1] = repSession(item) .. " this session" end
  f.meta:SetText(table.concat(parts, " \194\183 ")); f.meta:SetWidth(w - 2 * S.S3)
  local hist = buildRepHistory(item.name)
  -- the list is capped: its header says where this faction's stored gains start, and how much they add up to
  local first, total, named = nil, 0, 0
  for _, h in ipairs(hist) do
    if h.t > 0 and (not first or h.t < first) then first = h.t end
    total = total + num(h.amount)
    if h.source ~= "" then named = named + 1 end
  end
  -- (a stored gain of the faction that names no character, on the first listed day or later, could belong in this
  -- list: then neither a start nor a sum is said, the header is "GAINS" alone. The same when the list is full and
  -- the first listed day is the day of its first row or an earlier one: gains of that day were dropped, Rep.cut)
  local _, loose = repGains()
  local lt = loose[item.name]
  local _, cutDay = Rep.cut()
  f.cut = (cutDay ~= nil and first ~= nil and dayKey(first) <= cutDay) or nil
  f.partial = (f.cut or (lt ~= nil and (first == nil or dayKey(lt) >= dayKey(first)))) or nil
  f.label = "Gains" .. ((first and not f.partial) and (" since " .. UI.fmtSince(first)) or "")
  f.head:SetLabel(f.label)
  f.head:SetMeta((total > 0 and not f.partial) and ("+" .. UI.fmtNum(total)) or nil)
  -- (rule 0.3: Source is a column only while a third of the rows name one)
  local hide = named * 3 < #hist
  if (f.spec[2].hide or false) ~= hide then f.spec[2].hide = hide; f.tbl.relayout(w) end
  f.tbl.setRows(hist, function(row, h)
    row.c.when:SetText(UI.fmtWhen(h.t))
    row.c.source:SetText(h.source)
    row.c.amount:SetText(h.change)
  end)
  if #hist == 0 then f.tbl.setState("No gain recorded.") end
  f.head:ClearAllPoints(); f.head:SetPoint("TOPLEFT", f.col, "TOPLEFT", 0, -(22 + UI.LINE_H.META + S.S5)); f.head:SetWidth(w)
  local y = 22 + UI.LINE_H.META + S.S5 + H.SECTION
  f.tbl.frame:ClearAllPoints(); f.tbl.frame:SetPoint("TOPLEFT", f.col, "TOPLEFT", 0, -y); f.tbl.frame:SetWidth(w)
  y = y + (f.tbl.height or 0) + S.S4
  f.col:SetHeight(y)
  V.rep.detail.sf:SetContentHeight(y)
  f.hist = hist
end

-- ── Professions ── (docs/UX_PRAGMATIC.md 3.3)
-- The skills with their bar, then what was crafted, one row per batch. No headline, no recipe count and no recipe
-- list: the stored recipe rows rarely name their profession.
local PROF_ICON = {
  Alchemy = "Interface\\Icons\\Trade_Alchemy", Blacksmithing = "Interface\\Icons\\Trade_BlackSmithing",
  Enchanting = "Interface\\Icons\\Trade_Engraving", Engineering = "Interface\\Icons\\Trade_Engineering",
  Herbalism = "Interface\\Icons\\Trade_Herbalism", Leatherworking = "Interface\\Icons\\Trade_LeatherWorking",
  Mining = "Interface\\Icons\\Trade_Mining", Skinning = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01",
  Tailoring = "Interface\\Icons\\Trade_Tailoring", Cooking = "Interface\\Icons\\INV_Misc_Food_15",
  ["First Aid"] = "Interface\\Icons\\Spell_Holy_SealOfSacrifice", Fishing = "Interface\\Icons\\Trade_Fishing",
}
UI.PROF_ICON = PROF_ICON
-- an item or recipe name as the game gives it (a link "|cff..|Hitem:2318|h[Light Leather]|h|r", or "[Light Leather]")
-- as its plain name, no colour code and no brackets
function V.unbracket(s)
  if type(s) ~= "string" then return nil end
  s = s:match("|h%[(.-)%]|h") or s
  s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  return (s:gsub("^%[(.*)%]$", "%1"))
end
V.BAR_X, V.BAR_W = 320, 160
local function profRow(v, i)
  local r = v.profRows[i]
  if r then return r end
  r = UI.Row2(v.pg.col)
  r.bar = UI.Bar(r, V.BAR_W)
  r.count = UI.Text(r, "BODY_STRONG", "fg", { justify = "RIGHT" })
  r.train = UI.Text(r, "META", "fgSubtle")
  v.profRows[i] = r
  return r
end
-- the value "5 / 75" right-aligned at w - 12; the bar's right edge S3 left of the value; the title and the meta run
-- to S3 left of the bar (the bar at most V.BAR_W wide, never left of V.BAR_X)
local function placeProfRow(r)
  local w = tonumber(r:GetWidth()) or 0
  local cw = math.max(UI.TextWidth("BODY_STRONG", "300 / 300"), UI.TextWidth("BODY_STRONG", r.count:GetText() or ""))
  -- (the bar and its value are centred in the 48 px row; with a training line under them they sit on the title's line)
  local train = (r.train:GetText() or "") ~= ""
  local rowH = tonumber(r:GetHeight()) or H.ROW2
  local cy = train and (S.S2 + UI.LINE_H.BODY_STRONG / 2) or (rowH / 2)
  r.count:ClearAllPoints(); r.count:SetPoint("RIGHT", r, "TOPRIGHT", -S.S3, -cy); r.count:SetWidth(math.max(1, cw))
  local barR = w - S.S3 - cw - S.S3
  local barL = math.max(V.BAR_X, barR - V.BAR_W)
  r.bar:ClearAllPoints(); r.bar:SetPoint("LEFT", r, "TOPLEFT", barL, -cy)
  r.bar:SetSize(math.max(1, barR - barL), 6); r.bar:SetFrac(r.frac)
  -- (no track while the skill is not known: an empty track reads as skill 0)
  if r.unknown then r.bar:Hide() else r.bar:Show() end
  local textX = S.S3 + 24 + S.S2
  local room = math.max(1, barL - S.S3 - textX)
  r.meta:SetWidth(room)
  r.title:SetWidth(math.max(1, math.min(UI.TextWidth("ROW_TITLE", r.title:GetText()), room)))
  r.train:ClearAllPoints(); r.train:SetPoint("TOPLEFT", r, "TOPLEFT", barL, -26); r.train:SetWidth(math.max(1, w - barL - S.S3))
end
-- "23:46 to 23:48", or the one minute
local function batchWhen(r)
  local a, b = UI.fmtClock(r.t), UI.fmtClock(r.t1)
  return a == b and a or (a .. " to " .. b)
end
local function buildProf(content)
  local v = { content = content, profRows = {} }
  V.prof = v
  v.pg = UI.Page(content)
  local col = v.pg.col
  v.head = UI.Section(col, "Professions")
  v.empty = UI.EmptyLine(col)
  v.spec = {
    { key = "when", label = "When", kind = "tag", min = 40, measure = { "23:59 to 23:59" } },
    { key = "item", label = "Item", flex = 1, min = 120 },
    { key = "prof", label = "Profession", kind = "tag", min = 104, max = 160 },
  }
  v.crafted = block(col, "Crafted", v.spec, { tooltip = function(row, item, tip)
      tip:AddLine(V.unbracket(item.item) or "Crafted item", 1, 1, 1)
      local when = UI.fmtWhen(item.t) .. (UI.fmtClock(item.t) ~= UI.fmtClock(item.t1) and (" to " .. UI.fmtClock(item.t1)) or "")
      tip:AddLine(when, 0.78, 0.79, 0.80)
      if item.crafts > 1 then tip:AddLine(("%s made in %s, one after the other."):format(UI.plural(item.count, "item"), UI.plural(item.crafts, "craft")), 0.78, 0.79, 0.80, true) end
    end })
  content:HookScript("OnSizeChanged", function() pcall(V.placeProf) end)
  V.renderProf()
end
function V.placeProf()
  local v = V.prof; if not v then return end
  local list = { { v.head, H.SECTION } }
  for _, r in ipairs(v.profRows) do if r:IsShown() then list[#list + 1] = { r, H.ROW2 } end end
  if v.empty:IsShown() then list[#list + 1] = { v.empty, H.SECTION } end
  list[#list].gap = S.S5
  if v.craftedShown then
    list[#list + 1] = { v.crafted.head, H.SECTION }; list[#list + 1] = { v.crafted.tbl.frame, v.crafted.tbl.height }
  end
  v.pg.place(list)
  for _, r in ipairs(v.profRows) do if r:IsShown() then pcall(r.layout); pcall(placeProfRow, r) end end
end
function V.renderProf()
  local v = V.prof; if not v then return end
  local now = nowT()
  local rows = buildProfessions()
  local crafts, csum = buildCrafts()
  v.rows, v.batches, v.craftSum = rows, crafts, csum
  for i, p in ipairs(rows) do
    local r = profRow(v, i)
    local known = p.max > 0   -- (a profession only a craft or a recipe names has no rank read yet)
    r:Set({ icon = PROF_ICON[p.name] or "Interface\\Icons\\INV_Misc_Note_01", title = p.name, meta = known and p.rankName or "",
      tip = { title = p.name, text = known and ("%s, skill %d of %d."):format(p.rankName, p.rank, p.max)
        or "Skill: Not known yet. It shows once the game lists the profession." } })
    -- (a profession whose rank is not read yet: no track, and the one phrase for it, muted, where the number stands)
    r.unknown = not known
    r.frac = known and p.rank / p.max or 0
    r.count:SetText(known and ("%d / %d"):format(p.rank, p.max) or "Not known yet")
    UI.SetColor(r.count, known and "fg" or "fgMuted")
    r.train:SetText(p.training or "")
    r:Show()
  end
  for i = #rows + 1, #v.profRows do v.profRows[i]:Hide() end
  if #rows == 0 then v.empty:Set("No profession learned yet."); v.empty:Show() else v.empty:Hide() end
  -- CRAFTED: named after the first day the list holds whole, with the items listed; left out while nothing is listed
  v.craftedShown = #crafts > 0
  if v.craftedShown then
    v.craftLabel = "Crafted" .. (csum.since and (" since " .. UI.fmtSince(csum.since, now)) or "")
    v.crafted.head:SetLabel(v.craftLabel)
    v.crafted.head:SetMeta(UI.plural(csum.items, "item"))
    v.crafted.head:Show(); v.crafted.tbl.frame:Show()
    v.crafted.tbl.setRows(withDays(crafts, "item", "t1", "count"), function(row, r)
      row.c.when:SetText(batchWhen(r))
      row.c.item:SetText((V.unbracket(r.item) or "Crafted item") .. (r.count > 1 and (" x" .. UI.fmtNum(r.count)) or ""))
      local q = r.id and plain(call(C_Item and C_Item.GetItemQualityByID, r.id))
      if q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q] then local qc = ITEM_QUALITY_COLORS[q]; row.c.item:SetTextColor(qc.r, qc.g, qc.b) end
      row.c.prof:SetText(r.prof or "")
    end)
  else v.craftLabel = nil; v.crafted.head:Hide(); v.crafted.tbl.frame:Hide() end
  V.placeProf()
end

UI.registerPane("Character", 1, "Leveling", buildLeveling, function() pcall(V.renderLeveling) end,
  "Your level, when you reached each one, and the time played.")
UI.registerPane("Character", 2, "Reputation", buildRep, function() if V.rep and V.rep.detail.IsOpen() then V.rep.detail.Close() end; pcall(V.renderRep) end,
  "Your standing with every faction, what is left to the next one, and the last day it gained.")
UI.registerPane("Character", 3, "Professions", buildProf, function() pcall(V.renderProf) end,
  "Your skills and what you crafted.")

-- ── test exports: headless luajit tests in tests/ read these; no effect in-game ──
ns._test = ns._test or {}
ns._test.buildQuests, ns._test.buildReputation, ns._test.buildProfessions = buildQuests, buildReputation, buildProfessions
ns._test.buildLevels, ns._test.buildRepHistory, ns._test.buildCrafts = buildLevels, buildRepHistory, buildCrafts
ns._test.trainingLine = trainingLine
