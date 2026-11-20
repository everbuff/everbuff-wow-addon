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
        else r.unnamed = true; r.name = r.questId and ("Quest " .. r.questId) or "Quest name not given" end
      else r.name = nm end
      rows[#rows + 1] = r
    end
  end
  table.sort(rows, function(a, b) return a.t > b.t end)
  local x = charDB().xp or {}
  return rows, { done = #rows, xp = num(x.fromQuests), kills = num(x.fromKills) }
end

-- LEVELS: every level the character reached (the LEVELUP rows) and the levels /played was stamped at
local function levelOf(e) return tonumber(tostring(e.text or ""):match("(%d+)")) end
local function timeAtLevel(L, cur, now)
  local db = charDB()
  local pal = type(db.playedAtLevel) == "table" and db.playedAtLevel or {}
  local pl = type(db.played) == "table" and db.played or {}
  if L == cur and num(pl.level) > 0 then
    -- the played time since /played answered counts only while it is the same login (this session), never the time
    -- logged out
    local ses = curSession()
    local st = ses and tonumber(ses.startedEpoch)
    local since = (st and num(pl.atEpoch) >= st) and math.max(0, (now or nowT()) - num(pl.atEpoch)) or 0
    return num(pl.level) + since, true
  end
  local a, b = num(pal[L]), num(pal[L + 1])
  if a > 0 and b > a then return b - a, false end
  return nil
end
local function buildLevels(cur, now)
  now = now or nowT()
  local reached = {}
  for _, e in ipairs(events()) do
    if e.kind == "LEVELUP" then local L = levelOf(e); if L and (not reached[L] or num(e.t) < reached[L]) then reached[L] = num(e.t) end end
  end
  local db = charDB()
  local pal = type(db.playedAtLevel) == "table" and db.playedAtLevel or {}
  local pl = type(db.played) == "table" and db.played or {}
  local seen = {}
  for L in pairs(reached) do seen[L] = true end
  for L in pairs(pal) do if tonumber(L) then seen[tonumber(L)] = true end end
  if cur and cur > 0 and next(seen) then seen[cur] = true end
  local rows = {}
  for L in pairs(seen) do
    if not cur or L <= cur then
      local at, live = timeAtLevel(L, cur, now)
      local playedBy
      if L == cur and num(pl.total) > 0 and num(pl.level) > 0 then playedBy = num(pl.total) - num(pl.level)
      elseif num(pal[L]) > 0 then playedBy = num(pal[L]) end
      rows[#rows + 1] = { level = L, t = reached[L], at = at, live = live, playedBy = playedBy }
    end
  end
  table.sort(rows, function(a, b) return a.level > b.level end)
  for i, r in ipairs(rows) do
    local prev = rows[i + 1]
    -- (the level you are on is not finished: the hero compares its pace, the table only finished levels)
    if r.at and not r.live and prev and prev.level == r.level - 1 and prev.at then r.vs = r.at - prev.at end
  end
  return rows
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

-- ── Leveling ──
local function buildLeveling(content)
  local v = { content = content }
  V.leveling = v
  v.pg = UI.Page(content)
  local col = v.pg.col
  v.hero = UI.Hero(col, {})
  v.cards = UI.StatRow(col, 4)
  v.levels = block(col, "Levels", {
    { key = "level", label = "Level", kind = "num", min = 48 },
    { key = "reached", label = "Reached", flex = 1, min = 120 },
    { key = "at", label = "Time at level", kind = "num", min = 104, measure = { "10h 59m so far" } },
    { key = "played", label = "Played by then", kind = "num", min = 112 },
    { key = "vs", label = "Vs previous", kind = "tag", min = 104, justify = "RIGHT" },
  }, { tooltip = function(row, item, tip)
      tip:AddLine(("Level %d"):format(item.level), 1, 1, 1)
      tip:AddLine(item.t and ("Reached " .. UI.fmtWhen(item.t)) or "Reached before Everbuff recorded this character.", 0.78, 0.79, 0.80, true)
    end })
  v.quests = block(col, "Quests turned in", {
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
      else tip:AddLine("No gold was recorded for this quest.", 0.78, 0.79, 0.80, true) end
    end })
  UI.SetTip(v.hero, function(tip) if v.heroTip then v.heroTip(tip) end end)
  content:HookScript("OnSizeChanged", function() pcall(V.placeLeveling) end)
  V.renderLeveling()
end
function V.placeLeveling()
  local v = V.leveling; if not v then return end
  v.pg.place({
    { v.hero, H.HERO, gap = S.S3 },
    { v.cards, H.STAT, gap = S.S5 },
    { v.levels.head, H.SECTION }, { v.levels.tbl.frame, v.levels.tbl.height, gap = S.S5 },
    { v.quests.head, H.SECTION }, { v.quests.tbl.frame, v.quests.tbl.height },
  })
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
  local levels = buildLevels(lvl, now)
  local atLevel = timeAtLevel(lvl, lvl, now)
  local prevAt = timeAtLevel(lvl - 1, lvl, now)
  v.atLevel, v.remaining, v.pace = atLevel, remaining, pace
  -- hero: the comparison only Leveling has
  local hero = v.hero
  if atMax then
    hero:SetTitle("Level " .. lvl); hero:SetHero(("Level %d \194\183 max level"):format(lvl)); hero:SetMeta("No XP to earn at the level cap.", nil); hero:SetBar(nil)
    v.verdict = nil
  else
    hero:SetTitle("Level " .. lvl)
    local verdict, color
    if remaining and atLevel and prevAt then
      local d = (atLevel + remaining) - prevAt
      local word = UI.fmtDelta(d)
      if word == "same as best" then verdict = ("On pace to match level %d"):format(lvl - 1)
      else
        verdict = ("On pace to be %s than level %d"):format(word, lvl - 1)
        color = d < 0 and "good" or "warn"
        if d > 0 then verdict = UI.dot("warn", UI.DOT_SIZE.HERO) .. verdict end
      end
    elseif atLevel then verdict = ("%s at level %d so far"):format(UI.fmtDur(atLevel, { minutes = true }), lvl)
    else verdict = "Level " .. lvl end
    v.verdict = verdict
    hero:SetHero(verdict, color)
    local pct = mx > 0 and math.floor(cur / mx * 100) or 0
    local left = ("XP %s / %s \194\183 %d%%"):format(UI.fmtNum(cur), UI.fmtNum(mx), pct)
    if rested > 0 then left = left .. " \194\183 rested " .. UI.fmtNum(rested) end
    hero:SetMeta(left, remaining and (UI.fmtDur(remaining, { minutes = true }) .. " to level " .. (lvl + 1)) or "Pace shows after 10 minutes of play")
    hero:SetBar(mx > 0 and cur / mx or 0, (mx > 0 and rested > 0) and math.min(1, (cur + rested) / mx) or nil)
  end
  v.heroTip = function(tip)
    tip:AddLine("Level " .. lvl, 1, 1, 1)
    tip:AddLine("Your time at this level so far plus the time left at your XP per hour over the last 30 minutes of active play, against your time at the level before.", 0.78, 0.79, 0.80, true)
    if atLevel then tip:AddDoubleLine("At this level", UI.fmtDur(atLevel, { minutes = true }), C.fgMuted[1], C.fgMuted[2], C.fgMuted[3], 1, 1, 1) end
    if prevAt then tip:AddDoubleLine("At level " .. (lvl - 1), UI.fmtDur(prevAt, { minutes = true }), C.fgMuted[1], C.fgMuted[2], C.fgMuted[3], 1, 1, 1) end
    if pace.rate then tip:AddDoubleLine("XP per hour", UI.fmtNum(pace.rate), C.fgMuted[1], C.fgMuted[2], C.fgMuted[3], 1, 1, 1) end
  end

  -- the cards
  local cards = v.cards.cards
  local quests, qsum = buildQuests()
  local xpAll = qsum.xp + qsum.kills
  local runXP, nRuns = 0, 0
  for _, r in ipairs(type(db.dungeonRuns) == "table" and db.dungeonRuns or {}) do
    if type(r) == "table" then nRuns = nRuns + 1; runXP = runXP + num(type(r.xp) == "table" and r.xp.gain) end
  end
  if atMax then
    local pl = type(db.played) == "table" and db.played or {}
    cards[1]:Set("Played", num(pl.total) > 0 and UI.fmtDur(pl.total, { minutes = true }) or "-", "on this character")
    local perHour
    if ns.Gold and ns.Gold.metric then local ok, a = pcall(ns.Gold.metric, "perHour", "char", "session"); perHour = ok and a or nil end
    cards[2]:Set("Gold per hour", type(perHour) == "number" and UI.money(math.floor(perHour + 0.5), true) or "-", "this session")
    cards[3]:Set("Quests", UI.fmtNum(qsum.done), "turned in, all time")
    cards[4]:Set("Dungeon runs", UI.fmtNum(nRuns), "all time")
  else
    cards[1]:Set("Time at level " .. lvl, atLevel and UI.fmtDur(atLevel, { minutes = true }) or "-", "so far")
    UI.SetTip(cards[1], { title = "Time at level " .. lvl, text = atLevel and "Played time at this level, from the game's /played." or "Shows once the game answers /played." })
    local best
    for _, r in ipairs(levels) do if r.at and r.level < lvl and (not best or r.at < best.at) then best = r end end
    cards[2]:Set("Best level time", best and UI.fmtDur(best.at, { minutes = true }) or "-", best and ("level " .. best.level) or "after your next level")
    UI.SetTip(cards[2], { title = "Best level time", text = "Your fastest level on this character, in played time." })
    if xpAll > 0 then
      local q = math.floor(qsum.xp / xpAll * 100 + 0.5)
      cards[3]:Set("Quest XP share", q .. "%", ("kills %d%%, all time"):format(100 - q))
      cards[4]:Set("XP in dungeons", math.min(100, math.floor(runXP / xpAll * 100 + 0.5)) .. "%", "of all XP, all time")
    else
      cards[3]:Set("Quest XP share", "-", "after your first XP")
      cards[4]:Set("XP in dungeons", "-", "after your first XP")
    end
    UI.SetTip(cards[3], { title = "Quest XP share", text = "Of all the XP Everbuff recorded on this character, the part quests gave. Kills give the rest; dungeon XP counts in both.",
      pairs = { { "From quests", UI.fmtNum(qsum.xp) .. " XP" }, { "From kills", UI.fmtNum(qsum.kills) .. " XP" } } })
    UI.SetTip(cards[4], { title = "XP in dungeons", text = "The XP your recorded dungeon runs gave, of all the XP Everbuff recorded on this character.",
      pairs = { { "In dungeons", UI.fmtNum(runXP) .. " XP" }, { "Runs", UI.fmtNum(nRuns) } } })
  end

  -- LEVELS
  setTable(v.levels, levels, function(row, r)
    row.c.level:SetText(tostring(r.level))
    row.c.reached:SetText(r.t and UI.fmtWhen(r.t, now) or "-")
    if not r.t then row.c.reached:SetTextColor(C.fgMuted[1], C.fgMuted[2], C.fgMuted[3]) end
    row.c.at:SetText(r.at and (UI.fmtDur(r.at, { minutes = true }) .. (r.live and " so far" or "")) or "-")
    row.c.played:SetText(r.playedBy and UI.fmtDur(r.playedBy, { minutes = true }) or "-")
    if r.vs then
      local word = UI.fmtDelta(r.vs)
      if word == "same as best" then word = "same" end
      row.c.vs:SetText((r.vs > 0 and UI.dot("warn") or "") .. word)
      local col = r.vs < 0 and C.good or (r.vs > 0 and C.warn or C.fgSubtle)
      row.c.vs:SetTextColor(col[1], col[2], col[3])
    else row.c.vs:SetText("-") end
  end, "Your first level-up is timed from now.")
  -- QUESTS TURNED IN
  v.quests.head:SetMeta(#quests > 0 and UI.plural(#quests, "quest") or nil)
  local qrows = withDays(quests, "quest")
  setTable(v.quests, qrows, function(row, r)
    row.c.when:SetText(UI.fmtClock(r.t))
    row.c.name:SetText(r.name or "")
    if r.unnamed then row.c.name:SetTextColor(C.fgMuted[1], C.fgMuted[2], C.fgMuted[3]) end
    row.c.place:SetText(UI.fmtPlace(r.zone, r.sub))
    row.c.gold:SetText(r.gold and UI.money(r.gold) or "-")
    row.c.coords:SetText(UI.fmtCoords(r.x, r.y))
  end, "Turn in a quest and it shows here with its gold.")
  v.questRows = quests
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
    { key = "prog", label = "Progress", kind = "num", min = math.max(200, 120 + S.S2 + UI.TextWidth("BODY", "21,000 / 21,000")) },
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
    else row.bar:SetFrac(nil); row.c.prog:SetText("") end
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
  r.count:ClearAllPoints(); r.count:SetPoint("TOPRIGHT", r, "TOPRIGHT", -S.S3, -S.S2); r.count:SetWidth(math.max(1, cw))
  local barR = w - S.S3 - cw - S.S3
  local barL = math.max(V.BAR_X, barR - V.BAR_W)
  r.bar:ClearAllPoints(); r.bar:SetPoint("TOPLEFT", r, "TOPLEFT", barL, -(S.S2 + 5))
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
    { key = "prof", label = "Profession", kind = "tag", min = 104 },
    { key = "qty", label = "Qty", kind = "num", min = 40 },
  }, { tooltip = function(row, item, tip)
      tip:AddLine(item.item or "Crafted item", 1, 1, 1)
      if not item.prof then tip:AddLine("No profession window was open when you made it.", 0.78, 0.79, 0.80, true) end
      tip:AddLine(UI.fmtWhen(item.t), 0.78, 0.79, 0.80)
    end })
  v.recipes = block(col, "Recipes learned", {
    { key = "when", label = "When", kind = "tag", min = 96, measure = { "Mon 16 Nov, 23:59" } },
    { key = "name", label = "Recipe", flex = 1, min = 120 },
    { key = "prof", label = "Profession", kind = "tag", min = 104 },
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
  local segs = { { text = ("**%s**"):format(UI.plural(sum.professions, "profession")) }, { text = ("**%s** learned"):format(UI.plural(sum.recipes, "recipe")) } }
  if ups > 0 then segs[#segs + 1] = { text = ("**+%d** skill this session"):format(ups) } end
  v.summary:SetSegments(segs)
  v.rows = rows
  for i, p in ipairs(rows) do
    local r = profRow(v, i)
    local known = p.max > 0   -- (a profession only a craft or a recipe names has no rank read yet)
    local meta = {}
    if known then meta[1] = p.rankName end
    meta[#meta + 1] = UI.plural(p.recipes, "recipe") .. " learned"
    if p.session > 0 then meta[#meta + 1] = ("+%d this session"):format(p.session) end
    r:Set({ icon = PROF_ICON[p.name] or "Interface\\Icons\\INV_Misc_Note_01", title = p.name, meta = table.concat(meta, " \194\183 "),
      tip = { title = p.name, text = known and ("%s, skill %d of %d."):format(p.rankName, p.rank, p.max)
        or "Its skill shows once the game lists it: open the profession window." } })
    r.frac = known and p.rank / p.max or nil
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
  setTable(v.recipes, recs, function(row, r)
    row.c.when:SetText(UI.fmtWhen(r.t))
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
