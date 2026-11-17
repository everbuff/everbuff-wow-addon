-- Geometry of the stub's frames the way the client lays them out, with the addon's real fonts.
--
--   local G = dofile("tests/geometry.lua")
--   G.install(M)               -- GetWidth, GetHeight, GetSize, GetStringWidth, IsTruncated, GetFrameLevel answer
--                              -- from the resolved layout; M.textWidth measures with the TTF advance widths
--   G.resolve(frame [, cache]) -- the frame's absolute box { l, t, w, h }, y down, or nil when it cannot be placed
--
-- tests/wow_stub.lua records anchors, sizes, fonts and wrapping; this file resolves them: one or two points,
-- SetAllPoints, anchors to any region, nested frames, a scroll child at its scroll frame's top left. Text widths come
-- from tests/fontmetrics.lua (the TTF files in Everbuff/media/fonts), so the addon's own layout code
-- (GetStringWidth, IsTruncated, OnSizeChanged) sees what it sees in game. Used by tests/render_html.lua and by the
-- pane tests in tests/panes/.
local FM = dofile("tests/fontmetrics.lua")
local G = {}

G.FONT_DIR = "Everbuff/media/fonts/"
G.FACES = { ["Inter-Medium"] = true, ["Inter-SemiBold"] = true, ["ChakraPetch-Bold"] = true, ["ChakraPetch-SemiBold"] = true, ["ChakraPetch-Regular"] = true }
G.VIEW = { w = 1920, h = 1080 }   -- UIParent
G.MARGIN = 0                     -- UIParent's offset in the page (the renderer draws a margin around the window)

local metrics = {}
local function faceOf(file)
  local base = type(file) == "string" and file:match("([^\\/]+)%.[tT][tT][fF]$")
  if base and G.FACES[base] then return base end
  return "Inter-Medium"     -- a Blizzard template the addon did not map: the closest stand-in
end
local function metricsOf(face)
  metrics[face] = metrics[face] or FM.load(G.FONT_DIR .. face .. ".ttf")
  return metrics[face]
end

