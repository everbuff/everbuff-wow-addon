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
--   loot.ah.bought[]    { s, t, item?, id?, count, price, auctionId?, kind }
--   loot.ah.sold[]      { s, t, item, buyer?, bid, buyout, deposit, cut, net }   (from the seller invoice mail)
--   loot.ah.returned[]  { s, t, item, count, reason = "expired" | "cancelled" }   (from the returned-item mail)
-- Every row carries the addon session id `s` and a server-time `t`.
--
-- HOW: hooks on the post, bid and buy functions of whichever auction house API the client has (the Mainline
-- C_AuctionHouse with commodities, or the Classic StartAuction and PlaceAuctionBid), the tradeskill window
-- events for the profession behind a craft, and the mail invoice that Emitter already parses. Every value the
-- client could hide goes through the guards; nothing is recorded from a secret.

local ADDON, ns = ...
local UI = ns.UI
local C = UI and UI.C or {}

local Market = { tradeSkill = nil }
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
    -- the price was recorded at bid or buy time; the mail confirms the item and the seller
    local list = ah().bought
    for i = #list, math.max(1, #list - 20), -1 do
      local b = list[i]
      if b and not b.item and (nowEpoch() - (b.t or 0)) < 7 * 24 * 3600 then b.item = safeStr(name); b.id = plainNum(id); b.seller = meta and meta.seller; return b end
    end
    return push(list, { s = sid(), t = nowEpoch(), item = safeStr(name), id = plainNum(id), count = plainNum(count) or 1, seller = meta and meta.seller, kind = "mail" }, 500)
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
      Market.bought({ auctionId = plainNum(auctionID), price = plainNum(amount), count = 1, kind = "item" })
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

-- ── panes: LOOT · Auctions and CHARACTER · Crafting ─────────────────────────
local function fmtMoney(c)
  c = plainNum(c) or 0
  local g, s, cp = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
  if g > 0 then return ("%dg %02ds %02dc"):format(g, s, cp) elseif s > 0 then return ("%ds %02dc"):format(s, cp) end
  return ("%dc"):format(cp)
end
local function fmtWhen(t) t = plainNum(t); if not t then return "" end; return date("%a %H:%M", t) end
local function makeList(pane, cols)
  local hdr = CreateFrame("Frame", nil, pane); hdr:SetPoint("TOPLEFT", 2, -26); hdr:SetSize(660, 16)
  for _, c in ipairs(cols) do
    local fs = UI.FS(hdr, "GameFontNormalSmall"); fs:SetPoint("LEFT", c[2], 0); fs:SetWidth(c[3]); fs:SetJustifyH("LEFT")
    fs:SetText(c[4]:upper()); fs:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
  end
  local summary = UI.FS(pane, "GameFontHighlightSmall", C.gold); summary:SetPoint("TOPLEFT", 2, -6); summary:SetWidth(650); summary:SetJustifyH("LEFT")
  local sf, child = UI.ScrollChild(pane)
  sf:SetPoint("TOPLEFT", 0, -46); sf:SetPoint("BOTTOMRIGHT", -22, 2)
  child.rows = {}
  local L = { summary = summary, child = child }
  L.render = function(rows, fill, emptyText)
    local y, idx = 0, 0
    for _, item in ipairs(rows) do
      idx = idx + 1
      local row = child.rows[idx]
      if not row then
        row = CreateFrame("Frame", nil, child); row:SetHeight(18); row:SetPoint("RIGHT", child, "RIGHT", 0, 0); row.c = {}
        for _, c in ipairs(cols) do
          local fs = UI.FS(row, "GameFontHighlightSmall"); fs:SetPoint("LEFT", c[2], 0); fs:SetWidth(c[3]); fs:SetJustifyH("LEFT"); row.c[c[1]] = fs
        end
        child.rows[idx] = row
      end
      row:SetPoint("TOPLEFT", 0, -y); row:Show(); fill(row, item); y = y + 18
    end
    for j = idx + 1, #child.rows do child.rows[j]:Hide() end
    if idx == 0 then
      child.empty = child.empty or (function() local fs = UI.FS(child, "GameFontDisableSmall"); fs:SetPoint("TOPLEFT", 0, 0); return fs end)()
      child.empty:SetText(emptyText); child.empty:Show()
    elseif child.empty then child.empty:Hide() end
  end
  return L
end

