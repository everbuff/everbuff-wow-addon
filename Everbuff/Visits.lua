-- Everbuff.GG · Visits.lua - every visit to a town service is play (everbuff-business #39, approved 2026-09-29).
--
-- WHAT: one story event per visit to the auction house, the mailbox, a merchant, the bank or a trainer, written
-- when the window closes. A session where the player logs in, looks at the auction house and logs out now holds
-- gameplay, so it is captured (V5 counts these kinds; bookkeeping kinds like LOGIN and ZONE do not count).
--
-- WHERE IT LIVES (schema 2, additive): story.events[]
--   { t (opened), s, kind, closed, text, zone, sub?, map?, x?, y? } plus
--   AUCTION { searches, posts, bids, buys }   (the trades themselves stay in loot.ah, written by Market)
--   MAIL    { items, money }                   (the rows stay in loot, written by Emitter and Market)
--   VENDOR  { sold, bought, repair }
--   BANK    {}
--   TRAINER { learned }
--
-- HOW: its own event frame (Emitter's handler sits at Lua's 60-upvalue limit), hooks counted only while the
-- window is open, and a visit still open at logout is closed then, before WoW writes the save file.

local ADDON, ns = ...

local Visits = { open = nil }
ns.Visits = Visits

local KINDS = {
  AUCTION_HOUSE_SHOW = "AUCTION", AUCTION_HOUSE_CLOSED = "AUCTION",
  MAIL_SHOW = "MAIL", MAIL_CLOSED = "MAIL",
  MERCHANT_SHOW = "VENDOR", MERCHANT_CLOSED = "VENDOR",
  BANKFRAME_OPENED = "BANK", BANKFRAME_CLOSED = "BANK",
  TRAINER_SHOW = "TRAINER", TRAINER_CLOSED = "TRAINER",
}
local OPENS = { AUCTION_HOUSE_SHOW = true, MAIL_SHOW = true, MERCHANT_SHOW = true, BANKFRAME_OPENED = true, TRAINER_SHOW = true }
local LABEL = { AUCTION = "Auction house", MAIL = "Mailbox", VENDOR = "Merchant", BANK = "Bank", TRAINER = "Trainer" }

local function isFinite(v) return v == v and v ~= math.huge and v ~= -math.huge end
local function plainNum(v)
  if type(v) ~= "number" or (issecretvalue and issecretvalue(v)) then return nil end
  local ok, fin = pcall(isFinite, v)
  return (ok and fin) and v or nil
end
local function nowEpoch() return (GetServerTime and GetServerTime()) or time() end
local function money() return plainNum(GetMoney and GetMoney()) or 0 end

local function where()
  local L = { zone = GetRealZoneText and GetRealZoneText() or nil, sub = GetSubZoneText and GetSubZoneText() or nil }
  if L.sub == "" then L.sub = nil end
  pcall(function()
    if C_Map and C_Map.GetBestMapForUnit then
      local m = C_Map.GetBestMapForUnit("player")
      L.map = plainNum(m)
      local p = m and C_Map.GetPlayerMapPosition(m, "player")
      if p then L.x, L.y = plainNum(p.x), plainNum(p.y) end
    end
  end)
  return L
end

local function plural(n, one, many) return ("%d %s"):format(n, n == 1 and one or many) end

-- what the timeline says about a visit
local function words(v)
  local parts = {}
  if v.kind == "AUCTION" then
    if v.searches > 0 then parts[#parts + 1] = plural(v.searches, "search", "searches") end
    if v.posts > 0 then parts[#parts + 1] = plural(v.posts, "post", "posts") end
    if v.bids > 0 then parts[#parts + 1] = plural(v.bids, "bid", "bids") end
    if v.buys > 0 then parts[#parts + 1] = plural(v.buys, "buy", "buys") end
  elseif v.kind == "MAIL" then
    if v.items > 0 then parts[#parts + 1] = plural(v.items, "item", "items") end
    if v.money > 0 then parts[#parts + 1] = "money taken" end
  elseif v.kind == "VENDOR" then
    if v.sold > 0 then parts[#parts + 1] = plural(v.sold, "sold", "sold") end
    if v.bought > 0 then parts[#parts + 1] = plural(v.bought, "bought", "bought") end
    if v.repair > 0 then parts[#parts + 1] = "repaired" end
  elseif v.kind == "TRAINER" then
    if v.learned > 0 then parts[#parts + 1] = plural(v.learned, "skill learned", "skills learned") end
  end
  return LABEL[v.kind] .. (#parts > 0 and (": " .. table.concat(parts, ", ")) or "")
end

function Visits.begin(kind)
  if Visits.open then Visits.finish() end   -- a new window replaces one the client closed without an event
  Visits.open = { kind = kind, t = nowEpoch(), s = ns.DB and ns.DB.active, moneyAt = money(), where = where(),
    searches = 0, posts = 0, bids = 0, buys = 0, items = 0, money = 0, sold = 0, bought = 0, repair = 0, learned = 0,
    repairCost = kind == "VENDOR" and GetRepairAllCost and plainNum((GetRepairAllCost())) or nil }
end

-- count something done during the open visit of `kind`
function Visits.count(kind, field, n)
  local v = Visits.open
  if v and v.kind == kind then v[field] = v[field] + (n or 1) end
end

function Visits.finish()
  local v = Visits.open
  Visits.open = nil
  if not v or not ns.DB then return nil end
  if v.kind == "MAIL" then v.money = math.max(0, money() - v.moneyAt) end
  local L = v.where
  local rec = { t = v.t, s = v.s or ns.DB.active, kind = v.kind, closed = nowEpoch(), text = words(v),
    zone = L.zone, sub = L.sub, map = L.map, x = L.x, y = L.y }
  if v.kind == "AUCTION" then rec.searches, rec.posts, rec.bids, rec.buys = v.searches, v.posts, v.bids, v.buys
  elseif v.kind == "MAIL" then rec.items, rec.money = v.items, v.money
  elseif v.kind == "VENDOR" then rec.sold, rec.bought, rec.repair = v.sold, v.bought, v.repair
  elseif v.kind == "TRAINER" then rec.learned = v.learned end
  ns.DB.story = ns.DB.story or {}
  ns.DB.story.events = ns.DB.story.events or {}
  local log = ns.DB.story.events
  log[#log + 1] = rec
  while #log > 500 do table.remove(log, 1) end
  return rec
end

-- ── hooks: counted only while the matching window is open ──
local function hook(tbl, name, fn)
  if tbl and type(tbl[name]) == "function" and hooksecurefunc then hooksecurefunc(tbl, name, fn) end
end
local function hookG(name, fn)
  if type(_G[name]) == "function" and hooksecurefunc then hooksecurefunc(name, fn) end
end
function Visits.wire()
  -- auction house: searches on either API, trades as Market records them
  hook(C_AuctionHouse, "SendBrowseQuery", function() Visits.count("AUCTION", "searches") end)
  hook(C_AuctionHouse, "SendSearchQuery", function() Visits.count("AUCTION", "searches") end)
  hookG("QueryAuctionItems", function() Visits.count("AUCTION", "searches") end)
  hook(ns.Market, "posted", function() Visits.count("AUCTION", "posts") end)
  hook(ns.Market, "bought", function(row) Visits.count("AUCTION", (row and row.auctionId and not row.item) and "bids" or "buys") end)
  -- mailbox
  hookG("TakeInboxItem", function() Visits.count("MAIL", "items") end)
  -- merchant
  hookG("BuyMerchantItem", function() Visits.count("VENDOR", "bought") end)
  hook(C_Container, "UseContainerItem", function() Visits.count("VENDOR", "sold") end)
  hookG("UseContainerItem", function() Visits.count("VENDOR", "sold") end)
  hookG("RepairAllItems", function()
    local v = Visits.open
    if v and v.kind == "VENDOR" then v.repair = v.repairCost or 1 end
  end)
  -- trainer
  hookG("BuyTrainerService", function() Visits.count("TRAINER", "learned") end)
end

local f = CreateFrame("Frame")
for ev in pairs(KINDS) do f:RegisterEvent(ev) end
f:RegisterEvent("PLAYER_LOGOUT")
f:RegisterEvent("PLAYER_LEAVING_WORLD")
f:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGOUT" or event == "PLAYER_LEAVING_WORLD" then Visits.finish(); return end
  local kind = KINDS[event]
  if OPENS[event] then Visits.begin(kind)
  elseif Visits.open and Visits.open.kind == kind then Visits.finish() end
end)
Visits.wire()
