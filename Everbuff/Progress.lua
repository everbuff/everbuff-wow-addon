-- Everbuff.GG · Progress.lua - Quests, Reputation and Professions (the CHARACTER tab).
--
-- The leveling vertical's "what did I actually get done" panes, the three panes of the CHARACTER host tab
-- since 2026-09-25. All present data other modules already capture: quest events from the timeline, the
-- reputation snapshot Emitter keeps, and the structured professions snapshot with its tier milestones.
-- Nothing here reads a game API at render time except the clock; it is a pure view over ns.DB.

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
  local log = (ns.DB and ns.DB.story.events) or {}
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
  local xp = (ns.DB and ns.DB.character.xp and tonumber(ns.DB.character.xp.fromQuests)) or 0
  return rows, { accepted = #accepted, done = #done, open = #open, rewards = rewards, xp = xp }
end

-- reputation: the snapshot (faction -> standing) sorted best standing first, with the last tier-up seen
local function buildReputation()
  local snap = (ns.DB and ns.DB.character.reputation) or {}
  local log = (ns.DB and ns.DB.story.events) or {}
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
  local snap = (ns.DB and ns.DB.character.professions) or {}
  local log = (ns.DB and ns.DB.story.events) or {}
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
  local snap = (ns.DB and ns.DB.character.professions) or {}
  local log = (ns.DB and ns.DB.story.events) or {}
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

-- ── view ──────────────────────────────────────────────────────────────────────────
local STANDING_COLOR = {   -- reaction id 1..8: hated .. exalted
  [1] = { 0.80, 0.13, 0.13 }, [2] = { 0.80, 0.13, 0.13 }, [3] = { 0.93, 0.40, 0.13 }, [4] = C.dim or { 0.6, 0.6, 0.6 },
  [5] = { 0.13, 0.80, 0.13 }, [6] = { 0.13, 0.80, 0.13 }, [7] = { 0.13, 0.80, 0.13 }, [8] = { 0.13, 0.80, 0.80 },
}

local function makeList(pane, cols, header)
  -- one header row + a pooled scrolling list; cols = { {key, x, w, label} ... }
  local hdr = CreateFrame("Frame", nil, pane); hdr:SetPoint("TOPLEFT", 2, -26); hdr:SetSize(660, 16)
  for _, c in ipairs(cols) do
    local fs = UI.FS(hdr, "GameFontNormalSmall"); fs:SetPoint("LEFT", c[2], 0); fs:SetWidth(c[3]); fs:SetJustifyH("LEFT")
    fs:SetText(c[4]:upper()); fs:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
  end
  local summary = UI.FS(pane, "GameFontHighlightSmall", C.gold); summary:SetPoint("TOPLEFT", 2, -6); summary:SetWidth(650); summary:SetJustifyH("LEFT")
  local sf, child = UI.ScrollChild(pane)
  sf:SetPoint("TOPLEFT", 0, -46); sf:SetPoint("BOTTOMRIGHT", -22, 2)
  child.rows = {}
  local L = { summary = summary, child = child, cols = cols }
  -- render(rows, fill) : fill(row, item) sets the cells; rows are pooled Frames with .c[key] FontStrings
  L.render = function(rows, fill, emptyText)
    local y, idx = 0, 0
    for _, item in ipairs(rows) do
      idx = idx + 1
      local row = child.rows[idx]
      if not row then
        row = CreateFrame("Frame", nil, child); row:SetHeight(18); row:SetPoint("RIGHT", child, "RIGHT", 0, 0); row.c = {}
        for _, c in ipairs(cols) do
          local fs = UI.FS(row, "GameFontHighlightSmall"); fs:SetPoint("LEFT", c[2], 0); fs:SetWidth(c[3]); fs:SetJustifyH("LEFT"); row.c[c[1]] = fs
        end
        row.bar = row:CreateTexture(nil, "ARTWORK"); row.bar:SetColorTexture(C.cyan[1], C.cyan[2], C.cyan[3], 0.35); row.bar:Hide()
        child.rows[idx] = row
      end
      row:SetPoint("TOPLEFT", 0, -y); row:Show(); row.bar:Hide()
      fill(row, item)
      y = y + 18
    end
    for j = idx + 1, #child.rows do child.rows[j]:Hide() end
    if idx == 0 then
      child.empty = child.empty or (function() local fs = UI.FS(child, "GameFontDisableSmall"); fs:SetPoint("TOPLEFT", 0, 0); return fs end)()
      child.empty:SetText(emptyText); child.empty:Show()
    elseif child.empty then child.empty:Hide() end
    child:SetSize(math.max(660, (sf:GetWidth() or 660) - 4), math.max(1, y))
  end
  return L
end

-- CHARACTER host: Quests · Reputation · Professions, each a pane built on first select.
UI.registerHost(3, "Character", "How your character is growing: quests done, standing with every faction, and your professions.")
local quests, rep, prof
local function renderQuests()
  if not quests then return end
  local rows, sum = buildQuests()
  quests.summary:SetText(("%d completed  ·  %d in progress  ·  %d rewards chosen  ·  %s XP from quests"):format(sum.done, sum.open, sum.rewards, tostring(sum.xp)))
  quests.render(rows, function(row, q)
    row.c.time:SetText(date("%H:%M", q.t)); row.c.time:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
    row.c.name:SetText(q.name or "?"); row.c.name:SetTextColor(C.ink[1], C.ink[2], C.ink[3])
    if q.status == "done" then row.c.status:SetText("Completed"); row.c.status:SetTextColor(C.green[1], C.green[2], C.green[3])
    else row.c.status:SetText("In progress"); row.c.status:SetTextColor(C.gold[1], C.gold[2], C.gold[3]) end
    row.c.loc:SetText(UI.fmtPlace(q.zone, q.sub)); row.c.loc:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
    row.c.coords:SetText(UI.fmtCoords(q.x, q.y)); row.c.coords:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
  end, "No quests recorded yet. Accept or turn in a quest and it shows up here.")
end
local function renderRep()
  if not rep then return end
  local rows, sum = buildReputation()
  rep.summary:SetText(("%d factions known  ·  %d standing gains recorded"):format(sum.factions, sum.ups))
  rep.render(rows, function(row, r)
    row.c.name:SetText(r.name); row.c.name:SetTextColor(C.ink[1], C.ink[2], C.ink[3])
    local col = STANDING_COLOR[r.standing] or C.dim
    row.c.standing:SetText(r.label); row.c.standing:SetTextColor(col[1], col[2], col[3])
    row.c.last:SetText(r.lastUp and date("%b %d, %H:%M", r.lastUp) or ""); row.c.last:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
  end, "No reputation snapshot yet. It is taken a few seconds after login.")
end
local profFilter, profHist, profHistFrame
local function renderProf()
  if not prof then return end
  local rows, sum = buildProfessions()
  prof.summary:SetText(("%d professions  ·  %d recipes learned  ·  click a profession to see how it leveled"):format(sum.professions, sum.recipes))
  prof.render(rows, function(row, p)
    -- a profession row filters the history below; clicking the selected one shows all again
    if not row.clickable then
      row.clickable = true; row:EnableMouse(true)
      row.hl = row:CreateTexture(nil, "BACKGROUND"); row.hl:SetAllPoints(); row.hl:SetColorTexture(0, 0, 0, 0)
      row:SetScript("OnMouseUp", function(r) profFilter = (profFilter == r.prof) and nil or r.prof; renderProf() end)
      row:SetScript("OnEnter", function(r) if profFilter ~= r.prof then r.hl:SetColorTexture(C.panel2[1], C.panel2[2], C.panel2[3], 1) end end)
      row:SetScript("OnLeave", function(r) if profFilter ~= r.prof then r.hl:SetColorTexture(0, 0, 0, 0) end end)
    end
    row.prof = p.name
    if profFilter == p.name then row.hl:SetColorTexture(C.panel2[1], C.panel2[2], C.panel2[3], 1) else row.hl:SetColorTexture(0, 0, 0, 0) end
    row.c.name:SetText(p.name); row.c.name:SetTextColor(C.ink[1], C.ink[2], C.ink[3])
    row.c.rank:SetText(("%d / %d"):format(p.rank, p.max)); row.c.rank:SetTextColor(C.ink[1], C.ink[2], C.ink[3])
    row.c.bar:SetText("")
    if p.max > 0 then
      row.bar:ClearAllPoints(); row.bar:SetPoint("LEFT", 302, 0); row.bar:SetSize(math.max(1, 160 * math.min(1, p.rank / p.max)), 8); row.bar:Show()
    end
    row.c.tiers:SetText(p.tiers > 0 and tostring(p.tiers) or "-"); row.c.tiers:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
    row.c.ups:SetText(p.skillups > 0 and tostring(p.skillups) or "-"); row.c.ups:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
  end, "No professions found. Learn one and it shows up here.")
  -- the history sits right under the professions, however many there are
  if profHistFrame then
    profHistFrame:ClearAllPoints()
    profHistFrame:SetPoint("TOPLEFT", prof.pane, "TOPLEFT", 0, -(46 + 18 * math.max(1, #rows) + 16))
    profHistFrame:SetPoint("BOTTOMRIGHT", prof.pane, "BOTTOMRIGHT", 0, 0)
  end
  if profHist then
    local hist = buildSkillups(profFilter)
    profHist.summary:SetText(profFilter and ("How %s leveled  ·  %d skill-ups"):format(profFilter, #hist) or ("How your professions leveled  ·  %d skill-ups"):format(#hist))
    profHist.render(hist, function(row, h)
      row.c.time:SetText(date("%b %d, %H:%M", h.t)); row.c.time:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
      row.c.prof:SetText(h.prof); row.c.prof:SetTextColor(C.ink[1], C.ink[2], C.ink[3])
      row.c.rank:SetText(h.rank and tostring(h.rank) or ""); row.c.rank:SetTextColor(C.ink[1], C.ink[2], C.ink[3])
      row.c.source:SetText(h.source); row.c.source:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
      row.c.loc:SetText(UI.fmtPlace(h.zone, h.sub)); row.c.loc:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
      row.c.coords:SetText(UI.fmtCoords(h.x, h.y)); row.c.coords:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
    end, profFilter and ("No skill-ups for %s recorded yet."):format(profFilter) or "No skill-ups recorded yet. Gather or craft and each point shows up here.")
  end
end
UI.registerPane("Character", 1, "Quests", function(content)
  quests = makeList(content, {
    { "time", 0, 60, "Time" }, { "name", 66, 260, "Quest" }, { "status", 332, 80, "Status" }, { "loc", 418, 150, "Location" }, { "coords", 574, 80, "Coords" },
  }); renderQuests()
end, renderQuests)
UI.registerPane("Character", 2, "Reputation", function(content)
  rep = makeList(content, {
    { "name", 0, 300, "Faction" }, { "standing", 306, 120, "Standing" }, { "last", 432, 200, "Last standing gain" },
  }); renderRep()
end, renderRep)
UI.registerPane("Character", 3, "Professions", function(content)
  prof = makeList(content, {
    { "name", 0, 200, "Profession" }, { "rank", 206, 90, "Skill" }, { "bar", 302, 160, "" }, { "tiers", 468, 90, "Milestones" }, { "ups", 564, 90, "Skill-ups" },
  })
  prof.pane = content
  profHistFrame = CreateFrame("Frame", nil, content)
  profHist = makeList(profHistFrame, {
    { "time", 0, 96, "Time" }, { "prof", 100, 100, "Profession" }, { "rank", 204, 44, "Skill" }, { "source", 252, 170, "Source" }, { "loc", 426, 150, "Location" }, { "coords", 580, 70, "Coordinates" },
  })
  renderProf()
end, renderProf)

-- ── test exports: headless luajit tests in tests/ read these; no effect in-game ──
ns._test = ns._test or {}
ns._test.buildQuests, ns._test.buildReputation, ns._test.buildProfessions = buildQuests, buildReputation, buildProfessions
ns._test.buildSkillups = buildSkillups
