-- Everbuff.GG · Economy.lua - gold: the one model behind every place gold shows (everbuff-wow-addon #38).
--
-- ns.Gold reads what Emitter captures (the character's ledger, each session's ledger, and from 0.9.40 each session's
-- gold journal `goldLog` and `trades`) and answers three questions for every pane:
--   Gold.scope(key)        which sessions and which ledger a period means: "session" (the running one), "previous",
--                          "all" (the character's lifetime ledger and every journal still in the save file), or a
--                          session id (picked on Home / Sessions)
--   Gold.entries(sess)     the session's journal as rows: time, signed amount, source, detail (the quest, the item
--                          and the merchant, the mob, the player and who they are), Location and Coordinates as two
--                          values, balance after, and a flag (a stranger, an unexplained change, a sale above the
--                          vendor price)
--   Gold.sources(sc, rows) the per-source ledger of a scope, each source with its row count and biggest contributors
--   Gold.summary(sess)     a session's aggregates: per hour, top sources, best quest, mob and item sold, biggest
--                          sinks, flags (Home / Sessions and the Overview card read it)
-- Nothing is stored: the journal carries no place, so Location and Coordinates come from the record the gold belongs
-- to and nowhere else: the loot row of a coin pickup or a mail (same amount, same moment), the QUESTDONE row of a
-- turn-in, the TRADE row of a trade, the vendor, trainer, mailbox or auction house visit the change fell in. A row
-- with no such record (a flight, an unexplained change) has no place and shows none.
--
-- The Gold pane of the LOOT tab is the single home for gold: a period, five numbers for it, the source ledger, and
-- behind every source the journal rows that make it up.
--   toolbar  the period buttons at the left; the view button (Sources or Journal) and the search box at the right
--   cards    BALANCE, IN, OUT, NET and PER HOUR for the period, one row when each fits, else three over two
--   caption  what the list below shows, with "Flagged" (strangers, unexplained, above vendor price) and "All rows"
--   list     Sources: one row per source with money in the period, IN then OUT, a click opens its rows.
--            Journal: Time · Source · Detail · Location · Coords · Amount · Balance, newest first, one section per
--            session when the period holds several. Balance is left out when the list is too narrow for it.

local ADDON, ns = ...
local UI = ns.UI
local C = ns.UI.C

local fmtMoney = ns.fmtMoney   -- the one formatter (UI.lua)
local SP = UI.SP
local PAD, GAP, ROW_H = SP.S, SP.M, UI.ROW_H
local SEP = "  ·  "

local Gold = {}
ns.Gold = Gold

Gold.IN  = { "looted", "quests", "sold", "auctionSales", "mail", "trade", "unexplained" }
Gold.OUT = { "repairs", "vendor", "training", "flights", "auctions", "mailSpent", "tradeSpent", "other" }
-- the ledger's name of a source, and the word a journal row carries
Gold.LABEL = { looted = "Looted coin", quests = "Quest rewards", sold = "Sold to vendors", auctionSales = "Auction sales",
  mail = "Mail received", trade = "Trades received", unexplained = "Unexplained income",
  repairs = "Repairs", vendor = "Bought from vendors", training = "Training", flights = "Flights",
  auctions = "Auction house", mailSpent = "Mail: postage and COD", tradeSpent = "Trades given", other = "Unexplained spending",
  away = "Changed while away" }
Gold.WORD = { looted = "Loot", quests = "Quest", sold = "Vendor sale", auctionSales = "Auction sale", mail = "Mail",
  trade = "Trade", unexplained = "Unexplained", repairs = "Repair", vendor = "Vendor buy", training = "Training",
  flights = "Flight", auctions = "Auction house", mailSpent = "Mail", tradeSpent = "Trade", other = "Unexplained", away = "Away" }
local IS_IN, IS_OUT = {}, {}
for _, k in ipairs(Gold.IN) do IS_IN[k] = true end
for _, k in ipairs(Gold.OUT) do IS_OUT[k] = true end

local function num(v) v = tonumber(v); return (v and v == v) and v or 0 end
local function signed(c) c = num(c); return (c < 0 and "-" or "+") .. fmtMoney(math.abs(c)) end
Gold.signed = signed
local function nowT() return (GetServerTime and GetServerTime()) or time() end

local function itemName(id)
  id = tonumber(id)
  if not id or id == 0 then return nil end
  local name
  if C_Item and C_Item.GetItemNameByID then
    local ok, v = pcall(C_Item.GetItemNameByID, id)
    if ok and type(v) == "string" and v ~= "" then name = v end
  end
  if not name and GetItemInfo then
    local ok, v = pcall(GetItemInfo, id)
    if ok and type(v) == "string" and v ~= "" then name = v end
  end
  return name or ("item " .. id)
end
local function questName(id)
  id = tonumber(id)
  if id and C_QuestLog and C_QuestLog.GetTitleForQuestID then
    local ok, v = pcall(C_QuestLog.GetTitleForQuestID, id)
    if ok and type(v) == "string" and v ~= "" then return v end
  end
  return nil
end
local function refParse(s)
  local t = {}
  for k, v in (s or ""):gmatch("([^;=]+)=([^;]*)") do t[k] = v end
  return t
end
-- "Xzqtgold <Cheap Gold Fast> (stranger)"
local function person(name, guild, rel)
  if not name or name == "" then return nil end
  local out = name
  if guild and guild ~= "" then out = out .. " <" .. guild .. ">" end
  if rel and rel ~= "" and rel ~= "system" then out = out .. " (" .. rel .. ")" end
  return out
end

-- ── the records a journal row can belong to, per session ────────────────────────────────────────────────────────
local VISIT_OF = { sold = "VENDOR", vendor = "VENDOR", repairs = "VENDOR", training = "TRAINER", auctions = "AUCTION",
  mailSpent = "MAIL", mail = "MAIL", auctionSales = "MAIL" }
local EVENT_KINDS = { QUESTDONE = true, TRADE = true, GOLDAWAY = true, VENDOR = true, TRAINER = true, MAIL = true, AUCTION = true }
local COIN = { looted = true, mail = true, auctionSales = true }
local TOL = 5   -- seconds between a purse change and the record written for it
function Gold.index()
  local ix = {}
  local function of(sid)
    local b = ix[sid]
    if not b then b = { coins = {}, ev = {} }; ix[sid] = b end
    return b
  end
  local db = ns.DB or {}
  for _, r in ipairs((db.loot and db.loot.log) or {}) do
    if type(r) == "table" and r.money and r.s then local b = of(r.s); b.coins[#b.coins + 1] = r end
  end
  for _, e in ipairs((db.story and db.story.events) or {}) do
    if type(e) == "table" and e.s and EVENT_KINDS[e.kind] then
      local b = of(e.s)
      b.ev[e.kind] = b.ev[e.kind] or {}
      table.insert(b.ev[e.kind], e)
    end
  end
  return ix
end

local function place(e, rec)
  if not rec then return end
  e.zone = rec.zone
  if type(rec.x) == "number" and type(rec.y) == "number" then e.x, e.y = rec.x, rec.y end
end
-- the event of `list` this row belongs to: `fits(ev)` and not taken by an earlier row (`taken`, a set kept beside
-- the events: nothing is written into the story rows)
local function take(list, taken, fits)
  for _, ev in ipairs(list or {}) do
    if not taken[ev] and fits(ev) then taken[ev] = true; return ev end
  end
end

local function describe(e)
  local r, src = e.ref, e.src
  local npc = r.npc
  if src == "quests" then
    e.detail = e.quest or (r.quest and ("Quest " .. r.quest)) or "a quest"
    e.group = e.detail
  elseif src == "looted" then
    e.detail = e.loot and e.loot.src or ""
    if r.x then e.detail = (e.detail ~= "" and (e.detail .. ", ") or "") .. r.x .. " pickups in one row" end
    e.group = (e.loot and e.loot.src) or "source not recorded"
  elseif src == "sold" or src == "vendor" then
    local name = itemName(r.item)
    local what = name and (name .. " x" .. (r.n or 1)) or nil
    local word = src == "sold" and " to " or " from "
    e.detail = (what or (src == "sold" and "items" or "an item")) .. (npc and (word .. npc) or "")
    e.group = name or npc or "not recorded"
    local unit, n = tonumber(r.unit), tonumber(r.n)
    if src == "sold" and unit and n and unit * n > 0 then
      e.vendorPrice = unit * n
      if e.delta > unit * n then e.flag = "above vendor price" end
    end
  elseif src == "repairs" or src == "training" or src == "flights" then
    e.detail = npc or ""
    e.group = npc or "not recorded"
  elseif src == "mail" or src == "auctionSales" then
    local m = e.loot and e.loot.mail
    if src == "auctionSales" and type(m) == "table" and m.item then
      e.detail = m.item .. (m.buyer and (" to " .. m.buyer) or "")
      e.group = m.item
    else
      e.detail = r.sender and ("from " .. person(r.sender, nil, r.rel)) or "mailbox"
      e.group = r.sender or "not recorded"
    end
    if src == "mail" and r.rel == "stranger" then e.flag = "stranger" end
  elseif src == "mailSpent" then
    if num(r.cod) > 0 then
      e.detail = "COD to " .. (person(r.sender, nil, r.rel) or "a player")
      e.group = r.sender or "COD"
      if r.rel == "stranger" then e.flag = "stranger" end
    else e.detail = "Postage"; e.group = "Postage" end
  elseif src == "trade" or src == "tradeSpent" then
    e.detail = person(r.partner, r.guild, r.rel) or "a player the client did not name"
    e.group = r.partner or "not named"
    if r.rel == "stranger" or not r.partner then e.flag = "stranger" end
    local t = tonumber(r.trade)
    e.tradeRec = t and e.sess.trades and e.sess.trades[t] or nil
  elseif src == "auctions" then
    e.detail = "bid, buyout or deposit"
  elseif src == "away" then
    e.detail = "while the addon was not running" .. (r.mailWaiting and ", mail was waiting" or "")
  elseif src == "unexplained" then
    e.detail = "no source seen"; e.flag = "unexplained"
  elseif src == "other" then
    e.detail = "no window was open"; e.flag = "unexplained"
  else e.detail = "" end
end

-- The journal of one session as rows, oldest first. `ix` is Gold.index() (built once for several sessions).
function Gold.entries(sess, ix)
  local out = {}
  local log = sess and sess.goldLog
  if type(log) ~= "table" then return out end
  local t0, m0 = num(sess.startedEpoch), tonumber(sess.startedMono)
  for i, r in ipairs(log) do
    if type(r) == "string" then
      local mono, d, src, bal, ref = r:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t(.*)$")
      d, mono = tonumber(d), tonumber(mono)
      if d and src then
        out[#out + 1] = { i = i, sid = sess.id, sess = sess, delta = d, src = src, bal = tonumber(bal), ref = refParse(ref), mono = mono,
          t = (m0 and mono) and math.floor(t0 + (mono - m0) + 0.5) or t0 }
      end
    end
  end
  local b = (ix or Gold.index())[sess.id]
  if b then
    -- coin rows: the loot rows of the session carry the mob or the mail, the zone and the coordinates. Both lists
    -- are in the order the coin came in; walked from the newest (the loot log is trimmed at its old end).
    local j = #b.coins
    for k = #out, 1, -1 do
      local e = out[k]
      if COIN[e.src] then
        while j >= 1 and num(b.coins[j].t) > e.t + TOL do j = j - 1 end
        local c = b.coins[j]
        if c and c.money == e.delta and math.abs(num(c.t) - e.t) <= TOL then e.loot = c; place(e, c); j = j - 1 end
      end
    end
    local taken = {}
    local open = ns.Visits and ns.Visits.open
    for _, e in ipairs(out) do
      local ev
      if e.src == "quests" then
        ev = take(b.ev.QUESTDONE, taken, function(v) return math.abs(num(v.t) - e.t) <= TOL end)
        e.quest = questName(e.ref.quest) or (ev and type(ev.text) == "string" and ev.text:match("^Complete:%s+(.+)$")) or nil
      elseif e.src == "trade" or e.src == "tradeSpent" then
        ev = take(b.ev.TRADE, taken, function(v) return v.money == e.delta and math.abs(num(v.t) - e.t) <= TOL end)
      elseif e.src == "away" then
        ev = take(b.ev.GOLDAWAY, taken, function(v) return v.money == e.delta and math.abs(num(v.t) - e.t) <= TOL end)
      elseif VISIT_OF[e.src] and not e.zone then
        -- (a visit holds many rows, so it is never taken)
        local kind = VISIT_OF[e.src]
        ev = take(b.ev[kind], {}, function(v) return e.t >= num(v.t) - TOL and e.t <= num(v.closed or v.t) + TOL end)
        if not ev and open and open.kind == kind and open.s == sess.id and e.t >= num(open.t) - TOL then ev = open.where end
      end
      place(e, ev)
    end
  end
  for _, e in ipairs(out) do describe(e) end
  return out
end

-- ── scopes ──────────────────────────────────────────────────────────────────────────────────────────────────────
-- the logged-in character's sessions, the running one first, then newest first
function Gold.sessions()
  local out = {}
  for _, sess in pairs((ns.DB and ns.DB.sessions) or {}) do
    if type(sess) == "table" and ns.isMySession(sess) then out[#out + 1] = sess end
  end
  table.sort(out, function(a, b)
    local la, lb = a.endedEpoch == nil, b.endedEpoch == nil
    if la ~= lb then return la end
    if (a.startedEpoch or 0) ~= (b.startedEpoch or 0) then return (a.startedEpoch or 0) > (b.startedEpoch or 0) end
    return tostring(a.id) > tostring(b.id)
  end)
  return out
end
local function current() return ns.Recorder and ns.Recorder.current and ns.Recorder.current() or nil end
local function sessionLedger(sess)
  local g = {}
  if type(sess.gold) == "table" then for k, v in pairs(sess.gold) do g[k] = num(v) end end
  g.gained, g.spent = g.gained or num(sess.gained), g.spent or num(sess.spent)
  return g
end
local function sessionLabel(sess) return date("%b %d, %H:%M", sess.startedEpoch or 0) end
Gold.sessionLabel = sessionLabel
-- seconds a session ran; a session that never closed and is not the running one (a crash) has no known length
local function elapsedOf(sess)
  local endT = sess.endedEpoch or (sess == current() and nowT()) or sess.startedEpoch
  return math.max(0, (endT or 0) - (sess.startedEpoch or endT or 0))
end
local function fmtLen(sec)
  sec = math.floor(num(sec) / 60)
  if sec >= 60 then return ("%dh %dm"):format(math.floor(sec / 60), sec % 60) end
  return ("%dm"):format(sec)
end

-- key: "session", "previous", "all", a session id, or a day period of Gold.period ("today", "week", "day:YYYYMMDD",
-- ...). who: "char" (default), "realm" or "account"; a session belongs to one character, so its who is "char".
-- Returns { key, who, label, sessions, ledger, lifetime, elapsed, balance, noJournal (sessions of the scope recorded
-- before 0.9.40), dropped (rows past the cap) }; a day period also carries days = true, period, from, to. Journal
-- rows are the logged-in character's: a realm or account scope has totals only.
function Gold.scope(key, who)
  who = (who == "realm" or who == "account") and who or "char"
  local sc = { key = key, who = who, sessions = {}, ledger = {}, elapsed = 0, noJournal = 0, dropped = 0 }
  local all, cur = Gold.sessions(), current()
  local charGold = (ns.DB and ns.char and ns.char().gold) or {}
  if Gold.isDayScope(key) then
    local now = nowT()
    local p = Gold.period(key, who, now)
    sc.label, sc.days, sc.period, sc.from, sc.to, sc.elapsed = p.label, true, p, p.from, p.to, p.t
    for k, v in pairs(p.ledger) do sc.ledger[k] = v end
    if who == "char" then
      -- journal rows from before the history began have no day row to belong to: a day period lists the rows from
      -- goldSince on (2 s of slack: a row's time is rebuilt from the session's clock)
      local since = ns.DB and ns.charGuid() and num(ns.char().goldSince) or 0
      if since > 0 and p.from then
        sc.from = math.max(p.from, since - 2)
        for _, s in ipairs(all) do
          local s0, s1 = num(s.startedEpoch), s.endedEpoch or now
          if type(s.goldLog) == "table" and #s.goldLog > 0 and s0 < p.to and s1 >= sc.from then sc.sessions[#sc.sessions + 1] = s end
        end
      end
      sc.live = p.to ~= nil and now < p.to
      if sc.live then sc.balance = num(charGold.balance) else sc.balance = p.close end
    end
  elseif key == "all" and who ~= "char" then
    sc.label, sc.lifetime = "All time", true
    for _, blk in ipairs(Gold.whoBlocks(who)) do
      for k, v in pairs(type(blk.gold) == "table" and blk.gold or {}) do
        if k ~= "balance" then sc.ledger[k] = (sc.ledger[k] or 0) + num(v) end
      end
    end
  elseif key == "all" then
    sc.label, sc.lifetime = "All time", true
    for _, s in ipairs(all) do if type(s.goldLog) == "table" and #s.goldLog > 0 then sc.sessions[#sc.sessions + 1] = s end end
    for k, v in pairs(charGold) do sc.ledger[k] = num(v) end
    sc.balance = num(charGold.balance)
  else
    local sess
    if key == "session" then sess = cur; sc.label = "This session"
    elseif key == "previous" then
      for _, s in ipairs(all) do if s ~= cur and s.endedEpoch then sess = s; break end end
      sc.label = "Previous session"
    else
      sess = ns.DB and ns.DB.sessions and ns.DB.sessions[key]
      sc.label = sess and sessionLabel(sess) or "Session"
    end
    if sess then
      sc.sessions[1] = sess
      sc.ledger = sessionLedger(sess)
      sc.elapsed = elapsedOf(sess)
      sc.live = sess == cur
      sc.when = sessionLabel(sess)
      if sess == cur then sc.balance = num(charGold.balance) end
    end
    sc.who = "char"
  end
  for _, s in ipairs(sc.sessions) do
    if type(s.goldLog) ~= "table" then sc.noJournal = sc.noJournal + 1 end
    sc.dropped = sc.dropped + num(s.goldLogDropped)
  end
  local g = sc.ledger
  g.gained, g.spent = num(g.gained), num(g.spent)
  -- income no source claimed is in `gained` only
  -- (a day row carries it itself)
  if not sc.days then
    local known = 0
    for _, k in ipairs(Gold.IN) do if k ~= "unexplained" then known = known + num(g[k]) end end
    g.unexplained = math.max(0, g.gained - known)
  end
  return sc
end

-- every journal row of a scope, oldest first (session by session); a day period keeps the rows inside its days
function Gold.scopeEntries(sc)
  local ix, out = Gold.index(), {}
  for i = #sc.sessions, 1, -1 do
    for _, e in ipairs(Gold.entries(sc.sessions[i], ix)) do
      if not sc.from or (e.t >= sc.from and e.t < sc.to) then out[#out + 1] = e end
    end
  end
  if sc.balance == nil and #out > 0 then sc.balance = out[#out].bal end
  return out
end

-- the biggest contributors of a list of rows: { { name, amount, n }, ... } by amount
local function contributors(rows)
  local by, order = {}, {}
  for _, e in ipairs(rows) do
    local k = e.group
    if k then
      local a = by[k]
      if not a then a = { name = k, amount = 0, n = 0 }; by[k] = a; order[#order + 1] = a end
      a.amount = a.amount + math.abs(e.delta); a.n = a.n + 1
    end
  end
  table.sort(order, function(a, b) if a.amount ~= b.amount then return a.amount > b.amount end return a.name < b.name end)
  return order
end
Gold.contributors = contributors

-- The source ledger of a scope: { rows = { { key, label, dir, amount, n, top } ... }, inTotal, outTotal, away }.
-- Amounts are the ledger's (they hold when journal rows were merged or dropped); a source with no money is left out.
function Gold.sources(sc, entries)
  local bySrc = {}
  for _, e in ipairs(entries) do
    bySrc[e.src] = bySrc[e.src] or {}
    table.insert(bySrc[e.src], e)
  end
  local g, out = sc.ledger, { rows = {}, inTotal = num(sc.ledger.gained), outTotal = num(sc.ledger.spent), away = num(sc.ledger.away) }
  local function add(key, dir, total)
    local amount, list = num(g[key]), bySrc[key] or {}
    if amount == 0 and #list == 0 then return end
    out.rows[#out.rows + 1] = { key = key, label = Gold.LABEL[key], dir = dir, amount = amount, n = #list,
      share = total > 0 and amount / total or 0, top = contributors(list) }
  end
  for _, k in ipairs(Gold.IN) do add(k, 1, out.inTotal) end
  for _, k in ipairs(Gold.OUT) do add(k, -1, out.outTotal) end
  if out.away ~= 0 or bySrc.away then
    out.rows[#out.rows + 1] = { key = "away", label = Gold.LABEL.away, dir = 0, amount = out.away, n = #(bySrc.away or {}), share = 0, top = {} }
  end
  return out
end

-- A session's gold in a few lines, cached until its journal grows: net, perHour (nil under two minutes), topIn and
-- sinks (the three biggest sources each way), bestQuest, bestMob, bestItem (sold to a vendor), flags.
local cache = setmetatable({}, { __mode = "k" })
function Gold.summary(sess)
  if type(sess) ~= "table" then return nil end
  local log = type(sess.goldLog) == "table" and sess.goldLog or nil
  local n, last = log and #log or -1, log and log[#log] or nil
  local c = cache[sess]
  local live = sess == current()
  if c and c.n == n and c.last == last and not live then return c.sum end
  local sum
  if c and c.n == n and c.last == last then sum = c.sum
  else
    local sc = Gold.scope(sess.id)
    local entries = Gold.scopeEntries(sc)
    local src = Gold.sources(sc, entries)
    sum = { journal = log ~= nil, rows = #entries, topIn = {}, sinks = {}, strangers = {}, unexplained = 0, above = 0,
      dropped = num(sess.goldLogDropped), away = num(sc.ledger.away) }
    local ins, outs = {}, {}
    for _, r in ipairs(src.rows) do
      if r.dir > 0 and r.amount > 0 then ins[#ins + 1] = r elseif r.dir < 0 and r.amount > 0 then outs[#outs + 1] = r end
      if r.key == "quests" then sum.bestQuest = r.top[1] elseif r.key == "looted" then sum.bestMob = r.top[1]
      elseif r.key == "sold" then sum.bestItem = r.top[1] end
    end
    table.sort(ins, function(a, b) return a.amount > b.amount end)
    table.sort(outs, function(a, b) return a.amount > b.amount end)
    for i = 1, 3 do sum.topIn[i], sum.sinks[i] = ins[i], outs[i] end
    local seen = {}
    for _, e in ipairs(entries) do
      if e.flag == "stranger" then
        local who = e.group or "?"
        if not seen[who] then seen[who] = true; sum.strangers[#sum.strangers + 1] = who end
        sum.strangerRows = (sum.strangerRows or 0) + 1
      elseif e.flag == "unexplained" then sum.unexplained = sum.unexplained + math.abs(e.delta)
      elseif e.flag == "above vendor price" then sum.above = sum.above + 1 end
    end
    cache[sess] = { n = n, last = last, sum = sum }
  end
  sum.gained, sum.spent = num(sess.gained), num(sess.spent)
  sum.net = sum.gained - sum.spent
  sum.elapsed = elapsedOf(sess)
  sum.perHour = sum.elapsed >= 120 and sum.net / (sum.elapsed / 3600) or nil
  return sum
end

-- ── history, characters, first glance (0.9.44, everbuff-wow-addon #43) ──────────────────────────────────────────
-- Day rows: characters[guid].goldDays[dayKey] = { g, s, o, c, t, n, <non-zero source keys>, away, unexplained },
-- written at the moment of the credit into the logged-in character's block only (Emitter.goldDay calls
-- Gold.dayCredit). g gained, s spent, o the balance before the day's first change, c the closing balance, t active
-- seconds, n purse changes. Income keys sum to g and spend keys to s on every row: unexplained income is credited
-- on the row itself. Week, month, realm and account figures are sums on read and are never stored.
-- The day key is 'YYYYMMDD' of the day's start, from a write-once account-wide base (settings.gold.dayBase): the
-- server's daily reset when the client answers it, else the PC's midnight, marked 'local'.
local DAY = 86400
Gold.DAY = DAY
Gold.DAY_CAP = 400    -- day rows per character; nothing is dropped before the month fold exists (0.9.48)
Gold.STALE_DAYS = 90  -- a character not seen for longer is listed but left out of the default total
Gold.TIP_LINES = 18   -- the tooltip block's line budget
Gold.TIP_ROWS = 8     -- characters listed in the tooltip
Gold.SHORT = { looted = "Looted", quests = "Quests", sold = "Sold to vendors", auctionSales = "Auction sales", mail = "Mail",
  trade = "Trades", unexplained = "Unexplained", repairs = "Repairs", vendor = "Vendors", training = "Training",
  flights = "Flights", auctions = "Auctions", mailSpent = "Postage and COD", tradeSpent = "Trades given", other = "Unexplained" }

local function plainN(v)
  if type(v) ~= "number" or (issecretvalue and issecretvalue(v)) or v ~= v then return nil end
  return v
end
local function plainS(v)
  if type(v) ~= "string" or (issecretvalue and issecretvalue(v)) or v == "" then return nil end
  return v
end
local function realmKey(r) return ((r or ""):gsub("[%s%-']", "")):lower() end

-- settings.gold: created on the first write, never by a read
function Gold.cfg(create)
  local db = ns.DB
  if not (db and type(db.settings) == "table") then return create and {} or nil end
  if type(db.settings.gold) ~= "table" then
    if not create then return nil end
    db.settings.gold = {}
  end
  return db.settings.gold
end

-- seconds until the server's daily reset, or nil when the client does not answer a plain 0 < secs <= 86400
function Gold.readReset()
  local secs
  if C_DateAndTime and type(C_DateAndTime.GetSecondsUntilDailyReset) == "function" then
    local ok, v = pcall(C_DateAndTime.GetSecondsUntilDailyReset)
    secs = ok and plainN(v) or nil
  end
  if not secs and type(GetQuestResetTime) == "function" then
    local ok, v = pcall(GetQuestResetTime)
    secs = ok and plainN(v) or nil
  end
  if secs and secs > 0 and secs <= DAY then return secs end
  return nil
end
-- the reset's second of the day, rounded to the nearest quarter of an hour (a read jitters by a second or two)
function Gold.offsetOf(now, secs) return (math.floor(((now + secs) % DAY) / 900 + 0.5) * 900) % DAY end
local function localOffset(now)
  local ok, t = pcall(date, "*t", now)
  if not ok or type(t) ~= "table" then return 0 end
  local into = (tonumber(t.hour) or 0) * 3600 + (tonumber(t.min) or 0) * 60 + (tonumber(t.sec) or 0)
  return Gold.offsetOf(now, DAY - into)
end
function Gold.baseStored()
  local cfg = Gold.cfg()
  local b = cfg and cfg.dayBase
  if type(b) == "table" and plainN(b.offset) then return b end
  return nil
end
-- one weekly reset, written once: weeks are groups of 7 day keys from it
function Gold.anchorWeek(now)
  local cfg = Gold.cfg(true)
  if plainN(cfg.weekAnchor) then return cfg.weekAnchor end
  local a
  if C_DateAndTime and type(C_DateAndTime.GetWeeklyResetStartTime) == "function" then
    local ok, v = pcall(C_DateAndTime.GetWeeklyResetStartTime)
    v = ok and plainN(v) or nil
    if v and v > 1e9 then a = v end
  end
  if not a and C_DateAndTime and type(C_DateAndTime.GetSecondsUntilWeeklyReset) == "function" then
    local ok, v = pcall(C_DateAndTime.GetSecondsUntilWeeklyReset)
    v = ok and plainN(v) or nil
    if v and v > 0 and v <= 7 * DAY then a = now + v end
  end
  if a then cfg.weekAnchor = math.floor(a) end
  return cfg.weekAnchor
end
-- The day base, resolved on the first credit: the server reset when the client answers it; the PC's midnight when
-- it has not answered within 30 s of the first try (or `force`: a logout with credits still held). nil while it is
-- not known yet: the caller holds its credits in memory.
function Gold.base(now, force)
  local b = Gold.baseStored()
  if b then return b end
  if not (ns.DB and type(ns.DB.settings) == "table") then return nil end
  now = now or nowT()
  local secs = Gold.readReset()
  if secs then b = { kind = "server", offset = Gold.offsetOf(now, secs), since = now }
  else
    Gold._baseWait = Gold._baseWait or GetTime()
    if not force and GetTime() - Gold._baseWait < 30 then return nil end
    b = { kind = "local", offset = localOffset(now), since = now }
  end
  Gold.cfg(true).dayBase = b
  Gold._baseWait = nil
  Gold.anchorWeek(now)
  return b
end
-- A later reading that differs by more than 900 s is recorded, dated (at most 50, the earliest kept); the base and
-- every existing key stay.
function Gold.checkBase(now)
  local b = Gold.baseStored()
  if not b then return end
  now = now or nowT()
  Gold.anchorWeek(now)
  local secs = Gold.readReset()
  if not secs then return end
  local off = Gold.offsetOf(now, secs)
  local ch = type(b.changes) == "table" and b.changes or {}
  local last = (ch[#ch] and plainN(ch[#ch].offset)) or b.offset
  local d = math.abs(off - last); d = math.min(d, DAY - d)
  if d > 900 and #ch < 50 then ch[#ch + 1] = { at = now, offset = off }; b.changes = ch end
end

function Gold.dayStart(t, base) return math.floor((t - base.offset) / DAY) * DAY + base.offset end
function Gold.dayKey(t, base) return date("!%Y%m%d", Gold.dayStart(t, base)) end
-- days from 1970-01-01 to a civil date
local function civilDays(y, m, d)
  if m <= 2 then y = y - 1 end
  local era = math.floor(y / 400)
  local yoe = y - era * 400
  local doy = math.floor((153 * ((m + 9) % 12) + 2) / 5) + d - 1
  return era * 146097 + yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy - 719468
end
-- the epoch a day key starts at
function Gold.keyStart(key, base)
  local y, m, d = tostring(key):match("^(%d%d%d%d)(%d%d)(%d%d)$")
  if not y then return nil end
  return civilDays(tonumber(y), tonumber(m), tonumber(d)) * DAY + base.offset
end
-- the start of the week a day belongs to: 7 day keys from the stored anchor, else from a Monday of the day base
function Gold.weekStart(dayStart, base)
  local cfg = Gold.cfg()
  local anchor = cfg and plainN(cfg.weekAnchor)
  local a = anchor and Gold.dayStart(anchor + 1800, base) or (4 * DAY + base.offset)
  return a + math.floor((dayStart - a) / (7 * DAY)) * 7 * DAY
end
local function noZero(s) return (s:gsub(" 0", " ")) end
function Gold.fmtDate(t) return noZero(date("%b %d", t or 0)) end
-- "Nov 18" for a day key (the middle of the day, so the PC's time zone cannot move it to a neighbour)
function Gold.dayLabel(key, base)
  local s = Gold.keyStart(key, base)
  return s and Gold.fmtDate(s + DAY / 2) or tostring(key)
end
function Gold.fmtAge(seen, now)
  seen = plainN(seen)
  if not seen then return "before the update" end
  local d = math.floor(((now or nowT()) - seen) / DAY)
  if d <= 0 then return "today" elseif d == 1 then return "yesterday" elseif d <= 30 then return d .. " d ago" end
  return Gold.fmtDate(seen)
end

local function applyDay(c, base, key, n, bal, at)
  if key == "awayIn" or key == "awayOut" then return end
  c.goldDays = type(c.goldDays) == "table" and c.goldDays or {}
  local dk = Gold.dayKey(at, base)
  local r = c.goldDays[dk]
  if type(r) ~= "table" then
    r = { g = 0, s = 0, t = 0, n = 0 }
    c.goldDays[dk] = r
    c.goldSince = plainN(c.goldSince) or at
  end
  bal = plainN(bal)
  local delta
  if key == "gained" then r.g = r.g + n; delta = n
  elseif key == "spent" then r.s = r.s + n; delta = -n
  elseif key == "away" then
    local v = (r.away or 0) + n
    r.away = v ~= 0 and v or nil   -- (a 0 taken back leaves no key, like a source)
    delta = n
  else
    local v = (r[key] or 0) + n
    r[key] = v ~= 0 and v or nil
  end
  if delta then
    r.n = r.n + 1
    if bal then
      if r.o == nil then r.o = bal - delta end
      r.c = bal
    end
  end
end
-- One credit on the day row of the logged-in character. key: gained, spent, away (signed), a ledger source or
-- unexplained; bal: the purse after the change; at: server time of the change (now when nil). While the day base is
-- not known the credit is held in memory and written once it is.
function Gold.dayCredit(key, n, bal, at)
  if not (ns.DB and ns.charGuid()) then return end
  n = plainN(n)
  if not n then return end
  n = n < 0 and -math.floor(-n) or math.floor(n)
  at = plainN(at) or nowT()
  local base = Gold.base()
  if not base then
    Gold._held = Gold._held or {}
    Gold._held[#Gold._held + 1] = { key, n, bal, at }
    if not Gold._flushTimer and C_Timer and type(C_Timer.After) == "function" then
      Gold._flushTimer = true
      C_Timer.After(31, function() Gold._flushTimer = nil; Gold.flush() end)
    end
    return
  end
  if Gold._held then Gold.flush() end
  applyDay(ns.char(), base, key, n, bal, at)
end
function Gold.flush(force)
  local held = Gold._held
  if not held or not (ns.DB and ns.charGuid()) then return end
  local base = Gold.base(nil, force)
  if not base then return end
  Gold._held = nil
  local c = ns.char()
  for _, h in ipairs(held) do applyDay(c, base, h[1], h[2], h[3], h[4]) end
end
-- active seconds: every 10 s the time since the last tick (capped at the tick length) goes to today's row
function Gold.tick()
  local now = GetTime()
  local last = Gold._tickAt
  Gold._tickAt = now
  if not last or not (ns.DB and ns.charGuid()) then return end
  local add = math.floor(math.min(10, now - last) + 0.5)
  if add <= 0 then return end
  local base = Gold.baseStored()
  if not base then return end
  local c = ns.char()
  local at = nowT()
  c.goldDays = type(c.goldDays) == "table" and c.goldDays or {}
  local dk = Gold.dayKey(at, base)
  local r = c.goldDays[dk]
  if type(r) ~= "table" then
    local bal = type(c.gold) == "table" and plainN(c.gold.balance) or nil
    r = { g = 0, s = 0, t = 0, n = 0, o = bal, c = bal }
    c.goldDays[dk] = r
    c.goldSince = plainN(c.goldSince) or at
  end
  r.t = (plainN(r.t) or 0) + add
end

-- Roster facts on the logged-in character's block: name and realm refreshed, surname, class, faction, level, seen.
-- Returns false while the GUID is not known.
function Gold.noteChar(level)
  if not (ns.DB and ns.charGuid()) then return false end
  local c = ns.char()
  if not Gold._seenRead then Gold._seenRead = true; Gold._seenBefore = plainN(c.seen) end
  -- every read is tested and protected: a function the client lacks or blocks leaves the stored value as it is
  local name, realm, class, faction, lvl
  if type(UnitNameUnmodified) == "function" then local ok, v = pcall(UnitNameUnmodified, "player"); name = ok and plainS(v) or nil end
  if not name and type(UnitName) == "function" then local ok, v = pcall(UnitName, "player"); name = ok and plainS(v) or nil end
  if type(GetRealmName) == "function" then local ok, v = pcall(GetRealmName); realm = ok and plainS(v) or nil end
  if type(UnitClass) == "function" then local ok, _, v = pcall(UnitClass, "player"); class = ok and plainS(v) or nil end
  if type(UnitFactionGroup) == "function" then local ok, v = pcall(UnitFactionGroup, "player"); faction = ok and plainS(v) or nil end
  if type(UnitLevel) == "function" then local ok, v = pcall(UnitLevel, "player"); lvl = ok and plainN(v) or nil end
  local sur
  if ns.surname then local ok, v = pcall(ns.surname); sur = ok and plainS(v) or nil end
  c.name, c.realm = name or c.name, realm or c.realm
  c.surname = sur or c.surname
  c.class, c.faction = class or c.class, faction or c.faction
  c.level = plainN(level) or lvl or c.level
  c.seen = nowT()
  return true
end
-- when this character was last seen before this load (the gap an away change covers)
function Gold.seenBefore()
  if Gold._seenRead then return Gold._seenBefore end
  if not (ns.DB and ns.charGuid()) then return nil end
  return plainN(ns.char().seen)
end

-- Gold.onChange(fn): fn runs after every purse change is booked (the open tooltip and the open pane follow it)
Gold._subs = {}
function Gold.onChange(fn) if type(fn) == "function" then Gold._subs[#Gold._subs + 1] = fn end end
function Gold.fire() for _, fn in ipairs(Gold._subs) do pcall(fn) end end

-- A realm name for a list column: brackets dropped; of a long name in parts ("Group - Realm") the last part, which
-- tells two realms apart; at most 18 characters. The raw string stays in the row's tooltip. (The real WoW Forever
-- realm string is not known yet, #43 probe 2: a short name is shown as it is.)
function Gold.realmLabel(realm)
  realm = plainS(realm)
  if not realm then return "" end
  local s = realm:gsub("%s*%b()", ""):gsub("%s*%b[]", ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  if s == "" then s = realm end
  if #s > 18 then
    local tail = s:match("%s%-%s+([^%-]-)$") or s:match(":%s+([^:]-)$")
    if tail and #tail >= 3 then s = tail end
  end
  if #s > 18 then
    local cut = s:sub(1, 18):match("^(.*%S)%s+%S*$") or s:sub(1, 18)
    s = cut .. "..."
  end
  return s
end

-- Every character the save file knows, for a filter: "all", "realm" (the logged-in character's), "faction", or
-- "realmFaction". Rows { guid, block, name, surname, label, realm, realmLabel, class, faction, level, balance, seen,
-- me, facts (false: not seen since the update), hidden, stale, counted, today, d7 }, by balance. A block without a
-- name is skipped. The total sums the counted rows: not hidden, and seen within 90 days unless `withStale`.
function Gold.roster(filter, withStale, now)
  filter = filter or "all"
  now = now or nowT()
  local out = { rows = {}, filter = filter, total = 0, count = 0, hidden = 0, stale = 0, needLogin = 0, unknownAge = 0 }
  local db = ns.DB
  if not (db and type(db.characters) == "table") then return out end
  local meGuid = ns.charGuid()
  local me = meGuid and db.characters[meGuid] or nil
  local cfg = Gold.cfg()
  local hidden = cfg and type(cfg.hidden) == "table" and cfg.hidden or {}
  local base = Gold.baseStored()
  local todayK = base and Gold.dayKey(now, base) or nil
  local weekK = base and Gold.dayKey(now - 6 * DAY, base) or nil
  local byLabel = {}
  for guid, c in pairs(db.characters) do
    if type(c) == "table" and type(c.name) == "string" and c.name ~= "" then
      local ok = true
      if filter == "realm" or filter == "realmFaction" then ok = me ~= nil and realmKey(c.realm) == realmKey(me.realm) end
      if ok and (filter == "faction" or filter == "realmFaction") then ok = me ~= nil and me.faction ~= nil and c.faction == me.faction end
      if ok or guid == meGuid then
        local row = { guid = guid, block = c, name = c.name, surname = type(c.surname) == "string" and c.surname or nil,
          realm = type(c.realm) == "string" and c.realm or nil, class = type(c.class) == "string" and c.class or nil,
          faction = type(c.faction) == "string" and c.faction or nil, level = plainN(c.level),
          balance = num(type(c.gold) == "table" and c.gold.balance), seen = plainN(c.seen), me = guid == meGuid,
          today = 0, d7 = 0 }
        row.label = row.name .. (row.surname and (" " .. row.surname) or "")
        row.realmLabel = Gold.realmLabel(row.realm)
        row.facts = row.class ~= nil and row.seen ~= nil
        row.hidden = hidden[guid] == true
        row.stale = (not row.me) and row.seen ~= nil and (now - row.seen) > Gold.STALE_DAYS * DAY
        row.counted = not row.hidden and (withStale or not row.stale)
        if todayK and type(c.goldDays) == "table" then
          for k, r in pairs(c.goldDays) do
            if type(r) == "table" and type(k) == "string" and k >= weekK and k <= todayK then
              local net = num(r.g) - num(r.s)
              row.d7 = row.d7 + net
              if k == todayK then row.today = net end
            end
          end
        end
        byLabel[row.label] = (byLabel[row.label] or 0) + 1
        out.rows[#out.rows + 1] = row
        if row.hidden then out.hidden = out.hidden + 1
        elseif row.stale then out.stale = out.stale + 1 end
        if not row.facts then out.needLogin = out.needLogin + 1 end
        if row.counted then
          out.total = out.total + row.balance
          out.count = out.count + 1
          if row.seen then out.oldest = math.min(out.oldest or row.seen, row.seen) else out.unknownAge = out.unknownAge + 1 end
        end
      end
    end
  end
  -- two rows never show the same name: the realm goes beside a name that is not unique (the short label, or the
  -- whole realm string when the short labels are the same too)
  local again = {}
  for _, row in ipairs(out.rows) do
    if byLabel[row.label] > 1 and row.realm then
      row.dup = row.label
      row.label = row.label .. " (" .. (row.realmLabel ~= "" and row.realmLabel or row.realm) .. ")"
      again[row.label] = (again[row.label] or 0) + 1
    end
  end
  for _, row in ipairs(out.rows) do
    if row.dup and again[row.label] > 1 then row.label = row.dup .. " (" .. row.realm .. ")" end
  end
  table.sort(out.rows, function(a, b)
    if a.balance ~= b.balance then return a.balance > b.balance end
    if a.label ~= b.label then return a.label < b.label end
    return tostring(a.guid) < tostring(b.guid)
  end)
  return out
end
-- "4 characters, oldest balance from Nov 6"
function Gold.rosterLine(ro)
  local s = ("%d character%s"):format(ro.count, ro.count == 1 and "" or "s")
  if ro.oldest then s = s .. ", oldest balance from " .. Gold.fmtDate(ro.oldest) end
  return s
end

local DAYKEYS = { today = "Today", yesterday = "Yesterday", week = "This week", month = "This month",
  last7 = "Last 7 days", last30 = "Last 30 days" }
function Gold.isDayScope(key)
  return type(key) == "string" and (DAYKEYS[key] ~= nil or key:match("^day:%d%d%d%d%d%d%d%d$") ~= nil)
end
-- the day starts a period covers: from (inclusive), to (exclusive), and its label
function Gold.range(key, base, now)
  local d0 = Gold.dayStart(now, base)
  if key == "today" then return d0, d0 + DAY, DAYKEYS.today
  elseif key == "yesterday" then return d0 - DAY, d0, DAYKEYS.yesterday
  elseif key == "week" then local w = Gold.weekStart(d0, base); return w, w + 7 * DAY, DAYKEYS.week
  elseif key == "last7" then return d0 - 6 * DAY, d0 + DAY, DAYKEYS.last7
  elseif key == "last30" then return d0 - 29 * DAY, d0 + DAY, DAYKEYS.last30
  elseif key == "month" then
    local k = Gold.dayKey(now, base)
    local y, m = tonumber(k:sub(1, 4)), tonumber(k:sub(5, 6))
    local ny, nm = y, m + 1
    if nm > 12 then ny, nm = y + 1, 1 end
    return Gold.keyStart(("%04d%02d01"):format(y, m), base), Gold.keyStart(("%04d%02d01"):format(ny, nm), base), DAYKEYS.month
  end
  local dk = tostring(key):match("^day:(%d+)$")
  local s = dk and Gold.keyStart(dk, base)
  if s then return s, s + DAY, Gold.dayLabel(dk, base) end
  return nil
end
-- the character blocks a "who" means: "char" (the logged-in one), "realm" or "account" (never a hidden one)
local function whoBlocks(who, now)
  local out = {}
  if who == "realm" or who == "account" then
    for _, row in ipairs(Gold.roster(who == "realm" and "realm" or "all", true, now).rows) do
      if not row.hidden then out[#out + 1] = row.block end
    end
  elseif ns.DB and ns.charGuid() then out[1] = ns.char() end
  return out
end
Gold.whoBlocks = whoBlocks
-- A period summed from day rows: Gold.period(key, who) with key today, yesterday, week, month, last7, last30,
-- "day:YYYYMMDD" or "history" (every row); who "char", "realm" or "account". Returns { key, who, label, from, to,
-- ledger { gained, spent, away, unexplained, <sources> }, t, n, chars, gaps (characters with a change not seen on
-- this PC in the period), days[] newest first { key, start, g, s, t, n, away, o, c, src {} }, open, close }.
function Gold.period(key, who, now)
  who = who or "char"
  now = now or nowT()
  local p = { key = key, who = who, label = DAYKEYS[key] or "History", ledger = { gained = 0, spent = 0, away = 0 },
    t = 0, n = 0, chars = 0, gaps = 0, days = {} }
  local base = Gold.baseStored()
  if not base then return p end
  local fromK, toK
  if key ~= "history" then
    local from, to, label = Gold.range(key, base, now)
    if not from then return p end
    p.from, p.to, p.label = from, to, label
    fromK, toK = Gold.dayKey(from, base), Gold.dayKey(to - 1, base)
  end
  local byDay = {}
  local blocks = whoBlocks(who, now)
  for _, blk in ipairs(blocks) do
    local had, gap = false, false
    for k, r in pairs(type(blk.goldDays) == "table" and blk.goldDays or {}) do
      if type(k) == "string" and type(r) == "table" and (not fromK or (k >= fromK and k <= toK)) then
        had = true
        local d = byDay[k]
        if not d then
          d = { key = k, start = Gold.keyStart(k, base), g = 0, s = 0, t = 0, n = 0, away = 0, src = {} }
          byDay[k] = d; p.days[#p.days + 1] = d
        end
        d.g, d.s, d.t, d.n, d.away = d.g + num(r.g), d.s + num(r.s), d.t + num(r.t), d.n + num(r.n), d.away + num(r.away)
        if num(r.away) ~= 0 then gap = true end
        if #blocks == 1 then d.o, d.c = plainN(r.o), plainN(r.c) end
        for sk, v in pairs(r) do
          if (IS_IN[sk] or IS_OUT[sk]) and type(v) == "number" then
            d.src[sk] = (d.src[sk] or 0) + v
            p.ledger[sk] = (p.ledger[sk] or 0) + v
          end
        end
      end
    end
    if had then p.chars = p.chars + 1 end
    if gap then p.gaps = p.gaps + 1 end
  end
  table.sort(p.days, function(a, b) return a.key > b.key end)
  for _, d in ipairs(p.days) do
    p.ledger.gained, p.ledger.spent, p.ledger.away = p.ledger.gained + d.g, p.ledger.spent + d.s, p.ledger.away + d.away
    p.t, p.n = p.t + d.t, p.n + d.n
  end
  p.ledger.unexplained = p.ledger.unexplained or 0
  if #p.days > 0 then p.close, p.open = p.days[1].c, p.days[#p.days].o end
  return p
end
-- the biggest source of a day's `src`, by amount: key, amount
function Gold.topSource(src)
  local bk, bv
  for _, list in ipairs({ Gold.IN, Gold.OUT }) do
    for _, k in ipairs(list) do
      local v = num(src[k])
      if v > 0 and (not bv or v > bv) then bk, bv = k, v end
    end
  end
  return bk, bv
end

-- The one resolver behind every surface: Gold.metric(id, who, when).
--   id    "balance", "earned", "spent", "net", "away", "played" (active seconds of a day period, the length of a
--         session), "perHour" (net over that time, nil under 5 minutes), or a ledger source key
--   who   "char" (default), "realm", "account"
--   when  a day period of Gold.period, "session", "previous", "all" or a session id; default "today"
function Gold.metric(id, who, when)
  who, when = who or "char", when or "today"
  if id == "balance" then
    if who == "char" then
      local g = ns.DB and ns.charGuid() and ns.char().gold
      return num(type(g) == "table" and g.balance)
    end
    return Gold.roster(who == "realm" and "realm" or "all").total
  end
  local ledger, t
  if Gold.isDayScope(when) then
    local p = Gold.period(when, who)
    ledger, t = p.ledger, p.t
  else
    local sc = Gold.scope(when, who)
    ledger, t = sc.ledger, sc.elapsed
  end
  if id == "earned" then return num(ledger.gained)
  elseif id == "spent" then return num(ledger.spent)
  elseif id == "net" then return num(ledger.gained) - num(ledger.spent)
  elseif id == "played" then return num(t)
  elseif id == "perHour" then
    if num(t) < 300 then return nil end
    return (num(ledger.gained) - num(ledger.spent)) * 3600 / t
  end
  return num(ledger[id])
end

-- today's journal rows that carry a flag: unexplained changes, and mail or trades with a stranger
function Gold.flagsToday()
  local out = { unexplained = 0, strangers = 0 }
  for _, e in ipairs(Gold.scopeEntries(Gold.scope("today"))) do
    if e.flag == "unexplained" then out.unexplained = out.unexplained + 1
    elseif e.flag == "stranger" then out.strangers = out.strangers + 1 end
  end
  return out
end

-- The shared gold block of a hover tooltip. Gold.tipLines(opts) builds it as { { left, right, color, head } ... }
-- inside the line budget (opts.budget, 18): the current character is always listed, first, and the roster gives way
-- before anything else does. Gold.tooltip(tip, opts) adds the lines to an open tooltip and returns how many.
function Gold.tipLines(opts)
  opts = opts or {}
  local budget, limit = opts.budget or Gold.TIP_LINES, opts.limit or Gold.TIP_ROWS
  local L = {}
  local function add(left, right, color, head) L[#L + 1] = { left = left, right = right, color = color, head = head } end
  if not (ns.DB and ns.charGuid()) then return L end
  local now = nowT()
  add("THIS CHARACTER", nil, C.dim, true)
  add("Balance", fmtMoney(Gold.metric("balance")), C.gold)
  local p = Gold.period("today", "char", now)
  local g, s = p.ledger.gained, p.ledger.spent
  add("Today", ("%s   (in %s  ·  out %s)"):format(signed(g - s), fmtMoney(g), fmtMoney(s)), (g - s) < 0 and C.red or C.ink)
  local cur = current()
  if cur then add("This session", signed(num(cur.gained) - num(cur.spent))) end
  local ins, outs = {}, {}
  for _, k in ipairs(Gold.IN) do if num(p.ledger[k]) > 0 then ins[#ins + 1] = { k, p.ledger[k] } end end
  for _, k in ipairs(Gold.OUT) do if num(p.ledger[k]) > 0 then outs[#outs + 1] = { k, p.ledger[k] } end end
  local function top(list)
    table.sort(list, function(a, b) if a[2] ~= b[2] then return a[2] > b[2] end return a[1] < b[1] end)
    local parts = {}
    for i = 1, math.min(3, #list) do parts[#parts + 1] = Gold.SHORT[list[i][1]] .. " " .. fmtMoney(list[i][2]) end
    return table.concat(parts, "  ·  ")
  end
  if #ins + #outs > 0 then
    add("TOP TODAY", nil, C.dim, true)
    if #ins > 0 then add(top(ins)) end
    if #outs > 0 then add(top(outs), nil, C.dim) end
  end
  local tail = {}
  local okF, fl = pcall(Gold.flagsToday)
  if okF and fl.unexplained > 0 then
    tail[#tail + 1] = { left = ("%d unexplained change%s today"):format(fl.unexplained, fl.unexplained == 1 and "" or "s"), color = C.red }
  end
  if okF and fl.strangers > 0 then
    tail[#tail + 1] = { left = ("%d mail or trade row%s with a stranger today"):format(fl.strangers, fl.strangers == 1 and "" or "s"), color = C.red }
  end
  local cfg = Gold.cfg()
  local filter = (cfg and cfg.filter) or "all"
  local ro = Gold.roster(filter, false, now)
  local shown = {}
  for _, row in ipairs(ro.rows) do if row.me then shown[1] = row end end
  for _, row in ipairs(ro.rows) do if row.counted and not row.me then shown[#shown + 1] = row end end
  if #shown > 1 then
    local HEAD = { all = "ACCOUNT", realm = "THIS REALM", faction = "THIS FACTION", realmFaction = "THIS REALM AND FACTION" }
    -- the header and the total stay; the roster takes what the budget leaves, one line saying how many more
    local room = budget - #L - #tail - 2
    local n = math.max(1, math.min(limit, #shown, room))
    if n < #shown and n == room then n = math.max(1, n - 1) end
    add(("%s  ·  %d characters"):format(HEAD[filter] or HEAD.all, #shown), nil, C.dim, true)
    for i = 1, n do
      local row = shown[i]
      local left = (row.me and "> " or "   ") .. row.label .. (row.level and ("  " .. row.level) or "")
      local right = fmtMoney(row.balance)
      if not row.me then right = right .. "   seen " .. Gold.fmtAge(row.seen, now) end
      local col = row.facts and C.ink or C.dim
      if row.class and UI.ClassColor then col = { UI.ClassColor(row.class) } end
      add(left, right, col)
    end
    if n < #shown then add(("and %d more"):format(#shown - n), nil, C.dim) end
    add("Total", fmtMoney(ro.total) .. (ro.oldest and ("   oldest balance from " .. Gold.fmtDate(ro.oldest)) or ""), C.gold)
  end
  for _, t in ipairs(tail) do L[#L + 1] = t end
  while #L > budget do table.remove(L) end
  return L
end
function Gold.tooltip(tip, opts)
  if not tip then return 0 end
  local cfg = Gold.cfg()
  if cfg and cfg.tips == false then return 0 end
  local ok, L = pcall(Gold.tipLines, opts)
  if not ok or type(L) ~= "table" then return 0 end
  for _, l in ipairs(L) do
    local col = l.color or C.ink
    local r, g, b = col[1] or 1, col[2] or 1, col[3] or 1
    if l.right and tip.AddDoubleLine then tip:AddDoubleLine(l.left, l.right, r, g, b, r, g, b)
    else tip:AddLine(l.right and (l.left .. "   " .. l.right) or l.left, r, g, b) end
  end
  return #L
end

-- /eb gold and /eb gold chars: direct replies to a typed command; nothing else about gold goes to chat. Returns
-- true (the argument was a gold command).
function Gold.slash(sub)
  sub = tostring(sub or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if not (ns.DB and ns.charGuid()) then ns.msg("gold: the character is not known yet, try again in a moment"); return true end
  local now = nowT()
  local ro = Gold.roster((Gold.cfg() or {}).filter or "all", false, now)
  if sub == "" then
    local line = "gold: " .. fmtMoney(Gold.metric("balance"))
    if ro.count > 1 then line = line .. ("  ·  all characters %s (%s)"):format(fmtMoney(ro.total), Gold.rosterLine(ro)) end
    ns.msg(line)
    local p = Gold.period("today", "char", now)
    ns.msg(("today: %s (in %s, out %s)"):format(signed(p.ledger.gained - p.ledger.spent), fmtMoney(p.ledger.gained), fmtMoney(p.ledger.spent)))
    local sum = Gold.summary(current())
    if sum then
      ns.msg(("this session: %s"):format(signed(sum.net)))
      ns.msg(sum.perHour and ("per hour: %s net over this session"):format(signed(sum.perHour)) or "per hour: after 2 minutes of this session")
    else
      ns.msg("this session: no session yet"); ns.msg("per hour: no session yet")
    end
  elseif sub == "chars" or sub == "characters" then
    for _, row in ipairs(ro.rows) do
      local tag = row.hidden and "hidden from totals" or (row.stale and "not in the total, not seen in 90 days") or nil
      ns.msg(("%s%s%s  ·  %s  ·  %s%s"):format(row.me and "> " or "", row.label, row.level and (" " .. row.level) or "",
        fmtMoney(row.balance), row.me and "you" or ("seen " .. Gold.fmtAge(row.seen, now)), tag and ("  ·  " .. tag) or ""))
    end
    ns.msg(("total: %s  ·  %s"):format(fmtMoney(ro.total), Gold.rosterLine(ro)))
  else
    ns.msg("gold commands: /eb gold · /eb gold chars")
  end
  return true
end

-- the model's own events: roster facts at login, level-up and logout; the day base checked at login
do
  local gf = CreateFrame("Frame")
  ns.eventFrames = ns.eventFrames or {}
  ns.eventFrames[#ns.eventFrames + 1] = gf
  for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "PLAYER_LOGOUT" }) do pcall(gf.RegisterEvent, gf, e) end
  local function note(tries)
    if Gold.noteChar() then pcall(Gold.checkBase); return end
    if tries > 0 and C_Timer and type(C_Timer.After) == "function" then C_Timer.After(1, function() note(tries - 1) end) end
  end
  gf:SetScript("OnEvent", function(_, event, a1)
    if not ns.DB then return end
    if event == "PLAYER_ENTERING_WORLD" then note(5)
    elseif event == "PLAYER_LEVEL_UP" then Gold.noteChar(a1)
    elseif event == "PLAYER_LOGOUT" then Gold.noteChar(); Gold.flush(true) end
  end)
  if C_Timer and type(C_Timer.NewTicker) == "function" then pcall(C_Timer.NewTicker, 10, function() Gold.tick() end) end
end

-- ── the Gold pane ───────────────────────────────────────────────────────────────────────────────────────────────
local CARDS = {
  { key = "cBalance", label = "BALANCE" },
  { key = "cIn",      label = "EARNED" },
  { key = "cOut",     label = "SPENT" },
  { key = "cNet",     label = "NET" },
  { key = "cRate",    label = "NET PER HOUR" },
}
-- the toolbar: three periods one click away, the rest under "More"; who the numbers are of; what the list shows
local QUICK = { { "today", "Today" }, { "week", "This week" }, { "all", "All time" } }
local MORE = { { "session", "This session" }, { "yesterday", "Yesterday" }, { "month", "This month" }, { "last30", "Last 30 days" } }
local WHO = { { "char", "This character" }, { "realm", "This realm" }, { "account", "Account" } }
local VIEWS = { { "sources", "Sources" }, { "journal", "Journal" }, { "days", "Days" }, { "chars", "Characters" } }
local FILTERS = { { "all", "All characters" }, { "realm", "This realm" }, { "faction", "This faction" }, { "realmFaction", "This realm and faction" } }
Gold.QUICK, Gold.MORE, Gold.WHO, Gold.VIEWS, Gold.FILTERS = QUICK, MORE, WHO, VIEWS, FILTERS
local function labelOf(list, key) for _, e in ipairs(list) do if e[1] == key then return e[2] end end end
local NARROW = 760   -- a list narrower than this leaves the Balance column out of the journal
local WIDE = 980     -- Days and Characters show their optional columns from this width on
Gold.MAX_ROWS = 500  -- journal rows listed at once (a row is a frame): the newest, the caption says how many more
Gold.MORE_SESSIONS = 8   -- earlier sessions offered under "More"
local STRIP_DAYS = 30

local function textW(fs)
  local ok, w = pcall(fs.GetStringWidth, fs)
  return (ok and type(w) == "number") and w or 0
end
local function lineH(fs, dflt)
  local ok, h = pcall(fs.GetStringHeight, fs)
  h = ok and tonumber(h) or 0
  return math.ceil(math.max(h, dflt))
end
local function oneLine(fs)
  if fs.SetWordWrap then fs:SetWordWrap(false) end
  if fs.SetMaxLines then fs:SetMaxLines(1) end
  return fs
end
-- the widths of one row of cards `avail` px wide: equal when every card fits; else each card gets what it needs and
-- the rest is shared equally. The widths add up to `avail`.
local function rowWidths(needs, avail)
  local n = #needs
  local each = math.floor(avail / n)
  local fits, total = true, 0
  for _, nd in ipairs(needs) do total = total + nd; if nd > each then fits = false end end
  local out = {}
  if fits or total > avail then
    for i = 1, n do out[i] = each end
  else
    local extra = math.floor((avail - total) / n)
    for i = 1, n do out[i] = math.ceil(needs[i]) + extra end
  end
  local sum = 0
  for i = 1, n - 1 do sum = sum + out[i] end
  out[n] = avail - sum
  return out
end
local function cardNeed(p) return math.max(textW(p.title), textW(p.value)) + 2 * PAD end
local function showTable(t, on)
  if on then t.sf:Show() else t.header:Hide(); t.sf:Hide(); t.empty:Hide() end
end
local function stripH() return (UI.STRIP_H or 62) end

local function relayout(c, w, h)
  w, h = tonumber(w) or 0, tonumber(h) or 0
  if w <= 2 * PAD + 10 then return end
  c.layoutW, c.layoutH = w, h
  -- the toolbar: the search box takes what the buttons leave, between 90 and 170 px (at the narrowest window the
  -- periods, who and the view need the rest); under 150 px its hint is one word
  do
    local function bw(b) local ok, v = pcall(b.GetWidth, b); return ok and tonumber(v) or 0 end
    local used = SP.S
    for _, b in ipairs(c.scopeBtns) do used = used + bw(b) + SP.XS end
    used = used + bw(c.moreBtn) + SP.M + bw(c.whoBtn) + SP.XS + bw(c.viewBtn) + SP.S
    local sw = math.max(90, math.min(170, math.floor(w - UI.SCROLLBAR - used)))
    if sw ~= c.searchW then
      c.searchW = sw
      c.search:SetWidth(sw)
      c.search:SetPlaceholder(sw >= 150 and "search quest, item, player" or "search")
    end
  end
  -- cards: five in a row when each holds its value, else three over two; a row fills the width
  local need, needs = 0, {}
  for i, d in ipairs(CARDS) do needs[i] = cardNeed(c[d.key]); need = math.max(need, needs[i]) end
  local total = 0
  for _, nd in ipairs(needs) do total = total + nd end
  local rows = (total <= w - 4 * GAP) and { { 1, 2, 3, 4, 5 } } or { { 1, 2, 3 }, { 4, 5 } }
  c.cardRows = #rows
  local y = -(ROW_H + GAP)
  for _, r in ipairs(rows) do
    local rn = {}
    for i, idx in ipairs(r) do rn[i] = needs[idx] end
    local widths = rowWidths(rn, w - (#r - 1) * GAP)
    local tallest, x = 0, 0
    for i, idx in ipairs(r) do
      local p = c[CARDS[idx].key]
      p:ClearAllPoints(); p:SetPoint("TOPLEFT", c, "TOPLEFT", x, y); p:SetWidth(widths[i])
      tallest = math.max(tallest, PAD + lineH(p.title, 13) + SP.XS + lineH(p.value, 18) + PAD)
      x = x + widths[i] + GAP
    end
    for _, idx in ipairs(r) do c[CARDS[idx].key]:SetHeight(tallest) end
    y = y - tallest - GAP
  end
  -- the status line (only when it says something), the caption line and its buttons, then the list in the rest
  if (c.statusText or "") ~= "" then
    c.statusRow:ClearAllPoints()
    c.statusRow:SetPoint("TOPLEFT", c, "TOPLEFT", 0, y + SP.XS); c.statusRow:SetPoint("TOPRIGHT", c, "TOPRIGHT", -UI.SCROLLBAR, y + SP.XS)
    c.statusRow:Show()
    y = y - ROW_H
  else c.statusRow:Hide() end
  c.capRow:ClearAllPoints()
  c.capRow:SetPoint("TOPLEFT", c, "TOPLEFT", 0, y); c.capRow:SetPoint("TOPRIGHT", c, "TOPRIGHT", -UI.SCROLLBAR, y)
  y = y - ROW_H - SP.S
  c.body:ClearAllPoints()
  c.body:SetPoint("TOPLEFT", c, "TOPLEFT", 0, y); c.body:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 0, 0)
  -- the strip of the Days view: as wide as the list, one slot per day
  local st = c.dayStrip
  if st then
    local sw = w - UI.SCROLLBAR - 2 * SP.S
    st:ClearAllPoints(); st:SetPoint("TOPLEFT", c.body, "TOPLEFT", SP.S, 0); st:SetWidth(sw)
    st.slot = sw / STRIP_DAYS
    st.barW = math.max(2, math.min(40, math.floor(st.slot - 2)))
    if st.values and UI.renderStrip then UI.renderStrip(st, st.values, st.fmt, st.signed) end
  end
  local listW = w - UI.SCROLLBAR
  local narrow, wide = listW < NARROW, listW >= WIDE
  if narrow ~= c.narrow or wide ~= c.wide then c.narrow, c.wide = narrow, wide; if c.refresh then c.refresh() end end
end

-- the search text of a journal row
local function hay(e)
  return ((Gold.WORD[e.src] or "") .. " " .. (Gold.LABEL[e.src] or "") .. " " .. (e.detail or "") .. " " .. (e.zone or "") .. " " .. (e.flag or "")):lower()
end
local function tradeSide(tip, word, list, money)
  local parts = {}
  if num(money) > 0 then parts[#parts + 1] = fmtMoney(money) end
  for _, s in ipairs(list or {}) do
    local id, n = tostring(s):match("^(%d+):(%d+)$")
    parts[#parts + 1] = (itemName(id) or "an item") .. " x" .. (n or 1)
  end
  tip:AddLine(word .. ": " .. (#parts > 0 and table.concat(parts, ", ") or "nothing"), C.dim[1], C.dim[2], C.dim[3], true)
end
local function journalTip(row, e, tip)
  if not e or e.ebSection then return end
  tip:AddLine(("%s  %s"):format(Gold.LABEL[e.src] or e.src, signed(e.delta)), 1, 1, 1)
  if (e.detail or "") ~= "" then tip:AddLine(e.detail, C.dim[1], C.dim[2], C.dim[3], true) end
  if e.vendorPrice then
    tip:AddLine(("Vendor price %s, paid %s"):format(fmtMoney(e.vendorPrice), fmtMoney(e.delta)), C.dim[1], C.dim[2], C.dim[3], true)
  end
  local tr = e.tradeRec
  if tr then tradeSide(tip, "You gave", tr.gave, tr.gaveMoney); tradeSide(tip, "You got", tr.got, tr.gotMoney) end
  local m = e.loot and e.loot.mail
  if type(m) == "table" and m.subject then tip:AddLine("Mail: " .. tostring(m.subject), C.dim[1], C.dim[2], C.dim[3], true) end
  if num(e.ref.cod) > 0 then tip:AddLine("COD " .. fmtMoney(num(e.ref.cod)), C.dim[1], C.dim[2], C.dim[3]) end
  if e.flag then tip:AddLine("Flagged: " .. e.flag, C.red[1], C.red[2], C.red[3]) end
  tip:AddLine(("%s  ·  balance after %s"):format(date("%b %d, %H:%M:%S", e.t or 0), fmtMoney(e.bal or 0)), C.dim[1], C.dim[2], C.dim[3])
  if not e.zone then tip:AddLine("No place was recorded for this row.", C.dim[1], C.dim[2], C.dim[3], true) end
end
local function sourceTip(row, r, tip)
  if not r or r.ebSection then return end
  tip:AddLine(("%s  %s"):format(r.label, r.dir == 0 and signed(r.amount) or fmtMoney(r.amount)), 1, 1, 1)
  for i = 1, math.min(8, #r.top) do
    local t = r.top[i]
    tip:AddLine(("%s  %s%s"):format(t.name, fmtMoney(t.amount), t.n > 1 and ("  (" .. t.n .. ")") or ""), C.dim[1], C.dim[2], C.dim[3])
  end
  if #r.top > 8 then tip:AddLine(("and %d more"):format(#r.top - 8), C.dim[1], C.dim[2], C.dim[3]) end
  tip:AddLine(r.n > 0 and "Click to list every row." or "Totals only: no journal rows in the save file for this source.", C.cyan[1], C.cyan[2], C.cyan[3])
end
local function topText(r)
  if r.n == 0 then return r.key == "away" and "" or "totals only, no rows" end
  local parts = {}
  for i = 1, math.min(3, #r.top) do parts[#parts + 1] = r.top[i].name .. " " .. fmtMoney(r.top[i].amount) end
  if #r.top > 3 then parts[#parts + 1] = ("+%d more"):format(#r.top - 3) end
  return table.concat(parts, SEP)
end
local function dayTip(row, d, tip)
  if not d or d.ebSection then return end
  tip:AddLine(("%s  %s"):format(d.label or d.key, signed(d.g - d.s)), 1, 1, 1)
  for _, list in ipairs({ Gold.IN, Gold.OUT }) do
    for _, k in ipairs(list) do
      if num(d.src[k]) ~= 0 then tip:AddLine(("%s  %s"):format(Gold.LABEL[k], fmtMoney(d.src[k])), C.dim[1], C.dim[2], C.dim[3]) end
    end
  end
  if d.away ~= 0 then tip:AddLine(("%s  %s"):format(Gold.LABEL.away, signed(d.away)), C.dim[1], C.dim[2], C.dim[3]) end
  tip:AddLine(("%d purse change%s"):format(d.n, d.n == 1 and "" or "s"), C.dim[1], C.dim[2], C.dim[3])
  tip:AddLine("Click to open this day's sources.", C.cyan[1], C.cyan[2], C.cyan[3])
end
local function charTip(row, r, tip)
  if not r or r.ebSection then return end
  if r.total then
    tip:AddLine("Total  " .. fmtMoney(r.balance), 1, 1, 1)
    tip:AddLine("The characters listed and counted: not hidden, and seen in the last 90 days unless they are included.", C.dim[1], C.dim[2], C.dim[3], true)
    return
  end
  tip:AddLine(("%s  %s"):format(r.label, fmtMoney(r.balance)), 1, 1, 1)
  if r.realm then tip:AddLine("Realm: " .. r.realm, C.dim[1], C.dim[2], C.dim[3], true) end
  local facts = {}
  if r.level then facts[#facts + 1] = "level " .. r.level end
  if r.class then facts[#facts + 1] = r.class:sub(1, 1) .. r.class:sub(2):lower() end
  if r.faction then facts[#facts + 1] = r.faction end
  if #facts > 0 then tip:AddLine(table.concat(facts, SEP), C.dim[1], C.dim[2], C.dim[3]) end
  if r.me then tip:AddLine("The character you are playing.", C.dim[1], C.dim[2], C.dim[3])
  elseif r.seen then tip:AddLine("Balance as of " .. date("%b %d, %H:%M", r.seen), C.dim[1], C.dim[2], C.dim[3])
  else tip:AddLine("Balance as of the last login before the update. Log in once to refresh.", C.dim[1], C.dim[2], C.dim[3], true) end
  if r.hidden then tip:AddLine("Hidden from totals.", C.red[1], C.red[2], C.red[3])
  elseif r.stale and not r.counted then tip:AddLine("Not in the total: not seen in 90 days.", C.dim[1], C.dim[2], C.dim[3]) end
  tip:AddLine(r.hidden and "Click: show in totals." or "Click: hide from totals.", C.cyan[1], C.cyan[2], C.cyan[3])
end

-- the days a scope covers, newest first: a day period's own, every day for All time, a session's days
local function daysOf(sc, st)
  if sc.days then return sc.period.days end
  local hist = Gold.period("history", sc.who)
  if sc.lifetime then return hist.days end
  local base, sess = Gold.baseStored(), sc.sessions[1]
  if not (base and sess) then return {} end
  local fromK = Gold.dayKey(num(sess.startedEpoch), base)
  local toK = Gold.dayKey(sess.endedEpoch or nowT(), base)
  local out = {}
  for _, d in ipairs(hist.days) do if d.key >= fromK and d.key <= toK then out[#out + 1] = d end end
  return out
end

local function refresh(c)
  if not c or not c.cBalance then return end
  local st = c.st
  if c.menu then c.menu:Hide() end
  local cfg = Gold.cfg() or {}
  local now = nowT()
  local isSession = not Gold.isDayScope(st.scope) and st.scope ~= "all"
  if isSession then st.who = "char" end
  local sc = Gold.scope(st.scope, st.who)
  -- a picked session that is no longer in the save file
  if isSession and #sc.sessions == 0 and st.scope ~= "session" and st.scope ~= "previous" then
    st.scope = "today"; sc = Gold.scope("today", st.who)
  end
  local mine = sc.who == "char"
  local entries = mine and Gold.scopeEntries(sc) or {}
  local src = Gold.sources(sc, entries)
  c.scopeData, c.entries, c.sourceData = sc, entries, src
  -- the toolbar: a period that is not one of the quick three shows on the More button
  local quick = false
  for _, b in ipairs(c.scopeBtns) do
    local on = b.scope == st.scope
    quick = quick or on
    UI.SetButtonSelected(b, on); UI.FitButton(b, 44)
  end
  c.moreBtn.text:SetText(quick and "More" or (labelOf(MORE, st.scope) or sc.label or "More"))
  UI.FitButton(c.moreBtn, 44); UI.SetButtonSelected(c.moreBtn, not quick)
  c.whoBtn.text:SetText(labelOf(WHO, sc.who)); UI.FitButton(c.whoBtn, 44)
  c.viewBtn.text:SetText(labelOf(VIEWS, st.view)); UI.FitButton(c.viewBtn, 44)
  -- cards
  local g = sc.ledger
  local net = g.gained - g.spent
  local status = {}
  if mine then
    local ended = (sc.days and not sc.live and sc.balance ~= nil) or (not sc.days and not sc.lifetime and not sc.live and #sc.sessions > 0)
    c.cBalance.title:SetText(ended and "BALANCE AT ITS END" or "BALANCE")
    local bal = sc.balance
    if bal == nil and sc.days then bal = Gold.metric("balance") end
    c.cBalance.value:SetText(fmtMoney(bal or 0))
  else
    local ro = Gold.roster(sc.who == "realm" and "realm" or "all", false, now)
    c.cBalance.title:SetText("TOTAL GOLD")
    c.cBalance.value:SetText(fmtMoney(ro.total))
    status[#status + 1] = Gold.rosterLine(ro)
  end
  c.cIn.value:SetText(fmtMoney(g.gained))
  c.cOut.value:SetText(fmtMoney(g.spent))
  c.cNet.value:SetText((net < 0 and "-" or "+") .. fmtMoney(math.abs(net)))
  local nc = net < 0 and C.red or C.green
  c.cNet.value:SetTextColor(nc[1], nc[2], nc[3])
  if sc.lifetime then
    c.cRate.title:SetText("CHANGED WHILE AWAY")
    c.cRate.value:SetText(signed(num(g.away)))
  else
    -- the label names the definition: net over the time played (a day period) or the session's length
    c.cRate.title:SetText("NET PER HOUR")
    local need = sc.days and 300 or 120
    if sc.elapsed >= need then
      c.cRate.value:SetText(signed(net / (sc.elapsed / 3600)))
      status[#status + 1] = sc.days and ("per hour over %s played"):format(fmtLen(sc.elapsed)) or ("per hour over %s of the session"):format(fmtLen(sc.elapsed))
    else c.cRate.value:SetText(sc.days and "after 5 min played" or "after 2 min") end
  end
  -- shown, never subtracted: gold that moved between the player's own characters (rows with rel=alt)
  local movedIn, movedOut = 0, 0
  for _, e in ipairs(entries) do
    if e.ref and e.ref.rel == "alt" then
      if e.delta > 0 then movedIn = movedIn + e.delta else movedOut = movedOut - e.delta end
    end
  end
  if movedIn + movedOut > 0 then
    local parts = {}
    if movedIn > 0 then parts[#parts + 1] = fmtMoney(movedIn) .. " in" end
    if movedOut > 0 then parts[#parts + 1] = fmtMoney(movedOut) .. " out" end
    status[#status + 1] = "Moved between your characters: " .. table.concat(parts, ", ")
  end
  if not sc.lifetime and num(g.away) ~= 0 then status[#status + 1] = ("Not seen: %s changed while away"):format(signed(g.away)) end
  if not mine and sc.days and sc.period.gaps > 0 then
    status[#status + 1] = ("%d character%s with changes not seen on this PC in this period"):format(sc.period.gaps, sc.period.gaps == 1 and "" or "s")
  end
  local base = Gold.baseStored()
  local since = ns.DB and ns.charGuid() and plainN(ns.char().goldSince) or nil
  local historyNote
  if base and since then
    historyNote = ("History starts %s. %s"):format(Gold.fmtDate(since),
      base.kind == "server" and "Days follow the server reset." or "Days follow this PC's midnight: the server reset could not be read.")
    if (sc.days or st.view == "days") and now - since < 7 * DAY then status[#status + 1] = historyNote end
  end
  c.statusText = table.concat(status, SEP)
  c.status:SetText(c.statusText)
  -- the list
  local flagged = 0
  for _, e in ipairs(entries) do if e.flag then flagged = flagged + 1 end end
  local q = (c.search:GetText() or ""):lower()
  if q ~= "" and st.view ~= "journal" then st.view = "journal"; c.viewBtn.text:SetText(labelOf(VIEWS, st.view)); UI.FitButton(c.viewBtn, 44) end
  local view = st.view
  local jrn = c.narrow and c.tblJrnNarrow or c.tblJrn
  local days = c.wide and c.tblDays or c.tblDaysNarrow
  local chars = c.wide and c.tblChars or c.tblCharsNarrow
  showTable(c.tblSrc, view == "sources")
  showTable(c.tblJrn, view == "journal" and jrn == c.tblJrn)
  showTable(c.tblJrnNarrow, view == "journal" and jrn == c.tblJrnNarrow)
  showTable(c.tblDays, view == "days" and days == c.tblDays)
  showTable(c.tblDaysNarrow, view == "days" and days == c.tblDaysNarrow)
  showTable(c.tblChars, view == "chars" and chars == c.tblChars)
  showTable(c.tblCharsNarrow, view == "chars" and chars == c.tblCharsNarrow)
  if c.dayStrip then if view == "days" then c.dayStrip:Show() else c.dayStrip:Hide() end end
  local notes = {}
  if sc.noJournal > 0 then notes[#notes + 1] = "recorded before addon 0.9.40: totals only" end
  if sc.dropped > 0 then notes[#notes + 1] = ("%d rows past the cap not kept"):format(sc.dropped) end
  if sc.lifetime and mine then notes[#notes + 1] = ("rows from %d session%s since addon 0.9.40"):format(#sc.sessions, #sc.sessions == 1 and "" or "s") end
  if not mine then notes[#notes + 1] = "totals only: journal rows are kept per character"
  elseif sc.days and #entries < sc.period.n then notes[#notes + 1] = "Rows are kept until the desktop app has uploaded the session. Totals stay." end
  local caption
  local staleN = 0
  if view == "sources" then
    local items = {}
    if #src.rows > 0 then
      items[#items + 1] = { ebSection = ("EARNED%s%s"):format(SEP, fmtMoney(src.inTotal)), ebColor = C.dim }
      for _, r in ipairs(src.rows) do if r.dir > 0 then items[#items + 1] = r end end
      items[#items + 1] = { ebSection = ("SPENT%s%s"):format(SEP, fmtMoney(src.outTotal)), ebColor = C.dim }
      for _, r in ipairs(src.rows) do if r.dir < 0 then items[#items + 1] = r end end
      for _, r in ipairs(src.rows) do
        if r.dir == 0 then items[#items + 1] = { ebSection = "NEITHER IN NOR OUT", ebColor = C.dim }; items[#items + 1] = r end
      end
    end
    c.tblSrc.setRows(items, function(row, r)
      local cc = row.c
      cc.src:SetText(r.label)
      cc.what:SetText(topText(r))
      cc.n:SetText(r.n > 0 and tostring(r.n) or "")
      cc.share:SetText(r.dir ~= 0 and ("%d%%"):format(math.floor(r.share * 100 + 0.5)) or "")
      cc.amount:SetText(r.dir == 0 and signed(r.amount) or fmtMoney(r.amount))
      if r.dir < 0 or (r.dir == 0 and r.amount < 0) then cc.amount:SetTextColor(C.red[1], C.red[2], C.red[3]) end
      if r.key == "unexplained" or r.key == "other" then cc.src:SetTextColor(C.red[1], C.red[2], C.red[3]) end
      cc.go:SetText(r.n > 0 and "›" or "")
    end)
    local clickable = false
    for _, r in ipairs(src.rows) do if r.n > 0 then clickable = true end end
    -- (a session picked by its id is labelled with its date already)
    local byId = isSession and st.scope ~= "session" and st.scope ~= "previous"
    caption = ("%s%s%s"):format(sc.label, sc.when and not byId and (", " .. sc.when) or "", clickable and ": click a source to list its rows" or "")
  elseif view == "journal" then
    local rows, sum = {}, 0
    for i = #entries, 1, -1 do
      local e = entries[i]
      if (not st.src or e.src == st.src) and (not st.flags or e.flag) and (q == "" or hay(e):find(q, 1, true)) then
        rows[#rows + 1] = e; sum = sum + e.delta
      end
    end
    local matched = #rows
    local key, asc = st.sortKey, st.sortAsc
    if not (key == "time" and not asc) then
      local function val(e)
        if key == "amount" then return e.delta elseif key == "src" then return Gold.WORD[e.src] or ""
        elseif key == "detail" then return (e.detail or ""):lower() elseif key == "loc" then return (e.zone or ""):lower() end
        return e.t or 0
      end
      -- (a stable order: equal values keep newest first)
      local order = {}
      for i, e in ipairs(rows) do order[e] = i end
      table.sort(rows, function(a, b)
        local va, vb = val(a), val(b)
        if va == vb then return order[a] < order[b] end
        if asc then return va < vb else return va > vb end
      end)
    elseif #sc.sessions > 1 then
      -- newest first over several sessions: one section per session
      local out, lastSid = {}, nil
      for _, e in ipairs(rows) do
        if e.sid ~= lastSid then
          lastSid = e.sid
          local s = e.sess
          out[#out + 1] = { ebSection = ("%s%s%s%snet %s"):format(sessionLabel(s), SEP, s == current() and "running" or fmtLen(elapsedOf(s)), SEP,
            signed(num(s.gained) - num(s.spent))), ebColor = C.dim }
        end
        out[#out + 1] = e
      end
      rows = out
    end
    -- the list holds Gold.MAX_ROWS rows; the sum and the count are of every matching row
    if #rows > Gold.MAX_ROWS then for i = #rows, Gold.MAX_ROWS + 1, -1 do rows[i] = nil end end
    jrn.setRows(rows, function(row, e)
      local cc = row.c
      cc.time:SetText(date("%H:%M:%S", e.t or 0))
      cc.src:SetText(Gold.WORD[e.src] or e.src)
      cc.detail:SetText(e.detail or "")
      if e.flag then cc.detail:SetTextColor(C.red[1], C.red[2], C.red[3]) end
      cc.loc:SetText(e.zone or "")
      cc.coords:SetText((e.x and e.y) and UI.fmtCoords(e.x, e.y) or "")
      cc.amount:SetText(signed(e.delta))
      if e.delta < 0 then cc.amount:SetTextColor(C.red[1], C.red[2], C.red[3]) end
      if cc.bal then cc.bal:SetText(fmtMoney(e.bal or 0)) end
    end)
    c.journalRows, c.journalCount = jrn.rows, #rows
    local what = st.flags and "Flagged rows" or (st.src and Gold.LABEL[st.src]) or "Every row"
    local nRows = matched
    caption = ("%s%s%d row%s%s%s"):format(what, SEP, nRows, nRows == 1 and "" or "s", SEP, signed(sum))
    if matched > Gold.MAX_ROWS then caption = caption .. SEP .. ("the first %d listed: pick a source or search to narrow"):format(Gold.MAX_ROWS) end
    if q ~= "" then caption = caption .. SEP .. "matching \"" .. q .. "\"" end
  elseif view == "days" then
    local list = {}
    local todayK = base and Gold.dayKey(now, base) or nil
    for _, d in ipairs(daysOf(sc, st)) do
      d.label = base and Gold.dayLabel(d.key, base) or d.key
      d.today = d.key == todayK
      list[#list + 1] = d
    end
    -- the strip: the net of each of the last 30 days with a row, oldest left
    if c.dayStrip and UI.renderStrip then
      local vals = {}
      local hist = sc.days and Gold.period("last30", sc.who).days or list
      for i = math.min(#hist, STRIP_DAYS), 1, -1 do
        local d = hist[i]
        vals[#vals + 1] = { v = d.g - d.s, label = base and Gold.dayLabel(d.key, base) or d.key, live = d.key == todayK }
      end
      UI.renderStrip(c.dayStrip, vals, function(v) return signed(v) end, true)
    end
    local sumG, sumS = 0, 0
    for _, d in ipairs(list) do sumG, sumS = sumG + d.g, sumS + d.s end
    local key, asc = st.daySort, st.dayAsc
    local rows = list
    if not (key == "day" and not asc) then
      local function val(d)
        if key == "earned" then return d.g elseif key == "spent" then return d.s elseif key == "net" then return d.g - d.s end
        return d.key
      end
      rows = {}
      for i, d in ipairs(list) do rows[i] = d end
      table.sort(rows, function(a, b)
        local va, vb = val(a), val(b)
        if va == vb then return a.key > b.key end
        if asc then return va < vb else return va > vb end
      end)
    elseif base and #list > 1 then
      -- newest first: a subtotal line over each month and each week when the list spans more than one, and a line
      -- for the days a change while away covers (they were not recorded on this PC)
      local weeks, months, nW, nM = {}, {}, 0, 0
      for _, d in ipairs(list) do
        d.week, d.month = Gold.weekStart(d.start, base), d.key:sub(1, 6)
        for _, grp in ipairs({ { weeks, d.week }, { months, d.month } }) do
          local a = grp[1][grp[2]]
          if not a then a = { g = 0, s = 0 }; grp[1][grp[2]] = a; if grp[1] == weeks then nW = nW + 1 else nM = nM + 1 end end
          a.g, a.s = a.g + d.g, a.s + d.s
        end
      end
      local function sub(name, a)
        return { ebSection = ("%s%searned %s%sspent %s%snet %s"):format(name, SEP, fmtMoney(a.g), SEP, fmtMoney(a.s), SEP, signed(a.g - a.s)), ebColor = C.dim }
      end
      rows = {}
      local lastW, lastM
      for i, d in ipairs(list) do
        if nM > 1 and d.month ~= lastM then lastM = d.month; rows[#rows + 1] = sub(date("%B %Y", d.start + DAY / 2):upper(), months[d.month]) end
        if nW > 1 and d.week ~= lastW then lastW = d.week; rows[#rows + 1] = sub("Week of " .. Gold.fmtDate(d.week + DAY / 2), weeks[d.week]) end
        rows[#rows + 1] = d
        local older = list[i + 1]
        if mine and older and d.away ~= 0 and d.start - older.start > DAY then
          local a, b = older.start + DAY, d.start - DAY
          rows[#rows + 1] = { ebSection = ("%s%snot recorded on this PC"):format(a == b and Gold.fmtDate(a + DAY / 2) or (Gold.fmtDate(a + DAY / 2) .. " to " .. Gold.fmtDate(b + DAY / 2)), SEP),
            ebColor = C.dim, ebIndent = SP.M }
        end
      end
    end
    days.setRows(rows, function(row, d)
      local cc = row.c
      local dn = d.g - d.s
      cc.day:SetText(d.label .. (d.today and (SEP .. "today") or ""))
      cc.earned:SetText(fmtMoney(d.g)); cc.spent:SetText(fmtMoney(d.s)); cc.net:SetText(signed(dn))
      if dn < 0 then cc.net:SetTextColor(C.red[1], C.red[2], C.red[3]) end
      if cc.played then cc.played:SetText(d.t >= 60 and fmtLen(d.t) or "") end
      if cc.rate then cc.rate:SetText(d.t >= 300 and signed(dn * 3600 / d.t) or "") end
      if cc.top then
        local tk, tv = Gold.topSource(d.src)
        cc.top:SetText(tk and (Gold.LABEL[tk] .. " " .. fmtMoney(tv)) or "")
      end
      cc.bal:SetText(d.c and fmtMoney(d.c) or "")
    end)
    caption = ("%s%s%d day%s%snet %s"):format(sc.label, SEP, #list, #list == 1 and "" or "s", SEP, signed(sumG - sumS))
    if #list == 0 then caption = sc.label .. SEP .. "no days recorded" end
    notes = {}
    if historyNote and not (c.statusText or ""):find(historyNote, 1, true) then notes[#notes + 1] = historyNote end
    if #list > 0 then notes[#notes + 1] = "click a day to open its sources" end
  else
    -- Characters: the roster for the saved filter, the TOTAL row pinned first
    local filter = labelOf(FILTERS, cfg.filter) and cfg.filter or "all"
    local ro = Gold.roster(filter, st.withStale, now)
    staleN = ro.stale
    c.rosterData = ro
    local rows = {}
    for _, r in ipairs(ro.rows) do rows[#rows + 1] = r end
    local key, asc = st.charSort, st.charAsc
    if not (key == "balance" and not asc) then
      local function val(r)
        if key == "name" then return r.label:lower() elseif key == "realm" then return (r.realmLabel or ""):lower()
        elseif key == "level" then return r.level or 0 elseif key == "today" then return r.today elseif key == "d7" then return r.d7
        elseif key == "seen" then return r.me and math.huge or (r.seen or 0) end
        return r.balance
      end
      local order = {}
      for i, r in ipairs(rows) do order[r] = i end
      table.sort(rows, function(a, b)
        local va, vb = val(a), val(b)
        if va == vb then return order[a] < order[b] end
        if asc then return va < vb else return va > vb end
      end)
    end
    local tot = { total = true, label = "TOTAL", balance = ro.total, today = 0, d7 = 0, count = ro.count, oldest = ro.oldest }
    for _, r in ipairs(ro.rows) do if r.counted then tot.today, tot.d7 = tot.today + r.today, tot.d7 + r.d7 end end
    if #rows > 0 then table.insert(rows, 1, tot) end
    chars.setRows(rows, function(row, r)
      local cc = row.c
      local function money(fs, v) fs:SetText(signed(v)); if v < 0 then fs:SetTextColor(C.red[1], C.red[2], C.red[3]) end end
      if r.total then
        cc.name:SetText(("TOTAL%s%d character%s"):format(SEP, r.count, r.count == 1 and "" or "s"))
        cc.name:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
        cc.balance:SetText(fmtMoney(r.balance)); cc.balance:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
        money(cc.today, r.today); money(cc.d7, r.d7)
        cc.seen:SetText(r.oldest and ("oldest " .. Gold.fmtDate(r.oldest)) or "")
        if cc.share then cc.share:SetText(r.balance > 0 and "100%" or "") end
        return
      end
      cc.name:SetText(r.label .. (r.me and (SEP .. "You") or ""))
      if r.hidden or not r.counted or not r.facts then cc.name:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
      elseif r.class and UI.ClassColor then cc.name:SetTextColor(UI.ClassColor(r.class)) end
      cc.balance:SetText(fmtMoney(r.balance))
      if not r.counted then cc.balance:SetTextColor(C.dim[1], C.dim[2], C.dim[3]) end
      money(cc.today, r.today); money(cc.d7, r.d7)
      local seen
      if r.hidden then seen = "hidden from totals"
      elseif r.me then seen = "now"
      elseif not r.facts then seen = "log in once to refresh"
      else seen = Gold.fmtAge(r.seen, now) .. ((r.stale and not r.counted) and ", not in total" or "") end
      cc.seen:SetText(seen)
      if cc.realm then cc.realm:SetText(r.realmLabel or "") end
      if cc.faction then cc.faction:SetText(r.faction or "") end
      if cc.level then cc.level:SetText(r.level and tostring(r.level) or "") end
      if cc.share then cc.share:SetText((r.counted and ro.total > 0) and ("%d%%"):format(math.floor(r.balance / ro.total * 100 + 0.5)) or "") end
    end)
    caption = ("%s%s%s%stotal %s"):format(labelOf(FILTERS, filter), SEP, Gold.rosterLine(ro), SEP, fmtMoney(ro.total))
    notes = {}
    if ro.needLogin > 0 then
      notes[#notes + 1] = ("%d character%s not seen since the update: log in once on each to refresh"):format(ro.needLogin, ro.needLogin == 1 and "" or "s")
    end
    if ro.hidden > 0 then notes[#notes + 1] = ("%d hidden from totals"):format(ro.hidden) end
  end
  if #notes > 0 then caption = caption .. SEP .. table.concat(notes, SEP) end
  -- the caption's buttons, right to left. Sources and Journal: All rows (a filter is on), Flagged (the period has
  -- flagged rows). Characters: the filter, and the characters not seen in 90 days when there are any.
  local showAll = view == "journal" and (st.src or st.flags or q ~= "") and true or false
  local showFlag = (view == "sources" or view == "journal") and flagged > 0
  local showFilter = view == "chars"
  local showStale = view == "chars" and staleN > 0
  local anchor = c.capRow
  local function put(b, on)
    b:ClearAllPoints()
    if not on then b:Hide(); return end
    UI.FitButton(b, 44)
    if anchor == c.capRow then b:SetPoint("RIGHT", c.capRow, "RIGHT", 0, 0) else b:SetPoint("RIGHT", anchor, "LEFT", -SP.S, 0) end
    b:Show(); anchor = b
  end
  put(c.allBtn, showAll)
  if showFlag then c.flagBtn.text:SetText(("Flagged: %d"):format(flagged)) end
  put(c.flagBtn, showFlag)
  if showFlag then
    UI.SetButtonSelected(c.flagBtn, view == "journal" and st.flags or false)
    c.flagBtn.text:SetTextColor(C.red[1], C.red[2], C.red[3])
  end
  if showFilter then c.filterBtn.text:SetText(labelOf(FILTERS, cfg.filter) or FILTERS[1][2]) end
  put(c.filterBtn, showFilter)
  if showStale then c.staleBtn.text:SetText(("Not seen in 90 days: %d"):format(staleN)) end
  put(c.staleBtn, showStale)
  if showStale then UI.SetButtonSelected(c.staleBtn, st.withStale and true or false) end
  c.caption:ClearAllPoints()
  c.caption:SetPoint("LEFT", c.capRow, "LEFT", SP.S, 0)
  if anchor == c.capRow then c.caption:SetPoint("RIGHT", c.capRow, "RIGHT", -SP.S, 0) else c.caption:SetPoint("RIGHT", anchor, "LEFT", -SP.M, 0) end
  c.caption:SetText(caption)
  local w, h = c.layoutW, c.layoutH
  if not w or w <= 0 then
    local ok1, gw = pcall(c.GetWidth, c); local ok2, gh = pcall(c.GetHeight, c)
    w, h = ok1 and gw or 0, ok2 and gh or 0
  end
  relayout(c, w, h)
end

-- ── build ────────────────────────────────────────────────────────────────────
local function card(content, d)
  local p = UI.Panel(content)
  p:SetHeight(52)
  p.title = oneLine(UI.FS(p, "GameFontNormalSmall", C.dim))
  p.title:SetPoint("TOPLEFT", p, "TOPLEFT", PAD, -PAD); p.title:SetPoint("TOPRIGHT", p, "TOPRIGHT", -PAD, -PAD)
  p.title:SetJustifyH("LEFT"); p.title:SetText(d.label)
  p.value = oneLine(UI.FS(p, "GameFontNormalLarge", C.ink))
  if UI.TITLE_FONT then p.value:SetFontObject(UI.TITLE_FONT) end
  p.value:SetPoint("TOPLEFT", p.title, "BOTTOMLEFT", 0, -SP.XS); p.value:SetPoint("TOPRIGHT", p.title, "BOTTOMRIGHT", 0, -SP.XS)
  p.value:SetJustifyH("LEFT"); p.value:SetTextColor(C.ink[1], C.ink[2], C.ink[3])
  return p
end

-- A short list of choices under a button, the pane's own frame (no UIDropDownMenu: it spreads taint). One per pane:
-- menu.open(anchor, items, onPick, right) with items { { key, label, selected } }; a click picks and closes, a
-- second click on the same button closes.
local function buildMenu(c)
  local m = UI.Panel(c)
  if m.SetFrameStrata then m:SetFrameStrata("DIALOG") end
  m.btns = {}
  m:Hide()
  function m.open(anchor, items, onPick, right)
    if m:IsShown() and m.anchor == anchor then m:Hide(); m.anchor = nil; return end
    m.anchor, m.items = anchor, items
    local wmax = 0
    for i, it in ipairs(items) do
      local b = m.btns[i]
      if not b then
        b = UI.Button(m, "", 44, ROW_H, function(bb) m:Hide(); m.anchor = nil; if m.onPick then m.onPick(bb.key) end end)
        m.btns[i] = b
      end
      b.key = it[1]
      b.text:SetText(it[2]); UI.FitButton(b, 44); UI.SetButtonSelected(b, it[3] and true or false)
      local ok, bw = pcall(b.GetWidth, b)
      wmax = math.max(wmax, ok and tonumber(bw) or 0)
      b:Show()
    end
    for i = #items + 1, #m.btns do m.btns[i]:Hide() end
    for i = 1, #items do
      local b = m.btns[i]
      b:ClearAllPoints(); b:SetPoint("TOPLEFT", m, "TOPLEFT", SP.XS, -SP.XS - (i - 1) * (ROW_H + 2)); b:SetWidth(wmax)
    end
    m.onPick = onPick
    m:SetSize(wmax + 2 * SP.XS, #items * (ROW_H + 2) - 2 + 2 * SP.XS)
    m:ClearAllPoints()
    if right then m:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -2) else m:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2) end
    m:Show()
  end
  return m
end

-- Build the Gold pane into `pane` (a UI.Tabs pane). Returns a refresh function for the host to call.
function ns.BuildEconomyPane(pane)
  local c = pane
  -- state on one table: the period, whose numbers, the view, the journal's filter and sort, the sorts of Days and
  -- Characters. Only the Characters filter is saved (settings.gold.filter).
  local st = { scope = "today", who = "char", view = "sources", src = nil, flags = false, sortKey = "time", sortAsc = false,
    daySort = "day", dayAsc = false, charSort = "balance", charAsc = false, withStale = false }
  c.st = st
  local function again() refresh(c) end
  c.refresh = again
  local function setScope(key) st.scope = key; st.src, st.flags = nil, false; again() end
  local function setView(key)
    st.view = key
    if key ~= "journal" then st.src, st.flags = nil, false; c.search:SetText("") end
    again()
  end
  local function setWho(key)
    if key ~= "char" and not Gold.isDayScope(st.scope) and st.scope ~= "all" then st.scope = "today" end
    st.who = key; again()
  end
  c.setScope, c.setView, c.setWho = setScope, setView, setWho
  -- toolbar: periods at the left; who, the view and the search box at the right
  c.scopeBtns = {}
  local prev
  for _, s in ipairs(QUICK) do
    local b = UI.Button(c, s[2], 44, ROW_H, function(bb) setScope(bb.scope) end)
    UI.FitButton(b, 44); b.scope = s[1]
    if prev then b:SetPoint("LEFT", prev, "RIGHT", SP.XS, 0) else b:SetPoint("TOPLEFT", c, "TOPLEFT", SP.S, 0) end
    c.scopeBtns[#c.scopeBtns + 1] = b; prev = b
  end
  c.menu = buildMenu(c)
  c.moreBtn = UI.Button(c, "More", 44, ROW_H, function(bb)
    local items = {}
    for _, e in ipairs(MORE) do items[#items + 1] = { e[1], e[2], st.scope == e[1] } end
    -- the earlier sessions still in the save file, newest first
    local cur, earlier = current(), {}
    for _, s in ipairs(Gold.sessions()) do if s ~= cur then earlier[#earlier + 1] = s end end
    table.sort(earlier, function(a, b)
      if num(a.startedEpoch) ~= num(b.startedEpoch) then return num(a.startedEpoch) > num(b.startedEpoch) end
      return tostring(a.id) > tostring(b.id)
    end)
    for i = 1, math.min(#earlier, Gold.MORE_SESSIONS) do
      local s = earlier[i]
      items[#items + 1] = { s.id, sessionLabel(s), st.scope == s.id }
    end
    c.menu.open(bb, items, setScope)
  end)
  c.moreBtn:SetPoint("LEFT", prev, "RIGHT", SP.XS, 0)
  c.search = UI.EditBox(c, 170, ROW_H, "search quest, item, player")
  c.search:SetPoint("TOPRIGHT", c, "TOPRIGHT", -UI.SCROLLBAR, 0)
  c.search:HookScript("OnTextChanged", again)
  c.viewBtn = UI.Button(c, "Sources", 44, ROW_H, function(bb)
    local items = {}
    for _, e in ipairs(VIEWS) do items[#items + 1] = { e[1], e[2], st.view == e[1] } end
    c.menu.open(bb, items, setView, true)
  end)
  c.viewBtn:SetPoint("RIGHT", c.search, "LEFT", -SP.S, 0)
  c.whoBtn = UI.Button(c, "This character", 44, ROW_H, function(bb)
    local items = {}
    for _, e in ipairs(WHO) do items[#items + 1] = { e[1], e[2], st.who == e[1] } end
    c.menu.open(bb, items, setWho, true)
  end)
  c.whoBtn:SetPoint("RIGHT", c.viewBtn, "LEFT", -SP.XS, 0)
  for _, d in ipairs(CARDS) do c[d.key] = card(c, d) end
  -- the status line under the cards: what the cards do not say (who is counted, what moved between the player's own
  -- characters, what changed while away, where the history starts)
  c.statusRow = CreateFrame("Frame", nil, c); c.statusRow:SetHeight(ROW_H)
  c.status = UI.CellFS(c.statusRow, "GameFontHighlightSmall", C.dim); c.status:SetJustifyH("LEFT")
  c.status:SetPoint("LEFT", c.statusRow, "LEFT", SP.S, 0); c.status:SetPoint("RIGHT", c.statusRow, "RIGHT", -SP.S, 0)
  c.statusRow:Hide()
  -- the caption line: what the list shows, with its buttons at the right
  c.capRow = CreateFrame("Frame", nil, c); c.capRow:SetHeight(ROW_H)
  c.caption = UI.CellFS(c.capRow, "GameFontHighlightSmall", C.gold); c.caption:SetJustifyH("LEFT")
  c.allBtn = UI.Button(c.capRow, "All rows", 44, ROW_H, function() st.src, st.flags = nil, false; c.search:SetText(""); again() end)
  c.flagBtn = UI.Button(c.capRow, "Flagged", 44, ROW_H, function()
    st.flags = not (st.view == "journal" and st.flags); st.view = "journal"; st.src = nil; again()
  end)
  c.filterBtn = UI.Button(c.capRow, FILTERS[1][2], 44, ROW_H, function(bb)
    local cur = (Gold.cfg() or {}).filter or "all"
    local items = {}
    for _, e in ipairs(FILTERS) do items[#items + 1] = { e[1], e[2], cur == e[1] } end
    c.menu.open(bb, items, function(key) Gold.cfg(true).filter = key; again() end, true)
  end)
  c.staleBtn = UI.Button(c.capRow, "Not seen in 90 days", 44, ROW_H, function() st.withStale = not st.withStale; again() end)
  c.filterBtn:Hide(); c.staleBtn:Hide()
  c.body = CreateFrame("Frame", nil, c)
  c.body:SetPoint("TOPLEFT", c, "TOPLEFT", 0, -140); c.body:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 0, 0)
  -- Sources: one row per source, a click opens its rows
  c.tblSrc = UI.Table(c.body, {
    { key = "src", label = "Source", flex = 2, min = 130 },
    { key = "what", label = "Biggest", flex = 5, min = 120, color = "dim" },
    { key = "n", label = "Rows", kind = "num", color = "dim", measure = { "9999" } },
    { key = "share", label = "Share", kind = "num", color = "dim", measure = { "100%" } },
    { key = "amount", label = "Amount", kind = "money" },
    { key = "go", label = "", kind = "tag", color = "dim", measure = { "›" } },
  }, { tooltip = sourceTip, emptyText = "No gold moved in this period yet.",
    onClick = function(_, r) if r and r.key and r.n > 0 then Gold.filter(r.key) end end })
  -- Journal: text columns at the left, the numbers together at the right; Location and Coords are two columns
  local function journal(withBalance)
    local spec = {
      { key = "time", label = "Time", kind = "tag", color = "dim", measure = { "00:00:00" }, sort = true },
      { key = "src", label = "Source", kind = "tag", sort = true },
      { key = "detail", label = "Detail", flex = 3, min = 100, sort = true },
      { key = "loc", label = "Location", flex = 2, min = 72, color = "dim", sort = true },
      { key = "coords", label = "Coords", kind = "tag", justify = "RIGHT", color = "dim" },
      { key = "amount", label = "Amount", kind = "money", sort = true },
    }
    if withBalance then spec[#spec + 1] = { key = "bal", label = "Balance", kind = "money", color = "dim" } end
    return UI.Table(c.body, spec, { sortKey = st.sortKey, sortAsc = st.sortAsc, tooltip = journalTip,
      emptyText = "No rows. The gold journal is recorded from addon 0.9.40 on.",
      onSort = function(key, asc)
        st.sortKey, st.sortAsc = key, asc
        c.tblJrn.setSort(key, asc); c.tblJrnNarrow.setSort(key, asc)
        again()
      end })
  end
  c.tblJrn, c.tblJrnNarrow = journal(true), journal(false)
  -- Days: one row per day of the period, newest first, under a strip of the last 30 days' net. A click opens the
  -- day's sources. Played, Per hour and Top source are left out of a list narrower than WIDE.
  if UI.makeStrip then c.dayStrip = UI.makeStrip(c.body, "Net per day, last 30 days", STRIP_DAYS); c.dayStrip:Hide() end
  local function daysTable(wide)
    local spec = {
      { key = "day", label = "Day", flex = 2, min = 96, sort = true },
      { key = "earned", label = "Earned", kind = "money", sort = true },
      { key = "spent", label = "Spent", kind = "money", sort = true },
      { key = "net", label = "Net", kind = "money", sort = true },
    }
    if wide then
      spec[#spec + 1] = { key = "played", label = "Played", kind = "num", color = "dim" }
      spec[#spec + 1] = { key = "rate", label = "Per hour", kind = "money", color = "dim" }
      spec[#spec + 1] = { key = "top", label = "Top source", flex = 3, min = 110, color = "dim" }
    end
    spec[#spec + 1] = { key = "bal", label = "Closing balance", kind = "money", color = "dim" }
    return UI.Table(c.body, spec, { top = c.dayStrip and -(stripH() + SP.S) or 0, sortKey = st.daySort, sortAsc = st.dayAsc, tooltip = dayTip,
      emptyText = "No days yet. Each day with a gold change gets a row from addon 0.9.44 on. Days follow the server reset.",
      onClick = function(_, d) if d and d.key and not d.ebSection then st.view = "sources"; setScope("day:" .. d.key) end end,
      onSort = function(key, asc)
        st.daySort, st.dayAsc = key, asc
        c.tblDays.setSort(key, asc); c.tblDaysNarrow.setSort(key, asc)
        again()
      end })
  end
  c.tblDays, c.tblDaysNarrow = daysTable(true), daysTable(false)
  -- Characters: every character of the save file for the filter, the TOTAL row pinned first. A click on a row
  -- offers to hide it from totals (or show it again). Realm, Faction, Level and Share are left out when narrow.
  local function charsTable(wide)
    local spec = { { key = "name", label = "Character", flex = 3, min = 150, sort = true } }
    if wide then
      spec[#spec + 1] = { key = "realm", label = "Realm", flex = 2, min = 80, color = "dim", sort = true }
      spec[#spec + 1] = { key = "faction", label = "Faction", kind = "tag", color = "dim" }
      spec[#spec + 1] = { key = "level", label = "Level", kind = "num", color = "dim", sort = true }
    end
    spec[#spec + 1] = { key = "balance", label = "Balance", kind = "money", sort = true }
    if wide then spec[#spec + 1] = { key = "share", label = "Share", kind = "num", color = "dim", measure = { "100%" } } end
    spec[#spec + 1] = { key = "today", label = "Today", kind = "money", sort = true }
    spec[#spec + 1] = { key = "d7", label = "7 days", kind = "money", sort = true }
    spec[#spec + 1] = { key = "seen", label = "Last seen", kind = "tag", color = "dim", sort = true }
    return UI.Table(c.body, spec, { sortKey = st.charSort, sortAsc = st.charAsc, tooltip = charTip,
      emptyText = "No characters yet. A character is listed once it has logged in with the addon.",
      onClick = function(row, r)
        if not r or r.total or r.ebSection then return end
        c.menu.open(row, { { r.guid, r.hidden and "Show in totals" or "Hide from totals" } }, function(guid)
          local cfg = Gold.cfg(true)
          cfg.hidden = type(cfg.hidden) == "table" and cfg.hidden or {}
          if cfg.hidden[guid] then cfg.hidden[guid] = nil else cfg.hidden[guid] = true end
          if next(cfg.hidden) == nil then cfg.hidden = nil end
          again()
        end)
      end,
      onSort = function(key, asc)
        st.charSort, st.charAsc = key, asc
        c.tblChars.setSort(key, asc); c.tblCharsNarrow.setSort(key, asc)
        again()
      end })
  end
  c.tblChars, c.tblCharsNarrow = charsTable(true), charsTable(false)
  c:HookScript("OnSizeChanged", function(f, w, h) pcall(relayout, f, w, h) end)
  c:HookScript("OnHide", function() if c.menu then c.menu:Hide() end end)
  refresh(c)
  return again
end

-- LOOT / Gold pane (the Loot host is declared by Emitter.lua with the Items pane)
local goldRefresh, goldContent
UI.registerPane("Loot", 2, "Gold", function(content) goldContent = content; goldRefresh = ns.BuildEconomyPane(content) end,
  function() if goldRefresh then goldRefresh() end end)

-- the open pane follows the purse: one refresh 0.1 s after the first of a burst of changes
local function showing(f)
  for _ = 1, 20 do
    if not f then return true end
    if f.IsShown and not f:IsShown() then return false end
    f = f.GetParent and f:GetParent() or nil
  end
  return true
end
Gold.onChange(function()
  if not (goldRefresh and goldContent) then return end
  if not (C_Timer and type(C_Timer.After) == "function") then return end
  -- (a refresh queued over a second ago never ran: queue again)
  local now = GetTime()
  if Gold._refreshQueued and now - Gold._refreshQueued < 1 then return end
  Gold._refreshQueued = now
  C_Timer.After(0.1, function()
    Gold._refreshQueued = nil
    if goldRefresh and showing(goldContent) then pcall(goldRefresh) end
  end)
end)

-- Open the Gold pane on a period: "session", "previous", "all", a session id or a day period (Home / Sessions, the
-- Overview card). view: "sources" (default), "journal", "days" or "chars"; flags: true lists the flagged rows.
function Gold.open(scope, view, flags)
  UI.Open("Loot", "gold")
  if not (goldContent and goldContent.st) then return end
  local st = goldContent.st
  st.scope, st.src, st.flags = scope or "session", nil, flags and true or false
  st.view = flags and "journal" or (labelOf(VIEWS, view) and view or "sources")
  if not Gold.isDayScope(st.scope) and st.scope ~= "all" then st.who = "char" end
  if goldContent.search then goldContent.search:SetText("") end
  if goldRefresh then goldRefresh() end
end

-- the journal of the open period, one source only (a click on its Sources row does the same)
function Gold.filter(src)
  if not (goldContent and goldContent.st and Gold.LABEL[src]) then return end
  local st = goldContent.st
  st.view, st.src, st.flags = "journal", src, false
  if goldRefresh then goldRefresh() end
end

-- ── test exports: headless luajit tests in tests/ read these; no effect in-game ──
ns._test = ns._test or {}
ns._test.economyFmtMoney = fmtMoney
