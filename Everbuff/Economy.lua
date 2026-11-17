-- Everbuff.GG · Economy.lua - gold over the journey (the Gold pane of the LOOT tab).
--
-- Gold pace and the cost of leveling: a staple journey metric a pure combat recorder never touches.
-- Reads the running totals Emitter captures from PLAYER_MONEY (balance / looted / gained / spent).
-- Since 2026-09-25 this is not a top-level tab: it is the Gold pane of the Loot tab (ns.BuildEconomyPane).
--
-- Layout (founder, 2026-11-17: overflowing text on the loot screen). Everything is placed by relayout(w, h), which
-- runs on the pane's OnSizeChanged and after every refresh, from the pane's own size:
--   cards    five cards in one row when each one is wide enough for its value and subtitle (NET's with its rate on
--            the same line), else three over two, each row filling the width (no hole); a card that needs more than
--            an equal share gets it when the row has room. Card text is anchored to both card edges with 12 px
--            padding, one line each; NET's per-hour rate gets its own line inside the card only when it cannot fit
--            beside "gained minus spent". Every card of a row is as tall as the tallest.
--   ledgers  IN and OUT side by side, label left (dim) and amount right, a zero row dimmed. Each ledger is one
--            column of rows when the pane is tall enough, else two columns of label/amount pairs; a pair is never
--            wider than PAIR_W, so an amount stays near its label however wide the pane is.
--   note     anchored to both pane edges below the ledgers, wrapping.

local ADDON, ns = ...
local UI = ns.UI
local C = ns.UI.C

local fmtMoney = ns.fmtMoney   -- the one formatter (UI.lua)

local SP = UI.SP
local PAD, GAP, ROW_H = SP.PAD, SP.M, UI.ROW_H
local INSET = PAD   -- ledger text lines up with the card text above it
-- the pane's own edge: the cards, ledgers and note start where the Items toolbar and the Auctions rows start, at the
-- pane's edge; the 12 px padding is inside each card and ledger
local MARGIN = 0
local SEP = "  ·  "
local PAIR_W = 280     -- widest label/amount pair: wider, the eye loses the row between label and amount
-- the cards in reading order: the purse, what came in and went out, the looted share of it, and the net
local CARDS = {
  { key = "cBalance", label = "BALANCE", color = "gold" },
  { key = "cGained",  label = "GAINED",  color = "green" },
  { key = "cSpent",   label = "SPENT",   color = "red" },
  { key = "cLooted",  label = "LOOTED",  color = "gold" },
  { key = "cNet",     label = "NET THIS SESSION", color = "green" },
}
local IN_LABELS  = { "looted", "quests", "sold", "auctions", "mail", "trade", "other" }
local OUT_LABELS = { "repairs", "vendor", "training", "flights", "auctions", "mail", "trade", "other" }

local function num(v) return (type(v) == "number" and v == v) and v or 0 end
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

-- the values of one refresh: card texts and the two ledgers' rows ({ label, copper })
local function values()
  local g = (ns.DB and ns.char().gold) or {}
  local gained, looted, sold = num(tonumber(g.gained)), num(tonumber(g.looted)), num(tonumber(g.sold))
  local auctions, mail, quests, trade = num(tonumber(g.auctionSales)), num(tonumber(g.mail)), num(tonumber(g.quests)), num(tonumber(g.trade))
  local v = {}
  v.inRows = { looted, quests, sold, auctions, mail, trade, math.max(0, gained - looted - quests - sold - auctions - mail - trade) }
  v.outRows = { num(g.repairs), num(g.vendor), num(g.training), num(g.flights), num(g.auctions), num(g.mailSpent), num(g.tradeSpent), num(g.other) }
  v.cBalance, v.cLooted, v.cGained, v.cSpent = fmtMoney(g.balance or 0), fmtMoney(g.looted or 0), fmtMoney(g.gained or 0), fmtMoney(g.spent or 0)
  v.subs = { cBalance = "current purse", cLooted = "coin picked up from mobs and chests", cGained = "everything that came in", cSpent = "everything that went out", cNet = "gained minus spent" }
  local net = num(tonumber(g.gained)) - num(tonumber(g.spent))
  local ses = (ns.Recorder and ns.Recorder.current and ns.Recorder.current()) or {}
  local elapsed = (ses.startedEpoch and ((GetServerTime and GetServerTime()) or time()) - ses.startedEpoch) or 0
  local snet = num(tonumber(ses.gained)) - num(tonumber(ses.spent))
  if elapsed >= 120 and snet ~= 0 then
    local perHr = snet / (elapsed / 3600)
    v.rate = ("%s%s per hour this session"):format(perHr < 0 and "-" or "+", fmtMoney(math.abs(perHr)))
  else
    v.rate = "per-hour rate after a few minutes"
  end
  v.cNet, v.netNeg = (net < 0 and "-" or "") .. fmtMoney(math.abs(net)), net < 0
  return v
