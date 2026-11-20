-- Pane tests: every other list on the layout framework (plan step 8). Home / Overview, Timeline and Sessions; Character /
-- Quests, Reputation and Professions; Combat / Fights (list, replay and a member's view) and
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
    { "combat", "fights" }, { "combat", "deaths" },               -- (Dungeons: tests/panes/dungeons.lua)
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

  -- (Home > Now has its own file, tests/panes/home.lua)

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
