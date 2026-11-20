-- Pane tests: the design system of docs/UX_OVERHAUL.md section 2 (tokens, formatters, glyphs, the kit components)
-- and the settings migration of section 3.1. Built on a scratch frame inside the window, so the geometry is real.
return function(P)
  local check, eq, M, ns = P.check, P.eq, P.M, P.ns
  local UI = ns.UI
  local S, G, C = UI.S, UI.G, UI.C

  -- ── tokens ──
  check("tokens: the spacing scale is 4 8 12 16 24 32 48", S.S1 == 4 and S.S2 == 8 and S.S3 == 12 and S.S4 == 16 and S.S5 == 24 and S.S6 == 32 and S.S7 == 48)
  check("tokens: the grid", G.BOX_L == 192 and G.TEXT_L == 204 and G.CTRL_Y == 52 and G.CONTENT_TOP == 92 and G.SIDEBAR_W == 168 and G.TITLE_H == 40)
  check("tokens: boxR and textR follow the width", G.boxR(900) == 876 and G.textR(900) == 864 and G.cw(900) == 684)
  check("tokens: WIDE starts at a content width of 1044 (a 1260 window)", G.isWide(1260) and not G.isWide(1259))
  for _, k in ipairs({ "canvas", "panel", "raised", "sunken", "line", "lineStrong", "lineControl", "fg", "fgSubtle", "fgMuted", "fgFaint",
    "accent", "accentFg", "accentTint", "accentHover", "accentPressed", "onAccent", "good", "warn", "bad", "goodTint", "warnTint", "badTint" }) do
    check("tokens: color role " .. k, type(C[k]) == "table" and #C[k] >= 3)
  end
  for _, role in ipairs({ "WORDMARK", "HERO", "DISPLAY", "TITLE", "ROW_TITLE", "BODY", "BODY_STRONG", "META", "LABEL", "BADGE" }) do
    check("tokens: font role " .. role, UI.F[role] ~= nil and UI.LINE_H[role] ~= nil)
  end

  -- ── formatters (2.5) ──
  eq("fmtDur: seconds", UI.fmtDur(45), "45s")
  eq("fmtDur: minutes and seconds", UI.fmtDur(605), "10m 5s")
  eq("fmtDur: hours", UI.fmtDur(3600), "1h 0m")
  eq("fmtDur: days", UI.fmtDur(2 * 86400 + 4 * 3600), "2d 4h")
  local d1, c1 = UI.fmtDelta(-12)
  check("fmtDelta: faster is good", d1 and d1:find("12") and c1 == "good", d1)
  local d2, c2 = UI.fmtDelta(30)
  check("fmtDelta: slower is warn", d2 and d2:find("30") and c2 == "warn", d2)
  eq("plural: one", UI.plural(1, "fight"), "1 fight")
  eq("plural: many", UI.plural(3, "fight"), "3 fights")
  eq("plural: entry", UI.plural(2, "entry"), "2 entries")
  local m = UI.money(123456)
  check("money: two units with coin icons", m:find("12") and m:find("34") and not m:find("56") and m:find("|T", 1, true), m)
  local m0 = UI.money(0)
  check("money: zero is 0 copper", m0:find("^0") ~= nil, m0)
  check("money: no em dash in the formatters", not (m .. UI.fmtDur(605)):find("\226\128\148", 1, true))

  -- ── glyphs (2.6): every name builds from flat rects ──
  local host = CreateFrame("Frame", nil, _G.EverbuffFrame)
  host:SetPoint("TOPLEFT", _G.EverbuffFrame, "TOPLEFT", G.BOX_L, -G.CONTENT_TOP); host:SetSize(640, 400)
  for name in pairs(UI.GLYPHS) do
    local g = UI.Glyph(host, name, 8, "fg")
    check("glyph " .. name .. " has rects inside its box", #g.tex >= 1 and (function()
      for _, tx in ipairs(g.tex) do
        local pt = tx._pts and tx._pts[1]
        if not pt or pt.rel ~= g or pt.x < 0 or -pt.y < 0 or pt.x + tx._w > 8 + 0.01 or -pt.y + tx._h > 8 + 0.01 then return false end
      end
      return true end)())
    g:Hide()
  end

  -- ── buttons and the one-primary rule ──
  local clicks = 0
  local b = UI.KitButton(host, "Open replay", "primary", function() clicks = clicks + 1 end)
  b:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
  eq("KitButton: a control is 24 high", P.box(b).h, 24)
  check("KitButton: padded label", P.box(b).w >= UI.TextWidth("BODY_STRONG", "Open replay") + 24)
  b:GetScript("OnClick")(b)
  eq("KitButton: a click runs once", clicks, 1)
  b:SetDisabled(true); b:GetScript("OnClick")(b)
  eq("KitButton: a disabled button does nothing", clicks, 1)
  eq("KitButton: one primary under the scratch frame", UI.CountPrimaries(host), 1)
  b:Hide()
  eq("KitButton: a hidden primary is not counted", UI.CountPrimaries(host), 0)

  -- ── badge ──
  local bd = UI.Badge(host, "best")
  bd:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -40)
  check("Badge: capitals, 16 high", bd.ebText == "BEST" and P.box(bd).h == 16 and bd.text:GetText() == "BEST")

  -- ── summary: strong runs, separators, trailing segments dropped when they do not fit ──
  local sm = UI.Summary(host)
  sm:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -80); sm:SetWidth(600)
  sm:SetSegments({ { "**3** fights this session" }, { "**1** death" }, { "best **12:04**" } })
  eq("Summary: all segments in a wide line", sm.Text(), "3 fights this session \194\183 1 death \194\183 best 12:04")
  local strong = 0
  for _, fs in ipairs(sm.pool[1].runs) do if fs:IsShown() and fs.ebRole == "BODY_STRONG" then strong = strong + 1 end end
  eq("Summary: the figure is BODY_STRONG", strong, 1)
  sm:SetWidth(200); M.settle(); sm.layout()
  check("Summary: a narrow line keeps the first segment and drops the rest", sm.shownN >= 1 and sm.shownN < 3, sm.shownN)

  -- ── stat row: cards share the width, 12 apart, the last takes the remainder ──
  local row = UI.StatRow(host, 3)
  row:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -120); row:SetWidth(640); row.layout()
  local w1, w3 = P.box(row.cards[1]).w, P.box(row.cards[3]).w
  check("StatRow: three cards over 640 px", w1 == math.floor((640 - 24) / 3) and P.box(row.cards[3]).l + w3 == P.box(row).l + 640, w1 .. "," .. w3)
  row.cards[1]:Set("Gold", UI.money(50000), "this session")
  eq("StatCard: 80 high", P.box(row.cards[1]).h, 80)
  -- card labels fit at 900: four cards across the content width, the longest labels the pages use
  local row4 = UI.StatRow(host, 4)
  row4:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -120); row4:SetWidth(G.cw(900)); row4.layout(); M.settle()
  for i, lbl in ipairs({ "FARMING PER HOUR", "TIME IN DUNGEONS", "BEST THIS WEEK", "GOLD THIS SESSION" }) do
    row4.cards[i]:Set(lbl, "1,234g 56s", "this session")
    check("StatCard: the label " .. lbl .. " fits at 900", not row4.cards[i].label:IsTruncated())
  end
  row4:Hide()

  -- ── empty states ──
  local em = UI.Empty(host, { icon = "info", title = "No fights yet", text = "Pull something and it shows up here.", buttons = { { "Open Settings", function() end } } })
  check("Empty: title and text and one button", em.title:GetText() == "No fights yet" and em.buttons[1] and em.buttons[1]:IsShown())
  em:Hide()
  local el = UI.EmptyLine(host)
  el:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -220); el:SetWidth(600)
  el:Set("No items match.", "Clear search", function() end)
  check("EmptyLine: link after the sentence", el.link:IsShown() and P.box(el.link).l >= P.box(el.text).l + 1)

  -- ── kit table: header 24, rows 32, day rows 24, inline empty text ──
  local tbl = UI.Table(host, { { key = "name", label = "Name", flex = 1, max = 300 }, { key = "n", label = "Count", kind = "num", sort = true } },
    { kit = true, onClick = function() end })
  tbl.frame:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -260); tbl.frame:SetWidth(640); M.settle(); tbl.relayout(640)
  tbl.setRows({ { ebSection = "Today" }, { name = "Copper Ore", n = 3 }, { name = "Linen Cloth", n = 12 } }, function(r, it) r.c.name:SetText(it.name); r.c.n:SetText(tostring(it.n)) end)
  eq("KitTable: height is header + day row + two rows", tbl.height, 24 + 24 + 64)
  check("KitTable: the day row is in capitals", tbl.sections()[1] and tbl.sections()[1]:GetText() == "TODAY")
  check("KitTable: rows that open something carry a chevron", tbl.rows[2].c._chev and tbl.rows[2].c._chev:GetText() == "\226\128\186")
  check("KitTable: the flex column stops at its max", tbl.cols.name.w <= 300, tbl.cols.name.w)
  tbl.setState("No items yet.")
  check("KitTable: empty text under the header", tbl.stateFS:IsShown() and tbl.shownN == 0 and not tbl.rows[2]:IsShown())

  -- the stripe (panel at UI.STRIPE_ALPHA over the canvas) stays visible: at least 3 L* from the canvas (2.7 lists)
  local function L(c)
    local function lin(v) return v <= 0.04045 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4 end
    local y = 0.2126 * lin(c[1]) + 0.7152 * lin(c[2]) + 0.0722 * lin(c[3])
    return y > 0.008856 and (116 * y ^ (1 / 3) - 16) or (903.3 * y)
  end
  local a = UI.STRIPE_ALPHA
  local mix = { C.canvas[1] + (C.panel[1] - C.canvas[1]) * a, C.canvas[2] + (C.panel[2] - C.canvas[2]) * a, C.canvas[3] + (C.panel[3] - C.canvas[3]) * a }
  check("KitTable: stripe contrast of 3 L* or more", math.abs(L(mix) - L(C.canvas)) >= 3, L(mix) - L(C.canvas))

  -- ── filter button: off its default it is active and shows the clear glyph ──
  local picked
  local fb = UI.FilterButton(host, { default = "all", label = "All", items = { { "all", "All" }, { "green", "Green and up" } }, onPick = function(k) picked = k end })
  fb:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -380)
  check("FilterButton: on its default it is quiet", not fb.ebActive and fb.chev:IsShown() and not fb.clear:IsShown())
  fb:SetValue("green", "Green and up")
  check("FilterButton: off its default it is active with a clear glyph", fb.ebActive and fb.clear:IsShown() and not fb.chev:IsShown())
  fb.clear:GetScript("OnClick")(fb.clear)
  eq("FilterButton: clear picks the default", picked, "all")
  fb:GetScript("OnClick")(fb)
  check("FilterButton: a click opens its menu", fb.menu:IsShown() and fb.menu.rows[2] and fb.menu.rows[2].text:GetText() == "Green and up")
  fb.menu.rows[2]:GetScript("OnClick")(fb.menu.rows[2])
  check("FilterButton: a menu pick reaches onPick and closes the menu", picked == "green" and not fb.menu:IsShown())

  -- ── segmented control: one width for every segment, the selected one in accentTint, nil selects none ──
  local seg, segPicked = nil, nil
  seg = UI.Segmented(host, { { "session", "Session" }, { "today", "Today" }, { "week", "Week" }, { "all", "All time" } }, { value = "session", onPick = function(k) segPicked = k end })
  seg:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -420)
  local widest = 0
  for _, l in ipairs({ "Session", "Today", "Week", "All time" }) do widest = math.max(widest, UI.TextWidth("BODY_STRONG", l)) end
  check("Segmented: every segment is as wide as the longest label plus 24, at least 64", seg.segW == math.max(64, widest + UI.S.S5) and seg:GetWidth() == 4 * seg.segW and seg:GetHeight() == UI.H.CONTROL)
  check("Segmented: the value is filled, the others are not", seg.segs[1].fill:IsShown() and not seg.segs[2].fill:IsShown() and seg.segs[1].text._color[1] == UI.C.accentFg[1])
  seg.segs[3]:GetScript("OnClick")(seg.segs[3])
  check("Segmented: a click selects its segment and reaches onPick", segPicked == "week" and seg.value == "week" and seg.segs[3].fill:IsShown() and not seg.segs[1].fill:IsShown())
  seg:SetValue(nil)
  local none = true
  for _, b in ipairs(seg.segs) do if b.fill:IsShown() then none = false end end
  check("Segmented: SetValue(nil) selects none (the pick sits on a More overflow)", none)

  -- ── search: 176 x 24, the placeholder until there is text, a clear button, Esc clears ──
  local se = UI.Search(host, "Search items")
  se:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -460)
  check("Search: 176 x 24 with its placeholder and no clear button", se:GetWidth() == UI.SEARCH_W and se:GetHeight() == UI.H.CONTROL and se.placeholder:IsShown() and not se.clear:IsShown() and se.placeholder:GetText() == "Search items")
  se:SetText("linen"); se.scripts.OnTextChanged(se)
  check("Search: with text the placeholder hides and the clear button shows", not se.placeholder:IsShown() and se.clear:IsShown())
  se.clear:GetScript("OnClick")(se.clear); se.scripts.OnTextChanged(se)
  check("Search: the clear button empties it", se:GetText() == "" and se.placeholder:IsShown() and not se.clear:IsShown())
  se:SetText("x"); se.scripts.OnEscapePressed(se); se.scripts.OnTextChanged(se)
  check("Search: Esc clears it", se:GetText() == "")
  -- capitals keep their escapes: a money icon in a LABEL text still renders
  eq("UI.upper keeps the escapes", UI.upper("Earned +3|TGold:12:12:0:0|t |cff112233x|r"), "EARNED +3|TGold:12:12:0:0|t |cff112233X|r")
  host:Hide()

  -- ── settings migration (3.1): a 0.9.51 save and a fresh one ──
  local old = { lastTab = "Combat", lastSub = "fights", winScale = 0.7 }
  UI.MigrateSettings(old)
  check("migration: Combat/fights becomes Home/fights", old.lastTab == "Home" and old.lastSub == "fights", tostring(old.lastTab) .. "/" .. tostring(old.lastSub))
  eq("migration: the scale is raised to 90%", old.winScale, 0.9)
  check("migration: the new keys get their defaults", old.fightsView == "important" and old.itemsQuality == "green" and old.welcomeDone == false)
  local fresh = {}
  UI.MigrateSettings(fresh)
  check("migration: a fresh save opens on Home/now", fresh.lastTab == "Home" and fresh.lastSub == "now")
  local gone = { lastTab = "Journey", lastSub = "x" }
  UI.MigrateSettings(gone)
  check("migration: an unknown tab falls back to Home/now", gone.lastTab == "Home" and gone.lastSub == "now")
  local badSub = { lastTab = "Loot", lastSub = "nope" }
  UI.MigrateSettings(badSub)
  check("migration: an unknown pane falls back to the host's first", badSub.lastTab == "Loot" and badSub.lastSub == "items")

  -- ── the window remembers where it was: lastTab / lastSub are written on select and read on open ──
  ns.UI.Open("Loot", "gold"); M.settle()
  check("Open: selecting a pane writes lastTab and lastSub", ns.DB.settings.lastTab == "Loot" and ns.DB.settings.lastSub == "gold")
  ns.UI.Open("Combat", "deaths"); M.settle()
  check("Open: an old key lands on its new page", ns.UI.activeTab() == "Home" and ns.DB.settings.lastSub == "deaths")

  -- ── the status chip ──
  local st = UI.StatusState()
  check("chip: a known state sentence", ({ ["Recording"] = 1, ["Recording, combat log off"] = 1, ["Recording, desktop app not seen"] = 1, ["Starting"] = 1, ["Standing by"] = 1 })[st.text] ~= nil, st.text)
  check("chip: the sync count comes from the one Sync read", type(ns.SyncState().waiting) == "number")
  ns.UI.Open("Home", "now"); M.settle()
end
