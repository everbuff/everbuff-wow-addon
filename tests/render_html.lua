-- Real-font renderer of the addon window: the window as the player sees it, as HTML, for a headless browser.
--
-- Usage, from the repo root:
--   luajit tests/render_html.lua [outdir] [page ...]
--     outdir   where the pages go (default tests/render_out, which git ignores); fonts are copied to outdir/fonts
--     page     host/pane keys to render (default: loot/items loot/gold home/now home/activity);
--              settings/general, settings/golddisplay and settings/data open a Settings sub-tab
--   then, on a machine with Chrome (never next to a running WoW client):
--   node tests/render_shot.js outdir   (puppeteer-core; screenshots every page and writes <page>.findings.json)
--
-- It loads the addon exactly like tests/run_tests.lua (it runs the suite up to its layout audit, so the data is the
-- suite's: loot rows with items and coin, mail and auction rows, a gold ledger with trade, fights), opens each pane at
-- 900x580 and 1600x1000, on that data and on the same data made long (tests/layout.lua L.stretch), and writes every
-- visible region of EverbuffFrame as an absolutely positioned element:
--   frames    their backdrop (fill and 1 px edge) and textures (color fills; files as a placeholder square)
--   texts     font face and size from the font object (the TTF files in Everbuff/media/fonts), color, justify, width;
--             single line with "..." when word wrap is off, |c color codes as spans, |T icons as a square of the size
--   scroll frames clip their child, like the client
-- Positions come from the anchors tests/wow_stub.lua records, resolved the way the client does (one or two points,
-- SetAllPoints, anchors to any region, nested frames), with text widths from the fonts' real advance widths
-- (tests/geometry.lua over tests/fontmetrics.lua), so GetWidth, GetStringWidth and IsTruncated answer the addon's
-- layout code as in game.
-- Every element carries data-src (the Lua file and line that created it) and data-pane. Each page also gets
-- <page>.layout.json: structural findings Lua can see (rows narrower than 3 px holding text, regions it could not place).
package.path = "tests/?.lua;" .. package.path
local M = require("wow_stub")
local Lay = dofile("tests/layout.lua")

local OUT = arg[1] or "tests/render_out"
local PAGES = {}
for i = 2, #arg do PAGES[#PAGES + 1] = arg[i] end
if #PAGES == 0 then PAGES = { "loot/items", "loot/gold", "home/now", "home/activity" } end
local SIZES = { { 900, 580 }, { 1600, 1000 } }
-- EVERBUFF_RENDER_SIZES="900x580,1250x760" renders other window sizes
if os.getenv("EVERBUFF_RENDER_SIZES") then
  SIZES = {}
  for w, h in os.getenv("EVERBUFF_RENDER_SIZES"):gmatch("(%d+)x(%d+)") do SIZES[#SIZES + 1] = { tonumber(w), tonumber(h) } end
end
local MARGIN = 24          -- world around the window, so anything drawn outside it shows

-- ── geometry and fonts: tests/geometry.lua resolves the anchors and measures with the TTF advance widths ─────
local G = dofile("tests/geometry.lua")
G.MARGIN = MARGIN
local VIEW = G.VIEW
local FONT_DIR, FACES = G.FONT_DIR, G.FACES
local fontOf, parse, textSize, lineHeight, resolve = G.fontOf, G.parse, G.textSize, G.lineHeight, G.resolve
G.install(M, { src = true })

-- ── the suite's data ────────────────────────────────────────────────────────────────────────────────────────────
local realPrint = print
print = function() end
EVERBUFF_RENDER_SETUP = true
local S = dofile("tests/run_tests.lua")
local ns = S.ns
M.inCombat = false
if ns.DB and ns.DB.settings then ns.DB.settings.winPos = nil end

-- the suite ends on a nearly empty character: tests/play_session.lua plays one more session through the REAL
-- handlers (loot of every quality, coin, fights, quests, a vendor, a repair, the mailbox, the auction house, a trade)
dofile("tests/play_session.lua")(M, ns)
-- and two evenings of gold with a name behind every row (quests, merchants, mail, trades), for the gold surfaces
dofile("tests/play_gold.lua")(M, ns)
print = realPrint

-- ── HTML ───────────────────────────────────────────────────────────────────────────────────────────────────────
local function esc(s) return (tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;")) end
local function rgba(c, mul)
  local a = (c[4] or 1) * (mul or 1)
  return ("rgba(%d,%d,%d,%.3f)"):format(math.floor((c[1] or 0) * 255 + 0.5), math.floor((c[2] or 0) * 255 + 0.5), math.floor((c[3] or 0) * 255 + 0.5), a)
end
local function px(v) return ("%.2fpx"):format(v) end
local LAYERS = { BACKGROUND = 1, BORDER = 2, ARTWORK = 3, OVERLAY = 4, HIGHLIGHT = 9 }

local function children(f, index)
  local list = index[f] or {}
  local regions, frames = {}, {}
  for _, c in ipairs(list) do
    if c._isFS or c._isTex then regions[#regions + 1] = c else frames[#frames + 1] = c end
  end
  return regions, frames
end

local function runsHTML(runs, size)
  local out, open = {}, false
  for _, r in ipairs(runs) do
    if r.text then out[#out + 1] = esc(r.text)
    elseif r.color then if open then out[#out + 1] = "</span>" end; out[#out + 1] = ('<span style="color:%s">'):format(rgba(r.color)); open = true
    elseif r.reset then if open then out[#out + 1] = "</span>"; open = false end
    elseif r.icon then out[#out + 1] = ('<i class="ic" style="width:%s;height:%s"></i>'):format(px(r.icon), px(r.icon))
    elseif r.br then out[#out + 1] = "<br>" end
  end
  if open then out[#out + 1] = "</span>" end
  return table.concat(out)
end

local function placeholderTex(file)
  file = tostring(file)
  if file:find("mark") then return "#0cd29d" end
  if file:find("Coin") then return "#c9a227" end
  return nil
end

local function renderPage(pageKey, W, H, dataTag)
  VIEW.w, VIEW.h = W, H
  local C = {}
  local index = {}
  for _, f in ipairs(M.frames) do
    local pa = f.parentFrame
    if pa then index[pa] = index[pa] or {}; table.insert(index[pa], f) end
  end
  local out, structural, unplaced = {}, {}, 0
  local texts = 0
  local function attrs(f) return (' data-src="%s"'):format(esc(f._src or "?")) end
  local function frameBox(f) local b = resolve(f, C); return b end
  local function emit(f, ox, oy, alpha, level)
    if f.shown == false then return end
    local b = resolve(f, C)
    local a = alpha * (f._alpha or 1)
    local lv = f._level or level
    if b and not f._isFS and not f._isTex then
      -- a frame with text inside but (almost) no width: its row background and hover cannot show
      if (b.w <= 2 or b.h <= 2) and f.parentFrame and f.parentFrame._scrollChild ~= f then
        local kids = index[f] or {}
        for _, c in ipairs(kids) do
          if c._isFS and c.shown ~= false and c.text and tostring(c.text) ~= "" then
            structural[#structural + 1] = { kind = "zero-size-frame", src = f._src, w = b.w, h = b.h, text = tostring(c.text):sub(1, 60) }
            break
          end
        end
      end
    end
    if f._isFS then
      if not f.text or tostring(f.text) == "" then return end
      if not b then unplaced = unplaced + 1; return end
      local font = fontOf(f)
      local _, _, lines = textSize(f, (f._w and f._w > 0 or (#(f._pts or {}) >= 2)) and b.w or nil)
      local lh = lineHeight(f)
      local fixedW = (f._w and f._w > 0) or (function() local hl, hr = false, false
        for _, p in ipairs(f._pts or {}) do if p.p:find("LEFT") then hl = true elseif p.p:find("RIGHT") then hr = true end end
        return hl and hr end)()
      local nowrap = (f._wrap == false) or not fixedW
      local padT = math.max(0, (b.h - lines * lh) / 2)
      local just = (f._justify or "CENTER"):lower()
      local pb = f.parentFrame and resolve(f.parentFrame, C)
      local style = {
        ("left:%s;top:%s"):format(px(b.l - ox), px(b.t - oy)),
        fixedW and ("width:%s"):format(px(b.w)) or "",
        ("height:%s;padding-top:%s"):format(px(math.max(b.h - padT, lh)), px(padT)),
        ("font-family:'%s';font-size:%spx;line-height:%spx;color:%s"):format(font.face, font.size, lh, rgba(font.color, a)),
        ("text-align:%s"):format(just == "right" and "right" or just == "left" and "left" or "center"),
        nowrap and "white-space:pre" or "white-space:pre-wrap",
        (nowrap and fixedW) and "overflow:clip;text-overflow:ellipsis" or "",
        (f._maxLines and f._maxLines > 1 and not nowrap) and ("-webkit-line-clamp:%d"):format(f._maxLines) or "",
        font.shadow and ("text-shadow:1px 1px 0 %s"):format(rgba(font.shadow)) or "",
        ("z-index:%d"):format(lv * 10 + (LAYERS[f._layer or "ARTWORK"] or 3)),
      }
      texts = texts + 1
      out[#out + 1] = ('<div class="fs" data-wrap="%d" data-fixedw="%d" data-lines="%d"%s%s data-pbox="%s" style="%s">%s</div>'):format(
        nowrap and 0 or 1, fixedW and 1 or 0, lines, attrs(f), font.fallback and ' data-face-fallback="1"' or "",
        pb and ("%.1f,%.1f,%.1f,%.1f"):format(pb.l, pb.t, pb.w, pb.h) or "",
        table.concat(style, ";"), runsHTML(parse(f.text, font.size), font.size))
      return
    end
    if f._isTex then
      if not b then return end
      if (f._layer or "") == "HIGHLIGHT" then return end
      local fill
      if f._fill then fill = rgba(f._fill, a)
      elseif f._file then fill = placeholderTex(f._file) or "#3b3d42" end
      if not fill or b.w <= 0 or b.h <= 0 then return end
      if f._vc and f._file then fill = rgba({ f._vc[1] * 0.4, f._vc[2] * 0.4, f._vc[3] * 0.4, a }) end
      out[#out + 1] = ('<div class="tx%s"%s style="left:%s;top:%s;width:%s;height:%s;background:%s;z-index:%d"></div>'):format(
        f._file and " file" or "", attrs(f), px(b.l - ox), px(b.t - oy), px(b.w), px(b.h), fill, lv * 10 + (LAYERS[f._layer or "ARTWORK"] or 3))
      return
    end
    -- a frame: backdrop, then its regions by layer, then its child frames by level
    if not b then
      unplaced = unplaced + 1
    else
      local bg, edge
      if f._bd then
        if f._bd.bgFile then bg = rgba(f.bgc or { 1, 1, 1, 1 }, a) end
        if f._bd.edgeFile then edge = rgba(f._bdc or { 1, 1, 1, 1 }, a) end
      end
      local tmpl = tostring(f._tmpl or "")
      local extra = ""
      if tmpl:find("UIPanelCloseButton") then bg, extra = "#5a1d1d", "&#215;" end
      if tmpl:find("CheckButton") then bg, edge = "#1d1d20", "#6e737a" end
      if tmpl:find("OptionsSlider") then bg = "#2e2e33" end
      if bg or edge or extra ~= "" then
        out[#out + 1] = ('<div class="fr"%s style="left:%s;top:%s;width:%s;height:%s;%s%sz-index:%d">%s</div>'):format(
          attrs(f), px(b.l - ox), px(b.t - oy), px(b.w), px(b.h), bg and ("background:" .. bg .. ";") or "",
          edge and ("box-shadow:inset 0 0 0 1px " .. edge .. ";") or "", lv * 10, extra)
      end
      if f._kind == "EditBox" and type(f.text) == "string" and f.text ~= "" then
        local font = fontOf(f)
        local ins = f._insets or { 0, 0, 0, 0 }
        out[#out + 1] = ('<div class="fs" data-wrap="0" data-fixedw="1" data-lines="1"%s style="left:%s;top:%s;width:%s;height:%s;line-height:%spx;font-family:\'%s\';font-size:%spx;color:%s;white-space:pre;overflow:clip;text-align:left;z-index:%d">%s</div>'):format(
          attrs(f), px(b.l - ox + ins[1]), px(b.t - oy), px(b.w - ins[1] - ins[2]), px(b.h), b.h, font.face, font.size, rgba(font.color, a), lv * 10 + 5, esc(f.text))
      end
    end
    local regions, frames = children(f, index)
    table.sort(regions, function(x, y) return (LAYERS[x._layer or "ARTWORK"] or 3) < (LAYERS[y._layer or "ARTWORK"] or 3) end)
    -- a scroll frame clips its child to its own box, as the client does
    local clip = b and (f._kind == "ScrollFrame" or f._clips)
    local cox, coy = ox, oy
    if clip then
      out[#out + 1] = ('<div class="clip"%s style="left:%s;top:%s;width:%s;height:%s;z-index:%d">'):format(
        attrs(f), px(b.l - ox), px(b.t - oy), px(b.w), px(b.h), lv * 10)
      cox, coy = b.l, b.t
    end
    for _, r in ipairs(regions) do emit(r, cox, coy, a, lv) end
    local order = {}
    for i, c in ipairs(frames) do order[i] = { c = c, i = i } end
    table.sort(order, function(x, y) local lx, ly = x.c._level or lv + 1, y.c._level or lv + 1; if lx ~= ly then return lx < ly end return x.i < y.i end)
    for _, o in ipairs(order) do emit(o.c, cox, coy, a, lv + 1) end
    if clip then
      out[#out + 1] = "</div>"
      -- the template's scroll bar sits 16 px wide to the right of the frame when the child is taller
      local child = f._scrollChild
      local cb = child and resolve(child, C)
      if cb and cb.h > b.h + 1 then
        out[#out + 1] = ('<div class="sb" style="left:%s;top:%s;width:16px;height:%s;z-index:%d"><div style="height:%s"></div></div>'):format(
          px(b.l + b.w + 4 - ox), px(b.t + 16 - oy), px(math.max(0, b.h - 32)), lv * 10 + 1, px(math.max(12, (b.h - 32) * b.h / cb.h)))
      end
      if child then
        structural[#structural + 1] = { kind = "scroll-child", src = f._src, frameW = b.w, frameH = b.h, childW = cb and cb.w, childH = cb and cb.h }
      end
    end
  end
  local root = _G.EverbuffFrame
  emit(root, 0, 0, 1, 1)
  local title = ("%s %dx%d %s"):format(pageKey, W, H, dataTag)
  local html = {
    "<!doctype html><html><head><meta charset=\"utf-8\"><title>" .. esc(title) .. "</title><style>",
    "@font-face{font-family:'Inter-Medium';src:url(fonts/Inter-Medium.ttf)}",
    "@font-face{font-family:'Inter-SemiBold';src:url(fonts/Inter-SemiBold.ttf)}",
    "@font-face{font-family:'ChakraPetch-Bold';src:url(fonts/ChakraPetch-Bold.ttf)}",
    "@font-face{font-family:'ChakraPetch-SemiBold';src:url(fonts/ChakraPetch-SemiBold.ttf)}",
    "@font-face{font-family:'ChakraPetch-Regular';src:url(fonts/ChakraPetch-Regular.ttf)}",
    "html,body{margin:0;padding:0;background:#3a4048;overflow:hidden}",
    "#win{position:absolute;left:0;top:0;width:" .. (W + 2 * MARGIN) .. "px;height:" .. (H + 2 * MARGIN) .. "px}",
    "#win div{position:absolute;box-sizing:border-box;margin:0}",
    ".fs{font-kerning:none;font-variant-ligatures:none;font-feature-settings:'liga' 0,'calt' 0;-webkit-font-smoothing:antialiased}",
    ".clip{overflow:hidden}",
    ".fr{color:#f3f4f5;font:16px sans-serif;text-align:center;line-height:24px}",
    ".ic{display:inline-block;vertical-align:middle;background:#3b3d42;box-shadow:inset 0 0 0 1px #6e737a}",
    ".sb{background:#16161a}.sb div{position:absolute;left:3px;width:10px;top:0;background:#55585f;border-radius:3px}",
    "</style></head><body>",
    ('<div id="win" data-page="%s" data-w="%d" data-h="%d" data-margin="%d" data-data="%s">'):format(esc(pageKey), W, H, MARGIN, dataTag),
    table.concat(out, "\n"),
    "</div></body></html>",
  }
  return table.concat(html, "\n"), { page = pageKey, w = W, h = H, data = dataTag, texts = texts, unplaced = unplaced, structural = structural }
end

-- ── JSON (small writer for the layout findings and the manifest) ─────────────────────────────────────────────
local function json(v)
  local t = type(v)
  if t == "table" then
    if #v > 0 or next(v) == nil then
      local parts = {}
      for _, x in ipairs(v) do parts[#parts + 1] = json(x) end
      return "[" .. table.concat(parts, ",") .. "]"
    end
    local keys, parts = {}, {}
    for k in pairs(v) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    for _, k in ipairs(keys) do parts[#parts + 1] = json(k) .. ":" .. json(v[k]) end
    return "{" .. table.concat(parts, ",") .. "}"
  elseif t == "string" then
    return '"' .. v:gsub('[%c"\\]', function(c) return c == '"' and '\\"' or c == "\\" and "\\\\" or ("\\u%04x"):format(c:byte()) end) .. '"'
  elseif t == "number" then return (v ~= v or v == math.huge or v == -math.huge) and "null" or ("%.2f"):format(v):gsub("%.?0+$", "")
  elseif t == "boolean" then return tostring(v) end
  return "null"
end

local function write(path, s, mode)
  local fh = assert(io.open(path, mode or "wb")); fh:write(s); fh:close()
end
local function copy(src, dst) local fh = assert(io.open(src, "rb")); local s = fh:read("*a"); fh:close(); write(dst, s) end

-- ── run ────────────────────────────────────────────────────────────────────────────────────────────────────────
local sep = package.config:sub(1, 1)
os.execute((sep == "\\" and 'mkdir "%s\\fonts" 2>nul' or 'mkdir -p "%s/fonts"'):format(sep == "\\" and OUT:gsub("/", "\\") or OUT))
for face in pairs(FACES) do copy(FONT_DIR .. face .. ".ttf", OUT .. "/fonts/" .. face .. ".ttf") end

DUNGEON_FIXTURE = dofile("tests/dungeon_fixture.lua")
local HOSTS = { loot = "Loot", home = "Home", combat = "Combat", dungeons = "Dungeons", character = "Character", settings = "Settings" }
-- the Home > Now states: set the readings, return the function that puts them back
function NOW_STATE(state)
  local keep = { log = ns.Logging.state, dur = M.dur, cont = _G.C_Container.GetContainerNumFreeSlots, q = _G.GetQuestLogTitle,
    qn = _G.GetNumQuestLogEntries, lim = ns.DB.settings.instanceLimit, maxl = _G.GetMaxPlayerLevel, ses = ns.Recorder.current() }
  local sesKeep = keep.ses and { id = keep.ses.id, kills = keep.ses.kills, items = keep.ses.items }
  local pst = ns.Pace.state()
  local paceKeep = {}
  for k, v in pairs(pst) do paceKeep[k] = v end
  if state == "logoff" then ns.Logging.state = function() return true, false end
  elseif state == "next" then
    M.dur = { [1] = { 18, 100 }, [7] = { 40, 100 } }
    _G.C_Container.GetContainerNumFreeSlots = function(bag) return bag == 0 and 2 or 0, 0 end
    _G.GetNumQuestLogEntries = function() return 2 end
    _G.GetQuestLogTitle = function(i) return ({ "Wanted: Kolkar Leaders", "Plainstrider Menace" })[i], 18, nil, false, false, 1 end
    ns.DB.settings.instanceLimit = 1
  elseif state == "max" then _G.GetMaxPlayerLevel = function() return UnitLevel("player") end
  elseif state == "empty" and keep.ses then keep.ses.id, keep.ses.kills, keep.ses.items = "render-empty", 0, 0
  elseif state:match("^welcome%d?$") then
    -- the first-run guide (4.13) on step 1, 2 or 3, with the combat log off so step 1 shows its Turn on
    ns.DB.settings.welcomeDone = false
    ns.Logging.state = function() return true, false end
    local v = ns._test.journeyRefresh()
    if v then v.welcomeStep = tonumber(state:match("%d")) or 1 end
  end
  return function()
    ns.DB.settings.welcomeDone = true
    local v = ns._test.journeyRefresh()
    if v then v.welcomeStep = 1 end
    ns.Logging.state, M.dur, _G.C_Container.GetContainerNumFreeSlots = keep.log, keep.dur, keep.cont
    _G.GetQuestLogTitle, _G.GetNumQuestLogEntries, ns.DB.settings.instanceLimit, _G.GetMaxPlayerLevel = keep.q, keep.qn, keep.lim, keep.maxl
    if sesKeep then keep.ses.id, keep.ses.kills, keep.ses.items = sesKeep.id, sesKeep.kills, sesKeep.items end
    for k in pairs(pst) do pst[k] = nil end
    for k, v in pairs(paceKeep) do pst[k] = v end   -- (the empty state's session id started the pace over)
  end
end
local manifest = {}
for _, dataTag in ipairs({ "normal", "long" }) do
  if dataTag == "long" then Lay.stretch(ns.DB) end
  for _, sz in ipairs(SIZES) do
    ns.UI.SetWindowSize(sz[1], sz[2])
    _G.UIParent._w, _G.UIParent._h = sz[1], sz[2]
    VIEW.w, VIEW.h = sz[1], sz[2]
    for _, key in ipairs(PAGES) do
      -- "loot/gold:journal", ":flagged", ":all", ":previous", ":today", ":week", ":days", ":chars", ":zones", ":runs",
      -- ":auctions", ":empty" or ":<source key>" (that source's page) open the Gold pane in that state; "loot/items:byitem",
      -- ":all" (every quality) and ":nomatch" (a search with no match) open Items in that state
      local host, pane, state = key:match("^(%w+)/(%w+):?(%w*)$")
      -- Home > Now in a state of docs/UX_OVERHAUL.md 4.0: "home/now:logoff" (combat log off), ":next" (durability
      -- 18%, 2 free bag slots, a limit of 1 used up, 2 quests ready), ":max" (max level), ":empty" (nothing yet),
      -- ":welcome", ":welcome2", ":welcome3" (the first-run guide on that step)
      local undo
      if host == "home" and pane == "now" and state ~= "" then undo = NOW_STATE(state) end
      -- the Dungeons screens on the runs of docs/UX_OVERHAUL.md 4.0 (tests/dungeon_fixture.lua): "dungeons/runs" with
      -- ":empty", ":nomatch" (filter Shadowfang Keep), ":limit4", ":limit5" (a limit of 5) or ":live" (Ragefire Chasm in
      -- progress); "dungeons/bydungeon"; "dungeons/run" (the Wailing Caverns BEST run), ":live", ":death" (Tessa's)
      local openPane, fx = pane, nil
      if host == "dungeons" then
        local undoFx
        undoFx, fx = DUNGEON_FIXTURE.install(ns, M, pane == "run" and (state == "live" and "live" or "") or state)
        if pane == "run" then openPane = "runs" end
        undo = function()
          local lv = ns._test.dungeonList and ns._test.dungeonList()
          if lv then lv.pickInst(nil) end
          local dv = ns._test.dungeonDetail and ns._test.dungeonDetail()
          if dv and dv:IsShown() then dv.d.Close() end
          undoFx()
        end
      end
      ns.UI.Open(HOSTS[host] or host, openPane); M.tick()
      ns.UI.Open(HOSTS[host] or host, openPane)   -- a second open: the panes read sizes their first build set
      if host == "dungeons" and pane == "runs" and state == "nomatch" then ns._test.dungeonList().pickInst("Shadowfang Keep") end
      if host == "dungeons" and pane == "run" then
        local rec = state == "live" and fx.open or state == "death" and fx.rfc or fx.wc2
        ns._test.dungeonList()
        ns.Dungeons.openRun(rec)
      end
      if host == "loot" and pane == "gold" then
        if state == "" then ns.Gold.open("session")
        elseif state == "journal" then ns.Gold.open("session", "journal")
        elseif state == "flagged" then ns.Gold.open("session", "journal", true)
        elseif state == "all" then ns.Gold.open("all", "journal")
        elseif state == "previous" then ns.Gold.open("previous")
        elseif state == "today" then ns.Gold.open("today")
        elseif state == "days" then ns.Gold.open("all", "days")
        elseif state == "chars" then ns.Gold.open("today", "chars")
        elseif state == "week" then ns.Gold.open("week")
        elseif state == "zones" or state == "runs" then ns.Gold.open("all", state)
        elseif state == "auctions" then ns.UI.Open("Loot", "auctions")
        elseif state == "empty" then ns.Gold.open("day:" .. ns.Gold.dayKey(GetServerTime() - 400 * 86400, ns.Gold.baseStored()))
        else ns.Gold.open("session"); ns.Gold.filter(state) end
      end
      if host == "loot" and pane == "items" and state ~= "" then
        local ic = ns._test.lootContent and ns._test.lootContent()
        if ic then
          if state == "byitem" then ic.setLootMode("byitem")
          elseif state == "all" then ic.setLootQuality("all")
          elseif state == "nomatch" then ic.search:SetText("zzzz"); ic.search.scripts.OnTextChanged(ic.search) end
          undo = function()
            ic.search:SetText(""); ic.search.scripts.OnTextChanged(ic.search)
            ic.setLootMode("newest"); ic.setLootQuality("green")
          end
        end
      end
      if host == "settings" then                  -- Settings is a tab with its own sub-tabs (general, golddisplay, data)
        for _, t in ipairs(ns._test.tabs or {}) do
          if t.name == "Settings" and t.content and t.content.subtabs then t.content.subtabs.select(pane) end
        end
      end
      M.settle()                                  -- OnSizeChanged to every list whose size the open changed
      local html, info = renderPage(key, sz[1], sz[2], dataTag)
      if undo then undo(); ns.UI.Open(HOSTS[host] or host, openPane); M.settle() end
      local name = ("%s-%s%s-%dx%d-%s"):format(host, pane, state ~= "" and ("-" .. state) or "", sz[1], sz[2], dataTag)
      write(OUT .. "/" .. name .. ".html", html)
      write(OUT .. "/" .. name .. ".layout.json", json(info))
      manifest[#manifest + 1] = { name = name, w = sz[1] + 2 * MARGIN, h = sz[2] + 2 * MARGIN }
      realPrint(("%-40s %4d texts  %3d unplaced  %2d structural"):format(name, info.texts, info.unplaced, #info.structural))
    end
  end
end
write(OUT .. "/manifest.json", json(manifest))
if #M.errors > 0 then realPrint("addon errors while rendering: " .. #M.errors .. "  first: " .. tostring(M.errors[1])) end
