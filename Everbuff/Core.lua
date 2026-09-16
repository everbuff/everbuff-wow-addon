-- Everbuff · Core.lua — boot, event router, slash.
--
-- CORE GUARANTEE (not optional): advanced combat logging + landmark recording are ALWAYS ON, and
-- now EVERYWHERE — open-world leveling included, not just instances. Recording is the entire reason
-- the addon exists; a night with logging silently off is a lost night, so it is unconditional and
-- self-healing (ns.Logging guardian) and complains heavily if it ever can't keep logging on.
--
-- Cross-client: the primary target is the Midnight "WoW Forever" model (Secret Values → CLEU-free,
-- the file is the source of truth). The same code runs on Classic/SoD (our current data-gathering
-- testbed): Midnight-only APIs (C_DamageMeter, C_ChallengeMode / M+) are feature-detected and their
-- events are only registered where they exist. Flags live on ns (set in Logging.lua).

local ADDON, ns = ...

ns.VERSION = "0.6.1"
ns.GOLD = "|cffc9a63c"
ns.CYAN = "|cff00afd7"
function ns.msg(text) print(ns.GOLD .. "Everbuff|r: " .. text) end

EverbuffDB = EverbuffDB or nil -- materialized on ADDON_LOADED

local f = CreateFrame("Frame")

-- ── context detection (ambient recording — always on, no opt-out) ─────────────
-- Raid/dungeon → a full "instance" session (encounters, challenge mode, combat edges, meter).
-- Everywhere else → a lightweight "world" session for leveling (level-ups, deaths, zone changes).
-- We transition between them so exactly one session is active at a time.
-- One session per play session (login → logout). The combat log delimits fights, so we don't churn
-- sessions on zoning — the addon record is a thin identity/leveling/integrity beacon.
local function checkContext()
  if not ns.Recorder.active() then ns.Recorder.start() end
end
ns.checkContext = checkContext
ns.checkInstance = checkContext -- back-compat alias

-- ── event router (minimal — the combat-log FILE is the real record) ───────────
local handlers = {
  -- Re-assert logging the instant combat starts (the one moment it must be on), then the file does
  -- the rest. We do NOT record encounters/zones/deaths/meters here — those are all in the log.
  PLAYER_REGEN_DISABLED = function() ns.Logging.enforce() end,
  PLAYER_LEVEL_UP = function(level) ns.Recorder.onLevelUp(level) end,
}

-- ── slash ─────────────────────────────────────────────────────────────────────
SLASH_EVERBUFF1 = "/rb"
SLASH_EVERBUFF2 = "/everbuff"
SlashCmdList.EVERBUFF = function(arg)
  arg = (arg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if arg == "" or arg == "show" or arg == "open" then
    if ns.UI then ns.UI.Toggle() else ns.msg("UI not loaded") end
  elseif arg == "rec" or arg == "recording" then
    if ns.UI then ns.UI.Open("Recording") end
  -- NOTE: /rb loot · /rb ready · /rb crew (raid-lead tools) are DEFERRED — see addon/Everbuff/future/.
  elseif arg == "export" or arg == "end" then
    if ns.Recorder.active() then
      ns.Recorder.stop("manual export")
      ns.msg("now |cffffffff/reload|r (or log out) to hand the session to the uploader")
    else ns.msg("no active session") end
  elseif arg == "status" then
    local sess = ns.Recorder.active()
    local aclOn, combatOn = ns.Logging.state()
    if sess then
      ns.msg(("|cff46b36brecording|r · %s · session %s · %d markers · logging acl=%s combat=%s")
        :format(sess.context or "?", sess.id, #sess.segments,
                aclOn and "|cff46b36bon|r" or "|cffe25a5aOFF|r",
                combatOn and "|cff46b36bon|r" or "|cffe25a5aOFF|r"))
    else
      ns.msg(("idle · advanced logging %s · combat logging %s")
        :format(aclOn and "|cff46b36bon|r" or "|cffe25a5aoff|r",
                combatOn and "|cff46b36bon|r" or "|cffe25a5aoff|r"))
    end
    local n = 0
    for _ in pairs(ns.DB.sessions) do n = n + 1 end
    ns.msg(("client: %s · %d session(s) stored — flushed to disk on /reload or logout"):format(ns.flavor, n))
  elseif arg == "debug" or arg:match("^debug ") then
    if ns.Debug then ns.Debug.command((arg:gsub("^debug%s*", ""))) else ns.msg("debug module not loaded") end
  elseif arg == "wipe" then
    ns.DB.sessions = {}; ns.DB.active = nil
    ns.msg("stored sessions wiped")
  else
    ns.msg("commands: /rb (open) · /rb status · /rb debug · /rb export · /rb wipe")
  end
end

-- ── boot ───────────────────────────────────────────────────────────────────────
f:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" and ... == ADDON then
    EverbuffDB = EverbuffDB or {}
    local db = EverbuffDB
    db.sessions = db.sessions or {}
    db.runs = db.runs or {}                   -- saved party/raid runs (Runs.lua)
    db.loot = db.loot or {}                   -- loot state (Loot.lua)
    db.loot.history = db.loot.history or {}   -- award history
    db.loot.reserves = db.loot.reserves or {} -- [itemId] = { {player, class}, ... } (imported SR)
    db.settings = db.settings or {}           -- cosmetic/UI prefs only — never gates core recording
    db.consent = nil                          -- removed: core recording is unconditional
    ns.DB = db
    -- crash recovery: an 'active' session on load means we died mid-run; finalize it so it uploads.
    if db.active and db.sessions[db.active] then
      local orphan = db.sessions[db.active]
      orphan.endedEpoch = orphan.endedEpoch or GetServerTime()
      orphan.recovered = true
      db.active = nil
      ns.msg("recovered an interrupted session (" .. orphan.id .. ") — it will upload normally")
    end
  elseif event == "PLAYER_ENTERING_WORLD" then
    ns.Logging.startGuardian() -- always-on logging everywhere, from the moment we log in
    if not ns.DB.settings.welcomed then
      ns.DB.settings.welcomed = true
      C_Timer.After(4, function()
        ns.msg("installed — combat logging & recording are |cff46b36bon automatically|r, everywhere. Open the panel with |cffffffff/rb|r.")
      end)
    end
    checkContext()
  elseif event == "ZONE_CHANGED_NEW_AREA" then
    ns.Logging.enforce() -- zoning can drop combat logging; re-assert immediately
    checkContext()
  elseif event == "PLAYER_LOGOUT" then
    if ns.Recorder.active() then ns.Recorder.stop("logout") end
  elseif handlers[event] then
    handlers[event](...)
  end
end)

-- Minimal event set: boot, session lifecycle, logging re-assert on combat start, and level-ups.
-- Everything else (fights, deaths, encounters, zones, meters) lives in the combat-log file.
local events = {
  "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "PLAYER_LOGOUT",
  "PLAYER_REGEN_DISABLED", "PLAYER_LEVEL_UP",
}
for _, ev in ipairs(events) do f:RegisterEvent(ev) end
