-- Everbuff.GG · Journey.lua - Home: Now (this session at a glance) and Sessions.
--
-- Now answers, with no click: am I recorded (the title-bar chip), how is this session going (the hero and the four
-- cards), when do I ding (the hero), what needs me (NEXT) and what happened worth a look (WORTH A LOOK). Everything
-- is READ from data other modules capture (the session record, the story events, the loot log, the stored runs, the
-- gold ledger), plus the leveling pace (ns.Pace below), measured live from UnitXP while the addon runs
-- (docs/UX_OVERHAUL.md 4.1).

local ADDON, ns = ...
local UI = ns.UI
local C = ns.UI.C
local S, G, H = UI.S, UI.G, UI.H

local fmtMoney = ns.fmtMoney   -- the one formatter (UI.lua)
local function nowT() return (GetServerTime and GetServerTime()) or time() end
local function num(v) return (type(v) == "number" and v == v) and v or 0 end
local function curSession() return (ns.Recorder and ns.Recorder.current and ns.Recorder.current()) or nil end
-- the answers of a client call, nothing when it is missing or blocked
local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c, d, e, f = pcall(fn, ...)
  if not ok then return nil end
  return a, b, c, d, e, f
end
local function plain(v) if type(v) == "number" and not (issecretvalue and issecretvalue(v)) then return v end return nil end

-- ══ ns.Pace: the leveling pace (4.1 Pace definition) ═════════════════════════════════════════════════════════
-- A minute of the session is active when the player is not away (UnitIsAFK) and an XP, kill or loot event came in
-- that minute or the 4 before it (the last 5 minutes). The rate is the XP of the last 30 active minutes over those
-- minutes, times 60 (all active minutes while there are fewer than 30); it shows after 10 active minutes. The time
-- to the next level is what is left over the rate. XP is the live UnitXP delta since the session started, kept in
-- memory: nothing is stored (a /reload starts the measure again).
local Pace = { WINDOW = 30, WARM = 10, IDLE = 5, SCAN = 1440 }
ns.Pace = Pace
local P = { xpm = {}, ev = {}, afk = {}, total = 0 }
function Pace.state() return P end
local function readXP()
  local cur, mx, lvl = plain(call(UnitXP, "player")), plain(call(UnitXPMax, "player")), plain(call(UnitLevel, "player"))
  if not (cur and mx) then return nil end
  return cur, mx, lvl
end
-- the session the measure belongs to: a new session starts it over (the last reading carries over, so the first
-- gain of the new session counts)
function Pace.sync()
  local ses = curSession()
  local sid = ses and ses.id
  if sid ~= P.sid then
    P.sid, P.start = sid, ses and plain(ses.startedEpoch)
    P.xpm, P.ev, P.afk, P.total, P.kill = {}, {}, {}, 0, nil
  end
end
function Pace.mark(t) P.ev[math.floor(t / 60)] = true end
function Pace.baseline()
  if P.last then return end
  local cur, mx, lvl = readXP()
  if cur then P.last = { cur, mx, lvl } end
end
-- PLAYER_XP_UPDATE: the gain since the last reading. A lower reading is a level up (the client can answer the new
-- XP before the new level): what was left of the old level plus the new XP.
function Pace.onXP(t)
  t = t or nowT()
  Pace.sync()
  local cur, mx, lvl = readXP()
  if not cur then return end
  local last = P.last
  P.last = { cur, mx, lvl }
  if not last then return end
  local gain
  if (lvl and last[3] and lvl > last[3]) or cur < last[1] then gain = math.max(0, num(last[2]) - num(last[1])) + cur
  else gain = cur - last[1] end
  if gain > 0 then
    local m = math.floor(t / 60)
    P.xpm[m] = (P.xpm[m] or 0) + gain
    P.total = P.total + gain
    P.ev[m] = true
  end
end
function Pace.onKill(name, xp, t)
  Pace.sync(); Pace.mark(t or nowT())
  if type(name) == "string" and name ~= "" and num(xp) > 0 then P.kill = { name = name, xp = xp } end
end
function Pace.onAfk(t)
  local ok, v = pcall(function() return UnitIsAFK and UnitIsAFK("player") end)
  if ok and not (issecretvalue and issecretvalue(v)) and v == true then Pace.sync(); P.afk[math.floor((t or nowT()) / 60)] = true end
end
-- { xp = this session, active = active minutes, used = minutes the rate reads, sum = their XP, rate = XP per hour
-- (nil before 10 active minutes) }
function Pace.compute(now)
  now = now or nowT()
  Pace.sync()
  local out = { xp = P.total, active = 0, used = 0, sum = 0 }
  local nm = math.floor(now / 60)
  local sm = P.start and math.floor(P.start / 60) or (nm - Pace.SCAN)
  sm = math.max(sm, nm - Pace.SCAN)
  for m = nm, sm, -1 do
    if not P.afk[m] then
      local act = false
      for k = m - (Pace.IDLE - 1), m do if P.ev[k] then act = true; break end end
      if act then
        out.active = out.active + 1
        if out.used < Pace.WINDOW then out.used = out.used + 1; out.sum = out.sum + (P.xpm[m] or 0) end
      end
    end
  end
  if out.used >= Pace.WARM and out.sum > 0 then out.rate = out.sum / out.used * 60 end
  return out
end
-- seconds to the next level at `rate` XP per hour, nil without a rate
function Pace.remaining(cur, mx, rate)
  if not (rate and rate > 0 and mx and cur and mx > cur) then return nil end
  return (mx - cur) / rate * 3600
