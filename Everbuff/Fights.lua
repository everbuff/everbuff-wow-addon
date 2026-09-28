-- Everbuff.GG · Fights.lua - the per-fight context recorder.
--
-- Records one entry per fight (combat enter → leave): who you faced, the result, your party/raid,
-- and timestamped timelines of your buffs/debuffs, gear (worn + swaps), and readable character stats.
--
-- Scope + honesty: the engine-written combat-log FILE remains the source of truth for damage/DPS
-- (and on the Midnight/Secret-Values client that data is unreadable to addons anyway). This module
-- captures the CONTEXT the file does NOT hold well - group makeup, gear at each moment, and your aura
-- timeline - so everbuff.gg can reconstruct exactly what you brought to each fight. Every read that
-- Secret Values might block is wrapped in pcall and simply omitted when unavailable.

local ADDON, ns = ...
local F = {}
ns.Fights = F

-- FIGHT_CAP is a safety backstop only. Real cleanup will be upload-driven: once the desktop client
-- has read a fight and shipped it to the backend, it acks (by fight id) and the addon prunes it. Until
-- that handshake exists, the cap keeps SavedVariables from growing without bound if the desktop never runs.
local FIGHT_CAP = 250
local AURA_CAP = 150        -- per-fight aura timeline cap (each unit)
local DEFAULT_SAMPLE = 1    -- seconds between stat snapshots (fixed; identical snapshots are deduped)
local SAMPLE_MIN, SAMPLE_MAX = 1, 10

-- Durable flush: SavedVariables only hit disk on /reload or logout, and there is NO API to force a
-- mid-session flush. So for long sessions we prompt an out-of-combat reload once enough unsaved play
-- has built up - by FIGHT COUNT or by TIME (covers degenerate 100h+ no-reload sessions), throttled so
-- it is never spammy. A reload is non-destructive (fights persist), it just commits them to disk.
local FLUSH_FIGHTS = 60          -- flush after this many unsaved fights

F.SAMPLE_MIN, F.SAMPLE_MAX, F.DEFAULT_SAMPLE = SAMPLE_MIN, SAMPLE_MAX, DEFAULT_SAMPLE
-- how often to snapshot stats, honouring the Settings value (clamped)
function F.sampleInterval()
  local v = ns.DB and ns.DB.settings and tonumber(ns.DB.settings.statSample)
  v = v or DEFAULT_SAMPLE
  if v < SAMPLE_MIN then v = SAMPLE_MIN elseif v > SAMPLE_MAX then v = SAMPLE_MAX end
  return v
end

local sessionCount = 0            -- fights recorded since this load (unsaved until next flush)

local ef = CreateFrame("Frame")
local cur = nil                   -- the in-progress fight, or nil when out of combat
local sessionStart = GetTime()    -- when this UI load began (all fights since are unsaved)
local lastCombatEnd = 0           -- when we last left combat (let the dust settle before reloading)
local lastModalShown = GetTime()  -- throttle for the save-reminder modal
local modalInterrupted = false    -- the reminder was up and combat hid it: bring it back once safe, no throttle
local statTicker = nil
local flushTicker = nil

-- ── DISCONNECT PROTECTION ──────────────────────────────────────────────────────
-- SavedVariables only reach disk on /reload or logout; a DC/crash flushes nothing, and there is NO
-- API to force a mid-session flush. We do NOT auto-reload silently: reading secret aura/stat values
-- taints the addon, and a background reload from tainted code is blocked (and just spams). Instead we
-- show a periodic MODAL (Deathlog-style) - the player clicking "Reload & save" is a hardware event,
-- which is the reliable way to commit to disk. On by default; reappears every MODAL_SECS while unsaved.
local MODAL_SECS = 240            -- how often the reminder modal reappears while data is unsaved

local function autoSaveOn()
  local s = ns.DB and ns.DB.settings
  if not s or s.autoSave == nil then return true end     -- default ON
  return s.autoSave and true or false
end
local function unsaved() return sessionCount > 0 end

-- reliable UI reload across clients: Midnight (12.0) exposes C_UI.Reload; older uses global ReloadUI.
local function doReload()
  if C_UI and C_UI.Reload then C_UI.Reload()
  elseif ReloadUI then ReloadUI() end
end

-- branded periodic "save your progress" reminder (Deathlog-style), built lazily on first show
local modal
local function buildModal()
  if modal then return modal end
  local UI = ns.UI; if not (UI and UI.C) then return nil end
  local C = UI.C
  local f = CreateFrame("Frame", "EverbuffSaveModal", UIParent, "BackdropTemplate")
  f:SetSize(412, 176); f:SetPoint("TOP", 0, -160); f:SetFrameStrata("FULLSCREEN_DIALOG"); f:SetToplevel(true)
  f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
  f:SetBackdropColor(1, 1, 1, 0.98); f:SetBackdropBorderColor(C.edge[1], C.edge[2], C.edge[3], 1)
  f:EnableMouse(true); f:SetMovable(true); f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
  local mark = f:CreateTexture(nil, "ARTWORK"); mark:SetSize(24, 24); mark:SetPoint("TOPLEFT", 14, -14)
  mark:SetTexture("Interface\\AddOns\\EverbuffJournal\\media\\mark")
  local title = UI.FS(f, "GameFontNormalLarge", C.gold); title:SetPoint("TOPLEFT", 46, -18); title:SetText("Disconnect protection")
  local body = UI.FS(f, "GameFontHighlight"); body:SetPoint("TOPLEFT", 16, -54); body:SetWidth(380); body:SetJustifyH("LEFT")
  f.body = body
  -- SECURE reload button: our addon is tainted (we read secret values), so a reload called from our
  -- Lua is blocked. A SecureActionButton runs "/reload" through WoW's protected path on your click,
  -- which is not blocked. Attributes are set here (out of combat, when the modal is first built).
  local save = CreateFrame("Button", "EverbuffSaveReloadBtn", f, "SecureActionButtonTemplate,BackdropTemplate")
  save:SetSize(150, 28); save:SetPoint("BOTTOMLEFT", 16, 16)
  save:SetAttribute("type", "macro")
  save:SetAttribute("macrotext", "/reload")
  save:RegisterForClicks("AnyUp", "AnyDown")
  save:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
  save:SetBackdropColor(C.panel2[1], C.panel2[2], C.panel2[3], 0.9); save:SetBackdropBorderColor(C.edge[1], C.edge[2], C.edge[3], 1)
  local savefs = ns.UI.FS(save, "GameFontNormal")
  savefs:SetPoint("CENTER"); savefs:SetText("Reload & save"); savefs:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
  save:HookScript("OnEnter", function(s) s:SetBackdropBorderColor(C.edge[1], C.edge[2], C.edge[3], 1); s:SetBackdropColor(C.cyan[1], C.cyan[2], C.cyan[3], 0.22) end)
  save:HookScript("OnLeave", function(s) s:SetBackdropBorderColor(C.edge[1], C.edge[2], C.edge[3], 1); s:SetBackdropColor(C.panel2[1], C.panel2[2], C.panel2[3], 0.9) end)
  local later = UI.Button(f, "Later", 100, 28, function() lastModalShown = GetTime(); modalInterrupted = false; f:Hide() end)
  f.later = later
  later:SetPoint("BOTTOMRIGHT", -16, 16)
  f:Hide()
  modal = f
  return f
