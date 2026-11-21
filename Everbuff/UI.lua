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
  -- the role keys of the design system (docs/UX_OVERHAUL.md 2.5); the keys above are their aliases until phase 2
  canvas = T["bg-canvas"], raised = T["bg-raised"],
  lineStrong = T["line-strong"], lineControl = T["line-control"],
  fg = T["fg"], fgSubtle = T["fg-subtle"], fgMuted = T["fg-muted"], fgFaint = T["fg-faint"],
  accent = T["accent"], accentTint = T["accent-tint-n2"], accentHover = T["accent-hover"], onAccent = T["on-accent"],
  good = T["success-fg"], warn = T["warning-fg"], bad = T["danger-fg"],
  goodTint = T["success-tint-n2"], warnTint = T["warning-tint-n2"], badTint = T["danger-tint-n2"],
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
  if shadow then f:SetShadowColor(0, 0, 0, type(shadow) == "number" and shadow or 0.9); f:SetShadowOffset(1, -1) end
  if f then f.ebFile, f.ebSize = file, size end
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

-- ══ design system (docs/UX_OVERHAUL.md section 2) ════════════════════════════════════════════════════════════
-- Converted pages use these constants and the kit below only: no literal offsets, no literal colors, no Blizzard
-- templates. Everything is in window units at scale 1.0.
local SPACE = ns.Theme.space
UI.S = { S1 = SPACE[1], S2 = SPACE[2], S3 = SPACE[3], S4 = SPACE[4], S5 = SPACE[5], S6 = SPACE[6], S7 = SPACE[7] }
local S = UI.S
-- the window grid (2.2). Edges that follow the window size are functions of its width or height.
UI.G = {
  WIN_MIN_W = 900, WIN_MIN_H = 580, WIN_MAX_W = 1600, WIN_MAX_H = 1000,
  BORDER = 1, TITLE_H = 40, SIDEBAR_W = 168,
  BOX_L = 192, TEXT_L = 192 + S.S3,          -- every content box starts at BOX_L, every content text at TEXT_L
  BOX_R_INSET = S.S5, TEXT_R_INSET = S.S5 + S.S3,   -- BOX_R = W - 24, TEXT_R = W - 36
  CTRL_Y = 52, CTRL_H = 28, CONTENT_TOP = 52 + 28 + S.S3, BOTTOM = S.S4,
  RAIL_W = 336, MAIN_MAX = 1024, TABLE_MAX = 1024,
  NAV_X = 8, NAV_W = 152, NAV_TOP = 48, NAV_ICON_X = S.S4, NAV_LABEL_X = 44,
  CLOSE = 24, CHIP_RIGHT = 56,
}
local G = UI.G
function G.boxR(w) return w - G.BOX_R_INSET end
function G.textR(w) return w - G.TEXT_R_INSET end
function G.cw(w) return w - G.BOX_L - G.BOX_R_INSET end            -- 684 at 900
function G.ch(h) return h - G.CONTENT_TOP - G.BOTTOM end           -- 472 at 580
function G.contentBottom(h) return h - G.BOTTOM end
function G.isWide(w) return G.cw(w) >= 684 + S.S5 + G.RAIL_W end    -- a window 1260 px wide or more
function G.mainW(w)
  local cw = G.cw(w)
  if G.isWide(w) then return math.min(cw - G.RAIL_W - S.S5, G.MAIN_MAX) end
  return math.min(cw, G.MAIN_MAX)      -- no rail (tranche 1): left-aligned, never wider than MAIN_MAX
end
-- the window's width now (its minimum before it is built)
function G.winW()
  local f = _G.EverbuffFrame
  local w = f and f.GetWidth and tonumber(f:GetWidth())
  return (w and w > 1) and w or G.WIN_MIN_W
end
-- row heights (2.3)
UI.H = { CONTROL = 24, TABLE_HEAD = 24, DAY_ROW = 24, SECTION = 24, SUMMARY = 24, ROW = 32, SETTING = 32, SETTING_DESC = 48,
  NOTICE = 40, ROW2 = 48, STAT = 80, HERO = 104, NAV = 36, BIG_BUTTON = 28 }

-- the type scale (2.4): one font object per role, a 1,-1 black shadow at 0.85 (1.0 on HERO, DISPLAY and TITLE)
UI.F = {
  WORDMARK    = mkfont("EverbuffWordmark",   FONT_DIR .. "ChakraPetch-SemiBold.ttf", 15, "", C.fg, 0.85),
  HERO        = mkfont("EverbuffHero",       FONT_DIR .. "ChakraPetch-Bold.ttf", 24, "", C.fg, 1),
  DISPLAY     = mkfont("EverbuffDisplay",    FONT_DIR .. "ChakraPetch-Bold.ttf", 20, "", C.fg, 1),
  TITLE       = mkfont("EverbuffTitle",      FONT_DIR .. "Inter-SemiBold.ttf", 15, "", C.fg, 1),
  ROW_TITLE   = mkfont("EverbuffRowTitle",   FONT_DIR .. "Inter-SemiBold.ttf", 13, "", C.fg, 0.85),
  BODY        = mkfont("EverbuffBody",       FONT_DIR .. "Inter-Medium.ttf", 12, "", C.fg, 0.85),
  BODY_STRONG = mkfont("EverbuffBodyStrong", FONT_DIR .. "Inter-SemiBold.ttf", 12, "", C.fg, 0.85),
  META        = mkfont("EverbuffMeta",       FONT_DIR .. "Inter-Medium.ttf", 11, "", C.fgMuted, 0.85),
  LABEL       = mkfont("EverbuffLabel",      FONT_DIR .. "Inter-SemiBold.ttf", 10, "", C.fgMuted, 0.85),
  BADGE       = mkfont("EverbuffBadge",      FONT_DIR .. "Inter-SemiBold.ttf", 9, "", C.fg, 0.85),
}
-- line heights per role (measured: the TTF ascent and descent at that size, tests/fontmetrics.lua)
UI.LINE_H = { WORDMARK = 19, HERO = 30, DISPLAY = 25, TITLE = 19, ROW_TITLE = 16, BODY = 15, BODY_STRONG = 15, META = 14, LABEL = 13, BADGE = 11 }
-- the roles whose text is drawn in capitals (the font cannot do it: the kit upper-cases the text)
UI.UPPER = { LABEL = true, BADGE = true }
UI.SCALE_MIN = 0.9

-- A font string in a role of the type scale. `color` is a key of UI.C or an { r, g, b }. One line by default;
-- opts.wrap lets it wrap. fs:SetText runs through the role's case rule when the kit sets it (UI.SetText).
function UI.Text(parent, role, color, opts)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  local fo = UI.F[role] or UI.F.BODY
  if fo then fs:SetFontObject(fo) end
  fs.ebRole = role
  if fo then fs.ebFile, fs.ebSize = fo.ebFile, fo.ebSize end
  local c = type(color) == "string" and C[color] or color
  if c then fs:SetTextColor(unpackc(c)) end
  if not (opts and opts.wrap) then
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    if fs.SetMaxLines then fs:SetMaxLines(1) end
  elseif fs.SetSpacing and fo and fo.ebSize and UI.LINE_H[role] then
    -- wrapped lines sit at the role's line height (BODY 15, META 14), the pitch every layout reserves per line
    fs:SetSpacing(math.max(0, UI.LINE_H[role] - fo.ebSize))
  end
  fs:SetJustifyH((opts and opts.justify) or "LEFT")
  return fs
