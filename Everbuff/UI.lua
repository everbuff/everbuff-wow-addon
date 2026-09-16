-- Everbuff · UI.lua — the in-game panel: window frame, tab strip, shared widgets, theme.
--
-- Theme mirrors the web console (everbuff.gg / localhost:8080): dark panels, gold + cyan accents.
-- Tabs register themselves and are built lazily on first open. Today that's just Recording (the
-- always-on logging status); the raid-lead tabs (Runs/Loot/Readiness) are deferred — see future/.

local ADDON, ns = ...
local UI = {}
ns.UI = UI

-- ── palette (RGB 0..1) ────────────────────────────────────────────────────────
UI.C = {
  bg      = { 0.051, 0.059, 0.075 },
  panel   = { 0.082, 0.102, 0.129 },
  panel2  = { 0.106, 0.133, 0.173 },
  line    = { 0.149, 0.184, 0.231 },
  ink     = { 0.902, 0.922, 0.949 },
  dim     = { 0.541, 0.588, 0.651 },
  gold    = { 0.788, 0.651, 0.235 },
  cyan    = { 0.000, 0.686, 0.843 },
  green   = { 0.278, 0.788, 0.494 },
  red     = { 0.898, 0.329, 0.294 },
}
local C = UI.C

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
  p:SetBackdropColor(r or C.panel[1], g or C.panel[2], b or C.panel[3], a or 1)
  p:SetBackdropBorderColor(unpackc(C.line))
  return p
end

function UI.FS(parent, template, color)
  local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
  if color then fs:SetTextColor(unpackc(color)) end
  return fs
end

function UI.Button(parent, text, w, h, onClick)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetSize(w or 100, h or 22)
  b:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1,
  })
  b:SetBackdropColor(unpackc(C.panel2))
  b:SetBackdropBorderColor(unpackc(C.line))
  local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  fs:SetPoint("CENTER"); fs:SetText(text); fs:SetTextColor(unpackc(C.gold))
  b.text = fs
  b:SetScript("OnEnter", function(s) s:SetBackdropBorderColor(unpackc(C.gold)) end)
  b:SetScript("OnLeave", function(s) s:SetBackdropBorderColor(unpackc(C.line)) end)
  if onClick then b:SetScript("OnClick", onClick) end
  return b
end

function UI.EditBox(parent, w, h)
  local e = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
  e:SetSize(w or 200, h or 22)
  e:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  e:SetBackdropColor(0.03, 0.04, 0.05, 1); e:SetBackdropBorderColor(unpackc(C.line))
  e:SetFontObject("GameFontHighlight")
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
  if active then
    t.btn:SetBackdropColor(unpackc(C.panel2))
    t.btn:SetBackdropBorderColor(unpackc(C.gold))
    t.btn.text:SetTextColor(unpackc(C.gold))
  else
    t.btn:SetBackdropColor(unpackc(C.bg))
    t.btn:SetBackdropBorderColor(unpackc(C.line))
    t.btn.text:SetTextColor(unpackc(C.dim))
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
        if not ok then
          local fs = t.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
          fs:SetPoint("TOPLEFT", 12, -12); fs:SetText("|cffe25a5aerror building tab:|r " .. tostring(err))
        end
        t.built = true
      end
      t.content:Show()
      if t.onShow then pcall(t.onShow) end
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
  f:SetSize(900, 580)
  f:SetPoint("CENTER")
  f:SetFrameStrata("HIGH")
  f:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1,
  })
  f:SetBackdropColor(unpackc(C.bg))
  f:SetBackdropBorderColor(unpackc(C.gold))
  f:EnableMouse(true); f:SetMovable(true); f:SetClampedToScreen(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
  tinsert(UISpecialFrames, "EverbuffFrame") -- ESC closes

  -- title bar
  local bar = UI.Panel(f, unpackc(C.panel))
  bar:SetPoint("TOPLEFT", 1, -1); bar:SetPoint("TOPRIGHT", -1, -1); bar:SetHeight(38)
  local brand = UI.FS(bar, "GameFontNormalLarge")
  brand:SetPoint("LEFT", 14, 0)
  brand:SetText(ns.GOLD .. "Everbuff|r  " .. ns.CYAN .. "·|r  always-on recording")
  local ver = UI.FS(bar, "GameFontDisableSmall", C.dim)
  ver:SetPoint("LEFT", brand, "RIGHT", 8, -1); ver:SetText("v" .. ns.VERSION)

  local rec = UI.FS(bar, "GameFontHighlightSmall")
  rec:SetPoint("RIGHT", -44, 0)
  f.recFS = rec

  local close = UI.Button(bar, "X", 24, 22, function() f:Hide() end)
  close:SetPoint("RIGHT", -8, 0)

  -- left tab strip
  local strip = UI.Panel(f, unpackc(C.bg))
  strip:SetPoint("TOPLEFT", 1, -39); strip:SetPoint("BOTTOMLEFT", 1, 1); strip:SetWidth(140)
  f.strip = strip

  -- content host
  local host = CreateFrame("Frame", nil, f)
  host:SetPoint("TOPLEFT", strip, "TOPRIGHT", 1, -8)
  host:SetPoint("BOTTOMRIGHT", -8, 8)
  f.contentHost = host

  -- lay out tab buttons, grouped (Background vs Raid lead) with dim section labels
  table.sort(tabs, function(a, b) return a.order < b.order end)
  local y = -8
  local lastGroup
  for _, t in ipairs(tabs) do
    if t.group and t.group ~= lastGroup then
      local lbl = strip:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      lbl:SetPoint("TOPLEFT", 10, y - 2)
      lbl:SetText(t.group:upper()); lbl:SetTextColor(unpackc(C.dim))
      y = y - 18
      lastGroup = t.group
    end
    local b = CreateFrame("Button", nil, strip, "BackdropTemplate")
    b:SetSize(122, 30)
    b:SetPoint("TOPLEFT", 8, y)
    b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8",
      edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("LEFT", 10, 0); fs:SetText(t.name)
    b.text = fs
    b:SetScript("OnClick", function() selectTab(t.name) end)
    t.btn = b
    styleTabButton(t, false)
    y = y - 34
  end

  -- live recording status ticker on the title bar
  f:SetScript("OnShow", function()
    UI.refreshStatus()
    if not f.ticker then f.ticker = C_Timer.NewTicker(2, UI.refreshStatus) end
  end)
  f:SetScript("OnHide", function()
    if f.ticker then f.ticker:Cancel(); f.ticker = nil end
  end)
end

function UI.refreshStatus()
  if not (frame and frame:IsShown()) then return end
  local sess = ns.Recorder and ns.Recorder.active()
  if sess then
    local aclOn, combatOn = ns.Logging.state()
    local ok = aclOn and combatOn
    frame.recFS:SetText((ok and "|cff47c97erecording|r " or "|cffe5544blogging OFF|r ")
      .. (ns.CYAN .. (sess.context or "?") .. "|r"))
  else
    frame.recFS:SetText("|cff8a96a6idle|r")
  end
end

-- ── public API ────────────────────────────────────────────────────────────────

-- order: lower shows higher in the strip. group: dim section label shown above the first tab of it.
function UI.registerTab(order, name, build, onShow, group)
  tabs[#tabs + 1] = { order = order, name = name, build = build, onShow = onShow, group = group }
end

function UI.Open(name)
  buildFrame()
  frame:Show()
  selectTab(name or activeName or (tabs[1] and tabs[1].name))
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
