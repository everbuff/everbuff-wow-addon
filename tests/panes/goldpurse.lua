-- Pane tests: gold with the purses players really have (everbuff-wow-addon #49). The suite's purse used to be small
-- (123g, alts under 100g), so a column that only fits a small balance passed: Loot / Gold / Characters ran 2 px past
-- its list at 1250x760 once a balance went above 1,000g. Here every gold surface is laid out around balances above
-- 10,000g (the data as played, the alts up to the Classic cap of 214,748g) and above 1,000,000g (the long data, the
-- alts up to 9,999,999g), at the three window sizes:
--   Gold pane   every breakdown, today and all time, and Characters for the account: no text past its box or over
--               another, every cell inside the column, no number shortened, the cards' labels and amounts in full
--   elsewhere   the Overview gold card, the Sessions gold band, the pill and its tooltip
return function(P)
  local check, M, ns = P.check, P.M, P.ns
  local UI, Gold = ns.UI, ns.Gold
  local fmt = ns.fmtMoney
  local tip = _G.GameTooltip
  local DAY = 86400
  local function click(b) b.scripts.OnClick(b, "LeftButton"); M.settle() end
  local savedCurrent = ns.Recorder.current
  ns.Recorder.current = function() return ns.DB.active and ns.DB.sessions[ns.DB.active] or nil end
  local realPrint = print
  print = function() end

  -- the alts, the places and the runs of the data in use, as rich as the data: BIG is one large amount of copper
  local BIG
  local function rich(data)
    local long = data == "goldlong"
    BIG = long and 12345678912 or 123456789
    local cap = long and 99999999999 or 2147483647
    local base, now = Gold.baseStored(), GetServerTime()
    local me = ns.char()
    for guid in pairs(ns.DB.characters) do if guid ~= ns.charGuid() and guid ~= "Player-1-0000A1" then ns.DB.characters[guid] = nil end end
    local g, s = math.floor(BIG / 2), math.floor(BIG / 5)
    ns.DB.characters["Player-1-0000B1"] = { name = "Mira", surname = "Dawnfall", realm = GetRealmName(), class = "WARRIOR", faction = "Alliance", level = 21, seen = now - 3 * DAY,
      gold = { balance = BIG, gained = BIG, spent = 0 },
      goldDays = { [Gold.dayKey(now, base)] = { g = g, s = s, o = BIG - (g - s), c = BIG, t = 900, n = 3, looted = g, repairs = s, away = 0 } } }
    ns.DB.characters["Player-1-0000B2"] = { name = "Orgrim", realm = "Forever Realm [EU] - Other Shore", class = "SHAMAN", faction = "Horde", level = 40, seen = now - 100 * DAY,
      gold = { balance = cap, gained = cap, spent = 0 } }
    ns.DB.characters["Player-1-0000B3"] = { name = "Zulrik", realm = GetRealmName(), class = "HUNTER", faction = "Horde", level = 60, seen = now - 2 * 3600,
      gold = { balance = cap, gained = cap, spent = 0 } }
    ns.DB.characters["Player-1-0000A1"].gold = { balance = BIG + 7777 }
    me.goldZones = {
      [37] = { looted = BIG, quests = g, secs = 5400, last = now - 600, name = "Elwynn Forest" .. (long and " of the Scarlet Monastery Cathedral" or "") },
      [52] = { looted = cap, quests = 0, secs = 3599999, last = now - 30 * DAY, name = "Westfall" },
      [0] = { looted = 40, quests = 0, secs = 0, last = now - 40 * DAY },
    }
    me.goldRun = { t = now - 900, inst = "Shadowfang Keep" .. (long and " of the Scarlet Monastery Cathedral" or ""), secs = 840, looted = BIG, quests = g, lootValue = BIG, items = 999, wait = { [9003] = 2 } }
    me.goldRuns = {
      { t = now - 3 * DAY, inst = "The Deadmines", secs = 359940, looted = cap, quests = BIG, lootValue = cap, items = 999 },
      { t = now - 2 * DAY, inst = "Sunken Temple", secs = 120, looted = 100, quests = 0, lootValue = 0, items = 1, unpriced = 1 },
    }
    return me
  end
  local function audit(tag)
    local found = {}
    for _, x in ipairs(P.Lay.audit(M.frames)) do found[#found + 1] = ("%s: %s (%s)"):format(x.kind, x.text, x.detail) end
    check(tag .. ": no text spills out of its box, over another text, or a number cut short", #found == 0, table.concat(found, " || "):sub(1, 500))
  end
  -- every table showing under `root`: its header and every cell end inside the list, and no number is shortened
  local function tables(tag, root)
    local bad, n = {}, 0
    for _, sf in ipairs(P.scrollFrames(root)) do
      local tbl = sf.ebTable
      if tbl and tbl.shownN > 0 then
        n = n + 1
        local sfb = P.box(sf)
        local right = sfb.l + sfb.w + 0.5
        for _, col in ipairs(tbl.spec) do
          local hb = tbl.head[col.key]
          local fb = hb and hb.fs and P.box(hb.fs)
          if fb and fb.l + fb.w > right then bad[#bad + 1] = "header " .. col.key .. " past the list" end
        end
        for i = 1, tbl.shownN do
          local r = tbl.rows[i]
          if r.shown ~= false and r.item and not r.item.ebSection then
            for _, col in ipairs(tbl.spec) do
              local cell = r.c[col.key]
              if col.kind ~= "icon" then
                local b = P.box(cell)
                if b and b.l + b.w > right then bad[#bad + 1] = ("row %d %s past the list by %d px"):format(i, col.key, math.ceil(b.l + b.w - right)) end
                if (col.kind == "money" or col.kind == "num" or col.kind == "tag") and cell:IsTruncated() then bad[#bad + 1] = ("row %d %s shortened: %s"):format(i, col.key, tostring(cell.text)) end
              end
            end
          end
        end
      end
    end
    check(tag .. ": every header and cell ends inside the list, every number in full", #bad == 0, table.concat(bad, "; "):sub(1, 500))
    return n
  end
  -- the Gold pane's tables (UI.KitTable, one page scroll): every cell inside the column, no number shortened
  local function kitTables(tag, c)
    local bad, n = {}, 0
    local colR = P.box(c.col).l + P.box(c.col).w + 0.5
    for key, tbl in pairs(c.tbl) do
      if P.visible(tbl.frame) and tbl.shownN > 0 then
        n = n + 1
        for i = 1, tbl.shownN do
          local r = tbl.rows[i]
          if r.shown ~= false and r.item and not r.item.ebSection then
            for _, col in ipairs(tbl.spec) do
              local cell = r.c[col.key]
              if cell and tbl.cols[col.key] then
                local b = P.box(cell)
                if b and b.l + b.w > colR then bad[#bad + 1] = ("%s row %d %s past the column by %d px"):format(key, i, col.key, math.ceil(b.l + b.w - colR)) end
                if (col.kind == "money" or col.kind == "num") and cell:IsTruncated() then bad[#bad + 1] = ("%s row %d %s shortened: %s"):format(key, i, col.key, tostring(cell.text)) end
              end
            end
          end
        end
      end
    end
    check(tag .. ": every cell ends inside the column, every number in full", #bad == 0, table.concat(bad, "; "):sub(1, 500))
    return n
  end
  local function cards(tag, c)
    local bad = {}
    local colB = P.box(c.col)
    for i, cd in ipairs(c.shownCards) do
      local b = P.box(cd)
      if b.l < colB.l - 0.5 or b.l + b.w > colB.l + colB.w + 0.5 then bad[#bad + 1] = i .. " outside the column" end
      for _, part in ipairs({ "label", "value" }) do
        if cd[part]:IsTruncated() then bad[#bad + 1] = i .. "." .. part .. " shortened: " .. tostring(cd[part].text) end
      end
    end
    check(tag .. ": the cards hold their labels and amounts in full", #bad == 0, table.concat(bad, "; "):sub(1, 500))
  end

  for _, size in ipairs({ { 900, 580 }, { 1250, 760 }, { 1600, 1000 } }) do
    for _, data in ipairs({ "gold", "goldlong" }) do
      local tag = ("Gold purse %dx%d %s"):format(size[1], size[2], data)
      local c = P.open("loot", "gold", size[1], size[2], data)
      local me = rich(data)
      check(tag .. ": the purse of the data is a real one (above 10,000g, above 1,000,000g on the long data)", me.gold.balance >= (data == "goldlong" and 1e10 or 1e8), me.gold.balance)
      for _, v in ipairs(Gold.VIEWS) do
        local view = v[1]
        -- this character, today
        Gold.open("today", view); M.settle()
        local vt = ("%s %s"):format(tag, v[2])
        check(vt .. ": the view is open (Sources gives way to Journal when the period holds dungeon time from before 0.9.52)", c.st.view == view and (c.view == view or (view == "sources" and c.srcOff ~= nil and c.view == "journal")) and c.viewSeg.value == c.view, c.view)
        local n = kitTables(vt, c)
        check(vt .. ": its list has rows", n >= 1 or view == "journal" or view == "sources" or view == "auctions", n)
        cards(vt, c)
        audit(vt)
        -- all time
        Gold.open("all", view); M.settle()
        vt = vt .. ", all time"
        kitTables(vt, c)
        cards(vt, c)
        audit(vt)
      end
      -- BALANCE's meta holds every character's gold in full, or steps down without cutting a number
      Gold.open("today"); M.settle()
      local meta = c.shownCards[1].meta
      check(tag .. ": BALANCE's meta is not cut inside its number", not meta:IsTruncated() and (meta:GetText():find("^all ") ~= nil or (c.audit.state == "broken" and meta:GetText() == "records do not add up")), meta:GetText())

      -- the Overview gold card and the Sessions gold band on the same purses
      for _, page in ipairs({ "overview", "sessions" }) do
        local h = P.open("home", page, size[1], size[2], data)
        rich(data)
        ns.UI.Open("Loot", "gold"); M.settle(); ns.UI.Open("Home", page); M.settle()
        local pt = ("%s Home %s"):format(tag, page)
        if page == "overview" then
          -- the GOLD card is this session's net; the balance and what every character holds are in its tooltip
          local p = h.cards.cards[3]
          local roAll = Gold.roster("all")
          local tip = p.ebTip or {}
          check(pt .. ": the Gold card's tooltip names the balance and what every character holds, in full", tip.pairs and tip.pairs[1][2] == ns.fmtMoney(me.gold.balance, { icons = true })
            and (roAll.count < 2 or (tip.pairs[2] and tip.pairs[2][2] == ns.fmtMoney(roAll.total, { icons = true }))) and not p.value:IsTruncated() and not p.meta:IsTruncated(), tostring(p.value.text))
          local pb, vb = P.box(p), P.box(p.value)
          check(pt .. ": the value stays inside the card", vb.l + P.G.naturalWidth(p.value) <= pb.l + pb.w + 0.5, ("%s %s"):format(vb.l + P.G.naturalWidth(p.value), pb.l + pb.w))
        end
        tables(pt, h)
        audit(pt)
      end
    end
  end

  -- ── the pill and its tooltip ────────────────────────────────────────────────────────────────────────────────
  for _, data in ipairs({ "gold", "goldlong" }) do
    local tag = "Gold purse pill " .. data
    P.open("loot", "gold", 900, 580, data)
    rich(data)
    Gold.pillOn(true)
    local p = Gold.pill
    local bad = {}
    for _, m1 in ipairs({ "balance", "total", "today" }) do
      for _, label in ipairs({ false, true }) do
        Gold.pillSet(1, m1); Gold.pillSet(2, m1 == "total" and "balance" or "total"); Gold.pillOpt("label", label); M.settle()
        local b = P.box(p)
        local name = m1 .. (label and " labelled" or "")
        if not b then bad[#bad + 1] = name .. " not placed"
        else
          if p.text:IsTruncated() or P.G.naturalWidth(p.text) > b.w - 2 * UI.SP.S + 0.5 then bad[#bad + 1] = name .. " text cut: " .. tostring(p.text.text) end
          if b.l < -0.5 or b.l + b.w > P.G.VIEW.w + 0.5 then bad[#bad + 1] = name .. " off screen" end
        end
      end
    end
    check(tag .. ": as wide as its amounts, inside the screen, for one and two values, with and without labels", #bad == 0, table.concat(bad, "; "))
    Gold.pillSet(1, "balance"); Gold.pillSet(2, "total"); M.settle()
    check(tag .. ": it shows the balance and the total of every character", tostring(p.text.text):find("%d,%d%d%d") ~= nil, tostring(p.text.text))
    Gold.pillTip(p)
    local text = table.concat(tip.lines or {}, " | ")
    check(tag .. ": its tooltip lists the characters with their purses", #(tip.lines or {}) >= 4 and text:find("Mira", 1, true) ~= nil and text:find("%d,%d%d%d") ~= nil, text:sub(1, 300))
    if tip.Hide then tip:Hide() end
    Gold.pillSet(2, nil); Gold.pillOpt("label", false)
    Gold.pillOn(false)
  end

  Gold._tipOwner, Gold._tipRedo, Gold._pillDirty, Gold._openAfter = nil, nil, nil, nil
  ns.Recorder.current = savedCurrent
  print = realPrint
  UI.SetWindowSize(900, 580)
  check("Gold purse: no errors from the panes' resize or events", #UI.paneErrors() == 0, table.concat(UI.paneErrors(), " || "))
end
