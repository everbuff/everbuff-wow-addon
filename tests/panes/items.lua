-- Pane tests: Loot > Items (docs/UX_OVERHAUL.md 4.8) on the kit (UI.KitTable, UI.Segmented, UI.FilterButton,
-- UI.Search; tests/panes/framework.lua explains how pane tests work). At 900x580 and 1600x1000, on normal and long
-- data, in both modes: the control row (Newest · By item, the quality filter, search 176) right-aligned without
-- overlaps; the answer line; the columns of 4.8 with Coords only at WIDE; header x == cell x; numbers in full; day rows
-- over Newest; names in their quality colour; the QUEST badge beside the name; the item tooltip; the empty sentences.
return function(P)
  local check, eq, M, ns = P.check, P.eq, P.M, P.ns
  local UI = ns.UI
  local tip = _G.GameTooltip
  local function near(a, b) return a and b and math.abs(a - b) < 0.51 end
  local function right(b) return b.l + b.w end
  local function shown(rows) local out = {}; for _, r in ipairs(rows or {}) do if r.shown ~= false then out[#out + 1] = r end end return out end
  local function dataRows(tbl) local out = {}; for _, r in ipairs(shown(tbl.rows)) do if r.item and not r.item.ebSection then out[#out + 1] = r end end return out end
  local function keys(tbl) local t = {}; for _, col in ipairs(tbl.spec) do if not col.wide or tbl.cols[col.key] then t[#t + 1] = col.key end end; return table.concat(t, ",") end
  local function typeIn(e, text) e:SetText(text); e.scripts.OnTextChanged(e); M.settle() end
  local function click(b) b.scripts.OnClick(b, "LeftButton"); M.settle() end
  local function strip(s) return (tostring(s or ""):gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

  -- the pane keeps its mode, filter and search between opens: every check starts from Newest, Green and better, no search
  local function open(w, h, data, mode, quality)
    local content = P.open("loot", "items", w, h, data)
    typeIn(content.search, "")
    content.setLootQuality(quality or "green"); content.setLootMode(mode or "newest"); M.settle()
    return content
  end

  for _, mode in ipairs({ "newest", "byitem" }) do
    for _, size in ipairs({ { 900, 580 }, { 1600, 1000 } }) do
      for _, data in ipairs({ "normal", "long" }) do
        local tag = ("Items %s %dx%d %s"):format(mode, size[1], size[2], data)
        local content = open(size[1], size[2], data, mode, "all")
        local G = UI.G
        local winW = G.winW()
        local wide = G.isWide(winW)
        local tbl = content.lootTables[mode]
        local other = content.lootTables[mode == "newest" and "byitem" or "newest"]
        local rows = dataRows(tbl)
        check(tag .. ": the list has rows", #rows >= 3, #rows)
        check(tag .. ": only this mode's table shows", P.visible(tbl.frame) and not P.visible(other.frame))
        eq(tag .. ": the pane hands its live rows to readers", content.lootRows, tbl.rows)
        eq(tag .. ": the columns of 4.8", keys(tbl), mode == "newest" and ("time,icon,item,from,loc,price" .. (wide and ",coords" or "")) or "icon,item,times,qty,first,price")
        -- the control row: segmented, quality filter, search 176, right to left, S2 apart, inside the window
        local seg, qf, se = P.box(content.lootModeControl), P.box(content.lootQuality), P.box(content.search)
        check(tag .. ": the control row: Newest · By item, the quality filter, search 176, S2 apart", near(right(seg) + UI.S.S2, qf.l) and near(right(qf) + UI.S.S2, se.l)
          and near(se.w, UI.SEARCH_W) and right(se) <= P.box(_G.EverbuffFrame).l + winW - G.BOX_R_INSET + 0.5 and near(seg.t, se.t), ("%s %s %s %s"):format(right(seg), qf.l, right(qf), se.l))
        eq(tag .. ": the mode control", content.lootModeControl.value, mode)
        -- header x == cell x, numbers in full, rows inside the column
        local bad = {}
        local colR = P.box(tbl.frame).l + G.mainW(winW)
        for i, r in ipairs(rows) do
          for _, col in ipairs(tbl.spec) do
            local cell = r.c[col.key]
            if cell and tbl.cols[col.key] then
              if col.kind ~= "icon" and not near(P.box(tbl.head[col.key].fs).l, P.box(cell).l) then bad[#bad + 1] = ("%s row %d"):format(col.key, i) end
              if (col.kind == "num" or col.kind == "money" or col.key == "time") and cell:IsTruncated() then bad[#bad + 1] = col.key .. " cut " .. i end
              local cb = P.box(cell)
              if cb.l + cb.w > colR + 0.5 then bad[#bad + 1] = col.key .. " past the column " .. i end
            end
          end
        end
        check(tag .. ": header x == cell x, numbers and times in full, every cell inside the column", #bad == 0, table.concat(bad, "; "):sub(1, 300))
        -- names in their quality colour; a missing price is "-" in fgMuted
        local qbad = {}
        for i, r in ipairs(rows) do
          local q = (r.item.q or "ffffffff"):lower()
          local want = { tonumber(q:sub(3, 4), 16) / 255, tonumber(q:sub(5, 6), 16) / 255, tonumber(q:sub(7, 8), 16) / 255 }
          local got = r.c.item._color
          if q:len() == 8 and r.item.item and not (got and math.abs(got[1] - want[1]) < 0.01 and math.abs(got[2] - want[2]) < 0.01 and math.abs(got[3] - want[3]) < 0.01) and q ~= "ff9d9d9d" then qbad[#qbad + 1] = i end
          if r.c.price:GetText() == "-" and not (r.c.price._color and math.abs(r.c.price._color[1] - UI.C.fgMuted[1]) < 0.01) then qbad[#qbad + 1] = i .. " price" end
        end
        check(tag .. ": names in their quality colour, an unknown price a muted dash", #qbad == 0, table.concat(qbad, ","))
        if mode == "newest" then
          local secs = tbl.sections()
          check(tag .. ": newest first under day rows", #secs >= 1 and secs[1]:GetText():find(" ITEMS?$") ~= nil and rows[1].item.t >= rows[#rows].item.t, secs[1] and secs[1]:GetText())
          local coin = 0
          for _, r in ipairs(rows) do if r.item.money then coin = coin + 1 end end
          eq(tag .. ": no coin row (#38: coin is the Gold pane's)", coin, 0)
        else
          local counts = true
          for _, r in ipairs(rows) do if tonumber(r.c.times:GetText()) ~= r.item.drops or tonumber((r.c.qty:GetText() or ""):gsub(",", ""), 10) ~= r.item.count then counts = false end end
          check(tag .. ": Times and Total are each item's pickups and quantity", counts)
        end
        -- the answer line, with the best item in its colour
        local line = strip(content.lootSummary.Text())
        check(tag .. ": the answer line counts this session's items", line:find("^This session: ") ~= nil, line)
      end
    end
  end

  -- the quality filter: Green and better by default, saved; the menu of 4.8; the empty sentence names the floor
  do
    local content = P.open("loot", "items", 900, 580, "normal")
    ns.DB.settings.itemsQuality = nil
    content.setLootMode("newest"); content.setLootQuality("green")
    check("Items: Green and better is the filter's default: quiet, no clear glyph", content.lootQuality.text:GetText() == "Green and better" and not content.lootQuality.ebActive and ns.DB.settings.itemsQuality == "green")
    click(content.lootQuality)
    local labels = {}
    for _, r in ipairs(content.lootQuality.menu.rows) do if r.shown ~= false then labels[#labels + 1] = r.text:GetText() end end
    eq("Items: the quality menu", table.concat(labels, ","), "Everything,White and better,Green and better,Blue and better,Purple and better")
    local blue
    for _, r in ipairs(content.lootQuality.menu.rows) do if r.text:GetText() == "Blue and better" then blue = r end end
    click(blue)
    check("Items: Blue and better is active with its clear glyph and saved", content.lootQuality.ebActive and content.lootQuality.clear.shown ~= false and ns.DB.settings.itemsQuality == "blue" and content.lootFilter() == 3)
    local low = {}
    for _, r in ipairs(dataRows(content.lootTables.newest)) do
      local q = (r.item.q or ""):lower(); if q == "ffffffff" or q == "ff9d9d9d" or q == "ff1eff00" then low[#low + 1] = tostring(r.item.item) .. " " .. q end
    end
    check("Items: Blue and better leaves out grey, white and green items", #low == 0, table.concat(low, ", "))
    click(content.lootQuality.clear)
    check("Items: the clear glyph goes back to Green and better", content.lootFilter() == 2 and not content.lootQuality.ebActive)
    -- By item: saved; its default sort is Total
    click(content.lootModeControl.segs[2])
    check("Items: By item is picked and saved", content.lootMode() == "byitem" and ns.DB.settings.itemsMode == "byitem" and select(2, content.lootFilter()) == "qty")
    click(content.lootModeControl.segs[1])
    -- empty sentences
    local log = ns.DB.loot.log
    local keep = {}
    for i = #log, 1, -1 do keep[i] = log[i]; log[i] = nil end
    content.setLootQuality("green")
    local tbl = content.lootTables.newest
    eq("Items empty: the sentence of 4.8 at Green and better", tbl.stateFS:GetText(), "Loot anything green or better and it shows here. Lower the quality filter to see grey and white items.")
    check("Items empty: the answer line says nothing yet", strip(content.lootSummary.Text()) == "This session: nothing green or better yet", strip(content.lootSummary.Text()))
    content.setLootQuality("all")
    eq("Items empty: at Everything", tbl.stateFS:GetText(), "Loot anything and it shows here, with where it came from.")
    for i, e in pairs(keep) do log[i] = e end
    content.setLootQuality("green")
    typeIn(content.search, "zzzz no such loot")
    check("Items no match: the sentence and Clear search", tbl.stateFS:GetText() == 'No item matches "zzzz no such loot". ' and tbl.stateLink.shown ~= false and #dataRows(tbl) == 0)
    typeIn(content.search, "")
    check("Items: clearing the search brings the rows back", #dataRows(tbl) > 0)
  end

  -- the quest badge: its own kit badge beside the name, never in it; a long name gives way to it
  for _, data in ipairs({ "normal", "long" }) do
    local content = open(900, 580, data, "newest", "all")
    local log = ns.DB.loot.log
    local mine
    for i = #log, 1, -1 do if not log[i].money and log[i].item and ns.isMine(log[i]) then mine = log[i]; break end end
    local q = {}
    for k, v in pairs(mine) do q[k] = v end
    q.t = (mine.t or 0) + 5; q.quest = true; q.item = (data == "long") and ("Ancient Bloodstained Letter of the Scarlet Monastery Cathedral"):rep(2) or "Torn Letter"
    log[#log + 1] = q
    content.setLootQuality("all")
    local row
    for _, r in ipairs(dataRows(content.lootTables.newest)) do if r.item == q then row = r end end
    check("Items quest " .. data .. ": the quest pickup is listed", row ~= nil)
    if row then
      check("Items quest " .. data .. ": the name holds only the name", strip(row.c.item:GetText()):find("^" .. q.item:gsub("%p", "%%%0")) ~= nil and not row.c.item:GetText():find("Quest", 1, true))
      check("Items quest " .. data .. ": the badge says QUEST and shows", row.ebBadge and row.ebBadge.shown ~= false)
      local col = content.lootTables.newest.cols.item
      local bb, rl = P.box(row.ebBadge), P.box(row).l
      check("Items quest " .. data .. ": the badge stays inside the item column", bb.l + bb.w <= rl + col.x + col.w + 0.5, ("%s vs %s"):format(bb.l + bb.w, rl + col.x + col.w))
    end
    log[#log] = nil
    content.setLootQuality("green")
  end

  -- the item tooltip: the item's link; a quest reward names its quest
  do
    local content = open(1250, 760, "gold", "newest", "all")
    local row, questSrc
    for _, r in ipairs(dataRows(content.lootTables.newest)) do
      if r.itemId and not row then row = r end
      if strip(r.c.item:GetText()) == "Pikeman Shield" then questSrc = r.c.from:GetText() end
    end
    eq("Items: a quest's reward names its quest", questSrc, "Quest: The Defias Brotherhood")
    check("Items tooltip: an item row was found", row ~= nil)
    if row then
      local linked
      local orig = rawget(tip, "SetHyperlink")
      tip.SetHyperlink = function(self, link) linked = link; self.lines[#self.lines + 1] = "item card" end
      row.scripts.OnEnter(row)
      check("Items tooltip: shows the item's link", tip.shown and linked == "item:" .. tostring(row.itemId), linked)
      row.scripts.OnLeave(row)
      check("Items tooltip: leaving hides it", tip.shown == false)
      tip.SetHyperlink = orig
    end
    content.setLootQuality("green")
  end
end
