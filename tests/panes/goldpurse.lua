-- Pane tests: gold with the purses players really have (everbuff-wow-addon #49). The suite's purse used to be small
-- (123g, alts under 100g), so a column that only fits a small balance passed: Loot / Gold / Characters ran 2 px past
-- its list at 1250x760 once a balance went above 1,000g. Here every gold surface is laid out around balances above
-- 10,000g (the data as played, the alts up to the Classic cap of 214,748g) and above 1,000,000g (the long data, the
-- alts up to 9,999,999g), at the three window sizes:
--   Gold pane   Sources, Journal, Days, Characters, Zones and Runs, for this character and for the account: no text
--               past its box or over another, every cell inside the list, no number shortened, the cards, the
--               status line and the caption in full
--   elsewhere   the Overview gold card, the Sessions gold band, the pill and its tooltip
return function(P)
  local check, M, ns = P.check, P.M, P.ns
  local UI, Gold = ns.UI, ns.Gold
  local fmt = ns.fmtMoney
  local tip = _G.GameTooltip
  local DAY = 86400
  local function click(b) b.scripts.OnClick(b, "LeftButton"); M.settle() end
  local function pick(c, btn, label)
    if not (c.menu.shown and c.menu.anchor == btn) then click(btn) end
    for _, b in ipairs(c.menu.btns) do
      if b.shown ~= false and b.text.text == label then click(b); return true end
    end
    c.menu:Hide()
    return false
  end
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
  local KEYS = { "cBalance", "cIn", "cOut", "cNet", "cRate" }
  local function cards(tag, c)
    local bad = {}
    local cb = P.box(c)
    for _, k in ipairs(KEYS) do
      local p = c[k]
      local b = P.box(p)
      if b.l < cb.l - 0.5 or b.l + b.w > cb.l + cb.w + 0.5 then bad[#bad + 1] = k .. " outside the pane" end
      for _, part in ipairs({ "title", "value" }) do
        if p[part]:IsTruncated() then bad[#bad + 1] = k .. "." .. part .. " shortened: " .. tostring(p[part].text) end
        local fb = P.box(p[part])
        if fb.l < b.l + UI.SP.S - 0.5 or fb.l + P.G.naturalWidth(p[part]) > b.l + b.w - UI.SP.S + 0.5 then bad[#bad + 1] = k .. "." .. part .. " outside the padding" end
      end
    end
    if c.caption:IsTruncated() then bad[#bad + 1] = "caption shortened: " .. tostring(c.caption.text) end
    if P.visible(c.statusRow) and c.status:IsTruncated() then bad[#bad + 1] = "status line shortened" end
    check(tag .. ": the cards hold their amounts in full, the caption and the status line are in full", #bad == 0, table.concat(bad, "; "):sub(1, 500))
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
        check(vt .. ": the view is open", c.st.view == view and c.viewBtn.text.text == v[2], c.st.view)
        local n = tables(vt, c)
        check(vt .. ": its list has rows", n >= 1 or view == "journal" or view == "sources", n)
        cards(vt, c)
        audit(vt)
        -- the account, all time (Zones and Runs are this character's: the pane says so and stays laid out)
        Gold.open("all", view); M.settle()
        pick(c, c.whoBtn, "Account")
        vt = vt .. ", account, all time"
        tables(vt, c)
        cards(vt, c)
        audit(vt)
        pick(c, c.whoBtn, "This character")
      end
      -- Characters with the characters not seen in 90 days counted, at its fullest: the widest TOTAL row
      Gold.open("today", "chars"); M.settle()
      if P.visible(c.staleBtn) then click(c.staleBtn) end
      local ct = P.visible(c.tblChars.sf) and c.tblChars or c.tblCharsNarrow
      local total = ct.rows[1]
      local ro = c.rosterData
      check(tag .. " Characters: the TOTAL row holds every purse in full, the hint of a character not seen since the update too", total.item.total == true and total.c.balance.text == fmt(ro.total)
        and not total.c.balance:IsTruncated() and ro.total > 2 * BIG and (function()
          for i = 1, ct.shownN do local r = ct.rows[i]; if r.c.seen.text == "log in once to refresh" then return not r.c.seen:IsTruncated() end end
          return false
        end)(), total.c.balance.text)
      tables(tag .. " Characters, everyone counted", c)
      audit(tag .. " Characters, everyone counted")
      if P.visible(c.staleBtn) then click(c.staleBtn) end

      -- the Overview gold card and the Sessions gold band on the same purses
      for _, page in ipairs({ "overview", "sessions" }) do
        local h = P.open("home", page, size[1], size[2], data)
        rich(data)
        ns.UI.Open("Loot", "gold"); M.settle(); ns.UI.Open("Home", page); M.settle()
        local pt = ("%s Home %s"):format(tag, page)
        if page == "overview" then
          local p = h.cGold
          local roAll = Gold.roster("all")
          check(pt .. ": the Gold card says the balance and what every character holds, in full", p.value.text == fmt(me.gold.balance) and not p.value:IsTruncated() and not p.sub:IsTruncated()
            and p.sub2On == true and p.sub2.text == "all characters " .. fmt(roAll.total) and not p.sub2:IsTruncated(), tostring(p.value.text) .. " | " .. tostring(p.sub2.text))
          local pb, vb, s2 = P.box(p), P.box(p.value), P.box(p.sub2)
          check(pt .. ": both stay inside the card", vb.l + P.G.naturalWidth(p.value) <= pb.l + pb.w + 0.5 and s2.t + s2.h <= pb.t + pb.h + 0.5, ("%s %s"):format(vb.l + P.G.naturalWidth(p.value), pb.l + pb.w))
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
