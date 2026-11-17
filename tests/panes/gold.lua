-- Pane tests: gold, one model on every surface (everbuff-wow-addon #38). Everbuff/Economy.lua holds the model
-- (ns.Gold) and the LOOT / Gold pane; Home / Sessions shows a session's gold band, Home / Overview the card, and
-- LOOT / Items lists items only. Played on tests/play_gold.lua ("gold": two evenings with a name behind every row).
--   model     every journal row parsed, the balance chain intact, each source summing to the session ledger, the
--             quest, item, merchant, mob and player named, Location and Coordinates only from the row's own record
--   Gold pane periods, five cards that fill the width, Sources (IN, OUT, a click opens the rows), Journal (Location
--             and Coords two columns, numbers at the right, Balance left out when narrow), Flagged, search, sort
--   elsewhere the Sessions band, the Overview card, no coin row in Items, nothing written into the save file
return function(P)
  local check, eq, M, ns = P.check, P.eq, P.M, P.ns
  local UI, Gold = ns.UI, ns.Gold
  local fmt = ns.fmtMoney
  local tip = _G.GameTooltip
  local function near(a, b) return a and b and math.abs(a - b) < 0.51 end
  local function shown(rows) local out = {}; for _, r in ipairs(rows or {}) do if r.shown ~= false then out[#out + 1] = r end end return out end
  local function dataRows(tbl) local out = {}; for _, r in ipairs(shown(tbl.rows)) do if r.item and not r.item.ebSection then out[#out + 1] = r end end return out end
  local function click(b) b.scripts.OnClick(b, "LeftButton"); M.settle() end
  -- the suite's recorder still holds the session object of its last play; the panes read the running session of the
  -- data in use
  local savedCurrent = ns.Recorder.current
  ns.Recorder.current = function() return ns.DB.active and ns.DB.sessions[ns.DB.active] or nil end
  local function open(w, h, data, scope, view, flags)
    local c = P.open("loot", "gold", w, h, data or "gold")
    Gold.open(scope or "session", view, flags); M.settle()
    return c
  end

  -- ── the model ───────────────────────────────────────────────────────────────────────────────────────────────
  do
    local c = open(1250, 760)
    local ses = ns.Recorder.current()
    check("model: the running session of the gold data has a journal", ses and #ses.goldLog >= 60, ses and #ses.goldLog)
    local sc = Gold.scope("session")
    local rows = Gold.scopeEntries(sc)
    eq("model: one row per journal line", #rows, #ses.goldLog)
    local chain, sums, bySrc = true, {}, {}
    for i, e in ipairs(rows) do
      if i > 1 and e.bal - rows[i - 1].bal ~= e.delta then chain = false end
      sums[e.src] = (sums[e.src] or 0) + math.abs(e.delta)
      bySrc[e.src] = bySrc[e.src] or {}; table.insert(bySrc[e.src], e)
    end
    check("model: the balance chain holds over the rows", chain)
    local src = Gold.sources(sc, rows)
    local bad = {}
    for _, r in ipairs(src.rows) do
      if r.dir ~= 0 and r.amount ~= (sums[r.key] or 0) then bad[#bad + 1] = r.key end
      if r.dir ~= 0 and r.amount ~= (r.key == "unexplained" and sc.ledger.unexplained or ses.gold[r.key]) then bad[#bad + 1] = r.key .. " ledger" end
      if r.n ~= #(bySrc[r.key] or {}) then bad[#bad + 1] = r.key .. " count" end
    end
    check("model: every source's amount is the session ledger's and the sum of its rows", #bad == 0, table.concat(bad, ","))
    eq("model: IN is the session's gained, OUT its spent", src.inTotal .. "/" .. src.outTotal, ses.gained .. "/" .. ses.spent)
    local zero = false
    for _, r in ipairs(src.rows) do if r.amount == 0 and r.n == 0 then zero = true end end
    check("model: a source with no money and no rows is left out", not zero)
    -- what each row says
    local function find(srcKey, pat) for _, e in ipairs(bySrc[srcKey] or {}) do if e.detail:find(pat, 1, true) then return e end end end
    local q = find("quests", "The Defias Brotherhood")
    check("model: a quest row names its quest, with the place of the turn-in", q and q.delta == 1500 and q.zone == "Westfall" and q.x and q.y, q and q.detail)
    local sold = find("sold", "Linen Cloth x20 to Quartermaster Lewis")
    check("model: a sale names the item, the count and the merchant, with the place of the visit", sold and sold.zone == "Westfall" and sold.x ~= nil and not sold.flag, sold and sold.detail)
    local over = find("sold", "Short Bastard Sword of the Monkey")
    check("model: a sale above the vendor price is flagged", over and over.flag == "above vendor price" and over.vendorPrice == 1284 and over.delta == 3852)
    check("model: a purchase names the item and the merchant", find("vendor", "Ice Cold Milk x5 from Quartermaster Lewis") ~= nil)
    local loot = bySrc.looted[1]
    check("model: looted coin names the mob and its place from the loot row of that pickup", loot.loot and loot.detail == loot.loot.src and loot.loot.money == loot.delta and loot.zone == "Westfall" and loot.x == loot.loot.x, loot.detail)
    check("model: a repair, a trainer and a flight name the npc", find("repairs", "Quartermaster Lewis") and find("training", "Wu Shen") and find("flights", "Thor") and true)
    local flight = find("flights", "Thor")
    check("model: a row with no record of its own has no place (never guessed)", flight.zone == nil and flight.x == nil and bySrc.unexplained[1].zone == nil and bySrc.other[1].zone == nil)
    local stranger, mate = find("mail", "from Xzqtgold (stranger)"), find("mail", "from Maribel (guild)")
    check("model: mail names the sender and who they are; a stranger is flagged, a guild mate is not", stranger and stranger.flag == "stranger" and mate and mate.flag == nil and stranger.zone == "Stormwind City")
    check("model: a COD payment to a stranger is flagged, postage is not", find("mailSpent", "COD to Oreseller (stranger)").flag == "stranger" and find("mailSpent", "Postage").flag == nil)
    check("model: an auction sale names the item and the buyer", find("auctionSales", "Light Leather to Tannerjoe") ~= nil)
    local tr = find("trade", "Xzqtgold <Cheap Gold Fast> (stranger)")
    check("model: a trade names the partner, the guild and who they are, with its trades[] entry and place", tr and tr.flag == "stranger" and tr.tradeRec and tr.tradeRec.gotMoney == 250000 and tr.zone == "Stormwind City", tr and tr.detail)
    check("model: a trade with a friend is not flagged", find("trade", "Tessa (friend)").flag == nil)
    check("model: unexplained rows are flagged both ways", bySrc.unexplained[1].flag == "unexplained" and bySrc.other[1].flag == "unexplained")
    check("model: gold changed while away is its own row, neither in nor out", bySrc.away and bySrc.away[1].delta == 4200 and bySrc.away[1].detail:find("mail was waiting") and src.away == 4200)
    eq("model: a row's time is the session start plus its clock", rows[1].t, math.floor(ses.startedEpoch + (rows[1].mono - ses.startedMono) + 0.5))
    -- contributors and the summary
    local top = Gold.contributors(bySrc.quests)
    check("model: contributors are by amount, biggest first", top[1].name == "The Defias Brotherhood" and top[1].amount == 1500 and top[2].amount <= top[1].amount)
    local sum = Gold.summary(ses)
    check("model: the summary has net, pace, top sources, best earners, sinks and flags",
      sum.net == ses.gained - ses.spent and sum.perHour and sum.topIn[1].key == "trade" and sum.bestQuest.name == "The Defias Brotherhood"
      and sum.bestItem.name == "Short Bastard Sword of the Monkey" and sum.bestMob and sum.sinks[1].key == "auctions"
      and #sum.strangers == 2 and sum.unexplained == 260 + 75 and sum.above == 1 and sum.away == 4200, sum.topIn[1] and sum.topIn[1].key)
    -- periods
    local prev, all = Gold.scope("previous"), Gold.scope("all")
    check("model: Previous is the newest ended session", #prev.sessions == 1 and prev.sessions[1] ~= ses and prev.sessions[1].endedEpoch ~= nil)
    check("model: All time reads the character's ledger and every journal in the file", all.lifetime and all.ledger.gained == ns.char().gold.gained and #all.sessions >= 2 and all.balance == ns.char().gold.balance)
    local old = { id = "old-1", guid = ses.guid, startedEpoch = 1, endedEpoch = 100, gained = 500, spent = 20, gold = { gained = 500, spent = 20, quests = 500, repairs = 20 } }
    ns.DB.sessions[old.id] = old
    local osc = Gold.scope(old.id)
    local osrc = Gold.sources(osc, Gold.scopeEntries(osc))
    check("model: a session from before 0.9.40 keeps its totals and has no rows", osc.noJournal == 1 and #osrc.rows == 2 and osrc.rows[1].amount == 500 and osrc.rows[1].n == 0)
    check("model: its summary still names the top source", Gold.summary(old).topIn[1].key == "quests" and Gold.summary(old).journal == false)
    ns.DB.sessions[old.id] = nil
    -- nothing is written into the save file by reading it
    local marks = 0
    local function walk(t, seen)
      if seen[t] then return end; seen[t] = true
      for k, v in pairs(t) do
        if k == "ebTaken" or k == "questName" or k == "ebOrder" or k == "detail" or k == "flag" then marks = marks + 1 end
        if type(v) == "table" then walk(v, seen) end
      end
    end
    click(c.viewBtn); Gold.open("all", "journal"); ns.UI.Open("Loot", "items"); M.settle(); ns.UI.Open("Home", "sessions"); M.settle()
    walk(ns.DB, {})
    eq("model: the panes write nothing into the save file", marks, 0)
  end

  -- ── the Gold pane: layout on both data sets at three sizes ──────────────────────────────────────────────────
  local KEYS = { "cBalance", "cIn", "cOut", "cNet", "cRate" }
  for _, size in ipairs({ { 900, 580 }, { 1250, 760 }, { 1600, 1000 } }) do
    for _, data in ipairs({ "gold", "goldlong" }) do
      local tag = ("Gold %dx%d %s"):format(size[1], size[2], data)
      local c = open(size[1], size[2], data)
      local cb = P.box(c)
      local ses = ns.Recorder.current()
      -- toolbar
      local tb = {}
      local last
      for _, b in ipairs(c.scopeBtns) do
        local bb = P.box(b)
        if last and bb.l < last.l + last.w then tb[#tb + 1] = "period buttons overlap" end
        if P.G.naturalWidth(b.text) > bb.w - 2 * UI.SP.S then tb[#tb + 1] = "label cut: " .. b.text.text end
        last = bb
      end
      local vb, sb = P.box(c.viewBtn), P.box(c.search)
      if last.l + last.w > vb.l then tb[#tb + 1] = "periods run into the view button" end
      if not near(sb.l + sb.w, cb.l + cb.w - UI.SCROLLBAR) then tb[#tb + 1] = "search does not end where the list does" end
      check(tag .. ": toolbar: periods left, view button and search right, nothing overlapping", #tb == 0, table.concat(tb, "; "))
      check(tag .. ": This session is the selected period", c.scopeBtns[1].ebSelected == true and c.scopeBtns[2].ebSelected == nil and c.pickBtn.shown == false)
      -- cards
      local rowsBy, bad = {}, {}
      for _, k in ipairs(KEYS) do
        local p = c[k]
        local b = P.box(p)
        local key = math.floor(b.t - cb.t + 0.5)
        rowsBy[key] = rowsBy[key] or {}; table.insert(rowsBy[key], b)
        for _, part in ipairs({ "title", "value" }) do
          if p[part]:IsTruncated() then bad[#bad + 1] = k .. "." .. part .. " shortened: " .. tostring(p[part].text) end
          local fb = P.box(p[part])
          if fb.l < b.l + UI.SP.S - 0.5 or fb.t + fb.h > b.t + b.h - UI.SP.S + 0.5 then bad[#bad + 1] = k .. "." .. part .. " outside the padding" end
        end
      end
      local nRows = 0
      for _, r in pairs(rowsBy) do
        nRows = nRows + 1
        table.sort(r, function(a, b2) return a.l < b2.l end)
        if not near(r[1].l, cb.l) or not near(r[#r].l + r[#r].w, cb.l + cb.w) then bad[#bad + 1] = "a card row does not fill the width" end
        for i = 2, #r do if not near(r[i].l - (r[i - 1].l + r[i - 1].w), UI.SP.M) or not near(r[i].h, r[1].h) then bad[#bad + 1] = "card gap or height" end end
      end
      eq(tag .. ": card rows", nRows, c.cardRows)
      check(tag .. ": the cards fill the width, 12 px apart, text in full inside the padding", #bad == 0, table.concat(bad, "; "))
      local net = ses.gained - ses.spent
      eq(tag .. ": BALANCE", c.cBalance.value.text, fmt(ns.char().gold.balance))
      eq(tag .. ": IN / OUT", c.cIn.value.text .. " / " .. c.cOut.value.text, fmt(ses.gained) .. " / " .. fmt(ses.spent))
      eq(tag .. ": NET", c.cNet.value.text, Gold.signed(net))
      check(tag .. ": PER HOUR is a signed rate", c.cRate.title.text == "PER HOUR" and c.cRate.value.text:find("^[%+%-]%d") ~= nil, c.cRate.value.text)
      -- Sources
      local tbl = c.tblSrc
      check(tag .. ": the pane opens on Sources, the journal tables hidden", P.visible(tbl.sf) and not P.visible(c.tblJrn.sf) and not P.visible(c.tblJrnNarrow.sf) and c.viewBtn.text.text == "Journal")
      local secs = tbl.sections()
      check(tag .. ": IN and OUT sections carry their totals, then what is neither", #secs == 3 and secs[1].text == "IN  ·  " .. fmt(ses.gained) and secs[2].text == "OUT  ·  " .. fmt(ses.spent) and secs[3].text == "NEITHER IN NOR OUT", secs[1] and secs[1].text)
      local rows = dataRows(tbl)
      local sbad = {}
      local sfb = P.box(tbl.sf)
      for _, r in ipairs(rows) do
        local it = r.item
        if r.c.src.text ~= Gold.LABEL[it.key] then sbad[#sbad + 1] = it.key .. " label" end
        if r.c.amount.text ~= (it.dir == 0 and Gold.signed(it.amount) or fmt(it.amount)) then sbad[#sbad + 1] = it.key .. " amount" end
        if r.c.amount:IsTruncated() or r.c.n:IsTruncated() or r.c.share:IsTruncated() or r.c.src:IsTruncated() then sbad[#sbad + 1] = it.key .. " shortened" end
        if it.n > 0 and r.c.go.text ~= "›" then sbad[#sbad + 1] = it.key .. " no chevron" end
        local gb = P.box(r.c.go)
        if gb.l + gb.w > sfb.l + sfb.w + 0.5 then sbad[#sbad + 1] = it.key .. " past the list" end
        if not near(P.box(tbl.head.amount.fs).l, P.box(r.c.amount).l) then sbad[#sbad + 1] = it.key .. " header x" end
      end
      check(tag .. ": source rows: label, amount in full, right-aligned under its header, a chevron, inside the list", #sbad == 0 and #rows >= 14, table.concat(sbad, "; "))
      check(tag .. ": the caption says what the list is and how to go on", c.caption.text:find("^This session, ") and c.caption.text:find("click a source to list its rows", 1, true) ~= nil, c.caption.text)
      check(tag .. ": Flagged counts the flagged rows, All rows is hidden", P.visible(c.flagBtn) and c.flagBtn.text.text == "Flagged: 6" and not P.visible(c.allBtn), c.flagBtn.text.text)
      local fb, capb = P.box(c.flagBtn), P.box(c.caption)
      check(tag .. ": the caption ends before its button", capb.l + capb.w <= fb.l + 0.5 and fb.l + fb.w <= cb.l + cb.w - UI.SCROLLBAR + 0.5)
      check(tag .. ": the list ends inside the pane", sfb.t + sfb.h <= cb.t + cb.h + 0.5 and sfb.t > P.box(c.capRow).t + UI.ROW_H - 0.5)
      -- a click on a source opens its rows
      local qrow
      for _, r in ipairs(rows) do if r.item.key == "quests" then qrow = r end end
      click(qrow)
      local narrow = (cb.w - UI.SCROLLBAR) < 760
      local jt = narrow and c.tblJrnNarrow or c.tblJrn
      local other = narrow and c.tblJrn or c.tblJrnNarrow
      check(tag .. ": a click on Quest rewards opens the journal (" .. (narrow and "without" or "with") .. " Balance)", P.visible(jt.sf) and not P.visible(other.sf) and not P.visible(tbl.sf) and c.viewBtn.text.text == "Sources")
      local jr = dataRows(jt)
      local only, sumQ = true, 0
      for _, r in ipairs(jr) do if r.item.src ~= "quests" then only = false end; sumQ = sumQ + r.item.delta end
      -- (the long data makes the ledger's numbers long; the journal's rows are text and stay as played)
      check(tag .. ": only quest rows, as many as the source said", only and #jr == qrow.item.n and (data == "goldlong" or sumQ == ses.gold.quests), #jr)
      eq(tag .. ": the caption names the source, the rows and their sum", c.caption.text, ("Quest rewards  ·  %d rows  ·  %s"):format(#jr, Gold.signed(sumQ)))
      check(tag .. ": All rows shows beside Flagged", P.visible(c.allBtn) and P.box(c.flagBtn).l + P.box(c.flagBtn).w <= P.box(c.allBtn).l)
      eq(tag .. ": the newest quest row names its quest", jr[1].c.detail.text, "The Defias Brotherhood")
      click(c.allBtn)
      jr = dataRows(jt)
      eq(tag .. ": All rows lists every row", #jr, #ses.goldLog)
      check(tag .. ": newest first", jr[1].item.t >= jr[#jr].item.t and jt.sortKey == "time" and jt.sortAsc == false)
      -- columns: Location and Coords are two, the numbers sit at the right and are never shortened
      local order = {}
      for i, col in ipairs(jt.spec) do order[col.key] = i end
      check(tag .. ": Time, Source, Detail, Location, Coords, Amount" .. (narrow and "" or ", Balance"), order.time == 1 and order.src == 2 and order.detail == 3 and order.loc == 4 and order.coords == 5 and order.amount == 6 and ((narrow and order.bal == nil) or order.bal == 7))
      local jb = {}
      local jsf = P.box(jt.sf)
      for i, r in ipairs(jr) do
        local e = r.item
        if r.c.amount.text ~= Gold.signed(e.delta) then jb[#jb + 1] = i .. " amount" end
        if r.c.amount:IsTruncated() or r.c.time:IsTruncated() or r.c.src:IsTruncated() or r.c.coords:IsTruncated() or (r.c.bal and r.c.bal:IsTruncated()) then jb[#jb + 1] = i .. " shortened" end
        if r.c.loc.text ~= (e.zone or "") then jb[#jb + 1] = i .. " location" end
        if r.c.coords.text ~= ((e.x and e.y) and UI.fmtCoords(e.x, e.y) or "") then jb[#jb + 1] = i .. " coords" end
        if (r.c.loc.text or ""):find("%d+%.%d, %d") then jb[#jb + 1] = i .. " coords inside the location" end
        if r.c.bal and r.c.bal.text ~= fmt(e.bal) then jb[#jb + 1] = i .. " balance" end
        local lastCell = P.box(r.c.bal or r.c.amount)
        if lastCell.l + lastCell.w > jsf.l + jsf.w + 0.5 then jb[#jb + 1] = i .. " past the list" end
        for _, col in ipairs(jt.spec) do
          if not near(P.box(jt.head[col.key].fs).l, P.box(r.c[col.key]).l) then jb[#jb + 1] = i .. " header x " .. col.key end
        end
        if e.flag and not (r.c.detail._color and near(r.c.detail._color[1], UI.C.red[1])) then jb[#jb + 1] = i .. " flag not marked" end
      end
      check(tag .. ": journal rows: signed amounts and balances in full, Location and Coords apart, header x == cell x, flags marked", #jb == 0, table.concat(jb, "; "):sub(1, 300))
      -- Flagged
      click(c.flagBtn)
      jr = dataRows(jt)
      local allFlag = true
      for _, r in ipairs(jr) do if not r.item.flag then allFlag = false end end
      check(tag .. ": Flagged lists the six flagged rows and is selected", allFlag and #jr == 6 and c.flagBtn.ebSelected == true and c.caption.text:find("^Flagged rows  ·  6 rows") ~= nil, #jr)
      click(c.viewBtn)
      check(tag .. ": the view button goes back to Sources with no filter", P.visible(tbl.sf) and c.st.src == nil and c.st.flags == false and not P.visible(c.allBtn))
    end
  end

  -- ── search, sort, tooltips, periods ─────────────────────────────────────────────────────────────────────────
  do
    local c = open(1250, 760)
    local jt = c.tblJrn
    c.search:SetText("wu shen"); c.search.scripts.OnTextChanged(c.search); M.settle()
    local jr = dataRows(jt)
    check("Gold search: typing opens the journal on the matching rows", P.visible(jt.sf) and #jr == 3 and jr[1].item.src == "training" and c.caption.text:find('matching "wu shen"', 1, true) ~= nil, #jr)
    c.search:SetText("zzzz"); c.search.scripts.OnTextChanged(c.search); M.settle()
    check("Gold search: nothing found shows the empty sentence, the header hidden", jt.empty.shown and jt.header.shown == false)
    click(c.allBtn)
    eq("Gold search: All rows clears the search", c.search:GetText(), "")
    -- sort by amount
    local hb = jt.head.amount; hb.scripts.OnClick(hb); M.settle()
    jr = dataRows(jt)
    check("Gold sort: Amount, biggest first; both journal tables keep the same sort", jr[1].item.delta == 250000 and jr[#jr].item.delta == -12800 and c.tblJrnNarrow.sortKey == "amount", jr[1].item.delta)
    hb = jt.head.time; hb.scripts.OnClick(hb); M.settle()
    if jt.sortAsc then hb.scripts.OnClick(hb); M.settle() end
    -- tooltips
    jr = dataRows(jt)
    local trade, sale
    for _, r in ipairs(jr) do
      if r.item.src == "tradeSpent" then trade = r end
      if r.item.flag == "above vendor price" then sale = r end
    end
    trade.scripts.OnEnter(trade)
    local text = table.concat(tip.lines, " | ")
    check("Gold tooltip: a trade row lists both sides, the time and the balance", text:find("Trades given  -50s", 1, true) and text:find("You gave: 50s", 1, true) and text:find("You got: Light Leather x20", 1, true) and text:find("balance after", 1, true), text)
    trade.scripts.OnLeave(trade)
    sale.scripts.OnEnter(sale)
    text = table.concat(tip.lines, " | ")
    check("Gold tooltip: a sale above the vendor price says both prices and the flag", text:find("Vendor price 12s" .. UI.NBSP .. "84c, paid 38s" .. UI.NBSP .. "52c", 1, true) and text:find("Flagged: above vendor price", 1, true), text)
    sale.scripts.OnLeave(sale)
    click(c.viewBtn)
    local srow
    for _, r in ipairs(dataRows(c.tblSrc)) do if r.item.key == "looted" then srow = r end end
    srow.scripts.OnEnter(srow)
    text = table.concat(tip.lines, " | ")
    check("Gold tooltip: a source row lists its biggest contributors and says what a click does", text:find("^Looted coin") and text:find("Defias", 1, true) and text:find("Click to list every row.", 1, true), text)
    srow.scripts.OnLeave(srow)
    -- periods
    click(c.scopeBtns[2])
    local prev = Gold.scope("previous").sessions[1]
    check("Gold periods: Previous shows that session's numbers and its balance at the end", c.scopeBtns[2].ebSelected and c.cBalance.title.text == "BALANCE AT ITS END" and c.cIn.value.text == fmt(prev.gained) and c.caption.text:find("^Previous session, ") ~= nil, c.caption.text)
    click(c.scopeBtns[3])
    check("Gold periods: All time reads the lifetime ledger and names what changed while away", c.cIn.value.text == fmt(ns.char().gold.gained) and c.cRate.title.text == "CHANGED WHILE AWAY" and c.cRate.value.text == Gold.signed(ns.char().gold.away or 0))
    click(c.viewBtn)
    local secs = c.tblJrn.sections()
    check("Gold periods: the All time journal has one section per session, the running one first", #secs >= 2 and secs[1].text:find("  ·  running  ·  net ", 1, true) ~= nil and secs[2].text:find("running", 1, true) == nil and c.caption.text:find("sessions since addon 0.9.40", 1, true) ~= nil, #secs)
    Gold.open(prev.id); M.settle()
    check("Gold periods: a session picked elsewhere gets its own selected button", P.visible(c.pickBtn) and c.pickBtn.ebSelected == true and c.pickBtn.text.text == Gold.sessionLabel(prev) and c.scopeBtns[1].ebSelected == nil)
    click(c.scopeBtns[1])
    check("Gold periods: back on This session the picked button is gone", not P.visible(c.pickBtn))
    -- an empty period
    local ses = ns.Recorder.current()
    ses.goldLog, ses.gold, ses.gained, ses.spent, ses.trades = {}, {}, 0, 0, {}
    Gold.open("session"); M.settle()
    check("Gold empty: no gold moved shows the sentence and no Flagged button", c.tblSrc.empty.shown and c.tblSrc.empty.text == "No gold moved in this period yet." and not P.visible(c.flagBtn) and c.cNet.value.text == "+0c")
    local listening = {}
    for _, f in ipairs(P.descendants(c)) do for ev in pairs(rawget(f, "events") or {}) do listening[#listening + 1] = ev end end
    check("Gold: the pane registers no events (it refreshes when it is shown)", #listening == 0, table.concat(listening, ","))
  end

  -- ── Home / Sessions: the gold band; LOOT / Items: items only ────────────────────────────────────────────────
  for _, size in ipairs({ { 900, 580 }, { 1250, 760 }, { 1600, 1000 } }) do
    for _, data in ipairs({ "gold", "goldlong" }) do
      local tag = ("Sessions gold %dx%d %s"):format(size[1], size[2], data)
      local c = P.open("home", "sessions", size[1], size[2], data)
      ns.UI.Open("Home", "sessions"); M.settle()
      local band, cb = c.goldBand, P.box(c)
      local bb = P.box(band)
      local ses = ns.Recorder.current()
      check(tag .. ": the band sits at the pane's bottom, the list ends above it", P.visible(band) and near(bb.t + bb.h, cb.t + cb.h) and P.box(c.tbl.sf).t + P.box(c.tbl.sf).h <= bb.t - UI.SP.M + 0.5)
      check(tag .. ": the band opens on the running session: date, length, net and pace", band.title.text:find("GOLD  ·  " .. Gold.sessionLabel(ses), 1, true) == 1 and band.title.text:find("net " .. Gold.signed(ses.gained - ses.spent), 1, true) and band.title.text:find("per hour$") ~= nil, band.title.text)
      local bad = {}
      local lastR
      for i, b in ipairs(band.blocks) do
        local x = P.box(b)
        if x.l < bb.l or x.l + x.w > bb.l + bb.w or x.t + x.h > bb.t + bb.h + 0.5 then bad[#bad + 1] = "block " .. i .. " outside the band" end
        if lastR and x.l < lastR + UI.SP.L - 0.5 then bad[#bad + 1] = "block " .. i .. " too close" end
        lastR = x.l + x.w
        for _, fs in ipairs(b.lines) do
          local fb = P.box(fs)
          if (fs.text or "") ~= "" and (fb.t + fb.h > bb.t + bb.h - 4) then bad[#bad + 1] = "line past the band: " .. fs.text end
        end
      end
      local tb, ob = P.box(band.title), P.box(band.open)
      if tb.l + tb.w > ob.l then bad[#bad + 1] = "title under the button" end
      check(tag .. ": four blocks side by side inside the band, the title ends before the button", #bad == 0, table.concat(bad, "; "))
      eq(tag .. ": block heads", band.blocks[1].head.text .. "|" .. band.blocks[2].head.text .. "|" .. band.blocks[3].head.text .. "|" .. band.blocks[4].head.text, "TOP SOURCES|BEST EARNERS|BIGGEST SINKS|FLAGS")
      check(tag .. ": top source, best quest, biggest sink and the strangers are named",
        band.blocks[1].lines[1].text:find("^Trades received  ") and band.blocks[2].lines[1].text:find("^Quest: The Defias Brotherhood") and band.blocks[3].lines[1].text:find("^Auction house  ")
        and band.blocks[4].lines[1].text:find("^Strangers: Xzqtgold") and band.blocks[4].lines[2].text:find("^Unexplained: ") and band.blocks[4].lines[3].text:find("^Above vendor price: 1 sale"), band.blocks[4].lines[1].text)
    end
  end
  do
    local c = P.open("home", "sessions", 1250, 760, "gold")
    ns.UI.Open("Home", "sessions"); M.settle()
    local band = c.goldBand
    local prevRow
    for _, r in ipairs(shown(c.tbl.rows)) do if r.item.endedEpoch and r.item.gold and (r.item.gold.training or 0) == 1200 then prevRow = r end end
    check("Sessions gold: the first evening's row was found", prevRow ~= nil)
    click(prevRow)
    check("Sessions gold: a click on a row shows that session's gold", band.title.text:find(Gold.sessionLabel(prevRow.item), 1, true) ~= nil and band.blocks[2].lines[1].text:find("^Quest: The Jasperlode Mine") ~= nil and band.blocks[3].lines[1].text:find("^Training  12s") ~= nil, band.blocks[2].lines[1].text)
    check("Sessions gold: the shown row's date is marked", prevRow.c.date._color and near(prevRow.c.date._color[1], UI.C.cyan[1]))
    click(band.open)
    local gold
    for _, tab in ipairs(P.T.tabs) do if tab.name == "Loot" then gold = tab.paneByKey.gold.content end end
    check("Sessions gold: the button opens that session's journal in the Gold pane", P.visible(gold) and gold.st.scope == prevRow.item.id and gold.st.view == "journal" and P.visible(gold.pickBtn) and #dataRows(gold.tblJrn) == #prevRow.item.goldLog, gold.st.scope)
    -- a session from before 0.9.40
    local ses = ns.Recorder.current()
    ses.goldLog, ses.trades, ses.goldLogDropped = nil, nil, nil
    ns.UI.Open("Home", "sessions"); M.settle()
    click(shown(c.tbl.rows)[1])
    check("Sessions gold: a session without a journal keeps its top sources and says why the rest is empty", band.blocks[1].lines[1].text:find("^Trades received") ~= nil and band.blocks[2].lines[1].text == "Recorded before addon 0.9.40" and band.blocks[4].lines[1].text == "Changed while away: +42s", band.blocks[2].lines[1].text)
  end
  do
    local c = P.open("loot", "items", 1250, 760, "gold")
    ns.UI.Open("Loot", "items"); M.settle()
    local coin, questSrc = 0, nil
    for _, r in ipairs(shown(c.lootRows)) do
      if r.item and r.item.money then coin = coin + 1 end
      if r.c.item.text == "Pikeman Shield" then questSrc = r.c.from.text end
    end
    eq("Items: no coin row", coin, 0)
    eq("Items: a quest's reward names its quest", questSrc, "Quest: The Defias Brotherhood")
    check("Items: the totals line counts items, no gold", c.lootTotals.text:find("^%d+ pickups  ·  %d+ items in all$") ~= nil, c.lootTotals.text)
    eq("Items: the source column is headed Source", c.lootTables.newest.head.from.fs.text, "SOURCE")
  end
  ns.Recorder.current = savedCurrent
  check("Gold: no errors from the panes' resize or events", #UI.paneErrors() == 0, table.concat(UI.paneErrors(), " || "))
end
