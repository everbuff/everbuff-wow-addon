-- Every text a pane shows on a real save, as plain lines, so a screen can be checked against the stored data.
--
-- Usage, from the repo root (the same variables as tests/render_html.lua, see tests/real_save.lua):
--   EB_SAVE=<SavedVariables file> [EB_NOW=<unix time>] [EB_CHAR=<name>] [EB_BOOT=resume|login] [EB_RACE=<race>]
--     [EB_ZONE=<zone>] [EB_SIZE=<w>x<h>] luajit tests/dump_real.lua [page ...]
--     page      host/pane[:state] keys as tests/render_html.lua takes them (default: every page a real save can show)
--     EB_SIZE   the window size (default: the size the save holds, else 1104x697)
--
-- It boots the addon on the save the way the renderer does (tests/real_save.lua: the addon's own files, the real
-- handlers, a client that answers only what the save carries), opens each pane through the same call and prints:
--   the header   what the client was told and from which stored field, what the save does not carry, and every
--                stored value the boot itself changed (a resumed session, a re-read durability)
--   per page     every visible text of the window, top to bottom. Texts on one line of the same list share a dump
--                line, left to right, separated by " | ". Coin icons read g, s and c; any other icon reads [icon].
--                "~" in front: the line is in a list below its visible part (the player scrolls to it).
--                "[cut]" after a text: the window shortens it with "..." at this size.
-- The line starts with the y and the first x of the text in window pixels, so a line can be found in the shot of the
-- same page (tests/render_html.lua draws the same frames).
package.path = "tests/?.lua;" .. package.path
local M = require("wow_stub")
local G = dofile("tests/geometry.lua")
local Real = dofile("tests/real_save.lua")

local SAVE = os.getenv("EB_SAVE")
if not SAVE or SAVE == "" then io.stderr:write("EB_SAVE=<SavedVariables file> is required\n"); os.exit(2) end
local PAGES = {}
for i = 1, #arg do PAGES[#PAGES + 1] = arg[i] end
if #PAGES == 0 then PAGES = Real.PAGES end

G.install(M, {})
local out = io.write
local S = Real.boot(M, { save = SAVE, now = os.getenv("EB_NOW"), char = os.getenv("EB_CHAR"), boot = os.getenv("EB_BOOT"),
  race = os.getenv("EB_RACE"), zone = os.getenv("EB_ZONE") })
local ns = S.ns
print = function() end   -- (the addon's chat lines while the pages open; the boot's own are in the header)

local W, H = 1104, 697
if S.winSize and tonumber(S.winSize.w) and tonumber(S.winSize.h) then W, H = math.floor(S.winSize.w + 0.5), math.floor(S.winSize.h + 0.5) end
do
  local w, h = (os.getenv("EB_SIZE") or ""):match("^(%d+)x(%d+)$")
  if w then W, H = tonumber(w), tonumber(h) end
end

