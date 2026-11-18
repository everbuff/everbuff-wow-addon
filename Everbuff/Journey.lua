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
local fmtMoney = ns.fmtMoney   -- the one formatter (UI.lua)
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
  local SP = UI.SP
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
  content.welcome = UI.FS(content, "GameFontHighlightSmall", C.dim)
  content.welcome:SetPoint("BOTTOMLEFT", 4, 4); content.welcome:SetPoint("BOTTOMRIGHT", -4, 4); content.welcome:SetJustifyH("LEFT")
  content.welcome:SetText("Play, and this page fills in. The flag on screen is what the desktop app reads.")

  -- a stat card: dim title, big value, small sub between the card's edges. Title and value are one line; the sub takes
  -- a second line when it does not fit, so a number in it is never cut. Returned with .value/.sub to update on refresh. `drill` = { tab, pane } the card drills into on click (the detail behind the number).
  local PADC = SP.M
  local function oneLine(fs) if fs.SetWordWrap then fs:SetWordWrap(false) end; if fs.SetMaxLines then fs:SetMaxLines(1) end; fs:SetJustifyH("LEFT"); return fs end
  local function card(drill)
    local p = UI.Panel(ov)
    if drill then
      p:EnableMouse(true)
      p:SetScript("OnMouseUp", function() UI.Open(drill[1], drill[2]) end)
      p:SetScript("OnEnter", function(f) f:SetBackdropColor(C.panel2[1], C.panel2[2], C.panel2[3], 1); f:SetBackdropBorderColor(C.edgeHi[1], C.edgeHi[2], C.edgeHi[3], 1) end)
      p:SetScript("OnLeave", function(f) f:SetBackdropColor(C.panel[1], C.panel[2], C.panel[3], 0.92); f:SetBackdropBorderColor(C.edge[1], C.edge[2], C.edge[3], 1) end)
      p.more = UI.FS(p, "GameFontDisableSmall", C.dim); p.more:SetPoint("TOPRIGHT", -10, -9); p.more:SetText("›")
    end
    p.title = oneLine(UI.FS(p, "GameFontNormalSmall", C.dim)); p.title:SetPoint("TOPLEFT", PADC, -9); p.title:SetPoint("TOPRIGHT", -(PADC + 12), -9)
    p.value = oneLine(UI.CellFS(p, "GameFontNormalLarge", C.ink)); if UI.VALUE_FONT then p.value:SetFontObject(UI.VALUE_FONT) end
    p.value:SetPoint("TOPLEFT", PADC, -26); p.value:SetPoint("TOPRIGHT", -PADC, -26)
    p.sub = UI.CellFS(p, "GameFontHighlightSmall", C.dim); p.sub:SetPoint("TOPLEFT", PADC, -50); p.sub:SetPoint("TOPRIGHT", -PADC, -50)
    p.sub:SetJustifyH("LEFT"); p.sub:SetJustifyV("TOP")
    if p.sub.SetWordWrap then p.sub:SetWordWrap(true) end
    if p.sub.SetMaxLines then p.sub:SetMaxLines(2) end
    return p
  end

  -- three cards over three, filling the pane's width with the same X0 inset on both sides (the feed below keeps its
  -- own scroll bar gutter; the cards do not scroll, so they leave none)
  local CH, LINE, GAP, X0, Y0 = 78, 14, SP.M, SP.XS, -8
  content.cLevel  = card({ "Character", "professions" }); content.cLevel.title:SetText("CHARACTER")
  content.cXP     = card({ "Character", "quests" });      content.cXP.title:SetText("EXPERIENCE")
  content.cPlayed = card({ "Home", "sessions" });         content.cPlayed.title:SetText("TIME PLAYED")
  content.cGold   = card({ "Loot", "gold" });             content.cGold.title:SetText("GOLD")
  -- the Gold card's own second line under its subtitle: what every character holds together (0.9.44, #43). One
  -- line of its own, so it is never the part a wrapped subtitle loses; the row grows by a line when it is set.
  do
    local p = content.cGold
    p.sub2 = UI.CellFS(p, "GameFontHighlightSmall", C.dim)
    p.sub2:SetPoint("TOPLEFT", p.sub, "BOTTOMLEFT", 0, 0); p.sub2:SetPoint("TOPRIGHT", p.sub, "BOTTOMRIGHT", 0, 0)
    p.sub2:SetJustifyH("LEFT")
  end
  content.cKills  = card({ "Combat", "fights" });         content.cKills.title:SetText("COMBAT")
  content.cPace   = card();                               content.cPace.title:SetText("LEVELING PACE")
  local grid = { { content.cLevel, content.cXP, content.cPlayed }, { content.cGold, content.cKills, content.cPace } }

  -- full-width XP progress bar, under the cards
  local track = UI.Panel(ov, C.bg[1], C.bg[2], C.bg[3]); track:SetHeight(14)
  track:SetPoint("TOPLEFT", grid[2][1], "BOTTOMLEFT", 0, -(GAP + 4)); track:SetPoint("TOPRIGHT", grid[2][3], "BOTTOMRIGHT", 0, -(GAP + 4))
  local fill = track:CreateTexture(nil, "ARTWORK"); fill:SetPoint("TOPLEFT", 1, -1); fill:SetPoint("BOTTOMLEFT", 1, 1)
  fill:SetColorTexture(ns.UI.C.accentPressed[1], ns.UI.C.accentPressed[2], ns.UI.C.accentPressed[3], 1)   -- progress is the accent, pressed shade so the white label reads on it
  content.xpFill, content.xpTrack = fill, track
  content.xpPct = 0
  content.xpText = UI.FS(ov, "GameFontHighlightSmall", C.ink); content.xpText:SetPoint("LEFT", track, "LEFT", 8, 0)
  -- the fill follows the track's width
  content.placeXP = function()
    local tw = track:GetWidth()
    if tw and tw > 2 then fill:SetWidth(math.max(1, (tw - 2) * (content.xpPct / 100))) end
  end

  -- cards sized from the pane's width: three columns with M gaps, the last one takes the rounding. A row is one line
  -- taller when a subtitle in it needs a second line; every card of a row shares the row's height.
  local function relayout(w)
    w = tonumber(w) or 0
    if w <= 1 then return end
    local avail = w - 2 * X0
    local cw = math.floor((avail - 2 * GAP) / 3)
    local y = Y0
    for _, rowCards in ipairs(grid) do
      local extra = 0
      for c, p in ipairs(rowCards) do
        local pw = (c == 3) and (avail - 2 * (cw + GAP)) or cw
        local sw = tonumber(p.sub:GetStringWidth()) or 0
        local n = (sw > pw - 2 * PADC) and 1 or 0
        if p.sub2 and p.sub2On then n = n + 1 end
        if n > extra then extra = n end
      end
      local h = CH + extra * LINE
      for c, p in ipairs(rowCards) do
        local x = X0 + (c - 1) * (cw + GAP)
        p:ClearAllPoints(); p:SetPoint("TOPLEFT", ov, "TOPLEFT", x, y)
        p:SetSize((c == 3) and (avail - 2 * (cw + GAP)) or cw, h)
      end
      y = y - h - GAP
    end
    content.placeXP()
  end
  content.relayout = relayout
  content:HookScript("OnSizeChanged", function(_, w) pcall(relayout, w) end)
  pcall(relayout, content:GetWidth())

  -- this session's story: milestones newest first (the full feed with filters is the Timeline pane)
  local mh = UI.FS(ov, "GameFontNormal", C.gold); mh:SetPoint("TOPLEFT", track, "BOTTOMLEFT", 0, -SP.M); mh:SetText("This session")
  content.mhSub = oneLine(UI.FS(ov, "GameFontDisableSmall", C.dim))
  content.mhSub:SetPoint("TOPLEFT", mh, "TOPRIGHT", 10, -2); content.mhSub:SetPoint("TOPRIGHT", track, "BOTTOMRIGHT", 0, -(SP.M + 2)); content.mhSub:SetText("")
  -- the feed: time and milestone, no header; a shortened milestone reads in full on hover
  local feed = CreateFrame("Frame", nil, ov)
  feed:SetPoint("TOPLEFT", mh, "BOTTOMLEFT", -X0, -SP.S); feed:SetPoint("BOTTOMRIGHT", ov, "BOTTOMRIGHT", 0, 0)
  local mtbl = UI.Table(feed, {
    { key = "time", label = "", kind = "tag", color = "dim", measure = { "23:59" } },
    { key = "text", label = "", flex = 1, min = 120 },
  }, { top = 0, header = false, inset = SP.S,
    emptyText = "Nothing yet this session. Level up, explore, fight, and it shows up here." })
  content.mtbl, content.msf, content.mchild = mtbl, mtbl.sf, mtbl.child

  refresh(content)