--- Rows for the Auctions pane, newest first, plus the summary numbers.
function Market.buildAuctions()
  if not ns.DB then return {}, {} end
  local all = ah(); local rows = {}
  -- the logged-in character's trades only (#23); loot.ah itself keeps every character's rows
  local a = { posted = ns.mine(all.posted), sold = ns.mine(all.sold), bought = ns.mine(all.bought), returned = ns.mine(all.returned) }
  local sum = { posted = #a.posted, sold = #a.sold, bought = #a.bought, returned = #a.returned, net = 0, spent = 0, cut = 0 }
  for _, r in ipairs(a.posted) do rows[#rows + 1] = { t = r.t, item = r.item, count = r.count, price = r.buyout or r.bid, what = "Posted", note = r.hours and (r.hours .. " h") or "" } end
  for _, r in ipairs(a.sold) do sum.net = sum.net + (r.net or 0); sum.cut = sum.cut + (r.cut or 0); rows[#rows + 1] = { t = r.t, item = r.item, count = 1, price = r.net, what = "Sold", note = r.buyer or "", good = true } end
  for _, r in ipairs(a.bought) do sum.spent = sum.spent + (r.price or 0); rows[#rows + 1] = { t = r.t, item = r.item or "(item arrives by mail)", count = r.count, price = r.price, what = "Bought", note = r.seller or "" } end
  for _, r in ipairs(a.returned) do rows[#rows + 1] = { t = r.t, item = r.item, count = r.count, price = nil, what = r.reason == "cancelled" and "Cancelled" or "Expired", note = "", bad = true } end
  table.sort(rows, function(x, y) return (x.t or 0) > (y.t or 0) end)
  return rows, sum
end
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

local auctionsL, craftsL
local function renderAuctions()
  if not auctionsL then return end
  local rows, sum = Market.buildAuctions()
  auctionsL.summary:SetText(("posted %d  ·  sold %d for %s (house cut %s)  ·  bought %d for %s  ·  returned %d"):format(
    sum.posted, sum.sold, fmtMoney(sum.net), fmtMoney(sum.cut), sum.bought, fmtMoney(sum.spent), sum.returned))
  auctionsL.render(rows, function(row, r)
    row.c.when:SetText(fmtWhen(r.t)); row.c.when:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
    row.c.what:SetText(r.what); if r.good then row.c.what:SetTextColor(C.green[1], C.green[2], C.green[3]) elseif r.bad then row.c.what:SetTextColor(C.red[1], C.red[2], C.red[3]) else row.c.what:SetTextColor(C.ink[1], C.ink[2], C.ink[3]) end
    row.c.item:SetText(r.item or ""); row.c.item:SetTextColor(C.ink[1], C.ink[2], C.ink[3])
    row.c.count:SetText(r.count and tostring(r.count) or ""); row.c.count:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
    row.c.price:SetText(r.price and fmtMoney(r.price) or ""); row.c.price:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    row.c.note:SetText(r.note or ""); row.c.note:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
  end, "No auction activity yet. Post, buy or sell something and it shows up here with the prices.")
end
local function renderCrafts()
  if not craftsL then return end
  local rows, sum = Market.buildCrafts()
  local parts = {}
  for p, n in pairs(sum.byProf) do parts[#parts + 1] = ("%s %d"):format(p, n) end
  table.sort(parts)
  craftsL.summary:SetText(("%d crafts  ·  %d recipes learned%s"):format(sum.crafts, sum.recipes, #parts > 0 and ("  ·  " .. table.concat(parts, "  ·  ")) or ""))
  craftsL.render(rows, function(row, r)
    row.c.when:SetText(fmtWhen(r.t)); row.c.when:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
    row.c.what:SetText(r.what); row.c.what:SetTextColor(C.ink[1], C.ink[2], C.ink[3])
    row.c.item:SetText(r.item or ""); row.c.item:SetTextColor(C.ink[1], C.ink[2], C.ink[3])
    row.c.count:SetText(r.count and tostring(r.count) or ""); row.c.count:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
    row.c.prof:SetText(r.prof or ""); row.c.prof:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
    row.c.zone:SetText(r.zone or ""); row.c.zone:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
    row.c.coords:SetText((r.x and r.y) and ("%.1f, %.1f"):format(r.x * 100, r.y * 100) or ""); row.c.coords:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
  end, "No crafts yet. Make something and it shows up here with the profession and where you made it.")
end
if UI and UI.registerPane then
  UI.registerPane("Loot", 3, "Auctions", function(content)
    auctionsL = makeList(content, { { "when", 0, 70, "When" }, { "what", 74, 64, "What" }, { "item", 142, 220, "Item" }, { "count", 366, 40, "Qty" }, { "price", 410, 110, "Price" }, { "note", 524, 130, "Who / how long" } })
    renderAuctions()
  end, renderAuctions)
  UI.registerPane("Character", 4, "Crafting", function(content)
    craftsL = makeList(content, { { "when", 0, 70, "When" }, { "what", 74, 90, "What" }, { "item", 168, 190, "Item" }, { "count", 362, 36, "Qty" }, { "prof", 402, 100, "Profession" }, { "zone", 506, 110, "Location" }, { "coords", 620, 60, "Coords" } })
    renderCrafts()
  end, renderCrafts)
end
