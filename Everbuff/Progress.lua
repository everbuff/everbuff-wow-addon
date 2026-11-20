-- Everbuff.GG · Progress.lua - Quests, Reputation and Professions (the CHARACTER tab).
--
-- The leveling vertical's "what did I actually get done" panes, the three panes of the CHARACTER host tab
-- since 2026-09-25. All present data other modules already capture: quest events from the timeline, the
-- reputation snapshot Emitter keeps, and the structured professions snapshot with its tier milestones.
-- Nothing here reads a game API at render time except the clock; it is a pure view over ns.DB. Every list reads
-- the logged-in character's rows only (ns.mine, #23).

local ADDON, ns = ...
local UI = ns.UI
local C = ns.UI.C

-- ── pure builders (also exported for the headless tests) ─────────────────────────
local function stripPrefix(text, prefix)
  text = text or ""
  if text:sub(1, #prefix) == prefix then return (text:sub(#prefix + 1):gsub("^%s+", "")) end
  return text
end

-- quests: every QUESTDONE row newest first; accepted-but-not-completed names listed as in progress
local function buildQuests()
  local log = ns.mine(ns.DB and ns.DB.story.events)
  local done, accepted, doneSet, rewards = {}, {}, {}, 0
  for _, e in ipairs(log) do
    if e.kind == "QUESTDONE" then
      local nm = stripPrefix(e.text, "Complete:")
      done[#done + 1] = { t = e.t or 0, name = nm, zone = e.zone, sub = e.sub, x = e.x, y = e.y, status = "done" }
      doneSet[nm] = true
    elseif e.kind == "QUESTACCEPT" then
      accepted[#accepted + 1] = { t = e.t or 0, name = stripPrefix(e.text, "Quest:"), zone = e.zone, sub = e.sub, x = e.x, y = e.y, status = "accepted" }
    elseif e.kind == "REWARD" then rewards = rewards + 1 end
  end
  local open = {}
  for _, a in ipairs(accepted) do if not doneSet[a.name] then open[#open + 1] = a end end
  local rows = {}
  for _, o in ipairs(open) do rows[#rows + 1] = o end
  for _, d in ipairs(done) do rows[#rows + 1] = d end
  table.sort(rows, function(a, b) return a.t > b.t end)
  local xp = (ns.DB and ns.char().xp and tonumber(ns.char().xp.fromQuests)) or 0
  return rows, { accepted = #accepted, done = #done, open = #open, rewards = rewards, xp = xp }
end

-- reputation: the snapshot (faction -> standing) sorted best standing first, with the last tier-up seen
local function buildReputation()
  local snap = (ns.DB and ns.char().reputation) or {}
  local log = ns.mine(ns.DB and ns.DB.story.events)
  local lastUp, ups = {}, 0
  for _, e in ipairs(log) do
    if e.kind == "REP" then
      ups = ups + 1
      local nm = (e.text or ""):match("^(.-):%s") or e.text
      if nm and (not lastUp[nm] or (e.t or 0) > lastUp[nm]) then lastUp[nm] = e.t or 0 end
    end
  end
  local rows = {}
  for name, r in pairs(snap) do
    rows[#rows + 1] = { name = name, standing = tonumber(r.standing) or 0, label = r.label or "?", lastUp = lastUp[name] }
  end
  table.sort(rows, function(a, b) if a.standing ~= b.standing then return a.standing > b.standing end return a.name < b.name end)
  return rows, { factions = #rows, ups = ups }
end

-- professions: the snapshot (name -> rank/max) plus milestone and recipe counts from the timeline
local skillOf   -- defined below; buildProfessions counts every skill-up, crafted or gathered
local function buildProfessions()
  local snap = (ns.DB and ns.char().professions) or {}
  local log = ns.mine(ns.DB and ns.DB.story.events)
  local tiers, skillups, recipes, crafted = {}, {}, 0, {}
  for _, e in ipairs(log) do
    if e.kind == "PROFTIER" then
      local nm = (e.text or ""):match("Skill milestone:%s*(.-)%s+%d+$")
      if nm then tiers[nm] = (tiers[nm] or 0) + 1 end
    elseif e.kind == "SKILLUP" then
      local p = skillOf(e)
      if p then skillups[p] = (skillups[p] or 0) + 1; if e.crafted then crafted[p] = math.max(crafted[p] or 0, tonumber(e.crafted) or 0) end end
    elseif e.kind == "RECIPE" then recipes = recipes + 1 end
  end
  local rows = {}
  for name, pr in pairs(snap) do
    rows[#rows + 1] = { name = name, rank = tonumber(pr.rank) or 0, max = tonumber(pr.max) or 0, tiers = tiers[name] or 0, skillups = skillups[name] or 0 }
  end
  table.sort(rows, function(a, b) if a.rank ~= b.rank then return a.rank > b.rank end return a.name < b.name end)
  return rows, { professions = #rows, recipes = recipes }
end

-- the profession and rank of a SKILLUP row: its own prof field (crafts), else its text ("Skill up:  Herbalism 7")
function skillOf(e)
  local text = stripPrefix(e.text or "", "Skill up:")
  local nm, rank = text:match("^(.-)%s+(%d+)")
  return e.prof or nm, tonumber(rank)
end
local GATHERING = { Herbalism = true, Mining = true, Skinning = true, Fishing = true }

-- every skill-up of a profession you have, newest first; `only` limits it to one profession
local function buildSkillups(only)
  local snap = (ns.DB and ns.char().professions) or {}
  local log = ns.mine(ns.DB and ns.DB.story.events)
  local rows = {}
  for _, e in ipairs(log) do
    if e.kind == "SKILLUP" then
      local prof, rank = skillOf(e)
      if prof and snap[prof] and (not only or only == prof) then
        local source = ""
        if e.craft then source = (tonumber(e.crafted) or 1) > 1 and ("%s x%d"):format(e.craft, e.crafted) or e.craft
        elseif GATHERING[prof] then source = "Gathering" end
        rows[#rows + 1] = { t = e.t or 0, prof = prof, rank = rank, source = source, zone = e.zone, sub = e.sub, x = e.x, y = e.y }
      end
    end
  end
  table.sort(rows, function(a, b) return a.t > b.t end)
  return rows
end

-- every reputation gain and every new standing, newest first; `only` limits it to one faction
local function buildRepHistory(only)
  local rows = {}
  for _, g in ipairs(ns.mine(ns.DB and ns.DB.story.rep)) do
    if not only or only == g.faction then
      rows[#rows + 1] = { t = g.t or 0, faction = g.faction, change = ("+%d"):format(g.amount or 0), source = g.src or "", zone = g.zone, sub = g.sub, x = g.x, y = g.y }
    end
  end
  for _, e in ipairs(ns.mine(ns.DB and ns.DB.story.events)) do
    if e.kind == "REP" then
      local nm = (e.text or ""):match("^(.-):%s") or e.text
      if nm and (not only or only == nm) then
        rows[#rows + 1] = { t = e.t or 0, faction = nm, change = e.standing and ("Now " .. e.standing) or "New standing", source = "", zone = e.zone, sub = e.sub, x = e.x, y = e.y, milestone = true }
      end
    end
  end
  table.sort(rows, function(a, b) return a.t > b.t end)
  return rows
end

-- ── view ──────────────────────────────────────────────────────────────────────────
local STANDING_COLOR = {   -- reaction id 1..8: hated .. exalted
  [1] = { 0.80, 0.13, 0.13 }, [2] = { 0.80, 0.13, 0.13 }, [3] = { 0.93, 0.40, 0.13 }, [4] = C.dim or { 0.6, 0.6, 0.6 },
  [5] = { 0.13, 0.80, 0.13 }, [6] = { 0.13, 0.80, 0.13 }, [7] = { 0.13, 0.80, 0.13 }, [8] = { 0.13, 0.80, 0.80 },
}

-- A list pane: a summary line (it wraps; the list moves down with it) over a UI.Table. opts.fit = n makes the list
-- exactly as tall as its first n rows (the factions and professions, with their history right below them);
-- without it the list runs to the pane's bottom. opts.onClick(row) makes the rows a filter.
local function makeList(pane, spec, opts)
  opts = opts or {}
  local SP = UI.SP
  local summary = UI.SummaryLine(pane, C.gold, nil, true)
  local body = CreateFrame("Frame", nil, pane)
  body:SetPoint("TOPLEFT", summary, "BOTTOMLEFT", -SP.S, -SP.S)
  if opts.fit then body:SetPoint("TOPRIGHT", summary, "BOTTOMRIGHT", UI.SCROLLBAR + SP.S, -SP.S); body:SetHeight(2 * UI.ROW_H + 1)
  else body:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", 0, 0) end
  local tbl = UI.Table(body, spec, { top = 0, onClick = opts.onClick and function(row) opts.onClick(row) end })
  local L = { summary = summary, body = body, tbl = tbl, child = tbl.child, pane = pane }
  -- render(rows, fill, emptyText): fill(row, item) sets the cells row.c[key]
  L.render = function(rows, fill, emptyText)
    tbl.setRows(rows, fill)
    if #rows == 0 then tbl.setEmpty(emptyText) end
    if opts.fit then body:SetHeight(UI.ROW_H + 1 + UI.ROW_H * math.max(1, math.min(#rows, opts.fit))) end
  end
  return L
end
-- a selected filter row keeps a fill under its hover highlight
local function markSelected(row, on)
  if not row.sel then
    row.sel = row:CreateTexture(nil, "BACKGROUND"); row.sel:SetAllPoints(row)
    row.sel:SetColorTexture(C.panel2[1], C.panel2[2], C.panel2[3], 1)
  end
  if on then row.sel:Show() else row.sel:Hide() end
end
local TIME_MEASURE = { "Dec 31, 23:59", "Sep 30, 23:59" }
local COORDS = { key = "coords", label = "Coords", kind = "tag", justify = "RIGHT", color = "dim", measure = { "100.0, 100.0" } }
local STANDINGS = { "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted" }

-- CHARACTER host: Quests · Reputation · Professions, each a pane built on first select.
UI.registerHost(2, "Character", "Pace to the next level, your standing, and your skills.")
local quests, rep, prof
local function renderQuests()
  if not quests then return end
  local rows, sum = buildQuests()
  quests.summary:SetText(("%d completed  ·  %d in progress  ·  %d rewards chosen  ·  %s XP from quests"):format(sum.done, sum.open, sum.rewards, tostring(sum.xp)))
  quests.render(rows, function(row, q)
    row.c.time:SetText(date("%H:%M", q.t))
    row.c.name:SetText(q.name or "?")
    if q.status == "done" then row.c.status:SetText("Completed"); row.c.status:SetTextColor(C.green[1], C.green[2], C.green[3])
    else row.c.status:SetText("In progress"); row.c.status:SetTextColor(C.gold[1], C.gold[2], C.gold[3]) end
    row.c.loc:SetText(UI.fmtPlace(q.zone, q.sub))
    row.c.coords:SetText(UI.fmtCoords(q.x, q.y))
  end, "No quests recorded yet. Accept or turn in a quest and it shows up here.")
end
local repFilter, repHist, repHistFrame
local function renderRep()
  if not rep then return end
  local rows, sum = buildReputation()
  rep.summary:SetText(("%d factions known  ·  %d standing gains  ·  click a faction to see how you earned it"):format(sum.factions, sum.ups))
  rep.render(rows, function(row, r)
    row.faction = r.name
    markSelected(row, repFilter == r.name)
    row.c.name:SetText(r.name)
    local col = STANDING_COLOR[r.standing] or C.dim
    row.c.standing:SetText(r.label); row.c.standing:SetTextColor(col[1], col[2], col[3])
    row.c.last:SetText(r.lastUp and date("%b %d, %H:%M", r.lastUp) or "")
  end, "No reputation snapshot yet. It is taken a few seconds after login.")
  if repHist then
    local hist = buildRepHistory(repFilter)
    local total = 0
    for _, h in ipairs(hist) do if not h.milestone then total = total + (tonumber((h.change or ""):match("%d+")) or 0) end end
    repHist.summary:SetText(repFilter and ("How you earned %s  ·  +%d reputation"):format(repFilter, total) or ("How you earned your reputation  ·  +%d in %d gains"):format(total, #hist))
    repHist.render(hist, function(row, h)
      row.c.time:SetText(date("%b %d, %H:%M", h.t))
      row.c.faction:SetText(h.faction)
      row.c.change:SetText(h.change)
      if h.milestone then row.c.change:SetTextColor(C.green[1], C.green[2], C.green[3]) end
      row.c.source:SetText(h.source)
      row.c.loc:SetText(UI.fmtPlace(h.zone, h.sub))
      row.c.coords:SetText(UI.fmtCoords(h.x, h.y))
    end, repFilter and ("No gains for %s recorded yet."):format(repFilter) or "No reputation gains recorded yet. Turn in a quest or defeat an enemy that gives reputation.")
  end
end
local profFilter, profHist, profHistFrame
local function renderProf()
  if not prof then return end
  local rows, sum = buildProfessions()
  prof.summary:SetText(("%d professions  ·  %d recipes learned  ·  click a profession to see how it leveled"):format(sum.professions, sum.recipes))
  prof.render(rows, function(row, p)
    -- a profession row filters the history below; clicking the selected one shows all again
    row.prof = p.name
    markSelected(row, profFilter == p.name)
    row.c.name:SetText(p.name)
    row.c.rank:SetText(("%d / %d"):format(p.rank, p.max))
    -- the skill bar: a dim track across the whole bar column, the filled part over it, so a low skill still reads as
    -- a share of its column and not as a stray mark
    if not row.bar then
      row.barTrack = row:CreateTexture(nil, "BORDER"); row.barTrack:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
      row.barTrack:SetPoint("LEFT", row.c.bar, "LEFT", 0, 0)
      row.bar = row:CreateTexture(nil, "ARTWORK"); row.bar:SetColorTexture(C.cyan[1], C.cyan[2], C.cyan[3], 0.35)
      row.bar:SetPoint("LEFT", row.c.bar, "LEFT", 0, 0)
    end
    local colW = prof.tbl.cols.bar and prof.tbl.cols.bar.w or 160
    if p.max > 0 then
      local bw = math.max(1, colW * math.min(1, p.rank / p.max))
      row.barTrack:SetSize(colW, 8); row.barTrack:Show()
      row.bar:SetSize(bw, 8); row.bar:Show()
    else row.bar:Hide(); row.barTrack:Hide() end
    row.c.tiers:SetText(p.tiers > 0 and tostring(p.tiers) or "-")
    row.c.ups:SetText(p.skillups > 0 and tostring(p.skillups) or "-")
  end, "No professions found. Learn one and it shows up here.")
  if profHist then
    local hist = buildSkillups(profFilter)
    profHist.summary:SetText(profFilter and ("How %s leveled  ·  %d skill-ups"):format(profFilter, #hist) or ("How your professions leveled  ·  %d skill-ups"):format(#hist))
    profHist.render(hist, function(row, h)
      row.c.time:SetText(date("%b %d, %H:%M", h.t))
      row.c.prof:SetText(h.prof)
      row.c.rank:SetText(h.rank and tostring(h.rank) or "")
      row.c.source:SetText(h.source)
      row.c.loc:SetText(UI.fmtPlace(h.zone, h.sub))
      row.c.coords:SetText(UI.fmtCoords(h.x, h.y))
    end, profFilter and ("No skill-ups for %s recorded yet."):format(profFilter) or "No skill-ups recorded yet. Gather or craft and each point shows up here.")
  end
end
-- the history list of a pane, right under its first list
local function historyFrame(L)
  local f = CreateFrame("Frame", nil, L.pane)
  f:SetPoint("TOPLEFT", L.body, "BOTTOMLEFT", 0, -UI.SP.L)
  f:SetPoint("BOTTOMRIGHT", L.pane, "BOTTOMRIGHT", 0, 0)
  return f
end
UI.registerPane("Character", 1, "Quests", function(content)
  quests = makeList(content, {
    { key = "time", label = "Time", kind = "tag", color = "dim", measure = { "23:59" } },
    { key = "name", label = "Quest", flex = 1.4, min = 120 },
    { key = "status", label = "Status", kind = "tag", measure = { "In progress", "Completed" } },
    { key = "loc", label = "Location", flex = 1, min = 90, color = "dim" },
    COORDS,
  }); renderQuests()
end, renderQuests)
UI.registerPane("Character", 2, "Reputation", function(content)
  rep = makeList(content, {
    { key = "name", label = "Faction", flex = 1, min = 140 },
    { key = "standing", label = "Standing", kind = "tag", measure = STANDINGS },
    { key = "last", label = "Last standing gain", kind = "tag", color = "dim", measure = TIME_MEASURE },
  }, { fit = 8, onClick = function(row) repFilter = (repFilter == row.faction) and nil or row.faction; renderRep() end })
  repHistFrame = historyFrame(rep)
  repHist = makeList(repHistFrame, {
    { key = "time", label = "Time", kind = "tag", color = "dim", measure = TIME_MEASURE },
    { key = "faction", label = "Faction", flex = 1, min = 90 },
    { key = "change", label = "Gain", kind = "tag", justify = "RIGHT", measure = { "+9999", "Now Unfriendly" } },
    { key = "source", label = "Source", flex = 1, min = 90, color = "dim" },
    { key = "loc", label = "Location", flex = 0.8, min = 80, color = "dim" },
    COORDS,
  })
  renderRep()
end, renderRep)
UI.registerPane("Character", 3, "Professions", function(content)
  prof = makeList(content, {
    { key = "name", label = "Profession", flex = 1, min = 120 },
    { key = "rank", label = "Skill", kind = "num", measure = { "300 / 300" } },
    { key = "bar", label = "", kind = "tag", min = 160 },
    { key = "tiers", label = "Milestones", kind = "num", color = "dim", measure = { "9" } },
    { key = "ups", label = "Skill-ups", kind = "num", color = "dim", measure = { "9999" } },
  }, { fit = math.huge, onClick = function(row) profFilter = (profFilter == row.prof) and nil or row.prof; renderProf() end })
  profHistFrame = historyFrame(prof)
  profHist = makeList(profHistFrame, {
    { key = "time", label = "Time", kind = "tag", color = "dim", measure = TIME_MEASURE },
    { key = "prof", label = "Profession", flex = 0.6, min = 80 },
    { key = "rank", label = "Skill", kind = "num", measure = { "300" } },
    { key = "source", label = "Source", flex = 1, min = 90, color = "dim" },
    { key = "loc", label = "Location", flex = 0.8, min = 80, color = "dim" },
    COORDS,
  })
  renderProf()
end, renderProf)
-- ── test exports: headless luajit tests in tests/ read these; no effect in-game ──
ns._test = ns._test or {}
ns._test.buildQuests, ns._test.buildReputation, ns._test.buildProfessions = buildQuests, buildReputation, buildProfessions
ns._test.buildSkillups = buildSkillups
ns._test.buildRepHistory = buildRepHistory
