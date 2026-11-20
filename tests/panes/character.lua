-- Pane tests: Character (docs/UX_OVERHAUL.md 4.10, 4.11). Leveling (Quests folded in), Reputation and Professions
-- (Crafting folded in). At 900x580 and 1600x1000, normal and long data: the page column at BOX_L, every table with
-- header x == cell x and numbers right-aligned, Coords only at WIDE, no text past the pane; then what each page adds:
-- the hero's pace comparison, the cards, the quest names the game did not give, the faction page, the profession
-- rows with their bar and training line, the crafted table and every empty sentence.
return function(P)
  local check, M, ns = P.check, P.M, P.ns
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
                if not near(P.box(cell).l, fb.l + cw.x) then bad[#bad + 1] = col.key .. i end
                if numeric and cell._justify ~= "RIGHT" then bad[#bad + 1] = col.key .. i .. " not right-aligned" end
                if col.kind and col.kind ~= "text" and cell:IsTruncated() then bad[#bad + 1] = col.key .. i .. " cut" end
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
        check("Leveling " .. sz .. ": hero, four cards, LEVELS and QUESTS TURNED IN, top to bottom", P.box(v.hero).t < P.box(v.cards).t and P.box(v.cards).t < P.box(v.levels.head).t and P.box(v.levels.head).t < P.box(v.quests.head).t)
        check("Leveling " .. sz .. ": the hero title is the level", (v.hero.title and v.hero.title.text or ""):find("^Level %d+") ~= nil, v.hero.title and v.hero.title.text)
        check("Leveling " .. sz .. ": LEVELS columns", colsOf(v.levels.tbl) == "level,reached,at,played,vs", colsOf(v.levels.tbl))
        check("Leveling " .. sz .. ": QUESTS columns, Coords only at WIDE", colsOf(v.quests.tbl) == (wide and "when,name,place,gold,coords" or "when,name,place,gold"), colsOf(v.quests.tbl))
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
            if not near(P.box(row.bar).l - rb.l, V.BAR_X) or P.box(row.bar).w ~= V.BAR_W then bad[#bad + 1] = "bar " .. i end
            local cbx = P.box(row.count)
            if not near(cbx.l + cbx.w, rb.l + rb.w - S.S3) or row.count._justify ~= "RIGHT" then bad[#bad + 1] = "count " .. i end
            if row.train.text ~= "" and not near(P.box(row.train).l - rb.l, V.BAR_X) then bad[#bad + 1] = "training " .. i end
            if P.box(row.meta).l + P.G.naturalWidth(row.meta) > P.box(row.bar).l + 0.5 and not row.meta:IsTruncated() then bad[#bad + 1] = "meta runs into the bar " .. i end
          end
        end
        check("Professions " .. sz .. ": each row has its bar at x 320 (160 wide), the count at w-12, the training line under the bar", #bad == 0, table.concat(bad, ","))
      end
    end
  end
  UI.SetWindowSize(900, 580)

  -- (P.open puts a fresh copy of the data in place, so each block opens its pane first, then changes the data and
  -- renders again; nothing needs restoring)
  -- ── Leveling: the hero's comparison, the cards, the quest names ──
  do
    P.open("character", "leveling", 900, 580)
    local v = V.leveling
    local db = ns.char()
    local now = (GetServerTime and GetServerTime()) or time()
    local lvl = UnitLevel("player")
    db.playedAtLevel = { [lvl - 1] = 10000, [lvl] = 13600 }          -- 1h 0m at the level before
    db.played = { total = 13600 + 1800, level = 1800, atEpoch = now }  -- 30m at this level so far
    local Pace = ns.Pace
    local realCompute, realRemaining = Pace.compute, Pace.remaining
    Pace.compute = function() return { rate = 3600, active = 30 } end
    Pace.remaining = function() return 1200 end                         -- 20m left: 50m in all, 10m faster
    V.renderLeveling(); M.settle()
    check("Leveling: On pace to be 10m faster than the level before (good)", v.verdict == ("On pace to be 10m faster than level %d"):format(lvl - 1), v.verdict)
    Pace.remaining = function() return 3600 end                         -- 1h 30m in all, 30m slower
    V.renderLeveling(); M.settle()
    check("Leveling: slower reads warn with its dot", v.verdict:find(("On pace to be 30m slower than level %d"):format(lvl - 1), 1, true) ~= nil and v.verdict:find("|T", 1, true) == 1, v.verdict)
    Pace.compute = function() return {} end
    Pace.remaining = function() return nil end
    V.renderLeveling(); M.settle()
    check("Leveling: before 10 active minutes it says the time at this level so far", v.verdict == ("30m at level %d so far"):format(lvl), v.verdict)
    check("Leveling: TIME AT LEVEL card", v.cards.cards[1].label.text == ("TIME AT LEVEL %d"):format(lvl) and v.cards.cards[1].value.text == "30m" and v.cards.cards[1].meta.text == "so far", v.cards.cards[1].value.text)
    check("Leveling: BEST LEVEL TIME card names the level", v.cards.cards[2].value.text == "1h 0m" and v.cards.cards[2].meta.text == ("level %d"):format(lvl - 1), v.cards.cards[2].value.text)
    db.xp = { cur = 10, max = 100, fromQuests = 630, fromKills = 370 }
    V.renderLeveling(); M.settle()
    check("Leveling: QUEST XP SHARE 63%, kills 37%", v.cards.cards[3].value.text == "63%" and v.cards.cards[3].meta.text:find("kills 37%", 1, true) == 1, v.cards.cards[3].value.text)
    local lv
    for _, r in ipairs(ns._test.buildLevels(lvl, now)) do if r.level == lvl - 1 then lv = r end end
    check("Leveling: the level before took 1h 0m, with the played time by then", lv and lv.at == 3600 and lv.playedBy == 10000, lv and tostring(lv.at))
    -- at max level
    local keepMax = _G.GetMaxPlayerLevel
    _G.GetMaxPlayerLevel = function() return lvl end
    V.renderLeveling(); M.settle()
    check("Leveling: at max level the hero says so and the cards change", v.hero.hero.text == ("Level %d \194\183 max level"):format(lvl) and v.cards.cards[1].label.text == "PLAYED" and v.cards.cards[2].label.text == "GOLD PER HOUR" and v.cards.cards[3].label.text == "QUESTS" and v.cards.cards[4].label.text == "DUNGEON RUNS", v.hero.hero.text)
    _G.GetMaxPlayerLevel = keepMax
    Pace.compute, Pace.remaining = realCompute, realRemaining
    -- a quest the game did not name
    local L = ns.DB.story.events
    L[#L + 1] = { s = ns.DB.active, kind = "QUESTDONE", t = now + 5, text = "Complete:  quest", zone = "Elwynn Forest" }
    V.renderLeveling(); M.settle()
    local row
    for i = 1, v.quests.tbl.shownN do local r = v.quests.tbl.rows[i]; if r.item.t == now + 5 then row = r end end
    check("Leveling: an unnamed quest reads muted, never the placeholder", row and row.c.name.text ~= "quest" and row.c.name._color and near(row.c.name._color[1], UI.C.fgMuted[1], 0.01), row and row.c.name.text)
    check("Leveling: the quests are grouped under day rows", v.quests.tbl.rows[1].item.ebSection ~= nil)
    check("Leveling: the section right counts the quests", v.quests.head.meta.text == UI.plural(#v.questRows, "quest"), v.quests.head.meta.text)
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
    check("Leveling empty: Levels says the first level-up is timed from now", v.levels.tbl.state == "Your first level-up is timed from now.", tostring(v.levels.tbl.state))
    check("Leveling empty: Quests says what will show", v.quests.tbl.state == "Turn in a quest and it shows here with its gold.")
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
    check("Professions: RECIPES LEARNED lists the recipe by its plain name (no link, no brackets)", p.recipes.tbl.shownN == 1 and p.recipes.tbl.rows[1].c.name.text == "Brown Linen Vest")
  end
  check("Character: no error while building or rendering", (function() for _, e in ipairs(M.errors) do if tostring(e):find("Progress") then return false end end return #UI.paneErrors() == 0 end)(), table.concat(UI.paneErrors(), " | "))
end
