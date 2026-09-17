-- run.lua — load Everbuff under the WoW mock and exercise its logic + UI, on BOTH client flavors.
-- Usage:  luajit run.lua  [addonDir]
-- Tier-1 of the dev loop: catches runtime errors and verifies logic with no game.

local here = arg and arg[0] and arg[0]:gsub("[^/\\]+$", "") or "./"
local ADDON_DIR = (arg and arg[1]) or (here .. "../Everbuff/")
local M = dofile(here .. "wow_mock.lua")

-- load the addon exactly as WoW would (shared ns, vararg = ADDON, ns), under a chosen flavor.
local FILES = { "Logging.lua", "Segments.lua", "UI.lua", "Debug.lua", "Recording.lua", "Signal.lua", "Core.lua" }
local function loadAddon(flavor)
  M.reset()
  M.setFlavor(flavor or "mainline")
  local ns = {}
  for _, f in ipairs(FILES) do
    local chunk, err = loadfile(ADDON_DIR .. f)
    if not chunk then M.realprint("LOAD ERROR " .. f .. ": " .. tostring(err)); os.exit(1) end
    local okc, e = pcall(chunk, "Everbuff", ns)
    if not okc then M.realprint("RUNTIME ERROR loading " .. f .. ": " .. tostring(e)); os.exit(1) end
  end
  return ns
end

-- ── tiny test framework ───────────────────────────────────────────────────────
local pass, fail = 0, 0
local function ok(cond, msg)
  if cond then pass = pass + 1 else fail = fail + 1; M.realprint("  FAIL: " .. tostring(msg)) end
end
local function eq(a, b, msg)
  ok(a == b, (msg or "eq") .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")")
end
local function section(t) M.realprint("\n== " .. t .. " ==") end
local function has(sess, kind)
  for _, r in ipairs(sess.segments) do if r:find(kind) then return true end end
  return false
end
local function count(sess, kind)
  local n = 0; for _, r in ipairs(sess.segments) do if r:find(kind) then n = n + 1 end end; return n
end

local function setRaid(members)
  M.world.inInstance = true; M.world.raid = true; M.world.instanceType = "raid"
  M.world.instance = { "Emberhall", "raid", 16, "Mythic", 20, 0, false, 2769 }
  M.world.units = {}
  for i, m in ipairs(members) do M.world.units["raid" .. i] = m end
end
local function setParty(members)
  M.world.inInstance = true; M.world.raid = false; M.world.instanceType = "party"
  M.world.instance = { "Blackfathom Deeps", "party", 1, "Normal", 5, 0, false, 48 }
  M.world.units = { player = members[1] }
  for i = 2, #members do M.world.units["party" .. (i - 1)] = members[i] end
end

-- ════════════════════════════════════════════════════════════════════════════════
--  MAINLINE  (Midnight / "WoW Forever")
-- ════════════════════════════════════════════════════════════════════════════════
section("boot (mainline / WoW Forever)")
local ns = loadAddon("mainline")
M.fireEvent("ADDON_LOADED", "Everbuff")
M.flushAfters()
ok(ns.DB ~= nil, "ns.DB initialized")
ok(type(ns.DB.sessions) == "table", "sessions table")
ok(ns.UI and ns.Recorder and ns.Logging, "modules attached (UI/Recorder/Logging)")
ok(ns.DB.consent == nil, "consent removed (recording is unconditional)")
ok(ns.isMainline, "detected mainline client")
ok(ns.hasChallengeMode, "Mythic+ challenge mode available on mainline")
ok(ns.flavor == "mainline", "flavor tagged 'mainline'")

section("always-on logging + session")
M.world.acl = "0"; M.world.combat = false        -- pretend logging is OFF
M.fireEvent("PLAYER_ENTERING_WORLD")             -- guardian forces logging on + starts one session
M.flushAfters()
eq(M.world.acl, "1", "advanced combat logging forced ON")
eq(M.world.combat, true, "combat logging forced ON")
local sess = ns.Recorder.active()
ok(sess ~= nil, "one session auto-started for the play session")
ok(sess.player and sess.realm, "session carries identity (character + realm) for log correlation")

section("minimal record: level-ups only, no combat-log duplication")
M.world.level = 1
M.fireEvent("PLAYER_LEVEL_UP", 2); M.world.level = 2
ok(has(sess, "LEVEL_UP"), "LEVEL_UP recorded (the combat log has no character level)")
local id1 = sess.id
M.fireEvent("ZONE_CHANGED_NEW_AREA")
eq(ns.Recorder.active().id, id1, "session does NOT churn on zoning (the log delimits fights)")
ok(not has(sess, "ENCOUNTER"), "no encounter rows — those come from the combat log, not the addon")
ok(not has(sess, "COMBAT_START"), "no combat-edge rows")
ok(not has(sess, "METER"), "no meter rows")

