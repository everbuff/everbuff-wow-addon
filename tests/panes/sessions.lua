-- Pane tests: Home > Sessions (docs/UX_PRAGMATIC.md 1.2). The data rules on a small fixture in the shapes of the
-- founder's save of 21 Nov 2026 (two logins 30 s apart, a 0.9.39 session whose old counter says 22 runs, empty
-- logins of 76 s and 131 s, a 107 s login with XP, another character's session), then the page: the week's answer,
-- where the list starts, the columns that have something to say, and the geometry at three sizes.
return function(P)
  local check, eq, M, ns = P.check, P.eq, P.M, P.ns
  local UI = ns.UI
  local Sess, Gold = ns.Sessions, ns.Gold
  local function near(a, b, tol) return a and b and math.abs(a - b) <= (tol or 0.51) end
  local function reopen() UI.Open("Home", "sessions"); M.settle() end
  local function listed(tbl)
    local days, rows = {}, {}
    for i = 1, tbl.shownN do
      local r = tbl.rows[i]
      if r.item and r.item.ebSection then days[#days + 1] = r else rows[#rows + 1] = r end
    end
    return rows, days
  end
  local function cell(r, k) return tostring(r.c[k] and r.c[k].text or "") end
  local function lineOf(r, tbl)
    local out = {}
    for _, k in ipairs({ "date", "len", "lvl", "xp", "gold", "deaths", "dung" }) do out[#out + 1] = (not tbl or tbl.cols[k]) and cell(r, k) or "" end
    return table.concat(out, " | ")
  end
  local keepJoin = Gold.JOIN_S
  local keepCur
  local function restoreCur()
    local cur = ns.Recorder.current()
    if not (cur and keepCur) then return end
    for k in pairs(cur) do cur[k] = nil end
    for k, v in pairs(keepCur) do cur[k] = v end
    keepCur = nil
  end

  check("Sessions: the version compare reads 0.9.50 on, and nothing from a version it cannot read",
    Sess.verAtLeast("0.9.50", "0.9.50") and Sess.verAtLeast("0.9.51", "0.9.50") and Sess.verAtLeast("0.10.0", "0.9.50") and Sess.verAtLeast("1.0", "0.9.50")
    and not Sess.verAtLeast("0.9.49", "0.9.50") and not Sess.verAtLeast("0.9.5", "0.9.50") and not Sess.verAtLeast(nil, "0.9.50") and not Sess.verAtLeast("dev", "0.9.50"))

  -- ── the fixture: the stored records of one character, in the save's shapes ───────────────────────────────────
  -- Returns the ids by name. `now` is the stub's clock; the running session started 561 s ago, 30 s after the
  -- login before it ended (11:45:25 to 11:46:31 and 11:47:01 on the save).
  local DAY = 86400
  local function fixture()
    -- (the suite's running session is the recorder's own record; the data set of the page is a copy, so the record
    -- is put into it as the active one. keepCur holds its fields, put back at the end of the block.)
    local cur = ns.Recorder.current()
    local now = M.epoch
    local g = ns.charGuid()
    keepCur = {}
    for k, v in pairs(cur) do keepCur[k] = v end
    for id in pairs(ns.DB.sessions) do ns.DB.sessions[id] = nil end
    ns.DB.sessions[cur.id], ns.DB.active = cur, cur.id
    cur.guid = g
    local function add(id, t0, secs, f)
      local s = { id = id, guid = g, startedEpoch = t0, endedEpoch = secs and (t0 + secs) or nil, endedBy = secs and "logout" or nil,
        xp = 0, gained = 0, spent = 0, kills = 0, deaths = 0, fights = 0, items = 0, dungeons = 0, level0 = 60, level = 60, addonVersion = "0.9.51" }
      for k, v in pairs(f or {}) do s[k] = v end
      ns.DB.sessions[id] = s
      return s
    end
    -- the running login: bought at the auction house, nothing looted
    for k in pairs(cur) do if type(cur[k]) == "number" and k ~= "startedEpoch" then cur[k] = 0 end end
    cur.startedEpoch, cur.endedEpoch, cur.endedBy = now - 561, nil, nil
    cur.level0, cur.level, cur.addonVersion = 60, 60, "0.9.51"
    cur.gained, cur.spent, cur.items = 0, 309910, 2
    cur.goldLog = { { t = 60, d = -281985, src = "auctions" }, { t = 120, d = -27880, src = "auctions" }, { t = 180, d = -45, src = "flights" } }
    add("fx-relog", now - 561 - 30 - 66, 66, { gained = 84773 })
    -- yesterday evening: 59 to 60, a journal, no run although the run store covers it
    add("fx-ding", now - DAY, 13971, { level0 = 59, level = 60, xp = 191592, gained = 100, spent = 1265902, kills = 130, items = 202,
      goldLog = { { t = 10, d = 100, src = "looted" } } })
    -- yesterday afternoon: one stored run began in it, 2 deaths
    add("fx-run", now - DAY - 20000, 5901, { level0 = 58, level = 59, xp = 74593, gained = 35285, deaths = 2, kills = 63, items = 39, dungeons = 1 })
    -- 0.9.39: the old counter says 22 (door entries), no stored run
    add("fx-old22", now - 4 * DAY, 16338, { level0 = 52, level = 53, xp = 139703, spent = 1145564, deaths = 2, items = 180, dungeons = 22, addonVersion = "0.9.39" })
    -- 107 s with XP and gold: listed
    add("fx-107", now - 4 * DAY - 2000, 107, { level0 = 52, level = 52, xp = 14677, gained = 28375, items = 2, addonVersion = "0.9.39" })
    -- two logins 128 s apart (16 Nov 17:01 and 17:48 on the save): one row, 48 to 49
    add("fx-pair-b", now - 5 * DAY, 1482, { level0 = 48, level = 49, xp = 10505, gained = 8624, addonVersion = "0.9.37" })
    add("fx-pair-a", now - 5 * DAY - 128 - 2694, 2694, { level0 = 48, level = 48, xp = 47373, gained = 42101, items = 14, addonVersion = "0.9.37" })
    -- a level 41 session that earned no XP: a stored zero
    add("fx-zero", now - 9 * DAY, 1088, { level0 = 41, level = 41, spent = 25666, items = 1, addonVersion = "0.9.37" })
    -- empty logins of 76 s and 131 s: left out (the old rule kept the 131 s one)
    add("fx-empty76", now - 5 * DAY - 30000, 76, { level0 = 48, level = 48, addonVersion = "0.9.37" })
    add("fx-empty131", now - 16 * DAY, 131, { level0 = 17, level = 17, addonVersion = "0.9.33" })
    -- 5 minutes with nothing in it: over the limit, listed
    add("fx-empty300", now - 16 * DAY - 4000, 300, { level0 = 17, level = 17, addonVersion = "0.9.33" })
    -- a record with no stored end that is not the running one (the client closed without saving)
    add("fx-crash", now - 12 * DAY, nil, { level0 = 30, level = 30, xp = 500, addonVersion = "0.9.36" })
    -- a record from before the counters: no deaths, xp or gold field
    local bare = add("fx-bare", now - 14 * DAY, 3000, { addonVersion = "0.9.20" })
    bare.xp, bare.gained, bare.spent, bare.deaths, bare.level0, bare.level = nil, nil, nil, nil, nil, 20
    -- another character's session
    add("fx-alt", now - 3 * DAY, 4000, { guid = "Player-1-0000AA", xp = 999, gained = 999 })
    -- the run store: one record that began in fx-run
    local c = ns.char()
    c.dungeonRuns = { { id = "fx-r1", v = 2, inst = "Blackrock Spire", t = now - DAY - 20000 + 358, endT = now - DAY - 20000 + 4985, secs = { inside = 4148 }, bosses = {} } }
    c.dungeonRun, c.dungeonLegacy = nil, {}
    -- the character's totals: what the stored sessions add up to
    local gsum, xsum = 0, 0
    for _, s in pairs(ns.DB.sessions) do if s.guid == g then gsum, xsum = gsum + (s.gained or 0), xsum + (s.xp or 0) end end
    c.gold = c.gold or {}; c.gold.gained = gsum
    c.xp = c.xp or {}; c.xp.gained = xsum
    return cur, c
  end

  -- ── the rows ──────────────────────────────────────────────────────────────────────────────────────────────────
  do
    local c = P.open("home", "sessions", 1104, 697, "normal")
    Gold.JOIN_S = 5 * 60
    local cur, blk = fixture()
    local now = M.epoch
    local rows, hidden = Sess.rows(now)
    local by = {}
    for _, r in ipairs(rows) do by[r.id] = r end
    eq("Sessions data: 14 records of the character are 10 rows (2 joins, 2 empty logins left out)", #rows .. " " .. hidden, "10 2")
    check("Sessions data: another character's session is not a row", by["fx-alt"] == nil)
    check("Sessions data: newest first", rows[1].id == cur.id and rows[2].id == "fx-ding" and rows[#rows].id == "fx-empty300", rows[1].id .. " " .. rows[#rows].id)
    local live = by[cur.id]
    eq("Sessions data: two logins 30 s apart are one row, its start the first login's", live.logins .. " " .. live.startedEpoch, "2 " .. (now - 561 - 30 - 66))
    eq("Sessions data: its length is the logins added up, not the span (66 s + 561 s; the 30 s logged out are not played)", live.secs, 627)
    eq("Sessions data: its gold is both logins' (+84,773 and -309,910)", live.net, 84773 - 309910)
    check("Sessions data: the running session is live and never left out", live.live == true and by["fx-relog"] == nil)
    local pair = by["fx-pair-b"]
    eq("Sessions data: two logins 128 s apart: 48 to 49, XP and length added up", ("%d %d %d %d %d"):format(pair.logins, pair.level0, pair.level, pair.xp, pair.secs), "2 48 49 57878 4176")
    check("Sessions data: empty logins of 76 s and 131 s are left out, 107 s with XP and an empty 5 minutes are listed",
      by["fx-empty76"] == nil and by["fx-empty131"] == nil and by["fx-107"] ~= nil and by["fx-empty300"] ~= nil)
    -- runs: the run store's, never the old counter
    eq("Sessions data: a session with one stored run says 1", by["fx-run"].runs, 1)
    eq("Sessions data: a 0.9.51 session with no stored run says 0", by["fx-ding"].runs, 0)
    check("Sessions data: a 0.9.39 session whose old counter says 22 has no run count", by["fx-old22"].runs == nil and by["fx-old22"].sess.dungeons == 22)
    check("Sessions data: a join with one login from before the run store has no run count", pair.runs == nil)
    blk.dungeonLegacy = { { id = "g1", src = "gold", inst = "Maraudon", t = by["fx-old22"].startedEpoch + 600, secs = 4250, looted = 365, quests = 0, items = 36, lootValue = 93437 } }
    local rows2 = Sess.rows(now)
    for _, r in ipairs(rows2) do if r.id == "fx-old22" then eq("Sessions data: a rebuilt run that began in an old session counts for it", r.runs, 1) end end
    blk.dungeonLegacy = {}
    -- what a record does not store is nil, a stored zero is 0
    check("Sessions data: a stored zero XP below the cap is 0", by["fx-zero"].xp == 0 and by["fx-zero"].atCap == false)
    check("Sessions data: a session that started at the cap is marked (no XP to earn)", live.atCap == true and by["fx-ding"].atCap == false)
    local bare = by["fx-bare"]
    check("Sessions data: a record with no counters has no XP, gold or deaths", bare.xp == nil and bare.net == nil and bare.deaths == nil and bare.level0 == 20)
    check("Sessions data: a record with no stored end has no length and is not live", by["fx-crash"].secs == nil and by["fx-crash"].live == false)
    check("Sessions data: nor a run count: the runs after it are not its runs", by["fx-crash"].runs == nil and ns.RunsLegacy.inSession(by["fx-crash"].sess) == 0, tostring(by["fx-crash"].runs))
    -- the gap proof
    eq("Sessions data: totals equal to the stored sessions prove no gap", Sess.gaps(), false)
    blk.gold.gained = blk.gold.gained + 1
    eq("Sessions data: one copper more on the character than in the sessions proves a gap", Sess.gaps(), true)
    blk.gold.gained = blk.gold.gained - 1
    blk.xp.gained = blk.xp.gained + 10
    eq("Sessions data: so does XP the sessions do not hold", Sess.gaps(), true)
    blk.xp.gained = blk.xp.gained - 10
    -- what a row opens
    eq("Sessions data: the running session opens the Session period of Gold", Sess.goldScope(live), "session")
    eq("Sessions data: one stored login with a journal opens its own journal", Sess.goldScope(by["fx-ding"]), "fx-ding")
    check("Sessions data: a row with no journal, or of several past logins, opens nothing", Sess.goldScope(by["fx-run"]) == nil and Sess.goldScope(pair) == nil)

    -- ── the page on the same data ──
    reopen()
    local tbl = c.tbl
    local trs, days = listed(tbl)
    eq("Sessions page: 10 rows", #trs, 10)
    local t = {}
    for _, r in ipairs(trs) do t[r.item.id] = r end
    eq("Sessions page: columns When, Length, Level, XP, Gold, Deaths; Runs is left out (2 of 10 rows have a count)", (function()
      local k = {}
      for _, col in ipairs(tbl.full) do if tbl.cols[col.key] and col.key ~= "_chev" then k[#k + 1] = col.key end end
      return table.concat(k, ",")
    end)(), "date,len,lvl,xp,gold,deaths")
    eq("Sessions page: the joined session: its first login's time, 10m, no XP at the cap, the net of both logins, 0 deaths",
      lineOf(t[cur.id], tbl), UI.fmtClock(live.startedEpoch) .. " | 10m | 60 |  | " .. UI.money(84773 - 309910, true) .. " | 0 | ")
    check("Sessions page: LIVE stands on the running session only", t[cur.id].ebBadge and t[cur.id].ebBadge:IsShown() and not (t["fx-crash"].ebBadge and t["fx-crash"].ebBadge:IsShown()))
    eq("Sessions page: a level-up reads 59 to 60", cell(t["fx-ding"], "lvl") .. " | " .. cell(t["fx-ding"], "xp"), "59 to 60 | 191,592")
    eq("Sessions page: a stored zero reads 0", cell(t["fx-zero"], "xp") .. " | " .. cell(t["fx-zero"], "deaths"), "0 | 0")
    eq("Sessions page: 107 s reads 2m, the joined pair 1h 10m", cell(t["fx-107"], "len") .. " | " .. cell(t["fx-pair-b"], "len"), "2m | 1h 10m")
    eq("Sessions page: a record with no counters has blank cells", lineOf(t["fx-bare"], tbl), UI.fmtClock(t["fx-bare"].item.startedEpoch) .. " | 50m | 20 |  |  |  | ")
    eq("Sessions page: no stored end, no length", cell(t["fx-crash"], "len"), "")
    local bad = {}
    for _, r in ipairs(trs) do
      for k, fs in pairs(r.c) do
        local x = tostring(fs.text or "")
        if x == "-" or x:find("\226\128\148", 1, true) then bad[#bad + 1] = r.item.id .. "." .. k end
      end
    end
    check("Sessions page: no cell reads a dash", #bad == 0, table.concat(bad, ","))
    check("Sessions page: no Kills column, no strip, no gold block, no line about hidden sessions", tbl.cols.kills == nil and tbl.head.kills == nil and c.xpStrip == nil and c.goldStrip == nil
      and c.goldBand == nil and c.shortLine == nil)
    eq("Sessions page: the header says where the list starts", c.section.label.text, ("SESSIONS SINCE " .. UI.fmtSince(t["fx-empty300"].item.startedEpoch)):upper())
    check("Sessions page: no remark while the totals add up", not P.visible(c.section.meta))
    -- the row hover: the span, the logins, the run count the hidden column would show
    local tip = _G.GameTooltip
    t[cur.id]:GetScript("OnEnter")(t[cur.id])
    local said = table.concat(tip.lines, " / ")
    check("Sessions page: the hover of a joined row says 2 logins, Max level and its runs", said:find("Logins  2", 1, true) and said:find("XP  Max level", 1, true) and said:find("Runs  0", 1, true), said)
    t[cur.id]:GetScript("OnLeave")(t[cur.id])
    t["fx-old22"]:GetScript("OnEnter")(t["fx-old22"])
    said = table.concat(tip.lines, " / ")
    check("Sessions page: the hover of an old session says Runs Not recorded, never 22", said:find("Runs  Not recorded", 1, true) ~= nil and not said:find("Runs  22", 1, true), said)
    t["fx-old22"]:GetScript("OnLeave")(t["fx-old22"])
    t["fx-run"]:GetScript("OnEnter")(t["fx-run"])
    check("Sessions page: the hover of a session with a stored run says Runs 1", table.concat(tip.lines, " / "):find("Runs  1", 1, true) ~= nil, table.concat(tip.lines, " / "))
    t["fx-run"]:GetScript("OnLeave")(t["fx-run"])
    -- chevrons: only where a click opens the gold of the session
    check("Sessions page: a chevron only on rows that open their gold", cell(t["fx-ding"], "_chev") ~= "" and cell(t[cur.id], "_chev") ~= "" and cell(t["fx-run"], "_chev") == "" and cell(t["fx-pair-b"], "_chev") == "")
    -- the gap remark
    blk.gold.gained = blk.gold.gained + 500
    reopen()
    check("Sessions page: totals above the stored sessions: one muted remark, the reason in its hover", P.visible(c.section.meta) and c.section.meta.text == "not every session is kept"
      and c.section.metaHit and c.section.metaHit.ebTip and tostring(c.section.metaHit.ebTip.text):find("desktop app", 1, true) ~= nil, c.section.meta.text)
    blk.gold.gained = blk.gold.gained - 500
    -- Runs appears once a third of the rows have a count; Level goes when every row is one level; XP at the cap
    for _, s in pairs(ns.DB.sessions) do if s.guid == cur.guid then s.addonVersion = "0.9.51" end end
    reopen()
    trs = listed(tbl); t = {}
    for _, r in ipairs(trs) do t[r.item.id] = r end
    check("Sessions page: with every session on the run store the Runs column shows, 1 and 0", tbl.cols.dung ~= nil and cell(t["fx-run"], "dung") == "1" and cell(t["fx-ding"], "dung") == "0" and cell(t["fx-old22"], "dung") == "0")
    for id, s in pairs(ns.DB.sessions) do if s.guid == cur.guid then s.level0, s.level = 60, 60 end end
    reopen()
    check("Sessions page: every row at level 60: no Level column and no XP column", tbl.cols.lvl == nil and tbl.cols.xp == nil and tbl.cols.gold ~= nil)
    -- a click opens the session's gold journal
    trs = listed(tbl)
    local dingRow
    for _, r in ipairs(trs) do if r.item.id == "fx-ding" then dingRow = r end end
    dingRow:GetScript("OnClick")(dingRow, "LeftButton"); M.settle()
    local gold
    for _, tab in ipairs(P.T.tabs) do if tab.name == "Loot" then gold = tab.paneByKey.gold.content end end
    check("Sessions page: a click on a row opens that session's journal in Loot > Gold", P.visible(gold) and gold.st.scope == "fx-ding" and gold.st.view == "journal", gold and gold.st and tostring(gold.st.scope))
    Gold.JOIN_S = keepJoin
    restoreCur()
  end

  -- ── the answer line: the week of Loot > Gold, and the runs that began in it ──────────────────────────────────
  do
    local c = P.open("home", "sessions", 1104, 697, "gold")
    local sc = Gold.scope("week", "char")
    local a = Sess.answer()
    check("Sessions answer: the gold fixture has day rows this week", a ~= nil and #sc.period.days > 0)
    if a then
      eq("Sessions answer: the net is the Week of Loot > Gold, to the copper", a.net, sc.ledger.gained - sc.ledger.spent)
      local segs = {}
      for _, sg in ipairs(c.summary.segs or {}) do segs[#segs + 1] = sg.text end
      local head = sc.since and ("Since " .. UI.fmtStamp(sc.since)) or "This week"
      check("Sessions answer: it names the week, or where the gold history starts inside it", P.visible(c.summary) and tostring(segs[1]):find(head .. ": net ", 1, true) == 1, tostring(segs[1]))
      -- the runs of the run store that began in the range, full and rebuilt, and none from before it
      local blk = ns.char()
      blk.dungeonRuns = { { id = "a1", inst = "Deadmines", t = a.from + 10, bosses = {} }, { id = "a0", inst = "Deadmines", t = a.from - 10, bosses = {} } }
      blk.dungeonLegacy = { { id = "g" .. (a.from + 20), src = "gold", inst = "Maraudon", t = a.from + 20, secs = 100 } }
      blk.dungeonRun = nil
      eq("Sessions answer: 2 runs began in the range (one full, one rebuilt), the one before it is not counted", Sess.answer().runs, 2)
      reopen()
      segs = {}
      for _, sg in ipairs(c.summary.segs or {}) do segs[#segs + 1] = sg.text end
      check("Sessions answer: the line says 2 runs", tostring(segs[2]):find("2", 1, true) ~= nil and tostring(segs[2]):find("runs", 1, true) ~= nil, tostring(segs[2]))
      blk.dungeonRuns, blk.dungeonLegacy = {}, {}
      reopen()
      eq("Sessions answer: with no run in the range the line is the net alone", #(c.summary.segs or {}), 1)
      -- no day row: no line (never a net of 0 for a week with no gold history)
      blk.goldDays, blk.goldMonths = {}, nil
      eq("Sessions answer: no gold day row in the week, no answer", Sess.answer(), nil)
      reopen()
      check("Sessions answer: then the line is not shown and the list starts at the top", not P.visible(c.summary) and near(P.box(c.section).t, P.box(c.col).t, 1))
    end
  end

  -- ── no session at all ──
  do
    local c = P.open("home", "sessions", 900, 580, "normal")
    local keep = ns.DB.sessions
    ns.DB.sessions = {}
    local ok = pcall(reopen)
    check("Sessions empty: one sentence, no header, no answer", ok and c.tbl.stateFS:GetText() == "No session stored yet." and not P.visible(c.section) and not P.visible(c.summary), c.tbl.stateFS:GetText())
    ns.DB.sessions = keep
    reopen()
  end

  -- ── geometry: the list at three sizes on the long data ───────────────────────────────────────────────────────
  for _, size in ipairs({ { 900, 580 }, { 1104, 697 }, { 1600, 1000 } }) do
    local tag = ("Sessions %dx%d"):format(size[1], size[2])
    local c = P.open("home", "sessions", size[1], size[2], "long")
    local tbl = c.tbl
    local trs, days = listed(tbl)
    check(tag .. ": rows under day rows", #trs > 0 and #days > 0, #trs .. "/" .. #days)
    local cut, dash, liveRow = {}, {}, nil
    for _, r in ipairs(trs) do
      if r.item.live then liveRow = r end
      for k, fs in pairs(r.c) do
        if tbl.cols[k] and fs.IsTruncated and fs:IsTruncated() then cut[#cut + 1] = k .. ":" .. tostring(fs.text) end
        if tostring(fs.text or "") == "-" then dash[#dash + 1] = k end
      end
    end
    check(tag .. ": no cell is cut", #cut == 0, table.concat(cut, " | "))
    check(tag .. ": no cell reads a dash", #dash == 0, table.concat(dash, ","))
    local sb, hb, fb = P.box(c.section.label), P.box(tbl.head.date.fs), P.box(tbl.frame)
    check(tag .. ": the header label and the WHEN header share the list's left inset", near(sb.l, fb.l + UI.S.S3, 1) and near(hb.l, fb.l + UI.S.S3, 1), sb.l .. " " .. hb.l .. " " .. fb.l)
    for _, d in ipairs(days) do
      if d.section and not near(P.box(d.section).l, fb.l + UI.S.S3, 1) then check(tag .. ": a day row starts on the same inset", false, P.box(d.section).l) end
    end
    if liveRow then
      local db, tb = P.box(liveRow.ebBadge), P.box(liveRow.c.date)
      check(tag .. ": the LIVE badge sits S2 after the When text", liveRow.ebBadge:IsShown() and near(db.l, tb.l + tb.w + UI.S.S2, 1), db.l .. " vs " .. (tb.l + tb.w))
    end
    -- the numbers of one column end on one x
    for _, k in ipairs({ "len", "xp", "gold", "deaths" }) do
      if tbl.cols[k] then
        local right
        local okAll = true
        for _, r in ipairs(trs) do
          local b = P.box(r.c[k])
          if tostring(r.c[k].text or "") ~= "" then
            if right and not near(b.l + b.w, right, 1) then okAll = false end
            right = right or (b.l + b.w)
          end
        end
        check(tag .. ": the " .. k .. " cells end on one x", okAll)
      end
    end
  end
end
