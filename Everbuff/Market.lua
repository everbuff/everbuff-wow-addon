-- Everbuff.GG · Market.lua - crafting, recipes and the auction house (issue #8).
--
-- WHAT: two things the loot log alone cannot tell: what the character MADE (crafts, with the profession, the
-- place and the time) and what went through the AUCTION HOUSE (postings with their prices, purchases, sales
-- with the house cut, returns). Both feed the web's "where did my gold and materials go" questions.
--
-- WHERE IT LIVES (schema 2, additive):
--   character.crafts[]  { s, t, item, id, icon, count, prof, zone, x, y }
--   character.recipes[] { s, t, name, prof }
--   loot.ah.posted[]    { s, t, item, id, icon, count, bid, buyout, unit, hours, kind = "item" | "commodity" }
--   loot.ah.bought[]    { s, t, item?, id?, count, price, auctionId?, kind, seller?, named?, delivered? }
--     kind "item" | "commodity" is a purchase with its price; kind "mail" is a delivery whose purchase was not found
--     (no price). named = "bid" | "invoice": how a C_AuctionHouse.PlaceBid row, which has no item at bid time, got
--     its item (asked at the bid, or the won mail whose invoice names this exact price). A PlaceBid row with an item
--     and no `named` was written before 0.9.52 and took the name of whichever won mail came next: a guess, which
--     the pane does not show. delivered: units of a priced row that its won mails have brought so far. A row named
--     at the bid has count 1 until its won mail, whose invoice names its price, brings the real count.
--   loot.ah.sold[]      { s, t, item, buyer?, bid, buyout, deposit, cut, net }   (from the seller invoice mail)
--   loot.ah.returned[]  { s, t, item, count, reason = "expired" | "cancelled" }   (from the returned-item mail)
-- Every row carries the addon session id `s` and a server-time `t`.
--
-- HOW: hooks on the post, bid and buy functions of whichever auction house API the client has (the Mainline
-- C_AuctionHouse with commodities, or the Classic StartAuction and PlaceAuctionBid), the tradeskill window
-- events for the profession behind a craft, and the mail invoice that Emitter already parses. Every value the
-- client could hide goes through the guards; nothing is recorded from a secret.

local ADDON, ns = ...

local Market = { tradeSkill = nil }
-- a won mail belongs to a priced purchase of the same item made in the same session, or at most this long before it
Market.DELIVERY_S = 3600
Market.FOLD_S = 60         -- deliveries with no purchase, of one item, taken this close together are one row
ns.Market = Market

local function isFinite(v) return v == v and v ~= math.huge and v ~= -math.huge end
local function plainNum(v)
  if type(v) ~= "number" or (issecretvalue and issecretvalue(v)) then return nil end
  local ok, fin = pcall(isFinite, v)   -- a secret number throws on compare
  return (ok and fin) and v or nil
end
local function cmp0(v) return v == "" or (v .. "") end
local function safeStr(v)
  if type(v) ~= "string" or (issecretvalue and issecretvalue(v)) then return nil end
  local ok = pcall(cmp0, v)            -- a secret string throws on compare (concat alone does not, 12.0)
  return ok and v or nil
end
local function nowEpoch() return (GetServerTime and GetServerTime()) or time() end
local function sid() return ns.DB and ns.DB.active end
local function loc()
  local zone = (GetRealZoneText and GetRealZoneText()) or nil
  local x, y
  pcall(function()
    if C_Map and C_Map.GetBestMapForUnit then
      local m = C_Map.GetBestMapForUnit("player")
      local p = m and C_Map.GetPlayerMapPosition(m, "player")
      if p then x, y = plainNum(p.x), plainNum(p.y) end
    end
  end)
  return zone, x, y
end
local function push(list, row, cap)
  list[#list + 1] = row
  while #list > (cap or 500) do table.remove(list, 1) end
  return row
end
local function ah()
  ns.DB.loot.ah = ns.DB.loot.ah or {}
  local a = ns.DB.loot.ah
  a.posted = a.posted or {}; a.bought = a.bought or {}; a.sold = a.sold or {}; a.returned = a.returned or {}
  return a
end
local function ch()
  local c = ns.char()
  c.crafts = c.crafts or {}
  c.recipes = c.recipes or {}
  return c
end

-- ── crafting ────────────────────────────────────────────────────────────────
--- Emitter calls this from the "You create: [item]" line. `prof` defaults to the tradeskill window open now.
function Market.craft(item, count, id, icon)
  if not ns.DB then return nil end
  local zone, x, y = loc()
  return push(ch().crafts, { s = sid(), t = nowEpoch(), item = safeStr(item), id = plainNum(id), icon = plainNum(icon),
    count = plainNum(count) or 1, prof = Market.tradeSkill, zone = zone, x = x, y = y }, 1000)
end
function Market.recipe(name, prof)
  if not ns.DB then return nil end
  return push(ch().recipes, { s = sid(), t = nowEpoch(), name = safeStr(name) or "a new recipe", prof = prof or Market.tradeSkill }, 500)
end
local function readTradeSkill()
  local name
  pcall(function()
    if C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo then
      local info = C_TradeSkillUI.GetBaseProfessionInfo(); name = info and safeStr(info.professionName)
    end
    if not name and C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillLine then name = safeStr((C_TradeSkillUI.GetTradeSkillLine())) end
    if not name and GetTradeSkillLine then name = safeStr((GetTradeSkillLine())) end
  end)
  return name
end

-- ── auction house ───────────────────────────────────────────────────────────
local HOURS = { [1] = 12, [2] = 24, [3] = 48 }   -- Mainline duration codes; Classic passes minutes
local function hoursOf(v)
  v = plainNum(v); if not v then return nil end
  if HOURS[v] then return HOURS[v] end
  if v >= 60 then return v / 60 end
  return v
end
local function itemFromLocation(location)
  local link, id, name, icon, count
  pcall(function()
    if C_Item and location then
      if C_Item.GetItemLink then link = C_Item.GetItemLink(location) end
      if C_Item.GetItemID then id = plainNum(C_Item.GetItemID(location)) end
      if C_Item.GetItemName then name = safeStr(C_Item.GetItemName(location)) end
      if C_Item.GetItemIcon then icon = plainNum(C_Item.GetItemIcon(location)) end
      if C_Item.GetStackCount then count = plainNum(C_Item.GetStackCount(location)) end
    end
  end)
  link = safeStr(link)
  if not name and link then name = link:match("|h%[(.-)%]|h") end
  if not id and link then id = tonumber(link:match("|Hitem:(%d+)")) end
  if not icon and id and C_Item and C_Item.GetItemIconByID then pcall(function() icon = plainNum(C_Item.GetItemIconByID(id)) end) end
  return name, id, icon, count
end
function Market.posted(row)
  if not ns.DB then return nil end
  row.s, row.t = sid(), nowEpoch()
  return push(ah().posted, row, 500)
end
function Market.bought(row)
  if not ns.DB then return nil end
  row.s, row.t = sid(), nowEpoch()
  return push(ah().bought, row, 500)
end
--- Emitter calls these when a mail is taken: the seller invoice (money) and the returned or won item.
function Market.sold(meta, money)
  if not ns.DB or not meta then return nil end
  local bid, buyout, deposit, cut = plainNum(meta.bid), plainNum(meta.buyout), plainNum(meta.deposit), plainNum(meta.cut)
  return push(ah().sold, { s = sid(), t = nowEpoch(), item = meta.item, buyer = meta.buyer, bid = bid, buyout = buyout,
    deposit = deposit, cut = cut, net = plainNum(money) }, 500)
end
function Market.mailItem(src, name, id, count, meta)
  if not ns.DB then return nil end
  if src == "Auction returned" then
    local reason = "expired"
    if meta and meta.subject then
      local pre = (_G.AUCTION_REMOVED_MAIL_SUBJECT or "Auction cancelled: %s"):gsub("%%s.*$", "")
      if pre ~= "" and meta.subject:sub(1, #pre) == pre then reason = "cancelled" end
    end
    return push(ah().returned, { s = sid(), t = nowEpoch(), item = safeStr(name), id = plainNum(id), count = plainNum(count) or 1, reason = reason }, 500)
  elseif src == "Auction won" then
    -- The price was recorded at bid or buy time; the mail brings the item and the seller. It belongs to a priced
    -- row by a fact only, never by "the newest row without a name" (docs/UX_PRAGMATIC.md 4.2):
    --   1. a priced row of the same item id, bought in this session or at most an hour ago, with that many units
    --      still to come (a commodity purchase arrives as several mails): its `delivered` grows, no row is added;
    --   2. a row named at the bid (named = "bid") of the same item id whose price is the amount this mail's invoice
    --      names, with no delivery yet: the mail brings its count (the bid knew one auction, not how many units);
    --   3. a row without an item (C_AuctionHouse.PlaceBid) whose price is the amount this mail's invoice names.
    -- A mail that fits neither is a row of its own with no price.
    local list = ah().bought
    local now, n, mid = nowEpoch(), plainNum(count) or 1, plainNum(id)
    local seller = meta and safeStr(meta.seller) or nil
    if mid then
      for i = math.max(1, #list - 60), #list do
        local b = list[i]
        -- (a row named at the bid is never confirmed by the item alone: a bid can be outbid and the mail then
        -- belongs to another purchase of that item. Only the invoice's amount confirms it, rule 2.)
        if b and b.kind ~= "mail" and b.named ~= "bid" and b.id == mid and ns.isMine(b) and plainNum(b.price) and now >= (b.t or 0)
          and (now - (b.t or 0) <= Market.DELIVERY_S or (b.s ~= nil and b.s == sid()))
          and (plainNum(b.count) or 1) - (plainNum(b.delivered) or 0) >= n then
          b.delivered = (plainNum(b.delivered) or 0) + n
          b.seller = b.seller or seller
          return b
        end
      end
    end
    local paid = meta and plainNum(meta.bid) or nil
    if paid and paid > 0 and mid then
      for i = #list, math.max(1, #list - 60), -1 do
        local b = list[i]
        if b and b.kind ~= "mail" and b.named == "bid" and b.id == mid and ns.isMine(b) and plainNum(b.price) == paid
          and (plainNum(b.delivered) or 0) == 0 and now >= (b.t or 0) and (now - (b.t or 0)) < 7 * 24 * 3600 then
          b.count, b.delivered = n, n
          b.seller = b.seller or seller
          return b
        end
      end
    end
    if paid and paid > 0 then
      for i = #list, math.max(1, #list - 60), -1 do
        local b = list[i]
        if b and b.kind ~= "mail" and not b.item and ns.isMine(b) and plainNum(b.price) == paid and (now - (b.t or 0)) < 7 * 24 * 3600 then
          b.item, b.id, b.seller, b.named = safeStr(name), mid, seller, "invoice"
          b.count, b.delivered = n, n
          return b
        end
      end
    end
    return push(list, { s = sid(), t = now, item = safeStr(name), id = mid, count = n, seller = seller, kind = "mail" }, 500)
  end
  return nil
end

-- hooks: Mainline C_AuctionHouse
local pendingCommodity = nil   -- { id, count, total } between StartCommoditiesPurchase and COMMODITY_PURCHASE_SUCCEEDED
if hooksecurefunc and C_AuctionHouse then
  if C_AuctionHouse.PostItem then
    hooksecurefunc(C_AuctionHouse, "PostItem", function(location, duration, quantity, bid, buyout)
      local name, id, icon, count = itemFromLocation(location)
      Market.posted({ item = name, id = id, icon = icon, count = plainNum(quantity) or count or 1, bid = plainNum(bid), buyout = plainNum(buyout), hours = hoursOf(duration), kind = "item" })
    end)
  end
  if C_AuctionHouse.PostCommodity then
    hooksecurefunc(C_AuctionHouse, "PostCommodity", function(location, duration, quantity, unitPrice)
      local name, id, icon = itemFromLocation(location)
      local q = plainNum(quantity) or 1
      Market.posted({ item = name, id = id, icon = icon, count = q, unit = plainNum(unitPrice), buyout = plainNum(unitPrice) and q * unitPrice or nil, hours = hoursOf(duration), kind = "commodity" })
    end)
  end
  if C_AuctionHouse.PlaceBid then
    hooksecurefunc(C_AuctionHouse, "PlaceBid", function(auctionID, amount)
      -- (the item, when the client still answers for this auction at the bid: then the row is named by a fact and
      -- not by a mail that comes later)
      local name, id
      pcall(function()
        local info = C_AuctionHouse.GetAuctionInfoByID and C_AuctionHouse.GetAuctionInfoByID(auctionID)
        if type(info) == "table" then
          id = plainNum(info.itemID) or (type(info.itemKey) == "table" and plainNum(info.itemKey.itemID)) or nil
          local link = safeStr(info.itemLink)
          name = link and link:match("|h%[(.-)%]|h") or nil
          if not name and id and C_Item and C_Item.GetItemNameByID then name = safeStr(C_Item.GetItemNameByID(id)) end
        end
      end)
      Market.bought({ auctionId = plainNum(auctionID), price = plainNum(amount), count = 1, kind = "item", item = name, id = name and id or nil, named = name and "bid" or nil })
    end)
  end
  if C_AuctionHouse.StartCommoditiesPurchase then
    hooksecurefunc(C_AuctionHouse, "StartCommoditiesPurchase", function(itemID, quantity)
      pendingCommodity = { id = plainNum(itemID), count = plainNum(quantity) or 1 }
    end)
  end
  if C_AuctionHouse.CancelAuction then
    hooksecurefunc(C_AuctionHouse, "CancelAuction", function(auctionID)
      Market.cancelled = Market.cancelled or {}; Market.cancelled[#Market.cancelled + 1] = plainNum(auctionID)
    end)
  end
end
-- hooks: Classic auction house
if hooksecurefunc and StartAuction and GetAuctionSellItemInfo then
  hooksecurefunc("StartAuction", function(minBid, buyout, runTime, stackSize, numStacks)
    local ok, name, texture, count, _, _, _, _, _, _, itemID = pcall(GetAuctionSellItemInfo)
    if not ok then return end
    Market.posted({ item = safeStr(name), id = plainNum(itemID), icon = plainNum(texture), count = (plainNum(stackSize) or plainNum(count) or 1) * (plainNum(numStacks) or 1),
      bid = plainNum(minBid), buyout = plainNum(buyout), hours = hoursOf(runTime), kind = "item" })
  end)
end
if hooksecurefunc and PlaceAuctionBid and GetAuctionItemInfo then
  hooksecurefunc("PlaceAuctionBid", function(listType, index, bid)
    local ok, name, texture, count, _, _, _, _, _, _, buyoutPrice, _, _, _, _, _, _, itemId = pcall(GetAuctionItemInfo, listType, index)
    if not ok then return end
    Market.bought({ item = safeStr(name), id = plainNum(itemId), icon = plainNum(texture), count = plainNum(count) or 1, price = plainNum(bid),
      buyout = plainNum(bid) == plainNum(buyoutPrice) or nil, kind = "item" })
  end)
end

-- ── events ───────────────────────────────────────────────────────────────────
local f = CreateFrame("Frame")
ns.eventFrames[#ns.eventFrames + 1] = f
for _, e in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE", "TRADE_SKILL_LIST_UPDATE", "CRAFT_SHOW", "CRAFT_CLOSE",
  "COMMODITY_PRICE_UPDATED", "COMMODITY_PURCHASE_SUCCEEDED", "COMMODITY_PURCHASE_FAILED", "CHAT_MSG_SYSTEM" }) do
  pcall(f.RegisterEvent, f, e)
end
f:SetScript("OnEvent", function(_, event, a1, a2)
  if event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_LIST_UPDATE" then Market.tradeSkill = readTradeSkill() or Market.tradeSkill
  elseif event == "CRAFT_SHOW" then
    local name; pcall(function() if GetCraftDisplaySkillLine then name = safeStr((GetCraftDisplaySkillLine())) end end)
    Market.tradeSkill = name or Market.tradeSkill
  elseif event == "TRADE_SKILL_CLOSE" or event == "CRAFT_CLOSE" then
    -- keep the name a little longer: the create line arrives after the window closes on some clients
    local was = Market.tradeSkill
    if C_Timer and C_Timer.After then C_Timer.After(5, function() if Market.tradeSkill == was then Market.tradeSkill = nil end end) end
  elseif event == "COMMODITY_PRICE_UPDATED" then
    if pendingCommodity then pendingCommodity.unit, pendingCommodity.total = plainNum(a1), plainNum(a2) end
  elseif event == "COMMODITY_PURCHASE_SUCCEEDED" then
    if pendingCommodity then
      local p = pendingCommodity; pendingCommodity = nil
      local name, icon
      pcall(function()
        if p.id and C_Item then
          if C_Item.GetItemNameByID then name = safeStr(C_Item.GetItemNameByID(p.id)) end
          if C_Item.GetItemIconByID then icon = plainNum(C_Item.GetItemIconByID(p.id)) end
        end
      end)
      Market.bought({ item = name, id = p.id, icon = icon, count = p.count, price = p.total, unit = p.unit, kind = "commodity" })
    end
  elseif event == "COMMODITY_PURCHASE_FAILED" then pendingCommodity = nil
  elseif event == "CHAT_MSG_SYSTEM" then
    -- Classic prints the recipe line; Mainline fires NEW_RECIPE_LEARNED, which Emitter handles and forwards here
    local msg = safeStr(a1)
    local fmt = _G.ERR_LEARN_RECIPE_S or "You have learned how to create a new item: %s."
    local pre = fmt:gsub("%%s.*$", "")
    if msg and pre ~= "" and msg:sub(1, #pre) == pre then
      local name = msg:sub(#pre + 1):gsub("%.$", "")
      if not (C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo) then Market.recipe(name) end
    end
  end
end)

-- ── rows for the panes (the auctions are a breakdown of Loot > Gold, Economy.lua; the crafts and recipes are listed in
-- Character > Professions, Progress.lua) ──────────────────────────────────────────────────────────────────────────
-- Rows for Loot > Gold > Auction house, newest first, plus the summary numbers (docs/UX_PRAGMATIC.md 4.2). One trade
-- is one row:
--   Posted   price = the buyout (else the starting bid), hours. A kind = "item" posting with count above 1 is that
--            many auctions posted in one call at the price of ONE of them (C_AuctionHouse.PostItem's quantity; the
--            Classic hook stores stack size times stacks with the price of one stack): row.lots, and the price is
--            never divided by the count.
--   Sold     price = what the buyer paid (the invoice's bid), never the mail's money, which also holds the deposit
--            that came back and lacks the house cut; cut and deposit ride along for the tooltip, and net only when
--            it is the invoice's own sum (bid - cut + deposit): on rows written before 0.9.46 it was the purse
--            change of several mails. count is the posted row's only when that posting is one lot sold whole at
--            this price (a commodity posting whose total is the price, or a posting of one); else there is none.
--            A posting that has its outcome is not a row of its own: the Sold row of a sale at its buyout (a commodity
--            posting: at its total) or the Expired or Cancelled row of the same item and count stands for it, and
--            carries when it was posted (row.postedAt). A posting with no outcome is a row only while its time has
--            not run out: after that its outcome is not recorded, and the auction is not open (sum.ended counts
--            them; Market.OPEN_H hours when the posting stored no duration).
--   Bought   a purchase with its price and its item. A row that has no item of its own (C_AuctionHouse.PlaceBid
--            knows only the auction; before 0.9.52 the name was a guess) takes it from the invoice of an "Auction
--            won" mail of the same session that names exactly its price (Market.invoiceNames). With no such mail it
--            is a bid nothing confirms: not a row, not counted as bought (sum.bids, sum.bidRows). The won mails of a purchase are not rows: a mail is taken up by the earliest
--            priced row of the same item id, bought in the same session or at most an hour before it, with that many
--            units still to come (rows written before 0.9.52 keep their mails in the list; from 0.9.52
--            Market.mailItem counts them on the priced row as `delivered`).
--   Collected  deliveries whose purchase is not stored: no price. Mails of one item taken within Market.FOLD_S of
--            each other in one session are one row with the units summed (row.mails).
--   Expired, Cancelled   a returned item.
--   Bid      a row named at the bid (named = "bid", C_AuctionHouse.PlaceBid) that no "Auction won" mail has
--            confirmed yet (no `delivered`): a bid can be outbid or refused, so it is listed as a bid with its
--            amount and is not a purchase: not in sum.bought, not in sum.spent (sum.openBids counts them), and no
--            delivery is counted on it. The won mail whose invoice names its amount makes it a Bought row.
-- row.guessed: a PlaceBid row named by the old "newest row without a name" rule; the pane shows no item for it.
function Market.guessed(r) return r.kind == "item" and r.auctionId ~= nil and r.item ~= nil and r.named == nil end
-- a bid named when it was placed that no won mail has confirmed: nothing stored says the auction was won
function Market.unconfirmed(r) return type(r) == "table" and r.named == "bid" and (plainNum(r.delivered) or 0) <= 0 end
Market.OPEN_H = 48
-- The item of each purchase row that has none of its own (no item, or a guessed one), by a stored fact: the loot row
-- of an "Auction won" mail of the same session whose invoice names exactly the row's price, taken at or after the
-- bid. One mail names one row, the newest such bid before it. A mail that a named purchase of the same item and
-- price accounts for names nothing. Returns { [bought row] = { item, id, icon, seller } }; nothing is written.
function Market.invoiceNames(bought)
  local by, any = {}, false
  for _, r in ipairs(bought) do
    if type(r) == "table" and r.kind ~= "mail" and plainNum(r.price) and r.s ~= nil then
      local b = by[r.s]
      if not b then b = { need = {}, named = {} }; by[r.s] = b end
      if r.item == nil or Market.guessed(r) then b.need[#b.need + 1] = r; any = true else b.named[#b.named + 1] = r end
    end
  end
  local out = {}
  if not any then return out end
  local used = {}
  for _, e in ipairs(ns.mine(ns.DB and ns.DB.loot and ns.DB.loot.log) or {}) do
    local b = type(e) == "table" and e.src == "Auction won" and e.s ~= nil and by[e.s] or nil
    local paid = b and type(e.mail) == "table" and plainNum(e.mail.bid) or nil
    if b and #b.need > 0 and paid and paid > 0 and type(e.item) == "string" and e.item ~= "" then
      local own = false
      for _, n in ipairs(b.named) do
        if not used[n] and plainNum(n.price) == paid and ((n.id ~= nil and n.id == e.id) or n.item == e.item) then used[n] = true; own = true; break end
      end
      if not own then
        for i = #b.need, 1, -1 do
          local r = b.need[i]
          if not out[r] and plainNum(r.price) == paid and (r.t or 0) <= (e.t or 0) then
            out[r] = { item = e.item, id = plainNum(e.id), icon = e.icon, seller = type(e.mail.seller) == "string" and e.mail.seller ~= "" and e.mail.seller or nil }
            break
          end
        end
      end
    end
  end
  return out
end
function Market.buildAuctions()
  if not ns.DB then return {}, {} end
  local all = ah(); local rows = {}
  -- the logged-in character's trades only (#23); loot.ah itself keeps every character's rows
  local a = { posted = ns.mine(all.posted), sold = ns.mine(all.sold), bought = ns.mine(all.bought), returned = ns.mine(all.returned) }
  local sum = { posted = #a.posted, sold = #a.sold, bought = 0, won = 0, returned = #a.returned, net = 0, spent = 0, cut = 0, sales = 0, deposit = 0 }
  -- sum.unowned: stored rows whose session record is gone (the desktop app picked the session up), so whose
  -- character is not known and which no list shows: the list of all time is then not every row
  sum.unowned, sum.unownedAt = 0, {}
  if ns.charGuid and ns.charGuid() then
    local sessions = ns.DB.sessions or {}
    for _, k in ipairs({ "posted", "sold", "bought", "returned" }) do
      for _, r in ipairs(all[k]) do
        if type(r) == "table" and (r.s == nil or sessions[r.s] == nil) then sum.unowned = sum.unowned + 1; sum.unownedAt[#sum.unownedAt + 1] = plainNum(r.t) or 0 end
      end
    end
  end
  -- (a row keeps its session id `s`, so Loot > Gold can list the auctions of a period)
  sum.bids, sum.bidRows, sum.ended, sum.endedRows, sum.openBids = 0, {}, 0, {}, 0
  local now = nowEpoch()
  local byItem = {}   -- item name -> its postings, oldest first, for the outcome of each
  local posts = {}
  for _, r in ipairs(a.posted) do
    local lots = (r.kind ~= "commodity" and (plainNum(r.count) or 1) > 1) or nil
    local row = { s = r.s, t = r.t, item = r.item, id = r.id, count = r.count, price = r.buyout or r.bid, what = "Posted", hours = plainNum(r.hours), note = "", lots = lots }
    -- (left: the auctions of the posting with no outcome yet; several auctions posted in one call end one by one)
    local p = { r = r, row = row, left = lots and (plainNum(r.count) or 1) or 1, lots = lots }
    posts[#posts + 1] = p
    if r.item then byItem[r.item] = byItem[r.item] or {}; table.insert(byItem[r.item], p) end
  end
  for _, r in ipairs(a.sold) do
    local bid = plainNum(r.bid)
    sum.net = sum.net + (plainNum(r.net) or 0); sum.cut = sum.cut + (plainNum(r.cut) or 0)
    sum.sales = sum.sales + (bid or 0); sum.deposit = sum.deposit + (plainNum(r.deposit) or 0)
    local count, postedAt
    if bid then
      for _, p in ipairs(byItem[r.item or ""] or {}) do
        if p.left > 0 and (p.r.t or 0) <= (r.t or 0) and plainNum(p.r.buyout) == bid then
          p.left = p.left - 1; postedAt = p.r.t
          -- (only a posting that is one lot names the count of its sale)
          if not p.lots then count = plainNum(p.r.count) end
          break
        end
      end
    end
    local cut, deposit, net = plainNum(r.cut), plainNum(r.deposit), plainNum(r.net)
    if not (bid and net and net == bid - (cut or 0) + (deposit or 0)) then net = nil end
    rows[#rows + 1] = { s = r.s, t = r.t, item = r.item, count = count, price = bid, cut = cut, deposit = deposit, net = net,
      what = "Sold", note = r.buyer or "", postedAt = postedAt }
  end
  -- a returned item ends the oldest posting of that item still without an outcome (one lot: of that count too)
  local returned = {}
  for _, r in ipairs(a.returned) do
    local row = { s = r.s, t = r.t, item = r.item, id = r.id, count = r.count, price = nil, what = r.reason == "cancelled" and "Cancelled" or "Expired", note = "" }
    for _, p in ipairs(byItem[r.item or ""] or {}) do
      if p.left > 0 and (p.r.t or 0) <= (r.t or 0) and (p.lots or (plainNum(p.r.count) or 1) == (plainNum(r.count) or 1)) then
        p.left = p.left - 1; row.postedAt = p.r.t
        break
      end
    end
    returned[#returned + 1] = row
  end
  -- (sum.posted: the postings that are rows)
  for _, p in ipairs(posts) do
    local over = now > (p.r.t or 0) + (plainNum(p.r.hours) or Market.OPEN_H) * 3600
    if p.left <= 0 then sum.posted = sum.posted - 1
    elseif over then sum.posted = sum.posted - 1; sum.ended = sum.ended + 1; sum.endedRows[#sum.endedRows + 1] = { t = plainNum(p.r.t) or 0, s = p.r.s }
    else rows[#rows + 1] = p.row end
  end
  local invoice = Market.invoiceNames(a.bought)
  local open = {}   -- item id (else name) -> priced rows with units still to come, oldest first
  local loose = {}  -- item id (else name) -> the newest Collected row of it
  for _, r in ipairs(a.bought) do
    local key, n = r.id or r.item, plainNum(r.count) or 1
    if r.kind == "mail" or not plainNum(r.price) then
      local hit
      if r.kind == "mail" and key then
        for _, p in ipairs(open[key] or {}) do
          if p.rem >= n and (r.t or 0) >= (p.r.t or 0) and ((r.t or 0) - (p.r.t or 0) <= Market.DELIVERY_S or (r.s ~= nil and r.s == p.r.s)) then hit = p; break end
        end
      end
      if hit then
        hit.rem = hit.rem - n
        if (hit.row.note or "") == "" and r.seller then hit.row.note = r.seller end
      elseif r.kind == "mail" then
        sum.won = sum.won + 1
        local l = key and loose[key]
        if l and l.s == r.s and math.abs((r.t or 0) - (l.last or 0)) <= Market.FOLD_S then
          l.count, l.mails, l.last = (plainNum(l.count) or 1) + n, l.mails + 1, r.t or 0
          if l.note ~= (r.seller or "") then l.note = "" end
        else
          l = { s = r.s, t = r.t, last = r.t or 0, item = r.item, id = r.id, count = n, price = nil, what = "Collected", note = r.seller or "", mails = 1 }
          rows[#rows + 1] = l
          if key then loose[key] = l end
        end
      else
        sum.won = sum.won + 1
        rows[#rows + 1] = { s = r.s, t = r.t, item = r.item, id = r.id, count = r.count, price = nil, what = "Bought", note = r.seller or "" }
      end
    else
      local inv = invoice[r]
      if not inv and (r.item == nil or Market.guessed(r)) then
        -- a bid with no item, and no auction mail of its session names its price: nothing says what it bought, or
        -- that it bought at all. It is not a row; what was paid is in the ledger's Spent.
        sum.bids = sum.bids + 1; sum.bidRows[#sum.bidRows + 1] = { t = plainNum(r.t) or 0, s = r.s }
      elseif Market.unconfirmed(r) then
        -- a bid on a named item with no won mail: a row that says "Bid", never a purchase (it may have been outbid)
        sum.openBids = sum.openBids + 1
        rows[#rows + 1] = { s = r.s, t = r.t, item = r.item, id = r.id, count = nil, price = r.price, what = "Bid", note = "" }
      else
        sum.bought = sum.bought + 1; sum.spent = sum.spent + r.price
        local row = { s = r.s, t = r.t, item = inv and inv.item or r.item, id = inv and inv.id or r.id, icon = inv and inv.icon or nil, count = r.count, price = r.price, what = "Bought",
          note = (inv and inv.seller) or ((not inv) and r.seller) or "", byInvoice = inv and true or nil }
        rows[#rows + 1] = row
        if key and not inv then
          open[key] = open[key] or {}
          table.insert(open[key], { r = r, row = row, rem = n - (plainNum(r.delivered) or 0) })
        end
      end
    end
  end
  for _, row in ipairs(returned) do rows[#rows + 1] = row end
  local order = {}
  for i, r in ipairs(rows) do order[r] = i end
  table.sort(rows, function(x, y) if (x.t or 0) ~= (y.t or 0) then return (x.t or 0) > (y.t or 0) end return order[x] > order[y] end)
  return rows, sum
end

-- Rows for the crafts and recipes (the suite's contract checks; Character > Professions lists them, Progress.lua)
function Market.buildCrafts()
  if not ns.DB then return {}, {} end
  local c = ch(); local rows = {}
  for _, r in ipairs(c.crafts) do rows[#rows + 1] = { t = r.t, item = r.item, count = r.count, prof = r.prof or "", zone = r.zone or "", x = r.x, y = r.y, what = "Crafted" } end
  for _, r in ipairs(c.recipes) do rows[#rows + 1] = { t = r.t, item = r.name, count = nil, prof = r.prof or "", zone = "", what = "Recipe learned" } end
  table.sort(rows, function(a, b) return (a.t or 0) > (b.t or 0) end)
  local byProf = {}
  for _, r in ipairs(c.crafts) do local p = r.prof or "Unknown"; byProf[p] = (byProf[p] or 0) + (r.count or 1) end
  return rows, { crafts = #c.crafts, recipes = #c.recipes, byProf = byProf }
end