section("logging guardian: nag + repair")
M.world.acl = "0"
local aclOn, _, changed = ns.Logging.enforce()
ok(changed, "enforce() detects and repairs logging turned off")
eq(M.world.acl, "1", "logging repaired to ON")
ns.Recorder.noteLoggingRepair(true, true)
ok(has(sess, "LOGGING_REPAIR"), "LOGGING_REPAIR recorded during a session")
M.world.acl = "0"; M.world.combat = false; M.world.aclLocked = true
local beforePrints = #M.prints
M.tick()                                          -- run the guardian tick with logging stuck off
ok(#M.errors > 0 or #M.raidWarnings > 0, "heavy nag hit the UI (error text / raid warning) when logging stuck off")
local naggedChat = false
for i = beforePrints + 1, #M.prints do if tostring(M.prints[i]):find("ADVANCED COMBAT LOGGING") then naggedChat = true end end
ok(naggedChat, "chat nag printed when logging is off")
M.world.aclLocked = false
M.tick()
eq(M.world.acl, "1", "guardian recovers logging once the client allows it")

section("anti-tamper (block + name an addon that disables logging)")
M.debugstack = "[C]: ?\nInterface\\AddOns\\EvilLogStopper\\Evil.lua:12: in function <...>\n"
M.world.combat = true; M.world.acl = "1"; M.world.aclLocked = false
local beforeRepairs = ns.Logging.repairs
LoggingCombat(false) -- a "malicious" addon turns combat logging off
eq(M.world.combat, true, "logging force re-enabled the instant it was disabled")
ok(ns.Logging.repairs > beforeRepairs, "tamper counted as a repair")
eq(ns.Logging.lastCulprit, "EvilLogStopper", "named the culprit addon from the call stack")
local tamperWarned = false
for _, p in ipairs(M.prints) do if tostring(p):find("EvilLogStopper") then tamperWarned = true end end
ok(tamperWarned, "warned the user, naming the culprit")

section("roster (UI.groupMembers)")
setRaid({
  { name = "Hart", realm = "Kazzak", class = "Paladin", classFile = "PALADIN", role = "TANK", subgroup = 1 },
  { name = "Dave", realm = "Arathor", class = "Priest", classFile = "PRIEST", role = "HEALER", subgroup = 1 },
  { name = "Isolyte", realm = "Nemesis", class = "Mage", classFile = "MAGE", role = "DAMAGER", subgroup = 2 },
})
local members = ns.UI.groupMembers()
eq(#members, 3, "3 raid members")
eq(members[1].name, "Hart", "first member name")
eq(members[3].classFile, "MAGE", "class file parsed")

section("UI: every tab builds")
for _, tabName in ipairs({ "Recording" }) do
  local before = #M.fontstrings
  local okb, e = pcall(ns.UI.Open, tabName)
  ok(okb, "Open('" .. tabName .. "') no throw" .. (okb and "" or ": " .. tostring(e)))
  local errText, texts = nil, {}
  for i = before + 1, #M.fontstrings do
    local t = M.fontstrings[i].__text
    if t then
      texts[#texts + 1] = t
      if tostring(t):find("error building tab") then errText = t end
    end
  end
  ok(errText == nil, "tab '" .. tabName .. "' built cleanly" .. (errText and (": " .. errText) or ""))
  M.realprint("   [" .. tabName .. "] " .. #texts .. " labels")
end
-- header status ticker: fires on the panel's OnUpdate whenever it's open with an active session.
-- Must read sess.context (not the removed sess.instance.name), else it errors live while recording.
ns.UI.Toggle() -- show the frame so refreshStatus doesn't early-return
local okrs, ers = pcall(ns.UI.refreshStatus)
ok(okrs, "UI.refreshStatus() runs with an active session" .. (okrs and "" or ": " .. tostring(ers)))

section("debug bridge (Tier 2)")
ok(ns.Debug ~= nil, "Debug module loaded")
SlashCmdList.EVERBUFF("debug group")             -- toggle fake group ON
ok(ns.Debug.active(), "fake group active")
eq(#ns.UI.groupMembers(), 5, "fake 5-man roster served to tabs")
SlashCmdList.EVERBUFF("debug")                    -- write snapshot
ok(ns.DB.debug.snapshot ~= nil, "diagnostics snapshot written to SavedVariables")
eq(ns.DB.debug.snapshot.version, ns.VERSION, "snapshot has version")

section("slash")
ok(type(SlashCmdList.EVERBUFF) == "function", "slash handler registered")
pcall(SlashCmdList.EVERBUFF, "status")

-- ════════════════════════════════════════════════════════════════════════════════
--  CLASSIC / SoD  (the current data-gathering testbed)
-- ════════════════════════════════════════════════════════════════════════════════
section("cross-client: Classic / SoD")
local nsc = loadAddon("vanilla")
M.fireEvent("ADDON_LOADED", "Everbuff"); M.flushAfters()
ok(nsc.isClassic, "detected Classic/SoD client")
ok(not nsc.hasChallengeMode, "no Mythic+ challenge mode on Classic")
ok(not nsc.hasDamageMeter, "no C_DamageMeter on Classic")
ok(M.eventFrames["CHALLENGE_MODE_START"] == nil, "challenge-mode events NOT registered on Classic (would error live)")
-- Encounter DATA still comes from the log only. The one sanctioned listener is the Signal (visual
-- event channel), which uses ENCOUNTER_START as an on-screen video↔log sync ANCHOR — so exactly one
-- frame (Signal's) may be registered; the Recorder itself must not duplicate log data.
ok(M.eventFrames["ENCOUNTER_START"] ~= nil and #M.eventFrames["ENCOUNTER_START"] == 1,
  "ENCOUNTER_START registered exactly once (Signal anchor only; data stays in the log)")

M.world.acl = "0"; M.world.combat = false
M.fireEvent("PLAYER_ENTERING_WORLD"); M.flushAfters()
eq(M.world.acl, "1", "logging forced ON on Classic too")
local cws = nsc.Recorder.active()
ok(cws ~= nil, "one session on Classic")
eq(cws.flavor, "classic", "session tagged with the classic flavor")

M.fireEvent("PLAYER_LEVEL_UP", 12); M.world.level = 12
ok(has(cws, "LEVEL_UP"), "leveling landmark captured on Classic (the SoD data we want)")

-- zoning into a dungeon must NOT churn the session (the log delimits fights), and encounter
-- events are unregistered no-ops here — the addon never duplicates what the combat log records.
M.fireEvent("ZONE_CHANGED_NEW_AREA")
eq(nsc.Recorder.active().id, cws.id, "session does not churn on zoning (Classic)")
local okEnc = pcall(M.fireEvent, "ENCOUNTER_START", 409, "Gelihast", 0, 5)
          and pcall(M.fireEvent, "ENCOUNTER_END", 409, "Gelihast", 0, 5, true)
ok(okEnc, "encounter events are safe no-ops on Classic")
ok(not has(cws, "ENCOUNTER"), "no encounter rows on Classic either")
for _, tabName in ipairs({ "Recording" }) do
  ok((pcall(nsc.UI.Open, tabName)), "tab '" .. tabName .. "' builds on Classic")
end

-- ════════════════════════════════════════════════════════════════════════════════
--  SIGNAL — the visual event channel (addon → desktop via the screen recording)
-- ════════════════════════════════════════════════════════════════════════════════
section("visual event channel (Signal)")
local nss = loadAddon("mainline")
M.fireEvent("ADDON_LOADED", "Everbuff"); M.flushAfters()
ok(nss.Signal ~= nil, "Signal module loads")
-- direct emit: encoding invariants
local s1 = nss.Signal.Emit(2, 7) -- QUEST_ACCEPT payload 7
eq(s1.etype, 2, "etype encodes")
eq(s1.payload, 7, "payload encodes")
eq(s1.check, (s1.etype + s1.seq + s1.payload) % 16, "checksum = (type+seq+payload) % 16")
eq(#s1.pattern, 10, "10 cells")
eq(s1.pattern[1], 2, "sentinel cell 1 = magenta")
eq(s1.pattern[2], 3, "sentinel cell 2 = cyan")
-- nibble → two bit-pairs, high first
eq(s1.pattern[3] * 4 + s1.pattern[4], s1.etype, "type cells decode back")
eq(s1.pattern[5] * 4 + s1.pattern[6], s1.seq, "seq cells decode back")
eq(s1.pattern[7] * 4 + s1.pattern[8], s1.payload, "payload cells decode back")
eq(s1.pattern[9] * 4 + s1.pattern[10], s1.check, "check cells decode back")
-- seq advances per emit (dedupe key for the decoder)
local s2 = nss.Signal.Emit(2, 7)
eq((s1.seq + 1) % 16, s2.seq, "sequence increments")
-- game events drive it
M.fireEvent("QUEST_ACCEPTED", 12, 4523)
eq(nss.Signal.last.etype, 2, "QUEST_ACCEPTED → type 2")
eq(nss.Signal.last.payload, 4523 % 16, "quest id folded into payload")
M.fireEvent("QUEST_TURNED_IN", 4523, 450, 90)
eq(nss.Signal.last.etype, 3, "QUEST_TURNED_IN → type 3")
M.fireEvent("PLAYER_LEVEL_UP", 13)
eq(nss.Signal.last.etype, 6, "PLAYER_LEVEL_UP → type 6")
eq(nss.Signal.last.payload, 13, "level in payload")
M.fireEvent("PLAYER_ENTERING_WORLD")
eq(nss.Signal.last.etype, 1, "PLAYER_ENTERING_WORLD → type 1")
ok((pcall(M.fireEvent, "ENCOUNTER_START", 409, "Gelihast", 0, 5)), "encounter anchor emits safely")
eq(nss.Signal.last.etype, 4, "ENCOUNTER_START → type 4")

-- ── result ────────────────────────────────────────────────────────────────────
M.realprint(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
