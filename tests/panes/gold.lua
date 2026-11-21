-- Pane tests: gold, one model on every surface (everbuff-wow-addon #38). Everbuff/Economy.lua holds the model
-- (ns.Gold) and LOOT > Gold (docs/UX_PRAGMATIC.md 4.2); Home / Sessions shows a session's gold band. Played on
-- tests/play_gold.lua ("gold": two evenings with a name behind every row).
--   model     every journal row parsed, the balance chain intact, each source summing to the session ledger, the
--             quest, item, merchant, mob and player named, Location and Coordinates only from the row's own record
--   Gold pane the period control (Session, Today, Week, All); 4 cards with what was not traced, no line above them
--             and no note under them; the list under its section header, which names the period and holds the view:
--             Sources (EARNED, SPENT, a row opens its source page), Auction house (the answer Spent, received, net;
--             one purchase one row) and Journal (day rows with the day's net, search); where the gold history
--             starts inside a period; Sources not offered for dungeon time from before the coin capture of 0.9.52
--   elsewhere the Sessions band, nothing written into the save file
return function(P)
  local check, eq, M, ns = P.check, P.eq, P.M, P.ns
  local UI, Gold = ns.UI, ns.Gold
  local GP = Gold.GP
  local money = GP.money
  local tip = _G.GameTooltip
  local SIZES = { { 900, 580 }, { 1250, 760 }, { 1600, 1000 } }
  local function near(a, b) return a and b and math.abs(a - b) < 0.51 end
  local function colorIs(fs, key) local c, k = fs._color, UI.C[key]; return c ~= nil and math.abs(c[1] - k[1]) < 0.01 and math.abs(c[2] - k[2]) < 0.01 and math.abs(c[3] - k[3]) < 0.01 end
  local function shown(rows) local out = {}; for _, r in ipairs(rows or {}) do if r.shown ~= false then out[#out + 1] = r end end return out end
  local function dataRows(tbl) local out = {}; for _, r in ipairs(shown(tbl.rows)) do if r.item and not r.item.ebSection then out[#out + 1] = r end end return out end
  local function click(b) b.scripts.OnClick(b, "LeftButton"); M.settle() end
  -- a choice of a filter button's menu: open it, click the row with that label
  local function pick(fb, label)
    click(fb)
    for _, r in ipairs(fb.menu.rows or {}) do
      if r.shown ~= false and r.text:GetText() == label then click(r); return true end
    end
    fb.menu:Hide()
    return false
  end
  local function offered(fb)
    click(fb)
    local out = {}
    for _, r in ipairs(fb.menu.rows or {}) do if r.shown ~= false then out[#out + 1] = r.text:GetText() end end
    fb.menu:Hide()
    return out
  end
  local function period(c, key) for _, b in ipairs(c.period.segs) do if b.key == key then click(b) end end end
  local function view(c, key) for _, b in ipairs(c.viewSeg.segs) do if b.key == key then click(b) end end end
  local function strip(s) return (tostring(s or ""):gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("\194\160", " ")) end
  local function typeIn(e, text) e:SetText(text); e.scripts.OnTextChanged(e); M.settle() end
  local function tipOf(f) f.scripts.OnEnter(f); local t = table.concat(tip.lines, " | "); f.scripts.OnLeave(f); return t end
  local function keys(tbl) local t = {}; for _, col in ipairs(tbl.spec) do if not col.wide or (tbl.cols and tbl.cols[col.key]) then t[#t + 1] = col.key end end; return table.concat(t, ",") end
  local function cardLabels(cards) local t = {}; for i, cd in ipairs(cards) do t[i] = cd.label:GetText() end; return table.concat(t, ",") end
  -- the suite's recorder still holds the session object of its last play; the panes read the running session of the
  -- data in use
  local savedCurrent = ns.Recorder.current
  ns.Recorder.current = function() return ns.DB.active and ns.DB.sessions[ns.DB.active] or nil end
  local function open(w, h, data, scope, view, flags)
    local c = P.open("loot", "gold", w, h, data or "gold")
    -- (the coin capture of 0.9.52 as old as the character, so Sources is offered: its own tests set it otherwise)
    ns.char().goldShareSince = 1
    Gold.open(scope or "session", view, flags); M.settle()
    return c
  end
  -- every row of a table inside the column, its cells under their headers, numbers never shortened
  local function tableChecks(tag, tbl, c)
    local bad = {}
    local col = P.box(c.col)
    for i, r in ipairs(dataRows(tbl)) do
      for _, sp in ipairs(tbl.spec) do
        local cell = r.c[sp.key]
        if cell and cell.shown ~= false then
          if not near(P.box(tbl.head[sp.key].fs).l, P.box(cell).l) then bad[#bad + 1] = i .. " header x " .. sp.key end
          if (sp.kind == "money" or sp.kind == "num") and cell:IsTruncated() then bad[#bad + 1] = i .. " shortened " .. sp.key end
          local cb = P.box(cell)
          if cb.l + cb.w > col.l + col.w + 0.5 then bad[#bad + 1] = i .. " past the column " .. sp.key end
        end
      end
    end
    check(tag .. ": cells under their headers, numbers in full, every row inside the column", #bad == 0, table.concat(bad, "; "):sub(1, 300))
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
    view(c, "journal"); Gold.open("all", "journal"); Gold.open("today", "auctions"); Gold.open("week")
    ns.UI.Open("Loot", "items"); M.settle(); ns.UI.Open("Home", "sessions"); M.settle()
    walk(ns.DB, {})
    eq("model: the panes write nothing into the save file", marks, 0)
  end

  -- ── the Gold pane: layout on both data sets at three sizes ──────────────────────────────────────────────────
  for _, size in ipairs(SIZES) do
    for _, data in ipairs({ "gold", "goldlong" }) do
      local tag = ("Gold %dx%d %s"):format(size[1], size[2], data)
      local c = open(size[1], size[2], data)
      local ses = ns.Recorder.current()
      local G = UI.G
      local winW = G.winW()
      local mainW = G.mainW(winW)
      -- the control row: Session, Today, Week, All; nothing else
      local segs = {}
      for i, b in ipairs(c.period.segs) do segs[i] = b.text:GetText() end
      eq(tag .. ": the period control", table.concat(segs, ","), "Session,Today,Week,All")
      local pb = P.box(c.period)
      check(tag .. ": the period control ends at the control row's right, Session selected", pb.l + pb.w <= P.box(_G.EverbuffFrame).l + winW - G.BOX_R_INSET + 0.5 and c.period.value == "session", pb.l + pb.w)
      check(tag .. ": no More button, no Break down by, no line above the cards and no note under them", c.more == nil and c.breakdown == nil and c.summary == nil and c.untraced == nil and c.reviewBtn == nil)
      -- the cards: 4 at every width, as wide as the column, S3 apart, values in fg, at the top of the page
      local sc = Gold.scope("session")
      local card = Gold.netCard(sc.ledger, Gold.scopeEntries(sc))
      local cards = c.shownCards
      eq(tag .. ": the cards", cardLabels(cards), "BALANCE,EARNED,SPENT,NET")
      local cbad = {}
      local colB = P.box(c.col)
      local first, last = P.box(cards[1]), P.box(cards[#cards])
      if not near(first.l, colB.l) or not near(last.l + last.w, colB.l + mainW) then cbad[#cbad + 1] = "the row is not the column's width" end
      if not near(first.t, colB.t) then cbad[#cbad + 1] = "the cards are not the first thing on the page" end
      for i = 2, #cards do
        local a, b = P.box(cards[i - 1]), P.box(cards[i])
        if not near(a.l + a.w + UI.S.S3, b.l) or not near(a.h, UI.H.STAT) then cbad[#cbad + 1] = "gap or height " .. i end
      end
      for i, cd in ipairs(cards) do
        if cd.value:IsTruncated() then cbad[#cbad + 1] = "value cut " .. i end
        if cd.meta:IsTruncated() then cbad[#cbad + 1] = "meta cut " .. i .. ": " .. tostring(cd.meta:GetText()) end
        if not colorIs(cd.value, "fg") then cbad[#cbad + 1] = "value not fg " .. i end
        if (cd.meta:GetText() or ""):find("entr", 1, true) then cbad[#cbad + 1] = "an entry count on card " .. i end
      end
      check(tag .. ": the cards open the page, fill the column, 12 px apart, 80 high, values and metas in full, no entry count", #cbad == 0, table.concat(cbad, "; "))
      eq(tag .. ": BALANCE", cards[1].value:GetText(), money(ns.char().gold.balance))
      eq(tag .. ": EARNED / SPENT", cards[2].value:GetText() .. " / " .. cards[3].value:GetText(), money(ses.gained, true) .. " / " .. money(-ses.spent, true))
      eq(tag .. ": NET", cards[4].value:GetText(), money(card.net, true))
      check(tag .. ": the data has gold with no source seen both ways", sc.ledger.unexplained > 0 and (sc.ledger.other or 0) > 0)
      eq(tag .. ": EARNED says what moved in with no source seen", cards[2].meta:GetText(), money(sc.ledger.unexplained) .. " not traced")
      eq(tag .. ": SPENT says what moved out with no source seen", cards[3].meta:GetText(), money(sc.ledger.other) .. " not traced")
      check(tag .. ": BALANCE's meta is every character's gold", cards[1].meta:GetText():find("^all ") ~= nil or (c.audit.state == "broken" and cards[1].meta:GetText() == "records do not add up"), cards[1].meta:GetText())
      check(tag .. ": their hover says it in the list's words", tipOf(cards[2]):find(GP.UNTRACED.unexplained, 1, true) ~= nil and tipOf(cards[2]):find(GP.UNTRACED_TIP, 1, true) ~= nil
        and tipOf(cards[3]):find(GP.UNTRACED.other, 1, true) ~= nil, tipOf(cards[2]))
      -- the list: its section header names the period; the view control sits at the header's right
      local hb, vb = P.box(c.section), P.box(c.viewSeg)
      local vlabels = {}
      for i, b in ipairs(c.viewSeg.segs) do vlabels[i] = b.text:GetText() end
      eq(tag .. ": the views", table.concat(vlabels, ","), "Sources,Auction house,Journal")
      check(tag .. ": the section header THIS SESSION under the cards, the view control at its right, no search on Sources", c.section.label:GetText() == "THIS SESSION" and near(vb.l + vb.w, hb.l + hb.w)
        and c.viewSeg.value == "sources" and not P.visible(c.search) and near(hb.t, first.t + first.h + UI.S.S5) and P.box(c.section.label).l + P.box(c.section.label).w < vb.l, ("%s %s"):format(vb.l + vb.w, hb.l + hb.w))
      local tbl = c.tbl.sources
      local others = 0
      for k, t in pairs(c.tbl) do if k ~= "sources" and P.visible(t.frame) then others = others + 1 end end
      check(tag .. ": Sources shows, every other table is hidden, no auction answer", P.visible(tbl.frame) and others == 0 and not P.visible(c.answer))
      local secs = {}
      for i, s in ipairs(tbl.sections()) do secs[i] = s:GetText() end
      check(tag .. ": the groups are words only, EARNED then SPENT: a total is never a list row", secs[1] == "EARNED" and secs[2] == "SPENT" and not table.concat(secs, " "):find("%d"), table.concat(secs, " | "))
      eq(tag .. ": Sources columns", keys(tbl), "src,what,whatAmt,amount")
      eq(tag .. ": the column of the largest group is MOSTLY FROM", tbl.head.what.fs:GetText(), "MOSTLY FROM")
      local rows = dataRows(tbl)
      local sbad, away = {}, nil
      for _, r in ipairs(rows) do
        local it = r.item
        if r.c.src:GetText() ~= GP.srcLabel(it.key) then sbad[#sbad + 1] = it.key .. " label" end
        if r.c.amount:GetText() ~= (it.dir == 0 and money(it.amount, true) or money(it.dir * it.amount, true)) then sbad[#sbad + 1] = it.key .. " amount" end
        if GP.UNTRACED[it.key] and not colorIs(r.c.src, "fgSubtle") then sbad[#sbad + 1] = it.key .. " not subtle" end
        if colorIs(r.c.amount, "red") or colorIs(r.c.amount, "green") then sbad[#sbad + 1] = it.key .. " coloured" end
        for _, k in ipairs({ "what", "whatAmt", "amount", "src" }) do if r.c[k]:GetText() == "-" then sbad[#sbad + 1] = it.key .. " a dash in " .. k end end
        if it.dir ~= 0 and it.kept and it.top[1] and not GP.NO_NAME[it.top[1].name] and r.c.what:GetText() == "" then sbad[#sbad + 1] = it.key .. " no mostly from" end
        if it.dir ~= 0 and not it.kept and r.c.what:GetText() ~= "" then sbad[#sbad + 1] = it.key .. " mostly from on rows that do not add up" end
        if it.key == "away" then away = r end
      end
      check(tag .. ": source rows: the label, the signed amount, untraced ones in fgSubtle, nothing red or green, no dash, mostly from only on rows that add up", #sbad == 0 and #rows >= 14, table.concat(sbad, "; "))
      local labels = {}
      for _, r in ipairs(rows) do labels[r.item.key] = r.c.src:GetText() end
      check(tag .. ": gold with no source seen is not called away", labels.unexplained == "Source not seen" and labels.other == "Spending not explained", tostring(labels.unexplained))
      check(tag .. ": what changed while the addon was not running is its own row, neither earned nor spent", away ~= nil and away.c.src:GetText() == "While you were away" and away.c.amount:GetText() == money(4200, true)
        and secs[#secs] == "NOT EARNED OR SPENT" and tipOf(away):find(GP.AWAY_TIP, 1, true) ~= nil, away and away.c.amount:GetText())
      local mcut = {}
      for _, r in ipairs(rows) do if r.c.whatAmt:IsTruncated() then mcut[#mcut + 1] = r.item.key end end
      check(tag .. ": the largest group's amount has a cell of its own and is never cut", #mcut == 0, table.concat(mcut, ","))
      tableChecks(tag .. " Sources", tbl, c)
      check(tag .. ": the page scrolls as one: the column holds the table", c.contentH >= P.box(tbl.frame).t - colB.t + tbl.height, c.contentH)
      -- a source row opens its page
      local qrow
      for _, r in ipairs(rows) do if r.item.key == "quests" then qrow = r end end
      click(qrow)
      local d = c.srcPage
      local jr = dataRows(d.tbl)
      local sumQ = 0
      for _, r in ipairs(jr) do sumQ = sumQ + r.item.delta end
      check(tag .. ": a click on Quest rewards opens its page: TITLE, META with the period, times and sum", c.srcDetail.IsOpen() and d.title:GetText() == "Quest rewards"
        and d.meta:GetText() == ("This session \194\183 %s \194\183 %s"):format(UI.plural(qrow.item.n, "time"), money(sumQ, true)), d.meta:GetText())
      local only = true
      for _, r in ipairs(jr) do if r.item.src ~= "quests" then only = false end end
      check(tag .. ": the page lists only that source's entries, newest first under day rows", only and #jr == qrow.item.n and jr[1].item.t >= jr[#jr].item.t and #d.tbl.sections() >= 1, #jr)
      eq(tag .. ": the newest quest entry names its quest", jr[1].c.detail:GetText(), "The Defias Brotherhood")
      c.srcDetail.Close(); M.settle()
      check(tag .. ": Back returns to Sources", not c.srcDetail.IsOpen() and P.visible(tbl.frame))
      -- the other two views at this size: inside the column, nothing cut
      view(c, "journal")
      tableChecks(tag .. " Journal", c.tbl.journal, c)
      local sb = P.box(c.search)
      vb = P.box(c.viewSeg)
      check(tag .. ": on Journal the 176 px search sits S2 before the view control, after the header's label", P.visible(c.search) and near(sb.w, UI.SEARCH_W) and near(sb.l + sb.w + UI.S.S2, vb.l)
        and P.box(c.section.label).l + P.box(c.section.label).w <= sb.l, ("%s %s"):format(sb.l + sb.w, vb.l))
      Gold.open("all", "auctions"); M.settle()
      tableChecks(tag .. " Auction house", c.tbl.auctions, c)
      if P.visible(c.answer) then
        local ab = P.box(c.answer)
        check(tag .. ": the auction answer sits under the section header, over the table", near(ab.t, P.box(c.section).t + UI.H.SECTION) and ab.t + ab.h <= P.box(c.tbl.auctions.frame).t + 0.5, ab.t)
      end
    end
  end

  -- ── the views, search, tooltips, periods ────────────────────────────────────────────────────────────────────
  do
    local c = open(1250, 760)
    local ses = ns.Recorder.current()
    -- Journal
    view(c, "journal")
    check("Gold Journal: picked from the view control", c.st.view == "journal" and c.view == "journal" and c.viewSeg.value == "journal" and c.section.label:GetText() == "THIS SESSION" and P.visible(c.tbl.journal.frame))
    local jt = c.tbl.journal
    local jr = dataRows(jt)
    eq("Gold Journal: every entry of the session", #jr, #ses.goldLog)
    check("Gold Journal: newest first, a day row over each day, no entry count on it", jr[1].item.t >= jr[#jr].item.t and #jt.sections() >= 1 and jt.sections()[1]:GetText():find("ENTR", 1, true) == nil, jt.sections()[1]:GetText())
    local jbad = {}
    for i, r in ipairs(jr) do
      local e = r.item
      if r.c.amount:GetText() ~= money(e.delta, true) then jbad[#jbad + 1] = i .. " amount" end
      if r.c.loc:GetText() ~= (e.zone or "") then jbad[#jbad + 1] = i .. " place" end
      if (r.c.loc:GetText() or ""):find("%d+%.%d, %d") then jbad[#jbad + 1] = i .. " coords inside the place" end
      if colorIs(r.c.amount, "red") or colorIs(r.c.detail, "red") then jbad[#jbad + 1] = i .. " red" end
      for k, cell in pairs(r.c) do if cell.GetText and cell:GetText() == "-" then jbad[#jbad + 1] = i .. " a dash in " .. k end end
      if (e.src == "unexplained" or e.src == "other") and not (e.ref and e.ref.drift) and (r.c.src:GetText() ~= GP.UNTRACED[e.src] or r.c.detail:GetText() ~= "") then jbad[#jbad + 1] = i .. " untraced wording" end
    end
    check("Gold Journal: signed amounts, Place and Coords apart, a missing place blank, nothing red, a row with no source says so once", #jbad == 0, table.concat(jbad, "; "):sub(1, 300))
    local noPlace
    for _, r in ipairs(jr) do if not r.item.zone then noPlace = r end end
    check("Gold Journal: a blank place says Not recorded on hover", noPlace ~= nil and tipOf(noPlace):find("Place: Not recorded", 1, true) ~= nil)
    tableChecks("Gold Journal", jt, c)
    -- search
    typeIn(c.search, "wu shen")
    jr = dataRows(jt)
    check("Gold search: the matching entries", #jr == 3 and jr[1].item.src == "training", #jr)
    typeIn(c.search, "zzzz")
    check("Gold search: no match says so, with Clear search", jt.stateFS and jt.stateFS:GetText() == 'No entry matches "zzzz". ' and jt.stateLink and jt.stateLink.shown ~= false, jt.stateFS and jt.stateFS:GetText())
    typeIn(c.search, "wu shen")
    view(c, "sources")
    check("Gold search: leaving Journal clears the search and hides the box", (c.search:GetText() or "") == "" and not P.visible(c.search) and c.view == "sources")
    view(c, "journal")
    eq("Gold search: back on Journal every entry is listed", #dataRows(jt), #ses.goldLog)
    -- sort
    jt.head.amount.scripts.OnClick(jt.head.amount); M.settle()
    jr = dataRows(jt)
    local sorted = true
    for i = 2, #jr do if (jr[i].item.delta - jr[i - 1].item.delta) * (c.st.sortAsc and 1 or -1) < 0 then sorted = false end end
    check("Gold sort: by Amount, without day rows", #jt.sections() == 0 and c.st.sortKey == "amount" and sorted)
    c.st.sortKey, c.st.sortAsc = "time", false; jt.setSort("time", false); c.refresh()
    -- tooltips
    jr = dataRows(jt)
    local trade, sale
    for _, r in ipairs(jr) do
      if r.item.src == "tradeSpent" then trade = r end
      if r.item.flag == "above vendor price" then sale = r end
    end
    local t = tipOf(trade)
    check("Gold tooltip: a trade lists both sides, the time and the balance", t:find("You gave: ", 1, true) and t:find("You got: Light Leather x20", 1, true) and t:find("balance after", 1, true), t)
    t = tipOf(sale)
    check("Gold tooltip: a sale above the vendor price says both prices and why it is worth a look", t:find("Vendor price ", 1, true) and t:find("Worth a look: sold for more than a vendor pays", 1, true), t)
    view(c, "sources")
    local srow, urow
    for _, r in ipairs(dataRows(c.tbl.sources)) do
      if r.item.key == "looted" then srow = r end
      if r.item.key == "unexplained" then urow = r end
    end
    t = tipOf(srow)
    check("Gold tooltip: a source lists its biggest contributors and what a click does", t:find("^Looted coin") and t:find("Defias", 1, true) and t:find("Click to see every entry.", 1, true), t)
    check("Gold tooltip: an untraced source says what it is, in the same words everywhere", urow and urow.c.src:GetText() == "Source not seen" and tipOf(urow):find(GP.UNTRACED_TIP, 1, true) ~= nil
      and tipOf(urow):find("away", 1, true) == nil)
    -- periods
    local prev = Gold.scope("previous").sessions[1]
    Gold.open(prev.id); M.settle()
    check("Gold periods: a session opened from another page lights no period and is named in the section header", c.st.scope == prev.id and c.period.value == nil
      and c.section.label:GetText() == UI.upper("Session of " .. UI.fmtStamp(prev.startedEpoch)), c.section.label:GetText())
    check("Gold periods: an ended session shows its numbers and its balance at its end", c.shownCards[1].label:GetText() == "BALANCE AT ITS END" and c.shownCards[2].value:GetText() == money(prev.gained, prev.gained > 0), c.shownCards[2].value:GetText())
    period(c, "all")
    check("Gold periods: All reads the lifetime ledger, is saved, and its header says ALL TIME", c.shownCards[2].value:GetText() == money(ns.char().gold.gained, true) and ns.DB.settings.goldPeriod == "all" and c.period.value == "all"
      and c.section.label:GetText() == "ALL TIME", c.section.label:GetText())
    period(c, "today")
    check("Gold periods: Today", c.st.scope == "today" and c.period.value == "today" and (c.section.label:GetText() == "TODAY" or c.section.label:GetText():find("^SINCE ") ~= nil), c.section.label:GetText())
    period(c, "session")
    -- Auction house: the view, and the old Loot > Auctions key opens it
    ns.UI.Open("Loot", "auctions"); M.settle()
    ns.char().goldShareSince = 1; c.refresh(); M.settle()
    local at = c.tbl.auctions
    check("Gold Auction house: the old Loot / Auctions key opens Gold on Auction house, all time", c.st.view == "auctions" and c.st.scope == "all" and c.viewSeg.value == "auctions" and P.visible(at.frame))
    -- (All time is the cards' word; the list says where its own rows start, in its header, once)
    check("Gold Auction house: all time says where its rows start, once, in the header", c.section.label:GetText():find("^AUCTIONS SINCE ") ~= nil
      and (not P.visible(c.section.meta) or c.section.meta:GetText() == "not every row is kept"), c.section.label:GetText() .. " / " .. tostring(c.section.meta:GetText()))
    local g = c.scopeData.ledger
    local ans = strip(c.answer.Text())
    check("Gold Auction house: the answer is Spent, received, net, from the ledger, and adds up", P.visible(c.answer) and c.answerData.spent == (g.auctions or 0) and c.answerData.received == (g.auctionSales or 0)
      and c.answerData.net == c.answerData.received - c.answerData.spent and ans:find("^Spent .+Received .+Net ") ~= nil and ans:find("Profit", 1, true) == nil and ans:find("Posted", 1, true) == nil, ans)
    check("Gold Auction house: its hover says what the three words count", tipOf(c.answer.pool[1]):find("Received is what auction mail paid out", 1, true) ~= nil)
    eq("Gold Auction house: columns (Player only while a third of the rows name one)", keys(at), c.auctionCols.player and "when,icon,item,result,player,price" or "when,icon,item,result,price")
    local results, abad = {}, {}
    for i, r in ipairs(dataRows(at)) do
      local it = r.item
      results[it.what] = true
      for k, cell in pairs(r.c) do if cell.GetText and cell:GetText() == "-" then abad[#abad + 1] = i .. " a dash in " .. k end end
      local want = it.what .. ((it.what == "Posted" and it.hours) and (", " .. UI.fmtDur(it.hours * 3600)) or "")
      if r.c.result:GetText() ~= want then abad[#abad + 1] = i .. " result " .. tostring(r.c.result:GetText()) end
      if r.c.price:GetText() ~= (it.price and money(it.price) or "") then abad[#abad + 1] = i .. " price" end
      if not it.item and r.c.item:GetText() ~= "" then abad[#abad + 1] = i .. " an item with no name shows text" end
    end
    check("Gold Auction house: sold, posted and bought rows show", results.Sold and results.Posted and results.Bought)
    check("Gold Auction house: Result folds the duration, a missing price or item is blank, never a dash", #abad == 0, table.concat(abad, "; "):sub(1, 300))
    check("Gold Auction house: day rows carry no entry count", #at.sections() >= 1 and at.sections()[1]:GetText():find("ENTR", 1, true) == nil, at.sections()[1]:GetText())
    tableChecks("Gold Auction house", at, c)
    -- a purchase and its delivery mails are one row; a delivery with no purchase is Won with no price
    do
      local sid, now = ns.DB.active, GetServerTime()
      local keep = ns.DB.loot.ah
      ns.DB.loot.ah = { posted = {}, sold = {}, returned = {}, bought = {
        { s = sid, t = now - 60, item = "Mageweave Cloth", id = 4338, count = 120, price = 53300, kind = "commodity" },
        { s = sid, t = now - 50, item = "Mageweave Cloth", id = 4338, count = 20, kind = "mail" }, { s = sid, t = now - 50, item = "Mageweave Cloth", id = 4338, count = 20, kind = "mail" },
        { s = sid, t = now - 49, item = "Mageweave Cloth", id = 4338, count = 20, kind = "mail" }, { s = sid, t = now - 49, item = "Mageweave Cloth", id = 4338, count = 20, kind = "mail" },
        { s = sid, t = now - 48, item = "Mageweave Cloth", id = 4338, count = 20, kind = "mail" }, { s = sid, t = now - 48, item = "Mageweave Cloth", id = 4338, count = 20, kind = "mail" },
        { s = sid, t = now - 40, item = "Wool Cloth", id = 2592, count = 20, kind = "mail" },
        { s = sid, t = now - 30, auctionId = 7, price = 16046, count = 1, kind = "item", item = "Silk Cloth", id = 4306 },
      } }
      Gold.open("session", "auctions"); M.settle()
      local rows = dataRows(at)
      local texts = {}
      for i, r in ipairs(rows) do texts[i] = strip(r.c.item:GetText()) .. "|" .. r.c.result:GetText() .. "|" .. r.c.price:GetText() end
      eq("Gold Auction house: one purchase is one row, a lone delivery is Collected with a blank price, a guessed name is blank",
        table.concat(texts, " ; "), ("|Bought|%s ; Wool Cloth x20|Collected| ; Mageweave Cloth x120|Bought|%s"):format(money(16046), money(53300)))
      check("Gold Auction house: the blank item says Not recorded on hover, the Collected row that its price is not", tipOf(rows[1]):find("Item: Not recorded", 1, true) ~= nil and tipOf(rows[2]):find("Price: Not recorded", 1, true) ~= nil)
      eq("Gold Auction house: 2 purchases with a price, 1 delivery with none", c.auctionSum.bought .. "/" .. c.auctionSum.won, "2/1")
      ns.DB.loot.ah = keep
    end
    Gold.open("session"); M.settle()
    -- a long journal lists Gold.MAX_ROWS entries and says so
    do
      local keep = Gold.MAX_ROWS
      Gold.MAX_ROWS = 20
      Gold.open("session", "journal"); M.settle()
      local n = #ns.Recorder.current().goldLog
      check("Gold long journal: the newest entries are listed, the header says how many in all", #dataRows(c.tbl.journal) == 20 and c.section.meta:GetText() == ("newest 20 of %d"):format(n), c.section.meta:GetText())
      Gold.MAX_ROWS = keep
    end
    -- a journal that lost rows: the header says so, once
    do
      local row = table.remove(ses.goldLog, 3)
      Gold.open("session", "journal"); M.settle()
      check("Gold partial journal: the header says not every entry is kept", c.journalPartial == true and c.section.meta:GetText() == "not every entry is kept", c.section.meta:GetText())
      table.insert(ses.goldLog, 3, row)
      Gold.open("session", "journal"); M.settle()
      check("Gold whole journal: no remark", c.journalPartial == false and not P.visible(c.section.meta))
    end
    -- a journal that lost rows AND is cut at its newest rows: the header says both, the cut never takes the place of
    -- the coverage; and the remark is never drawn under the search box (the founder's Week at 900 px read "newes")
    do
      local keep = Gold.MAX_ROWS
      Gold.MAX_ROWS = 20
      local row = table.remove(ses.goldLog, 3)
      Gold.open("session", "journal"); M.settle()
      eq("Gold partial long journal: the header says the cut and the coverage", c.section.meta:GetText(), ("newest 20 of %d, not every entry is kept"):format(c.journalCount))
      check("Gold partial long journal: the reason is on the remark's hover", c.section.metaHit and P.visible(c.section.metaHit) and tipOf(c.section.metaHit):find("desktop app", 1, true) ~= nil)
      local win0 = ns.DB.settings.winSize and { ns.DB.settings.winSize.w, ns.DB.settings.winSize.h } or { 900, 580 }
      local function clash(a, b) return a.l < b.l + b.w - 0.5 and b.l < a.l + a.w - 0.5 and a.t < b.t + b.h - 0.5 and b.t < a.t + a.h - 0.5 end
      for _, size in ipairs({ { 900, 580 }, { 1104, 697 }, { 1600, 1000 } }) do
        ns.UI.SetWindowSize(size[1], size[2]); M.settle()
        local mb, sb, vb, lb, tb = P.box(c.section.meta), P.box(c.search), P.box(c.viewSeg), P.box(c.section.label), P.box(c.tbl.journal.frame)
        local tag = ("Gold partial long journal %dx%d"):format(size[1], size[2])
        check(tag .. ": the remark is whole, clear of the search box, the view control and the label", P.visible(c.section.meta) and not c.section.meta:IsTruncated() and not clash(mb, sb) and not clash(mb, vb) and not clash(mb, lb),
          ("meta %d..%d at %d, search from %d"):format(mb.l, mb.l + mb.w, mb.t, sb.l))
        check(tag .. ": and above the table", mb.t + mb.h <= tb.t + 0.5, ("%s %s"):format(mb.t + mb.h, tb.t))
        if size[1] == 900 then check(tag .. ": with no room beside the controls it has a line of its own", c.metaBelow == true and mb.t >= lb.t + lb.h - 0.5) end
        if size[1] == 1600 then check(tag .. ": with room it follows the label on the header's line", c.metaBelow == nil and math.abs((mb.t + mb.h / 2) - (lb.t + lb.h / 2)) < 2) end
      end
      ns.UI.SetWindowSize(win0[1], win0[2]); M.settle()
      table.insert(ses.goldLog, 3, row)
      Gold.MAX_ROWS = keep
      Gold.open("session", "journal"); M.settle()
      check("Gold whole journal: the line under the header is gone with its remark", c.metaBelow == nil and not P.visible(c.section.meta))
    end
    -- All time, Journal: ALL TIME is the cards' word; the list's header says where its own entries start
    do
      Gold.open("all", "journal"); M.settle()
      local first = c.entries[1]
      check("Gold all journal: the header says where the kept entries start", first ~= nil and c.section.label:GetText() == ns.UI.upper("Entries since " .. ns.UI.fmtSince(first.t)), c.section.label:GetText())
      Gold.open("session", "journal"); M.settle()
    end
    -- the Auction house answer: each dot is a glyph of its own, centred in the gap between two figures and on their
    -- middle line (it sat at the top of the line, glued to the next word)
    do
      Gold.open("all", "auctions"); M.settle()
      if P.visible(c.answer) and (c.answer.shownN or 0) >= 2 then
        local bad = {}
        for i = 2, c.answer.shownN do
          local sep, a, b = c.answer.seps[i], P.box(c.answer.pool[i - 1]), P.box(c.answer.pool[i])
          local sbx = P.box(sep)
          if sep:GetText() ~= "\194\183" then bad[#bad + 1] = i .. " text" end
          if math.abs(sbx.l - (a.l + a.w)) > 0.5 or math.abs((sbx.l + sbx.w) - b.l) > 0.5 then bad[#bad + 1] = i .. " not between the two figures" end
          if math.abs((sbx.t + sbx.h / 2) - (a.t + a.h / 2)) > 1 then bad[#bad + 1] = i .. " off the middle line" end
          if sep._justify ~= "CENTER" then bad[#bad + 1] = i .. " not centred" end
        end
        check("Gold Auction house: the dots of the answer line are centred between the figures", #bad == 0, table.concat(bad, "; "))
      else check("Gold Auction house: the answer line shows for the dot check", false) end
      Gold.open("session"); M.settle()
    end
    -- an empty period
    ses.goldLog, ses.gold, ses.gained, ses.spent, ses.trades = {}, {}, 0, 0, {}
    Gold.open("session"); M.settle()
    check("Gold empty: the one sentence", c.tbl.sources.stateFS and c.tbl.sources.stateFS:GetText() == "No gold has moved in this period." and GP.EMPTY == "No gold has moved in this period.", c.tbl.sources.stateFS and c.tbl.sources.stateFS:GetText())
    check("Gold empty: the cards read zero with no meta about sources", c.shownCards[2].value:GetText() == money(0) and c.shownCards[2].meta:GetText() == "" and c.shownCards[3].meta:GetText() == "", c.shownCards[2].value:GetText() .. "|" .. c.shownCards[2].meta:GetText() .. "|" .. c.shownCards[3].meta:GetText())
    ns.DB.loot.ah = { posted = {}, sold = {}, returned = {}, bought = {} }
    view(c, "auctions")
    check("Gold empty: Auction house has no answer line and says so", not P.visible(c.answer) and c.tbl.auctions.stateFS:GetText() == GP.NO_AUCTION, c.tbl.auctions.stateFS:GetText())
    view(c, "journal")
    check("Gold empty: Journal says the same sentence", c.tbl.journal.stateFS:GetText() == GP.EMPTY)
    local listening = {}
    for _, f in ipairs(P.descendants(c)) do for ev in pairs(rawget(f, "events") or {}) do listening[#listening + 1] = ev end end
    check("Gold: the pane registers no events (it refreshes when it is shown)", #listening == 0, table.concat(listening, ","))
  end

  -- ── Home / Sessions: the gold band ──────────────────────────────────────────────────────────────────────────
  for _, size in ipairs({ { 900, 580 }, { 1250, 760 }, { 1600, 1000 } }) do
    for _, data in ipairs({ "gold", "goldlong" }) do
      local tag = ("Sessions gold %dx%d %s"):format(size[1], size[2], data)
      local c = P.open("home", "sessions", size[1], size[2], data)
      ns.UI.Open("Home", "sessions"); M.settle()
      local band, cb = c.goldBand, P.box(c)
      local bb = P.box(band)
      local ses = ns.Recorder.current()
      -- (A17: the gold block flows S5 under the list, its section header names the session as the list does)
      local under = c.shortLine:IsShown() and (P.box(c.shortLine).t + UI.H.DAY_ROW) or (P.box(c.tbl.frame).t + c.tbl.height)
      check(tag .. ": the gold block flows S5 under the list", P.visible(band) and near(P.box(c.goldHead).t, under + UI.S.S5, 1), P.box(c.goldHead).t .. " vs " .. under)
      check(tag .. ": the block opens on the running session: When, length, net and pace in coins", c.goldHead.label.text:find(UI.fmtWhen(ses.startedEpoch):upper(), 1, true) ~= nil and band.title.text:find("net " .. UI.money(ses.gained - ses.spent, true), 1, true) and band.title.text:find("per hour$") ~= nil, c.goldHead.label.text .. " | " .. band.title.text)
      local bad = {}
      local lastR
      for i, b in ipairs(band.blocks) do
       if b.shown ~= false then
        local x = P.box(b)
        if x.l < bb.l or x.l + x.w > bb.l + bb.w or x.t + x.h > bb.t + bb.h + 0.5 then bad[#bad + 1] = "block " .. i .. " outside the band" end
        if lastR and x.l < lastR + UI.SP.L - 0.5 then bad[#bad + 1] = "block " .. i .. " too close" end
        lastR = x.l + x.w
        for _, fs in ipairs(b.lines) do
          local fb = P.box(fs)
          if (fs.text or "") ~= "" and (fb.t + fb.h > bb.t + bb.h - 4) then bad[#bad + 1] = "line past the band: " .. fs.text end
          if (fs.text or "") ~= "" and fs:IsTruncated() then bad[#bad + 1] = "cut: " .. fs.text end
        end
       end
      end
      -- under WIDE the BEST EARNERS block gives its room to the other three (no line cut at 900)
      check(tag .. ": BEST EARNERS shows at WIDE only", (band.blocks[2].shown ~= false) == UI.G.isWide(UI.G.winW()))
      local tb = P.box(band.title)
      if tb.l + tb.w > bb.l + bb.w + 0.5 then bad[#bad + 1] = "title past the panel" end
      check(tag .. ": the blocks side by side inside the panel, S5 apart", #bad == 0, table.concat(bad, "; "))
      eq(tag .. ": block heads", band.blocks[1].head.text .. "|" .. band.blocks[2].head.text .. "|" .. band.blocks[3].head.text .. "|" .. band.blocks[4].head.text, "TOP SOURCES|BEST EARNERS|BIGGEST SINKS|NOTES")
      check(tag .. ": top source, best quest, biggest sink and the strangers are named",
        band.blocks[1].lines[1].text:find("^Trades received  ") and band.blocks[2].lines[1].text:find("^Quest: The Defias Brotherhood") and band.blocks[3].lines[1].text:find("^Auction house  ")
        and band.blocks[4].lines[1].text:find("^Traded with: Xzqtgold") and band.blocks[4].lines[2].text:find("^Not traced: ") and band.blocks[4].lines[3].text:find("^Above vendor price: 1 sale"), band.blocks[4].lines[1].text)
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
    check("Sessions gold: a click on a row shows that session's gold", c.goldHead.label.text:find(UI.fmtWhen(prevRow.item.startedEpoch):upper(), 1, true) ~= nil and band.blocks[2].lines[1].text:find("^Quest: The Jasperlode Mine") ~= nil and band.blocks[3].lines[1].text:find("^Training  12" .. UI.NBSP .. "|T[^|]*SilverIcon") ~= nil, band.blocks[3].lines[1].text)
    check("Sessions gold: the shown row is the selected one", c.tbl.selected == prevRow.item)
    click(c.goldHead.link)
    local gold
    for _, tab in ipairs(P.T.tabs) do if tab.name == "Loot" then gold = tab.paneByKey.gold.content end end
    check("Sessions gold: the button opens that session's journal in the Gold pane", P.visible(gold) and gold.st.scope == prevRow.item.id and gold.st.view == "journal" and gold.period.value == nil and #dataRows(gold.tbl.journal) == #prevRow.item.goldLog, gold.st.scope)
    -- a session from before 0.9.40
    local ses = ns.Recorder.current()
    ses.goldLog, ses.trades, ses.goldLogDropped = nil, nil, nil
    ns.UI.Open("Home", "sessions"); M.settle()
    click(shown(c.tbl.rows)[1])
    check("Sessions gold: a session without a journal keeps its top sources and says why the rest is empty", band.blocks[1].lines[1].text:find("^Trades received") ~= nil and band.blocks[2].lines[1].text == "Recorded before addon 0.9.40" and band.blocks[4].lines[1].text:find("^Changed while away: %+42") ~= nil, band.blocks[2].lines[1].text)
  end
  -- ── day periods: the day rows, where the history starts, and when Sources is not offered ────────────────────
  local DAY = 86400
  for _, size in ipairs(SIZES) do
    local tag = ("Gold days %dx%d"):format(size[1], size[2])
    local c = open(size[1], size[2], "gold", "today")
    local me = ns.char()
    local base = Gold.baseStored()
    local now = GetServerTime()
    local kT = Gold.dayKey(now, base)
    local today = me.goldDays[kT]
    -- Today: the day row's numbers on the cards
    check(tag .. ": Today is selected and reads the day row", c.period.value == "today" and today ~= nil and c.shownCards[2].value:GetText() == money(today.g, today.g > 0)
      and c.shownCards[3].value:GetText() == (today.s > 0 and money(-today.s, true) or money(0)) and c.shownCards[1].label:GetText() == "BALANCE" and c.shownCards[1].value:GetText() == money(me.gold.balance), c.shownCards[2].value:GetText())
    local src = c.sourceData
    local okSrc = src.inTotal == today.g and src.outTotal == today.s
    for _, r in ipairs(src.rows) do if r.dir ~= 0 and r.amount ~= (today[r.key] or 0) then okSrc = false end end
    check(tag .. ": the sources of Today are the day row's keys", okSrc and #src.rows >= 10)
    -- the Journal's day rows are gold days and carry the day's net from the day row
    Gold.open("today", "journal"); M.settle()
    local jt = c.tbl.journal
    local head = jt.sections()[1]:GetText()
    eq(tag .. ": a Journal day row carries the day's net", head, UI.upper(GP.dayHead(kT, base, now, true)))
    check(tag .. ": it is the day row's earned minus spent", head:find(UI.upper(money(today.g - today.s, true)), 1, true) ~= nil and head:find("^TODAY") ~= nil, head)
    typeIn(c.search, "a")
    check(tag .. ": while a search narrows the rows the day row shows no net", #jt.sections() >= 1 and jt.sections()[1]:GetText():find(UI.upper(money(today.g - today.s, true)), 1, true) == nil, jt.sections()[1]:GetText())
    typeIn(c.search, "")
    Gold.open("session", "journal"); M.settle()
    check(tag .. ": a session's Journal shows no day net (NET is the session's)", jt.sections()[1]:GetText():find(UI.upper(money(today.g - today.s, true)), 1, true) == nil, jt.sections()[1]:GetText())
    -- a first day that starts mid-day says from when
    local keepSince = me.goldSince
    local d0 = Gold.keyStart(kT, base)
    me.goldSince = d0 + 60
    check(tag .. ": a day the history starts in says from when", GP.dayHead(kT, base, now, false) == "TODAY, FROM " .. UI.fmtClock(d0 + 60), GP.dayHead(kT, base, now, false))
    -- the history starts inside the period: the header says the real range, not the period word
    Gold.open("today"); M.settle()
    eq(tag .. ": Today counted from where the history starts", c.section.label:GetText(), UI.upper("Since " .. UI.fmtStamp(d0 + 60)))
    Gold.open("week"); M.settle()
    eq(tag .. ": Week counted from where the history starts", c.section.label:GetText(), UI.upper("Since " .. UI.fmtStamp(d0 + 60)))
    check(tag .. ": the header's text does not run into the view control", P.box(c.section.label).l + P.box(c.section.label).w < P.box(c.viewSeg).l and not c.section.label:IsTruncated())
    me.goldSince = d0 - 30 * DAY
    Gold.open("week"); M.settle()
    eq(tag .. ": a week inside the history is WEEK", c.section.label:GetText(), "WEEK")
    Gold.open("today"); M.settle()
    eq(tag .. ": a day inside the history is TODAY", c.section.label:GetText(), "TODAY")
    me.goldSince = keepSince
    -- Sources is not offered for a period with dungeon time from before the coin capture of 0.9.52
    me.goldRuns = { { inst = "The Deadmines", t = now - 1800, secs = 1200, looted = 365, quests = 0 } }
    me.goldShareSince = now - 60
    Gold.open("today"); M.settle()
    local sb = c.viewSeg.segs[1]
    check(tag .. ": a period with a dungeon run from before the fix opens on Journal", c.srcOff ~= nil and c.view == "journal" and c.viewSeg.value == "journal" and P.visible(c.tbl.journal.frame) and not P.visible(c.tbl.sources.frame), c.view)
    check(tag .. ": the Sources button is greyed and says why on hover, with the date", colorIs(sb.text, "fgFaint") and tipOf(sb):find(("Sources are not reliable for dungeon time before %s."):format(UI.fmtSince(now - 60)), 1, true) ~= nil, tipOf(sb))
    click(sb)
    check(tag .. ": a click on it changes nothing", c.view == "journal" and c.viewSeg.value == "journal" and colorIs(sb.text, "fgFaint"))
    view(c, "auctions")
    check(tag .. ": Auction house is still offered", c.view == "auctions")
    view(c, "sources")
    -- the same run after the fix: Sources as usual
    me.goldShareSince = now - 3600
    Gold.open("today"); M.settle()
    check(tag .. ": a run from after the fix leaves Sources on, with no hover", c.srcOff == nil and c.view == "sources" and sb.ebTip == nil and not colorIs(sb.text, "fgFaint"))
    -- a period the run is not in keeps Sources
    me.goldShareSince = now - 60
    me.goldRuns[1].t = now - 10 * DAY
    Gold.open("today"); M.settle()
    check(tag .. ": a run outside the period does not take Sources away", c.srcOff == nil and c.view == "sources")
    Gold.open("all"); M.settle()
    check(tag .. ": All time holds it, so it opens on Journal", c.srcOff ~= nil and c.view == "journal")
    me.goldRuns = nil
  end
  -- the first run: no day row yet, one character
  do
    local c = open(900, 580, "gold", "today")
    local me = ns.char()
    me.goldDays, me.goldSince = nil, nil
    for guid in pairs(ns.DB.characters) do if guid ~= ns.charGuid() then ns.DB.characters[guid] = nil end end
    Gold.open("today"); M.settle()
    check("Gold first run: Today with no day row shows zeros, the balance and the empty sentence", c.shownCards[2].value:GetText() == money(0) and c.shownCards[4].value:GetText() == money(0, true)
      and c.shownCards[1].value:GetText() == money(me.gold.balance) and c.tbl.sources.stateFS:GetText() == GP.EMPTY, c.shownCards[2].value:GetText())
    check("Gold first run: with one character BALANCE has no meta", c.shownCards[1].meta:GetText() == "", c.shownCards[1].meta:GetText())
    for _, key in ipairs({ "week", "yesterday", "month", "last30", "all" }) do
      for _, v in ipairs(Gold.VIEWS) do Gold.open(key, v[1]); M.settle() end
    end
    check("Gold first run: every period and view opens on an empty history without an error", #UI.paneErrors() == 0, table.concat(UI.paneErrors(), " || "))
    -- the pane follows the purse while it is open: one refresh 0.1 s after a change
    Gold.open("today"); M.settle()
    local before = c.shownCards[2].value:GetText()
    M.money = M.money + 1234; M.fire("PLAYER_MONEY")
    check("Gold live: a change is not drawn in the same call (coalesced)", c.shownCards[2].value:GetText() == before)
    M.runTimers(); M.settle()
    check("Gold live: the open pane shows the change after its 0.1 s refresh", c.shownCards[2].value:GetText() == money(1234, true) and me.goldDays ~= nil, c.shownCards[2].value:GetText())
  end
  ns.Recorder.current = savedCurrent
  check("Gold: no errors from the panes' resize or events", #UI.paneErrors() == 0, table.concat(UI.paneErrors(), " || "))
end
