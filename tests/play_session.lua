-- One more session played through the addon's REAL event handlers: an hour of questing with loot of every quality,
-- coin, fights, quests, a vendor, a repair, the mailbox, the auction house and a trade, enough rows to fill and scroll
-- every list. The suite ends on a nearly empty character; tests/render_html.lua and the pane tests (tests/panes/) play
-- this first so their panes show real data.
--   dofile("tests/play_session.lua")(M, ns)
-- The purse is the size a player really has (#49): 12,345g here, so every pane is laid out around a balance in the
-- tens of thousands of gold and, on the long data (tests/layout.lua L.stretch), in the millions.
return function(M, ns)
  ns._test.newLoad(); M.money = 123456789; M.fire("PLAYER_ENTERING_WORLD", true, false); M.runTimers()
  M.money = GetMoney(); M.fire("PLAYER_MONEY")
  local px_, py_ = 0.30, 0.55
  _G.C_Map.GetPlayerMapPosition = function() return { GetXY = function() return px_, py_ end } end
  local Q = { "ff9d9d9d", "ffffffff", "ff1eff00", "ff0070dd", "ffa335ee" }
  local ITEMS = { { "Linen Cloth", 2589, 2, 3 }, { "Ruined Pelt", 4865, 1, 1 }, { "Cruel Barb", 5191, 4, 1 }, { "Small Venom Sac", 1475, 2, 2 },
    { "Thistlewood Bow", 2507, 3, 1 }, { "Wool Cloth", 2592, 2, 4 }, { "Gnoll War Harness", 1211, 1, 1 }, { "Silk Cloth", 4306, 2, 2 },
    { "Bundle of Wood", 5075, 2, 1 }, { "Mageweave Cloth", 4338, 2, 5 }, { "Defias Brotherhood Mask", 7997, 3, 1 } }
  local FOES = { "Riverpaw Gnoll", "Defias Thug", "Murloc Coastrunner", "Harvest Watcher", "Kobold Miner", "Redridge Mystic", "Young Forest Bear" }
  local ZONES = { "Westfall", "Elwynn Forest", "Redridge Mountains", "Duskwood" }
  for i = 1, 36 do
    M.epoch = M.epoch + 61; M.now = M.now + 61
    M.zone = ZONES[(math.floor((i - 1) / 9)) % #ZONES + 1]
    px_, py_ = 0.30 + (i % 7) * 0.031, 0.55 - (i % 5) * 0.027
    local foe = FOES[i % #FOES + 1]
    M.units.target = { name = foe, hostile = true, guid = ("Creature-0-1-1-1-%d-%04X"):format(400 + i, i), cls = (i % 9 == 0) and "elite" or "normal" }
    M.inCombat = true; M.fire("PLAYER_REGEN_DISABLED"); M.now = M.now + 9 + i % 11
    M.units.target.dead = true; M.inCombat = false; M.fire("PLAYER_REGEN_ENABLED")
    -- the kill's XP (Home > Now reads the pace from these, ns.Pace), never past the level
    M.fire("CHAT_MSG_COMBAT_XP_GAIN", foe .. " dies, you gain 8 experience.")
    M.xp = math.min((M.xp or 0) + 8, (M.xpmax or 1000) - 1); M.fire("PLAYER_XP_UPDATE")
    M.lootSourceGUID = M.units.target.guid
    M.fire("LOOT_OPENED")
    if i % 3 ~= 0 then
      local it = ITEMS[i % #ITEMS + 1]
      local link = ("|c%s|Hitem:%d::::::::12:::::|h[%s]|h|r"):format(Q[it[3]], it[2], it[1])
      M.fire("CHAT_MSG_LOOT", "You receive loot: " .. link .. (it[4] > 1 and ("x" .. it[4]) or "") .. ".")
    end
    if i % 2 == 0 then M.money = M.money + 37 * i; M.fire("PLAYER_MONEY") end
    M.fire("LOOT_CLOSED")
    M.units.target = nil; M.lootSourceGUID = nil
    if i % 12 == 0 then M.fire("QUEST_TURNED_IN", 100 + i, 850 + i * 10, 1200 + i * 20) end
  end
  -- vendor and repairs, then the mailbox and the auction house
  M.epoch = M.epoch + 120; M.now = M.now + 120
  M.fire("MERCHANT_SHOW"); M.money = M.money + 4321; M.fire("PLAYER_MONEY")
  M.repairCost = 2468; M.fire("UPDATE_INVENTORY_DURABILITY"); RepairAllItems(); M.money = M.money - 2468; M.fire("PLAYER_MONEY"); M.fire("MERCHANT_CLOSED")
  M.locations.r1 = { name = "Cruel Barb", id = 5191, icon = 135651, count = 1 }
  M.locations.r2 = { name = "Bolt of Silk Cloth", id = 4305, icon = 132891, count = 20 }
  M.fire("AUCTION_HOUSE_SHOW")
  C_AuctionHouse.PostItem("r1", 3, 1, 50000, 90000)
  C_AuctionHouse.PostCommodity("r2", 2, 20, 1250)
  C_AuctionHouse.PlaceBid(9101, 23456)
  M.itemNames = { [2772] = "Iron Ore" }
  C_AuctionHouse.StartCommoditiesPurchase(2772, 40); M.fire("COMMODITY_PRICE_UPDATED", 310, 12400); M.fire("COMMODITY_PURCHASE_SUCCEEDED")
  M.money = M.money - 12400 - 23456; M.fire("PLAYER_MONEY")
  M.fire("AUCTION_HOUSE_CLOSED")
  M.epoch = M.epoch + 3600; M.now = M.now + 3600
  M.inbox = {
    { sender = "Auction House", subject = "Auction successful: Cruel Barb", money = 85500, invoice = { "seller", "Cruel Barb", "Buyerguy", 50000, 90000, 500, 4500 } },
    { sender = "Auction House", subject = "Auction expired: Wool Cloth", money = 0, items = { { name = "Wool Cloth", id = 2592, count = 8, quality = 1 } } },
    { sender = "Auction House", subject = "Auction won: Thick Leather", money = 0, invoice = { "buyer", "Thick Leather", "Sellerguy" }, items = { { name = "Thick Leather", id = 4304, count = 5, quality = 1 } } },
    { sender = "Thrall", subject = "gift", money = 0, items = { { name = "Elixir of Agility", id = 8949, count = 3, quality = 1 } } },
    { sender = "Sylvanas", subject = "loan", money = 25000 },
  }
  M.fire("MAIL_SHOW")
  TakeInboxMoney(1); M.money = M.money + 85500; M.fire("PLAYER_MONEY")
  TakeInboxItem(2, 1); TakeInboxItem(3, 1); TakeInboxItem(4, 1)
  TakeInboxMoney(5); M.money = M.money + 25000; M.fire("PLAYER_MONEY")
  M.fire("MAIL_CLOSED"); M.inbox = {}
  M.units.NPC = { name = "Kristijan" }; M.fire("TRADE_SHOW"); M.money = M.money + 2500; M.fire("PLAYER_MONEY")
  M.money = M.money - 700; M.fire("PLAYER_MONEY"); M.fire("TRADE_CLOSED"); M.units.NPC = nil
  M.runTimers(); M.tick()
end
