-- Two evenings of gold played through the addon's REAL handlers, after tests/play_session.lua: quests with names,
-- coin from mobs, items sold to and bought from named merchants, repairs, a trainer, flights, the auction house, mail
-- from an alt, a guild mate and a stranger (one with COD), trades with a stranger and a guild mate, income nothing
-- explains and gold that changed while the addon was off. The first evening ends with a logout, so the Gold pane has a
-- previous session; the second is the running one.
--   dofile("tests/play_gold.lua")(M, ns)
return function(M, ns)
  local QUESTS = { [62] = "The Fargodeep Mine", [60] = "Kobold Candles", [47] = "Gold Dust Exchange", [76] = "The Jasperlode Mine",
    [88] = "Princess Must Die!", [176] = "Wanted: \"Hogger\"", [11] = "Riverpaw Gnoll Bounty", [12] = "The People's Militia",
    [214] = "Red Silk Bandanas", [9] = "The Killing Fields", [151] = "Poor Old Blanchy", [22] = "Goretusk Liver Pie",
    [102] = "Patrolling Westfall", [153] = "Red Leather Bandanas", [38] = "Westfall Stew", [166] = "The Defias Brotherhood" }
  _G.C_QuestLog = _G.C_QuestLog or {}
  local prevTitle = _G.C_QuestLog.GetTitleForQuestID
  _G.C_QuestLog.GetTitleForQuestID = function(id) return QUESTS[id] or (prevTitle and prevTitle(id)) end
  M.itemNames = M.itemNames or {}
  for id, name in pairs({ [2589] = "Linen Cloth", [4865] = "Ruined Pelt", [5191] = "Cruel Barb", [1475] = "Small Venom Sac",
    [2592] = "Wool Cloth", [1211] = "Gnoll War Harness", [769] = "Chunk of Boar Meat", [2070] = "Darnassian Bleu",
    [159] = "Refreshing Spring Water", [2770] = "Copper Ore", [3300] = "Rabbit's Foot", [4536] = "Shiny Red Apple",
    [2318] = "Light Leather", [1179] = "Ice Cold Milk", [3192] = "Short Bastard Sword of the Monkey" }) do M.itemNames[id] = name end

  local px_, py_ = 0.42, 0.61
  _G.C_Map.GetPlayerMapPosition = function() return { x = px_, y = py_, GetXY = function() return px_, py_ end } end
  local function at(zone, x, y) M.zone, px_, py_ = zone, x, y end
  local function wait(s) M.epoch = M.epoch + s; M.now = M.now + s end
  local function money(d) M.money = M.money + d; M.fire("PLAYER_MONEY") end
  local function closeAll()
    for _, e in ipairs({ "MERCHANT_CLOSED", "MAIL_CLOSED", "AUCTION_HOUSE_CLOSED", "TRAINER_CLOSED", "TRADE_CLOSED" }) do M.fire(e) end
    M.units.NPC = nil
  end
  local guidN = 9000
  local function kill(foe, copper)
    guidN = guidN + 1
    M.units.target = { name = foe, hostile = true, guid = ("Creature-0-1-1-1-%d-%04X"):format(guidN, guidN), cls = "normal" }
    M.inCombat = true; M.fire("PLAYER_REGEN_DISABLED"); wait(14)
    M.units.target.dead = true; M.inCombat = false; M.fire("PLAYER_REGEN_ENABLED")
    M.lootSourceGUID = M.units.target.guid
    M.fire("LOOT_OPENED"); if copper then money(copper) end; M.fire("LOOT_CLOSED")
    M.units.target = nil; M.lootSourceGUID = nil
    wait(46)
  end
  local function quest(id, copper, reward)
    M.fire("QUEST_TURNED_IN", id, 400 + id, copper); money(copper)
    if reward then M.fire("CHAT_MSG_LOOT", ("You receive item: |cff1eff00|Hitem:%d::::::::12:::::|h[%s]|h|r."):format(reward[1], reward[2])) end
    wait(20)
  end
  local function vendor(npc, sales, buys, repair)
    M.units.NPC = { name = npc }; M.fire("MERCHANT_SHOW")
    for i, s in ipairs(sales or {}) do   -- { id, n, unit, paid? }
      M.bags[0][i] = { itemID = s[1], quality = 1, stackCount = s[2] }; M.sellPrice[s[1]] = s[3]
      C_Container.UseContainerItem(0, i); M.bags[0][i] = nil
      money(s[4] or s[2] * s[3]); wait(1)
    end
    for i, b in ipairs(buys or {}) do    -- { id, name, price, n }
      M.merchant[i] = { id = b[1], name = b[2], price = b[3], qty = b[4] }
      BuyMerchantItem(i, b[4]); money(-b[3]); wait(1)
    end
    if repair then M.repairCost = repair; M.fire("UPDATE_INVENTORY_DURABILITY"); RepairAllItems(); money(-repair) end
    wait(6); M.fire("MERCHANT_CLOSED"); M.units.NPC = nil; wait(30)
  end
  local function trainer(npc, costs)
    M.units.NPC = { name = npc }; M.fire("TRAINER_SHOW")
    for _, c in ipairs(costs) do money(-c); wait(2) end
    M.fire("TRAINER_CLOSED"); M.units.NPC = nil; wait(20)
  end
  local function flight(npc, cost) M.units.NPC = { name = npc }; M.fire("TAXIMAP_OPENED"); money(-cost); M.units.NPC = nil; wait(95) end
  local function trade(npc, guild, got, gave, target, player)
    M.units.NPC = { name = npc, guild = guild }; M.fire("TRADE_SHOW")
    M.tradeWin = { gaveMoney = gave, gotMoney = got, player = player, target = target }
    M.fire("TRADE_MONEY_CHANGED"); M.fire("TRADE_PLAYER_ITEM_CHANGED"); M.fire("TRADE_TARGET_ITEM_CHANGED"); M.fire("TRADE_ACCEPT_UPDATE", 1, 1)
    if got - gave ~= 0 then money(got - gave) end
    M.fire("UI_INFO_MESSAGE", 0, "Trade complete."); M.tradeWin = nil; M.fire("TRADE_CLOSED"); M.units.NPC = nil
    wait(40)
  end
  local function mailbox(inbox, cod)
    M.fire("MAIL_SHOW"); M.inbox = inbox
    for i, m in ipairs(inbox) do
      if (m.money or 0) > 0 then TakeInboxMoney(i); money(m.money); wait(4) end
    end
    if cod then
      M.inbox = { cod }; TakeInboxItem(1, 1); money(-cod.cod); wait(4)
      money(-30); wait(4)   -- postage on a mail sent
    end
    M.fire("MAIL_CLOSED"); M.inbox = {}; wait(30)
  end

  -- who people are to this character
  ns.DB.characters["Player-1-0000A1"] = { name = "Hartbank", realm = (GetRealmName and GetRealmName()) or "Realm" }
  ns.Emitter.loadAlts()
  M.guild = { "Maribel", "Oswin" }; M.fire("GUILD_ROSTER_UPDATE")
  M.friends = { "Tessa" }; M.fire("FRIENDLIST_UPDATE")

  -- ── evening one: Elwynn Forest, ends with a logout ───────────────────────────────────────────────────────────
  closeAll(); M.runTimers(); wait(60)
  ns._test.newLoad(); M.fire("PLAYER_ENTERING_WORLD", true, false); M.runTimers(); M.tick()
  at("Elwynn Forest", 0.386, 0.812)
  for i = 1, 9 do kill(({ "Kobold Tunneler", "Kobold Miner", "Kobold Vermin" })[i % 3 + 1], 9 + i * 4) end
  at("Elwynn Forest", 0.432, 0.657); quest(62, 400); quest(60, 250)
  at("Elwynn Forest", 0.424, 0.659)
  vendor("Andrew Krighton", { { 2589, 12, 13 }, { 4865, 4, 20 }, { 769, 6, 4 } }, { { 159, "Refreshing Spring Water", 25, 5 } }, 312)
  at("Elwynn Forest", 0.413, 0.659); trainer("Lyria Du Lac", { 1000, 200 })
  at("Elwynn Forest", 0.612, 0.535)
  for i = 1, 7 do kill(({ "Kobold Geomancer", "Kobold Miner" })[i % 2 + 1], 21 + i * 6) end
  at("Elwynn Forest", 0.743, 0.722); quest(76, 500); quest(47, 350)
  money(180); wait(30)                                    -- income nothing explains
  at("Stormwind City", 0.612, 0.706)
  mailbox({ { sender = "Hartbank", subject = "pocket money", money = 15000 } })
  closeAll(); M.fire("PLAYER_LOGOUT"); wait(20 * 3600)

  -- ── evening two: Westfall and Stormwind; the purse changed while the addon was off, with mail waiting ────────
  ns._test.newLoad(); M.newMail = true; M.money = M.money + 4200
  M.fire("PLAYER_ENTERING_WORLD", true, false); M.runTimers(); M.tick(); M.newMail = false
  wait(40)
  at("Stormwind City", 0.662, 0.624); flight("Dungar Longdrink", 110)
  at("Westfall", 0.566, 0.526)
  local MOBS = { "Defias Trapper", "Riverpaw Gnoll", "Defias Smuggler", "Harvest Watcher", "Goretusk", "Riverpaw Scout", "Defias Pillager" }
  for i = 1, 14 do
    at("Westfall", 0.44 + (i % 6) * 0.021, 0.31 + (i % 5) * 0.034)
    kill(MOBS[i % #MOBS + 1], (i % 4 == 0) and nil or (31 + i * 9))
  end
  at("Westfall", 0.564, 0.476); quest(12, 900); quest(9, 650); quest(214, 1100); quest(151, 300)
  at("Westfall", 0.571, 0.538)
  vendor("Quartermaster Lewis", { { 2589, 20, 13 }, { 5191, 3, 85 }, { 1475, 5, 71 }, { 2592, 8, 33 }, { 1211, 1, 356 },
    { 3192, 1, 1284, 3852 } }, { { 2070, "Darnassian Bleu", 25, 5 }, { 1179, "Ice Cold Milk", 125, 5 } }, 1874)
  for i = 1, 12 do
    at("Westfall", 0.36 + (i % 7) * 0.018, 0.62 + (i % 4) * 0.029)
    kill(MOBS[(i + 3) % #MOBS + 1], 44 + i * 11)
  end
  at("Westfall", 0.564, 0.476); quest(22, 550); quest(102, 700); quest(153, 1250); quest(38, 450); quest(166, 1500, { 6078, "Pikeman Shield" })
  money(260); wait(25)                                    -- income nothing explains
  at("Westfall", 0.565, 0.527); flight("Thor", 190)
  at("Stormwind City", 0.538, 0.612)
  M.fire("AUCTION_HOUSE_SHOW"); money(-450); wait(5); money(-12800); wait(8); M.fire("AUCTION_HOUSE_CLOSED"); wait(20)
  at("Stormwind City", 0.612, 0.706)
  mailbox({
    { sender = "Stormwind Auction House", subject = "Auction successful: Wool Cloth", money = 8550, invoice = { "seller", "Wool Cloth", "Buyerguy", 8000, 9000, 150, 450 } },
    { sender = "Stormwind Auction House", subject = "Auction successful: Light Leather", money = 14250, invoice = { "seller", "Light Leather", "Tannerjoe", 0, 15000, 300, 750 } },
    { sender = "Maribel", subject = "for the guild tabard", money = 10000 },
    { sender = "Xzqtgold", subject = "cheap gold visit our site", money = 100 },
  }, { sender = "Oreseller", subject = "your ore", cod = 4500, items = { { name = "Copper Ore", id = 2770, count = 20, quality = 1 } } })
  at("Stormwind City", 0.741, 0.526); trainer("Wu Shen", { 2200, 1800, 900 })
  at("Stormwind City", 0.57, 0.57)
  trade("Xzqtgold", "Cheap Gold Fast", 250000, 0)
  trade("Oswin", "Azeroth Wanderers", 0, 5000, { { id = 2318, name = "Light Leather", count = 20 } })
  trade("Tessa", nil, 1500, 0, nil, { { id = 4536, name = "Shiny Red Apple", count = 5 } })
  money(-75); wait(15)                                    -- spending with no window open
  at("Stormwind City", 0.558, 0.647)
  vendor("Marda Weller", { { 3300, 2, 240 } }, {}, 640)
  M.runTimers(); M.tick()
end
