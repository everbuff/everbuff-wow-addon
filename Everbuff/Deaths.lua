-- Everbuff.GG · Deaths.lua - the death recap gallery.
--
-- A filtered view (docs/UX_PRAGMATIC.md 1.5): every death still in the stored events, matched to its pull while the
-- pull is stored, so a click opens the replay at the moment of death. The stored events are a window, not the
-- character's history (500 rows of every kind, pruned when the desktop app picks a session up), so the page says
-- where it starts and counts only its own rows. In a dungeon the game hides who killed the character: that cell is
-- blank, never a word like "unknown". The tab exists only while a stored death names its killer.

local ADDON, ns = ...
local UI = ns.UI
local C = ns.UI.C

local listRebuild, view

local function collectDeaths()
  local log = ns.mine(ns.DB and ns.DB.story.events)   -- the logged-in character's only (#23)
  local fightsAll = ns.mine(ns.Fights and ns.Fights.list and ns.Fights.list())
  local out = {}
  for _, e in ipairs(log) do
    if e.kind == "DEATH" then
      local t = e.t or 0
      local linked
      for _, f in ipairs(fightsAll) do
        if f.outcome == "death" then
          local s = f.startEpoch or 0
          if t >= s - 2 and t <= s + (f.duration or 0) + 6 then linked = f; break end
        end
      end
      out[#out + 1] = {
        t = t,
        level = (linked and linked.level) or tonumber((e.text or ""):match("[Ll]evel (%d+)")),
        zone = e.zone or (linked and linked.zone),
        x = e.x or (linked and linked.x), y = e.y or (linked and linked.y),
        killer = e.foe or (linked and linked.foes and linked.foes[1]),
        downtime = tonumber(e.downtime), durLoss = tonumber(e.durLoss),
        fight = linked,
      }
    end
  end
  return out
end

-- the oldest stored event of the character: where this page's history starts (nil with none)
local function since()
  local t0
  for _, e in ipairs(ns.mine(ns.DB and ns.DB.story.events)) do
    local t = tonumber(e.t)
    if t and (not t0 or t < t0) then t0 = t end
  end
  return t0
end
-- the deaths the character's stored session records count (their counters outlive the event rows)
local function sessionDeaths()
  local n = 0
  for _, s in pairs((ns.DB and ns.DB.sessions) or {}) do
    if type(s) == "table" and ns.isMySession(s) then n = n + (tonumber(s.deaths) or 0) end
  end
  return n
end
-- whether a stored death of the character names its killer (the tab's reason to exist)
local function anyKiller()
  for _, d in ipairs(collectDeaths()) do if d.killer then return true end end
  return false
end

local ticker
local function fmtDowntime(dn)
  if not dn then return "" end
  return dn >= 60 and ("%dm %02ds"):format(math.floor(dn / 60), dn % 60) or (dn .. "s")
end
UI.registerPane("Home", 5, "Deaths", function(content)
  view = content
  local summary = UI.SummaryLine(content, C.red, nil, true)
  view.summary = summary
  -- When · Level · Killed by · Place · Coords · (opens the pull) · Downtime. No gear column: the loss is the same 10%
  -- on every row.
  local holder = UI.Below(content, summary)
  local tbl = UI.Table(holder, {
    { key = "time", label = "When", kind = "tag", color = "dim", measure = { "12/31 23:59" } },
    { key = "lvl", label = "Level", kind = "num", measure = { "60" } },
    { key = "by", label = "Killed by", flex = 1, min = 90 },
    { key = "zone", label = "Place", flex = 1, min = 90 },
    { key = "coords", label = "Coords", kind = "tag", justify = "RIGHT", color = "dim", measure = { "100.0, 100.0" } },
    { key = "open", label = "", kind = "tag", color = "dim", measure = { ">" } },
    { key = "down", label = "Downtime", kind = "num", color = "dim", measure = { "59m 59s" } },
  }, { top = 0,
    onClick = function(row) if row.fight and ns.OpenFightDetail then ns.OpenFightDetail(row.fight) end end })
  view.tbl = tbl
  -- no death at all: the kit's big empty state (2.7), its top at CONTENT_TOP + 48 as on Dungeons > Runs (4.4)
  view.empty = UI.Empty(content, { icon = "Interface\\Icons\\Ability_Rogue_FeignDeath", title = "You have not died.",
    text = "When you die, this page shows what killed you and the pull to replay." })
  view.empty:Hide()

  listRebuild = function()
    local list = collectDeaths()
    -- the line over the list: where the stored history starts, and the place most deaths happened in once that says
    -- something (at least 3 deaths in at least 2 places)
    local byZone, places = {}, 0
    for _, d in ipairs(list) do
      if d.zone then
        if not byZone[d.zone] then places = places + 1 end
        byZone[d.zone] = (byZone[d.zone] or 0) + 1
      end
    end
    local tz, tzc = nil, 0
    for k, c in pairs(byZone) do if c > tzc or (c == tzc and tz and k < tz) then tz, tzc = k, c end end
    if #list == 0 then summary:SetText("")
    else
      local t0 = since()
      local bits = { t0 and ("Deaths since " .. UI.fmtStamp(t0)) or "Deaths" }
      if #list >= 3 and places >= 2 and tz then bits[#bits + 1] = ("most in %s (%d)"):format(tz, tzc) end
      summary:SetText(table.concat(bits, "   \194\183   "))
    end
    view.since = since()
    -- (with nothing listed, "You have not died." only when the stored sessions count no death either)
    view.sessionDeaths = sessionDeaths()
    if view.empty.title then view.empty.title:SetText(view.sessionDeaths == 0 and "You have not died." or "No death is stored with its details.") end
    local rows = {}
    for i = #list, 1, -1 do rows[#rows + 1] = list[i] end
    if #rows == 0 then summary:Hide(); holder:Hide(); view.empty:Show() else view.empty:Hide(); summary:Show(); holder:Show() end
    tbl.setRows(rows, function(row, d)
      row.fight = d.fight
      row.c.time:SetText(date("%m/%d %H:%M", d.t or 0))
      -- (a cell with nothing recorded is blank: never "-", never "unknown")
      row.c.lvl:SetText(d.level and tostring(d.level) or "")
      row.c.zone:SetText(d.zone or "")
      row.c.coords:SetText(UI.fmtCoords(d.x, d.y))
      row.c.by:SetText(d.killer or "")
      row.c.open:SetText(d.fight and ">" or "")
      row.c.down:SetText(fmtDowntime(d.downtime))
    end)
  end

  listRebuild()
end, function()
  if listRebuild then listRebuild() end
  if not ticker then ticker = C_Timer.NewTicker(3, function() if view and view:IsShown() and listRebuild then listRebuild() end end) end
end, "The deaths still stored: what killed you, and the pull to replay.",
  function() return anyKiller() end)

-- ── test exports: headless luajit tests in tests/ read these; no effect in-game ──
ns._test = ns._test or {}
ns._test.collectDeaths = collectDeaths
ns._test.deathsView = function() if listRebuild then listRebuild() end; return view end
