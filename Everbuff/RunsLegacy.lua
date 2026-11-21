-- Everbuff.GG · RunsLegacy.lua - the dungeon runs from before the run store (docs/UX_PRAGMATIC.md 2.1, gate A).
--
-- A run is a stored record only from 0.9.50 on (Runs.lua). What the save still holds of the runs before it is the
-- character's gold runs (Economy.lua, characters[guid].goldRuns, from 0.9.47): when the run began, the time in the
-- dungeon to the 10 second tick, the coin looted, the quest coin, the item count and their vendor value. This file
-- copies those into characters[guid].dungeonLegacy[], once per character, so they stay when the gold run list
-- evicts them. The acknowledgement never touches the list.
--
-- Rules (founder: data accuracy is crucial):
--   a row holds only what the gold run stored. No bosses, no deaths, no XP, no end time: they were not recorded.
--   a gold run that began inside the span of a run record of the same dungeon is that record, never a row.
--   nothing is rebuilt from timing, gaps between events or zone names.
--   the rows never enter bests, averages or statistics (dungeonStats). They are listed, marked partial.
--   the copy runs once per character (the list exists from then on, even when empty): after it every run has a
--   record of its own, and a record deleted by hand does not come back as a row.

local ADDON, ns = ...

local L = {}
ns.RunsLegacy = L

L.CAP = 200                -- rows kept per character, oldest first
L.MATCH = 300              -- a gold run and a run record that began this close together are one run
L.MIN_SECS = 60            -- a shorter gold run with nothing in it is not a run (the rule of Runs.MIN_SECS)
L.KEYS = { "looted", "quests", "items", "lootValue", "unpriced" }

local function num(v) return type(v) == "number" and v == v and v or 0 end
local function me()
  if not (ns.DB and ns.charGuid and ns.charGuid()) then return nil end
  return ns.char()
end
local function sameInst(a, b) return type(a) == "string" and type(b) == "string" and a:lower() == b:lower() end

-- whether a row is one this file wrote and can read
function L.valid(r)
  return type(r) == "table" and type(r.id) == "string" and type(r.inst) == "string" and r.inst ~= ""
    and type(r.t) == "number" and r.t > 0 and type(r.secs) == "number" and r.secs >= 0
end
-- Where a run record ends on the wall clock: its stored end, else the end of its last visit. Nil when neither is
-- stored (the record then covers only its start).
function L.recordEnd(r)
  if type(r.endT) == "number" and r.endT >= num(r.t) then return r.endT end
  local last
  for _, x in ipairs(type(r.visits) == "table" and r.visits or {}) do
    local o = type(x) == "table" and (type(x.o) == "number" and x.o or (type(x.i) == "number" and x.i)) or nil
    if o and (not last or o > last) then last = o end
  end
  return last and (num(r.t) + last) or nil
end
-- The run record (closed or open) a gold run belongs to, or nil: same dungeon, and the gold run began inside the
-- record's span (L.MATCH seconds of slack at both ends). A record covers more than one gold run when the character
-- was outside for over 20 minutes (the gold run closes and a new one opens) and when two records were joined by
-- hand; matching the start alone listed those later gold runs a second time, as partial rows. The open record has
-- no end yet: every gold run of its dungeon after its start is its own.
function L.recordOf(c, g)
  local gt = num(g.t)
  local function hit(r, open)
    if type(r) ~= "table" or not sameInst(r.inst, g.inst) or num(r.t) <= 0 then return false end
    local z = open and math.huge or (L.recordEnd(r) or num(r.t))
    return gt >= num(r.t) - L.MATCH and gt <= z + L.MATCH
  end
  for _, r in ipairs(type(c.dungeonRuns) == "table" and c.dungeonRuns or {}) do if hit(r) then return r end end
  if hit(c.dungeonRun, true) then return c.dungeonRun end
  return nil
end
-- Copy the gold runs with no run record into the character's legacy list. Runs once per character; returns the
-- number of rows written, or nil when the character was read before.
function L.harvest(c)
  if type(c) ~= "table" then return nil end
  if type(c.dungeonLegacy) == "table" then
    for i = #c.dungeonLegacy, 1, -1 do if not L.valid(c.dungeonLegacy[i]) then table.remove(c.dungeonLegacy, i) end end
    return nil
  end
  local out = {}
  for _, g in ipairs(type(c.goldRuns) == "table" and c.goldRuns or {}) do
    if type(g) == "table" and type(g.inst) == "string" and g.inst ~= "" and num(g.t) > 0 and not L.recordOf(c, g) then
      local worth = num(g.looted) + num(g.quests) + num(g.items)
      if num(g.secs) >= L.MIN_SECS or worth > 0 then
        local row = { id = ("g%d"):format(g.t), src = "gold", inst = g.inst, t = g.t, secs = num(g.secs) }
        for _, k in ipairs(L.KEYS) do if num(g[k]) > 0 then row[k] = g[k] end end
        out[#out + 1] = row
      end
    end
  end
  table.sort(out, function(a, b) return a.t < b.t end)
  while #out > L.CAP do table.remove(out, 1) end
  c.dungeonLegacy = out
  return #out
end
-- every character of the save, at load (Core.lua, before the acknowledgement is applied)
function L.harvestAll(db)
  local n = 0
  for _, c in pairs(type(db) == "table" and type(db.characters) == "table" and db.characters or {}) do n = n + (L.harvest(c) or 0) end
  return n
end

-- One legacy row as the Dungeons list and its page read it: only what is stored. `legacy` marks it, so no surface
-- compares it with a run record.
function L.view(r)
  local gold = { looted = num(r.looted), quests = num(r.quests), lootValue = num(r.lootValue), items = num(r.items),
    unpriced = num(r.unpriced) > 0 and r.unpriced or nil }
  return { legacy = true, row = r, id = r.id, name = r.inst, startT = r.t, inside = num(r.secs), gold = gold,
    items = gold.items, coin = gold.looted, bosses = {} }
end
-- the legacy rows of the logged-in character, oldest first
function L.views()
  local c = me()
  local out = {}
  for _, r in ipairs(c and type(c.dungeonLegacy) == "table" and c.dungeonLegacy or {}) do
    if L.valid(r) then out[#out + 1] = L.view(r) end
  end
  return out
end

-- The runs that began in a session of the logged-in character: run records (the open one too) and legacy rows.
-- The one count Home > Sessions shows. The session's own `dungeons` counter is never read for it: before 0.9.50 it
-- counted dungeon entry events (22 for a night with 2 runs).
function L.inSession(sess)
  local c = me()
  if not (c and type(sess) == "table") then return 0 end
  local a = num(sess.startedEpoch)
  -- (a record with no stored end is open-ended only while it is the running session; one the client closed without
  -- saving has no known span, so no run is counted for it)
  local running = ns.Recorder and ns.Recorder.current and ns.Recorder.current() == sess
  local z = type(sess.endedEpoch) == "number" and sess.endedEpoch or (running and math.huge or nil)
  if a <= 0 or not z then return 0 end
  local n = 0
  local function count(list)
    for _, r in ipairs(type(list) == "table" and list or {}) do
      if type(r) == "table" and num(r.t) >= a and num(r.t) <= z then n = n + 1 end
    end
  end
  count(c.dungeonRuns); count(c.dungeonLegacy)
  if type(c.dungeonRun) == "table" then count({ c.dungeonRun }) end
  return n
end
