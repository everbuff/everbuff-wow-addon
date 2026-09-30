-- Everbuff.GG · UI.lua - the in-game panel: window frame, tab strip, shared widgets, theme.
--
-- Theme mirrors everbuff.gg: dark panels, gold + cyan accents. Tabs register themselves and are
-- built lazily on first open. Raid-lead tabs (Runs/Loot/Readiness) are deferred, see future/.

local ADDON, ns = ...
local UI = {}
ns.UI = UI

-- ── palette (RGB 0..1) ────────────────────────────────────────────────────────
-- Quiet Precision (everbuff-business #36): charcoal surfaces, one mint accent, neutral text. Tan and ember
-- left the interface; the keys stay so every screen keeps working. Values mirror everbuff-claude design/tokens.json.
UI.C = {
  bg      = { 0.067, 0.067, 0.067 },   -- n1 #111111 canvas
  panel   = { 0.098, 0.098, 0.106 },   -- n2 #19191B panels and cards
  panel2  = { 0.133, 0.133, 0.145 },   -- n3 #222225 raised and hover
  line    = { 0.180, 0.180, 0.200 },   -- n5 #2E2E33 hairline
  edge    = { 0.180, 0.180, 0.200 },   -- n5, the 1 px frame edge
  edgeHi  = { 0.431, 0.451, 0.478 },   -- n7 #6E737A, a hovered or focused edge
  hover   = { 0.165, 0.165, 0.180 },   -- n4 #2A2A2E, hover one step up from raised
  data    = { 0.357, 0.608, 0.941 },   -- data blue #5B9BF0, for kinds of events (never the accent)
  ink     = { 0.953, 0.957, 0.961 },   -- n10 #F3F4F5 text
  dim     = { 0.549, 0.569, 0.592 },   -- n8 #8C9197 secondary text
  gold    = { 0.780, 0.792, 0.804 },   -- n9 #C7CACD, headings (was tan)
  cyan    = { 0.047, 0.824, 0.616 },   -- mint #0CD29D, the accent (was lagoon)
  green   = { 0.298, 0.765, 0.541 },   -- success #4CC38A
  red     = { 1.000, 0.420, 0.435 },   -- danger #FF6B6F (was ember)
}
local C = UI.C
-- ── type kit ──────────────────────────────────────────────────────────────────
-- The faces of the desktop app (everbuff-business #36): Inter Medium and SemiBold for everything read (Medium,
-- not Regular: WoW's rasterizer draws Inter 400 thin at small sizes), Chakra Petch for the wordmark and the
-- big numbers. Static TTF instances in media/fonts (SIL OFL). Bundled as TTF in media/fonts (SIL OFL); native fallback.
local FONT_DIR = "Interface\\AddOns\\EverbuffJournal\\media\\fonts\\"
local NATIVE_FALLBACK = "Fonts\\ARIALN.TTF"
local function mkfont(name, file, size, flags, color, shadow)
  if not CreateFont then return nil end
  local f = CreateFont(name)
  local ok = f:SetFont(file, size, flags or "")
  if ok == false then f:SetFont(NATIVE_FALLBACK, size, flags or "") end   -- file missing: native face
  if color then f:SetTextColor(color[1], color[2], color[3]) end
  if shadow then f:SetShadowColor(0, 0, 0, 0.9); f:SetShadowOffset(1, -1) end
  return f
end
UI.TITLE_FONT = mkfont("EverbuffTitleFont", FONT_DIR .. "ChakraPetch-SemiBold.ttf", 15, "", C.ink, true)
UI.VALUE_FONT = mkfont("EverbuffValueFont", FONT_DIR .. "ChakraPetch-Bold.ttf", 18, "", C.ink, true)
UI.HEAD_FONT  = mkfont("EverbuffHeadFont",  FONT_DIR .. "Inter-SemiBold.ttf", 13, "", C.ink, true)
UI.LABEL_FONT = mkfont("EverbuffLabelFont", FONT_DIR .. "Inter-SemiBold.ttf", 11, "", C.dim, false)
UI.TAB_FONT   = mkfont("EverbuffTabFont",   FONT_DIR .. "Inter-SemiBold.ttf", 12, "", C.dim, true)
UI.BODY_FONT  = mkfont("EverbuffBodyFont",  FONT_DIR .. "Inter-Medium.ttf", 12, "", C.ink, false)
UI.BODY_SM    = mkfont("EverbuffBodySmall", FONT_DIR .. "Inter-Medium.ttf", 11, "", C.ink, false)
UI.DIM_SM     = mkfont("EverbuffDimSmall",  FONT_DIR .. "Inter-Medium.ttf", 11, "", C.dim, false)
-- map a Blizzard template (name or font object) to the brand font that plays its role
local FONT_ROLE = {
  GameFontNormalLarge = "TITLE_FONT", GameFontNormal = "HEAD_FONT", GameFontNormalSmall = "LABEL_FONT",
  GameFontHighlight = "BODY_FONT", GameFontHighlightSmall = "BODY_SM", GameFontDisableSmall = "DIM_SM",
}
function UI.Font(tmpl)
  if tmpl == nil then return nil end
  local key = tmpl
  if type(tmpl) ~= "string" then
    key = nil
    for name in pairs(FONT_ROLE) do if _G[name] == tmpl then key = name; break end end
  end
  local role = key and FONT_ROLE[key]
  return role and UI[role] or nil
end

local function unpackc(c, a) return c[1], c[2], c[3], a or 1 end

-- ── small widget helpers ──────────────────────────────────────────────────────

-- A filled, thin-bordered panel.
function UI.Panel(parent, r, g, b, a)
  local p = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  p:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
  })
  p:SetBackdropColor(r or C.panel[1], g or C.panel[2], b or C.panel[3], a or 0.92)
  p:SetBackdropBorderColor(C.edge[1], C.edge[2], C.edge[3], 1)   -- the hairline edge
  return p
