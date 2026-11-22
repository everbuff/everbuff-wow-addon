-- Pane tests: the layout framework in Everbuff/UI.lua (UI.ScrollChild, UI.Table, UI.CellFS, UI.EditBox, the window).
--
-- How pane tests work. tests/run_tests.lua runs every tests/panes/*.lua after the main suite and its layout sweep, in
-- name order. Each file returns function(P); P carries the suite's helpers:
--   P.check(name, cond, detail)        one assertion; P.eq(name, got, want) compares
--   P.open(host, pane, w, h, data)     the window at w x h with the suite's data ("normal") or the same data made
--                                      long ("long": long names, gold three digits larger), the pane opened, every
--                                      OnSizeChanged delivered; returns the pane's content frame
--   P.box(region)                      the region's absolute box { l, t, w, h } (y down), from tests/geometry.lua
--   P.visible(region), P.descendants(root), P.scrollFrames(root), P.hosts() (every { host, pane })
--   P.M (tests/wow_stub.lua: M.settle(), GameTooltip.lines), P.ns, P.G (geometry), P.Lay (tests/layout.lua)
-- GetWidth, GetStringWidth and IsTruncated answer from the resolved layout with the addon's real fonts, so a pane's
-- own sizing code runs as in game. A pane file checks, at 900x580 and 1600x1000 on normal and long data: the list's
-- child is as wide as its scroll frame, rows are wider than 0, header x == cell x, numbers right-aligned and never
-- shortened, nothing past the viewport.
return function(P)
  local check, eq, M, ns = P.check, P.eq, P.M, P.ns
  local UI = ns.UI
  local function near(a, b) return a and b and math.abs(a - b) < 0.51 end

  -- ── UI.ScrollChild: the child follows its scroll frame's width in every pane, at both window sizes and after a resize
  for _, size in ipairs({ { 900, 580 }, { 1600, 1000 }, { 900, 580 } }) do
    local bad, seen = {}, 0
    for _, hp in ipairs(P.hosts()) do
      local content = P.open(hp.host, hp.pane, size[1], size[2])
      for _, sf in ipairs(content and P.scrollFrames(content) or {}) do
        local b = P.box(sf)
        if b and b.w > 1 then
          seen = seen + 1
          if not near(sf.child._w, math.floor(b.w)) then bad[#bad + 1] = ("%s/%s child %s, frame %d"):format(hp.host, hp.pane, tostring(sf.child._w), b.w) end
          -- the child is as tall as what it holds, so the list scrolls to its last row
          local cb, low = P.box(sf.child), 0
          for _, f in ipairs(P.descendants(sf.child)) do
            -- (an empty-state text in the child draws without a height: the scroll frame clips to its own box)
            if f.parentFrame == sf.child and f ~= rawget(sf.child, "empty") and P.visible(f) and (not f._isFS or (f.text and f.text ~= "")) then
              local fb = P.box(f)
              if fb then low = math.max(low, fb.t + fb.h - cb.t) end
            end
          end
          if low > (sf.child._h or 0) + 1 then bad[#bad + 1] = ("%s/%s content %d px, child %s high"):format(hp.host, hp.pane, low, tostring(sf.child._h)) end
        end
      end
    end
    check(("ScrollChild %dx%d: the panes' lists were measured"):format(size[1], size[2]), seen >= 8, seen)
    check(("ScrollChild %dx%d: every list's child is as wide as its scroll frame"):format(size[1], size[2]), #bad == 0, table.concat(bad, "; "))
  end

  -- a scroll child on its own: SetContentHeight sets the height, onResize hears the width, the gutter is left free
  do
    local host = CreateFrame("Frame", nil, _G.EverbuffFrame)
    host:SetPoint("TOPLEFT", _G.EverbuffFrame, "TOPLEFT", 20, -20); host:SetPoint("BOTTOMRIGHT", _G.EverbuffFrame, "BOTTOMRIGHT", -20, 20)
    local sf, child = UI.ScrollChild(host, { top = -8 })
    local heard = {}
    sf.onResize = function(w) heard[#heard + 1] = w end
    sf:SetContentHeight(123.2)
    UI.SetWindowSize(900, 580)
    eq("ScrollChild: SetContentHeight rounds up", child._h, 124)
    eq("ScrollChild: the scroll bar gutter is left at the right", P.box(sf).w, 900 - 40 - UI.SCROLLBAR)
    eq("ScrollChild: the child takes the frame's width", child._w, 900 - 40 - UI.SCROLLBAR)
    UI.SetWindowSize(1200, 700)
    eq("ScrollChild: a resize reaches the child", child._w, 1200 - 40 - UI.SCROLLBAR)
    check("ScrollChild: onResize heard both widths", heard[#heard] == 1200 - 40 - UI.SCROLLBAR and #heard >= 2, table.concat(heard, ","))
    sf:SetContentHeight(0)
    eq("ScrollChild: an empty list is 1 px high, never 0", child._h, 1)
    host:Hide()
  end

  -- ── UI.Table: one column model for the header and the cells
  -- longer than any column at 1600 px, so it always shortens
  local function longName(n) return ("Gnarled Staff of the Scarlet Monastery Cathedral %d "):format(n):rep(30) end
  local items = {}
  for i = 1, 6 do items[i] = { name = i == 3 and longName(i) or ("Linen Cloth " .. i), qty = i * 7, price = i == 2 and 1234567890 or i * 1013, tag = i % 2 == 0 and "quest" or "" } end
  local sorted, clicked = {}, {}
  local host = CreateFrame("Frame", nil, _G.EverbuffFrame)
  host:SetPoint("TOPLEFT", _G.EverbuffFrame, "TOPLEFT", 160, -100); host:SetPoint("BOTTOMRIGHT", _G.EverbuffFrame, "BOTTOMRIGHT", -14, 14)
  local tbl = UI.Table(host, {
    { key = "icon", kind = "icon" },
    { key = "name", label = "Item", flex = 1, min = 120, sort = true },
    { key = "tag", label = "", kind = "tag" },
    { key = "qty", label = "Qty", kind = "num", sort = true, measure = { "9999" } },
    { key = "price", label = "Price", kind = "money", sort = true },
  }, { top = -24, sortKey = "qty", sortAsc = false, emptyText = "Nothing yet.",
       onSort = function(k, asc) sorted[#sorted + 1] = { k, asc } end,
       tooltip = function(row, item, tip) tip:AddLine("own line " .. item.name) end,
       onClick = function(row, item) clicked[#clicked + 1] = item end })
  local function fill(row, it)
    row.c.icon:SetTexture(134400)
    row.c.name:SetText(it.name); row.c.tag:SetText(it.tag); row.c.qty:SetText(tostring(it.qty)); row.c.price:SetText(ns.fmtMoney(it.price))
  end
  local function tableChecks(tag)
    local bad, rows = {}, 0
    for _, col in ipairs(tbl.spec) do
      local hb = tbl.head[col.key]
      for i = 1, #items do
        local cell = tbl.rows[i].c[col.key]
        local hx = P.box(hb.fs or hb).l
        local cx = P.box(cell).l
        if not near(hx, cx) then bad[#bad + 1] = ("%s row %d: header %s, cell %s"):format(col.key, i, tostring(hx), tostring(cx)) end
      end
    end
    check(tag .. ": header x == cell x in every column", #bad == 0, table.concat(bad, "; "))
    local sfw = P.box(tbl.sf).w
    local narrow = {}
    for i = 1, #items do
      local b = P.box(tbl.rows[i]); rows = rows + 1
      if not (b and b.w > 0 and near(b.w, math.floor(sfw))) then narrow[#narrow + 1] = i .. ":" .. tostring(b and b.w) end
    end
    check(tag .. ": every row spans the list (TOPLEFT + TOPRIGHT of the child)", #narrow == 0 and rows == #items, table.concat(narrow, ","))
    local cut = {}
    for i = 1, #items do
      for _, k in ipairs({ "qty", "price", "tag" }) do if tbl.rows[i].c[k]:IsTruncated() then cut[#cut + 1] = k .. i end end
    end
    check(tag .. ": numbers, money and tags are never shortened", #cut == 0, table.concat(cut, ","))
    check(tag .. ": the long name shortens (only names do)", tbl.rows[3].c.name:IsTruncated() == true)
    local last = tbl.cols.price
    check(tag .. ": the last column ends inside the list", last.x + last.w <= sfw + 0.5, ("%d > %d"):format(last.x + last.w, sfw))
    check(tag .. ": the header sits on the list, 1 px rule under it", P.box(tbl.header).t + P.box(tbl.header).h + 1 == P.box(tbl.sf).t and tbl.rule._h == 1)
  end
  tbl.setRows(items, fill)
  UI.SetWindowSize(900, 580)
  tableChecks("Table 900x580")
  local nameW900 = tbl.cols.name.w
  UI.SetWindowSize(1600, 1000)
  tableChecks("Table 1600x1000")
  check("Table: a wider window goes to the flex column", tbl.cols.name.w > nameW900 + 600, ("%d vs %d"):format(tbl.cols.name.w, nameW900))
  UI.SetWindowSize(900, 580)
  check("Table: numbers, money and their headers are right-aligned; text left",
    tbl.rows[1].c.qty._justify == "RIGHT" and tbl.rows[1].c.price._justify == "RIGHT" and tbl.head.qty.fs._justify == "RIGHT"
    and tbl.head.price.fs._justify == "RIGHT" and tbl.rows[1].c.name._justify == "LEFT" and tbl.head.name.fs._justify == "LEFT")
  check("Table: cells are single line", tbl.rows[1].c.name._wrap == false and tbl.rows[1].c.name._maxLines == 1)
  check("Table: rows are Buttons with a HIGHLIGHT texture", tbl.rows[1]._kind == "Button" and tbl.rows[1].highlight._layer == "HIGHLIGHT")
  check("Table: the money column widened to 5-digit gold", tbl.cols.price.w >= math.ceil(P.G.naturalWidth(tbl.rows[2].c.price)), tbl.cols.price.w)
  check("Table: the icon is cropped to its art", tbl.rows[1].c.icon._tc and tbl.rows[1].c.icon._tc[1] == 0.08 and tbl.rows[1].c.icon._tc[4] == 0.92)
  -- the header: uppercase labels, the sort arrow is a texture, a click sorts
  eq("Table: header label is uppercase, no arrow characters in it", tbl.head.qty.fs.text, "QTY")
  check("Table: the arrow shows on the sorted column only", tbl.head.qty.arrow.shown == true and tbl.head.name.arrow.shown == false and tbl.head.price.arrow.shown == false)
  tbl.head.name.scripts.OnClick(tbl.head.name)
  check("Table: a header click sorts by that column, text ascending first", sorted[1] and sorted[1][1] == "name" and sorted[1][2] == true and tbl.head.name.arrow.shown and not tbl.head.qty.arrow.shown)
  tbl.head.name.scripts.OnClick(tbl.head.name)
  check("Table: a second click flips the order", sorted[2] and sorted[2][1] == "name" and sorted[2][2] == false)
  -- the right-aligned column's arrow sits left of its label, inside the column
  tbl.setSort("price", false)
  local ab, pc = P.box(tbl.head.price.arrow), tbl.cols.price
  check("Table: a right-aligned column's arrow sits inside the column, left of the label", ab and ab.l >= P.box(tbl.header).l + pc.x - 0.5 and ab.l + ab.w <= P.box(tbl.header).l + pc.x + pc.w, ab and ab.l)
  -- the row pool: fewer rows hide the rest, more rows reuse them with fresh anchors
  tbl.setRows({ items[1], items[2] }, fill)
  check("Table: fewer rows hide the rest", tbl.rows[3].shown == false and tbl.rows[2].shown == true)
  eq("Table: the list's height is its rows", tbl.child._h, 2 * UI.ROW_H)
  tbl.setRows(items, fill)
  local pts = 0
  for i = 1, #items do pts = math.max(pts, #(tbl.rows[i]._pts or {})) end
  eq("Table: a reused row has two anchors, cleared first", pts, 2)
  -- the row's own tooltip sits on the name cell and also carries the full text of a shortened cell, once
  local tip = _G.GameTooltip
  local r3 = tbl.rows[3]
  r3.scripts.OnEnter(r3)
  local full = 0
  for _, l in ipairs(tip.lines) do if l == longName(3) then full = full + 1 end end
  check("Table: the row's own tooltip shows", tip.shown and tip.owner == r3 and tip.lines[1] == "own line " .. longName(3), tip.lines[1])
  eq("Table: a shortened name is added to the row's tooltip once", full, 1)
  check("Table: the tooltip is anchored to the name cell", tip._pts and tip._pts[1] and tip._pts[1].rel == r3.c.name)
  r3.scripts.OnLeave(r3)
  check("Table: leaving the row hides its tooltip", tip.shown == false)
  r3.scripts.OnClick(r3, "LeftButton")
  check("Table: a click hands the row's item to onClick", clicked[1] == items[3])
  check("Table: rows take the left button only (a right click opens nothing)", r3._clicks and #r3._clicks == 1 and r3._clicks[1] == "LeftButtonUp", r3._clicks and table.concat(r3._clicks, ","))
  do
    local h2 = CreateFrame("Frame", nil, _G.EverbuffFrame)
    h2:SetPoint("TOPLEFT", _G.EverbuffFrame, "TOPLEFT", 160, -100); h2:SetSize(300, 200)
    local t2 = UI.Table(h2, { { key = "name", label = "Name", flex = 1 } }, { onClick = function() end, rightClick = true })
    t2.setRows({ { name = "x" } }, function(row, it) row.c.name:SetText(it.name) end)
    check("Table: opts.rightClick registers the right button too", t2.rows[1]._clicks and #t2.rows[1]._clicks == 2)
    h2:Hide()
  end
  -- a resize places only the rows showing; a pooled row is placed when it is used again
  tbl.setRows({ items[1], items[2] }, fill)
  UI.SetWindowSize(1250, 760)
  check("Table: a resize lays out the rows showing, not the hidden pool",
    tbl.shownN == 2 and tbl.rows[1].ebGen == tbl.gen and tbl.rows[2].ebGen == tbl.gen and tbl.rows[3].ebGen ~= tbl.gen, ("%s %s"):format(tostring(tbl.rows[3].ebGen), tbl.gen))
  tbl.setRows(items, fill)
  check("Table: a pooled row used again is placed for the current layout", tbl.rows[3].ebGen == tbl.gen and tbl.rows[6].ebGen == tbl.gen)
  tableChecks("Table 1250x760 after reuse")
  UI.SetWindowSize(900, 580)
  -- the empty state: header hidden, the text centred and wrapping across the list
  tbl.setRows({}, fill)
  check("Table: no rows shows the empty text, the header hidden", tbl.empty.shown and tbl.empty.text == "Nothing yet." and tbl.header.shown == false and tbl.rows[1].shown == false)
  check("Table: the empty text is centred and wraps", tbl.empty._justify == "CENTER" and tbl.empty._wrap ~= false and #(tbl.empty._pts or {}) == 2)
  tbl.setRows(items, fill)
  check("Table: rows again bring the header back", tbl.header.shown and not tbl.empty.shown)
  host:Hide()

  -- ── dragging the resize grip: lists are laid out again at most every UI.RESIZE_STEP and once when it is let go
  do
    local f = _G.EverbuffFrame
    local host2 = CreateFrame("Frame", nil, f)
    host2:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -20); host2:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20, 20)
    local sf2 = UI.ScrollChild(host2, { top = -8 })
    local heard = {}
    sf2.onResize = function(w) heard[#heard + 1] = w end
    UI.SetWindowSize(900, 580); P.M.runTimers()
    local n0 = #heard
    f.grip.scripts.OnMouseDown(f.grip)
    check("resize grip: pressing it marks the drag", UI.sizing == true)
    f:SetSize(1000, 600); f:SetSize(1100, 640); f:SetSize(1200, 700)
    eq("resize grip: the child follows the frame at once", sf2.child._w, 1200 - 40 - UI.SCROLLBAR)
    eq("resize grip: no layout on each frame of the drag", #heard, n0)
    P.M.runTimers()
    check("resize grip: the step timer lays the list out once, at the newest width", #heard == n0 + 1 and heard[#heard] == 1200 - 40 - UI.SCROLLBAR, table.concat(heard, ","))
    f:SetSize(1300, 760)
    f.grip.scripts.OnMouseUp(f.grip)
    check("resize grip: letting go lays out the held list at once", UI.sizing == nil and #heard == n0 + 2 and heard[#heard] == 1300 - 40 - UI.SCROLLBAR and UI.PendingResizes() == 0, table.concat(heard, ","))
    P.M.runTimers()
    eq("resize grip: nothing runs twice after the drag", #heard, n0 + 2)
    host2:Hide()
    UI.SetWindowSize(900, 580)
  end

  -- ── CellFS on a list's scroll child (a detail page): one line, but the page never takes the mouse
  do
    local host3 = CreateFrame("Frame", nil, _G.EverbuffFrame)
    host3:SetPoint("TOPLEFT", _G.EverbuffFrame, "TOPLEFT", 20, -20); host3:SetPoint("BOTTOMRIGHT", _G.EverbuffFrame, "BOTTOMRIGHT", -20, 20)
    local _, child3 = UI.ScrollChild(host3, { top = -8 })
    local fs3 = UI.CellFS(child3, "GameFontHighlightSmall")
    check("CellFS: a cell on a scroll child is one line", fs3._wrap == false and fs3._maxLines == 1)
    check("CellFS: a scroll child is never made to take the mouse or hooked", child3._mouse ~= true and child3.scripts.OnEnter == nil)
    host3:Hide()
  end

  -- ── CellFS on a row that builds its own tooltip with SetScript (the panes' existing pattern)
  do
    local box = CreateFrame("Frame", nil, _G.EverbuffFrame)
    box:SetPoint("TOPLEFT", _G.EverbuffFrame, "TOPLEFT", 160, -100); box:SetSize(300, 20)
    local plain = UI.CellFS(box, "GameFontHighlightSmall"); plain:SetPoint("LEFT", 0, 0); plain:SetWidth(60); plain:SetText(longName(9))
    check("CellFS: a plain frame it hooks takes the mouse", box:IsMouseEnabled() == true)
    box.scripts.OnEnter(box)
    check("CellFS: hovering a plain row shows the shortened text in full", tip.shown and tip.lines[1] == longName(9) and tip.anchor == "ANCHOR_NONE" and tip._pts[1].rel == plain, tip.lines[1])
    box.scripts.OnLeave(box)
    check("CellFS: leaving hides it", tip.shown == false)
    local row = CreateFrame("Button", nil, _G.EverbuffFrame)
    row:SetPoint("TOPLEFT", _G.EverbuffFrame, "TOPLEFT", 160, -130); row:SetSize(300, 20)
    row:SetScript("OnEnter", function(r) tip:SetOwner(r, "ANCHOR_RIGHT"); tip:AddLine("the row's own line"); tip:Show() end)
    row:SetScript("OnLeave", function() tip:Hide() end)
    local cell = UI.CellFS(row, "GameFontHighlightSmall"); cell:SetPoint("LEFT", 0, 0); cell:SetWidth(60); cell:SetText(longName(10))
    local short = UI.CellFS(row, "GameFontHighlightSmall"); short:SetPoint("LEFT", 70, 0); short:SetWidth(60); short:SetText("12")
    row.scripts.OnEnter(row)
    check("CellFS: a row's own tooltip keeps its lines and gains the shortened cell's full text",
      tip.shown and tip.lines[1] == "the row's own line" and tip.lines[2] == longName(10) and #tip.lines == 2, table.concat(tip.lines, " | "))
    row.scripts.OnLeave(row)
    row.scripts.OnEnter(row)
    eq("CellFS: hovering again adds the line again, not twice", #tip.lines, 2)
    row.scripts.OnLeave(row)
    box:Hide(); row:Hide()
  end

  -- ── UI.EditBox: the placeholder is a region of the box and follows its text
  do
    local hooked = 0
    local e = UI.EditBox(_G.EverbuffFrame, 180, 20, "search item, source, zone")
    e:HookScript("OnTextChanged", function() hooked = hooked + 1 end)
    check("EditBox: the placeholder belongs to the box", e.placeholder.parentFrame == e and e.placeholder.text == "search item, source, zone")
    check("EditBox: the placeholder shows while the box is empty", e.placeholder.shown == true)
    e:SetText("linen"); e.scripts.OnTextChanged(e)
    check("EditBox: typing hides it and the caller's hook still runs", e.placeholder.shown == false and hooked == 1)
    e:SetText(""); e.scripts.OnTextChanged(e)
    check("EditBox: clearing shows it again", e.placeholder.shown == true and hooked == 2)
    e:Hide()
    local strays = 0
    for _, f in ipairs(P.M.frames) do
      if f._isFS and f.text and (f.text == "search events" or f.text == "search foe or zone" or f.text == "search item, source, zone"
        or f.text == "paste the sync code from the desktop app") and f.parentFrame and f.parentFrame._kind ~= "EditBox" then strays = strays + 1 end
    end
    eq("EditBox: no search hint is drawn on a pane under a box any more", strays, 0)
  end

  -- ── the window: its size stays inside 900x580 to 1600x1000; the chrome sits on the grid of docs/UX_OVERHAUL.md 2.7
  do
    UI.SetWindowSize(5000, 100)
    check("window: SetWindowSize clamps to the bounds", _G.EverbuffFrame._w == 1600 and _G.EverbuffFrame._h == 580 and ns.DB.settings.winSize.w == 1600)
    local w, h = UI.clampWinSize(nil, "x")
    check("window: a missing or broken saved size is the minimum", w == 900 and h == 580)
    w, h = UI.clampWinSize(1200.7, 2000)
    check("window: a saved size is floored and capped", w == 1200 and h == 1000)
    for _, size in ipairs({ { 900, 580 }, { 1600, 1000 } }) do
      local W, H = size[1], size[2]
      UI.SetWindowSize(W, H); ns.UI.Open("Home", "now"); P.M.settle()
      local fr = _G.EverbuffFrame
      local fb = P.box(fr)
      local function rel(f) local b = P.box(f); return b.l - fb.l, b.t - fb.t, b.w, b.h end
      local tag = ("window %dx%d: "):format(W, H)
      local x, y, bw, bh = rel(fr.close)
      check(tag .. "close is 24 x 24 with its box edge on BOX_R", x == W - 48 and y == 8 and bw == 24 and bh == 24, x .. "," .. y)
      x, y, bw = rel(fr.chip)
      check(tag .. "the status chip ends at W - 56, inside the title bar", x + bw == W - 56 and y == 8 and x > 44 + 80, x + bw)
      x, y, bw, bh = rel(fr.strip)
      check(tag .. "the sidebar is 168 wide under the 40 px title bar", x == 1 and y == 40 and x + bw == 167 and y + bh == H - 1, x .. "," .. y .. "," .. bw .. "," .. bh)
      local i = 0
      for _, tab in ipairs(P.T.tabs) do
        x, y, bw, bh = rel(tab.btn)
        if tab.pin == "bottom" then
          check(tag .. tab.name .. " is pinned with its bottom 16 px over the window's", x == 8 and y + bh == H - 16 and bw == 152 and bh == 36, y)
        else
          check(tag .. tab.name .. " sits on the nav rhythm (x 8, y 48 + 36 n, 152 x 36)", x == 8 and y == 48 + 36 * i and bw == 152 and bh == 36, x .. "," .. y)
          i = i + 1
        end
      end
      -- the host draws no title and no subtitle (3.2): its sidebar row and the sub-tab name the page
      local strays = 0
      for _, tab in ipairs(P.T.tabs) do
        if tab.content then
          for _, f in ipairs(P.descendants(tab.content)) do
            if f._isFS and f.text and (f.text == tab.subtitle or (f.text == tab.name and f.parentFrame == tab.content)) then strays = strays + 1 end
          end
        end
      end
      eq(tag .. "no host draws its title or description on the page", strays, 0)
      local home = nil
      for _, tab in ipairs(P.T.tabs) do if tab.name == "Home" then home = tab end end
      local ctl = home.ctl
      x, y, bw, bh = rel(ctl.tabs[1])
      check(tag .. "the first sub-tab starts at TEXT_L on the control row", x == 204 and y == 52 and bh == 28, x .. "," .. y)
      -- (a sub-tab with no page now is not in the row: the ones shown follow each other)
      local shownTabs = {}
      for _, b in ipairs(ctl.tabs) do if not (ctl.hidden and ctl.hidden[b.key]) then shownTabs[#shownTabs + 1] = b end end
      for k = 2, #shownTabs do
        local x1, _, w1 = rel(shownTabs[k - 1]); local x2 = rel(shownTabs[k])
        check(tag .. "sub-tabs are 24 px apart (" .. shownTabs[k].key .. ")", x2 - (x1 + w1) == 24, x2 - (x1 + w1))
      end
      local last = ctl.tabs[#ctl.tabs]; local lx, _, lw = rel(last)
      check(tag .. "the sub-tabs fit on the control row", lx + lw <= W - 36, lx + lw)
      x, y, bw, bh = rel(ctl.panes.now)
      check(tag .. "a pane's box runs from BOX_L to BOX_R and CONTENT_TOP to the bottom margin", x == 192 and y == 92 and x + bw == W - 24 and y + bh == H - 16, x .. "," .. y .. "," .. bw .. "," .. bh)
      check(tag .. "the active sub-tab is underlined in accent, the others are not", ctl.tabs[1].accent._fill and ctl.tabs[1].accent._fill[4] ~= 0 and ctl.tabs[2].accent._fill and ctl.tabs[2].accent._fill[4] == 0)
    end
    UI.SetWindowSize(900, 580)
  end
end
