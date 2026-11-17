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

-- key: "session", "previous", "all", or a session id. Returns { key, label, sessions, ledger, lifetime, elapsed,
-- balance, noJournal (sessions of the scope recorded before 0.9.40), dropped (rows past the cap) }.
function Gold.scope(key)
  local sc = { key = key, sessions = {}, ledger = {}, elapsed = 0, noJournal = 0, dropped = 0 }
  local all, cur = Gold.sessions(), current()
  local charGold = (ns.DB and ns.char and ns.char().gold) or {}
  if key == "all" then
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
  end
  for _, s in ipairs(sc.sessions) do
    if type(s.goldLog) ~= "table" then sc.noJournal = sc.noJournal + 1 end
    sc.dropped = sc.dropped + num(s.goldLogDropped)
  end
  local g = sc.ledger
  g.gained, g.spent = num(g.gained), num(g.spent)
  -- income no source claimed is in `gained` only
  local known = 0
  for _, k in ipairs(Gold.IN) do if k ~= "unexplained" then known = known + num(g[k]) end end
  g.unexplained = math.max(0, g.gained - known)
  return sc
end

-- every journal row of a scope, oldest first (session by session)
function Gold.scopeEntries(sc)
  local ix, out = Gold.index(), {}
  for i = #sc.sessions, 1, -1 do
    for _, e in ipairs(Gold.entries(sc.sessions[i], ix)) do out[#out + 1] = e end
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

-- ── the Gold pane ───────────────────────────────────────────────────────────────────────────────────────────────
local CARDS = {
  { key = "cBalance", label = "BALANCE" },
  { key = "cIn",      label = "IN" },
  { key = "cOut",     label = "OUT" },
  { key = "cNet",     label = "NET" },
  { key = "cRate",    label = "PER HOUR" },
}
local SCOPES = { { "session", "This session" }, { "previous", "Previous" }, { "all", "All time" } }
local NARROW = 760   -- a list narrower than this leaves the Balance column out
Gold.MAX_ROWS = 500  -- journal rows listed at once (a row is a frame): the newest, the caption says how many more

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

local function relayout(c, w, h)
  w, h = tonumber(w) or 0, tonumber(h) or 0
  if w <= 2 * PAD + 10 then return end
  c.layoutW, c.layoutH = w, h
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
  -- the caption line and its buttons, then the list in the rest of the pane
  c.capRow:ClearAllPoints()
  c.capRow:SetPoint("TOPLEFT", c, "TOPLEFT", 0, y); c.capRow:SetPoint("TOPRIGHT", c, "TOPRIGHT", -UI.SCROLLBAR, y)
  y = y - ROW_H - SP.S
  c.body:ClearAllPoints()
  c.body:SetPoint("TOPLEFT", c, "TOPLEFT", 0, y); c.body:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 0, 0)
  local narrow = (w - UI.SCROLLBAR) < NARROW
  if narrow ~= c.narrow then c.narrow = narrow; if c.refresh then c.refresh() end end
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
  tip:AddLine(r.n > 0 and "Click to list every row." or "No rows: recorded before addon 0.9.40.", C.cyan[1], C.cyan[2], C.cyan[3])
