-- The market snapshot (#58) on a player's real Auctionator save. Run from the repo root:
--   EB_AUCTIONATOR=<path to SavedVariables/Auctionator.lua> luajit tests/market_real.lua [out.tsv]
-- The file is only read. The addon is loaded in TOC order under tests/wow_stub.lua; Auctionator's globals come from
-- the file as the client loads it, with the realm left CBOR-serialized as Auctionator writes it at logout, so the
-- addon takes the decode path (C_EncodingUtil.DeserializeCBOR, here a CBOR reader of this file's own). The snapshot
-- is written as "id TAB m/a/d" lines, sorted, for a check against an independent decoder of the same file.
package.path = "tests/?.lua;" .. package.path
local path = os.getenv("EB_AUCTIONATOR") or error("set EB_AUCTIONATOR to the Auctionator.lua save file")
local out = arg[1] or "market_real.tsv"
local M = require("wow_stub")

-- CBOR (RFC 8949), the subset Auctionator writes: unsigned and negative ints, strings, arrays, maps, simple values
local function cbor(s)
  local i = 1
  local function u(n) local v = 0; for _ = 1, n do v = v * 256 + s:byte(i); i = i + 1 end return v end
  local item
  function item()
    local ib = s:byte(i); i = i + 1
    local mt, ai = math.floor(ib / 32), ib % 32
    local v
    if ai < 24 then v = ai elseif ai == 24 then v = u(1) elseif ai == 25 then v = u(2) elseif ai == 26 then
      if mt == 7 then error("float32 not expected") end v = u(4)
    elseif ai == 27 then if mt == 7 then error("float64 not expected") end v = u(8)
    else error(("indefinite length at byte %d"):format(i - 1)) end
    if mt == 0 then return v elseif mt == 1 then return -1 - v
    elseif mt == 2 or mt == 3 then local str = s:sub(i, i + v - 1); i = i + v; return str
    elseif mt == 4 then local a = {}; for k = 1, v do a[k] = item() end return a
    elseif mt == 5 then local t = {}; for _ = 1, v do local k = item(); t[k] = item() end return t
    elseif mt == 6 then return item()
    elseif mt == 7 then if ai == 20 then return false elseif ai == 21 then return true end return nil end
  end
  local r = item()
  if i ~= #s + 1 then error(("CBOR: %d bytes left over"):format(#s + 1 - i)) end
  return r
end
_G.C_EncodingUtil = { DeserializeCBOR = cbor }

local ns, ADDON = {}, "EverbuffJournal"
for _, f in ipairs({ "Theme", "Logging", "Segments", "Fights", "UI", "Debug", "Recording", "Economy", "Runs", "RunsLegacy", "Progress", "Market", "Visits", "Journey", "Dungeons", "Deaths", "Sync", "Emitter", "Core", "Deps", "SelfTest" }) do
  assert(loadfile("Everbuff/" .. f .. ".lua"))(ADDON, ns)
end
M.fire("ADDON_LOADED", ADDON)

local env = {}
assert(loadfile(path, "t", env) or setfenv(assert(loadfile(path)), env))()
local db = env.AUCTIONATOR_PRICE_DATABASE or error("no AUCTIONATOR_PRICE_DATABASE in the file")
local realm
for k, v in pairs(db) do if k ~= "__dbversion" then assert(realm == nil, "more than one realm: pass one"); realm = k end end
_G.AUCTIONATOR_PRICE_DATABASE = db
_G.Auctionator = { State = { CurrentRealm = realm }, Constants = { SCAN_DAY_0 = os.time({ year = 2020, month = 1, day = 1, hour = 0 }) } }

local t0 = os.clock()
assert(ns.Market.snap.take(true), "the snapshot read nothing")
local mk = ns.DB.market
local ids = {}
for id in pairs(mk.items) do ids[#ids + 1] = id end
table.sort(ids)
local f = assert(io.open(out, "w"))
for _, id in ipairs(ids) do f:write(id, "\t", mk.items[id], "\n") end
f:close()
io.write(("realm %s: %d items, %d skipped, scanDay %d, %.2f s; written to %s\n"):format(realm, mk.n, mk.skipped, mk.scanDay, os.clock() - t0, out))
