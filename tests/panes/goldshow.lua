-- Pane tests: the gold showcase on LOOT / Gold (everbuff-wow-addon #43, 0.9.47). Played on tests/play_gold.lua
-- ("gold") with places, dungeon runs and folded months put into the logged-in character's block:
--   Zones    one row per place with its coin, the TOTAL row first, the evicted places as one row last, sortable
--   Runs     one row per dungeon run, the open one first, Loot value as an estimate column of its own ("so far"
--            while an item has no price), Coin per hour and Items left out when narrow
--   Days     the balance line in the strip's place by the caption row's button, folded months as rows of their own
--   status   "Reconciled" with its check mark and its hover, a break in red, nothing more when not checkable
--   Combat / Dungeons   the open run's loot line reads the run's own gold record
return function(P)
  local check, eq, M, ns = P.check, P.eq, P.M, P.ns
  local UI, Gold = ns.UI, ns.Gold
  local fmt = ns.fmtMoney
  local tip = _G.GameTooltip
  local SEP = "  ·  "
  local function shown(rows) local out = {}; for _, r in ipairs(rows or {}) do if r.shown ~= false then out[#out + 1] = r end end return out end
  local function click(b) b.scripts.OnClick(b, "LeftButton"); M.settle() end
  local function pick(c, btn, label)
    if not (c.menu.shown and c.menu.anchor == btn) then click(btn) end
    for _, b in ipairs(c.menu.btns) do
      if b.shown ~= false and b.text.text == label then click(b); return true end
    end
    return false
  end
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
  local function inside(c, tbl)
    -- every shown cell of the table lies inside the list and no text is cut that the column should hold
    local cb = P.box(c)
    for _, r in ipairs(shown(tbl.rows)) do
      for _, fs in pairs(r.c or {}) do
        local b = P.box(fs)
        if b and (b.l < cb.l - 0.5 or b.l + b.w > cb.l + cb.w - UI.SCROLLBAR + 0.5) then return false, "cell past the list" end
      end
    end
    for _, h in pairs(tbl.head or {}) do
      local fs = h.text or h
      if type(fs) == "table" and fs.IsTruncated and fs:IsTruncated() then return false, "header cut: " .. tostring(fs.text) end
    end
    return true
  end

  for _, size in ipairs({ { 900, 580 }, { 1250, 760 } }) do
    local tag = ("Gold 0.9.47 %dx%d"):format(size[1], size[2])
    -- ── Zones ────────────────────────────────────────────────────────────────────────────────────────────────
    do
      local c = open(size[1], size[2], "zones")
      check(tag .. ": the view button offers Zones and Runs after the four views", Gold.VIEWS[5][2] == "Zones" and Gold.VIEWS[6][2] == "Runs" and c.viewBtn.text.text == "Zones")
      local rows = shown(c.tblZones.rows)
      check(tag .. ": Zones lists the TOTAL, each place and the evicted places", #rows == 5 and P.visible(c.tblZones.sf) and not P.visible(c.tblSrc.sf), #rows)
      local t, first, last = rows[1], rows[2], rows[5]
      check(tag .. ": the TOTAL row is pinned first and counts the evicted places", t.item.total and t.c.zone.text == "TOTAL" .. SEP .. "5 places" and t.c.looted.text == fmt(123456 + 2000 + 40 + 700)
        and t.c.quests.text == fmt(50300), t.c.zone.text .. " " .. t.c.looted.text)
      check(tag .. ": places by looted coin, the biggest first: name, looted, quests, played, per hour, last visit", first.c.zone.text == "Elwynn Forest" and first.c.looted.text == fmt(123456)
        and first.c.quests.text == fmt(50000) and first.c.played.text == "1h 30m" and first.c.rate.text == fmt(math.floor(173456 * 3600 / 5400 + 0.5)) and first.c.last.text == "today", first.c.played.text .. " " .. first.c.rate.text .. " " .. first.c.last.text)
      check(tag .. ": a place under 5 minutes has no rate, one the client named no map for is named so", rows[3].c.zone.text == "Westfall" and rows[3].c.rate.text == "" and rows[3].c.last.text == "3 d ago"
        and rows[4].c.zone.text == "Unknown place" and rows[4].c.played.text == "")
      check(tag .. ": the evicted places are one row at the end", last.item.evicted and last.c.zone.text == "2 earlier places" and last.c.looted.text == fmt(700) and last.c.last.text == "")
      check(tag .. ": the caption says whose and what is counted", c.caption.text:find("^Coin by place" .. SEP .. "this character") ~= nil and c.caption.text:find("looted coin and quest rewards", 1, true) ~= nil, c.caption.text)
      check(tag .. ": the Zones caption is shown in full", not c.caption:IsTruncated(), c.caption.text)
      local ok, why = inside(c, c.tblZones)
      check(tag .. ": every Zones cell is inside the list, no header cut", ok, why)
      -- hover
      tip:ClearLines(); first.scripts.OnEnter(first)
      local text = table.concat(tip.lines or {}, "\n")
      check(tag .. ": a place's hover names its coin, its map and what is not counted", text:find("Elwynn Forest", 1, true) ~= nil and text:find("Map 37", 1, true) ~= nil and text:find("Vendor sales and repairs are not counted by place", 1, true) ~= nil, text)
      first.scripts.OnLeave(first)
      -- sort by quests ascending: the TOTAL stays first, the evicted row last
      c.tblZones.head.quests.scripts.OnClick(c.tblZones.head.quests); M.settle()
      c.tblZones.head.quests.scripts.OnClick(c.tblZones.head.quests); M.settle()
      rows = shown(c.tblZones.rows)
      check(tag .. ": a sort keeps the TOTAL first and the evicted row last", rows[1].item.total and rows[5].item.evicted and c.st.zoneSort == "quests", c.st.zoneSort)
      c.st.zoneSort, c.st.zoneAsc = "looted", false; c.tblZones.setSort("looted", false)
      -- the realm or the account: still this character's places, and the caption says so
      c.setWho("account"); M.settle()
      check(tag .. ": with the account picked the places stay this character's", #shown(c.tblZones.rows) == 5 and c.caption.text:find("this character", 1, true) ~= nil)
      c.setWho("char"); M.settle()
      -- empty
      ns.char().goldZones, ns.char().goldZonesEvicted = nil, nil
      Gold.open("today", "zones"); M.settle()
      check(tag .. ": with no place yet the list says from when they are counted", #shown(c.tblZones.rows) == 0 and P.visible(c.tblZones.empty) and c.tblZones.empty.text:find("from addon 0.9.47 on", 1, true) ~= nil)
    end
    -- ── Runs ─────────────────────────────────────────────────────────────────────────────────────────────────
    do
      local c = open(size[1], size[2], "runs")
      local wide = (P.box(c).w - UI.SCROLLBAR) >= 980
      local tbl = wide and c.tblRuns or c.tblRunsNarrow
      local rows = shown(tbl.rows)
      check(tag .. ": Runs lists the TOTAL, the open run, the closed runs newest first and the evicted runs", #rows == 5 and P.visible(tbl.sf) and c.viewBtn.text.text == "Runs", #rows)
      check(tag .. ": the TOTAL row counts every run", rows[1].item.total and rows[1].c.inst.text == "TOTAL" .. SEP .. "7 runs" and rows[1].c.looted.text == fmt(5000 + 32000 + 100 + 9000), rows[1].c.inst.text)
      local openRow, dm, st = rows[2], rows[4], rows[3]
      check(tag .. ": the open run is first and says it is in progress", openRow.c.inst.text == "Shadowfang Keep" .. SEP .. "in progress" and openRow.c.length.text == "14m" and openRow.c.looted.text == fmt(5000))
      check(tag .. ": an item waiting for its price makes the loot value read \"so far\"", openRow.c.value.text == fmt(1234) .. " so far" and st.c.value.text == fmt(0) .. " so far", openRow.c.value.text)
      check(tag .. ": a closed run: time, dungeon, played, looted, quests and the loot value in its own column", dm.c.inst.text == "The Deadmines" and dm.c.time.text == date("%m/%d %H:%M", now - 3 * 86400)
        and dm.c.length.text == "1h 0m" and dm.c.looted.text == fmt(32000) and dm.c.quests.text == fmt(12000) and dm.c.value.text == fmt(51000), dm.c.value.text)
      if wide then
        check(tag .. ": wide: coin per hour is coin over the time played, never the loot value; items counted", dm.c.rate.text == fmt(44000) and dm.c.items.text == "14" and st.c.rate.text == "", dm.c.rate.text)
      else
        check(tag .. ": narrow: Coin per hour and Items are left out", dm.c.rate == nil and dm.c.items == nil and not P.visible(c.tblRuns.sf))
      end
      check(tag .. ": the evicted runs are one row at the end", rows[5].item.evicted and rows[5].c.inst.text == "4 earlier runs" and rows[5].c.time.text == "")
      check(tag .. ": the caption says the loot value is an estimate and never added to coin", c.caption.text:find("^Dungeon runs" .. SEP .. "this character") ~= nil and c.caption.text:find("estimate", 1, true) ~= nil and c.caption.text:find("never added to coin", 1, true) ~= nil, c.caption.text)
      check(tag .. ": the Runs caption is shown in full, to \"never added to coin\"", not c.caption:IsTruncated(), c.caption.text)
      check(tag .. ": the evicted runs' unpriced items make the TOTAL's loot value read \"so far\"", rows[1].c.value.text == fmt(1234 + 51000 + 0 + 3000) .. " so far" and rows[5].c.value.text == fmt(3000) .. " so far", rows[1].c.value.text .. " / " .. rows[5].c.value.text)
      local ok, why = inside(c, tbl)
      check(tag .. ": every Runs cell is inside the list, no header cut", ok, why)
      tip:ClearLines(); dm.scripts.OnEnter(dm)
      local text = table.concat(tip.lines or {}, "\n")
      check(tag .. ": a run's hover reads items, coin, loot value and coin per hour, and what the estimate is",
        text:find(("14 items%s%s coin%sloot value about %s%s%s/h"):format(SEP, fmt(44000), SEP, fmt(51000), SEP, Gold.fmt(44000, { rate = true })), 1, true) ~= nil
        and text:find("never added to coin or to a rate", 1, true) ~= nil, text)
      dm.scripts.OnLeave(dm)
      tip:ClearLines(); openRow.scripts.OnEnter(openRow)
      text = table.concat(tip.lines or {}, "\n")
      check(tag .. ": the open run's hover says how many items count 0 so far", text:find("2 items had no price loaded yet and count 0", 1, true) ~= nil and text:find("loot value so far about", 1, true) ~= nil, text)
      openRow.scripts.OnLeave(openRow)
      ns.char().goldRuns, ns.char().goldRunsEvicted, ns.char().goldRun = nil, nil, nil
      Gold.open("today", "runs"); M.settle()
      check(tag .. ": with no run yet the list says so", #shown(tbl.rows) == 0 and P.visible(tbl.empty) and tbl.empty.text:find("No dungeon runs yet", 1, true) ~= nil)
    end
    -- ── Days: the balance line, folded months ────────────────────────────────────────────────────────────────
    do
      local c = open(size[1], size[2], "days", "all")
      c.st.daySort, c.st.dayAsc = "day", false; c.tblDays.setSort("day", false); c.tblDaysNarrow.setSort("day", false)
      Gold.open("all", "days"); M.settle()
      check(tag .. ": Days shows the net strip first, and a button for the balance line", P.visible(c.dayStrip) and not P.visible(c.dayLine) and P.visible(c.chartBtn) and c.chartBtn.text.text == "Balance line")
      click(c.chartBtn)
      check(tag .. ": the button puts the balance line in the strip's place and names the way back", P.visible(c.dayLine) and not P.visible(c.dayStrip) and c.chartBtn.text.text == "Net per day")
      local lb, cb = P.box(c.dayLine), P.box(c)
      local days = c.wide and c.tblDays or c.tblDaysNarrow
      local hb = P.box(days.header)
      check(tag .. ": the line is as wide as the list and ends above the list's header", lb and lb.l >= cb.l and lb.l + lb.w <= cb.l + cb.w - UI.SCROLLBAR + 0.5 and lb.t + lb.h <= hb.t + 0.5, lb and (lb.t + lb.h) .. " " .. hb.t)
      local line = c.dayLine
      check(tag .. ": 30 slots, drawn across the whole width", line.n == 30 and math.abs(line.slot * 30 - lb.w) < 1 and #line.values == 30)
      check(tag .. ": days with a row are solid, carried days dashed, today solid", line.solid >= 2 and line.dashes > 0 and line.values[30].live == true and line.values[30].stale == false, line.solid .. " " .. line.dashes)
      check(tag .. ": the line's title and range", line.title.text == "BALANCE, LAST 30 DAYS" and line.range.text ~= "" and not line.range:IsTruncated(), line.range.text)
      -- a new width draws it again
      UI.SetWindowSize(size[1] + 80, size[2]); M.settle()
      check(tag .. ": a wider window draws the line again for its width", math.abs(c.dayLine.slot * 30 - P.box(c.dayLine).w) < 1)
      UI.SetWindowSize(size[1], size[2]); M.settle()
      click(c.chartBtn)
      check(tag .. ": the button brings the net strip back", P.visible(c.dayStrip) and not P.visible(c.dayLine) and c.chartBtn.text.text == "Balance line")
      Gold.open("all", "sources"); M.settle()
      check(tag .. ": the chart button is only in the Days view", not P.visible(c.chartBtn) and not P.visible(c.dayLine))
      -- folded months: rows of their own under the days, not clickable
      local me = ns.char()
      local oldest
      for k in pairs(me.goldDays) do if not oldest or k < oldest then oldest = k end end
      local o = me.goldDays[oldest].o or 0
      me.goldMonths = { ["201901"] = { g = 900000, s = 100000, t = 36000, n = 300, d = 28, looted = 900000, repairs = 100000, o = o - 1000000, c = o - 200000 },
        ["201902"] = { g = 300000, s = 100000, t = 7200, n = 90, d = 12, quests = 300000, vendor = 100000, o = o - 200000, c = o } }
      Gold.open("all", "days"); M.settle()
      local rows = shown(days.rows)
      local folded, lastData = {}, nil
      for _, r in ipairs(rows) do
        if r.item and r.item.folded then folded[#folded + 1] = r end
        if r.item and not r.item.ebSection then lastData = r end
      end
      check(tag .. ": the folded months are rows under the days, newest first, with their days counted", #folded == 2 and folded[1].c.day.text == "Feb 2019, 12 days" and folded[2].c.day.text == "Jan 2019, 28 days"
        and lastData == folded[2], (folded[1] and folded[1].c.day.text or "?") .. " / " .. tostring(lastData and lastData.c.day.text))
      check(tag .. ": a month row reads earned, spent, net and its closing balance", folded[2].c.earned.text == fmt(900000) and folded[2].c.spent.text == fmt(100000) and folded[2].c.net.text == Gold.signed(800000)
        and folded[2].c.bal.text == fmt(o - 200000))
      check(tag .. ": All time sums the months with the days", c.cIn.value.text == fmt(me.gold.gained) and Gold.period("history", "char").ledger.gained >= 1200000)
      local scopeBefore = c.st.scope
      folded[1].scripts.OnClick(folded[1], "LeftButton"); M.settle()
      check(tag .. ": a click on a month row opens nothing", c.st.scope == scopeBefore and c.st.view == "days")
      tip:ClearLines(); folded[1].scripts.OnEnter(folded[1])
      local text = table.concat(tip.lines or {}, "\n")
      check(tag .. ": its hover says why it is a month", text:find("folded into their month", 1, true) ~= nil and text:find("Click to open", 1, true) == nil, text)
      folded[1].scripts.OnLeave(folded[1])
      -- the records on the status line of the Days view
      me.goldBest = { day = { key = "20261115", net = 123400 }, session = { at = now - 86400, net = 56700 } }
      Gold.open("all", "days"); M.settle()
      check(tag .. ": the Days view names the best day and the best session", c.status.text:find("Best day Nov 15 " .. Gold.signed(123400), 1, true) ~= nil and c.status.text:find("best session", 1, true) ~= nil, c.status.text)
    end
    -- ── the status line: reconciled, broken, not checkable ───────────────────────────────────────────────────
    do
      -- reconciled: a character played from zero through the real handlers
      local c = open(size[1], size[2], "sources", "today")
      local back = playFromZero()
      local MARK = Gold.AUDIT_MARK .. " Reconciled"
      for _, scope in ipairs({ "today", "all" }) do
        Gold.open(scope, "sources"); M.settle()
        local a = c.audit
        check(tag .. ": " .. scope .. ": a character played from zero reconciles", a ~= nil and a.state == "ok" and a.key == (scope == "all" and "history" or scope) and a.checks >= 1, a and tostring(a.text or a.reason))
        check(tag .. ": " .. scope .. ": a period that adds up ends its status line with a quiet check mark", c.status.text:sub(-#MARK) == MARK and P.visible(c.statusRow) and P.visible(c.status), c.status.text)
        check(tag .. ": " .. scope .. ": the status line is shown in full and says nothing in red", not c.status:IsTruncated() and c.status.text:find("do not add up", 1, true) == nil, c.status.text)
        tip:ClearLines(); c.statusRow.scripts.OnEnter(c.statusRow)
        local text = table.concat(tip.lines or {}, "\n")
        check(tag .. ": " .. scope .. ": its hover shows the identities", text:find("^Reconciled") ~= nil and text:find("closing minus opening balance = earned minus spent plus changed while away", 1, true) ~= nil, text)
        c.statusRow.scripts.OnLeave(c.statusRow)
      end
      check(tag .. ": the reconciled character's cards read what was played", c.cIn.value.text == fmt(2340) and c.cOut.value.text == fmt(450), c.cIn.value.text .. " " .. c.cOut.value.text)
      back()
      -- the played data: changes while away in every period, so not checkable, and never a break
      c = open(size[1], size[2], "sources", "session")
      local a = c.audit
      check(tag .. ": the running session of the gold data is audited", a ~= nil and a.key == "session", a and a.state)
      check(tag .. ": a period that cannot be checked says nothing more", a and a.state == "unknown" and c.status.text:find("Reconciled", 1, true) == nil and c.status.text:find("do not add up", 1, true) == nil, a and tostring(a.text))
      for _, scope in ipairs({ "all", "today", "yesterday", "week", "month", "last30" }) do
        Gold.open(scope, "sources"); M.settle()
        local b = c.audit
        check(tag .. ": " .. scope .. " on the played data does not read broken", b ~= nil and b.state == "unknown" and c.status.text:find("do not add up", 1, true) == nil and c.status.text:find("Reconciled", 1, true) == nil
          and not c.status:IsTruncated(), b and tostring(b.text or b.reason))
      end
      Gold.open("all", "sources"); M.settle()
      check(tag .. ": All time on the played data says why it is not checkable", c.audit.reason:find("changed while away", 1, true) ~= nil, c.audit.reason)
      Gold.open("session", "sources"); M.settle()
      -- a break: red, short, first of what the line says; the hover and the command say where
      local ses = ns.Recorder.current()
      ses.gold.other = (ses.gold.other or 0) + 1
      Gold.open("session", "sources"); M.settle()
      check(tag .. ": a break is said in red on the status line", c.audit.state == "broken" and c.status.text:find("|cff%x%x%x%x%x%x" .. Gold.AUDIT_BROKEN:gsub("%p", "%%%0") .. "|r") == 1 and c.status.text:find("Reconciled", 1, true) == nil, c.status.text)
      tip:ClearLines(); c.statusRow.scripts.OnEnter(c.statusRow)
      local text = table.concat(tip.lines or {}, "\n")
      check(tag .. ": the hover names the break", text:find("Unexplained spending", 1, true) ~= nil and text:find("The gold records do not add up", 1, true) == 1, text)
      c.statusRow.scripts.OnLeave(c.statusRow)
      ses.gold.other = ses.gold.other - 1
      -- another character's totals are never audited here
      Gold.open("today", "sources"); M.settle()
      c.setWho("account"); M.settle()
      check(tag .. ": a realm or account period carries no audit", c.audit == nil and c.status.text:find("Reconciled", 1, true) == nil)
      c.setWho("char"); M.settle()
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
    eq("Dungeons: a run reads items, coin, loot value and coin per hour from its own gold block", dv.lootLine,
      ("Coin looted %s · vendor price of items %s · %s per hour"):format(ns.UI.money(32000), ns.UI.money(51000), ns.UI.money(64000, true)))
    local function onPage(text)
      local found, cutOff = false, false
      for _, fs in ipairs(dv.lines) do
        if fs.shown ~= false and fs.text == text then found = true; if fs.IsTruncated and fs:IsTruncated() then cutOff = true end end
      end
      return found and not cutOff
    end
    check("Dungeons: the line is on the run's page in full at 900 px", onPage(dv.lootLine))
    check("Dungeons: no purse line while the looted coin is what the purse gained", dv.purseLine == nil)
    check("Dungeons: the clocks of the run are two lines, in full", dv.timeLine == "Inside 30m 0s" and dv.timeLine2 == "Active 30m 0s" and onPage(dv.timeLine) and onPage(dv.timeLine2), dv.timeLine)
    -- the list row of the run reads the same block as its page
    local function listRow()
      local lv = ns._test.dungeonList(); M.settle()
      for _, r in ipairs(lv and lv.tbl and lv.tbl.rows or {}) do
        if r.shown ~= false and r.run and r.run.id == rec.id then return r end
      end
    end
    local row = listRow()
    eq("Dungeons: the list row of that run reads the block's items", row and row.c.loot.text, "12 items")
    eq("Dungeons: and its coin looted (a WIDE column)", row and row.c.coin.text, ns.UI.money(32000))
    eq("Dungeons: and no XP per hour while the run has no XP", row and row.c.xph.text, "-")
    -- the purse gained more inside than was booked as looted (group shares booked as mail, seen 2026-11-18)
    rec.gold.looted, rec.gold.purse = 365, 11253
    rec.xp = { gain = 12300, kill = 9000, quest = 0, n = 45, l0 = 23, p0 = 0.4, l1 = 24, p1 = 0.1, need = 30000 }
    rec.hidden = { xp = 12 }
    ns._test.renderRun(view()); M.settle()
    eq("Dungeons: the page says when the looted coin is not what the purse gained", dv.purseLine, ("Coin %s of %s gained inside"):format(fmt(365), fmt(11253)))
    check("Dungeons: that line is on the page in full", onPage(dv.purseLine))
    eq("Dungeons: the XP line reads XP, XP per hour, the levels and the runs the next level takes", dv.xpLine,
      "12,300 XP, all from kills")
    eq("Dungeons: the rate, the levels, the runs the next level takes and the kills (a lower bound) are the line under it", dv.xpMore,
      "24,600 per hour · level 23.4 to 24.1 · about 3 more runs to level 25 · at least 45 kills")
    check("Dungeons: the XP lines and the hidden-lines note are on the page in full", onPage(dv.xpLine) and onPage(dv.xpMore) and onPage("12 XP lines were hidden by the client."))
    row = listRow()
    eq("Dungeons: the list row reads XP per hour while the run has XP", row and row.c.xph.text, "24,600")
    table.remove(list)
  end
  ns.Recorder.current = savedCurrent
end
