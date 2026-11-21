-- Pane tests: Home > Now (docs/UX_OVERHAUL.md 4.1 and 5 step 5): the hero, the four THIS SESSION cards, NEXT and
-- WORTH A LOOK, the combat-log notice, the leveling pace (ns.Pace), the ranking and caps, and the geometry on the
-- window grid at 900x580 and 1600x1000.
return function(P)
  local check, eq, M, ns = P.check, P.eq, P.M, P.ns
  local UI = ns.UI
  local G, S, H = UI.G, UI.S, UI.H
  local Now, Pace = ns.Now, ns.Pace
  local function near(a, b, tol) return a and b and math.abs(a - b) <= (tol or 0.51) end
  local function win() return P.box(_G.EverbuffFrame) end
  local function wx(f) return P.box(f).l - win().l end
  local function wy(f) return P.box(f).t - win().t end
  local function shown(list) local n = 0; for _, r in ipairs(list) do if r:IsShown() then n = n + 1 end end return n end
  local function reopen() ns.UI.Open("Home", "now"); M.settle() end

  -- ── the pace: one function for the hero and the XP PER HOUR card ──
  do
    local st = Pace.state()
    local keep = { xpm = st.xpm, ev = st.ev, afk = st.afk, total = st.total, start = st.start }
    Pace.sync()
    local now = 1800000000
    st.start = now - 3600
    st.xpm, st.ev, st.afk, st.total = {}, {}, {}, 0
    local nm = math.floor(now / 60)
    -- 9 active minutes: no rate yet
    for m = nm - 8, nm do st.ev[m] = true; st.xpm[m] = 60 end
    local r9 = Pace.compute(now)
    check("Pace: no rate before 10 active minutes", r9.rate == nil and r9.active == 9, r9.active)
    -- 40 active minutes of 60 XP each, then 10 away minutes that do not count
    st.xpm, st.ev, st.afk = {}, {}, {}
    for m = nm - 49, nm - 10 do st.ev[m] = true; st.xpm[m] = 60 end
    for m = nm - 9, nm do st.afk[m] = true; st.ev[m] = true; st.xpm[m] = 500 end
    local r = Pace.compute(now)
    check("Pace: the last 30 active minutes, away minutes left out", r.used == 30 and r.active == 40 and near(r.rate, 3600), ("%s %s %s"):format(r.used, r.active, tostring(r.rate)))
    -- a minute is active while an event came within the last 5 minutes
    st.xpm, st.ev, st.afk = {}, {}, {}
    st.ev[nm - 20] = true
    eq("Pace: one event keeps 5 minutes active", Pace.compute(now).active, 5)
    -- the estimate: what is left over the shown rate, within a minute
    local secs = Pace.remaining(9100, 11800, 3860)
    local shownMin = math.floor(secs / 60 + 0.5)
    check("Pace: remaining / shown rate equals the shown estimate within 1 minute", math.abs(shownMin - (11800 - 9100) / 3860 * 60) <= 1, shownMin)
    eq("Pace: the fixture's 42m to level 19", UI.fmtDur(secs, { minutes = true }), "42m")
    check("Pace: no estimate without a rate or at the level's end", Pace.remaining(100, 200, nil) == nil and Pace.remaining(200, 200, 3000) == nil)
    local n, x = Pace.xpLine("Bristleback Quilboar dies, you gain 45 experience.")
    check("Pace: the kill line names the enemy and its XP", n == "Bristleback Quilboar" and x == 45, tostring(n))
    -- a level up between two readings counts what was left of the old level plus the new XP
    st.xpm, st.ev, st.afk, st.total = {}, {}, {}, 0
    st.last = { 900, 1000, 12 }
    local kx, km, kl = M.xp, M.xpmax, M.level
    M.xp, M.xpmax = 30, 1200
    Pace.onXP(now)
    eq("Pace: a level up between readings counts both sides", st.total, 130)
    M.xp, M.xpmax = kx, km
    st.xpm, st.ev, st.afk, st.total, st.start = keep.xpm, keep.ev, keep.afk, keep.total, keep.start
    st.last = nil; Pace.baseline()
  end

  -- ── the page on the fixture, both sizes, both data sets ──
  for _, size in ipairs({ { 900, 580 }, { 1600, 1000 } }) do
    for _, data in ipairs({ "normal", "long" }) do
      local tag = ("Now %dx%d %s"):format(size[1], size[2], data)
      local c = P.open("home", "now", size[1], size[2], data)
      check(tag .. ": the pane opened", c ~= nil and c.hero ~= nil)
      if c then
        local W = size[1]
        local mainW = G.mainW(W)
        eq(tag .. ": the hero is the first block, at CONTENT_TOP", wy(c.hero), G.CONTENT_TOP)
        eq(tag .. ": the hero box starts at BOX_L", wx(c.hero), G.BOX_L)
        eq(tag .. ": the hero is as wide as the main column", P.box(c.hero).w, mainW)
        eq(tag .. ": the hero is 104 high", P.box(c.hero).h, H.HERO)
        eq(tag .. ": the THIS SESSION header at 220, S5 under the hero (A11)", wy(c.sesHead), 220)
        eq(tag .. ": its label at TEXT_L", wx(c.sesHead.label), G.TEXT_L)
        eq(tag .. ": the cards at 244", wy(c.cards), 244)
        local cw = math.floor((mainW - 3 * S.S3) / 4)
        eq(tag .. ": four cards of (main - 36) / 4", P.box(c.cards.cards[1]).w, cw)
        -- (NEXT only when something needs attention, WORTH A LOOK only with rows: the first of them shown is at 348)
        local firstBlock = (c.nextHead:IsShown() and c.nextHead) or (c.lookHead:IsShown() and c.lookHead) or nil
        if firstBlock then eq(tag .. ": the block under the cards at 348 (S5 under them, A11)", wy(firstBlock), 348) end
        check(tag .. ": NEXT is on the page exactly when it has a row", c.nextHead:IsShown() == (#c.nextList > 0))
        check(tag .. ": WORTH A LOOK is on the page exactly when it has a row", c.lookHead:IsShown() == (#c.lookList > 0))
        check(tag .. ": the cards' last box edge is the main column's", near(P.box(c.cards.cards[4]).l + P.box(c.cards.cards[4]).w, P.box(c.hero).l + mainW))
        -- every card's period is on the card or its group header
        -- (the PLAYED card names the period, "21:35 to now"; the group header has no META)
        local p1 = tostring(c.cards.cards[1].meta.text or "")
        check(tag .. ": the PLAYED card names the period, the header no second one", p1:find("^%d%d:%d%d to now$") ~= nil and c.sesHead.meta.shown == false, p1)
        -- (1.1: no kills and items line; the card is the session's stored death count)
        eq(tag .. ": the DEATHS card has no kills and items line", tostring(c.cards.cards[4].meta.text or ""), "")
        check(tag .. ": the GOLD card has no per hour figure before 30 minutes of play, and one after", (function()
          local sg, meta = c.sessionGold, tostring(c.cards.cards[3].meta.text or "")
          if not sg then return meta == "" end
          if sg.played < Now.RATE_FLOOR or not sg.moved then return meta == "" and sg.perHour == nil end
          return meta:find(" per hour$") ~= nil
        end)(), tostring(c.cards.cards[3].meta.text))
        check(tag .. ": no link to Activity on the page", c.more == nil and c.lookHead.link.shown == false)
        for i, card in ipairs(c.cards.cards) do
          check(tag .. ": card " .. i .. " label fits", not card.label:IsTruncated(), card.label.text)
          check(tag .. ": card " .. i .. " value is never cut", not card.value:IsTruncated(), card.value.text)
        end
        -- the XP label is drawn above the bar (labels OVERLAY, the bar ARTWORK of the same frame)
        check(tag .. ": the XP label sits above the bar's layer", c.hero.meta1._layer == "OVERLAY" and c.hero.track._layer == "BORDER" and c.hero.fill._layer == "ARTWORK" and c.hero.meta1.parentFrame == c.hero.track.parentFrame,
          tostring(c.hero.meta1._layer) .. "/" .. tostring(c.hero.track._layer))
        -- text never runs past TEXT_R
        for _, fs in ipairs({ c.hero.meta1r, c.sesHead.meta }) do
          if fs:IsShown() and (fs.text or "") ~= "" then check(tag .. ": right text ends by the main column's text edge", P.box(fs).l + P.box(fs).w <= win().l + G.BOX_L + mainW - S.S3 + 0.5) end
        end
        -- WORTH A LOOK: capped, and never the empty sentence while the session has events
        local cap = G.isWide(W) and Now.CAP_WIDE or Now.CAP_COMPACT
        check(tag .. ": WORTH A LOOK shows at most its cap", shown(c.lookRows) <= cap, shown(c.lookRows))
        check(tag .. ": no empty sentence, no all-clear line and no +N more link exist on the page", c.lookEmpty == nil and c.allClear == nil and c.more == nil)
        eq(tag .. ": one primary on the view", UI.CountPrimaries(c), c.notice:IsShown() and 1 or 0)
        check(tag .. ": the page's height is what it holds", c.sf.contentH and c.sf.contentH >= 348 - G.CONTENT_TOP + H.SECTION)
      end
    end
  end

  -- ── the ranking: every row kind has an icon, rows come in rank order, the best drop is green or better ──
  do
    local c = P.open("home", "now", 900, 580, "gold")
    local items = Now.lookItems()
    local last = 0
    for _, it in ipairs(items) do
      check("Now: a " .. it.kind .. " row has an icon", it.icon ~= nil)
      check("Now: rows are in rank order", it.rank >= last, it.kind); last = it.rank
      if it.kind == "loot" then check("Now: the best drop is green or better", not it.title:find("Linen Cloth", 1, true), it.title) end
      check("Now: no placeholder reaches a title", not it.title:find("%[") and not it.title:find("Unknown", 1, true) and not it.title:find("|H", 1, true), it.title)
    end
    for _, k in ipairs({ "death", "run", "level", "loot", "quest", "lockout", "repair", "bags", "instance" }) do
      check("Now: UI.KIND_ICON has " .. k, UI.KIND_ICON[k] ~= nil)
    end
    -- what the live session holds is listed: its best green drop over a grey one, and its quests (one row)
    local ses = ns.Recorder.current()
    local now = GetServerTime()
    local function copyOf(list, pred)
      for i = #list, 1, -1 do local r = list[i]; if type(r) == "table" and pred(r) then local o = {}; for k, v in pairs(r) do o[k] = v end return o end end
    end
    local log, evs = ns.DB.loot.log, ns.DB.story.events
    local lootN, evN = #log, #evs
    local base = copyOf(log, function(r) return r.item and not r.money end)
    local qd = copyOf(evs, function(r) return r.kind == "QUESTDONE" and ns.isMine(r) end)
    check("Now: the fixture has a loot row and a quest to copy", base ~= nil and qd ~= nil)
    -- (the harness swaps the saved data under the session being played: its record goes in for the test)
    local hadRec = ns.DB.sessions[ses.id] ~= nil
    if not hadRec then ns.DB.sessions[ses.id] = { id = ses.id, guid = ns.charGuid(), startedEpoch = ses.startedEpoch } end
    if base and qd then
      local grey = {}; for k, v in pairs(base) do grey[k] = v end
      grey.item, grey.q, grey.s, grey.t, grey.id, grey.src = "|cff9d9d9d|Hitem:2589::::::::12:::::|h[Linen Cloth]|h|r", "ff9d9d9d", ses.id, now - 30, 2589, "Defias Trapper"
      base.item, base.q, base.s, base.t, base.id, base.src = "|cff1eff00|Hitem:6078::::::::12:::::|h[Pikeman Shield]|h|r", "ff1eff00", ses.id, now - 20, 6078, "Defias Pillager"
      base.mail, grey.mail = nil, nil   -- (the copied row may be a mail's)
      base.zone = "Westfall"            -- (the best drop's META says where it dropped: the zone outside a run)
      -- (a rarer quest reward in the same session is not a drop: it never becomes the best drop)
      local reward = {}; for k, v in pairs(base) do reward[k] = v end
      reward.item, reward.q, reward.t, reward.id, reward.src = "|cff0070dd|Hitem:2041::::::::12:::::|h[Tunic of Westfall]|h|r", "ff0070dd", now - 15, 2041, "Quest reward"
      log[#log + 1] = grey; log[#log + 1] = base; log[#log + 1] = reward
      for i = 1, 2 do
        local q = {}; for k, v in pairs(qd) do q[k] = v end
        q.s, q.t, q.text, q.xp = ses.id, now - 10 + i, "Complete: The Defias Brotherhood " .. i, 450
        evs[#evs + 1] = q
      end
      local got = {}
      for _, it in ipairs(Now.lookItems()) do got[it.kind] = it end
      check("Now: the session's best drop is the green one", got.loot and got.loot.title == "Best drop: |cff1eff00Pikeman Shield|r" and got.loot.meta:find("^From Westfall") ~= nil, got.loot and (got.loot.title .. " | " .. got.loot.meta) or "none")
      check("Now: the quests turned in are one row", got.quest and got.quest.title == "2 quests turned in" and got.quest.meta:find("^%+900 XP \194\183 ") ~= nil and got.quest.meta:find("last: The Defias Brotherhood 2", 1, true) ~= nil, got.quest and got.quest.meta)
      for i = #log, lootN + 1, -1 do log[i] = nil end
      for i = #evs, evN + 1, -1 do evs[i] = nil end
    end
    if not hadRec then ns.DB.sessions[ses.id] = nil end
    -- the pace lives in memory for the session being played (a data swap of the harness starts it over): 30 active
    -- minutes of 120 XP put in for this session, then the hero and the XP PER HOUR card read the same rate
    local st = Pace.state()
    Pace.sync()
    local nm = math.floor(GetServerTime() / 60)
    for m = nm - 29, nm do st.ev[m] = true; st.xpm[m] = 120 end
    reopen()
    check("Now: with 10 active minutes the hero says when the next level comes", c.pace.rate ~= nil and tostring(c.hero.hero.text):find(" to level ") ~= nil, tostring(c.hero.hero.text))
    check("Now: the XP PER HOUR card shows the hero's rate", c.pace.rate ~= nil and c.cards.cards[2].value.text == UI.fmtNum(c.pace.rate), c.cards.cards[2].value.text)
    local r = c.pace.rate and Pace.remaining(UnitXP("player"), UnitXPMax("player"), c.pace.rate)
    check("Now: the hero's estimate is what is left over the shown rate", r ~= nil and tostring(c.hero.hero.text):find(UI.fmtDur(r, { minutes = true }), 1, true) == 1, tostring(c.hero.hero.text))
    st.xpm, st.ev, st.afk, st.total = {}, {}, {}, 0
  end

  -- ── at the level cap (docs/UX_PRAGMATIC.md 1.1): the hero is gold, the cards are a list of what has a value ──
  do
    local keepMax, keepMetric, keepName, keepPI = _G.GetMaxPlayerLevel, ns.Gold.metric, _G.UnitName, _G.C_PlayerInfo
    local lvl = UnitLevel("player")
    _G.GetMaxPlayerLevel = function() return lvl end
    local led = { gained = 5000, spent = 2000, net = 3000, played = 1799 }
    ns.Gold.metric = function(id, who, when) if when == "session" and led[id] ~= nil then return led[id] end return keepMetric(id, who, when) end
    -- (P.open puts a fresh copy of the data in place: the data is changed after it, then the page drawn again)
    local c = P.open("home", "now", 900, 580)
    local ses = ns.Recorder.current()
    local keepAck, keepDeaths = ns.DB.combat.lastAck, ses.deaths
    ses.deaths = 0
    ns.DB.combat.lastAck = nil
    reopen()
    local function labels() local t = {}; for i, d in ipairs(c.cardDefs or {}) do t[i] = d.label end return table.concat(t, " | ") end
    local function card(key) for i, d in ipairs(c.cardDefs or {}) do if d.key == key then return c.cardRow.cards[i] end end end
    eq("Now at the cap: the hero is the session's net gold", c.hero.hero.text, UI.money(3000, true) .. " this session")
    eq("Now at the cap: no per hour figure one second under 30 minutes of play", tostring(c.hero.meta1.text or ""), "")
    -- (with no line under the hero figure, the name line and the figure are centred on the portrait: the box had an
    -- empty lower third and the text sat higher than the picture)
    do
      local pb, tb, vb = P.box(c.hero.imageFrame), P.box(c.hero.title), P.box(c.hero.hero)
      local mid = (tb.t + vb.t + vb.h) / 2
      check("Now at the cap: with no meta line the two text lines are centred on the portrait", math.abs(mid - (pb.t + pb.h / 2)) <= 3 and tb.t >= pb.t - 1 and vb.t + vb.h <= pb.t + pb.h + 1,
        ("text %s..%s, portrait %s..%s"):format(tb.t, vb.t + vb.h, pb.t, pb.t + pb.h))
      check("Now at the cap: the name's meta moves with the name", math.abs((P.box(c.hero.titleMeta).t + P.box(c.hero.titleMeta).h) - (tb.t + tb.h)) <= 4)
    end
    check("Now at the cap: the level is not the hero and Max level is not on the page", not tostring(c.hero.hero.text):find("Level", 1, true) and not tostring(c.hero.meta1.text):find("Max level", 1, true))
    check("Now at the cap: no XP bar", c.hero.track.shown == false)
    check("Now at the cap: no THIS SESSION header and no XP PER HOUR card", not c.sesHead:IsShown() and not c.cards:IsShown() and not labels():find("XP", 1, true), labels())
    check("Now at the cap: BALANCE, PLAYED, then LAST RUN when a run is stored, then SAVED TO EVERBUFF.GG; no DEATHS at 0",
      labels() == (Now.lastRun() and "Balance | Played | Last run | Saved to everbuff.gg" or "Balance | Played | Saved to everbuff.gg"), labels())
    check("Now at the cap: with no pickup seen the card says Not seen yet, muted, and the hover says what to do", card("saved").value.text == "Not seen yet"
      and near(card("saved").value._color[1], UI.C.fgMuted[1], 0.01) and card("saved").ebTip.text:find("Install the desktop app from everbuff.gg", 1, true) ~= nil, card("saved").value.text)
    check("Now at the cap: PLAYED has no second line", tostring(card("played").meta.text or "") == "")
    for i, d in ipairs(c.cardDefs) do
      local cd = c.cardRow.cards[i]
      check("Now at the cap: card " .. d.key .. " has a value, never a dash, and nothing is cut", tostring(cd.value.text) ~= "-" and tostring(cd.value.text) ~= "" and not cd.value:IsTruncated() and not cd.meta:IsTruncated(), tostring(cd.value.text) .. " / " .. tostring(cd.meta.text))
    end
    eq("Now at the cap: the cards are S3 under the hero, with no header between", wy(c.cardRow) - wy(c.hero), H.HERO + S.S3)
    eq("Now at the cap: the last card ends on the main column's edge", P.box(c.cardRow.cards[#c.cardDefs]).l + P.box(c.cardRow.cards[#c.cardDefs]).w, P.box(c.hero).l + G.mainW(900))
    led.played = 1800; reopen()
    eq("Now at the cap: from 30 minutes on the hero names the rate", c.hero.meta1.text, UI.money(6000, true) .. " per hour")
    check("Now at the cap: with the rate line the hero keeps its three line layout", c.hero.dy == 0 and math.abs(P.box(c.hero.title).t - P.box(c.hero).t - S.S3) <= 0.5, tostring(c.hero.dy))
    ns.DB.combat.lastAck = { at = GetServerTime() - 120, fights = 2, source = "file" }
    ses.deaths = 3; reopen()
    -- (lastAck.at is when the addon saw the confirmation, not when the desktop app saved: the count leads and the
    -- time is worded "confirmed")
    check("Now at the cap: a save seen reads its pulls, and the time as when it was confirmed", card("saved").value.text == "2 pulls"
      and (card("saved").meta.text == "confirmed " .. UI.fmtStamp(GetServerTime() - 120) or card("saved").meta.text == "confirmed " .. UI.fmtStamp(GetServerTime() - 120):gsub("^%a+ ", ""))
      and card("saved").meta.text:find("^confirmed .*%d%d:%d%d$") ~= nil and not card("saved").meta:IsTruncated(), tostring(card("saved").value.text) .. " / " .. tostring(card("saved").meta.text))
    eq("Now at the cap: its hover says the time is the confirmation's", card("saved").ebTip.text, "The desktop app saved this data earlier. The time is when the addon saw its confirmation, not when it was saved.")
    check("Now at the cap: DEATHS only above 0, and at most 4 cards", (card("deaths") ~= nil) == (#c.cardDefs < 4 or labels():find("Deaths", 1, true) ~= nil) and #c.cardDefs <= 4
      and (Now.lastRun() ~= nil or (card("deaths") and card("deaths").value.text == "3")), labels())
    -- no gold moved: the hero is the balance, and BALANCE is not a card too
    led.gained, led.spent, led.net = 0, 0, 0
    ns.char().gold.balance = 1219; reopen()
    eq("Now at the cap: with no gold moved the hero is the balance", c.hero.hero.text, UI.money(1219))
    check("Now at the cap: and BALANCE is not shown twice", card("balance") == nil and c.heroIsBalance == true, labels())
    -- WORTH A LOOK: the session's largest gold lines, or no section
    local keepEntries = ns.Gold.entries
    ns.Gold.entries = function() return {} end; reopen()
    check("Now at the cap: with no gold line the WORTH A LOOK section is not there, and no kills line stands in", #c.lookList == 0 and not c.lookHead:IsShown() and shown(c.lookRows) == 0)
    ns.Gold.entries = function() return {
      { delta = -45, src = "flights", detail = "Tal", t = 1800000100 }, { delta = -281985, src = "auctions", detail = "Buyout", t = 1800000000 },
      { delta = 120, src = "looted", detail = "", t = 1800000200 }, { delta = -27880, src = "auctions", detail = "Buyout", t = 1800000050 }, { delta = 0, src = "other", detail = "", t = 1 } } end
    reopen()
    check("Now at the cap: WORTH A LOOK lists the 3 largest gold lines, largest first", #c.lookList == 3 and c.lookList[1].title == "Buyout" and c.lookList[1].meta == UI.money(-281985, true) .. " \194\183 Auction house \194\183 " .. UI.fmtClock(1800000000)
      and c.lookList[2].meta:find(UI.money(-27880, true), 1, true) == 1 and c.lookList[3].title == "Loot" and c.lookHead:IsShown() and shown(c.lookRows) == 3, c.lookList[1] and c.lookList[1].meta)
    ns.Gold.entries = keepEntries
    -- the name: whole, or not at all
    local first = (keepName("player"))
    _G.C_PlayerInfo = { ShouldDisplaySurname = function() return true end }
    _G.UnitName = function(u) if u == "player" then return first, "Hart" end return keepName(u) end
    reopen()
    eq("Now: the title is the whole name", c.hero.title.text, first .. " Hart")
    check("Now: who that is stands beside it", tostring(c.hero.titleMeta.text):find("^Level " .. lvl) ~= nil and c.hero.titleMeta:IsShown())
    local keepSur = ns.char().surname
    _G.UnitName = function(u) if u == "player" then return first, nil end return keepName(u) end
    ns.char().surname = "Stored"; reopen()
    eq("Now: the second name falls back to the stored one", c.hero.title.text, first .. " Stored")
    ns.char().surname = nil; reopen()
    check("Now: with half a name the name is left out and the title is the class line", ns.fullName() == nil and tostring(c.hero.title.text):find("^Level " .. lvl) ~= nil and not c.hero.titleMeta:IsShown()
      and not tostring(c.hero.title.text):find(first, 1, true), c.hero.title.text)
    _G.C_PlayerInfo = keepPI
    eq("Now: a client with no second names shows the one name it has", ns.fullName(), first)
    ns.char().surname = keepSur
    _G.UnitName, _G.GetMaxPlayerLevel, ns.Gold.metric = keepName, keepMax, keepMetric
    ses.deaths, ns.DB.combat.lastAck = keepDeaths, keepAck
    reopen()
    check("Now: a leveling character keeps THIS SESSION and its four cards", c.sesHead:IsShown() and c.cards:IsShown() and c.cardRow == c.cards and c.cards.cards[2].label.text == "XP PER HOUR")
  end

  -- ── NEXT: the live readings, their order and the cap; the all-clear line when nothing needs you ──
  do
    local keepDur, keepCont = M.dur, _G.C_Container.GetContainerNumFreeSlots
    local keepQ, keepN, keepLim = _G.GetQuestLogTitle, _G.GetNumQuestLogEntries, ns.DB.settings.instanceLimit
    M.dur = {}
    local c = P.open("home", "now", 900, 580)
    check("Now: nothing needs you: no NEXT section and no sentence", not c.nextHead:IsShown() and shown(c.nextRows) == 0 and c.allClear == nil)
    M.dur = { [1] = { 18, 100 }, [5] = { 60, 100 }, [7] = { 40, 100 } }
    _G.C_Container.GetContainerNumFreeSlots = function(bag) return bag == 0 and 2 or 0, 0 end
    _G.GetNumQuestLogEntries = function() return 3 end
    _G.GetQuestLogTitle = function(i)
      if i == 1 then return "The Barrens", nil, nil, true, false, nil end
      if i == 2 then return "Wanted: Kolkar Leaders", 18, nil, false, false, 1 end
      return "Plainstrider Menace", 17, nil, false, false, 1
    end
    ns.DB.settings.instanceLimit = 1
    local now = GetServerTime()
    local cg = ns.char()
    local keepCopies = cg.dungeonCopies
    cg.dungeonCopies = { { t = now - 34 * 60, key = "Ragefire Chasm", why = "first" } }
    reopen()
    local nx = c.nextList
    check("Now: NEXT holds at most 3 rows", #nx == 3 and shown(c.nextRows) == 3, #nx)
    check("Now: bags first, then repair, then the instance limit", nx[1].kind == "bags" and nx[2].kind == "repair" and nx[3].kind == "instance",
      (nx[1] and nx[1].kind or "") .. "," .. (nx[2] and nx[2].kind or "") .. "," .. (nx[3] and nx[3].kind or ""))
    check("Now: bags are bad with their count", nx[1].dot == "bad" and nx[1].title == "Bags almost full: 2 free slots", nx[1].title)
    check("Now: repair at 18% is bad and names the lowest item", nx[2].dot == "bad" and nx[2].title == "Repair soon: your lowest item is at 18%" and #nx[2].tip.pairs == 2, nx[2].title)
    check("Now: no instance left, next free in 26m", nx[3].dot == "bad" and nx[3].title == "No instances left this hour" and nx[3].meta == "Next free in 26m" and nx[3].onClick ~= nil, tostring(nx[3].meta))
    check("Now: a row with no link has no chevron", not c.nextRows[1].chev:IsShown() and c.nextRows[3].chev:IsShown())
    check("Now: the state dot sits before the title", c.nextRows[1].dot:IsShown() and P.box(c.nextRows[1].dot).l < P.box(c.nextRows[1].title).l)
    -- with no limit set, the quests ready row takes the third place
    ns.DB.settings.instanceLimit = nil
    M.dur = { [1] = { 40, 100 } }
    reopen()
    nx = c.nextList
    check("Now: repair at 40% is warn", nx[2] and nx[2].kind == "repair" and nx[2].dot == "warn", nx[2] and nx[2].dot)
    check("Now: the quests ready row with their names", nx[3] and nx[3].kind == "quest" and nx[3].title == "2 quests ready to turn in" and nx[3].meta == "Wanted: Kolkar Leaders, Plainstrider Menace", nx[3] and nx[3].meta)
    -- whole names, then +N
    eq("Now: names that do not fit end in +N", Now.fitNames({ "Wanted: Kolkar Leaders", "Plainstrider Menace", "Fungal Spores" }, 160), "Wanted: Kolkar Leaders +2")
    M.dur, _G.C_Container.GetContainerNumFreeSlots = keepDur, keepCont
    _G.GetQuestLogTitle, _G.GetNumQuestLogEntries, ns.DB.settings.instanceLimit = keepQ, keepN, keepLim
    cg.dungeonCopies = keepCopies
    reopen()
  end

  -- ── the combat-log notice: the page moves down 52, its button is the view's one primary ──
  do
    local keep = ns.Logging.state
    ns.Logging.state = function() return true, false end
    local c = P.open("home", "now", 900, 580)
    check("Now: the notice shows with the combat log off", c.notice:IsShown())
    eq("Now: the notice at CONTENT_TOP", wy(c.notice), G.CONTENT_TOP)
    eq("Now: the hero moves down 52 under the notice", wy(c.hero), G.CONTENT_TOP + 52)
    eq("Now: one primary with the notice", UI.CountPrimaries(c), 1)
    c.notice.dismiss:GetScript("OnClick")(c.notice.dismiss); M.settle()
    check("Now: dismissed, the hero is back at CONTENT_TOP", not c.notice:IsShown() and wy(c.hero) == G.CONTENT_TOP)
    eq("Now: no primary without the notice", UI.CountPrimaries(c), 0)
    ns.Logging.state = keep
  end

  -- ── a session with nothing in it yet: the empty sentence right under its header ──
  do
    local ses = ns.Recorder.current()
    local keepId, keepK, keepI = ses.id, ses.kills, ses.items
    local pst, paceKeep = Pace.state(), {}
    for k, v in pairs(Pace.state()) do paceKeep[k] = v end
    ses.id, ses.kills, ses.items = "empty-session", 0, 0
    local c = P.open("home", "now", 900, 580)
    ses = ns.Recorder.current()
    ses.id, ses.kills, ses.items = "empty-session", 0, 0
    reopen()
    local lockouts = 0
    for _, it in ipairs(c.lookList) do if it.kind == "lockout" then lockouts = lockouts + 1 end end
    if lockouts == 0 then
      check("Now: an empty session has no WORTH A LOOK section, no 'so far' row and no sentence", #c.lookList == 0 and not c.lookHead:IsShown() and shown(c.lookRows) == 0 and c.lookEmpty == nil)
    end
    ses.id, ses.kills, ses.items = keepId, keepK, keepI
    for k in pairs(pst) do pst[k] = nil end
    for k, v in pairs(paceKeep) do pst[k] = v end
    reopen()
  end

  -- ── first run (4.13): the guide stands in for Now until Finish or Skip; three steps; the old card's answer counts ──
  do
    local st = ns.DB.settings
    local keepLog, keepPill = ns.Logging.state, ns.Gold.pillAnswer
    local answered
    ns.Gold.pillAnswer = function(yes) answered = yes; return true end
    ns.Logging.state = function() return true, false end
    st.welcomeDone = false
    local c = P.open("home", "now", 900, 580)
    st = ns.DB.settings; st.welcomeDone = false; reopen()
    local w = c.welcome
    check("First run: the guide replaces Now, scroll thumb and all", w:IsShown() and not c.sf:IsShown() and not c.sf.thumb:IsShown())
    eq("First run: step 1 of 3", w.stepText.text, "Step 1 of 3")
    eq("First run: the step bar at CONTENT_TOP", wy(w.dots[1]), G.CONTENT_TOP + 4)
    eq("First run: the title at y 124", wy(w.title), 124)
    eq("First run: the body at y 148", wy(w.body), 148)
    eq("First run: texts start at TEXT_L", wx(w.title), G.TEXT_L)
    check("First run: the body is at most 520 wide", P.box(w.body).w <= 520)
    eq("First run: step 1 names the welcome", w.title.text, "Welcome to everbuff.gg")
    check("First run: the combat log row offers Turn on", w.status[2].text.text == "Combat log: off" and w.turnOn:IsShown())
    check("First run: no Back on step 1", not w.back:IsShown() and w.next:IsShown() and w.skip:IsShown())
    eq("First run: one primary on step 1", UI.CountPrimaries(w), 1)
    local nb = P.box(w.next)
    check("First run: the footer is right-aligned to BOX_R at the content bottom", near(nb.l + nb.w, win().l + G.BOX_L + G.mainW(900)) or near(nb.l + nb.w, P.box(c).l + P.box(c).w), ("%s"):format(nb.l + nb.w))
    check("First run: the sidebar still works", _G.EverbuffFrame and true)
    w.next:GetScript("OnClick")(w.next); M.settle()
    eq("First run: step 2 asks about the gold line", w.title.text, "Show your gold on screen?")
    check("First run: step 2 hides Next, shows Back, No thanks and Show it", not w.next:IsShown() and w.back:IsShown() and w.noThanks:IsShown() and w.showIt:IsShown())
    eq("First run: one primary on step 2", UI.CountPrimaries(w), 1)
    check("First run: the gold preview has text", (w.pill.text.text or "") ~= "")
    w.showIt:GetScript("OnClick")(w.showIt); M.settle()
    check("First run: Show it answers the pill question and moves to step 3", answered == true and w.title.text == "Three things to get started")
    check("First run: three ROW2 rows with an icon", w.rows[3]:IsShown() and w.rows[1].title.text == "Run a dungeon" and w.rows[3].meta.text == "Type /eb or click the minimap button.")
    eq("First run: Next reads Finish on step 3", w.next.text.text, "Finish")
    w.back:GetScript("OnClick")(w.back); M.settle()
    eq("First run: Back goes one step back", w.stepText.text, "Step 2 of 3")
    w.noThanks:GetScript("OnClick")(w.noThanks); M.settle()
    check("First run: No thanks answers no", answered == false and w.stepText.text == "Step 3 of 3")
    w.next:GetScript("OnClick")(w.next); M.settle()
    check("First run: Finish sets welcomeDone and lands on Now", ns.DB.settings.welcomeDone == true and not w:IsShown() and c.sf:IsShown())
    -- Skip from step 1
    ns.DB.settings.welcomeDone = false; reopen()
    check("First run: the guide starts over on step 1", w:IsShown() and w.stepText.text == "Step 1 of 3")
    w.skip:GetScript("OnClick")(w.skip); M.settle()
    check("First run: Skip sets welcomeDone", ns.DB.settings.welcomeDone == true and not w:IsShown())
    -- the old welcome card's answer
    local s1 = { onboarded = true }
    UI.MigrateSettings(s1)
    check("First run: a save that dismissed the old card counts as done", s1.welcomeDone == true and s1.onboarded == nil)
    local s2 = {}
    UI.MigrateSettings(s2)
    check("First run: a new save sees the guide", s2.welcomeDone == false)
    ns.Logging.state, ns.Gold.pillAnswer = keepLog, keepPill
    reopen()
  end
end
