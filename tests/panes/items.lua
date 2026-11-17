-- Pane tests: Loot / Items on UI.Table (tests/panes/framework.lua explains how pane tests work).
-- At 900x580 and 1600x1000, on normal and long data, in both modes: header x == cell x per column, rows span the
-- list, time, quantity, drops and coordinates never shorten and stay right of nothing they should not cross, the
-- toolbar sits on the spacing grid without overlaps, the quest badge is its own text beside the name, the item
-- tooltip sits on the name cell with the full text of shortened cells, and no loot shows the centred empty text.
return function(P)
  local check, eq, M, ns = P.check, P.eq, P.M, P.ns
  local UI = ns.UI
  local tip = _G.GameTooltip
  local function near(a, b) return a and b and math.abs(a - b) < 0.51 end
  local function right(b) return b.l + b.w end
  local function overlaps(a, b) return a.l < right(b) - 0.5 and b.l < right(a) - 0.5 and a.t < b.t + b.h - 0.5 and b.t < a.t + a.h - 0.5 end
  local EMPTY = "No loot yet. Items and coin you pick up show here."

  -- the pane keeps its mode, filter and search between opens: every check starts from Newest, All, no search
  local function reset(content)
    content.search:SetText(""); content.search.scripts.OnTextChanged(content.search)
    local all = content.lootQualityButtons[1]; all.scripts.OnClick(all)
  end
  local function modeButton(content)
    for _, f in ipairs(P.descendants(content)) do
      if f._kind == "Button" and f.text and (f.text.text == "By item" or f.text.text == "Newest") and f.parentFrame == content then return f end
    end
  end
  local function setMode(content, mode)
    if content.lootMode() ~= mode then local b = modeButton(content); b.scripts.OnClick(b); M.settle() end
  end
  local function open(w, h, data, mode)
    local content = P.open("loot", "items", w, h, data)
    setMode(content, "newest"); reset(content); setMode(content, mode or "newest"); M.settle()
    return content
  end
  local function shown(rows) local out = {}; for _, r in ipairs(rows or {}) do if r.shown ~= false then out[#out + 1] = r end end return out end

  for _, mode in ipairs({ "newest", "byitem" }) do
    for _, size in ipairs({ { 900, 580 }, { 1600, 1000 } }) do
      for _, data in ipairs({ "normal", "long" }) do
        local tag = ("Items %s %dx%d %s"):format(mode, size[1], size[2], data)
        local content = open(size[1], size[2], data, mode)
        local tbl = content.lootTables[mode]
        local other = content.lootTables[mode == "newest" and "byitem" or "newest"]
        local rows = shown(tbl.rows)
        check(tag .. ": the list has rows", #rows >= 3, #rows)
        check(tag .. ": only this mode's table shows", P.visible(tbl.sf) and P.visible(tbl.header) and not P.visible(other.sf) and not P.visible(other.header))
        eq(tag .. ": the pane hands its live rows to readers", content.lootRows, tbl.rows)
        -- header and cells share one x per column
        local bad = {}
        for _, col in ipairs(tbl.spec) do
          local hb = tbl.head[col.key]
          local hx = P.box(hb.fs or hb).l
          for i, r in ipairs(rows) do
            local cx = P.box(r.c[col.key]).l
            if not near(hx, cx) then bad[#bad + 1] = ("%s row %d: %s vs %s"):format(col.key, i, tostring(hx), tostring(cx)) end
          end
        end
        check(tag .. ": header x == cell x in every column", #bad == 0, table.concat(bad, "; "))
        -- rows span the list; the last column ends inside it
        local sfb = P.box(tbl.sf)
        local narrow = {}
        for i, r in ipairs(rows) do local b = P.box(r); if not (b and near(b.w, math.floor(sfb.w))) then narrow[#narrow + 1] = i .. ":" .. tostring(b and b.w) end end
        check(tag .. ": every row spans the list", #narrow == 0, table.concat(narrow, ","))
        local lastKey = tbl.spec[#tbl.spec].key
        local cw = tbl.cols[lastKey]
        local dump = {}; for _, col in ipairs(tbl.spec) do dump[#dump + 1] = col.key .. "@" .. tbl.cols[col.key].x .. "+" .. tbl.cols[col.key].w end
        check(tag .. ": the last column ends inside the list", cw.x + cw.w <= sfb.w + 0.5, ("%s %d > %d: %s"):format(lastKey, cw.x + cw.w, sfb.w, table.concat(dump, " ")))
        eq(tag .. ": the list's child is as wide as its frame", tbl.child._w, math.floor(sfb.w))
        -- the number columns sit together at the right, after every text column
        local lastText, firstNum = 0, math.huge
        for _, col in ipairs(tbl.spec) do
          if col.flex then lastText = math.max(lastText, tbl.cols[col.key].x)
          elseif col.key ~= "time" and col.kind ~= "icon" then firstNum = math.min(firstNum, tbl.cols[col.key].x) end
        end
        check(tag .. ": the number columns come after the text columns", firstNum > lastText, ("%s vs %s"):format(firstNum, lastText))
        eq(tag .. ": the list's child is as tall as its rows", tbl.child._h, #rows * UI.ROW_H)
        -- numbers, times, coordinates never shorten; numbers right-aligned, header too
        local cut = {}
        for i, r in ipairs(rows) do
          for _, k in ipairs({ "time", "qty", "drops", "coords" }) do
            local c = r.c[k]
            if c and c:IsTruncated() then cut[#cut + 1] = k .. i .. "=" .. tostring(c.text) end
          end
        end
        check(tag .. ": time, quantity, drops and coordinates are never shortened", #cut == 0, table.concat(cut, ","))
        check(tag .. ": quantity is right-aligned, its header too", rows[1].c.qty._justify == "RIGHT" and tbl.head.qty.fs._justify == "RIGHT")
        if mode == "newest" then
          check(tag .. ": coordinates are right-aligned, their header too", rows[1].c.coords._justify == "RIGHT" and tbl.head.coords.fs._justify == "RIGHT")
        else
          check(tag .. ": drops are right-aligned, their header too", rows[1].c.drops._justify == "RIGHT" and tbl.head.drops.fs._justify == "RIGHT")
        end
        check(tag .. ": the ITEM header sits over the name, not the icon", P.box(tbl.head.item.fs).l >= P.box(rows[1].c.icon).l + P.box(rows[1].c.icon).w)
        -- the toolbar: on the grid, nothing overlapping, nothing shortened, nothing outside the pane
        local cb = P.box(content)
        local mb = modeButton(content)
        local parts = { totals = content.lootTotals, search = content.search, mode = mb }
        for i, b in ipairs(content.lootQualityButtons) do parts["q" .. i] = b end
        local boxes, outside = {}, {}
        for k, f in pairs(parts) do
          local b = P.box(f); boxes[k] = b
          if b.l < cb.l - 0.5 or right(b) > right(cb) + 0.5 or b.t < cb.t - 0.5 then outside[#outside + 1] = k end
        end
        check(tag .. ": the toolbar stays inside the pane", #outside == 0, table.concat(outside, ","))
        local hits = {}
        for ka, a in pairs(boxes) do for kb, b in pairs(boxes) do
          if ka < kb and ka ~= "totals" and kb ~= "totals" and overlaps(a, b) then hits[#hits + 1] = ka .. "/" .. kb end
        end end
        local tw = P.G.naturalWidth(content.lootTotals)
        check(tag .. ": the toolbar controls do not overlap", #hits == 0, table.concat(hits, ","))
        check(tag .. ": the totals line is read in full, left of the mode button", content.lootTotals:IsTruncated() ~= true and boxes.totals.l + tw <= boxes.mode.l, ("%s + %s vs %s"):format(boxes.totals.l, tw, boxes.mode.l))
        check(tag .. ": the totals text starts at the first column's x (TIME header)", near(boxes.totals.l, P.box(tbl.head.time.fs).l), ("%s vs %s"):format(boxes.totals.l, P.box(tbl.head.time.fs).l))
        check(tag .. ": the quality filters start at the list's inset, as the Auctions chips do", near(boxes.q1.l, sfb.l + UI.SP.S), boxes.q1.l - sfb.l)
        check(tag .. ": the search box ends at the header's right edge", near(right(boxes.search), right(P.box(tbl.header))), right(boxes.search))
        local hb = P.box(tbl.header)
        check(tag .. ": the header starts M below the filters", near(hb.t - (boxes.q1.t + boxes.q1.h), UI.SP.M), hb.t - (boxes.q1.t + boxes.q1.h))
        check(tag .. ": the filters start S below the first toolbar row", near(boxes.q1.t - (boxes.search.t + boxes.search.h), UI.SP.S))
      end
    end
  end

  -- the quality filters: sized from their labels, the selected one filled, a click moves the selection
  do
    local content = open(900, 580, "normal")
    local qb = content.lootQualityButtons
    local fits, prevR = true, nil
    for _, b in ipairs(qb) do
      local need = math.ceil(P.G.naturalWidth(b.text)) + 2 * UI.SP.M
      if math.abs(b._w - math.max(44, need)) > 0.5 then fits = false end
      local bb = P.box(b)
      if prevR and not near(bb.l - prevR, UI.SP.XS) then fits = false end
      prevR = right(bb)
    end
    check("Items: each quality filter is as wide as its label plus M each side, XS apart", fits)
    check("Items: All starts selected with a fill, the others not", qb[1].ebSelected == true and not qb[2].ebSelected and not qb[3].ebSelected and not qb[4].ebSelected)
    qb[3].scripts.OnClick(qb[3])
    check("Items: a click selects Rare+ and only Rare+", qb[3].ebSelected == true and not qb[1].ebSelected and content.lootFilter() == 3)
    local rare = true
    for _, r in ipairs(shown(content.lootRows)) do
      if r.item and not r.item.money then local q = (r.item.q or ""):lower(); if q == "ffffffff" or q == "ff9d9d9d" or q == "ff1eff00" then rare = false end end
    end
    check("Items: Rare+ leaves out common and uncommon items", rare)
    qb[1].scripts.OnClick(qb[1])
    local mb = modeButton(content)
    local w1 = mb._w; mb.scripts.OnClick(mb)
    check("Items: the mode button keeps its width when its label flips", mb._w == w1 and mb.text.text == "Newest" and P.G.naturalWidth(mb.text) + 2 * UI.SP.M <= mb._w + 0.5)
    mb.scripts.OnClick(mb)
  end

  -- By item: the drop count is its own column, never inside the source text
  do
    local content = open(900, 580, "normal", "byitem")
    local rows = shown(content.lootRows)
    local suffix, counts = false, true
    for _, r in ipairs(rows) do
      if (r.c.from.text or ""):find("drops", 1, true) then suffix = true end
      if not tostring(r.c.drops.text or ""):match("^%d+$") or tonumber(r.c.drops.text) ~= r.item.drops then counts = false end
    end
    check("Items by item: no 'N drops' suffix in the source", not suffix)
    check("Items by item: the Drops column shows each item's drop count", #rows > 0 and counts)
    eq("Items by item: the drops header", content.lootTables.byitem.head.drops.fs.text, "DROPS")
  end

  -- the quest badge: its own text beside the name, never in it; a long name gives way to it
  for _, data in ipairs({ "normal", "long" }) do
    local content = open(900, 580, data)
    local log = ns.DB.loot.log
    local mine
    for i = #log, 1, -1 do if not log[i].money and log[i].item then mine = log[i]; break end end
    local q = {}
    for k, v in pairs(mine) do q[k] = v end
    q.t = (mine.t or 0) + 5; q.quest = true; q.item = (data == "long") and ("Ancient Bloodstained Letter of the Scarlet Monastery Cathedral"):rep(2) or "Torn Letter"
    log[#log + 1] = q
    ns.UI.Open("Loot", "items"); M.settle()
    local row
    for _, r in ipairs(shown(content.lootRows)) do if r.item == q then row = r end end
    check("Items quest " .. data .. ": the quest pickup is listed", row ~= nil)
    if row then
      eq("Items quest " .. data .. ": the name holds only the name", row.c.item.text, q.item)
      check("Items quest " .. data .. ": the badge says quest and shows", row.questBadge and row.questBadge.text == "quest" and row.questBadge.shown ~= false)
      local nb, bb, col = P.box(row.c.item), P.box(row.questBadge), content.lootTables.newest.cols.item
      local rowL = P.box(row).l
      local nameEnd = nb.l + math.min(nb.w, P.G.naturalWidth(row.c.item))
      check("Items quest " .. data .. ": the badge sits S after the name", near(bb.l - nameEnd, UI.SP.S) or bb.l - nameEnd >= UI.SP.S - 0.5, ("%s vs %s"):format(bb.l, nameEnd))
      check("Items quest " .. data .. ": the badge stays inside the item column", bb.l + P.G.naturalWidth(row.questBadge) <= rowL + col.x + col.w + 0.5)
      if data == "long" then check("Items quest long: the long name shortens to make room", row.c.item:IsTruncated() == true) end
      -- a resize alone (no rebuild) lays the badge out again: the name still gives up the badge's width
      UI.SetWindowSize(1600, 1000); M.settle()
      do
        local col2 = content.lootTables.newest.cols.item
        local nb2, bb2 = P.box(row.c.item), P.box(row.questBadge)
        local bw = math.ceil(P.G.naturalWidth(row.questBadge))
        check("Items quest " .. data .. " after a resize: the name leaves room for the badge", col2.w ~= col.w and near(row.c.item._w, col2.w - bw - UI.SP.S),
          ("name %s, column %s, badge %s"):format(tostring(row.c.item._w), col2.w, bw))
        local nameEnd2 = nb2.l + math.min(nb2.w, P.G.naturalWidth(row.c.item))
        check("Items quest " .. data .. " after a resize: the badge sits S after the name", near(bb2.l - nameEnd2, UI.SP.S), ("%s vs %s"):format(bb2.l, nameEnd2))
      end
      UI.SetWindowSize(900, 580); M.settle()
      -- a row that is not a quest pickup any more hides the badge
      q.quest = nil; ns.UI.Open("Loot", "items"); M.settle()
      check("Items quest " .. data .. ": no badge on a plain pickup", row.questBadge.shown == false or row.item ~= q or not row.isQuest)
      -- the pooled row that showed the badge now shows a plain item: its name has the whole column again
      local tbl, stale = content.lootTables.newest, {}
      for i = 1, tbl.shownN do
        local r = tbl.rows[i]
        if not r.isQuest and not near(r.c.item._w, tbl.cols.item.w) then stale[#stale + 1] = ("row %d name %s, column %s"):format(i, tostring(r.c.item._w), tbl.cols.item.w) end
      end
      check("Items quest " .. data .. ": a reused row's name takes the full column again", #stale == 0, table.concat(stale, "; "))
    end
  end

  -- the item tooltip: on the name cell, the item's link, and the full name when the name is shortened
  do
    local content = open(900, 580, "long")
    local row
    for _, r in ipairs(shown(content.lootRows)) do if r.itemId and r.c.item:IsTruncated() then row = r; break end end
    if not row then for _, r in ipairs(shown(content.lootRows)) do if r.itemId then row = r; break end end end
    check("Items tooltip: an item row was found", row ~= nil)
    if row then
      local linked
      local orig = rawget(tip, "SetHyperlink")
      tip.SetHyperlink = function(self, link) linked = link; self.lines[#self.lines + 1] = "item card" end
      row.scripts.OnEnter(row)
      check("Items tooltip: shows the item's link", tip.shown and tip.owner == row and linked == "item:" .. tostring(row.itemId), linked)
      check("Items tooltip: anchored to the name cell", tip._pts and tip._pts[1] and tip._pts[1].rel == row.c.item)
      if row.c.item:IsTruncated() then
        local full = 0
        for _, l in ipairs(tip.lines) do if l == row.c.item.text then full = full + 1 end end
        eq("Items tooltip: a shortened name is added in full, once", full, 1)
      end
      row.scripts.OnLeave(row)
      check("Items tooltip: leaving hides it", tip.shown == false)
      tip.SetHyperlink = orig
    end
    -- a coin row with nothing to say shows no empty tooltip box
    local coin
    for _, r in ipairs(shown(content.lootRows)) do if not r.itemId and not r.c.item:IsTruncated() and not r.c.from:IsTruncated() and not r.c.loc:IsTruncated() then coin = r; break end end
    if coin then
      coin.scripts.OnEnter(coin)
      check("Items tooltip: a coin row shows no empty tooltip", tip.shown == false or tip:NumLines() > 0)
      coin.scripts.OnLeave(coin)
    end
    check("Items: the icons are cropped to their art", content.lootRows[1].c.icon._tc and content.lootRows[1].c.icon._tc[1] == 0.08)
  end

  -- empty: the existing sentence, centred across the list, the header hidden
  do
    local content = open(900, 580, "normal")
    content.search:SetText("zzzz no such loot"); content.search.scripts.OnTextChanged(content.search)
    local tbl = content.lootTables.newest
    check("Items empty: the existing sentence shows, the header hidden", tbl.empty.shown and tbl.empty.text == EMPTY and tbl.header.shown == false and #shown(tbl.rows) == 0)
    check("Items empty: the sentence is centred across the list", tbl.empty._justify == "CENTER" and #(tbl.empty._pts or {}) == 2)
    content.search:SetText(""); content.search.scripts.OnTextChanged(content.search)
    check("Items empty: clearing the search brings the rows and header back", tbl.header.shown ~= false and #shown(tbl.rows) > 0)
    for _, f in ipairs(P.descendants(content)) do
      if f._isFS and f.text == EMPTY and f ~= tbl.empty and f ~= content.lootTables.byitem.empty then check("Items empty: no old empty text in the list's corner", false) end
    end
  end
end
