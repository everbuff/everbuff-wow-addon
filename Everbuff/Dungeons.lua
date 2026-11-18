-- Everbuff.GG · Dungeons.lua - grouped instance RUNS (not per-encounter fights).
--
-- A classic player thinks in RUNS: enter -> clear -> leave. Warcraft Recorder only shows isolated boss
-- pulls; we show the whole run as one card (bosses, wipes, deaths, loot, party, duration) that expands
-- to its encounters, each linking into the existing Fights detail. All from data already captured:
-- Emitter's DUNGEON / DUNGEONLEAVE / KILL / DEATH eventlog + lootlog, and the Fights list.

local ADDON, ns = ...
local UI = ns.UI
local C = ns.UI.C

local listView, detailView, listRebuild

-- ── formatting ──────────────────────────────────────────────────────────────────
local function fmtDur(sec)
  sec = math.floor((tonumber(sec) or 0) + 0.5)
  if sec >= 3600 then return ("%dh %dm"):format(math.floor(sec / 3600), math.floor((sec % 3600) / 60)) end
  if sec >= 60 then return ("%dm %ds"):format(math.floor(sec / 60), sec % 60) end
  return sec .. "s"
end
local fmtMoney = ns.fmtMoney   -- the one formatter (UI.lua)
local RESULT = { kill = { "Kill", C.green }, wipe = { "Wipe", C.red }, death = { "Death", C.red }, fled = { "Fled", C.dim } }
-- loot row quality from its stored hex color ("ff0070dd" = rare); rank drives what counts as notable
local Q_RANK = { ff9d9d9d = 0, ffffffff = 1, ff1eff00 = 2, ff0070dd = 3, ffa335ee = 4, ffff8000 = 5, ffe6cc80 = 6 }
local function qRank(q) return Q_RANK[(q or ""):lower()] or 1 end
local function qColor(q)
  q = (q or "ffffffff"):lower()
  local r, g, b = q:sub(3, 4), q:sub(5, 6), q:sub(7, 8)
  if #q ~= 8 then return C.ink end
  return { (tonumber(r, 16) or 255) / 255, (tonumber(g, 16) or 255) / 255, (tonumber(b, 16) or 255) / 255 }
end

-- ── build the list of runs from the event timeline, enriched with fights/loot/deaths ──
local function nowEpoch() return (GetServerTime and GetServerTime()) or time() end

