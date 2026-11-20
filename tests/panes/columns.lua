-- Pane tests: the column model's choices on the busiest lists. Fights: Faced and Location share the spare width, so
-- a realistic zone name is never cut and neither column hoards empty space. Timeline: an event summary carries
-- counts, and with the suite's data it is never the text the ellipsis takes at the minimum window; the foe and the
-- place share what is left equally, and from 1250 wide a realistic foe name is never cut.
return function(P)
  local check, ns = P.check, P.ns
  local UI = ns.UI
  local function tableOf(content)
    for _, f in ipairs(P.descendants(content)) do if rawget(f, "SetContentHeight") and f.ebTable and P.visible(f) then return f.ebTable end end
  end
  local function rowsOf(t)
    local out = {}
    for i = 1, t.shownN do local r = t.rows[i]; if r.shown ~= false and not (r.item and r.item.ebSection) then out[#out + 1] = r end end
    return out
  end
  -- the flex minimum: a column is never narrower than its measured values while the row has room
  do
    local cols = UI.LayoutColumns({
      { key = "a", flex = 3, min = 40 }, { key = "b", flex = 1, min = 40, headMin = 150 }, { key = "c", flex = 1, min = 40 },
    }, 400, function() return 0 end, 12, 8)
    check("LayoutColumns: a flex column under its minimum is held at it, the rest share what is left",
      cols.b.w == 150 and cols.a.w + cols.b.w + cols.c.w == 400 - 16 - 24 and cols.a.w > cols.c.w, ("%d %d %d"):format(cols.a.w, cols.b.w, cols.c.w))
    -- #49: fixed columns that grew with their values leave less than the flex minimums: the flex columns give way,
    -- the row ends at the inset, and none goes under the floor
    local spec = { { key = "name", flex = 3, min = 150 }, { key = "realm", flex = 2, min = 80 }, { key = "bal" }, { key = "seen" } }
    local function fixed(w) return function() return w end end
    local function right(c) return c.seen.x + c.seen.w + 8 end
    local roomy, tight, none = UI.LayoutColumns(spec, 700, fixed(100), 12, 8), UI.LayoutColumns(spec, 700, fixed(250), 12, 8), UI.LayoutColumns(spec, 700, fixed(320), 12, 8)
    check("LayoutColumns: with room every flex column keeps its minimum and the row ends at the inset", roomy.name.w >= 150 and roomy.realm.w >= 80 and right(roomy) == 700, ("%d %d %d"):format(roomy.name.w, roomy.realm.w, right(roomy)))
    check("LayoutColumns: without room the flex columns shrink under their minimums and the row still ends at the inset",
      right(tight) == 700 and tight.name.w < 150 and tight.realm.w < 80 and tight.name.w >= UI.COL_FLOOR and tight.realm.w >= UI.COL_FLOOR and tight.bal.w == 250 and tight.seen.w == 250,
      ("%d %d %d"):format(tight.name.w, tight.realm.w, right(tight)))
    check("LayoutColumns: no flex column goes under the floor, however little room there is", none.name.w == UI.COL_FLOOR and none.realm.w == UI.COL_FLOOR and none.bal.w == 320, ("%d %d"):format(none.name.w, none.realm.w))
    spec[1].headMin = 90
    local head = UI.LayoutColumns(spec, 700, fixed(320), 12, 8)
    check("LayoutColumns: nor under its header label and measured values", head.name.w == 90 and head.realm.w == UI.COL_FLOOR, ("%d %d"):format(head.name.w, head.realm.w))
  end
  for _, size in ipairs({ { 900, 580 }, { 1250, 760 }, { 1600, 1000 } }) do
    local tag = ("%dx%d"):format(size[1], size[2])
    local c = P.open("combat", "fights", size[1], size[2], "normal")
    local t = c and tableOf(c)
    check("Fights " .. tag .. ": the list was found", t ~= nil)
    if t then
      local cut = {}
      for _, r in ipairs(rowsOf(t)) do if r.c.loc:IsTruncated() then cut[#cut + 1] = r.c.loc.text end end
      check("Fights " .. tag .. ": no zone name is cut", #cut == 0, table.concat(cut, ", "))
      check("Fights " .. tag .. ": Faced and Location share the spare width equally", math.abs(t.cols.foe.w - t.cols.loc.w) <= 1, ("%d vs %d"):format(t.cols.foe.w, t.cols.loc.w))
    end
    local h = P.open("home", "timeline", size[1], size[2], "normal")
    local tt = h and tableOf(h)
    check("Timeline " .. tag .. ": the list was found", tt ~= nil)
    if tt then
      local cut = {}
      for _, r in ipairs(rowsOf(tt)) do
        if r.c.ev:IsTruncated() and tostring(r.c.ev.text):find("%d") then cut[#cut + 1] = r.c.ev.text end
      end
      check("Timeline " .. tag .. ": an event summary with counts is never cut", #cut == 0, table.concat(cut, " | "))
      -- past the summary's minimum, the foe and the place share the width equally; from 1250 wide a realistic foe
      -- name is never cut. At 900 the summary is held at its minimum and the names take everything else.
      if size[1] >= 1250 then
        check("Timeline " .. tag .. ": While fighting and Location share the spare width equally", math.abs(tt.cols.foe.w - tt.cols.where.w) <= 2, ("%d vs %d"):format(tt.cols.foe.w, tt.cols.where.w))
        local foes = {}
        for _, r in ipairs(rowsOf(tt)) do if r.c.foe:IsTruncated() then foes[#foes + 1] = r.c.foe.text end end
        check("Timeline " .. tag .. ": no realistic foe name is cut under While fighting", #foes == 0, table.concat(foes, ", "))
      else
        local evMin = 0
        for _, r in ipairs(rowsOf(tt)) do
          if tostring(r.c.ev.text):find("^Auction house: 2 posts, 1 bid, 1 buy$") then evMin = math.ceil(P.G.naturalWidth(r.c.ev)) end
        end
        check("Timeline " .. tag .. ": the event column holds only its measured minimum, the names take the rest", evMin > 0 and tt.cols.ev.w <= evMin + 1, ("%d vs %d"):format(tt.cols.ev.w, evMin))
      end
    end
  end
  -- A left-aligned column right after a right-aligned one needs S5 (24) between them: at S3 two headers read as one
  -- label ("TIME VS BEST") and two values as one ("4m 47s -"). Every kit table on the kit pages, at both sizes.
  do
    local FX = dofile("tests/dungeon_fixture.lua")
    local function pairsOf(root)
      local bad, n = {}, 0
      for _, f in ipairs(P.descendants(root)) do
        local t = rawget(f, "ebKitTable")
        if t and P.visible(f) and t.cols then
          n = n + 1
          local shownCols = {}
          for _, col in ipairs(t.full or t.spec) do
            local cw = t.cols[col.key]
            if cw and not col.chevron and col.kind ~= "icon" then shownCols[#shownCols + 1] = { col = col, x = cw.x, w = cw.w } end
          end
          table.sort(shownCols, function(a, b) return a.x < b.x end)
          for i = 1, #shownCols - 1 do
            local a, b = shownCols[i], shownCols[i + 1]
            if a.col.justify == "RIGHT" and b.col.justify ~= "RIGHT" and b.x - (a.x + a.w) < UI.S.S5 then
              bad[#bad + 1] = ("%s|%s %d"):format(a.col.key, b.col.key, b.x - (a.x + a.w))
            end
          end
        end
      end
      return bad, n
    end
    for _, size in ipairs({ { 900, 580 }, { 1600, 1000 } }) do
      local tag = ("%dx%d"):format(size[1], size[2])
      local undo, fx = FX.install(ns, P.M, "")
      local c = P.open("dungeons", "runs", size[1], size[2], "normal")
      local bad, n = pairsOf(c)
      check("Runs " .. tag .. ": no left-aligned column follows a right-aligned one by less than 24", n > 0 and #bad == 0, table.concat(bad, ", "))
      for _, rec in ipairs({ fx.wc2, fx.rfc }) do
        ns.Dungeons.openRun(rec); P.M.settle()
        bad, n = pairsOf(c)
        check("Run page " .. rec.inst .. " " .. tag .. ": no left-aligned column follows a right-aligned one by less than 24", n > 0 and #bad == 0, table.concat(bad, ", "))
      end
      local dv = P.T.dungeonDetail and P.T.dungeonDetail()
      if dv and dv:IsShown() then dv.d.Close() end
      undo()
      for _, pane in ipairs({ "leveling", "reputation", "professions" }) do
        local cc = P.open("character", pane, size[1], size[2], "normal")
        bad, n = pairsOf(cc)
        check("Character " .. pane .. " " .. tag .. ": no left-aligned column follows a right-aligned one by less than 24", #bad == 0, table.concat(bad, ", "))
      end
    end
  end
  UI.SetWindowSize(900, 580)
end
