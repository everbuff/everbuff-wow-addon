-- Gold glance (everbuff-wow-addon #43, 0.9.45). Loaded by tests/run_tests.lua after tests/gold_rate.lua:
--   dofile("tests/gold_glance.lua")({ check = check, M = M, ns = ns })
-- Runs on a save file of its own (the suite's is put aside and put back): the money formatter's options as a table
-- of cases, the pill (no frame while it is off, saved on creation, its text following the purse with no timer and
-- in combat, nothing moved or resized in combat, the clicks, the lock), the pure placing functions (inside the
-- screen at every scale, clear of the flag), the menu with the client's MenuUtil and with the addon's own list, the
-- broker objects (no library, a throwing library), the tooltip's new lines, the flag tooltip, /eb gold stats and
-- /eb gold timer read from the raw argument, and settings that no read creates.
return function(P)
  local M, ns = P.M, P.ns
  local E, G, UI = ns.Emitter, ns.Gold, ns.UI
  local ME = "Player-1-000001"
  local NB = UI.NBSP
  local fmt = ns.fmtMoney
  local realPrint = print
  -- (a failed check is printed with the real print, whatever the test has put in its place)
  local function check(name, cond, detail) local mine = print; print = realPrint; P.check(name, cond, detail); print = mine end
  local said = {}
  print = function(...) said[#said + 1] = table.concat({ ... }, " ") end

  local main = { db = ns.DB, epoch = M.epoch, now = M.now, money = M.money }
  local real = { menu = rawget(_G, "MenuUtil"), stub = rawget(_G, "LibStub"), frameShown = _G.EverbuffFrame and _G.EverbuffFrame.shown }
  ns.Recorder.pause("logout")
  local function fresh(db)
    ns.Recorder.discard()
    ns.DB = ns.migrateDB(db or {})
    G._held, G._baseWait, G._flushTimer, G._tickAt, G._afk = nil, nil, nil, nil, nil
    E._openGain, E._questMoney, E._dayErr = nil, nil, nil
    ns._test.newLoad()
    M.timers = {}
    for _, e in ipairs({ "MERCHANT_CLOSED", "MAIL_CLOSED", "AUCTION_HOUSE_CLOSED", "TRAINER_CLOSED", "TRADE_CLOSED" }) do M.fire(e) end
    M.units.NPC = nil
    M.now = M.now + 100
  end
  local function login(reload) M.fire("PLAYER_ENTERING_WORLD", not reload, reload and true or false); M.runTimers() end
  local function money(d) M.money = M.money + d; M.fire("PLAYER_MONEY") end
  local function play(sec) for _ = 1, math.floor(sec / 10) do M.now = M.now + 10; M.epoch = M.epoch + 10; G.tick() end end
  local function me() return ns.DB.characters[ME] end
  local function hideWindow() if _G.EverbuffFrame then _G.EverbuffFrame.shown = false end; G.rateWatch() end
  hideWindow()

  -- ── the formatter: one table of cases, every option ─────────────────────────────────────────────────────────
  do
    local S, SG, SC, SR = { short = true }, { short = true, signed = true }, { short = true, compact = true }, { short = true, rate = true }
    local nan = 0 / 0
    local secret = 4242
    M.secrets[secret] = true
    local cases = {
      -- value, options, text
      { 0, nil, "0c" }, { 99, nil, "99c" }, { 10000, nil, "1g" }, { 120400, nil, "12g" .. NB .. "4s" }, { 999999, nil, "99g" .. NB .. "99s" .. NB .. "99c" },
      { 1000000, nil, "100g" }, { 12345670000, nil, "1,234,567g" }, { -120400, nil, "12g" .. NB .. "4s" }, { nan, nil, "0c" }, { secret, nil, "0c" },
      { "12", nil, "0c" }, { math.huge, nil, "0c" },
      { 0, S, "0c" }, { 99, S, "99c" }, { 105, S, "1s" .. NB .. "05c" }, { 10000, S, "1g" .. NB .. "00s" }, { 120400, S, "12g" .. NB .. "04s" },
      { 999999, S, "99g" .. NB .. "99s" }, { 1000000, S, "100g" }, { 12345670000, S, "1,234,567g" }, { -120400, S, "12g" .. NB .. "04s" },
      { nan, S, "0c" }, { secret, S, "0c" },
      { 120400, SG, "+12g" .. NB .. "04s" }, { -120400, SG, "-12g" .. NB .. "04s" }, { 0, SG, "+0c" }, { -99, SG, "-99c" },
      { 12345670000, SC, "1,234.5k" .. NB .. "g" }, { 1000000000, SC, "100.0k" .. NB .. "g" }, { 999999999, SC, "99,999g" }, { 120400, SC, "12g" .. NB .. "04s" },
      { 1234.5, SR, "12s" .. NB .. "35c" }, { 1234.5, S, "12s" .. NB .. "34c" }, { 999950, SR, "100g" }, { 999949, SR, "99g" .. NB .. "99s" },
      { 444960, SR, "44g" .. NB .. "50s" },
      { -120400, { signed = true }, "-12g" .. NB .. "4s" }, { 120400, { signed = true }, "+12g" .. NB .. "4s" },
    }
    local bad = {}
    for i, c in ipairs(cases) do
      local got = fmt(c[1], c[2])
      if got ~= c[3] then bad[#bad + 1] = ("case %d: got %s, want %s"):format(i, tostring(got), c[3]) end
    end
    M.secrets[secret] = nil
    check("formatter: every case of the table", #bad == 0, table.concat(bad, "; "))
    local gi, si, ci = UI.COIN_ICON.g, UI.COIN_ICON.s, UI.COIN_ICON.c
    check("formatter: the icons are inline textures of height 0, so they follow the font size", gi:find("^|TInterface\\MoneyFrame\\UI%-GoldIcon:0:0:") ~= nil and gi:sub(-2) == "|t" and si:find("SilverIcon:0:0:", 1, true) ~= nil and ci:find("CopperIcon:0:0:", 1, true) ~= nil)
    check("formatter: icons take the place of the letters", fmt(120400, { short = true, icons = true }) == "12" .. gi .. NB .. "04" .. si and fmt(7, { icons = true }) == "7" .. ci
      and fmt(120407, { icons = true }) == "12" .. gi .. NB .. "4" .. si .. NB .. "7" .. ci)
    check("formatter: compact with icons has no letter", fmt(12345670000, { short = true, compact = true, icons = true }) == "1,234.5k" .. gi)
    check("formatter: a signed amount with icons keeps its sign", fmt(-120400, { short = true, icons = true, signed = true }) == "-12" .. gi .. NB .. "04" .. si)
    -- width: while an amount moves inside one band its text keeps its length (zero-padded), so a pill does not jitter
    local steady = true
    for _, band in ipairs({ { 100000, 999999 }, { 1000, 9999 }, { 1000000, 9999999 } }) do
      local len
      for i = 0, 400 do
        local v = band[1] + math.floor((band[2] - band[1]) * i / 400)
        local n = #fmt(v, S)
        len = len or n
        if n ~= len then steady = false end
      end
    end
    check("formatter: the short form keeps its width inside a band (10g to 99g, 10s to 99s, 100g to 999g)", steady)
    check("formatter: a total is formatted from summed copper, never from summed texts", fmt(60 + 60, S) == "1s" .. NB .. "20c")
  end

  -- ── the pure placing functions ──────────────────────────────────────────────────────────────────────────────
  do
    local sw, sh = 1920, 1080
    local bad = {}
    local corners = { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }
    for _, corner in ipairs(corners) do
      for _, sc in ipairs({ 0.5, 1, 1.35, 2 }) do
        for _, pos in ipairs({ { 0, 0 }, { 5000, -5000 }, { -5000, 5000 }, { 900, -500 }, { -30, 30 } }) do
          local w, h = 180 * sc, G.PILL_H * sc
          local x, y = G.pillClamp(corner, pos[1], pos[2], w, h, sw, sh)
          local l, b = G.cornerRect(corner, x, y, w, h, sw, sh)
          if l < -0.01 or b < -0.01 or l + w > sw + 0.01 or b + h > sh + 0.01 then bad[#bad + 1] = ("%s x%s at %d,%d"):format(corner, sc, pos[1], pos[2]) end
          local c2, x2, y2 = G.nearestCorner(l, b, w, h, sw, sh)
          local l2, b2 = G.cornerRect(c2, x2, y2, w, h, sw, sh)
          if math.abs(l2 - l) > 0.01 or math.abs(b2 - b) > 0.01 then bad[#bad + 1] = corner .. " round trip" end
        end
      end
    end
    check("placing: a pill is inside the screen from every corner, at every scale, wherever it was saved", #bad == 0, table.concat(bad, "; "))
    check("placing: a pill wider than the screen is pinned to its corner", select(1, G.pillClamp("TOPLEFT", 50, -10, 3000, 22, sw, sh)) == 0)
    -- clear of the flag: every place a pill could be saved at, for every flag corner and size
    local over = {}
    local saved = ns.DB.settings
    for _, fc in ipairs(corners) do
      for _, fs in ipairs({ 1, 1.5 }) do
        ns.DB.settings = { emitCorner = fc, flagScale = fs }
        local fr = G.flagRect(sw, sh)
        for px = 0, sw - 180, 60 do
          for py = 0, sh - 22, 27 do
            local l, b = G.pillClear(px, py, 180, 22, fr, sw, sh)
            local m = G.FLAG_MARGIN - 0.01
            if not (l >= fr.l + fr.w + m or l + 180 <= fr.l - m or b >= fr.b + fr.h + m or b + 22 <= fr.b - m) then over[#over + 1] = fc end
            if l < 0 or b < 0 or l + 180 > sw or b + 22 > sh then over[#over + 1] = fc .. " off screen" end
          end
        end
      end
    end
    ns.DB.settings = { flagPos = { point = "BOTTOMRIGHT", x = -100, y = 200 }, flagScale = 1 }
    local fr = G.flagRect(sw, sh)
    check("placing: a dragged flag is where its saved spot says", fr.l == sw - 100 - 320 and fr.b == 200 and fr.w == 320 and fr.h == 40, fr.l .. " " .. fr.b)
    ns.DB.settings = saved
    check("placing: no saved place leaves the pill over the flag or its notification line", #over == 0, #over .. " " .. tostring(over[1]))
  end

  -- ── the pill ────────────────────────────────────────────────────────────────────────────────────────────────
  fresh()
  M.epoch, M.money = 1797000000, 4123000
  local frames0 = #M.frames
  login(); G.tick()
  check("pill: off by default, no frame exists and no setting was written", G.pill == nil and (ns.DB.settings.gold == nil or ns.DB.settings.gold.pill == nil))
  money(100); G.pillApply(); G.pillUpdate(); G.repaint()
  check("pill: while it is off a purse change, an apply and a repaint create no frame", G.pill == nil and #M.frames == frames0, #M.frames - frames0)
  check("pill: the first-run question is due", G.pillAskDue() == true)
  check("pill: reading its settings creates nothing", G.pillCfg() == nil and G.tipCfg() == nil and G.pillMetrics()[1] == "balance" and (ns.DB.settings.gold == nil or ns.DB.settings.gold.pill == nil))
  check("pill: answering No is remembered and shows nothing", G.pillAnswer(false) == true and G.pill == nil and ns.DB.settings.gold.pill.asked == true and ns.DB.settings.gold.pill.on == false and G.pillAskDue() == false)
  check("pill: turning it on builds it, shown", G.pillOn(true) == true and G.pill ~= nil and G.pill.shown == true)
  local p = G.pill
  local pc = ns.DB.settings.gold.pill
  check("pill: its place is saved the moment it is created, relative to a corner", pc.corner == "TOPLEFT" and type(pc.x) == "number" and type(pc.y) == "number" and p._pts and p._pts[1].p == pc.corner and p._pts[1].rel == UIParent, tostring(pc.corner))
  check("pill: it shows the balance in the short form", p.text.text == fmt(M.money, { short = true }) and p.text.text == "412g", p.text.text)
  M.timers = {}
  local tk0 = #M.tickers
  money(2500)
  check("pill: the text follows the purse in the frame of the change, with no timer and no ticker", p.text.text == fmt(M.money, { short = true }) and #M.timers == 0 and #M.tickers == tk0, p.text.text)
  G.pillSet(1, "today"); G.pillSet(2, "balance")
  check("pill: two values, joined by the separator", p.text.text == fmt(2600, { short = true, signed = true }) .. "  ·  " .. fmt(M.money, { short = true }), p.text.text)
  G.pillSet(2, "today")
  check("pill: the second value is never the first again", #G.pillMetrics() == 1 and G.pillMetrics()[1] == "today")
  G.pillOpt("label", true)
  check("pill: with the label on a value names itself", p.text.text == "Today " .. fmt(2600, { short = true, signed = true }), p.text.text)
  G.pillOpt("label", false)
  G.pillSet(1, "total")
  ns.DB.characters.ALT = { name = "Mira", realm = "Realm", class = "MAGE", faction = "Alliance", seen = M.epoch - 86400, gold = { balance = 1000000 } }
  G.pillUpdate()
  check("pill: the account total", p.text.text == fmt(M.money + 1000000, { short = true }), p.text.text)
  ns.DB.settings.gold.icons = true
  G.fire()
  check("pill: Coin icons in Settings draws the coin icon", p.text.text:find("UI-GoldIcon", 1, true) ~= nil)
  ns.DB.settings.gold.icons = nil
  G.pillSet(1, "rate")
  check("pill: with no active time the rate says so, dimmed", p.text.text:find("Farming no time yet", 1, true) ~= nil and p.text.text:find("^|cff") ~= nil, p.text.text)
  check("pill: a rate on the pill starts the 10 s repaint", G._rateTicker ~= nil)
  play(310)
  M.units.target = { name = "Kobold", hostile = true, dead = true, guid = "Creature-0-1-1-1-6-00AB" }
  M.fire("LOOT_OPENED"); money(31000); M.units.target = nil
  check("pill: the rate, named by its definition", p.text.text == "Farming " .. fmt(360000, { short = true }) .. "/h", p.text.text)
  M.epoch = M.epoch + 10; M.now = M.now + 10; G.tick()
  local before = p.text.text
  G._rateTicker.fn()
  check("pill: the 10 s repaint moves the rate with time", p.text.text ~= before and p.text.text:find("^Farming ") ~= nil, p.text.text)
  G.pillSet(1, "timer")
  check("pill: the farm timer when none runs", p.text.text == "Farm timer off")
  G.timerStart()
  check("pill: starting the timer shows it at once", p.text.text:find("^Farm %+0c in 1 min") ~= nil, p.text.text)
  G.pillSet(1, "balance")
  check("pill: with no rate on it the repaint stops", G._rateTicker == nil)

  -- combat: the text moves, nothing else does
  do
    M.inCombat = true
    local pts, w, shown = p._pts, p._w, p.shown
    money(50000000)
    check("combat: the text still follows the purse", p.text.text == fmt(M.money, { short = true }), p.text.text)
    G.pillOpt("scale", 1.5); G.pillOpt("pos"); G.pillPlace()
    check("combat: the pill is not moved, resized, scaled or hidden", p._pts == pts and p._w == w and p.shown == shown and G._pillDirty == true)
    said = {}
    p.scripts.OnMouseUp(p, "RightButton")
    check("combat: a right-click opens no menu and says why", (G._menu == nil or G._menu.shown == false) and #said == 1 and said[1]:find("not during combat", 1, true) ~= nil, said[1])
    said = {}
    p.scripts.OnDragStart(p)
    check("combat: a drag does not start", p._dragging == nil and #said == 1)
    p.scripts.OnMouseUp(p, "LeftButton")
    check("combat: a left-click opens nothing, it waits for the end of the fight", G._openAfter ~= nil and not (_G.EverbuffFrame and _G.EverbuffFrame.shown))
    check("combat: turning the pill off waits too", G.pillOn(false) == false and p.shown == true)
    M.inCombat = false
    M.fire("PLAYER_REGEN_ENABLED")
    check("combat: after the fight what waited is done: the scale, the place and the window", G._pillDirty == nil and p._pts ~= pts and G._openAfter == nil and G.paneShowing() == true and ns.DB.settings.gold.pill.scale == 1.5)
    hideWindow()
    G.pillOpt("scale", 1)
  end

  -- the clicks, the drag, the lock
  do
    p.scripts.OnMouseUp(p, "LeftButton")
    check("pill: a left-click opens Loot, Gold", G.paneShowing() == true)
    hideWindow()
    p.scripts.OnDragStart(p)
    check("pill: a drag starts", p._dragging == true)
    p.scripts.OnMouseUp(p, "LeftButton")
    check("pill: the mouse button going up during a drag is not a click", G.paneShowing() == false)
    p.scripts.OnDragStop(p)
    check("pill: the drag ends with the place saved", p._dragging == nil and type(pc.corner) == "string" and type(pc.x) == "number")
    p.scripts.OnMouseUp(p, "LeftButton")
    check("pill: nor is the release right after a drag", G.paneShowing() == false)
    M.now = M.now + 1
    G.pillOpt("locked", true)
    p.scripts.OnDragStart(p)
    check("pill: a locked pill does not move", p._dragging == nil)
    G.pillOpt("locked", false)
    -- the hover: help lines and the gold block, live while the pill owns the tooltip
    local gt = _G.GameTooltip
    p.scripts.OnEnter(p)
    check("pill: the hover shows the gold block under two help lines", gt.owner == p and gt.lines[1] == "everbuff.gg gold" and gt.lines[2]:find("Right-click: menu", 1, true) ~= nil and gt.lines[3] == "THIS CHARACTER", gt.lines[3])
    local function bal() for _, l in ipairs(gt.lines) do if type(l) == "string" and l:find("^Balance  ") then return l end end end
    money(700)
    check("pill: the open tooltip follows the purse", bal() == "Balance  " .. fmt(M.money), bal())
    p.scripts.OnLeave(p)
    check("pill: Hide turns it off and keeps the frame hidden", G.pillOn(false) == true and p.shown == false and ns.DB.settings.gold.pill.on == false)
    money(5)
    check("pill: a hidden pill starts no repaint", G._rateTicker == nil)
    G.pillOn(true)
  end

  -- ── the menu ────────────────────────────────────────────────────────────────────────────────────────────────
  do
    local items = G.menuItems()
    local kinds = {}
    for _, it in ipairs(items) do kinds[#kinds + 1] = it.kind .. ":" .. it.text end
    check("menu: Show, the six values, the second value, the label, the timer, the reset, Lock, Hide, Open gold", table.concat(kinds, "|") ==
      "title:Show|radio:Balance|radio:Account total|radio:Session net|radio:Today net|radio:Per hour|radio:Farm timer|sub:Second value|check:Show label|button:Restart farm timer|button:Reset per hour|check:Lock|button:Hide|button:Open gold",
      table.concat(kinds, "|"))
    -- without MenuUtil: the addon's own list
    _G.MenuUtil = nil
    G._menuFail = nil
    check("menu: without MenuUtil the own list opens", G.menu(p) == "own" and G._menu ~= nil and G._menu.shown == true and G._menu.count == #items + 1, G._menu and G._menu.count)
    local function row(text) for i = 1, G._menu.count do local b = G._menu.btns[i]; if b.text.text == text then return b end end end
    check("menu: the value shown is drawn selected", row("Balance").ebSelected == true and row("Today net").ebSelected == nil)
    row("Today net").scripts.OnClick(row("Today net"))
    check("menu: a click picks and closes", G.pillMetrics()[1] == "today" and G._menu.shown == false)
    G.menu(p)
    row("Second value  ›").scripts.OnClick(row("Second value  ›"))
    check("menu: the second value opens as a list of its own, with a way back", G._menu.shown == true and row("None") ~= nil and row("‹ Back") ~= nil and row("None").ebSelected == true and G._menu.count == 9, G._menu.count)
    row("Balance").scripts.OnClick(row("Balance"))
    check("menu: picking the second value", G.pillMetrics()[2] == "balance" and G._menu.shown == false)
    G.menu(p); G.menu(p)
    check("menu: a second right-click closes it", G._menu.shown == false)
    G.menu(p)
    row("Lock").scripts.OnClick(row("Lock"))
    check("menu: Lock", ns.DB.settings.gold.pill.locked == true)
    G.pillOpt("locked", false)
    G.menu(p)
    row("Hide").scripts.OnClick(row("Hide"))
    check("menu: Hide turns the pill off (a right-click alone never does)", ns.DB.settings.gold.pill.on == false and p.shown == false)
    check("menu: with the pill off the entry offers to show it", (function() for _, it in ipairs(G.menuItems()) do if it.text == "Show the gold pill" then return true end end end)() == true)
    G.pillOn(true)
    -- with MenuUtil
    local calls, kids = {}, {}
    local function node()
      local n = {}
      function n:CreateTitle(t) calls[#calls + 1] = "title:" .. t end
      function n:CreateRadio(t, isSel, pick) calls[#calls + 1] = "radio:" .. t; kids["radio:" .. t .. ":" .. #calls] = { isSel, pick } end
      function n:CreateCheckbox(t, isSel, pick) calls[#calls + 1] = "check:" .. t end
      function n:CreateButton(t, fn) calls[#calls + 1] = "button:" .. t; local c = node(); kids[t] = fn; return c end
      return n
    end
    local opened
    _G.MenuUtil = { CreateContextMenu = function(owner, gen) opened = owner; gen(owner, node()) end }
    check("menu: with MenuUtil the client's menu is used and the own list stays closed", G.menu(p) == "MenuUtil" and opened == p and G._menu.shown == false)
    local radios = 0
    for _, c in ipairs(calls) do if c:find("^radio:") then radios = radios + 1 end end
    check("menu: the same entries, the second value as a submenu", calls[1] == "title:Show" and radios == 13 and #calls == #items + 7, #calls)
    kids["Reset per hour"]()
    check("menu: a button of the client's menu runs its action", me().goldRate == nil)
    -- a MenuUtil that throws, and one whose root lacks a method: the own list, and it is remembered
    _G.MenuUtil = { CreateContextMenu = function() error("no menus here") end }
    check("menu: a throwing MenuUtil falls back to the own list", G.menu(p) == "own" and G._menu.shown == true and G._menuFail == true)
    G._menu:Hide(); G._menu.owner = nil
    G._menuFail = nil
    _G.MenuUtil = { CreateContextMenu = function(owner, gen) gen(owner, { CreateTitle = function() end }) end }
    check("menu: a menu root without the methods falls back too", G.menu(p) == "own" and G._menu.shown == true)
    G._menu:Hide(); G._menu.owner = nil
    _G.MenuUtil = { CreateContextMenu = "not a function" }
    G._menuFail = nil
    check("menu: a MenuUtil without the function is not called", G.menu(p) == "own")
    G._menu:Hide(); G._menu.owner = nil
    _G.MenuUtil = real.menu
    G._menuFail = nil
  end

  -- ── bar text: LibDataBroker ─────────────────────────────────────────────────────────────────────────────────
  do
    local errs = #M.errors
    _G.LibStub = nil
    check("broker: without LibStub nothing happens", G.brokerInit() == false and G._broker == nil)
    M.fire("PLAYER_LOGIN")
    check("broker: PLAYER_LOGIN without the library raises nothing", G._broker == nil and #M.errors == errs)
    _G.LibStub = { GetLibrary = function() error("library table is broken") end }
    check("broker: a throwing GetLibrary is contained", G.brokerInit() == false and G._broker == nil)
    _G.LibStub = { GetLibrary = function() return nil end }
    check("broker: a LibStub without LibDataBroker is fine", G.brokerInit() == false)
    _G.LibStub = { GetLibrary = function() return { NewDataObject = function() error("refused") end } end }
    check("broker: a throwing NewDataObject is contained", G.brokerInit() == false and G._broker == nil and #M.errors == errs)
    check("broker: with no bar addon no repaint runs for it", (function() G.pillSet(1, "balance"); G.pillSet(2, nil); G.rateWatch(); return G._rateTicker == nil end)())
    local made, asked = {}, nil
    _G.LibStub = { GetLibrary = function(self, name, silent) asked = { self, name, silent }; return { NewDataObject = function(_, name2, obj) made[#made + 1] = { name = name2, obj = obj }; return obj end } end }
    M.fire("PLAYER_LOGIN")
    check("broker: at PLAYER_LOGIN the library is asked for silently", asked ~= nil and asked[1] == _G.LibStub and asked[2] == "LibDataBroker-1.1" and asked[3] == true)
    local names = {}
    for _, m in ipairs(made) do names[#names + 1] = m.name end
    check("broker: four data sources", table.concat(names, "|") == "everbuff.gg Balance|everbuff.gg Account total|everbuff.gg Today|everbuff.gg Per hour" and made[1].obj.type == "data source", table.concat(names, "|"))
    check("broker: the texts are set", made[1].obj.text == fmt(M.money, { short = true }) and made[2].obj.text ~= "" and made[3].obj.text:find("^[%+%-]") ~= nil and made[4].obj.text:find("Farming", 1, true) ~= nil, made[1].obj.text)
    money(123400)
    check("broker: a text follows the purse in the frame of the change", made[1].obj.text == fmt(M.money, { short = true }))
    M.fire("PLAYER_LOGIN")
    check("broker: registering happens once", #made == 4)
    check("broker: bar text keeps the 10 s repaint running", G._rateTicker ~= nil)
    local tipF = { lines = {} }
    function tipF:AddLine(t) self.lines[#self.lines + 1] = t end
    function tipF:AddDoubleLine(a, b) self.lines[#self.lines + 1] = a .. "  " .. b end
    made[1].obj.OnTooltipShow(tipF)
    check("broker: the tooltip is the shared gold block", tipF.lines[1] == "everbuff.gg gold" and tipF.lines[2] == "THIS CHARACTER" and #tipF.lines <= G.TIP_LINES + 1, tipF.lines[2])
    made[1].obj.OnClick(p, "LeftButton")
    check("broker: a left-click opens Loot, Gold", G.paneShowing() == true)
    hideWindow()
    _G.MenuUtil = nil
    made[1].obj.OnClick(p, "RightButton")
    check("broker: a right-click opens the menu", G._menu.shown == true)
    G._menu:Hide(); G._menu.owner = nil
    _G.MenuUtil = real.menu
    check("broker: none of it raised an error", #M.errors == errs, M.errors[#M.errors])
    G._broker = nil
    _G.LibStub = real.stub
    G.rateWatch()
  end

  -- ── the tooltip: the rate, the farm timer, week and month, the row limit ────────────────────────────────────
  do
    local function has(L, left) for _, l in ipairs(L) do if l.left == left then return l end end end
    play(320)
    local L = G.tipLines()
    check("tooltip: the rate is a line named by its definition, with its window", has(L, "Farming") ~= nil and has(L, "Farming").right:find("/h  ·  last %d+ min$") ~= nil, has(L, "Farming") and has(L, "Farming").right)
    check("tooltip: the farm timer is a line while it runs", has(L, "Farm timer") ~= nil and has(L, "Farm timer").right:find(" in %d+ min") ~= nil, has(L, "Farm timer") and has(L, "Farm timer").right)
    check("tooltip: week and month are off by default", has(L, "This week") == nil and has(L, "This month") == nil and #L <= G.TIP_LINES)
    G.tipCfg(true).week = true; G.tipCfg(true).month = true
    L = G.tipLines()
    check("tooltip: on in Settings they are two lines, and the budget grows by them", has(L, "This week") ~= nil and has(L, "This month") ~= nil and has(L, "This week").right:find("^%+") ~= nil and #L <= G.TIP_LINES + 2)
    G.tipCfg(true).week = false; G.tipCfg(true).month = false
    for i = 1, 20 do ns.DB.characters["X" .. i] = { name = "Alt" .. i, realm = "Realm", class = "MAGE", faction = "Alliance", seen = M.epoch - 3600, gold = { balance = i * 100 } } end
    local function rows(L2) local n = 0; for _, l in ipairs(L2) do if l.left:find("^   Alt") or l.left:find("^   Mira") or l.left:find("^> ") then n = n + 1 end end return n end
    L = G.tipLines()
    check("tooltip: by default it stays inside 18 lines with the current character first", #L <= G.TIP_LINES and rows(L) <= 8 and (function() for _, l in ipairs(L) do if l.left:find("^> Hart") then return true end end end)() == true, #L)
    G.tipCfg(true).limit = 15
    L = G.tipLines()
    check("tooltip: Characters in tooltips = 15 lists 15 and widens the budget for them", rows(L) == 15 and #L <= G.TIP_LINES + 10 and has(L, "and 7 more") ~= nil, rows(L) .. " " .. #L)
    G.tipCfg(true).limit = 99
    check("tooltip: the limit is held to 30", rows(G.tipLines()) <= 30)
    G.tipCfg(true).limit = nil
    for i = 1, 20 do ns.DB.characters["X" .. i] = nil end
    ns.DB.settings.gold.icons = true
    check("tooltip: Coin icons draws the icons in the block", (function() for _, l in ipairs(G.tipLines()) do if l.left == "Balance" then return l.right:find("UI-GoldIcon", 1, true) ~= nil end end end)() == true)
    ns.DB.settings.gold.icons = nil
  end

  -- ── the flag's tooltip: its four lines, and the gold block only when it is turned on ────────────────────────
  do
    local flag, gt = _G.EverbuffFlag, _G.GameTooltip
    check("flag: the flag frame is there", flag ~= nil and flag.scripts.OnEnter ~= nil)
    flag.scripts.OnEnter(flag)
    check("flag: by default its tooltip is the four lines it always was", #gt.lines == 4 and gt.lines[1] == "everbuff.gg", #gt.lines)
    flag.scripts.OnLeave(flag)
    G.tipCfg(true).flag = true
    flag.scripts.OnEnter(flag)
    check("flag: turned on, the gold block follows the four help lines", #gt.lines > 4 and #gt.lines <= 4 + G.TIP_LINES and gt.lines[4]:find("Right-click", 1, true) ~= nil and gt.lines[5] == "THIS CHARACTER", gt.lines[5])
    local function bal() for _, l in ipairs(gt.lines) do if type(l) == "string" and l:find("^Balance  ") then return l end end end
    money(900)
    check("flag: while it is open it follows the purse", gt.owner == flag and bal() == "Balance  " .. fmt(M.money), bal())
    flag.scripts.OnLeave(flag)
    ns.DB.settings.gold.tips = false
    flag.scripts.OnEnter(flag)
    check("flag: with gold in tooltips off it is the four lines again", #gt.lines == 4)
    flag.scripts.OnLeave(flag)
    ns.DB.settings.gold.tips = nil
    G.tipCfg(true).flag = nil
  end

  -- ── /eb gold stats and /eb gold timer, read from the raw argument ───────────────────────────────────────────
  do
    local function run(arg) said = {}; SlashCmdList.EVERBUFF(arg); local out = {}; for i, s in ipairs(said) do out[i] = s end; return out end
    local out = run("gold stats")
    check("/eb gold stats: three lines, the character, its realm and the account", #out == 3 and out[1]:find("this character: today ", 1, true) ~= nil and out[2]:find("this realm: today ", 1, true) ~= nil and out[3]:find("account: today ", 1, true) ~= nil, out[1])
    check("/eb gold stats: today, week and month with in, out and net", out[1]:find("week [%+%-]") ~= nil and out[1]:find("month [%+%-]") ~= nil and select(2, out[1]:gsub("%(in ", "")) == 3 and select(2, out[1]:gsub(", out ", "")) == 3, out[1])
    me().goldTimer = nil
    out = run("   GOLD    Timer  ")
    check("/eb gold timer: read from the raw argument, whatever its case and spacing", #out == 1 and out[1]:find("Farm timer started.", 1, true) ~= nil and me().goldTimer ~= nil and me().goldTimer.at == M.epoch, out[1])
    out = run("gold")
    check("/eb gold: with a farm timer running it is the fifth line", #out == 5 and out[5]:find("This farm: ", 1, true) ~= nil and out[4]:find("per hour: Farming ", 1, true) ~= nil, out[4])
    out = run("gold nonsense")
    check("/eb gold with an unknown word names the four commands", #out == 1 and out[1]:find("/eb gold stats", 1, true) ~= nil and out[1]:find("/eb gold timer", 1, true) ~= nil)
    M.inCombat = true
    check("/eb gold stats and timer answer in combat: they open, move and change nothing on screen", #run("Gold STATS") == 3 and #run("gold timer") == 1)
    M.inCombat = false
    out = run("help")
    check("/eb: the command list names them", out[1]:find("/eb gold stats", 1, true) ~= nil and out[1]:find("/eb gold timer", 1, true) ~= nil)
    local dash = false
    for _, a in ipairs({ "gold", "gold stats", "gold timer", "gold chars" }) do for _, s in ipairs(run(a)) do if s:find("\226\128\148", 1, true) then dash = true end end end
    for _, it in ipairs(G.menuItems()) do if it.text:find("\226\128\148", 1, true) then dash = true end end
    check("copy: no em dash in the replies or the menu", not dash)
  end

  -- ── the suite's save file and client back in place ──────────────────────────────────────────────────────────
  if G.pill then G.pill:Hide() end
  if G._menu then G._menu:Hide(); G._menu.owner = nil end
  _G.GameTooltip:Hide()
  G._tipOwner, G._tipRedo, G._openAfter, G._pillDirty = nil, nil, nil, nil
  _G.MenuUtil, _G.LibStub = real.menu, real.stub
  if _G.EverbuffFrame then _G.EverbuffFrame.shown = real.frameShown end
  ns.Recorder.discard()
  ns.DB = main.db
  G._held, G._baseWait, G._flushTimer, G._tickAt, G._afk = nil, nil, nil, nil, nil
  E._openGain, E._questMoney = nil, nil
  M.timers = {}
  M.epoch, M.now, M.money = main.epoch, M.now + 100, main.money
  ns._test.newLoad()
  M.fire("PLAYER_ENTERING_WORLD", false, true); M.runTimers()
  G.rateWatch()
  print = realPrint
  check("glance: the suite's save file is back, its session resumed, no pill on its screen", ns.DB == main.db and ns.Recorder.current() ~= nil and ns.DB.characters[ME].gold.balance == main.money
    and (G.pill == nil or G.pill.shown == false))
end
