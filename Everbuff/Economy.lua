-- Everbuff.GG · Economy.lua - gold over the journey (the Gold pane of the LOOT tab).
--
-- Gold pace and the cost of leveling: a staple journey metric a pure combat recorder never touches.
-- Reads the running totals Emitter captures from PLAYER_MONEY (balance / looted / gained / spent).
-- Since 2026-09-25 this is not a top-level tab: it is the Gold pane of the Loot tab (ns.BuildEconomyPane).

local ADDON, ns = ...
local UI = ns.UI
local C = ns.UI.C

local function fmtMoney(c)
  c = math.floor(tonumber(c) or 0)
  local g, s, cp = math.floor(c / 10000), math.floor((c % 10000) / 100), c % 100
  local out = {}
  if g > 0 then out[#out + 1] = g .. "g" end
  if s > 0 then out[#out + 1] = s .. "s" end
  if cp > 0 or #out == 0 then out[#out + 1] = cp .. "c" end
  return table.concat(out, " ")
end

local function refresh(c)
  if not c or not c.cBalance then return end
  local g = (ns.DB and ns.DB.loot.gold) or {}
  c.cBalance.value:SetText(fmtMoney(g.balance or 0))
  c.cLooted.value:SetText(fmtMoney(g.looted or 0))
  c.cGained.value:SetText(fmtMoney(g.gained or 0))
  c.cSpent.value:SetText(fmtMoney(g.spent or 0))
  local gained, looted, sold = tonumber(g.gained) or 0, tonumber(g.looted) or 0, tonumber(g.sold) or 0
  local auctions, mail = tonumber(g.auctionSales) or 0, tonumber(g.mail) or 0
  c.cBalance.sub:SetText("current purse")
  c.cLooted.sub:SetText("coin picked up from mobs and chests")
  c.cGained.sub:SetText(("looted %s  ·  sold %s  ·  auctions %s  ·  mail %s  ·  other %s"):format(
    fmtMoney(looted), fmtMoney(sold), fmtMoney(auctions), fmtMoney(mail), fmtMoney(math.max(0, gained - looted - sold - auctions - mail))))
  c.cSpent.sub:SetText(("repairs %s  ·  vendor %s  ·  training %s  ·  flights %s  ·  auctions %s  ·  mail %s"):format(
    fmtMoney(g.repairs or 0), fmtMoney(g.vendor or 0), fmtMoney(g.training or 0), fmtMoney(g.flights or 0), fmtMoney(g.auctions or 0), fmtMoney(g.mailSpent or 0)))
  local net = (tonumber(g.gained) or 0) - (tonumber(g.spent) or 0)
  local ses = (ns.Recorder and ns.Recorder.current and ns.Recorder.current()) or {}
  local elapsed = (ses.startedEpoch and ((GetServerTime and GetServerTime()) or time()) - ses.startedEpoch) or 0
  local snet = (tonumber(ses.gained) or 0) - (tonumber(ses.spent) or 0)
  if elapsed >= 120 and snet ~= 0 then
    local perHr = snet / (elapsed / 3600)
    c.cNet.sub:SetText(("gained minus spent  ·  %s%s per hour this session"):format(perHr < 0 and "-" or "+", fmtMoney(math.abs(perHr))))
  else
    c.cNet.sub:SetText("gained minus spent  ·  per-hour rate after a few minutes")
  end
  c.cNet.value:SetText((net < 0 and "-" or "") .. fmtMoney(math.abs(net)))
  c.cNet.value:SetTextColor(net < 0 and C.red[1] or C.green[1], net < 0 and C.red[2] or C.green[2], net < 0 and C.red[3] or C.green[3])
end

-- Build the Gold pane into `pane` (a UI.Tabs pane). Returns a refresh function for the host to call.
function ns.BuildEconomyPane(pane)
  local content = pane
  local function card(x, y, w, h, label, valueColor)
    local p = UI.Panel(content); p:SetSize(w, h); p:SetPoint("TOPLEFT", x, y)
    p.title = UI.FS(p, "GameFontNormalSmall", C.dim); p.title:SetPoint("TOPLEFT", 12, -9); p.title:SetText(label)
    p.value = UI.FS(p, "GameFontNormalLarge", valueColor or C.ink); if UI.VALUE_FONT then p.value:SetFontObject(UI.VALUE_FONT) end; p.value:SetPoint("TOPLEFT", 12, -28)
    p.sub = UI.FS(p, "GameFontHighlightSmall", C.dim); p.sub:SetPoint("TOPLEFT", 12, -52); p.sub:SetWidth(w - 20); p.sub:SetJustifyH("LEFT")
    return p
  end
  local CW, CH, GAP, X0, Y0 = 220, 80, 12, 4, -8
  local col = { X0, X0 + CW + GAP, X0 + 2 * (CW + GAP) }
  content.cBalance = card(col[1], Y0, CW, CH, "BALANCE", C.gold)
  content.cLooted  = card(col[2], Y0, CW, CH, "LOOTED", C.gold)
  content.cGained  = card(col[3], Y0, CW, CH, "GAINED", C.green)
  local Y1 = Y0 - CH - GAP
  content.cSpent   = card(col[1], Y1, CW, CH, "SPENT", C.red)
  content.cNet     = card(col[2], Y1, CW, CH, "NET THIS SESSION", C.green)

  local note = UI.FS(content, "GameFontDisableSmall", C.dim); note:SetPoint("TOPLEFT", X0, Y1 - CH - 16)
  note:SetWidth(680); note:SetJustifyH("LEFT")
  note:SetText("Gold in and out since this session began. Sinks are attributed by the window that was open when gold left: repairs, vendor, trainer, flight master, auction house, mailbox. Coin looted, auction proceeds and mailed gold are attributed to their source in the Loot tab. On the beta these totals are per session until SavedVariables persistence is fixed.")
  refresh(content)
  return function() refresh(content) end
end

-- LOOT / Gold pane (the Loot host is declared by Emitter.lua with the Items pane)
local goldRefresh
UI.registerPane("Loot", 2, "Gold", function(content) goldRefresh = ns.BuildEconomyPane(content) end, function() if goldRefresh then goldRefresh() end end)

-- ── test exports: headless luajit tests in tests/ read these; no effect in-game ──
ns._test = ns._test or {}
ns._test.economyFmtMoney = fmtMoney
