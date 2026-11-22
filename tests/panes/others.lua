-- Pane tests: every other list on the layout framework (plan step 8). Home / Overview, Timeline and Sessions (Character
-- has its own file, tests/panes/character.lua); Combat / Fights (list, replay and a member's view) and
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
    f1.zone, f2.zone = "Wailing Caverns", "Wailing Caverns"   -- (a run's pulls are in its instance, B3)
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
    { "home", "overview" }, { "home", "sessions" },
    { "combat", "fights" }, { "combat", "deaths" },               -- (Dungeons: tests/panes/dungeons.lua)
  }
  local HOST = { home = "Home", combat = "Combat" }
  for _, size in ipairs({ { 900, 580 }, { 1600, 1000 } }) do
    for _, data in ipairs({ "normal", "long" }) do
      for _, pg in ipairs(PAGES) do
        local tag = ("%s/%s %dx%d %s"):format(pg[1], pg[2], size[1], size[2], data)
        local content = P.open(pg[1], pg[2], size[1], size[2], data)
        addRun(); reopen(HOST[pg[1]], pg[2])
        check(tag .. ": the pane opened", content ~= nil)
        if content then
          local tbls = audit(tag, content)
          if pg[2] ~= "overview" then
            local kit = 0
            for _, f in ipairs(P.descendants(content)) do if rawget(f, "ebKitTable") and P.visible(f) then kit = kit + 1 end end
            check(tag .. ": the pane shows a table", #tbls + kit >= 1, #tbls + kit)
          end
        end
      end
    end
  end

  -- (Home > Now has its own file, tests/panes/home.lua)

  -- (Home > Sessions has its own file, tests/panes/sessions.lua; Home > Activity is removed)

  -- ── Home / Fights (a kit page): day and run rows, sorting by a header, durations in one dialect
  do
    local c = P.open("combat", "fights", 900, 580)
    addRun(); reopen("Combat", "fights")
    local fl = T.fightsList()
    local tbl = fl.tbl
    local runHead, dayHead = nil, nil
    for _, s in ipairs(tbl.sections()) do
      local t = tostring(s.text):lower()
      if t:find("wailing caverns", 1, true) then runHead = s.text end
      if t:find("pull", 1, true) then dayHead = s.text end
    end
    check("Fights: a run row heads the fights inside a dungeon run", runHead ~= nil)
    check("Fights: a day row counts its pulls (A4)", dayHead ~= nil, dayHead)
    -- (a count only when somebody died: "nobody died" is not said of a list that holds only the stored pulls)
    if runHead then check("Fights: the run row names its death count, or none (A7)", tostring(runHead):lower():find("nobody died", 1, true) == nil, runHead) end
    local bad = {}
    for i = 1, tbl.shownN do
      local r = tbl.rows[i]
      if r.fight then
        local d = tostring(r.c.dur.text or "")
        if d:find(":", 1, true) then bad[#bad + 1] = d end
        if tostring(r.c.foe.text):find("player", 1, true) then bad[#bad + 1] = "size in name" end
      elseif r.item and r.item.ebSection then
        if r.section and r.section.shown ~= false and not near(P.box(r.section).l, P.box(tbl.frame).l + UI.S.S3) then bad[#bad + 1] = "group row x" end
      end
    end
    check("Fights: lengths read 1m 10s, never mm:ss; the party size is not in the name (A6)", #bad == 0, table.concat(bad, ","))
    -- sort by Length: no sections, longest first, the glyph on Length
    local hb = tbl.head.dur
    hb:GetScript("OnClick")(hb)
    if tbl.sortAsc then hb:GetScript("OnClick")(hb) end
    local prev, ordered, n = math.huge, true, 0
    for i = 1, tbl.shownN do
      local r = tbl.rows[i]
      if r.item and r.item.ebSection then ordered = false end
      local d = r.fight and r.fight.duration or 0
      if d > prev then ordered = false end
      prev = d; n = n + 1
    end
    check("Fights: sorted by length, longest first, without day rows", ordered and n > 2)
    check("Fights: the sort glyph sits on the Length header", hb.glyph and hb.glyph.shown ~= false and tbl.sortKey == "dur")
    for _ = 1, 2 do
      if not (tbl.sortKey == "time" and tbl.sortAsc == false) then tbl.head.time:GetScript("OnClick")(tbl.head.time) end
    end
    check("Fights: back to newest first with the day rows", #tbl.sections() >= 1 and tbl.sortKey == "time" and tbl.sortAsc == false)
    local r1
    for i = 1, tbl.shownN do local r = tbl.rows[i]; if r.fight then r1 = r; break end end
    r1:GetScript("OnEnter")(r1)
    check("Fights: the tooltip ends with the click hint", _G.GameTooltip.lines[#_G.GameTooltip.lines] == "Click to open the replay")
    r1:GetScript("OnLeave")(r1)
    -- the control row as on Activity
    local sb, fb = P.box(fl.search), P.box(fl.filter)
    check("Fights: the search is 176 x 24, S2 left of the filter (A3)", near(sb.w, 176) and near(sb.h, 24) and near(fb.l - (sb.l + sb.w), UI.S.S2), ("%s x %s, gap %s"):format(sb.w, sb.h, fb.l - (sb.l + sb.w)))
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

  -- ── Combat / Deaths: the summary wraps and the table moves below it; no gear column (the loss is the same on every row)
  do
    local c = P.open("combat", "deaths", 900, 580, "long")
    addRun(); reopen("Combat", "deaths")
    local sb, hb = P.box(c.summary), P.box(c.tbl.header)
    check("Deaths: the table starts below the summary", hb.t >= sb.t + sb.h, hb.t - (sb.t + sb.h))
    check("Deaths: the long summary wraps instead of cutting its numbers", not c.summary:IsTruncated())
    local r
    for _, x in ipairs(shownRows(c.tbl)) do if x.c.by.text == "Mutanus the Devourer" then r = x end end
    check("Deaths: the open marker is a cell of its own, and there is no gear column", r ~= nil and r.c.gear == nil and r.c.open.text == ">" and not tostring(r.c.down.text):find("gear", 1, true),
      r and ("%s|%s"):format(tostring(r.c.open.text), tostring(r.c.down.text)))
    if not r then return end
    r:GetScript("OnClick")(r, "LeftButton")
    check("Deaths: clicking a death opens its fight", host("Home").ctl.active == "fights")
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
    check("Table sections: indented by ebIndent", near(P.box(feed.rows[2].section).l, P.box(feed.rows[2]).l + UI.S.S3 + 12))
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
