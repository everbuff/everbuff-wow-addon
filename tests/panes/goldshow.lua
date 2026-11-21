-- Pane tests: the gold showcase on LOOT / Gold (everbuff-wow-addon #43, 0.9.47). Played on tests/play_gold.lua
-- ("gold") with places, dungeon runs and folded months put into the logged-in character's block:
--   Zones    one row per place with its coin, the total row first, the evicted places as one row last, sortable
--   Runs     one row per dungeon run, the open one first, the vendor price of the loot in a column of its own ("so
--            far" while an item has no price), Coin per hour and Items only at WIDE
--   Days     the balance line in the bars' place by the section header's button, folded months as rows of their own
--   audit    BALANCE's hover says when the records add up; a break is said on the untraced line, never in red
--   Combat / Dungeons   the open run's loot line reads the run's own gold record
return function(P)
  local check, eq, M, ns = P.check, P.eq, P.M, P.ns
  local UI, Gold = ns.UI, ns.Gold
  local fmt = ns.fmtMoney
  local tip = _G.GameTooltip
  local SEP = "  ·  "
  local function shown(rows) local out = {}; for _, r in ipairs(rows or {}) do if r.shown ~= false then out[#out + 1] = r end end return out end
  local function click(b) b.scripts.OnClick(b, "LeftButton"); M.settle() end
  local savedCurrent = ns.Recorder.current
  ns.Recorder.current = function() return ns.DB.active and ns.DB.sessions[ns.DB.active] or nil end
  local now = GetServerTime()
  -- places, runs and months for the character of the data in use
  local function fill()
    local c = ns.char()
    c.goldZones = {
      [37] = { looted = 123456, quests = 50000, secs = 5400, last = now - 600, name = "Elwynn Forest" },
      [52] = { looted = 2000, quests = 0, secs = 200, last = now - 3 * 86400, name = "Westfall" },
      [0] = { looted = 40, quests = 0, secs = 0, last = now - 40 * 86400 },
    }
    c.goldZonesEvicted = { n = 2, looted = 700, quests = 300, secs = 900 }
    c.goldRun = { t = now - 900, inst = "Shadowfang Keep", secs = 840, looted = 5000, quests = 0, lootValue = 1234, items = 3, wait = { [9003] = 2 } }
    c.goldRuns = {
      { t = now - 3 * 86400, inst = "The Deadmines", secs = 3600, looted = 32000, quests = 12000, lootValue = 51000, items = 14 },
      { t = now - 2 * 86400, inst = "Sunken Temple", secs = 120, looted = 100, quests = 0, lootValue = 0, items = 1, unpriced = 1 },
    }
c.goldRunsEvicted = { n = 4, looted = 9000, quests = 1000, secs = 7200, lootValue = 3000, items = 9, unpriced = 2 }
    return c
  end
  local function open(w, h, view, scope)
    local c = P.open("loot", "gold", w, h, "gold")
    fill()
    Gold.open(scope or "today", view); M.settle()
    return c
  end
  -- A character played from zero through the real handlers, in a save file of its own put in the place of the data
  -- in use (the played "gold" data holds changes while away in every period, so nothing in it can read
  -- "Reconciled"). Returns the function that puts the client back; the next P.open brings the data back.
  local function playFromZero()
    local E = ns.Emitter
    local keep = { money = M.money, now = M.now, timers = M.timers, repair = M.repairCost }
    local db = ns.migrateDB({})
    for k in pairs(ns.DB) do ns.DB[k] = nil end
    for k, v in pairs(db) do ns.DB[k] = v end
    Gold._held, Gold._baseWait, Gold._flushTimer, Gold._tickAt = nil, nil, nil, nil
    ns._test.newLoad()
    M.timers = {}
    M.money = 0
    local realPrint = print
    print = function() end
    M.fire("PLAYER_ENTERING_WORLD", true, false); M.runTimers()
    print = realPrint
    Gold.tick()
    local function money(d) M.money = M.money + d; M.fire("PLAYER_MONEY") end
    M.units.target = { name = "Kobold Miner", hostile = true, dead = true, guid = "Creature-0-1-1-1-6-00AA" }
    M.fire("LOOT_OPENED"); money(1500)
    M.units.target = nil
    M.now = M.now + 4
    E.questMoney(800, 4242); money(800)
    M.now = M.now + 4
    money(40)                                   -- a gain nothing explains
    money(-150)                                 -- a spend nothing explains
    M.repairCost = 300; M.fire("MERCHANT_SHOW")
    money(-300); M.repairCost = 0; M.fire("UPDATE_INVENTORY_DURABILITY")   -- a repair, booked after its wait
    M.fire("MERCHANT_CLOSED")
    M.runTimers()
    return function()
      M.money, M.now, M.repairCost = keep.money, keep.now, keep.repair
      Gold._held, Gold._baseWait, Gold._flushTimer, Gold._tickAt = nil, nil, nil, nil
      ns._test.newLoad()
      M.timers = {}
      P.open("loot", "gold", 900, 580, "gold")
      -- the baseline of the purse is read again on the data's own balance
      M.fire("PLAYER_MONEY"); M.runTimers()
      M.timers = keep.timers
    end
  end

  local GP = Gold.GP
  local money = GP.money
  local function dataRows(tbl) local out = {}; for _, r in ipairs(shown(tbl.rows)) do if r.item and not r.item.ebSection then out[#out + 1] = r end end return out end
  local function tipOf(f) tip:ClearLines(); f.scripts.OnEnter(f); local t = table.concat(tip.lines or {}, "\n"); f.scripts.OnLeave(f); return t end
  local function colorIs(fs, key) local c, k = fs._color, UI.C[key]; return c ~= nil and math.abs(c[1] - k[1]) < 0.01 and math.abs(c[2] - k[2]) < 0.01 and math.abs(c[3] - k[3]) < 0.01 end
  -- every shown cell of a table inside the page's column
  local function inside(c, tbl)
    local cb = P.box(c.col)
    for _, r in ipairs(dataRows(tbl)) do
      for k, fs in pairs(r.c or {}) do
        local b = fs.shown ~= false and P.box(fs)
        if b and b.l + b.w > cb.l + cb.w + 0.5 then return false, "cell past the column: " .. k end
      end
    end
    return true
  end

  for _, size in ipairs({ { 900, 580 }, { 1600, 1000 } }) do
    local tag = ("Gold 0.9.47 %dx%d"):format(size[1], size[2])
    -- ── Zones ────────────────────────────────────────────────────────────────────────────────────────────────
    do
      local c = open(size[1], size[2], "zones")
      check(tag .. ": Break down by offers Zones and Runs after the four views", Gold.VIEWS[5][2] == "Zones" and Gold.VIEWS[6][2] == "Runs" and c.breakdown.text:GetText() == "Break down by: Zones")
      local rows = dataRows(c.tbl.zones)
      check(tag .. ": Zones lists the total, each place and the evicted places", #rows == 5 and P.visible(c.tbl.zones.frame) and not P.visible(c.tbl.sources.frame), #rows)
      local t, first, last = rows[1], rows[2], rows[5]
      check(tag .. ": the total row is first and counts the evicted places", t.item.total and t.c.zone:GetText() == "Every place" and t.c.looted:GetText() == money(123456 + 2000 + 40 + 700)
        and t.c.quests:GetText() == money(50300), t.c.zone:GetText())
      check(tag .. ": places by looted coin, the biggest first: name, looted, quests, played, per hour, last visit", first.c.zone:GetText() == "Elwynn Forest" and first.c.looted:GetText() == money(123456)
        and first.c.quests:GetText() == money(50000) and first.c.played:GetText() == UI.fmtDur(5400) and first.c.rate:GetText() == money(173456 * 3600 / 5400) and first.c.last:GetText() == UI.fmtDate(now - 600), first.c.rate:GetText())
      check(tag .. ": a place under 5 minutes has no rate, one the client named no map for is named so", rows[3].c.zone:GetText() == "Westfall" and rows[3].c.rate:GetText() == "-"
        and rows[4].c.zone:GetText() == Gold.NO_MAP and rows[4].c.played:GetText() == "-")
      check(tag .. ": the evicted places are one muted row at the end", last.item.evicted and last.c.zone:GetText() == "2 earlier places" and last.c.looted:GetText() == money(700) and colorIs(last.c.zone, "fgMuted"))
      check(tag .. ": the section header says whose places they are", c.section.label:GetText() == "ZONES" and c.section.meta:GetText():find("this character", 1, true) ~= nil)
      local ok, why = inside(c, c.tbl.zones)
      check(tag .. ": every Zones cell is inside the column", ok, why)
      local text = tipOf(first)
      check(tag .. ": a place's hover names its coin and what is not counted", text:find("Elwynn Forest", 1, true) ~= nil and text:find("Vendor sales and repairs are not counted by place", 1, true) ~= nil, text)
      -- sort by quests ascending: the total stays first, the evicted row last
      c.tbl.zones.head.quests.scripts.OnClick(c.tbl.zones.head.quests); M.settle()
      c.tbl.zones.head.quests.scripts.OnClick(c.tbl.zones.head.quests); M.settle()
      rows = dataRows(c.tbl.zones)
      check(tag .. ": a sort keeps the total first and the evicted row last", rows[1].item.total and rows[5].item.evicted and c.st.zoneSort == "quests", c.st.zoneSort)
      c.st.zoneSort, c.st.zoneAsc = "looted", false; c.tbl.zones.setSort("looted", false)
      -- empty
      ns.char().goldZones, ns.char().goldZonesEvicted = nil, nil
      Gold.open("today", "zones"); M.settle()
      check(tag .. ": with no place yet the list says what comes", #dataRows(c.tbl.zones) == 0 and c.tbl.zones.stateFS:GetText() == "Loot coin or turn in a quest and the place shows here.")
    end
    -- ── Runs ─────────────────────────────────────────────────────────────────────────────────────────────────
    do
      local c = open(size[1], size[2], "runs")
      local wide = UI.G.isWide(UI.G.winW())
      local tbl = c.tbl.runs
      local rows = dataRows(tbl)
      check(tag .. ": Runs lists the total, the open run, the closed runs newest first and the evicted runs", #rows == 5 and P.visible(tbl.frame) and c.st.view == "runs", #rows)
      check(tag .. ": the total row counts every run", rows[1].item.total and rows[1].c.inst:GetText() == "Every run" and rows[1].c.looted:GetText() == money(5000 + 32000 + 100 + 9000), rows[1].c.inst:GetText())
      local openRow, st, dm = rows[2], rows[3], rows[4]
      check(tag .. ": the open run is first and says it is in progress", openRow.c.inst:GetText() == "Shadowfang Keep (in progress)" and openRow.c.length:GetText() == UI.fmtDur(840) and openRow.c.looted:GetText() == money(5000), openRow.c.inst:GetText())
      check(tag .. ": an item waiting for its price makes the vendor price read \"so far\"", openRow.c.value:GetText() == money(1234) .. " so far" and st.c.value:GetText() == money(0) .. " so far", openRow.c.value:GetText())
      check(tag .. ": a closed run: date, dungeon, length, looted, quests and the vendor price in its own column", dm.c.inst:GetText() == "The Deadmines" and dm.c.time:GetText() == UI.fmtDate(now - 3 * 86400)
        and dm.c.length:GetText() == UI.fmtDur(3600) and dm.c.looted:GetText() == money(32000) and dm.c.quests:GetText() == money(12000) and dm.c.value:GetText() == money(51000), dm.c.value:GetText())
      if wide then
        check(tag .. ": wide: coin per hour is coin over the time played, never the vendor price; items counted", dm.c.rate:GetText() == money(44000) and dm.c.items:GetText() == "14" and st.c.rate:GetText() == "-", dm.c.rate:GetText())
      else
        check(tag .. ": narrow: Coin per hour and Items are left out", tbl.cols.rate == nil and tbl.cols.items == nil)
      end
      check(tag .. ": the evicted runs are one row at the end", rows[5].item.evicted and rows[5].c.inst:GetText() == "4 earlier runs" and rows[5].c.time:GetText() == "-")
      local ok, why = inside(c, tbl)
      check(tag .. ": every Runs cell is inside the column", ok, why)
      local text = tipOf(dm)
      check(tag .. ": a run's hover says the vendor price is never added to coin", text:find("The Deadmines", 1, true) ~= nil and text:find("never added to coin", 1, true) ~= nil, text)
      ns.char().goldRuns, ns.char().goldRunsEvicted, ns.char().goldRun = nil, nil, nil
      Gold.open("today", "runs"); M.settle()
      check(tag .. ": with no run yet the list says so", #dataRows(tbl) == 0 and tbl.stateFS:GetText() == "Run a dungeon and its coin shows here.")
    end
    -- ── Days: the balance line, folded months ────────────────────────────────────────────────────────────────
    do
      local c = open(size[1], size[2], "days", "all")
      check(tag .. ": Days shows the net bars first, and a button for the balance line", P.visible(c.dayStrip) and not P.visible(c.dayLine) and P.visible(c.chartBtn) and c.chartBtn.text:GetText() == "Show balance")
      click(c.chartBtn)
      check(tag .. ": the button puts the balance line in the bars' place and names the way back", P.visible(c.dayLine) and not P.visible(c.dayStrip) and c.chartBtn.text:GetText() == "Show net per day")
      local lb, colB, hb = P.box(c.dayLine), P.box(c.col), P.box(c.tbl.days.frame)
      check(tag .. ": the line is inside the column and ends above the list", lb.l >= colB.l and lb.l + lb.w <= colB.l + colB.w + 0.5 and lb.t + lb.h <= hb.t + 0.5, (lb.t + lb.h) .. " " .. hb.t)
      local line = c.dayLine
      check(tag .. ": 30 slots, drawn across the whole width", line.n == 30 and math.abs(line.slot * 30 - lb.w) < 1 and #line.values == 30)
      check(tag .. ": days with a row are solid, carried days dashed, today solid", line.solid >= 2 and line.dashes > 0 and line.values[30].live == true and line.values[30].stale == false, line.solid .. " " .. line.dashes)
      UI.SetWindowSize(size[1] + 80, size[2]); M.settle()
      check(tag .. ": a wider window draws the line again for its width", math.abs(c.dayLine.slot * 30 - P.box(c.dayLine).w) < 1)
      UI.SetWindowSize(size[1], size[2]); M.settle()
      click(c.chartBtn)
      check(tag .. ": the button brings the net bars back", P.visible(c.dayStrip) and not P.visible(c.dayLine) and c.chartBtn.text:GetText() == "Show balance")
      Gold.open("all", "sources"); M.settle()
      check(tag .. ": the chart button is only on Days", not P.visible(c.chartBtn) and not P.visible(c.dayLine) and not P.visible(c.dayStrip))
      -- folded months: rows of their own under the days, opening nothing
      local me = ns.char()
      local oldest
      for k in pairs(me.goldDays) do if not oldest or k < oldest then oldest = k end end
      local o = me.goldDays[oldest].o or 0
      me.goldMonths = { ["201901"] = { g = 900000, s = 100000, t = 36000, n = 300, d = 28, looted = 900000, repairs = 100000, o = o - 1000000, c = o - 200000 },
        ["201902"] = { g = 300000, s = 100000, t = 7200, n = 90, d = 12, quests = 300000, vendor = 100000, o = o - 200000, c = o } }
      Gold.open("all", "days"); M.settle()
      local rows = dataRows(c.tbl.days)
      local folded = {}
      for _, r in ipairs(rows) do if r.item.folded then folded[#folded + 1] = r end end
      check(tag .. ": the folded months are rows under the days, newest first, with their days counted", #folded == 2 and folded[1].c.day:GetText() == "Feb 2019, 12 days" and folded[2].c.day:GetText() == "Jan 2019, 28 days"
        and rows[#rows] == folded[2], folded[1] and folded[1].c.day:GetText())
      check(tag .. ": a month row reads earned, spent, net and its closing balance", folded[2].c.earned:GetText() == money(900000, true) and folded[2].c.spent:GetText() == money(-100000, true)
        and folded[2].c.net:GetText() == money(800000, true) and folded[2].c.bal:GetText() == money(o - 200000))
      local scopeBefore = c.st.scope
      folded[1].scripts.OnClick(folded[1], "LeftButton"); M.settle()
      check(tag .. ": a click on a month row opens nothing", c.st.scope == scopeBefore and c.st.view == "days" and folded[1].item.ebNoOpen == true)
      local text = tipOf(folded[1])
      check(tag .. ": its hover says why it is a month", text:find("folded into their month", 1, true) ~= nil and text:find("Click to see", 1, true) == nil, text)
    end
    -- ── the audit: reconciled, broken, not checkable ─────────────────────────────────────────────────────────
    do
      local c = open(size[1], size[2], "sources", "today")
      local back = playFromZero()
      for _, scope in ipairs({ "today", "all" }) do
        Gold.open(scope, "sources"); M.settle()
        local a = c.audit
        check(tag .. ": " .. scope .. ": a character played from zero reconciles", a ~= nil and a.state == "ok" and a.key == (scope == "all" and "history" or scope) and a.checks >= 1, a and tostring(a.text or a.reason))
        check(tag .. ": " .. scope .. ": BALANCE's hover says the records add up", tipOf(c.shownCards[1]):find("The records add up for this period.", 1, true) ~= nil)
        check(tag .. ": " .. scope .. ": nothing on the page says they do not", (c.untracedText or ""):find("do not add up", 1, true) == nil)
      end
      check(tag .. ": the reconciled character's cards read what was played", c.shownCards[2].value:GetText() == money(2340, true) and c.shownCards[3].value:GetText() == money(-450, true), c.shownCards[2].value:GetText())
      back()
      -- the played data: changes while away in every period, so not checkable, and never a break
      c = open(size[1], size[2], "sources", "session")
      check(tag .. ": the running session of the gold data is audited and cannot be checked", c.audit ~= nil and c.audit.key == "session" and c.audit.state == "unknown" and (c.untracedText or ""):find("do not add up", 1, true) == nil)
      for _, scope in ipairs({ "all", "today", "yesterday", "week", "month", "last30" }) do
        Gold.open(scope, "sources"); M.settle()
        check(tag .. ": " .. scope .. " on the played data does not read broken", c.audit ~= nil and c.audit.state == "unknown" and (c.untracedText or ""):find("do not add up", 1, true) == nil, c.audit and tostring(c.audit.reason))
      end
      -- a break: on the untraced line, muted, never red; its hover says where
      Gold.open("session", "sources"); M.settle()
      local ses = ns.Recorder.current()
      ses.gold.other = (ses.gold.other or 0) + 1
      Gold.open("session", "sources"); M.settle()
      check(tag .. ": a break is said on the untraced line, in fgMuted", c.audit.state == "broken" and c.untraced:GetText():lower():find("some gold changes could not be traced", 1, true) ~= nil and c.untraced:GetText():find("Hover", 1, true) == nil and colorIs(c.untraced, "fgMuted"), c.untraced:GetText())
      local text = tipOf(c.untracedHit)
      check(tag .. ": the hover names the break", text:find("Unexplained spending", 1, true) ~= nil, text)
      ses.gold.other = ses.gold.other - 1
    end
  end
  -- ── Combat / Dungeons: the open run's loot line ────────────────────────────────────────────────────────────
  do
    local c = P.open("combat", "dungeons", 900, 580, "normal")
    -- a stored run of the character (0.9.50: the pane reads characters[guid].dungeonRuns), with its own gold block
    ns.char().dungeonRuns = ns.char().dungeonRuns or {}
    local list = ns.char().dungeonRuns
    local rec = ns._test.runRecord("The Deadmines", now - 4000, 1800, { gold = { looted = 32000, quests = 0, lootValue = 51000, items = 12, purse = 32000 } })
    list[#list + 1] = rec
    local function view() local vs = ns._test.runViews(true); return vs[#vs] end
    local run = view()
    ns._test.renderRun(run); M.settle()
    local dv = ns._test.dungeonDetail()
    eq("Dungeons: a run's WORTH is its coin looted plus the vendor value of its items, from its own gold block", dv.card.worth and dv.card.worth.value.text, ns.UI.money(32000 + 51000))
    eq("Dungeons: and the card says the two parts", ns.Dungeons.D.worthParts(run), ("%s coin · %s items at vendor prices"):format(ns.UI.money(32000), ns.UI.money(51000)))
    check("Dungeons: the WORTH card's meta is not cut at 900 px", dv.card.worth.meta.IsTruncated == nil or not dv.card.worth.meta:IsTruncated(), dv.card.worth.meta.text)
    local function onPage(text)
      local found, cutOff = false, false
      for _, fs in ipairs(dv.lines) do
        if fs.shown ~= false and fs.text == text then found = true; if fs.IsTruncated and fs:IsTruncated() then cutOff = true end end
      end
      return found and not cutOff
    end
    check("Dungeons: no purse note while the looted coin is what the purse gained", dv.purseLine == nil and dv.purseTip == nil)
    check("Dungeons: the clocks of the run are two lines, in full", dv.timeLine == "Inside 30m 0s" and dv.timeLine2 == "Active 30m 0s" and onPage(dv.timeLine) and onPage(dv.timeLine2), dv.timeLine)
    -- the list row of the run reads the same block as its page
    local function listRow()
      local lv = ns._test.dungeonList(); M.settle()
      for _, r in ipairs(lv and lv.tbl and lv.tbl.rows or {}) do
        if r.shown ~= false and r.run and r.run.id == rec.id then return r end
      end
    end
    local row = listRow()
    eq("Dungeons: the list row of that run reads the same worth", row and row.c.worth.text, ns.UI.money(32000 + 51000))
    check("Dungeons: the list has no item count, coin or XP per hour column", row and row.c.loot == nil and row.c.coin == nil and row.c.xph == nil)
    -- the purse gained more inside than was booked as looted (group shares booked as mail, seen 2026-11-18)
    rec.gold.looted, rec.gold.purse = 365, 11253
    rec.xp = { gain = 12300, kill = 9000, quest = 0, n = 45, l0 = 23, p0 = 0.4, l1 = 24, p1 = 0.1, need = 30000 }
    rec.hidden = { xp = 12 }
    ns._test.renderRun(view()); M.settle()
    -- (the purse against the looted coin is a hover of the WORTH card, never a line: the card already has the coin)
    eq("Dungeons: the WORTH hover says when the looted coin is not what the purse gained", dv.purseTip,
      ("Your purse grew by %s inside, quest rewards aside. Looted coin was %s."):format(fmt(11253), fmt(365)))
    check("Dungeons: and the hover carries it", tipOf(dv.card.worth):find(dv.purseTip, 1, true) ~= nil, tipOf(dv.card.worth))
    local pageText = {}
    for _, fs in ipairs(dv.lines) do if fs.shown ~= false then pageText[#pageText + 1] = tostring(fs.text) end end
    pageText = table.concat(pageText, " | ")
    check("Dungeons: the page has no purse line, no XP section, no kill count and no forecast of runs to a level",
      dv.purseLine == nil and dv.xpLine == nil and dv.xpMore == nil and dv.sections.xp == nil
      and pageText:find("gained inside", 1, true) == nil and pageText:find("more run", 1, true) == nil and pageText:find("kills", 1, true) == nil, pageText)
    eq("Dungeons: the XP hover has the split, the levels and what the client hid, and nothing forecast", table.concat(dv.xpTip, " | "),
      "XP earned inside, and per hour of the time inside. | All from kills. | Level 23.4 to 24.1. | 12 XP lines were hidden by the client.")
    -- (one rate on the page: the XP card's, per hour of the 30 minutes inside)
    eq("Dungeons: the XP card carries the rate, per hour of time inside", dv.card.xp and dv.card.xp.meta.text, "24,600 per hour")
    row = listRow()
    table.remove(list)
  end
  ns.Recorder.current = savedCurrent
end