end

function UI.FS(parent, template, color)
  local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
  local f = UI.Font(template or "GameFontHighlight")
  if f then fs:SetFontObject(f) end
  if color then fs:SetTextColor(unpackc(color)) end
  return fs
end

function UI.Button(parent, text, w, h, onClick)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetSize(w or 100, h or 22)
  b:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
  })
  b:SetBackdropColor(unpackc(C.panel2, 1))
  b:SetBackdropBorderColor(unpackc(C.panel2, 1))
  local fs = ns.UI.FS(b, "GameFontNormal")
  fs:SetPoint("CENTER"); fs:SetText(text); fs:SetTextColor(unpackc(C.ink))
  b.text = fs
  b:SetScript("OnEnter", function(s) s:SetBackdropColor(unpackc(C.hover, 1)); s:SetBackdropBorderColor(unpackc(C.hover, 1)) end)
  b:SetScript("OnLeave", function(s) s:SetBackdropColor(unpackc(C.panel2, 1)); s:SetBackdropBorderColor(unpackc(C.panel2, 1)) end)
  if onClick then b:SetScript("OnClick", onClick) end
  return b
end

function UI.EditBox(parent, w, h)
  local e = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
  e:SetSize(w or 200, h or 22)
  e:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
  e:SetBackdropColor(C.panel[1], C.panel[2], C.panel[3], 0.95); e:SetBackdropBorderColor(C.edge[1], C.edge[2], C.edge[3], 1)
  e:SetFontObject(UI.BODY_SM or "GameFontHighlight")
  e:SetScript("OnEditFocusGained", function(x) x:SetBackdropBorderColor(unpackc(C.edgeHi)) end)
  e:SetScript("OnEditFocusLost", function(x) x:SetBackdropBorderColor(C.edge[1], C.edge[2], C.edge[3], 1) end)
  e:SetTextInsets(6, 6, 0, 0)
  e:SetAutoFocus(false)
  e:SetScript("OnEscapePressed", e.ClearFocus)
  e:SetScript("OnEnterPressed", e.ClearFocus)
  return e
end

-- A vertically scrolling list host. Returns the scroll child; add rows to it and call layout yourself.
function UI.ScrollChild(parent)
  local sf = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
  local child = CreateFrame("Frame", nil, sf)
  child:SetSize(1, 1)
  sf:SetScrollChild(child)
  sf.child = child
  return sf, child
end

function UI.ClassColor(classFile)
  local c = classFile and (RAID_CLASS_COLORS or {})[classFile]
  if c then return c.r, c.g, c.b end
  return unpackc(C.ink)
end

-- ── main window ───────────────────────────────────────────────────────────────
local frame
local tabs = {}      -- { {name=, build=, order=, btn=, content=, built=} }
local activeName

