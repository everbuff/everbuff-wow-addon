-- Everbuff.GG · Sync.lua - Settings (docs/UX_OVERHAUL.md 4.12): General, Gold display and Data and sync.
--
-- Built into the Settings tab by Emitter via ns.BuildSettings. One settings column, min(content width, 600) wide at
-- BOX_L (two columns of 500 at WIDE); each setting is a row (UI.SettingRow) with its control at the column's right
-- text edge. General: the recording flag, the window, the on-screen notifications. Gold display: Economy.lua
-- (ns.BuildGoldSettings). Data and sync: what the desktop app picked up, whether the addon is recording, what is
-- stored (each with a two-step clear), and Advanced. Everything shown is what the ADDON can know: video lives in the
-- desktop app, which the game cannot see, so it is stated as such and never claimed.

local ADDON, ns = ...
local UI = ns.UI
local C = ns.UI.C
local S, G, H = UI.S, UI.G, UI.H

-- the one read of the desktop sync state (docs/UX_OVERHAUL.md 5 step 3a): the last ack (when, and how many pulls it
-- took), the pulls stored and the ones the desktop app has not saved yet. The title-bar chip, Home and Data and sync
-- all read it, on show. The addon removes a pull once the desktop app has saved it, so `stored` is only ever the
-- stretch since the last pickup: `ackAt` and `ackFights` are what is known of the pulls before it.
function ns.SyncState()
  local combat = ns.DB and ns.DB.combat
  local waiting, stored = 0, 0
  for _, f in ipairs((combat and combat.fights) or {}) do stored = stored + 1; if f.uploaded ~= true then waiting = waiting + 1 end end
  local la = combat and type(combat.lastAck) == "table" and combat.lastAck or nil
  return { lastAck = la, waiting = waiting, stored = stored, ackAt = la and tonumber(la.at) or nil, ackFights = la and tonumber(la.fights) or nil }
end

local SET = {}          -- the Settings panes and their state (ns.SettingsView for the tests)
ns.SettingsView = SET
local function cfg() return (ns.DB and ns.DB.settings) or {} end
local function nowT() return (GetServerTime and GetServerTime()) or time() end

-- the settings column(s) span the main column, BOX_L to BOX_L + MAIN_W, as every other page (A2): one column under
-- WIDE, two halves S5 apart at WIDE, so a control's right edge is the main column's text edge (BOX_L + MAIN_W - S3).
-- Descriptions stay capped at 520 inside their row. sections = { { head, items } } where an item is a frame with its
-- height (ebH, else its own), placed one under the other. Data and sync takes two columns at WIDE too (B23): its
-- status lines wrap inside their half.
function UI.settingsColumns()
  local mw = G.mainW(G.winW())
  if G.isWide(G.winW()) then
    local half = math.floor((mw - S.S5) / 2)
    return { { x = 0, w = half }, { x = mw - half, w = half } }
  end
  return { { x = 0, w = mw } }
end
local function columnsOf() return UI.settingsColumns() end
local function hOf(f) return f.ebH or tonumber(f:GetHeight()) or 0 end
local function sectionH(sec)
  local h = H.SECTION
  for _, it in ipairs(sec.items) do if it:IsShown() then h = h + hOf(it) end end
  return h
