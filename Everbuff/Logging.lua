-- Everbuff · Logging.lua - client-flavor detection + the combat-log recording GUARANTEE.
--
-- This is the addon's highest-value job and the first vertical of "recording": whenever you are
-- playing, the engine-written WoWCombatLog.txt IS being written, with advanced params, cleanly,
-- for the WHOLE time - not just in instances. There is no opt-out, and if logging is ever off we
-- complain heavily and repeatedly until it is back on.
--
-- Cross-client (Midnight "WoW Forever" + Classic/SoD):
--   Midnight's Secret Values (12.0) make in-combat CLEU unreadable to addons, so the file is the
--   only clean path. Classic/SoD have NO Secret Values (CLEU is readable) - but we deliberately use
--   the SAME file-guarantee + landmark model on both so there is a single code path. The only
--   sanctioned APIs we touch here exist on every flavor: SetCVar/GetCVar("advancedCombatLogging"),
--   LoggingCombat(bool) and LoggingCombat() (query).

local ADDON, ns = ...

-- What the client blocks (founder, 2026-10-02: "blocked from an action only available to the Blizzard UI"). This is the
-- second file the TOC loads, so it listens before every other module runs: the addon and the protected function are
-- printed in chat at once and kept (the last 10) in settings.blocked with the time, the call stack and whether we were
-- in combat. Before the save file is loaded they wait in ns.blockedPending.
ns.blockedPending = {}
function ns.noteBlocked(kind, addon, func)
  local inCombat = InCombatLockdown and InCombatLockdown() or false
  local stack = debugstack and debugstack(3, 6, 0) or ""
  print(("|cffd4af37everbuff.gg|r: |cffff4444%s|r %s tried %s%s"):format(kind, tostring(addon or "?"), tostring(func or "?"), inCombat and " (in combat)" or ""))
  local row = { t = GetServerTime and GetServerTime() or 0, kind = kind, addon = addon, func = func, combat = inCombat, stack = stack }
  local db = ns.DB and ns.DB.settings
  if db then
    db.blocked = db.blocked or {}
    for _, r in ipairs(ns.blockedPending) do table.insert(db.blocked, r) end
    ns.blockedPending = {}
    table.insert(db.blocked, row)
    while #db.blocked > 10 do table.remove(db.blocked, 1) end
  else
    table.insert(ns.blockedPending, row)
  end
end
function ns.flushBlocked()
  local db = ns.DB and ns.DB.settings
  if not db or #ns.blockedPending == 0 then return end
  db.blocked = db.blocked or {}
  for _, r in ipairs(ns.blockedPending) do table.insert(db.blocked, r) end
  ns.blockedPending = {}
  while #db.blocked > 10 do table.remove(db.blocked, 1) end