end
local function showModal()
  local f = buildModal(); if not f then return end
  f.body:SetText("Reload now to protect this session from disconnect data loss.")
  lastModalShown = GetTime(); modalInterrupted = false
  f:Show()
end

-- watchdog: while there is unsaved data and we're not in combat, show the save reminder periodically
-- "Safe to reload" = out of combat for a settle period, alive, and not mid-loot. The reminder must never
-- be on screen during a fight (it hides the moment combat starts, see PLAYER_REGEN_DISABLED) and only
-- appears again once the addon judges the moment safe.
local SETTLE_SECS = 8
local function safeToReload()
  if InCombatLockdown and InCombatLockdown() then return false end
  if UnitAffectingCombat and UnitAffectingCombat("player") then return false end
  if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return false end
  if (GetTime() - lastCombatEnd) < SETTLE_SECS then return false end
  return true
end
local function flushTick()
  if not autoSaveOn() or not unsaved() then return end
  if not safeToReload() then
    if modal and modal:IsShown() then modal:Hide(); modalInterrupted = true end   -- never linger into a fight
    return
  end
  if modal and modal:IsShown() then return end
  -- a reminder that combat interrupted comes straight back once it is safe; otherwise the throttle applies
  if modalInterrupted or (GetTime() - lastModalShown) >= MODAL_SECS then showModal() end
end

-- ── small safe helpers ────────────────────────────────────────────────────────
local function now() return (GetServerTime and GetServerTime()) or time() end
local function mono() return GetTime() end
-- One-time clock calibration: time() is whole seconds, GetTime() is fractional but monotonic. Pairing
-- them at load lets each fight carry a FRACTIONAL local wall-clock, which the desktop needs to align a
-- fight boundary to a video frame (whole-second server time cannot).
local CAL_EPOCH, CAL_MONO = time(), GetTime()
local function try(fn, ...)  -- call an API that Secret Values may block; return nil on failure
  local ok, a, b, c, d, e, f2 = pcall(fn, ...)
  if ok then return a, b, c, d, e, f2 end