end
local function topText(r)
  if r.n == 0 then return r.key == "away" and "" or "totals only, no rows" end
  local parts = {}
  for i = 1, math.min(3, #r.top) do parts[#parts + 1] = r.top[i].name .. " " .. fmtMoney(r.top[i].amount) end
  if #r.top > 3 then parts[#parts + 1] = ("+%d more"):format(#r.top - 3) end
  return table.concat(parts, SEP)
end

local function refresh(c)
  if not c or not c.cBalance then return end
  local st = c.st
  local sc = Gold.scope(st.scope)
  if #sc.sessions == 0 and st.scope ~= "all" and st.scope ~= "session" and st.scope ~= "previous" then st.scope = "session"; sc = Gold.scope("session") end
  local entries = Gold.scopeEntries(sc)
  local src = Gold.sources(sc, entries)
  c.scopeData, c.entries, c.sourceData = sc, entries, src
  -- the period buttons; a session picked on Home / Sessions gets a button of its own
  local picked = st.scope ~= "session" and st.scope ~= "previous" and st.scope ~= "all"
  for _, b in ipairs(c.scopeBtns) do UI.SetButtonSelected(b, b.scope == st.scope); UI.FitButton(b, 44) end
  if picked then
    c.pickBtn.text:SetText(sc.label); UI.FitButton(c.pickBtn, 44); UI.SetButtonSelected(c.pickBtn, true); c.pickBtn:Show()
  else c.pickBtn:Hide() end
  -- cards
  local g = sc.ledger
  local net = g.gained - g.spent
  c.cBalance.title:SetText((sc.lifetime or sc.live or #sc.sessions == 0) and "BALANCE" or "BALANCE AT ITS END")
  c.cBalance.value:SetText(fmtMoney(sc.balance or 0))
  c.cIn.value:SetText(fmtMoney(g.gained))
  c.cOut.value:SetText(fmtMoney(g.spent))
  c.cNet.value:SetText((net < 0 and "-" or "+") .. fmtMoney(math.abs(net)))
  local nc = net < 0 and C.red or C.green
  c.cNet.value:SetTextColor(nc[1], nc[2], nc[3])
  if sc.lifetime then
    c.cRate.title:SetText("CHANGED WHILE AWAY")
    c.cRate.value:SetText(signed(num(g.away)))
  else
    c.cRate.title:SetText("PER HOUR")
    c.cRate.value:SetText(sc.elapsed >= 120 and signed(net / (sc.elapsed / 3600)) or "after 2 min")
  end
  -- the list
  local flagged = 0
  for _, e in ipairs(entries) do if e.flag then flagged = flagged + 1 end end
  local q = (c.search:GetText() or ""):lower()
  if q ~= "" and st.view == "sources" then st.view = "journal" end
  c.viewBtn.text:SetText(st.view == "sources" and "Journal" or "Sources")
  local jrn = c.narrow and c.tblJrnNarrow or c.tblJrn
  showTable(c.tblSrc, st.view == "sources")
  showTable(c.tblJrn, st.view == "journal" and jrn == c.tblJrn)
  showTable(c.tblJrnNarrow, st.view == "journal" and jrn == c.tblJrnNarrow)
  local notes = {}
  if sc.noJournal > 0 then notes[#notes + 1] = "recorded before addon 0.9.40: totals only" end
  if sc.dropped > 0 then notes[#notes + 1] = ("%d rows past the cap not kept"):format(sc.dropped) end
  if sc.lifetime then notes[#notes + 1] = ("rows from %d session%s since addon 0.9.40"):format(#sc.sessions, #sc.sessions == 1 and "" or "s") end
  local caption
  if st.view == "sources" then
    local items = {}
    if #src.rows > 0 then
      items[#items + 1] = { ebSection = ("IN%s%s"):format(SEP, fmtMoney(src.inTotal)), ebColor = C.dim }
      for _, r in ipairs(src.rows) do if r.dir > 0 then items[#items + 1] = r end end
      items[#items + 1] = { ebSection = ("OUT%s%s"):format(SEP, fmtMoney(src.outTotal)), ebColor = C.dim }
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
    caption = ("%s%s%s"):format(sc.label, sc.when and not picked and (", " .. sc.when) or "", #src.rows > 0 and ": click a source to list its rows" or "")
  else
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
  end
  if #notes > 0 then caption = caption .. SEP .. table.concat(notes, SEP) end
  -- the caption's buttons, right to left: All rows (a filter is on), Flagged (the period has flagged rows)
  local filtered = st.view == "journal" and (st.src or st.flags or q ~= "")
  c.allBtn:ClearAllPoints(); c.flagBtn:ClearAllPoints()
  local anchor, ax = c.capRow, 0
  if filtered then
    UI.FitButton(c.allBtn, 44); c.allBtn:SetPoint("RIGHT", c.capRow, "RIGHT", 0, 0); c.allBtn:Show()
    anchor, ax = c.allBtn, -SP.S
  else c.allBtn:Hide() end
  if flagged > 0 then
    c.flagBtn.text:SetText(("Flagged: %d"):format(flagged)); UI.FitButton(c.flagBtn, 44)
    if anchor == c.capRow then c.flagBtn:SetPoint("RIGHT", c.capRow, "RIGHT", 0, 0) else c.flagBtn:SetPoint("RIGHT", anchor, "LEFT", ax, 0) end
    UI.SetButtonSelected(c.flagBtn, st.view == "journal" and st.flags or false)
    c.flagBtn.text:SetTextColor(C.red[1], C.red[2], C.red[3])
    c.flagBtn:Show(); anchor = c.flagBtn
  else c.flagBtn:Hide() end
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

-- Build the Gold pane into `pane` (a UI.Tabs pane). Returns a refresh function for the host to call.
function ns.BuildEconomyPane(pane)
  local c = pane
  -- state on one table: the period, the view, the journal's filter and sort
  local st = { scope = "session", view = "sources", src = nil, flags = false, sortKey = "time", sortAsc = false }
  c.st = st
  local function again() refresh(c) end
  c.refresh = again
  -- toolbar: periods at the left, the view button and the search box at the right
  c.scopeBtns = {}
  local prev
  for _, s in ipairs(SCOPES) do
    local b = UI.Button(c, s[2], 44, ROW_H, function(bb) st.scope = bb.scope; st.src, st.flags = nil, false; again() end)
    UI.FitButton(b, 44); b.scope = s[1]
    if prev then b:SetPoint("LEFT", prev, "RIGHT", SP.XS, 0) else b:SetPoint("TOPLEFT", c, "TOPLEFT", SP.S, 0) end
    c.scopeBtns[#c.scopeBtns + 1] = b; prev = b
  end
  c.pickBtn = UI.Button(c, "", 44, ROW_H, nil); c.pickBtn:SetPoint("LEFT", prev, "RIGHT", SP.XS, 0); c.pickBtn:Hide()
  c.search = UI.EditBox(c, 170, ROW_H, "search quest, item, player")
  c.search:SetPoint("TOPRIGHT", c, "TOPRIGHT", -UI.SCROLLBAR, 0)
  c.search:HookScript("OnTextChanged", again)
  c.viewBtn = UI.Button(c, "Journal", 84, ROW_H, function()
    st.view = st.view == "sources" and "journal" or "sources"
    if st.view == "sources" then st.src, st.flags = nil, false; c.search:SetText("") end
    again()
  end)
  c.viewBtn:SetPoint("RIGHT", c.search, "LEFT", -SP.S, 0)
  for _, d in ipairs(CARDS) do c[d.key] = card(c, d) end
  -- the caption line: what the list shows, with its two buttons at the right
  c.capRow = CreateFrame("Frame", nil, c); c.capRow:SetHeight(ROW_H)
  c.caption = UI.CellFS(c.capRow, "GameFontHighlightSmall", C.gold); c.caption:SetJustifyH("LEFT")
  c.allBtn = UI.Button(c.capRow, "All rows", 44, ROW_H, function() st.src, st.flags = nil, false; c.search:SetText(""); again() end)
  c.flagBtn = UI.Button(c.capRow, "Flagged", 44, ROW_H, function()
    st.flags = not (st.view == "journal" and st.flags); st.view = "journal"; st.src = nil; again()
  end)
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
  c:HookScript("OnSizeChanged", function(f, w, h) pcall(relayout, f, w, h) end)
  refresh(c)
  return again
end

-- LOOT / Gold pane (the Loot host is declared by Emitter.lua with the Items pane)
local goldRefresh, goldContent
UI.registerPane("Loot", 2, "Gold", function(content) goldContent = content; goldRefresh = ns.BuildEconomyPane(content) end,
  function() if goldRefresh then goldRefresh() end end)

-- Open the Gold pane on a period: "session", "previous", "all" or a session id (Home / Sessions, the Overview card).
-- view: "sources" (default) or "journal"; flags: true lists the flagged rows.
function Gold.open(scope, view, flags)
  UI.Open("Loot", "gold")
  if not (goldContent and goldContent.st) then return end
  local st = goldContent.st
  st.scope, st.view, st.src, st.flags = scope or "session", (flags or view == "journal") and "journal" or "sources", nil, flags and true or false
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
