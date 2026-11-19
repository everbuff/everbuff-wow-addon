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
  child.fs, child.tex, child.btn, child.bbtn = {}, {}, {}, {}
  v.sf, v.child = sf, child
  local W = 600                 -- the content width this render lays out for (the scroll child's)
  local INSET = SP.S
  local fn, tn, bn, bbn = 0, 0, 0, 0
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
    { key = "boss", flex = 1, min = 100 },
    { key = "pulls", measure = { "PULLS", "99" } },
    { key = "combat", measure = { "IN COMBAT", "59m 59s", "88m 88s" } },
    { key = "down", measure = { "DOWN AT", "+23h 59m", "+88h 88m" } },
    { key = "seg", measure = { "SEGMENT", "59m 59s", "88m 88s" } },
    { key = "res", flex = 1, min = 120 },
  }
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
  local cTile, cBoss, cDeath, cLoot, cFight
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
    v.run = run; fn, tn, bn, bbn = 0, 0, 0, 0
    v.renders = (v.renders or 0) + 1
    W = math.max(300, sf.contentW or math.floor(tonumber(sf:GetWidth()) or 0))
    v.renderedW = W
    cTile = UI.Columns(TILE, W, { inset = INSET })
    cBoss = UI.Columns(BOSS, W, { inset = INSET })
    cDeath = UI.Columns(deathCols(run.deathRows), W, { inset = INSET })
    cLoot = UI.Columns(LOOT, W, { inset = INSET })
    cFight = UI.Columns(FIGHT, W, { inset = INSET })
    v.titleFS:SetText((run.name or "Dungeon") .. (run.kind == "raid" and "  ·  RAID" or ""))
    local meta = { date("%b %d, %H:%M", run.startT or 0) }
    if run.inProgress then meta[#meta + 1] = "in progress" else meta[#meta + 1] = Runs.endedLine(run) or "ended" end
    if n0(run.reentries) > 0 then meta[#meta + 1] = ("re-entered %d time%s"):format(run.reentries, run.reentries == 1 and "" or "s") end
    v.metaFS:SetText(table.concat(meta, "   ·   "))
    local y = 0
    -- four tiles: time, bosses, deaths, per hour
    local bosses = run.bosses or {}
    local byUid = {}                                             -- the fights of the run still stored, for the boss rows
    for _, f in ipairs(run.fights or {}) do if type(f.uid) == "string" then byUid[f.uid] = f end end
    col(cTile, "time", y + 6, "TIME", C.dim); col(cTile, "boss", y + 6, "BOSSES", C.dim); col(cTile, "death", y + 6, "DEATHS", C.dim); col(cTile, "rate", y + 6, "PER HOUR", C.dim)
    local function tile(key, text, color) local c = cTile[key]; return cell(c.x, y + 22, c.w, text, color or C.ink, GameFontNormal) end
    live.time = tile("time", "")
    tile("boss", tostring(n0(run.bossesDown)))
    tile("death", n0(run.deaths) == 0 and "0" or tostring(run.deaths), n0(run.deaths) > 0 and C.red or C.ink)
    live.rate = tile("rate", "")
    timeTip:ClearAllPoints(); timeTip:SetPoint("TOPLEFT", child, "TOPLEFT", cTile.time.x, -(y + 4)); timeTip:SetWidth(math.max(1, cTile.time.w)); timeTip:SetHeight(36)
    y = y + 44
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
    -- bosses: one row per boss in pull order, from the encounter events themselves
    y = heading(y, ("Bosses  (%d)"):format(#bosses))
    if #bosses > 0 then
      col(cBoss, "boss", y, "BOSS", C.dim); col(cBoss, "pulls", y, "PULLS", C.dim, "RIGHT"); col(cBoss, "combat", y, "IN COMBAT", C.dim, "RIGHT")
      col(cBoss, "down", y, "DOWN AT", C.dim, "RIGHT"); col(cBoss, "seg", y, "SEGMENT", C.dim, "RIGHT"); col(cBoss, "res", y, "RESULT", C.dim); y = y + 16
      for _, b in ipairs(bosses) do
        local res, kind = Runs.bossResult(b)
        col(cBoss, "boss", y, b.name or "Boss", C.ink)
        col(cBoss, "pulls", y, tostring(b.pulls or 1), C.dim, "RIGHT")
        col(cBoss, "combat", y, fmtDur(b.combat), C.dim, "RIGHT")
        col(cBoss, "down", y, b.kill and ("+" .. fmtDur(b.kill)) or "-", C.dim, "RIGHT")
        local sp = run.splits and run.splits[b.enc]
        col(cBoss, "seg", y, sp and fmtDur(sp.seg) or "-", C.dim, "RIGHT")
        local bits = {}
        if b.kill and n0(b.wipes) > 0 then bits[#bits + 1] = ("%d wipe%s"):format(b.wipes, b.wipes == 1 and "" or "s") end
        col(cBoss, "res", y, res .. (#bits > 0 and ("  ·  " .. table.concat(bits, ", ")) or ""), kind == "kill" and C.green or (kind == "wipe" and C.red or C.dim))
        local bf = b.fight and byUid[b.fight]
        if bf then bossButton(y, bf) end
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
    -- encounters: the fights of the run that are still stored; no section when none is (every older run, once the
    -- desktop has read its fights)
    v.encounters = #(run.fights or {})
    if v.encounters > 0 then
      y = heading(y, ("Encounters  (%d)"):format(v.encounters))
      for i = #run.fights, 1, -1 do fightRow(y, run.fights[i]); y = y + 16 end
    end
    for j = fn + 1, #child.fs do child.fs[j]:Hide() end
    for j = tn + 1, #child.tex do child.tex[j]:Hide() end
    for j = bn + 1, #child.btn do child.btn[j]:Hide() end
    for j = bbn + 1, #child.bbtn do child.bbtn[j]:Hide() end
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
    local p = { lists, #rec.bosses, #rec.deaths, n0(rec.nDeaths and rec.nDeaths.me), tostring(rec.partial), n0(rec.secs.active), n0(rec.hidden and rec.hidden.xp) }
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
  v.emptyText = "No dungeon runs yet. Enter a dungeon and it shows up here.\n" .. Runs.SINCE
  -- Time · Dungeon · (in progress) · Length · Bosses · Deaths · Per hour · Loot
  local tbl = UI.Table(UI.Below(v, lock), {
    { key = "time", label = "Time", kind = "tag", color = "dim", measure = { "12/31 23:59" } },
    { key = "name", label = "Dungeon", flex = 1, min = 120 },
    { key = "live", label = "", kind = "tag", color = "green", measure = { "•" } },
    { key = "dur", label = "Length", kind = "num", color = "dim", measure = { "23h 59m" } },
    { key = "boss", label = "Bosses", kind = "num", measure = { "99" } },
    { key = "death", label = "Deaths", kind = "num", color = "dim", measure = { "99" } },
    { key = "rate", label = "Per hour", kind = "num", color = "dim", measure = { "999,999 XP/h" } },
    { key = "loot", label = "Loot", kind = "money", color = "gold", measure = { "999 · " .. fmtMoney(9999999) } },
  }, { top = 0, emptyText = v.emptyText,
    onClick = function(row) if row.run then openRun(row.run) end end,
    -- the clocks of the run, why it ended, and what is missing from it
    tooltip = function(row, _, tip)
      local run = row.run
      if not run then return end
      tip:AddLine(run.name or "Dungeon")
      for _, l in ipairs(v.tipLines(run)) do tip:AddLine(l) end
    end })
  v.tbl = tbl
  v.tipLines = function(run)
    local out = { "Inside " .. fmtDur(run.inside) }
    if n0(run.ghost) > 0 then out[#out + 1] = "Run back " .. fmtDur(run.ghost) end
    if n0(run.outside) > 0 then out[#out + 1] = "Outside " .. fmtDur(run.outside) end
    if n0(run.offline) > 0 then out[#out + 1] = "Offline " .. fmtDur(run.offline) end
    out[#out + 1] = "Active " .. fmtDur(run.active)
    if run.inProgress then out[#out + 1] = "In progress" else out[#out + 1] = Runs.endedLine(run) end
    if n0(run.reentries) > 0 then out[#out + 1] = ("Re-entered %d time%s"):format(run.reentries, run.reentries == 1 and "" or "s") end
    local partial = Runs.partialLine(run)
    if partial then out[#out + 1] = partial end
    return out
  end

  listRebuild = function()
    lock:SetText(lockText())
    local runs, rows = Runs.views(), {}
    for i = #runs, 1, -1 do rows[#rows + 1] = runs[i] end
    tbl.setRows(rows, function(row, run)
      row.run = run
      row.c.time:SetText(date("%m/%d %H:%M", run.startT or 0))
      row.c.name:SetText((run.name or "?") .. (run.kind == "raid" and "  ·  RAID" or "") .. (run.inProgress and "  ·  in progress" or ""))
      row.c.live:SetText(run.inProgress and "•" or "")
      row.c.dur:SetText(fmtDur(run.duration))
      row.c.boss:SetText(tostring(run.bossesDown or 0))
      row.c.death:SetText(tostring(run.deaths or 0))
      if (run.deaths or 0) > 0 then row.c.death:SetTextColor(C.red[1], C.red[2], C.red[3]) end
      row.c.rate:SetText(perHour(run))
      -- items and coin of the run's own gold block, as on its page
      local items, coin = run.items or 0, run.coin or 0
      row.c.loot:SetText((items > 0 and (items .. " · ") or "") .. fmtMoney(coin))
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