local function buildRuns()
  local log = ns.mine(ns.DB and ns.DB.story.events)   -- the logged-in character's runs only (#23)
  -- One run per visit to an instance: the two names a client gives one dungeon are one name, and going back in within
  -- REENTER seconds (a wipe and the run back, a repair at the entrance) continues the run instead of starting a new one.
  local canon = (ns.Emitter and ns.Emitter.canonInstance) or function(n) return n end
  local REENTER = 20 * 60
  local runs, open = {}, nil
  for _, e in ipairs(log) do
    if e.kind == "DUNGEON" then
      local name, t = canon(e.text) or "Dungeon", e.t or 0
      if open and open.name ~= name then open.endT = t; open = nil end   -- straight into another instance
      if not open then
        local last = runs[#runs]
        if last and last.name == name and last.endT and t - last.endT <= REENTER then
          open = last; open.endT = nil; open.reentries = (open.reentries or 0) + 1
        else
          open = { name = name, startT = t }
          runs[#runs + 1] = open
        end
      end
    elseif e.kind == "DUNGEONLEAVE" and open then
      open.endT = e.t or open.startT; open = nil
    end
  end
  -- enrich each run window with fights, deaths, kills and loot
  local fightsAll = ns.mine(ns.Fights and ns.Fights.list and ns.Fights.list())
  local lootAll = ns.mine(ns.DB and ns.DB.loot.log)
  for _, run in ipairs(runs) do
    local endT = run.endT or nowEpoch()
    run.inProgress = (run.endT == nil)
    run.duration = math.max(0, endT - run.startT)
    local deaths, kills, deathRows = 0, 0, {}
    for _, e in ipairs(log) do
      local t = e.t or 0
      if t >= run.startT and t <= endT then
        if e.kind == "DEATH" then deaths = deaths + 1; deathRows[#deathRows + 1] = e elseif e.kind == "KILL" then kills = kills + 1 end
      end
    end
    -- loot in the run window: counts for the list, rare-and-better rows for the detail
    local items, gold, notable = 0, 0, {}
    for _, l in ipairs(lootAll) do
      local t = l.t or 0
      if t >= run.startT and t <= endT then
        if l.money then gold = gold + l.money else items = items + 1; if qRank(l.q) >= 3 then notable[#notable + 1] = l end end
      end
    end
    -- fights in the window; bosses grouped by name into attempts (wipes before the kill), in pull order
    local fights, bossesDown, wipes, grp = {}, 0, 0, nil
    local bosses, byBoss = {}, {}
    for _, f in ipairs(fightsAll) do
      local t = f.startEpoch or 0
      if t >= run.startT and t <= endT then
        fights[#fights + 1] = f
        if f.bossName then
          if f.outcome == "kill" then bossesDown = bossesDown + 1 elseif f.outcome == "wipe" then wipes = wipes + 1 end
          local b = byBoss[f.bossName]
          if not b then b = { name = f.bossName, attempts = 0, wipes = 0, deaths = 0, partyDeaths = 0, combat = 0, firstPull = t, fights = {} }; byBoss[f.bossName] = b; bosses[#bosses + 1] = b end
          b.attempts = b.attempts + 1; b.combat = b.combat + (f.duration or 0); b.fights[#b.fights + 1] = f
          b.partyDeaths = b.partyDeaths + (tonumber(f.memberDeaths) or 0)
          if f.outcome == "wipe" then b.wipes = b.wipes + 1 end
          if f.outcome == "death" then b.deaths = b.deaths + 1 end
          if f.outcome == "kill" and not b.killedAt then b.killedAt = t + (f.duration or 0); b.killFight = f end
          if t < b.firstPull then b.firstPull = t end
        end
        if f.group and (not grp or #f.group > #grp) then grp = f.group end
      end
    end
    table.sort(bosses, function(a, b) return a.firstPull < b.firstPull end)
    local partyDeaths = 0
    for _, f in ipairs(fights) do partyDeaths = partyDeaths + (tonumber(f.memberDeaths) or 0) end
    run.partyDeaths = partyDeaths
    run.deaths, run.kills, run.items, run.gold = deaths, kills, items, gold
    run.fights, run.bossesDown, run.wipes, run.group = fights, bossesDown, wipes, grp
    run.bosses, run.deathRows, run.notable = bosses, deathRows, notable
    run.trash = #fights - (function() local n = 0; for _, b in ipairs(bosses) do n = n + b.attempts end; return n end)()
  end
  return runs
end

-- ══ DETAIL VIEW ═════════════════════════════════════════════════════════════════
-- A document laid out for the width it has: every block runs from the list's left to its right edge (W, the scroll
-- child's width), the small tables in it use UI.Columns, and a resize lays the open run out again.
local function buildDetail(content)
  local SP = UI.SP
  local v = CreateFrame("Frame", nil, content); v:SetAllPoints(content); v:Hide()
  local back = UI.Button(v, "< Back", 70, 24, function() v:Hide(); listView:Show(); if listRebuild then listRebuild() end end)
  back:SetPoint("TOPLEFT", SP.M, -SP.M)
  -- title on the Back button's row, meta under it; both anchored on that row's own y so the two points agree
  v.titleFS = UI.FS(v, "GameFontNormalLarge"); v.titleFS:SetPoint("LEFT", back, "RIGHT", SP.M, 0); v.titleFS:SetPoint("RIGHT", v, "TOPRIGHT", -SP.M, -(SP.M + 12))
  v.titleFS:SetJustifyH("LEFT"); if v.titleFS.SetWordWrap then v.titleFS:SetWordWrap(false) end
  v.metaFS = UI.FS(v, "GameFontHighlightSmall", C.dim); v.metaFS:SetPoint("TOPLEFT", back, "BOTTOMLEFT", 2, -SP.S); v.metaFS:SetPoint("TOPRIGHT", v, "TOPRIGHT", -SP.M, -(SP.M + 24 + SP.S)); v.metaFS:SetJustifyH("LEFT")

  local sf, child = UI.ScrollChild(v)
  sf:SetPoint("TOPLEFT", v.metaFS, "BOTTOMLEFT", -2, -SP.M); sf:SetPoint("BOTTOMRIGHT", -(SP.M + UI.SCROLLBAR), SP.M)
  child.fs, child.tex, child.btn = {}, {}, {}
  v.sf, v.child = sf, child
  local W = 600                 -- the content width this render lays out for (the scroll child's)
  local INSET = SP.S
  local fn, tn, bn = 0, 0, 0
  local function cell(x, y, w, text, color, tmpl, justify)
    fn = fn + 1
    local fs = child.fs[fn] or ns.UI.CellFS(child, "GameFontHighlightSmall"); child.fs[fn] = fs
    fs:SetFontObject(ns.UI.Font(tmpl) or ns.UI.BODY_SM or GameFontHighlightSmall); fs:ClearAllPoints(); fs:SetPoint("TOPLEFT", x, -y)
    fs:SetWidth(math.max(1, w)); fs:SetJustifyH(justify or "LEFT"); local c = color or C.ink
    fs:SetText(text or ""); fs:SetTextColor(c[1], c[2], c[3]); fs:Show(); return fs
  end
  -- a cell in a laid-out column
  local function col(cols, key, y, text, color, justify) local c = cols[key]; return cell(c.x, y, c.w, text, color, nil, justify) end
  local function line(y, text, color) return cell(INSET, y, W - INSET, text, color) end
  local function rule(y) tn = tn + 1; local t = child.tex[tn] or child:CreateTexture(nil, "ARTWORK"); child.tex[tn] = t
    t:ClearAllPoints(); t:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y); t:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, -y); t:SetHeight(1)
    t:SetColorTexture(C.line[1], C.line[2], C.line[3], 1); t:Show() end
  local function heading(y, text) cell(0, y + 12, W, text, C.gold, GameFontNormal); rule(y + 32); return y + 40 end
  -- the small tables of the page, laid out per render for W; numbers measured from their widest realistic value
  local BOSS = {
    { key = "boss", flex = 1, min = 100 },
    { key = "att", measure = { "ATTEMPTS", "99  (99 wipes)" } },
    { key = "combat", measure = { "IN COMBAT", "59m 59s", "88m 88s" } },
    { key = "down", measure = { "DOWN AT", "+23h 59m", "+88h 88m" } },
    { key = "res", flex = 1, min = 120 },
  }
  local DEATH = { { key = "t", measure = { "+23h 59m", "+88h 88m" } }, { key = "foe", flex = 1, min = 100 }, { key = "back", flex = 1, min = 100 } }
  local LOOT = { { key = "item", flex = 1, min = 100 }, { key = "count", measure = function()
      local m = { "x999" }   -- and every quantity in the run, so a big stack is never cut
      for _, l in ipairs((v.run and v.run.notable) or {}) do m[#m + 1] = "x" .. tostring(l.count or 1) end
      return m
    end }, { key = "src", flex = 0.7, min = 80 }, { key = "t", measure = { "+23h 59m", "+88h 88m" } } }
  local FIGHT = { { key = "tm", measure = { "23:59:59", "88:88:88" } }, { key = "nm", flex = 1, min = 100 }, { key = "open", measure = { ">" } }, { key = "re", measure = { "Death", "Wipe", "Kill", "Fled" } } }
  local cBoss, cDeath, cLoot, cFight
  -- a clickable encounter row that opens the Fights detail: a Button across the list with a hover highlight
  local function fightRow(y, f)
    bn = bn + 1
    local b = child.btn[bn]
    if not b then
      b = CreateFrame("Button", nil, child)
      b.hl = b:CreateTexture(nil, "HIGHLIGHT"); b.hl:SetAllPoints(); b.hl:SetColorTexture(C.hover[1], C.hover[2], C.hover[3], 0.7)
      b.tm = ns.UI.CellFS(b, "GameFontDisableSmall")
      b.nm = ns.UI.CellFS(b, "GameFontHighlightSmall"); b.nm:SetJustifyH("LEFT")
      b.ar = ns.UI.CellFS(b, "GameFontDisableSmall")
      b.re = ns.UI.CellFS(b, "GameFontHighlightSmall"); b.re:SetJustifyH("LEFT")
      b:SetScript("OnClick", function(s) if ns.OpenFightDetail and s.fight then ns.OpenFightDetail(s.fight) end end)
      child.btn[bn] = b
    end
    b:ClearAllPoints(); b:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y); b:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, -y); b:SetHeight(16)
    for key, fs in pairs({ tm = b.tm, nm = b.nm, open = b.ar, re = b.re }) do
      local c = cFight[key]; fs:ClearAllPoints(); fs:SetPoint("LEFT", b, "LEFT", c.x, 0); fs:SetWidth(c.w)
    end
    b.tm:SetText(date("%H:%M:%S", f.startEpoch or 0)); b.tm:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
    b.nm:SetText(f.bossName or ((f.foes and f.foes[1]) or "fight")); b.nm:SetTextColor(C.ink[1], C.ink[2], C.ink[3])
    b.ar:SetText(">"); b.ar:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
    local rc = RESULT[f.outcome] or RESULT.fled
    b.re:SetText(rc[1]); b.re:SetTextColor(rc[2][1], rc[2][2], rc[2][3])
    b.fight = f; b:Show()
  end

  v.render = function(run)
    v.run = run; fn, tn, bn = 0, 0, 0
    W = math.max(300, sf.contentW or math.floor(tonumber(sf:GetWidth()) or 0))
    v.renderedW = W
    cBoss = UI.Columns(BOSS, W, { inset = INSET })
    cDeath = UI.Columns(DEATH, W, { inset = INSET })
    cLoot = UI.Columns(LOOT, W, { inset = INSET })
    cFight = UI.Columns(FIGHT, W, { inset = INSET })
    v.titleFS:SetText(run.name or "Dungeon")
    v.metaFS:SetText(("%s   ·   %s%s   ·   bosses %d   ·   wipes %d   ·   your deaths %d   ·   party deaths %d"):format(
      date("%b %d, %H:%M", run.startT or 0), fmtDur(run.duration), run.inProgress and "  (in progress)" or "",
      run.bossesDown or 0, run.wipes or 0, run.deaths or 0, run.partyDeaths or 0))
    local y = 0
    -- party
    y = heading(y, "Party")
    if run.group and #run.group > 0 then
      local names = {}
      for _, m in ipairs(run.group) do
        local r, g, b = UI.ClassColor(m.class)
        names[#names + 1] = ("|cff%02x%02x%02x%s|r"):format(math.floor(r * 255), math.floor(g * 255), math.floor(b * 255), m.name or "?")
      end
      line(y, table.concat(names, "   ")); y = y + 18
    else
      line(y, "Solo (no group recorded).", C.dim); y = y + 18
    end
    -- bosses: one row per boss in pull order, with attempts and when in the run it went down
    y = heading(y, ("Bosses  (%d)"):format(#(run.bosses or {})))
    if run.bosses and #run.bosses > 0 then
      col(cBoss, "boss", y, "BOSS", C.dim); col(cBoss, "att", y, "ATTEMPTS", C.dim); col(cBoss, "combat", y, "IN COMBAT", C.dim, "RIGHT")
      col(cBoss, "down", y, "DOWN AT", C.dim, "RIGHT"); col(cBoss, "res", y, "RESULT", C.dim); y = y + 16
      for _, b in ipairs(run.bosses) do
        local killed = b.killedAt ~= nil
        col(cBoss, "boss", y, b.name, C.ink)
        col(cBoss, "att", y, tostring(b.attempts) .. (b.wipes > 0 and ("  (%d wipe%s)"):format(b.wipes, b.wipes == 1 and "" or "s") or ""), b.wipes > 0 and C.red or C.dim)
        col(cBoss, "combat", y, fmtDur(b.combat), C.dim, "RIGHT")
        col(cBoss, "down", y, killed and ("+" .. fmtDur(math.max(0, b.killedAt - (run.startT or 0)))) or "-", C.dim, "RIGHT")
        local res = killed and "Killed" or (b.wipes > 0 and "Wiped" or (b.deaths > 0 and "Died" or "Not killed"))
        local dbits = {}
        if b.deaths > 0 then dbits[#dbits + 1] = ("you died x%d"):format(b.deaths) end
        if (b.partyDeaths or 0) > 0 then dbits[#dbits + 1] = ("%d party death%s"):format(b.partyDeaths, b.partyDeaths == 1 and "" or "s") end
        col(cBoss, "res", y, res .. (#dbits > 0 and ("  ·  " .. table.concat(dbits, ", ")) or ""), killed and C.green or C.red)
        y = y + 16
      end
      if (run.trash or 0) > 0 then line(y + 2, ("%d trash pull%s recorded between bosses"):format(run.trash, run.trash == 1 and "" or "s"), C.dim); y = y + 18 end
    else
      line(y, "No boss encounters recorded in this run.", C.dim); y = y + 18
    end
    -- deaths
    y = heading(y, ("Deaths  (%d)"):format(run.deaths or 0))
    if run.deathRows and #run.deathRows > 0 then
      for _, d in ipairs(run.deathRows) do
        local dn = tonumber(d.downtime)
        col(cDeath, "t", y, "+" .. fmtDur(math.max(0, (d.t or 0) - (run.startT or 0))), C.dim, "RIGHT")
        col(cDeath, "foe", y, "slain by " .. (d.foe or "unknown"), C.red)
        col(cDeath, "back", y, dn and ("back on your feet after " .. fmtDur(dn)) or "", C.dim)
        y = y + 16
      end
    else
      line(y, "Deathless run.", C.green); y = y + 16
    end
    -- loot: totals plus every rare-and-better drop
    y = heading(y, "Loot")
    line(y, ("%d item%s  ·  %s"):format(run.items or 0, (run.items == 1) and "" or "s", fmtMoney(run.gold or 0)), C.gold); y = y + 20
    if run.notable and #run.notable > 0 then
      for _, l in ipairs(run.notable) do
        local icon = l.icon and ("|T" .. tostring(l.icon) .. ":14:14:0:0|t ") or ""
        col(cLoot, "item", y, icon .. (l.item or "?"), qColor(l.q))
        col(cLoot, "count", y, (l.count or 1) > 1 and ("x" .. l.count) or "", C.dim, "RIGHT")
        col(cLoot, "src", y, l.src or "", C.dim)
        col(cLoot, "t", y, "+" .. fmtDur(math.max(0, (l.t or 0) - (run.startT or 0))), C.dim, "RIGHT")
        y = y + 16
      end
    else
      line(y, "No rare or better drops in this run.", C.dim); y = y + 16
    end
    -- encounters
    y = heading(y, ("Encounters  (%d)"):format(#(run.fights or {})))
    if run.fights and #run.fights > 0 then
      for i = #run.fights, 1, -1 do fightRow(y, run.fights[i]); y = y + 16 end
    else
      line(y, "No fights recorded in this run.", C.dim); y = y + 16
    end
    for j = fn + 1, #child.fs do child.fs[j]:Hide() end
    for j = tn + 1, #child.tex do child.tex[j]:Hide() end
    for j = bn + 1, #child.btn do child.btn[j]:Hide() end
    sf:SetContentHeight(y + 12)
  end
  -- a new width lays the open run out again
  sf.onResize = function() if v.run and v:IsShown() then pcall(v.render, v.run) end end
  v:HookScript("OnShow", function() if v.run and sf.contentW and v.renderedW ~= sf.contentW then pcall(v.render, v.run) end end)
  return v
end

local function openRun(run) listView:Hide(); detailView.render(run); detailView:Show() end

-- ══ LIST VIEW ═══════════════════════════════════════════════════════════════════
local function buildList(content)
  local v = CreateFrame("Frame", nil, content); v:SetAllPoints(content)
  -- lockouts: which instances this character is saved to, and when they reset (wraps; the list moves down with it)
  local lock = UI.SummaryLine(v, C.gold, nil, true)
  v.lockFS = lock
  local function lockText()
    local L = (ns.DB and ns.char().lockouts) or {}
    if #L == 0 then return "|cff8c9197Not saved to any instance.|r" end
    local nowT = (GetServerTime and GetServerTime()) or time()
    local bits = {}
    for _, l in ipairs(L) do
      local left = math.max(0, (l.resetAt or nowT) - nowT)
      local when = left >= 86400 and ("%dd %dh"):format(math.floor(left / 86400), math.floor((left % 86400) / 3600)) or ("%dh %dm"):format(math.floor(left / 3600), math.floor((left % 3600) / 60))
      local prog = (l.bosses and l.down) and (" %d/%d"):format(l.down, l.bosses) or ""
      bits[#bits + 1] = ("%s%s |cff8c9197resets in %s|r"):format(l.name or "?", prog, when)
    end
    return "Saved to:  " .. table.concat(bits, "   ·   ")
  end
  v.lockText = lockText
  -- Time · Dungeon · (in progress) · Length · Bosses · Deaths · Loot
  local tbl = UI.Table(UI.Below(v, lock), {
    { key = "time", label = "Time", kind = "tag", color = "dim", measure = { "12/31 23:59" } },
    { key = "name", label = "Dungeon", flex = 1, min = 120 },
    { key = "live", label = "", kind = "tag", color = "green", measure = { "•" } },
    { key = "dur", label = "Length", kind = "num", color = "dim", measure = { "23h 59m" } },
    { key = "boss", label = "Bosses", kind = "num", measure = { "99" } },
    { key = "death", label = "Deaths", kind = "num", color = "dim", measure = { "99" } },
    { key = "loot", label = "Loot", kind = "money", color = "gold", measure = { "999 · " .. fmtMoney(9999999) } },
  }, { top = 0, emptyText = "No dungeon runs yet. Enter a dungeon and it shows up here.",
    onClick = function(row) if row.run then openRun(row.run) end end })
  v.tbl = tbl

  listRebuild = function()
    lock:SetText(lockText())
    local runs, rows = buildRuns(), {}
    for i = #runs, 1, -1 do rows[#rows + 1] = runs[i] end
    tbl.setRows(rows, function(row, run)
      row.run = run
      row.c.time:SetText(date("%m/%d %H:%M", run.startT or 0))
      row.c.name:SetText(run.name or "?")
      row.c.live:SetText(run.inProgress and "•" or "")
      row.c.dur:SetText(fmtDur(run.duration))
      row.c.boss:SetText(tostring(run.bossesDown or 0))
      row.c.death:SetText(tostring(run.deaths or 0))
      if (run.deaths or 0) > 0 then row.c.death:SetTextColor(C.red[1], C.red[2], C.red[3]) end
      row.c.loot:SetText(((run.items or 0) > 0 and (run.items .. " · ") or "") .. fmtMoney(run.gold or 0))
    end)
  end

  listRebuild()
  return v
end
local ticker
UI.registerHost(1, "Combat", "Every dungeon run, every fight and every death, each with a replay you can scrub.")
UI.registerPane("Combat", 1, "Dungeons", function(content)
  listView = buildList(content)
  detailView = buildDetail(content)
end, function()
  if detailView and detailView:IsShown() then return end
  if listRebuild then listRebuild() end
  if not ticker then ticker = C_Timer.NewTicker(3, function()
    if listView and listView:IsShown() and listRebuild then listRebuild() end
  end) end
end)

-- ── test exports: headless luajit tests in tests/ read these; no effect in-game ──
ns._test = ns._test or {}
ns.DungeonRuns = buildRuns
ns._test.buildRuns = buildRuns
ns._test.dungeonsLockText = function() return listView and listView.lockText and listView.lockText() or nil end
ns._test.renderRun = function(run) if detailView then detailView.render(run); detailView:Show(); detailView:Hide() end end
ns._test.dungeonDetail = function() return detailView end
ns._test.openRun = function(run) openRun(run) end
