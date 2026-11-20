-- The story the shots tell (tests/render_html.lua): an Orc Warrior levelling from 17 to 18 between Orgrimmar and
-- The Barrens, who ran Ragefire Chasm this session. The suite's own data (tests/play_session.lua, play_gold.lua) is an
-- Alliance character at level 12 in Westfall, and the pane tests read those names; this layer renames that data for
-- the shots only, after the suite has run, so the dungeon runs (tests/dungeon_fixture.lua), the zones, the quests,
-- the foes and the level all belong to one character.
--   S.apply(ns, M) -> undo()
local S = {}

-- the Alliance names of the suite's data and their Horde counterparts, longest first so a name inside a longer one
-- is never renamed on its own first
S.NAMES = {
  { "Stormwind Auction House", "Orgrimmar Auction House" }, { "Riverpaw Gnoll Bounty", "Wanted: Kolkar Leaders" },
  { "Defias Brotherhood Mask", "Kolkar Booty Key" }, { "The Defias Brotherhood", "Lost in Battle" },
  { "The People's Militia", "Crossroads Conscription" }, { "The Jasperlode Mine", "Sarkoth" },
  { "The Fargodeep Mine", "Thwarting Kolkar Aggression" }, { "The Killing Fields", "The Forgotten Pools" },
  { "Patrolling Westfall", "Plainstrider Menace" }, { "Red Leather Bandanas", "Centaur Bracers" },
  { "Red Silk Bandanas", "Harpy Raiders" }, { "Goretusk Liver Pie", "Raptor Thieves" }, { "Poor Old Blanchy", "Fungal Spores" },
  { "Gold Dust Exchange", "Vile Familiars" }, { "Kobold Candles", "Burning Blade Medallion" }, { "Westfall Stew", "Zhevra Hides" },
  { "Quartermaster Lewis", "Ironzar" }, { "Dungar Longdrink", "Doras" }, { "Andrew Krighton", "Rashona Straglash" },
  { "Marda Weller", "Kaja" }, { "Lyria Du Lac", "Uthrok" }, { "Wu Shen", "Sorek" },
  { "Stormwind City", "Orgrimmar" }, { "Elwynn Forest", "Durotar" }, { "Redridge Mountains", "Ashenvale" },
  { "Westfall", "The Barrens" }, { "Duskwood", "Stonetalon Mountains" }, { "Stormwind", "Orgrimmar" },
  { "Riverpaw Gnoll", "Kolkar Marauder" }, { "Riverpaw Scout", "Kolkar Outrunner" }, { "Redridge Mystic", "Razormane Mystic" },
  { "Harvest Watcher", "Plainstrider" }, { "Murloc Coastrunner", "Razormane Water Seeker" }, { "Young Forest Bear", "Savannah Huntress" },
  { "Kobold Geomancer", "Razormane Geomancer" }, { "Kobold Tunneler", "Razormane Dustrunner" }, { "Kobold Vermin", "Razormane Quilboar" },
  { "Kobold Miner", "Razormane Hunter" }, { "Defias Pillager", "Kolkar Bloodcharger" }, { "Defias Smuggler", "Kolkar Wrangler" },
  { "Defias Trapper", "Kolkar Stormer" }, { "Defias Thug", "Kolkar Pack Runner" }, { "Goretusk", "Zhevra Runner" },
  { "Darnassian Bleu", "Mulgore Spice Bread" }, { "Ironforge", "Thunder Bluff" }, { "Darnassus", "Darkspear Trolls" },
  { "Gnomeregan Exiles", "Undercity" }, { "Thor", "Bragok" },
}
S.LEVEL_SHIFT = 6       -- level 12 of the suite is level 18 of the story

