-- Everbuff.GG · Emitter.lua - the in-game notification flag and the real-time event feed.
--
-- WHY: some moments are invisible or late in the combat log (level-up, zone change, quest accepted or
-- turned in, dungeon enter and leave, death and release). This file watches for them and does two things:
--   1. shows the player a FLAG: the Everbuff.GG mark, which tints RED while in combat, with a panel that
--      unfurls beside it carrying a human line colored by event kind (tan level-up, lagoon travel and
--      quests, ember death and wipe, green kill, tan loot). The flag sits in one of four corners
--      (settings.emitCorner) and can be dragged, scaled, dimmed or hidden;
--   2. feeds the same events to the timeline (story events in the save file) with the session id, the
--      time, the zone and the coordinates, which is what the desktop and the backend read.
--
-- Founder rule: nothing is ever drawn on screen for a machine to read except the flag itself. No color
-- strips, no encoded cells. The desktop's real-time channel is OCR of the flag's text; how the flag's
-- machine line is rendered for that is decided in everbuff-wow-addon issue #10 before it is built. The
-- short "machine" line built below is the compact label for the event kind in the panel and the timeline.

local ADDON, ns = ...

local Emitter = {}
ns.Emitter = Emitter

-- loot collected THIS session (in-memory only, so garbage never bloats SavedVariables). Shown in the
-- Loot tab; the video/OCR is the durable, video-correlated record.
local sessionLoot = {}

