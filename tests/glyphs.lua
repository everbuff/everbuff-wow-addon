-- The cmap scan (docs/UX_OVERHAUL.md 5 step 1): every character above ASCII that the addon's code puts in a text
-- (string literals, UTF-8 or decimal escapes, comments left out) must have a glyph in the faces the text roles use,
-- or the client draws a box. Shapes the fonts lack (chevrons, the clear cross, the info mark) are drawn as flat
-- textures by UI.Glyph instead; this scan proves no string asks a font for them.
-- Run from tests/run_tests.lua with { check = check }; standalone: luajit tests/glyphs.lua
local ctx = ...
local check = ctx and ctx.check or function(name, cond, detail)
  print((cond and "ok    " or "FAIL  ") .. name .. ((not cond and detail) and ("   -> " .. tostring(detail)) or ""))
end
local FM = dofile("tests/fontmetrics.lua")
local FACES = { "Inter-Medium", "Inter-SemiBold" }   -- every text role but the display ones (2.4)
local fonts = {}
for _, f in ipairs(FACES) do fonts[f] = FM.load("Everbuff/media/fonts/" .. f .. ".ttf") end
local FILES = { "Core", "Deaths", "Dungeons", "Economy", "Emitter", "Journey", "Market", "Progress", "Recording", "Runs", "RunsLegacy",
  "Sync", "UI", "Visits", "Fights", "Segments", "Logging", "Debug", "SelfTest" }

local BS = string.char(92)
local function unescape(s)
  return (s:gsub(BS .. "(%d%d?%d?)", function(d) return string.char(tonumber(d)) end))
end
local seen, n = {}, 0
for _, file in ipairs(FILES) do
  local ln = 0
  for line in io.lines("Everbuff/" .. file .. ".lua") do
    ln = ln + 1
    local code = line:gsub("%-%-[^\"]*$", "")
    for str in code:gmatch('"([^"]*)"') do
      for _, cp in ipairs(FM.codepoints(unescape(str))) do
        if cp > 127 and not seen[cp] then seen[cp] = file .. ".lua:" .. ln; n = n + 1 end
      end
    end
  end
end
check("glyphs: the scan found the window's characters above ASCII", n >= 3, n)
local missing = {}
for cp, where in pairs(seen) do
  for _, face in ipairs(FACES) do
    if fonts[face]:glyph(cp) == 0 then missing[#missing + 1] = ("U+%04X in %s (%s)"):format(cp, face, where) end
  end
end
table.sort(missing)
check("glyphs: every character above ASCII in a string has a glyph in Inter", #missing == 0, table.concat(missing, "; "))
-- the characters the kit itself writes as text
for _, ch in ipairs({ "\194\183", "\226\128\186", "\226\128\185", "\194\160", "\226\128\166" }) do
  local cp = FM.codepoints(ch)[1]
  check(("glyphs: U+%04X is in both Inter faces"):format(cp), fonts["Inter-Medium"]:glyph(cp) ~= 0 and fonts["Inter-SemiBold"]:glyph(cp) ~= 0)
end
-- the shapes the fonts may lack are UI.Glyph textures, never text
for _, ch in ipairs({ "\226\150\190", "\226\156\149", "\226\147\152" }) do
  local cp = FM.codepoints(ch)[1]
  check(("glyphs: U+%04X is never asked of a font"):format(cp), seen[cp] == nil, seen[cp])
end
-- The words of the window (docs/UX_PRAGMATIC.md 0.3, 0.4): the status is CAPTURING and the brand is everbuff.gg, in
-- every string the addon shows. "Recording" as a status word, "RECORDING" and a capitalised "Everbuff" as the brand
-- fail here. (A frame name such as "EverbuffFrame" is one word and is not the brand; the addon's own folder name is
-- compared as the bare string "Everbuff" in Logging.lua.)
do
  local badWords = {}
  for _, file in ipairs(FILES) do
    local ln = 0
    for line in io.lines("Everbuff/" .. file .. ".lua") do
      ln = ln + 1
      local code = line:gsub("%-%-[^\"]*$", "")
      for str in code:gmatch('"([^"]*)"') do
        local why
        if str:find("%f[%a]Recording%f[%A]") or str:find("%f[%a]RECORDING%f[%A]") then why = "Recording"
        elseif str ~= "Everbuff" and (str:find("%f[%a]Everbuff%f[%A]") or str:find("%f[%a]EVERBUFF%.GG")) then why = "Everbuff" end
        if why then badWords[#badWords + 1] = ("%s in %s.lua:%d"):format(why, file, ln) end
      end
    end
  end
  check("words: no string says Recording (the status is CAPTURING) or Everbuff (the brand is everbuff.gg)", #badWords == 0, table.concat(badWords, "; "))
  local ui = assert(io.open("Everbuff/UI.lua", "rb")):read("*a")
  check("words: the title bar brand is everbuff.gg", ui:find('brand:SetText("everbuff.gg")', 1, true) ~= nil)
  check("words: the status chip says CAPTURING", ui:find('st.textColor = "CAPTURING", "accent"', 1, true) ~= nil and ui:find('"CAPTURING, combat log off"', 1, true) ~= nil
    and ui:find('"CAPTURING, desktop app not seen"', 1, true) ~= nil)
end
