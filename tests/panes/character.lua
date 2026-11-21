-- Pane tests: Character (docs/UX_OVERHAUL.md 4.10, 4.11). Leveling (Quests folded in), Reputation and Professions
-- (Crafting folded in). At 900x580 and 1600x1000, normal and long data: the page column at BOX_L, every table with
-- header x == cell x and numbers right-aligned, Coords only at WIDE, no text past the pane; then what each page adds:
-- the hero's pace comparison, the cards, the quest names the game did not give, the faction page, the profession
-- rows with their bar and training line, the crafted table and every empty sentence.
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
          for _, r in ipairs(rows) do if not (type(r.t) == "number" and r.t > 0) then dated = false end end
          check("Leveling " .. sz .. ": every listed level has a recorded moment, and the rest are counted", dated and #rows + missing == UnitLevel("player") - 1 and P.visible(v.levels.head) == (#rows > 0)
            and P.visible(v.levelNote) == (missing > 0), #rows .. "+" .. missing)
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
        check("Reputation " .. sz .. ": columns, Last gain only at WIDE", colsOf(r.tbl) == (wide and "name,standing,prog,ses,last" or "name,standing,prog,ses"), colsOf(r.tbl))
        tables("Reputation " .. sz, c, { r.tbl })
        spill("Reputation " .. sz, c)
        local bars = {}
        for i = 1, r.tbl.shownN do
          local row = r.tbl.rows[i]
          if row.bar and P.visible(row.bar) then
            local bb, cw = P.box(row.bar), r.tbl.cols.prog
            local pb = P.box(row.c.prog)
            if not near(bb.l, P.box(r.tbl.frame).l + cw.x) or bb.w ~= 120 then bars[#bars + 1] = "bar " .. i end
            if pb.l + pb.w - P.G.naturalWidth(row.c.prog) < bb.l + bb.w + S.S2 - 0.5 then bars[#bars + 1] = "text over bar " .. i end
          end
        end
        check("Reputation " .. sz .. ": the 120 px bar at the Progress column, its numbers right of it", #bars == 0, table.concat(bars, ","))
      end
      -- Professions
      c = P.open("character", "professions", size[1], size[2], data)
      local p = V.prof
      check("Professions " .. sz .. ": opened", c ~= nil and p ~= nil)
      if p then
        check("Professions " .. sz .. ": CRAFTED columns", colsOf(p.crafted.tbl) == "when,item,prof,qty", colsOf(p.crafted.tbl))
        tables("Professions " .. sz, c, { p.crafted.tbl, p.recipes.tbl })
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

  -- ── empty states ──
  do
    local function empty()
      local db = ns.char()
      ns.DB.story.events, ns.DB.story.rep, db.playedAtLevel, db.reputation, db.professions, db.crafts, db.recipes = {}, {}, nil, nil, nil, nil, nil
    end
    local keepF = { _G.GetNumFactions, _G.C_Reputation }
    _G.GetNumFactions, _G.C_Reputation = nil, nil
    P.open("character", "leveling", 900, 580); empty(); V.renderLeveling(); M.settle()
    local v = V.leveling
    check("Leveling empty: no Levels table and no Quests table stand empty, and no sentence takes their place", not P.visible(v.levels.head) and not P.visible(v.levels.tbl.frame)
      and not P.visible(v.quests.head) and not P.visible(v.quests.tbl.frame))
    P.open("character", "reputation", 900, 580); empty(); V.renderRep(); M.settle()
    check("Reputation empty: the inline sentence", V.rep.tbl.state == "Turn in quests or defeat a faction's enemies and your gains show here. Factions you know already are listed with their standing.")
    check("Reputation empty: the summary says 0 factions known", V.rep.summary:Text():find("0 factions known", 1, true) ~= nil, V.rep.summary:Text())
    P.open("character", "professions", 900, 580); empty(); V.renderProf(); M.settle()
    local p = V.prof
    check("Professions empty: the inline sentence", P.visible(p.empty) and p.empty.text.text == "Learn a profession at any trainer and its skill shows here.", p.empty.text and p.empty.text.text)
    check("Professions empty: Crafted says it", p.crafted.tbl.state == "Craft something and it is listed here.")
    _G.GetNumFactions, _G.C_Reputation = keepF[1], keepF[2]
  end

  -- ── Reputation: the faction page ──
  do
    P.open("character", "reputation", 900, 580)
    local db = ns.char()
    db.reputation = { ["Stormwind"] = { standing = 5, label = "Friendly" }, ["Defias Brotherhood"] = { standing = 2, label = "Hostile" } }
    ns.DB.story.rep = ns.DB.story.rep or {}
    local now = (GetServerTime and GetServerTime()) or time()
    table.insert(ns.DB.story.rep, { s = ns.DB.active, t = now, faction = "Stormwind", amount = 250, src = "Quest: The Fargodeep Mine" })
    local r = V.rep
    V.renderRep(); M.settle()
    local sw, hostile
    for i = 1, r.tbl.shownN do
      local row = r.tbl.rows[i]
      if row.item.name == "Stormwind" then sw = row elseif row.item.name == "Defias Brotherhood" then hostile = row end
    end
    check("Reputation: Hostile reads bad with the dot", hostile and hostile.c.standing.text:find("Hostile", 1, true) ~= nil and near(hostile.c.standing._color[1], UI.C.bad[1], 0.01))
    check("Reputation: This session shows the gain", sw and sw.c.ses.text == "+250", sw and sw.c.ses.text)
    click(sw)
    check("Reputation: a row opens the faction page", r.detail.IsOpen() and V.FACTION.title.text == "Stormwind")
    check("Reputation: the faction page lists how you earned it", V.FACTION.hist[1] and V.FACTION.hist[1].source == "Quest: The Fargodeep Mine" and V.FACTION.tbl.rows[1].c.amount.text == "+250")
    r.detail.Close(); M.settle()
    check("Reputation: Back returns to the list", not r.detail.IsOpen() and P.visible(r.list))
  end

  -- ── Professions: rows, training line, crafted ──
  do
    P.open("character", "professions", 900, 580)
    local db = ns.char()
    db.professions = { Tailoring = { rank = 118, max = 150 }, Mining = { rank = 30, max = 75 } }
    db.crafts = { { t = 100, item = "Bolt of Linen Cloth", count = 4, prof = "Tailoring" }, { t = 200, item = "Rough Arrow", count = 200 } }
    db.recipes = { { t = 150, name = "|cffffffff|Hitem:2568|h[Brown Linen Vest]|h|r", prof = "Tailoring" } }
    V.renderProf(); M.settle()
    local p = V.prof
    local t = p.profRows[1]
    check("Professions: the highest skill first, with its rank name and recipes", t.title.text == "Tailoring" and t.meta.text == "Journeyman \194\183 1 recipe learned", t.meta.text)
    check("Professions: the count reads rank / max", t.count.text == "118 / 150")
    check("Professions: the training line 10 under the threshold", t.train.text == "Expert training opens at 125")
    check("Professions: Mining has no training line at 30 of 75", p.profRows[2].train.text == "")
    check("Professions: CRAFTED counts crafts and items", p.crafted.head.meta.text == "2 crafts \194\183 204 items", p.crafted.head.meta.text)
    local other
    for i = 1, p.crafted.tbl.shownN do local row = p.crafted.tbl.rows[i]; if row.item.item == "Rough Arrow" then other = row end end
    check("Professions: a craft with no profession window reads Other, muted", other and other.c.prof.text == "Other" and near(other.c.prof._color[1], UI.C.fgMuted[1], 0.01))
    -- (under its day row, as Crafted)
    check("Professions: RECIPES LEARNED lists the recipe by its plain name (no link, no brackets), under a day row", p.recipes.tbl.shownN == 2 and p.recipes.tbl.rows[1].item.ebSection ~= nil
      and p.recipes.tbl.rows[2].c.name.text == "Brown Linen Vest" and p.recipes.tbl.rows[2].c.when.text:find("^%d%d:%d%d$") ~= nil)
  end
  check("Character: no error while building or rendering", (function() for _, e in ipairs(M.errors) do if tostring(e):find("Progress") then return false end end return #UI.paneErrors() == 0 end)(), table.concat(UI.paneErrors(), " | "))
end
