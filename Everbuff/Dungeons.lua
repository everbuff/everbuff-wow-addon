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
local function fmtMoney(c)
  c = math.floor(tonumber(c) or 0)
  local g, s, cp = math.floor(c / 10000), math.floor((c % 10000) / 100), c % 100
  local out = {}
  if g > 0 then out[#out + 1] = g .. "g" end
  if s > 0 then out[#out + 1] = s .. "s" end
  if cp > 0 or #out == 0 then out[#out + 1] = cp .. "c" end
  return table.concat(out, " ")
end
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
  local log = (ns.DB and ns.DB.story.events) or {}
  local runs, open = {}, nil
  for _, e in ipairs(log) do
    if e.kind == "DUNGEON" then
      open = { name = e.text or "Dungeon", startT = e.t or 0 }
      runs[#runs + 1] = open
    elseif e.kind == "DUNGEONLEAVE" and open then
      open.endT = e.t or open.startT; open = nil
    end
  end
  -- enrich each run window with fights, deaths, kills and loot
  local fightsAll = (ns.Fights and ns.Fights.list and ns.Fights.list()) or {}
  local lootAll = (ns.DB and ns.DB.loot.log) or {}
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
local function buildDetail(content)
  local v = CreateFrame("Frame", nil, content); v:SetAllPoints(content); v:Hide()
  local back = UI.Button(v, "< Back", 70, 24, function() v:Hide(); listView:Show(); if listRebuild then listRebuild() end end)
  back:SetPoint("TOPLEFT", 12, -12)
  v.titleFS = UI.FS(v, "GameFontNormalLarge"); v.titleFS:SetPoint("TOPLEFT", 92, -14); v.titleFS:SetWidth(600); v.titleFS:SetJustifyH("LEFT")
  v.metaFS = UI.FS(v, "GameFontHighlightSmall", C.dim); v.metaFS:SetPoint("TOPLEFT", 14, -42); v.metaFS:SetWidth(700); v.metaFS:SetJustifyH("LEFT")

  local sf, child = UI.ScrollChild(v)
  sf:SetPoint("TOPLEFT", 12, -66); sf:SetPoint("BOTTOMRIGHT", -28, 12)
  child.fs, child.tex, child.btn = {}, {}, {}
  local WIDTH = 700
  local fn, tn, bn = 0, 0, 0
  local function cell(x, y, w, text, color, tmpl)
    fn = fn + 1
    local fs = child.fs[fn] or ns.UI.FS(child, "GameFontHighlightSmall"); child.fs[fn] = fs
    fs:SetFontObject(ns.UI.Font(tmpl) or ns.UI.BODY_SM or GameFontHighlightSmall); fs:ClearAllPoints(); fs:SetPoint("TOPLEFT", x, -y)
    fs:SetWidth(w); fs:SetJustifyH("LEFT"); local c = color or C.ink
    fs:SetText(text or ""); fs:SetTextColor(c[1], c[2], c[3]); fs:Show(); return fs
  end
  local function rule(y) tn = tn + 1; local t = child.tex[tn] or child:CreateTexture(nil, "ARTWORK"); child.tex[tn] = t
    t:ClearAllPoints(); t:SetPoint("TOPLEFT", 0, -y); t:SetSize(WIDTH, 1); t:SetColorTexture(C.line[1], C.line[2], C.line[3], 1); t:Show() end
  local function heading(y, text) cell(0, y + 12, WIDTH, text, C.gold, GameFontNormal); rule(y + 32); return y + 40 end
  -- a clickable encounter row that opens the Fights detail
  local function fightRow(y, f)
    bn = bn + 1
    local b = child.btn[bn]
    if not b then
      b = CreateFrame("Button", nil, child)
      b.hl = b:CreateTexture(nil, "BACKGROUND"); b.hl:SetAllPoints(); b.hl:SetColorTexture(C.panel2[1], C.panel2[2], C.panel2[3], 0)
      b.tm = ns.UI.FS(b, "GameFontDisableSmall"); b.tm:SetPoint("LEFT", 0, 0); b.tm:SetWidth(64)
      b.nm = ns.UI.FS(b, "GameFontHighlightSmall"); b.nm:SetPoint("LEFT", 70, 0); b.nm:SetWidth(360); b.nm:SetJustifyH("LEFT")
      b.re = ns.UI.FS(b, "GameFontHighlightSmall"); b.re:SetPoint("LEFT", 440, 0); b.re:SetWidth(120); b.re:SetJustifyH("LEFT")
      b:SetScript("OnEnter", function(s) s.hl:SetColorTexture(C.panel2[1], C.panel2[2], C.panel2[3], 0.6) end)
      b:SetScript("OnLeave", function(s) s.hl:SetColorTexture(0, 0, 0, 0) end)
      b:SetScript("OnClick", function(s) if ns.OpenFightDetail and s.fight then ns.OpenFightDetail(s.fight) end end)
      child.btn[bn] = b
    end
    b:SetSize(WIDTH, 16); b:ClearAllPoints(); b:SetPoint("TOPLEFT", 0, -y)
    b.tm:SetText(date("%H:%M:%S", f.startEpoch or 0)); b.tm:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
    local nm = f.bossName or ((f.foes and f.foes[1]) or "fight")
    b.nm:SetText(nm .. "   |cff8a96a6>|r"); b.nm:SetTextColor(C.ink[1], C.ink[2], C.ink[3])
    local rc = RESULT[f.outcome] or RESULT.fled
    b.re:SetText(rc[1]); b.re:SetTextColor(rc[2][1], rc[2][2], rc[2][3])
    b.fight = f; b:Show()
  end

  v.render = function(run)
    v.run = run; fn, tn, bn = 0, 0, 0
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
      cell(8, y, WIDTH - 8, table.concat(names, "   ")); y = y + 18
    else
      cell(8, y, WIDTH - 8, "Solo (no group recorded).", C.dim); y = y + 18
    end
    -- bosses: one row per boss in pull order, with attempts and when in the run it went down
    y = heading(y, ("Bosses  (%d)"):format(#(run.bosses or {})))
    if run.bosses and #run.bosses > 0 then
      cell(8, y, 220, "BOSS", C.dim); cell(236, y, 80, "ATTEMPTS", C.dim); cell(320, y, 90, "IN COMBAT", C.dim); cell(414, y, 120, "DOWN AT", C.dim); cell(540, y, 150, "RESULT", C.dim); y = y + 16
      for _, b in ipairs(run.bosses) do
        local killed = b.killedAt ~= nil
        cell(8, y, 220, b.name, C.ink)
        cell(236, y, 80, tostring(b.attempts) .. (b.wipes > 0 and ("  (%d wipe%s)"):format(b.wipes, b.wipes == 1 and "" or "s") or ""), b.wipes > 0 and C.red or C.dim)
        cell(320, y, 90, fmtDur(b.combat), C.dim)
        cell(414, y, 120, killed and ("+" .. fmtDur(math.max(0, b.killedAt - (run.startT or 0)))) or "-", C.dim)
        local res = killed and "Killed" or (b.wipes > 0 and "Wiped" or (b.deaths > 0 and "Died" or "Not killed"))
        local dbits = {}
        if b.deaths > 0 then dbits[#dbits + 1] = ("you died x%d"):format(b.deaths) end
        if (b.partyDeaths or 0) > 0 then dbits[#dbits + 1] = ("%d party death%s"):format(b.partyDeaths, b.partyDeaths == 1 and "" or "s") end
        cell(540, y, 150, res .. (#dbits > 0 and ("  ·  " .. table.concat(dbits, ", ")) or ""), killed and C.green or C.red)
        y = y + 16
      end
      if (run.trash or 0) > 0 then cell(8, y + 2, WIDTH - 8, ("%d trash pull%s recorded between bosses"):format(run.trash, run.trash == 1 and "" or "s"), C.dim); y = y + 18 end
    else
      cell(8, y, WIDTH - 8, "No boss encounters recorded in this run.", C.dim); y = y + 18
    end
    -- deaths
    y = heading(y, ("Deaths  (%d)"):format(run.deaths or 0))
    if run.deathRows and #run.deathRows > 0 then
      for _, d in ipairs(run.deathRows) do
        local dn = tonumber(d.downtime)
        cell(8, y, 70, "+" .. fmtDur(math.max(0, (d.t or 0) - (run.startT or 0))), C.dim)
        cell(84, y, 300, "slain by " .. (d.foe or "unknown"), C.red)
        cell(390, y, 300, dn and ("back on your feet after " .. fmtDur(dn)) or "", C.dim)
        y = y + 16
      end
    else
      cell(8, y, WIDTH - 8, "Deathless run.", C.green); y = y + 16
    end
    -- loot: totals plus every rare-and-better drop
    y = heading(y, "Loot")
    cell(8, y, WIDTH - 8, ("%d item%s  ·  %s"):format(run.items or 0, (run.items == 1) and "" or "s", fmtMoney(run.gold or 0)), C.gold); y = y + 20
    if run.notable and #run.notable > 0 then
      for _, l in ipairs(run.notable) do
        local icon = l.icon and ("|T" .. tostring(l.icon) .. ":14:14:0:0|t ") or ""
        cell(8, y, 320, icon .. (l.item or "?") .. ((l.count or 1) > 1 and (" x" .. l.count) or ""), qColor(l.q))
        cell(336, y, 200, l.src or "", C.dim)
        cell(540, y, 150, "+" .. fmtDur(math.max(0, (l.t or 0) - (run.startT or 0))), C.dim)
        y = y + 16
      end
    else
      cell(8, y, WIDTH - 8, "No rare or better drops in this run.", C.dim); y = y + 16
    end
    -- encounters
    y = heading(y, ("Encounters  (%d)"):format(#(run.fights or {})))
    if run.fights and #run.fights > 0 then
      for i = #run.fights, 1, -1 do fightRow(y, run.fights[i]); y = y + 16 end
    else
      cell(8, y, WIDTH - 8, "No fights recorded in this run.", C.dim); y = y + 16
    end
    for j = fn + 1, #child.fs do child.fs[j]:Hide() end
    for j = tn + 1, #child.tex do child.tex[j]:Hide() end
    for j = bn + 1, #child.btn do child.btn[j]:Hide() end
    child:SetSize(WIDTH, math.max(1, y + 12))
  end
  return v
end

local function openRun(run) listView:Hide(); detailView.render(run); detailView:Show() end

-- ══ LIST VIEW ═══════════════════════════════════════════════════════════════════
local function buildList(content)
  local v = CreateFrame("Frame", nil, content); v:SetAllPoints(content)

  local COL = { time = 0, name = 70, dur = 300, boss = 388, death = 478, loot = 556 }
  -- lockouts: which instances this character is saved to, and when they reset
  local lock = UI.FS(v, "GameFontHighlightSmall", C.gold); lock:SetPoint("TOPLEFT", 2, -6); lock:SetWidth(660); lock:SetJustifyH("LEFT")
  v.lockFS = lock
  local function lockText()
    local L = (ns.DB and ns.DB.character and ns.DB.character.lockouts) or {}
    if #L == 0 then return "|cff8c9aa3Not saved to any instance.|r" end
    local nowT = (GetServerTime and GetServerTime()) or time()
    local bits = {}
    for _, l in ipairs(L) do
      local left = math.max(0, (l.resetAt or nowT) - nowT)
      local when = left >= 86400 and ("%dd %dh"):format(math.floor(left / 86400), math.floor((left % 86400) / 3600)) or ("%dh %dm"):format(math.floor(left / 3600), math.floor((left % 3600) / 60))
      local prog = (l.bosses and l.down) and (" %d/%d"):format(l.down, l.bosses) or ""
      bits[#bits + 1] = ("%s%s |cff8c9aa3resets in %s|r"):format(l.name or "?", prog, when)
    end
    return "Saved to:  " .. table.concat(bits, "   ·   ")
  end
  v.lockText = lockText
  local hdr = CreateFrame("Frame", nil, v); hdr:SetPoint("TOPLEFT", 2, -26); hdr:SetSize(660, 16)
  local function head(col, text)
    local fs = ns.UI.FS(hdr, "GameFontDisableSmall")
    fs:SetPoint("LEFT", col, 0); fs:SetText(text); fs:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
  end
  head(COL.time, "Time"); head(COL.name, "Dungeon"); head(COL.dur, "Length")
  head(COL.boss, "Bosses"); head(COL.death, "Deaths"); head(COL.loot, "Loot")

  local sf, child = UI.ScrollChild(v)
  sf:SetPoint("TOPLEFT", 0, -46); sf:SetPoint("BOTTOMRIGHT", -22, 2)
  child.rows = {}

  listRebuild = function()
    lock:SetText(lockText())
    local runs = buildRuns()
    local y, idx = 0, 0
    for i = #runs, 1, -1 do
      idx = idx + 1
      local run = runs[i]
      local row = child.rows[idx]
      if not row then
        row = CreateFrame("Button", nil, child, "BackdropTemplate"); row:SetHeight(20); row:SetPoint("RIGHT", child, "RIGHT", 0, 0)
        row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" }); row:SetBackdropColor(0, 0, 0, 0)
        row:SetScript("OnEnter", function(s) s:SetBackdropColor(C.panel2[1], C.panel2[2], C.panel2[3], 0.6) end)
        row:SetScript("OnLeave", function(s) s:SetBackdropColor(0, 0, 0, 0) end)
        row:SetScript("OnClick", function(s) if s.run then openRun(s.run) end end)
        row.cells = {}
        for _, key in ipairs({ "time", "name", "dur", "boss", "death", "loot" }) do
          local fs = ns.UI.FS(row, "GameFontHighlightSmall")
          fs:SetPoint("LEFT", COL[key], 0); fs:SetJustifyH("LEFT"); row.cells[key] = fs
        end
        row.cells.name:SetWidth(224); row.cells.time:SetWidth(64)
        child.rows[idx] = row
      end
      row.run = run; row:SetPoint("TOPLEFT", 0, -y); row:Show()
      row.cells.time:SetText(date("%m/%d %H:%M", run.startT or 0)); row.cells.time:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
      row.cells.name:SetText((run.name or "?") .. (run.inProgress and "  |cff47c97e•|r" or "")); row.cells.name:SetTextColor(C.ink[1], C.ink[2], C.ink[3])
      row.cells.dur:SetText(fmtDur(run.duration)); row.cells.dur:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
      row.cells.boss:SetText(tostring(run.bossesDown or 0)); row.cells.boss:SetTextColor(C.ink[1], C.ink[2], C.ink[3])
      row.cells.death:SetText(tostring(run.deaths or 0))
      local dc = (run.deaths or 0) > 0 and C.red or C.dim
      row.cells.death:SetTextColor(dc[1], dc[2], dc[3])
      row.cells.loot:SetText(((run.items or 0) > 0 and (run.items .. " · ") or "") .. fmtMoney(run.gold or 0))
      row.cells.loot:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
      y = y + 20
    end
    for j = idx + 1, #child.rows do child.rows[j]:Hide() end
    if idx == 0 then
      child.empty = child.empty or (function()
        local fs = ns.UI.FS(child, "GameFontDisableSmall")
        fs:SetPoint("TOPLEFT", 0, 0); fs:SetText("No dungeon runs yet. Enter a dungeon and it shows up here."); return fs
      end)()
      child.empty:Show()
    elseif child.empty then child.empty:Hide() end
    child:SetSize(math.max(660, (sf:GetWidth() or 660) - 4), math.max(1, y))
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