end

-- ── layout ───────────────────────────────────────────────────────────────────
-- the width a card needs: its widest line plus the padding. NET counts its subtitle with the rate on the same line,
-- so a row only gets narrow enough to push the rate onto a line of its own when nothing else fits.
local function cardNeed(p)
  local sub = textW(p.base)
  if p.rate and p.probe then
    p.probe:SetText((p.baseText or "") .. SEP .. (p.rateText or ""))
    sub = textW(p.probe)
  end
  return math.max(textW(p.title), textW(p.value), sub) + 2 * PAD
end
-- the widths of one row of cards `avail` px wide: equal when every card fits; else each card gets what it needs and
-- the rest is shared equally; equal again when the needs do not fit at all. The widths add up to `avail`.
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
  out[n] = avail - sum   -- the last card takes the rounding, so the row ends at the edge
  return out
end
-- place one card at (x, y) w wide; returns the height its text needs
local function placeCard(c, p, x, y, w)
  p:ClearAllPoints(); p:SetPoint("TOPLEFT", c, "TOPLEFT", x, y); p:SetWidth(w)
  if p.rate then
    -- NET: "gained minus spent  ·  <rate>" on one line when it fits, else the rate on its own line below
    local inner = w - 2 * PAD
    p.probe:SetText(p.baseText .. SEP .. p.rateText)
    if textW(p.probe) <= inner then
      p.sub:SetText(p.baseText .. SEP .. p.rateText); p.rate:SetText(""); p.rate:Hide()
    else
      p.sub:SetText(p.baseText); p.rate:SetText(p.rateText); p.rate:Show()
    end
  end
  local h = PAD + lineH(p.title, 13) + SP.XS + lineH(p.value, 22) + SP.XS + lineH(p.sub, 13) + PAD
  if p.rate and p.rate:IsShown() then h = h + 2 + lineH(p.rate, 13) end
  return h
end
-- place one ledger (header, rule and its label/amount pairs) at (x, y) w wide in cols columns; returns its height
local function placeLedger(c, L, x, y, w, cols)
  L:ClearAllPoints(); L:SetPoint("TOPLEFT", c, "TOPLEFT", x, y); L:SetWidth(w)
  local n = #L.pairs
  local per = math.ceil(n / cols)
  -- the pairs share the width inside the ledger's inset, SP.L apart, never wider than PAIR_W (an amount stays near
  -- its label); a pair's label and amount touch its edges
  local pw = math.min(PAIR_W, math.floor((w - 2 * INSET - (cols - 1) * SP.L) / cols))
  L.pairW = pw
  for i, pr in ipairs(L.pairs) do
    local col, row = math.floor((i - 1) / per), (i - 1) % per
    local px = INSET + col * (pw + SP.L)
    pr:ClearAllPoints()
    pr:SetPoint("TOPLEFT", L, "TOPLEFT", px, -(ROW_H + 1 + row * ROW_H))
    pr:SetSize(pw, ROW_H)
  end
  local h = ROW_H + 1 + per * ROW_H
  L:SetHeight(h)
  return h
end

