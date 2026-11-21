-- Everbuff.GG · Progress.lua - the CHARACTER host: Leveling, Reputation and Professions (docs/UX_OVERHAUL.md 4.10, 4.11).
--
-- Leveling answers how fast you level compared with before (the hero), where your XP comes from (the cards), every
-- level with its time (LEVELS) and every quest turned in with its gold (QUESTS TURNED IN; the old Quests tab folds in
-- here). Reputation lists every faction with its standing, the progress to the next one and what you gained this
-- session; a faction opens how you earned it. Professions lists your skills with their bar and when to train next,
-- then what you crafted and the recipes you learned (the old Crafting tab folds in here).
-- The data is what other modules capture (the story events, the reputation gains, the professions snapshot, the
-- crafts and recipes Market keeps, the gold journal), plus the live reputation bars and the leveling pace (ns.Pace).
-- Every list reads the logged-in character's rows only (ns.mine, #23). Built from the kit (UI.lua) only.

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
local function mutedTip(fs, title, text) UI.SetTip(fs, { title = title, text = text }) end

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

-- LEVELS: every level with a recorded moment (docs/UX_PRAGMATIC.md 3.1). Two sources, both exact: the LEVELUP story
-- event, and the LEVEL_UP row of a stored session record ("seq, server time, clock, LEVEL_UP, level, zone"), which
-- outlives the event list. A level with neither has no row: nothing is worked out from the /played stamps
-- (playedAtLevel), which were overwritten at every login, so no time at a level but the current one is shown.
local function levelOf(e) return tonumber(tostring(e.text or ""):match("(%d+)")) end
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
-- Rows { level, t, zone }, highest level first, and how many of the levels 2 to `cur` have no recorded moment.
local function buildLevels(cur)
  local reached = {}
  local function note(L, t, zone)
    L, t = tonumber(L), tonumber(t)
    if not (L and t and t > 0 and L >= 2 and L == math.floor(L)) then return end
    if cur and L > cur then return end
    local r = reached[L]
    if not r or t < r.t then
      reached[L] = { level = L, t = t, zone = (type(zone) == "string" and zone ~= "") and zone or (r and r.zone) or nil }
    elseif not r.zone and type(zone) == "string" and zone ~= "" then r.zone = zone end
  end
  for _, e in ipairs(events()) do
    if e.kind == "LEVELUP" then note(levelOf(e), e.t, e.zone) end
  end
  for _, sess in pairs((ns.DB and ns.DB.sessions) or {}) do
    if type(sess) == "table" and ns.isMySession(sess) and type(sess.segments) == "table" then
      for _, seg in ipairs(sess.segments) do
        if type(seg) == "string" and seg:find("\tLEVEL_UP\t", 1, true) then
          local t, L, zone = seg:match("^%d+\t(%d+)\t[%d%.]+\tLEVEL_UP\t(%d+)\t?(.*)$")
          note(L, t, zone)
        end
      end
    end
  end
  local rows = {}
  for _, r in pairs(reached) do rows[#rows + 1] = r end
  table.sort(rows, function(a, b) return a.level > b.level end)
  local missing = (cur and cur >= 2) and math.max(0, (cur - 1) - #rows) or 0
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
local function buildReputation()
  local snap = charDB().reputation or {}
  local live = readFactions()
  local session, last = {}, {}
  local s = sid()
  for _, g in ipairs(ns.mine(ns.DB and ns.DB.story and ns.DB.story.rep)) do
    if type(g) == "table" and g.faction then
      if s and g.s == s then session[g.faction] = (session[g.faction] or 0) + num(g.amount) end
      if not last[g.faction] or num(g.t) > last[g.faction] then last[g.faction] = num(g.t) end
    end
  end
  local names = {}
  for name in pairs(snap) do names[name] = true end
  for name in pairs(live) do names[name] = true end
  local rows, gained = {}, 0
  for name in pairs(names) do
    local sr, lr = snap[name] or {}, live[name] or {}
    local st = tonumber(lr.standing) or tonumber(sr.standing) or 0
    local r = { name = name, standing = st, label = STANDINGS[st] or sr.label or _G["FACTION_STANDING_LABEL" .. st] or "Neutral",
      session = session[name], lastGain = last[name] }
    if lr.min and lr.max and lr.value and lr.max > lr.min then r.progress, r.need = lr.value - lr.min, lr.max - lr.min end
    gained = gained + num(session[name])
    rows[#rows + 1] = r
  end
  table.sort(rows, function(a, b) if a.standing ~= b.standing then return a.standing > b.standing end return a.name < b.name end)
  return rows, { factions = #rows, gained = gained }
end
-- every reputation gain and every new standing, newest first; `only` limits it to one faction
local function buildRepHistory(only)
  local rows = {}
  for _, g in ipairs(ns.mine(ns.DB and ns.DB.story and ns.DB.story.rep)) do
    if not only or only == g.faction then
      rows[#rows + 1] = { t = num(g.t), faction = g.faction, amount = num(g.amount), change = ("+%s"):format(UI.fmtNum(num(g.amount))), source = g.src or "", zone = g.zone, sub = g.sub, x = g.x, y = g.y }
    end
  end
  for _, e in ipairs(events()) do
    if e.kind == "REP" then
      local nm = (e.text or ""):match("^(.-):%s") or e.text
      if nm and (not only or only == nm) then
        local now = (e.text or ""):match("now%s+(.+)$") or e.standing
        rows[#rows + 1] = { t = num(e.t), faction = nm, change = now and ("Now " .. now) or "New standing", source = "", zone = e.zone, sub = e.sub, x = e.x, y = e.y, milestone = true }
      end
    end
  end
  table.sort(rows, function(a, b) return a.t > b.t end)
  return rows
end

-- professions: the snapshot (name -> rank / max) with the rank it is, the recipes, the skill-ups this session and
-- the next training
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
  local recipes, session = {}, {}
  for _, r in ipairs(type(c.recipes) == "table" and c.recipes or {}) do if r.prof then recipes[r.prof] = (recipes[r.prof] or 0) + 1 end end
  local s = sid()
  for _, e in ipairs(events()) do
    if e.kind == "SKILLUP" and s and e.s == s then local p = skillOf(e); if p then session[p] = (session[p] or 0) + 1 end end
  end
  local rows = {}
  for name, pr in pairs(snap) do
    local rank, max = num(tonumber(pr.rank)), num(tonumber(pr.max))
    rows[#rows + 1] = { name = name, rank = rank, max = max, rankName = rankName(max), recipes = recipes[name] or 0,
      session = session[name] or 0, training = trainingLine(name, rank, max) }
  end
  -- a profession a craft or a recipe names that the skill lines do not (not read yet): listed, its rank unknown
  local seen = {}
  for _, r in ipairs(rows) do seen[r.name] = true end
  local named = {}
  for _, l in ipairs({ type(c.crafts) == "table" and c.crafts or {}, type(c.recipes) == "table" and c.recipes or {} }) do
    for _, x in ipairs(l) do if type(x.prof) == "string" and x.prof ~= "" and not seen[x.prof] then named[x.prof] = true end end
  end
  for name in pairs(named) do rows[#rows + 1] = { name = name, rank = -1, max = 0, recipes = recipes[name] or 0, session = session[name] or 0 } end
  table.sort(rows, function(a, b) if a.rank ~= b.rank then return a.rank > b.rank end return a.name < b.name end)
  local nRec = #(type(c.recipes) == "table" and c.recipes or {})
  return rows, { professions = #rows, recipes = nRec }
end
-- the profession and rank of a SKILLUP row: its own prof field (crafts), else its text ("Skill up:  Herbalism 7")
function skillOf(e)
  local text = stripPrefix(e.text or "", "Skill up:")
  local nm, rank = text:match("^(.-)%s+(%d+)")
  return e.prof or nm, tonumber(rank)
end
-- CRAFTED and RECIPES LEARNED, newest first
local function buildCrafts()
  local c = charDB()
  local crafts, recs, items = {}, {}, 0
  for _, r in ipairs(type(c.crafts) == "table" and c.crafts or {}) do
    crafts[#crafts + 1] = { t = num(r.t), item = r.item, count = num(r.count) > 0 and r.count or 1, prof = r.prof, id = r.id }
    items = items + (num(r.count) > 0 and r.count or 1)
  end
  for _, r in ipairs(type(c.recipes) == "table" and c.recipes or {}) do recs[#recs + 1] = { t = num(r.t), name = r.name, prof = r.prof } end
  table.sort(crafts, function(a, b) return a.t > b.t end)
  table.sort(recs, function(a, b) return a.t > b.t end)
  return crafts, recs, { crafts = #crafts, items = items }
end

-- day rows over a newest-first list (a "TODAY · 3 QUESTS" row whenever the date changes)
local function withDays(rows, word)
  local out, lastDay, head = {}, nil, nil
  for _, r in ipairs(rows) do
    local day = r.t > 0 and date("%Y-%m-%d", r.t) or "?"
    if day ~= lastDay then
      lastDay = day
      head = { ebSection = "", n = 0, t = r.t }
      out[#out + 1] = head
    end
    head.n = head.n + 1
    out[#out + 1] = r
  end
  for _, r in ipairs(out) do
    if r.ebSection then r.ebSection = (r.t > 0 and UI.fmtDay(r.t) or "EARLIER") .. " \194\183 " .. UI.plural(r.n, word) end
  end
  return out
end

-- ══ view ═══════════════════════════════════════════════════════════════════════════════════════════════════════
UI.registerHost(2, "Character", "Pace to the next level, your standing, and your skills.")
local V = {}           -- the three pages, built on first select
ns.Progress = V

-- a kit table with its section header and inline empty line, placed on a page
local function block(col, label, spec, opts)
  local b = { head = UI.Section(col, label) }
  b.tbl = UI.KitTable(col, spec, opts or {})
  return b
end
local function setTable(b, rows, fill, emptyText)
  b.tbl.setRows(rows, fill)
  if #rows == 0 then b.tbl.setState(emptyText) end
end
local COORDS = { key = "coords", label = "Coords", kind = "num", min = 72, measure = { "100.0, 100.0" }, wide = true }

-- ── Leveling ── (docs/UX_PRAGMATIC.md 3.1)
-- At the level cap the page is short: the level, when and where it was reached, the played time, and the levels
-- that have a recorded moment. A leveling character has the time to the next level with the XP bar, the cards
-- PLAYED and TIME AT LEVEL, the same Levels table and the quests turned in.
-- "Fri 20 Nov, 22:49": a fixed moment in a table cell (never "Yesterday": the row is read days later too)
local function fmtReached(t, now)
  if date("%Y", t) == date("%Y", now) then return UI.fmtSince(t, now) .. ", " .. UI.fmtClock(t) end
  return UI.fmtStamp(t, now)
end
local function buildLeveling(content)
  local v = { content = content }
  V.leveling = v
  v.pg = UI.Page(content)
  local col = v.pg.col
  v.hero = UI.Hero(col, {})
  v.cards = UI.StatRow(col, 2)
  v.levels = block(col, "Levels", {
    { key = "level", label = "Level", kind = "num", min = 48 },
    { key = "reached", label = "Reached", kind = "tag", min = 136, measure = { "Wed 28 Nov, 23:59" } },
    { key = "zone", label = "Zone", flex = 1, min = 120 },
  }, { tooltip = function(row, item, tip)
      tip:AddLine(("Level %d"):format(item.level), 1, 1, 1)
      tip:AddLine("Reached " .. UI.fmtStamp(item.t) .. (item.zone and (" in " .. item.zone) or ""), 0.78, 0.79, 0.80, true)
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
    -- the level once, when and where it was reached (left out when not stored), and the played time
    local top = levels[1] and levels[1].level == lvl and levels[1] or nil
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

  -- LEVELS: only the levels with a recorded moment; one muted line counts the rest
  v.levelsShown = #levels > 0
  if v.levelsShown then
    v.levels.head:Show(); v.levels.tbl.frame:Show()
    v.levels.tbl.setRows(levels, function(row, r)
      row.c.level:SetText(tostring(r.level))
      row.c.reached:SetText(fmtReached(r.t, now))
      row.c.zone:SetText(r.zone or "")
    end)
  else v.levels.head:Hide(); v.levels.tbl.frame:Hide() end
  v.noteShown = missing > 0
  v.noteText = v.noteShown and (missing == 1 and "1 level has no recorded date." or ("%d levels have no recorded date."):format(missing)) or nil
  if v.noteShown then
    v.levelNote:Set(v.noteText); v.levelNote:Show()
    UI.SetTip(v.levelNote, { title = "Not recorded", text = "A level is listed when its level-up was captured and is still stored." })
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

-- ── Reputation ──
local function buildRep(content)
  local v = { content = content }
  V.rep = v
  local list = CreateFrame("Frame", nil, content); list:SetAllPoints(content)
  v.list = list
  v.pg = UI.Page(list)
  local col = v.pg.col
  v.summary = UI.Summary(col)
  v.head = UI.Section(col, "Factions")
  v.tbl = UI.KitTable(col, {
    { key = "name", label = "Faction", flex = 1, min = 140 },
    { key = "standing", label = "Standing", kind = "tag", min = 88, measure = STANDINGS },
    -- (the bar, S2, then the numbers: 200 wide, or wider when the longest numbers need it)
    -- (PROGRESS heads both: the bar at the column's left, S2, then the number, left-aligned under the header)
    { key = "prog", label = "Progress", kind = "tag", justify = "LEFT", lead = 120 + S.S2, min = math.max(200, 120 + S.S2 + UI.TextWidth("BODY", "21,000 / 21,000")) },
    { key = "ses", label = "This session", kind = "num", min = 88 },
    { key = "last", label = "Last gain", kind = "tag", min = 96, wide = true, justify = "RIGHT", measure = { "Mon 16 Nov" } },
  }, { onClick = function(row) if row.item then V.openFaction(row.item) end end,
    onLayout = function(t) for i = 1, t.shownN do pcall(V.placeRepBar, t.rows[i]) end end,
    tooltip = function(row, item, tip)
      tip:AddLine(item.name, 1, 1, 1)
      tip:AddLine("Opens how you earned it.", 0.78, 0.79, 0.80, true)
      if item.need then tip:AddDoubleLine("To " .. (STANDINGS[item.standing + 1] or "the next standing"), UI.fmtNum(item.need - item.progress), C.fgMuted[1], C.fgMuted[2], C.fgMuted[3], 1, 1, 1) end
    end })
  v.detail = UI.Detail(content, { list = list, back = "\226\128\185 Reputation", render = function(item, child, d) V.renderFaction(item, child) end,
    onBack = function(item) if v.tbl.setSelected then v.tbl.setSelected(nil) end end })
  content:HookScript("OnSizeChanged", function() pcall(V.placeRep) end)
  V.renderRep()
end
function V.placeRep()
  local v = V.rep; if not v then return end
  v.pg.place({
    { v.summary, H.SUMMARY, gap = S.S3 },
    { v.head, H.SECTION }, { v.tbl.frame, v.tbl.height },
  })
end
function V.renderRep()
  local v = V.rep; if not v then return end
  local rows, sum = buildReputation()
  v.rows = rows
  local segs = { { text = ("**%s** known"):format(UI.plural(sum.factions, "faction")) } }
  if sum.gained > 0 then segs[#segs + 1] = { text = ("**+%s** reputation this session"):format(UI.fmtNum(sum.gained)) } end
  local top
  for _, r in ipairs(rows) do if num(r.session) > 0 and (not top or r.session > top.session) then top = r end end
  if top then segs[#segs + 1] = { text = "most with " .. top.name } end
  v.summary:SetSegments(segs)
  v.tbl.setRows(rows, function(row, r)
    row.c.name:SetText(r.name)
    local bad = r.standing == 1 or r.standing == 2
    row.c.standing:SetText((bad and UI.dot("bad") or "") .. r.label)
    local col = bad and C.bad or C.fgSubtle
    row.c.standing:SetTextColor(col[1], col[2], col[3])
    if not row.bar then row.bar = UI.Bar(row, 120) end
    V.placeRepBar(row)
    if r.need then
      row.bar:SetFrac(r.progress / r.need)
      row.c.prog:SetText(("%s / %s"):format(UI.fmtNum(r.progress), UI.fmtNum(r.need)))
    -- (a standing with no numbers read yet keeps its empty track and a muted "-": every row has its bar)
    else row.bar:SetFrac(0); row.c.prog:SetText("-"); UI.SetColor(row.c.prog, "fgMuted") end
    row.c.ses:SetText(num(r.session) > 0 and ("+" .. UI.fmtNum(r.session)) or "-")
    row.c.last:SetText(r.lastGain and UI.fmtDate(r.lastGain) or "-")
  end)
  if #rows == 0 then v.tbl.setState("Turn in quests or defeat a faction's enemies and your gains show here. Factions you know already are listed with their standing.") end
  V.placeRep()
end
-- the progress bar sits at the left of the Progress column, the "1,500 / 3,000" right-aligned after it
function V.placeRepBar(row)
  local cw = V.rep and V.rep.tbl.cols.prog
  if not (row and row.bar and cw) then return end
  row.bar:ClearAllPoints(); row.bar:SetPoint("LEFT", row, "LEFT", cw.x, 0)
  local fs = row.c and row.c.prog
  if fs then
    fs:ClearAllPoints(); fs:SetPoint("LEFT", row, "LEFT", cw.x + 120 + S.S2, 0)
    fs:SetWidth(math.max(1, cw.w - 120 - S.S2)); fs:SetJustifyH("LEFT")
  end
end
function V.openFaction(item)
  local v = V.rep; if not v then return end
  local idx = 1
  for i, r in ipairs(v.rows or {}) do if r.name == item.name then idx = i end end
  if v.tbl.setSelected then v.tbl.setSelected(item) end
  v.detail:Open(v.rows, idx)
end
V.FACTION = {}
function V.renderFaction(item, child)
  local f = V.FACTION
  if not f.title then
    f.col = CreateFrame("Frame", nil, child); f.col:SetPoint("TOPLEFT", child, "TOPLEFT", 0, 0)
    f.title = UI.Text(f.col, "TITLE", "fg"); f.title:SetPoint("TOPLEFT", f.col, "TOPLEFT", S.S3, 0)
    f.meta = UI.Text(f.col, "META", "fgMuted"); f.meta:SetPoint("TOPLEFT", f.col, "TOPLEFT", S.S3, -22)
    f.head = UI.Section(f.col, "How you earned it")
    f.tbl = UI.KitTable(f.col, {
      { key = "when", label = "When", kind = "tag", min = 96, measure = { "Mon 16 Nov, 23:59" } },
      { key = "source", label = "Source", flex = 1, min = 120 },
      { key = "amount", label = "Amount", kind = "num", min = 88, measure = { "Now Unfriendly" } },
    }, {})
  end
  local w = G.mainW(G.winW())
  f.col:SetWidth(w)
  f.title:SetText(item.name); f.title:SetWidth(w - 2 * S.S3)
  local parts = { (item.standing == 1 or item.standing == 2) and (UI.dot("bad") .. item.label) or item.label }
  if item.need then parts[#parts + 1] = ("%s / %s to %s"):format(UI.fmtNum(item.progress), UI.fmtNum(item.need), STANDINGS[item.standing + 1] or "the next standing") end
  if num(item.session) > 0 then parts[#parts + 1] = ("+%s this session"):format(UI.fmtNum(item.session)) end
  f.meta:SetText(table.concat(parts, " \194\183 ")); f.meta:SetWidth(w - 2 * S.S3)
  local hist = buildRepHistory(item.name)
  f.tbl.setRows(hist, function(row, h)
    row.c.when:SetText(UI.fmtWhen(h.t))
    local src = h.source ~= "" and h.source or (h.milestone and "New standing" or "Other")
    row.c.source:SetText(src)
    if h.source == "" and not h.milestone then row.c.source:SetTextColor(C.fgMuted[1], C.fgMuted[2], C.fgMuted[3]) end
    row.c.amount:SetText(h.change)
  end)
  if #hist == 0 then f.tbl.setState(("No gains for %s recorded yet."):format(item.name)) end
  f.head:ClearAllPoints(); f.head:SetPoint("TOPLEFT", f.col, "TOPLEFT", 0, -(22 + UI.LINE_H.META + S.S5)); f.head:SetWidth(w)
  local y = 22 + UI.LINE_H.META + S.S5 + H.SECTION
  f.tbl.frame:ClearAllPoints(); f.tbl.frame:SetPoint("TOPLEFT", f.col, "TOPLEFT", 0, -y); f.tbl.frame:SetWidth(w)
  y = y + (f.tbl.height or 0) + S.S4
  f.col:SetHeight(y)
  V.rep.detail.sf:SetContentHeight(y)
  f.hist = hist
end

-- ── Professions ──
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
V.GATHERING = { Herbalism = true, Mining = true, Skinning = true, Fishing = true }
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
  local textX = S.S3 + 24 + S.S2
  local room = math.max(1, barL - S.S3 - textX)
  r.meta:SetWidth(room)
  r.title:SetWidth(math.max(1, math.min(UI.TextWidth("ROW_TITLE", r.title:GetText()), room)))
  r.train:ClearAllPoints(); r.train:SetPoint("TOPLEFT", r, "TOPLEFT", barL, -26); r.train:SetWidth(math.max(1, w - barL - S.S3))
end
local function buildProf(content)
  local v = { content = content, profRows = {} }
  V.prof = v
  v.pg = UI.Page(content)
  local col = v.pg.col
  v.summary = UI.Summary(col)
  v.head = UI.Section(col, "Professions")
  v.empty = UI.EmptyLine(col)
  v.crafted = block(col, "Crafted", {
    { key = "when", label = "When", kind = "tag", min = 40, measure = { "23:59" } },
    { key = "item", label = "Item", flex = 1, min = 120 },
    { key = "prof", label = "Profession", kind = "tag", min = 104, max = 160 },
    { key = "qty", label = "Qty", kind = "num", min = 40 },
  }, { tooltip = function(row, item, tip)
      tip:AddLine(item.item or "Crafted item", 1, 1, 1)
      if not item.prof then tip:AddLine("No profession window was open when you made it.", 0.78, 0.79, 0.80, true) end
      tip:AddLine(UI.fmtWhen(item.t), 0.78, 0.79, 0.80)
    end })
  -- (grouped by day like Crafted: a day row, then each recipe at its clock time)
  v.recipes = block(col, "Recipes learned", {
    { key = "when", label = "When", kind = "tag", min = 40, measure = { "23:59" } },
    { key = "name", label = "Recipe", flex = 1, min = 120 },
    { key = "prof", label = "Profession", kind = "tag", min = 104, max = 160 },
  }, {})
  content:HookScript("OnSizeChanged", function() pcall(V.placeProf) end)
  V.renderProf()
end
function V.placeProf()
  local v = V.prof; if not v then return end
  local list = { { v.summary, H.SUMMARY, gap = S.S3 }, { v.head, H.SECTION } }
  for _, r in ipairs(v.profRows) do list[#list + 1] = { r, H.ROW2 } end
  list[#list + 1] = { v.empty, H.SECTION }
  -- the gap after the profession list sits under whichever is last: the rows or the empty line
  if v.empty:IsShown() then list[#list].gap = S.S5 else list[#list - 1].gap = S.S5 end
  list[#list + 1] = { v.crafted.head, H.SECTION }; list[#list + 1] = { v.crafted.tbl.frame, v.crafted.tbl.height, gap = S.S5 }
  list[#list + 1] = { v.recipes.head, H.SECTION }; list[#list + 1] = { v.recipes.tbl.frame, v.recipes.tbl.height }
  v.pg.place(list)
  for _, r in ipairs(v.profRows) do if r:IsShown() then pcall(r.layout); pcall(placeProfRow, r) end end
end
function V.renderProf()
  local v = V.prof; if not v then return end
  local rows, sum = buildProfessions()
  local crafts, recs, csum = buildCrafts()
  local ups = 0
  for _, r in ipairs(rows) do ups = ups + r.session end
  -- (one recipe count: the recipes the profession rows count, plus the ones no profession of yours names)
  local mapped = 0
  for _, r in ipairs(rows) do mapped = mapped + r.recipes end
  local other = math.max(0, sum.recipes - mapped)
  local segs = { { text = ("**%s**"):format(UI.plural(sum.professions, "profession")) }, { text = ("**%s** learned"):format(UI.plural(sum.recipes, "recipe")) } }
  if other > 0 then segs[#segs + 1] = { text = ("%d from other professions"):format(other) } end
  v.otherRecipes = other
  if ups > 0 then segs[#segs + 1] = { text = ("**+%d** skill this session"):format(ups) } end
  v.summary:SetSegments(segs)
  v.rows = rows
  for i, p in ipairs(rows) do
    local r = profRow(v, i)
    local known = p.max > 0   -- (a profession only a craft or a recipe names has no rank read yet)
    local meta = {}
    if known then meta[1] = p.rankName end
    -- (a gathering profession learns no recipes: no "0 recipes learned" under it)
    if not (V.GATHERING[p.name] and p.recipes == 0) then meta[#meta + 1] = UI.plural(p.recipes, "recipe") .. " learned" end
    if p.session > 0 then meta[#meta + 1] = ("+%d this session"):format(p.session) end
    r:Set({ icon = PROF_ICON[p.name] or "Interface\\Icons\\INV_Misc_Note_01", title = p.name, meta = table.concat(meta, " \194\183 "),
      tip = { title = p.name, text = known and ("%s, skill %d of %d."):format(p.rankName, p.rank, p.max)
        or "Its skill shows once the game lists it: open the profession window." } })
    -- (a profession whose rank is not read yet keeps its empty track: every row has its bar)
    r.frac = known and p.rank / p.max or 0
    r.count:SetText(known and ("%d / %d"):format(p.rank, p.max) or "-")
    r.train:SetText(p.training or "")
    r:Show()
  end
  for i = #rows + 1, #v.profRows do v.profRows[i]:Hide() end
  if #rows == 0 then v.empty:Set("Learn a profession at any trainer and its skill shows here."); v.empty:Show() else v.empty:Hide() end
  v.crafted.head:SetMeta(csum.crafts > 0 and (UI.plural(csum.crafts, "craft") .. " \194\183 " .. UI.plural(csum.items, "item")) or nil)
  setTable(v.crafted, withDays(crafts, "craft"), function(row, r)
    row.c.when:SetText(UI.fmtClock(r.t))
    row.c.item:SetText(V.unbracket(r.item) or "Crafted item")
    local q = r.id and plain(call(C_Item and C_Item.GetItemQualityByID, r.id))
    if q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q] then local qc = ITEM_QUALITY_COLORS[q]; row.c.item:SetTextColor(qc.r, qc.g, qc.b) end
    row.c.prof:SetText(r.prof or "Other")
    if not r.prof then row.c.prof:SetTextColor(C.fgMuted[1], C.fgMuted[2], C.fgMuted[3]) end
    row.c.qty:SetText(UI.fmtNum(r.count))
  end, "Craft something and it is listed here.")
  setTable(v.recipes, withDays(recs, "recipe"), function(row, r)
    row.c.when:SetText(UI.fmtClock(r.t))
    row.c.name:SetText(V.unbracket(r.name) or "")
    row.c.prof:SetText(r.prof or "Other")
    if not r.prof then row.c.prof:SetTextColor(C.fgMuted[1], C.fgMuted[2], C.fgMuted[3]) end
  end, "Learn a recipe and it is listed here.")
  V.placeProf()
end

UI.registerPane("Character", 1, "Leveling", buildLeveling, function() pcall(V.renderLeveling) end,
  "How fast you level compared with before, and where your XP comes from.")
UI.registerPane("Character", 2, "Reputation", buildRep, function() if V.rep and V.rep.detail.IsOpen() then V.rep.detail.Close() end; pcall(V.renderRep) end,
  "Your standing with every faction, and what you gained this session.")
UI.registerPane("Character", 3, "Professions", buildProf, function() pcall(V.renderProf) end,
  "Your skills, what you crafted, and when to train next.")

-- ── test exports: headless luajit tests in tests/ read these; no effect in-game ──
ns._test = ns._test or {}
ns._test.buildQuests, ns._test.buildReputation, ns._test.buildProfessions = buildQuests, buildReputation, buildProfessions
ns._test.buildLevels, ns._test.buildRepHistory, ns._test.buildCrafts = buildLevels, buildRepHistory, buildCrafts
ns._test.trainingLine = trainingLine
