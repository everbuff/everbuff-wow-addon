-- Everbuff.GG · Journey.lua (the HOME tab) - the landing dashboard.
--
-- The glanceable "how is my forever-classic run going?" screen: level + XP pace, /played, gold, kills
-- and deaths, and a recent-milestones ribbon. Everything here is READ from data other modules already
-- capture (Emitter's eventlog / gold / xp / played, Fights' fight list), so this file only presents.
-- A pure per-pull recorder like Warcraft Recorder has no equivalent; this is the journey identity.

local ADDON, ns = ...
local UI = ns.UI
local C = ns.UI.C

-- ── formatting ──────────────────────────────────────────────────────────────────
local function fmtMoney(c)
  c = math.floor(tonumber(c) or 0)
  local g, s, cp = math.floor(c / 10000), math.floor((c % 10000) / 100), c % 100
  local out = {}
  if g > 0 then out[#out + 1] = g .. "g" end
  if s > 0 then out[#out + 1] = s .. "s" end
  if cp > 0 or #out == 0 then out[#out + 1] = cp .. "c" end
  return table.concat(out, " ")
end
local function fmtTime(sec)
  sec = math.floor(tonumber(sec) or 0)
  if sec <= 0 then return "-" end
  local d, h, m = math.floor(sec / 86400), math.floor((sec % 86400) / 3600), math.floor((sec % 3600) / 60)
  if d > 0 then return ("%dd %dh"):format(d, h) end
  if h > 0 then return ("%dh %dm"):format(h, m) end
  return m .. "m"
end
local function commas(n)
  n = tostring(math.floor(tonumber(n) or 0))
  local out = n:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
  return out
end

-- milestone kinds worth surfacing on the ribbon, with a color
local MILE = {
  LEVELUP = C.gold, DEATH = C.red, ACHIEV = C.gold, DISCOVERY = C.data,
  FLIGHT = C.data, REP = C.gold, SPELL = C.data, WIPE = C.red, FIRSTZONE = C.data, BROKEN = C.red, COLLECT = C.gold, PROFTIER = C.gold, RECIPE = C.gold, UPGRADE = C.gold,
}

local build, refresh
local view    -- the content frame the framework builds for us (set in build, used by onShow)

-- HOME / Overview: the cards, the XP bar and the feed of this session. `content` is the pane.
build = function(content)
  view = content
  local ov = content
  -- first-run walkthrough: a card over the dashboard until "Got it". Three things a new player must know.
  local ob = UI.Panel(content); ob:SetPoint("TOPLEFT", 4, -8); ob:SetPoint("TOPRIGHT", -4, -8); ob:SetHeight(150)
  ob:SetFrameLevel((content:GetFrameLevel() or 1) + 20)
  local obT = UI.FS(ob, "GameFontNormal", C.gold); obT:SetPoint("TOPLEFT", 14, -12); obT:SetText("Welcome to everbuff.gg")
  local obB = UI.FS(ob, "GameFontHighlightSmall"); obB:SetPoint("TOPLEFT", 14, -34); obB:SetPoint("TOPRIGHT", -14, -34); obB:SetJustifyH("LEFT"); obB:SetSpacing(3)
  obB:SetText("1.  Keep the flag on screen. The desktop app reads it to mark the moments in your recording. Drag it anywhere, right-click to snap it to a corner.\n" ..
              "2.  Play. Fights, loot, deaths, quests and gold are captured on their own. Nothing to start or stop.\n" ..
              "3.  Home shows how your run is going. Combat has every fight with a replay. Loot has every pickup. Character has quests, reputation and professions.")
  local obOk = UI.Button(ob, "Got it", 90, 24, function()
    if ns.DB and ns.DB.settings then ns.DB.settings.onboarded = true end
    ob:Hide()
  end)
  obOk:SetPoint("BOTTOMRIGHT", -12, 10)
  local obSet = UI.Button(ob, "Open Settings", 110, 24, function() UI.Open("Settings") end)
  obSet:SetPoint("RIGHT", obOk, "LEFT", -8, 0)
  ob.okBtn = obOk
  content.onboard = ob
  if ns.DB and ns.DB.settings and ns.DB.settings.onboarded then ob:Hide() end
  content.welcome = UI.FS(content, "GameFontHighlightSmall", C.dim); content.welcome:SetPoint("BOTTOMLEFT", 4, 4); content.welcome:SetWidth(660); content.welcome:SetJustifyH("LEFT")
  content.welcome:SetText("Play, and this page fills in. The flag on screen is what the desktop app reads.")

  -- a stat card: dim title, big value, small sub. Returned with .value/.sub to update on refresh.
  -- `goto` = { tab, pane } the card drills into on click (the detail behind the number).
  local function card(x, y, w, h, goto)
    local p = UI.Panel(ov); p:SetSize(w, h); p:SetPoint("TOPLEFT", x, y)
    if goto then
      p:EnableMouse(true)
      p:SetScript("OnMouseUp", function() UI.Open(goto[1], goto[2]) end)
      p:SetScript("OnEnter", function(f) f:SetBackdropColor(C.panel2[1], C.panel2[2], C.panel2[3], 1); f:SetBackdropBorderColor(C.edgeHi[1], C.edgeHi[2], C.edgeHi[3], 1) end)
      p:SetScript("OnLeave", function(f) f:SetBackdropColor(C.panel[1], C.panel[2], C.panel[3], 0.92); f:SetBackdropBorderColor(C.edge[1], C.edge[2], C.edge[3], 1) end)
      p.more = UI.FS(p, "GameFontDisableSmall", C.dim); p.more:SetPoint("TOPRIGHT", -10, -9); p.more:SetText("›")
    end
    p.title = UI.FS(p, "GameFontNormalSmall", C.dim); p.title:SetPoint("TOPLEFT", 12, -9)
    p.value = UI.FS(p, "GameFontNormalLarge", C.ink); if UI.VALUE_FONT then p.value:SetFontObject(UI.VALUE_FONT) end; p.value:SetPoint("TOPLEFT", 12, -26)
    p.sub = UI.FS(p, "GameFontHighlightSmall", C.dim); p.sub:SetPoint("TOPLEFT", 12, -50)
    p.sub:SetWidth(w - 20); p.sub:SetJustifyH("LEFT")
    return p
  end

  local CW, CH, GAP, X0, Y0 = 220, 78, 12, 4, -8
  local col = { X0, X0 + CW + GAP, X0 + 2 * (CW + GAP) }
  content.cLevel  = card(col[1], Y0, CW, CH, { "Character", "professions" }); content.cLevel.title:SetText("CHARACTER")
  content.cXP     = card(col[2], Y0, CW, CH, { "Character", "quests" });      content.cXP.title:SetText("EXPERIENCE")
  content.cPlayed = card(col[3], Y0, CW, CH, { "Home", "sessions" });         content.cPlayed.title:SetText("TIME PLAYED")
  local Y1 = Y0 - CH - GAP
  content.cGold   = card(col[1], Y1, CW, CH, { "Loot", "gold" });             content.cGold.title:SetText("GOLD")
  content.cKills  = card(col[2], Y1, CW, CH, { "Combat", "fights" });         content.cKills.title:SetText("COMBAT")
  content.cPace   = card(col[3], Y1, CW, CH);                                 content.cPace.title:SetText("LEVELING PACE")

  -- full-width XP progress bar
  local barY = Y1 - CH - GAP - 4
  local track = UI.Panel(ov, C.bg[1], C.bg[2], C.bg[3]); track:SetHeight(14)
  track:SetPoint("TOPLEFT", X0, barY); track:SetPoint("TOPRIGHT", ov, "TOPLEFT", col[3] + CW, barY)
  local fill = track:CreateTexture(nil, "ARTWORK"); fill:SetPoint("TOPLEFT", 1, -1); fill:SetPoint("BOTTOMLEFT", 1, 1)
  fill:SetColorTexture(ns.UI.C.accentPressed[1], ns.UI.C.accentPressed[2], ns.UI.C.accentPressed[3], 1)   -- progress is the accent, pressed shade so the white label reads on it
  content.xpFill, content.xpTrack = fill, track
  content.xpText = UI.FS(ov, "GameFontHighlightSmall", C.ink); content.xpText:SetPoint("LEFT", track, "LEFT", 8, 0)

  -- this session's story: milestones newest first (the full feed with filters is the Timeline pane)
  local mh = UI.FS(ov, "GameFontNormal", C.gold); mh:SetPoint("TOPLEFT", X0, barY - 26); mh:SetText("This session")
  content.mhSub = UI.FS(ov, "GameFontDisableSmall", C.dim); content.mhSub:SetPoint("LEFT", mh, "RIGHT", 10, 0); content.mhSub:SetText("")
  local sf, mchild = UI.ScrollChild(ov)
  sf:SetPoint("TOPLEFT", X0 - 2, barY - 48); sf:SetPoint("BOTTOMRIGHT", -22, 2)
  mchild.rows = {}
  content.mchild = mchild

  refresh(content)
end

refresh = function(content)
  if not content or not content.cLevel then return end
  local D = ns.DB or {}
  local db = (ns.DB and ns.char()) or {}                  -- CHARACTER: xp, played, durability, ...
  local story, lootNS = D.story or {}, D.loot or {}
  if content.welcome then
    local fresh = #(story.events or {}) == 0 and #((D.combat or {}).fights or {}) == 0
    if fresh and not (content.onboard and content.onboard:IsShown()) then content.welcome:Show() else content.welcome:Hide() end
  end

  -- Character
  local lvl = (UnitLevel and UnitLevel("player")) or 0
  local pname = (UnitName and UnitName("player")) or "?"
  local raceN = (UnitRace and UnitRace("player")) or ""
  local classN, classFile = "", nil
  if UnitClass then classN, classFile = UnitClass("player") end
  local r, g, b = UI.ClassColor(classFile)
  content.cLevel.value:SetText("Level " .. lvl); content.cLevel.value:SetTextColor(r, g, b)
  local gear = (db.durability and db.durability.pct) and ("  ·  gear " .. db.durability.pct .. "%") or ""
  content.cLevel.sub:SetText(("%s  ·  %s %s%s"):format(pname, raceN, classN, gear))

  -- Experience
  local xp = db.xp or {}
  local cur, max = tonumber(xp.cur) or 0, tonumber(xp.max) or 0
  local pct = (max > 0) and (cur / max * 100) or 0
  if lvl >= (GetMaxPlayerLevel and GetMaxPlayerLevel() or 60) then
    content.cXP.value:SetText("Max"); content.cXP.sub:SetText("Level cap reached")
    content.xpFill:SetWidth(1); content.xpText:SetText("")
  else
    content.cXP.value:SetText(("%.0f%%"):format(pct))
    local rested = tonumber(xp.rested) or 0
    local q, k = tonumber(xp.fromQuests) or 0, tonumber(xp.fromKills) or 0
    local split = (q + k) > 0 and ("  ·  quests %d%% / kills %d%%"):format(math.floor(q / (q + k) * 100 + 0.5), math.floor(k / (q + k) * 100 + 0.5)) or ""
    content.cXP.sub:SetText(("%s / %s%s%s"):format(commas(cur), commas(max),
      rested > 0 and ("  ·  rested " .. commas(rested)) or "", split))
    local tw = content.xpTrack:GetWidth()
    if tw and tw > 2 then content.xpFill:SetWidth(math.max(1, (tw - 2) * (pct / 100))) end
    content.xpText:SetText(("XP  %s / %s  (%.0f%%)"):format(commas(cur), commas(max), pct))
  end

  -- Time played
  local pl = db.played or {}
  content.cPlayed.value:SetText(fmtTime(pl.total))
  content.cPlayed.sub:SetText(pl.level and ("this level: " .. fmtTime(pl.level)) or "play a bit to record")

  -- Gold
  local gold = lootNS.gold or {}
  content.cGold.value:SetText(fmtMoney(gold.balance or 0)); content.cGold.value:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
  content.cGold.sub:SetText(("looted %s  ·  spent %s"):format(fmtMoney(gold.looted or 0), fmtMoney(gold.spent or 0)))

  -- Combat (from the event timeline: every kill/death lands there)
  local kills, deaths = 0, 0
  for _, e in ipairs(story.events or {}) do
    if e.kind == "KILL" then kills = kills + 1 elseif e.kind == "DEATH" then deaths = deaths + 1 end
  end
  local fights = (ns.Fights and ns.Fights.list and #ns.Fights.list()) or 0
  content.cKills.value:SetText(commas(kills) .. " kills"); content.cKills.value:SetTextColor(C.green[1], C.green[2], C.green[3])
  content.cKills.sub:SetText(("%d death%s  ·  %d fights recorded"):format(deaths, deaths == 1 and "" or "s", fights))

  -- Leveling pace: time played across the last levels (from the per-level /played stamps)
  local pace = "-"
  local pal = db.playedAtLevel
  if pal and lvl and lvl > 1 and pal[lvl] and pal[lvl - 1] then
    pace = fmtTime(pal[lvl] - pal[lvl - 1])
  end
  -- session rate: XP gained since login over wall-clock time since login
  local ses = (ns.Recorder and ns.Recorder.current and ns.Recorder.current()) or {}
  local elapsed = (ses.startedEpoch and ((GetServerTime and GetServerTime()) or time()) - ses.startedEpoch) or 0
  local sxp = tonumber(ses.xp) or 0
  local rate = (elapsed >= 120 and sxp > 0) and (sxp / (elapsed / 3600)) or 0
  if rate > 0 then
    content.cPace.value:SetText(commas(math.floor(rate + 0.5)) .. " XP/hr")
    local toLevel = (max > cur) and ((max - cur) / rate * 3600) or 0
    local bits = {}
    if toLevel > 0 and lvl < (GetMaxPlayerLevel and GetMaxPlayerLevel() or 60) then bits[#bits + 1] = "level in ~" .. fmtTime(toLevel) end
    if pace ~= "-" then bits[#bits + 1] = "last level took " .. pace end
    content.cPace.sub:SetText(#bits > 0 and table.concat(bits, "  ·  ") or "this session")
  else
    content.cPace.value:SetText(pace)
    content.cPace.sub:SetText(pace ~= "-" and "played for the last level  ·  XP/hr after a few minutes" or "levels timed as you play")
  end

  -- This session's milestones (falls back to everything when the session id is unknown)
  local mchild = content.mchild
  local log = story.events or {}
  local sid = D.active
  local y, idx = 0, 0
  if content.mhSub then
    local ses = (ns.Recorder and ns.Recorder.current and ns.Recorder.current()) or {}
    local el = (ses.startedEpoch and ((GetServerTime and GetServerTime()) or time()) - ses.startedEpoch) or 0
    content.mhSub:SetText(el > 0 and ("started %s ago  ·  %d kills  ·  %d deaths  ·  %d items"):format(fmtTime(el) ~= "-" and fmtTime(el) or "moments", tonumber(ses.kills) or 0, tonumber(ses.deaths) or 0, tonumber(ses.items) or 0) or "")
  end
  for i = #log, 1, -1 do
    local e = log[i]
    if MILE[e.kind] and (sid == nil or e.s == nil or e.s == sid) then
      idx = idx + 1
      local row = mchild.rows[idx]
      if not row then
        row = CreateFrame("Frame", nil, mchild); row:SetHeight(16); row:SetPoint("RIGHT", mchild, "RIGHT", 0, 0)
        row.tm = ns.UI.FS(row, "GameFontDisableSmall"); row.tm:SetPoint("LEFT", 0, 0); row.tm:SetWidth(64)
        row.tx = ns.UI.FS(row, "GameFontHighlightSmall"); row.tx:SetPoint("LEFT", 70, 0); row.tx:SetWidth(580); row.tx:SetJustifyH("LEFT")
        mchild.rows[idx] = row
      end
      row:SetPoint("TOPLEFT", 0, -y); row:Show()
      row.tm:SetText(date("%H:%M", e.t or 0)); row.tm:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
      local col = MILE[e.kind] or C.ink
      row.tx:SetText(e.text or e.kind or "?"); row.tx:SetTextColor(col[1], col[2], col[3])
      y = y + 16
      if idx >= 40 then break end
    end
  end
  for j = idx + 1, #mchild.rows do mchild.rows[j]:Hide() end
  if idx == 0 then
    mchild.empty = mchild.empty or (function()
      local fs = ns.UI.FS(mchild, "GameFontDisableSmall")
      fs:SetPoint("TOPLEFT", 0, 0); fs:SetText("Nothing yet this session. Level up, explore, fight, and it shows up here."); return fs
    end)()
    mchild.empty:Show()
  elseif mchild.empty then mchild.empty:Hide() end
  mchild:SetSize(660, math.max(1, y))
end

-- ── HOME / Sessions: one row per play session (login -> logout), newest first ─────
local sessionsRebuild, sessionsView
local function sessionRows()
  local out = {}
  for id, sess in pairs((ns.DB and ns.DB.sessions) or {}) do out[#out + 1] = sess end
  -- the live session first, then newest first (ids break ties within the same second)
  table.sort(out, function(a, b)
    local la, lb = a.endedEpoch == nil, b.endedEpoch == nil
    if la ~= lb then return la end
    if (a.startedEpoch or 0) ~= (b.startedEpoch or 0) then return (a.startedEpoch or 0) > (b.startedEpoch or 0) end
    return tostring(a.id) > tostring(b.id)
  end)
  return out
end
-- a strip of bars, one per session (oldest left), value scaled to the strip height; negative values
-- hang below the baseline in ember. Pooled textures; hover names the session and value.
local STRIP_N, STRIP_H, BAR_W, BAR_GAP = 10, 44, 28, 4
local function makeStrip(parent, x, y, label)
  local st = CreateFrame("Frame", nil, parent); st:SetPoint("TOPLEFT", x, y); st:SetSize(STRIP_N * (BAR_W + BAR_GAP), STRIP_H + 18)
  st.title = UI.FS(st, "GameFontNormalSmall", C.dim); st.title:SetPoint("TOPLEFT", 0, 0); st.title:SetText(label:upper())
  st.base = st:CreateTexture(nil, "ARTWORK"); st.base:SetPoint("BOTTOMLEFT", 0, 0); st.base:SetPoint("BOTTOMRIGHT", 0, 0); st.base:SetHeight(1)
  st.base:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
  st.bars, st.hits = {}, {}
  return st
end
-- values: array of { v = number, label = string } oldest first; fmt(v) renders the hover text
local function renderStrip(st, values, fmt, signed)
  local maxAbs = 1
  for _, e in ipairs(values) do if math.abs(e.v) > maxAbs then maxAbs = math.abs(e.v) end end
  local baseY = signed and STRIP_H / 2 or 0
  st.base:ClearAllPoints(); st.base:SetPoint("BOTTOMLEFT", 0, baseY); st.base:SetPoint("BOTTOMRIGHT", 0, baseY)
  local span = signed and STRIP_H / 2 or STRIP_H
  for i = 1, STRIP_N do
    local e = values[i]
    local bar = st.bars[i]; local hit = st.hits[i]
    if not bar then
      bar = st:CreateTexture(nil, "ARTWORK"); st.bars[i] = bar
      hit = CreateFrame("Frame", nil, st); hit:SetSize(BAR_W, STRIP_H); hit:EnableMouse(true); st.hits[i] = hit
      hit:SetScript("OnEnter", function(h) if h.tip and GameTooltip then GameTooltip:SetOwner(h, "ANCHOR_TOP"); GameTooltip:AddLine(h.tip, 1, 1, 1); GameTooltip:Show() end end)
      hit:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    end
    if e then
      local h = math.max(1, math.floor(math.abs(e.v) / maxAbs * (span - 2) + 0.5))
      bar:ClearAllPoints(); bar:SetWidth(BAR_W); bar:SetHeight(h)
      if e.v < 0 then bar:SetPoint("TOP", st, "BOTTOMLEFT", (i - 1) * (BAR_W + BAR_GAP) + BAR_W / 2, baseY)
      else bar:SetPoint("BOTTOM", st, "BOTTOMLEFT", (i - 1) * (BAR_W + BAR_GAP) + BAR_W / 2, baseY) end
      local col = e.v < 0 and C.red or (e.live and C.cyan or C.gold)
      bar:SetColorTexture(col[1], col[2], col[3], 0.85); bar:Show()
      hit:ClearAllPoints(); hit:SetPoint("BOTTOMLEFT", (i - 1) * (BAR_W + BAR_GAP), 0); hit.tip = e.label .. "  ·  " .. fmt(e.v); hit:Show()
    else bar:Hide(); hit:Hide() end
  end
end
local function stripValues(rows, key, signed)
  -- rows newest first -> take the last STRIP_N, oldest left
  local out = {}
  local n = math.min(#rows, STRIP_N)
  for i = n, 1, -1 do
    local sess = rows[i]
    local v = signed and ((tonumber(sess.gained) or 0) - (tonumber(sess.spent) or 0)) or (tonumber(sess[key]) or 0)
    out[#out + 1] = { v = v, label = date("%b %d, %H:%M", sess.startedEpoch or 0), live = (sess.endedEpoch == nil) }
  end
  return out
end
ns._test = ns._test or {}
ns._test.stripValues = stripValues

local function buildSessions(content)
  sessionsView = content
  local xpStrip = makeStrip(content, 2, -4, "XP per session")
  local goldStrip = makeStrip(content, 2 + STRIP_N * (BAR_W + BAR_GAP) + 20, -4, "Gold per session")
  content.xpStrip, content.goldStrip = xpStrip, goldStrip
  local COL = { date = 0, len = 116, lvl = 190, xp = 250, gold = 330, kills = 428, deaths = 486, dung = 550, items = 622 }
  local WID = { date = 110, len = 70, lvl = 56, xp = 76, gold = 94, kills = 54, deaths = 60, dung = 68, items = 48 }
  local hdr = CreateFrame("Frame", nil, content); hdr:SetPoint("TOPLEFT", 2, -(STRIP_H + 30)); hdr:SetSize(670, 16)
  local function head(k, text)
    local fs = UI.FS(hdr, "GameFontNormalSmall"); fs:SetPoint("LEFT", COL[k], 0); fs:SetWidth(WID[k]); fs:SetJustifyH("LEFT")
    fs:SetText(text:upper()); fs:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
  end
  head("date", "Session"); head("len", "Length"); head("lvl", "Level"); head("xp", "XP"); head("gold", "Gold"); head("kills", "Kills"); head("deaths", "Deaths"); head("dung", "Dungeons"); head("items", "Items")
  local sf, child = UI.ScrollChild(content)
  sf:SetPoint("TOPLEFT", 0, -(STRIP_H + 50)); sf:SetPoint("BOTTOMRIGHT", -22, 2)
  child.rows = {}
  sessionsRebuild = function()
    local rows = sessionRows()
    renderStrip(xpStrip, stripValues(rows, "xp"), function(v) return commas(v) .. " XP" end, false)
    renderStrip(goldStrip, stripValues(rows, nil, true), function(v) return (v < 0 and "-" or "+") .. fmtMoney(math.abs(v)) end, true)
    local nowT = (GetServerTime and GetServerTime()) or time()
    local y, idx = 0, 0
    for _, sess in ipairs(rows) do
      idx = idx + 1
      local row = child.rows[idx]
      if not row then
        row = CreateFrame("Frame", nil, child); row:SetHeight(18); row:SetPoint("RIGHT", child, "RIGHT", 0, 0); row.c = {}
        for k, x in pairs(COL) do
          local fs = UI.FS(row, "GameFontHighlightSmall"); fs:SetPoint("LEFT", x, 0); fs:SetWidth(WID[k]); fs:SetJustifyH("LEFT"); row.c[k] = fs
        end
        child.rows[idx] = row
      end
      row:SetPoint("TOPLEFT", 0, -y); row:Show()
      local live = (sess.endedEpoch == nil)
      local endT = sess.endedEpoch or nowT
      row.c.date:SetText(date("%b %d, %H:%M", sess.startedEpoch or 0) .. (live and "  |cff59c77f•|r" or "")); row.c.date:SetTextColor(C.ink[1], C.ink[2], C.ink[3])
      row.c.len:SetText(fmtTime(math.max(0, endT - (sess.startedEpoch or endT)))); row.c.len:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
      local l0, l1 = tonumber(sess.level0) or tonumber(sess.level) or 0, tonumber(sess.level) or 0
      row.c.lvl:SetText(l1 > l0 and (l0 .. " > " .. l1) or tostring(l1)); row.c.lvl:SetTextColor(l1 > l0 and C.gold[1] or C.ink[1], l1 > l0 and C.gold[2] or C.ink[2], l1 > l0 and C.gold[3] or C.ink[3])
      row.c.xp:SetText(commas(sess.xp or 0)); row.c.xp:SetTextColor(C.ink[1], C.ink[2], C.ink[3])
      local net = (tonumber(sess.gained) or 0) - (tonumber(sess.spent) or 0)
      row.c.gold:SetText((net < 0 and "-" or "+") .. fmtMoney(math.abs(net))); row.c.gold:SetTextColor(net < 0 and C.red[1] or C.gold[1], net < 0 and C.red[2] or C.gold[2], net < 0 and C.red[3] or C.gold[3])
      row.c.kills:SetText(tostring(sess.kills or 0)); row.c.kills:SetTextColor(C.ink[1], C.ink[2], C.ink[3])
      row.c.deaths:SetText(tostring(sess.deaths or 0)); local dc = (tonumber(sess.deaths) or 0) > 0 and C.red or C.dim; row.c.deaths:SetTextColor(dc[1], dc[2], dc[3])
      row.c.dung:SetText(tostring(sess.dungeons or 0)); row.c.dung:SetTextColor(C.ink[1], C.ink[2], C.ink[3])
      row.c.items:SetText(tostring(sess.items or 0)); row.c.items:SetTextColor(C.ink[1], C.ink[2], C.ink[3])
      y = y + 18
    end
    for j = idx + 1, #child.rows do child.rows[j]:Hide() end
    if idx == 0 then
      child.empty = child.empty or (function() local fs = UI.FS(child, "GameFontDisableSmall"); fs:SetPoint("TOPLEFT", 0, 0); fs:SetText("Your first session starts when you log in."); return fs end)()
      child.empty:Show()
    elseif child.empty then child.empty:Hide() end
    child:SetSize(math.max(670, (sf:GetWidth() or 670) - 4), math.max(1, y))
  end
  sessionsRebuild()
end

-- HOME is the landing tab (order 0). Overview and Sessions live here; the Timeline pane is registered
-- into Home by Emitter.lua.
UI.registerHost(0, "Home", "How your run is going, the story of this session, and every session before it.")
local ticker
UI.registerPane("Home", 1, "Overview", build, function()
  if view then refresh(view) end
  -- light live refresh while the dashboard is the visible pane; cancels itself when it isn't
  if not ticker then
    ticker = C_Timer.NewTicker(3, function()
      if view and view:IsShown() then refresh(view) end
      if sessionsView and sessionsView:IsShown() and sessionsRebuild then sessionsRebuild() end
    end)
  end
end)
UI.registerPane("Home", 3, "Sessions", buildSessions, function() if sessionsRebuild then sessionsRebuild() end end)

-- ── test exports: headless luajit tests in tests/ read these; no effect in-game ──
ns._test = ns._test or {}
ns._test.sessionRows = sessionRows
ns._test.fmtTime, ns._test.commas, ns._test.journeyMoney = fmtTime, commas, fmtMoney