local function rename(s)
  if type(s) ~= "string" or s == "" then return s end
  for _, p in ipairs(S.NAMES) do
    local a, b = p[1], p[2]
    local i = 1
    while true do
      local x, y = s:find(a, i, true)
      if not x then break end
      -- (whole words only: "Thor" in "Thorium" stays)
      local before, after = s:sub(x - 1, x - 1), s:sub(y + 1, y + 1)
      if before:match("[%w]") or after:match("[%l]") then i = y + 1
      else s = s:sub(1, x - 1) .. b .. s:sub(y + 1); i = x + #b end
    end
  end
  return s
end
S.rename = rename

local function walk(t, done)
  if done[t] then return end
  done[t] = true
  local moves = {}
  for k, v in pairs(t) do
    if type(v) == "table" then walk(v, done)
    elseif type(v) == "string" then local nv = rename(v); if nv ~= v then t[k] = nv end end
    if type(k) == "string" then local nk = rename(k); if nk ~= k then moves[#moves + 1] = { k, nk } end end
  end
  for _, m in ipairs(moves) do t[m[2]] = t[m[1]]; t[m[1]] = nil end
end

function S.apply(ns, M)
  local keep = { level = M.level, xp = M.xp, xpmax = M.xpmax, zone = M.zone, race = _G.UnitRace }
  local copy = {}
  local function deep(v, seen)
    if type(v) ~= "table" then return v end
    if seen[v] then return seen[v] end
    local o = {}; seen[v] = o
    for k, x in pairs(v) do o[deep(k, seen)] = deep(x, seen) end
    return o
  end
  for k, v in pairs(ns.DB) do copy[k] = deep(v, {}) end
  local function undo()
    M.level, M.xp, M.xpmax, M.zone, _G.UnitRace = keep.level, keep.xp, keep.xpmax, keep.zone, keep.race
    for k in pairs(ns.DB) do ns.DB[k] = nil end
    for k, v in pairs(copy) do ns.DB[k] = v end
  end
  -- the names
  local done = {}
  for k, v in pairs(ns.DB) do if k ~= "settings" and type(v) == "table" then walk(v, done) end end
  -- the character: an Orc at level 18 in Orgrimmar, 96% through the level as the suite's character was
  local d = S.LEVEL_SHIFT
  local frac = (tonumber(M.xp) or 0) / math.max(1, tonumber(M.xpmax) or 1)
  local k = 11800 / math.max(1, tonumber(M.xpmax) or 1)
  M.level = (tonumber(M.level) or 12) + d
  M.xpmax = 11800
  M.xp = math.floor(11800 * frac)
  M.zone = rename(M.zone)
  _G.UnitRace = function() return "Orc" end
  -- the XP per minute the pace reads, in the new level's scale (the time to level stays the suite's)
  local P = ns.Pace and ns.Pace.state and ns.Pace.state()
  if P then
    for m, x in pairs(P.xpm or {}) do P.xpm[m] = math.floor(x * k + 0.5) end
    P.total = math.floor((tonumber(P.total) or 0) * k + 0.5)
    if type(P.last) == "table" then P.last = { M.xp, M.xpmax, M.level } end
  end
  -- levels: the sessions' levels, /played by level, the level-up events
  local c = ns.char and ns.char()
  if c then
    if type(c.playedAtLevel) == "table" then
      local pal = {}
      for L, v in pairs(c.playedAtLevel) do pal[(tonumber(L) or 0) + d] = v end
      c.playedAtLevel = pal
    end
    if type(c.xp) == "table" then
      for _, f in ipairs({ "gained", "fromQuests", "fromKills" }) do if tonumber(c.xp[f]) then c.xp[f] = math.floor(c.xp[f] * k) end end
      if tonumber(c.xp.cur) then c.xp.cur, c.xp.max = M.xp, M.xpmax end
    end
  end
  for _, s in pairs(ns.DB.sessions or {}) do
    if type(s) == "table" then
      if tonumber(s.level) then s.level = s.level + d end
      if tonumber(s.level0) then s.level0 = s.level0 + d end
      if tonumber(s.xp) then s.xp = math.floor(s.xp * k) end
    end
  end
  for _, e in ipairs(ns.DB.story and ns.DB.story.events or {}) do
    if e.kind == "LEVELUP" or e.kind == "DEATH" then
      e.text = tostring(e.text or ""):gsub("(%d+)", function(n) return tostring(tonumber(n) + d) end, 1)
    end
    if e.kind == "QUESTDONE" and tonumber(e.xp) then e.xp = math.floor(e.xp * k) end
  end
  -- this session started at level 18 and has not dinged: its XP (and its quests' share of it) fits inside the XP
  -- the bar holds now
  local cur = ns.DB.sessions and ns.DB.sessions[ns.DB.active]
  local sx = cur and tonumber(cur.xp) or 0
  local cap = math.floor(M.xp * 0.9)
  if sx > cap then cur.xp, sx = cap, cap end
  -- and its quests earned a part of that XP, never more than the session did (the kills earned the rest)
  local qsum = 0
  for _, e in ipairs(ns.DB.story and ns.DB.story.events or {}) do
    if e.s == ns.DB.active and e.kind == "QUESTDONE" then qsum = qsum + (tonumber(e.xp) or 0) end
  end
  if qsum > 0 and qsum > sx * 0.6 then
    local f = (sx * 0.6) / qsum
    for _, e in ipairs(ns.DB.story and ns.DB.story.events or {}) do
      if e.s == ns.DB.active and e.kind == "QUESTDONE" and tonumber(e.xp) then e.xp = math.floor(e.xp * f) end
    end
  end
  -- professions: the suite records a "craft" of Linen Cloth and a "recipe" Light Leather from its own steps; neither
  -- is made at a profession window, so the story keeps only the real ones
  if c then
    local function keepOnly(list, bad)
      if type(list) ~= "table" then return end
      for i = #list, 1, -1 do local n = tostring(list[i].item or list[i].name or ""); if n:find(bad, 1, true) and not list[i].prof then table.remove(list, i) end end
    end
    keepOnly(c.crafts, "Linen Cloth")
    keepOnly(c.recipes, "Light Leather")
    -- (the suite's food recipes are learned at no profession window: in the story they are Cooking ones)
    local COOK = { ["Tasty Raptor Bites"] = true, ["Smoked Bear Meat"] = true }
    for _, r in ipairs(type(c.recipes) == "table" and c.recipes or {}) do if COOK[r.name] and not r.prof then r.prof = "Cooking" end end
  end
  -- the two level-ups of the story, when the data has none: 18 reached before this session's time at the level,
  -- 17 a day before that (Leveling's REACHED column)
  local has = {}
  for _, e in ipairs(ns.DB.story and ns.DB.story.events or {}) do if e.kind == "LEVELUP" then has[tonumber(tostring(e.text or ""):match("(%d+)") or "")] = true end end
  local pl = c and type(c.played) == "table" and c.played or {}
  local now = GetServerTime()
  local t18 = now - (tonumber(pl.level) or 3600) - 600
  ns.DB.story = ns.DB.story or {}; ns.DB.story.events = ns.DB.story.events or {}
  local evs = ns.DB.story.events
  -- (written under an earlier session of this character, so the character's lists read them and none says "this
  -- session")
  local sid
  local g = ns.charGuid and ns.charGuid()
  for id, ses in pairs(ns.DB.sessions or {}) do
    if id ~= ns.DB.active and (not g or ses.guid == g) and (not sid or (tonumber(ses.startedEpoch) or 0) < (tonumber(ns.DB.sessions[sid].startedEpoch) or 0)) then sid = id end
  end
  sid = sid or ns.DB.active
  if not has[M.level - 1] then table.insert(evs, 1, { t = t18 - 26 * 3600, kind = "LEVELUP", text = ("Ding!  Level %d"):format(M.level - 1), s = sid, zone = "Durotar" }) end
  if not has[M.level] then table.insert(evs, 2, { t = t18, kind = "LEVELUP", text = ("Ding!  Level %d"):format(M.level), s = sid, zone = "The Barrens" }) end
  return undo
end

return S