local function styleTabButton(t, active)
  local b = t.btn
  if active then
    b:SetBackdropColor(C.panel2[1], C.panel2[2], C.panel2[3], 0.95)
    if b.accent then b.accent:SetColorTexture(unpackc(C.cyan)) end
    b.text:SetTextColor(unpackc(C.ink))
    if b.icon then b.icon:SetVertexColor(1, 1, 1) end
  else
    b:SetBackdropColor(0, 0, 0, 0)
    if b.accent then b.accent:SetColorTexture(0, 0, 0, 0) end
    b.text:SetTextColor(unpackc(C.dim))
    if b.icon then b.icon:SetVertexColor(0.72, 0.72, 0.72) end
  end
end

local function selectTab(name)
  if not frame then return end
  for _, t in ipairs(tabs) do
    local on = (t.name == name)
    styleTabButton(t, on)
    if on then
      if not t.built then
        t.content = CreateFrame("Frame", nil, frame.contentHost)
        t.content:SetAllPoints(frame.contentHost)
        local ok, err = pcall(t.build, t.content)
        t.buildError = (not ok) and tostring(err) or nil      -- surfaced in Sync + the test suite
        if not ok then
          local fs = ns.UI.FS(t.content, "GameFontHighlight")
          fs:SetPoint("TOPLEFT", 12, -12); fs:SetText("|cffe25a5aerror building tab:|r " .. tostring(err))
        end
        t.built = true
      end
      t.content:Show()
      if t.onShow then
        local ok2, e2 = pcall(t.onShow)
        t.showError = (not ok2) and tostring(e2) or nil
      end
    elseif t.content then
      t.content:Hide()
    end
  end
  activeName = name
end