end
refresh = function(content)
  if not content or not content.cLevel then return end
  local D = ns.DB or {}
  local db = (ns.DB and ns.char()) or {}                  -- CHARACTER: xp, played, durability, ...
  local story = D.story or {}
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
    content.xpPct = 0; content.placeXP(); content.xpText:SetText("")
  else
    content.cXP.value:SetText(("%.0f%%"):format(pct))
    local rested = tonumber(xp.rested) or 0
    local q, k = tonumber(xp.fromQuests) or 0, tonumber(xp.fromKills) or 0
    local split = (q + k) > 0 and ("  ·  quests %d%% / kills %d%%"):format(math.floor(q / (q + k) * 100 + 0.5), math.floor(k / (q + k) * 100 + 0.5)) or ""
    content.cXP.sub:SetText(("%s / %s%s%s"):format(commas(cur), commas(max),
      rested > 0 and ("  ·  rested " .. commas(rested)) or "", split))
    content.xpPct = math.max(0, math.min(100, pct)); content.placeXP()
    content.xpText:SetText(("XP  %s / %s  (%.0f%%)"):format(commas(cur), commas(max), pct))
  end

  -- Time played
  local pl = db.played or {}
  content.cPlayed.value:SetText(fmtTime(pl.total))
  content.cPlayed.sub:SetText(pl.level and ("this level: " .. fmtTime(pl.level)) or "play a bit to record")

  -- Gold
  local gold = db.gold or {}   -- the character's own ledger (#23); loot.gold is retired
  content.cGold.value:SetText(fmtMoney(gold.balance or 0)); content.cGold.value:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
  -- a label and its amount are joined by a no-break space, so a wrap can only fall at the separator
  -- the balance, then today's net (the period the Gold pane opens on) and today's pace: the same day's net over the
  -- time played that day, so the two numbers are of one period (nothing under 5 minutes played). With more than one
  -- character known, what they hold together on a line of its own (0.9.44, everbuff-wow-addon #43)
  local sub2 = ""
  if ns.Gold then
    local sub = ("today%s%s"):format(UI.NBSP, ns.Gold.signed(ns.Gold.metric("net", "char", "today")))
    local rate = ns.Gold.metric("perHour", "char", "today")
    if rate then sub = sub .. ("  ·  %s%sper%shour"):format(ns.Gold.signed(rate), UI.NBSP, UI.NBSP) end
    local ro = ns.Gold.roster("all")
    if ro.count > 1 then sub2 = ("all characters %s"):format(fmtMoney(ro.total)) end
    content.cGold.sub:SetText(sub)
  else content.cGold.sub:SetText("") end
  content.cGold.sub2:SetText(sub2); content.cGold.sub2On = sub2 ~= ""

  -- Combat (from the event timeline: every kill/death lands there)
  local kills, deaths = 0, 0
  for _, e in ipairs(story.events or {}) do   -- the logged-in character's only (#23)
    if ns.isMine(e) then
      if e.kind == "KILL" then kills = kills + 1 elseif e.kind == "DEATH" then deaths = deaths + 1 end
    end
  end
  local fights = 0
  for _, fi in ipairs((ns.Fights and ns.Fights.list and ns.Fights.list()) or {}) do if ns.isMine(fi) then fights = fights + 1 end end
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
  local log = story.events or {}
  local sid = D.active
  if content.mhSub then
    local ses = (ns.Recorder and ns.Recorder.current and ns.Recorder.current()) or {}
    local el = (ses.startedEpoch and ((GetServerTime and GetServerTime()) or time()) - ses.startedEpoch) or 0
    content.mhSub:SetText(el > 0 and ("started %s ago  ·  %d kills  ·  %d deaths  ·  %d items"):format(fmtTime(el) ~= "-" and fmtTime(el) or "moments", tonumber(ses.kills) or 0, tonumber(ses.deaths) or 0, tonumber(ses.items) or 0) or "")
  end
  local miles = {}
  for i = #log, 1, -1 do
    local e = log[i]
    if MILE[e.kind] and (sid == nil or e.s == nil or e.s == sid) and ns.isMine(e) then
      miles[#miles + 1] = e
      if #miles >= 40 then break end
    end
  end
  content.mtbl.setRows(miles, function(row, e)
    row.c.time:SetText(date("%H:%M", e.t or 0))
    local col = MILE[e.kind] or C.ink
    row.c.text:SetText(e.text or e.kind or "?"); row.c.text:SetTextColor(col[1], col[2], col[3])
  end)
  -- the subtitles just set decide whether a card row needs its second line
  if content.relayout then pcall(content.relayout, content:GetWidth()) end
end

-- ── HOME / Sessions: one row per play session (login -> logout), newest first ─────
local sessionsRebuild, sessionsView
local function sessionRows()
  local out = {}
  for id, sess in pairs((ns.DB and ns.DB.sessions) or {}) do if ns.isMySession(sess) then out[#out + 1] = sess end end   -- the logged-in character's (#23)
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
-- hang below the baseline in ember. Pooled textures; hover names the session and value. The strip is as wide as
-- the pane gives it (placeStrips): each of the STRIP_N slots is stripW / STRIP_N wide and holds a bar of at most
-- BAR_MAX px, centred in it.
local STRIP_N, STRIP_H, BAR_W, BAR_GAP, BAR_MAX = 10, 44, 28, 4, 56
local function makeStrip(parent, label, n)
  local st = CreateFrame("Frame", nil, parent); st:SetSize((n or STRIP_N) * (BAR_W + BAR_GAP), STRIP_H + 18)
  st.n = n or STRIP_N
  st.slot, st.barW = BAR_W + BAR_GAP, BAR_W
  st.title = UI.FS(st, "GameFontNormalSmall", C.dim); st.title:SetPoint("TOPLEFT", 0, 0); st.title:SetText(label:upper())
  st.base = st:CreateTexture(nil, "ARTWORK"); st.base:SetPoint("BOTTOMLEFT", 0, 0); st.base:SetPoint("BOTTOMRIGHT", 0, 0); st.base:SetHeight(1)
  st.base:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
  st.bars, st.hits = {}, {}
  return st
end
-- values: array of { v = number, label = string } oldest first (false leaves a slot empty); fmt(v) renders the hover text
local function renderStrip(st, values, fmt, signed)
  st.values, st.fmt, st.signed = values, fmt, signed   -- drawn again when the strip takes a new width
  local slot, bw = st.slot, st.barW
  local maxAbs = 1
  -- (a slot may be empty: false, as the Days strip of Loot > Gold leaves a day without a row)
  for i = 1, st.n or STRIP_N do local e = values[i]; if e and math.abs(e.v) > maxAbs then maxAbs = math.abs(e.v) end end
  local baseY = signed and STRIP_H / 2 or 0
  st.base:ClearAllPoints(); st.base:SetPoint("BOTTOMLEFT", 0, baseY); st.base:SetPoint("BOTTOMRIGHT", 0, baseY)
  local span = signed and STRIP_H / 2 or STRIP_H
  for i = 1, st.n or STRIP_N do
    local e = values[i]
    local bar = st.bars[i]; local hit = st.hits[i]
    if not bar then
      bar = st:CreateTexture(nil, "ARTWORK"); st.bars[i] = bar
      hit = CreateFrame("Frame", nil, st); hit:EnableMouse(true); st.hits[i] = hit
      hit:SetScript("OnEnter", function(h) if h.tip and GameTooltip then GameTooltip:SetOwner(h, "ANCHOR_TOP"); GameTooltip:AddLine(h.tip, 1, 1, 1); GameTooltip:Show() end end)
      hit:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    end
    if e then
      local h = math.max(1, math.floor(math.abs(e.v) / maxAbs * (span - 2) + 0.5))
      bar:ClearAllPoints(); bar:SetWidth(bw); bar:SetHeight(h)
      local cx = (i - 1) * slot + slot / 2
      if e.v < 0 then bar:SetPoint("TOP", st, "BOTTOMLEFT", cx, baseY)
      else bar:SetPoint("BOTTOM", st, "BOTTOMLEFT", cx, baseY) end
      local col = e.v < 0 and C.red or (e.live and C.cyan or C.gold)
      bar:SetColorTexture(col[1], col[2], col[3], 0.85); bar:Show()
      hit:ClearAllPoints(); hit:SetSize(slot, STRIP_H); hit:SetPoint("BOTTOMLEFT", (i - 1) * slot, 0); hit.tip = e.label .. "  ·  " .. fmt(e.v); hit:Show()
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
-- the strip is also the Days view's (Loot > Gold, Economy.lua): one bar per day
UI.makeStrip, UI.renderStrip, UI.STRIP_H = makeStrip, renderStrip, STRIP_H + 18

local BAND_H = 104          -- the selected session's gold band under the list
local sel = {}              -- sel.id: the session clicked; sel.shown: the session the band shows
local function buildSessions(content)
  sessionsView = content
  local xpStrip = makeStrip(content, "XP per session")
  local goldStrip = makeStrip(content, "Gold per session")
  content.xpStrip, content.goldStrip = xpStrip, goldStrip
  -- the two strips share the list's width in two halves, L apart, from the table's text inset (SP.S) to its right
  -- inset, so their titles line up with the SESSION header and the right half of the row is used
  local function placeStrips(w)
    w = tonumber(w) or 0
    if w <= 1 then return end
    local SP = UI.SP
    local left, right = SP.S, w - UI.SCROLLBAR - SP.S
    local half = math.floor((right - left - SP.L) / 2)
    for i, st in ipairs({ xpStrip, goldStrip }) do
      st:ClearAllPoints(); st:SetPoint("TOPLEFT", content, "TOPLEFT", left + (i - 1) * (half + SP.L), -4)
      st:SetWidth(half)
      st.slot = half / STRIP_N
      st.barW = math.max(4, math.min(BAR_MAX, math.floor(st.slot - BAR_GAP)))
      if st.values then renderStrip(st, st.values, st.fmt, st.signed) end
    end
  end
  content.placeStrips = placeStrips
  content:HookScript("OnSizeChanged", function(_, w) pcall(placeStrips, w) end)
  pcall(placeStrips, content:GetWidth())
  -- Session · (live) · Length · Level · XP · Gold · Kills · Deaths · Dungeons · Items: the numbers right-aligned at
  -- the right, the session's date takes the free width
  local tbl = UI.Table(content, {
    { key = "date", label = "Session", flex = 1, min = 110 },
    { key = "live", label = "", kind = "tag", color = "green", measure = { "•" } },
    { key = "len", label = "Length", kind = "num", color = "dim", measure = { "23h 59m" } },
    { key = "lvl", label = "Level", kind = "num", measure = { "59 > 60" } },
    { key = "xp", label = "XP", kind = "num", measure = { "9,999,999" } },
    { key = "gold", label = "Gold", kind = "money", color = "gold", measure = { "+" .. fmtMoney(9999999) } },
    { key = "kills", label = "Kills", kind = "num", measure = { "9999" } },
    { key = "deaths", label = "Deaths", kind = "num", color = "dim", measure = { "999" } },
    { key = "dung", label = "Dungeons", kind = "num", measure = { "99" } },
    { key = "items", label = "Items", kind = "num", measure = { "9999" } },
  }, { top = -(4 + STRIP_H + 18 + UI.SP.M), bottom = BAND_H + UI.SP.M, emptyText = "Your first session starts when you log in.",
    onClick = function(_, sess) if sess and sess.id then sel.id = sess.id; if sessionsRebuild then sessionsRebuild() end end end })
  content.tbl = tbl
  -- the selected session's gold (#38): the running session until a row is clicked. One title line (net and pace) and
  -- four blocks of three lines: top sources, best earners, biggest sinks, flags. The button opens its journal.
  local SP = UI.SP
  local band = UI.Panel(content)
  band:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 0, 0); band:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0); band:SetHeight(BAND_H)
  band.open = UI.Button(band, "Open gold journal", 120, UI.ROW_H, function() if ns.Gold and sel.shown then ns.Gold.open(sel.shown, "journal") end end)
  band.open:SetPoint("TOPRIGHT", band, "TOPRIGHT", -SP.S, -SP.S)
  band.title = UI.CellFS(band, "GameFontNormalSmall", C.gold); band.title:SetJustifyH("LEFT")
  band.title:SetPoint("LEFT", band, "TOPLEFT", SP.M, -(SP.S + UI.ROW_H / 2)); band.title:SetPoint("RIGHT", band.open, "LEFT", -SP.M, 0)
  band.blocks = {}
  for i, label in ipairs({ "TOP SOURCES", "BEST EARNERS", "BIGGEST SINKS", "FLAGS" }) do
    local b = CreateFrame("Frame", nil, band); b:SetHeight(BAND_H - UI.ROW_H - 2 * SP.S - SP.XS)
    b.head = UI.CellFS(b, "GameFontNormalSmall", C.dim); b.head:SetJustifyH("LEFT"); b.head:SetText(label)
    b.head:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0); b.head:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, 0)
    b.lines = {}
    for j = 1, 3 do
      local fs = UI.CellFS(b, "GameFontHighlightSmall", C.ink); fs:SetJustifyH("LEFT")
      fs:SetPoint("TOPLEFT", b, "TOPLEFT", 0, -(j * 16)); fs:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, -(j * 16))
      b.lines[j] = fs
    end
    band.blocks[i] = b
  end
  local function placeBand(w)
    w = tonumber(w) or 0
    if w <= 1 then return end
    local bw = math.floor((w - 2 * SP.M - 3 * SP.L) / 4)
    for i, b in ipairs(band.blocks) do
      b:ClearAllPoints(); b:SetPoint("TOPLEFT", band, "TOPLEFT", SP.M + (i - 1) * (bw + SP.L), -(SP.S + UI.ROW_H + SP.XS)); b:SetWidth(bw)
    end
  end
  content:HookScript("OnSizeChanged", function(_, w) pcall(placeBand, w) end)
  pcall(placeBand, content:GetWidth())
  content.goldBand = band
  local function fillBand(rows)
    local sess
    for _, s in ipairs(rows) do if s.id == sel.id then sess = s end end
    sess = sess or rows[1]
    sel.shown = sess and sess.id or nil
    local sum = sess and ns.Gold and ns.Gold.summary(sess)
    if not sum then band:Hide(); return end
    band:Show()
    local title = ("GOLD  ·  %s  ·  %s  ·  net %s"):format(date("%b %d, %H:%M", sess.startedEpoch or 0),
      fmtTime(sum.elapsed), ns.Gold.signed(sum.net))
    if sum.perHour then title = title .. ("  ·  %s per hour"):format(ns.Gold.signed(sum.perHour)) end
    band.title:SetText(title)
    local L = { {}, {}, {}, {} }
    for i, r in ipairs(sum.topIn) do L[1][i] = { ("%s  %s"):format(r.label, fmtMoney(r.amount)) } end
    local function best(word, t) if t then L[2][#L[2] + 1] = { ("%s: %s  %s"):format(word, t.name, fmtMoney(t.amount)) } end end
    best("Quest", sum.bestQuest); best("Mob", sum.bestMob); best("Sold", sum.bestItem)
    for i, r in ipairs(sum.sinks) do L[3][i] = { ("%s  %s"):format(r.label, fmtMoney(r.amount)) } end
    if #sum.strangers > 0 then L[4][#L[4] + 1] = { "Strangers: " .. table.concat(sum.strangers, ", "), C.red } end
    if sum.unexplained > 0 then L[4][#L[4] + 1] = { "Unexplained: " .. fmtMoney(sum.unexplained), C.red } end
    if sum.above > 0 then L[4][#L[4] + 1] = { ("Above vendor price: %d sale%s"):format(sum.above, sum.above == 1 and "" or "s"), C.red } end
    if #L[4] < 3 and sum.away ~= 0 then L[4][#L[4] + 1] = { "Changed while away: " .. ns.Gold.signed(sum.away) } end
    if #L[4] < 3 and sum.dropped > 0 then L[4][#L[4] + 1] = { ("%d rows past the cap not kept"):format(sum.dropped) } end
    local EMPTY = { "No income", sum.journal and "None recorded" or "Recorded before addon 0.9.40", "Nothing spent", "Nothing flagged" }
    for i, b in ipairs(band.blocks) do
      for j, fs in ipairs(b.lines) do
        local l = L[i][j] or (j == 1 and #L[i] == 0 and { EMPTY[i], C.dim }) or nil
        fs:SetText(l and l[1] or "")
        local col = (l and l[2]) or C.ink
        fs:SetTextColor(col[1], col[2], col[3])
      end
    end
  end
  sessionsRebuild = function()
    local rows = sessionRows()
    renderStrip(xpStrip, stripValues(rows, "xp"), function(v) return commas(v) .. " XP" end, false)
    renderStrip(goldStrip, stripValues(rows, nil, true), function(v) return (v < 0 and "-" or "+") .. fmtMoney(math.abs(v)) end, true)
    local nowT = (GetServerTime and GetServerTime()) or time()
    pcall(fillBand, rows)
    tbl.setRows(rows, function(row, sess)
      local c = row.c
      local live = (sess.endedEpoch == nil)
      local endT = sess.endedEpoch or nowT
      c.date:SetText(date("%b %d, %H:%M", sess.startedEpoch or 0))
      if sess.id == sel.shown then c.date:SetTextColor(C.cyan[1], C.cyan[2], C.cyan[3]) end   -- the row the gold band shows
      c.live:SetText(live and "•" or "")
      c.len:SetText(fmtTime(math.max(0, endT - (sess.startedEpoch or endT))))
      local l0, l1 = tonumber(sess.level0) or tonumber(sess.level) or 0, tonumber(sess.level) or 0
      c.lvl:SetText(l1 > l0 and (l0 .. " > " .. l1) or tostring(l1))
      if l1 > l0 then c.lvl:SetTextColor(C.gold[1], C.gold[2], C.gold[3]) end
      c.xp:SetText(commas(sess.xp or 0))
      local net = (tonumber(sess.gained) or 0) - (tonumber(sess.spent) or 0)
      c.gold:SetText((net < 0 and "-" or "+") .. fmtMoney(math.abs(net)))
      if net < 0 then c.gold:SetTextColor(C.red[1], C.red[2], C.red[3]) end
      c.kills:SetText(tostring(sess.kills or 0))
      c.deaths:SetText(tostring(sess.deaths or 0))
      if (tonumber(sess.deaths) or 0) > 0 then c.deaths:SetTextColor(C.red[1], C.red[2], C.red[3]) end
      c.dung:SetText(tostring(sess.dungeons or 0))
      c.items:SetText(tostring(sess.items or 0))
    end)
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
ns._test.journeyRefresh = function() if view then refresh(view) end return view end
