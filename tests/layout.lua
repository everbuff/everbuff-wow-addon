-- Layout audit for the headless suite (founder, 2026-11-17: "fix the overflowing txt problem cause you have alot of
-- that in tables and overview boxes"). tests/wow_stub.lua records every frame's parent, anchors, size, font and
-- wrapping; this file places the regions it can (anchored to their parent or to a sibling of the same parent) and
-- reports, for every visible text:
--   spill    the text runs past the right or bottom edge of a parent whose size is known
--   overlap  two texts of the same parent are drawn over each other (a wrapped table cell over the next row)
--   cut      a number shortened by the client's "..." (a fixed width with wrapping off); names may shorten, numbers never
--   clipped  a label drawn in capitals that carries the brand in lower case ("SAVED TO everbuff.gg") on a line only
--            as tall as its font: capitals have no tails, "gg" does, and a one-line text of a fixed width is cut at
--            its box (review round 3: the card label read close to "everbuff.qq"). L.CAPS names the roles.
-- Text widths come from the addon's TrueType files through tests/geometry.lua (set L.G); without it a text's width
-- is estimated per character from its font size, on the wide side of Inter and Chakra Petch.
local L = {}

local function fontSize(fs)
  local fo = fs._font
  if type(fo) == "table" and fo._size then return fo._size, fo end
  return 12, fo
end

-- the visible characters of a WoW string: color codes and hyperlinks unwrapped, an icon counts as one square
local function plain(s)
  s = tostring(s or "")
  s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1")
  local icons = 0
  s = s:gsub("|T.-|t", function() icons = icons + 1; return "" end)
  s = s:gsub("|n", "\n")
  return s, icons
end

local WIDE = "[MWmw@%%]"
local function charW(ch)
  if ch == " " then return 0.28 end
  if ch:match(WIDE) then return 0.85 end
  if ch:match("%d") then return 0.6 end
  if ch:match("%u") then return 0.68 end
  if ch:match("[%.,:;'!|il]") then return 0.3 end
  if ch:byte() and ch:byte() >= 128 then return 0.3 end   -- a byte of a UTF-8 sequence (the middle dot is two)
  return 0.55
end

-- the width of the longest line of `s` in a font of `size`, in pixels: the fonts' real advance widths when
-- tests/geometry.lua is loaded (L.G), else the estimate above
function L.textWidth(fs, s)
  if L.G then return math.ceil(L.G.naturalWidth(fs, s)) end
  local size, fo = fontSize(fs)
  local bold = (L.BOLD and L.BOLD[fo]) and 1.08 or 1
  local txt, icons = plain(s or fs.text)
  local best = 0
  for line in (txt .. "\n"):gmatch("(.-)\n") do
    local w = 0
    for ch in line:gmatch(".") do w = w + charW(ch) end
    best = math.max(best, w)
  end
  return math.ceil(best * size * bold + icons * size)
end

local function lineH(fs) return math.ceil(fontSize(fs) * 1.25) end

-- only the addon's own window (EverbuffFrame) is audited: the on-screen notification sizes itself from its text and
-- is what the desktop reads, so it is not changed without approval
local function inWindow(f)
  local n = 0
  while f and n < 60 do
    if f == _G.EverbuffFrame then return true end
    f = f.parentFrame; n = n + 1
  end
  return false
end
local function visible(f)
  if not inWindow(f) then return false end
  local n = 0
  while f and n < 60 do
    if f.shown == false then return false end
    f = f.parentFrame; n = n + 1
  end
  return true
end

-- the size of a frame: its own, or what its anchors span inside its parent; nil when unknown
local sizeOf
local placeIn   -- forward
local function hasText(f) return f._isFS and f.text ~= nil and plain(f.text):match("%S") ~= nil end

-- where a point sits on a box { l, t, w, h }
local function pointOn(b, p)
  local x = p:find("LEFT") and b.l or p:find("RIGHT") and (b.l + (b.w or 0)) or (b.l + (b.w or 0) / 2)
  local y = p:find("TOP") and b.t or p:find("BOTTOM") and (b.t + (b.h or 0)) or (b.t + (b.h or 0) / 2)
  return x, y
end

-- the box of the region a point is anchored to, in the coordinates of `f`'s parent; nil when it is elsewhere
local function relBox(f, rel, seen)
  local pa = f.parentFrame
  if rel == nil or rel == pa then
    local w, h = sizeOf(pa, seen)
    -- a scroll child starts at 1 x 1 and the client lays its rows out past it: not a box to measure against
    if w and w <= 2 then w = nil end
    if h and h <= 2 then h = nil end
    return { l = 0, t = 0, w = w, h = h }
  end
  if type(rel) == "table" and rel.parentFrame == pa and rel ~= f then return placeIn(rel, seen) end
  return nil
end

-- natural size of a text: its set width (wrapping into lines) or the estimate
local function textBox(f)
  local est = L.textWidth(f)
  local lh = lineH(f)
  local w = f._w and f._w > 0 and f._w or nil
  local lines = 1
  if w and f._wrap ~= false and est > w then lines = math.ceil(est / w) end
  if f._maxLines and f._maxLines > 0 then lines = math.min(lines, f._maxLines) end
  local nl = select(2, plain(f.text):gsub("\n", "")) or 0
  lines = math.max(lines, 1 + nl)
  return w or est, f._h and f._h > 0 and f._h or lines * lh, est, lines
end

-- the box of `f` inside its parent { l, t, w, h }, or nil when its anchors cannot be resolved
placeIn = function(f, seen)
  seen = seen or {}
  if seen[f] then return nil end
  seen[f] = true
  local pts = f._pts
  if not pts or #pts == 0 then seen[f] = nil; return nil end
  local w, h
  if f._isFS then w, h = textBox(f) else w, h = f._w, f._h end
  local xs, ys = {}, {}
  for _, a in ipairs(pts) do
    local rb = relBox(f, a.rel, seen)
    if not rb then seen[f] = nil; return nil end
    local rx, ry = pointOn(rb, a.rp)
    if (a.rp:find("RIGHT") and not rb.w) or (a.rp:find("BOTTOM") and not rb.h) then rx, ry = nil, nil end
    xs[#xs + 1] = { p = a.p, x = rx and (rx + a.x) }
    ys[#ys + 1] = { p = a.p, y = ry and (ry - a.y) }
  end
  -- horizontal: a LEFT and a RIGHT anchor fix the width; one anchor places the region by its own width
  local l, r
  for _, e in ipairs(xs) do
    if e.x then
      if e.p:find("LEFT") then l = e.x elseif e.p:find("RIGHT") then r = e.x end
    end
  end
  if l and r then w = r - l
  elseif l then -- placed by its left edge
  elseif r and w then l = r - w
  else
    for _, e in ipairs(xs) do if e.x and w and not e.p:find("LEFT") and not e.p:find("RIGHT") then l = e.x - w / 2 end end
  end
  local t, b
  for _, e in ipairs(ys) do
    if e.y then
      if e.p:find("TOP") then t = e.y elseif e.p:find("BOTTOM") then b = e.y end
    end
  end
  if t and b then h = b - t
  elseif t then
  elseif b and h then t = b - h
  else
    for _, e in ipairs(ys) do if e.y and h and not e.p:find("TOP") and not e.p:find("BOTTOM") then t = e.y - h / 2 end end
  end
  seen[f] = nil
  if not l or not t then return nil end
  return { l = l, t = t, w = w, h = h }
end

sizeOf = function(f, seen)
  if not f then return nil, nil end
  local w, h = f._w, f._h
  if (not w or not h) and f._pts and f.parentFrame then
    local b = placeIn(f, seen)
    if b then w, h = w or b.w, h or b.h end
  end
  return w, h
end

local function looksNumeric(s)
  local p = plain(s)
  return p:match("^%s*[%+%-]?[%d%.,%s:%%xgsc]+%s*$") ~= nil and p:match("%d") ~= nil
end

local function label(f)
  local s = plain(f.text):gsub("\n", " / ")
  return s:sub(1, 48)
end

-- audit every visible text the stub knows; returns a list of findings { kind, text, detail }
function L.audit(frames)
  local out, byParent = {}, {}
  L.placed, L.unplaced = 0, {}
  for _, f in ipairs(frames) do
    if hasText(f) and visible(f) then
      local b = placeIn(f)
      if not b then L.unplaced[#L.unplaced + 1] = f
      else L.placed = L.placed + 1
        byParent[f.parentFrame] = byParent[f.parentFrame] or {}
        table.insert(byParent[f.parentFrame], { f = f, b = b })
        local pw, ph = sizeOf(f.parentFrame)
        local _, _, est = textBox(f)
        -- a width of its own, or a LEFT and a RIGHT anchor: the text is drawn (and shortened) inside that width
        local boxW = f._w
        if not boxW then
          local hl, hr = false, false
          for _, p in ipairs(f._pts or {}) do if p.p:find("LEFT") then hl = true elseif p.p:find("RIGHT") then hr = true end end
          if hl and hr then boxW = b.w end
        end
        local drawnW = (boxW and f._wrap ~= false) and b.w or math.min(est, boxW or est)
        if boxW and f._wrap == false and est > boxW + 1 and looksNumeric(f.text) then
          out[#out + 1] = { kind = "cut", text = label(f), detail = ("needs %d px, has %d"):format(est, boxW) }
        end
        if boxW and f._wrap == false and L.CAPS and L.CAPS[f.ebRole] and plain(f.text):find("everbuff.gg", 1, true) then
          local has = (f._h and f._h > 0) and f._h or fontSize(f)   -- with no height of its own the line is its font size
          if has < lineH(f) then
            out[#out + 1] = { kind = "clipped", text = label(f), detail = ("line %d px, the lower case brand needs %d"):format(has, lineH(f)) }
          end
        end
        -- a parent of 2 px or less is a scroll child sized later, not a box
        if pw and pw > 2 and b.l + drawnW > pw + 1 then
          out[#out + 1] = { kind = "spill", text = label(f), detail = ("right edge %d > box %d"):format(b.l + drawnW, pw) }
        elseif ph and ph > 2 and b.t + b.h > ph + 1 and b.t < ph then
          out[#out + 1] = { kind = "spill", text = label(f), detail = ("bottom %d > box %d"):format(b.t + b.h, ph) }
        end
      end
    end
  end
  -- two texts of one parent drawn over each other, by more than 2 px each way
  for _, list in pairs(byParent) do
    for i = 1, #list do
      for j = i + 1, #list do
        local a, c = list[i], list[j]
        local function ext(e)
          local _, _, est = textBox(e.f)
          local w = e.f._w and math.min(e.b.w, e.f._wrap == false and e.b.w or e.b.w) or est
          -- a justified text inside a set width draws only its own width, at its side
          local l = e.b.l
          if e.f._w and textBox(e.f) and est < e.b.w then
            local j2 = e.f._justify
            if j2 == "RIGHT" then l = e.b.l + e.b.w - est elseif j2 == "CENTER" then l = e.b.l + (e.b.w - est) / 2 end
            w = est
          end
          return l, e.b.t, w, e.b.h
        end
        local al, at, aw, ah = ext(a)
        local cl, ct, cw, ch = ext(c)
        local ox = math.min(al + aw, cl + cw) - math.max(al, cl)
        local oy = math.min(at + ah, ct + ch) - math.max(at, ct)
        if ox > 2 and oy > 2 then
          out[#out + 1] = { kind = "overlap", text = label(a.f) .. " x " .. label(c.f), detail = ("%dx%d px"):format(ox, oy) }
        end
      end
    end
  end
  return out
end

-- the suite's data made long: every name gets " of the Scarlet Monastery Cathedral" and every amount of copper, count
-- and price becomes three digits larger (v * 1000 + 777); the settings are left alone. Used by the layout sweep and by
-- tests/render_html.lua.
local LONG = { item = 1, src = 1, zone = 1, sub = 1, foe = 1, name = 1, text = 1, title = 1, boss = 1, context = 1, prof = 1, craft = 1, buyer = 1, seller = 1, faction = 1 }
local BIG = { money = 1, balance = 1, gained = 1, spent = 1, looted = 1, sold = 1, quests = 1, auctionSales = 1, mail = 1, repairs = 1, vendor = 1, training = 1, flights = 1, auctions = 1, mailSpent = 1, other = 1, trade = 1, tradeSpent = 1, kills = 1, xp = 1, gold = 1, price = 1, bid = 1, buyout = 1, net = 1, count = 1 }
function L.stretch(db)
  local done = {}
  local function stretch(t)
    if done[t] then return end; done[t] = true
    for k, v in pairs(t) do
      if type(v) == "table" then stretch(v)
      elseif type(v) == "string" and LONG[k] and #v > 1 and #v < 40 then t[k] = v .. " of the Scarlet Monastery Cathedral"
      elseif type(v) == "number" and BIG[k] and v > 0 and v == math.floor(v) then t[k] = v * 1000 + 777 end
    end
  end
  for k, v in pairs(db) do if k ~= "settings" and type(v) == "table" then stretch(v) end end
end

return L
