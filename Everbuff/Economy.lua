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
-- The Gold pane of the LOOT tab is the single home for gold (docs/UX_PRAGMATIC.md 4.2): a period, four numbers for
-- it, and one list.
--   control  the period: Session, Today, Week, All
--   cards    BALANCE, EARNED, SPENT and NET. EARNED and SPENT say what moved with no source seen ("not traced"),
--            NET the rate per hour once the period holds 30 minutes of play. No entry counts.
--   header   the period in words, or the real range when the gold history starts inside it ("SINCE WED 18 NOV
--            20:35"); at its right the view: Sources, Auction house, Journal
--   list     Sources: one row per source with money in the period, EARNED then SPENT, what it mostly came from; a
--            click opens its rows. Not offered for a period with dungeon time from before the coin capture of 0.9.52.
--            Auction house: Spent, received and net from the ledger, then one row per trade.
--            Journal: When, Source, Detail, Place, Coords, Amount, Balance, newest first under day rows that carry
--            the day's net.

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
  mail = "Mail received", trade = "Trades received", unexplained = "Source not seen",
  repairs = "Repairs", vendor = "Bought from vendors", training = "Training", flights = "Flights",
  auctions = "Auction house", mailSpent = "Mail: postage and COD", tradeSpent = "Trades given", other = "Spending not explained",
  away = "Changed while away" }
Gold.WORD = { looted = "Loot", quests = "Quest", sold = "Vendor sale", auctionSales = "Auction sale", mail = "Mail",
  trade = "Trade", unexplained = "Unexplained", repairs = "Repair", vendor = "Vendor buy", training = "Training",
  flights = "Flight", auctions = "Auction house", mailSpent = "Mail", tradeSpent = "Trade", other = "Unexplained", away = "Away" }
