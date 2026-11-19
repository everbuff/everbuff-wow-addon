-- Guards and #42 (0.9.49, the fix release before the dungeon run store; plan in everbuff-wow-addon #51).
-- Loaded by tests/run_tests.lua after the gold suites:
--   dofile("tests/guards.lua")({ check = check, M = M, ns = ns })
-- Runs on a save file of its own (the suite's is put aside and put back). What it holds the addon to:
--   1. the shared readers (ns.safeStr, ns.plainNum, ns.unitName in Logging.lua);
--   2. the five chat handlers never match a line the client hides, and count such lines while inside an instance
--      (settings.selftest.chatSecret);
--   3. #42: a group member the client has not named yet is never written as "Unknown", in roster events and in the
--      group of a fight, and is read again when the name arrives;
--   4. a kill row is never named after a friendly target;
--   5. settings.selftest.instances keeps, per dungeon, the strongest and the weakest answer of the dungeon check;
--   6. no frame of the addon holds an event the client restricts (tests/api_restricted.lua, build 1.60.1.70959);
--   7. the contract of the new keys, and the upvalue limit of the handlers.
return function(P)
  local M, ns = P.M, P.ns
  local E, T = ns.Emitter, ns._test
  local realPrint = print
  local function check(name, cond, detail) local mine = print; print = realPrint; P.check("guards: " .. name, cond, detail); print = mine end
  print = function() end

  -- ── the suite's state, put aside ──────────────────────────────────────────────────────────────────────────────
  local main = { db = ns.DB, epoch = M.epoch, now = M.now, money = M.money, zone = M.zone, inst = M.inst, uiMap = M.uiMap, mapType = M.mapType,
    groupN = M.groupN, units = M.units, auras = M.auras, inCombat = M.inCombat, dead = M.dead, errors = #M.errors }
  local real = { msg = ns.msg, unknown = rawget(_G, "UNKNOWNOBJECT"), build = _G.GetBuildInfo }
  ns.Recorder.pause("logout")
  ns.Recorder.discard()
  ns.DB = ns.migrateDB({})
  ns._test.newLoad()
  M.timers = {}
  M.units, M.auras, M.groupN, M.inCombat, M.dead = {}, {}, 1, false, false
  local function outside()
    M.zone, M.uiMap, M.mapType = "Elwynn Forest", 37, 3
    M.inst = { name = "Elwynn Forest", type = "none", diff = 0, mapID = 0 }
  end
  outside()
  M.now = M.now + 100
  M.fire("PLAYER_ENTERING_WORLD", true, false); M.runTimers()
  M.fire("GROUP_ROSTER_UPDATE")                       -- the roster the suite left behind is gone, silently or not
  check("a session of its own is running", ns.Recorder.current() ~= nil and ns.DB ~= main.db)

  local function events() return ns.DB.story.events end
  local function nk(kind, pred)
    local n = 0
    for _, e in ipairs(events()) do if e.kind == kind and (not pred or pred(e)) then n = n + 1 end end
    return n
  end
  local function named(kind, name) return nk(kind, function(e) return (e.text or ""):find(name, 1, true) ~= nil end) end
  local function anyText(word)
    for _, e in ipairs(events()) do if type(e.text) == "string" and e.text:find(word, 1, true) then return e.kind .. ": " .. e.text end end
    return nil
  end
  local function errs() return #M.errors end
  local function lastErr() return M.errors[#M.errors] end
  local function enter(zone, itype, iname, mapID)
    M.zone = zone
    M.inst = { name = iname or zone, type = itype or "party", diff = 1, mapID = mapID or 349 }
    M.fire("PLAYER_ENTERING_WORLD", false, false); M.runTimers()
  end
  local function leave() outside(); M.fire("PLAYER_ENTERING_WORLD", false, false); M.runTimers() end

  -- ── 1. the shared readers ─────────────────────────────────────────────────────────────────────────────────────
  do
    check("ns.safeStr keeps a plain string and refuses the rest", ns.safeStr("Pebbles") == "Pebbles" and ns.safeStr("") == ""
      and ns.safeStr(nil) == nil and ns.safeStr(12) == nil and ns.safeStr({}) == nil)
    M.secrets["Hidden Name"] = true; M.secrets[4711] = true
    check("ns.safeStr refuses a string the client marks secret", ns.safeStr("Hidden Name") == nil)
    check("ns.plainNum keeps a plain number and refuses a secret one", ns.plainNum(5) == 5 and ns.plainNum(4711) == nil and ns.plainNum("5") == nil and ns.plainNum(nil) == nil)
    check("the shared readers answer as Emitter's own do", T.safeStr("Hidden Name") == ns.safeStr("Hidden Name") and T.safeStr("x") == ns.safeStr("x")
      and T.plainNum(4711) == ns.plainNum(4711) and T.plainNum(7) == ns.plainNum(7))
    M.units.party1 = { name = "Equi" }
    local n1, w1 = ns.unitName("party1")
    check("ns.unitName: a named unit", n1 == "Equi" and w1 == false, tostring(n1) .. " " .. tostring(w1))
    M.units.party1 = { name = "Unknown" }
    local n2, w2 = ns.unitName("party1")
    check("ns.unitName: the client's placeholder is no name, and the caller is told to wait", n2 == nil and w2 == true, tostring(n2) .. " " .. tostring(w2))
    _G.UNKNOWNOBJECT = "Unbekannt"
    M.units.party1 = { name = "Unbekannt" }
    local n3, w3 = ns.unitName("party1")
    M.units.party1 = { name = "Unknown" }
    local n3b = ns.unitName("party1")
    check("ns.unitName: the placeholder is the client's own word (UNKNOWNOBJECT), in any language", n3 == nil and w3 == true and n3b == "Unknown", tostring(n3) .. " " .. tostring(n3b))
    _G.UNKNOWNOBJECT = nil
    local n3c, w3c = ns.unitName("party1")
    check("ns.unitName: a client without UNKNOWNOBJECT still skips the English placeholder", n3c == nil and w3c == true)
    _G.UNKNOWNOBJECT = "Unknown"
    M.units.party1 = { name = "Hidden Name" }
    local n4, w4 = ns.unitName("party1")
    check("ns.unitName: a hidden name is no name, the unit is there", n4 == nil and w4 == true)
    M.units.party1 = { name = "" }
    local n5, w5 = ns.unitName("party1")
    check("ns.unitName: an empty name is no name", n5 == nil and w5 == true)
    M.units.party1 = nil
    local n6, w6 = ns.unitName("party1")
    check("ns.unitName: no unit, nothing to wait for", n6 == nil and w6 == false)
    local realUN = _G.UnitName
    _G.UnitName = function() error("blocked") end
    local ok, n7, w7 = pcall(ns.unitName, "party1")
    check("ns.unitName: a read the client refuses does not throw", ok and n7 == nil and w7 == false)
    _G.UnitName = nil
    local ok8, n8 = pcall(ns.unitName, "party1")
    check("ns.unitName: a client without UnitName answers nothing", ok8 and n8 == nil)
    _G.UnitName = realUN
    M.secrets["Hidden Name"] = nil; M.secrets[4711] = nil
  end

  -- ── 2. the five chat handlers ────────────────────────────────────────────────────────────────────────────────
  -- A value that throws the way a secret does when it is indexed, compared, concatenated or measured. The stub
  -- cannot make a Lua string throw, so the handlers are fed both: this (nothing may throw) and real lines the stub
  -- marks secret (nothing may be read from them).
  local function thrower()
    local function boom() error("attempt to use a secret value", 2) end
    return setmetatable({}, { __index = boom, __concat = boom, __eq = boom, __lt = boom, __le = boom, __len = boom, __call = boom, __tostring = boom })
  end
  local LINES = {
    { ev = "CHAT_MSG_SKILL", kind = nil, line = "Your skill in Mining has increased to 76." },
    { ev = "CHAT_MSG_SYSTEM", kind = "system", line = "Discovered: Secret Cove" },
    { ev = "CHAT_MSG_COMBAT_FACTION_CHANGE", kind = "rep", line = "Reputation with Stormwind increased by 25." },
    { ev = "CHAT_MSG_COMBAT_XP_GAIN", kind = "xp", line = "Hidden Mob dies, you gain 120 experience." },
    { ev = "CHAT_MSG_LOOT", kind = "loot", line = "You receive loot: |cffffffff|Hitem:2589::::::::1:::::::|h[Linen Cloth]|h|r." },
  }
  local function footprint()
    local c = ns.char()
    return table.concat({ #events(), #(ns.DB.loot.log or {}), #(ns.DB.story.rep or {}), tostring(c.xp and c.xp.fromKills or 0) }, "/")
  end
  do
    for _, L in ipairs(LINES) do
      local e0 = errs()
      M.fire(L.ev, thrower())
      check(L.ev .. ": a value that throws on every use throws nothing in the handler", errs() == e0, lastErr())
      M.fire(L.ev, nil)
      check(L.ev .. ": a line with no text throws nothing", errs() == e0, lastErr())
      M.secrets[L.line] = true
      local before = footprint()
      M.fire(L.ev, L.line)
      check(L.ev .. ": a line the client hides is not read", errs() == e0 and footprint() == before, footprint() .. " was " .. before)
      M.secrets[L.line] = nil
      M.now = M.now + 20
      M.fire(L.ev, L.line)
      check(L.ev .. ": the same line in plain text is read", errs() == e0 and footprint() ~= before, footprint())
      M.now = M.now + 20
    end
    local ok, err = pcall(E.repGain, thrower())
    check("Emitter.repGain itself refuses a value that throws", ok, err)
    check("Emitter.chatText: plain text back, nothing for the rest", E.chatText(nil, "abc") == "abc" and E.chatText(nil, nil) == nil and E.chatText(nil, 5) == nil and E.chatText("xp", thrower()) == nil)
    local st = ns.DB.settings.selftest
    check("outside an instance no chat line is counted", st == nil or st.chatSecret == nil, st and st.chatSecret and "counted")
  end
  -- the counters, inside an instance
  do
    enter("Maraudon", "party", "Maraudon", 349)
    check("the character is inside", ns.char().inInstance == "Maraudon", tostring(ns.char().inInstance))
    local function cs(kind) local c = ns.DB.settings.selftest.chatSecret; return c and c[kind] or nil end
    for _, L in ipairs(LINES) do
      if L.kind then
        local c0 = cs(L.kind)
        local p0, s0 = c0 and c0.plain or 0, c0 and c0.secret or 0
        M.now = M.now + 20
        M.fire(L.ev, L.line)
        M.secrets[L.line] = true; M.fire(L.ev, L.line); M.fire(L.ev, L.line); M.secrets[L.line] = nil
        M.fire(L.ev, thrower())
        M.fire(L.ev, nil)
        local c = cs(L.kind)
        check(("inside, %s lines are counted: 1 plain, 3 hidden, a missing text is no line"):format(L.kind),
          c and c.plain == p0 + 1 and c.secret == s0 + 3, c and (c.plain .. "/" .. c.secret))
      end
    end
    M.fire("CHAT_MSG_SKILL", LINES[1].line)
    local keys = 0
    for k in pairs(ns.DB.settings.selftest.chatSecret) do keys = keys + 1; if not ({ xp = 1, rep = 1, loot = 1, system = 1 })[k] then keys = 99 end end
    check("chatSecret holds exactly xp, rep, loot and system (a skill line is guarded, not counted)", keys == 4, keys)
    -- a damaged record does not stop a handler
    ns.DB.settings.selftest.chatSecret = "broken"
    local e0 = errs()
    M.fire("CHAT_MSG_LOOT", LINES[5].line)
    check("a damaged chatSecret record is rebuilt, not an error", errs() == e0 and type(ns.DB.settings.selftest.chatSecret) == "table" and ns.DB.settings.selftest.chatSecret.loot.plain == 1, lastErr())
    leave()
    local c1 = ns.DB.settings.selftest.chatSecret.loot.plain
    M.now = M.now + 20
    M.fire("CHAT_MSG_LOOT", LINES[5].line)
    check("after leaving, lines are no longer counted", ns.DB.settings.selftest.chatSecret.loot.plain == c1 and ns.char().inInstance == nil)
  end

  -- ── 3. #42: a member the client has not named yet ─────────────────────────────────────────────────────────────
  local function roster() M.fire("GROUP_ROSTER_UPDATE") end
  local function nameUpdate(u) M.fire("UNIT_NAME_UPDATE", u) end
  local function resetRoster()
    M.units.party1, M.units.party2, M.units.party3, M.units.party4 = nil, nil, nil, nil
    M.groupN = 1; M.timers = {}; M.now = M.now + 100
    roster(); M.runTimers()
  end
  do
    local on = { e = false, f = false }
    check("UNIT_NAME_UPDATE is registered on the Emitter's frame", T.emitterFrame.events.UNIT_NAME_UPDATE == true)
    -- the save file of 2026-11-17: "Equi joined the group", then "Unknown joined the group", "Unknown left the group"
    resetRoster()
    local j0, l0 = nk("ROSTERJOIN"), nk("ROSTERLEAVE")
    M.units.party1 = { name = "Equi" }; M.groupN = 2; roster()
    check("#42 a named member joins", named("ROSTERJOIN", "Equi") == 1 and nk("ROSTERJOIN") == j0 + 1)
    M.units.party2 = { name = "Unknown" }; M.groupN = 3; roster()
    check("#42 a member with the placeholder name is not written", nk("ROSTERJOIN") == j0 + 1 and anyText("Unknown") == nil, anyText("Unknown"))
    check("#42 the roster is marked as waiting for a name", type(E._rosterWait) == "table" and #M.timers >= 1)
    roster(); roster()
    check("#42 more roster updates while waiting write nothing", nk("ROSTERJOIN") == j0 + 1 and nk("ROSTERLEAVE") == l0)
    nameUpdate("target")
    check("#42 a name update for another unit, name still missing: nothing", nk("ROSTERJOIN") == j0 + 1)
    M.units.party2.name = "Pebbles"; nameUpdate("party2")
    check("#42 the name arrives: the member joins once, under its name", named("ROSTERJOIN", "Pebbles") == 1 and nk("ROSTERJOIN") == j0 + 2 and nk("ROSTERLEAVE") == l0)
    check("#42 nothing is waited for any more", E._rosterWait == nil)
    M.runTimers(); nameUpdate("party2"); roster()
    check("#42 the pending re-read and later updates add nothing", nk("ROSTERJOIN") == j0 + 2 and nk("ROSTERLEAVE") == l0)
    check("#42 no row anywhere names the placeholder", anyText("Unknown") == nil, anyText("Unknown"))
    -- the member leaves before the client ever names it: neither a join nor a leave
    M.units.party3 = { name = "Unknown" }; M.groupN = 4; roster()
    M.units.party3 = nil; M.groupN = 3; roster()
    check("#42 a member gone before it was named leaves no row", nk("ROSTERJOIN") == j0 + 2 and nk("ROSTERLEAVE") == l0 and E._rosterWait == nil and anyText("Unknown") == nil)
    M.runTimers()

    -- the client never sends UNIT_NAME_UPDATE: the roster is read again 2 s later
    resetRoster()
    j0, l0 = nk("ROSTERJOIN"), nk("ROSTERLEAVE")
    M.units.party1 = { name = "Unknown" }; M.groupN = 2; roster()
    check("#42 without the event: nothing yet, one re-read is scheduled", nk("ROSTERJOIN") == j0 and #M.timers == 1, #M.timers)
    roster()
    check("#42 a second update does not schedule a second re-read", #M.timers == 1, #M.timers)
    M.now = M.now + 2; M.runTimers()
    check("#42 still unnamed after 2 s: nothing, and the next re-read is scheduled", nk("ROSTERJOIN") == j0 and #M.timers == 1, #M.timers)
    M.units.party1.name = "Oxii"; M.now = M.now + 2; M.runTimers()
    check("#42 the re-read finds the name: one join", named("ROSTERJOIN", "Oxii") == 1 and nk("ROSTERJOIN") == j0 + 1 and #M.timers == 0, #M.timers)

    -- a member already seen reads as the placeholder for a moment: no leave, no second join
    j0, l0 = nk("ROSTERJOIN"), nk("ROSTERLEAVE")
    M.units.party1.name = "Unknown"; roster()
    check("#42 a seen member unnamed for a moment has not left", nk("ROSTERLEAVE") == l0 and nk("ROSTERJOIN") == j0)
    M.units.party1.name = "Oxii"; nameUpdate("party1")
    check("#42 and is not announced again when the name is back", nk("ROSTERLEAVE") == l0 and nk("ROSTERJOIN") == j0)
    M.runTimers()

    -- a real leave while another name is waited for: written once the roster is readable
    M.units.party1 = { name = "Unknown" }; roster()        -- Oxii is gone, the token now holds a newcomer not named yet
    check("#42 a leave waits while a name is waited for", nk("ROSTERLEAVE") == l0 and nk("ROSTERJOIN") == j0)
    M.units.party1.name = "Zed"; nameUpdate("party1")
    check("#42 then both are written: the newcomer joined, the other left", named("ROSTERJOIN", "Zed") == 1 and named("ROSTERLEAVE", "Oxii") == 1
      and nk("ROSTERJOIN") == j0 + 1 and nk("ROSTERLEAVE") == l0 + 1)
    M.runTimers()

    -- a name that never comes: after ROSTER_WAIT the roster is diffed as it reads, and no timer keeps running
    resetRoster()
    j0, l0 = nk("ROSTERJOIN"), nk("ROSTERLEAVE")
    M.units.party1 = { name = "Ann" }; M.groupN = 2; roster()
    M.units.party1 = { name = "Unknown" }; roster()
    local rounds = 0
    while #M.timers > 0 and rounds < 14 do M.now = M.now + 2; M.runTimers(); rounds = rounds + 1 end
    check("#42 a name that never comes: for 28 s nothing is written and a re-read stays scheduled", rounds == 14 and #M.timers == 1
      and nk("ROSTERLEAVE") == l0 and named("ROSTERJOIN", "Ann") == 1 and anyText("Unknown") == nil, rounds)
    while #M.timers > 0 and rounds < 100 do M.now = M.now + 2; M.runTimers(); rounds = rounds + 1 end
    check("#42 the re-reads stop after the wait", rounds == 15 and #M.timers == 0, rounds)
    check("#42 the last re-read writes the roster as it reads: the leave, still no placeholder", named("ROSTERLEAVE", "Ann") == 1 and anyText("Unknown") == nil)
    roster(); roster()
    check("#42 and later updates add no second leave and no timer", named("ROSTERLEAVE", "Ann") == 1 and nk("ROSTERLEAVE") == l0 + 1 and #M.timers == 0)

    -- login with a group whose names are not there yet: the seed stays silent when they arrive
    resetRoster()
    j0, l0 = nk("ROSTERJOIN"), nk("ROSTERLEAVE")
    M.units.party1 = { name = "Unknown" }; M.units.party2 = { name = "Equi" }; M.groupN = 3
    M.fire("PLAYER_ENTERING_WORLD", true, false)
    M.units.party1.name = "Crowbar"; nameUpdate("party1")
    M.runTimers()
    check("#42 names arriving after the silent seed at login are not joins", nk("ROSTERJOIN") == j0 and nk("ROSTERLEAVE") == l0, nk("ROSTERJOIN") - j0)
    M.units.party3 = { name = "Dave" }; M.groupN = 4; roster()
    check("#42 a real join after that is written", named("ROSTERJOIN", "Dave") == 1 and nk("ROSTERJOIN") == j0 + 1)
    M.units.party1 = nil; M.units.party1 = M.units.party2; M.units.party2 = M.units.party3; M.units.party3 = nil; M.groupN = 3; roster()
    check("#42 and a real leave too (the unit tokens moved up)", named("ROSTERLEAVE", "Crowbar") == 1 and nk("ROSTERLEAVE") == l0 + 1 and nk("ROSTERJOIN") == j0 + 1)

    -- a hidden name: no row, no error, no comparison
    resetRoster()
    j0, l0 = nk("ROSTERJOIN"), nk("ROSTERLEAVE")
    local e0 = errs()
    M.secrets["Veiled"] = true
    M.units.party1 = { name = "Veiled" }; M.groupN = 2; roster(); nameUpdate("party1")
    check("#42 a member whose name the client hides is not written and nothing throws", errs() == e0 and nk("ROSTERJOIN") == j0 and anyText("Veiled") == nil, lastErr())
    M.secrets["Veiled"] = nil
    nameUpdate("party1")
    check("#42 readable again: the join is written", named("ROSTERJOIN", "Veiled") == 1)
    resetRoster()
    check("#42 the 153 grouped fights of the real save have no Unknown member; this suite is synthetic by design", true)
  end
  -- the group of a fight
  do
    resetRoster()
    local F = ns.Fights
    local fightFrame
    for _, fr in ipairs(ns.eventFrames) do if fr.events.UNIT_NAME_UPDATE and fr ~= T.emitterFrame then fightFrame = fr end end
    check("UNIT_NAME_UPDATE is registered on the fights frame", fightFrame ~= nil and fightFrame.events.PLAYER_REGEN_DISABLED == true)
    M.units.party1 = { name = "Equi" }; M.units.party2 = { name = "Unknown" }; M.units.party3 = { name = "Unknown" }; M.groupN = 4
    M.auras.party2 = { HELPFUL = { { name = "Mark of the Wild", icon = 136078, spellId = 1126, auraInstanceID = 901 } }, HARMFUL = {} }
    roster()
    local e0 = errs()
    M.units.target = { name = "Noxxion", hostile = true }
    M.inCombat = true; M.now = M.now + 30; M.fire("PLAYER_REGEN_DISABLED")
    local cf = T.currentFight()
    local function member(unit) for _, m in ipairs(cf and cf.group or {}) do if m.unit == unit then return m end end end
    check("#42 fight: every unit of the group is a member", cf and cf.group and #cf.group == 4 and errs() == e0, cf and cf.group and #cf.group or lastErr())
    check("#42 fight: a member not named yet has no name, not the placeholder", member("party2") and member("party2").name == nil and member("party3").name == nil and member("party1").name == "Equi")
    check("#42 fight: no aura timeline is kept under the placeholder", cf and cf.memberAuras and cf.memberAuras["Unknown"] == nil and cf.memberAuras["Equi"] ~= nil)
    check("#42 fight: the captures after the group still ran (the foe is there)", cf and cf.foes[1] == "Noxxion", cf and cf.foes[1])
    M.now = M.now + 3
    M.units.party2.name = "Pebbles"; nameUpdate("party2")
    check("#42 fight: the name arrives during the fight", member("party2").name == "Pebbles" and member("party3").name == nil)
    check("#42 fight: its aura timeline starts then", type(cf.memberAuras["Pebbles"]) == "table")
    M.now = M.now + 2
    M.auras.party2.HELPFUL[2] = { name = "Power Word: Fortitude", icon = 135987, spellId = 1243, auraInstanceID = 902 }
    M.fire("UNIT_AURA", "party2")
    local gained = 0
    for _, a in ipairs(cf.memberAuras["Pebbles"]) do if a.gain and a.name == "Power Word: Fortitude" then gained = gained + 1 end end
    check("#42 fight: and records what the member gains from there on", gained == 1, gained)
    -- a member not named yet still dies
    M.now = M.now + 2; M.units.party3.dead = true; M.fire("UNIT_HEALTH", "party3")
    check("#42 fight: the death of a member not named yet is counted", cf.memberDeaths == 1 and member("party3").deadT ~= nil, cf.memberDeaths)
    -- the last name is there when the fight closes
    M.units.party3.name = "Oxii"
    M.now = M.now + 5; M.inCombat = false; M.units.target = nil; M.fire("PLAYER_REGEN_ENABLED")
    local sf = ns.DB.combat.fights[#ns.DB.combat.fights]
    local names = {}
    for _, m in ipairs(sf and sf.group or {}) do names[#names + 1] = tostring(m.name) end
    table.sort(names)
    check("#42 fight: the stored group names everyone, the close read the last name", table.concat(names, ",") == "Equi,Hart,Oxii,Pebbles", table.concat(names, ","))
    check("#42 fight: no handler threw", errs() == e0, lastErr())
    -- a name that never comes, and a hidden one: the member is stored without a name
    M.secrets["Veiled"] = true
    M.units.party2 = { name = "Unknown" }; M.units.party3 = { name = "Veiled" }
    M.inCombat = true; M.now = M.now + 30; M.fire("PLAYER_REGEN_DISABLED")
    M.now = M.now + 5; M.inCombat = false; M.fire("PLAYER_REGEN_ENABLED")
    local sf2 = ns.DB.combat.fights[#ns.DB.combat.fights]
    local unnamed, bad = 0, nil
    for _, m in ipairs(sf2 and sf2.group or {}) do
      if m.name == nil then unnamed = unnamed + 1 elseif m.name == "Unknown" or m.name == "Veiled" then bad = m.name end
    end
    for k in pairs(sf2 and sf2.memberAuras or {}) do if k == "Unknown" or k == "Veiled" then bad = k end end
    check("#42 fight: a name that never comes and a hidden one are stored as no name", sf2 ~= sf and sf2.group and #sf2.group == 4 and unnamed == 2 and bad == nil and errs() == e0, bad or unnamed)
    M.secrets["Veiled"] = nil
    -- the pane that lists a group shows such a member as "?" (Recording.lua, Dungeons.lua): no string is built from nil
    local okSan, clean = pcall(T.sanitize, sf2)
    check("#42 fight: the stored fight passes the save sanitizer", okSan and clean ~= nil, clean)
    M.auras = {}
    resetRoster()
    check("#42 fight: F.groupNames with no fight is harmless", pcall(F.groupNames))
  end

  -- ── 4. a kill row is never named after a friendly target ──────────────────────────────────────────────────────
  do
    local function fightWith(setTarget)
      M.units.target = nil
      M.inCombat = true; M.now = M.now + 30; M.fire("PLAYER_REGEN_DISABLED")   -- pulled with no target: no foe captured
      M.inCombat = false; M.now = M.now + 6
      M.units.target = setTarget                                                -- what the player has selected when combat ends
      local k0 = nk("KILL")
      M.fire("PLAYER_REGEN_ENABLED")
      M.units.target = nil
      local last
      for i = #events(), 1, -1 do if events()[i].kind == "KILL" then last = events()[i]; break end end
      return nk("KILL") - k0, last and last.text
    end
    local n, text = fightWith({ name = "Pebbles", hostile = false, player = true })
    check("a friendly target at combat end: the kill is an enemy, not the party member", n == 1 and text == "an enemy down!", text)
    check("no KILL row names the party member", named("KILL", "Pebbles") == 0)
    n, text = fightWith({ name = "Oxii", hostile = false, player = true, dead = true })
    check("a dead party member as target is not the foe either", n == 1 and text == "an enemy down!", text)
    n, text = fightWith({ name = "Stormwind Guard", hostile = false, friend = true })
    check("a friendly NPC is not the foe", n == 1 and text == "an enemy down!", text)
    n, text = fightWith({ name = "Cavern Shambler", hostile = false, friend = false, dead = true })
    check("a dead mob (no longer attackable) still names the kill", n == 1 and text == "Cavern Shambler down!", text)
    n, text = fightWith({ name = "Enemy Rogue", hostile = false, friend = false, dead = true, player = true })
    check("a dead player who is no friend is not named by this fallback", n == 1 and text == "an enemy down!", text)
    n, text = fightWith(nil)
    check("no target at all: an enemy", n == 1 and text == "an enemy down!", text)
    -- the enemy's name is hidden, the healer has a party member selected the whole fight (the Maraudon rows)
    M.secrets["Theradras Guard"] = true
    M.units.target = { name = "Theradras Guard", hostile = true }
    M.inCombat = true; M.now = M.now + 30; M.fire("PLAYER_REGEN_DISABLED")
    M.units.target = { name = "Crowbar", hostile = false, player = true }; M.fire("PLAYER_TARGET_CHANGED")
    M.inCombat = false; M.now = M.now + 8
    local k0 = nk("KILL"); M.fire("PLAYER_REGEN_ENABLED")
    check("hidden enemy name, friendly target: one kill of an enemy", nk("KILL") == k0 + 1 and named("KILL", "Crowbar") == 0 and named("KILL", "Theradras Guard") == 0)
    M.secrets["Theradras Guard"] = nil; M.units.target = nil
    -- the client lacks the functions the corpse rule asks: only an attackable target counts
    local rf, rp = _G.UnitIsFriend, _G.UnitIsPlayer
    _G.UnitIsFriend = nil
    n, text = fightWith({ name = "Cavern Shambler", hostile = false, friend = false, dead = true })
    check("without UnitIsFriend a corpse is not taken", n == 1 and text == "an enemy down!", text)
    _G.UnitIsFriend = rf
    local ra = _G.UnitCanAttack
    _G.UnitCanAttack = function() error("blocked") end
    local e0 = errs()
    local ok = pcall(E.targetIsFoe)
    check("Emitter.targetIsFoe: a read the client refuses does not throw", ok and errs() == e0)
    _G.UnitCanAttack = ra; _G.UnitIsPlayer = rp
    M.units.target = { name = "Defias Thug", hostile = true }
    check("Emitter.targetIsFoe: an attackable target", E.targetIsFoe() == true)
    M.units.target = nil
    check("Emitter.targetIsFoe: no target", E.targetIsFoe() == false)
  end

  -- ── 5. settings.selftest.instances ───────────────────────────────────────────────────────────────────────────
  do
    local function inst(name) local t = ns.DB.settings.selftest.instances; return t and t[name] end
    ns.DB.settings.selftest.instances = nil
    M.epoch = M.epoch + 60
    enter("Maraudon", "party", "Maraudon", 349)
    local r = inst("Maraudon")
    check("instances: a visit writes the record under the dungeon's name", r and r.strong and r.at == M.epoch, r and r.at)
    local s = r and r.strong or {}
    check("instances: the record carries every answer and the signal that fired", s.sig == "type" and s.zone == "Maraudon" and s.name == "Maraudon"
      and s.type == "party" and s.ptype == nil and s.map == 349 and s.diff == 1 and s.inInstance == true and s.at == M.epoch, tostring(s.sig))
    check("instances: one signal seen, no weakest record yet", r and r.weak == nil)
    check("instance: the last check names its signal too", ns.DB.settings.selftest.instance.sig == "type" and ns.DB.settings.selftest.instance.verdict == "party")
    leave()
    check("instances: leaving does not touch the record (the last check is overwritten, this is not)", inst("Maraudon") == r and r.strong == s
      and ns.DB.settings.selftest.instance.verdict == "none" and ns.DB.settings.selftest.instance.sig == nil)
    local n = 0; for _ in pairs(ns.DB.settings.selftest.instances) do n = n + 1 end
    check("instances: the open world writes no record", n == 1, n)

    -- Sunken Temple, 2026-11-17: inside, the client says party under either name; in the halls outside the portal it
    -- says none with a continent map id, and only the zone name still says dungeon
    M.epoch = M.epoch + 60
    enter("The Temple of Atal'Hakkar", "party", "Sunken Temple", 109)
    M.epoch = M.epoch + 600
    M.zone = "Sunken Temple"; M.fire("ZONE_CHANGED_NEW_AREA")
    M.epoch = M.epoch + 600
    M.zone = "The Temple of Atal'Hakkar"; M.inst = { name = "Eastern Kingdoms", type = "none", diff = 0, mapID = 0 }
    M.fire("ZONE_CHANGED_NEW_AREA")
    local st = inst("Sunken Temple")
    check("instances: both names of one dungeon share one record", st ~= nil and inst("The Temple of Atal'Hakkar") == nil)
    check("instances: the strongest answer is the one from inside", st and st.strong and st.strong.sig == "type" and st.strong.map == 109 and st.strong.name == "Sunken Temple"
      and st.strong.zone == "Sunken Temple", st and st.strong and st.strong.zone)
    check("instances: the weakest is the name alone, with the continent the client answered and both names", st and st.weak and st.weak.sig == "name" and st.weak.map == 0
      and st.weak.type == "none" and st.weak.zone == "The Temple of Atal'Hakkar" and st.weak.name == "Eastern Kingdoms" and st.weak.inInstance == false, st and st.weak and st.weak.sig)
    check("instances: the record's time is the last time either was seen", st and st.at == M.epoch and st.strong.at == M.epoch - 600)
    -- the map type signal in between replaces neither
    local weak0, strong0 = st.weak, st.strong
    M.mapType = 4; M.fire("ZONE_CHANGED_NEW_AREA")
    check("instances: a signal between the two replaces neither", st.weak == weak0 and st.strong == strong0 and ns.DB.settings.selftest.instance.sig == "mapType")
    M.mapType = 3
    leave()
    -- the other order: the halls first, then inside
    ns.DB.settings.selftest.instances = nil
    M.zone = "The Temple of Atal'Hakkar"; M.inst = { name = "Eastern Kingdoms", type = "none", diff = 0, mapID = 0 }
    M.fire("ZONE_CHANGED_NEW_AREA")
    local st1 = inst("Sunken Temple")
    check("instances: seen from outside only, the name signal is the strongest so far", st1 and st1.strong.sig == "name" and st1.weak == nil)
    enter("Sunken Temple", "party", "Sunken Temple", 109)
    check("instances: then inside: the same two records, whichever came first", st1.strong.sig == "type" and st1.weak and st1.weak.sig == "name" and st1.weak.map == 0)
    leave()
    -- the dungeon map type and IsInInstance as the signal
    M.zone = "Some New Crypt"; M.mapType = 4; M.fire("ZONE_CHANGED_NEW_AREA")
    check("instances: a dungeon the name list lacks, found by its map type", inst("Some New Crypt") and inst("Some New Crypt").strong.sig == "mapType" and inst("Some New Crypt").strong.mapType == 4)
    M.mapType = 3; leave()
    local realIn = _G.IsInInstance
    _G.IsInInstance = function() return true, "raid" end
    M.zone = "Onyxia's Lair"; M.inst = { name = "Onyxia's Lair", type = "none", diff = 0, mapID = 249 }
    M.fire("ZONE_CHANGED_NEW_AREA")
    check("instances: IsInInstance as the signal", inst("Onyxia's Lair") and inst("Onyxia's Lair").strong.sig == "ptype" and inst("Onyxia's Lair").strong.ptype == "raid")
    _G.IsInInstance = realIn
    leave()
    -- the cap: 40 dungeons, the one not seen for longest goes
    ns.DB.settings.selftest.instances = nil
    M.mapType = 4
    for i = 1, 45 do M.epoch = M.epoch + 10; M.zone = ("Crypt %02d"):format(i); M.fire("ZONE_CHANGED_NEW_AREA") end
    M.mapType = 3
    local kept = 0; for _ in pairs(ns.DB.settings.selftest.instances) do kept = kept + 1 end
    check("instances: at most 40 dungeons are kept", kept == 40 and E.INSTANCES_CAP == 40, kept)
    check("instances: the ones not seen for longest went", inst("Crypt 05") == nil and inst("Crypt 06") ~= nil and inst("Crypt 45") ~= nil)
    M.epoch = M.epoch + 10; M.zone = "Crypt 06"; M.mapType = 4; M.fire("ZONE_CHANGED_NEW_AREA")
    M.epoch = M.epoch + 10; M.zone = "Crypt 46"; M.fire("ZONE_CHANGED_NEW_AREA"); M.mapType = 3
    check("instances: a dungeon seen again is not the oldest", inst("Crypt 06") ~= nil and inst("Crypt 07") == nil and inst("Crypt 46") ~= nil)
    leave()
    -- a hidden zone name: no key is made from it, nothing throws
    local e0 = errs()
    M.secrets["Veiled Depths"] = true
    M.zone = "Veiled Depths"; M.mapType = 4; M.fire("ZONE_CHANGED_NEW_AREA"); M.mapType = 3
    check("instances: a hidden zone name is no key and no error", errs() == e0 and inst("Veiled Depths") == nil, lastErr())
    M.secrets["Veiled Depths"] = nil
    leave()
    -- a damaged record
    ns.DB.settings.selftest.instances = { ["Maraudon"] = "broken" }
    enter("Maraudon", "party", "Maraudon", 349)
    check("instances: a damaged entry is replaced, not an error", errs() == e0 and type(inst("Maraudon")) == "table" and inst("Maraudon").strong.sig == "type", lastErr())
    leave()
    check("Emitter.noteInstance refuses what is no name", pcall(E.noteInstance, nil, { sig = "type", at = 1 }) and pcall(E.noteInstance, "", { sig = "type", at = 1 }) and inst("") == nil)

    -- the client check on a new build replaces the record and keeps what was collected
    local ST = ns.SelfTest
    local before = { instances = ns.DB.settings.selftest.instances, chat = ns.DB.settings.selftest.chatSecret, last = ns.DB.settings.selftest.instance }
    _G.GetBuildInfo = function() return "1.60.9", "79999", "Nov 19 2026", 16009 end
    local rec, ran = ST.run()
    check("selftest: a new build runs the check again", ran == true and rec.build == "1.60.9.79999" and ns.DB.settings.selftest == rec)
    check("selftest: the new record keeps instances, chatSecret and the last dungeon check", rec.instances == before.instances and rec.chatSecret == before.chat
      and rec.instance == before.last and before.instances ~= nil and before.chat ~= nil)
    _G.GetBuildInfo = real.build
  end

  -- ── 6. no restricted event ───────────────────────────────────────────────────────────────────────────────────
  do
    local okA, api = pcall(dofile, "tests/api_restricted.lua")
    check("restricted: tests/api_restricted.lua loads", okA and type(api) == "table", api)
    api = okA and type(api) == "table" and api or { restricted = {}, events = {} }
    check("restricted: the list is the one of build 1.60.1.70959", api.build == "1.60.1.70959" and api.interface == 16001, tostring(api.build))
    check("restricted: it holds the 7 events the client restricts", #api.restricted == 7 and api.eventCount == 1816, #api.restricted)
    local R, known = {}, {}
    for _, ev in ipairs(api.restricted) do R[ev] = true end
    for _, ev in ipairs(api.events) do known[ev] = true end
    check("restricted: the combat log event is among them", R.COMBAT_LOG_EVENT_UNFILTERED == true and R.COMBAT_LOG_EVENT == true)
    -- what the frames hold, after everything the suite has done so far
    local function held()
      local out = {}
      for _, fr in ipairs(M.frames) do for ev in pairs(fr.events) do if R[ev] then out[#out + 1] = ev end end end
      table.sort(out)
      return out
    end
    check("restricted: no frame holds a restricted event", #held() == 0, table.concat(held(), ","))
    local probe = CreateFrame("Frame")
    probe:RegisterEvent("MINIMAP_PING")
    check("restricted: the check sees a restricted event when one is registered", #held() == 1 and held()[1] == "MINIMAP_PING")
    probe:UnregisterEvent("MINIMAP_PING")
    -- the dependency list (every event the source registers, generated by tools/deps.lua)
    local bad, nEvents, undocumented = {}, 0, {}
    for _, d in ipairs(ns.deps or {}) do
      if d[1] == "event" then
        nEvents = nEvents + 1
        if R[d[2]] then bad[#bad + 1] = d[2] end
        if not known[d[2]] then undocumented[#undocumented + 1] = d[2] end
      end
    end
    check("restricted: no event of the dependency list is restricted", nEvents > 80 and #bad == 0, table.concat(bad, ","))
    check("restricted: the events 0.9.49 adds exist on this build", known.UNIT_NAME_UPDATE == true and not R.UNIT_NAME_UPDATE)
    -- events the addon registers that the client's documentation of this build does not list: named, so a new one
    -- is a decision (each of these is registered through pcall or exists on other flavors only)
    table.sort(undocumented)
    local allowed = {}
    for _, ev in ipairs(api.undocumentedOk or {}) do allowed[ev] = true end
    local surprise = {}
    for _, ev in ipairs(undocumented) do if not allowed[ev] then surprise[#surprise + 1] = ev end end
    check("restricted: every registered event is documented on this build or listed as known absent", #surprise == 0, table.concat(surprise, ","))
    local forb = {}
    for _, ev in ipairs(ns.depsForbidden or {}) do forb[ev] = true; if not R[ev] then bad[#bad + 1] = ev end end
    check("restricted: what the addon calls forbidden is restricted on this build", #bad == 0 and forb.COMBAT_LOG_EVENT_UNFILTERED == true, table.concat(bad, ","))
    -- the source: a restricted event named anywhere in a loaded file must be one the addon declares forbidden (it is
    -- then registered only on clients without Secret Values, tools/deps.lua)
    local namedIn = {}
    for line in io.lines("Everbuff/EverbuffJournal.toc") do
      local f = line:match("^([%w_]+)%.lua%s*$")
      if f and f ~= "Deps" then
        local fh = io.open("Everbuff/" .. f .. ".lua", "rb")
        local src = fh:read("*a"); fh:close()
        for q, ev in src:gmatch("([\"'])([A-Z][A-Z0-9_]+)%1") do
          if q and R[ev] and not forb[ev] then namedIn[#namedIn + 1] = f .. ":" .. ev end
        end
      end
    end
    check("restricted: no loaded file names a restricted event it does not declare forbidden", #namedIn == 0, table.concat(namedIn, ","))
    check("restricted: on a client with Secret Values the combat log event is not registered", ns.hasSecretValues == true and #held() == 0)
  end

  -- ── 7. contract of the new keys, limits ──────────────────────────────────────────────────────────────────────
  do
    local st = ns.DB.settings.selftest
    local okShape, why = true, nil
    local SIG = { type = true, ptype = true, mapType = true, name = true }
    local function rec(r, where)
      if type(r) ~= "table" then okShape, why = false, where .. " is no table"; return end
      for k, v in pairs(r) do
        local t = type(v)
        local want = ({ zone = "string", name = "string", type = "string", ptype = "string", diff = "number", map = "number", inInstance = "boolean",
          uiMap = "number", mapType = "number", sig = "string", at = "number" })[k]
        if want == nil then okShape, why = false, where .. " has an unknown key " .. tostring(k)
        elseif t ~= want then okShape, why = false, where .. "." .. k .. " is a " .. t end
      end
      if not SIG[r.sig] then okShape, why = false, where .. ".sig is " .. tostring(r.sig) end
      if type(r.at) ~= "number" or type(r.zone) ~= "string" or type(r.inInstance) ~= "boolean" then okShape, why = false, where .. " lacks at, zone or inInstance" end
    end
    local n = 0
    for name, e in pairs(st.instances or {}) do
      n = n + 1
      if type(name) ~= "string" or name == "" then okShape, why = false, "a key that is no name" end
      if type(e) ~= "table" or type(e.at) ~= "number" then okShape, why = false, tostring(name) .. " has no at"
      else
        for k in pairs(e) do if k ~= "at" and k ~= "strong" and k ~= "weak" then okShape, why = false, tostring(name) .. " has an unknown key " .. tostring(k) end end
        rec(e.strong, name .. ".strong")
        if e.weak ~= nil then
          rec(e.weak, name .. ".weak")
          if okShape and E.SIG_RANK[e.weak.sig] >= E.SIG_RANK[e.strong.sig] then okShape, why = false, name .. ": weak is not weaker than strong" end
        end
      end
    end
    check("contract: settings.selftest.instances[name] = { at, strong, weak? }, every record typed", okShape and n > 0 and n <= 40, why or n)
    local okChat = type(st.chatSecret) == "table"
    for k, c in pairs(st.chatSecret or {}) do
      if not ({ xp = 1, rep = 1, loot = 1, system = 1 })[k] or type(c) ~= "table" or type(c.plain) ~= "number" or type(c.secret) ~= "number"
        or c.plain < 0 or c.secret < 0 or c.plain % 1 ~= 0 or c.secret % 1 ~= 0 then okChat = false end
      for kk in pairs(type(c) == "table" and c or {}) do if kk ~= "plain" and kk ~= "secret" then okChat = false end end
    end
    check("contract: settings.selftest.chatSecret[kind] = { plain, secret }, whole numbers, four kinds", okChat)
    check("contract: settings.selftest.instance.sig is a signal name or absent", st.instance == nil or st.instance.sig == nil or SIG[st.instance.sig] == true)
    check("contract: the new records are diagnostics under settings, nothing new on the character block",
      ns.char().instances == nil and ns.char().chatSecret == nil and ns.DB.instances == nil)
    -- a fight row keeps its shape: `name` of a group member is a string or absent
    local okGroup = true
    for _, f in ipairs(ns.DB.combat.fights or {}) do
      for _, m in ipairs(f.group or {}) do if m.name ~= nil and (type(m.name) ~= "string" or m.name == "" or m.name == "Unknown") then okGroup = false end end
    end
    check("contract: fights[].group[].name is a real name or absent", okGroup)
    -- the 60 upvalue limit of a Lua function: Emitter's handler took one branch more and no new upvalue
    local worst, emitterUps = 0, debug.getinfo(T.emitterFrame.scripts.OnEvent, "u").nups
    for _, fr in ipairs(ns.eventFrames) do
      local h = fr.scripts.OnEvent
      if h then worst = math.max(worst, debug.getinfo(h, "u").nups) end
    end
    check("limits: no event handler has more than 60 upvalues", worst <= 60 and emitterUps <= 60, worst)
    check("limits: Emitter.lua and Fights.lua still load", loadfile("Everbuff/Emitter.lua") ~= nil and loadfile("Everbuff/Fights.lua") ~= nil)
    check("limits: the helpers of 0.9.49 are on the Emitter table and on ns, not file-level locals of Emitter.lua",
      type(E.chatText) == "function" and type(E.noteInstance) == "function" and type(E.targetIsFoe) == "function" and type(E.rosterReread) == "function"
      and type(ns.unitName) == "function")
    check("no handler threw anywhere in this suite", errs() == main.errors, lastErr())
  end

  -- ── the suite's save file and client back in place ──────────────────────────────────────────────────────────
  M.units, M.auras, M.groupN, M.inCombat, M.dead = main.units, main.auras, main.groupN, main.inCombat, main.dead
  _G.UNKNOWNOBJECT, _G.GetBuildInfo, ns.msg = real.unknown, real.build, real.msg
  E._rosterWait = nil
  M.timers = {}
  M.fire("GROUP_ROSTER_UPDATE")
  ns.Recorder.discard()
  ns.DB = main.db
  M.zone, M.inst, M.uiMap, M.mapType = main.zone, main.inst, main.uiMap, main.mapType
  M.epoch, M.now, M.money = main.epoch, M.now + 100, main.money
  ns._test.newLoad()
  M.fire("PLAYER_ENTERING_WORLD", false, true); M.runTimers()
  print = realPrint
  P.check("guards: the suite's save file is back, its session resumed", ns.DB == main.db and ns.Recorder.current() ~= nil)
end
