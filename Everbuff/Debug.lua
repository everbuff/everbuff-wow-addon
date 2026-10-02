-- Everbuff · Debug.lua - the "put Claude in the loop" bridge (Tier 2 of the dev loop).
--
-- Addons can't talk to a dev machine, but SavedVariables IS a file on disk. So we:
--   1. capture every Lua error into EverbuffDB.debug.errors (survives to the SV file),
--   2. write a diagnostics snapshot on `/rb debug`,
--   3. offer a fake 5-man roster (`/rb debug group`) so the group-dependent tabs (Crew, Readiness)
--      can be seen and tested SOLO.
-- Flow: play / repro → `/rb debug` → `/reload` (flushes SV) → the dev reads
--   WTF/Account/<acct>/SavedVariables/Everbuff.lua and sees exactly what happened.

local ADDON, ns = ...
local D = {}
ns.Debug = D

-- ── error capture (chains the existing handler so BugSack etc. still work) ─────
-- Each row keeps the call stack: the 2026-10-02 save file held 49 "attempt to call a nil value" rows and nothing that
-- said where. A repeat of the row before it only counts up (`n`, `last`), so one error firing on every combat event
-- cannot push every other error out of the 50 kept.
local errbuf = {}
local orig = geterrorhandler and geterrorhandler()
if seterrorhandler then
  seterrorhandler(function(err)
    local msg, at = tostring(err), date("%m-%d %H:%M:%S")
    local prev = errbuf[#errbuf]
    if prev and prev.err == msg then
      prev.n, prev.last = (prev.n or 1) + 1, at
    else
      local stack = debugstack and debugstack(2, 8, 0) or nil
      errbuf[#errbuf + 1] = { at = at, err = msg, stack = (type(stack) == "string" and stack ~= "") and stack:gsub("|", "/") or nil }
    end
    while #errbuf > 50 do table.remove(errbuf, 1) end
    if ns.DB then ns.DB.debug = ns.DB.debug or {}; ns.DB.debug.errors = errbuf end
    if orig then return orig(err) end
  end)
end

function D.active() return ns.DB and ns.DB.debug and ns.DB.debug.fakeGroup and true or false end

-- A stand-in raid so Crew / Readiness show real-looking data with no group. `scan` feeds Readiness.
function D.members()
  return {
    { unit = "player", name = UnitNameUnmodified("player") or "You", class = "Paladin", classFile = "PALADIN", role = "TANK",   online = true, scan = { flask = true,  food = true,  rune = true } },
    { unit = "dbg2", name = "Dave",    class = "Priest", classFile = "PRIEST",     role = "HEALER",  online = true, scan = { flask = true,  food = false, rune = false } },
    { unit = "dbg3", name = "Isolyte", class = "Mage",   classFile = "MAGE",       role = "DAMAGER", online = true, scan = { flask = false, food = true,  rune = true } },
    { unit = "dbg4", name = "Brster",  class = "Rogue",  classFile = "ROGUE",      role = "DAMAGER", online = true, scan = { flask = true,  food = true,  rune = false } },
    { unit = "dbg5", name = "Sudac",   class = "Warlock",classFile = "WARLOCK",    role = "DAMAGER", online = false,scan = { flask = false, food = false, rune = false } },
  }
end

function D.snapshot()
  ns.DB.debug = ns.DB.debug or {}
  local aclOn, combatOn = ns.Logging.state()
  local sess = ns.Recorder.active()
  local nsess = 0; for _ in pairs(ns.DB.sessions) do nsess = nsess + 1 end
  local resItems, resPlayers = 0, {}
  for _, list in pairs(ns.DB.loot.reserves or {}) do
    resItems = resItems + 1
    for _, e in ipairs(list) do resPlayers[e.player] = true end
  end
  local np = 0; for _ in pairs(resPlayers) do np = np + 1 end
  ns.DB.debug.snapshot = {
    at = date("%Y-%m-%d %H:%M:%S"),
    version = ns.VERSION,
    build = select(4, GetBuildInfo()),
    logging = { acl = aclOn, combat = combatOn },
    inInstance = (select(1, IsInInstance())) and (select(2, IsInInstance())) or "no",
    session = sess and { id = sess.id, context = sess.context, markers = #sess.segments } or nil,
    storedSessions = nsess,
    reserves = { items = resItems, players = np, raid = ns.DB.loot.raidCode },
    fakeGroup = D.active(),
    errorCount = #errbuf,
  }
  ns.msg("diagnostics written - |cffffffff/reload|r then share SavedVariables\\Everbuff.lua")
end

-- slash: /rb debug [group|clear]
function D.command(rest)
  rest = (rest or ""):gsub("^%s+", "")
  if rest == "group" then
    ns.DB.debug = ns.DB.debug or {}
    ns.DB.debug.fakeGroup = not ns.DB.debug.fakeGroup
    ns.msg("fake group " .. (ns.DB.debug.fakeGroup and "|cff47c97eON|r - open Crew/Readiness" or "|cffe25a5aoff|r"))
    if ns.UI then ns.UI.onRosterUpdate() end
  elseif rest == "clear" then
    if ns.DB.debug then ns.DB.debug.errors = {}; errbuf = {} end
    ns.msg("debug errors cleared")
  else
    D.snapshot()
    if #errbuf > 0 then ns.msg(("|cffe25a5a%d error(s) captured|r - included in the snapshot"):format(#errbuf)) end
  end
end
