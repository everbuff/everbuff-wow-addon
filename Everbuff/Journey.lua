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

-- ── formatting (the Sessions half below still reads these) ─────────────────────────
local fmtMoney = ns.fmtMoney   -- the one formatter (UI.lua)
-- (the not-yet-redesigned Sessions tab speaks the kit's money dialect: coin icons, the two largest units, 2.5)
local function coin2(c) return ns.fmtMoney(c, { icons = true, units = 2 }) end
local function fmtTime(sec)
  sec = math.floor(tonumber(sec) or 0)
  if sec <= 0 then return "-" end
  local d, h, m = math.floor(sec / 86400), math.floor((sec % 86400) / 3600), math.floor((sec % 3600) / 60)
  if d > 0 then return ("%dd %dh"):format(d, h) end
  if h > 0 then return ("%dh %dm"):format(h, m) end
  return m .. "m"
end
local function commas(n)
  n = tostring(math.floor(tonumber(n) or 0))
  local out = n:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
  return out
end
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

-- the story events of the live session that are the logged-in character's, oldest first
local function sessionEvents(ses)
  local out = {}
  local sid = ses and ses.id
  if not sid then return out end
  for _, e in ipairs((ns.DB and ns.DB.story and ns.DB.story.events) or {}) do
    if type(e) == "table" and e.s == sid and ns.isMine(e) then out[#out + 1] = e end
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
local function qColor(q)
  q = qHex(q)
  return { (tonumber(q:sub(3, 4), 16) or 255) / 255, (tonumber(q:sub(5, 6), 16) or 255) / 255, (tonumber(q:sub(7, 8), 16) or 255) / 255 }
end
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

-- WORTH A LOOK: what happened this session, in rank order, newest first within a rank (4.1)
function Now.lookItems(now)
  now = now or nowT()
  local ses = curSession()
  local start = ses and plain(ses.startedEpoch) or now
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
    out[#out + 1] = { kind = "death", rank = 1, t = num(e.t), icon = UI.KIND_ICON.death,
      title = (type(e.foe) == "string" and e.foe ~= "") and ("Died to " .. e.foe) or "You died",
      meta = table.concat(parts, " \194\183 "), onClick = function() UI.Open("Home", "deaths") end }
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
    local total = (DD and DD.totalOf) and DD.totalOf(v) or num(v.total)
    local down = num(v.bossesDown)
    local bosses = total > 0 and ("%d of %s"):format(down, UI.plural(total, "boss")) or "no boss killed"
    local word, wkey, kind = "", nil, "none"
    if DD and DD.vsBest then word, wkey, kind = DD.vsBest(v) end
    local title, badge, bar
    if v.inProgress then title, badge = ("%s: %s so far"):format(name, bosses), "IN PROGRESS"
    elseif kind == "first" then title = ("%s: first run, %s"):format(name, bosses)
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
  local pal = type(db.playedAtLevel) == "table" and db.playedAtLevel or {}
  for i = #ev, 1, -1 do
    local e = ev[i]
    if e.kind == "LEVELUP" then
      local lvl = tonumber(tostring(e.text or ""):match("(%d+)%s*$"))
      local meta = { UI.fmtClock(e.t) }
      if lvl and pal[lvl - 1] and pal[lvl - 2] then
        local took = num(pal[lvl - 1]) - num(pal[lvl - 2])
        if took > 0 then meta[#meta + 1] = UI.fmtDur(took, { minutes = true }) .. " at level " .. (lvl - 1) end
        if took > 0 and pal[lvl - 3] then
          local before = num(pal[lvl - 2]) - num(pal[lvl - 3])
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
      title = "Best drop: " .. stripLink(best.item), titleColor = qColor(best.q), meta = table.concat(meta, " \194\183 "),
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
        tip = (not match) and { title = l.name, text = "Saved before Everbuff recorded this dungeon on this character." } or nil,
        onClick = match and function() UI.Open("Dungeons", "runs"); if ns.Dungeons and ns.Dungeons.openRun then pcall(ns.Dungeons.openRun, match) end end or nil }
      end
    end
  end
  table.sort(out, function(a, b) if a.rank ~= b.rank then return a.rank < b.rank end return a.t > b.t end)
  return out, extra, ev
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
  { "Welcome to Everbuff", "Everbuff records your pulls, loot, deaths and leveling while you play, so you can see how you are doing here and watch it back on everbuff.gg. You can change everything later in Settings." },
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
      { st.sess and "accent" or "warn", st.sess and "Recording is on" or "Recording starts when you enter the world" },
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
    { onClick = function() UI.Open("Home", "deaths") end },
  })
  content.nextHead = UI.Section(col, "Next")
  content.nextRows = {}
  content.allClear = UI.EmptyLine(col)
  content.lookHead = UI.Section(col, "Worth a look")
  content.lookHead:SetLink("See all activity \226\128\186", function() UI.Open("Home", "activity") end)
  content.lookRows = {}
  content.lookEmpty = UI.EmptyLine(col)
  local function linkRow(fn)
    local f = CreateFrame("Frame", nil, col); f:SetHeight(H.DAY_ROW)
    f.link = UI.KitButton(f, "", "link", fn, { role = "BODY" })
    f.link:SetPoint("TOPLEFT", f, "TOPLEFT", S.S3, -4)
    return f
  end
  content.moreDeaths = linkRow(function() UI.Open("Home", "deaths") end)
  content.more = linkRow(function() UI.Open("Home", "activity") end)
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
  put(content.hero, H.HERO); y = y + H.HERO + S.S3
  put(content.sesHead, H.SECTION); y = y + H.SECTION
  put(content.cards, H.STAT); pcall(content.cards.layout); y = y + H.STAT + S.S5
  put(content.nextHead, H.SECTION); y = y + H.SECTION
  for _, r in ipairs(content.nextRows) do if r:IsShown() then put(r, H.ROW2); y = y + H.ROW2 end end
  if content.allClear:IsShown() then put(content.allClear, H.SECTION); y = y + H.SECTION end
  y = y + S.S5
  put(content.lookHead, H.SECTION); y = y + H.SECTION
  for _, r in ipairs(content.lookRows) do if r:IsShown() then put(r, H.ROW2); y = y + H.ROW2 end end
  if content.lookEmpty:IsShown() then put(content.lookEmpty, H.SECTION); y = y + H.SECTION end
  if content.moreDeaths:IsShown() then put(content.moreDeaths, H.DAY_ROW); y = y + H.DAY_ROW end
  if content.more:IsShown() then put(content.more, H.DAY_ROW); y = y + H.DAY_ROW end
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
  local start = ses and plain(ses.startedEpoch)
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
  hero:SetTitle(type(name) == "string" and name or "", { UI.ClassColor(classFile) })
  local who = ("Level %d"):format(lvl)
  if type(race) == "string" and race ~= "" then who = who .. " " .. race end
  if type(classN) == "string" and classN ~= "" then who = who .. " " .. classN end
  if type(zone) == "string" and zone ~= "" then who = who .. " \194\183 " .. zone end
  hero:SetTitleMeta(who)
  if hero.image and type(SetPortraitTexture) == "function" then pcall(SetPortraitTexture, hero.image, "player") end
  local cur, mx = readXP()
  if not cur then local x = type(db.xp) == "table" and db.xp or {}; cur, mx = num(x.cur), num(x.max) end
  local rested = plain(call(GetXPExhaustion)) or 0
  local pace = Pace.compute(now)
  content.pace = pace
  local atMax = lvl >= maxLvl
  local remaining = (not atMax) and Pace.remaining(cur, mx, pace.rate) or nil
  content.remaining = remaining
  if atMax then
    hero:SetHero("Level " .. lvl); hero:SetMeta("Max level", nil); hero:SetBar(nil); hero:SetMeta2(nil)
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
    tip:AddLine("At your XP per hour over the last 30 minutes of active play. It already includes the rested bonus you earned in that time.", 0.78, 0.79, 0.80, true)
    local pl = type(db.played) == "table" and db.played or {}
    if num(pl.total) > 0 then tip:AddDoubleLine("Played in all", UI.fmtDur(pl.total, { minutes = true }), C.fgMuted[1], C.fgMuted[2], C.fgMuted[3], 1, 1, 1) end
    if num(pl.level) > 0 then tip:AddDoubleLine("At this level", UI.fmtDur(pl.level, { minutes = true }), C.fgMuted[1], C.fgMuted[2], C.fgMuted[3], 1, 1, 1) end
    local k = P.kill
    if k and not atMax and mx > cur then
      tip:AddLine(("About %s more %s kills"):format(UI.fmtNum(math.ceil((mx - cur) / k.xp)), k.name), 0.78, 0.79, 0.80, true)
    end
  end

  -- THIS SESSION: played, XP per hour, gold, deaths
  content.sesHead:SetMeta(nil)   -- (the PLAYED card says when the session started: no second "since")
  local cards = content.cards.cards
  local elapsed = start and math.max(0, now - start) or 0
  cards[1]:Set("Played", start and UI.fmtDur(elapsed, { minutes = true }) or "-", start and (UI.fmtClock(start) .. " to now") or "no session yet")
  UI.SetTip(cards[1], { title = "Played", text = "How long this session has run. Opens your sessions." })
  if atMax then
    cards[2]:Set("XP per hour", "-", "max level")
    UI.SetTip(cards[2], { title = "XP per hour", text = "You are at the level cap." })
  elseif pace.rate then
    cards[2]:Set("XP per hour", UI.fmtNum(pace.rate), ("last %dm of play"):format(pace.used))
    UI.SetTip(cards[2], { title = "XP per hour", text = ("+%s XP this session"):format(UI.fmtNum(pace.xp)) })
  else
    cards[2]:Set("XP per hour", "-", "after 10m of play")
    UI.SetTip(cards[2], { title = "XP per hour", text = "Shows after 10 minutes of play" })
  end
  local net, perHour
  if ns.Gold and ns.Gold.metric then
    local ok1, a = pcall(ns.Gold.metric, "net", "char", "session"); net = ok1 and a or nil
    local ok2, b = pcall(ns.Gold.metric, "perHour", "char", "session"); perHour = ok2 and b or nil
  end
  cards[3]:Set("Gold", type(net) == "number" and UI.money(net, true) or "-",
    type(perHour) == "number" and (UI.money(math.floor(perHour + 0.5), true) .. " per hour") or "per hour after 5m")
  local bal = num(type(db.gold) == "table" and db.gold.balance)
  local goldPairs = { { "Balance", ns.fmtMoney(bal, { icons = true }) } }
  if ns.Gold and ns.Gold.roster then
    local ok, ro = pcall(ns.Gold.roster, "all")
    if ok and type(ro) == "table" and num(ro.count) > 1 then goldPairs[2] = { "All characters", ns.fmtMoney(num(ro.total), { icons = true }) } end
  end
  UI.SetTip(cards[3], { title = "Gold this session", text = "What you made this session, and per hour of play.", pairs = goldPairs })
  local kills, sdeaths, items = num(ses and ses.kills), num(ses and ses.deaths), num(ses and ses.items)
  local lk, ld = 0, 0
  for _, s in pairs((ns.DB and ns.DB.sessions) or {}) do if type(s) == "table" and ns.isMySession(s) then lk, ld = lk + num(s.kills), ld + num(s.deaths) end end
  -- (the META is about deaths: how many in all, never kills and items)
  cards[4]:Set("Deaths", UI.fmtNum(sdeaths), ld > 0 and (UI.plural(ld, "death") .. " in all") or "none in all")
  UI.SetTip(cards[4], { title = "Deaths this session", text = "Opens every death.", pairs = { { "Lifetime", UI.plural(lk, "kill") .. " \194\183 " .. UI.plural(ld, "death") } } })

  -- NEXT
  local nx = Now.nextItems(w - (S.S3 + 24 + S.S2) - S.S3, now)
  content.nextList = nx
  for i, it in ipairs(nx) do row2(content, content.nextRows, i):Set(it):Show() end
  for i = #nx + 1, #content.nextRows do content.nextRows[i]:Hide() end
  if #nx == 0 then content.allClear:Set("Nothing needs you. Go have fun.", nil, nil, "good"); content.allClear:Show() else content.allClear:Hide() end

  -- WORTH A LOOK
  local look, extra, ev = Now.lookItems(now)
  local cap = G.isWide(G.winW()) and Now.CAP_WIDE or Now.CAP_COMPACT
  if #look == 0 and (#ev > 0 or kills > 0 or items > 0) then
    look = { { kind = "session", icon = UI.KIND_ICON.session, title = ("%s and %s so far"):format(UI.plural(kills, "kill"), UI.plural(items, "item")),
      meta = "No deaths and no level yet. Keep going." } }
  end
  local shown = math.min(#look, cap)
  content.lookList = look
  for i = 1, shown do row2(content, content.lookRows, i):Set(look[i]):Show() end
  for i = shown + 1, #content.lookRows do content.lookRows[i]:Hide() end
  if #look == 0 then content.lookEmpty:Set("Nothing yet. Run a dungeon, ding, or loot something green and it shows here."); content.lookEmpty:Show() else content.lookEmpty:Hide() end
  if extra.deaths and extra.deaths > 0 then
    content.moreDeaths.link:SetLabel(UI.plural(extra.deaths, "more death") .. " \226\128\186"); content.moreDeaths:Show()
  else content.moreDeaths:Hide() end
  if #look > cap then content.more.link:SetLabel(("+%d more \226\128\186"):format(#look - cap)); content.more:Show() else content.more:Hide() end

  Now.place(content)
end
local build, refresh = Now.build, Now.refresh


-- ── HOME / Sessions: one row per play session (login -> logout), newest first ─────
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
-- a strip of bars, one per session (oldest left), value scaled to the strip height; negative values
-- hang below the baseline in ember. Pooled textures; hover names the session and value. The strip is as wide as
-- the pane gives it (placeStrips): each of the STRIP_N slots is stripW / STRIP_N wide and holds a bar of at most
-- BAR_MAX px, centred in it.
local STRIP_N, STRIP_H, BAR_W, BAR_GAP, BAR_MAX = 10, 44, 28, 4, 56
local function makeStrip(parent, label, n)
  local st = CreateFrame("Frame", nil, parent); st:SetSize((n or STRIP_N) * (BAR_W + BAR_GAP), STRIP_H + 18)
  st.n = n or STRIP_N
  st.slot, st.barW = BAR_W + BAR_GAP, BAR_W
  st.title = UI.FS(st, "GameFontNormalSmall", C.dim); st.title:SetPoint("TOPLEFT", 0, 0); st.title:SetText(label:upper())
  st.base = st:CreateTexture(nil, "ARTWORK"); st.base:SetPoint("BOTTOMLEFT", 0, 0); st.base:SetPoint("BOTTOMRIGHT", 0, 0); st.base:SetHeight(1)
  st.base:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
  st.bars, st.hits = {}, {}
  return st
end
-- values: array of { v = number, label = string } oldest first (false leaves a slot empty); fmt(v) renders the hover text
local function renderStrip(st, values, fmt, signed)
  st.values, st.fmt, st.signed = values, fmt, signed   -- drawn again when the strip takes a new width
  local slot, bw = st.slot, st.barW
  local maxAbs = 1
  -- (a slot may be empty: false, as the Days strip of Loot > Gold leaves a day without a row)
  for i = 1, st.n or STRIP_N do local e = values[i]; if e and math.abs(e.v) > maxAbs then maxAbs = math.abs(e.v) end end
  local baseY = signed and STRIP_H / 2 or 0
  st.base:ClearAllPoints(); st.base:SetPoint("BOTTOMLEFT", 0, baseY); st.base:SetPoint("BOTTOMRIGHT", 0, baseY)
  local span = signed and STRIP_H / 2 or STRIP_H
  for i = 1, st.n or STRIP_N do
    local e = values[i]
    local bar = st.bars[i]; local hit = st.hits[i]
    if not bar then
      bar = st:CreateTexture(nil, "ARTWORK"); st.bars[i] = bar
      hit = CreateFrame("Frame", nil, st); hit:EnableMouse(true); st.hits[i] = hit
      hit:SetScript("OnEnter", function(h) if h.tip and GameTooltip then GameTooltip:SetOwner(h, "ANCHOR_TOP"); GameTooltip:AddLine(h.tip, 1, 1, 1); GameTooltip:Show() end end)
      hit:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    end
    if e then
      local h = math.max(1, math.floor(math.abs(e.v) / maxAbs * (span - 2) + 0.5))
      bar:ClearAllPoints(); bar:SetWidth(bw); bar:SetHeight(h)
      local cx = (i - 1) * slot + slot / 2
      if e.v < 0 then bar:SetPoint("TOP", st, "BOTTOMLEFT", cx, baseY)
      else bar:SetPoint("BOTTOM", st, "BOTTOMLEFT", cx, baseY) end
      local col = e.v < 0 and C.red or (e.live and C.cyan or C.gold)
      bar:SetColorTexture(col[1], col[2], col[3], 0.85); bar:Show()
      hit:ClearAllPoints(); hit:SetSize(slot, STRIP_H); hit:SetPoint("BOTTOMLEFT", (i - 1) * slot, 0); hit.tip = e.label .. "  ·  " .. fmt(e.v); hit:Show()
    else bar:Hide(); hit:Hide() end
  end
end
local function stripValues(rows, key, signed)
  -- rows newest first -> take the last STRIP_N, oldest left
  local out = {}
  local n = math.min(#rows, STRIP_N)
  for i = n, 1, -1 do
    local sess = rows[i]
    local v = signed and ((tonumber(sess.gained) or 0) - (tonumber(sess.spent) or 0)) or (tonumber(sess[key]) or 0)
    out[#out + 1] = { v = v, label = date("%b %d, %H:%M", sess.startedEpoch or 0), live = (sess.endedEpoch == nil) }
  end
  return out
end
ns._test = ns._test or {}
ns._test.stripValues = stripValues
-- the strip is also the Days view's (Loot > Gold, Economy.lua): one bar per day
UI.makeStrip, UI.renderStrip, UI.STRIP_H = makeStrip, renderStrip, STRIP_H + 18

local BAND_H = 104          -- the selected session's gold band under the list
local sel = {}              -- sel.id: the session clicked; sel.shown: the session the band shows
local function buildSessions(content)
  sessionsView = content
  local xpStrip = makeStrip(content, "XP per session")
  local goldStrip = makeStrip(content, "Gold per session")
  content.xpStrip, content.goldStrip = xpStrip, goldStrip
  -- the two strips share the list's width in two halves, L apart, from the table's text inset (SP.S) to its right
  -- inset, so their titles line up with the SESSION header and the right half of the row is used
  local function placeStrips(w)
    w = tonumber(w) or 0
    if w <= 1 then return end
    local SP = UI.SP
    local left, right = S.S3, w - UI.SCROLLBAR - S.S3
    local half = math.floor((right - left - SP.L) / 2)
    for i, st in ipairs({ xpStrip, goldStrip }) do
      st:ClearAllPoints(); st:SetPoint("TOPLEFT", content, "TOPLEFT", left + (i - 1) * (half + SP.L), -4)
      st:SetWidth(half)
      st.slot = half / STRIP_N
      st.barW = math.max(4, math.min(BAR_MAX, math.floor(st.slot - BAR_GAP)))
      if st.values then renderStrip(st, st.values, st.fmt, st.signed) end
    end
  end
  content.placeStrips = placeStrips
  content:HookScript("OnSizeChanged", function(_, w) pcall(placeStrips, w) end)
  pcall(placeStrips, content:GetWidth())
  -- Session · (live) · Length · Level · XP · Gold · Kills · Deaths · Dungeons · Items: the numbers right-aligned at
  -- the right, the session's date takes the free width
  local tbl = UI.Table(content, {
    { key = "date", label = "Session", flex = 1, min = 110 },
    { key = "live", label = "", kind = "tag", color = "green", measure = { "•" } },
    { key = "len", label = "Length", kind = "num", color = "dim", measure = { "23h 59m" } },
    { key = "lvl", label = "Level", kind = "num", measure = { "59 > 60" } },
    { key = "xp", label = "XP", kind = "num", measure = { "9,999,999" } },
    { key = "gold", label = "Gold", kind = "money", color = "gold", measure = { "+" .. coin2(9999999) } },
    { key = "kills", label = "Kills", kind = "num", measure = { "9999" } },
    { key = "deaths", label = "Deaths", kind = "num", color = "dim", measure = { "999" } },
    { key = "dung", label = "Dungeons", kind = "num", measure = { "99" } },
    { key = "items", label = "Items", kind = "num", measure = { "9999" } },
  }, { top = -(4 + STRIP_H + 18 + UI.SP.M), bottom = BAND_H + UI.SP.M, emptyText = "Your first session starts when you log in.",
    onClick = function(_, sess) if sess and sess.id then sel.id = sess.id; if sessionsRebuild then sessionsRebuild() end end end })
  content.tbl = tbl
  -- the selected session's gold (#38): the running session until a row is clicked. One title line (net and pace) and
  -- four blocks of three lines: top sources, best earners, biggest sinks, flags. The button opens its journal.
  local SP = UI.SP
  local band = UI.Panel(content)
  band:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 0, 0); band:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0); band:SetHeight(BAND_H)
  band.open = UI.Button(band, "Open gold journal", 120, UI.ROW_H, function() if ns.Gold and sel.shown then ns.Gold.open(sel.shown, "journal") end end)
  band.open:SetPoint("TOPRIGHT", band, "TOPRIGHT", -SP.S, -SP.S)
  band.title = UI.CellFS(band, "GameFontNormalSmall", C.gold); band.title:SetJustifyH("LEFT")
  band.title:SetPoint("LEFT", band, "TOPLEFT", SP.M, -(SP.S + UI.ROW_H / 2)); band.title:SetPoint("RIGHT", band.open, "LEFT", -SP.M, 0)
  band.blocks = {}
  -- (NOTES, not "flags": a banned word, principle 8)
  for i, label in ipairs({ "TOP SOURCES", "BEST EARNERS", "BIGGEST SINKS", "NOTES" }) do
    local b = CreateFrame("Frame", nil, band); b:SetHeight(BAND_H - UI.ROW_H - 2 * SP.S - SP.XS)
    b.head = UI.CellFS(b, "GameFontNormalSmall", C.dim); b.head:SetJustifyH("LEFT"); b.head:SetText(label)
    b.head:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0); b.head:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, 0)
    b.lines = {}
    for j = 1, 3 do
      local fs = UI.CellFS(b, "GameFontHighlightSmall", C.ink); fs:SetJustifyH("LEFT")
      fs:SetPoint("TOPLEFT", b, "TOPLEFT", 0, -(j * 16)); fs:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, -(j * 16))
      b.lines[j] = fs
    end
    band.blocks[i] = b
  end
  -- four blocks where they fit whole; under WIDE the BEST EARNERS block goes, so no line of the other three is cut
  local function placeBand(w)
    w = tonumber(w) or 0
    if w <= 1 then return end
    local shown = {}
    for i, b in ipairs(band.blocks) do
      if i == 2 and not UI.G.isWide(UI.G.winW()) then b:Hide() else b:Show(); shown[#shown + 1] = b end
    end
    local n = #shown
    local bw = math.floor((w - 2 * SP.M - (n - 1) * SP.L) / n)
    band.blockW = bw
    for i, b in ipairs(shown) do
      b:ClearAllPoints(); b:SetPoint("TOPLEFT", band, "TOPLEFT", SP.M + (i - 1) * (bw + SP.L), -(SP.S + UI.ROW_H + SP.XS)); b:SetWidth(bw)
    end
  end
  content:HookScript("OnSizeChanged", function(_, w) pcall(placeBand, w) end)
  pcall(placeBand, content:GetWidth())
  content.goldBand = band
  local function fillBand(rows)
    local sess
    for _, s in ipairs(rows) do if s.id == sel.id then sess = s end end
    sess = sess or rows[1]
    sel.shown = sess and sess.id or nil
    local sum = sess and ns.Gold and ns.Gold.summary(sess)
    if not sum then band:Hide(); return end
    band:Show()
    local title = ("GOLD  ·  %s  ·  %s  ·  net %s"):format(date("%b %d, %H:%M", sess.startedEpoch or 0),
      fmtTime(sum.elapsed), ns.Gold.signed(sum.net))
    if sum.perHour then title = title .. ("  ·  %s per hour"):format(ns.Gold.signed(sum.perHour)) end
    band.title:SetText(title)
    local L = { {}, {}, {}, {} }
    for i, r in ipairs(sum.topIn) do L[1][i] = { ("%s  %s"):format(r.label, coin2(r.amount)) } end
    -- (a long name is shortened, never the amount: the line is cut at the name with "...")
    local function best(word, t)
      if not t then return end
      local name, amt = tostring(t.name or ""), coin2(t.amount)
      L[2][#L[2] + 1] = { ("%s: %s  %s"):format(word, name, amt), nil, function(n) return ("%s: %s...  %s"):format(word, name:sub(1, n), amt) end, #name }
    end
    best("Quest", sum.bestQuest); best("Mob", sum.bestMob); best("Sold", sum.bestItem)
    for i, r in ipairs(sum.sinks) do L[3][i] = { ("%s  %s"):format(r.label, coin2(r.amount)) } end
    -- (bookkeeping notes in a neutral colour: red never means unusual bookkeeping, principle 5)
    if #sum.strangers > 0 then
      -- (whole names plus "+N" in the block's width)
      local pre, names = "Players you traded with: ", sum.strangers
      local room = (band.blockW or 200) - UI.TextWidth("BODY", pre)
      local out, shownN = "", 0
      for i, n in ipairs(names) do
        local cand = (shownN > 0 and (out .. ", ") or "") .. n
        local tail = (#names - i) > 0 and (" +" .. (#names - i)) or ""
        if shownN > 0 and UI.TextWidth("BODY", cand .. tail) > room then break end
        out, shownN = cand, shownN + 1
      end
      if shownN < #names then out = out .. " +" .. (#names - shownN) end
      L[4][#L[4] + 1] = { pre .. out, C.fgSubtle }
    end
    if sum.unexplained > 0 then L[4][#L[4] + 1] = { "Unexplained: " .. coin2(sum.unexplained), C.fgSubtle } end
    if sum.above > 0 then L[4][#L[4] + 1] = { ("Above vendor price: %d sale%s"):format(sum.above, sum.above == 1 and "" or "s"), C.fgSubtle } end
    if #L[4] < 3 and sum.away ~= 0 then L[4][#L[4] + 1] = { "Changed while away: " .. ns.Gold.signed(sum.away) } end
    if #L[4] < 3 and sum.dropped > 0 then L[4][#L[4] + 1] = { ("%d rows past the cap not kept"):format(sum.dropped) } end
    local EMPTY = { "No income", sum.journal and "None recorded" or "Recorded before addon 0.9.40", "Nothing spent", "Nothing to note" }
    for i, b in ipairs(band.blocks) do
      for j, fs in ipairs(b.lines) do
        local l = L[i][j] or (j == 1 and #L[i] == 0 and { EMPTY[i], C.dim }) or nil
        fs:SetText(l and l[1] or "")
        if l and l[3] and fs.IsTruncated then
          local n = l[4]
          while n > 4 and fs:IsTruncated() do n = n - 1; fs:SetText(l[3](n)) end
        end
        local col = (l and l[2]) or C.ink
        fs:SetTextColor(col[1], col[2], col[3])
      end
    end
  end
  sessionsRebuild = function()
    local rows = sessionRows()
    renderStrip(xpStrip, stripValues(rows, "xp"), function(v) return commas(v) .. " XP" end, false)
    renderStrip(goldStrip, stripValues(rows, nil, true), function(v) return (v < 0 and "-" or "+") .. fmtMoney(math.abs(v)) end, true)
    local nowT = (GetServerTime and GetServerTime()) or time()
    pcall(fillBand, rows)
    tbl.setRows(rows, function(row, sess)
      local c = row.c
      local live = (sess.endedEpoch == nil)
      local endT = sess.endedEpoch or nowT
      c.date:SetText(UI.fmtWhen(sess.startedEpoch or 0))
      if sess.id == sel.shown then c.date:SetTextColor(C.fgSubtle[1], C.fgSubtle[2], C.fgSubtle[3]) end   -- the row the gold band shows (never mint on a value)
      c.live:SetText(live and "•" or "")
      if live then c.live:SetTextColor(C.fgSubtle[1], C.fgSubtle[2], C.fgSubtle[3]) end
      c.len:SetText(fmtTime(math.max(0, endT - (sess.startedEpoch or endT))))
      local l0, l1 = tonumber(sess.level0) or tonumber(sess.level) or 0, tonumber(sess.level) or 0
      c.lvl:SetText(l1 > l0 and (l0 .. " > " .. l1) or tostring(l1))
      if l1 > l0 then c.lvl:SetTextColor(C.gold[1], C.gold[2], C.gold[3]) end
      c.xp:SetText(UI.fmtNum(sess.xp or 0))
      local net = (tonumber(sess.gained) or 0) - (tonumber(sess.spent) or 0)
      c.gold:SetText((net < 0 and "-" or "+") .. coin2(math.abs(net)))
      if net < 0 then c.gold:SetTextColor(C.red[1], C.red[2], C.red[3]) end
      c.kills:SetText(UI.fmtNum(sess.kills or 0))
      c.deaths:SetText(tostring(sess.deaths or 0))
      if (tonumber(sess.deaths) or 0) > 0 then c.deaths:SetTextColor(C.red[1], C.red[2], C.red[3]) end
      c.dung:SetText(tostring(sess.dungeons or 0))
      c.items:SetText(UI.fmtNum(sess.items or 0))
    end)
  end
  sessionsRebuild()
end
-- HOME is the landing tab (order 0). Now and Sessions live here; Activity (the 0.9.51 Timeline) is registered
-- into Home by Emitter.lua, Fights by Recording.lua and Deaths by Deaths.lua (docs/UX_OVERHAUL.md 0.3).
UI.registerHost(0, "Home", "How this session is going, and every session, pull and death before it.")
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
ns._test.fmtTime, ns._test.commas, ns._test.journeyMoney = fmtTime, commas, fmtMoney
ns._test.journeyRefresh = function() if nowView then refresh(nowView) end return nowView end