local function relayout(c, w, h)
  w, h = tonumber(w) or 0, tonumber(h) or 0
  if w <= 2 * PAD + 10 then return end   -- (narrower than any card)
  c.layoutW, c.layoutH = w, h
  local W = w - 2 * MARGIN
  -- cards: five in a row when each fits with its subtitle on one line, else three over two; a row fills the width
  local need, needs = 0, {}
  for i, d in ipairs(CARDS) do needs[i] = cardNeed(c[d.key]); need = math.max(need, needs[i]) end
  local rows = ((W - 4 * GAP) / 5 >= need) and { { 1, 2, 3, 4, 5 } } or { { 1, 2, 3 }, { 4, 5 } }
  c.cardRows = #rows
  local y = -MARGIN
  for _, r in ipairs(rows) do
    local n = #r
    local rn = {}
    for i, idx in ipairs(r) do rn[i] = needs[idx] end
    local widths = rowWidths(rn, W - (n - 1) * GAP)
    local tallest, x = 0, MARGIN
    for i, idx in ipairs(r) do
      tallest = math.max(tallest, placeCard(c, c[CARDS[idx].key], x, y, widths[i]))
      x = x + widths[i] + GAP
    end
    for _, idx in ipairs(r) do c[CARDS[idx].key]:SetHeight(tallest) end
    y = y - tallest - GAP
  end
  -- ledgers: one column of rows when the pane is tall enough for them and the note, else two columns of pairs
  y = y - (SP.L - GAP)
  local lw = math.floor((W - GAP) / 2)
  local noteH = lineH(c.note, 42)
  local longest = math.max(#c.ledIn.pairs, #c.ledOut.pairs)
  local tall = h <= 0 or -y + ROW_H + 1 + longest * ROW_H + SP.L + noteH + MARGIN <= h
  local cols = tall and 1 or 2   -- (a pair is capped at PAIR_W, so a wide ledger never spreads label from amount)
  c.ledgerCols = cols
  local hIn = placeLedger(c, c.ledIn, MARGIN, y, lw, cols)
  local hOut = placeLedger(c, c.ledOut, MARGIN + W - lw, y, lw, cols)
  c.ledIn:SetHeight(math.max(hIn, hOut)); c.ledOut:SetHeight(math.max(hIn, hOut))   -- side by side, one height
  y = y - math.max(hIn, hOut) - SP.L
  c.note:ClearAllPoints()
  c.note:SetPoint("TOPLEFT", c, "TOPLEFT", MARGIN + INSET, y); c.note:SetPoint("TOPRIGHT", c, "TOPRIGHT", -(MARGIN + INSET), y)
end

local function refresh(c)
  if not c or not c.cBalance then return end
  local v = values()
  for _, d in ipairs(CARDS) do
    local p = c[d.key]
    p.value:SetText(v[d.key])
    p.baseText = v.subs[d.key]
    p.base:SetText(p.baseText)
    if not p.rate then p.sub:SetText(p.baseText) end
  end
  c.cNet.rateText = v.rate
  local nc = v.netNeg and C.red or C.green
  c.cNet.value:SetTextColor(nc[1], nc[2], nc[3])
  for _, L in ipairs({ { c.ledIn, v.inRows }, { c.ledOut, v.outRows } }) do
    for i, pr in ipairs(L[1].pairs) do
      local cp = L[2][i] or 0
      pr.amount:SetText(fmtMoney(cp))
      local zero = cp == 0
      pr.label:SetTextColor(C.dim[1], C.dim[2], C.dim[3], zero and 0.55 or 1)
      if zero then pr.amount:SetTextColor(C.dim[1], C.dim[2], C.dim[3], 0.55)
      else pr.amount:SetTextColor(C.ink[1], C.ink[2], C.ink[3], 1) end
    end
  end
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
  p:SetHeight(80)
  local function two(fs, above, gapY)
    fs:SetPoint("TOPLEFT", above or p, above and "BOTTOMLEFT" or "TOPLEFT", above and 0 or PAD, -(gapY or PAD))
    fs:SetPoint("TOPRIGHT", above or p, above and "BOTTOMRIGHT" or "TOPRIGHT", above and 0 or -PAD, -(gapY or PAD))
    fs:SetJustifyH("LEFT")
    return fs
  end
  p.title = two(oneLine(UI.FS(p, "GameFontNormalSmall", C.dim)))
  p.title:SetText(d.label)
  p.value = two(oneLine(UI.FS(p, "GameFontNormalLarge", C[d.color] or C.ink)), p.title, SP.XS)
  if UI.VALUE_FONT then p.value:SetFontObject(UI.VALUE_FONT) end
  p.sub = two(UI.CellFS(p, "GameFontHighlightSmall", C.dim), p.value, SP.XS)
  -- measures the subtitle without its rate (hidden; the width a card needs)
  p.base = UI.FS(p, "GameFontHighlightSmall"); p.base:Hide()
  if d.key == "cNet" then
    p.rate = two(UI.CellFS(p, "GameFontHighlightSmall", C.dim), p.sub, 2); p.rate:Hide()
    p.probe = UI.FS(p, "GameFontHighlightSmall"); p.probe:Hide()
  end
  return p
end
local function ledger(content, label, labels)
  local L = CreateFrame("Frame", nil, content)
  L:SetHeight(ROW_H)
  L.head = oneLine(UI.FS(L, "GameFontNormalSmall", C.dim))
  L.head:SetPoint("LEFT", L, "TOPLEFT", INSET, -ROW_H / 2); L.head:SetText(label)
  L.rule = L:CreateTexture(nil, "ARTWORK")
  L.rule:SetPoint("TOPLEFT", L, "TOPLEFT", 0, -ROW_H); L.rule:SetPoint("TOPRIGHT", L, "TOPRIGHT", 0, -ROW_H); L.rule:SetHeight(1)
  L.rule:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
  L.pairs = {}
  for i, text in ipairs(labels) do
    local pr = CreateFrame("Frame", nil, L)
    pr.label = oneLine(UI.FS(pr, "GameFontHighlightSmall", C.dim))
    pr.label:SetPoint("LEFT", pr, "LEFT", 0, 0); pr.label:SetJustifyH("LEFT"); pr.label:SetText(text)
    pr.amount = oneLine(UI.FS(pr, "GameFontHighlightSmall", C.ink))
    pr.amount:SetPoint("RIGHT", pr, "RIGHT", 0, 0); pr.amount:SetJustifyH("RIGHT")
    L.pairs[i] = pr
  end
  return L
end

-- Build the Gold pane into `pane` (a UI.Tabs pane). Returns a refresh function for the host to call.
function ns.BuildEconomyPane(pane)
  local content = pane
  for _, d in ipairs(CARDS) do content[d.key] = card(content, d) end
  content.ledIn = ledger(content, "IN", IN_LABELS)
  content.ledOut = ledger(content, "OUT", OUT_LABELS)
  local note = UI.FS(content, "GameFontDisableSmall", C.dim); note:SetJustifyH("LEFT")
  note:SetText("Gold in and out since this session began. Sinks are attributed by the window that was open when gold left: repairs, vendor, trainer, flight master, auction house, mailbox, trade window. Coin looted, auction proceeds and mailed gold are attributed to their source in the Loot tab. On the beta these totals are per session until SavedVariables persistence is fixed.")
  content.note = note
  content:HookScript("OnSizeChanged", function(f, w, h) pcall(relayout, f, w, h) end)
  refresh(content)
  return function() refresh(content) end
end

-- LOOT / Gold pane (the Loot host is declared by Emitter.lua with the Items pane)
local goldRefresh
UI.registerPane("Loot", 2, "Gold", function(content) goldRefresh = ns.BuildEconomyPane(content) end, function() if goldRefresh then goldRefresh() end end)

-- ── test exports: headless luajit tests in tests/ read these; no effect in-game ──
ns._test = ns._test or {}
ns._test.economyFmtMoney = fmtMoney