end
-- capitals, with the escapes left as they are (a money icon's "|T...|t", a colour's "|c...", "|r", a link's "|H...|h")
function UI.upper(text)
  local esc = {}
  local function keep(m) esc[#esc + 1] = m; return "\001" .. #esc .. "\002" end
  local t = tostring(text):gsub("|T.-|t", keep):gsub("|H.-|h", keep):gsub("|c%x%x%x%x%x%x%x%x", keep):gsub("|r", keep)
  t = t:upper():gsub("\001(%d+)\002", function(i) return esc[tonumber(i)] end)
  return t
end
-- set the text of a kit font string, upper-cased when its role is drawn in capitals
function UI.SetText(fs, text)
  text = text == nil and "" or tostring(text)
  if fs.ebRole and UI.UPPER[fs.ebRole] then text = UI.upper(text) end
  fs:SetText(text)
  return fs
end
function UI.SetColor(region, color, a)
  local c = type(color) == "string" and C[color] or color
  if not c then return end
  if region.SetTextColor and region.ebRole ~= nil then region:SetTextColor(unpackc(c, a))
  elseif region.SetColorTexture then region:SetColorTexture(unpackc(c, a))
  elseif region.SetTextColor then region:SetTextColor(unpackc(c, a)) end
end
-- A name that does not fit steps down 1 px at a time to `min` (default 10); only then does the client shorten it
-- with "...". Returns the size it took.
function UI.Fit(fs, min)
  min = min or 10
  local file, size = fs.ebFile, fs.ebSize
  if not (file and size and fs.SetFont and fs.IsTruncated) then return size end
  fs:SetFont(file, size)
  local cur = size
  while cur > min and fs:IsTruncated() == true do cur = cur - 1; fs:SetFont(file, cur) end
  return cur
end

-- ── formatters (2.6): one date, duration and number dialect everywhere ────────────────────────────────────────
local function nowT() return (GetServerTime and GetServerTime()) or time() end
local function sameDay(a, b) return date("%Y-%m-%d", a) == date("%Y-%m-%d", b) end
local function dayNum(t) return tostring(tonumber(date("%d", t)) or date("%d", t)) end
function UI.fmtClock(t) return date("%H:%M", tonumber(t) or 0) end
-- "Today", "Yesterday", "Mon 16 Nov" this year, "16 Nov 2025" before it
function UI.fmtDate(t, now)
  t = tonumber(t) or 0; now = now or nowT()
  if sameDay(t, now) then return "Today" end
  if sameDay(t, now - 86400) then return "Yesterday" end
  if date("%Y", t) == date("%Y", now) then return date("%a ", t) .. dayNum(t) .. date(" %b", t) end
  return dayNum(t) .. date(" %b %Y", t)
end
-- "Today 21:35", "Yesterday 21:35", "Mon 16 Nov, 21:35", "16 Nov 2025"
function UI.fmtWhen(t, now)
  t = tonumber(t) or 0; now = now or nowT()
  local d = UI.fmtDate(t, now)
  if d == "Today" or d == "Yesterday" then return d .. " " .. UI.fmtClock(t) end
  if date("%Y", t) == date("%Y", now) then return d .. ", " .. UI.fmtClock(t) end
  return d
end
-- "Sat 21 Nov 11:45" ("21 Nov 2025 11:45" before this year): a fixed moment, such as where a stored list starts or
-- when the desktop app picked data up. Never "Today": a section header and a status row are read days later too.
function UI.fmtStamp(t, now)
  t = tonumber(t) or 0; now = now or nowT()
  if date("%Y", t) == date("%Y", now) then return date("%a ", t) .. dayNum(t) .. date(" %b ", t) .. UI.fmtClock(t) end
  return dayNum(t) .. date(" %b %Y ", t) .. UI.fmtClock(t)
end
-- day rows: "TODAY", "YESTERDAY", "MONDAY 16 NOV" ("MONDAY 16 NOV 2025" before this year)
function UI.fmtDay(t, now)
  t = tonumber(t) or 0; now = now or nowT()
  if sameDay(t, now) then return "TODAY" end
  if sameDay(t, now - 86400) then return "YESTERDAY" end
  local s = date("%A ", t) .. dayNum(t) .. date(" %b", t)
  if date("%Y", t) ~= date("%Y", now) then s = s .. date(" %Y", t) end
  return s:upper()
end
-- "45s", "10m 5s", "1h 39m", "2d 4h"; never mm:ss. opts.minutes: to the minute ("38m"), as a played time
function UI.fmtDur(s, opts)
  s = tonumber(s)
  if not s or s ~= s then return "-" end
  s = math.max(0, math.floor(s + 0.5))
  if opts and opts.minutes and s >= 60 then s = math.floor(s / 60 + 0.5) * 60 end
  if s < 60 then return s .. "s" end
  if s < 3600 then
    local m, r = math.floor(s / 60), s % 60
    return r > 0 and (m .. "m " .. r .. "s") or (m .. "m")
  end
  -- (a zero second unit is dropped at every size: "2m", "1h", "2d", never "1h 0m")
  if s < 86400 then local h, m = math.floor(s / 3600), math.floor((s % 3600) / 60); return m > 0 and (h .. "h " .. m .. "m") or (h .. "h") end
  local d, h = math.floor(s / 86400), math.floor((s % 86400) / 3600)
  return h > 0 and (d .. "d " .. h .. "h") or (d .. "d")
end
-- a session's length (and any time played), one function and one rounding everywhere: to the nearest minute ("38m",
-- "1h 39m"); under half a minute it is "-" (nothing to say). UI.sessionSecs(sess) is the length of a session record,
-- up to now while it runs.
function UI.fmtPlayed(s)
  s = tonumber(s)
  if not s or s ~= s or s < 30 then return "-" end
  return UI.fmtDur(s, { minutes = true })
end
function UI.sessionSecs(sess, now)
  if type(sess) ~= "table" then return 0 end
  local a = tonumber(sess.startedEpoch)
  if not a then return 0 end
  local b = tonumber(sess.endedEpoch) or now or nowT()
  return math.max(0, b - a)
end
-- a time against the best: returns the words and the color key ("good", "warn" or nil).
--   UI.fmtDelta(-42) -> "42s faster", "good"; UI.fmtDelta(209) -> "3m 29s slower", "warn"
--   opts.best (this run is the best) -> "best"; opts.first (nothing to compare) -> "first run"; |d| < 0.5 -> "same as best"
function UI.fmtDelta(d, opts)
  if opts and opts.first then return "first run", nil end
  if opts and opts.best then return "best", nil end
  d = tonumber(d)
  if not d then return "first run", nil end
  if math.abs(d) < 0.5 then return "same as best", nil end
  if d < 0 then return UI.fmtDur(-d) .. " faster", "good" end
  return UI.fmtDur(d) .. " slower", "warn"
end
local function groupDigits(n)
  local s = tostring(n)
  local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  return (out:gsub("^,", ""))
end
-- "116,310"; a fraction is rounded, a hidden or broken value is "-"
function UI.fmtNum(n)
  n = tonumber(n)
  if not n or n ~= n or n == math.huge or n == -math.huge then return "-" end
  local neg = n < 0
  n = math.floor(math.abs(n) + 0.5)
  return (neg and "-" or "") .. groupDigits(n)
end
-- "21:35 to 22:13"; live: "21:35 to now"
function UI.fmtRange(a, b, live)
  return UI.fmtClock(a) .. " to " .. ((live or not b) and "now" or UI.fmtClock(b))
end
-- the TYPE word of every story event kind, sentence case, one table for Activity and every list that names a kind
-- (docs/UX_OVERHAUL.md 4.2). tests/panes/columns.lua checks that every kind the addon writes has one.
UI.KIND_LABEL = {
  LEVELUP = "Level", ZONE = "Zone", FIRSTZONE = "New zone", DISCOVERY = "Discovery", FLIGHT = "Flight path", FLIGHTTRIP = "Flight",
  DUNGEON = "Dungeon", DUNGEONLEAVE = "Dungeon", QUESTACCEPT = "Quest", QUESTDONE = "Quest", REWARD = "Reward",
  BOSS = "Boss", KILL = "Kill", WIPE = "Wipe", DEATH = "Died", ALIVE = "Revived", ROSTERJOIN = "Party", ROSTERLEAVE = "Party",
  LOOT = "Loot", COLLECT = "Collected", UPGRADE = "Gear", BROKEN = "Gear", GOLDAWAY = "Gold",
  SKILLUP = "Skill", RECIPE = "Recipe", PROFTIER = "Profession", ACHIEV = "Achievement", SPELL = "Learned", REP = "Reputation",
  VENDOR = "Merchant", TRAINER = "Trainer", MAIL = "Mail", AUCTION = "Auction", TRADE = "Trade", BANK = "Bank",
}
-- the event results that carry a colour (2.5 rule 3): a kill is good, a wipe and a death are bad
UI.KIND_RESULT = { KILL = "good", WIPE = "bad", DEATH = "bad" }
local PLURAL = { entry = "entries", faction = "factions", copy = "copies", party = "parties", ["party member"] = "party members" }
-- "1 item", "2 items", "3 entries"
function UI.plural(n, word, many)
  n = tonumber(n) or 0
  local w = word
  if n ~= 1 then
    w = many or PLURAL[word] or (word:match("[^aeiou]y$") and (word:sub(1, -2) .. "ies")) or (word:match("[sxz]$") or word:match("[cs]h$")) and (word .. "es") or (word .. "s")
  end
  return UI.fmtNum(n) .. " " .. w
end

-- ── glyphs (2.4): the bundled fonts lack ▾ ✕ ⓘ →; these draw them from WHITE8x8 squares ────────────────────────
local WHITE = "Interface\\Buttons\\WHITE8x8"
UI.WHITE = WHITE
-- the squares of each glyph at `s` px: { x, y, w, h } from the glyph's top left
local function glyphRects(name, s)
  local out = {}
  local function add(x, y, w, h) out[#out + 1] = { math.floor(x), math.floor(y), math.max(1, math.floor(w)), math.max(1, math.floor(h)) } end
  local t = s >= 8 and 2 or 1          -- stroke
  if name == "dot" then
    local e = math.max(1, math.floor(s / 6))
    add(e, 0, s - 2 * e, s); add(0, e, s, s - 2 * e)
  elseif name == "chevronDown" or name == "chevronUp" then
    local hgt = math.floor(s / 2)
    local y0 = math.floor((s - hgt) / 2)
    for i = 0, hgt - 1 do
      local y = name == "chevronDown" and (y0 + i) or (y0 + hgt - 1 - i)
      add(i, y, t, t); add(s - t - i, y, t, t)
    end
  elseif name == "clear" then
    for i = 0, s - t do add(i, i, t, t); add(s - t - i, i, t, t) end
  elseif name == "check" then
    local k = math.floor(s * 0.35)
    for i = 0, k do add(i, math.floor(s * 0.5) + i - t, t, t) end
    for i = 0, s - k - t do add(k + i, math.floor(s * 0.5) + k - i - t, t, t) end
  elseif name == "info" then
    local cx = math.floor((s - t) / 2)
    add(cx, 0, t, t); add(cx, t + 1, t, s - t - 1)
  elseif name == "search" then
    local r = math.floor(s * 0.7)
    add(0, 0, r, 1); add(0, r - 1, r, 1); add(0, 0, 1, r); add(r - 1, 0, 1, r)
    for i = 0, s - r - 1 do add(r - 1 + i, r - 1 + i, t, t) end
  end
  return out
end
UI.GLYPHS = { dot = true, chevronDown = true, chevronUp = true, clear = true, check = true, info = true, search = true }
-- UI.Glyph(parent, name, size, color): a size x size frame drawing the glyph; g:SetColor(color) recolors it
function UI.Glyph(parent, name, size, color)
  size = size or 8
  local g = CreateFrame("Frame", nil, parent)
  g:SetSize(size, size)
  g.ebGlyph, g.tex = name, {}
  for _, r in ipairs(glyphRects(name, size)) do
    local tx = g:CreateTexture(nil, "OVERLAY")
    tx:SetPoint("TOPLEFT", g, "TOPLEFT", r[1], -r[2]); tx:SetSize(r[3], r[4])
    g.tex[#g.tex + 1] = tx
  end
  function g.SetColor(_, c, a)
    c = type(c) == "string" and C[c] or c or C.fg
    for _, tx in ipairs(g.tex) do tx:SetColorTexture(unpackc(c, a)) end
    g.ebColor = c
  end
  g:SetColor(color or "fg")
  return g
end
-- the dot scales with the text it leads: 6 px for BODY and META, 8 for DISPLAY, 10 for HERO (2.5 accent rule 3)
UI.DOT_SIZE = { HERO = 10, DISPLAY = 8, BODY = 6, META = 6 }
-- the 6 px state dot as an inline texture, for a text that carries a warn or bad state ("|T...|t " before it)
function UI.dot(color, size)
  local c = type(color) == "string" and C[color] or color or C.fg
  size = size or 6
  return ("|T%s:%d:%d:0:0:8:8:0:8:0:8:%d:%d:%d|t "):format(WHITE, size, size,
    math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end
-- a click sound for kit buttons, guarded
function UI.Click()
  if PlaySound then pcall(PlaySound, 856) end   -- 856 is SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON (no new client global)
end

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
-- the coin icons of the design system: 12 x 12, the GetCoinTextureString style
local COIN_ICON12 = {
  g = "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:0:0|t",
  s = "|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:0:0|t",
  c = "|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:0:0|t",
}
UI.COIN_ICON12 = COIN_ICON12
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
  elseif opts and opts.units then
    -- the design system's money (2.5 rule 4): at most `units` of the largest non-zero units, digits then a no-break
    -- space and the game's 12 px coin icon (or the letter), the units joined by a space
    c = round(c)
    local parts = { { math.floor(c / 10000), "g" }, { math.floor(c / 100) % 100, "s" }, { c % 100, "c" } }
    local out = {}
    for _, p in ipairs(parts) do
      if p[1] > 0 and #out < opts.units then
        local digits = p[2] == "g" and grouped(p[1]) or tostring(p[1])
        out[#out + 1] = digits .. (opts.icons and (NBSP .. COIN_ICON12[p[2]]) or p[2])
      end
    end
    if #out == 0 then out[1] = "0" .. (opts.icons and (NBSP .. COIN_ICON12.c) or "c") end
    text = table.concat(out, " ")
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
-- A short list of choices under a button, the pane's own frame (never UIDropDownMenu: it spreads taint). One per
-- pane: menu.open(anchor, items, onPick, right) with items { { key, label, selected } }; a click picks and closes, a
-- second click on the same button closes. (The Gold pane keeps its own copy, Economy.lua buildMenu.)
UI.MENU_ROWS, UI.MENU_MIN_ROWS = 15, 5
function UI.Menu(parent)
  local SP, ROW_H = UI.SP, UI.ROW_H
  local m = UI.Panel(parent)
  if m.SetFrameStrata then m:SetFrameStrata("DIALOG") end
  m.btns = {}
  m:Hide()
  function m.open(anchor, items, onPick, right)
    if m:IsShown() and m.anchor == anchor then m:Hide(); m.anchor = nil; return end
    m.anchor, m.items = anchor, items
    local wmax = 0
    for i, it in ipairs(items) do
      local b = m.btns[i]
      if not b then
        b = UI.Button(m, "", 44, ROW_H, function(bb) m:Hide(); m.anchor = nil; if m.onPick then m.onPick(bb.key) end end)
        m.btns[i] = b
      end
      b.key = it[1]
      b.text:SetText(it[2]); UI.FitButton(b, 44); UI.SetButtonSelected(b, it[3] and true or false)
      -- (the width FitButton gave it, worked out again: an unplaced frame need not answer GetWidth yet)
      local ok, tw = pcall(b.text.GetStringWidth, b.text)
      wmax = math.max(wmax, 44, math.ceil(ok and tonumber(tw) or 0) + 2 * SP.M)
      b:Show()
    end
    for i = #items + 1, #m.btns do m.btns[i]:Hide() end
    -- A long list goes on in columns, never past the bottom of the screen: as many rows as fit below the anchor (the
    -- client's GetBottom, UIParent units from the bottom), at most UI.MENU_ROWS, at least UI.MENU_MIN_ROWS.
    local rows = UI.MENU_ROWS
    local ok, bottom = pcall(anchor.GetBottom, anchor)
    bottom = ok and tonumber(bottom) or nil
    if bottom and bottom > 0 then rows = math.max(UI.MENU_MIN_ROWS, math.min(UI.MENU_ROWS, math.floor((bottom - 2 - 2 * SP.XS - SP.S) / (ROW_H + 2)))) end
    local cols = math.max(1, math.ceil(#items / rows))
    rows = math.max(1, math.min(rows, #items))
    for i = 1, #items do
      local b = m.btns[i]
      local col, row = math.floor((i - 1) / rows), (i - 1) % rows
      b:ClearAllPoints(); b:SetPoint("TOPLEFT", m, "TOPLEFT", SP.XS + col * (wmax + SP.XS), -SP.XS - row * (ROW_H + 2)); b:SetWidth(wmax)
    end
    m.rows, m.cols = rows, cols
    m.onPick = onPick
    m:SetSize(cols * wmax + (cols + 1) * SP.XS, rows * (ROW_H + 2) - 2 + 2 * SP.XS)
    if m.SetClampedToScreen then pcall(m.SetClampedToScreen, m, true) end
    m:ClearAllPoints()
    if right then m:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -2) else m:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2) end
    m:Show()
  end
  return m
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
  -- opts.slim: the design system's page scroll (2.2): no Blizzard scroll bar and no gutter; a 4 px thumb 10 px right
  -- of the frame, shown only while the content overflows; the mouse wheel scrolls
  local slim = opts and opts.slim
  local sf = slim and CreateFrame("ScrollFrame", nil, parent) or CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
  local child = CreateFrame("Frame", nil, sf)
  child:SetSize(1, 1)
  child.ebScrollChild = true
  sf:SetScrollChild(child)
  sf.child = child
  sf.contentH = 1
  if opts then
    sf:SetPoint("TOPLEFT", parent, "TOPLEFT", opts.left or 0, opts.top or 0)
    sf:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -((opts.right or 0) + (slim and 0 or UI.SCROLLBAR)), opts.bottom or 0)
  end
  if slim then
    sf.ebSlim, sf.ebScroll = true, 0
    local thumb = parent:CreateTexture(nil, "OVERLAY")
    thumb:SetWidth(4); thumb:SetColorTexture(unpackc(C.lineControl)); thumb:Hide()
    sf.thumb = thumb
    function sf.UpdateThumb()
      local viewH = tonumber(sf:GetHeight()) or 0
      local range = math.max(0, (sf.contentH or 1) - viewH)
      sf.ebScroll = math.min(math.max(0, sf.ebScroll or 0), range)
      if range <= 0 or viewH <= 0 then thumb:Hide(); return end
      local th = math.max(UI.S.S5, math.floor(viewH * viewH / sf.contentH))
      thumb:ClearAllPoints()
      thumb:SetPoint("TOPLEFT", sf, "TOPRIGHT", 10, -math.floor((viewH - th) * sf.ebScroll / range))
      thumb:SetHeight(th); thumb:Show()
    end
    function sf.ScrollTo(_, y)
      sf.ebScroll = tonumber(y) or 0
      sf.UpdateThumb()
      sf:SetVerticalScroll(sf.ebScroll)
    end
    if sf.EnableMouseWheel then sf:EnableMouseWheel(true) end
    sf:SetScript("OnMouseWheel", function(_, delta) sf:ScrollTo((sf.ebScroll or 0) - (tonumber(delta) or 0) * UI.H.ROW2) end)
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
    if sf.UpdateThumb then pcall(sf.UpdateThumb) end
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
  for _, col in ipairs(spec) do
    if col.flex then flexCols[#flexCols + 1] = col else fixed = fixed + widthOf(col) end
    fixed = fixed + (col.ebExtra or 0)          -- (a wider gap before this column, UI.KitTable's right-then-left rule)
  end
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
  -- a flex column with `max` never grows past it: what it gives up goes to a flex column without one, and with
  -- every flex column at its max the row is narrower than `w` (the table shrinks and stays left-aligned)
  local spare, open = 0, nil
  for _, col in ipairs(flexCols) do
    if col.max and widths[col] and widths[col] > col.max then spare = spare + widths[col] - col.max; widths[col] = col.max
    elseif not col.max then open = col end
  end
  if spare > 0 and open then widths[open] = (widths[open] or minOf(open)) + spare end
  local x = inset
  for _, col in ipairs(spec) do
    local cw
    x = x + (col.ebExtra or 0)
    if col.flex then cw = widths[col] or minOf(col) else cw = widthOf(col) end
    cols[col.key] = { x = x, w = cw }
    x = x + cw + gap
  end
  return cols, x - gap + inset
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

local function isNumeric(kind) return kind == "num" or kind == "money" end
function UI.Table(parent, spec, opts)
  if opts and opts.kit then return UI.KitTable(parent, spec, opts) end
  opts = opts or {}
  local SP = UI.SP
  local rowH = opts.rowHeight or UI.ROW_H
  -- (the text inset is S3, as on the kit tables: a legacy list's first column starts on the TEXT_L line too)
  local gap, inset = opts.gap or SP.M, opts.inset or S.S3
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
        -- (the sort mark is the kit's drawn chevron, as on every kit table: one style in the window)
        local ar = CreateFrame("Frame", nil, header); ar:SetSize(8, 8); ar:Hide()
        hb.gDown = UI.Glyph(ar, "chevronDown", 8, "fg"); hb.gDown:SetPoint("TOPLEFT", ar, "TOPLEFT", 0, 0)
        hb.gUp = UI.Glyph(ar, "chevronUp", 8, "fg"); hb.gUp:SetPoint("TOPLEFT", ar, "TOPLEFT", 0, 0)
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
            local g = hb.arrow
            g:ClearAllPoints()
            if col.justify == "RIGHT" then g:SetPoint("RIGHT", header, "LEFT", cw.x + cw.w - lw - SP.XS, 0)
            else g:SetPoint("LEFT", header, "LEFT", cw.x + lw + SP.XS, 0) end
            if asc then hb.gDown:Hide(); hb.gUp:Show() else hb.gUp:Hide(); hb.gDown:Show() end
            g:Show()
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

-- ══ the kit (docs/UX_OVERHAUL.md 2.7) ═════════════════════════════════════════════════════════════════════════
-- Every converted page is built from these. Unconverted panes keep UI.Button, UI.Tabs (nested), UI.Menu and the
-- classic UI.Table until their own step (the shims of section 0.3).
local function colorOf(k) return type(k) == "string" and C[k] or k end
local BOX_BD = { bgFile = WHITE, edgeFile = WHITE, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } }
-- a flat square box: `fillKey` at `alpha` (none when nil) and a 1 px `edgeKey` edge (none when nil)
function UI.BoxColors(b, fillKey, edgeKey, alpha)
  local f, e = colorOf(fillKey), colorOf(edgeKey)
  if f then b:SetBackdropColor(unpackc(f, alpha or 1)) else b:SetBackdropColor(0, 0, 0, 0) end
  if e then b:SetBackdropBorderColor(unpackc(e, 1)) else b:SetBackdropBorderColor(0, 0, 0, 0) end
end
function UI.Box(parent, fillKey, edgeKey, alpha, kind)
  local b = CreateFrame(kind or "Frame", nil, parent, "BackdropTemplate")
  b:SetBackdrop(BOX_BD)
  UI.BoxColors(b, fillKey, edgeKey, alpha)
  return b
end
-- the width of a text in a role, measured
local measureFS
function UI.TextWidth(role, text)
  if not measureFS then measureFS = UIParent:CreateFontString(nil, "OVERLAY"); measureFS:Hide() end
  local fo = UI.F[role] or UI.F.BODY
  if fo then measureFS:SetFontObject(fo) end
  if measureFS.SetFont and fo and fo.ebFile then measureFS:SetFont(fo.ebFile, fo.ebSize) end
  measureFS:SetText(UI.UPPER[role] and tostring(text or ""):upper() or tostring(text or ""))
  local w = measureFS:GetStringWidth()
  return math.ceil(type(w) == "number" and w or 0)
end
-- money as the window shows it: digits and coin icons, the two largest units (2.5 rule 4)
function UI.money(c, signed) return ns.fmtMoney(c, { icons = true, units = 2, signed = signed and true or nil }) end

-- ── tooltips: one format everywhere. spec = { title, text, pairs = { { label, value } } } or function(tip)
function UI.ShowTip(owner, spec, anchor)
  if not (GameTooltip and spec) then return end
  GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
  if type(spec) == "function" then pcall(spec, GameTooltip, owner)
  else
    if spec.title then GameTooltip:AddLine(spec.title, 1, 1, 1) end
    if spec.text then GameTooltip:AddLine(spec.text, 0.78, 0.79, 0.80, true) end
    for i, p in ipairs(spec.pairs or {}) do
      if i > 6 then break end
      GameTooltip:AddDoubleLine(p[1], p[2], C.fgMuted[1], C.fgMuted[2], C.fgMuted[3], 1, 1, 1)
    end
  end
  GameTooltip:Show()
  owner.ebTipShown = true
end
function UI.SetTip(f, spec, anchor)
  f.ebTip, f.ebTipAnchor = spec, anchor
  if f.ebTipHooked then return f end
  f.ebTipHooked = true
  if f.EnableMouse and not (f.IsMouseEnabled and f:IsMouseEnabled() == true) then pcall(f.EnableMouse, f, true) end
  f:HookScript("OnEnter", function(s) if s.ebTip then UI.ShowTip(s, s.ebTip, s.ebTipAnchor) end end)
  f:HookScript("OnLeave", function(s) if s.ebTipShown and GameTooltip then GameTooltip:Hide() end; s.ebTipShown = nil end)
  return f
end

-- ── buttons: primary, ghost, danger, link (h 24; 28 in heroes and empty states). At most one primary per view.
UI.primaries = setmetatable({}, { __mode = "k" })
local BTN_PAINT = {
  primary = { rest = { "accent", "accent", "onAccent" }, hover = { "accentHover", "accentHover", "onAccent" }, down = { "accentPressed", "accentPressed", "onAccent" } },
  ghost   = { rest = { nil, "lineStrong", "fgSubtle" }, hover = { nil, "lineControl", "fg" }, down = { "raised", "lineControl", "fg" } },
  danger  = { rest = { nil, "lineStrong", "bad" }, hover = { nil, "lineControl", "bad" }, down = { "raised", "lineControl", "bad" } },
  link    = { rest = { nil, nil, "accentFg" }, hover = { nil, nil, "accent" }, down = { nil, nil, "accent" } },
}
function UI.KitButton(parent, text, style, onClick, opts)
  opts = opts or {}
  style = BTN_PAINT[style] and style or "ghost"
  local link = style == "link"
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b.ebStyle = style
  if not link then b:SetBackdrop(BOX_BD) end
  local fs = UI.Text(b, link and (opts.role or "META") or "BODY_STRONG")
  if link then fs:SetPoint("LEFT", b, "LEFT", 0, 0) else fs:SetPoint("CENTER", b, "CENTER", 0, 0) end
  b.text = fs
  local ul
  if link then
    ul = b:CreateTexture(nil, "OVERLAY"); ul:SetHeight(1)
    ul:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -1); ul:SetPoint("TOPRIGHT", fs, "BOTTOMRIGHT", 0, -1); ul:Hide()
    b.underline = ul
  end
  local function paint(state)
    local p = BTN_PAINT[b.ebStyle][state] or BTN_PAINT[b.ebStyle].rest
    if not link then UI.BoxColors(b, p[1], p[2]) end
    fs:SetTextColor(unpackc(C[p[3]]))
    if ul then ul:SetColorTexture(unpackc(C[p[3]])); if state == "hover" then ul:Show() else ul:Hide() end end
  end
  b.ebPaint = paint
  b:SetScript("OnEnter", function(s) if not s.ebDisabled then paint("hover") end end)
  b:SetScript("OnLeave", function(s) paint("rest"); fs:ClearAllPoints(); if link then fs:SetPoint("LEFT", s, "LEFT", 0, 0) else fs:SetPoint("CENTER", s, "CENTER", 0, 0) end end)
  b:SetScript("OnMouseDown", function(s)
    if s.ebDisabled then return end
    paint("down"); fs:ClearAllPoints()
    if link then fs:SetPoint("LEFT", s, "LEFT", 0, -1) else fs:SetPoint("CENTER", s, "CENTER", 0, -1) end
  end)
  b:SetScript("OnMouseUp", function(s)
    fs:ClearAllPoints()
    if link then fs:SetPoint("LEFT", s, "LEFT", 0, 0) else fs:SetPoint("CENTER", s, "CENTER", 0, 0) end
    if not s.ebDisabled then paint("hover") end
  end)
  b:SetScript("OnClick", function(s, ...)
    if s.ebDisabled then return end
    UI.Click()
    if s.ebOnClick then s.ebOnClick(s, ...) end
  end)
  b.ebOnClick = onClick
  function b.SetLabel(_, t)
    fs:SetText(t or "")
    local w = opts.w or (UI.TextWidth(link and (opts.role or "META") or "BODY_STRONG", t) + (link and 0 or 2 * S.S3))
    b:SetSize(math.max(opts.minW or 0, w), opts.h or (link and UI.LINE_H[opts.role or "META"] or UI.H.CONTROL))
    return b
  end
  function b.SetDisabled(_, on)
    b.ebDisabled = on and true or nil
    b:SetAlpha(on and 0.4 or 1)
    paint("rest")
  end
  -- a filled button turned ghost and back (the hero's button while a run is in progress is never a primary)
  function b.SetStyle(_, st)
    if link or not BTN_PAINT[st] or st == "link" then return b end
    b.ebStyle = st
    UI.primaries[b] = (st == "primary") or nil
    paint("rest")
    return b
  end
  b:SetLabel(text)
  paint("rest")
  if style == "primary" then UI.primaries[b] = true end
  return b
end
-- the visible primary buttons under `root` (the one-primary-per-view rule)
function UI.CountPrimaries(root)
  local n = 0
  for b in pairs(UI.primaries) do
    local f, under = b, false
    while f do if f == root then under = true; break end; f = f.GetParent and f:GetParent() or nil end
    if under and b:IsVisible() then n = n + 1 end
  end
  return n
end

-- ── badges: h 16, pad 6, capitals on a tint
UI.BADGE = {
  BEST = { "goodTint", "good", tip = "Fastest run with these bosses, first pull to last kill" },
  ["IN PROGRESS"] = { "accentTint", "accentFg", dot = true },
  LIVE = { "accentTint", "accentFg", dot = true, tip = "In progress: you are in this dungeon now" },   -- (the short marker in table rows)
  WIPE = { "warnTint", "warn" }, DIED = { "badTint", "bad" },
}
function UI.Badge(parent, text)
  local b = UI.Box(parent, "raised", nil)
  b:SetHeight(16)
  local dot = UI.Glyph(b, "dot", 6, "accent"); dot:SetPoint("LEFT", b, "LEFT", 6, 0); dot:Hide()
  local fs = UI.Text(b, "BADGE")
  b.text, b.dot = fs, dot
  function b.SetBadge(_, t)
    t = tostring(t or ""):upper()
    local k = UI.BADGE[t] or { "raised", "fgSubtle" }
    UI.BoxColors(b, k[1], k[1])
    fs:SetTextColor(unpackc(C[k[2]]))
    UI.SetText(fs, t)
    fs:ClearAllPoints()
    if k.dot then dot:Show(); fs:SetPoint("LEFT", dot, "RIGHT", S.S1, 0) else dot:Hide(); fs:SetPoint("LEFT", b, "LEFT", 6, 0) end
    b:SetWidth(UI.TextWidth("BADGE", t) + 12 + (k.dot and (6 + S.S1) or 0))
    b.ebText = t
    if k.tip then UI.SetTip(b, { title = t, text = k.tip }) end
    return b
  end
  b:SetBadge(text)
  return b
end

-- ── sub-tabs: the control row (y 52 to 80) of a host. `parent` is window-aligned (a host's content frame).
-- items = { { key, label, desc } }. ctl.panes[key] are the content boxes (BOX_L to BOX_R, CONTENT_TOP to the
-- bottom margin); ctl.controls[key] is the right side of the control row for that pane (its controls anchor
-- TOPRIGHT to it, the last box edge on BOX_R). opts.shared: one content frame for every tab (a filter).
-- Detail pages swap the sub-tabs for a Back button (ctl.showBack).
function UI.SubTabs(parent, items, opts)
  opts = opts or {}
  local ctl = { panes = {}, tabs = {}, controls = {}, items = items, kit = true }
  local x = G.TEXT_L
  local rule = parent:CreateTexture(nil, "ARTWORK")
  rule:SetHeight(1); rule:SetColorTexture(unpackc(C.line))
  ctl.rule = rule
  -- The control row ends where the page's content does (2.2, 2.7): at BOX_L + MAIN_W, the right edge of the hero,
  -- the cards and the tables. With no rail that is BOX_R at 900 and window x 1216 at 1600, so a filter sits over the
  -- list it filters. ctl.rightInset() is the distance of that edge from the window's right side.
  function ctl.rightInset()
    local w = tonumber(parent:GetWidth()) or 0
    if w <= 1 then w = G.winW() end
    return math.max(G.BOX_R_INSET, w - (G.BOX_L + G.mainW(w)))
  end
  local edged = {}
  ctl.clamped = {}
  function ctl.edge()
    local r = ctl.rightInset()
    for p in pairs(ctl.clamped) do
      p:ClearAllPoints()
      p:SetPoint("TOPLEFT", parent, "TOPLEFT", G.BOX_L, -G.CONTENT_TOP); p:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -r, G.BOTTOM)
    end
    rule:ClearAllPoints()
    rule:SetPoint("TOPLEFT", parent, "TOPLEFT", G.BOX_L, -(G.CTRL_Y + G.CTRL_H)); rule:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -r, -(G.CTRL_Y + G.CTRL_H))
    for _, e in ipairs(edged) do e.f:ClearAllPoints(); e.f:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -r, e.y) end
  end
  ctl.edge()
  parent:HookScript("OnSizeChanged", function() pcall(ctl.edge) end)
  local function paneFrame()
    local p = CreateFrame("Frame", nil, parent)
    p:SetPoint("TOPLEFT", parent, "TOPLEFT", G.BOX_L, -G.CONTENT_TOP)
    p:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -G.BOX_R_INSET, G.BOTTOM)
    return p
  end
  for _, it in ipairs(items) do
    local b = CreateFrame("Button", nil, parent)
    local fs = UI.Text(b, "ROW_TITLE", "fgMuted")
    fs:SetPoint("LEFT", b, "LEFT", 0, 0); fs:SetText(it.label)
    local w = UI.TextWidth("ROW_TITLE", it.label)
    b:SetSize(w, G.CTRL_H); b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -G.CTRL_Y)
    local ul = b:CreateTexture(nil, "OVERLAY")
    ul:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0); ul:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0); ul:SetHeight(2)
    b.text, b.accent, b.key, b.ebW = fs, ul, it.key, w
    b:SetScript("OnClick", function(tb) UI.Click(); ctl.select(tb.key) end)
    b:SetScript("OnEnter", function(tb) if ctl.active ~= tb.key then fs:SetTextColor(unpackc(C.fg)) end end)
    b:SetScript("OnLeave", function() ctl.style() end)
    if it.desc then UI.SetTip(b, { title = it.label, text = it.desc }, "ANCHOR_BOTTOMLEFT") end
    ctl.tabs[#ctl.tabs + 1] = b
    if opts.shared then
      ctl.content = ctl.content or paneFrame()
      ctl.panes[it.key] = ctl.content
    else
      local p = paneFrame(); p:Hide()
      ctl.panes[it.key] = p
    end
    local cr = CreateFrame("Frame", nil, ctl.panes[it.key])
    cr:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -ctl.rightInset(), -(G.CTRL_Y + 2)); cr:SetSize(1, UI.H.CONTROL)
    edged[#edged + 1] = { f = cr, y = -(G.CTRL_Y + 2) }
    ctl.controls[it.key] = cr
    x = x + w + S.S5
  end
  ctl.tabsRight = x - S.S5
  -- A sub-tab can be hidden while its page has nothing to show (docs/UX_PRAGMATIC.md 0.5): the tabs left of it close
  -- the gap. ctl.setHidden({ key = true }) lays the row out again; a hidden tab's pane can still be selected by code.
  ctl.hidden = {}
  function ctl.layoutTabs()
    local tx = G.TEXT_L
    for _, b in ipairs(ctl.tabs) do
      if ctl.hidden[b.key] then b:Hide()
      else
        b:ClearAllPoints(); b:SetPoint("TOPLEFT", parent, "TOPLEFT", tx, -G.CTRL_Y)
        if not ctl.back then b:Show() end
        tx = tx + b.ebW + S.S5
      end
    end
    ctl.tabsRight = tx - S.S5
  end
  function ctl.setHidden(set)
    ctl.hidden = set or {}
    ctl.layoutTabs()
  end
  -- a pane not yet rebuilt on the kit (Sessions, Activity, Fights) ends where its host's converted pages end, at
  -- BOX_L + MAIN_W, so every page of the host shares one right edge
  function ctl.clamp(key)
    local p = ctl.panes[key]
    if not p or ctl.clamped[p] then return end
    ctl.clamped[p] = true
    ctl.edge()
  end
  function ctl.style()
    for _, b in ipairs(ctl.tabs) do
      local on = b.key == ctl.active
      b.text:SetTextColor(unpackc(on and C.fg or C.fgMuted))
      if on then b.accent:SetColorTexture(unpackc(C.accent)) else b.accent:SetColorTexture(0, 0, 0, 0) end
    end
  end
  function ctl.select(key)
    if ctl.back then ctl.hideBack() end
    ctl.active = key
    if not opts.shared then for k, pn in pairs(ctl.panes) do if k == key then pn:Show() else pn:Hide() end end end
    ctl.style()
    if opts.onSelect then opts.onSelect(key) end
  end
  -- a detail page: Back (named after the list it returns to) at BOX_L, optional Older and Newer at the right
  function ctl.showBack(label, onBack, nav)
    if not ctl.backBtn then
      ctl.backBtn = UI.KitButton(parent, label, "ghost", function() if ctl.onBack then ctl.onBack() end end)
      ctl.backBtn:SetPoint("TOPLEFT", parent, "TOPLEFT", G.BOX_L, -(G.CTRL_Y + 2))
      ctl.newerBtn = UI.KitButton(parent, "Newer \226\128\186", "ghost", function() if ctl.nav and ctl.nav.newer then ctl.nav.newer() end end)
      edged[#edged + 1] = { f = ctl.newerBtn, y = -(G.CTRL_Y + 2) }
      ctl.olderBtn = UI.KitButton(parent, "\226\128\185 Older", "ghost", function() if ctl.nav and ctl.nav.older then ctl.nav.older() end end)
      ctl.olderBtn:SetPoint("TOPRIGHT", ctl.newerBtn, "TOPLEFT", -S.S2, 0)
    end
    ctl.back, ctl.onBack, ctl.nav = true, onBack, nav
    ctl.edge()
    ctl.backBtn:SetLabel(label); ctl.backBtn:Show()
    for _, b in ipairs(ctl.tabs) do b:Hide() end
    for _, cr in pairs(ctl.controls) do cr:Hide() end
    local hasNav = nav ~= nil
    if hasNav then
      ctl.olderBtn:Show(); ctl.newerBtn:Show()
      ctl.olderBtn:SetDisabled(not nav.older); ctl.newerBtn:SetDisabled(not nav.newer)
    else ctl.olderBtn:Hide(); ctl.newerBtn:Hide() end
  end
  function ctl.hideBack()
    ctl.back = nil
    if ctl.backBtn then ctl.backBtn:Hide(); ctl.olderBtn:Hide(); ctl.newerBtn:Hide() end
    for _, b in ipairs(ctl.tabs) do if not ctl.hidden[b.key] then b:Show() end end
    for _, cr in pairs(ctl.controls) do cr:Show() end
  end
  return ctl
end

-- ── summary line: the page's answer, at CONTENT_TOP (h 24). f:SetSegments({ seg, ... }) where a segment is
-- { text, tip = spec, onClick = fn, color = key, dot = key }. Figures between ** are BODY_STRONG in fg
-- ("**1** instance this hour"). A segment with onClick is a link (accentFg). Segments that do not fit are left out.
function UI.Summary(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetHeight(UI.H.SUMMARY)
  f.segs, f.pool, f.seps = {}, {}, {}
  local function runsOf(text)
    local out, pos = {}, 1
    text = tostring(text or "")
    while true do
      local a, b2 = text:find("**", pos, true)
      if not a then out[#out + 1] = { text:sub(pos), false }; break end
      local c, d = text:find("**", b2 + 1, true)
      if not c then out[#out + 1] = { text:sub(pos), false }; break end
      if a > pos then out[#out + 1] = { text:sub(pos, a - 1), false } end
      out[#out + 1] = { text:sub(b2 + 1, c - 1), true }
      pos = d + 1
    end
    local clean = {}
    for _, r in ipairs(out) do if r[1] ~= "" then clean[#clean + 1] = r end end
    return clean
  end
  local function segButton(i)
    local b = f.pool[i]
    if b then return b end
    b = CreateFrame("Button", nil, f)
    b:SetHeight(UI.LINE_H.BODY + 1)
    b.runs = {}
    b:SetScript("OnClick", function(s) if s.seg and s.seg.onClick then UI.Click(); s.seg.onClick(s) end end)
    f.pool[i] = b
    return b
  end
  function f.layout()
    local avail = (tonumber(f:GetWidth()) or 0) - 2 * S.S3
    local x, shownN = S.S3, 0
    local sepW = UI.TextWidth("BODY", " \194\183 ")
    local function widthOf(runs)
      local w = 0
      for _, r in ipairs(runs) do w = w + UI.TextWidth(r[2] and "BODY_STRONG" or "BODY", r[1]) end
      return w
    end
    -- (a segment marked `optional` is the first to go when the whole line does not fit, wherever it stands)
    local segs = {}
    for _, sg in ipairs(f.segs) do segs[#segs + 1] = sg end
    local function total()
      local t = 0
      for i, sg in ipairs(segs) do t = t + (i > 1 and sepW or 0) + widthOf(runsOf((sg.dot and UI.dot(sg.dot) or "") .. tostring(sg.text or sg[1] or ""))) end
      return t
    end
    for i = #segs, 1, -1 do
      if #segs > 1 and segs[i].optional and total() > avail then table.remove(segs, i) end
    end
    f.dropped = #f.segs - #segs
    for i, sg in ipairs(segs) do
      local b = segButton(i)
      local runs = runsOf((sg.dot and UI.dot(sg.dot) or "") .. tostring(sg.text or sg[1] or ""))
      -- (a segment with a short form takes it when its full text does not fit, before the line drops it)
      if sg.short and x + (i > 1 and sepW or 0) + widthOf(runs) > S.S3 + avail then
        runs = runsOf((sg.dot and UI.dot(sg.dot) or "") .. tostring(sg.short))
      end
      local w = 0
      for j, r in ipairs(runs) do
        local fs = b.runs[j]
        if not fs then fs = UI.Text(b, "BODY"); b.runs[j] = fs end
        local role = r[2] and "BODY_STRONG" or "BODY"
        fs:SetFontObject(UI.F[role]); fs.ebRole = role
        local col = sg.onClick and "accentFg" or sg.color or (r[2] and "fg" or "fgSubtle")
        fs:SetTextColor(unpackc(C[col] or C.fgSubtle))
        fs:SetText(r[1]); fs:SetWidth(UI.TextWidth(role, r[1]) + 2)   -- (its own width: a figure is never shortened)
        fs:ClearAllPoints(); fs:SetPoint("LEFT", b, "LEFT", w, 0)
        fs:Show()
        w = w + UI.TextWidth(role, r[1])
      end
      for j = #runs + 1, #b.runs do b.runs[j]:Hide() end
      local lead = i > 1 and sepW or 0
      if i > 1 and x + lead + w > S.S3 + avail then b:Hide(); for k = i, #f.pool do f.pool[k]:Hide() end; break end
      if i > 1 then
        local sep = f.seps[i]
        if not sep then sep = UI.Text(f, "BODY", "fgMuted"); sep:SetText(" \194\183 "); f.seps[i] = sep end
        sep:ClearAllPoints(); sep:SetPoint("TOPLEFT", f, "TOPLEFT", x, -4); sep:Show()
        x = x + lead
      end
      -- the first segment alone longer than the line: its last run shortens with "..."
      if x + w > S.S3 + avail and #runs > 0 then
        local last = b.runs[#runs]
        local before = w - UI.TextWidth(last.ebRole, last:GetText())
        last:SetWidth(math.max(1, S.S3 + avail - x - before))
        w = S.S3 + avail - x
      end
      b.seg = sg
      b:ClearAllPoints(); b:SetPoint("TOPLEFT", f, "TOPLEFT", x, -4); b:SetWidth(math.max(1, w)); b:Show()
      UI.SetTip(b, sg.tip)
      if b.EnableMouse then b:EnableMouse(sg.tip ~= nil or sg.onClick ~= nil) end
      x = x + w
      shownN = i
    end
    for k = shownN + 1, #f.pool do f.pool[k]:Hide() end
    for k = shownN + 1, #f.seps do if f.seps[k] then f.seps[k]:Hide() end end
    f.shownN = shownN
  end
  function f.SetSegments(_, segs) f.segs = segs or {}; f.layout() end
  -- the visible text of the line, as the player reads it (for tests)
  function f.Text()
    local out = {}
    for i = 1, f.shownN or 0 do
      local parts = {}
      for _, fs in ipairs(f.pool[i].runs) do if fs:IsShown() then parts[#parts + 1] = fs:GetText() end end
      out[#out + 1] = table.concat(parts)
    end
    return table.concat(out, " \194\183 ")
  end
  f:HookScript("OnSizeChanged", function() pcall(f.layout) end)
  return f
end

-- ── section header (h 24): LABEL at x 12, y 7; on the right a META summary, a link, or a list's controls (f.right)
function UI.Section(parent, label)
  local f = CreateFrame("Frame", nil, parent)
  f:SetHeight(UI.H.SECTION)
  f.label = UI.Text(f, "LABEL", "fgMuted"); f.label:SetPoint("TOPLEFT", f, "TOPLEFT", S.S3, -7)
  UI.SetText(f.label, label)
  f.meta = UI.Text(f, "META", "fgSubtle", { justify = "RIGHT" }); f.meta:SetPoint("TOPRIGHT", f, "TOPRIGHT", -S.S3, -6); f.meta:Hide()
  f.link = UI.KitButton(f, "", "link"); f.link:SetPoint("TOPRIGHT", f, "TOPRIGHT", -S.S3, -5); f.link:Hide()
  f.right = CreateFrame("Frame", nil, f); f.right:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0); f.right:SetSize(1, UI.H.CONTROL)
  function f.SetLabel(_, t) UI.SetText(f.label, t) end
  function f.SetMeta(_, t) if t and t ~= "" then f.meta:SetText(t); f.meta:Show() else f.meta:Hide() end end
  function f.SetLink(_, t, fn) if t then f.link:SetLabel(t); f.link.ebOnClick = fn; f.link:Show() else f.link:Hide() end end
  return f
end

-- ── stat card (h 80): LABEL y 12, DISPLAY value y 29, META y 58. opts.onClick adds the "›" and the hover.
function UI.StatCard(parent, opts)
  opts = opts or {}
  local click = opts.onClick ~= nil
  local c = UI.Box(parent, "panel", "line", 1, click and "Button" or "Frame")
  c:SetHeight(UI.H.STAT)
  c.label = UI.Text(c, "LABEL", "fgMuted")
  c.label:SetPoint("TOPLEFT", c, "TOPLEFT", S.S3, -S.S3); c.label:SetPoint("TOPRIGHT", c, "TOPRIGHT", -(click and S.S5 or S.S3), -S.S3)
  c.value = UI.Text(c, "DISPLAY", "fg")
  c.value:SetPoint("TOPLEFT", c, "TOPLEFT", S.S3, -29); c.value:SetPoint("TOPRIGHT", c, "TOPRIGHT", -S.S3, -29)
  c.meta = UI.Text(c, "META", "fgMuted")
  c.meta:SetPoint("TOPLEFT", c, "TOPLEFT", S.S3, -58); c.meta:SetPoint("TOPRIGHT", c, "TOPRIGHT", -S.S3, -58)
  if click then
    c.chev = UI.Text(c, "META", "fgFaint"); c.chev:SetPoint("TOPLEFT", c, "TOPRIGHT", -20, -S.S3); c.chev:SetText("\226\128\186")
    c:SetScript("OnClick", function(s) UI.Click(); opts.onClick(s) end)
    c:SetScript("OnEnter", function() UI.BoxColors(c, "hover", "lineControl", 0.4); c.chev:SetTextColor(unpackc(C.fg)) end)
    c:SetScript("OnLeave", function() UI.BoxColors(c, "panel", "line"); c.chev:SetTextColor(unpackc(C.fgFaint)) end)
  end
  if opts.tip then UI.SetTip(c, opts.tip) end
  function c.Set(_, label, value, meta, valueColor)
    UI.SetText(c.label, label)
    c.value:SetText(value or "-"); c.value:SetTextColor(unpackc(colorOf(valueColor) or C.fg))
    c.meta:SetText(meta or "")
    pcall(UI.Fit, c.value, 14)
    return c
  end
  if opts.label then c:Set(opts.label, opts.value, opts.meta) end
  return c
end
-- a row of n stat cards as wide as the row: floor((width - 12 * (n - 1)) / n) each, the last takes the remainder
function UI.StatRow(parent, n, opts)
  local f = CreateFrame("Frame", nil, parent)
  f:SetHeight(UI.H.STAT)
  f.cards = {}
  for i = 1, n do f.cards[i] = UI.StatCard(f, opts and opts[i]) end
  function f.layout()
    local w = tonumber(f:GetWidth()) or 0
    if w <= 1 then return end
    local cw = math.floor((w - S.S3 * (n - 1)) / n)
    local x = 0
    for i, c in ipairs(f.cards) do
      c:ClearAllPoints(); c:SetPoint("TOPLEFT", f, "TOPLEFT", x, 0)
      c:SetWidth(i == n and (w - x) or cw)
      x = x + cw + S.S3
    end
  end
  f:HookScript("OnSizeChanged", function() pcall(f.layout) end)
  pcall(f.layout)
  return f
end

-- ── hero card (h 104): the page's one answer. opts.image adds a 56 x 56 square at x 12, y 24 (text from x 80).
-- Slots: TITLE y 12 (an optional LABEL before it, badges after), HERO y 34, META y 68 (and one at the right), then
-- a bar (y 86, h 6) or a second META line. One primary button (h 28) at the right, vertically centred.
function UI.Hero(parent, opts)
  opts = opts or {}
  local h = UI.Box(parent, "panel", "line")
  h:SetHeight(UI.H.HERO)
  local x0 = opts.image and 80 or S.S3
  h.x0 = x0
  if opts.image then
    local fr = UI.Box(h, "raised", "line"); fr:SetSize(56, 56); fr:SetPoint("TOPLEFT", h, "TOPLEFT", S.S3, -S.S5)
    local tx = fr:CreateTexture(nil, "ARTWORK"); tx:SetPoint("TOPLEFT", fr, "TOPLEFT", 1, -1); tx:SetPoint("BOTTOMRIGHT", fr, "BOTTOMRIGHT", -1, 1)
    h.imageFrame, h.image = fr, tx
  end
  h.kicker = UI.Text(h, "LABEL", "fgMuted"); h.kicker:Hide()
  h.title = UI.Text(h, "TITLE", "fg")
  h.titleMeta = UI.Text(h, "META", "fgMuted"); h.titleMeta:Hide()
  h.badges = {}
  h.hero = UI.Text(h, "HERO", "fg")
  h.meta1 = UI.Text(h, "META", "fgMuted")
  h.meta1r = UI.Text(h, "META", "fgMuted", { justify = "RIGHT" })
  h.meta2 = UI.Text(h, "META", "fgMuted"); h.meta2:Hide()
  -- the bar is drawn on the hero frame itself (ARTWORK), so the labels above it (OVERLAY) always draw over it
  -- (the track one layer under the fill and the rested part, which never overlap: the fill always draws over it)
  h.track = h:CreateTexture(nil, "BORDER"); h.track:SetColorTexture(unpackc(C.sunken)); h.track:SetHeight(6)
  h.rested = h:CreateTexture(nil, "ARTWORK"); h.rested:SetColorTexture(unpackc(C.accentTint)); h.rested:SetHeight(6)
  h.fill = h:CreateTexture(nil, "ARTWORK"); h.fill:SetColorTexture(unpackc(C.accent)); h.fill:SetHeight(6)
  h.track:Hide(); h.rested:Hide(); h.fill:Hide()
  h.button = UI.KitButton(h, "", "primary", nil, { h = UI.H.BIG_BUTTON }); h.button:Hide()
  h.button:SetPoint("TOPRIGHT", h, "TOPRIGHT", -S.S3, -38)
  function h.layout()
    local w = tonumber(h:GetWidth()) or 0
    local rInset = S.S3
    if h.button:IsShown() then rInset = S.S3 + (tonumber(h.button:GetWidth()) or 0) + S.S3 end
    for _, fs in ipairs({ h.hero, h.meta2 }) do
      fs:ClearAllPoints()
    end
    h.hero:SetPoint("TOPLEFT", h, "TOPLEFT", x0, -34); h.hero:SetPoint("TOPRIGHT", h, "TOPRIGHT", -rInset, -34)
    h.meta2:SetPoint("TOPLEFT", h, "TOPLEFT", x0, -86); h.meta2:SetPoint("TOPRIGHT", h, "TOPRIGHT", -rInset, -86)
    -- META line 1: the right text takes its width, the left text what is left
    local rw = h.meta1r:IsShown() and (h.meta1r:GetText() or "") ~= "" and UI.TextWidth("META", h.meta1r:GetText()) or 0
    h.meta1r:ClearAllPoints(); h.meta1r:SetPoint("TOPRIGHT", h, "TOPRIGHT", -rInset, -68); h.meta1r:SetWidth(math.max(1, rw))
    h.meta1:ClearAllPoints(); h.meta1:SetPoint("TOPLEFT", h, "TOPLEFT", x0, -68); h.meta1:SetPoint("TOPRIGHT", h, "TOPRIGHT", -(rInset + (rw > 0 and (rw + S.S3) or 0)), -68)
    -- the title line: kicker, title, title meta and badges, the title shortening first
    local avail = w - x0 - rInset
    local x = x0
    if h.kicker:IsShown() then
      h.kicker:ClearAllPoints(); h.kicker:SetPoint("TOPLEFT", h, "TOPLEFT", x, -16)
      x = x + UI.TextWidth("LABEL", h.kicker:GetText()) + S.S2
    end
    local bw = 0
    for _, b in ipairs(h.badges) do if b:IsShown() then bw = bw + (tonumber(b:GetWidth()) or 0) + S.S2 end end
    local mw = (h.titleMeta:IsShown() and (UI.TextWidth("META", h.titleMeta:GetText()) + S.S2)) or 0
    local tw = UI.TextWidth("TITLE", h.title:GetText())
    local room = x0 + avail - x - bw
    if mw > 0 and tw + mw > room then mw = math.max(0, room - tw) end
    tw = math.max(1, math.min(tw, room - mw))
    h.title:ClearAllPoints(); h.title:SetPoint("TOPLEFT", h, "TOPLEFT", x, -S.S3); h.title:SetWidth(tw)
    x = x + tw
    if h.titleMeta:IsShown() then
      h.titleMeta:ClearAllPoints(); h.titleMeta:SetPoint("TOPLEFT", h, "TOPLEFT", x + S.S2, -16)
      h.titleMeta:SetWidth(math.max(1, mw - S.S2)); x = x + mw
    end
    -- (badges sit on the title line's vertical centre: anchored to the title's right edge, y offset 0)
    local bx = h.titleMeta:IsShown() and mw or 0
    for _, b in ipairs(h.badges) do
      if b:IsShown() then b:ClearAllPoints(); b:SetPoint("LEFT", h.title, "RIGHT", bx + S.S2, 0); bx = bx + S.S2 + (tonumber(b:GetWidth()) or 0) end
    end
    -- the bar
    local bwid = math.max(1, w - x0 - rInset)
    h.track:ClearAllPoints(); h.track:SetPoint("TOPLEFT", h, "TOPLEFT", x0, -86); h.track:SetWidth(bwid)
    if h.barFrac then
      local f1 = math.max(0, math.min(1, h.barFrac))
      local fw = f1 > 0 and math.max(4, math.floor(bwid * f1)) or 0
      h.fill:ClearAllPoints(); h.fill:SetPoint("TOPLEFT", h, "TOPLEFT", x0, -86); h.fill:SetWidth(math.max(1, fw))
      if fw > 0 then h.fill:Show() else h.fill:Hide() end
      local f2 = h.restedFrac and math.max(f1, math.min(1, h.restedFrac)) or f1
      local rwid = math.floor(bwid * f2) - fw
      h.rested:ClearAllPoints(); h.rested:SetPoint("TOPLEFT", h, "TOPLEFT", x0 + fw, -86); h.rested:SetWidth(math.max(1, rwid))
      if rwid > 0 then h.rested:Show() else h.rested:Hide() end
    end
  end
  function h.SetKicker(_, t) if t and t ~= "" then UI.SetText(h.kicker, t); h.kicker:Show() else h.kicker:Hide() end end
  function h.SetTitle(_, t, color) h.title:SetText(t or ""); h.title:SetTextColor(unpackc(colorOf(color) or C.fg)) end
  function h.SetTitleMeta(_, t) if t and t ~= "" then h.titleMeta:SetText(t); h.titleMeta:Show() else h.titleMeta:Hide() end end
  function h.SetBadges(_, list)
    for i, t in ipairs(list or {}) do
      local b = h.badges[i] or UI.Badge(h, t); h.badges[i] = b
      b:SetBadge(t); b:Show()
    end
    for i = #(list or {}) + 1, #h.badges do h.badges[i]:Hide() end
  end
  function h.SetHero(_, t, color) h.hero:SetText(t or ""); h.hero:SetTextColor(unpackc(colorOf(color) or C.fg)) end
  function h.SetMeta(_, left, right) h.meta1:SetText(left or ""); h.meta1r:SetText(right or ""); if right and right ~= "" then h.meta1r:Show() else h.meta1r:Hide() end end
  function h.SetMeta2(_, t) if t and t ~= "" then h.meta2:SetText(t); h.meta2:Show() else h.meta2:Hide() end end
  -- the bar (slot 4): frac 0..1, an optional rested end; nil hides it
  function h.SetBar(_, frac, restedFrac)
    h.barFrac, h.restedFrac = frac, restedFrac
    if frac then h.track:Show(); h.meta2:Hide() else h.track:Hide(); h.fill:Hide(); h.rested:Hide() end
  end
  -- (style: "ghost" for a button that must not be the view's primary)
  function h.SetButton(_, label, fn, style)
    if label then h.button:SetStyle(style or "primary"); h.button:SetLabel(label); h.button.ebOnClick = fn; h.button:Show() else h.button:Hide() end
  end
  h:HookScript("OnSizeChanged", function() pcall(h.layout) end)
  return h
end

-- ── a menu of choices under a button (h 24 rows, the selected one marked by a 3 px accent bar; at most 10 rows,
-- then it scrolls with the wheel; a greyed item carries its reason). items = { { key, label, selected, disabled } }
UI.KIT_MENU_ROWS = 10
function UI.KitMenu(parent)
  local m = UI.Box(parent, "panel", "lineStrong")
  if m.SetFrameStrata then m:SetFrameStrata("DIALOG") end
  m.rows, m.offset = {}, 0
  m:Hide()
  local function row(i)
    local r = m.rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, m)
    r:SetHeight(UI.H.CONTROL)
    local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(r); hl:SetColorTexture(unpackc(C.hover, 0.6))
    r.bar = r:CreateTexture(nil, "ARTWORK"); r.bar:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0); r.bar:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0); r.bar:SetWidth(3)
    r.bar:SetColorTexture(unpackc(C.accent))
    r.text = UI.Text(r, "BODY", "fg"); r.text:SetPoint("LEFT", r, "LEFT", S.S3, 0); r.text:SetPoint("RIGHT", r, "RIGHT", -S.S3, 0)
    r:SetScript("OnClick", function(s) if s.item and not s.item[4] then UI.Click(); m:Hide(); m.anchor = nil; if m.onPick then m.onPick(s.item[1]) end end end)
    m.rows[i] = r
    return r
  end
  function m.draw()
    local n = math.min(#m.items, UI.KIT_MENU_ROWS)
    for i = 1, n do
      local it = m.items[i + m.offset]
      local r = row(i)
      r.item = it
      r:ClearAllPoints(); r:SetPoint("TOPLEFT", m, "TOPLEFT", 1, -1 - (i - 1) * UI.H.CONTROL); r:SetPoint("TOPRIGHT", m, "TOPRIGHT", -1, -1 - (i - 1) * UI.H.CONTROL)
      r.text:SetText(it and it[2] or "")
      r.text:SetTextColor(unpackc(it and it[4] and C.fgFaint or C.fg))
      if it and it[3] then r.bar:Show() else r.bar:Hide() end
      if r.EnableMouse then r:EnableMouse(it ~= nil and not it[4]) end
      r:Show()
    end
    for i = n + 1, #m.rows do m.rows[i]:Hide() end
  end
  function m.open(anchor, items, onPick)
    if m:IsShown() and m.anchor == anchor then m:Hide(); m.anchor = nil; return end
    m.anchor, m.items, m.onPick, m.offset = anchor, items or {}, onPick, 0
    local wmax = tonumber(anchor:GetWidth()) or 0
    for _, it in ipairs(m.items) do wmax = math.max(wmax, UI.TextWidth("BODY", it[2]) + 48) end
    m:SetSize(wmax, math.min(#m.items, UI.KIT_MENU_ROWS) * UI.H.CONTROL + 2)
    m:ClearAllPoints(); m:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -S.S1)
    if m.SetClampedToScreen then pcall(m.SetClampedToScreen, m, true) end
    m.draw(); m:Show()
  end
  if m.EnableMouseWheel then m:EnableMouseWheel(true) end
  m:SetScript("OnMouseWheel", function(_, d)
    local most = math.max(0, #(m.items or {}) - UI.KIT_MENU_ROWS)
    m.offset = math.max(0, math.min(most, m.offset - (tonumber(d) or 0)))
    m.draw()
  end)
  return m
end

-- ── filter button (h 24, ghost): its label plus a ▾ glyph; not on its default it is active (accent tint, label
-- accentFg) and the glyph turns into a clear glyph that resets it. opts = { items = fn() -> menu items,
-- onPick(key), default = key }. b:SetValue(key, label) after a pick. Anchor it by its TOPRIGHT.
function UI.FilterButton(parent, opts)
  opts = opts or {}
  local b = UI.Box(parent, nil, "lineStrong", 1, "Button")
  b:SetHeight(UI.H.CONTROL)
  b.text = UI.Text(b, "BODY_STRONG", "fgSubtle"); b.text:SetPoint("LEFT", b, "LEFT", S.S3, 0)
  b.chev = UI.Glyph(b, "chevronDown", 8, "fgSubtle"); b.chev:SetPoint("RIGHT", b, "RIGHT", -S.S2, 0)
  b.clear = CreateFrame("Button", nil, b); b.clear:SetSize(16, 16); b.clear:SetPoint("RIGHT", b, "RIGHT", -S.S1, 0); b.clear:Hide()
  b.clearGlyph = UI.Glyph(b.clear, "clear", 8, "accentFg"); b.clearGlyph:SetPoint("CENTER", b.clear, "CENTER", 0, 0)
  b.clear:SetScript("OnClick", function() UI.Click(); if opts.onPick then opts.onPick(opts.default) end end)
  UI.SetTip(b.clear, { title = "Clear the filter" })
  local menu = UI.KitMenu(parent)
  b.menu = menu
  b:SetScript("OnClick", function(s)
    UI.Click()
    local items = type(opts.items) == "function" and opts.items() or opts.items or {}
    menu.open(s, items, function(k) if opts.onPick then opts.onPick(k) end end)
  end)
  b:SetScript("OnEnter", function(s) if not s.ebActive then UI.BoxColors(s, nil, "lineControl") end end)
  b:SetScript("OnLeave", function(s) if s.ebActive then UI.BoxColors(s, "accentTint", "accentTint") else UI.BoxColors(s, nil, "lineStrong") end end)
  function b.SetValue(_, key, label)
    b.key = key
    b.ebActive = key ~= opts.default
    b.text:SetText(label or "")
    b:SetWidth(UI.TextWidth("BODY_STRONG", label) + 44)
    if b.ebActive then
      UI.BoxColors(b, "accentTint", "accentTint"); b.text:SetTextColor(unpackc(C.accentFg)); b.chev:Hide(); b.clear:Show()
    else
      UI.BoxColors(b, nil, "lineStrong"); b.text:SetTextColor(unpackc(C.fgSubtle)); b.chev:Show(); b.clear:Hide()
    end
    return b
  end
  b:SetValue(opts.default, opts.label or "")
  return b
end

-- ── segmented control (h 24): exclusive choices that share one width (the longest label plus 24, at least 64),
-- one 1 px lineStrong outline around the group and 1 px dividers. The selected segment has the accentTint fill and
-- its label in accentFg; the others fgMuted, fg on hover. items = { { key, label, tip } }; opts.onPick(key);
-- opts.segW fixes the segment width (Settings > Position: 4 x 100, every label inside it with S1 each side).
-- f:SetValue(key) selects (nil: none selected, as when a "More" overflow holds the pick). Anchor it by TOPRIGHT.
function UI.Segmented(parent, items, opts)
  opts = opts or {}
  local f = UI.Box(parent, nil, "lineStrong")
  f:SetHeight(UI.H.CONTROL)
  f.segs, f.items = {}, items
  local segW = 64
  for _, it in ipairs(items) do segW = math.max(segW, UI.TextWidth("BODY_STRONG", it[2]) + S.S5) end
  if opts.segW then
    segW = opts.segW
    for _, it in ipairs(items) do segW = math.max(segW, math.ceil(UI.TextWidth("BODY_STRONG", it[2])) + S.S2) end
  end
  f.segW = segW
  f:SetWidth(#items * segW)
  for i, it in ipairs(items) do
    local b = CreateFrame("Button", nil, f)
    b:SetPoint("TOPLEFT", f, "TOPLEFT", (i - 1) * segW, 0); b:SetSize(segW, UI.H.CONTROL)
    b.fill = b:CreateTexture(nil, "BACKGROUND"); b.fill:SetPoint("TOPLEFT", b, "TOPLEFT", i == 1 and 1 or 0, -1); b.fill:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", i == #items and -1 or 0, 1)
    b.fill:SetColorTexture(unpackc(C.accentTint)); b.fill:Hide()
    if i > 1 then
      b.div = b:CreateTexture(nil, "ARTWORK"); b.div:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0); b.div:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
      b.div:SetWidth(1); b.div:SetColorTexture(unpackc(C.lineStrong))
    end
    b.text = UI.Text(b, "BODY_STRONG", "fgMuted", { justify = "CENTER" }); b.text:SetPoint("CENTER", b, "CENTER", 0, 0); b.text:SetText(it[2])
    b.key = it[1]
    b:SetScript("OnClick", function(s) UI.Click(); f:SetValue(s.key); if opts.onPick then opts.onPick(s.key) end end)
    b:SetScript("OnEnter", function(s) if f.value ~= s.key then s.text:SetTextColor(unpackc(C.fg)) end end)
    b:SetScript("OnLeave", function() f.paint() end)
    if it[3] then UI.SetTip(b, { title = it[2], text = it[3] }) end
    f.segs[i] = b
  end
  function f.paint()
    for _, b in ipairs(f.segs) do
      local on = b.key == f.value
      if on then b.fill:Show() else b.fill:Hide() end
      b.text:SetTextColor(unpackc(on and C.accentFg or C.fgMuted))
    end
  end
  function f.SetValue(_, key) f.value = key; f.paint(); return f end
  f:SetValue(opts.value)
  return f
end

-- ── search input (176 x 24): sunken fill, 1 px lineStrong edge (accent while it has focus), a magnifier at x 8,
-- the text inset 26, the placeholder in fgFaint, a clear glyph button at w - 20 while there is text. Esc clears the
-- text and drops focus. Callers listen with HookScript("OnTextChanged", fn). 176 is the only search width.
UI.SEARCH_W = 176
function UI.Search(parent, placeholder)
  local e = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
  e:SetSize(UI.SEARCH_W, UI.H.CONTROL)
  e:SetBackdrop(BOX_BD)
  UI.BoxColors(e, "sunken", "lineStrong")
  e:SetFontObject(UI.F.BODY)
  e:SetTextInsets(26, S.S5, 0, 0)
  e:SetAutoFocus(false)
  e.ebSearch = true
  local mag = UI.Glyph(e, "search", 12, "fgFaint"); mag:SetPoint("LEFT", e, "LEFT", S.S2, 0)
  e.glyph = mag
  local ph = UI.Text(e, "BODY", "fgFaint")
  ph:SetPoint("LEFT", e, "LEFT", 26, 0); ph:SetPoint("RIGHT", e, "RIGHT", -S.S5, 0)
  e.placeholder = ph
  local clr = CreateFrame("Button", nil, e); clr:SetSize(16, 16); clr:SetPoint("LEFT", e, "RIGHT", -20, 0); clr:Hide()
  local cg = UI.Glyph(clr, "clear", 8, "fgMuted"); cg:SetPoint("CENTER", clr, "CENTER", 0, 0)
  clr:SetScript("OnClick", function() UI.Click(); e:SetText(""); if e.ClearFocus then e:ClearFocus() end end)
  UI.SetTip(clr, { title = "Clear the search" })
  e.clear = clr
  local function sync(x)
    local t = x:GetText()
    if t == nil or t == "" then ph:Show(); clr:Hide() else ph:Hide(); clr:Show() end
  end
  e.sync = sync
  e:SetScript("OnTextChanged", function(x) pcall(sync, x) end)
  e:SetScript("OnEditFocusGained", function(x) UI.BoxColors(x, "sunken", "accent") end)
  e:SetScript("OnEditFocusLost", function(x) UI.BoxColors(x, "sunken", "lineStrong") end)
  e:SetScript("OnEscapePressed", function(x) x:SetText(""); x:ClearFocus() end)
  e:SetScript("OnEnterPressed", function(x) x:ClearFocus() end)
  function e.SetPlaceholder(_, text) ph:SetText(text or ""); sync(e) end
  e:SetPlaceholder(placeholder)
  return e
end

-- ── notice strip (h 40): something the player can fix (tone "warn") or What's new (tone "accent").
-- opts = { tone, text, button = { label, fn }, primary = bool, onDismiss = fn }
function UI.Notice(parent, opts)
  opts = opts or {}
  local f = UI.Box(parent, "panel", nil)
  f:SetHeight(UI.H.NOTICE)
  local tone = opts.tone == "accent" and "accent" or "warn"
  f.bar = f:CreateTexture(nil, "ARTWORK"); f.bar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0); f.bar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0); f.bar:SetWidth(3)
  f.bar:SetColorTexture(unpackc(C[tone]))
  f.icon = UI.Glyph(f, "info", 16, tone); f.icon:SetPoint("LEFT", f, "LEFT", S.S3, 0)
  f.text = UI.Text(f, "BODY", "fg"); f.text:SetPoint("LEFT", f, "LEFT", 36, 0)
  f.dismiss = CreateFrame("Button", nil, f); f.dismiss:SetSize(16, 16); f.dismiss:SetPoint("LEFT", f, "RIGHT", -S.S5, 0)
  local dg = UI.Glyph(f.dismiss, "clear", 10, "fgMuted"); dg:SetPoint("CENTER", f.dismiss, "CENTER", 0, 0)
  f.dismiss:SetScript("OnClick", function() UI.Click(); f:Hide(); if opts.onDismiss then opts.onDismiss() end end)
  UI.SetTip(f.dismiss, { title = "Dismiss" })
  if opts.button then
    f.button = UI.KitButton(f, opts.button[1], opts.primary and "primary" or "ghost", function() opts.button[2]() end)
    f.button:SetPoint("RIGHT", f, "RIGHT", -40, 0)
    f.text:SetPoint("RIGHT", f.button, "LEFT", -S.S3, 0)
  else
    f.text:SetPoint("RIGHT", f, "RIGHT", -40, 0)
  end
  f.text:SetText(opts.text or "")
  return f
end

-- ── empty states. Big: a whole page with nothing in it, centred, 48 px under the top of `parent`: an icon 32
-- (fgFaint), a ROW_TITLE title at 44, a BODY sentence at 64 (420 wide), up to two buttons S5 under it.
-- opts = { icon = texture path or glyph name, title, text, buttons = { { label, fn, style } }, top }
-- The x, in `parent`, of the main column's centre (BOX_L + MAIN_W / 2 of the window): every big empty state sits on
-- it, whatever its parent's own left edge and width (a pane's frame, a column, a list host).
function UI.MainCentreX(parent)
  local win = _G.EverbuffFrame
  local wl = win and win.GetLeft and tonumber(win:GetLeft()) or nil
  local pl = parent and parent.GetLeft and tonumber(parent:GetLeft()) or nil
  local off = (wl and pl) and (pl - wl) or G.BOX_L
  return G.BOX_L + math.floor(G.mainW(G.winW()) / 2) - off
end
-- place a big empty state: its top `top` px under its parent's, centred on the main column
function UI.PlaceEmpty(f)
  local parent = f:GetParent()
  f:ClearAllPoints()
  f:SetPoint("TOP", parent, "TOPLEFT", UI.MainCentreX(parent), -(f.ebTop or S.S7))
end
function UI.Empty(parent, opts)
  opts = opts or {}
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(420, 140)
  f.ebTop = opts.top or S.S7
  f.ebEmpty = true
  UI.PlaceEmpty(f)
  f:HookScript("OnShow", function() pcall(UI.PlaceEmpty, f) end)
  if parent.HookScript then parent:HookScript("OnSizeChanged", function() pcall(UI.PlaceEmpty, f) end) end
  if opts.icon and UI.GLYPHS[opts.icon] then
    f.icon = UI.Glyph(f, opts.icon, 32, "fgFaint")
  else
    f.icon = f:CreateTexture(nil, "ARTWORK"); f.icon:SetSize(32, 32)
    if opts.icon then f.icon:SetTexture(opts.icon) end
    if f.icon.SetDesaturated then f.icon:SetDesaturated(true) end
    f.icon:SetVertexColor(unpackc(C.fgFaint))
  end
  f.icon:SetPoint("TOP", f, "TOP", 0, 0)
  f.title = UI.Text(f, "ROW_TITLE", "fg", { justify = "CENTER" })
  f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -44); f.title:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -44)
  f.text = UI.Text(f, "BODY", "fgMuted", { wrap = true, justify = "CENTER" })
  f.text:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -64); f.text:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -64)
  f.buttons = {}
  function f.Set(_, title, text, buttons)
    f.title:SetText(title or ""); f.text:SetText(text or "")
    local th = tonumber(f.text.GetStringHeight and f.text:GetStringHeight()) or UI.LINE_H.BODY
    local total, list = 0, {}
    for i, bt in ipairs(buttons or {}) do
      if i > 2 then break end
      local b = f.buttons[i] or UI.KitButton(f, bt[1], bt[3] or "ghost", nil, { h = UI.H.BIG_BUTTON })
      f.buttons[i] = b
      b.ebStyle = BTN_PAINT[bt[3] or "ghost"] and (bt[3] or "ghost") or "ghost"
      if b.ebStyle == "primary" then UI.primaries[b] = true end
      b:SetLabel(bt[1]); b.ebOnClick = bt[2]; b.ebPaint("rest"); b:Show()
      list[#list + 1] = b
      total = total + (tonumber(b:GetWidth()) or 0) + (i > 1 and S.S2 or 0)
    end
    for i = #list + 1, #f.buttons do f.buttons[i]:Hide() end
    local x = -total / 2
    for _, b in ipairs(list) do
      b:ClearAllPoints(); b:SetPoint("TOPLEFT", f, "TOP", x, -(64 + th + S.S5))
      x = x + (tonumber(b:GetWidth()) or 0) + S.S2
    end
    f:SetHeight(64 + th + (#list > 0 and (S.S5 + UI.H.BIG_BUTTON) or 0))
  end
  f:Set(opts.title, opts.text, opts.buttons)
  return f
end
-- Inline: a section or list with no rows shows its sentence right under its header, in 24 px (BODY fgMuted at
-- x 12), with an optional link after it ("Clear search"). f:Set(text, linkText, linkFn)
function UI.EmptyLine(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetHeight(UI.H.SECTION)
  f.text = UI.Text(f, "BODY", "fgMuted"); f.text:SetPoint("TOPLEFT", f, "TOPLEFT", S.S3, -4)
  f.link = UI.KitButton(f, "", "link", nil, { role = "BODY" }); f.link:Hide()
  function f.Set(_, text, linkText, fn, color)
    f.text:SetText(text or "")
    f.text:SetTextColor(unpackc(colorOf(color) or C.fgMuted))
    local tw = UI.TextWidth("BODY", text)
    local w = tonumber(f:GetWidth()) or 0
    f.text:SetWidth(math.max(1, w > 0 and math.min(tw, w - 2 * S.S3) or tw))
    if linkText then
      f.link:SetLabel(linkText); f.link.ebOnClick = fn
      f.link:ClearAllPoints(); f.link:SetPoint("LEFT", f.text, "RIGHT", S.S1, 0); f.link:Show()
    else f.link:Hide() end
  end
  return f
end

-- ── two-line row (ROW2, h 48): icon 24 at x 12, a ROW_TITLE title and a META line at x 44. r:Set(o) with
-- o = { icon = texture, title, titleColor, dot = color key (a 6 px state dot before the title), badge, meta,
-- bar = color key (a 3 px left bar), onClick, tip }. A row that opens something has a "›" and a hover band; a row
-- that opens nothing has neither.
function UI.Row2(parent)
  local r = CreateFrame("Button", nil, parent)
  r:SetHeight(UI.H.ROW2)
  r.band = r:CreateTexture(nil, "BACKGROUND"); r.band:SetAllPoints(r); r.band:SetColorTexture(unpackc(C.hover, 0.6)); r.band:Hide()
  r.bar = r:CreateTexture(nil, "ARTWORK"); r.bar:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0); r.bar:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0); r.bar:SetWidth(3); r.bar:Hide()
  r.iconFrame = UI.Box(r, "raised", "line"); r.iconFrame:SetSize(24, 24); r.iconFrame:SetPoint("TOPLEFT", r, "TOPLEFT", S.S3, -S.S3)
  r.icon = r.iconFrame:CreateTexture(nil, "ARTWORK"); r.icon:SetPoint("TOPLEFT", r.iconFrame, "TOPLEFT", 1, -1); r.icon:SetPoint("BOTTOMRIGHT", r.iconFrame, "BOTTOMRIGHT", -1, 1)
  r.dot = UI.Glyph(r, "dot", 6, "warn"); r.dot:Hide()
  r.title = UI.Text(r, "ROW_TITLE", "fg")
  r.meta = UI.Text(r, "META", "fgMuted")
  r.chev = UI.Text(r, "META", "fgFaint"); r.chev:SetPoint("TOPRIGHT", r, "TOPRIGHT", -S.S3, -17); r.chev:SetText("\226\128\186"); r.chev:Hide()
  r.badge = UI.Badge(r, ""); r.badge:Hide()
  local TX = S.S3 + 24 + S.S2      -- 44: the text column
  function r.layout()
    local w = tonumber(r:GetWidth()) or 0
    local right = S.S3 + (r.ebClick and (12 + S.S2) or 0)
    local x = TX
    if r.dot:IsShown() then r.dot:ClearAllPoints(); r.dot:SetPoint("TOPLEFT", r, "TOPLEFT", x, -(S.S2 + 5)); x = x + 6 + S.S2 end
    local bw = r.badge:IsShown() and ((tonumber(r.badge:GetWidth()) or 0) + S.S2) or 0
    local tw = UI.TextWidth("ROW_TITLE", r.title:GetText())
    local room = math.max(1, w - right - x - bw)
    r.title:ClearAllPoints(); r.title:SetPoint("TOPLEFT", r, "TOPLEFT", x, -S.S2); r.title:SetWidth(math.min(tw, room))
    if r.badge:IsShown() then r.badge:ClearAllPoints(); r.badge:SetPoint("TOPLEFT", r, "TOPLEFT", x + math.min(tw, room) + S.S2, -S.S2) end
    r.meta:ClearAllPoints(); r.meta:SetPoint("TOPLEFT", r, "TOPLEFT", TX, -26); r.meta:SetWidth(math.max(1, w - right - TX))
  end
  function r.Set(_, o)
    o = o or {}
    if o.icon then r.icon:SetTexture(o.icon); r.icon:Show() else r.icon:Hide() end
    r.title:SetText(o.title or "")
    r.title:SetTextColor(unpackc(colorOf(o.titleColor) or C.fg))
    if o.dot then r.dot:SetColor(o.dot); r.dot:Show() else r.dot:Hide() end
    if o.badge then r.badge:SetBadge(o.badge); r.badge:Show() else r.badge:Hide() end
    r.meta:SetText(o.meta or "")
    if o.bar then r.bar:SetColorTexture(unpackc(colorOf(o.bar))); r.bar:Show() else r.bar:Hide() end
    r.ebClick = o.onClick
    if o.onClick then r.chev:Show() else r.chev:Hide(); r.band:Hide() end
    r.ebTip = o.tip
    if (o.onClick or o.tip) and r.EnableMouse then r:EnableMouse(true) elseif r.EnableMouse then r:EnableMouse(false) end
    r.layout()
    return r
  end
  r:SetScript("OnClick", function(s) if s.ebClick then UI.Click(); s.ebClick(s) end end)
  r:SetScript("OnEnter", function(s)
    if s.ebClick then s.band:Show(); s.chev:SetTextColor(unpackc(C.fg)) end
    if s.ebTip then UI.ShowTip(s, s.ebTip) end
  end)
  r:SetScript("OnLeave", function(s)
    s.band:Hide(); s.chev:SetTextColor(unpackc(C.fgFaint))
    if s.ebTipShown and GameTooltip then GameTooltip:Hide() end; s.ebTipShown = nil
  end)
  r:HookScript("OnSizeChanged", function() pcall(r.layout) end)
  return r
end

-- ── the kit list (UI.Table with opts.kit): no scroll of its own (the page scrolls as one), rows 32, header 24 in
-- LABEL with a 1 px rule, stripes, a hover band and a "›" on rows that open something, a selected mark, `max` on
-- flex columns, `wide` columns only at WIDE, day rows (items with ebSection, h 24) and inline loading, empty and
-- no-match text under the header. The caller anchors tbl.frame (TOPLEFT and TOPRIGHT); its height follows the
-- rows, and opts.onHeight(h) hears it. Cell fonts: the first text column BODY fg, others BODY fgSubtle, a column
-- with strong = true BODY_STRONG fg.
-- The stripe is `panel` at full alpha: at 0.5 over the canvas (#111111) it is 1.7 L* away and does not show; the
-- spec's own check asks for 3 L* or more (docs/UX_OVERHAUL.md 5 step 2), which full alpha meets (3.4 L*).
UI.STRIPE_ALPHA = 1
-- the lead column of every table on a detail page ("#", the 20 px icon or the time): the name column after it starts
-- at table x 60 (inset 12 + 36 + gap 12) on every table of the page
UI.LEAD_W = 36
-- the regions a page adds to a table row beside its cells (row[key]); a day or group row hides them all
UI.ROW_EXTRAS = { "ebCount", "ebBadge", "ebLootIc", "ebBar", "ebDot", "ebIcon" }
function UI.KitTable(parent, spec, opts)
  opts = opts or {}
  local rowH, headH, dayH = opts.rowHeight or UI.H.ROW, UI.H.TABLE_HEAD, UI.H.DAY_ROW
  local gap, inset = S.S3, S.S3
  local iconSize = opts.iconSize or 20
  local f = CreateFrame("Frame", nil, parent)
  local tbl = { spec = spec, cols = {}, rows = {}, head = {}, kit = true, frame = f, sortKey = opts.sortKey, sortAsc = opts.sortAsc, shownN = 0, gen = 0 }
  f.ebKitTable = tbl   -- (the tests find a page's tables through their frames)
  local clickable = opts.onClick ~= nil
  local full = {}
  local firstText
  for _, col in ipairs(spec) do
    full[#full + 1] = col
    col.justify = col.justify or (isNumeric(col.kind) and "RIGHT" or "LEFT")
    if not firstText and (col.kind == nil or col.kind == "text") then firstText = col.key end
  end
  -- (opts.chevron = "reserve": a table that opens nothing keeps the 12 px slot, so the tables of one page share their
  -- right edge; its rows show no chevron)
  if (clickable and opts.chevron ~= false) or opts.chevron == "reserve" then full[#full + 1] = { key = "_chev", label = "", min = 12, chevron = true, justify = "RIGHT" } end
  tbl.full = full
  local header = CreateFrame("Frame", nil, f)
  header:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0); header:SetHeight(headH)
  local rule = header:CreateTexture(nil, "ARTWORK"); rule:SetHeight(1); rule:SetColorTexture(unpackc(C.line))
  rule:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0); rule:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
  tbl.header, tbl.rule = header, rule
  for _, col in ipairs(full) do
    local hb = CreateFrame("Button", nil, header); hb:SetHeight(headH)
    local fs = UI.CellFS(header, "GameFontNormalSmall")
    fs:SetFontObject(UI.F.LABEL); fs.ebRole = "LABEL"; fs:SetTextColor(unpackc(C.fgMuted))
    fs:SetJustifyH(col.justify); fs:SetText((col.label or ""):upper())
    hb.fs, hb.key = fs, col.key
    if col.tip then UI.SetTip(hb, { title = col.label, text = col.tip }) end
    if col.sort then
      hb.gDown = UI.Glyph(header, "chevronDown", 8, "fg"); hb.gDown:Hide()
      hb.gUp = UI.Glyph(header, "chevronUp", 8, "fg"); hb.gUp:Hide()
      hb.glyph = hb.gDown
      hb:SetScript("OnClick", function(b)
        UI.Click()
        local asc
        if tbl.sortKey == b.key then asc = not tbl.sortAsc else asc = (col.kind == nil or col.kind == "text") end
        tbl.setSort(b.key, asc)
        if opts.onSort then opts.onSort(b.key, asc) end
      end)
    end
    tbl.head[col.key] = hb
  end
  local base, shown = {}, {}
  local function measureBase()
    for _, col in ipairs(full) do
      local lw = UI.TextWidth("LABEL", col.label or "") + (col.sort and 12 or 0)
      local m = col.measure
      if type(m) == "function" then local ok, r = pcall(m); m = ok and r or nil end
      local mw = 0
      if type(m) == "table" then for _, v in ipairs(m) do mw = math.max(mw, UI.TextWidth(col.strong and "BODY_STRONG" or "BODY", v)) end end
      if col.kind == "icon" then base[col.key] = math.max(col.min or 0, iconSize)
      elseif col.flex then col.headMin = math.max(lw, mw)
      else base[col.key] = math.max(col.min or 0, lw, mw) end
    end
  end
  measureBase()
  -- (a text column with `max` stops growing with its values there, so the first text column keeps the flex space:
  -- a long source shortens before the item name does)
  local function widthOf(col)
    if col.fixed then return col.fixed end   -- (a lead column: "#", the 20 px icon or the time, UI.LEAD_W on every table of a page)
    local w = math.max(base[col.key] or 0, shown[col.key] or 0)
    if col.max and not col.flex and not isNumeric(col.kind) then w = math.min(w, math.max(col.max, base[col.key] or 0)) end
    return w
  end
  local function active()
    local wide, out = G.isWide(G.winW()), {}
    -- (col.hide: a column the page leaves out for now, such as a comparison with nothing to compare)
    for _, col in ipairs(full) do if (not col.wide or wide) and not col.hide then out[#out + 1] = col end end
    return out
  end
  local function placeRow(row)
    row.ebGen = tbl.gen
    for _, col in ipairs(full) do
      local cw, cell = tbl.cols[col.key], row.c[col.key]
      if cw then
        cell:ClearAllPoints()
        if col.kind == "icon" then cell:SetPoint("LEFT", row, "LEFT", cw.x, 0); cell:SetSize(iconSize, iconSize)
        else cell:SetPoint("LEFT", row, "LEFT", cw.x, 0); cell:SetWidth(cw.w) end
        if not row.section or not row.section:IsShown() then cell:Show() end
      else cell:Hide() end
    end
  end
  function tbl.relayout(w)
    w = tonumber(w) or 0
    if w <= 1 then return end
    w = math.min(w, G.TABLE_MAX)
    tbl.width = w
    tbl.gen = tbl.gen + 1
    -- a left-aligned column right after a right-aligned one is S5 from it, not S3: at S3 two headers read as one
    -- label and two values as one ("4m 47s -")
    local act = active()
    for i, col in ipairs(act) do
      local prev = act[i - 1]
      col.ebExtra = (prev and prev.justify == "RIGHT" and col.justify ~= "RIGHT" and col.kind ~= "icon") and (S.S5 - gap) or nil
    end
    local cols, used = UI.LayoutColumns(act, w, widthOf, gap, inset)
    tbl.cols, tbl.usedW = cols, math.min(w, used or w)
    header:SetWidth(tbl.usedW)
    for _, col in ipairs(full) do
      local cw, hb = cols[col.key], tbl.head[col.key]
      if cw then
        hb:ClearAllPoints(); hb:SetPoint("LEFT", header, "LEFT", cw.x, 0); hb:SetWidth(cw.w); hb:Show()
        hb.fs:ClearAllPoints(); hb.fs:SetPoint("LEFT", header, "LEFT", cw.x, 0); hb.fs:SetWidth(cw.w); hb.fs:Show()
      else hb:Hide(); hb.fs:Hide() end
    end
    tbl.setSort(tbl.sortKey, tbl.sortAsc)
    for i = 1, tbl.shownN do placeRow(tbl.rows[i]); tbl.rows[i]:SetWidth(tbl.usedW) end
    -- (the inline sentence is as wide as its text, so a link after it stays on its line, right after its last word)
    if tbl.state and tbl.stateArgs then tbl.setState(tbl.stateArgs[1], tbl.stateArgs[2], tbl.stateArgs[3], tbl.stateArgs[4]) end
    if opts.onLayout then pcall(opts.onLayout, tbl) end
  end
  function tbl.setSort(key, asc)
    tbl.sortKey, tbl.sortAsc = key, asc and true or false
    for _, col in ipairs(full) do
      local hb, cw = tbl.head[col.key], tbl.cols[col.key]
      local on = col.sort and col.key == key
      hb.fs:SetTextColor(unpackc(on and C.fg or C.fgMuted))
      if hb.gDown then
        hb.gDown:Hide(); hb.gUp:Hide()
        if on and cw then
          local lw = math.min(cw.w - 12, UI.TextWidth("LABEL", col.label or ""))
          hb.glyph = asc and hb.gUp or hb.gDown
          hb.glyph:ClearAllPoints()
          if col.justify == "RIGHT" then hb.glyph:SetPoint("LEFT", header, "LEFT", cw.x + cw.w - lw - 12, 0)
          else hb.glyph:SetPoint("LEFT", header, "LEFT", cw.x + lw + S.S1, 0) end
          hb.glyph:Show()
        end
      end
    end
  end
  local function newRow()
    local row = CreateFrame("Button", nil, f)
    row:SetHeight(rowH)
    row.stripe = row:CreateTexture(nil, "BACKGROUND"); row.stripe:SetAllPoints(row)
    row.sel = row:CreateTexture(nil, "BORDER"); row.sel:SetAllPoints(row); row.sel:SetColorTexture(unpackc(C.raised)); row.sel:Hide()
    row.mark = row:CreateTexture(nil, "ARTWORK"); row.mark:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0); row.mark:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    row.mark:SetWidth(3); row.mark:SetColorTexture(unpackc(C.accent)); row.mark:Hide()
    if clickable then
      local hl = row:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(row); hl:SetColorTexture(unpackc(C.hover, 0.6)); row.highlight = hl
      if row.RegisterForClicks then row:RegisterForClicks("LeftButtonUp") end
      row:SetScript("OnClick", function(r, button) UI.Click(); pcall(opts.onClick, r, r.item, button) end)
    end
    if opts.tooltip then
      row:SetScript("OnEnter", function(r)
        if not GameTooltip then return end
        GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
        local ok = pcall(opts.tooltip, r, r.item, GameTooltip)
        if ok then UI.AddCellLines(r) end
        GameTooltip:Show(); r.ebOwnTip = true
        if r.c._chev then r.c._chev:SetTextColor(unpackc(C.fg)) end
      end)
      row:SetScript("OnLeave", function(r) if r.ebOwnTip and GameTooltip then GameTooltip:Hide() end; r.ebOwnTip = nil; if r.c._chev then r.c._chev:SetTextColor(unpackc(C.fgFaint)) end end)
    elseif clickable then
      row:SetScript("OnEnter", function(r) if r.c._chev then r.c._chev:SetTextColor(unpackc(C.fg)) end end)
      row:SetScript("OnLeave", function(r) if r.c._chev then r.c._chev:SetTextColor(unpackc(C.fgFaint)) end end)
    end
    row.c = {}
    for _, col in ipairs(full) do
      if col.kind == "icon" then
        local tx = row:CreateTexture(nil, "ARTWORK"); tx:SetSize(iconSize, iconSize); tx:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.c[col.key] = tx
      else
        local fs = UI.CellFS(row, "GameFontHighlightSmall")
        local role = col.strong and "BODY_STRONG" or "BODY"
        fs:SetFontObject(UI.F[role]); fs.ebRole = role
        fs:SetJustifyH(col.justify); fs.ebRow = row
        if col.chevron then fs:SetText("\226\128\186") end
        row.c[col.key] = fs
      end
    end
    if tbl.width then placeRow(row) end
    return row
  end
  local function defaultColor(col)
    if col.chevron then return C.fgFaint end
    if col.strong or col.key == firstText then return C.fg end
    return colorOf(col.color) or C.fgSubtle
  end
  -- the inline text under the header: "loading", "empty" or "nomatch" (with a link). noHead: a list with nothing
  -- to show has no column header either (B24): the sentence takes the header's place.
  function tbl.setState(text, linkText, linkFn, noHead)
    if not tbl.stateFS then
      tbl.stateFS = UI.Text(f, "BODY", "fgMuted", { wrap = true })
      tbl.stateLink = UI.KitButton(f, "", "link", nil, { role = "BODY" }); tbl.stateLink:Hide()
    end
    if not text then tbl.stateFS:Hide(); tbl.stateLink:Hide(); tbl.state, tbl.stateArgs = nil, nil; header:Show(); return end
    tbl.state, tbl.stateArgs = text, { text, linkText, linkFn, noHead }
    local top = noHead and 0 or headH
    if noHead then header:Hide() else header:Show() end
    tbl.stateFS:ClearAllPoints(); tbl.stateFS:SetPoint("TOPLEFT", f, "TOPLEFT", S.S3, -(top + S.S3))
    tbl.shownN = 0
    for _, row in ipairs(tbl.rows) do row:Hide() end
    local maxW = math.min((tbl.usedW or 520) - 2 * S.S3, 520)
    local tw = UI.TextWidth("BODY", text)
    tbl.stateFS:SetWidth(math.max(1, math.min(tw, maxW))); tbl.stateFS:SetText(text); tbl.stateFS:Show()
    local th = UI.LINE_H.BODY
    if linkText then
      tbl.stateLink:SetLabel(linkText); tbl.stateLink.ebOnClick = linkFn
      tbl.stateLink:ClearAllPoints()
      -- (on the sentence's line: the link's label shares the sentence's vertical centre and font height)
      if tw + S.S1 + UI.TextWidth("BODY", linkText) <= maxW then tbl.stateLink:SetPoint("LEFT", tbl.stateFS, "RIGHT", S.S1, 0)
      else
        th = math.ceil(tw / math.max(1, maxW)) * UI.LINE_H.BODY
        tbl.stateLink:SetPoint("TOPLEFT", f, "TOPLEFT", S.S3, -(top + S.S3 + th + S.S1)); th = th + S.S1 + UI.LINE_H.BODY
      end
      tbl.stateLink:Show()
    else
      tbl.stateLink:Hide()
      if tw > maxW then th = math.ceil(tw / math.max(1, maxW)) * UI.LINE_H.BODY end
    end
    tbl.height = top + S.S3 + th + S.S3
    f:SetHeight(tbl.height)
    if opts.onHeight then pcall(opts.onHeight, tbl.height) end
  end
  tbl.setEmpty = tbl.setState
  function tbl.setSelected(item)
    tbl.selected = item
    for i = 1, tbl.shownN do local r = tbl.rows[i]; local on = item ~= nil and r.item == item; if on then r.sel:Show(); r.mark:Show() else r.sel:Hide(); r.mark:Hide() end end
  end
  function tbl.setRows(items, fillFn)
    items = items or {}
    local before = {}
    for k, v in pairs(base) do before[k] = v end
    pcall(measureBase)
    local changed = false
    for k, v in pairs(base) do if before[k] ~= v then changed = true end end
    if #items == 0 and opts.emptyText then tbl.setState(opts.emptyText); return end
    tbl.setState(nil)
    tbl.shownN = #items
    local y, dataI = headH, 0
    for i, item in ipairs(items) do
      local row = tbl.rows[i]
      if not row then row = newRow(); tbl.rows[i] = row
      elseif tbl.width and row.ebGen ~= tbl.gen then placeRow(row) end
      row.item, row.index = item, i
      row:ClearAllPoints(); row:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y)
      if tbl.usedW then row:SetWidth(tbl.usedW) end
      for _, col in ipairs(full) do
        local cell = row.c[col.key]
        if col.kind == "icon" then cell:SetTexture(nil)
        elseif not col.chevron then cell:SetText(""); cell:SetTextColor(unpackc(defaultColor(col)))
        else cell:SetTextColor(unpackc(C.fgFaint)) end
      end
      row.sel:Hide(); row.mark:Hide()
      if item.ebSection then
        if not row.section then
          row.section = UI.Text(row, "LABEL", "fgMuted")
          row.section:SetPoint("LEFT", row, "LEFT", inset, 0); row.section:SetPoint("RIGHT", row, "RIGHT", -inset, 0)
        end
        UI.SetText(row.section, item.ebSection); row.section:Show()
        for _, col in ipairs(full) do row.c[col.key]:Hide() end
        -- (a recycled data row keeps the regions its page added beside the cells, a stack count, a badge, a loot
        -- icon: a day row shows its label and nothing else)
        for _, k in ipairs(UI.ROW_EXTRAS) do local x = row[k]; if x and x.Hide then x:Hide() end end
        row.stripe:SetColorTexture(0, 0, 0, 0)
        row:SetHeight(dayH)
        if row.EnableMouse then row:EnableMouse(false) end
        y = y + dayH
      else
        if row.section then row.section:Hide() end
        for _, col in ipairs(full) do if tbl.cols[col.key] then row.c[col.key]:Show() end end
        dataI = dataI + 1
        if dataI % 2 == 0 then row.stripe:SetColorTexture(unpackc(C.panel, UI.STRIPE_ALPHA)) else row.stripe:SetColorTexture(0, 0, 0, 0) end
        row:SetHeight(rowH)
        if row.EnableMouse then row:EnableMouse(clickable or opts.tooltip ~= nil) end
        -- (row.ebNoOpen: a fill that knows a row opens nothing says so on the row, so a stored record is never marked)
        row.ebNoOpen = nil
        if fillFn then fillFn(row, item, i) end
        if row.c._chev then row.c._chev:SetText((item.ebNoOpen or row.ebNoOpen or not clickable) and "" or "\226\128\186") end
        if item == tbl.selected then row.sel:Show(); row.mark:Show() end
        y = y + rowH
      end
      row:Show()
    end
    for j = #items + 1, #tbl.rows do tbl.rows[j]:Hide() end
    tbl.height = y
    f:SetHeight(y)
    for _, col in ipairs(full) do
      if not col.flex and col.kind ~= "icon" and col.kind ~= "text" and col.kind ~= nil then
        local wmax = 0
        for i = 1, #items do
          local fs = tbl.rows[i].c[col.key]
          local t = fs:GetText()
          if t and t ~= "" and not items[i].ebSection then wmax = math.max(wmax, UI.TextWidth(fs.ebRole or "BODY", t)) end
        end
        if wmax ~= (shown[col.key] or 0) then shown[col.key] = wmax; changed = true end
      end
    end
    if tbl.width and changed then tbl.relayout(tbl.width) end
    if opts.onHeight then pcall(opts.onHeight, y) end
  end
  function tbl.sections()
    local out = {}
    for i = 1, tbl.shownN do local r = tbl.rows[i]; if r.section and r.section:IsShown() then out[#out + 1] = r.section end end
    return out
  end
  f:HookScript("OnSizeChanged", function() pcall(tbl.relayout, f:GetWidth()) end)
  pcall(tbl.relayout, f:GetWidth())
  return tbl
end

-- ── a detail page with Back (UI.Detail). `pane` is a pane's content frame (its host's sub-tab control is
-- pane.ebHostCtl); opts = { list = the list frame it covers, back = "‹ Runs", render(item, content, d),
-- onBack(item) }. d:Open(items, index): items is the list's current order (newest first), so Older is index + 1.
-- The list frame is only hidden, so its scroll offset and selection are kept for Back.
function UI.Detail(pane, opts)
  opts = opts or {}
  local d = {}
  local view = CreateFrame("Frame", nil, pane); view:SetAllPoints(pane); view:Hide()
  local sf, child = UI.ScrollChild(view, { slim = true })
  d.view, d.sf, d.content = view, sf, child
  local function ctl() return pane.ebHostCtl end
  local function draw()
    local item = d.items and d.items[d.index]
    if not item then return end
    if sf.ScrollTo then sf:ScrollTo(0) end
    local c = ctl()
    if c and c.showBack then
      c.showBack(opts.back or "\226\128\185 Back", d.Close, {
        older = d.items[d.index + 1] and function() d.index = d.index + 1; draw() end or nil,
        newer = d.items[d.index - 1] and function() d.index = d.index - 1; draw() end or nil })
    end
    if opts.render then local ok, err = pcall(opts.render, item, child, d); d.renderError = (not ok) and tostring(err) or nil end
  end
  function d.Open(_, items, index)
    d.items, d.index = items or {}, index or 1
    if opts.list then opts.list:Hide() end
    view:Show()
    draw()
  end
  function d.Close()
    if not view:IsShown() then return end
    view:Hide()
    if opts.list then opts.list:Show() end
    local c = ctl()
    if c and c.hideBack then c.hideBack() end
    if opts.onBack then pcall(opts.onBack, d.items and d.items[d.index]) end
  end
  function d.IsOpen() return view:IsShown() end
  d.Redraw = draw
  return d
end

-- ── a page: one scroll (UI.ScrollChild, slim) holding a column at the pane's left edge (BOX_L). pg.place(list, w)
-- stacks the list top to bottom: each entry is { frame, height, gap = px after it, x = px from the left, w = width }
-- (a hidden frame takes no room); the column and the scroll take the total height.
function UI.Page(content)
  local pg = {}
  local sf, child = UI.ScrollChild(content, { slim = true, top = 0, left = 0, right = 0, bottom = 0 })
  local col = CreateFrame("Frame", nil, child)
  col:SetPoint("TOPLEFT", child, "TOPLEFT", 0, 0); col:SetSize(1, 1)
  pg.sf, pg.child, pg.col = sf, child, col
  function pg.place(list, w)
    w = w or G.mainW(G.winW())
    col:SetWidth(w)
    local y, ys = 0, {}
    for _, e in ipairs(list) do
      local f = e[1]
      if f and f:IsShown() then
        local ex = e.x or 0
        local top = e.y or y
        f:ClearAllPoints(); f:SetPoint("TOPLEFT", col, "TOPLEFT", ex, -top); f:SetWidth(e.w or (w - ex))
        if e[2] then f:SetHeight(e[2]) end
        ys[f] = top
        local bottom = top + (e[2] or tonumber(f:GetHeight()) or 0) + (e.gap or 0)
        if e.y then y = math.max(y, bottom) else y = bottom end
      end
    end
    y = y + S.S4
    col:SetHeight(y)
    sf:SetContentHeight(y)
    pg.height, pg.ys = y, ys
    return y
  end
  return pg
end

-- ── a progress bar (h 6): a `sunken` track and an `accent` fill, a 4 px sliver once there is any progress.
-- b:SetFrac(0..1 or nil): nil hides the bar.
function UI.Bar(parent, w)
  local b = CreateFrame("Frame", nil, parent)
  b:SetSize(w or 120, 6)
  b.track = b:CreateTexture(nil, "BORDER"); b.track:SetAllPoints(b); b.track:SetColorTexture(unpackc(C.sunken))
  b.fill = b:CreateTexture(nil, "ARTWORK"); b.fill:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0); b.fill:SetHeight(6)
  b.fill:SetColorTexture(unpackc(C.fgSubtle)); b.fill:Hide()   -- (fgSubtle on the sunken track, as every bar)
  function b.SetFrac(_, frac)
    b.frac = frac
    if not frac then b:Hide(); return b end
    b:Show()
    local bw = tonumber(b:GetWidth()) or (w or 120)
    local f = math.max(0, math.min(1, frac))
    local fw = f > 0 and math.max(4, math.floor(bw * f)) or 0
    if fw > 0 then b.fill:SetWidth(math.min(bw, fw)); b.fill:Show() else b.fill:Hide() end
    return b
  end
  return b
end

-- ── settings controls (4.12), drawn from WHITE8x8 and text only (no Blizzard templates).
-- Checkbox: 16 x 16, a 1 px lineControl edge; checked, an accent fill with a check glyph in onAccent.
-- cb:SetChecked(on), cb:GetChecked(); opts.onChange(on) hears a click. cb.checked mirrors the state (tests).
function UI.Checkbox(parent, opts)
  opts = opts or {}
  local cb = UI.Box(parent, nil, "lineControl", 1, "Button")
  cb:SetSize(16, 16)
  cb.glyph = UI.Glyph(cb, "check", 10, "onAccent"); cb.glyph:SetPoint("CENTER", cb, "CENTER", 0, 0); cb.glyph:Hide()
  cb.ebCheckbox = true
  function cb.SetChecked(_, on)
    cb.checked = on and true or false
    if cb.checked then UI.BoxColors(cb, "accent", "accent"); cb.glyph:Show() else UI.BoxColors(cb, nil, "lineControl"); cb.glyph:Hide() end
  end
  function cb.GetChecked() return cb.checked end
  cb:SetScript("OnClick", function(s)
    UI.Click()
    s:SetChecked(not s.checked)
    if opts.onChange then opts.onChange(s.checked) end
  end)
  cb:SetScript("OnEnter", function(s) if not s.checked then UI.BoxColors(s, "hover", "fgMuted") end end)
  cb:SetScript("OnLeave", function(s) s:SetChecked(s.checked) end)
  cb:SetChecked(opts.checked)
  return cb
end
-- Slider: a 200 x 4 sunken track with an accent fill, a 12 x 12 fg thumb, the value (BODY_STRONG, 40 wide) right of
-- the track. opts = { min, max, step, value, fmt(v) -> text, onChange(v) }. s:SetValue(v) moves it and tells
-- onChange; a click or a drag on the track sets it; the wheel steps it.
UI.SLIDER_W = 200
-- Every slider maps the same way: the low end of its range at the left of the track, the high end at the right,
-- both named in fgFaint META at the track's ends (the min left of it, the max right of it); the fill is fgSubtle on
-- the sunken track, as every bar of the window.
UI.SLIDER_END_W = 32
function UI.Slider(parent, opts)
  opts = opts or {}
  local lo, hi, step = opts.min or 0, opts.max or 1, opts.step or 0.05
  local s = CreateFrame("Button", nil, parent)
  local EW = UI.SLIDER_END_W
  s:SetSize(EW + S.S1 + UI.SLIDER_W + S.S1 + EW + S.S2 + 40, 16)
  local fmtEnd = opts.fmt or tostring
  s.minText = UI.Text(s, "META", "fgFaint", { justify = "RIGHT" }); s.minText:SetPoint("LEFT", s, "LEFT", 0, 0); s.minText:SetWidth(EW)
  s.minText:SetText(fmtEnd(lo))
  s.maxText = UI.Text(s, "META", "fgFaint", { justify = "LEFT" }); s.maxText:SetPoint("LEFT", s, "LEFT", EW + S.S1 + UI.SLIDER_W + S.S1, 0); s.maxText:SetWidth(EW)
  s.maxText:SetText(fmtEnd(hi))
  local X0 = EW + S.S1
  s.trackX = X0
  s.track = s:CreateTexture(nil, "BORDER"); s.track:SetPoint("LEFT", s, "LEFT", X0, 0); s.track:SetSize(UI.SLIDER_W, 4)
  s.track:SetColorTexture(unpackc(C.sunken))
  s.fill = s:CreateTexture(nil, "ARTWORK"); s.fill:SetPoint("LEFT", s, "LEFT", X0, 0); s.fill:SetHeight(4); s.fill:SetColorTexture(unpackc(C.fgSubtle))
  s.thumb = s:CreateTexture(nil, "OVERLAY"); s.thumb:SetSize(12, 12); s.thumb:SetColorTexture(unpackc(C.fg))
  s.valueText = UI.Text(s, "BODY_STRONG", "fg", { justify = "RIGHT" }); s.valueText:SetPoint("RIGHT", s, "RIGHT", 0, 0); s.valueText:SetWidth(40)
  s.ebSlider = true
  local function snap(v)
    v = math.max(lo, math.min(hi, tonumber(v) or lo))
    return math.floor((v - lo) / step + 0.5) * step + lo
  end
  local function draw()
    local f = hi > lo and (s.value - lo) / (hi - lo) or 0
    local x = math.floor(UI.SLIDER_W * f + 0.5)
    s.fill:SetWidth(math.max(1, x)); if x > 0 then s.fill:Show() else s.fill:Hide() end
    s.thumb:ClearAllPoints(); s.thumb:SetPoint("CENTER", s, "LEFT", s.trackX + math.max(6, math.min(UI.SLIDER_W - 6, x)), 0)
    s.valueText:SetText(opts.fmt and opts.fmt(s.value) or tostring(s.value))
  end
  function s.SetValue(_, v, quiet)
    local nv = snap(v)
    local changed = nv ~= s.value
    s.value = nv
    draw()
    if changed and not quiet and opts.onChange then opts.onChange(nv) end
  end
  function s.GetValue() return s.value end
  local function fromCursor()
    local ok, x = pcall(GetCursorPosition)
    if not ok or type(x) ~= "number" then return end
    local sc = (s.GetEffectiveScale and s:GetEffectiveScale()) or 1
    local l = s.GetLeft and s:GetLeft()
    if type(l) ~= "number" or not sc or sc == 0 then return end
    s:SetValue(lo + (hi - lo) * math.max(0, math.min(1, (x / sc - l - s.trackX) / UI.SLIDER_W)))
  end
  s:SetScript("OnMouseDown", function() s.dragging = true; pcall(fromCursor) end)
  s:SetScript("OnMouseUp", function() s.dragging = nil end)
  s:SetScript("OnUpdate", function() if s.dragging then pcall(fromCursor) end end)
  if s.EnableMouseWheel then s:EnableMouseWheel(true) end
  s:SetScript("OnMouseWheel", function(_, d) s:SetValue(s.value + (tonumber(d) or 0) * step) end)
  s:SetScript("OnEnter", function() s.thumb:SetColorTexture(unpackc(C.accentFg)) end)
  s:SetScript("OnLeave", function() s.thumb:SetColorTexture(unpackc(C.fg)) end)
  s.value = snap(opts.value or lo)
  draw()
  return s
end
-- Setting row (h 32, 48 with a description): ROW_TITLE label at x 12 (vertically centred; y 8 when described), a
-- META description at y 28 (wrapping at min(w - 24, 520), under the control), the control right-aligned at w - 12.
-- r:SetControl(frame).
function UI.SettingRow(parent, label, desc)
  local r = CreateFrame("Frame", nil, parent)
  local h = desc and UI.H.SETTING_DESC or UI.H.SETTING
  r:SetHeight(h); r.ebH = h
  r.label = UI.Text(r, "ROW_TITLE", "fg")
  r.label:SetPoint("TOPLEFT", r, "TOPLEFT", S.S3, desc and -S.S2 or -((h - UI.LINE_H.ROW_TITLE) / 2))
  r.label:SetText(label or "")
  if desc then
    r.desc = UI.Text(r, "META", "fgMuted", { wrap = true })
    r.desc:SetPoint("TOPLEFT", r, "TOPLEFT", S.S3, -28)
    r.desc:SetText(desc)
  end
  -- a control too wide to share the line with the label (a 500 column at WIDE) goes under it, right-aligned
  function r.layout()
    local w = tonumber(r:GetWidth()) or 0
    local cw = r.control and (tonumber(r.control:GetWidth()) or 0) or 0
    local need = UI.TextWidth("ROW_TITLE", r.label:GetText()) + 1
    local room = math.max(1, w - 2 * S.S3 - (cw > 0 and (cw + S.S2) or 0))
    local stack = r.control ~= nil and not desc and cw > 0 and need > room and w > 0
    r.stacked = stack
    if stack then room = math.max(1, w - 2 * S.S3) end
    r.label:SetWidth(math.min(room, need))
    if r.desc then r.desc:SetWidth(math.max(1, math.min(520, w - 2 * S.S3))) end
    -- (anchored again only when the control or its line changes: a secure control is never moved in combat)
    local key = stack and "stack" or "line"
    if r.control and (r.anchored ~= r.control or r.anchoredAs ~= key) then
      r.anchored, r.anchoredAs = r.control, key
      r.control:ClearAllPoints()
      if stack then r.control:SetPoint("TOPRIGHT", r, "TOPRIGHT", -S.S3, -UI.H.SETTING)
      else r.control:SetPoint("RIGHT", r, "RIGHT", -S.S3, desc and (h / 2 - S.S2 - UI.LINE_H.ROW_TITLE / 2) or 0) end
    end
    local nh = stack and (UI.H.SETTING + UI.H.CONTROL + S.S2) or h
    if nh ~= r.ebH then r.ebH = nh; r:SetHeight(nh) end
  end
  function r.SetControl(_, f)
    r.control = f
    pcall(r.layout)
    return f
  end
  function r.SetDesc(_, t) if r.desc then r.desc:SetText(t or "") end end
  r:HookScript("OnSizeChanged", function() pcall(r.layout) end)
  return r
end

function UI.ClassColor(classFile)
  local c = classFile and (RAID_CLASS_COLORS or {})[classFile]
  if c then return c.r, c.g, c.b end
  return unpackc(C.ink)
end

-- ── main window (docs/UX_OVERHAUL.md 2.7 Chrome) ───────────────────────────────────────────────────────────────
-- A 1 px black edge; the title bar (h 40) with the mark, the wordmark, the status chip and the close button; the
-- sidebar (168 wide) with one row per host (h 36 from y 48, Settings pinned to the bottom); the hosts' content
-- frames cover the whole window, so their own coordinates are window coordinates (UI.G).
local frame
local tabs = {}      -- { {name=, build=, order=, btn=, content=, built=} }
local activeName
local function paneKey(label) return (label:lower():gsub("%s+", "")) end
UI.paneKey = paneKey

-- old window keys (0.9.51) and where they live now (3.1, the rows active tonight)
UI.ALIASES = {
  ["Combat"] = { "Dungeons", "runs" },
  ["Combat/dungeons"] = { "Dungeons", "runs" },
  ["Combat/fights"] = { "Home", "fights" },
  ["Combat/deaths"] = { "Home", "deaths" },
  ["Home/overview"] = { "Home", "now" },
  ["Home/timeline"] = { "Home", "activity" },
  -- the auctions are a breakdown of Gold now (4.9): the old key opens Gold on Auction house
  ["Loot/auctions"] = { "Loot", "gold", function() if ns.Gold and ns.Gold.open then ns.Gold.open("all", "auctions") end end },
  -- Quests fold into Leveling and Crafting into Professions (4.10, 4.11); Settings > Capture and Data are one page,
  -- Data and sync, and Gold is named for what it sets (4.12)
  ["Character/quests"] = { "Character", "leveling" },
  ["Character/crafting"] = { "Character", "professions" },
  ["Settings/capture"] = { "Settings", "data" },
  ["Settings/gold"] = { "Settings", "golddisplay" },
}
-- a host and pane key from any name the addon or a saved setting uses (old keys pass through the aliases)
function UI.Resolve(name, sub)
  if type(name) ~= "string" then return nil, nil end
  local key = type(sub) == "string" and paneKey(sub) or nil
  local a = (key and UI.ALIASES[name .. "/" .. key]) or (not key and UI.ALIASES[name])
  if a then return a[1], a[2], a[3] end
  if name == "Combat" then return "Dungeons", key end
  return name, key
end

-- the settings keys of the new window (3.1), their defaults, and the migration of a 0.9.51 save
UI.SETTING_DEFAULTS = {
  lastTab = "Home", lastSub = "now", fightsView = "important", itemsQuality = "green", itemsMode = "newest",
  sessionsShowShort = false, goldPeriod = "session", welcomeDone = false, advancedOpen = false,
}
function UI.MigrateSettings(s)
  if type(s) ~= "table" then return end
  -- a save that dismissed the old welcome card has seen Everbuff: the first-run guide (4.13) is done for it
  if s.onboarded ~= nil then
    if s.onboarded == true and s.welcomeDone == nil then s.welcomeDone = true end
    s.onboarded = nil
  end
  for k, v in pairs(UI.SETTING_DEFAULTS) do if s[k] == nil then s[k] = v end end
  local tab, sub = UI.Resolve(s.lastTab, s.lastSub)
  local known = false
  for _, t in ipairs(tabs) do
    if t.name == tab then
      known = true
      if t.host then
        local ok, first = false, nil
        for _, pn in ipairs(t.panes) do
          if pn.key == sub then ok = true end
          if not first or pn.order < first.order then first = pn end
        end
        if not ok then sub = first and first.key or nil end
      end
    end
  end
  if not known then tab, sub = "Home", "now" end
  s.lastTab, s.lastSub = tab, sub
  local sc = tonumber(s.winScale)
  if sc and sc < UI.SCALE_MIN then s.winScale = UI.SCALE_MIN end
end

local NAV_ICONS = {
  ["Home"]      = "Interface\\Icons\\INV_Misc_Map_01",
  ["Dungeons"]  = "Interface\\GossipFrame\\BattleMasterGossipIcon",
  ["Loot"]      = "Interface\\Icons\\INV_Misc_Coin_01",
  ["Character"] = "Interface\\Icons\\INV_Misc_Book_09",
  ["Settings"]  = "Interface\\Buttons\\UI-OptionsButton",
}
UI.NAV_ICONS = NAV_ICONS

local function styleTabButton(t, active)
  local b = t.btn
  if not b then return end
  if active then
    b.bg:SetColorTexture(unpackc(C.raised)); b.bg:Show()
    b.accent:Show()
    b.text:SetTextColor(unpackc(C.fg))
    if b.icon then b.icon:SetVertexColor(unpackc(C.fg)) end
  else
    b.bg:Hide(); b.accent:Hide()
    b.text:SetTextColor(unpackc(C.fgMuted))
    if b.icon then b.icon:SetVertexColor(unpackc(C.fgMuted)) end
  end
end
local function hostCtl(t)
  return t.ctl or (t.content and (t.content.subtabs or t.content.tabs)) or nil
end
local function selectTab(name)
  if not frame then return end
  for _, t in ipairs(tabs) do
    local on = (t.name == name)
    -- leaving a host (or opening it again from the sidebar) closes its detail page: the list is what reopens
    local ctl = hostCtl(t)
    if ctl and ctl.back and ctl.onBack then pcall(ctl.onBack) end
    styleTabButton(t, on)
    if on then
      if not t.built then
        t.content = CreateFrame("Frame", nil, frame.contentHost)
        t.content:SetAllPoints(frame.contentHost)
        local ok, err = pcall(t.build, t.content)
        t.buildError = (not ok) and tostring(err) or nil      -- surfaced in Sync + the test suite
        if not ok then
          local fs = UI.Text(t.content, "BODY", "bad")
          fs:SetPoint("TOPLEFT", t.content, "TOPLEFT", G.TEXT_L, -G.CONTENT_TOP); fs:SetText("Error building tab: " .. tostring(err))
        end
        t.built = true
        local c2 = hostCtl(t)
        if c2 then c2.ebTabName = t.name end
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
  if ns.DB and ns.DB.settings then ns.DB.settings.lastTab = name end
end
UI.activeTab = function() return activeName end

-- the status chip's facts (one place, read on show): what the addon can know about its capture and the desktop app
function UI.StatusState()
  local sess = ns.Recorder and ns.Recorder.active()
  local aclOn, combatOn = false, false
  if ns.Logging and ns.Logging.state then aclOn, combatOn = ns.Logging.state() end
  local sync = ns.SyncState and ns.SyncState() or { waiting = 0 }
  local now = (GetServerTime and GetServerTime()) or time()
  local la = sync.lastAck
  local stale = la ~= nil and type(la.at) == "number" and (now - la.at) > 3 * 86400 and (sync.waiting or 0) >= 1
  local st = { sess = sess, acl = aclOn, combat = combatOn, waiting = sync.waiting or 0, lastAck = la, now = now }
  if sess and not combatOn then st.text, st.dot, st.textColor = "Recording, combat log off", "warn", "warn"
  elseif sess and stale then st.text, st.dot, st.textColor = "Recording, desktop app not seen", "warn", "warn"
  elseif sess then st.text, st.dot, st.textColor = "Recording", "accent", "fgSubtle"
  elseif IsInInstance and IsInInstance() then st.text, st.dot, st.textColor = "Starting", "warn", "fgSubtle"
  else st.text, st.dot, st.textColor = "Standing by", "fgFaint", "fgSubtle" end
  return st
end
local function chipTip(tip)
  local st = UI.StatusState()
  local first = st.text
  if st.sess then
    local zone = (GetRealZoneText and GetRealZoneText()) or st.sess.context
    local len = st.sess.startedEpoch and UI.fmtDur(st.now - st.sess.startedEpoch, { minutes = true }) or nil
    first = "Recording" .. (zone and zone ~= "" and (" \194\183 " .. zone) or "") .. (len and (" \194\183 session " .. len) or "")
  end
  tip:AddLine(first, 1, 1, 1)
  if st.lastAck and st.lastAck.at then
    tip:AddLine("Desktop app picked up your data " .. UI.fmtDur(math.max(0, st.now - st.lastAck.at), { minutes = true }) .. " ago", 0.78, 0.79, 0.80, true)
  else tip:AddLine("Desktop app: not seen yet", 0.78, 0.79, 0.80, true) end
  tip:AddLine(UI.plural(st.waiting, "pull") .. " not saved yet by the desktop app", 0.78, 0.79, 0.80, true)
  if st.sess and st.combat and not st.acl then tip:AddLine("Advanced combat logging is off", 0.78, 0.79, 0.80, true) end
end

local function buildFrame()
  if frame then return end
  local f = CreateFrame("Frame", "EverbuffFrame", UIParent, "BackdropTemplate")
  frame = f
  local st = ns.DB and ns.DB.settings
  if st then UI.MigrateSettings(st) end
  local ws = st and st.winSize
  f:SetSize(UI.clampWinSize(ws and ws.w, ws and ws.h))
  f:SetScale(math.max(UI.SCALE_MIN, (st and tonumber(st.winScale)) or 1))
  local pos = st and st.winPos
  if pos and type(pos.point) == "string" then f:SetPoint(pos.point, UIParent, pos.point, pos.x or 0, pos.y or 0)
  else f:SetPoint("CENTER") end
  f:SetFrameStrata("HIGH")
  f:SetBackdrop(BOX_BD)
  f:SetBackdropColor(unpackc(C.canvas)); f:SetBackdropBorderColor(0, 0, 0, 1)   -- the 1 px black edge (BORDER)
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
  -- resizable from the 16 px grip at the bottom right (inset 4), inside 900x580 to 1600x1000, persisted
  f:SetResizable(true)
  if f.SetResizeBounds then f:SetResizeBounds(UI.WIN_MIN_W, UI.WIN_MIN_H, UI.WIN_MAX_W, UI.WIN_MAX_H)
  elseif f.SetMinResize then f:SetMinResize(UI.WIN_MIN_W, UI.WIN_MIN_H); if f.SetMaxResize then f:SetMaxResize(UI.WIN_MAX_W, UI.WIN_MAX_H) end end
  local grip = CreateFrame("Button", nil, f)
  grip:SetSize(16, 16); grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -S.S1, S.S1)
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

  -- title bar: y 0 to 40, sunken, a 1 px rule at y 39
  local bar = CreateFrame("Frame", nil, f)
  bar:SetPoint("TOPLEFT", f, "TOPLEFT", G.BORDER, -G.BORDER); bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -G.BORDER, -G.BORDER)
  bar:SetHeight(G.TITLE_H - G.BORDER)
  local barBg = bar:CreateTexture(nil, "BACKGROUND"); barBg:SetAllPoints(bar); barBg:SetColorTexture(unpackc(C.sunken))
  local barRule = bar:CreateTexture(nil, "ARTWORK"); barRule:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0); barRule:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0); barRule:SetHeight(1)
  barRule:SetColorTexture(unpackc(C.line))
  f.bar = bar
  local mark = bar:CreateTexture(nil, "ARTWORK")
  mark:SetSize(20, 20); mark:SetPoint("TOPLEFT", f, "TOPLEFT", S.S4, -10)
  mark:SetTexture("Interface\\AddOns\\EverbuffJournal\\media\\mark")
  local brand = UI.Text(bar, "WORDMARK", "fg")
  brand:SetPoint("LEFT", f, "TOPLEFT", 44, -20)
  brand:SetText("everbuff")
  f.wordmark = brand
  local brandHit = CreateFrame("Frame", nil, bar)
  brandHit:SetPoint("TOPLEFT", f, "TOPLEFT", S.S4, -S.S2); brandHit:SetSize(44 - S.S4 + UI.TextWidth("WORDMARK", "everbuff"), 24)
  UI.SetTip(brandHit, { title = "Everbuff " .. tostring(ns.VERSION) .. " \194\183 type /eb help for every command" })
  f.brandHit = brandHit

  -- close: 24 x 24, its box edge on BOX_R
  local close = CreateFrame("Button", nil, bar)
  close:SetSize(G.CLOSE, G.CLOSE); close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -G.BOX_R_INSET, -S.S2)
  local cbg = close:CreateTexture(nil, "BACKGROUND"); cbg:SetAllPoints(close); cbg:SetColorTexture(unpackc(C.hover)); cbg:Hide()
  local cg = UI.Glyph(close, "clear", 10, "fgMuted"); cg:SetPoint("CENTER", close, "CENTER", 0, 0)
  close:SetScript("OnEnter", function() cbg:Show(); cg:SetColor("fg") end)
  close:SetScript("OnLeave", function() cbg:Hide(); cg:SetColor("fgMuted") end)
  close:SetScript("OnClick", function() UI.Click(); f:Hide() end)
  UI.SetTip(close, { title = "Close", text = "Esc closes the window too." })
  f.close = close

  -- the status chip: an 8 px dot and a sentence, its right edge at W - 56; a click opens the capture settings
  local chip = CreateFrame("Button", nil, bar)
  chip:SetHeight(UI.H.CONTROL); chip:SetPoint("TOPRIGHT", f, "TOPRIGHT", -G.CHIP_RIGHT, -S.S2)
  local chipBg = chip:CreateTexture(nil, "BACKGROUND"); chipBg:SetAllPoints(chip); chipBg:SetColorTexture(unpackc(C.hover)); chipBg:Hide()
  chip.dot = UI.Glyph(chip, "dot", 8, "accent"); chip.dot:SetPoint("LEFT", chip, "LEFT", S.S2, 0)
  chip.text = UI.Text(chip, "META", "fgSubtle"); chip.text:SetPoint("LEFT", chip, "LEFT", S.S2 + 8 + 6, 0)
  chip:SetScript("OnEnter", function(s) chipBg:Show(); UI.ShowTip(s, chipTip, "ANCHOR_BOTTOMLEFT") end)
  chip:SetScript("OnLeave", function(s) chipBg:Hide(); if s.ebTipShown and GameTooltip then GameTooltip:Hide() end; s.ebTipShown = nil end)
  chip:SetScript("OnClick", function() UI.Click(); UI.Open("Settings", "data") end)
  f.chip = chip

  -- the sidebar: x 0 to 168, sunken, a 1 px rule at x 167
  local strip = CreateFrame("Frame", nil, f)
  strip:SetPoint("TOPLEFT", f, "TOPLEFT", G.BORDER, -G.TITLE_H); strip:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", G.BORDER, G.BORDER)
  strip:SetWidth(G.SIDEBAR_W - 1 - G.BORDER)
  local stripBg = strip:CreateTexture(nil, "BACKGROUND"); stripBg:SetAllPoints(strip); stripBg:SetColorTexture(unpackc(C.sunken))
  local stripRule = f:CreateTexture(nil, "ARTWORK")
  stripRule:SetPoint("TOPLEFT", f, "TOPLEFT", G.SIDEBAR_W - 1, -G.TITLE_H); stripRule:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", G.SIDEBAR_W - 1, G.BORDER); stripRule:SetWidth(1)
  stripRule:SetColorTexture(unpackc(C.line))
  f.strip = strip

  -- the hosts draw in window coordinates
  local host = CreateFrame("Frame", nil, f)
  host:SetAllPoints(f)
  f.contentHost = host

  table.sort(tabs, function(a, b) return a.order < b.order end)
  local function makeButton(t)
    local b = CreateFrame("Button", nil, f)
    b:SetSize(G.NAV_W, UI.H.NAV)
    b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints(b); b.bg:Hide()
    b.hover = b:CreateTexture(nil, "HIGHLIGHT"); b.hover:SetAllPoints(b); b.hover:SetColorTexture(unpackc(C.hover, 0.6))
    b.accent = b:CreateTexture(nil, "OVERLAY"); b.accent:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0); b.accent:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0); b.accent:SetWidth(3)
    b.accent:SetColorTexture(unpackc(C.accent)); b.accent:Hide()
    local ic = NAV_ICONS[t.name]
    if ic then
      local icon = b:CreateTexture(nil, "ARTWORK")
      icon:SetSize(16, 16); icon:SetPoint("LEFT", b, "LEFT", G.NAV_ICON_X - G.NAV_X, 0); icon:SetTexture(ic)
      if icon.SetDesaturated then icon:SetDesaturated(true) end
      b.icon = icon
    end
    local fs = UI.Text(b, "ROW_TITLE", "fgMuted")
    fs:SetPoint("LEFT", b, "LEFT", G.NAV_LABEL_X - G.NAV_X, 0); fs:SetText(t.name)
    b.text = fs
    b:SetScript("OnEnter", function(s) if activeName ~= t.name then s.text:SetTextColor(unpackc(C.fg)) end end)
    b:SetScript("OnLeave", function() styleTabButton(t, activeName == t.name) end)
    b:SetScript("OnClick", function() UI.Click(); selectTab(t.name) end)
    if t.subtitle then UI.SetTip(b, { title = t.name, text = t.subtitle }) end
    t.btn = b
    styleTabButton(t, false)
    return b
  end
  local i = 0
  for _, t in ipairs(tabs) do
    local b = makeButton(t)
    if t.pin == "bottom" then b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", G.NAV_X, G.BOTTOM)
    else
      b:SetPoint("TOPLEFT", f, "TOPLEFT", G.NAV_X, -(G.NAV_TOP + i * UI.H.NAV))
      i = i + 1
    end
  end

  -- live status on the title bar
  f:SetScript("OnShow", function()
    UI.refreshStatus()
    if not f.ticker then f.ticker = C_Timer.NewTicker(2, UI.refreshStatus) end
  end)
  f:SetScript("OnHide", function()
    if f.ticker then f.ticker:Cancel(); f.ticker = nil end
  end)
  f:Hide()  -- CreateFrame shows by default; start hidden so the first Toggle opens (not hides) it
end

function UI.refreshStatus()
  if not (frame and frame:IsShown()) then return end
  local st = UI.StatusState()
  local chip = frame.chip
  chip.dot:SetColor(st.dot)
  chip.text:SetText(st.text); chip.text:SetTextColor(unpackc(C[st.textColor]))
  chip:SetWidth(S.S2 + 8 + 6 + UI.TextWidth("META", st.text) + S.S2)
  frame.statusState = st
end

-- ── public API ────────────────────────────────────────────────────────────────

-- order: lower shows higher in the sidebar. pin: "bottom" anchors the row to the bottom (Settings).
-- desc: the row's tooltip, what the host answers.
function UI.registerTab(order, name, build, onShow, group, pin, desc)
  tabs[#tabs + 1] = { order = order, name = name, build = build, onShow = onShow, group = group, pin = pin, subtitle = desc }
end

-- ── HOSTS: one sidebar row each (Home, Dungeons, Character, Loot), their panes on one row of sub-tabs. A pane
--    is built lazily on first select into its content box (BOX_L to BOX_R, CONTENT_TOP to the bottom margin)
--    and refreshed (onShow) every time it is selected. The host draws no title: the sidebar row and the sub-tab
--    name the page. Pane key = label lowercased without spaces ("By dungeon" -> "bydungeon").
local hosts = {}
-- the panes that are not rebuilt on the kit yet (docs/UX_OVERHAUL.md 0.3): clamped to the main column
UI.LEGACY_PANES = {}
local function buildHost(t, content)
  table.sort(t.panes, function(a, b) return a.order < b.order end)
  local items = {}
  t.paneByKey = {}
  for _, pn in ipairs(t.panes) do items[#items + 1] = { key = pn.key, label = pn.label, desc = pn.desc }; t.paneByKey[pn.key] = pn end
  t.ctl = UI.SubTabs(content, items, { onSelect = function(key)
    local pn = t.paneByKey[key]; if not pn then return end
    if ns.DB and ns.DB.settings and activeName == t.name then ns.DB.settings.lastSub = key end
    if not pn.built then
      if UI.LEGACY_PANES[t.name .. "/" .. key] then t.ctl.clamp(key) end
      pn.content = CreateFrame("Frame", nil, t.ctl.panes[key]); pn.content:SetAllPoints(t.ctl.panes[key])
      pn.content.ebHostCtl, pn.content.ebControls = t.ctl, t.ctl.controls[key]
      local ok, err = pcall(pn.build, pn.content)
      pn.buildError = (not ok) and tostring(err) or nil
      if not ok then
        local fs = UI.Text(pn.content, "BODY", "bad"); fs:SetPoint("TOPLEFT", pn.content, "TOPLEFT", S.S3, 0); fs:SetText("Error building pane: " .. tostring(err))
      end
      pn.built = true
    end
    if pn.onShow then local ok2, e2 = pcall(pn.onShow); pn.showError = (not ok2) and tostring(e2) or nil end
  end })
  t.ctl.ebTabName = t.name
  content.tabs = t.ctl
  -- the sub-tabs whose page has something to show now (a pane's `visible` function; none: always). When the page on
  -- screen loses its tab, the host goes to its first tab.
  t.refreshTabs = function()
    local hidden, first = {}, nil
    for _, pn in ipairs(t.panes) do
      local ok, vis = true, true
      if pn.visible then ok, vis = pcall(pn.visible) end
      if ok and vis == false then hidden[pn.key] = true elseif not first then first = pn.key end
    end
    t.ctl.setHidden(hidden)
    if t.ctl.active and hidden[t.ctl.active] and first and not t.ctl.back then t.ctl.select(first) end
    return hidden
  end
  local hidden = t.refreshTabs()
  local want = ns.DB and ns.DB.settings and ns.DB.settings.lastTab == t.name and ns.DB.settings.lastSub
  if want and t.paneByKey[want] and not hidden[want] then t.ctl.select(want)
  else for _, it in ipairs(items) do if not hidden[it.key] then t.ctl.select(it.key); break end end end
end
function UI.registerHost(order, name, desc)
  -- (a pane registered before its host made the host with a placeholder order: the host's own call sets it)
  if hosts[name] then
    if desc then hosts[name].subtitle = desc end
    if hosts[name].autoOrder and order then hosts[name].order, hosts[name].autoOrder = order, nil end
    return hosts[name]
  end
  local t = { order = order, name = name, subtitle = desc, panes = {}, host = true }
  t.build = function(content) buildHost(t, content) end
  t.onShow = function()
    if t.refreshTabs then t.refreshTabs() end
    local pn = t.ctl and t.paneByKey and t.paneByKey[t.ctl.active]
    if pn and pn.built and pn.onShow then pn.onShow() end
  end
  tabs[#tabs + 1] = t; hosts[name] = t
  return t
end
-- desc: the sub-tab's tooltip, one sentence on what the page answers
-- visible: optional, a function that answers false while the page has nothing to show (its sub-tab is then hidden)
function UI.registerPane(hostName, order, label, build, onShow, desc, visible)
  local h = hosts[hostName]
  if not h then h = UI.registerHost(50, hostName, nil); h.autoOrder = true end
  h.panes[#h.panes + 1] = { order = order, key = paneKey(label), label = label, build = build, onShow = onShow, desc = desc, visible = visible }
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

-- Open the window on a tab; `sub` selects a pane of a host ("Home", "fights"). Old keys pass through UI.ALIASES.
-- With no name the window opens where it was, or on the saved lastTab / lastSub.
function UI.Open(name, sub)
  if ns.blockedInCombat and ns.blockedInCombat() then return end
  buildFrame()
  frame:Show()
  if not name then
    if activeName then name = activeName
    else
      local st = ns.DB and ns.DB.settings
      if st then UI.MigrateSettings(st); name, sub = st.lastTab, st.lastSub end
    end
  end
  local after
  name, sub, after = UI.Resolve(name, sub)
  local known = false
  for _, t in ipairs(tabs) do if t.name == name then known = true end end
  if not known then name, sub = tabs[1] and tabs[1].name, nil end
  selectTab(name)
  local t
  for _, x in ipairs(tabs) do if x.name == name then t = x end end
  local ctl = t and hostCtl(t)
  -- (a page whose sub-tab is hidden now has nothing to show: the host stays on the page it has)
  if t and t.refreshTabs then t.refreshTabs() end
  if sub and ctl and ctl.select and ctl.panes and ctl.panes[sub] and not (ctl.hidden and ctl.hidden[sub]) then ctl.select(sub) end
  if after then pcall(after) end
end

-- ── UI.Tabs: with no `top` (a host's or Settings' own sub-tabs) it is UI.SubTabs, the control row. With a `top`
--    (a filter inside an unconverted pane) it is the 0.9.51 bordered pane with the tabs on its top edge, kept as a
--    shim until that pane's own step (docs/UX_OVERHAUL.md 0.3). items = { { key=, label= }, ... }.
--    Returns ctl with ctl.panes[key] (parent your content into these), ctl.select(key), ctl.active.
function UI.Tabs(parent, items, top, sidePad, opts)
  if top == nil then return UI.SubTabs(parent, items, opts) end
  sidePad = sidePad or 14; opts = opts or {}
  -- On a converted host (a pane with a control row) a second tab row under the sub-tabs would make two rows with a
  -- mint underline: the choice becomes a filter button ("All" and a chevron) at the right of the control row, and the pane is
  -- the pane's own frame, with no border, so its list starts at BOX_L with its text on TEXT_L.
  local holder = parent
  while holder and not rawget(holder, "ebControls") do holder = holder.GetParent and holder:GetParent() or nil end
  if holder and opts.shared then
    local ctl = { panes = {}, tabs = {}, kit = true }
    local pane = CreateFrame("Frame", nil, parent); pane:SetAllPoints(parent)
    ctl.host, ctl.content = pane, pane
    for _, it in ipairs(items) do ctl.panes[it.key] = pane end
    local labels = {}
    for _, it in ipairs(items) do labels[it.key] = it.label end
    local first = items[1] and items[1].key
    local fb = UI.FilterButton(holder.ebControls, { default = first, label = labels[first] or "",
      items = function()
        local out = {}
        for _, it in ipairs(items) do out[#out + 1] = { it.key, it.label, it.key == ctl.active } end
        return out
      end,
      onPick = function(key) ctl.select(key) end })
    fb:SetPoint("TOPRIGHT", holder.ebControls, "TOPRIGHT", 0, 0)
    ctl.filter = fb
    function ctl.style() fb:SetValue(ctl.active, labels[ctl.active] or "") end
    function ctl.select(key)
      if not labels[key] then key = first end
      ctl.active = key
      ctl.style()
      if opts.onSelect then opts.onSelect(key) end
    end
    return ctl
  end
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
-- Settings > General, "Reset window size and position": the smallest size, centred, the saved place forgotten
function UI.ResetWindow()
  if ns.blockedInCombat and ns.blockedInCombat() then return false end
  if ns.DB and ns.DB.settings then ns.DB.settings.winPos = nil end
  UI.SetWindowSize(UI.WIN_MIN_W, UI.WIN_MIN_H)
  if frame then frame:ClearAllPoints(); frame:SetPoint("CENTER") end
  return true
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
