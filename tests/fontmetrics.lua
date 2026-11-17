-- Real advance widths from the addon's own TrueType files (Everbuff/media/fonts), for tests/render_html.lua.
-- Reads the cmap (format 4 or 12), hhea, hmtx and head tables and answers the width of a string in pixels at a
-- font size, the way a renderer without kerning or ligatures lays it out (WoW's font strings draw glyph by glyph).
--   local FM = dofile("tests/fontmetrics.lua")
--   local inter = FM.load("Everbuff/media/fonts/Inter-Medium.ttf")
--   inter:width("Linen Cloth", 11)  --> pixels
local FM = {}

local function u16(s, o) local a, b = s:byte(o + 1, o + 2); return a * 256 + b end
local function s16(s, o) local v = u16(s, o); return v >= 32768 and v - 65536 or v end
local function u32(s, o) local a, b, c, d = s:byte(o + 1, o + 4); return ((a * 256 + b) * 256 + c) * 256 + d end

-- the code points of a UTF-8 string
function FM.codepoints(str)
  local out, i, n = {}, 1, #str
  while i <= n do
    local c = str:byte(i)
    local cp, len = c, 1
    if c >= 0xF0 then cp, len = c % 8, 4 elseif c >= 0xE0 then cp, len = c % 16, 3 elseif c >= 0xC0 then cp, len = c % 32, 2 end
    for j = 1, len - 1 do cp = cp * 64 + ((str:byte(i + j) or 128) % 64) end
    out[#out + 1] = cp; i = i + len
  end
  return out
end

local Font = {}
Font.__index = Font

function FM.load(path)
  local fh = assert(io.open(path, "rb"), "font not found: " .. path)
  local s = fh:read("*a"); fh:close()
  local tables = {}
  for i = 0, u16(s, 4) - 1 do
    local r = 12 + i * 16
    tables[s:sub(r + 1, r + 4)] = u32(s, r + 8)
  end
  local head, hhea, hmtx, cmap = tables.head, tables.hhea, tables.hmtx, tables.cmap
  assert(head and hhea and hmtx and cmap, "not a TrueType font: " .. path)
  local f = setmetatable({ path = path, upem = u16(s, head + 18), s = s, hmtx = hmtx, nh = u16(s, hhea + 34),
    ascent = s16(s, hhea + 4), descent = s16(s, hhea + 6), cache = {} }, Font)
  -- pick the Unicode subtable: (3,10) format 12 covers everything, (3,1) or (0,x) format 4 the BMP
  local best, bestFmt
  for i = 0, u16(s, cmap + 2) - 1 do
    local r = cmap + 4 + i * 8
    local plat, enc, off = u16(s, r), u16(s, r + 2), u32(s, r + 4)
    local fmt = u16(s, cmap + off)
    if fmt == 12 and (plat == 3 or plat == 0) then best, bestFmt = cmap + off, 12
    elseif fmt == 4 and (plat == 3 or plat == 0) and bestFmt ~= 12 then best, bestFmt = cmap + off, 4 end
  end
  assert(best, "no Unicode cmap in " .. path)
  f.cm, f.cmFmt = best, bestFmt
  return f
end

function Font:glyph(cp)
  local s, t = self.s, self.cm
  if self.cmFmt == 12 then
    local n = u32(s, t + 12)
    local lo, hi = 0, n - 1
    while lo <= hi do
      local mid = math.floor((lo + hi) / 2)
      local r = t + 16 + mid * 12
      local a, b = u32(s, r), u32(s, r + 4)
      if cp < a then hi = mid - 1 elseif cp > b then lo = mid + 1 else return u32(s, r + 8) + (cp - a) end
    end
    return 0
  end
  local segX2 = u16(s, t + 6)
  local ends, starts = t + 14, t + 16 + segX2
  local deltas, ranges = starts + segX2, starts + 2 * segX2
  for i = 0, segX2 / 2 - 1 do
    local e = u16(s, ends + i * 2)
    if cp <= e then
      local st = u16(s, starts + i * 2)
      if cp < st then return 0 end
      local ro = u16(s, ranges + i * 2)
      if ro == 0 then return (cp + u16(s, deltas + i * 2)) % 65536 end
      local g = u16(s, ranges + i * 2 + ro + (cp - st) * 2)
      if g == 0 then return 0 end
      return (g + u16(s, deltas + i * 2)) % 65536
    end
  end
  return 0
end

-- advance of one code point in font units
function Font:advance(cp)
  local a = self.cache[cp]
  if a then return a end
  local g = self:glyph(cp)
  local i = math.min(g, self.nh - 1)
  a = u16(self.s, self.hmtx + i * 4)
  self.cache[cp] = a
  return a
end

-- width in pixels of a plain string (no WoW escapes) at `size` px
function Font:width(str, size)
  local units = 0
  for _, cp in ipairs(FM.codepoints(str)) do units = units + self:advance(cp) end
  return units * size / self.upem
end

return FM
