-- Gold journal tests (everbuff-wow-addon #36, 0.9.40). Loaded by tests/run_tests.lua after the #31 gold tests:
--   dofile("tests/gold_journal.lua")({ check = check, M = M, ns = ns })
-- Every source writes one goldLog row (mono TAB delta TAB source TAB balance TAB ref) with the right sign, balance
-- and ref; completed trades land in trades[] with both sides; mail carries rel; the cap coalesces and never drops a
-- trade, mail, away or unexplained row; the balance chain holds over the whole played session.
return function(P)
  local check, M, ns = P.check, P.M, P.ns
  local E = ns.Emitter
  local function ses() return ns.Recorder.current() end
  local function row(i, s)
    local log = (s or ses()).goldLog
    i = i or #log
    local mono, d, src, bal, ref = E.rowParse(log[i] or "")
    return { mono = mono, delta = d, src = src, bal = bal, ref = ref, refT = E.refParse(ref) }
  end
  local function money(d) M.money = M.money + d; M.fire("PLAYER_MONEY") end
  local function later() M.now = M.now + 10 end
  local function is(name, r, src, delta, ref)
    check("#36 " .. name .. ": source, sign, balance and ref",
      r.src == src and r.delta == delta and r.bal == M.money and (ref == nil or r.ref == ref),
      ("%s %s %s %s [%s]"):format(tostring(r.src), tostring(r.delta), tostring(r.bal), tostring(M.money), tostring(r.ref)))
  end

  M.runTimers(); later()
  -- the suite before left windows open; a played session starts with none
  for _, e in ipairs({ "MERCHANT_CLOSED", "MAIL_CLOSED", "AUCTION_HOUSE_CLOSED", "TRAINER_CLOSED", "TRADE_CLOSED" }) do M.fire(e) end
  M.units.NPC = nil; later()
  local s0 = ses()
  check("#36 a session started by 0.9.40 carries goldLog, trades and goldLogDropped", type(s0.goldLog) == "table" and type(s0.trades) == "table" and s0.goldLogDropped == 0)
  local n0 = #s0.goldLog

  -- income
  M.fire("LOOT_OPENED"); money(150)
  is("looted coin", row(), "looted", 150, "")
  check("#36 the row is written at the purse change: mono is GetTime() with one decimal", row().mono == ("%.1f"):format(M.now), row().mono)
  check("#36 one row per purse change", #s0.goldLog == n0 + 1, #s0.goldLog - n0)
  later()
  M.fire("QUEST_TURNED_IN", 4321, 100, 250); money(250)
  is("quest reward after the turn-in", row(), "quests", 250, "quest=4321")
  later()
  local before = #s0.goldLog
  money(300)
  is("income with no source yet", row(), "unexplained", 300, "")
  M.fire("QUEST_TURNED_IN", 4322, 0, 300)
  is("a quest claiming the income a moment later rewrites that row", row(), "quests", 300, "quest=4322")
  check("#36 the claimed income is still one row", #s0.goldLog == before + 1)
  later()
  money(77)
  is("income nothing explains stays unexplained", row(), "unexplained", 77, "")
  M.now = M.now + 4; M.fire("QUEST_TURNED_IN", 4323, 0, 77)
  is("a turn-in after 3 s does not claim it", row(), "unexplained", 77, "")
  later()

  -- merchant: sold with the item's vendor price, bought, repaired
  M.units.NPC = { name = "Merchant Bob" }; M.fire("MERCHANT_SHOW")
  M.bags[0][3] = { itemID = 2589, quality = 1, stackCount = 5 }; M.sellPrice[2589] = 13
  C_Container.UseContainerItem(0, 3); M.bags[0][3] = nil
  money(65)
  is("an item sold to a merchant", row(), "sold", 65, "item=2589;n=5;unit=13;npc=Merchant Bob")
  M.bags[0][4] = { itemID = 4306, quality = 1, stackCount = 2 }; M.sellPrice[4306] = 400
  C_Container.UseContainerItem(0, 4); M.bags[0][4] = nil
  money(1200)   -- an exploit signature: paid 3 times the vendor price
  local r = row()
  check("#36 a sale above the vendor price shows: unit times n differs from the delta", r.src == "sold" and tonumber(r.refT.unit) * tonumber(r.refT.n) == 800 and r.delta == 1200, r.ref)
  money(9)
  is("a sale the addon did not see asked for still names the merchant", row(), "sold", 9, "npc=Merchant Bob")
  M.merchant[2] = { id = 159, name = "Refreshing Spring Water", price = 25, qty = 5 }
  BuyMerchantItem(2, 5); money(-25)
  is("an item bought from a merchant", row(), "vendor", -25, "item=159;n=5;npc=Merchant Bob")
  RepairAllItems(); money(-500)
  is("a repair", row(), "repairs", -500, "npc=Merchant Bob")
  M.fire("MERCHANT_CLOSED"); later()

  M.units.NPC = { name = "Trainer Tom" }; M.fire("TRAINER_SHOW"); money(-1000)
  is("training", row(), "training", -1000, "npc=Trainer Tom")
  M.fire("TRAINER_CLOSED"); later()
  M.units.NPC = { name = "Flight Fay" }; M.fire("TAXIMAP_OPENED"); money(-200)
  is("a flight", row(), "flights", -200, "npc=Flight Fay")
  later(); M.units.NPC = nil
  M.fire("AUCTION_HOUSE_SHOW"); money(-60)
  is("an auction house deposit", row(), "auctions", -60, "")
  M.fire("AUCTION_HOUSE_CLOSED"); later()
  money(-10)
  is("spending nothing explains", row(), "other", -10, "")
  later()

  -- mail: who the sender is to the player
  ns.DB.characters["Player-1-000009"] = { name = "Alty", realm = "Realm" }
  ns.DB.characters["Player-1-000010"] = { name = "Faraway", realm = "Other Realm" }
  E.loadAlts()
  M.guild = { "Guildie-Realm" }; M.fire("GUILD_ROSTER_UPDATE")
  M.friends = { "Pal" }; M.fire("FRIENDLIST_UPDATE")
  M.fire("MAIL_SHOW")
  M.inbox = {
    { sender = "Alty", subject = "gold", money = 1000 },
    { sender = "Guildie", subject = "gold", money = 1001 },
    { sender = "Pal", subject = "gold", money = 1002 },
    { sender = "Rando", subject = "gold", money = 1003 },
    { sender = "Faraway", subject = "gold", money = 1004 },
    { sender = "Stormwind Auction House", subject = "Auction successful: Linen Cloth", money = 1005, invoice = { "seller", "Linen Cloth", "Buyerguy", 100, 120, 5, 6 } },
    { sender = "The Postmaster", subject = "Recovered items", money = 1006, canReply = false },
  }
  local want = { { "mail", "alt" }, { "mail", "guild" }, { "mail", "friend" }, { "mail", "stranger" }, { "mail", "stranger" }, { "auctionSales", "system" }, { "mail", "system" } }
  for i, w in ipairs(want) do
    TakeInboxMoney(i); money(M.inbox[i].money)
    is(("mail from %s"):format(M.inbox[i].sender), row(), w[1], M.inbox[i].money, ("sender=%s;rel=%s;cod=0"):format(M.inbox[i].sender, w[2]))
    local lr = ns.DB.loot.log[#ns.DB.loot.log]
    check(("#36 the loot.log mail row from %s carries rel=%s"):format(M.inbox[i].sender, w[2]), lr.money == M.inbox[i].money and lr.mail and lr.mail.rel == w[2], lr.mail and lr.mail.rel)
    M.now = M.now + 4
  end
  check("#36 an alt on another realm is not an alt", E.relOf("Faraway") == "stranger" and E.relOf("Faraway-OtherRealm") == "alt" and E.relOf("Alty-Realm") == "alt")
  M.inbox = { { sender = "Rando", subject = "ore", cod = 300, items = { { name = "Copper Ore", id = 2770, count = 10, quality = 1 } } } }
  TakeInboxItem(1, 1); money(-300)
  is("a COD payment", row(), "mailSpent", -300, "sender=Rando;rel=stranger;cod=300")
  later(); money(-30)
  is("postage", row(), "mailSpent", -30, "")
  M.fire("MAIL_CLOSED"); M.inbox = {}; later()

  -- trades
  local nt = #s0.trades
  M.units.NPC = { name = "Goldseller", guild = "Cheap Gold" }; M.fire("TRADE_SHOW")
  M.tradeWin = { gaveMoney = 0, gotMoney = 50000 }; M.fire("TRADE_MONEY_CHANGED"); M.fire("TRADE_ACCEPT_UPDATE", 1, 1)
  M.tradeWin = nil; M.fire("TRADE_TARGET_ITEM_CHANGED")   -- the client clears the window as it completes
  M.fire("UI_INFO_MESSAGE", 0, "Trade complete."); M.fire("TRADE_CLOSED"); M.units.NPC = nil
  money(50000)
  local tr = s0.trades[#s0.trades]
  check("#36 a gift trade (gold in, nothing out) is one trades[] entry", #s0.trades == nt + 1 and tr.partner == "Goldseller" and tr.guild == "Cheap Gold" and tr.rel == "stranger"
    and tr.gotMoney == 50000 and tr.gaveMoney == 0 and #tr.gave == 0 and #tr.got == 0 and tr.t == M.epoch and tr.mono == M.now, #s0.trades - nt)
  is("the gift's purse change", row(), "trade", 50000, ("partner=Goldseller;guild=Cheap Gold;rel=stranger;trade=%d"):format(#s0.trades))
  later()
  M.units.NPC = { name = "Alty" }; M.fire("TRADE_SHOW")
  M.tradeWin = { gaveMoney = 2000, gotMoney = 0, player = { { id = 2589, name = "Linen Cloth", count = 20 } }, target = { [2] = { id = 2770, name = "Copper Ore", count = 5 } } }
  M.fire("TRADE_PLAYER_ITEM_CHANGED"); M.fire("TRADE_TARGET_ITEM_CHANGED")
  money(-2000)   -- the purse moves before the client says complete
  M.fire("UI_INFO_MESSAGE", 0, "Trade complete."); M.tradeWin = nil; M.fire("TRADE_CLOSED")
  tr = s0.trades[#s0.trades]
  check("#36 a trade with items both ways and gold out: one entry, both sides as id:count", #s0.trades == nt + 2 and tr.rel == "alt" and tr.gaveMoney == 2000
    and tr.gave[1] == "2589:20" and tr.got[1] == "2770:5" and #tr.gave == 1 and #tr.got == 1, #s0.trades - nt)
  is("gold given in a trade", row(), "tradeSpent", -2000, ("partner=Alty;rel=alt;trade=%d"):format(#s0.trades))
  later()
  local rows0 = #s0.goldLog
  M.units.NPC = { name = "Pal" }; M.fire("TRADE_SHOW")
  M.tradeWin = { gaveMoney = 0, gotMoney = 0, target = { { id = 2770, name = "Copper Ore", count = 20 } } }; M.fire("TRADE_TARGET_ITEM_CHANGED")
  M.fire("UI_INFO_MESSAGE", 0, "Trade complete."); M.tradeWin = nil; M.fire("TRADE_CLOSED")
  tr = s0.trades[#s0.trades]
  check("#36 an items-only trade is written on the client's Trade complete, with no gold row", #s0.trades == nt + 3 and tr.rel == "friend" and tr.got[1] == "2770:20" and #s0.goldLog == rows0)
  later()
  M.units.NPC = { name = "Rando" }; M.fire("TRADE_SHOW")
  M.tradeWin = { gaveMoney = 0, gotMoney = 900 }; M.fire("TRADE_MONEY_CHANGED")
  M.fire("UI_INFO_MESSAGE", 0, "Trade cancelled."); M.tradeWin = nil; M.fire("TRADE_CLOSED")
  M.fire("TRADE_SHOW"); M.tradeWin = { gaveMoney = 100, gotMoney = 0 }; M.fire("TRADE_MONEY_CHANGED"); M.tradeWin = nil; M.fire("TRADE_CLOSED")
  later()
  check("#36 cancelled trades write nothing", #s0.trades == nt + 3 and #s0.goldLog == rows0)
  local errs0 = #M.errors
  M.units.NPC = { name = "Hidden" }; M.secrets["Hidden"] = true; M.fire("TRADE_SHOW"); money(5)
  r = row()
  check("#36 a partner name the client hides is left out, never a crash", r.src == "trade" and r.ref == "" and #M.errors == errs0, r.ref .. " " .. tostring(M.errors[#M.errors]))
  M.fire("TRADE_CLOSED"); M.units.NPC = nil; M.secrets["Hidden"] = nil; later()

  -- the journal matches the session's ledger key by key, and the balance chain holds over the whole session
  local function chain(s)
    local ok, bad = true, nil
    for i = 2, #s.goldLog do
      local a, b = row(i - 1, s), row(i, s)
      if b.bal - a.bal ~= b.delta then ok, bad = false, i end
    end
    return ok, bad
  end
  local okC, badC = chain(s0)
  check("#36 balance chain: each balance minus the one before is the delta, over the whole played session", okC and #s0.goldLog > 20, badC)
  local sums = {}
  for i = 1, #s0.goldLog do local x = row(i, s0); sums[x.src] = (sums[x.src] or 0) + math.abs(x.delta) end
  local okL, badL = true, nil
  for key, sign in pairs(E.GOLD_SIGN) do
    if key ~= "unexplained" and key ~= "away" and (s0.gold[key] or 0) ~= (sums[key] or 0) then okL, badL = false, key end
  end
  check("#36 the journal sums to the session ledger for every source key", okL, badL)
  for i = 1, #s0.goldLog do
    if s0.goldLog[i]:find("|", 1, true) or select(2, s0.goldLog[i]:gsub("\t", "")) ~= 4 then okL = false end
  end
  check("#36 every row has five TAB fields and no pipe", okL)

  -- away: the purse changed while the addon was off, with mail waiting at login
  local lastBal = row(#s0.goldLog, s0).bal
  ns._test.newLoad(); M.newMail = true; M.money = M.money + 777; M.fire("PLAYER_ENTERING_WORLD", true, false); M.runTimers()
  local s1 = ses()
  check("#36 the away row opens the new session's journal", s1 ~= s0 and #s1.goldLog == 1)
  is("gold changed while away, mail waiting", row(1, s1), "away", 777, "mailWaiting=1")
  check("#36 the away row continues the chain from the last session", row(1, s1).bal - lastBal == 777)
  M.newMail = false; later()
  ns._test.newLoad(); M.money = M.money - 50; M.fire("PLAYER_ENTERING_WORLD", false, true); M.runTimers()
  is("gold lost while away, no mail", row(), "away", -50, "")
  check("#36 away rows chain inside one session too", chain(s1))

  -- ref: separators stripped from values, numbers plain, empty when nothing is known
  check("#36 ref strips TAB, ; and = from values", E.refStr({ sender = "Bad\tNa;me=x|y", cod = 0 }) == "sender=BadNamexy;cod=0", E.refStr({ sender = "Bad\tNa;me=x|y", cod = 0 }))
  check("#36 ref is empty when nothing is known", E.refStr(nil) == "" and E.refStr({}) == "")

  -- the cap: coalescing past 4000 rows, never a trade, mail, away or unexplained row dropped
  do
    local fs, bal = { goldLog = {}, goldLogDropped = 0 }, 0
    local function put(key, n, ref)
      bal = bal + E.GOLD_SIGN[key] * n
      E._gbal, E._gref = bal, ref
      return E.goldRow(fs, key, n)
    end
    for i = 1, E.GOLD_CAP do put(i % 2 == 0 and "looted" or "vendor", 1) end
    check("#36 cap: 4000 rows fill normally", #fs.goldLog == 4000 and fs.goldLogDropped == 0)
    put("looted", 5); put("looted", 7)
    local x = row(nil, fs)
    check("#36 cap: consecutive looted rows past the cap merge (deltas summed, last balance, x counts the rows)", #fs.goldLog == 4000 and x.src == "looted" and x.delta == 13 and x.bal == bal and x.refT.x == "3", x.delta .. " " .. x.ref)
    put("sold", 6, { item = 5, n = 2, unit = 3, npc = "Bob" })
    check("#36 cap: a sold row after a looted row cannot merge and is counted dropped", #fs.goldLog == 4000 and fs.goldLogDropped == 1)
    bal = bal - 6   -- what the journal lost is in goldLogDropped
    put("trade", 100, { partner = "Goldseller", trade = 1 })
    put("tradeSpent", 40, { partner = "Goldseller", trade = 2 })
    put("mail", 50, { sender = "Rando", rel = "stranger", cod = 0 })
    put("mailSpent", 30, { sender = "Rando", rel = "stranger", cod = 30 })
    put("auctionSales", 20, { sender = "Auction House", rel = "system", cod = 0 })
    put("away", -25, { mailWaiting = 1 })
    put("unexplained", 9)
    check("#36 cap: trade, mail, away and unexplained rows are never dropped", #fs.goldLog == 4007 and fs.goldLogDropped == 1
      and row(4001, fs).src == "trade" and row(4003, fs).src == "mail" and row(4006, fs).src == "away" and row(4007, fs).src == "unexplained")
    put("sold", 6, { item = 5, n = 2, unit = 3, npc = "Bob" })
    check("#36 cap: a sold row after them is dropped (it follows an unexplained row)", fs.goldLogDropped == 2 and #fs.goldLog == 4007)
    fs.goldLog[#fs.goldLog + 1] = ("1.0\t6\tsold\t%d\titem=5;n=2;unit=3;npc=Bob"):format(bal)
    put("sold", 6, { item = 5, n = 2, unit = 3, npc = "Bob" }); put("sold", 4, { item = 6, n = 1, unit = 4, npc = "Bob" })
    x = row(nil, fs)
    check("#36 cap: merged sold rows keep only what they share (same merchant, items differ)", x.src == "sold" and x.delta == 16 and x.ref == "npc=Bob;x=3", x.ref)
    local lf = { goldLog = {}, goldLogDropped = 0 }
    for _ = 1, E.GOLD_CAP do lf.goldLog[#lf.goldLog + 1] = "1.0\t1\tlooted\t1\t" end
    E._gbal, E._gref = 4, { sender = "x" }; E.goldRow(lf, "looted", 3)
    check("#36 cap: a row that names a sender never merges", lf.goldLogDropped == 1 and lf.goldLog[E.GOLD_CAP] == "1.0\t1\tlooted\t1\t")
    local s = { goldLog = { ("1.0\t5\tsold\t%d\titem=5;n=2;unit=3;npc=Bob"):format(5) } }
    for _ = 1, E.GOLD_CAP - 1 do s.goldLog[#s.goldLog + 1] = s.goldLog[1] end
    E._gbal, E._gref = 11, { item = 5, n = 2, unit = 3, npc = "Bob" }; E.goldRow(s, "sold", 6)
    x = row(nil, s)
    check("#36 cap: merged sold rows of one item sum n and keep the unit", x.ref == "item=5;n=4;unit=3;npc=Bob;x=2" and x.bal == 11, x.ref)
  end
end
