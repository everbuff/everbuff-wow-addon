-- The SavedVariables contract export (master plan P0-12). Run from the repo root:
--   luajit tests/export_fixture.lua [out.lua]          (default tests/export/EverbuffJournal.lua)
--   luajit tests/export_fixture.lua --check            (exit 1 when the committed export is stale)
--
-- A scripted play session runs through the REAL addon files under tests/wow_stub.lua: a login, two fights with
-- loot and coin, a quest, a level-up, a /reload (a fresh Lua state that loads the save file the logout wrote, as
-- the client does), a third fight and a logout. The save file is written the way the client writes it
-- (`Name = { ... }` per SavedVariable in the TOC), with sorted keys and a fixed clock and random seed, so the
-- same addon code always produces the same bytes. The backend checks in this file and ingests it with exact
-- counts (everbuff-backend tests/ingest_addon_export.rs), so a change to what the addon saves shows up here first.
package.path = "tests/?.lua;" .. package.path

local DEFAULT_OUT = "tests/export/EverbuffJournal.lua"
local ADDON = "EverbuffJournal"
local EPOCH0 = 1793000000          -- 2026-10-26 07:33:20 UTC: the session's server time at login
local LOCAL_OFFSET = -1            -- the PC clock runs 1 s behind the server, as on real machines
local MONO0 = 831000.5             -- GetTime() at login (seconds since the PC booted)

-- ── the save file writer: the client's layout, made deterministic ──────────────────────────────────────────
local function num(n)
  if n ~= n or n == math.huge or n == -math.huge then error("non-finite number in the save file") end
  if n == math.floor(n) and math.abs(n) < 2 ^ 53 then return ("%d"):format(n) end
  return ("%.14g"):format(n)
end
local function str(s)
  return '"' .. s:gsub('[%c"\\]', function(c)
    if c == "\n" then return "\\n" elseif c == "\r" then return "\\r" elseif c == "\t" then return "\t"
    elseif c == '"' or c == "\\" then return "\\" .. c end
    return ("\\%03d"):format(c:byte())
  end) .. '"'
end
local function keyOrder(a, b)
  local ta, tb = type(a), type(b)
  if ta ~= tb then return ta == "number" end
  return a < b
