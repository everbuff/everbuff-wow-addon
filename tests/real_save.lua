-- A real SavedVariables file behind the headless window: tests/render_html.lua and tests/dump_real.lua load a
-- player's own save instead of the suite's fixtures, so a shot or a dump shows that player's real numbers.
--
--   EB_SAVE=<path>   the SavedVariables file (EverbuffJournal.lua as the client wrote it). It is only read.
--   EB_CHAR=<name or GUID>   the character to log in as (default: the highest level, then the one seen last)
--   EB_NOW=<unix time>       the clock (default: the end of that character's last session in the save, the latest
--                            moment the save knows of that character)
--   EB_BOOT=resume|login     resume (default): the character's last session at or before the clock goes on, the way
--                            a /reload keeps it, so Home > Now shows the session the player was in.
--                            login: a fresh login at the clock; the addon starts a new, empty session.
--   EB_RACE=<race>           the race UnitRace answers. A save does not carry it unless a stored fight does.
--   EB_ZONE=<zone>           the zone the character stands in (default: the zone of its last stored row)
--
-- The rule (founder: data accuracy is crucial): every answer the stubbed client gives comes from the save, or the
-- client answers nothing. What the save does not carry stays unanswered and is listed in S.unknown, so a pane shows
-- its own "not known" state instead of a number this file made up. The addon is loaded from the TOC in the client's
-- order, the save is handed over as EverbuffDB before ADDON_LOADED, and PLAYER_LOGIN and PLAYER_ENTERING_WORLD
-- fire into the real handlers. S.changes lists what that boot changed in the stored data.
--
--   local Real = dofile("tests/real_save.lua")
--   local S = Real.boot(M, { save = path, now = n, char = s, boot = s, race = s, zone = s })
--     S.ns, S.db, S.guid, S.char, S.now, S.session (the live session record), S.facts, S.unknown, S.changes, S.chat
--   Real.open(S, key) -> true | false, why      opens "host/pane[:state]" the way tests/render_html.lua does
--   Real.close(S)                               puts the window back after a page (filters, an open run page)
local R = {}

local CLASS_NAME = { WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest",
  SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid", DEATHKNIGHT = "Death Knight", MONK = "Monk",
  DEMONHUNTER = "Demon Hunter", EVOKER = "Evoker" }

local function num(v) return type(v) == "number" and v == v and v or nil end
local function deep(v, seen)
  if type(v) ~= "table" then return v end
  seen = seen or {}
  if seen[v] then return seen[v] end
  local o = {}; seen[v] = o
  for k, x in pairs(v) do o[deep(k, seen)] = deep(x, seen) end
  return o
end

-- the save file's three variables, read into a table of their own (nothing reaches _G here)
function R.read(path)
  local chunk, err = loadfile(path)
  if not chunk then error("EB_SAVE: cannot read " .. tostring(path) .. ": " .. tostring(err), 0) end
  local env = {}
  setfenv(chunk, env)
  local ok, e = pcall(chunk)
  if not ok then error("EB_SAVE: " .. tostring(path) .. " does not run: " .. tostring(e), 0) end
  if type(env.EverbuffDB) ~= "table" then error("EB_SAVE: " .. tostring(path) .. " holds no EverbuffDB", 0) end
  return env
end

