-- The gold suites on a client of their own (everbuff-wow-addon #43, 0.9.46). Run from the repo root:
--   luajit tests/gold_profile.lua legacy      the stub as it is: legacy globals and namespaced functions both there
--   luajit tests/gold_profile.lua forever     the WoW Forever profile: the globals with a documented namespaced
--                                             replacement are gone BEFORE the addon loads (M.FOREVER_GONE)
--   luajit tests/gold_profile.lua bare        a client with none of what 0.9.46 feature-tests: the new events are
--                                             unknown (registering one throws), the new functions are missing;
--                                             every rule falls back to the behavior of 0.9.45
-- tests/run_tests.lua runs the three (one process each: a profile has to be in place when the addon files load, as
-- on the real client) and counts their checks. Exit code 1 when a check fails.
package.path = "tests/?.lua;" .. package.path
local mode = (arg and arg[1]) or "legacy"
local M = require("wow_stub")
local passed, failed = 0, 0
local function check(name, cond, detail)
  if cond then passed = passed + 1
  else failed = failed + 1; io.stdout:write(("FAIL  [%s] %s%s\n"):format(mode, name, detail ~= nil and ("   -> " .. tostring(detail)) or "")) end
end
_G.print = function() end   -- the addon's chat lines are not part of the result

local NEW_EVENTS = { "CHAT_MSG_MONEY", "CONFIRM_TALENT_WIPE", "COMMODITY_PRICE_UPDATED", "AUCTION_HOUSE_AUCTION_CREATED", "AUCTION_HOUSE_PURCHASE_COMPLETED",
  "COMMODITY_PURCHASE_SUCCEEDED", "COMMODITY_PURCHASE_FAILED", "AUCTION_CANCELED", "AUCTION_HOUSE_SHOW_ERROR",
  "MAIL_FAILED", "ACCOUNT_MONEY" }   -- (0.9.48)
if mode == "forever" or mode == "bare" then M.profile("forever") end
if mode == "bare" then
  M.unknownEvents = {}
  for _, e in ipairs(NEW_EVENTS) do M.unknownEvents[e] = true end
  C_PlayerInteractionManager, CanMerchantRepair, GetRepairAllCost = nil, nil, nil
  C_MerchantFrame.GetItemInfo, GetBuybackItemInfo, GetBuybackItemLink = nil, nil, nil
  C_AuctionHouse.CalculateItemDeposit, C_AuctionHouse.CalculateCommodityDeposit, C_AuctionHouse.GetCancelCost = nil, nil, nil
  LOOT_MONEY_SPLIT, YOU_LOOT_MONEY, YOU_LOOT_MONEY_GUILD = nil, nil, nil
  TakeTaxiNode = nil
  -- (0.9.48) no send hooks, no outbid subject, no banks
  SetSendMailMoney, SetSendMailCOD, SendMail, GetSendMailPrice, AUCTION_OUTBID_MAIL_SUBJECT = nil, nil, nil, nil, nil
  C_Bank, DepositGuildBankMoney, WithdrawGuildBankMoney, C_PlayerInfo = nil, nil, nil, nil
  ReloadUI, GOLD_AMOUNT, SILVER_AMOUNT, COPPER_AMOUNT, ERR_TAXINOTENOUGHMONEY, ERR_TAXINOPATHS = nil, nil, nil, nil, nil, nil
end

local ns, ADDON = {}, "EverbuffJournal"
for line in io.lines("Everbuff/EverbuffJournal.toc") do
  local f = line:match("^([%w_]+)%.lua%s*$")
  if f then
    local chunk, err = loadfile("Everbuff/" .. f .. ".lua")
    check("parse " .. f, chunk ~= nil, err)
    if chunk then local ok, e = pcall(chunk, ADDON, ns); check("load " .. f, ok, e) end
  end
end
M.fire("ADDON_LOADED", ADDON)
M.money, M.xp = 5000, 100
M.fire("PLAYER_ENTERING_WORLD", true, false)
M.runTimers()
check("boot: a session is running and no handler threw", ns.Recorder and ns.Recorder.current() ~= nil and #M.errors == 0, M.errors[1])

local function suite(name)
  local ok, err = pcall(dofile("tests/" .. name .. ".lua"), { check = check, M = M, ns = ns })
  check("tests/" .. name .. ".lua runs to its end", ok, err)
end

if mode == "bare" then
  local E = ns.Emitter
  local function row()
    local log = ns.Recorder.current().goldLog
    local _, d, src, bal, ref = E.rowParse(log[#log] or "")
    return { delta = d, src = src, bal = bal, ref = ref }
  end
  local function money(d) M.money = M.money + d; M.fire("PLAYER_MONEY") end
  local function is(name, src, delta, ref)
    local r = row()
    check(name, r.src == src and r.delta == delta and r.bal == M.money and (ref == nil or r.ref == ref), ("%s %s [%s]"):format(tostring(r.src), tostring(r.delta), tostring(r.ref)))
  end
  for _, e in ipairs(NEW_EVENTS) do
    local on = false
    for _, fr in ipairs(M.frames) do if fr.events[e] then on = true end end
    check("an event this client does not have is skipped, not an error: " .. e, not on)
  end
  M.now = M.now + 10
  M.fire("LOOT_OPENED"); money(150); is("looted coin", "looted", 150, "")
  M.now = M.now + 10
  M.fire("CHAT_MSG_MONEY", "Your share of the loot is 5 Copper."); money(5)
  is("no coin line on this client: income with no window stays unexplained", "unexplained", 5, "")
  M.now = M.now + 10
  M.units.NPC = { name = "Merchant Bob" }; M.fire("MERCHANT_SHOW")
  M.bags[0][3] = { itemID = 2589, quality = 1, stackCount = 5 }; M.sellPrice[2589] = 13
  C_Container.UseContainerItem(0, 3); M.bags[0][3] = nil
  money(65); is("a sale, the price from C_Item.GetItemInfo", "sold", 65, "item=2589;n=5;unit=13;npc=Merchant Bob")
  M.merchant[2] = { id = 159, name = "Refreshing Spring Water", price = 25, qty = 5 }
  BuyMerchantItem(2, 5); money(-25); is("a purchase with no price to read is matched by age, as before", "vendor", -25, "item=159;n=5;npc=Merchant Bob")
  RepairAllItems(); money(-40); is("no repair cost to read: the 2 s rule", "repairs", -40, "npc=Merchant Bob")
  M.now = M.now + 3; money(-41); is("after the 2 s: a purchase", "vendor", -41, "npc=Merchant Bob")
  BuybackItem(1); money(-13); is("a buyback with nothing to read is a purchase", "vendor", -13, "npc=Merchant Bob")
  M.fire("MERCHANT_CLOSED"); M.runTimers(); M.units.NPC = nil; M.now = M.now + 10
  M.units.NPC = { name = "Flight Fay" }; M.fire("TAXIMAP_OPENED"); money(-20); is("the 5 s window of the flight map", "flights", -20, "npc=Flight Fay")
  M.units.NPC = nil; M.now = M.now + 10
  M.fire("AUCTION_HOUSE_SHOW"); C_AuctionHouse.PostItem("x", 2, 1, 10, 20); money(-6); is("no deposit to read: a plain auctions row", "auctions", -6, "")
  M.fire("AUCTION_HOUSE_CLOSED"); M.runTimers(); M.now = M.now + 10
  M.fire("CONFIRM_TALENT_WIPE", 700); money(-700); is("no talent wipe event: unexplained spending", "other", -700, "")
  M.fire("MAIL_SHOW"); M.inbox = { { sender = "Rando", subject = "gold", money = 90 } }
  TakeInboxMoney(1); money(90); is("mail", "mail", 90, "sender=Rando;rel=stranger;cod=0")
  -- (0.9.48) with no send hook, no outbid subject and no bank functions every rule is the behavior of 0.9.47
  M.inbox = { { sender = "Stormwind Auction House", subject = "Outbid on Linen Cloth", money = 70, canReply = false } }
  TakeInboxMoney(1); money(70); is("no outbid subject on this client: a returned bid stays mail", "mail", 70, "sender=Stormwind Auction House;rel=system;cod=0")
  M.now = M.now + 10
  money(-1030); is("no send hooks: gold mailed is one mailSpent row, as before", "mailSpent", -1030, "")
  M.fire("MAIL_CLOSED"); M.runTimers(); M.now = M.now + 10
  money(-500); is("no bank functions: a deposit is unexplained spending, as before", "other", -500, "")
  check("the session still says transfers are apart, with every key at 0", ns.Recorder.current().goldV == 2 and ns.Recorder.current().gold.xferOut == 0 and ns.Recorder.current().gold.mailSent == 0)
  check("no handler threw on the bare client", #M.errors == 0, M.errors[1])
else
  suite("gold_journal")
  suite("gold_sources")
  suite("gold_xfer")   -- (0.9.48) transfers and refunds
  check("no handler threw", #M.errors == 0, M.errors[1])
end

io.stdout:write(("%d passed, %d failed\n"):format(passed, failed))
os.exit(failed > 0 and 1 or 0)