local function buildFrame()
  if frame then return end
  local f = CreateFrame("Frame", "EverbuffFrame", UIParent, "BackdropTemplate")
  frame = f
  local ws = ns.DB and ns.DB.settings and ns.DB.settings.winSize
  f:SetSize((ws and tonumber(ws.w)) or 900, (ws and tonumber(ws.h)) or 580)
  f:SetScale((ns.DB and ns.DB.settings and tonumber(ns.DB.settings.winScale)) or 1)
  local pos = ns.DB and ns.DB.settings and ns.DB.settings.winPos
  if pos and type(pos.point) == "string" then f:SetPoint(pos.point, UIParent, pos.point, pos.x or 0, pos.y or 0)
  else f:SetPoint("CENTER") end
  f:SetFrameStrata("HIGH")
  f:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
  })
  f:SetBackdropColor(C.bg[1], C.bg[2], C.bg[3], 1)
  f:SetBackdropBorderColor(0, 0, 0, 1)
  f:EnableMouse(true); f:SetMovable(true); f:SetClampedToScreen(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(w)
    w:StopMovingOrSizing()
    if ns.DB and ns.DB.settings then   -- persist so the window opens where you left it
      local pt, _, _, x, y = w:GetPoint(1)
      if type(pt) == "string" then ns.DB.settings.winPos = { point = pt, x = x, y = y } end
    end
  end)
  tinsert(UISpecialFrames, "EverbuffFrame") -- ESC closes
  -- resizable: grow from the bottom-right grip; lists and panes are anchored to the edges so they grow
  -- with the window. Never smaller than the designed 900x580 (fixed column grids), persisted in settings.
  f:SetResizable(true)
  if f.SetResizeBounds then f:SetResizeBounds(900, 580, 1600, 1000) elseif f.SetMinResize then f:SetMinResize(900, 580); f:SetMaxResize(1600, 1000) end
  local grip = CreateFrame("Button", nil, f)
  grip:SetSize(16, 16); grip:SetPoint("BOTTOMRIGHT", -8, 8)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
  grip:SetScript("OnMouseUp", function()
    f:StopMovingOrSizing()
    UI.SetWindowSize(f:GetWidth(), f:GetHeight())
  end)

  -- title bar
  local bar = CreateFrame("Frame", nil, f)
  bar:SetPoint("TOPLEFT", 12, -12); bar:SetPoint("TOPRIGHT", -12, -12); bar:SetHeight(40)
  local barBg = bar:CreateTexture(nil, "BACKGROUND"); barBg:SetAllPoints(); barBg:SetColorTexture(0.043, 0.043, 0.047, 1)   -- n0, the desktop top bar
  local barRule = bar:CreateTexture(nil, "ARTWORK"); barRule:SetPoint("BOTTOMLEFT"); barRule:SetPoint("BOTTOMRIGHT"); barRule:SetHeight(1)
  barRule:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
  local mark = bar:CreateTexture(nil, "ARTWORK")
  mark:SetSize(26, 26); mark:SetPoint("LEFT", 10, 0)
  mark:SetTexture("Interface\\AddOns\\EverbuffJournal\\media\\mark")
  local brand = UI.FS(bar, "GameFontNormalLarge")
  brand:SetPoint("LEFT", mark, "RIGHT", 8, -1)
  brand:SetText("everbuff.gg")
  local ver = UI.FS(bar, "GameFontDisableSmall", C.dim)
  ver:SetPoint("LEFT", brand, "RIGHT", 8, -1); ver:SetText("v" .. ns.VERSION)

  local rec = UI.FS(bar, "GameFontNormalSmall")
  rec:SetPoint("RIGHT", -46, 0)
  f.recFS = rec

  -- native WoW close button: always centered and reads as the game
  local close = CreateFrame("Button", nil, bar, "UIPanelCloseButton")
  close:SetSize(26, 26); close:SetPoint("RIGHT", -2, 0)
  close:SetScript("OnClick", function() f:Hide() end)

  -- left tab strip
  local strip = CreateFrame("Frame", nil, f)
  strip:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -1); strip:SetPoint("BOTTOMLEFT", 12, 12); strip:SetWidth(142)
  local stripBg = strip:CreateTexture(nil, "BACKGROUND"); stripBg:SetAllPoints(); stripBg:SetColorTexture(0, 0, 0, 0.35)
  local stripRule = strip:CreateTexture(nil, "ARTWORK"); stripRule:SetPoint("TOPRIGHT"); stripRule:SetPoint("BOTTOMRIGHT"); stripRule:SetWidth(1)
  stripRule:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
  f.strip = strip

  -- content host
  local host = CreateFrame("Frame", nil, f)
  host:SetPoint("TOPLEFT", strip, "TOPRIGHT", 1, -6)
  host:SetPoint("BOTTOMRIGHT", -14, 14)
  f.contentHost = host

  -- lay out tab buttons, grouped (Background vs Raid lead) with dim section labels.
  -- tabs flagged pin=="bottom" are anchored to the bottom of the strip instead of flowing top-down.
  table.sort(tabs, function(a, b) return a.order < b.order end)
  -- per-tab nav icons (WoW built-in textures)
  local TAB_ICONS = {
    ["Home"]       = "Interface\\Icons\\INV_Misc_Map_01",              -- how am I doing
    ["Combat"]     = "Interface\\GossipFrame\\BattleMasterGossipIcon", -- what happened when I fought
    ["Loot"]       = "Interface\\Icons\\INV_Misc_Coin_01",             -- what did I get
    ["Character"]  = "Interface\\Icons\\INV_Misc_Book_09",             -- how is my character growing
    ["Settings"]   = "Interface\\Buttons\\UI-OptionsButton",           -- gear
  }
  local function makeButton(t, point, ox, oy, rel)
    local b = CreateFrame("Button", nil, strip, "BackdropTemplate")
    b:SetSize(130, 30)
    b:SetPoint(point, rel or strip, point, ox, oy)
    b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    b.accent = b:CreateTexture(nil, "OVERLAY"); b.accent:SetPoint("TOPLEFT"); b.accent:SetPoint("BOTTOMLEFT"); b.accent:SetWidth(3)
    b:SetScript("OnEnter", function(s) if activeName ~= t.name then s:SetBackdropColor(C.panel[1], C.panel[2], C.panel[3], 1); s.text:SetTextColor(unpackc(C.ink)) end end)
    b:SetScript("OnLeave", function(s) styleTabButton(t, activeName == t.name) end)
    local ic = TAB_ICONS[t.name]
    local tx = 10
    if ic then
      local icon = b:CreateTexture(nil, "ARTWORK")
      icon:SetSize(16, 16); icon:SetPoint("LEFT", 10, 0); icon:SetTexture(ic)
      b.icon = icon; tx = 32
    end
    local fs = ns.UI.FS(b, "GameFontNormal")
    fs:SetPoint("LEFT", tx, 0); fs:SetText(t.name)
    b.text = fs
    b:SetScript("OnClick", function() selectTab(t.name) end)
    t.btn = b
    styleTabButton(t, false)
  end
  local y = -10
  local lastGroup
  for _, t in ipairs(tabs) do
    if t.pin ~= "bottom" then
      if t.group and t.group ~= lastGroup then
        local lbl = ns.UI.FS(strip, "GameFontNormalSmall")
        lbl:SetPoint("TOPLEFT", 10, y - 2)
        lbl:SetText(t.group:upper()); lbl:SetTextColor(unpackc(C.dim))
        y = y - 18
        lastGroup = t.group
      end
      makeButton(t, "TOPLEFT", 6, y)
      y = y - 32
    end
  end
  -- bottom-pinned tabs (e.g. Settings): stack up from the strip's bottom edge
  local by = 8
  for i = #tabs, 1, -1 do
    local t = tabs[i]
    if t.pin == "bottom" then
      makeButton(t, "BOTTOMLEFT", 6, by)
      by = by + 32
    end
  end

  -- live recording status ticker on the title bar
  f:SetScript("OnShow", function()
    UI.refreshStatus()
    if not f.ticker then f.ticker = C_Timer.NewTicker(2, UI.refreshStatus) end
  end)
  f:SetScript("OnHide", function()
    if f.ticker then f.ticker:Cancel(); f.ticker = nil end
  end)
  f:Hide()  -- CreateFrame shows by default; start hidden so the first Toggle opens (not hides) it
