-- Pane tests: Character (docs/UX_OVERHAUL.md 4.10, 4.11). Leveling (Quests folded in), Reputation and Professions
-- (Crafting folded in). At 900x580 and 1600x1000, normal and long data: the page column at BOX_L, every table with
-- header x == cell x and numbers right-aligned, Coords only at WIDE, no text past the pane; then what each page adds
-- (docs/UX_PRAGMATIC.md 3.1 to 3.3): the hero, the cards, the levels with an exact moment or a bound, the quest names
-- the game did not give, the reputation answer, order and columns, the faction page, the profession rows with their
-- bar and training line, the crafted batches and every empty state.
return function(P)
  local check, eq, M, ns = P.check, P.eq, P.M, P.ns
  local UI = ns.UI
  local G, S, H = UI.G, UI.S, UI.H
  local V = ns.Progress
  local function near(a, b, tol) return a and b and math.abs(a - b) <= (tol or 0.51) end
  local function click(b) b.scripts.OnClick(b, "LeftButton"); M.settle() end
  local function host() for _, t in ipairs(P.T.tabs) do if t.name == "Character" then return t end end end
  local function colsOf(tbl) local out = {}; for _, c in ipairs(tbl.spec) do if tbl.cols[c.key] then out[#out + 1] = c.key end end return table.concat(out, ",") end

  check("Character: three panes, Leveling, Reputation, Professions; no Quests or Crafting pane", (function()
    local h = host(); local k = {}
    for _, pn in ipairs(h.panes) do k[#k + 1] = pn.key end
    return table.concat(k, ",") == "leveling,reputation,professions" and h.paneByKey.quests == nil and h.paneByKey.crafting == nil
  end)())
  check("Character: the old links land on the new panes", (function()
    UI.Open("Character", "quests"); M.settle()
    local a = host().ctl.active
    UI.Open("Character", "crafting"); M.settle()
    return a == "leveling" and host().ctl.active == "professions"
  end)())

  -- the generic checks: every kit table on the page
  local function tables(tag, content, list)
    local cb = P.box(content)
    local bad = {}
    for _, tbl in ipairs(list) do
      if P.visible(tbl.frame) then
        local fb = P.box(tbl.frame)
        if fb.l + (tbl.usedW or fb.w) > cb.l + cb.w + 0.5 then bad[#bad + 1] = "a table past the pane" end
        for _, col in ipairs(tbl.spec) do
          local cw = tbl.cols[col.key]
          if cw then
            local hb = tbl.head[col.key]
            if not near(P.box(hb.fs).l, fb.l + cw.x) then bad[#bad + 1] = col.key .. " header" end
            local numeric = col.kind == "num" or col.kind == "money"
            if numeric and hb.fs._justify ~= "RIGHT" then bad[#bad + 1] = col.key .. " header not right-aligned" end
            for i = 1, tbl.shownN do
              local row = tbl.rows[i]
              if not row.item.ebSection then
                local cell = row.c[col.key]
                -- (a cell led by a bar, as Reputation's PROGRESS, starts `lead` px into its column)
                if not near(P.box(cell).l, fb.l + cw.x + (col.lead or 0)) then bad[#bad + 1] = col.key .. i end
                if numeric and cell._justify ~= "RIGHT" then bad[#bad + 1] = col.key .. i .. " not right-aligned" end
                -- (a text column held at its `max` may shorten, so the first text column keeps the flex space)
                if col.kind and col.kind ~= "text" and not (col.max and not numeric) and cell:IsTruncated() then bad[#bad + 1] = col.key .. i .. " cut" end
              end
            end
          end
        end
      end
    end
    check(tag .. ": every table's header x == cell x, numbers right-aligned and whole, inside the pane", #bad == 0, table.concat(bad, ","))
  end
  local function spill(tag, content)
    local cb = P.box(content)
    local out = {}
    for _, f in ipairs(P.descendants(content)) do
      if P.visible(f) and rawget(f, "_isFS") and f.text and f.text ~= "" then
        local b = P.box(f)
        if b and b.w > 0 and b.l + math.min(b.w, P.G.naturalWidth(f)) > cb.l + cb.w + 0.5 then out[#out + 1] = tostring(f.text):sub(1, 30) end
      end
    end
    check(tag .. ": no text runs past the pane's right edge", #out == 0, table.concat(out, " | "))
  end

  for _, size in ipairs({ { 900, 580 }, { 1600, 1000 } }) do
    for _, data in ipairs({ "normal", "long" }) do
      local sz = ("%dx%d %s"):format(size[1], size[2], data)
      local wide = G.isWide(size[1])
      -- Leveling
      local c = P.open("character", "leveling", size[1], size[2], data)
      local v = V.leveling
      check("Leveling " .. sz .. ": opened", c ~= nil and v ~= nil)
      if v then
        check("Leveling " .. sz .. ": the column starts at BOX_L, as wide as the main column", near(P.box(v.pg.col).l - P.box(_G.EverbuffFrame).l, G.BOX_L) and near(P.box(v.pg.col).w, G.mainW(G.winW())))
        -- (docs/UX_PRAGMATIC.md 3.1: each block only when it has something; the order is fixed)
        local order, lastT = true, P.box(v.hero).t
        for _, f in ipairs({ v.cards, v.levels.head, v.levels.tbl.frame, v.levelNote, v.quests.head, v.quests.tbl.frame }) do
          if P.visible(f) then if P.box(f).t <= lastT then order = false end; lastT = P.box(f).t end
        end
        check("Leveling " .. sz .. ": hero, cards, LEVELS, its note and QUESTS, top to bottom", order)
        check("Leveling " .. sz .. ": the level is said once, as the hero or its estimate, never as the title too", not tostring(v.hero.title.text or ""):find("Level", 1, true)
          and (tostring(v.hero.hero.text):find("^Level %d+$") ~= nil or tostring(v.hero.hero.text):find(" to level %d+$") ~= nil), tostring(v.hero.title.text) .. " / " .. tostring(v.hero.hero.text))
        check("Leveling " .. sz .. ": LEVELS columns are Level, Reached, Zone: no time at a level, no played stamp, no comparison", colsOf(v.levels.tbl) == "level,reached,zone", colsOf(v.levels.tbl))
        do
          local rows, missing = ns._test.buildLevels(UnitLevel("player"))
          local dated = true
          local n = 0
          for _, r in ipairs(rows) do
            n = n + ((r.lo or r.level) <= r.level and (r.level - (r.lo or r.level) + 1) or 0)
            if not ((type(r.t) == "number" and r.t > 0) or (type(r.from) == "number" and type(r.to) == "number" and r.from <= r.to)) then dated = false end
          end
          check("Leveling " .. sz .. ": every listed level has a recorded moment or a bound, and the rest are counted", dated and n + missing == UnitLevel("player") - 1 and P.visible(v.levels.head) == (#rows > 0)
            and P.visible(v.levelNote) == (missing > 0), n .. "+" .. missing)
        end
        if P.visible(v.quests.tbl.frame) then
          check("Leveling " .. sz .. ": QUESTS columns, Coords only at WIDE", colsOf(v.quests.tbl) == (wide and "when,name,place,gold,coords" or "when,name,place,gold"), colsOf(v.quests.tbl))
          check("Leveling " .. sz .. ": the Quests header says where the list starts, never all time", tostring(v.quests.head.label.text):find("^QUESTS SINCE ") ~= nil, v.quests.head.label.text)
        end
        tables("Leveling " .. sz, c, { v.levels.tbl, v.quests.tbl })
        spill("Leveling " .. sz, c)
      end
      -- Reputation
      c = P.open("character", "reputation", size[1], size[2], data)
      local r = V.rep
      check("Reputation " .. sz .. ": opened", c ~= nil and r ~= nil)
      if r then
        -- (Last day gained at every size; This session only while a faction gained this session, 0.3)
        do
          local want = { "name", "standing" }
          local anyP, anyL, anyS = false, false, false
          for _, row in ipairs(r.rows) do
            if row.need or row.standing >= 8 then anyP = true end
            if row.lastGain then anyL = true end
            if row.session then anyS = true end
          end
          if anyP then want[#want + 1] = "prog" end
          if anyL then want[#want + 1] = "last" end
          if anyS then want[#want + 1] = "ses" end
          want[#want + 1] = "_chev"
          local got = {}
          for _, c2 in ipairs(r.tbl.full) do if r.tbl.cols[c2.key] then got[#got + 1] = c2.key end end
          check("Reputation " .. sz .. ": Faction, Standing, then Progress, Last day gained and This session only while a row has a value", table.concat(got, ",") == table.concat(want, ","), table.concat(got, ","))
          local dash = false
          for i = 1, r.tbl.shownN do for _, c2 in ipairs(r.tbl.spec) do local cell = r.tbl.rows[i].c[c2.key]; if cell and cell.text == "-" then dash = true end end end
          check("Reputation " .. sz .. ": no cell is a dash", not dash)
        end
        tables("Reputation " .. sz, c, { r.tbl })
        spill("Reputation " .. sz, c)
        local bars = {}
        for i = 1, r.tbl.shownN do
          local row = r.tbl.rows[i]
          if row.bar and P.visible(row.bar) then
            local bb, cw = P.box(row.bar), r.tbl.cols.prog
            local pb = P.box(row.c.prog)
            if not near(bb.l, P.box(r.tbl.frame).l + cw.x) or bb.w ~= 120 then bars[#bars + 1] = "bar " .. i end
            if not near(pb.l, bb.l + bb.w + S.S2) then bars[#bars + 1] = "text not right after the bar " .. i end
            if row.c.prog:IsTruncated() then bars[#bars + 1] = "text cut " .. i end
          end
        end
        check("Reputation " .. sz .. ": the 120 px bar at the Progress column, what is left right after it and whole", #bars == 0, table.concat(bars, ","))
      end
      -- Professions
      c = P.open("character", "professions", size[1], size[2], data)
      local p = V.prof
      check("Professions " .. sz .. ": opened", c ~= nil and p ~= nil)
      if p then
        check("Professions " .. sz .. ": CRAFTED columns: When, Item, Profession; the quantity stands after the item's name", colsOf(p.crafted.tbl) == "when,item,prof", colsOf(p.crafted.tbl))
        check("Professions " .. sz .. ": no headline above the rows and no recipe list", p.summary == nil and p.recipes == nil)
        tables("Professions " .. sz, c, { p.crafted.tbl })
        spill("Professions " .. sz, c)
        local bad = {}
        for i, row in ipairs(p.profRows) do
          if P.visible(row) then
            local rb = P.box(row)
            local cbx, bb = P.box(row.count), P.box(row.bar)
            -- (the bar ends S3 left of the value, at most V.BAR_W wide and never left of V.BAR_X)
            if not near(bb.l + bb.w, cbx.l - S.S3) or bb.w > V.BAR_W + 0.5 or bb.l - rb.l < V.BAR_X - 0.5 then bad[#bad + 1] = "bar " .. i end
            if not near(cbx.l + cbx.w, rb.l + rb.w - S.S3) or row.count._justify ~= "RIGHT" then bad[#bad + 1] = "count " .. i end
            if row.train.text ~= "" and not near(P.box(row.train).l, bb.l) then bad[#bad + 1] = "training " .. i end
            if P.box(row.title).l + P.box(row.title).w > bb.l - S.S3 + 0.5 then bad[#bad + 1] = "title runs into the bar " .. i end
            if P.box(row.meta).l + P.G.naturalWidth(row.meta) > P.box(row.bar).l + 0.5 and not row.meta:IsTruncated() then bad[#bad + 1] = "meta runs into the bar " .. i end
          end
        end
        check("Professions " .. sz .. ": each row has its bar S3 left of its count at w-12, the title up to the bar, the training line under the bar", #bad == 0, table.concat(bad, ","))
      end
    end
  end
  UI.SetWindowSize(900, 580)

  -- (P.open puts a fresh copy of the data in place, so each block opens its pane first, then changes the data and
  -- renders again; nothing needs restoring)
  -- ── Leveling: the hero, the two cards, the levels with a recorded moment, the quest names (3.1) ──
  do
    P.open("character", "leveling", 900, 580)
    local v = V.leveling
    local db = ns.char()
    local now = (GetServerTime and GetServerTime()) or time()
    local lvl = UnitLevel("player")
    local ses = ns.Recorder.current()
    -- (the played stamps of the save are overwritten at every login: nothing on the page reads them)
    db.playedAtLevel = { [lvl - 1] = 10000, [lvl] = 13600 }
    db.played = { total = 13600 + 1800, level = 1800, atEpoch = now }  -- 30m at this level so far
    local Pace = ns.Pace
    local realCompute, realRemaining = Pace.compute, Pace.remaining
    Pace.compute = function() return { rate = 3600, active = 30 } end
    Pace.remaining = function() return 1200 end
    V.renderLeveling(); M.settle()
    check("Leveling: the hero is the time to the next level, with no comparison against the level before", v.verdict == ("20m to level %d"):format(lvl + 1) and v.hero.hero.text == v.verdict
      and not tostring(v.hero.meta1r.text):find("faster", 1, true) and not tostring(v.hero.meta1r.text):find("slower", 1, true), v.verdict)
    Pace.compute = function() return {} end
    Pace.remaining = function() return nil end
    V.renderLeveling(); M.settle()
    check("Leveling: before 10 active minutes the hero is the level", v.verdict == ("Level %d"):format(lvl), v.verdict)
    check("Leveling: two cards, PLAYED and TIME AT LEVEL", #v.cards.cards == 2 and v.cardsShown and v.cards.cards[1].label.text == "PLAYED" and v.cards.cards[1].value.text == "4h 17m"
      and v.cards.cards[2].label.text == ("TIME AT LEVEL %d"):format(lvl) and v.cards.cards[2].value.text == "30m" and v.cards.cards[2].meta.text == "so far", v.cards.cards[1].value.text)
    -- (the time since /played answered counts only when it answered in this login)
    db.played.atEpoch = math.max(ses.startedEpoch, now - 600)
    local since = now - db.played.atEpoch
    V.renderLeveling(); M.settle()
    eq("Leveling: the played time moves on since /played answered in this login", v.atLevel, 1800 + since)
    db.played.atEpoch = ses.startedEpoch - 5000
    V.renderLeveling(); M.settle()
    eq("Leveling: an answer from an earlier login adds no time logged out", v.atLevel, 1800)
    db.played = nil
    V.renderLeveling(); M.settle()
    check("Leveling: before /played has answered there are no cards, and no 0 or dash stands in", v.cardsShown == false and not P.visible(v.cards))
    db.played = { total = 13600 + 1800, level = 1800, atEpoch = now }
    -- the levels: the LEVELUP event and the LEVEL_UP row of a stored session, the earliest moment of each
    do
      local sdb = ns.DB.sessions[ns.DB.active]
      local keepEv, keepSeg = ns.DB.story.events, sdb.segments
      ns.DB.story.events = { { s = ns.DB.active, kind = "LEVELUP", t = now - 3000, text = "Ding!  Level " .. lvl, zone = "Westfall" } }
      sdb.segments = { ("7\t%d\t123.456\tLEVEL_UP\t%d\tElwynn Forest"):format(now - 9000, lvl - 1), ("9\t%d\t999.000\tLEVEL_UP\t%d\tWestfall"):format(now - 2990, lvl),
        ("10\t%d\t1000.000\tLEVEL_UP\t%d\tNowhere"):format(now, lvl + 1), "11\t1\t1.000\tRESUME\treload" }
      local other = { id = "other-char", guid = "Player-1-0000FF", startedEpoch = now - 99999, segments = { ("1\t%d\t1.000\tLEVEL_UP\t%d\tDurotar"):format(now - 99000, lvl - 2) } }
      ns.DB.sessions[other.id] = other
      local rows, missing = ns._test.buildLevels(lvl)
      check("levels: one row per level with a recorded moment, newest first; another character's session and a level above the current one give none",
        #rows == 2 and rows[1].level == lvl and rows[1].t == now - 3000 and rows[1].zone == "Westfall" and rows[2].level == lvl - 1 and rows[2].t == now - 9000 and rows[2].zone == "Elwynn Forest", #rows)
      eq("levels: the levels with no recorded moment are counted, from level 2", missing, lvl - 1 - 2)
      check("levels: no row carries a time at the level, a played stamp or a comparison", rows[2].at == nil and rows[2].playedBy == nil and rows[2].vs == nil)
      V.renderLeveling(); M.settle()
      local r1 = v.levels.tbl.rows[1]
      check("Leveling: a row reads the level, the fixed moment and the zone", r1.c.level.text == tostring(lvl) and r1.c.reached.text == UI.fmtSince(now - 3000) .. ", " .. UI.fmtClock(now - 3000) and r1.c.zone.text == "Westfall", r1.c.reached.text)
      eq("Leveling: one muted line counts the levels with no date", v.levelNote.text.text, ("%d levels have no recorded date."):format(lvl - 3))
      -- at the level cap: the level once, when and where, the played time; no cards, no quests
      local keepMax = _G.GetMaxPlayerLevel
      _G.GetMaxPlayerLevel = function() return lvl end
      V.renderLeveling(); M.settle()
      check("Leveling: at the level cap the hero is the level, once", v.hero.hero.text == "Level " .. lvl and not tostring(v.hero.title.text):find("Level", 1, true), v.hero.hero.text)
      eq("Leveling: when and where it was reached", v.hero.meta1.text, "Reached " .. UI.fmtStamp(now - 3000) .. " in Westfall")
      eq("Leveling: the played time, total and at the level", v.hero.meta2.text, "4h 17m played, 30m at " .. lvl)
      check("Leveling: no cards and no quests at the level cap", v.cardsShown == false and not P.visible(v.cards) and not P.visible(v.quests.head) and not P.visible(v.quests.tbl.frame))
      ns.DB.story.events, sdb.segments = {}, {}
      V.renderLeveling(); M.settle()
      check("Leveling: with no moment stored for the level the Reached line is left out and the played line moves up", v.reachedLine == nil and v.hero.meta1.text == "4h 17m played, 30m at " .. lvl
        and not P.visible(v.hero.meta2), v.hero.meta1.text)
      check("Leveling: and no Levels table stands empty", not P.visible(v.levels.head) and not P.visible(v.levels.tbl.frame) and v.levelNote.text.text == ("%d levels have no recorded date."):format(lvl - 1))
      _G.GetMaxPlayerLevel = keepMax
      ns.DB.story.events, sdb.segments = keepEv, keepSeg
      ns.DB.sessions[other.id] = nil
    end
    Pace.compute, Pace.remaining = realCompute, realRemaining
    -- a quest the game did not name
    local L = ns.DB.story.events
    L[#L + 1] = { s = ns.DB.active, kind = "QUESTDONE", t = now + 5, text = "Complete:  quest", zone = "Elwynn Forest" }
    V.renderLeveling(); M.settle()
    local row
    for i = 1, v.quests.tbl.shownN do local r = v.quests.tbl.rows[i]; if r.item.t == now + 5 then row = r end end
    check("Leveling: an unnamed quest reads muted, never the placeholder", row and row.c.name.text ~= "quest" and row.c.name._color and near(row.c.name._color[1], UI.C.fgMuted[1], 0.01), row and row.c.name.text)
    check("Leveling: the quests are grouped under day rows", v.quests.tbl.rows[1].item.ebSection ~= nil)
    check("Leveling: a quest with no gold recorded has a blank Gold cell, never a dash", row and row.c.gold.text == "", row and row.c.gold.text)
    local first
    for _, q in ipairs(v.questRows) do if not first or q.t < first then first = q.t end end
    eq("Leveling: the Quests header says where the stored list starts, and carries no count", v.quests.head.label.text, ("QUESTS SINCE " .. UI.fmtSince(first)):upper())
  end

  -- ── Leveling: a level known only between two stored moments, and what is kept in the character's block (gate E) ──
  do
    P.open("character", "leveling", 900, 580)
    local v = V.leveling
    local Lv = ns.Levels
    local g = ns.charGuid()
    -- (noon, four days before the suite's clock: every record of the fixture lies before the running session)
    local now0 = (GetServerTime and GetServerTime()) or time()
    local d0 = os.date("*t", now0 - 4 * 86400)
    local D0 = os.time({ year = d0.year, month = d0.month, day = d0.day, hour = 12 })
    local function seg(n, t, L, zone) return ("%d\t%d\t1.000\tLEVEL_UP\t%d\t%s"):format(n, t, L, zone) end
    local function fixture()
      return {
        a = { id = "a", guid = g, level0 = 50, level = 51, startedEpoch = D0, endedEpoch = D0 + 2000, segments = { seg(1, D0 + 1500, 51, "The Hinterlands") } },
        b = { id = "b", guid = g, level0 = 51, level = 51, startedEpoch = D0 + 3000, endedEpoch = D0 + 4000, segments = {} },
        -- (the session in which 52 was reached is gone: 51 at the end of b, 52 at the start of c)
        c = { id = "c", guid = g, level0 = 52, level = 53, startedEpoch = D0 + 6000, endedEpoch = D0 + 9000, segments = { seg(1, D0 + 8000, 53, "Swamp of Sorrows") } },
        -- (54, 55 and 56 were reached between c and d, two days apart)
        d = { id = "d", guid = g, level0 = 56, level = 57, startedEpoch = D0 + 2 * 86400, endedEpoch = D0 + 2 * 86400 + 5000, segments = { seg(1, D0 + 2 * 86400 + 2500, 57, "Blackrock Depths") } },
        -- (a record whose level was not read says nothing, and another character's record is not this character's)
        z = { id = "z", guid = g, level0 = 0, level = 0, startedEpoch = D0 + 4500, endedEpoch = D0 + 5000, segments = {} },
        o = { id = "o", guid = "Player-1-0000FF", level0 = 56, level = 56, startedEpoch = D0 + 100, endedEpoch = D0 + 200, segments = { seg(1, D0 + 150, 52, "Durotar") } },
      }
    end
    local list = {}
    for _, s in pairs(fixture()) do if s.guid == g then list[#list + 1] = s end end
    local at = Lv.derive(list, { { kind = "LEVELUP", t = D0 + 1501, text = "Ding!  Level 51", zone = "Elsewhere" } }, 57)
    check("levels: an exact moment is the earliest stored one, with its zone", at[51] and at[51].t == D0 + 1500 and at[51].zone == "The Hinterlands" and at[53].t == D0 + 8000 and at[57].t == D0 + 2 * 86400 + 2500)
    check("levels: a level with no row of its own is bound by the session before it and the one after it", at[52] and at[52].t == nil and at[52].from == D0 + 4000 and at[52].to == D0 + 6000,
      at[52] and (tostring(at[52].from) .. ".." .. tostring(at[52].to)))
    check("levels: three levels between the same two sessions share one bound", at[54] and at[55] and at[56] and at[54].from == D0 + 9000 and at[56].to == D0 + 2 * 86400 and at[55].from == at[54].from and at[55].to == at[56].to)
    check("levels: a level below every stored record has nothing (no lower moment is stored)", at[50] == nil and at[2] == nil)
    -- the merge: the earliest exact moment stays, an exact moment replaces a bound, a bound only narrows
    local m = Lv.merge({ [51] = { t = D0 + 1400, zone = "Kept" }, [52] = { from = D0 + 4500, to = D0 + 7000 }, [53] = { from = 1, to = 2 }, [40] = { t = 5 } }, at)
    check("levels: a stored moment is never replaced by a later one", m[51].t == D0 + 1400 and m[51].zone == "Kept" and m[40].t == 5)
    check("levels: an exact moment replaces a stored bound, and two bounds narrow", m[53].t == D0 + 8000 and m[52].from == D0 + 4500 and m[52].to == D0 + 6000, m[52].from)
    -- the table: one row per exact level, one row for the levels that share a bound
    local keepS, keepE, keepLvl, keepMax = ns.DB.sessions, ns.DB.story.events, _G.UnitLevel, _G.GetMaxPlayerLevel
    local db = ns.char()
    local keepAt = db.levelAt
    db.levelAt = nil
    local fx = fixture()
    fx[ns.DB.active] = keepS[ns.DB.active]
    ns.DB.sessions, ns.DB.story.events = fx, {}
    local act = fx[ns.DB.active]
    local keepAct = { act.level0, act.level, act.segments }
    act.level0, act.level, act.segments = 57, 57, {}
    _G.UnitLevel = function() return 57 end
    _G.GetMaxPlayerLevel = function() return 60 end
    local rows, missing = ns._test.buildLevels(57)
    local got = {}
    for _, r in ipairs(rows) do got[#got + 1] = (r.lo and r.lo < r.level and (r.lo .. "-" .. r.level) or tostring(r.level)) .. (r.t and "=" or "~") end
    eq("levels: the rows, highest first: exact (=) and bound (~), levels of one bound together", table.concat(got, " "), "57= 54-56~ 53= 52~ 51=")
    eq("levels: the levels with nothing stored are counted", missing, 56 - 7)
    V.renderLeveling(); M.settle()
    local cells = {}
    for i = 1, v.levels.tbl.shownN do local r = v.levels.tbl.rows[i]; cells[#cells + 1] = r.c.level.text .. " | " .. r.c.reached.text .. " | " .. r.c.zone.text end
    eq("Leveling: a bound within one day reads the day, with no time and no zone", cells[4], "52 | " .. UI.fmtSince(D0 + 4000, now0) .. " | ")
    eq("Leveling: a bound over days reads both days, and the levels it covers", cells[2], "54 to 56 | " .. V.fmtBound(D0 + 9000, D0 + 2 * 86400, now0) .. " | ")
    eq("Leveling: an exact row keeps its time and zone", cells[3], "53 | " .. UI.fmtSince(D0 + 8000, now0) .. ", 14:13 | Swamp of Sorrows")
    -- (the wording on fixed dates: 17 Nov 2026 is a Tuesday)
    local N17 = os.time({ year = 2026, month = 11, day = 17, hour = 12 })
    eq("Leveling: a bound within one day is that day", V.fmtBound(N17 + 4000, N17 + 6000, N17 + 9 * 86400), "Tue 17 Nov")
    eq("Leveling: a bound over days of one month", V.fmtBound(N17 + 9000, N17 + 2 * 86400, N17 + 9 * 86400), "17 to 19 Nov")
    eq("Leveling: a bound across two months", V.fmtBound(os.time({ year = 2026, month = 10, day = 30, hour = 12 }), os.time({ year = 2026, month = 11, day = 2, hour = 12 }), N17), "30 Oct to 2 Nov")
    eq("Leveling: a bound of another year names the year", V.fmtBound(os.time({ year = 2025, month = 12, day = 30, hour = 12 }), os.time({ year = 2026, month = 1, day = 2, hour = 12 }), os.time({ year = 2026, month = 6, day = 1, hour = 12 })), "30 Dec 2025 to 2 Jan")
    eq("Leveling: the hover of a bound says between which two moments", V.boundTip(N17 + 4000, N17 + 6000, N17 + 9 * 86400), "Between 13:06 and 13:40")
    eq("Leveling: over days the hover names both days", V.boundTip(N17 + 9000, N17 + 2 * 86400, N17 + 9 * 86400), "Between Tue 17 Nov 14:30 and Thu 19 Nov 12:00")
    check("Leveling: no cell is a dash", not table.concat(cells, "\n"):find(" %- ") and not table.concat(cells, "\n"):find("| %-$"))
    eq("Leveling: the muted line counts only the levels with nothing stored", v.levelNote.text.text, "49 levels have no recorded date.")
    -- at the level cap the Reached line needs the exact moment: a bound for the level leaves it out
    _G.GetMaxPlayerLevel = function() return 57 end
    V.renderLeveling(); M.settle()
    check("Leveling: at the level cap the Reached line is the exact moment", v.reachedLine ~= nil and v.reachedLine:find("Blackrock Depths", 1, true) ~= nil, v.reachedLine)
    fx.d.segments = {}
    V.renderLeveling(); M.settle()
    check("Leveling: a level known only by a bound has no Reached line", v.reachedLine == nil, v.reachedLine)
    fx.d.segments = { seg(1, D0 + 2 * 86400 + 2500, 57, "Blackrock Depths") }
    -- the load and the pickup: the moments are copied into the block before a session record is deleted
    check("levels: nothing is in the block before the copy", db.levelAt == nil)
    local keepAck = ns.DB.combat.lastAck
    ns.applyAck({ sessions = { a = true, b = true, c = true, d = true, o = true } }, "test")
    check("levels: the pickup deleted the session records", ns.DB.sessions.a == nil and ns.DB.sessions.c == nil and ns.DB.sessions.d == nil)
    check("levels: the moments and the bounds are in the character's block, so they outlive the records", type(db.levelAt) == "table" and db.levelAt[51] and db.levelAt[51].t == D0 + 1500
      and db.levelAt[51].zone == "The Hinterlands" and db.levelAt[57].t == D0 + 2 * 86400 + 2500 and db.levelAt[52].from == D0 + 4000 and db.levelAt[52].to == D0 + 6000)
    check("levels: another character's level-up is not copied into this block", db.levelAt[52].t == nil)
    local rows2 = ns._test.buildLevels(57)
    local got2 = {}
    for _, r in ipairs(rows2) do got2[#got2 + 1] = (r.lo and r.lo < r.level and (r.lo .. "-" .. r.level) or tostring(r.level)) .. (r.t and "=" or "~") end
    eq("levels: the table reads the same after the pickup", table.concat(got2, " "), "57= 54-56~ 53= 52~ 51=")
    -- a second copy changes nothing, and a later moment for a stored level is not taken
    ns.DB.sessions.late = { id = "late", guid = g, level0 = 50, level = 51, startedEpoch = D0 + 90000, endedEpoch = D0 + 99000, segments = { seg(1, D0 + 95000, 51, "Wrong") } }
    Lv.harvest(ns.DB)
    check("levels: a copy never replaces a stored moment by a later one", db.levelAt[51].t == D0 + 1500 and db.levelAt[51].zone == "The Hinterlands")
    -- a save with two characters: each block gets its own levels, and a block is never created
    local two = { characters = { A = {}, B = {} }, story = { events = { { s = "s2", kind = "LEVELUP", t = 700, text = "Ding!  Level 9", zone = "Durotar" } } },
      sessions = { s1 = { guid = "A", level0 = 4, level = 5, startedEpoch = 100, endedEpoch = 200, segments = { seg(1, 150, 5, "Elwynn Forest") } },
        s2 = { guid = "B", level0 = 8, level = 9, startedEpoch = 600, endedEpoch = 800, segments = {} }, s3 = { guid = "C", level0 = 1, level = 2, startedEpoch = 1, endedEpoch = 2, segments = { seg(1, 1, 2, "Nowhere") } } } }
    Lv.harvest(two)
    check("levels: each character's block gets its own level-ups; a character with no block gets none", two.characters.A.levelAt[5].t == 150 and two.characters.A.levelAt[9] == nil
      and two.characters.B.levelAt[9].t == 700 and two.characters.B.levelAt[5] == nil and two.characters.C == nil)
    ns.DB.combat.lastAck = keepAck
    act.level0, act.level, act.segments = keepAct[1], keepAct[2], keepAct[3]
    ns.DB.sessions, ns.DB.story.events, _G.UnitLevel, _G.GetMaxPlayerLevel = keepS, keepE, keepLvl, keepMax
    db.levelAt = keepAt
  end

  -- ── empty states ──
  do
    local function empty()
      local db = ns.char()
      ns.DB.story.events, ns.DB.story.rep, db.playedAtLevel, db.levelAt, db.reputation, db.professions, db.crafts, db.recipes = {}, {}, nil, nil, nil, nil, nil, nil
    end
    local keepF = { _G.GetNumFactions, _G.C_Reputation }
    _G.GetNumFactions, _G.C_Reputation = nil, nil
    P.open("character", "leveling", 900, 580); empty(); V.renderLeveling(); M.settle()
    local v = V.leveling
    check("Leveling empty: no Levels table and no Quests table stand empty, and no sentence takes their place", not P.visible(v.levels.head) and not P.visible(v.levels.tbl.frame)
      and not P.visible(v.quests.head) and not P.visible(v.quests.tbl.frame))
    P.open("character", "reputation", 900, 580); empty(); V.renderRep(); M.settle()
    check("Reputation empty: the inline sentence", V.rep.tbl.state == "No faction met yet.", V.rep.tbl.state)
    check("Reputation empty: no answer line", not P.visible(V.rep.summary) and V.rep.answer == nil)
    P.open("character", "professions", 900, 580); empty(); V.renderProf(); M.settle()
    local p = V.prof
    check("Professions empty: the inline sentence", P.visible(p.empty) and p.empty.text.text == "No profession learned yet.", p.empty.text and p.empty.text.text)
    check("Professions empty: no Crafted section stands empty", not P.visible(p.crafted.head) and not P.visible(p.crafted.tbl.frame))
    _G.GetNumFactions, _G.C_Reputation = keepF[1], keepF[2]
  end

  -- ── Reputation: the answer, the order, the columns, whose gains count, the faction page (3.2) ──
  do
    local keepF = { _G.GetNumFactions, _G.GetFactionInfo, _G.C_Reputation }
    local LIVE = { { "Stormwind", 7, 21000, 42000, 25928 }, { "Defias Brotherhood", 2, -6000, -3000, -5000 }, { "Ironforge", 8, 42000, 43000, 42999 }, { "Gnomeregan Exiles", 4, 0, 3000, 75 } }
    _G.C_Reputation = nil
    _G.GetNumFactions = function() return #LIVE end
    _G.GetFactionInfo = function(i) local f = LIVE[i]; if f then return f[1], "", f[2], f[3], f[4], f[5], false, false, false end end
    P.open("character", "reputation", 900, 580)
    local db = ns.char()
    local g = ns.charGuid()
    local now = (GetServerTime and GetServerTime()) or time()
    -- (Darnassus is in the stored block only: the client does not answer for it)
    db.reputation = { Stormwind = { standing = 7, label = "Revered" }, ["Defias Brotherhood"] = { standing = 2, label = "Hostile" }, Darnassus = { standing = 4, label = "Neutral" },
      Ironforge = { standing = 8, label = "Exalted" }, ["Gnomeregan Exiles"] = { standing = 4, label = "Neutral" } }
    local old = now - 3 * 86400
    ns.DB.story.rep = {
      -- a row of a session the desktop picked up, with no character on it: nothing says whose it is
      { s = "gone-1", t = now, faction = "Defias Brotherhood", amount = 999 },
      -- the same, written from 0.9.52: it carries its character and still counts
      { s = "gone-2", g = g, t = old, faction = "Gnomeregan Exiles", amount = 75 },
      -- another character's row
      { s = "gone-3", g = "Player-1-0000FF", t = now, faction = "Darnassus", amount = 10 },
      { s = ns.DB.active, g = g, t = now, faction = "Stormwind", amount = 250, src = "Quest: The Fargodeep Mine" },
      { s = ns.DB.active, t = now, faction = "Stormwind", amount = 5 },
    }
    local r = V.rep
    V.renderRep(); M.settle()
    local names, byName = {}, {}
    for i = 1, r.tbl.shownN do local row = r.tbl.rows[i]; names[#names + 1] = row.item.name; byName[row.item.name] = row end
    eq("Reputation: factions with a stored gain first (newest day first), then by standing, a Neutral one with no gain last", table.concat(names, ", "),
      "Stormwind, Gnomeregan Exiles, Ironforge, Defias Brotherhood, Darnassus")
    eq("Reputation: the answer is the first row: the faction, what that day brought, the day; never called one gain", r.answer, "Stormwind +255 today")
    eq("Reputation: the column says what the number is", r.spec.last.label, "Last day gained")
    check("Reputation: the answer line is shown, above the list", P.visible(r.summary) and P.box(r.summary).t < P.box(r.head).t)
    local sw, hostile = byName.Stormwind, byName["Defias Brotherhood"]
    check("Reputation: Hostile reads bad with the dot", hostile and hostile.c.standing.text:find("Hostile", 1, true) ~= nil and near(hostile.c.standing._color[1], UI.C.bad[1], 0.01))
    eq("Reputation: Progress is what is left to the next standing (21,000 - 4,928)", sw.c.prog.text, "16,072 to Exalted")
    eq("Reputation: at the top standing Progress reads it, with a full bar", byName.Ironforge.c.prog.text, "Exalted")
    check("Reputation: a faction the client does not answer for reads Not known yet, muted, never a dash", byName.Darnassus.c.prog.text == "Not known yet" and near(byName.Darnassus.c.prog._color[1], UI.C.fgMuted[1], 0.01))
    eq("Reputation: Last day gained is the day's gain and the day", sw.c.last.text, "+255 \194\183 Today")
    eq("Reputation: a gain that carries its character counts after its session record is gone", byName["Gnomeregan Exiles"].c.last.text, "+75 \194\183 " .. UI.fmtDate(old, now))
    check("Reputation: a gain with no character and no session record is not attributed", hostile.item.lastGain == nil and hostile.item.hasGains == false and hostile.item.partial == true and hostile.c.last.text == "")
    check("Reputation: another character's gain is not this character's", byName.Darnassus.item.lastGain == nil and byName.Darnassus.c.last.text == "")
    check("Reputation: This session is a column while a faction gained this session", r.tbl.cols.ses ~= nil and sw.c.ses.text == "+255" and hostile.c.ses.text == "", sw.c.ses.text)
    check("Reputation: a Neutral faction with no gain is muted", near(byName.Darnassus.c.name._color[1], UI.C.fgMuted[1], 0.01) and not near(byName["Gnomeregan Exiles"].c.name._color[1], UI.C.fgMuted[1], 0.001))
    check("Reputation: only a faction with stored gains has the chevron", sw.c._chev.text ~= "" and byName["Gnomeregan Exiles"].c._chev.text ~= "" and hostile.c._chev.text == "" and byName.Darnassus.c._chev.text == "")
    click(hostile)
    check("Reputation: a faction with no stored gain opens nothing", not r.detail.IsOpen())
    click(sw)
    check("Reputation: a faction with gains opens its page", r.detail.IsOpen() and V.FACTION.title.text == "Stormwind")
    check("Reputation: the faction page lists the stored gains", #V.FACTION.hist == 2 and V.FACTION.hist[1].source == "Quest: The Fargodeep Mine" and V.FACTION.tbl.rows[1].c.amount.text == "+250")
    eq("Reputation: its header says where the stored gains start, and their sum", V.FACTION.head.label.text .. " | " .. V.FACTION.head.meta.text, ("GAINS SINCE " .. UI.fmtSince(now)):upper() .. " | +255")
    check("Reputation: a gain with no stored source has a blank Source cell, never Other", V.FACTION.tbl.cols.source ~= nil and V.FACTION.tbl.rows[2].c.source.text == "", V.FACTION.tbl.rows[2].c.source.text)
    check("Reputation: the faction page is whole (no stored gain of the faction without a character)", V.FACTION.partial == nil)
    check("Reputation: the faction page says what is left, not the raw numbers", V.FACTION.meta.text:find("16,072 to Exalted", 1, true) ~= nil and V.FACTION.meta.text:find("+255 this session", 1, true) ~= nil, V.FACTION.meta.text)
    r.detail.Close(); M.settle()
    check("Reputation: Back returns to the list", not r.detail.IsOpen() and P.visible(r.list))
    -- no gain this session: the column goes
    for _, row in ipairs(ns.DB.story.rep) do if row.s == ns.DB.active then row.s, row.g = "gone-4", g end end
    V.renderRep(); M.settle()
    check("Reputation: with no gain this session there is no This session column", r.tbl.cols.ses == nil and r.tbl.cols.last ~= nil)
    -- no stored gain at all: no answer, no Last day gained column, nothing opens
    -- A stored gain of a session the desktop picked up, with no character on it, may be this character's. On the day
    -- the cell shows (or after it) the day's total cannot be said: the cell is blank, never the smaller number.
    do
      local D = now - (now % 86400) + 43200   -- (a noon, so +-1 h stays on the day)
      local function setRep(extra)
        ns.DB.story.rep = {
          { s = "gone-5", g = g, t = D - 2 * 86400, faction = "Stormwind", amount = 100 },
          { s = "gone-5", g = g, t = D - 86400, faction = "Stormwind", amount = 200 },
          { s = "gone-5", g = g, t = D - 86400 + 60, faction = "Stormwind", amount = 50 },
          { s = "gone-5", g = g, t = D - 86400, faction = "Gnomeregan Exiles", amount = 75 },
          extra,
        }
        V.renderRep(); M.settle()
        local by = {}
        for i = 1, r.tbl.shownN do by[r.tbl.rows[i].item.name] = r.tbl.rows[i] end
        return by
      end
      local by = setRep(nil)
      eq("Reputation: with every stored gain attributed the cell is the day's sum", by.Stormwind.c.last.text, "+250 \194\183 " .. UI.fmtDate(D - 86400, now))
      by = setRep({ s = "gone-6", t = D - 86400 + 3600, faction = "Stormwind", amount = 450 })
      check("Reputation: a stored gain with no character on the shown day makes the cell blank, not a smaller number",
        by.Stormwind.c.last.text == "" and by.Stormwind.item.partial == true and by.Stormwind.item.lastGain == nil and by.Stormwind.item.dayGain == nil, by.Stormwind.c.last.text)
      check("Reputation: the faction still opens its stored gains", by.Stormwind.c._chev.text ~= "" and by.Stormwind.item.hasGains == true)
      eq("Reputation: the answer is then the first row that shows a gain", r.answer, "Gnomeregan Exiles +75 " .. (UI.fmtDate(D - 86400, now) == "Yesterday" and "yesterday" or ("on " .. UI.fmtDate(D - 86400, now))))
      eq("Reputation: the blank faction stands with the rest, by standing (after Exalted Ironforge)", r.tbl.rows[1].item.name .. ", " .. r.tbl.rows[2].item.name .. ", " .. r.tbl.rows[3].item.name, "Gnomeregan Exiles, Ironforge, Stormwind")
      click(by.Stormwind); M.settle()
      check("Reputation: its page lists the gains but says no start and no sum", r.detail.IsOpen() and #V.FACTION.hist == 3 and V.FACTION.head.label.text == "GAINS" and not P.visible(V.FACTION.head.meta) and V.FACTION.partial == true, V.FACTION.head.label.text)
      r.detail.Close(); M.settle()
      by = setRep({ s = "gone-6", t = D + 3600, faction = "Stormwind", amount = 450 })
      check("Reputation: a stored gain with no character on a later day: the older day is not shown as the last one", by.Stormwind.c.last.text == "" and by.Stormwind.item.partial == true)
      by = setRep({ s = "gone-6", t = D - 2 * 86400 + 3600, faction = "Stormwind", amount = 450 })
      eq("Reputation: a stored gain with no character on an earlier day leaves the last day's sum exact", by.Stormwind.c.last.text, "+250 \194\183 " .. UI.fmtDate(D - 86400, now))
      click(by.Stormwind); M.settle()
      check("Reputation: but the page, which starts on that earlier day, says no start and no sum", V.FACTION.head.label.text == "GAINS" and not P.visible(V.FACTION.head.meta), V.FACTION.head.label.text)
      r.detail.Close(); M.settle()
      -- the same row once its session is proven (a craft of this character carries the session id): it counts
      local keepCrafts = db.crafts
      db.crafts = { { s = "gone-6", t = D, item = "Tin Bar", id = 3576, prof = "Mining" } }
      by = setRep({ s = "gone-6", t = D - 86400 + 3600, faction = "Stormwind", amount = 450 })
      ns.Rep.harvest(ns.DB); V.renderRep(); M.settle()
      eq("Reputation: after the harvest proved the session by a craft, the gain counts", r.tbl.rows[1].c.last.text .. " " .. r.tbl.rows[1].item.name, "+700 \194\183 " .. UI.fmtDate(D - 86400, now) .. " Stormwind")
      db.crafts = keepCrafts
      -- a pickup: rows of before 0.9.52 whose session records the ack deletes still count afterwards
      ns.DB.sessions["old-1"] = { id = "old-1", guid = g, startedEpoch = D - 86400, endedEpoch = D - 86400 + 7200 }
      ns.DB.story.rep = { { s = "old-1", t = D - 86400, faction = "Stormwind", amount = 300 }, { s = "old-1", t = D - 86400 + 30, faction = "Stormwind", amount = 25 } }
      -- (applyAck also copies the level moments into the block and notes the pickup: both put back)
      local lastAck, keepAt = ns.DB.combat.lastAck, db.levelAt
      ns.applyAck({ sessions = { ["old-1"] = true } }, "file")
      db.levelAt = keepAt
      V.renderRep(); M.settle()
      check("Reputation: old rows still show after applyAck deleted their session record", ns.DB.sessions["old-1"] == nil and r.tbl.rows[1].item.name == "Stormwind" and r.tbl.rows[1].c.last.text == "+325 \194\183 " .. UI.fmtDate(D - 86400, now), r.tbl.rows[1].c.last.text)
      ns.DB.combat.lastAck = lastAck
    end
    ns.DB.story.rep = {}
    V.renderRep(); M.settle()
    check("Reputation: with no stored gain there is no answer line and no Last day gained column", not P.visible(r.summary) and r.answer == nil and r.tbl.cols.last == nil and r.tbl.cols.prog ~= nil)
    eq("Reputation: the header counts the factions", r.head.meta.text, "5 factions")
    -- the client answers nothing (a save read outside the game): no Progress column, no bar, no row of "Not known yet"
    _G.GetNumFactions, _G.GetFactionInfo = nil, nil
    db.reputation.Ironforge = nil
    V.renderRep(); M.settle()
    local bars = false
    for i = 1, r.tbl.shownN do if r.tbl.rows[i].bar and P.visible(r.tbl.rows[i].bar) then bars = true end end
    check("Reputation: while the client answers for no faction the Progress column and its bars are left out", r.tbl.cols.prog == nil and not bars)
    _G.GetNumFactions, _G.GetFactionInfo, _G.C_Reputation = keepF[1], keepF[2], keepF[3]
  end

  -- ── Professions: rows, training line, the crafted batches (3.3) ──
  do
    P.open("character", "professions", 900, 580)
    local db = ns.char()
    local D0 = os.time({ year = 2026, month = 11, day = 20, hour = 12 })
    db.professions = { Tailoring = { rank = 118, max = 150 }, Mining = { rank = 30, max = 75 }, ["First Aid"] = { rank = 246, max = 300 } }
    -- (recipes are learned at a trainer with no profession window open: their rows name no profession)
    db.recipes = { { s = "s1", t = D0, name = "Linen Bandage" }, { s = "s1", t = D0, name = "Heavy Linen Bandage" }, { s = "s1", t = D0, name = "Wool Bandage", prof = "" },
      { s = "s1", t = D0, name = "|cffffffff|Hitem:2568|h[Brown Linen Vest]|h|r", prof = "Tailoring" } }
    local crafts = {}
    -- 30 bandages in 58 s: one batch
    for i = 0, 29 do crafts[#crafts + 1] = { s = "s1", t = D0 + i * 2, item = "Linen Bandage", id = 1251, count = 1, prof = "First Aid" } end
    -- 61 s after the last one: a new batch
    crafts[#crafts + 1] = { s = "s1", t = D0 + 58 + 61, item = "Linen Bandage", id = 1251, count = 1, prof = "First Aid" }
    -- two crafts of 2: the row counts items
    crafts[#crafts + 1] = { s = "s1", t = D0 + 600, item = "Bronze Bar", count = 2, prof = "Mining" }
    crafts[#crafts + 1] = { s = "s1", t = D0 + 603, item = "Bronze Bar", count = 2, prof = "Mining" }
    -- the same item in another session is its own row; a craft stored with no profession joins the crafts of its
    -- spell around it and reads their profession
    crafts[#crafts + 1] = { s = "s2", t = D0 + 610, item = "Bronze Bar", count = 2, prof = "Mining" }
    crafts[#crafts + 1] = { s = "s2", t = D0 + 612, item = "Bronze Bar", count = 2 }
    -- a row merged at write time (0.9.52) with the craft that follows its last second
    crafts[#crafts + 1] = { s = "s2", t = D0 + 3600, t1 = D0 + 3720, item = "Bolt of Linen Cloth", count = 49, prof = "Tailoring" }
    crafts[#crafts + 1] = { s = "s2", t = D0 + 3770, item = "Bolt of Linen Cloth", count = 1, prof = "Tailoring" }
    -- the first craft of a round, stored before the profession was read (by spell id), then the rest of the round
    crafts[#crafts + 1] = { s = "s2", t = D0 + 7200, item = "Tin Bar", id = 3576, count = 1 }
    crafts[#crafts + 1] = { s = "s2", t = D0 + 7203, item = "Tin Bar", id = 3576, count = 1, prof = "Mining" }
    crafts[#crafts + 1] = { s = "s2", t = D0 + 7206, item = "Tin Bar", id = 3576, count = 1, prof = "Mining" }
    -- an item a quest made: no stored row of its spell names a profession
    crafts[#crafts + 1] = { s = "s2", t = D0 + 7300, item = "Courier's Shipment", id = 260452, count = 1 }
    -- the day after
    crafts[#crafts + 1] = { s = "s3", t = D0 + 86400, item = "Rough Arrow", count = 200, prof = "Engineering" }
    db.crafts = crafts
    local batches, sum = ns._test.buildCrafts()
    local got = {}
    for _, b in ipairs(batches) do got[#got + 1] = ("%s x%d (%d) %s"):format(b.item, b.count, b.crafts, tostring(b.prof)) end
    eq("crafts: one row per batch, newest first: same spell and session, at most 60 s apart; the profession is the one a row of the spell names", table.concat(got, ", "),
      "Rough Arrow x200 (1) Engineering, Tin Bar x3 (3) Mining, Bolt of Linen Cloth x50 (2) Tailoring, Bronze Bar x4 (2) Mining, Bronze Bar x4 (2) Mining, Linen Bandage x1 (1) First Aid, Linen Bandage x30 (30) First Aid")
    check("crafts: a craft whose spell no stored row gives a profession is left out, with its item", (function() for _, b in ipairs(batches) do if b.item == "Courier's Shipment" then return false end end return true end)())
    check("crafts: the sum is the items listed and where they start", sum.items == 292 and sum.since == D0 and sum.batches == 7, sum.items)
    check("crafts: a batch runs from its first craft to its last", batches[7].t == D0 and batches[7].t1 == D0 + 58 and batches[3].t == D0 + 3600 and batches[3].t1 == D0 + 3770 and batches[2].t == D0 + 7200)
    -- the cap: a list that has reached Market.CRAFT_CAP has lost its oldest rows, so its oldest day is cut
    do
      local cap = ns.Market.CRAFT_CAP
      local DAY0 = D0 - 5 * 86400
      local full = {}
      -- 25 rows left of a longer day, the first of them the tail of a batch
      for i = 0, 24 do full[#full + 1] = { s = "c1", t = DAY0 + i * 3, item = "Roast Raptor", id = 15856, count = 1, prof = "Cooking" } end
      -- then whole days
      for i = 0, cap - 26 do full[#full + 1] = { s = "c2", t = DAY0 + 86400 + i * 3, item = "Tin Bar", id = 3576, count = 1, prof = "Mining" } end
      db.crafts = full
      local b2, s2 = ns._test.buildCrafts()
      check("crafts at the cap: the fixture is full", #full == cap, #full)
      check("crafts at the cap: the oldest day is partial, so its batches and its items are left out", s2.items == cap - 25 and s2.since == DAY0 + 86400 and b2[#b2].item == "Tin Bar", s2.items)
      V.renderProf(); M.settle()
      eq("crafts at the cap: the header names the first whole day", V.prof.crafted.head.label.text .. " | " .. V.prof.crafted.head.meta.text, ("CRAFTED SINCE " .. UI.fmtSince(DAY0 + 86400)):upper() .. " | " .. UI.plural(cap - 25, "item"))
      local cutDay = false
      for i = 1, V.prof.crafted.tbl.shownN do local it = V.prof.crafted.tbl.rows[i].item; if it.ebSection and it.t < DAY0 + 86400 then cutDay = true end end
      check("crafts at the cap: no day row for the cut day", not cutDay)
      -- one row under the cap: nothing was dropped, the first day stays
      table.remove(full)
      b2, s2 = ns._test.buildCrafts()
      check("crafts below the cap: the first day stays, with its items", s2.items == cap - 1 and s2.since == DAY0 and b2[#b2].item == "Roast Raptor", s2.items)
      db.crafts = crafts
    end
    V.renderProf(); M.settle()
    local p = V.prof
    local t = p.profRows[1]
    check("Professions: the highest skill first, with its rank name", t.title.text == "First Aid" and t.meta.text == "Artisan" and p.profRows[2].title.text == "Tailoring", t.meta.text)
    local anyRecipe = false
    for _, row in ipairs(p.profRows) do if P.visible(row) and (tostring(row.meta.text):find("recipe", 1, true) or tostring(row.train.text):find("recipe", 1, true)) then anyRecipe = true end end
    check("Professions: no row counts recipes (First Aid has three stored with no profession: never 0 recipes learned)", not anyRecipe)
    check("Professions: the count reads rank / max", t.count.text == "246 / 300" and p.profRows[2].count.text == "118 / 150")
    check("Professions: the training line 10 under the threshold", p.profRows[2].train.text == "Expert training opens at 125")
    check("Professions: Mining has no training line at 30 of 75", p.profRows[3].train.text == "")
    eq("Professions: the Crafted header says where the stored list starts", p.crafted.head.label.text, ("CRAFTED SINCE " .. UI.fmtSince(D0)):upper())
    eq("Professions: its meta counts items, not crafts", p.crafted.head.meta.text, "292 items")
    local lines = {}
    for i = 1, p.crafted.tbl.shownN do
      local row = p.crafted.tbl.rows[i]
      lines[#lines + 1] = row.item.ebSection or (row.c.when.text .. " | " .. row.c.item.text .. " | " .. row.c.prof.text)
    end
    eq("Professions: a day row counts the day's items", lines[1], UI.fmtDay(D0 + 86400) .. " \194\183 200 items")
    eq("Professions: the newest batch", lines[2], "12:00 | Rough Arrow x200 | Engineering")
    eq("Professions: the second day row (the quest item is not counted)", lines[3], UI.fmtDay(D0) .. " \194\183 92 items")
    eq("Professions: the craft stored with no profession is in the batch of its spell, with the profession", lines[4], "14:00 | Tin Bar x3 | Mining")
    eq("Professions: a batch reads its span and its items after the name", lines[5], "13:00 to 13:02 | Bolt of Linen Cloth x50 | Tailoring")
    eq("Professions: 30 crafts in under a minute are one row", lines[#lines], "12:00 | Linen Bandage x30 | First Aid")
    eq("Professions: a craft 61 s later is its own row, with no x1", lines[#lines - 1], "12:01 | Linen Bandage | First Aid")
    check("Professions: 7 batches under 2 day rows", #lines == 9, #lines)
    local blank = false
    for _, l in ipairs(lines) do if l:find(" | $") then blank = true end end
    check("Professions: every listed batch names its profession", not blank and p.crafted.tbl.cols.prof ~= nil)
    -- with no profession on any craft nothing says these are profession crafts: nothing is listed
    for _, c2 in ipairs(db.crafts) do c2.prof = nil end
    V.renderProf(); M.settle()
    check("Professions: with no profession on any stored craft the Crafted section is left out", not P.visible(p.crafted.head) and not P.visible(p.crafted.tbl.frame))
    -- a profession only a craft names: listed, with no number standing in for its skill
    db.crafts[1].prof = "Alchemy"
    V.renderProf(); M.settle()
    local alch
    for _, row in ipairs(p.profRows) do if P.visible(row) and row.title.text == "Alchemy" then alch = row end end
    check("Professions: a profession whose skill is not read yet has no number and no dash", alch ~= nil and alch.count.text == "" and alch.meta.text == "", alch and alch.count.text)
    db.crafts = {}
    V.renderProf(); M.settle()
    check("Professions: with nothing crafted the Crafted section is left out", not P.visible(p.crafted.head) and not P.visible(p.crafted.tbl.frame))
  end
  check("Character: no error while building or rendering", (function() for _, e in ipairs(M.errors) do if tostring(e):find("Progress") then return false end end return #UI.paneErrors() == 0 end)(), table.concat(UI.paneErrors(), " | "))
end
