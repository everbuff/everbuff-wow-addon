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
  local log = (ns.DB and ns.DB.story.events) or {}
  local fightsAll = (ns.Fights and ns.Fights.list and ns.Fights.list()) or {}
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
UI.registerPane("Combat", 3, "Deaths", function(content)
  view = content
  local summary = UI.FS(content, "GameFontHighlightSmall", C.red); summary:SetPoint("TOPLEFT", 2, -6)

  local COL = { time = 0, lvl = 118, zone = 170, coords = 326, by = 416, down = 586 }
  local hdr = CreateFrame("Frame", nil, content); hdr:SetPoint("TOPLEFT", 2, -26); hdr:SetSize(660, 16)
  local function head(col, text)
    local fs = ns.UI.FS(hdr, "GameFontDisableSmall")
    fs:SetPoint("LEFT", col, 0); fs:SetText(text); fs:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
  end
  head(COL.time, "When"); head(COL.lvl, "Level"); head(COL.zone, "Location"); head(COL.coords, "Coords"); head(COL.by, "Slain by"); head(COL.down, "Downtime")

  local sf, child = UI.ScrollChild(content)
  sf:SetPoint("TOPLEFT", 0, -46); sf:SetPoint("BOTTOMRIGHT", -22, 2)
  child.rows = {}

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

    local y, idx = 0, 0
    for i = #list, 1, -1 do
      idx = idx + 1
      local d = list[i]
      local row = child.rows[idx]
      if not row then
        row = CreateFrame("Button", nil, child, "BackdropTemplate"); row:SetHeight(20); row:SetPoint("RIGHT", child, "RIGHT", 0, 0)
        row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" }); row:SetBackdropColor(0, 0, 0, 0)
        row:SetScript("OnEnter", function(s) s:SetBackdropColor(C.panel2[1], C.panel2[2], C.panel2[3], 0.6) end)
        row:SetScript("OnLeave", function(s) s:SetBackdropColor(0, 0, 0, 0) end)
        row:SetScript("OnClick", function(s) if s.fight and ns.OpenFightDetail then ns.OpenFightDetail(s.fight) end end)
        row.tm = ns.UI.FS(row, "GameFontDisableSmall"); row.tm:SetPoint("LEFT", COL.time, 0); row.tm:SetWidth(112)
        row.lv = ns.UI.FS(row, "GameFontHighlightSmall"); row.lv:SetPoint("LEFT", COL.lvl, 0); row.lv:SetWidth(46)
        row.zo = ns.UI.FS(row, "GameFontHighlightSmall"); row.zo:SetPoint("LEFT", COL.zone, 0); row.zo:SetWidth(150); row.zo:SetJustifyH("LEFT")
        row.co = ns.UI.FS(row, "GameFontDisableSmall"); row.co:SetPoint("LEFT", COL.coords, 0); row.co:SetWidth(84); row.co:SetJustifyH("LEFT")
        row.by = ns.UI.FS(row, "GameFontHighlightSmall"); row.by:SetPoint("LEFT", COL.by, 0); row.by:SetWidth(164); row.by:SetJustifyH("LEFT")
        row.dn = ns.UI.FS(row, "GameFontDisableSmall"); row.dn:SetPoint("LEFT", COL.down, 0); row.dn:SetWidth(70); row.dn:SetJustifyH("LEFT")
        child.rows[idx] = row
      end
      row.fight = d.fight; row:SetPoint("TOPLEFT", 0, -y); row:Show()
      row.tm:SetText(date("%m/%d %H:%M", d.t or 0)); row.tm:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
      row.lv:SetText(d.level and tostring(d.level) or "-"); row.lv:SetTextColor(C.ink[1], C.ink[2], C.ink[3])
      row.zo:SetText(d.zone or "-")
      row.co:SetText(UI.fmtCoords(d.x, d.y)); row.co:SetTextColor(C.dim[1], C.dim[2], C.dim[3]); row.zo:SetTextColor(C.ink[1], C.ink[2], C.ink[3])
      local by = d.killer or "unknown"
      row.by:SetText(by .. (d.fight and "   |cff8c9197>|r" or "")); row.by:SetTextColor(C.red[1], C.red[2], C.red[3])
      local dn = d.downtime
      local dnText = dn and (dn >= 60 and ("%dm %02ds"):format(math.floor(dn / 60), dn % 60) or (dn .. "s")) or ""
      if d.durLoss and d.durLoss > 0 then dnText = dnText .. ("  |cffe5484d-%d%% gear|r"):format(d.durLoss) end
      row.dn:SetText(dnText); row.dn:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
      y = y + 20
    end
    for j = idx + 1, #child.rows do child.rows[j]:Hide() end
    if idx == 0 then
      child.empty = child.empty or (function()
        local fs = ns.UI.FS(child, "GameFontDisableSmall")
        fs:SetPoint("TOPLEFT", 0, 0); fs:SetText("No deaths recorded. Stay alive out there."); return fs
      end)()
      child.empty:Show()
    elseif child.empty then child.empty:Hide() end
    child:SetSize(math.max(660, (sf:GetWidth() or 660) - 4), math.max(1, y))
  end

  listRebuild()
end, function()
  if listRebuild then listRebuild() end
  if not ticker then ticker = C_Timer.NewTicker(3, function() if view and view:IsShown() and listRebuild then listRebuild() end end) end
end)

-- ── test exports: headless luajit tests in tests/ read these; no effect in-game ──
ns._test = ns._test or {}
ns._test.collectDeaths = collectDeaths