end
-- Some identity values (an ENEMY's UnitGUID, sometimes an aura spellId/name) come back as Secret Values
-- on the Midnight client and THROW when used as a table key ("cannot be indexed with secret keys").
-- safeKey returns v only if it can actually be used as a key, else nil so callers can fall back.
local keyScratch = {}
local function setKey(t, k) t[k] = true; t[k] = nil end
local function safeKey(v)
  if v == nil then return nil end
  if issecretvalue and issecretvalue(v) then return nil end
  local ok = pcall(setKey, keyScratch, v)   -- hot path: no closure or table allocation per call
  return ok and v or nil
end

-- ── gear ────────────────────────────────────────────────────────────────────
local SLOTS = {
  [1] = "Head", [2] = "Neck", [3] = "Shoulder", [5] = "Chest", [6] = "Waist",
  [7] = "Legs", [8] = "Feet", [9] = "Wrist", [10] = "Hands", [11] = "Finger 1",
  [12] = "Finger 2", [13] = "Trinket 1", [14] = "Trinket 2", [15] = "Back",
  [16] = "Main hand", [17] = "Off hand", [18] = "Ranged",
}
-- structured item info for a slot: name + icon + quality (NEVER the raw link - its pipe escapes are
-- stripped by sanitize() on this client and render as garbage, and can't show an icon). id lets the
-- desktop resolve the exact item; quality drives the name color; icon renders inline in the UI.
-- The link's item string is id:enchant:gem1:gem2:gem3:gem4:...; a 0 or empty field is none (#11, CB-1).
local function linkExtras(link)
  local fields = link:match("Hitem:([%-%d:]+)")
  if not fields then return nil, nil end
  local parts, i = {}, 0
  for f in (fields .. ":"):gmatch("([^:]*):") do i = i + 1; parts[i] = f end
  local enchant = tonumber(parts[2] or "")
  local gems = {}
  for k = 3, 6 do local g = tonumber(parts[k] or ""); if g and g > 0 then gems[#gems + 1] = g end end
  return (enchant and enchant > 0) and enchant or nil, (#gems > 0) and gems or nil
end
F.linkExtras = linkExtras   -- tests
local function itemAt(slot)
  local link = try(GetInventoryItemLink, "player", slot)
  if not link then return nil end
  local enchant, gems = linkExtras(link)
  return {
    name = link:match("%[(.-)%]"),
    id = tonumber(link:match("Hitem:(%d+)")),
    icon = try(GetInventoryItemTexture, "player", slot),
    quality = try(GetInventoryItemQuality, "player", slot),
    enchant = enchant, gems = gems,
  }
end
local function snapshotGear()
  local g = {}
  for slot in pairs(SLOTS) do
    local it = itemAt(slot)
    if it then g[slot] = it end
  end
  return g
end

-- ── auras (buffs + debuffs on the player) ─────────────────────────────────────
-- returns a set keyed by a stable id → { name, icon, debuff }
-- one pass over a filter; hoisted (no closure per scan) and guarded by ONE pcall per filter instead
-- of one per aura index. This runs per unit per sweep and per throttled UNIT_AURA, so it must be lean.
-- On the Midnight client an aura's name / spellId / icon can be Secret Values WHILE IN COMBAT and plain
-- again out of combat. If we skipped hidden auras the fight timeline would be empty until the final
-- out-of-combat scan re-added everything as a "gain" at the end. So: identity comes from the aura
-- INSTANCE id (or spell id, or name) - whichever is plain; a hidden name is resolved from a plain spell
-- id (spell data is static, never secret); anything still unknown is backfilled after combat.
F.hiddenAuras = 0   -- diagnostic: how many aura reads had no readable name this session
F.blindScans = 0    -- diagnostic: scans that saw auras but could identify NONE of them (skipped, no diff)
-- The UNIT_AURA storm in a dungeon calls this hundreds of times a minute. To keep garbage low, an aura
-- that was already in the previous snapshot keeps its entry table (identity fields never change; a name
-- that was hidden and became readable is filled in place), and the scan counters live in one reused table.
local scanStat = { raw = 0, kept = 0 }
local function scanFilter(unit, filter, debuff, set, stat, prev)
  local getData = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
  for i = 1, 40 do
    local rawName, rawIcon, rawSid, rawInst
    if getData then
      local a = getData(unit, i, filter)
      if not a then break end
      rawName, rawIcon, rawSid, rawInst = a.name, a.icon, a.spellId, a.auraInstanceID
    elseif UnitAura then
      local n, ic, _, _, _, _, _, _, _, sid = UnitAura(unit, i, filter)
      if not n then break end
      rawName, rawIcon, rawSid = n, ic, sid
    else
      break
    end
    stat.raw = stat.raw + 1
    local inst, sid = safeKey(rawInst), safeKey(rawSid)
    local name, icon = safeKey(rawName), safeKey(rawIcon)
    if not name and sid then                              -- static spell data is never secret
      if GetSpellInfo then local n2, _, ic2 = GetSpellInfo(sid); name = safeKey(n2); icon = icon or safeKey(ic2) end
      if not name and C_Spell and C_Spell.GetSpellName then name = safeKey(C_Spell.GetSpellName(sid)) end
      if not icon and C_Spell and C_Spell.GetSpellTexture then icon = safeKey(C_Spell.GetSpellTexture(sid)) end
    end
    if not name then F.hiddenAuras = F.hiddenAuras + 1; if cur then cur.auraHidden = (cur.auraHidden or 0) + 1 end end
    local key = inst or sid or name
    if key then
      stat.kept = stat.kept + 1
      local k = tostring(key) .. (debuff and "|d" or "|b")
      local e = prev and prev[k]
      if e then
        if not e.name and name then e.name = name end     -- became readable: fill in place
        if not e.icon and icon then e.icon = icon end
        set[k] = e
      else
        set[k] = { name = name, icon = icon, debuff = debuff, inst = inst, sid = sid }
      end
    end
  end
end
-- returns the live set and `blind`: true when the client showed auras but every identity field was
-- hidden. A blind scan carries no information, so callers must skip the diff instead of recording
-- "everything lost" (that artifact is exactly what emptied the scrubber mid-fight).
local function scanAuras(unit, prev)
  local set, stat = {}, scanStat
  stat.raw, stat.kept = 0, 0
  pcall(scanFilter, unit, "HELPFUL", false, set, stat, prev)
  pcall(scanFilter, unit, "HARMFUL", true, set, stat, prev)
  local blind = (stat.raw > 0 and stat.kept == 0)
  if blind then F.blindScans = F.blindScans + 1 end
  return set, blind, stat.raw
end
-- Observed on the beta (fight at 10:39, 2026-09-25): a few seconds into combat the client returned NO
-- auras for the living player, then all of them again once combat ended. A living unit does not lose
-- every buff in one tick, so "had >= 2, now 0, still alive" is treated as unreadable, not as a loss.
-- (Death is the one legitimate all-gone case and is exempt.)
local function vanished(prev, raw, unit, isEnemy)
  if raw ~= 0 then return false end
  local n = 0; for _ in pairs(prev) do n = n + 1; if n >= 2 then break end end
  if n < 2 then return false end
  local dead = isEnemy and (UnitIsDead and UnitIsDead(unit)) or (not isEnemy and UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit))
  return not dead
end

-- Cap an aura timeline WITHOUT discarding the pull-time seeds. The old-first trim dropped the t=0
-- atPull gains, so replaying the log lost buffs that were up at the pull and the scrubber reconstructed
-- the wrong state for long fights. Here we evict the oldest NON-pull entry instead.
local function trimAura(log)
  while #log > AURA_CAP do
    local removed = false
    for i = 1, #log do
      if not log[i].atPull then table.remove(log, i); removed = true; break end
    end
    if not removed then table.remove(log, 1) end   -- all remaining are pull seeds: fall back to old-first
  end
end

-- diff `unit`'s live auras against its last snapshot; append gains/losses (with timestamp) to `log`.
-- prevKey selects which working-set slot on `cur` holds the previous snapshot for this unit.
local function diffAurasFor(unit, log, prevKey, atPull)
  if not cur then return end
  local prev = cur[prevKey] or {}
  local live, blind, raw = scanAuras(unit, prev)
  if blind or vanished(prev, raw, unit, false) then   -- unreadable right now: keep the previous state, no diff
    cur.auraBlind = (cur.auraBlind or 0) + 1; F.blindScans = F.blindScans + (blind and 0 or 1)
    return
  end
  local t = mono() - cur.startMono
  for key, a in pairs(live) do
    if not prev[key] then
      log[#log + 1] = { t = t, gain = true, name = a.name, icon = a.icon, debuff = a.debuff, inst = a.inst, sid = a.sid, atPull = atPull or nil }
    end
  end
  for key, a in pairs(prev) do
    if not live[key] then
      log[#log + 1] = { t = t, gain = false, name = a.name, icon = a.icon, debuff = a.debuff, inst = a.inst, sid = a.sid }
    end
  end
  trimAura(log)
  cur[prevKey] = live
end

local function diffAuras() if cur then diffAurasFor("player", cur.auras, "_auraSet") end end

-- After combat the client makes aura data readable again: fill in names/icons for timeline entries
-- that were recorded while hidden, matching by aura instance id against the final (readable) scan.
local function backfillAuras(log, live)
  if not (log and live) then return end
  local byInst = {}
  for _, a in pairs(live) do if a.inst and a.name then byInst[a.inst] = a end end
  for _, e in ipairs(log) do
    if e.inst and not e.name then
      local a = byInst[e.inst]
      if a then e.name = a.name; e.icon = e.icon or a.icon end
    end
  end
end

-- diff a party/raid member's auras into their timeline (O(1) lookup via the unit->member map)
local function diffMember(unit)
  if not cur or not cur._memberByUnit or not cur.memberAuras then return end
  local m = cur._memberByUnit[unit]
  if m and not m.me and cur.memberAuras[m.name] then
    diffAurasFor(unit, cur.memberAuras[m.name], "_ms_" .. unit)
  end
end

-- ── enemy (monster) auras ──────────────────────────────────────────────────────
-- The mobs we're fighting also carry buffs/debuffs (our DoTs, their enrage/shields). Aura NAMES and
-- ICONS are not Secret Values, so we can read them off enemy unit tokens even on the Midnight client.
-- We track each distinct enemy by GUID (to keep same-named mobs separate) and diff its auras over time,
-- exactly like party members. Enemy unit tokens are transient (target/nameplate/boss), so we sweep them
-- on every sample tick and on UNIT_AURA.
local ENEMY_TOKENS = { "target", "boss1", "boss2", "boss3", "boss4", "boss5" }
local ENEMY_CAP = 16
local function eachEnemyUnit(fn)
  local function consider(u)
    if UnitExists(u) and UnitCanAttack and UnitCanAttack("player", u)
       and (not UnitIsDead or not UnitIsDead(u)) then fn(u) end
  end
  for _, u in ipairs(ENEMY_TOKENS) do consider(u) end
  if C_NamePlate and C_NamePlate.GetNamePlates then
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    if ok and plates then
      for _, np in ipairs(plates) do
        local u = np.namePlateUnitToken or (np.UnitFrame and np.UnitFrame.unit)
        if u then consider(u) end
      end
    end
  end
end
-- record the aura state of one enemy unit, creating its entry on first sight
local function noteEnemy(u)
  if not cur then return end
  local guid = try(UnitGUID, u)
  local name = try(UnitName, u)
  -- an enemy GUID is often a Secret Value here and cannot be a table key; fall back to the name as the
  -- identity (same-named mobs then share one timeline, an acceptable degrade). Skip if neither is usable.
  local key = safeKey(guid) or safeKey(name)
  if not key then return end
  cur.enemies = cur.enemies or {}
  cur._enemyByGuid = cur._enemyByGuid or {}
  cur._es = cur._es or {}
  local e = cur._enemyByGuid[key]
  local t = mono() - cur.startMono
  if not e then
    if #cur.enemies >= ENEMY_CAP then return end
    e = { name = name or "?", guid = safeKey(guid), auras = {}, firstT = t }   -- guid stored only if plain
    cur.enemies[#cur.enemies + 1] = e
    cur._enemyByGuid[key] = e
  end
  local prev = cur._es[key] or {}
  local live, blind, raw = scanAuras(u, prev)
  if blind or vanished(prev, raw, u, true) then      -- unreadable right now: keep the previous state, no diff
    cur.auraBlind = (cur.auraBlind or 0) + 1; F.blindScans = F.blindScans + (blind and 0 or 1)
    return
  end
  for k, a in pairs(live) do
    if not prev[k] then e.auras[#e.auras + 1] = { t = t, gain = true, name = a.name, icon = a.icon, debuff = a.debuff, inst = a.inst, sid = a.sid } end
  end
  for k, a in pairs(prev) do
    if not live[k] then e.auras[#e.auras + 1] = { t = t, gain = false, name = a.name, icon = a.icon, debuff = a.debuff, inst = a.inst, sid = a.sid } end
  end
  trimAura(e.auras)
  cur._es[key] = live
end
local function scanEnemies() if cur then eachEnemyUnit(noteEnemy) end end
local function isEnemyUnit(u)
  return UnitExists(u) and UnitCanAttack and UnitCanAttack("player", u) and true or false
end
-- Rate-limit per-unit aura scans. A UNIT_AURA storm (DoT/HoT ticks across every nameplate in a raid)
-- can fire hundreds of times a second; without this each one ran a full 2x40 aura scan. We cap each unit
-- to ~4 scans/sec here and let the periodic sample tick catch anything skipped. (Unit tokens are plain
-- strings, safe as keys.)
local lastScan = {}
local function throttleOK(u)
  if not u then return false end
  local t = mono()
  if lastScan[u] and (t - lastScan[u]) < 0.25 then return false end
  lastScan[u] = t; return true
end

-- ── readable character stats (best-effort; Secret Values may hide many) ────────
-- resistance schools in paperdoll order → UnitResistance index
local RESI = { { "Arcane", 6 }, { "Fire", 2 }, { "Frost", 4 }, { "Nature", 3 }, { "Shadow", 5 } }

-- CRITICAL for the Midnight/Secret-Values client: combat stats (AP, crit, armor, damage, resist,
-- max HP …) come back as *secret numbers* - you cannot do arithmetic on, compare, store, or format
-- them without tainting/erroring. plain() proves a value is an ordinary number by attempting the
-- arithmetic inside pcall; anything secret (or non-numeric) collapses to nil and is simply dropped.
local function add0(v) return v + 0 end
local function plain(v)
  if type(v) ~= "number" then return nil end
  if issecretvalue and issecretvalue(v) then return nil end
  local ok = pcall(add0, v)                   -- no closure allocation (called ~30x per stat tick)
  return ok and v or nil
end
local function sum3(a, b, c) return (a or 0) + (b or 0) + (c or 0) end
local function plainSum(a, b, c)  -- safe (a+b+c) with secret operands -> nil
  local ok, r = pcall(sum3, a, b, c)
  return ok and r or nil
end

-- Deep-sanitize a value so it is ALWAYS safe to store in SavedVariables. A single bad value (a secret
-- number, a NaN/inf, a function/frame) makes the whole EverbuffDB file unparseable on next load, and
-- WoW then discards ALL of it - that is exactly how a session of fights got wiped. This guarantees the
-- stored copy contains only finite plain numbers, strings, booleans and clean tables.
local function sanitize(v, depth)
  local t = type(v)
  if t == "number" then
    local n = plain(v)                                   -- drop secret numbers
    if n == nil or n ~= n or n == math.huge or n == -math.huge then return nil end  -- drop NaN / inf
    return n
  elseif t == "string" then
    -- strip pipes: this client's SV loader rejects the whole file if a stored string carries the
    -- pipe-heavy item-link escapes (|cn.. |Hitem.. |h.. |r). Names/ids survive; link stays parseable.
    return (v:gsub("|", ""))
  elseif t == "boolean" then
    return v
  elseif t == "table" and (depth or 0) < 12 then
    local out = {}
    for k, val in pairs(v) do
      local tk = type(k)
      if tk == "string" or tk == "number" then
        local cv = sanitize(val, (depth or 0) + 1)
        if cv ~= nil then out[k] = cv end
      end
    end
    return out
  end
  return nil                                             -- functions / userdata / threads → dropped
end

local function snapshotStats()
  local s = {}
  s.level = plain(try(UnitLevel, "player"))
  local _, ilvlEquipped = try(GetAverageItemLevel)      -- (overall, equipped) → keep equipped
  s.ilvl = plain(ilvlEquipped)
  s.hp = plain(try(UnitHealthMax, "player"))            -- secret on Midnight → dropped
  s.mana = plain(try(UnitPowerMax, "player"))

  -- primary attributes STR/AGI/STA/INT/SPI (UnitStat → base, effective, ...)
  local prim = {}
  for i = 1, 5 do local base, eff = try(UnitStat, "player", i); local v = plain(eff) or plain(base); if v then prim[i] = v end end
  s.prim = next(prim) and prim or nil

  -- offensive modifiers
  do local base, pos, neg = try(UnitAttackPower, "player"); s.ap = plainSum(base, pos, neg) end
  do local base, pos, neg = try(UnitRangedAttackPower, "player"); s.rap = plainSum(base, pos, neg) end
  s.crit = plain(try(GetCritChance))
  s.spellCrit = plain(try(GetSpellCritChance))
  s.haste = plain(try(GetHaste)) or plain(try(GetMeleeHaste))
  s.mastery = plain(try(GetMasteryEffect))
  s.hit = plain(try(GetHitModifier))                    -- classic melee hit %
  s.spellPower = plain(try(GetSpellBonusDamage, 6))     -- shadow school as a spellpower proxy where present

  -- weapon (main + off hand damage range and swing speed)
  do
    local ml, mh, ol, oh = try(UnitDamage, "player")
    local ms, os = try(UnitAttackSpeed, "player")
    ml, mh, ol, oh = plain(ml), plain(mh), plain(ol), plain(oh)
    ms, os = plain(ms), plain(os)
    if ml and mh then s.weapon = { mainLow = ml, mainHigh = mh, mainSpeed = ms, offLow = ol, offHigh = oh, offSpeed = os } end
  end

  -- defense / avoidance
  do local base, eff = try(UnitArmor, "player"); s.armor = plain(eff) or plain(base) end
  s.defense = plain(try(UnitDefense, "player")) or (GetCombatRating and plain(try(GetCombatRating, 2)))  -- CR_DEFENSE_SKILL
  s.dodge = plain(try(GetDodgeChance))
  s.parry = plain(try(GetParryChance))
  s.block = plain(try(GetBlockChance))

  -- resistances
  local res = {}
  for _, r in ipairs(RESI) do
    local base, total = try(UnitResistance, "player", r[2])
    local v = plain(total) or plain(base)
    if v and v ~= 0 then res[r[1]] = v end
  end
  s.resist = next(res) and res or nil

  -- keep the entry only if something beyond a bare level came back
  local keys = 0; for _ in pairs(s) do keys = keys + 1 end
  return (keys > 1 or s.level) and s or nil
end

-- coarse signature so we don't store an identical snapshot every tick
local function statSig(s)
  local p = s.prim or {}
  local w = s.weapon or {}
  local r = s.resist or {}
  return table.concat({
    s.level or 0, math.floor(s.ilvl or 0), s.ap or 0, s.rap or 0,
    math.floor((s.crit or 0) * 10), math.floor((s.haste or 0) * 10), s.armor or 0,
    p[1] or 0, p[2] or 0, p[3] or 0, p[4] or 0, p[5] or 0,
    math.floor(w.mainLow or 0), math.floor(w.mainHigh or 0),
    r.Arcane or 0, r.Fire or 0, r.Frost or 0, r.Nature or 0, r.Shadow or 0,
  }, "|")
end

local STAT_CAP = 40
local function recordStat()
  if not cur then return end
  local snap = snapshotStats()
  if not snap then return end
  local sig = statSig(snap)
  if sig == cur._lastStatSig then return end     -- unchanged since last tick → don't duplicate
  cur._lastStatSig = sig
  snap.t = mono() - cur.startMono
  cur.stats[#cur.stats + 1] = snap
  while #cur.stats > STAT_CAP do table.remove(cur.stats, 1) end
end

-- one sampling tick: refresh character stats every tick, but sweep enemy auras at most every 2s (the
-- nameplate sweep is the expensive part; UNIT_AURA already catches most enemy changes between sweeps).
local lastEnemySweep = 0
-- Party deaths. UnitIsDeadOrGhost is a plain boolean even on the Secret-Values client (no arithmetic),
-- so a groupmate's death is safe to read. Checked on UNIT_HEALTH / UNIT_FLAGS for that unit and on the
-- sample tick as a fallback. Each member's deadT (seconds into the fight) is stored on the group entry.
-- A member resurrected and killed again in the same fight dies twice: `deadT` keeps the first second (schema
-- unchanged) and `deaths` every one (#11, WD-1). `_downNow` is runtime state, stripped before the fight is saved.
local function checkMemberDeath(unit)
  if not cur or not cur._memberByUnit then return end
  local m = cur._memberByUnit[unit]
  if not m or m.me then return end
  local ok, dead = pcall(UnitIsDeadOrGhost, unit)
  if not ok then return end
  cur._downNow = cur._downNow or {}
  if dead and not cur._downNow[unit] then
    local t = mono() - cur.startMono
    m.deadT = m.deadT or t
    m.deaths = m.deaths or {}
    m.deaths[#m.deaths + 1] = t
    cur.memberDeaths = (cur.memberDeaths or 0) + 1
  end
  cur._downNow[unit] = dead and true or nil
end
local function checkMemberDeaths()
  if not cur or not cur.group then return end
  for _, m in ipairs(cur.group) do if not m.me and m.unit then checkMemberDeath(m.unit) end end
end
-- Item uses (potions, food, bandages, scrolls, engineering). There is no item-use event, but every use
-- casts a spell, and that spell is NOT in the player's spellbook. So: UNIT_SPELLCAST_SUCCEEDED for the
-- player whose spell id is not a known spell = an item was used. Own casts are plain on the beta client.
-- Per fight: `uses = { { t, name, sid, icon } }`; persisted tally `db.itemUses[name] = count` for the desktop.
local USES_CAP = 60
local function spellKnown(sid)
  if IsPlayerSpell then local ok, k = pcall(IsPlayerSpell, sid); if ok and k then return true end end
  if IsSpellKnown then local ok, k = pcall(IsSpellKnown, sid); if ok and k then return true end end
  return false
end
local function noteItemUse(sid)
  sid = plain(sid); if not sid or spellKnown(sid) then return end
  local name, icon
  if GetSpellInfo then local n, _, ic = try(GetSpellInfo, sid); name, icon = safeKey(n), safeKey(ic) end
  if not name and C_Spell and C_Spell.GetSpellName then name = safeKey(try(C_Spell.GetSpellName, sid)) end
  if not icon and C_Spell and C_Spell.GetSpellTexture then icon = safeKey(try(C_Spell.GetSpellTexture, sid)) end
  if not name then return end
  -- internal effects the client casts on the player (LOGINEFFECT at every login) are not item uses
  if name:match("^[%u%d_]+$") then return end
  if ns.DB then
    ns.DB.character.itemUses = ns.DB.character.itemUses or {}
    ns.DB.character.itemUses[name] = (ns.DB.character.itemUses[name] or 0) + 1
  end
  if cur then
    cur.uses = cur.uses or {}
    cur.uses[#cur.uses + 1] = { t = mono() - cur.startMono, name = name, sid = sid, icon = icon }
    while #cur.uses > USES_CAP do table.remove(cur.uses, 1) end
  end
end
local function sampleTick()
  recordStat()
  checkMemberDeaths()
  local t = mono()
  if t - lastEnemySweep >= 2 then lastEnemySweep = t; scanEnemies() end
end

-- ── party / raid roster at the moment of the fight ─────────────────────────────
-- returns { {name, class, race, level, unit, me}, ... }; unit is the token we can read auras from.
local function snapshotGroup()
  local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
  if n <= 1 then return nil end                  -- solo: no group to record
  local raid = IsInRaid and IsInRaid()
  local unit = raid and "raid" or "party"
  local out = {}
  local function add(u, me)
    if not UnitExists(u) then return end
    local name = UnitName(u); if not name then return end
    local _, class = try(UnitClass, u)
    local race = try(UnitRace, u)
    out[#out + 1] = { name = name, class = class, race = race, level = plain(try(UnitLevel, u)), unit = u, me = me or nil }
  end
  -- party excludes the player from party1..N; raid includes everyone in raid1..N
  if not raid then add("player", true) end
  for i = 1, n do add(unit .. i, raid and UnitIsUnit(unit .. i, "player") or nil) end
  return (#out > 0) and out or nil
end

-- ── fight lifecycle ────────────────────────────────────────────────────────────
local function addFoe(name)
  name = safeKey(name)   -- an enemy name is a Secret Value here; drop it rather than crash on compare
  if not cur or not name or name == "" then return end
  for _, f2 in ipairs(cur.foes) do if f2 == name then return end end
  cur.foes[#cur.foes + 1] = name
end

-- Spec and talent build at the pull. Retail and Midnight: the specialization and the loadout import string.
-- Classic trees: the tab with most points and the split "31/20/0". A client that defines GetSpecialization but
-- answers nothing (the classic clients can) falls through to the trees; before #11 it recorded neither.
-- GetTalentTabInfo answers (name, icon, points) on Era, (id, name, description, icon, points) on the later
-- classic clients, or a table; points missing means summing the ranks of GetTalentInfo (rank is the 5th).
local function tabPoints(tab)
  local r = { pcall(GetTalentTabInfo, tab) }
  if not r[1] then return nil, nil end
  local nm, pts
  if type(r[2]) == "table" then nm, pts = r[2].name, r[2].pointsSpent
  elseif type(r[2]) == "number" and type(r[3]) == "string" then nm, pts = r[3], r[6]
  else nm, pts = r[2], r[4] end
  pts = plain(pts)
  if type(pts) ~= "number" and GetNumTalents and GetTalentInfo then
    local okN, n = pcall(GetNumTalents, tab)
    n = okN and plain(n)
    if type(n) == "number" then
      pts = 0
      for i = 1, n do
        local t = { pcall(GetTalentInfo, tab, i) }
        pts = pts + ((t[1] and plain(t[6])) or 0)
      end
    end
  end
  return safeKey(nm), pts
end
local function specAndTalents()
  local spec, talents
  if GetSpecialization and GetSpecializationInfo then
    local ok, i = pcall(GetSpecialization)
    i = ok and plain(i)
    if type(i) == "number" and i > 0 then
      local ok2, _, name = pcall(GetSpecializationInfo, i)
      if ok2 then spec = safeKey(name) end
    end
    if C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_Traits and C_Traits.GenerateImportString then
      local cfg = try(C_ClassTalents.GetActiveConfigID)
      local str = cfg and try(C_Traits.GenerateImportString, cfg)
      if type(str) == "string" and #str > 0 and #str < 400 then talents = str end
    end
  end
  if not spec and not talents and GetNumTalentTabs and GetTalentTabInfo then
    local okT, tabs = pcall(GetNumTalentTabs)
    tabs = okT and plain(tabs)
    if type(tabs) == "number" and tabs > 0 then
      local best, bestPts, split = nil, 0, {}
      for tab = 1, tabs do
        local nm, pts = tabPoints(tab)
        if nm and pts and pts > bestPts then best, bestPts = nm, pts end
        split[#split + 1] = tostring(pts or 0)
      end
      spec = best                                         -- nil while no point is spent
      talents = table.concat(split, "/")                  -- "31/20/0": the build at the pull
    end
  end
  return spec, talents
end
F.specAndTalents = specAndTalents   -- tests

local function beginFight()
  if cur then return end
  cur = {
    startEpoch = now(), startMono = mono(),
    zone = (GetRealZoneText and GetRealZoneText()) or "World",
    level = try(UnitLevel, "player"),
    foes = {}, auras = {}, gear = { swaps = {} }, stats = {},
    outcome = "fled",         -- default; overwritten by kill/wipe/death as they happen
  }
  -- Identity + correlation keys for the desktop (backlog 1d). fightSeq alone resets when SavedVariables
  -- are lost, so each fight gets a globally unique uid; we also stamp WHO fought (SV is account-wide),
  -- the client LOCAL wall-clock (the combat-log FILE is stamped in local time, not server time), and the
  -- instance/difficulty so a fight joins cleanly to its slice of the log.
  pcall(function() cur.spec, cur.talents = specAndTalents() end)
  pcall(function()
    cur.schema = 1
    cur.startLocal = time()
    cur.startLocalHi = CAL_EPOCH + (cur.startMono - CAL_MONO)   -- fractional local clock (video anchor)
    cur.player = safeKey(try(UnitName, "player"))
    cur.realm = try(GetRealmName)
    local sess = ns.Recorder and ns.Recorder.active and ns.Recorder.active()
    cur.session = sess and sess.id or nil
    local ok, _, itype, diff, _, _, _, _, mapID = pcall(GetInstanceInfo)
    if ok then cur.instanceType = itype; cur.difficultyID = plain(diff); cur.instanceMapID = plain(mapID) end
    cur.uid = ("%s-%s-%d-%04x"):format(cur.player or "?", cur.realm or "?", cur.startEpoch or 0, math.random(0, 65535))
    -- where the pull happened (map id + normalized coords), for the Location column and desktop maps
    if C_Map and C_Map.GetBestMapForUnit then
      local m = C_Map.GetBestMapForUnit("player")
      if m then
        cur.map = plain(m)
        local pos = C_Map.GetPlayerMapPosition(m, "player")
        if pos and pos.GetXY then
          local px, py = pos:GetXY()
          if plain(px) and plain(py) then cur.x, cur.y = math.floor(px * 1e4) / 1e4, math.floor(py * 1e4) / 1e4 end
        end
      end
    end
  end)
  -- pull-time captures are protected: if any read throws, the fight still exists and endFight stores it
  pcall(function()
    cur.gear.initial = snapshotGear()
    cur._worn = {}                              -- track live worn items so swaps record the true "from"
    for slot, it in pairs(cur.gear.initial) do cur._worn[slot] = it end
    cur.group = snapshotGroup()
    cur.enemies = {}                            -- per-monster aura timelines (seeded below)
    cur._auraSet = scanAuras("player")
    for _, a in pairs(cur._auraSet) do          -- seed the timeline with everything up at pull (t = 0)
      cur.auras[#cur.auras + 1] = { t = 0, gain = true, name = a.name, icon = a.icon, debuff = a.debuff, inst = a.inst, sid = a.sid, atPull = true }
    end
    -- Per-member aura timelines only for party-sized groups (<=6). In a raid this would multiply the
    -- stored aura data by up to 40x for little value; there self + enemy timelines are what matter.
    if cur.group then
      cur._memberByUnit = {}                     -- unit token -> member, for O(1) UNIT_AURA / death lookup
      for _, m in ipairs(cur.group) do cur._memberByUnit[m.unit] = m end
    end
    if cur.group and #cur.group <= 6 then
      cur.memberAuras = {}
      for _, m in ipairs(cur.group) do
        if not m.me then
          local set = scanAuras(m.unit)
          local log = {}
          for _, a in pairs(set) do log[#log + 1] = { t = 0, gain = true, name = a.name, icon = a.icon, debuff = a.debuff, inst = a.inst, sid = a.sid, atPull = true } end
          cur.memberAuras[m.name] = log
          cur["_ms_" .. m.unit] = set            -- working set for this unit's diffs
        end
      end
    end
    if UnitExists("target") and UnitCanAttack and UnitCanAttack("player", "target") then addFoe(UnitName("target")) end
    scanEnemies()   -- seed enemy aura timelines at pull
    recordStat()
  end)
  if statTicker then statTicker:Cancel() end
  statTicker = C_Timer.NewTicker(F.sampleInterval(), sampleTick)
end

local function endFight()
  if not cur then return end
  if statTicker then statTicker:Cancel(); statTicker = nil end
  -- CRITICAL: run the closing captures in a protected call. If any read throws (e.g. a secret value
  -- slips through), the fight must STILL be stored - an error here is exactly what silently lost data
  -- before. We pcall the captures and always fall through to the store below.
  pcall(function()
    diffAuras()                     -- capture whatever fell off at the end
    recordStat()
    scanEnemies()                   -- final enemy aura diffs
    if cur.group then               -- final member aura diffs
      for _, m in ipairs(cur.group) do
        if not m.me then diffMember(m.unit) end
      end
    end
    -- names hidden during combat are readable now: backfill the timelines
    backfillAuras(cur.auras, cur._auraSet)
    if cur.group and cur.memberAuras then
      for _, m in ipairs(cur.group) do
        if not m.me then backfillAuras(cur.memberAuras[m.name], cur["_ms_" .. m.unit]) end
      end
    end
  end)
  cur.endEpoch = now(); cur.endMono = mono()
  cur.duration = math.max(0, cur.endMono - cur.startMono)
  cur.endLocalHi = CAL_EPOCH + (cur.endMono - CAL_MONO)
  -- resolve the result: PLAYER_DEAD / ENCOUNTER_END may have set it already; otherwise infer a kill
  -- when we faced something and lived, else leave "fled" (evade / disengage).
  if cur.outcome == "fled" and #cur.foes > 0 then cur.outcome = "kill" end
  -- strip all working sets so they don't persist
  if cur.group then
    for _, m in ipairs(cur.group) do
      if not m.me then cur["_ms_" .. m.unit] = nil end
    end
  end
  cur._auraSet = nil
  cur._lastStatSig = nil
  cur._enemyByGuid = nil          -- working sets: never persist
  cur._es = nil
  cur._worn = nil
  cur._memberByUnit = nil
  cur._downNow = nil
  if ns.DB then
    ns.DB.combat.fights = ns.DB.combat.fights or {}
    -- persistent, monotonic id across sessions: the key the desktop will ack so we can prune
    -- exactly what has already been uploaded to the backend (upload-driven cleanup, TBD).
    ns.DB.combat.fightSeq = (ns.DB.combat.fightSeq or 0) + 1
    cur.id = ns.DB.combat.fightSeq
    cur.uploaded = false      -- flipped true by the desktop uploader once shipped; prune on next load
    -- store a SANITIZED copy so a stray secret/NaN/inf value can never corrupt the SavedVariables file
    ns.DB.combat.fights[#ns.DB.combat.fights + 1] = sanitize(cur)
    if ns.Recorder and ns.Recorder.bump then ns.Recorder.bump("fights") end
    while #ns.DB.combat.fights > FIGHT_CAP do table.remove(ns.DB.combat.fights, 1) end
    -- until the desktop ack channel exists nothing ever gets pruned by upload, so warn ONCE per session
    -- before the oldest un-acked fights start rolling off the cap (silent data loss otherwise)
    if not F._capWarned and #ns.DB.combat.fights >= FIGHT_CAP - 25 and ns.msg then
      F._capWarned = true
      ns.msg(("fight history is nearly full (%d of %d). Oldest fights roll off at the cap until the desktop app syncs them."):format(#ns.DB.combat.fights, FIGHT_CAP))
    end
  end
  cur = nil

  sessionCount = sessionCount + 1
  lastCombatEnd = GetTime()   -- the watchdog (flushTick) handles the flush / reminder from here
end

-- called by Emitter when it resolves the outcome (kill/wipe) so the two agree
function F.setOutcome(outcome, bossName)
  if not cur then return end
  cur.outcome = outcome
  if bossName then cur.bossName = bossName; addFoe(bossName) end
end

function F.list() return (ns.DB and ns.DB.combat.fights) or {} end
function F.capInfo() return #F.list(), FIGHT_CAP end

-- Upload-driven cleanup hook (run at load): drop fights the desktop client has already shipped to the
-- backend. The desktop signals this either per-fight (fight.uploaded = true) or via a high-water mark
-- (ns.DB.combat.uploadedThrough = <last uploaded fight id>). Until that handshake ships this is a safe no-op.
function F.pruneUploaded()
  local list = ns.DB and ns.DB.combat.fights
  if not list then return 0 end
  local through = tonumber(ns.DB.combat.uploadedThrough) or 0
  local removed = 0
  for i = #list, 1, -1 do
    local f = list[i]
    if f.uploaded == true or (f.id and f.id <= through) then table.remove(list, i); removed = removed + 1 end
  end
  return removed
end

-- ── events ──────────────────────────────────────────────────────────────────
ef:SetScript("OnEvent", function(_, event, ...)
  if event == "PLAYER_REGEN_DISABLED" then
    if modal and modal:IsShown() then modal:Hide(); modalInterrupted = true end   -- reminder must not be up during a fight
    beginFight()
  elseif event == "PLAYER_REGEN_ENABLED" then
    endFight()
    -- re-check shortly after the settle period so an interrupted reminder returns promptly, not on the next 15s tick
    if C_Timer and C_Timer.After then C_Timer.After(SETTLE_SECS + 1, flushTick) end
  elseif event == "UNIT_AURA" then
    local u = ...
    if throttleOK(u) then                                    -- rate-limit the UNIT_AURA storm
      if u == "player" then diffAuras()
      elseif cur and isEnemyUnit(u) then noteEnemy(u)        -- a monster's buff/debuff changed
      elseif cur and cur.memberAuras then diffMember(u) end
    end
  elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
    local u, _, sid = ...
    if u == "player" then noteItemUse(sid) end
  elseif event == "UNIT_HEALTH" or event == "UNIT_FLAGS" then
    local u = ...
    if cur and cur._memberByUnit and u then checkMemberDeath(u) end
  elseif event == "PLAYER_EQUIPMENT_CHANGED" then
    if cur then
      local slot = ...
      local prev = cur._worn and cur._worn[slot]      -- what was in the slot just before this change
      local to = itemAt(slot)
      cur.gear.swaps[#cur.gear.swaps + 1] = {
        t = mono() - cur.startMono, slot = slot, name = SLOTS[slot] or ("slot " .. tostring(slot)),
        from = prev, to = to,
      }
      while #cur.gear.swaps > 60 do table.remove(cur.gear.swaps, 1) end   -- bound (was unbounded)
      cur._worn = cur._worn or {}; cur._worn[slot] = to
    end
  elseif event == "PLAYER_TARGET_CHANGED" then
    if cur and UnitExists("target") and UnitCanAttack and UnitCanAttack("player", "target")
       and (not UnitIsDead or not UnitIsDead("target")) then
      addFoe(UnitName("target"))
    end
  elseif event == "ENCOUNTER_START" then
    if not cur then beginFight() end
    if cur then
      local eid, ename = ...
      cur.encounterID = plain(eid)           -- numeric id: joins to the log file's ENCOUNTER_START line
      cur.bossName = ename; addFoe(cur.bossName)
    end
  elseif event == "ENCOUNTER_END" then
    -- args: encounterID, name, difficultyID, groupSize, success
    local name = select(2, ...)
    local success = select(5, ...)
    if cur then cur.outcome = (success == 1) and "kill" or "wipe"; addFoe(name) end
  elseif event == "PLAYER_DEAD" then
    if cur then
      cur.outcome = "death"
      -- who killed us: best-effort. If no foe was captured during the fight, take the current target
      -- (usually the mob that killed you). Exact killing blow needs the combat-log file (secret here).
      -- addFoe guards the (secret) name itself; don't compare it here or we crash on a secret string
      if #cur.foes == 0 and UnitExists("target") then addFoe(UnitName("target")) end
    end
  end
end)

for _, ev in ipairs({
  "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "UNIT_AURA",
  "PLAYER_EQUIPMENT_CHANGED", "PLAYER_TARGET_CHANGED",
  "ENCOUNTER_START", "ENCOUNTER_END", "PLAYER_DEAD",
  "UNIT_HEALTH", "UNIT_FLAGS",                     -- groupmate deaths (boolean read only, never health math)
  "UNIT_SPELLCAST_SUCCEEDED",                      -- item uses (casts that are not known spells)
}) do ef:RegisterEvent(ev) end

-- auto-save watchdog: every 15s, flush unsaved fights to disk if it's a safe moment (see flushTick).
-- (A normal /logout or /reload already flushes SavedVariables; this covers everything in between.)
flushTicker = C_Timer.NewTicker(15, flushTick)

-- ── test exports: headless luajit tests in tests/ read these; no effect in-game ──
ns._test = ns._test or {}
ns._test.plain, ns._test.plainSum, ns._test.sanitize = plain, plainSum, sanitize
ns._test.trimAura, ns._test.safeKey, ns._test.statSig = trimAura, safeKey, statSig
ns._test.AURA_CAP = AURA_CAP
ns._test.currentFight = function() return cur end
ns._test.flushTick = flushTick
ns._test.scanAuras = scanAuras
ns._test.saveModal = function() return modal end
