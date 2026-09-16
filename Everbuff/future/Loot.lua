-- DEFERRED — raid-lead tool. NOT loaded yet (removed from the .toc). Needs to be implemented/finished in a future release; see addon/Everbuff/future/.
-- Everbuff · Loot.lua — soft-reserve loot distribution (raid-lead tool).
--
-- ⏸ PHASE 2 (deferred, 2026-09-13): raid-org / soft-reserve loot is parked while the MVP focuses on
--   Leveling + Dungeons for the WoW Forever launch. This code is COMPLETE and working — keep it; it
--   becomes an opt-in module once the module registry lands. Do not delete. See docs/DESIGN_PILLARS.md §9.
--
-- The raid-lead flow (reserves are collected on the website, addons can't fetch — D-007):
--   1. Create the raid + share the link on everbuff.gg; raiders soft-reserve; you lock it.
--   2. Copy the import string from the locked raid page and paste it here → Import.
--   3. Set an item → the addon shows its soft-reserves and picks the distribution mode:
--        · no reserve  → open MS/OS roll (fallback)
--        · 1 reserver  → award directly
--        · 2+ reservers → SR roll (only reservers' /roll counts)
--   4. Award → announced to the group and logged to history.

local ADDON, ns = ...
local UI = ns.UI
local C = ns.UI.C

local ROLL_SECONDS = 30

local current = nil          -- { link, name, texture, itemId, reservers }
local rolls = {}             -- ordered { name, value, kind }
local rolled = {}            -- name -> true
local listening = false
local rollMode = nil         -- "open" | "sr"
local allowed = nil          -- lowercased name set for SR rolls
local selectedRoller = nil
local closeTimer

local rollRows, histRows = {}, {}
local itemBtn, itemFS, srFS, statusFS, rollChild, histChild, nameAssign, importSummaryFS, srRollBtn, awardSRBtn

local refreshRolls, refreshHistory, updateStatus

-- ── SR import (paste string from the locked raid page) ────────────────────────
local function importSR(text)
  local reserves, code, max = {}, nil, nil
  for line in text:gmatch("[^\r\n]+") do
    line = line:gsub("^%s+", ""):gsub("%s+$", "")
    if line:match("^RSR1") then
      code, max = line:match("^RSR1%s+(%S+)%s+(%d+)")
    elseif line ~= "" then
      local id, player, class = line:match("^(%d+)%s+(%S+)%s+(%S+)")
      if id then
        id = tonumber(id)
        player = player:gsub("_", " ")
        reserves[id] = reserves[id] or {}
        table.insert(reserves[id], { player = player, class = class })
      end
    end
  end
  return reserves, code, tonumber(max or "2")
end

local function reserveSummary()
  local r = ns.DB.loot.reserves or {}
  local items, names = 0, {}
  for _, list in pairs(r) do
    items = items + 1
    for _, e in ipairs(list) do names[e.player] = true end
  end
  local n = 0; for _ in pairs(names) do n = n + 1 end
  return items, n
end

local function reserversFor(itemId)
  if not itemId then return {} end
  return (ns.DB.loot.reserves or {})[itemId] or {}
end

-- ── item selection ────────────────────────────────────────────────────────────
local function setItem(link)
  if not link then return end
  local name, _, _, _, _, _, _, _, _, texture = GetItemInfo(link)
  local itemId = tonumber(link:match("|?Hitem:(%d+)")) or tonumber(link:match("item:(%d+)"))
  current = { link = link, name = name or link, texture = texture, itemId = itemId,
              reservers = reserversFor(itemId) }
  if itemFS then itemFS:SetText(link) end
  if itemBtn and itemBtn.icon then
    itemBtn.icon:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
  end
  updateStatus()
end

local function grabCursorItem()
  local kind, _, link = GetCursorInfo()
  if kind == "item" and link then setItem(link); ClearCursor() end
end

-- ── roll capture ──────────────────────────────────────────────────────────────
local ev = CreateFrame("Frame")
ev:RegisterEvent("CHAT_MSG_SYSTEM")
ev:SetScript("OnEvent", function(_, _, msg)
  if not listening then return end
  local who, val, low, high = msg:match("^(%S+) rolls (%d+) %((%d+)%-(%d+)%)$")
  if not who then return end
  if allowed and not allowed[who:lower()] then return end -- SR roll: only reservers count
  if rolled[who] then return end
  rolled[who] = true
  val = tonumber(val); high = tonumber(high)
  local kind = (rollMode == "sr") and "SR" or ((high and high <= 50) and "OS" or "MS")
  rolls[#rolls + 1] = { name = who, value = val, kind = kind }
  table.sort(rolls, function(a, b)
    if a.kind ~= b.kind then return (a.kind == "MS" or a.kind == "SR") end
    return a.value > b.value
  end)
  refreshRolls()
end)

local function startRoll(mode)
  if not current then ns.msg("set an item first (drag it onto the slot or paste a link)"); return end
  wipe(rolls); wipe(rolled); selectedRoller = nil
  rollMode = mode; allowed = nil
  local ch = UI.groupChannel()
  local msg
  if mode == "sr" then
    local rs = current.reservers or {}
    if #rs < 1 then ns.msg("no soft-reserves on this item"); return end
    allowed = {}
    local names = {}
    for _, r in ipairs(rs) do allowed[r.player:lower()] = true; names[#names + 1] = r.player end
    msg = ("Everbuff SR — %s : reservers roll now → %s  (%ds)"):format(current.link, table.concat(names, ", "), ROLL_SECONDS)
  else
    msg = ("Everbuff — roll on %s : MS = /roll, OS = /roll 50  (%ds)"):format(current.link, ROLL_SECONDS)
  end
  listening = true
  refreshRolls()
  if ch then SendChatMessage(msg, ch) else ns.msg(msg .. "  (solo: /roll to test)") end
  if closeTimer then closeTimer:Cancel() end
  closeTimer = C_Timer.NewTimer(ROLL_SECONDS, function()
    listening = false; updateStatus()
    local c2 = UI.groupChannel(); if c2 then SendChatMessage("Everbuff — rolls closed.", c2) end
  end)
  updateStatus()
end

local function award(nameOverride, kindOverride)
  local winner, roll, kind
  if nameOverride and nameOverride ~= "" then
    winner = nameOverride; kind = kindOverride
  elseif selectedRoller then
    winner = selectedRoller.name; roll = selectedRoller.value; kind = selectedRoller.kind
  else
    ns.msg("select a roller or type a name to award to"); return
  end
  if not current then return end
  listening = false
  if closeTimer then closeTimer:Cancel(); closeTimer = nil end

  local entry = {
    item = current.link, itemName = current.name, winner = winner,
    roll = roll, kind = kind, when = GetServerTime(), raid = ns.DB.loot.raidCode,
  }
  table.insert(ns.DB.loot.history, 1, entry)
  while #ns.DB.loot.history > 200 do table.remove(ns.DB.loot.history) end

  local ch = UI.groupChannel()
  local tail = roll and (" (" .. roll .. " " .. (kind or "") .. ")") or (kind and (" (" .. kind .. ")") or "")
  local msg = ("Everbuff — %s awarded to %s%s"):format(current.link, winner, tail)
  if ch then SendChatMessage(msg, ch) else ns.msg(msg) end

  current = nil; wipe(rolls); wipe(rolled); selectedRoller = nil
  if itemFS then itemFS:SetText("|cff5f6b7adrop an item here or paste a link|r") end
  if itemBtn and itemBtn.icon then itemBtn.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark") end
  refreshRolls(); refreshHistory(); updateStatus()
end

-- ── rendering ─────────────────────────────────────────────────────────────────
updateStatus = function()
  if not statusFS then return end
  -- SR line for the current item
  if current then
    local rs = current.reservers or {}
    if not current.itemId then
      srFS:SetText("|cff8a96a6(couldn't read item id — open roll or assign)|r")
    elseif #rs == 0 then
      srFS:SetText("|cff8a96a6no soft-reserve on this item|r — open roll or assign")
    elseif #rs == 1 then
      srFS:SetText(("★ soft-reserved by |cffc9a63c%s|r — award directly"):format(rs[1].player))
    else
      local names = {}
      for _, r in ipairs(rs) do names[#names + 1] = r.player end
      srFS:SetText(("★ soft-reserved by %d: |cffc9a63c%s|r — SR roll"):format(#rs, table.concat(names, ", ")))
    end
    if srRollBtn then srRollBtn:SetEnabled(#rs >= 2) end
    if awardSRBtn then awardSRBtn:SetEnabled(#rs == 1) end
  else
    srFS:SetText("")
    if srRollBtn then srRollBtn:SetEnabled(false) end
    if awardSRBtn then awardSRBtn:SetEnabled(false) end
  end
  if listening then statusFS:SetText(rollMode == "sr" and "|cff47c97e● SR roll open|r" or "|cff47c97e● open roll|r")
  elseif current then statusFS:SetText("|cffc9a63citem set|r")
  else statusFS:SetText("|cff8a96a6no item|r") end
end

refreshRolls = function()
  if not rollChild then return end
  for _, r in ipairs(rollRows) do r:Hide() end
  for i, roll in ipairs(rolls) do
    local row = rollRows[i]
    if not row then
      row = CreateFrame("Button", nil, rollChild, "BackdropTemplate")
      row:SetSize(300, 20); row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
      row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      row.name:SetPoint("LEFT", 6, 0); row.name:SetWidth(170); row.name:SetJustifyH("LEFT")
      row.val = row:CreateFontString(nil, "OVERLAY", "GameFontNormal"); row.val:SetPoint("LEFT", 190, 0)
      row.kind = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); row.kind:SetPoint("LEFT", 240, 0)
      rollRows[i] = row
    end
    row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, -(i - 1) * 22); row:Show()
    row.name:SetText(roll.name); row.val:SetText(tostring(roll.value)); row.kind:SetText(roll.kind)
    local sel = (selectedRoller == roll)
    row:SetBackdropColor(sel and C.panel2[1] or 0, sel and C.panel2[2] or 0, sel and C.panel2[3] or 0, sel and 1 or 0)
    local hot = (roll.kind ~= "OS")
    row.val:SetTextColor(hot and C.gold[1] or C.dim[1], hot and C.gold[2] or C.dim[2], hot and C.gold[3] or C.dim[3])
    row:SetScript("OnClick", function() selectedRoller = roll; refreshRolls() end)
  end
  rollChild:SetHeight(math.max(1, #rolls * 22))
end

refreshHistory = function()
  if not histChild then return end
  for _, r in ipairs(histRows) do r:Hide() end
  local h = ns.DB.loot.history
  for i = 1, math.min(#h, 60) do
    local e = h[i]
    local row = histRows[i]
    if not row then
      row = CreateFrame("Frame", nil, histChild); row:SetSize(320, 30)
      row.item = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      row.item:SetPoint("TOPLEFT", 4, -2); row.item:SetWidth(300); row.item:SetJustifyH("LEFT")
      row.who = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
      row.who:SetPoint("TOPLEFT", 4, -16); row.who:SetWidth(300); row.who:SetJustifyH("LEFT")
      histRows[i] = row
    end
    row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, -(i - 1) * 32); row:Show()
    row.item:SetText(e.item or e.itemName or "?")
    local tail = e.roll and (" · " .. e.roll .. " " .. (e.kind or "")) or (e.kind and (" · " .. e.kind) or " · assigned")
    row.who:SetText(("→ |cffc9a63c%s|r%s · %s"):format(e.winner or "?", tail, date("%b %d %H:%M", e.when or 0)))
  end
  histChild:SetHeight(math.max(1, math.min(#h, 60) * 32))
end

local function updateImportSummary()
  if not importSummaryFS then return end
  local items, players = reserveSummary()
  if items == 0 then
    importSummaryFS:SetText("|cff8a96a6no reserves imported|r")
  else
    importSummaryFS:SetText(("|cff47c97e✓ reserves loaded|r%s · %d items · %d raiders")
      :format(ns.DB.loot.raidCode and (" — raid " .. ns.DB.loot.raidCode) or "", items, players))
  end
end

local function build(content)
  local title = UI.FS(content, "GameFontNormalLarge", C.gold)
  title:SetPoint("TOPLEFT", 4, -4); title:SetText("Loot — soft-reserve")

  -- SR import row
  local hint = UI.FS(content, "GameFontHighlightSmall", C.dim)
  hint:SetPoint("TOPLEFT", 6, -28); hint:SetWidth(560); hint:SetJustifyH("LEFT")
  hint:SetText("Create the raid & collect reserves at |cff00afd7everbuff.gg/raid/new|r, lock it, then paste the import string:")

  local importEdit = UI.EditBox(content, 300, 22)
  importEdit:SetPoint("TOPLEFT", 6, -48)
  local iph = UI.FS(importEdit, "GameFontDisableSmall", C.dim)
  iph:SetPoint("LEFT", 6, 0); iph:SetText("paste import string (RSR1 …)")
  importEdit:SetScript("OnTextChanged", function(s) iph:SetShown(s:GetText() == "") end)
  local importBtn = UI.Button(content, "Import", 80, 22, function()
    local reserves, code, max = importSR(importEdit:GetText())
    ns.DB.loot.reserves = reserves
    ns.DB.loot.raidCode = code
    ns.DB.loot.maxPerPlayer = max
    importEdit:SetText("")
    if current then current.reservers = reserversFor(current.itemId) end
    updateImportSummary(); updateStatus()
    local items = reserveSummary()
    ns.msg(("imported %d reserved items%s"):format(items, code and (" for raid " .. code) or ""))
  end)
  importBtn:SetPoint("LEFT", importEdit, "RIGHT", 8, 0)
  importSummaryFS = UI.FS(content, "GameFontHighlightSmall")
  importSummaryFS:SetPoint("TOPLEFT", 6, -74)

  -- item slot
  itemBtn = CreateFrame("Button", nil, content, "BackdropTemplate")
  itemBtn:SetSize(40, 40); itemBtn:SetPoint("TOPLEFT", 6, -98)
  itemBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  itemBtn:SetBackdropColor(0.03, 0.04, 0.05, 1); itemBtn:SetBackdropBorderColor(unpack(C.line))
  itemBtn.icon = itemBtn:CreateTexture(nil, "ARTWORK")
  itemBtn.icon:SetPoint("TOPLEFT", 2, -2); itemBtn.icon:SetPoint("BOTTOMRIGHT", -2, 2)
  itemBtn.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
  itemBtn:SetScript("OnClick", grabCursorItem)
  itemBtn:SetScript("OnReceiveDrag", grabCursorItem)

  itemFS = UI.FS(content, "GameFontHighlight")
  itemFS:SetPoint("TOPLEFT", 54, -100); itemFS:SetWidth(300); itemFS:SetJustifyH("LEFT")
  itemFS:SetText("|cff5f6b7adrop an item here or paste a link|r")

  local linkEdit = UI.EditBox(content, 260, 20)
  linkEdit:SetPoint("TOPLEFT", 54, -122)
  linkEdit:SetScript("OnEnterPressed", function(s)
    local link = s:GetText():match("(|c%x+|Hitem:.-|h.-|h|r)") or s:GetText():match("(|Hitem:.-|h.-|h)")
    if link then setItem(link) end
    s:SetText(""); s:ClearFocus()
  end)

  srFS = UI.FS(content, "GameFontHighlightSmall")
  srFS:SetPoint("TOPLEFT", 6, -148)
  statusFS = UI.FS(content, "GameFontHighlightSmall", C.dim)
  statusFS:SetPoint("TOPLEFT", 6, -166)

  -- distribution buttons
  local srBtn = UI.Button(content, "SR Roll", 90, 22, function() startRoll("sr") end)
  srBtn:SetPoint("TOPLEFT", 6, -186); srRollBtn = srBtn
  local awSR = UI.Button(content, "Award reserver", 120, 22, function()
    local rs = current and current.reservers
    if rs and #rs == 1 then award(rs[1].player, "SR") end
  end)
  awSR:SetPoint("LEFT", srBtn, "RIGHT", 8, 0); awardSRBtn = awSR
  local openBtn = UI.Button(content, "Open Roll", 90, 22, function() startRoll("open") end)
  openBtn:SetPoint("LEFT", awSR, "RIGHT", 8, 0)

  -- rolls list
  local rollHdr = UI.FS(content, "GameFontNormalSmall", C.dim)
  rollHdr:SetPoint("TOPLEFT", 6, -214); rollHdr:SetText("ROLLS")
  local sf, child = UI.ScrollChild(content)
  sf:SetPoint("TOPLEFT", 4, -230); sf:SetPoint("BOTTOMLEFT", 4, 40); sf:SetWidth(330)
  child:SetWidth(310); rollChild = child

  -- award controls
  nameAssign = UI.EditBox(content, 150, 22)
  nameAssign:SetPoint("BOTTOMLEFT", 6, 8)
  local nph = UI.FS(nameAssign, "GameFontDisableSmall", C.dim)
  nph:SetPoint("LEFT", 6, 0); nph:SetText("assign to name…")
  nameAssign:SetScript("OnTextChanged", function(s) nph:SetShown(s:GetText() == "") end)
  local awardBtn = UI.Button(content, "Award", 90, 22, function() award(nameAssign:GetText()) end)
  awardBtn:SetPoint("LEFT", nameAssign, "RIGHT", 8, 0)

  -- history
  local histHdr = UI.FS(content, "GameFontNormalSmall", C.dim)
  histHdr:SetPoint("TOPLEFT", 360, -28); histHdr:SetText("AWARD HISTORY")
  local sf2, child2 = UI.ScrollChild(content)
  sf2:SetPoint("TOPLEFT", 360, -46); sf2:SetPoint("BOTTOMRIGHT", -26, 8)
  child2:SetWidth(330); histChild = child2

  updateImportSummary(); updateStatus(); refreshRolls(); refreshHistory()
end

UI.registerTab(3, "Loot", build, function() refreshRolls(); refreshHistory(); updateImportSummary(); updateStatus() end, "Raid lead")

-- test hooks (harness only; harmless in-game)
ns.TEST = ns.TEST or {}
ns.TEST.Loot_importSR = importSR
ns.TEST.Loot_reserversFor = reserversFor
