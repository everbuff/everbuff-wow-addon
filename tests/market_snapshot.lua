-- The market snapshot (everbuff-wow-addon #58): Auctionator's prices and the client's vendor prices copied into
-- EverbuffDB.market, silently. Loaded by tests/run_tests.lua:
--   dofile("tests/market_snapshot.lua")({ check = check, M = M, ns = ns })
-- Auctionator is faked with the shapes of its real database (dbversion 8, per-day `h`/`a` keyed by day strings, `m`
-- the latest lowest buyout per unit, a `version` key in the realm table). Cases:
--   copy       every plain item id with a price is written as "m/a/d" with its own newest day; a pet key, an item with
--              no price or no day, and the `version` key are not items; skipped counts the non-id keys
--   cbor       an item still CBOR-encoded (an older Auctionator) and a realm left serialized at logout are decoded
--   vendor     vendor prices come only from the client: a known item at once, an unloaded one when
--              GET_ITEM_INFO_RECEIVED says it loaded, a failed load never; kept across snapshots, never asked twice
--   timing     the copy waits AFTER_CLOSE after the AH closes, is built over several frames, replaces the stored
--              snapshot only once complete, pauses in combat; a logout at the auctioneer finishes it in one go
--   silent     no chat line and no Lua error from any of it; with no Auctionator nothing is written
-- The suite's market key, Auctionator globals and combat flag are put back at the end.
return function(P)
  local check, M, ns = P.check, P.M, P.ns
  local Snap = ns.Market.snap
  local function eq(name, got, want) check(name, got == want, ("got %s, want %s"):format(tostring(got), tostring(want))) end
  local function drain(n) for _ = 1, n or 200 do if #M.timers == 0 then return end M.runTimers() end end

  local keep = { market = ns.DB.market, A = rawget(_G, "Auctionator"), APD = rawget(_G, "AUCTIONATOR_PRICE_DATABASE"),
    enc = rawget(_G, "C_EncodingUtil"), combat = M.inCombat, print = print, chunk = Snap.CHUNK, sell = M.sellPrice }
  local said = 0
  _G.print = function() said = said + 1 end
  local errs0 = #M.errors

  -- a CBOR stand-in: the test's "encoded" values are tables wrapped in a marker string
  local enc = {}
  _G.C_EncodingUtil = { DeserializeCBOR = function(s) local t = enc[s]; if not t then error("bad cbor") end return t end }
  local function cbor(t) local s = "CBOR#" .. tostring(t); enc[s] = t; return s end

  local function realm()
    return {
      version = 2,
      ["2589"] = { m = 18, a = { ["2517"] = 29574 }, h = { ["2517"] = 18 }, l = {} },                    -- Linen Cloth
      ["3575"] = { m = 309, a = { ["2504"] = 10, ["2517"] = 8303 }, h = { ["2504"] = 350, ["2517"] = 309 }, l = {} },
      ["10620"] = { m = 2173, h = { ["2509"] = 2200 }, l = {} },                                           -- seen earlier only, no count
      [12359] = { m = 2420, a = { [2516] = 6724 }, h = { [2516] = 2420 }, l = {} },                       -- number keys
      ["8959"] = cbor({ m = 185, a = { ["2517"] = 332 }, h = { ["2517"] = 185, ["2514"] = 169 }, l = {} }), -- per-item CBOR
      ["999"] = { a = { ["2517"] = 1 }, h = { ["2517"] = 5 } },                                             -- no m: no price
      ["998"] = { m = 50, a = {}, h = {} },                                                                 -- no day
      ["p:1234:25:3"] = { m = 9000, a = { ["2517"] = 1 }, h = { ["2517"] = 9000 } },                        -- a pet key
    }
  end
  local db = realm()
  _G.Auctionator = { State = { CurrentRealm = "PvE Horde" }, Database = { db = db }, Constants = { SCAN_DAY_0 = 1577833200 } }
  M.sellPrice = { [2589] = 13, [3575] = 200, [8959] = 0 }   -- 10620 and 12359 not loaded yet; 8959 sells for nothing
  ns.DB.market = nil
  Snap.CHUNK = 3                                             -- several frames for the eight keys

  -- ── no snapshot while the AH is open; the copy comes AFTER_CLOSE after it closes ──
  M.fire("AUCTION_HOUSE_SHOW")
  drain()
  eq("market: nothing is copied while the AH is open", ns.DB.market, nil)
  M.fire("AUCTION_HOUSE_CLOSED")
  eq("market: the copy waits after the close (one timer queued)", #M.timers >= 1, true)
  M.runTimers()   -- the AFTER_CLOSE timer: the job starts
  M.runTimers()   -- first chunk
  eq("market: a half-built copy is not stored", ns.DB.market and ns.DB.market.items, nil)
  drain()
  local mk = ns.DB.market
  check("market: the copy is stored once complete", type(mk) == "table" and type(mk.items) == "table")
  mk = mk or { items = {}, vendor = {} }
  eq("market: src", mk.src, "Auctionator")
  eq("market: realm", mk.realm, "PvE Horde")
  eq("market: day0 is Auctionator's", mk.day0, 1577833200)
  eq("market: at is the server time", mk.at, M.epoch)
  eq("market: Linen Cloth", mk.items[2589], "18/29574/2517")
  eq("market: Iron Bar takes its newest day's count", mk.items[3575], "309/8303/2517")
  eq("market: an item seen earlier keeps its day, no count", mk.items[10620], "2173//2509")
  eq("market: number keys are read too", mk.items[12359], "2420/6724/2516")
  eq("market: a CBOR item is decoded", mk.items[8959], "185/332/2517")
  eq("market: no m is no price", mk.items[999], nil)
  eq("market: no day is not written", mk.items[998], nil)
  eq("market: n counts the written items", mk.n, 5)
  eq("market: skipped counts the pet key only (not version)", mk.skipped, 1)
  eq("market: scanDay is the newest day", mk.scanDay, 2517)
  local strKeys = 0
  for k in pairs(mk.items) do if type(k) ~= "number" then strKeys = strKeys + 1 end end
  eq("market: items are keyed by number", strKeys, 0)

  -- ── vendor prices: only from the client ──
  eq("market: vendor of a loaded item", mk.vendor[2589], 13)
  eq("market: vendor 0 is a price", mk.vendor[8959], 0)
  eq("market: an unloaded item has no vendor price yet", mk.vendor[10620], nil)
  eq("market: an unloaded item has no vendor price yet (2)", mk.vendor[12359], nil)
  M.sellPrice[10620] = 250
  M.fire("GET_ITEM_INFO_RECEIVED", 10620, true)
  eq("market: the vendor price fills when the item loads", mk.vendor[10620], 250)
  M.sellPrice[12359] = 600
  M.fire("GET_ITEM_INFO_RECEIVED", 12359, false)
  eq("market: a failed load writes nothing", mk.vendor[12359], nil)
  M.fire("GET_ITEM_INFO_RECEIVED", 4242, true)
  eq("market: an item it never asked for is not written", mk.vendor[4242], nil)

  -- ── a second visit: the snapshot is replaced whole, the vendor map kept and completed ──
  db["2589"] = { m = 21, a = { ["2518"] = 30000 }, h = { ["2518"] = 21 }, l = {} }
  db["3575"] = nil
  M.sellPrice[2589] = 9999    -- a vendor price is never read again once known
  M.fire("AUCTION_HOUSE_SHOW"); M.fire("AUCTION_HOUSE_CLOSED")
  drain()
  mk = ns.DB.market
  eq("market: the new copy has the new price", mk.items[2589], "21/30000/2518")
  eq("market: an item gone from Auctionator is gone from the copy", mk.items[3575], nil)
  eq("market: vendor prices are kept", mk.vendor[3575], 200)
  eq("market: a known vendor price is not asked again", mk.vendor[2589], 13)
  eq("market: the next snapshot asks again for one still missing", mk.vendor[12359], 600)
  eq("market: scanDay moves", mk.scanDay, 2518)

  -- ── combat: the copy and the vendor reads wait ──
  db["4306"] = { m = 120, a = { ["2518"] = 50 }, h = { ["2518"] = 120 }, l = {} }
  M.sellPrice[4306] = 150
  M.inCombat = true
  M.fire("AUCTION_HOUSE_SHOW"); M.fire("AUCTION_HOUSE_CLOSED")
  for _ = 1, 10 do M.runTimers() end
  eq("market: nothing is copied in combat", ns.DB.market.items[4306], nil)
  M.inCombat = false
  drain()
  eq("market: the copy finishes after combat", ns.DB.market.items[4306], "120/50/2518")
  eq("market: and its vendor price", ns.DB.market.vendor[4306], 150)

  -- ── logout at the auctioneer: finished in one go, no frame needed ──
  db["2840"] = { m = 77, a = { ["2518"] = 9 }, h = { ["2518"] = 77 }, l = {} }
  M.fire("AUCTION_HOUSE_SHOW")
  M.fire("PLAYER_LOGOUT")
  eq("market: a logout at the AH writes the copy at once", ns.DB.market.items[2840], "77/9/2518")
  M.timers = {}

  -- ── a realm Auctionator serialized at logout (no Database table) ──
  _G.Auctionator = { State = { CurrentRealm = "PvE Horde" }, Constants = { SCAN_DAY_0 = 1577833200 } }
  _G.AUCTIONATOR_PRICE_DATABASE = { __dbversion = 8, ["PvE Horde"] = cbor({ ["5000"] = { m = 5, a = { ["2519"] = 2 }, h = { ["2519"] = 5 } } }) }
  eq("market: a serialized realm is decoded", Snap.take(true), true)
  eq("market: its item", ns.DB.market.items[5000], "5/2/2519")
  eq("market: the old items are not mixed in", ns.DB.market.items[2589], nil)
  M.timers = {}

  -- ── no Auctionator: nothing happens, the stored copy stays ──
  local before = ns.DB.market
  _G.Auctionator = nil; _G.AUCTIONATOR_PRICE_DATABASE = nil
  M.fire("AUCTION_HOUSE_SHOW"); M.fire("AUCTION_HOUSE_CLOSED"); drain(); M.fire("PLAYER_LOGOUT")
  eq("market: without Auctionator the stored copy is untouched", ns.DB.market, before)
  eq("market: take answers false without Auctionator", Snap.take(true), false)
  _G.Auctionator = { State = { CurrentRealm = "X" }, Database = { db = "garbage" } }
  eq("market: an unreadable database is nothing", Snap.take(true), false)
  _G.AUCTIONATOR_PRICE_DATABASE = { X = "not cbor" }
  eq("market: a realm that does not decode is nothing", Snap.take(true), false)

  -- ── silent ──
  eq("market: no chat line from any of it", said, 0)
  eq("market: no Lua error from any of it", #M.errors, errs0)

  ns.DB.market = keep.market
  _G.Auctionator, _G.AUCTIONATOR_PRICE_DATABASE, _G.C_EncodingUtil = keep.A, keep.APD, keep.enc
  M.inCombat, _G.print, Snap.CHUNK, M.sellPrice = keep.combat, keep.print, keep.chunk, keep.sell
  Snap.queue, Snap.waiting, Snap.pumping, Snap.job, Snap.open = {}, {}, false, nil, false
  M.timers = {}
end
