-- Pane tests: gold, one model on every surface (everbuff-wow-addon #38). Everbuff/Economy.lua holds the model
-- (ns.Gold) and LOOT > Gold (docs/UX_OVERHAUL.md 4.9); Home / Sessions shows a session's gold band. Played on
-- tests/play_gold.lua ("gold": two evenings with a name behind every row).
--   model     every journal row parsed, the balance chain intact, each source summing to the session ledger, the
--             quest, item, merchant, mob and player named, Location and Coordinates only from the row's own record
--   Gold pane the period control (Session, Today, Week, All time) and More; the answer line; 4 cards, 5 at WIDE; the
--             untraced line; the list under its section header with "Break down by" and search: Sources (EARNED,
--             SPENT, MOVED groups, a row opens its source page), Journal (day rows, "N to review"), Days,
--             Characters (the scope filter in place of search), Zones, Runs, Auction house
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
    pick(c.breakdown, "Journal"); Gold.open("all", "journal"); Gold.open("today", "days"); Gold.open("week", "chars")
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
      local wide, mainW = G.isWide(winW), G.mainW(winW)
      -- the control row: Session, Today, Week, All time, then More
      local segs = {}
      for i, b in ipairs(c.period.segs) do segs[i] = b.text:GetText() end
      eq(tag .. ": the period control", table.concat(segs, ","), "Session,Today,Week,All time")
      local pb, mb = P.box(c.period), P.box(c.more)
      check(tag .. ": the period control, then More, at the control row's right, S2 apart", near(pb.l + pb.w + UI.S.S2, mb.l) and near(pb.t, mb.t) and mb.l + mb.w <= P.box(_G.EverbuffFrame).l + winW - G.BOX_R_INSET + 0.5,
        ("%s %s %s"):format(pb.l + pb.w, mb.l, mb.l + mb.w))
      check(tag .. ": Session is selected, More is quiet", c.period.value == "session" and not c.more.ebActive and c.more.text:GetText() == "More")
      -- the answer line
      local sc = Gold.scope("session")
      local card = Gold.netCard(sc.ledger, Gold.scopeEntries(sc))
      local line = c.summary.Text()
      check(tag .. ": the answer line: the net this session, what it mostly came from, the rate of play", line:find(money(card.net, true) .. " this session, mostly ", 1, true) == 1
        and line:find(" per hour of play", 1, true) ~= nil, line)
      -- the cards: 4, 5 at WIDE, as wide as the column, S3 apart, values in fg
      local cards = c.shownCards
      eq(tag .. ": the cards", cardLabels(cards), wide and "BALANCE,EARNED,SPENT,NET,PER HOUR" or "BALANCE,EARNED,SPENT,NET")
      check(tag .. ": the card row of this width shows, the other is hidden", P.visible(wide and c.cards5 or c.cards4) and not P.visible(wide and c.cards4 or c.cards5))
      local cbad = {}
      local colB = P.box(c.col)
      local first, last = P.box(cards[1]), P.box(cards[#cards])
      if not near(first.l, colB.l) or not near(last.l + last.w, colB.l + mainW) then cbad[#cbad + 1] = "the row is not the column's width" end
      for i = 2, #cards do
        local a, b = P.box(cards[i - 1]), P.box(cards[i])
        if not near(a.l + a.w + UI.S.S3, b.l) or not near(a.h, UI.H.STAT) then cbad[#cbad + 1] = "gap or height " .. i end
      end
      for i, cd in ipairs(cards) do
        if cd.value:IsTruncated() then cbad[#cbad + 1] = "value cut " .. i end
        if not colorIs(cd.value, "fg") then cbad[#cbad + 1] = "value not fg " .. i end
      end
      check(tag .. ": the cards fill the column, 12 px apart, 80 high, values in full and in fg", #cbad == 0, table.concat(cbad, "; "))
      eq(tag .. ": BALANCE", cards[1].value:GetText(), money(ns.char().gold.balance))
      eq(tag .. ": EARNED / SPENT", cards[2].value:GetText() .. " / " .. cards[3].value:GetText(), money(ses.gained, true) .. " / " .. money(-ses.spent, true))
      eq(tag .. ": NET", cards[4].value:GetText(), money(card.net, true))
      check(tag .. ": the cards' meta lines: all characters, entries, per hour", cards[1].meta:GetText():find("^all characters ") ~= nil and cards[2].meta:GetText():find(" entries$") ~= nil
        and cards[4].meta:GetText():find(" per hour$") ~= nil, cards[1].meta:GetText())
      if wide then check(tag .. ": PER HOUR names its stretch of play", cards[5].meta:GetText():find("^over ") ~= nil and cards[5].value:GetText() == money(c.rate, true), cards[5].meta:GetText()) end
      -- the untraced line: under the cards, fgMuted, never red
      local ub = P.box(c.untraced)
      check(tag .. ": the untraced line sits S3 under the cards in fgMuted", P.visible(c.untraced) and c.untraced:GetText():find("^While you were away %(in%): ") ~= nil and colorIs(c.untraced, "fgMuted")
        and near(ub.t, first.t + first.h + UI.S.S3), c.untraced:GetText())
      check(tag .. ": its hover explains it", tipOf(c.untracedHit):find(GP.UNTRACED_TIP, 1, true) ~= nil)
      -- the list: SOURCES, Break down by and search at the header's right
      local hb, bb, sb = P.box(c.section), P.box(c.breakdown), P.box(c.search)
      check(tag .. ": the section header SOURCES, then Break down by and the 176 px search at its right", c.section.label:GetText() == "SOURCES" and c.breakdown.text:GetText() == "Break down by: Sources"
        and not c.breakdown.ebActive and near(sb.w, UI.SEARCH_W) and near(sb.l + sb.w, hb.l + hb.w) and near(bb.l + bb.w + UI.S.S2, sb.l) and hb.t >= ub.t + ub.h, ("%s %s %s"):format(bb.l + bb.w, sb.l, hb.l + hb.w))
      local tbl = c.tbl.sources
      local others = 0
      for k, t in pairs(c.tbl) do if k ~= "sources" and P.visible(t.frame) then others = others + 1 end end
      check(tag .. ": Sources shows, every other table is hidden", P.visible(tbl.frame) and others == 0 and not P.visible(c.dayStrip))
      local secs = {}
      for i, s in ipairs(tbl.sections()) do secs[i] = s:GetText() end
      eq(tag .. ": the groups: EARNED, SPENT, MOVED", table.concat(secs, " | "), UI.upper("Earned " .. money(ses.gained, true) .. " | Spent " .. money(-ses.spent, true) .. " | Moved between characters and bank " .. money(0)))
      eq(tag .. ": Sources columns", keys(tbl), "src,what,whatAmt,n,share,amount")
      local rows = dataRows(tbl)
      local sbad = {}
      for _, r in ipairs(rows) do
        local it = r.item
        if r.c.src:GetText() ~= GP.srcLabel(it.key) then sbad[#sbad + 1] = it.key .. " label" end
        if r.c.amount:GetText() ~= money(it.dir * it.amount, true) then sbad[#sbad + 1] = it.key .. " amount" end
        if GP.UNTRACED[it.key] and not colorIs(r.c.src, "fgSubtle") then sbad[#sbad + 1] = it.key .. " not subtle" end
        if colorIs(r.c.amount, "red") or colorIs(r.c.amount, "green") then sbad[#sbad + 1] = it.key .. " coloured" end
      end
      check(tag .. ": source rows: the label, the signed amount, untraced ones in fgSubtle, nothing red or green", #sbad == 0 and #rows >= 14, table.concat(sbad, "; "))
      local mcut = {}
      for _, r in ipairs(rows) do if r.c.whatAmt:IsTruncated() then mcut[#mcut + 1] = r.item.key end end
      check(tag .. ": the biggest single's amount has a cell of its own and is never cut", #mcut == 0, table.concat(mcut, ","))
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
    end
  end

  -- ── the breakdowns, search, review, tooltips, periods ───────────────────────────────────────────────────────
  do
    local c = open(1250, 760)
    local ses = ns.Recorder.current()
    check("Gold breakdowns: the menu offers every breakdown", table.concat(offered(c.breakdown), ",") == "Sources,Journal,Days,Characters,Zones,Runs,Auction house")
    -- Journal
    check("Gold Journal: picked from Break down by", pick(c.breakdown, "Journal") and c.st.view == "journal" and c.section.label:GetText() == "JOURNAL"
      and c.breakdown.text:GetText() == "Break down by: Journal" and c.breakdown.ebActive)
    local jt = c.tbl.journal
    local jr = dataRows(jt)
    eq("Gold Journal: every entry of the session", #jr, #ses.goldLog)
    check("Gold Journal: newest first, a day row over each day", jr[1].item.t >= jr[#jr].item.t and #jt.sections() >= 1 and jt.sections()[1]:GetText():find(" ENTRIES$") ~= nil)
    local jbad = {}
    for i, r in ipairs(jr) do
      local e = r.item
      if r.c.amount:GetText() ~= money(e.delta, true) then jbad[#jbad + 1] = i .. " amount" end
      if r.c.loc:GetText() ~= (e.zone or "-") then jbad[#jbad + 1] = i .. " place" end
      if (r.c.loc:GetText() or ""):find("%d+%.%d, %d") then jbad[#jbad + 1] = i .. " coords inside the place" end
      if colorIs(r.c.amount, "red") or colorIs(r.c.detail, "red") then jbad[#jbad + 1] = i .. " red" end
    end
    check("Gold Journal: signed amounts, Place and Coords apart, nothing red", #jbad == 0, table.concat(jbad, "; "):sub(1, 300))
    tableChecks("Gold Journal", jt, c)
    -- the review button
    check("Gold Journal: the ghost button counts the entries worth a look", P.visible(c.reviewBtn) and c.reviewBtn.text:GetText() == "6 to review" and c.flagged == 6, c.reviewBtn.text:GetText())
    local rb, sb = P.box(c.reviewBtn), P.box(c.search)
    check("Gold Journal: it sits before search", near(rb.l + rb.w + UI.S.S2, sb.l))
    check("Gold Journal: its tooltip gives each reason in one line", tipOf(c.reviewBtn):find("a player you do not know", 1, true) ~= nil)
    click(c.reviewBtn)
    jr = dataRows(jt)
    local allFlag = true
    for _, r in ipairs(jr) do if not r.item.flag then allFlag = false end end
    check("Gold Journal: a click lists the six entries worth a look", allFlag and #jr == 6 and c.reviewBtn.text:GetText() == "Show every entry", #jr)
    click(c.reviewBtn)
    eq("Gold Journal: a second click lists every entry again", #dataRows(jt), #ses.goldLog)
    -- search
    typeIn(c.search, "wu shen")
    jr = dataRows(jt)
    check("Gold search: the matching entries", #jr == 3 and jr[1].item.src == "training", #jr)
    typeIn(c.search, "zzzz")
    check("Gold search: no match says so, with Clear search", jt.stateFS and jt.stateFS:GetText() == 'No entry matches "zzzz". ' and jt.stateLink and jt.stateLink.shown ~= false, jt.stateFS and jt.stateFS:GetText())
    typeIn(c.search, "")
    pick(c.breakdown, "Sources")
    typeIn(c.search, "wu shen")
    check("Gold search: typing on Sources opens the Journal on the matches", c.st.view == "journal" and #dataRows(jt) == 3)
    typeIn(c.search, "")
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
    pick(c.breakdown, "Sources")
    local srow, urow
    for _, r in ipairs(dataRows(c.tbl.sources)) do
      if r.item.key == "looted" then srow = r end
      if r.item.key == "unexplained" then urow = r end
    end
    t = tipOf(srow)
    check("Gold tooltip: a source lists its biggest contributors and what a click does", t:find("^Looted coin") and t:find("Defias", 1, true) and t:find("Click to see every entry.", 1, true), t)
    check("Gold tooltip: an untraced source says what it is, in the same words everywhere", urow and urow.c.src:GetText() == "While you were away (in)" and tipOf(urow):find(GP.UNTRACED_TIP, 1, true) ~= nil)
    -- periods
    local prev = Gold.scope("previous").sessions[1]
    local label = "Session " .. UI.fmtWhen(prev.startedEpoch)
    local more = offered(c.more)
    check("Gold periods: More offers Yesterday, This month, Last 30 days, then the earlier sessions", more[1] == "Yesterday" and more[2] == "This month" and more[3] == "Last 30 days"
      and more[4] == label and #more <= 3 + Gold.MORE_SESSIONS, table.concat(more, ","))
    check("Gold periods: an earlier session is picked from More", pick(c.more, label))
    check("Gold periods: the pick shows on More, active with its clear glyph; the period control shows none", c.st.scope == prev.id and c.more.ebActive and c.more.clear.shown ~= false
      and c.period.value == nil and c.more.text:GetText() == UI.fmtWhen(prev.startedEpoch), c.more.text:GetText())
    check("Gold periods: an ended session shows its numbers and its balance at its end", c.shownCards[1].label:GetText() == "BALANCE AT ITS END" and c.shownCards[2].value:GetText() == money(prev.gained, prev.gained > 0), c.shownCards[2].value:GetText())
    click(c.more.clear)
    check("Gold periods: the clear glyph goes back to Session", c.st.scope == "session" and c.period.value == "session" and not c.more.ebActive)
    period(c, "all")
    check("Gold periods: All time reads the lifetime ledger and is saved", c.shownCards[2].value:GetText() == money(ns.char().gold.gained, true) and ns.DB.settings.goldPeriod == "all" and c.period.value == "all")
    period(c, "today")
    check("Gold periods: Today", c.st.scope == "today" and c.period.value == "today" and c.summary.Text():find(" today", 1, true) ~= nil, c.summary.Text())
    period(c, "session")
    -- Auction house: the breakdown, and the old Loot > Auctions key opens it
    ns.UI.Open("Loot", "auctions"); M.settle()
    check("Gold Auction house: the old Loot / Auctions key opens Gold on Auction house, all time", c.st.view == "auctions" and c.st.scope == "all" and c.section.label:GetText() == "AUCTION HOUSE" and P.visible(c.tbl.auctions.frame))
    local _, a = GP.auctions(c.scopeData)
    local ans = c.summary.Text()
    check("Gold Auction house: the answer line counts posted, sold, the house cut, the profit and the expired", ans:find("^Posted " .. a.posted) and ans:find("Sold " .. a.sold .. " for ", 1, true) and ans:find("House cut ", 1, true)
      and ans:find("Profit ", 1, true) and ans:find("Expired " .. a.expired, 1, true), ans)
    eq("Gold Auction house: columns", keys(c.tbl.auctions), "when,item,result,buyer,dur,price")
    local results, mailItem = {}, nil
    for _, r in ipairs(dataRows(c.tbl.auctions)) do results[r.c.result:GetText()] = true; if r.c.item:GetText() == "Item from auction mail" then mailItem = r end end
    check("Gold Auction house: sold, posted and bought rows show", results.Sold and results.Posted and results.Bought)
    if mailItem then check("Gold Auction house: a missing item reads Item from auction mail, muted, and says why", colorIs(mailItem.c.item, "fgMuted") and tipOf(mailItem):find("The item name was not in the mail.", 1, true) ~= nil) end
    tableChecks("Gold Auction house", c.tbl.auctions, c)
    -- Zones and Runs
    pick(c.breakdown, "Zones")
    local zr = dataRows(c.tbl.zones)
    check("Gold Zones: the total first, then the places", c.st.view == "zones" and P.visible(c.tbl.zones.frame) and (#zr == 0 or zr[1].item.total == true))
    pick(c.breakdown, "Runs")
    check("Gold Runs: shows", c.st.view == "runs" and P.visible(c.tbl.runs.frame))
    pick(c.breakdown, "Sources")
    -- a long journal lists Gold.MAX_ROWS entries and says so
    do
      local keep = Gold.MAX_ROWS
      Gold.MAX_ROWS = 20
      Gold.open("session", "journal"); M.settle()
      local n = #ns.Recorder.current().goldLog
      check("Gold long journal: the newest entries are listed, the header says how many in all", #dataRows(c.tbl.journal) == 20 and c.section.meta:GetText() == ("newest 20 of %d"):format(n), c.section.meta:GetText())
      Gold.MAX_ROWS = keep
    end
    -- an empty period
    ses.goldLog, ses.gold, ses.gained, ses.spent, ses.trades = {}, {}, 0, 0, {}
    Gold.open("session"); M.settle()
    check("Gold empty: the sentence of 4.9", c.tbl.sources.stateFS and c.tbl.sources.stateFS:GetText() == GP.EMPTY and c.summary.Text() == "No gold moved this session", c.summary.Text())
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
    check("Sessions gold: a click on a row shows that session's gold", band.title.text:find(Gold.sessionLabel(prevRow.item), 1, true) ~= nil and band.blocks[2].lines[1].text:find("^Quest: The Jasperlode Mine") ~= nil and band.blocks[3].lines[1].text:find("^Training  12" .. UI.NBSP .. "|T[^|]*SilverIcon") ~= nil, band.blocks[3].lines[1].text)
    check("Sessions gold: the shown row's date is marked in fgSubtle, never mint", prevRow.c.date._color and near(prevRow.c.date._color[1], UI.C.fgSubtle[1]))
    click(band.open)
    local gold
    for _, tab in ipairs(P.T.tabs) do if tab.name == "Loot" then gold = tab.paneByKey.gold.content end end
    check("Sessions gold: the button opens that session's journal in the Gold pane", P.visible(gold) and gold.st.scope == prevRow.item.id and gold.st.view == "journal" and gold.more.ebActive == true and #dataRows(gold.tbl.journal) == #prevRow.item.goldLog, gold.st.scope)
    -- a session from before 0.9.40
    local ses = ns.Recorder.current()
    ses.goldLog, ses.trades, ses.goldLogDropped = nil, nil, nil
    ns.UI.Open("Home", "sessions"); M.settle()
    click(shown(c.tbl.rows)[1])
    check("Sessions gold: a session without a journal keeps its top sources and says why the rest is empty", band.blocks[1].lines[1].text:find("^Trades received") ~= nil and band.blocks[2].lines[1].text == "Recorded before addon 0.9.40" and band.blocks[4].lines[1].text == "Changed while away: +42s", band.blocks[2].lines[1].text)
  end
  -- ── 0.9.44 (#43): periods by server day, who, Days and Characters ───────────────────────────────────────────
  local DAY = 86400
  local MIRA, ORG = "Player-1-0000B1", "Player-1-0000B2"
  -- two more characters in the data in use: one seen three days ago with a day row today, one of another realm and
  -- faction not seen for 100 days; Hartbank (tests/play_gold.lua) has never logged in with 0.9.44. The purses are the
  -- size a player really has (#49): above 10,000g on the data as played (Orgrim at the Classic cap of 214,748g), above
  -- 1,000,000g on the long data (Orgrim at the 9,999,999g cap), so a column that only fits a small balance fails here
  local ALT
  local function addAlts(data)
    local rich = data == "goldlong"
    ALT = rich and { mira = 12345678912, org = 99999999999, bank = 15000007777, g = 5000000000, s = 2000000000 }
      or { mira = 123456789, org = 2147483647, bank = 150000000, g = 50000000, s = 20000000 }
    local base = Gold.baseStored()
    local now = GetServerTime()
    for guid in pairs(ns.DB.characters) do if guid ~= ns.charGuid() and guid ~= "Player-1-0000A1" then ns.DB.characters[guid] = nil end end
    ns.DB.characters[MIRA] = { name = "Mira", surname = "Dawnfall", realm = GetRealmName(), class = "WARRIOR", faction = "Alliance", level = 21, seen = now - 3 * DAY,
      gold = { balance = ALT.mira, gained = ALT.mira, spent = 0 },
      goldDays = { [Gold.dayKey(now, base)] = { g = ALT.g, s = ALT.s, o = ALT.mira - (ALT.g - ALT.s), c = ALT.mira, t = 900, n = 3, looted = ALT.g, repairs = ALT.s, away = 0 } } }
    ns.DB.characters[ORG] = { name = "Orgrim", realm = "Forever Realm [EU] - Other Shore", class = "SHAMAN", faction = "Horde", level = 40, seen = now - 100 * DAY,
      gold = { balance = ALT.org, gained = ALT.org, spent = 0 } }
    ns.DB.characters["Player-1-0000A1"].gold = { balance = ALT.bank }
  end

  for _, size in ipairs(SIZES) do
    for _, data in ipairs({ "gold", "goldlong" }) do
      local tag = ("Gold 0.9.44 %dx%d %s"):format(size[1], size[2], data)
      local c = open(size[1], size[2], data, "today")
      addAlts(data); Gold.open("today"); M.settle()
      local me = ns.char()
      local base = Gold.baseStored()
      local now = GetServerTime()
      local kT = Gold.dayKey(now, base)
      local today = me.goldDays[kT]
      local wide = UI.G.isWide(UI.G.winW())
      -- Today: the day row's numbers on the cards
      check(tag .. ": Today is selected and reads the day row", c.period.value == "today" and today ~= nil and c.shownCards[2].value:GetText() == money(today.g, today.g > 0)
        and c.shownCards[3].value:GetText() == (today.s > 0 and money(-today.s, true) or money(0)) and c.shownCards[1].label:GetText() == "BALANCE" and c.shownCards[1].value:GetText() == money(me.gold.balance), c.shownCards[2].value:GetText())
      local src = c.sourceData
      local okSrc = src.inTotal == today.g and src.outTotal == today.s
      for _, r in ipairs(src.rows) do if r.dir ~= 0 and r.amount ~= (today[r.key] or 0) then okSrc = false end end
      check(tag .. ": the sources of Today are the day row's keys", okSrc and #src.rows >= 10)
      -- ── Days ──
      check(tag .. ": Days is picked from Break down by", pick(c.breakdown, "Days") and c.st.view == "days" and c.section.label:GetText() == "DAYS")
      local dt = c.tbl.days
      check(tag .. ": the Days table shows, every other table is hidden", P.visible(dt.frame) and not P.visible(c.tbl.sources.frame) and not P.visible(c.tbl.journal.frame) and not P.visible(c.tbl.chars.frame))
      eq(tag .. ": Days columns", keys(dt), wide and "day,earned,spent,net,played,rate,top,bal" or "day,earned,spent,net,bal")
      local dr = dataRows(dt)
      check(tag .. ": Today has one day with the row's numbers", #dr == 1 and dr[1].c.earned:GetText() == money(today.g, today.g > 0) and dr[1].c.net:GetText() == money(today.g - today.s, true)
        and dr[1].c.bal:GetText() == money(today.c), #dr)
      local stb, hb = P.box(c.dayStrip), P.box(dt.frame)
      check(tag .. ": the strip of the last 30 days sits above the table, inside the column", P.visible(c.dayStrip) and c.dayStrip.n == 30 and stb.t + stb.h <= hb.t + 0.5
        and stb.l + stb.w <= P.box(c.col).l + P.box(c.col).w + 0.5, stb.w)
      check(tag .. ": the chart button shows the balance line instead", P.visible(c.chartBtn) and c.chartBtn.text:GetText() == "Show balance")
      click(c.chartBtn)
      check(tag .. ": the balance line replaces the bars", P.visible(c.dayLine) and not P.visible(c.dayStrip) and c.chartBtn.text:GetText() == "Show net per day")
      click(c.chartBtn)
      tableChecks(tag .. " Days", dt, c)
      -- All time: every day, newest first
      me.goldDays[Gold.dayKey(now - 12 * DAY, base)] = { g = 9000, s = 1000, o = 2000, c = 10050, t = 3700, n = 3, looted = 9000, repairs = 1000, away = 50 }
      me.goldDays[Gold.dayKey(now - 20 * DAY, base)] = { g = 2000, s = 0, o = 0, c = 2000, t = 60, n = 1, quests = 2000 }
      period(c, "all")
      dr = dataRows(dt)
      local nDays = 0
      for _ in pairs(me.goldDays) do nDays = nDays + 1 end
      check(tag .. ": All time lists every day, newest first", #dr == nDays and nDays >= 4 and dr[1].item.key == kT and dr[#dr].item.key == Gold.dayKey(now - 20 * DAY, base), #dr)
      if wide then
        local old
        for _, r in ipairs(dr) do if r.item.key == Gold.dayKey(now - 12 * DAY, base) then old = r end end
        check(tag .. ": Played and Per hour come from the day's active seconds", old and old.c.played:GetText() == UI.fmtDur(3700) and old.c.rate:GetText() == money(8000 * 3600 / 3700, true), old and old.c.played:GetText())
      end
      dt.head.earned.scripts.OnClick(dt.head.earned); M.settle()
      dr = dataRows(dt)
      local sorted = true
      for i = 2, #dr do if (dr[i].item.g - dr[i - 1].item.g) * (c.st.dayAsc and 1 or -1) < 0 then sorted = false end end
      check(tag .. ": a click on Earned sorts by it", sorted and c.st.daySort == "earned")
      c.st.daySort, c.st.dayAsc = "day", false; dt.setSort("day", false); c.refresh()
      -- a day's tooltip, then a click opens its sources
      dr = dataRows(dt)
      local oldRow
      for _, r in ipairs(dr) do if r.item.key == Gold.dayKey(now - 12 * DAY, base) then oldRow = r end end
      local t = tipOf(oldRow)
      check(tag .. ": a day's tooltip lists its sources and what a click does", t:find("Looted coin", 1, true) and t:find("While you were away", 1, true) and t:find("Click to see this day's sources.", 1, true), t)
      click(oldRow)
      check(tag .. ": a click on a day opens Sources for that day, the day on More", c.st.view == "sources" and c.st.scope == "day:" .. Gold.dayKey(now - 12 * DAY, base) and P.visible(c.tbl.sources.frame)
        and c.more.ebActive and c.period.value == nil and c.shownCards[2].value:GetText() == money(9000, true) and c.shownCards[1].label:GetText() == "BALANCE AT ITS END" and c.shownCards[1].value:GetText() == money(10050), c.st.scope)
      local looted
      for _, r in ipairs(dataRows(c.tbl.sources)) do if r.item.key == "looted" then looted = r end end
      check(tag .. ": a day older than the journals keeps its totals; its source opens nothing", looted and looted.c.amount:GetText() == money(9000, true) and looted.item.n == 0 and looted.item.ebNoOpen == true)
      Gold.open("today"); M.settle()
      -- ── Characters: the scope filter in place of search ──
      check(tag .. ": Characters is picked from Break down by", pick(c.breakdown, "Characters") and c.st.view == "chars" and c.section.label:GetText() == "CHARACTERS")
      check(tag .. ": the scope filter takes the place of search", P.visible(c.whoFilter) and not P.visible(c.search) and c.whoFilter.text:GetText() == "This character")
      eq(tag .. ": the scope filter offers", table.concat(offered(c.whoFilter), ","), "This character,This realm,Account")
      local ct = c.tbl.chars
      local ro = Gold.roster("all")
      local cr = dataRows(ct)
      check(tag .. ": the total first, then every character counted, by balance", cr[1].item.total == true and cr[1].c.balance:GetText() == money(ro.total) and cr[1].c.name:GetText() == ("All %d characters"):format(ro.count)
        and cr[2].item.balance >= cr[3].item.balance, cr[1].c.name:GetText())
      local function rowOf(guid) for _, r in ipairs(dataRows(ct)) do if r.item.guid == guid then return r end end end
      local meRow, mira = rowOf(ns.charGuid()), rowOf(MIRA)
      check(tag .. ": the current character says you and now", meRow.c.name:GetText():find(" %(you%)$") ~= nil and meRow.c.seen:GetText() == "now", meRow.c.name:GetText())
      check(tag .. ": another character in its class colour, with today, 7 days and its age", mira.c.name:GetText() == "Mira Dawnfall" and math.abs(mira.c.name._color[1] - RAID_CLASS_COLORS.WARRIOR.r) < 0.01
        and mira.c.today:GetText() == money(ALT.g - ALT.s, true) and mira.c.balance:GetText() == money(ALT.mira), mira.c.name:GetText())
      check(tag .. ": the not seen in 90 days button counts them", P.visible(c.staleBtn) and c.staleBtn.text:GetText() == "Show 1 not seen in 90 days", c.staleBtn.text:GetText())
      click(c.staleBtn)
      check(tag .. ": included, the stale character is counted", dataRows(ct)[1].c.balance:GetText() == money(ro.total + ALT.org))
      click(c.staleBtn)
      -- hide from totals with a click
      click(rowOf(MIRA))
      check(tag .. ": a click on a character hides it from totals", ns.DB.settings.gold.hidden[MIRA] == true and dataRows(ct)[1].c.balance:GetText() == money(ro.total - ALT.mira) and rowOf(MIRA).c.seen:GetText() == "hidden")
      t = tipOf(rowOf(MIRA))
      check(tag .. ": its tooltip says a click counts it again", t:find("Click to count it in totals again.", 1, true) ~= nil, t)
      click(rowOf(MIRA))
      check(tag .. ": shown again, no empty table is left in the settings", dataRows(ct)[1].c.balance:GetText() == money(ro.total) and ns.DB.settings.gold.hidden == nil)
      -- Account: the cards add up the characters
      check(tag .. ": Account is picked from the scope filter", pick(c.whoFilter, "Account") and c.st.who == "account" and c.whoFilter.ebActive)
      check(tag .. ": BALANCE becomes ACCOUNT GOLD; EARNED sums the day rows", c.shownCards[1].label:GetText() == "ACCOUNT GOLD" and c.shownCards[1].value:GetText() == money(ro.total)
        and c.shownCards[2].value:GetText() == money(today.g + ALT.g, true), c.shownCards[2].value:GetText())
      pick(c.whoFilter, "This realm")
      check(tag .. ": This realm leaves the other realm out", c.shownCards[1].value:GetText() == money(Gold.roster("realm").total) and c.shownCards[1].label:GetText() == "REALM GOLD")
      pick(c.whoFilter, "This character")
      tableChecks(tag .. " Characters", ct, c)
      pick(c.breakdown, "Sources")
      check(tag .. ": leaving Characters goes back to this character and to search", c.st.who == "char" and P.visible(c.search) and not P.visible(c.whoFilter))
    end
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
    pick(c.breakdown, "Days")
    check("Gold first run: Days says what comes", c.tbl.days.stateFS:GetText() == "Each day you play gets a row here, with what you earned and spent.")
    pick(c.breakdown, "Characters")
    local cr = dataRows(c.tbl.chars)
    check("Gold first run: Characters lists the one character and says how the others come", #cr == 1 and cr[1].c.name:GetText():find(" %(you%)$") ~= nil and P.visible(c.charsNote)
      and c.charsNote.text:GetText() == "Log in on your other characters once and their gold shows here.", #cr)
    for _, key in ipairs({ "week", "yesterday", "month", "last30" }) do Gold.open(key); M.settle() end
    check("Gold first run: every day period opens on an empty history without an error", #UI.paneErrors() == 0, table.concat(UI.paneErrors(), " || "))
    pick(c.breakdown, "Sources")
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
