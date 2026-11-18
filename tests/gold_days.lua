-- Gold day rows (everbuff-wow-addon #43, 0.9.44). Loaded by tests/run_tests.lua after the gold journal tests:
--   dofile("tests/gold_days.lua")({ check = check, M = M, ns = ns })
-- Runs on a save file of its own (the suite's is put aside and put back), with the clock in the test's hands:
-- credits on both sides of the server reset, the day base (the reset read once, held while unknown, the PC's
-- midnight after 30 s), a late quest claim after a rollover, the row identities over 10,000 random purse changes,
-- the acknowledgement prune, a 0.9.43 save file, and the rule that only the logged-in character's block is written.
return function(P)
  local check, M, ns = P.check, P.M, P.ns
  local E, G = ns.Emitter, ns.Gold
  local DAY = 86400
  local ME = "Player-1-000001"
  local realPrint, realDate = print, _G.date
  print = function() end

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

  -- the suite's state, put aside
  local main = { db = ns.DB, epoch = M.epoch, now = M.now, money = M.money, resetSecs = M.resetSecs, weekStart = M.weekStart }
  ns.Recorder.pause("logout")
  local function fresh(db)
    ns.Recorder.discard()
    ns.DB = ns.migrateDB(db or {})
    G._held, G._baseWait, G._flushTimer, G._tickAt = nil, nil, nil, nil
    E._openGain, E._questMoney, E._dayErr = nil, nil, nil
    ns._test.newLoad()
    M.timers = {}
    M.resetSecs, M.weekStart = nil, nil
    for _, e in ipairs({ "MERCHANT_CLOSED", "MAIL_CLOSED", "AUCTION_HOUSE_CLOSED", "TRAINER_CLOSED", "TRADE_CLOSED" }) do M.fire(e) end
    M.units.NPC = nil
    M.now = M.now + 100
  end
  local function login(reload) M.fire("PLAYER_ENTERING_WORLD", not reload, reload and true or false); M.runTimers() end
  local function money(d) M.money = M.money + d; M.fire("PLAYER_MONEY") end
  local function me() return ns.DB.characters[ME] end
  local function days() return (me() and me().goldDays) or {} end
  local function count(t) local n = 0; for _ in pairs(t or {}) do n = n + 1 end return n end
  local function utc(t) return realDate("!%Y%m%d", t) end

  -- a reset moment (07:00 UTC, as the stub answers it) far from anything the suite played
  local reset = math.floor(1795000000 / DAY) * DAY + M.resetAt
  local kA, kB = utc(reset - DAY), utc(reset)

  -- ── credits on both sides of a reset land in two keys ──────────────────────────────────────────────────────
  fresh()
  M.epoch, M.money = reset - 3600, 1000
  login()
  check("days: a new character is seeded silently, no row is invented", count(days()) == 0 and me().goldSince == nil)
  money(100)
  M.epoch = reset + 60; M.now = M.now + 3660
  money(50); money(-30)
  local a, b = days()[kA], days()[kB]
  check("days: a credit before the reset and one after it land in two keys", count(days()) == 2 and a ~= nil and b ~= nil, count(days()))
  check("days: the key is the UTC date of the day's start, YYYYMMDD", kA:match("^%d%d%d%d%d%d%d%d$") ~= nil and G.dayKey(reset - 1, G.baseStored()) == kA and G.dayKey(reset, G.baseStored()) == kB)
  check("days: g, s, n, the opening and the closing balance of each row", a and b and a.g == 100 and a.s == 0 and a.n == 1 and a.o == 1000 and a.c == 1100
    and b.g == 50 and b.s == 30 and b.n == 2 and b.o == 1100 and b.c == 1120, a and (a.g .. " " .. tostring(a.o) .. " " .. tostring(a.c)))
  check("days: unexplained income and spending are keys of the row", a.unexplained == 100 and b.unexplained == 50 and b.other == 30)
  check("days: goldSince is the time of the first row", me().goldSince == reset - 3600, me().goldSince)
  local base = ns.DB.settings.gold.dayBase
  check("days: the day base is written once, account-wide: server, the reset's second of the day", base.kind == "server" and base.offset == M.resetAt and base.since == reset - 3600, base.offset)
  check("days: the week anchor is written with it", ns.DB.settings.gold.weekAnchor ~= nil and (ns.DB.settings.gold.weekAnchor - M.resetAt) % DAY == 0)
  check("days: no error in the day writer", E._dayErr == nil, E._dayErr)

  -- ── the reset reading: 0, 86400, nil and everything that is not a plain number in range ─────────────────────
  do
    local function read(v) M.resetSecs = v; local r = G.readReset(); M.resetSecs = nil; return r end
    check("base: secs = 0 is not a reading", read(0) == nil)
    check("base: secs = 86400 is a reading", read(86400) == 86400)
    check("base: no answer is not a reading", read(false) == nil)
    check("base: a negative, a too large, a text and a NaN answer are not readings", read(-5) == nil and read(86401) == nil and read("3600") == nil and read(0 / 0) == nil)
    local secret = 4321.5
    M.secrets[secret] = true
    check("base: a secret answer is not a reading and raises nothing", read(secret) == nil)
    M.secrets[secret] = nil
    local saved = C_DateAndTime.GetSecondsUntilDailyReset
    C_DateAndTime.GetSecondsUntilDailyReset = function() error("blocked") end
    check("base: a throwing client function is contained", G.readReset() == nil)
    C_DateAndTime.GetSecondsUntilDailyReset = nil
    _G.GetQuestResetTime = function() return 600 end
    check("base: the legacy GetQuestResetTime answers when the namespace does not", G.readReset() == 600)
    _G.GetQuestResetTime = nil
    check("base: neither function present is no reading", G.readReset() == nil)
    C_DateAndTime.GetSecondsUntilDailyReset = saved
    check("base: 86400 s to the reset is the same offset as 0 s after it", G.offsetOf(reset, 86400) == M.resetAt)
    -- a jitter of a second or two around the reading does not move the offset
    local ok = true
    for j = -2, 2 do if G.offsetOf(reset - 5000 + j, 5000) ~= M.resetAt or G.offsetOf(reset - 5000, 5000 + j) ~= M.resetAt then ok = false end end
    check("base: a 1 s jitter in the reading gives the same offset (rounded to 900 s)", ok)
    -- later readings: within 900 s nothing is recorded; a different one is recorded once, dated, and moves no key
    local keyBefore = G.dayKey(M.epoch, G.baseStored())
    M.resetSecs = (DAY - ((M.epoch - M.resetAt) % DAY)) + 1
    G.checkBase(M.epoch)
    check("base: a later reading 1 s off records nothing", base.changes == nil)
    M.resetSecs = (DAY - ((M.epoch - M.resetAt) % DAY)) - 3600
    if M.resetSecs <= 0 then M.resetSecs = M.resetSecs + DAY end
    G.checkBase(M.epoch); G.checkBase(M.epoch + 50)
    check("base: a reading an hour off is recorded once with its date", type(base.changes) == "table" and #base.changes == 1 and base.changes[1].at == M.epoch and base.changes[1].offset == (M.resetAt - 3600) % DAY, base.changes and #base.changes)
    check("base: the stored offset and every key stay", base.offset == M.resetAt and G.dayKey(M.epoch, G.baseStored()) == keyBefore and days()[kA] == a and days()[kB] == b)
    money(7)
    check("base: the next credit still lands on the key of the stored base", days()[kB].g == 57 and count(days()) == 2)
    M.resetSecs = nil
  end

  -- ── a PC time zone change moves no key ──────────────────────────────────────────────────────────────────────
  do
    local b0 = G.baseStored()
    local keys = {}
    for i = 0, 47 do keys[i] = G.dayKey(reset + i * 1800, b0) end
    _G.date = function(fmt, t)   -- the PC clock nine hours east
      fmt = fmt or "%c"
      if fmt:sub(1, 1) == "!" then return realDate(fmt, t) end
      return realDate("!" .. fmt, (t or M.epoch) + 9 * 3600)
    end
    local ok = true
    for i = 0, 47 do if G.dayKey(reset + i * 1800, b0) ~= keys[i] then ok = false end end
    money(3)
    check("zone: every key is the same after the PC time zone changed", ok)
    check("zone: a credit after the change lands on the same row", days()[kB].g == 60 and count(days()) == 2)
    _G.date = realDate
    -- keys and their starts agree for any offset, also one late in the UTC day
    local okRound = true
    for _, off in ipairs({ 0, 900, 25200, 54000, 82800, 85500 }) do
      local fb = { offset = off }
      for i = 0, 400 do
        local t = 1700000000 + i * 40007
        local k = G.dayKey(t, fb)
        local s = G.keyStart(k, fb)
        if not (s and s <= t and t < s + DAY and G.dayKey(s, fb) == k and G.dayKey(s - 1, fb) ~= k) then okRound = false end
      end
    end
    check("zone: a key's start is the first second that has that key, for every base offset", okRound)
    check("zone: keyStart crosses a leap day and a year end", G.keyStart("20280301", { offset = 0 }) - G.keyStart("20280228", { offset = 0 }) == 2 * DAY
      and G.keyStart("20270101", { offset = 0 }) - G.keyStart("20261231", { offset = 0 }) == DAY)
  end

  -- ── the first load ever: credits are held until the base is known ──────────────────────────────────────────
  fresh()
  M.resetSecs = false
  M.epoch, M.money = reset - 200, 2000
  login()
  money(10)
  check("first load: with no reading the credit is held in memory, nothing is written", count(days()) == 0 and G._held ~= nil and #G._held == 2 and (ns.DB.settings.gold == nil or ns.DB.settings.gold.dayBase == nil), G._held and #G._held)
  M.epoch = reset + 200; M.now = M.now + 5
  M.resetSecs = nil
  money(5)
  check("first load: once the client answers, the held credit is written on the day it happened and the new one on its own", G._held == nil and days()[kA] and days()[kA].g == 10 and days()[kA].o == 2000 and days()[kB] and days()[kB].g == 5 and days()[kB].o == 2010
    and ns.DB.settings.gold.dayBase.kind == "server", count(days()))
  -- no answer for 30 s: the PC's midnight, marked local
  fresh()
  M.resetSecs = false
  M.epoch, M.money = reset - 200, 2000
  login()
  money(10)
  M.now = M.now + 20; M.runTimers()
  check("first load: 20 s without an answer still holds", count(days()) == 0 and G._held ~= nil)
  money(4)
  M.now = M.now + 11; M.runTimers()
  local lb = ns.DB.settings.gold and ns.DB.settings.gold.dayBase
  check("first load: after 30 s the base is the PC's midnight, marked local", lb ~= nil and lb.kind == "local" and lb.offset % 900 == 0 and lb.offset >= 0 and lb.offset < DAY, lb and lb.kind)
  local sumG = 0
  for _, r in pairs(days()) do sumG = sumG + r.g end
  check("first load: the held credits are flushed by the timer, none lost", G._held == nil and sumG == 14, sumG)
  M.resetSecs = nil
  money(1)
  login(true)
  check("first load: a local base stays local when the client answers later; the reading is recorded", ns.DB.settings.gold.dayBase.kind == "local" and (lb.offset == M.resetAt or (type(lb.changes) == "table" and #lb.changes == 1)))
  -- a logout inside the 30 s writes what is held
  fresh()
  M.resetSecs = false
  M.epoch, M.money = reset - 200, 2000
  login()
  money(25)
  M.fire("PLAYER_LOGOUT")
  check("first load: a logout inside the 30 s writes the held credits on a local base", G._held == nil and count(days()) == 1 and ns.DB.settings.gold.dayBase.kind == "local")
  M.resetSecs = nil

  -- ── a late quest claim after a rollover moves on the original day ──────────────────────────────────────────
  fresh()
  M.epoch, M.money = reset - 1, 500
  login()
  money(300)
  check("late quest: the income is unexplained on the day before the reset", days()[kA] and days()[kA].unexplained == 300)
  M.epoch = reset + 1; M.now = M.now + 2
  M.fire("QUEST_TURNED_IN", 4322, 0, 300)
  local ra = days()[kA]
  check("late quest: the claim after the rollover moves it on the original day: unexplained down, quests up", ra.unexplained == nil and ra.quests == 300 and ra.g == 300 and ra.n == 1, tostring(ra.unexplained) .. " " .. tostring(ra.quests))
  check("late quest: nothing lands on the new day", days()[kB] == nil)
  local ses = ns.Recorder.current()
  check("late quest: the session ledger and the journal row follow", ses.gold.quests == 300 and select(3, E.rowParse(ses.goldLog[#ses.goldLog])) == "quests" and me().gold.quests == 300)

  -- ── active seconds ──────────────────────────────────────────────────────────────────────────────────────────
  do
    G._tickAt = nil
    G.tick()
    M.now = M.now + 10; G.tick()
    M.now = M.now + 500; G.tick()   -- a tick that came late counts as one tick length
    local kNow = G.dayKey(M.epoch, G.baseStored())
    check("played: each tick adds the time since the last one, capped at the tick length", days()[kNow] and days()[kNow].t == 20, days()[kNow] and days()[kNow].t)
    check("played: a day with play and no purse change stores no balance of its own", days()[kNow].g == 0 and days()[kNow].n == 0 and days()[kNow].o == nil and days()[kNow].c == nil)
    local pd = G.period("today", "char").days[1]
    check("played: read back, such a day stands on the close of the row before it", pd and pd.key == kNow and pd.o == M.money and pd.c == M.money and days()[kA].c == M.money, pd and pd.c)
    money(40)
    check("played: the day's first change keeps the opening balance", days()[kNow].o == M.money - 40 and days()[kNow].c == M.money and days()[kNow].n == 1)
  end

  -- ── gold changed while away is written into the day it is discovered, with the gap ──────────────────────────
  do
    M.fire("PLAYER_LOGOUT")
    local seen = me().seen
    ns._test.newLoad()
    M.epoch = M.epoch + 3 * DAY + 5; M.now = M.now + 50
    M.money = M.money + 900
    login()
    M.runTimers()
    local k = G.dayKey(M.epoch, G.baseStored())
    local r = days()[k]
    check("away: the change lands on the day it was discovered, neither gained nor spent", r and r.away == 900 and r.g == 0 and r.s == 0 and r.n == 1 and r.c - r.o == 900, r and r.away)
    local s2 = ns.Recorder.current()
    local _, d, src, _, ref = E.rowParse(s2.goldLog[#s2.goldLog])
    check("away: the journal row carries the seconds since the character was last seen", src == "away" and d == 900 and ref == ("gap=%d"):format(M.epoch - seen), ref)
    check("away: the character's seen time is this login", me().seen == M.epoch)
  end

  -- ── weeks ───────────────────────────────────────────────────────────────────────────────────────────────────
  do
    local b0 = G.baseStored()
    local anchor = ns.DB.settings.gold.weekAnchor
    local w0 = G.weekStart(G.dayStart(M.epoch, b0), b0)
    local okW = (w0 - anchor) % (7 * DAY) == 0
    for i = 0, 6 do if G.weekStart(w0 + i * DAY, b0) ~= w0 then okW = false end end
    check("week: seven day keys from the stored anchor are one week", okW and G.weekStart(w0 + 7 * DAY, b0) == w0 + 7 * DAY and G.weekStart(w0 - 1, b0) == w0 - 7 * DAY)
    M.weekStart = anchor + 3 * DAY
    G.anchorWeek(M.epoch)
    check("week: the anchor is written once", ns.DB.settings.gold.weekAnchor == anchor)
    M.weekStart = nil
    ns.DB.settings.gold.weekAnchor = nil
    local mon = G.weekStart(G.dayStart(M.epoch, b0), b0)
    check("week: without an anchor a week starts on a Monday of the day base", realDate("!%w", mon) == "1" and (mon - b0.offset) % DAY == 0, realDate("!%a", mon))
    -- the countdown is the fallback when the start time is not answered
    local savedW = C_DateAndTime.GetWeeklyResetStartTime
    C_DateAndTime.GetWeeklyResetStartTime = nil
    C_DateAndTime.GetSecondsUntilWeeklyReset = function() return 2 * DAY end
    check("week: the weekly countdown anchors it when the start time is missing", G.anchorWeek(M.epoch) == M.epoch + 2 * DAY)
    C_DateAndTime.GetWeeklyResetStartTime, C_DateAndTime.GetSecondsUntilWeeklyReset = savedW, nil
    ns.DB.settings.gold.weekAnchor = anchor
  end

  -- ── 10,000 random purse changes: the row identities, the chain, the ledger, one block written ──────────────
  fresh()
  M.epoch, M.money = reset - 5 * DAY + 123, 500000
  ns.DB.characters["Player-1-000009"] = { name = "Alty", realm = "Realm", gold = { balance = 777, gained = 800, spent = 23 }, goldDays = { ["20260101"] = { g = 800, s = 23, o = 0, c = 777, t = 60, n = 2, looted = 800, other = 23 } } }
  ns.DB.characters["Player-1-000010"] = { name = "Faraway", realm = "Other Realm", gold = { balance = 5 } }
  local others = { deepcopy(ns.DB.characters["Player-1-000009"]), deepcopy(ns.DB.characters["Player-1-000010"]) }
  login()
  local seed0 = M.money
  math.randomseed(20261118)
  local ops, away = 0, 0
  M.sellPrice[2589] = 13
  for i = 1, 10000 do
    M.now = M.now + 4 + math.random(0, 12)
    M.epoch = M.epoch + math.random(0, 600)
    local op = math.random(1, 12)
    local n = math.random(1, 5000)
    if op == 1 then M.fire("LOOT_OPENED"); money(n)
    elseif op == 2 then M.fire("QUEST_TURNED_IN", 100 + i, 0, n); money(n)
    elseif op == 3 then money(n); M.fire("QUEST_TURNED_IN", 100 + i, 0, n)                -- claimed a moment later
    elseif op == 4 then money(n)                                                             -- nothing explains it
    elseif op == 5 then
      M.units.NPC = { name = "Merchant Bob" }; M.fire("MERCHANT_SHOW")
      M.bags[0][3] = { itemID = 2589, quality = 1, stackCount = 5 }
      C_Container.UseContainerItem(0, 3); M.bags[0][3] = nil
      money(65); money(-math.min(n, M.money))
      M.fire("MERCHANT_CLOSED"); M.units.NPC = nil
    elseif op == 6 then
      M.units.NPC = { name = "Merchant Bob" }; M.fire("MERCHANT_SHOW")
      M.repairCost = math.min(n, M.money); M.fire("UPDATE_INVENTORY_DURABILITY")
      RepairAllItems(); money(-M.repairCost); M.repairCost = 0
      M.fire("MERCHANT_CLOSED"); M.units.NPC = nil
    elseif op == 7 then M.units.NPC = { name = "Trainer Tom" }; M.fire("TRAINER_SHOW"); money(-math.min(n, M.money)); M.fire("TRAINER_CLOSED"); M.units.NPC = nil
    elseif op == 8 then M.fire("MAIL_SHOW"); M.inbox = { { sender = "Rando", subject = "gold", money = n } }; TakeInboxMoney(1); money(n); M.fire("MAIL_CLOSED"); M.inbox = {}
    elseif op == 9 then money(-math.min(n, M.money))
    elseif op == 10 then M.fire("AUCTION_HOUSE_SHOW"); money(-math.min(n, M.money)); M.fire("AUCTION_HOUSE_CLOSED")
    elseif op == 11 and i % 7 == 0 then
      -- a relog with the purse changed elsewhere
      M.fire("PLAYER_LOGOUT"); ns._test.newLoad()
      M.epoch = M.epoch + math.random(60, 30000)
      local d = math.random(-math.min(2000, M.money), 2000)
      M.money = M.money + d; away = away + d
      login(); M.runTimers()
    else M.fire("LOOT_OPENED"); money(n); M.now = M.now + 1; M.fire("QUEST_TURNED_IN", 100 + i, 0, 7); money(7) end
    ops = ops + 1
  end
  M.runTimers()
  do
    local c = me()
    local keys = {}
    for k in pairs(c.goldDays) do keys[#keys + 1] = k end
    table.sort(keys)
    local bad, sumG, sumS, sumA, per = {}, 0, 0, 0, {}
    for i, k in ipairs(keys) do
      local r = c.goldDays[k]
      local inS, outS = 0, 0
      for _, sk in ipairs(G.IN) do inS = inS + (r[sk] or 0); per[sk] = (per[sk] or 0) + (r[sk] or 0) end
      for _, sk in ipairs(G.OUT) do outS = outS + (r[sk] or 0); per[sk] = (per[sk] or 0) + (r[sk] or 0) end
      if inS ~= r.g then bad[#bad + 1] = k .. " income keys " .. inS .. " ~= g " .. r.g end
      if outS ~= r.s then bad[#bad + 1] = k .. " spend keys " .. outS .. " ~= s " .. r.s end
      if r.c - r.o ~= r.g - r.s + (r.away or 0) then bad[#bad + 1] = k .. " c - o" end
      if i > 1 and c.goldDays[keys[i - 1]].c ~= r.o then bad[#bad + 1] = k .. " does not open on the close of the day before" end
      for sk, v in pairs(r) do
        if type(v) ~= "number" or v ~= math.floor(v) then bad[#bad + 1] = k .. "." .. sk .. " is not an integer" end
        if v == 0 and sk ~= "g" and sk ~= "s" and sk ~= "t" and sk ~= "n" and sk ~= "o" and sk ~= "c" then bad[#bad + 1] = k .. "." .. sk .. " is a stored zero" end
        if v < 0 and sk ~= "away" then bad[#bad + 1] = k .. "." .. sk .. " is negative" end
      end
      sumG, sumS, sumA = sumG + r.g, sumS + r.s, sumA + (r.away or 0)
    end
    check("random: 10,000 events ran over several days", ops == 10000 and #keys >= 20, #keys)
    check("random: on every row the income keys sum to g, the spend keys to s, and c - o = g - s + away; each day opens on the close before", #bad == 0, table.concat(bad, "; "):sub(1, 300))
    check("random: the rows sum to the lifetime ledger since goldSince", sumG == c.gold.gained and sumS == c.gold.spent and sumA == (c.gold.away or 0) and sumA == away, sumG .. " " .. c.gold.gained .. " " .. sumS .. " " .. c.gold.spent .. " " .. sumA .. " " .. tostring(c.gold.away))
    local okSrc, badSrc = true, nil
    for _, sk in ipairs(G.IN) do if sk ~= "unexplained" and (per[sk] or 0) ~= (c.gold[sk] or 0) then okSrc, badSrc = false, sk end end
    for _, sk in ipairs(G.OUT) do if (per[sk] or 0) ~= (c.gold[sk] or 0) then okSrc, badSrc = false, sk end end
    check("random: every source's rows sum to its lifetime ledger key", okSrc, badSrc)
    check("random: balance = the seed + gained - spent + away", c.gold.balance == M.money and c.gold.balance == seed0 + sumG - sumS + sumA)
    check("random: the last row closes on the purse, the first opens on the seed", c.goldDays[keys[#keys]].c == M.money and c.goldDays[keys[1]].o == seed0)
    check("random: no error in the day writer", E._dayErr == nil, E._dayErr)
    check("random: the other characters' blocks are untouched (only the logged-in block is written)", same(ns.DB.characters["Player-1-000009"], others[1]) and same(ns.DB.characters["Player-1-000010"], others[2]))
    local extra = {}
    for k in pairs(ns.DB.settings.gold) do if k ~= "dayBase" and k ~= "weekAnchor" then extra[#extra + 1] = k end end
    check("random: settings.gold holds the day base and the week anchor, nothing per character", #extra == 0, table.concat(extra, ","))
    -- the period model reads the same numbers back
    local hist = G.period("history", "char")
    check("period: the history sums every row", hist.ledger.gained == sumG and hist.ledger.spent == sumS and hist.ledger.away == sumA and #hist.days == #keys and hist.days[1].key == keys[#keys])
    local today, yest = G.period("today", "char"), G.period("yesterday", "char")
    local kT = G.dayKey(M.epoch, G.baseStored())
    local kY = G.dayKey(M.epoch - DAY, G.baseStored())
    check("period: today and yesterday are their rows", today.ledger.gained == (c.goldDays[kT] and c.goldDays[kT].g or 0) and yest.ledger.gained == (c.goldDays[kY] and c.goldDays[kY].g or 0)
      and today.from == G.dayStart(M.epoch, G.baseStored()) and today.to - today.from == DAY)
    local l7 = G.period("last7", "char")
    local want7 = 0
    for i = 0, 6 do local r = c.goldDays[G.dayKey(M.epoch - i * DAY, G.baseStored())]; if r then want7 = want7 + r.g - r.s end end
    check("period: the last 7 days are seven keys", l7.ledger.gained - l7.ledger.spent == want7 and #l7.days <= 7)
    check("metric: one resolver for every surface", G.metric("balance") == M.money and G.metric("net", "char", "today") == today.ledger.gained - today.ledger.spent
      and G.metric("earned", "char", "last7") == l7.ledger.gained and G.metric("looted", "char", "today") == (today.ledger.looted or 0)
      and G.metric("net", "char", "all") == c.gold.gained - c.gold.spent)
    local acct = G.period("history", "account")
    check("period: the account is a sum over character blocks at read time", acct.ledger.gained == sumG + 800 and acct.chars == 2 and G.metric("balance", "account") == M.money + 777 + 5)
    -- the month is a sum of server days
    local mo = G.period("month", "char")
    local wantM = 0
    for _, k in ipairs(keys) do if k:sub(1, 6) == kT:sub(1, 6) then wantM = wantM + c.goldDays[k].g end end
    check("period: the month sums the server days whose key is in it", mo.ledger.gained == wantM and realDate("!%d", mo.from) == "01")

    -- ── the acknowledgement prune leaves the day rows ─────────────────────────────────────────────────────────
    local before = deepcopy(c.goldDays)
    local roster = deepcopy(ns.DB.characters)
    local ack = { sessions = {}, through = M.epoch + 10 * DAY }
    for id in pairs(ns.DB.sessions) do ack.sessions[id] = true end
    M.fire("PLAYER_LOGOUT")
    ns.applyAck(ack, "file")
    local left = 0
    for id in pairs(ns.DB.sessions) do if id ~= ns.DB.active then left = left + 1 end end
    roster[ME].seen = c.seen   -- (the logout stamped it)
    check("ack: every acked session is pruned", left == 0, left)
    check("ack: goldDays, goldSince and every character block stay", same(c.goldDays, before) and c.goldSince ~= nil and same(ns.DB.characters, roster))
    check("ack: the history still sums to the lifetime ledger with no session left", G.period("history", "char").ledger.gained == c.gold.gained)
  end

  -- ── a played tick between the login read and the booking of a change while away ─────────────────────────────
  -- (the booking runs one frame after the read; the 10 s ticker may land in between and must not open the day's
  -- row on the new balance)
  do
    fresh()
    M.epoch, M.money = reset - 3600, 1000
    login()
    money(100)                                      -- the day before closes on 1100
    M.fire("PLAYER_LOGOUT"); ns._test.newLoad()
    M.epoch = reset + 600; M.now = M.now + 50
    M.money = 700                                   -- 400 spent on another PC
    G._tickAt = M.now - 10
    M.fire("PLAYER_ENTERING_WORLD", true, false)    -- the login read; the booking waits for the next frame
    local seeded = me().gold.balance == 700 and (me().gold.away or 0) == 0
    G.tick()
    local mid = days()[kB]
    check("tick at login: the tick lands between the read and the booking", seeded and mid ~= nil and mid.t == 10 and mid.n == 0, mid and mid.t)
    check("tick at login: the tick invents no opening or closing balance", mid ~= nil and mid.o == nil and mid.c == nil)
    M.runTimers()
    local a, b = days()[kA], days()[kB]
    check("tick at login: the away change opens the row on the old balance and closes it on the new one", b and b.o == 1100 and b.c == 700 and b.away == -400 and b.n == 1, b and (tostring(b.o) .. " " .. tostring(b.c)))
    check("tick at login: c - o = g - s + away, and the day opens on the close of the day before", b and b.c - b.o == b.g - b.s + b.away and a.c == b.o)
  end

  -- ── every credit of one purse change lands on one day row, also at the reset second ─────────────────────────
  do
    fresh()
    M.epoch, M.money = reset - 3600, 1000
    login()
    money(1)                                        -- the day base is known
    local realST = _G.GetServerTime
    local t = reset - 2
    _G.GetServerTime = function() t = t + 1; return t end   -- the server second ticks over between two readings
    money(500)                                      -- gained, its source (unexplained) and the open claim's time
    local og = E._openGain
    M.now = M.now + 1
    M.fire("QUEST_TURNED_IN", 4323, 0, 500)         -- the late claim moves on the row the income was booked on
    _G.GetServerTime = realST
    local bad, hit = {}, nil
    for k, r in pairs(days()) do
      local inS = 0
      for _, sk in ipairs(G.IN) do inS = inS + (r[sk] or 0) end
      if inS ~= r.g then bad[#bad + 1] = k .. " income keys " .. inS .. " ~= g " .. r.g end
      if r.quests == 500 then hit = k end
    end
    check("reset second: the gain and its source are on one row, the income keys sum to g on every row", #bad == 0, table.concat(bad, "; "))
    check("reset second: the open claim carries the time the gain was booked at, and the quest moved on that row", og ~= nil and hit ~= nil and G.dayKey(og.epoch, G.baseStored()) == hit
      and days()[hit].unexplained == (hit == kA and 1 or nil), tostring(hit))
    check("reset second: no error in the day writer", E._dayErr == nil, E._dayErr)
  end

  -- ── a day's label is read from its key, whatever the PC's time zone ─────────────────────────────────────────
  do
    local MON = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
    local function want(k) return MON[tonumber(k:sub(5, 6))] .. " " .. tonumber(k:sub(7, 8)) end
    local okL, badL = true, nil
    for _, east in ipairs({ -11, -5, 0, 5, 9, 13 }) do
      _G.date = function(fmt, tt)
        fmt = fmt or "%c"
        if fmt:sub(1, 1) == "!" then return realDate(fmt, tt) end
        return realDate("!" .. fmt, (tt or M.epoch) + east * 3600)
      end
      for _, off in ipairs({ 0, 25200, 54000, 85500 }) do
        local fb = { offset = off }
        for i = 0, 40 do
          local k = G.dayKey(1795000000 + i * 79003, fb)
          if G.dayLabel(k, fb) ~= want(k) or G.startLabel(G.keyStart(k, fb), fb) ~= want(k) then okL, badL = false, ("%s at UTC%+d, offset %d: %s"):format(k, east, off, G.dayLabel(k, fb)) end
        end
      end
    end
    _G.date = realDate
    check("label: a day's label is the date its key names, for a PC far east or west and every day base", okL, badL)
    check("label: 20261118 reads Nov 18, 20270101 reads Jan 1", G.dayLabel("20261118") == "Nov 18" and G.dayLabel("20270101") == "Jan 1" and G.fmtKey("20261118", "%B %Y") == "November 2026", G.dayLabel("20261118"))
  end

  -- ── the Days strip: 30 fixed day slots ending today, a day without a row leaves its slot empty ──────────────
  do
    fresh()
    M.epoch, M.money = reset + 3600, 1000
    login()
    money(10); money(-4)
    local b0 = G.baseStored()
    local function k(n) return G.dayKey(M.epoch - n * DAY, b0) end
    local d = days()
    d[k(5)] = { g = 500, s = 100, t = 60, n = 2, o = 100, c = 500, looted = 500, other = 100 }
    d[k(29)] = { g = 0, s = 70, t = 60, n = 1, o = 170, c = 100, other = 70 }
    d[k(30)] = { g = 9, s = 0, t = 60, n = 1, o = 161, c = 170, looted = 9 }      -- one day too old for the strip
    d[k(150)] = { g = 9000, s = 0, t = 60, n = 1, o = 0, c = 9000, looted = 9000 }
    local sv = G.stripDays("char")
    local filled, holes = 0, 0
    for i = 1, 30 do if sv[i] == false then holes = holes + 1 elseif type(sv[i]) == "table" then filled = filled + 1 end end
    check("strip: 30 slots, one per day, never fewer", filled + holes == 30 and #sv == 30, filled + holes)
    check("strip: today is the last slot, 5 days ago the 25th, 29 days ago the first", sv[30] and sv[30].key == k(0) and sv[30].v == 6 and sv[30].live == true
      and sv[25] and sv[25].key == k(5) and sv[25].v == 400 and sv[1] and sv[1].key == k(29) and sv[1].v == -70, sv[25] and sv[25].key)
    check("strip: a day without a row leaves its slot empty, an older day is not packed in", filled == 3 and holes == 27 and sv[29] == false and sv[2] == false)
    check("strip: a slot's label is its day's", sv[25].label == G.dayLabel(k(5)))
    check("strip: the same 30 days whatever the period shown", #G.period("history", "char").days == 5)
  end

  -- ── a 0.9.43 save file loads with no invented history ───────────────────────────────────────────────────────
  do
    local old = { schema = 2, settings = { welcomed = true }, sessions = {}, combat = { fights = {}, fightSeq = 0 }, loot = { log = {} }, story = { events = {} },
      characters = {
        [ME] = { name = "Hart", realm = "Realm", xp = { gained = 0 }, played = {}, gold = { balance = 5000, gained = 9000, spent = 4000, looted = 1200, quests = 7800, repairs = 4000 } },
        ["Player-1-000009"] = { name = "Alty", realm = "Realm", xp = { gained = 0 }, played = {}, gold = { balance = 31, gained = 31, spent = 0, looted = 31 } },
      } }
    local alt0, gold0 = deepcopy(old.characters["Player-1-000009"]), deepcopy(old.characters[ME].gold)
    fresh(old)
    M.epoch, M.money = reset + 3600, 5000
    login()
    local c = me()
    check("0.9.43 save: no day row, no goldSince, no settings.gold invented by loading", c.goldDays == nil and c.goldSince == nil and ns.DB.settings.gold == nil)
    check("0.9.43 save: the lifetime ledger is as it was", same(c.gold, gold0))
    check("0.9.43 save: the roster facts are written on the logged-in block", c.class == "WARRIOR" and c.faction == "Alliance" and c.level == M.level and c.seen == M.epoch and c.name == "Hart" and c.realm == "Realm", tostring(c.class))
    check("0.9.43 save: the alt's block is untouched: no class, no seen, no history", same(ns.DB.characters["Player-1-000009"], alt0))
    money(1)
    check("0.9.43 save: the first change after the update starts the history today", count(c.goldDays) == 1 and c.goldDays[kB] and c.goldDays[kB].o == 5000 and c.goldSince == M.epoch)
    -- with the purse changed while the old version ran: one away row today, no gap (the old save has no seen)
    old = { schema = 2, settings = {}, sessions = {}, combat = { fights = {}, fightSeq = 0 }, loot = { log = {} }, story = { events = {} },
      characters = { [ME] = { name = "Hart", realm = "Realm", xp = { gained = 0 }, played = {}, gold = { balance = 5000, gained = 9000, spent = 4000 } } } }
    fresh(old)
    M.epoch, M.money = reset + 3600, 5600
    login(); M.runTimers()
    c = me()
    local s3 = ns.Recorder.current()
    local _, d3, src3, _, ref3 = E.rowParse(s3.goldLog[1])
    check("0.9.43 save: a balance that differs is one away row on today's day, with no gap claimed", count(c.goldDays) == 1 and c.goldDays[kB].away == 600 and c.goldDays[kB].o == 5000 and src3 == "away" and d3 == 600 and ref3 == "", ref3)
    -- a level-up and a logout refresh the facts
    M.level = M.level + 1; M.fire("PLAYER_LEVEL_UP", M.level)
    check("roster facts: a level-up writes the level", c.level == M.level)
    M.level = M.level - 1
    M.epoch = M.epoch + 77; M.fire("PLAYER_LOGOUT")
    check("roster facts: a logout writes seen", c.seen == M.epoch)
    -- a renamed character: name and realm are refreshed at login
    local savedName = _G.UnitNameUnmodified
    _G.UnitNameUnmodified = function() return "Hartnew" end
    ns._test.newLoad(); login(true)
    check("roster facts: name and realm are refreshed at each login", c.name == "Hartnew")
    _G.UnitNameUnmodified = savedName
    ns._test.newLoad(); login(true)
    local hidden = "Hart"
    M.secrets[hidden] = true
    ns._test.newLoad(); login(true)
    check("roster facts: a name the client hides keeps the stored one", c.name == "Hart")
    M.secrets[hidden] = nil
  end

  -- ── the suite's save file back in place, its session resumed as a /reload does ──────────────────────────────
  ns.Recorder.discard()
  ns.DB = main.db
  G._held, G._baseWait, G._flushTimer, G._tickAt = nil, nil, nil, nil
  E._openGain, E._questMoney = nil, nil
  M.timers = {}
  M.epoch, M.now, M.resetSecs, M.weekStart = main.epoch, M.now + 100, main.resetSecs, main.weekStart
  M.money = main.money
  for _, e in ipairs({ "MERCHANT_CLOSED", "MAIL_CLOSED", "AUCTION_HOUSE_CLOSED", "TRAINER_CLOSED", "TRADE_CLOSED" }) do M.fire(e) end
  M.units.NPC = nil; M.inbox = {}
  ns._test.newLoad()
  M.fire("PLAYER_ENTERING_WORLD", false, true); M.runTimers()
  print = realPrint
  check("days: the suite's save file is back, its session resumed", ns.DB == main.db and ns.Recorder.current() ~= nil and ns.DB.characters[ME].gold.balance == main.money)
end
