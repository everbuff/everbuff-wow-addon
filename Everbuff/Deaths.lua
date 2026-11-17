-- Everbuff.GG · Deaths.lua - the death recap gallery.
--
-- Deaths are the emotionally sticky, shareable moments of a forever-classic run (and the whole point of
-- hardcore). This is mostly a FILTERED VIEW: every death from the eventlog, matched to its fight when
-- there is one, so a click deep-links into the Fights detail that already renders the "slain by" recap
-- with the scrubber parked at the moment of death. Plus a cause-of-death summary.

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

local ticker
local function fmtDowntime(dn)
  if not dn then return "" end
  return dn >= 60 and ("%dm %02ds"):format(math.floor(dn / 60), dn % 60) or (dn .. "s")
end
UI.registerPane("Combat", 3, "Deaths", function(content)
  view = content
  local summary = UI.SummaryLine(content, C.red, nil, true)
  view.summary = summary
  -- When · Level · Location · Coords · Slain by · (opens the fight) · Downtime · Gear lost
  local tbl = UI.Table(UI.Below(content, summary), {
    { key = "time", label = "When", kind = "tag", color = "dim", measure = { "12/31 23:59" } },
    { key = "lvl", label = "Level", kind = "num", measure = { "60" } },
    { key = "zone", label = "Location", flex = 1, min = 90 },
    { key = "coords", label = "Coords", kind = "tag", justify = "RIGHT", color = "dim", measure = { "100.0, 100.0" } },
    { key = "by", label = "Slain by", flex = 1, min = 90, color = "red" },
    { key = "open", label = "", kind = "tag", color = "dim", measure = { ">" } },
    { key = "down", label = "Downtime", kind = "num", color = "dim", measure = { "59m 59s" } },
    { key = "gear", label = "", kind = "tag", color = "red", measure = { "-100% gear" } },
  }, { top = 0, emptyText = "No deaths recorded. Stay alive out there.",
    onClick = function(row) if row.fight and ns.OpenFightDetail then ns.OpenFightDetail(row.fight) end end })
  view.tbl = tbl

  listRebuild = function()
    local list = collectDeaths()
    -- cause-of-death aggregation for the summary line
    local byKiller, byZone = {}, {}
    for _, d in ipairs(list) do
      if d.killer then byKiller[d.killer] = (byKiller[d.killer] or 0) + 1 end
      if d.zone then byZone[d.zone] = (byZone[d.zone] or 0) + 1 end
    end
    local function top(t) local bn, bc = nil, 0; for k, c in pairs(t) do if c > bc then bn, bc = k, c end end return bn, bc end
    local tk, tkc = top(byKiller); local tz, tzc = top(byZone)
    if #list == 0 then summary:SetText("")
    else
      local bits = { ("%d death%s"):format(#list, #list == 1 and "" or "s") }
      if tk then bits[#bits + 1] = ("most often: %s (%d)"):format(tk, tkc) end
      if tz then bits[#bits + 1] = ("deadliest zone: %s (%d)"):format(tz, tzc) end
      summary:SetText(table.concat(bits, "   ·   "))
    end
    local rows = {}
    for i = #list, 1, -1 do rows[#rows + 1] = list[i] end
    tbl.setRows(rows, function(row, d)
      row.fight = d.fight
      row.c.time:SetText(date("%m/%d %H:%M", d.t or 0))
      row.c.lvl:SetText(d.level and tostring(d.level) or "-")
      row.c.zone:SetText(d.zone or "-")
      row.c.coords:SetText(UI.fmtCoords(d.x, d.y))
      row.c.by:SetText(d.killer or "unknown")
      row.c.open:SetText(d.fight and ">" or "")
      row.c.down:SetText(fmtDowntime(d.downtime))
      row.c.gear:SetText((d.durLoss and d.durLoss > 0) and ("-%d%% gear"):format(d.durLoss) or "")
    end)
  end

  listRebuild()
end, function()
  if listRebuild then listRebuild() end
  if not ticker then ticker = C_Timer.NewTicker(3, function() if view and view:IsShown() and listRebuild then listRebuild() end end) end
end)

-- ── test exports: headless luajit tests in tests/ read these; no effect in-game ──
ns._test = ns._test or {}
ns._test.collectDeaths = collectDeaths