-- the sessions of one character, oldest first
local function sessionsOf(db, guid)
  local out = {}
  for id, s in pairs(type(db.sessions) == "table" and db.sessions or {}) do
    if type(s) == "table" and s.guid == guid and num(s.startedEpoch) then out[#out + 1] = s; s.id = s.id or id end
  end
  table.sort(out, function(a, b) return a.startedEpoch < b.startedEpoch end)
  return out
end

-- which character: EB_CHAR by GUID, name or "name surname"; else the highest level, then the one seen last
function R.pick(db, want)
  local chars = type(db.characters) == "table" and db.characters or {}
  local list = {}
  for guid, c in pairs(chars) do if type(c) == "table" then list[#list + 1] = { guid = guid, c = c } end end
  if #list == 0 then error("EB_SAVE: the save holds no character", 0) end
  if want and want ~= "" then
    local w = want:lower()
    for _, e in ipairs(list) do
      local full = ((e.c.name or "") .. " " .. (e.c.surname or "")):lower():gsub("%s+$", "")
      if e.guid:lower() == w or (e.c.name or ""):lower() == w or full == w then return e.guid, e.c end
    end
    error("EB_CHAR: no character '" .. want .. "' in the save", 0)
  end
  table.sort(list, function(a, b)
    local la, lb = num(a.c.level) or 0, num(b.c.level) or 0
    if la ~= lb then return la > lb end
    local sa, sb = num(a.c.seen) or 0, num(b.c.seen) or 0
    if sa ~= sb then return sa > sb end
    return a.guid < b.guid
  end)
  return list[1].guid, list[1].c
end

-- the last stored row of the character that names a place, at or before `now`: { zone, sub, map, t, from }
local function lastPlace(db, c, mine, now)
  local best
  local function look(list, from)
    for _, r in ipairs(type(list) == "table" and list or {}) do
      if type(r) == "table" and type(r.zone) == "string" and r.zone ~= "" and num(r.t) and r.t <= now and mine[r.s]
        and (not best or r.t >= best.t) then
        best = { zone = r.zone, sub = type(r.sub) == "string" and r.sub or nil, map = num(r.map), t = r.t, from = from }
      end
    end
  end
  look(db.story and db.story.events, "story.events")
  look(db.loot and db.loot.log, "loot.log")
  look(db.story and db.story.rep, "story.rep")
  look(c.crafts, "crafts")
  return best
end

-- the race of the character when a stored fight names it (a fight's group row with me = true)
local function storedRace(db, mine)
  local fights = db.combat and db.combat.fights
  for i = #(type(fights) == "table" and fights or {}), 1, -1 do
    local f = fights[i]
    if type(f) == "table" and mine[f.session] then
      for _, g in ipairs(type(f.group) == "table" and f.group or {}) do
        if type(g) == "table" and g.me and type(g.race) == "string" and g.race ~= "" then return g.race end
      end
    end
  end
  return nil
end

-- every stored value that differs between two trees, as "path: old -> new" lines
local function diff(a, b, path, out, cap)
  if #out >= cap then return end
  if type(a) == "table" and type(b) == "table" then
    local keys = {}
    for k in pairs(a) do keys[k] = true end
    for k in pairs(b) do keys[k] = true end
    local order = {}
    for k in pairs(keys) do order[#order + 1] = k end
    table.sort(order, function(x, y) if type(x) == type(y) then return x < y end return tostring(x) < tostring(y) end)
    -- (a list that lost or gained many rows is one line: an applied ack prunes hundreds of fights)
    local gone, came = 0, 0
    for _, k in ipairs(order) do
      if type(k) == "number" then
        if b[k] == nil then gone = gone + 1 elseif a[k] == nil then came = came + 1 end
      end
    end
    local brief = gone + came > 6
    if brief then out[#out + 1] = ("%s: %d rows before, %d after (%d positions emptied, %d filled; a row removed from the middle shifts the rest)"):format(path, #a, #b, gone, came) end
    for _, k in ipairs(order) do
      if not (brief and type(k) == "number") then diff(a[k], b[k], path .. (path ~= "" and "." or "") .. tostring(k), out, cap) end
    end
  elseif a ~= b then
    local function show(v)
      if type(v) == "table" then local n = 0; for _ in pairs(v) do n = n + 1 end; return ("{%d keys}"):format(n) end
      if type(v) == "string" then return '"' .. v:gsub("\t", " "):sub(1, 70) .. '"' end
      return tostring(v)
    end
    out[#out + 1] = ("%s: %s -> %s"):format(path, show(a), show(b))
  end
end

-- ── the client the save describes ───────────────────────────────────────────────────────────────────────────────
local function client(M, db, guid, c, S, opts)
  local facts, unknown = S.facts, S.unknown
  local function fact(k, v, from) facts[#facts + 1] = { k = k, v = tostring(v), from = from } end
  local now, ses = S.now, S.last

  -- the clocks: server time is the chosen moment; GetTime runs on from the session's own monotonic stamps
  M.epoch = now
  if ses and num(ses.endedMono) and num(ses.endedEpoch) then M.now = ses.endedMono + (now - ses.endedEpoch)
  elseif ses and num(ses.startedMono) then M.now = ses.startedMono + (now - ses.startedEpoch)
  else M.now = 1000 end
  _G.time = function(t) if t then return os.time(t) end return M.epoch end
  _G.date = function(fmt, t) return os.date(fmt, t or M.epoch) end
  math.randomseed(now)
  fact("clock", ("%d  (%s local)"):format(now, os.date("%Y-%m-%d %H:%M:%S", now)), S.nowFrom)

  -- the day and the week as the save keeps them (settings.gold.dayBase, weekAnchor); else the client answers nothing
  local gold = type(db.settings) == "table" and type(db.settings.gold) == "table" and db.settings.gold or {}
  local base = type(gold.dayBase) == "table" and gold.dayBase or nil
  if base and base.kind == "server" and num(base.offset) then
    M.resetAt = base.offset
    fact("daily reset", ("%02d:%02d UTC"):format(math.floor(base.offset / 3600), math.floor(base.offset % 3600 / 60)), "settings.gold.dayBase")
  else
    M.resetSecs = false
    unknown[#unknown + 1] = "the server's daily reset (no settings.gold.dayBase of kind server): the client answers nothing"
  end
  if num(gold.weekAnchor) then
    M.weekStart = gold.weekAnchor + math.floor((now - gold.weekAnchor) / 604800) * 604800
    fact("weekly reset", os.date("!%a %H:%M UTC", gold.weekAnchor), "settings.gold.weekAnchor")
  else
    M.weekStart = false
    unknown[#unknown + 1] = "the weekly reset (no settings.gold.weekAnchor): the client answers nothing"
  end

  -- who
  local name, surname = c.name, type(c.surname) == "string" and c.surname ~= "" and c.surname or nil
  if type(name) ~= "string" then name = ses and ses.player or nil end
  local realm = type(c.realm) == "string" and c.realm or ""
  local classFile = type(c.class) == "string" and c.class or (ses and ses.class) or nil
  local race = opts.race and opts.race ~= "" and opts.race or storedRace(db, S.mine)
  fact("character", ("%s%s  %s"):format(tostring(name), surname and (" " .. surname) or "", guid), "characters[guid].name, surname")
  fact("class", tostring(classFile), "characters[guid].class")
  if race then fact("race", race, opts.race and opts.race ~= "" and "EB_RACE" or "combat.fights[].group (me)")
  else unknown[#unknown + 1] = "the race (no stored fight names it; pass EB_RACE): UnitRace answers nothing" end
  local unitName = _G.UnitName
  _G.UnitName = function(u) if u == "player" then return name, surname end return unitName(u) end
  _G.UnitNameUnmodified = _G.UnitName
  _G.UnitGUID = function(u) if u == "player" then return guid end local x = M.units[u]; return x and x.guid end
  _G.GetRealmName = function() return realm end
  _G.UnitClass = function() return classFile and (CLASS_NAME[classFile] or classFile) or nil, classFile end
  _G.UnitRace = function() return race end
  _G.UnitFactionGroup = function() return c.faction end
  _G.C_PlayerInfo = { ShouldDisplaySurname = function() return surname ~= nil end }
  local level = num(c.level) or (ses and num(ses.level)) or 0
  M.level = level
  fact("level", level, "characters[guid].level")

  -- the purse, the XP bar, the gear
  local bal = type(c.gold) == "table" and num(c.gold.balance) or nil
  if bal then M.money = bal; fact("purse", bal .. " copper", "characters[guid].gold.balance")
  else
    _G.GetMoney = function() return nil end
    unknown[#unknown + 1] = "the purse (no gold.balance): GetMoney answers nothing"
  end
  local xp = type(c.xp) == "table" and c.xp or {}
  if num(xp.cur) and num(xp.max) then
    M.xp, M.xpmax, M.rested = xp.cur, xp.max, (num(xp.rested) or 0) > 0 and xp.rested or nil
    fact("xp bar", ("%d / %d, rested %d"):format(xp.cur, xp.max, num(xp.rested) or 0), "characters[guid].xp")
  else
    _G.UnitXP, _G.UnitXPMax, _G.GetXPExhaustion = function() return nil end, function() return nil end, function() return nil end
    unknown[#unknown + 1] = "the XP bar (no xp.cur and xp.max): UnitXP answers nothing"
  end
  if num(c.ilvl) then
    _G.GetAverageItemLevel = function() return c.ilvl, c.ilvl end
    fact("item level", c.ilvl, "characters[guid].ilvl")
  else _G.GetAverageItemLevel = nil end
  -- durability is stored as one percentage over all slots: at 100 every slot is whole; under 100 the save does not
  -- say which slot is worn, so no slot answers and the stored percentage stays as it is
  local dur = type(c.durability) == "table" and num(c.durability.pct) or nil
  M.dur = {}
  if dur == 100 then M.dur[16] = { 100, 100 }; fact("durability", "100% on every slot", "characters[guid].durability.pct")
  else unknown[#unknown + 1] = ("durability by slot (stored: %s%% over all slots): no slot answers"):format(tostring(dur)) end
  M.gear = {}

  -- professions, as stored
  M.profs = {}
  local pnames = {}
  for pn, pr in pairs(type(c.professions) == "table" and c.professions or {}) do if type(pr) == "table" then pnames[#pnames + 1] = pn end end
  table.sort(pnames)
  for i, pn in ipairs(pnames) do M.profs[i] = { name = pn, rank = c.professions[pn].rank, max = c.professions[pn].max } end
  _G.GetProfessions = function() local idx = {}; for i = 1, math.min(#pnames, 6) do idx[i] = i end; return unpack(idx) end
  fact("professions", #pnames > 0 and table.concat(pnames, ", ") or "none", "characters[guid].professions")

  -- where
  local place = lastPlace(db, c, S.mine, now)
  local zone = opts.zone and opts.zone ~= "" and opts.zone or (place and place.zone) or nil
  local inInst = type(c.inInstance) == "string" and c.inInstance ~= "" and c.inInstance or nil
  local openRun = type(c.dungeonRun) == "table" and c.dungeonRun or nil
  if inInst then zone = (opts.zone and opts.zone ~= "" and opts.zone) or inInst end
  M.zone = zone
  _G.GetSubZoneText = function() return (place and zone == place.zone and place.sub) or "" end
  _G.GetZoneText = function() return zone end
  M.uiMap = place and zone == place.zone and place.map or nil
  local st = type(db.settings) == "table" and type(db.settings.selftest) == "table" and db.settings.selftest or {}
  if inInst then
    M.inst = { name = inInst, type = (openRun and openRun.kind) or "party", diff = (openRun and num(openRun.diff)) or 1, mapID = (openRun and num(openRun.map)) or 0 }
    M.mapType = 4
    fact("instance", inInst, "characters[guid].inInstance")
  else
    M.inst = { name = zone or "", type = "none", diff = 0, mapID = 0 }
    M.mapType = 3
  end
  if zone then fact("zone", zone .. ((place and zone == place.zone and place.sub and place.sub ~= "") and (", " .. place.sub) or ""),
    (opts.zone and opts.zone ~= "") and "EB_ZONE" or inInst and "characters[guid].inInstance"
      or ("the last row of %s, at %d%s"):format(place.from, place.t, (ses and place.t < ses.startedEpoch) and ", before this session: where the character stood then" or ""))
  else unknown[#unknown + 1] = "the zone (no stored row names one; pass EB_ZONE): GetRealZoneText answers nothing" end
  if not M.uiMap then _G.C_Map.GetBestMapForUnit = function() return nil end end
  _G.C_Map.GetPlayerMapPosition = function() return nil end
  M.groupN = 0
  _G.GetNumGroupMembers = function() return 0 end

  -- the build, from the self-test record of the client that wrote the save
  local ver, build = tostring(st.build or ""):match("^(.*)%.(%d+)$")
  local iface = num(st.interface) or (ses and num(ses.build)) or nil
  if ver and iface then
    _G.GetBuildInfo = function() return ver, build, "", iface end
    fact("client build", ("%s.%s, interface %d"):format(ver, build, iface), "settings.selftest")
  end
  if ses and ses.project ~= nil then _G.WOW_PROJECT_ID = ses.project end

  -- combat logging as the session found it
  local lg = ses and type(ses.logging) == "table" and ses.logging or {}
  M.logging = lg.combat and true or false
  M.cvars.advancedCombatLogging = lg.acl and "1" or "0"
  fact("combat log", ("combat=%s advanced=%s"):format(tostring(M.logging), tostring(lg.acl and true or false)), "sessions[id].logging")

  -- item names the save itself carries (a loot or craft row has the id and the name); nothing else is "cached"
  M.itemNames = {}
  local function names(list)
    for _, r in ipairs(type(list) == "table" and list or {}) do
      if type(r) == "table" and num(r.id) and type(r.item) == "string" and r.item ~= "" then M.itemNames[r.id] = r.item end
    end
  end
  names(db.loot and db.loot.log); names(c.crafts)
  _G.GetItemInfo = function() return nil end
  _G.C_Item.GetItemInfo = function() return nil end
  M.sellPrice, M.itemQuality = {}, {}
  unknown[#unknown + 1] = "vendor prices and item qualities the client would answer from its item cache: C_Item.GetItemInfo answers nothing"

  -- the stub's invented answers have no place here
  _G.GetFactionInfo, _G.GetNumFactions = nil, nil
  _G.GetSpecialization, _G.GetSpecializationInfo = nil, nil
  M.saved, M.guild, M.friends, M.inbox, M.bags = {}, {}, {}, {}, {}
  _G.C_Container.GetContainerNumSlots = function() return 0 end
  unknown[#unknown + 1] = "live reputation bars (the save keeps the standing, not the progress inside it): no faction API answers"
  unknown[#unknown + 1] = "free bag slots, the quest log, saved instances (lockouts beyond characters[guid].lockouts), the guild and friends lists"
  unknown[#unknown + 1] = "spell names beyond the stub's few (C_Spell.GetSpellName), the character portrait, item icons (drawn as squares)"

  -- what this client does not have (the self-test's own list of absent APIs, events and strings)
  local absent = type(st.absent) == "table" and st.absent or {}
  local was = {}
  for _, n in ipairs(absent) do if type(n) == "string" then was[n] = true end end
  -- (a namespaced replacement the client must have, since the addon read its version and its spells through it)
  if was.GetAddOnMetadata then _G.C_AddOns = { GetAddOnMetadata = _G.GetAddOnMetadata } end
  if was.GetSpellInfo then
    local gsi = _G.GetSpellInfo
    _G.C_Spell = _G.C_Spell or {}
    _G.C_Spell.GetSpellName = _G.C_Spell.GetSpellName or function(id) return (gsi(id)) end
  end
  M.unknownEvents = M.unknownEvents or {}
  local gone = 0
  for n in pairs(was) do
    local tbl, field = n:match("^([%w_]+)%.([%w_]+)$")
    if tbl then if type(_G[tbl]) == "table" and _G[tbl][field] ~= nil then _G[tbl][field] = nil; gone = gone + 1 end
    elseif rawget(_G, n) ~= nil then _G[n] = nil; gone = gone + 1
    elseif n:match("^[%u%d_]+$") then M.unknownEvents[n] = true; gone = gone + 1 end
  end
  if #absent > 0 then fact("absent on this client", ("%d of the self-test's %d names removed from the stub"):format(gone, #absent), "settings.selftest.absent")
  else M.profile("forever"); unknown[#unknown + 1] = "which APIs the client lacks (no settings.selftest.absent): the WoW Forever profile of the stub" end
end

-- ── boot ────────────────────────────────────────────────────────────────────────────────────────────────────────
function R.boot(M, opts)
  opts = opts or {}
  local env = R.read(opts.save)
  local db = env.EverbuffDB
  local guid, c = R.pick(db, opts.char)
  local S = { db = db, guid = guid, char = c, facts = {}, unknown = {}, chat = {}, notes = {}, M = M, save = opts.save }
  local mode = opts.boot and opts.boot ~= "" and opts.boot:lower() or "resume"
  if mode ~= "resume" and mode ~= "login" then error("EB_BOOT: resume or login, not '" .. tostring(opts.boot) .. "'", 0) end
  S.mode = mode

  local mine = {}
  local sessions = sessionsOf(db, guid)
  for _, s in ipairs(sessions) do mine[s.id] = true end
  S.mine = mine
  local latest = num(c.seen) or 0
  for _, s in ipairs(sessions) do latest = math.max(latest, num(s.endedEpoch) or s.startedEpoch) end
  local saveLatest = 0
  for _, s in pairs(type(db.sessions) == "table" and db.sessions or {}) do
    if type(s) == "table" then saveLatest = math.max(saveLatest, num(s.endedEpoch) or num(s.startedEpoch) or 0) end
  end
  local now = tonumber(opts.now)
  if opts.now and opts.now ~= "" and not now then error("EB_NOW: a unix time, not '" .. tostring(opts.now) .. "'", 0) end
  if now then S.nowFrom = "EB_NOW"
  elseif latest > 0 then now, S.nowFrom = latest, "the end of the character's last session in the save"
  else error("EB_SAVE: no session of " .. tostring(c.name) .. " in the save; pass EB_NOW", 0) end
  now = math.floor(now)
  S.now, S.latest, S.saveLatest = now, latest, saveLatest
  if now < latest then S.notes[#S.notes + 1] = ("EB_NOW %d is before the character's last stored moment %d: rows written after it are still in the save and still show"):format(now, latest) end
  if saveLatest > latest then S.notes[#S.notes + 1] = ("the save's last session ends at %d, on another character; this character's own data ends at %d"):format(saveLatest, latest) end

  -- the session the clock falls in or follows
  local last
  for _, s in ipairs(sessions) do if s.startedEpoch <= now then last = s end end
  S.last = last

  S.raw = deep(db)
  client(M, db, guid, c, S, opts)

  -- the addon, file by file in the TOC's order, with (addonName, ns) as the client passes them
  local ns, ADDON = {}, "EverbuffJournal"
  local realPrint = print
  print = function(...) local t = {}; for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end; S.chat[#S.chat + 1] = table.concat(t, " ") end
  local ok, err = pcall(function()
    for line in io.lines("Everbuff/EverbuffJournal.toc") do
      local f = line:match("^([%w_]+%.lua)%s*$")
      if f then
        local chunk, e = loadfile("Everbuff/" .. f)
        if not chunk then error("parse " .. f .. ": " .. tostring(e), 0) end
        local good, e2 = pcall(chunk, ADDON, ns)
        if not good then error("load " .. f .. ": " .. tostring(e2), 0) end
      end
    end
    -- the client hands the saved variables over after the files ran and before ADDON_LOADED
    _G.EverbuffDB, _G.EverbuffTest, _G.EverbuffAck = db, env.EverbuffTest, env.EverbuffAck
    M.fire("ADDON_LOADED", ADDON)
    if mode == "resume" and last then
      -- a /reload keeps the session: the record must be the active one (the save's active record can be another
      -- character's, when that one logged out last)
      if db.active ~= last.id then
        S.notes[#S.notes + 1] = ("the save's active record is %s; %s is made the active one so the reload resumes it"):format(tostring(db.active), last.id)
        db.active = last.id
      end
      if last.endedBy ~= nil and last.endedBy ~= "logout" then
        S.notes[#S.notes + 1] = ("session %s ended by '%s', not by a logout: a reload does not resume it, a new session starts"):format(last.id, tostring(last.endedBy))
      end
    end
    M.fire("PLAYER_LOGIN")
    if mode == "resume" then M.fire("PLAYER_ENTERING_WORLD", false, true) else M.fire("PLAYER_ENTERING_WORLD", true, false) end
    for _ = 1, 4 do M.runTimers() end   -- the reads a load schedules (rep seed, /played request, the away booking)
  end)
  print = realPrint
  if not ok then error("EB_SAVE boot: " .. tostring(err), 0) end
  S.ns = ns
  S.session = ns.Recorder and ns.Recorder.current and ns.Recorder.current() or nil
  if mode == "resume" and last and S.session ~= last then
    S.notes[#S.notes + 1] = ("the addon did not resume %s; the live session is %s"):format(last.id, tostring(S.session and S.session.id))
  end
  do
    local st = S.raw.settings and S.raw.settings.selftest
    if type(st) == "table" and st.addon ~= ns.VERSION then
      S.notes[#S.notes + 1] = ("the save was written by addon %s and this is %s: the addon's self-test ran again, against the stub's API list (settings.selftest below is not the client's)"):format(tostring(st.addon), tostring(ns.VERSION))
    end
  end
  if mode == "resume" and not last then S.notes[#S.notes + 1] = "no session of this character starts at or before the clock: the addon started a new one" end
  -- the window where the renderer draws it (the saved position belongs to the player's screen)
  S.winSize = type(db.settings) == "table" and type(db.settings.winSize) == "table" and deep(db.settings.winSize) or nil
  if type(db.settings) == "table" then db.settings.winPos = nil end
  M.inCombat = false

  local changes = {}
  diff(S.raw, db, "", changes, 400)
  S.changes = changes
  return S
end

-- ── pages ───────────────────────────────────────────────────────────────────────────────────────────────────────
R.HOSTS = { loot = "Loot", home = "Home", combat = "Combat", dungeons = "Dungeons", character = "Character", settings = "Settings" }
-- every page a real save can show (the fixture-only states of tests/render_html.lua are not among them)
R.PAGES = { "home/now", "home/sessions", "home/activity", "home/fights", "home/deaths",
  "dungeons/runs", "dungeons/bydungeon", "dungeons/run",
  "loot/items", "loot/items:all", "loot/items:byitem",
  "loot/gold", "loot/gold:today", "loot/gold:week", "loot/gold:all", "loot/gold:journal", "loot/gold:days", "loot/gold:zones",
  "loot/gold:runs", "loot/gold:chars", "loot/gold:auctions",
  "character/leveling", "character/reputation", "character/professions",
  "settings/general", "settings/golddisplay", "settings/data" }

-- the Gold pane, the Items pane and a Settings sub-tab in a state; returns the function that takes the state back
function R.view(ns, host, pane, state)
  if host == "loot" and pane == "gold" then
    if state == "" then ns.Gold.open("session")
    elseif state == "journal" then ns.Gold.open("session", "journal")
    elseif state == "flagged" then ns.Gold.open("session", "journal", true)
    elseif state == "all" then ns.Gold.open("all", "journal")
    elseif state == "previous" then ns.Gold.open("previous")
    elseif state == "today" then ns.Gold.open("today")
    elseif state == "days" then ns.Gold.open("all", "days")
    elseif state == "chars" then ns.Gold.open("today", "chars")
    elseif state == "week" then ns.Gold.open("week")
    elseif state == "zones" or state == "runs" then ns.Gold.open("all", state)
    elseif state == "auctions" then ns.UI.Open("Loot", "auctions")
    elseif state == "empty" then ns.Gold.open("day:" .. ns.Gold.dayKey(GetServerTime() - 400 * 86400, ns.Gold.baseStored()))
    else ns.Gold.open("session"); ns.Gold.filter(state) end
  end
  if host == "loot" and pane == "items" and state ~= "" then
    local ic = ns._test.lootContent and ns._test.lootContent()
    if ic then
      local mode, quality = ns.DB.settings.itemsMode, ns.DB.settings.itemsQuality
      if state == "byitem" then ic.setLootMode("byitem")
      elseif state == "all" then ic.setLootQuality("all")
      elseif state == "nomatch" then ic.search:SetText("zzzz"); ic.search.scripts.OnTextChanged(ic.search) end
      return function()
        ic.search:SetText(""); ic.search.scripts.OnTextChanged(ic.search)
        ic.setLootMode(mode or "newest"); ic.setLootQuality(quality or "green")
      end
    end
  end
  if host == "settings" then
    for _, t in ipairs(ns._test.tabs or {}) do
      if t.name == "Settings" and t.content and t.content.subtabs then t.content.subtabs.select(pane) end
    end
  end
  return nil
end

-- states that only the fixtures can build: a real save shows what it holds
local FIXTURE_ONLY = { ["home/now"] = true, ["dungeons/runs"] = true, ["dungeons/bydungeon"] = true }

function R.open(S, key)
  local ns, M = S.ns, S.M
  local host, pane, state = key:match("^(%w+)/(%w+):?(%w*)$")
  if not host then return false, "not a page key" end
  if state ~= "" and FIXTURE_ONLY[host .. "/" .. pane] then return false, "the state '" .. state .. "' is built by the fixtures; a real save has no such state" end
  local openPane = pane
  local run
  if host == "dungeons" and pane == "run" then
    -- "dungeons/run": the newest run of the character; "dungeons/run:2": the one before it
    local nth = state == "" and 1 or tonumber(state)
    if not nth then return false, "dungeons/run takes a number (1 is the newest run)" end
    local views = ns._test.runViews and ns._test.runViews(true) or {}
    run = views[#views - nth + 1]
    if not run then return false, ("the save holds %d dungeon run%s of this character"):format(#views, #views == 1 and "" or "s") end
    openPane = "runs"
  end
  local tab = R.HOSTS[host] or host
  ns.UI.Open(tab, openPane); M.tick()
  ns.UI.Open(tab, openPane)   -- a second open: the panes read sizes their first build set
  if run then ns._test.dungeonList(); ns.Dungeons.openRun(run) end
  S.undo = R.view(ns, host, pane, state)
  S.opened = { tab = tab, pane = openPane, run = run ~= nil }
  M.settle()
  return true
end

function R.close(S)
  local ns, M, o = S.ns, S.M, S.opened
  if not o then return end
  if o.run then
    local dv = ns._test.dungeonDetail and ns._test.dungeonDetail()
    if dv and dv:IsShown() and dv.d and dv.d.Close then dv.d.Close() end
  end
  if S.undo then S.undo() end
  S.undo, S.opened = nil, nil
  ns.UI.Open(o.tab, o.pane); M.settle()
end

return R
