-- Everbuff.GG · Dungeons.lua - the Dungeons host: Runs (every run against your best), By dungeon (which dungeon is
-- worth your time) and the run page (docs/UX_OVERHAUL.md 4.5 to 4.7).
--
-- A classic player thinks in RUNS: enter, clear, leave. From 0.9.50 a run is a stored record of the character
-- (Runs.lua: characters[guid].dungeonRun and dungeonRuns), so the list survives the desktop's acknowledgement and
-- the story event cap. These panes only read, except the run page's own edits (keep, end, join, split, delete).
-- Every page is built from the kit in UI.lua: one scroll per page. What each shows and what it leaves out is
-- docs/UX_PRAGMATIC.md section 2: a number only when it is stored, a blank cell where nothing was recorded, and the
-- runs from before the run store (RunsLegacy.lua) in the same list, marked partial.

local ADDON, ns = ...
local UI = ns.UI
local C = ns.UI.C
local Runs = ns.Runs
local S, G, H = UI.S, UI.G, UI.H

local D = {}                 -- the module's state and helpers (one table: no long list of upvalues)
ns.Dungeons = ns.Dungeons or {}
local listView, detailView, byView, listRebuild

local SEP = " \194\183 "     -- " · "
local function n0(v) return type(v) == "number" and v or 0 end
local function nowT() return (GetServerTime and GetServerTime()) or time() end
-- what the open run of the character is now, straight from the store (a row of the list can be seconds old)
local function openRec()
  local c = ns.DB and ns.charGuid and ns.charGuid() and ns.char() or nil
  local r = c and c.dungeonRun
  return type(r) == "table" and r or nil
end
-- a frame counts as on screen only when its parents show too (IsShown is the frame's own flag)
local function onScreen(f)
  if not f then return false end
  if f.IsVisible then return f:IsVisible() and true or false end
  return f:IsShown() and true or false
end
local function qHex(q)
  q = type(q) == "string" and q:lower() or "ffffffff"
  if #q ~= 8 then q = "ffffffff" end
  return q
end
local function qColor(q)
  q = qHex(q)
  return { (tonumber(q:sub(3, 4), 16) or 255) / 255, (tonumber(q:sub(5, 6), 16) or 255) / 255, (tonumber(q:sub(7, 8), 16) or 255) / 255 }
end
local function colored(text, c) return ("|cff%02x%02x%02x%s|r"):format(math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5), text) end
local function stripLink(s)
  if ns.Now and ns.Now.stripLink then return ns.Now.stripLink(s) end
  return tostring(s or "")
end
local function sellPrice(id) if ns.Now and ns.Now.sellPrice then return ns.Now.sellPrice(id) end return 0 end
local function icon(path, size) return path and ("|T" .. tostring(path) .. (":%d:%d:0:0|t"):format(size, size)) or "" end
-- whole names plus "+N" in `width` px of META
local function fitNames(names, width, role)
  local out, shown = "", 0
  for i, n in ipairs(names) do
    local rest = #names - i
    local cand = (shown > 0 and (out .. ", ") or "") .. n
    local tail = rest > 0 and (" +" .. rest) or ""
    if shown > 0 and UI.TextWidth(role or "META", cand .. tail) > width then break end
    out, shown = cand, shown + 1
  end
  if shown < #names then out = out .. " +" .. (#names - shown) end
  return out
end
D.fitNames = fitNames
-- "16 Nov", the day of a best
local function dayMonth(t) return (tostring(tonumber(date("%d", t or 0)) or "")) .. date(" %b", t or 0) end
-- A kill clock or a split, to the second at every length ("19m 39s", "1h 4m 44s"): splits are compared run against
-- run, so the seconds are the point (docs/UX_PRAGMATIC.md 7). Every other duration is UI.fmtDur.
function D.fmtSplit(s)
  s = tonumber(s)
  if not s then return "" end
  s = math.max(0, math.floor(s + 0.5))
  if s < 3600 then return UI.fmtDur(s) end
  local h, m, r = math.floor(s / 3600), math.floor((s % 3600) / 60), s % 60
  return ("%dh %dm %ds"):format(h, m, r)
end
-- The length of a run, a sum or an average (docs/UX_PRAGMATIC.md 0.3): under 10 minutes with its seconds
-- ("7m 59s"), from 10 minutes in whole minutes ("33m", "1h 9m"), the seconds cut and not rounded, as the hour
-- sizes of UI.fmtDur already cut them. One formatter for full and rebuilt rows, so a column never mixes the two.
function D.fmtLen(s)
  s = tonumber(s)
  if not s or s ~= s then return "" end
  s = math.max(0, math.floor(s + 0.5))
  if s >= 600 then s = s - s % 60 end
  return UI.fmtDur(s)
end
-- the one way a pull-to-kill time is named, on the run page, on Runs and on By dungeon
function D.pullMeta(m) return UI.fmtDur(m) .. " first pull to last kill" end

-- ══ the facts of a run, as every surface says them ═══════════════════════════════════════════════════════════════
-- The bosses a run is counted against (docs/UX_PRAGMATIC.md 2.1): a total is shown only when it is known, from the
-- dungeon's learned list (the bosses killed in at least half of two or more stored runs, Runs.learned) or from a
-- lockout of the dungeon. The bosses one run met are never a total: with a single run "7 of 7" would be a circle.
local function lockTotal(name)
  if type(name) ~= "string" then return 0 end
  local c = ns.char and ns.char() or nil
  local n = 0
  for _, l in ipairs(c and type(c.lockouts) == "table" and c.lockouts or {}) do
    if type(l) == "table" and l.name == name then n = math.max(n, n0(l.bosses)) end
  end
  return n