local SHOW_SECS = 2.6
-- everbuff.gg brand kit (tokens.json)
-- The flag's colors are the desktop's screen-reading contract (it finds the flag and reads combat from its red),
-- so they are fixed here on purpose and do not follow the design tokens (wow-addon #19).
local INK  = { 0.067, 0.067, 0.067 }   -- n1 #111111 charcoal
local GOLD = { 1.00, 0.82, 0.00 }      -- coin gold #FFD100 (tan left the interface)
local LAGOON = { 0.357, 0.608, 0.941 } -- data blue #5B9BF0
local EMBER = { 0.898, 0.282, 0.302 } -- danger #E5484D (ember left the interface)
local GREEN = { 0.298, 0.765, 0.541 } -- success #4CC38A
local RED = { 1.00, 0.42, 0.435 }      -- danger #FF6B6F
local BONE = { 0.953, 0.957, 0.961 }   -- n10 #F3F4F5
local STEEL = { 0.55, 0.62, 0.74 }
local COLORS = {
  LEVELUP = GOLD, ZONE = LAGOON, DUNGEON = STEEL, DUNGEONLEAVE = STEEL,
  QUESTACCEPT = LAGOON, QUESTDONE = LAGOON, DISCOVERY = LAGOON, SKILLUP = LAGOON,
  BOSS = EMBER, KILL = GREEN, WIPE = RED, DEATH = RED, ALIVE = LAGOON, LOOT = GOLD, REWARD = GOLD,
  ACHIEV = GOLD, SPELL = LAGOON, REP = GOLD, FLIGHT = STEEL,
  FIRSTZONE = LAGOON, ROSTERJOIN = STEEL, ROSTERLEAVE = STEEL, BROKEN = EMBER,
  COLLECT = GOLD, PROFTIER = GOLD, FLIGHTTRIP = STEEL, RECIPE = GOLD, UPGRADE = GOLD,
}
local CORNERS = {
  TOPLEFT = "TOPLEFT", TOPRIGHT = "TOPRIGHT", BOTTOMLEFT = "BOTTOMLEFT", BOTTOMRIGHT = "BOTTOMRIGHT",
}
local MARK = "Interface\\AddOns\\EverbuffJournal\\media\\mark"   -- the white everbuff.gg mark, both chevrons cut out (0.9.11)

-- class color (not a Secret Value - safe to read). Falls back to gold before login.
local classR, classG, classB = GOLD[1], GOLD[2], GOLD[3]
local function refreshClassColor()
  if not UnitClass then return end
  local _, class = UnitClass("player")
  local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
  if c then classR, classG, classB = c.r, c.g, c.b end
end

-- ── the flag: the Everbuff.GG mark; it tints red while you are in combat ────────────────────────
local flag = CreateFrame("Frame", "EverbuffFlag", UIParent)
flag:SetSize(40, 40)
flag:SetFrameStrata("FULLSCREEN_DIALOG"); flag:SetFrameLevel(10000)   -- above the UI, below game tooltips
local emblem = flag:CreateTexture(nil, "ARTWORK")      -- the mark, always visible (keeps the frame)
emblem:SetPoint("CENTER"); emblem:SetSize(30, 30); emblem:SetTexture(MARK)
-- combat is shown by tinting the whole mark red (no swords): clean and unmistakable.
local inCombat = false
local combatFoe = nil   -- best-effort name of the mob we're fighting, for context on events during combat
local combatFoeElite = false   -- was that foe an elite/rare/boss? decides whether its kill flags on-screen
local lastKillName, lastKillAt = nil, 0   -- de-dup regular-mob kills vs boss ENCOUNTER_END kills
-- fight events that should also appear on the Combat Log tab (recorded as session markers)
local COMBAT_KINDS = { BOSS = true, KILL = true, WIPE = true, DEATH = true, ALIVE = true }
-- high-value journey events: after these we nudge a disconnect-save so they can't be lost to a crash
local MILESTONE_KINDS = {
  LEVELUP = true, DEATH = true, ACHIEV = true, WIPE = true, REWARD = true, LOOT = true,
  REP = true, FLIGHT = true, FIRSTZONE = true, BROKEN = true, COLLECT = true, PROFTIER = true, RECIPE = true, UPGRADE = true,
}
-- On-screen notification groups the player can mute in Settings. Muting only affects the on-screen
-- flag; every event is still RECORDED in the Timeline. LEVELUP / DEATH / WIPE / ALIVE are never muted.
local FLAG_GROUP_OF = {}
for g, kinds in pairs({
  travel   = { "ZONE", "DUNGEON", "DUNGEONLEAVE", "DISCOVERY", "FLIGHT", "FIRSTZONE", "FLIGHTTRIP" },
  quests   = { "QUESTACCEPT", "QUESTDONE", "REWARD" },
  kills    = { "KILL", "BOSS" },
  loot     = { "LOOT" },
  progress = { "SKILLUP", "SPELL", "REP", "ACHIEV", "COLLECT", "PROFTIER", "RECIPE", "UPGRADE" },
}) do for _, k in ipairs(kinds) do FLAG_GROUP_OF[k] = g end end
local function flagMuted(kind)
  local g = FLAG_GROUP_OF[kind]; if not g then return false end
  local m = ns.DB and ns.DB.settings and ns.DB.settings.flagMute
  return (m and m[g]) and true or false
end
-- best-effort location stamp for an event (zone/subzone + normalized map coords) for desktop map correlation
local function locStamp()
  local s = {}
  s.zone = (GetRealZoneText and GetRealZoneText()) or nil
  local sub = GetSubZoneText and GetSubZoneText(); if sub and sub ~= "" then s.sub = sub end
  if C_Map and C_Map.GetBestMapForUnit then
    local ok, m = pcall(C_Map.GetBestMapForUnit, "player")
    if ok and m then
      s.map = m
      local ok2, pos = pcall(C_Map.GetPlayerMapPosition, m, "player")
      if ok2 and pos and pos.GetXY then
        local x, y = pos:GetXY()
        if x and y then s.x = math.floor(x * 1e4) / 1e4; s.y = math.floor(y * 1e4) / 1e4 end
      end
    end
  end
  return s
end
local COMBAT_TINT = { 1.0, 0.34, 0.30 }
local function paintFlag() end   -- class color isn't used for the icon in this style
-- an ENEMY unit's NAME is a Secret Value on this client; comparing or concatenating it throws. safeStr
-- returns the value only if it is an ordinary usable string, else nil, so foe handling can degrade to
-- a generic label instead of crashing. (Enemy names are recovered from the combat-log FILE desktop-side.)
-- Probe order matters: on the 12.0 client a secret string CONCATENATES without error (the result is
-- itself secret) and only throws on COMPARISON; the old concat-only probe let a secret foe name through
-- to `name ~= ""` (dungeon kill, 0.9.1). So: ask the client (issecretvalue), then compare, then concat.
local function cat0(v) return v == "" or (v .. "") end
local function safeStr(v)
  if type(v) ~= "string" then return nil end
  if issecretvalue and issecretvalue(v) then return nil end
  local ok = pcall(cat0, v)                   -- no closure allocation (runs on every event/loot line)
  return ok and v or nil
end
-- record the current target as our combat foe if it's a hostile, living unit
local function noteFoe()
  if UnitExists("target") and UnitCanAttack and UnitCanAttack("player", "target")
     and (not UnitIsDead or not UnitIsDead("target")) then
    combatFoe = safeStr(UnitName("target"))   -- nil if the name is secret; we fall back to "an enemy"
    local cls = UnitClassification and UnitClassification("target")
    combatFoeElite = (cls == "elite" or cls == "rareelite" or cls == "rare" or cls == "worldboss")
  end
end
local function setCombat(on)
  inCombat = on
  if on then
    emblem:SetVertexColor(COMBAT_TINT[1], COMBAT_TINT[2], COMBAT_TINT[3])
    noteFoe()             -- capture whom we engaged
  else
    emblem:SetVertexColor(1, 1, 1)
    -- keep combatFoe as the last foe so an event firing just as combat ends still has context
  end
end

-- the flag is interactive: left-click opens the config panel, right-click walks it around the corners.
flag:EnableMouse(true)
flag:SetScript("OnMouseUp", function(_, btn)
  if flag.dragging then return end
  if ns.blockedInCombat() then return end
  if btn == "RightButton" then
    if ns.DB and ns.DB.settings and ns.DB.settings.flagPos then Emitter.setFlagPos(nil); return end   -- dragged: snap back first
    local order = { "TOPLEFT", "TOPRIGHT", "BOTTOMRIGHT", "BOTTOMLEFT" }
    local cur = (ns.DB and ns.DB.settings and ns.DB.settings.emitCorner) or "TOPLEFT"
    local i = 1; for k, v in ipairs(order) do if v == cur then i = k end end
    Emitter.setCorner(order[(i % #order) + 1])
  elseif ns.UI and ns.UI.Open then
    ns.UI.Open("Home")   -- left-click opens the landing dashboard
  elseif ns.msg then
    ns.msg("settings panel not loaded")
  end
end)
flag:SetScript("OnEnter", function(self)
  emblem:SetSize(34, 34)                       -- gentle hover pop (static, no flashing)
  -- anchor the tooltip clear of the icon: below it for top corners, above it for bottom corners
  local key = (ns.DB and ns.DB.settings and ns.DB.settings.emitCorner) or "TOPLEFT"
  GameTooltip:SetOwner(self, "ANCHOR_NONE")
  GameTooltip:ClearAllPoints()
  if key == "TOPRIGHT" then GameTooltip:SetPoint("TOPRIGHT", self, "BOTTOMRIGHT", 0, -6)
  elseif key == "BOTTOMLEFT" then GameTooltip:SetPoint("BOTTOMLEFT", self, "TOPLEFT", 0, 6)
  elseif key == "BOTTOMRIGHT" then GameTooltip:SetPoint("BOTTOMRIGHT", self, "TOPRIGHT", 0, 6)
  else GameTooltip:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -6) end
  GameTooltip:AddLine("everbuff.gg")
  GameTooltip:AddLine("Left-click  ·  open Everbuff", 0.8, 0.8, 0.8)
  GameTooltip:AddLine("Drag  ·  move anywhere", 0.8, 0.8, 0.8)
  GameTooltip:AddLine("Right-click  ·  snap to a corner", 0.8, 0.8, 0.8)
  GameTooltip:Show()
end)
flag:SetScript("OnLeave", function() emblem:SetSize(30, 30); GameTooltip:Hide() end)

-- ── the event panel: unfurls beside the flag on events ─────────────────────────
local panel = CreateFrame("Frame", "EverbuffToast", UIParent)
panel:SetSize(320, 40); panel:SetFrameStrata("FULLSCREEN_DIALOG"); panel:SetFrameLevel(9999)
local bg = panel:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints()
bg:SetColorTexture(INK[1], INK[2], INK[3], 0.88)
local sheen = panel:CreateTexture(nil, "BORDER"); sheen:SetAllPoints(); sheen:SetColorTexture(1, 1, 1, 0)   -- no sheen (#36)
local accent = panel:CreateTexture(nil, "ARTWORK"); accent:SetWidth(3)  -- flag-side color tick
local hero = panel:CreateFontString(nil, "OVERLAY")
hero:SetFont("Interface\\AddOns\\EverbuffJournal\\media\\fonts\\ChakraPetch-SemiBold.ttf", 15, "")   -- no serif, no outline (#36)
hero:SetShadowColor(0, 0, 0, 0.8); hero:SetShadowOffset(1, -1)
panel:Hide()

local ICON_INSET = 44   -- keep text clear of the corner icon
-- flag prefs: size (the desktop reads the flag, so a known size helps OCR) and a hide switch (which
-- also silences toasts: nothing to read means nothing to draw). Both persisted in settings.
local function flagPrefs()
  local st = (ns.DB and ns.DB.settings) or {}
  local sc = tonumber(st.flagScale) or 1
  if sc < 0.7 then sc = 0.7 elseif sc > 1.5 then sc = 1.5 end
  local al = tonumber(st.flagAlpha) or 1
  if al < 0.3 then al = 0.3 elseif al > 1 then al = 1 end
  return sc, st.flagHidden and true or false, al
end
local function applyFlagPrefs()
  local sc, hidden, al = flagPrefs()
  flag:SetScale(sc); panel:SetScale(sc); flag:SetAlpha(al)
  if hidden then flag:Hide(); panel:Hide() else flag:Show() end
end
Emitter.applyFlagPrefs = applyFlagPrefs
function Emitter.setFlagScale(v)
  if ns.blockedInCombat() then return end
  v = tonumber(v) or 1
  if ns.DB and ns.DB.settings then ns.DB.settings.flagScale = math.floor(v * 20 + 0.5) / 20 end
  applyFlagPrefs()
end
function Emitter.setFlagAlpha(v)
  if ns.blockedInCombat() then return end
  v = tonumber(v) or 1
  if v < 0.3 then v = 0.3 elseif v > 1 then v = 1 end
  if ns.DB and ns.DB.settings then ns.DB.settings.flagAlpha = math.floor(v * 20 + 0.5) / 20 end
  applyFlagPrefs()
end
function Emitter.setFlagHidden(on)
  if ns.blockedInCombat() then return end
  if ns.DB and ns.DB.settings then ns.DB.settings.flagHidden = on and true or nil end
  applyFlagPrefs()
end
function Emitter.flagHidden() local _, h = flagPrefs(); return h end
local function place()
  local key = (ns.DB and ns.DB.settings and ns.DB.settings.emitCorner) or "TOPLEFT"
  local corner = CORNERS[key] or "TOPLEFT"
  -- a dragged flag (settings.flagPos) wins over the corner; the text still unfurls away from the
  -- nearer screen edge so it never runs off screen
  local pos = ns.DB and ns.DB.settings and ns.DB.settings.flagPos
  if pos and type(pos.point) == "string" then corner = pos.point end
  local isRight = corner:find("RIGHT") ~= nil
  local top = corner:find("TOP") ~= nil
  -- panel pinned flush to the corner (or at the dragged spot); the icon is FIXED on the corner side and
  -- vertically centered; the single text line sits inward, vertically centered, so the icon never drifts.
  panel:ClearAllPoints()
  if pos and type(pos.point) == "string" then panel:SetPoint(pos.point, UIParent, pos.point, pos.x or 0, pos.y or 0)
  else panel:SetPoint(corner, UIParent, corner, 0, 0) end
  flag:ClearAllPoints(); accent:ClearAllPoints(); hero:ClearAllPoints()
  accent:SetWidth(3); accent:SetHeight(20)
  if isRight then
    flag:SetPoint("RIGHT", panel, "RIGHT", 0, 0)
    accent:SetPoint("RIGHT", panel, "RIGHT", -(ICON_INSET - 5), 0)
    hero:SetPoint("RIGHT", panel, "RIGHT", -ICON_INSET, 0); hero:SetPoint("LEFT", panel, "LEFT", 12, 0)
    hero:SetJustifyH("RIGHT")
  else
    flag:SetPoint("LEFT", panel, "LEFT", 0, 0)
    accent:SetPoint("LEFT", panel, "LEFT", (ICON_INSET - 5), 0)
    hero:SetPoint("LEFT", panel, "LEFT", ICON_INSET, 0); hero:SetPoint("RIGHT", panel, "RIGHT", -12, 0)
    hero:SetJustifyH("LEFT")
  end
end
place()

-- free-drag: drag the flag anywhere; the toast panel travels with it. Right-click snaps back to a corner.
panel:SetMovable(true); panel:SetClampedToScreen(true)
flag:RegisterForDrag("LeftButton")
flag:SetScript("OnDragStart", function()
  if ns.blockedInCombat() then return end
  panel:StartMoving(); flag.dragging = true
end)
flag:SetScript("OnDragStop", function()
  if not flag.dragging then return end   -- a drag refused in combat never started
  panel:StopMovingOrSizing(); flag.dragging = nil
  -- store the spot relative to the nearest screen corner so the text unfurls inward
  local cx, cy = panel:GetCenter(); local sw, sh = UIParent:GetWidth() or 0, UIParent:GetHeight() or 0
  if not (cx and cy) then return end
  local right, top = cx > sw / 2, cy > sh / 2
  local point = (top and "TOP" or "BOTTOM") .. (right and "RIGHT" or "LEFT")
  local x = right and ((panel:GetRight() or cx) - sw) or (panel:GetLeft() or cx)
  local y = top and ((panel:GetTop() or cy) - sh) or (panel:GetBottom() or cy)
  Emitter.setFlagPos(point, x, y)
end)
function Emitter.setFlagPos(point, x, y)
  if ns.blockedInCombat() then return end
  if ns.DB and ns.DB.settings then ns.DB.settings.flagPos = point and { point = point, x = x or 0, y = y or 0 } or nil end
  place()
end

-- ── curated toast (human) ──
local hideAt = 0
local queue = {}
local TOAST_PRIORITY = { LEVELUP = true, DEATH = true, WIPE = true, BOSS = true, ACHIEV = true }
local function show(kind, human, rec)
  if Emitter.flagHidden() then return end      -- hidden flag: nothing on screen (still recorded)
  -- the moment it reaches the screen, on the client's own clock: the desktop sees the same notification in
  -- the video, so the pair is an alignment anchor (everbuff-desktop #72). Data only; nothing on screen changes.
  if rec then rec.shown = math.floor(GetTime() * 1000 + 0.5) / 1000 end
  local col = COLORS[kind] or GOLD
  accent:SetColorTexture(col[1], col[2], col[3], 1)
  hero:SetTextColor(BONE[1], BONE[2], BONE[3]); hero:SetText(human or kind)   -- the kind's color is the tick only
  panel:SetWidth(math.min(600, (hero:GetStringWidth() or 0) + ICON_INSET + 16)); panel:SetHeight(40)
  place()
  panel:SetAlpha(0); panel:Show()
  panel:SetFrameStrata("FULLSCREEN_DIALOG"); panel:SetFrameLevel(9999); panel:Raise(); flag:Raise()
  UIFrameFadeIn(panel, 0.18, 0, 1)
  hideAt = GetTime() + SHOW_SECS
end
local function showNext()
  local item = table.remove(queue, 1)
  if item then show(item.kind, item.human, item.rec) end
end
panel:SetScript("OnUpdate", function()
  if hideAt > 0 and GetTime() >= hideAt then
    if #queue > 0 then showNext() else hideAt = 0; panel:Hide() end
  end
end)

-- ── public entry: build the human form per kind. `quiet` = record only (Loot tab), no toast. ──
function Emitter.event(kind, d, quiet)
  d = d or {}
  local zone = d.zone or GetRealZoneText() or "World"
  local lvl = d.level or (UnitLevel and UnitLevel("player")) or 0
  local name = safeStr(d.name or d.title) or ""   -- never let a secret string reach compare/concat/format below
  local machine, human
  if kind == "LEVELUP" then machine = ("LEVELUP %d %s"):format(lvl, zone); human = ("Ding!  Level %d"):format(lvl)
  elseif kind == "ZONE" then machine = "ZONE " .. zone; human = zone
  elseif kind == "DUNGEON" then machine = "DUNGEON " .. name; human = name
  elseif kind == "QUESTACCEPT" then machine = "QUESTACCEPT " .. name; human = "Quest:  " .. name
  elseif kind == "QUESTDONE" then machine = "QUESTDONE " .. name; human = "Complete:  " .. name
  elseif kind == "BOSS" then machine = "BOSS " .. name; human = "Pull:  " .. name
  elseif kind == "KILL" then machine = "KILL " .. (name ~= "" and name or "an enemy"); human = (name ~= "" and name or "an enemy") .. " down!"
  elseif kind == "WIPE" then machine = "WIPE " .. name; human = "Wiped:  " .. name
  elseif kind == "DEATH" then machine = ("DEATH %d %s"):format(lvl, zone); human = ("You died  ·  Level %d"):format(lvl)
  elseif kind == "ALIVE" then machine = "ALIVE " .. zone; human = "Back on your feet"
  elseif kind == "DUNGEONLEAVE" then machine = "DUNGEONLEAVE " .. name; human = "Left  " .. name
  elseif kind == "SKILLUP" then
    machine = ("SKILLUP %d %s"):format(lvl, name)
    human = ("Skill up:  %s %d"):format(name, lvl)
    -- profession skill-up from a craft: name what was made and how many times
    if d.craft then human = human .. ("  ·  %s x%d"):format(d.craft, d.crafted or 1) end
  elseif kind == "DISCOVERY" then machine = "DISCOVERY " .. name; human = "Discovered  " .. name
  elseif kind == "ACHIEV" then machine = "ACHIEV " .. name; human = "Achievement:  " .. name
  elseif kind == "SPELL" then machine = "SPELL " .. name; human = "Learned:  " .. name
  elseif kind == "REP" then machine = "REP " .. name; human = ("%s:  now %s"):format(name, d.standing or "?")
  elseif kind == "FLIGHT" then machine = "FLIGHT " .. name; human = "Flight path:  " .. name
  elseif kind == "FIRSTZONE" then machine = "FIRSTZONE " .. zone; human = "First visit:  " .. zone
  elseif kind == "ROSTERJOIN" then machine = "ROSTERJOIN " .. name; human = name .. " joined the group"
  elseif kind == "ROSTERLEAVE" then machine = "ROSTERLEAVE " .. name; human = name .. " left the group"
  elseif kind == "BROKEN" then machine = "BROKEN " .. name; human = "Broken gear:  " .. name
  elseif kind == "COLLECT" then machine = "COLLECT " .. name; human = "Collected:  " .. name
  elseif kind == "FLIGHTTRIP" then machine = "FLIGHTTRIP " .. name; human = "Flight:  " .. name
  elseif kind == "RECIPE" then machine = "RECIPE " .. name; human = "New recipe:  " .. name
  elseif kind == "UPGRADE" then machine = ("UPGRADE %d"):format(lvl); human = ("Gear up:  item level %d"):format(lvl)
  elseif kind == "PROFTIER" then machine = ("PROFTIER %d %s"):format(lvl, name); human = ("Skill milestone:  %s %d"):format(name, lvl)
  elseif kind == "LOOT" then
    local c = d.count or 1
    machine = ("LOOT %d %s"):format(c, name)
    human = c > 1 and ("Loot:  %s x%d"):format(name, c) or ("Loot:  " .. name)
  elseif kind == "REWARD" then machine = "REWARD " .. name; human = "Chose:  " .. name
  else machine = kind .. " " .. (name ~= "" and name or zone); human = kind end
  -- bulk/common loot is already recorded in the Loot tab (lootlog); keep it out of the timeline and flag
  if kind == "LOOT" and quiet then return end
  -- RECORD tier: every kill/event lands in the timeline (Events tab) + session (Combat Log tab),
  -- correlated by timestamp with the combat-log file and video. This is the complete stats record.
  local rec
  if ns.DB then
    ns.DB.story.events = ns.DB.story.events or {}
    local L = locStamp()
    rec = {
      t = (GetServerTime and GetServerTime()) or time(), kind = kind, text = human, s = ns.DB.active,
      combat = inCombat or nil, foe = d.foe or (inCombat and combatFoe) or nil,
      -- profession skill-ups carry what was crafted + how many times, in which profession (= name)
      prof = (kind == "SKILLUP" and d.craft) and name or nil, craft = d.craft, crafted = d.crafted,
      standing = d.standing,  -- reputation tier reached (REP)
      guid = d.guid,          -- exact npc guid for a precise kill (PARTY_KILL) - desktop attribution
      -- location, for map correlation on the desktop
      zone = L.zone, sub = L.sub, map = L.map, x = L.x, y = L.y,
    }
    ns.DB.story.events[#ns.DB.story.events + 1] = rec
    ns.trimToCap(ns.DB.story.events, 500)
    if ns.Recorder and ns.Recorder.bump then
      if kind == "KILL" then ns.Recorder.bump("kills") elseif kind == "DEATH" then ns.Recorder.bump("deaths") elseif kind == "DUNGEON" then ns.Recorder.bump("dungeons") end
    end
  end
  -- a high-value journey milestone just happened: ask Fights to protect it with a save reminder soon
  if MILESTONE_KINDS[kind] and ns.Fights and ns.Fights.milestone then ns.Fights.milestone() end
  -- fight events also land in the session record so they show on the Combat Log tab
  if COMBAT_KINDS[kind] and ns.Recorder and ns.Recorder.row then
    ns.Recorder.row(kind, name ~= "" and name or (human or ""))
  end
  if kind == "KILL" then lastKillName, lastKillAt = safeStr(name), GetTime() end   -- plain-or-nil: safe to compare later
  -- FLAG tier: only notable events show the on-screen flag (the CV/highlight channel). Quiet events
  -- (trash-mob kills, etc.) are fully recorded above but stay off screen to avoid spam.
  if quiet then return end
  if flagMuted(kind) then return end   -- player muted this group in Settings (already recorded above)
  if hideAt > 0 and GetTime() < hideAt then
    -- a burst (dungeon pull, quest hub) must not back the channel up for half a minute:
    --   the same line twice in a row is shown once; a kind already queued 3 times is not queued again;
    --   the moments that matter (level-up, death, wipe, boss) jump the queue.
    local same = 0
    for _, q in ipairs(queue) do
      if q.human == human then return end
      if q.kind == kind then same = same + 1 end
    end
    if same >= 3 and not TOAST_PRIORITY[kind] then return end
    if TOAST_PRIORITY[kind] then table.insert(queue, 1, { kind = kind, human = human, rec = rec })
    else queue[#queue + 1] = { kind = kind, human = human, rec = rec } end
    while #queue > 12 do table.remove(queue) end   -- drop the newest low-priority tail, never the front
  else
    -- the toast is presentation: a rendering error must never break event recording above
    pcall(show, kind, human, rec)
  end
end

function Emitter.testCombat(on) setCombat(on and true or false) end

function Emitter.setCorner(key)
  if ns.blockedInCombat() then return false end
  if ns.DB and ns.DB.settings then ns.DB.settings.flagPos = nil end   -- a corner choice ends free placement
  key = tostring(key or ""):upper():gsub("%s", "")
  if key == "TL" then key = "TOPLEFT" elseif key == "TR" then key = "TOPRIGHT"
  elseif key == "BL" then key = "BOTTOMLEFT" elseif key == "BR" then key = "BOTTOMRIGHT" end
  if not CORNERS[key] then return false end
  if ns.DB and ns.DB.settings then ns.DB.settings.emitCorner = key end
  place()
  return true
end

-- ── helpers + event wiring ──────────────────────────────────────────────────────
local function questTitle(qid, index)
  if qid and C_QuestLog and C_QuestLog.GetTitleForQuestID then
    local t = C_QuestLog.GetTitleForQuestID(qid); if t and t ~= "" then return t end
  end
  if index and C_QuestLog and C_QuestLog.GetInfo then
    local info = C_QuestLog.GetInfo(index); if info and info.title then return info.title end
  end
  if index and GetQuestLogTitle then local t = GetQuestLogTitle(index); if t then return t end end
  return "quest"
end

local lastZone, wasInstance, lastInstanceName, wasDead = nil, false, nil, false
local deadAt = nil       -- GetTime() at PLAYER_DEAD, for the corpse-run downtime
local lootSource = nil   -- the corpse/node currently being looted (best effort)
local lootSourceGUID = nil  -- its GUID (contains the npcID) for exact desktop attribution
local lootLoc = nil         -- location stamp taken when the loot window opened (nodes have no unit)
-- Gathering: remember the last gather-type cast so node/corpse loot is attributed by profession.
-- Labels resolve from base-rank spell ids at load, so this works in any locale (ranks share the name).
local GATHER_BASE = { [2366] = "Herb node", [2575] = "Mining node", [8613] = "Skinned creature", [7620] = "Fishing spot" }
local GATHER_NAMES = {}
for id, label in pairs(GATHER_BASE) do
  local nm = (GetSpellInfo and GetSpellInfo(id)) or (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id))
  if nm then GATHER_NAMES[nm] = label end
end
local lastGather = nil      -- { label, at }
-- taxi flights: boarding = control lost while UnitOnTaxi; landing = control regained. Total time on
-- flights is a real journey number (and dead time the desktop can skip in a recording).
local flightStart = nil     -- { t, zone }
-- crafting: "You create: [Item]" comes through CHAT_MSG_LOOT. We count how many of each item we make
-- and remember the most recent craft, so a profession skill-up can report what produced it.
local craftCount = {}    -- [itemName] = times crafted this session
local lastCraft = nil    -- { item = name, count = n, at = GetTime() }
local spellReady = false -- suppress the flood of spell-learned events fired during login
-- localized "You create: " prefix so we can tell a craft apart from a normal loot line
-- ── localization: build Lua patterns from the CLIENT'S OWN format strings ────────
-- Hardcoded English patterns silently break on every other locale, so we derive matchers from the
-- global format strings (which are already localized) instead of literal English text.
local function fmtToPattern(fmt)
  local out = fmt or ""
  out = out:gsub("%%%d+%$s", "\001"):gsub("%%%d+%$d", "\002")   -- positional args (%1$s, %2$d)
  out = out:gsub("%%s", "\001"):gsub("%%d", "\002")             -- plain args
  out = out:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")        -- escape pattern magic
  out = out:gsub("\001", "(.-)"):gsub("\002", "(%%d+)")         -- restore as captures
  out = out:gsub("%(%.%-%)$", "(.+)")                           -- a trailing capture must be greedy, not empty
  return "^" .. out
end
local CREATE_PAT     = fmtToPattern(LOOT_ITEM_CREATE_SELF or "You create: %s.")             -- crafted an item
local SKILLUP_PAT    = fmtToPattern(SKILL_RANK_UP or "Your skill in %s has increased to %d.") -- profession/skill up
local DISCOVER_XP_PAT = fmtToPattern(ERR_ZONE_EXPLORED_XP or "Discovered %s: %d experience gained.")
local DISCOVER_PAT   = fmtToPattern(ERR_ZONE_EXPLORED or "Discovered: %s")
local RECIPE_PAT     = fmtToPattern(ERR_LEARN_RECIPE_S or "You have learned how to create a new item: %s.")
-- kill XP lines (named / unnamed, with and without the rested bonus); the %d capture is the XP
local XP_PATS = {
  { fmtToPattern(COMBATLOG_XPGAIN_EXHAUSTION1 or "%s dies, you gain %d experience. (%s exp %s bonus)"), 2 },
  { fmtToPattern(COMBATLOG_XPGAIN_EXHAUSTION4 or "You gain %d experience. (%s exp %s bonus)"), 1 },
  { fmtToPattern(COMBATLOG_XPGAIN_FIRSTPERSON or "%s dies, you gain %d experience."), 2 },
  { fmtToPattern(COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED or "You gain %d experience."), 1 },
}
local function killXpFrom(msg)
  for _, pp in ipairs(XP_PATS) do
    local caps = { msg:match(pp[1]) }
    if caps[1] then local v = tonumber(caps[pp[2]]); if v then return v end end
  end
end
-- self-loot prefixes: CHAT_MSG_LOOT also fires for GROUPMATES' pickups; only lines starting with one of
-- these are ours. Derived from the localized self-loot format strings.
local LOOT_SELF_PREFIXES = {}
for _, g in ipairs({ "LOOT_ITEM_SELF", "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_PUSHED_SELF", "LOOT_ITEM_PUSHED_SELF_MULTIPLE" }) do
  local s = _G[g]; local pre = s and s:match("^(.-)%%s")
  if pre and pre ~= "" then LOOT_SELF_PREFIXES[#LOOT_SELF_PREFIXES + 1] = pre end
end
if #LOOT_SELF_PREFIXES == 0 then LOOT_SELF_PREFIXES = { "You receive loot:", "You receive item:" } end
-- Loot toasts: which drops flash on screen. settings.lootToast = "uncommon" | "rare" (default) | "epic" | "off".
-- Everything is still recorded in the Loot tab; this only gates the on-screen flag.
local LOOT_Q_RANK = { ff9d9d9d = 0, ffffffff = 1, ff1eff00 = 2, ff0070dd = 3, ffa335ee = 4, ffff8000 = 5, ffe6cc80 = 6 }
local LOOT_TOAST_MIN = { uncommon = 2, rare = 3, epic = 4 }
local function lootQuiet(q)
  local mode = (ns.DB and ns.DB.settings and ns.DB.settings.lootToast) or "rare"
  if mode == "off" then return true end
  local rank = LOOT_Q_RANK[(q or ""):lower()] or 1
  return rank < (LOOT_TOAST_MIN[mode] or 3)
end
local function isSelfLoot(msg)
  for _, pre in ipairs(LOOT_SELF_PREFIXES) do if msg:sub(1, #pre) == pre then return true end end
  return false
end

-- ── journey stats capture: gold, XP, /played ────────────────────────────────────
-- These are the player's OWN values (not enemy combat stats), so they are ordinary numbers, but we still
-- guard defensively. Totals feed the Journey/Economy tabs; gold looted also shows in the Loot tab.
local function plainNum(v)
  if type(v) ~= "number" then return nil end
  if issecretvalue and issecretvalue(v) then return nil end
  local ok = pcall(function() return v + 0 end); return ok and v or nil
end
local function rd(fn, ...) if not fn then return nil end local ok, a, b = pcall(fn, ...); if ok then return a, b end end
local lastMoney               -- last GetMoney() copper, for diffs
local lootWindowUntil = 0     -- coin gained before this time counts as looted-from-a-mob/chest
-- Items PUSHED into the bags without a loot window (quest items off a world object, auto-pushed drops
-- on a kill, quest rewards) have no LOOT_OPENED to attribute them. The "Opening" cast that clicking a
-- world object triggers names the object in UNIT_SPELLCAST_SENT; a kill names the mob; a turn-in names
-- the reward. Whichever happened last, within a few seconds, is the source.
-- (one table, not three locals: the OnEvent handler below is close to Lua's 60-upvalue limit)
local pushed = {
  OPEN = { [3365] = true, [6478] = true, [6247] = true, [21651] = true, [22810] = true, [24390] = true, [61437] = true },
  obj = nil,        -- { name, at }: the world object last opened
  turnIn = 0,       -- GetTime() of the last quest turn-in
}
local function pushedSource()
  local now = GetTime()
  if pushed.obj and (now - pushed.obj.at) < 15 then return pushed.obj.name or "Object", nil end
  if (now - pushed.turnIn) < 5 then return "Quest reward", nil end
  if lastKillName and (now - lastKillAt) < 15 then return lastKillName, nil end
  return "Picked up", nil
end
-- gold SINK context: which window was open when the purse went down decides what the gold went to
local merchantOpen, trainerOpen, taxiUntil, repairUntil = false, false, 0, 0
if hooksecurefunc and RepairAllItems then hooksecurefunc("RepairAllItems", function() repairUntil = GetTime() + 2 end) end
local function goldDB() ns.DB.loot.gold = ns.DB.loot.gold or { looted = 0, gained = 0, spent = 0 }; return ns.DB.loot.gold end

-- ── mailbox: auction proceeds, items and coin taken from the inbox ─────────────
-- Classic prints NO chat line when you take an item or coin out of a mail, so the inbox API hooks are the
-- record. SOURCE is the mail's origin (Auction sale / Auction won / Auction returned / Mail from <name>);
-- LOCATION is the mailbox. Auction proceeds and COD payments also feed the Economy breakdown.
local mailOpen, auctionOpen = false, false
local mailMoneySrc, mailMoneyMeta, mailMoneyUntil = nil, nil, 0
local mailTaken = {}          -- item name -> GetTime() of the hook, to skip a duplicate chat line (retail)
local function subjPrefix(global, fallback)
  local fmt = _G[global] or fallback
  return (fmt:gsub("%%s.*$", ""))
end
local function mailSource(index)
  local ok, _, _, sender, subject, money, cod = pcall(GetInboxHeaderInfo, index)
  if not ok then return "Mail", nil end
  sender, subject = safeStr(sender), safeStr(subject)
  local m = { sender = sender, subject = subject, cod = plainNum(cod) }
  local invOk, invType, itemName, playerName, invBid, invBuyout, invDeposit, invCut = pcall(GetInboxInvoiceInfo or function() end, index)
  invType = invOk and safeStr(invType) or nil
  if invOk then m.bid, m.buyout, m.deposit, m.cut = plainNum(invBid), plainNum(invBuyout), plainNum(invDeposit), plainNum(invCut) end
  if invType == "seller" or invType == "seller_temp_invoice" then
    m.item, m.buyer = safeStr(itemName), safeStr(playerName); return "Auction sale", m
  elseif invType == "buyer" then
    m.item, m.seller = safeStr(itemName), safeStr(playerName); return "Auction won", m
  end
  if subject then
    for _, g in ipairs({ { "AUCTION_EXPIRED_MAIL_SUBJECT", "Auction expired: %s" }, { "AUCTION_REMOVED_MAIL_SUBJECT", "Auction cancelled: %s" } }) do
      local pre = subjPrefix(g[1], g[2])
      if pre ~= "" and subject:sub(1, #pre) == pre then m.item = subject:sub(#pre + 1); return "Auction returned", m end
    end
    local sold = subjPrefix("AUCTION_SOLD_MAIL_SUBJECT", "Auction successful: %s")
    if sold ~= "" and subject:sub(1, #sold) == sold then m.item = m.item or subject:sub(#sold + 1); return "Auction sale", m end
    local won = subjPrefix("AUCTION_WON_MAIL_SUBJECT", "Auction won: %s")
    if won ~= "" and subject:sub(1, #won) == won then m.item = m.item or subject:sub(#won + 1); return "Auction won", m end
  end
  if sender then return "Mail from " .. sender, m end
  return "Mail", m
end
local LOOT_Q_HEX = { [0] = "ff9d9d9d", "ffffffff", "ff1eff00", "ff0070dd", "ffa335ee", "ffff8000", "ffe6cc80", "ffe6cc80" }
-- Quality of a looted item as the 8-hex color the Loot pane keys on. Three sources, in order: the link's
-- literal color (|cffRRGGBB, pre-11.0 clients), the link's named quality color (|cnIQ<n>:, 11.0+ and Forever,
-- which is why every row used to fall back to white), and the client's item quality API by item id.
function Emitter.linkQuality(msg, id)
  local hex = msg and msg:match("|c(%x%x%x%x%x%x%x%x)|Hitem")
  if hex then return hex:lower() end
  local named = msg and msg:match("|cnIQ(%d+):|Hitem")
  if named then return LOOT_Q_HEX[tonumber(named)] or "ffffffff" end
  if id then
    local qn
    if C_Item and C_Item.GetItemQualityByID then qn = plainNum(C_Item.GetItemQualityByID(id)) end
    if not qn and GetItemInfo then qn = plainNum(select(3, GetItemInfo(id))) end
    if qn then return LOOT_Q_HEX[qn] or "ffffffff" end
  end
  return "ffffffff"
end
-- Rows recorded before this fix are white with an item id; resolve them once per login while the client can.
function Emitter.backfillLootQuality()
  local log = ns.DB and ns.DB.loot and ns.DB.loot.log
  if not log or not (C_Item and C_Item.GetItemQualityByID) then return 0 end
  local fixed = 0
  for i = #log, math.max(1, #log - 2000), -1 do
    local r = log[i]
    if r and r.id and (r.q == nil or r.q == "ffffffff") then
      local qn = plainNum(C_Item.GetItemQualityByID(r.id))
      if qn and qn ~= 1 then r.q = LOOT_Q_HEX[qn] or r.q; fixed = fixed + 1 end
    end
  end
  return fixed
end
local function pushLoot(entry)
  entry.s = entry.s or (ns.DB and ns.DB.active)
  if entry.item and ns.Recorder and ns.Recorder.bump then ns.Recorder.bump("items") end
  sessionLoot[#sessionLoot + 1] = entry
  while #sessionLoot > 800 do table.remove(sessionLoot, 1) end
  if ns.DB then
    ns.DB.loot.log = ns.DB.loot.log or {}
    ns.DB.loot.log[#ns.DB.loot.log + 1] = entry
    ns.trimToCap(ns.DB.loot.log, 2000)
  end
end
local function logMailItem(index, itemIndex)
  local r = { pcall(GetInboxItem, index, itemIndex) }
  if not r[1] or not r[2] then return end
  local name = safeStr(r[2]); if not name then return end
  local link = GetInboxItemLink and safeStr(GetInboxItemLink(index, itemIndex)) or nil
  -- shapes: (name, itemID, texture, count, quality, canUse) on 1.13+/retail; (name, texture, count, quality) older
  local id, icon, count, quality
  if type(r[6]) == "number" and r[6] <= 7 then id, icon, count, quality = r[3], r[4], r[5], r[6]
  else icon, count, quality = r[3], r[4], r[5] end
  id = plainNum(id) or (link and tonumber(link:match("|Hitem:(%d+)"))) or nil
  icon = plainNum(icon)
  if not icon and id then
    if GetItemIcon then icon = GetItemIcon(id) end
    if not icon and C_Item and C_Item.GetItemIconByID then icon = C_Item.GetItemIconByID(id) end
  end
  local color = link and link:match("|c(%x%x%x%x%x%x%x%x)|Hitem")
  local Q = { [0] = "ff9d9d9d", "ffffffff", "ff1eff00", "ff0070dd", "ffa335ee", "ffff8000", "ffe6cc80" }
  local q = (color or Q[plainNum(quality) or 1] or "ffffffff"):lower()
  local src, meta = mailSource(index)
  local loc = locStamp()
  local tnow = (GetServerTime and GetServerTime()) or time()
  pushLoot({ t = tnow, item = name, count = plainNum(count) or 1, q = q, icon = icon, src = src, mail = meta, id = id,
             x = loc.x, y = loc.y, zone = loc.zone })
  if ns.Market then pcall(ns.Market.mailItem, src, name, id, plainNum(count) or 1, meta) end
  mailTaken[name] = GetTime()
  Emitter.event("LOOT", { name = name, count = plainNum(count) or 1 }, lootQuiet(q))
end
local function armMailMoney(index)
  local ok, _, _, _, _, money = pcall(GetInboxHeaderInfo, index)
  if ok and (plainNum(money) or 0) > 0 then
    mailMoneySrc, mailMoneyMeta = mailSource(index); mailMoneyUntil = GetTime() + 3
  end
end
if hooksecurefunc then
  if TakeInboxMoney then hooksecurefunc("TakeInboxMoney", function(index) armMailMoney(index) end) end
  if TakeInboxItem then hooksecurefunc("TakeInboxItem", function(index, itemIndex) logMailItem(index, itemIndex or 1) end) end
  if AutoLootMailItem then
    hooksecurefunc("AutoLootMailItem", function(index)
      armMailMoney(index)
      for j = 1, (ATTACHMENTS_MAX_RECEIVE or 16) do
        local ok, nm = pcall(GetInboxItem, index, j)
        if ok and nm then logMailItem(index, j) end
      end
    end)
  end
end

-- SESSION pace: since login (a /reload keeps it). XP and gold deltas accumulate here so the Journey and
-- Economy tabs can show per-hour rates and a time-to-level estimate. Reset only on a real login.
local sessionScratch = {}
local function sessionDB() return (ns.Recorder and ns.Recorder.current and ns.Recorder.current()) or sessionScratch end

local function onMoney()
  if not ns.DB then return end
  local c = plainNum(rd(GetMoney)); if not c then return end
  if lastMoney == nil then lastMoney = c; goldDB().balance = c; return end   -- first read seeds baseline
  local delta = c - lastMoney; lastMoney = c
  if delta == 0 then return end
  local g = goldDB(); g.balance = c
  local ses = sessionDB()
  if delta > 0 then
    g.gained = (g.gained or 0) + delta; ses.gained = (ses.gained or 0) + delta
    if GetTime() < lootWindowUntil then                 -- gained while a loot window was open = looted coin
      g.looted = (g.looted or 0) + delta
      ns.DB.loot.log = ns.DB.loot.log or {}
      ns.DB.loot.log[#ns.DB.loot.log + 1] = {
        t = (GetServerTime and GetServerTime()) or time(), money = delta, src = lootSource, guid = lootSourceGUID, s = ns.DB.active,
        x = lootLoc and lootLoc.x, y = lootLoc and lootLoc.y, zone = lootLoc and lootLoc.zone,
      }
      ns.trimToCap(ns.DB.loot.log, 2000)
    elseif Emitter._questMoney and Emitter._questMoney.amount == delta and GetTime() - Emitter._questMoney.at < 3 then
      g.quests = (g.quests or 0) + delta                   -- a quest's money reward (QUEST_TURNED_IN just said so)
      Emitter._questMoney = nil
    elseif merchantOpen then
      g.sold = (g.sold or 0) + delta                       -- vendoring items is income too
    elseif GetTime() < mailMoneyUntil or mailOpen then
      -- coin taken out of a mail: auction proceeds or gold a player sent us
      local src, meta = (GetTime() < mailMoneyUntil) and mailMoneySrc or "Mail", (GetTime() < mailMoneyUntil) and mailMoneyMeta or nil
      mailMoneyUntil = 0
      if src == "Auction sale" then g.auctionSales = (g.auctionSales or 0) + delta; if ns.Market then pcall(ns.Market.sold, mailMoneyMeta, delta) end
      else g.mail = (g.mail or 0) + delta end
      local loc = locStamp()
      pushLoot({ t = (GetServerTime and GetServerTime()) or time(), money = delta, src = src, mail = meta,
                 x = loc.x, y = loc.y, zone = loc.zone })
    else
      Emitter._openGain = { amount = delta, at = GetTime() }   -- no category yet: a quest turn-in may claim it
    end
  else
    local spent = -delta
    g.spent = (g.spent or 0) + spent; ses.spent = (ses.spent or 0) + spent
    if GetTime() < repairUntil then g.repairs = (g.repairs or 0) + spent; repairUntil = 0
    elseif merchantOpen then g.vendor = (g.vendor or 0) + spent
    elseif trainerOpen then g.training = (g.training or 0) + spent
    elseif GetTime() < taxiUntil then g.flights = (g.flights or 0) + spent
    elseif auctionOpen then g.auctions = (g.auctions or 0) + spent     -- bids, buyouts, deposits
    elseif mailOpen then g.mailSpent = (g.mailSpent or 0) + spent      -- COD payments, postage
    else g.other = (g.other or 0) + spent end
  end
end

-- A quest's money reward (#11, G-2). The client may change the money before or after QUEST_TURNED_IN: a gain
-- of exactly the reward in the 3 s before is claimed now, otherwise the next gain of exactly the reward within 3 s.
function Emitter.questMoney(amount)
  if not amount or amount <= 0 or not ns.DB then return end
  local o = Emitter._openGain
  if o and o.amount == amount and GetTime() - o.at < 3 then
    local g = goldDB(); g.quests = (g.quests or 0) + amount
    Emitter._openGain = nil
    return
  end
  Emitter._questMoney = { amount = amount, at = GetTime() }
end

-- ── durability: aggregate gear health + a milestone when something breaks ──
local DUR_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }
local SLOT_NAME = { [1] = "Head", [2] = "Neck", [3] = "Shoulder", [5] = "Chest", [6] = "Waist", [7] = "Legs", [8] = "Feet",
  [9] = "Wrist", [10] = "Hands", [11] = "Finger 1", [12] = "Finger 2", [13] = "Trinket 1", [14] = "Trinket 2", [15] = "Back",
  [16] = "Main hand", [17] = "Off hand", [18] = "Ranged" }
local brokenFlagged = {}
local function onDurability()
  if not ns.DB or not GetInventoryItemDurability then return end
  local sumC, sumM = 0, 0
  for _, slot in ipairs(DUR_SLOTS) do
    local ok, c, m = pcall(GetInventoryItemDurability, slot)
    if ok then
      c, m = plainNum(c), plainNum(m)
      if c and m and m > 0 then
        sumC, sumM = sumC + c, sumM + m
        if c == 0 then
          if not brokenFlagged[slot] then brokenFlagged[slot] = true; Emitter.event("BROKEN", { name = SLOT_NAME[slot] or ("slot " .. slot) }) end
        else brokenFlagged[slot] = nil end
      end
    end
  end
  if sumM > 0 then ns.DB.character.durability = { pct = math.floor(sumC / sumM * 100 + 0.5), at = (GetServerTime and GetServerTime()) or time() } end
end

local function onXP()
  if not ns.DB then return end
  local xp = plainNum(rd(UnitXP, "player"))
  local mx = plainNum(rd(UnitXPMax, "player"))
  if not xp or not mx then return end
  local x = ns.DB.character.xp or { gained = 0 }; ns.DB.character.xp = x
  if x.last ~= nil and x.lastMax ~= nil then
    local d = xp - x.last
    if d < 0 then d = (x.lastMax - x.last) + xp end      -- crossed a level: remainder of old bar + new
    if d > 0 and d <= (x.lastMax + mx) then x.gained = (x.gained or 0) + d; local ses = sessionDB(); ses.xp = (ses.xp or 0) + d end
  end
  x.last, x.lastMax, x.cur, x.max = xp, mx, xp, mx
  x.rested = plainNum(rd(GetXPExhaustion)) or 0
end

local function onPlayed(total, levelt)
  if not ns.DB then return end
  total = plainNum(total); if not total then return end
  ns.DB.character.played = ns.DB.character.played or {}
  ns.DB.character.played.total = total
  ns.DB.character.played.level = plainNum(levelt)
  ns.DB.character.played.atEpoch = (GetServerTime and GetServerTime()) or time()
  local lvl = plainNum(rd(UnitLevel, "player"))
  if lvl and lvl > 0 then
    ns.DB.character.playedAtLevel = ns.DB.character.playedAtLevel or {}
    ns.DB.character.playedAtLevel[lvl] = total          -- stamp real /played at each level for the pace chart
  end
end

-- ── group roster over time ──────────────────────────────────────────────────────
-- snapshotGroup() in Fights captures the party once at pull; here we diff the roster on every change so
-- a run with a swap or a resummon reads correctly ("Dave joined", "Mia left"). Login seeds silently.
local rosterSeen, rosterSeeded = {}, false
local function currentRoster()
  local set = {}
  local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
  local raid = IsInRaid and IsInRaid()
  for i = 1, n do
    local u = (raid and "raid" or "party") .. i
    if UnitExists(u) and not (UnitIsUnit and UnitIsUnit(u, "player")) then
      local nm = safeStr(UnitName(u)); if nm then set[nm] = true end
    end
  end
  return set
end
local function diffRoster(fire)
  local now = currentRoster()
  if fire then
    for nm in pairs(now) do if not rosterSeen[nm] then Emitter.event("ROSTERJOIN", { name = nm }, true) end end
    for nm in pairs(rosterSeen) do if not now[nm] then Emitter.event("ROSTERLEAVE", { name = nm }, true) end end
  end
  rosterSeen = now; rosterSeeded = true
end

local ef = CreateFrame("Frame")
for _, e in ipairs({
  "PLAYER_LEVEL_UP", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD",
  "QUEST_ACCEPTED", "QUEST_TURNED_IN", "ENCOUNTER_START", "ENCOUNTER_END",
  "PLAYER_DEAD", "PLAYER_UNGHOST", "PLAYER_ALIVE",
  "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",   -- combat enter / leave (not secret)
  "PLAYER_TARGET_CHANGED",                            -- track which mob we're fighting
  "CHAT_MSG_SKILL", "CHAT_MSG_SYSTEM", "CHAT_MSG_LOOT",  -- skill-ups, discoveries, loot
  "LOOT_OPENED", "LOOT_CLOSED",                          -- to attribute loot to the corpse being looted
  "ACHIEVEMENT_EARNED",                                  -- journey milestone
  "LEARNED_SPELL_IN_TAB", "NEW_SPELL_ADDED",             -- a new ability learned (trainer / level)
  "CHAT_MSG_COMBAT_FACTION_CHANGE",                      -- reputation (we detect tier-ups)
  "PLAYER_MONEY",                                        -- gold balance changed (income + sinks)
  "PLAYER_XP_UPDATE",                                    -- experience gained (leveling pace)
  "TIME_PLAYED_MSG",                                     -- /played total + per-level time
  "UNIT_SPELLCAST_SUCCEEDED",                            -- gathering casts (herb / mine / skin / fish)
  "UNIT_SPELLCAST_SENT",                                 -- Opening casts name the world object being clicked
  "GROUP_ROSTER_UPDATE",                                 -- party/raid joins and leaves over time
  "MERCHANT_SHOW", "MERCHANT_CLOSED", "TRAINER_SHOW", "TRAINER_CLOSED", "TAXIMAP_OPENED",  -- gold sink context
  "MAIL_SHOW", "MAIL_CLOSED", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED",                -- mailbox / auction context
  "UPDATE_INVENTORY_DURABILITY",                         -- gear health
  "UPDATE_INSTANCE_INFO",                                -- saved instances (lockouts) after RequestRaidInfo
  "SKILL_LINES_CHANGED",                                 -- profession ranks (tier milestones)
  "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED",        -- taxi flights (board / land)
  "CHAT_MSG_COMBAT_XP_GAIN",                             -- kill XP (quest XP comes with QUEST_TURNED_IN)
  "NEW_RECIPE_LEARNED",                                  -- recipes (retail); Classic parses the system line
  "PLAYER_EQUIPMENT_CHANGED",                            -- gear-upgrade milestones (out of combat)
  "NEW_MOUNT_ADDED", "COMPANION_LEARNED", "NEW_PET_ADDED", "NEW_TOY_ADDED",  -- collections
}) do pcall(ef.RegisterEvent, ef, e) end   -- pcall: some events are absent on older flavors
-- Precise kill attribution via the combat log's PARTY_KILL. Only on clients WITHOUT Secret Values
-- (Classic/SoD) - on the Midnight client CLEU is secret and would taint us, so we skip it there and
-- fall back to the target-based heuristic.
if not ns.hasSecretValues then pcall(ef.RegisterEvent, ef, "COMBAT_LOG_EVENT_UNFILTERED") end
-- NOTE: no UNIT_HEALTH here - on the Midnight "WoW Forever" client health is a Secret Value that
-- tainted (addon) code cannot do arithmetic on. Near-death is detected desktop-side (CV / combat log).

-- ── reputation tier-ups ─────────────────────────────────────────────────────────
-- We snapshot each faction's standing and only emit a REP event when it CLIMBS a tier (Neutral →
-- Friendly, etc.), not on every reputation point. Standing (a small integer) is not a Secret Value.
-- API varies: C_Reputation on current clients, GetFactionInfo on Classic - both feature-detected.
-- ── profession tiers ───────────────────────────────────────────────────────────
-- Snapshot professions (ranks) and emit a PROFTIER milestone when a rank crosses a tier boundary.
-- Retail/Midnight: GetProfessions + GetProfessionInfo. Classic: skill lines under the Professions /
-- Secondary Skills headers (so weapon skills and languages are excluded).
local PROF_TIERS = { 75, 150, 225, 300, 375, 450, 525, 600 }
local profSeen, profSeeded = {}, false
local function scanProfessions(fire)
  local out = {}
  pcall(function()
    if GetProfessions and GetProfessionInfo then
      local a, b, c, d, e, f = GetProfessions()
      for _, idx in ipairs({ a, b, c, d, e, f }) do
        if idx then
          local name, _, rank, max = GetProfessionInfo(idx)
          if name then out[name] = { rank = plainNum(rank) or 0, max = plainNum(max) or 0 } end
        end
      end
    elseif GetNumSkillLines and GetSkillLineInfo then
      local under = false
      for i = 1, GetNumSkillLines() do
        local name, isHeader, _, rank, _, _, max = GetSkillLineInfo(i)
        if isHeader then under = (name == TRADE_SKILLS) or (name == SECONDARY_SKILLS)
        elseif under and name and max and max > 0 then out[name] = { rank = plainNum(rank) or 0, max = plainNum(max) or 0 } end
      end
    end
  end)
  if fire then
    for name, pr in pairs(out) do
      local prev = profSeen[name]
      if prev and pr.rank > prev then
        for _, t in ipairs(PROF_TIERS) do
          if prev < t and pr.rank >= t then Emitter.event("PROFTIER", { name = name, level = t }); break end
        end
      end
    end
  end
  for name, pr in pairs(out) do profSeen[name] = pr.rank end
  if ns.DB and next(out) then ns.DB.character.professions = out end
  profSeeded = true
end

-- every reputation gain, not just tier-ups: faction, amount and what caused it (a quest turned in or a kill a
-- moment before), with the place. Kept in story.rep (capped 2000) so a mob-grinding session never pushes the
-- rest of the timeline out of story.events. Record only: nothing on screen changes.
Emitter.REPGAIN_PAT = fmtToPattern(FACTION_STANDING_INCREASED or "Reputation with %s increased by %d.")
function Emitter.repGain(msg)
  if not ns.DB then return end
  local faction, amount = (msg or ""):match(Emitter.REPGAIN_PAT)
  faction, amount = safeStr(faction), tonumber(amount)
  if not faction or faction == "" or not amount then return end
  local now = (GetServerTime and GetServerTime()) or time()
  local src
  local log = ns.DB.story.events or {}
  local last = log[#log]
  if last and last.kind == "QUESTDONE" and (now - (last.t or 0)) <= 5 then
    src = "Quest: " .. (((last.text or ""):gsub("^Complete:%s*", "")))
  elseif lastKillName and (GetTime() - (lastKillAt or 0)) < 5 then
    src = "Kill: " .. lastKillName
  end
  local L = locStamp()
  ns.DB.story.rep = ns.DB.story.rep or {}
  local rep = ns.DB.story.rep
  rep[#rep + 1] = { t = now, s = ns.DB.active, faction = faction, amount = amount, src = src,
    zone = L.zone, sub = L.sub, map = L.map, x = L.x, y = L.y }
  while #rep > 2000 do table.remove(rep, 1) end
end

local repStanding, repSeeded = {}, false
local function scanRep(fire)
  local snap = {}
  pcall(function()
    if C_Reputation and C_Reputation.GetNumFactions and C_Reputation.GetFactionDataByIndex then
      for i = 1, C_Reputation.GetNumFactions() do
        local d = C_Reputation.GetFactionDataByIndex(i)
        if d and d.name and not d.isHeader and d.reaction then
          local prev = repStanding[d.name]
          if fire and prev and d.reaction > prev then
            Emitter.event("REP", { name = d.name, standing = _G["FACTION_STANDING_LABEL" .. d.reaction] or "a new standing" })
          end
          repStanding[d.name] = d.reaction
          snap[d.name] = { standing = d.reaction, label = _G["FACTION_STANDING_LABEL" .. d.reaction] }
        end
      end
    elseif GetNumFactions and GetFactionInfo then
      for i = 1, GetNumFactions() do
        local name, _, standingID, _, _, _, _, _, isHeader = GetFactionInfo(i)
        if name and not isHeader and standingID then
          local prev = repStanding[name]
          if fire and prev and standingID > prev then
            Emitter.event("REP", { name = name, standing = _G["FACTION_STANDING_LABEL" .. standingID] or "a new standing" })
          end
          repStanding[name] = standingID
          snap[name] = { standing = standingID, label = _G["FACTION_STANDING_LABEL" .. standingID] }
        end
      end
    end
  end)
  if ns.DB and next(snap) then ns.DB.character.reputation = snap end
end

ef:SetScript("OnEvent", function(_, event, a1, a2, a3, a4, a5)
  if event == "PLAYER_LEVEL_UP" then
    Emitter.event("LEVELUP", { level = a1 })
    if RequestTimePlayed then pcall(RequestTimePlayed) end   -- stamp real /played at this ding (pace chart)
  elseif event == "ZONE_CHANGED_NEW_AREA" then
    local z = GetRealZoneText() or GetZoneText()
    if z and z ~= lastZone then
      lastZone = z
      Emitter.event("ZONE", { zone = z })
      -- the journey milestone is the FIRST time you set foot somewhere, not every re-entry
      if ns.DB then
        ns.DB.character.seenZones = ns.DB.character.seenZones or {}
        if not ns.DB.character.seenZones[z] then
          ns.DB.character.seenZones[z] = (GetServerTime and GetServerTime()) or time()
          Emitter.event("FIRSTZONE", { zone = z })
        end
      end
    end
  elseif event == "PLAYER_ENTERING_WORLD" then
    Emitter.backfillLootQuality()
    refreshClassColor(); paintFlag()
    place()   -- settings are loaded now, so move the flag to the corner the user saved last time
    Emitter.applyFlagPrefs()
    spellReady = false
    onMoney()   -- seed the gold baseline so the first change diffs correctly
    if C_Timer and C_Timer.After then
      C_Timer.After(10, function() spellReady = true; scanRep(false); repSeeded = true end)  -- seed rep baseline, don't fire on login
      C_Timer.After(12, function() if RequestTimePlayed then pcall(RequestTimePlayed) end end) -- /played once on login
      C_Timer.After(15, function() if RequestRaidInfo then pcall(RequestRaidInfo) end end)     -- lockouts once on login
    end
    local iname, itype = GetInstanceInfo()
    local nowInst = (itype == "party" or itype == "raid")
    -- de-dup across reload/relog: wasInstance resets to false on every load, so we key the
    -- "already announced this dungeon" state on ns.DB (survives /reload) to avoid a duplicate DUNGEON.
    local announced = ns.DB and ns.DB.story.inInstance
    -- state FIRST, then the event/toast: if presentation ever throws, the dedupe state is still correct
    if nowInst and announced ~= iname then
      if ns.DB then ns.DB.story.inInstance = iname end
      Emitter.event("DUNGEON", { name = iname })
    elseif (not nowInst) and announced then
      if ns.DB then ns.DB.story.inInstance = nil end
      Emitter.event("DUNGEONLEAVE", { name = lastInstanceName or announced or "the dungeon" })
    end
    wasInstance = nowInst
    if nowInst then lastInstanceName = iname end
    lastZone = GetRealZoneText()
    if ns.DB and lastZone then   -- the zone you log into is "seen", not discovered
      ns.DB.character.seenZones = ns.DB.character.seenZones or {}
      ns.DB.character.seenZones[lastZone] = ns.DB.character.seenZones[lastZone] or ((GetServerTime and GetServerTime()) or time())
    end
    diffRoster(false)   -- seed the roster without announcing everyone on login
    onDurability()      -- seed gear health
    scanProfessions(false)   -- seed profession ranks without announcing
    if GetAverageItemLevel and ns.DB then local _, eq = GetAverageItemLevel(); ns.DB.character.ilvl = plainNum(eq) or ns.DB.character.ilvl end
  elseif event == "PLAYER_REGEN_DISABLED" then
    setCombat(true)
  elseif event == "PLAYER_REGEN_ENABLED" then
    -- best-effort mob kill: combat ended and we're alive → count the foe we were fighting as killed.
    -- (uses the foe captured while it was alive; a dead corpse reports not-attackable so we can't
    --  re-derive it here. skips if a boss ENCOUNTER_END just logged the same name.)
    if not wasDead then
      local foe = combatFoe   -- already safeStr at capture (a plain string or nil)
      if not foe and UnitExists("target") then foe = safeStr(UnitName("target")) end
      -- don't credit a kill if that foe is still ALIVE in front of us (we fled / it evaded / a group-mate
      -- was fighting it). Only meaningful when we actually have a plain foe name to compare.
      local tname = UnitExists("target") and safeStr(UnitName("target")) or nil
      local stillAlive = foe and tname and tname == foe
        and UnitCanAttack and UnitCanAttack("player", "target")
        and UnitIsDead and not UnitIsDead("target")
      local dup = foe and lastKillName and foe == lastKillName and (GetTime() - lastKillAt) < 5
      foe = foe or "an enemy"   -- secret/unknown name degrades to a generic label
      if not stillAlive and not dup then
        -- notable foes (elite/rare/boss) flag on-screen for the CV; trash kills record silently
        Emitter.event("KILL", { name = foe }, not combatFoeElite)   -- emitted before setCombat: in-combat flag
      end
    end
    setCombat(false)
    combatFoe = nil; combatFoeElite = false
  elseif event == "PLAYER_TARGET_CHANGED" then
    if inCombat then noteFoe() end   -- keep the foe current as we switch targets mid-fight
  elseif event == "QUEST_ACCEPTED" then
    local index, qid = a1, a2
    if not qid then qid = a1; index = nil end
    Emitter.event("QUESTACCEPT", { name = questTitle(qid, index) })
  elseif event == "UNIT_SPELLCAST_SENT" then
    -- (unit, target, castGUID, spellID): the Opening cast carries the world object's name as target
    if a1 == "player" and pushed.OPEN[a4] then pushed.obj = { name = safeStr(a2), at = GetTime() } end
  elseif event == "QUEST_TURNED_IN" then
    pushed.turnIn = GetTime()
    Emitter.event("QUESTDONE", { name = questTitle(a1, nil) })
    Emitter.questMoney(plainNum(a3))
    local qxp = plainNum(a2)                              -- (questID, xpReward, moneyReward)
    if qxp and qxp > 0 and ns.DB then ns.DB.character.xp = ns.DB.character.xp or {}; ns.DB.character.xp.fromQuests = (ns.DB.character.xp.fromQuests or 0) + qxp end
  elseif event == "ENCOUNTER_START" then
    Emitter.event("BOSS", { name = a2 or "boss" })
  elseif event == "ENCOUNTER_END" then
    Emitter.event(a5 == 1 and "KILL" or "WIPE", { name = a2 or "boss" })
  elseif event == "PLAYER_DEAD" then
    wasDead = true; deadAt = GetTime()
    pushed.durBefore = ns.DB and ns.DB.character.durability and ns.DB.character.durability.pct or nil   -- gear health going in
    local hit = pushed.lastHit
    Emitter.event("DEATH", { foe = (hit and hit.name and (GetTime() - hit.at) < 10) and hit.name or nil })
  elseif event == "PLAYER_UNGHOST" or event == "PLAYER_ALIVE" then
    -- only a real resurrection, not the PLAYER_ALIVE that also fires on login
    if wasDead and (not UnitIsDeadOrGhost or not UnitIsDeadOrGhost("player")) then
      wasDead = false
      local down = deadAt and math.max(0, GetTime() - deadAt) or nil; deadAt = nil
      -- stamp the downtime on the DEATH row so the Deaths tab can show how long the corpse run took
      if down and ns.DB and ns.DB.story.events then
        onDurability()   -- fresh read after the corpse run / spirit healer
        local after = ns.DB.character.durability and ns.DB.character.durability.pct
        local loss = (pushed.durBefore and after) and math.max(0, pushed.durBefore - after) or nil
        for i = #ns.DB.story.events, 1, -1 do local e = ns.DB.story.events[i]; if e.kind == "DEATH" then e.downtime = math.floor(down); e.durLoss = loss; break end end
        pushed.durBefore = nil
      end
      Emitter.event("ALIVE", { duration = down })
    end
  elseif event == "ACHIEVEMENT_EARNED" then
    local id = a1
    local nm = id and GetAchievementInfo and select(2, GetAchievementInfo(id))
    if nm then Emitter.event("ACHIEV", { name = nm }) end
  elseif event == "LEARNED_SPELL_IN_TAB" or event == "NEW_SPELL_ADDED" then
    if spellReady then
      local sid = a1
      local nm = sid and ((GetSpellInfo and GetSpellInfo(sid)) or (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(sid)))
      if nm then Emitter.event("SPELL", { name = nm }, true) end   -- recorded, not flagged (can be frequent)
    end
  elseif event == "CHAT_MSG_SKILL" then
    local skill, val = (a1 or ""):match(SKILLUP_PAT)
    if skill then
      local d = { name = skill, level = tonumber(val) }
      -- if we crafted something in the last few seconds, this profession skill-up came from it
      if lastCraft and (GetTime() - lastCraft.at) < 6 then
        d.craft = lastCraft.item; d.crafted = lastCraft.count
      end
      Emitter.event("SKILLUP", d)
    end
  elseif event == "CHAT_MSG_SYSTEM" then
    local msg = a1 or ""
    local area = msg:match(DISCOVER_XP_PAT) or msg:match(DISCOVER_PAT)
    local recipe = msg:match(RECIPE_PAT)
    if recipe then
      Emitter.event("RECIPE", { name = recipe:match("%[(.-)%]") or recipe })
    elseif area then
      Emitter.event("DISCOVERY", { name = area })
    elseif ERR_NEWTAXIPATH and msg == ERR_NEWTAXIPATH then
      -- "New flight path discovered!" - stamp the flight master's location (message carries no name)
      local sub = GetSubZoneText and GetSubZoneText() or ""
      Emitter.event("FLIGHT", { name = (sub ~= "" and sub) or (GetRealZoneText and GetRealZoneText()) or "a new location" })
    end
  elseif event == "CHAT_MSG_COMBAT_FACTION_CHANGE" then
    Emitter.repGain(a1)                   -- every gain, with its source (story.rep)
    if repSeeded then scanRep(true) end   -- a rep gain just happened: re-scan and emit only genuine tier-ups
  elseif event == "GROUP_ROSTER_UPDATE" then
    diffRoster(rosterSeeded)
  elseif event == "MAIL_SHOW" then mailOpen = true
  elseif event == "MAIL_CLOSED" then mailOpen = false
  elseif event == "AUCTION_HOUSE_SHOW" then auctionOpen = true
  elseif event == "AUCTION_HOUSE_CLOSED" then auctionOpen = false
  elseif event == "MERCHANT_SHOW" then merchantOpen = true
  elseif event == "MERCHANT_CLOSED" then merchantOpen = false
  elseif event == "TRAINER_SHOW" then trainerOpen = true
  elseif event == "TRAINER_CLOSED" then trainerOpen = false
  elseif event == "TAXIMAP_OPENED" then taxiUntil = GetTime() + 5
  elseif event == "UPDATE_INVENTORY_DURABILITY" then onDurability()
  elseif event == "UPDATE_INSTANCE_INFO" then
    -- saved instances: which dungeons and raids this character is locked to, and until when
    if ns.DB and GetNumSavedInstances and GetSavedInstanceInfo then
      local out, nowT = {}, (GetServerTime and GetServerTime()) or time()
      for i = 1, (GetNumSavedInstances() or 0) do
        local ok, name, id, reset, diff, locked, extended, _, isRaid, maxPlayers, diffName, numEnc, progress = pcall(GetSavedInstanceInfo, i)
        if ok and name and (locked or extended) then
          out[#out + 1] = { name = safeStr(name), id = plainNum(id), resetAt = nowT + (plainNum(reset) or 0), difficulty = safeStr(diffName), raid = isRaid and true or nil,
                            players = plainNum(maxPlayers), bosses = plainNum(numEnc), down = plainNum(progress), extended = extended and true or nil }
        end
      end
      ns.DB.character.lockouts = out
    end
  elseif event == "SKILL_LINES_CHANGED" then scanProfessions(profSeeded)
  elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
    local kxp = killXpFrom(a1 or "")
    if kxp and ns.DB then ns.DB.character.xp = ns.DB.character.xp or {}; ns.DB.character.xp.fromKills = (ns.DB.character.xp.fromKills or 0) + kxp end
  elseif event == "NEW_RECIPE_LEARNED" then
    local nm
    if a1 and C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo then local ok, info = pcall(C_TradeSkillUI.GetRecipeInfo, a1); nm = ok and info and safeStr(info.name) end
    Emitter.event("RECIPE", { name = nm or "a new recipe" })
    if ns.Market then pcall(ns.Market.recipe, nm) end
  elseif event == "PLAYER_EQUIPMENT_CHANGED" then
    -- journey-level gear progression: equipped item level going UP (checked out of combat only)
    if not (InCombatLockdown and InCombatLockdown()) and GetAverageItemLevel and ns.DB then
      local _, eq = GetAverageItemLevel()
      eq = plainNum(eq)
      if eq then
        local prev = tonumber(ns.DB.character.ilvl)
        if prev and eq > prev + 0.05 then Emitter.event("UPGRADE", { level = math.floor(eq + 0.5) }) end
        ns.DB.character.ilvl = eq
      end
    end
  elseif event == "PLAYER_CONTROL_LOST" then
    Emitter.boardFlight(false)
  elseif event == "PLAYER_CONTROL_GAINED" then
    Emitter.landFlight()
  elseif event == "NEW_MOUNT_ADDED" then
    local nm = a1 and C_MountJournal and C_MountJournal.GetMountInfoByID and safeStr((C_MountJournal.GetMountInfoByID(a1)))
    Emitter.event("COLLECT", { name = nm or "a new mount" })
  elseif event == "COMPANION_LEARNED" then
    Emitter.event("COLLECT", { name = "a new companion" })
  elseif event == "NEW_PET_ADDED" then
    Emitter.event("COLLECT", { name = "a new battle pet" })
  elseif event == "NEW_TOY_ADDED" then
    local nm = a1 and C_ToyBox and C_ToyBox.GetToyInfo and safeStr(select(2, C_ToyBox.GetToyInfo(a1)))
    Emitter.event("COLLECT", { name = nm or "a new toy" })
  elseif event == "PLAYER_MONEY" then
    onMoney()
  elseif event == "PLAYER_XP_UPDATE" then
    onXP()
  elseif event == "TIME_PLAYED_MSG" then
    onPlayed(a1, a2)   -- totalTime, levelTime (seconds)
  elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
    -- Classic only (registration is gated off on Secret-Value clients). Exact kill credit via PARTY_KILL:
    -- the combat log names the mob whose killing blow WE landed, so we don't guess from the last target.
    local _, sub, _, srcGUID, srcName, _, _, destGUID, destName = CombatLogGetCurrentEventInfo()
    -- the last thing that damaged US names the killer when we die (Classic only; CLEU is secret on Midnight)
    if sub and destGUID and UnitGUID and destGUID == UnitGUID("player") and (sub:find("_DAMAGE$") or sub == "ENVIRONMENTAL_DAMAGE") then
      pushed.lastHit = { name = safeStr(srcName) or (sub == "ENVIRONMENTAL_DAMAGE" and "the environment") or nil, at = GetTime() }
    end
    if sub == "PARTY_KILL" and destName and UnitGUID and srcGUID == UnitGUID("player") then
      local quiet = not (destName == combatFoe and combatFoeElite)   -- flag elites, record trash silently
      Emitter.event("KILL", { name = destName, guid = destGUID }, quiet)
    end
  elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
    if a1 == "player" and a3 then
      local nm = (GetSpellInfo and GetSpellInfo(a3)) or (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(a3))
      local label = nm and GATHER_NAMES[nm]
      if label then lastGather = { label = label, at = GetTime() } end
    end
  elseif event == "LOOT_OPENED" then
    -- Attribute the loot window to its source, best effort, always with coordinates:
    --   a dead target        -> the mob's name (or "Skinned creature at (x, y)" when the name is secret)
    --   a recent gather cast -> "Herb node / Mining node / Fishing spot at (x, y)"
    --   otherwise            -> the loot-source GUID type (object / creature) at (x, y)
    lootSource, lootSourceGUID = nil, nil
    lootLoc = locStamp()
    -- SOURCE is who/what (mob, node, profession, object); LOCATION (zone + coords) is stored separately
    -- on every loot row and shown in its own column, never embedded in the source text.
    local gather = (lastGather and (GetTime() - lastGather.at) < 5) and lastGather.label or nil
    if UnitExists("target") and UnitIsDead and UnitIsDead("target") then
      lootSource = safeStr(UnitName("target")) or ((gather == "Skinned creature") and gather or "Creature")
      lootSourceGUID = UnitGUID and safeStr(UnitGUID("target"))
    elseif gather then
      lootSource = gather
    else
      local ok, sg = pcall(GetLootSourceInfo or function() end, 1)
      sg = ok and safeStr(sg) or nil
      local typ = sg and sg:match("^(%a+)%-")
      if typ == "GameObject" then lootSource = "Object"
      elseif typ == "Creature" then lootSource = "Creature"
      else lootSource = "Unknown source" end
      lootSourceGUID = sg
    end
    lootWindowUntil = GetTime() + 3   -- coin gained in this window is attributed to this loot source
    -- (kept until the next loot; NOT cleared on LOOT_CLOSED, since loot messages can arrive at/after close)
  elseif event == "CHAT_MSG_LOOT" then
    local msg = a1 or ""
    -- capture the item name from the link independent of the quality color, so greys log too
    local item = msg:match("|Hitem:.-|h%[(.-)%]|h")
    -- a "You create: [Item]xN" line is a craft, not loot: count it and remember it for skill-ups
    if item and msg:match(CREATE_PAT) then
      local made = tonumber(msg:match("x(%d+)")) or 1
      craftCount[item] = (craftCount[item] or 0) + made
      lastCraft = { item = item, count = craftCount[item], at = GetTime() }
      if ns.Market then
        local cid = tonumber(msg:match("|Hitem:(%d+)"))
        local cicon = cid and ((GetItemIcon and GetItemIcon(cid)) or (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(cid))) or nil
        pcall(ns.Market.craft, item, made, cid, cicon)
      end
      return   -- not loot; don't log or toast
    end
    -- an item we just took out of a mail was logged by the inbox hook; retail also prints a chat line for it
    if item and mailTaken[item] and (GetTime() - mailTaken[item]) < 3 then mailTaken[item] = nil; return end
    -- CHAT_MSG_LOOT fires for every group member; only log lines that are OUR pickup
    if item and not isSelfLoot(msg) then return end
    if item then
      local count = tonumber(msg:match("x(%d+)")) or 1
      local id = tonumber(msg:match("|Hitem:(%d+)"))
      local q = Emitter.linkQuality(msg, id)
      local icon
      if id then
        if GetItemIcon then icon = GetItemIcon(id) end
        if not icon and C_Item and C_Item.GetItemIconByID then icon = C_Item.GetItemIconByID(id) end
        if not icon and GetItemInfoInstant then local _, _, _, _, ic = GetItemInfoInstant(id); icon = ic end
      end
      local tnow = (GetServerTime and GetServerTime()) or time()
      -- no loot window in the last ~15s: the item was pushed, attribute it to what just happened instead
      local src, srcGUID = lootSource, lootSourceGUID
      if GetTime() > lootWindowUntil + 12 then src, srcGUID = pushedSource() end
      local quest = nil
      if id and GetItemInfoInstant then local _, _, _, _, _, classID = GetItemInfoInstant(id); if classID == 12 then quest = true end end
      local entry = { t = tnow, item = item, count = count, q = q, icon = icon, src = src, quest = quest, id = id }
      sessionLoot[#sessionLoot + 1] = entry
      while #sessionLoot > 800 do table.remove(sessionLoot, 1) end
      -- persistent, timestamped loot log (item + source + time): flushed on logout, read by the desktop
      -- at finalize and correlated to the video/combat log by timestamp. Capped; kept out of Events.
      if ns.DB then
        ns.DB.loot.log = ns.DB.loot.log or {}
        ns.DB.loot.log[#ns.DB.loot.log + 1] = {
          t = tnow, item = item, count = count, q = q, icon = icon, src = src, guid = srcGUID, s = ns.DB.active, quest = quest, id = id,
          x = lootLoc and lootLoc.x, y = lootLoc and lootLoc.y, zone = lootLoc and lootLoc.zone,
        }
        ns.trimToCap(ns.DB.loot.log, 2000)
      end
      -- drops at or above the loot-toast threshold get the on-screen flag; the rest stay off-screen
      if ns.Recorder and ns.Recorder.bump then ns.Recorder.bump("items") end
      Emitter.event("LOOT", { name = item, count = count }, lootQuiet(q))
    end
  end
end)

-- Which quest reward the player PICKED: GetQuestReward(choiceIndex) fires when they confirm a choice
-- reward. Read the chosen item's name at that moment (QUEST_TURNED_IN doesn't carry it).
-- Flights (#11, T-2, T-5). Boarding is control lost while on a taxi, or a TakeTaxiNode call followed by the
-- taxi flag within 10 s (a client that raises the flag after PLAYER_CONTROL_LOST recorded no trip before);
-- landing is control regained or the flag clearing, whichever comes first, and records the trip once.
function Emitter.boardFlight(fromHook)
  if flightStart and flightStart.boarded then return end
  local zone = (GetRealZoneText and GetRealZoneText()) or "?"
  if UnitOnTaxi and UnitOnTaxi("player") then
    flightStart = { t = flightStart and flightStart.t or GetTime(), zone = flightStart and flightStart.zone or zone, boarded = true }
  elseif fromHook then
    flightStart = { t = GetTime(), zone = zone, boarded = false }
  end
end
function Emitter.landFlight()
  if not flightStart or not flightStart.boarded then return end
  local dur = math.max(0, GetTime() - flightStart.t)
  local to = (GetRealZoneText and GetRealZoneText()) or "?"
  if ns.DB then ns.DB.character.flightTime = (ns.DB.character.flightTime or 0) + dur end
  local from = flightStart.zone
  flightStart = nil
  Emitter.event("FLIGHTTRIP", { name = ("%s to %s (%dm %ds)"):format(from, to, math.floor(dur / 60), math.floor(dur % 60)), duration = dur }, true)
end
if TakeTaxiNode and hooksecurefunc then
  hooksecurefunc("TakeTaxiNode", function()
    pcall(Emitter.boardFlight, true)
    if not (C_Timer and C_Timer.NewTicker) then return end
    local waited, tk = 0, nil
    tk = C_Timer.NewTicker(1, function()
      waited = waited + 1
      if not flightStart then if tk then tk:Cancel() end; return end
      local onTaxi = UnitOnTaxi and UnitOnTaxi("player")
      if not flightStart.boarded then
        if onTaxi then Emitter.boardFlight(false)
        elseif waited > 10 then flightStart = nil; if tk then tk:Cancel() end end   -- the taxi never left
      elseif not onTaxi then Emitter.landFlight(); if tk then tk:Cancel() end end
    end)
  end)
end

-- The hook runs after the reward is taken, when the panel can already be gone and the choice reads empty
-- (#11: no REWARD in the Forever save files), so the choices are also read when the panel opens.
local function choiceName(i)
  local name
  if GetQuestItemLink then local ok, l = pcall(GetQuestItemLink, "choice", i); if ok and type(l) == "string" then name = l:match("%[(.-)%]") end end
  if (not name or name == "") and GetQuestItemInfo then local ok, nm = pcall(GetQuestItemInfo, "choice", i); if ok and type(nm) == "string" then name = nm end end
  return (name and name ~= "") and name or nil
end
Emitter._rewardChoices = {}
do
  local qf = CreateFrame("Frame")
  qf:RegisterEvent("QUEST_COMPLETE")
  qf:SetScript("OnEvent", function()
    local t, n = {}, 0
    if GetNumQuestChoices then local ok, c = pcall(GetNumQuestChoices); n = (ok and type(c) == "number") and c or 0 end
    for i = 1, n do t[i] = choiceName(i) end
    Emitter._rewardChoices = t
  end)
end
if GetQuestReward and hooksecurefunc then
  hooksecurefunc("GetQuestReward", function(choice)
    if type(choice) ~= "number" or choice == 0 then return end
    local name = choiceName(choice) or Emitter._rewardChoices[choice]
    Emitter._rewardChoices = {}
    if name then Emitter.event("REWARD", { name = name }) end
  end)
end

-- ── config tab: pick which screen corner the flag + notifications live in ───────
if ns.UI and ns.UI.registerTab then
  ns.UI.registerTab(20, "Settings", function(content)
    local C = ns.UI.C
    local title = ns.UI.FS(content, "GameFontNormalLarge"); title:SetPoint("TOPLEFT", 14, -14); title:SetText("Settings")
    local sub = ns.UI.FS(content, "GameFontHighlightSmall", C.dim); sub:SetPoint("TOPLEFT", 14, -38)
    sub:SetText("Look and notifications, capture health, stored data.")

    -- ── sub-tabs: a real tab control on a bordered pane (UI.Tabs); panes built eagerly so tests cover them
    local subtabs = ns.UI.Tabs(content, { { key = "general", label = "General" }, { key = "capture", label = "Capture" }, { key = "data", label = "Data" } }, nil, 14)
    content.subtabs = subtabs
    local general, capture, data = subtabs.panes.general, subtabs.panes.capture, subtabs.panes.data

    -- ═══ General: flag position · window size · on-screen notifications ═══
    local flagHdr = ns.UI.FS(general, "GameFontNormal", C.gold); flagHdr:SetPoint("TOPLEFT", 14, -6); flagHdr:SetText("Flag position")
    local choices = {
      { "TOPLEFT", "Top left" }, { "TOPRIGHT", "Top right" },
      { "BOTTOMLEFT", "Bottom left" }, { "BOTTOMRIGHT", "Bottom right" },
    }
    local btns = {}
    local function refresh()
      local cur = (ns.DB and ns.DB.settings and ns.DB.settings.emitCorner) or "TOPLEFT"
      for _, b in ipairs(btns) do
        local col = (b.corner == cur) and C.gold or C.dim
        b.text:SetTextColor(col[1], col[2], col[3])
      end
    end
    local x, y = 14, -32
    for i, ch in ipairs(choices) do
      local b = ns.UI.Button(general, ch[2], 130, 28, function() Emitter.setCorner(ch[1]); refresh() end)
      b.corner = ch[1]; b:SetPoint("TOPLEFT", x, y); btns[#btns + 1] = b
      if i % 2 == 0 then x = 14; y = y - 36 else x = x + 140 end
    end
    local PREVIEW = { { "LEVELUP", {} }, { "LOOT", { name = "Cursed Felblade", count = 1 } }, { "BOSS", { name = "Edwin VanCleef" } }, { "DEATH", {} }, { "DISCOVERY", { name = "Westfall" } } }
    local previewI = 0
    local preview = ns.UI.Button(general, "Preview a notification", 200, 26, function()
      previewI = (previewI % #PREVIEW) + 1
      local pv = PREVIEW[previewI]
      Emitter.event(pv[1], pv[2])   -- cycles level-up, loot, boss, death, discovery so every style is seen
    end)
    preview:SetPoint("TOPLEFT", 14, y - 8)

    -- flag size + hide
    local fsHdr = ns.UI.FS(general, "GameFontNormal", C.gold); fsHdr:SetPoint("TOPLEFT", 14, y - 48); fsHdr:SetText("Flag size")
    local fsl = CreateFrame("Slider", "EverbuffFlagScaleSlider", general, "OptionsSliderTemplate")
    fsl:SetOrientation("HORIZONTAL"); fsl:SetWidth(240); fsl:SetHeight(16); fsl:SetPoint("TOPLEFT", 18, y - 76)
    fsl:SetMinMaxValues(0.7, 1.5); fsl:SetValueStep(0.05); fsl:SetObeyStepOnDrag(true)
    if _G.EverbuffFlagScaleSliderLow then _G.EverbuffFlagScaleSliderLow:SetText("70%") end
    if _G.EverbuffFlagScaleSliderHigh then _G.EverbuffFlagScaleSliderHigh:SetText("150%") end
    local curFs = (ns.DB and ns.DB.settings and tonumber(ns.DB.settings.flagScale)) or 1
    fsl:SetValue(curFs)
    if _G.EverbuffFlagScaleSliderText then _G.EverbuffFlagScaleSliderText:SetText(math.floor(curFs * 100 + 0.5) .. "%") end
    fsl:SetScript("OnValueChanged", function(_, val)
      Emitter.setFlagScale(val)
      if _G.EverbuffFlagScaleSliderText then _G.EverbuffFlagScaleSliderText:SetText(math.floor(val * 100 + 0.5) .. "%") end
    end)
    local faHdr = ns.UI.FS(general, "GameFontNormal", C.gold); faHdr:SetPoint("TOPLEFT", 14, y - 98); faHdr:SetText("Flag opacity")
    local fal = CreateFrame("Slider", "EverbuffFlagAlphaSlider", general, "OptionsSliderTemplate")
    fal:SetOrientation("HORIZONTAL"); fal:SetWidth(240); fal:SetHeight(16); fal:SetPoint("TOPLEFT", 18, y - 126)
    fal:SetMinMaxValues(0.3, 1); fal:SetValueStep(0.05); fal:SetObeyStepOnDrag(true)
    if _G.EverbuffFlagAlphaSliderLow then _G.EverbuffFlagAlphaSliderLow:SetText("30%") end
    if _G.EverbuffFlagAlphaSliderHigh then _G.EverbuffFlagAlphaSliderHigh:SetText("100%") end
    local curFa = (ns.DB and ns.DB.settings and tonumber(ns.DB.settings.flagAlpha)) or 1
    fal:SetValue(curFa)
    if _G.EverbuffFlagAlphaSliderText then _G.EverbuffFlagAlphaSliderText:SetText(math.floor(curFa * 100 + 0.5) .. "%") end
    fal:SetScript("OnValueChanged", function(_, val)
      Emitter.setFlagAlpha(val)
      if _G.EverbuffFlagAlphaSliderText then _G.EverbuffFlagAlphaSliderText:SetText(math.floor(val * 100 + 0.5) .. "%") end
    end)
    local hideCb = CreateFrame("CheckButton", nil, general, "UICheckButtonTemplate"); hideCb:SetPoint("TOPLEFT", 14, y - 148); hideCb:SetSize(22, 22)
    hideCb:SetChecked(ns.DB and ns.DB.settings and ns.DB.settings.flagHidden and true or false)
    local hideLbl = ns.UI.FS(general, "GameFontHighlightSmall"); hideLbl:SetPoint("LEFT", hideCb, "RIGHT", 4, 0); hideLbl:SetWidth(290); hideLbl:SetJustifyH("LEFT")
    hideLbl:SetText("Hide the flag and notifications")
    local hideWarn = ns.UI.FS(general, "GameFontDisableSmall", C.dim); hideWarn:SetPoint("TOPLEFT", 40, y - 170); hideWarn:SetWidth(280); hideWarn:SetJustifyH("LEFT")
    hideWarn:SetText("The desktop app reads the flag to mark moments in your recording. Hidden means no markers. Everything is still recorded here.")
    hideCb:SetScript("OnClick", function(self) Emitter.setFlagHidden(self:GetChecked() and true or false) end)

    local scHdr = ns.UI.FS(general, "GameFontNormal", C.gold); scHdr:SetPoint("TOPLEFT", 14, y - 210); scHdr:SetText("Window size")
    local sc = CreateFrame("Slider", "EverbuffScaleSlider", general, "OptionsSliderTemplate")
    sc:SetOrientation("HORIZONTAL"); sc:SetWidth(240); sc:SetHeight(16); sc:SetPoint("TOPLEFT", 18, y - 238)
    sc:SetMinMaxValues(0.7, 1.3); sc:SetValueStep(0.05); sc:SetObeyStepOnDrag(true)
    if _G.EverbuffScaleSliderLow then _G.EverbuffScaleSliderLow:SetText("70%") end
    if _G.EverbuffScaleSliderHigh then _G.EverbuffScaleSliderHigh:SetText("130%") end
    local curSc = (ns.DB and ns.DB.settings and tonumber(ns.DB.settings.winScale)) or 1
    sc:SetValue(curSc)
    if _G.EverbuffScaleSliderText then _G.EverbuffScaleSliderText:SetText(math.floor(curSc * 100 + 0.5) .. "%") end
    sc:SetScript("OnValueChanged", function(_, val)
      val = math.floor(val * 20 + 0.5) / 20
      if ns.DB and ns.DB.settings then ns.DB.settings.winScale = val end
      if ns.UI.SetWindowScale then ns.UI.SetWindowScale(val) end
      if _G.EverbuffScaleSliderText then _G.EverbuffScaleSliderText:SetText(math.floor(val * 100 + 0.5) .. "%") end
    end)

    local ntHdr = ns.UI.FS(general, "GameFontNormal", C.gold); ntHdr:SetPoint("TOPLEFT", 340, -6); ntHdr:SetText("On-screen notifications")
    local ntSub = ns.UI.FS(general, "GameFontDisableSmall", C.dim); ntSub:SetPoint("TOPLEFT", 340, -26); ntSub:SetWidth(330); ntSub:SetJustifyH("LEFT")
    ntSub:SetText("Level-ups, deaths and wipes always show. Untick a group to keep it off screen; it is still recorded in the Timeline.")
    local ny = -62
    for _, g in ipairs({
      { "travel",   "Travel: zones, dungeons, discoveries, flight paths" },
      { "quests",   "Quests: accepted, completed, rewards" },
      { "kills",    "Kills: notable mobs and boss pulls" },
      { "loot",     "Loot: drops at or above the threshold below" },
      { "progress", "Progress: skill-ups, spells, reputation, achievements, collections" },
    }) do
      local cb = CreateFrame("CheckButton", nil, general, "UICheckButtonTemplate"); cb:SetPoint("TOPLEFT", 342, ny); cb:SetSize(22, 22)
      local muted = ns.DB and ns.DB.settings and ns.DB.settings.flagMute and ns.DB.settings.flagMute[g[1]]
      cb:SetChecked(not muted)
      local lbl = ns.UI.FS(general, "GameFontHighlightSmall"); lbl:SetPoint("LEFT", cb, "RIGHT", 4, 0); lbl:SetWidth(300); lbl:SetJustifyH("LEFT"); lbl:SetText(g[2])
      cb:SetScript("OnClick", function(self)
        if ns.DB and ns.DB.settings then
          ns.DB.settings.flagMute = ns.DB.settings.flagMute or {}
          ns.DB.settings.flagMute[g[1]] = (not self:GetChecked()) and true or nil
        end
      end)
      ny = ny - 24
    end
    local ltHdr = ns.UI.FS(general, "GameFontHighlightSmall", C.dim); ltHdr:SetPoint("TOPLEFT", 342, ny - 6); ltHdr:SetText("Loot toast threshold")
    local ltBtns = {}
    local function refreshLT()
      local cur = (ns.DB and ns.DB.settings and ns.DB.settings.lootToast) or "rare"
      for _, b in ipairs(ltBtns) do local col = (b.mode == cur) and C.gold or C.dim; b.text:SetTextColor(col[1], col[2], col[3]) end
    end
    local lx = 342
    for _, m in ipairs({ { "uncommon", "Uncommon+" }, { "rare", "Rare+" }, { "epic", "Epic+" }, { "off", "Off" } }) do
      local b = ns.UI.Button(general, m[2], 78, 24, function() if ns.DB and ns.DB.settings then ns.DB.settings.lootToast = m[1] end; refreshLT() end)
      b.mode = m[1]; b:SetPoint("TOPLEFT", lx, ny - 24); ltBtns[#ltBtns + 1] = b; lx = lx + 84
    end
    refreshLT()

    -- ═══ Capture: health + disconnect protection (Sync.lua) ═══
    if ns.BuildCapturePane then ns.BuildCapturePane(capture) end

    -- ═══ Data: stored counts · clear · fight stat sampling ═══
    local dataHdr = ns.UI.FS(data, "GameFontNormal", C.gold); dataHdr:SetPoint("TOPLEFT", 14, -6); dataHdr:SetText("Stored data")
    local dataInfo = ns.UI.FS(data, "GameFontHighlightSmall", C.dim); dataInfo:SetPoint("TOPLEFT", 18, -30); dataInfo:SetWidth(660); dataInfo:SetJustifyH("LEFT")
    local function refreshData()
      local db = ns.DB or { combat = {}, loot = {}, story = {} }
      local nF = #(db.combat.fights or {})
      local capF = 1000
      if ns.Fights and ns.Fights.capInfo then nF, capF = ns.Fights.capInfo() end
      local pending = 0
      for _, f in ipairs(db.combat.fights or {}) do if f.uploaded ~= true then pending = pending + 1 end end
      dataInfo:SetText(("%d of %d fights  ·  %d loot  ·  %d events  ·  %d fights waiting for the desktop app%s"):format(
        nF, capF, #(db.loot.log or {}), #(db.story.events or {}), pending,
        (nF >= capF - 25) and "   (near the cap: oldest fights roll off)" or ""))
    end
    local function clearBtn(label, bx, fn)
      local b = ns.UI.Button(data, label, 132, 24)
      b:SetPoint("TOPLEFT", dataInfo, "BOTTOMLEFT", bx, -12)
      b.armed = false
      b:SetScript("OnClick", function(bb)
        if not bb.armed then
          bb.armed = true; bb.text:SetText("Confirm?"); bb.text:SetTextColor(C.red[1], C.red[2], C.red[3])
          C_Timer.After(3, function()
            if bb.armed then bb.armed = false; bb.text:SetText(label); bb.text:SetTextColor(C.gold[1], C.gold[2], C.gold[3]) end
          end)
        else
          bb.armed = false; bb.text:SetText(label); bb.text:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
          fn(); refreshData()
        end
      end)
      return b
    end
    clearBtn("Clear fights", 0, function() if ns.DB then ns.DB.combat.fights = {}; ns.DB.combat.fightSeq = 0 end end)
    clearBtn("Clear loot", 140, function() if ns.DB then ns.DB.loot.log = {}; if ns.DB.loot.gold then ns.DB.loot.gold.looted = 0 end end end)
    clearBtn("Clear events", 280, function() if ns.DB then ns.DB.story.events = {} end end)

    local sampHdr = ns.UI.FS(data, "GameFontNormal", C.gold); sampHdr:SetPoint("TOPLEFT", 14, -104); sampHdr:SetText("Fight stat sampling")
    local samp = CreateFrame("Slider", "EverbuffSampleSlider", data, "OptionsSliderTemplate")
    samp:SetOrientation("HORIZONTAL"); samp:SetWidth(240); samp:SetHeight(16); samp:SetPoint("TOPLEFT", 18, -130)
    local smin = (ns.Fights and ns.Fights.SAMPLE_MIN) or 1
    local smax = (ns.Fights and ns.Fights.SAMPLE_MAX) or 10
    samp:SetMinMaxValues(smin, smax); samp:SetValueStep(1); samp:SetObeyStepOnDrag(true)
    if _G.EverbuffSampleSliderLow then _G.EverbuffSampleSliderLow:SetText(smin .. "s") end
    if _G.EverbuffSampleSliderHigh then _G.EverbuffSampleSliderHigh:SetText(smax .. "s") end
    local curSamp = (ns.DB and ns.DB.settings and tonumber(ns.DB.settings.statSample)) or (ns.Fights and ns.Fights.DEFAULT_SAMPLE) or 1
    samp:SetValue(curSamp)
    if _G.EverbuffSampleSliderText then _G.EverbuffSampleSliderText:SetText("every " .. curSamp .. "s") end
    samp:SetScript("OnValueChanged", function(_, val)
      val = math.floor(val + 0.5)
      if ns.DB and ns.DB.settings then ns.DB.settings.statSample = val end
      if _G.EverbuffSampleSliderText then _G.EverbuffSampleSliderText:SetText("every " .. val .. "s") end
    end)
    local sampDesc = ns.UI.FS(data, "GameFontDisableSmall", C.dim); sampDesc:SetPoint("TOPLEFT", 14, -160); sampDesc:SetWidth(640); sampDesc:SetJustifyH("LEFT")
    sampDesc:SetText("How often character stats are snapshotted during a fight. Lower = finer scrubber detail but more SavedVariables. Applies from your next fight.")

    -- desktop sync: paste the code the desktop app shows after an upload; acked data is pruned here
    local ackHdr = ns.UI.FS(data, "GameFontNormal", C.gold); ackHdr:SetPoint("TOPLEFT", 14, -200); ackHdr:SetText("Desktop sync")
    local ackBox = ns.UI.EditBox(data, 380, 22); ackBox:SetPoint("TOPLEFT", 18, -224)
    local ackHint = ns.UI.FS(data, "GameFontDisableSmall", C.dim); ackHint:SetPoint("LEFT", ackBox, "LEFT", 8, 0); ackHint:SetText("paste the sync code from the desktop app")
    ackBox:SetScript("OnTextChanged", function(e) if (e:GetText() or "") == "" then ackHint:Show() else ackHint:Hide() end end)
    local ackInfo = ns.UI.FS(data, "GameFontDisableSmall", C.dim); ackInfo:SetPoint("TOPLEFT", 14, -252); ackInfo:SetWidth(640); ackInfo:SetJustifyH("LEFT")
    local function refreshAck()
      local la = ns.DB and ns.DB.combat and ns.DB.combat.lastAck
      ackInfo:SetText(la and ("Last synced %s via %s: %d fights acked. The desktop app can also sync on its own while the game is closed."):format(date("%b %d, %H:%M", la.at or 0), la.source == "paste" and "a pasted code" or "the desktop file", la.fights or 0)
        or "Never synced. Uploaded fights, loot and events are pruned here once the desktop app acks them. It syncs on its own while the game is closed, or paste its code above.")
    end
    local ackBtn = ns.UI.Button(data, "Apply", 80, 22, function()
      local ack = ns.parseAckCode(ackBox:GetText())
      if ack then
        local marked = ns.applyAck(ack, "paste"); ackBox:SetText(""); refreshData(); refreshAck()
        if ns.msg then ns.msg(("desktop sync applied: %d fight%s acked"):format(marked, marked == 1 and "" or "s")) end
      else ackInfo:SetText("|cffe5484dThat is not a sync code.|r It looks like EB-ACK-<number>, shown by the desktop app after an upload.") end
    end)
    ackBtn:SetPoint("LEFT", ackBox, "RIGHT", 8, 0)
    content.ackBox, content.ackBtn = ackBox, ackBtn
    refreshAck()

    refreshData()
    content.refresh = function() refresh(); refreshData(); if ns.RefreshCapturePane then ns.RefreshCapturePane() end end
    subtabs.select("general"); refresh()
  end, function() end, nil, "bottom")

  -- ── Events tab: a filterable timeline of everything Everbuff.GG detected, newest first ──
  -- Journey / Combat / Travel / Loot chips cut the firehose; a Where column surfaces the coordinates
  -- every event already carries; combat rows jump to their fight, loot rows to the Loot tab.
  local eventsRebuild, eventsTicker, eventsView
  local EVENT_GROUP = {
    journey = { LEVELUP = true, ACHIEV = true, SPELL = true, REP = true, SKILLUP = true, REWARD = true, QUESTACCEPT = true, QUESTDONE = true, BROKEN = true, COLLECT = true, PROFTIER = true, RECIPE = true, UPGRADE = true },
    combat  = { BOSS = true, KILL = true, WIPE = true, DEATH = true, ALIVE = true, ROSTERJOIN = true, ROSTERLEAVE = true },
    travel  = { ZONE = true, DUNGEON = true, DUNGEONLEAVE = true, DISCOVERY = true, FLIGHT = true, FIRSTZONE = true, FLIGHTTRIP = true },
    loot    = { LOOT = true },
    professions = { SKILLUP = true, PROFTIER = true, RECIPE = true },
  }
  -- an optional time window (a fight's span) set by ns.OpenTimelineWindow; cleared from the banner
  local window = nil   -- { t0, t1, label }
  local function eventMatches(e, filter, q)
    if window and ((e.t or 0) < window.t0 or (e.t or 0) > window.t1) then return false end
    if q and q ~= "" then
      q = q:lower()
      local hay = ((e.text or "") .. " " .. (e.zone or "") .. " " .. (e.sub or "") .. " " .. (e.foe or "") .. " " .. (e.kind or "")):lower()
      if not hay:find(q, 1, true) then return false end
    end
    if filter == "all" then return true end
    local g = EVENT_GROUP[filter]
    return (g and g[e.kind]) and true or false
  end
  -- "Sub, Zone  (x, y)" from the location stamp; degrades gracefully when parts are missing
  local function fmtWhere(e) return ns.UI.fmtLocation(e.zone, e.x, e.y, e.sub) end
  -- the fight that was running when this event happened (for click-through)
  local function fightAt(t)
    for _, f in ipairs((ns.Fights and ns.Fights.list and ns.Fights.list()) or {}) do
      local st = f.startEpoch or 0
      if t >= st - 1 and t <= st + (f.duration or 0) + 2 then return f end
    end
  end
  ns.UI.registerPane("Home", 2, "Timeline", function(content)
    local C = ns.UI.C
    eventsView = content
    local LABELS = {
      LEVELUP = "Level up", ZONE = "Zone", DUNGEON = "Dungeon", DUNGEONLEAVE = "Dungeon",
      QUESTACCEPT = "Quest", QUESTDONE = "Quest", BOSS = "Boss", KILL = "Kill", WIPE = "Wipe",
      DEATH = "Death", ALIVE = "Revived", SKILLUP = "Skill up", DISCOVERY = "Discovery",
      LOOT = "Loot", REWARD = "Reward",
      ACHIEV = "Achievement", SPELL = "Learned", REP = "Reputation", FLIGHT = "Flight path",
      FIRSTZONE = "First visit", ROSTERJOIN = "Joined", ROSTERLEAVE = "Left", BROKEN = "Broken gear",
      COLLECT = "Collected", PROFTIER = "Profession", FLIGHTTRIP = "Flight", RECIPE = "Recipe", UPGRADE = "Gear up",
    }
    -- filter TABS on a bordered pane; the list lives inside the pane
    local filter = "all"
    local tabs = ns.UI.Tabs(content, {
      { key = "all", label = "All" }, { key = "journey", label = "Journey" }, { key = "combat", label = "Combat" },
      { key = "travel", label = "Travel" }, { key = "loot", label = "Loot" }, { key = "professions", label = "Professions" },
    }, -30, 2, { shared = true, onSelect = function(key) filter = key; if eventsRebuild then eventsRebuild() end end })
    content.tabs = tabs
    local pane = tabs.content
    -- text search (right of the header row)
    local search = ns.UI.EditBox(pane, 180, 20); search:SetPoint("TOPRIGHT", -24, -4)
    local hint = ns.UI.FS(pane, "GameFontDisableSmall", C.dim); hint:SetPoint("LEFT", search, "LEFT", 8, 0); hint:SetText("search events")
    -- window banner: "Showing <fight> · clear"
    local banner = ns.UI.Button(pane, "", 320, 20, function() window = nil; if eventsRebuild then eventsRebuild() end end)
    banner:SetPoint("TOPLEFT", 2, -4); banner:Hide()
    content.timelineBanner = banner
    ns.OpenTimelineWindow = function(t0, t1, label)
      window = { t0 = t0, t1 = t1, label = label or "this window" }
      if ns.UI.Open then ns.UI.Open("Home", "timeline") end
      if eventsRebuild then eventsRebuild() end
    end
    ns._test.timelineWindow = function() return window end
    search:SetScript("OnTextChanged", function(e)
      if (e:GetText() or "") == "" then hint:Show() else hint:Hide() end
      if eventsRebuild then eventsRebuild() end
    end)
    content.search = search
    -- columns: Time · Type · Event · Location (name) · Coords · While fighting (source)
    local COL = { time = 0, type = 66, ev = 156, where = 358, coords = 490, foe = 576 }
    local WID = { time = 60, type = 84, ev = 196, where = 126, coords = 80, foe = 94 }
    local ROWW = 670
    local hdr = CreateFrame("Frame", nil, pane); hdr:SetPoint("TOPLEFT", 2, -30); hdr:SetSize(ROWW, 16)
    local function head(col, w, text)
      local fs = ns.UI.FS(hdr, "GameFontNormalSmall")
      fs:SetPoint("LEFT", col, 0); if w then fs:SetWidth(w) end; fs:SetJustifyH("LEFT")
      fs:SetText(text:upper()); fs:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
    end
    head(COL.time, WID.time, "Time"); head(COL.type, WID.type, "Type"); head(COL.ev, WID.ev, "Event")
    head(COL.where, WID.where, "Location"); head(COL.coords, WID.coords, "Coords"); head(COL.foe, WID.foe, "While fighting")
    local sf, child = ns.UI.ScrollChild(pane)
    sf:SetPoint("TOPLEFT", 0, -50); sf:SetPoint("BOTTOMRIGHT", -22, 2)
    child.rows = {}
    eventsRebuild = function()
      local log = (ns.DB and ns.DB.story.events) or {}
      local q = search:GetText()
      if window then banner.text:SetText(("Showing: %s   ·   click to show everything"):format(window.label)); banner:Show() else banner:Hide() end
      local y, idx, dn, lastDay = 0, 0, 0, nil
      child.days = child.days or {}
      for i = #log, 1, -1 do
        local e = log[i]
        if eventMatches(e, filter, q) then
          local day = date("%Y-%m-%d", e.t or 0)
          if day ~= lastDay then                          -- a day header whenever the date changes
            lastDay = day; dn = dn + 1
            local dfs = child.days[dn]
            if not dfs then dfs = ns.UI.FS(child, "GameFontNormalSmall", C.gold); dfs:SetJustifyH("LEFT"); child.days[dn] = dfs end
            dfs:ClearAllPoints(); dfs:SetPoint("TOPLEFT", 2, -(y + 4)); dfs:SetText(ns.UI.fmtDay(e.t):upper()); dfs:Show()
            y = y + 20
          end
          idx = idx + 1
          local row = child.rows[idx]
          if not row then
            row = CreateFrame("Button", nil, child, "BackdropTemplate"); row:SetHeight(18); row:SetPoint("RIGHT", child, "RIGHT", 0, 0)
            row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" }); row:SetBackdropColor(0, 0, 0, 0)
            row:SetScript("OnEnter", function(r)
              if r.clickable then r:SetBackdropColor(C.panel2[1], C.panel2[2], C.panel2[3], 0.6) end
              local ev = r.ev; if not (ev and GameTooltip) then return end
              GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
              GameTooltip:AddLine(ev.text or ev.kind or "?", 1, 1, 1, true)
              GameTooltip:AddLine(date("%b %d, %H:%M:%S", ev.t or 0) .. "  ·  " .. (LABELS[ev.kind] or ev.kind or ""), 0.8, 0.8, 0.8)
              local place = ns.UI.fmtPlace(ev.zone, ev.sub); local co = ns.UI.fmtCoords(ev.x, ev.y)
              if place ~= "" or co ~= "" then GameTooltip:AddLine(place .. (co ~= "" and ("  " .. co) or ""), 0.6, 0.7, 0.75) end
              if ev.standing then GameTooltip:AddLine("Standing: " .. tostring(ev.standing), 0.6, 0.7, 0.75) end
              if ev.craft then GameTooltip:AddLine(("Crafted: %s x%s"):format(tostring(ev.craft), tostring(ev.crafted or 1)), 0.6, 0.7, 0.75) end
              if ev.foe then GameTooltip:AddLine("While fighting: " .. tostring(ev.foe), 1.0, 0.44, 0.30) end
              if ev.downtime then GameTooltip:AddLine(("Back on your feet after %ds"):format(ev.downtime), 0.6, 0.7, 0.75) end
              if ev.guid then GameTooltip:AddLine("GUID: " .. tostring(ev.guid), 0.45, 0.5, 0.55) end
              if r.clickable then GameTooltip:AddLine("Click to open", 0.5, 0.65, 0.75) end
              GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function(r) r:SetBackdropColor(0, 0, 0, 0); if GameTooltip then GameTooltip:Hide() end end)
            row:SetScript("OnClick", function(r)
              local ev = r.ev; if not ev then return end
              if EVENT_GROUP.combat[ev.kind] then
                local f = fightAt(ev.t or 0); if f and ns.OpenFightDetail then ns.OpenFightDetail(f) end
              elseif ev.kind == "LOOT" and ns.UI.Open then ns.UI.Open("Loot", "items") end
            end)
            row.tm = ns.UI.FS(row, "GameFontDisableSmall"); row.tm:SetPoint("LEFT", COL.time, 0); row.tm:SetWidth(WID.time); row.tm:SetJustifyH("LEFT")
            row.ty = ns.UI.FS(row, "GameFontHighlightSmall"); row.ty:SetPoint("LEFT", COL.type, 0); row.ty:SetWidth(WID.type); row.ty:SetJustifyH("LEFT")
            row.tx = ns.UI.FS(row, "GameFontHighlightSmall"); row.tx:SetPoint("LEFT", COL.ev, 0); row.tx:SetWidth(WID.ev); row.tx:SetJustifyH("LEFT")
            row.wh = ns.UI.FS(row, "GameFontDisableSmall"); row.wh:SetPoint("LEFT", COL.where, 0); row.wh:SetWidth(WID.where); row.wh:SetJustifyH("LEFT")
            row.co = ns.UI.FS(row, "GameFontDisableSmall"); row.co:SetPoint("LEFT", COL.coords, 0); row.co:SetWidth(WID.coords); row.co:SetJustifyH("LEFT")
            row.fo = ns.UI.FS(row, "GameFontHighlightSmall"); row.fo:SetPoint("LEFT", COL.foe, 0); row.fo:SetWidth(WID.foe); row.fo:SetJustifyH("LEFT")
            child.rows[idx] = row
          end
          row.ev = e
          row.clickable = (EVENT_GROUP.combat[e.kind] and fightAt(e.t or 0) ~= nil) or e.kind == "LOOT"
          row:SetPoint("TOPLEFT", 0, -y); row:Show()
          row.tm:SetText(date("%H:%M:%S", e.t or 0)); row.tm:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
          row.ty:SetText(LABELS[e.kind] or e.kind or "?")
          local col = COLORS[e.kind] or C.dim
          row.ty:SetTextColor(col[1], col[2], col[3])
          row.tx:SetText((e.text or e.kind or "?") .. (row.clickable and "  |cff8c9197>|r" or "")); row.tx:SetTextColor(C.ink[1], C.ink[2], C.ink[3])
          row.wh:SetText(ns.UI.fmtPlace(e.zone, e.sub)); row.wh:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
          row.co:SetText(ns.UI.fmtCoords(e.x, e.y)); row.co:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
          if e.combat then row.fo:SetText(e.foe or "in combat"); row.fo:SetTextColor(EMBER[1], EMBER[2], EMBER[3]) else row.fo:SetText("") end
          y = y + 18
        end
      end
      for j = idx + 1, #child.rows do child.rows[j]:Hide() end
      for j = dn + 1, #child.days do child.days[j]:Hide() end
      if idx == 0 then
        child.empty = child.empty or (function()
          local fs = ns.UI.FS(child, "GameFontDisableSmall"); fs:SetPoint("TOPLEFT", 0, 0); return fs
        end)()
        child.empty:SetText(#log == 0 and "No events yet. Play and they show up here." or "No events match this filter or search.")
        child.empty:Show()
      elseif child.empty then child.empty:Hide() end
      child:SetSize(math.max(ROWW, (sf:GetWidth() or ROWW) - 4), math.max(1, y))
    end
    tabs.select("all")
  end, function()
    if eventsRebuild then eventsRebuild() end
    -- rebuild only while this tab is actually visible (the old ticker ran forever, even hidden)
    if not eventsTicker then
      eventsTicker = C_Timer.NewTicker(2, function()
        if eventsView and eventsView:IsShown() and eventsRebuild then eventsRebuild() end
      end)
    end
  end)
  ns._test = ns._test or {}; ns._test.eventMatches, ns._test.fmtWhere = eventMatches, fmtWhere
  ns._test.safeStr, ns._test.plainNum = safeStr, plainNum

  -- ── Loot tab: everything you've picked up (items + coin), newest first ─────────
  local function qrgb(q)
    if not q or #q < 8 then return 0.8, 0.8, 0.8 end
    return (tonumber(q:sub(3, 4), 16) or 200) / 255, (tonumber(q:sub(5, 6), 16) or 200) / 255, (tonumber(q:sub(7, 8), 16) or 200) / 255
  end
  local COIN_ICON = "Interface\\Icons\\INV_Misc_Coin_01"
  local function fmtMoney(c)
    c = math.floor(tonumber(c) or 0)
    local g, s, cp = math.floor(c / 10000), math.floor((c % 10000) / 100), c % 100
    local out = {}
    if g > 0 then out[#out + 1] = g .. "g" end
    if s > 0 then out[#out + 1] = s .. "s" end
    if cp > 0 or #out == 0 then out[#out + 1] = cp .. "c" end
    return table.concat(out, " ")
  end
  ns._test = ns._test or {}; ns._test.fmtMoney = fmtMoney
  local lootRebuild
  ns.UI.registerHost(2, "Loot", "Everything you picked up, newest first, and where your gold comes from and goes.")
  ns.UI.registerPane("Loot", 1, "Items", function(content)
    local C = ns.UI.C
    local totals = ns.UI.FS(content, "GameFontHighlightSmall", C.gold); totals:SetPoint("TOPLEFT", 2, -6)
    local search = ns.UI.EditBox(content, 180, 20); search:SetPoint("TOPRIGHT", -22, -2)
    local hint = ns.UI.FS(content, "GameFontDisableSmall", C.dim); hint:SetPoint("LEFT", search, "LEFT", 8, 0); hint:SetText("search item, source, zone")
    search:SetScript("OnTextChanged", function(e)
      if (e:GetText() or "") == "" then hint:Show() else hint:Hide() end
      if lootRebuild then lootRebuild() end
    end)
    content.search = search
    -- quality floor: All · Uncommon+ · Rare+ · Epic+ (coin rows always pass); sort key + direction
    local Q_RANK = { ff9d9d9d = 0, ffffffff = 1, ff1eff00 = 2, ff0070dd = 3, ffa335ee = 4, ffff8000 = 5, ffe6cc80 = 6 }
    local minQ, sortKey, sortAsc = 0, "time", false
    local qBtns = {}
    local function styleQ() for _, b in ipairs(qBtns) do local col = (b.minQ == minQ) and C.gold or C.dim; b.text:SetTextColor(col[1], col[2], col[3]) end end
    local qx = 2
    for _, qq in ipairs({ { 0, "All" }, { 2, "Uncommon+" }, { 3, "Rare+" }, { 4, "Epic+" } }) do
      local b = ns.UI.Button(content, qq[2], qq[2] == "All" and 44 or 84, 20, function(bb) minQ = bb.minQ; styleQ(); if lootRebuild then lootRebuild() end end)
      b.minQ = qq[1]; b:SetPoint("TOPLEFT", qx, -24); qBtns[#qBtns + 1] = b; qx = qx + (qq[2] == "All" and 50 or 90)
    end
    styleQ()
    content.lootFilter = function() return minQ, sortKey, sortAsc end
    -- sort keys read the same fields the columns show; coin rows sort by their value under "item"
    local function sortVal(e, key)
      if key == "time" then return e.t or 0
      elseif key == "item" then return (e.item or (e.money and ("~coin " .. tostring(e.money))) or ""):lower()
      elseif key == "qty" then return e.money and 0 or (tonumber(e.count) or 1)
      elseif key == "from" then return (e.src or ""):lower()
      elseif key == "loc" then return (e.zone or ""):lower()
      elseif key == "quality" then return Q_RANK[(e.q or ""):lower()] or (e.money and 1) or 1 end
      return 0
    end
    local function sortRows(rows)
      if sortKey == "time" and not sortAsc then return rows end   -- already newest first
      table.sort(rows, function(a, b)
        local va, vb = sortVal(a, sortKey), sortVal(b, sortKey)
        if va == vb then return (a.t or 0) > (b.t or 0) end
        if sortAsc then return va < vb else return va > vb end
      end)
      return rows
    end
    ns._test.lootSort = function(rows, key, asc) local k0, a0 = sortKey, sortAsc; sortKey, sortAsc = key, asc; local out = sortRows(rows); sortKey, sortAsc = k0, a0; return out end
    -- Newest (the log) or By item (one row per item: total quantity, drop count, most frequent source)
    local mode = "newest"
    local modeBtn = ns.UI.Button(content, "By item", 84, 20, function(b)
      mode = (mode == "newest") and "byitem" or "newest"
      b.text:SetText(mode == "newest" and "By item" or "Newest")
      if lootRebuild then lootRebuild() end
    end)
    modeBtn:SetPoint("RIGHT", search, "LEFT", -8, 0)
    content.lootMode = function() return mode end
    local function aggregate(loot, q, matches)
      local by, order = {}, {}
      for _, e in ipairs(loot) do
        if not e.money and matches(e, q) then
          local a = by[e.item]
          if not a then
            a = { item = e.item, count = 0, drops = 0, q = e.q, icon = e.icon, id = e.id, quest = e.quest, t = e.t, srcs = {}, agg = true }
            by[e.item] = a; order[#order + 1] = a
          end
          a.count = a.count + (tonumber(e.count) or 1); a.drops = a.drops + 1
          if (e.t or 0) > (a.t or 0) then a.t = e.t end
          if e.src then a.srcs[e.src] = (a.srcs[e.src] or 0) + 1 end
        end
      end
      for _, a in ipairs(order) do
        local best, bn = nil, 0
        for src, n in pairs(a.srcs) do if n > bn then best, bn = src, n end end
        a.src = best and (best .. (a.drops > 1 and ("  ·  %d drops"):format(a.drops) or "")) or nil
      end
      table.sort(order, function(a, b) if a.count ~= b.count then return a.count > b.count end return (a.t or 0) > (b.t or 0) end)
      return order
    end
    ns._test.lootAggregate = aggregate
    local function lootMatches(e, q)
      if minQ > 0 and not e.money and (Q_RANK[(e.q or ""):lower()] or 1) < minQ then return false end
      if not q or q == "" then return true end
      local hay = ((e.item or "") .. " " .. (e.src or "") .. " " .. (e.zone or "") .. " " .. (e.money and "coin gold" or "") .. (e.quest and " quest" or "")):lower()
      return hay:find(q:lower(), 1, true) ~= nil
    end
    ns._test = ns._test or {}; ns._test.lootMatches = lootMatches
    -- columns: Time · Item · Qty · Dropped by (source) · Location (name) · Coords
    local COL = { time = 0, icon = 70, item = 92, qty = 292, from = 334, loc = 480, coords = 606 }
    local WID = { time = 64, item = 196, qty = 36, from = 140, loc = 120, coords = 80 }
    -- fixed header row
    local hdr = CreateFrame("Frame", nil, content); hdr:SetPoint("TOPLEFT", 2, -48); hdr:SetSize(700, 16)
    local heads = {}
    local function styleHeads()
      for _, b in ipairs(heads) do
        local on = (b.key == sortKey)
        b.fs:SetText(b.label .. (on and (sortAsc and "  ^" or "  v") or ""))
        local col = on and C.gold or C.dim; b.fs:SetTextColor(col[1], col[2], col[3])
      end
    end
    local function head(key, col, w, text)
      local b = CreateFrame("Button", nil, hdr); b:SetPoint("LEFT", col, 0); b:SetSize(w or 60, 16)
      local fs = ns.UI.FS(b, "GameFontDisableSmall"); fs:SetPoint("LEFT", 0, 0); if w then fs:SetWidth(w) end; fs:SetJustifyH("LEFT")
      b.fs, b.key, b.label = fs, key, text
      if key then
        b:SetScript("OnClick", function(hb)
          if sortKey == hb.key then sortAsc = not sortAsc else sortKey = hb.key; sortAsc = (hb.key == "item" or hb.key == "from" or hb.key == "loc") end
          styleHeads(); if lootRebuild then lootRebuild() end
        end)
      end
      heads[#heads + 1] = b
    end
    head("time", COL.time, WID.time, "Time"); head("item", COL.icon, 120, "Item")
    head("qty", COL.qty, WID.qty, "Qty"); head("from", COL.from, WID.from, "Dropped by"); head("loc", COL.loc, WID.loc, "Location"); head(nil, COL.coords, WID.coords, "Coords")
    styleHeads()
    local sf, child = ns.UI.ScrollChild(content)
    sf:SetPoint("TOPLEFT", 0, -68); sf:SetPoint("BOTTOMRIGHT", -22, 2)
    child.rows = {}
    content.lootRows = child.rows
    local FALLBACK = "Interface\\Icons\\INV_Misc_QuestionMark"
    lootRebuild = function()
      local loot = (ns.DB and ns.DB.loot.log) or {}   -- persisted; survives reloads
      -- totals line: gold looted (running) + item pickups counted
      local items = 0
      for _, e in ipairs(loot) do if not e.money then items = items + 1 end end
      local goldLooted = (ns.DB and ns.DB.loot.gold and ns.DB.loot.gold.looted) or 0
      totals:SetText(("Looted:  %s  ·  %d item%s"):format(fmtMoney(goldLooted), items, items == 1 and "" or "s"))
      local y, idx = 0, 0
      local q = search:GetText()
      local rows
      if mode == "byitem" then rows = aggregate(loot, q, lootMatches)
      else rows = {}; for i = #loot, 1, -1 do if lootMatches(loot[i], q) then rows[#rows + 1] = loot[i] end end end
      rows = sortRows(rows)
      for _, e in ipairs(rows) do
        if true then
        idx = idx + 1
        local row = child.rows[idx]
        if not row then
          row = CreateFrame("Button", nil, child); row:SetHeight(20); row:SetPoint("RIGHT", child, "RIGHT", 0, 0)
          row:SetScript("OnEnter", function(r)
            if r.itemId and GameTooltip then
              GameTooltip:SetOwner(r, "ANCHOR_RIGHT"); GameTooltip:SetHyperlink("item:" .. tostring(r.itemId)); GameTooltip:Show()
            end
          end)
          row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
          row:SetScript("OnClick", function(r)
            if r.itemId and IsShiftKeyDown and IsShiftKeyDown() and GetItemInfo and ChatEdit_InsertLink then
              local _, link = GetItemInfo(r.itemId); if link then ChatEdit_InsertLink(link) end
            end
          end)
          row.lo = ns.UI.FS(row, "GameFontDisableSmall")
          row.lo:SetPoint("LEFT", COL.loc, 0); row.lo:SetWidth(WID.loc); row.lo:SetJustifyH("LEFT")
          row.co = ns.UI.FS(row, "GameFontDisableSmall")
          row.co:SetPoint("LEFT", COL.coords, 0); row.co:SetWidth(WID.coords); row.co:SetJustifyH("LEFT")
          row.tm = ns.UI.FS(row, "GameFontDisableSmall")
          row.tm:SetPoint("LEFT", COL.time, 0); row.tm:SetWidth(WID.time); row.tm:SetJustifyH("LEFT")
          row.ic = row:CreateTexture(nil, "ARTWORK"); row.ic:SetSize(16, 16); row.ic:SetPoint("LEFT", COL.icon, 0)
          row.nm = ns.UI.FS(row, "GameFontHighlightSmall")
          row.nm:SetPoint("LEFT", COL.item, 0); row.nm:SetWidth(WID.item); row.nm:SetJustifyH("LEFT")
          row.qt = ns.UI.FS(row, "GameFontHighlightSmall")
          row.qt:SetPoint("LEFT", COL.qty, 0); row.qt:SetWidth(WID.qty); row.qt:SetJustifyH("LEFT")
          row.fr = ns.UI.FS(row, "GameFontHighlightSmall")
          row.fr:SetPoint("LEFT", COL.from, 0); row.fr:SetWidth(WID.from); row.fr:SetJustifyH("LEFT")
          child.rows[idx] = row
        end
        row:SetPoint("TOPLEFT", 0, -y); row:Show()
        row.itemId = (not e.money) and tonumber(e.id) or nil       -- hover tooltip / shift-click link
        row.tm:SetText(date("%H:%M:%S", e.t or 0)); row.tm:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
        if e.money then
          -- coin looted from a mob/chest: gold amount instead of an item, no quantity
          row.ic:SetTexture(COIN_ICON)
          row.nm:SetText(fmtMoney(e.money)); row.nm:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
          row.qt:SetText("")
        else
          row.ic:SetTexture(e.icon or FALLBACK)
          row.nm:SetText((e.item or "?") .. (e.quest and "  |cff8c9197quest|r" or "")); row.nm:SetTextColor(qrgb(e.q))
          row.qt:SetText("x" .. (e.count or 1)); row.qt:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
        end
        -- legacy rows embedded " at (x, y)" in the source; split it out so old data still reads right
        local srcName, legacyLoc = (e.src or ""):match("^(.-) at (%(.-%))$")
        srcName = srcName or e.src
        row.fr:SetText(srcName or "unknown")
        if srcName then row.fr:SetTextColor(C.ink[1], C.ink[2], C.ink[3]) else row.fr:SetTextColor(C.dim[1], C.dim[2], C.dim[3]) end
        row.lo:SetText(e.zone or ""); row.lo:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
        -- legacy rows carried "(x, y)" inside the source; show it in the coords column, bare
        row.co:SetText((e.x and e.y) and ns.UI.fmtCoords(e.x, e.y) or (legacyLoc and legacyLoc:gsub("[()]", "")) or ""); row.co:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
        y = y + 20
        end
      end
      for j = idx + 1, #child.rows do child.rows[j]:Hide() end
      if idx == 0 then
        child.empty = child.empty or (function()
          local fs = ns.UI.FS(child, "GameFontDisableSmall")
          fs:SetPoint("TOPLEFT", 0, 0); fs:SetText("No loot yet. Items and coin you pick up show here."); return fs
        end)()
        child.empty:Show()
      elseif child.empty then child.empty:Hide() end
      child:SetSize(math.max(700, (sf:GetWidth() or 700) - 4), math.max(1, y))
    end
    lootRebuild()
  end, function() if lootRebuild then lootRebuild() end end)
end

-- ── test exports: headless luajit tests in tests/ read these; no effect in-game ──
ns._test = ns._test or {}
ns._test.fmtToPattern = fmtToPattern
ns._test.flagMuted, ns._test.FLAG_GROUP_OF = flagMuted, FLAG_GROUP_OF
ns._test.toastQueue = function() return queue end
ns._test.emitterFrame = ef
ns._test.flagFrame = function() return flag end
ns._test.toastBusy = function() return hideAt > 0 and GetTime() < hideAt end
ns._test.onDurability = onDurability
ns._test.killXpFrom = killXpFrom
ns._test.isSelfLoot = isSelfLoot
ns._test.lootQuiet = lootQuiet
ns._test.safeStr = safeStr
ns._test.plainNum = plainNum
ns._test.onMoney, ns._test.onXP, ns._test.onPlayed = onMoney, onXP, onPlayed
ns._test.CREATE_PAT, ns._test.SKILLUP_PAT = CREATE_PAT, SKILLUP_PAT
ns._test.DISCOVER_XP_PAT, ns._test.DISCOVER_PAT = DISCOVER_XP_PAT, DISCOVER_PAT