-- what a journal row says for the refs of 0.9.46 (#43)
-- (a `bid` claim comes from C_AuctionHouse.PlaceBid, which is also how an item is bought out)
Gold.AUCTION_KIND = { deposit = "Deposit", bid = "Bid or buyout", buyout = "Buyout", cancel = "Auction cancelled" }
Gold.CRASH_LABEL = "Unattributed (game closed without saving)"
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
  -- the purchases and postings of the auction house (loot.ah), for the item behind an auction row
  local ahAll = db.loot and db.loot.ah
  for _, kind in ipairs({ "bought", "posted" }) do
    for _, r in ipairs(type(ahAll) == "table" and type(ahAll[kind]) == "table" and ahAll[kind] or {}) do
      if type(r) == "table" and r.s then local b = of(r.s); b[kind] = b[kind] or {}; table.insert(b[kind], r) end
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
    -- (0.9.46: a share of coin a group member looted, said by the client's own coin line)
    local from = e.loot and e.loot.src or ""
    if r.share then from = (from ~= "" and from ~= "Group share") and ("Group share, " .. from) or "Group share" end
    e.detail = from
    if r.x then e.detail = (e.detail ~= "" and (e.detail .. ", ") or "") .. r.x .. " pickups in one row" end
    e.group = r.share and "Group share" or (e.loot and e.loot.src) or "source not recorded"
  elseif src == "sold" or src == "vendor" then
    local name = itemName(r.item)
    local what = name and (name .. " x" .. (r.n or 1)) or nil
    local word = src == "sold" and " to " or " from "
    if r.kind == "buyback" then
      -- a sale taken back (0.9.46): a sold row with a negative amount
      e.detail = "Bought back: " .. (what or "an item") .. (npc and (" from " .. npc) or "")
    else
      e.detail = (what or (src == "sold" and "items" or "an item")) .. (npc and (word .. npc) or "")
      if r.x == "unmatched" then e.detail = e.detail .. ", no item asked for has this amount"; e.flag = "amount not matched" end
    end
    e.group = name or npc or "not recorded"
    local unit, n = tonumber(r.unit), tonumber(r.n)
    if src == "sold" and unit and n and unit * n > 0 then
      e.vendorPrice = unit * n
      if e.delta > unit * n then e.flag = "above vendor price" end
    end
  elseif src == "repairs" then
    e.detail = "Repair" .. (r.kind == "repairOne" and ", one item" or "") .. (npc and (" at " .. npc) or "")
    e.group = npc or "not recorded"
  elseif src == "training" or src == "flights" then
    e.detail = npc or ""
    if r.kind == "respec" then e.detail = "Talent reset" .. (npc and (" at " .. npc) or "") end
    e.group = r.kind == "respec" and "Talent reset" or npc or "not recorded"
  elseif src == "mail" or src == "auctionSales" then
    local m = e.loot and e.loot.mail
    if src == "auctionSales" and type(m) == "table" and m.item then
      e.detail = m.item .. ((type(m.buyer) == "string" and m.buyer ~= "") and (" to " .. m.buyer) or "")
      e.group = m.item
    else
      e.detail = r.sender and ("from " .. person(r.sender, nil, r.rel)) or "mailbox"
      if r.x == "unmatched" then e.detail = "mailbox, no mail taken has this amount" end
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
    -- (the item of a purchase or a posting, when its loot.ah row was found by Gold.entries: "Bought Black Lotus x3",
    -- "Deposit: Iron Bar x17". A row with no such record keeps the word of its kind.)
    local a = e.ah
    local name = a and type(a.item) == "string" and a.item ~= "" and not (ns.Market and ns.Market.guessed and ns.Market.guessed(a)) and a.item or nil
    local n = a and num(a.count) or 0
    if name and e.ahKind == "bought" then
      e.detail = "Bought " .. name .. (n > 1 and (" x" .. n) or "")
      e.group, e.qty = name, n > 0 and n or 1
    elseif name and e.ahKind == "posted" then
      e.detail = "Deposit: " .. name .. (n > 1 and (" x" .. n) or "")
      e.group = "Deposits"
    else
      e.detail = Gold.AUCTION_KIND[r.kind or ""] or "bid, buyout or deposit"
      e.group = Gold.AUCTION_KIND[r.kind or ""]
    end
  elseif src == "away" then
    -- (0.9.46: the last save was a /reload and the client then ended without saving, so what the purse did after it was never seen)
    e.detail = (r.crash and Gold.CRASH_LABEL or "while the addon was not running") .. (r.mailWaiting and ", mail was waiting" or "")
  elseif src == "unexplained" then
    e.detail = r.drift and "the purse changed and the client sent no event" or "no source seen"; e.flag = "unexplained"
  elseif src == "other" then
    e.detail = r.drift and "the purse changed and the client sent no event" or "no window was open"; e.flag = "unexplained"
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
    -- Auction rows (docs/UX_PRAGMATIC.md 4.2). Each loot.ah row is taken once, and a row is named only when
    -- nothing else could be meant:
    --   a purchase is the loot.ah.bought row of this session with exactly this price, written within TOL of the
    --   purse change. Several such rows are fine while they are the same item and count; if they differ, none is
    --   taken.
    --   a deposit is a posting within TOL, when it is the only posting that near and this is the only deposit that
    --   near to it. Postings a few seconds apart cannot be told apart by time (a posting stores no deposit, and the
    --   two clocks differ by a second or two), so their deposits stay "Deposit".
    local deps = {}
    for _, e in ipairs(out) do if e.src == "auctions" and e.delta < 0 and e.ref.kind == "deposit" then deps[#deps + 1] = e end end
    for _, e in ipairs(out) do
      if e.src == "auctions" and e.delta < 0 then
        local kind = e.ref.kind
        if kind == "deposit" then
          local hit, nPost = nil, 0
          for _, p in ipairs(b.posted or {}) do
            if math.abs(num(p.t) - e.t) <= TOL then nPost = nPost + 1; hit = p end
          end
          local nDep = 0
          if hit and nPost == 1 then
            for _, d in ipairs(deps) do if math.abs(num(hit.t) - d.t) <= TOL then nDep = nDep + 1 end end
          end
          if hit and nPost == 1 and nDep == 1 and not taken[hit] then taken[hit] = true; e.ah, e.ahKind = hit, "posted" end
        elseif kind ~= "cancel" then
          local hit, same = nil, true
          for _, p in ipairs(b.bought or {}) do
            if p.kind ~= "mail" and p.price == -e.delta and math.abs(num(p.t) - e.t) <= TOL then
              if hit and (p.item ~= hit.item or p.count ~= hit.count or p.id ~= hit.id) then same = false end
              if not hit and not taken[p] then hit = p end
            end
          end
          if hit and same then taken[hit] = true; e.ah, e.ahKind = hit, "bought" end
        end
      end
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
-- rows are the logged-in character's: a realm or account scope has totals only, of the characters the roster total
-- counts (`withStale` adds the ones not seen in 90 days, as in Gold.roster).
function Gold.scope(key, who, withStale)
  who = (who == "realm" or who == "account") and who or "char"
  local sc = { key = key, who = who, withStale = withStale and true or false, sessions = {}, ledger = {}, elapsed = 0, noJournal = 0, dropped = 0 }
  local all, cur = Gold.sessions(), current()
  local charGold = (ns.DB and ns.char and ns.char().gold) or {}
  if Gold.isDayScope(key) then
    local now = nowT()
    local p = Gold.period(key, who, now, withStale)
    sc.label, sc.days, sc.period, sc.from, sc.to, sc.elapsed = p.label, true, p, p.from, p.to, p.t
    for k, v in pairs(p.ledger) do sc.ledger[k] = v end
    if who == "char" then
      -- journal rows from before the history began have no day row to belong to: a day period lists the rows from
      -- goldSince on (2 s of slack: a row's time is rebuilt from the session's clock)
      local since = ns.DB and ns.charGuid() and num(ns.char().goldSince) or 0
      -- (sc.since: the day rows begin inside the period, so the period is counted from there and its header says
      -- so, "SINCE WED 18 NOV 20:35", docs/UX_PRAGMATIC.md 4.2)
      if since > 0 and p.from and since > p.from and since < p.to then sc.since = since end
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
    for _, blk in ipairs(Gold.whoBlocks(who, nil, withStale)) do
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
      if not a then a = { name = k, amount = 0, n = 0, qty = 0 }; by[k] = a; order[#order + 1] = a end
      -- (the units behind a group, "Black Lotus x3": only while every row of the group names them)
      if a.qty and e.qty then a.qty = a.qty + e.qty else a.qty = nil end
      -- (a buyback, 0.9.46, is a sale taken back: it counts against what it was sold for)
      local v = math.abs(e.delta)
      if e.ref and e.ref.kind == "buyback" then v = -v end
      a.amount = a.amount + v; a.n = a.n + 1
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
    -- (kept: the journal rows listed add up to the ledger's amount. Sessions whose records were picked up by the
    -- desktop app are gone with their journals, and then no "mostly from" can be named for the source.)
    local sumRows = 0
    for _, e in ipairs(list) do sumRows = sumRows + e.delta end
    out.rows[#out.rows + 1] = { key = key, label = Gold.LABEL[key], dir = dir, amount = amount, n = #list,
      share = total > 0 and amount / total or 0, top = contributors(list), kept = #list > 0 and sumRows * dir == amount }
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
Gold.DAY_CAP = 400    -- day rows per character; the older ones are folded into their month at login (Gold.fold, 0.9.47)
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
-- A day key as a date text, read from the key itself (the UTC date it names), so a label and its key always agree
-- whatever the PC's time zone and the day base are. fmt as for date(), without the "!".
function Gold.fmtKey(key, fmt)
  local y, m, d = tostring(key):match("^(%d%d%d%d)(%d%d)(%d%d)$")
  if not y then return tostring(key) end
  return noZero(date("!" .. (fmt or "%b %d"), civilDays(tonumber(y), tonumber(m), tonumber(d)) * DAY + DAY / 2))
end
-- "Nov 18" for a day key
function Gold.dayLabel(key) return Gold.fmtKey(key) end
-- the same for the start of a day (a week's first day, the edge of a gap)
function Gold.startLabel(start, base) return Gold.fmtKey(Gold.dayKey(start, base)) end
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
  -- the rate window (0.9.45) needs no day base; a failure there never stops the day row
  local okR, errR = pcall(Gold.rateCredit, key, n, at)
  if not okR then Gold._rateErr = errR end
  -- the place and the dungeon run of the credit (0.9.47) need no day base either
  local okP, errP = pcall(Gold.placeCredit, key, n, at)
  if not okP then Gold._placeErr = errP end
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
  if key == "gained" or key == "spent" then
    local okB, errB = pcall(Gold.bestNote, at)
    if not okB then Gold._placeErr = errB end
  end
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
-- active seconds: every 10 s the time since the last tick (capped at the tick length) goes to today's row and to
-- the current minute of the rate window (0.9.45), and from 0.9.47 to the place the player stands on and the dungeon
-- run it is in. Time away from the keyboard is not active time (Gold._afk, read
-- on PLAYER_FLAGS_CHANGED), and neither is time logged out (no tick runs).
function Gold.tick()
  local now = GetTime()
  local last = Gold._tickAt
  Gold._tickAt = now
  if not last or not (ns.DB and ns.charGuid()) then return end
  if Gold._afk then return end
  local add = math.floor(math.min(10, now - last) + 0.5)
  if add <= 0 then return end
  local at = nowT()
  local okR, errR = pcall(Gold.rateActive, add, at)
  if not okR then Gold._rateErr = errR end
  -- the place the player stands on and the dungeon run it is in (0.9.47)
  local okP, errP = pcall(Gold.placeActive, add, at)
  if not okP then Gold._placeErr = errP end
  local base = Gold.baseStored()
  if not base then return end
  local c = ns.char()
  c.goldDays = type(c.goldDays) == "table" and c.goldDays or {}
  local dk = Gold.dayKey(at, base)
  local r = c.goldDays[dk]
  if type(r) ~= "table" then
    -- no opening or closing balance is invented here: the day's first change sets them (o = balance before it), so
    -- a tick between the login read and the booking of a change while away cannot open the row on the new balance
    r = { g = 0, s = 0, t = 0, n = 0 }
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
  -- (the first load with the coin capture of 0.9.52, write-once: Gold.dungeonBefore)
  if plainN(c.goldShareSince) == nil then c.goldShareSince = nowT() end
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
-- the character blocks a "who" means: "char" (the logged-in one), "realm" or "account". Realm and account are the
-- characters the roster total counts, so a sum and the total beside it are of the same set: never a hidden one,
-- and one not seen in 90 days only with `withStale`.
local function whoBlocks(who, now, withStale)
  local out = {}
  if who == "realm" or who == "account" then
    for _, row in ipairs(Gold.roster(who == "realm" and "realm" or "all", withStale, now).rows) do
      if row.counted then out[#out + 1] = row.block end
    end
  elseif ns.DB and ns.charGuid() then out[1] = ns.char() end
  return out
end
Gold.whoBlocks = whoBlocks
-- A period summed from day rows: Gold.period(key, who) with key today, yesterday, week, month, last7, last30,
-- "day:YYYYMMDD" or "history" (every row); who "char", "realm" or "account". Returns { key, who, label, from, to,
-- ledger { gained, spent, away, unexplained, <sources> }, t, n, chars, gaps (characters with a change not seen on
-- this PC in the period), days[] newest first { key, start, g, s, t, n, away, o, c, src {} }, open, close }.
function Gold.period(key, who, now, withStale)
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
  local blocks = whoBlocks(who, now, withStale)
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
    -- the whole history also reads the months the oldest days were folded into (0.9.47): a row { key = "YYYYMM",
    -- folded = true, n days = the days in it }. A month's days are older than every day row kept, and its key sorts
    -- there ("202511" before "20251201", after "20251031").
    if not fromK then
      for k, r in pairs(type(blk.goldMonths) == "table" and blk.goldMonths or {}) do
        if type(k) == "string" and type(r) == "table" and k:match("^%d%d%d%d%d%d$") then
          had = true
          local d = byDay[k]
          if not d then
            d = { key = k, folded = true, start = Gold.keyStart(k .. "01", base), g = 0, s = 0, t = 0, n = 0, away = 0, nDays = 0, src = {} }
            byDay[k] = d; p.days[#p.days + 1] = d
          end
          d.g, d.s, d.t, d.n, d.away = d.g + num(r.g), d.s + num(r.s), d.t + num(r.t), d.n + num(r.n), d.away + num(r.away)
          d.nDays = math.max(d.nDays, num(r.d))
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
    end
    if had then p.chars = p.chars + 1 end
    if gap then p.gaps = p.gaps + 1 end
  end
  table.sort(p.days, function(a, b) return a.key > b.key end)
  -- a day that was played with no purse change stores no balance of its own (the 10 s ticker invents none): the
  -- purse stood where the last row before it closed
  if #blocks == 1 and type(blocks[1].goldDays) == "table" then
    for _, d in ipairs(p.days) do
      if d.c == nil and not d.folded then
        local bk
        for k, r in pairs(blocks[1].goldDays) do
          if type(k) == "string" and type(r) == "table" and k < d.key and plainN(r.c) and (not bk or k > bk) then bk = k end
        end
        if bk then d.o, d.c = plainN(blocks[1].goldDays[bk].c), plainN(blocks[1].goldDays[bk].c) end
      end
    end
  end
  for _, d in ipairs(p.days) do
    p.ledger.gained, p.ledger.spent, p.ledger.away = p.ledger.gained + d.g, p.ledger.spent + d.s, p.ledger.away + d.away
    p.t, p.n = p.t + d.t, p.n + d.n
  end
  p.ledger.unexplained = p.ledger.unexplained or 0
  if #p.days > 0 then p.close, p.open = p.days[1].c, p.days[#p.days].o end
  return p
end
-- The one resolver behind every surface: Gold.metric(id, who, when).
--   id    "balance", "earned" (everything gained), "spent", "net" (gained minus spent), "farmed" (looted coin,
--         vendor sales and quest rewards), "earnedOwn" (gained without mail and auction payouts: the Earned of
--         the per hour setting), "byMode" (farmed, earnedOwn or net, by the per hour setting), "away", "played"
--         (active seconds of a day period, the length of a session), "perHour" (net over that time, nil under 5
--         minutes), "rate" (the rolling per hour figure of the logged-in character by the per hour setting,
--         Gold.rate; nil with no active time), or a ledger source key. The figures of a ledger have one
--         definition, Gold.figure, which the farm timer and the per hour modes share.
--   who   "char" (default), "realm", "account"
--   when  a day period of Gold.period, "session", "previous", "all", a session id, or "timer" (since the farm
--         timer was started: the lifetime ledger minus its snapshot; nil when no timer runs); default "today"
function Gold.figure(id, ledger)
  if type(ledger) ~= "table" then return 0 end
  if id == "byMode" then
    local mode = Gold.rateMode()
    id = (mode == "farm" and "farmed") or (mode == "earned" and "earnedOwn") or "net"
  end
  if id == "earned" then return num(ledger.gained)
  elseif id == "net" then return num(ledger.gained) - num(ledger.spent)
  elseif id == "farmed" then return num(ledger.looted) + num(ledger.sold) + num(ledger.quests)
  elseif id == "earnedOwn" then return num(ledger.gained) - num(ledger.mail) - num(ledger.auctionSales) end
  return num(ledger[id])
end
function Gold.metric(id, who, when)
  who, when = who or "char", when or "today"
  if id == "balance" then
    if who == "char" then
      local g = ns.DB and ns.charGuid() and ns.char().gold
      return num(type(g) == "table" and g.balance)
    end
    return Gold.roster(who == "realm" and "realm" or "all").total
  end
  if id == "rate" then return Gold.rate().perHour end
  local ledger, t
  if when == "timer" then
    local tm = Gold.timer()
    if not tm then return nil end
    ledger, t = tm.ledger, tm.elapsed
  elseif Gold.isDayScope(when) then
    local p = Gold.period(when, who)
    ledger, t = p.ledger, p.t
  else
    local sc = Gold.scope(when, who)
    ledger, t = sc.ledger, sc.elapsed
  end
  if id == "played" then return num(t)
  elseif id == "perHour" then
    if num(t) < 300 then return nil end
    return Gold.figure("net", ledger) * 3600 / t
  end
  return Gold.figure(id, ledger)
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
  -- (0.9.45) the coin icons when they are on; more characters, and the week and month lines, when Settings asks
  -- for them: each widens the budget by what it adds (more characters also by the three lines that may stand
  -- beside them: the rate, the farm timer and "and N more"), so the default block stays inside 18 lines
  local fmtMoney = Gold.full
  local function signed(c) return Gold.full(c, { signed = true }) end
  local tc = Gold.tipCfg() or {}
  local rowsSet = math.max(5, math.min(30, tonumber(tc.limit) or Gold.TIP_ROWS))
  local limit = opts.limit or rowsSet
  local budget = opts.budget or (Gold.TIP_LINES + (limit > Gold.TIP_ROWS and (limit - Gold.TIP_ROWS + 3) or 0) + (tc.week == true and 1 or 0) + (tc.month == true and 1 or 0))
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
  for _, pk in ipairs({ { "week", "This week" }, { "month", "This month" } }) do
    if tc[pk[1]] == true then
      local pp = Gold.period(pk[1], "char", now)
      add(pk[2], ("%s   (in %s  ·  out %s)"):format(signed(pp.ledger.gained - pp.ledger.spent), fmtMoney(pp.ledger.gained), fmtMoney(pp.ledger.spent)))
    end
  end
  -- the rolling rate, named by its definition; dimmed while it warms up; left out before any active time
  do
    local r = Gold.rate(nil, now)
    if r.perHour then
      local name, v, note, dim = Gold.rateParts(r)
      add(name, v .. "  ·  " .. note, dim and C.dim or nil)
    end
    local tm = Gold.timer(now)
    if tm then add("Farm timer", (Gold.timerText(tm):gsub("^This farm: ", ""))) end
  end
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
    -- the header counts what the Total sums; the current character is listed even when it is not counted
    add(("%s  ·  %d character%s"):format(HEAD[filter] or HEAD.all, ro.count, ro.count == 1 and "" or "s"), nil, C.dim, true)
    for i = 1, n do
      local row = shown[i]
      local left = (row.me and "> " or "   ") .. row.label .. (row.level and ("  " .. row.level) or "")
      local right = fmtMoney(row.balance)
      if not row.me then right = right .. "   seen " .. Gold.fmtAge(row.seen, now)
      elseif not row.counted then right = right .. "   not in total" end
      local col = row.facts and C.ink or C.dim
      if not row.counted then col = C.dim
      elseif row.class and UI.ClassColor then col = { UI.ClassColor(row.class) } end
      add(left, right, col)
    end
    if n < #shown then add(("and %d more"):format(#shown - n), nil, C.dim) end
    add("Total", fmtMoney(ro.total) .. (ro.oldest and ("   oldest balance from " .. Gold.fmtDate(ro.oldest)) or ""), C.gold)
  end
  for _, t in ipairs(tail) do L[#L + 1] = t end
  while #L > budget do table.remove(L) end
  return L
end
-- opts.owner and opts.redo(owner): the frame the tooltip belongs to and the function that draws it again; while that
-- frame owns the tooltip the block follows the purse and, every 10 s, the rate (Gold.tipRedo, Gold.repaint).
function Gold.tooltip(tip, opts)
  if not tip then return 0 end
  local cfg = Gold.cfg()
  if cfg and cfg.tips == false then return 0 end
  if opts and opts.owner and opts.redo then
    Gold._tipOwner, Gold._tipRedo = opts.owner, opts.redo
    Gold.rateWatch()
  end
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

-- /eb gold, /eb gold chars, /eb gold stats and /eb gold timer: direct replies to a typed command; nothing else
-- about gold goes to chat. Returns true (the argument was a gold command).
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
    ns.msg(sum and ("this session: %s"):format(signed(sum.net)) or "this session: no session yet")
    -- the rolling rate once there is active time for it (0.9.45), else the session's net over its length
    local r = Gold.rate(nil, now)
    if r.perHour then
      local name, v, note = Gold.rateParts(r)
      ns.msg(("per hour: %s %s  ·  %s"):format(name, v, note))
    elseif sum then
      ns.msg(sum.perHour and ("per hour: %s net over this session"):format(signed(sum.perHour)) or "per hour: after 2 minutes of this session")
    else ns.msg("per hour: no session yet") end
    local tm = Gold.timer(now)
    if tm then ns.msg(Gold.timerText(tm)) end
  elseif sub == "chars" or sub == "characters" then
    for _, row in ipairs(ro.rows) do
      local tag = row.hidden and "hidden from totals" or (row.stale and "not in the total, not seen in 90 days") or nil
      ns.msg(("%s%s%s  ·  %s  ·  %s%s"):format(row.me and "> " or "", row.label, row.level and (" " .. row.level) or "",
        fmtMoney(row.balance), row.me and "you" or ("seen " .. Gold.fmtAge(row.seen, now)), tag and ("  ·  " .. tag) or ""))
    end
    ns.msg(("total: %s  ·  %s"):format(fmtMoney(ro.total), Gold.rosterLine(ro)))
  elseif sub == "stats" then
    -- today, this week and this month: in, out and net, for the character, its realm and the account
    for _, w in ipairs({ { "char", "this character" }, { "realm", "this realm" }, { "account", "account" } }) do
      local parts = {}
      for _, pk in ipairs({ { "today", "today" }, { "week", "week" }, { "month", "month" } }) do
        local p = Gold.period(pk[1], w[1], now)
        parts[#parts + 1] = ("%s %s (in %s, out %s)"):format(pk[2], signed(p.ledger.gained - p.ledger.spent), fmtMoney(p.ledger.gained), fmtMoney(p.ledger.spent))
      end
      ns.msg(("%s: %s"):format(w[2], table.concat(parts, "  ·  ")))
    end
  elseif sub == "timer" then
    Gold.timerStart(now)
    ns.msg("Farm timer started.")
  elseif sub == "audit" or sub:match("^audit%s") then
    -- the whole history, or one period: /eb gold audit today (week, month, session, ...)
    local what = sub:match("^audit%s+(%S+)") or "history"
    if not (what == "history" or what == "all" or what == "session" or what == "previous" or Gold.isDayScope(what)) then
      ns.msg("gold audit: /eb gold audit, or with a period: today, yesterday, week, month, last30, session")
    else ns.msg(Gold.auditText(Gold.audit(what, now))) end
  else
    ns.msg("gold commands: /eb gold · /eb gold chars · /eb gold stats · /eb gold timer · /eb gold audit")
  end
  return true
end

-- the model's own events: roster facts at login, level-up and logout; the day base checked at login
do
  local gf = CreateFrame("Frame")
  ns.eventFrames = ns.eventFrames or {}
  ns.eventFrames[#ns.eventFrames + 1] = gf
  -- (0.9.45: the AFK flag, the end of a fight for what waited for it, the broker objects at login, the screen size)
  for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "PLAYER_LOGOUT", "PLAYER_LOGIN", "PLAYER_FLAGS_CHANGED",
    "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED" }) do pcall(gf.RegisterEvent, gf, e) end
  local function note(tries)
    if Gold.noteChar() then
      pcall(Gold.checkBase); pcall(Gold.pillApply)
      -- (0.9.47) the month fold of this character's own rows, and the dungeon run it may have left while away
      pcall(Gold.bestNote); pcall(Gold.fold); pcall(Gold.runSync)
      return
    end
    if tries > 0 and C_Timer and type(C_Timer.After) == "function" then C_Timer.After(1, function() note(tries - 1) end) end
  end
  gf:SetScript("OnEvent", function(_, event, a1)
    if not ns.DB then return end
    if event == "PLAYER_ENTERING_WORLD" then note(5); pcall(Gold.readAfk); pcall(Gold.brokerInit)
    elseif event == "PLAYER_LEVEL_UP" then Gold.noteChar(a1)
    elseif event == "PLAYER_LOGOUT" then Gold.noteChar(); Gold.flush(true)
    elseif event == "PLAYER_LOGIN" then pcall(Gold.brokerInit)
    elseif event == "PLAYER_FLAGS_CHANGED" then
      -- (the unit is asked through the guard too: a hidden value is not compared)
      if plainS(a1) == "player" then pcall(Gold.readAfk) end
    elseif event == "PLAYER_REGEN_ENABLED" then pcall(Gold.afterCombat)
    elseif event == "PLAYER_REGEN_DISABLED" then pcall(Gold.menuClose)   -- no list of ours stays open into a fight
    elseif event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then pcall(Gold.pillPlace) end
  end)
  if C_Timer and type(C_Timer.NewTicker) == "function" then pcall(C_Timer.NewTicker, 10, function() Gold.tick() end) end
end

-- ── rate and glance (0.9.45, everbuff-wow-addon #43) ────────────────────────────────────────────────────────────
-- Everything here lives on the Gold table (no new file-level state): the rate window, the farm timer, the glance
-- texts, the gold pill, its menu, the broker objects and the settings pane.
--
-- characters[guid].goldRate = { m = { [epochMinute] = { e, s, f, a, x } }, last }: one bucket per minute of server
-- time, at most 91. e earned (the purse's gains without mail and auction payouts), s spent, f farmed (looted coin,
-- vendor sales, quest rewards), a active seconds of that minute, x the mail and auction payouts left out of e
-- (only in a minute that had one), so that Net is the purse's own net: e + x - s, the NET card's figure. A rate is the sum over the buckets of the last 90
-- minutes times 3600 over their active seconds; the window starts over after more than 30 minutes without a write
-- (logged out, or away from the keyboard). Written by Gold.dayCredit (every credit) and Gold.tick (active time).
Gold.RATE_WINDOW = 90 * 60   -- seconds of wall time a rate looks back
Gold.RATE_GAP = 30 * 60      -- a longer silence starts the window over
Gold.RATE_WARM = 300         -- active seconds under which a rate is shown dimmed
Gold.RATE_CAP = 91           -- minute buckets kept
Gold.RATE_MODES = { { "farm", "Farming" }, { "earned", "Earned" }, { "net", "Net" } }
Gold.RATE_LABEL = { farm = "Farming", earned = "Earned", net = "Net" }
Gold.RATE_WHAT = {
  farm = "looted coin, vendor sales and quest rewards",
  earned = "everything gained except mail and auction payouts",
  net = "everything gained minus everything spent",
}
Gold.RATE_NOTE = {}
for k, what in pairs(Gold.RATE_WHAT) do Gold.RATE_NOTE[k] = ("%s: %s, per hour of active time"):format(Gold.RATE_LABEL[k], what) end
Gold.FARM = { looted = true, sold = true, quests = true }
Gold.NOT_EARNED = { mail = true, auctionSales = true }

function Gold.rateMode()
  local cfg = Gold.cfg()
  local m = cfg and cfg.rateMode
  return Gold.RATE_LABEL[m] and m or "farm"
end
-- the logged-in character's window, ready for a write at `now`: started over after a gap, old minutes pruned
function Gold.rateStore(now)
  local c = ns.char()
  local r = c.goldRate
  if type(r) ~= "table" or type(r.m) ~= "table" then r = { m = {} }; c.goldRate = r end
  local last = plainN(r.last)
  if last and now - last > Gold.RATE_GAP then r.m = {} end
  local oldest = math.floor(now / 60) - (Gold.RATE_CAP - 1)
  for k in pairs(r.m) do if type(k) ~= "number" or k < oldest then r.m[k] = nil end end
  r.last = now
  return r
end
local function rateBucket(r, minute)
  local b = r.m[minute]
  if type(b) ~= "table" then b = { e = 0, s = 0, f = 0, a = 0 }; r.m[minute] = b end
  return b
end
-- One credit into its minute. A credit always counts, also while the character is away from the keyboard. Mail and
-- auction payouts were added with `gained` a moment before and are moved from `e` to `x` (they are no part of
-- Farming or Earned, and Net counts them as the purse does); transfers, away changes and every other key leave
-- the window alone.
function Gold.rateCredit(key, n, at)
  local field, sign
  if key == "gained" then field, sign = "e", 1
  elseif key == "spent" then field, sign = "s", 1
  elseif Gold.FARM[key] then field, sign = "f", 1
  elseif Gold.NOT_EARNED[key] then field, sign = "e", -1
  else return end
  if not (ns.DB and ns.charGuid()) then return end
  local now = nowT()
  at = plainN(at) or now
  local minute = math.min(math.floor(at / 60), math.floor(now / 60))
  local r = Gold.rateStore(now)
  if minute < math.floor(now / 60) - (Gold.RATE_CAP - 1) then return end
  local b = rateBucket(r, minute)
  b[field] = (plainN(b[field]) or 0) + sign * n
  if sign < 0 then b.x = (plainN(b.x) or 0) + n end
end
-- `add` active seconds into the minute of `at`
function Gold.rateActive(add, at)
  local r = Gold.rateStore(at)
  local b = rateBucket(r, math.floor(at / 60))
  b.a = math.min(60, (plainN(b.a) or 0) + add)
end
-- The rate of the logged-in character: { mode, label, sum, active, span (seconds from the first bucket to now),
-- warm (under 300 active seconds), left (seconds of warm-up left), perHour (copper, nil with no active time) }.
-- Reads only: a window past its gap reads as empty and is started over by the next write.
function Gold.rate(mode, now)
  mode = Gold.RATE_LABEL[mode] and mode or Gold.rateMode()
  now = now or nowT()
  local out = { mode = mode, label = Gold.RATE_LABEL[mode], sum = 0, active = 0, span = 0 }
  local c = ns.DB and ns.charGuid() and ns.char() or nil
  local r = c and c.goldRate
  if type(r) == "table" and type(r.m) == "table" and not (plainN(r.last) and now - r.last > Gold.RATE_GAP) then
    local cur, first = math.floor(now / 60), nil
    for k, b in pairs(r.m) do
      if type(k) == "number" and type(b) == "table" and k >= cur - (Gold.RATE_CAP - 1) and k <= cur then
        local e, s, f = num(b.e), num(b.s), num(b.f)
        out.active = out.active + num(b.a)
        out.sum = out.sum + ((mode == "farm" and f) or (mode == "earned" and e) or (e + num(b.x) - s))
        if not first or k < first then first = k end
      end
    end
    if first then out.span = math.max(0, now - first * 60) end
  end
  out.warm = out.active < Gold.RATE_WARM
  out.left = math.max(0, Gold.RATE_WARM - out.active)
  if out.active > 0 then
    local v = out.sum * 3600 / out.active
    out.perHour = v < 0 and -math.floor(-v + 0.5) or math.floor(v + 0.5)   -- half away from zero
  end
  return out
end
function Gold.resetRate()
  if not (ns.DB and ns.charGuid()) then return false end
  ns.char().goldRate = nil
  Gold.fire()
  return true
end

-- whether the character is away from the keyboard, read on PLAYER_FLAGS_CHANGED and at login. A missing function,
-- a blocked call or a secret answer counts as active; the raw answer is never tested before the guard.
function Gold.readAfk()
  local afk = false
  if type(UnitIsAFK) == "function" then
    local ok, v = pcall(UnitIsAFK, "player")
    if ok and not (issecretvalue and issecretvalue(v)) and v == true then afk = true end
  end
  Gold._afk = afk
  return afk
end

-- settings.gold.pill and settings.gold.tip: created on the first write, never by a read
function Gold.pillCfg(create)
  local cfg = Gold.cfg(create)
  if not cfg then return nil end
  if type(cfg.pill) ~= "table" then
    if not create then return nil end
    cfg.pill = { on = false, metrics = { "balance" } }
  end
  return cfg.pill
end
function Gold.tipCfg(create)
  local cfg = Gold.cfg(create)
  if not cfg then return nil end
  if type(cfg.tip) ~= "table" then
    if not create then return nil end
    cfg.tip = { limit = Gold.TIP_ROWS, week = false, month = false }
  end
  return cfg.tip
end

-- the formatter with the player's display settings: Gold.full for a tooltip or a chat line (every part of the
-- amount), Gold.fmt for a glance (pill, bar text, rates: the short form, compact when that is on)
function Gold.full(c, o)
  local cfg = Gold.cfg()
  local opts = { icons = (cfg and cfg.icons == true) or nil }
  if o then for k, v in pairs(o) do opts[k] = v end end
  return fmtMoney(c, opts)
end
function Gold.fmt(c, o)
  local cfg = Gold.cfg()
  local opts = { short = true, icons = (cfg and cfg.icons == true) or nil, compact = (cfg and cfg.compact == true) or nil }
  if o then for k, v in pairs(o) do opts[k] = v end end
  return fmtMoney(c, opts)
end
-- "18 min", "1h 05m"
function Gold.fmtSpan(sec)
  local m = math.max(1, math.floor(num(sec) / 60 + 0.5))
  if m >= 60 then return ("%dh %02dm"):format(math.floor(m / 60), m % 60) end
  return ("%d min"):format(m)
end
-- a rate as its label ("Farming"), its value ("44g 20s/h"), a note ("last 37 min" or "warming up 1:20") and whether
-- it is still warming up (shown dimmed). The label always names the definition.
function Gold.rateParts(r)
  r = r or Gold.rate()
  if not r.perHour then return r.label, "no time yet", "no active time yet", true end
  local v = Gold.fmt(r.perHour, { rate = true, signed = (r.mode == "net" or r.perHour < 0) or nil }) .. "/h"
  local note
  if r.warm then note = ("warming up %d:%02d"):format(math.floor(r.left / 60), r.left % 60)
  else note = "last " .. Gold.fmtSpan(r.span) end
  return r.label, v, note, r.warm
end

-- the status line of a pane that shows the rate: its definition and its window
-- ("Farming per hour, last 37 min: looted coin, vendor sales and quest rewards over active time")
function Gold.rateStatus(r)
  r = r or Gold.rate()
  local name, _, note = Gold.rateParts(r)
  return ("%s per hour, %s: %s over active time"):format(name, note, Gold.RATE_WHAT[r.mode])
end

-- The farm timer: characters[guid].goldTimer = { at, ledger = <every key of the lifetime ledger at the start> }.
-- It survives a /reload and a relog and never touches the recording session. Its figures are the ledger now minus
-- the snapshot, over the time since `at`.
function Gold.timerStart(now)
  if not (ns.DB and ns.charGuid()) then return false end
  local c = ns.char()
  local snap = {}
  for k, v in pairs(type(c.gold) == "table" and c.gold or {}) do
    if k ~= "balance" and plainN(v) then snap[k] = v end
  end
  c.goldTimer = { at = now or nowT(), ledger = snap }
  Gold.fire()
  return true
end
-- { at, elapsed, ledger (the difference per key), farmed, earnedOwn (gained without mail and auction payouts), net
-- (gained minus spent), mode, value (by the per hour setting), perHour (nil in the first minute) }, or nil when no
-- timer runs. The figures are Gold.figure's, the ones Gold.metric(id, "char", "timer") answers with.
function Gold.timer(now)
  local c = ns.DB and ns.charGuid() and ns.char() or nil
  local t = c and c.goldTimer
  if type(t) ~= "table" or not plainN(t.at) then return nil end
  now = now or nowT()
  local out = { at = t.at, elapsed = math.max(0, now - t.at), ledger = {} }
  local snap = type(t.ledger) == "table" and t.ledger or {}
  for k, v in pairs(type(c.gold) == "table" and c.gold or {}) do
    if k ~= "balance" then out.ledger[k] = num(v) - num(snap[k]) end
  end
  local L = out.ledger
  L.gained, L.spent = num(L.gained), num(L.spent)
  out.farmed, out.earnedOwn, out.net = Gold.figure("farmed", L), Gold.figure("earnedOwn", L), Gold.figure("net", L)
  out.mode = Gold.rateMode()
  out.value = Gold.figure("byMode", L)
  if out.elapsed >= 60 then
    local v = out.value * 3600 / out.elapsed
    out.perHour = v < 0 and -math.floor(-v + 0.5) or math.floor(v + 0.5)
  end
  return out
end
-- "This farm: +12g 00s in 18 min  ·  40g 00s/h"
function Gold.timerText(t)
  t = t or Gold.timer()
  if not t then return "No farm timer. Start one with /eb gold timer." end
  local s = ("This farm: %s in %s"):format(Gold.fmt(t.value, { signed = true }), Gold.fmtSpan(t.elapsed))
  if t.perHour then s = s .. SEP .. Gold.fmt(t.perHour, { rate = true, signed = t.perHour < 0 or nil }) .. "/h" end
  return s
end

-- Reset gold history, for the logged-in character only (#43, rule 44): the day rows, the month rows, the records
-- (the best day and session are read from those rows and begin again with them), the rate window and the farm timer
-- go, and the history starts now. The lifetime ledger and the balance stay (the backend reads them), and so do the
-- places and the dungeon runs, which are counted on their own and are not part of the day history.
function Gold.resetHistory(now)
  if not (ns.DB and ns.charGuid()) then return false end
  local c = ns.char()
  c.goldDays, c.goldMonths, c.goldRate, c.goldTimer, c.goldBest = nil, nil, nil, nil, nil
  c.goldSince = now or nowT()
  Gold._held = nil
  Gold.fire()
  return true
end

-- ── glance texts: the seven values a pill or a bar can show ────────────────────────────────────────────────────
-- (the dungeon run from 0.9.51, everbuff-wow-addon #51 decision 8: "Deadmines 18m · 3/7 · +0:41", Runs.glance)
Gold.GLANCE = { { "balance", "Balance" }, { "total", "Account total" }, { "session", "Session net" }, { "today", "Today net" },
  { "rate", "Per hour" }, { "timer", "Farm timer" }, { "dungeon", "Dungeon run" } }
Gold.GLANCE_LABEL = {}
for _, g in ipairs(Gold.GLANCE) do Gold.GLANCE_LABEL[g[1]] = g[2] end
local function dimText(s)
  return ("|cff%02x%02x%02x%s|r"):format(math.floor(C.dim[1] * 255 + 0.5), math.floor(C.dim[2] * 255 + 0.5), math.floor(C.dim[3] * 255 + 0.5), s)
end
-- the text of one value; `label` puts its name before it (a rate and the farm timer always name themselves)
function Gold.glance(id, label)
  if not (ns.DB and ns.charGuid()) then return "" end
  local function named(name, s) return label and (name .. " " .. s) or s end
  if id == "total" then
    return named("All", Gold.fmt(Gold.roster((Gold.cfg() or {}).filter or "all").total))
  elseif id == "session" then
    local cur = current()
    return named("Session", Gold.fmt(cur and (num(cur.gained) - num(cur.spent)) or 0, { signed = true }))
  elseif id == "today" then
    return named("Today", Gold.fmt(Gold.metric("net", "char", "today"), { signed = true }))
  elseif id == "rate" then
    local name, v, _, dim = Gold.rateParts()
    return dim and dimText(name .. " " .. v) or (name .. " " .. v)
  elseif id == "timer" then
    local t = Gold.timer()
    if not t then return "Farm timer off" end
    return ("Farm %s in %s"):format(Gold.fmt(t.value, { signed = true }), Gold.fmtSpan(t.elapsed))
  elseif id == "dungeon" then
    local ok, s = pcall(function() return ns.Runs and ns.Runs.glance and ns.Runs.glance() end)
    if ok and type(s) == "string" then return s end
    return dimText("No dungeon run")
  end
  return named("Balance", Gold.fmt(Gold.metric("balance")))
end

-- ── the gold pill (opt-in: settings.gold.pill.on) ───────────────────────────────────────────────────────────────
-- One line of text on the screen showing one or two glance values. No frame exists while it is off. Left-click
-- opens Loot > Gold (after the fight when in combat), right-click opens the menu, a drag moves it. Its place is
-- kept relative to the nearest screen corner, inside the screen and clear of the flag and of the whole reach of
-- its notification line (the flag is what the desktop app reads): the line grows to Emitter.TOAST_MAX_W (600) at
-- the flag's size, inward from the flag's corner. Its text follows the purse in the frame of the change, in combat
-- too; nothing is moved, resized, shown or hidden in combat (a text that got longer than the pill is cut short
-- inside it until the fight ends).
Gold.PILL_H = 22
Gold.PILL_SCALE = { 0.5, 2 }
Gold.PILL_ALPHA = { 0.2, 1 }
Gold.FLAG_W, Gold.FLAG_H, Gold.FLAG_MARGIN = 600, 40, 8   -- FLAG_W only when the Emitter does not say (TOAST_MAX_W)
function Gold.flagW()
  local w = ns.Emitter and tonumber(ns.Emitter.TOAST_MAX_W)
  return (w and w > 0) and w or Gold.FLAG_W
end
local CORNER_OK = { TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true }
local function clampN(v, lo, hi) v = tonumber(v) or lo; if v ~= v then v = lo end; return math.max(lo, math.min(hi, v)) end
function Gold.inCombat()
  local a = type(InCombatLockdown) == "function" and InCombatLockdown()
  local b = type(UnitAffectingCombat) == "function" and UnitAffectingCombat("player")
  return (a or b) and true or false
end
function Gold.pillMetrics()
  local pc = Gold.pillCfg()
  local out = {}
  for _, m in ipairs(pc and type(pc.metrics) == "table" and pc.metrics or {}) do
    if Gold.GLANCE_LABEL[m] and #out < 2 and out[1] ~= m then out[#out + 1] = m end
  end
  if #out == 0 then out[1] = "balance" end
  return out
end
function Gold.pillText()
  local pc = Gold.pillCfg()
  local parts = {}
  for _, m in ipairs(Gold.pillMetrics()) do parts[#parts + 1] = Gold.glance(m, pc and pc.label == true) end
  return table.concat(parts, SEP)
end
-- The offsets of a w x h pill whose `corner` sits x, y from the same corner of a sw x sh screen, moved the least
-- that brings all of it inside the screen. All in screen units.
function Gold.pillClamp(corner, x, y, w, h, sw, sh)
  local right, top = corner:find("RIGHT") ~= nil, corner:find("TOP") ~= nil
  local ax, ay = right and -x or x, top and -y or y   -- the distance inward from the corner
  ax = math.max(0, math.min(ax, math.max(0, sw - w)))
  ay = math.max(0, math.min(ay, math.max(0, sh - h)))
  return right and -ax or ax, top and -ay or ay
end
-- the left and bottom edge of that pill
function Gold.cornerRect(corner, x, y, w, h, sw, sh)
  local right, top = corner:find("RIGHT") ~= nil, corner:find("TOP") ~= nil
  return right and (sw + x - w) or x, top and (sh + y - h) or y
end
-- the corner nearest to a rectangle, and its offsets from it
function Gold.nearestCorner(l, b, w, h, sw, sh)
  local right, top = (l + w / 2) > sw / 2, (b + h / 2) > sh / 2
  return (top and "TOP" or "BOTTOM") .. (right and "RIGHT" or "LEFT"), right and (l + w - sw) or l, top and (b + h - sh) or b
end
-- where the flag and its notification line at its widest are: { l, b, w, h } in screen units, from the saved flag
-- settings
function Gold.flagRect(sw, sh)
  local st = (ns.DB and ns.DB.settings) or {}
  local sc = clampN(st.flagScale, 1, 1.5)
  local w, h = Gold.flagW() * sc, Gold.FLAG_H * sc
  local corner, x, y = st.emitCorner, 0, 0
  local pos = st.flagPos
  if type(pos) == "table" and CORNER_OK[pos.point] then corner, x, y = pos.point, num(pos.x) * sc, num(pos.y) * sc end
  if not CORNER_OK[corner] then corner = "TOPLEFT" end
  local l, b = Gold.cornerRect(corner, x, y, w, h, sw, sh)
  return { l = l, b = b, w = w, h = h }
end
-- A pill that would lie over the flag (with 8 px of air) is moved off it: under the flag when the flag is in the
-- top half of the screen, above it otherwise, and sideways when there is no room. Returns the left and bottom edge.
function Gold.pillClear(l, b, w, h, fr, sw, sh)
  local m = Gold.FLAG_MARGIN
  local fl, fb, fw, fh = fr.l - m, fr.b - m, fr.w + 2 * m, fr.h + 2 * m
  if l >= fl + fw or l + w <= fl or b >= fb + fh or b + h <= fb then return l, b end
  local nb = (fb + fh / 2 > sh / 2) and (fb - h) or (fb + fh)
  if nb >= 0 and nb + h <= sh then return l, nb end
  local nl = (fl + fw / 2 > sw / 2) and (fl - w) or (fl + fw)
  return math.max(0, math.min(nl, math.max(0, sw - w))), b
end
local function screenSize()
  local okW, sw = pcall(UIParent.GetWidth, UIParent)
  local okH, sh = pcall(UIParent.GetHeight, UIParent)
  return (okW and tonumber(sw)) or 0, (okH and tonumber(sh)) or 0
end
-- Put the pill where its settings say, inside the screen and clear of the flag, and save the place it ended at
-- (so a new pill is saved the moment it is created). Not in combat, except for the first placing of a new pill.
function Gold.pillPlace()
  local p = Gold.pill
  if not p then return false end
  if Gold.inCombat() and p._placed then Gold._pillDirty = true; return false end
  local pc = Gold.pillCfg(true)
  local sw, sh = screenSize()
  local sc = clampN(pc.scale or 1, Gold.PILL_SCALE[1], Gold.PILL_SCALE[2])
  local okW, pw = pcall(p.GetWidth, p)
  local w, h = ((okW and tonumber(pw)) or 80) * sc, Gold.PILL_H * sc
  local corner = CORNER_OK[pc.corner] and pc.corner or "TOPLEFT"
  local x, y = plainN(pc.x), plainN(pc.y)
  -- the default: under the row of the flag at its biggest (the notification line runs sideways, never down)
  if not (x and y) then corner, x, y = "TOPLEFT", Gold.FLAG_MARGIN, -(Gold.FLAG_H * 1.5 + Gold.FLAG_MARGIN) end
  if sw > 0 and sh > 0 then
    x, y = Gold.pillClamp(corner, x, y, w, h, sw, sh)
    local l, b = Gold.cornerRect(corner, x, y, w, h, sw, sh)
    local l2, b2 = Gold.pillClear(l, b, w, h, Gold.flagRect(sw, sh), sw, sh)
    if l2 ~= l or b2 ~= b then
      corner, x, y = Gold.nearestCorner(l2, b2, w, h, sw, sh)
      x, y = Gold.pillClamp(corner, x, y, w, h, sw, sh)
    end
  end
  pc.corner, pc.x, pc.y = corner, math.floor(x + 0.5), math.floor(y + 0.5)
  p:ClearAllPoints()
  p:SetPoint(corner, UIParent, corner, pc.x / sc, pc.y / sc)
  p._placed = true
  return true
end
-- The flag was moved, snapped to a corner or resized (Emitter.setFlagPos, setCorner, setFlagScale): a pill on screen
-- is placed again, so it makes way.
function Gold.flagMoved()
  local p = Gold.pill
  if not (p and p:IsShown()) then return false end
  return Gold.pillPlace()
end
-- the width of the pill's whole text, whatever width the text is held to
function Gold.pillTextW(p)
  local fs = p.text
  local get = type(fs.GetUnboundedStringWidth) == "function" and fs.GetUnboundedStringWidth or fs.GetStringWidth
  local ok, tw = pcall(get, fs)
  return math.ceil((ok and tonumber(tw)) or 0)
end
-- the text, and (out of combat) the width that fits it. In combat the pill keeps its size: a text that got longer
-- than it is held to the pill's inner width (one line, cut short by the client), so nothing is drawn outside it.
function Gold.pillUpdate()
  local p = Gold.pill
  if not (p and p:IsShown()) then return end
  local text = Gold.pillText()
  if text ~= p._text then p._text = text; p.text:SetText(text) end
  if Gold.inCombat() and p._placed then
    Gold._pillDirty = true
    local inner = (p._wSet or 0) - 2 * SP.S
    if not p._held and inner > 0 and Gold.pillTextW(p) > inner then p._held = true; p.text:SetWidth(inner) end
    return
  end
  if p._held then p._held = nil; p.text:SetWidth(0) end   -- 0: as wide as its text again
  local w = Gold.pillTextW(p) + 2 * SP.S
  if w ~= p._wSet then
    p._wSet = w
    p:SetSize(w, Gold.PILL_H)
    Gold.pillPlace()
  end
end
function Gold.pillTip(p)
  if not (GameTooltip and type(GameTooltip.SetOwner) == "function") then return end
  local pc = Gold.pillCfg() or {}
  local top = not (type(pc.corner) == "string" and pc.corner:find("BOTTOM"))
  local right = type(pc.corner) == "string" and pc.corner:find("RIGHT") ~= nil
  GameTooltip:SetOwner(p, "ANCHOR_NONE")
  GameTooltip:ClearAllPoints()
  if top then GameTooltip:SetPoint(right and "TOPRIGHT" or "TOPLEFT", p, right and "BOTTOMRIGHT" or "BOTTOMLEFT", 0, -6)
  else GameTooltip:SetPoint(right and "BOTTOMRIGHT" or "BOTTOMLEFT", p, right and "TOPRIGHT" or "TOPLEFT", 0, 6) end
  GameTooltip:AddLine("everbuff.gg gold")
  GameTooltip:AddLine("Left-click: open gold   Right-click: menu   Drag: move", 0.7, 0.7, 0.7)
  Gold.tooltip(GameTooltip, { owner = p, redo = Gold.pillTip })
  GameTooltip:Show()
end
function Gold.pillBuild()
  local p = UI.Panel(UIParent)
  if p.SetFrameStrata then p:SetFrameStrata("MEDIUM") end
  p:SetSize(80, Gold.PILL_H)
  p:SetMovable(true); p:SetClampedToScreen(true); p:EnableMouse(true)
  p:RegisterForDrag("LeftButton")
  p.text = UI.FS(p, "GameFontHighlightSmall", C.gold)
  if p.text.SetWordWrap then p.text:SetWordWrap(false) end
  p.text:SetPoint("CENTER", p, "CENTER", 0, 0)
  p:SetScript("OnDragStart", function(s)
    local pc = Gold.pillCfg() or {}
    if pc.locked == true then return end
    if ns.blockedInCombat and ns.blockedInCombat() then return end
    s._dragging = true
    s:StartMoving()
  end)
  p:SetScript("OnDragStop", function(s)
    if not s._dragging then return end
    s:StopMovingOrSizing()
    s._dragging, s._draggedAt = nil, GetTime()
    local pc = Gold.pillCfg(true)
    local sw, sh = screenSize()
    local sc = clampN(pc.scale or 1, Gold.PILL_SCALE[1], Gold.PILL_SCALE[2])
    local okL, l = pcall(s.GetLeft, s)
    local okB, b = pcall(s.GetBottom, s)
    local okW, w = pcall(s.GetWidth, s)
    if okL and okB and okW and tonumber(l) and tonumber(b) and sw > 0 then
      -- the frame answers in its own scaled units: times the scale is screen units
      pc.corner, pc.x, pc.y = Gold.nearestCorner(l * sc, b * sc, (tonumber(w) or 80) * sc, Gold.PILL_H * sc, sw, sh)
    end
    Gold.pillPlace()
  end)
  p:SetScript("OnMouseUp", function(s, button)
    if s._dragging or (s._draggedAt and GetTime() - s._draggedAt < 0.2) then return end
    if button == "RightButton" then Gold.menu(s) else Gold.openSoon() end
  end)
  p:SetScript("OnEnter", function(s) pcall(Gold.pillTip, s) end)
  p:SetScript("OnLeave", function() if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end end)
  return p
end
-- Make the screen match the settings: build, show, scale and place the pill when it is on, hide it when it is off.
-- Returns false when it had to wait (combat, or the character not known yet).
function Gold.pillApply()
  local pc = Gold.pillCfg()
  local on = pc ~= nil and pc.on == true
  local p = Gold.pill
  if not on and not p then Gold.rateWatch(); return true end
  if Gold.inCombat() and p then Gold._pillDirty = true; return false end   -- shown, hidden and scaled after the fight
  if not on then
    p:Hide()
    Gold.rateWatch()
    return true
  end
  if not (ns.DB and ns.charGuid()) then return false end
  if not p then p = Gold.pillBuild(); Gold.pill = p end
  pc = Gold.pillCfg(true)
  if type(pc.metrics) ~= "table" or #pc.metrics == 0 then pc.metrics = { "balance" } end
  p:SetScale(clampN(pc.scale or 1, Gold.PILL_SCALE[1], Gold.PILL_SCALE[2]))
  p:SetAlpha(clampN(pc.alpha or 1, Gold.PILL_ALPHA[1], Gold.PILL_ALPHA[2]))
  p:Show()
  p._text, p._wSet = nil, nil
  Gold.pillUpdate()
  Gold.pillPlace()
  Gold.rateWatch()
  return true
end
-- the setters behind the menu and Settings; each returns false when combat made it wait
function Gold.pillOn(on)
  if ns.blockedInCombat and ns.blockedInCombat() then return false end
  local pc = Gold.pillCfg(true)
  pc.on = on and true or false
  pc.asked = true
  return Gold.pillApply()
end
function Gold.pillSet(i, id)
  local pc = Gold.pillCfg(true)
  local m = Gold.pillMetrics()
  if i == 1 then
    if not Gold.GLANCE_LABEL[id] then return end
    m[1] = id
    if m[2] == id then m[2] = nil end
  else
    m[2] = (Gold.GLANCE_LABEL[id] and id ~= m[1]) and id or nil
  end
  pc.metrics = m
  Gold.pillUpdate(); Gold.rateWatch()
end
function Gold.pillOpt(key, v)
  local pc = Gold.pillCfg(true)
  if key == "scale" then pc.scale = math.floor(clampN(v, Gold.PILL_SCALE[1], Gold.PILL_SCALE[2]) * 20 + 0.5) / 20
  elseif key == "alpha" then pc.alpha = math.floor(clampN(v, Gold.PILL_ALPHA[1], Gold.PILL_ALPHA[2]) * 20 + 0.5) / 20
  elseif key == "locked" or key == "label" then pc[key] = v and true or false
  elseif key == "pos" then pc.corner, pc.x, pc.y = nil, nil, nil end
  if pc.on == true then return Gold.pillApply() end
  return true
end
-- Left-click on the pill or a bar text: open Loot > Gold, after the fight when in combat (nothing opens in combat)
function Gold.openSoon()
  if Gold.inCombat() then Gold._openAfter = GetTime(); return false end
  Gold._openAfter = nil
  Gold.open("today")
  return true
end
function Gold.afterCombat()
  if Gold._pillDirty then
    Gold._pillDirty = nil
    local p = Gold.pill
    if p then p._wSet = nil end
    pcall(Gold.pillApply)
  end
  local at = Gold._openAfter
  Gold._openAfter = nil
  if at and GetTime() - at < 300 then pcall(Gold.open, "today") end
end

-- ── the menu of the pill and the bar texts ─────────────────────────────────────────────────────────────────────
-- Gold.menuItems() is the menu as data: { kind = "title" | "radio" | "check" | "button" | "sub", text, checked(),
-- pick(), items }. Gold.menu(owner) shows it with the client's MenuUtil when that is there and works, else with the
-- addon's own list frame. Never UIDropDownMenu (it spreads taint).
function Gold.menuItems()
  local items = { { kind = "title", text = "Show" } }
  for _, g in ipairs(Gold.GLANCE) do
    items[#items + 1] = { kind = "radio", text = g[2], checked = function() return Gold.pillMetrics()[1] == g[1] end,
      pick = function() Gold.pillSet(1, g[1]) end }
  end
  local second = { { kind = "radio", text = "None", checked = function() return Gold.pillMetrics()[2] == nil end, pick = function() Gold.pillSet(2, nil) end } }
  for _, g in ipairs(Gold.GLANCE) do
    second[#second + 1] = { kind = "radio", text = g[2], checked = function() return Gold.pillMetrics()[2] == g[1] end,
      pick = function() Gold.pillSet(2, g[1]) end }
  end
  items[#items + 1] = { kind = "sub", text = "Second value", items = second }
  items[#items + 1] = { kind = "check", text = "Show label", checked = function() return (Gold.pillCfg() or {}).label == true end,
    pick = function() Gold.pillOpt("label", not ((Gold.pillCfg() or {}).label == true)) end }
  items[#items + 1] = { kind = "button", text = Gold.timer() and "Restart farm timer" or "Start farm timer", pick = function() Gold.timerStart() end }
  items[#items + 1] = { kind = "button", text = "Reset per hour", pick = function() Gold.resetRate() end }
  items[#items + 1] = { kind = "check", text = "Lock", checked = function() return (Gold.pillCfg() or {}).locked == true end,
    pick = function() Gold.pillOpt("locked", not ((Gold.pillCfg() or {}).locked == true)) end }
  local on = (Gold.pillCfg() or {}).on == true
  items[#items + 1] = { kind = "button", text = on and "Hide" or "Show the gold pill", pick = function() Gold.pillOn(not on) end }
  items[#items + 1] = { kind = "button", text = "Open gold", pick = function() Gold.openSoon() end }
  return items
end
function Gold.menuBuild(root, items)
  for _, it in ipairs(items) do
    if it.kind == "title" then root:CreateTitle(it.text)
    elseif it.kind == "radio" then root:CreateRadio(it.text, it.checked, it.pick)
    elseif it.kind == "check" then root:CreateCheckbox(it.text, it.checked, it.pick)
    elseif it.kind == "sub" then Gold.menuBuild(root:CreateButton(it.text), it.items)
    else root:CreateButton(it.text, it.pick) end
  end
end
-- The addon's own list: one button per entry under `owner`; a selected radio or a ticked box is drawn selected, a
-- sub list replaces the list (with a way back), a click on anything else picks and closes. A second call for the
-- same owner closes it.
function Gold.ownMenu(owner, items, keep)
  local m = Gold._menu
  if not m then
    m = UI.Panel(UIParent)
    if m.SetFrameStrata then m:SetFrameStrata("DIALOG") end
    m:SetClampedToScreen(true); m:EnableMouse(true)
    m.btns = {}
    m:Hide()
    Gold._menu = m
  end
  if not keep and m:IsShown() and m.owner == owner then m:Hide(); m.owner = nil; return m end
  -- the list goes when what it hangs under goes (the window closed, another tab, the pill hidden): hooked once
  m.hooked = m.hooked or setmetatable({}, { __mode = "k" })
  if type(owner) == "table" and not m.hooked[owner] and type(owner.HookScript) == "function" then
    m.hooked[owner] = true
    pcall(owner.HookScript, owner, "OnHide", function(o) Gold.menuClose(o) end)
  end
  m.owner, m.items = owner, items
  local rows = {}
  for _, it in ipairs(items) do rows[#rows + 1] = it end
  if not keep then m.root = items end
  if items ~= m.root then table.insert(rows, 1, { kind = "back", text = "‹ Back" }) end
  rows[#rows + 1] = { kind = "close", text = "Close" }
  local wmax = 0
  for i, it in ipairs(rows) do
    local b = m.btns[i]
    if not b then
      b = UI.Button(m, "", 44, ROW_H, function(bb)
        local e = bb.item
        if not e or e.kind == "title" then return end
        if e.kind == "sub" then Gold.ownMenu(m.owner, e.items, true); return end
        if e.kind == "back" then Gold.ownMenu(m.owner, m.root, true); return end
        m:Hide(); m.owner = nil
        if e.pick then e.pick() end
      end)
      m.btns[i] = b
    end
    b.item = it
    b.text:SetText(it.kind == "sub" and (it.text .. "  ›") or it.text)
    UI.FitButton(b, 44)
    local sel = (it.kind == "radio" or it.kind == "check") and it.checked and it.checked() or false
    UI.SetButtonSelected(b, sel and true or false)
    if it.kind == "title" then b.text:SetTextColor(C.dim[1], C.dim[2], C.dim[3]) elseif not sel then b.text:SetTextColor(C.ink[1], C.ink[2], C.ink[3]) end
    local ok, bw = pcall(b.GetWidth, b)
    wmax = math.max(wmax, ok and tonumber(bw) or 0)
    b:Show()
  end
  for i = #rows + 1, #m.btns do m.btns[i]:Hide() end
  for i = 1, #rows do
    local b = m.btns[i]
    b:ClearAllPoints(); b:SetPoint("TOPLEFT", m, "TOPLEFT", SP.XS, -SP.XS - (i - 1) * (ROW_H + 2)); b:SetWidth(wmax)
  end
  m.count = #rows
  m:SetSize(wmax + 2 * SP.XS, #rows * (ROW_H + 2) - 2 + 2 * SP.XS)
  m:ClearAllPoints()
  m:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
  m:Show()
  return m
end
-- Close the own list: always, or only when it hangs under `owner`. Called when its owner hides, when the settings
-- pane is drawn again or turns its page, and when a fight starts.
function Gold.menuClose(owner)
  local m = Gold._menu
  if not m or (owner ~= nil and m.owner ~= owner) then return false end
  local was = m:IsShown() and true or false
  m:Hide(); m.owner = nil
  return was
end
-- Show the menu under `owner`. Returns "MenuUtil" or "own", or false in combat (nothing opens in combat).
-- The client's menu counts as open when its entries were built during the call, or when the call handed back a
-- menu and builds its entries later. A call that throws, a root without the methods, or a call that hands back
-- nothing and builds nothing: the own list, now and for the rest of the session. A client that builds the entries
-- only after the call returned takes its menu back the moment it does (the own list closes).
function Gold.menu(owner, items)
  if ns.blockedInCombat and ns.blockedInCombat() then return false end
  items = items or Gold.menuItems()
  if not Gold._menuFail and type(MenuUtil) == "table" and type(MenuUtil.CreateContextMenu) == "function" then
    local ran, built, returned = false, false, false
    local ok, handle = pcall(MenuUtil.CreateContextMenu, owner, function(_, root)
      ran = true
      built = pcall(Gold.menuBuild, root, items)
      if not returned then return end
      if built then Gold._menuFail = nil; Gold.menuClose(owner) else Gold._menuFail = true end
    end)
    returned = true
    if ok and built then return "MenuUtil" end
    if ok and not ran and handle ~= nil then return "MenuUtil" end
    Gold._menuFail = true   -- this client's menu does not work for us: the own list from now on
  end
  Gold.ownMenu(owner, items)
  return "own"
end

-- ── bar text: LibDataBroker data sources, only when another addon brought the library (#43, decision 18) ─────────
Gold.BROKER = { { "balance", "everbuff.gg Balance" }, { "total", "everbuff.gg Account total" }, { "today", "everbuff.gg Today" },
  { "rate", "everbuff.gg Per hour" }, { "dungeon", "everbuff.gg Dungeon" } }
function Gold.brokerInit()
  if Gold._broker then return true end
  local LS = rawget(_G, "LibStub")   -- another addon's library, not a client function
  if LS == nil then return false end
  local ok, ldb = pcall(function() return LS:GetLibrary("LibDataBroker-1.1", true) end)
  if not ok or type(ldb) ~= "table" or type(ldb.NewDataObject) ~= "function" then return false end
  local objs = {}
  for _, b in ipairs(Gold.BROKER) do
    local okN, obj = pcall(ldb.NewDataObject, ldb, b[2], { type = "data source", label = b[2], text = "",
      icon = "Interface\\AddOns\\EverbuffJournal\\media\\mark",
      OnClick = function(frame, button) if button == "RightButton" then Gold.menu(frame) else Gold.openSoon() end end,
      OnTooltipShow = function(tip)
        if not (tip and tip.AddLine) then return end
        tip:AddLine("everbuff.gg gold")
        pcall(Gold.tooltip, tip)
      end })
    if okN and type(obj) == "table" then objs[#objs + 1] = { id = b[1], obj = obj } end
  end
  if #objs == 0 then return false end
  Gold._broker = objs
  Gold.brokerUpdate()
  Gold.rateWatch()
  return true
end
function Gold.brokerUpdate()
  for _, o in ipairs(Gold._broker or {}) do
    local ok, text = pcall(Gold.glance, o.id, false)
    if ok and text ~= o.text then
      o.text = text
      pcall(function() o.obj.text = text end)
    end
  end
end

-- ── the 10 s repaint: a rate moves with time, so what shows one is drawn again every 10 s, and only then ────────
-- A rate is on screen when the pill shows one (or the farm timer), a bar text exists, one of our tooltips is open
-- or the Gold pane is showing. With none of them there is no ticker.
function Gold.rateOnScreen()
  local p = Gold.pill
  if p and p:IsShown() then
    for _, m in ipairs(Gold.pillMetrics()) do if m == "rate" or m == "timer" or m == "dungeon" then return true end end
  end
  if Gold._broker then return true end
  if Gold._tipOwner and GameTooltip and type(GameTooltip.IsOwned) == "function" and GameTooltip:IsOwned(Gold._tipOwner) == true then return true end
  if Gold.paneShowing and Gold.paneShowing() then return true end
  return false
end
function Gold.rateWatch()
  local need = Gold.rateOnScreen()
  local tk = Gold._rateTicker
  if tk and not need then
    if type(tk.Cancel) == "function" then pcall(tk.Cancel, tk) end
    Gold._rateTicker = nil
  elseif need and not tk and C_Timer and type(C_Timer.NewTicker) == "function" then
    local ok, t = pcall(C_Timer.NewTicker, 10, function() Gold.repaint() end)
    Gold._rateTicker = ok and t or nil
  end
end
function Gold.tipRedo()
  local owner, redo = Gold._tipOwner, Gold._tipRedo
  if not (owner and redo) then return end
  if GameTooltip and type(GameTooltip.IsOwned) == "function" and GameTooltip:IsOwned(owner) == true then pcall(redo, owner)
  else Gold._tipOwner, Gold._tipRedo = nil, nil end
end
function Gold.repaint()
  if not Gold.rateOnScreen() then Gold.rateWatch(); return end
  pcall(Gold.pillUpdate); pcall(Gold.brokerUpdate); pcall(Gold.tipRedo)
  if Gold.paneRate then pcall(Gold.paneRate) end
end
-- every surface follows the purse in the frame of the change
Gold.onChange(function() pcall(Gold.pillUpdate); pcall(Gold.brokerUpdate); pcall(Gold.tipRedo) end)

-- The gold block on the flag's tooltip, under its four help lines. Built and switched off in code: the flag is what
-- the desktop app reads, and a taller tooltip beside it waits for the desktop's replay of its fixtures (decision
-- 3c). No setting and no control turns it on; the release that carries the replay result sets FLAG_TIP.
Gold.FLAG_TIP = false
function Gold.flagTip(tip, flag)
  if Gold.FLAG_TIP ~= true then return 0 end
  return Gold.tooltip(tip, { owner = flag, redo = function(f)
    local h = f and f.GetScript and f:GetScript("OnEnter")
    if h then h(f) end
  end })
end

-- the first-run question of the pill (#43, decision 4): asked once, in the Gold pane, until it is answered or the
-- pill was turned on some other way
function Gold.pillAskDue()
  if not (ns.DB and ns.charGuid()) then return false end
  local pc = Gold.pillCfg()
  return not (pc and (pc.asked == true or pc.on == true))
end
function Gold.pillAnswer(yes)
  if yes then return Gold.pillOn(true) end
  Gold.pillCfg(true).asked = true
  return true
end

-- ── showcase: zones, runs, months, records, audit (0.9.47, everbuff-wow-addon #43) ──────────────────────────────
-- Everything here is written into the logged-in character's block only, at the moment of the credit or the tick:
--   goldZones[uiMapID] = { looted, quests, secs, last, name }   coin by place: looted coin and quest rewards only,
--                        measured, on the map the player stands on at the purse change (the key is the map id, never
--                        the zone's name; 0 when the client names no map). At most Gold.ZONE_CAP places: the one
--                        visited longest ago goes into goldZonesEvicted { n, looted, quests, secs }, so the table
--                        still sums to what was counted.
--   goldRun            the dungeon run that is open: { t, inst, secs, looted, quests, lootValue, items, wait, left }
--   goldRuns[]         the last Gold.RUN_CAP closed runs { t, inst, secs, looted, quests, lootValue, items, unpriced },
--                        oldest first; an older one goes into goldRunsEvicted { n, looted, quests, secs, lootValue, items, unpriced }.
--                        A run begins and ends where the addon's own dungeon detection says so (Emitter.checkInstance,
--                        names through Emitter.canonInstance), and going back in within 20 minutes continues it, as
--                        on Combat > Dungeons. Vendor sales and repairs are never given to a run.
--   goldMonths[YYYYMM] the day rows past the 400 kept, folded into their month (the row shape of a day, plus d, the
--                        days folded in), kept forever
--   goldBest           { day = { key, net, was }, session = { at, net, was } }: the best day and session by net,
--                        stored when set, so the fold cannot change a record
-- lootValue is an estimate: the vendor price of the items looted in the run. It is never added to coin and never
-- part of a rate. An item whose price the client has not loaded counts 0 until it has (`wait`), and the value then
-- reads "so far".
Gold.ZONE_CAP = 300
Gold.RUN_CAP = 50
Gold.RUN_REENTER = 20 * 60
Gold.PLACE = { looted = true, quests = true }   -- the sources a place and a run count (#43 rule 45)
Gold.NO_MAP = "Unknown place"

-- the map the player stands on: id (0 when the client names none), name (nil when it has none)
function Gold.mapNow()
  local id, name
  if C_Map and type(C_Map.GetBestMapForUnit) == "function" then
    local ok, v = pcall(C_Map.GetBestMapForUnit, "player")
    id = ok and plainN(v) or nil
  end
  if id and C_Map and type(C_Map.GetMapInfo) == "function" then
    local ok, info = pcall(C_Map.GetMapInfo, id)
    name = ok and type(info) == "table" and plainS(info.name) or nil
  end
  if not name and type(GetRealZoneText) == "function" then
    local ok, v = pcall(GetRealZoneText)
    name = ok and plainS(v) or nil
  end
  return id and math.floor(id) or 0, name
end

-- the row of the place the player stands on, created on the first credit or tick there; a place past the cap makes
-- room by moving the one visited longest ago into the evicted sums
function Gold.zoneRow(c, at)
  local id, name = Gold.mapNow()
  local z = c.goldZones
  if type(z) ~= "table" then z = {}; c.goldZones = z end
  local r = z[id]
  if type(r) ~= "table" then
    r = { looted = 0, quests = 0, secs = 0 }
    z[id] = r
    local n, oldK, oldT = 0, nil, nil
    for k, v in pairs(z) do
      if type(v) == "table" then
        n = n + 1
        local t = plainN(v.last) or 0
        if k ~= id and (oldT == nil or t < oldT or (t == oldT and tostring(k) < tostring(oldK))) then oldK, oldT = k, t end
      end
    end
    if n > Gold.ZONE_CAP and oldK ~= nil then
      local o = z[oldK]
      local ev = type(c.goldZonesEvicted) == "table" and c.goldZonesEvicted or { n = 0, looted = 0, quests = 0, secs = 0 }
      ev.n, ev.looted, ev.quests, ev.secs = num(ev.n) + 1, num(ev.looted) + num(o.looted), num(ev.quests) + num(o.quests), num(ev.secs) + num(o.secs)
      c.goldZonesEvicted = ev
      z[oldK] = nil
    end
  end
  -- (the places with no map id share row 0: it keeps no name, so it never reads as the last of them)
  if id ~= 0 then if name then r.name = name end else r.name = nil end
  r.last = at
  return r
end

-- the vendor price of one item, or nil while the client has not loaded it (0 is a price: the item sells for nothing)
function Gold.sellPrice(id)
  id = plainN(id)
  if not id then return nil end
  local v
  if C_Item and type(C_Item.GetItemInfo) == "function" then
    local r = { pcall(C_Item.GetItemInfo, id) }
    if r[1] then v = plainN(r[12]) end
  end
  if v == nil and type(GetItemInfo) == "function" then
    local r = { pcall(GetItemInfo, id) }
    if r[1] then v = plainN(r[12]) end
  end
  return v
end
-- the items of a run still waiting for a price are asked again
function Gold.runPrice(run)
  if type(run.wait) ~= "table" then return end
  for id, n in pairs(run.wait) do
    local p = Gold.sellPrice(id)
    if p then run.lootValue = num(run.lootValue) + math.floor(p * num(n)); run.wait[id] = nil end
  end
  if next(run.wait) == nil then run.wait = nil end
end
function Gold.runClose(c, run)
  Gold.runPrice(run)
  local unpriced = num(run.unpriced)
  for _, n in pairs(type(run.wait) == "table" and run.wait or {}) do unpriced = unpriced + num(n) end
  local rec = { t = num(run.t), inst = run.inst, secs = num(run.secs), looted = num(run.looted), quests = num(run.quests),
    lootValue = num(run.lootValue), items = num(run.items), unpriced = unpriced > 0 and unpriced or nil }
  c.goldRun = nil
  local list = type(c.goldRuns) == "table" and c.goldRuns or {}
  c.goldRuns = list
  list[#list + 1] = rec
  while #list > Gold.RUN_CAP do
    local o = table.remove(list, 1)
    local ev = type(c.goldRunsEvicted) == "table" and c.goldRunsEvicted or { n = 0, looted = 0, quests = 0, secs = 0, lootValue = 0, items = 0 }
    ev.n = num(ev.n) + 1
    for _, k in ipairs({ "looted", "quests", "secs", "lootValue", "items" }) do ev[k] = num(ev[k]) + num(o[k]) end
    -- (the items that never got a price stay marked, so the estimate of the earlier runs still reads "so far")
    if num(o.unpriced) > 0 then ev.unpriced = num(ev.unpriced) + num(o.unpriced) end
    c.goldRunsEvicted = ev
  end
  return rec
end
-- The open run follows the dungeon the addon says the character is in (characters[guid].inInstance, kept by
-- Emitter.checkInstance, which calls this at every change; every credit, tick and looted item asks again). Leaving
-- marks the run; it closes when the character is still outside 20 minutes later or enters another dungeon.
-- Returns the open run when the character is inside it.
function Gold.runSync(at)
  if not (ns.DB and ns.charGuid()) then return nil end
  local c = ns.char()
  at = plainN(at) or nowT()
  local inst = plainS(c.inInstance)
  if inst and ns.Emitter and ns.Emitter.canonInstance then inst = plainS(ns.Emitter.canonInstance(inst)) or inst end
  local run = type(c.goldRun) == "table" and c.goldRun or nil
  if run and plainN(run.left) and at - run.left > Gold.RUN_REENTER then Gold.runClose(c, run); run = nil end
  if run and inst and inst ~= run.inst then Gold.runClose(c, run); run = nil end
  if not inst then
    if run and not run.left then run.left = at end
    return nil
  end
  if run then run.left = nil
  else
    run = { t = at, inst = inst, secs = 0, looted = 0, quests = 0, lootValue = 0, items = 0 }
    c.goldRun = run
  end
  return run
end
-- an item the player looted (Emitter, CHAT_MSG_LOOT): one more item of the open run, and its vendor price times the
-- count on the estimate
function Gold.runItem(id, count)
  local run = Gold.runSync()
  if not run then return end
  count = plainN(count) or 1
  run.items = num(run.items) + 1
  Gold.runPrice(run)
  id = plainN(id)
  local p = id and Gold.sellPrice(id) or nil
  if p then run.lootValue = num(run.lootValue) + math.floor(p * count)
  elseif id then
    run.wait = type(run.wait) == "table" and run.wait or {}
    run.wait[id] = num(run.wait[id]) + count
  else run.unpriced = num(run.unpriced) + count end
end

-- one credit of looted coin or of a quest reward: on the place, and on the run when the character is inside one
function Gold.placeCredit(key, n, at)
  if not Gold.PLACE[key] then return end
  local c = ns.char()
  local r = Gold.zoneRow(c, at)
  r[key] = num(r[key]) + n
  local run = Gold.runSync(at)
  if run then run[key] = num(run[key]) + n end
end
-- active seconds (the 10 s tick): on the place and on the run
function Gold.placeActive(add, at)
  local c = ns.char()
  local r = Gold.zoneRow(c, at)
  r.secs = num(r.secs) + add
  local run = Gold.runSync(at)
  if run then run.secs = num(run.secs) + add end
end

-- The places of the logged-in character for the Zones view: { rows = { { id, name, looted, quests, coin, secs,
-- perHour (coin over the time played there, nil under 5 minutes), last } ... } by coin, total, evicted (or nil) }.
-- The total includes the evicted places.
function Gold.zones()
  local out = { rows = {}, total = { looted = 0, quests = 0, coin = 0, secs = 0, n = 0 } }
  if not (ns.DB and ns.charGuid()) then return out end
  local c = ns.char()
  for id, r in pairs(type(c.goldZones) == "table" and c.goldZones or {}) do
    if type(r) == "table" then
      local row = { id = id, name = plainS(r.name) or (id == 0 and Gold.NO_MAP or ("Map " .. tostring(id))), looted = num(r.looted),
        quests = num(r.quests), secs = num(r.secs), last = plainN(r.last) }
      row.coin = row.looted + row.quests
      row.perHour = row.secs >= Gold.RATE_WARM and row.coin * 3600 / row.secs or nil
      out.rows[#out.rows + 1] = row
    end
  end
  local ev = c.goldZonesEvicted
  if type(ev) == "table" and num(ev.n) > 0 then
    out.evicted = { evicted = true, n = num(ev.n), looted = num(ev.looted), quests = num(ev.quests), secs = num(ev.secs) }
    out.evicted.coin = out.evicted.looted + out.evicted.quests
    out.evicted.name = ("%d earlier place%s"):format(out.evicted.n, out.evicted.n == 1 and "" or "s")
  end
  local t = out.total
  for _, r in ipairs(out.rows) do t.looted, t.quests, t.secs, t.n = t.looted + r.looted, t.quests + r.quests, t.secs + r.secs, t.n + 1 end
  if out.evicted then t.looted, t.quests, t.secs, t.n = t.looted + out.evicted.looted, t.quests + out.evicted.quests, t.secs + out.evicted.secs, t.n + out.evicted.n end
  t.coin = t.looted + t.quests
  t.perHour = t.secs >= Gold.RATE_WARM and t.coin * 3600 / t.secs or nil
  table.sort(out.rows, function(a, b)
    if a.coin ~= b.coin then return a.coin > b.coin end
    if a.name ~= b.name then return a.name < b.name end
    return tostring(a.id) < tostring(b.id)
  end)
  return out
end

-- one run as the views read it
local function runView(r, open)
  local v = { t = num(r.t), inst = plainS(r.inst) or "Dungeon", secs = num(r.secs), looted = num(r.looted), quests = num(r.quests),
    lootValue = num(r.lootValue), items = num(r.items), open = open or nil }
  local unpriced = num(r.unpriced)
  for _, n in pairs(type(r.wait) == "table" and r.wait or {}) do unpriced = unpriced + num(n) end
  v.unpriced = unpriced
  v.coin = v.looted + v.quests
  v.perHour = v.secs >= Gold.RATE_WARM and v.coin * 3600 / v.secs or nil
  return v
end
-- The dungeon runs of the logged-in character for the Runs view, newest first, the open one first:
-- { rows = { { t, inst, secs, looted, quests, coin, perHour, lootValue, items, unpriced, open } ... }, total, evicted }
function Gold.runs()
  local out = { rows = {}, total = { looted = 0, quests = 0, coin = 0, secs = 0, lootValue = 0, items = 0, n = 0, unpriced = 0 } }
  if not (ns.DB and ns.charGuid()) then return out end
  local c = ns.char()
  if type(c.goldRun) == "table" then out.rows[1] = runView(c.goldRun, true) end
  local list = type(c.goldRuns) == "table" and c.goldRuns or {}
  for i = #list, 1, -1 do if type(list[i]) == "table" then out.rows[#out.rows + 1] = runView(list[i]) end end
  local ev = c.goldRunsEvicted
  if type(ev) == "table" and num(ev.n) > 0 then
    out.evicted = { evicted = true, n = num(ev.n), looted = num(ev.looted), quests = num(ev.quests), secs = num(ev.secs),
      lootValue = num(ev.lootValue), items = num(ev.items), unpriced = num(ev.unpriced) }
    out.evicted.coin = out.evicted.looted + out.evicted.quests
    out.evicted.inst = ("%d earlier run%s"):format(out.evicted.n, out.evicted.n == 1 and "" or "s")
  end
  local t = out.total
  local function add(r, n)
    t.looted, t.quests, t.secs, t.lootValue, t.items = t.looted + r.looted, t.quests + r.quests, t.secs + r.secs, t.lootValue + r.lootValue, t.items + r.items
    t.unpriced, t.n = t.unpriced + num(r.unpriced), t.n + n
  end
  for _, r in ipairs(out.rows) do add(r, 1) end
  if out.evicted then add(out.evicted, out.evicted.n) end
  t.coin = t.looted + t.quests
  t.perHour = t.secs >= Gold.RATE_WARM and t.coin * 3600 / t.secs or nil
  return out
end
-- "about 5g 10s", or "so far about 5g 10s" while an item of the run has no price yet
function Gold.lootValueText(r)
  return (num(r.unpriced) > 0 and "so far about " or "about ") .. fmtMoney(num(r.lootValue))
end
-- The line of a run on Combat > Dungeons: "12 items · 3g 20s coin · loot value about 5g 10s · 14g/h". Coin is the
-- looted coin and the quest rewards of the run; the rate is coin over the time played in it and never counts the
-- loot value.
function Gold.runLine(r)
  local parts = { ("%d item%s"):format(r.items, r.items == 1 and "" or "s"), fmtMoney(r.coin) .. " coin" }
  if r.items > 0 then parts[#parts + 1] = "loot value " .. Gold.lootValueText(r) end
  if r.perHour then parts[#parts + 1] = Gold.fmt(r.perHour, { rate = true }) .. "/h" end
  return table.concat(parts, SEP)
end

-- The month fold, for the logged-in character at its own login: the day rows past the Gold.DAY_CAP newest go into
-- their month's row, oldest first, so every sum over days and months stays what it was. Returns the days folded.
function Gold.fold()
  if not (ns.DB and ns.charGuid()) then return 0 end
  local c = ns.char()
  local days = c.goldDays
  if type(days) ~= "table" then return 0 end
  local keys = {}
  for k, r in pairs(days) do
    if type(k) == "string" and k:match("^%d%d%d%d%d%d%d%d$") and type(r) == "table" then keys[#keys + 1] = k end
  end
  local over = #keys - Gold.DAY_CAP
  if over <= 0 then return 0 end
  table.sort(keys)
  c.goldMonths = type(c.goldMonths) == "table" and c.goldMonths or {}
  for i = 1, over do
    local k = keys[i]
    local r, mk = days[k], k:sub(1, 6)
    local m = c.goldMonths[mk]
    if type(m) ~= "table" then m = { g = 0, s = 0, t = 0, n = 0, d = 0 }; c.goldMonths[mk] = m end
    m.g, m.s, m.t, m.n, m.d = num(m.g) + num(r.g), num(m.s) + num(r.s), num(m.t) + num(r.t), num(m.n) + num(r.n), num(m.d) + 1
    for sk, v in pairs(r) do
      if (IS_IN[sk] or IS_OUT[sk] or sk == "away") and type(v) == "number" then
        local x = num(m[sk]) + v
        m[sk] = x ~= 0 and x or nil
      end
    end
    if m.o == nil and plainN(r.o) then m.o = r.o end
    if plainN(r.c) then m.c = r.c end
    days[k] = nil
  end
  return over
end
-- "Nov 2025" for a month key
function Gold.monthLabel(key) return Gold.fmtKey(tostring(key) .. "01", "%b %Y") end

-- Records: the best day and the best session by net (gained minus spent), kept as they are set. The running day or
-- session follows its own net while it holds the record and gives it back to the one it took it from (`was`) when
-- it falls under it, so a record never needs a row that the fold or the upload has already taken away.
local function record(b, slot, idKey, id, net)
  local r = type(b[slot]) == "table" and b[slot] or nil
  if r and r[idKey] == id then
    local was = type(r.was) == "table" and r.was or nil
    if was and num(was.net) >= net then b[slot] = was
    elseif net > 0 then r.net = net
    else b[slot] = was end
  elseif net > 0 and (not r or net > num(r.net)) then
    b[slot] = { [idKey] = id, net = net, was = r and { [idKey] = r[idKey], net = r.net } or nil }
  end
end
function Gold.bestNote(at)
  if not (ns.DB and ns.charGuid()) then return end
  local c = ns.char()
  local b = c.goldBest
  if type(b) ~= "table" then
    -- the first note reads the day rows already kept
    b = {}
    for k, r in pairs(type(c.goldDays) == "table" and c.goldDays or {}) do
      if type(k) == "string" and type(r) == "table" then
        local net = num(r.g) - num(r.s)
        if net > 0 and (not b.day or net > b.day.net or (net == b.day.net and k < b.day.key)) then b.day = { key = k, net = net } end
      end
    end
  end
  local base = Gold.baseStored()
  if base and type(c.goldDays) == "table" then
    local k = Gold.dayKey(plainN(at) or nowT(), base)
    local r = c.goldDays[k]
    if type(r) == "table" then record(b, "day", "key", k, num(r.g) - num(r.s)) end
  end
  local s = current()
  -- (the session's own ledger: it is credited before the day row, the session's `gained` field after it)
  if s and plainN(s.startedEpoch) then
    local sl = sessionLedger(s)
    record(b, "session", "at", s.startedEpoch, sl.gained - sl.spent)
  end
  if b.day or b.session or c.goldBest then c.goldBest = b end
end
-- "Best day Nov 12 +120g · best session Nov 3, 21:14 +80g", or nil with no record yet
function Gold.bestText()
  if not (ns.DB and ns.charGuid()) then return nil end
  local b = ns.char().goldBest
  if type(b) ~= "table" then return nil end
  local parts = {}
  if type(b.day) == "table" and b.day.key then parts[#parts + 1] = ("best day %s %s"):format(Gold.dayLabel(b.day.key), signed(b.day.net)) end
  if type(b.session) == "table" and plainN(b.session.at) then
    parts[#parts + 1] = ("best session %s %s"):format(noZero(date("%b %d, %H:%M", b.session.at)), signed(b.session.net))
  end
  if #parts == 0 then return nil end
  local s = table.concat(parts, SEP)
  return s:sub(1, 1):upper() .. s:sub(2)
end

-- Reconciliation (#43, 4.9): Gold.audit(key) for the logged-in character. key: "history" (default: every day and
-- month row and every journal still in the save file), a day period, "session", "previous" or a session id.
-- Returns { key, state, text, reason, checks, notes }:
--   state "ok"       every identity below holds
--         "broken"   one does not: `text` names the first break
--         "unknown"  not checkable: `reason` says why (a journal that reached its cap, so rows were merged or not
--                    kept; a period that begins before the history; a change while away in the period; nothing
--                    recorded). The identities that could be checked did hold.
-- The identities:
--   1 row chain  in a journal, a row's balance minus the balance of the row before it is the row's amount
--   2 session    the rows of each source sum to the session's ledger (unexplained income: gained minus the sources)
--   3 day        closing minus opening balance = gained - spent + changed while away; the income sources sum to
--                gained and the spending sources to spent
--   4 character  balance = gained - spent + changed while away. A character that had gold before the addon first
--                saw it differs by that fixed amount, which no save file can tell from a break: it is noted, not judged.
--   5 history    each row opens on the balance the row before it closed on, and the newest closes on the balance
Gold.AUDIT_IDENTITY = {
  "Every purse change is one journal row: the balance after it minus the balance before it is its amount.",
  "The rows of each source add up to the session's total for that source.",
  "Each day: closing minus opening balance = earned minus spent plus changed while away.",
  "Each day opens on the balance the day before closed on, and the newest closes on the balance.",
}
function Gold.audit(key, now)
  if key == nil or key == "all" or key == "" then key = "history" end
  local res = { key = key, state = "unknown", checks = 0, notes = {} }
  if not (ns.DB and ns.charGuid()) then res.reason = "the character is not known yet"; return res end
  now = now or nowT()
  local c = ns.char()
  local E = ns.Emitter
  local cap = (E and tonumber(E.GOLD_CAP)) or 4000
  local SIGN = (E and E.GOLD_SIGN) or {}
  local whole = key == "history"
  local base = Gold.baseStored()
  local function broke(text) res.state, res.text = "broken", text; return res end
  local unk
  -- A purse change that is not fully booked yet is not judged, like Gold._held: a merchant spend waiting for its
  -- repair cost (Emitter.creditRepair, up to 0.3 s) is on the day row and the balance before its source row is
  -- written, and a change while away read at login is on the balance one frame before its row (Emitter.goldAway).
  if E and ((type(E._repair) == "table" and E._repair.wait) or num(E._awayWait) > 0) then
    res.reason = "a purse change is still being booked"
    return res
  end

  -- the sessions and the rows of the scope
  local sessions, rows, period = {}, {}, nil
  if whole then
    sessions = Gold.sessions()
    for k, r in pairs(type(c.goldMonths) == "table" and c.goldMonths or {}) do
      if type(k) == "string" and type(r) == "table" then rows[#rows + 1] = { key = k, r = r, label = Gold.monthLabel(k) } end
    end
    for k, r in pairs(type(c.goldDays) == "table" and c.goldDays or {}) do
      if type(k) == "string" and type(r) == "table" then rows[#rows + 1] = { key = k, r = r, label = Gold.dayLabel(k) } end
    end
  elseif Gold.isDayScope(key) then
    if not base then res.reason = "no day has been recorded yet"; return res end
    local from, to = Gold.range(key, base, now)
    if not from then res.reason = "not a period"; return res end
    period = { from = from, to = to }
    local fromK, toK = Gold.dayKey(from, base), Gold.dayKey(to - 1, base)
    for k, r in pairs(type(c.goldDays) == "table" and c.goldDays or {}) do
      if type(k) == "string" and type(r) == "table" and k >= fromK and k <= toK then rows[#rows + 1] = { key = k, r = r, label = Gold.dayLabel(k) } end
    end
    for _, s in ipairs(Gold.sessions()) do
      local s0, s1 = num(s.startedEpoch), s.endedEpoch or now
      if s0 < to and s1 >= from then sessions[#sessions + 1] = s end
    end
    local since = plainN(c.goldSince)
    if since and from < Gold.dayStart(since, base) then unk = ("the history starts %s, inside this period"):format(Gold.fmtDate(since)) end
  else
    sessions = Gold.scope(key).sessions
  end
  -- (a month's days are older than every day row kept: "202511" sorts before "20251201" and after "20251031")
  table.sort(rows, function(a, b) return a.key < b.key end)

  -- 1 and 2: every journal of the scope
  local awaySeen, data = 0, 0   -- (data: the journals with a row and the day rows that were read)
  for _, s in ipairs(sessions) do
    local log, sg = s.goldLog, s.gold
    local label = sessionLabel(s)
    if type(log) ~= "table" or type(sg) ~= "table" then
      unk = unk or ("the session of %s was recorded before addon 0.9.40 and has no journal"):format(label)
    elseif num(s.goldLogDropped) > 0 or #log >= cap then
      unk = unk or ("the journal of the session of %s reached its cap, rows were merged or not kept"):format(label)
    else
      local prev, sums = nil, {}
      for i, r in ipairs(log) do
        local d, src, bal
        if type(r) == "string" then
          local _, ds, ss, bs = r:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t")
          d, src, bal = tonumber(ds), ss, tonumber(bs)
        end
        if not (d and src and bal) then return broke(("session of %s: journal row %d cannot be read"):format(label, i)) end
        if prev and bal - prev ~= d then
          return broke(("session of %s, row %d: the balance went from %s to %s, the row says %s"):format(label, i, fmtMoney(prev), fmtMoney(bal), signed(d)))
        end
        prev = bal
        sums[src] = (sums[src] or 0) + d
      end
      local known = 0
      for _, k in ipairs(Gold.IN) do if k ~= "unexplained" then known = known + num(sg[k]) end end
      for k, sign in pairs(SIGN) do
        local want
        if k == "unexplained" then want = num(sg.gained) - known else want = num(sg[k]) * sign end
        if (sums[k] or 0) ~= want then
          return broke(("session of %s: the rows of %s add up to %s, its total says %s"):format(label, Gold.LABEL[k] or k, signed(sums[k] or 0), signed(want)))
        end
      end
      if num(sums.away) ~= 0 or num(sg.away) ~= 0 then awaySeen = awaySeen + math.abs(num(sg.away)) + 1 end
      res.checks = res.checks + 1
      if #log > 0 then data = data + 1 end
    end
  end

  -- 3 and 5: the day and month rows
  local awaySum, awayAt, last = 0, nil, nil
  for _, e in ipairs(rows) do
    local r = e.r
    local inc, out = 0, 0
    for _, k in ipairs(Gold.IN) do inc = inc + num(r[k]) end
    for _, k in ipairs(Gold.OUT) do out = out + num(r[k]) end
    if inc ~= num(r.g) then return broke(("%s: the income sources add up to %s, the day gained %s"):format(e.label, fmtMoney(inc), fmtMoney(num(r.g)))) end
    if out ~= num(r.s) then return broke(("%s: the spending sources add up to %s, the day spent %s"):format(e.label, fmtMoney(out), fmtMoney(num(r.s)))) end
    local o, cl = plainN(r.o), plainN(r.c)
    if o and cl then
      local want = num(r.g) - num(r.s) + num(r.away)
      if cl - o ~= want then
        return broke(("%s: the balance went from %s to %s, the rows say %s"):format(e.label, fmtMoney(o), fmtMoney(cl), signed(want)))
      end
      if last and o ~= last.c then
        return broke(("%s opens on %s, %s closed on %s"):format(e.label, fmtMoney(o), last.label, fmtMoney(last.c)))
      end
      last = { c = cl, label = e.label }
    end
    if num(r.away) ~= 0 then awaySum = awaySum + num(r.away); awayAt = awayAt or e.label end
    res.checks = res.checks + 1
    data = data + 1
  end
  local bal = plainN(type(c.gold) == "table" and c.gold.balance)
  local live = whole or (period and now >= period.from and now < period.to)
  if live and last and bal and last.c ~= bal and not Gold._held then
    return broke(("%s closed on %s, the balance is %s"):format(last.label, fmtMoney(last.c), fmtMoney(bal)))
  end

  -- 4: the character's lifetime ledger
  if whole and type(c.gold) == "table" and bal then
    local k = bal - (num(c.gold.gained) - num(c.gold.spent) + num(c.gold.away))
    if k == 0 then res.checks = res.checks + 1
    else res.notes[#res.notes + 1] = ("The lifetime totals began when the character already had gold: they differ from the balance by a fixed %s and are not compared."):format(fmtMoney(math.abs(k))) end
  end

  if data == 0 and not unk then res.reason = whole and "nothing is recorded yet" or "no gold moved in this period"; return res end
  if unk then res.reason = unk; return res end
  -- (an away gap is a row with an away amount: two gaps that cancel are still two gaps, the sum is only for the text)
  if awayAt or (#rows == 0 and awaySeen > 0) then
    res.away = awaySum
    res.reason = awaySum ~= 0 and ("%s changed while away (%s), not seen on this PC. Everything recorded here adds up"):format(signed(awaySum), awayAt)
      or awayAt and ("gold changed while away (%s and later, the changes cancel), not seen on this PC. Everything recorded here adds up"):format(awayAt)
      or "gold changed while away in this session, not seen on this PC. Everything recorded here adds up"
    return res
  end
  res.state = "ok"
  return res
end
Gold.AUDIT_MARK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:0|t"
Gold.AUDIT_BROKEN = "The gold records do not add up: hover for where"
-- what the status line of the Gold pane says on hover
function Gold.auditTip(tip, a)
  if a.state == "broken" then
    tip:AddLine("The gold records do not add up", C.red[1], C.red[2], C.red[3])
    tip:AddLine(tostring(a.text), 1, 1, 1, true)
  else tip:AddLine("Reconciled", 1, 1, 1) end
  for _, s in ipairs(Gold.AUDIT_IDENTITY) do tip:AddLine(s, C.dim[1], C.dim[2], C.dim[3], true) end
  for _, s in ipairs(a.notes or {}) do tip:AddLine(s, C.dim[1], C.dim[2], C.dim[3], true) end
end
-- the reply of /eb gold audit
function Gold.auditText(a)
  if a.state == "ok" then return "Gold ledger reconciled." end
  if a.state == "broken" then return "Gold ledger does not add up: " .. tostring(a.text) end
  return "Not checkable: " .. tostring(a.reason)
end

-- ── the Gold pane (docs/UX_PRAGMATIC.md 4.2; the design system is docs/UX_OVERHAUL.md 2) ─────────────────────────────
-- Loot > Gold: am I up or down, and from what. The control row holds the period (Session, Today, Week, All); the page
-- is one scroll: four cards (NET is the answer), then one list under its section header, which names the period and
-- holds the view (Sources, Auction house, Journal). No line above the cards, no note under them, no entry counts.
-- Built from the kit in UI.lua; the pane's helpers live on one table (GP) so the file keeps few locals.
local GP = {}
local S = UI.S
Gold.GP = GP
GP.PERIODS = { { "session", "Session" }, { "today", "Today" }, { "week", "Week" }, { "all", "All" } }
GP.VIEWS = { { "sources", "Sources" }, { "auctions", "Auction house" }, { "journal", "Journal" } }
Gold.VIEWS, Gold.PERIODS = GP.VIEWS, GP.PERIODS
Gold.MAX_ROWS = 500       -- journal rows listed at once (a row is a frame): the newest; the header says how many more
Gold.RATE_MIN_S = 1800    -- a per hour figure needs this much play in the period (docs/UX_PRAGMATIC.md 4.2, 6)
GP.UNTRACED_TIP = "Gold that moved while you played and the addon saw no source for it."
GP.AWAY_TIP = "Your balance changed by this much while the addon was not running."
GP.MOVED_TIP = "Gold that moved between your own characters or the bank. It is not earned or spent."
GP.EMPTY = "No gold has moved in this period."
GP.NO_AUCTION = "No auction in this period."
GP.SOURCES_OFF = "Sources are not reliable for dungeon time before %s."
GP.SOURCES_OFF_WHY = "Until then coin shared in a group was often booked as mail or with no source."
-- gold with no source seen says the same words on every screen. It moved while playing: only `away` is "while you
-- were away" (the balance differed at login).
GP.UNTRACED = { unexplained = "Source not seen", other = "Spending not explained", away = "While you were away" }
GP.OTHER_LABEL = { moved = "Your characters and bank" }
-- group names of Gold.entries that stand for "nothing recorded": never shown as what a source mostly came from
GP.NO_NAME = { ["source not recorded"] = true, ["not recorded"] = true, ["not named"] = true }
function GP.labelOf(list, key) for _, e in ipairs(list) do if e[1] == key then return e[2] end end end
function GP.srcLabel(key) return GP.UNTRACED[key] or GP.OTHER_LABEL[key] or Gold.LABEL[key] or tostring(key) end
local function money(c, sgn) c = num(c); return UI.money((c < 0 and -1 or 1) * math.floor(math.abs(c) + 0.5), sgn) end
GP.money = money
-- gold only, for a card's META line when the full amount does not fit: "12,393g"
function GP.gold(c) return ns.fmtMoney(math.floor(num(c) / 10000) * 10000, { icons = true, units = 1 }) end

-- the period in words: "this session", "today", "on Mon 16 Nov, 21:35"
function GP.periodWords(sc)
  local k = sc.key
  if k == "session" then return "this session" elseif k == "today" then return "today" elseif k == "week" then return "this week"
  elseif k == "all" then return "in all" elseif k == "yesterday" then return "yesterday" elseif k == "month" then return "this month"
  elseif k == "last30" then return "in the last 30 days" elseif k == "previous" then return "last session" end
  local s = sc.sessions and sc.sessions[1]
  if not sc.days and s then return "in the session of " .. UI.fmtWhen(num(s.startedEpoch)) end
  if sc.from then return "on " .. UI.fmtDate(sc.from) end
  return (sc.label or ""):lower()
end
-- The section header of the list: the period. When the gold history starts inside the period, the real range takes
-- the period word's place ("SINCE WED 18 NOV 20:35", not "WEEK"): the cards count from there.
function GP.periodHead(sc)
  if sc.since then return "Since " .. UI.fmtStamp(sc.since) end
  local k = sc.key
  if k == "session" then return "This session" elseif k == "today" then return "Today" elseif k == "week" then return "Week"
  elseif k == "all" then return "All time" elseif k == "yesterday" then return "Yesterday" elseif k == "month" then return "This month"
  elseif k == "last30" then return "Last 30 days" elseif k == "last7" then return "Last 7 days" elseif k == "previous" then return "Last session" end
  local s = sc.sessions and sc.sessions[1]
  if not sc.days and s then return "Session of " .. UI.fmtStamp(num(s.startedEpoch)) end
  if sc.days and sc.period and sc.period.from then return UI.fmtSince(sc.period.from) end
  return sc.label or ""
end
-- the search text of a journal row
function GP.hay(e)
  return ((Gold.WORD[e.src] or "") .. " " .. GP.srcLabel(e.src) .. " " .. (e.detail or "") .. " " .. (e.zone or "") .. " " .. (e.flag or "")):lower()
end
-- what a journal row says in Detail. A row with no source seen says so in its Source cell and nothing twice.
function GP.detailOf(e)
  if GP.UNTRACED[e.src] and e.src ~= "away" and not (e.ref and e.ref.drift) then return "" end
  return (e.detail or "") ~= "" and e.detail or GP.srcLabel(e.src)
end

-- Whether a period holds time inside a dungeon from before the coin capture of 0.9.52 (characters[guid].goldShareSince,
-- the first load with it). Until then coin shared in a group could be booked as mail or with no source, so the
-- sources of such a period are not offered (docs/UX_PRAGMATIC.md 4.2). Returns true and that first load's time.
function Gold.dungeonBefore(sc)
  if not (ns.DB and ns.charGuid() and sc) then return false end
  local c = ns.char()
  local fix = num(c.goldShareSince)
  if fix <= 0 then fix = math.huge end
  local from, to
  if sc.lifetime then from, to = 0, math.huge
  elseif sc.days and sc.period and sc.period.from then from, to = sc.period.from, sc.period.to
  else
    local s = sc.sessions and sc.sessions[1]
    if not s then return false end
    from, to = num(s.startedEpoch), s.endedEpoch or nowT()
  end
  local function hit(t, secs)
    t, secs = num(t), math.max(0, num(secs))
    return t > 0 and t < fix and t < to and t + secs >= from
  end
  for _, r in ipairs(type(c.goldRuns) == "table" and c.goldRuns or {}) do if type(r) == "table" and hit(r.t, r.secs) then return true, fix end end
  for _, r in ipairs(type(c.dungeonLegacy) == "table" and c.dungeonLegacy or {}) do if type(r) == "table" and hit(r.t, r.secs) then return true, fix end end
  for _, r in ipairs(type(c.dungeonRuns) == "table" and c.dungeonRuns or {}) do
    if type(r) == "table" and hit(r.t, num(r.endT) - num(r.t)) then return true, fix end
  end
  if sc.lifetime and type(c.goldRunsEvicted) == "table" and fix ~= math.huge then return true, fix end
  -- (a session from before the run store counted its dungeon entries on the record)
  for _, s in ipairs(sc.sessions or {}) do
    if num(s.dungeons) > 0 and hit(s.startedEpoch, num(s.endedEpoch or nowT()) - num(s.startedEpoch)) then return true, fix end
  end
  return false
end

-- ── tooltips (one format: the name white, a sentence, then label and value pairs) ──
local DIM = { 0.78, 0.79, 0.80 }
local function line(tip, text) tip:AddLine(text, DIM[1], DIM[2], DIM[3], true) end
local function pair(tip, label, value) tip:AddDoubleLine(label, value, C.fgMuted[1], C.fgMuted[2], C.fgMuted[3], 1, 1, 1) end
function GP.tradeSide(tip, word, list, m)
  local parts = {}
  if num(m) > 0 then parts[#parts + 1] = fmtMoney(m) end
  for _, s in ipairs(list or {}) do
    local id, n = tostring(s):match("^(%d+):(%d+)$")
    parts[#parts + 1] = (itemName(id) or "an item") .. " x" .. (n or 1)
  end
  line(tip, word .. ": " .. (#parts > 0 and table.concat(parts, ", ") or "nothing"))
end
function GP.journalTip(row, e, tip)
  if not e or e.ebSection then return end
  tip:AddLine(("%s  %s"):format(GP.srcLabel(e.src), signed(e.delta)), 1, 1, 1)
  if GP.detailOf(e) ~= "" and (e.detail or "") ~= "" then line(tip, e.detail) end
  if e.vendorPrice then line(tip, ("Vendor price %s, paid %s"):format(fmtMoney(e.vendorPrice), fmtMoney(e.delta))) end
  local tr = e.tradeRec
  if tr then GP.tradeSide(tip, "You gave", tr.gave, tr.gaveMoney); GP.tradeSide(tip, "You got", tr.got, tr.gotMoney) end
  local m = e.loot and e.loot.mail
  if type(m) == "table" and m.subject then line(tip, "Mail: " .. tostring(m.subject)) end
  if num(e.ref.cod) > 0 then line(tip, "COD " .. fmtMoney(num(e.ref.cod))) end
  if e.flag and e.flag ~= "unexplained" then line(tip, "Worth a look: " .. GP.reason(e.flag)) end
  if e.src == "unexplained" or e.src == "other" then line(tip, GP.UNTRACED_TIP) elseif e.src == "away" then line(tip, GP.AWAY_TIP) end
  line(tip, ("%s  ·  balance after %s"):format(UI.fmtWhen(e.t or 0), fmtMoney(e.bal or 0)))
  if not e.zone then line(tip, "Place: Not recorded") end
end
GP.REASONS = { unexplained = "the addon saw no source for it", stranger = "gold to or from a player you do not know",
  ["above vendor price"] = "sold for more than a vendor pays" }
function GP.reason(flag) return GP.REASONS[flag] or tostring(flag) end
function GP.sourceTip(row, r, tip)
  if not r or r.ebSection then return end
  tip:AddLine(("%s  %s"):format(GP.srcLabel(r.key), r.dir == 0 and signed(r.amount) or fmtMoney(r.amount)), 1, 1, 1)
  if r.key == "away" then line(tip, GP.AWAY_TIP) elseif GP.UNTRACED[r.key] then line(tip, GP.UNTRACED_TIP) elseif r.key == "moved" then line(tip, GP.MOVED_TIP) end
  for i = 1, math.min(6, #r.top) do
    local t = r.top[i]
    pair(tip, t.name .. (t.n > 1 and ("  x" .. t.n) or ""), fmtMoney(t.amount))
  end
  if #r.top > 6 then line(tip, ("and %d more"):format(#r.top - 6)) end
  if r.key == "moved" or r.dir == 0 then return end
  if r.n == 0 then line(tip, "Entries: Not recorded")
  elseif not r.kept then line(tip, "Not every entry of this source is still stored. Click to see the ones that are.")
  else line(tip, "Click to see every entry.") end
end
function GP.auctionTip(row, r, tip)
  if not r or r.ebSection then return end
  if r.item then tip:AddLine(r.item .. (num(r.count) > 1 and ("  x" .. r.count) or ""), 1, 1, 1)
  else tip:AddLine(r.what or "Auction", 1, 1, 1); line(tip, "Item: Not recorded") end
  pair(tip, "When", UI.fmtWhen(r.t or 0))
  if r.price and num(r.count) > 1 then pair(tip, "Each", fmtMoney(math.floor(r.price / r.count))) end
  if r.what == "Sold" then
    if r.price then pair(tip, "Buyer paid", fmtMoney(r.price)) end
    if r.cut and r.cut > 0 then pair(tip, "House cut", fmtMoney(r.cut)) end
    if r.deposit and r.deposit > 0 then pair(tip, "Deposit returned", fmtMoney(r.deposit)) end
    if r.net then pair(tip, "Mail paid", fmtMoney(r.net)) end
  elseif r.what == "Won" then line(tip, "Price: Not recorded")
  elseif r.what == "Posted" and r.hours then pair(tip, "Posted for", UI.fmtDur(r.hours * 3600)) end
  if (r.note or "") ~= "" then pair(tip, r.what == "Sold" and "Buyer" or "Seller", r.note) end
end

-- The NET card (0.9.46, #43 rule 9). Gold from a play stretch that never saved (away rows with crash=1) is part of
-- the period's net here: the card then is the closing balance minus the opening one, less only what truly changed
-- while away. Returns { net, crash, away = changed while away without the crash rows }.
function Gold.netCard(ledger, entries)
  local crash = 0
  for _, e in ipairs(entries or {}) do if e.src == "away" and e.ref and e.ref.crash then crash = crash + e.delta end end
  return { net = num(ledger.gained) - num(ledger.spent) + crash, crash = crash, away = num(ledger.away) - crash,
    line = crash ~= 0 and ("%s: %s, counted in the net of this pane"):format(Gold.CRASH_LABEL, signed(crash)) or nil }
end

-- The auction rows of a period, newest first, and their sums (Market.buildAuctions is every trade of the character).
-- sum: posted, sold, bought (purchases with a price), won (deliveries with none), expired, cancelled, and in copper
-- spent (the prices of the purchases), sales (what the buyers paid), cut, deposit (returned), mail (what the sale
-- mails paid: sales - cut + deposit).
function GP.auctions(sc)
  local rows, out = {}, {}
  if ns.Market and ns.Market.buildAuctions then rows = ns.Market.buildAuctions() end
  local inSess = {}
  for _, s in ipairs(sc.sessions or {}) do if s.id then inSess[s.id] = true end end
  local sum = { posted = 0, sold = 0, sales = 0, cut = 0, deposit = 0, mail = 0, bought = 0, won = 0, spent = 0, expired = 0, cancelled = 0 }
  for _, r in ipairs(rows) do
    local keep
    if sc.lifetime then keep = true
    elseif sc.from and sc.to then keep = num(r.t) >= sc.from and num(r.t) < sc.to
    else keep = r.s ~= nil and inSess[r.s] == true end
    if keep then
      out[#out + 1] = r
      if r.what == "Posted" then sum.posted = sum.posted + 1
      elseif r.what == "Sold" then
        sum.sold = sum.sold + 1; sum.sales = sum.sales + num(r.price); sum.cut = sum.cut + num(r.cut)
        sum.deposit = sum.deposit + num(r.deposit); sum.mail = sum.mail + num(r.net)
      elseif r.what == "Bought" then sum.bought = sum.bought + 1; sum.spent = sum.spent + num(r.price)
      elseif r.what == "Won" then sum.won = sum.won + 1
      elseif r.what == "Expired" then sum.expired = sum.expired + 1
      elseif r.what == "Cancelled" then sum.cancelled = sum.cancelled + 1 end
    end
  end
  return out, sum
end
-- The answer of the Auction house view: "Spent 30g 98s · Received 5g 97s · Net -25g 0s" (three segments: a comma
-- after a coin icon reads badly). Spent is everything paid at
-- the auction house (ledger.auctions: purchases and deposits), Received what auction mail paid out
-- (ledger.auctionSales: sale prices minus the house cut plus deposits returned), Net is Received minus Spent. All
-- three are the ledger's, so they add up on sight and hold when journals are gone. Returns nil when neither moved.
function GP.auctionAnswer(ledger)
  local spent, got = num(ledger.auctions), num(ledger.auctionSales)
  if spent == 0 and got == 0 then return nil end
  return { spent = spent, received = got, net = got - spent,
    segs = { ("Spent **%s**"):format(money(spent)), ("Received **%s**"):format(money(got)), ("Net **%s**"):format(money(got - spent, true)) } }
end

-- ── the top of the page: the four cards ──
function GP.paintTop(c)
  local sc, g = c.scopeData, c.scopeData.ledger
  local card = Gold.netCard(g, c.entries)
  c.crash, c.crashAmt = card.crash, card.crash
  local net = card.net
  -- (a rate needs 30 minutes of play in the period; all time has none)
  local rate = (not sc.lifetime and (sc.elapsed or 0) >= Gold.RATE_MIN_S) and (net * 3600 / sc.elapsed) or nil
  c.rate = rate
  local cards = c.cards.cards
  c.shownCards = cards
  local ended = (sc.days and not sc.live and sc.balance ~= nil) or (not sc.days and not sc.lifetime and not sc.live and #sc.sessions > 0)
  local bal = sc.balance
  if bal == nil and sc.days then bal = Gold.metric("balance") end
  local okR, ro = pcall(Gold.roster, "all")
  local all = (okR and ro and ro.count > 1) and ro.total or nil
  c.balAll = all
  local broken = c.audit and c.audit.state == "broken"
  local balMeta = broken and "records do not add up" or (all and ("all characters " .. money(all)) or "")
  cards[1]:Set(ended and "Balance at its end" or "Balance", money(bal or 0), balMeta)
  -- (a money meta never shortens inside its number: it steps down to 10 px, then drops its silver, then its words;
  -- the full value is in the BALANCE tooltip)
  pcall(UI.Fit, cards[1].meta, 10)
  if all and not broken and cards[1].meta:IsTruncated() then cards[1].meta:SetText("all characters " .. GP.gold(all)); pcall(UI.Fit, cards[1].meta, 10) end
  if all and not broken and cards[1].meta:IsTruncated() then cards[1].meta:SetText("all " .. GP.gold(all)); pcall(UI.Fit, cards[1].meta, 10) end
  cards[1].ebBal = bal
  -- EARNED and SPENT say how far the rest can be trusted: what moved with no source seen, else the main source
  local function mostly(dir)
    local top
    for _, r in ipairs(c.sourceData.rows) do
      if r.dir == dir and r.amount > 0 and not GP.UNTRACED[r.key] and (not top or r.amount > top.amount) then top = r end
    end
    return top and ("mostly " .. GP.srcLabel(top.key):lower()) or ""
  end
  local inU, outU = num(g.unexplained), num(g.other)
  c.notTraced = { inU, outU }
  cards[2]:Set("Earned", money(g.gained, g.gained > 0), inU > 0 and (money(inU) .. " not traced") or mostly(1))
  cards[3]:Set("Spent", g.spent > 0 and money(-g.spent, true) or money(0), outU > 0 and (money(outU) .. " not traced") or mostly(-1))
  cards[4]:Set("Net", money(net, true), rate and (money(rate, true) .. " per hour") or "")
  for i = 2, 4 do pcall(UI.Fit, cards[i].meta, 10) end
end

-- an item's icon and quality by its name, from the newest loot row that names it (the auction rows carry only the name)
function GP.itemLook(name)
  local log = ns.DB and ns.DB.loot and ns.DB.loot.log or {}
  for i = #log, math.max(1, #log - 2000), -1 do
    local l = log[i]
    if type(l) == "table" and l.item and (l.item == name or tostring(l.item):find("[" .. name .. "]", 1, true)) then
      return { icon = l.icon, q = type(l.q) == "string" and #l.q == 8 and l.q or nil }
    end
  end
  return nil
end
-- A day row of the Journal: the gold day (it turns over at the daily reset, as Today does), and its net from the day
-- row when `withNet`. A first day that starts mid-day says from when: "WEDNESDAY 18 NOV, FROM 20:35".
function GP.dayHead(key, base, now, withNet)
  local start = Gold.keyStart(key, base)
  local label
  if key == Gold.dayKey(now, base) then label = "TODAY"
  elseif key == Gold.dayKey(now - DAY, base) then label = "YESTERDAY"
  else
    label = (date("%A ", start) .. tostring(tonumber(date("%d", start)) or date("%d", start)) .. date(" %b", start)):upper()
    if date("%Y", start) ~= date("%Y", now) then label = label .. date(" %Y", start) end
  end
  local c = ns.DB and ns.charGuid() and ns.char() or {}
  local since = num(c.goldSince)
  if since > start and since < start + DAY then label = label .. ", FROM " .. UI.fmtClock(since) end
  local r = withNet and type(c.goldDays) == "table" and c.goldDays[key] or nil
  if type(r) == "table" then label = label .. " \194\183 " .. money(num(r.g) - num(r.s), true) end
  return label
end

-- ── the list ──
function GP.paintList(c)
  local st, sc, entries, src = c.st, c.scopeData, c.entries, c.sourceData
  local view = c.view
  local q = view == "journal" and (c.search:GetText() or ""):lower() or ""
  for k, t in pairs(c.tbl) do if k == view then t.frame:Show() else t.frame:Hide() end end
  c.section:SetLabel(GP.periodHead(sc))
  c.section:SetMeta(nil)
  c.viewSeg:SetValue(view)
  c.answer:Hide(); c.answerData = nil
  local tbl = c.tbl[view]
  if view == "sources" then
    local items = {}
    if #src.rows > 0 then
      local ins, outs = {}, {}
      for _, r in ipairs(src.rows) do if r.dir > 0 then ins[#ins + 1] = r elseif r.dir < 0 then outs[#outs + 1] = r end end
      if #ins > 0 then items[#items + 1] = { ebSection = "Earned" }; for _, r in ipairs(ins) do items[#items + 1] = r end end
      if #outs > 0 then items[#items + 1] = { ebSection = "Spent" }; for _, r in ipairs(outs) do items[#items + 1] = r end end
      -- neither earned nor spent: what the balance did while the addon was not running, and gold between the
      -- player's own characters and the bank (counted in its source above, summed here once more)
      local other = {}
      for _, r in ipairs(src.rows) do if r.dir == 0 and r.amount ~= 0 then other[#other + 1] = r end end
      local moved, nMoved = 0, 0
      for _, e in ipairs(entries) do if e.ref and e.ref.rel == "alt" then moved, nMoved = moved + e.delta, nMoved + 1 end end
      if nMoved > 0 and moved ~= 0 then other[#other + 1] = { key = "moved", dir = 0, amount = moved, n = nMoved, share = 0, top = {} } end
      if #other > 0 then items[#items + 1] = { ebSection = "Not earned or spent" }; for _, r in ipairs(other) do items[#items + 1] = r end end
    end
    for _, r in ipairs(items) do if r.key then r.ebNoOpen = (r.dir == 0 or r.n == 0) or nil end end
    tbl.setRows(items, function(row, r)
      local cc = row.c
      cc.src:SetText(GP.srcLabel(r.key))
      if GP.UNTRACED[r.key] then UI.SetColor(cc.src, "fgSubtle") end
      -- (mostly from: the largest group of the source, only while the journal rows kept add up to its amount)
      local t = r.kept and r.top[1] or nil
      if t and GP.NO_NAME[t.name] then t = nil end
      cc.what:SetText(t and (t.name .. ((t.qty and t.qty > 1) and (" x" .. t.qty) or "")) or "")
      cc.whatAmt:SetText(t and money(t.amount) or "")
      cc.amount:SetText(r.dir == 0 and money(r.amount, true) or money(r.dir * r.amount, true))
    end)
    if #items == 0 then tbl.setState(GP.EMPTY) end
  elseif view == "journal" then
    local rows = {}
    for i = #entries, 1, -1 do
      local e = entries[i]
      if q == "" or GP.hay(e):find(q, 1, true) then rows[#rows + 1] = e end
    end
    local matched = #rows
    local key, asc = st.sortKey, st.sortAsc
    if not (key == "time" and not asc) then
      local function val(e)
        if key == "amount" then return e.delta elseif key == "src" then return GP.srcLabel(e.src)
        elseif key == "detail" then return GP.detailOf(e):lower() elseif key == "loc" then return (e.zone or ""):lower() end
        return e.t or 0
      end
      local order = {}
      for i, e in ipairs(rows) do order[e] = i end
      table.sort(rows, function(a, b)
        local va, vb = val(a), val(b)
        if va == vb then return order[a] < order[b] end
        if asc then return va < vb else return va > vb end
      end)
    end
    if #rows > Gold.MAX_ROWS then for i = #rows, Gold.MAX_ROWS + 1, -1 do rows[i] = nil end end
    -- newest first: a day row over each day, with the day's net when the list is the whole of a day period
    if key == "time" and not asc then
      local base, now = Gold.baseStored(), nowT()
      local withNet = q == "" and (sc.days or sc.lifetime) and true or false
      local out, last = {}, nil
      for _, e in ipairs(rows) do
        local k = base and Gold.dayKey(e.t or 0, base) or date("%Y-%m-%d", e.t or 0)
        if k ~= last then last = k; out[#out + 1] = { ebSection = base and GP.dayHead(k, base, now, withNet) or UI.fmtDay(e.t or 0) } end
        out[#out + 1] = e
      end
      rows = out
    end
    tbl.setRows(rows, function(row, e)
      local cc = row.c
      cc.time:SetText(UI.fmtClock(e.t or 0))
      cc.src:SetText(GP.UNTRACED[e.src] or Gold.WORD[e.src] or e.src)
      if GP.UNTRACED[e.src] then UI.SetColor(cc.src, "fgSubtle") end
      cc.detail:SetText(GP.detailOf(e))
      cc.loc:SetText(e.zone or "")
      if cc.coords then cc.coords:SetText((e.x and e.y) and UI.fmtCoords(e.x, e.y) or "") end
      cc.amount:SetText(money(e.delta, true))
      if cc.bal then cc.bal:SetText(money(e.bal or 0)) end
    end)
    c.journalRows, c.journalCount = tbl.rows, matched
    -- the header's one remark: the list is cut at its newest rows, or it does not hold every entry of the period
    local partial = false
    for _, r in ipairs(src.rows) do if r.dir ~= 0 and r.amount ~= 0 and not r.kept then partial = true end end
    c.journalPartial = partial
    c.section:SetMeta(matched > Gold.MAX_ROWS and ("newest %d of %d"):format(Gold.MAX_ROWS, matched)
      or (sc.lifetime and matched > 0 and q == "" and #entries > 0 and ("entries since " .. UI.fmtSince(num(entries[1].t))))
      or (partial and matched > 0 and q == "" and "not every entry is kept") or nil)
    if matched == 0 then
      if q ~= "" then tbl.setState(('No entry matches "%s". '):format(q), "Clear search", function() c.search:SetText("") end)
      elseif partial then tbl.setState("No entry of this period is kept.")
      else tbl.setState(GP.EMPTY) end
    end
  else
    local list, sum = GP.auctions(sc)
    c.auctionSum = sum
    local ans = GP.auctionAnswer(sc.ledger)
    c.answerData = ans
    if ans then
      local function why(tip)
        tip:AddLine("Auction house", 1, 1, 1)
        line(tip, "Spent is everything paid at the auction house, deposits included. Received is what auction mail paid out. Net is received minus spent.")
        if sum.sold > 0 and sum.mail == ans.received then
          pair(tip, "Sold", fmtMoney(sum.sales)); pair(tip, "House cut", "-" .. fmtMoney(sum.cut)); pair(tip, "Deposits returned", fmtMoney(sum.deposit))
        elseif ans.received > 0 then line(tip, "Not every sale of this period is still stored.") end
      end
      c.answer:SetSegments({ { text = ans.segs[1], tip = why }, { text = ans.segs[2], tip = why }, { text = ans.segs[3], tip = why } })
      c.answer:Show()
    end
    -- Player (the buyer of a sale, the seller of a purchase) shows only while a third of the rows name one
    local named = 0
    for _, r in ipairs(list) do if (r.note or "") ~= "" then named = named + 1 end end
    local hide = named == 0 or named * 3 < #list
    local spec = c.auctionSpec.player
    if (spec.hide or false) ~= hide then spec.hide = hide; tbl.relayout(UI.G.mainW(UI.G.winW())) end
    c.auctionCols = { player = not hide }
    local rows, last = {}, nil
    for _, r in ipairs(list) do
      local k = date("%Y-%m-%d", r.t or 0)
      if k ~= last then last = k; rows[#rows + 1] = { ebSection = UI.fmtDay(r.t or 0) } end
      rows[#rows + 1] = r
    end
    tbl.setRows(rows, function(row, r)
      local cc = row.c
      cc.when:SetText(UI.fmtClock(r.t or 0))
      local look = r.item and GP.itemLook(r.item) or nil
      if cc.icon then cc.icon:SetTexture((look and look.icon) or "Interface\\Icons\\INV_Misc_QuestionMark") end
      if r.item then
        cc.item:SetText(r.item .. (num(r.count) > 1 and ("|cff8c9197 x" .. r.count .. "|r") or ""))
        if look and look.q then local lq = look.q; cc.item:SetTextColor(tonumber(lq:sub(3, 4), 16) / 255, tonumber(lq:sub(5, 6), 16) / 255, tonumber(lq:sub(7, 8), 16) / 255) end
      else cc.item:SetText("") end
      cc.result:SetText((r.what or "") .. ((r.what == "Posted" and r.hours) and (", " .. UI.fmtDur(r.hours * 3600)) or ""))
      if cc.player then cc.player:SetText(r.note or "") end
      cc.price:SetText(r.price and money(r.price) or "")
    end)
    -- (all time is every row the save still holds: the header says where they start, once)
    if sc.lifetime and #list > 0 then c.section:SetMeta("rows since " .. UI.fmtSince(num(list[#list].t))) end
    if #list == 0 then tbl.setState(ans and "No auction row of this period is kept." or GP.NO_AUCTION) end
  end
  -- the section header's right side, right to left: the view, then search (Journal only)
  local right = c.section.right
  c.viewSeg:ClearAllPoints(); c.viewSeg:SetPoint("TOPRIGHT", right, "TOPRIGHT", 0, 0)
  if view == "journal" then
    c.search:ClearAllPoints(); c.search:SetPoint("TOPRIGHT", c.viewSeg, "TOPLEFT", -S.S2, 0); c.search:Show()
  else c.search:Hide() end
end

-- one refresh: the period, its rows, the top and the list, then the layout
function GP.refresh(c)
  if not c or not c.st then return end
  local st = c.st
  local now = nowT()
  local isSession = not Gold.isDayScope(st.scope) and st.scope ~= "all"
  local sc = Gold.scope(st.scope, "char")
  if isSession and #sc.sessions == 0 and st.scope ~= "session" and st.scope ~= "previous" then
    st.scope = "today"; sc = Gold.scope("today", "char")
  end
  local entries = Gold.scopeEntries(sc)
  c.scopeData, c.entries, c.sourceData = sc, entries, Gold.sources(sc, entries)
  c.audit = nil
  local okA, a = pcall(Gold.audit, st.scope == "all" and "history" or st.scope, now)
  if okA and type(a) == "table" then c.audit = a end
  -- Sources is not offered for a period with dungeon time from before the coin capture of 0.9.52: the page opens
  -- on Journal, and the Sources button says why on hover (the screen's one history line)
  local off, fix = Gold.dungeonBefore(sc)
  c.srcOff = off and (fix or true) or nil
  c.view = GP.labelOf(GP.VIEWS, st.view) and st.view or "sources"
  if c.view == "sources" and off then c.view = "journal" end
  local sb = c.viewSeg.segs[1]
  sb.ebTip = off and { title = "Sources", text = GP.SOURCES_OFF:format((fix and fix ~= math.huge) and UI.fmtSince(fix) or "the next addon update") .. " " .. GP.SOURCES_OFF_WHY } or nil
  -- the control row: a quick period lights its segment; a session or a day opened from another page lights none
  c.period:SetValue(GP.labelOf(GP.PERIODS, st.scope) and st.scope or nil)
  c.period:ClearAllPoints(); c.period:SetPoint("TOPRIGHT", c.controls, "TOPRIGHT", 0, 0)
  GP.paintTop(c)
  GP.paintList(c)
  GP.place(c)
end

-- the page layout: cards, section header, (the Auction house answer,) list; one scroll
function GP.place(c)
  local G, H = UI.G, UI.H
  local w = G.mainW(G.winW())
  local col = c.col
  col:SetWidth(w)
  local y = 0
  local function put(f, h) f:ClearAllPoints(); f:SetPoint("TOPLEFT", col, "TOPLEFT", 0, -y); f:SetWidth(w); if h then f:SetHeight(h) end end
  put(c.cards, H.STAT); pcall(c.cards.layout); y = y + H.STAT
  y = y + S.S5
  put(c.section, H.SECTION); y = y + H.SECTION
  if c.answer:IsShown() then put(c.answer, H.SUMMARY); pcall(c.answer.layout); y = y + H.SUMMARY + S.S1 end
  local tbl = c.tbl[c.view]
  if tbl then
    put(tbl.frame); if tbl.width ~= math.min(w, G.TABLE_MAX) then tbl.relayout(w) end
    y = y + (tbl.height or 0)
  end
  y = y + S.S4
  col:SetHeight(y); c.sf:SetContentHeight(y)
  c.contentH = y
end

-- the source page: every entry of one source in the period (UI.Detail; Back "‹ Sources")
function GP.renderSource(c, r, content)
  local d = c.srcPage
  if not d.title then
    d.title = UI.Text(content, "TITLE", "fg"); d.title:SetPoint("TOPLEFT", content, "TOPLEFT", S.S3, 0)
    d.meta = UI.Text(content, "META", "fgMuted"); d.meta:SetPoint("TOPLEFT", content, "TOPLEFT", S.S3, -22)
    d.tbl = UI.KitTable(content, {
      { key = "time", label = "When", kind = "tag", min = 40, measure = { "00:00" } },
      { key = "detail", label = "Detail", flex = 1, min = 140 },
      { key = "loc", label = "Place", min = 120 },
      { key = "coords", label = "Coords", kind = "num", min = 72, wide = true },
      { key = "amount", label = "Amount", kind = "money", min = 88 },
    }, { tooltip = GP.journalTip })
  end
  local w = UI.G.mainW(UI.G.winW())
  content:SetWidth(w)
  d.title:SetText(GP.srcLabel(r.key))
  local list = {}
  for i = #c.entries, 1, -1 do local e = c.entries[i]; if e.src == r.key then list[#list + 1] = e end end
  local sum = 0
  for _, e in ipairs(list) do sum = sum + e.delta end
  local words = GP.periodWords(c.scopeData)
  d.meta:SetText(("%s \194\183 %s \194\183 %s"):format(words:sub(1, 1):upper() .. words:sub(2), UI.plural(#list, "time"), money(sum, true)))
  local rows, last = {}, nil
  for _, e in ipairs(list) do
    local k = date("%Y-%m-%d", e.t or 0)
    if k ~= last then last = k; rows[#rows + 1] = { ebSection = UI.fmtDay(e.t or 0) } end
    rows[#rows + 1] = e
  end
  d.tbl.frame:ClearAllPoints(); d.tbl.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(UI.LINE_H.TITLE + S.S1 + UI.LINE_H.META + S.S5)); d.tbl.frame:SetWidth(w)
  if d.tbl.width ~= math.min(w, UI.G.TABLE_MAX) then d.tbl.relayout(w) end
  d.tbl.setRows(rows, function(row, e)
    local cc = row.c
    cc.time:SetText(UI.fmtClock(e.t or 0))
    cc.detail:SetText(GP.detailOf(e))
    cc.loc:SetText(e.zone or "")
    if cc.coords then cc.coords:SetText((e.x and e.y) and UI.fmtCoords(e.x, e.y) or "") end
    cc.amount:SetText(money(e.delta, true))
  end)
  if #rows == 0 then d.tbl.setState("No entries for this source in this period.") end
  local h = UI.LINE_H.TITLE + S.S1 + UI.LINE_H.META + S.S5 + (d.tbl.height or 0) + S.S4
  content:SetHeight(h)
  if c.srcDetail.sf then c.srcDetail.sf:SetContentHeight(h) end
  c.srcShown = r
end

-- ── build ──
function ns.BuildEconomyPane(pane)
  local c = pane
  local cfg = (ns.DB and ns.DB.settings) or {}
  local st = { scope = GP.labelOf(GP.PERIODS, cfg.goldPeriod) and cfg.goldPeriod or "session", view = "sources", sortKey = "time", sortAsc = false }
  c.st = st
  local function again() GP.refresh(c) end
  c.refresh = again
  local function closeSource() if c.srcDetail and c.srcDetail.IsOpen() then c.srcDetail.Close() end end
  local function setScope(key) closeSource(); st.scope = key; again() end
  local function setView(key)
    closeSource()
    -- (Sources while it is not offered for this period: the click changes nothing)
    if key == "sources" and c.srcOff then c.viewSeg:SetValue(c.view); return end
    st.view = GP.labelOf(GP.VIEWS, key) and key or "sources"
    if st.view ~= "journal" and (c.search:GetText() or "") ~= "" then c.search:SetText("") end
    again()
  end
  c.setScope, c.setView = setScope, setView
  -- the page: one scroll
  c.list = CreateFrame("Frame", nil, c); c.list:SetAllPoints(c)
  local sf, child = UI.ScrollChild(c.list, { slim = true, top = 0, left = 0, right = 0, bottom = 0 })
  c.sf = sf
  c.col = CreateFrame("Frame", nil, child); c.col:SetPoint("TOPLEFT", child, "TOPLEFT", 0, 0); c.col:SetSize(1, 1)
  local col = c.col
  -- the control row: Session, Today, Week, All
  c.controls = c.ebControls or c
  c.period = UI.Segmented(c.controls, GP.PERIODS, { value = st.scope, onPick = function(key)
    if ns.DB and ns.DB.settings then ns.DB.settings.goldPeriod = key end
    setScope(key)
  end })
  -- the four cards; BALANCE's hover holds the full amount and the audit, NET's what it counts
  local function balTip(tip, owner)
    tip:AddLine(owner.label:GetText() or "Balance", 1, 1, 1)
    tip:AddLine(fmtMoney(num(owner.ebBal), { icons = true }), DIM[1], DIM[2], DIM[3])
    local ok, ro = pcall(Gold.roster, "all")
    if ok and ro then pair(tip, "All characters", fmtMoney(ro.total, { icons = true })) end
    if c.audit and (c.audit.state == "ok" or c.audit.state == "broken") then
      line(tip, c.audit.state == "ok" and "The records add up for this period." or "The records do not add up for this period.")
    end
    if c.audit and c.audit.state == "broken" then Gold.auditTip(tip, c.audit) end
  end
  local function tracedTip(i, title, word)
    return function(tip)
      local g = c.scopeData and c.scopeData.ledger or {}
      tip:AddLine(title, 1, 1, 1)
      tip:AddLine(fmtMoney(num(i == 1 and g.gained or g.spent), { icons = true }), DIM[1], DIM[2], DIM[3])
      local u = c.notTraced and c.notTraced[i] or 0
      if u > 0 then pair(tip, word, fmtMoney(u)); line(tip, GP.UNTRACED_TIP) end
    end
  end
  local function netTip(tip)
    tip:AddLine("Net", 1, 1, 1)
    line(tip, "Earned minus spent in this period. Per hour shows after 30 minutes of play in the period.")
    local sc = c.scopeData
    if sc and c.rate then pair(tip, "Played", UI.fmtPlayed(sc.elapsed)) end
    if num(c.crashAmt) ~= 0 then
      pair(tip, "Unattributed", fmtMoney(c.crashAmt))
      line(tip, "The game closed without saving, so the addon could not see where this went. It is counted in the net.")
    end
    local away = sc and not sc.lifetime and (num(sc.ledger.away) - num(c.crashAmt)) or 0
    if away ~= 0 then pair(tip, GP.UNTRACED.away, signed(away)); line(tip, GP.AWAY_TIP .. " It is not in the net.") end
  end
  c.cards = UI.StatRow(col, 4, { { tip = balTip }, { tip = tracedTip(1, "Earned", GP.UNTRACED.unexplained) }, { tip = tracedTip(2, "Spent", GP.UNTRACED.other) }, { tip = netTip } })
  -- the list's section header (the period) and its controls: the view, and search on Journal
  c.section = UI.Section(col, "This session")
  -- the controls own the header's right side: the meta follows the label instead
  c.section.meta:ClearAllPoints(); c.section.meta:SetPoint("LEFT", c.section.label, "RIGHT", S.S2, 0); c.section.meta:SetJustifyH("LEFT")
  local right = c.section.right
  c.viewSeg = UI.Segmented(right, GP.VIEWS, { value = st.view, onPick = function(key) setView(key) end })
  do
    -- (Sources greys out while it is not offered for the period; its hover says why)
    local paint = c.viewSeg.paint
    c.viewSeg.paint = function()
      paint()
      if c.srcOff then c.viewSeg.segs[1].text:SetTextColor(C.fgFaint[1], C.fgFaint[2], C.fgFaint[3]) end
    end
    UI.SetTip(c.viewSeg.segs[1], nil)
  end
  c.search = UI.Search(right, "Search entries")
  c.search:HookScript("OnTextChanged", function() if c.scopeData then again() end end)
  c.search:Hide()
  -- the Auction house answer, under the section header
  c.answer = UI.Summary(col); c.answer:Hide()
  -- the tables, one per view
  c.tbl = {}
  c.tbl.sources = UI.KitTable(col, {
    { key = "src", label = "Source", flex = 1, min = 140 },
    -- (the largest group of the source as a name that may shorten and its amount in a money cell of its own: a
    -- number is never cut, 2.4)
    { key = "what", label = "Mostly from", flex = 1, min = 96, max = 220 },
    { key = "whatAmt", label = "", kind = "money", min = 40 },
    { key = "amount", label = "Amount", kind = "money", min = 88, strong = true },
  }, { tooltip = GP.sourceTip, onHeight = function() pcall(GP.place, c) end,
    onClick = function(_, r) if r and r.key and r.dir ~= 0 and r.n > 0 then Gold.filter(r.key) end end })
  c.tbl.journal = UI.KitTable(col, {
    { key = "time", label = "When", kind = "tag", min = 40, measure = { "00:00" }, sort = true },
    { key = "src", label = "Source", kind = "tag", min = 88, sort = true, measure = { GP.UNTRACED.other } },
    { key = "detail", label = "Detail", flex = 1, min = 140, sort = true },
    { key = "loc", label = "Place", min = 120, sort = true },
    { key = "coords", label = "Coords", kind = "num", min = 72, wide = true },
    { key = "amount", label = "Amount", kind = "money", min = 88, sort = true, strong = true },
    { key = "bal", label = "Balance", kind = "money", min = 88, wide = true, tip = "Your balance after this entry" },
  }, { sortKey = "time", sortAsc = false, tooltip = GP.journalTip, onHeight = function() pcall(GP.place, c) end,
    onSort = function(key, asc) st.sortKey, st.sortAsc = key, asc; again() end })
  -- (the item cell is the Items one: its icon, the name in its quality's colour, "x3" after it)
  local aSpec = {
    { key = "when", label = "When", kind = "tag", min = 40, measure = { "00:00" } },
    { key = "icon", label = "", kind = "icon" },
    { key = "item", label = "Item", flex = 1, min = 140 },
    { key = "result", label = "Result", kind = "tag", min = 72, measure = { "Posted, 2d", "Cancelled" } },
    { key = "player", label = "Player", min = 104, tip = "Who bought it, or who sold it to you" },
    { key = "price", label = "Price", kind = "money", min = 88, tip = "For the whole stack. A sale: what the buyer paid." },
  }
  c.auctionSpec = {}
  for _, sp in ipairs(aSpec) do c.auctionSpec[sp.key] = sp end
  c.tbl.auctions = UI.KitTable(col, aSpec, { tooltip = GP.auctionTip, onHeight = function() pcall(GP.place, c) end })
  for _, t in pairs(c.tbl) do t.frame:Hide() end
  -- the source page
  c.srcDetail = UI.Detail(c, { list = c.list, back = "\226\128\185 Sources",
    render = function(r, content) GP.renderSource(c, r, content) end,
    onBack = function() again() end })
  c.srcPage = {}
  c:HookScript("OnSizeChanged", function() if c.scopeData then pcall(GP.place, c) end end)
  again()
  return again
end

-- LOOT / Gold pane (the Loot host is declared by Emitter.lua with the Items pane)
UI.registerPane("Loot", 2, "Gold", function(content) GP.content = content; GP.refreshFn = ns.BuildEconomyPane(content) end,
  function() if GP.refreshFn and not (GP.content.srcDetail and GP.content.srcDetail.IsOpen()) then GP.refreshFn() end; Gold.rateWatch() end,
  "Where your gold came from and where it went, traced to every copper.")

-- the open pane follows the purse: one refresh 0.1 s after the first of a burst of changes
function GP.showing(f)
  for _ = 1, 20 do
    if not f then return true end
    if f.IsShown and not f:IsShown() then return false end
    f = f.GetParent and f:GetParent() or nil
  end
  return true
end
Gold.onChange(function()
  if not (GP.refreshFn and GP.content) then return end
  if not (C_Timer and type(C_Timer.After) == "function") then return end
  local now = GetTime()
  if Gold._refreshQueued and now - Gold._refreshQueued < 1 then return end
  Gold._refreshQueued = now
  C_Timer.After(0.1, function()
    Gold._refreshQueued = nil
    if GP.refreshFn and GP.showing(GP.content) and not GP.content.srcDetail.IsOpen() then pcall(GP.refreshFn) end
  end)
end)

-- the 10 s repaint of the open pane: the cards only (the list keeps its place)
function Gold.paneShowing() return (GP.content ~= nil and GP.refreshFn ~= nil and GP.showing(GP.content)) and true or false end
function Gold.paneRate()
  local c = GP.content
  if not (c and c.scopeData and Gold.paneShowing()) then return end
  if c.scopeData.live then
    c.scopeData = Gold.scope(c.st.scope, "char")
    pcall(GP.paintTop, c)
  end
end

-- Open the Gold pane on a period: "session", "previous", "all", a session id or a day period (Home > Now, the
-- session page). view: "sources" (the default), "auctions" or "journal"; a key of a view that no longer exists opens
-- Sources. flags: true opens the Journal (the entries worth a look were a list of their own before 0.9.52).
function Gold.open(scope, view, flags)
  UI.Open("Loot", "gold")
  local c = GP.content
  if not (c and c.st) then return end
  if c.srcDetail and c.srcDetail.IsOpen() then c.srcDetail.Close() end
  local st = c.st
  st.scope = scope or "session"
  st.view = flags and "journal" or (GP.labelOf(GP.VIEWS, view) and view or "sources")
  if c.search then c.search:SetText("") end
  if GP.refreshFn then GP.refreshFn() end
end

-- the source page of one source in the open period (a click on its Sources row does the same)
function Gold.filter(src)
  local c = GP.content
  if not (c and c.st and c.sourceData and Gold.LABEL[src]) then return end
  local list, index = {}, 1
  for _, r in ipairs(c.sourceData.rows) do
    if r.dir ~= 0 and r.n > 0 then list[#list + 1] = r; if r.key == src then index = #list end end
  end
  if #list == 0 then return end
  c.srcDetail:Open(list, index)
end

-- the roster filters of Settings > Gold (Characters in the Gold pane uses the saved one for this character)
local FILTERS = { { "all", "All characters" }, { "realm", "This realm" }, { "faction", "This faction" }, { "realmFaction", "This realm and faction" } }
Gold.FILTERS = FILTERS
local labelOf = GP.labelOf

-- ── Settings > Gold display (0.9.45, everbuff-wow-addon #43; restyled for docs/UX_OVERHAUL.md 4.12) ──────────────
-- Built into the Gold display sub-tab of Settings by Sync.lua (ns.BuildSettings). The main page holds the controls
-- most players touch, as setting rows; the rest sits behind "More". A choice of several values is a button that
-- opens the addon's own list (Gold.ownMenu). Same settings and the same writes as before the restyle.
function ns.BuildGoldSettings(pane)
  local K = UI.S
  local SV = ns.SettingsView
  local main, more = CreateFrame("Frame", nil, pane), CreateFrame("Frame", nil, pane)
  main:SetAllPoints(pane); more:SetAllPoints(pane); more:Hide()
  pane.main, pane.more = main, more
  local mainPg, morePg = UI.Page(main), UI.Page(more)
  pane.mainPg, pane.morePg = mainPg, morePg
  local checks, loading = {}, false
  local function refresh() if pane.refresh then pane.refresh() end end
  local function row(pg, text, desc) return UI.SettingRow(pg.col, text, desc) end
  local function checkbox(pg, text, get, set, desc)
    local r = row(pg, text, desc)
    local cb = UI.Checkbox(r, { onChange = function(on) set(on and true or false); refresh() end })
    cb.label, cb.get, cb.row = r.label, get, r
    r:SetControl(cb)
    checks[#checks + 1] = cb
    return cb
  end
  -- a button that opens a list of choices { key, label }; `get` names the current key, `set` takes the picked one
  local function picker(pg, text, choices, get, set)
    local r = row(pg, text)
    local b = UI.Box(r, nil, "lineStrong", 1, "Button")
    b:SetHeight(UI.H.CONTROL)
    b.text = UI.Text(b, "BODY_STRONG", "fgSubtle"); b.text:SetPoint("LEFT", b, "LEFT", K.S3, 0)
    b.chev = UI.Glyph(b, "chevronDown", 8, "fgSubtle"); b.chev:SetPoint("RIGHT", b, "RIGHT", -K.S2, 0)
    b:SetScript("OnClick", function(bb)
      UI.Click()
      local items = {}
      for _, ch in ipairs(choices) do
        items[#items + 1] = { kind = "radio", text = ch[2], checked = function() return get() == ch[1] end, pick = function() set(ch[1]); refresh() end }
      end
      Gold.ownMenu(bb, items)
    end)
    b:SetScript("OnEnter", function(s) UI.BoxColors(s, nil, "lineControl") end)
    b:SetScript("OnLeave", function(s) UI.BoxColors(s, nil, "lineStrong") end)
    b.choices, b.get, b.row = choices, get, r
    function b.fit() b:SetWidth(UI.TextWidth("BODY_STRONG", b.text:GetText()) + 44); r:SetControl(b) end
    r:SetControl(b)
    return b
  end
  local function slider(pg, text, lo, hi, step, get, set, fmt)
    local r = row(pg, text)
    local s = UI.Slider(r, { min = lo, max = hi, step = step, value = get(), fmt = fmt, onChange = function(v) if not loading then set(v) end end })
    s.label, s.caption, s.get, s.fmt, s.row = r.label, text, get, fmt, r
    r:SetControl(s)
    return s
  end
  local function button(pg, text, btnText, style, fn, desc)
    local r = row(pg, text, desc)
    local b = UI.KitButton(r, btnText, style, fn)
    b.row = r
    r:SetControl(b)
    return b
  end
  local function section(pg, label) return { head = UI.Section(pg.col, label), items = {} } end

  -- ── the main page ──
  local onScreen = section(mainPg, "Gold on screen")
  -- (what bar text needs is the description of this row: a 48 px row, not a loose note under the list)
  pane.cbPill = checkbox(mainPg, "Show your gold on screen",
    function() return (Gold.pillCfg() or {}).on == true end,
    function(v) Gold.pillOn(v) end, "Bar text needs a bar addon such as Titan Panel or ElvUI")
  pane.cbTips = checkbox(mainPg, "Show gold in tooltips",
    function() local cfg = Gold.cfg(); return not (cfg and cfg.tips == false) end,
    function(v) Gold.cfg(true).tips = v end)
  pane.pick1 = picker(mainPg, "On screen it shows", Gold.GLANCE, function() return Gold.pillMetrics()[1] end, function(k) Gold.pillSet(1, k) end)
  local second = { { "none", "None" } }
  for _, g in ipairs(Gold.GLANCE) do second[#second + 1] = g end
  pane.pick2 = picker(mainPg, "Second value", second, function() return Gold.pillMetrics()[2] or "none" end, function(k) Gold.pillSet(2, k ~= "none" and k or nil) end)
  local rateRow = row(mainPg, "Per hour", " ")
  pane.rateSeg = UI.Segmented(rateRow, Gold.RATE_MODES, { onPick = function(k) Gold.cfg(true).rateMode = k; Gold.fire(); refresh() end })
  rateRow:SetControl(pane.rateSeg)
  pane.rateBtns = pane.rateSeg.segs
  for i, b in ipairs(pane.rateBtns) do b.mode = Gold.RATE_MODES[i][1] end
  pane.rateNote = rateRow.desc
  pane.pickFilter = picker(mainPg, "Show gold from", FILTERS, function() local f = (Gold.cfg() or {}).filter; return labelOf(FILTERS, f) and f or "all" end,
    function(k) Gold.cfg(true).filter = k; Gold.fire() end)
  pane.cbIcons = checkbox(mainPg, "Coin icons",
    function() return (Gold.cfg() or {}).icons == true end, function(v) Gold.cfg(true).icons = v; Gold.fire() end)
  pane.cbCompact = checkbox(mainPg, "Compact numbers",
    function() return (Gold.cfg() or {}).compact == true end, function(v) Gold.cfg(true).compact = v; Gold.fire() end)
  pane.barText = pane.cbPill.row.desc
  pane.moreBtn = button(mainPg, "Pill size, tooltip rows and resets", "More \226\128\186", "ghost", function() main:Hide(); more:Show(); refresh() end)
  onScreen.items = { pane.cbPill.row, pane.cbTips.row, pane.pick1.row, pane.pick2.row, rateRow, pane.pickFilter.row, pane.cbIcons.row, pane.cbCompact.row, pane.moreBtn.row }
  -- hidden characters, each with "Show again"
  local hiddenSec = section(mainPg, "Hidden characters")
  local noneNote = SV.note(mainPg.col, "None. Hide a character in Loot > Gold.")
  pane.hiddenNone = noneNote.text
  pane.hiddenNoneRow = noneNote
  hiddenSec.items[1] = noneNote
  pane.hiddenRows = {}
  for i = 1, 6 do
    local b
    b = button(mainPg, "", "Show again", "ghost", function(bb)
      local cfg = Gold.cfg(true)
      if type(cfg.hidden) == "table" and bb.guid then
        cfg.hidden[bb.guid] = nil
        if next(cfg.hidden) == nil then cfg.hidden = nil end
      end
      Gold.fire(); refresh()
    end)
    pane.hiddenRows[i] = { name = b.row.label, btn = b, row = b.row }
    hiddenSec.items[#hiddenSec.items + 1] = b.row
  end
  local moreNote = SV.note(mainPg.col, "")
  pane.hiddenMore = moreNote.text
  pane.hiddenMoreRow = moreNote
  hiddenSec.items[#hiddenSec.items + 1] = moreNote
  pane.mainSections = { onScreen, hiddenSec }

  -- ── behind "More" ──
  local back = { head = UI.Section(morePg.col, "More gold settings"), items = {} }
  pane.backBtn = UI.KitButton(back.head.right, "\226\128\185 Gold display", "ghost", function() more:Hide(); main:Show(); refresh() end)
  pane.backBtn:SetPoint("TOPRIGHT", back.head.right, "TOPRIGHT", -K.S3, 0)
  pane.cbLock = checkbox(morePg, "Lock the pill",
    function() return (Gold.pillCfg() or {}).locked == true end, function(v) Gold.pillOpt("locked", v) end)
  local function pct(v) return ("%d%%"):format(math.floor(v * 100 + 0.5)) end
  pane.slScale = slider(morePg, "Pill text size", Gold.PILL_SCALE[1], Gold.PILL_SCALE[2], 0.05,
    function() return tonumber((Gold.pillCfg() or {}).scale) or 1 end,
    function(v) if not Gold.inCombat() then Gold.pillOpt("scale", v) end end, pct)
  pane.slAlpha = slider(morePg, "Pill opacity", Gold.PILL_ALPHA[1], Gold.PILL_ALPHA[2], 0.05,
    function() return tonumber((Gold.pillCfg() or {}).alpha) or 1 end,
    function(v) if not Gold.inCombat() then Gold.pillOpt("alpha", v) end end, pct)
  back.items = { pane.cbLock.row, pane.slScale.row, pane.slAlpha.row }
  local tipsSec = section(morePg, "Tooltips")
  pane.slRows = slider(morePg, "Characters in tooltips", 5, 30, 1,
    function() return math.max(5, math.min(30, tonumber((Gold.tipCfg() or {}).limit) or Gold.TIP_ROWS)) end,
    function(v) Gold.tipCfg(true).limit = math.max(5, math.min(30, math.floor((tonumber(v) or Gold.TIP_ROWS) + 0.5))) end,
    function(v) return tostring(v) end)
  pane.cbWeek = checkbox(morePg, "This week in tooltips",
    function() return (Gold.tipCfg() or {}).week == true end, function(v) Gold.tipCfg(true).week = v end)
  pane.cbMonth = checkbox(morePg, "This month in tooltips",
    function() return (Gold.tipCfg() or {}).month == true end, function(v) Gold.tipCfg(true).month = v end)
  tipsSec.items = { pane.slRows.row, pane.cbWeek.row, pane.cbMonth.row }
  local resetSec = section(morePg, "Reset")
  pane.resetPos = button(morePg, "Pill position", "Reset", "ghost", function() if not (ns.blockedInCombat and ns.blockedInCombat()) then Gold.pillOpt("pos") end end)
  pane.resetRate = button(morePg, "Per hour", "Reset", "ghost", function() Gold.resetRate(); refresh() end)
  -- two clicks: the first names what goes, the second within 3 s deletes it
  local RESET, CONFIRM = "Reset gold history", "Confirm: delete this character's day history"
  pane.resetHist = button(morePg, "Gold history", RESET, "danger", nil, "Cannot be undone.")
  local function rest(bb) bb.armed = false; bb:SetLabel(RESET); bb.row:SetControl(bb) end
  pane.resetHist.ebOnClick = function(bb)
    if not bb.armed then
      bb.armed = true
      bb:SetLabel(CONFIRM); bb.row:SetControl(bb)
      if C_Timer and type(C_Timer.After) == "function" then C_Timer.After(3, function() if bb.armed then rest(bb) end end) end
    else
      rest(bb)
      Gold.resetHistory()
      refresh()
    end
  end
  local resetNote = SV.note(morePg.col, "Reset gold history deletes this character's day rows, its records, its per hour window and its farm timer. The balance, the lifetime totals, the places and the dungeon runs stay, and no other character is touched.")
  pane.resetNote = resetNote.text
  resetSec.items = { pane.resetPos.row, pane.resetRate.row, pane.resetHist.row, resetNote }
  pane.moreSections = { back, tipsSec, resetSec }
  local function place()
    SV.place(mainPg, pane.mainSections)
    SV.place(morePg, pane.moreSections)
  end
  pane.place = place

  function pane.refresh()
    loading = true
    for _, b in ipairs({ pane.pick1, pane.pick2, pane.pickFilter }) do Gold.menuClose(b) end   -- no list left over a page that changed
    for _, cb in ipairs(checks) do cb:SetChecked(cb.get() and true or false) end
    for _, b in ipairs({ pane.pick1, pane.pick2, pane.pickFilter }) do
      b.text:SetText(labelOf(b.choices, b.get()) or b.choices[1][2]); b.fit()
    end
    local mode = Gold.rateMode()
    pane.rateSeg:SetValue(mode)
    for _, b in ipairs(pane.rateBtns) do b.ebSelected = (b.mode == mode) or nil end
    pane.rateNote:SetText(Gold.RATE_NOTE[mode])
    pane.barText:SetText(Gold._broker and "Bar text: detected" or "Bar text needs a bar addon such as Titan Panel or ElvUI")
    for _, s in ipairs({ pane.slScale, pane.slAlpha, pane.slRows }) do s:SetValue(s.get(), true) end
    -- the hidden characters by name, the first six; the rest as a count
    local cfg = Gold.cfg()
    local hidden = {}
    for guid in pairs(cfg and type(cfg.hidden) == "table" and cfg.hidden or {}) do
      local blk = ns.DB and type(ns.DB.characters) == "table" and ns.DB.characters[guid]
      local nm = type(blk) == "table" and type(blk.name) == "string" and blk.name or "No longer in the save file"
      if type(blk) == "table" and type(blk.surname) == "string" then nm = nm .. " " .. blk.surname end
      hidden[#hidden + 1] = { guid = guid, name = nm }
    end
    table.sort(hidden, function(a, b) if a.name ~= b.name then return a.name < b.name end return tostring(a.guid) < tostring(b.guid) end)
    for i, r in ipairs(pane.hiddenRows) do
      local h = hidden[i]
      if h then r.name:SetText(h.name); r.name:Show(); r.btn.guid = h.guid; r.btn:Show(); r.row:Show(); pcall(r.row.layout)
      else r.name:SetText(""); r.name:Hide(); r.btn:Hide(); r.row:Hide() end
    end
    if #hidden == 0 then pane.hiddenNone:Show(); pane.hiddenNoneRow:Show() else pane.hiddenNone:Hide(); pane.hiddenNoneRow:Hide() end
    local extra = #hidden > #pane.hiddenRows and ("and %d more"):format(#hidden - #pane.hiddenRows) or ""
    pane.hiddenMoreRow:Set(extra)
    if extra == "" then pane.hiddenMoreRow:Hide() else pane.hiddenMoreRow:Show() end
    place()
    loading = false
  end
  pane:HookScript("OnShow", function() pcall(pane.refresh) end)
  pane:HookScript("OnSizeChanged", function() pcall(place) end)
  -- (a hidden parent hides its children without their own OnHide on some clients: the pane and its pages say so too)
  for _, fr in ipairs({ pane, main, more }) do
    fr:HookScript("OnHide", function() for _, b in ipairs({ pane.pick1, pane.pick2, pane.pickFilter }) do Gold.menuClose(b) end end)
  end
  pane.refresh()
  return pane.refresh
end

-- ── test exports: headless luajit tests in tests/ read these; no effect in-game ──
ns._test = ns._test or {}
ns._test.economyFmtMoney = fmtMoney
ns._test.goldPane = function() return GP.content end
