-- Pane tests: gold, one model on every surface (everbuff-wow-addon #38). Everbuff/Economy.lua holds the model
-- (ns.Gold) and the LOOT / Gold pane; Home / Sessions shows a session's gold band, Home / Overview the card, and
-- LOOT / Items lists items only. Played on tests/play_gold.lua ("gold": two evenings with a name behind every row).
--   model     every journal row parsed, the balance chain intact, each source summing to the session ledger, the
--             quest, item, merchant, mob and player named, Location and Coordinates only from the row's own record
--   Gold pane periods, five cards that fill the width, Sources (EARNED, SPENT, a click opens the rows), Journal
--             (Location and Coords two columns, numbers at the right, Balance left out when narrow), Flagged, search,
--             sort; from 0.9.44 (#43) periods by server day, who (character, realm, account), Days and Characters
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
  -- a choice of one of the pane's list buttons (More, who, the view, the Characters filter): open the list, click it
  local function pick(c, btn, label)
    if not (c.menu.shown and c.menu.anchor == btn) then click(btn) end
    for _, b in ipairs(c.menu.btns) do
      if b.shown ~= false and b.text.text == label then click(b); return true end
    end
    return false
  end
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
    pick(c, c.viewBtn, "Journal"); Gold.open("all", "journal"); Gold.open("today", "days"); Gold.open("week", "chars")
    ns.UI.Open("Loot", "items"); M.settle(); ns.UI.Open("Home", "sessions"); M.settle()
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
      check(tag .. ": This session is the selected period, shown on the More button", c.scopeBtns[1].ebSelected == nil and c.scopeBtns[2].ebSelected == nil and c.scopeBtns[3].ebSelected == nil
        and c.moreBtn.ebSelected == true and c.moreBtn.text.text == "This session", c.moreBtn.text.text)
      local wb = P.box(c.whoBtn)
      local mb = P.box(c.moreBtn)
      check(tag .. ": who and the view sit between the periods and the search box", mb.l >= last.l + last.w and mb.l + mb.w <= wb.l and wb.l + wb.w <= vb.l and vb.l + vb.w <= sb.l
        and c.whoBtn.text.text == "This character" and P.G.naturalWidth(c.whoBtn.text) <= wb.w - 2 * UI.SP.S and P.G.naturalWidth(c.moreBtn.text) <= mb.w - 2 * UI.SP.S,
        ("periods end %d, More %d to %d, who %d to %d, view %d to %d, search from %d, pane %d wide"):format(last.l + last.w, mb.l, mb.l + mb.w, wb.l, wb.l + wb.w, vb.l, vb.l + vb.w, sb.l, cb.w))
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
      check(tag .. ": NET PER HOUR is a signed rate, the label names the definition and the status line its time", c.cRate.title.text == "NET PER HOUR" and c.cRate.value.text:find("^[%+%-]%d") ~= nil
        and c.status.text:find("per hour over %d+h? ?%d*m? ?of the session") ~= nil and P.visible(c.statusRow), c.cRate.value.text .. " | " .. tostring(c.status.text))
      local stb = P.box(c.statusRow)
      local lowest = 0
      for _, k in ipairs(KEYS) do local b = P.box(c[k]); lowest = math.max(lowest, b.t + b.h) end
      check(tag .. ": the status line sits between the cards and the caption", stb.t >= lowest and stb.t + stb.h <= P.box(c.capRow).t + 0.5 and not c.status:IsTruncated(), stb.t - lowest)
      -- Sources
      local tbl = c.tblSrc
      check(tag .. ": the pane opens on Sources, every other table hidden", P.visible(tbl.sf) and not P.visible(c.tblJrn.sf) and not P.visible(c.tblJrnNarrow.sf) and not P.visible(c.tblDays.sf)
        and not P.visible(c.tblDaysNarrow.sf) and not P.visible(c.tblChars.sf) and not P.visible(c.tblCharsNarrow.sf) and not P.visible(c.dayStrip) and not P.visible(c.menu) and c.viewBtn.text.text == "Sources")
      local secs = tbl.sections()
      check(tag .. ": EARNED and SPENT sections carry their totals, then what is neither", #secs == 3 and secs[1].text == "EARNED  ·  " .. fmt(ses.gained) and secs[2].text == "SPENT  ·  " .. fmt(ses.spent) and secs[3].text == "NEITHER IN NOR OUT", secs[1] and secs[1].text)
      check(tag .. ": the cards are headed EARNED and SPENT", c.cIn.title.text == "EARNED" and c.cOut.title.text == "SPENT")
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
      check(tag .. ": a click on Quest rewards opens the journal (" .. (narrow and "without" or "with") .. " Balance)", P.visible(jt.sf) and not P.visible(other.sf) and not P.visible(tbl.sf) and c.viewBtn.text.text == "Journal")
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
      local mnb, vbb = P.box(c.menu), P.box(c.viewBtn)
      check(tag .. ": the view button opens its list under it: Sources, Journal, Days, Characters, the current one marked", P.visible(c.menu) and c.menu.btns[1].text.text == "Sources" and c.menu.btns[2].text.text == "Journal"
        and c.menu.btns[3].text.text == "Days" and c.menu.btns[4].text.text == "Characters" and c.menu.btns[2].ebSelected == true and c.menu.btns[1].ebSelected == nil
        and mnb.t >= vbb.t + vbb.h and near(mnb.l + mnb.w, vbb.l + vbb.w) and mnb.l >= cb.l, mnb.t - (vbb.t + vbb.h))
      click(c.viewBtn)
      check(tag .. ": a second click closes the list", not P.visible(c.menu))
      check(tag .. ": Sources is picked from the list", pick(c, c.viewBtn, "Sources") and not P.visible(c.menu))
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
    pick(c, c.viewBtn, "Sources")
    local srow
    for _, r in ipairs(dataRows(c.tblSrc)) do if r.item.key == "looted" then srow = r end end
    srow.scripts.OnEnter(srow)
    text = table.concat(tip.lines, " | ")
    check("Gold tooltip: a source row lists its biggest contributors and says what a click does", text:find("^Looted coin") and text:find("Defias", 1, true) and text:find("Click to list every row.", 1, true), text)
    srow.scripts.OnLeave(srow)
    -- periods
    local prev = Gold.scope("previous").sessions[1]
    click(c.moreBtn)
    local offered = {}
    for _, b in ipairs(c.menu.btns) do if b.shown ~= false then offered[#offered + 1] = b.text.text end end
    check("Gold periods: More offers This session, Yesterday, This month, Last 30 days, then the earlier sessions", offered[1] == "This session" and offered[2] == "Yesterday" and offered[3] == "This month"
      and offered[4] == "Last 30 days" and offered[5] == Gold.sessionLabel(prev) and #offered <= 4 + Gold.MORE_SESSIONS, table.concat(offered, ","))
    check("Gold periods: an earlier session is picked from More", pick(c, c.moreBtn, Gold.sessionLabel(prev)))
    check("Gold periods: an earlier session shows its numbers and its balance at the end", c.moreBtn.ebSelected and c.moreBtn.text.text == Gold.sessionLabel(prev) and c.cBalance.title.text == "BALANCE AT ITS END" and c.cIn.value.text == fmt(prev.gained)
      and c.caption.text:find(Gold.sessionLabel(prev), 1, true) == 1, c.caption.text)
    check("Gold periods: gold from the player's own character is shown as moved, not subtracted", c.status.text:find("Moved between your characters: " .. fmt(15000) .. " in", 1, true) ~= nil and c.cIn.value.text == fmt(prev.gained), c.status.text)
    Gold.open("previous"); M.settle()
    check("Gold periods: the Previous period is that session", c.cIn.value.text == fmt(prev.gained) and c.caption.text:find("^Previous session, ") ~= nil, c.caption.text)
    click(c.scopeBtns[3])
    check("Gold periods: All time reads the lifetime ledger and names what changed while away", c.cIn.value.text == fmt(ns.char().gold.gained) and c.cRate.title.text == "CHANGED WHILE AWAY" and c.cRate.value.text == Gold.signed(ns.char().gold.away or 0))
    pick(c, c.viewBtn, "Journal")
    local secs = c.tblJrn.sections()
    check("Gold periods: the All time journal has one section per session, the running one first", #secs >= 2 and secs[1].text:find("  ·  running  ·  net ", 1, true) ~= nil and secs[2].text:find("running", 1, true) == nil and c.caption.text:find("sessions since addon 0.9.40", 1, true) ~= nil, #secs)
    Gold.open(prev.id); M.settle()
    check("Gold periods: a session picked elsewhere shows on the More button, selected", P.visible(c.moreBtn) and c.moreBtn.ebSelected == true and c.moreBtn.text.text == Gold.sessionLabel(prev) and c.scopeBtns[1].ebSelected == nil)
    click(c.scopeBtns[1])
    check("Gold periods: on Today the More button is plain again", c.moreBtn.text.text == "More" and c.moreBtn.ebSelected == nil and c.scopeBtns[1].ebSelected == true and c.st.scope == "today")
    -- a long journal lists Gold.MAX_ROWS rows and says so; the count and the sum are of every row
    do
      local keep = Gold.MAX_ROWS
      Gold.MAX_ROWS = 20
      Gold.open("session", "journal"); M.settle()
      local n = #ns.Recorder.current().goldLog
      check("Gold long journal: the newest rows are listed, the caption counts them all", #dataRows(c.tblJrn) == 20 and c.caption.text:find(("Every row  ·  %d rows"):format(n), 1, true) == 1 and c.caption.text:find("the first 20 listed", 1, true) ~= nil, c.caption.text)
      Gold.MAX_ROWS = keep
    end
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
    check("Sessions gold: the button opens that session's journal in the Gold pane", P.visible(gold) and gold.st.scope == prevRow.item.id and gold.st.view == "journal" and gold.moreBtn.ebSelected == true and #dataRows(gold.tblJrn) == #prevRow.item.goldLog, gold.st.scope)
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
  -- ── 0.9.44 (#43): periods by server day, who, Days and Characters ───────────────────────────────────────────
  local DAY = 86400
  local MIRA, ORG = "Player-1-0000B1", "Player-1-0000B2"
  -- two more characters in the data in use: one seen three days ago with a day row today, one of another realm and
  -- faction not seen for 100 days; Hartbank (tests/play_gold.lua) has never logged in with 0.9.44
  local function addAlts()
    local base = Gold.baseStored()
    local now = GetServerTime()
    for guid in pairs(ns.DB.characters) do if guid ~= ns.charGuid() and guid ~= "Player-1-0000A1" then ns.DB.characters[guid] = nil end end
    ns.DB.characters[MIRA] = { name = "Mira", surname = "Dawnfall", realm = GetRealmName(), class = "WARRIOR", faction = "Alliance", level = 21, seen = now - 3 * DAY,
      gold = { balance = 961000, gained = 961000, spent = 0 },
      goldDays = { [Gold.dayKey(now, base)] = { g = 50000, s = 20000, o = 931000, c = 961000, t = 900, n = 3, looted = 50000, repairs = 20000, away = 0 } } }
    ns.DB.characters[ORG] = { name = "Orgrim", realm = "Forever Realm [EU] - Other Shore", class = "SHAMAN", faction = "Horde", level = 40, seen = now - 100 * DAY,
      gold = { balance = 5000000 } }
    ns.DB.characters["Player-1-0000A1"].gold = { balance = 150000 }
  end
  local function audit(tag)
    local found = {}
    for _, x in ipairs(P.Lay.audit(M.frames)) do found[#found + 1] = ("%s: %s (%s)"):format(x.kind, x.text, x.detail) end
    check(tag .. ": no text spills out of its box, over another text, or a number cut short", #found == 0, table.concat(found, " || "):sub(1, 400))
  end
  local function tableChecks(tag, tbl, c)
    local bad = {}
    local sfb, cb = P.box(tbl.sf), P.box(c)
    for i, r in ipairs(dataRows(tbl)) do
      local lastCell
      for _, col in ipairs(tbl.spec) do
        local cell = r.c[col.key]
        if not near(P.box(tbl.head[col.key].fs).l, P.box(cell).l) then bad[#bad + 1] = i .. " header x " .. col.key end
        if (col.kind == "money" or col.kind == "num" or col.kind == "tag") and cell:IsTruncated() then bad[#bad + 1] = i .. " shortened " .. col.key end
        lastCell = P.box(cell)
      end
      if lastCell.l + lastCell.w > sfb.l + sfb.w + 0.5 then bad[#bad + 1] = i .. " past the list" end
    end
    check(tag .. ": header x == cell x, numbers in full, every row inside the list", #bad == 0, table.concat(bad, "; "):sub(1, 300))
    check(tag .. ": the list ends inside the pane", sfb.t + sfb.h <= cb.t + cb.h + 0.5 and sfb.l >= cb.l - 0.5)
  end
  local function keys(tbl) local t = {}; for i, col in ipairs(tbl.spec) do t[i] = col.key end; return table.concat(t, ",") end

  for _, size in ipairs({ { 900, 580 }, { 1250, 760 }, { 1600, 1000 } }) do
    for _, data in ipairs({ "gold", "goldlong" }) do
      local tag = ("Gold 0.9.44 %dx%d %s"):format(size[1], size[2], data)
      local c = open(size[1], size[2], data, "today")
      addAlts(); Gold.open("today"); M.settle()
      local cb = P.box(c)
      local me = ns.char()
      local base = Gold.baseStored()
      local now = GetServerTime()
      local kT = Gold.dayKey(now, base)
      local today = me.goldDays[kT]
      local wide = (cb.w - UI.SCROLLBAR) >= 980
      check(tag .. ": the optional columns show from 980 px of list on: not at 900 px, at 1250 and 1600", (size[1] == 900) == (not wide), cb.w)
      -- every period's label fits on the More button without running into who
      local fits = {}
      local prevS = Gold.scope("previous").sessions[1]
      for _, key in ipairs({ "session", "yesterday", "month", "last30", prevS and prevS.id or "session", "day:" .. kT }) do
        Gold.open(key); M.settle()
        local mb, wb, vb, sb = P.box(c.moreBtn), P.box(c.whoBtn), P.box(c.viewBtn), P.box(c.search)
        if mb.l + mb.w > wb.l or wb.l + wb.w > vb.l or vb.l + vb.w > sb.l or sb.w < 90 or c.search.placeholder:IsTruncated() then fits[#fits + 1] = c.moreBtn.text.text end
      end
      check(tag .. ": the toolbar holds every period's label, the search box takes what is left", #fits == 0, table.concat(fits, ", "))
      Gold.open("today"); M.settle()
      -- Today: the first quick period, the day row's numbers on the cards
      check(tag .. ": Today is a quick period and the day row of the character", c.scopeBtns[1].text.text == "Today" and c.scopeBtns[2].text.text == "This week" and c.scopeBtns[3].text.text == "All time"
        and c.scopeBtns[1].ebSelected == true and c.moreBtn.text.text == "More" and c.moreBtn.ebSelected == nil and today ~= nil)
      check(tag .. ": the cards read the day row: EARNED, SPENT, NET, the live balance", c.cIn.value.text == fmt(today.g) and c.cOut.value.text == fmt(today.s) and c.cNet.value.text == Gold.signed(today.g - today.s)
        and c.cBalance.title.text == "BALANCE" and c.cBalance.value.text == fmt(me.gold.balance), c.cIn.value.text)
      check(tag .. ": under 5 minutes played the rate says so", c.cRate.title.text == "NET PER HOUR" and c.cRate.value.text == "after 5 min played", c.cRate.value.text)
      check(tag .. ": the status line says what changed while away and where the history starts", (today.away or 0) ~= 0 and c.status.text:find("Not seen: " .. Gold.signed(today.away) .. " changed while away", 1, true) ~= nil
        and c.status.text:find("History starts " .. Gold.fmtDate(me.goldSince) .. ". Days follow the server reset.", 1, true) ~= nil, c.status.text)
      local src = c.sourceData
      local okSrc = src.inTotal == today.g and src.outTotal == today.s
      for _, r in ipairs(src.rows) do if r.dir ~= 0 and r.amount ~= (today[r.key] or 0) then okSrc = false end end
      check(tag .. ": the sources of Today are the day row's keys, their rows the journal's of that day", okSrc and #src.rows >= 10 and c.caption.text:find("^Today: click a source to list its rows") ~= nil, c.caption.text)
      audit(tag .. " Today")

      -- ── Days ──
      check(tag .. ": Days is picked from the view list", pick(c, c.viewBtn, "Days") and c.viewBtn.text.text == "Days" and c.st.view == "days")
      local dt, dOther = wide and c.tblDays or c.tblDaysNarrow, wide and c.tblDaysNarrow or c.tblDays
      check(tag .. ": the Days table for this width shows, every other table is hidden", P.visible(dt.sf) and not P.visible(dOther.sf) and not P.visible(c.tblSrc.sf) and not P.visible(c.tblJrn.sf) and not P.visible(c.tblChars.sf) and not P.visible(c.tblCharsNarrow.sf))
      eq(tag .. ": Days columns", keys(dt), wide and "day,earned,spent,net,played,rate,top,bal" or "day,earned,spent,net,bal")
      local dr = dataRows(dt)
      check(tag .. ": Today has one day, marked today, with the row's numbers", #dr == 1 and dr[1].c.day.text == Gold.dayLabel(kT, base) .. "  ·  today" and dr[1].c.earned.text == fmt(today.g)
        and dr[1].c.spent.text == fmt(today.s) and dr[1].c.net.text == Gold.signed(today.g - today.s) and dr[1].c.bal.text == fmt(today.c), dr[1] and dr[1].c.day.text)
      if wide then
        local tk, tv = Gold.topSource(Gold.period("today").days[1].src)
        check(tag .. ": the wide Days table names the day's top source", dr[1].c.top.text == Gold.LABEL[tk] .. " " .. fmt(tv), dr[1].c.top.text)
      end
      local stb, hb = P.box(c.dayStrip), P.box(dt.header)
      check(tag .. ": the strip of the last 30 days sits above the table, as wide as the list", P.visible(c.dayStrip) and c.dayStrip.n == 30 and stb.t + stb.h <= hb.t + 0.5 and stb.l >= cb.l and stb.l + stb.w <= cb.l + cb.w - UI.SCROLLBAR + 0.5
        and c.dayStrip.title.text == "NET PER DAY, LAST 30 DAYS" and #c.dayStrip.values >= 2, stb.w)
      check(tag .. ": the caption counts the days and their net", c.caption.text:find("^Today  ·  1 day  ·  net " .. Gold.signed(today.g - today.s):gsub("%p", "%%%0")) ~= nil, c.caption.text)
      tableChecks(tag .. " Days", dt, c)
      audit(tag .. " Days")
      -- All time: every day, a subtotal line per week and month, the days a change while away covers
      me.goldDays[Gold.dayKey(now - 12 * DAY, base)] = { g = 9000, s = 1000, o = 2000, c = 10050, t = 3700, n = 3, looted = 9000, repairs = 1000, away = 50 }
      me.goldDays[Gold.dayKey(now - 20 * DAY, base)] = { g = 2000, s = 0, o = 0, c = 2000, t = 60, n = 1, quests = 2000 }
      click(c.scopeBtns[3])
      dr = dataRows(dt)
      local nDays = 0
      for _ in pairs(me.goldDays) do nDays = nDays + 1 end
      check(tag .. ": All time lists every day, newest first", #dr == nDays and nDays >= 4 and dr[1].item.key == kT and dr[#dr].item.key == Gold.dayKey(now - 20 * DAY, base), #dr)
      local weeks, gaps, months = 0, 0, 0
      for _, s in ipairs(dt.sections()) do
        if s.text:find("^Week of ") and s.text:find("earned ", 1, true) and s.text:find("net ", 1, true) then weeks = weeks + 1 end
        if s.text:find("not recorded on this PC", 1, true) then gaps = gaps + 1 end
        if s.text:find("^%u+ %d%d%d%d  ·  earned ") then months = months + 1 end
      end
      check(tag .. ": a subtotal line over each week", weeks >= 3, weeks)
      check(tag .. ": the days a change while away covers read not recorded on this PC, never zero", gaps >= 1, gaps)
      if wide then
        local old
        for _, r in ipairs(dr) do if r.item.key == Gold.dayKey(now - 12 * DAY, base) then old = r end end
        check(tag .. ": Played and Per hour come from the day's active seconds", old and old.c.played.text == "1h 1m" and old.c.rate.text:find("^%+") ~= nil and dr[1].c.rate.text == "", old and old.c.played.text)
      end
      local hbE = dt.head.earned; hbE.scripts.OnClick(hbE); M.settle()
      dr = dataRows(dt)
      local sorted = true
      for i = 2, #dr do if dr[i].item.g > dr[i - 1].item.g then sorted = false end end
      check(tag .. ": a click on Earned sorts by it, biggest first, with no subtotal lines; both Days tables keep the sort", sorted and #dt.sections() == 0 and dOther.sortKey == "earned")
      local hbD = dt.head.day; hbD.scripts.OnClick(hbD); M.settle()
      if dt.sortAsc then hbD.scripts.OnClick(hbD); M.settle() end
      tableChecks(tag .. " Days, all time", dt, c)
      audit(tag .. " Days, all time")
      -- a click on a day opens its sources
      dr = dataRows(dt)
      local oldRow
      for _, r in ipairs(dr) do if r.item.key == Gold.dayKey(now - 12 * DAY, base) then oldRow = r end end
      oldRow.scripts.OnEnter(oldRow)
      local tipText = table.concat(tip.lines, " | ")
      check(tag .. ": a day's tooltip lists its sources and says what a click does", tipText:find("Looted coin  " .. fmt(9000), 1, true) and tipText:find("Changed while away  +50c", 1, true) and tipText:find("Click to open this day's sources.", 1, true), tipText)
      oldRow.scripts.OnLeave(oldRow)
      click(oldRow)
      check(tag .. ": a click on a day opens Sources for that day, the day on the More button", c.st.view == "sources" and c.st.scope == "day:" .. Gold.dayKey(now - 12 * DAY, base) and P.visible(c.tblSrc.sf)
        and c.moreBtn.ebSelected == true and c.moreBtn.text.text == Gold.dayLabel(Gold.dayKey(now - 12 * DAY, base), base) and c.cIn.value.text == fmt(9000) and c.cOut.value.text == fmt(1000)
        and c.cBalance.title.text == "BALANCE AT ITS END" and c.cBalance.value.text == fmt(10050), c.st.scope)
      local looted
      for _, r in ipairs(dataRows(c.tblSrc)) do if r.item.key == "looted" then looted = r end end
      check(tag .. ": a day older than the journals in the file keeps its totals and says why it has no rows", looted and looted.c.amount.text == fmt(9000) and looted.c.what.text == "totals only, no rows" and looted.c.go.text == ""
        and c.caption.text:find("Rows are kept until the desktop app has uploaded the session. Totals stay.", 1, true) ~= nil, c.caption.text)

      -- ── who ──
      click(c.scopeBtns[1])
      check(tag .. ": Account is picked from the who list", pick(c, c.whoBtn, "Account") and c.whoBtn.text.text == "Account" and c.st.who == "account")
      local ro = Gold.roster("all")
      check(tag .. ": the account's Today sums the characters' day rows on read", c.cIn.value.text == fmt(today.g + 50000) and c.cOut.value.text == fmt(today.s + 20000), c.cIn.value.text)
      check(tag .. ": BALANCE becomes TOTAL GOLD, the status line counts the characters and dates the oldest balance", c.cBalance.title.text == "TOTAL GOLD" and c.cBalance.value.text == fmt(ro.total)
        and ro.total == me.gold.balance + 961000 + 150000 and c.status.text:find("3 characters, oldest balance from " .. Gold.fmtDate(now - 3 * DAY), 1, true) == 1, c.status.text)
      check(tag .. ": a character with a change not seen on this PC in the period is named in the status line", c.status.text:find("1 character with changes not seen on this PC in this period", 1, true) ~= nil, c.status.text)
      check(tag .. ": an account has totals only, and the caption says so", #c.entries == 0 and c.caption.text:find("totals only: journal rows are kept per character", 1, true) ~= nil and not P.visible(c.flagBtn), c.caption.text)
      audit(tag .. " Account")
      pick(c, c.whoBtn, "This realm")
      check(tag .. ": This realm leaves the other realm out", c.cBalance.value.text == fmt(Gold.roster("realm").total) and c.whoBtn.text.text == "This realm")
      pick(c, c.moreBtn, "This session")
      check(tag .. ": a session is one character's: who goes back to This character", c.st.who == "char" and c.whoBtn.text.text == "This character" and c.cBalance.title.text == "BALANCE")
      click(c.scopeBtns[1])

      -- ── Characters ──
      check(tag .. ": Characters is picked from the view list", pick(c, c.viewBtn, "Characters") and c.st.view == "chars")
      local ct, cOther = wide and c.tblChars or c.tblCharsNarrow, wide and c.tblCharsNarrow or c.tblChars
      check(tag .. ": the Characters table for this width shows", P.visible(ct.sf) and not P.visible(cOther.sf) and not P.visible(c.tblSrc.sf) and not P.visible(dt.sf) and not P.visible(c.dayStrip))
      eq(tag .. ": Characters columns", keys(ct), wide and "name,realm,faction,level,balance,share,today,d7,seen" or "name,balance,today,d7,seen")
      local cr = shown(ct.rows)
      local function rowOf(guid) for _, r in ipairs(shown(ct.rows)) do if r.item and r.item.guid == guid then return r end end end
      check(tag .. ": the TOTAL row is pinned first and sums the characters counted", cr[1].item.total == true and cr[1].c.name.text == "TOTAL  ·  3 characters" and cr[1].c.balance.text == fmt(ro.total)
        and cr[1].c.today.text == Gold.signed(today.g - today.s + 30000), cr[1].c.name.text .. " " .. cr[1].c.today.text)
      check(tag .. ": every character of the save file is listed, by balance", #cr == 5 and cr[2].item.balance >= cr[3].item.balance and cr[3].item.balance >= cr[4].item.balance and cr[4].item.balance >= cr[5].item.balance, #cr)
      local meRow, mira, org, bank = rowOf(ns.charGuid()), rowOf(MIRA), rowOf(ORG), rowOf("Player-1-0000A1")
      check(tag .. ": the current character says You and now", meRow.c.name.text:find("  ·  You$") ~= nil and meRow.c.seen.text == "now", meRow.c.name.text)
      check(tag .. ": a two-name character in its class colour, with today, 7 days and its age", mira.c.name.text == "Mira Dawnfall" and math.abs(mira.c.name._color[1] - RAID_CLASS_COLORS.WARRIOR.r) < 0.01 and math.abs(UI.C.ink[1] - RAID_CLASS_COLORS.WARRIOR.r) > 0.01
        and mira.c.today.text == "+3g" and mira.c.d7.text == "+3g" and mira.c.seen.text == "3 d ago" and mira.c.balance.text == fmt(961000), mira.c.name.text .. " " .. mira.c.seen.text)
      check(tag .. ": a character not seen in 90 days is listed, dimmed, and says it is not in the total", org.c.seen.text:find(", not in total$") ~= nil and near(org.c.name._color[1], UI.C.dim[1]) and org.item.counted == false, org.c.seen.text)
      check(tag .. ": a character not seen since the update says log in once to refresh", bank.c.seen.text == "log in once to refresh" and near(bank.c.name._color[1], UI.C.dim[1]))
      check(tag .. ": the caption names the filter, the count, the total and who still needs a login", c.caption.text:find("^All characters  ·  3 characters, oldest balance from ") ~= nil and c.caption.text:find("total " .. fmt(ro.total), 1, true) ~= nil
        and c.caption.text:find("1 character not seen since the update: log in once on each to refresh", 1, true) ~= nil, c.caption.text)
      if wide then
        check(tag .. ": the wide table adds realm (short), faction, level and share", org.c.realm.text == "Other Shore" and org.c.faction.text == "Horde" and org.c.level.text == "40" and mira.c.level.text == "21"
          and org.c.share.text == "" and mira.c.share.text == ("%d%%"):format(math.floor(961000 / ro.total * 100 + 0.5)) and cr[1].c.share.text == "100%", org.c.realm.text)
      end
      check(tag .. ": the filter and the 90 days button sit at the caption's right, the caption ends before them", P.visible(c.filterBtn) and c.filterBtn.text.text == "All characters" and P.visible(c.staleBtn)
        and c.staleBtn.text.text == "Not seen in 90 days: 1" and P.box(c.staleBtn).l + P.box(c.staleBtn).w <= P.box(c.filterBtn).l and P.box(c.caption).l + P.box(c.caption).w <= P.box(c.staleBtn).l + 0.5
        and not P.visible(c.flagBtn) and not P.visible(c.allBtn))
      tableChecks(tag .. " Characters", ct, c)
      audit(tag .. " Characters")
      -- the tooltip of a row: the raw realm string
      org.scripts.OnEnter(org)
      tipText = table.concat(tip.lines, " | ")
      check(tag .. ": a character's tooltip carries the raw realm string, its facts and what a click does", tipText:find("Realm: Forever Realm [EU] - Other Shore", 1, true) and tipText:find("level 40", 1, true) and tipText:find("Not in the total: not seen in 90 days.", 1, true)
        and tipText:find("Click: hide from totals.", 1, true), tipText)
      org.scripts.OnLeave(org)
      -- the characters not seen in 90 days, included on request
      click(c.staleBtn)
      check(tag .. ": included, the stale character is in the TOTAL row", shown(ct.rows)[1].c.balance.text == fmt(ro.total + 5000000) and shown(ct.rows)[1].c.name.text == "TOTAL  ·  4 characters" and c.staleBtn.ebSelected == true)
      click(c.staleBtn)
      -- hide from totals: the row menu
      click(rowOf(MIRA))
      check(tag .. ": a click on a character offers to hide it from totals", P.visible(c.menu) and c.menu.btns[1].text.text == "Hide from totals" and c.menu.btns[2].shown == false)
      click(c.menu.btns[1])
      check(tag .. ": hidden, it leaves the TOTAL row and every account figure at once", ns.DB.settings.gold.hidden[MIRA] == true and shown(ct.rows)[1].c.balance.text == fmt(ro.total - 961000)
        and shown(ct.rows)[1].c.name.text == "TOTAL  ·  2 characters" and rowOf(MIRA).c.seen.text == "hidden from totals" and Gold.metric("balance", "account") == ro.total - 961000
        and Gold.metric("earned", "account", "today") == today.g and ns.DB.characters[MIRA].hidden == nil and c.caption.text:find("1 hidden from totals", 1, true) ~= nil, shown(ct.rows)[1].c.balance.text)
      click(rowOf(MIRA))
      check(tag .. ": a hidden character offers to be shown again", c.menu.btns[1].text.text == "Show in totals")
      click(c.menu.btns[1])
      check(tag .. ": shown again, the total is back and no empty table is left in the settings", shown(ct.rows)[1].c.balance.text == fmt(ro.total) and ns.DB.settings.gold.hidden == nil)
      -- the filter is saved and is the roster's
      check(tag .. ": This realm is picked from the filter list", pick(c, c.filterBtn, "This realm") and ns.DB.settings.gold.filter == "realm" and c.filterBtn.text.text == "This realm")
      check(tag .. ": the filter leaves the other realm's character out of the list and the 90 days button with it", rowOf(ORG) == nil and #shown(ct.rows) == 4 and not P.visible(c.staleBtn) and c.caption.text:find("^This realm  ·  ") ~= nil)
      pick(c, c.filterBtn, "All characters")
      -- sort by name: the TOTAL row stays first
      local hbN = ct.head.name; hbN.scripts.OnClick(hbN); M.settle()
      cr = shown(ct.rows)
      local okSort = cr[1].item.total == true
      for i = 3, #cr do if cr[i].item.label:lower() < cr[i - 1].item.label:lower() then okSort = false end end
      check(tag .. ": sorted by name the TOTAL row stays pinned; both Characters tables keep the sort", okSort and cOther.sortKey == "name")
      local hbB = ct.head.balance; hbB.scripts.OnClick(hbB); M.settle()
      if ct.sortAsc then hbB.scripts.OnClick(hbB); M.settle() end
      pick(c, c.viewBtn, "Sources")
    end
  end
  -- the first run: no day row yet, one character
  do
    local c = open(900, 580, "gold", "today")
    local me = ns.char()
    me.goldDays, me.goldSince = nil, nil
    for guid in pairs(ns.DB.characters) do if guid ~= ns.charGuid() then ns.DB.characters[guid] = nil end end
    Gold.open("today"); M.settle()
    check("Gold first run: Today with no day row shows zeros, the balance and the empty sentence", c.cIn.value.text == "0c" and c.cOut.value.text == "0c" and c.cNet.value.text == "+0c" and c.cBalance.value.text == fmt(me.gold.balance)
      and c.tblSrc.empty.shown and c.tblSrc.empty.text == "No gold moved in this period yet." and c.caption.text == "Today", c.caption.text)
    check("Gold first run: nothing claims a history that does not exist", not tostring(c.status.text):find("History starts", 1, true))
    pick(c, c.viewBtn, "Days")
    check("Gold first run: Days says when rows begin and that days follow the server reset", c.tblDaysNarrow.empty.shown and c.tblDaysNarrow.header.shown == false
      and c.tblDaysNarrow.empty.text == "No days yet. Each day with a gold change gets a row from addon 0.9.44 on. Days follow the server reset." and c.caption.text == "Today  ·  no days recorded", c.caption.text)
    pick(c, c.viewBtn, "Characters")
    local cr = shown(c.tblCharsNarrow.rows)
    check("Gold first run: Characters lists the one character under its TOTAL row", #cr == 2 and cr[1].c.name.text == "TOTAL  ·  1 character" and cr[1].c.balance.text == fmt(me.gold.balance) and cr[2].c.name.text:find("  ·  You$") ~= nil and not P.visible(c.staleBtn), #cr)
    for _, key in ipairs({ "week", "yesterday", "month", "last30" }) do Gold.open(key); M.settle() end
    check("Gold first run: every day period opens on an empty history without an error", #UI.paneErrors() == 0 and c.cIn.value.text == "0c", table.concat(UI.paneErrors(), " || "))
    pick(c, c.viewBtn, "Sources")
    -- the pane follows the purse while it is open: one refresh 0.1 s after a change
    Gold.open("today"); M.settle()
    local before = c.cIn.value.text
    M.money = M.money + 1234; M.fire("PLAYER_MONEY")
    check("Gold live: a change is not drawn in the same call (coalesced)", c.cIn.value.text == before)
    M.runTimers(); M.settle()
    check("Gold live: the open pane shows the change after its 0.1 s refresh", c.cIn.value.text == fmt(1234) and me.goldDays ~= nil, c.cIn.value.text)
  end
  ns.Recorder.current = savedCurrent
  check("Gold: no errors from the panes' resize or events", #UI.paneErrors() == 0, table.concat(UI.paneErrors(), " || "))
end