end
-- "Bristleback Quilboar dies, you gain 45 experience." (the client's English line; another locale only marks activity)
local function xpLine(msg)
  if type(msg) ~= "string" or (issecretvalue and issecretvalue(msg)) then return nil end
  local name, xp = msg:match("^(.-) dies, you gain (%d+) experience")
  return name, tonumber(xp)
end
Pace.xpLine = xpLine
do
  local ef = CreateFrame("Frame")
  ns.eventFrames = ns.eventFrames or {}
  ns.eventFrames[#ns.eventFrames + 1] = ef
  for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_XP_UPDATE", "CHAT_MSG_COMBAT_XP_GAIN", "CHAT_MSG_LOOT", "PLAYER_FLAGS_CHANGED" }) do
    pcall(ef.RegisterEvent, ef, e)
  end
  ef:SetScript("OnEvent", function(_, ev, a1)
    pcall(function()
      local t = nowT()
      if ev == "PLAYER_XP_UPDATE" then Pace.onXP(t)
      elseif ev == "PLAYER_ENTERING_WORLD" then Pace.sync(); Pace.baseline()
      elseif ev == "CHAT_MSG_COMBAT_XP_GAIN" then local n, x = xpLine(a1); Pace.onKill(n, x, t)
      elseif ev == "CHAT_MSG_LOOT" then Pace.sync(); Pace.mark(t)
      elseif ev == "PLAYER_FLAGS_CHANGED" then Pace.onAfk(t) end
    end)
  end)
  if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(60, function() pcall(Pace.onAfk, nowT()) end) end
end

-- ══ HOME / Now ═══════════════════════════════════════════════════════════════════════════════════════════════
UI.KIND_ICON = {
  death = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01", run = "Interface\\Icons\\INV_Misc_Map_01",
  level = "Interface\\Icons\\Spell_Holy_SurgeOfLight", quest = "Interface\\Icons\\INV_Misc_Note_01",
  lockout = "Interface\\Icons\\INV_Misc_Key_04", repair = "Interface\\Icons\\Trade_BlackSmithing",
  bags = "Interface\\Icons\\INV_Misc_Bag_08", instance = "Interface\\Icons\\INV_Misc_PocketWatch_01",
  loot = "Interface\\Icons\\INV_Misc_Bag_10",     -- (a loot row shows the item's own icon; this one only without it)
  session = "Interface\\Icons\\INV_Misc_PocketWatch_02",
  gold = "Interface\\Icons\\INV_Misc_Coin_01",
}
local Now = { CAP_COMPACT = 4, CAP_WIDE = 12, NEXT_CAP = 3, REPAIR_WARN = 45, REPAIR_BAD = 20, BAGS_BAD = 2 }
ns.Now = Now
local SLOT_NAME = { [1] = "Head", [2] = "Neck", [3] = "Shoulder", [5] = "Chest", [6] = "Waist", [7] = "Legs", [8] = "Feet",
  [9] = "Wrist", [10] = "Hands", [11] = "Finger", [12] = "Finger", [13] = "Trinket", [14] = "Trinket", [15] = "Back",
  [16] = "Main hand", [17] = "Off hand", [18] = "Ranged" }

-- whole names that fit `width` in META, then "+N"
local function fitNames(names, width)
  local out, shown = "", 0
  for i, n in ipairs(names) do
    local rest = #names - i
    local cand = (shown > 0 and (out .. ", ") or "") .. n
    local tail = rest > 0 and (" +" .. rest) or ""
    if shown > 0 and UI.TextWidth("META", cand .. tail) > width then break end
    out, shown = cand, shown + 1
  end
  if shown < #names then out = out .. " +" .. (#names - shown) end
  return out
end
Now.fitNames = fitNames

-- the live readings NEXT acts on, each nil when the client cannot answer
function Now.freeBagSlots()
  local f = (C_Container and C_Container.GetContainerNumFreeSlots) or GetContainerNumFreeSlots
  if type(f) ~= "function" then return nil end
  local n, any = 0, false
  for bag = 0, 4 do
    local free, fam = call(f, bag)
    free, fam = plain(free), plain(fam)
    if free then any = true; if not fam or fam == 0 then n = n + free end end
  end
  return any and n or nil
end
-- the lowest equipped slot in percent, and every slot at or under the repair line
function Now.durability()
  if type(GetInventoryItemDurability) ~= "function" then return nil end
  local low, worn = nil, {}
  for slot = 1, 18 do
    local c, m = call(GetInventoryItemDurability, slot)
    c, m = plain(c), plain(m)
    if c and m and m > 0 then
      local pct = math.floor(c / m * 100)
      if not low or pct < low then low = pct end
      if pct <= Now.REPAIR_WARN then worn[#worn + 1] = { slot = slot, pct = pct } end
    end
  end
  table.sort(worn, function(a, b) if a.pct ~= b.pct then return a.pct < b.pct end return a.slot < b.slot end)
  return low, worn
end
-- the quest log entries whose objectives are complete (the 6th answer of GetQuestLogTitle is 1)
function Now.questsReady()
  if type(GetQuestLogTitle) ~= "function" or type(GetNumQuestLogEntries) ~= "function" then return nil end
  local n = plain(call(GetNumQuestLogEntries)) or 0
  local out = {}
  for i = 1, n do
    local title, _, _, isHeader, _, isComplete = call(GetQuestLogTitle, i)
    if type(title) == "string" and not isHeader and isComplete == 1 then out[#out + 1] = title end
  end
  return out
end

-- NEXT: what needs the player, at most 3, in rank order (4.1)
function Now.nextItems(width, now)
  now = now or nowT()
  local out = {}
  local free = Now.freeBagSlots()
  if free and free <= Now.BAGS_BAD then
    out[#out + 1] = { kind = "bags", icon = UI.KIND_ICON.bags, dot = "bad",
      title = ("Bags almost full: %s"):format(UI.plural(free, "free slot")), meta = "Sell grey items at a vendor" }
  end
  local low, worn = Now.durability()
  if low and low <= Now.REPAIR_WARN then
    local rows = {}
    for _, w in ipairs(worn) do rows[#rows + 1] = { SLOT_NAME[w.slot] or ("Slot " .. w.slot), w.pct .. "%" } end
    out[#out + 1] = { kind = "repair", icon = UI.KIND_ICON.repair, dot = low <= Now.REPAIR_BAD and "bad" or "warn",
      title = ("Repair soon: your lowest item is at %d%%"):format(low), meta = "Any repair vendor fixes it",
      tip = { title = "Repair soon", text = "Your equipped items at 45% or below.", pairs = rows } }
  end
  local lim = ns.Runs and ns.Runs.limit and ns.Runs.limit()
  if lim then
    local hour, _, rows = ns.Runs.copies(now)
    local left = lim - hour
    if left <= 1 then
      local oldest
      for _, r in ipairs(rows or {}) do if r.t > now - 3600 and (not oldest or r.t < oldest) then oldest = r.t end end
      local nextIn = oldest and math.max(0, oldest + 3600 - now) or nil
      out[#out + 1] = { kind = "instance", icon = UI.KIND_ICON.instance, dot = left <= 0 and "bad" or "warn",
        title = left <= 0 and "No instances left this hour" or "1 instance left this hour",
        meta = nextIn and ("Next free in " .. UI.fmtDur(nextIn, { minutes = true })) or ("Your own limit: " .. UI.plural(lim, "instance") .. " an hour"),
        onClick = function() UI.Open("Dungeons", "runs") end }
    end
  end
  local ready = Now.questsReady()
  if ready and #ready > 0 then
    out[#out + 1] = { kind = "quest", icon = UI.KIND_ICON.quest,
      title = ("%s ready to turn in"):format(UI.plural(#ready, "quest")), meta = fitNames(ready, width or 400) }
  end
  while #out > Now.NEXT_CAP do table.remove(out) end
  return out
end

-- The stored records of "this session", newest first: logins less than 5 minutes apart are one session
-- (docs/UX_PRAGMATIC.md 0.2.4; Gold.joined is the one definition, the Session period of Loot > Gold reads it too).
local function sessionParts(ses)
  if not ses then return {} end
  if ns.Gold and ns.Gold.joined then
    local ok, j = pcall(ns.Gold.joined, ses)
    if ok and type(j) == "table" and #j > 0 then return j end
  end
  return { ses }
end
Now.sessionParts = sessionParts
-- when this session started: the first of its logins
local function sessionStart(ses)
  local p = sessionParts(ses)
  return p[#p] and plain(p[#p].startedEpoch) or nil
end
-- the story events of this session that are the logged-in character's, oldest first
local function sessionEvents(ses)
  local out = {}
  if not (ses and ses.id) then return out end
  local ids = {}
  for _, s in ipairs(sessionParts(ses)) do if s.id then ids[s.id] = true end end
  for _, e in ipairs((ns.DB and ns.DB.story and ns.DB.story.events) or {}) do
    if type(e) == "table" and e.s ~= nil and ids[e.s] and ns.isMine(e) then out[#out + 1] = e end
  end
  return out
end
Now.sessionEvents = sessionEvents
local function fightAt(t)
  for _, f in ipairs((ns.Fights and ns.Fights.list and ns.Fights.list()) or {}) do
    local s0 = num(f.startEpoch)
    if s0 > 0 and t >= s0 - 1 and t <= s0 + num(f.duration) + 2 then return f end
  end
  return nil
end
local function qHex(q) q = type(q) == "string" and q:lower() or "ffffffff"; return #q == 8 and q or "ffffffff" end
local function sellPrice(id)
  if not id then return 0 end
  local fn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  if type(fn) ~= "function" then return 0 end
  local ok, r = pcall(function() return select(11, fn(id)) end)
  return (ok and plain(r)) or 0
end
-- an item or source name without its link markup and brackets
local function stripLink(s)
  s = tostring(s or "")
  s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h", ""):gsub("|h", "")
  return (s:gsub("^%[", ""):gsub("%]$", ""))
end
Now.stripLink = stripLink
Now.sellPrice = sellPrice
-- whether the character is at the level cap (By dungeon sorts by gold per hour then)
function Now.atMax()
  local l = plain(call(UnitLevel, "player")) or 0
  return l >= (plain(call(GetMaxPlayerLevel)) or 60)
end

-- Whether Home > Deaths has a page now (Deaths.lua hides the tab while no stored death names its killer). Every
-- link to it asks this, so no click on Now goes nowhere.
function Now.deathsOpen() return UI.SubVisible ~= nil and UI.SubVisible("Home", "deaths") == true end
-- the stored run record (the open one too) a moment falls in, or nil
function Now.runRecAt(t)
  if not (ns.Runs and ns.Runs.views) or num(t) <= 0 then return nil end
  local ok, vs = pcall(ns.Runs.views, false)
  for _, v in ipairs(ok and vs or {}) do
    local a, z = num(v.startT), v.inProgress and math.huge or num(v.endT)
    if a > 0 and t >= a and t <= z and v.rec then return v.rec end
  end
  return nil
end
-- WORTH A LOOK: what happened this session, in rank order, newest first within a rank (4.1)
function Now.lookItems(now)
  now = now or nowT()
  local ses = curSession()
  local start = sessionStart(ses) or now
  local ev = sessionEvents(ses)
  local out, extra = {}, {}
  -- 1 deaths, at most 2, then a link row for the rest
  local deaths = {}
  for i = #ev, 1, -1 do if ev[i].kind == "DEATH" then deaths[#deaths + 1] = ev[i] end end
  for i, e in ipairs(deaths) do
    if i > 2 then break end
    local f = fightAt(num(e.t))
    local parts = { UI.fmtClock(e.t) }
    if type(e.zone) == "string" and e.zone ~= "" then parts[#parts + 1] = e.zone end
    if f and num(f.duration) > 0 then parts[#parts + 1] = "in a " .. UI.fmtDur(f.duration) .. " pull" end
    -- (a row opens a page that exists: Deaths while that tab has one, else the run the death happened in, whose page
    -- lists its deaths; with neither the row opens nothing and has no chevron)
    local open
    if Now.deathsOpen() then open = function() UI.Open("Home", "deaths") end
    else
      local rec = Now.runRecAt(num(e.t))
      if rec then open = function() UI.Open("Dungeons", "runs"); if ns.Dungeons and ns.Dungeons.openRun then pcall(ns.Dungeons.openRun, rec) end end end
    end
    out[#out + 1] = { kind = "death", rank = 1, t = num(e.t), icon = UI.KIND_ICON.death,
      title = (type(e.foe) == "string" and e.foe ~= "") and ("Died to " .. e.foe) or "You died",
      meta = table.concat(parts, " \194\183 "), onClick = open }
  end
  if #deaths > 2 then extra.deaths = #deaths - 2 end
  -- 2 dungeon runs of this session, one row each, at most 2
  local runs = {}
  if ns.Runs and ns.Runs.views then
    local ok, vs = pcall(ns.Runs.views, false)
    for _, v in ipairs(ok and vs or {}) do
      if v.inProgress or num(v.startT) >= start then runs[#runs + 1] = v end
    end
  end
  table.sort(runs, function(a, b) return num(a.startT) > num(b.startT) end)
  -- (the run rows speak the Runs page's words: its boss total, its TIME clock and its first run / best / delta word,
  -- through the Dungeons helpers, so the two screens never tell one run two ways)
  local DD = ns.Dungeons and ns.Dungeons.D
  local today = date("%Y-%m-%d", now)
  for i, v in ipairs(runs) do
    if i > 2 then break end
    local name = v.name or "Dungeon"
    -- (a total only when it is known, Dungeons.lua D.totalOf: "2 of 4 bosses", else the kills alone, "7 bosses")
    local total = (DD and DD.totalOf) and DD.totalOf(v) or nil
    local down = num(v.bossesDown)
    local bosses = (DD and DD.bossWord and (total or down > 0)) and DD.bossWord(v) or "no boss killed"
    local word, wkey, kind = "", nil, "none"
    if DD and DD.vsBest then word, wkey, kind = DD.vsBest(v) end
    local title, badge, bar
    if v.inProgress then title, badge = ("%s: %s so far"):format(name, bosses), "IN PROGRESS"
    elseif kind == "first" then title = ("%s: %s"):format(name, bosses)
    elseif kind == "best" then title, badge, bar = ("%s: your best run, %s"):format(name, bosses), "BEST", "good"
    elseif kind == "slower" and word ~= "" then title = ("%s: %s, %s than your best"):format(name, bosses, word)
    else title = ("%s: %s"):format(name, bosses) end
    local who = {}
    for _, d in ipairs(v.deathRows or {}) do if type(d) == "table" and type(d.who) == "string" then who[#who + 1] = d.who end end
    -- (a run from another day carries its date; the time is the Runs page's TIME, inside the dungeon)
    local parts = { date("%Y-%m-%d", num(v.startT)) == today and UI.fmtClock(v.startT) or UI.fmtWhen(v.startT), UI.fmtDur(v.inside) }
    if #who > 0 then parts[#parts + 1] = fitNames(who, 160) .. " died"
    elseif num(v.deaths) + num(v.partyDeaths) > 0 then parts[#parts + 1] = UI.plural(num(v.deaths) + num(v.partyDeaths), "death")
    else parts[#parts + 1] = "nobody died" end
    if num(v.xpGain) > 0 then parts[#parts + 1] = "+" .. UI.fmtNum(v.xpGain) .. " XP" end
    local rec = v.rec
    out[#out + 1] = { kind = "run", rank = 2, t = num(v.startT), icon = UI.KIND_ICON.run, title = title, badge = badge, bar = bar,
      meta = table.concat(parts, " \194\183 "), inst = name, metaParts = parts,
      onClick = function() UI.Open("Dungeons", "runs"); if ns.Dungeons and ns.Dungeons.openRun then pcall(ns.Dungeons.openRun, rec) end end }
  end
  -- 3 level-ups
  local db = (ns.DB and ns.char()) or {}
  -- (the /played stamps: the played total when each level was reached, read only from a block whose stamps are
  -- all of that kind, 0.9.52; the time at level L is then the stamp of L + 1 minus the stamp of L)
  local pal = (db.playedExact and type(db.playedAtLevel) == "table") and db.playedAtLevel or {}
  for i = #ev, 1, -1 do
    local e = ev[i]
    if e.kind == "LEVELUP" then
      local lvl = tonumber(tostring(e.text or ""):match("(%d+)%s*$"))
      local meta = { UI.fmtClock(e.t) }
      if lvl and pal[lvl] and pal[lvl - 1] then
        local took = num(pal[lvl]) - num(pal[lvl - 1])
        if took > 0 then meta[#meta + 1] = UI.fmtDur(took, { minutes = true }) .. " at level " .. (lvl - 1) end
        if took > 0 and pal[lvl - 2] then
          local before = num(pal[lvl - 1]) - num(pal[lvl - 2])
          if before > 0 then
            local d = UI.fmtDelta(took - before)
            if d ~= "same as best" then meta[#meta + 1] = d .. " than level " .. (lvl - 2) end
          end
        end
      end
      out[#out + 1] = { kind = "level", rank = 3, t = num(e.t), icon = UI.KIND_ICON.level,
        title = lvl and ("Reached level " .. lvl) or "Level up", meta = table.concat(meta, " \194\183 ") }
    end
  end
  -- 4 the best drop of the session, green and better: the highest quality, then the highest vendor price
  local best, bestRank, bestPrice
  local sid = ses and ses.id
  for _, l in ipairs((ns.DB and ns.DB.loot and ns.DB.loot.log) or {}) do
    -- (of the live session, and a drop: a kill or a container, never a quest reward or a mail)
    local drop = type(l) == "table" and (not (DD and DD.isDrop) or DD.isDrop(l))
    if type(l) == "table" and sid and l.s == sid and l.item and not l.money and drop then
      local rank = ns.Runs and ns.Runs.qRank and ns.Runs.qRank(l.q) or 1
      if rank >= 2 then
        local price = sellPrice(l.id)
        if not best or rank > bestRank or (rank == bestRank and price > bestPrice) then best, bestRank, bestPrice = l, rank, price end
      end
    end
  end
  if best then
    local meta = {}
    -- (where it dropped: the dungeon of a run of this session that holds its moment, else the zone, else the source)
    local from
    for _, v in ipairs(runs) do
      local t0, t1 = num(v.startT), num(v.endT) > 0 and num(v.endT) or now
      if num(best.t) >= t0 and num(best.t) <= t1 then from = v.name end
    end
    from = from or (type(best.zone) == "string" and best.zone ~= "" and best.zone) or (type(best.src) == "string" and best.src ~= "" and stripLink(best.src)) or nil
    if from then meta[#meta + 1] = "From " .. from end
    if bestPrice > 0 then meta[#meta + 1] = "vendor price " .. UI.money(bestPrice) end
    if #meta == 0 then meta[1] = UI.fmtClock(best.t) end
    out[#out + 1] = { kind = "loot", rank = 4, t = num(best.t), icon = best.icon or UI.KIND_ICON.loot,
      -- (A12: the words in fg, only the item name in its quality colour)
      title = "Best drop: |c" .. qHex(best.q) .. stripLink(best.item) .. "|r", meta = table.concat(meta, " \194\183 "),
      onClick = function() UI.Open("Loot", "items") end }
  end
  -- 5 quests turned in, one row
  local quests, lastQ, lastT, qxp = 0, nil, 0, 0
  for _, e in ipairs(ev) do
    if e.kind == "QUESTDONE" then
      quests = quests + 1
      qxp = qxp + num(e.xp)
      local n = tostring(e.text or ""):match("^Complete:%s+(.+)$")
      if n and n ~= "" then lastQ = n end
      lastT = num(e.t)
    end
  end
  if quests > 0 then
    local meta = {}
    local okq, qm = false, nil
    if ns.Gold and ns.Gold.metric then okq, qm = pcall(ns.Gold.metric, "quests", "char", "session") end
    -- ("+N XP · coin · last: name": the XP of the turn-ins, their coin, the last one)
    if qxp > 0 then meta[#meta + 1] = "+" .. UI.fmtNum(qxp) .. " XP" end
    if okq and type(qm) == "number" and qm > 0 then meta[#meta + 1] = UI.money(qm) end
    if lastQ then meta[#meta + 1] = "last: " .. lastQ end
    out[#out + 1] = { kind = "quest", rank = 5, t = lastT, icon = UI.KIND_ICON.quest,
      title = UI.plural(quests, "quest") .. " turned in", meta = table.concat(meta, " \194\183 "),
      onClick = function() UI.Open("Character", "leveling") end }
  end
  -- 6 lockouts that still hold; the › opens the run of that dungeon inside the lockout's life
  for _, l in ipairs(type(db.lockouts) == "table" and db.lockouts or {}) do
    if type(l) == "table" and num(l.resetAt) > now and type(l.name) == "string" then
      local title = (l.bosses and l.down) and ("%s: %d of %d bosses down"):format(l.name, l.down, l.bosses) or (l.name .. ": saved")
      local match
      for _, rec in ipairs(type(db.dungeonRuns) == "table" and db.dungeonRuns or {}) do
        if type(rec) == "table" and type(rec.inst) == "string" and rec.inst:lower() == l.name:lower() and num(rec.t) > now - 7 * 86400
          and (not match or num(rec.t) > num(match.t)) then match = rec end
      end
      local runRow
      for _, o in ipairs(out) do if o.kind == "run" and type(o.inst) == "string" and o.inst:lower() == l.name:lower() then runRow = o end end
      if runRow then
        -- (the run row already names the dungeon and its bosses: the lockout adds only when it resets)
        runRow.meta = runRow.meta .. " \194\183 resets in " .. UI.fmtDur(l.resetAt - now, { minutes = true })
      else
      out[#out + 1] = { kind = "lockout", rank = 6, t = num(l.resetAt), icon = UI.KIND_ICON.lockout, title = title,
        meta = "Resets in " .. UI.fmtDur(l.resetAt - now, { minutes = true }),
        tip = (not match) and { title = l.name, text = "Saved before everbuff.gg captured this dungeon on this character." } or nil,
        onClick = match and function() UI.Open("Dungeons", "runs"); if ns.Dungeons and ns.Dungeons.openRun then pcall(ns.Dungeons.openRun, match) end end or nil }
      end
    end
  end
  table.sort(out, function(a, b) if a.rank ~= b.rank then return a.rank < b.rank end return a.t > b.t end)
  return out, extra, ev
end

-- A per hour figure needs this much play behind it (docs/UX_PRAGMATIC.md 1.1, 4.2): 9 minutes of play gave
-- "-198g 87s per hour", a number that says nothing.
Now.RATE_FLOOR = 30 * 60
-- The session's gold as the max level hero reads it: whether any moved, the net, and the rate only from
-- Now.RATE_FLOOR of play on. Every figure is the session ledger's (Gold.metric); nil when the ledger cannot be read.
function Now.sessionGold()
  if not (ns.Gold and ns.Gold.metric) then return nil end
  local function m(id) local ok, v = pcall(ns.Gold.metric, id, "char", "session"); return (ok and type(v) == "number") and v or nil end
  local gained, spent, net, played = m("gained"), m("spent"), m("net"), m("played")
  if not (gained and spent and net) then return nil end
  local out = { moved = gained > 0 or spent > 0, net = net, gained = gained, spent = spent, played = num(played) }
  if out.moved and out.played >= Now.RATE_FLOOR then out.perHour = math.floor(net * 3600 / out.played + 0.5) end
  return out
end
-- The newest stored run record as the LAST RUN card reads it: { name, meta, rec }, or nil with none stored.
-- "Fri 20 Nov · 1h 9m · 7 bosses · 2 deaths": the day, the time inside, the bosses killed, your deaths. A card too
-- narrow for the line (`width`, in px of META text) gets the day without its weekday, then the line without the day:
-- the run's page has it. No part is ever cut mid-word.
function Now.lastRun(now, width)
  if not (ns.Runs and ns.Runs.views and ns.Dungeons and ns.Dungeons.D) then return nil end
  local ok, vs = pcall(ns.Runs.views, false)
  local last
  for _, v in ipairs(ok and vs or {}) do
    if not v.inProgress and v.rec and num(v.startT) > 0 and (not last or num(v.startT) > num(last.startT)) then last = v end
  end
  if not last then return nil end
  local D = ns.Dungeons.D
  local rest = { D.fmtLen(last.inside) }
  if num(last.bossesDown) > 0 then rest[#rest + 1] = UI.plural(last.bossesDown, "boss", "bosses") end
  if num(last.deaths) > 0 then rest[#rest + 1] = UI.plural(last.deaths, "death") end
  local tail = table.concat(rest, " \194\183 ")
  local day = UI.fmtSince(last.startT, now)
  local meta = day .. " \194\183 " .. tail
  if width and UI.TextWidth("META", meta) > width then meta = (day:gsub("^%a+ ", "")) .. " \194\183 " .. tail end
  if width and UI.TextWidth("META", meta) > width then meta = tail end
  -- (still too long: whole parts go from the end, the time inside stays)
  while width and #rest > 1 and UI.TextWidth("META", meta) > width do
    table.remove(rest)
    meta = table.concat(rest, " \194\183 ")
  end
  return { name = last.name or "Dungeon", meta = meta, rec = last.rec }
end
-- WORTH A LOOK at the level cap: the up to 3 largest gold lines of the session, largest first. Each is a journal row
-- of the session (Gold.entries): what it was, then the amount, its source and the time. None: an empty list, and
-- the section is not shown.
Now.GOLD_LINES = 3
function Now.goldLines()
  local ses = curSession()
  if not (ses and ns.Gold and ns.Gold.scope and ns.Gold.scopeEntries) then return {} end
  -- (the rows of every login of this session: the same list the Session period of Loot > Gold shows)
  local ok, rows = pcall(function() return ns.Gold.scopeEntries(ns.Gold.scope("session")) end)
  if not (ok and type(rows) == "table") then return {} end
  local list = {}
  for _, r in ipairs(rows) do if type(r.delta) == "number" and r.delta ~= 0 then list[#list + 1] = r end end
  table.sort(list, function(a, b)
    if math.abs(a.delta) ~= math.abs(b.delta) then return math.abs(a.delta) > math.abs(b.delta) end
    return num(a.t) > num(b.t)
  end)
  local out = {}
  for i = 1, math.min(Now.GOLD_LINES, #list) do
    local r = list[i]
    local label = ns.Gold.LABEL and ns.Gold.LABEL[r.src] or nil
    local word = ns.Gold.WORD and ns.Gold.WORD[r.src] or nil
    local title = (type(r.detail) == "string" and r.detail ~= "") and r.detail or word or label or "Gold"
    -- (a flight or a training row's detail is only the name of who was paid: "Flight: Tal")
    if (r.src == "flights" or r.src == "training") and word and title ~= word then title = word .. ": " .. title end
    -- (a sale's detail is the item alone; beside "Bought Black Lotus x3" it says which way the gold went)
    if r.src == "auctionSales" and title == r.detail then title = "Sold " .. title end
    local parts = { UI.money(r.delta, true) }
    if label and label ~= title then parts[#parts + 1] = label end
    parts[#parts + 1] = UI.fmtClock(r.t)
    out[#out + 1] = { kind = "gold", rank = 1, t = num(r.t), icon = UI.KIND_ICON.gold or UI.KIND_ICON.session, title = title,
      meta = table.concat(parts, " \194\183 "),
      onClick = function() if ns.Gold and ns.Gold.open then ns.Gold.open("session", "journal") else UI.Open("Loot", "gold") end end }
  end
  return out
end

local nowView
local noticeOff = false   -- the combat-log notice was dismissed (until the next /reload)

-- ══ First run (4.13): three steps in place of Now's content, until Finish or Skip sets settings.welcomeDone. The
-- window is never opened for it; the sidebar works throughout. A save from before this guide that dismissed the old
-- welcome card (settings.onboarded) counts as done (UI.MigrateSettings).
local Welcome = { STEPS = 3 }
Now.Welcome = Welcome
function Welcome.due()
  local st = ns.DB and ns.DB.settings
  return type(st) == "table" and st.welcomeDone ~= true
end
function Welcome.finish()
  if ns.DB and ns.DB.settings then ns.DB.settings.welcomeDone = true end
  if nowView then nowView.welcomeStep = 1; Now.refresh(nowView) end
end
function Welcome.build(content)
  local f = CreateFrame("Frame", nil, content); f:SetAllPoints(content); f:Hide()
  content.welcome = f
  f.dots = {}
  for i = 1, Welcome.STEPS do
    local d = UI.Glyph(f, "dot", 8, "lineControl")
    d:SetPoint("TOPLEFT", f, "TOPLEFT", S.S3 + (i - 1) * (8 + S.S2), -4)
    f.dots[i] = d
  end
  f.stepText = UI.Text(f, "META", "fgMuted"); f.stepText:SetPoint("TOPLEFT", f, "TOPLEFT", S.S3 + Welcome.STEPS * (8 + S.S2), -1)
  f.title = UI.Text(f, "TITLE", "fg"); f.title:SetPoint("TOPLEFT", f, "TOPLEFT", S.S3, -32)
  f.body = UI.Text(f, "BODY", "fgSubtle", { wrap = true }); f.body:SetPoint("TOPLEFT", f, "TOPLEFT", S.S3, -56); f.body:SetWidth(520)
  f.block = CreateFrame("Frame", nil, f)
  -- step 1: three status rows
  f.status = {}
  for i = 1, 3 do
    local r = CreateFrame("Frame", nil, f.block); r:SetHeight(H.ROW)
    r:SetPoint("TOPLEFT", f.block, "TOPLEFT", 0, -(i - 1) * H.ROW); r:SetPoint("TOPRIGHT", f.block, "TOPRIGHT", 0, -(i - 1) * H.ROW)
    r.dot = UI.Glyph(r, "dot", 8, "accent"); r.dot:SetPoint("LEFT", r, "LEFT", S.S3, 0)
    r.text = UI.Text(r, "BODY", "fg"); r.text:SetPoint("LEFT", r, "LEFT", S.S3 + 8 + S.S2, 0)
    r.meta = UI.Text(r, "META", "fgMuted")
    f.status[i] = r
  end
  f.turnOn = UI.KitButton(f.status[2], "Turn on", "ghost", function()
    if ns.Logging and ns.Logging.enforce then pcall(ns.Logging.enforce, true) end
    if UI.refreshStatus then pcall(UI.refreshStatus) end
    Welcome.draw(content)
  end)
  -- step 2: a preview of the gold line, and the answer
  f.pill = UI.Box(f.block, "sunken", "line"); f.pill:SetHeight(H.CONTROL)
  f.pill:SetPoint("TOPLEFT", f.block, "TOPLEFT", S.S3, 0)
  f.pill.text = UI.Text(f.pill, "BODY_STRONG", "fg"); f.pill.text:SetPoint("LEFT", f.pill, "LEFT", S.S2, 0)
  local function answer(yes)
    if ns.Gold and ns.Gold.pillAnswer then pcall(ns.Gold.pillAnswer, yes) end
    content.welcomeStep = 3; Welcome.draw(content)
  end
  f.noThanks = UI.KitButton(f.block, "No thanks", "ghost", function() answer(false) end, { h = UI.H.BIG_BUTTON })
  f.noThanks:SetPoint("TOPLEFT", f.pill, "BOTTOMLEFT", 0, -S.S5)
  f.showIt = UI.KitButton(f.block, "Show it", "primary", function() answer(true) end, { h = UI.H.BIG_BUTTON })
  f.showIt:SetPoint("LEFT", f.noThanks, "RIGHT", S.S2, 0)
  -- step 3: three things to get started
  f.rows = {}
  local THINGS = {
    { UI.KIND_ICON.run, "Run a dungeon", "Your time, bosses and loot show under Dungeons, against your best." },
    { UI.KIND_ICON.session, "Play as usual", "Home shows this session at a glance." },
    { UI.KIND_ICON.quest, "Open this window any time", "Type /eb or click the minimap button." },
  }
  for i, t in ipairs(THINGS) do
    local r = UI.Row2(f.block)
    r:SetPoint("TOPLEFT", f.block, "TOPLEFT", 0, -(i - 1) * H.ROW2); r:SetPoint("TOPRIGHT", f.block, "TOPRIGHT", 0, -(i - 1) * H.ROW2)
    r:Set({ icon = t[1], title = t[2], meta = t[3] })
    f.rows[i] = r
  end
  -- the footer, right-aligned to BOX_R at CONTENT_BOTTOM - 28: Back, Skip, Next (Finish on the last step)
  f.next = UI.KitButton(f, "Next", "primary", function()
    if content.welcomeStep >= Welcome.STEPS then Welcome.finish() else content.welcomeStep = content.welcomeStep + 1; Welcome.draw(content) end
  end, { h = UI.H.BIG_BUTTON })
  f.next:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
  f.skip = UI.KitButton(f, "Skip", "link", function() Welcome.finish() end, { role = "BODY" })
  f.back = UI.KitButton(f, "Back", "ghost", function() content.welcomeStep = math.max(1, content.welcomeStep - 1); Welcome.draw(content) end, { h = UI.H.BIG_BUTTON })
  content.welcomeStep = 1
end
local STEP_TEXT = {
  { "Welcome to everbuff.gg", "The addon captures your pulls, loot, deaths and leveling while you play, so you can see how you are doing here and watch it back on everbuff.gg. You can change everything later in Settings." },
  { "Show your gold on screen?", "A small line near the flag shows your gold and how much you made this session. It never covers your game." },
  { "Three things to get started", "" },
}
function Welcome.draw(content)
  local f = content.welcome
  local step = math.max(1, math.min(Welcome.STEPS, content.welcomeStep or 1))
  content.welcomeStep = step
  for i, d in ipairs(f.dots) do d:SetColor(i == step and "accent" or (i < step and "fgSubtle" or "lineControl")) end
  f.stepText:SetText(("Step %d of %d"):format(step, Welcome.STEPS))
  f.title:SetText(STEP_TEXT[step][1]); f.body:SetText(STEP_TEXT[step][2])
  local bodyH = STEP_TEXT[step][2] ~= "" and (tonumber(f.body:GetStringHeight()) or UI.LINE_H.BODY) or 0
  f.block:ClearAllPoints()
  f.block:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -(56 + bodyH + S.S5)); f.block:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -(56 + bodyH + S.S5)); f.block:SetHeight(3 * H.ROW2)
  for _, r in ipairs(f.status) do if step == 1 then r:Show() else r:Hide() end end
  for _, x in ipairs({ f.pill, f.noThanks, f.showIt }) do if step == 2 then x:Show() else x:Hide() end end
  for _, r in ipairs(f.rows) do if step == 3 then r:Show() else r:Hide() end end
  if step == 1 then
    local combatOn = true
    if ns.Logging and ns.Logging.state then local _, c = ns.Logging.state(); combatOn = c and true or false end
    local st = UI.StatusState and UI.StatusState() or {}
    local rows = {
      { st.sess and "accent" or "warn", st.sess and "CAPTURING" or "Capture starts when you enter the world" },
      { combatOn and "accent" or "warn", combatOn and "Combat log: on" or "Combat log: off" },
      { st.lastAck and "accent" or "fgFaint", st.lastAck and "Desktop app: seen" or "Desktop app: not seen yet", (not st.lastAck) and "Install it from everbuff.gg to record video" or nil },
    }
    for i, r in ipairs(f.status) do
      r.dot:SetColor(rows[i][1]); r.text:SetText(rows[i][2])
      local tw = UI.TextWidth("BODY", rows[i][2])
      r.text:SetWidth(tw)
      r.meta:ClearAllPoints(); r.meta:SetPoint("LEFT", r, "LEFT", S.S3 + 8 + S.S2 + tw + S.S2, 0); r.meta:SetText(rows[i][3] or "")
    end
    f.turnOn:ClearAllPoints(); f.turnOn:SetPoint("LEFT", f.status[2], "LEFT", S.S3 + 8 + S.S2 + UI.TextWidth("BODY", rows[2][2]) + S.S3, 0)
    if combatOn then f.turnOn:Hide() else f.turnOn:Show() end
  elseif step == 2 then
    local cb = ns.DB and ns.char and ns.char() or {}
    local bal = num(type(cb.gold) == "table" and cb.gold.balance)
    local okN, net = false, nil
    if ns.Gold and ns.Gold.metric then okN, net = pcall(ns.Gold.metric, "net", "char", "session") end
    local txt = UI.money(bal) .. ((okN and type(net) == "number") and ("  \194\183  " .. UI.money(net, true) .. " this session") or "")
    f.pill.text:SetText(txt)
    f.pill:SetWidth(UI.TextWidth("BODY_STRONG", txt) + 2 * S.S2)
  end
  -- the footer: Next is hidden on step 2 (its own two buttons answer it), Back from step 2 on
  f.next:SetLabel(step == Welcome.STEPS and "Finish" or "Next")
  if step ~= 2 then f.next:Show() else f.next:Hide() end
  f.skip:ClearAllPoints()
  if step ~= 2 then f.skip:SetPoint("RIGHT", f.next, "LEFT", -S.S3, 0)
  else f.skip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, (UI.H.BIG_BUTTON - UI.LINE_H.BODY) / 2) end
  f.back:ClearAllPoints(); f.back:SetPoint("RIGHT", f.skip, "LEFT", -S.S3, 0)
  if step > 1 then f.back:Show() else f.back:Hide() end
end

function Now.build(content)
  nowView = content
  local sf, child = UI.ScrollChild(content, { slim = true, top = 0, left = 0, right = 0, bottom = 0 })
  content.sf, content.child = sf, child
  local col = CreateFrame("Frame", nil, child)
  col:SetPoint("TOPLEFT", child, "TOPLEFT", 0, 0); col:SetSize(1, 1)
  content.col = col
  content.notice = UI.Notice(col, { tone = "warn", text = "Combat log is off, so pulls, deaths and replays are not recorded.",
    button = { "Turn on", function()
      if ns.Logging and ns.Logging.enforce then pcall(ns.Logging.enforce, true) end
      if UI.refreshStatus then pcall(UI.refreshStatus) end
      if nowView then Now.refresh(nowView) end
    end }, primary = true, onDismiss = function() noticeOff = true; if nowView then Now.refresh(nowView) end end })
  content.notice:Hide()
  local hero = UI.Hero(col, { image = true })
  content.hero = hero
  UI.SetTip(hero, function(tip) if content.heroTip then content.heroTip(tip) end end)
  content.sesHead = UI.Section(col, "This session")
  content.cards = UI.StatRow(col, 4, {
    { onClick = function() UI.Open("Home", "sessions") end },
    { onClick = function() UI.Open("Character", "leveling") end },
    { onClick = function() if ns.Gold and ns.Gold.open then ns.Gold.open("session") else UI.Open("Loot", "gold") end end },
    { onClick = function() if Now.deathsOpen() then UI.Open("Home", "deaths") end end },
  })
  -- (at the level cap the cards are a list of up to 4, each only when it has a value: one row per count)
  content.maxRows = {}
  content.maxRow = function(n)
    local row = content.maxRows[n]
    if not row then
      local opts = {}
      for i = 1, n do opts[i] = { onClick = function(card) if card.ebClick then card.ebClick() end end } end
      row = UI.StatRow(col, n, opts)
      content.maxRows[n] = row
    end
    for k, r in pairs(content.maxRows) do if k == n then r:Show() else r:Hide() end end
    return row
  end
  content.nextHead = UI.Section(col, "Next")
  content.nextRows = {}
  content.lookHead = UI.Section(col, "Worth a look")
  content.lookRows = {}
  local function linkRow(fn)
    local f = CreateFrame("Frame", nil, col); f:SetHeight(H.DAY_ROW)
    f.link = UI.KitButton(f, "", "link", fn, { role = "BODY" })
    f.link:SetPoint("TOPLEFT", f, "TOPLEFT", S.S3, -4)
    return f
  end
  -- (the rest of the deaths: their list while Deaths has a page, else Sessions, which counts them per session)
  content.moreDeaths = linkRow(function() if Now.deathsOpen() then UI.Open("Home", "deaths") else UI.Open("Home", "sessions") end end)
  Welcome.build(content)
  content:HookScript("OnSizeChanged", function() if nowView then pcall(Now.place, nowView) end end)
  Now.refresh(content)
end

local function row2(content, pool, i)
  local r = pool[i]
  if not r then r = UI.Row2(content.col); pool[i] = r end
  return r
end

-- lay the blocks out top to bottom in the main column (the pane's top is CONTENT_TOP; the page scrolls as one)
function Now.place(content)
  local w = G.mainW(G.winW())
  local col = content.col
  col:SetWidth(w)
  local y = 0
  local function put(f, h)
    f:ClearAllPoints(); f:SetPoint("TOPLEFT", col, "TOPLEFT", 0, -y); f:SetWidth(w)
    if h then f:SetHeight(h) end
  end
  if content.notice:IsShown() then put(content.notice, H.NOTICE); y = y + H.NOTICE + S.S3 end
  -- (a block with nothing to say is not there, heading and all: no sentence takes its place, 0.3)
  put(content.hero, H.HERO); y = y + H.HERO + (content.sesHead:IsShown() and S.S5 or S.S3)
  if content.sesHead:IsShown() then put(content.sesHead, H.SECTION); y = y + H.SECTION end
  local cardRow = content.cardRow
  if cardRow and cardRow:IsShown() then put(cardRow, H.STAT); pcall(cardRow.layout); y = y + H.STAT + S.S5 end
  if content.nextHead:IsShown() then
    put(content.nextHead, H.SECTION); y = y + H.SECTION
    for _, r in ipairs(content.nextRows) do if r:IsShown() then put(r, H.ROW2); y = y + H.ROW2 end end
    y = y + S.S5
  end
  if content.lookHead:IsShown() then
    put(content.lookHead, H.SECTION); y = y + H.SECTION
    for _, r in ipairs(content.lookRows) do if r:IsShown() then put(r, H.ROW2); y = y + H.ROW2 end end
    if content.moreDeaths:IsShown() then put(content.moreDeaths, H.DAY_ROW); y = y + H.DAY_ROW end
  end
  y = y + S.S4
  col:SetHeight(y)
  pcall(content.hero.layout)
  content.sf:SetContentHeight(y)
  content.contentH = y
end

function Now.refresh(content)
  if not (content and content.hero) then return end
  -- the first-run guide stands in for the page until it is finished or skipped
  if Welcome.due() then
    content.sf:Hide(); if content.sf.thumb then content.sf.thumb:Hide() end
    content.welcome:Show(); Welcome.draw(content)
    return
  end
  if content.welcome:IsShown() then content.welcome:Hide(); content.sf:Show(); if content.sf.UpdateThumb then content.sf.UpdateThumb() end end
  content.sf:Show()
  local now = nowT()
  local db = (ns.DB and ns.char()) or {}
  local ses = curSession()
  local parts = sessionParts(ses)
  local start = sessionStart(ses)
  local w = G.mainW(G.winW())

  -- the combat-log notice (Now has no other primary, so its button is the primary)
  local combatOn = true
  if ns.Logging and ns.Logging.state then local _, c = ns.Logging.state(); combatOn = c and true or false end
  if not combatOn and not noticeOff then content.notice:Show() else content.notice:Hide() end

  -- hero: who, when the next level comes, the XP bar with the rested part
  local hero = content.hero
  local lvl = plain(call(UnitLevel, "player")) or 0
  local name = call(UnitName, "player")
  local race = call(UnitRace, "player")
  local classN, classFile = call(UnitClass, "player")
  local zone = call(GetRealZoneText) or call(GetZoneText)
  local maxLvl = plain(call(GetMaxPlayerLevel)) or 60
  local who = ("Level %d"):format(lvl)
  if type(race) == "string" and race ~= "" then who = who .. " " .. race end
  if type(classN) == "string" and classN ~= "" then who = who .. " " .. classN end
  if type(zone) == "string" and zone ~= "" then who = who .. " \194\183 " .. zone end
  -- (the whole name, "Iron Hart", then who that is; with half a name known the title is the class line alone)
  name = ns.fullName and ns.fullName() or nil
  content.fullName = name
  if name then hero:SetTitle(name, { UI.ClassColor(classFile) }); hero:SetTitleMeta(who)
  else hero:SetTitle(who); hero:SetTitleMeta(nil) end
  if hero.image and type(SetPortraitTexture) == "function" then pcall(SetPortraitTexture, hero.image, "player") end
  local cur, mx = readXP()
  if not cur then local x = type(db.xp) == "table" and db.xp or {}; cur, mx = num(x.cur), num(x.max) end
  local rested = plain(call(GetXPExhaustion)) or 0
  local pace = Pace.compute(now)
  content.pace = pace
  local atMax = lvl >= maxLvl
  local remaining = (not atMax) and Pace.remaining(cur, mx, pace.rate) or nil
  content.remaining = remaining
  local db0 = type(db.gold) == "table" and db.gold or {}
  local bal = num(db0.balance)
  local allChars
  if ns.Gold and ns.Gold.roster then
    local ok, ro = pcall(ns.Gold.roster, "all")
    if ok and type(ro) == "table" and num(ro.count) > 1 then allChars = num(ro.total) end
  end
  local sg = Now.sessionGold()
  content.sessionGold = sg
  content.heroIsBalance = false
  if atMax then
    -- the level cap: the hero is the session's gold once any moved, else the balance (Leveling owns the level)
    hero:SetBar(nil); hero:SetMeta2(nil)
    if sg and sg.moved then
      hero:SetHero(UI.money(sg.net, true) .. " this session")
      hero:SetMeta(sg.perHour and (UI.money(sg.perHour, true) .. " per hour") or "", nil)
    else
      content.heroIsBalance = true
      hero:SetHero(UI.money(bal))
      hero:SetMeta(allChars and ("all characters " .. UI.money(allChars)) or "", nil)
    end
  else
    hero:SetHero(remaining and (UI.fmtDur(remaining, { minutes = true }) .. " to level " .. (lvl + 1)) or ("Level " .. lvl))
    local pct = mx > 0 and math.floor(cur / mx * 100) or 0
    local left = ("XP %s / %s \194\183 %d%%"):format(UI.fmtNum(cur), UI.fmtNum(mx), pct)
    if rested > 0 then left = left .. " \194\183 rested " .. UI.fmtNum(rested) end
    hero:SetMeta(left, pace.rate and ("at " .. UI.fmtNum(pace.rate) .. " XP per hour") or "Pace shows after 10 minutes of play")
    hero:SetBar(mx > 0 and cur / mx or 0, (mx > 0 and rested > 0) and math.min(1, (cur + rested) / mx) or nil)
  end
  pcall(hero.layout)
  content.heroTip = function(tip)
    tip:AddLine(type(name) == "string" and name or "Your character", 1, 1, 1)
    if atMax then
      if sg and sg.moved then
        tip:AddLine("What your gold did this session: earned less spent. Per hour shows after 30 minutes of play.", 0.78, 0.79, 0.80, true)
        tip:AddDoubleLine("Earned", ns.fmtMoney(sg.gained, { icons = true }), C.fgMuted[1], C.fgMuted[2], C.fgMuted[3], 1, 1, 1)
        tip:AddDoubleLine("Spent", ns.fmtMoney(sg.spent, { icons = true }), C.fgMuted[1], C.fgMuted[2], C.fgMuted[3], 1, 1, 1)
      else tip:AddLine("Your gold. No gold has moved this session.", 0.78, 0.79, 0.80, true) end
      return
    end
    tip:AddLine("At your XP per hour over the last 30 minutes of active play. It already includes the rested bonus you earned in that time.", 0.78, 0.79, 0.80, true)
    local pl = type(db.played) == "table" and db.played or {}
    if num(pl.total) > 0 then tip:AddDoubleLine("Played in all", UI.fmtDur(pl.total, { minutes = true }), C.fgMuted[1], C.fgMuted[2], C.fgMuted[3], 1, 1, 1) end
    if num(pl.level) > 0 then tip:AddDoubleLine("At this level", UI.fmtDur(pl.level, { minutes = true }), C.fgMuted[1], C.fgMuted[2], C.fgMuted[3], 1, 1, 1) end
    local k = P.kill
    if k and not atMax and mx > cur then
      tip:AddLine(("About %s more %s kills"):format(UI.fmtNum(math.ceil((mx - cur) / k.xp)), k.name), 0.78, 0.79, 0.80, true)
    end
  end

  -- (played is the time logged in: the lengths of the session's records added up, never the span from the first
  -- login to now, which would count the time logged out between two logins as played)
  local elapsed = 0
  local sdeaths = 0
  for _, s in ipairs(parts) do sdeaths = sdeaths + num(s.deaths); elapsed = elapsed + UI.sessionSecs(s, now) end
  if not start then elapsed = 0 end
  local playedTip = #parts > 1 and ("Time logged in this session, its %d logins added up. Time logged out between them is not counted. Opens your sessions."):format(#parts) or "How long this session has run. Opens your sessions."
  local deathsOpen = Now.deathsOpen()
  content.deathsOpen = deathsOpen
  if atMax then
    -- THE CARDS at the level cap (1.1): BALANCE, PLAYED, LAST RUN, SAVED TO EVERBUFF.GG, DEATHS; each only when it
    -- has a value, at most 4 in this order. No XP per hour, no kills, no count of 0.
    content.sesHead:Hide(); content.cards:Hide()
    local defs = {}
    -- (the META room of one of 4 cards, the most the row can hold: a line then reads the same at every count)
    local metaW = math.floor((w - 3 * S.S3) / 4) - 2 * S.S3 - S.S2
    if not content.heroIsBalance then
      -- (a total too long for the card says "all" for "all characters": never cut mid-amount)
      local allText = allChars and ("all characters " .. UI.money(allChars)) or ""
      if allChars and UI.TextWidth("META", allText) > metaW then allText = "all " .. UI.money(allChars) end
      defs[#defs + 1] = { key = "balance", label = "Balance", value = UI.money(bal), meta = allText,
        tip = { title = "Balance", text = "Your gold on this character. Opens Loot > Gold." },
        click = function() if ns.Gold and ns.Gold.open then ns.Gold.open("session") else UI.Open("Loot", "gold") end end }
    end
    if start then
      defs[#defs + 1] = { key = "played", label = "Played", value = (elapsed < 30 and UI.fmtDur(elapsed) or UI.fmtPlayed(elapsed)), meta = "",
        tip = { title = "Played", text = playedTip }, click = function() UI.Open("Home", "sessions") end }
    end
    local lr = Now.lastRun(now, metaW)
    if lr then
      defs[#defs + 1] = { key = "run", label = "Last run", value = lr.name, meta = lr.meta, tip = { title = "Last run", text = "Your newest stored dungeon run. Opens its page." },
        click = function() UI.Open("Dungeons", "runs"); if ns.Dungeons and ns.Dungeons.openRun then pcall(ns.Dungeons.openRun, lr.rec) end end }
    end
    local sync = ns.SyncState and ns.SyncState() or {}
    if sync.lastAck then
      -- (the count is the fact; the time is when the addon saw the confirmation, and says so: ns.AckWords)
      local n, confirmed, tipText = ns.AckWords(sync, now)
      -- (a card too narrow for "confirmed Sat 21 Nov 11:45" drops the weekday: never cut mid-date)
      if UI.TextWidth("META", confirmed) > metaW then confirmed = confirmed:gsub("^confirmed %a+ ", "confirmed ") end
      defs[#defs + 1] = { key = "saved", label = "Saved to everbuff.gg", value = n or "Confirmed",
        meta = n and confirmed or confirmed:gsub("^confirmed ", ""),
        tip = { title = "Saved to everbuff.gg", text = tipText } }
    else
      defs[#defs + 1] = { key = "saved", label = "Saved to everbuff.gg", value = "Not seen yet", meta = "", muted = true,
        tip = { title = "Not seen yet", text = "Install the desktop app from everbuff.gg to keep your history and watch your recordings." } }
    end
    if sdeaths > 0 then
      defs[#defs + 1] = { key = "deaths", label = "Deaths", value = UI.fmtNum(sdeaths), meta = "",
        tip = { title = "Deaths this session", text = deathsOpen and "Opens every death." or nil }, click = deathsOpen and function() UI.Open("Home", "deaths") end or nil }
    end
    while #defs > 4 do table.remove(defs) end
    local row = content.maxRow(#defs)
    content.cardRow, content.cardDefs = row, defs
    for i, d in ipairs(defs) do
      local card = row.cards[i]
      card.ebKey = d.key
      card:Set(d.label, d.value, d.meta, d.muted and "fgMuted" or nil)
      card.ebClick = d.click
      if card.SetClickable then card:SetClickable(d.click ~= nil) end
      UI.SetTip(card, d.tip)
    end
  else
  for _, r in pairs(content.maxRows) do r:Hide() end
  content.cardRow, content.cardDefs = content.cards, nil
  content.sesHead:Show(); content.cards:Show()
  -- THIS SESSION: played, XP per hour, gold, deaths
  content.sesHead:SetMeta(nil)   -- (the PLAYED card says when the session started: no second "since")
  local cards = content.cards.cards
  cards[1]:Set("Played", start and (elapsed < 30 and UI.fmtDur(elapsed) or UI.fmtPlayed(elapsed)) or "Not known yet", start and (UI.fmtClock(start) .. " to now") or "")
  UI.SetTip(cards[1], { title = "Played", text = playedTip })
  if pace.rate then
    cards[2]:Set("XP per hour", UI.fmtNum(pace.rate), ("last %dm of play"):format(pace.used))
    UI.SetTip(cards[2], { title = "XP per hour", text = ("+%s XP this session"):format(UI.fmtNum(pace.xp)) })
  else
    cards[2]:Set("XP per hour", "Not known yet", "after 10m of play", "fgMuted")
    UI.SetTip(cards[2], { title = "XP per hour", text = "Shows after 10 minutes of play" })
  end
  -- (the rate only from Now.RATE_FLOOR of play on; before it the card has no second line)
  cards[3]:Set("Gold", sg and UI.money(sg.net, true) or "Not known yet", (sg and sg.perHour) and (UI.money(sg.perHour, true) .. " per hour") or "", (not sg) and "fgMuted" or nil)
  local goldPairs = { { "Balance", ns.fmtMoney(bal, { icons = true }) } }
  if allChars then goldPairs[2] = { "All characters", ns.fmtMoney(allChars, { icons = true }) } end
  UI.SetTip(cards[3], { title = "Gold this session", text = "What you made this session. Per hour shows after 30 minutes of play.", pairs = goldPairs })
  -- (a true stored count, 0 included; no kills or items line under it)
  cards[4]:Set("Deaths", UI.fmtNum(sdeaths), "")
  if cards[4].SetClickable then cards[4]:SetClickable(deathsOpen) end
  UI.SetTip(cards[4], { title = "Deaths this session", text = deathsOpen and "Opens every death." or nil })
  end

  -- NEXT
  local nx = Now.nextItems(w - (S.S3 + 24 + S.S2) - S.S3, now)
  content.nextList = nx
  for i, it in ipairs(nx) do row2(content, content.nextRows, i):Set(it):Show() end
  for i = #nx + 1, #content.nextRows do content.nextRows[i]:Hide() end
  -- (nothing needs attention: no section and no sentence)
  if #nx == 0 then content.nextHead:Hide() else content.nextHead:Show() end

  -- WORTH A LOOK: at the level cap the session's largest gold lines; while leveling what happened this session in
  -- rank order. With nothing to list the section is not there (no "so far" row, no sentence).
  local look, extra = {}, {}
  if atMax then look = Now.goldLines()
  else look, extra = Now.lookItems(now) end
  local cap = G.isWide(G.winW()) and Now.CAP_WIDE or Now.CAP_COMPACT
  local shown = math.min(#look, cap)
  content.lookList = look
  for i = 1, shown do row2(content, content.lookRows, i):Set(look[i]):Show() end
  for i = shown + 1, #content.lookRows do content.lookRows[i]:Hide() end
  if #look == 0 then content.lookHead:Hide() else content.lookHead:Show() end
  if #look > 0 and extra.deaths and extra.deaths > 0 then
    content.moreDeaths.link:SetLabel(UI.plural(extra.deaths, "more death") .. " \226\128\186"); content.moreDeaths:Show()
  else content.moreDeaths:Hide() end

  Now.place(content)
end
local build, refresh = Now.build, Now.refresh


-- ── HOME / Sessions: what each play session gave (docs/UX_PRAGMATIC.md 1.2) ───────────────────────────────────
-- One line for the week, then one table under day rows. A row is a session, not a login: logins of the character
-- less than 5 minutes apart are one row (Gold.joined, the one definition of "this session"). Every cell is a stored
-- counter of the session records; a counter a record does not hold is a blank cell, a stored zero reads "0".
local sessionsRebuild, sessionsView
local function sessionRows()
  local out = {}
  for id, sess in pairs((ns.DB and ns.DB.sessions) or {}) do if ns.isMySession(sess) then out[#out + 1] = sess end end   -- the logged-in character's (#23)
  -- the live session first, then newest first (ids break ties within the same second)
  table.sort(out, function(a, b)
    local la, lb = a.endedEpoch == nil, b.endedEpoch == nil
    if la ~= lb then return la end
    if (a.startedEpoch or 0) ~= (b.startedEpoch or 0) then return (a.startedEpoch or 0) > (b.startedEpoch or 0) end
    return tostring(a.id) > tostring(b.id)
  end)
  return out
end

local Sess = { EMPTY_S = 5 * 60, RUNS_FROM = "0.9.50" }
ns.Sessions = Sess
-- "0.9.51" against "0.9.50": true when version `v` is `min` or later; false for a version that cannot be read
function Sess.verAtLeast(v, min)
  if type(v) ~= "string" or type(min) ~= "string" then return false end
  local a, b = {}, {}
  for n in v:gmatch("%d+") do a[#a + 1] = tonumber(n) end
  for n in min:gmatch("%d+") do b[#b + 1] = tonumber(n) end
  if #a == 0 then return false end
  for i = 1, math.max(#a, #b) do
    local x, y = a[i] or 0, b[i] or 0
    if x ~= y then return x > y end
  end
  return true
end
local function statN(v) if type(v) == "number" and v == v then return v end return nil end
-- The rows of the list, newest first, and how many were left out. A row: { parts (its session records, newest
-- first), sess (the newest), id, startedEpoch (of the first login), endedEpoch (nil while it runs or when not
-- stored), live, logins, secs (the lengths of its logins added up: the time logged out between two logins is not
-- played; nil when a login has no stored end), level0, level, atCap (it started at the level cap: no XP to earn),
-- xp, net, gained, spent, deaths, items, runs }. xp, net, deaths and runs are nil when no record of the row stores
-- the counter.
-- runs: the runs of the run store that began in the session (RunsLegacy.inSession, the Dungeons list's own rows). A
-- count of 0 is said only for a session the run store covers (addon 0.9.50 on); before that 0 means not recorded.
-- The session's old `dungeons` counter is never read: it counted door entries (22 for a night with 2 runs).
-- Left out: rows under 5 minutes with nothing in them (no XP, gold, death or loot).
function Sess.rows(now)
  now = now or nowT()
  local cur = curSession()
  local all = sessionRows()
  table.sort(all, function(a, b)
    if num(a.startedEpoch) ~= num(b.startedEpoch) then return num(a.startedEpoch) > num(b.startedEpoch) end
    return tostring(a.id) > tostring(b.id)
  end)
  local cap = plain(call(GetMaxPlayerLevel)) or 60
  local used, rows, hidden = {}, {}, 0
  for _, s in ipairs(all) do
    if not used[s] then
      local parts = {}
      for _, p in ipairs(sessionParts(s)) do if not used[p] then used[p] = true; parts[#parts + 1] = p else break end end
      if #parts == 0 then used[s] = true; parts[1] = s end
      local first = parts[#parts]
      local r = { parts = parts, sess = s, id = s.id, startedEpoch = statN(first.startedEpoch), endedEpoch = statN(s.endedEpoch),
        live = (s == cur), logins = #parts, secs = 0, items = 0 }
      local runsKnown, runs = true, 0
      for _, p in ipairs(parts) do
        local a, z = statN(p.startedEpoch), statN(p.endedEpoch) or (p == cur and now or nil)
        if r.secs and a and z then r.secs = r.secs + math.max(0, z - a) else r.secs = nil end
        if statN(p.xp) then r.xp = (r.xp or 0) + p.xp end
        if statN(p.gained) or statN(p.spent) then
          r.gained, r.spent = (r.gained or 0) + num(p.gained), (r.spent or 0) + num(p.spent)
        end
        if statN(p.deaths) then r.deaths = (r.deaths or 0) + p.deaths end
        r.items = r.items + num(p.items)
        runs = runs + (ns.RunsLegacy and ns.RunsLegacy.inSession(p) or 0)
        -- (a login with no stored end has no known span: its runs are not known)
        if not Sess.verAtLeast(p.addonVersion, Sess.RUNS_FROM) or not z then runsKnown = false end
      end
      if r.gained then r.net = r.gained - r.spent end
      if runs > 0 or runsKnown then r.runs = runs end
      local l1 = statN(s.level)
      local l0 = statN(first.level0) or statN(first.level)
      if l0 and l0 > 0 then r.level0, r.level = l0, (l1 and l1 > l0) and l1 or l0 end
      r.atCap = r.level0 ~= nil and r.level0 >= cap
      local empty = not r.live and r.secs ~= nil and r.secs < Sess.EMPTY_S and num(r.xp) == 0 and num(r.gained) == 0 and num(r.spent) == 0
        and num(r.deaths) == 0 and r.items == 0
      if empty then hidden = hidden + 1 else rows[#rows + 1] = r end
    end
  end
  return rows, hidden
end
-- The list has gaps when the character's own totals are more than every stored session adds up to: both are bumped
-- by the same change, so the difference is sessions whose record is gone (the desktop app removes a session from
-- the save once it has saved it). Never a guess: with equal sums the list says nothing.
function Sess.gaps()
  if not (ns.DB and ns.charGuid and ns.charGuid() and ns.char) then return false end
  local c = ns.char()
  if type(c) ~= "table" then return false end
  local g, x = 0, 0
  for _, s in ipairs(sessionRows()) do g, x = g + num(s.gained), x + num(s.xp) end
  return num(type(c.gold) == "table" and c.gold.gained) > g or num(type(c.xp) == "table" and c.xp.gained) > x
end
-- The answer line: the runs of the run store that began in the week, and the week's net gold from the day rows
-- (the Week of Loot > Gold, one function). When the gold history starts inside the week the line names the real
-- start. nil while the character has no gold day row in the week.
-- The gold stands right above the Gold column, so it is said only in a form the rows under it bear out:
--   gold = "net"   the stored sessions that began in the range add up to it, to the copper
--   gold = "more"  they do not, and the stored data says why: no stored session reaches into the range from before
--                  it and every one in it holds its gold counter, so the rest moved in sessions that are no longer
--                  in the save (the desktop app removes a session once it has saved it). The line says so itself.
--   gold = nil     the difference cannot be explained from the save: the gold is left out of the line.
-- listed is what the stored sessions of the range add up to.
function Sess.answer()
  if not (ns.Gold and ns.Gold.scope and ns.DB and ns.charGuid and ns.charGuid()) then return nil end
  local ok, sc = pcall(ns.Gold.scope, "week", "char")
  if not (ok and type(sc) == "table" and sc.period and sc.period.from and sc.to and #(sc.period.days or {}) > 0) then return nil end
  local from = sc.since or sc.period.from
  local out = { since = sc.since, from = from, to = sc.to, net = num(sc.ledger.gained) - num(sc.ledger.spent), runs = 0 }
  local c = ns.char()
  local function count(list)
    for _, r in ipairs(type(list) == "table" and list or {}) do
      if type(r) == "table" and num(r.t) >= from and num(r.t) < sc.to then out.runs = out.runs + 1 end
    end
  end
  count(c.dungeonRuns); count(c.dungeonLegacy)
  if type(c.dungeonRun) == "table" then count({ c.dungeonRun }) end
  -- the stored sessions of the range (2 s of slack at its start, as the gold scope has it)
  local cur = curSession()
  local listed, explained = 0, true
  for _, s in ipairs(sessionRows()) do
    local a, z = statN(s.startedEpoch), statN(s.endedEpoch)
    if not a then explained = false
    elseif a >= from - 2 and a < sc.to then
      if statN(s.gained) or statN(s.spent) then listed = listed + num(s.gained) - num(s.spent) else explained = false end
    elseif a < from - 2 and (s == cur or (z or a) > from) then explained = false   -- it reaches into the range
    end
  end
  out.listed = listed
  if listed == out.net then out.gold = "net" elseif explained then out.gold = "more" end
  return out
end
Sess.NOT_LISTED = "including sessions not listed"
-- The text of the answer line, one segment (nil: no line): the range, the runs, then the gold last, so nothing
-- follows a coin.
function Sess.answerSeg(a)
  if type(a) ~= "table" then return nil end
  local parts = {}
  if num(a.runs) > 0 then parts[#parts + 1] = ("**%d** %s"):format(a.runs, a.runs == 1 and "run" or "runs") end
  local tip
  if a.gold == "net" then parts[#parts + 1] = ("net **%s**"):format(UI.money(a.net, true))
  elseif a.gold == "more" then
    parts[#parts + 1] = ("gold %s **%s**"):format(Sess.NOT_LISTED, UI.money(a.net, true))
    tip = { title = "Gold in this time", text = "Earned less spent, from this character's daily gold totals. The desktop app removes a session from the game's save once it has saved it, so the list below holds fewer sessions than were played.",
      pairs = { { "All gold changes", UI.money(a.net, true) }, { "Sessions listed below", UI.money(num(a.listed), true) } } }
  end
  if #parts == 0 then return nil end
  local head = a.since and ("Since " .. UI.fmtStamp(a.since)) or "This week"
  return { text = head .. ": " .. table.concat(parts, " \194\183 "), tip = tip }
end
-- what a click on a row opens: the session's gold journal (Loot > Gold), when the row is the running session or
-- one stored login with a journal. nil: the row opens nothing.
function Sess.goldScope(r)
  if type(r) ~= "table" or type(r.sess) ~= "table" then return nil end
  if r.live then return "session" end
  if r.logins == 1 and type(r.sess.goldLog) == "table" and #r.sess.goldLog > 0 and r.sess.id then return r.sess.id end
  return nil
end

local function withDays(rows)
  local out, i = {}, 1
  while i <= #rows do
    local day = UI.fmtDay(rows[i].startedEpoch or 0)
    -- (the day alone: a total would claim the sessions of a day whose other records are gone)
    out[#out + 1] = { ebSection = day }
    while i <= #rows and UI.fmtDay(rows[i].startedEpoch or 0) == day do out[#out + 1] = rows[i]; i = i + 1 end
  end
  return out
end
local function fmtLength(secs)
  if not secs then return "" end
  if secs < 30 then return UI.fmtDur(secs) end
  return UI.fmtPlayed(secs)
end

local function buildSessions(content)
  local G, H = UI.G, UI.H
  sessionsView = content
  local sf, child = UI.ScrollChild(content, { slim = true, top = 0, left = 0, right = 0, bottom = 0 })
  local col = CreateFrame("Frame", nil, child); col:SetPoint("TOPLEFT", child, "TOPLEFT", 0, 0); col:SetSize(1, 1)
  content.sf, content.col = sf, col
  content.summary = UI.Summary(col)
  content.section = UI.Section(col, "Sessions")
  -- When (a LIVE badge after the running one) · Length · Level · XP · Gold · Deaths · Runs. A column is left out
  -- while it has nothing to say (0.3): one level on every row, every row at the level cap, fewer than a third of
  -- the rows with a value.
  local spec = {
    { key = "date", label = "When", flex = 1, min = 96 },
    { key = "len", label = "Length", kind = "num", min = 56, tip = "Time logged in. A session of several logins adds them up." },
    { key = "lvl", label = "Level", kind = "num", min = 48, measure = { "17 to 18" }, tip = "Your level when the session started, and when it ended if you levelled" },
    { key = "xp", label = "XP", kind = "num", min = 64 },
    { key = "gold", label = "Gold", kind = "money", min = 88, tip = "Earned less spent in the session" },
    { key = "deaths", label = "Deaths", kind = "num", min = 48 },
    { key = "dung", label = "Runs", kind = "num", min = 40, tip = "Dungeon runs that began in the session, as Dungeons lists them" },
  }
  local specOf = {}
  for _, c in ipairs(spec) do specOf[c.key] = c end
  local tbl = UI.KitTable(col, spec, {
    onClick = function(_, r)
      local scope = Sess.goldScope(r)
      if scope and ns.Gold and ns.Gold.open then ns.Gold.open(scope, "journal") end
    end,
    tooltip = function(_, r, tip)
      if not (r and r.startedEpoch) then return end
      local from = UI.fmtStamp(r.startedEpoch)
      tip:AddLine(r.endedEpoch and (from .. " to " .. UI.fmtClock(r.endedEpoch)) or from, 1, 1, 1)
      local function line(k, v) tip:AddDoubleLine(k, v, C.fgMuted[1], C.fgMuted[2], C.fgMuted[3], 1, 1, 1) end
      if r.logins > 1 then line("Logins", tostring(r.logins)) end
      if not r.secs then line("Length", "Not recorded") end
      if r.atCap then line("XP", "Max level") elseif r.xp == nil then line("XP", "Not recorded") end
      if r.net == nil then line("Gold", "Not recorded") end
      if r.deaths == nil then line("Deaths", "Not recorded") end
      line("Runs", r.runs and tostring(r.runs) or "Not recorded")
      if Sess.goldScope(r) then tip:AddLine("Click for the gold of this session", C.fgSubtle[1], C.fgSubtle[2], C.fgSubtle[3]) end
    end,
    onLayout = function(t) for i = 1, t.shownN do pcall(content.placeLive, t, t.rows[i]) end end,
    onHeight = function() if content.place then pcall(content.place) end end })
  content.tbl, content.spec = tbl, specOf
  -- the LIVE badge right after the When text (S2), the text shortening first
  function content.placeLive(t, row)
    local cw, fs, b = t.cols and t.cols.date, row.c and row.c.date, row.ebBadge
    if not (cw and fs) then return end
    if b and b:IsShown() and row.item and not row.item.ebSection then
      local room = cw.w - (tonumber(b:GetWidth()) or 0) - S.S2
      local tw = math.max(1, math.min(UI.TextWidth("BODY", fs:GetText() or ""), room))
      fs:SetWidth(tw)
      b:ClearAllPoints(); b:SetPoint("LEFT", row, "LEFT", cw.x + tw + S.S2, 0)
    else
      if b then b:Hide() end
      fs:SetWidth(cw.w)
    end
  end
  function content.place()
    local w = G.mainW(G.winW())
    col:SetWidth(w)
    local y = 0
    local function put(f, h) f:ClearAllPoints(); f:SetPoint("TOPLEFT", col, "TOPLEFT", 0, -y); f:SetWidth(w); if h then f:SetHeight(h) end end
    if content.summary:IsShown() then put(content.summary, H.SUMMARY); pcall(content.summary.layout); y = y + H.SUMMARY + S.S3 end
    if tbl.width ~= math.min(w, G.TABLE_MAX) then tbl.relayout(w) end
    if content.section:IsShown() then put(content.section, H.SECTION); y = y + H.SECTION end
    put(tbl.frame)
    y = y + (tbl.height or 0) + S.S4
    col:SetHeight(y); sf:SetContentHeight(y)
    content.contentH = y
  end
  content:HookScript("OnSizeChanged", function() pcall(content.place) end)
  sessionsRebuild = function()
    local nowS = nowT()
    local rows, hidden = Sess.rows(nowS)
    content.shownSessions, content.hiddenEmpty = rows, hidden
    -- the answer: the week, each part only when it can be derived
    local a = Sess.answer()
    content.answer = a
    local seg = a and #rows > 0 and Sess.answerSeg(a) or nil
    if seg then content.summary:SetSegments({ seg }); content.summary:Show()
    else content.summary:SetSegments({}); content.summary:Hide() end
    -- the header says where the list starts, once (0.2.3), and the one remark when the stored totals prove a gap
    if #rows > 0 then
      local oldest = rows[#rows].startedEpoch
      content.section:SetLabel("Sessions" .. (oldest and (" since " .. UI.fmtSince(oldest)) or ""))
      local okG, gaps = pcall(Sess.gaps)
      content.gaps = okG and gaps or false
      if content.gaps then
        content.section:SetMeta("not every session is kept", { title = "Not every session is kept",
          text = "This character's totals are higher than the listed sessions add up to. The desktop app removes a session from the game's save once it has saved it." })
      else content.section:SetMeta(nil) end
      content.section:Show()
    else content.section:Hide() end
    -- which columns have something to say
    local has = { lvl = 0, xp = 0, gold = 0, deaths = 0, dung = 0 }
    local oneLevel, sameLevel, anyBelowCap = true, nil, false
    for _, r in ipairs(rows) do
      if r.level0 then
        has.lvl = has.lvl + 1
        if r.level ~= r.level0 then oneLevel = false end
        if sameLevel == nil then sameLevel = r.level0 elseif sameLevel ~= r.level0 then oneLevel = false end
      end
      if not r.atCap then anyBelowCap = true; if r.xp ~= nil then has.xp = has.xp + 1 end end
      if r.net ~= nil then has.gold = has.gold + 1 end
      if r.deaths ~= nil then has.deaths = has.deaths + 1 end
      if r.runs ~= nil then has.dung = has.dung + 1 end
    end
    local hide = {}
    for k, n in pairs(has) do hide[k] = n == 0 or n * 3 < #rows end
    if oneLevel then hide.lvl = true end
    if not anyBelowCap then hide.xp = true end
    local changed = false
    for k, h in pairs(hide) do if (specOf[k].hide or false) ~= h then specOf[k].hide = h; changed = true end end
    content.colHidden = hide
    if changed then tbl.relayout(G.mainW(G.winW())) end
    tbl.setRows(withDays(rows), function(row, r)
      local c = row.c
      c.date:SetText(UI.fmtClock(r.startedEpoch or 0))
      if r.live then
        if not row.ebBadge then row.ebBadge = UI.Badge(row, "LIVE"); UI.SetTip(row.ebBadge, { title = "LIVE", text = "The session you are playing now" }) end
        row.ebBadge:Show()
      elseif row.ebBadge then row.ebBadge:Hide() end
      c.len:SetText(fmtLength(r.secs))
      c.lvl:SetText(r.level0 and (r.level > r.level0 and (r.level0 .. " to " .. r.level) or tostring(r.level0)) or "")
      c.xp:SetText((r.atCap or r.xp == nil) and "" or UI.fmtNum(r.xp))
      c.gold:SetText(r.net == nil and "" or (r.net == 0 and "0" or UI.money(r.net, true)))
      c.deaths:SetText(r.deaths == nil and "" or UI.fmtNum(r.deaths))
      c.dung:SetText(r.runs == nil and "" or tostring(r.runs))
      row.ebNoOpen = Sess.goldScope(r) == nil
    end)
    for i = 1, tbl.shownN do pcall(content.placeLive, tbl, tbl.rows[i]) end
    if #rows == 0 then tbl.setState("No session stored yet.") end
    content.place()
  end
  sessionsRebuild()
end
-- HOME is the landing tab (order 0). Now and Sessions live here; Fights is registered into Home by Recording.lua
-- and Deaths by Deaths.lua, each shown only while it has rows (docs/UX_PRAGMATIC.md 0.5).
UI.registerHost(0, "Home", "How this session is going, and every session before it.")
local ticker
UI.registerPane("Home", 1, "Now", build, function()
  if nowView then refresh(nowView) end
  -- light live refresh while the dashboard is the visible pane; cancels itself when it isn't
  if not ticker then
    ticker = C_Timer.NewTicker(3, function()
      if nowView and nowView:IsShown() then refresh(nowView) end
      if sessionsView and sessionsView:IsShown() and sessionsRebuild then sessionsRebuild() end
    end)
  end
end, "How this session is going, and what needs you.")
UI.registerPane("Home", 2, "Sessions", buildSessions, function() if sessionsRebuild then sessionsRebuild() end end,
  "Every play session: how long, what you earned, and how far you got.")

-- ── test exports: headless luajit tests in tests/ read these; no effect in-game ──
ns._test = ns._test or {}
ns._test.sessionRows = sessionRows
ns._test.journeyMoney = fmtMoney
ns._test.journeyRefresh = function() if nowView then refresh(nowView) end return nowView end
