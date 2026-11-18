-- Transfers and refunds (everbuff-wow-addon #43, 0.9.48). Loaded by tests/run_tests.lua after tests/gold_show.lua
-- and by tests/gold_profile.lua (the stub as it is and the WoW Forever profile):
--   dofile("tests/gold_xfer.lua")({ check = check, M = M, ns = ns })
-- Runs on a save file of its own (the suite's is put aside and put back), on a WoW Forever style client: a long
-- realm string and characters with two names. One case per rule of the milestone: the four ledger keys and the
-- session and ledger marks, who counts as an own character (full name only, never the logged-in one), sending mail
-- with the postage split in one and in two purse changes, mail from an own character, a trade with a colliding
-- name, "This is my character", a failed send, a returned bid, the banks, a session from before the update, the
-- netted figures on every surface, the unmatched line, and every identity of the journal and the day rows. From the
-- review of the draft: a trade partner read with both names, a COD between own characters, a small spend beside an
-- open send, the farm timer and the ledger's marks, the legs with no second side (xferSolo), the legacy bid hook.
return function(P)
  local check, M, ns = P.check, P.M, P.ns
  local E, G = ns.Emitter, ns.Gold
  local DAY = 86400
  local ME = "Player-1-000001"
  local T = "#43 xfer: "
  local realPrint = print
  local said = {}
  print = function(...) said[#said + 1] = table.concat({ ... }, " ") end
  -- (chat is captured in this file; a failing check still prints)
  local rawCheck = check
  check = function(name, cond, detail) local p = print; print = realPrint; rawCheck(name, cond, detail); print = p end

  local main = { db = ns.DB, epoch = M.epoch, now = M.now, money = M.money, inbox = M.inbox, interact = M.interact, friends = M.friends, guild = M.guild }
  local real = { realm = _G.GetRealmName, unitName = _G.UnitName, unmod = _G.UnitNameUnmodified, playerInfo = _G.C_PlayerInfo,
    outbid = _G.AUCTION_OUTBID_MAIL_SUBJECT, frameShown = _G.EverbuffFrame and _G.EverbuffFrame.shown }
  ns.Recorder.pause("logout")
  local function fresh(db)
    ns.Recorder.discard()
    ns.DB = ns.migrateDB(db or {})
    G._held, G._baseWait, G._flushTimer, G._tickAt = nil, nil, nil, nil
    E._openGain, E._questMoney, E._dayErr = nil, nil, nil
    ns._test.newLoad()
    M.timers = {}
    for _, e in ipairs({ "MERCHANT_CLOSED", "MAIL_CLOSED", "AUCTION_HOUSE_CLOSED", "TRAINER_CLOSED", "TRADE_CLOSED" }) do M.fire(e) end
    M.timers = {}
    M.units.NPC = nil
    M.now = M.now + 100
  end
  local function login(reload) M.fire("PLAYER_ENTERING_WORLD", not reload, reload and true or false); M.runTimers() end
  local function ses() return ns.Recorder.current() end
  local function money(d) M.money = M.money + d; M.fire("PLAYER_MONEY") end
  local function later(s) M.now = M.now + (s or 10); M.epoch = M.epoch + (s or 10) end
  local function rows() return #ses().goldLog end
  local function row(i, s)
    local log = (s or ses()).goldLog
    i = i or #log
    local mono, d, src, bal, ref = E.rowParse(log[i] or "")
    return { mono = mono, delta = d, src = src, bal = bal, ref = ref, refT = E.refParse(ref) }
  end
  local function is(name, r, src, delta, ref, bal)
    check(T .. name, r.src == src and r.delta == delta and r.bal == (bal or M.money) and (ref == nil or r.ref == ref),
      ("%s %s %s %s [%s]"):format(tostring(r.src), tostring(r.delta), tostring(r.bal), tostring(M.money), tostring(r.ref)))
  end
  local function chain(s)
    for i = 2, #s.goldLog do
      local a, b = row(i - 1, s), row(i, s)
      if b.bal - a.bal ~= b.delta then return false, i end
    end
    return true
  end
  local function has(list, text)
    for _, l in ipairs(list) do if tostring(l):find(text, 1, true) then return true end end
    return false
  end

  -- a WoW Forever style client
  local REALM = "Forever Realm [EU] - Azure Dawn's Rest"
  _G.GetRealmName = function() return REALM end
  _G.C_PlayerInfo = { ShouldDisplaySurname = function() return true end, IsAccountBankEnabled = function() return M.accountBank == true end }
  _G.UnitName = function(u) if u == "player" then return "Hart", "Hammershield" end return real.unitName(u) end
  _G.UnitNameUnmodified = _G.UnitName
  _G.AUCTION_OUTBID_MAIL_SUBJECT = "Outbid on %s"
  M.inbox, M.interact, M.friends, M.guild, M.accountBank, M.bankMoney, M.sendPrice = {}, {}, {}, {}, nil, nil, 30
  if _G.EverbuffFrame then _G.EverbuffFrame.shown = false end

  fresh()
  M.epoch, M.money = 1795500000, 50000000
  login()
  local now = M.epoch
  local chars = ns.DB.characters
  local c = chars[ME]
  local g = c.gold
  -- A: two names, this realm; B: one name, seen since the update; C: this realm, not seen since the update (no
  -- facts); D: two names, another realm; the logged-in character is Hart Hammershield
  chars.A = { name = "Mira", surname = "Dawnfall", realm = "forever realm [EU] - Azure Dawns Rest", class = "MAGE", faction = "Alliance", level = 21, seen = now - 3 * DAY, gold = { balance = 961000 } }
  chars.B = { name = "Grok", realm = REALM, class = "SHAMAN", faction = "Horde", level = 40, seen = now - 10 * DAY, gold = { balance = 250000 } }
  chars.C = { name = "Lena", realm = REALM, gold = { balance = 3000 } }
  chars.D = { name = "Mira", surname = "Sunfall", realm = "Forever Realm [EU] - Other Shore", class = "PRIEST", faction = "Alliance", level = 12, seen = now - DAY, gold = { balance = 70000 } }
  E.loadAlts()
  -- (the day base is written with the first credit)
  local base
  local function day() base = base or G.baseStored(); return c.goldDays[G.dayKey(GetServerTime(), base)] end
  local errs0 = #M.errors

  -- ── the session and the ledger say that transfers are apart ───────────────────────────────────────────────────
  do
    local s = ses()
    check(T .. "a session started on this version carries goldV = 2", s.goldV == 2)
    check(T .. "its ledger has the four new keys from the start, at 0", s.gold.xferIn == 0 and s.gold.xferOut == 0 and s.gold.mailSent == 0 and s.gold.auctionRefund == 0)
    check(T .. "the character's ledger is not marked before the first purse change", g.v == nil and g.since == nil)
    -- a farm timer started before the mark (it survives a relog): the marks are not copper, the timer never has them
    G.timerStart()
    M.fire("LOOT_OPENED"); money(100); later()
    local tm = G.timer()
    check(T .. "a farm timer started before the mark has neither v nor since in its ledger", tm ~= nil and tm.ledger.v == nil and tm.ledger.since == nil and tm.ledger.gained == 100 and tm.net == 100,
      ("%s %s"):format(tostring(tm and tm.ledger.v), tostring(tm and tm.ledger.since)))
    G.timerStart()
    check(T .. "a farm timer started after it keeps neither in its snapshot", c.goldTimer.ledger.v == nil and c.goldTimer.ledger.since == nil and G.timer().ledger.v == nil)
    check(T .. "an all time scope does not sum the marks either", G.scope("all").ledger.v == nil and G.scope("all", "account").ledger.since == nil)
    c.goldTimer = nil
    money(-100); M.fire("LOOT_OPENED"); money(100)
    check(T .. "the first purse change marks the ledger: gold.v = 2 and gold.since", g.v == 2 and g.since == M.epoch - 10, tostring(g.since))
    local since = g.since
    M.fire("LOOT_OPENED"); money(100); later()
    check(T .. "gold.since is written once", g.since == since)
  end

  -- ── who counts as an own character (rule 20) ──────────────────────────────────────────────────────────────────
  do
    check(T .. "the full name of a two-name character is an own character", E.relOf("Mira Dawnfall") == "alt")
    check(T .. "in any case and with stray spaces", E.relOf("mira dawnfall") == "alt" and E.relOf("  Mira   Dawnfall ") == "alt")
    check(T .. "its first name alone is uncertain", E.relOf("Mira") == "alt?", E.relOf("Mira"))
    check(T .. "a one-name character seen since the update is an own character", E.relOf("Grok") == "alt")
    check(T .. "a block with no facts yet is uncertain", E.relOf("Lena") == "alt?")
    check(T .. "the logged-in character is not its own alt", E.relOf("Hart Hammershield") == "stranger" and E.relOf("Hart") == "stranger", E.relOf("Hart"))
    check(T .. "a character of another realm is not matched on this one", E.relOf("Mira Sunfall") == "stranger")
    check(T .. "another player with an alt's first name and another surname is a stranger", E.relOf("Mira Stonefist") == "stranger")
    check(T .. "the realm suffix is read, written with other spacing", E.relOf("Mira Sunfall-ForeverRealm[EU]OtherShore") == "alt", E.relOf("Mira Sunfall-ForeverRealm[EU]OtherShore"))
  end

  -- ── sending mail (rules 16 and 17) ────────────────────────────────────────────────────────────────────────────
  M.fire("MAIL_SHOW")
  do
    -- one purse change: the postage row, then the transfer, with the balance between the two
    local n0, bal0 = rows(), M.money
    local spent0, post0, x0, n1 = g.spent, g.mailSpent or 0, g.xferOut or 0, day().n
    SetSendMailMoney(1000000); SendMail("Mira Dawnfall", "gold", "")
    money(-1000030)
    check(T .. "mail to an own two-name character, one purse change: two rows", rows() == n0 + 2, rows() - n0)
    is("the postage row comes first, with the balance before the gold left", row(n0 + 1), "mailSpent", -30, "kind=postage;to=Mira Dawnfall", bal0 - 30)
    is("the gold is a transfer out, named", row(n0 + 2), "xferOut", -1000000, "rel=alt;to=Mira Dawnfall")
    check(T .. "the ledger: spent once, postage and transfer each on its key", g.spent == spent0 + 1000030 and g.mailSpent == post0 + 30 and g.xferOut == x0 + 1000000,
      ("%s %s %s"):format(g.spent - spent0, g.mailSpent - post0, (g.xferOut or 0) - x0))
    check(T .. "the session's ledger says the same", ses().gold.xferOut == 1000000 and ses().gold.mailSpent == 30 and ses().gold.mailSent == 0)
    check(T .. "the day row: one purse change, both keys", day().n == n1 + 1 and day().xferOut == 1000000 and day().mailSpent == 30 and day().c == M.money, day().n - n1)
    check(T .. "the pending send is used up", E._send == nil)
    later()
    -- two purse changes, the postage first
    n0 = rows()
    SetSendMailMoney(200000); SendMail("Mira Dawnfall", "gold", "")
    money(-30); is("two purse changes: the postage alone", row(), "mailSpent", -30, "kind=postage;to=Mira Dawnfall")
    money(-200000); is("two purse changes: then the gold", row(), "xferOut", -200000, "rel=alt;to=Mira Dawnfall")
    check(T .. "two purse changes: two rows, the send is used up", rows() == n0 + 2 and E._send == nil)
    later()
    -- two purse changes, the gold first
    n0 = rows()
    SetSendMailMoney(300000); SendMail("grok", "gold", "")
    money(-300000); is("the gold first: a transfer to a one-name character, as typed", row(), "xferOut", -300000, "rel=alt;to=grok")
    money(-30); is("the gold first: then the postage", row(), "mailSpent", -30, "kind=postage;to=grok")
    check(T .. "the gold first: two rows, the send is used up", rows() == n0 + 2 and E._send == nil)
    later()
    -- a client that names no postage: any postage up to 30c x 13
    M.sendPrice = nil
    n0, bal0 = rows(), M.money
    SetSendMailMoney(50000); SendMail("Mira Dawnfall", "gold and items", "")
    money(-50390)
    is("no price named: postage of 30c x 13 is still a postage row", row(n0 + 1), "mailSpent", -390, "kind=postage;to=Mira Dawnfall", bal0 - 390)
    is("no price named: the gold is the transfer", row(n0 + 2), "xferOut", -50000, "rel=alt;to=Mira Dawnfall")
    later()
    n0 = rows()
    SetSendMailMoney(50000); SendMail("Mira Dawnfall", "gold", "")
    money(-50391)
    check(T .. "no price named: more than 30c x 13 beside the gold fits nothing, one mailSpent row as before", rows() == n0 + 1 and row().src == "mailSpent" and row().delta == -50391 and row().ref == "", row().ref)
    M.fire("MAIL_CLOSED"); M.runTimers(); M.fire("MAIL_SHOW"); later()
    M.sendPrice = 30
    -- the price is named: only exactly that
    n0 = rows()
    SetSendMailMoney(50000); SendMail("Mira Dawnfall", "gold", "")
    money(-50031)
    check(T .. "a price named: gold plus another amount fits nothing, one mailSpent row as before", rows() == n0 + 1 and row().src == "mailSpent" and row().delta == -50031 and row().ref == "", row().ref)
    M.fire("MAIL_CLOSED"); M.runTimers(); M.fire("MAIL_SHOW"); later()
    -- a mail with no gold: postage only
    n0 = rows()
    SendMail("Someone Else", "hello", "")
    money(-30)
    is("a mail with no gold is one postage row", row(), "mailSpent", -30, "kind=postage;to=Someone Else")
    check(T .. "a mail with no gold: one row", rows() == n0 + 1 and E._send == nil)
    later()
    -- a stranger who shares a first name with an alt (the plan's case), and the first name alone
    local sent0, xo = g.mailSent or 0, g.xferOut
    SetSendMailMoney(70000); SendMail("Mira Stonefist", "gold", "")
    money(-70030)
    is("mail to a stranger sharing a first name with an alt is not a transfer", row(), "mailSent", -70000, "rel=stranger;to=Mira Stonefist")
    later()
    SetSendMailMoney(80000); SendMail("Mira", "gold", "")
    money(-80030)
    is("mail to a first name alone is uncertain: shown, not booked as a transfer", row(), "mailSent", -80000, "rel=alt?;to=Mira")
    check(T .. "neither moved xferOut; mailSent has both", g.xferOut == xo and g.mailSent == sent0 + 150000)
    later()
    -- the send older than 5 s is forgotten
    n0 = rows()
    SetSendMailMoney(90000); SendMail("Mira Dawnfall", "gold", "")
    later(6); money(-90030)
    check(T .. "a purse change 6 s after the send is not the send's", rows() == n0 + 1 and row().src == "mailSpent" and row().ref == "" and E._send == nil, row().src .. " " .. row().ref)
    later()
    -- a COD mail sent: no gold leaves, the postage is a postage row
    SetSendMailCOD(500000); SendMail("Mira Dawnfall", "cod", "")
    money(-30)
    is("a COD mail sent: only the postage leaves the purse", row(), "mailSpent", -30, "kind=postage;to=Mira Dawnfall")
    later()
    check(T .. "the chain holds over every split", chain(ses()))
  end

  -- ── a failed send, then a COD payment (the plan's case) ───────────────────────────────────────────────────────
  do
    local xo = g.xferOut
    SetSendMailMoney(50000); SendMail("Mira Dawnfall", "gold", "")
    M.fire("MAIL_FAILED")
    check(T .. "MAIL_FAILED forgets the pending send", E._send == nil)
    M.inbox = { { sender = "Rando", subject = "ore", cod = 50000, items = { { name = "Copper Ore", id = 2770, count = 10, quality = 1 } } } }
    TakeInboxItem(1, 1); money(-50000)
    is("a failed send, then a COD payment of the same amount, is not claimed", row(), "mailSpent", -50000, "sender=Rando;rel=stranger;cod=50000")
    check(T .. "no transfer was booked for it", g.xferOut == xo)
    later()
    SetSendMailMoney(50000); SendMail("Mira Dawnfall", "gold", "")
    M.fire("MAIL_CLOSED"); M.runTimers()
    check(T .. "MAIL_CLOSED forgets the pending send", E._send == nil)
    M.fire("MAIL_SHOW"); M.inbox = {}; later()
  end

  -- ── a small spend beside a send still waiting for its postage (no price named by the client) ─────────────────
  do
    M.sendPrice = nil
    local n0 = rows()
    SetSendMailMoney(100000); SendMail("Grok", "gold", "")
    money(-100000)
    is("no price named: the gold alone is booked, the postage is still waited for", row(), "xferOut", -100000, "rel=alt;to=Grok")
    check(T .. "the send stays open for its postage", E._send ~= nil and E._send.moneyDone == true)
    M.inbox = { { sender = "Rando", subject = "ore", cod = 300, items = { { name = "Copper Ore", id = 2770, count = 10, quality = 1 } } } }
    TakeInboxItem(1, 1); money(-300)
    is("a COD payment taken beside it is not the send's postage", row(), "mailSpent", -300, "sender=Rando;rel=stranger;cod=300")
    check(T .. "the send still waits", E._send ~= nil and rows() == n0 + 2)
    M.fire("MAIL_SEND_SUCCESS")
    check(T .. "MAIL_SEND_SUCCESS closes a send whose gold is booked", E._send == nil)
    later(4); money(-30)
    is("a small spend after it is booked as before 0.9.48", row(), "mailSpent", -30, "")
    M.inbox = {}; later()
    -- a mail with no gold: the success event does not close it before its postage came
    SendMail("Someone Else", "hello", "")
    M.fire("MAIL_SEND_SUCCESS")
    check(T .. "MAIL_SEND_SUCCESS leaves a send with nothing booked yet", E._send ~= nil)
    money(-60)
    is("no price named, nothing else explains the spend: it is the postage", row(), "mailSpent", -60, "kind=postage;to=Someone Else")
    later()
    -- a purchase of that price asked for, and a trade, are not the postage either
    SendMail("Someone Else", "hello", "")
    E._pend.buy[#E._pend.buy + 1] = { id = 159, n = 1, amount = 25, at = GetTime() }
    money(-25)
    check(T .. "a spend a pending purchase explains is not the postage", row().refT.kind ~= "postage", row().src .. " " .. row().ref)
    E._pend.buy = {}
    E.sendClear(); later()
    M.sendPrice = 30
  end

  -- ── COD between two own characters: both legs are transfers ───────────────────────────────────────────────────
  do
    local xo, post0, solo0 = g.xferOut, g.mailSpent or 0, g.xferSolo or 0
    M.inbox = { { sender = "Grok", subject = "ore", cod = 50000, items = { { name = "Copper Ore", id = 2770, count = 10, quality = 1 } } } }
    TakeInboxItem(1, 1); money(-50000)
    is("a COD paid to an own character is a transfer out, named", row(), "xferOut", -50000, "sender=Grok;rel=alt;cod=50000")
    check(T .. "it is booked instead of mailSpent, and it has a second leg in this save file", g.xferOut == xo + 50000 and (g.mailSpent or 0) == post0 and (g.xferSolo or 0) == solo0)
    later()
    M.inbox = { { sender = "Mira", subject = "ore", cod = 700, items = { { name = "Copper Ore", id = 2770, count = 1, quality = 1 } } } }
    TakeInboxItem(1, 1); money(-700)
    is("a COD paid to an uncertain name stays mailSpent", row(), "mailSpent", -700, "sender=Mira;rel=alt?;cod=700")
    later()
    -- the seller's side: the payment mail the paying character sent is xferIn, so the account's net is unchanged
    M.inbox = { { sender = "Grok", subject = "COD Payment: Copper Ore", money = 50000 } }
    local xi = g.xferIn or 0
    TakeInboxMoney(1); money(50000)
    is("the COD payment an own character sent is a transfer in", row(), "xferIn", 50000, "sender=Grok;rel=alt;cod=0")
    check(T .. "the two legs of a COD between own characters cancel: earned, spent and net unchanged", (g.xferIn or 0) - xi == 50000 and g.xferOut - xo == 50000)
    M.inbox = {}; later()
  end

  -- ── mail from an own character (rule 20) ──────────────────────────────────────────────────────────────────────
  do
    local mail0, xi, gained0 = g.mail or 0, g.xferIn or 0, g.gained
    M.inbox = {
      { sender = "Mira Dawnfall", subject = "gold", money = 500000 },
      { sender = "Mira", subject = "gold", money = 60000 },
      { sender = "Mira Stonefist", subject = "gold", money = 7000 },
      { sender = "Lena", subject = "gold", money = 800 },
    }
    TakeInboxMoney(1); money(500000)
    is("mail from an own character is xferIn instead of mail", row(), "xferIn", 500000, "sender=Mira Dawnfall;rel=alt;cod=0")
    check(T .. "it is booked instead of mail, never beside it", (g.mail or 0) == mail0 and g.xferIn == xi + 500000 and g.gained == gained0 + 500000)
    local lr = ns.DB.loot.log[#ns.DB.loot.log]
    check(T .. "its loot log row names the mail", lr.money == 500000 and lr.mail and lr.mail.rel == "alt" and lr.src == "Mail from Mira Dawnfall", lr.src)
    later()
    TakeInboxMoney(2); money(60000)
    is("mail from a first name alone stays mail, tagged alt?", row(), "mail", 60000, "sender=Mira;rel=alt?;cod=0")
    later()
    TakeInboxMoney(3); money(7000)
    is("mail from a stranger with an alt's first name stays mail", row(), "mail", 7000, "sender=Mira Stonefist;rel=stranger;cod=0")
    later()
    TakeInboxMoney(4); money(800)
    is("mail from a block with no facts stays mail, tagged alt?", row(), "mail", 800, "sender=Lena;rel=alt?;cod=0")
    later()
    -- an amount no waiting mail has is never a transfer
    M.inbox = { { sender = "Mira Dawnfall", subject = "gold", money = 4000 } }
    TakeInboxMoney(1); money(4001)
    is("a gain that matches no mail taken is plain mail, never a transfer", row(), "mail", 4001, "x=unmatched")
    money(4000)
    is("the mail's own amount is then the transfer", row(), "xferIn", 4000, "sender=Mira Dawnfall;rel=alt;cod=0")
    check(T .. "xferIn holds the two exact matches only", g.xferIn == xi + 504000 and (g.mail or 0) == mail0 + 60000 + 7000 + 800 + 4001)
    M.inbox = {}; later()
  end

  -- ── a returned bid (rule 18) ──────────────────────────────────────────────────────────────────────────────────
  do
    local ref0, mail0 = g.auctionRefund or 0, g.mail or 0
    M.inbox = {
      { sender = "Stormwind Auction House", subject = "Outbid on Linen Cloth", money = 7000, canReply = false },
      { sender = "The Postmaster", subject = "Recovered items", money = 900, canReply = false },
      { sender = "Rando", subject = "Outbid on your patience", money = 1234 },
      { sender = "Stormwind Auction House", subject = "Outbid on Copper Ore", money = 5500, canReply = false },
    }
    TakeInboxMoney(1); money(7000)
    is("a mail with the client's outbid subject that cannot be answered is a returned bid", row(), "auctionRefund", 7000, "sender=Stormwind Auction House;rel=system;cod=0")
    check(T .. "booked instead of mail", g.auctionRefund == ref0 + 7000 and (g.mail or 0) == mail0)
    later()
    TakeInboxMoney(2); money(900)
    is("an NPC money mail stays mail", row(), "mail", 900, "sender=The Postmaster;rel=system;cod=0")
    later()
    TakeInboxMoney(3); money(1234)
    is("a player's mail with that subject, and no bid of that amount, stays mail", row(), "mail", 1234, "sender=Rando;rel=stranger;cod=0")
    later()
    -- an open bid of exactly the amount confirms the refund and is used up
    M.fire("AUCTION_HOUSE_SHOW")
    C_AuctionHouse.PlaceBid(77, 5500); money(-5500)
    is("the bid itself is auction house spending, gross", row(), "auctions", -5500, "kind=bid")
    check(T .. "the bid hook notes the open bid on the character", type(c.goldBids) == "table" and #c.goldBids == 1 and c.goldBids[1].amount == 5500 and c.goldBids[1].at == M.epoch)
    M.fire("AUCTION_HOUSE_CLOSED"); M.runTimers(); later()
    TakeInboxMoney(4); money(5500)
    is("a refund that equals an open bid says so", row(), "auctionRefund", 5500, "sender=Stormwind Auction House;rel=system;cod=0;kind=bid")
    check(T .. "the open bid is used up", c.goldBids == nil)
    later()
    -- a player's mail with the subject and the amount of an open bid: the bid confirms it
    C_AuctionHouse.PlaceBid(78, 4321)
    M.inbox = { { sender = "Stormwind Auction House", subject = "Outbid on Silk", money = 4321 } }
    TakeInboxMoney(1); money(4321)
    check(T .. "a mail with the subject whose amount is an open bid is a returned bid", row().src == "auctionRefund" and row().refT.kind == "bid", row().src .. " " .. row().ref)
    later()
    -- the bids kept: at most 50, none older than 7 days
    for i = 1, 60 do C_AuctionHouse.PlaceBid(i, 1000 + i) end
    check(T .. "at most 50 open bids are kept, the oldest dropped", #c.goldBids == 50 and c.goldBids[1].amount == 1011 and c.goldBids[50].amount == 1060, #c.goldBids)
    M.epoch = M.epoch + 8 * DAY
    C_AuctionHouse.PlaceBid(1, 999)
    check(T .. "a bid older than 7 days is forgotten", #c.goldBids == 1 and c.goldBids[1].amount == 999, #c.goldBids)
    M.epoch = M.epoch - 8 * DAY
    c.goldBids = nil
    -- the legacy call PlaceAuctionBid(type, index, bid) notes the bid too, where the client still has it
    if type(PlaceAuctionBid) == "function" then
      PlaceAuctionBid("list", 3, 8800)
      check(T .. "the legacy PlaceAuctionBid notes an open bid from its third argument", type(c.goldBids) == "table" and #c.goldBids == 1 and c.goldBids[1].amount == 8800)
      PlaceAuctionBid("list", 3, 0); PlaceAuctionBid("list", 3)
      check(T .. "a bid of nothing notes nothing", #c.goldBids == 1)
      c.goldBids = nil
    end
    E._ah = { claims = {} }
    -- no outbid subject on this client: nothing is a refund
    _G.AUCTION_OUTBID_MAIL_SUBJECT = nil
    M.inbox = { { sender = "Stormwind Auction House", subject = "Outbid on Linen Cloth", money = 7100, canReply = false } }
    TakeInboxMoney(1); money(7100)
    is("a client with no outbid subject books no refund", row(), "mail", 7100, "sender=Stormwind Auction House;rel=system;cod=0")
    _G.AUCTION_OUTBID_MAIL_SUBJECT = "%s was outbid"
    M.inbox = { { sender = "Stormwind Auction House", subject = "Linen Cloth was outbid", money = 7200, canReply = false } }
    TakeInboxMoney(1); money(7200)
    is("a subject format with no text before its %s has no prefix: no refund", row(), "mail", 7200, "sender=Stormwind Auction House;rel=system;cod=0")
    _G.AUCTION_OUTBID_MAIL_SUBJECT = "Outbid on %s"
    check(T .. "auctionRefund holds the three returned bids", g.auctionRefund == ref0 + 7000 + 5500 + 4321, g.auctionRefund - ref0)
    M.inbox = {}; later()
  end
  M.fire("MAIL_CLOSED"); M.runTimers(); later()

  -- ── trades (rule 19) and "This is my character" (decision 11) ─────────────────────────────────────────────────
  do
    local function trade(name, got, gave)
      -- (the client gives a unit's two names as two values, as it does for the player)
      local first, sur = name:match("^(%S+) (.+)$")
      M.units.NPC = { name = first or name, surname = sur }; M.fire("TRADE_SHOW")
      M.tradeWin = { gaveMoney = gave or 0, gotMoney = got or 0 }; M.fire("TRADE_MONEY_CHANGED"); M.fire("TRADE_ACCEPT_UPDATE", 1, 1)
      M.tradeWin = nil
      M.fire("UI_INFO_MESSAGE", 0, "Trade complete."); M.fire("TRADE_CLOSED"); M.units.NPC = nil
      money((got or 0) - (gave or 0))
      later()
    end
    local xi, xo, tr0 = g.xferIn, g.xferOut, g.trade or 0
    trade("Grok", 25000)
    check(T .. "a trade with a partner who has an alt's name stays trade", row().src == "trade" and row().refT.rel == "alt" and g.xferIn == xi and (g.trade or 0) == tr0 + 25000, row().src .. " " .. row().ref)
    -- a character on another account, marked by the player
    check(T .. "an unmarked name is not mine", G.isMine("Otheracct Banker") == false and #G.mineList() == 0)
    local key = G.mineSet("Otheracct Banker", true)
    check(T .. "the mark is settings.gold.mine[nameKey]", key == "otheracct banker-foreverrealm[eu]azuredawnsrest" and ns.DB.settings.gold.mine[key] == true and G.isMine("otheracct  banker"), tostring(key))
    check(T .. "a marked name is an own character", E.relOf("Otheracct Banker") == "alt")
    trade("Otheracct Banker", 30000)
    is("a trade with a character marked as mine is a transfer in", row(), "xferIn", 30000, ("partner=Otheracct Banker;rel=alt;trade=%d"):format(#ses().trades))
    trade("Otheracct Banker", 0, 12000)
    is("and a transfer out", row(), "xferOut", -12000, ("partner=Otheracct Banker;rel=alt;trade=%d"):format(#ses().trades))
    check(T .. "the trade itself is still written to trades[]", ses().trades[#ses().trades].partner == "Otheracct Banker" and ses().trades[#ses().trades].gaveMoney == 12000)
    M.fire("MAIL_SHOW")
    M.inbox = { { sender = "Otheracct Banker", subject = "gold", money = 2500 } }
    TakeInboxMoney(1); money(2500)
    is("mail from a character marked as mine is a transfer", row(), "xferIn", 2500, "sender=Otheracct Banker;rel=alt;cod=0")
    M.inbox = {}; M.fire("MAIL_CLOSED"); M.runTimers(); later()
    check(T .. "the marks moved xferIn and xferOut, not trade", g.xferIn == xi + 32500 and g.xferOut == xo + 12000 and (g.trade or 0) == tr0 + 25000)
    -- applied forward only: taking the mark back changes nothing written, and the next trade is a trade again
    local n0 = rows()
    G.mineSet("Otheracct Banker", false)
    check(T .. "the mark taken back leaves no key and no empty table", ns.DB.settings.gold.mine == nil and rows() == n0)
    trade("Otheracct Banker", 100)
    check(T .. "without the mark the same partner is a trade again", row().src == "trade" and row().refT.rel == "stranger", row().src .. " " .. row().ref)
    check(T .. "a trade names its partner by both names, in the row and in trades[]", row().refT.partner == "Otheracct Banker" and ses().trades[#ses().trades].partner == "Otheracct Banker")
    -- the partner is read with both names: a mark set from a mail row matches the trade, a first name never does
    local xi2, tr2 = g.xferIn, g.trade or 0
    G.mineSet("Otheracct Banker", true)
    trade("Otheracct Someoneelse", 800)
    check(T .. "another player sharing the first name of a marked character stays trade", row().src == "trade" and row().refT.rel == "stranger" and row().refT.partner == "Otheracct Someoneelse"
      and g.xferIn == xi2 and (g.trade or 0) == tr2 + 800, row().src .. " " .. row().ref)
    trade("Otheracct", 900)
    check(T .. "and so does a player who has that first name alone", row().src == "trade" and g.xferIn == xi2, row().src .. " " .. row().ref)
    trade("Otheracct Banker", 1000)
    check(T .. "the marked character itself, read as two values, is the transfer", row().src == "xferIn" and row().refT.partner == "Otheracct Banker" and g.xferIn == xi2 + 1000, row().src .. " " .. row().ref)
    G.mineSet("Otheracct Banker", false)
    -- a mark of one word where the client shows surnames: whole only for a trade partner who has no second name
    G.mineSet("Solo", true)
    check(T .. "a one-word mark is kept, and a mail string with it is uncertain", G.isMine("Solo") and E.isMine("Solo") == false and E.relOf("Solo") == "alt?")
    M.fire("MAIL_SHOW")
    M.inbox = { { sender = "Solo", subject = "gold", money = 1500 } }
    TakeInboxMoney(1); money(1500)
    is("mail from a one-word mark stays mail, tagged alt?", row(), "mail", 1500, "sender=Solo;rel=alt?;cod=0")
    M.inbox = {}; M.fire("MAIL_CLOSED"); M.runTimers(); later()
    trade("Solo Otherguy", 1600)
    check(T .. "a two-name partner with that first name stays trade", row().src == "trade" and row().refT.rel == "stranger", row().src .. " " .. row().ref)
    trade("Solo", 1700)
    check(T .. "a partner with that one name and no second is the marked character", row().src == "xferIn" and row().refT.rel == "alt" and row().refT.partner == "Solo", row().src .. " " .. row().ref)
    -- where the client shows no surnames the second value is a realm and is not read
    _G.C_PlayerInfo.ShouldDisplaySurname = function() return false end
    M.units.NPC = { name = "Solo", surname = "SomeRealm" }
    check(T .. "with surnames off the unit's second value is not part of the name", E.npcFullName() == "Solo" and E.surnamesShown() == false and E.isMine("Solo") == true)
    M.units.NPC = nil
    _G.C_PlayerInfo.ShouldDisplaySurname = function() return true end
    G.mineSet("Solo", false)
    check(T .. "the marks are gone again", ns.DB.settings.gold.mine == nil)
  end

  -- ── banks (rules 31 to 33) ────────────────────────────────────────────────────────────────────────────────────
  do
    local xi, xo, other0, gained0, spent0 = g.xferIn, g.xferOut, g.other or 0, g.gained, g.spent
    local un0 = day().unexplained or 0
    -- the guild bank: named, never a transfer
    M.interact.GuildBanker = true
    WithdrawGuildBankMoney(20000); money(20000)
    is("a guild bank withdrawal is not a transfer: income with no ledger key of its own, named", row(), "unexplained", 20000, "bank=guild")
    check(T .. "the guild bank moved no transfer key; the day row has it in unexplained", g.xferIn == xi and (day().unexplained or 0) == un0 + 20000 and g.gained == gained0 + 20000)
    check(T .. "no quest can claim the guild bank's coin later", #(E._openGain or {}) == 0 or E._openGain[#E._openGain].amount ~= 20000)
    later()
    DepositGuildBankMoney(15000); money(-15000)
    is("a guild bank deposit is not a transfer either", row(), "other", -15000, "bank=guild")
    check(T .. "it is spending, on the key it had before", g.xferOut == xo and (g.other or 0) == other0 + 15000 and g.spent == spent0 + 15000)
    later()
    -- the client says the player is not at a guild bank: the claim is not used
    M.interact.GuildBanker = nil
    WithdrawGuildBankMoney(3300); money(3300)
    is("the client says the player is not at a guild banker: as before 0.9.48", row(), "unexplained", 3300, "")
    E._bank = nil; later()
    M.interact.GuildBanker = true
    WithdrawGuildBankMoney(3300); money(3301)
    is("a purse change of another amount is not the bank's", row(), "unexplained", 3301, "")
    E._bank = nil; later()
    WithdrawGuildBankMoney(3300); later(6); money(3300)
    is("a claim older than 5 s is forgotten", row(), "unexplained", 3300, "")
    later()
    M.interact.GuildBanker = nil
    -- the account bank: off on this client, nothing is claimed
    M.interact.Banker = true
    C_Bank.DepositMoney(Enum.BankType.Account, 40000); money(-40000)
    is("the account bank is off: a deposit is booked as before 0.9.48", row(), "other", -40000, "")
    later()
    -- on: a transfer both ways
    M.accountBank = true
    C_Bank.DepositMoney(Enum.BankType.Account, 40000); money(-40000)
    is("an account bank deposit is a transfer out", row(), "xferOut", -40000, "bank=account")
    later()
    C_Bank.WithdrawMoney(Enum.BankType.Account, 10000); money(10000)
    is("an account bank withdrawal is a transfer in", row(), "xferIn", 10000, "bank=account")
    later()
    M.interact.GuildBanker = true
    C_Bank.DepositMoney(Enum.BankType.Guild, 500); money(-500)
    is("the bank type says which bank: the guild bank through C_Bank is not a transfer", row(), "other", -500, "bank=guild")
    M.interact.GuildBanker = nil
    later()
    check(T .. "the account bank moved xferIn and xferOut", g.xferIn == xi + 10000 and g.xferOut == xo + 40000)
    -- its balance is read when the bank opens, with the moment of the read
    M.bankMoney = 7770000
    M.fire("BANKFRAME_OPENED")
    check(T .. "the account bank's balance is stored on the logged-in block with its time", type(c.goldBank) == "table" and c.goldBank.balance == 7770000 and c.goldBank.at == M.epoch)
    M.bankMoney = 7780000; later(5)
    M.fire("ACCOUNT_MONEY")
    check(T .. "ACCOUNT_MONEY reads it again", c.goldBank.balance == 7780000 and c.goldBank.at == M.epoch)
    M.bankMoney = 7770000; M.fire("ACCOUNT_MONEY")
    local ro = G.roster("all")
    local sum = 0
    for _, r in ipairs(ro.rows) do if r.counted then sum = sum + r.balance end end
    check(T .. "the roster lists the account bank and counts it in the account's total", ro.bank ~= nil and ro.bank.balance == 7770000 and ro.total == sum + 7770000, ro.total - sum)
    check(T .. "a realm's total does not hold the account bank", G.roster("realm").bank ~= nil and G.roster("realm").bank.counted == nil and G.roster("realm").total < ro.total - 7000000)
    check(T .. "the roster line says the bank is in", G.rosterLine(ro):find("account bank as of", 1, true) ~= nil, G.rosterLine(ro))
    M.accountBank = nil
    check(T .. "with the account bank off no bank row is listed", G.roster("all").bank == nil and G.roster("all").total == sum)
    M.bankMoney = nil; M.interact.Banker = nil
  end

  -- ── the figures: earned, spent and net with the transfers taken out ───────────────────────────────────────────
  do
    local p = G.period("today")
    local L = p.ledger
    local earned, spent, net, moved, refund = G.netted(L)
    check(T .. "the day's raw flow still adds up: income keys sum to gained, spending keys to spent", (function()
      local a, b = 0, 0
      for _, k in ipairs(G.IN) do a = a + (L[k] or 0) end
      for _, k in ipairs(G.OUT) do b = b + (L[k] or 0) end
      return a == L.gained and b == L.spent
    end)())
    check(T .. "the lifetime ledger: balance = gained - spent + away still holds", g.balance - (g.gained - g.spent + (g.away or 0)) == 50000000, g.balance - (g.gained - g.spent + (g.away or 0)))
    check(T .. "earned is gained without transfers in and returned bids", earned == L.gained - L.xferIn - L.auctionRefund and L.xferIn == g.xferIn and L.auctionRefund == g.auctionRefund)
    check(T .. "spent is spent without transfers out", spent == L.spent - L.xferOut and L.xferOut == g.xferOut)
    check(T .. "net is the purse's change less what moved", net == (L.gained - L.spent) - (L.xferIn - L.xferOut) and moved == L.xferIn - L.xferOut and refund == L.auctionRefund)
    check(T .. "Gold.figure answers with the same figures", G.figure("earned", L) == earned and G.figure("spent", L) == spent and G.figure("net", L) == net and G.figure("moved", L) == moved)
    check(T .. "Gold.metric too, for today and for the session", G.metric("net", "char", "today") == net and G.metric("earned", "char", "session") == G.figure("earned", ses().gold))
    check(T .. "the session's net is the same definition", G.sessionNet(ses()) == G.figure("net", ses().gold) and G.summary(ses()).net == G.sessionNet(ses()) and G.summary(ses()).moved == moved)
    local d = p.days[1]
    check(T .. "a day of the Days view carries earned, spent, net and moved", d.earned == earned and d.out == spent and d.net == net and d.moved == moved)
    check(T .. "the roster's Today is the net", (function() for _, r in ipairs(G.roster("all").rows) do if r.me then return r.today == net end end end)())
    check(T .. "the strip's bar of today is the net", (function() local s = G.stripDays("char"); return s[#s] and s[#s].v == net end)())
    check(T .. "no transfer is the day's top source", (function() local k = G.topSource(d.src); return k ~= nil and not G.MOVED[k] end)())
    -- one wording on every surface
    local lines = {}
    for _, l in ipairs(G.tipLines()) do lines[#lines + 1] = (l.left or "") .. " " .. (l.right or "") end
    local movedText = G.movedText(moved, G.full)
    check(T .. "the tooltip's Today line is netted and says what moved", has(lines, "Today " .. G.full(net, { signed = true })) and has(lines, movedText) and has(lines, "bids returned " .. G.full(refund)), table.concat(lines, " | "))
    check(T .. "no transfer is in the tooltip's top sources", not has(lines, "To your characters " ) and not has(lines, "From your characters "))
    said = {}
    SlashCmdList.EVERBUFF("gold")
    check(T .. "/eb gold says the same", has(said, "today: " .. G.signed(net)) and has(said, G.movedText(moved)) and has(said, "this session: " .. G.signed(G.sessionNet(ses()))), table.concat(said, " | "))
    check(T .. "the glance values are netted, and Today says what moved", G.glance("today", true) == "Today " .. G.fmt(net, { signed = true }) .. " · " .. G.movedText(moved, G.fmt)
      and G.glance("session", true) == "Session " .. G.fmt(G.sessionNet(ses()), { signed = true }), G.glance("today", true))
    check(T .. "several counterparties today: no one is named", G.movedWhoToday() == nil and G.movedText(-1000000) == "moved " .. ns.fmtMoney(1000000) .. " out" and G.movedText(500, nil, "Mira") == "moved " .. ns.fmtMoney(500) .. " from Mira")
    check(T .. "one counterparty is named, as typed or as the client named it; the account bank by its name",
      G.movedWho({ { src = "xferOut", ref = { to = "Mira Dawnfall" } }, { src = "xferIn", ref = { sender = "mira dawnfall" } }, { src = "mail", ref = { sender = "Rando" } } }) == "Mira Dawnfall"
      and G.movedWho({ { src = "xferOut", ref = { bank = "account" } } }) == "the account bank" and G.movedWho({ { src = "xferOut", ref = { to = "A" } }, { src = "xferOut", ref = { bank = "account" } } }) == nil
      and G.movedWho({}) == nil)
    -- the sources of the period
    local sc = G.scope("today")
    local entries = G.scopeEntries(sc)
    local src = G.sources(sc, entries)
    local by, bank = {}, {}
    for _, r in ipairs(src.rows) do if r.bank then bank[r.label] = r else by[r.key] = r end end
    check(T .. "Sources: the totals are earned and spent with the transfers taken out", src.inTotal == earned and src.outTotal == spent and src.moved == moved)
    check(T .. "Sources: transfers and returned bids are rows of their own, neither in nor out", by.xferIn and by.xferIn.moved and by.xferIn.dir == 0 and by.xferIn.amount == L.xferIn
      and by.xferOut.amount == -L.xferOut and by.auctionRefund.amount == L.auctionRefund and by.xferIn.label == "From your characters" and by.xferOut.label == "To your characters" and by.auctionRefund.label == "Bids returned")
    check(T .. "Sources: gold mailed to another player is spending", by.mailSent and by.mailSent.dir == -1 and by.mailSent.amount == 150000 and by.mailSent.label == "Mail: gold sent")
    check(T .. "Sources: the guild bank is shown as a source of its own, both ways", bank["Guild bank: taken out"] and bank["Guild bank: taken out"].amount == 20000 and bank["Guild bank: taken out"].dir == 1
      and bank["Guild bank: put in"] and bank["Guild bank: put in"].amount == 15500 and bank["Guild bank: put in"].dir == -1, bank["Guild bank: put in"] and bank["Guild bank: put in"].amount)
    check(T .. "Sources: what is left in unexplained does not hold the guild bank", by.unexplained and by.unexplained.amount == (L.unexplained or 0) - 20000)
    check(T .. "Sources: the two rows of a key the guild bank has a share of say which rows a click lists", bank["Guild bank: put in"].bank == "guild" and by.other and by.other.rest == "none" and by.unexplained.rest == "none" and by.looted.rest == nil)
    check(T .. "Sources: auctions net of returned bids is a derived line of the auction and the bids rows (rule 18)", by.auctions and by.auctions.netBids == L.auctions - L.auctionRefund
      and by.auctionRefund.netBids == L.auctions - L.auctionRefund and by.looted.netBids == nil and L.auctions == g.auctions, tostring(by.auctions and by.auctions.netBids))
    -- the journal rows read as the plan words them
    local det = {}
    for _, e in ipairs(entries) do det[#det + 1] = e.detail or "" end
    check(T .. "Journal: To your character, From your character, Sent to, Postage, Bid returned, the banks",
      has(det, "To your character Mira Dawnfall") and has(det, "From your character Mira Dawnfall") and has(det, "Sent to Mira Stonefist (stranger)") and has(det, "Postage, mail to Mira Dawnfall")
      and has(det, "Bid returned: Linen Cloth") and has(det, "Guild bank: taken out") and has(det, "Guild bank: put in") and has(det, "Put into the account bank") and has(det, "Taken out of the account bank")
      and has(det, "To your character Otheracct Banker, in a trade"), table.concat(det, " | "))
    local flagged, players = 0, 0
    for _, e in ipairs(entries) do
      if e.ref.bank and e.flag then flagged = flagged + 1 end
      if e.player then players = players + 1 end
    end
    check(T .. "Journal: a bank row is not flagged unexplained; rows with a player name them", flagged == 0 and players > 5, flagged .. " " .. players)
    local offered = {}
    for _, e in ipairs(entries) do
      local r = e.ref
      local who = r.partner or r.to or r.sender
      if who then offered[(r.rel or "") .. ":" .. who:lower()] = e.player ~= nil end
    end
    check(T .. "Journal: a character of this account is not offered This is my character; an uncertain name and a stranger are",
      offered["alt:mira dawnfall"] == false and offered["alt:grok"] == false and offered["alt?:mira"] == true and offered["stranger:mira stonefist"] == true and offered["system:stormwind auction house"] == false,
      ("%s %s %s %s"):format(tostring(offered["alt:mira dawnfall"]), tostring(offered["alt:grok"]), tostring(offered["alt?:mira"]), tostring(offered["stranger:mira stonefist"])))
    check(T .. "Journal: a COD paid to an own character reads as a transfer with its COD", has(det, "To your character Grok, COD"), table.concat(det, " | "))
    -- the rate: a transfer moves no mode
    local f0, e0, n0 = G.rate("farm").sum, G.rate("earned").sum, G.rate("net").sum
    M.fire("MAIL_SHOW")
    M.inbox = { { sender = "Mira Dawnfall", subject = "gold", money = 110000 } }
    TakeInboxMoney(1); money(110000)
    SetSendMailMoney(60000); SendMail("Mira Dawnfall", "gold", ""); money(-60030)
    check(T .. "rate: a transfer in or out moves neither Farming, Earned nor Net (the postage is spent)", G.rate("farm").sum == f0 and G.rate("earned").sum == e0 and G.rate("net").sum == n0 - 30,
      ("%s %s %s"):format(G.rate("farm").sum - f0, G.rate("earned").sum - e0, G.rate("net").sum - n0))
    M.inbox = { { sender = "Stormwind Auction House", subject = "Outbid on Wool", money = 900, canReply = false } }
    TakeInboxMoney(1); money(900)
    check(T .. "rate: a returned bid is not earned, and is in Net as the purse is", G.rate("earned").sum == e0 and G.rate("net").sum == n0 - 30 + 900)
    M.inbox = {}; M.fire("MAIL_CLOSED"); M.runTimers(); later()
    -- the records are by the net
    G.bestNote()
    local _, _, netNow = G.netted(G.period("today").ledger)
    check(T .. "the best day is kept by the net, not by the raw flow", (c.goldBest == nil or c.goldBest.day == nil) == (netNow <= 0) and (netNow <= 0 or c.goldBest.day.net == netNow), netNow)
  end

  -- ── two characters: a completed transfer, and one whose sender leg is missing (rule 21) ───────────────────────
  do
    local kT = G.dayKey(GetServerTime(), base)
    local me = G.period("today", "char").ledger
    local eMe, sMe = G.netted(me)
    -- Mira received what Hart sent her today, and looted 5g of her own
    -- the legs with a second side in this save file, from the journal: not the account bank, not a trade (a marked
    -- character on another account), not mail with a marked name
    local pairedOut, pairedIn = 0, 0
    for i = 1, rows() do
      local r = row(i)
      local who = r.refT.sender or r.refT.to or ""
      if (r.src == "xferOut" or r.src == "xferIn") and not r.refT.bank and not r.refT.partner and not who:find("Otheracct", 1, true) then
        if r.src == "xferOut" then pairedOut = pairedOut - r.delta else pairedIn = pairedIn + r.delta end
      end
    end
    check(T .. "xferSolo is the signed sum of the legs with no second side here, on the ledger and on the day row",
      g.xferSolo == (me.xferIn - pairedIn) - (me.xferOut - pairedOut) and day().xferSolo == g.xferSolo and me.xferSolo == g.xferSolo and ses().gold.xferSolo == nil, tostring(g.xferSolo))
    check(T .. "one character alone: what it sent to its own less what it got from them", G.unmatched(me) == pairedOut - pairedIn and pairedOut > 0 and pairedIn > 0)
    local sentToMira = pairedOut
    chars.A.goldDays = { [kT] = { g = sentToMira + 50000, s = 0, o = 961000 - sentToMira - 50000, c = 961000, t = 600, n = 4, xferIn = sentToMira, looted = 50000 } }
    chars.A.gold.gained, chars.A.gold.xferIn, chars.A.gold.looted = sentToMira + 50000, sentToMira, 50000
    local acct = G.period("today", "account")
    local eA, sA, netA = G.netted(acct.ledger)
    check(T .. "account: earned and spent are unchanged by the transfers between its characters", eA == eMe + 50000 and sA == sMe, ("%s %s"):format(eA - eMe, sA - sMe))
    check(T .. "account: the net is each character's own net, summed", netA == G.figure("net", me) + 50000)
    -- what Hart received from Mira (the mails taken above) was never recorded on her side: her sender leg is missing
    local un = G.unmatchedText(acct.ledger)
    local diff = pairedIn
    check(T .. "a leg recorded on one side only is said, with its amount: the bank and the other account are not in it", G.unmatched(acct.ledger) == -pairedIn and un ~= nil
      and un == "Unmatched transfers: " .. ns.fmtMoney(diff) .. " (the other side was not recorded here)", tostring(un))
    check(T .. "the receiver's own figures are right without the sender's leg", G.figure("earned", chars.A.goldDays[kT] and { gained = chars.A.goldDays[kT].g, xferIn = chars.A.goldDays[kT].xferIn }) == 50000)
    -- both legs there: nothing to say
    check(T .. "legs that agree say nothing", G.unmatchedText({ xferIn = 500, xferOut = 500 }) == nil and G.unmatchedText({}) == nil)
    check(T .. "a bank deposit or a transfer to another account alone says nothing", G.unmatchedText({ xferOut = 40000, xferSolo = -40000 }) == nil and G.unmatchedText({ xferIn = 700, xferSolo = 700 }) == nil
      and G.unmatchedText({ xferOut = 40500, xferSolo = -40000 }) == "Unmatched transfers: " .. ns.fmtMoney(500) .. " (the other side was not recorded here)")
    said = {}
    SlashCmdList.EVERBUFF("gold stats")
    check(T .. "/eb gold stats says the unmatched amount for the account", has(said, "Unmatched transfers: "), table.concat(said, " | "))
    chars.A.goldDays, chars.A.gold = nil, { balance = 961000 }
  end

  -- ── the pane: the cards, the moved section, the row menu ──────────────────────────────────────────────────────
  do
    local okPane, errPane = pcall(function()
      if _G.EverbuffFrame then _G.EverbuffFrame.shown = true end
      local p = G.period("today")
      local earned, spent, net = G.netted(p.ledger)
      G.open("today", "sources"); M.settle(); ns._test.goldPane().setWho("char"); M.settle()
      local pane = ns._test.goldPane()
      check(T .. "pane: Earned, Spent and Net are netted", pane.cIn.value.text == ns.fmtMoney(earned) and pane.cOut.value.text == ns.fmtMoney(spent) and pane.cNet.value.text == G.signed(net),
        ("%s %s %s"):format(tostring(pane.cIn.value.text), tostring(pane.cOut.value.text), tostring(pane.cNet.value.text)))
      check(T .. "pane: the line under the cards says what moved, each way, and the bids returned", pane.statusText:find("Moved between your characters: " .. ns.fmtMoney(p.ledger.xferIn) .. " in, " .. ns.fmtMoney(p.ledger.xferOut) .. " out", 1, true) ~= nil
        and pane.statusText:find("Bids returned: " .. ns.fmtMoney(p.ledger.auctionRefund), 1, true) ~= nil, pane.statusText)
      local sections, movedAt, firstMoved = {}, nil, nil
      for i, r in ipairs(pane.tblSrc.rows or {}) do
        local it = r.shown ~= false and r.item or nil
        if it and it.ebSection then sections[#sections + 1] = it.ebSection; if it.ebSection == "MOVED BETWEEN YOUR CHARACTERS" then movedAt = i end
        elseif it and it.moved and not firstMoved then firstMoved = i end
      end
      check(T .. "pane: Sources has the section MOVED BETWEEN YOUR CHARACTERS, after the rest", movedAt ~= nil and firstMoved == movedAt + 1 and sections[#sections] == "MOVED BETWEEN YOUR CHARACTERS"
        and sections[1]:find("EARNED", 1, true) == 1 and sections[1]:find(ns.fmtMoney(earned), 1, true) ~= nil, table.concat(sections, " | "))
      check(T .. "pane: the audit of the day does not read broken", pane.audit == nil or pane.audit.state ~= "broken", pane.audit and (pane.audit.text or pane.audit.reason))
      check(T .. "pane: the line says the bids are in the net and not in earned, and the auctions net of them", pane.statusText:find("Bids returned: " .. ns.fmtMoney(p.ledger.auctionRefund) .. " (in the net, not in earned)", 1, true) ~= nil
        and pane.statusText:find("Auctions net of returned bids: " .. ns.fmtMoney(p.ledger.auctions - p.ledger.auctionRefund), 1, true) ~= nil, pane.statusText)
      check(T .. "pane: one character's scope has no unmatched line", pane.statusText:find("Unmatched transfers", 1, true) == nil)
      -- the tooltips of the auction house row and of the guild bank row; a click on the guild bank row lists its rows only
      local tipF = _G.GameTooltip
      local function srcRow(pred) for _, r in ipairs(pane.tblSrc.rows or {}) do if r.shown ~= false and r.item and not r.item.ebSection and pred(r.item) then return r end end end
      local ahRow, gbRow, restRow = srcRow(function(it) return it.key == "auctions" end), srcRow(function(it) return it.bank == "guild" and it.key == "other" end), srcRow(function(it) return it.key == "other" and it.rest == "none" end)
      check(T .. "pane: Sources lists the auction house, the guild bank and the rest of unexplained spending", ahRow ~= nil and gbRow ~= nil and restRow ~= nil)
      check(T .. "pane: its rows carry a tooltip and a click", ahRow ~= nil and tipF ~= nil and ahRow.scripts.OnEnter ~= nil and gbRow ~= nil and gbRow.scripts.OnClick ~= nil)
      if ahRow and gbRow and restRow and tipF and ahRow.scripts.OnEnter then
        ahRow.scripts.OnEnter(ahRow)
        check(T .. "pane: the auction house row's tooltip has the derived line", table.concat(tipF.lines or {}, " | "):find("Auctions net of returned bids: " .. ns.fmtMoney(p.ledger.auctions - p.ledger.auctionRefund), 1, true) ~= nil, table.concat(tipF.lines or {}, " | "))
        if ahRow.scripts.OnLeave then ahRow.scripts.OnLeave(ahRow) end
        local nGuild, nOther = gbRow.item.n, restRow.item.n
        gbRow.scripts.OnClick(gbRow, "LeftButton"); M.settle()
        pane = ns._test.goldPane()
        local okRows = pane.st.view == "journal" and pane.st.src == "other" and pane.st.bank == "guild" and pane.journalCount == nGuild and nGuild == 2
        for _, r in ipairs(pane.journalRows or {}) do if r.shown ~= false and r.item and not r.item.ebSection and not (r.item.src == "other" and r.item.ref.bank == "guild") then okRows = false end end
        check(T .. "pane: a click on the guild bank row lists the guild bank's rows, not every unexplained row", okRows and pane.caption.text:find("Guild bank: put in", 1, true) == 1, ("%s %s %s"):format(tostring(pane.st.bank), tostring(pane.journalCount), tostring(pane.caption.text)))
        G.filter("other", "none"); M.settle()
        pane = ns._test.goldPane()
        okRows = pane.st.bank == "none" and pane.journalCount == nOther
        for _, r in ipairs(pane.journalRows or {}) do if r.shown ~= false and r.item and not r.item.ebSection and r.item.ref.bank == "guild" then okRows = false end end
        check(T .. "pane: the other row of that key lists the rows the guild bank did not name", okRows, ("%s %s"):format(tostring(pane.journalCount), nOther))
        G.filter("looted"); M.settle()
        check(T .. "pane: another source clears the bank filter", ns._test.goldPane().st.bank == nil and ns._test.goldPane().st.src == "looted")
      end
      -- the Days view: a day with a returned bid explains itself
      G.open("today", "days"); M.settle(); ns._test.goldPane().setWho("char"); M.settle()
      pane = ns._test.goldPane()
      local dayRow
      for _, tb in ipairs({ pane.tblDays, pane.tblDaysNarrow }) do
        for _, r in ipairs(tb and tb.rows or {}) do if r.shown ~= false and r.item and r.item.today and r.scripts and r.scripts.OnEnter then dayRow = dayRow or r end end
      end
      check(T .. "pane: Days lists today", dayRow ~= nil)
      if dayRow and tipF then
        dayRow.scripts.OnEnter(dayRow)
        local text = table.concat(tipF.lines or {}, " | ")
        check(T .. "pane: the day's tooltip says the bids are in the net and not in earned, and what moved", text:find("Bids returned " .. ns.fmtMoney(p.ledger.auctionRefund) .. " (in the net, not in earned)", 1, true) ~= nil
          and text:find("Auctions net of returned bids: ", 1, true) ~= nil and text:find("Moved between your characters " .. G.signed(G.figure("moved", p.ledger)), 1, true) ~= nil, text)
        if dayRow.scripts.OnLeave then dayRow.scripts.OnLeave(dayRow) end
      end
      -- the row menu of a journal row with a player
      G.open("today", "journal"); M.settle(); ns._test.goldPane().setWho("char"); M.settle()
      pane = ns._test.goldPane()
      local jr
      for _, r in ipairs(pane.journalRows or {}) do if r.item and r.item.src == "mailSent" and r.item.player == "Mira Stonefist" then jr = r end end
      check(T .. "pane: the journal lists the row of the gold sent to a stranger", jr ~= nil, ("%d rows, view %s, scope %s, who %s, n %s"):format(#(pane.journalRows or {}), tostring(pane.st.view), tostring(pane.st.scope), tostring(pane.st.who), tostring(pane.journalCount)))
      if jr then
        jr.scripts.OnClick(jr, "LeftButton")
        local b = pane.menu.btns[1]
        check(T .. "pane: its menu offers This is my character", pane.menu.shown ~= false and b and b.text.text == "This is my character", b and b.text.text)
        b.scripts.OnClick(b, "LeftButton")
        check(T .. "pane: the pick marks the name", G.isMine("Mira Stonefist") and #G.mineList() == 1)
        check(T .. "pane: rows already written keep their source", row(1) ~= nil and (function()
          for i = 1, rows() do local r = row(i); if r.refT.to == "Mira Stonefist" and r.src ~= "mailSent" and r.src ~= "mailSpent" then return false end end
          return true
        end)())
        G.open("today", "journal"); M.settle(); ns._test.goldPane().setWho("char"); M.settle()
        pane = ns._test.goldPane()
        for _, r in ipairs(pane.journalRows or {}) do if r.item and r.item.src == "mailSent" and r.item.player == "Mira Stonefist" then jr = r end end
        jr.scripts.OnClick(jr, "LeftButton")
        b = pane.menu.btns[1]
        check(T .. "pane: a marked name is offered Not my character", b and b.text.text == "Not my character", b and b.text.text)
        b.scripts.OnClick(b, "LeftButton")
        check(T .. "pane: and the mark is gone again", not G.isMine("Mira Stonefist") and ns.DB.settings.gold.mine == nil)
      end
      -- every view renders with the new rows
      for _, v in ipairs(G.VIEWS) do
        for _, who in ipairs({ "char", "account" }) do
          G.open("all", v[1]); M.settle()
          local pc = ns._test.goldPane()
          if pc and pc.setWho then pc.setWho(who); M.settle() end
        end
      end
      check(T .. "pane: All time says since when transfers are apart", (function()
        G.open("all", "sources"); M.settle()
        ns._test.goldPane().setWho("char"); M.settle()
        return ns._test.goldPane().statusText:find("Transfers separated since " .. G.fmtDate(g.since), 1, true) ~= nil
      end)(), ns._test.goldPane().statusText)
      if ns.UI.Close then pcall(ns.UI.Close) end
      if _G.EverbuffFrame and _G.EverbuffFrame.Hide then pcall(_G.EverbuffFrame.Hide, _G.EverbuffFrame) end
      if _G.EverbuffFrame then _G.EverbuffFrame.shown = false end
    end)
    check(T .. "pane: every view renders with transfers, refunds and bank rows", okPane and #ns.UI.paneErrors() == 0, tostring(errPane) .. " " .. table.concat(ns.UI.paneErrors(), " || "))
  end

  -- ── every identity still holds ────────────────────────────────────────────────────────────────────────────────
  do
    local s = ses()
    local okc, at = chain(s)
    check(T .. "the balance chain holds over the whole session", okc, at)
    local sums = {}
    for i = 1, #s.goldLog do local r = row(i, s); sums[r.src] = (sums[r.src] or 0) + r.delta end
    local bad = {}
    local known = 0
    for _, k in ipairs(G.IN) do if k ~= "unexplained" then known = known + (s.gold[k] or 0) end end
    for k, sign in pairs(E.GOLD_SIGN) do
      local want = k == "unexplained" and (s.gold.gained - known) or (s.gold[k] or 0) * sign
      if (sums[k] or 0) ~= want then bad[#bad + 1] = ("%s %s~=%s"):format(k, tostring(sums[k]), tostring(want)) end
    end
    check(T .. "the journal's rows of each source sum to the session's ledger, the four new keys too", #bad == 0, table.concat(bad, ", "))
    local r = day()
    local inc, out = 0, 0
    for _, k in ipairs(G.IN) do inc = inc + (r[k] or 0) end
    for _, k in ipairs(G.OUT) do out = out + (r[k] or 0) end
    check(T .. "the day row: income keys sum to g, spending keys to s, c - o = g - s + away", inc == r.g and out == r.s and r.c - r.o == r.g - r.s + (r.away or 0), ("%s %s"):format(inc - r.g, out - r.s))
    local a = G.audit("today")
    check(T .. "the audit of the day reconciles", a.state == "ok", tostring(a.text or a.reason))
    a = G.audit("session")
    check(T .. "the audit of the session reconciles", a.state == "ok", tostring(a.text or a.reason))
    check(T .. "no writer failed and no handler threw", E._dayErr == nil and G._rateErr == nil and G._placeErr == nil and #M.errors == errs0, tostring(E._dayErr or G._rateErr or G._placeErr or M.errors[#M.errors]))
    local dash = false
    for _, e in ipairs(G.scopeEntries(G.scope("today"))) do if (e.detail or ""):find("\226\128\148", 1, true) then dash = true end end
    for _, k in ipairs({ "xferIn", "xferOut", "mailSent", "auctionRefund" }) do
      if (G.LABEL[k] .. G.WORD[k] .. G.SHORT[k]):find("\226\128\148", 1, true) then dash = true end
    end
    check(T .. "copy: no em dash in the new rows and labels", not dash)
  end

  -- ── a session from before the update: everything is booked and shown as before (rule 36) ──────────────────────
  do
    M.fire("PLAYER_LOGOUT"); later(60)
    ns._test.newLoad(); login(); later()
    local s = ses()
    s.goldV = nil   -- as a session started on 0.9.47 and resumed by a /reload into 0.9.48 has it
    for _, k in ipairs({ "xferIn", "xferOut", "mailSent", "auctionRefund" }) do s.gold[k] = nil end
    local xi, xo, mail0, post0 = g.xferIn, g.xferOut, g.mail or 0, g.mailSpent or 0
    M.fire("MAIL_SHOW")
    M.inbox = { { sender = "Mira Dawnfall", subject = "gold", money = 33000 },
      { sender = "Stormwind Auction House", subject = "Outbid on Linen Cloth", money = 4400, canReply = false } }
    TakeInboxMoney(1); money(33000)
    is("pre-upgrade session: mail from an own character is mail, tagged alt", row(), "mail", 33000, "sender=Mira Dawnfall;rel=alt;cod=0")
    TakeInboxMoney(2); money(4400)
    is("pre-upgrade session: a returned bid is mail", row(), "mail", 4400, "sender=Stormwind Auction House;rel=system;cod=0")
    SetSendMailMoney(21000); SendMail("Mira Dawnfall", "gold", ""); money(-21030)
    is("pre-upgrade session: gold sent is one mailSpent row", row(), "mailSpent", -21030, "")
    M.inbox = {}; M.fire("MAIL_CLOSED"); M.runTimers()
    M.accountBank = true; M.interact.Banker = true
    C_Bank.DepositMoney(Enum.BankType.Account, 900); money(-900)
    is("pre-upgrade session: an account bank deposit is named and stays on its old key", row(), "other", -900, "bank=account")
    M.accountBank, M.interact.Banker = nil, nil
    check(T .. "pre-upgrade session: no transfer key moved, in the session or the lifetime ledger", g.xferIn == xi and g.xferOut == xo and s.gold.xferIn == nil and s.gold.xferOut == nil and s.gold.mailSent == nil
      and (g.mail or 0) == mail0 + 37400 and (g.mailSpent or 0) == post0 + 21030)
    local sc = G.scope("session")
    local earned, spent, net = G.netted(sc.ledger)
    check(T .. "pre-upgrade session: its figures are the raw flow, and the scope says so", sc.raw == true and earned == sc.ledger.gained and spent == sc.ledger.spent and net == sc.ledger.gained - sc.ledger.spent
      and earned == 37400 and spent == 21930, ("%s %s"):format(earned, spent))
    local okPane, errPane = pcall(function()
      if _G.EverbuffFrame then _G.EverbuffFrame.shown = true end
      G.open("session", "sources"); M.settle(); ns._test.goldPane().setWho("char"); M.settle()
      local pane = ns._test.goldPane()
      check(T .. "pre-upgrade session: the pane shows raw In and Out with a note", pane.cIn.value.text == ns.fmtMoney(37400) and pane.cOut.value.text == ns.fmtMoney(21930)
        and pane.statusText:find("Began before addon 0.9.48: transfers not separated", 1, true) ~= nil
        and pane.statusText:find("Mail with your characters, not separated: " .. ns.fmtMoney(33000) .. " in", 1, true) ~= nil, pane.statusText)
      if ns.UI.Close then pcall(ns.UI.Close) end
      if _G.EverbuffFrame and _G.EverbuffFrame.Hide then pcall(_G.EverbuffFrame.Hide, _G.EverbuffFrame) end
      if _G.EverbuffFrame then _G.EverbuffFrame.shown = false end
    end)
    check(T .. "pre-upgrade session: the pane renders", okPane, errPane)
    local a = G.audit("session")
    check(T .. "pre-upgrade session: it reconciles", a.state == "ok", tostring(a.text or a.reason))
    -- the next session, started on this version, books transfers apart again
    M.fire("PLAYER_LOGOUT"); later(60)
    ns._test.newLoad(); login(); later()
    check(T .. "the next login starts a session with goldV = 2", ses() ~= s and ses().goldV == 2)
    M.fire("MAIL_SHOW")
    M.inbox = { { sender = "Mira Dawnfall", subject = "gold", money = 1200 } }
    TakeInboxMoney(1); money(1200)
    is("and mail from an own character is a transfer again", row(), "xferIn", 1200, "sender=Mira Dawnfall;rel=alt;cod=0")
    M.inbox = {}; M.fire("MAIL_CLOSED"); M.runTimers()
    check(T .. "only the logged-in character's block was written", chars.A.goldDays == nil and chars.B.goldDays == nil and chars.A.goldBids == nil and chars.B.goldBank == nil and chars.A.gold.xferIn == nil)
    check(T .. "no handler threw", #M.errors == errs0, M.errors[#M.errors])
  end

  -- ── a save file of its own: the account bank alone leaves no unmatched line (rule 21) ─────────────────────────
  do
    M.fire("PLAYER_LOGOUT")
    fresh()
    M.money = 900000
    login(); later()
    local c2 = ns.DB.characters[ME]
    ns.DB.characters.B = { name = "Grok", realm = REALM, class = "SHAMAN", faction = "Horde", level = 40, seen = M.epoch - DAY, gold = { balance = 250000 } }
    E.loadAlts()
    M.accountBank, M.interact.Banker = true, true
    C_Bank.DepositMoney(Enum.BankType.Account, 40000); money(-40000)
    is("a session with one account bank deposit: a transfer out", row(), "xferOut", -40000, "bank=account")
    local k2 = G.dayKey(GetServerTime(), G.baseStored())
    check(T .. "its leg is noted as one with no second side", c2.gold.xferSolo == -40000 and c2.goldDays[k2].xferSolo == -40000 and ses().gold.xferSolo == nil)
    check(T .. "the account shows no unmatched line for it, today and all time", G.unmatchedText(G.period("today", "account").ledger) == nil and G.unmatchedText(G.scope("all", "account").ledger) == nil
      and G.unmatchedText(G.period("month", "realm").ledger) == nil)
    check(T .. "the glance says where it went", G.glance("today", true) == "Today " .. G.fmt(0, { signed = true }) .. " · moved " .. G.fmt(40000) .. " to the account bank", G.glance("today", true))
    said = {}
    SlashCmdList.EVERBUFF("gold")
    check(T .. "/eb gold names the one counterparty too", has(said, "moved " .. ns.fmtMoney(40000) .. " to the account bank"), table.concat(said, " | "))
    said = {}
    SlashCmdList.EVERBUFF("gold stats")
    check(T .. "/eb gold stats has no unmatched line", not has(said, "Unmatched transfers"), table.concat(said, " | "))
    local okPane, errPane = pcall(function()
      if _G.EverbuffFrame then _G.EverbuffFrame.shown = true end
      G.open("today", "sources"); M.settle(); ns._test.goldPane().setWho("account"); M.settle()
      local pane = ns._test.goldPane()
      check(T .. "pane: the account's status has no unmatched line for a bank deposit", pane.statusText:find("Unmatched transfers", 1, true) == nil and pane.statusText:find("Moved between your characters: " .. ns.fmtMoney(40000) .. " out", 1, true) ~= nil, pane.statusText)
      -- a mail to an own character not taken yet: the line is there, a plain line after what the sums leave out
      M.fire("MAIL_SHOW")
      SetSendMailMoney(5000); SendMail("Grok", "gold", ""); money(-5030)
      M.fire("MAIL_CLOSED"); M.runTimers()
      G.open("today", "sources"); M.settle(); ns._test.goldPane().setWho("account"); M.settle()
      pane = ns._test.goldPane()
      local at = pane.statusText:find("Unmatched transfers: " .. ns.fmtMoney(5000) .. " (the other side was not recorded here)", 1, true)
      check(T .. "pane: a leg whose other side is missing is said on the account's status, not first", at ~= nil and at > 1, pane.statusText)
      if ns.UI.Close then pcall(ns.UI.Close) end
      if _G.EverbuffFrame and _G.EverbuffFrame.Hide then pcall(_G.EverbuffFrame.Hide, _G.EverbuffFrame) end
      if _G.EverbuffFrame then _G.EverbuffFrame.shown = false end
    end)
    check(T .. "pane: the account scope renders with one-sided legs", okPane, errPane)
    check(T .. "the mail to the own character is not a solo leg", c2.gold.xferSolo == -40000 and c2.gold.xferOut == 45000)
    C_Bank.WithdrawMoney(Enum.BankType.Account, 40000); money(40000)
    check(T .. "taken out again the note is gone, no key left at 0", c2.gold.xferSolo == nil and c2.goldDays[k2].xferSolo == nil and G.unmatched(G.period("today", "account").ledger) == 5000)
    check(T .. "no handler threw", #M.errors == errs0, M.errors[#M.errors])
    M.accountBank, M.interact.Banker = nil, nil
  end

  -- ── the suite's save file and client back in place ──────────────────────────────────────────────────────────
  _G.GetRealmName, _G.UnitName, _G.UnitNameUnmodified, _G.C_PlayerInfo = real.realm, real.unitName, real.unmod, real.playerInfo
  _G.AUCTION_OUTBID_MAIL_SUBJECT = real.outbid
  if _G.EverbuffFrame then _G.EverbuffFrame.shown = real.frameShown end
  M.inbox, M.interact, M.friends, M.guild, M.accountBank, M.bankMoney, M.sendPrice = main.inbox, main.interact, main.friends, main.guild, nil, nil, nil
  ns.Recorder.discard()
  ns.DB = main.db
  G._held, G._baseWait, G._flushTimer, G._tickAt = nil, nil, nil, nil
  E._openGain, E._questMoney = nil, nil
  M.timers = {}
  M.epoch, M.now, M.money = main.epoch, M.now + 100, main.money
  ns._test.newLoad()
  M.fire("PLAYER_ENTERING_WORLD", false, true); M.runTimers()
  print = realPrint
  check(T .. "the suite's save file is back, its session resumed", ns.DB == main.db and ns.Recorder.current() ~= nil and ns.DB.characters[ME].gold.balance == main.money)
end
