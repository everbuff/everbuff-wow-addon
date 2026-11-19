-- Everbuff.GG · Dungeons.lua - Combat > Dungeons: the stored dungeon runs (not per-encounter fights).
--
-- A classic player thinks in RUNS: enter -> clear -> leave. From 0.9.50 a run is a stored record of the character
-- (Runs.lua: characters[guid].dungeonRun and dungeonRuns), so the list survives the desktop's acknowledgement and
-- the story event cap. This pane only reads: the list is one row per run, the page shows its clocks, bosses,
-- deaths, loot and XP, and the fights still stored open in the Fights detail.

local ADDON, ns = ...
local UI = ns.UI
local C = ns.UI.C
local Runs = ns.Runs

local listView, detailView, listRebuild

-- ── formatting ──────────────────────────────────────────────────────────────────
local fmtDur = Runs.fmtDur
local fmtMoney = ns.fmtMoney   -- the one formatter (UI.lua)
-- what the open run of the character is now, straight from the store (a row of the list can be seconds old)
local function openRec()
  local c = ns.DB and ns.charGuid and ns.charGuid() and ns.char() or nil
  local r = c and c.dungeonRun
  return type(r) == "table" and r or nil
end
-- a frame counts as on screen only when its parents show too (IsShown is the frame's own flag)
local function onScreen(f)
  if not f then return false end
  if f.IsVisible then return f:IsVisible() and true or false end
  return f:IsShown() and true or false
end
local function qColor(q)
  q = (q or "ffffffff"):lower()
  local r, g, b = q:sub(3, 4), q:sub(5, 6), q:sub(7, 8)
  if #q ~= 8 then return C.ink end
  return { (tonumber(r, 16) or 255) / 255, (tonumber(g, 16) or 255) / 255, (tonumber(b, 16) or 255) / 255 }
end
local function n0(v) return type(v) == "number" and v or 0 end
-- "23,000 XP/h" while the run has XP, else coin per hour; "" before a rate is known
local function perHour(run)
  if run.xpPerHour then return Runs.commas(run.xpPerHour) .. " XP/h" end
  if run.coinPerHour and n0(run.coin) > 0 then
    return ((ns.Gold and ns.Gold.fmt) and ns.Gold.fmt(run.coinPerHour, { rate = true }) or fmtMoney(math.floor(run.coinPerHour))) .. "/h"
  end
  return ""
end
-- the loot line of a run: its own gold block through the Gold pane's formatter
local function lootLine(run)
  local g = run.gold
  if type(g) ~= "table" then return ("%d item%s  ·  %s"):format(n0(run.items), (run.items == 1) and "" or "s", fmtMoney(n0(run.coin))) end
  local r = { items = n0(g.items), coin = n0(g.looted) + n0(g.quests), lootValue = n0(g.lootValue), unpriced = n0(g.unpriced), perHour = run.coinPerHour }
  if ns.Gold and ns.Gold.runLine then return ns.Gold.runLine(r) end
  return ("%d item%s  ·  %s"):format(r.items, r.items == 1 and "" or "s", fmtMoney(r.coin))
end
local function bossName(run, enc)
  for _, b in ipairs(run.bosses or {}) do if b.enc == enc then return b.name or "Boss" end end
  return nil
end
local SEP = "  ·  "
-- The delta of a run against the best, as the LENGTH column and the TIME tile say it: "+3:29 ↑" (slower than the
-- best), "-0:42 ↓" (faster), "best", "first run here", or "" (nothing to compare with). The arrow and the sign
-- carry it; the colour only repeats it. A closed run compares only on its own route; the run in progress against
-- the best at the same boss.
-- (`short`: the list's LENGTH cell, where "first run here" reads "first run": seven columns fit 900 px only so)
local function deltaWord(run, short)
  local cmp = run.cmp
  local FIRST = short and "first run" or "first run here"
  if not cmp then return "", C.dim end
  if cmp.mode == "same" then
    if cmp.isBest then return cmp.first and FIRST or "best", C.gold end
    return Runs.deltaText(cmp.delta), cmp.delta > 0 and C.red or C.green
  end
  if cmp.mode == "prefix" and run.inProgress then return Runs.deltaText(cmp.delta), cmp.delta > 0 and C.red or C.green end
  if not run.inProgress and cmp.first then return FIRST, C.dim end
  return "", C.dim
end
-- "5" until the dungeon has a learned boss list, then "5/7"
local function bossText(run)
  if run.total then return ("%d/%d"):format(n0(run.bossesDown), run.total) end
  return tostring(n0(run.bossesDown))
end
-- The Pace lines of a run: "Best 28m 41s on 14 Nov  ·  this run +3:29 ↑" and the sum of the best segments when
-- every segment of this run's own order of kills is known; or, with no best on its route, against the best of the
-- route that shares its start: "At boss 3 of 5: best 12m 10s on 14 Nov  ·  this run +0:41 ↑". nil with no best.
local function paceLines(run)
  local cmp = run.cmp
  if not (cmp and cmp.mode and cmp.delta and run.cleared) then return nil end   -- (absent before a first full clear)
  local when = date("%d %b", cmp.bestAt or 0)
  if cmp.mode == "same" then
    local l1 = ("Best %s on %s"):format(fmtDur(cmp.best), when) .. SEP .. (cmp.isBest and "this run is the best" or ("this run " .. Runs.deltaText(cmp.delta)))
    return l1, cmp.sumBest and ("Sum of best segments " .. fmtDur(cmp.sumBest)) or nil
  end
  return ("At boss %d of %d: best %s on %s"):format(cmp.at, cmp.of, fmtDur(cmp.best), when) .. SEP .. "this run " .. Runs.deltaText(cmp.delta), nil
end
-- the lockouts of the account's other characters, for the hover of the "Saved to" line (plan decision 14)
local function otherLockouts()
  local out, mine = {}, ns.charGuid and ns.charGuid()
  local nowT = (GetServerTime and GetServerTime()) or time()
  for guid, ch in pairs(ns.DB and type(ns.DB.characters) == "table" and ns.DB.characters or {}) do
    if guid ~= mine and type(ch) == "table" and type(ch.lockouts) == "table" then
      for _, l in ipairs(ch.lockouts) do
        if type(l) == "table" and n0(l.resetAt) > nowT then
          local left = l.resetAt - nowT
          local when = left >= 86400 and ("%dd %dh"):format(math.floor(left / 86400), math.floor((left % 86400) / 3600)) or ("%dh %dm"):format(math.floor(left / 3600), math.floor((left % 3600) / 60))
          local prog = (l.bosses and l.down) and (" %d/%d"):format(l.down, l.bosses) or ""
          out[#out + 1] = { who = ch.name or "?", text = ("%s: %s%s, resets in %s"):format(ch.name or "?", l.name or "?", prog, when) }
        end
      end
    end
  end
  table.sort(out, function(a, b) if a.who ~= b.who then return a.who < b.who end return a.text < b.text end)
  local lines = {}
  for _, x in ipairs(out) do lines[#lines + 1] = x.text end
  return lines
end

-- ══ DETAIL VIEW ═════════════════════════════════════════════════════════════════
-- A document laid out for the width it has: every block runs from the list's left to its right edge (W, the scroll
-- child's width), the small tables in it use UI.Columns, and a resize lays the open run out again.
local function buildDetail(content)
  local SP = UI.SP
  local v = CreateFrame("Frame", nil, content); v:SetAllPoints(content); v:Hide()
  local back = UI.Button(v, "< Back", 70, 24, function() v.toList() end)
  back:SetPoint("TOPLEFT", SP.M, -SP.M)
  -- title on the Back button's row, meta under it; both anchored on that row's own y so the two points agree
  v.titleFS = UI.FS(v, "GameFontNormalLarge"); v.titleFS:SetPoint("LEFT", back, "RIGHT", SP.M, 0); v.titleFS:SetPoint("RIGHT", v, "TOPRIGHT", -SP.M, -(SP.M + 12))
  v.titleFS:SetJustifyH("LEFT"); if v.titleFS.SetWordWrap then v.titleFS:SetWordWrap(false) end
  v.metaFS = UI.FS(v, "GameFontHighlightSmall", C.dim); v.metaFS:SetPoint("TOPLEFT", back, "BOTTOMLEFT", 2, -SP.S); v.metaFS:SetPoint("TOPRIGHT", v, "TOPRIGHT", -SP.M, -(SP.M + 24 + SP.S)); v.metaFS:SetJustifyH("LEFT")

  local sf, child = UI.ScrollChild(v)
  sf:SetPoint("TOPLEFT", v.metaFS, "BOTTOMLEFT", -2, -SP.M); sf:SetPoint("BOTTOMRIGHT", -(SP.M + UI.SCROLLBAR), SP.M)
  child.fs, child.tex, child.btn, child.bbtn, child.abtn = {}, {}, {}, {}, {}
  v.sf, v.child = sf, child
  local W = 600                 -- the content width this render lays out for (the scroll child's)
  local INSET = SP.S
  local fn, tn, bn, bbn, abn = 0, 0, 0, 0, 0
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
  local TILE = { { key = "time", flex = 1, min = 60 }, { key = "boss", flex = 1, min = 60 }, { key = "death", flex = 1, min = 60 }, { key = "rate", flex = 1, min = 60 } }
  local BOSS = {
    { key = "boss", flex = 3, min = 100 },
    { key = "pulls", measure = { "PULLS", "99" } },
    { key = "combat", measure = { "IN COMBAT", "59m 59s", "88m 88s" } },
    { key = "down", measure = { "DOWN AT", "+23h 59m", "+88h 88m" } },
    { key = "seg", measure = { "SEGMENT", "59m 59s", "88m 88s" } },
    { key = "vs", measure = { "VS BEST", "+88:88 ↑", "-88:88 ↓" } },
    { key = "res", flex = 2, min = 110 },
  }
  local VISIT = { { key = "n", measure = { "VISIT", "20" } }, { key = "at", measure = { "AT", "+23h 59m", "+88h 88m" } },
    { key = "len", measure = { "INSIDE", "23h 59m", "88m 88s" } }, { key = "how", flex = 1, min = 80 }, { key = "act", measure = { "Yes, split here", "Split here" } } }
  -- deaths: "slain by" and "back after" are columns of their own, each there only when a row of the run has it
  local function deathCols(rows)
    local spec = { { key = "t", measure = { "AT", "+23h 59m", "+88h 88m" } }, { key = "who", measure = { "WHO", "You" } }, { key = "where", flex = 1, min = 100 } }
    local foe, back = false, false
    for _, d in ipairs(rows or {}) do foe, back = foe or d.foe ~= nil, back or d.back ~= nil end
    if foe then spec[#spec + 1] = { key = "foe", flex = 1.4, min = 100 } end
    if back then spec[#spec + 1] = { key = "back", measure = { "BACK AFTER", "59m 59s", "88m 88s", "23h 59m" } } end
    return spec
  end
  local LOOT = { { key = "item", flex = 1, min = 100 }, { key = "count", measure = function()
      local m = { "x999" }   -- and every quantity in the run, so a big stack is never cut
      for _, l in ipairs((v.run and v.run.notable) or {}) do m[#m + 1] = "x" .. tostring(l.count or 1) end
      return m
    end }, { key = "src", flex = 0.7, min = 80 }, { key = "t", measure = { "23:59:59", "88:88:88" } } }
  local FIGHT = { { key = "tm", measure = { "23:59:59", "88:88:88" } }, { key = "nm", flex = 1, min = 100 }, { key = "open", measure = { ">" } }, { key = "re", measure = { "Death", "Wipe", "Kill", "Fled", "Trash" } } }
  local cTile, cBoss, cDeath, cLoot, cFight, cVisit
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
    local rc = ns.FightResult(f)
    b.re:SetText(rc[1]); b.re:SetTextColor(rc[2][1], rc[2][2], rc[2][3])
    b.fight = f; b:Show()
  end
  -- a boss row whose fight is still stored opens it: a Button over the row, text-less, with the hover highlight
  local function bossButton(y, f)
    bbn = bbn + 1
    local b = child.bbtn[bbn]
    if not b then
      b = CreateFrame("Button", nil, child)
      b.hl = b:CreateTexture(nil, "HIGHLIGHT"); b.hl:SetAllPoints(); b.hl:SetColorTexture(C.hover[1], C.hover[2], C.hover[3], 0.7)
      b:SetScript("OnClick", function(s2) if ns.OpenFightDetail and s2.fight then ns.OpenFightDetail(s2.fight) end end)
      child.bbtn[bbn] = b
    end
    b:ClearAllPoints(); b:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y); b:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, -y); b:SetHeight(16)
    b.fight = f; b:Show()
  end
  -- The buttons of the page (Keep, End run now, Join with previous run, Delete run, and Split here on a visit):
  -- pooled, laid out per render. A button that changes the record asks first, in the page (two clicks: the first
  -- shows the question and turns the button into "Yes, ..."; a second click within 8 seconds does it).
  v.pending = nil
  local function actBtn(x, y, w, label, onClick)
    abn = abn + 1
    local b = child.abtn[abn]
    if not b then
      b = UI.Button(child, "", 60, 20, function(s2) if s2.ebAct then s2.ebAct() end end)
      child.abtn[abn] = b
    end
    b.text:SetText(label); UI.FitButton(b, w or 60)
    b:ClearAllPoints(); b:SetPoint("TOPLEFT", child, "TOPLEFT", x, -y)
    b.ebAct, b.label, b.key, b.visit = onClick, label, nil, nil   -- (a pooled button forgets what it was before)
    b:Show()
    return b
  end
  v.actBtns = function()
    local out = {}
    for i = 1, abn do out[#out + 1] = child.abtn[i] end
    return out
  end
  -- what a refused action says, on the page under the buttons
  local REFUSED = {
    cap = ("%d runs are kept already. Unkeep one first."):format(Runs.KEEP_CAP),
    old = "This run was stored before version 0.9.51 with more than one kind of time outside, so it cannot be split or joined.",
    evicted = "A run between these two is no longer in the list, so they cannot be joined.",
    none = "There is no stored run before this one.",
    other = "The run before this one is of another dungeon.",
    visits = ("Together they would have more than %d visits."):format(Runs.VISIT_CAP),
    bosses = ("Together they would have more than %d bosses."):format(Runs.BOSS_CAP),
    order = "The run before this one ends after it begins.",
    gone = "This run is no longer stored.",
    visit = "A run can only be split where a visit begins.",
    char = "The character is not known yet. Try again in a moment.",
  }
  v.REFUSED = REFUSED
  -- after an action: the page shows the record the action left (by id), or the list when there is none
  local function showId(id)
    v.pending = nil
    local c = ns.DB and ns.charGuid and ns.charGuid() and ns.char() or nil
    local rec = openRec()
    if rec and rec.id == id and Runs.valid(rec) then v.render(Runs.view(rec, true, true)); return end
    for _, r in ipairs(c and type(c.dungeonRuns) == "table" and c.dungeonRuns or {}) do
      if type(r) == "table" and r.id == id and Runs.valid(r) then v.render(Runs.view(r, false, true)); return end
    end
    v.toList()
  end
  v.showId = showId
  -- an action that asks first: `key` names it (and the visit for a split)
  local function ask(key, fn)
    local p = v.pending
    if p and p.key == key and p.id == (v.run and v.run.id) and GetTime() < p.untilT then fn(); return end
    local q = { key = key, id = v.run and v.run.id, untilT = GetTime() + 8 }
    v.pending = q
    v.render(v.run)
    -- when the 8 seconds are over the button reads its own label again and the question goes: a "Yes, ..." that
    -- would only ask again is never left on the page
    if C_Timer and C_Timer.After then
      C_Timer.After(8.1, function()
        if v.pending == q and GetTime() >= q.untilT then
          v.pending = nil
          if v.run and v:IsShown() then pcall(v.render, v.run) end
        end
      end)
    end
  end
  v.ask = ask
  v.QUESTION = {
    delete = "Delete this run? Its numbers leave the dungeon totals.",
    ["end"] = "End this run now? What happens next in the dungeon is a new run.",
    join = "Join this run with the run before it? The two become one run.",
    split = "Split this run here? This visit and the ones after it become a run of their own.",
  }
  v.YES = { delete = "Yes, delete", ["end"] = "Yes, end it", join = "Yes, join", split = "Yes, split here" }
  local function result(ok, why, id)
    if ok then showId(id) else v.pending = nil; v.refused = REFUSED[why] or tostring(why); v.render(v.run) end
  end
  -- the TIME tile lists the clocks on hover (the lines of the list row's tooltip)
  local timeTip = CreateFrame("Button", nil, child)
  v.timeTip = timeTip
  v.timeTipLines = function()
    local run = v.run
    if not (run and run.inside and listView and listView.tipLines) then return {} end
    return listView.tipLines(run)
  end
  timeTip:SetScript("OnEnter", function(s2)
    local lines = v.timeTipLines()
    if #lines == 0 or not GameTooltip then return end
    GameTooltip:SetOwner(s2, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Time", 1, 1, 1)
    for _, l in ipairs(lines) do GameTooltip:AddLine(l, 0.8, 0.8, 0.8) end
    GameTooltip:Show()
  end)
  timeTip:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  -- what a second changes on the page of a run in progress: the TIME and PER HOUR tiles and the two Time lines
  local live = {}
  local function clocks(run)
    if live.time then live.time:SetText(fmtDur(run.duration)) end
    if live.rate then
      local rate = perHour(run)
      local c = rate ~= "" and C.gold or C.dim
      live.rate:SetText(rate ~= "" and rate or "-"); live.rate:SetTextColor(c[1], c[2], c[3])
    end
    if run.inside then v.timeLine, v.timeLine2 = Runs.timeLine(run) else v.timeLine, v.timeLine2 = "Length " .. fmtDur(run.duration), nil end
    if live.line1 then live.line1:SetText(v.timeLine) end
    if live.line2 then live.line2:SetText(v.timeLine2 or "") end
  end

  v.render = function(run)
    if v.run and run and v.run.id ~= run.id then v.pending, v.refused = nil, nil end
    v.run = run; fn, tn, bn, bbn, abn = 0, 0, 0, 0, 0
    v.renders = (v.renders or 0) + 1
    W = math.max(300, sf.contentW or math.floor(tonumber(sf:GetWidth()) or 0))
    v.renderedW = W
    cTile = UI.Columns(TILE, W, { inset = INSET })
    cBoss = UI.Columns(BOSS, W, { inset = INSET })
    cDeath = UI.Columns(deathCols(run.deathRows), W, { inset = INSET })
    cLoot = UI.Columns(LOOT, W, { inset = INSET })
    cFight = UI.Columns(FIGHT, W, { inset = INSET })
    cVisit = UI.Columns(VISIT, W, { inset = INSET })
    v.titleFS:SetText((run.name or "Dungeon") .. (run.kind == "raid" and "  ·  RAID" or ""))
    local meta = { date("%b %d, %H:%M", run.startT or 0) }
    if run.inProgress then meta[#meta + 1] = "in progress" else meta[#meta + 1] = Runs.endedLine(run) or "ended" end
    if n0(run.reentries) > 0 then meta[#meta + 1] = ("re-entered %d time%s"):format(run.reentries, run.reentries == 1 and "" or "s") end
    if run.edited then meta[#meta + 1] = "corrected by hand" end
    if run.keep then meta[#meta + 1] = "kept" end
    v.metaFS:SetText(table.concat(meta, "   ·   "))
    local y = 0
    -- four tiles: time, bosses, deaths, per hour
    local bosses = run.bosses or {}
    local byUid = {}                                             -- the fights of the run still stored, for the boss rows
    for _, f in ipairs(run.fights or {}) do if type(f.uid) == "string" then byUid[f.uid] = f end end
    col(cTile, "time", y + 6, "TIME", C.dim); col(cTile, "boss", y + 6, "BOSSES", C.dim); col(cTile, "death", y + 6, "DEATHS", C.dim); col(cTile, "rate", y + 6, "PER HOUR", C.dim)
    local function tile(key, text, color) local c = cTile[key]; return cell(c.x, y + 22, c.w, text, color or C.ink, GameFontNormal) end
    live.time = tile("time", "")
    tile("boss", bossText(run))
    tile("death", n0(run.deaths) == 0 and "0" or tostring(run.deaths), n0(run.deaths) > 0 and C.red or C.ink)
    live.rate = tile("rate", "")
    -- the TIME tile's delta against the best, on a line of its own under it ("+3:29 ↑", "best", "first run here")
    local dw, dc = deltaWord(run)
    v.deltaText = dw
    live.delta = cell(cTile.time.x, y + 40, cTile.time.w, dw, dc)
    timeTip:ClearAllPoints(); timeTip:SetPoint("TOPLEFT", child, "TOPLEFT", cTile.time.x, -(y + 4)); timeTip:SetWidth(math.max(1, cTile.time.w)); timeTip:SetHeight(52)
    y = y + 58
    if run.repull then line(y, "Possibly two runs: a boss killed before was pulled again in visit " .. run.repull .. ". Split here is on that visit.", C.gold); y = y + 18 end
    local partial = Runs.partialLine(run)
    if partial then line(y, partial, C.red); y = y + 18 end
    -- time: where the wall time went on one line, what was done inside on the next (one line of all six clocks is
    -- wider than the page at 900x580, and a cell on a detail page has no tooltip to read a cut text in)
    y = heading(y, "Time")
    live.line1 = line(y, "", C.ink); y = y + 18
    live.line2 = nil
    if run.inside then live.line2 = line(y, "", C.dim); y = y + 18 end
    clocks(run)
    v.timeFS = { live.line1, live.line2 }
    -- pace: against the best of the route (0.9.51)
    local p1, p2 = paceLines(run)
    v.paceLine, v.paceLine2 = p1, p2
    if p1 then
      y = heading(y, "Pace")
      line(y, p1, C.ink); y = y + 18
      if p2 then line(y, p2, C.dim); y = y + 18 end
    end
    -- bosses: one row per boss in pull order, from the encounter events themselves
    y = heading(y, ("Bosses  (%d)"):format(#bosses))
    local vs = run.cmp and run.cmp.vs or {}
    if #bosses > 0 then
      col(cBoss, "boss", y, "BOSS", C.dim); col(cBoss, "pulls", y, "PULLS", C.dim, "RIGHT"); col(cBoss, "combat", y, "IN COMBAT", C.dim, "RIGHT")
      col(cBoss, "down", y, "DOWN AT", C.dim, "RIGHT"); col(cBoss, "seg", y, "SEGMENT", C.dim, "RIGHT"); col(cBoss, "vs", y, "VS BEST", C.dim, "RIGHT"); col(cBoss, "res", y, "RESULT", C.dim); y = y + 16
      for _, b in ipairs(bosses) do
        local res, kind = Runs.bossResult(b)
        col(cBoss, "boss", y, b.name or "Boss", C.ink)
        col(cBoss, "pulls", y, tostring(b.pulls or 1), C.dim, "RIGHT")
        col(cBoss, "combat", y, fmtDur(b.combat), C.dim, "RIGHT")
        col(cBoss, "down", y, b.kill and ("+" .. fmtDur(b.kill)) or "-", C.dim, "RIGHT")
        local sp = run.splits and run.splits[b.enc]
        col(cBoss, "seg", y, sp and fmtDur(sp.seg) or "-", C.dim, "RIGHT")
        local d = b.kill and vs[b.enc]
        col(cBoss, "vs", y, d and Runs.deltaText(d) or "", d and (d > 0 and C.red or C.green) or C.dim, "RIGHT")
        local bits = {}
        if b.kill and n0(b.wipes) > 0 then bits[#bits + 1] = ("%d wipe%s"):format(b.wipes, b.wipes == 1 and "" or "s") end
        col(cBoss, "res", y, res .. (#bits > 0 and ("  ·  " .. table.concat(bits, ", ")) or ""), kind == "kill" and C.green or (kind == "wipe" and C.red or C.dim))
        local bf = b.fight and byUid[b.fight]
        if bf then bossButton(y, bf) end
        y = y + 16
      end
      -- the bosses of the dungeon's learned list this run never pulled
      for _, m in ipairs(run.missing or {}) do
        col(cBoss, "boss", y, m.name or "Boss", C.dim); col(cBoss, "res", y, "Not killed", C.dim)
        y = y + 16
      end
    else
      line(y, "No boss encounters recorded in this run.", C.dim); y = y + 18
    end
    -- deaths: the character's own (the party's follow in a later version)
    y = heading(y, ("Deaths  (%d)"):format(n0(run.deaths)))
    if run.deathRows and #run.deathRows > 0 then
      col(cDeath, "t", y, "AT", C.dim, "RIGHT"); col(cDeath, "who", y, "WHO", C.dim); col(cDeath, "where", y, "WHERE", C.dim)
      if cDeath.foe then col(cDeath, "foe", y, "SLAIN BY", C.dim) end
      if cDeath.back then col(cDeath, "back", y, "BACK AFTER", C.dim, "RIGHT") end
      y = y + 16
      for _, d in ipairs(run.deathRows) do
        col(cDeath, "t", y, "+" .. fmtDur(n0(d.o)), C.dim, "RIGHT")
        col(cDeath, "who", y, "You", C.red)
        col(cDeath, "where", y, d.enc and (bossName(run, d.enc) or "Boss") or "Trash", C.ink)
        if cDeath.foe then col(cDeath, "foe", y, d.foe or "", C.dim) end
        if cDeath.back then col(cDeath, "back", y, d.back and fmtDur(d.back) or "", C.dim, "RIGHT") end
        y = y + 16
      end
      if n0(run.deaths) > #run.deathRows then line(y, ("and %d more"):format(run.deaths - #run.deathRows), C.dim); y = y + 16 end
    elseif n0(run.deaths) > 0 then
      line(y, ("%d death%s."):format(run.deaths, run.deaths == 1 and "" or "s"), C.red); y = y + 16
    else
      line(y, "Deathless run.", C.green); y = y + 16
    end
    -- loot: the run's own gold (items, looted coin and quest rewards, the vendor value as an estimate, coin per
    -- hour active in the run), then every rare-and-better drop still in the loot log
    y = heading(y, "Loot")
    v.lootLine = lootLine(run)
    v.lootFS = line(y, v.lootLine, C.gold); y = y + 20
    v.purseLine = run.gold and Runs.purseLine(run) or nil
    v.purseFS = nil
    if v.purseLine then v.purseFS = line(y, v.purseLine, C.dim); y = y + 18 end
    if run.notable and #run.notable > 0 then
      for _, l in ipairs(run.notable) do
        local icon = l.icon and ("|T" .. tostring(l.icon) .. ":14:14:0:0|t ") or ""
        col(cLoot, "item", y, icon .. (l.item or "?"), qColor(l.q))
        col(cLoot, "count", y, (l.count or 1) > 1 and ("x" .. l.count) or "", C.dim, "RIGHT")
        col(cLoot, "src", y, l.src or "", C.dim)
        col(cLoot, "t", y, date("%H:%M:%S", l.t or 0), C.dim, "RIGHT")
        y = y + 16
      end
    else
      line(y, "No rare or better drops in this run.", C.dim); y = y + 16
    end
    -- XP, when the character gained any
    local xpLine, xpMore, xpHidden = nil, nil, nil
    if run.xp then xpLine, xpMore, xpHidden = Runs.xpLine(run) end
    v.xpLine, v.xpMore, v.xpHidden = xpLine, xpMore, xpHidden
    v.xpFS = {}
    if xpLine then
      y = heading(y, "XP")
      v.xpFS[1] = line(y, xpLine, C.ink); y = y + 18
      if xpMore then v.xpFS[#v.xpFS + 1] = line(y, xpMore, C.dim); y = y + 18 end
      if xpHidden then v.xpFS[#v.xpFS + 1] = line(y, xpHidden, C.dim); y = y + 18 end
    end
    -- party: the largest group a fight of the run recorded (join and leave times follow in a later version)
    if run.group and #run.group > 0 then
      y = heading(y, ("Party  (%d)"):format(#run.group))
      local names = {}
      for _, m in ipairs(run.group) do
        local r, g, b = UI.ClassColor(m.class)
        names[#names + 1] = ("|cff%02x%02x%02x%s|r"):format(math.floor(r * 255), math.floor(g * 255), math.floor(b * 255), m.name or "?")
      end
      line(y, table.concat(names, "   ")); y = y + 18
    end
    -- visits: where each stretch inside began, how long it was, and where a run can be split
    local visits = run.visits or {}
    local canSplit = Runs.visitClocks(run.rec or run) ~= nil
    if #visits > 1 then
      y = heading(y, ("Visits  (%d)"):format(#visits))
      col(cVisit, "n", y, "VISIT", C.dim, "RIGHT"); col(cVisit, "at", y, "AT", C.dim, "RIGHT"); col(cVisit, "len", y, "INSIDE", C.dim, "RIGHT"); col(cVisit, "how", y, "HOW", C.dim)
      y = y + 16
      local HOW = { zone = "entered", login = "logged in inside", reload = "after a reload", ghost = "back after a run back", boss = "at a boss pull", split = "after a split" }
      for k, x in ipairs(visits) do
        col(cVisit, "n", y, tostring(k), run.repull == k and C.gold or C.dim, "RIGHT")
        col(cVisit, "at", y, "+" .. fmtDur(n0(x.i)), C.dim, "RIGHT")
        col(cVisit, "len", y, fmtDur(n0(x.secs)), C.ink, "RIGHT")
        col(cVisit, "how", y, (HOW[x.how] or tostring(x.how or "")) .. (n0(x.n) > 0 and ("  ·  and %d more"):format(x.n) or ""), run.repull == k and C.gold or C.dim)
        if k >= 2 and canSplit and x.i ~= nil and visits[k - 1].o ~= nil then
          local key = "split" .. k
          local asking = v.pending and v.pending.key == key
          local b = actBtn(cVisit.act.x, y - 2, cVisit.act.w, asking and v.YES.split or "Split here", function()
            ask(key, function() local id = run.id; local ok, why = Runs.split(id, k); result(ok, why, id) end)
          end)
          b.visit = k
        end
        y = y + 20
      end
    end
    -- encounters: the fights of the run that are still stored; no section when none is (every older run, once the
    -- desktop has read its fights)
    v.encounters = #(run.fights or {})
    if v.encounters > 0 then
      y = heading(y, ("Encounters  (%d)"):format(v.encounters))
      for i = #run.fights, 1, -1 do fightRow(y, run.fights[i]); y = y + 16 end
    end
    -- the run's buttons: Keep, End run now (the open run), Join with previous run, Delete run
    y = y + 8
    local x = INSET
    local function act(key, label, fnAct, needsAsk)
      local asking = v.pending and v.pending.key == key
      local b = actBtn(x, y, 60, asking and v.YES[key] or label, function()
        if needsAsk then ask(key, fnAct) else fnAct() end
      end)
      b.key = key
      local ok, bw = pcall(b.GetWidth, b)
      x = x + ((ok and tonumber(bw)) or 60) + UI.SP.S
      return b
    end
    act("keep", run.keep and "Unkeep" or "Keep", function()
      local id = run.id
      local ok, why = Runs.setKeep(id, not run.keep)
      if ok then v.refused = nil end
      result(ok, why, id)
    end, false)
    if run.inProgress then act("end", "End run now", function() local id = run.id; Runs.endNow(); showId(id) end, true) end
    act("join", "Join with previous run", function() local ok, why = Runs.join(run.id); result(ok, why, ok and why or run.id) end, true)
    act("delete", "Delete run", function() local id = run.id; local ok, why = Runs.delete(id); if ok then v.pending = nil; v.toList() else result(ok, why, id) end end, true)
    y = y + 26
    local q = v.pending and (v.QUESTION[v.pending.key] or (v.pending.key:match("^split") and v.QUESTION.split))
    v.questionLine = q
    if q then line(y, q, C.gold); y = y + 18 end
    if v.refused then line(y, v.refused, C.red); y = y + 18 end
    v.refusedLine = v.refused
    for j = fn + 1, #child.fs do child.fs[j]:Hide() end
    for j = tn + 1, #child.tex do child.tex[j]:Hide() end
    for j = bn + 1, #child.btn do child.btn[j]:Hide() end
    for j = bbn + 1, #child.bbtn do child.bbtn[j]:Hide() end
    for j = abn + 1, #child.abtn do child.abtn[j]:Hide() end
    sf:SetContentHeight(y + 12)
    v.sigLists, v.sigPage = nil, nil
    if run.inProgress and type(run.rec) == "table" then v.sigLists, v.sigPage = v.signature(run.rec) end
  end
  -- What the page of a run in progress shows, as two short texts: `lists` changes when a fight or a loot row was
  -- stored or a visit began or ended (the fights and the drops are read again), `page` when anything but a clock did
  -- (the page is laid out again). While neither changes, a second only moves the clocks.
  v.signature = function(rec)
    local nF = #((ns.Fights and ns.Fights.list and ns.Fights.list()) or {})
    local nL = #((ns.DB and ns.DB.loot and ns.DB.loot.log) or {})
    local lists = ("%d.%d.%d.%s"):format(nF, nL, #rec.visits, tostring(rec.st))
    local p = { lists, #rec.bosses, #rec.deaths, n0(rec.nDeaths and rec.nDeaths.me), tostring(rec.partial), n0(rec.secs.active), n0(rec.hidden and rec.hidden.xp),
      tostring(rec.keep), tostring(rec.repull), tostring(rec.id) }
    for _, b in ipairs(rec.bosses) do
      p[#p + 1] = ("%d/%d/%d/%d/%d/%d"):format(n0(b.pulls), n0(b.kill), n0(b.wipes), n0(b.unknown), n0(b.resets), n0(b.combat))
    end
    local d = rec.deaths[#rec.deaths]                            -- (an open run has every block, Runs.validOpen)
    if d then p[#p + 1] = tostring(d.foe) .. n0(d.back) end
    local x = rec.xp
    if type(x) == "table" then p[#p + 1] = ("%d/%d/%d"):format(n0(x.gain), n0(x.n), n0(x.quest)) end
    for _, vis in ipairs(rec.visits) do
      p[#p + 1] = ("%d/%d/%d/%d/%d/%d"):format(n0(vis.looted), n0(vis.quests), n0(vis.lootValue), n0(vis.items), n0(vis.unpriced), n0(vis.purse))
    end
    return lists, table.concat(p, " ")
  end
  v.toList = function() v:Hide(); if listView then listView:Show() end; if listRebuild then listRebuild() end end
  -- The open run's page follows it, once a second while it is on screen. The run is read from the store by its id:
  -- it may have closed meanwhile (the page becomes the closed run's), or have been discarded as empty (the page goes
  -- back to the list). Returns whether the page still shows a run.
  v.refresh = function()
    local run = v.run
    if not (run and run.inProgress and run.id) then return false end
    local rec = openRec()
    if rec and rec.id == run.id and Runs.valid(rec) then
      local light = Runs.view(rec, true, false)
      local lists, page = v.signature(rec)
      if page == v.sigPage then                                  -- only the clocks moved
        light.fights, light.notable, light.group = run.fights, run.notable, run.group
        v.run = light
        clocks(light)
      elseif lists == v.sigLists then                            -- a number changed: laid out again, the lists as they were
        light.fights, light.notable, light.group = run.fights, run.notable, run.group
        v.render(light)
      else v.render(Runs.view(rec, true, true)) end
      return true
    end
    local c = ns.DB and ns.charGuid and ns.charGuid() and ns.char() or nil
    local list = c and type(c.dungeonRuns) == "table" and c.dungeonRuns or {}
    for i = #list, 1, -1 do
      if type(list[i]) == "table" and list[i].id == run.id and Runs.valid(list[i]) then v.render(Runs.view(list[i], false, true)); return true end
    end
    -- the run is nowhere: it was too short and empty to be kept. Nothing is left to follow.
    run.inProgress = false
    v.toList()
    return false
  end
  -- a new width lays the open run out again
  sf.onResize = function() if v.run and v:IsShown() then pcall(v.render, v.run) end end
  v:HookScript("OnShow", function() if v.run and sf.contentW and v.renderedW ~= sf.contentW then pcall(v.render, v.run) end end)
  return v
end

local function openRun(run)
  -- a row of the list carries the short view: the page reads the fights and the drops as well. Whether the run is
  -- open is asked of the store, never of the row: the list is rebuilt every 3 s and the run may have closed since.
  if run.rec and not run.fights then run = Runs.view(run.rec, openRec() == run.rec, true) end
  listView:Hide(); detailView.render(run); detailView:Show()
end

-- ══ LIST VIEW ═══════════════════════════════════════════════════════════════════
-- the value a column sorts by (the Per hour column: runs with an XP rate before those with a coin rate)
local SORT_VAL = {
  time = function(r) return n0(r.startT) end,
  name = function(r) return (r.name or ""):lower() end,
  dur = function(r) return n0(r.duration) end,
  boss = function(r) return n0(r.bossesDown) end,
  death = function(r) return n0(r.deaths) end,
  rate = function(r) return r.xpPerHour and (1e12 + r.xpPerHour) or n0(r.coinPerHour) end,
  loot = function(r) return n0(r.coin) end,
}
-- the rows of the list: the runs the filter keeps, sorted by `key`; ties and the default newest first
local function listRows(runs, kind, inst, key, asc)
  local rows = {}
  for _, r in ipairs(runs) do
    local k = r.kind == "raid" and "raid" or "party"
    if (kind == "all" or kind == k) and (not inst or r.name == inst) then rows[#rows + 1] = r end
  end
  local val = SORT_VAL[key] or SORT_VAL.time
  table.sort(rows, function(a, b)
    local x, y = val(a), val(b)
    if x ~= y then if asc then return x < y end return x > y end
    if n0(a.startT) ~= n0(b.startT) then return n0(a.startT) > n0(b.startT) end
    return tostring(a.id) > tostring(b.id)
  end)
  return rows
end

-- "The Temple of Atal'Hakkar  ·  RAID  ·  in progress": the list's DUNGEON cell; `kept` adds "kept" (the hover,
-- where a long name is never cut)
local function nameLabel(run, kept)
  return (run.name or "?") .. (run.kind == "raid" and "  ·  RAID" or "") .. (run.inProgress and "  ·  in progress" or "") .. ((kept and run.keep) and "  ·  kept" or "")
end
local function buildList(content)
  local v = CreateFrame("Frame", nil, content); v:SetAllPoints(content)
  -- the filter: All, Dungeons, Raids on the tab strip, and one dungeon from the list at its right (the pane's own
  -- list frame). The sort: a click on a column's header.
  local st = { kind = "all", inst = nil, sortKey = "time", sortAsc = false }
  v.st = st
  local tabs = UI.Tabs(v, { { key = "all", label = "All" }, { key = "party", label = "Dungeons" }, { key = "raid", label = "Raids" } }, -30, 2,
    { shared = true, onSelect = function(key) st.kind = key; if listRebuild then listRebuild() end end })
  v.tabs = tabs
  local pane = tabs.content
  local menu = UI.Menu(v)
  v.menu = menu
  local pick
  pick = UI.Button(pane, "All dungeons", 120, UI.ROW_H, function(b)
    local names, seen = {}, {}
    for _, r in ipairs(Runs.views()) do
      if r.name and not seen[r.name] then seen[r.name] = true; names[#names + 1] = r.name end
    end
    table.sort(names)
    local items = { { "", "All dungeons", st.inst == nil } }
    for _, n in ipairs(names) do items[#items + 1] = { n, n, st.inst == n } end
    menu.open(b, items, function(key) v.pickInst(key ~= "" and key or nil) end, true)
  end)
  -- (a row of its own under the tab strip, with the view switch at its left: on the tab strip's row a long dungeon
  -- name and the two view buttons lay over the Raids tab at 900x580)
  pick:SetPoint("TOPRIGHT", pane, "TOPRIGHT", -(UI.SCROLLBAR + UI.SP.S), -UI.SP.XS)
  v.pick = pick
  -- the view: RUNS (one row per run) or BY DUNGEON (one row per dungeon, from its statistics; a click there filters
  -- RUNS to that dungeon). Both views follow the tabs and the pick.
  st.view = "runs"
  local viewBtn = {}
  v.viewBtn = viewBtn
  v.setView = function(key)
    st.view = key
    for k, b in pairs(viewBtn) do UI.SetButtonSelected(b, k == key) end
    if listRebuild then listRebuild() end
  end
  viewBtn.runs = UI.Button(pane, "Runs", 60, UI.ROW_H, function() v.setView("runs") end)
  viewBtn.runs:SetPoint("TOPLEFT", pane, "TOPLEFT", UI.SP.S, -UI.SP.XS)
  viewBtn.dungeons = UI.Button(pane, "By dungeon", 90, UI.ROW_H, function() v.setView("dungeons") end)
  viewBtn.dungeons:SetPoint("LEFT", viewBtn.runs, "RIGHT", UI.SP.XS, 0)
  UI.FitButton(viewBtn.dungeons, 60); UI.FitButton(viewBtn.runs, 44)
  UI.SetButtonSelected(viewBtn.runs, true); UI.SetButtonSelected(viewBtn.dungeons, false)
  v.pickInst = function(name)
    st.inst = name
    pick.text:SetText(name or "All dungeons"); UI.FitButton(pick, 120); UI.SetButtonSelected(pick, name ~= nil)
    if listRebuild then listRebuild() end
  end
  UI.FitButton(pick, 120)
  -- lockouts: which instances this character is saved to, and when they reset (wraps; the list moves down with it)
  local lock = UI.SummaryLine(pane, C.gold, -(UI.SP.XS + UI.ROW_H + UI.SP.S), true)
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
  v.otherLockouts = otherLockouts
  -- the account's instances of the last hour and day, under the lockouts (0.9.51)
  local hour = UI.FS(pane, "GameFontHighlightSmall", C.dim)
  hour:SetJustifyH("LEFT")
  if hour.SetWordWrap then hour:SetWordWrap(false) end
  hour:SetPoint("TOPLEFT", lock, "BOTTOMLEFT", 0, -2); hour:SetPoint("TOPRIGHT", lock, "BOTTOMRIGHT", 0, -2)
  v.hourFS = hour
  -- the two lines have a hover: the other characters' lockouts, and one row per copy counted
  local function hover(region, title, lines)
    local h = CreateFrame("Button", nil, pane)
    h:SetAllPoints(region)
    h:SetScript("OnEnter", function(s2)
      if not GameTooltip then return end
      GameTooltip:SetOwner(s2, "ANCHOR_BOTTOMLEFT")
      GameTooltip:AddLine(title, 1, 1, 1)
      for _, l in ipairs(lines()) do GameTooltip:AddLine(l, 0.8, 0.8, 0.8, true) end
      GameTooltip:Show()
    end)
    h:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return h
  end
  v.lockTipLines = function()
    local L = otherLockouts()
    if #L == 0 then return { "No other character of this account is saved to an instance." } end
    return L
  end
  v.hourTipLines = function()
    local out = { Runs.HOUR_TIP }
    for _, l in ipairs(Runs.hourTip()) do out[#out + 1] = l end
    if not Runs.limit() then out[#out + 1] = "Set your own limit with /eb instances limit 5 (or 10)." end
    return out
  end
  v.lockHover = hover(lock, "Your other characters", v.lockTipLines)
  v.hourHover = hover(hour, "Instances", v.hourTipLines)
  v.emptyText = "No dungeon runs yet. Enter a dungeon and it shows up here.\n" .. Runs.SINCE
  -- Time · Dungeon · (in progress) · Length · Bosses · Deaths · Per hour · Loot
  local body = UI.Below(pane, hour)
  local runsHost = CreateFrame("Frame", nil, body); runsHost:SetAllPoints(body)
  local dungHost = CreateFrame("Frame", nil, body); dungHost:SetAllPoints(body); dungHost:Hide()
  v.runsHost, v.dungHost = runsHost, dungHost
  local tbl = UI.Table(runsHost, {
    { key = "time", label = "Time", kind = "tag", color = "dim", measure = { "12/31 23:59" }, sort = true },
    { key = "name", label = "Dungeon", flex = 1, min = 120, sort = true },
    { key = "live", label = "", kind = "tag", color = "green", measure = { "•" } },
    { key = "dur", label = "Length", kind = "num", color = "dim", measure = { "23h 59m", "59m 59s · +8:88 ↑" }, sort = true },
    { key = "boss", label = "Bosses", kind = "num", measure = { "20/20" }, sort = true },
    { key = "death", label = "Deaths", kind = "num", color = "dim", measure = { "99" }, sort = true },
    { key = "rate", label = "Per hour", kind = "num", color = "dim", measure = { "99,999 XP/h" }, sort = true },
    { key = "loot", label = "Loot", kind = "money", color = "gold", measure = { "99 · " .. fmtMoney(999999) }, sort = true },
  -- (the columns 8 px apart, not 12: with the filter strip's inset and the sort arrows' room, the name of a run in
  -- progress, "Maraudon  ·  in progress", is cut at 900x580 otherwise. From 0.9.51 LENGTH carries the delta, so it
  -- reads "32m 10s · +3:29 ↑" with the short separator, and Per hour and Loot are measured from their realistic
  -- widest values, 99,999 XP an hour and 99 items with 99 gold; a wider value is cut and shown in full on hover. The
  -- first and last column sit 4 px in from the row's ends, not 8)
  }, { top = 0, gap = UI.SP.S, inset = UI.SP.XS, emptyText = v.emptyText, sortKey = st.sortKey, sortAsc = st.sortAsc,
    onSort = function(key, asc) st.sortKey, st.sortAsc = key, asc; if listRebuild then listRebuild() end end,
    onClick = function(row) if row.run then openRun(row.run) end end,
    -- the clocks of the run, why it ended, and what is missing from it
    tooltip = function(row, _, tip)
      local run = row.run
      if not run then return end
      tip:AddLine(nameLabel(run, true))                         -- (the whole name: the cell can cut a long one)
      for _, l in ipairs(v.tipLines(run)) do tip:AddLine(l) end
    end })
  v.tbl = tbl
  v.nameLabel = nameLabel
  v.tipLines = function(run)
    local out = { "Inside " .. fmtDur(run.inside) }
    if n0(run.ghost) > 0 then out[#out + 1] = "Run back " .. fmtDur(run.ghost) end
    if n0(run.outside) > 0 then out[#out + 1] = "Outside " .. fmtDur(run.outside) end
    if n0(run.offline) > 0 then out[#out + 1] = "Offline " .. fmtDur(run.offline) end
    out[#out + 1] = "Active " .. fmtDur(run.active)
    if run.inProgress then out[#out + 1] = "In progress" else out[#out + 1] = Runs.endedLine(run) end
    if run.edited then out[#out + 1] = "Corrected by hand" end
    if run.repull then out[#out + 1] = "Possibly two runs: a boss killed before was pulled again" end
    if run.keep then out[#out + 1] = "Kept: never removed when the list is full" end
    if n0(run.reentries) > 0 then out[#out + 1] = ("Re-entered %d time%s"):format(run.reentries, run.reentries == 1 and "" or "s") end
    local partial = Runs.partialLine(run)
    if partial then out[#out + 1] = partial end
    return out
  end

  -- BY DUNGEON: Dungeon · Runs · Full clears · Average · Best · Coin per hour · XP per hour · Deaths per run · Last run
  local dtbl = UI.Table(dungHost, {
    { key = "name", label = "Dungeon", flex = 1, min = 110 },
    { key = "n", label = "Runs", kind = "num", measure = { "999" } },
    { key = "full", label = "Full", kind = "num", measure = { "999" } },
    { key = "avg", label = "Average", kind = "num", color = "dim", measure = { "23h 59m" } },
    { key = "best", label = "Best", kind = "num", measure = { "59m 59s" } },
    { key = "coin", label = "Coin/h", kind = "money", color = "gold", measure = { fmtMoney(999999) } },
    { key = "xp", label = "XP/h", kind = "num", color = "dim", measure = { "99,999" } },
    { key = "dpr", label = "Deaths/run", kind = "num", color = "dim", measure = { "9.9" } },
    { key = "last", label = "Last run", kind = "tag", color = "dim", measure = { "12/31 23:59" } },
  }, { top = 0, gap = UI.SP.S, emptyText = "No dungeon statistics yet. A run is counted here once it ends.",
    onClick = function(row)
      local d = row.drow
      if not d or d.other then return end
      local k = d.kind == "raid" and "raid" or "party"
      if st.kind ~= "all" and st.kind ~= k then tabs.select(k) end      -- (RUNS then lists the clicked dungeon's runs)
      v.pickInst(d.name); v.setView("runs")
    end,
    tooltip = function(row, _, tip)
      local d = row.drow
      if not d then return end
      tip:AddLine(d.name)
      tip:AddLine(("%d run%s, %d full clear%s"):format(d.n, d.n == 1 and "" or "s", d.full, d.full == 1 and "" or "s"))
      if d.other then tip:AddLine("Dungeons run least recently, counted together once 80 dungeons have numbers of their own.") end
    end })
  v.dtbl = dtbl
  local function dungeonRebuild()
    local all, rows = Runs.dungeonRows(), {}
    for _, d in ipairs(all) do
      local k = d.kind == "raid" and "raid" or "party"
      if (st.kind == "all" or st.kind == k) and (not st.inst or d.name == st.inst) then rows[#rows + 1] = d end
    end
    v.dshown = rows
    dtbl.setRows(rows, function(row, d)
      row.drow = d
      row.c.name:SetText(d.name .. (d.kind == "raid" and "  ·  RAID" or ""))
      row.c.n:SetText(tostring(d.n))
      row.c.full:SetText(d.kind == "raid" and "-" or tostring(d.full))
      row.c.avg:SetText(d.avg and fmtDur(d.avg) or "-")
      row.c.best:SetText(d.best and fmtDur(d.best) or "-")
      row.c.coin:SetText(d.coinPerHour and ((ns.Gold and ns.Gold.fmt) and ns.Gold.fmt(d.coinPerHour, { rate = true }) or fmtMoney(math.floor(d.coinPerHour))) or "-")
      row.c.xp:SetText(d.xpPerHour and Runs.commas(d.xpPerHour) or "-")
      row.c.dpr:SetText(("%.1f"):format(d.deathsPerRun))
      row.c.last:SetText(d.last > 0 and date("%m/%d %H:%M", d.last) or "")
    end)
    if #rows == 0 and #all > 0 then dtbl.setEmpty("No dungeon matches this filter.") end
  end
  v.dungeonRebuild = dungeonRebuild

  listRebuild = function()
    lock:SetText(lockText())
    hour:SetText(Runs.hourLine())
    if st.view == "dungeons" then runsHost:Hide(); dungHost:Show() else dungHost:Hide(); runsHost:Show() end
    if st.view == "dungeons" then dungeonRebuild(); return end
    local runs = Runs.views()
    local rows = listRows(runs, st.kind, st.inst, st.sortKey, st.sortAsc)
    v.shown = rows
    tbl.setRows(rows, function(row, run)
      row.run = run
      row.c.time:SetText(date("%m/%d %H:%M", run.startT or 0))
      row.c.name:SetText(nameLabel(run, false))
      row.c.live:SetText(run.inProgress and "•" or "")
      local dw, dc = deltaWord(run, true)
      row.c.dur:SetText(fmtDur(run.duration) .. (dw ~= "" and (" · " .. dw) or ""))
      if dw ~= "" and dc then row.c.dur:SetTextColor(dc[1], dc[2], dc[3]) end
      row.c.boss:SetText(bossText(run))
      row.c.death:SetText(tostring(run.deaths or 0))
      if (run.deaths or 0) > 0 then row.c.death:SetTextColor(C.red[1], C.red[2], C.red[3]) end
      row.c.rate:SetText(perHour(run))
      -- items and coin of the run's own gold block, as on its page
      local items, coin = run.items or 0, run.coin or 0
      row.c.loot:SetText((items > 0 and (items .. " · ") or "") .. fmtMoney(coin))
    end)
    -- runs there are, none the filter keeps: say so, not that there are no runs
    if #rows == 0 and #runs > 0 then tbl.setEmpty("No run matches this filter.") end
  end

  tabs.select("all")
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
  if not ticker then
    -- both only while the pane is on screen: a closed window or another pane leaves the frames' own flags set
    ticker = C_Timer.NewTicker(3, function()
      if onScreen(listView) and listRebuild then listRebuild() end
    end)
    -- the page of the run in progress ticks every second while it shows
    C_Timer.NewTicker(1, function()
      if onScreen(detailView) and detailView.refresh then pcall(detailView.refresh) end
    end)
  end
end)

-- the runs of the logged-in character as the panes read them, oldest first (the Fights list groups by them)
ns.DungeonRuns = function() return Runs.views() end

-- ── test exports: headless luajit tests in tests/ read these; no effect in-game ──
ns._test = ns._test or {}
ns._test.runViews = function(full) return Runs.views(full) end
ns._test.dungeonsLockText = function() return listView and listView.lockText and listView.lockText() or nil end
ns._test.renderRun = function(run) if detailView then detailView.render(run); detailView:Show(); detailView:Hide() end end
ns._test.dungeonDetail = function() return detailView end
ns._test.dungeonList = function() if listRebuild then listRebuild() end; return listView end
ns._test.openRun = function(run) openRun(run) end
