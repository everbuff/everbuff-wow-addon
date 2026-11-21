-- The auction house in Loot > Gold (docs/UX_PRAGMATIC.md 4.2). Loaded by tests/run_tests.lua after the gold suites:
--   dofile("tests/gold_auctions.lua")({ check = check, M = M, ns = ns })
-- The fixtures mirror the shapes of a real save (the founder's of 21 Nov 2026): a commodity purchase with its price
-- and the delivery mails that follow it, deliveries with no purchase stored, commodity sale invoices whose `buyout`
-- slot is the quantity, C_AuctionHouse.PlaceBid rows that have no item at bid time, and postings a few seconds apart.
--   rows      one purchase is one row: its delivery mails are taken up by it (same item, same session or within the
--             hour, units still to come); deliveries with no purchase are "Collected" with no price, the mails of
--             one item taken together folded into one row; a sale's price is what the buyer paid and its count the
--             posting's only when that posting is one lot; a stored net that is not the invoice's sum is dropped; a
--             bid with no item of its own (or one named by the old "newest row without a name" rule) is a row only
--             when an auction mail of its session names its price (Market.invoiceNames); a posting with a stored
--             outcome is only its Sold, Expired or Cancelled row, and one with none is a row while its time runs
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
  -- a later session of the same character (a mail taken there, more than an hour after a purchase of the first)
  local SID2 = "t-auctions-2"
  ns.DB.sessions[SID2] = { id = SID2, guid = guid, startedEpoch = T + 3700, startedMono = 5000, endedEpoch = T + 7300, gained = 0, spent = 0, gold = {}, goldLog = {} }
  local function ahRows(t) ns.DB.loot.ah = { posted = t.posted or {}, bought = t.bought or {}, sold = t.sold or {}, returned = t.returned or {} } end
  local function find(rows, what, item) local out = {}; for _, r in ipairs(rows) do if r.what == what and (item == nil or r.item == item) then out[#out + 1] = r end end return out end

  -- ── rows: one purchase is one row ───────────────────────────────────────────────────────────────────────────
  M.epoch = T + 900   -- (the rows below are looked at 15 minutes into the session: every posting can still be open)
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
      -- a mail taken in another session, more than an hour after the purchase, is not this purchase's
      { s = SID, t = T + 300, item = "Black Lotus", id = 13468, count = 3, price = 281985, unit = 93995, kind = "commodity" },
      { s = SID2, t = T + 300 + 3601, item = "Black Lotus", id = 13468, count = 3, kind = "mail", seller = "Acornelius Thost" },
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
    for _, r in ipairs(rows) do if r.s == SID or r.s == SID2 then mine[#mine + 1] = r end end
    local mage = find(mine, "Bought", "Mageweave Cloth")
    check("auctions: a purchase of 120 and its six delivery mails are one Bought row with the price", #mage == 1 and mage[1].price == 53300 and mage[1].count == 120, #mage)
    eq("auctions: the delivery mail gives the seller to its purchase", mage[1].note, "Neti One")
    check("auctions: no delivery of it is listed", #find(mine, "Collected", "Mageweave Cloth") == 0 and #find(mine, "Won") == 0)
    local gs = find(mine, "Bought", "Golden Sansam")
    check("auctions: three purchases of one item stay three rows, each with its own price", #gs == 3 and gs[1].price + gs[2].price + gs[3].price == 22780 + 22780 + 22763, #gs)
    local won = find(mine, "Collected")
    local names = {}
    for _, r in ipairs(won) do names[#names + 1] = r.item end
    table.sort(names)
    eq("auctions: a delivery with no purchase to take it up is Collected: the fourth Sansam, the Wool Cloth, the late Black Lotus", table.concat(names, ","), "Black Lotus,Golden Sansam,Wool Cloth")
    local priced = true
    for _, r in ipairs(won) do if r.price ~= nil then priced = false end end
    check("auctions: a Collected row has no price", priced)
    local lotus = find(mine, "Bought", "Black Lotus")
    check("auctions: a mail of another session more than an hour after the purchase is not taken up by it", #lotus == 1 and lotus[1].price == 281985 and lotus[1].note == "")
    -- the bids
    local unnamed, bag = {}, nil
    for _, r in ipairs(find(mine, "Bought")) do
      if r.price == 16046 or r.price == 16047 then unnamed[#unnamed + 1] = r end
      if r.price == 16499 then bag = r end
    end
    check("auctions: a bid named by the old rule (a guess is not a fact) and a bid never named are not rows: nothing says what they bought", #unnamed == 0 and sum.bids >= 2, #unnamed)
    check("auctions: a bid named by its invoice shows the item and the seller", bag and bag.item == "Red Mageweave Bag" and bag.note == "Bagmaker" and not bag.byInvoice)
    local blank = 0
    for _, r in ipairs(mine) do if r.item == nil or r.item == "" then blank = blank + 1 end end
    eq("auctions: no row is without an item", blank, 0)
    check("auctions: Market.guessed tells the three apart", Market.guessed(ns.DB.loot.ah.bought[18]) == true and Market.guessed(ns.DB.loot.ah.bought[19]) == false and Market.guessed(ns.DB.loot.ah.bought[20]) == false)
    -- sales
    local stag, sansam, boots, wolf = find(mine, "Sold", "Stag Meat")[1], find(mine, "Sold", "Golden Sansam")[1], find(mine, "Sold", "Formula: Enchant Boots - Greater Stamina")[1], find(mine, "Sold", "Red Wolf Meat")[1]
    check("auctions: a sale's price is what the buyer paid, never the mail money", stag.price == 1043 and stag.net == 1147 and boots.price == 29000 and boots.net == 28150, stag.price)
    check("auctions: a sale's count is its posting's (same item, buyout == bid)", stag.count == 7 and sansam.count == 1 and boots.count == 1, stag.count)
    check("auctions: a sale with no posting stored has no count, never the invoice's slot", wolf.count == nil and wolf.price == 759 and wolf.postedAt == nil)
    check("auctions: a posting that sold is only its Sold row, which knows when it was posted", #find(mine, "Posted") == 0 and stag.postedAt == T + 500 and sansam.postedAt == T + 504 and boots.postedAt == T + 600, #find(mine, "Posted"))
    check("auctions: cut and deposit ride along for the tooltip", stag.cut == 52 and stag.deposit == 156)
    -- the sums: purchases with a price only
    local n, spent = 0, 0
    for _, r in ipairs(find(mine, "Bought")) do n = n + 1; spent = spent + (r.price or 0) end
    check("auctions: the purchases are the priced rows that have an item", n == 6 and spent == 53300 + 22780 + 22780 + 22763 + 281985 + 16499, n .. " " .. spent)
    check("auctions: the sum counts purchases and deliveries apart", sum.bought >= 6 and sum.won >= 3)
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
    check("auctions of a session: bought 6, 2 deliveries with no purchase (the third is another session's), no open posting (the 3 sold), expired 1; 2 bids are not rows",
      sum.bought == 6 and sum.won == 2 and sum.posted == 0 and sum.expired == 1 and sum.bids == 2 and sum.ended == 0, ("%d %d %d %d %d %d"):format(sum.bought, sum.won, sum.posted, sum.expired, sum.bids, sum.ended))
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
    -- A bid named at bid time (C_AuctionHouse.PlaceBid with the item asked from the client): count 1 until the mail.
    -- Its won mail, whose invoice names its price, is taken up by it whatever the stack and however late.
    do
      local n0 = #list
      Market.bought({ auctionId = 601, price = 4000, count = 1, kind = "item", item = "Runecloth", id = 14047, named = "bid" })
      M.epoch = M.epoch + 30
      local b = Market.mailItem("Auction won", "Runecloth", 14047, 20, { seller = "Clothier", bid = 4000 })
      check("capture: a bid named at the bid takes up its won mail of a stack: one row, the mail's count, the seller", #list == n0 + 1 and b == list[n0 + 1] and b.count == 20 and b.delivered == 20 and b.seller == "Clothier"
        and b.named == "bid" and b.price == 4000, #list - n0)
      Market.bought({ auctionId = 602, price = 9000, count = 1, kind = "item", item = "Lichbane", id = 20083, named = "bid" })
      M.epoch = M.epoch + 2 * 3600
      b = Market.mailItem("Auction won", "Lichbane", 20083, 1, { bid = 9000 })
      check("capture: and its mail two hours later", #list == n0 + 2 and b == list[n0 + 2] and b.delivered == 1 and b.count == 1, #list - n0)
      -- a second mail of the same item at the same price is not the same auction
      b = Market.mailItem("Auction won", "Lichbane", 20083, 1, { bid = 9000 })
      check("capture: a bid takes one mail, a second one of the same item and price is a row of its own", #list == n0 + 3 and b.kind == "mail", #list - n0)
      -- an invoice of another amount is not this bid's
      Market.bought({ auctionId = 603, price = 5000, count = 1, kind = "item", item = "Felcloth", id = 14256, named = "bid" })
      M.epoch = M.epoch + 2 * 3600
      b = Market.mailItem("Auction won", "Felcloth", 14256, 4, { bid = 5001 })
      check("capture: a mail whose invoice names another amount is not the bid's", #list == n0 + 5 and b.kind == "mail" and list[n0 + 4].delivered == nil and list[n0 + 4].count == 1)
      -- a commodity purchase whose mails come more than an hour later, in the same session: still its own
      Market.bought({ item = "Tender Wolf Meat", id = 12208, count = 40, price = 10579, kind = "commodity" })
      M.epoch = M.epoch + 96 * 60
      Market.mailItem("Auction won", "Tender Wolf Meat", 12208, 20, {})
      b = Market.mailItem("Auction won", "Tender Wolf Meat", 12208, 20, {})
      check("capture: the mails of a purchase of the same session are counted on it, also 96 minutes later", #list == n0 + 6 and b == list[n0 + 6] and b.delivered == 40)
      b = Market.mailItem("Auction won", "Tender Wolf Meat", 12208, 20, {})
      check("capture: one more mail than was bought is a row of its own", #list == n0 + 7 and b.kind == "mail")
      for i = #list, n0 + 1, -1 do list[i] = nil end
    end
    -- the rows these captures give the pane
    local rows = Market.buildAuctions()
    local won, bought = 0, 0
    for _, r in ipairs(rows) do if r.s == SID then if r.what == "Collected" then won = won + 1 elseif r.what == "Bought" then bought = bought + 1 end end end
    check("capture: the pane then lists 3 purchases (the bid nothing named is not a row) and 5 deliveries with no purchase", bought == 3 and won == 5, bought .. " " .. won)
    ns.DB.active = active
  end

  -- ── review round 1: shapes of the founder's save that showed a wrong number or one trade twice ───────────────
  do
    ahRows({
      bought = {
        -- Tender Wolf Meat x40 bought, its two delivery mails 96 minutes later in the same session (18 Nov 10:43, 12:19)
        { s = SID, t = T + 10, item = "Tender Wolf Meat", id = 12208, count = 40, price = 10579, kind = "commodity" },
        { s = SID, t = T + 10 + 5760, item = "Tender Wolf Meat", id = 12208, count = 20, kind = "mail" },
        { s = SID, t = T + 10 + 5760, item = "Tender Wolf Meat", id = 12208, count = 20, kind = "mail" },
        -- Wool Cloth x120 bought, nine mails of 20: six are its own, three have no purchase (19 Nov 21:53)
        { s = SID, t = T + 6000, item = "Wool Cloth", id = 2592, count = 120, price = 17000, kind = "commodity" },
        { s = SID, t = T + 6060, item = "Wool Cloth", id = 2592, count = 20, kind = "mail" }, { s = SID, t = T + 6060, item = "Wool Cloth", id = 2592, count = 20, kind = "mail" },
        { s = SID, t = T + 6061, item = "Wool Cloth", id = 2592, count = 20, kind = "mail" }, { s = SID, t = T + 6061, item = "Wool Cloth", id = 2592, count = 20, kind = "mail" },
        { s = SID, t = T + 6062, item = "Wool Cloth", id = 2592, count = 20, kind = "mail" }, { s = SID, t = T + 6062, item = "Wool Cloth", id = 2592, count = 20, kind = "mail" },
        { s = SID, t = T + 6063, item = "Wool Cloth", id = 2592, count = 20, kind = "mail", seller = "Ann" }, { s = SID, t = T + 6063, item = "Wool Cloth", id = 2592, count = 20, kind = "mail", seller = "Ann" },
        { s = SID, t = T + 6064, item = "Wool Cloth", id = 2592, count = 20, kind = "mail", seller = "Bob" },
        -- one more Wool Cloth mail ten minutes later: not the same visit, a row of its own
        { s = SID, t = T + 6700, item = "Wool Cloth", id = 2592, count = 20, kind = "mail" },
      },
      posted = {
        -- ten auctions of one breastplate each, posted in one call at 10s each (the founder's save: Runed Copper Breastplate)
        { s = SID, t = T + 100, item = "Runed Copper Breastplate", id = 2864, count = 10, bid = 900, buyout = 1000, hours = 24, kind = "item" },
        -- a commodity lot of 3 at 55s each
        { s = SID, t = T + 101, item = "Ironweb Spider Silk", id = 14227, count = 3, unit = 5500, buyout = 16500, hours = 24, kind = "commodity" },
      },
      sold = {
        { s = SID, t = T + 200, item = "Runed Copper Breastplate", bid = 1000, buyout = 1000, cut = 50, deposit = 30, net = 980 },
        { s = SID, t = T + 201, item = "Runed Copper Breastplate", bid = 1000, buyout = 1000, cut = 50, deposit = 30, net = 980 },
        { s = SID, t = T + 202, item = "Ironweb Spider Silk", bid = 16500, buyout = 3, cut = 825, deposit = 150, net = 15825 },
        -- rows written before 0.9.46: `net` was the purse change of several mails (7 Nov, Azora's Will and Moccasins)
        { s = SID, t = T + 300, item = "Azora's Will", bid = 4400, buyout = 4400, cut = 220, deposit = 210, net = 7607 },
        { s = SID, t = T + 301, item = "Moccasins of the White Hare", bid = 3800, buyout = 3800, cut = 190, deposit = 286, net = 2176 },
      },
    })
    -- a stored row of a session whose record is gone (the desktop app picked it up): whose it is, is not known
    ns.DB.loot.ah.sold[#ns.DB.loot.ah.sold + 1] = { s = "t-auctions-gone", t = T + 50, item = "Linen Cloth", bid = 100, buyout = 100, cut = 5, deposit = 1, net = 96 }
    local rows, all = Market.buildAuctions()
    local mine = {}
    for _, r in ipairs(rows) do if r.s == SID then mine[#mine + 1] = r end end
    local meat = find(mine, "Bought", "Tender Wolf Meat")
    check("round 1: a purchase and its mails 96 minutes later in the same session are one row", #meat == 1 and meat[1].price == 10579 and #find(mine, "Collected", "Tender Wolf Meat") == 0)
    local wool, loose = find(mine, "Bought", "Wool Cloth"), find(mine, "Collected", "Wool Cloth")
    check("round 1: six of nine mails are the purchase's; the three left over are one Collected row of 60, the later one its own row", #wool == 1 and #loose == 2 and loose[1].count == 20 and loose[1].mails == 1
      and loose[2].count == 60 and loose[2].mails == 3 and loose[2].price == nil, #loose .. " " .. tostring(loose[2] and loose[2].count))
    eq("round 1: a folded row names a seller only when its mails agree", loose[2].note, "")
    eq("round 1: the sum counts the four mails with no purchase", all.won, 4)
    local post = find(mine, "Posted", "Runed Copper Breastplate")[1]
    check("round 1: ten auctions posted at once: the row says so and its price is the price of one", post.lots == true and post.count == 10 and post.price == 1000)
    local plate = find(mine, "Sold", "Runed Copper Breastplate")
    check("round 1: a sale of one of them takes no count from the posting of ten", #plate == 2 and plate[1].count == nil and plate[2].count == nil, tostring(plate[1].count) .. " " .. tostring(plate[2].count))
    local silk = find(mine, "Sold", "Ironweb Spider Silk")[1]
    check("round 1: a commodity lot sold whole still gives its count, and is one row", silk.count == 3 and silk.postedAt == T + 101 and #find(mine, "Posted", "Ironweb Spider Silk") == 0)
    check("round 1: ten auctions of which two sold: the posting stays a row while eight can still be open", #find(mine, "Posted", "Runed Copper Breastplate") == 1 and plate[1].postedAt == T + 100)
    local az, moc = find(mine, "Sold", "Azora's Will")[1], find(mine, "Sold", "Moccasins of the White Hare")[1]
    check("round 1: a stored net that is not bid - cut + deposit is dropped, the invoice's figures stay", az.net == nil and az.price == 4400 and az.cut == 220 and az.deposit == 210 and moc.net == nil)
    check("round 1: a net that is the invoice's sum is kept", plate[1].net == 980 and silk.net == 15825)
    eq("round 1: the row whose session record is gone is counted, not listed", all.unowned .. "/" .. #find(rows, "Sold", "Linen Cloth"), "1/0")
    -- the tooltips
    local function tipOf(r) local tip = _G.GameTooltip; tip:ClearLines(); GP.auctionTip(nil, r, tip); return (table.concat(tip.lines or {}, "\n"):gsub("|T.-|t", ""):gsub("\194\160", " ")) end
    check("round 1: the hover of a sale with an inconsistent stored net has no Mail paid line", tipOf(az):find("Buyer paid", 1, true) ~= nil and tipOf(az):find("Mail paid", 1, true) == nil, tipOf(az))
    check("round 1: the hover of a consistent sale keeps it", tipOf(silk):find("Mail paid", 1, true) ~= nil and tipOf(silk):find("Each", 1, true) ~= nil)
    check("round 1: the hover of ten auctions posted at once divides nothing", tipOf(post):find("Each", 1, true) == nil and tipOf(post):find("The price is for one of them", 1, true) ~= nil, tipOf(post))
    check("round 1: the hover of a Collected row says what it is", tipOf(loose[2]):find("Price: Not recorded", 1, true) ~= nil and tipOf(loose[2]):find("Mails", 1, true) ~= nil)
    -- the period: the sale mails by their invoices, and the rows no list shows
    local list, sum = GP.auctions({ lifetime = true, ledger = {} })
    eq("round 1: all time counts the row it cannot list", sum.unowned, 1)
    local _, sumS = GP.auctions({ sessions = { sess }, ledger = {} })
    eq("round 1: the mail money of a period is the invoices' (sales - cut + deposits), never a stored net", sumS.mail, sumS.sales - sumS.cut + sumS.deposit)
    eq("round 1: a period of sessions cannot count the rows of sessions that are gone", sumS.unowned, 0)
    eq("round 1: four delivery mails with no purchase in the session", sumS.won, 4)
  end

  -- ── review round 2: one row per auction, and no row without an item ────────────────────────────────────────
  do
    local log = ns.DB.loot.log
    local n0 = #log
    local keepEpoch = M.epoch
    local function won(dt, item, id, bid, seller) log[#log + 1] = { s = SID, t = T + dt, item = item, id = id, count = 1, src = "Auction won", mail = { bid = bid, buyout = bid, seller = seller, subject = "Auction won: " .. item } } end
    ahRows({
      bought = {
        -- the founder's 17 Nov: eight PlaceBid rows with guessed names, two of them on one auction; five won mails
        -- of Red Mageweave Bag, 16,046 and 4 x 16,499
        { s = SID, t = T + 57, auctionId = 142300059, price = 16046, count = 1, kind = "item", item = "Silk Cloth", id = 4306 },
        { s = SID, t = T + 59, auctionId = 142300059, price = 16046, count = 1, kind = "item", item = "Wool Cloth", id = 2592 },
        { s = SID, t = T + 67, auctionId = 142310355, price = 16047, count = 1, kind = "item", item = "Wool Cloth", id = 2592 },
        { s = SID, t = T + 70, auctionId = 142318523, price = 16046, count = 1, kind = "item", item = "Red Mageweave Bag", id = 10051, seller = "Wrong Guess" },
        { s = SID, t = T + 75, auctionId = 142310003, price = 16047, count = 1, kind = "item", item = "Red Mageweave Bag", id = 10051 },
        { s = SID, t = T + 81, auctionId = 132895591, price = 16499, count = 1, kind = "item", item = "Red Mageweave Bag", id = 10051 },
        { s = SID, t = T + 84, auctionId = 132893650, price = 16499, count = 1, kind = "item", item = "Red Mageweave Bag", id = 10051 },
        { s = SID, t = T + 87, auctionId = 132893638, price = 16499, count = 1, kind = "item" },
        -- a purchase that has its item: a won mail of its price is its own and names no bid
        { s = SID, t = T + 90, item = "Mithril Casing", id = 10561, count = 1, price = 4685, kind = "item", named = "bid" },
        { s = SID, t = T + 91, auctionId = 5, price = 4685, count = 1, kind = "item" },
        -- a bid of another session with the same price: a mail of this session does not name it
        { s = SID2, t = T + 3800, auctionId = 6, price = 16499, count = 1, kind = "item" },
      },
      posted = {
        { s = SID, t = T + 10, item = "Fadeleaf", id = 3818, count = 1, buyout = 375, hours = 24, kind = "commodity" },             -- sold
        { s = SID, t = T + 11, item = "Raider's Belt", id = 9788, count = 1, buyout = 400, hours = 12, kind = "item" },              -- expired
        { s = SID, t = T + 12, item = "Red Leather Bag", id = 2657, count = 1, buyout = 1600, hours = 24, kind = "item" },           -- cancelled
        { s = SID, t = T + 13, item = "Sprite Darter Egg", id = 11474, count = 1, buyout = 650, hours = 24, kind = "item" },         -- no outcome
        { s = SID, t = T + 14, item = "Gorilla Fang", id = 2799, count = 12, buyout = 2352, hours = 48, kind = "commodity" },        -- no outcome, 48 h
        { s = SID, t = T + 15, item = "Fadeleaf", id = 3818, count = 1, buyout = 375, hours = 24, kind = "commodity" },              -- the second of two, one sale
        { s = SID, t = T + 16, item = "Raider's Belt", id = 9788, count = 2, buyout = 800, hours = 12, kind = "commodity" },         -- another count than the return
      },
      sold = { { s = SID, t = T + 3000, item = "Fadeleaf", bid = 375, buyout = 1, cut = 18, deposit = 10, net = 367 } },
      returned = { { s = SID, t = T + 600, item = "Red Leather Bag", id = 2657, count = 1, reason = "cancelled" } },
    })
    won(109, "Red Mageweave Bag", 10051, 16046, "Putrid Deathgasp")
    won(110, "Red Mageweave Bag", 10051, 16499, "Bagmaker One")
    won(110, "Red Mageweave Bag", 10051, 16499, "Bagmaker Two")
    won(110, "Red Mageweave Bag", 10051, 16499, "Bagmaker Two")
    won(111, "Red Mageweave Bag", 10051, 16499, "Bagmaker One")
    won(112, "Mithril Casing", 10561, 4685, "Smith")
    -- an hour in: every posting can still be open
    M.epoch = T + 3600
    local rows, all = Market.buildAuctions()
    local mine = {}
    for _, r in ipairs(rows) do if r.s == SID or r.s == SID2 then mine[#mine + 1] = r end end
    local bags = find(mine, "Bought", "Red Mageweave Bag")
    local got = {}
    for _, r in ipairs(bags) do got[#got + 1] = (r.t - T) .. ":" .. r.price .. ":" .. tostring(r.note) .. ":" .. tostring(r.byInvoice) end
    eq("round 2: a bid is named by the won mail of its session with exactly its price: the newest bid of 16,046 and the three of 16,499, each with the mail's seller",
      table.concat(got, " "), "87:16499:Bagmaker One:true 84:16499:Bagmaker Two:true 81:16499:Bagmaker Two:true 70:16046:Putrid Deathgasp:true")
    local blank, guessedName = 0, 0
    for _, r in ipairs(mine) do
      if r.item == nil then blank = blank + 1 end
      if r.what == "Bought" and (r.item == "Silk Cloth" or r.item == "Wool Cloth") then guessedName = guessedName + 1 end
    end
    eq("round 2: no purchase row is without an item, and no guessed name is shown", blank .. " " .. guessedName, "0 0")
    eq("round 2: the bids nothing names are counted, not listed: two on one auction, two of 16,047, the one beside a named purchase, the one of another session", all.bids, 6)
    eq("round 2: the fifth mail (a fourth 16,499) has no bid left and adds no row", #bags, 4)
    eq("round 2: a purchase that has its item keeps its own mail", #find(mine, "Bought", "Mithril Casing"), 1)
    eq("round 2: only the rows with an item count as bought", all.bought .. " " .. all.spent, "5 " .. (16046 + 3 * 16499 + 4685))
    eq("round 2: nothing is written into the stored rows", tostring(ns.DB.loot.ah.bought[8].item) .. " " .. ns.DB.loot.ah.bought[1].item, "nil Silk Cloth")
    local tipB = (function() local tip = _G.GameTooltip; tip:ClearLines(); GP.auctionTip(nil, bags[1], tip); return table.concat(tip.lines or {}, "\n") end)()
    check("round 2: the hover says where the name comes from", tipB:find("auction mail of this price", 1, true) ~= nil, tipB)
    -- one row per auction
    local posted = find(mine, "Posted")
    got = {}
    for _, r in ipairs(posted) do got[#got + 1] = r.item end
    table.sort(got)
    eq("round 2: a posting with its outcome is not a row: the sold Fadeleaf and the cancelled bag are gone, the rest can still be open", table.concat(got, ","), "Fadeleaf,Gorilla Fang,Raider's Belt,Raider's Belt,Sprite Darter Egg")
    eq("round 2: the Sold and Cancelled rows know when they were posted (the oldest posting of that item)", find(mine, "Sold", "Fadeleaf")[1].postedAt .. " " .. find(mine, "Cancelled")[1].postedAt, (T + 10) .. " " .. (T + 12))
    eq("round 2: the open postings are counted", all.posted .. " " .. all.ended, "5 0")
    -- 13 hours in: the 12 h postings have run out, one came back
    M.epoch = T + 13 * 3600
    table.insert(ns.DB.loot.ah.returned, { s = SID, t = T + 12 * 3600 + 500, item = "Raider's Belt", id = 9788, count = 1, reason = "expired" })
    rows, all = Market.buildAuctions()
    mine = {}
    for _, r in ipairs(rows) do if r.s == SID then mine[#mine + 1] = r end end
    got = {}
    for _, r in ipairs(find(mine, "Posted")) do got[#got + 1] = r.item end
    table.sort(got)
    eq("round 2: a posting whose time ran out is no longer a row: the belt that came back is its Expired row, the lot of 2 has no outcome recorded", table.concat(got, ","), "Fadeleaf,Gorilla Fang,Sprite Darter Egg")
    eq("round 2: the returned belt of 1 ends the posting of 1, not the lot of 2", find(mine, "Expired")[1].postedAt, T + 11)
    eq("round 2: the posting with no recorded outcome is counted, not listed", all.ended, 1)
    -- three days in: nothing can be open
    M.epoch = T + 3 * 86400
    rows, all = Market.buildAuctions()
    local open = 0
    for _, r in ipairs(rows) do if r.s == SID and r.what == "Posted" then open = open + 1 end end
    eq("round 2: three days later no posting is listed; four ended with no outcome recorded", open .. " " .. all.ended, "0 4")
    local _, sumS = GP.auctions({ sessions = { sess }, ledger = {} })
    eq("round 2: a period counts its own bids and ended postings", sumS.bids .. " " .. sumS.ended .. " " .. sumS.posted, "5 4 0")
    local tipText = GP.partialAhTip(sumS).text
    check("round 2: the remark's hover names each reason with its count", tipText:find("5 bids with no item recorded", 1, true) ~= nil and tipText:find("4 postings whose time ran out", 1, true) ~= nil
      and tipText:find("desktop app", 1, true) == nil, tipText)
    for i = #log, n0 + 1, -1 do log[i] = nil end
    M.epoch = keepEpoch
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
  ns.DB.sessions[SID2] = nil
  ns.DB.loot.ah = keep.ah
  M.epoch = keep.epoch
  ns.Recorder.current = keep.current
end
