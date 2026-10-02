-- Headless tests for the Everbuff addon. Run from the repo root:  luajit tests/run_tests.lua
-- Loads the real addon files (TOC order) under tests/wow_stub.lua, fires WoW events into the REAL
-- handlers, and asserts on the resulting state + on pure helpers exported via ns._test.
package.path = "tests/?.lua;" .. package.path
local M = require("wow_stub")
local passed, failed = 0, 0
local function check(name, cond, detail)
  if cond then passed = passed + 1
  else failed = failed + 1; print(("FAIL  %s%s"):format(name, detail ~= nil and ("   -> " .. tostring(detail)) or "")) end
end
local function count(t, pred) local n = 0; for _, v in ipairs(t or {}) do if pred(v) then n = n + 1 end end return n end

-- ── load the addon exactly as WoW would (TOC order, (addonName, ns) varargs) ──
local ns, ADDON = {}, "EverbuffJournal"
for _, f in ipairs({ "Theme", "Logging", "Segments", "Fights", "UI", "Debug", "Recording", "Economy", "Progress", "Market", "Visits", "Journey", "Dungeons", "Deaths", "Sync", "Emitter", "Core", "Deps", "SelfTest" }) do
  local chunk, err = loadfile("Everbuff/" .. f .. ".lua")
  check("parse " .. f, chunk ~= nil, err)
  if chunk then local ok, e = pcall(chunk, ADDON, ns); check("load " .. f, ok, e) end
end
local T = ns._test or {}

-- ── boot ──
M.fire("ADDON_LOADED", ADDON)
check("ADDON_LOADED creates ns.DB", type(ns.DB) == "table")
check("db.gold/xp/played initialised", ns.DB and ns.DB.loot.gold and ns.DB.character.xp and ns.DB.character.played)
M.money = 5000; M.xp = 100
M.fire("PLAYER_ENTERING_WORLD")
M.runTimers()   -- rep seed, /played request, welcome line
-- every frame that registers an event is known to the self-test
do
  local own = {}
  for _, fr in ipairs(ns.eventFrames or {}) do own[fr] = true end
  local stray = 0
  for _, fr in ipairs(M.frames) do if next(fr.events) and not own[fr] then stray = stray + 1 end end
  check("selftest: every event frame of the addon is in ns.eventFrames", stray == 0, stray)
end