-- the font of a font string or edit box: face, size, color, shadow (own settings over its font object's)
function G.fontOf(f)
  local fo = type(f._font) == "table" and f._font or nil
  local file = f._file or (fo and fo._file)
  local size = f._size or (fo and fo._size) or 12
  return { face = faceOf(file), fallback = file == nil, size = size,
    color = f._color or (fo and fo._color) or { 1, 1, 1, 1 }, shadow = f._shadow or (fo and fo._shadow),
    spacing = f._spacing or (fo and fo._spacing) or 0 }
end

-- WoW markup as runs of { text = s } | { color = {r,g,b} } | { reset = true } | { icon = px } | { br = true }
local function hexc(h) return { tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255 } end
function G.parse(s, size)
  s = tostring(s or "")
  local runs, buf, i, n = {}, {}, 1, #s
  local function flush() if #buf > 0 then runs[#runs + 1] = { text = table.concat(buf) }; buf = {} end end
  while i <= n do
    local c = s:sub(i, i)
    if c == "|" then
      local nx = s:sub(i + 1, i + 1)
      if nx == "c" and s:sub(i + 2, i + 9):match("^%x%x%x%x%x%x%x%x$") then flush(); runs[#runs + 1] = { color = hexc(s:sub(i + 4, i + 9)) }; i = i + 10
      elseif nx == "r" then flush(); runs[#runs + 1] = { reset = true }; i = i + 2
      elseif nx == "H" then local e = s:find("|h", i + 2, true); i = e and e + 2 or n + 1             -- link target, text follows
      elseif nx == "h" then i = i + 2                                                              -- link end
      elseif nx == "T" or nx == "A" then
        local close = nx == "T" and "|t" or "|a"
        local e = s:find(close, i + 2, true) or n
        local spec = s:sub(i + 2, e - 1)
        local h = tonumber(spec:match("^[^:]*:(%-?%d+)") or "") or 0
        flush(); runs[#runs + 1] = { icon = (h and h > 0) and h or size }; i = e + 2
      elseif nx == "n" then flush(); runs[#runs + 1] = { br = true }; i = i + 2
      elseif nx == "|" then buf[#buf + 1] = "|"; i = i + 2
      else buf[#buf + 1] = c; i = i + 1 end
    elseif c == "\n" then flush(); runs[#runs + 1] = { br = true }; i = i + 1
    else buf[#buf + 1] = c; i = i + 1 end
  end
  flush()
  return runs
end

-- the width of each line of a text, in pixels
local function lineWidths(runs, font)
  local fm = metricsOf(font.face)
  local lines, cur = {}, 0
  for _, r in ipairs(runs) do
    if r.text then cur = cur + fm:width(r.text, font.size)
    elseif r.icon then cur = cur + r.icon
    elseif r.br then lines[#lines + 1] = cur; cur = 0 end
  end
  lines[#lines + 1] = cur
  return lines
end
function G.naturalWidth(f, text)
  local font = G.fontOf(f)
  local best = 0
  for _, w in ipairs(lineWidths(G.parse(text or f.text, font.size), font)) do best = math.max(best, w) end
  return best
end
-- the number of lines a text takes at `width` with word wrap on (greedy, at spaces, as the client breaks;
-- a no-break space U+00A0 never breaks)
local function wrappedLines(f, width)
  local font = G.fontOf(f)
  local fm = metricsOf(font.face)
  local plain = {}
  for _, r in ipairs(G.parse(f.text, font.size)) do
    if r.text then plain[#plain + 1] = r.text elseif r.icon then plain[#plain + 1] = "\1" elseif r.br then plain[#plain + 1] = "\n" end
  end
  local text = table.concat(plain)
  local space = fm:width(" ", font.size)
  local count = 0
  for para in (text .. "\n"):gmatch("(.-)\n") do
    local lineW, lines = 0, 1
    -- runs of spaces keep their width (the client does not collapse "  ·  "); a break drops them
    for gap, word in para:gmatch("( *)([^ ]+)") do
      local w = 0
      for piece in word:gmatch("[^\1]+") do w = w + fm:width(piece, font.size) end
      w = w + select(2, word:gsub("\1", "")) * font.size
      local gw = #gap * space
      if lineW > 0 and lineW + gw + w > width + 0.5 then lines = lines + 1; lineW = w
      else lineW = lineW + (lineW > 0 and gw or 0) + w end
    end
    count = count + lines
  end
  return math.max(1, count)
end
function G.lineHeight(f) local font = G.fontOf(f); return font.size + font.spacing end
-- a text with a width wraps into it (unless wrap is off); without one it is as wide as its longest line
function G.textSize(f, w)
  local lines
  if w and w > 0 and f._wrap ~= false then lines = wrappedLines(f, w)
  else lines = #lineWidths(G.parse(f.text, G.fontOf(f).size), G.fontOf(f)) end
  if f._maxLines and f._maxLines > 0 then lines = math.min(lines, f._maxLines) end
  return w or G.naturalWidth(f), lines * G.lineHeight(f), lines
end

-- ── absolute boxes { l, t, w, h }, y down, from the recorded anchors ─────────────────────────────────────────
local guard = {}
local resolve
local function pointOn(b, p)
  local x = p:find("LEFT") and b.l or p:find("RIGHT") and (b.l + b.w) or (b.l + b.w / 2)
  local y = p:find("TOP") and b.t or p:find("BOTTOM") and (b.t + b.h) or (b.t + b.h / 2)
  return x, y
end
local function solve(f, C)
  local own_w = f._w and f._w > 0 and f._w or nil
  local own_h = f._h and f._h > 0 and f._h or nil
  local hx, vy = {}, {}
  for _, a in ipairs(f._pts) do
    local rel = a.rel or f.parentFrame
    local rb = rel and resolve(rel, C)
    if not rb then return nil end
    local x, y = pointOn(rb, a.rp)
    local p = a.p
    hx[#hx + 1] = { k = p:find("LEFT") and "l" or p:find("RIGHT") and "r" or "c", v = x + a.x }
    vy[#vy + 1] = { k = p:find("TOP") and "t" or p:find("BOTTOM") and "b" or "c", v = y - a.y }
  end
  local l, r, cx, t, b, cy
  for _, e in ipairs(hx) do if e.k == "l" then l = e.v elseif e.k == "r" then r = e.v else cx = e.v end end
  for _, e in ipairs(vy) do if e.k == "t" then t = e.v elseif e.k == "b" then b = e.v else cy = e.v end end
  local w = (l and r) and (r - l) or own_w
  if not w and f._isFS then w = G.naturalWidth(f) end
  w = w or 0                                      -- a frame without a width is 0 wide, as in the client
  if not l then l = r and (r - w) or cx and (cx - w / 2) end
  local h = (t and b) and (b - t) or own_h
  if not h and f._isFS then local _, th = G.textSize(f, ((l and r) or own_w) and w or nil); h = th end
  h = h or 0
  if not t then t = b and (b - h) or cy and (cy - h / 2) end
  if not l or not t then return nil end
  return { l = l, t = t, w = w, h = h }
end
resolve = function(f, C)
  if C and C[f] ~= nil then return C[f] or nil end
  if guard[f] then return nil end
  guard[f] = true
  local box
  if f == _G.UIParent then box = { l = G.MARGIN, t = G.MARGIN, w = G.VIEW.w, h = G.VIEW.h }
  elseif f._pts and #f._pts > 0 then box = solve(f, C)
  elseif f.parentFrame and f.parentFrame._scrollChild == f then
    local pb = resolve(f.parentFrame, C)          -- a scroll child sits at its scroll frame's top left, scrolled to 0
    if pb then box = { l = pb.l, t = pb.t, w = f._w or 0, h = f._h or 0 } end
  end
  guard[f] = nil
  if C then C[f] = box or false end
  return box
end
G.resolve = resolve

-- which addon file and line created a region (the renderer's data-src), skipping UI.lua's helpers when it can
local function srcOf()
  local helper
  for lv = 3, 30 do
    local info = debug.getinfo(lv, "Sl")
    if not info then break end
    local file = info.short_src and info.short_src:match("Everbuff[\\/]([%w_]+%.lua)")
    if file then
      if file ~= "UI.lua" then return file .. ":" .. tostring(info.currentline) end
      helper = helper or (file .. ":" .. tostring(info.currentline))
    end
  end
  return helper
end

-- answer the addon's size questions from the resolved layout. opts.src tags every region with the line that made it.
function G.install(M, opts)
  if G.installed then return end
  G.installed = true
  opts = opts or {}
  local probe = CreateFrame("Frame")
  local mt = getmetatable(probe)
  local base = mt.__index
  local function levelOf(f)
    if f._level then return f._level end
    local pa = f.parentFrame
    if not pa or pa == _G.UIParent then return 1 end
    return levelOf(pa) + 1
  end
  mt.__index = function(t, k)
    if k == "GetWidth" then return function(self) local b = resolve(self); return b and b.w or 0 end end
    if k == "GetHeight" then return function(self) local b = resolve(self); return b and b.h or 0 end end
    if k == "GetSize" then return function(self) local b = resolve(self); return b and b.w or 0, b and b.h or 0 end end
    if k == "GetStringWidth" or k == "GetUnboundedStringWidth" then return function(self) return self.text and G.naturalWidth(self) or 0 end end
    if k == "GetStringHeight" then return function(self) local b = resolve(self); local _, h = G.textSize(self, b and b.w); return h end end
    if k == "IsTruncated" then return function(self)
      local b = resolve(self); if not b or not self.text then return false end
      if self._wrap == false then return G.naturalWidth(self) > b.w + 0.5 end
      return select(2, G.textSize(self, b.w)) > b.h + 0.5
    end end
    if k == "GetFrameLevel" then return function(self) return levelOf(self) end end
    if opts.src and (k == "CreateFontString" or k == "CreateTexture") then
      local orig = base(t, k)
      return function(self, ...) local r = orig(self, ...); r._src = srcOf(); return r end
    end
    if k == "SetNormalTexture" or k == "SetPushedTexture" or k == "SetHighlightTexture" then return function(self) return self end end
    return base(t, k)
  end
  if opts.src then
    local cf = _G.CreateFrame
    _G.CreateFrame = function(...) local f = cf(...); f._src = srcOf(); return f end
  end
  M.textWidth = function(f) return f.text and G.naturalWidth(f) or 0 end
end

return G
