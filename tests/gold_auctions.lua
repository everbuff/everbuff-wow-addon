-- The auction house in Loot > Gold (docs/UX_PRAGMATIC.md 4.2). Loaded by tests/run_tests.lua after the gold suites:
--   dofile("tests/gold_auctions.lua")({ check = check, M = M, ns = ns })
-- The fixtures mirror the shapes of a real save (the founder's of 21 Nov 2026): a commodity purchase with its price
-- and the delivery mails that follow it, deliveries with no purchase stored, commodity sale invoices whose `buyout`
-- slot is the quantity, C_AuctionHouse.PlaceBid rows that have no item at bid time, and postings a few seconds apart.
--   rows      one purchase is one row: its delivery mails are taken up by it; a delivery with no purchase is "Won"
--             with no price; a sale's price is what the buyer paid and its count the posting's; a bid named by the
--             old "newest row without a name" rule shows no item
--   capture   Market.mailItem names a bid by the invoice's amount only, counts commodity deliveries on the priced
--             row, and never renames a row
--   journal   an auction row of the journal is joined to its purchase by the exact price, and to a posting only
--             when nothing else could be meant
--   answer    Spent, Received and Net are the ledger's and add up
-- The suite's loot.ah, sessions and clock are put back at the end.
return function(P)
  local check, M, ns = P.check, P.M, P.ns
  local Market, Gold = ns.Market, ns.Gold
  local GP = Gold.GP
  local function eq(name, got, want) check(name, got == want, ("got %s, want %s"):format(tostring(got), tostring(want))) end

  local keep = { ah = ns.DB.loot.ah, epoch = M.epoch, current = ns.Recorder.current }
  local guid = ns.charGuid()
  local T = 1795258000
  local SID = "t-auctions-1"
  local sess = { id = SID, guid = guid, startedEpoch = T, startedMono = 1000, endedEpoch = T + 3600, gained = 0, spent = 0, gold = {}, goldLog = {} }
  ns.DB.sessions[SID] = sess
  local function ahRows(t) ns.DB.loot.ah = { posted = t.posted or {}, bought = t.bought or {}, sold = t.sold or {}, returned = t.returned or {} } end
  local function find(rows, what, item) local out = {}; for _, r in ipairs(rows) do if r.what == what and (item == nil or r.item == item) then out[#out + 1] = r end end return out end

  -- ── rows: one purchase is one row ───────────────────────────────────────────────────────────────────────────
  ahRows({
    bought = {
      -- a commodity purchase of 120 and the six mails that deliver it
      { s = SID, t = T + 10, item = "Mageweave Cloth", id = 4338, icon = 1, count = 120, price = 53300, unit = 444, kind = "commodity" },
      { s = SID, t = T + 20, item = "Mageweave Cloth", id = 4338, count = 20, kind = "mail" },
      { s = SID, t = T + 20, item = "Mageweave Cloth", id = 4338, count = 20, kind = "mail" },
      { s = SID, t = T + 21, item = "Mageweave Cloth", id = 4338, count = 20, kind = "mail" },
      { s = SID, t = T + 21, item = "Mageweave Cloth", id = 4338, count = 20, kind = "mail" },
      { s = SID, t = T + 22, item = "Mageweave Cloth", id = 4338, count = 20, kind = "mail" },
      { s = SID, t = T + 22, item = "Mageweave Cloth", id = 4338, count = 20, kind = "mail", seller = "Neti One" },
      -- four purchases of one item at almost one price, then their four mails
      { s = SID, t = T + 100, item = "Golden Sansam", id = 13464, count = 20, price = 22780, unit = 1139, kind = "commodity" },
      { s = SID, t = T + 106, item = "Golden Sansam", id = 13464, count = 20, price = 22780, unit = 1139, kind = "commodity" },
      { s = SID, t = T + 111, item = "Golden Sansam", id = 13464, count = 20, price = 22763, unit = 1138, kind = "commodity" },
      { s = SID, t = T + 134, item = "Golden Sansam", id = 13464, count = 20, kind = "mail" },
      { s = SID, t = T + 134, item = "Golden Sansam", id = 13464, count = 20, kind = "mail" },
      { s = SID, t = T + 135, item = "Golden Sansam", id = 13464, count = 20, kind = "mail" },
      -- one more mail of the same item than was bought: its purchase is not stored
      { s = SID, t = T + 136, item = "Golden Sansam", id = 13464, count = 20, kind = "mail" },
      -- deliveries with no purchase stored at all
      { s = SID, t = T + 200, item = "Wool Cloth", id = 2592, count = 20, kind = "mail" },
      -- a purchase delivered more than an hour later is not this mail's
      { s = SID, t = T + 300, item = "Black Lotus", id = 13468, count = 3, price = 281985, unit = 93995, kind = "commodity" },
      { s = SID, t = T + 300 + 3601, item = "Black Lotus", id = 13468, count = 3, kind = "mail", seller = "Acornelius Thost" },
      -- PlaceBid rows: one named by the old rule (a guess), one named by its invoice, one never named
      { s = SID, t = T + 400, auctionId = 71, price = 16046, count = 1, kind = "item", item = "Silk Cloth", id = 4306 },
      { s = SID, t = T + 401, auctionId = 72, price = 16499, count = 1, kind = "item", item = "Red Mageweave Bag", id = 10051, named = "invoice", seller = "Bagmaker" },
      { s = SID, t = T + 402, auctionId = 73, price = 16047, count = 1, kind = "item" },
    },
    posted = {
      { s = SID, t = T + 500, item = "Stag Meat", id = 5471, count = 7, unit = 149, buyout = 1043, hours = 24, kind = "commodity" },
      { s = SID, t = T + 504, item = "Golden Sansam", id = 13464, count = 1, unit = 1211, buyout = 1211, hours = 24, kind = "commodity" },
      { s = SID, t = T + 600, item = "Formula: Enchant Boots - Greater Stamina", id = 16215, count = 1, buyout = 29000, hours = 48, kind = "item" },
    },
    sold = {
      -- a commodity invoice: `buyout` is the quantity, `net` the mail money (bid + deposit - cut)
      { s = SID, t = T + 700, item = "Stag Meat", bid = 1043, buyout = 7, cut = 52, deposit = 156, net = 1147 },
      { s = SID, t = T + 701, item = "Golden Sansam", bid = 1211, buyout = 1, cut = 60, deposit = 20, net = 1171 },
      { s = SID, t = T + 702, item = "Formula: Enchant Boots - Greater Stamina", buyer = "", bid = 29000, buyout = 29000, cut = 1450, deposit = 600, net = 28150 },
      -- a sale whose posting is not stored
      { s = SID, t = T + 703, item = "Red Wolf Meat", bid = 759, buyout = 3, cut = 37, deposit = 52, net = 774 },
    },
    returned = { { s = SID, t = T + 800, item = "Anti-Venom", id = 6452, count = 3, reason = "expired" } },
  })
  do
    local rows, sum = Market.buildAuctions()
    local mine = {}
    for _, r in ipairs(rows) do if r.s == SID then mine[#mine + 1] = r end end
    local mage = find(mine, "Bought", "Mageweave Cloth")
    check("auctions: a purchase of 120 and its six delivery mails are one Bought row with the price", #mage == 1 and mage[1].price == 53300 and mage[1].count == 120, #mage)
    eq("auctions: the delivery mail gives the seller to its purchase", mage[1].note, "Neti One")
    check("auctions: no delivery of it is listed", #find(mine, "Won", "Mageweave Cloth") == 0)
    local gs = find(mine, "Bought", "Golden Sansam")
    check("auctions: three purchases of one item stay three rows, each with its own price", #gs == 3 and gs[1].price + gs[2].price + gs[3].price == 22780 + 22780 + 22763, #gs)
    local won = find(mine, "Won")
    local names = {}
    for _, r in ipairs(won) do names[#names + 1] = r.item end
    table.sort(names)
    eq("auctions: a delivery with no purchase to take it up is Won: the fourth Sansam, the Wool Cloth, the late Black Lotus", table.concat(names, ","), "Black Lotus,Golden Sansam,Wool Cloth")
    local priced = true
    for _, r in ipairs(won) do if r.price ~= nil then priced = false end end
    check("auctions: a Won row has no price", priced)
    local lotus = find(mine, "Bought", "Black Lotus")
    check("auctions: a mail more than an hour after the purchase is not taken up by it", #lotus == 1 and lotus[1].price == 281985 and lotus[1].note == "")
    -- the bids
    local unnamed, bag = {}, nil
    for _, r in ipairs(find(mine, "Bought")) do
      if r.price == 16046 or r.price == 16047 then unnamed[#unnamed + 1] = r end
      if r.price == 16499 then bag = r end
    end
    check("auctions: a bid named by the old rule shows no item (a guess is not a fact); its price stays", #unnamed == 2 and unnamed[1].item == nil and unnamed[2].item == nil and (unnamed[1].guessed or unnamed[2].guessed) == true)
    check("auctions: a bid named by its invoice shows the item and the seller", bag and bag.item == "Red Mageweave Bag" and bag.note == "Bagmaker" and not bag.guessed)
    check("auctions: Market.guessed tells the three apart", Market.guessed(ns.DB.loot.ah.bought[18]) == true and Market.guessed(ns.DB.loot.ah.bought[19]) == false and Market.guessed(ns.DB.loot.ah.bought[20]) == false)
    -- sales
    local stag, sansam, boots, wolf = find(mine, "Sold", "Stag Meat")[1], find(mine, "Sold", "Golden Sansam")[1], find(mine, "Sold", "Formula: Enchant Boots - Greater Stamina")[1], find(mine, "Sold", "Red Wolf Meat")[1]
    check("auctions: a sale's price is what the buyer paid, never the mail money", stag.price == 1043 and stag.net == 1147 and boots.price == 29000 and boots.net == 28150, stag.price)
    check("auctions: a sale's count is its posting's (same item, buyout == bid)", stag.count == 7 and sansam.count == 1 and boots.count == 1, stag.count)
    check("auctions: a sale with no posting stored has no count, never the invoice's slot", wolf.count == nil and wolf.price == 759)
    check("auctions: cut and deposit ride along for the tooltip", stag.cut == 52 and stag.deposit == 156)
    -- the sums: purchases with a price only
    local n, spent = 0, 0
    for _, r in ipairs(find(mine, "Bought")) do n = n + 1; spent = spent + (r.price or 0) end
    check("auctions: the purchases are the priced rows", n == 8 and spent == 53300 + 22780 + 22780 + 22763 + 281985 + 16046 + 16499 + 16047, n .. " " .. spent)
    check("auctions: the sum counts purchases and deliveries apart", sum.bought >= 8 and sum.won >= 3)
    -- newest first
    local sorted = true
    for i = 2, #rows do if (rows[i].t or 0) > (rows[i - 1].t or 0) then sorted = false end end
    check("auctions: newest first", sorted)
  end

  -- ── the period sums and the answer ─────────────────────────────────────────────────────────────────────────
  do
    local sc = { sessions = { sess }, ledger = { auctions = 453000, auctionSales = 31242 } }
    local list, sum = GP.auctions(sc)
    check("auctions of a session: its rows only", #list > 0 and (function() for _, r in ipairs(list) do if r.s ~= SID then return false end end return true end)())
    check("auctions of a session: sold 4, what the buyers paid, the cut, the deposits, the mail money", sum.sold == 4 and sum.sales == 1043 + 1211 + 29000 + 759 and sum.cut == 52 + 60 + 1450 + 37
      and sum.deposit == 156 + 20 + 600 + 52 and sum.mail == 1147 + 1171 + 28150 + 774, sum.sales)
    eq("auctions of a session: the mail money is sales minus cut plus deposits", sum.mail, sum.sales - sum.cut + sum.deposit)
    check("auctions of a session: bought 8, won 3, posted 3, expired 1", sum.bought == 8 and sum.won == 3 and sum.posted == 3 and sum.expired == 1, ("%d %d %d %d"):format(sum.bought, sum.won, sum.posted, sum.expired))
    local a = GP.auctionAnswer(sc.ledger)
    check("answer: Spent and Received are the ledger's, Net is Received minus Spent", a.spent == 453000 and a.received == 31242 and a.net == 31242 - 453000)
    local plain = table.concat(a.segs, " | "):gsub("|T.-|t", ""):gsub("%*%*", ""):gsub("\194\160", " "):gsub("%s+", " ")
    check("answer: the line reads Spent, Received, Net; no Profit", plain:find("^Spent 45 30 | Received 3 12 | Net %-42 17") ~= nil and #a.segs == 3 and not plain:find("Profit", 1, true), plain)
    check("answer: nothing moved at the auction house, no line", GP.auctionAnswer({ auctions = 0, auctionSales = 0 }) == nil and GP.auctionAnswer({}) == nil)
    -- (the founder's save, today: 309,865 spent, 59,773 received)
    local real = GP.auctionAnswer({ auctions = 309865, auctionSales = 59773 })
    eq("answer: 309,865 spent and 59,773 received is a net of -250,092", real.net, -250092)
  end

  -- ── capture: a won mail and the purchase it belongs to ─────────────────────────────────────────────────────
  do
    ns.Recorder.current = function() return sess end
    local active = ns.DB.active
    ns.DB.active = SID
    M.epoch = T + 1000
    ahRows({})
    local list = ns.DB.loot.ah.bought
    -- a commodity purchase, then its deliveries: counted on the priced row, no row added
    Market.bought({ item = "Mageweave Cloth", id = 4338, count = 60, price = 26650, unit = 444, kind = "commodity" })
    M.epoch = M.epoch + 9
    Market.mailItem("Auction won", "Mageweave Cloth", 4338, 20, { seller = "Neti One", bid = 8883 })
    Market.mailItem("Auction won", "Mageweave Cloth", 4338, 20, { bid = 8883 })
    Market.mailItem("Auction won", "Mageweave Cloth", 4338, 20, { bid = 8884 })
    check("capture: three deliveries of a commodity purchase add no row and are counted on it", #list == 1 and list[1].delivered == 60 and list[1].seller == "Neti One" and list[1].price == 26650, #list)
    Market.mailItem("Auction won", "Mageweave Cloth", 4338, 20, { bid = 8883 })
    check("capture: a delivery beyond what was bought is a row of its own, with no price", #list == 2 and list[2].kind == "mail" and list[2].price == nil and list[2].count == 20)
    -- two bids with no item, different prices: each is named by the mail whose invoice names its price
    M.epoch = M.epoch + 10
    Market.bought({ auctionId = 501, price = 16046, count = 1, kind = "item" })
    Market.bought({ auctionId = 502, price = 16499, count = 1, kind = "item" })
    M.epoch = M.epoch + 5
    Market.mailItem("Auction won", "Red Mageweave Bag", 10051, 1, { seller = "Bagmaker", bid = 16499 })
    check("capture: the invoice of 1g 64s 99c names the bid of that price, not the newest or the oldest", list[4].item == "Red Mageweave Bag" and list[4].named == "invoice" and list[4].seller == "Bagmaker" and list[3].item == nil,
      tostring(list[3].item) .. " / " .. tostring(list[4].item))
    Market.mailItem("Auction won", "Silk Cloth", 4306, 13, { bid = 16046 })
    check("capture: the other mail names the other bid, with the stack the mail held", list[3].item == "Silk Cloth" and list[3].count == 13 and list[3].named == "invoice" and #list == 4)
    -- a mail whose invoice names an amount no bid has, or no amount: its own row, the bid keeps no name
    Market.bought({ auctionId = 503, price = 777, count = 1, kind = "item" })
    Market.mailItem("Auction won", "Wool Cloth", 2592, 20, { bid = 778 })
    Market.mailItem("Auction won", "Linen Cloth", 2589, 20, {})
    check("capture: a mail that fits no bid by its amount is its own row; the bid stays unnamed", list[5].item == nil and list[6].kind == "mail" and list[6].item == "Wool Cloth" and list[7].kind == "mail" and list[7].item == "Linen Cloth" and #list == 7)
    -- a named row is never renamed
    Market.mailItem("Auction won", "Something Else", 9999, 1, { bid = 16499 })
    check("capture: a bid that has its item is never renamed", list[4].item == "Red Mageweave Bag" and #list == 8 and list[8].kind == "mail")
    -- another character's purchase of the same item is not this mail's
    ns.DB.sessions["t-auctions-other"] = { id = "t-auctions-other", guid = "Player-9-0000FFFF", startedEpoch = T, endedEpoch = T + 10 }
    list[#list + 1] = { s = "t-auctions-other", t = M.epoch, item = "Iron Bar", id = 3575, count = 20, price = 4000, kind = "commodity" }
    Market.mailItem("Auction won", "Iron Bar", 3575, 20, {})
    check("capture: a purchase of another character takes no mail of this one", list[9].delivered == nil and list[10].kind == "mail" and list[10].item == "Iron Bar")
    ns.DB.sessions["t-auctions-other"] = nil
    -- the rows these captures give the pane
    local rows = Market.buildAuctions()
    local won, bought = 0, 0
    for _, r in ipairs(rows) do if r.s == SID then if r.what == "Won" then won = won + 1 elseif r.what == "Bought" then bought = bought + 1 end end end
    check("capture: the pane then lists 4 purchases and 5 deliveries with no purchase", bought == 4 and won == 5, bought .. " " .. won)
    ns.DB.active = active
  end

  -- ── journal: the item behind an auction row ────────────────────────────────────────────────────────────────
  do
    ahRows({
      bought = {
        { s = SID, t = T + 90, item = "Black Lotus", id = 13468, count = 3, price = 281985, unit = 93995, kind = "commodity" },
        { s = SID, t = T + 99, item = "Black Lotus", id = 13468, count = 3, kind = "mail", seller = "Acornelius Thost" },
        { s = SID, t = T + 143, item = "Golden Sansam", id = 13464, count = 20, price = 27880, unit = 1394, kind = "commodity" },
        -- two purchases of one item at one price within seconds: either row is the same fact
        { s = SID, t = T + 200, item = "Golden Sansam", id = 13464, count = 20, price = 22780, kind = "commodity" },
        { s = SID, t = T + 203, item = "Golden Sansam", id = 13464, count = 20, price = 22780, kind = "commodity" },
        -- two different items at one price within seconds: the price cannot say which
        { s = SID, t = T + 300, item = "Silk Cloth", id = 4306, count = 20, price = 3900, kind = "commodity" },
        { s = SID, t = T + 302, item = "Wool Cloth", id = 2592, count = 20, price = 3900, kind = "commodity" },
        -- a guessed name is not used
        { s = SID, t = T + 400, auctionId = 71, price = 16046, count = 1, kind = "item", item = "Silk Cloth", id = 4306 },
      },
      posted = {
        -- one posting alone, and two 4 s apart (the founder's save, 20 Nov 23:14: deposits 15s and 6s)
        { s = SID, t = T + 500, item = "Ironweb Spider Silk", id = 14227, count = 3, buyout = 16500, hours = 24, kind = "commodity" },
        { s = SID, t = T + 600, item = "Formula: Enchant Bracer - Superior Stamina", id = 16251, count = 1, buyout = 9077, hours = 24, kind = "item" },
        { s = SID, t = T + 604, item = "Formula: Enchant Boots - Greater Stamina", id = 16215, count = 1, buyout = 29000, hours = 24, kind = "item" },
      },
    })
    local bal = 1000000
    local function jr(at, delta, kind) bal = bal + delta; return ("%.1f\t%d\tauctions\t%d\t%s"):format(1000 + at, delta, bal, kind and ("kind=" .. kind) or "") end
    sess.goldLog = {
      jr(90, -281985, "buyout"), jr(143, -27880, "buyout"),
      jr(200, -22780, "buyout"), jr(203, -22780, "buyout"),
      jr(300, -3900, "buyout"), jr(302, -3900, "buyout"),
      jr(400, -16046, "bid"),
      jr(501, -1500, "deposit"),
      jr(601, -1500, "deposit"), jr(605, -600, "deposit"),
      jr(900, -5000, "buyout"),
      jr(950, -45, "deposit"),
    }
    sess.gold = { auctions = 281985 + 27880 + 22780 * 2 + 3900 * 2 + 16046 + 1500 + 1500 + 600 + 5000 + 45 }
    sess.spent = sess.gold.auctions
    local e = Gold.entries(sess)
    eq("journal: one entry per row", #e, 12)
    eq("journal: a purchase names its item and count", e[1].detail, "Bought Black Lotus x3")
    eq("journal: the next one too", e[2].detail, "Bought Golden Sansam x20")
    check("journal: two purchases of one item at one price are both named", e[3].detail == "Bought Golden Sansam x20" and e[4].detail == "Bought Golden Sansam x20" and e[3].ah ~= e[4].ah)
    check("journal: two different items at one price within seconds are not named by the price", e[5].detail == "Buyout" and e[6].detail == "Buyout", e[5].detail)
    eq("journal: a bid whose name was a guess keeps the word of its kind", e[7].detail, "Bid or buyout")
    eq("journal: a deposit with one posting near it names the posting", e[8].detail, "Deposit: Ironweb Spider Silk x3")
    check("journal: deposits of postings a few seconds apart are not told apart by time", e[9].detail == "Deposit" and e[10].detail == "Deposit", e[9].detail .. " / " .. e[10].detail)
    check("journal: a row with no auction record keeps the word of its kind", e[11].detail == "Buyout" and e[12].detail == "Deposit")
    check("journal: nothing is written into the stored rows", ns.DB.loot.ah.bought[1].detail == nil and ns.DB.loot.ah.posted[1].ebTaken == nil)
    -- the source's "mostly from": the item with its units, while the rows kept add up to the ledger
    local sc = Gold.scope(SID)
    local src = Gold.sources(sc, Gold.scopeEntries(sc))
    local ah
    for _, r in ipairs(src.rows) do if r.key == "auctions" then ah = r end end
    check("sources: Auction house is mostly Black Lotus x3, the rows kept add up", ah and ah.kept == true and ah.top[1].name == "Black Lotus" and ah.top[1].qty == 3 and ah.top[1].amount == 281985, ah and ah.top[1] and ah.top[1].name)
    local gs
    for _, t in ipairs(ah.top) do if t.name == "Golden Sansam" then gs = t end end
    check("sources: the three Sansam purchases are one group of 60", gs and gs.qty == 60 and gs.amount == 27880 + 22780 * 2)
    -- a journal with a row missing: the ledger keeps the amount, and no "mostly from" is offered
    sess.gold.auctions = sess.gold.auctions + 12345; sess.spent = sess.gold.auctions
    sc = Gold.scope(SID)
    src = Gold.sources(sc, Gold.scopeEntries(sc))
    for _, r in ipairs(src.rows) do if r.key == "auctions" then ah = r end end
    check("sources: rows that do not add up to the ledger are not kept: the amount is the ledger's", ah.kept == false and ah.amount == sess.gold.auctions)
  end

  ns.DB.sessions[SID] = nil
  ns.DB.loot.ah = keep.ah
  M.epoch = keep.epoch
  ns.Recorder.current = keep.current
end
