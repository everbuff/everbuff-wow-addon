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
    -- ── the views cut by docs/UX_PRAGMATIC.md 4.2: Zones, Runs, Days and Characters are not screens any more ──
    do
      local c = open(size[1], size[2], "zones")
      local views = {}
      for i, v in ipairs(Gold.VIEWS) do views[i] = v[2] end
      eq(tag .. ": the views are Sources, Auction house and Journal", table.concat(views, ","), "Sources,Auction house,Journal")
      check(tag .. ": the key of a view that is gone opens Sources", c.st.view == "sources" and c.tbl.zones == nil and c.tbl.runs == nil and c.tbl.days == nil and c.tbl.chars == nil, c.st.view)
      check(tag .. ": the places and runs are still counted (Dungeons reads the runs)", type(Gold.zones) == "function" and type(Gold.runs) == "function" and #Gold.zones().rows >= 1 and #Gold.runs().rows >= 1)
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
        check(tag .. ": " .. scope .. ": nothing on the page says they do not", (c.shownCards[1].meta:GetText() or ""):find("do not add up", 1, true) == nil)
      end
      check(tag .. ": the reconciled character's cards read what was played", c.shownCards[2].value:GetText() == money(2340, true) and c.shownCards[3].value:GetText() == money(-450, true), c.shownCards[2].value:GetText())
      back()
      -- the played data: changes while away in every period, so not checkable, and never a break
      c = open(size[1], size[2], "sources", "session")
      check(tag .. ": the running session of the gold data is audited and cannot be checked", c.audit ~= nil and c.audit.key == "session" and c.audit.state == "unknown" and (c.shownCards[1].meta:GetText() or ""):find("do not add up", 1, true) == nil)
      for _, scope in ipairs({ "all", "today", "yesterday", "week", "month", "last30" }) do
        Gold.open(scope, "sources"); M.settle()
        check(tag .. ": " .. scope .. " on the played data does not read broken", c.audit ~= nil and c.audit.state == "unknown" and (c.shownCards[1].meta:GetText() or ""):find("do not add up", 1, true) == nil, c.audit and tostring(c.audit.reason))
      end
      -- a break: BALANCE's meta says so, muted, never red; its hover says where
      Gold.open("session", "sources"); M.settle()
      local ses = ns.Recorder.current()
      ses.gold.other = (ses.gold.other or 0) + 1
      Gold.open("session", "sources"); M.settle()
      local meta = c.shownCards[1].meta
      check(tag .. ": a break is said on the BALANCE card, in fgMuted", c.audit.state == "broken" and meta:GetText() == "records do not add up" and not meta:IsTruncated() and colorIs(meta, "fgMuted"), meta:GetText())
      local text = tipOf(c.shownCards[1])
      check(tag .. ": the hover names the break", text:find("Spending not explained", 1, true) ~= nil and text:find("do not add up", 1, true) ~= nil, text)
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
    check("Dungeons: the run's page has no clock lines and no ENTERED AND LEFT section: the TIME card has the time", dv.timeLine == nil and dv.timeLine2 == nil and dv.visitsShown == false
      and dv.sections.visits.shown == false and not onPage("Inside 30m 0s") and not onPage("Active 30m 0s") and dv.card.time.value.text == "30m", dv.card.time.value.text)
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
    -- (Maraudon, 18 Nov: 3s 65c booked, 1g 12s 53c gained. The card's coin is the purse figure, the hover says so.)
    eq("Dungeons: WORTH counts the purse figure when it is more than the booked coin", dv.card.worth.value.text, ns.UI.money(11253 + 51000))
    eq("Dungeons: and names it as the coin", ns.Dungeons.D.worthParts(view()), ("%s coin · %s items at vendor prices"):format(ns.UI.money(11253), ns.UI.money(51000)))
    eq("Dungeons: the WORTH hover says where the coin comes from and what was booked as loot", dv.purseTip,
      ("Coin is what your purse gained inside, quest rewards aside: %s. Of it %s was seen as loot when it was picked up."):format(fmt(11253), fmt(365)))
    eq("Dungeons: the list row reads the same worth as the page", listRow() and listRow().c.worth.text, ns.UI.money(11253 + 51000))
    do
      -- the purse gained less than was booked (coin was spent inside): the coin stays the booked figure
      local keepP = rec.gold.purse
      rec.gold.looted, rec.gold.purse = 5000, 3000
      local D = ns.Dungeons.D
      local c1, how1 = D.coinOf(view())
      check("Dungeons: a purse that gained less than was booked leaves the booked coin", c1 == 5000 and how1 == "looted" and (D.worth(view())) == 5000 + 51000
        and D.purseTip(view()) == ("Your purse grew by %s inside, quest rewards aside. Looted coin was %s."):format(fmt(3000), fmt(5000)), tostring(c1))
      rec.gold.purse = nil
      local c2, how2 = D.coinOf(view())
      check("Dungeons: a record with no purse figure reads its booked coin, and has no hover line", c2 == 5000 and how2 == "looted" and D.purseTip(view()) == nil)
      rec.gold.looted, rec.gold.purse = 365, keepP
    end
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
