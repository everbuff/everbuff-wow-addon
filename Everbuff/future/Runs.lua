-- DEFERRED — raid-lead tool. NOT loaded yet (removed from the .toc). Needs to be implemented/finished in a future release; see addon/Everbuff/future/.
-- Everbuff · Runs.lua — plan party/raid runs and keep the crew ("Crew" tab).
--
-- ⏸ PHASE 2 (deferred, 2026-09-13): raid-org feature, parked behind the Leveling+Dungeons MVP.
--   Complete & working — keep it; becomes an opt-in module later. See docs/DESIGN_PILLARS.md §9.
--
-- A "run" is a saved roster + context (instance, difficulty, when). You snapshot your current group
-- into a run, or build one over time, then re-invite the whole crew with one click next week.

local ADDON, ns = ...
local UI = ns.UI
local C = ns.UI.C

local selectedId
local runRows, rosterRows = {}, {}
local nameEdit, runListChild, rosterChild, detailTitle, detailMeta

local function newId()
  return date("%y%m%d%H%M%S") .. "-" .. string.format("%03d", math.random(0, 999))
end

local function runsSorted()
  local out = {}
  for _, r in pairs(ns.DB.runs) do out[#out + 1] = r end
  table.sort(out, function(a, b) return (a.created or 0) > (b.created or 0) end)
  return out
end

local function snapshotRoster()
  local out = {}
  for _, m in ipairs(UI.groupMembers()) do
    out[#out + 1] = { name = m.name, realm = m.realm, class = m.class,
                      classFile = m.classFile, role = m.role }
  end
  return out
end

local refreshRuns, refreshDetail

local function createRun()
  local name = nameEdit:GetText()
  if not name or name == "" then name = "Run " .. date("%b %d %H:%M") end
  local instName = GetInstanceInfo() or ""
  local _, _, _, diffName = GetInstanceInfo()
  local run = {
    id = newId(), name = name, instance = instName, difficulty = diffName or "",
    created = GetServerTime(), roster = snapshotRoster(), notes = "",
  }
  ns.DB.runs[run.id] = run
  selectedId = run.id
  nameEdit:SetText("")
  refreshRuns(); refreshDetail()
  ns.msg(("run |cffffffff%s|r saved with %d crew"):format(run.name, #run.roster))
end

local function recrewSelected()
  local run = selectedId and ns.DB.runs[selectedId]
  if not run then return end
  run.roster = snapshotRoster()
  refreshDetail()
  ns.msg(("crew updated — %d members"):format(#run.roster))
end

local function deleteSelected()
  if not selectedId then return end
  ns.DB.runs[selectedId] = nil
  selectedId = nil
  refreshRuns(); refreshDetail()
end

local function inviteCrew()
  local run = selectedId and ns.DB.runs[selectedId]
  if not run then return end
  local me = UnitNameUnmodified("player")
  local n = 0
  for _, member in ipairs(run.roster) do
    if member.name ~= me then
      local full = member.realm and (member.name .. "-" .. member.realm) or member.name
      pcall(function()
        if C_PartyInfo and C_PartyInfo.InviteUnit then C_PartyInfo.InviteUnit(full)
        else InviteUnit(full) end
      end)
      n = n + 1
    end
  end
  ns.msg(("invited %d crew for |cffffffff%s|r"):format(n, run.name))
end

-- ── list rendering ────────────────────────────────────────────────────────────
local function runButton(i, parent)
  local b = runRows[i]
  if not b then
    b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(232, 34)
    b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8",
      edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    b.title = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.title:SetPoint("TOPLEFT", 8, -5); b.title:SetJustifyH("LEFT"); b.title:SetWidth(216)
    b.sub = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    b.sub:SetPoint("TOPLEFT", 8, -19); b.sub:SetJustifyH("LEFT"); b.sub:SetWidth(216)
    runRows[i] = b
  end
  b:ClearAllPoints(); b:SetPoint("TOPLEFT", 0, -(i - 1) * 38); b:Show()
  return b
end

refreshRuns = function()
  if not runListChild then return end
  for _, b in ipairs(runRows) do b:Hide() end
  local list = runsSorted()
  for i, run in ipairs(list) do
    local b = runButton(i, runListChild)
    b.title:SetText(run.name)
    b.sub:SetText(("%s · %d crew · %s"):format(run.instance ~= "" and run.instance or "no instance",
      #(run.roster or {}), date("%b %d", run.created or 0)))
    local active = (run.id == selectedId)
    b:SetBackdropColor(active and C.panel2[1] or C.panel[1], active and C.panel2[2] or C.panel[2], active and C.panel2[3] or C.panel[3], 1)
    b:SetBackdropBorderColor(active and C.gold[1] or C.line[1], active and C.gold[2] or C.line[2], active and C.gold[3] or C.line[3], 1)
    b.title:SetTextColor(active and C.gold[1] or C.ink[1], active and C.gold[2] or C.ink[2], active and C.gold[3] or C.ink[3])
    b:SetScript("OnClick", function() selectedId = run.id; refreshRuns(); refreshDetail() end)
  end
  runListChild:SetHeight(math.max(1, #list * 38))
end

refreshDetail = function()
  if not detailTitle then return end
  for _, r in ipairs(rosterRows) do r:Hide() end
  local run = selectedId and ns.DB.runs[selectedId]
  if not run then
    detailTitle:SetText("|cff8a96a6select or create a run|r")
    detailMeta:SetText("")
    return
  end
  detailTitle:SetText(run.name)
  detailMeta:SetText(("%s%s · saved %s · %d crew"):format(
    run.instance ~= "" and run.instance or "no instance",
    run.difficulty ~= "" and (" (" .. run.difficulty .. ")") or "",
    date("%b %d %H:%M", run.created or 0), #(run.roster or {})))
  for i, m in ipairs(run.roster or {}) do
    local row = rosterRows[i]
    if not row then
      row = CreateFrame("Frame", nil, rosterChild)
      row:SetSize(320, 18)
      row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      row.name:SetPoint("LEFT", 4, 0); row.name:SetWidth(180); row.name:SetJustifyH("LEFT")
      row.role = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
      row.role:SetPoint("LEFT", 200, 0)
      rosterRows[i] = row
    end
    row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, -(i - 1) * 20); row:Show()
    row.name:SetText(m.name .. (m.realm and (" |cff5f6b7a-" .. m.realm .. "|r") or ""))
    row.name:SetTextColor(UI.ClassColor(m.classFile))
    row.role:SetText(m.role and m.role ~= "NONE" and m.role or "")
  end
  rosterChild:SetHeight(math.max(1, #(run.roster or {}) * 20))
end

local function build(content)
  local title = UI.FS(content, "GameFontNormalLarge", C.gold)
  title:SetPoint("TOPLEFT", 4, -4); title:SetText("Runs & crew")

  -- new-run row
  nameEdit = UI.EditBox(content, 200, 22)
  nameEdit:SetPoint("TOPLEFT", 6, -30)
  local ph = UI.FS(nameEdit, "GameFontDisableSmall", C.dim)
  ph:SetPoint("LEFT", 6, 0); ph:SetText("run name…")
  nameEdit:SetScript("OnTextChanged", function(s) ph:SetShown(s:GetText() == "") end)
  local createBtn = UI.Button(content, "Create from group", 140, 22, createRun)
  createBtn:SetPoint("LEFT", nameEdit, "RIGHT", 8, 0)

  -- left: runs list
  local leftHdr = UI.FS(content, "GameFontNormalSmall", C.dim)
  leftHdr:SetPoint("TOPLEFT", 6, -60); leftHdr:SetText("SAVED RUNS")
  local sf, child = UI.ScrollChild(content)
  sf:SetPoint("TOPLEFT", 4, -78); sf:SetPoint("BOTTOMLEFT", 4, 6); sf:SetWidth(250)
  child:SetWidth(232); runListChild = child

  -- right: detail
  detailTitle = UI.FS(content, "GameFontNormalLarge", C.gold)
  detailTitle:SetPoint("TOPLEFT", 280, -60)
  detailMeta = UI.FS(content, "GameFontHighlightSmall", C.dim)
  detailMeta:SetPoint("TOPLEFT", 282, -84)

  local sf2, child2 = UI.ScrollChild(content)
  sf2:SetPoint("TOPLEFT", 280, -104); sf2:SetPoint("BOTTOMRIGHT", -26, 40)
  child2:SetWidth(330); rosterChild = child2

  local inviteBtn = UI.Button(content, "Invite crew", 110, 22, inviteCrew)
  inviteBtn:SetPoint("BOTTOMLEFT", 282, 8)
  local recrewBtn = UI.Button(content, "Update crew", 110, 22, recrewSelected)
  recrewBtn:SetPoint("LEFT", inviteBtn, "RIGHT", 8, 0)
  local delBtn = UI.Button(content, "Delete", 90, 22, deleteSelected)
  delBtn:SetPoint("LEFT", recrewBtn, "RIGHT", 8, 0)

  refreshRuns(); refreshDetail()
end

UI.registerTab(2, "Crew", build, function() refreshRuns(); refreshDetail() end, "Raid lead")
UI.setRosterHook("Crew", function() end)
