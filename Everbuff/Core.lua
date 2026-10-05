-- Everbuff.GG · Core.lua - boot, event router, slash.
--
-- Keeps combat logging on (self-healing via ns.Logging guardian) and captures leveling + dungeon
-- landmarks so everbuff.gg can rebuild the session.
--
-- Cross-client: the primary target is the Midnight "WoW Forever" model (Secret Values → CLEU-free,
-- the file is the source of truth). The same code runs on Classic/SoD (our current data-gathering
-- testbed): Midnight-only APIs (C_DamageMeter, C_ChallengeMode / M+) are feature-detected and their
-- events are only registered where they exist. Flags live on ns (set in Logging.lua).

local ADDON, ns = ...

-- the ONE version number lives in the TOC (## Version); read it so the header can never drift from the package
do
  local meta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  local ok, v = pcall(function() return meta and meta(ADDON, "Version") end)
  ns.VERSION = (ok and type(v) == "string" and v ~= "" and v) or "dev"
end
ns.GOLD = "|cff0cd29d"   -- the chat prefix in the accent (tan left the interface, #36)
ns.CYAN = "|cff35eebb"
function ns.msg(text) print(ns.GOLD .. "everbuff.gg|r: " .. text) end

-- Nothing is opened or changed in combat (founder, 2026-09-30): the flag is the desktop's combat signal, and
-- moving, resizing or hiding it mid-fight loses a combat flip. Settings, /eb commands and every way of moving the
-- flag wait until the fight is over. Returns true (and says so once) when the caller must stop.
function ns.blockedInCombat()
  local fighting = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
  if fighting then ns.msg("not during combat. Try again after the fight.") end
  return fighting and true or false
end

EverbuffDB = EverbuffDB or nil -- materialized on ADDON_LOADED

local f = CreateFrame("Frame")
ns.eventFrames[#ns.eventFrames + 1] = f

-- ── SavedVariables schema 2: the data mirrors the product structure ─────────────
--   settings                      what the player configured
--   sessions[id] (+ active)       HOME: one record per login -> logout, with live counters; every fight,
--                                 pickup and event carries s = its session id
--   combat.fights                 COMBAT: every fight (dungeon runs and deaths are derived views)
--   loot.log                      LOOT: every pickup (item or coin row)
--   characters[guid]              CHARACTER, one block per character keyed by its GUID (#23): xp, played,
--                                 professions, reputation, durability, gold totals and sinks, ...
--   story.events                  the feed (timeline) behind Home
-- Facts are stored once; anything a tab shows that can be derived is derived at render time.
function ns.migrateDB(db)
  db.settings = db.settings or {}
  db.sessions = db.sessions or {}
  db.combat = db.combat or {}
  db.loot = db.loot or {}
  db.story = db.story or {}
  if (tonumber(db.schema) or 1) < 2 then
    -- v1 kept everything at the top level; move each key into its area, then drop the old slot
    db.combat.fights = db.fights or db.combat.fights; db.fights = nil
    db.combat.fightSeq = db.fightSeq or db.combat.fightSeq; db.fightSeq = nil
    db.combat.uploadedThrough = db.uploadedThrough or db.combat.uploadedThrough; db.uploadedThrough = nil
    db.loot.log = db.lootlog or db.loot.log; db.lootlog = nil
    db.gold = nil   -- the account-wide gold ledger mixed every character: discarded (#23)
    db.story.events = db.eventlog or db.story.events; db.eventlog = nil
    db._inInstance = nil
    for _, k in ipairs({ "xp", "played", "playedAtLevel", "professions", "reputation", "durability", "ilvl", "seenZones", "itemUses", "crafts", "recipes", "flightTime" }) do
      db[k] = nil   -- account-wide character data mixed every character: discarded (#23)
    end
    db.session = nil; db.runs = nil; db.consent = nil   -- superseded (sessions carry the pace counters) / never built
    db.schema = 2
  end
  db.combat.fights = db.combat.fights or {}
  db.combat.fightSeq = db.combat.fightSeq or 0
  db.loot.log = db.loot.log or {}
  db.loot.history = db.loot.history or {}     -- raid loot council (Later)
  db.loot.reserves = db.loot.reserves or {}
  -- Data per character, always (#23, approved 2026-10-04, option A). The account-wide `character` block, the
  -- lifetime `loot.gold` ledger and the `characterLegacy` copy of both (0.9.30 and 0.9.31) mixed every character on
  -- the account, so they are invalid and deleted on load, never read and never attributed (founder rule,
  -- 2026-10-05: data that does not fit the current system is discarded). Each character's block starts from what
  -- that character writes.
  db.character, db.loot.gold, db.characterLegacy = nil, nil, nil
  db.story.inInstance = nil   -- now per character (characters[guid].inInstance)
  db.characters = db.characters or {}
  db.story.events = db.story.events or {}
  -- loot rows from before schema 2 carry no session id (#17): the backend selects rows by session, so they can never
  -- upload; drop them
  for i = #db.loot.log, 1, -1 do
    if type(db.loot.log[i]) ~= "table" or db.loot.log[i].s == nil then table.remove(db.loot.log, i) end
  end
  return db
end

-- The logged-in character's block (#23): everything that belongs to one character lives under its GUID
-- (`UnitGUID("player")`, the session records' `guid`). Before the GUID is known (or if the client ever hid it) the
-- writes land in a scratch block that is never saved, so no character's data is written into another's.
local charScratch
function ns.newCharBlock() return { xp = { gained = 0 }, played = {}, gold = { looted = 0, gained = 0, spent = 0 } } end
function ns.charGuid()
  local g = UnitGUID and UnitGUID("player")
  if type(g) ~= "string" or (issecretvalue and issecretvalue(g)) or g == "" then return nil end
  return g
end
function ns.char()
  local db, g = ns.DB, ns.charGuid()
  if not (db and g) then charScratch = charScratch or ns.newCharBlock(); return charScratch end
  db.characters = db.characters or {}
  local c = db.characters[g]
  if c == nil then
    c = ns.newCharBlock()
    c.name = UnitNameUnmodified and UnitNameUnmodified("player") or (UnitName and UnitName("player")) or nil
    c.realm = GetRealmName and GetRealmName() or nil
    if type(c.name) ~= "string" or (issecretvalue and issecretvalue(c.name)) then c.name = nil end
    if type(c.realm) ~= "string" or (issecretvalue and issecretvalue(c.realm)) then c.realm = nil end
    db.characters[g] = c
  end
  return c
end

-- Whether a session-stamped row (fight, loot row, event, trade) is the logged-in character's (#23): its session record
-- carries the character's GUID. Fights name their session in `session`, every other row in `s`. Before the GUID is
-- known every row counts, since there is nothing to tell them apart by.
local function rowSession(row) return row and (row.s or row.session) end
function ns.isMine(row)
  local g = ns.charGuid()
  if not g then return true end
  local sid = rowSession(row)
  local s = sid and ns.DB and ns.DB.sessions and ns.DB.sessions[sid]
  return s ~= nil and s.guid == g
end
-- Whether a session record is the logged-in character's (#23), by the same rule as ns.isMine.
function ns.isMySession(sess)
  local g = ns.charGuid()
  if not g then return true end
  return sess ~= nil and sess.guid == g
end
-- The rows of `list` that are the logged-in character's, in order (#23). Every pane lists through this so it shows
-- one character; the stored lists stay as they are (the desktop and the backend read every character's rows).
function ns.mine(list)
  local out = {}
  if not list then return out end
  local g = ns.charGuid()
  if not g then for i = 1, #list do out[i] = list[i] end return out end
  local sessions = (ns.DB and ns.DB.sessions) or {}
  local ok = {}   -- session id -> true/false, so a long list reads each session record once
  for _, r in ipairs(list) do
    local sid = rowSession(r)
    if sid ~= nil then
      local m = ok[sid]
      if m == nil then local s = sessions[sid]; m = (s ~= nil and s.guid == g); ok[sid] = m end
      if m then out[#out + 1] = r end
    end
  end
  return out
end

-- Drop the fights, loot rows and events whose session record is gone (#17): the backend selects all three by
-- session id, so a row without its session never uploads. Returns the number of rows removed.
function ns.dropOrphans(db)
  local removed = 0
  local function sweep(list, key)
    if not list then return end
    for i = #list, 1, -1 do
      local id = list[i][key]
      if id == nil or db.sessions[id] == nil then table.remove(list, i); removed = removed + 1 end
    end
  end
  sweep(db.combat.fights, "session")
  sweep(db.loot.log, "s")
  sweep(db.story.events, "s")
  return removed
end

-- ── upload ack channel (addon side) ─────────────────────────────────────────────
-- The desktop tells the addon what it has already uploaded so the addon can prune. Two inbound paths,
-- both landing in ns.applyAck:
--   A. `EverbuffAck` companion SavedVariable, written by the desktop ONLY while WoW is closed:
--      EverbuffAck = { uids = { ["<fight uid>"] = true, ... }, through = <epoch> }
--      Read on ADDON_LOADED; uids are cleared after use so the file never grows.
--   B. a paste code from the desktop: EB-ACK-<epoch>[:<uid>,<uid>,...]  (/eb ack <code>, or Settings > Data)
-- Effect: fights with an acked uid, or that started at or before `through`, are marked uploaded and pruned;
-- loot rows, events and finished sessions at or before `through` are pruned. `combat.lastAck` records it.
-- Keep a record list at `cap` rows (ADDON-2, everbuff-backend #68): drop the oldest row of an earlier session first,
-- and the running session's own rows only when nothing else is left. Rows carry their session id in `s`. Acked rows
-- are already gone (applyAck prunes them), so everything here still waits for an upload.
function ns.trimToCap(list, cap)
  if not list then return end
  local active = ns.DB and ns.DB.active
  while #list > cap do
    local drop = 1
    if active then
      for i = 1, #list do
        if list[i].s ~= active then drop = i; break end
      end
    end
    table.remove(list, drop)
  end
end

function ns.applyAck(ack, source)
  local db = ns.DB
  if not (db and type(ack) == "table") then return 0, 0 end
  local through = tonumber(ack.through) or 0
  local uids = type(ack.uids) == "table" and ack.uids or {}
  local marked = 0
  for _, f in ipairs(db.combat.fights or {}) do
    if (f.uid and uids[f.uid]) or (through > 0 and (f.startEpoch or math.huge) <= through) then
      if f.uploaded ~= true then marked = marked + 1 end
      f.uploaded = true
    end
  end
  local removed = (ns.Fights and ns.Fights.pruneUploaded and ns.Fights.pruneUploaded()) or 0
  if through > 0 then
    local function pruneT(list) if not list then return end for i = #list, 1, -1 do if (list[i].t or 0) <= through then table.remove(list, i) end end end
    pruneT(db.loot.log); pruneT(db.story.events)
    for id, sess in pairs(db.sessions or {}) do
      if id ~= db.active and sess.endedEpoch and sess.endedEpoch <= through then db.sessions[id] = nil end
    end
  end
  local now = (GetServerTime and GetServerTime()) or time()
  db.combat.lastAck = { at = now, through = through > 0 and through or nil, fights = marked, source = source or "file" }
  if ack.uids then ack.uids = {} end          -- consumed: the companion file cannot grow
  ack.applied = now
  return marked, removed
end
-- "EB-ACK-1758800000" or "EB-ACK-1758800000:Hart-Realm-1758..-3f2a,Hart-Realm-..." -> ack table, or nil
function ns.parseAckCode(code)
  code = tostring(code or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local epoch, rest = code:match("^EB%-ACK%-(%d+):?(.*)$")
  if not epoch then return nil end
  local ack = { through = tonumber(epoch), uids = {} }
  for uid in (rest or ""):gmatch("[^,%s]+") do ack.uids[uid] = true end
  if ack.through == 0 then ack.through = nil end
  return ack
end

-- ── context detection (one session per play session) ──
-- Raid/dungeon → a full "instance" session (encounters, challenge mode, combat edges, meter).
-- Everywhere else → a lightweight "world" session for leveling (level-ups, deaths, zone changes).
-- We transition between them so exactly one session is active at a time.
-- One session per play session (login → logout). The combat log delimits fights, so we don't churn
-- sessions on zoning - the addon record is a thin identity/leveling/integrity beacon.
local function checkContext()
  if not ns.Recorder.active() then ns.Recorder.start() end
end
ns.checkContext = checkContext
ns.checkInstance = checkContext -- back-compat alias

-- ── event router (minimal - the combat-log FILE is the real record) ───────────
local handlers = {
  -- Re-assert logging the instant combat starts (the one moment it must be on), then the file does
  -- the rest. We do NOT record encounters/zones/deaths/meters here - those are all in the log.
  PLAYER_REGEN_DISABLED = function() ns.Logging.enforce() end,
  PLAYER_LEVEL_UP = function(level) ns.Recorder.onLevelUp(level) end,
}

-- ── slash ─────────────────────────────────────────────────────────────────────
SLASH_EVERBUFF1 = "/eb"
SLASH_EVERBUFF2 = "/everbuff"
SlashCmdList.EVERBUFF = function(arg)
  if ns.blockedInCombat() then return end
  arg = (arg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if arg == "" or arg == "show" or arg == "open" then
    if ns.UI then ns.UI.Toggle() else ns.msg("UI not loaded") end
  elseif arg == "rec" or arg == "recording" then
    if ns.UI then ns.UI.Open("Combat", "fights") end
  -- NOTE: /eb loot · /eb ready · /eb crew (raid-lead tools) are DEFERRED - see addon/Everbuff/future/.
  elseif arg:match("^ack") then
    local ack = ns.parseAckCode((arg:gsub("^ack%s*", "")))
    if ack then
      local marked, removed = ns.applyAck(ack, "paste")
      ns.msg(("desktop sync applied: %d fight%s acked, %d pruned"):format(marked, marked == 1 and "" or "s", removed))
    else
      ns.msg("usage: /eb ack EB-ACK-<epoch>[:<uid>,<uid>...]  (the desktop app shows this code)")
    end
  elseif arg == "export" or arg == "end" then
    if ns.Recorder.active() then
      ns.Recorder.stop("manual export")
      ns.msg("session closed")
      -- what happens next belongs to a new session (#17): rows stamped with no session never upload
      ns.Recorder.start()
    else ns.msg("no active session") end
  elseif arg == "status" then
    local sess = ns.Recorder.active()
    local aclOn, combatOn = ns.Logging.state()
    if sess then
      ns.msg(("|cff46b36bcapturing|r · %s · session %s · %d markers · logging acl=%s combat=%s")
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
    ns.msg(("client: %s · %d session(s) stored"):format(ns.flavor, n))
  elseif arg == "debug" or arg:match("^debug ") then
    if ns.Debug then ns.Debug.command((arg:gsub("^debug%s*", ""))) else ns.msg("debug module not loaded") end
  elseif arg == "wipe" then
    -- the sessions go with their fights, loot and events (#17), which could never upload without them; a running
    -- session is replaced by a fresh one so what follows still uploads
    local running = ns.Recorder.active() ~= nil
    ns.Recorder.discard()
    ns.DB.sessions = {}; ns.DB.active = nil
    ns.dropOrphans(ns.DB)
    ns.msg("stored sessions wiped")
    if running then ns.Recorder.start() end
  elseif arg:match("^corner") then
    local where = arg:gsub("^corner%s*", "")
    if ns.Emitter and ns.Emitter.setCorner(where) then
      ns.msg("event overlay moved to |cffffffff" .. ns.DB.settings.emitCorner .. "|r")
    else
      ns.msg("usage: /eb corner tl|tr|bl|br (top/bottom, left/right)")
    end
  elseif arg == "testevent" or arg == "test" then
    if ns.Emitter then
      local samples = {
        { "LEVELUP", {} }, { "ZONE", { zone = GetRealZoneText() or "Stranglethorn Vale" } },
        { "DUNGEON", { name = "Deadmines" } }, { "KILL", { name = "Edwin VanCleef" } },
        { "DEATH", {} },
      }
      local i = 0
      local function step()
        i = i + 1
        if samples[i] then ns.Emitter.event(samples[i][1], samples[i][2]); C_Timer.After(3, step) end
      end
      step()
      ns.msg("firing test events into the " .. ((ns.DB.settings.emitCorner) or "TOPLEFT") .. " toast")
    end
  elseif arg:match("^combat") then
    local on = not arg:match("off")
    if ns.Emitter then ns.Emitter.testCombat(on); ns.msg("combat indicator " .. (on and "ON (crossed swords)" or "off")) end
  else
    ns.msg("commands: /eb (open) · /eb status · /eb corner tl|tr|bl|br · /eb testevent · /eb ack <code> · /eb debug · /eb export · /eb wipe")
  end
end

-- ── boot ───────────────────────────────────────────────────────────────────────
f:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" and ... == ADDON then
    -- second SavedVariable (load canary), declared in the TOC. Its counter climbing across a full
    -- restart proves SavedVariables persisted; on the WoW Forever beta they currently do not (client bug).
    EverbuffTest = (type(EverbuffTest) == "table") and EverbuffTest or {}
    EverbuffTest.n = (tonumber(EverbuffTest.n) or 0) + 1
    EverbuffDB = EverbuffDB or {}
    local db = EverbuffDB
    ns.migrateDB(db)
    ns.DB = db
    if ns.flushBlocked then ns.flushBlocked() end   -- blocks seen before the save file loaded
    -- the desktop's ack (companion SavedVariable, written while WoW was closed): mark + prune
    if type(EverbuffAck) == "table" and (next(EverbuffAck.uids or {}) or tonumber(EverbuffAck.through)) and not EverbuffAck.applied then
      local marked, removed = ns.applyAck(EverbuffAck, "file")
      ns.msg(("desktop sync applied: %d fight%s acked, %d pruned"):format(marked, marked == 1 and "" or "s", removed))
    end
    -- drop fights the desktop already uploaded to the backend (upload-driven cleanup handshake)
    if ns.Fights and ns.Fights.pruneUploaded then ns.Fights.pruneUploaded() end
    -- one clean load line: confirms SavedVariables came back (numbers > 0 after you've played = persisting)
    ns.msg(("ready · %d fights · %d loot · flag %s"):format(
      #db.combat.fights, #db.loot.log, tostring(db.settings.emitCorner or "default")))
  elseif event == "PLAYER_ENTERING_WORLD" then
    local isLogin, isReload = ...
    ns.reloadingUi = isReload and true or false   -- R.start reopens the session a reload's PLAYER_LOGOUT closed (#14)
    -- a REAL login with a session still marked active means the last session never closed (crash or
    -- disconnect): finalize it so it uploads. A /reload keeps the session (Recorder.start resumes it).
    if isLogin and ns.Recorder.active() then ns.Recorder.stop("relogin") end   -- a stale in-memory session (never in a real client, but be safe)
    -- a real login after a clean logout: the last session ended at that logout and stays as it is (#14)
    if isLogin and ns.DB.active and ns.DB.sessions[ns.DB.active] and ns.DB.sessions[ns.DB.active].endedBy == "logout" then
      ns.DB.active = nil
    end
    if isLogin and ns.DB.active and ns.DB.sessions[ns.DB.active] then
      local orphan = ns.DB.sessions[ns.DB.active]
      orphan.endedEpoch = orphan.endedEpoch or GetServerTime()
      orphan.recovered = true
      ns.DB.active = nil
      ns.msg("recovered an interrupted session (" .. orphan.id .. ")")
    end
    ns.Logging.startGuardian() -- keep combat logging on from login
    ns.Logging.enforce(true)    -- and after every loading screen: one header per world entry (#15)
    if ns.UI and ns.UI.buildMinimapButton then pcall(ns.UI.buildMinimapButton) end
    if not ns.DB.settings.welcomed then
      ns.DB.settings.welcomed = true
      C_Timer.After(4, function()
        ns.msg("ready. Open the panel with |cffffffff/eb|r.")
      end)
    end
    checkContext()
  elseif event == "ZONE_CHANGED_NEW_AREA" then
    ns.Logging.enforce() -- zoning can drop combat logging; re-assert immediately
    checkContext()
  elseif event == "PLAYER_LOGOUT" then
    if ns.Recorder.active() then ns.Recorder.pause("logout") end
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
