-- Pane tests: Loot > Items (docs/UX_PRAGMATIC.md 4.1) on the kit (UI.KitTable, UI.Segmented, UI.FilterButton,
-- UI.Search; tests/panes/framework.lua explains how pane tests work). At 900x580 and 1600x1000, on normal and long
-- data, in both modes: the control row (List, By item, the quality filter, search 176) right-aligned without
-- overlaps; no line above the list; the section header that says where the list starts and how many rows it shows;
-- the columns of 4.1 with Coords only at WIDE; header x == cell x; numbers in full; day rows over List; names in
-- their quality colour; the QUEST badge beside the name; the item tooltip; the empty sentences. Then on rows shaped
-- like a real save's: what From and Place say, the rows that are not loot, and what the capture of 0.9.52 stores.
return function(P)
  local check, eq, M, ns = P.check, P.eq, P.M, P.ns
  local UI = ns.UI
  local tip = _G.GameTooltip
  local function near(a, b) return a and b and math.abs(a - b) < 0.51 end
  local function right(b) return b.l + b.w end
  local function shown(rows) local out = {}; for _, r in ipairs(rows or {}) do if r.shown ~= false then out[#out + 1] = r end end return out end
  local function dataRows(tbl) local out = {}; for _, r in ipairs(shown(tbl.rows)) do if r.item and not r.item.ebSection then out[#out + 1] = r end end return out end
  local function keys(tbl) local t = {}; for _, col in ipairs(tbl.spec) do if tbl.cols[col.key] then t[#t + 1] = col.key end end; return table.concat(t, ",") end
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
        local hid = content.lootCols or {}
        eq(tag .. ": the columns of 4.1 (From and Place only while a third of the rows have a value)", keys(tbl),
          mode == "newest" and ("time,icon,item" .. (hid.from and "" or ",from") .. (hid.loc and "" or ",loc") .. ((wide and not hid.coords) and ",coords" or "")) or "icon,item,qty,last")
        check(tag .. ": no Value, Vendor price or Qty column", tbl.head.price == nil and tbl.head.times == nil and tbl.head.first == nil)
        -- the control row: segmented, quality filter, search 176, right to left, S2 apart, inside the window
        local seg, qf, se = P.box(content.lootModeControl), P.box(content.lootQuality), P.box(content.search)
        check(tag .. ": the control row: List · By item, the quality filter, search 176, S2 apart", content.lootModeControl.segs[1].text:GetText() == "List" and near(right(seg) + UI.S.S2, qf.l) and near(right(qf) + UI.S.S2, se.l)
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
        -- names in their quality colour; no cell is a dash
        local qbad = {}
        for i, r in ipairs(rows) do
          local q = (r.item.q or "ffffffff"):lower()
          local want = { tonumber(q:sub(3, 4), 16) / 255, tonumber(q:sub(5, 6), 16) / 255, tonumber(q:sub(7, 8), 16) / 255 }
          local got = r.c.item._color
          if q:len() == 8 and r.item.item and not (got and math.abs(got[1] - want[1]) < 0.01 and math.abs(got[2] - want[2]) < 0.01 and math.abs(got[3] - want[3]) < 0.01) and q ~= "ff9d9d9d" then qbad[#qbad + 1] = i end
          for k, cell in pairs(r.c) do if cell.GetText and cell:GetText() == "-" then qbad[#qbad + 1] = i .. " a dash in " .. k end end
          if r.c.from and (r.c.from:GetText() == "an enemy" or r.c.from:GetText() == "Creature" or r.c.from:GetText() == "Picked up" or r.c.from:GetText() == "Unknown source" or r.c.from:GetText() == "Other") then qbad[#qbad + 1] = i .. " a stored placeholder in From" end
        end
        check(tag .. ": names in their quality colour, no dash and no stored placeholder in any cell", #qbad == 0, table.concat(qbad, ","))
        if mode == "newest" then
          local secs = tbl.sections()
          check(tag .. ": newest first under day rows, a day row is the day only", #secs >= 1 and secs[1]:GetText():find("ITEM", 1, true) == nil and rows[1].item.t >= rows[#rows].item.t, secs[1] and secs[1]:GetText())
          local coin = 0
          for _, r in ipairs(rows) do if r.item.money then coin = coin + 1 end end
          eq(tag .. ": no coin row (#38: coin is the Gold pane's)", coin, 0)
          local notLoot = 0
          for _, r in ipairs(rows) do local src = r.item.src or ""; if r.item.mail or src:find("^Auction ") or src:find("^Mail") then notLoot = notLoot + 1 end end
          eq(tag .. ": no auction or mail row (Gold > Auction house owns them)", notLoot, 0)
        else
          local counts = true
          for _, r in ipairs(rows) do if tonumber((r.c.qty:GetText() or ""):gsub(",", ""), 10) ~= r.item.count or r.c.last:GetText() ~= UI.fmtDate(r.item.t) then counts = false end end
          check(tag .. ": Count is each item's quantity, Last looted its newest pickup", counts)
        end
        -- no line above the list: the section header opens the page, says where the list starts and how many rows it shows
        local first
        for _, e in ipairs(ns.mine(ns.DB.loot.log)) do
          local src = e.src or ""
          if e.item and not e.money and not e.mail and not src:find("^Auction ") and not src:find("^Mail") and (not first or e.t < first) then first = e.t end
        end
        local n = #rows
        check(tag .. ": no answer line; the section header is the first thing on the page", content.lootSummary == nil and math.abs(P.box(content.lootSection).t - P.box(tbl.frame).t + UI.H.SECTION) < 0.51)
        eq(tag .. ": the header says where the list starts", content.lootSection.label:GetText(), UI.upper("Items since " .. UI.fmtSince(first)))
        -- (a row of the list is a pickup, of one item or a stack; a row of By item is an item)
        eq(tag .. ": its meta counts the rows shown as what they are", content.lootSection.meta:GetText(), UI.plural(n, mode == "byitem" and "item" or "pickup"))
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
    eq("Items empty: the sentence of 4.1", tbl.stateFS:GetText(), "No item stored yet.")
    check("Items empty: the header claims no start and no count", content.lootSection.label:GetText() == "ITEMS" and not P.visible(content.lootSection.meta), content.lootSection.label:GetText())
    content.setLootQuality("all")
    eq("Items empty: at Everything", tbl.stateFS:GetText(), "No item stored yet.")
    for i, e in pairs(keep) do log[i] = e end
    content.setLootQuality("purple")
    if #dataRows(tbl) == 0 then eq("Items: a filter with no row says so, and never \"nothing yet\"", tbl.stateFS:GetText(), "No item matches this filter.") end
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
    for i = #log, 1, -1 do if not log[i].money and log[i].item and ns.isMine(log[i]) and ns._test.lootMatches(log[i], "") then mine = log[i]; break end end
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

  -- ── rows shaped like a real save's (the founder's of 21 Nov 2026): what From and Place say ──────────────────
  do
    local content = open(1250, 760, "normal", "newest", "all")
    local log = ns.DB.loot.log
    local keep = {}
    for i = #log, 1, -1 do keep[i] = log[i]; log[i] = nil end
    local sid, now = ns.DB.active, GetServerTime()
    local G, B, W = "ff1eff00", "ff0070dd", "ffffffff"
    local function add(dt, item, q, src, more)
      local e = { t = now - dt, item = item, count = 1, q = q, src = src, s = sid, id = 1000 + #log }
      for k, v in pairs(more or {}) do e[k] = v end
      log[#log + 1] = e
      return e
    end
    -- oldest first, as the log is written
    add(9000, "Thick Cloak", "ff9d9d9d", "Picked up", { zone = "Orgrimmar", x = 0.52, y = 0.64 })
    add(800, "Formula: Enchant Bracer", G, "Forgotten Soldier", { zone = "Mount Hyjal", x = 0.69, y = 0.69, guid = "Creature-0-1-1-1-9-00AA" })
    add(700, "Slashclaw Bracers", B, "Creature", { zone = "Blackrock Spire", x = 0.4, y = 0.5 })
    -- (a roll won after the loot window closed: stored with the place of the last loot window, another zone)
    add(600, "Hibernal Armor", G, "an enemy", { zone = "Orgrimmar", x = 0.5205, y = 0.6444 })
    add(500, "Lesser Moonstone", G, "Picked up", { zone = "Mount Hyjal", x = 0.69, y = 0.69 })
    add(450, "Star Ruby", G, "Picked up")
    add(400, "Lichbane", G, "Quest reward", { zone = "Mount Hyjal" })
    add(350, "Hakkari Breastplate", B, "Unknown source", { guid = "Item-6945-0-40000000736D45BB", zone = "Sunken Temple" })
    add(300, "Seapost Girdle", G, "Unknown source", { zone = "Blackrock Spire" })
    add(250, "Black Lotus", G, "Auction won", { count = 3, zone = "Thunder Bluff", mail = { bid = 281985, buyout = 3, seller = "Acornelius Thost" } })
    add(240, "Runecloth", W, "Mail from Undertaker Hart", { count = 20, zone = "Thunder Bluff", mail = { sender = "Undertaker Hart" } })
    add(230, "Iron Bar", W, "Auction returned", { count = 17, zone = "Orgrimmar" })
    -- rows of 0.9.52: stamped where they were picked up and marked
    add(200, "Weed Whacker", G, "Picked up", { zone = "Felwood", x = 0.3, y = 0.4, map = 77, pushed = true })
    add(150, "Plaguecrusher Greaves", G, "Quest reward", { zone = "Felwood", x = 0.31, y = 0.41, map = 77, pushed = true })
    add(100, "Linken's Sword", B, "Container", { zone = "Un'Goro Crater", x = 0.1, y = 0.2, map = 78, guid = "Item-6945-0-4000000012345678" })
    content.setLootQuality("green"); M.settle()
    local tbl = content.lootTables.newest
    local rows = dataRows(tbl)
    local got = {}
    for i, r in ipairs(rows) do got[i] = strip(r.c.item:GetText()) .. "|" .. r.c.from:GetText() .. "|" .. r.c.loc:GetText() end
    eq("Items real shapes: From and Place, newest first", table.concat(got, " ; "), table.concat({
      "Linken's Sword|Container|Un'Goro Crater",
      "Plaguecrusher Greaves|Quest|Felwood",
      "Weed Whacker||Felwood",
      "Seapost Girdle||Blackrock Spire",
      "Hakkari Breastplate|Container|Sunken Temple",
      "Lichbane|Quest|",
      "Star Ruby||",
      "Lesser Moonstone||",
      "Hibernal Armor||",
      "Slashclaw Bracers||Blackrock Spire",
      "Formula: Enchant Bracer|Forgotten Soldier|Mount Hyjal",
    }, " ; "))
    check("Items real shapes: an auction purchase, a mail and a returned auction are not listed", #rows == 11)
    eq("Items real shapes: the header starts at the oldest item kept, whatever the filter", content.lootSection.label:GetText(), UI.upper("Items since " .. UI.fmtSince(now - 9000)))
    eq("Items real shapes: the meta counts the pickups in the filter's words", content.lootSection.meta:GetText(), "11 pickups green or better")
    local function rowOf(name) for _, r in ipairs(dataRows(tbl)) do if strip(r.c.item:GetText()) == name then return r end end end
    local function tipOf(r) tip:ClearLines(); r.scripts.OnEnter(r); local t = table.concat(tip.lines or {}, "\n"); r.scripts.OnLeave(r); return t end
    check("Items real shapes: a hidden name is a blank cell that says Name not recorded on hover, never Enemy", rowOf("Hibernal Armor").c.from:GetText() == "" and tipOf(rowOf("Hibernal Armor")):find("From: Name not recorded", 1, true) ~= nil
      and tipOf(rowOf("Hibernal Armor")):find("Enemy", 1, true) == nil, tipOf(rowOf("Hibernal Armor")))
    check("Items real shapes: a blank From says Not recorded on hover", tipOf(rowOf("Star Ruby")):find("From: Not recorded", 1, true) ~= nil)
    check("Items real shapes: a place taken from an earlier loot window is not shown, on the row or in its hover", rowOf("Hibernal Armor").c.loc:GetText() == "" and tipOf(rowOf("Hibernal Armor")):find("Orgrimmar", 1, true) == nil
      and tipOf(rowOf("Hibernal Armor")):find("Place: Not recorded", 1, true) ~= nil)
    check("Items real shapes: a row of 0.9.52 that came with no loot window shows the place it was stamped with", rowOf("Weed Whacker").c.loc:GetText() == "Felwood" and tipOf(rowOf("Weed Whacker")):find("Place: Felwood", 1, true) ~= nil)
    check("Items real shapes: a named source says nothing more on hover", tipOf(rowOf("Formula: Enchant Bracer")):find("Not recorded", 1, true) == nil)
    eq("Items real shapes: the helpers the pane reads", table.concat({ tostring(ns._test.lootFrom({ src = "Creature" })), tostring(ns._test.lootFrom({ src = "Picked up" })), tostring(ns._test.lootFrom({ src = "Quest reward" })),
      tostring(ns._test.lootPlace({ src = "Quest reward", zone = "Durotar" })), tostring(ns._test.lootPlace({ src = "Quest reward", zone = "Durotar", pushed = true })), tostring(ns._test.lootPlace({ src = "Kobold", zone = "Durotar" })),
      tostring(ns._test.lootPlace({ src = "Kobold", zone = "Durotar", guid = "Creature-0-1-1-1-6-00AA" })), tostring(ns._test.lootFrom({ src = "Kobold" })), tostring(ns._test.lootFrom({ src = "Kobold", guid = "Creature-0-1-1-1-6-00AA" })) }, ","),
      "nil,nil,Quest,nil,Durotar,nil,Durotar,nil,Kobold")
    eq("Items real shapes: a source that repeats the item's name (a gathered node) is blank, with nothing to add on hover",
      table.concat({ tostring((ns._test.lootFrom({ item = "Hyjal Silphium", src = "Hyjal Silphium", guid = "GameObject-0-1-1-1-6-00AA" }))), tostring(select(2, ns._test.lootFrom({ item = "Hyjal Silphium", src = "Hyjal Silphium", guid = "GameObject-0-1-1-1-6-00AA" }))),
        tostring((ns._test.lootFrom({ item = "Iron Ore", src = "Iron Deposit", guid = "GameObject-0-1-1-1-6-00AB" }))) }, ","), "nil,nil,Iron Deposit")
    -- search reads what the row shows
    typeIn(content.search, "enemy")
    eq("Items real shapes: a search for Enemy finds nothing: no row says so", #dataRows(tbl), 0)
    typeIn(content.search, "orgrimmar")
    eq("Items real shapes: a place that is not shown is not found", #dataRows(tbl), 0)
    typeIn(content.search, "")
    -- columns: From and Place stay while a third of the rows have a value
    check("Items real shapes: From (7 of 11) and Place (7 of 11) show", content.lootCols.from == false and content.lootCols.loc == false)
    typeIn(content.search, "moonstone")
    check("Items real shapes: a list with no From and no Place value shows neither column", content.lootCols.from == true and content.lootCols.loc == true and tbl.cols.from == nil and tbl.cols.loc == nil and tbl.cols.item ~= nil)
    typeIn(content.search, "felwood")
    check("Items real shapes: Place the same on every row is left out", #dataRows(tbl) == 2 and content.lootCols.loc == true and content.lootCols.from == false)
    typeIn(content.search, "")
    check("Items real shapes: the columns come back with the rows", tbl.cols.from ~= nil and tbl.cols.loc ~= nil)
    -- By item on the same rows
    content.setLootMode("byitem"); M.settle()
    eq("Items real shapes: By item counts its own rows, items", content.lootSection.meta:GetText(), "11 items green or better")
    content.setLootMode("newest")
    -- the capture of 0.9.52: an item that reaches the bags with no loot window is stamped where the character stands
    local keepZone, keepMap = M.zone, M.uiMap
    M.zone, M.uiMap = "Elwynn Forest", 37
    M.units.target = { name = "Kobold Miner", hostile = true, dead = true, guid = "Creature-0-1-1-1-6-00AA" }
    M.fire("LOOT_OPENED"); M.units.target = nil
    M.now = M.now + 60
    M.zone, M.uiMap = "Westfall", 52
    local n0 = #log
    M.fire("CHAT_MSG_LOOT", "You receive loot: |cff1eff00|Hitem:9001::::::::12:::::|h[Rolled Ring]|h|r.")
    local e = log[#log]
    check("Items capture: a pushed row is stamped at the pickup, with its map, and marked", #log == n0 + 1 and e.item == "Rolled Ring" and e.zone == "Westfall" and e.pushed == true and (e.map == nil or e.map == 52), tostring(e.zone) .. " " .. tostring(e.map))
    check("Items capture: its source is never the on-screen placeholder", e.src ~= "an enemy", e.src)
    check("Items capture: a pushed row with no kill and no opened object behind it says nothing of how it was named", (e.src == "Picked up") == (e.srcBy == nil), tostring(e.src) .. " " .. tostring(e.srcBy))
    -- a kill, then a pushed item: the name is the last kill's, a guess by timing, and the row says so (srcBy)
    ns.Emitter.event("KILL", { name = "Pebbles" }, true)
    M.now = M.now + 2
    M.fire("CHAT_MSG_LOOT", "You receive loot: |cff1eff00|Hitem:9004::::::::12:::::|h[Head of Someone]|h|r.")
    e = log[#log]
    check("Items capture: an item pushed after a kill is marked as named by that kill", e.item == "Head of Someone" and e.src == "Pebbles" and e.pushed == true and e.srcBy == "kill", tostring(e.src) .. " " .. tostring(e.srcBy))
    eq("Items capture: the pane shows no name for it: blank, with Name not recorded", tostring((ns._test.lootFrom(e))) .. "|" .. tostring(select(2, ns._test.lootFrom(e))), "nil|Name not recorded")
    M.now = M.now + 30
    -- a kill whose name the client hid, then a pushed item: Creature, as a loot window stores it
    ns.Emitter.event("KILL", { name = "an enemy" }, true)
    M.now = M.now + 2
    M.fire("CHAT_MSG_LOOT", "You receive loot: |cff1eff00|Hitem:9002::::::::12:::::|h[Rolled Cloak]|h|r.")
    e = log[#log]
    check("Items capture: an item after a kill with a hidden name is stored as Creature, never as an enemy", e.item == "Rolled Cloak" and e.src == "Creature" and e.pushed == true, e.src)
    -- a loot window: the row names the window's mob, is stamped when the item arrives and is not marked
    M.units.target = { name = "Defias Thug", hostile = true, dead = true, guid = "Creature-0-1-1-1-7-00AB" }
    M.zone, M.uiMap = "Duskwood", 47
    M.fire("LOOT_OPENED"); M.units.target = nil
    M.zone, M.uiMap = "Westfall", 52
    M.fire("CHAT_MSG_LOOT", "You receive loot: |cff1eff00|Hitem:9003::::::::12:::::|h[Looted Belt]|h|r.")
    e = log[#log]
    check("Items capture: a row from a loot window names the mob, is stamped where the item arrived and has no mark", e.item == "Looted Belt" and e.src == "Defias Thug" and e.zone == "Westfall" and e.pushed == nil and e.srcBy == nil
      and e.guid == "Creature-0-1-1-1-7-00AB", tostring(e.src) .. " " .. tostring(e.zone) .. " " .. tostring(e.pushed))
    eq("Items capture: the pane shows the loot window's name", tostring((ns._test.lootFrom(e))), "Defias Thug")
    M.now = M.now + 30
    M.zone, M.uiMap = keepZone, keepMap
    for i = #log, 1, -1 do log[i] = nil end
    for i, x in pairs(keep) do log[i] = x end
    content.setLootQuality("green")
  end

  -- ── review round 1 (docs/UX_PRAGMATIC.md 0.2.1): a place, a name or a quest is shown only when the stored rows
  --    prove it. Rows written before 0.9.52 (no `map`, no `pushed`), shaped like the founder's of 20 Nov 2026. ──
  do
    local content = open(1600, 1000, "normal", "newest", "all")
    local log = ns.DB.loot.log
    local keep = {}
    for i = #log, 1, -1 do keep[i] = log[i]; log[i] = nil end
    local sid, now = ns.DB.active, GetServerTime()
    local sess = ns.DB.sessions[sid]
    local nSeg, events = #sess.segments, ns.DB.story.events
    local nEv = #events
    local c0 = ns.char()
    local keepRuns = c0.goldRuns
    local Gq, W = "ff1eff00", "ffffffff"
    local function add(dt, item, src, more)
      local e = { t = now - dt, item = item, count = 1, q = Gq, src = src, s = sid, id = 2000 + #log }
      for k, v in pairs(more or {}) do e[k] = v end
      log[#log + 1] = e
      return e
    end
    local function kill(dt, name) sess.segments[#sess.segments + 1] = ("%d\t%d\t%.3f\tKILL\t%s"):format(#sess.segments + 1, now - dt, 1, name) end
    local function coin(dt, x, y) log[#log + 1] = { t = now - dt, money = 120, src = "Creature", s = sid, zone = "Mount Hyjal", x = x, y = y } end
    local STALE = { zone = "Mount Hyjal", x = 0.6903, y = 0.6981 }
    -- a loot window at -2000 s: a herb, stamped 69.0, 69.8. Every later pushed item reuses that stamp for 33 minutes.
    add(2000, "Hyjal Herb", "Herb node", STALE)
    add(1995, "Hyjal Herb Seed", "Herb node", STALE)
    kill(1500, "Forgotten Soldier"); coin(1498, 0.2225, 0.5418)
    add(1499, "Formula: Enchant Bracer", "Forgotten Soldier", STALE)
    add(1300, "Bear Berries", "Bear Berries", { zone = "Mount Hyjal", x = 0.6903, y = 0.6981, q = W })   -- (an opened world object: no kill of that name)
    kill(1105, "Jammal'an the Prophet"); kill(1101, "Pebbles")
    add(1100, "Head of Jammal'an", "Pebbles", { zone = "The Temple of Atal'Hakkar", q = W })
    kill(1000, "Healing Ward")
    add(990, "Deadwood Tribal Beads", "Healing Ward", STALE)
    -- a mob looted through its loot window: the row carries the loot GUID and a fresh stamp
    add(900, "Battlefield Destroyer", "Vilebranch Warrior", { zone = "The Hinterlands", x = 0.678, y = 0.638, guid = "Creature-0-1-1-1-2649-00AA" })
    -- a name with a kill of another name 5 s before it, and a kill of its own name 25 s before: neither names it
    kill(825, "Vilebranch Scalper"); kill(805, "Someone Else")
    add(800, "Scalper Loot", "Vilebranch Scalper", { zone = "The Hinterlands", x = 0.5, y = 0.5 })
    -- two quests turned in 1 s apart, a reward of each; then one quest alone
    local function done(dt, name) events[#events + 1] = { kind = "QUESTDONE", s = sid, t = now - dt, text = "Complete: " .. name } end
    done(700, "Final Death"); done(699, "Blight No More")
    add(700, "Lichbane", "Quest reward", { zone = "Mount Hyjal" })
    add(699, "Plaguecrusher Greaves", "Quest reward", { zone = "Mount Hyjal" })
    done(600, "A Rest Without Pain")
    add(600, "Manual: Major Healing Potion", "Quest reward", { zone = "Mount Hyjal" })
    -- a row of a session whose record is gone cannot be judged: no name
    log[#log + 1] = { t = now - 500, item = "Orphan Blade", count = 1, q = Gq, src = "Some Mob", s = sid, zone = "Tanaris", x = 0.3, y = 0.3 }
    content.setLootQuality("all"); M.settle()
    local tbl = content.lootTables.newest
    local F, Pl, XY = ns._test.lootFrom, ns._test.lootPlace, ns._test.lootCoords
    local function row(name) for _, e in ipairs(log) do if e.item == name then return e end end end
    local function says(name) local e = row(name); local f, why = F(e); return tostring(f) .. "/" .. tostring(why) .. "/" .. tostring(Pl(e)) .. "/" .. tostring(XY(e)) end
    eq("Items truth: the loot window's own rows keep their place and coordinates", says("Hyjal Herb") .. " ; " .. says("Hyjal Herb Seed"), "Herb node/nil/Mount Hyjal/69.0, 69.8 ; Herb node/nil/Mount Hyjal/69.0, 69.8")
    eq("Items truth: a row named by the last kill shows no source, and neither the stale place nor its coordinates", says("Formula: Enchant Bracer"), "nil/Name not recorded/nil/nil")
    eq("Items truth: a party member's name is never the source", says("Head of Jammal'an"), "nil/Name not recorded/nil/nil")
    eq("Items truth: nor a totem's", says("Deadwood Tribal Beads"), "nil/Name not recorded/nil/nil")
    eq("Items truth: an opened world object that has the item's own name says nothing twice; its stamp is still the old loot window's, so no place", says("Bear Berries"), "nil/nil/nil/nil")
    eq("Items truth: a name with the loot window's GUID is shown, with its place", says("Battlefield Destroyer"), "Vilebranch Warrior/nil/The Hinterlands/67.8, 63.8")
    eq("Items truth: a name with no kill of that name in the 20 s before it is not a kill guess (the capture counts 15 s): it stays, with no place", says("Scalper Loot"), "Vilebranch Scalper/nil/nil/nil")
    eq("Items truth: two turn-ins within 5 s: neither reward names a quest", says("Lichbane") .. " ; " .. says("Plaguecrusher Greaves"), "Quest/Quest not recorded/nil/nil ; Quest/Quest not recorded/nil/nil")
    eq("Items truth: one turn-in within 5 s names the quest", says("Manual: Major Healing Potion"), "Quest: A Rest Without Pain/nil/nil/nil")
    -- no two shown rows more than 15 s apart share an exact stamp without a loot window of their own
    do
      local seen, far, bare = {}, 0, 0
      for _, r in ipairs(dataRows(tbl)) do
        local e = r.item
        if XY(e) and not Pl(e) then bare = bare + 1 end
        if XY(e) and e.x then
          local k = e.zone .. "|" .. e.x .. "|" .. e.y
          if seen[k] and math.abs(seen[k] - e.t) > 15 and not e.guid then far = far + 1 end
          seen[k] = seen[k] or e.t
        end
      end
      eq("Items truth: no stamp is shown on two rows more than 15 s apart", far, 0)
      eq("Items truth: no coordinates without a place", bare, 0)
    end
    -- the columns: 3 of 12 rows have a place, under a third: no Place column and so no Coords column, even at 1600 px
    check("Items truth: Coords is never shown without Place", content.lootCols.loc == true and content.lootCols.coords == true and tbl.cols.loc == nil and tbl.cols.coords == nil, tostring(content.lootCols.loc) .. " " .. tostring(content.lootCols.coords))
    typeIn(content.search, "hyjal herb")
    check("Items truth: one place on every row shown: no Place column, and no Coords column either", #dataRows(tbl) == 2 and tbl.cols.loc == nil and tbl.cols.coords == nil, #dataRows(tbl))
    typeIn(content.search, "")
    local function tipOf(r) tip:ClearLines(); r.scripts.OnEnter(r); local t = table.concat(tip.lines or {}, "\n"); r.scripts.OnLeave(r); return t end
    local function rowOf(name) for _, r in ipairs(dataRows(tbl)) do if strip(r.c.item:GetText()) == name then return r end end end
    check("Items truth: the place and coordinates of a row stay in its hover when the columns are left out", tipOf(rowOf("Battlefield Destroyer")):find("Place: The Hinterlands  67.8, 63.8", 1, true) ~= nil, tipOf(rowOf("Battlefield Destroyer")))
    check("Items truth: a reward with two candidate quests says so on hover", tipOf(rowOf("Lichbane")):find("Quest not recorded", 1, true) ~= nil and tipOf(rowOf("Lichbane")):find("Final Death", 1, true) == nil)
    -- a row whose session record is gone: nothing can be said about its name
    do
      local e = row("Orphan Blade")
      e.s = "t-items-gone"
      eq("Items truth: a name whose session record is gone is not shown", tostring((F(e))) .. "/" .. tostring(select(2, F(e))), "nil/Not recorded")
      e.s = sid
    end
    -- the header: a pickup is a row, and the list says when it is not complete
    row("Bear Berries").count = 7
    c0.goldRuns = nil
    content.setLootQuality("green"); content.setLootQuality("all"); M.settle()
    eq("Items truth: the header counts pickups, not items (12 rows hold 18 units)", content.lootSection.meta:GetText(), "12 pickups")
    c0.goldRuns = { { inst = "Maraudon", t = now - 3000, secs = 600, items = 36 } }
    content.setLootQuality("green"); content.setLootQuality("all"); M.settle()
    eq("Items truth: a run from before the list's start says nothing about the list", content.lootSection.meta:GetText(), "12 pickups")
    c0.goldRuns = { { inst = "Maraudon", t = now - 1600, secs = 400, items = 36 } }
    content.setLootQuality("green"); content.setLootQuality("all"); M.settle()
    eq("Items truth: a run inside the span that counted 36 items where the list holds 2: the header says so", content.lootSection.meta:GetText(), "12 pickups, not every item is kept")
    check("Items truth: the reason is on the remark's hover, never on the screen", content.lootSection.metaHit and content.lootSection.metaHit.shown ~= false and type(content.lootSection.metaHit.ebTip) == "table"
      and content.lootSection.metaHit.ebTip.text:find("desktop app", 1, true) ~= nil)
    c0.goldRuns = { { inst = "Maraudon", t = now - 1600, secs = 400, items = 2 } }
    content.setLootQuality("green"); content.setLootQuality("all"); M.settle()
    eq("Items truth: a run whose 2 items are both in the list leaves no remark", content.lootSection.meta:GetText(), "12 pickups")
    -- review round 2: a run's `secs` are active seconds (time away is not counted), not a clock. A run with a long
    -- break whose rows are all still stored makes no remark, however far after start + secs its last pickup is
    -- (the founder's Blackrock Depths of 19 Nov: secs 9,220, last pickup 9,534 s in).
    do
      local times = {}
      for _, e in ipairs(log) do if e.item and not e.money and e.t >= now - 1600 then times[#times + 1] = e.t end end
      table.sort(times)
      c0.goldRuns = { { inst = "Maraudon", t = now - 1600, secs = 30, items = #times } }
      content.setLootQuality("green"); content.setLootQuality("all"); M.settle()
      check("Items truth: the fixture has rows well after the run's active seconds", #times >= 3 and times[#times] > now - 1600 + 30 + 60, #times)
      eq("Items truth: a run with a break in it (active seconds far below its span) whose rows are all stored leaves no remark", content.lootSection.meta:GetText(), "12 pickups")
      -- the next run bounds the span: rows from its start on are not the first run's, so the first run misses one
      c0.goldRuns = { { inst = "Maraudon", t = now - 1600, secs = 30, items = #times }, { inst = "Maraudon", t = times[#times], secs = 5, items = 1 } }
      content.setLootQuality("green"); content.setLootQuality("all"); M.settle()
      eq("Items truth: a run that counted more items than the rows kept up to the next run's start still says so", content.lootSection.meta:GetText(), "12 pickups, not every item is kept")
      c0.goldRuns = { { inst = "Maraudon", t = now - 1600, secs = 30, items = #times - 1 }, { inst = "Maraudon", t = times[#times], secs = 5, items = 1 } }
      content.setLootQuality("green"); content.setLootQuality("all"); M.settle()
      eq("Items truth: two runs, each with its rows, leave no remark", content.lootSection.meta:GetText(), "12 pickups")
      -- the open run bounds it too
      c0.goldRuns = { { inst = "Maraudon", t = now - 1600, secs = 30, items = #times } }
      local keepOpen = c0.goldRun
      c0.goldRun = { inst = "Maraudon", t = times[#times], secs = 0, items = 1 }
      content.setLootQuality("green"); content.setLootQuality("all"); M.settle()
      eq("Items truth: the open run's start ends the span of the run before it", content.lootSection.meta:GetText(), "12 pickups, not every item is kept")
      c0.goldRun = keepOpen
    end
    content.setLootMode("byitem"); M.settle()
    eq("Items truth: By item counts items", content.lootSection.meta:GetText(), "12 items")
    content.setLootMode("newest"); M.settle()
    c0.goldRuns = keepRuns
    for i = #sess.segments, nSeg + 1, -1 do sess.segments[i] = nil end
    for i = #events, nEv + 1, -1 do events[i] = nil end
    for i = #log, 1, -1 do log[i] = nil end
    for i, x in pairs(keep) do log[i] = x end
    content.setLootQuality("green")
  end

  -- ── review round 2: the pickups of one item in one minute are one row (display only), shaped like the founder's
  --    20 Nov 23:33 (Iron Ore, a Lesser Moonstone between) and 22:43 to 22:44 (Hyjal Silphium from its own node) ──
  do
    local content = open(1104, 697, "normal", "newest", "all")
    local log = ns.DB.loot.log
    local keep = {}
    for i = #log, 1, -1 do keep[i] = log[i]; log[i] = nil end
    local sid, now = ns.DB.active, GetServerTime()
    local c0 = ns.char()
    local keepRuns = c0.goldRuns
    c0.goldRuns = nil
    local m = math.floor((now - 600) / 60) * 60   -- the start of a minute, ten minutes ago
    local W = "ffffffff"
    local function add(t, item, id, count, src, more)
      local e = { t = t, item = item, id = id, count = count, q = W, src = src, s = sid }
      for k, v in pairs(more or {}) do e[k] = v end
      log[#log + 1] = e
      return e
    end
    local node = "GameObject-0-1-1-1-6-00AA"
    add(m - 62, "Hyjal Silphium", 501, 2, "Hyjal Silphium", { guid = node })
    add(m - 61, "Hyjal Silphium", 501, 2, "Hyjal Silphium", { guid = node })
    add(m + 12, "Hyjal Silphium", 501, 3, "Hyjal Silphium", { guid = node })
    add(m + 13, "Hyjal Silphium", 501, 3, "Hyjal Silphium", { guid = node })
    add(m + 14, "Hyjal Silphium", 501, 2, "Hyjal Silphium", { guid = node })
    add(m + 122, "Iron Ore", 502, 1, "Iron Deposit", { guid = "GameObject-0-1-1-1-6-00AB" })
    add(m + 123, "Lesser Moonstone", 503, 1, "Iron Deposit", { guid = "GameObject-0-1-1-1-6-00AB" })
    add(m + 127, "Iron Ore", 502, 1, "Iron Deposit", { guid = "GameObject-0-1-1-1-6-00AB" })
    add(m + 128, "Iron Ore", 502, 1, "Iron Deposit", { guid = "GameObject-0-1-1-1-6-00AB" })
    -- the same item in the same minute from another source is another row
    add(m + 130, "Iron Ore", 502, 4, "Quest reward")
    local stored = #log
    content.setLootQuality("green"); content.setLootQuality("all"); M.settle()
    local tbl = content.lootTables.newest
    local got = {}
    for _, r in ipairs(dataRows(tbl)) do
      got[#got + 1] = r.c.time:GetText() .. " " .. strip(r.c.item:GetText()) .. ((r.ebCount and r.ebCount:IsShown()) and (" " .. r.ebCount:GetText()) or "") .. "|" .. (r.c.from and r.c.from:GetText() or "(no From)")
    end
    local c1, c2, c3 = UI.fmtClock(m + 120), UI.fmtClock(m), UI.fmtClock(m - 62)
    eq("Items merge: one row per item, source and minute, with the summed count, newest first", table.concat(got, " ; "), table.concat({
      c1 .. " Iron Ore x4|Quest", c1 .. " Iron Ore x3|Iron Deposit", c1 .. " Lesser Moonstone|Iron Deposit", c2 .. " Hyjal Silphium x8|", c3 .. " Hyjal Silphium x4|" }, " ; "))
    eq("Items merge: the header counts the pickups, not the rows", content.lootSection.meta:GetText(), "10 pickups")
    eq("Items merge: the stored rows stay as written", #log .. " " .. log[6].count .. " " .. log[3].count, stored .. " 1 3")
    local function rowOf(name, clock) for _, r in ipairs(dataRows(tbl)) do if strip(r.c.item:GetText()) == name and r.c.time:GetText() == clock and r.item.ebMerged then return r end end end
    local function tipOf(r) tip:ClearLines(); r.scripts.OnEnter(r); local t = table.concat(tip.lines or {}, "\n"); r.scripts.OnLeave(r); return t end
    check("Items merge: the hover says how many pickups the row holds", tipOf(rowOf("Iron Ore", c1)):find("3 pickups in this minute, 3 in all", 1, true) ~= nil and tipOf(rowOf("Hyjal Silphium", c2)):find("3 pickups in this minute, 8 in all", 1, true) ~= nil,
      tipOf(rowOf("Iron Ore", c1)))
    check("Items merge: a source that only repeats the item's name is a blank cell", rowOf("Hyjal Silphium", c2).c.from:GetText() == "")
    content.setLootMode("byitem"); M.settle()
    local by = {}
    for _, r in ipairs(dataRows(content.lootTables.byitem)) do by[strip(r.c.item:GetText())] = r.c.qty:GetText() end
    eq("Items merge: By item still counts every unit", tostring(by["Iron Ore"]) .. " " .. tostring(by["Hyjal Silphium"]) .. " " .. tostring(by["Lesser Moonstone"]), "7 12 1")
    content.setLootMode("newest"); M.settle()
    c0.goldRuns = keepRuns
    for i = #log, 1, -1 do log[i] = nil end
    for i, x in pairs(keep) do log[i] = x end
    content.setLootQuality("green")
  end
end