-- ── Debug.lua: captured Lua errors carry their stack; a repeat counts up instead of filling the buffer ──
do
  local h = geterrorhandler()
  for _ = 1, 49 do h("Emitter.lua:1170: attempt to call a nil value") end
  h("another error")
  local errs = ns.DB.debug and ns.DB.debug.errors or {}
  check("debug: 49 identical errors make one row with a count", #errs == 2 and errs[1].n == 49, #errs)
  check("debug: the row carries the call stack", errs[1] and type(errs[1].stack) == "string" and errs[1].stack:find("Emitter.lua") ~= nil)
  ns.Debug.command("clear")
end
-- ── localization pattern builder ──
check("skillup pattern", select(1, ("Your skill in Mining has increased to 75."):match(T.SKILLUP_PAT)) == "Mining")
check("skillup number", select(2, ("Your skill in Mining has increased to 75."):match(T.SKILLUP_PAT)) == "75")
check("discover-xp pattern", ("Discovered Elwynn Forest: 45 experience gained."):match(T.DISCOVER_XP_PAT) == "Elwynn Forest")
check("discover plain pattern (trailing capture greedy)", ("Discovered: Stormwind"):match(T.DISCOVER_PAT) == "Stormwind")
check("create matches a create line", ("You create: |cffffffff|Hitem:2589|h[Linen Cloth]|h|rx2."):match(T.CREATE_PAT) ~= nil)
check("create does NOT match a loot line", ("You receive loot: |Hitem:2589|h[Linen Cloth]|h|r."):match(T.CREATE_PAT) == nil)
check("positional args handled", ("Mining: 75"):match(T.fmtToPattern("%1$s: %2$d")) == "Mining")
check("isSelfLoot self", T.isSelfLoot("You receive loot: [x]."))
check("isSelfLoot pushed", T.isSelfLoot("You receive item: [x]."))
check("isSelfLoot groupmate", not T.isSelfLoot("Dave receives loot: [x]."))

-- ── loot via the REAL CHAT_MSG_LOOT handler ──
local LINK = "|cffffffff|Hitem:2589::::::::12:::::|h[Linen Cloth]|h|r"
M.fire("CHAT_MSG_LOOT", "You receive loot: " .. LINK .. "x3.")
M.fire("CHAT_MSG_LOOT", "Dave receives loot: " .. LINK .. ".")
M.fire("CHAT_MSG_LOOT", "You create: " .. LINK .. "x2.")
local items = count(ns.DB.loot.log, function(e) return e.item == "Linen Cloth" end)
check("self loot logged once (groupmate + craft excluded)", items == 1, items)
check("loot count parsed x3", ns.DB.loot.log[1] and ns.DB.loot.log[1].count == 3, ns.DB.loot.log[1] and ns.DB.loot.log[1].count)

-- ── gold via the REAL PLAYER_MONEY handler ──
M.money = 5250; M.fire("PLAYER_MONEY")                       -- +250, no loot window -> gained only
check("gold gained", ns.DB.loot.gold.gained == 250, ns.DB.loot.gold.gained)
check("gold not looted (no window)", (ns.DB.loot.gold.looted or 0) == 0, ns.DB.loot.gold.looted)
M.units.target = { name = "Kobold Miner", hostile = true, dead = true, guid = "Creature-0-1-1-1-6-000A" }
M.fire("LOOT_OPENED"); M.money = 5330; M.fire("PLAYER_MONEY")   -- +80 inside a loot window -> looted
check("gold looted in loot window", ns.DB.loot.gold.looted == 80, ns.DB.loot.gold.looted)
local coin = ns.DB.loot.log[#ns.DB.loot.log]
check("coin row logged with source", coin and coin.money == 80 and coin.src == "Kobold Miner", coin and coin.src)
M.money = 5000; M.fire("PLAYER_MONEY")                       -- -330 spent
check("gold spent", ns.DB.loot.gold.spent == 330, ns.DB.loot.gold.spent)
check("gold balance tracks", ns.DB.loot.gold.balance == 5000)
M.units.target = nil

-- ── XP via PLAYER_XP_UPDATE (incl. crossing a level) ──
M.xp = 100; M.fire("PLAYER_XP_UPDATE")           -- baseline
M.xp = 400; M.fire("PLAYER_XP_UPDATE")           -- +300
check("xp gained", ns.DB.character.xp.gained == 300, ns.DB.character.xp.gained)
M.xp = 50; M.xpmax = 1200; M.fire("PLAYER_XP_UPDATE")   -- leveled: (1000-400) + 50 = 650 more
check("xp level-cross accounted", ns.DB.character.xp.gained == 950, ns.DB.character.xp.gained)
check("xp cur/max stored", ns.DB.character.xp.cur == 50 and ns.DB.character.xp.max == 1200)

-- ── /played ──
M.fire("TIME_PLAYED_MSG", 90061, 3600)
check("played total stored", ns.DB.character.played.total == 90061)
check("played stamped at level", ns.DB.character.playedAtLevel and ns.DB.character.playedAtLevel[12] == 90061)

-- ── fight lifecycle through the REAL recorder ──
M.units.target = { name = "Kobold Miner", hostile = true, guid = "Creature-0-1-1-1-6-000B", cls = "normal" }
M.inCombat = true; M.fire("PLAYER_REGEN_DISABLED")
local cur = T.currentFight()
check("fight begins on combat", cur ~= nil)
check("fight has uid", cur and type(cur.uid) == "string" and cur.uid:find("Hart%-Realm%-") ~= nil)
check("fight has identity", cur and cur.player == "Hart" and cur.realm == "Realm" and cur.schema == 1)
check("fight has local clock", cur and type(cur.startLocal) == "number")
check("foe captured", cur and cur.foes[1] == "Kobold Miner", cur and cur.foes[1])
M.now = M.now + 12
M.units.target = nil; M.inCombat = false
local before = #ns.DB.combat.fights
M.fire("PLAYER_REGEN_ENABLED")
check("fight stored on combat end", #ns.DB.combat.fights == before + 1)
local f = ns.DB.combat.fights[#ns.DB.combat.fights]
check("fight inferred kill (faced foe, lived)", f and f.outcome == "kill", f and f.outcome)
check("fight duration ~12s", f and math.abs((f.duration or 0) - 12) < 0.01, f and f.duration)
check("stored fight sanitized (no working sets)", f and f._es == nil and f._worn == nil)
check("KILL landed in eventlog", count(ns.DB.story.events, function(e) return e.kind == "KILL" end) >= 1)

-- ── kill over-count guard: foe still alive & targeted at combat end -> no kill ──
M.units.target = { name = "Defias Thug", hostile = true, guid = "Creature-0-1-1-1-7-000C" }
M.inCombat = true; M.fire("PLAYER_REGEN_DISABLED"); M.now = M.now + 3
M.inCombat = false                                            -- still targeted + alive
local killsBefore = count(ns.DB.story.events, function(e) return e.kind == "KILL" end)
M.fire("PLAYER_REGEN_ENABLED")
check("no KILL credited when foe still alive", count(ns.DB.story.events, function(e) return e.kind == "KILL" end) == killsBefore)
M.units.target = nil

-- ── dungeon enter dedupe across reload ──
M.inst = { name = "Deadmines", type = "party", diff = 1, mapID = 36 }
M.fire("PLAYER_ENTERING_WORLD"); M.fire("PLAYER_ENTERING_WORLD")   -- second = a /reload inside
check("DUNGEON emitted once across reload", count(ns.DB.story.events, function(e) return e.kind == "DUNGEON" end) == 1)
M.inst = { name = "Elwynn Forest", type = "none", diff = 0, mapID = 0 }
M.fire("PLAYER_ENTERING_WORLD")
check("DUNGEONLEAVE emitted", count(ns.DB.story.events, function(e) return e.kind == "DUNGEONLEAVE" end) == 1)

-- ── Dungeons run grouping (pure) ──
local runs = T.buildRuns()
check("one run built", #runs == 1, #runs)
check("run named", runs[1] and runs[1].name == "Deadmines", runs[1] and runs[1].name)
check("run closed (not in progress)", runs[1] and runs[1].inProgress == false)

-- ── Deaths matching (pure) ──
ns.DB.story.events[#ns.DB.story.events + 1] = { kind = "DEATH", t = M.epoch, text = "You died  ·  Level 12", zone = "Elwynn Forest", foe = "Kobold Miner", x = 0.5, y = 0.25 }
ns.DB.combat.fights[#ns.DB.combat.fights + 1] = { outcome = "death", startEpoch = M.epoch - 5, duration = 4, level = 12, zone = "Elwynn Forest", foes = { "Kobold Miner" } }
local deaths = T.collectDeaths()
check("death collected", #deaths == 1, #deaths)
check("death linked to its fight", deaths[1] and deaths[1].fight ~= nil)
check("death level from fight", deaths[1] and deaths[1].level == 12)
check("death carries coordinates separately from the killer", deaths[1] and deaths[1].x == 0.5 and deaths[1].killer == "Kobold Miner")

-- ── pure helpers ──
local log = {}
for i = 1, 3 do log[#log + 1] = { t = 0, gain = true, name = "Seed" .. i, atPull = true } end
for i = 1, T.AURA_CAP + 20 do log[#log + 1] = { t = i, gain = true, name = "Churn" .. i } end
T.trimAura(log)
check("trimAura caps", #log == T.AURA_CAP, #log)
check("trimAura preserves pull seeds", count(log, function(a) return a.atPull end) == 3)

local s = T.sanitize({ a = 1, b = 0 / 0, c = math.huge, d = function() end, e = "x|cff00ff00y|r", f = true, g = { h = 2 } })
check("sanitize drops NaN", s.b == nil); check("sanitize drops inf", s.c == nil); check("sanitize drops function", s.d == nil)
check("sanitize strips pipes", s.e == "xcff00ff00yr", s.e); check("sanitize keeps nested", s.g and s.g.h == 2 and s.f == true)

local al = { { t = 0, gain = true, name = "Fort", debuff = false }, { t = 1, gain = true, name = "Poison", debuff = true }, { t = 5, gain = false, name = "Fort", debuff = false } }
local at3, at6 = T.activeAuras(al, 3), T.activeAuras(al, 6)
check("activeAuras at t=3 has both", #at3 == 2 and at3[1].name == "Fort" and at3[2].name == "Poison")
check("activeAuras at t=6 lost Fort", #at6 == 1 and at6[1].name == "Poison")

check("fmtMoney", T.fmtMoney(12345) == "1g 23s 45c" and T.fmtMoney(0) == "0c" and T.fmtMoney(500) == "5s")
check("fmtTime", T.fmtTime(90061) == "1d 1h" and T.fmtTime(3661) == "1h 1m" and T.fmtTime(300) == "5m" and T.fmtTime(0) == "-")
check("commas", T.commas(1234567) == "1,234,567" and T.commas(50) == "50")
check("fmtDur", T.fmtDur(75) == "1:15" and T.fmtDur(9) == "9s")
check("plain passes numbers", T.plain(5) == 5 and T.plain("x") == nil)
check("safeKey passes plain values", T.safeKey("abc") == "abc" and T.safeKey(nil) == nil)
check("safeStr type gate", T.safeStr("ok") == "ok" and T.safeStr(5) == nil)
check("statSig stable", T.statSig({ level = 1, ap = 10 }) == T.statSig({ level = 1, ap = 10 }))
check("foesText", T.foesText({ foes = {} }) == "unknown" and T.foesText({ bossName = "Edwin", foes = {} }) == "Edwin")

-- ── Events tab helpers ──
check("eventMatches all", T.eventMatches({ kind = "ZONE" }, "all"))
check("eventMatches combat", T.eventMatches({ kind = "KILL" }, "combat") and not T.eventMatches({ kind = "ZONE" }, "combat"))
check("eventMatches travel", T.eventMatches({ kind = "FLIGHT" }, "travel") and T.eventMatches({ kind = "DUNGEON" }, "travel"))
check("eventMatches journey", T.eventMatches({ kind = "LEVELUP" }, "journey") and not T.eventMatches({ kind = "LOOT" }, "journey"))
check("fmtWhere zone + coords", T.fmtWhere({ zone = "Elwynn Forest", x = 0.421, y = 0.637 }) == "Elwynn Forest  (42.1, 63.7)")
check("fmtWhere sub, zone", T.fmtWhere({ zone = "Elwynn Forest", sub = "Goldshire" }) == "Goldshire, Elwynn Forest")
check("fmtWhere sub == zone collapses", T.fmtWhere({ zone = "Deadmines", sub = "Deadmines" }) == "Deadmines")
check("fmtWhere empty", T.fmtWhere({}) == "")
-- ── on-screen notification muting (Settings) ──
ns.DB.settings.flagMute = { travel = true }
check("flagMuted: muted group", T.flagMuted("ZONE") == true and T.flagMuted("FLIGHT") == true)
check("flagMuted: other groups untouched", T.flagMuted("KILL") == false and T.flagMuted("LOOT") == false)
check("flagMuted: level-up/death/wipe never mute", T.flagMuted("LEVELUP") == false and T.flagMuted("DEATH") == false and T.flagMuted("WIPE") == false)
M.zone = "Westfall"; M.fire("ZONE_CHANGED_NEW_AREA")
check("muted event is still RECORDED in the timeline", count(ns.DB.story.events, function(e) return e.kind == "ZONE" and e.text == "Westfall" end) == 1)
check("a muted notification has no show time", count(ns.DB.story.events, function(e) return e.kind == "ZONE" and e.text == "Westfall" and e.shown == nil end) == 1)
ns.DB.settings.flagMute = nil
check("flagMuted: default is unmuted", T.flagMuted("ZONE") == false)
M.now = M.now + 30   -- let any notification on screen expire
M.zone = "Duskwood"; M.fire("ZONE_CHANGED_NEW_AREA")
check("a shown notification records when it reached the screen", count(ns.DB.story.events, function(e) return e.kind == "ZONE" and e.text == "Duskwood" and e.shown == math.floor(M.now * 1000 + 0.5) / 1000 end) == 1)
-- ── gathering loot attribution ──
M.units.target = nil
M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 2575)          -- Mining
M.fire("LOOT_OPENED")
M.fire("CHAT_MSG_LOOT", "You receive loot: |cffffffff|Hitem:2770::::::::12:::::|h[Copper Ore]|h|rx2.")
local ore = ns.DB.loot.log[#ns.DB.loot.log]
check("mining node is the SOURCE (no coords embedded)", ore and ore.item == "Copper Ore" and ore.src == "Mining node", ore and ore.src)
check("loot row carries x/y/zone", ore and ore.x == 0.421 and ore.y == 0.637 and ore.zone ~= nil)
M.now = M.now + 10                                                      -- gather cast expires
M.lootSourceGUID = "GameObject-0-1-1-1-1731-000B"; M.fire("LOOT_OPENED")
M.fire("CHAT_MSG_LOOT", "You receive loot: |cffffffff|Hitem:2447::::::::12:::::|h[Peacebloom]|h|r.")
local herb = ns.DB.loot.log[#ns.DB.loot.log]
check("object loot attributed by GUID type", herb and herb.src == "Object", herb and herb.src)
M.lootSourceGUID = nil
M.units.target = { name = "Mottled Boar", hostile = true, dead = true, guid = "Creature-0-1-1-1-3098-000C" }
M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-2", 8613)          -- Skinning
M.fire("LOOT_OPENED")
M.fire("CHAT_MSG_LOOT", "You receive loot: |cffffffff|Hitem:2934::::::::12:::::|h[Ruined Leather Scraps]|h|r.")
local skin = ns.DB.loot.log[#ns.DB.loot.log]
check("skinned corpse keeps the readable name", skin and skin.src == "Mottled Boar", skin and skin.src)
M.units.target = nil
-- loot quality: hex link colors, 11.0+ named quality colors (Forever), API fallback, and the login backfill (#9)
M.fire("CHAT_MSG_LOOT", "You receive loot: |cnIQ2:|Hitem:3010::::::::12:::::|h[Green Thing]|h|r.")
local qgreen = ns.DB.loot.log[#ns.DB.loot.log]
check("named quality color |cnIQ2: parsed as uncommon", qgreen and qgreen.q == "ff1eff00", qgreen and qgreen.q)
M.fire("CHAT_MSG_LOOT", "You receive loot: |cffa335ee|Hitem:3011::::::::12:::::|h[Purple Thing]|h|r.")
local qpurple = ns.DB.loot.log[#ns.DB.loot.log]
check("hex link color still parsed as epic", qpurple and qpurple.q == "ffa335ee", qpurple and qpurple.q)
M.itemQuality[3012] = 3
M.fire("CHAT_MSG_LOOT", "You receive loot: |Hitem:3012::::::::12:::::|h[Blue Thing]|h|r.")
local qblue = ns.DB.loot.log[#ns.DB.loot.log]
check("no link color: quality from C_Item.GetItemQualityByID", qblue and qblue.q == "ff0070dd", qblue and qblue.q)
M.fire("CHAT_MSG_LOOT", "You receive loot: |Hitem:3013::::::::12:::::|h[Unknown Thing]|h|r.")
local qunknown = ns.DB.loot.log[#ns.DB.loot.log]
check("no color and no API answer stays white", qunknown and qunknown.q == "ffffffff", qunknown and qunknown.q)
ns.DB.loot.log[#ns.DB.loot.log + 1] = { t = 1, item = "Old Row", count = 1, q = "ffffffff", id = 3014, src = "Creature", s = ns.DB.active }
M.itemQuality[3014] = 4
local fixedRows = ns.Emitter.backfillLootQuality()
local old = ns.DB.loot.log[#ns.DB.loot.log]
check("backfill resolves old white rows by item id", fixedRows >= 1 and old.q == "ffa335ee", old.q)
check("backfill leaves a true white row white", qunknown.q == "ffffffff", qunknown.q)
-- ── aura timelines (player + enemy) through the REAL recorder ──
M.auras.player = { HELPFUL = { { name = "Power Word: Fortitude", icon = 135987, spellId = 1243 } }, HARMFUL = {} }
M.units.target = { name = "Kobold Miner", hostile = true, guid = "Creature-0-1-1-1-6-000D" }
M.auras.target = { HELPFUL = {}, HARMFUL = { { name = "Rend", icon = 132155, spellId = 772 } } }
M.inCombat = true; M.now = M.now + 5; M.fire("PLAYER_REGEN_DISABLED")
local cf = T.currentFight()
check("player buff seeded at pull", cf and count(cf.auras, function(a) return a.name == "Power Word: Fortitude" and a.atPull end) == 1)
check("enemy tracked with its debuff at pull", cf and cf.enemies and cf.enemies[1] and cf.enemies[1].name == "Kobold Miner"
  and cf.enemies[1].auras[1] and cf.enemies[1].auras[1].name == "Rend", cf and cf.enemies and cf.enemies[1] and cf.enemies[1].name)
M.now = M.now + 1
M.auras.player.HARMFUL = { { name = "Poison", icon = 132273, spellId = 744 } }
M.fire("UNIT_AURA", "player")
check("player debuff gain recorded", cf and count(cf.auras, function(a) return a.name == "Poison" and a.gain == true end) == 1)
M.now = M.now + 1
M.auras.player.HELPFUL = {}
M.fire("UNIT_AURA", "player")
check("player buff loss recorded", cf and count(cf.auras, function(a) return a.name == "Power Word: Fortitude" and a.gain == false end) == 1)
M.now = M.now + 0.1; M.fire("UNIT_AURA", "player")
check("UNIT_AURA throttled within 0.25s (no duplicate entries)", cf and count(cf.auras, function(a) return a.name == "Power Word: Fortitude" end) == 2)
M.now = M.now + 1; M.inCombat = false; M.units.target = nil
M.fire("PLAYER_REGEN_ENABLED")
local sf = ns.DB.combat.fights[#ns.DB.combat.fights]
check("stored fight keeps aura timeline + enemy", sf and #sf.auras >= 3 and sf.enemies and #sf.enemies == 1, sf and #sf.auras)
check("stored fight has no working sets", sf and sf._es == nil and sf._enemyByGuid == nil and sf._memberByUnit == nil)
M.auras = {}
-- ── Fights text search ──
check("fightMatchesText foe", T.fightMatchesText({ foes = { "Kobold Miner" }, zone = "Elwynn" }, "kobold"))
check("fightMatchesText zone", T.fightMatchesText({ foes = {}, zone = "Deadmines" }, "dead"))
check("fightMatchesText boss name", T.fightMatchesText({ bossName = "Edwin VanCleef", foes = {} }, "vancleef"))
check("fightMatchesText miss", not T.fightMatchesText({ foes = { "Boar" }, zone = "Durotar" }, "kobold"))
check("fightMatchesText empty query", T.fightMatchesText({ foes = {} }, "") and T.fightMatchesText({ foes = {} }, nil))
-- ── first-visit zones ──
M.zone = "Redridge Mountains"; M.fire("ZONE_CHANGED_NEW_AREA")
check("FIRSTZONE on a never-seen zone", count(ns.DB.story.events, function(e) return e.kind == "FIRSTZONE" and (e.text or ""):find("Redridge") ~= nil end) == 1)
M.zone = "Elwynn Forest"; M.fire("ZONE_CHANGED_NEW_AREA")
check("login zone was seeded as seen (no FIRSTZONE)", count(ns.DB.story.events, function(e) return e.kind == "FIRSTZONE" and (e.text or ""):find("Elwynn") ~= nil end) == 0)
M.zone = "Redridge Mountains"; M.fire("ZONE_CHANGED_NEW_AREA")
check("no second FIRSTZONE for a known zone", count(ns.DB.story.events, function(e) return e.kind == "FIRSTZONE" and (e.text or ""):find("Redridge") ~= nil end) == 1)
check("plain ZONE still fires on re-entry", count(ns.DB.story.events, function(e) return e.kind == "ZONE" and e.text == "Redridge Mountains" end) == 2)
-- ── roster join / leave ──
M.units.party1 = { name = "Dave" }; M.groupN = 2; M.fire("GROUP_ROSTER_UPDATE")
check("ROSTERJOIN recorded", count(ns.DB.story.events, function(e) return e.kind == "ROSTERJOIN" and (e.text or ""):find("Dave") ~= nil end) == 1)
M.fire("GROUP_ROSTER_UPDATE")
check("no duplicate join on an unchanged roster", count(ns.DB.story.events, function(e) return e.kind == "ROSTERJOIN" end) == 1)
M.units.party1 = nil; M.groupN = 1; M.fire("GROUP_ROSTER_UPDATE")
check("ROSTERLEAVE recorded", count(ns.DB.story.events, function(e) return e.kind == "ROSTERLEAVE" and (e.text or ""):find("Dave") ~= nil end) == 1)
-- ── fractional video anchor on fights ──
local lf = ns.DB.combat.fights[#ns.DB.combat.fights]
check("fight carries fractional local clock", lf and type(lf.startLocalHi) == "number" and type(lf.endLocalHi) == "number" and lf.endLocalHi >= lf.startLocalHi)
check("anchor agrees with duration", lf and math.abs((lf.endLocalHi - lf.startLocalHi) - lf.duration) < 0.01)
-- ── gold sink attribution (window open when the purse moved) ──
M.money = 5000; M.fire("PLAYER_MONEY")                          -- re-baseline
local g0 = ns.DB.loot.gold; local other0 = g0.other or 0   -- earlier tests already spent into "other"
M.fire("MERCHANT_SHOW"); M.money = 4850; M.fire("PLAYER_MONEY")   -- bought something
check("vendor spend attributed", g0.vendor == 150, g0.vendor)
M.money = 4890; M.fire("PLAYER_MONEY")                           -- sold something
check("vendor sale counted as income", g0.sold == 40, g0.sold)
M.fire("MERCHANT_CLOSED"); M.fire("TRAINER_SHOW"); M.money = 4390; M.fire("PLAYER_MONEY")
check("training spend attributed", g0.training == 500, g0.training)
M.fire("TRAINER_CLOSED"); M.fire("TAXIMAP_OPENED"); M.money = 4365; M.fire("PLAYER_MONEY")
check("flight spend attributed", g0.flights == 25, g0.flights)
M.now = M.now + 10; M.money = 4300; M.fire("PLAYER_MONEY")
check("unattributed spend lands in other", g0.other == other0 + 65, g0.other)
-- ── durability + broken gear ──
M.dur = { [1] = { 50, 100 }, [16] = { 0, 100 } }
M.fire("UPDATE_INVENTORY_DURABILITY")
check("durability aggregated", ns.DB.character.durability and ns.DB.character.durability.pct == 25, ns.DB.character.durability and ns.DB.character.durability.pct)
check("BROKEN milestone for the main hand", count(ns.DB.story.events, function(e) return e.kind == "BROKEN" and (e.text or ""):find("Main hand") ~= nil end) == 1)
M.fire("UPDATE_INVENTORY_DURABILITY")
check("BROKEN not repeated while still broken", count(ns.DB.story.events, function(e) return e.kind == "BROKEN" end) == 1)
M.dur[16] = { 100, 100 }; M.fire("UPDATE_INVENTORY_DURABILITY")
check("durability updates after repair", ns.DB.character.durability.pct == 75, ns.DB.character.durability.pct)
M.dur[16] = { 0, 100 }; M.fire("UPDATE_INVENTORY_DURABILITY")
check("BROKEN fires again after a repair-then-break", count(ns.DB.story.events, function(e) return e.kind == "BROKEN" end) == 2)
M.dur = {}
-- ── collections + profession tiers ──
M.fire("NEW_MOUNT_ADDED", 458)
check("mount collected with name", count(ns.DB.story.events, function(e) return e.kind == "COLLECT" and (e.text or ""):find("Brown Horse") ~= nil end) == 1)
M.profs[1] = { name = "Mining", rank = 70, max = 75 }; M.fire("SKILL_LINES_CHANGED")   -- first sight: seeds only
check("profession snapshot stored", ns.DB.character.professions and ns.DB.character.professions.Mining and ns.DB.character.professions.Mining.rank == 70)
check("no tier event on first sight", count(ns.DB.story.events, function(e) return e.kind == "PROFTIER" end) == 0)
M.profs[1].rank = 76; M.profs[1].max = 150; M.fire("SKILL_LINES_CHANGED")
check("PROFTIER at 75", count(ns.DB.story.events, function(e) return e.kind == "PROFTIER" and (e.text or ""):find("Mining 75") ~= nil end) == 1)
M.profs[1].rank = 80; M.fire("SKILL_LINES_CHANGED")
check("no tier event between boundaries", count(ns.DB.story.events, function(e) return e.kind == "PROFTIER" end) == 1)
-- ── Fights column sort (pure) ──
local F1 = { startEpoch = 100, duration = 5, outcome = "kill", foes = { "Boar" } }
local F2 = { startEpoch = 200, duration = 50, outcome = "death", foes = { "Kobold" } }
local F3 = { startEpoch = 300, duration = 20, outcome = "wipe", bossName = "Edwin", foes = {} }
local byTime = T.sortFights({ F1, F2, F3 }, "time", false)
check("sort time desc (default) newest first", byTime[1] == F3 and byTime[3] == F1)
local byDur = T.sortFights({ F1, F2, F3 }, "dur", true)
check("sort duration asc", byDur[1] == F1 and byDur[2] == F3 and byDur[3] == F2)
local byFoe = T.sortFights({ F1, F2, F3 }, "foe", true)
check("sort faced asc", byFoe[1] == F1 and byFoe[2] == F3 and byFoe[3] == F2)
local byRes = T.sortFights({ F1, F2, F3 }, "res", true)
check("sort result asc", byRes[1] == F2 and byRes[2] == F1 and byRes[3] == F3)
-- ── UI smoke: build + refresh EVERY tab against the real data accumulated above ──
ns.UI.Open("Home")
for _, tab in ipairs(T.tabs) do
  ns.UI.Open(tab.name)
  check("tab builds cleanly: " .. tab.name, tab.buildError == nil, tab.buildError)
  check("tab refreshes cleanly: " .. tab.name, tab.showError == nil, tab.showError)
  if tab.host then
    for _, pn in ipairs(tab.panes) do
      tab.ctl.select(pn.key)
      check("pane builds cleanly: " .. tab.name .. "/" .. pn.key, pn.buildError == nil, pn.buildError)
      check("pane refreshes cleanly: " .. tab.name .. "/" .. pn.key, pn.showError == nil, pn.showError)
    end
    tab.ctl.select(tab.panes[1].key)
  end
end
check("no pane errors reported by the framework", #ns.UI.paneErrors() == 0, table.concat(ns.UI.paneErrors(), " || "))
M.tick()   -- run every live-refresh ticker once (list rebuilds, dashboards, status line)
local anyFight
for _, f in ipairs(ns.DB.combat.fights) do if f.enemies and #f.enemies > 0 then anyFight = f end end
anyFight = anyFight or ns.DB.combat.fights[1]
if anyFight and ns.OpenFightDetail then
  local ok, err = pcall(ns.OpenFightDetail, anyFight)
  check("fight detail renders", ok, err)
  local sl = _G.EverbuffFightScrubber
  if sl then
    local ok2, e2 = pcall(function() sl:SetValue(0); sl:SetValue((anyFight.duration or 1) / 2); sl:SetValue(anyFight.duration or 1) end)
    check("scrubber renders at pull, mid and end", ok2, e2)
  else check("scrubber exists", false, "EverbuffFightScrubber not created") end
end
check("UI reports no tab errors", #ns.UI.tabErrors() == 0, table.concat(ns.UI.tabErrors(), " | "))
-- ── minimap button ──
check("minimap button built on entering world", _G.EverbuffMinimapButton ~= nil)
-- ── flight trips ──
M.zone = "Elwynn Forest"; M.onTaxi = true; M.fire("PLAYER_CONTROL_LOST")
M.now = M.now + 200; M.zone = "Westfall"; M.onTaxi = false; M.fire("PLAYER_CONTROL_GAINED")
check("flight trip recorded with route + duration", count(ns.DB.story.events, function(e) return e.kind == "FLIGHTTRIP" and (e.text or ""):find("Elwynn Forest to Westfall %(3m 20s%)") ~= nil end) == 1)
check("total flight time accumulated", ns.DB.character.flightTime == 200, ns.DB.character.flightTime)
M.fire("PLAYER_CONTROL_GAINED")
check("control regained without a flight is ignored", count(ns.DB.story.events, function(e) return e.kind == "FLIGHTTRIP" end) == 1)
-- #11: the taxi flag raised after control is lost (or no control events at all): the TakeTaxiNode watch
M.zone = "Westfall"; M.onTaxi = false; TakeTaxiNode(3); M.fire("PLAYER_CONTROL_LOST")
M.now = M.now + 1; M.onTaxi = true; M.tick()
M.now = M.now + 89; M.zone = "Duskwood"; M.onTaxi = false; M.tick()
check("#11 flight recorded from the taxi flag", count(ns.DB.story.events, function(e) return e.kind == "FLIGHTTRIP" and (e.text or ""):find("Westfall to Duskwood %(1m 30s%)") ~= nil end) == 1)
M.fire("PLAYER_CONTROL_GAINED"); M.tick()
check("#11 the same flight is not recorded twice", count(ns.DB.story.events, function(e) return e.kind == "FLIGHTTRIP" end) == 2 and ns.DB.character.flightTime == 290, ns.DB.character.flightTime)
TakeTaxiNode(4); for _ = 1, 12 do M.now = M.now + 1; M.tick() end
M.fire("PLAYER_CONTROL_LOST"); M.now = M.now + 4; M.fire("PLAYER_CONTROL_GAINED")
check("#11 a taxi that never left, then a stun, is no flight", count(ns.DB.story.events, function(e) return e.kind == "FLIGHTTRIP" end) == 2)
-- ── spec snapshot on a fight ──
M.inCombat = true; M.now = M.now + 5; M.fire("PLAYER_REGEN_DISABLED"); M.now = M.now + 2; M.inCombat = false; M.fire("PLAYER_REGEN_ENABLED")
check("fight records the spec", ns.DB.combat.fights[#ns.DB.combat.fights].spec == "Arms", ns.DB.combat.fights[#ns.DB.combat.fights].spec)
local nF, capF = ns.Fights.capInfo()
check("capInfo reports count + cap", nF == #ns.DB.combat.fights and capF == 1000)

-- A1 (#38): at the cap an uploaded fight goes first; an un-uploaded one only when nothing else can, and not silently
do
  local said = {}
  local oldMsg = ns.msg
  ns.msg = function(m) said[#said + 1] = m end
  local list = {}
  for i = 1, 1000 do list[i] = { id = i, uploaded = (i == 500) } end
  list[#list + 1] = { id = 1001, uploaded = false }
  ns.Fights.trim(list)
  local has500 = false
  for _, f in ipairs(list) do if f.id == 500 then has500 = true end end
  check("A1: at the cap the uploaded fight goes first", #list == 1000 and not has500 and list[1].id == 1 and #said == 0)
  list[#list + 1] = { id = 1002, uploaded = false }
  ns.Fights.trim(list)
  check("A1: then the oldest un-uploaded fight goes, and chat says so", #list == 1000 and list[1].id == 2 and #said == 1 and said[1]:find("not read yet") ~= nil)
  ns.msg = oldMsg
end
-- ── DATA CONTRACT: the shape the desktop parses (see docs/ADDON_DATA_CONTRACT.md) ──
for _, k in ipairs({ "schema", "settings", "sessions", "combat", "loot", "character", "story" }) do
  check("contract: top-level key " .. k, ns.DB[k] ~= nil, "missing")
end
check("contract: schema 2", ns.DB.schema == 2, ns.DB.schema)
-- everbuff-backend #85: the second name, only where the client shows surnames (elsewhere UnitName's second value is the realm)
do
  local saved = _G.C_PlayerInfo
  _G.C_PlayerInfo = nil
  check("surname: none without C_PlayerInfo.ShouldDisplaySurname (the realm is never taken for it)", ns.surname() == nil)
  _G.C_PlayerInfo = { ShouldDisplaySurname = function() return false end }
  check("surname: none when the client hides surnames", ns.surname() == nil)
  _G.C_PlayerInfo = { ShouldDisplaySurname = function() return true end }
  check("surname: UnitName's second value when surnames show", ns.surname() == "Realm", tostring(ns.surname()))
  _G.C_PlayerInfo = { ShouldDisplaySurname = function() error("boom") end }
  check("surname: an erroring client call is no surname", ns.surname() == nil)
  _G.C_PlayerInfo = saved
end
check("contract: no v1 keys left at the top level", ns.DB.fights == nil and ns.DB.lootlog == nil and ns.DB.eventlog == nil and ns.DB.gold == nil and ns.DB.xp == nil)
check("contract: combat / loot / character / story shapes", type(ns.DB.combat.fights) == "table" and type(ns.DB.loot.log) == "table" and type(ns.DB.loot.gold) == "table" and type(ns.DB.character.xp) == "table" and type(ns.DB.story.events) == "table")
local cf2 = ns.DB.combat.fights[#ns.DB.combat.fights]
for _, k in ipairs({ "id", "uid", "schema", "player", "realm", "startEpoch", "startLocal", "startLocalHi", "endEpoch", "endLocalHi", "duration", "zone", "foes", "outcome", "auras", "gear", "stats", "uploaded" }) do
  check("contract: fight field " .. k, cf2[k] ~= nil, "missing")
end
check("contract: fight.gear has initial + swaps", type(cf2.gear.initial) == "table" and type(cf2.gear.swaps) == "table")
check("contract: no pipe characters anywhere in a stored fight", (function()
  local function scan(v) if type(v) == "string" then return not v:find("|", 1, true) elseif type(v) == "table" then for _, x in pairs(v) do if not scan(x) then return false end end end return true end
  return scan(cf2) end)())
local le = ns.DB.story.events[#ns.DB.story.events]
for _, k in ipairs({ "t", "kind", "text", "s" }) do check("contract: event field " .. k, le[k] ~= nil, "missing") end
check("contract: fight and loot rows carry the session id", cf2.session ~= nil and ns.DB.loot.log[#ns.DB.loot.log].s ~= nil)
check("contract: a session record carries its gold ledger with the lifetime keys (#46)", (function()
  local sg = ns.DB.sessions[ns.DB.active] and ns.DB.sessions[ns.DB.active].gold
  if type(sg) ~= "table" then return false end
  for _, k in ipairs({ "gained", "spent", "looted", "sold", "quests", "auctionSales", "mail", "repairs", "vendor", "training", "flights", "auctions", "mailSpent", "other" }) do
    if type(sg[k]) ~= "number" then return false end
  end
  return sg.balance == nil end)())
-- v1 -> v2 migration of an old save file
do
  local old = { fights = { { id = 1 } }, fightSeq = 1, lootlog = { { item = "x" } }, gold = { balance = 5 }, eventlog = { { kind = "ZONE" } }, xp = { cur = 1 }, seenZones = { Elwynn = 1 }, settings = { emitCorner = "TOPLEFT" }, sessions = {}, session = { xp = 3 } }
  ns.migrateDB(old)
  check("migration moves v1 keys into their areas", old.schema == 2 and #old.combat.fights == 1 and old.combat.fightSeq == 1 and #old.loot.log == 1 and old.loot.gold.balance == 5 and #old.story.events == 1 and old.character.xp.cur == 1 and old.character.seenZones.Elwynn == 1)
  check("migration drops the v1 slots", old.fights == nil and old.lootlog == nil and old.gold == nil and old.eventlog == nil and old.xp == nil and old.session == nil)
  check("migration keeps settings and sessions", old.settings.emitCorner == "TOPLEFT" and type(old.sessions) == "table")
end
-- ── Settings absorbed Sync ──
local names = {}
for _, tab in ipairs(T.tabs) do names[tab.name] = true end
check("Sync is no longer a top-level tab", names.Sync == nil)
check("five top-level tabs: Home · Combat · Loot · Character · Settings", #T.tabs == 5 and names.Home and names.Combat and names.Loot and names.Character and names.Settings, #T.tabs)
check("old tab names are gone", names.Journey == nil and names.Fights == nil and names.Deaths == nil and names.Dungeons == nil and names.Timeline == nil and names.Progress == nil and names.Economy == nil)
local function host(n) for _, tab in ipairs(T.tabs) do if tab.name == n then return tab end end end
check("Combat hosts Dungeons · Fights · Deaths in that order", (function() local h = host("Combat"); return h and h.panes[1].key == "dungeons" and h.panes[2].key == "fights" and h.panes[3].key == "deaths" end)())
check("Home hosts Overview · Timeline · Sessions", (function() local h = host("Home"); return h and h.panes[1].key == "overview" and h.panes[2].key == "timeline" and h.panes[3].key == "sessions" end)())
check("Loot hosts Items · Gold; Character hosts Quests · Reputation · Professions", (function() local l, c = host("Loot"), host("Character"); return l and l.panes[1].key == "items" and l.panes[2].key == "gold" and c and c.panes[1].key == "quests" and c.panes[3].key == "professions" end)())
check("capture pane builder exposed", type(ns.BuildCapturePane) == "function")
-- ── Settings sub-tab control ──
local settingsTab
for _, tab in ipairs(T.tabs) do if tab.name == "Settings" then settingsTab = tab end end
local st = settingsTab and settingsTab.content and settingsTab.content.subtabs
check("Settings exposes a tab control with three panes", st and st.panes.general and st.panes.capture and st.panes.data)
if st then
  local okSel, errSel = pcall(function() st.select("capture"); st.select("data"); st.select("general") end)
  check("switching sub-tabs renders cleanly", okSel, errSel)
  check("only the active pane is shown", st.panes.general:IsShown() and not st.panes.capture:IsShown() and not st.panes.data:IsShown())
end
-- ── Source / Location split ──
check("fmtLocation zone + coords", ns.UI.fmtLocation("Elwynn Forest", 0.421, 0.637) == "Elwynn Forest  (42.1, 63.7)")
check("fmtLocation sub + zone", ns.UI.fmtLocation("Elwynn Forest", nil, nil, "Goldshire") == "Goldshire, Elwynn Forest")
check("fmtLocation coords only", ns.UI.fmtLocation(nil, 0.5, 0.5) == "(50.0, 50.0)")
check("fmtLocation nothing", ns.UI.fmtLocation(nil) == "")
local lastFight = ns.DB.combat.fights[#ns.DB.combat.fights]
check("fights capture coordinates at the pull", lastFight and lastFight.x == 0.421 and lastFight.y == 0.637 and lastFight.map == 37, lastFight and lastFight.x)
-- ── filter tabs on Fights + Timeline ──
local fl = T.fightsList()
check("Fights list has a tab control", fl and fl.tabs and fl.tabs.content ~= nil)
if fl and fl.tabs then
  local okF, errF = pcall(function() fl.tabs.select("death"); fl.tabs.select("notable"); fl.tabs.select("all") end)
  check("Fights filter tabs switch cleanly", okF, errF)
end
local tlTab = host("Home") and host("Home").paneByKey.timeline
check("Timeline pane has a filter tab control", tlTab and tlTab.content and tlTab.content.tabs ~= nil)
if tlTab and tlTab.content and tlTab.content.tabs then
  local okT, errT = pcall(function() tlTab.content.tabs.select("combat"); tlTab.content.tabs.select("all") end)
  check("Timeline filter tabs switch cleanly", okT, errT)
end
-- ── in-combat SECRET aura data (Midnight): tracked by instance id, names resolved / backfilled ──
local SECRET = 0 / 0   -- NaN cannot be used as a table key: stands in for a Secret Value in the stub
M.auras.player = { HELPFUL = {
  { name = SECRET, icon = 135987, spellId = 1243, auraInstanceID = 501 },   -- name hidden, spell id readable
  { name = SECRET, icon = SECRET, spellId = SECRET, auraInstanceID = 502 }, -- everything hidden but the instance
}, HARMFUL = {} }
M.units.target = { name = "Kobold Miner", hostile = true, guid = "Creature-0-1-1-1-6-000E" }
M.inCombat = true; M.now = M.now + 5; M.fire("PLAYER_REGEN_DISABLED")
local cf3 = T.currentFight()
check("hidden name resolved from spell id at the pull", cf3 and count(cf3.auras, function(a) return a.name == "Power Word: Fortitude" and a.atPull end) == 1)
check("fully hidden aura still seeded by instance id", cf3 and count(cf3.auras, function(a) return a.inst == 502 and a.atPull and a.name == nil end) == 1)
check("hidden reads counted for the diagnostic", ns.Fights.hiddenAuras >= 1)
M.now = M.now + 1; M.fire("UNIT_AURA", "player")
check("mid-fight rescan of unchanged hidden auras adds nothing", cf3 and #cf3.auras == 2, cf3 and #cf3.auras)
-- combat ends: the client makes names readable again; the final scan backfills the unknown entry
M.now = M.now + 3; M.inCombat = false; M.units.target = nil
M.auras.player.HELPFUL[2].name = "Mark of the Wild"; M.auras.player.HELPFUL[2].spellId = 1126; M.auras.player.HELPFUL[2].icon = 136078
M.fire("PLAYER_REGEN_ENABLED")
local sf3 = ns.DB.combat.fights[#ns.DB.combat.fights]
check("unknown name backfilled after combat", sf3 and count(sf3.auras, function(a) return a.inst == 502 and a.name == "Mark of the Wild" end) == 1)
check("no spurious end-of-fight mass gain", sf3 and count(sf3.auras, function(a) return a.gain and not a.atPull end) == 0, sf3 and #sf3.auras)
check("scrubber shows both buffs mid-fight", sf3 and #T.activeAuras(sf3.auras, (sf3.duration or 1) / 2) == 2)
M.auras = {}
-- ── blind scan: the client shows auras but hides EVERY identity field -> no diff, no mass loss ──
M.auras.player = { HELPFUL = { { name = "Blessing of Kings", icon = 135995, spellId = 20217, auraInstanceID = 601 },
                               { name = "Find Minerals", icon = 136025, spellId = 2580, auraInstanceID = 602 } }, HARMFUL = {} }
M.inCombat = true; M.now = M.now + 5; M.fire("PLAYER_REGEN_DISABLED")
local cf4 = T.currentFight()
check("two buffs seeded readable at pull", cf4 and count(cf4.auras, function(a) return a.atPull end) == 2)
local blind0 = ns.Fights.blindScans
local S = 0 / 0
M.auras.player.HELPFUL = { { name = S, icon = S, spellId = S, auraInstanceID = S }, { name = S, icon = S, spellId = S, auraInstanceID = S } }
M.now = M.now + 5; M.fire("UNIT_AURA", "player")
check("blind scan recorded as blind", ns.Fights.blindScans == blind0 + 1)
check("blind scan records NO losses (the mid-fight wipe-out)", cf4 and count(cf4.auras, function(a) return a.gain == false end) == 0, cf4 and #cf4.auras)
M.auras.player.HELPFUL = { { name = "Blessing of Kings", icon = 135995, spellId = 20217, auraInstanceID = 601 },
                           { name = "Find Minerals", icon = 136025, spellId = 2580, auraInstanceID = 602 } }
M.now = M.now + 5; M.fire("UNIT_AURA", "player")
check("readable again: no spurious re-gains", cf4 and count(cf4.auras, function(a) return a.gain and not a.atPull end) == 0)
M.now = M.now + 1; M.inCombat = false; M.fire("PLAYER_REGEN_ENABLED")
local sf4 = ns.DB.combat.fights[#ns.DB.combat.fights]
check("scrubber keeps both buffs across the whole fight", sf4 and #T.activeAuras(sf4.auras, (sf4.duration or 1) * 0.6) == 2 and #T.activeAuras(sf4.auras, sf4.duration or 1) == 2)
M.auras = {}
-- ── XP source split ──
check("kill xp parse (named)", T.killXpFrom("Kobold Miner dies, you gain 45 experience.") == 45)
check("kill xp parse (rested)", T.killXpFrom("Kobold Miner dies, you gain 90 experience. (45 exp Rested bonus)") == 90)
check("kill xp parse (unnamed)", T.killXpFrom("You gain 12 experience.") == 12)
check("kill xp parse rejects other lines", T.killXpFrom("You loot 5 Copper.") == nil)
M.fire("CHAT_MSG_COMBAT_XP_GAIN", "Kobold Miner dies, you gain 45 experience.")
M.fire("QUEST_TURNED_IN", 176, 850, 1200)
check("xp split accumulated", ns.DB.character.xp.fromKills == 45 and ns.DB.character.xp.fromQuests == 850, tostring(ns.DB.character.xp.fromKills) .. "/" .. tostring(ns.DB.character.xp.fromQuests))
-- ── recipes ──
M.fire("CHAT_MSG_SYSTEM", "You have learned how to create a new item: |cffffffff|Hitem:2318|h[Light Leather]|h|r.")
check("recipe learned from the system line", count(ns.DB.story.events, function(e) return e.kind == "RECIPE" and (e.text or ""):find("Light Leather") ~= nil end) == 1)
-- ── gear upgrade milestone ──
M.inCombat = false
local ilvl0 = ns.DB.character.ilvl
_G.GetAverageItemLevel = function() return 20, 18 end; M.fire("PLAYER_EQUIPMENT_CHANGED", 16)
check("first equipped ilvl seeds without a milestone", count(ns.DB.story.events, function(e) return e.kind == "UPGRADE" end) == 0 or ilvl0 ~= nil)
_G.GetAverageItemLevel = function() return 21, 19 end; M.fire("PLAYER_EQUIPMENT_CHANGED", 16)
check("UPGRADE on equipped ilvl increase", count(ns.DB.story.events, function(e) return e.kind == "UPGRADE" and (e.text or ""):find("19") ~= nil end) == 1)
_G.GetAverageItemLevel = function() return 21, 18.5 end; M.fire("PLAYER_EQUIPMENT_CHANGED", 16)
check("no UPGRADE on a downgrade", count(ns.DB.story.events, function(e) return e.kind == "UPGRADE" end) == 1)
-- ── reputation standings snapshot ──
M.fire("CHAT_MSG_COMBAT_FACTION_CHANGE", "Reputation with Stormwind increased by 25.")
check("reputation snapshot stored", ns.DB.character.reputation and ns.DB.character.reputation.Stormwind and ns.DB.character.reputation.Stormwind.standing == 5 and ns.DB.character.reputation.Stormwind.label == "Friendly")
-- ── vanish guard: the client returns NO auras mid-combat for a living player (the 10:39 fight) ──
M.auras.player = { HELPFUL = { { name = "Retribution Aura", icon = 1, spellId = 7294, auraInstanceID = 701 },
                               { name = "Seal of Righteousness", icon = 2, spellId = 21084, auraInstanceID = 702 },
                               { name = "Well Fed", icon = 3, spellId = 24870, auraInstanceID = 703 } }, HARMFUL = {} }
M.inCombat = true; M.now = M.now + 5; M.fire("PLAYER_REGEN_DISABLED")
local cf5 = T.currentFight()
check("three buffs seeded", cf5 and count(cf5.auras, function(a) return a.atPull end) == 3)
M.auras.player = { HELPFUL = {}, HARMFUL = {} }                       -- client hides everything: raw = 0
M.now = M.now + 4.4; M.fire("UNIT_AURA", "player")
check("empty scan on a living player records NO losses", cf5 and count(cf5.auras, function(a) return a.gain == false end) == 0, cf5 and #cf5.auras)
check("vanish counted on the fight for later verification", cf5 and (cf5.auraBlind or 0) >= 1)
M.auras.player = { HELPFUL = { { name = "Retribution Aura", icon = 1, spellId = 7294, auraInstanceID = 701 },
                               { name = "Seal of Righteousness", icon = 2, spellId = 21084, auraInstanceID = 702 },
                               { name = "Well Fed", icon = 3, spellId = 24870, auraInstanceID = 703 } }, HARMFUL = {} }
M.now = M.now + 80; M.inCombat = false; M.fire("PLAYER_REGEN_ENABLED")
local sf5 = ns.DB.combat.fights[#ns.DB.combat.fights]
check("no end-of-fight mass re-gain", sf5 and count(sf5.auras, function(a) return a.gain and not a.atPull end) == 0, sf5 and #sf5.auras)
check("scrubber shows all three buffs at t=50", sf5 and #T.activeAuras(sf5.auras, 50) == 3)
check("blind/vanish counter persisted on the stored fight", sf5 and (sf5.auraBlind or 0) >= 1)
-- a real death DOES clear buffs: the guard must not suppress that
M.auras.player = { HELPFUL = { { name = "Well Fed", icon = 3, spellId = 24870, auraInstanceID = 801 }, { name = "Blessing of Kings", icon = 4, spellId = 20217, auraInstanceID = 802 } }, HARMFUL = {} }
M.inCombat = true; M.now = M.now + 5; M.fire("PLAYER_REGEN_DISABLED")
local cf6 = T.currentFight()
M.dead = true; M.auras.player = { HELPFUL = {}, HARMFUL = {} }; M.fire("PLAYER_DEAD"); M.now = M.now + 1; M.fire("UNIT_AURA", "player")
check("death: buffs genuinely lost are recorded", cf6 and count(cf6.auras, function(a) return a.gain == false end) == 2, cf6 and #cf6.auras)
M.inCombat = false; M.fire("PLAYER_REGEN_ENABLED"); M.dead = false; M.auras = {}
-- ── scrubber-side repair of a hidden-window log (the exact 10:39 shape) ──
local function seedLog(names, tLose, tGain)
  local L = {}
  for i, nm in ipairs(names) do L[#L + 1] = { t = 0, gain = true, name = nm, inst = 900 + i, atPull = true } end
  if tLose then for i, nm in ipairs(names) do L[#L + 1] = { t = tLose, gain = false, name = nm, inst = 900 + i } end end
  if tGain then for i, nm in ipairs(names) do L[#L + 1] = { t = tGain, gain = true, name = nm, inst = 900 + i } end end
  return L
end
local six = { "Retribution Aura", "Seal of Righteousness", "Blessing of Kings", "Find Minerals", "Well Fed", "Blessing of Might" }
local artifact = seedLog(six, 4.4, 87.4)
local fixed, removed = T.repairAuraLog(artifact, 87.4)
check("repair drops the hidden-window losses and re-gains", removed == 12 and #fixed == 6, removed)
check("repaired timeline keeps all six buffs at t=50", #T.activeAuras(fixed, 50) == 6)
check("repaired timeline keeps all six buffs at the end", #T.activeAuras(fixed, 87.4) == 6)
local death = seedLog(six, 22.7, nil)
local fixedDeath, removedDeath = T.repairAuraLog(death, 22.7)
check("a death at the end is NOT repaired away", removedDeath == 0 and #T.activeAuras(fixedDeath, 22.7) == 0)
local partial = seedLog({ "A", "B", "C" }, nil, nil); partial[#partial + 1] = { t = 10, gain = false, name = "B", inst = 902 }
local fixedPartial, removedPartial = T.repairAuraLog(partial, 60)
check("a single genuine loss is kept", removedPartial == 0 and #T.activeAuras(fixedPartial, 20) == 2)
local dispel = seedLog({ "A", "B" }, 10, nil); dispel[#dispel + 1] = { t = 30, gain = true, name = "A", inst = 901 }
local fixedDispel, removedDispel = T.repairAuraLog(dispel, 60)
check("all-lost but only partly re-gained is kept as real", removedDispel == 0 and #T.activeAuras(fixedDispel, 20) == 0 and #T.activeAuras(fixedDispel, 40) == 1)
-- ── Location NAME and COORDS are separate ──
check("fmtPlace sub, zone", ns.UI.fmtPlace("Elwynn Forest", "Goldshire") == "Goldshire, Elwynn Forest")
check("fmtPlace zone only", ns.UI.fmtPlace("Elwynn Forest") == "Elwynn Forest" and ns.UI.fmtPlace(nil) == "")
check("fmtCoords bare numbers, no parentheses", ns.UI.fmtCoords(0.421, 0.637) == "42.1, 63.7")
check("fmtCoords empty when unknown", ns.UI.fmtCoords(nil, 0.5) == "")
-- ── mailbox: auction proceeds, mailed items and gold land in the Loot tab ──
M.money = 5000; M.fire("PLAYER_MONEY")                          -- re-baseline
M.inbox = {
  { sender = "Auction House", subject = "Auction successful: Linen Cloth", money = 1234, invoice = { "seller", "Linen Cloth", "Buyerguy", 1000, 1234, 50, 60 } },
  { sender = "Thrall", subject = "gift", money = 0, items = { { name = "Silk Cloth", id = 4306, count = 5, quality = 1 } } },
  { sender = "Auction House", subject = "Auction won: Copper Ore", money = 0, invoice = { "buyer", "Copper Ore", "Sellerguy" }, items = { { name = "Copper Ore", id = 2770, count = 20, quality = 1 } } },
  { sender = "Auction House", subject = "Auction expired: Wool Cloth", money = 0, items = { { name = "Wool Cloth", id = 2592, count = 8, quality = 1 } } },
  { sender = "Sylvanas", subject = "loan", money = 777 },
}
M.fire("MAIL_SHOW")
TakeInboxMoney(1); M.money = 6234; M.fire("PLAYER_MONEY")
local sale = ns.DB.loot.log[#ns.DB.loot.log]
check("auction proceeds logged as coin from 'Auction sale'", sale and sale.money == 1234 and sale.src == "Auction sale", sale and sale.src)
check("auction sale row carries the sold item and buyer", sale and sale.mail and sale.mail.item == "Linen Cloth" and sale.mail.buyer == "Buyerguy")
check("auction sale row has its own location fields", sale and sale.zone == M.zone and sale.x == 0.421 and sale.y == 0.637, sale and tostring(sale.zone) .. " " .. tostring(sale.x))
check("auction sales counted in the gold breakdown", (ns.DB.loot.gold.auctionSales or 0) == 1234, ns.DB.loot.gold.auctionSales)
TakeInboxItem(2, 1)
local gift = ns.DB.loot.log[#ns.DB.loot.log]
check("mailed item logged with the sender as source", gift and gift.item == "Silk Cloth" and gift.count == 5 and gift.src == "Mail from Thrall", gift and gift.src)
local beforeDup = #ns.DB.loot.log
M.fire("CHAT_MSG_LOOT", "You receive item: |cffffffff|Hitem:4306::::::::1:::::::|h[Silk Cloth]|h|rx5.")
check("a chat line for the same mailed item is not logged twice", #ns.DB.loot.log == beforeDup, #ns.DB.loot.log - beforeDup)
AutoLootMailItem(3)
local won = ns.DB.loot.log[#ns.DB.loot.log]
check("auction won item logged via open-all", won and won.item == "Copper Ore" and won.count == 20 and won.src == "Auction won", won and won.src)
TakeInboxItem(4, 1)
local ret = ns.DB.loot.log[#ns.DB.loot.log]
check("expired auction return labeled 'Auction returned'", ret and ret.item == "Wool Cloth" and ret.src == "Auction returned", ret and ret.src)
TakeInboxMoney(5); M.money = 7011; M.fire("PLAYER_MONEY")
local loan = ns.DB.loot.log[#ns.DB.loot.log]
check("gold a player mailed is a coin row from that player", loan and loan.money == 777 and loan.src == "Mail from Sylvanas", loan and loan.src)
check("mailed gold counted separately from auction sales", (ns.DB.loot.gold.mail or 0) == 777)
M.money = 7001; M.fire("PLAYER_MONEY")                          -- postage while the mailbox is open
check("postage / COD while mailbox open is a mail sink", (ns.DB.loot.gold.mailSpent or 0) == 10, ns.DB.loot.gold.mailSpent)
M.fire("MAIL_CLOSED"); M.fire("AUCTION_HOUSE_SHOW"); M.money = 6501; M.fire("PLAYER_MONEY")
check("gold spent at the auction house is attributed to auctions", (ns.DB.loot.gold.auctions or 0) == 500, ns.DB.loot.gold.auctions)
M.fire("AUCTION_HOUSE_CLOSED"); M.inbox = {}
-- ── session pace: XP and gold since login feed per-hour rates ──
M.fire("PLAYER_ENTERING_WORLD", true, false)                        -- a real login resets the session
check("a real login starts a fresh session record", ns.Recorder.current() and ns.Recorder.current().xp == 0 and ns.Recorder.current().gained == 0 and ns.DB.sessions[ns.DB.active] == ns.Recorder.current())
M.money = GetMoney(); M.fire("PLAYER_MONEY")                          -- baseline after reset
M.xp = 100; M.fire("PLAYER_XP_UPDATE"); local sxp0 = ns.Recorder.current().xp   -- first update re-syncs against the old bar
M.xp = 700; M.fire("PLAYER_XP_UPDATE")
check("session XP accumulates", ns.Recorder.current().xp == sxp0 + 600, ns.Recorder.current().xp)
M.money = M.money + 3000; M.fire("PLAYER_MONEY"); M.money = M.money - 1000; M.fire("PLAYER_MONEY")
check("session gold in and out accumulate", ns.Recorder.current().gained == 3000 and ns.Recorder.current().spent == 1000)
-- #46 (everbuff-backend): the session's own gold ledger, credited with the lifetime one, same keys
do
  local sg = ns.Recorder.current().gold
  check("#46 a new session starts its gold ledger with every key at zero", type(sg) == "table" and sg.vendor == 0 and sg.repairs == 0 and sg.auctionSales == 0 and sg.balance == nil)
  check("#46 session ledger gained and spent", sg and sg.gained == 3000 and sg.spent == 1000 and sg.other == 1000, sg and (tostring(sg.gained) .. " " .. tostring(sg.spent) .. " " .. tostring(sg.other)))
  local life = ns.DB.loot.gold; local lv, lr = life.vendor or 0, life.repairs or 0
  M.fire("MERCHANT_SHOW"); M.money = M.money - 200; M.fire("PLAYER_MONEY")      -- bought at a vendor
  RepairAllItems(); M.money = M.money - 75; M.fire("PLAYER_MONEY")              -- repaired
  M.money = M.money + 40; M.fire("PLAYER_MONEY"); M.fire("MERCHANT_CLOSED")      -- sold
  check("#46 vendor spend in both ledgers", sg.vendor == 200 and life.vendor == lv + 200, sg.vendor)
  check("#46 repairs in both ledgers", sg.repairs == 75 and life.repairs == lr + 75, sg.repairs)
  check("#46 vendor sale in the session ledger", sg.sold == 40, sg.sold)
  M.now = M.now + 10
  ns.Emitter.questMoney(500); M.money = M.money + 500; M.fire("PLAYER_MONEY")   -- quest reward after the turn-in
  M.now = M.now + 10; M.money = M.money + 650; M.fire("PLAYER_MONEY"); ns.Emitter.questMoney(650)   -- and before it
  check("#46 quest money in the session ledger, either order", sg.quests == 1150, sg.quests)
  check("#46 the lifetime ledger still has no session-only keys", life.balance ~= nil)
  -- a session that began before the ledger existed keeps none, so a partial ledger is never sent as the whole
  local cur = ns.Recorder.current(); local saved = cur.gold; cur.gold = nil
  M.money = M.money - 10; M.fire("PLAYER_MONEY")
  check("#46 an older session without a ledger is not given a partial one", cur.gold == nil)
  cur.gold = saved
  check("#46 the ledger is in the save file record", ns.DB.sessions[ns.DB.active].gold == saved)
end
M.fire("PLAYER_ENTERING_WORLD", false, true)                        -- a /reload keeps the running session
check("reload keeps the session", ns.Recorder.current().xp == sxp0 + 600 and ns.Recorder.current().fights ~= nil)
-- #14: a /reload fires PLAYER_LOGOUT first; the save file then has the session ended, and the reload reopens it
local sid14 = ns.DB.active
M.fire("PLAYER_LOGOUT")
check("logout writes the end into the save file", ns.DB.sessions[sid14].endedEpoch ~= nil and ns.DB.active == sid14)
M.fire("PLAYER_ENTERING_WORLD", false, true)
local s14 = ns.DB.sessions[sid14]
check("a reload after its PLAYER_LOGOUT reopens the same session", ns.DB.active == sid14 and ns.Recorder.current() == s14 and s14.endedEpoch == nil and s14.xp == sxp0 + 600)
local resumes = 0; for _, r in ipairs(s14.segments or {}) do if r.kind == "RESUME" or r[2] == "RESUME" or (type(r) == "string" and r:find("RESUME")) then resumes = resumes + 1 end end
check("the reopened session carries a RESUME row", resumes >= 1, resumes)
-- a real logout followed by a real login: the old session stays ended at the logout, not marked recovered
M.fire("PLAYER_LOGOUT"); local ended14 = s14.endedEpoch
M.now = M.now + 600
M.fire("PLAYER_ENTERING_WORLD", true, false)
check("a real login keeps the logged-out session ended at its logout", s14.endedEpoch == ended14 and not s14.recovered and ns.DB.active ~= sid14 and ns.Recorder.current() ~= s14)
-- ── corpse run: downtime stamped on the death row ──
M.fire("PLAYER_DEAD"); M.now = M.now + 95; M.dead = false; M.fire("PLAYER_UNGHOST")
local lastDeath; for i = #ns.DB.story.events, 1, -1 do if ns.DB.story.events[i].kind == "DEATH" then lastDeath = ns.DB.story.events[i]; break end end
check("death row carries the corpse-run downtime", lastDeath and lastDeath.downtime == 95, lastDeath and lastDeath.downtime)
-- ── text search on Timeline and Loot ──
check("event search matches text", ns._test.eventMatches({ kind = "KILL", text = "Kobold Vermin down!" }, "all", "kobold"))
check("event search matches zone", ns._test.eventMatches({ kind = "ZONE", text = "x", zone = "Westfall" }, "all", "westf"))
check("event search rejects non-matching", not ns._test.eventMatches({ kind = "KILL", text = "Kobold Vermin down!" }, "all", "murloc"))
check("event search still respects the filter tab", not ns._test.eventMatches({ kind = "LOOT", text = "Kobold" }, "combat", "kobold"))
M.tick()
check("loot search matches item", ns._test.lootMatches({ item = "Linen Cloth", src = "Kobold" }, "linen"))
check("loot search matches source", ns._test.lootMatches({ item = "Linen Cloth", src = "Auction sale" }, "auction"))
check("loot search matches coin rows", ns._test.lootMatches({ money = 120, src = "Defias Thug" }, "gold"))
check("loot search rejects non-matching", not ns._test.lootMatches({ item = "Linen Cloth", src = "Kobold" }, "wool"))
-- ── dungeon run detail: boss-by-boss attempts, deaths, notable loot ──
do
  local t0 = M.epoch + 100000
  local L, Fz = ns.DB.story.events, ns.DB.combat.fights
  L[#L + 1] = { kind = "DUNGEON", t = t0, text = "Ragefire Chasm" }
  Fz[#Fz + 1] = { outcome = "kill", startEpoch = t0 + 60, duration = 20, foes = { "Ragefire Trogg" } }                      -- trash
  Fz[#Fz + 1] = { outcome = "wipe", startEpoch = t0 + 120, duration = 45, bossName = "Taragaman the Hungerer", foes = { "Taragaman the Hungerer" } }
  L[#L + 1] = { kind = "DEATH", t = t0 + 165, text = "You died", foe = "Taragaman the Hungerer", downtime = 80 }
  Fz[#Fz + 1] = { outcome = "kill", startEpoch = t0 + 300, duration = 50, bossName = "Taragaman the Hungerer", foes = { "Taragaman the Hungerer" } }
  Fz[#Fz + 1] = { outcome = "kill", startEpoch = t0 + 420, duration = 30, bossName = "Jergosh the Invoker", foes = { "Jergosh the Invoker" } }
  ns.DB.loot.log[#ns.DB.loot.log + 1] = { t = t0 + 352, item = "Cursed Felblade", count = 1, q = "ff0070dd", src = "Taragaman the Hungerer" }
  ns.DB.loot.log[#ns.DB.loot.log + 1] = { t = t0 + 353, item = "Linen Cloth", count = 3, q = "ffffffff", src = "Taragaman the Hungerer" }
  ns.DB.loot.log[#ns.DB.loot.log + 1] = { t = t0 + 354, money = 1500, src = "Taragaman the Hungerer" }
  L[#L + 1] = { kind = "DUNGEONLEAVE", t = t0 + 600, text = "Ragefire Chasm" }
  local runs = T.buildRuns(); local run = runs[#runs]
  check("run has two bosses in pull order", run and #run.bosses == 2 and run.bosses[1].name == "Taragaman the Hungerer", run and #run.bosses)
  local tara = run and run.bosses[1]
  check("boss attempts count wipes before the kill", tara and tara.attempts == 2 and tara.wipes == 1, tara and tara.attempts)
  check("boss kill time is relative to the run start", tara and tara.killedAt == t0 + 350, tara and tara.killedAt)
  check("boss combat time sums the attempts", tara and tara.combat == 95, tara and tara.combat)
  check("trash pulls counted separately", run and run.trash == 1, run and run.trash)
  check("deaths listed with downtime", run and #run.deathRows == 1 and run.deathRows[1].downtime == 80)
  check("notable loot lists rare+ only", run and #run.notable == 1 and run.notable[1].item == "Cursed Felblade", run and #run.notable)
  check("run totals still count every item and coin", run and run.items == 2 and run.gold == 1500)
  local okR, errR = xpcall(function() return T.renderRun(run) end, debug.traceback)
  check("run detail renders bosses, deaths and loot without error", okR and #M.errors == 0, errR)
end
ns.DB.settings = ns.DB.settings or {}
-- ── loot toast threshold ──
ns.DB.settings.lootToast = nil
check("default threshold: uncommon is quiet, rare toasts", T.lootQuiet("ff1eff00") == true and T.lootQuiet("ff0070dd") == false)
ns.DB.settings.lootToast = "uncommon"
check("uncommon+ threshold toasts greens", T.lootQuiet("ff1eff00") == false and T.lootQuiet("ffffffff") == true)
ns.DB.settings.lootToast = "epic"
check("epic threshold keeps rares quiet", T.lootQuiet("ff0070dd") == true and T.lootQuiet("ffa335ee") == false)
ns.DB.settings.lootToast = "off"
check("off keeps everything quiet", T.lootQuiet("ffff8000") == true)
ns.DB.settings.lootToast = nil
-- ── disconnect-protection reminder: hidden by combat, back right after the fight ──
M.inCombat = false; M.dead = false; M.now = M.now + 1800     -- past the 30 min throttle and the settle period
T.flushTick()
local sm = T.saveModal()
check("reminder shows when safe and unsaved data exists", sm and sm:IsShown())
do  -- #16: the charcoal theme of the desktop, never the white box
  local r, g, b = sm:GetBackdropColor()
  check("reminder is charcoal, not white", r and r < 0.2 and g < 0.2 and b < 0.2, tostring(r))
  local sr, sg, sb = sm.save:GetBackdropColor()
  check("Reload & save is the mint primary button", sr and sg > 0.7 and sr < 0.2, tostring(sg))
end
M.inCombat = true; M.fire("PLAYER_REGEN_DISABLED")
check("reminder hides the moment combat starts", sm and not sm:IsShown())
M.inCombat = false; M.now = M.now + 2; M.fire("PLAYER_REGEN_ENABLED")
M.now = M.now + 3; T.flushTick()
check("reminder stays hidden during the settle period", sm and not sm:IsShown())
M.now = M.now + 10; T.flushTick()
check("interrupted reminder returns after the fight without waiting for the throttle", sm and sm:IsShown())
sm.later:GetScript("OnClick")(sm.later)
check("Later dismisses it", sm and not sm:IsShown())
M.now = M.now + 30; T.flushTick()
check("a dismissed reminder respects the throttle", sm and not sm:IsShown())
M.now = M.now + 300; T.flushTick()
check("5 min later it is still quiet (was every 4 min, #16)", sm and not sm:IsShown())
M.now = M.now + 1500; T.flushTick()
check("and comes back once the 30 min throttle elapses", sm and sm:IsShown())
sm.later:GetScript("OnClick")(sm.later)
-- ── aura scanner reuses entry tables across scans (allocation churn) ──
M.auras.player = { HELPFUL = { { name = "Blessing of Might", icon = 5, spellId = 19740, auraInstanceID = 5001 },
                               { name = "Well Fed", icon = 3, spellId = 24870, auraInstanceID = 5002 } }, HARMFUL = {} }
local scan1 = T.scanAuras("player")
local scan2 = T.scanAuras("player", scan1)
local reused = 0; for k, e in pairs(scan2) do if scan1[k] == e then reused = reused + 1 end end
check("unchanged auras keep their entry table", reused == 2, reused)
M.auras.player.HELPFUL[2] = { name = "Retribution Aura", icon = 1, spellId = 7294, auraInstanceID = 5003 }
local scan3 = T.scanAuras("player", scan2)
local kept, fresh = 0, 0; for k, e in pairs(scan3) do if scan2[k] == e then kept = kept + 1 else fresh = fresh + 1 end end
check("a new aura gets a fresh entry, the rest are reused", kept == 1 and fresh == 1, kept .. "/" .. fresh)
M.auras = {}
-- ── loot inline in the fight detail ──
do
  local f = { startEpoch = M.epoch + 200000, duration = 30, outcome = "kill", foes = { "Defias Thug" } }
  ns.DB.loot.log[#ns.DB.loot.log + 1] = { t = f.startEpoch + 10, item = "Linen Cloth", count = 2, q = "ffffffff", src = "Defias Thug" }
  ns.DB.loot.log[#ns.DB.loot.log + 1] = { t = f.startEpoch + 45, money = 340, src = "Defias Thug" }      -- looted 15s after the kill
  ns.DB.loot.log[#ns.DB.loot.log + 1] = { t = f.startEpoch + 120, item = "Wool Cloth", count = 1, q = "ffffffff", src = "Other" }
  local fl = T.fightLoot(f)
  check("fight loot includes pickups during the fight and the looting window after", #fl == 2 and fl[1].item == "Linen Cloth" and fl[2].money == 340, #fl)
  ns.DB.combat.fights[#ns.DB.combat.fights + 1] = f
  local okD, errD = pcall(ns.OpenFightDetail, f)
  check("fight detail renders its loot section", okD and #M.errors == 0, errD)
end
-- ── party deaths: a groupmate dying mid-fight is recorded with its time ──
M.units.party1 = { name = "Dave", class = "PRIEST" }; M.units.party2 = { name = "Erin", class = "MAGE" }; M.groupN = 3
M.units.target = { name = "Mosshide Gnoll", hostile = true, guid = "Creature-0-1-1-1-1234-0001" }
M.inCombat = true; M.now = M.now + 20; M.fire("PLAYER_REGEN_DISABLED")
local pf = T.currentFight()
check("group of three recorded at pull", pf and pf.group and #pf.group == 3, pf and pf.group and #pf.group)
M.now = M.now + 12; M.units.party1.dead = true; M.fire("UNIT_HEALTH", "party1")
local dave; if pf and pf.group then for _, m in ipairs(pf.group) do if m.name == "Dave" then dave = m end end end
check("groupmate death stamped with fight time", dave and dave.deadT and math.abs(dave.deadT - 12) < 0.01, dave and dave.deadT)
check("member death counted once", pf and pf.memberDeaths == 1)
M.fire("UNIT_FLAGS", "party1"); M.tick()
check("repeat events do not double count", pf and pf.memberDeaths == 1, pf and pf.memberDeaths)
M.now = M.now + 10; M.inCombat = false; M.fire("PLAYER_REGEN_ENABLED")
local spf = ns.DB.combat.fights[#ns.DB.combat.fights]
check("party death persisted on the stored fight", spf and spf.memberDeaths == 1 and spf.group[2].deadT ~= nil)
local okP, errP = pcall(ns.OpenFightDetail, spf)
check("fight detail renders the died-at tag without error", okP and #M.errors == 0, errP)
M.units.party1, M.units.party2, M.units.target = nil, nil, nil; M.groupN = 1
-- ── talent split at the pull (Classic talent tabs) ──
do
  local savedSpec = _G.GetSpecialization; _G.GetSpecialization = nil
  _G.GetNumTalentTabs = function() return 3 end
  _G.GetTalentTabInfo = function(i) local T3 = { { "Arms", 31 }, { "Fury", 20 }, { "Protection", 0 } }; return T3[i][1], nil, T3[i][2] end
  M.inCombat = true; M.now = M.now + 30; M.fire("PLAYER_REGEN_DISABLED")
  local tf = T.currentFight()
  check("talent split recorded", tf and tf.talents == "31/20/0", tf and tf.talents)
  check("spec is the tree with most points", tf and tf.spec == "Arms", tf and tf.spec)
  M.now = M.now + 5; M.inCombat = false; M.fire("PLAYER_REGEN_ENABLED")
  _G.GetSpecialization = savedSpec; _G.GetNumTalentTabs, _G.GetTalentTabInfo = nil, nil
end
-- ── day labels ──
do
  local nowT = M.epoch
  check("fmtDay today", ns.UI.fmtDay(nowT, nowT) == "Today")
  check("fmtDay yesterday", ns.UI.fmtDay(nowT - 86400, nowT) == "Yesterday")
  check("fmtDay older shows weekday and date", ns.UI.fmtDay(nowT - 5 * 86400, nowT) == date("%A, %b %d", nowT - 5 * 86400))
end
-- ── delete a single fight from its detail (two clicks) ──
do
  local victim = { uid = "test-victim-uid", startEpoch = M.epoch + 300000, duration = 9, outcome = "kill", foes = { "Test Dummy" } }
  ns.DB.combat.fights[#ns.DB.combat.fights + 1] = victim
  local before = #ns.DB.combat.fights
  ns.OpenFightDetail(victim)
  local dv = T.fightDetail()
  local click = dv.delBtn:GetScript("OnClick")
  click(dv.delBtn)
  check("first click arms the delete", #ns.DB.combat.fights == before and dv.delBtn.text:GetText() == "Confirm delete", dv.delBtn.text:GetText())
  click(dv.delBtn)
  local still = false; for _, g in ipairs(ns.DB.combat.fights) do if g.uid == "test-victim-uid" then still = true end end
  check("second click removes exactly that fight", #ns.DB.combat.fights == before - 1 and not still, #ns.DB.combat.fights)
  check("delete returns to the list", not dv:IsShown())
  M.runTimers()
end
-- ── item uses per fight: casts that are not known spells ──
do
  M.inCombat = true; M.now = M.now + 40; M.fire("PLAYER_REGEN_DISABLED")
  local uf = T.currentFight()
  M.now = M.now + 7; M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-p1", 17534)   -- potion: not in the spellbook
  M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-k1", 746)                        -- First Aid: a known spell
  M.fire("UNIT_SPELLCAST_SUCCEEDED", "party1", "cast-x", 17534)                       -- someone else's cast
  check("potion recorded as an item use with fight time", uf and uf.uses and #uf.uses == 1 and uf.uses[1].name == "Superior Healing Potion" and math.abs(uf.uses[1].t - 7) < 0.01, uf and uf.uses and #uf.uses)
  check("known spells and other units are not item uses", uf and #uf.uses == 1)
  check("item use tally persisted", ns.DB.character.itemUses and ns.DB.character.itemUses["Superior Healing Potion"] >= 1)
  M.now = M.now + 5; M.inCombat = false; M.fire("PLAYER_REGEN_ENABLED")
  local suf = ns.DB.combat.fights[#ns.DB.combat.fights]
  check("uses stored on the fight", suf and suf.uses and #suf.uses == 1 and suf.uses[1].sid == 17534)
  local okU, errU = pcall(ns.OpenFightDetail, suf)
  check("fight detail renders the items-used section and landmark", okU and #M.errors == 0, errU)
end
-- ── capture gaps the question catalog needs (#11) ──
do
  local FX = ns.Fights
  -- gear: enchant and gems from the item string
  local e1, g1 = FX.linkExtras("|cff1eff00|Hitem:2140:1897:0:0:0:0:0:0:20|h[Carving Knife]|h|r")
  check("#11 enchant read from the item link", e1 == 1897 and g1 == nil, tostring(e1))
  local e2, g2 = FX.linkExtras("|cffa335ee|Hitem:28484:2564:24027:24030::::::70|h[Bulwark]|h|r")
  check("#11 gems read from the item link, empty fields skipped", e2 == 2564 and g2 and #g2 == 2 and g2[1] == 24027 and g2[2] == 24030)
  local e3, g3 = FX.linkExtras("|cffffffff|Hitem:6948::::::::|h[Hearthstone]|h|r")
  check("#11 a plain item has neither", e3 == nil and g3 == nil)
  check("#11 a link without an item string is harmless", FX.linkExtras("[Broken]") == nil)
  local savedGear = M.gear
  M.gear = { [16] = "|cff1eff00|Hitem:2140:1897:0:0:0:0:0:0:20|h[Carving Knife]|h|r" }
  M.inCombat = true; M.now = M.now + 40; M.fire("PLAYER_REGEN_DISABLED")
  local gf = T.currentFight()
  check("#11 gear at the pull carries the enchant", gf and gf.gear.initial and gf.gear.initial[16] and gf.gear.initial[16].enchant == 1897, gf and gf.gear.initial and gf.gear.initial[16] and gf.gear.initial[16].enchant)
  -- party deaths: a member resurrected and killed again dies twice
  M.units.party1 = { name = "Dave", class = "PRIEST" }; M.groupN = 2
  M.fire("GROUP_ROSTER_UPDATE")
  M.now = M.now + 5; M.inCombat = false; M.fire("PLAYER_REGEN_ENABLED")
  M.inCombat = true; M.now = M.now + 30; M.fire("PLAYER_REGEN_DISABLED")
  local df = T.currentFight()
  M.now = M.now + 4; M.units.party1.dead = true; M.fire("UNIT_HEALTH", "party1")
  M.now = M.now + 1; M.fire("UNIT_HEALTH", "party1")
  M.now = M.now + 5; M.units.party1.dead = false; M.fire("UNIT_HEALTH", "party1")
  M.now = M.now + 6; M.units.party1.dead = true; M.fire("UNIT_HEALTH", "party1")
  local dm; if df and df.group then for _, m in ipairs(df.group) do if m.name == "Dave" then dm = m end end end
  check("#11 every party death kept with its second", dm and dm.deaths and #dm.deaths == 2 and math.abs(dm.deaths[1] - 4) < 0.01 and math.abs(dm.deaths[2] - 16) < 0.01, dm and dm.deaths and #dm.deaths)
  check("#11 deadT stays the first death", dm and math.abs((dm.deadT or -1) - 4) < 0.01)
  check("#11 member deaths count both", df and df.memberDeaths == 2, df and df.memberDeaths)
  M.now = M.now + 3; M.inCombat = false; M.fire("PLAYER_REGEN_ENABLED")
  local sdf = ns.DB.combat.fights[#ns.DB.combat.fights]
  check("#11 the dead-now working set is not saved", sdf and sdf._downNow == nil and sdf.memberDeaths == 2)
  M.units.party1 = nil; M.groupN = 1; M.gear = savedGear
  -- item uses: the client's internal effects are not item uses
  local savedInfo = _G.GetSpellInfo
  _G.GetSpellInfo = function(id) if id == 836 then return "LOGINEFFECT" end return savedInfo(id) end
  local before = ns.DB.character.itemUses and ns.DB.character.itemUses.LOGINEFFECT
  M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-login", 836)
  check("#11 LOGINEFFECT is not counted as an item use", (ns.DB.character.itemUses and ns.DB.character.itemUses.LOGINEFFECT) == before)
  _G.GetSpellInfo = savedInfo
  -- quest money: filed under quests whichever event comes first
  local g = ns.DB.loot.gold; local q0 = g.quests or 0
  M.money = GetMoney(); M.fire("PLAYER_MONEY")
  M.now = M.now + 10; M.fire("QUEST_TURNED_IN", 300, 450, 2500)
  M.money = M.money + 2500; M.fire("PLAYER_MONEY")
  check("#11 quest money after the turn-in is filed as quests", (g.quests or 0) == q0 + 2500, g.quests)
  M.now = M.now + 10; M.money = M.money + 900; M.fire("PLAYER_MONEY")
  M.fire("QUEST_TURNED_IN", 301, 300, 900)
  check("#11 quest money before the turn-in is claimed by it", (g.quests or 0) == q0 + 3400, g.quests)
  M.now = M.now + 10; M.fire("QUEST_TURNED_IN", 302, 300, 700)
  M.now = M.now + 5; M.money = M.money + 700; M.fire("PLAYER_MONEY")
  check("#11 money long after a turn-in is not the quest's", (g.quests or 0) == q0 + 3400, g.quests)
  M.now = M.now + 10; M.fire("QUEST_TURNED_IN", 304, 300, 400)
  M.money = M.money + 75; M.fire("PLAYER_MONEY")
  check("#11 a vendor sale right after a turn-in is not the quest's", (g.quests or 0) == q0 + 3400, g.quests)
  M.money = M.money + 400; M.fire("PLAYER_MONEY")
  check("#11 the reward that follows the sale still is", (g.quests or 0) == q0 + 3800, g.quests)
  M.now = M.now + 10; M.money = M.money + 50; M.fire("PLAYER_MONEY")
  M.fire("QUEST_TURNED_IN", 303, 300, 60)
  check("#11 a gain of another amount is not claimed", (g.quests or 0) == q0 + 3800, g.quests)
  ns.Emitter._questMoney, ns.Emitter._openGain = nil, nil
  -- quest reward choice: read when the panel opens, recorded when the choice is confirmed
  M.questChoices = { "Worn Shortsword", "Frayed Robe" }; M.fire("QUEST_COMPLETE")
  GetQuestReward(2)
  check("#11 the chosen reward is recorded after the panel closed", count(ns.DB.story.events, function(e) return e.kind == "REWARD" and (e.text or ""):find("Frayed Robe") ~= nil end) == 1)
  M.questChoices = { "Other Blade" }; M.fire("QUEST_COMPLETE"); GetQuestReward(0)
  check("#11 a quest without a choice records no reward", count(ns.DB.story.events, function(e) return e.kind == "REWARD" and (e.text or ""):find("Other Blade") ~= nil end) == 0)
  M.questChoices = nil; M.fire("QUEST_COMPLETE"); GetQuestReward(1)
  check("#11 a stale choice from an earlier quest is not reused", count(ns.DB.story.events, function(e) return e.kind == "REWARD" and (e.text or ""):find("Other Blade") ~= nil end) == 0)
  M.runTimers()
  -- spec and talents: a client with GetSpecialization that answers nothing falls through to the talent trees
  local sS, sI = _G.GetSpecialization, _G.GetSpecializationInfo
  _G.GetSpecialization = function() return nil end
  _G.GetNumTalentTabs = function() return 3 end
  _G.GetTalentTabInfo = function(i) local T3 = { { "Holy", 5 }, { "Protection", 0 }, { "Retribution", 12 } }; return T3[i][1], nil, T3[i][2] end
  local sp, tl = FX.specAndTalents()
  check("#11 empty specialization falls through to the trees", sp == "Retribution" and tl == "5/0/12", tostring(sp) .. " " .. tostring(tl))
  _G.GetTalentTabInfo = function(i) if i == 1 then return 161, "Arms", "", "icon", 8 end return 164, "Fury", "", "icon", 0 end
  _G.GetNumTalentTabs = function() return 2 end
  sp, tl = FX.specAndTalents()
  check("#11 id-first GetTalentTabInfo shape", sp == "Arms" and tl == "8/0", tostring(sp) .. " " .. tostring(tl))
  _G.GetTalentTabInfo = function(i) return ({ "Fire", "Frost" })[i] end
  _G.GetNumTalents = function() return 2 end
  _G.GetTalentInfo = function(tab, i) if tab == 2 then return "Talent", nil, 1, i, 3, 5 end return "Talent", nil, 1, i, 0, 5 end
  sp, tl = FX.specAndTalents()
  check("#11 points summed from talent ranks when the tab has none", sp == "Frost" and tl == "0/6", tostring(sp) .. " " .. tostring(tl))
  _G.GetTalentTabInfo = function() error("blocked") end
  local okS = pcall(FX.specAndTalents)
  check("#11 a throwing talent API does not break the pull", okS)
  _G.GetTalentTabInfo = function(i) return ({ "Holy", "Shadow" })[i], nil, 0 end
  _G.GetNumTalents, _G.GetTalentInfo = nil, nil
  sp, tl = FX.specAndTalents()
  check("#11 no points spent: no spec, split recorded", sp == nil and tl == "0/0", tostring(sp) .. " " .. tostring(tl))
  _G.GetSpecialization, _G.GetSpecializationInfo = sS, sI
  _G.GetNumTalentTabs, _G.GetTalentTabInfo = nil, nil
  sp = FX.specAndTalents()
  check("#11 mainline specialization still read", sp == "Arms", tostring(sp))
end
-- ── Progress tab builders (pure) ──
do
  local L = ns.DB.story.events; local t0 = M.epoch + 400000
  L[#L + 1] = { kind = "QUESTACCEPT", t = t0, text = "Quest:  Kobold Camp Cleanup", zone = "Elwynn Forest", sub = "Northshire", x = 0.5, y = 0.4 }
  L[#L + 1] = { kind = "QUESTACCEPT", t = t0 + 10, text = "Quest:  Investigate Echo Ridge", zone = "Elwynn Forest" }
  L[#L + 1] = { kind = "QUESTDONE", t = t0 + 300, text = "Complete:  Kobold Camp Cleanup", zone = "Elwynn Forest", sub = "Northshire", x = 0.48, y = 0.41 }
  L[#L + 1] = { kind = "REWARD", t = t0 + 301, text = "Chose:  Worn Shortsword" }
  local rows, sum = T.buildQuests()
  check("quests: completed and open counted", sum.done >= 1 and sum.open >= 1 and sum.rewards >= 1, sum.done .. "/" .. sum.open)
  local top = rows[1]
  check("quests: newest first with a status", top and top.name == "Kobold Camp Cleanup" and top.status == "done", top and top.name)
  local openRow; for _, r in ipairs(rows) do if r.name == "Investigate Echo Ridge" then openRow = r end end
  check("quests: accepted but not completed is in progress", openRow and openRow.status == "accepted")
  ns.DB.character.reputation = { ["Stormwind"] = { standing = 5, label = "Friendly" }, ["Darnassus"] = { standing = 4, label = "Neutral" }, ["Ironforge"] = { standing = 6, label = "Honored" } }
  L[#L + 1] = { kind = "REP", t = t0 + 500, text = "Ironforge:  now Honored", standing = "Honored" }
  local rr, rs = T.buildReputation()
  check("reputation: sorted best standing first", rr[1] and rr[1].name == "Ironforge" and rr[3].name == "Darnassus", rr[1] and rr[1].name)
  check("reputation: last standing gain matched to the faction", rr[1].lastUp == t0 + 500 and rs.ups >= 1)
  ns.DB.character.professions = { ["Mining"] = { rank = 78, max = 150 }, ["First Aid"] = { rank = 40, max = 75 } }
  L[#L + 1] = { kind = "PROFTIER", t = t0 + 600, text = "Skill milestone:  Mining 75" }
  L[#L + 1] = { kind = "SKILLUP", t = t0 + 610, text = "Mining 78", prof = "Mining", craft = "Copper Bar", crafted = 12 }
  L[#L + 1] = { kind = "RECIPE", t = t0 + 620, text = "New recipe:  Bronze Bar" }
  local pr, ps = T.buildProfessions()
  check("professions: highest skill first with rank/max", pr[1] and pr[1].name == "Mining" and pr[1].rank == 78 and pr[1].max == 150, pr[1] and pr[1].name)
  check("professions: milestones and skill-ups per profession", pr[1].tiers >= 1 and pr[1].skillups >= 1 and ps.recipes >= 1, pr[1].tiers .. "/" .. pr[1].skillups)
  -- a gathered skill-up has no prof field: its profession comes from the text
  L[#L + 1] = { kind = "SKILLUP", t = t0 + 630, text = "Skill up:  First Aid 41", zone = "Elwynn Forest", x = 0.41, y = 0.66 }
  L[#L + 1] = { kind = "SKILLUP", t = t0 + 640, text = "Skill up:  Swords 12" }   -- a weapon skill, not a profession
  local pr2 = T.buildProfessions()
  local fa; for _, r in ipairs(pr2) do if r.name == "First Aid" then fa = r end end
  check("professions: a skill-up without a prof field still counts", fa and fa.skillups == 1, fa and fa.skillups)
  local hist = T.buildSkillups()
  check("history: every profession skill-up newest first, weapon skills left out", #hist == 2 and hist[1].prof == "First Aid" and hist[1].rank == 41 and hist[2].prof == "Mining", #hist)
  check("history: a craft is the source, with the count", hist[2].source == "Copper Bar x12" and hist[2].rank == 78, hist[2].source)
  check("history: filtered to one profession", #T.buildSkillups("Mining") == 1 and #T.buildSkillups("Herbalism") == 0)
  -- founder 2026-09-30: nothing opens or moves in combat, so the desktop never loses the flag mid-fight
  do
    local corner0 = ns.DB.settings.emitCorner
    M.inCombat = true
    check("in combat: /eb corner does nothing", ns.Emitter.setCorner("tr") == false and ns.DB.settings.emitCorner == corner0)
    SlashCmdList.EVERBUFF("corner bl")
    check("in combat: the slash command is refused", ns.DB.settings.emitCorner == corner0)
    local sc0 = ns.DB.settings.flagScale
    ns.Emitter.setFlagScale(1.5)
    check("in combat: a size change is refused", ns.DB.settings.flagScale == sc0)
    M.inCombat = false
    check("out of combat: /eb corner works again", ns.Emitter.setCorner("tr") == true and ns.DB.settings.emitCorner == "TOPRIGHT")
    ns.Emitter.setCorner(corner0 or "TOPLEFT")
  end
  -- ADDON-2: at a cap the oldest rows of earlier sessions go first; the running session's rows only when nothing else is left
  do
    local saved = ns.DB.active
    ns.DB.active = "now-1"
    local list = {}
    for k = 1, 3 do list[#list + 1] = { t = k, s = "old-1" } end
    for k = 4, 6 do list[#list + 1] = { t = k, s = "now-1" } end
    ns.trimToCap(list, 4)
    check("cap drops earlier sessions' rows first", #list == 4 and list[1].t == 3 and list[2].t == 4 and list[4].t == 6, #list .. " rows, first t=" .. tostring(list[1] and list[1].t))
    ns.trimToCap(list, 2)
    check("cap then drops the running session's oldest rows", #list == 2 and list[1].t == 5 and list[2].t == 6, tostring(list[1] and list[1].t))
    ns.trimToCap(nil, 2)
    ns.DB.active = saved
  end
  -- every reputation gain is recorded with its source; the history merges gains and new standings
  L[#L + 1] = { kind = "QUESTDONE", t = M.epoch, text = "Complete:  Wanted: Hogger" }
  local repBefore = #(ns.DB.story.rep or {})
  M.fire("CHAT_MSG_COMBAT_FACTION_CHANGE", "Reputation with Stormwind increased by 250.")
  local g = ns.DB.story.rep and ns.DB.story.rep[#ns.DB.story.rep]
  check("reputation gain recorded with faction, amount and the quest that gave it", g and g.faction == "Stormwind" and g.amount == 250 and g.src == "Quest: Wanted: Hogger", g and tostring(g.src))
  M.fire("CHAT_MSG_COMBAT_FACTION_CHANGE", "You are exalted with nobody.")
  check("an unrelated faction line records nothing", #ns.DB.story.rep == repBefore + 1)
  local rh = T.buildRepHistory()
  local sw; for _, r in ipairs(rh) do if r.faction == "Stormwind" and r.change == "+250" then sw = r end end
  local sorted = true; for i = 2, #rh do if rh[i].t > rh[i - 1].t then sorted = false end end
  check("reputation history: gains and new standings, newest first", #rh >= 2 and sw ~= nil and sorted, #rh)
  check("reputation history: filtered to one faction", #T.buildRepHistory("Ironforge") == 1 and T.buildRepHistory("Ironforge")[1].change == "Now Honored")
  ns.UI.Open("Character", "reputation"); M.tick()
  local rp = host("Character").paneByKey.reputation
  check("Reputation pane with its history builds and renders cleanly", rp and rp.built and rp.buildError == nil and rp.showError == nil, rp and (rp.buildError or rp.showError))
  ns.UI.Open("Character", "professions"); M.tick()
  local chr = host("Character")
  local pp = chr and chr.paneByKey.professions
  check("Professions pane with its history builds and renders cleanly", pp and pp.built and pp.buildError == nil and pp.showError == nil, pp and (pp.buildError or pp.showError))
  check("timeline: the Professions filter", T.eventMatches({ kind = "SKILLUP" }, "professions") and T.eventMatches({ kind = "RECIPE" }, "professions") and not T.eventMatches({ kind = "LOOT" }, "professions"))
  ns.UI.Open("Home"); M.tick()
  local home = host("Home")
  check("Home built and refreshed cleanly", home and home.buildError == nil and home.showError == nil, home and (home.buildError or home.showError))
  local ov = home.paneByKey.overview
  check("Home opens on Overview with the cards in the pane", home.ctl.active == "overview" and ov.content.cLevel and ov.content.cLevel:GetParent() == ov.content)
  ns.UI.Open("Loot", "gold")
  local gold = host("Loot").paneByKey.gold
  check("Loot / Gold pane renders the economy cards", host("Loot").ctl.active == "gold" and gold.content.cBalance and gold.content.cBalance.value:GetText() ~= nil)
  ns.UI.Open("Home")
  ov.content.cXP:GetScript("OnMouseUp")(ov.content.cXP)
  check("clicking the XP card opens Character / Quests", host("Character").ctl.active == "quests" and host("Character").paneByKey.quests.built)
  ns.UI.Open("Home", "sessions")
  local srows = T.sessionRows()
  check("Sessions pane lists the current session first", #srows >= 1 and srows[1].id == ns.DB.active, srows[1] and srows[1].id)
  check("every host has an active pane after build", (function() for _, tb in ipairs(T.tabs) do if tb.host and tb.built and (not tb.ctl or tb.ctl.active == nil) then return false end end return true end)())
  local okS, errS = pcall(function() for _, k in ipairs({ "reputation", "professions", "quests" }) do ns.UI.Open("Character", k) end end)
  check("Character panes render without error", okS and #M.errors == 0 and #ns.UI.paneErrors() == 0, errS or table.concat(ns.UI.paneErrors(), " || "))
  ns.UI.Open("Home", "overview")
end
-- ── pushed items: quest items from world objects, kills and turn-ins get a real source ──
do
  M.now = M.now + 60                                                    -- any loot window is long gone
  M.fire("UNIT_SPELLCAST_SENT", "player", "Kobold Cage", "cast-o1", 3365)   -- clicked a world object
  M.fire("CHAT_MSG_LOOT", "You receive item: |cffffffff|Hitem:5075::::::::1:::::::|h[Cage Key]|h|r.")
  local key = ns.DB.loot.log[#ns.DB.loot.log]
  check("quest item from a world object is sourced to that object", key and key.item == "Cage Key" and key.src == "Kobold Cage", key and key.src)
  check("quest items are flagged", key and key.quest == true)
  M.now = M.now + 30

-- ── secret foe name (0.9.1 dungeon error: Emitter.lua:363 compare on a secret string) ──
do
  M.secrets["Bruuz"] = true
  check("safeStr refuses a value the client marks secret", T.safeStr("Bruuz") == nil)
  check("safeStr keeps a plain string", T.safeStr("Defias Trapper") == "Defias Trapper")
  check("plainNum refuses a secret number", (function() M.secrets[4242] = true; local r = T.plainNum(4242); M.secrets[4242] = nil; return r end)() == nil)
  local before = #ns.DB.story.events
  local ok, err = pcall(ns.Emitter.event, "KILL", { name = "Bruuz" }, false)
  check("KILL with a secret name does not error", ok, err)
  local last = ns.DB.story.events[#ns.DB.story.events]
  check("KILL with a secret name is recorded as an enemy", #ns.DB.story.events == before + 1 and last and last.text == "an enemy down!", last and last.text)
  M.secrets["Bruuz"] = nil
end

  ns.Emitter.event("KILL", { name = "Defias Trapper" }, true)
  M.fire("CHAT_MSG_LOOT", "You receive item: |cffffffff|Hitem:1234::::::::1:::::::|h[Red Leather Bandana]|h|r.")
  local drop = ns.DB.loot.log[#ns.DB.loot.log]
  check("item pushed right after a kill is sourced to the mob", drop and drop.src == "Defias Trapper" and not drop.quest, drop and drop.src)
  M.now = M.now + 30
  M.fire("QUEST_TURNED_IN", 200, 100, 0)
  M.fire("CHAT_MSG_LOOT", "You receive item: |cff1eff00|Hitem:2222::::::::1:::::::|h[Sturdy Belt]|h|r.")
  local rew = ns.DB.loot.log[#ns.DB.loot.log]
  check("item pushed at a turn-in is a quest reward", rew and rew.src == "Quest reward", rew and rew.src)
  M.now = M.now + 30
  M.fire("CHAT_MSG_LOOT", "You receive item: |cffffffff|Hitem:3333::::::::1:::::::|h[Mystery Egg]|h|r.")
  local egg = ns.DB.loot.log[#ns.DB.loot.log]
  check("item with nothing recent is 'Picked up', never blank", egg and egg.src == "Picked up", egg and egg.src)
  check("a loot window still attributes to the corpse", (function()
    M.units.target = { name = "Kobold Miner", dead = true, hostile = true, guid = "Creature-0-1-1-1-6-0009" }
    M.fire("LOOT_OPENED")
    M.fire("CHAT_MSG_LOOT", "You receive loot: |cffffffff|Hitem:2589::::::::1:::::::|h[Linen Cloth]|h|r.")
    local l = ns.DB.loot.log[#ns.DB.loot.log]; M.units.target = nil
    return l and l.src == "Kobold Miner" end)())
end
-- ── loot rows: item id, tooltip on hover, shift-click chat link ──
do
  M.now = M.now + 60
  M.fire("CHAT_MSG_LOOT", "You receive item: |cff0070dd|Hitem:7777::::::::1:::::::|h[Shiny Dagger]|h|r.")
  local e = ns.DB.loot.log[#ns.DB.loot.log]
  check("loot row stores the item id", e and e.id == 7777, e and e.id)
  ns.UI.Open("Loot", "items"); M.tick()
  local items = host("Loot").paneByKey.items
  local rows = items.content and items.content.lootRows
  local top
  if rows then for _, r in ipairs(rows) do if r.shown ~= false and r.itemId == 7777 then top = r end end end
  check("the newest row carries the item id for its tooltip", top ~= nil)
  if top then
    top:GetScript("OnEnter")(top); top:GetScript("OnLeave")(top)
    M.shift = true; top:GetScript("OnClick")(top); M.shift = false
    check("shift-click inserts the item link into chat", M.inserted and M.inserted:find("Hitem:7777") ~= nil, M.inserted)
  end
end
-- ── toast bursts: dedupe, throttle, priority ──
do
  M.now = M.now + 100
  local q0 = T.toastQueue(); for i = #q0, 1, -1 do q0[i] = nil end   -- leftovers from earlier tests (no OnUpdate in the stub)
  ns.DB.settings.flagMute = nil                                       -- travel was muted by an earlier test
  ns.Emitter.event("QUESTDONE", { name = "Warm Up" })            -- shows now, channel busy for SHOW_SECS
  check("toast channel busy after a toast", T.toastBusy())
  for i = 1, 6 do ns.Emitter.event("ZONE", { zone = "Same Zone" }) end
  local q = T.toastQueue()
  local zones = 0; for _, it in ipairs(q) do if it.kind == "ZONE" then zones = zones + 1 end end
  check("identical lines are queued once", zones == 1, zones)
  for i = 1, 6 do ns.Emitter.event("QUESTACCEPT", { name = "Quest " .. i }) end
  local qa = 0; for _, it in ipairs(q) do if it.kind == "QUESTACCEPT" then qa = qa + 1 end end
  check("a kind is queued at most three times", qa == 3, qa)
  ns.Emitter.event("DEATH", {})
  check("a death jumps the queue", q[1] and q[1].kind == "DEATH", q[1] and q[1].kind)
  M.now = M.now + 60; M.fire("PLAYER_ALIVE")   -- drain state for later tests
  for i = #q, 1, -1 do q[i] = nil end
end
-- ── flag size, and the flag is always shown (desktop #90) ──
do
  local fl = T.flagFrame()
  ns.Emitter.setFlagScale(1.25)
  check("flag scale persisted and stepped", ns.DB.settings.flagScale == 1.25, ns.DB.settings.flagScale)
  ns.Emitter.setFlagScale(0.7)
  check("flag never smaller than 100% (smaller was never proven readable)", ns.DB.settings.flagScale == 1, ns.DB.settings.flagScale)
  ns.Emitter.setFlagScale(3)
  check("flag never larger than 150%", ns.DB.settings.flagScale == 1.5, ns.DB.settings.flagScale)
  check("no way to hide the flag or fade it", ns.Emitter.setFlagHidden == nil and ns.Emitter.flagHidden == nil and ns.Emitter.setFlagAlpha == nil)
  -- a save from an older version that had it hidden at 30 %: shown, at full opacity, and the old keys dropped
  ns.DB.settings.flagHidden, ns.DB.settings.flagAlpha = true, 0.3
  ns.Emitter.applyFlagPrefs()
  check("an old hidden flag comes back", fl.shown == true and ns.DB.settings.flagHidden == nil and ns.DB.settings.flagAlpha == nil)
  M.now = M.now + 100
  local q0 = T.toastQueue(); for i = #q0, 1, -1 do q0[i] = nil end
  ns.Emitter.event("LEVELUP", {})
  check("a notification shows and the event is recorded", T.toastBusy() and ns.DB.story.events[#ns.DB.story.events].kind == "LEVELUP")
  ns.Emitter.setFlagScale(1)
end
-- ── Loot "By item" aggregation ──
do
  local log = {
    { t = 1, item = "Linen Cloth", count = 3, q = "ffffffff", src = "Kobold Miner" },
    { t = 2, item = "Linen Cloth", count = 2, q = "ffffffff", src = "Kobold Miner" },
    { t = 3, item = "Linen Cloth", count = 1, q = "ffffffff", src = "Defias Thug" },
    { t = 4, item = "Shiny Dagger", count = 1, q = "ff0070dd", src = "Defias Thug", id = 7777 },
    { t = 5, money = 120, src = "Kobold Miner" },
  }
  local agg = ns._test.lootAggregate(log, "", function() return true end)
  check("aggregation: one row per item, coin excluded, most quantity first", #agg == 2 and agg[1].item == "Linen Cloth" and agg[1].count == 6 and agg[1].drops == 3, agg[1] and agg[1].count)
  check("aggregation: most frequent source with drop count", agg[1].src == "Kobold Miner  ·  3 drops", agg[1].src)
  check("aggregation keeps id and quality for tooltips and color", agg[2].id == 7777 and agg[2].q == "ff0070dd")
  ns.UI.Open("Loot", "items"); M.tick()
  local items = host("Loot").paneByKey.items
  check("Items pane starts in newest mode", items.content.lootMode() == "newest")
end
-- ── resizable window: size persisted and clamped ──
ns.UI.SetWindowSize(1100, 700)
check("window size persisted", ns.DB.settings.winSize and ns.DB.settings.winSize.w == 1100 and ns.DB.settings.winSize.h == 700)
ns.UI.SetWindowSize(600, 300)
check("window never shrinks below the designed minimum", ns.DB.settings.winSize.w == 900 and ns.DB.settings.winSize.h == 580)
-- ── Fights row tooltip runs without error ──
do
  local fl = T.fightsList()
  local anyRow; if fl and fl.rows then for _, r in ipairs(fl.rows) do if r.fight then anyRow = r end end end
  if anyRow then
    local okH, errH = pcall(function() anyRow:GetScript("OnEnter")(anyRow); anyRow:GetScript("OnLeave")(anyRow) end)
    check("fight row hover tooltip renders", okH, errH)
  end
end
-- ── fight detail -> Timeline window ──
do
  local f = { uid = "tl-win", startEpoch = M.epoch + 500000, duration = 30, outcome = "kill", foes = { "Windowed Mob" } }
  ns.DB.combat.fights[#ns.DB.combat.fights + 1] = f
  local L = ns.DB.story.events
  L[#L + 1] = { kind = "KILL", t = f.startEpoch + 10, text = "Windowed Mob down!", s = ns.DB.active }
  L[#L + 1] = { kind = "ZONE", t = f.startEpoch + 3600, text = "Far Away Later", s = ns.DB.active }
  ns.OpenFightDetail(f)
  local dv = T.fightDetail()
  dv.tlBtn:GetScript("OnClick")(dv.tlBtn)
  local w = ns._test.timelineWindow()
  check("Timeline button opens Home / Timeline with the fight's window", host("Home").ctl.active == "timeline" and w and w.t0 == f.startEpoch - 5 and w.t1 == f.startEpoch + 50, w and w.t0)
  local tl = host("Home").paneByKey.timeline
  check("window banner shown", tl.content.timelineBanner.shown == true)
  check("events outside the window are filtered out", ns._test.eventMatches(L[#L], "all", "") == false and ns._test.eventMatches(L[#L - 1], "all", "") == true)
  tl.content.timelineBanner:GetScript("OnClick")(tl.content.timelineBanner)
  check("clicking the banner clears the window", ns._test.timelineWindow() == nil and ns._test.eventMatches(L[#L], "all", "") == true)
  ns.UI.Open("Home", "overview")
end
-- ── durability lost across a death ──
do
  M.dur = { [1] = { 100, 100 }, [5] = { 100, 100 } }; M.fire("UPDATE_INVENTORY_DURABILITY")
  check("durability at 100% before dying", ns.DB.character.durability.pct == 100)
  M.fire("PLAYER_DEAD"); M.now = M.now + 40
  M.dur = { [1] = { 90, 100 }, [5] = { 90, 100 } }          -- spirit healer took 10%
  M.dead = false; M.fire("PLAYER_UNGHOST")
  local lastDeath; for i = #ns.DB.story.events, 1, -1 do if ns.DB.story.events[i].kind == "DEATH" then lastDeath = ns.DB.story.events[i]; break end end
  check("death row carries the durability lost", lastDeath and lastDeath.durLoss == 10, lastDeath and lastDeath.durLoss)
  local deaths = T.collectDeaths()
  check("Deaths view sees the loss", deaths[#deaths] and deaths[#deaths].durLoss == 10)
  M.dur = {}
end
-- ── instance lockouts ──
do
  M.saved = { { name = "Blackfathom Deeps", reset = 90000, bosses = 6, down = 4 }, { name = "Molten Core", raid = true, players = 40, reset = 3000, locked = false } }
  M.fire("UPDATE_INSTANCE_INFO")
  local L = ns.DB.character.lockouts
  check("locked instances captured with reset time and boss progress", L and #L == 1 and L[1].name == "Blackfathom Deeps" and L[1].down == 4 and L[1].bosses == 6 and L[1].resetAt == M.epoch + 90000, L and #L)
  ns.UI.Open("Combat", "dungeons"); M.tick()
  local dg = host("Combat").paneByKey.dungeons
  local txt = T.dungeonsLockText and T.dungeonsLockText() or ""
  check("Dungeons pane shows the lockout with time to reset", txt:find("Blackfathom Deeps 4/6") ~= nil and txt:find("resets in 1d 1h") ~= nil, txt)
  M.saved = {}
end
-- ── retail trait string ──
do
  _G.C_ClassTalents = { GetActiveConfigID = function() return 77 end }
  _G.C_Traits = { GenerateImportString = function(cfg) return cfg == 77 and "BwQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" or nil end }
  M.inCombat = true; M.now = M.now + 30; M.fire("PLAYER_REGEN_DISABLED")
  local tf = T.currentFight()
  check("retail build stored as the game's import string", tf and tf.talents and tf.talents:sub(1, 3) == "BwQ", tf and tf.talents)
  M.now = M.now + 3; M.inCombat = false; M.fire("PLAYER_REGEN_ENABLED")
  -- WoW Forever 1.60.1: no global GetSpecialization, no talent tabs; C_SpecializationInfo and the trait loadout instead
  local gS, gI = _G.GetSpecialization, _G.GetSpecializationInfo
  _G.GetSpecialization, _G.GetSpecializationInfo = nil, nil
  _G.C_SpecializationInfo = { GetSpecialization = function() return 3 end,
    GetSpecializationInfo = function(i) return i == 3 and 70 or nil, i == 3 and "Retribution" or nil end }
  M.inCombat = true; M.now = M.now + 30; M.fire("PLAYER_REGEN_DISABLED")
  M.now = M.now + 3; M.inCombat = false; M.fire("PLAYER_REGEN_ENABLED")
  local ff = ns.DB.combat.fights[#ns.DB.combat.fights]
  check("Forever: spec read from C_SpecializationInfo", ff and ff.spec == "Retribution", ff and tostring(ff.spec))
  check("Forever: talents are the loadout import string", ff and ff.talents and ff.talents:sub(1, 3) == "BwQ", ff and tostring(ff.talents))
  _G.C_SpecializationInfo.GetSpecialization = function() return 0 end   -- no spec chosen yet
  local sp, tl = ns.Fights.specAndTalents()
  check("Forever: no spec chosen still records the loadout", sp == nil and tl and tl:sub(1, 3) == "BwQ", tostring(sp) .. " " .. tostring(tl))
  _G.C_SpecializationInfo.GetSpecialization = function() error("blocked") end
  check("Forever: a throwing specialization API does not break the pull", (pcall(ns.Fights.specAndTalents)))
  _G.C_SpecializationInfo = nil
  _G.GetSpecialization, _G.GetSpecializationInfo = gS, gI
  _G.C_ClassTalents, _G.C_Traits = nil, nil
end
-- ── #18: a fight still running at /reload or logout is stored, not lost ──
do
  local n0, sid = #ns.DB.combat.fights, ns.DB.active
  M.units.target = { name = "Deepmoss Venomspitter", hostile = true, guid = "Creature-0-1-1-1-4263-000C", cls = "normal" }
  M.inCombat = true; M.now = M.now + 30; M.fire("PLAYER_REGEN_DISABLED"); M.fire("PLAYER_TARGET_CHANGED")
  M.now = M.now + 4
  M.fire("PLAYER_LOGOUT")                                      -- the /reload's PLAYER_LOGOUT, combat still on
  local cut = ns.DB.combat.fights[#ns.DB.combat.fights]
  check("#18 the running fight is stored at PLAYER_LOGOUT", #ns.DB.combat.fights == n0 + 1 and T.currentFight() == nil, #ns.DB.combat.fights - n0)
  check("#18 it says it was interrupted and keeps its session and foes", cut and cut.interrupted == "logout" and cut.session == sid and cut.foes[1] == "Deepmoss Venomspitter" and cut.uid ~= nil, cut and tostring(cut.interrupted))
  check("#18 an interrupted fight claims no outcome it does not know", cut and cut.outcome == nil and cut.duration and cut.duration >= 4, cut and tostring(cut.outcome))
  M.fire("PLAYER_ENTERING_WORLD", false, true)                -- the reload comes back
  M.fire("PLAYER_REGEN_ENABLED"); M.inCombat = false            -- combat ends after the reload: nothing half-made is stored
  check("#18 the end of combat after the reload stores nothing extra", #ns.DB.combat.fights == n0 + 1, #ns.DB.combat.fights - n0)
  -- a death already known before the logout keeps its outcome
  M.inCombat = true; M.now = M.now + 30; M.fire("PLAYER_REGEN_DISABLED"); M.fire("PLAYER_DEAD")
  M.fire("PLAYER_LOGOUT")
  local died = ns.DB.combat.fights[#ns.DB.combat.fights]
  check("#18 a known death survives the interruption", died and died.outcome == "death" and died.interrupted == "logout", died and tostring(died.outcome))
  M.fire("PLAYER_ENTERING_WORLD", false, true); M.inCombat = false; M.dead = false; M.fire("PLAYER_ALIVE")
  M.units.target = nil
end
-- ── Loot quality filter + sortable columns ──
do
  ns.UI.Open("Loot", "items"); M.tick()
  local items = host("Loot").paneByKey.items
  local minQ = items.content.lootFilter()
  check("quality filter starts at All", minQ == 0)
  local rows = {
    { t = 1, item = "Wool Cloth", count = 4, q = "ffffffff", src = "Zed" },
    { t = 2, item = "Blue Sword", count = 1, q = "ff0070dd", src = "Abe" },
    { t = 3, item = "Green Belt", count = 2, q = "ff1eff00", src = "Moe" },
    { t = 4, money = 500, src = "Abe" },
  }
  local byQty = ns._test.lootSort({ unpack(rows) }, "qty", false)
  check("sort by quantity descending", byQty[1].item == "Wool Cloth" and byQty[2].item == "Green Belt", byQty[1].item)
  local byFrom = ns._test.lootSort({ unpack(rows) }, "from", true)
  check("sort by source ascending", byFrom[1].src == "Abe" and byFrom[#byFrom].src == "Zed", byFrom[1].src)
  local byQ = ns._test.lootSort({ unpack(rows) }, "quality", false)
  check("sort by quality puts the rare first", byQ[1].item == "Blue Sword", byQ[1].item)
end
-- ── onboarding card ──
do
  ns.UI.Open("Home", "overview"); M.tick()
  local ov = host("Home").paneByKey.overview.content
  check("onboarding card shows on a fresh install", ov.onboard and ov.onboard:IsShown() and not ns.DB.settings.onboarded)
  ov.onboard.okBtn:GetScript("OnClick")(ov.onboard.okBtn)
  check("Got it dismisses the card for good", ns.DB.settings.onboarded == true and not ov.onboard:IsShown())
end
-- ── flag free-drag position ──
do
  ns.Emitter.setFlagPos("TOPRIGHT", -120, -80)
  check("dragged flag position persisted", ns.DB.settings.flagPos and ns.DB.settings.flagPos.point == "TOPRIGHT" and ns.DB.settings.flagPos.x == -120)
  ns.Emitter.setCorner("TOPLEFT")
  check("choosing a corner ends free placement", ns.DB.settings.flagPos == nil and ns.DB.settings.emitCorner == "TOPLEFT")
end
-- ── per-session bar strips ──
do
  local rows = { { startedEpoch = 300, xp = 900, gained = 100, spent = 400 }, { startedEpoch = 200, xp = 300, gained = 500, spent = 0, endedEpoch = 250 }, { startedEpoch = 100, xp = 0, gained = 0, spent = 0, endedEpoch = 150 } }
  local xpv = ns._test.stripValues(rows, "xp")
  check("XP strip is oldest-left with the live session last", #xpv == 3 and xpv[1].v == 0 and xpv[3].v == 900 and xpv[3].live == true)
  local gv = ns._test.stripValues(rows, nil, true)
  check("gold strip is signed net per session", gv[2].v == 500 and gv[3].v == -300, gv[3].v)
  ns.UI.Open("Home", "sessions"); M.tick()
  local sp = host("Home").paneByKey.sessions
  check("Sessions pane renders both strips", sp.content.xpStrip and sp.content.goldStrip and #ns.UI.paneErrors() == 0, table.concat(ns.UI.paneErrors(), " || "))
end
-- ── run headers in the Fights list ──
do
  local t0 = M.epoch + 700000
  local L = ns.DB.story.events
  L[#L + 1] = { kind = "DUNGEON", t = t0, text = "Wailing Caverns", s = ns.DB.active }
  ns.DB.combat.fights[#ns.DB.combat.fights + 1] = { uid = "wc-1", startEpoch = t0 + 60, duration = 20, outcome = "kill", bossName = "Lady Anacondra", foes = { "Lady Anacondra" } }
  L[#L + 1] = { kind = "DUNGEONLEAVE", t = t0 + 600, text = "Wailing Caverns", s = ns.DB.active }
  local dv = T.fightDetail(); if dv then dv:Hide() end          -- an earlier test left the replay open; the list only rebuilds when visible
  local fl = T.fightsList(); fl:Show()
  ns.UI.Open("Combat", "fights"); M.tick()
  local found = false
  for _, d in ipairs((fl.daysFn and fl.daysFn()) or {}) do if d.shown ~= false and d.text and tostring(d.text):find("Wailing Caverns") then found = true end end
  local diag = {}
  for _, r in ipairs(ns.DungeonRuns()) do if r.name == "Wailing Caverns" then diag[#diag + 1] = ("run %s..%s fights=%d"):format(tostring(r.startT), tostring(r.endT), #(r.fights or {})) end end
  diag[#diag + 1] = "days=" .. tostring(fl.daysFn and #(fl.daysFn() or {}))
  for _, d in ipairs((fl.daysFn and fl.daysFn()) or {}) do if d.shown ~= false then diag[#diag + 1] = tostring(d.text) end end
  diag[#diag + 1] = "listShown=" .. tostring(fl.shown) .. " rows=" .. tostring(#(fl.rows or {}))
  check("Fights list shows a run header for fights inside a dungeon run", found, table.concat(diag, " | "))
end
-- ── ack channel: companion file + paste code ──
do
  -- isolated tables: the through epoch must not sweep the fixtures of earlier tests
  local keepF, keepL, keepE, keepS = ns.DB.combat.fights, ns.DB.loot.log, ns.DB.story.events, ns.DB.sessions
  ns.DB.combat.fights, ns.DB.loot.log, ns.DB.story.events = {}, {}, {}
  ns.DB.sessions = { [ns.DB.active] = keepS[ns.DB.active] }
  local F = ns.DB.combat.fights
  local base = M.epoch + 900000
  F[#F + 1] = { uid = "ack-old", id = 9001, startEpoch = base, duration = 5, outcome = "kill", foes = { "A" } }
  F[#F + 1] = { uid = "ack-mid", id = 9002, startEpoch = base + 100, duration = 5, outcome = "kill", foes = { "B" } }
  F[#F + 1] = { uid = "ack-new", id = 9003, startEpoch = base + 1000, duration = 5, outcome = "kill", foes = { "C" } }
  ns.DB.loot.log[#ns.DB.loot.log + 1] = { t = base + 50, item = "Acked Cloth", count = 1, q = "ffffffff", src = "A" }
  ns.DB.loot.log[#ns.DB.loot.log + 1] = { t = base + 2000, item = "Kept Cloth", count = 1, q = "ffffffff", src = "C" }
  ns.DB.sessions["old-session"] = { id = "old-session", startedEpoch = base - 500, endedEpoch = base + 10, segments = {} }
  local ackFile = { uids = { ["ack-mid"] = true }, through = base + 60 }
  local marked, removed = ns.applyAck(ackFile, "file")
  local function has(uid) for _, f in ipairs(F) do if f.uid == uid then return true end end return false end
  check("ack marks by uid and by through, then prunes", marked == 2 and removed == 2 and not has("ack-old") and not has("ack-mid") and has("ack-new"), marked .. "/" .. removed)
  local keptLoot, prunedLoot = false, true
  for _, l in ipairs(ns.DB.loot.log) do if l.item == "Kept Cloth" then keptLoot = true elseif l.item == "Acked Cloth" then prunedLoot = false end end
  check("loot at or before through is pruned, later loot kept", keptLoot and prunedLoot)
  check("finished sessions before through are pruned, the live one stays", ns.DB.sessions["old-session"] == nil and ns.DB.sessions[ns.DB.active] ~= nil)
  check("companion file is consumed", next(ackFile.uids) == nil and ackFile.applied ~= nil)
  check("lastAck recorded", ns.DB.combat.lastAck and ns.DB.combat.lastAck.fights == 2 and ns.DB.combat.lastAck.source == "file")
  local code = ns.parseAckCode("  EB-ACK-" .. (base + 1500) .. ":ack-new,other-uid  ")
  check("paste code parses through and uids", code and code.through == base + 1500 and code.uids["ack-new"] and code.uids["other-uid"])
  check("garbage is not a code", ns.parseAckCode("hello") == nil and ns.parseAckCode("") == nil)
  local m2 = ns.applyAck(code, "paste")
  check("paste code acks the remaining fight", m2 == 1 and not has("ack-new") and ns.DB.combat.lastAck.source == "paste")
  ns.UI.Open("Settings"); M.tick()
  local st = host and nil
  local settingsTab; for _, tab in ipairs(T.tabs) do if tab.name == "Settings" then settingsTab = tab end end
  local dataPane = settingsTab.content.subtabs.panes.data
  check("Settings > Data has the sync box", settingsTab.content.ackBox ~= nil and settingsTab.content.ackBtn ~= nil)
  settingsTab.content.ackBox:SetText("not a code"); settingsTab.content.ackBtn:GetScript("OnClick")(settingsTab.content.ackBtn)
  check("a bad code does not crash and leaves data alone", #M.errors == 0 and ns.DB.combat.lastAck.source == "paste")
  ns.DB.combat.fights, ns.DB.loot.log, ns.DB.story.events, ns.DB.sessions = keepF, keepL, keepE, keepS
end
-- ── the desktop's EverbuffAck.lua, byte for byte as everbuff-desktop ack::render writes it (desktop #38) ──
do
  local keepF, keepL, keepE, keepS = ns.DB.combat.fights, ns.DB.loot.log, ns.DB.story.events, ns.DB.sessions
  ns.DB.combat.fights, ns.DB.loot.log, ns.DB.story.events = {}, {}, {}
  ns.DB.sessions = { [ns.DB.active] = keepS[ns.DB.active] }
  local F = ns.DB.combat.fights
  local base = M.epoch + 950000
  F[#F + 1] = { uid = "Hart-Classic Beta PvE-" .. base .. "-a1b2", id = 9101, startEpoch = base + 500, duration = 5, outcome = "kill", foes = { "A" } }
  F[#F + 1] = { uid = "Hart-Classic Beta PvE-" .. (base + 900) .. "-c3d4", id = 9102, startEpoch = base + 900, duration = 5, outcome = "kill", foes = { "B" } }
  local text = "\nEverbuffAck = {\n[\"uids\"] = {\n[\"Hart-Classic Beta PvE-" .. base .. "-a1b2\"] = true,\n},\n[\"through\"] = " .. (base + 100) .. ",\n}\n"
  local chunk = assert((loadstring or load)(text))
  local env = {}
  if setfenv then setfenv(chunk, env) end
  chunk()
  local ack = (setfenv and env or _G).EverbuffAck
  check("the desktop's ack file loads as the EverbuffAck table", type(ack) == "table" and ack.through == base + 100 and ack.uids["Hart-Classic Beta PvE-" .. base .. "-a1b2"] == true)
  local marked = ns.applyAck(ack, "file")
  local function has(n) for _, f in ipairs(F) do if f.id == n then return true end end return false end
  check("an acked uid with spaces in the realm prunes its fight, the later unacked one stays", marked == 1 and not has(9101) and has(9102), tostring(marked))
  check("the file is stamped applied, which the desktop reads to drop its pending ack", type(ack.applied) == "number" and next(ack.uids) == nil)
  ns.DB.combat.fights, ns.DB.loot.log, ns.DB.story.events, ns.DB.sessions = keepF, keepL, keepE, keepS
end
-- ── death killer from the combat log (Classic) ──
do
  local ef = ns._test.emitterFrame; ef:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
  M.cleu = { 0, "SWING_DAMAGE", false, "Creature-0-1-1-1-6-0077", "Defias Pillager", 0, 0, "Player-1-000001", "Hart" }
  M.fire("COMBAT_LOG_EVENT_UNFILTERED")
  M.now = M.now + 2; M.fire("PLAYER_DEAD")
  local lastDeath; for i = #ns.DB.story.events, 1, -1 do if ns.DB.story.events[i].kind == "DEATH" then lastDeath = ns.DB.story.events[i]; break end end
  check("death names the last thing that hit us", lastDeath and lastDeath.foe == "Defias Pillager", lastDeath and lastDeath.foe)
  M.dead = false; M.fire("PLAYER_UNGHOST"); M.cleu = nil
end
-- ── the header version is the TOC version ──
do
  local toc = io.open("Everbuff/EverbuffJournal.toc"); local tv = toc and toc:read("*a"):match("## Version: (%S+)"); if toc then toc:close() end
  check("ns.VERSION comes from the TOC", tv and ns.VERSION == tv, tostring(ns.VERSION) .. " vs " .. tostring(tv))
  check("no hardcoded version string left in Lua", (function() for _, f in ipairs({ "Core", "UI", "Sync", "Debug" }) do local h = io.open("Everbuff/" .. f .. ".lua"); local src = h:read("*a"); h:close(); if src:find('ns.VERSION = "%d') then return false end end return true end)())
end
check("no errors thrown inside event handlers", #M.errors == 0, #M.errors > 0 and table.concat(M.errors, " || ") or nil)

-- ── Market.lua: crafting, recipes and the auction house (#8) ──
check("Market loaded", ns.Market ~= nil and ns.Market.craft ~= nil)
M.tradeSkillName = "Tailoring"; M.fire("TRADE_SKILL_SHOW")
M.fire("CHAT_MSG_LOOT", "You create: |cffffffff|Hitem:2996::::::::12:::::|h[Bolt of Linen Cloth]|h|rx2.")
local craft = ns.DB.character.crafts and ns.DB.character.crafts[#ns.DB.character.crafts]
check("craft row recorded with count, id and the open profession", craft and craft.item == "Bolt of Linen Cloth" and craft.count == 2 and craft.id == 2996 and craft.prof == "Tailoring", craft and craft.prof)
check("craft row carries the session id and a place", craft and craft.s == ns.DB.active and craft.zone ~= nil)
check("craft line still not logged as loot", count(ns.DB.loot.log, function(e) return e.item == "Bolt of Linen Cloth" end) == 0)
M.fire("TRADE_SKILL_CLOSE")
M.fire("CHAT_MSG_SYSTEM", "You have learned how to create a new item: Heavy Linen Bandage.")
local rec = ns.DB.character.recipes and ns.DB.character.recipes[#ns.DB.character.recipes]
check("recipe learned from the system line (Classic path)", rec and rec.name == "Heavy Linen Bandage", rec and rec.name)
-- postings through the Mainline API hooks
M.locations["loc1"] = { name = "Bolt of Linen Cloth", id = 2996, icon = 132889, count = 20 }
C_AuctionHouse.PostCommodity("loc1", 2, 20, 150)
local posted = ns.DB.loot.ah.posted[#ns.DB.loot.ah.posted]
check("commodity posting recorded with unit price, total and hours", posted and posted.item == "Bolt of Linen Cloth" and posted.count == 20 and posted.unit == 150 and posted.buyout == 3000 and posted.hours == 24, posted and posted.buyout)
M.locations["loc2"] = { name = "Cruel Barb", id = 5191, icon = 135651, count = 1 }
C_AuctionHouse.PostItem("loc2", 3, 1, 50000, 90000)
posted = ns.DB.loot.ah.posted[#ns.DB.loot.ah.posted]
check("item posting recorded with bid, buyout and 48 hours", posted and posted.item == "Cruel Barb" and posted.bid == 50000 and posted.buyout == 90000 and posted.hours == 48, posted and posted.hours)
-- purchases: a bid on an item, and a commodity purchase with the price event
C_AuctionHouse.PlaceBid(9001, 12345)
local bought = ns.DB.loot.ah.bought[#ns.DB.loot.ah.bought]
check("bid recorded with auction id and price", bought and bought.auctionId == 9001 and bought.price == 12345, bought and bought.price)
M.itemNames = { [2770] = "Copper Ore" }
C_AuctionHouse.StartCommoditiesPurchase(2770, 20); M.fire("COMMODITY_PRICE_UPDATED", 12, 240); M.fire("COMMODITY_PURCHASE_SUCCEEDED")
bought = ns.DB.loot.ah.bought[#ns.DB.loot.ah.bought]
check("commodity purchase recorded with item, count and total", bought and bought.item == "Copper Ore" and bought.count == 20 and bought.price == 240 and bought.kind == "commodity", bought and bought.price)
-- mail: a seller invoice becomes a sale with the house cut; an expired mail becomes a return; a won mail completes the bid
M.money = 6234; M.fire("PLAYER_MONEY")
M.inbox = {
  { sender = "Auction House", subject = "Auction successful: Cruel Barb", money = 85500, invoice = { "seller", "Cruel Barb", "Buyerguy", 50000, 90000, 500, 4500 } },
  { sender = "Auction House", subject = "Auction expired: Wool Cloth", money = 0, items = { { name = "Wool Cloth", id = 2592, count = 8, quality = 1 } } },
  { sender = "Auction House", subject = "Auction won: Rough Stone", money = 0, invoice = { "buyer", "Rough Stone", "Sellerguy" }, items = { { name = "Rough Stone", id = 2835, count = 5, quality = 1 } } },
}
M.fire("MAIL_SHOW")
TakeInboxMoney(1); M.money = M.money + 85500; M.fire("PLAYER_MONEY")
local sold = ns.DB.loot.ah.sold[#ns.DB.loot.ah.sold]
check("sale recorded from the seller invoice: net, buyout, deposit, house cut, buyer", sold and sold.item == "Cruel Barb" and sold.net == 85500 and sold.buyout == 90000 and sold.deposit == 500 and sold.cut == 4500 and sold.buyer == "Buyerguy", sold and sold.cut)
TakeInboxItem(2, 1)
local ret = ns.DB.loot.ah.returned[#ns.DB.loot.ah.returned]
check("expired auction recorded as a return", ret and ret.item == "Wool Cloth" and ret.count == 8 and ret.reason == "expired", ret and ret.reason)
TakeInboxItem(3, 1)
local won = ns.DB.loot.ah.bought[#ns.DB.loot.ah.bought - 1]
check("won mail completes the earlier bid with the item and seller", won and won.item == "Rough Stone" and won.seller == "Sellerguy" and won.auctionId == 9001, won and tostring(won.item))
M.fire("MAIL_CLOSED")
local arows, asum = ns.Market.buildAuctions()
check("auctions pane rows and sums", #arows >= 5 and asum.net >= 85500 and asum.cut >= 4500 and asum.spent == 12345 + 240, asum.spent)
local crows, csum = ns.Market.buildCrafts()
check("crafting pane rows and sums", #crows >= 2 and csum.crafts >= 1 and csum.recipes >= 1 and csum.byProf.Tailoring == 2, csum.crafts)
check("contract: market rows carry the session id", (function() for _, l in ipairs({ ns.DB.loot.ah.posted, ns.DB.loot.ah.bought, ns.DB.loot.ah.sold, ns.DB.loot.ah.returned, ns.DB.character.crafts, ns.DB.character.recipes }) do for _, row in ipairs(l) do if type(row.s) ~= "string" or type(row.t) ~= "number" then return false end end end return true end)())
check("no errors from the market wiring", #M.errors == 0, M.errors[1])

-- ── chat logging guardian (everbuff-business #39) ──
check("chat logging is on after world entry", M.chatLogging == true and ns.Logging._chat == true)
local calls = M.chatCalls
for _ = 1, 5 do M.tick() end
check("the chat log is not re-enabled on every tick (no chat spam)", M.chatCalls == calls, M.chatCalls - calls)
LoggingChat(false)
check("something turning the chat log off is undone at once", M.chatLogging == true and (ns.Logging.chatRepairs or 0) >= 1)

-- ── Visits.lua: town visits are play (everbuff-business #39) ──
check("Visits loaded", ns.Visits ~= nil and ns.Visits.finish ~= nil)
local function lastVisit(kind) local log = ns.DB.story.events; for i = #log, 1, -1 do if log[i].kind == kind then return log[i] end end end
local nBefore = #ns.DB.story.events
M.fire("AUCTION_HOUSE_SHOW")
check("nothing is written while the window is open", #ns.DB.story.events == nBefore)
if C_AuctionHouse.SendBrowseQuery then C_AuctionHouse.SendBrowseQuery({}) end
QueryAuctionItems("Linen"); QueryAuctionItems("Wool")
M.locations["loc3"] = { name = "Wool Cloth", id = 2592, icon = 132911, count = 20 }
C_AuctionHouse.PostItem("loc3", 1, 1, 400, 800)
C_AuctionHouse.PlaceBid(9002, 700)
M.fire("AUCTION_HOUSE_CLOSED")
local av = lastVisit("AUCTION")
local searches = C_AuctionHouse.SendBrowseQuery and 3 or 2
check("an AH visit where you look and post is one AUCTION event", av and av.searches == searches and av.posts == 1 and av.bids == 1 and av.buys == 0, av and ("%s %s %s %s"):format(av.searches, av.posts, av.bids, av.buys))
check("the visit carries the session, both times, the place and words", av and av.s == ns.DB.active and type(av.t) == "number" and av.closed >= av.t and av.zone ~= nil and av.text:find("^Auction house: ") ~= nil, av and av.text)
M.fire("AUCTION_HOUSE_SHOW"); M.fire("AUCTION_HOUSE_CLOSED")
local look = lastVisit("AUCTION")
check("a look-only visit is still recorded", look and look ~= av and look.searches == 0 and look.text == "Auction house", look and look.text)
-- mailbox: items and money taken
M.inbox = { { sender = "Friend", subject = "hi", money = 500, items = { { name = "Linen Cloth", id = 2589, count = 5, quality = 1 } } } }
M.fire("MAIL_SHOW"); TakeInboxItem(1, 1); M.money = M.money + 500; M.fire("PLAYER_MONEY"); M.fire("MAIL_CLOSED")
local mv = lastVisit("MAIL")
check("mail visit counts items and money taken", mv and mv.items == 1 and mv.money == 500, mv and ("%s %s"):format(mv.items, mv.money))
-- merchant: bought, sold, repaired
M.repairCost = 1234
M.fire("MERCHANT_SHOW"); BuyMerchantItem(1, 1); UseContainerItem(0, 1); UseContainerItem(0, 2); RepairAllItems(); M.fire("MERCHANT_CLOSED")
local vv = lastVisit("VENDOR")
check("merchant visit counts sold, bought and the repair cost", vv and vv.sold == 2 and vv.bought == 1 and vv.repair == 1234, vv and ("%s %s %s"):format(vv.sold, vv.bought, vv.repair))
BuyMerchantItem(1, 1)
check("a purchase outside a visit changes nothing", lastVisit("VENDOR") == vv and vv.bought == 1)
-- bank and trainer
M.fire("BANKFRAME_OPENED"); M.fire("BANKFRAME_CLOSED")
check("bank visit recorded", lastVisit("BANK") ~= nil and lastVisit("BANK").text == "Bank")
M.fire("TRAINER_SHOW"); BuyTrainerService(1); M.fire("TRAINER_CLOSED")
check("trainer visit counts skills learned", lastVisit("TRAINER") and lastVisit("TRAINER").learned == 1)
-- a window open at logout is closed before WoW writes the save file; a second window replaces the first
M.fire("MERCHANT_SHOW"); M.fire("MAIL_SHOW")
check("opening another window closes the first", lastVisit("VENDOR") ~= vv)
local n2 = #ns.DB.story.events
M.fire("PLAYER_LOGOUT")
check("a visit still open at logout is written", #ns.DB.story.events == n2 + 1 and ns.DB.story.events[#ns.DB.story.events].kind == "MAIL")
M.fire("PLAYER_LOGOUT")
check("nothing is written twice", #ns.DB.story.events == n2 + 1)
check("no errors from the visit wiring", #M.errors == 0, M.errors[1])
-- #15: combat logging is asserted at world entry and every 5 min, not on every 10 s tick, and a tamper is undone at once
do
  local real, enables = _G.LoggingCombat, 0
  _G.LoggingCombat = function(v) if v == true then enables = enables + 1 end return real(v) end
  M.fire("PLAYER_ENTERING_WORLD", false, false)
  local atEntry = enables
  for _ = 1, 10 do M.tick() end
  check("world entry asserts combat logging once", atEntry >= 1, atEntry)
  local afterTicks = enables
  check("ten guardian ticks add no logging header while it is on", afterTicks - atEntry <= 1, afterTicks - atEntry)
  for _ = 1, 30 do M.tick() end
  check("the 5 min safety re-check asserts it again", enables - afterTicks >= 1, enables - afterTicks)
  local before = enables
  LoggingCombat(false)
  check("something turning combat logging off is undone at once", M.logging == true and enables == before + 1, enables - before)
  _G.LoggingCombat = real
end

-- the 1.60.1.70170 update reports WoW Forever as project 18: a client with Secret Values is still recognised as one, so
-- COMBAT_LOG_EVENT_UNFILTERED is never registered (the client forbids it: "blocked from an action only available to
-- the Blizzard UI", founder 2026-10-02)
do
  local pid = _G.WOW_PROJECT_ID
  _G.WOW_PROJECT_ID = 18
  local ns2 = {}
  local ok, err = pcall(loadfile("Everbuff/Logging.lua"), "EverbuffJournal", ns2)
  check("Forever as project 18 is a client with Secret Values", ok and ns2.hasSecretValues == true and ns2.flavor == "mainline", err)
  local sv = _G.issecretvalue; _G.issecretvalue = nil
  local ns3 = {}
  pcall(loadfile("Everbuff/Logging.lua"), "EverbuffJournal", ns3)
  check("a Classic client without Secret Values stays Classic", ns3.hasSecretValues == false and ns3.flavor == "classic")
  _G.issecretvalue, _G.WOW_PROJECT_ID = sv, pid
end

-- ── L5 self-test (everbuff-business #45, approved 2026-10-02) ──
-- the list the self-test checks is generated from the source and must be current (the L1 API diff reads the same list)
do
  local gen = loadfile("tools/deps.lua")("deps")
  local list, forbidden = gen.build()
  local fh = io.open("Everbuff/Deps.lua", "rb"); local have = fh and fh:read("*a") or ""; if fh then fh:close() end
  check("deps: Everbuff/Deps.lua is current (run luajit tools/deps.lua)", have:gsub("\r\n", "\n") == gen.render(list, forbidden))
  local by = {}
  for _, d in ipairs(ns.deps or {}) do by[d[2]] = d end
  local function is(name, kind, need) local d = by[name]; return d ~= nil and d[1] == kind and d[3] == need end
  check("deps: CreateFrame is a required function", is("CreateFrame", "function", "required"))
  check("deps: C_Timer.After is a required function", is("C_Timer.After", "function", "required"))
  check("deps: GetSpellInfo is guarded (every use is tested first)", is("GetSpellInfo", "function", "guarded"))
  check("deps: GetCritChance is a guarded function (called through try)", is("GetCritChance", "function", "guarded"))
  check("deps: a hooked C_AuctionHouse.PostItem is a guarded function", is("C_AuctionHouse.PostItem", "function", "guarded"))
  check("deps: GetAddOnMetadata, the fallback after C_AddOns, is guarded", is("GetAddOnMetadata", "value", "guarded") or is("GetAddOnMetadata", "function", "guarded"))
  check("deps: ADDON_LOADED is a required event", is("ADDON_LOADED", "event", "required"))
  check("deps: an event registered through pcall is guarded", is("ACHIEVEMENT_EARNED", "event", "guarded"))
  check("deps: the addon's own SavedVariables and globals are not listed", by.EverbuffDB == nil and by.EverbuffAck == nil and by.SLASH_EVERBUFF1 == nil and by.ns == nil)
  check("deps: Lua itself is not listed", by.pairs == nil and by.string == nil and by["string.format"] == nil)
  check("deps: COMBAT_LOG_EVENT_UNFILTERED is forbidden, never a dependency",
    by.COMBAT_LOG_EVENT_UNFILTERED == nil and ns.depsForbidden and ns.depsForbidden[1] == "COMBAT_LOG_EVENT_UNFILTERED")
  local json = io.popen and io.popen("luajit tools/deps.lua --json")
  if json then
    local out = json:read("*a"); json:close()
    check("deps: --json lists the same entries for L1", select(2, out:gsub('"kind":', "")) == #ns.deps and out:find('"forbidden"', 1, true) ~= nil)
  end
end
check("contract: settings.selftest written at the first world entry", type(ns.DB.settings.selftest) == "table"
  and type(ns.DB.settings.selftest.build) == "string" and type(ns.DB.settings.selftest.at) == "number"
  and type(ns.DB.settings.selftest.ok) == "boolean" and type(ns.DB.settings.selftest.missing) == "table"
  and type(ns.DB.settings.selftest.forbidden) == "table")
do
  local ST = ns.SelfTest
  ns._test.emitterFrame:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")   -- the PARTY_KILL test above registered it on purpose
  local saved = {}
  local function setG(k, v) if saved[k] == nil then saved[k] = { v = rawget(_G, k) } end; rawset(_G, k, v) end
  -- a client that has everything the addon takes, with every event valid
  local validEvent = {}
  setG("C_EventUtils", { IsEventValid = function(e) return validEvent[e] ~= false end })
  for _, d in ipairs(ns.deps) do
    if d[1] ~= "event" and ST.resolve(d[2]) == nil then
      local parts = {}
      for p in d[2]:gmatch("[^%.]+") do parts[#parts + 1] = p end
      if #parts == 1 then setG(parts[1], d[1] == "function" and function() end or {})
      else
        local t = rawget(_G, parts[1])
        if t == nil then t = {}; setG(parts[1], t) end
        for i = 2, #parts - 1 do t[parts[i]] = t[parts[i]] or {}; t = t[parts[i]] end
        t[parts[#parts]] = d[1] == "function" and function() end or {}
      end
    end
  end
  local build = "1.60.1.70170"
  setG("GetBuildInfo", function() local v, b = build:match("^(.*)%.(%d+)$"); return v, b, "Oct 1 2026", 120105 end)
  local said = {}
  local oldMsg = ns.msg
  ns.msg = function(t) said[#said + 1] = t end
  ns.DB.settings.selftest = nil

  local r, ran = ST.run()
  check("selftest: runs at the first login on a build", ran == true)
  check("selftest: a client with everything passes", r.ok == true and #r.missing == 0 and #r.forbidden == 0, table.concat(r.missing, ",") .. " / " .. table.concat(r.forbidden, ",") .. " / " .. tostring(r.error))
  check("selftest: record carries build, interface, addon, at", r.build == "1.60.1.70170" and r.interface == 120105 and r.addon == ns.VERSION and r.at == M.epoch, tostring(r.build))
  check("selftest: events are checked when the client can say", r.events == "checked" and r.secrets == true)
  check("selftest: silent when everything passes", ST.line(r) == nil)
  local _, again = ST.run()
  check("selftest: the same build is not checked twice", again == false)

  -- a patch removes a required function and a guarded one the last build had
  build = "1.60.2.70200"
  local fade, gsi = rawget(_G, "UIFrameFadeIn"), rawget(_G, "GetSpellInfo")
  rawset(_G, "UIFrameFadeIn", nil); rawset(_G, "GetSpellInfo", nil)
  r, ran = ST.run()
  local has = {}
  for _, n in ipairs(r.missing) do has[n] = true end
  check("selftest: a new build runs again", ran == true and r.build == "1.60.2.70200")
  check("selftest: a removed required function is missing", has.UIFrameFadeIn == true)
  check("selftest: a guarded function the last build had is missing", has.GetSpellInfo == true)
  check("selftest: and is absent for the next build's comparison", (function() for _, n in ipairs(r.absent) do if n == "GetSpellInfo" then return true end end end)() == true)
  check("selftest: ok is false", r.ok == false)
  check("selftest: the approved line", ST.line(r) == ("this WoW build changed %s (and 1 more); recording continues."):format(r.missing[1]), ST.line(r))

  -- the next build still lacks the guarded one: no longer a change; the required one is back
  build = "1.60.2.70210"; rawset(_G, "UIFrameFadeIn", fade)
  r = ST.run()
  check("selftest: a guarded function already absent on the last build is not a change", r.ok == true and #r.missing == 0, table.concat(r.missing, ","))
  rawset(_G, "GetSpellInfo", gsi)

  -- the first record ever on a client that lacks a guarded function: it is how this client is
  ns.DB.settings.selftest = nil; build = "1.60.2.70220"
  rawset(_G, "GetSpellInfo", nil)
  r = ST.run()
  check("selftest: on the first record a guarded absence is baseline, not a failure", r.ok == true and r.absent[1] ~= nil)
  rawset(_G, "GetSpellInfo", gsi)

  -- a forbidden event on one of the addon's frames; the line names it first
  build = "1.60.2.70230"
  local fr = ns.eventFrames[1]
  fr:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
  validEvent.ENCOUNTER_START = false
  r = ST.run()
  check("selftest: a registered forbidden event fails", r.forbidden[1] == "COMBAT_LOG_EVENT_UNFILTERED" and r.ok == false)
  check("selftest: an event the client no longer knows is missing", (function() for _, n in ipairs(r.missing) do if n == "ENCOUNTER_START" then return true end end end)() == true)
  check("selftest: the line names the forbidden event first", ST.line(r) == "this WoW build changed COMBAT_LOG_EVENT_UNFILTERED (and 1 more); recording continues.", ST.line(r))
  fr:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED"); validEvent.ENCOUNTER_START = nil

  -- issecretvalue gone, or answering true for a plain value
  build = "1.60.2.70240"
  local sv = rawget(_G, "issecretvalue")
  rawset(_G, "issecretvalue", nil)
  r = ST.run()
  check("selftest: issecretvalue gone is missing", r.missing[1] == "issecretvalue" and r.secrets == false)
  build = "1.60.2.70250"
  rawset(_G, "issecretvalue", function() return true end)
  r = ST.run()
  check("selftest: issecretvalue calling a plain value secret is missing", r.missing[1] == "issecretvalue")
  rawset(_G, "issecretvalue", sv)

  -- without C_EventUtils the events are not checked, and nothing fails for it
  build = "1.60.2.70260"
  rawset(_G, "C_EventUtils", nil)
  r = ST.run()
  check("selftest: events unchecked without C_EventUtils", r.events == "unchecked" and r.ok == true)
  rawset(_G, "C_EventUtils", { IsEventValid = function(e) return validEvent[e] ~= false end })

  -- a Classic client is not checked (WoW Forever only)
  build = "1.15.7.61000"
  local hsv, pid = ns.hasSecretValues, rawget(_G, "WOW_PROJECT_ID")
  ns.hasSecretValues = false; rawset(_G, "WOW_PROJECT_ID", rawget(_G, "WOW_PROJECT_CLASSIC"))
  r = ST.run()
  check("selftest: a Classic client is skipped", r.skipped == "classic" and r.ok == true and ST.line(r) == nil)
  ns.hasSecretValues = hsv; rawset(_G, "WOW_PROJECT_ID", pid)

  -- the login path: exactly one chat line when something fails, none when it passes
  build = "1.60.3.70300"; rawset(_G, "UIFrameFadeIn", nil); rawset(_G, "GetSpellInfo", nil)
  said = {}
  ST.onEnteringWorld(nil); M.runTimers()
  check("selftest: exactly one chat line when something fails", #said == 1 and said[1]:find("^this WoW build changed ") ~= nil and said[1]:find("; recording continues%.$") ~= nil, #said)
  ST.onEnteringWorld(nil); M.runTimers()
  check("selftest: no second line on the next login on the same build", #said == 1, #said)
  rawset(_G, "UIFrameFadeIn", fade); rawset(_G, "GetSpellInfo", gsi)
  build = "1.60.3.70310"; said = {}
  ST.onEnteringWorld(nil); M.runTimers()
  check("selftest: silent when everything passes at login", #said == 0, said[1])

  -- the self-test never breaks the addon: a broken frame in the registry is recorded, not thrown
  build = "1.60.3.70320"
  ns.eventFrames[#ns.eventFrames + 1] = { IsEventRegistered = function() error("boom") end }
  local okRun, rr = pcall(ST.run)
  check("selftest: an erroring check does not throw", okRun and rr and rr.ok == true)
  ns.eventFrames[#ns.eventFrames] = nil

  ns.msg = oldMsg
  for k, s in pairs(saved) do rawset(_G, k, s.v) end
end

print(("\n%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
