-- Pane tests: every other list on the layout framework (plan step 8). Home / Overview, Timeline and Sessions; Character /
-- Quests, Reputation and Professions; Combat / Dungeons (list and run), Fights (list, replay and a member's view) and
-- Deaths. At 900x580 and 1600x1000 on normal and long data, for every UI.Table a pane shows: the rows span the list,
-- the list is as tall as its rows, header x == cell x, numbers right-aligned (headers too) and never shortened, every
-- column ends inside the list; for every region of the pane: its anchor points agree (a LEFT and a RIGHT point on two
-- different rows put a text in the middle of the pane in the client), and no text runs past the pane's right edge.
-- Then what each pane adds: section rows, the header-less feed, the card grid, the stacked lists, the detail pages
-- laid out again for a new width.
return function(P)
  local check, eq, M, ns, T = P.check, P.eq, P.M, P.ns, P.T
  local UI = ns.UI
  local function near(a, b, tol) return a and b and math.abs(a - b) <= (tol or 0.51) end
  local function shownRows(tbl) local out = {}; for _, r in ipairs(tbl.rows) do if r.shown ~= false then out[#out + 1] = r end end return out end
  local function host(name) for _, t in ipairs(T.tabs) do if t.name == name then return t end end end

  -- the tables a pane shows (UI.Table registers itself on its scroll frame)
  local function tablesIn(content)
    local out = {}
    for _, sf in ipairs(P.scrollFrames(content)) do if rawget(sf, "ebTable") then out[#out + 1] = sf.ebTable end end
    return out
  end

  -- every anchor point of `f` lands where its resolved box says: two points that disagree are a conflict
  local function pointOn(b, p)
    local x = p:find("LEFT") and b.l or p:find("RIGHT") and (b.l + b.w) or (b.l + b.w / 2)
    local y = p:find("TOP") and b.t or p:find("BOTTOM") and (b.t + b.h) or (b.t + b.h / 2)
    return x, y
  end
  local function anchorConflict(f)
    local pts = rawget(f, "_pts")
    if not pts or #pts < 2 then return nil end
    local b = P.box(f)
    if not b then return nil end
    for _, a in ipairs(pts) do
      local rb = P.box(a.rel or f.parentFrame)
      if rb then
        local rx, ry = pointOn(rb, a.rp)
        local wx, wy = pointOn(b, a.p)
        if not near(rx + a.x, wx, 1) or not near(ry - a.y, wy, 1) then
          return ("%s %s->%s wants %d,%d, box puts it at %d,%d"):format(tostring(f._src or ""), a.p, a.rp, rx + a.x, ry - a.y, wx, wy)
        end
      end
    end
  end

  -- the generic checks of one opened pane
  local function audit(tag, content)
    local cb = P.box(content)
    local conflicts, spill = {}, {}
    for _, f in ipairs(P.descendants(content)) do
      if P.visible(f) then
        local c = anchorConflict(f)
        if c then conflicts[#conflicts + 1] = c end
        -- a filter tab's label is left out: UI.Tabs sizes its buttons once, at build, from the font the suite had then
        -- (it is not part of this step; the renders show the strip in place)
        local inTab = f.parentFrame and rawget(f.parentFrame, "accent") ~= nil
        if rawget(f, "_isFS") and f.text and f.text ~= "" and not inTab then
          local b = P.box(f)
          if b and b.w > 0 and b.l + math.min(b.w, P.G.naturalWidth(f)) > cb.l + cb.w + 0.5 then spill[#spill + 1] = ("%s %s l=%d edge=%d"):format(tostring(f.text):sub(1, 30), tostring(f._src), b.l, cb.l + cb.w) end
        end
      end
    end
    check(tag .. ": every region's anchor points agree", #conflicts == 0, table.concat(conflicts, " | "))
    check(tag .. ": no text runs past the pane's right edge", #spill == 0, table.concat(spill, " | "))
    local tbls = tablesIn(content)
    for ti, tbl in ipairs(tbls) do
      local t2 = tag .. (" table %d"):format(ti)
      local sfb = P.box(tbl.sf)
      local rows = shownRows(tbl)
      eq(t2 .. ": the list's child is as wide as the list", tbl.child._w, math.floor(sfb.w))
      eq(t2 .. ": the list is as tall as its rows", tbl.child._h, math.max(1, #rows * UI.ROW_H))
      local narrow, off, cut, just = {}, {}, {}, {}
      for i, row in ipairs(rows) do
        local b = P.box(row)
        if not (b and near(b.w, math.floor(sfb.w))) then narrow[#narrow + 1] = i end
      end
      for _, col in ipairs(tbl.spec) do
        local cw = tbl.cols[col.key]
        if cw.x + cw.w > sfb.w + 0.5 then off[#off + 1] = col.key .. " ends past the list" end
        local hb = tbl.head[col.key]
        local numeric = col.kind == "num" or col.kind == "money"
        if hb.fs then
          if tbl.header.shown ~= false and not near(P.box(hb.fs).l, sfb.l + cw.x) then off[#off + 1] = col.key .. " header" end
          if numeric and hb.fs._justify ~= "RIGHT" then just[#just + 1] = col.key end
          if tbl.header.shown ~= false and hb.fs:IsTruncated() then cut[#cut + 1] = "header " .. col.key end
        end
        for i, row in ipairs(rows) do
          if not (row.item and row.item.ebSection) then
            local cell = row.c[col.key]
            if col.kind ~= "icon" then
              if not near(P.box(cell).l, sfb.l + cw.x) then off[#off + 1] = col.key .. i end
              if numeric and cell._justify ~= "RIGHT" then just[#just + 1] = col.key .. i end
              if col.kind and col.kind ~= "text" and cell:IsTruncated() then cut[#cut + 1] = col.key .. i end
            end
          end
        end
      end
      check(t2 .. ": every row spans the list", #narrow == 0, table.concat(narrow, ","))
      check(t2 .. ": header x == cell x, every column inside the list", #off == 0, table.concat(off, ","))
      check(t2 .. ": numbers and their headers right-aligned", #just == 0, table.concat(just, ","))
      check(t2 .. ": numbers, times, coords and tags are never shortened, headers neither", #cut == 0, table.concat(cut, ","))
    end
    return tbls
  end

  -- data the suite does not have: a dungeon run with a boss, a death in it, milestones this session
  local function addRun()
    local fl = ns.Fights.list()
    local L = ns.DB.story.events
    local f1, f2 = fl[#fl - 1], fl[#fl]
    f2.bossName, f2.outcome = "Mutanus the Devourer", "kill"
    f1.bossName, f1.outcome = "Mutanus the Devourer", "death"   -- the attempt you died in
    f2.group = { { name = "Hart", class = "WARRIOR", me = true }, { name = "Undertaker", class = "PRIEST" } }
    f2.memberAuras = { Undertaker = { { t = 1.2, gain = true, name = "Power Word: Fortitude" } } }
    L[#L + 1] = { kind = "DEATH", t = (f1.startEpoch or 0) + 5, foe = "Mutanus the Devourer", zone = "Wailing Caverns", x = 0.5, y = 0.5, downtime = 95, durLoss = 10, s = ns.DB.active, text = "You died" }
    -- the stored run around the two fights (0.9.50): one boss, wiped once and killed, the death in the first pull
    local t0 = (f1.startEpoch or 0) - 60
    local inside = (f2.startEpoch or 0) + 120 - t0
    ns.char().dungeonRuns = { T.runRecord("Wailing Caverns", t0, inside, {
      bosses = { { enc = 481, name = "Mutanus the Devourer", pulls = 2, wipes = 1, resets = 0, unknown = 0, combat = 40, kill = inside - 100 } },
      nDeaths = { me = 1, party = 0 }, deaths = { { o = 65, enc = 481, foe = "Mutanus the Devourer", back = 95 } },
      xp = { gain = 4200, kill = 3000, quest = 0, n = 14, l0 = 12, p0 = 0.2, l1 = 12, p1 = 0.6, need = 10000 },
      gold = { looted = 4321, quests = 0, lootValue = 12000, items = 9, purse = 6000 }, firstPull = 60 }) }
    L[#L + 1] = { kind = "LEVELUP", t = (f2.startEpoch or 0) + 130, text = "Level 13!", s = ns.DB.active }
    return f2
  end
  local function reopen(hostName, pane) ns.UI.Open(hostName, pane); M.settle() end

  local PAGES = {
    { "home", "overview" }, { "home", "timeline" }, { "home", "sessions" },
    { "character", "quests" }, { "character", "reputation" }, { "character", "professions" },
    { "combat", "dungeons" }, { "combat", "fights" }, { "combat", "deaths" },
  }
  local HOST = { home = "Home", character = "Character", combat = "Combat" }
  for _, size in ipairs({ { 900, 580 }, { 1600, 1000 } }) do
    for _, data in ipairs({ "normal", "long" }) do
      for _, pg in ipairs(PAGES) do
        local tag = ("%s/%s %dx%d %s"):format(pg[1], pg[2], size[1], size[2], data)
        local content = P.open(pg[1], pg[2], size[1], size[2], data)
        addRun(); reopen(HOST[pg[1]], pg[2])
        check(tag .. ": the pane opened", content ~= nil)
        if content then
          local tbls = audit(tag, content)
          if pg[2] ~= "overview" then check(tag .. ": the pane shows a table", #tbls >= 1, #tbls) end
        end
      end
    end
  end

  -- ── Home / Overview: the card grid fills the width, every row of cards shares one height, the feed sits below
  -- the card checks, run on the data as it is and again with an alt and amounts in the thousands of gold
  local function overviewCards(tag, c)
      local cb = P.box(c)
      local rows = { { c.cLevel, c.cXP, c.cPlayed }, { c.cGold, c.cKills, c.cPace } }
      local bad = {}
      for r, cards in ipairs(rows) do
        local b1, b2, b3 = P.box(cards[1]), P.box(cards[2]), P.box(cards[3])
        if not near(b1.l, cb.l + UI.SP.XS) then bad[#bad + 1] = r .. " left" end
        if not near(b3.l + b3.w, cb.l + cb.w - UI.SP.XS) then bad[#bad + 1] = r .. " right (the inset matches the left)" end
        if not (near(b2.l - (b1.l + b1.w), UI.SP.M) and near(b3.l - (b2.l + b2.w), UI.SP.M)) then bad[#bad + 1] = r .. " gaps" end
        if not (near(b1.h, b2.h) and near(b2.h, b3.h)) then bad[#bad + 1] = r .. " heights" end
        if math.abs(b1.w - b3.w) > 2 then bad[#bad + 1] = r .. " widths" end
        for _, p in ipairs(cards) do
          if p.sub:IsTruncated() then bad[#bad + 1] = "sub cut: " .. tostring(p.sub.text) end
          if p.value:IsTruncated() then bad[#bad + 1] = "value cut: " .. tostring(p.value.text) end
          local sb = P.box(p.sub)
          if sb.t + select(2, P.G.textSize(p.sub, sb.w)) > P.box(p).t + P.box(p).h - 4 then bad[#bad + 1] = "sub past the card: " .. tostring(p.sub.text) end
          -- the lines the subtitle needs, counted without its max-lines cap (a wrapped text that needs more lines
          -- than the cap is cut without spilling)
          local cap = p.sub._maxLines
          p.sub._maxLines = nil
          local _, _, need = P.G.textSize(p.sub, sb.w)
          p.sub._maxLines = cap
          if cap and need > cap then bad[#bad + 1] = ("sub needs %d lines of %d: %s"):format(need, cap, tostring(p.sub.text)) end
          if p.sub2 and p.sub2On then
            local s2 = P.box(p.sub2)
            if p.sub2:IsTruncated() then bad[#bad + 1] = "second line cut: " .. tostring(p.sub2.text) end
            if s2.t < sb.t + select(2, P.G.textSize(p.sub, sb.w)) - 0.5 then bad[#bad + 1] = "second line over the subtitle" end
            if s2.t + s2.h > P.box(p).t + P.box(p).h - 4 then bad[#bad + 1] = "second line past the card: " .. tostring(p.sub2.text) end
          end
        end
      end
      check(tag .. ": the cards fill the width in rows of three, M gaps, one height per row, nothing cut", #bad == 0, table.concat(bad, "; "))
      -- GOLD: each label keeps its amount (a no-break space joins them), so a wrap can only fall at the separator.
      -- Today's net and today's pace are of the same period; what every character holds has a line of its own.
      local gs = tostring(c.cGold.sub.text)
      local rate = ns.Gold.metric("perHour", "char", "today")
      local ro = ns.Gold.roster("all")
      check(tag .. ": the Gold card says today's net and, after 5 minutes played, today's pace, each joined to its amount (#43)", gs:find("^today" .. UI.NBSP .. "[%+%-]") ~= nil
        and (gs:find(UI.NBSP .. "per" .. UI.NBSP .. "hour") ~= nil) == (rate ~= nil)
        and (rate == nil or gs:find(ns.Gold.signed(rate) .. UI.NBSP .. "per", 1, true) ~= nil) and gs:find("all", 1, true) == nil, gs)
      check(tag .. ": with more than one character the Gold card has a second line: what they all hold", (ro.count > 1) == (c.cGold.sub2On == true)
        and tostring(c.cGold.sub2.text) == (ro.count > 1 and ("all characters " .. ns.fmtMoney(ro.total)) or ""), tostring(c.cGold.sub2.text))
      local words = {}
      for wd in gs:gsub(UI.NBSP, "_"):gmatch("%S+") do words[#words + 1] = wd end
      local okWords = #words % 2 == 1
      for i, wd in ipairs(words) do if (i % 2 == 0) ~= (wd == "·") then okWords = false end end
      check(tag .. ": the only break points left in the Gold subtitle are around the separators", okWords and #words >= 1, #words)
  end
  for _, size in ipairs({ { 900, 580 }, { 1600, 1000 } }) do
    for _, data in ipairs({ "normal", "long" }) do
      local tag = ("Overview %dx%d %s"):format(size[1], size[2], data)
      local c = P.open("home", "overview", size[1], size[2], data)
      addRun(); reopen("Home", "overview")
      overviewCards(tag, c)
      -- an alt and amounts in the thousands of gold, with enough time played today for the pace (#43): the row of
      -- cards grows by the lines it needs and nothing is cut, also at 900x580
      do
        local G = ns.Gold
        local me, base = ns.char(), G.baseStored()
        check(tag .. ": the day base is known in the data", base ~= nil)
        if base then
          local kT = G.dayKey(GetServerTime(), base)
          me.goldDays = me.goldDays or {}
          local keepRow, keepSince = me.goldDays[kT], me.goldSince
          me.goldDays[kT] = { g = 87654321, s = 12345678, t = 4000, n = 9, looted = 87654321, other = 12345678 }
          me.goldSince = me.goldSince or GetServerTime()
          ns.DB.characters["Player-1-0000C7"] = { name = "Richalt", realm = me.realm, class = "MAGE", faction = me.faction, level = 30, seen = GetServerTime() - 3600,
            gold = { balance = 123456789 } }
          reopen("Home", "overview")
          local gs = tostring(c.cGold.sub.text)
          check(tag .. " rich: thousands of gold today, a pace and an alt are all on the card", gs:find(ns.fmtMoney(87654321 - 12345678), 1, true) ~= nil and gs:find("per" .. UI.NBSP .. "hour", 1, true) ~= nil
            and c.cGold.sub2On == true and tostring(c.cGold.sub2.text):find("^all characters %d") ~= nil, gs .. " | " .. tostring(c.cGold.sub2.text))
          overviewCards(tag .. " rich", c)
          ns.DB.characters["Player-1-0000C7"] = nil
          me.goldDays[kT], me.goldSince = keepRow, keepSince
          reopen("Home", "overview")
        end
      end
      local cb = P.box(c)
      local tb, mb, sb = P.box(c.xpTrack), P.box(c.mhSub), P.box(c.mtbl.sf)
      local r2 = P.box(c.cGold)
      check(tag .. ": the XP bar sits under the cards", tb.t >= r2.t + r2.h + UI.SP.M - 0.5)
      check(tag .. ": the session line sits under the XP bar, on the heading's row", mb.t >= tb.t + tb.h and mb.t < tb.t + tb.h + 30, mb.t - (tb.t + tb.h))
      check(tag .. ": the feed starts under the heading", sb.t >= mb.t + mb.h)
      check(tag .. ": the feed has no header row", c.mtbl.header.shown == false)
      check(tag .. ": the feed shows this session's milestones", #shownRows(c.mtbl) >= 1, #shownRows(c.mtbl))
    end
  end
  -- a subtitle that does not fit takes a second line and its row grows; the other row keeps its height
  do
    local c = P.open("home", "overview", 900, 580)
    for _, p in ipairs({ c.cLevel, c.cXP, c.cPlayed, c.cGold, c.cKills, c.cPace }) do p.sub:SetText("short") end
    c.cGold.sub2:SetText(""); c.cGold.sub2On = false
    c.relayout(c:GetWidth()); M.settle()
    local h0 = P.box(c.cGold).h
    eq("Overview: short subtitles give the base card height", h0, 78)
    -- the Gold card's second line (what every character holds) adds a line to its row, and one more when the
    -- subtitle above it wraps
    c.cGold.sub2:SetText("all characters 12,345g 67s 89c"); c.cGold.sub2On = true
    c.relayout(c:GetWidth()); M.settle()
    check("Overview: the Gold card's second line grows its row by one line, under the subtitle and inside the card", near(P.box(c.cGold).h, h0 + 14) and near(P.box(c.cKills).h, h0 + 14) and near(P.box(c.cLevel).h, h0)
      and P.box(c.cGold.sub2).t >= P.box(c.cGold.sub).t + P.box(c.cGold.sub).h - 0.5 and P.box(c.cGold.sub2).t + P.box(c.cGold.sub2).h <= P.box(c.cGold).t + P.box(c.cGold).h - 4 and not c.cGold.sub2:IsTruncated(), P.box(c.cGold).h)
    c.cGold.sub:SetText("today" .. UI.NBSP .. "+7,530g 86s 43c  ·  +6,777g 77s 77c" .. UI.NBSP .. "per" .. UI.NBSP .. "hour")
    c.relayout(c:GetWidth()); M.settle()
    check("Overview: a wrapped subtitle and the second line together grow the row by two lines, nothing cut", near(P.box(c.cGold).h, h0 + 28) and not c.cGold.sub:IsTruncated() and not c.cGold.sub2:IsTruncated()
      and P.box(c.cGold.sub2).t >= P.box(c.cGold.sub).t + P.box(c.cGold.sub).h - 0.5 and P.box(c.cGold.sub2).t + P.box(c.cGold.sub2).h <= P.box(c.cGold).t + P.box(c.cGold).h - 4, P.box(c.cGold).h)
    c.cGold.sub:SetText("short"); c.cGold.sub2:SetText(""); c.cGold.sub2On = false
    c.relayout(c:GetWidth()); M.settle()
    -- a text that needs more lines than its cap is reported as cut (the check the card audit relies on)
    c.cGold.sub:SetText("one" .. UI.NBSP .. "111,111g 11s 11c  ·  two" .. UI.NBSP .. "222,222g 22s 22c  ·  three" .. UI.NBSP .. "333,333g 33s 33c  ·  four" .. UI.NBSP .. "444,444g 44s 44c")
    c.relayout(c:GetWidth()); M.settle()
    check("Overview: a subtitle that needs more lines than its cap is seen as cut by the test geometry", c.cGold.sub:IsTruncated() == true)
    c.cGold.sub:SetText("short")
    c.relayout(c:GetWidth()); M.settle()
    c.cGold.sub:SetText("looted 123,456,789g 99s 99c  ·  spent 987,654,321g 99s 99c")
    c.relayout(c:GetWidth()); M.settle()
    check("Overview: a long subtitle wraps, the card row grows by one line", P.box(c.cGold).h > h0 and not c.cGold.sub:IsTruncated() and near(P.box(c.cKills).h, P.box(c.cGold).h), P.box(c.cGold).h)
    check("Overview: the first row keeps its height", near(P.box(c.cLevel).h, h0))
    check("Overview: the XP bar moved down with the taller row", P.box(c.xpTrack).t >= P.box(c.cGold).t + P.box(c.cGold).h)
    ns._test.journeyRefresh()
  end

  -- ── Home / Sessions: the two strips share the list's width and start at the table's text inset
  for _, size in ipairs({ { 900, 580 }, { 1600, 1000 } }) do
    local tag = ("Sessions %dx%d"):format(size[1], size[2])
    local c = P.open("home", "sessions", size[1], size[2], "long")
    local xs, gs, hb = P.box(c.xpStrip), P.box(c.goldStrip), P.box(c.tbl.head.date.fs)
    local lastCol = c.tbl.cols.items
    local listR = P.box(c.tbl.header).l + lastCol.x + lastCol.w
    check(tag .. ": XP PER SESSION starts where the SESSION header does", near(xs.l, hb.l), ("%s vs %s"):format(xs.l, hb.l))
    check(tag .. ": the strips are two equal halves L apart, ending at the last column", near(xs.w, gs.w) and near(gs.l - (xs.l + xs.w), UI.SP.L) and math.abs(gs.l + gs.w - listR) <= 1.5, ("%s %s %s/%s"):format(xs.w, gs.l - (xs.l + xs.w), gs.l + gs.w, listR))
    local outside = 0
    for _, st in ipairs({ c.xpStrip, c.goldStrip }) do
      local sb = P.box(st)
      for _, bar in ipairs(st.bars) do
        if bar.shown ~= false then local b = P.box(bar); if b.l < sb.l - 0.5 or b.l + b.w > sb.l + sb.w + 0.5 then outside = outside + 1 end end
      end
    end
    eq(tag .. ": every bar stays inside its strip", outside, 0)
  end

  -- ── Home / Timeline: a section row per day, event rows with the tooltip on the event cell
  do
    local c = P.open("home", "timeline", 900, 580)
    addRun(); reopen("Home", "timeline")
    local tbl = c.timelineTable
    local secs, evs = 0, 0
    for _, r in ipairs(shownRows(tbl)) do
      if r.item and r.item.ebSection then
        secs = secs + 1
        check("Timeline: a day row takes no mouse (no hover, no click)", r._mouse == false)
        check("Timeline: a day row's cells are empty", (r.c.ev.text or "") == "" and r.section.shown ~= false)
      elseif r.ev then evs = evs + 1 end
    end
    check("Timeline: day rows and event rows", secs >= 1 and evs >= 3, secs .. "/" .. evs)
    eq("Timeline: tbl.sections() lists the day rows", #tbl.sections(), secs)
    local row
    for _, r in ipairs(shownRows(tbl)) do if r.ev and r.ev.kind == "LOOT" then row = r; break end end
    check("Timeline: a loot event is listed", row ~= nil)
    if row then
      check("Timeline: the open marker is its own cell, not in the event text", row.c.open.text == ">" and not tostring(row.c.ev.text):find(">", 1, true))
      row:GetScript("OnEnter")(row)
      local tip = _G.GameTooltip
      check("Timeline: the tooltip is anchored to the event cell", tip.owner == row and tip._pts and tip._pts[1].rel == row.c.ev, tip._pts and tostring(tip._pts[1].rel))
      check("Timeline: the tooltip shows the event and the click hint", tip.lines[1] == (row.ev.text or row.ev.kind) and tip.lines[#tip.lines] == "Click to open")
      row:GetScript("OnLeave")(row)
      row:GetScript("OnClick")(row, "LeftButton")
      check("Timeline: clicking a loot event opens Loot / Items", host("Loot").ctl.active == "items")
    end
    -- the window banner spans from the pane's left to the search box, its text on one line
    c = P.open("home", "timeline", 900, 580)
    ns.OpenTimelineWindow(0, 1, ("Kobold Miner of the Scarlet Monastery Cathedral "):rep(4)); M.settle()
    local bb, sb2 = P.box(c.timelineBanner), P.box(c.search)
    check("Timeline: the window banner ends before the search box", bb.l + bb.w <= sb2.l - UI.SP.M + 0.5, bb.l + bb.w)
    check("Timeline: the banner's text stays one line inside it", c.timelineBanner.text._wrap == false and P.box(c.timelineBanner.text).l + P.box(c.timelineBanner.text).w <= bb.l + bb.w)
    c.timelineBanner:GetScript("OnClick")(c.timelineBanner)
    check("Timeline: the search sits inside the pane's list edge", near(sb2.l + sb2.w, P.box(c.tabs.content).l + P.box(c.tabs.content).w - UI.SCROLLBAR))
  end

  -- ── Combat / Fights: day and run sections, sorting by a header, the replay laid out again for a new width
  do
    local c = P.open("combat", "fights", 900, 580)
    addRun(); reopen("Combat", "fights")
    local fl = T.fightsList()
    local tbl = fl.tbl
    local runHead = false
    for _, s in ipairs(tbl.sections()) do if tostring(s.text):find("Wailing Caverns", 1, true) then runHead = true end end
    check("Fights: a run row heads the fights inside a dungeon run", runHead)
    local grpCell
    for _, r in ipairs(shownRows(tbl)) do if r.fight and r.fight.group and #r.fight.group > 1 then grpCell = r end end
    check("Fights: the group size is its own cell, not in the name", grpCell and grpCell.c.grp.text == "2-player" and not tostring(grpCell.c.foe.text):find("player", 1, true))
    -- sort by Length: no sections, longest first, the arrow on Length
    local hb = tbl.head.dur
    hb:GetScript("OnClick")(hb)
    local rows, prev, ordered = shownRows(tbl), math.huge, true
    for _, r in ipairs(rows) do
      if r.item and r.item.ebSection then ordered = false end
      local d = r.fight and r.fight.duration or 0
      if d > prev then ordered = false end
      prev = d
    end
    check("Fights: sorted by length, longest first, without day rows", ordered and #rows > 2)
    check("Fights: the sort arrow sits on the Length header", hb.arrow.shown ~= false and tbl.head.time.arrow.shown == false)
    for _ = 1, 2 do   -- back to newest first
      if not (tbl.sortKey == "time" and tbl.sortAsc == false) then tbl.head.time:GetScript("OnClick")(tbl.head.time) end
    end
    check("Fights: back to newest first with the day rows", #tbl.sections() >= 1 and tbl.sortKey == "time" and tbl.sortAsc == false)
    -- hover: the fight's tooltip on the name cell
    local r1
    for _, r in ipairs(shownRows(tbl)) do if r.fight then r1 = r; break end end
    r1:GetScript("OnEnter")(r1)
    check("Fights: the tooltip is anchored to the name cell and ends with the click hint", _G.GameTooltip._pts and _G.GameTooltip._pts[1].rel == r1.c.foe and _G.GameTooltip.lines[#_G.GameTooltip.lines] == "Click to open the replay")
    -- a shortened foe is already the tooltip's first line: it is not added a second time
    local cutRow
    for _, r in ipairs(shownRows(tbl)) do if r.fight and r.c.foe:IsTruncated() then cutRow = r; break end end
    if cutRow then
      r1:GetScript("OnLeave")(r1)
      cutRow:GetScript("OnEnter")(cutRow)
      local n = 0
      for _, l in ipairs(_G.GameTooltip.lines) do if l == cutRow.c.foe.text then n = n + 1 end end
      eq("Fights: a shortened foe the tooltip already names shows once", n, 1)
      r1 = cutRow
    end
    r1:GetScript("OnLeave")(r1)
  end
  -- the replay: built for the width it has, and again for a new one; nothing past the list
  do
    local function replayAudit(tag, dv)
      local sfb = P.box(dv.sf)
      eq(tag .. ": the replay's child is as wide as its list", dv.child._w, math.floor(sfb.w))
      local past, cut = {}, {}
      for _, fs in ipairs(dv.child.fs) do
        if fs.shown ~= false and fs.text and fs.text ~= "" then
          local b = P.box(fs)
          if b.l + b.w > sfb.l + sfb.w + 0.5 then past[#past + 1] = tostring(fs.text):sub(1, 24) end
          if fs._justify == "RIGHT" and fs:IsTruncated() then cut[#cut + 1] = tostring(fs.text) end
        end
      end
      check(tag .. ": every text of the replay ends inside its list", #past == 0, table.concat(past, " | "))
      check(tag .. ": right-aligned numbers in the replay are never shortened", #cut == 0, table.concat(cut, " | "))
      local sl, vb = P.box(dv.slider), P.box(dv)
      check(tag .. ": the scrubber spans the view", near(sl.l + sl.w, vb.l + vb.w - 16 - UI.SCROLLBAR), sl.w)
      local late = {}
      for _, t in ipairs(dv.ticks) do if t.shown ~= false and P.box(t).l > sl.l + sl.w then late[#late + 1] = t.label end end
      check(tag .. ": the landmarks stay on the scrubber", #late == 0, table.concat(late, ","))
    end
    for _, data in ipairs({ "normal", "long" }) do
      P.open("combat", "fights", 900, 580, data)
      local f = addRun()
      f.gear = { swaps = { { t = 1, name = "Swap", slot = 16 } } }
      ns.OpenFightDetail(f); M.settle()
      local dv = T.fightDetail()
      replayAudit("Replay 900x580 " .. data, dv)
      check("Replay " .. data .. ": the fight page's scroll child does not take the mouse", dv.child._mouse ~= true and dv.child.scripts.OnEnter == nil)
      local w0 = dv.child._w
      ns.UI.SetWindowSize(1600, 1000); M.settle()
      check("Replay " .. data .. ": a wider window lays the fight out again", dv.child._w > w0, dv.child._w)
      replayAudit("Replay 1600x1000 " .. data, dv)
      -- a member's view, then a fight opened from elsewhere: the member's view does not stay over it
      local mb
      for _, b in ipairs(dv.child.mbtn) do if b.shown ~= false and b.member then mb = b end end
      check("Replay " .. data .. ": the other member's name opens their view", mb ~= nil)
      -- every name in the group list: one line, the ">" its own text, a shortened one reads in full on hover
      local bad = {}
      for _, b in ipairs(dv.child.mbtn) do
        if b.shown ~= false then
          if b.fs._wrap ~= false or b.arrow.text ~= ">" or tostring(b.fs.text):find(">", 1, true) then bad[#bad + 1] = tostring(b.fs.text) end
          if b.fs:IsTruncated() then
            b:GetScript("OnEnter")(b)
            if not (_G.GameTooltip.owner == b and _G.GameTooltip.lines[1] == b.fs.text) then bad[#bad + 1] = "no tooltip: " .. tostring(b.fs.text) end
            b:GetScript("OnLeave")(b)
          end
        end
      end
      check("Replay " .. data .. ": group names are one line with the marker apart, shortened ones in a tooltip", #bad == 0, table.concat(bad, " | "))
      if mb then
        mb:GetScript("OnClick")(mb); M.settle()
        local mv = dv.parentFrame and nil
        for _, f2 in ipairs(P.descendants(P.box and host("Home").paneByKey.fights.content or {})) do
          if rawget(f2, "titleFS") and f2 ~= dv and f2.shown ~= false and rawget(f2, "render") then mv = f2 end
        end
        check("Replay " .. data .. ": the member's view is up", mv ~= nil and dv.shown == false)
        if mv then
          check("Replay " .. data .. ": the member page's scroll child does not take the mouse", mv.child._mouse ~= true and mv.child.scripts.OnEnter == nil)
          local tb = P.box(mv.titleFS)
          check("Replay " .. data .. ": the member's name sits on the Back button's row, left-aligned", mv.titleFS._justify == "LEFT" and tb.t < P.box(mv).t + 40, tb.t - P.box(mv).t)
          ns.OpenFightDetail(f); M.settle()
          check("Replay " .. data .. ": opening a fight closes the member's view", mv.shown == false and dv.shown ~= false)
        end
      end
    end
  end

  -- ── Combat / Dungeons: the list's row opens the run; the run is laid out for its width and again on a resize
  for _, data in ipairs({ "normal", "long" }) do
    P.open("combat", "dungeons", 900, 580, data)
    addRun(); reopen("Combat", "dungeons")
    local runs = T.runViews(true)
    local run = runs[#runs]
    run.notable = { { item = "Cruel Barb", count = 17777, src = "Riverpaw Gnoll", t = run.startT + 60, q = "ff0070dd" } }
    T.openRun(run); M.settle()
    local dv = T.dungeonDetail()
    check("Run " .. data .. ": the run page's scroll child does not take the mouse", dv.child._mouse ~= true and dv.child.scripts.OnEnter == nil)
    local function runAudit(tag)
      local sfb = P.box(dv.sf)
      eq(tag .. ": the run's child is as wide as its list", dv.child._w, math.floor(sfb.w))
      local past, cut = {}, {}
      for _, fs in ipairs(dv.child.fs) do
        if fs.shown ~= false and fs.text and fs.text ~= "" then
          local b = P.box(fs)
          if b.l + b.w > sfb.l + sfb.w + 0.5 then past[#past + 1] = tostring(fs.text):sub(1, 24) end
          if fs._justify == "RIGHT" and fs:IsTruncated() then cut[#cut + 1] = tostring(fs.text) end
        end
      end
      check(tag .. ": every text of the run ends inside its list", #past == 0, table.concat(past, " | "))
      check(tag .. ": quantities and times are never shortened", #cut == 0, table.concat(cut, " | "))
      local tb = P.box(dv.titleFS)
      check(tag .. ": the title sits on the Back button's row", tb.t < P.box(dv).t + 40, tb.t - P.box(dv).t)
      local enc = 0
      for _, b in ipairs(dv.child.btn) do
        if b.shown ~= false then
          enc = enc + 1
          if not near(P.box(b).w, math.floor(sfb.w)) then enc = -100 end
          if b.hl._layer ~= "HIGHLIGHT" then enc = -100 end
        end
      end
      check(tag .. ": the encounter rows span the list with a hover highlight", enc >= 1, enc)
    end
    runAudit("Dungeon run 900x580 " .. data)
    local w0 = dv.child._w
    ns.UI.SetWindowSize(1600, 1000); M.settle()
    check("Dungeon run " .. data .. ": a wider window lays the run out again", dv.child._w > w0 and dv.renderedW == dv.child._w, dv.child._w)
    runAudit("Dungeon run 1600x1000 " .. data)
    dv:Hide()
  end

  -- a stored (lean) record made the open run it was while the character was inside: every block and clock back
  local function asOpen(rec, t)
    rec.why, rec.gold, rec.visits[1].o, rec.visits[1].out = nil, nil, nil, nil
    rec.st, rec.mark, rec.beat = "in", t, t
    ns.Runs._read = true                                         -- (the pane suite plays no world entry: the load counts as read)
    rec.nDeaths, rec.deaths, rec.hidden = rec.nDeaths or {}, rec.deaths or {}, rec.hidden or {}
    rec.nDeaths.me, rec.nDeaths.party = rec.nDeaths.me or 0, rec.nDeaths.party or 0
    for _, k in ipairs({ "xp", "rep", "loot" }) do rec.hidden[k] = rec.hidden[k] or 0 end
    for _, k in ipairs(ns.Runs.SECS) do rec.secs[k] = rec.secs[k] or 0 end
    for _, b in ipairs(rec.bosses) do b.pulls = b.pulls or 1 end
    return rec
  end
  -- ── Combat / Dungeons (0.9.50): the empty state, and the row and the page of the run in progress, at both sizes
  for _, size in ipairs({ { 900, 580 }, { 1600, 1000 } }) do
    local tag = ("Dungeons %dx%d"):format(size[1], size[2])
    P.open("combat", "dungeons", size[1], size[2], "normal")
    local me = ns.char()
    local keep, keepOpen = me.dungeonRuns, me.dungeonRun
    me.dungeonRuns, me.dungeonRun = nil, nil
    local dv = T.dungeonDetail(); dv:Hide()
    local lv = T.dungeonList(); lv:Show(); M.settle()
    local e = lv.tbl.empty
    check(tag .. ": with no run the list says how runs get there and since when they are kept", e.shown ~= false and lv.tbl.shownN == 0
      and e.text == "No dungeon runs yet. Enter a dungeon and it shows up here.\nRuns are kept from version 0.9.50 on.", e.text)
    local eb, pb = P.box(e), P.box(lv)
    check(tag .. ": the empty text sits inside the pane", eb.l >= pb.l - 0.5 and eb.l + eb.w <= pb.l + pb.w + 0.5, eb.w)
    -- a run in progress: 15 minutes inside so far, one boss down, one still up
    local t = GetServerTime()
    local rec = asOpen(T.runRecord("Maraudon", t - 900, 900, { firstPull = 100,
      bosses = { { enc = 422, name = "Noxxion", pulls = 1, combat = 52, kill = 373 }, { enc = 423, name = "Razorlash", pulls = 1, combat = 0 } } }), t)
    rec.encs = { [423] = { t = t - 20, o = 880, d = 0 } }
    me.dungeonRun = rec
    lv = T.dungeonList(); M.settle()
    local row
    for _, r in ipairs(lv.tbl.rows) do if r.shown ~= false and r.run and r.run.id == rec.id then row = r end end
    check(tag .. ": the run in progress is a row, marked in words and with the dot", row ~= nil and row.c.name.text == "Maraudon  ·  in progress" and row.c.live.text == "•"
      and row.c.dur.text == "15m 0s" and row.c.boss.text == "1" and row.c.death.text == "0", row and row.c.name.text)
    check(tag .. ": its name and its numbers are in full", row ~= nil and not row.c.name:IsTruncated() and not row.c.dur:IsTruncated() and not row.c.rate:IsTruncated() and not row.c.loot:IsTruncated())
    if row then
      local tips = lv.tipLines(row.run)
      check(tag .. ": the row's tooltip reads the clocks and the state", tips[1] == "Inside 15m 0s" and tips[2] == "Active 15m 0s" and tips[3] == "In progress", table.concat(tips, " | "))
      T.openRun(row.run); M.settle()
      check(tag .. ": its page says in progress and lists both bosses", dv.shown ~= false and dv.run.inProgress == true and tostring(dv.metaFS.text):find("in progress", 1, true) ~= nil and #dv.run.bosses == 2)
      local res = {}
      for _, fs in ipairs(dv.child.fs) do if fs.shown ~= false and (fs.text == "Killed" or fs.text == "Not killed" or fs.text == "Deathless run.") then res[#res + 1] = fs.text end end
      check(tag .. ": a boss still up reads Not killed, the page of a run with no death says so", table.concat(res, ",") == "Killed,Not killed,Deathless run.", table.concat(res, ","))
      -- the page follows the run: five seconds later it reads five seconds more
      local line0 = dv.timeLine
      M.epoch = M.epoch + 5
      check(tag .. ": the open run's page reads the store again", dv.refresh() == true and dv.timeLine ~= line0 and dv.timeLine:find("Inside 15m 5s", 1, true) == 1, dv.timeLine)
      M.epoch = M.epoch - 5
      local sfb, past = P.box(dv.sf), {}
      for _, fs in ipairs(dv.child.fs) do
        if fs.shown ~= false and fs.text and fs.text ~= "" then
          local b = P.box(fs)
          if b.l + b.w > sfb.l + sfb.w + 0.5 then past[#past + 1] = tostring(fs.text):sub(1, 24) end
        end
      end
      check(tag .. ": every text of the open run's page ends inside its list", #past == 0, table.concat(past, " | "))
    end
    dv:Hide(); lv:Show()
    me.dungeonRuns, me.dungeonRun = keep, keepOpen
  end

  -- ── Combat / Dungeons (0.9.50, review round 1): nothing on the run page is cut at 900x580, the page of a run in
  -- progress follows it through the pane's own ticker and only while it is on screen, and one fight reads one way
  do
    local R = ns.Runs
    local tag = "Run page 900x580"
    P.open("combat", "dungeons", 900, 580, "normal")
    local me = ns.char()
    local keep, keepOpen = me.dungeonRuns, me.dungeonRun
    local fights = ns.DB.combat.fights
    local nFights = #fights
    local t = GetServerTime()
    local dv = T.dungeonDetail()
    local lv
    local function rowOf(id)
      lv = T.dungeonList(); lv:Show(); M.settle()
      for _, r in ipairs(lv.tbl.rows) do if r.shown ~= false and r.run and r.run.id == id then return r end end
    end
    local function cutTexts()
      local cut = {}
      for _, fs in ipairs(dv.child.fs) do if fs.shown ~= false and fs.text and fs.text ~= "" and fs:IsTruncated() then cut[#cut + 1] = tostring(fs.text):sub(1, 30) end end
      for _, b in ipairs(dv.child.btn) do
        if b.shown ~= false then for _, fs in ipairs({ b.tm, b.nm, b.re }) do if fs:IsTruncated() then cut[#cut + 1] = tostring(fs.text):sub(1, 30) end end end
      end
      return cut
    end
    local function has(text) for _, fs in ipairs(dv.child.fs) do if fs.shown ~= false and fs.text == text then return fs end end end
    local function hasPrefix(text) for _, fs in ipairs(dv.child.fs) do if fs.shown ~= false and tostring(fs.text):find(text, 1, true) == 1 then return fs end end end

    -- a closed run with every clock above zero, hours long and then minutes long, XP with every part, a purse line,
    -- a death with a long killer's name and the time back, and two fights still stored (the boss and a trash pull)
    local CLOCKS = {
      { secs = { inside = 14000, ghost = 3960, outside = 4980, offline = 6960, active = 12480, combat = 9000, boss = 7200 },
        l1 = "Inside 3h 53m  ·  running back 1h 6m  ·  outside 1h 23m  ·  offline 1h 56m", l2 = "Active 3h 28m  ·  in combat 2h 30m (bosses 2h 0m)" },
      { secs = { inside = 1870, ghost = 754, outside = 870, offline = 3540, active = 1720, combat = 842, boss = 190 },
        l1 = "Inside 31m 10s  ·  running back 12m 34s  ·  outside 14m 30s  ·  offline 59m 0s", l2 = "Active 28m 40s  ·  in combat 14m 2s (bosses 3m 10s)" },
    }
    for ci, cl in ipairs(CLOCKS) do
      local s = cl.secs
      local rec = T.runRecord("Blackrock Depths", t - 40000, s.inside, {
        secs = { inside = s.inside, ghost = s.ghost, outside = s.outside, offline = s.offline, active = s.active, combat = s.combat, boss = s.boss }, firstPull = 100,
        bosses = { { enc = 228, name = "High Interrogator Gerstahn", pulls = 2, wipes = 1, combat = 300, kill = 900, fight = "uid-brd-boss" },
          { enc = 229, name = "Lord Roccor", pulls = 1, combat = 60, kill = 1500, fight = "uid-brd-gone" } },
        nDeaths = { me = 2 }, deaths = { { o = 700, enc = 228, foe = "High Interrogator Gerstahn", back = 754 }, { o = 1200 } },
        xp = { gain = 123456, kill = 98765, quest = 23456, n = 1450, l0 = 52, p0 = 0.41, l1 = 53, p1 = 0.12, need = 150000 }, hidden = { xp = 12 },
        gold = { looted = 123456, quests = 5000, lootValue = 234567, items = 45, purse = 345678 } })
      me.dungeonRuns, me.dungeonRun = { rec }, nil
      while #fights > nFights do table.remove(fights) end
      fights[#fights + 1] = { uid = "uid-brd-trash", session = ns.DB.active, startEpoch = rec.t + 300, duration = 20, outcome = "fled", foes = {}, zone = "Blackrock Depths" }
      fights[#fights + 1] = { uid = "uid-brd-boss", session = ns.DB.active, startEpoch = rec.t + 600, duration = 300, outcome = "kill", bossName = "High Interrogator Gerstahn",
        foes = { "High Interrogator Gerstahn" }, zone = "Blackrock Depths" }
      local row = rowOf(rec.id)
      check(tag .. ": (the run is a row of the list)", row ~= nil)
      if row then
        T.openRun(row.run); M.settle()
        check(tag .. ": the clocks are two lines, where the time went and what was done inside (" .. ci .. ")", dv.timeLine == cl.l1 and dv.timeLine2 == cl.l2 and #dv.timeFS == 2
          and dv.timeFS[1].text == cl.l1 and dv.timeFS[2].text == cl.l2, tostring(dv.timeLine) .. " | " .. tostring(dv.timeLine2))
        check(tag .. ": neither Time line is cut (" .. ci .. ")", not dv.timeFS[1]:IsTruncated() and not dv.timeFS[2]:IsTruncated())
        check(tag .. ": the loot line, the purse line and the three XP lines are there and not cut (" .. ci .. ")", dv.lootFS and not dv.lootFS:IsTruncated() and dv.purseFS and not dv.purseFS:IsTruncated()
          and #dv.xpFS == 3 and not dv.xpFS[1]:IsTruncated() and not dv.xpFS[2]:IsTruncated() and not dv.xpFS[3]:IsTruncated(), #dv.xpFS)
        local cut = cutTexts()
        check(tag .. ": no text of the page is cut, the deaths table included (" .. ci .. ")", #cut == 0, table.concat(cut, " | "))
      end
    end
    -- the page of that run, part by part
    check(tag .. ": the XP line ends on the runs the next level takes; quest XP and kills are the next line", dv.xpLine:find("about 2 more runs to level 54", 1, true) ~= nil
      and dv.xpMore == "23,456 XP from quests  ·  at least 1,450 kills" and dv.xpHidden == "12 XP lines were hidden by the client.", dv.xpLine .. " | " .. tostring(dv.xpMore))
    check(tag .. ": slain by and back after are columns of their own", has("SLAIN BY") ~= nil and has("BACK AFTER") ~= nil and has("12m 34s") ~= nil and has("12m 34s")._justify == "RIGHT"
      and hasPrefix("slain by") == nil and hasPrefix("back after") == nil)
    -- the TIME tile lists the clocks on hover
    local tipB = dv.timeTip
    tipB:GetScript("OnEnter")(tipB)
    local tip = table.concat(GameTooltip.lines, " | ")
    check(tag .. ": hovering the TIME tile lists the clocks", GameTooltip:GetOwner() == tipB and tip:find("Time | Inside 31m 10s | Run back 12m 34s | Outside 14m 30s | Offline 59m 0s | Active 28m 40s", 1, true) == 1, tip)
    tipB:GetScript("OnLeave")(tipB)
    local tb, tileB = P.box(tipB), P.box(has("TIME"))
    check(tag .. ": the hover area sits on the TIME tile", near(tb.l, tileB.l) and tb.w > 20 and tb.t <= tileB.t and tb.t + tb.h >= tileB.t + tileB.h, tb.l - tileB.l)
    -- the boss whose fight is still stored opens it; the one whose fight is gone is plain text
    local bossBtns = {}
    for _, b in ipairs(dv.child.bbtn) do if b.shown ~= false then bossBtns[#bossBtns + 1] = b end end
    check(tag .. ": a boss row opens its fight while the fight is stored, and only then", #bossBtns == 1 and bossBtns[1].fight and bossBtns[1].fight.uid == "uid-brd-boss"
      and near(P.box(bossBtns[1]).t, P.box(has("High Interrogator Gerstahn")).t, 2), #bossBtns)
    -- one fight, one reading: the trash pull is Trash on the run page, in the Fights list, its tooltip and its page
    local trashRow
    for _, b in ipairs(dv.child.btn) do if b.shown ~= false and b.fight and b.fight.uid == "uid-brd-trash" then trashRow = b end end
    check(tag .. ": Encounters lists the stored fights, the foe-less one as Trash", dv.encounters == 2 and has("Encounters  (2)") ~= nil and trashRow ~= nil and trashRow.re.text == "Trash", trashRow and trashRow.re.text)
    local label, _, key = ns.FightResult(fights[#fights - 1])
    check(tag .. ": the shared reading says trash for it, and fled for the same fight outside every run", key == "trash" and label[1] == "Trash"
      and select(3, ns.FightResult({ outcome = "fled", foes = {}, startEpoch = t - 90000 })) == "fled")
    local fl = T.fightsList()
    T.fightDetail():Hide(); fl:Show()                           -- (an earlier test left a replay open; the list rebuilds only while it shows)
    reopen("Combat", "fights")
    local listRow
    for _, r in ipairs(shownRows(fl.tbl)) do if r.fight and r.fight.uid == "uid-brd-trash" then listRow = r end end
    check("Fights: the same fight reads Trash in the list", listRow ~= nil and tostring(listRow.c.res.text):find("Trash", 1, true) ~= nil and tostring(listRow.c.res.text):find("Fled", 1, true) == nil,
      listRow and listRow.c.res.text)
    ns.OpenFightDetail(fights[#fights - 1]); M.settle()
    local fdv = T.fightDetail()
    check("Fights: and on its own page", tostring(fdv.metaFS.text):find("Trash", 1, true) ~= nil and tostring(fdv.metaFS.text):find("Fled", 1, true) == nil, fdv.metaFS.text)
    fdv:Hide(); fl:Show()
    -- a boss row's click lands on that fight
    reopen("Combat", "dungeons")
    local row = rowOf(me.dungeonRuns[1].id)
    T.openRun(row.run); M.settle()
    for _, b in ipairs(dv.child.bbtn) do if b.shown ~= false then b:GetScript("OnClick")(b, "LeftButton") end end
    check(tag .. ": clicking the boss row opens its fight", host("Home").ctl.active == "fights" and T.fightDetail().fight and T.fightDetail().fight.uid == "uid-brd-boss")
    T.fightDetail():Hide(); fl:Show()
    -- a run none of whose fights is stored has no Encounters section
    while #fights > nFights do table.remove(fights) end
    reopen("Combat", "dungeons")
    row = rowOf(me.dungeonRuns[1].id)
    T.openRun(row.run); M.settle()
    check(tag .. ": with no fight of the run stored there is no Encounters section", dv.encounters == 0 and hasPrefix("Encounters") == nil and has("No fights of this run are stored.") == nil
      and #bossBtns >= 0 and (function() for _, b in ipairs(dv.child.bbtn) do if b.shown ~= false then return false end end return true end)())

    -- ── the run in progress: the page follows it through the pane's 1 s ticker ──
    tag = "Run in progress"
    local function openOne()
      local rec = asOpen(T.runRecord("Maraudon", t - 900, 900, { firstPull = 100, bosses = { { enc = 422, name = "Noxxion", pulls = 1, combat = 52, kill = 373 } } }), GetServerTime())
      me.dungeonRuns, me.dungeonRun = {}, rec
      return rec
    end
    local rec = openOne()
    row = rowOf(rec.id)
    T.openRun(row.run); M.settle()
    M.tick()                                                    -- (the run's own 10 s tick settles first)
    local renders, refreshes = dv.renders, 0
    local realRefresh = dv.refresh
    dv.refresh = function() refreshes = refreshes + 1; return realRefresh() end
    M.epoch = M.epoch + 5
    M.tick()
    check(tag .. ": the ticker moves the clocks of the page: five seconds later it reads five seconds more", refreshes == 1 and dv.timeLine == "Inside 15m 5s" and dv.timeFS[1].text == "Inside 15m 5s"
      and dv.run.inProgress == true, tostring(dv.timeLine))
    check(tag .. ": a second in which only the clocks moved lays nothing out again and reads no fight", dv.renders == renders and has("15m 5s") ~= nil, dv.renders - renders)
    -- a fight is stored: the next tick reads the lists again
    fights[#fights + 1] = { uid = "uid-mara-1", session = ns.DB.active, startEpoch = GetServerTime() - 3, duration = 2, outcome = "kill", foes = { "Noxious Slime" }, zone = "Maraudon" }
    M.tick()
    check(tag .. ": a fight stored since is on the page at the next tick", dv.renders == renders + 1 and dv.encounters == 1 and has("Encounters  (1)") ~= nil, dv.encounters)
    -- a number changed, no row was stored: laid out again, the lists as they were
    local listsBefore = dv.run.fights
    rec.nDeaths.me = 1; rec.deaths[1] = { o = 903 }
    M.tick()
    check(tag .. ": a death since is on the page at the next tick, the fights are not read again", dv.renders == renders + 2 and has("Deaths  (1)") ~= nil and dv.run.fights == listsBefore)
    -- the window is closed, or another pane shows: the frame's own flag stays set, the ticker does nothing
    renders, refreshes = dv.renders, 0
    _G.EverbuffFrame:Hide()
    M.epoch = M.epoch + 5
    M.tick()
    check(tag .. ": with the window closed the ticker reads nothing and lays nothing out", refreshes == 0 and dv.renders == renders and dv.shown ~= false and dv:IsVisible() == false, refreshes)
    _G.EverbuffFrame:Show()
    ns.UI.Open("Combat", "fights"); M.settle()
    M.tick()
    check(tag .. ": the same while another pane shows", refreshes == 0 and dv.renders == renders and dv.shown ~= false, refreshes)
    reopen("Combat", "dungeons")
    lv:Hide(); dv:Show(); M.settle()
    M.tick()
    check(tag .. ": back on screen it follows again", refreshes == 1 and dv.timeLine == "Inside 15m 10s", tostring(dv.timeLine))
    -- the run closes while its page is open: the page becomes the closed run's
    R.close(me, rec, "left", GetServerTime())
    M.tick()
    check(tag .. ": a run that closed while its page was open reads as ended", dv.shown ~= false and dv.run.inProgress == false and dv.run.id == rec.id
      and tostring(dv.metaFS.text):find("Ended: left the dungeon", 1, true) ~= nil, tostring(dv.metaFS.text))
    refreshes = 0
    M.tick()
    check(tag .. ": and is followed no further", dv.refresh() == false and dv.shown ~= false)
    -- the run is discarded (too short and empty to be kept): the page lets go and the list shows
    while #fights > nFights do table.remove(fights) end
    rec = openOne()
    row = rowOf(rec.id)
    T.openRun(row.run); M.settle()
    me.dungeonRun = nil
    local views, realViews = 0, R.views
    M.tick()
    R.views = function(...) views = views + 1; return realViews(...) end
    local again = dv.refresh()
    R.views = realViews
    check(tag .. ": a run that was not kept sends the page back to the list", dv.shown == false and lv.shown ~= false and dv.run.inProgress == false)
    check(tag .. ": and nothing asks for it again", again == false and views == 0, views)
    -- a row a few seconds old: the run closed between the list's rebuild and the click
    rec = openOne()
    row = rowOf(rec.id)
    check(tag .. ": (the row says in progress)", row and row.run.inProgress == true)
    R.close(me, rec, "left", GetServerTime())
    T.openRun(row.run); M.settle()
    check(tag .. ": a stale row opens the closed run as closed and writes nothing onto its record", dv.run.inProgress == false and rec.mark == nil and rec.beat == nil and rec.st == nil
      and tostring(dv.metaFS.text):find("Ended: left the dungeon", 1, true) ~= nil, tostring(dv.metaFS.text))
    dv.refresh = realRefresh
    dv:Hide(); lv:Show()

    -- ── the Fights list: a run header only over the fights of the run's visits ──
    rec = openOne()
    rec.visits[1].o, rec.visits[1].out = 900, "alive"                   -- left alive a minute ago: the run stays open
    rec.st, rec.left, rec.endT, rec.gap = "out", rec.t + 900, rec.t + 900, { ghost = 0, outside = 0, offline = 0 }
    fights[#fights + 1] = { uid = "uid-mara-in", session = ns.DB.active, startEpoch = rec.t + 100, duration = 20, outcome = "kill", foes = { "Noxious Slime" }, zone = "Maraudon" }
    fights[#fights + 1] = { uid = "uid-after-leave", session = ns.DB.active, startEpoch = rec.t + 950, duration = 20, outcome = "kill", foes = { "Desolace Kodo" }, zone = "Desolace" }
    T.fightDetail():Hide(); fl:Show()
    reopen("Combat", "fights")
    local order = {}
    for i, r in ipairs(shownRows(fl.tbl)) do
      if r.item and r.item.ebSection and tostring(r.item.ebSection):find("Maraudon", 1, true) then order.head = order.head or i end
      if r.fight and r.fight.uid == "uid-mara-in" then order.inside = i end
      if r.fight and r.fight.uid == "uid-after-leave" then order.after = i end
    end
    check("Fights: a fight after the character left a run that is still open gets no run header", order.head and order.inside and order.after and order.after < order.head and order.head < order.inside,
      ("%s %s %s"):format(tostring(order.after), tostring(order.head), tostring(order.inside)))
    while #fights > nFights do table.remove(fights) end
    me.dungeonRuns, me.dungeonRun = keep, keepOpen
    reopen("Combat", "dungeons")
    T.dungeonDetail():Hide(); T.dungeonList():Show()
  end

  -- ── Combat / Deaths: the summary wraps and the table moves below it; the gear loss is its own cell
  do
    local c = P.open("combat", "deaths", 900, 580, "long")
    addRun(); reopen("Combat", "deaths")
    local sb, hb = P.box(c.summary), P.box(c.tbl.header)
    check("Deaths: the table starts below the summary", hb.t >= sb.t + sb.h, hb.t - (sb.t + sb.h))
    check("Deaths: the long summary wraps instead of cutting its numbers", not c.summary:IsTruncated())
    local r
    for _, x in ipairs(shownRows(c.tbl)) do if x.c.by.text == "Mutanus the Devourer" then r = x end end
    check("Deaths: the gear loss and the open marker are cells of their own", r ~= nil and r.c.gear.text == "-10% gear" and r.c.open.text == ">" and not tostring(r.c.down.text):find("gear", 1, true),
      r and ("%s|%s|%s"):format(tostring(r.c.gear.text), tostring(r.c.open.text), tostring(r.c.down.text)))
    if not r then return end
    r:GetScript("OnClick")(r, "LeftButton")
    check("Deaths: clicking a death opens its fight", host("Home").ctl.active == "fights")
  end

  -- ── Character / Reputation and Professions: the first list is as tall as its rows, the history right below it
  for _, pg in ipairs({ { "reputation", "faction" }, { "professions", "prof" } }) do
    local c = P.open("character", pg[1], 900, 580)
    local tbls = tablesIn(c)
    check("Character/" .. pg[1] .. ": two lists", #tbls == 2, #tbls)
    if #tbls == 2 then
      local top, hist = tbls[1], tbls[2]
      if P.box(top.sf).t > P.box(hist.sf).t then top, hist = hist, top end
      local rows = shownRows(top)
      local tb = P.box(top.sf)
      eq("Character/" .. pg[1] .. ": the first list shows its rows without scrolling", math.floor(tb.h + 0.5), math.max(1, #rows) * UI.ROW_H)
      check("Character/" .. pg[1] .. ": the history starts L below the first list", P.box(hist.header).t >= tb.t + tb.h + UI.SP.L - 0.5 or hist.header.shown == false)
      local r = rows[1]
      if r then
        r:GetScript("OnClick")(r, "LeftButton")
        local key = r.faction or r.prof
        local function rowOf() for _, x in ipairs(shownRows(top)) do if (x.faction or x.prof) == key then return x end end end
        local sel = rowOf()
        check("Character/" .. pg[1] .. ": a clicked row stays selected and filters the history", sel.sel and sel.sel.shown ~= false and sel.sel._layer == "BACKGROUND")
        local others = 0
        for _, x in ipairs(shownRows(top)) do if x ~= sel and x.sel and x.sel.shown ~= false then others = others + 1 end end
        check("Character/" .. pg[1] .. ": only the clicked row is marked", others == 0, others)
      end
      if pg[1] == "professions" and r then
        local cw = top.cols.bar
        check("Professions: the skill bar is drawn inside its column", r.bar and r.bar._w and r.bar._w <= cw.w + 0.5 and r.bar._pts[1].rel == r.c.bar)
        check("Professions: a dim track spans the bar column under the bar", r.barTrack and near(r.barTrack._w, cw.w) and r.barTrack._layer == "BORDER" and r.barTrack._pts[1].rel == r.c.bar)
        check("Professions: the skill value and its header are right-aligned (a number)", r.c.rank._justify == "RIGHT" and top.head.rank.fs._justify == "RIGHT")
      end
    end
  end

  -- ── Combat / Dungeons (0.9.50, review round 3): the dungeon list of a levelling character (40 names) lies inside
  -- the window at 900x580, in columns, every name a button that can be clicked
  do
    P.open("combat", "dungeons", 900, 580, "normal")
    local me = ns.char()
    local keep, keepOpen = me.dungeonRuns, me.dungeonRun
    local list, t0 = {}, GetServerTime() - 40 * 3600
    for i = 1, 40 do list[i] = T.runRecord(("Dungeon Number %02d of the Long List"):format(i), t0 + i * 3600, 600) end
    me.dungeonRuns, me.dungeonRun = list, nil
    T.dungeonDetail():Hide()
    local lv = T.dungeonList(); lv:Show(); M.settle()
    lv.pick:GetScript("OnClick")(lv.pick); M.settle()
    local menu = lv.menu
    local wb = P.box(_G.EverbuffFrame)
    local out, n = {}, 0
    for i = 1, #menu.items do
      local b = menu.btns[i]
      local bb = b and b.shown ~= false and P.box(b)
      if not bb then out[#out + 1] = "no box " .. i
      else
        n = n + 1
        if bb.l < wb.l - 0.5 or bb.t < wb.t - 0.5 or bb.l + bb.w > wb.l + wb.w + 0.5 or bb.t + bb.h > wb.t + wb.h + 0.5 then out[#out + 1] = ("%d at %d,%d"):format(i, bb.l, bb.t) end
      end
    end
    check("Dungeons menu: 40 dungeons and All dungeons are 41 buttons, in columns of at most UI.MENU_ROWS", #menu.items == 41 and n == 41 and menu.rows <= UI.MENU_ROWS and menu.cols == 3,
      ("%d %d %s %s"):format(#menu.items, n, tostring(menu.rows), tostring(menu.cols)))
    check("Dungeons menu: every entry lies inside the 900x580 window", #out == 0, table.concat(out, " | "))
    menu.btns[41]:GetScript("OnClick")(menu.btns[41]); M.settle()
    check("Dungeons menu: the last entry can be picked", lv.st.inst == "Dungeon Number 40 of the Long List" and #lv.shown == 1 and menu.shown == false, lv.st.inst)
    lv.pickInst(nil)
    me.dungeonRuns, me.dungeonRun = keep, keepOpen
  end

  -- ── Combat / Dungeons (0.9.51): bests, VS BEST, Pace, Visits and the buttons, BY DUNGEON, the hour line; a run
  -- with 12 bosses and one with none, at both sizes: nothing cut, every button inside the window
  for _, size in ipairs({ { 900, 580 }, { 1600, 1000 } }) do
    local R = ns.Runs
    local tag = ("Dungeons 0.9.51 %dx%d"):format(size[1], size[2])
    P.open("combat", "dungeons", size[1], size[2], "normal")
    local me = ns.char()
    local keep, keepOpen, keepStats = me.dungeonRuns, me.dungeonRun, me.dungeonStats
    local t = GetServerTime() - 90000
    -- three runs of a dungeon with 12 bosses (the last one 3 bosses short), two visits each, the real names
    local BRD = { "High Interrogator Gerstahn", "Lord Roccor", "Houndmaster Grebmar", "Ring of Law", "Pyromancer Loregrain", "Lord Incendius", "Warder Stilgiss",
      "Fineous Darkvire", "Bael'Gar", "General Angerforge", "Golem Lord Argelmach", "Emperor Dagran Thaurissan" }
    local function twelve(at, step, n, over)
      local b = {}
      for i = 1, n do b[i] = { enc = 3000 + i, name = BRD[i], pulls = 1, combat = 30, kill = 100 + i * step } end
      local inside = 200 + 12 * step
      local o = { firstPull = 70, bosses = b, size = 5, diff = 1,
        visits = { { i = 0, o = 300, how = "zone", out = "ghost", secs = 300, active = 300 }, { i = 400, o = inside + 100, how = "ghost", secs = inside - 300, active = inside - 300, gg = 100 } },
        secs = { inside = inside, ghost = 100, active = inside, combat = 0, boss = 0 } }
      for k, v in pairs(over or {}) do o[k] = v end
      local r = T.runRecord("Blackrock Depths", at, inside, o)
      r.endT = at + inside + 100
      return r
    end
    local runs = { twelve(t, 200, 12), twelve(t + 10000, 190, 12), twelve(t + 20000, 210, 9, { keep = true }), T.runRecord("Ragefire Chasm", t + 30000, 400, { size = 1 }),
      T.runRecord("The Temple of Atal'Hakkar", t + 40000, 500, { keep = true }) }
    me.dungeonRuns, me.dungeonRun, me.dungeonStats = runs, nil, nil
    R.statsRebuild(me)
    local dv = T.dungeonDetail()
    local function cut()
      local out = {}
      for _, fs in ipairs(dv.child.fs) do if fs.shown ~= false and fs.text and fs.text ~= "" and fs:IsTruncated() then out[#out + 1] = tostring(fs.text):sub(1, 40) end end
      return out
    end
    local wb = P.box(_G.EverbuffFrame)
    local function inside(b)
      local bb = P.box(b)
      return bb and bb.l >= wb.l - 0.5 and bb.l + bb.w <= wb.l + wb.w + 0.5
    end
    for _, which in ipairs({ { 1, "12 bosses" }, { 3, "9 of 12 bosses" }, { 4, "no boss" } }) do
      local v = R.view(runs[which[1]], false, true)
      dv.pending, dv.refused = nil, nil
      T.openRun(v); M.settle()
      local c = cut()
      check(tag .. ", " .. which[2] .. ": nothing on the run page is cut", #c == 0, table.concat(c, " | "))
      local outB = {}
      for _, b in ipairs(dv.actBtns()) do if b.shown ~= false and not inside(b) then outB[#outB + 1] = tostring(b.label) end end
      check(tag .. ", " .. which[2] .. ": every button lies inside the window", #outB == 0 and #dv.actBtns() >= 3, table.concat(outB, " | "))
      if which[1] == 1 then
        local vs, splits = 0, 0
        for _, fs in ipairs(dv.child.fs) do if fs.shown ~= false and tostring(fs.text):find(R.UP, 1, true) then vs = vs + 1 end end
        for _, b in ipairs(dv.actBtns()) do if b.shown ~= false and b.visit then splits = splits + 1 end end
        check(tag .. ": the slower run reads its 12 bosses against the best, each with its sign and arrow", vs >= 12 and dv.paceLine ~= nil, vs)
        check(tag .. ": Split here on the second visit", splits == 1, splits .. " " .. tostring(R.visitClocks(runs[1]) ~= nil))
      elseif which[1] == 3 then
        local nk = 0
        for _, fs in ipairs(dv.child.fs) do if fs.shown ~= false and fs.text == "Not killed" then nk = nk + 1 end end
        check(tag .. ": the short run lists the 3 bosses it did not kill", nk == 3 and R.view(runs[3], false).total == 12, nk)
      else
        check(tag .. ": a run with no boss has no Pace and no VS BEST", dv.paceLine == nil)
      end
    end
    dv:Hide()
    local lv = T.dungeonList(); lv:Show(); M.settle()
    check(tag .. ": the hour line and the lock line are not cut", not lv.hourFS:IsTruncated() and lv.hourFS.text:find("^Instances this hour: ") ~= nil, lv.hourFS.text)
    -- (the longest real name may be cut in its cell: the hover says it in full, checked below)
    local cutL = {}
    for _, r in ipairs(lv.tbl.rows) do if r.shown ~= false and r.run then for k, fs in pairs(r.c) do if fs.IsTruncated and fs:IsTruncated() and not (k == "name" and r.run.name == "The Temple of Atal'Hakkar") then cutL[#cutL + 1] = k .. "=" .. tostring(fs.text) end end end end
    local wd = {}
    for _, r in ipairs(lv.tbl.rows) do if r.shown ~= false and r.run and not wd[1] then for k, fs in pairs(r.c) do local bx = P.box(fs); wd[#wd + 1] = k .. "=" .. (bx and math.floor(bx.w) or -1) end end end
    check(tag .. ": RUNS: LENGTH with its delta and BOSSES 9/12 are not cut", #cutL == 0, table.concat(cutL, " | ") .. " || " .. table.concat(wd, " "))
    check(tag .. ": the view buttons lie inside the window", inside(lv.viewBtn.runs) and inside(lv.viewBtn.dungeons))
    -- the view switch and the dungeon pick, with the longest real name picked, lie over no tab
    lv.pickInst("The Temple of Atal'Hakkar"); M.settle()
    local over = {}
    local function meets(a, b) return a and b and a.l < b.l + b.w and b.l < a.l + a.w and a.t < b.t + b.h and b.t < a.t + a.h end
    for nm, f in pairs({ runs = lv.viewBtn.runs, dungeons = lv.viewBtn.dungeons, pick = lv.pick }) do
      for _, tb in ipairs(lv.tabs.tabs) do if meets(P.box(f), P.box(tb)) then over[#over + 1] = nm .. " over " .. tostring(tb.key) end end
      if not inside(f) then over[#over + 1] = nm .. " outside the window" end
    end
    check(tag .. ": no view button and no dungeon pick lies over a tab, with a long dungeon picked", #over == 0 and #lv.shown == 1, table.concat(over, " | "))
    lv.pickInst(nil); M.settle()
    -- a long name: the hover says it in full, with what the cell leaves out
    local longRow
    for _, r in ipairs(lv.tbl.rows) do if r.shown ~= false and r.run and r.run.name == "The Temple of Atal'Hakkar" then longRow = r end end
    if longRow then longRow:GetScript("OnEnter")(longRow) end
    check(tag .. ": the hover of a run names it in full, kept included", longRow and _G.GameTooltip.lines[1] == "The Temple of Atal'Hakkar  ·  kept"
      and longRow.c.name.text == "The Temple of Atal'Hakkar", longRow and _G.GameTooltip.lines[1])
    if longRow then longRow:GetScript("OnLeave")(longRow) end
    lv.setView("dungeons"); M.settle()
    local cutD = {}
    for _, r in ipairs(lv.dtbl.rows) do if r.shown ~= false and r.drow then for k, fs in pairs(r.c) do if fs.IsTruncated and fs:IsTruncated() then cutD[#cutD + 1] = k .. "=" .. tostring(fs.text) end end end end
    check(tag .. ": BY DUNGEON lists the three dungeons, nothing cut", #lv.dshown == 3 and lv.dungHost:IsShown() and not lv.runsHost:IsShown() and #cutD == 0, table.concat(cutD, " | "))
    local first
    for _, r in ipairs(lv.dtbl.rows) do if r.shown ~= false and r.drow and r.drow.name == "Blackrock Depths" then first = r end end
    if first then first:GetScript("OnClick")(first, "LeftButton"); M.settle() end
    check(tag .. ": a click on a dungeon filters RUNS to it", lv.st.view == "runs" and lv.st.inst == "Blackrock Depths" and #lv.shown == 3, lv.st.inst)
    lv.pickInst(nil)
    me.dungeonRuns, me.dungeonRun, me.dungeonStats = keep, keepOpen, keepStats
  end

  -- ── the framework pieces this step added
  do
    local hostF = CreateFrame("Frame", nil, _G.EverbuffFrame)
    hostF:SetPoint("TOPLEFT", _G.EverbuffFrame, "TOPLEFT", 160, -100); hostF:SetPoint("BOTTOMRIGHT", _G.EverbuffFrame, "BOTTOMRIGHT", -14, 14)
    UI.SetWindowSize(900, 580)
    -- a header-less table starts its rows at `top`
    local feed = UI.Table(hostF, { { key = "a", label = "A", kind = "tag", measure = { "00:00" } }, { key = "b", label = "Bee", flex = 1 } }, { top = -8, header = false })
    feed.setRows({ { "x" }, { ebSection = "TODAY", ebIndent = 12 }, { "y" } }, function(row, it) row.c.a:SetText("12:00"); row.c.b:SetText(it[1]) end)
    M.settle()
    check("Table header=false: no header, the list starts at top", feed.header.shown == false and near(P.box(feed.sf).t, P.box(hostF).t + 8))
    check("Table sections: the section row shows its text, takes no mouse, fill skips it",
      feed.rows[2].section.text == "TODAY" and feed.rows[2]._mouse == false and feed.rows[2].c.b.text == "" and feed.rows[1]._mouse == true)
    check("Table sections: indented by ebIndent", near(P.box(feed.rows[2].section).l, P.box(feed.rows[2]).l + 8 + 12))
    eq("Table sections: tbl.sections() lists them", #feed.sections(), 1)
    feed.setRows({ { "z" } }, function(row, it) row.c.b:SetText(it[1]) end)
    check("Table sections: a pooled section row becomes a normal row again", feed.rows[1].section == nil or feed.rows[1].section.shown == false)
    -- a flex column is never narrower than its header
    local narrow = UI.Table(hostF, {
      { key = "a", label = "A", kind = "tag", measure = { ("0"):rep(90) } },
      { key = "b", label = "While fighting", flex = 1, min = 10 },
    }, { top = -8 })
    narrow.setRows({ { 1 } }, function(row) row.c.b:SetText("x") end)
    M.settle()
    check("Table: a flex column keeps its header's width", not narrow.head.b.fs:IsTruncated() and narrow.cols.b.w >= P.G.naturalWidth(narrow.head.b.fs) - 0.5, narrow.cols.b.w)
    -- UI.Columns: fixed columns from their measure, flex shares the rest, inside the width
    local cols = UI.Columns({ { key = "t", measure = { "23:59:59" } }, { key = "n", flex = 1 }, { key = "q", measure = { "x999" } } }, 400, { inset = 8 })
    check("Columns: fixed widths measured, flex takes the rest, the last ends inside", cols.t.x == 8 and cols.t.w >= 40 and cols.q.x + cols.q.w <= 400 - 8 + 0.5 and cols.n.w > 100, ("%d %d %d"):format(cols.t.w, cols.n.w, cols.q.x + cols.q.w))
    -- UI.SummaryLine + UI.Below: a wrapping summary pushes the list down
    local s = UI.SummaryLine(hostF, nil, nil, true)
    local below = UI.Below(hostF, s)
    s:SetText("short")
    local y1 = P.box(below).t
    s:SetText(("a long summary line with numbers 1,234  ·  "):rep(12))
    check("SummaryLine: a long summary wraps inside the pane, the list below moves down", P.box(below).t > y1 and not s:IsTruncated() and P.box(s).l + P.box(s).w <= P.box(hostF).l + P.box(hostF).w - UI.SCROLLBAR + 0.5)
    hostF:Hide()
  end

  check("others: no pane errors", #UI.paneErrors() == 0, table.concat(UI.paneErrors(), " || "))
end
