-- Everbuff · Segments.lua - the MINIMAL addon record (a beacon, not a firehose).
--
-- Data hierarchy: combat log (primary) > computer vision > SavedVariables (this file, LEAST).
-- SavedVariables only flush on /reload, so we deliberately store the least here - only what the
-- combat log CANNOT give and that ties an uploaded log to an account:
--   • identity + correlation (character/realm/guild/class, session start time, build/flavor)
--   • level-ups (the combat log has no character level)
--   • logging integrity (posture at start + any repairs) so the uploader can trust the file is gapless
-- Everything else - fights, damage/healing, deaths, encounters, zones, roster/gear - is parsed from
-- the combat-log file itself (or, later, computer vision), never duplicated here.

local ADDON, ns = ...
local R = {}
ns.Recorder = R

local ROW_CAP = 5000 -- a beacon; identity + a night of level-ups + repairs is a few dozen rows
local S = { session = nil, seq = 0 }
R.state = S

local function hex16() return string.format("%04x", math.random(0, 65535)) end
local function newId() return date("%y%m%d%H%M%S") .. "-" .. hex16() end
local function playerLevel() return (UnitLevel and UnitLevel("player")) or 0 end

local function row(kind, payload)
  local sess = S.session
  if not sess then return end
  local n = #sess.segments
  if n >= ROW_CAP then return end
  S.seq = S.seq + 1
  -- TAB-delimited (not "|"): this client's SavedVariables loader rejects the whole file when stored
  -- strings carry pipes. Desktop segment parser must split on \t. Payloads below are tab-delimited too.
  sess.segments[n + 1] = string.format("%d\t%d\t%.3f\t%s\t%s", S.seq, GetServerTime(), GetTime(), kind, payload or "")
end
R.row = row

-- One session per play session (login → logout). Not per-instance: the log already delimits fights.
function R.start()
  if S.session then return end
  -- a /reload keeps the session: the record is still marked active and not ended, so resume it
  local prev = ns.DB and ns.DB.active and ns.DB.sessions[ns.DB.active]
  if prev and not prev.endedEpoch then
    S.session, S.seq = prev, #(prev.segments or {})
    row("RESUME", "reload")
    return
  end
  local name, itype = GetInstanceInfo()
  local context = (itype == "raid" or itype == "party") and name or (GetRealZoneText() or "World")
  local sess = {
    id = newId(), schema = 4,
    startedEpoch = GetServerTime(), startedMono = GetTime(),
    build = select(4, GetBuildInfo()), project = WOW_PROJECT_ID, flavor = ns.flavor, addonVersion = ns.VERSION,
    player = UnitNameUnmodified("player"), realm = GetRealmName(),
    guid = (UnitGUID and UnitGUID("player")) or nil, startedLocal = time(),   -- integrity manifest: who + local clock
    guild = (GetGuildInfo("player")) or "", class = select(2, UnitClass("player")),
    level = playerLevel(), level0 = playerLevel(),
    context = context,
    logging = ns.Logging.snapshot(),
    segments = {},
    -- live counters (HOME's session cards and per-hour rates): bumped by the capture modules
    xp = 0, gained = 0, spent = 0, kills = 0, deaths = 0, fights = 0, items = 0, dungeons = 0,
  }
  ns.DB.sessions[sess.id] = sess
  ns.DB.active = sess.id
  S.session, S.seq = sess, 0

  row("SESSION_START", string.format("%s\t%s\t%s\tlvl=%d", sess.player or "?", sess.realm or "?", context, sess.level))
  local aclOn, combatOn = ns.Logging.enforce()
  row("LOGGING", string.format("acl=%d\tcombat=%d", aclOn and 1 or 0, combatOn and 1 or 0))
  ns.msg(("recording %s%s|r · %ssession %s|r · the combat log is the record; this is just the beacon")
    :format(ns.CYAN, context, ns.CYAN, sess.id))
end

function R.stop(reason)
  local sess = S.session
  if not sess then return end
  row("SESSION_END", reason or "")
  sess.endedEpoch, sess.endedMono, sess.endedLocal = GetServerTime(), GetTime(), time()
  ns.DB.active = nil
  S.session = nil
  ns.msg(("session ended (%s) · %d markers"):format(reason or "ended", #sess.segments))
end

function R.active() return S.session end
-- the session record everything since login accrues to (nil before the first PLAYER_ENTERING_WORLD)
function R.current() return S.session or (ns.DB and ns.DB.active and ns.DB.sessions[ns.DB.active]) or nil end
-- add n (default 1) to a live counter on the current session
function R.bump(key, n)
  local sess = R.current(); if not sess then return end
  sess[key] = (tonumber(sess[key]) or 0) + (n or 1)
end

-- Level-ups are the one thing the combat log genuinely can't give us.
function R.onLevelUp(level)
  local sess = S.session; if not sess then return end
  sess.level = level or playerLevel()
  row("LEVEL_UP", string.format("%s\t%s", tostring(sess.level or ""), GetRealZoneText() or "?"))
end

-- Called by the logging guardian when it had to repair a mid-session drop - marks a possible gap so
-- the uploader knows the file might be missing a slice there.
function R.noteLoggingRepair(acl, combat)
  if not S.session then return end
  row("LOGGING_REPAIR", string.format("acl=%d\tcombat=%d", acl and 1 or 0, combat and 1 or 0))
end
