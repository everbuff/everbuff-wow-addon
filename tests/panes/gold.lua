-- Pane tests: LOOT / Gold (Everbuff/Economy.lua). The cards are laid out from the pane's width (five in a row, or
-- three over two, every row filling the width), their text is anchored to both card edges with 12 px padding and
-- stays on one line, NET's per-hour rate gets its own line when it does not fit, IN and OUT are two side-by-side
-- label/amount ledgers, and the note runs full width below them, all inside the pane at 900x580 and 1600x1000.
return function(P)
  local check, eq, M, ns = P.check, P.eq, P.M, P.ns
  local UI = ns.UI
  local fmt = ns.fmtMoney
  local PAD = UI.SP.PAD   -- the padding inside a card and a ledger
  local EDGE = 0          -- the cards and ledgers start at the pane's edge, as the Items toolbar and Auctions rows do
  local function near(a, b) return a and b and math.abs(a - b) < 0.51 end
  local KEYS = { "cBalance", "cGained", "cSpent", "cLooted", "cNet" }
  local SUBS = { cBalance = "current purse", cLooted = "coin picked up from mobs and chests", cGained = "everything that came in", cSpent = "everything that went out" }
  local IN_L = { "looted", "quests", "sold", "auctions", "mail", "trade", "other" }
  local OUT_L = { "repairs", "vendor", "training", "flights", "auctions", "mail", "trade", "other" }
  local OUT_K = { "repairs", "vendor", "training", "flights", "auctions", "mailSpent", "tradeSpent", "other" }
  local function rel(b, o) return { l = b.l - o.l, t = b.t - o.t, w = b.w, h = b.h, r = b.l - o.l + b.w, btm = b.t - o.t + b.h } end

  local function sweep(w, h, data)
    local tag = ("Gold %dx%d %s"):format(w, h, data)
    local c = P.open("loot", "gold", w, h, data)
    check(tag .. ": the pane opened", c and c.cBalance ~= nil)
    if not (c and c.cBalance) then return end
    local cb = P.box(c)
    local W = cb.w - 2 * EDGE
    local g = ns.char().gold or {}
    -- cards: rows that fill the width, no hole, no overlap, one height per row
    local rows, bad = {}, {}
    for _, k in ipairs(KEYS) do
      local b = rel(P.box(c[k]), cb)
      local key = math.floor(b.t + 0.5)
      rows[key] = rows[key] or {}
      table.insert(rows[key], { k = k, b = b })
    end
    local tops = {}
    for t in pairs(rows) do tops[#tops + 1] = t end
    table.sort(tops)
    eq(tag .. ": card rows (five in a row only when each card holds its subtitle on one line)", #tops, c.cardRows)
    check(tag .. ": five in a row only when the NET rate shares its subtitle's line", #tops == 2 or c.cNet.rate.shown == false)
    check(tag .. ": the first row starts at the pane's top edge", tops[1] == EDGE, tops[1])
    for ri, t in ipairs(tops) do
      local r = rows[t]
      table.sort(r, function(a, b2) return a.b.l < b2.b.l end)
      if not near(r[1].b.l, EDGE) then bad[#bad + 1] = ("row %d starts at %s"):format(ri, r[1].b.l) end
      if not near(r[#r].b.r, EDGE + W) then bad[#bad + 1] = ("row %d ends at %s, not %s"):format(ri, r[#r].b.r, EDGE + W) end
      for i = 2, #r do
        if not near(r[i].b.l - r[i - 1].b.r, UI.SP.M) then bad[#bad + 1] = ("row %d gap %s"):format(ri, r[i].b.l - r[i - 1].b.r) end
        if r[i].b.w < r[1].b.w - 0.5 and r[i].k ~= "cNet" and r[1].k ~= "cNet" then bad[#bad + 1] = ("row %d: only NET takes more than an equal share"):format(ri) end
        if not near(r[i].b.h, r[1].b.h) then bad[#bad + 1] = ("row %d heights %s/%s"):format(ri, r[i].b.h, r[1].b.h) end
      end
      if ri > 1 then
        local prev = rows[tops[ri - 1]][1].b
        if not near(t - prev.btm, UI.SP.M) then bad[#bad + 1] = ("row %d is %s below the row above"):format(ri, t - prev.btm) end
      end
    end
    check(tag .. ": card rows fill the width, 12 px apart, no hole", #bad == 0, table.concat(bad, "; "))
    -- card text: anchored to both edges with 12 px padding, one line, never shortened, inside the card
    local tb = {}
    for _, k in ipairs(KEYS) do
      local p = c[k]
      local pb = P.box(p)
      for _, part in ipairs({ "title", "value", "sub", "rate" }) do
        local fs = p[part]
        if fs and fs.shown ~= false and (fs.text or "") ~= "" then
          local b = P.box(fs)
          if not (near(b.l, pb.l + PAD) and near(b.w, pb.w - 2 * PAD)) then tb[#tb + 1] = ("%s.%s box %s+%s"):format(k, part, b.l - pb.l, b.w) end
          if fs._wrap ~= false then tb[#tb + 1] = k .. "." .. part .. " wraps" end
          if fs:IsTruncated() then tb[#tb + 1] = k .. "." .. part .. " shortened: " .. fs.text end
          if b.t + b.h > pb.t + pb.h - PAD + 0.5 then tb[#tb + 1] = ("%s.%s runs into the bottom padding (%s > %s)"):format(k, part, b.t + b.h, pb.t + pb.h - PAD) end
          if b.t < pb.t + PAD - 0.5 then tb[#tb + 1] = k .. "." .. part .. " above the top padding" end
        end
      end
    end
    check(tag .. ": card text has 12 px padding, one line, nothing shortened or on the border", #tb == 0, table.concat(tb, "; "))
    -- the same words and numbers as before
    eq(tag .. ": BALANCE value", c.cBalance.value.text, fmt(g.balance or 0))
    eq(tag .. ": LOOTED value", c.cLooted.value.text, fmt(g.looted or 0))
    eq(tag .. ": GAINED value", c.cGained.value.text, fmt(g.gained or 0))
    eq(tag .. ": SPENT value", c.cSpent.value.text, fmt(g.spent or 0))
    local net = (g.gained or 0) - (g.spent or 0)
    eq(tag .. ": NET value", c.cNet.value.text, (net < 0 and "-" or "") .. fmt(math.abs(net)))
    eq(tag .. ": NET label kept", c.cNet.title.text, "NET THIS SESSION")
    for k, s in pairs(SUBS) do eq(tag .. ": " .. k .. " subtitle kept", c[k].sub.text, s) end
    local rate = c.cNet.rate
    local words = (rate.shown ~= false and rate.text ~= "") and (c.cNet.sub.text .. "  ·  " .. rate.text) or c.cNet.sub.text
    check(tag .. ": NET subtitle keeps its words and the per-hour rate",
      words:match("^gained minus spent  ·  [%+%-].+ per hour this session$") or words == "gained minus spent  ·  per-hour rate after a few minutes", words)
    if rate.shown ~= false and rate.text ~= "" then
      eq(tag .. ": the rate's own line follows the subtitle", c.cNet.sub.text, "gained minus spent")
      check(tag .. ": the rate went to its own line only because it did not fit",
        P.G.naturalWidth(c.cNet.sub, words) > P.box(c.cNet.sub).w, words)
    end
    -- ledgers: IN and OUT side by side, labels left, amounts right, same labels as today, zero rows dimmed
    local li, lo = c.ledIn, c.ledOut
    local bi, bo = rel(P.box(li), cb), rel(P.box(lo), cb)
    check(tag .. ": IN and OUT sit side by side at one height, inside the padding",
      near(bi.t, bo.t) and near(bi.l, EDGE) and near(bo.r, EDGE + W) and bi.r < bo.l and near(bi.h, bo.h), ("%s/%s %s..%s"):format(bi.t, bo.t, bi.l, bo.r))
    local lastCard = rows[tops[#tops]][1].b
    check(tag .. ": the ledgers start 16 px below the cards", near(bi.t - lastCard.btm, UI.SP.L), bi.t - lastCard.btm)
    eq(tag .. ": IN header", li.head.text, "IN"); eq(tag .. ": OUT header", lo.head.text, "OUT")
    check(tag .. ": a 1 px rule under each header", li.rule._h == 1 and lo.rule._h == 1)
    local lb = {}
    local gained, sold = g.gained or 0, g.sold or 0
    local inV = { g.looted or 0, g.quests or 0, sold, g.auctionSales or 0, g.mail or 0, g.trade or 0 }
    local other = gained; for _, v in ipairs(inV) do other = other - v end
    inV[7] = math.max(0, other)
    local outV = {}
    for i, k in ipairs(OUT_K) do outV[i] = g[k] or 0 end
    for _, L in ipairs({ { li, IN_L, inV, bi }, { lo, OUT_L, outV, bo } }) do
      eq(tag .. ": " .. L[1].head.text .. " has its rows", #L[1].pairs, #L[2])
      for i, pr in ipairs(L[1].pairs) do
        local nm = L[1].head.text .. "/" .. L[2][i]
        if pr.label.text ~= L[2][i] then lb[#lb + 1] = nm .. " label " .. tostring(pr.label.text) end
        if pr.amount.text ~= fmt(L[3][i]) then lb[#lb + 1] = nm .. " amount " .. tostring(pr.amount.text) .. " want " .. fmt(L[3][i]) end
        if pr.amount._justify ~= "RIGHT" or pr.label._justify ~= "LEFT" then lb[#lb + 1] = nm .. " alignment" end
        local pb, lab, am = P.box(pr), P.box(pr.label), P.box(pr.amount)
        if pr.amount:IsTruncated() or pr.label:IsTruncated() then lb[#lb + 1] = nm .. " shortened" end
        if lab.l + P.G.naturalWidth(pr.label) > am.l + am.w - P.G.naturalWidth(pr.amount) - UI.SP.XS then lb[#lb + 1] = nm .. " label runs into its amount" end
        if not near(am.l + am.w, pb.l + pb.w) or not near(lab.l, pb.l) then lb[#lb + 1] = nm .. " label and amount not at the pair's edges" end
        local Lb = P.box(L[1])
        if pb.l < Lb.l + PAD - 0.5 or pb.l + pb.w > Lb.l + Lb.w - PAD + 0.5 then lb[#lb + 1] = nm .. " outside the ledger's 12 px inset" end
        if i == 1 and not near(pb.l, Lb.l + PAD) then lb[#lb + 1] = nm .. " first row not under the card text (12 px)" end
        if pb.w > 280.5 then lb[#lb + 1] = nm .. " pair " .. pb.w .. " px wide: the amount drifts from its label" end
        if pb.l < P.box(L[1]).l - 0.5 or pb.l + pb.w > P.box(L[1]).l + P.box(L[1]).w + 0.5 or pb.t + pb.h > P.box(L[1]).t + P.box(L[1]).h + 0.5 then lb[#lb + 1] = nm .. " outside its ledger" end
        if not near(pb.h, UI.ROW_H) then lb[#lb + 1] = nm .. " row height " .. pb.h end
        local zero = L[3][i] == 0
        local dimmed = (pr.amount._color and pr.amount._color[4] or 1) < 1 and (pr.label._color and pr.label._color[4] or 1) < 1
        if zero ~= dimmed then lb[#lb + 1] = nm .. (zero and " is 0 but not dimmed" or " is dimmed but not 0") end
      end
    end
    check(tag .. ": ledger rows: today's labels, amounts right-aligned in full, zero rows dimmed", #lb == 0, table.concat(lb, "; "))
    -- the note: both pane edges, below the ledgers, inside the pane
    local nb = rel(P.box(c.note), cb)
    check(tag .. ": the note spans the pane, its text under the ledger text", near(nb.l, EDGE + PAD) and near(nb.w, W - 2 * PAD), ("%s+%s"):format(nb.l, nb.w))
    check(tag .. ": the note sits 16 px below the ledgers", near(nb.t - math.max(bi.btm, bo.btm), UI.SP.L), nb.t - bi.btm)
    check(tag .. ": the note ends inside the pane", nb.btm <= cb.h - EDGE + 0.5, ("%s > %s"):format(nb.btm, cb.h - EDGE))
    check(tag .. ": the note keeps its words", c.note.text:find("^Gold in and out since this session began%.") and c.note.text:find("persistence is fixed%.$"))
  end

  for _, size in ipairs({ { 900, 580 }, { 1600, 1000 }, { 900, 580 } }) do
    for _, data in ipairs({ "normal", "long" }) do sweep(size[1], size[2], data) end
  end
  -- the suite's data has no zero row: make two, see them dimmed, and a value again undims its row
  do
    local c = P.open("loot", "gold", 900, 580)   -- (P.open loads a fresh copy of the data: change it after)
    local gold = ns.char().gold
    local function show() ns.UI.Open("Loot", "gold"); M.settle() end
    gold.training, gold.quests = 0, nil
    show()
    local tr, qu, rp = c.ledOut.pairs[3], c.ledIn.pairs[2], c.ledOut.pairs[1]
    check("Gold: a zero row is dimmed, label and amount", tr.amount.text == "0c" and tr.amount._color[4] < 1 and tr.label._color[4] < 1 and qu.amount.text == "0c" and qu.amount._color[4] < 1)
    check("Gold: a row with gold is not dimmed", (gold.repairs or 0) > 0 and rp.amount._color[4] == 1 and rp.label._color[4] == 1)
    gold.training = 7
    show()
    check("Gold: a row that gets gold is undimmed", tr.amount._color[4] == 1 and tr.amount.text == "7c")
  end
  -- a 900 px wide but tall window has room for one column of ledger rows
  do
    local c = P.open("loot", "gold", 900, 1000)
    eq("Gold 900x1000: one column of ledger rows when tall", c.ledgerCols, 1)
    eq("Gold 900x1000: IN in one column: 'other' sits below 'trade'", P.box(c.ledIn.pairs[7]).t - P.box(c.ledIn.pairs[6]).t, UI.ROW_H)
    local c2 = P.open("loot", "gold", 900, 580)
    eq("Gold 900x580: two columns of pairs when short", c2.ledgerCols, 2)
    local c3 = P.open("loot", "gold", 1600, 1000)
    eq("Gold 1600x1000: one column of rows when tall, the pane's height used", c3.ledgerCols, 1)
    check("Gold 1600x1000: a wide ledger keeps each amount within 280 px of its label", c3.ledIn.pairW <= 280 and c3.ledOut.pairW <= 280, c3.ledIn.pairW)
  end
  -- NET: the rate shares the subtitle's line when the card is wide enough, else has its own line
  do
    local saved = ns.Recorder.current
    local now = (GetServerTime and GetServerTime()) or time()
    ns.Recorder.current = function() return { startedEpoch = now - 3600, gained = 50000, spent = 0 } end
    local c = P.open("loot", "gold", 900, 580)
    ns.UI.Open("Loot", "gold"); M.settle()
    local words = c.cNet.sub.text .. ((c.cNet.rate.shown ~= false and c.cNet.rate.text ~= "") and ("  ·  " .. c.cNet.rate.text) or "")
    eq("Gold: NET reads the rate of this session", words, "gained minus spent  ·  +5g per hour this session")
    check("Gold 900x580: in the wide NET card the rate shares the line", c.cNet.rate.shown == false and c.cNet.sub.text == words, c.cNet.sub.text)
    P.open("loot", "gold", 1600, 1000)
    check("Gold 1600x1000: the cards keep three over two rather than push the rate onto a second line", c.cardRows == 2 and c.cNet.rate.shown == false and c.cNet.sub.text == words, c.cardRows)
    -- a long rate in a narrow window: NET takes the width it needs from the row before the rate moves down
    ns.Recorder.current = function() return { startedEpoch = now - 3600, gained = 5534543600, spent = 0 } end
    P.open("loot", "gold", 900, 580, "long")
    check("Gold 900x580 long: a five-digit rate still shares NET's subtitle line", c.cNet.rate.shown == false and c.cNet.sub.text:find("per hour this session$") ~= nil and not c.cNet.sub:IsTruncated(), c.cNet.sub.text)
    check("Gold 900x580 long: NET is wider than LOOTED beside it", P.box(c.cNet).w > P.box(c.cLooted).w, P.box(c.cNet).w)
    ns.Recorder.current = saved
  end
  -- a layout change adds no behavior: the pane hears no game event of its own (it refreshes when it is shown, as before)
  do
    local c = P.open("loot", "gold", 900, 580)
    local listening = {}
    for _, f in ipairs(P.descendants(c)) do
      for ev in pairs(rawget(f, "events") or {}) do listening[#listening + 1] = ev end
    end
    check("Gold: the pane registers no events (no live money refresh)", #listening == 0 and rawget(c, "moneyEvents") == nil, table.concat(listening, ","))
  end
  check("Gold: no errors from the pane's resize or events", #UI.paneErrors() == 0, table.concat(UI.paneErrors(), " || "))
end
