-- Gold rate, farm timer and reset (everbuff-wow-addon #43, 0.9.45). Loaded by tests/run_tests.lua after
-- tests/gold_roster.lua:
--   dofile("tests/gold_rate.lua")({ check = check, M = M, ns = ns })
-- Runs on a save file of its own (the suite's is put aside and put back), with the clock in the test's hands: the
-- rate window (10 active minutes with 5g farmed is 30g an hour), time away from the keyboard and logged out left
-- out, a secret AFK answer, the warm-up, the 30 minute gap, the 91 minute cap, what does and does not move Farming,
-- a /reload, a second character, the farm timer, Reset gold history, and the 10 s repaint that only runs while a
-- rate is on screen.
return function(P)
  local M, ns = P.M, P.ns
  local E, G = ns.Emitter, ns.Gold
  local ME, OTHER = "Player-1-000001", "Player-1-000002"
  local realPrint = print
  -- (a failed check is printed with the real print, whatever the test has put in its place)
  local function check(name, cond, detail) local mine = print; print = realPrint; P.check(name, cond, detail); print = mine end
  print = function() end

  local main = { db = ns.DB, epoch = M.epoch, now = M.now, money = M.money }
  local real = { guid = _G.UnitGUID, afk = _G.UnitIsAFK, frameShown = _G.EverbuffFrame and _G.EverbuffFrame.shown }
  ns.Recorder.pause("logout")
  local function fresh(db)
    ns.Recorder.discard()
    ns.DB = ns.migrateDB(db or {})
    G._held, G._baseWait, G._flushTimer, G._tickAt, G._afk, G._rateErr = nil, nil, nil, nil, nil, nil
    E._openGain, E._questMoney, E._dayErr = nil, nil, nil
    ns._test.newLoad()
    M.timers = {}
    for _, e in ipairs({ "MERCHANT_CLOSED", "MAIL_CLOSED", "AUCTION_HOUSE_CLOSED", "TRAINER_CLOSED", "TRADE_CLOSED" }) do M.fire(e) end
    M.units.NPC = nil
    M.now = M.now + 100
  end
  local function login(reload) M.fire("PLAYER_ENTERING_WORLD", not reload, reload and true or false); M.runTimers() end
  local function money(d) M.money = M.money + d; M.fire("PLAYER_MONEY") end
  local function loot(d)
    M.units.target = { name = "Kobold Miner", hostile = true, dead = true, guid = "Creature-0-1-1-1-6-00AA" }
    M.fire("LOOT_OPENED"); money(d)
    M.units.target = nil
    M.now = M.now + 4   -- past the loot window
  end
  -- `sec` seconds of play: the clocks move 10 s at a time and the model's ticker runs
  local function play(sec)
    for _ = 1, math.floor(sec / 10) do M.now = M.now + 10; M.epoch = M.epoch + 10; G.tick() end
  end
  local function me() return ns.DB.characters[ME] end
  local function count(t) local n = 0; for _ in pairs(t or {}) do n = n + 1 end return n end
  local function deepcopy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = deepcopy(x) end
    return out
  end
  local function same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not same(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
  end
  if _G.EverbuffFrame then _G.EverbuffFrame.shown = false end   -- no pane on screen in this file

  local T0 = math.floor(1796000000 / 60) * 60

  -- ── 10 active minutes with 5g farmed is 30g an hour ─────────────────────────────────────────────────────────
  fresh()
  M.epoch, M.money = T0, 10000
  login()
  G.tick()   -- the first tick of a load only starts the count
  check("rate: nothing is stored before the first write", me().goldRate == nil)
  check("rate: with no active time there is no figure", G.rate().perHour == nil and G.rate().active == 0 and G.metric("rate") == nil)
  loot(50000)
  play(600)
  local r = G.rate("farm")
  check("rate: 10 active minutes with 5g farmed give 30g an hour", r.active == 600 and r.sum == 50000 and r.perHour == 300000, ("%s %s %s"):format(r.active, r.sum, tostring(r.perHour)))
  check("rate: past the warm-up", r.warm == false and r.left == 0)
  do
    local name, v, note, dim = G.rateParts(r)
    check("rate: the label names the definition and the window", name == "Farming" and v == "30g" .. ns.UI.NBSP .. "00s/h" and note == "last 10 min" and dim == false, ("%s|%s|%s"):format(name, v, note))
    check("rate: the resolver answers it", G.metric("rate") == 300000)
    check("rate: the glance text is not dimmed", G.glance("rate") == "Farming " .. v, G.glance("rate"))
  end
  check("rate: the window lives on the character's block, one bucket per minute", type(me().goldRate.m) == "table" and count(me().goldRate.m) >= 10 and me().goldRate.last == M.epoch)
  do
    local ok = true
    for k, b in pairs(me().goldRate.m) do
      if type(k) ~= "number" or type(b.e) ~= "number" or type(b.s) ~= "number" or type(b.f) ~= "number" or type(b.a) ~= "number" or b.a > 60 or b.a < 0 then ok = false end
    end
    check("rate: every bucket is { e, s, f, a } in numbers, a at most 60", ok)
  end
  check("rate: the day row counts the same active seconds", (function() local t = 0; for _, row in pairs(me().goldDays or {}) do t = t + (row.t or 0) end return t end)() == 600)
  check("rate: no error in the rate writer", G._rateErr == nil and E._dayErr == nil, tostring(G._rateErr or E._dayErr))

  -- ── away from the keyboard: no active time, but a credit still counts ───────────────────────────────────────
  _G.UnitIsAFK = function() return M.afk end
  M.afk = true; M.fire("PLAYER_FLAGS_CHANGED", "player")
  check("afk: the flag is read on PLAYER_FLAGS_CHANGED", G._afk == true)
  play(300)
  check("afk: time away adds no active seconds", G.rate("farm").active == 600, G.rate("farm").active)
  check("afk: and none to the day row", (function() local t = 0; for _, row in pairs(me().goldDays or {}) do t = t + (row.t or 0) end return t end)() == 600)
  loot(10000)
  r = G.rate("farm")
  check("afk: a credit lands in its bucket while away", r.sum == 60000 and r.active == 600 and r.perHour == 360000, r.sum)
  M.afk = false; M.fire("PLAYER_FLAGS_CHANGED", "target")
  check("afk: another unit's flags are not ours", G._afk == true)
  M.fire("PLAYER_FLAGS_CHANGED", "player")
  check("afk: back at the keyboard the count goes on", G._afk == false)
  play(60)
  check("afk: active time runs again", G.rate("farm").active == 660, G.rate("farm").active)
  -- a secret answer, a throwing function and a missing one all count as active, with no error
  do
    local errs = #M.errors
    local secret = {}
    M.secrets[secret] = true
    _G.UnitIsAFK = function() return secret end
    G._afk = true
    M.fire("PLAYER_FLAGS_CHANGED", "player")
    check("afk: a secret answer counts as active", G._afk == false)
    M.secrets[secret] = nil
    _G.UnitIsAFK = function() error("blocked") end
    G._afk = true
    M.fire("PLAYER_FLAGS_CHANGED", "player")
    check("afk: a blocked call counts as active", G._afk == false)
    _G.UnitIsAFK = nil
    G._afk = true
    M.fire("PLAYER_FLAGS_CHANGED", "player")
    check("afk: a client without the function counts as active", G._afk == false)
    local hidden = "player-hidden"
    M.secrets[hidden] = true
    M.fire("PLAYER_FLAGS_CHANGED", hidden)
    M.secrets[hidden] = nil
    play(10)
    check("afk: none of it raises an error", #M.errors == errs and G._rateErr == nil, M.errors[#M.errors])
    check("afk: and play counts", G.rate("farm").active == 670, G.rate("farm").active)
  end

  -- ── logged out: no tick runs, and the first tick of the next load adds nothing ──────────────────────────────
  do
    local before = G.rate("farm").active
    local saved = deepcopy(me().goldRate)
    M.fire("PLAYER_LOGOUT")
    M.epoch, M.now = M.epoch + 600, M.now + 600   -- ten minutes logged out, inside the 30 minute gap
    G._tickAt = nil
    ns._test.newLoad(); login()
    G.tick()
    check("logout: time logged out is not active time", G.rate("farm").active == before, G.rate("farm").active)
    check("logout: the window came back from the save file as it was written", same(me().goldRate.m, saved.m))
    play(20)
    check("logout: the same window goes on after a relog inside the gap", G.rate("farm").active == before + 20 and G.rate("farm").sum == 60000)
  end

  -- ── a /reload keeps the window ──────────────────────────────────────────────────────────────────────────────
  do
    local before = G.rate("farm")
    G._tickAt = nil
    ns._test.newLoad(); login(true)
    G.tick()
    local after = G.rate("farm")
    check("reload: the window survives a /reload", after.active == before.active and after.sum == before.sum and after.perHour == before.perHour)
  end

  -- ── what moves Farming, Earned and Net ──────────────────────────────────────────────────────────────────────
  do
    local f0, e0, n0 = G.rate("farm").sum, G.rate("earned").sum, G.rate("net").sum
    check("modes: looted coin is farmed and earned", f0 == 60000 and e0 == 60000 and n0 == 60000, ("%s %s %s"):format(f0, e0, n0))
    local mail0 = me().gold.mail or 0
    M.fire("MAIL_SHOW"); money(70000); M.fire("MAIL_CLOSED")
    check("modes: the gain was booked as mail", (me().gold.mail or 0) == mail0 + 70000, me().gold.mail)
    check("modes: a mail from an alt moves neither Farming nor Earned", G.rate("farm").sum == f0 and G.rate("earned").sum == e0 and G.rate("net").sum == n0)
    local tr0 = me().gold.training or 0
    M.fire("TRAINER_SHOW"); money(-20000); M.fire("TRAINER_CLOSED")
    check("modes: the spend was booked as training", (me().gold.training or 0) == tr0 + 20000, me().gold.training)
    check("modes: a training spend does not move Farming or Earned, and Net falls by it", G.rate("farm").sum == f0 and G.rate("earned").sum == e0 and G.rate("net").sum == n0 - 20000, G.rate("net").sum)
    money(3000)   -- income no source claims: earned, not farmed
    check("modes: unexplained income is earned, not farmed", G.rate("farm").sum == f0 and G.rate("earned").sum == e0 + 3000)
    -- a quest claims it within 3 s: it becomes farmed, in the minute it was booked in
    M.fire("QUEST_TURNED_IN", 4711, 0, 3000)
    check("modes: a quest that claims it makes it farmed", G.rate("farm").sum == f0 + 3000 and G.rate("earned").sum == e0 + 3000, G.rate("farm").sum)
    ns.DB.settings.gold.rateMode = "net"
    check("modes: settings.gold.rateMode picks the default mode", G.rate().mode == "net" and G.rateMode() == "net" and G.rate().label == "Net")
    local _, v = G.rateParts()
    check("modes: a net rate carries its sign", v:sub(1, 1) == "+" and v:sub(-2) == "/h", v)
    ns.DB.settings.gold.rateMode = "nonsense"
    check("modes: an unknown mode reads as Farming", G.rate().mode == "farm")
    ns.DB.settings.gold.rateMode = nil
    check("modes: the rounding is half away from zero", (function()
      local c = me()
      local keep = c.goldRate
      c.goldRate = { m = { [math.floor(M.epoch / 60)] = { e = 0, s = 1, f = 1, a = 7200 } }, last = M.epoch }
      local up, down = G.rate("farm").perHour, G.rate("net").perHour   -- 0.5 and -0.5
      c.goldRate = keep
      return up == 1 and down == -1
    end)())
  end

  -- ── the warm-up: under 300 active seconds the value is dimmed ───────────────────────────────────────────────
  fresh()
  M.epoch, M.money = T0 + 86400, 10000
  login(); G.tick()
  loot(20000)
  play(100)
  r = G.rate()
  check("warm-up: 100 active seconds is warming up, 3:20 to go", r.warm == true and r.left == 200 and r.perHour == 720000, ("%s %s"):format(tostring(r.left), tostring(r.perHour)))
  do
    local _, _, note, dim = G.rateParts(r)
    check("warm-up: the note says so and the value is dimmed", note == "warming up 3:20" and dim == true and G.glance("rate"):find("^|cff%x%x%x%x%x%xFarming ") ~= nil and G.glance("rate"):sub(-2) == "|r", G.glance("rate"))
  end
  play(200)
  check("warm-up: at 300 active seconds it is over", G.rate().warm == false and G.glance("rate"):find("|cff", 1, true) == nil)

  -- ── a gap of more than 30 minutes starts the window over; 30 minutes does not ───────────────────────────────
  do
    M.epoch, M.now = M.epoch + 1800, M.now + 1800
    check("gap: exactly 30 minutes of silence keeps the window", G.rate().active == 300 and G.rate().sum == 20000)
    M.epoch, M.now = M.epoch + 1, M.now + 1
    check("gap: one second more reads as empty", G.rate().active == 0 and G.rate().sum == 0 and G.rate().perHour == nil)
    check("gap: a read changes nothing in the save file", count(me().goldRate.m) > 0)
    G._tickAt = M.now - 10
    G.tick()
    check("gap: the next write starts the window over", count(me().goldRate.m) == 1 and G.rate().active == 10)
  end

  -- ── the window: 90 minutes of wall time, at most 91 buckets ─────────────────────────────────────────────────
  do
    loot(600000)
    play(100 * 60)
    local n = count(me().goldRate.m)
    r = G.rate()
    check("window: at most 91 minute buckets are kept", n <= 91 and n >= 90, n)
    check("window: active seconds are those of the window", r.active <= 91 * 60 and r.active >= 89 * 60, r.active)
    check("window: a credit older than the window is no longer in the rate", r.sum == 0, r.sum)
    check("window: the label says how far it looks back", select(3, G.rateParts(r)):find("^last 1h 3%dm$") ~= nil, select(3, G.rateParts(r)))
  end

  -- ── a second character has its own window ───────────────────────────────────────────────────────────────────
  do
    local mine = deepcopy(me().goldRate)
    local seenMe = me().seen
    _G.UnitGUID = function(u) if u == "player" then return OTHER end return real.guid(u) end
    M.fire("PLAYER_LOGOUT")
    G._tickAt = nil
    ns._test.newLoad()
    M.money = 500
    login(); G.tick()
    check("second character: it starts with no window", G.rate().active == 0 and ns.DB.characters[OTHER].goldRate == nil)
    loot(1000); play(30)
    check("second character: its credits and its time go to its own block", G.rate().sum == 1000 and G.rate().active == 30 and count(ns.DB.characters[OTHER].goldRate.m) >= 1)
    check("second character: the first character's window is untouched", same(ns.DB.characters[ME].goldRate, mine))
    G.timerStart()
    G.resetHistory()
    check("second character: its reset leaves the first character's block alone", same(ns.DB.characters[ME].goldRate, mine) and ns.DB.characters[ME].goldDays ~= nil and ns.DB.characters[ME].seen == seenMe)
    _G.UnitGUID = real.guid
    M.fire("PLAYER_LOGOUT")
    G._tickAt = nil
    ns._test.newLoad()
    M.money = ns.DB.characters[ME].gold.balance
    login(); G.tick()
  end

  -- ── the farm timer ──────────────────────────────────────────────────────────────────────────────────────────
  fresh()
  M.epoch, M.money = T0 + 3 * 86400, 10000
  login(); G.tick()
  loot(5000); money(-700)
  check("timer: none until it is started", G.timer() == nil and me().goldTimer == nil and G.metric("net", "char", "timer") == nil and G.glance("timer") == "Farm timer off")
  local sessBefore = deepcopy(ns.Recorder.current())
  check("timer: it starts", G.timerStart() == true and me().goldTimer.at == M.epoch)
  do
    local snapOk = true
    for k, v in pairs(me().gold) do if k ~= "balance" and me().goldTimer.ledger[k] ~= v then snapOk = false end end
    check("timer: the snapshot holds every key of the lifetime ledger, not the balance", snapOk and me().goldTimer.ledger.balance == nil and me().goldTimer.ledger.gained == 5000)
    check("timer: starting it touches no session record", same(ns.Recorder.current(), sessBefore))
  end
  loot(120000)
  M.fire("MAIL_SHOW"); money(40000); M.fire("MAIL_CLOSED")
  M.fire("TRAINER_SHOW"); money(-10000); M.fire("TRAINER_CLOSED")
  M.epoch, M.now = M.epoch + 18 * 60, M.now + 18 * 60
  do
    local t = G.timer()
    check("timer: farmed, earned and net since the start", t.farmed == 120000 and t.earned == 120000 and t.net == 110000 and t.elapsed == 1080, ("%s %s %s"):format(t.farmed, t.earned, t.net))
    check("timer: the value follows the per hour setting, 12g in 18 minutes is 40g an hour", t.mode == "farm" and t.value == 120000 and t.perHour == 400000)
    local nb = ns.UI.NBSP
    check("timer: its line", G.timerText(t) == ("This farm: +12g%s00s in 18 min  ·  40g%s00s/h"):format(nb, nb), G.timerText(t))
    check("timer: the resolver answers it like any other period", G.metric("net", "char", "timer") == 150000 and G.metric("earned", "char", "timer") == 160000
      and G.metric("spent", "char", "timer") == 10000 and G.metric("looted", "char", "timer") == 120000 and G.metric("played", "char", "timer") == 1080)
    check("timer: the glance text", G.glance("timer") == ("Farm +12g%s00s in 18 min"):format(nb), G.glance("timer"))
    ns.DB.settings.gold = ns.DB.settings.gold or {}
    ns.DB.settings.gold.rateMode = "net"
    check("timer: in Net mode it is earned minus spent", G.timer().value == 110000)
    ns.DB.settings.gold.rateMode = nil
  end
  do
    local saved = deepcopy(me().goldTimer)
    G._tickAt = nil
    ns._test.newLoad(); login(true)
    check("timer: it survives a /reload", same(me().goldTimer, saved) and G.timer().farmed == 120000)
    M.fire("PLAYER_LOGOUT")
    M.epoch, M.now = M.epoch + 7200, M.now + 7200
    ns._test.newLoad(); login()
    check("timer: it survives a relog, and no session record carries it", same(me().goldTimer, saved) and G.timer().farmed == 120000 and G.timer().elapsed == 1080 + 7200
      and (function() for _, s in pairs(ns.DB.sessions) do if s.goldTimer ~= nil or s.timer ~= nil then return false end end return true end)())
    G.timerStart()
    check("timer: starting again starts over", G.timer().farmed == 0 and G.timer().elapsed == 0)
  end

  -- ── Reset gold history: this character's day rows, rate window and farm timer; the ledger and balance stay ──
  do
    play(30)
    loot(100)
    local c = me()
    c.goldMonths = { ["202611"] = { g = 1, s = 0 } }
    ns.DB.characters.ALT = { name = "Mira", gold = { balance = 5 }, goldDays = { ["20261101"] = { g = 5, s = 0 } }, goldRate = { m = {} }, goldTimer = { at = 1, ledger = {} }, goldSince = 7 }
    local alt = deepcopy(ns.DB.characters.ALT)
    local ledger, since = deepcopy(c.gold), c.goldSince
    check("reset: there is something to reset", c.goldDays ~= nil and c.goldRate ~= nil and c.goldTimer ~= nil and since ~= nil)
    M.epoch = M.epoch + 50
    check("reset: it runs", G.resetHistory() == true)
    check("reset: the day rows, the month rows, the rate window and the farm timer are gone", c.goldDays == nil and c.goldMonths == nil and c.goldRate == nil and c.goldTimer == nil)
    check("reset: the history starts now", c.goldSince == M.epoch and c.goldSince ~= since)
    check("reset: the lifetime ledger and the balance stay", same(c.gold, ledger) and c.gold.balance == M.money)
    check("reset: no other character's block is touched", same(ns.DB.characters.ALT, alt))
    loot(200)
    check("reset: the next change opens a new day row on the old balance", count(c.goldDays) == 1 and (function() for _, row in pairs(c.goldDays) do return row.g == 200 and row.c == M.money and row.o == M.money - 200 end end)())
    ns.DB.characters.ALT = nil
    check("reset per hour: only the window goes", (function() play(20); local d = c.goldDays; local ok = G.resetRate(); return ok and c.goldRate == nil and c.goldDays == d end)())
  end

  -- ── the 10 s repaint runs only while a rate is on screen ────────────────────────────────────────────────────
  do
    G.rateWatch()
    check("repaint: with the pill off, no bar text, no tooltip and no pane there is no ticker", G._rateTicker == nil and G.rateOnScreen() == false)
    local owner = CreateFrame("Frame")
    local redone = 0
    local gt = _G.GameTooltip
    gt:SetOwner(owner, "ANCHOR_NONE")
    G.tooltip(gt, { owner = owner, redo = function() redone = redone + 1 end })
    check("repaint: an open tooltip of ours starts it", G._rateTicker ~= nil and G.rateOnScreen() == true)
    local tk = G._rateTicker
    tk.fn()
    check("repaint: a tick draws the tooltip again", redone == 1, redone)
    gt:Hide()
    tk.fn()
    check("repaint: once the tooltip is closed the next tick stops the ticker", G._rateTicker == nil and tk.cancelled == true and redone == 1)
  end

  -- ── the suite's save file and client back in place ──────────────────────────────────────────────────────────
  _G.UnitGUID, _G.UnitIsAFK = real.guid, real.afk
  if _G.EverbuffFrame then _G.EverbuffFrame.shown = real.frameShown end
  ns.Recorder.discard()
  ns.DB = main.db
  G._held, G._baseWait, G._flushTimer, G._tickAt, G._afk = nil, nil, nil, nil, nil
  E._openGain, E._questMoney = nil, nil
  M.timers = {}
  M.epoch, M.now, M.money = main.epoch, M.now + 100, main.money
  for _, e in ipairs({ "MERCHANT_CLOSED", "MAIL_CLOSED", "AUCTION_HOUSE_CLOSED", "TRAINER_CLOSED", "TRADE_CLOSED" }) do M.fire(e) end
  ns._test.newLoad()
  M.fire("PLAYER_ENTERING_WORLD", false, true); M.runTimers()
  print = realPrint
  check("rate: the suite's save file is back, its session resumed", ns.DB == main.db and ns.Recorder.current() ~= nil and ns.DB.characters[ME].gold.balance == main.money)
end