end
local function serialize(v, depth, seen, out)
  local t = type(v)
  if t == "string" then out[#out + 1] = str(v)
  elseif t == "number" then out[#out + 1] = num(v)
  elseif t == "boolean" then out[#out + 1] = tostring(v)
  elseif t == "table" then
    if seen[v] then error("a cycle in the save file") end
    seen[v] = true
    local n = 0
    while v[n + 1] ~= nil do n = n + 1 end
    local pad = ("\t"):rep(depth + 1)
    out[#out + 1] = "{\n"
    for i = 1, n do
      out[#out + 1] = pad; serialize(v[i], depth + 1, seen, out); out[#out + 1] = (", -- [%d]\n"):format(i)
    end
    local keys = {}
    for k in pairs(v) do
      local tk = type(k)
      if tk == "number" then
        if not (k >= 1 and k <= n and k == math.floor(k)) then keys[#keys + 1] = k end
      elseif tk == "string" then keys[#keys + 1] = k
      else error("a " .. tk .. " key in the save file") end
    end
    table.sort(keys, keyOrder)
    for _, k in ipairs(keys) do
      out[#out + 1] = pad .. "[" .. (type(k) == "string" and str(k) or num(k)) .. "] = "
      serialize(v[k], depth + 1, seen, out); out[#out + 1] = ",\n"
    end
    out[#out + 1] = ("\t"):rep(depth) .. "}"
    seen[v] = nil
  else error("a " .. t .. " value in the save file") end
end
local function savedVariableNames()
  local toc = assert(io.open("Everbuff/EverbuffJournal.toc", "rb")):read("*a")
  local names = {}
  for n in toc:match("## SavedVariables: ([^\r\n]+)"):gmatch("[%w_]+") do names[#names + 1] = n end
  return names
end
local function saveFile()
  local out = {}
  for _, name in ipairs(savedVariableNames()) do
    if _G[name] ~= nil then   -- the client leaves a nil SavedVariable out of the file
      out[#out + 1] = "\n" .. name .. " = "
      serialize(_G[name], 0, {}, out)
      out[#out + 1] = "\n"
    end
  end
  return table.concat(out)
end

-- ── a game session: the stub, the addon (TOC order), the clock ─────────────────────────────────────────────
local pristine = {}
for k in pairs(_G) do pristine[k] = true end
local clock = { epoch = EPOCH0, mono = MONO0 }
local M, ns

local function tocFiles()
  local files = {}
  for line in io.lines("Everbuff/EverbuffJournal.toc") do
    local f = line:match("^([%w_]+)%.lua%s*$"); if f then files[#files + 1] = f end
  end
  return files
end

-- start the client: every global from a previous run is gone, the save file's globals are loaded, the addon files
-- run in a fresh namespace. This is what a /reload or a restart does to an addon.
local function bootClient(save)
  for k in pairs(_G) do if not pristine[k] then _G[k] = nil end end
  package.loaded.wow_stub = nil
  math.randomseed(20261109)
  M = require("wow_stub")
  M.epoch, M.now = clock.epoch, clock.mono
  -- the clock as the client has it: server time, the PC's local time, and date() on it in UTC
  _G.time = function(t) if t then return os.time(t) end return M.epoch + LOCAL_OFFSET end
  _G.date = function(fmt, t)
    fmt = fmt or "%c"
    if fmt:sub(1, 1) == "!" then fmt = fmt:sub(2) end
    return os.date("!" .. fmt, t or (M.epoch + LOCAL_OFFSET))
  end
  _G.C_QuestLog = { GetTitleForQuestID = function(id) return ({ [176] = "Wanted: Hogger", [5545] = "A Bundle of Trouble" })[id] end }
  _G.print = function() end   -- chat lines are not part of the save file
  if save then
    local chunk = assert(loadstring(save, "=SavedVariables"))
    chunk()
  end
  ns = {}
  for _, f in ipairs(tocFiles()) do
    local chunk = assert(loadfile("Everbuff/" .. f .. ".lua"))
    chunk(ADDON, ns)
  end
end
local function advance(s)
  clock.epoch, clock.mono = clock.epoch + s, clock.mono + s
  M.epoch, M.now = clock.epoch, clock.mono
end
local function fight(foe, guid, seconds, opts)
  opts = opts or {}
  M.units.target = { name = foe, hostile = true, guid = guid, cls = opts.cls or "normal" }
  M.inCombat = true; M.fire("PLAYER_REGEN_DISABLED")
  advance(seconds)
  M.units.target.dead = true; M.inCombat = false
  M.fire("PLAYER_REGEN_ENABLED")
  if opts.xp then M.fire("CHAT_MSG_COMBAT_XP_GAIN", ("%s dies, you gain %d experience."):format(foe, opts.xp)); M.xp = M.xp + opts.xp; M.fire("PLAYER_XP_UPDATE") end
  if opts.coin or opts.item then
    M.fire("LOOT_OPENED")
    if opts.coin then M.money = M.money + opts.coin; M.fire("PLAYER_MONEY") end
    if opts.item then M.fire("CHAT_MSG_LOOT", "You receive loot: " .. opts.item .. ".") end
    M.fire("LOOT_CLOSED")
  end
  M.units.target = nil
  advance(20)
end

local function playSession()
  -- login
  bootClient(nil)
  M.money, M.xp, M.xpmax, M.level = 1520, 300, 1000, 12
  M.gear = { [2] = "|cff1eff00|Hitem:12019::::::::12:::::|h[Cerulean Ring]|h|r", [16] = "|cffffffff|Hitem:2488::::::::12:::::|h[Gladius]|h|r" }
  M.dur = { [16] = { 45, 50 } }
  M.zone = "Elwynn Forest"; M.inst = { name = "Elwynn Forest", type = "none", diff = 0, mapID = 0 }
  M.fire("ADDON_LOADED", ADDON)
  M.fire("PLAYER_ENTERING_WORLD", true, false)
  M.runTimers()
  M.fire("TIME_PLAYED_MSG", 90061, 3600)
  advance(30)
  -- two fights, loot and coin, a quest turned in, a level-up
  fight("Kobold Miner", "Creature-0-4618-0-1-40-000A1B2C3D", 12, { xp = 45, coin = 80, item = "|cffffffff|Hitem:2589::::::::12:::::|h[Linen Cloth]|h|rx2" })
  fight("Kobold Tunneler", "Creature-0-4618-0-1-475-000A1B2C3E", 15, { xp = 50, coin = 112, item = "|cff1eff00|Hitem:1416::::::::12:::::|h[Rusty Hatchet]|h|r" })
  M.fire("QUEST_TURNED_IN", 176, 600, 350); M.money = M.money + 350; M.fire("PLAYER_MONEY")
  M.xp = M.xp + 600
  M.xp, M.level = M.xp - M.xpmax, 13; M.xpmax = 1300
  M.fire("PLAYER_XP_UPDATE"); M.fire("PLAYER_LEVEL_UP", 13)
  advance(40)
  -- /reload: the logout writes the save file, the client starts over and loads it
  M.fire("PLAYER_LOGOUT")
  local save = saveFile()
  local money, xp, xpmax, level, gear, dur = M.money, M.xp, M.xpmax, M.level, M.gear, M.dur
  advance(5)
  bootClient(save)
  M.money, M.xp, M.xpmax, M.level, M.gear, M.dur = money, xp, xpmax, level, gear, dur
  M.zone = "Elwynn Forest"; M.inst = { name = "Elwynn Forest", type = "none", diff = 0, mapID = 0 }
  M.fire("ADDON_LOADED", ADDON)
  M.fire("PLAYER_ENTERING_WORLD", false, true)
  M.runTimers()
  advance(30)
  -- one more fight, then a logout
  fight("Defias Thug", "Creature-0-4618-0-1-38-000A1B2C3F", 9, { xp = 60, coin = 95 })
  M.fire("PLAYER_LOGOUT")
  local errors = M.errors
  return saveFile(), errors
end

local args = { ... }
local text, errors = playSession()
if #errors > 0 then
  io.stderr:write("handler errors during the scripted session:\n  " .. table.concat(errors, "\n  ") .. "\n")
  os.exit(1)
end
if args[1] == "--check" then
  local f = io.open(DEFAULT_OUT, "rb")
  local have = f and f:read("*a"):gsub("\r\n", "\n") or ""
  if f then f:close() end
  if have ~= text then
    io.stderr:write(DEFAULT_OUT .. " is out of date: run luajit tests/export_fixture.lua and commit it (and the backend's copy)\n")
    os.exit(1)
  end
  io.stdout:write(("%s is current (%d bytes)\n"):format(DEFAULT_OUT, #text))
  return
end
local out = args[1] or DEFAULT_OUT
local f = assert(io.open(out, "wb")); f:write(text); f:close()
io.stdout:write(("wrote %s (%d bytes)\n"):format(out, #text))
