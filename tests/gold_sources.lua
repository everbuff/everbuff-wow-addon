-- Honest sources (everbuff-wow-addon #43, 0.9.46). Loaded by tests/run_tests.lua after tests/gold_glance.lua and by
-- tests/gold_profile.lua (the WoW Forever stub profile):
--   dofile("tests/gold_sources.lua")({ check = check, M = M, ns = ns })
-- One case per accounting rule of the milestone, in both event orders where the order is not guaranteed: the mail
-- queue with its summed split, the client's coin lines (and their prefixes in the 13 mined locales), repairs by the
-- drop of the repair cost, flights from the TakeTaxiNode hook, merchant sales that need a pending sale, buyback as
-- a reversal, purchase prices, combined purse changes, auction house claims, the talent reset cost, the drift
-- check, the crash tag on away rows (read from the save file as the client would hold it) and the interaction
-- manager's context. No new ledger key: amounts only move
-- between the existing ones, and every identity of the journal and the day rows still holds at the end.
return function(P)
  local check, M, ns = P.check, P.M, P.ns
  local E, G = ns.Emitter, ns.Gold
  local function ses() return ns.Recorder.current() end
  local function row(i, s)
    local log = (s or ses()).goldLog
    i = i or #log
    local mono, d, src, bal, ref = E.rowParse(log[i] or "")
    return { mono = mono, delta = d, src = src, bal = bal, ref = ref, refT = E.refParse(ref) }
  end
  local function money(d) M.money = M.money + d; M.fire("PLAYER_MONEY") end
  local function later(s) M.now = M.now + (s or 10); M.epoch = M.epoch + (s or 10) end
  local function is(name, r, src, delta, ref, bal)
    check("#43 sources: " .. name,
      r.src == src and r.delta == delta and r.bal == (bal or M.money) and (ref == nil or r.ref == ref),
      ("%s %s %s %s [%s]"):format(tostring(r.src), tostring(r.delta), tostring(r.bal), tostring(M.money), tostring(r.ref)))
  end
  local function rows() return #ses().goldLog end
  local function chain(s)
    for i = 2, #s.goldLog do
      local a, b = row(i - 1, s), row(i, s)
      if b.bal - a.bal ~= b.delta then return false, i end
    end
    return true
  end

  -- a played session of its own, with no window open and a purse that can pay for everything below
  M.runTimers(); later()
  for _, e in ipairs({ "MERCHANT_CLOSED", "MAIL_CLOSED", "AUCTION_HOUSE_CLOSED", "TRAINER_CLOSED", "TRADE_CLOSED" }) do M.fire(e) end
  M.runTimers()
  M.units.NPC = nil; M.inbox = {}; M.repairCost = 0; M.interact = {}; M.interactOff = nil
  M.fire("PLAYER_LOGOUT"); later(60)
  ns._test.newLoad(); M.fire("PLAYER_ENTERING_WORLD", true, false); M.runTimers(); later()
  M.fire("LOOT_OPENED"); money(2000000); later()
  local s0 = ses()
  local g = ns.char().gold
  -- (a save file that began with gold in the purse has it in the balance and in no ledger key)
  local born = g.balance - (g.gained - g.spent + (g.away or 0))
  local errs0 = #M.errors
  local first = rows()

  -- ── rule 15: the mail queue ───────────────────────────────────────────────────────────────────────────────────
  local function inbox()
    M.inbox = {
      { sender = "Rando", subject = "gold", money = 1100 },
      { sender = "Stormwind Auction House", subject = "Auction successful: Linen Cloth", money = 2300, invoice = { "seller", "Linen Cloth", "Buyerguy", 100, 2300, 5, 6 } },
      { sender = "Pal", subject = "gold", money = 3700 },
    }
  end
  M.friends = { "Pal" }; M.fire("FRIENDLIST_UPDATE")
  M.fire("MAIL_SHOW")
  do
    -- Open All, three mails, three purse changes: every take is asked for before the first answer
    inbox()
    local n0 = rows()
    for i = 1, 3 do TakeInboxMoney(i) end
    money(1100); is("Open All, separate changes: the first mail's sender", row(), "mail", 1100, "sender=Rando;rel=stranger;cod=0")
    money(2300); is("Open All, separate changes: the auction sale is an auction sale", row(), "auctionSales", 2300, "sender=Stormwind Auction House;rel=system;cod=0")
    money(3700); is("Open All, separate changes: the third mail's sender", row(), "mail", 3700, "sender=Pal;rel=friend;cod=0")
    check("#43 sources: Open All, separate changes: three rows, the queue is empty", rows() == n0 + 3 and #E._mailQ == 0, rows() - n0)
    later()
    -- the same three mails answered in another order: each change finds the mail of its amount
    inbox(); n0 = rows()
    for i = 1, 3 do TakeInboxMoney(i) end
    money(3700); is("Open All, reordered: the amount names the mail", row(), "mail", 3700, "sender=Pal;rel=friend;cod=0")
    money(1100); is("Open All, reordered: second", row(), "mail", 1100, "sender=Rando;rel=stranger;cod=0")
    money(2300); is("Open All, reordered: third", row(), "auctionSales", 2300, "sender=Stormwind Auction House;rel=system;cod=0")
    later()
    -- the three mails answered with one purse change: three rows with the balance after each
    inbox(); n0 = rows()
    local mail0, sales0, gained0, bal0 = g.mail or 0, g.auctionSales or 0, g.gained, M.money
    for i = 1, 3 do TakeInboxMoney(i) end
    money(7100)
    local a, b, c = row(n0 + 1), row(n0 + 2), row(n0 + 3)
    check("#43 sources: Open All, one combined change: one row per mail, oldest first", rows() == n0 + 3 and a.src == "mail" and a.delta == 1100 and b.src == "auctionSales" and b.delta == 2300 and c.src == "mail" and c.delta == 3700,
      ("%d %s %s %s"):format(rows() - n0, tostring(a.src), tostring(b.src), tostring(c.src)))
    check("#43 sources: Open All, one combined change: the balance after each mail", a.bal == bal0 + 1100 and b.bal == bal0 + 3400 and c.bal == M.money, ("%s %s %s"):format(a.bal, b.bal, c.bal))
    check("#43 sources: Open All, one combined change: each row names its own sender", a.refT.sender == "Rando" and b.refT.sender == "Stormwind Auction House" and c.refT.sender == "Pal")
    check("#43 sources: Open All, one combined change: gained once, each key its own", g.gained == gained0 + 7100 and (g.mail or 0) == mail0 + 4800 and (g.auctionSales or 0) == sales0 + 2300)
    later()
    -- the two oldest answered together, the third alone
    inbox(); n0 = rows()
    for i = 1, 3 do TakeInboxMoney(i) end
    money(3400); money(3700)
    check("#43 sources: the two oldest mails as one change, then the third", rows() == n0 + 3 and row(n0 + 1).delta == 1100 and row(n0 + 2).delta == 2300 and row(n0 + 3).refT.sender == "Pal")
    later()
    -- an amount no waiting mail has: a plain mail row that says so; the mail asked for is still found by its amount
    M.inbox = { { sender = "Rando", subject = "gold", money = 500 } }
    TakeInboxMoney(1); money(123)
    is("a gain no waiting mail has is a plain mail row, flagged", row(), "mail", 123, "x=unmatched")
    money(500); is("the mail asked for is still matched by its amount", row(), "mail", 500, "sender=Rando;rel=stranger;cod=0")
    later()
    -- a take the server never answered is forgotten after 3 s
    TakeInboxMoney(1); later(4); money(500)
    is("a take older than 3 s names no sender", row(), "mail", 500, "")
    later()
    -- a take still waiting, the mailbox closed: a gain of another amount is not the mail's (the loot window says
    -- what it is), and the mail's own amount still is
    M.inbox = { { sender = "Rando", subject = "gold", money = 500 } }
    TakeInboxMoney(1); money(123)
    is("an unmatched gain at the mailbox is still a mail row", row(), "mail", 123, "x=unmatched")
    M.fire("MAIL_CLOSED"); M.runTimers(); M.now = M.now + 1
    M.fire("LOOT_OPENED"); money(77)
    is("a take still waiting, the mailbox closed, a corpse looted: looted, not mail", row(), "looted", 77, "")
    money(500)
    is("the mail's own amount is still the mail's after the mailbox closed", row(), "mail", 500, "sender=Rando;rel=stranger;cod=0")
    later()
    TakeInboxMoney(1); M.now = M.now + 1; money(9)
    is("a take still waiting, the mailbox closed, no loot window: unexplained, not mail", row(), "unexplained", 9, "")
    later(); M.fire("MAIL_SHOW")
    check("#43 sources: the mail chain holds", chain(s0))
  end
  M.fire("MAIL_CLOSED"); M.inbox = {}; M.runTimers(); later()

  -- ── rule 13: the client's coin lines ──────────────────────────────────────────────────────────────────────────
  do
    local looted0, n0 = g.looted or 0, rows()
    M.fire("CHAT_MSG_MONEY", "You loot 1 Gold, 20 Silver, 5 Copper"); money(12005)
    is("coin line before the purse change, no loot window: looted", row(), "looted", 12005, "")
    local lr = ns.DB.loot.log[#ns.DB.loot.log]
    check("#43 sources: the loot log row of coin with no loot window of its own", lr.money == 12005 and lr.src == "Coin" and lr.s == ns.DB.active, lr.src)
    later()
    M.fire("CHAT_MSG_MONEY", "Your share of the loot is 3 Silver, 40 Copper."); money(340)
    is("a group share said before the purse change", row(), "looted", 340, "share=1")
    check("#43 sources: its loot log row says group share", ns.DB.loot.log[#ns.DB.loot.log].src == "Group share")
    later()
    -- the other order: the purse first, the line a moment later
    local before = rows()
    local day = function() return ns.char().goldDays[G.dayKey(GetServerTime(), G.baseStored())] end
    local un0 = day().unexplained or 0
    money(340)
    is("a group share, the purse first: unexplained until the line comes", row(), "unexplained", 340, "")
    check("#43 sources: the day row holds it as unexplained meanwhile", (day().unexplained or 0) == un0 + 340)
    M.fire("CHAT_MSG_MONEY", "Your share of the loot is 3 Silver, 40 Copper.")
    is("the line a moment later rewrites that row", row(), "looted", 340, "share=1")
    check("#43 sources: still one row, and the day row moved it from unexplained to looted", rows() == before + 1 and (day().unexplained or 0) == un0)
    check("#43 sources: looted counts the three pickups", (g.looted or 0) == looted0 + 12005 + 340 + 340, (g.looted or 0) - looted0)
    later()
    -- the digit check: a line with other digits claims nothing, before or after
    M.fire("CHAT_MSG_MONEY", "Your share of the loot is 5 Silver."); money(340)
    is("digits that are not the purse change leave it unexplained (line first)", row(), "unexplained", 340, "")
    later()
    money(77); M.fire("CHAT_MSG_MONEY", "You loot 78 Copper")
    is("digits that are not the purse change leave it unexplained (purse first)", row(), "unexplained", 77, "")
    later()
    -- a line older than 3 s claims nothing
    M.fire("CHAT_MSG_MONEY", "You loot 55 Copper"); later(4); money(55)
    is("a coin line older than 3 s claims nothing", row(), "unexplained", 55, "")
    later()
    -- the player's own loot window: looted either way, and a share line after it adds the share
    M.fire("LOOT_OPENED"); money(250)
    is("own loot window: looted", row(), "looted", 250, "")
    M.fire("CHAT_MSG_MONEY", "Your share of the loot is 2 Silver, 50 Copper.")
    is("a share line after the looted row adds share=1", row(), "looted", 250, "share=1")
    later()
    M.fire("LOOT_OPENED"); M.fire("CHAT_MSG_MONEY", "Your share of the loot is 2 Silver, 50 Copper."); money(250)
    is("own loot window, the share line first", row(), "looted", 250, "share=1")
    check("#43 sources: with a loot window the loot log row keeps the mob", ns.DB.loot.log[#ns.DB.loot.log].src ~= "Group share")
    later()
    -- a mismatching line inside the loot window changes nothing: the window says looted, as before
    M.fire("LOOT_OPENED"); M.fire("CHAT_MSG_MONEY", "You loot 9 Gold"); money(31)
    is("a mismatching line in the loot window: looted by the window, no share", row(), "looted", 31, "")
    later()
    -- the guild form: the first amount is the purse's
    M.fire("CHAT_MSG_MONEY", "You loot 2 Silver (10 Copper deposited to guild bank)"); money(200)
    is("the guild form: the amount that reached the purse", row(), "looted", 200, "")
    later()
    M.fire("CHAT_MSG_MONEY", "You loot 2 Silver (10 Copper deposited to guild bank)"); money(210)
    is("the guild form: the deposit is not the purse's", row(), "unexplained", 210, "")
    later()
    -- coin icons instead of words (the digits inside the texture escapes are not amounts)
    M.fire("CHAT_MSG_MONEY", "You loot 3|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t 20|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t"); money(320)
    is("a line with coin icons", row(), "looted", 320, "")
    later()
    -- a text the client hides is skipped, with no error
    local hidden = "You loot 4 Copper"
    M.secrets[hidden] = true
    M.fire("CHAT_MSG_MONEY", hidden); money(4)
    M.secrets[hidden] = nil
    is("a secret line is skipped", row(), "unexplained", 4, "")
    check("#43 sources: no error on the secret line", #M.errors == errs0, M.errors[#M.errors])
    later()
    -- a line that is no coin line
    M.fire("CHAT_MSG_MONEY", "Rando loots 5 Copper."); money(5)
    is("another player's coin line is not ours", row(), "unexplained", 5, "")
    later()
    -- several lines at once (a pull of several mobs in a group): every line finds its purse change, in either order
    do
      local A, B, C = "Your share of the loot is 3 Silver, 40 Copper.", "Your share of the loot is 2 Silver, 10 Copper.", "Your share of the loot is 7 Copper."
      local m0 = rows()
      M.fire("CHAT_MSG_MONEY", A); M.fire("CHAT_MSG_MONEY", B)
      money(340); is("two share lines, then the purse: the first", row(), "looted", 340, "share=1")
      money(210); is("two share lines, then the purse: the second", row(), "looted", 210, "share=1")
      later()
      money(340); money(210)
      M.fire("CHAT_MSG_MONEY", B); M.fire("CHAT_MSG_MONEY", A)
      local a, b = row(m0 + 3), row(m0 + 4)
      check("#43 sources: two purse changes, then their two lines (in the other order): both are shares", rows() == m0 + 4 and a.src == "looted" and a.delta == 340 and a.ref == "share=1" and b.src == "looted" and b.delta == 210 and b.ref == "share=1",
        ("%d %s %s [%s] [%s]"):format(rows() - m0, tostring(a.src), tostring(b.src), tostring(a.ref), tostring(b.ref)))
      later()
      M.fire("CHAT_MSG_MONEY", A); M.fire("CHAT_MSG_MONEY", B); M.fire("CHAT_MSG_MONEY", C)
      money(7); money(340); money(210)
      check("#43 sources: three lines, then three purse changes in another order", rows() == m0 + 7 and row(m0 + 5).ref == "share=1" and row(m0 + 5).delta == 7 and row(m0 + 6).delta == 340 and row(m0 + 6).src == "looted"
        and row(m0 + 7).src == "looted" and row(m0 + 7).ref == "share=1", rows() - m0)
      later()
      money(210); M.fire("CHAT_MSG_MONEY", A); money(340); money(7); M.fire("CHAT_MSG_MONEY", C); M.fire("CHAT_MSG_MONEY", B)
      local un = 0
      for i = m0 + 8, rows() do if row(i).src ~= "looted" or row(i).ref ~= "share=1" then un = un + 1 end end
      check("#43 sources: lines and purse changes mixed: three rows, all shares", rows() == m0 + 10 and un == 0, ("%d %d"):format(rows() - m0, un))
      check("#43 sources: the waiting lists are empty again", #E.qList("_coin") == 0 and #E.qList("_openGain") == 0)
      later()
    end
    -- the line names the coin of each figure: 1 Gold, 5 Silver is not a purse change of 1g 5c
    M.fire("CHAT_MSG_MONEY", "Your share of the loot is 1 Gold, 5 Silver."); money(10005)
    is("a line that names other coins than the purse change claims nothing (line first)", row(), "unexplained", 10005, "")
    later()
    money(105); M.fire("CHAT_MSG_MONEY", "Your share of the loot is 1 Gold, 5 Silver.")
    is("a line that names other coins than the purse change claims nothing (purse first)", row(), "unexplained", 105, "")
    later()
    M.fire("CHAT_MSG_MONEY", "Your share of the loot is 1 Gold, 5 Silver."); money(10500)
    is("the same line and the amount it names", row(), "looted", 10500, "share=1")
    later()
    do
      -- (read without a purse change: the purse of this suite stays small, the pane tests after it draw its numbers)
      local big = E.coinLine("You loot 1,234 Gold, 5 Silver")
      check("#43 sources: a large gold figure with a thousands separator", big ~= nil and E.coinMatches(big.groups, 12340500, big.den) and not E.coinMatches(big.groups, 10002345, big.den) and not E.coinMatches(big.groups, 12340005, big.den),
        big and table.concat(big.groups, " "))
    end
    check("#43 sources: digits: with the coins named, the amount is compared exactly", E.coinMatches({ "1", "5" }, 10500, { "g", "s" }) and not E.coinMatches({ "1", "5" }, 10005, { "g", "s" })
      and not E.coinMatches({ "1", "5" }, 105, { "g", "s" }) and E.coinMatches({ "1", "5" }, 105, { "s", "c" }) and E.coinMatches({ "1", "234", "5" }, 12340500, { [2] = "g", [3] = "s" }))
    check("#43 sources: digits: a figure that names no coin falls back to the order of the figures", E.coinMatches({ "1", "5" }, 10005, { "g" }) and E.coinMatches({ "1", "5" }, 10500, {}))
    -- the client's grammar escapes left in the text are not amounts
    do
      local raw = E.coinLine("You loot 3 |4Silver:Silvers; 12 |4Copper:Coppers;")
      check("#43 sources: an unresolved |4 escape is not a figure", raw ~= nil and table.concat(raw.groups, " ") == "3 12" and E.coinMatches(raw.groups, 312, raw.den), raw and table.concat(raw.groups, " "))
      raw = E.coinLine("You loot 3 Silver|1a;b; 12 Copper|1a;b;")
      check("#43 sources: an unresolved |1 escape is not a figure", raw ~= nil and table.concat(raw.groups, " ") == "3 12", raw and table.concat(raw.groups, " "))
    end
    -- the digit matcher on its own
    check("#43 sources: digits: gold, silver, copper in order", E.coinMatches({ "1", "20", "5" }, 12005) and not E.coinMatches({ "1", "20", "5" }, 12050))
    check("#43 sources: digits: a denomination of 0 left out or written", E.coinMatches({ "1", "5" }, 10005) and E.coinMatches({ "1", "0", "5" }, 10005) and not E.coinMatches({ "1", "5" }, 10600) and not E.coinMatches({ "1", "0", "5" }, 10500))
    check("#43 sources: digits: silver and copper only", E.coinMatches({ "3", "40" }, 340) and E.coinMatches({ "40" }, 40) and not E.coinMatches({ "40" }, 4100))
    check("#43 sources: digits: a large gold figure in groups of three", E.coinMatches({ "1", "234", "5" }, 12340500) and E.coinMatches({ "1234", "5" }, 12340500) and not E.coinMatches({ "1", "234", "5" }, 10002345))
    check("#43 sources: digits: nothing, a secret or a negative amount never match", not E.coinMatches({}, 5) and not E.coinMatches({ "5" }, -5) and not E.coinMatches(nil, 5))
    check("#43 sources: the coin chain holds", chain(s0) and rows() > n0)
  end

  -- the prefixes in the 13 mined locales (the money text is built as the client builds it, with the grammar
  -- escapes of koKR and ruRU resolved)
  do
    local locales = dofile("tests/coin_locales.lua")
    local keep = { LOOT_MONEY_SPLIT, YOU_LOOT_MONEY, YOU_LOOT_MONEY_GUILD }
    local function grammar(s) return (s:gsub("|4([^:;]*)[^;]*;", "%1"):gsub("|1([^;]*);[^;]*;", "%1")) end
    local n = 0
    for name, L in pairs(locales) do
      n = n + 1
      LOOT_MONEY_SPLIT, YOU_LOOT_MONEY, YOU_LOOT_MONEY_GUILD = L.LOOT_MONEY_SPLIT, L.YOU_LOOT_MONEY, L.YOU_LOOT_MONEY_GUILD
      local function coins(c)
        local out, gold, silver, copper = {}, math.floor(c / 10000), math.floor(c % 10000 / 100), c % 100
        if gold > 0 then out[#out + 1] = L.GOLD_AMOUNT:format(gold) end
        if silver > 0 then out[#out + 1] = L.SILVER_AMOUNT:format(silver) end
        if copper > 0 then out[#out + 1] = L.COPPER_AMOUNT:format(copper) end
        return table.concat(out, ", ")
      end
      -- the text as the event may carry it, with the grammar escapes unresolved: the same figures
      local keepAmt = { GOLD_AMOUNT, SILVER_AMOUNT, COPPER_AMOUNT }
      GOLD_AMOUNT, SILVER_AMOUNT, COPPER_AMOUNT = L.GOLD_AMOUNT, L.SILVER_AMOUNT, L.COPPER_AMOUNT
      for _, form in ipairs({ "raw", "resolved" }) do
        local function text(s) return form == "raw" and s or grammar(s) end
        local rs = E.coinLine(text(L.LOOT_MONEY_SPLIT:format(coins(30412))))
        check(("#43 sources: locale %s, %s text: a share line gives the three figures and matches only its amount"):format(name, form),
          rs ~= nil and rs.share == true and table.concat(rs.groups, " ") == "3 4 12" and E.coinMatches(rs.groups, 30412, rs.den) and not E.coinMatches(rs.groups, 30421, rs.den),
          rs and table.concat(rs.groups, " "))
        local ro = E.coinLine(text(L.YOU_LOOT_MONEY:format(coins(30012))))
        check(("#43 sources: locale %s, %s text: 3 gold 12 copper is never 3 gold 12 silver"):format(name, form),
          ro ~= nil and ro.share == nil and ro.den[1] == "g" and ro.den[2] == "c" and E.coinMatches(ro.groups, 30012, ro.den) and not E.coinMatches(ro.groups, 31200, ro.den),
          ro and (table.concat(ro.groups, " ") .. " " .. tostring(ro.den[1]) .. tostring(ro.den[2])))
      end
      GOLD_AMOUNT, SILVER_AMOUNT, COPPER_AMOUNT = keepAmt[1], keepAmt[2], keepAmt[3]
      local share = E.coinLine(grammar(L.LOOT_MONEY_SPLIT:format(coins(30412))))
      check(("#43 sources: locale %s: a group share line is a share with the purse's digits"):format(name), share ~= nil and share.share == true and E.coinMatches(share.groups, 30412) and not E.coinMatches(share.groups, 30421),
        share and table.concat(share.groups, " "))
      local solo = E.coinLine(grammar(L.YOU_LOOT_MONEY:format(coins(512))))
      check(("#43 sources: locale %s: a loot line is not a share, with the purse's digits"):format(name), solo ~= nil and solo.share == nil and E.coinMatches(solo.groups, 512), solo and table.concat(solo.groups, " "))
      local guild = E.coinLine(grammar(L.YOU_LOOT_MONEY_GUILD:format(coins(70003), coins(900))))
      if L.YOU_LOOT_MONEY_GUILD:sub(1, 2) == "%s" then
        check(("#43 sources: locale %s: the guild form has no prefix and is skipped"):format(name), guild == nil)
      else
        check(("#43 sources: locale %s: the guild form gives the purse's amount, never the deposit"):format(name), guild ~= nil and guild.share == nil and E.coinMatches(guild.groups, 70003) and not E.coinMatches(guild.groups, 900),
          guild and table.concat(guild.groups, " "))
      end
    end
    check("#43 sources: the locale table has the 13 mined locales", n == 13, n)
    -- a share prefix that is also the loot prefix cannot tell the two apart: the share is skipped
    LOOT_MONEY_SPLIT, YOU_LOOT_MONEY, YOU_LOOT_MONEY_GUILD = "You loot %s (share)", "You loot %s", nil
    local amb = E.coinLine("You loot 5 Copper (share)")
    check("#43 sources: a share prefix equal to the loot prefix is skipped", amb ~= nil and amb.share == nil)
    LOOT_MONEY_SPLIT, YOU_LOOT_MONEY, YOU_LOOT_MONEY_GUILD = "%s is your share", nil, nil
    check("#43 sources: a format with no prefix, or no format at all, matches nothing", E.coinLine("5 Copper is your share") == nil)
    LOOT_MONEY_SPLIT, YOU_LOOT_MONEY, YOU_LOOT_MONEY_GUILD = keep[1], keep[2], keep[3]
  end

  -- ── rule 24: repairs by the drop of the repair cost ───────────────────────────────────────────────────────────
  do
    local rep0 = g.repairs or 0
    M.units.NPC = { name = "Smith Sam" }
    -- one item repaired: the cost drops by the spend and stays above 0
    M.repairCost = 500; M.fire("MERCHANT_SHOW")
    M.repairCost = 300; money(-200)
    is("a single item repaired", row(), "repairs", -200, "npc=Smith Sam;kind=repairOne")
    -- the rest with Repair All: the cost drops to 0
    RepairAllItems(); money(-300)
    is("repair all", row(), "repairs", -300, "npc=Smith Sam")
    M.fire("MERCHANT_CLOSED"); M.runTimers(); later()
    -- the client shows the cost drop before the purse change (a durability event in between)
    M.repairCost = 450; M.fire("MERCHANT_SHOW")
    M.repairCost = 0; M.fire("UPDATE_INVENTORY_DURABILITY"); money(-450)
    is("the cost drop seen before the purse change", row(), "repairs", -450, "npc=Smith Sam")
    M.fire("MERCHANT_CLOSED"); M.runTimers(); later()
    -- the purse first, the cost not moved yet: one more look on the next durability event
    M.repairCost = 600; M.fire("MERCHANT_SHOW")
    local n0, bal0 = rows(), M.money
    money(-600)
    check("#43 sources: a spend whose repair cost has not moved yet waits", rows() == n0 and g.spent ~= nil)
    M.repairCost = 0; M.fire("UPDATE_INVENTORY_DURABILITY")
    is("the cost moved on the next durability event: a repair", row(), "repairs", -600, "npc=Smith Sam", bal0 - 600)
    check("#43 sources: one row for it", rows() == n0 + 1)
    M.runTimers()
    check("#43 sources: the 0.3 s look afterwards books nothing twice", rows() == n0 + 1)
    M.fire("MERCHANT_CLOSED"); M.runTimers(); later()
    -- the same wait, and the cost never moves: a purchase after 0.3 s
    M.repairCost = 600; M.fire("MERCHANT_SHOW")
    n0 = rows(); money(-600)
    check("#43 sources: waiting again", rows() == n0)
    M.runTimers()
    is("the cost did not move: a purchase", row(), "vendor", -600, "npc=Smith Sam")
    -- and a spend that follows at once is written after the one that waited
    n0 = rows()
    money(-50); money(-7)
    check("#43 sources: a spend waiting is booked before the next purse change", rows() == n0 + 1 and row().delta == -50 and row().bal == M.money + 7, row().delta)
    M.runTimers()
    check("#43 sources: and the one after it follows, the chain intact", rows() == n0 + 2 and row().delta == -7 and row().bal == M.money and chain(s0))
    M.fire("MERCHANT_CLOSED"); M.runTimers(); later()
    -- a spend waiting when the merchant closes is booked then
    M.repairCost = 80; M.fire("MERCHANT_SHOW")
    n0 = rows(); money(-80); M.repairCost = 0
    M.fire("MERCHANT_CLOSED")
    is("a waiting spend is booked when the merchant closes", row(), "repairs", -80, "npc=Smith Sam")
    M.runTimers(); later()
    check("#43 sources: and only once", rows() == n0 + 1)
    -- a guild repair, then a purchase: the guild bank paid, the purse did not
    M.repairCost = 500; M.fire("MERCHANT_SHOW")
    RepairAllItems(true); M.fire("UPDATE_INVENTORY_DURABILITY")
    money(-500)
    is("a guild repair then a purchase of the same amount: a purchase", row(), "vendor", -500, "npc=Smith Sam")
    M.fire("MERCHANT_CLOSED"); M.runTimers(); later()
    M.repairCost = 500; M.fire("MERCHANT_SHOW")
    RepairAllItems(true); money(-500)
    is("a guild repair then a purchase, no durability event between", row(), "vendor", -500, "npc=Smith Sam")
    M.fire("MERCHANT_CLOSED"); M.runTimers(); later()
    -- a purchase of exactly the repair cost, asked for: the pending purchase wins
    M.repairCost = 500; M.fire("MERCHANT_SHOW")
    M.merchant[3] = { id = 4500, name = "Traveler's Backpack", price = 500, qty = 1 }
    BuyMerchantItem(3, 1); money(-500)
    is("a purchase equal to the repair cost with a pending buy", row(), "vendor", -500, "item=4500;n=1;npc=Smith Sam")
    RepairAllItems(); money(-500)
    is("and the repair after it is a repair", row(), "repairs", -500, "npc=Smith Sam")
    M.fire("MERCHANT_CLOSED"); M.runTimers(); later()
    -- a merchant that cannot repair: no waiting
    M.canRepair = false; M.repairCost = 0; M.fire("MERCHANT_SHOW")
    n0 = rows(); money(-10)
    is("a merchant that cannot repair: a purchase at once", row(), "vendor", -10, "npc=Smith Sam")
    M.canRepair = nil
    M.fire("MERCHANT_CLOSED"); M.runTimers(); later()
    -- a client with no repair cost to read: the 2 s rule of before
    local getter = GetRepairAllCost
    GetRepairAllCost = nil
    M.fire("MERCHANT_SHOW")
    RepairAllItems(); money(-75)
    is("no GetRepairAllCost: a spend within 2 s of Repair All is a repair", row(), "repairs", -75, "npc=Smith Sam")
    RepairAllItems(true); money(-75)
    is("no GetRepairAllCost: a guild repair arms nothing", row(), "vendor", -75, "npc=Smith Sam")
    GetRepairAllCost = getter
    M.fire("MERCHANT_CLOSED"); M.runTimers(); later()
    -- a spend waiting when the merchant window opens again is booked then, never dropped
    M.repairCost = 1000; M.fire("MERCHANT_SHOW")
    n0 = rows()
    local spent0, vend0 = g.spent, g.vendor or 0
    money(-100)
    check("#43 sources: a spend waits for its repair cost", rows() == n0 and g.spent == spent0 + 100)
    M.fire("MERCHANT_SHOW")
    is("a waiting spend is booked when the merchant window opens again", row(), "vendor", -100, "npc=Smith Sam")
    M.runTimers()
    check("#43 sources: one row for it, and the spend keys follow spent", rows() == n0 + 1 and (g.vendor or 0) == vend0 + 100)
    M.fire("MERCHANT_CLOSED"); M.runTimers(); later()
    -- the timer of an earlier wait does not end a later one: the second spend still sees its durability event
    M.repairCost = 900; M.fire("MERCHANT_SHOW"); M.runTimers()
    money(-50)                                      -- waits (its timer is among the first `mine`)
    local mine = #M.timers
    money(-60)                                      -- books the first as a purchase, waits itself (a later timer)
    local timers = M.timers; M.timers = {}
    n0 = rows()
    for i = 1, mine do timers[i]() end
    check("#43 sources: the timer of the first wait does not book the second", rows() == n0 and mine >= 1 and #timers > mine, ("%d %d"):format(mine, #timers))
    M.repairCost = 840; M.fire("UPDATE_INVENTORY_DURABILITY")
    is("the second spend is the repair its durability event shows", row(), "repairs", -60, "npc=Smith Sam;kind=repairOne")
    for i = mine + 1, #timers do timers[i]() end
    check("#43 sources: and its own timer books nothing twice", rows() == n0 + 1)
    M.fire("MERCHANT_CLOSED"); M.runTimers(); later()
    check("#43 sources: repairs counted", (g.repairs or 0) == rep0 + 200 + 300 + 450 + 600 + 80 + 500 + 75 + 60, (g.repairs or 0) - rep0)
    M.units.NPC = nil
  end

  -- ── rule 25: flights from the TakeTaxiNode hook ───────────────────────────────────────────────────────────────
  do
    M.units.NPC = { name = "Flight Fay" }; M.fire("TAXIMAP_OPENED"); M.units.NPC = nil
    later(20)
    TakeTaxiNode(4); money(-230)
    is("a flight clicked 20 s after the map opened", row(), "flights", -230, "npc=Flight Fay")
    money(-11)
    is("the fare is taken once: the next spend is not a flight", row(), "other", -11, "")
    M.runTimers(); later(20)
    M.fire("TAXIMAP_OPENED"); later(20); money(-12)
    is("20 s after the map opened with no flight asked for: not a flight", row(), "other", -12, "")
    M.fire("TAXIMAP_OPENED"); money(-13)
    is("the 5 s window of the map still works", row(), "flights", -13)
    later()
    local ev0 = #ns.DB.story.events
    -- a flight that never starts: the client says why, and the next spend is no fare
    TakeTaxiNode(4); M.fire("UI_ERROR_MESSAGE", 1, ERR_TAXINOTENOUGHMONEY); M.now = M.now + 2; money(-30)
    is("a flight the client refused arms nothing", row(), "other", -30, "")
    M.runTimers(); later(20)
    -- another error message changes nothing
    TakeTaxiNode(4); M.fire("UI_ERROR_MESSAGE", 1, "Inventory is full."); money(-31)
    is("an error that is not about the flight leaves it armed", row(), "flights", -31)
    later(20)
    -- a flight that costs nothing: once on the taxi the wait ends, a spend 12 s later is no fare
    TakeTaxiNode(4); M.onTaxi = true; M.fire("PLAYER_CONTROL_LOST"); later(12); money(-32)
    is("a free flight, a spend 12 s after boarding: not a flight", row(), "other", -32, "")
    M.onTaxi = false; M.fire("PLAYER_CONTROL_GAINED"); later(20)
    -- the fare reaching the purse a moment after the taxi flag is still the fare
    TakeTaxiNode(4); M.onTaxi = true; M.fire("PLAYER_CONTROL_LOST"); M.now = M.now + 1; money(-33)
    is("the fare a moment after boarding", row(), "flights", -33)
    M.onTaxi = false; M.fire("PLAYER_CONTROL_GAINED"); later(20)
    -- (the two short trips of this block are not part of the story the pane tests draw later)
    do
      local ev, trips = ns.DB.story.events, 0
      for i = #ev, 1, -1 do
        if ev[i].kind == "FLIGHTTRIP" and trips < 2 and #ev - i < 10 then table.remove(ev, i); trips = trips + 1 end
      end
      check("#43 sources: the two flights of the block were recorded as trips", trips == 2 and #ev <= ev0 + 2, trips)
    end
  end

  -- ── rules 26, 27, 28 and 14: the merchant ─────────────────────────────────────────────────────────────────────
  do
    M.units.NPC = { name = "Merchant Bob" }; M.repairCost = 0; M.fire("MERCHANT_SHOW")
    local sold0, gained0, spent0, vendor0 = g.sold or 0, g.gained, g.spent, g.vendor or 0
    local function sell(slot, id, n, unit)
      M.bags[0][slot] = { itemID = id, quality = 1, stackCount = n }; M.sellPrice[id] = unit
      C_Container.UseContainerItem(0, slot); M.bags[0][slot] = nil
    end
    -- rule 26: no sale asked for
    money(9)
    is("a gain at a merchant with no pending sale stays unexplained", row(), "unexplained", 9, "")
    later()
    -- rule 27: sell, buy back, sell again
    sell(3, 2589, 5, 13); money(65)
    is("a sale", row(), "sold", 65, "item=2589;n=5;unit=13;npc=Merchant Bob")
    M.buyback[1] = { id = 2589, name = "Linen Cloth", price = 65, qty = 5 }
    BuybackItem(1); money(-65)
    is("a buyback is the sale taken back: a sold row with a negative amount", row(), "sold", -65, "item=2589;n=5;npc=Merchant Bob;kind=buyback")
    check("#43 sources: after the buyback the sale is gone from sold and gained, and spent did not move", (g.sold or 0) == sold0 and g.gained == gained0 + 9 and g.spent == spent0,
      ("%s %s %s"):format((g.sold or 0) - sold0, g.gained - gained0, g.spent - spent0))
    sell(3, 2589, 5, 13); money(65)
    check("#43 sources: sell, buy back, sell again nets to one sale in farm income", (g.sold or 0) == sold0 + 65 and g.gained == gained0 + 9 + 65 and g.spent == spent0, (g.sold or 0) - sold0)
    later()
    -- a buyback whose price the client does not give is a purchase, as before
    M.buyback[2] = { id = 2589, name = "Linen Cloth", price = nil, qty = 5 }
    BuybackItem(2); money(-65)
    is("a buyback with no price known is a purchase", row(), "vendor", -65, "item=2589;n=5;npc=Merchant Bob")
    later()
    -- rule 28: the price of a purchase, also for a part of a stack and for several stacks
    M.merchant[1] = { id = 159, name = "Refreshing Spring Water", price = 25, qty = 5 }
    M.merchant[2] = { id = 4540, name = "Tough Hunk of Bread", price = 100, qty = 5 }
    BuyMerchantItem(2, 10); BuyMerchantItem(1, 5)
    money(-25); is("two purchases asked for: the price names the item (the second asked for)", row(), "vendor", -25, "item=159;n=5;npc=Merchant Bob")
    money(-200); is("ten of an item sold by five: twice the price", row(), "vendor", -200, "item=4540;n=10;npc=Merchant Bob")
    later()
    -- rule 14: two purchases answered with one purse change
    local n0, bal0 = rows(), M.money
    BuyMerchantItem(2, 10); BuyMerchantItem(1, 5); money(-225)
    local a, b = row(n0 + 1), row(n0 + 2)
    check("#43 sources: two purchases as one change: two rows with the balance after each", rows() == n0 + 2 and a.src == "vendor" and a.delta == -200 and a.bal == bal0 - 200 and a.refT.item == "4540"
      and b.delta == -25 and b.bal == M.money and b.refT.item == "159", ("%d %s %s"):format(rows() - n0, tostring(a.delta), tostring(b.delta)))
    later()
    -- three sales answered with one purse change
    n0, bal0 = rows(), M.money
    sell(3, 2589, 5, 13); sell(4, 4306, 2, 400); sell(5, 2770, 3, 10)
    money(895)
    a, b = row(n0 + 1), row(n0 + 3)
    check("#43 sources: three sales as one change: three rows, items named, the chain intact", rows() == n0 + 3 and a.src == "sold" and a.delta == 65 and a.bal == bal0 + 65 and row(n0 + 2).delta == 800
      and b.delta == 30 and b.bal == M.money and b.ref == "item=2770;n=3;unit=10;npc=Merchant Bob", rows() - n0)
    later()
    -- a subset: two of three answered together, the third alone
    n0 = rows()
    sell(3, 2589, 5, 13); sell(4, 4306, 2, 400); sell(5, 2770, 3, 10)
    money(95); money(800)
    check("#43 sources: two of three sales as one change, then the third", rows() == n0 + 3 and row(n0 + 1).refT.item == "2589" and row(n0 + 2).refT.item == "2770" and row(n0 + 3).refT.item == "4306" and row(n0 + 3).delta == 800)
    later()
    -- no exact decomposition with several sales waiting: one flagged row, no item guessed
    n0 = rows()
    sell(3, 2589, 5, 13); sell(4, 4306, 2, 400)
    money(900)
    is("several sales waiting and no exact split: one flagged row with no item", row(), "sold", 900, "npc=Merchant Bob;x=unmatched")
    check("#43 sources: one row for it", rows() == n0 + 1)
    later()
    -- one sale waiting and another amount: the item is named and the difference shows, as before
    sell(4, 4306, 2, 400); money(1200)
    is("one sale waiting, paid more than the vendor price: the item stays named", row(), "sold", 1200, "item=4306;n=2;unit=400;npc=Merchant Bob")
    later()
    -- a buyback of an item no sale of this session covers (sold before a /reload, or never seen sold): a purchase.
    -- sold and gained never go below what the session's own sales put there
    do
      local s1, g1, sp1 = g.sold or 0, g.gained, g.spent
      M.buyback[3] = { id = 7777, name = "Old Sword", price = 900, qty = 1 }
      BuybackItem(3); money(-900)
      is("a buyback with no sale of the item in this session is a purchase", row(), "vendor", -900, "item=7777;n=1;npc=Merchant Bob")
      check("#43 sources: it leaves sold and gained alone and counts in spent", (g.sold or 0) == s1 and g.gained == g1 and g.spent == sp1 + 900)
      -- the same item sold once for 65 and bought back twice: the second buyback is a purchase
      sell(3, 6001, 1, 65); money(65)
      M.buyback[4] = { id = 6001, name = "Bent Staff", price = 65, qty = 1 }
      BuybackItem(4); money(-65)
      is("the sale of this session taken back", row(), "sold", -65, "item=6001;n=1;npc=Merchant Bob;kind=buyback")
      BuybackItem(4); money(-65)
      is("a second buyback of it has no sale left to take back: a purchase", row(), "vendor", -65, "item=6001;n=1;npc=Merchant Bob")
      check("#43 sources: session sold and gained are not below their start", (g.sold or 0) == s1 and g.gained == g1 and s0.gold.sold >= 0 and s0.gold.gained >= 0)
    end
    later()
    -- three sales asked for at once, answered 3 s apart: each answer restarts the wait of the rest
    n0 = rows()
    sell(3, 2589, 5, 13); sell(4, 4306, 2, 400); sell(5, 2770, 3, 10)
    money(65); M.now = M.now + 3; money(800); M.now = M.now + 3; money(30)
    check("#43 sources: three sales answered 3 s apart are three sales", rows() == n0 + 3 and row(n0 + 1).src == "sold" and row(n0 + 2).src == "sold" and row(n0 + 3).src == "sold" and row(n0 + 3).refT.item == "2770",
      ("%s %s %s"):format(row(n0 + 1).src, row(n0 + 2).src, row(n0 + 3).src))
    later()
    check("#43 sources: merchant ledger: sold, vendor", (g.sold or 0) == sold0 + 65 + 895 + 895 + 900 + 1200 + 895 and (g.vendor or 0) == vendor0 + 65 + 225 + 225 + 900 + 65, ("%s %s"):format((g.sold or 0) - sold0, (g.vendor or 0) - vendor0))
    M.fire("MERCHANT_CLOSED"); M.runTimers(); M.units.NPC = nil; later()
    check("#43 sources: the merchant chain holds", chain(s0))
  end

  -- ── rule 29: auction house claims ─────────────────────────────────────────────────────────────────────────────
  do
    M.fire("AUCTION_HOUSE_SHOW")
    M.locations.h1 = { name = "Cruel Barb", id = 5191, icon = 135651, count = 1 }
    M.ahDeposit = 60
    C_AuctionHouse.PostItem("h1", 2, 1, 5000, 9000); money(-60)
    is("a deposit, from the post's own arguments", row(), "auctions", -60, "kind=deposit")
    C_AuctionHouse.PostCommodity("h1", 2, 20, 15); money(-60)
    is("a commodity's deposit", row(), "auctions", -60, "kind=deposit")
    M.ahDeposit = nil
    C_AuctionHouse.PostItem("h1", 2, 1, 5000, 9000); money(-61)
    is("a deposit the client does not answer: a plain auctions row", row(), "auctions", -61, "")
    C_AuctionHouse.PlaceBid(77, 5000); money(-5000)
    is("a bid, from the bid's own argument", row(), "auctions", -5000, "kind=bid")
    C_AuctionHouse.StartCommoditiesPurchase(2589, 5); M.fire("COMMODITY_PRICE_UPDATED", 100, 500)
    C_AuctionHouse.ConfirmCommoditiesPurchase(2589, 5); money(-500)
    is("a commodity bought at the total the client quoted", row(), "auctions", -500, "kind=buyout")
    M.ahCancelCost = 25
    C_AuctionHouse.CancelAuction(77); money(-25)
    is("the fee of a cancelled auction", row(), "auctions", -25, "kind=cancel")
    M.ahCancelCost = nil
    C_AuctionHouse.PlaceBid(78, 700); money(-701)
    is("a spend that equals no claim stays plain", row(), "auctions", -701, "")
    later(31); money(-700)
    is("a claim older than 30 s is gone", row(), "auctions", -700, "")
    -- the client says the action is over: the claim has 2 s left for its purse change
    M.ahDeposit = 60
    C_AuctionHouse.PostItem("h1", 2, 1, 5000, 9000); M.fire("AUCTION_HOUSE_AUCTION_CREATED", 1); M.now = M.now + 1; money(-60)
    is("the purse change just after the completion event keeps its kind", row(), "auctions", -60, "kind=deposit")
    C_AuctionHouse.PostItem("h1", 2, 1, 5000, 9000); M.fire("AUCTION_HOUSE_AUCTION_CREATED", 1); M.now = M.now + 3; money(-60)
    is("a claim whose action ended 3 s ago is gone", row(), "auctions", -60, "")
    C_AuctionHouse.PostItem("h1", 2, 1, 5000, 9000); C_AuctionHouse.PlaceBid(79, 800)
    M.fire("AUCTION_HOUSE_PURCHASE_COMPLETED", 79); M.now = M.now + 3; money(-60)
    is("a completion event ends only the claims of its kind", row(), "auctions", -60, "kind=deposit")
    money(-800)
    is("the bid it ended is a plain row", row(), "auctions", -800, "")
    C_AuctionHouse.PlaceBid(80, 800); M.fire("AUCTION_HOUSE_SHOW_ERROR", 3); M.now = M.now + 3; money(-800)
    is("an auction house error ends every claim", row(), "auctions", -800, "")
    M.ahDeposit = nil
    M.fire("AUCTION_HOUSE_CLOSED"); M.runTimers(); later()
  end

  -- ── rule 30: the talent reset ─────────────────────────────────────────────────────────────────────────────────
  do
    local t0 = g.training or 0
    M.fire("CONFIRM_TALENT_WIPE", 10000, 0); later(5); money(-10000)
    is("a talent reset: the cost asked before it is paid", row(), "training", -10000, "kind=respec")
    money(-10000)
    is("the cost is claimed once", row(), "other", -10000, "")
    M.fire("CONFIRM_TALENT_WIPE", 10000, 0); money(-9999)
    is("another amount is not the reset", row(), "other", -9999, "")
    later(61); money(-10000)
    is("a reset asked for over a minute ago is not claimed", row(), "other", -10000, "")
    -- asked, the question left open or declined: 50 s later a spend of that amount elsewhere is not the reset
    later()
    M.fire("CONFIRM_TALENT_WIPE", 10000, 0); later(50); money(-10000)
    is("a reset asked for 50 s ago, no trainer open: not claimed", row(), "other", -10000, "")
    later(20)
    -- at the trainer the question may stay open for a minute
    M.units.NPC = { name = "Trainer Tom" }; M.fire("TRAINER_SHOW")
    M.fire("CONFIRM_TALENT_WIPE", 10000, 0); later(50); money(-10000)
    is("a reset confirmed 50 s after the question at the trainer", row(), "training", -10000, "npc=Trainer Tom;kind=respec")
    M.fire("TRAINER_CLOSED"); M.runTimers(); M.units.NPC = nil
    check("#43 sources: training counted for the two resets", (g.training or 0) == t0 + 20000)
    later()
  end

  -- ── rule 11: drift ────────────────────────────────────────────────────────────────────────────────────────────
  do
    local n0 = rows()
    M.fire("MAIL_SHOW"); M.money = M.money + 44; M.fire("MAIL_CLOSED")
    check("#43 sources: drift is looked for one frame after the window closes", rows() == n0)
    M.runTimers()
    is("a gain with no purse event, found when the mailbox closes", row(), "unexplained", 44, "drift=1")
    M.fire("QUEST_TURNED_IN", 9001, 0, 44)
    is("a quest does not claim a drifted gain", row(), "unexplained", 44, "drift=1")
    later()
    M.units.NPC = { name = "Merchant Bob" }; M.fire("MERCHANT_SHOW"); M.money = M.money - 30; M.fire("MERCHANT_CLOSED"); M.runTimers()
    is("a loss with no purse event, found when the merchant closes", row(), "other", -30, "drift=1")
    M.units.NPC = nil; later()
    M.money = M.money + 7; M.fire("PLAYER_ENTERING_WORLD", false, false); M.runTimers()
    is("drift found on a loading screen is booked at once", row(), "unexplained", 7, "drift=1")
    later()
    -- the purse event of the same frame keeps its source
    n0 = rows()
    M.fire("MAIL_SHOW"); M.inbox = { { sender = "Rando", subject = "gold", money = 60 } }
    TakeInboxMoney(1); M.money = M.money + 60; M.fire("MAIL_CLOSED"); M.fire("PLAYER_MONEY"); M.runTimers()
    is("a purse event in the frame of the close keeps its source", row(), "mail", 60, "sender=Rando;rel=stranger;cod=0")
    check("#43 sources: and no drift row beside it", rows() == n0 + 1)
    M.inbox = {}; later()
    n0 = rows()
    for _, e in ipairs({ "MERCHANT_CLOSED", "MAIL_CLOSED", "AUCTION_HOUSE_CLOSED", "TRAINER_CLOSED" }) do M.fire(e) end
    M.runTimers(); M.fire("PLAYER_ENTERING_WORLD", false, false); M.runTimers()
    check("#43 sources: no drift, no row", rows() == n0)
  end

  -- ── the interaction manager as context ────────────────────────────────────────────────────────────────────────
  do
    M.interact.Merchant = true
    money(-33)
    is("no MERCHANT_SHOW seen, the client says a merchant is open: a purchase", row(), "vendor", -33)
    M.interact.Merchant = nil; M.interact.Auctioneer = true
    money(-34)
    is("the client says an auctioneer is open", row(), "auctions", -34, "")
    M.interact.Auctioneer = nil; M.interact.Trainer = true
    money(-35)
    is("the client says a trainer is open", row(), "training", -35)
    M.interact.Trainer = nil; M.interact.MailInfo = true
    money(-36)
    is("the client says the mailbox is open", row(), "mailSpent", -36, "")
    M.interact.MailInfo = nil
    money(-37)
    is("nothing open: unexplained spending", row(), "other", -37, "")
    -- a client that answers nothing, a hidden answer, a client without the API: the window events decide, as before
    M.interactOff = true
    M.units.NPC = { name = "Trainer Tom" }; M.fire("TRAINER_SHOW"); money(-38)
    is("the API answers nothing: the window events decide", row(), "training", -38, "npc=Trainer Tom")
    M.interactOff = nil
    local real = C_PlayerInteractionManager.IsInteractingWithNpcOfType
    local secret = {}
    M.secrets[secret] = true
    C_PlayerInteractionManager.IsInteractingWithNpcOfType = function() return secret end
    money(-39)
    is("a hidden answer is no answer", row(), "training", -39, "npc=Trainer Tom")
    C_PlayerInteractionManager.IsInteractingWithNpcOfType = function() error("blocked") end
    money(-40)
    is("an API that throws is no answer", row(), "training", -40, "npc=Trainer Tom")
    C_PlayerInteractionManager.IsInteractingWithNpcOfType = real
    M.secrets[secret] = nil
    local pim = C_PlayerInteractionManager
    C_PlayerInteractionManager = nil
    money(-41)
    is("no interaction manager at all", row(), "training", -41, "npc=Trainer Tom")
    check("#43 sources: Emitter.interacting says nil without the API", E.interacting("merchant") == nil)
    C_PlayerInteractionManager = pim
    M.fire("TRAINER_CLOSED"); M.runTimers(); M.units.NPC = nil; later()
  end

  -- ── the refs of the milestone, the events, the upvalue limit ──────────────────────────────────────────────────
  check("#43 sources: the new ref keys are written after the old ones, in a fixed order",
    E.refStr({ drift = 1, to = "Mira", crash = 1, bank = "guild", share = 1, kind = "deposit", gap = 9, npc = "Bob" }) == "npc=Bob;gap=9;kind=deposit;share=1;bank=guild;crash=1;to=Mira;drift=1",
    E.refStr({ drift = 1, to = "Mira", crash = 1, bank = "guild", share = 1, kind = "deposit", gap = 9, npc = "Bob" }))
  do
    local known = M.unknownEvents or {}
    for _, ev in ipairs({ "CHAT_MSG_MONEY", "CONFIRM_TALENT_WIPE", "COMMODITY_PRICE_UPDATED", "UPDATE_INVENTORY_DURABILITY", "TRAINER_CLOSED", "MAIL_CLOSED", "AUCTION_HOUSE_CLOSED", "PLAYER_LOGOUT",
      "UI_ERROR_MESSAGE", "AUCTION_HOUSE_AUCTION_CREATED", "AUCTION_HOUSE_PURCHASE_COMPLETED", "COMMODITY_PURCHASE_SUCCEEDED", "COMMODITY_PURCHASE_FAILED", "AUCTION_CANCELED", "AUCTION_HOUSE_SHOW_ERROR" }) do
      local on = false
      for _, fr in ipairs(ns.eventFrames) do if fr.events[ev] then on = true end end
      check("#43 sources: " .. ev .. " is registered on one of the addon's frames", on or known[ev] == true)
    end
    -- the limit a Lua function has: 60 upvalues. Every event handler of the addon is under it (a file past it does
    -- not load at all, which "parse Emitter" says first)
    local worst = 0
    for _, fr in ipairs(ns.eventFrames) do
      local h = fr.scripts.OnEvent
      if h then worst = math.max(worst, debug.getinfo(h, "u").nups) end
    end
    check("#43 sources: no event handler has more than 60 upvalues", worst <= 60, worst)
    check("#43 sources: the money handler is under the limit too", debug.getinfo(ns._test.onMoney, "u").nups <= 60, debug.getinfo(ns._test.onMoney, "u").nups)
    check("#43 sources: Emitter.lua still loads (the upvalue and local limits)", loadfile("Everbuff/Emitter.lua") ~= nil)
    check("#43 sources: the helpers of 0.9.46 are on the Emitter table, not file-level locals", type(E.prunePending) == "function" and type(E.coinForm) == "function")
  end

  -- ── what the Gold pane says for these rows ────────────────────────────────────────────────────────────────────
  do
    local entries = G.entries(s0)
    local function find(src, pat) for _, e in ipairs(entries) do if e.src == src and e.detail:find(pat, 1, true) then return e end end end
    check("#43 sources: journal: a group share says so", find("looted", "Group share") ~= nil)
    check("#43 sources: journal: a repair of one item, a repair", find("repairs", "Repair, one item at Smith Sam") ~= nil and find("repairs", "Repair at Smith Sam") ~= nil)
    check("#43 sources: journal: deposit, bid or buyout, buyout, cancelled", find("auctions", "Deposit") and find("auctions", "Bid or buyout") and find("auctions", "Buyout") and find("auctions", "Auction cancelled") and find("auctions", "bid, buyout or deposit") and true)
    local back = find("sold", "Bought back: ")
    check("#43 sources: journal: a buyback says bought back, with no price flag", back ~= nil and back.delta == -65 and back.flag == nil, back and back.detail)
    local cloth = 0
    for _, top in ipairs(G.contributors((function() local t = {} for _, e in ipairs(entries) do if e.src == "sold" then t[#t + 1] = e end end return t end)())) do
      if top.name:lower() == "item 2589" then cloth = top.amount end
    end
    check("#43 sources: journal: the buyback counts against the item's sales (sold 5 times for 65, bought back once)", cloth == 65 * 4, cloth)
    check("#43 sources: journal: a talent reset", find("training", "Talent reset") ~= nil)
    local dr = find("unexplained", "the client sent no event")
    check("#43 sources: journal: drift is flagged unexplained", dr ~= nil and dr.flag == "unexplained" and find("other", "the client sent no event") ~= nil)
    local um = find("sold", "no item asked for has this amount")
    check("#43 sources: journal: an unmatched sale is flagged", um ~= nil and um.flag == "amount not matched")
    check("#43 sources: journal: an unmatched mail says so", find("mail", "no mail taken has this amount") ~= nil)
  end

  -- ── the identities over the whole played session ──────────────────────────────────────────────────────────────
  do
    M.runTimers()
    local okC, badC = chain(s0)
    check("#43 sources: balance chain over the whole session", okC and rows() - first > 80, badC)
    local sums = {}
    for i = 1, #s0.goldLog do local x = row(i, s0); sums[x.src] = (sums[x.src] or 0) + x.delta * E.GOLD_SIGN[x.src] end
    local okL, badL = true, nil
    for key in pairs(E.GOLD_SIGN) do
      if key ~= "unexplained" and key ~= "away" and (s0.gold[key] or 0) ~= (sums[key] or 0) then okL, badL = false, key end
    end
    check("#43 sources: the journal sums to the session ledger for every source key (a buyback counts against sold)", okL and s0.goldLogDropped == 0, badL)
    local known = 0
    for _, k in ipairs(G.IN) do if k ~= "unexplained" then known = known + (s0.gold[k] or 0) end end
    check("#43 sources: session: gained minus the known income is the unexplained rows", s0.gold.gained - known == (sums.unexplained or 0), s0.gold.gained - known - (sums.unexplained or 0))
    local out = 0
    for _, k in ipairs(G.OUT) do out = out + (s0.gold[k] or 0) end
    check("#43 sources: session: the spend keys sum to spent", out == s0.gold.spent, out - s0.gold.spent)
    check("#43 sources: character: balance = gained - spent + away", g.balance == born + g.gained - g.spent + (g.away or 0) and g.balance == M.money, g.balance - born - (g.gained - g.spent + (g.away or 0)))
    local d = ns.char().goldDays[G.dayKey(GetServerTime(), G.baseStored())]
    local din, dout = 0, 0
    for _, k in ipairs(G.IN) do din = din + (d[k] or 0) end
    for _, k in ipairs(G.OUT) do dout = dout + (d[k] or 0) end
    check("#43 sources: day row: income keys sum to g, spend keys to s, and it closes on the purse", din == d.g and dout == d.s and d.c == M.money, ("%s %s %s"):format(din - d.g, dout - d.s, tostring(d.c)))
    check("#43 sources: no error in the day writer, the rate window or a handler", E._dayErr == nil and G._rateErr == nil and #M.errors == errs0, tostring(E._dayErr or G._rateErr or M.errors[#M.errors]))
  end

  -- ── rule 9: the crash tag ─────────────────────────────────────────────────────────────────────────────────────
  -- The client writes the save file only after PLAYER_LOGOUT (a logout, an exit, a /reload), and there the session is
  -- always closed with endedBy = "logout". So every login below starts from the save file as the client would hold
  -- it: a copy of the DB taken right after a PLAYER_LOGOUT, put back over whatever the session did afterwards.
  do
    local function deepcopy(v)
      if type(v) ~= "table" then return v end
      local out = {}
      for k, x in pairs(v) do out[k] = deepcopy(x) end
      return out
    end
    local function putBack(dst, src)
      for k in pairs(dst) do if src[k] == nil then dst[k] = nil end end
      for k, v in pairs(src) do
        if type(v) == "table" and type(dst[k]) == "table" then putBack(dst[k], v) else dst[k] = deepcopy(v) end
      end
    end
    -- the client died: nothing since `file` was saved, and nothing of the running session is in memory
    local function died(file) putBack(ns.DB, file); ns.Recorder.discard(); ns._test.newLoad() end
    local function login() M.fire("PLAYER_ENTERING_WORLD", true, false); M.runTimers(); return ses() end
    local function reload()
      ReloadUI(); M.fire("PLAYER_LOGOUT")
      local file = deepcopy(ns.DB)
      ns._test.newLoad(); M.fire("PLAYER_ENTERING_WORLD", false, true); M.runTimers()
      return file
    end
    local function me() return ns.DB.characters[ns.charGuid()] end
    local function crashSum(s)
      local sum, n = 0, 0
      for _, e in ipairs(G.entries(s)) do if e.src == "away" and e.ref and e.ref.crash then sum, n = sum + e.delta, n + 1 end end
      return sum, n
    end

    -- a clean logout, the purse changed elsewhere: away, no crash
    M.fire("PLAYER_LOGOUT")
    local file = deepcopy(ns.DB)
    check("#43 sources: a logout leaves no open mark in the save file", me().goldOpen == nil)
    later(60)
    ns._test.newLoad(); M.money = M.money + 500
    local s1 = login()
    is("away after a clean logout carries no crash", row(1, s1), "away", 500, "gap=60")
    later()
    -- the client dies in a session with no /reload: the save file is still the one of the logout, and nothing in it
    -- says a session ran. A plain away row (the limit of what a save file can tell)
    M.fire("LOOT_OPENED"); money(40); later()
    died(file)
    local s2 = login()
    local r2 = row(1, s2)
    check("#43 sources: a crash with no /reload before it leaves no trace: a plain away row for all of it", s2 ~= s1 and r2.src == "away" and r2.delta == 540 and r2.refT.crash == nil and r2.refT.gap ~= nil, r2.ref)
    later()

    -- a /reload, then the client dies: the save of the reload holds the session closed (endedBy = "logout") and the mark
    local n2 = #s2.goldLog
    local file2 = reload()
    check("#43 sources: the save of a /reload closes the session in the file, as a logout does", file2.sessions[file2.active] ~= nil and file2.sessions[file2.active].endedBy == "logout")
    check("#43 sources: and carries the open mark for this character", type(file2.characters[ns.charGuid()].goldOpen) == "number")
    check("#43 sources: the reload resumes the session, no away row, the mark stays", ses() == s2 and s2.endedBy == nil and #s2.goldLog == n2 and type(me().goldOpen) == "number")
    M.fire("LOOT_OPENED"); money(1234); later()
    died(file2)
    check("#43 sources: after the crash the file says the session ended by logout (no orphan to find)", ns.DB.sessions[ns.DB.active].endedBy == "logout")
    local s3 = login()
    is("away after a /reload and a crash carries crash=1", row(1, s3), "away", 1234, "gap=10;crash=1")
    local e = G.entries(s3)[1]
    check("#43 sources: the journal calls it unattributed", e and e.detail == "Unattributed (game closed without saving)", e and e.detail)
    check("#43 sources: the mark is read once", s3 ~= s2 and me().goldOpen == nil)
    -- what the Gold pane says: the amount is in the NET card of the pane (the glance figures stay gained minus spent)
    do
      local sum, n = crashSum(s3)
      check("#43 sources: the crash rows of the session sum to the row", sum == 1234 and n == 1, sum)
      local sc = G.scope("session", "char")
      local t = G.netCard(sc.ledger, G.scopeEntries(sc))
      check("#43 sources: pane: the NET card counts the crash amount", t.crash == 1234 and t.net == sc.ledger.gained - sc.ledger.spent + 1234, ("%s %s"):format(tostring(t.crash), tostring(t.net)))
      check("#43 sources: pane: the status line names it and says where it counts", t.line ~= nil and t.line:find("Unattributed (game closed without saving): +", 1, true) == 1 and t.line:find(", counted in the net of this pane", 1, true) ~= nil, t.line)
      check("#43 sources: pane: it is not also listed as changed while away", t.away == 0, t.away)
      check("#43 sources: the glance net stays gained minus spent (day rows carry no crash amount)", G.figure("net", sc.ledger) == sc.ledger.gained - sc.ledger.spent)
    end
    later()

    -- a /reload, then a real logout: the mark is gone, the next login is a plain one
    reload()
    check("#43 sources: the mark is set again by the next /reload", type(me().goldOpen) == "number")
    M.fire("PLAYER_LOGOUT")
    check("#43 sources: a real logout after a /reload removes the mark", me().goldOpen == nil)
    later(60)
    ns._test.newLoad(); M.money = M.money + 5
    local s4 = login()
    is("away after a /reload and a clean logout carries no crash", row(1, s4), "away", 5, "gap=60")
    later()

    -- a 0 read at the login after a crash, then corrected: the booking and its take-back carry the same tag and cancel
    local file5 = reload()
    later()
    died(file5)
    local saved = me().gold.balance
    local real = M.money
    check("#43 sources: 0-read after a crash: the test starts with gold saved", saved > 0 and saved == real, saved)
    M.money = 0
    local s5 = login()
    M.now = M.now + 15; M.fire("PLAYER_MONEY"); M.runTimers()
    local r5 = row(#s5.goldLog, s5)
    check("#43 sources: 0-read after a crash: the 0 is booked with crash=1", r5.src == "away" and r5.delta == -saved and r5.refT.crash == "1", r5.ref)
    M.money = real; M.fire("PLAYER_MONEY"); M.runTimers()
    local r6 = row(#s5.goldLog, s5)
    check("#43 sources: 0-read after a crash: the take-back carries the same tag", r6.src == "away" and r6.delta == saved and r6.refT.crash == "1" and r6.bal == saved, r6.ref)
    local sum5 = crashSum(s5)
    check("#43 sources: 0-read after a crash: the crash rows sum to 0, so does away", sum5 == 0 and (s5.gold.away or 0) == 0, sum5)
    do
      local sc = G.scope("session", "char")
      local t = G.netCard(sc.ledger, G.scopeEntries(sc))
      check("#43 sources: 0-read after a crash: the pane shows no crash amount and nothing changed while away", t.crash == 0 and t.net == sc.ledger.gained - sc.ledger.spent and t.line == nil and t.away == 0, tostring(t.line))
    end
    later()
    M.fire("PLAYER_LOGOUT"); later(60)
    ns._test.newLoad(); M.fire("PLAYER_ENTERING_WORLD", true, false); M.runTimers(); later()
  end
end