end
-- lay `sections` (and a footer) out on the page; at WIDE the second column takes the sections after the split
function SET.place(pg, sections, footer)
  local cols = columnsOf()
  -- every row laid out at its column's width first, so a row that grows (a stacked control, a wrapped status) is
  -- placed at its own height
  for _, sec in ipairs(sections) do
    for _, it in ipairs(sec.items) do if it.layout then it:SetWidth(cols[#cols].w); pcall(it.layout) end end
  end
  local list = {}
  local split = #sections + 1
  if #cols == 2 and #sections > 1 then
    -- the split that makes the taller column the shortest (sections stay whole and in order)
    local hs, total = {}, 0
    for i, sec in ipairs(sections) do hs[i] = sectionH(sec) + S.S5; total = total + hs[i] end
    local best, run = math.huge, 0
    for k = 1, #sections - 1 do
      run = run + hs[k]
      local tall = math.max(run, total - run)
      if tall < best then best, split = tall, k + 1 end
    end
  end
  local ys = { 0, 0 }
  for i, sec in ipairs(sections) do
    local ci = (i >= split and #cols == 2) and 2 or 1
    local c = cols[ci]
    local y = ys[ci]
    list[#list + 1] = { sec.head, H.SECTION, x = c.x, w = c.w, y = y }
    y = y + H.SECTION
    for _, it in ipairs(sec.items) do
      if it:IsShown() then list[#list + 1] = { it, hOf(it), x = c.x, w = c.w, y = y }; y = y + hOf(it) end
    end
    ys[ci] = y + S.S5
  end
  if footer then list[#list + 1] = { footer, H.SECTION, x = 0, w = cols[1].w, y = math.max(ys[1], ys[2]) } end
  pg.place(list, (#cols == 2) and (cols[2].x + cols[2].w) or cols[1].w)
  for _, sec in ipairs(sections) do for _, it in ipairs(sec.items) do if it.layout then pcall(it.layout) end end end
end
-- a META note under a section header (wraps at min(w - 24, 520), the Table inline-text rule); its height follows
-- its lines
local function note(col, text, color)
  local f = CreateFrame("Frame", nil, col)
  f.text = UI.Text(f, "META", color or "fgMuted", { wrap = true }); f.text:SetPoint("TOPLEFT", f, "TOPLEFT", S.S3, -S.S1)
  function f.layout()
    local w = math.max(1, math.min(520, (tonumber(f:GetWidth()) or 0) - 2 * S.S3))
    f.text:SetWidth(w)
    local lines = math.max(1, math.ceil(UI.TextWidth("META", f.text:GetText()) / w))
    f.ebH = lines * UI.LINE_H.META + S.S3
    f:SetHeight(f.ebH)
  end
  function f.Set(_, t, col2) f.text:SetText(t or ""); if col2 then f.text:SetTextColor(C[col2][1], C[col2][2], C[col2][3]) end; pcall(f.layout) end
  f:Set(text)
  return f
end
SET.note = note
-- a row whose text starts with a 6 px state dot ("Combat log: on"), an optional button at the right
-- (a long status wraps: the row grows by its lines, the button stays on the first line)
local function dotRow(col)
  local r = UI.SettingRow(col, "")
  r.label:SetFontObject(UI.F.BODY)
  r.label:SetWordWrap(true)
  r.label:ClearAllPoints(); r.label:SetPoint("TOPLEFT", r, "TOPLEFT", S.S3, -((H.SETTING - UI.LINE_H.BODY) / 2))
  function r.layout()
    local w = tonumber(r:GetWidth()) or 0
    local cw = (r.btn and r.btn:IsShown()) and ((tonumber(r.btn:GetWidth()) or 0) + S.S2) or 0
    local room = math.max(1, w - 2 * S.S3 - cw)
    local tw = UI.TextWidth("BODY", r.label:GetText())
    r.label:SetWidth(math.min(room, tw + 1))
    local lines = math.max(1, math.ceil(tw / room))
    r.ebH = math.max(H.SETTING, lines * UI.LINE_H.BODY + (H.SETTING - UI.LINE_H.BODY))
    r:SetHeight(r.ebH)
  end
  function r.SetState(_, text, color, button)
    r.plain = text
    r.label:SetText(UI.dot(color or "accent") .. text)
    r.label:SetTextColor(C.fg[1], C.fg[2], C.fg[3])
    if r.btn then if button then r.btn:Show() else r.btn:Hide() end end
    pcall(r.layout)
  end
  return r
end
-- a danger ghost that asks first: the first click arms it ("Click again to clear 78 pulls") for 4 s
local function twoStep(parent, label, armed, fn)
  local b
  b = UI.KitButton(parent, label, "danger", function(s)
    if not s.armed then
      s.armed = true; s:SetLabel(armed())
      if C_Timer and C_Timer.After then C_Timer.After(4, function() if s.armed then s.armed = false; s:SetLabel(label); if s.ebRow then pcall(s.ebRow.SetControl, s.ebRow, s) end end end) end
    else
      s.armed = false; s:SetLabel(label)
      fn()
    end
    if s.ebRow then pcall(s.ebRow.SetControl, s.ebRow, s) end
  end)
  return b
end
SET.twoStep = twoStep

-- ═══ General ═══════════════════════════════════════════════════════════════════════════════════════════════════
local CORNERS = { { "TOPLEFT", "Top left" }, { "TOPRIGHT", "Top right" }, { "BOTTOMLEFT", "Bottom left" }, { "BOTTOMRIGHT", "Bottom right" } }
local LOOT_FROM = { { "uncommon", "Green and better" }, { "rare", "Blue and better" }, { "epic", "Purple and better" } }
local GROUPS = {
  { "travel", "Travel", "Zones, dungeons, discoveries and flight paths." },
  { "quests", "Quests", "Accepted, completed and the reward you chose." },
  { "kills", "Kills", "Elites, rares and boss pulls." },
  { "progress", "Progress", "Skill-ups, spells, reputation, achievements and collections." },
}
local PREVIEW = { { "LEVELUP", {} }, { "LOOT", { name = "Cursed Felblade", count = 1 } }, { "BOSS", { name = "Edwin VanCleef" } }, { "DEATH", {} }, { "DISCOVERY", { name = "Westfall" } } }
local function muted(k) local m = cfg().flagMute; return type(m) == "table" and m[k] end
local function setMuted(k, on)
  local st = ns.DB and ns.DB.settings; if not st then return end
  st.flagMute = st.flagMute or {}
  st.flagMute[k] = on and true or nil
end
local function buildGeneral(pane)
  local g = { pane = pane }
  SET.general = g
  g.pg = UI.Page(pane)
  local col = g.pg.col
  local E = ns.Emitter or {}
  -- RECORDING FLAG
  local flag = { head = UI.Section(col, "Capture flag"), items = {} }
  flag.items[1] = note(col, "The small square the desktop app reads to line up your video. It is always shown.")
  g.corner = UI.SettingRow(col, "Position")
  g.cornerSeg = UI.Segmented(g.corner, (function() local t = {}; for _, c in ipairs(CORNERS) do t[#t + 1] = { c[1], c[2] } end return t end)(),
    { segW = 100, onPick = function(k) if E.setCorner then E.setCorner(k) end; SET.refreshGeneral() end })
  g.corner:SetControl(g.cornerSeg)
  flag.items[2] = g.corner
  g.flagSize = UI.SettingRow(col, "Size")
  local fr = E.FLAG_RANGE or { 1.0, 1.5 }
  g.flagSlider = UI.Slider(g.flagSize, { min = fr[1], max = fr[2], step = 0.05, value = tonumber(cfg().flagScale) or 1,
    fmt = function(v) return math.floor(v * 100 + 0.5) .. "%" end, onChange = function(v) if E.setFlagScale then E.setFlagScale(v) end end })
  g.flagSize:SetControl(g.flagSlider)
  flag.items[3] = g.flagSize
  -- WINDOW
  local win = { head = UI.Section(col, "Window"), items = {} }
  g.scale = UI.SettingRow(col, "Window scale")
  g.scaleSlider = UI.Slider(g.scale, { min = UI.SCALE_MIN, max = 1.3, step = 0.05, value = math.max(UI.SCALE_MIN, tonumber(cfg().winScale) or 1),
    fmt = function(v) return math.floor(v * 100 + 0.5) .. "%" end,
    onChange = function(v) if ns.DB and ns.DB.settings then ns.DB.settings.winScale = v end; if UI.SetWindowScale then UI.SetWindowScale(v) end end })
  g.scale:SetControl(g.scaleSlider)
  g.reset = UI.SettingRow(col, "Reset window size and position")
  g.resetBtn = UI.KitButton(g.reset, "Reset", "ghost", function() UI.ResetWindow() end)
  g.reset:SetControl(g.resetBtn)
  win.items = { g.scale, g.reset }
  -- ON-SCREEN NOTIFICATIONS
  local nt = { head = UI.Section(col, "On-screen notifications"), items = {} }
  g.previewI = 0
  g.preview = UI.KitButton(nt.head.right, "Preview", "ghost", function()
    g.previewI = (g.previewI % #PREVIEW) + 1
    local pv = PREVIEW[g.previewI]
    if E.event then E.event(pv[1], pv[2]) end   -- cycles level-up, loot, boss, death, discovery so every style is seen
  end)
  g.preview:SetPoint("TOPRIGHT", nt.head.right, "TOPRIGHT", -S.S3, 0)
  UI.SetTip(g.preview, { title = "Preview", text = "Shows a notification as it looks in game, a different kind each click." })
  nt.items[1] = note(col, "Level-ups, deaths and wipes always show. Everything else is recorded either way.")
  g.loot = UI.SettingRow(col, "Loot", "Drops of the quality below and better.")
  g.lootCb = UI.Checkbox(g.loot, { onChange = function(on)
    setMuted("loot", not on)
    if on and cfg().lootToast == "off" and ns.DB and ns.DB.settings then ns.DB.settings.lootToast = "rare" end
    SET.refreshGeneral()
  end })
  g.loot:SetControl(g.lootCb)
  g.lootFrom = UI.SettingRow(col, "Show loot from")
  -- (the menu's pick is the setting, not a filter: its default follows the setting so it never shows as active)
  g.lootFromOpts = { default = "rare", label = "Blue and better",
    items = function()
      local cur = cfg().lootToast or "rare"
      local out = {}
      for _, q in ipairs(LOOT_FROM) do out[#out + 1] = { q[1], q[2], q[1] == cur } end
      return out
    end,
    onPick = function(k) if ns.DB and ns.DB.settings then ns.DB.settings.lootToast = k end; SET.refreshGeneral() end }
  g.lootFromBtn = UI.FilterButton(g.lootFrom, g.lootFromOpts)
  g.lootFrom:SetControl(g.lootFromBtn)
  nt.items[2], nt.items[3] = g.loot, g.lootFrom
  g.groups = {}
  for _, gr in ipairs(GROUPS) do
    local r = UI.SettingRow(col, gr[2], gr[3])
    r.cb = UI.Checkbox(r, { onChange = function(on) setMuted(gr[1], not on) end })
    r.key = gr[1]
    r:SetControl(r.cb)
    g.groups[#g.groups + 1] = r
    nt.items[#nt.items + 1] = r
  end
  -- the welcome guide
  local wl = { head = UI.Section(col, "Welcome guide"), items = {} }
  g.welcome = UI.SettingRow(col, "Show the welcome guide again")
  g.welcomeBtn = UI.KitButton(g.welcome, "Show", "ghost", function()
    if ns.DB and ns.DB.settings then ns.DB.settings.welcomeDone = false end
    UI.Open("Home", "now")
  end)
  g.welcome:SetControl(g.welcomeBtn)
  wl.items[1] = g.welcome
  g.sections = { flag, win, nt, wl }
  pane:HookScript("OnSizeChanged", function() pcall(SET.place, g.pg, g.sections) end)
  SET.refreshGeneral()
end
function SET.refreshGeneral()
  local g = SET.general; if not g then return end
  local st = cfg()
  g.cornerSeg:SetValue(st.emitCorner or "TOPLEFT")
  g.flagSlider:SetValue(tonumber(st.flagScale) or 1, true)
  g.scaleSlider:SetValue(math.max(UI.SCALE_MIN, tonumber(st.winScale) or 1), true)
  local lootOn = not muted("loot") and st.lootToast ~= "off"
  g.lootCb:SetChecked(lootOn)
  local mode = (st.lootToast and st.lootToast ~= "off") and st.lootToast or "rare"
  local label = "Blue and better"
  for _, q in ipairs(LOOT_FROM) do if q[1] == mode then label = q[2] end end
  g.lootFromOpts.default = mode
  g.lootFromBtn:SetValue(mode, label)
  g.lootFrom:SetControl(g.lootFromBtn)
  if lootOn then g.lootFromBtn:SetAlpha(1) else g.lootFromBtn:SetAlpha(0.4) end
  for _, r in ipairs(g.groups) do r.cb:SetChecked(not muted(r.key)) end
  SET.place(g.pg, g.sections)
end

-- ═══ Data and sync ═════════════════════════════════════════════════════════════════════════════════════════════
-- (Clear on the pulls never resets combat.fightSeq: the pull ids stay monotonic, and it is the only count of the
-- pulls ever recorded. The story events have no row here: the backend reads them and a count of them says nothing.)
local STORED = {
  { "fights", "Pulls waiting", function(db) return #(db.combat.fights or {}) end, function(n) return UI.fmtNum(n) end,
    function() if ns.DB then ns.DB.combat.fights = {} end end, "pull", "Clear the pulls waiting" },
  -- (the gold ledger is not the loot list: clearing it would break looted + ... = gained, 0.9.44)
  { "loot", "Loot", function(db) return #(db.loot.log or {}) end, function(n) return UI.plural(n, "pickup") end,
    function() if ns.DB then ns.DB.loot.log = {} end end, "pickup", "Clear the loot list" },
}
local SAMPLES = { { 1, "Fine" }, { 3, "Normal" }, { 10, "Coarse" } }
local function buildData(pane)
  local d = { pane = pane }
  SET.data = d
  d.pg = UI.Page(pane)
  local col = d.pg.col
  -- The page is one answer, CAPTURE HEALTH (docs/UX_PRAGMATIC.md 5): is the addon capturing, did the desktop app
  -- pick the data up, what is still waiting, what is stored. The paste code (a fallback: the pickup is automatic)
  -- and the Clear buttons are under Advanced, collapsed.
  d.syncStatus = dotRow(col)
  d.syncStatus.text = d.syncStatus.label
  d.pasteRow = CreateFrame("Frame", nil, col); d.pasteRow.ebH = UI.H.CONTROL + S.S2; d.pasteRow:SetHeight(d.pasteRow.ebH)
  local box = CreateFrame("EditBox", nil, d.pasteRow, "BackdropTemplate")
  box:SetHeight(UI.H.CONTROL)
  box:SetBackdrop({ bgFile = UI.WHITE, edgeFile = UI.WHITE, edgeSize = 1 })
  UI.BoxColors(box, "sunken", "lineStrong")
  box:SetFontObject(UI.F.BODY); box:SetTextInsets(S.S2, S.S2, 0, 0); box:SetAutoFocus(false)
  box:SetPoint("TOPLEFT", d.pasteRow, "TOPLEFT", S.S3, 0)   -- (it stretches: Apply ends on the column's text edge)
  local ph = UI.Text(box, "BODY", "fgFaint"); ph:SetPoint("LEFT", box, "LEFT", S.S2, 0); ph:SetText("Paste the code from the desktop app")
  local function placeholder() local t = box:GetText(); if t == nil or t == "" then ph:Show() else ph:Hide() end end
  box:SetScript("OnTextChanged", placeholder)
  d.placeholderSync = placeholder   -- (refreshData runs it too: a SetText from code does not always fire OnTextChanged)
  box:SetScript("OnEditFocusGained", function(x) UI.BoxColors(x, "sunken", "accent") end)
  box:SetScript("OnEditFocusLost", function(x) UI.BoxColors(x, "sunken", "lineStrong") end)
  box:SetScript("OnEscapePressed", function(x) x:SetText(""); x:ClearFocus() end)
  d.ackBox, d.placeholder = box, ph
  d.ackBtn = UI.KitButton(d.pasteRow, "Apply", "ghost", function() SET.applyCode() end)
  d.ackBtn:SetPoint("TOPRIGHT", d.pasteRow, "TOPRIGHT", -S.S3, 0)
  box:SetPoint("RIGHT", d.ackBtn, "LEFT", -S.S2, 0)
  box:SetScript("OnEnterPressed", function(x) x:ClearFocus(); SET.applyCode() end)
  d.ackError = note(col, "", "bad"); d.ackError:Hide()   -- only after a paste attempt; gone when the page opens again
  pane:HookScript("OnShow", function() d.ackErrorOn = nil; d.ackError:Hide() end)
  d.syncDesc = note(col, "Only if the desktop app asks for it: the pickup is automatic.")
  -- CAPTURE HEALTH (the addon captures data; only the desktop app knows about video)
  local health = { head = UI.Section(col, "Capture health"), items = {} }
  d.rec = dotRow(col)
  d.combat = dotRow(col)
  d.combat.btn = UI.KitButton(d.combat, "Turn on", "ghost", function() SET.turnOn() end); d.combat:SetControl(d.combat.btn)
  d.acl = dotRow(col)
  d.acl.btn = UI.KitButton(d.acl, "Turn on", "ghost", function() SET.turnOn() end); d.acl:SetControl(d.acl.btn)
  d.remind = UI.SettingRow(col, "Remind me to /reload before I log out", "Saves your data even if the game disconnects you.")
  d.remindCb = UI.Checkbox(d.remind, { onChange = function(on) if ns.DB and ns.DB.settings then ns.DB.settings.autoSave = on and true or false end end })
  d.remind:SetControl(d.remindCb)
  -- the reload: a SECURE button running /reload (a click on it is a hardware event; a Lua-driven reload is blocked
  -- while the addon reads secret values). A protected frame is anchored once, to its row, and the rows are not moved
  -- in combat (SET.placeData holds the layout until combat ends), so nothing re-anchors it during lockdown.
  d.save = UI.SettingRow(col, "Save now", "Reloads the interface, which writes your data to disk. Nothing is lost.")
  local sv = CreateFrame("Button", "EverbuffSyncReloadBtn", d.save, "SecureActionButtonTemplate,BackdropTemplate")
  sv:SetSize(UI.TextWidth("BODY_STRONG", "Reload and save") + 2 * S.S3, UI.H.CONTROL)
  sv:SetAttribute("type", "macro"); sv:SetAttribute("macrotext", "/reload"); sv:RegisterForClicks("AnyUp", "AnyDown")
  sv:SetBackdrop({ bgFile = UI.WHITE, edgeFile = UI.WHITE, edgeSize = 1 })
  UI.BoxColors(sv, nil, "lineStrong")
  local svt = UI.Text(sv, "BODY_STRONG", "fgSubtle"); svt:SetPoint("CENTER", sv, "CENTER", 0, 0); svt:SetText("Reload and save")
  sv:HookScript("OnEnter", function(s) UI.BoxColors(s, nil, "lineControl"); svt:SetTextColor(C.fg[1], C.fg[2], C.fg[3]) end)
  sv:HookScript("OnLeave", function(s) UI.BoxColors(s, nil, "lineStrong"); svt:SetTextColor(C.fgSubtle[1], C.fgSubtle[2], C.fgSubtle[3]) end)
  d.save:SetControl(sv)
  d.saveBtn = sv
  -- what is stored: one status row each in CAPTURE HEALTH ("Pulls waiting · 0"), and its Clear on a row of its own
  -- under Advanced (d.clear), there only while the store holds something
  d.stored, d.clear = {}, {}
  local clearRows = {}
  for _, it in ipairs(STORED) do
    local r = dotRow(col)
    r.key = it[1]
    d.stored[it[1]] = r
    local cr = UI.SettingRow(col, it[7], "Cannot be undone.")
    local db = function() return ns.DB or { combat = {}, loot = {}, story = {} } end
    cr.btn = twoStep(cr, "Clear", function() return ("Click again to clear %s"):format(UI.plural(it[3](db()), it[6])) end, function() it[5](); SET.refreshData() end)
    cr.btn.ebRow = cr
    cr:SetControl(cr.btn)
    d.clear[it[1]] = cr
    r.clear = cr.btn
    clearRows[#clearRows + 1] = cr
  end
  health.items = { d.rec, d.syncStatus, d.stored.fights, d.stored.loot, d.combat, d.acl, d.remind, d.save }
  -- ADVANCED (collapsed by default)
  local adv = { head = UI.Section(col, "Advanced \226\128\186"), items = {} }
  d.advHit = CreateFrame("Button", nil, adv.head); d.advHit:SetAllPoints(adv.head)
  d.advHit:SetScript("OnClick", function()
    UI.Click()
    if ns.DB and ns.DB.settings then ns.DB.settings.advancedOpen = not ns.DB.settings.advancedOpen end
    SET.refreshData()
  end)
  UI.SetTip(d.advHit, { title = "Advanced", text = "Replay detail, the code from the desktop app, clearing stored data, and what the addon can read in this client." })
  d.sample = UI.SettingRow(col, "Replay detail", "Finer detail makes replays smoother and the save file larger. Applies from your next pull.")
  local segItems = {}
  for _, sm in ipairs(SAMPLES) do segItems[#segItems + 1] = { sm[1], sm[2], ("A stat snapshot every %s during a pull."):format(UI.fmtDur(sm[1])) } end
  d.sampleSeg = UI.Segmented(d.sample, segItems, { onPick = function(k) if ns.DB and ns.DB.settings then ns.DB.settings.statSample = k end end })
  d.sample:SetControl(d.sampleSeg)
  d.auras = dotRow(col)
  d.client = dotRow(col)
  d.ui = dotRow(col)
  d.video = dotRow(col)
  d.errors = UI.SettingRow(col, "Errors the addon caught", "Prints them in chat so you can copy them into a bug report.")
  d.errorsBtn = UI.KitButton(d.errors, "Copy errors", "ghost", function() if SlashCmdList and SlashCmdList.EVERBUFF then pcall(SlashCmdList.EVERBUFF, "errors") end end)
  d.errors:SetControl(d.errorsBtn)
  d.advItems = { d.sample, d.pasteRow, d.syncDesc, d.ackError }
  for _, cr in ipairs(clearRows) do d.advItems[#d.advItems + 1] = cr end
  for _, x in ipairs({ d.auras, d.client, d.ui, d.video, d.errors }) do d.advItems[#d.advItems + 1] = x end
  adv.items = d.advItems
  d.footer = CreateFrame("Frame", nil, col); d.footer:SetHeight(H.SECTION)
  d.footerText = UI.Text(d.footer, "META", "fgMuted"); d.footerText:SetPoint("TOPLEFT", d.footer, "TOPLEFT", S.S3, -S.S1)
  d.sections = { health, adv }
  d.advHead = adv.head
  pane:HookScript("OnSizeChanged", function() SET.placeData() end)
  SET.refreshData()
end
-- the layout of Data and sync waits for the end of combat: the secure reload button hangs from its row
function SET.placeData()
  local d = SET.data; if not d then return end
  if InCombatLockdown and InCombatLockdown() then
    if not d.regen then
      d.regen = CreateFrame("Frame")
      d.regen:SetScript("OnEvent", function() pcall(SET.place, d.pg, d.sections, d.footer) end)
      d.regen:RegisterEvent("PLAYER_REGEN_ENABLED")
    end
    return
  end
  pcall(SET.place, d.pg, d.sections, d.footer)
end
function SET.applyCode()
  local d = SET.data; if not d then return end
  local ack = ns.parseAckCode and ns.parseAckCode(d.ackBox:GetText())
  if ack then
    local marked = ns.applyAck(ack, "paste"); d.ackBox:SetText(""); d.ackErrorOn = nil; d.ackError:Hide()
    if ns.msg then ns.msg(("desktop sync applied: %s saved"):format(UI.plural(marked, "pull"))) end
  else
    d.ackError:Set(UI.dot("bad") .. "That is not a code from the desktop app. It looks like EB-ACK- and a number."); d.ackErrorOn = true
  end
  SET.refreshData()
end
function SET.turnOn()
  if ns.Logging and ns.Logging.enforce then pcall(ns.Logging.enforce, true) end
  if UI.refreshStatus then pcall(UI.refreshStatus) end
  SET.refreshData()
end
function SET.refreshData()
  local d = SET.data; if not d then return end
  local st = cfg()
  -- desktop sync: both counts from the one Sync function
  local sync = ns.SyncState()
  local la, waiting = sync.lastAck, sync.waiting
  if la then
    -- (the pickup as a fixed moment and what it took, both from combat.lastAck: "Sat 21 Nov 11:45, 142 pulls")
    local took = (sync.ackFights and sync.ackFights > 0) and (", " .. UI.plural(sync.ackFights, "pull")) or ""
    d.syncStatus:SetState("Saved to everbuff.gg: " .. UI.fmtStamp(sync.ackAt or 0) .. took, "accent")
    UI.SetTip(d.syncStatus, { title = "Saved to everbuff.gg", text = "When the desktop app last picked your data up, and how many pulls it took." })
  else
    -- (never seen: said plainly; what to do about it is the hover, not a sentence on the page)
    d.syncStatus:SetState("Saved to everbuff.gg: not seen yet", "fgFaint")
    UI.SetTip(d.syncStatus, { title = "Not seen yet", text = "The desktop app has not picked your data up. Install it from everbuff.gg to keep your history and watch your video." })
  end
  pcall(d.placeholderSync)
  -- recording health
  local sess = ns.Recorder and ns.Recorder.active and ns.Recorder.active()
  local aclOn, combatOn = false, false
  if ns.Logging and ns.Logging.state then aclOn, combatOn = ns.Logging.state() end
  local zone = (GetRealZoneText and GetRealZoneText()) or nil
  if sess then d.rec:SetState("CAPTURING" .. ((type(zone) == "string" and zone ~= "") and (" in " .. zone) or ""), "accent")
  else d.rec:SetState("Standing by", "fgFaint") end
  d.combat:SetState(combatOn and "Combat log: on" or "Combat log: off", combatOn and "accent" or "warn", not combatOn)
  d.acl:SetState(aclOn and "Advanced combat logging: on" or "Advanced combat logging: off", aclOn and "accent" or "warn", not aclOn)
  d.remindCb:SetChecked(st.autoSave == nil or st.autoSave == true)
  -- stored data
  local db = ns.DB or { combat = {}, loot = {}, story = {} }
  for _, it in ipairs(STORED) do
    local r = d.stored[it[1]]
    local n = it[3](db)
    local extra, near = "", false
    if it[1] == "fights" and ns.Fights and ns.Fights.capInfo then
      local nF, cap = ns.Fights.capInfo()
      if nF >= cap - 25 then near = true; extra = (" \194\183 near the limit of %s: the oldest roll off"):format(UI.fmtNum(cap)) end
    end
    -- (a true stored count, 0 included; no sentence restates it)
    r:SetState(it[2] .. " \194\183 " .. it[4](n) .. extra, near and "warn" or "accent")
    r.count = n
  end
  -- advanced
  local open = st.advancedOpen == true
  d.advHead:SetLabel(open and "Advanced" or "Advanced \226\128\186")
  for _, it in ipairs(d.advItems) do if open then it:Show() else it:Hide() end end
  -- (the paste error only after a paste attempt; a Clear only for a store with something in it)
  if not (open and d.ackErrorOn) then d.ackError:Hide() end
  for _, it in ipairs(STORED) do
    local cr = d.clear[it[1]]
    if open and (d.stored[it[1]].count or 0) > 0 then cr:Show(); cr.btn:Show() else cr:Hide(); cr.btn:Hide() end
    pcall(cr.layout)
  end
  local cur = tonumber(st.statSample) or (ns.Fights and ns.Fights.DEFAULT_SAMPLE) or 1
  local pick
  for _, sm in ipairs(SAMPLES) do if sm[1] == cur then pick = sm[1] end end
  d.sampleSeg:SetValue(pick)
  local hidden, blind = (ns.Fights and ns.Fights.hiddenAuras) or 0, (ns.Fights and ns.Fights.blindScans) or 0
  if hidden == 0 and blind == 0 then d.auras:SetState("Aura names in combat: readable", "accent")
  else d.auras:SetState(("Aura names in combat: %s hidden by the client, %s skipped; names come back from the spell or after combat"):format(UI.fmtNum(hidden), UI.plural(blind, "scan")), "warn") end
  d.client:SetState(ns.hasSecretValues and "Client: damage and DPS come from the combat log file, by design" or "Client: every combat value is readable", "accent")
  local errs = (UI.tabErrors and UI.tabErrors()) or {}
  if #errs == 0 then d.ui:SetState("Window: every page built cleanly", "accent")
  else d.ui:SetState("Window: " .. table.concat(errs, " \194\183 "), "warn") end
  d.video:SetState("Video: the desktop app records it; the game cannot see it", "fgFaint")
  d.footerText:SetText(("everbuff.gg %s \194\183 type /eb help for every command"):format(tostring(ns.VERSION)))
  SET.placeData()
end

-- ═══ the Settings tab ══════════════════════════════════════════════════════════════════════════════════════════
local ticker
function ns.BuildSettings(content)
  SET.content = content
  local subtabs = UI.SubTabs(content, {
    { key = "general", label = "General", desc = "How the window and on-screen notifications behave." },
    { key = "golddisplay", label = "Gold display", desc = "Where your gold shows outside this window: the tooltips and the small line on screen." },
    { key = "data", label = "Data and sync", desc = "Whether your data reaches everbuff.gg, and what is stored." },
  }, { onSelect = function(key)
    if key == "general" then SET.refreshGeneral() elseif key == "data" then SET.refreshData()
    elseif key == "golddisplay" and SET.goldRefresh then pcall(SET.goldRefresh) end
  end })
  content.subtabs = subtabs
  -- panes built eagerly, so the tests cover them
  buildGeneral(subtabs.panes.general)
  if ns.BuildGoldSettings then SET.goldRefresh = ns.BuildGoldSettings(subtabs.panes.golddisplay); content.goldRefresh = SET.goldRefresh end
  buildData(subtabs.panes.data)
  content.ackBox, content.ackBtn = SET.data.ackBox, SET.data.ackBtn
  content.refresh = function() SET.refreshGeneral(); SET.refreshData(); if SET.goldRefresh then pcall(SET.goldRefresh) end end
  subtabs.select("general")
  if not ticker and C_Timer and C_Timer.NewTicker then
    ticker = C_Timer.NewTicker(3, function() if SET.data and SET.data.pane:IsShown() then pcall(SET.refreshData) end end)
  end
end