end
-- the known total of a run's dungeon, or nil. Never below what the run itself met: the total is never the kills
-- alone when an encounter was left up (B1).
local function totalOf(run)
  local known = math.max(n0(run.total), lockTotal(run.name))
  if known == 0 then return nil end
  return math.max(known, #(run.bosses or {}) + #(run.missing or {}), n0(run.bossesDown))
end
D.totalOf = totalOf
-- "2/4" with a known total, else the kills alone "7" (table cells); D.bossCount(run) "2 of 4" or "7" (cards);
-- D.bossWord(run) "2 of 4 bosses" or "7 bosses" (sentences)
local function bossText(run)
  local t = totalOf(run)
  return t and ("%d/%d"):format(n0(run.bossesDown), t) or tostring(n0(run.bossesDown))
end
D.bossText = bossText
function D.bossCount(run)
  local t = totalOf(run)
  return t and ("%d of %d"):format(n0(run.bossesDown), t) or tostring(n0(run.bossesDown))
end
function D.bossWord(run)
  local t = totalOf(run)
  return t and ("%d of %s"):format(n0(run.bossesDown), UI.plural(t, "boss")) or UI.plural(n0(run.bossesDown), "boss")
end
-- the earlier runs of a run's route: the fastest of them before this run (the best it beat), or nil
local function previousBest(run)
  local rec = run.rec
  if type(rec) ~= "table" then return nil end
  local key, sig = Runs.keyOf(rec), Runs.sigOf(rec)
  if not sig then return nil end
  local c = ns.char and ns.char() or nil
  local best
  for _, o in ipairs(c and type(c.dungeonRuns) == "table" and c.dungeonRuns or {}) do
    if type(o) == "table" and o.id ~= rec.id and Runs.valid(o) and n0(o.t) < n0(rec.t) and Runs.keyOf(o) == key and Runs.sigOf(o) == sig and Runs.bestable(o) then
      local m = Runs.measure(o)
      if m and (not best or m < best) then best = m end
    end
  end
  return best
end
-- the fastest other run of a run's route (any time, not only before it): what the best run's bosses compare with
local function runnerUp(run)
  local rec = run.rec
  if type(rec) ~= "table" then return nil end
  local key, sig = Runs.keyOf(rec), Runs.sigOf(rec)
  if not sig then return nil end
  local c = ns.char and ns.char() or nil
  local best, bestM
  for _, o in ipairs(c and type(c.dungeonRuns) == "table" and c.dungeonRuns or {}) do
    if type(o) == "table" and o.id ~= rec.id and Runs.valid(o) and Runs.keyOf(o) == key and Runs.sigOf(o) == sig and Runs.bestable(o) then
      local m = Runs.measure(o)
      if m and (not bestM or m < bestM) then best, bestM = o, m end
    end
  end
  return best, bestM
end
D.runnerUp = runnerUp
-- The run against its best in words (UI.fmtDelta), the color key, and what kind of word it is:
--   ""               the only stored run of this dungeon (kind "first"): nothing to compare, and "first run" is not
--                    said, since runs from before the run store are not all stored
--   "42s faster"     a best that beat the route's earlier best (kind "best")
--   "best"           the best of a route no earlier run had (kind "best")
--   "3m 29s slower"  a run slower than its route's best
--   the run in progress against the best at the same boss; "" with nothing to compare
local function vsBest(run)
  local cmp = run.cmp
  if not cmp then return "", nil, "none" end
  if run.inProgress then
    if cmp.mode == "prefix" and cmp.delta then local w, k = UI.fmtDelta(cmp.delta); return w, k, "live" end
    return "", nil, "none"
  end
  if cmp.first then return "", nil, "first" end
  if cmp.mode == "same" then
    if cmp.isBest then
      local prev = previousBest(run)
      local m = Runs.measure(run.rec or {})
      if prev and m and m < prev then local w, k = UI.fmtDelta(m - prev); return w, k, "best" end
      return "best", nil, "best"
    end
    local w, k = UI.fmtDelta(cmp.delta)
    return w, k, "slower"
  end
  return "", nil, "none"
end
D.vsBest = vsBest
-- a word with its state dot when it is a warn or bad word (colour is never alone)
local function withDot(text, key, size) if key == "warn" or key == "bad" then return UI.dot(key, size) .. text end return text end
D.withDot = withDot
-- the bosses a run missed: the learned list's bosses it never pulled and those it pulled and did not kill
local function missedNames(run)
  local out = {}
  for _, b in ipairs(run.bosses or {}) do if not b.kill then out[#out + 1] = b.name or "Boss" end end
  for _, m in ipairs(run.missing or {}) do out[#out + 1] = m.name or "Boss" end
  return out
end
-- "2 of 4 bosses, missed Jergosh the Invoker, Bazzalan", "4 of 4 bosses, full clear", "3 bosses"
local function bossLine(run, width)
  local down, total = n0(run.bossesDown), totalOf(run)
  local missed = missedNames(run)
  if down == 0 and #missed == 0 and not total then return "no boss killed" end
  local s = D.bossWord(run)
  -- (a full clear needs the dungeon's learned list: before it, the bosses a run met are not all there are)
  if total and down >= total and #missed == 0 then return run.total and (s .. ", full clear") or s end
  if #missed > 0 then
    local pre = s .. ", missed "
    return pre .. fitNames(missed, math.max(80, (width or 400) - UI.TextWidth("META", pre)))
  end
  return s
end
D.bossLine = bossLine
-- who died in a run: the names of the death rows ("you" for the character's own), else a count
local function deathNames(run)
  local names, seen = {}, {}
  for _, d in ipairs(run.deathRows or {}) do
    local n = type(d) == "table" and (type(d.who) == "string" and d.who or "you") or nil
    if n and not seen[n] then seen[n] = true; names[#names + 1] = n end
  end
  return names
end
local function deathCount(run) return n0(run.deaths) + n0(run.partyDeaths) end
-- an item row that dropped in the dungeon: looted from a kill or a container, never a quest reward, a mail or an
-- auction (those can land inside a run's window and are not the run's loot)
function D.isDrop(l)
  if l.money or l.item == nil or l.mail then return false end
  local src = type(l.src) == "string" and l.src or ""
  return not (src:find("^Quest") or src:find("^Mail") or src:find("^Auction"))
end
-- the items of a run (from the loot log, drops only), best first: quality, then vendor price
local function runItems(run)
  local rec = run.rec
  if type(rec) ~= "table" then return {} end
  local rows = Runs.rowsOf(rec, ns.DB and ns.DB.loot and ns.DB.loot.log, "t", D.isDrop)
  local out = {}
  for _, l in ipairs(rows) do out[#out + 1] = { row = l, rank = Runs.qRank(l.q), price = sellPrice(l.id) } end
  table.sort(out, function(a, b)
    if a.rank ~= b.rank then return a.rank > b.rank end
    if a.price ~= b.price then return a.price > b.price end
    return n0(a.row.t) < n0(b.row.t)
  end)
  return out
end
D.runItems = runItems
-- The coin of a run, and where the figure comes from. The coin the addon books as looted misses the shares of group
-- loot the client pays without a loot window (Blackrock Spire, 20 Nov: 1g 16s booked, 1g 88s paid), so:
--   a run record whose purse gained more inside (quest coin aside) than was booked: the purse figure, "purse"
--   any other run record: the booked coin, "looted"
--   a rebuilt row: nil. It stores the booked coin only and no purse figure, so its coin is not known and is
--   never shown as a fact (D.PARTIAL_COIN = true would count the booked coin, a lower bound, again).
D.PARTIAL_COIN = false
function D.coinOf(run)
  local g = type(run) == "table" and type(run.gold) == "table" and run.gold or {}
  if run and run.legacy and not D.PARTIAL_COIN then return nil, "none" end
  local looted, purse = n0(g.looted), n0(g.purse)
  if purse > looted then return purse, "purse" end
  return looted, "looted"
end
-- What a run was worth (2.1): its coin (D.coinOf) and the vendor value of its items. Quest reward coin is not loot
-- and is not in it. Returns the sum, the coin and the item value.
function D.worth(run)
  local g = type(run.gold) == "table" and run.gold or {}
  local coin = n0((D.coinOf(run)))
  return coin + n0(g.lootValue), coin, n0(g.lootValue)
end
-- "1g 88s coin · 18g 3s items at vendor prices" (the meta of a WORTH card, the tooltip of a Worth cell). A rebuilt
-- row has no coin part: "items at vendor prices" under the card, "9g 34s items at vendor prices" in a tooltip.
function D.worthParts(run, short)
  local _, coin, value = D.worth(run)
  local parts = {}
  if coin > 0 then parts[#parts + 1] = UI.money(coin) .. " coin" end
  if value > 0 then parts[#parts + 1] = UI.money(value) .. (short and " items" or " items at vendor prices") end
  return table.concat(parts, SEP)
end
-- Where a drop of a run came from (2.2). A stored name is shown as stored. In a dungeon the game hides enemy names,
-- so the loot log holds a placeholder there; then the boss of this run killed at most D.BOSS_WINDOW seconds before
-- the row is named (an inference by timing, said so in the tooltip), an enemy placeholder with no boss kill in
-- range is "Trash" (the same inference), and every other placeholder is blank. Returns the text (nil: blank) and
-- the tooltip line.
D.PLACEHOLDER = { ["Creature"] = "enemy", ["an enemy"] = "enemy", ["Picked up"] = "none", ["Unknown source"] = "none" }
D.BOSS_WINDOW = 90
-- How the coin of a WORTH card was derived, for its hover and only when the purse and the booked coin differ. Exact
-- amounts, as every hover has them. The purse gained more: the coin is the purse figure, and the hover says so and
-- what was booked. The purse gained less (coin was spent inside): the coin is the booked figure.
D.NO_COIN = "The coin of this run was not recorded in full, so it is not counted."
function D.purseTip(run)
  local g = type(run) == "table" and type(run.gold) == "table" and run.gold or nil
  local looted, purse = n0(g and g.looted), n0(g and g.purse)
  if not g or run.legacy or purse <= 0 or purse == looted then return nil end
  if purse > looted then
    return ("Coin is what your purse gained inside, quest rewards aside: %s. Of it %s was seen as loot when it was picked up."):format(ns.fmtMoney(purse), ns.fmtMoney(looted))
  end
  return ("Your purse grew by %s inside, quest rewards aside. Looted coin was %s."):format(ns.fmtMoney(purse), ns.fmtMoney(looted))
end
function D.sourceOf(run, l)
  local src = type(l.src) == "string" and stripLink(l.src) or nil
  if src == "" then src = nil end
  local kind = src and D.PLACEHOLDER[src]
  if src and not kind then return src, nil end
  if not src then return nil, "Not recorded" end
  local rec, t = run.rec, tonumber(l.t)
  -- (without the record or the row's own time nothing can be said about the kills around it)
  if type(rec) ~= "table" or not t then return nil, "Not recorded" end
  local best, bestD, unknown
  for _, b in ipairs(type(rec.bosses) == "table" and rec.bosses or {}) do
    if b.kill then
      local w = Runs.wallOf(rec, b.kill)
      local d = w and (t - w) or nil
      -- A kill the record cannot place on the wall clock (Runs.visitClocks: a 0.9.50 record with three or more
      -- visits and gaps of two kinds) may be the one before this row: neither a boss nor "Trash" can be claimed.
      -- The same for a kill in range whose name is not stored.
      if not w then unknown = true
      elseif d >= 0 and d <= D.BOSS_WINDOW then
        if type(b.name) ~= "string" then unknown = true
        elseif not bestD or d < bestD then best, bestD = b, d end
      end
    end
  end
  if unknown then return nil, "Not recorded" end
  if best then
    return best.name, ("Looted %s after %s died. The game hides enemy names in dungeons."):format(UI.fmtDur(math.floor(bestD)), best.name)
  end
  if kind == "enemy" then
    return "Trash", ("No boss died in the %ds before this. The game hides enemy names in dungeons."):format(D.BOSS_WINDOW)
  end
  return nil, "Not recorded"
end
-- the best drop of every stored run, worked out once per change of the loot log or the runs (the list draws every
-- run again every 3 s)
D.dropCache = { key = nil, byId = {} }
local function bestDrops(runs)
  local log = ns.DB and ns.DB.loot and ns.DB.loot.log or {}
  local key = ("%d:%d:%d"):format(#log, #runs, n0(Runs._gen))
  if D.dropCache.key == key then return D.dropCache.byId end
  local byId = {}
  for _, r in ipairs(runs) do
    local items = runItems(r)
    byId[r.id] = { best = items[1] and items[1].row or nil, items = items }
  end
  D.dropCache = { key = key, byId = byId }
  return byId
end
D.bestDrops = bestDrops

-- ══ the summary line: instances this hour and the lockouts (shared by Runs and By dungeon) ════════════════════════
-- the lockouts of the account's other characters, for the hover of the lockout segment
local function otherLockouts()
  local out, mine = {}, ns.charGuid and ns.charGuid()
  local nowS = nowT()
  for guid, ch in pairs(ns.DB and type(ns.DB.characters) == "table" and ns.DB.characters or {}) do
    if guid ~= mine and type(ch) == "table" and type(ch.lockouts) == "table" then
      for _, l in ipairs(ch.lockouts) do
        if type(l) == "table" and n0(l.resetAt) > nowS then
          local prog = (l.bosses and l.down) and (" %d of %d"):format(l.down, l.bosses) or ""
          out[#out + 1] = { who = ch.name or "?", text = ("%s: %s%s, resets in %s"):format(ch.name or "?", l.name or "?", prog, UI.fmtDur(l.resetAt - nowS, { minutes = true })) }
        end
      end
    end
  end
  table.sort(out, function(a, b) if a.who ~= b.who then return a.who < b.who end return a.text < b.text end)
  local lines = {}
  for _, x in ipairs(out) do lines[#lines + 1] = x.text end
  return lines
end
D.otherLockouts = otherLockouts
-- this character's lockouts that still hold, soonest reset first
local function myLockouts()
  local L = (ns.DB and ns.char and type(ns.char().lockouts) == "table" and ns.char().lockouts) or {}
  local nowS, out = nowT(), {}
  for _, l in ipairs(L) do if type(l) == "table" and n0(l.resetAt) > nowS then out[#out + 1] = l end end
  table.sort(out, function(a, b) return n0(a.resetAt) < n0(b.resetAt) end)
  return out
end
-- the stored run a lockout came from: the newest run of that dungeon inside the lockout's life (a week at most)
local function lockoutRun(l)
  local c = ns.char and ns.char() or nil
  local nowS, match = nowT(), nil
  local runs = {}
  for _, r in ipairs(c and type(c.dungeonRuns) == "table" and c.dungeonRuns or {}) do runs[#runs + 1] = r end
  local o = openRec(); if o then runs[#runs + 1] = o end
  for _, rec in ipairs(runs) do
    if type(rec) == "table" and type(rec.inst) == "string" and type(l.name) == "string" and rec.inst:lower() == l.name:lower()
      and n0(rec.t) > nowS - 7 * 86400 and (not match or n0(rec.t) > n0(match.t)) then match = rec end
  end
  return match
end
D.lockoutRun = lockoutRun
local SAVED_BEFORE = "Saved before everbuff.gg captured this dungeon on this character."
-- the bosses down in a lockout: the open run's kills while the character is inside that dungeon (the client's
-- count lags a kill, and an earlier copy's number would contradict the run on screen), else the client's
local function lockDown(l)
  local o = openRec()
  if o and type(o.inst) == "string" and type(l.name) == "string" and o.inst:lower() == l.name:lower() then
    local k = 0
    for _, b in ipairs(type(o.bosses) == "table" and o.bosses or {}) do if b.kill then k = k + 1 end end
    return k
  end
  return l.down
end
D.lockDown = lockDown
-- (one form at every size: when the line is too long, another segment goes, never this wording)
local function lockLine(l, nowS)
  local down = lockDown(l)
  local reset = UI.fmtDur(n0(l.resetAt) - nowS, { minutes = true })
  local prog = (l.bosses and down) and (": %d of %d bosses down"):format(down, l.bosses) or ": saved"
  return (l.name or "?") .. prog .. ", resets in " .. reset
end
-- the lockout segment: one lockout (a link to its run), several (a count), or none
function D.lockSegment()
  local L, nowS = myLockouts(), nowT()
  local tip = function(tip)
    tip:AddLine("Lockouts", 1, 1, 1)
    for _, l in ipairs(L) do tip:AddLine(lockLine(l, nowS), 0.78, 0.79, 0.80, true) end
    local o = openRec()
    for _, l in ipairs(L) do
      if o and type(o.inst) == "string" and type(l.name) == "string" and o.inst:lower() == l.name:lower() then
        tip:AddLine("Counted from the run you are in now.", 0.78, 0.79, 0.80, true)
      end
    end
    local other = otherLockouts()
    if #other > 0 then
      tip:AddLine("Your other characters", 1, 1, 1)
      for i, line in ipairs(other) do if i > 4 then break end; tip:AddLine(line, 0.78, 0.79, 0.80, true) end
    end
  end
  -- (no lockout: nothing to say, the segment is left out)
  if #L == 0 then return nil end
  if #L > 1 then
    return { text = ("**%d** lockouts, next reset in %s"):format(#L, UI.fmtDur(n0(L[1].resetAt) - nowS, { minutes = true })), tip = tip }
  end
  local l = L[1]
  local rec = lockoutRun(l)
  if rec then return { text = lockLine(l, nowS), tip = tip, onClick = function() UI.Open("Dungeons", "runs"); ns.Dungeons.openRun(rec) end } end
  return { text = lockLine(l, nowS), tip = function(t2) tip(t2); t2:AddLine(SAVED_BEFORE, 0.78, 0.79, 0.80, true) end }
end
-- the instance segment: the count this hour (a guessed copy is named in the tooltip, never as a hedge on the line); against the player's own
-- limit only when one is set (Runs.limit(), unset by default: "of 5" is never invented)
function D.instanceSegment(at)
  at = at or nowT()
  local h, d, rows = Runs.copies(at)
  local lim = Runs.limit()
  local guess, oldest = false, nil
  for _, r in ipairs(rows) do
    if r.t > at - Runs.HOUR then
      if r.why == "estimate" then guess = true end
      if not oldest or r.t < oldest then oldest = r.t end
    end
  end
  local nextFree = oldest and UI.fmtDur(math.max(60, oldest + Runs.HOUR - at), { minutes = true }) or nil
  local tip = function(tip)
    tip:AddLine("Instances this hour", 1, 1, 1)
    tip:AddLine("Counted from your characters' dungeon entries this hour. A new copy within 20 minutes of the last is a guess.", 0.78, 0.79, 0.80, true)
    if guess then tip:AddLine("One of this hour's copies is such a guess, so the count may be one off.", 0.78, 0.79, 0.80, true) end
    for i, l in ipairs(Runs.hourTip(at)) do if i > 4 then break end; tip:AddLine(l, 0.78, 0.79, 0.80) end
    tip:AddDoubleLine("Last 24 hours", tostring(d), C.fgMuted[1], C.fgMuted[2], C.fgMuted[3], 1, 1, 1)
    if not lim then tip:AddLine("Set your own limit with /eb instances limit 5 (or 10).", 0.78, 0.79, 0.80, true) end
  end
  if not lim then
    -- (no instance this hour and no limit set: nothing to say, the segment is left out)
    if h == 0 then return nil end
    return { text = ("**%d** %s this hour"):format(h, h == 1 and "instance" or "instances"), tip = tip, hour = h }
  end
  local left = lim - h
  if left <= 0 then return { text = "No instances left this hour" .. (nextFree and (", next free in " .. nextFree) or ""), color = "bad", dot = "bad", tip = tip, hour = h } end
  if left == 1 then return { text = "**1** instance left this hour" .. (nextFree and (", next free in " .. nextFree) or ""), color = "warn", dot = "warn", tip = tip, hour = h } end
  return { text = ("**%d of %d** instances left this hour"):format(left, lim), tip = tip, hour = h }
end

-- ══ RUN PAGE (4.6) ════════════════════════════════════════════════════════════════════════════════════════════════
-- Drawn into the detail page's scroll child (docs/UX_PRAGMATIC.md 2.2): the title and its badges, the META line, the
-- stat cards (TIME, BOSSES, XP, WORTH, each only with a value), then the sections in their fixed order. A section
-- with nothing in it is left out; no sentence takes its place. A row from before the run store (RunsLegacy.lua) is
-- its time and its worth, nothing else.
local function buildDetail(content, list)
  local v
  local d = UI.Detail(content, { list = list, back = "\226\128\185 Runs",
    render = function(item) v.render(item) end,
    onBack = function(item) if listView and listView.restore then listView.restore(item) end end })
  v = d.view
  v.d, v.sf, v.child = d, d.sf, d.content
  local child = d.content
  local col = CreateFrame("Frame", nil, child); col:SetPoint("TOPLEFT", child, "TOPLEFT", 0, 0); col:SetSize(1, 1)
  v.col = col
  v.titleFS = UI.Text(col, "TITLE", "fg")
  v.badges = {}
  v.metaFS = UI.Text(col, "META", "fgMuted")
  -- (one card row per count of cards, made when first needed: a card with no value is left out, never a "-")
  v.cardRows = {}
  v.cardRow = function(n)
    for k, r in pairs(v.cardRows) do if k ~= n then r:Hide() end end
    local r = v.cardRows[n]
    if not r then r = UI.StatRow(col, n); v.cardRows[n] = r end
    r:Show()
    return r
  end
  v.sections, v.lines, v.tables, v.btns = {}, {}, {}, {}
  local SECTION_KEYS = { "bosses", "loot", "deaths", "party", "pace", "visits", "pulls", "edit" }
  local LABELS = { bosses = "Bosses", loot = "Loot", deaths = "Deaths", party = "Party", pace = "Pace",
    visits = "Entered and left", pulls = "Pulls of this run", edit = "Edit this run" }
  for _, k in ipairs(SECTION_KEYS) do v.sections[k] = UI.Section(col, LABELS[k]) end
  v.SECTION_KEYS = SECTION_KEYS
  -- the inline sentences and the META lines of the sections: a pool, laid out per render
  local ln = 0
  local function line(role, color)
    ln = ln + 1
    local fs = v.lines[ln]
    if not fs then fs = UI.Text(col, "BODY", "fgMuted"); v.lines[ln] = fs end
    fs:SetFontObject(UI.F[role or "BODY"]); fs.ebRole = role or "BODY"
    UI.SetColor(fs, color or "fgMuted")
    fs:Show()
    return fs
  end
  local function fight(f) if f and ns.OpenFightDetail then ns.OpenFightDetail(f) end end
  -- the section tables (kit lists): rows open a fight where one is stored
  -- (every table of the page: one lead column of UI.LEAD_W ("#", the item icon, the time), so every name column starts
  -- at table x 60, and the 12 px chevron slot on every table, so every last number ends on one right edge)
  local LEAD = UI.LEAD_W
  v.tables.bosses = UI.KitTable(col, {
    { key = "n", label = "#", kind = "tag", fixed = LEAD },
    { key = "boss", label = "Boss" },
    { key = "at", label = "Killed at", kind = "num", min = 64, measure = { "1h 59m 59s" } },
    { key = "since", label = "Split", kind = "num", min = 64, measure = { "1h 59m 59s" }, tip = "Boss 1: since entering. Others: since the previous kill." },
    { key = "vs", label = "Vs best", kind = "tag", min = 88, justify = "RIGHT" },
    { key = "len", label = "Fight length", kind = "num", min = 88, measure = { "wipe, 10s" } },
  }, { onClick = function(row) if row.item and row.item.fight then fight(row.item.fight) end end,
    tooltip = function(row, item, tip)
      tip:AddLine(item.name or "Boss", 1, 1, 1)
      for _, l in ipairs(item.tip or {}) do tip:AddLine(l, 0.78, 0.79, 0.80, true) end
    end })
  v.tables.bosses.spec[2].flex = 1
  v.tables.loot = UI.KitTable(col, {
    { key = "ic", label = "", kind = "icon", fixed = LEAD },
    { key = "item", label = "Item", flex = 1, min = 120 },
    { key = "src", label = "From", kind = "tag", min = 120, max = 200 },
    { key = "at", label = "When", kind = "num", min = 48, measure = { "00:00" } },
  }, { chevron = "reserve", tooltip = function(row, item, tip)
      local l = item.row
      tip:AddLine(stripLink(l.item), unpack(qColor(l.q)))
      if item.from then tip:AddLine("From " .. item.from, 0.78, 0.79, 0.80, true) end
      if item.fromTip then tip:AddLine(item.fromTip, 0.78, 0.79, 0.80, true) end
      tip:AddLine(UI.fmtWhen(l.t), 0.78, 0.79, 0.80)
    end })
  v.tables.deaths = UI.KitTable(col, {
    { key = "n", label = "#", kind = "tag", fixed = LEAD },
    { key = "who", label = "Who", min = 96 },
    { key = "foe", label = "Killed by", flex = 1, min = 120 },
    { key = "where", label = "Where", kind = "tag", min = 72, max = 160 },
    { key = "at", label = "Into the run", kind = "num", min = 88 },
    { key = "back", label = "Back after", kind = "num", min = 80 },
  }, { chevron = "reserve" })
  v.tables.pulls = UI.KitTable(col, {
    { key = "tm", label = "When", kind = "tag", fixed = LEAD },
    { key = "nm", label = "Enemy", flex = 1, min = 120 },
    { key = "len", label = "Length", kind = "num", min = 56 },
    { key = "re", label = "Result", kind = "tag", min = 64, justify = "RIGHT" },
  }, { onClick = function(row) if row.item and row.item.f then fight(row.item.f) end end })
  v.tables.visits = UI.KitTable(col, {
    { key = "n", label = "#", kind = "tag", fixed = LEAD },
    { key = "how", label = "How", flex = 1, min = 120 },
    { key = "act", label = "", kind = "tag", min = 104 },
    { key = "at", label = "Entered", kind = "num", min = 72 },
    { key = "len", label = "Inside", kind = "num", min = 64 },
  }, { chevron = "reserve" })

  -- the TIME card lists the clocks on hover
  v.timeTipLines = function()
    local run = v.run
    if not (run and listView and listView.tipLines) then return {} end
    return listView.tipLines(run)
  end

  -- ── the run's edits: two clicks for anything that changes the record (the first asks, in the page; a second
  -- within 8 seconds does it)
  local REFUSED = {
    cap = ("%d runs are kept already. Unkeep one first."):format(Runs.KEEP_CAP),
    old = "This run was stored before version 0.9.51 with more than one kind of time outside, so it cannot be split or joined.",
    evicted = "A run between these two is no longer in the list, so they cannot be joined.",
    none = "There is no stored run before this one.",
    other = "The run before this one is of another dungeon.",
    visits = ("Together they would have more than %d visits."):format(Runs.VISIT_CAP),
    bosses = ("Together they would have more than %d bosses."):format(Runs.BOSS_CAP),
    order = "The run before this one ends after it begins.",
    gone = "This run is no longer stored.",
    visit = "A run can only be split where a visit begins.",
    char = "The character is not known yet. Try again in a moment.",
  }
  v.REFUSED = REFUSED
  v.QUESTION = {
    delete = "Delete this run? Its numbers leave the dungeon totals. Cannot be undone.",
    ["end"] = "End this run now? What happens next in the dungeon is a new run.",
    join = "Join this run with the run before it? The two become one run.",
    split = "Split this run here? This visit and the ones after it become a run of their own.",
  }
  v.YES = { delete = "Yes, delete", ["end"] = "Yes, end it", join = "Yes, join", split = "Yes, split here" }
  v.pending = nil
  local bn = 0
  local function actBtn(label, style, onClick)
    bn = bn + 1
    local b = v.btns[bn]
    if not b then
      b = UI.KitButton(col, "", "ghost", function(s2) if s2.ebAct then s2.ebAct() end end)
      v.btns[bn] = b
    end
    b.ebStyle = style or "ghost"
    b:SetLabel(label); b.ebPaint("rest")
    b.ebAct, b.label, b.key, b.visit = onClick, label, nil, nil   -- (a pooled button forgets what it was before)
    b:Show()
    return b
  end
  v.actBtns = function()
    local out = {}
    for i = 1, bn do out[#out + 1] = v.btns[i] end
    return out
  end
  -- after an action: the page shows the record the action left (by id), or the list when there is none
  local function showId(id)
    v.pending = nil
    local c = ns.DB and ns.charGuid and ns.charGuid() and ns.char() or nil
    local rec = openRec()
    if rec and rec.id == id and Runs.valid(rec) then v.show(Runs.view(rec, true, true)); return end
    for _, r in ipairs(c and type(c.dungeonRuns) == "table" and c.dungeonRuns or {}) do
      if type(r) == "table" and r.id == id and Runs.valid(r) then v.show(Runs.view(r, false, true)); return end
    end
    v.toList()
  end
  v.showId = showId
  local function ask(key, fn)
    local p = v.pending
    if p and p.key == key and p.id == (v.run and v.run.id) and GetTime() < p.untilT then fn(); return end
    local q = { key = key, id = v.run and v.run.id, untilT = GetTime() + 8 }
    v.pending = q
    v.render(v.run)
    -- when the 8 seconds are over the button reads its own label again and the question goes
    if C_Timer and C_Timer.After then
      C_Timer.After(8.1, function()
        if v.pending == q and GetTime() >= q.untilT then
          v.pending = nil
          if v.run and v:IsShown() then pcall(v.render, v.run) end
        end
      end)
    end
  end
  v.ask = ask
  local function result(ok, why, id)
    if ok then showId(id) else v.pending = nil; v.refused = REFUSED[why] or tostring(why); v.render(v.run) end
  end

  -- what a second changes on the page of a run in progress: the TIME card. The page names two clocks, time inside
  -- (this card) and the boss clock (the BOSSES card); where the rest of the time went is the card's hover.
  local live = {}
  local function clocks(run)
    if live.time then live.time.value:SetText(D.fmtLen(run.inside)) end
  end

  v.render = function(run)
    if not run then return end
    if v.run and v.run.id ~= run.id then v.pending, v.refused = nil, nil end
    v.run = run
    ln, bn = 0, 0
    v.renders = (v.renders or 0) + 1
    local W = G.mainW(G.winW())
    v.renderedW = W
    col:SetWidth(W)
    local y = 0
    local function put(f, h, x)
      f:ClearAllPoints(); f:SetPoint("TOPLEFT", col, "TOPLEFT", x or 0, -y); f:SetWidth(W - (x or 0))
      if h then f:SetHeight(h) end
    end
    local function text(fs, s, h)
      fs:ClearAllPoints(); fs:SetPoint("TOPLEFT", col, "TOPLEFT", S.S3, -y); fs:SetWidth(W - 2 * S.S3)
      fs:SetText(s or ""); y = y + (h or UI.LINE_H[fs.ebRole or "BODY"] + S.S1)
      return fs
    end
    -- title with its badges inline, the META line
    local badges = {}
    if run.inProgress then badges[#badges + 1] = "IN PROGRESS" end
    local word, wkey, kind = vsBest(run)
    if kind == "best" then badges[#badges + 1] = "BEST" end
    if run.keep then badges[#badges + 1] = "KEPT" end
    local title = (run.name or "Dungeon") .. (run.kind == "raid" and " (raid)" or "")
    v.titleFS:ClearAllPoints(); v.titleFS:SetPoint("TOPLEFT", col, "TOPLEFT", S.S3, 0); v.titleFS:SetText(title)
    local bw = 0
    for i, t in ipairs(badges) do local b = v.badges[i] or UI.Badge(col, t); v.badges[i] = b; b:SetBadge(t); b.ebTip = nil; b:Show(); bw = bw + b:GetWidth() + S.S2 end
    for i = #badges + 1, #v.badges do v.badges[i]:Hide() end
    local tw = math.min(UI.TextWidth("TITLE", title), W - 2 * S.S3 - bw)
    v.titleFS:SetWidth(math.max(1, tw))
    -- (badges on the title line's vertical centre)
    local bx = 0
    for i = 1, #badges do v.badges[i]:ClearAllPoints(); v.badges[i]:SetPoint("LEFT", v.titleFS, "RIGHT", bx + S.S2, 0); bx = bx + S.S2 + v.badges[i]:GetWidth() end
    local meta = { run.inProgress and (UI.fmtDate(run.startT) .. " since " .. UI.fmtClock(run.startT)) or (UI.fmtWhen(run.startT) .. (run.endT and (" to " .. UI.fmtClock(run.endT)) or "")) }
    local x1 = type(run.xp) == "table" and run.xp or {}
    if x1.l0 then meta[#meta + 1] = "level " .. math.floor(x1.l0) end
    -- (the party only as a stored fact: the largest group a stored pull of the run recorded, or "solo" from the
    -- record's own size. A size the record does not hold says nothing: it is never read as solo.)
    local grp = run.group and #run.group or 0
    if grp > 1 then meta[#meta + 1] = "party of " .. grp
    elseif not run.inProgress and run.size == 1 then meta[#meta + 1] = "solo" end
    if run.edited then meta[#meta + 1] = "corrected by hand" end
    -- (the run against its best, once there is one to compare with)
    if kind == "best" and word ~= "best" and word ~= "" then meta[#meta + 1] = word .. " than your best before"
    elseif kind == "slower" then meta[#meta + 1] = word == "same as best" and "same as your best" or (word .. " than your best") end
    v.metaFS:ClearAllPoints(); v.metaFS:SetPoint("TOPLEFT", col, "TOPLEFT", S.S3, -22); v.metaFS:SetWidth(W - 2 * S.S3)
    v.metaFS:SetText(table.concat(meta, SEP))
    v.metaText = v.metaFS:GetText()
    y = 48
    for _, sec in pairs(v.sections) do sec:Hide() end
    for _, t in pairs(v.tables) do t.frame:Hide() end
    v.empties = {}
    -- the cards: TIME, BOSSES, XP (when the run earned any), WORTH (when it looted anything)
    local m = Runs.measure(run.rec or {})
    local cmp = run.cmp or {}
    -- (the comparison's word, as the tests and the META read it; "first run" names a run with nothing to compare)
    v.deltaText = (kind == "first" and "first run") or (word ~= "" and word) or "No best yet"
    local worth = D.worth(run)
    local defs = { "time", "bosses" }
    if n0(run.xpGain) > 0 then defs[#defs + 1] = "xp" end
    if worth > 0 then defs[#defs + 1] = "worth" end
    local row = v.cardRow(#defs)
    put(row, H.STAT); pcall(row.layout)
    local cards, card = row.cards, {}
    for i, k in ipairs(defs) do card[k] = cards[i]; cards[i].ebKey = k end
    v.cards, v.card = cards, card
    live.time = card.time
    local away = n0(run.ghost) + n0(run.outside)
    card.time:Set("Time", D.fmtLen(run.inside), run.inProgress and "inside, so far" or (away > 0 and (D.fmtLen(away) .. " dead or outside") or "inside"))
    UI.SetTip(card.time, function(tip)
      tip:AddLine("Time", 1, 1, 1)
      tip:AddLine("Time inside the dungeon. " .. (v.clockSentence or ""), 0.78, 0.79, 0.80, true)
      for _, l in ipairs(v.timeTipLines()) do tip:AddLine(l, 0.78, 0.79, 0.80) end
    end)
    local missed = missedNames(run)
    local total = totalOf(run)
    local bossMeta
    if run.inProgress then bossMeta = total and ((total - n0(run.bossesDown)) > 0 and (UI.fmtNum(total - n0(run.bossesDown)) .. " left") or "all down") or ""
    elseif m then bossMeta = "boss clock " .. UI.fmtDur(m)
    else bossMeta = #missed > 0 and ("missed " .. #missed) or "" end
    card.bosses:Set("Bosses", D.bossCount(run), bossMeta)
    local routeNames = {}
    for _, b in ipairs(run.bosses or {}) do if b.kill then routeNames[#routeNames + 1] = b.name or "Boss" end end
    UI.SetTip(card.bosses, function(tip)
      tip:AddLine("Bosses", 1, 1, 1)
      if total then tip:AddLine(bossLine(run, 260), 0.78, 0.79, 0.80, true)
      else tip:AddLine("Bosses killed in this run. A total shows once the dungeon has been run twice.", 0.78, 0.79, 0.80, true) end
      if m then tip:AddLine(("Boss clock: %s, the measure bests are compared on."):format(D.pullMeta(m)), 0.78, 0.79, 0.80, true) end
      if #routeNames > 0 and (kind == "best" or kind == "slower") then
        tip:AddLine(("Compared with your fastest run that killed these %s: %s."):format(UI.plural(#routeNames, "boss"), fitNames(routeNames, 260)), 0.78, 0.79, 0.80, true)
      end
    end)
    v.xpTip, v.purseTip = nil, nil
    if card.xp then
      -- (per hour of time inside, the TIME card's own clock; a rate needs Runs.RATE_WARM seconds)
      local rate = n0(run.inside) >= Runs.RATE_WARM and math.floor(n0(run.xpGain) * 3600 / run.inside + 0.5) or nil
      card.xp:Set("XP", UI.fmtNum(n0(run.xpGain)), rate and (UI.fmtNum(rate) .. " per hour") or "")
      -- (the card is the page's whole answer on XP; the split, the levels and what the client hid are its hover.
      -- Stored facts only: no kill count, which disagrees with the pulls, and no forecast of runs to a level.)
      local xr = type(run.xp) == "table" and run.xp or {}
      local tipLines = { "XP earned inside, and per hour of the time inside." }
      local quest, kill = n0(xr.quest), math.max(0, n0(run.xpGain) - n0(xr.quest))
      if quest > 0 and kill > 0 then tipLines[#tipLines + 1] = ("%s from kills, %s from quests."):format(UI.fmtNum(kill), UI.fmtNum(quest))
      elseif quest > 0 then tipLines[#tipLines + 1] = "All from quests."
      else tipLines[#tipLines + 1] = "All from kills." end
      local lv = Runs.xpLine(run)
      lv = lv and lv:match("(level [%d%.]+ to [%d%.]+)")
      if lv then tipLines[#tipLines + 1] = "L" .. lv:sub(2) .. "." end
      local _, _, hid = Runs.xpLine(run)
      if hid then tipLines[#tipLines + 1] = hid end
      v.xpTip = tipLines
      UI.SetTip(card.xp, function(tip)
        tip:AddLine("XP", 1, 1, 1)
        for _, l in ipairs(tipLines) do tip:AddLine(l, 0.78, 0.79, 0.80, true) end
      end)
    end
    if card.worth then
      local full = D.worthParts(run)
      local metaW = full
      if UI.TextWidth("META", full) > (tonumber(card.worth:GetWidth()) or 0) - 2 * S.S3 then metaW = D.worthParts(run, true) end
      if UI.TextWidth("META", metaW) > (tonumber(card.worth:GetWidth()) or 0) - 2 * S.S3 then metaW = "coin and items" end
      card.worth:Set("Worth", UI.money(worth), metaW)
      local g0 = type(run.gold) == "table" and run.gold or {}
      -- (the purse beside the looted coin, when the two differ, is a hover fact: the page has no line for it)
      v.purseTip = D.purseTip(run)
      UI.SetTip(card.worth, function(tip)
        tip:AddLine("Worth", 1, 1, 1)
        tip:AddLine(full:sub(1, 1):upper() .. full:sub(2) .. ".", 0.78, 0.79, 0.80, true)
        if n0(g0.unpriced) > 0 then tip:AddLine(("%s had no vendor price yet and %s not counted."):format(UI.plural(g0.unpriced, "item"), g0.unpriced == 1 and "is" or "are"), 0.78, 0.79, 0.80, true) end
        if n0(g0.quests) > 0 then tip:AddLine(("Quest rewards paid %s more. They are not loot and are not counted here."):format(UI.money(g0.quests)), 0.78, 0.79, 0.80, true) end
        if v.purseTip then tip:AddLine(v.purseTip, 0.78, 0.79, 0.80, true) end
      end)
    end
    v.worthText = card.worth and card.worth.value:GetText() or nil
    y = y + H.STAT + S.S5
    -- the notes a run can carry (a repeated pull, a lost part): META lines under the cards
    if run.repull then text(line("META", "fgSubtle"), "Possibly two runs: a boss killed before was pulled again in visit " .. run.repull .. ". Split here is on that visit.") end
    local partial = Runs.partialLine(run)
    if partial then text(line("META", "fgSubtle"), partial) end
    if run.repull or partial then y = y + S.S3 end
    local function section(key, metaText)
      local sec = v.sections[key]
      put(sec, H.SECTION); sec:SetMeta(metaText); sec:Show()
      y = y + H.SECTION
      return sec
    end
    local function tableAt(tbl, items, fill)
      tbl.frame:Show()
      put(tbl.frame)
      tbl.relayout(W)
      tbl.setRows(items, fill)
      y = y + (tbl.height or 0)
    end

    -- 1 BOSSES: one row per boss in pull order, then the learned list's bosses never pulled
    local bosses = run.bosses or {}
    local byUid = {}
    for _, f in ipairs(run.fights or {}) do if type(f.uid) == "string" then byUid[f.uid] = f end end
    local brows = {}
    -- (the best run and a first run are their own best: no delta to show)
    -- (a run that is not the best: each boss against the best's split. The best run: against the next fastest run of
    -- the same bosses. A run nothing compares with leaves the column out.)
    local vs, vsAgainst = cmp.vs or {}, nil
    if cmp.first then vs = {} end
    if cmp.isBest then
      vs = {}
      local other = runnerUp(run)
      if other then
        local mine, theirs = Runs.splits(run.rec or {}), Runs.splits(other)
        for enc, x in pairs(mine) do if theirs[enc] then vs[enc] = x.at - theirs[enc].at end end
        vsAgainst = ("against your next fastest run of these bosses, on %s"):format(dayMonth(other.t))
      end
    end
    v.vsAgainst = vsAgainst
    local kills = {}
    for _, b in ipairs(bosses) do if b.kill then kills[#kills + 1] = b end end
    table.sort(kills, function(a, b) return a.kill < b.kill end)
    local order = {}
    for i, b in ipairs(kills) do order[b] = i end
    for _, b in ipairs(bosses) do
      local res = Runs.bossResult(b)
      local tip = { res .. (n0(b.wipes) > 0 and (", " .. UI.plural(b.wipes, "wipe")) or "") .. (n0(b.pulls) > 1 and (" in " .. UI.plural(b.pulls, "fight")) or "") }
      if b.kill and vs[b.enc] and vsAgainst then tip[#tip + 1] = "Vs best: " .. vsAgainst end
      -- (Split is on the clock of Killed at: the first boss since entering, so the two cells of its row agree; the
      -- others since the kill before. Bests still measure from the first pull, Runs.splits.)
      local sp = run.splits and run.splits[b.enc]
      local since = sp and b.kill and (sp.prevKey == "start" and b.kill or sp.seg) or nil
      brows[#brows + 1] = { name = b.name or "Boss", kill = b.kill, n = order[b], since = since, d = b.kill and vs[b.enc], len = b.combat, tip = tip,
        wiped = n0(b.wipes) > 0, fight = b.kill and b.fight and byUid[b.fight] or nil, ebNoOpen = not (b.kill and b.fight and byUid[b.fight]) }
    end
    -- (every boss of the dungeon is listed, the ones still to go too: a run in progress marks the first of them "next")
    for i, mm in ipairs(run.missing or {}) do
      brows[#brows + 1] = { name = mm.name or "Boss", tip = { run.inProgress and "Not pulled yet" or "Not pulled in this run" }, ebNoOpen = true, next = run.inProgress and i == 1 or nil }
    end
    table.sort(brows, function(a, b)
      if (a.kill ~= nil) ~= (b.kill ~= nil) then return a.kill ~= nil end
      if a.kill and b.kill then return a.kill < b.kill end
      return false
    end)
    v.bossRows = brows
    -- (never a column of blanks: with no boss to compare, the column goes)
    local anyVs = false
    for _, it in ipairs(brows) do if it.d or it.next then anyVs = true end end
    v.tables.bosses.spec[5].hide = not anyVs
    v.bossVsShown = anyVs
    if #brows > 0 then
      section("bosses", total and D.bossCount(run) or nil)
      tableAt(v.tables.bosses, brows, function(r, it)
        local dim = not it.kill
        -- (a cell with nothing recorded is blank, never "-")
        r.c.n:SetText(it.n and tostring(it.n) or "")
        r.c.boss:SetText(it.name); UI.SetColor(r.c.boss, dim and "fgMuted" or "fg")
        r.c.at:SetText(it.kill and D.fmtSplit(it.kill) or "")
        r.c.since:SetText(it.since and D.fmtSplit(it.since) or "")
        if it.d then local w2, k2 = UI.fmtDelta(it.d); r.c.vs:SetText(withDot(w2, k2)); UI.SetColor(r.c.vs, k2 or "fgSubtle")
        else r.c.vs:SetText(it.next and "next" or ""); UI.SetColor(r.c.vs, "fgMuted") end
        if it.kill then r.c.len:SetText(n0(it.len) > 0 and UI.fmtDur(it.len) or "")
        elseif n0(it.len) > 0 then
          -- (pulled and not killed: what happened, then how long it lasted; a wipe is an event result)
          if it.wiped then r.c.len:SetText(withDot("wipe, " .. UI.fmtDur(it.len), "bad")); UI.SetColor(r.c.len, "bad")
          else r.c.len:SetText("not killed, " .. UI.fmtDur(it.len)); UI.SetColor(r.c.len, "fgMuted") end
        else r.c.len:SetText("") end
      end)
    end
    -- the deaths of the run as one line while no row names a killer or a party member (in a dungeon the game hides
    -- who killed whom): when each happened and how long the character was down
    local drows = run.deathRows or {}
    v.deathRows = drows
    local named = false
    for _, dd in ipairs(drows) do if dd.foe or dd.who then named = true end end
    v.deathLine, v.deathFS = nil, nil
    if deathCount(run) > 0 and not named then
      local bits = {}
      for _, dd in ipairs(drows) do
        local w = type(run.rec) == "table" and Runs.wallOf(run.rec, dd.o) or nil
        local one = w and UI.fmtClock(w) or (UI.fmtDur(n0(dd.o)) .. " in")
        if dd.back then one = one .. (" (%s down)"):format(UI.fmtDur(dd.back)) end
        bits[#bits + 1] = one
      end
      if #bits == 0 then v.deathLine = "Deaths: " .. deathCount(run)
      else
        v.deathLine = "Deaths: " .. table.concat(bits, SEP)
        if deathCount(run) > #bits then v.deathLine = v.deathLine .. SEP .. ("and %d more"):format(deathCount(run) - #bits) end
      end
      if #brows > 0 then y = y + S.S2 end
      v.deathFS = text(line("META", "fgMuted"), v.deathLine)
    end
    if #brows > 0 or v.deathLine then y = y + S.S5 end

    -- 2 LOOT: the drops of the run, green and better as rows, the rest as one line
    local items = runItems(run)
    v.lootAll = items
    local shown, white, grey = {}, 0, 0
    for _, it in ipairs(items) do
      if it.rank >= 2 then
        it.from, it.fromTip = D.sourceOf(run, it.row)
        shown[#shown + 1] = it
      elseif it.rank == 1 then white = white + 1 else grey = grey + 1 end
    end
    v.lootItems = shown
    local more = white + grey
    local moreParts = {}
    if white > 0 then moreParts[#moreParts + 1] = white .. " white" end
    if grey > 0 then moreParts[#moreParts + 1] = grey .. " grey" end
    v.lootMore = more > 0 and ((#shown > 0 and "%d more: %s" or "%d looted: %s"):format(more, table.concat(moreParts, ", "))) or nil
    -- (with no row left in the loot log the run's own count is all there is to say)
    local stored = n0(run.items)
    if #items == 0 and stored > 0 then v.lootMore = UI.plural(stored, "item") end
    v.lootFS = nil
    if #shown > 0 or v.lootMore then
      section("loot", #shown > 0 and (#shown .. " green or better") or nil)
      if #shown > 0 then
        tableAt(v.tables.loot, shown, function(r, it)
          local l = it.row
          -- (the stack count in fgMuted right after the name, as Loot > Auctions writes it)
          r.c.ic:SetTexture(l.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
          r.c.item:SetText(stripLink(l.item) .. (n0(l.count) > 1 and (" " .. colored("x" .. l.count, C.fgMuted)) or ""))
          r.c.item:SetTextColor(unpack(qColor(l.q)))
          r.c.src:SetText(it.from or "")
          r.c.at:SetText(UI.fmtClock(l.t))
        end)
      end
      if v.lootMore then
        y = y + S.S1
        v.lootFS = text(line("META", "fgMuted"), v.lootMore)
      end
    end
    if #shown > 0 or v.lootMore then y = y + S.S5 - S.S1 end

    -- 3 DEATHS: a table only when a row names the killer or the party member who died
    if named then
      section("deaths", UI.plural(deathCount(run), "death"))
      -- (Where is a place: the boss the party was fighting, by its number in the kill order, never the killer again)
      local bossNo = {}
      for i, b in ipairs(kills) do bossNo[b.enc] = i end
      local di = 0
      tableAt(v.tables.deaths, drows, function(r, dd)
        di = di + 1
        r.c.n:SetText(tostring(di))
        r.c.at:SetText(UI.fmtDur(n0(dd.o)))
        -- (who, in class colour when the run's party names them)
        local who = type(dd.who) == "string" and dd.who or nil
        local cls
        for _, mm in ipairs(run.group or {}) do if (who and mm.name == who) or (not who and mm.me) then cls = mm.class end end
        r.c.who:SetText(who or "You")
        if cls then r.c.who:SetTextColor(UI.ClassColor(cls)) else UI.SetColor(r.c.who, who and "fgSubtle" or "fg") end
        r.c.foe:SetText(dd.foe or "")
        local where = type(dd.sub) == "string" and dd.sub ~= "" and dd.sub or (dd.enc and bossNo[dd.enc] and ("at boss " .. bossNo[dd.enc])) or nil
        if where == dd.foe then where = nil end
        r.c.where:SetText(where or "")
        r.c.back:SetText(dd.back and UI.fmtDur(dd.back) or "")
      end)
      if deathCount(run) > #drows then text(line("META", "fgMuted"), ("and %d more"):format(deathCount(run) - #drows)) end
      y = y + S.S5
    end

    -- (no XP section: the XP card is the answer, and its hover has the split and the levels)

    -- 5 PARTY: the largest group a pull of the run recorded, in class colours
    if grp > 1 then
      section("party", UI.plural(grp, "player"))
      -- one cell per member, joined with " · ": the name in class colour, then level and role in fgMuted
      local ROLE = { TANK = "tank", HEALER = "healer", DAMAGER = "damage" }
      local nm = {}
      for _, mm in ipairs(run.group) do
        local r2, g2, b2 = UI.ClassColor(mm.class)
        local tail = {}
        -- (your own level is the run's, the one the subtitle names; the others are what the pull recorded)
        local lvl = (mm.me and x1.l0) and math.floor(x1.l0) or mm.level
        if lvl then tail[#tail + 1] = tostring(lvl) end
        if ROLE[mm.role] then tail[#tail + 1] = ROLE[mm.role] end
        nm[#nm + 1] = colored(mm.name or "?", { r2, g2, b2 }) .. (#tail > 0 and (" " .. colored(table.concat(tail, " "), C.fgMuted)) or "")
      end
      v.partyFS = text(line("BODY", "fg"), table.concat(nm, colored(SEP, C.fgMuted)), UI.LINE_H.BODY + S.S1)
      y = y + S.S5
    else v.partyFS = nil end

    -- 6 PACE: against the best of the route
    local p1, p2 = D.paceLines(run)
    v.paceLine, v.paceLine2 = p1, p2
    if p1 then
      section("pace", nil)
      text(line("BODY", "fg"), p1, UI.LINE_H.BODY + S.S1)
      if p2 then text(line("META", "fgMuted"), p2) end
      y = y + S.S5
    end

    -- 7 ENTERED AND LEFT: only on a run marked "possibly two runs", whose note points at Split here on a visit.
    -- Every other run has no such section (2.2): the TIME card carries inside and dead or outside, its hover the
    -- rest, and no visit count, third clock or combat total is on the page.
    clocks(run)
    local visits = run.repull and (run.visits or {}) or {}
    v.visitsShown = run.repull ~= nil and #visits > 0
    if v.visitsShown then
      section("visits", nil)
      y = y + S.S1
      local canSplit = Runs.visitClocks(run.rec or run) ~= nil
      local HOW = { zone = "entered", login = "logged in inside", reload = "after a reload", ghost = "back after a run back", boss = "at a boss pull", split = "after a split" }
      local vrows = {}
      for k, xv in ipairs(visits) do vrows[#vrows + 1] = { k = k, x = xv } end
      local splitAt = {}
      tableAt(v.tables.visits, vrows, function(r, it)
        local xv = it.x
        r.c.n:SetText(tostring(it.k)); if run.repull == it.k then UI.SetColor(r.c.n, "warn") end
        r.c.at:SetText(UI.fmtClock(n0(run.startT) + n0(xv.i)))
        r.c.len:SetText(UI.fmtDur(n0(xv.secs)))
        r.c.how:SetText((HOW[xv.how] or tostring(xv.how or "")) .. (n0(xv.n) > 0 and (SEP .. ("and %d more"):format(xv.n)) or ""))
        r.c.act:SetText("")
        if it.k >= 2 and canSplit and xv.i ~= nil and visits[it.k - 1].o ~= nil then splitAt[#splitAt + 1] = { row = r, k = it.k } end
      end)
      for _, sa in ipairs(splitAt) do
        local key = "split" .. sa.k
        local ac = v.tables.visits.cols.act
        local asking = v.pending and v.pending.key == key
        local b = actBtn(asking and v.YES.split or "Split here", "ghost", function()
          ask(key, function() local id = run.id; local ok, why = Runs.split(id, sa.k); result(ok, why, id) end)
        end)
        b.visit = sa.k
        b:ClearAllPoints(); b:SetPoint("LEFT", sa.row, "LEFT", ac and ac.x or S.S3, 0)
      end
      y = y + S.S5
      end

    -- 8 ALL FIGHTS IN THIS RUN: the fights still stored, the same list Home > Fights groups under the run (A21, B23)
    v.encounters = #(run.fights or {})
    -- (shown only while pulls of this run are stored: the desktop app picks them up, and then the section goes)
    if v.encounters > 0 then
      section("pulls", UI.plural(v.encounters, "pull"))
      local prow = {}
      for i = #run.fights, 1, -1 do prow[#prow + 1] = { f = run.fights[i] } end
      v.pullRows = prow
      tableAt(v.tables.pulls, prow, function(r, it)
        local f = it.f
        r.c.tm:SetText(UI.fmtClock(f.startEpoch or 0))
        r.c.nm:SetText(f.bossName or ((f.foes and f.foes[1]) or "Pull"))
        r.c.len:SetText(UI.fmtDur(n0(f.duration)))
        local rc = ns.FightResult and ns.FightResult(f) or { "-", C.fgSubtle }
        r.c.re:SetText(rc[1]); r.c.re:SetTextColor(rc[2][1], rc[2][2], rc[2][3])
      end)
      y = y + S.S5
    end

    -- 9 EDIT THIS RUN: Keep, End run now (the open run), Join with the run before, Delete run
    section("edit", nil)
    y = y + S.S1
    local bx = S.S3
    local function act(key, label, style, fnAct, needsAsk)
      local asking = v.pending and v.pending.key == key
      local b = actBtn(asking and v.YES[key] or label, style, function()
        if needsAsk then ask(key, fnAct) else fnAct() end
      end)
      b.key = key
      b:ClearAllPoints(); b:SetPoint("TOPLEFT", col, "TOPLEFT", bx, -y)
      bx = bx + (tonumber(b:GetWidth()) or 60) + S.S2
      return b
    end
    act("keep", run.keep and "Unkeep" or "Keep", "ghost", function()
      local id = run.id
      local ok, why = Runs.setKeep(id, not run.keep)
      if ok then v.refused = nil end
      result(ok, why, id)
    end, false)
    if run.inProgress then act("end", "End run now", "ghost", function() local id = run.id; Runs.endNow(); showId(id) end, true) end
    act("join", "Join with the run before", "ghost", function() local ok, why = Runs.join(run.id); result(ok, why, ok and why or run.id) end, true)
    act("delete", "Delete run", "danger", function() local id = run.id; local ok, why = Runs.delete(id); if ok then v.pending = nil; v.toList() else result(ok, why, id) end end, true)
    y = y + H.CONTROL + S.S2
    local q = v.pending and (v.QUESTION[v.pending.key] or (v.pending.key:match("^split") and v.QUESTION.split))
    v.questionLine = q
    if q then text(line("META", "fgSubtle"), q) end
    if v.refused then text(line("META", "fgSubtle"), v.refused) end
    v.refusedLine = v.refused
    if not q and not v.refused then text(line("META", "fgMuted"), run.keep and "Kept: never removed when the list is full." or "Keep a run so it is never removed when the list is full.") end
    for i = ln + 1, #v.lines do v.lines[i]:Hide() end
    for i = bn + 1, #v.btns do v.btns[i]:Hide() end
    y = y + S.S4
    col:SetHeight(y)
    v.sf:SetContentHeight(y)
    v.contentH = y
    v.sigLists, v.sigPage = nil, nil
    if run.inProgress and type(run.rec) == "table" then v.sigLists, v.sigPage = v.signature(run.rec) end
  end
  -- A row from before the run store (RunsLegacy.lua): the time in the dungeon and what it was worth, the two facts
  -- the gold run kept. Nothing else is on the page, and nothing says what is absent.
  local function renderLegacy(run)
    v.pending, v.refused = nil, nil
    v.run = run
    ln, bn = 0, 0
    v.renders = (v.renders or 0) + 1
    local W = G.mainW(G.winW())
    v.renderedW = W
    col:SetWidth(W)
    for _, sec in pairs(v.sections) do sec:Hide() end
    for _, t in pairs(v.tables) do t.frame:Hide() end
    v.empties, v.bossRows, v.lootItems, v.lootAll, v.deathRows = {}, {}, {}, {}, {}
    v.lootMore, v.lootFS, v.deathLine, v.deathFS, v.xpTip, v.purseTip, v.paceLine, v.paceLine2, v.partyFS = nil, nil, nil, nil, nil, nil, nil, nil, nil
    v.deltaText, v.encounters, v.visitsShown = nil, 0, false
    live.time = nil
    local title = run.name or "Dungeon"
    v.titleFS:ClearAllPoints(); v.titleFS:SetPoint("TOPLEFT", col, "TOPLEFT", S.S3, 0); v.titleFS:SetText(title)
    local b = v.badges[1] or UI.Badge(col, "PARTIAL"); v.badges[1] = b
    b:SetBadge("PARTIAL"); b:Show()
    UI.SetTip(b, { title = "Partial", text = "Time and loot only" })
    for i = 2, #v.badges do v.badges[i]:Hide() end
    local tw = math.min(UI.TextWidth("TITLE", title), W - 2 * S.S3 - b:GetWidth() - S.S2)
    v.titleFS:SetWidth(math.max(1, tw))
    b:ClearAllPoints(); b:SetPoint("LEFT", v.titleFS, "RIGHT", S.S2, 0)
    v.metaFS:ClearAllPoints(); v.metaFS:SetPoint("TOPLEFT", col, "TOPLEFT", S.S3, -22); v.metaFS:SetWidth(W - 2 * S.S3)
    v.metaFS:SetText(UI.fmtWhen(run.startT))
    v.metaText = v.metaFS:GetText()
    local y = 48
    local worth = D.worth(run)
    local row = v.cardRow(worth > 0 and 2 or 1)
    row:ClearAllPoints(); row:SetPoint("TOPLEFT", col, "TOPLEFT", 0, -y); row:SetWidth(W); row:SetHeight(H.STAT); pcall(row.layout)
    local cards = row.cards
    v.cards, v.card = cards, { time = cards[1], worth = cards[2] }
    cards[1]:Set("Time", D.fmtLen(run.inside), "in the dungeon")
    UI.SetTip(cards[1], { title = "Time", text = "Time in the dungeon and at its entrance, counted in steps of 10 seconds." })
    if cards[2] then
      local full = D.worthParts(run)
      local _, coin = D.worth(run)
      local metaW = full
      if coin == 0 then metaW = "items at vendor prices"
      elseif UI.TextWidth("META", full) > (tonumber(cards[2]:GetWidth()) or 0) - 2 * S.S3 then metaW = D.worthParts(run, true) end
      cards[2]:Set("Worth", UI.money(worth), metaW)
      local g0 = run.gold
      v.coinTip = select(2, D.coinOf(run)) == "none" and D.NO_COIN or nil
      UI.SetTip(cards[2], function(tip)
        tip:AddLine("Worth", 1, 1, 1)
        tip:AddLine(full:sub(1, 1):upper() .. full:sub(2) .. ".", 0.78, 0.79, 0.80, true)
        if v.coinTip then tip:AddLine(v.coinTip, 0.78, 0.79, 0.80, true) end
        if n0(g0.items) > 0 then tip:AddLine(UI.plural(g0.items, "item") .. " looted.", 0.78, 0.79, 0.80, true) end
        if n0(g0.unpriced) > 0 then tip:AddLine(("%s had no vendor price yet and %s not counted."):format(UI.plural(g0.unpriced, "item"), g0.unpriced == 1 and "is" or "are"), 0.78, 0.79, 0.80, true) end
        if n0(g0.quests) > 0 then tip:AddLine(("Quest rewards paid %s more. They are not loot and are not counted here."):format(UI.money(g0.quests)), 0.78, 0.79, 0.80, true) end
      end)
    end
    v.worthText = cards[2] and cards[2].value:GetText() or nil
    y = y + H.STAT + S.S4
    for i = ln + 1, #v.lines do v.lines[i]:Hide() end
    for i = bn + 1, #v.btns do v.btns[i]:Hide() end
    col:SetHeight(y)
    v.sf:SetContentHeight(y)
    v.contentH = y
    v.sigLists, v.sigPage = nil, nil
  end
  -- the clocks of the TIME tooltip, as one sentence
  v.clockSentence = nil
  local baseRender = v.render
  v.render = function(run)
    if run and run.legacy then return renderLegacy(run) end
    if run then
      local bits = { "entered " .. UI.fmtClock(run.startT) }
      local rec = run.rec or {}
      if n0(rec.firstPull) > 0 then bits[#bits + 1] = "first pull " .. UI.fmtClock(n0(run.startT) + rec.firstPull) end
      local last
      for _, b in ipairs(run.bosses or {}) do if b.kill and (not last or b.kill > last) then last = b.kill end end
      if last then bits[#bits + 1] = "last kill " .. UI.fmtClock(n0(run.startT) + last) end
      if run.endT then bits[#bits + 1] = "left " .. UI.fmtClock(run.endT) end
      v.clockSentence = "Your clocks: " .. table.concat(bits, ", ") .. "."
    end
    return baseRender(run)
  end
  -- What the page of a run in progress shows, as two short texts: `lists` changes when a fight or a loot row was
  -- stored or a visit began or ended, `page` when anything but a clock did. While neither changes, a second only
  -- moves the clocks.
  v.signature = function(rec)
    local nF = #((ns.Fights and ns.Fights.list and ns.Fights.list()) or {})
    local nL = #((ns.DB and ns.DB.loot and ns.DB.loot.log) or {})
    local lists = ("%d.%d.%d.%s"):format(nF, nL, #rec.visits, tostring(rec.st))
    local p = { lists, #rec.bosses, #rec.deaths, n0(rec.nDeaths and rec.nDeaths.me), tostring(rec.partial), n0(rec.secs.active), n0(rec.hidden and rec.hidden.xp),
      tostring(rec.keep), tostring(rec.repull), tostring(rec.id) }
    for _, b in ipairs(rec.bosses) do
      p[#p + 1] = ("%d/%d/%d/%d/%d/%d"):format(n0(b.pulls), n0(b.kill), n0(b.wipes), n0(b.unknown), n0(b.resets), n0(b.combat))
    end
    local dd = rec.deaths[#rec.deaths]
    if dd then p[#p + 1] = tostring(dd.foe) .. n0(dd.back) end
    local x = rec.xp
    if type(x) == "table" then p[#p + 1] = ("%d/%d/%d"):format(n0(x.gain), n0(x.n), n0(x.quest)) end
    for _, vis in ipairs(rec.visits) do
      p[#p + 1] = ("%d/%d/%d/%d/%d/%d"):format(n0(vis.looted), n0(vis.quests), n0(vis.lootValue), n0(vis.items), n0(vis.unpriced), n0(vis.purse))
    end
    return lists, table.concat(p, " ")
  end
  -- show a run on the page (the list's order for Older and Newer when the run is in it)
  v.show = function(run)
    local items = listView and listView.shown or {}
    local idx
    for i, r in ipairs(items) do if r.id == run.id then idx = i; items[i] = run end end
    if not idx then items, idx = { run }, 1 end
    d:Open(items, idx)
  end
  v.toList = function() d.Close(); if listRebuild then listRebuild() end end
  -- The open run's page follows it, once a second while it is on screen. The run is read from the store by its id:
  -- it may have closed meanwhile (the page becomes the closed run's), or have been discarded as empty (the page goes
  -- back to the list). Returns whether the page still shows a run.
  v.refresh = function()
    local run = v.run
    if not (run and run.inProgress and run.id) then return false end
    local rec = openRec()
    if rec and rec.id == run.id and Runs.valid(rec) then
      local light = Runs.view(rec, true, false)
      local lists, page = v.signature(rec)
      if page == v.sigPage then
        light.fights, light.notable, light.group = run.fights, run.notable, run.group
        v.run = light
        clocks(light)
      elseif lists == v.sigLists then
        light.fights, light.notable, light.group = run.fights, run.notable, run.group
        v.render(light)
      else v.render(Runs.view(rec, true, true)) end
      return true
    end
    local c = ns.DB and ns.charGuid and ns.charGuid() and ns.char() or nil
    local lst = c and type(c.dungeonRuns) == "table" and c.dungeonRuns or {}
    for i = #lst, 1, -1 do
      if type(lst[i]) == "table" and lst[i].id == run.id and Runs.valid(lst[i]) then v.render(Runs.view(lst[i], false, true)); return true end
    end
    run.inProgress = false
    v.toList()
    return false
  end
  -- a new width lays the open run out again
  d.sf.onResize = function() if v.run and v:IsShown() then pcall(v.render, v.run) end end
  v:HookScript("OnShow", function() if v.run and v.renderedW ~= G.mainW(G.winW()) then pcall(v.render, v.run) end end)
  return v
end

-- The Pace lines of a run (on the route's own measure, first pull to last kill, never the TIME card's clock):
--   "Your best for these 6 bosses: 28m 41s on 16 Nov, first pull to last kill. This run is your best."
--   "Your best for these 6 bosses: ... This run: 29m 23s, 42s slower."
--   then "If you matched your best on every boss: 27m 50s" when every segment of this run's order is known;
--   or, with no best on its route (the run in progress), against the best of the route that shares its start:
--   "At boss 3 of 5 your best is 12m 10s from the first pull, on 16 Nov. This run: 12m 51s, 41s slower."
-- nil before the dungeon's first full clear or with nothing to compare.
function D.paceLines(run)
  local cmp = run.cmp
  if not (cmp and cmp.mode and cmp.delta and run.cleared) then return nil end
  local when = dayMonth(cmp.bestAt or 0)
  local w = UI.fmtDelta(cmp.delta)
  local mine = ("This run: %s, %s."):format(UI.fmtDur(cmp.best + cmp.delta), w)
  if cmp.mode == "same" then
    local n = Runs.routePart(run) or select(2, Runs.routeOf(run.rec or run))
    local l1 = ("Your best for these %s: %s on %s, first pull to last kill. %s"):format(UI.plural(n or 0, "boss"), UI.fmtDur(cmp.best), when,
      cmp.isBest and "This run is your best." or mine)
    -- (the sum of the best segments says something only when it differs from the best: with one run behind the
    -- per-boss bests it is the same number twice)
    local sum = cmp.sumBest and math.floor(cmp.sumBest) ~= math.floor(cmp.best) and cmp.sumBest or nil
    return l1, sum and ("If you matched your best on every boss: " .. UI.fmtDur(sum)) or nil
  end
  return ("At boss %d of %d your best is %s from the first pull, on %s. %s"):format(cmp.at, cmp.of, UI.fmtDur(cmp.best), when, mine), nil
end

-- ══ RUNS (4.5) ═════════════════════════════════════════════════════════════════════════════════════════════════════
-- the value a column sorts by
local SORT_VAL = {
  time = function(r) return n0(r.startT) end,
  name = function(r) return (r.name or ""):lower() end,
  dur = function(r) return n0(r.inside) end,
  vs = function(r) local c = r.cmp; return (c and c.mode == "same" and c.delta) or 1e9 end,
  boss = function(r) return r.legacy and -1 or n0(r.bossesDown) end,
  death = function(r) return r.legacy and -1 or deathCount(r) end,
  worth = function(r) return (D.worth(r)) end,
}
-- every run the list shows: the run records (the open one last) and the rows from before the run store
function D.allRuns()
  local out = Runs.views()
  local L = ns.RunsLegacy
  for _, r in ipairs(L and L.views() or {}) do out[#out + 1] = r end
  return out
end
-- the runs the filter keeps, sorted by `key`; ties and the default newest first
local function listRows(runs, inst, key, asc)
  local rows = {}
  for _, r in ipairs(runs) do if not inst or r.name == inst then rows[#rows + 1] = r end end
  local val = SORT_VAL[key] or SORT_VAL.time
  table.sort(rows, function(a, b)
    local x, y = val(a), val(b)
    if x ~= y then if asc then return x < y end return x > y end
    if n0(a.startT) ~= n0(b.startT) then return n0(a.startT) > n0(b.startT) end
    return tostring(a.id) > tostring(b.id)
  end)
  return rows
end
D.listRows = listRows
-- the rows with their day rows ("TODAY") while the list is in time order
local function withDays(rows, grouped)
  if not grouped then return rows end
  local out, i = {}, 1
  while i <= #rows do
    local day = UI.fmtDay(rows[i].startT)
    local j = i
    while j + 1 <= #rows and UI.fmtDay(rows[j + 1].startT) == day do j = j + 1 end
    -- (the day alone: a count would claim the runs of a day whose earlier runs were never stored)
    out[#out + 1] = { ebSection = day }
    for k = i, j do out[#out + 1] = rows[k] end
    i = j + 1
  end
  return out
end

-- the badge after a name cell (BEST, KEPT, IN PROGRESS): placed after the text, the text shortening first
local function placeBadge(tbl, row)
  local cw = tbl.cols and tbl.cols.name
  local fs = row.c and row.c.name
  if not (cw and fs) then return end
  local b = row.ebBadge
  -- (the name steps down to 10 px before it may shorten: a badge never costs the row its dungeon name)
  fs.ebFile, fs.ebSize = UI.F.BODY.ebFile, UI.F.BODY.ebSize
  if b and b:IsShown() and not (row.item and row.item.ebSection) then
    local bw = tonumber(b:GetWidth()) or 0
    local room = cw.w - bw - S.S2
    fs:SetWidth(math.max(1, room)); UI.Fit(fs, 10)
    local tw = math.max(1, math.min(tonumber(fs:GetStringWidth()) or room, room))
    fs:SetWidth(tw)
    b:ClearAllPoints(); b:SetPoint("LEFT", row, "LEFT", cw.x + tw + S.S2, 0)
  else
    if b then b:Hide() end
    fs:SetWidth(cw.w); UI.Fit(fs, 10)
  end
end
local function badgeOf(run)
  if run.legacy then return nil end
  if run.inProgress then return "LIVE" end   -- (the short live marker in a row; the hero and the page say IN PROGRESS)
  local _, _, kind = vsBest(run)
  if kind == "best" then return "BEST" end
  if run.keep then return "KEPT" end
  return nil
end
D.badgeOf = badgeOf

local function buildList(content)
  local v = CreateFrame("Frame", nil, content); v:SetAllPoints(content)
  local st = { inst = nil, sortKey = "time", sortAsc = false }
  v.st = st
  local sf, child = UI.ScrollChild(v, { slim = true, top = 0, left = 0, right = 0, bottom = 0 })
  v.sf, v.child = sf, child
  local col = CreateFrame("Frame", nil, child); col:SetPoint("TOPLEFT", child, "TOPLEFT", 0, 0); col:SetSize(1, 1)
  v.col = col
  v.summary = UI.Summary(col)
  v.hero = UI.Hero(col, {})
  v.empty = UI.Empty(col, { icon = "Interface\\Icons\\INV_Misc_Map_01", title = "No run stored yet",
    text = "Enter any dungeon and your run is recorded: time, bosses, deaths and loot." })
  v.empty:Hide()
  v.section = UI.Section(col, "Runs")
  -- the dungeon filter: a filter button at the right of the control row
  local controls = content.ebControls or v
  v.filter = UI.FilterButton(controls, { default = "", label = "All dungeons",
    items = function()
      local names, seen = {}, {}
      for _, r in ipairs(D.allRuns()) do
        if r.name and not seen[r.name] then seen[r.name] = true; names[#names + 1] = r.name end
      end
      table.sort(names)
      local items = { { "", "All dungeons", st.inst == nil } }
      for _, n in ipairs(names) do items[#items + 1] = { n, n, st.inst == n } end
      items[#items + 1] = { "raids", "Raids \194\183 coming soon", false, true }
      return items
    end,
    onPick = function(key) v.pickInst(key ~= "" and key or nil) end })
  v.filter:SetPoint("TOPRIGHT", controls, "TOPRIGHT", 0, 0)
  v.pickInst = function(name)
    st.inst = name
    v.filter:SetValue(name and name or "", name or "All dungeons")
    if listRebuild then listRebuild() end
  end
  -- the list
  local spec = {
    { key = "time", label = "When", kind = "tag", min = 40, sort = true },
    -- (the name takes the width the other columns leave, so the list ends on the hero's right edge)
    { key = "name", label = "Dungeon", flex = 1, min = 140, sort = true },
    { key = "dur", label = "Time", kind = "num", min = 56, sort = true, tip = "Time inside the dungeon" },
    { key = "vs", label = "Vs best", kind = "tag", min = 88, justify = "RIGHT", sort = true, tip = "Compared from first pull to last kill, against your fastest run with the same bosses" },
    { key = "boss", label = "Bosses", kind = "num", min = 40, sort = true },
    { key = "death", label = "Deaths", kind = "num", min = 48, sort = true },
    { key = "worth", label = "Worth", kind = "money", min = 72, sort = true, tip = "Coin plus the vendor value of the items. Partial runs: items only." },
    { key = "drop", label = "Best drop", min = 160, max = 260, wide = true },
  }
  local specOf = {}
  for _, c in ipairs(spec) do specOf[c.key] = c end
  local tbl
  tbl = UI.KitTable(col, spec, {
    sortKey = st.sortKey, sortAsc = st.sortAsc,
    onSort = function(key, asc) st.sortKey, st.sortAsc = key, asc; if listRebuild then listRebuild() end end,
    onClick = function(row, item) if item and not item.ebSection then v.open(item) end end,
    onLayout = function(t) for i = 1, t.shownN do placeBadge(t, t.rows[i]) end end,
    onHeight = function() if v.place then pcall(v.place) end end,
    tooltip = function(row, run, tip)
      if not run or run.ebSection then return end
      tip:AddLine(run.name or "Dungeon", 1, 1, 1)
      for _, l in ipairs(v.tipLines(run)) do tip:AddLine(l, 0.78, 0.79, 0.80, true) end
    end })
  v.tbl = tbl
  -- the lines of a row's tooltip (and of the run page's TIME card): the clocks, the state, the best, XP and loot
  v.tipLines = function(run)
    if run.legacy then
      local out = { "Time and loot only", "Time " .. UI.fmtDur(run.inside) }
      local parts = D.worthParts(run)
      if parts ~= "" then out[#out + 1] = "Worth: " .. parts end
      if select(2, D.coinOf(run)) == "none" then out[#out + 1] = D.NO_COIN end
      if n0(run.items) > 0 then out[#out + 1] = UI.plural(run.items, "item") end
      return out
    end
    local out = { "Inside " .. UI.fmtDur(run.inside) }
    if n0(run.ghost) > 0 then out[#out + 1] = "Run back " .. UI.fmtDur(run.ghost) end
    if n0(run.outside) > 0 then out[#out + 1] = "Outside " .. UI.fmtDur(run.outside) end
    if n0(run.offline) > 0 then out[#out + 1] = "Offline " .. UI.fmtDur(run.offline) end
    if run.inProgress then out[#out + 1] = "In progress" else out[#out + 1] = "Ended: " .. (Runs.WHY[run.why] or "left the dungeon") end
    if run.edited then out[#out + 1] = "Corrected by hand" end
    if run.repull then out[#out + 1] = "Possibly two runs: a boss killed before was pulled again" end
    if run.keep then out[#out + 1] = "Kept: never removed when the list is full" end
    local partial = Runs.partialLine(run)
    if partial then out[#out + 1] = partial end
    local cmp = run.cmp
    if cmp and cmp.mode == "same" and cmp.best and cmp.delta then
      -- (the measure in words: "28m 41s first pull to last kill, 42s faster than 29m 23s")
      local here = cmp.best + cmp.delta
      local word = vsBest(run)
      local prev = cmp.isBest and previousBest(run) or nil
      -- (a run of part of the dungeon says which best: "your best for these 2 bosses")
      local n = Runs.routePart(run)
      local which = n and (" (your best for these %d bosses)"):format(n) or ""
      if cmp.isBest and prev and here < prev then out[#out + 1] = ("%s, %s than %s%s"):format(D.pullMeta(here), word, UI.fmtDur(prev), which)
      elseif cmp.isBest then out[#out + 1] = D.pullMeta(here) .. ", your best" .. (n and (" for these %d bosses"):format(n) or "")
      elseif cmp.delta == 0 then out[#out + 1] = D.pullMeta(here) .. ", same as your best" .. (n and (" for these %d bosses"):format(n) or "")
      else out[#out + 1] = ("%s, %s than %s%s"):format(D.pullMeta(here), word, UI.fmtDur(cmp.best), which) end
    elseif cmp and cmp.mode == "prefix" and cmp.best and cmp.delta then
      out[#out + 1] = ("Against your best at boss %d of %d: from the first pull, %s here, best %s"):format(cmp.at, cmp.of, UI.fmtDur(cmp.best + cmp.delta), UI.fmtDur(cmp.best))
    end
    local names = deathNames(run)
    if deathCount(run) > 0 then out[#out + 1] = UI.plural(deathCount(run), "death") .. (#names > 0 and (": " .. table.concat(names, ", ")) or "") end
    if n0(run.xpGain) > 0 then out[#out + 1] = UI.fmtNum(run.xpGain) .. " XP" end
    local drop = v.drops and v.drops[run.id]
    if drop then
      for i, it in ipairs(drop.items) do
        if i > 4 then out[#out + 1] = ("and %d more"):format(#drop.items - 4); break end
        out[#out + 1] = colored(stripLink(it.row.item), qColor(it.row.q)) .. (n0(it.row.count) > 1 and (" x" .. it.row.count) or "")
      end
    end
    local parts = D.worthParts(run)
    if parts ~= "" then out[#out + 1] = "Worth " .. UI.money((D.worth(run))) .. ": " .. parts end
    return out
  end

  -- lay the page out: summary, hero, ALL RUNS and the list (or the big empty state), one scroll
  v.place = function()
    local w = G.mainW(G.winW())
    col:SetWidth(w)
    local y = 0
    local function put(f, h) f:ClearAllPoints(); f:SetPoint("TOPLEFT", col, "TOPLEFT", 0, -y); f:SetWidth(w); if h then f:SetHeight(h) end end
    -- (the summary line and its gap only while it has something to say)
    if n0(v.summaryN) > 0 then put(v.summary, H.SUMMARY); pcall(v.summary.layout); y = y + H.SUMMARY + S.S3 end
    if v.empty:IsShown() then
      -- (the big empty block's top at CONTENT_TOP + S7, 2.7: 48 under the column's top, the summary above it)
      UI.PlaceEmpty(v.empty)
      y = S.S7 + (tonumber(v.empty:GetHeight()) or 140) + S.S4
    else
      if v.hero:IsShown() then put(v.hero, H.HERO); pcall(v.hero.layout); y = y + H.HERO + S.S5 end
      put(v.section, H.SECTION); y = y + H.SECTION
      put(tbl.frame); if tbl.width ~= math.min(w, G.TABLE_MAX) then tbl.relayout(w) end
      y = y + (tbl.height or 0) + S.S4
    end
    col:SetHeight(y)
    sf:SetContentHeight(y)
    v.contentH = y
  end
  content:HookScript("OnSizeChanged", function() pcall(v.place) end)

  -- the Last run hero: the verdict a row cannot hold
  v.heroRefresh = function(run)
    local h = v.hero
    -- (no run to lead with: the card goes and so does the run it showed, or the 1 s ticker of a run in progress
    -- would draw it again over a list filtered to another dungeon)
    if not run then v.heroRun = nil; h:Hide(); return end
    h:Show()
    h:SetKicker(run.inProgress and "In this dungeon" or "Last run")
    h:SetTitle(run.name or "Dungeon")
    local word, wkey, kind = vsBest(run)
    local badges = {}
    -- (a first run carries no FIRST RUN badge here: META says "first run" and the HERO gives the result)
    if run.inProgress then badges[#badges + 1] = "IN PROGRESS" elseif kind == "best" then badges[#badges + 1] = "BEST" end
    h:SetBadges(badges)
    local w = G.mainW(G.winW()) - 2 * S.S3
    local cmp = run.cmp or {}
    local verdict, vkey
    if run.inProgress then
      if kind == "live" and cmp.at then verdict, vkey = ("%s than your best at boss %d"):format(word, cmp.at), wkey
        if word == "same as best" then verdict, vkey = ("Same as your best at boss %d"):format(cmp.at), nil end
      else verdict = D.fmtLen(run.inside) .. " so far" end
      -- (META never repeats the HERO line: the start, then the bosses)
      h:SetMeta("Since " .. UI.fmtClock(run.startT) .. SEP .. bossLine(run, w - 200), nil)
      -- (the run in progress opens its page as every other run does, A10; a ghost: no primary while it runs)
      h:SetButton("Open run", function() v.open(run) end, "ghost")
    else
      -- (the answer is the result, "7 bosses in 1h 9m"; a comparison leads only when there is a best to compare with)
      local compared = (kind == "best" and word ~= "best" and word ~= "") or kind == "slower"
      if compared and word == "same as best" then verdict = "Same as your best"
      elseif compared then verdict, vkey = word .. " than your best", wkey
      else verdict = ((n0(run.bossesDown) > 0 or totalOf(run)) and D.bossWord(run) or "No boss killed") .. " in " .. D.fmtLen(run.inside) end
      local m1 = { UI.fmtWhen(run.startT) }
      if compared then m1[#m1 + 1] = D.fmtLen(run.inside); m1[#m1 + 1] = bossLine(run, w - 200)
      else
        local missed = missedNames(run)
        if #missed > 0 then m1[#m1 + 1] = "missed " .. fitNames(missed, math.max(80, w - 260))
        elseif run.total and n0(run.bossesDown) >= run.total then m1[#m1 + 1] = "full clear" end
      end
      h:SetMeta(table.concat(m1, SEP), nil)
      h:SetButton("Open run", function() v.open(run) end)
    end
    verdict = verdict:sub(1, 1):upper() .. verdict:sub(2)
    h:SetHero(withDot(verdict, vkey, UI.DOT_SIZE.HERO), vkey == "good" and "good" or (vkey == "warn" and "warn") or "fg")
    v.heroVerdict = verdict
    -- META line 2: the deaths (a count, only when there were any) and the best drop
    local drop = v.drops and v.drops[run.id]
    local best = drop and drop.best
    local parts = {}
    if deathCount(run) > 0 then parts[#parts + 1] = UI.plural(deathCount(run), "death") end
    if best and Runs.qRank(best.q) >= 2 then parts[#parts + 1] = "best drop " .. icon(best.icon, 12) .. (best.icon and " " or "") .. colored(stripLink(best.item), qColor(best.q)) end
    if #parts > 0 then parts[1] = parts[1]:sub(1, 1):upper() .. parts[1]:sub(2) end
    h:SetMeta2(table.concat(parts, SEP))
    v.heroRun = run
    pcall(h.layout)
  end

  -- open a run's page with the list's current order (Older and Newer walk it)
  v.open = function(run)
    if run.rec and not run.fights then run = Runs.view(run.rec, openRec() == run.rec, true) end
    local items, idx = {}, 1
    for i, r in ipairs(v.shown or {}) do items[i] = r; if r.id == run.id then idx = i; items[i] = run end end
    if #items == 0 or items[idx] ~= run then items, idx = { run }, 1 end
    v.selectedId = run.id
    detailView.d:Open(items, idx)
  end
  -- Back: the list as it was (its scroll is kept, since it was only hidden), the run marked
  v.restore = function(item)
    if item then v.selectedId = item.id end
    if listRebuild then listRebuild() end
  end

  -- the line under the hero's place: the instances this hour and the lockouts, each only with something to say
  v.summarySegments = function()
    local segs = {}
    local a, b = D.instanceSegment(), D.lockSegment()
    if a then segs[#segs + 1] = a end
    if b then segs[#segs + 1] = b end
    v.summary:SetSegments(segs)
    v.summaryN = #segs
    if #segs == 0 then v.summary:Hide() else v.summary:Show() end
  end

  listRebuild = function()
    local runs = D.allRuns()
    v.drops = bestDrops(runs)
    v.summarySegments()
    local rows = listRows(runs, st.inst, st.sortKey, st.sortAsc)
    v.shown = rows
    v.all = runs
    -- (no runs: nothing to filter, so no filter)
    if #runs == 0 then v.filter:Hide() else v.filter:Show() end
    if #runs == 0 then
      v.heroRun = nil
      v.hero:Hide(); v.section:Hide(); tbl.frame:Hide(); v.empty:Show()
      v.place()
      return
    end
    v.empty:Hide(); v.section:Show(); tbl.frame:Show()
    -- the hero: the newest run record the filter keeps (a partial row has no result to lead with)
    local newest
    for _, r in ipairs(rows) do if not r.legacy and (not newest or n0(r.startT) > n0(newest.startT)) then newest = r end end
    v.heroRefresh(newest)
    -- (filtered to one dungeon, the section is named after it; the screen claims no count of runs. The list is not
    -- the character's history: it starts with the oldest run stored, and the header says that day, once, 0.2.3)
    v.since = D.firstRunT(rows)
    v.sectionLabel = (st.inst or "Runs") .. (v.since and (" since " .. UI.fmtSince(v.since)) or "")
    v.section:SetLabel(v.sectionLabel)
    v.section:SetMeta(nil)
    -- A column is left out while no listed row has a value for it, or fewer than a third have one (0.3): Vs best,
    -- Bosses and Deaths are blank on the partial rows, and Vs best on a run with nothing to compare.
    local has = { vs = 0, boss = 0, death = 0, drop = 0 }
    local words = {}
    for _, r in ipairs(rows) do
      local word, wkey = vsBest(r)
      words[r] = { word, wkey }
      if word ~= "" then has.vs = has.vs + 1 end
      if not r.legacy then has.boss = has.boss + 1; has.death = has.death + 1 end
      local dr = v.drops[r.id]
      if dr and dr.best and Runs.qRank(dr.best.q) >= 2 then has.drop = has.drop + 1 end
    end
    local changed = false
    for k, n in pairs(has) do
      local hide = n == 0 or n * 3 < #rows
      if (specOf[k].hide or false) ~= hide then specOf[k].hide = hide; changed = true end
    end
    v.colHidden = { vs = specOf.vs.hide, boss = specOf.boss.hide, death = specOf.death.hide, drop = specOf.drop.hide }
    if changed then tbl.relayout(G.mainW(G.winW())) end
    v.place()
    local grouped = st.sortKey == "time"
    tbl.setRows(withDays(rows, grouped), function(row, run)
      row.run = run
      row.c.time:SetText(grouped and UI.fmtClock(run.startT) or UI.fmtDate(run.startT))
      -- (a row from before the run store carries a muted "partial": its tooltip says "Time and loot only")
      row.c.name:SetText((run.name or "?") .. (run.legacy and (" " .. colored("partial", C.fgMuted)) or ""))
      local b = badgeOf(run)
      if b then
        if not row.ebBadge then row.ebBadge = UI.Badge(row, b) end
        row.ebBadge:SetBadge(b); row.ebBadge:Show()
      elseif row.ebBadge then row.ebBadge:Hide() end
      row.c.dur:SetText(D.fmtLen(run.inside))
      -- (a cell with nothing recorded is blank, never "-" and never 0)
      local word, wkey = words[run][1], words[run][2]
      if row.c.vs then
        row.c.vs:SetText(word ~= "" and withDot(word, wkey) or "")
        UI.SetColor(row.c.vs, (wkey == "good" and "good") or (wkey == "warn" and "warn") or "fgSubtle")
      end
      if row.c.boss then row.c.boss:SetText(run.legacy and "" or bossText(run)) end
      if row.c.death then row.c.death:SetText(run.legacy and "" or tostring(deathCount(run))) end
      local worth = D.worth(run)
      row.c.worth:SetText(worth > 0 and UI.money(worth) or "")
      if row.c.drop then
        local dr = v.drops[run.id]
        local best = dr and dr.best
        if best and Runs.qRank(best.q) >= 2 then row.c.drop:SetText(stripLink(best.item)); row.c.drop:SetTextColor(unpack(qColor(best.q)))
        else row.c.drop:SetText("") end
      end
    end)
    for i = 1, tbl.shownN do
      local r = tbl.rows[i]
      if r.item and r.item.ebSection and r.ebBadge then r.ebBadge:Hide() end
      placeBadge(tbl, r)
    end
    -- the run whose page was open last is marked
    local sel
    for _, r in ipairs(rows) do if r.id == v.selectedId then sel = r end end
    tbl.setSelected(sel)
    if #rows == 0 then
      tbl.setState(("No run of %s stored."):format(st.inst or "this dungeon"), "Show all dungeons", function() v.pickInst(nil) end, true)
      v.heroRun = nil
      v.hero:Hide()
    end
    v.place()
  end
  -- (the tests and the By dungeon page switch views through the host)
  v.setView = function(key) UI.Open("Dungeons", key == "dungeons" and "bydungeon" or "runs") end
  return v
end

-- the deaths per run of each dungeon, counted the way the Runs DEATHS column counts a run (yours and the party's),
-- over the runs still stored; a dungeon with none stored keeps the statistics' own figure
-- When the oldest of these runs started (full and rebuilt rows alike): where a list of runs begins. One function
-- for the Runs header and the Leveling card, so the two never name different days. Nothing without a stored start.
function D.firstRunT(runs)
  local first
  for _, r in ipairs(runs or D.allRuns()) do
    local t = type(r) == "table" and tonumber(r.startT) or nil
    if t and t > 0 and (not first or t < first) then first = t end
  end
  return first
end
function D.deathsPerRun()
  local c = ns.char and ns.char() or nil
  local sum, n = {}, {}
  local list = {}
  for _, r in ipairs(c and type(c.dungeonRuns) == "table" and c.dungeonRuns or {}) do list[#list + 1] = r end
  for _, r in ipairs(list) do
    if type(r) == "table" and Runs.valid(r) then
      local k = Runs.keyOf(r)
      local nd = type(r.nDeaths) == "table" and r.nDeaths or {}
      sum[k], n[k] = (sum[k] or 0) + n0(nd.me) + n0(nd.party), (n[k] or 0) + 1
    end
  end
  local out = {}
  for k, s in pairs(sum) do out[k] = s / n[k] end
  return out
end

-- ══ BY DUNGEON (docs/UX_PRAGMATIC.md 2.3) ═════════════════════════════════════════════════════════════════════════
-- The page exists only once two dungeons have two stored runs each: before that a best is the only run and an
-- average is one number. Only dungeons with run records are listed (the statistics count nothing else).
function D.byVisible()
  local n = 0
  for _, d in ipairs(Runs.dungeonRows()) do if not d.other and n0(d.n) >= 2 then n = n + 1 end end
  return n >= 2
end
local function buildBy(content)
  local v = CreateFrame("Frame", nil, content); v:SetAllPoints(content)
  local st = { sortKey = nil, sortAsc = false }
  v.st = st
  local sf, child = UI.ScrollChild(v, { slim = true, top = 0, left = 0, right = 0, bottom = 0 })
  v.sf = sf
  local col = CreateFrame("Frame", nil, child); col:SetPoint("TOPLEFT", child, "TOPLEFT", 0, 0); col:SetSize(1, 1)
  v.col = col
  v.section = UI.Section(col, "Dungeons")
  local BEST_TIP = "Boss clock: first pull to last kill, on the route of your best."
  local dtbl = UI.KitTable(col, {
    { key = "name", label = "Dungeon", flex = 1, min = 140, max = 360, sort = true },
    { key = "n", label = "Runs", kind = "num", min = 40, sort = true },
    { key = "best", label = "Best", kind = "num", min = 56, sort = true, tip = BEST_TIP },
    { key = "avg", label = "Average", kind = "num", min = 56, sort = true, tip = BEST_TIP },
    { key = "dpr", label = "Deaths per run", kind = "num", min = 88, sort = true, tip = "Yours and your party's, as the Deaths column of Runs counts them" },
    { key = "worth", label = "Worth per run", kind = "money", min = 88, sort = true, tip = "Coin plus the vendor value of the items, per run" },
  }, {
    onSort = function(key, asc) st.sortKey, st.sortAsc = key, asc; v.rebuild() end,
    onHeight = function() pcall(v.place) end,
    onClick = function(row, d)
      if not d or d.other then return end
      UI.Open("Dungeons", "runs")
      if listView then listView.pickInst(d.name) end
    end,
    tooltip = function(row, d, tip)
      if not d then return end
      tip:AddLine(d.name, 1, 1, 1)
      tip:AddLine(UI.plural(d.n, "run"), 0.78, 0.79, 0.80)
      if d.other then tip:AddLine("Dungeons run least recently, counted together once 80 dungeons have numbers of their own.", 0.78, 0.79, 0.80, true)
      elseif d.best then tip:AddLine("Best and Average: " .. BEST_TIP, 0.78, 0.79, 0.80, true) end
    end })
  v.dtbl = dtbl
  v.place = function()
    local w = G.mainW(G.winW())
    col:SetWidth(w)
    local y = 0
    v.section:ClearAllPoints(); v.section:SetPoint("TOPLEFT", col, "TOPLEFT", 0, -y); v.section:SetWidth(w); y = y + H.SECTION
    dtbl.frame:ClearAllPoints(); dtbl.frame:SetPoint("TOPLEFT", col, "TOPLEFT", 0, -y); dtbl.frame:SetWidth(w)
    if dtbl.width ~= math.min(w, G.TABLE_MAX) then dtbl.relayout(w) end
    y = y + (dtbl.height or 0) + S.S4
    col:SetHeight(y); sf:SetContentHeight(y)
    v.contentH = y
  end
  content:HookScript("OnSizeChanged", function() pcall(v.place) end)
  local VAL = {
    name = function(d) return (d.name or ""):lower() end, n = function(d) return n0(d.n) end,
    best = function(d) return d.best or 1e12 end, avg = function(d) return (n0(d.n) >= 2 and d.avg) or 1e12 end,
    dpr = function(d) return n0(d.deathsPerRun) end, worth = function(d) return n0(d.worthPerRun) end,
    last = function(d) return n0(d.last) end,
  }
  v.rebuild = function()
    local rows = Runs.dungeonRows()
    local dpr = D.deathsPerRun()
    for _, d in ipairs(rows) do if dpr[d.key] then d.deathsPerRun = dpr[d.key] end end
    -- (the dungeon run last comes first until a column is picked)
    local key = st.sortKey or "last"
    local asc = st.sortKey and st.sortAsc or false
    if st.sortKey then dtbl.setSort(key, asc) end
    local val = VAL[key] or VAL.last
    table.sort(rows, function(a, b)
      if a.other ~= b.other then return b.other end
      local x, y = val(a), val(b)
      if x ~= y then if asc then return x < y end return x > y end
      return n0(a.last) > n0(b.last)
    end)
    v.dshown = rows
    v.section:SetMeta(nil)
    dtbl.setRows(rows, function(row, d)
      row.drow = d
      row.c.name:SetText(d.name .. (d.kind == "raid" and " (raid)" or ""))
      row.c.n:SetText(tostring(d.n))
      row.c.best:SetText(d.best and UI.fmtDur(d.best) or "")
      -- (an average of one run is that run: shown from two)
      row.c.avg:SetText((d.avg and n0(d.n) >= 2) and UI.fmtDur(d.avg) or "")
      -- (one decimal from two runs, the plain count for one)
      row.c.dpr:SetText(n0(d.n) >= 2 and ("%.1f"):format(n0(d.deathsPerRun)) or tostring(math.floor(n0(d.deathsPerRun) + 0.5)))
      row.c.worth:SetText(n0(d.worthPerRun) > 0 and UI.money(math.floor(d.worthPerRun)) or "")
      row.item.ebNoOpen = d.other or nil
    end)
    if #rows == 0 then dtbl.setState("No run stored yet.") end
    v.place()
  end
  return v
end

-- ══ the host ═══════════════════════════════════════════════════════════════════════════════════════════════════════
local ticker
UI.registerHost(1, "Dungeons", "Every dungeon run against your best, and which dungeon is worth your time.")
UI.registerPane("Dungeons", 1, "Runs", function(content)
  local list = buildList(content)
  listView = list
  detailView = buildDetail(content, list)
end, function()
  if detailView and detailView:IsShown() then return end
  if listRebuild then listRebuild() end
  if not ticker then
    -- both only while the pane is on screen: a closed window or another pane leaves the frames' own flags set
    ticker = C_Timer.NewTicker(3, function()
      if onScreen(listView) and listRebuild then listRebuild() end
    end)
    -- the page of the run in progress, and the hero of a run in progress, tick every second
    C_Timer.NewTicker(1, function()
      if onScreen(detailView) and detailView.refresh then pcall(detailView.refresh) end
      if onScreen(listView) and listView.heroRun and listView.heroRun.inProgress and listView.hero:IsShown() then
        local rec = openRec()
        if rec and rec.id == listView.heroRun.id then pcall(listView.heroRefresh, Runs.view(rec, true, false)) end
      end
    end)
  end
end, "Your dungeon runs against your best: time, bosses, deaths, loot and XP.")
UI.registerPane("Dungeons", 2, "By dungeon", function(content)
  byView = buildBy(content)
end, function() if byView then byView.rebuild() end end,
  "Your dungeons side by side: runs, best, average, deaths and worth per run.", function() return D.byVisible() end)

-- the runs of the logged-in character as the Fights list groups by them, oldest first: the light read (name, start,
-- bosses down, deaths and the record), nothing from the statistics (its list is drawn again every 2 s)
ns.DungeonRuns = function() return Runs.views(true, true) end   -- (light, with each run's fights for the group rows)

-- open a run's page from anywhere (a view, or a stored record: WORTH A LOOK and the lockout link pass a record)
local function openRun(run)
  if type(run) ~= "table" then return end
  if not listView then UI.Open("Dungeons", "runs") end
  if not listView then return end
  if run.secs and run.inst and not run.rec then
    local rec = run
    run = Runs.view(rec, openRec() == rec, true)
  elseif run.rec and not run.fights then
    run = Runs.view(run.rec, openRec() == run.rec, true)
  end
  if listRebuild and not listView.shown then pcall(listRebuild) end
  listView.open(run)
end
ns.Dungeons.openRun = openRun
ns.Dungeons.D = D

-- ── test exports: headless luajit tests in tests/ read these; no effect in-game ──
ns._test = ns._test or {}
ns._test.runViews = function(full) return Runs.views(full) end
ns._test.dungeonsLockText = function() local sg = D.lockSegment(); return sg and sg.text or nil end
ns._test.renderRun = function(run) if detailView then detailView.render(run) end end
ns._test.dungeonDetail = function() return detailView end
ns._test.dungeonList = function() if listRebuild then listRebuild() end; return listView end
ns._test.dungeonBy = function() if byView then byView.rebuild() end; return byView end
ns._test.openRun = function(run) openRun(run) end
