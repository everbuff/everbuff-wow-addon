-- Everbuff.GG · Dungeons.lua - the Dungeons host: Runs (every run against your best), By dungeon (which dungeon is
-- worth your time) and the run page (docs/UX_OVERHAUL.md 4.5 to 4.7).
--
-- A classic player thinks in RUNS: enter, clear, leave. From 0.9.50 a run is a stored record of the character
-- (Runs.lua: characters[guid].dungeonRun and dungeonRuns), so the list survives the desktop's acknowledgement and
-- the story event cap. These panes only read, except the run page's own edits (keep, end, join, split, delete).
-- Every page is built from the kit in UI.lua: one scroll per page, the summary line first, then the answer.

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
-- the one way a pull-to-kill time is named, on the run page, on Runs and on By dungeon
function D.pullMeta(m) return UI.fmtDur(m) .. " first pull to last kill" end

-- ══ the facts of a run, as every surface says them ═══════════════════════════════════════════════════════════════
-- the bosses a run is counted against: the dungeon's learned list, else the most bosses any stored run of the
-- dungeon met (pulled or killed) or its lockout names. A run in progress has met only the bosses so far, so its own
-- rows alone would say "1 of 1".
local function knownTotal(name)
  if type(name) ~= "string" then return 0 end
  local c = ns.char and ns.char() or nil
  local n = 0
  local runs = c and type(c.dungeonRuns) == "table" and c.dungeonRuns or {}
  for _, r in ipairs(runs) do
    if type(r) == "table" and r.inst == name and type(r.bosses) == "table" then n = math.max(n, #r.bosses) end
  end
  for _, l in ipairs(c and type(c.lockouts) == "table" and c.lockouts or {}) do
    if type(l) == "table" and l.name == name then n = math.max(n, n0(l.bosses)) end
  end
  return n
end
local function totalOf(run)
  -- (the most the run, its dungeon's learned list, its other runs and its lockout know of: the total is never the
  -- kills alone when an encounter was left up, B1)
  return math.max(n0(run.total), #(run.bosses or {}) + #(run.missing or {}), n0(run.bossesDown), knownTotal(run.name))
end
D.totalOf = totalOf
-- "2/4", always with the total (table cells); D.bossCount(run) "2 of 4" (cards and heroes)
local function bossText(run) return ("%d/%d"):format(n0(run.bossesDown), totalOf(run)) end
D.bossText = bossText
function D.bossCount(run) return ("%d of %d"):format(n0(run.bossesDown), totalOf(run)) end
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
--   "first run"      no earlier run of this dungeon by this character
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
  if cmp.first then return "first run", nil, "first" end
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
  local down = n0(run.bossesDown)
  local total = totalOf(run)
  if total == 0 then return "no boss killed" end
  local s = ("%d of %s"):format(down, UI.plural(total, "boss"))
  local missed = missedNames(run)
  -- (a full clear needs the dungeon's learned list: before it, the bosses a run met are not all there are)
  if down >= total and #missed == 0 then return run.total and (s .. ", full clear") or s end
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
-- the item count every surface of a run shows (the card, the LOOT section, the Runs row): the rows the section
-- lists, or the run's own count when the loot log no longer holds its rows
local function itemCount(run, items) return (items and #items > 0) and #items or n0(run.items) end
D.itemCount = itemCount
-- the best drop of every stored run, worked out once per change of the loot log or the runs (the list draws every
-- run again every 3 s)
D.dropCache = { key = nil, byId = {} }
D.BAG_ICON = "Interface\\Icons\\INV_Misc_Bag_08"
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
local SAVED_BEFORE = "Saved before Everbuff recorded this dungeon on this character."
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
    if #L == 0 then tip:AddLine("This character is not saved to any instance.", 0.78, 0.79, 0.80, true) end
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
  if #L == 0 then return { text = "No lockouts", tip = tip } end
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
    return { text = ("**%d** %s this hour"):format(h, h == 1 and "instance" or "instances"), tip = tip, hour = h }
  end
  local left = lim - h
  if left <= 0 then return { text = "No instances left this hour" .. (nextFree and (", next free in " .. nextFree) or ""), color = "bad", dot = "bad", tip = tip, hour = h } end
  if left == 1 then return { text = "**1** instance left this hour" .. (nextFree and (", next free in " .. nextFree) or ""), color = "warn", dot = "warn", tip = tip, hour = h } end
  return { text = ("**%d of %d** instances left this hour"):format(left, lim), tip = tip, hour = h }
end

-- ══ RUN PAGE (4.6) ════════════════════════════════════════════════════════════════════════════════════════════════
-- Drawn into the detail page's scroll child: the title and its badges, the META line, the stat cards (4, or 6 at
-- WIDE), then the sections in their fixed order. Every section shows, an empty one with its sentence.
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
  v.cards4 = UI.StatRow(col, 4)
  v.cards6 = UI.StatRow(col, 6)
  v.sections, v.lines, v.tables, v.btns = {}, {}, {}, {}
  local SECTION_KEYS = { "bosses", "loot", "deaths", "xp", "party", "pace", "visits", "pulls", "edit" }
  local LABELS = { bosses = "Bosses", loot = "Loot", deaths = "Deaths", xp = "XP", party = "Party", pace = "Pace",
    visits = "Entered and left", pulls = "All fights in this run", edit = "Edit this run" }
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
    { key = "at", label = "Killed at", kind = "num", min = 64, measure = { "1h 59m" } },
    { key = "since", label = "Since last boss", kind = "num", min = 104 },
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
    { key = "src", label = "From", kind = "tag", min = 120, max = 160 },
    { key = "price", label = "Vendor price", kind = "money", min = 80 },
  }, { chevron = "reserve", tooltip = function(row, item, tip)
      local l = item.row
      tip:AddLine(stripLink(l.item), unpack(qColor(l.q)))
      if l.src then tip:AddLine("From " .. stripLink(l.src), 0.78, 0.79, 0.80, true) end
      tip:AddLine(UI.fmtWhen(l.t), 0.78, 0.79, 0.80)
      if item.price <= 0 then tip:AddLine("Vendor price not known: the game had not loaded this item yet.", 0.78, 0.79, 0.80, true) end
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

  -- what a second changes on the page of a run in progress: the TIME card and the two clock lines
  local live = {}
  local function clocks(run)
    if live.time then live.time.value:SetText(UI.fmtDur(run.inside)) end
    -- (a view built by hand can lack a clock: every missing one is 0)
    local cl = {}
    for _, k in ipairs({ "inside", "ghost", "outside", "offline", "active", "combat", "boss" }) do cl[k] = n0(run[k]) end
    local a, b = Runs.timeLine(cl)
    v.timeLine, v.timeLine2 = (a:gsub("  \194\183  ", SEP)), (b:gsub("  \194\183  ", SEP))
    if live.line1 then live.line1:SetText(v.timeLine) end
    if live.line2 then live.line2:SetText(v.timeLine2) end
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
    if kind == "best" then badges[#badges + 1] = "BEST" elseif kind == "first" then badges[#badges + 1] = "FIRST RUN" end
    if run.keep then badges[#badges + 1] = "KEPT" end
    local title = (run.name or "Dungeon") .. (run.kind == "raid" and " (raid)" or "")
    v.titleFS:ClearAllPoints(); v.titleFS:SetPoint("TOPLEFT", col, "TOPLEFT", S.S3, 0); v.titleFS:SetText(title)
    local bw = 0
    for i, t in ipairs(badges) do local b = v.badges[i] or UI.Badge(col, t); v.badges[i] = b; b:SetBadge(t); b:Show(); bw = bw + b:GetWidth() + S.S2 end
    for i = #badges + 1, #v.badges do v.badges[i]:Hide() end
    local tw = math.min(UI.TextWidth("TITLE", title), W - 2 * S.S3 - bw)
    v.titleFS:SetWidth(math.max(1, tw))
    -- (badges on the title line's vertical centre)
    local bx = 0
    for i = 1, #badges do v.badges[i]:ClearAllPoints(); v.badges[i]:SetPoint("LEFT", v.titleFS, "RIGHT", bx + S.S2, 0); bx = bx + S.S2 + v.badges[i]:GetWidth() end
    local meta = { run.inProgress and (UI.fmtDate(run.startT) .. " since " .. UI.fmtClock(run.startT)) or (UI.fmtWhen(run.startT) .. (run.endT and (" to " .. UI.fmtClock(run.endT)) or "")) }
    local x1 = type(run.xp) == "table" and run.xp or {}
    if x1.l0 then meta[#meta + 1] = "level " .. math.floor(x1.l0) end
    local grp = run.group and #run.group or 0
    meta[#meta + 1] = grp > 1 and ("party of " .. grp) or "solo"
    if n0(run.reentries) > 0 then meta[#meta + 1] = ("re-entered %s"):format(UI.plural(run.reentries, "time")) end
    if run.edited then meta[#meta + 1] = "corrected by hand" end
    v.metaFS:ClearAllPoints(); v.metaFS:SetPoint("TOPLEFT", col, "TOPLEFT", S.S3, -22); v.metaFS:SetWidth(W - 2 * S.S3)
    v.metaFS:SetText(table.concat(meta, SEP))
    v.metaText = v.metaFS:GetText()
    y = 48
    -- the cards: TIME, VS YOUR BEST, BOSSES, DEATHS (and XP, LOOT at WIDE)
    local wide = G.isWide(G.winW())
    local row = wide and v.cards6 or v.cards4
    v.cards4:Hide(); v.cards6:Hide(); row:Show()
    put(row, H.STAT); pcall(row.layout)
    local cards = row.cards
    v.cards = cards
    live.time = cards[1]
    cards[1]:Set("Time", UI.fmtDur(run.inside), run.inProgress and "inside, so far" or "inside")
    UI.SetTip(cards[1], function(tip)
      tip:AddLine("Time", 1, 1, 1)
      tip:AddLine("Time inside the dungeon. " .. (v.clockSentence or ""), 0.78, 0.79, 0.80, true)
      for _, l in ipairs(v.timeTipLines()) do tip:AddLine(l, 0.78, 0.79, 0.80) end
    end)
    local m = Runs.measure(run.rec or {})
    local cmp = run.cmp or {}
    local vsVal = word ~= "" and word or nil
    if kind == "first" then vsVal = "first run" end
    -- (one meta string everywhere: "28m 41s first pull to last kill", D.pullMeta)
    local vsMeta = m and D.pullMeta(m) or "no boss killed"
    -- (on a card too narrow for the whole string the time stays and the words go to the hover, never cut)
    local fullMeta = vsMeta
    if m and UI.TextWidth("META", vsMeta) > (tonumber(cards[2]:GetWidth()) or 0) - 2 * S.S3 then vsMeta = UI.fmtDur(m) end
    local routeNames = {}
    for _, b in ipairs(run.bosses or {}) do if b.kill then routeNames[#routeNames + 1] = b.name or "Boss" end end
    if vsVal then
      cards[2]:Set("Vs your best", vsVal, vsMeta, (wkey == "good" and "good") or (wkey == "warn" and "warn") or "fg")
      if wkey == "warn" then cards[2].value:SetText(withDot(vsVal, "warn", UI.DOT_SIZE.DISPLAY)) end
      UI.SetTip(cards[2], { title = "Vs your best", text = ("%s. Against your fastest run that killed these %s: %s."):format(fullMeta:sub(1, 1):upper() .. fullMeta:sub(2), UI.plural(#routeNames, "boss"), fitNames(routeNames, 260)) })
    else
      -- (nothing to compare with yet: said in words at TITLE size, never a lone "-")
      cards[2]:Set("Vs your best", "No best yet", vsMeta, "fgMuted")
      cards[2].value:SetFont(UI.F.TITLE.ebFile, UI.F.TITLE.ebSize)
      UI.SetTip(cards[2], { title = "Vs your best", text = "Kill the same bosses in another run to compare." })
    end
    v.deltaText = vsVal or "No best yet"
    local missed = missedNames(run)
    local left = totalOf(run) - n0(run.bossesDown)
    local bossMeta
    if run.inProgress then bossMeta = left > 0 and (UI.fmtNum(left) .. " left") or "all down"
    elseif run.total and #missed == 0 and n0(run.bossesDown) >= run.total then bossMeta = "full clear"
    else bossMeta = #missed > 0 and ("missed " .. #missed) or "" end
    cards[3]:Set("Bosses", D.bossCount(run), bossMeta)
    local names = deathNames(run)
    cards[4]:Set("Deaths", tostring(deathCount(run)), deathCount(run) == 0 and "clean run" or (#names > 0 and fitNames(names, 120) or ""))
    if wide then
      cards[5]:Set("XP", UI.fmtNum(n0(run.xpGain)), run.xpPerHour and (UI.fmtNum(run.xpPerHour) .. " per hour") or "")
      -- (the coin is the value, the items its meta: Runs names the coin COIN LOOTED and the items LOOT)
      local nIt = itemCount(run, runItems(run))
      if n0(run.coin) == 0 and nIt == 0 then cards[6]:Set("Coin looted", "-", "nothing yet")
      else cards[6]:Set("Coin looted", n0(run.coin) > 0 and UI.money(n0(run.coin)) or "-", UI.plural(nIt, "item")) end
    end
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
    local function empty(s, color)
      local fs = line("BODY", color or "fgMuted")
      fs:ClearAllPoints(); fs:SetPoint("TOPLEFT", col, "TOPLEFT", S.S3, -(y + 4)); fs:SetWidth(W - 2 * S.S3); fs:SetText(s)
      y = y + H.SECTION
      return fs
    end
    local function tableAt(tbl, items, fill)
      tbl.frame:Show()
      put(tbl.frame)
      tbl.relayout(W)
      tbl.setRows(items, fill)
      y = y + (tbl.height or 0)
    end
    for _, t in pairs(v.tables) do t.frame:Hide() end
    v.empties = {}

    -- 1 BOSSES: one row per boss in pull order, then the learned list's bosses never pulled
    local bosses = run.bosses or {}
    local byUid = {}
    for _, f in ipairs(run.fights or {}) do if type(f.uid) == "string" then byUid[f.uid] = f end end
    local bossSec = section("bosses", totalOf(run) > 0 and D.bossCount(run) or nil)
    local brows = {}
    -- (the best run and a first run are their own best: no delta to show)
    -- (a run that is not the best: each boss against the best's split. The best run: against the next fastest run of
    -- the same bosses. A run nothing compares with leaves the column out and says so once in the section META.)
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
      local sp = run.splits and run.splits[b.enc]
      brows[#brows + 1] = { name = b.name or "Boss", kill = b.kill, n = order[b], since = sp and sp.seg, d = b.kill and vs[b.enc], len = b.combat, tip = tip,
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
    -- (never a column of dashes: with no boss to compare, the column goes and the META says why once)
    local anyVs = false
    for _, it in ipairs(brows) do if it.d then anyVs = true end end
    v.tables.bosses.spec[5].hide = not anyVs
    v.bossVsShown = anyVs
    if not anyVs and #brows > 0 then
      bossSec:SetMeta((totalOf(run) > 0 and D.bossCount(run) .. SEP or "") .. (run.inProgress and "nothing to compare yet" or "no other run of these bosses yet"))
    end
    if #brows == 0 then v.empties.bosses = empty("No boss pulled in this run.")
    else
      tableAt(v.tables.bosses, brows, function(r, it)
        local dim = not it.kill
        r.c.n:SetText(it.n and tostring(it.n) or "-")
        r.c.boss:SetText(it.name); UI.SetColor(r.c.boss, dim and "fgMuted" or "fg")
        r.c.at:SetText(it.kill and UI.fmtDur(it.kill) or "-")
        r.c.since:SetText(it.since and UI.fmtDur(it.since) or "-")
        if it.d then local w2, k2 = UI.fmtDelta(it.d); r.c.vs:SetText(withDot(w2, k2)); UI.SetColor(r.c.vs, k2 or "fgSubtle") else r.c.vs:SetText(it.next and "next" or "-") end
        if it.kill then r.c.len:SetText(n0(it.len) > 0 and UI.fmtDur(it.len) or "-")
        elseif n0(it.len) > 0 then
          -- (pulled and not killed: what happened, then how long it lasted; a wipe is an event result)
          if it.wiped then r.c.len:SetText(withDot("wipe, " .. UI.fmtDur(it.len), "bad")); UI.SetColor(r.c.len, "bad")
          else r.c.len:SetText("not killed, " .. UI.fmtDur(it.len)); UI.SetColor(r.c.len, "fgMuted") end
        else r.c.len:SetText("-") end
        for _, k in ipairs({ "n", "at", "since", "vs", "len" }) do if r.c[k]:GetText() == "-" or r.c[k]:GetText() == "next" then UI.SetColor(r.c[k], "fgMuted") end end
      end)
    end
    y = y + S.S5

    -- 2 LOOT: the items of the run (green and better), then the coin
    local items = runItems(run)
    v.lootItems = items
    -- (the row prices and the footer total are one source: the vendor price of each row's stack)
    local priced, unpriced = 0, 0
    for _, it in ipairs(items) do
      if it.price > 0 then priced = priced + it.price * math.max(1, n0(it.row.count)) else unpriced = unpriced + 1 end
    end
    local nItems = itemCount(run, items)
    section("loot", nItems > 0 and UI.plural(nItems, "item") or nil)
    if #items == 0 and nItems > 0 then v.empties.loot = empty(UI.plural(nItems, "item") .. " looted. Their rows are no longer stored.")
    elseif #items == 0 then v.empties.loot = empty("Nothing looted.")
    else
      tableAt(v.tables.loot, items, function(r, it)
        local l = it.row
        -- (the stack count in fgMuted right after the name, as Loot > Auctions writes it)
        r.c.ic:SetTexture(l.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        r.c.item:SetText(stripLink(l.item) .. (n0(l.count) > 1 and (" " .. colored("x" .. l.count, C.fgMuted)) or ""))
        r.c.item:SetTextColor(unpack(qColor(l.q)))
        r.c.src:SetText(l.src and stripLink(l.src) or "-")
        r.c.price:SetText(it.price > 0 and UI.money(it.price * math.max(1, n0(l.count))) or "-")
        if it.price <= 0 then UI.SetColor(r.c.price, "fgMuted") end
      end)
    end
    local g = run.gold or {}
    -- (a zero coin line is filler: it shows only when there is coin or a priced item to name)
    local coinParts = {}
    if n0(g.looted) > 0 then coinParts[#coinParts + 1] = "Coin looted " .. UI.money(n0(g.looted)) end
    if n0(g.quests) > 0 then coinParts[#coinParts + 1] = "quest rewards " .. UI.money(g.quests) end
    -- ("known" only when a row's price is not known: the run's gold block counts the items it could not price; a row
    -- at 0 with no such count is an item no vendor buys)
    local unknown = n0(g.unpriced) > 0 or (g.lootValue == nil and unpriced > 0)
    -- (with no row left in the loot log there is no row price to disagree with: the gold block's own value)
    if #items == 0 and n0(g.lootValue) > 0 then priced = n0(g.lootValue) end
    if priced > 0 then coinParts[#coinParts + 1] = (unknown and "vendor price of known items " or "vendor price of items ") .. UI.money(priced) end
    if run.coinPerHour and n0(run.coin) > 0 then coinParts[#coinParts + 1] = UI.money(math.floor(run.coinPerHour), true) .. " per hour" end
    if #coinParts > 0 then coinParts[1] = coinParts[1]:sub(1, 1):upper() .. coinParts[1]:sub(2) end
    v.lootLine = #coinParts > 0 and table.concat(coinParts, SEP) or nil
    v.lootFS = nil
    if v.lootLine then
      y = y + S.S1
      v.lootFS = text(line("META", "fgMuted"), v.lootLine)
    end
    v.purseLine = run.gold and Runs.purseLine(run) or nil
    v.purseFS = nil
    if v.purseLine then v.purseFS = text(line("META", "fgMuted"), v.purseLine) end
    y = y + S.S5 - S.S1

    -- 3 DEATHS: the character's own, and the party's when the run recorded them
    section("deaths", deathCount(run) > 0 and UI.plural(deathCount(run), "death") or nil)
    local drows = run.deathRows or {}
    v.deathRows = drows
    if #drows == 0 and deathCount(run) == 0 then v.empties.deaths = empty("Nobody died. Clean run.")
    elseif #drows == 0 then v.empties.deaths = empty(UI.plural(deathCount(run), "death") .. " in this run. The game did not say who killed whom.")
    else
      local anyBack = false
      for _, dd in ipairs(drows) do if dd.back then anyBack = true end end
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
        r.c.foe:SetText(dd.foe or "-"); if not dd.foe then UI.SetColor(r.c.foe, "fgMuted") end
        local where = type(dd.sub) == "string" and dd.sub ~= "" and dd.sub or (dd.enc and bossNo[dd.enc] and ("at boss " .. bossNo[dd.enc])) or nil
        if where == dd.foe then where = nil end
        r.c.where:SetText(where or "-"); if not where then UI.SetColor(r.c.where, "fgMuted") end
        r.c.back:SetText(dd.back and UI.fmtDur(dd.back) or (anyBack and "-" or ""))
      end)
      if deathCount(run) > #drows then text(line("META", "fgMuted"), ("and %d more"):format(deathCount(run) - #drows)) end
    end
    y = y + S.S5

    -- 4 XP: what the run paid, kills and quests apart, then the rate and the levels
    section("xp", nil)
    local xa, xb, xc = nil, nil, nil
    if run.xp then xa, xb, xc = Runs.xpLine(run) end
    local xp = type(run.xp) == "table" and run.xp or nil
    v.xpFS = {}
    if xp and n0(run.xpGain) > 0 then
      local quest, kill = n0(xp.quest), math.max(0, n0(run.xpGain) - n0(xp.quest))
      local main = UI.fmtNum(run.xpGain) .. " XP"
      if quest > 0 and kill > 0 then main = main .. (": %s from kills, %s from quests"):format(UI.fmtNum(kill), UI.fmtNum(quest))
      elseif quest > 0 then main = main .. ", all from quests" else main = main .. ", all from kills" end
      v.xpLine = main
      v.xpFS[1] = text(line("BODY", "fg"), main, UI.LINE_H.BODY + S.S1)
      -- the rest of Runs.xpLine: the rate, the levels and the runs to the next level
      local rest = {}
      for part in tostring(xa or ""):gmatch("[^\194\183]+") do
        part = part:gsub("^%s+", ""):gsub("%s+$", "")
        if part ~= "" and not part:find(" XP$") then rest[#rest + 1] = part end
      end
      -- (and the kills the client let the addon read: "at least 45 kills" when it hid XP lines)
      local k = xb and xb:match("([%w ,]*kills?)$")
      if k then rest[#rest + 1] = (k:gsub("^%s+", "")) end
      v.xpMore = #rest > 0 and table.concat(rest, SEP) or nil
      if v.xpMore then v.xpFS[#v.xpFS + 1] = text(line("META", "fgMuted"), v.xpMore) end
      v.xpHidden = xc
      if xc then v.xpFS[#v.xpFS + 1] = text(line("META", "fgMuted"), xc) end
    else
      v.xpLine, v.xpMore, v.xpHidden = nil, nil, nil
      v.empties.xp = empty((ns.Now and ns.Now.atMax and ns.Now.atMax()) and "Max level: no XP to earn." or "No XP in this run.")
    end
    y = y + S.S5

    -- 5 PARTY: the largest group a pull of the run recorded, in class colours
    section("party", grp > 1 and UI.plural(grp, "player") or nil)
    if grp > 1 then
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
    else v.partyFS = nil; v.empties.party = empty(run.fights and #run.fights > 0 and "You ran it alone." or "No fight of this run is stored, so the party is not known.") end
    y = y + S.S5

    -- 6 PACE: against the best of the route
    section("pace", nil)
    local p1, p2 = D.paceLines(run)
    v.paceLine, v.paceLine2 = p1, p2
    if p1 then
      text(line("BODY", "fg"), p1, UI.LINE_H.BODY + S.S1)
      if p2 then text(line("META", "fgMuted"), p2) end
    else v.empties.pace = empty("Kill the same bosses twice to see your pace.") end
    y = y + S.S5

    -- 7 ENTERED AND LEFT: where the time went, then one row per visit (Split here where a run can be split)
    section("visits", UI.plural(#(run.visits or {}), "visit"))
    live.line1 = text(line("BODY", "fg"), "", UI.LINE_H.BODY + S.S1)
    live.line2 = text(line("META", "fgMuted"), "")
    clocks(run)
    v.timeFS = { live.line1, live.line2 }
    y = y + S.S1
    local visits = run.visits or {}
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

    -- 8 ALL FIGHTS IN THIS RUN: the fights still stored, the same list Home > Fights groups under the run (A21, B23)
    v.encounters = #(run.fights or {})
    section("pulls", v.encounters > 0 and UI.plural(v.encounters, "fight") or nil)
    if v.encounters == 0 then v.empties.pulls = empty("No fight of this run is stored any more. The desktop app saved them.")
    else
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
    end
    y = y + S.S5

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
    for k, sec in pairs(v.sections) do if not sec:IsShown() then sec:Hide() end end
    y = y + S.S4
    col:SetHeight(y)
    v.sf:SetContentHeight(y)
    v.contentH = y
    v.sigLists, v.sigPage = nil, nil
    if run.inProgress and type(run.rec) == "table" then v.sigLists, v.sigPage = v.signature(run.rec) end
  end
  -- the clocks of the TIME tooltip, as one sentence
  v.clockSentence = nil
  local baseRender = v.render
  v.render = function(run)
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
  boss = function(r) return n0(r.bossesDown) end,
  death = function(r) return deathCount(r) end,
  xp = function(r) return n0(r.xpGain) end,
  coin = function(r) return n0(r.coin) end,
  xph = function(r) return n0(r.xpPerHour) end,
  loot = function(r) return n0(r.items) end,
}
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
-- the rows with their day rows ("TODAY · 1 RUN") while the list is in time order
local function withDays(rows, grouped)
  if not grouped then return rows end
  local out, i = {}, 1
  while i <= #rows do
    local day = UI.fmtDay(rows[i].startT)
    local j = i
    while j + 1 <= #rows and UI.fmtDay(rows[j + 1].startT) == day do j = j + 1 end
    out[#out + 1] = { ebSection = day .. SEP .. UI.plural(j - i + 1, "run") }
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
  -- the LOOT cell: the best drop's icon as its own 20 px texture at the column's left edge, centred on the row, and
  -- "+N" after it on the BODY line of the other cells (never an inline |T|t in a 12 px line)
  local lc, lf, ic = tbl.cols and tbl.cols.loot, row.c and row.c.loot, row.ebLootIc
  if lc and lf then
    lf:ClearAllPoints()
    if ic and ic:IsShown() and not (row.item and row.item.ebSection) then
      ic:ClearAllPoints(); ic:SetPoint("LEFT", row, "LEFT", lc.x, 0)
      lf:SetPoint("LEFT", ic, "RIGHT", S.S1, 0); lf:SetWidth(math.max(1, lc.w - 20 - S.S1))
    else
      if ic then ic:Hide() end
      lf:SetPoint("LEFT", row, "LEFT", lc.x, 0); lf:SetWidth(lc.w)
    end
  end
end
local function badgeOf(run)
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
  v.empty = UI.Empty(col, { icon = "Interface\\Icons\\INV_Misc_Map_01", title = "No dungeon runs yet",
    text = "Enter any dungeon and your run is recorded: time, bosses, deaths, loot and XP, against your best." })
  v.empty:Hide()
  v.section = UI.Section(col, "All runs")
  -- the dungeon filter: a filter button at the right of the control row
  local controls = content.ebControls or v
  v.filter = UI.FilterButton(controls, { default = "", label = "All dungeons",
    items = function()
      local names, seen = {}, {}
      for _, r in ipairs(Runs.views(nil, true)) do
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
    { key = "name", label = "Dungeon", flex = 1, min = 140, max = 360, sort = true },
    { key = "dur", label = "Time", kind = "num", min = 56, sort = true, tip = "Time inside the dungeon, entrance to exit" },
    { key = "vs", label = "Vs best", kind = "tag", min = 88, justify = "RIGHT", sort = true, tip = "Against your fastest run with the same bosses, first pull to last kill" },
    { key = "boss", label = "Bosses", kind = "num", min = 40, sort = true },
    { key = "death", label = "Deaths", kind = "num", min = 48, sort = true },
    { key = "xp", label = "XP", kind = "num", min = 56, wide = true, sort = true },
    { key = "coin", label = "Coin looted", kind = "money", min = 72, wide = true, sort = true },
    { key = "xph", label = "XP per hour", kind = "num", min = 64, wide = true, sort = true },
    { key = "loot", label = "Loot", kind = "tag", min = 72, sort = true, measure = { "99 items" } },
  }
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
    local out = { "Inside " .. UI.fmtDur(run.inside) }
    if n0(run.ghost) > 0 then out[#out + 1] = "Run back " .. UI.fmtDur(run.ghost) end
    if n0(run.outside) > 0 then out[#out + 1] = "Outside " .. UI.fmtDur(run.outside) end
    if n0(run.offline) > 0 then out[#out + 1] = "Offline " .. UI.fmtDur(run.offline) end
    out[#out + 1] = "Active " .. UI.fmtDur(run.active)
    if run.inProgress then out[#out + 1] = "In progress" else out[#out + 1] = "Ended: " .. (Runs.WHY[run.why] or "left the dungeon") end
    if run.edited then out[#out + 1] = "Corrected by hand" end
    if run.repull then out[#out + 1] = "Possibly two runs: a boss killed before was pulled again" end
    if run.keep then out[#out + 1] = "Kept: never removed when the list is full" end
    if n0(run.reentries) > 0 then out[#out + 1] = "Re-entered " .. UI.plural(run.reentries, "time") end
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
    if n0(run.xpGain) > 0 then out[#out + 1] = UI.fmtNum(run.xpGain) .. " XP" .. (run.xpPerHour and (SEP .. UI.fmtNum(run.xpPerHour) .. " XP per hour") or "") end
    local drop = v.drops and v.drops[run.id]
    if drop then
      for i, it in ipairs(drop.items) do
        if i > 4 then out[#out + 1] = ("and %d more"):format(#drop.items - 4); break end
        out[#out + 1] = colored(stripLink(it.row.item), qColor(it.row.q)) .. (n0(it.row.count) > 1 and (" x" .. it.row.count) or "")
      end
    end
    out[#out + 1] = "Coin looted " .. UI.money(n0(run.coin))
    return out
  end

  -- lay the page out: summary, hero, ALL RUNS and the list (or the big empty state), one scroll
  v.place = function()
    local w = G.mainW(G.winW())
    col:SetWidth(w)
    local y = 0
    local function put(f, h) f:ClearAllPoints(); f:SetPoint("TOPLEFT", col, "TOPLEFT", 0, -y); f:SetWidth(w); if h then f:SetHeight(h) end end
    put(v.summary, H.SUMMARY); pcall(v.summary.layout); y = y + H.SUMMARY + S.S3
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
    if not run then h:Hide(); return end
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
      else verdict = UI.fmtDur(run.inside) .. " so far" end
      -- (META never repeats the HERO line: the start, then the bosses)
      h:SetMeta("Since " .. UI.fmtClock(run.startT) .. SEP .. bossLine(run, w - 200), nil)
      -- (the run in progress opens its page as every other run does, A10; a ghost: no primary while it runs)
      h:SetButton("Open run", function() v.open(run) end, "ghost")
    else
      if kind == "first" then
        local total = totalOf(run)
        verdict = (total > 0 and (D.bossCount(run) .. " bosses") or "No boss killed") .. " in " .. UI.fmtDur(run.inside)
      elseif kind == "best" then
        if word == "best" then verdict = (cmp.runs and cmp.runs > 1) and "Your best for these bosses" or "No best for these bosses yet"
        else verdict, vkey = word .. " than your best", wkey end
      elseif kind == "slower" then
        if word == "same as best" then verdict = "Same as your best" else verdict, vkey = word .. " than your best", wkey end
      else verdict = n0(run.bossesDown) == 0 and "No boss killed" or "No best for these bosses yet" end
      if kind == "first" then
        -- (the HERO has the count and the time: META has the day, the word and what was missed)
        local missed = missedNames(run)
        local tail = #missed > 0 and ("missed " .. fitNames(missed, math.max(80, w - 260))) or (run.total and n0(run.bossesDown) >= run.total and "full clear" or nil)
        h:SetMeta(UI.fmtWhen(run.startT) .. SEP .. "first run" .. (tail and (SEP .. tail) or ""), nil)
      else
        h:SetMeta(UI.fmtWhen(run.startT) .. SEP .. UI.fmtDur(run.inside) .. SEP .. bossLine(run, w - 200), nil)
      end
      h:SetButton("Open run", function() v.open(run) end)
    end
    verdict = verdict:sub(1, 1):upper() .. verdict:sub(2)
    h:SetHero(withDot(verdict, vkey, UI.DOT_SIZE.HERO), vkey == "good" and "good" or (vkey == "warn" and "warn") or "fg")
    v.heroVerdict = verdict
    -- META line 2: the best drop, the item count and who died
    local drop = v.drops and v.drops[run.id]
    local best = drop and drop.best
    local parts = {}
    if best then parts[#parts + 1] = "Best drop: " .. icon(best.icon, 12) .. (best.icon and " " or "") .. colored(stripLink(best.item), qColor(best.q)) end
    local nIt = itemCount(run, drop and drop.items)
    if nIt > 0 then parts[#parts + 1] = UI.plural(nIt, "item") elseif not best then parts[#parts + 1] = "Nothing looted" end
    local names = deathNames(run)
    if deathCount(run) == 0 then parts[#parts + 1] = "nobody died"
    elseif #names > 0 then
      for i, n in ipairs(names) do if n == "you" then names[i] = "You" end end
      parts[#parts + 1] = fitNames(names, 160) .. (#names == 1 and names[1] == "You" and " died" or " died")
    else parts[#parts + 1] = UI.plural(deathCount(run), "death") end
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

  v.summarySegments = function()
    local segs = { D.instanceSegment(), D.lockSegment() }
    v.summary:SetSegments(segs)
  end

  listRebuild = function()
    local runs = Runs.views()
    v.drops = bestDrops(runs)
    v.summarySegments()
    local rows = listRows(runs, st.inst, st.sortKey, st.sortAsc)
    v.shown = rows
    v.all = runs
    -- (no runs: nothing to filter, so no filter)
    if #runs == 0 then v.filter:Hide() else v.filter:Show() end
    if #runs == 0 then
      v.hero:Hide(); v.section:Hide(); tbl.frame:Hide(); v.empty:Show()
      v.place()
      return
    end
    v.empty:Hide(); v.section:Show(); tbl.frame:Show()
    -- the hero: the newest run the filter keeps
    local newest
    for _, r in ipairs(rows) do if not newest or n0(r.startT) > n0(newest.startT) then newest = r end end
    v.heroRefresh(newest)
    -- (filtered to one dungeon, the section is named after it; a list with no row says no "0 runs", B24)
    v.section:SetLabel(st.inst or "All runs")
    v.section:SetMeta(#rows > 0 and UI.plural(#rows, "run") or nil)
    v.place()
    local grouped = st.sortKey == "time"
    tbl.setRows(withDays(rows, grouped), function(row, run)
      row.run = run
      row.c.time:SetText(grouped and UI.fmtClock(run.startT) or UI.fmtDate(run.startT))
      row.c.name:SetText(run.name or "?")
      local b = badgeOf(run)
      if b then
        if not row.ebBadge then row.ebBadge = UI.Badge(row, b) end
        row.ebBadge:SetBadge(b); row.ebBadge:Show()
      elseif row.ebBadge then row.ebBadge:Hide() end
      row.c.dur:SetText(UI.fmtDur(run.inside))
      local word, wkey = vsBest(run)
      row.c.vs:SetText(word ~= "" and withDot(word, wkey) or "-")
      UI.SetColor(row.c.vs, (wkey == "good" and "good") or (wkey == "warn" and "warn") or (word == "" and "fgMuted") or "fgSubtle")
      row.c.boss:SetText(bossText(run))
      row.c.death:SetText(tostring(deathCount(run)))
      row.c.xp:SetText(n0(run.xpGain) > 0 and UI.fmtNum(run.xpGain) or "-")
      row.c.coin:SetText(n0(run.coin) > 0 and UI.money(run.coin) or "-")
      row.c.xph:SetText(run.xpPerHour and UI.fmtNum(run.xpPerHour) or "-")
      local drop = v.drops[run.id]
      local nItems = itemCount(run, drop and drop.items)
      if not row.ebLootIc then
        row.ebLootIc = row:CreateTexture(nil, "ARTWORK"); row.ebLootIc:SetSize(20, 20); row.ebLootIc:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      end
      -- (one format in every row: the best drop's icon, a bag when its row is no longer stored, then "N items")
      if nItems > 0 then
        row.ebLootIc:SetTexture((drop and drop.best and drop.best.icon) or D.BAG_ICON); row.ebLootIc:Show()
        row.c.loot:SetText(UI.plural(nItems, "item"))
      else
        row.ebLootIc:Hide()
        row.c.loot:SetText("-"); UI.SetColor(row.c.loot, "fgMuted")
      end
      for _, k in ipairs({ "xp", "coin", "xph" }) do if row.c[k]:GetText() == "-" then UI.SetColor(row.c[k], "fgMuted") end end
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
      tbl.setState(("No run of %s yet."):format(st.inst or "this dungeon"), "Show all dungeons", function() v.pickInst(nil) end, true)
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

-- ══ BY DUNGEON (4.7) ═══════════════════════════════════════════════════════════════════════════════════════════════
local function buildBy(content)
  local v = CreateFrame("Frame", nil, content); v:SetAllPoints(content)
  local st = { sortKey = nil, sortAsc = false }
  v.st = st
  local sf, child = UI.ScrollChild(v, { slim = true, top = 0, left = 0, right = 0, bottom = 0 })
  v.sf = sf
  local col = CreateFrame("Frame", nil, child); col:SetPoint("TOPLEFT", child, "TOPLEFT", 0, 0); col:SetSize(1, 1)
  v.col = col
  v.summary = UI.Summary(col)
  v.section = UI.Section(col, "All dungeons")   -- (the list-page structure of Runs and Items)
  local BEST_TIP = "First pull to last kill, on the route of your best."
  local dtbl = UI.KitTable(col, {
    { key = "name", label = "Dungeon", flex = 1, min = 140, max = 360, sort = true },
    { key = "n", label = "Runs", kind = "num", min = 40, sort = true },
    { key = "best", label = "Best", kind = "num", min = 56, sort = true, tip = BEST_TIP },
    { key = "avg", label = "Average", kind = "num", min = 56, sort = true, tip = BEST_TIP },
    { key = "xp", label = "XP per hour", kind = "num", min = 64, sort = true, tip = "XP per hour of active time inside" },
    { key = "coin", label = "Gold per hour", kind = "money", min = 72, sort = true, tip = "Looted coin and quest rewards per hour of active time inside" },
    { key = "dpr", label = "Deaths/run", kind = "num", min = 64, sort = true, tip = "Deaths per run, yours and your party's, as the Deaths column of Runs counts them" },
    { key = "lvl", label = "Level", kind = "num", min = 48, sort = true, tip = "Your level on your last run" },
    { key = "full", label = "Full clears", kind = "num", min = 64, wide = true, sort = true },
    { key = "last", label = "Last", kind = "tag", min = 72, wide = true, sort = true },
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
      tip:AddLine(("%s, %s"):format(UI.plural(d.n, "run"), UI.plural(d.full, "full clear")), 0.78, 0.79, 0.80)
      if d.other then tip:AddLine("Dungeons run least recently, counted together once 80 dungeons have numbers of their own.", 0.78, 0.79, 0.80, true)
      elseif d.best then tip:AddLine("Best and Average: " .. BEST_TIP, 0.78, 0.79, 0.80, true) end
    end })
  v.dtbl = dtbl
  v.place = function()
    local w = G.mainW(G.winW())
    col:SetWidth(w)
    local y = 0
    v.summary:ClearAllPoints(); v.summary:SetPoint("TOPLEFT", col, "TOPLEFT", 0, 0); v.summary:SetWidth(w); pcall(v.summary.layout)
    y = H.SUMMARY + S.S3
    v.section:ClearAllPoints(); v.section:SetPoint("TOPLEFT", col, "TOPLEFT", 0, -y); v.section:SetWidth(w); y = y + H.SECTION
    dtbl.frame:ClearAllPoints(); dtbl.frame:SetPoint("TOPLEFT", col, "TOPLEFT", 0, -y); dtbl.frame:SetWidth(w)
    if dtbl.width ~= math.min(w, G.TABLE_MAX) then dtbl.relayout(w) end
    y = y + (dtbl.height or 0) + S.S4
    col:SetHeight(y); sf:SetContentHeight(y)
    v.contentH = y
  end
  content:HookScript("OnSizeChanged", function() pcall(v.place) end)
  -- your level on your last run of each dungeon
  local function levels()
    local c = ns.char and ns.char() or nil
    local out = {}
    for _, r in ipairs(c and type(c.dungeonRuns) == "table" and c.dungeonRuns or {}) do
      if type(r) == "table" and type(r.xp) == "table" and r.xp.l0 then out[Runs.keyOf(r)] = math.floor(r.xp.l0) end
    end
    return out
  end
  local VAL = {
    name = function(d) return (d.name or ""):lower() end, n = function(d) return n0(d.n) end,
    best = function(d) return d.best or 1e12 end, avg = function(d) return d.avg or 1e12 end,
    xp = function(d) return n0(d.xpPerHour) end, coin = function(d) return n0(d.coinPerHour) end,
    dpr = function(d) return n0(d.deathsPerRun) end, lvl = function(d) return n0(d.level) end,
    full = function(d) return n0(d.full) end, last = function(d) return n0(d.last) end,
  }
  v.rebuild = function()
    local rows = Runs.dungeonRows()
    local lv = levels()
    local dpr = D.deathsPerRun()
    for _, d in ipairs(rows) do d.level = lv[d.key]; if dpr[d.key] then d.deathsPerRun = dpr[d.key] end end
    local atMax = (ns.Now and ns.Now.atMax and ns.Now.atMax()) or false
    v.atMax = atMax
    local key = st.sortKey or (atMax and "coin" or "xp")
    local asc = st.sortKey and st.sortAsc or false
    dtbl.setSort(key, asc)
    local val = VAL[key] or VAL.xp
    table.sort(rows, function(a, b)
      if a.other ~= b.other then return b.other end
      local x, y = val(a), val(b)
      if x ~= y then if asc then return x < y end return x > y end
      return n0(a.last) > n0(b.last)
    end)
    v.dshown = rows
    -- the answer: the dungeon that pays best
    local top
    for _, d in ipairs(rows) do
      local r = atMax and d.coinPerHour or d.xpPerHour
      if not d.other and r and (not top or r > (atMax and top.coinPerHour or top.xpPerHour)) then top = d end
    end
    local first
    if top then first = atMax and { text = ("Best gold per hour: %s, **%s**"):format(top.name, UI.money(math.floor(top.coinPerHour), true)) }
      or { text = ("Best XP per hour: %s, **%s**"):format(top.name, UI.fmtNum(top.xpPerHour)) }
    elseif #rows > 0 then first = { text = "Pay per hour shows after 5 minutes inside a dungeon" } end
    local segs = {}
    -- (the line too long at 900: the pay segment goes first, the lockout keeps its one wording)
    if first then first.optional = true; segs[#segs + 1] = first end
    segs[#segs + 1] = D.instanceSegment(); segs[#segs + 1] = D.lockSegment()
    v.summary:SetSegments(segs)
    -- (the measure of Best and Average in the copy, not only in a header tooltip: Runs' TIME is the time inside)
    v.section:SetMeta(#rows > 0 and (UI.plural(#rows, "dungeon") .. SEP .. "best and average: first pull to last kill") or nil)
    dtbl.setRows(rows, function(row, d)
      row.drow = d
      row.c.name:SetText(d.name .. (d.kind == "raid" and " (raid)" or ""))
      row.c.n:SetText(tostring(d.n))
      row.c.best:SetText(d.best and UI.fmtDur(d.best) or "-")
      row.c.avg:SetText(d.avg and UI.fmtDur(d.avg) or "-")
      row.c.xp:SetText(d.xpPerHour and UI.fmtNum(d.xpPerHour) or "-")
      row.c.coin:SetText(d.coinPerHour and UI.money(math.floor(d.coinPerHour), true) or "-")
      row.c.dpr:SetText(("%.1f"):format(n0(d.deathsPerRun)))
      row.c.lvl:SetText(d.level and tostring(d.level) or "-")
      row.c.full:SetText(d.kind == "raid" and "-" or tostring(n0(d.full)))
      row.c.last:SetText(n0(d.last) > 0 and UI.fmtDate(d.last) or "-")
      for _, k in ipairs({ "best", "avg", "xp", "coin", "lvl", "full", "last" }) do if row.c[k]:GetText() == "-" then UI.SetColor(row.c[k], "fgMuted") end end
      row.item.ebNoOpen = d.other or nil
    end)
    if #rows == 0 then dtbl.setState("Run a dungeon and its best, average and pay show here.") end
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
      if onScreen(listView) and listView.heroRun and listView.heroRun.inProgress then
        local rec = openRec()
        if rec and rec.id == listView.heroRun.id then pcall(listView.heroRefresh, Runs.view(rec, true, false)) end
      end
    end)
  end
end, "Your dungeon runs against your best: time, bosses, deaths, loot and XP.")
UI.registerPane("Dungeons", 2, "By dungeon", function(content)
  byView = buildBy(content)
end, function() if byView then byView.rebuild() end end,
  "Which dungeon is worth your time: your best, your average, and what each pays.")

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
ns._test.dungeonsLockText = function() return D.lockSegment().text end
ns._test.renderRun = function(run) if detailView then detailView.render(run) end end
ns._test.dungeonDetail = function() return detailView end
ns._test.dungeonList = function() if listRebuild then listRebuild() end; return listView end
ns._test.dungeonBy = function() if byView then byView.rebuild() end; return byView end
ns._test.openRun = function(run) openRun(run) end
