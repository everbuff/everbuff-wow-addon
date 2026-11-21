-- Pane tests: Dungeons > Runs, the run page and By dungeon (docs/UX_OVERHAUL.md 4.5 to 4.7, 5 step 6), on the runs of
-- 4.0 (tests/dungeon_fixture.lua) at 900x580 and 1600x1000:
--   every Bosses cell holds "/"; every delta is a UI.fmtDelta word; one primary, none while a run is in progress;
--   the filter clears with its glyph; every run page section is there, with its empty sentence when it has nothing;
--   Back restores the list's scroll offset and its selection; "of N" only with a limit set.
-- Then the layout (nothing cut, nothing past the right edge), the 1 s ticker of a run in progress, one fight one
-- reading (a foe-less pull inside a run is Trash), a boss row that opens its fight, and By dungeon.
return function(P)
  local check, eq, M, ns, T = P.check, P.eq, P.M, P.ns, P.T
  local UI, R = ns.UI, ns.Runs
  local FX = dofile("tests/dungeon_fixture.lua")
  local function strip(s) return (tostring(s or ""):gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%s+", ""):gsub("%s+$", "")) end
  local function isDelta(s)
    s = strip(s)
    return s:find("^%d[%dhms ]* faster$") ~= nil or s:find("^%d[%dhms ]* slower$") ~= nil or s == "same as best" or s == "best" or s == "first run"
  end
  local function shown(tbl) local out = {}; for i = 1, tbl.shownN or 0 do local r = tbl.rows[i]; if not (r.item and r.item.ebSection) then out[#out + 1] = r end end return out end
  local function pane() return P.open("dungeons", "runs", P.size[1], P.size[2], "normal") end
  -- every install is undone in reverse order (each puts back what was there before it)
  local undos = {}
  local function install(state) local u, fx = FX.install(ns, M, state); undos[#undos + 1] = u; return fx end
  local function unwind() for i = #undos, 1, -1 do undos[i]() end; undos = {} end
  local function open(state)
    local fx = install(state)
    local lv = T.dungeonList(); M.settle()
    return lv, fx
  end
  local wb
  -- every text of a frame tree that is cut or ends past `right`
  local function audit(root, right)
    local cut, past = {}, {}
    for _, f in ipairs(P.descendants(root)) do
      if type(f.text) == "string" and f.text ~= "" and P.visible(f) and f.IsTruncated then
        local b = P.box(f)
        if f:IsTruncated() then cut[#cut + 1] = strip(f.text):sub(1, 30) end
        if b and b.l + math.min(b.w, UI.TextWidth(f.ebRole or "BODY", strip(f.text))) > right + 1 then past[#past + 1] = strip(f.text):sub(1, 30) end
      end
    end
    return cut, past
  end

  for _, size in ipairs({ { 900, 580 }, { 1600, 1000 } }) do
    P.size = size
    local tag = ("Dungeons %dx%d"):format(size[1], size[2])
    local content = pane()
    local dv = T.dungeonDetail(); if dv:IsShown() then dv.d.Close() end
    wb = P.box(_G.EverbuffFrame)

    -- ── Runs: the summary line, the hero, the table ──
    local lv, fx = open("")
    -- the story: the session holds the runs it played, their XP and their kills (Now, Activity and Runs agree)
    do
      local ses = ns.Recorder.current()
      local st = tonumber(ses and ses.startedEpoch) or 0
      local runXP, nRuns = 0, 0
      for _, r in ipairs(ns.char().dungeonRuns or {}) do
        if (tonumber(r.t) or 0) >= st then nRuns = nRuns + 1; runXP = runXP + (tonumber(type(r.xp) == "table" and r.xp.gain) or 0) end
      end
      local kills = 0
      for _, e in ipairs(ns.DB.story.events) do if e.kind == "KILL" and e.zone == "Ragefire Chasm" and e.s == ns.DB.active then kills = kills + 1 end end
      check(tag .. ": story: the session's XP is at least its runs' XP, its run count is theirs, the run's kills are its events",
        ses and (tonumber(ses.xp) or 0) >= runXP and tonumber(ses.dungeons) == nRuns and nRuns == 1 and kills >= 2,
        ses and ("%s/%s %s/%s %d"):format(tostring(ses.xp), runXP, tostring(ses.dungeons), nRuns, kills))
    end
    local rows = shown(lv.tbl)
    check(tag .. ": the three runs are rows under day sections", #rows == 3 and lv.section.shown ~= false, #rows)
    local slash = true
    for _, r in ipairs(rows) do if not tostring(r.c.boss.text):find("/", 1, true) then slash = false end end
    check(tag .. ": every Bosses cell holds the total (\"2/4\")", slash, rows[1] and rows[1].c.boss.text)
    local deltas = true
    for _, r in ipairs(rows) do if r.c.vs.text ~= "-" and not isDelta(r.c.vs.text) then deltas = false end end
    check(tag .. ": every Vs best cell is a fmtDelta word", deltas, rows[1] and rows[1].c.vs.text)
    local byName = {}
    for _, r in ipairs(rows) do byName[r.run.id] = r end
    eq(tag .. ": the Ragefire Chasm row: first run, 2/4, one death (Tessa's)", byName[fx.rfc.id] and (byName[fx.rfc.id].c.vs.text .. " " .. byName[fx.rfc.id].c.boss.text .. " " .. byName[fx.rfc.id].c.death.text), "first run 2/4 1")
    eq(tag .. ": the best Wailing Caverns run carries BEST", byName[fx.wc2.id] and byName[fx.wc2.id].ebBadge and byName[fx.wc2.id].ebBadge.shown ~= false and byName[fx.wc2.id].ebBadge.ebText, "BEST")
    eq(tag .. ": the older one reads how much slower it was", byName[fx.wc1.id] and strip(byName[fx.wc1.id].c.vs.text), "42s slower")
    local sum = lv.summary.Text()
    check(tag .. ": the summary reads the instances this hour and the lockout", sum:find("1 instance this hour", 1, true) == 1
      and sum:find("Ragefire Chasm: 2 of 4 bosses down, resets in 1h 59m", 1, true) ~= nil, sum)
    check(tag .. ": no \"of N\" without a limit", sum:find(" of 5", 1, true) == nil, sum)
    eq(tag .. ": the hero is the newest run", lv.heroRun and lv.heroRun.id, fx.rfc.id)
    eq(tag .. ": its verdict: the result of a first run", lv.heroVerdict, "2 of 4 bosses in 12m 30s")
    check(tag .. ": a first run's META says first run, with no FIRST RUN badge", lv.hero.meta1 and tostring(lv.hero.meta1.text or ""):find("first run", 1, true) ~= nil, lv.hero.meta1 and lv.hero.meta1.text)
    eq(tag .. ": one primary on the list (the hero's Open run)", UI.CountPrimaries(content), 1)
    local cut, past = audit(lv, wb.l + wb.w)
    if os.getenv("EB_DEBUG") then for k, c in pairs(lv.tbl.cols) do print("COL", tag, k, c.x, c.w) end end
    check(tag .. ": nothing on the list is cut or past the window", #cut == 0 and #past == 0, table.concat(cut, " | ") .. " || " .. table.concat(past, " | "))
    local cols = lv.tbl.cols
    check(tag .. ": Coin looted and XP per hour only at WIDE", (size[1] >= 1250) == (cols.coin ~= nil and (cols.coin.w or 0) > 0), cols.coin and cols.coin.w)

    -- ── the filter: a dungeon picked, the clear glyph back to all ──
    lv.filter:GetScript("OnClick")(lv.filter)
    local items = lv.filter.menu.items
    eq(tag .. ": the filter lists All dungeons, the two dungeons, then raids greyed", #items == 4 and items[4][4] == true and items[4][2], "Raids \194\183 coming soon")
    lv.filter.menu.rows[3]:GetScript("OnClick")(lv.filter.menu.rows[3]); M.settle()
    check(tag .. ": a dungeon picked keeps its runs, the button in its active style with the clear glyph", #lv.shown == 2 and lv.filter.ebActive == true and lv.filter.clear.shown ~= false
      and lv.filter.text:GetText() == "Wailing Caverns", lv.filter.text:GetText())
    eq(tag .. ": the hero follows the filter", lv.heroRun and lv.heroRun.id, fx.wc2.id)
    lv.filter.clear:GetScript("OnClick")(lv.filter.clear); M.settle()
    check(tag .. ": the clear glyph shows every run again", #lv.shown == 3 and lv.filter.ebActive == false and lv.filter.text:GetText() == "All dungeons" and lv.filter.clear.shown == false)
    lv.pickInst("Shadowfang Keep"); M.settle()
    check(tag .. ": a filter with no run says so, with a way back, and no hero", lv.tbl.state == "No run of Shadowfang Keep yet." and lv.hero.shown == false and UI.CountPrimaries(content) == 0, lv.tbl.state)
    lv.tbl.stateLink:GetScript("OnClick")(lv.tbl.stateLink); M.settle()
    check(tag .. ": Show all dungeons clears it", lv.st.inst == nil and #lv.shown == 3)

    -- ── the run page: the best run, every section, the cards ──
    T.openRun(byName[fx.wc2.id].run); M.settle()
    check(tag .. ": the run page opens over the list", dv:IsShown() and not lv:IsShown() and dv.run.id == fx.wc2.id)
    local missing = {}
    for _, k in ipairs(dv.SECTION_KEYS) do if dv.sections[k].shown == false then missing[#missing + 1] = k end end
    check(tag .. ": every section is on the page, in the spec's order", #missing == 0, table.concat(missing, ","))
    local order, lastY = true, -1
    for _, k in ipairs(dv.SECTION_KEYS) do local b = P.box(dv.sections[k]); if not b or b.t <= lastY then order = false end; lastY = b and b.t or lastY end
    check(tag .. ": the sections run Bosses, Loot, Deaths, XP, Party, Pace, Entered and left, All pulls, Edit", order)
    eq(tag .. ": VS YOUR BEST on the best run: how much it beat the best before it", dv.deltaText, "42s faster")
    eq(tag .. ": the cards are four, six at WIDE", #dv.cards, size[1] >= 1250 and 6 or 4)
    check(tag .. ": the party of five is named", dv.partyFS and strip(dv.partyFS.text):find("Tessa", 1, true) ~= nil and dv.metaText:find("party of 5", 1, true) ~= nil, dv.metaText)
    check(tag .. ": the Pace line is the best of the route", dv.paceLine and dv.paceLine:find("^Your best for these 6 bosses: 28m 41s") ~= nil and dv.paceLine:find("This run is your best.", 1, true) ~= nil, dv.paceLine)
    local bd = true
    for _, r in ipairs(shown(dv.tables.bosses)) do if r.c.vs.text ~= "-" and not isDelta(r.c.vs.text) then bd = false end end
    check(tag .. ": every delta of the bosses table is a fmtDelta word", bd)
    eq(tag .. ": no primary on the run page", UI.CountPrimaries(content), 0)
    cut, past = audit(dv, wb.l + wb.w)
    check(tag .. ": nothing on the run page is cut or past the window", #cut == 0 and #past == 0, table.concat(cut, " | ") .. " || " .. table.concat(past, " | "))
    local ctl = content.ebHostCtl
    check(tag .. ": Older and Newer walk the list: the best run has both", ctl.olderBtn.shown ~= false and not ctl.olderBtn.ebDisabled and not ctl.newerBtn.ebDisabled)
    ctl.olderBtn:GetScript("OnClick")(ctl.olderBtn); M.settle()
    eq(tag .. ": Older shows the older run", dv.run.id, fx.wc1.id)
    check(tag .. ": the oldest run has no Older", ctl.olderBtn.ebDisabled == true)
    -- the TIME card's hover: the clocks, with the sentence of what they are
    dv.cards[1]:GetScript("OnEnter")(dv.cards[1])
    local tip = table.concat(_G.GameTooltip.lines or {}, " | ")
    check(tag .. ": the TIME card's hover lists the clocks", tip:find("Time inside the dungeon. Your clocks: entered", 1, true) ~= nil and tip:find("Inside 32m 30s", 1, true) ~= nil, tip)
    dv.cards[1]:GetScript("OnLeave")(dv.cards[1])

    -- ── the run with a death: Tessa's row, Trash for a foe-less pull, a boss row that opens its fight ──
    local fights = ns.DB.combat.fights
    fights[#fights + 1] = { uid = "fx-rfc-trash", session = ns.DB.active, startEpoch = fx.rfc.t + 200, duration = 20, outcome = "fled", foes = {}, zone = "Ragefire Chasm" }
    T.openRun(fx.rfc); M.settle()
    local d1 = dv.tables.deaths.rows[1]
    -- (Where is a place, never the killer again: the subzone, "at boss N" or "-")
    check(tag .. ": the death of a party member names her", d1 and d1.c.who.text == "Tessa" and d1.c.foe.text == "Taragaman the Hungerer"
      and d1.c.where.text ~= d1.c.foe.text and (d1.c.where.text == "-" or d1.c.where.text:find("^at boss %d") ~= nil), d1 and (d1.c.who.text .. " / " .. d1.c.where.text))
    local trash, fled = 0, 0
    -- (a pull with no foe; Jergosh and Bazzalan, left up on the way out, are flights with a foe)
    for _, r in ipairs(shown(dv.tables.pulls)) do
      local f = r.item and r.item.f
      if f and #(f.foes or {}) == 0 then if r.c.re.text == "Trash" then trash = trash + 1 elseif r.c.re.text == "Fled" then fled = fled + 1 end end
    end
    check(tag .. ": a pull with no foe inside the run reads Trash, never Fled", trash == 1 and fled == 0, trash .. "/" .. fled)
    local label, _, key = ns.FightResult(fights[#fights])
    check(tag .. ": the shared reading says the same", key == "trash" and label[1] == "Trash")
    eq(tag .. ": the boss card reads 2 of 4 with the misses", dv.cards[3].value.text, "2 of 4")
    local bossRow
    for _, r in ipairs(shown(dv.tables.bosses)) do if r.item.fight and r.item.fight.uid == "fx-rfc-1" then bossRow = r end end
    check(tag .. ": a boss whose fight is stored is a row that opens", bossRow ~= nil and not bossRow.item.ebNoOpen)
    if bossRow then
      bossRow:GetScript("OnClick")(bossRow, "LeftButton"); M.settle()
      check(tag .. ": clicking it opens that fight", T.fightDetail and T.fightDetail() and T.fightDetail().fight and T.fightDetail().fight.uid == "fx-rfc-1")
      if T.fightDetail() then T.fightDetail():Hide() end
      if T.fightsList and T.fightsList() then T.fightsList():Show() end   -- (as Back does: the next pane test starts on the list)
      pane(); fx = install(""); T.dungeonList()
    end

    -- ── a run with nothing in it: every section says so in its own sentence ──
    local bare = T.runRecord("Shadowfang Keep", GetServerTime() - 4000, 400, {})
    table.insert(ns.char().dungeonRuns, 1, bare)
    T.openRun(bare); M.settle()
    local want = { bosses = "No boss pulled in this run.", loot = "Nothing looted.", deaths = "Nobody died. Clean run.", xp = "No XP in this run.",
      party = "No fight of this run is stored, so the party is not known.", pace = "Kill the same bosses twice to see your pace.",
      pulls = "No fight of this run is stored any more. The desktop app saved them." }
    local bad = {}
    for k, s in pairs(want) do
      local fs = dv.empties[k]
      if not (fs and fs.shown ~= false and fs.text == s and dv.sections[k].shown ~= false) then bad[#bad + 1] = k .. "=" .. tostring(fs and fs.text) end
    end
    check(tag .. ": every empty section is there with its sentence", #bad == 0, table.concat(bad, " | "))
    check(tag .. ": the edit row is there with its buttons", dv.sections.edit.shown ~= false and #dv.actBtns() == 3)
    eq(tag .. ": a run with no boss reads 0/0 in the list", (function() for _, r in ipairs(shown(T.dungeonList().tbl)) do if r.run.id == bare.id then return r.c.boss.text end end end)(), "0/0")
    -- Back from the run page: the list's scroll offset and the selection come back
    for i = 1, 14 do table.insert(ns.char().dungeonRuns, 1, T.runRecord("The Stockade", GetServerTime() - 90000 - i * 3600, 600, {})) end
    R.statsRebuild(ns.char())
    if dv:IsShown() then dv.d.Close() end
    lv = T.dungeonList(); M.settle()
    lv.sf:ScrollTo(120); M.settle()
    local y0 = lv.sf.ebScroll
    local target
    for _, r in ipairs(shown(lv.tbl)) do if r.run.name == "The Stockade" then target = r end end
    target:GetScript("OnClick")(target, "LeftButton"); M.settle()
    check(tag .. ": a row's click opens its run", dv:IsShown() and dv.run.id == target.run.id)
    ctl.backBtn:GetScript("OnClick")(ctl.backBtn); M.settle()
    check(tag .. ": Back shows the list at the same scroll offset", lv:IsShown() and not dv:IsShown() and y0 > 0 and lv.sf.ebScroll == y0, ("%s %s"):format(tostring(y0), tostring(lv.sf.ebScroll)))
    check(tag .. ": with the run it came from selected", lv.tbl.selected and lv.tbl.selected.id == target.run.id)
    unwind()

    -- ── the limit: "of N" with it, the warn and bad states ──
    lv = open("")
    ns.DB.settings.instanceLimit = 5
    lv = T.dungeonList(); M.settle()
    sum = lv.summary.Text()
    check(tag .. ": a limit of 5 with 1 used reads 4 of 5 left, no dot", sum:find("4 of 5 instances left this hour", 1, true) == 1, sum)
    lv = open("limit4")
    sum = lv.summary.Text()
    check(tag .. ": with 4 of 5 used: 1 left, when the next is free, the warn dot", sum:find("1 instance left this hour, next free in ", 1, true) ~= nil
      and lv.summary.segs[1].dot == "warn", sum)
    lv = open("limit5")
    sum = lv.summary.Text()
    check(tag .. ": with 5 of 5 used: none left, the bad dot", sum:find("No instances left this hour, next free in ", 1, true) ~= nil and lv.summary.segs[1].dot == "bad", sum)
    unwind()

    -- ── a run in progress: no primary, the hero follows it, the page follows it every second ──
    lv, fx = open("live")
    eq(tag .. ": the run in progress is the hero", lv.heroRun and lv.heroRun.inProgress, true)
    check(tag .. ": its hero opens the run with a ghost Open run (A10)", lv.hero.button and lv.hero.button.shown ~= false and lv.hero.button.text.text == "Open run" and lv.hero.button.ebStyle == "ghost")
    eq(tag .. ": no primary while a run is in progress", UI.CountPrimaries(content), 0)
    local liveRow
    for _, r in ipairs(shown(lv.tbl)) do if r.run.inProgress then liveRow = r end end
    check(tag .. ": its row carries the short LIVE marker", liveRow and liveRow.ebBadge and liveRow.ebBadge.ebText == "LIVE" and liveRow.c.boss.text:find("/", 1, true) ~= nil)
    check(tag .. ": the live row keeps its whole dungeon name next to the marker", liveRow and liveRow.c.name.IsTruncated and liveRow.c.name:IsTruncated() == false, liveRow and liveRow.c.name.text)
    eq(tag .. ": the live row counts against the dungeon's 4 bosses, not its kills so far", liveRow and liveRow.c.boss.text, "1/4")
    check(tag .. ": the live hero says 1 of 4 bosses", lv.hero and tostring(lv.hero.meta1.text or ""):find("1 of 4 bosses", 1, true) ~= nil, lv.hero.meta1.text)
    -- one kill count on every surface of the live run: the summary's lockout counts the run's kills too
    local lsum = lv.summary.Text()
    check(tag .. ": the live summary's lockout reads the run's 1 of 4, with no \"(about)\"", lsum:find("Ragefire Chasm: 1 of 4", 1, true) ~= nil and lsum:find("(about)", 1, true) == nil, lsum)
    T.openRun(liveRow.run); M.settle()
    check(tag .. ": its page shows End run now", (function() for _, b in ipairs(dv.actBtns()) do if b.key == "end" and b.shown ~= false then return true end end end)())
    -- one item list on the page: the LOOT section counts the rows it lists (drops only: no quest reward, no mail), and
    -- the LOOT card (WIDE) says the same; the BOSSES card counts against the dungeon's 4 bosses
    local lootMeta = dv.sections.loot.meta.shown ~= false and dv.sections.loot.meta.text or ""
    local nLoot = #(dv.lootItems or {})
    check(tag .. ": the live run's LOOT section lists no quest reward or mail and counts what it lists", (function()
      for _, it in ipairs(dv.lootItems or {}) do local src = tostring(it.row.src or ""); if src:find("^Quest") or src:find("^Mail") then return false end end
      return nLoot == 0 and lootMeta == "" or lootMeta == UI.plural(nLoot, "item")
    end)(), lootMeta)
    if dv.cards[6] then eq(tag .. ": the COIN LOOTED card counts the same items", dv.cards[6].meta.text, nLoot > 0 and UI.plural(nLoot, "item") or "nothing yet") end
    eq(tag .. ": the live BOSSES card reads 1 of 4", dv.cards[3].value.text, "1 of 4")
    if dv.empties.deaths then
      local c = dv.empties.deaths._color or {}
      check(tag .. ": an inline empty sentence is fgMuted, never good", math.abs((c[1] or 0) - UI.C.fgMuted[1]) < 0.01 and math.abs((c[2] or 0) - UI.C.fgMuted[2]) < 0.01)
    end
    M.tick()
    local renders = dv.renders
    M.epoch = M.epoch + 5
    M.tick()
    check(tag .. ": the ticker moves the clocks; a second in which only they moved lays nothing out again", dv.timeLine:find("^Inside 12m 45s") ~= nil and dv.renders == renders
      and dv.cards[1].value.text == "12m 45s", dv.timeLine)
    -- with the window closed the ticker does nothing
    local calls, realRefresh = 0, dv.refresh
    dv.refresh = function() calls = calls + 1; return realRefresh() end
    _G.EverbuffFrame:Hide(); M.epoch = M.epoch + 5; M.tick()
    check(tag .. ": with the window closed the ticker reads nothing", calls == 0)
    _G.EverbuffFrame:Show(); M.tick()
    dv.refresh = realRefresh
    -- the run closes while its page is open: the page becomes the closed run's
    local rec = ns.char().dungeonRun
    R.close(ns.char(), rec, "left", GetServerTime())
    M.tick()
    check(tag .. ": a run that closed while its page was open reads as ended", dv:IsShown() and dv.run.inProgress == false and dv.run.id == rec.id
      and dv.metaText:find(" to %d%d:%d%d") ~= nil and dv.metaText:find("so far", 1, true) == nil, dv.metaText)
    dv.d.Close()
    unwind()

    -- ── By dungeon ──
    unwind()
    P.open("dungeons", "bydungeon", size[1], size[2], "normal")   -- (a new copy of the suite's data: the runs go on it after)
    install("")
    local by = T.dungeonBy(); M.settle()
    eq(tag .. ": By dungeon lists the two dungeons", #by.dshown, 2)
    eq(tag .. ": sorted by XP per hour below the level cap", by.dtbl.sortKey, "xp")
    local wcRow
    for _, r in ipairs(shown(by.dtbl)) do if r.drow.name == "Wailing Caverns" then wcRow = r end end
    check(tag .. ": the Wailing Caverns row: two runs, the best, your level", wcRow and wcRow.c.n.text == "2" and wcRow.c.best.text == "28m 41s" and wcRow.c.lvl.text == "17", wcRow and wcRow.c.best.text)
    -- (A15: one lockout wording at every size; at 900 the "Best XP per hour" segment is the one that gives way)
    if UI.G.isWide(UI.G.winW()) then check(tag .. ": the summary names the dungeon that pays best", by.summary.Text():find("Best XP per hour: ", 1, true) ~= nil, by.summary.Text())
    else check(tag .. ": at 900 the summary keeps the lockout whole and drops the pay segment", by.summary.Text():find("Best XP per hour", 1, true) == nil and by.summary.Text():find("resets in", 1, true) ~= nil, by.summary.Text()) end
    cut, past = audit(by, wb.l + wb.w)
    check(tag .. ": nothing on By dungeon is cut or past the window", #cut == 0 and #past == 0, table.concat(cut, " | ") .. " || " .. table.concat(past, " | "))
    wcRow:GetScript("OnClick")(wcRow, "LeftButton"); M.settle()
    lv = T.dungeonList()
    check(tag .. ": a click opens Runs on that dungeon", lv:IsVisible() and lv.st.inst == "Wailing Caverns" and #lv.shown == 2)
    lv.pickInst(nil)
    -- (empty: the big empty state, no hero, no table)
    install("empty")
    lv = T.dungeonList(); M.settle()
    check(tag .. ": no runs: the big empty state, no hero and no table", lv.empty.shown ~= false and lv.hero.shown == false and lv.tbl.frame.shown == false and UI.CountPrimaries(content) == 0)
    unwind()
    T.dungeonList()
  end
  P.size = nil

  -- ── the fixture's story holds together (A7, B1, B3, B4, B23) ──
  for _, state in ipairs({ "", "live" }) do
    local tag = "fixture " .. (state == "" and "normal" or state)
    P.open("dungeons", "runs", 900, 580, "normal")
    local fx = install(state)
    local runs = ns.DungeonRuns()
    -- every fight that began inside a run's window carries the run's zone: the open world waits until the run is over
    local bad = {}
    for _, f in ipairs(ns.mine(ns.Fights.list())) do
      for _, r in ipairs(runs) do
        if ns.Runs.inRun(r.rec, f.startEpoch) and tostring(f.zone or ""):lower() ~= tostring(r.name):lower() then bad[#bad + 1] = ("%s at %s in %s"):format(tostring(f.foes and f.foes[1]), UI.fmtClock(f.startEpoch or 0), tostring(f.zone)) end
      end
    end
    check(tag .. ": every fight inside a run's window is in the run's instance (A7)", #bad == 0, table.concat(bad, "; "))
    -- a boss total equals the kills only when every encounter the run met was killed
    local tb = {}
    for _, r in ipairs(runs) do
      local allKilled = true
      for _, b in ipairs(r.bosses or {}) do if not b.kill then allKilled = false end end
      if ns.Dungeons.D.totalOf(r) == r.bossesDown and not allKilled then tb[#tb + 1] = r.name .. " " .. ns.Dungeons.D.bossCount(r) end
    end
    check(tag .. ": a boss total is never the kills while an encounter was left up (B1)", #tb == 0, table.concat(tb, "; "))
    for _, r in ipairs(runs) do
      if r.name == "Wailing Caverns" then eq(tag .. ": Wailing Caverns reads 6 of 8", ns.Dungeons.D.bossCount(r), "6 of 8") end
    end
    -- the run page and the Fights list count the same fights (one store, B23)
    if fx.rfc then
      local rv
      for _, r in ipairs(runs) do if r.id == fx.rfc.id then rv = r end end
      local fl = T.fightsList(); fl:Show(); fl.setFilter("all"); ns.UI.Open("Home", "fights"); M.settle()
      local under, inRun = 0, false
      for i = 1, fl.tbl.shownN do
        local row = fl.tbl.rows[i]
        if row.item and row.item.ebSection then inRun = row.item.ebRun and tostring(row.item.ebSection):find("Ragefire Chasm \194\183 " .. UI.fmtClock(fx.rfc.t), 1, true) ~= nil
        elseif inRun and row.fight then under = under + 1 end
      end
      check(tag .. ": the Fights list groups as many fights under the run as the run page lists (B23)", rv and under == #rv.fights and #rv.fights == 10, ("%d vs %s"):format(under, rv and #rv.fights or "?"))
    end
    -- a run in progress keeps the earlier run of the hour (B2)
    if state == "live" then
      local n = 0
      for _, r in ipairs(runs) do if r.name == "Ragefire Chasm" then n = n + 1 end end
      eq(tag .. ": the live state keeps the 21:39 run beside the one in progress (B2)", n, 2)
    end
    unwind()
  end
end
