-- Pane tests: Character / Crafting (Everbuff/Market.lua), a row of summary chips over a UI.Table, and the auction
-- rows Market builds for Loot > Gold, Auction house (tests/panes/gold.lua tests that breakdown's page). At 900x580 and 1600x1000 on normal and long data: the rows span the list and it scrolls over all of them,
-- header x == cell x, numbers, money, coords and tags right where they belong and never shortened, the last column
-- inside the list, the chips inside the pane and clear of each other, the table below the chips, the chips carrying
-- the same labels and numbers the summary line did, hover and tooltips, and the empty state.
return function(P)
  local check, eq, M, ns = P.check, P.eq, P.M, P.ns
  local UI, Market = ns.UI, ns.Market
  local function near(a, b) return a and b and math.abs(a - b) < 0.51 end
  local NB = UI.NBSP

  local PANES = {
    { host = "character", pane = "crafting", which = 2, name = "Crafting",
      fixed = { "when", "what", "count", "coords" }, right = { count = true, coords = true }, last = "coords",
      build = function() return Market.buildCrafts() end,
      chips = function(sum)
        local out = { { "CRAFTS", tostring(sum.crafts) }, { "RECIPES LEARNED", tostring(sum.recipes) } }
        local profs = {}
        for p in pairs(sum.byProf) do profs[#profs + 1] = p end
        table.sort(profs)
        for _, p in ipairs(profs) do out[#out + 1] = { p:upper(), tostring(sum.byProf[p]) } end
        return out
      end },
  }
  local function L(which) local a, c = Market._panes(); return which == 1 and a or c end

  for _, pd in ipairs(PANES) do
    for _, size in ipairs({ { 900, 580 }, { 1600, 1000 } }) do
      for _, data in ipairs({ "normal", "long" }) do
        local tag = ("%s %dx%d %s"):format(pd.name, size[1], size[2], data)
        local content = P.open(pd.host, pd.pane, size[1], size[2], data)
        local pl = L(pd.which)
        check(tag .. ": the pane opened", content ~= nil and pl ~= nil)
        if pl then
          local tbl, rows, sum = pl.tbl, pd.build()
          check(tag .. ": the data has rows", #rows >= 2, #rows)
          -- the rows: one per data row, as they come, across the list, and the list scrolls over all of them
          local sfb = P.box(tbl.sf)
          local narrow, wrong = {}, {}
          for i = 1, #rows do
            local row = tbl.rows[i]
            local b = row and P.box(row)
            if not (b and near(b.w, math.floor(sfb.w)) and P.visible(row)) then narrow[#narrow + 1] = i .. ":" .. tostring(b and b.w) end
            if not (row and row.c.item.text == (rows[i].item or "")) then wrong[#wrong + 1] = i end
          end
          check(tag .. ": every row spans the list", #narrow == 0, table.concat(narrow, ","))
          check(tag .. ": the rows are the data's rows in its order", #wrong == 0, table.concat(wrong, ","))
          eq(tag .. ": the list is as tall as its rows, so it scrolls to the last", tbl.child._h, #rows * UI.ROW_H)
          check(tag .. ": the list's child is as wide as the list", near(tbl.child._w, math.floor(sfb.w)), tbl.child._w)
          -- header x == cell x, numbers right-aligned (header too), fixed cells read in full
          local off, cut, just = {}, {}, {}
          for _, col in ipairs(tbl.spec) do
            local hx = P.box(tbl.head[col.key].fs).l
            for i = 1, #rows do if not near(hx, P.box(tbl.rows[i].c[col.key]).l) then off[#off + 1] = col.key .. i; break end end
            local want = pd.right[col.key] and "RIGHT" or "LEFT"
            if tbl.rows[1].c[col.key]._justify ~= want or tbl.head[col.key].fs._justify ~= want then just[#just + 1] = col.key end
          end
          for _, k in ipairs(pd.fixed) do
            for i = 1, #rows do if tbl.rows[i].c[k]:IsTruncated() then cut[#cut + 1] = k .. i end end
          end
          check(tag .. ": header x == cell x in every column", #off == 0, table.concat(off, ","))
          check(tag .. ": numbers and their headers right-aligned, text left", #just == 0, table.concat(just, ","))
          check(tag .. ": times, kinds, quantities, prices and coords are never shortened", #cut == 0, table.concat(cut, ","))
          local lc = tbl.cols[pd.last]
          check(tag .. ": the last column ends inside the list", lc.x + lc.w <= sfb.w + 0.5, ("%d > %d"):format(lc.x + lc.w, sfb.w))
          check(tag .. ": the list ends inside the pane", sfb.l + sfb.w + UI.SCROLLBAR <= P.box(content).l + P.box(content).w + 0.5)
          -- the chips: same labels and numbers as the summary line, inside the pane, clear of each other, one line each
          local want = pd.chips(sum)
          local box = P.box(pl.chips.box)
          local bad, seen = {}, {}
          for i, w in ipairs(want) do
            local ch = pl.chips.chips[i]
            if not ch then bad[#bad + 1] = "missing " .. w[1]
            else
              if ch.label.text ~= w[1] or ch.value.text ~= w[2] then bad[#bad + 1] = ("%s=%s"):format(tostring(ch.label.text), tostring(ch.value.text)) end
              if ch.value:IsTruncated() or ch.label:IsTruncated() then bad[#bad + 1] = "shortened " .. w[1] end
              for _, fs in ipairs({ ch.label, ch.value }) do
                local b = P.box(fs)
                if not b or b.l + P.G.naturalWidth(fs) > box.l + box.w + 0.5 then bad[#bad + 1] = "past the pane " .. w[1] end
                if b then
                  for _, o in ipairs(seen) do
                    if b.l < o.l + o.w and o.l < b.l + b.w and b.t < o.t + o.h and o.t < b.t + b.h then bad[#bad + 1] = "overlap " .. w[1] end
                  end
                  seen[#seen + 1] = b
                end
              end
            end
          end
          check(tag .. ": the chips carry the summary's labels and numbers, in full, inside the pane, apart", #bad == 0, table.concat(bad, "; "))
          local fx = P.box(tbl.rows[1].c.when).l
          check(tag .. ": the chips start where the first column's text does", near(P.box(pl.chips.chips[1].label).l, fx), ("%s vs %s"):format(P.box(pl.chips.chips[1].label).l, fx))
          local hb = P.box(tbl.header)
          check(tag .. ": the table's header starts below the chips", hb.t >= box.t + box.h + UI.SP.M - 0.5, ("%d vs %d"):format(hb.t, box.t + box.h))
          local low = 0
          for _, s in ipairs(seen) do low = math.max(low, s.t + s.h) end
          check(tag .. ": the chips box holds its chips", low <= box.t + box.h + 0.5, ("%d > %d"):format(low, box.t + box.h))
          check(tag .. ": the header has one rule under it and shows", tbl.header.shown ~= false and tbl.rule._h == 1)
        end
      end
    end
  end

  -- the auction rows: newest first, each with its session id (Loot > Gold lists a period's), Posted with its hours
  do
    P.open("loot", "gold", 900, 580, "long")
    local rows, sum = Market.buildAuctions()
    local sorted, sess, kinds = true, true, {}
    for i, r in ipairs(rows) do
      if i > 1 and (r.t or 0) > (rows[i - 1].t or 0) then sorted = false end
      if r.s == nil then sess = false end
      kinds[r.what] = true
    end
    check("Auctions: the rows are newest first and carry their session id", #rows >= 2 and sorted and sess, #rows)
    check("Auctions: posted, sold and bought rows are built", kinds.Posted and kinds.Sold and kinds.Bought)
    check("Auctions: the sums add up the sold and bought rows", sum.sold >= 1 and sum.net > 0 and sum.bought >= 1)
    local loot
    for _, tab in ipairs(P.T.tabs) do if tab.name == "Loot" then loot = tab end end
    check("Auctions: Loot has no Auctions pane of its own any more (it is Gold's Auction house)", loot and loot.paneByKey.auctions == nil and loot.paneByKey.gold ~= nil and select(1, Market._panes()) == nil)
  end

  -- coordinates are their own right-aligned column, formatted as everywhere else
  do
    P.open("character", "crafting", 900, 580, "normal")
    local cl = L(2)
    local rows = Market.buildCrafts()
    local ok = true
    for i, r in ipairs(rows) do if cl.tbl.rows[i].c.coords.text ~= UI.fmtCoords(r.x, r.y) then ok = false end end
    check("Crafting: coords read as UI.fmtCoords", ok)
    check("Crafting: Profession, Location and Coords are separate columns", cl.tbl.cols.prof and cl.tbl.cols.zone and cl.tbl.cols.coords
      and cl.tbl.cols.prof.x < cl.tbl.cols.zone.x and cl.tbl.cols.zone.x < cl.tbl.cols.coords.x)
  end

  -- many professions: the chips wrap onto a second line and the table moves down with them
  do
    P.open("character", "crafting", 1600, 1000, "normal")
    local cl = L(2)
    check("Crafting: a short summary is one line of chips", P.box(cl.chips.box).h == 32, P.box(cl.chips.box).h)
    P.open("character", "crafting", 900, 580, "long")
    local hb1 = P.box(cl.tbl.header).t
    local c = ns.char()
    for _, p in ipairs({ "Alchemy", "Blacksmithing", "Enchanting", "Engineering", "Leatherworking", "Cooking" }) do
      c.crafts[#c.crafts + 1] = { s = "x", t = 1, item = "Thing", count = 1, prof = p .. " of the Scarlet Monastery Cathedral" }
    end
    ns.UI.Open("Character", "crafting"); M.settle()
    local box = P.box(cl.chips.box)
    check("Crafting many professions 900: the chips wrap onto more lines", box.h > 32 and (box.h - 32) % 40 == 0, box.h)
    local hb2 = P.box(cl.tbl.header).t
    check("Crafting many professions 900: the table moves down with the chips", hb2 >= box.t + box.h + UI.SP.M - 0.5 and hb2 > hb1, ("%d / %d"):format(hb2, hb1))
    local past = {}
    for _, ch in ipairs(cl.chips.chips) do
      if ch.value.shown ~= false then
        local b = P.box(ch.label)
        if b.l + b.w > box.l + box.w + 0.5 or ch.label:IsTruncated() then past[#past + 1] = ch.label.text end
      end
    end
    check("Crafting many professions 900: every chip inside the pane, in full", #past == 0, table.concat(past, "; "))
    P.open("character", "crafting", 900, 580, "normal")
  end

  -- the empty state: centred text, no header, the chips still read 0
  do
    P.open("character", "crafting", 900, 580, "normal")
    ns.DB.characters = ns.DB.characters or {}
    local c = ns.char()
    c.crafts, c.recipes = {}, {}
    ns.UI.Open("Character", "crafting"); M.settle()
    local cl = L(2)
    check("Crafting empty: the empty text shows, the header hidden", cl.tbl.empty.shown and cl.tbl.empty.text:find("No crafts yet", 1, true) and cl.tbl.header.shown == false)
    check("Crafting empty: only the two count chips show", cl.chips.chips[3] == nil or cl.chips.chips[3].value.shown == false)
  end
  check("Market: no error while sizing or rendering", (function() for _, e in ipairs(M.errors) do if tostring(e):find("Market") then return false, e end end return true end)())
  P.open("character", "crafting", 900, 580, "normal")
end
