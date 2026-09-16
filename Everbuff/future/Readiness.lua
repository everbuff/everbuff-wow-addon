-- DEFERRED — raid-lead tool. NOT loaded yet (removed from the .toc). Needs to be implemented/finished in a future release; see addon/Everbuff/future/.
-- Everbuff · Readiness.lua — pre-pull consumables / buffs preview for the party or raid.
--
-- Secret Values note: unit auras are only secret *during* an encounter. This screen is a pre-pull
-- readiness check (in town / at the door), where AuraUtil reads are allowed. Every read is pcall'd
-- so an unexpected secret context degrades to "unknown", never an error.

local ADDON, ns = ...
local UI = ns.UI
local C = UI.C

-- Buff detection is name-based (English heuristics). Spell-ID tables can tighten this later.
local function classifyAura(name, r)
  if not name then return end
  if name:find("Flask") or name:find("Phial") then r.flask = true end
  if name == "Well Fed" or name:find("Well Fed") then r.food = true end
  if name:find("Augment") then r.rune = true end
  if name:find("Intellect") or name:find("Stamina") or name:find("Fortitude")
     or name:find("Motivation") or name:find("Mark of") then r.classbuff = true end
end

local function scanUnit(unit)
  local r = { flask = false, food = false, rune = false, classbuff = false }
  if not UnitExists(unit) then return r end
  pcall(function()
    if AuraUtil and AuraUtil.ForEachAura then
      AuraUtil.ForEachAura(unit, "HELPFUL", nil, function(aura)
        if type(aura) == "table" then classifyAura(aura.name, r) end
      end, true)
    end
  end)
  return r
end

local panel, listChild, summaryFS
local rows = {}

local function cell(parent, x)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  fs:SetPoint("LEFT", x, 0); fs:SetWidth(70); fs:SetJustifyH("LEFT")
  return fs
end

local function mark(fs, on)
  if on then fs:SetText("|cff47c97e✓|r") else fs:SetText("|cffe5544b✗|r") end
end

local function getRow(i, parent)
  local row = rows[i]
  if not row then
    row = CreateFrame("Frame", nil, parent)
    row:SetSize(560, 20)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.name:SetPoint("LEFT", 6, 0); row.name:SetWidth(170); row.name:SetJustifyH("LEFT")
    row.flask = cell(row, 182)
    row.food  = cell(row, 262)
    row.rune  = cell(row, 342)
    row.ready = cell(row, 440)
    rows[i] = row
  end
  row:ClearAllPoints()
  row:SetPoint("TOPLEFT", 0, -(i - 1) * 22)
  row:Show()
  return row
end

local function refresh()
  if not listChild then return end
  for _, row in ipairs(rows) do row:Hide() end
  local members = UI.groupMembers()
  local missingFlask, missingFood = {}, {}
  for i, m in ipairs(members) do
    local scan = m.scan or scanUnit(m.unit) -- m.scan supplied by /rb debug fake group
    local row = getRow(i, listChild)
    row.name:SetText(m.name)
    row.name:SetTextColor(UI.ClassColor(m.classFile))
    mark(row.flask, scan.flask)
    mark(row.food, scan.food)
    mark(row.rune, scan.rune)
    local ready = scan.flask and scan.food
    row.ready:SetText(ready and "|cff47c97eREADY|r" or "|cffc9a63cnot ready|r")
    if not scan.flask then missingFlask[#missingFlask + 1] = m.name end
    if not scan.food then missingFood[#missingFood + 1] = m.name end
  end
  listChild:SetHeight(math.max(1, #members * 22))
  local total = #members
  local ready = total - math.max(#missingFlask, #missingFood)
  summaryFS:SetText(("%d in group · |cff47c97e%d ready|r · |cffe5544b%d missing flask|r · |cffe5544b%d missing food|r")
    :format(total, ready, #missingFlask, #missingFood))
  panel.missingFlask, panel.missingFood = missingFlask, missingFood
end

local function reportMissing()
  local ch = UI.groupChannel()
  local function line(label, list)
    if #list == 0 then return end
    local msg = "Everbuff — missing " .. label .. ": " .. table.concat(list, ", ")
    if ch then SendChatMessage(msg, ch) else ns.msg(msg) end
  end
  line("flask", panel.missingFlask or {})
  line("food", panel.missingFood or {})
  if (#(panel.missingFlask or {}) == 0) and (#(panel.missingFood or {}) == 0) then
    local msg = "Everbuff — everyone is flasked & fed. Pull!"
    if ch then SendChatMessage(msg, ch) else ns.msg(msg) end
  end
end

local function build(content)
  panel = content
  local title = UI.FS(content, "GameFontNormalLarge", C.gold)
  title:SetPoint("TOPLEFT", 4, -4); title:SetText("Raid readiness")

  summaryFS = UI.FS(content, "GameFontHighlightSmall", C.dim)
  summaryFS:SetPoint("TOPLEFT", 6, -30)

  local refreshBtn = UI.Button(content, "Refresh", 90, 22, refresh)
  refreshBtn:SetPoint("TOPRIGHT", -6, -2)
  local reportBtn = UI.Button(content, "Report missing", 120, 22, reportMissing)
  reportBtn:SetPoint("RIGHT", refreshBtn, "LEFT", -8, 0)

  -- column headers
  local head = UI.Panel(content, C.panel2[1], C.panel2[2], C.panel2[3])
  head:SetPoint("TOPLEFT", 4, -52); head:SetPoint("TOPRIGHT", -4, -52); head:SetHeight(20)
  local function hcol(text, x)
    local fs = head:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("LEFT", x, 0); fs:SetText(text); fs:SetTextColor(unpack(C.dim))
    return fs
  end
  hcol("Player", 8); hcol("Flask", 184); hcol("Food", 264); hcol("Rune", 344); hcol("Status", 442)

  local sf, child = UI.ScrollChild(content)
  sf:SetPoint("TOPLEFT", 4, -76); sf:SetPoint("BOTTOMRIGHT", -26, 6)
  child:SetWidth(560)
  listChild = child

  refresh()
end

UI.registerTab(4, "Readiness", build, refresh, "Raid lead")
UI.setRosterHook("Readiness", refresh)

-- test hooks (harness only; harmless in-game)
ns.TEST = ns.TEST or {}
ns.TEST.Readiness_classifyAura = classifyAura
ns.TEST.Readiness_scanUnit = scanUnit