end

-- inline status icons for the title bar (WoW texture escape sequences)
local ICO = "|T%s:14:14:0:-1|t"
local IND_GREEN  = "Interface\\COMMON\\Indicator-Green"
local IND_GRAY   = "Interface\\COMMON\\Indicator-Gray"
local IND_YELLOW = "Interface\\COMMON\\Indicator-Yellow"
local CHK_ON     = "Interface\\RaidFrame\\ReadyCheck-Ready"
local CHK_OFF    = "Interface\\RaidFrame\\ReadyCheck-NotReady"
local CHK_WAIT   = "Interface\\RaidFrame\\ReadyCheck-Waiting"

function UI.refreshStatus()
  if not (frame and frame:IsShown()) then return end
  local sess = ns.Recorder and ns.Recorder.active()
  local aclOn, combatOn = ns.Logging.state()
  -- ONE honest indicator of what the addon can actually know: whether ITS capture (session beacon +
  -- combat-log file) is live. It cannot see the desktop app, so video "recording" is never claimed here.
  local state
  if sess and combatOn and aclOn then
    state = ICO:format(IND_GREEN) .. " |cff59c77fCAPTURING|r  |cff0cd29d" .. (sess.context or "?") .. "|r"
  elseif sess and combatOn then
    state = ICO:format(IND_YELLOW) .. " |cffc7cacdCAPTURING (basic log)|r"
  elseif sess then
    state = ICO:format(IND_YELLOW) .. " |cffc7cacdCAPTURING, COMBAT LOG OFF|r"
  elseif IsInInstance() then
    state = ICO:format(IND_YELLOW) .. " |cffc7cacdSTARTING|r"
  else
    state = ICO:format(IND_GRAY) .. " |cff8c9197STANDING BY|r"
  end
  frame.recFS:SetText(state)
end

-- ── public API ────────────────────────────────────────────────────────────────