end
-- Every frame that registers events joins ns.eventFrames, so the self-test (SelfTest.lua) can see that none of them
-- holds an event the client forbids.
ns.eventFrames = ns.eventFrames or {}
do
  local catcher = CreateFrame("Frame")
  ns.eventFrames[#ns.eventFrames + 1] = catcher
  catcher:RegisterEvent("ADDON_ACTION_BLOCKED")
  catcher:RegisterEvent("ADDON_ACTION_FORBIDDEN")
  catcher:SetScript("OnEvent", function(_, event, addon, func)
    ns.noteBlocked(event == "ADDON_ACTION_FORBIDDEN" and "forbidden" or "blocked", addon, func)
  end)
end
local L = {}
ns.Logging = L

-- ── client flavor (set once at load - Logging loads first, so all modules can read these) ──
local MAINLINE = WOW_PROJECT_MAINLINE or 1
-- A client with Secret Values (issecretvalue) is a Midnight-engine client, WoW Forever included, whatever project id it
-- reports: the 1.60.1.70170 update of 2026-10-01 moved Forever from project 1 to 18, the addon took it for Classic,
-- registered COMBAT_LOG_EVENT_UNFILTERED and the client blocked it ("blocked from an action only available to the
-- Blizzard UI"). Capability first, project id second.
ns.hasSecretValues = type(issecretvalue) == "function" or (WOW_PROJECT_ID == nil) or (WOW_PROJECT_ID == MAINLINE)
ns.isMainline     = ns.hasSecretValues
ns.isClassic      = not ns.isMainline
ns.hasChallengeMode = ns.isMainline and (C_ChallengeMode ~= nil) -- Mythic+ is retail-only
ns.hasDamageMeter   = (C_DamageMeter ~= nil)                     -- Blizzard's 12.0 meter; nil on Classic
ns.flavor          = ns.isMainline and "mainline" or "classic"

-- advancedCombatLogging=1 adds infoGUID, HP, position, item level + COMBATANT_INFO to the file -
-- the fields the backend segmenter and CLA/RPB metrics depend on. Best-effort: some clients gate
-- cvars, so we pcall and re-read rather than trust the write.
local function setACL(on)
  local ok = pcall(SetCVar, "advancedCombatLogging", on and "1" or "0")
  return ok
end

-- CRITICAL: never call LoggingCombat() with NO argument. On the Classic/SoD client a nil/absent arg
-- is treated as false, so *querying* combat logging actually DISABLES it - which caused a vicious
-- ON→OFF cycle (every status read turned it off; the guardian turned it back on). We only ever call
-- LoggingCombat(true)/(false) explicitly and track our own intent in L._combat.
L._combat = false

-- Current logging posture. ACL is a real cvar we can query safely; combat logging is our tracked
-- intent (there is no side-effect-free way to query it).
function L.state()
  local aclOn = GetCVar("advancedCombatLogging") == "1"
  return aclOn, L._combat
end

-- Logging ON; report whether we had to change anything. Every LoggingCombat(true) writes a COMBAT_LOG_VERSION and a
-- ZONE_CHANGE header into the log, so it is called only when logging is not known to be on, or with `force` (world
-- entry and the slow safety re-check): called every 10 s it made 7 % of a log synthetic headers and broke its time
-- order (#15). Something else turning it off is caught at once by the tamper guards.
function L.enforce(force)
  local aclOn = GetCVar("advancedCombatLogging") == "1"
  local changed = false
  if not aclOn then
    changed = setACL(true) or changed
    aclOn = GetCVar("advancedCombatLogging") == "1"
  end
  if force or not L._combat then
    LoggingCombat(true) -- explicit enable; unlike the no-argument form it never disables
  end
  if not L._combat then changed = true end
  L._combat = true
  return aclOn, L._combat, changed
end

-- The chat log (everbuff-business #39, approved 2026-09-29): WoW writes Logs/WoWChatLog.txt continuously while it
-- is on, and its system lines (loot, money, XP, quests, levels) let the backend rebuild what an Alt+F4 kept out of
-- the save file. The desktop uploads only those system lines; conversations never leave the PC. Like combat
-- logging it is never queried with no argument; it is turned on at world entry and again whenever something turns
-- it off (the tamper guard), not on every tick, so it can never print a line every ten seconds.
L._chat = false
local reentrantChat = false -- set while enforceChat runs, so its own call is not taken for tampering
function L.enforceChat()
  if type(LoggingChat) ~= "function" then return false end
  reentrantChat = true
  pcall(LoggingChat, true)
  reentrantChat = false
  L._chat = true
  return true
end

-- Provided for completeness, but the addon never calls this: logging is always-on by design.
function L.stop() LoggingCombat(false); L._combat = false end

-- Compact snapshot for the session record / status line.
function L.snapshot()
  local aclOn, combatOn = L.state()
  return { acl = aclOn, combat = combatOn }
end

-- ── heavy, repeating complaint when logging is not actually on ────────────────────────────────
-- The user's rule: if advanced logging is off, complain HEAVILY and always. So we hit three
-- channels at once (chat, center-screen raid warning, red UI error text + a sound) and repeat on a
-- timer until it is fixed - impossible to miss, whether the player is leveling or mid-raid.
local NAG_PERIOD = 10
local lastNag, wasOff = -1e9, false

local function bigWarn(text)
  if RaidNotice_AddMessage and RaidWarningFrame then
    pcall(RaidNotice_AddMessage, RaidWarningFrame, text, (ChatTypeInfo and ChatTypeInfo.RAID_WARNING) or { r = 1, g = .2, b = .2 })
  end
  if UIErrorsFrame and UIErrorsFrame.AddMessage then
    pcall(UIErrorsFrame.AddMessage, UIErrorsFrame, text, 1, .1, .1, 1)
  end
  if PlaySound then pcall(PlaySound, 8959) end -- IG_MainMenuOptionCheckBoxOn-ish / RaidWarning cue
end

function L.nag(force)
  local now = GetTime()
  if not force and (now - lastNag) < NAG_PERIOD then return end
  lastNag = now
  local msg = "ADVANCED COMBAT LOGGING is off and couldn't be enabled."
  ns.msg("|cffe5544b" .. msg .. "|r  Everbuff needs the |cffffffffadvancedCombatLogging|r CVar on. If this keeps happening, a script or another addon is resetting it.")
  bigWarn("Everbuff.GG: " .. msg)
end

-- The guardian runs for the WHOLE play session (not just in instances). It enforces logging every
-- NAG_PERIOD seconds, nags heavily while off, confirms once when it comes back, and records a
-- LOGGING_REPAIR landmark (via the recorder) whenever it had to fix a mid-session drop.
-- How many times we've had to turn combat logging back on after startup (exposed for the UI).
L.repairs = 0

-- ── anti-tamper: catch (and name) any addon that disables our logging ──────────────────────────
-- We post-hook the global toggles. If anything turns combat logging OFF or clears the cvar, our hook
-- fires the instant it happens: we turn it straight back on and blame the addon whose file is on the
-- call stack. `reentrant` stops our own re-enable from looking like tampering.
local reentrant = false

local function culpritFromStack()
  local s = debugstack and debugstack(1, 20, 0) or ""
  for name in s:gmatch("[Aa]dd[Oo]ns[\\/]([^\\/]+)") do
    if name ~= ADDON and name ~= "Everbuff" then return name end
  end
  return nil -- Blizzard code / a /combatlog macro leaves no AddOns path
end

local function onTamper(what)
  if reentrant then return end
  local culprit = culpritFromStack()
  reentrant = true
  L._combat = false -- it was turned off: our intent no longer matches the client
  L.enforce() -- turn it straight back on
  reentrant = false
  L.repairs = (L.repairs or 0) + 1
  L.lastCulprit = culprit
  local who = culprit and ("|cffff4444" .. culprit .. "|r") or "another addon or a macro"
  ns.msg(("|cffe5544bBlocked " .. who .. "|r from disabling %s - recording re-enabled. If that wasn't you, that addon is sabotaging your logs; consider removing it."):format(what))
  bigWarn("Everbuff.GG: blocked an addon from stopping your combat log")
end

function L.installTamperGuards()
  if L._tamperHooked or not hooksecurefunc then return end
  L._tamperHooked = true
  hooksecurefunc("LoggingCombat", function(state)
    if not reentrant and (state == false or state == nil) then onTamper("combat logging") end
  end)
  if type(LoggingChat) == "function" then
    hooksecurefunc("LoggingChat", function(state)
      if not reentrantChat and not reentrant and state == false then
        L.enforceChat()
        L.chatRepairs = (L.chatRepairs or 0) + 1
      end
    end)
  end
  hooksecurefunc("SetCVar", function(cvar, value)
    if not reentrant and cvar == "advancedCombatLogging" and tostring(value) == "0" then
      onTamper("advanced combat logging")
    end
  end)
end

function L.startGuardian()
  if L._guardian then return end
  L.installTamperGuards()
  local started, ticks = false, 0
  local function tick()
    ticks = ticks + 1
    -- the first tick (world entry) and every 30th (5 min) re-assert logging; the others only check the cvar (#15)
    local acl, combat, changed = L.enforce(ticks == 1 or ticks % 30 == 0)
    local off = not (acl and combat)
    if off then
      L.nag()
      wasOff = true
    elseif wasOff then
      wasOff = false
      ns.msg("|cff47c97ecombat logging is back ON|r - recording resumed.")
    end
    -- A change after startup means something dropped logging and we corrected it - count it + mark
    -- the gap in the landmark index (the first tick is initial setup, not a repair).
    if changed and started then
      L.repairs = L.repairs + 1
      if ns.Recorder and ns.Recorder.noteLoggingRepair then ns.Recorder.noteLoggingRepair(acl, combat) end
    end
    started = true
  end
  tick() -- enforce immediately on first world-enter
  L.enforceChat()
  -- Every 10 s: the advanced logging cvar is checked and a nag goes out while logging is off (NAG_PERIOD throttles
  -- it); combat logging itself is re-asserted only every 5 min, at world entry and when the tamper guards fire.
  L._guardian = C_Timer.NewTicker(10, tick)
end