-- ── the header ──────────────────────────────────────────────────────────────────────────────────────────────────
local function plainChat(s) return (tostring(s):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
out(("SAVE    %s\n"):format(SAVE))
out(("BOOT    %s (%s)\n"):format(S.mode, S.mode == "resume" and "the last session goes on, as after a /reload" or "a fresh login, a new session"))
out(("ADDON   %s\n"):format(tostring(ns.VERSION)))
out(("SESSION %s\n"):format(S.session and ("%s  started %s  level %s"):format(tostring(S.session.id), tostring(S.session.startedEpoch), tostring(S.session.level)) or "none"))
out(("WINDOW  %dx%d\n"):format(W, H))
out("\nCLIENT ANSWERS (each from the save)\n")
for _, f in ipairs(S.facts) do out(("  %-22s %s   [%s]\n"):format(f.k, f.v, f.from)) end
out("\nNOT IN THE SAVE (the client answers nothing; in game these are live)\n")
for _, u in ipairs(S.unknown) do out("  " .. u .. "\n") end
if #S.notes > 0 then
  out("\nNOTES\n")
  for _, n in ipairs(S.notes) do out("  " .. n .. "\n") end
end
out("\nCHAT AT BOOT\n")
for _, c in ipairs(S.chat) do out("  " .. plainChat(c) .. "\n") end
out(("\nSTORED VALUES THE BOOT CHANGED (%d%s)\n"):format(#S.changes, #S.changes >= 400 and " or more" or ""))
for _, c in ipairs(S.changes) do out("  " .. c .. "\n") end

-- ── a page as lines ─────────────────────────────────────────────────────────────────────────────────────────────
local function plainText(s)
  s = tostring(s or "")
  s = s:gsub("|T([^|]-)|t", function(spec)
    local file = spec:match("^([^:]*)") or ""
    if file:find("GoldIcon") then return "g" end
    if file:find("SilverIcon") then return "s" end
    if file:find("CopperIcon") then return "c" end
    return "[icon]"
  end)
  s = s:gsub("|A.-|a", "[icon]")
  s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h", ""):gsub("|h", ""):gsub("|n", " / "):gsub("||", "|")
  s = s:gsub("\r?\n", " / "):gsub("\194\160", " ")
  return (s:gsub("%s+$", ""))
end

local function collect()
  local C, index, texts = {}, {}, {}
  for _, f in ipairs(M.frames) do
    local pa = f.parentFrame
    if pa then index[pa] = index[pa] or {}; table.insert(index[pa], f) end
  end
  local function walk(f, alpha, clip)
    if f.shown == false then return end
    local a = alpha * (f._alpha or 1)
    if a <= 0 then return end
    local b = G.resolve(f, C)
    if f._isTex then return end
    if f._isFS or (f._kind == "EditBox" and type(f.text) == "string") then
      local text = f.text ~= nil and plainText(f.text) or ""
      if text ~= "" and b then
        local below = clip and (b.t >= clip.t + clip.h - 0.5 or b.t + b.h <= clip.t + 0.5) or false
        local cut = false
        if f._isFS then local ok, v = pcall(f.IsTruncated, f); cut = ok and v == true end
        texts[#texts + 1] = { x = b.l, y = b.t + b.h / 2, text = text, below = below, cut = cut, seq = #texts, region = clip }
      elseif text ~= "" then
        texts[#texts + 1] = { x = -1, y = -1, text = text, unplaced = true, seq = #texts }
      end
      if f._isFS then return end
    end
    local inner = clip
    if b and (f._kind == "ScrollFrame" or f._clips) then inner = b end
    for _, c in ipairs(index[f] or {}) do walk(c, a, inner) end
  end
  walk(_G.EverbuffFrame, 1, nil)
  return texts
end

local function dump(key)
  local ok, why = Real.open(S, key)
  out(("\n=== %s\n"):format(key))
  if not ok then out("  (not shown: " .. tostring(why) .. ")\n"); return end
  local texts = collect()
  Real.close(S)
  table.sort(texts, function(a, b)
    if math.abs(a.y - b.y) > 3 then return a.y < b.y end
    if a.x ~= b.x then return a.x < b.x end
    return a.seq < b.seq
  end)
  -- texts whose middles are within 3 px share a line of the screen
  local i = 1
  while i <= #texts do
    local row, rest = { texts[i] }, {}
    local j = i + 1
    while j <= #texts and math.abs(texts[j].y - row[1].y) <= 3 do
      if texts[j].region == row[1].region then row[#row + 1] = texts[j] else rest[#rest + 1] = texts[j] end
      j = j + 1
    end
    table.sort(row, function(a, b) if a.x ~= b.x then return a.x < b.x end return a.seq < b.seq end)
    local parts, below = {}, true
    for _, t in ipairs(row) do
      parts[#parts + 1] = t.text .. (t.cut and " [cut]" or "")
      if not t.below then below = false end
    end
    if row[1].unplaced then out(("  ?            %s   (no position)\n"):format(table.concat(parts, " | ")))
    else out(("%s y=%5d x=%4d  %s\n"):format(below and "~" or " ", math.floor(row[1].y + 0.5), math.floor(row[1].x + 0.5), table.concat(parts, " | "))) end
    -- (texts at the same height in another part of the window, the side bar beside a list, are lines of their own)
    for k = #rest, 1, -1 do j = j - 1; texts[j] = rest[k] end
    i = j
  end
  out(("  (%d texts)\n"):format(#texts))
end

ns.UI.SetWindowSize(W, H)
_G.UIParent._w, _G.UIParent._h = W, H
G.VIEW.w, G.VIEW.h = W, H
for _, key in ipairs(PAGES) do dump(key) end
if #M.errors > 0 then
  out(("\nADDON ERRORS (%d)\n"):format(#M.errors))
  for i = 1, math.min(#M.errors, 30) do out("  " .. tostring(M.errors[i]) .. "\n") end
end