-- order: lower shows higher in the strip. group: dim section label shown above the first tab of it.
-- pin: "bottom" anchors the tab to the bottom of the strip (e.g. Settings) instead of the top-down flow.
function UI.registerTab(order, name, build, onShow, group, pin)
  tabs[#tabs + 1] = { order = order, name = name, build = build, onShow = onShow, group = group, pin = pin }
end

-- ── HOST tabs: one question each (Home · Combat · Loot · Character), answered by PANES on a UI.Tabs
--    control. A pane is what used to be a whole tab; it is built lazily on first select into the pane's
--    content frame and refreshed (onShow) every time it is selected. Panes never draw a title: the host
--    owns the title and subtitle. Pane key = label lowercased without spaces ("Dungeons" -> "dungeons").
local hosts = {}
local function paneKey(label) return (label:lower():gsub("%s+", "")) end
local function buildHost(t, content)
  local title = UI.FS(content, "GameFontNormalLarge"); title:SetPoint("TOPLEFT", 14, -14); title:SetText(t.name)
  local sub = UI.FS(content, "GameFontHighlightSmall", C.dim); sub:SetPoint("TOPLEFT", 14, -38); sub:SetWidth(700); sub:SetJustifyH("LEFT")
  sub:SetText(t.subtitle or "")
  table.sort(t.panes, function(a, b) return a.order < b.order end)
  local items = {}
  t.paneByKey = {}
  for _, pn in ipairs(t.panes) do items[#items + 1] = { key = pn.key, label = pn.label }; t.paneByKey[pn.key] = pn end
  t.ctl = UI.Tabs(content, items, nil, 14, { onSelect = function(key)
    local pn = t.paneByKey[key]; if not pn then return end
    if not pn.built then
      pn.content = CreateFrame("Frame", nil, t.ctl.panes[key]); pn.content:SetAllPoints()
      local ok, err = pcall(pn.build, pn.content)
      pn.buildError = (not ok) and tostring(err) or nil
      if not ok then
        local fs = UI.FS(pn.content, "GameFontHighlight"); fs:SetPoint("TOPLEFT", 12, -12); fs:SetText("|cffe25a5aerror building pane:|r " .. tostring(err))
      end
      pn.built = true
    end
    if pn.onShow then local ok2, e2 = pcall(pn.onShow); pn.showError = (not ok2) and tostring(e2) or nil end
  end })
  content.tabs = t.ctl
  if items[1] then t.ctl.select(items[1].key) end
end
function UI.registerHost(order, name, subtitle)
  if hosts[name] then if subtitle then hosts[name].subtitle = subtitle end return hosts[name] end
  local t = { order = order, name = name, subtitle = subtitle, panes = {}, host = true }
  t.build = function(content) buildHost(t, content) end
  t.onShow = function()
    local pn = t.ctl and t.paneByKey and t.paneByKey[t.ctl.active]
    if pn and pn.built and pn.onShow then pn.onShow() end
  end
  tabs[#tabs + 1] = t; hosts[name] = t
  return t
end
function UI.registerPane(hostName, order, label, build, onShow)
  local h = hosts[hostName] or UI.registerHost(50, hostName, nil)
  h.panes[#h.panes + 1] = { order = order, key = paneKey(label), label = label, build = build, onShow = onShow }
end
function UI.paneErrors()
  local out = {}
  for _, t in ipairs(tabs) do
    if t.host and t.paneByKey then
      for k, pn in pairs(t.paneByKey) do
        if pn.buildError then out[#out + 1] = t.name .. "/" .. k .. ": " .. pn.buildError end
        if pn.showError then out[#out + 1] = t.name .. "/" .. k .. " (show): " .. pn.showError end
      end
    end
  end
  return out
end

-- Open the window on a tab; `sub` selects a pane of a host tab ("Combat", "fights").
-- persist + apply a window size (used by the resize grip; clamped to the designed minimum)
function UI.SetWindowSize(w, h)
  w = math.max(900, math.floor(tonumber(w) or 900)); h = math.max(580, math.floor(tonumber(h) or 580))
  if ns.DB and ns.DB.settings then ns.DB.settings.winSize = { w = w, h = h } end
  if frame then frame:SetSize(w, h) end
end

function UI.Open(name, sub)
  if ns.blockedInCombat and ns.blockedInCombat() then return end
  buildFrame()
  frame:Show()
  selectTab(name or activeName or (tabs[1] and tabs[1].name))
  if sub and name and hosts[name] and hosts[name].ctl then hosts[name].ctl.select(sub) end
end

-- ── sub-tabs: a real tab control, not a row of buttons. A bordered pane with the tabs sitting ON its
--    top edge; the active tab shares the pane's fill and merges into it (border covered, tan accent on
--    top); inactive tabs are dimmer, shorter and set behind. items = { { key=, label= }, ... }.
--    Returns ctl with ctl.panes[key] (parent your content into these), ctl.select(key), ctl.active.
function UI.Tabs(parent, items, top, sidePad, opts)
  -- geometry: the strip sits 18px clear of the page subtitle; every tab is the SAME height so labels
  -- never shift between states; tabs size to their label with 14px side padding and a 6px gap.
  top = top or -96; sidePad = sidePad or 14; opts = opts or {}
  local TAB_H, PAD, GAP = 26, 14, 6
  local ctl = { panes = {}, tabs = {} }
  local pane = UI.Panel(parent)
  pane:SetPoint("TOPLEFT", sidePad, top); pane:SetPoint("BOTTOMRIGHT", -sidePad, 12)
  ctl.host = pane
  local x = 12
  for _, it in ipairs(items) do
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetPoint("BOTTOMLEFT", pane, "TOPLEFT", x, -1)          -- rests on the pane's top edge
    b:SetFrameLevel((pane:GetFrameLevel() or 1) + 5)          -- draws over the pane border
    b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8",
      edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    b.accent = b:CreateTexture(nil, "OVERLAY"); b.accent:SetPoint("BOTTOMLEFT", 0, 0); b.accent:SetPoint("BOTTOMRIGHT", 0, 0); b.accent:SetHeight(2)
    b.join = b:CreateTexture(nil, "OVERLAY"); b.join:SetPoint("BOTTOMLEFT", 3, -3); b.join:SetPoint("BOTTOMRIGHT", -3, -3); b.join:SetHeight(6)
    b.text = UI.FS(b, "GameFontNormalSmall")
    if UI.TAB_FONT then b.text:SetFontObject(UI.TAB_FONT) end
    b.text:SetPoint("CENTER", 0, 0); b.text:SetJustifyH("CENTER"); b.text:SetText(it.label)   -- sentence case (#36)
    local w = math.max(84, math.floor((b.text:GetStringWidth() or 60) + PAD * 2 + 0.5))
    b:SetSize(w, TAB_H)
    b.key = it.key
    b:SetScript("OnClick", function(tb) ctl.select(tb.key) end)
    b:SetScript("OnEnter", function(tb) if ctl.active ~= tb.key then tb.text:SetTextColor(unpackc(C.ink)) end end)
    b:SetScript("OnLeave", function() ctl.style() end)
    -- shared mode: the tabs FILTER one content area instead of switching panes
    if opts.shared then
      if not ctl.content then
        ctl.content = CreateFrame("Frame", nil, pane)
        ctl.content:SetPoint("TOPLEFT", 10, -12); ctl.content:SetPoint("BOTTOMRIGHT", -10, 8)
      end
      ctl.panes[it.key] = ctl.content
    else
      local content = CreateFrame("Frame", nil, pane)
      content:SetPoint("TOPLEFT", 10, -12); content:SetPoint("BOTTOMRIGHT", -10, 8); content:Hide()
      ctl.panes[it.key] = content
    end
    ctl.tabs[#ctl.tabs + 1] = b
    x = x + w + GAP
  end
  function ctl.style()
    for _, b in ipairs(ctl.tabs) do
      -- no box around a tab: the label alone, as on the desktop; the frame stays so layout and clicks are unchanged
      b:SetBackdropColor(0, 0, 0, 0); b:SetBackdropBorderColor(0, 0, 0, 0)
      b.join:SetColorTexture(0, 0, 0, 0)
      b:SetAlpha(1)
      if b.key == ctl.active then
        b.accent:SetColorTexture(unpackc(C.cyan))
        b.text:SetTextColor(unpackc(C.ink))
      else
        b.accent:SetColorTexture(0, 0, 0, 0)
        b.text:SetTextColor(unpackc(C.dim))
      end
    end
  end
  function ctl.select(key)
    ctl.active = key
    if not opts.shared then
      for k, pn in pairs(ctl.panes) do if k == key then pn:Show() else pn:Hide() end end
    end
    ctl.style()
    if opts.onSelect then opts.onSelect(key) end
  end
  return ctl
end

-- Location is TWO columns everywhere: the place name (fmtPlace) and the coordinates (fmtCoords).
-- Source (who / what) is a third, separate column. fmtLocation joins both for single-line prose only.
-- day separator label for time-ordered lists: "Today", "Yesterday", else "Thursday, Sep 25"
function UI.fmtDay(t, nowT)
  t = tonumber(t) or 0
  nowT = nowT or ((GetServerTime and GetServerTime()) or time())
  local d, today, yday = date("%Y-%m-%d", t), date("%Y-%m-%d", nowT), date("%Y-%m-%d", nowT - 86400)
  if d == today then return "Today" elseif d == yday then return "Yesterday" end
  return date("%A, %b %d", t)
end
function UI.fmtPlace(zone, sub)
  if sub and zone and sub ~= zone then return sub .. ", " .. zone end
  return sub or zone or ""
end
function UI.fmtCoords(x, y)
  if x and y then return ("%.1f, %.1f"):format(x * 100, y * 100) end
  return ""
end
function UI.fmtLocation(zone, x, y, sub)
  local place = sub or zone
  if sub and zone and sub ~= zone then place = sub .. ", " .. zone end
  if x and y then return (place and (place .. "  ") or "") .. ("(%.1f, %.1f)"):format(x * 100, y * 100) end
  return place or ""
end

-- ── minimap button: the conventional launcher. Left-click opens, right-click opens Settings, drag
--    moves it around the minimap edge (angle persisted). Built once on PLAYER_ENTERING_WORLD by Core.
function UI.buildMinimapButton()
  if not Minimap or UI.minimapBtn then return end
  local b = CreateFrame("Button", "EverbuffMinimapButton", Minimap)
  b:SetSize(31, 31); b:SetFrameStrata("MEDIUM"); b:SetFrameLevel(8)
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  local ring = b:CreateTexture(nil, "OVERLAY"); ring:SetSize(53, 53); ring:SetPoint("TOPLEFT")
  ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  local icon = b:CreateTexture(nil, "BACKGROUND"); icon:SetSize(20, 20); icon:SetPoint("TOPLEFT", 7, -6)
  icon:SetTexture("Interface\\AddOns\\EverbuffJournal\\media\\mark")
  local function place()
    local angle = (ns.DB and ns.DB.settings and tonumber(ns.DB.settings.minimapAngle)) or 220
    local r = ((Minimap:GetWidth() or 140) / 2) + 5
    b:ClearAllPoints()
    b:SetPoint("CENTER", Minimap, "CENTER", r * math.cos(math.rad(angle)), r * math.sin(math.rad(angle)))
  end
  b:RegisterForDrag("LeftButton")
  b:SetScript("OnDragStart", function(btn)
    btn:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter(); local cx, cy = GetCursorPosition()
      local sc = UIParent:GetEffectiveScale() or 1
      if mx and cx then
        local angle = math.deg(math.atan2((cy / sc) - my, (cx / sc) - mx))
        if ns.DB and ns.DB.settings then ns.DB.settings.minimapAngle = angle end
        place()
      end
    end)
  end)
  b:SetScript("OnDragStop", function(btn) btn:SetScript("OnUpdate", nil) end)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:SetScript("OnClick", function(_, which) if which == "RightButton" then UI.Open("Settings") else UI.Toggle() end end)
  b:SetScript("OnEnter", function(btn)
    GameTooltip:SetOwner(btn, "ANCHOR_LEFT")
    GameTooltip:AddLine("everbuff.gg")
    GameTooltip:AddLine("Left-click: open   Right-click: settings   Drag: move", 0.7, 0.7, 0.7)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  place()
  UI.minimapBtn = b
end

-- any tab whose build or refresh threw (for the Sync tab's UI-health line and the test suite)
function UI.tabErrors()
  local out = {}
  for _, t in ipairs(tabs) do
    if t.buildError then out[#out + 1] = t.name .. ": " .. t.buildError end
    if t.showError then out[#out + 1] = t.name .. " (refresh): " .. t.showError end
  end
  return out
end

function UI.SetWindowScale(sc)
  if frame and sc then frame:SetScale(sc) end
end

function UI.Toggle()
  buildFrame()
  if frame:IsShown() then frame:Hide() else UI.Open() end
end

-- Broadcast roster changes to any tab that cares (kept for the deferred raid-lead tabs in future/).
function UI.onRosterUpdate()
  for _, t in ipairs(tabs) do
    if t.content and t.content:IsShown() and t.onRoster then pcall(t.onRoster) end
  end
end

-- Let a tab register a roster-refresh hook (called by onRosterUpdate).
function UI.setRosterHook(name, fn)
  for _, t in ipairs(tabs) do if t.name == name then t.onRoster = fn end end
end

-- ── shared group helpers ──────────────────────────────────────────────────────
-- Returns a list of { unit, name, realm, class, classFile, role, online } for the current group
-- (or just the player when solo). Unit tokens are usable for aura/inspect reads outside combat.
function UI.groupMembers()
  if ns.Debug and ns.Debug.active() then return ns.Debug.members() end
  local out = {}
  local function add(unit)
    if not UnitExists(unit) then return end
    local name, realm = UnitNameUnmodified(unit)
    if not name then return end
    local classLoc, classFile = UnitClass(unit)
    out[#out + 1] = {
      unit = unit, name = name, realm = realm ~= "" and realm or nil,
      class = classLoc, classFile = classFile,
      role = UnitGroupRolesAssigned(unit),
      online = UnitIsConnected(unit) and true or false,
    }
  end
  if IsInRaid() then
    for i = 1, GetNumGroupMembers() do add("raid" .. i) end
  else
    add("player")
    for i = 1, GetNumGroupMembers() - 1 do add("party" .. i) end
  end
  return out
end

-- Whisper/report helper: sends to the right channel (RAID/PARTY) or prints if solo.
function UI.groupChannel()
  if IsInRaid() then return "RAID" elseif IsInGroup() then return "PARTY" end
  return nil
end

-- test exports
ns._test = ns._test or {}
ns._test.tabs = tabs
