-- Everbuff.GG · UI.lua - the in-game panel: window frame, tab strip, shared widgets, theme.
--
-- Theme mirrors everbuff.gg: dark panels, gold + cyan accents. Tabs register themselves and are
-- built lazily on first open. Raid-lead tabs (Runs/Loot/Readiness) are deferred, see future/.

local ADDON, ns = ...
local UI = {}
ns.UI = UI

-- ── palette (RGB 0..1) ────────────────────────────────────────────────────────
-- Quiet Precision (everbuff-business #36): charcoal surfaces, one mint accent, neutral text. The colors come from
-- Theme.lua, generated from everbuff-claude design/tokens.json like the desktop's and the web's tokens.css, so one
-- token change reaches all three (wow-addon #19). Tan and ember left the interface; the old keys stay so every
-- screen keeps working.
local T = ns.Theme.color
UI.C = {
  bg      = T["bg-canvas"],        -- n1 #111111 canvas
  panel   = T["bg-panel"],         -- n2 #19191B panels and cards
  panel2  = T["bg-raised"],        -- n3 #222225 raised and hover
  line    = T["line"],             -- n5 #2E2E33 hairline
  edge    = T["line"],             -- n5, the 1 px frame edge
  edgeHi  = T["line-control"],     -- n7 #6E737A, a hovered or focused edge
  hover   = T["bg-hover-raised"],  -- n4 #2A2A2E, hover one step up from raised
  data    = { 0.357, 0.608, 0.941 },   -- data blue #5B9BF0, for kinds of events (never the accent); not a token
  ink     = T["fg"],               -- n10 #F3F4F5 text
  dim     = T["fg-muted"],         -- n8 #8C9197 secondary text
  gold    = T["fg-subtle"],        -- n9 #C7CACD, headings (was tan)
  cyan    = T["accent"],           -- mint #0CD29D, the accent (was lagoon)
  green   = T["success-fg"],       -- success #4CC38A
  red     = T["danger-fg"],        -- danger #FF6B6F (was ember)
  sunken  = T["bg-sunken"],        -- n0 #0B0B0C, the top bar
  accentFg = T["accent-fg"],       -- #35EEBB, the primary button's hover
  accentPressed = T["accent-pressed"], -- #08A67B, progress fills
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

-- ── spacing, sizes and money ─────────────────────────────────────────────────
-- Spacing is a multiple of 4 everywhere: XS 4, S 8, M 12, L 16; a pane's padding is M. Rows are 20 px. The scroll
-- bar of UIPanelScrollFrameTemplate sits outside its frame's right edge: a list leaves SCROLLBAR px free for it.
UI.SP = { XS = 4, S = 8, M = 12, L = 16, PAD = 12 }
UI.ROW_H = 20
UI.SCROLLBAR = 22
UI.WIN_MIN_W, UI.WIN_MIN_H, UI.WIN_MAX_W, UI.WIN_MAX_H = 900, 580, 1600, 1000

-- The one money formatter: "12,345g 6s 7c". Gold is grouped by thousands, a zero part is left out (0 is "0c"), and
-- the parts are joined by no-break spaces so a wrapping text never breaks inside an amount. A hidden or non-number
-- value reads as 0. With no options the text is the full amount without its sign, as every pane shows it.
-- Options (0.9.45, everbuff-wow-addon #43), `opts` a table:
--   signed   the sign is always printed: "+" or "-" (a caller can no longer forget it)
--   short    the glance form: under 1g silver and copper, under 100g gold and silver, from 100g gold only; the
--            smaller part is zero-padded ("12g 04s") so the width stays steady while the amount moves
--   compact  from 100,000g "123.4k" and from 1,000,000g "1.2M", with the gold icon, or "123.4k g" in letters (only
--            with `short`); the tenth is floored
--   icons    the coin icons instead of the letters g, s and c: inline textures of height 0, which follow the size
--            of the font they are drawn in
--   rate     round half away from zero (a rate); without it the amount is floored (a balance)
local NBSP = "\194\160"
UI.NBSP = NBSP
local function grouped(n)
  local s = tostring(n)
  local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  return (out:gsub("^,", ""))
end
local COIN_ICON = {
  g = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t",
  s = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t",
  c = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t",
}
UI.COIN_ICON = COIN_ICON
function ns.fmtMoney(c, opts)
  if type(c) ~= "number" or (issecretvalue and issecretvalue(c)) then c = 0 end
  if c ~= c or c == math.huge or c == -math.huge then c = 0 end
  if type(opts) ~= "table" then opts = nil end
  local neg = c < 0
  c = math.abs(c)
  local unit = (opts and opts.icons) and COIN_ICON or nil
  local function u(letter) return unit and unit[letter] or letter end
  local round = (opts and opts.rate) and function(v) return math.floor(v + 0.5) end or math.floor
  local text
  if opts and opts.short then
    -- the amount in the smallest unit its band shows (copper under 1g, silver under 100g, gold from there),
    -- rounded or floored in that unit; a value rounded up over its band is shown in the next one
    local gold, silver, copper = round(c / 10000), round(c / 100), round(c)
    if opts.compact and gold >= 1000000 then
      text = grouped(math.floor(gold / 1000000)) .. "." .. (math.floor(gold / 100000) % 10) .. "M" .. (unit and unit.g or (NBSP .. "g"))
    elseif opts.compact and gold >= 100000 then
      text = grouped(math.floor(gold / 1000)) .. "." .. (math.floor(gold / 100) % 10) .. "k" .. (unit and unit.g or (NBSP .. "g"))
    elseif c >= 1000000 or silver >= 10000 then
      text = grouped(c >= 1000000 and gold or math.floor(silver / 100)) .. u("g")
    elseif c >= 10000 or copper >= 10000 then
      if c < 10000 then silver = math.floor(copper / 100) end
      text = math.floor(silver / 100) .. u("g") .. NBSP .. ("%02d"):format(silver % 100) .. u("s")
    elseif copper >= 100 then
      text = math.floor(copper / 100) .. u("s") .. NBSP .. ("%02d"):format(copper % 100) .. u("c")
    else text = copper .. u("c") end
  else
    c = round(c)
    local g, s, cp = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
    local out = {}
    if g > 0 then out[#out + 1] = grouped(g) .. u("g") end
    if s > 0 then out[#out + 1] = s .. u("s") end
    if cp > 0 or #out == 0 then out[#out + 1] = cp .. u("c") end
    text = table.concat(out, NBSP)
  end
  if opts and opts.signed then text = (neg and "-" or "+") .. text end
  return text
end

-- ── cells and their tooltips ──────────────────────────────────────────────────
-- A table cell or column header: one line, never wrapped into the row below (founder, 2026-11-17: overflowing text in
-- tables). The client shortens a text longer than the cell with "..."; hovering the row shows the full text of every
-- shortened cell. When the row shows a tooltip of its own, the full texts are added under its lines, so a shortened
-- name can always be read in full. A row that builds its tooltip calls UI.AddCellLines(row) itself, or leaves it to
-- the hook, which runs after the row's own OnEnter. A cell placed straight on a list's scroll child (a detail page)
-- is one line too, but the page never takes the mouse for it (see isScrollChild).
local function truncatedTexts(row)
  local out = {}
  for _, fs in ipairs(row.ebCells or {}) do
    if fs:IsShown() and fs.IsTruncated and fs:IsTruncated() == true then
      local t = fs:GetText()
      if type(t) == "string" and t ~= "" then out[#out + 1] = { fs = fs, text = t } end
    end
  end
  return out
end
-- the left texts the tooltip shows now (GameTooltipTextLeft1..n), so a full text it already says is not added twice
local function tipLines(tip)
  local out = {}
  local ok, n = pcall(tip.NumLines, tip)
  local okN, name = pcall(tip.GetName, tip)
  if not (ok and type(n) == "number" and okN and type(name) == "string") then return out end
  for i = 1, n do
    local fs = _G[name .. "TextLeft" .. i]
    local okT, t = pcall(function() return fs and fs:GetText() end)
    if okT and type(t) == "string" and not (issecretvalue and issecretvalue(t)) then out[t] = true end
  end
  return out
end
-- add the full text of every shortened cell of `row` to the tooltip that is showing, unless it already says it;
-- returns how many were added
function UI.AddCellLines(row, tip)
  tip = tip or GameTooltip
  if not (row and tip) or row.ebCellLinesAdded then return 0 end
  local list = truncatedTexts(row)
  local have, added = tipLines(tip), 0
  for _, x in ipairs(list) do
    if not have[x.text] then tip:AddLine(x.text, 1, 1, 1, true); have[x.text] = true; added = added + 1 end
  end
  row.ebCellLinesAdded = true
  return added
end
local function cellTip(row)
  if not GameTooltip then return end
  local ownTip = GameTooltip:IsShown() and GameTooltip.GetOwner and GameTooltip:GetOwner() == row
  if ownTip then
    if UI.AddCellLines(row) > 0 then GameTooltip:Show() end   -- Show again so the tooltip grows to its new lines
    return
  end
  local list = truncatedTexts(row)
  if #list == 0 then return end
  -- anchored over the first shortened cell, where the eye already is, not at the far edge of a full-width row
  GameTooltip:SetOwner(row, "ANCHOR_NONE")
  GameTooltip:ClearAllPoints()
  GameTooltip:SetPoint("BOTTOMLEFT", list[1].fs, "TOPLEFT", -UI.SP.XS, UI.SP.XS)
  for _, x in ipairs(list) do GameTooltip:AddLine(x.text, 1, 1, 1, true) end
  row.ebCellLinesAdded = true
  GameTooltip:Show()
  row.ebCellTip = true
end
local function cellTipHide(row)
  if row.ebCellTip and GameTooltip then GameTooltip:Hide() end
  row.ebCellTip, row.ebCellLinesAdded = nil, nil
end
-- a list's scroll child holds a whole page (a detail view): it never takes the mouse, or hovering anywhere on the
-- page, gaps included, would open one tooltip for every shortened cell of the page and fight the page's own buttons
local function isScrollChild(f)
  if f.ebScrollChild then return true end
  local ok, r = pcall(function()
    local p = f.GetParent and f:GetParent()
    return p and p.GetScrollChild and p:GetScrollChild() == f
  end)
  return ok and r == true
end
local function hookCells(parent)
  if parent.ebCellHooked or not parent.HookScript or isScrollChild(parent) then return end
  parent.ebCellHooked = true
  -- a plain Frame gets no OnEnter until it takes the mouse
  if parent.EnableMouse and not (parent.IsMouseEnabled and parent:IsMouseEnabled() == true) then pcall(parent.EnableMouse, parent, true) end
  pcall(parent.HookScript, parent, "OnEnter", function(r) pcall(cellTip, r) end)
  pcall(parent.HookScript, parent, "OnLeave", function(r) pcall(cellTipHide, r) end)
end
function UI.CellFS(parent, template, color)
  local fs = UI.FS(parent, template, color)
  if fs.SetWordWrap then fs:SetWordWrap(false) end
  if fs.SetNonSpaceWrap then fs:SetNonSpaceWrap(false) end
  if fs.SetMaxLines then fs:SetMaxLines(1) end
  parent.ebCells = parent.ebCells or {}
  parent.ebCells[#parent.ebCells + 1] = fs
  hookCells(parent)
  return fs
end

-- A summary line across the top of a list pane: one line, anchored to both edges of `parent` (its text lines up with
-- a UI.Table's first column, its right end with the list's), `top` px down (default UI.SP.XS). The text wraps into
-- a second line when `wrap` is true; whatever sits below anchors to its bottom, so it moves down with it.
function UI.SummaryLine(parent, color, top, wrap)
  local fs = UI.FS(parent, "GameFontHighlightSmall", color)
  if not wrap then
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    if fs.SetMaxLines then fs:SetMaxLines(1) end
  end
  fs:SetJustifyH("LEFT")
  top = top or -UI.SP.XS
  fs:SetPoint("TOPLEFT", parent, "TOPLEFT", UI.SP.S, top)
  fs:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -(UI.SCROLLBAR + UI.SP.S), top)
  return fs
end
-- the rest of `parent` below `above` (a summary line made by UI.SummaryLine), `gap` px under it (default UI.SP.S):
-- a list built in it moves down when the text above takes a second line
function UI.Below(parent, above, gap)
  local body = CreateFrame("Frame", nil, parent)
  body:SetPoint("TOPLEFT", above, "BOTTOMLEFT", -UI.SP.S, -(gap or UI.SP.S))
  body:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
  return body
end

-- ── buttons and edit boxes ────────────────────────────────────────────────────
function UI.Button(parent, text, w, h, onClick)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetSize(w or 100, h or 22)
  b:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
  })
  local function rest(s)
    local c = s.ebSelected and C.hover or C.panel2
    s:SetBackdropColor(unpackc(c, 1)); s:SetBackdropBorderColor(unpackc(s.ebSelected and C.edgeHi or c, 1))
  end
  b.ebRest = rest
  rest(b)
  local fs = ns.UI.FS(b, "GameFontNormal")
  fs:SetPoint("CENTER"); fs:SetText(text); fs:SetTextColor(unpackc(C.ink))
  b.text = fs
  b:SetScript("OnEnter", function(s) s:SetBackdropColor(unpackc(C.hover, 1)); s:SetBackdropBorderColor(unpackc(s.ebSelected and C.edgeHi or C.hover, 1)) end)
  b:SetScript("OnLeave", rest)
  if onClick then b:SetScript("OnClick", onClick) end
  return b
end
-- a button as wide as its label plus M on each side (never narrower than `minW`)
function UI.FitButton(b, minW)
  local tw = (b.text and b.text.GetStringWidth and b.text:GetStringWidth()) or 0
  b:SetWidth(math.max(minW or 0, math.ceil(tw) + 2 * UI.SP.M))
  return b
end
-- the selected state of a button in a group (a filter): a fill and a brighter edge, not only a text color
function UI.SetButtonSelected(b, on)
  b.ebSelected = on and true or nil
  if b.ebRest then b.ebRest(b) end
  if b.text then b.text:SetTextColor(unpackc(on and C.ink or C.dim)) end
end

-- An edit box with an optional placeholder drawn inside it (a region of the box, so it sits on the box's fill and
-- moves with it). The box keeps the placeholder in step on OnTextChanged; callers add their own handling with
-- HookScript("OnTextChanged", fn), since SetScript would replace the placeholder's handler.
function UI.EditBox(parent, w, h, placeholder)
  local e = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
  e:SetSize(w or 200, h or 22)
  e:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
  e:SetBackdropColor(C.panel[1], C.panel[2], C.panel[3], 0.95); e:SetBackdropBorderColor(C.edge[1], C.edge[2], C.edge[3], 1)
  e:SetFontObject(UI.BODY_SM or "GameFontHighlight")
  e:SetScript("OnEditFocusGained", function(x) x:SetBackdropBorderColor(unpackc(C.edgeHi)) end)
  e:SetScript("OnEditFocusLost", function(x) x:SetBackdropBorderColor(C.edge[1], C.edge[2], C.edge[3], 1) end)
  e:SetTextInsets(UI.SP.S, UI.SP.S, 0, 0)
  e:SetAutoFocus(false)
  e:SetScript("OnEscapePressed", e.ClearFocus)
  e:SetScript("OnEnterPressed", e.ClearFocus)
  local ph = UI.FS(e, "GameFontDisableSmall", C.dim)
  if ph.SetWordWrap then ph:SetWordWrap(false) end
  if ph.SetMaxLines then ph:SetMaxLines(1) end
  ph:SetPoint("LEFT", e, "LEFT", UI.SP.S, 0); ph:SetPoint("RIGHT", e, "RIGHT", -UI.SP.S, 0); ph:SetJustifyH("LEFT")
  e.placeholder = ph
  local function sync(x) local t = x:GetText(); if t == nil or t == "" then ph:Show() else ph:Hide() end end
  e:SetScript("OnTextChanged", function(x) pcall(sync, x) end)
  function e.SetPlaceholder(_, text) ph:SetText(text or ""); sync(e) end
  e:SetPlaceholder(placeholder)
  return e
end

-- ── scroll lists ──────────────────────────────────────────────────────────────
-- A vertically scrolling list host. The helper owns the child's size: its width follows the scroll frame (on
-- OnSizeChanged and on show), its height is what the caller says the content needs (sf:SetContentHeight(h)).
-- sf.onResize(w) runs after the child takes a new width, so a list can lay its columns out again. While the player
-- drags the window's resize grip (UI.sizing), onResize is held and runs at most every UI.RESIZE_STEP seconds and
-- once more when the grip is let go, so a long list is not laid out again on every frame of the drag.
--   local sf, child = UI.ScrollChild(parent [, { top = -y, bottom = 0, left = 0, right = 0 }])
-- With the options the helper anchors the scroll frame inside `parent` and leaves the scroll bar's gutter
-- (UI.SCROLLBAR) at the right; without them the caller anchors it and leaves the gutter itself.
function UI.ScrollChild(parent, opts)
  local sf = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
  local child = CreateFrame("Frame", nil, sf)
  child:SetSize(1, 1)
  child.ebScrollChild = true
  sf:SetScrollChild(child)
  sf.child = child
  sf.contentH = 1
  if opts then
    sf:SetPoint("TOPLEFT", parent, "TOPLEFT", opts.left or 0, opts.top or 0)
    sf:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -((opts.right or 0) + UI.SCROLLBAR), opts.bottom or 0)
  end
  local function fit()
    local w = sf:GetWidth()
    if type(w) ~= "number" or w <= 1 then return end
    w = math.floor(w)
    if w == sf.contentW then return end
    sf.contentW = w
    child:SetWidth(w)
    if not sf.onResize then return end
    if UI.sizing then UI.QueueResize(sf) else sf.onResize(w) end
  end
  function sf.Fit() pcall(fit) end   -- never an error out of OnSizeChanged or OnShow
  function sf.SetContentHeight(_, h)
    h = tonumber(h) or 1
    sf.contentH = math.max(1, math.ceil(h))
    child:SetHeight(sf.contentH)
    if not sf.contentW then sf.Fit() end
  end
  sf:HookScript("OnSizeChanged", sf.Fit)
  sf:HookScript("OnShow", sf.Fit)
  return sf, child
end

-- the lists waiting for their onResize while the grip is dragged; one timer runs them, never more than one queued
UI.RESIZE_STEP = 0.1
local resizeQueue = { set = {}, timer = false }
function UI.FlushResizes()
  resizeQueue.timer = false
  local set = resizeQueue.set
  resizeQueue.set = {}
  for sf in pairs(set) do
    if sf.onResize and sf.contentW then pcall(sf.onResize, sf.contentW) end
  end
end
function UI.QueueResize(sf)
  resizeQueue.set[sf] = true
  if resizeQueue.timer then return end
  if C_Timer and C_Timer.After then
    resizeQueue.timer = true
    C_Timer.After(UI.RESIZE_STEP, function() pcall(UI.FlushResizes) end)
  else UI.FlushResizes() end
end
function UI.PendingResizes() local n = 0; for _ in pairs(resizeQueue.set) do n = n + 1 end; return n end

-- ── tables ────────────────────────────────────────────────────────────────────
-- UI.Table(parent, spec, opts): a header row, a scrolling list of rows and an empty state, laid out from a column
-- model so the header and the cells share one x per column at every window size.
--
-- spec: the columns, left to right. Each is
--   key      the cell's name: row.c[key] is its FontString (a Texture for kind "icon"); the header is tbl.head[key]
--   label    header text, drawn uppercase in the label font; "" for none
--   kind     "text" (default), "num", "money", "tag" or "icon". num and money are right-aligned and never shortened:
--            their column widens to the widest value shown. Only text columns ellipsize.
--   min      the narrowest the column gets, px
--   flex     a weight: flex columns share what the fixed columns leave (a name column is flex = 1). A column without
--            flex is fixed: max(min, its header, the widest `measure` value, the widest value shown for num/money/tag)
--   measure  realistic widest values (a list of strings, or a function returning one) the fixed width is measured
--            from; on a flex column they are its minimum (a realistic zone or summary line it never cuts)
--   justify  "LEFT", "RIGHT" or "CENTER"; default RIGHT for num and money, LEFT otherwise (the header follows it)
--   font     the cell's font template (default "GameFontHighlightSmall"); color: the name of its default text color
--            in UI.C ("ink" by default, "dim", "gold")
--   sort     true: the header is a button; a click calls opts.onSort(key, asc) and the arrow shows the order
-- opts:
--   top, bottom, left, right   the table's inset in `parent` (default 0, 0, 0, 0); the scroll bar gutter is added
--   rowHeight (UI.ROW_H), gap between columns (UI.SP.M), inset of the first and last column in a row (UI.SP.S)
--   iconSize (16), sortKey, sortAsc, onSort(key, asc)
--   tooltip(row, item, tip): fills the row's own tooltip (anchored to the first flex cell); the full text of every
--            shortened cell is added under it. Without it, hovering a row shows only the shortened cells' full texts.
--   onClick(row, item, button), emptyText (shown by setRows when there are no items); rightClick: true registers the
--            right button too (left only by default)
--   onLayout(tbl): runs after every relayout (a pane that places extras on its rows, such as a badge)
--   header   false: no header row, the list starts at `top` (a feed whose columns need no labels)
-- Returns tbl with
--   tbl.setRows(items, fill)   one row per item; fill(row, item, i) sets the texts (row.c[key]:SetText) and colors.
--                              The texts are cleared and their colors reset before every fill. An item with
--                              `ebSection` (text; `ebIndent` px, `ebColor`) is a section row: its text across the
--                              row in the label color, no hover, no click, fill not called. tbl.sections() lists
--                              the section texts showing.
--   tbl.setEmpty(text)         hides the header and the rows and shows `text` centred, wrapping; nil hides it
--   tbl.setSort(key, asc)      moves the arrow (onSort is not called)
--   tbl.relayout(w)            lays the columns out for a list `w` px wide (runs on every resize by itself) and
--                              places the rows showing (tbl.shownN); a pooled row is placed again when reused
--   tbl.cols[key] = { x, w }   the laid-out columns; tbl.sf, tbl.child, tbl.header, tbl.rows (the pool), tbl.empty
-- The column model's arithmetic, shared by UI.Table and by the views that place their own texts (UI.Columns): fixed
-- columns take widthOf(col), flex columns share what is left by weight (the last one takes the rounding), `gap` px
-- between columns and `inset` px before the first. Returns { [key] = { x, w } }.
-- A flex column never gets less than its minimum (its `min`, its header label and its `measure` values): a column
-- whose share would fall under it is held at it and the others share what is left by weight, so the minimums are
-- kept whenever the row has room for them all. When it has not (the fixed columns grew with their values: balances
-- in the millions of gold, #49), the flex columns give way below their `min` in proportion to what each has above
-- its floor (UI.COL_FLOOR px, or its header label and `measure` values when those are wider), so the row still ends
-- at the inset and it is a name that shortens, never a header or a number that runs past the list. Only when every
-- flex column is at its floor can a row still be wider than `w`.
UI.COL_FLOOR = 48
function UI.LayoutColumns(spec, w, widthOf, gap, inset)
  local cols, fixed, n = {}, 0, #spec
  local flexCols = {}
  for _, col in ipairs(spec) do if col.flex then flexCols[#flexCols + 1] = col else fixed = fixed + widthOf(col) end end
  local free = w - 2 * inset - gap * math.max(0, n - 1) - fixed
  local function minOf(col) return math.max(col.min or 40, col.headMin or 0) end
  -- hold at their minimum the columns whose share is under it, until the shares of the rest all clear theirs
  local held, widths = {}, {}
  for _ = 1, #flexCols + 1 do
    local left, sum = free, 0
    for _, col in ipairs(flexCols) do if held[col] then left = left - minOf(col) else sum = sum + col.flex end end
    local again = false
    for _, col in ipairs(flexCols) do
      if not held[col] and sum > 0 and left * col.flex / sum < minOf(col) then held[col] = true; again = true end
    end
    if not again then
      for _, col in ipairs(flexCols) do
        widths[col] = held[col] and minOf(col) or math.max(minOf(col), math.floor(left * col.flex / sum))
      end
      break
    end
  end
  -- the last flex column that is not held takes the rounding, so the row ends at the inset
  local last
  for _, col in ipairs(flexCols) do if not held[col] then last = col end end
  if last then
    local used = 0
    for _, col in ipairs(flexCols) do if col ~= last then used = used + (widths[col] or minOf(col)) end end
    widths[last] = math.max(minOf(last), free - used)
  end
  local over = -free
  for _, col in ipairs(flexCols) do over = over + (widths[col] or minOf(col)) end
  if over > 0 then
    local function floorOf(col) return math.min(minOf(col), math.max(UI.COL_FLOOR, col.headMin or 0)) end
    local slack = 0
    for _, col in ipairs(flexCols) do widths[col] = widths[col] or minOf(col); slack = slack + math.max(0, widths[col] - floorOf(col)) end
    local take = math.min(over, slack)
    local left = take
    for _, col in ipairs(flexCols) do
      local cut = math.floor(take * math.max(0, widths[col] - floorOf(col)) / math.max(1, slack))
      widths[col] = widths[col] - cut; left = left - cut
    end
    -- the rounding, a pixel at a time from the columns that still have some to give
    for _, col in ipairs(flexCols) do
      local cut = math.min(left, math.max(0, widths[col] - floorOf(col)))
      widths[col] = widths[col] - cut; left = left - cut
    end
  end
  local x = inset
  for _, col in ipairs(spec) do
    local cw
    if col.flex then cw = widths[col] or minOf(col) else cw = widthOf(col) end
    cols[col.key] = { x = x, w = cw }
    x = x + cw + gap
  end
  return cols
end
-- Columns for a view that places its own texts (a detail page): the spec of UI.Table (key, min, flex, measure, font)
-- laid out for content `w` px wide. A fixed column is as wide as the widest of `min` and its `measure` values in its
-- font. opts: gap (UI.SP.M), inset (0).
local colProbe
function UI.Columns(spec, w, opts)
  opts = opts or {}
  if not colProbe then colProbe = UI.FS(UIParent, "GameFontHighlightSmall"); colProbe:Hide() end
  local function widthOf(col)
    local cw = col.min or 0
    local m = col.measure
    if type(m) == "function" then local ok, r = pcall(m); m = ok and r or nil end
    if type(m) == "table" then
      local f = UI.Font(col.font or "GameFontHighlightSmall")
      if f then colProbe:SetFontObject(f) end
      for _, v in ipairs(m) do
        colProbe:SetText(tostring(v))
        local sw = colProbe:GetStringWidth()
        if type(sw) == "number" then cw = math.max(cw, sw) end
      end
    end
    return math.ceil(cw)
  end
  return UI.LayoutColumns(spec, tonumber(w) or 0, widthOf, opts.gap or UI.SP.M, opts.inset or 0)
end

local ARROW = "Interface\\Buttons\\UI-SortArrow"
local function isNumeric(kind) return kind == "num" or kind == "money" end
function UI.Table(parent, spec, opts)
  opts = opts or {}
  local SP = UI.SP
  local rowH = opts.rowHeight or UI.ROW_H
  local gap, inset = opts.gap or SP.M, opts.inset or SP.S
  local iconSize = opts.iconSize or 16
  local top, bottom = opts.top or 0, opts.bottom or 0
  local left, right = opts.left or 0, opts.right or 0
  local tbl = { spec = spec, cols = {}, rows = {}, head = {}, sortKey = opts.sortKey, sortAsc = opts.sortAsc,
    onLayout = opts.onLayout }

  -- header: as wide as the list below it, so both start their columns at the same x
  local header = CreateFrame("Frame", nil, parent)
  header:SetPoint("TOPLEFT", parent, "TOPLEFT", left, top)
  header:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -(right + UI.SCROLLBAR), top)
  header:SetHeight(rowH)
  local rule = header:CreateTexture(nil, "ARTWORK")
  rule:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0); rule:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0); rule:SetHeight(1)
  rule:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
  tbl.header, tbl.rule = header, rule
  local noHead = opts.header == false   -- a list without a header row: the rows start at `top`
  if noHead then header:Hide() end
  local probe = UI.FS(header, "GameFontHighlightSmall"); probe:Hide()
  local function textW(template, s)
    local f = UI.Font(template)
    if f then probe:SetFontObject(f) end
    probe:SetText(s or "")
    local w = probe:GetStringWidth()
    return type(w) == "number" and w or 0
  end

  local sf, child = UI.ScrollChild(parent, { top = noHead and top or (top - rowH - 1), bottom = bottom, left = left, right = right })
  tbl.sf, tbl.child = sf, child
  sf.ebTable = tbl   -- a list's table, for readers that start from its scroll frame (the pane tests)

  local base, shown = {}, {}       -- measured fixed widths; widest value shown per num/money/tag column
  for _, col in ipairs(spec) do
    col.justify = col.justify or (isNumeric(col.kind) and "RIGHT" or "LEFT")
    if col.kind == "icon" then
      local hb = CreateFrame("Frame", nil, header); hb:SetHeight(rowH); tbl.head[col.key] = hb
    else
      local hb = CreateFrame("Button", nil, header); hb:SetHeight(rowH)
      local fs = UI.CellFS(header, "GameFontNormalSmall", C.dim)
      fs:SetJustifyH(col.justify); fs:SetText((col.label or ""):upper())
      hb.fs, hb.key = fs, col.key
      if col.sort then
        local ar = header:CreateTexture(nil, "OVERLAY"); ar:SetSize(9, 8); ar:SetTexture(ARROW); ar:Hide()
        hb.arrow = ar
        hb:SetScript("OnClick", function(b)
          local asc
          if tbl.sortKey == b.key then asc = not tbl.sortAsc else asc = (col.kind == nil or col.kind == "text") end
          tbl.setSort(b.key, asc)
          if opts.onSort then opts.onSort(b.key, asc) end
        end)
      end
      tbl.head[col.key] = hb
    end
  end
  local function measureBase()
    for _, col in ipairs(spec) do
      if col.kind == "icon" then base[col.key] = math.max(col.min or 0, iconSize)
      elseif col.flex then
        -- a flex column's minimum: its header label, and the realistic values it must show in full (`measure`)
        local mn = textW("GameFontNormalSmall", (col.label or ""):upper()) + (col.sort and 13 or 0)
        local m = col.measure
        if type(m) == "function" then local ok, r = pcall(m); m = ok and r or nil end
        if type(m) == "table" then for _, v in ipairs(m) do mn = math.max(mn, textW(col.font or "GameFontHighlightSmall", tostring(v))) end end
        col.headMin = math.ceil(mn)
      else
        local w = math.max(col.min or 0, textW("GameFontNormalSmall", (col.label or ""):upper()) + (col.sort and 13 or 0))
        local m = col.measure
        if type(m) == "function" then local ok, r = pcall(m); m = ok and r or nil end
        if type(m) == "table" then for _, v in ipairs(m) do w = math.max(w, textW(col.font or "GameFontHighlightSmall", tostring(v))) end end
        base[col.key] = math.ceil(w)
      end
    end
  end
  measureBase()

  local function widthOf(col) return math.max(base[col.key] or 0, shown[col.key] or 0) end
  local function placeCell(cell, x, w)
    cell:ClearAllPoints(); cell:SetPoint("LEFT", cell.ebRow or header, "LEFT", x, 0); cell:SetWidth(w)
  end
  -- tbl.gen counts the layouts: a row placed for the current one has row.ebGen == tbl.gen
  tbl.gen, tbl.shownN = 0, 0
  local function placeRow(row)
    row.ebGen = tbl.gen
    for _, col in ipairs(spec) do
      local cw = tbl.cols[col.key]
      local cell = row.c[col.key]
      if col.kind == "icon" then
        cell:ClearAllPoints(); cell:SetPoint("LEFT", row, "LEFT", cw.x, 0); cell:SetSize(iconSize, iconSize)
      else placeCell(cell, cw.x, cw.w) end
    end
  end
  function tbl.relayout(w)
    w = tonumber(w) or 0
    if w <= 1 then return end
    tbl.width = w
    tbl.gen = tbl.gen + 1
    tbl.cols = UI.LayoutColumns(spec, w, widthOf, gap, inset)
    for _, col in ipairs(spec) do
      local cw, hb = tbl.cols[col.key], tbl.head[col.key]
      hb:ClearAllPoints(); hb:SetPoint("LEFT", header, "LEFT", cw.x, 0); hb:SetWidth(cw.w)
      if hb.fs then placeCell(hb.fs, cw.x, cw.w) end
    end
    tbl.setSort(tbl.sortKey, tbl.sortAsc)
    -- only the rows showing; a pooled row hidden now is placed when setRows uses it again
    for i = 1, tbl.shownN do placeRow(tbl.rows[i]) end
    if tbl.onLayout then pcall(tbl.onLayout, tbl) end
  end
  function tbl.setSort(key, asc)
    tbl.sortKey, tbl.sortAsc = key, asc and true or false
    for _, col in ipairs(spec) do
      local hb, cw = tbl.head[col.key], tbl.cols[col.key]
      if hb.fs then
        local on = col.sort and col.key == key
        hb.fs:SetTextColor(unpackc(on and C.ink or C.dim))
        if hb.arrow then
          if on and cw then
            local lw = math.min(cw.w - 13, math.ceil(hb.fs:GetStringWidth() or 0))
            hb.arrow:ClearAllPoints()
            if col.justify == "RIGHT" then hb.arrow:SetPoint("RIGHT", header, "LEFT", cw.x + cw.w - lw - SP.XS, 0)
            else hb.arrow:SetPoint("LEFT", header, "LEFT", cw.x + lw + SP.XS, 0) end
            -- the texture points down; flipped for ascending
            if asc then hb.arrow:SetTexCoord(0, 0.5625, 1, 0) else hb.arrow:SetTexCoord(0, 0.5625, 0, 1) end
            hb.arrow:SetVertexColor(unpackc(C.ink)); hb.arrow:Show()
          else hb.arrow:Hide() end
        end
      end
    end
  end

  -- rows: Buttons across the full width of the list, a hover highlight, the row's tooltip on the name cell
  local nameKey
  for _, col in ipairs(spec) do if col.flex and not nameKey then nameKey = col.key end end
  local function onEnter(row)
    if not opts.tooltip or not GameTooltip then return end
    GameTooltip:SetOwner(row, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    GameTooltip:SetPoint("BOTTOMLEFT", (nameKey and row.c[nameKey]) or row, "TOPLEFT", -SP.XS, SP.XS)
    local ok = pcall(opts.tooltip, row, row.item, GameTooltip)
    if ok then UI.AddCellLines(row) end
    GameTooltip:Show()
    row.ebOwnTip = true
  end
  local function onLeave(row) if row.ebOwnTip and GameTooltip then GameTooltip:Hide() end; row.ebOwnTip = nil end
  local function newRow()
    local row = CreateFrame("Button", nil, child)
    row:SetHeight(rowH)
    local hl = row:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(row); hl:SetColorTexture(C.hover[1], C.hover[2], C.hover[3], 0.7)
    row.highlight = hl
    row.c = {}
    if opts.tooltip then row:SetScript("OnEnter", onEnter); row:SetScript("OnLeave", onLeave) end
    if opts.onClick then
      -- a left click by default (as a plain Button); a table that handles the right button asks with opts.rightClick
      if row.RegisterForClicks then
        if opts.rightClick then row:RegisterForClicks("LeftButtonUp", "RightButtonUp") else row:RegisterForClicks("LeftButtonUp") end
      end
      row:SetScript("OnClick", function(r, button) pcall(opts.onClick, r, r.item, button) end)
    end
    for _, col in ipairs(spec) do
      if col.kind == "icon" then
        local tx = row:CreateTexture(nil, "ARTWORK"); tx:SetSize(iconSize, iconSize)
        tx:SetTexCoord(0.08, 0.92, 0.08, 0.92)    -- crop the icon's built-in border
        row.c[col.key] = tx
      else
        local fs = UI.CellFS(row, col.font or "GameFontHighlightSmall")
        fs:SetJustifyH(col.justify); fs.ebRow = row
        row.c[col.key] = fs
      end
    end
    if tbl.width then placeRow(row) end
    return row
  end

  local empty = UI.FS(parent, "GameFontDisableSmall", C.dim)
  empty:SetPoint("LEFT", sf, "LEFT", SP.L, 0); empty:SetPoint("RIGHT", sf, "RIGHT", -SP.L, 0)
  empty:SetJustifyH("CENTER"); if empty.SetWordWrap then empty:SetWordWrap(true) end
  empty:Hide()
  tbl.empty = empty
  function tbl.setEmpty(text)
    if text then
      tbl.shownN = 0
      for _, row in ipairs(tbl.rows) do row:Hide() end
      header:Hide(); empty:SetText(text); empty:Show(); sf:SetContentHeight(1)
    else empty:Hide(); if not noHead then header:Show() end end
  end

  function tbl.setRows(items, fill)
    items = items or {}
    -- the fixed widths are measured again here, not on every resize: a text measured before its font file has
    -- loaded (a table built early) is off, and by the first fill the fonts are in
    local before = {}
    for k, v in pairs(base) do before[k] = v end
    pcall(measureBase)
    local changed = false
    for k, v in pairs(base) do if before[k] ~= v then changed = true end end
    if #items == 0 and opts.emptyText then tbl.shownN = 0; tbl.setEmpty(opts.emptyText); return end
    tbl.setEmpty(nil)
    tbl.shownN = #items
    for i, item in ipairs(items) do
      local row = tbl.rows[i]
      if not row then row = newRow(); tbl.rows[i] = row
      elseif tbl.width and row.ebGen ~= tbl.gen then placeRow(row) end
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(i - 1) * rowH)
      row:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, -(i - 1) * rowH)
      row.item, row.index = item, i
      for _, col in ipairs(spec) do
        local cell = row.c[col.key]
        if col.kind == "icon" then cell:SetTexture(nil)
        else cell:SetText(""); cell:SetTextColor(unpackc(C[col.color or "ink"] or C.ink)) end
      end
      if item.ebSection then
        -- a section row (a day, a run): one line of text across the row, not a hover or click target
        if not row.section then
          local sfs = UI.FS(row, "GameFontNormalSmall", C.gold)
          if sfs.SetWordWrap then sfs:SetWordWrap(false) end
          if sfs.SetMaxLines then sfs:SetMaxLines(1) end
          sfs:SetJustifyH("LEFT")
          row.section = sfs
        end
        local sfs = row.section
        sfs:ClearAllPoints()
        sfs:SetPoint("LEFT", row, "LEFT", inset + (tonumber(item.ebIndent) or 0), 0); sfs:SetPoint("RIGHT", row, "RIGHT", -inset, 0)
        sfs:SetText(item.ebSection); sfs:SetTextColor(unpackc(item.ebColor or C.gold)); sfs:Show()
        if row.EnableMouse then row:EnableMouse(false) end
      else
        if row.section then row.section:Hide() end
        if row.EnableMouse then row:EnableMouse(true) end
        if fill then fill(row, item, i) end
      end
      row:Show()
    end
    for j = #items + 1, #tbl.rows do tbl.rows[j]:Hide() end
    sf:SetContentHeight(#items * rowH)
    -- numbers and tags never shorten: their columns take the widest value shown
    for _, col in ipairs(spec) do
      if not col.flex and col.kind ~= "icon" and col.kind ~= "text" and col.kind ~= nil then
        local wmax = 0
        for i = 1, #items do
          local fs = tbl.rows[i].c[col.key]
          local t = fs:GetText()
          if t and t ~= "" then local sw = fs:GetStringWidth(); if type(sw) == "number" then wmax = math.max(wmax, sw) end end
        end
        wmax = math.ceil(wmax)
        if wmax ~= (shown[col.key] or 0) then shown[col.key] = wmax; changed = true end
      end
    end
    if tbl.width and changed then tbl.relayout(tbl.width) end
  end

  -- the section texts showing now (a day or run header), top to bottom
  function tbl.sections()
    local out = {}
    for _, row in ipairs(tbl.rows) do
      if row:IsShown() and row.section and row.section:IsShown() and row.item and row.item.ebSection then out[#out + 1] = row.section end
    end
    return out
  end

  sf.onResize = function(w) tbl.relayout(w) end
  tbl.relayout(sf:GetWidth() or 0)
  return tbl
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
  f:SetSize(UI.clampWinSize(ws and ws.w, ws and ws.h))
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
  if f.SetResizeBounds then f:SetResizeBounds(UI.WIN_MIN_W, UI.WIN_MIN_H, UI.WIN_MAX_W, UI.WIN_MAX_H)
  elseif f.SetMinResize then f:SetMinResize(UI.WIN_MIN_W, UI.WIN_MIN_H); if f.SetMaxResize then f:SetMaxResize(UI.WIN_MAX_W, UI.WIN_MAX_H) end end
  local grip = CreateFrame("Button", nil, f)
  grip:SetSize(16, 16); grip:SetPoint("BOTTOMRIGHT", -8, 8)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:SetScript("OnMouseDown", function() UI.sizing = true; f:StartSizing("BOTTOMRIGHT") end)
  grip:SetScript("OnMouseUp", function()
    f:StopMovingOrSizing()
    UI.sizing = nil
    UI.SetWindowSize(f:GetWidth(), f:GetHeight())
    pcall(UI.FlushResizes)   -- the lists held during the drag take the final width now
  end)
  f.grip = grip

  -- title bar
  local bar = CreateFrame("Frame", nil, f)
  bar:SetPoint("TOPLEFT", 12, -12); bar:SetPoint("TOPRIGHT", -12, -12); bar:SetHeight(40)
  local barBg = bar:CreateTexture(nil, "BACKGROUND"); barBg:SetAllPoints(); barBg:SetColorTexture(C.sunken[1], C.sunken[2], C.sunken[3], 1)   -- n0, the desktop top bar
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
  -- one line across the host, whatever the window's width; a longer subtitle shortens with "..."
  local sub = UI.FS(content, "GameFontHighlightSmall", C.dim)
  if sub.SetWordWrap then sub:SetWordWrap(false) end
  if sub.SetMaxLines then sub:SetMaxLines(1) end
  sub:SetPoint("TOPLEFT", content, "TOPLEFT", 14, -38); sub:SetPoint("TOPRIGHT", content, "TOPRIGHT", -14, -38); sub:SetJustifyH("LEFT")
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

-- a window size inside the designed bounds (900x580 to 1600x1000); a missing or broken value is the minimum
function UI.clampWinSize(w, h)
  w, h = tonumber(w), tonumber(h)
  if not w or w ~= w then w = UI.WIN_MIN_W end
  if not h or h ~= h then h = UI.WIN_MIN_H end
  return math.min(UI.WIN_MAX_W, math.max(UI.WIN_MIN_W, math.floor(w))), math.min(UI.WIN_MAX_H, math.max(UI.WIN_MIN_H, math.floor(h)))
end
-- persist + apply a window size (used by the resize grip; clamped to the designed bounds)
function UI.SetWindowSize(w, h)
  w, h = UI.clampWinSize(w, h)
  if ns.DB and ns.DB.settings then ns.DB.settings.winSize = { w = w, h = h } end
  if frame then frame:SetSize(w, h) end
end

-- Open the window on a tab; `sub` selects a pane of a host tab ("Combat", "fights").

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
  -- the two help lines, then the gold block (Gold.tooltip, Economy.lua: balance, today, the characters; off with
  -- settings.gold.tips = false). Nothing is drawn until the hover; while it is open it follows the purse.
  local function tip(btn)
    GameTooltip:SetOwner(btn, "ANCHOR_LEFT")
    GameTooltip:AddLine("everbuff.gg")
    GameTooltip:AddLine("Left-click: open   Right-click: settings   Drag: move", 0.7, 0.7, 0.7)
    -- (the owner and the redraw: while the button owns the tooltip the block follows the purse and the rate)
    if ns.Gold and ns.Gold.tooltip then pcall(ns.Gold.tooltip, GameTooltip, { owner = btn, redo = tip }) end
    GameTooltip:Show()
  end
  b:SetScript("OnEnter", tip)
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
