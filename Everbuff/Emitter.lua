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
-- strips, no encoded cells. The desktop reads the flag as the player sees it (founder approval on
-- everbuff-desktop #72, 2026-09-28): the mark's red and white combat tint and OCR of the human line beside
-- it. No machine line is drawn (the proposal on everbuff-wow-addon #10 was closed as not needed). The short
-- "machine" string built below is the compact label for the event kind in the timeline, never drawn.

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
  if not (GameTooltip and GameTooltip.SetOwner) then return end
  GameTooltip:SetOwner(self, "ANCHOR_NONE")
  GameTooltip:ClearAllPoints()
  if key == "TOPRIGHT" then GameTooltip:SetPoint("TOPRIGHT", self, "BOTTOMRIGHT", 0, -6)
  elseif key == "BOTTOMLEFT" then GameTooltip:SetPoint("BOTTOMLEFT", self, "TOPLEFT", 0, 6)
  elseif key == "BOTTOMRIGHT" then GameTooltip:SetPoint("BOTTOMRIGHT", self, "TOPRIGHT", 0, 6)
  else GameTooltip:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -6) end
  GameTooltip:AddLine("everbuff.gg")
  GameTooltip:AddLine("Left-click  ·  open everbuff.gg", 0.8, 0.8, 0.8)
  GameTooltip:AddLine("Drag  ·  move anywhere", 0.8, 0.8, 0.8)
  GameTooltip:AddLine("Right-click  ·  snap to a corner", 0.8, 0.8, 0.8)
  -- the gold block under the four help lines: built, and switched off in code (ns.Gold.FLAG_TIP) until the desktop
  -- has replayed its fixtures with the taller tooltip (0.9.45, #43, decision 3c)
  if ns.Gold and ns.Gold.flagTip then pcall(ns.Gold.flagTip, GameTooltip, self) end
  GameTooltip:Show()
end)
flag:SetScript("OnLeave", function() emblem:SetSize(30, 30); if GameTooltip then GameTooltip:Hide() end end)

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
-- flag prefs: only the size, 100 to 150 %. The desktop reads the flag to align the recording, so it is always
-- shown at full opacity (founder, 2026-10-01, desktop #90: without the flag the data cannot be aligned). Smaller
-- sizes and lower opacity were never proven readable; the hide switch and the opacity slider are gone, and a saved
-- `flagHidden` or `flagAlpha` from an older version is dropped.
local FLAG_MIN, FLAG_MAX = 1.0, 1.5
Emitter.FLAG_RANGE = { FLAG_MIN, FLAG_MAX }   -- Settings > General reads the flag size range here
local function flagPrefs()
  local st = (ns.DB and ns.DB.settings) or {}
  st.flagHidden, st.flagAlpha = nil, nil
  local sc = tonumber(st.flagScale) or 1
  if sc < FLAG_MIN then sc = FLAG_MIN elseif sc > FLAG_MAX then sc = FLAG_MAX end
  return sc
end
local function applyFlagPrefs()
  local sc = flagPrefs()
  flag:SetScale(sc); panel:SetScale(sc); flag:SetAlpha(1)
  flag:Show()
end
Emitter.applyFlagPrefs = applyFlagPrefs
function Emitter.setFlagScale(v)
  if ns.blockedInCombat() then return end
  v = tonumber(v) or 1
  if v < FLAG_MIN then v = FLAG_MIN elseif v > FLAG_MAX then v = FLAG_MAX end
  if ns.DB and ns.DB.settings then ns.DB.settings.flagScale = math.floor(v * 20 + 0.5) / 20 end
  applyFlagPrefs()
  if ns.Gold and ns.Gold.flagMoved then pcall(ns.Gold.flagMoved) end   -- the gold pill stays clear of the bigger flag
end
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
  if ns.Gold and ns.Gold.flagMoved then pcall(ns.Gold.flagMoved) end   -- the gold pill makes way for the flag
end
-- the widest the notification line gets, in the panel's own units (times the flag's size on screen); the gold pill
-- keeps clear of this reach (ns.Gold.flagRect)
Emitter.TOAST_MAX_W = 600

-- ── curated toast (human) ──
local hideAt = 0
local queue = {}
local TOAST_PRIORITY = { LEVELUP = true, DEATH = true, WIPE = true, BOSS = true, ACHIEV = true }
local function show(kind, human, rec)
  -- the moment it reaches the screen, on the client's own clock: the desktop sees the same notification in
  -- the video, so the pair is an alignment anchor (everbuff-desktop #72). Data only; nothing on screen changes.
  if rec then rec.shown = math.floor(GetTime() * 1000 + 0.5) / 1000 end
  local col = COLORS[kind] or GOLD
  accent:SetColorTexture(col[1], col[2], col[3], 1)
  hero:SetTextColor(BONE[1], BONE[2], BONE[3]); hero:SetText(human or kind)   -- the kind's color is the tick only
  panel:SetWidth(math.min(Emitter.TOAST_MAX_W, (hero:GetStringWidth() or 0) + ICON_INSET + 16)); panel:SetHeight(40)
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
  elseif kind == "GOLDAWAY" or kind == "TRADE" then
    local m = type(d.money) == "number" and d.money or 0   -- our own purse: a plain number
    local c = math.abs(m); local g, sv, cp = math.floor(c / 10000), math.floor(c % 10000 / 100), c % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. "g" end
    if sv > 0 then parts[#parts + 1] = sv .. "s" end
    if cp > 0 or #parts == 0 then parts[#parts + 1] = cp .. "c" end
    local amt = (m < 0 and "-" or "+") .. table.concat(parts, " ")
    machine = kind .. " " .. m
    human = kind == "TRADE" and ("Trade %s with %s"):format(amt, name) or ("Gold elsewhere " .. amt)   -- the amount first: a narrow column shortens the end
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
      xp = (kind == "QUESTDONE" and type(d.xp) == "number" and d.xp > 0) and d.xp or nil,   -- the quest's XP reward
      money = (kind == "GOLDAWAY" or kind == "TRADE") and type(d.money) == "number" and d.money or nil,   -- copper, signed (#31)
      -- seconds on the taxi (FLIGHTTRIP, #11): the catalog's T-2 and T-5 read it per trip, not from the text
      duration = (kind == "FLIGHTTRIP" and type(d.duration) == "number") and math.floor(d.duration * 10 + 0.5) / 10 or nil,
      guid = d.guid,          -- exact npc guid for a precise kill (PARTY_KILL) - desktop attribution
      -- location, for map correlation on the desktop
      zone = L.zone, sub = L.sub, map = L.map, x = L.x, y = L.y,
    }
    ns.DB.story.events[#ns.DB.story.events + 1] = rec
    ns.trimToCap(ns.DB.story.events, 500)
    if ns.Recorder and ns.Recorder.bump then
      -- (a session's `dungeons` counts runs from 0.9.50, bumped where a run opens, Runs.lua; it counted DUNGEON events)
      if kind == "KILL" then ns.Recorder.bump("kills") elseif kind == "DEATH" then ns.Recorder.bump("deaths") end
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
  if ns.Gold and ns.Gold.flagMoved then pcall(ns.Gold.flagMoved) end   -- the gold pill makes way for the flag
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

-- Is the player in a dungeon or raid, and which? WoW Forever answers GetInstanceInfo() inside Shadowfang Keep with
-- instance type "none" (a session there started with context "Shadowfang Keep" from the zone text and recorded no
-- DUNGEON), so one signal is not enough. Any of these says yes, in order: GetInstanceInfo's type, IsInInstance's
-- type, the map the player stands on being a dungeon map (C_Map mapType 4), the zone being a known instance by name.
-- Returns name, kind ("party" or "raid") or nil. The raw answers go to settings.selftest.instance for the next look,
-- and (0.9.49) to settings.selftest.instances, one sticky record per dungeon: `sig` names the signal that fired
-- ("type", "ptype", "mapType" or "name", strongest first) and the newest answer under each signal is kept
-- (instances[name].bySig[sig]), so one evening's save says what the client answers inside every dungeon visited,
-- inside it when the type reads "none" (sig "mapType": the map id in question) and at its door (sig "name").
-- The signal of the last check of this load is Emitter._sig (nil before the first check and outside).
Emitter.SIG_RANK = { type = 4, ptype = 3, mapType = 2, name = 1 }
Emitter.INSTANCES_CAP = 40
function Emitter.noteInstance(key, rec)
  local st = ns.DB and ns.DB.settings and ns.DB.settings.selftest
  if type(st) ~= "table" or type(key) ~= "string" or key == "" then return end
  if type(st.instances) ~= "table" then st.instances = {} end
  local R, e = Emitter.SIG_RANK, st.instances[key]
  if type(e) ~= "table" then
    local n, oldK, oldAt = 0, nil, nil
    for k, v in pairs(st.instances) do
      n = n + 1
      local at = type(v) == "table" and type(v.at) == "number" and v.at or 0
      if not oldAt or at < oldAt then oldK, oldAt = k, at end
    end
    if n >= Emitter.INSTANCES_CAP and oldK ~= nil then st.instances[oldK] = nil end   -- the one not seen for longest
    e = {}; st.instances[key] = e
  end
  e.at = rec.at
  if type(e.bySig) ~= "table" then e.bySig = {} end
  if R[rec.sig] then e.bySig[rec.sig] = rec end   -- the newest answer per signal: at most four small records
end
Emitter.INSTANCES = {
  party = { "Ragefire Chasm", "Wailing Caverns", "The Deadmines", "Deadmines", "Shadowfang Keep", "Blackfathom Deeps",
    "The Stockade", "Stormwind Stockade", "Gnomeregan", "Razorfen Kraul", "Scarlet Monastery", "Razorfen Downs",
    "Uldaman", "Zul'Farrak", "Maraudon", "The Temple of Atal'Hakkar", "Sunken Temple", "Blackrock Depths",
    "Blackrock Spire", "Lower Blackrock Spire", "Upper Blackrock Spire", "Dire Maul", "Stratholme", "Scholomance" },
  raid = { "Molten Core", "Onyxia's Lair", "Blackwing Lair", "Zul'Gurub", "Ruins of Ahn'Qiraj", "Ahn'Qiraj Temple",
    "Temple of Ahn'Qiraj", "Naxxramas" },
}
-- One instance, one name: the client calls Sunken Temple both "Sunken Temple" and "The Temple of Atal'Hakkar" (seen
-- on WoW Forever, 2026-11-17: a run split in twelve on the flips), so names are compared and stored canonical.
Emitter.INSTANCE_ALIAS = {
  ["the temple of atal'hakkar"] = "Sunken Temple", ["temple of atal'hakkar"] = "Sunken Temple",
  ["deadmines"] = "The Deadmines", ["stormwind stockade"] = "The Stockade", ["ahn'qiraj temple"] = "Temple of Ahn'Qiraj",
  ["the temple of ahn'qiraj"] = "Temple of Ahn'Qiraj", ["ruins of ahn'qiraj"] = "Ruins of Ahn'Qiraj",
}
function Emitter.canonInstance(name)
  if type(name) ~= "string" then return name end
  local k = name:lower()
  local a = Emitter.INSTANCE_ALIAS[k]
  if a then return a end
  -- a second name the addon learned for a dungeon it was inside (0.9.50, Runs.alias: settings.instanceAlias)
  local L = ns.DB and ns.DB.settings and ns.DB.settings.instanceAlias
  local l = type(L) == "table" and L[k] or nil
  return type(l) == "string" and l or name
end
function Emitter.instanceNow()
  -- (plainNum is declared further down; the same guard inline)
  local function plainNum(v) if type(v) == "number" and not (issecretvalue and issecretvalue(v)) then return v end end
  local byName = Emitter._instByName
  if not byName then
    byName = {}
    for kind, list in pairs(Emitter.INSTANCES) do for _, n in ipairs(list) do byName[n:lower()] = kind end end
    Emitter._instByName = byName
  end
  local zone = safeStr(GetRealZoneText and GetRealZoneText()) or ""
  local ok, iname, itype, diff, _, _, _, _, imap = pcall(GetInstanceInfo)
  iname, itype = ok and safeStr(iname) or nil, ok and safeStr(itype) or nil
  local inInst, ptype
  if IsInInstance then local ok2, a, b = pcall(IsInInstance); if ok2 then inInst, ptype = a, safeStr(b) end end
  local mapID, mapType
  if C_Map and C_Map.GetBestMapForUnit and C_Map.GetMapInfo then
    local ok3, m = pcall(C_Map.GetBestMapForUnit, "player"); mapID = ok3 and plainNum(m) or nil
    if mapID then local ok4, info = pcall(C_Map.GetMapInfo, mapID); mapType = ok4 and type(info) == "table" and plainNum(info.mapType) or nil end
  end
  local name, kind, sig
  if itype == "party" or itype == "raid" then name, kind, sig = iname, itype, "type"
  elseif inInst and (ptype == "party" or ptype == "raid") then name, kind, sig = iname, ptype, "ptype"
  elseif mapType == 4 then kind = byName[zone:lower()] or "party"; name = zone; sig = "mapType"
  elseif byName[zone:lower()] then name, kind, sig = zone, byName[zone:lower()], "name" end
  if kind and (not name or name == "") then name = (zone ~= "" and zone) or iname or "Dungeon" end
  Emitter._sig = sig
  -- the whole answer of this check, for the dungeon run (0.9.50, Runs.lua: Runs.where reads it)
  Emitter._det = { name = name, kind = kind, sig = sig, zone = zone, map = plainNum(imap), diff = plainNum(diff), uiMap = mapID }
  if ns.DB and ns.DB.settings then
    ns.DB.settings.selftest = ns.DB.settings.selftest or {}
    ns.DB.settings.selftest.instance = { zone = zone, name = iname, type = itype, diff = plainNum(diff), map = plainNum(imap),
      inInstance = inInst and true or false, ptype = ptype, uiMap = mapID, mapType = mapType, verdict = kind or "none", sig = sig }
    if kind then
      pcall(Emitter.noteInstance, Emitter.canonInstance(name), { zone = zone, name = iname, type = itype, ptype = ptype,
        diff = plainNum(diff), map = plainNum(imap), inInstance = inInst and true or false, uiMap = mapID, mapType = mapType,
        sig = sig, at = (GetServerTime and GetServerTime()) or time() })
    end
  end
  return name, kind
end
-- A chat line as text the addon may match (0.9.49). The client can hand a chat line over as a secret value inside
-- an instance; matching, comparing or indexing one throws, so every chat handler asks here first and drops a line
-- it may not read. While the character is inside an instance the line is counted by kind and by the signal that
-- says "inside" in settings.selftest.chatSecret[kind][sig] = { plain, secret }: a later version reads there whether
-- XP, reputation, loot and system lines can be trusted inside. Inside is what the last dungeon check of this load
-- answered (Emitter._sig), never the flag saved on the character: a line that arrives before the first check of a
-- load is not counted, and neither is one at the door (sig "name": the open world in front of the portal, whose
-- zone carries the dungeon's name). Lines under sig "mapType" (the client's type reads "none") have their own
-- counters, apart from those where the client itself says instance. `kind` nil: guard only, nothing counted.
function Emitter.chatText(kind, v)
  local s = safeStr(v)
  local sig = Emitter._sig
  if kind and type(v) ~= "nil" and (sig == "type" or sig == "ptype" or sig == "mapType") and ns.DB and ns.DB.settings then
    local st = ns.DB.settings.selftest
    if type(st) ~= "table" then st = {}; ns.DB.settings.selftest = st end
    if type(st.chatSecret) ~= "table" then st.chatSecret = {} end
    local k = st.chatSecret[kind]
    if type(k) ~= "table" then k = {}; st.chatSecret[kind] = k end
    local c = k[sig]
    if type(c) ~= "table" then c = { plain = 0, secret = 0 }; k[sig] = c end
    if s then c.plain = (tonumber(c.plain) or 0) + 1 else c.secret = (tonumber(c.secret) or 0) + 1 end
  end
  return s
end
-- Is the target something the player can have killed? A unit the player can attack, or a corpse that is neither a
-- friend nor a player (a dead mob may read as not attackable). No answer from the client: no.
function Emitter.targetIsFoe()
  local there = UnitExists("target")
  if not there or type(UnitCanAttack) ~= "function" then return false end
  local ok, can = pcall(UnitCanAttack, "player", "target")
  if ok and can == true then return true end
  if type(UnitIsDead) ~= "function" or type(UnitIsFriend) ~= "function" or type(UnitIsPlayer) ~= "function" then return false end
  local ok1, dead = pcall(UnitIsDead, "target")
  local ok2, friend = pcall(UnitIsFriend, "player", "target")
  local ok3, isPlayer = pcall(UnitIsPlayer, "target")
  return ok1 and ok2 and ok3 and dead == true and friend == false and isPlayer == false
end
-- Announce a dungeon entry or exit when the answer changed (deduped on the character across /reload).
function Emitter.checkInstance()
  local iname, kind = Emitter.instanceNow()
  -- a second name of the dungeon the character is inside is learned before the names are compared (0.9.50)
  if ns.Runs and ns.Runs.alias then pcall(ns.Runs.alias) end
  iname = Emitter.canonInstance(iname)
  local announced = ns.DB and Emitter.canonInstance(ns.char().inInstance)   -- per character (#23): another character is not in this dungeon
  -- state FIRST, then the event/toast: if presentation ever throws, the dedupe state is still correct
  if kind and announced ~= iname then
    if announced then Emitter.event("DUNGEONLEAVE", { name = announced }) end
    if ns.DB then ns.char().inInstance = iname end
    Emitter.event("DUNGEON", { name = iname })
  elseif (not kind) and announced then
    if ns.DB then ns.char().inInstance = nil end
    Emitter.event("DUNGEONLEAVE", { name = announced })
  end
  -- the gold of a dungeon run follows the same answer (0.9.47, #43: characters[guid].goldRun and goldRuns)
  if ns.Gold and ns.Gold.runSync then pcall(ns.Gold.runSync) end
  -- and so does the stored dungeon run (0.9.50, #51: characters[guid].dungeonRun and dungeonRuns)
  if ns.Runs and ns.Runs.sync then pcall(ns.Runs.sync) end
  return kind ~= nil
end

local lastZone, wasDead = nil, false
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
Emitter.XP_PATS = XP_PATS   -- read by Runs.lua (the named forms count a kill of the run)
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
-- A quest reward can reach the bags before QUEST_TURNED_IN (Blackrock Spire, 20 Nov: Prismcharm at 15:29:42, the
-- turn-in after it), when the 5 s test below cannot know it yet. A reward reads "You receive item:"
-- (LOOT_ITEM_PUSHED_SELF); a drop reads "You receive loot:", also when a roll is won after the loot window closed. So
-- a pushed line that was given the last kill's name or none is remembered for a moment with the source it was
-- stored under, and the turn-in then names it (pushed.request). A line that named a world object keeps it.
pushed.PRE = {}
for _, g in ipairs({ "LOOT_ITEM_PUSHED_SELF", "LOOT_ITEM_PUSHED_SELF_MULTIPLE" }) do
  local s = _G[g]; local pre = s and s:match("^(.-)%%s")
  if pre and pre ~= "" then pushed.PRE[#pushed.PRE + 1] = pre end
end
if #pushed.PRE == 0 then pushed.PRE = { "You receive item:" } end
pushed.recent = {}   -- { at = GetTime(), item = name, src = stored source }: the pushed lines of the last seconds
pushed.REQUEST_S = 3
-- Returns the source, nil (no loot GUID), and how it was named: "object" (the world object opened in the last 15 s),
-- "kill" (the last kill of the last 15 s, a guess by timing: the pane shows no name for it), nil otherwise.
local function pushedSource(msg, item)
  local now = GetTime()
  local line = false
  if type(msg) == "string" then
    for _, pre in ipairs(pushed.PRE) do if msg:sub(1, #pre) == pre then line = true end end
  end
  if pushed.obj and (now - pushed.obj.at) < 15 then return pushed.obj.name or "Object", nil, "object" end
  if (now - pushed.turnIn) < 5 then return "Quest reward", nil end
  -- (a kill whose name the client hid is "Creature", the word a loot window stores for it: the on-screen
  -- placeholder "an enemy" is never stored as a source)
  local src = (lastKillName and (now - lastKillAt) < 15) and (lastKillName ~= "an enemy" and lastKillName or "Creature") or "Picked up"
  if line and item then
    local keep = {}
    for _, r in ipairs(pushed.recent) do if now - r.at <= pushed.REQUEST_S then keep[#keep + 1] = r end end
    keep[#keep + 1] = { at = now, item = item, src = src }
    pushed.recent = keep
  end
  return src, nil, (src ~= "Picked up") and "kill" or nil
end
-- QUEST_TURNED_IN: the pushed items of the last pushed.REQUEST_S seconds that named no world object are this
-- turn-in's reward. Only rows written a moment ago by this session are touched, never older data. Returns how many
-- rows of the loot log changed.
function pushed.request()
  local now, n = GetTime(), 0
  local log = ns.DB and ns.DB.loot and ns.DB.loot.log
  for _, r in ipairs(pushed.recent) do
    if now - r.at <= pushed.REQUEST_S then
      for _, list in ipairs({ sessionLoot, type(log) == "table" and log or {} }) do
        for i = #list, math.max(1, #list - 20), -1 do
          local e = list[i]
          if type(e) == "table" and not e.money and e.item == r.item and e.src == r.src and (list == sessionLoot or e.s == ns.DB.active) then
            e.src, e.guid, e.srcBy = "Quest reward", nil, nil
            if list ~= sessionLoot then n = n + 1 end
            break
          end
        end
      end
    end
  end
  pushed.recent = {}
  return n
end
-- gold SINK context: which window was open when the purse went down decides what the gold went to
local merchantOpen, trainerOpen, taxiUntil, repairUntil = false, false, 0, 0
-- Repairs (0.9.46, #43 rule 24): Emitter._repair.cost is the last GetRepairAllCost() seen while the purse was
-- unchanged (Emitter.repairSample). RepairAllItems(true) is paid by the guild bank: it arms nothing, and the cost it
-- clears is forgotten so its drop is never read as a repair the purse paid.
Emitter._repair = {}
if hooksecurefunc and RepairAllItems then
  hooksecurefunc("RepairAllItems", function(guild)
    local r = Emitter._repair
    if guild then r.cost, r.prev, r.guildAt = nil, nil, GetTime(); return end
    repairUntil = GetTime() + 2
  end)
end
local function goldDB() local c = ns.char(); c.gold = c.gold or { looted = 0, gained = 0, spent = 0 }; return c.gold end   -- the character's own ledger (#23)

-- ── mailbox: auction proceeds, items and coin taken from the inbox ─────────────
-- Classic prints NO chat line when you take an item or coin out of a mail, so the inbox API hooks are the
-- record. SOURCE is the mail's origin (Auction sale / Auction won / Auction returned / Mail from <name>);
-- LOCATION is the mailbox. Auction proceeds and COD payments also feed the Economy breakdown.
local mailOpen, auctionOpen = false, false
-- Which window the purse change belongs to (0.9.46, #43): the window events as before, and where the client has it,
-- C_PlayerInteractionManager at the moment of the change. The API only ever adds context: a window the events say
-- is open stays open, so a client that answers nothing behaves as before.
Emitter.NPC_TYPE = { merchant = "Merchant", trainer = "Trainer", mail = "MailInfo", auction = "Auctioneer" }
function Emitter.interacting(kind)
  local types = Enum and Enum.PlayerInteractionType
  if not (C_PlayerInteractionManager and type(C_PlayerInteractionManager.IsInteractingWithNpcOfType) == "function" and type(types) == "table") then return nil end
  local t = types[Emitter.NPC_TYPE[kind]]
  if t == nil then return nil end
  local v = rd(C_PlayerInteractionManager.IsInteractingWithNpcOfType, t)
  if v == nil or (issecretvalue and issecretvalue(v)) then return nil end
  return v == true
end
function Emitter.at(kind)
  local open
  if kind == "merchant" then open = merchantOpen elseif kind == "trainer" then open = trainerOpen
  elseif kind == "mail" then open = mailOpen elseif kind == "auction" then open = auctionOpen end
  return (open or Emitter.interacting(kind) == true) and true or false
end
-- Coin taken out of mails, waiting for the purse change (0.9.46, #43 rule 15): one entry per take, { src, meta,
-- money, at }, with the money the mail's header names. "Open All" takes several mails before the purse answers, so
-- the single slot of 0.9.40 named the wrong sender; the queue is matched by amount (Emitter.mailTake).
Emitter._mailQ = {}
Emitter.MAIL_TTL = 3   -- seconds an entry waits for its purse change (each answer of the server restarts the wait of the rest)
local mailTaken = {}          -- item name -> GetTime() of the hook, to skip a duplicate chat line (retail)
local function subjPrefix(global, fallback)
  local fmt = _G[global] or fallback
  return (fmt:gsub("%%s.*$", ""))
end
local function mailOrigin(index)
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
-- The mail's origin plus `rel`, who the sender is to the player (#36): "system" for the auction house and any mail
-- that cannot be answered (the client's own and NPC mail), else Emitter.relOf (alt, guild, friend, stranger).
local function mailSource(index)
  local src, m = mailOrigin(index)
  if not m then return src, m end
  local ok, _, _, _, _, _, _, _, _, _, _, _, canReply, isGM = pcall(GetInboxHeaderInfo, index)
  local system = src:sub(1, 8) == "Auction " or not m.sender or (ok and (canReply == false or isGM == true))
  m.rel = system and "system" or Emitter.relOf(m.sender)
  return src, m
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
  Emitter._mailCtx = { meta = meta, at = GetTime() }   -- a COD payment for this item is booked against this mail (#36)
  Emitter.event("LOOT", { name = name, count = plainNum(count) or 1 }, lootQuiet(q))
end
local function armMailMoney(index)
  local ok, _, _, _, _, money = pcall(GetInboxHeaderInfo, index)
  money = ok and plainNum(money) or 0
  if money > 0 then
    local src, meta = mailSource(index)
    local q = Emitter._mailQ
    q[#q + 1] = { src = src, meta = meta, money = money, at = GetTime() }
    while #q > 60 do table.remove(q, 1) end
  end
end
-- whether a mail's coin is still waiting for its purse change (entries past MAIL_TTL are forgotten)
function Emitter.mailArmed()
  local q, now = Emitter._mailQ, GetTime()
  for i = #q, 1, -1 do if now - q[i].at > Emitter.MAIL_TTL then table.remove(q, i) end end
  return #q > 0
end
-- The mails a gain of `amount` is: the one whose money it equals, else the k oldest whose money sums to it (several
-- mails answered with one purse change), else nil. The entries returned leave the queue. With `peek` nothing is
-- taken: true when the amount is a waiting mail's (or the sum of the oldest), else nil.
function Emitter.mailTake(amount, peek)
  local q, out = Emitter._mailQ, nil
  for i, e in ipairs(q) do
    if e.money == amount then
      if peek then return true end
      out = { table.remove(q, i) }; break
    end
  end
  if not out then
    local sum = 0
    for k, e in ipairs(q) do
      sum = sum + e.money
      if sum == amount then
        if peek then return true end
        out = {}
        for _ = 1, k do out[#out + 1] = table.remove(q, 1) end
        break
      end
      if sum > amount then break end
    end
  end
  if out then for _, e in ipairs(q) do e.at = GetTime() end end   -- the server is answering: the rest are still to come
  return out
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

-- One credit to the gold ledger: the character's lifetime total (characters[guid].gold, #23) and, from 0.9.23, the running session's own ledger
-- (session.gold, everbuff-backend #46, approved 2026-09-29), same keys, at the same moment. A session that began
-- before 0.9.23 has no ledger and keeps none, so a half-filled one is never mistaken for the whole session.
-- A credit to a source key also writes the purse change into the session's gold journal (Emitter.goldRow, #36), with
-- the balance and the ref the caller put in Emitter._gbal and Emitter._gref just before.
-- From 0.9.44 every credit also lands on the character's row of the server day (Emitter.goldDay, #43).
local function credit(g, ses, key, n)
  g[key] = (g[key] or 0) + n
  local sg = ses.gold
  if type(sg) == "table" then sg[key] = (sg[key] or 0) + n end
  Emitter.goldDay(key, n)
  if Emitter.GOLD_SIGN[key] then Emitter.goldRow(ses, key, n) end
end
-- The day row of a credit (everbuff-wow-addon #43, 0.9.44): characters[guid].goldDays, kept by ns.Gold (Economy.lua).
-- The balance is the one the caller put in Emitter._gbal; Emitter._dayAt names the moment of an earlier change (a
-- quest claiming an income first seen with no source), so the move lands on the day the income was booked on. A
-- failure here never stops the ledger: it is kept in Emitter._dayErr for the tests and the debug window.
function Emitter.goldDay(key, n)
  local G = ns.Gold
  if not (G and G.dayCredit) then return end
  local ok, err = pcall(G.dayCredit, key, n, Emitter._gbal, Emitter._dayAt)
  if not ok then Emitter._dayErr = err end
end

-- ── the gold journal (everbuff-wow-addon #36, option A, approved 2026-11-17) ─────────────────────────────────────
-- Per session `goldLog[]`: one row per purse change, `mono TAB delta TAB source TAB balance TAB ref`, written into
-- the running session record at the moment of the credit. `trades[]`: every completed trade, both sides. Nothing is
-- drawn and nothing is said in chat. A session that began before 0.9.40 has neither (Segments starts them empty), so a
-- half-filled journal is never mistaken for the whole session.
-- source -> sign of the delta (away is booked signed)
Emitter.GOLD_SIGN = { looted = 1, quests = 1, sold = 1, auctionSales = 1, mail = 1, trade = 1, unexplained = 1,
  repairs = -1, vendor = -1, training = -1, flights = -1, auctions = -1, mailSpent = -1, tradeSpent = -1, other = -1, away = 1 }
Emitter.GOLD_CAP = 4000
-- past the cap: rows of these sources merge with the row before them when it has the same source
local COALESCE = { looted = true, sold = true, vendor = true }
-- never dropped, never merged: the rows that carry a counterparty or an explanation gap
local KEEP = { trade = true, tradeSpent = true, mail = true, mailSpent = true, auctionSales = true, away = true, unexplained = true }
local REF_KEYS = { "item", "n", "unit", "npc", "sender", "partner", "guild", "rel", "cod", "trade", "quest", "mailWaiting", "x", "gap",
  "kind", "share", "bank", "crash", "to", "drift" }   -- (0.9.46, #43; `bank` and `to` are written from 0.9.47)
local function refStr(ref)
  if type(ref) ~= "table" then return "" end
  local out = {}
  for _, k in ipairs(REF_KEYS) do
    local v = ref[k]
    if type(v) == "number" then v = plainNum(v) and ("%d"):format(v) or nil
    elseif type(v) == "string" then v = safeStr(v); v = v and v:gsub("[\t;=|\r\n]", "") or nil end
    if v and v ~= "" then out[#out + 1] = k .. "=" .. v end
  end
  return table.concat(out, ";")
end
local function refParse(s)
  local t = {}
  for k, v in (s or ""):gmatch("([^;=]+)=([^;]*)") do t[k] = v end
  return t
end
Emitter.refStr, Emitter.refParse = refStr, refParse
local function rowParse(r)
  local mono, d, src, bal, ref = r:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t(.*)$")
  return mono, tonumber(d), src, tonumber(bal), ref
end
Emitter.rowParse = rowParse

-- Write one row. `n` is the credited amount (positive; signed for away). A row that a quest claims later (an income
-- first seen with no source) is rewritten in place: Emitter._grewrite names it.
function Emitter.goldRow(ses, key, n)
  local log = ses and ses.goldLog
  local ref, bal = Emitter._gref, Emitter._gbal
  Emitter._gref = nil
  if type(log) ~= "table" then return nil end
  local rw = Emitter._grewrite
  Emitter._grewrite = nil
  if rw and rw.ses == ses and log[rw.i] == rw.row then
    local mono, d, _, b = rowParse(rw.row)
    log[rw.i] = ("%s\t%d\t%s\t%d\t%s"):format(mono, d, key, b, refStr(ref))
    return rw.i
  end
  local delta = Emitter.GOLD_SIGN[key] * n
  bal = plainNum(bal) or plainNum(rd(GetMoney)) or 0
  local mono = ("%.1f"):format(GetTime())
  local rs = refStr(ref)
  if #log >= Emitter.GOLD_CAP and not KEEP[key] then
    local free = not (type(ref) == "table" and (ref.partner or ref.sender))
    local last = log[#log]
    local _, ld, lsrc, _, lref = rowParse(last or "")
    if COALESCE[key] and free and lsrc == key then
      local a, b = refParse(lref), refParse(rs)
      local merged = { x = (tonumber(a.x) or 1) + 1 }
      for _, k in ipairs({ "item", "unit", "npc" }) do if a[k] and a[k] == b[k] then merged[k] = a[k] end end
      if merged.item and a.n and b.n then merged.n = (tonumber(a.n) or 0) + (tonumber(b.n) or 0) end
      for k, v in pairs(merged) do if type(v) == "string" then merged[k] = tonumber(v) or v end end
      log[#log] = ("%s\t%d\t%s\t%d\t%s"):format(mono, ld + delta, key, bal, refStr(merged))
      return #log
    end
    ses.goldLogDropped = (tonumber(ses.goldLogDropped) or 0) + 1
    return nil
  end
  log[#log + 1] = ("%s\t%d\t%s\t%d\t%s"):format(mono, delta, key, bal, rs)
  return #log
end

-- Who a player is to this character (#36): "alt" (a character of this account on the same realm, from the save file's
-- characters blocks), "guild" (the guild roster, cached on GUILD_ROSTER_UPDATE), "friend" (the friends list), else
-- "stranger". Read only for a mail or a trade, never per copper.
local function realmKey(r) return ((r or ""):gsub("[%s%-']", "")):lower() end
local function nameKey(name)
  local base, realm = name:match("^([^%-]+)%-(.+)$")
  if not base then base, realm = name, safeStr(GetRealmName and GetRealmName()) end
  return base:lower() .. "-" .. realmKey(realm)
end
Emitter.nameKey = nameKey
function Emitter.loadAlts()
  local set = {}
  for _, c in pairs((ns.DB and ns.DB.characters) or {}) do
    if type(c) == "table" and type(c.name) == "string" and type(c.realm) == "string" then set[c.name:lower() .. "-" .. realmKey(c.realm)] = true end
  end
  Emitter._alts = set
  return set
end
function Emitter.loadGuild()
  local set = {}
  local n = (GetNumGuildMembers and plainNum(rd(GetNumGuildMembers))) or 0
  for i = 1, n do
    local nm = GetGuildRosterInfo and safeStr(rd(GetGuildRosterInfo, i))
    if nm and nm ~= "" then set[nameKey(nm)] = true end
  end
  Emitter._guild = set
  return set
end
function Emitter.loadFriends()
  local set = {}
  if C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetFriendInfoByIndex then
    local n = plainNum(rd(C_FriendList.GetNumFriends)) or 0
    for i = 1, n do
      local info = rd(C_FriendList.GetFriendInfoByIndex, i)
      local nm = type(info) == "table" and safeStr(info.name)
      if nm and nm ~= "" then set[nameKey(nm)] = true end
    end
  end
  Emitter._friends = set
  return set
end
function Emitter.relOf(name, guid)
  name = safeStr(name)
  if not name or name == "" then return nil end
  local key = nameKey(name)
  if (Emitter._alts or Emitter.loadAlts())[key] then return "alt" end
  if (Emitter._guild or {})[key] then return "guild" end
  if (Emitter._friends or {})[key] then return "friend" end
  guid = safeStr(guid)
  if guid and C_FriendList and C_FriendList.IsFriend and rd(C_FriendList.IsFriend, guid) == true then return "friend" end
  if C_FriendList and C_FriendList.GetFriendInfo and type(rd(C_FriendList.GetFriendInfo, name)) == "table" then return "friend" end
  return "stranger"
end

-- Items bought and sold at a merchant, waiting for the purse change the server answers with (#36). Each entry
-- { id, n, amount?, at }; the purse change takes the entry whose amount it matches, else the oldest of the last 5 s.
Emitter._pend = { sell = {}, buy = {}, back = {} }
local function itemId(link) link = safeStr(link); return link and tonumber(link:match("|Hitem:(%d+)")) or nil end
-- the n-th value a client function returns, or nil when it is missing or throws
local function nth(fn, n, ...)
  if type(fn) ~= "function" then return nil end
  local r = { pcall(fn, ...) }
  if r[1] then return r[n + 1] end
end
Emitter.nth = nth
local function sellPrice(id)
  if not id then return nil end
  local v = nth(GetItemInfo, 11, id)
  if v == nil and C_Item then v = nth(C_Item.GetItemInfo, 11, id) end
  return plainNum(v)
end
local function bagItem(bag, slot)
  bag, slot = plainNum(bag), plainNum(slot)
  if not (bag and slot) then return nil end
  if C_Container and C_Container.GetContainerItemInfo then
    local info = rd(C_Container.GetContainerItemInfo, bag, slot)
    if type(info) == "table" then return plainNum(info.itemID), plainNum(info.stackCount) or 1 end
  elseif GetContainerItemInfo then
    local ok, _, count, _, _, _, _, link, _, _, id = pcall(GetContainerItemInfo, bag, slot)
    if ok then return plainNum(id) or itemId(link), plainNum(count) or 1 end
  end
end
local function pend(list, id, n, unit, amount)
  if amount == nil and unit and n then amount = unit * n end
  list[#list + 1] = { id = id, n = n, unit = unit, amount = amount, at = GetTime() }
  while #list > 60 do table.remove(list, 1) end
end
function Emitter.prunePending(list)
  local now = GetTime()
  for i = #list, 1, -1 do if now - list[i].at > 5 then table.remove(list, i) end end
end
-- the server is answering: the entries still waiting are still to come (their 5 s start again, like the mail queue)
function Emitter.restartPending(list)
  local now = GetTime()
  for _, e in ipairs(list) do e.at = now end
end
-- The pending entries a purse change of `amount` pays for (0.9.46, #43 rule 14): the one entry whose amount it
-- equals, else a set of entries (searched over the 8 oldest with a known amount) whose amounts sum to it exactly:
-- several sales or purchases the server answered with one purse change. nil when nothing matches exactly. The
-- entries returned leave the list, in the order they were asked for, and the wait of the rest starts again.
function Emitter.matchPending(list, amount)
  Emitter.prunePending(list)
  for i, e in ipairs(list) do
    if e.amount == amount then
      local out = { table.remove(list, i) }
      Emitter.restartPending(list)
      return out
    end
  end
  local idx = {}
  for i, e in ipairs(list) do
    if e.amount and e.amount > 0 and e.amount < amount then idx[#idx + 1] = i; if #idx == 8 then break end end
  end
  local n = #idx
  if n < 2 then return nil end
  for mask = 1, 2 ^ n - 1 do
    local sum, m = 0, mask
    for b = 1, n do
      if m % 2 == 1 then sum = sum + list[idx[b]].amount end
      m = math.floor(m / 2)
    end
    if sum == amount then
      local out, take = {}, {}
      m = mask
      for b = 1, n do
        if m % 2 == 1 then take[#take + 1] = idx[b] end
        m = math.floor(m / 2)
      end
      for t = #take, 1, -1 do table.insert(out, 1, table.remove(list, take[t])) end
      Emitter.restartPending(list)
      return out
    end
  end
  return nil
end
-- whether a sale was asked for in the last 5 s (a gain then is the sale's, also inside a loot window)
function Emitter.pendingSale()
  Emitter.prunePending(Emitter._pend.sell)
  return #Emitter._pend.sell > 0
end
function Emitter.noteSale(bag, slot)
  if not (Emitter._merchantOpen or Emitter.at("merchant")) then return end
  local id, n = bagItem(bag, slot)
  if id then pend(Emitter._pend.sell, id, n, sellPrice(id)) end
end
function Emitter.noteJunkSale()
  if not ((Emitter._merchantOpen or Emitter.at("merchant")) and C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo) then return end
  for bag = 0, (NUM_BAG_SLOTS or 4) do
    for slot = 1, (plainNum(rd(C_Container.GetContainerNumSlots, bag)) or 0) do
      local info = rd(C_Container.GetContainerItemInfo, bag, slot)
      if type(info) == "table" and info.quality == 0 and not info.hasNoValue then
        local id = plainNum(info.itemID)
        if id then pend(Emitter._pend.sell, id, plainNum(info.stackCount) or 1, sellPrice(id)) end
      end
    end
  end
end
-- A merchant item's price and the count one purchase gives (0.9.46, #43 rule 28): C_MerchantFrame.GetItemInfo where
-- the client has it, else the legacy global.
function Emitter.merchantItem(index)
  if C_MerchantFrame and type(C_MerchantFrame.GetItemInfo) == "function" then
    local info = rd(C_MerchantFrame.GetItemInfo, index)
    if type(info) == "table" then return plainNum(info.price), plainNum(info.stackCount) end
  end
  return plainNum(nth(GetMerchantItemInfo, 3, index)), plainNum(nth(GetMerchantItemInfo, 4, index))
end
-- The price is for one purchase of `per` items; BuyMerchantItem's quantity counts items. A price that does not come
-- out whole, or an item paid in another currency, leaves the amount unknown (the entry then matches by age).
function Emitter.noteBuy(index, qty)
  local id = GetMerchantItemLink and itemId(rd(GetMerchantItemLink, index))
  if not id then return end
  local price, per = Emitter.merchantItem(index)
  qty = plainNum(qty)
  local amount
  if price and price > 0 then
    if qty and per and per > 0 then amount = price * qty / per else amount = price * (qty or 1) end
    if amount ~= math.floor(amount) then amount = nil end
  end
  pend(Emitter._pend.buy, id, qty or per or 1, nil, amount)
end
-- An item bought back (rule 27): with its price known the purse change is a sale taken back (Emitter._pend.back),
-- else a purchase like any other, as before.
function Emitter.noteBuyback(index)
  local id = GetBuybackItemLink and itemId(rd(GetBuybackItemLink, index))
  if not id and C_MerchantFrame and type(C_MerchantFrame.GetBuybackItemID) == "function" then id = plainNum(rd(C_MerchantFrame.GetBuybackItemID, index)) end
  if not id then return end
  local price, n = plainNum(nth(GetBuybackItemInfo, 3, index)), plainNum(nth(GetBuybackItemInfo, 4, index))
  if price and price > 0 then pend(Emitter._pend.back, id, n or 1, nil, price)
  else pend(Emitter._pend.buy, id, n or 1, nil) end
end
if hooksecurefunc then
  if C_Container and type(C_Container.UseContainerItem) == "function" then hooksecurefunc(C_Container, "UseContainerItem", function(b, s) pcall(Emitter.noteSale, b, s) end) end
  if type(UseContainerItem) == "function" then hooksecurefunc("UseContainerItem", function(b, s) pcall(Emitter.noteSale, b, s) end) end
  if C_MerchantFrame and type(C_MerchantFrame.SellAllJunkItems) == "function" then hooksecurefunc(C_MerchantFrame, "SellAllJunkItems", function() pcall(Emitter.noteJunkSale) end) end
  if type(BuyMerchantItem) == "function" then hooksecurefunc("BuyMerchantItem", function(i, q) pcall(Emitter.noteBuy, i, q) end) end
  if type(BuybackItem) == "function" then hooksecurefunc("BuybackItem", function(i) pcall(Emitter.noteBuyback, i) end) end
end

-- Auction house spending (0.9.46, #43 rule 29): what the purse is about to pay, taken from the arguments of the
-- client functions the auction window calls, as claims of an exact amount. A spend at the auction house that
-- equals a claim carries its `kind` (deposit, bid, buyout, cancel); one that equals none stays a plain `auctions`
-- row. A deposit the client does not answer leaves no claim. Claims lapse after 30 s, and 2 s after the client
-- says the auction action is over (Emitter.AH_DONE: the purse change may come just after that event, never long
-- after it). PlaceBid is also how an item is bought out, so its claim reads "Bid or buyout" in the Gold pane.
Emitter._ah = { claims = {} }
-- event -> the kind of claim it ends (false: every kind)
Emitter.AH_DONE = { AUCTION_HOUSE_AUCTION_CREATED = "deposit", AUCTION_HOUSE_PURCHASE_COMPLETED = "bid", COMMODITY_PURCHASE_SUCCEEDED = "buyout",
  COMMODITY_PURCHASE_FAILED = "buyout", AUCTION_CANCELED = "cancel", AUCTION_HOUSE_SHOW_ERROR = false }
function Emitter.ahExpire(kind)
  local late = GetTime() - 28
  for _, e in ipairs(Emitter._ah.claims) do
    if (not kind or e.kind == kind) and e.at > late then e.at = late end
  end
end
function Emitter.ahClaim(kind, amount)
  amount = plainNum(amount)
  if not amount or amount <= 0 then return end
  local q = Emitter._ah.claims
  q[#q + 1] = { kind = kind, amount = math.floor(amount), at = GetTime() }
  while #q > 40 do table.remove(q, 1) end
end
function Emitter.ahTake(amount)
  local q, now = Emitter._ah.claims, GetTime()
  for i = #q, 1, -1 do if now - q[i].at > 30 then table.remove(q, i) end end
  for i, e in ipairs(q) do if e.amount == amount then table.remove(q, i); return e.kind end end
  return nil
end
if hooksecurefunc and C_AuctionHouse then
  if type(C_AuctionHouse.PostItem) == "function" then
    hooksecurefunc(C_AuctionHouse, "PostItem", function(item, duration, quantity)
      if type(C_AuctionHouse.CalculateItemDeposit) == "function" then Emitter.ahClaim("deposit", rd(C_AuctionHouse.CalculateItemDeposit, item, duration, quantity)) end
    end)
  end
  if type(C_AuctionHouse.PostCommodity) == "function" then
    hooksecurefunc(C_AuctionHouse, "PostCommodity", function(item, duration, quantity)
      local id = C_Item and type(C_Item.GetItemID) == "function" and plainNum(rd(C_Item.GetItemID, item)) or nil
      if id and type(C_AuctionHouse.CalculateCommodityDeposit) == "function" then Emitter.ahClaim("deposit", rd(C_AuctionHouse.CalculateCommodityDeposit, id, duration, quantity)) end
    end)
  end
  if type(C_AuctionHouse.PlaceBid) == "function" then
    hooksecurefunc(C_AuctionHouse, "PlaceBid", function(_, amount) Emitter.ahClaim("bid", amount) end)
  end
  if type(C_AuctionHouse.CancelAuction) == "function" then
    hooksecurefunc(C_AuctionHouse, "CancelAuction", function(auctionID)
      if type(C_AuctionHouse.GetCancelCost) == "function" then Emitter.ahClaim("cancel", rd(C_AuctionHouse.GetCancelCost, auctionID)) end
    end)
  end
  -- a commodity purchase: the total the client quotes (COMMODITY_PRICE_UPDATED) is claimed when it is confirmed
  if type(C_AuctionHouse.StartCommoditiesPurchase) == "function" then
    hooksecurefunc(C_AuctionHouse, "StartCommoditiesPurchase", function() Emitter._ah.quote = nil end)
  end
  if type(C_AuctionHouse.ConfirmCommoditiesPurchase) == "function" then
    hooksecurefunc(C_AuctionHouse, "ConfirmCommoditiesPurchase", function() Emitter.ahClaim("buyout", Emitter._ah.quote); Emitter._ah.quote = nil end)
  end
end

-- Gold that changed while the addon did not see it (everbuff-wow-addon #31): another PC, the addon off, a
-- character transfer. The first read of a load compares the purse with the balance the save file last kept for
-- this character; a difference goes to `away` (signed) and `awayIn` or `awayOut`, never to gained or spent, so
-- balance = gained - spent + away holds across loads. Booked one tick later: Core starts the new session after
-- this file's PLAYER_ENTERING_WORLD handler has run. A quiet GOLDAWAY story row says how much; nothing shows in game.
-- The row is written into the day it is discovered on, with ref `gap`: the seconds since the character was last seen
-- (0.9.44, #43). `undo` takes back a 0 the client answered at login and then corrected: the same amount the other
-- way, taken out of awayIn or awayOut again, so away, awayIn and awayOut end where they were. `sync` books at once: a
-- change that follows in the same call (a gain on a purse that really was 0) must find the away row before it.
-- Both credits of the booking land on one day row: the clock is read once (Emitter._dayAt).
-- The game ended without saving (0.9.46, #43 rule 9). The save file is written only after PLAYER_LOGOUT, which a
-- /reload fires as well as a logout, and there the session is closed in it (`endedBy = "logout"`) either way, so a
-- session record cannot say that the client died later. What can: `characters[guid].goldOpen`, the server epoch of
-- a save made by a /reload (the hooks on ReloadUI and C_UI.Reload say a reload is coming). A real logout or exit
-- removes it. A login that finds it in the save file follows a play stretch that never saved: its away row carries
-- `crash=1` and the Gold pane names it "Unattributed (game closed without saving)". A crash in a session with no
-- /reload before it leaves nothing in the save file, so it stays a plain away row; so does every crash on a client
-- whose reload does not run the hooks before it saves (today's behavior).
function Emitter.openMark()
  if not (ns.DB and ns.charGuid and ns.charGuid()) then return end
  local c = ns.char()
  if Emitter._reloading then c.goldOpen = (GetServerTime and GetServerTime()) or time() else c.goldOpen = nil end
end
function Emitter.reloadAsked() Emitter._reloading = true; Emitter.openMark() end
if hooksecurefunc then
  if type(ReloadUI) == "function" then hooksecurefunc("ReloadUI", function() pcall(Emitter.reloadAsked) end) end
  if C_UI and type(C_UI.Reload) == "function" then hooksecurefunc(C_UI, "Reload", function() pcall(Emitter.reloadAsked) end) end
end
-- PLAYER_ENTERING_WORLD: a login reads the mark once the character is known (Emitter.crashRead, at the first read
-- of the purse); a reload keeps it, the session goes on
function Emitter.loadKind(isLogin)
  Emitter._reloading = nil
  if isLogin == true then Emitter._crashAsk = true end
end
function Emitter.crashRead()
  if not Emitter._crashAsk then return end
  Emitter._crashAsk = nil
  local c = ns.char()
  Emitter._crashed = (c.goldOpen ~= nil) or nil
  c.goldOpen = nil
end
function Emitter.goldAway(d, bal, mailWaiting, undo, sync)
  local seen = ns.Gold and ns.Gold.seenBefore and ns.Gold.seenBefore() or nil
  local nowS = (GetServerTime and GetServerTime()) or time()
  local gap = (not undo and seen and nowS > seen) and math.floor(nowS - seen) or nil
  local waits = not sync and C_Timer and C_Timer.After and true or nil
  -- (the balance is already the new one: until the row is booked, one frame later, the audit does not judge)
  if waits then Emitter._awayWait = (Emitter._awayWait or 0) + 1 end
  local function book()
    if waits then Emitter._awayWait = (Emitter._awayWait or 1) > 1 and Emitter._awayWait - 1 or nil end
    if not ns.DB then return end
    local g, ses = goldDB(), sessionDB()
    -- (the row that takes a 0 read back carries the same tag as its booking, so the two cancel in every sum)
    local crash = Emitter._crashed and 1 or nil
    Emitter._gbal = bal
    Emitter._gref = (mailWaiting or gap or crash) and { mailWaiting = mailWaiting and 1 or nil, gap = gap, crash = crash } or nil
    Emitter._dayAt = (GetServerTime and GetServerTime()) or time()
    credit(g, ses, "away", d)
    if undo then credit(g, ses, d > 0 and "awayOut" or "awayIn", -math.abs(d))
    else credit(g, ses, d > 0 and "awayIn" or "awayOut", math.abs(d)) end
    Emitter._dayAt, Emitter._gref = nil, nil
    Emitter.event("GOLDAWAY", { money = d }, true)
    if ns.Gold and ns.Gold.fire then ns.Gold.fire() end
  end
  if waits then C_Timer.After(0, book) else book() end
end

-- Coin and items traded with another player (#31, #36). The window is open, or closed under 3 s ago (the purse can
-- move just after TRADE_CLOSED). The partner, their guild and who they are to the player are read at TRADE_SHOW from
-- the client's "NPC" unit. The client clears the window on close, so both sides are snapshotted on every change and
-- the last snapshot is kept; a trade is written to the session's `trades[]` only once it completed (gold moved in the
-- window, or the client said "Trade complete."). A cancelled trade writes nothing.
Emitter._trade = { open = false, untilT = 0, name = nil }
function Emitter.tradeShow()
  local npcName = UnitName and safeStr(UnitName("NPC")) or nil
  local guild = GetGuildInfo and safeStr(rd(GetGuildInfo, "NPC")) or nil
  local guid = UnitGUID and safeStr(UnitGUID("NPC")) or nil
  Emitter._trade = { open = true, untilT = 0, name = npcName, guild = guild ~= "" and guild or nil,
    rel = Emitter.relOf(npcName, guid) }
end
function Emitter.tradeClosed() local t = Emitter._trade; t.open, t.untilT = false, GetTime() + 3 end
-- the client said the trade was cancelled: coin moving in the next 3 s is not the trade's
function Emitter.tradeCancelled() local t = Emitter._trade; t.open, t.untilT, t.snap = false, 0, nil end
local function inTrade() local t = Emitter._trade; return t.open or GetTime() < t.untilT end
local function tradeRow(money) Emitter.event("TRADE", { name = Emitter._trade.name or "a player", money = money }, true) end
-- one side of the window as "id:count" per filled slot (id 0 when the client gives a name but no link)
local function tradeSide(player)
  local out = {}
  for i = 1, (MAX_TRADABLE_ITEMS or 6) do
    local link, name, count
    if player then link, name, count = nth(GetTradePlayerItemLink, 1, i), nth(GetTradePlayerItemInfo, 1, i), nth(GetTradePlayerItemInfo, 3, i)
    else link, name, count = nth(GetTradeTargetItemLink, 1, i), nth(GetTradeTargetItemInfo, 1, i), nth(GetTradeTargetItemInfo, 3, i) end
    local id = itemId(link)
    name = safeStr(name)
    if id or (name and name ~= "") then out[#out + 1] = ("%d:%d"):format(id or 0, plainNum(count) or 1) end
  end
  return out
end
-- One snapshot of both sides while the window is open. An empty read never replaces a full one: the client clears
-- the window as the trade completes, and a trade with nothing on either side moves nothing worth keeping.
function Emitter.tradeSnap()
  local t = Emitter._trade
  if not t.open then return end
  local s = { gaveMoney = plainNum(rd(GetPlayerTradeMoney)) or 0, gotMoney = plainNum(rd(GetTargetTradeMoney)) or 0,
    gave = tradeSide(true), got = tradeSide(false) }
  if s.gaveMoney == 0 and s.gotMoney == 0 and #s.gave == 0 and #s.got == 0 and t.snap then return end
  t.snap = s
end
-- The trade completed: write it once into the session's trades[] and return its 1-based index. `delta` is the purse
-- change that proved it; it fills the money only when no snapshot was taken.
function Emitter.tradeDone(delta)
  local t = Emitter._trade
  local ses = sessionDB()
  if t.idx and t.ses == ses then
    local e = ses.trades and ses.trades[t.idx]
    if e and t.derived and delta then
      if delta > 0 then e.gotMoney = e.gotMoney + delta else e.gaveMoney = e.gaveMoney - delta end
    end
    return t.idx
  end
  if type(ses.trades) ~= "table" or not (t.name or t.snap) then return nil end
  local s = t.snap
  local e = { t = (GetServerTime and GetServerTime()) or time(), mono = math.floor(GetTime() * 10 + 0.5) / 10,
    partner = t.name, guild = t.guild, rel = t.rel,
    gaveMoney = s and s.gaveMoney or 0, gotMoney = s and s.gotMoney or 0, gave = s and s.gave or {}, got = s and s.got or {} }
  t.derived = (s == nil) or nil
  if t.derived and delta then
    if delta > 0 then e.gotMoney = delta else e.gaveMoney = -delta end
  end
  ses.trades[#ses.trades + 1] = e
  t.idx, t.ses = #ses.trades, ses
  return t.idx
end
function Emitter.tradeRef(delta)
  local t = Emitter._trade
  return { partner = t.name, guild = t.guild, rel = t.rel, trade = Emitter.tradeDone(delta) }
end
-- the ref of a mail row: the mail the coin came from (#36)
local function mailRef(meta)
  if type(meta) ~= "table" then return nil end
  return { sender = meta.sender, rel = meta.rel, cod = plainNum(meta.cod) or 0 }
end

-- ── honest sources (0.9.46, everbuff-wow-addon #43): the helpers of onMoney ─────────────────────────────────────
-- (functions on the Emitter table: the file's handlers sit at Lua's 60-upvalue limit)

-- One merchant purse change of `amount` on `key` (sold or vendor), from the pending list. An exact match writes the
-- item; several entries that sum to the amount write one row each, with the balance after each (rule 14). With no
-- exact match the oldest entry is used up as before: its item is named when it is the only one waiting or an amount
-- is not known, else the row is flagged `x=unmatched` and names no item.
function Emitter.creditItems(g, ses, key, list, amount, bal, withUnit)
  local npcName = Emitter._npc and Emitter._npc.merchant
  local es = Emitter.matchPending(list, amount)
  if es and #es > 1 then
    local sign = Emitter.GOLD_SIGN[key]
    local run = bal - sign * amount
    for _, e in ipairs(es) do
      run = run + sign * e.amount
      Emitter._gbal = run
      Emitter._gref = { npc = npcName, item = e.id, n = e.n, unit = withUnit and e.unit or nil }
      credit(g, ses, key, e.amount)
      if key == "sold" then Emitter.soldNote(ses, e.id, e.amount) end
    end
    Emitter._gbal = bal
    return
  end
  local ref = { npc = npcName }
  local e = es and es[1]
  if not e then
    local known = #list > 1
    for _, x in ipairs(list) do if not x.amount then known = false end end
    e = table.remove(list, 1)
    Emitter.restartPending(list)
    if e and known then ref.x = "unmatched"; e = nil end
  end
  if e then ref.item, ref.n = e.id, e.n; if withUnit then ref.unit = e.unit end end
  Emitter._gref = ref
  credit(g, ses, key, amount)
  if e and key == "sold" then Emitter.soldNote(ses, e.id, amount) end
end
-- What each item was sold for in the running session, less what was bought back (rule 27): a buyback is a sale
-- taken back only while a sale of that item booked in this session covers it, so `sold` and `gained` never go below
-- what the session's own sales put there. Kept in memory: after a /reload a buyback is a purchase, as before 0.9.46.
function Emitter.soldNote(ses, id, amount)
  local t = Emitter._sold
  if not t or t.ses ~= ses then t = { ses = ses, by = {} }; Emitter._sold = t end
  if id then t.by[id] = (t.by[id] or 0) + amount end
end
function Emitter.soldTake(ses, id, amount)
  local t = Emitter._sold
  if not (t and t.ses == ses and id and (t.by[id] or 0) >= amount) then return false end
  t.by[id] = t.by[id] - amount
  return true
end

-- Coin taken out of mails (rule 15): the mail whose money the gain equals, else the oldest mails that sum to it,
-- one row each with the balance after each; else a plain mail row, flagged `x=unmatched` when takes were waiting.
function Emitter.creditMail(g, ses, delta, bal)
  local waiting = Emitter.mailArmed()
  local list = waiting and Emitter.mailTake(delta) or nil
  local tnow = (GetServerTime and GetServerTime()) or time()
  local loc = locStamp()
  if not list then
    Emitter._gref = waiting and { x = "unmatched" } or nil
    credit(g, ses, "mail", delta)
    pushLoot({ t = tnow, money = delta, src = "Mail", x = loc.x, y = loc.y, zone = loc.zone })
    return
  end
  local run = bal - delta
  for _, e in ipairs(list) do
    run = run + e.money
    Emitter._gbal = run
    Emitter._gref = mailRef(e.meta)
    if e.src == "Auction sale" then
      credit(g, ses, "auctionSales", e.money)
      if ns.Market then pcall(ns.Market.sold, e.meta, e.money) end
    else credit(g, ses, "mail", e.money) end
    pushLoot({ t = tnow, money = e.money, src = e.src, mail = e.meta, x = loc.x, y = loc.y, zone = loc.zone })
  end
  Emitter._gbal = bal
end

-- The client's coin lines (rule 13), CHAT_MSG_MONEY, used as a classifier only: the text before the first %s of
-- LOOT_MONEY_SPLIT (a group share), YOU_LOOT_MONEY and YOU_LOOT_MONEY_GUILD says what the line is, in any locale.
-- A format that starts with its %s has no prefix and is skipped; a share prefix equal to a loot prefix cannot tell
-- the two apart and is skipped too. The longest prefix that fits the line wins.
function Emitter.coinForm(fmt)
  fmt = safeStr(fmt)
  if not fmt then return nil end
  local a, b = fmt:find("%%[%d%$]*s")
  if not a or a == 1 then return nil end
  local rest = fmt:sub(b + 1)
  local c = rest:find("%%[%d%$]*s")
  return { pre = fmt:sub(1, a - 1), mid = c and rest:sub(1, c - 1) or nil }
end
function Emitter.coinForms()
  local f = { split = Emitter.coinForm(LOOT_MONEY_SPLIT or nil), solo = Emitter.coinForm(YOU_LOOT_MONEY or nil), guild = Emitter.coinForm(YOU_LOOT_MONEY_GUILD or nil) }
  if f.guild and (not f.guild.mid or f.guild.mid == "") then f.guild = nil end
  if f.split and ((f.solo and f.solo.pre == f.split.pre) or (f.guild and f.guild.pre == f.split.pre)) then f.split = nil end
  return f
end
-- The words that name a coin after its figure, from the client's own amount formats (GOLD_AMOUNT "%d Gold"; a
-- format with the grammar escape |4one:few:many; gives every form): { g = { words }, s = ..., c = ... }.
function Emitter.coinWords()
  local out = {}
  for d, fmt in pairs({ g = GOLD_AMOUNT or false, s = SILVER_AMOUNT or false, c = COPPER_AMOUNT or false }) do
    fmt = safeStr(fmt or nil)
    local tail = fmt and fmt:match("%%d(.*)$")
    if tail then
      local words = {}
      local forms = tail:match("|4([^;]*);")
      if forms then
        for w in forms:gmatch("[^:]+") do words[#words + 1] = w end
      else
        tail = tail:gsub("^%s+", ""):gsub("%s+$", "")
        if tail ~= "" then words[1] = tail end
      end
      if #words > 0 then out[d] = words end
    end
  end
  return out
end
-- a coin icon names its coin (kept as a mark); any other texture or atlas is dropped
function Emitter.coinIcon(p)
  p = p:lower()
  return (p:find("gold", 1, true) and "\3g") or (p:find("silver", 1, true) and "\3s") or (p:find("copper", 1, true) and "\3c") or ""
end
-- { share = true or nil, groups = the digit groups of the amount that reached the purse, den = the coin each group
-- is ("g", "s", "c") where the line says so by a word or an icon } or nil for another line. The client's grammar
-- escapes (|4one:few:many; after a number, |1a;b; after a word, |2, |3-n(word)) are taken out first: an event text
-- that carries them unresolved must not have their digits read as amounts.
function Emitter.coinLine(msg)
  local f = Emitter.coinForms()
  local kind, len, text = nil, 0, nil
  for _, k in ipairs({ "guild", "solo", "split" }) do
    local p = f[k]
    if p and #p.pre > len and msg:sub(1, #p.pre) == p.pre then
      local body = msg:sub(#p.pre + 1)
      if k == "guild" then
        local at = body:find(p.mid, 1, true)
        body = at and body:sub(1, at - 1) or nil
      end
      if body then kind, len, text = k, #p.pre, body end
    end
  end
  if not kind then return nil end
  text = text:gsub("|T(.-)|t", Emitter.coinIcon):gsub("|A(.-)|a", Emitter.coinIcon):gsub("|cn[^:]*:", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  text = text:gsub("|4([^;]*);", "\1%1\2"):gsub("|1[^;]*;[^;]*;", ""):gsub("|3%-%d+%((.-)%)", "%1"):gsub("|2", "")
  local words = Emitter.coinWords()
  local groups, den = {}, {}
  local pos = 1
  while true do
    local a, b = text:find("%d+", pos)
    if not a then break end
    local after = text:sub(b + 1, (text:find("%d", b + 1) or (#text + 1)) - 1):gsub("^%s+", "")
    local d, len = nil, 0
    if after:sub(1, 1) == "\3" then d = after:sub(2, 2)
    else
      local forms = after:match("^\1([^\2]*)\2")
      for k, ws in pairs(words) do
        for _, w in ipairs(ws) do
          local hit
          if forms then hit = (":" .. forms .. ":"):find(":" .. w .. ":", 1, true) ~= nil else hit = after:sub(1, #w) == w end
          if hit and #w > len then d, len = k, #w end
        end
      end
    end
    groups[#groups + 1] = text:sub(a, b)
    den[#groups] = d
    pos = b + 1
  end
  if #groups == 0 then return nil end
  return { share = kind == "split" or nil, groups = groups, den = den }
end
-- The amount a line names when every figure says which coin it is (`den`): true or false for `delta`, nil when a
-- figure names no coin (then only the order of the figures can be compared). A figure with no coin followed by a
-- group of three digits is a thousands separator inside one figure.
function Emitter.coinExact(groups, den, delta)
  local sum, seen, acc = 0, {}, ""
  for i, gs in ipairs(groups) do
    acc = acc .. gs
    local d = den[i]
    if d then
      local mult = (d == "g" and 10000) or (d == "s" and 100) or (d == "c" and 1) or nil
      if not mult or seen[d] then return nil end
      seen[d] = true
      sum = sum + tonumber(acc) * mult
      acc = ""
    elseif not (groups[i + 1] and #groups[i + 1] == 3) then return nil end
  end
  if acc ~= "" then return nil end
  return sum == delta
end
-- The digit check: the line's digit groups are the gold, silver and copper of `delta`, in order (a denomination of
-- 0 may be left out; a large gold figure may be written in groups of three). Where the line names the coin of every
-- figure (`den`, from Emitter.coinLine) the amount is compared exactly: "1 Gold, 5 Silver" is never 1g 5c. Only a
-- line that does not say (no amount formats on this client, unknown words) is compared by order alone.
function Emitter.coinMatches(groups, delta, den)
  delta = plainNum(delta)
  if not delta or delta <= 0 or type(groups) ~= "table" then return false end
  if type(den) == "table" then
    local exact = Emitter.coinExact(groups, den, delta)
    if exact ~= nil then return exact end
  end
  local parts = { math.floor(delta / 10000), math.floor(delta % 10000 / 100), delta % 100 }
  local function try(comps)
    local i = 1
    for _, want in ipairs(comps) do
      local acc = groups[i]
      if not acc then return false end
      i = i + 1
      while tonumber(acc) ~= want and groups[i] and #groups[i] == 3 and #acc + 3 <= #tostring(want) do acc = acc .. groups[i]; i = i + 1 end
      if tonumber(acc) ~= want then return false end
    end
    return i - 1 == #groups
  end
  local nonzero, tail = {}, {}
  for _, v in ipairs(parts) do
    if v > 0 then nonzero[#nonzero + 1] = v end
    if v > 0 or #tail > 0 then tail[#tail + 1] = v end
  end
  return try(nonzero) or try(tail) or try(parts)
end
-- Coin lines and purse changes come in either order and several at a time (a pull of several mobs in a group), so
-- each side waits in a short list: Emitter._coin (lines no gain has claimed), Emitter._openGain (gains written
-- with no source) and Emitter._lastLoot (looted rows a share line may still mark). An entry lives 3 s, a list holds
-- 20. `qList` drops what is too old and returns the list (nil is an empty list: a test may clear one that way).
function Emitter.qList(name)
  local q = Emitter[name]
  if type(q) ~= "table" then q = {}; Emitter[name] = q end
  local now = GetTime()
  for i = #q, 1, -1 do if now - q[i].at >= 3 then table.remove(q, i) end end
  while #q > 20 do table.remove(q, 1) end
  return q
end
-- the oldest coin line of the last 3 s whose digits are this gain: it is taken and returned
function Emitter.coinClaim(delta)
  local q = Emitter.qList("_coin")
  for i, cm in ipairs(q) do
    if Emitter.coinMatches(cm.groups, delta, cm.den) then return table.remove(q, i) end
  end
  return nil
end
-- the loot log row of coin that came with no loot window of the player's own
function Emitter.coinRow(delta, share)
  if not ns.DB then return end
  local loc = locStamp()
  ns.DB.loot.log = ns.DB.loot.log or {}
  ns.DB.loot.log[#ns.DB.loot.log + 1] = { t = (GetServerTime and GetServerTime()) or time(), money = delta, src = share and "Group share" or "Coin",
    s = ns.DB.active, x = loc.x, y = loc.y, zone = loc.zone }
  ns.trimToCap(ns.DB.loot.log, 2000)
end
-- CHAT_MSG_MONEY. The line may come before the purse change (kept 3 s for onMoney) or after it: an income of
-- exactly these digits seen with no source in the last 3 s turns from unexplained into looted, like a quest claim,
-- and a looted row of these digits learns it was a group share. A line whose digits fit nothing changes nothing.
function Emitter.coinChat(msg)
  msg = safeStr(msg)
  if not msg or not ns.DB then return end
  local line = Emitter.coinLine(msg)
  if not line then return end
  local now = GetTime()
  local open = Emitter.qList("_openGain")
  for qi, o in ipairs(open) do
    if Emitter.coinMatches(line.groups, o.amount, line.den) then
      table.remove(open, qi)
      Emitter.coinBook(o, line.share)
      if ns.Gold and ns.Gold.fire then ns.Gold.fire() end
      return
    end
  end
  local loots = Emitter.qList("_lastLoot")
  for qi, l in ipairs(loots) do
    if Emitter.coinMatches(line.groups, l.amount, line.den) then
      table.remove(loots, qi)
      if line.share and not l.share and type(l.ses.goldLog) == "table" and l.ses.goldLog[l.i] == l.row then
        Emitter._grewrite = { ses = l.ses, i = l.i, row = l.row }
        Emitter._gref = { share = 1 }
        Emitter.goldRow(l.ses, "looted", l.amount)
        Emitter._grewrite, Emitter._gref = nil, nil
      end
      return
    end
  end
  if Emitter.coinSplit(line) then return end
  local q = Emitter.qList("_coin")
  q[#q + 1] = { share = line.share, groups = line.groups, den = line.den, at = now }
end
-- An income written with no source turns into looted coin: its journal row is rewritten in place, the day row and
-- the ledgers move from unexplained to looted (which also credits the place and the dungeon run, Gold.placeCredit),
-- and the loot log gets its coin row. `o` is an entry of Emitter._openGain.
function Emitter.coinBook(o, share)
  if o.i then Emitter._grewrite = { ses = o.ses, i = o.i, row = o.row } end
  Emitter._gref = share and { share = 1 } or nil
  Emitter._dayAt = o.epoch
  Emitter.goldDay("unexplained", -o.amount)
  credit(goldDB(), o.ses or sessionDB(), "looted", o.amount)
  Emitter._dayAt = nil
  Emitter._grewrite, Emitter._gref = nil, nil
  Emitter.coinRow(o.amount, share)
end
-- One coin line paid in several purse changes (0.9.52, gate H of docs/UX_PRAGMATIC.md). The client pays one group
-- share in two purse events at times ("Your share of the loot is 2 Silver, 55 Copper", then +154 and +101): no
-- single gain has the line's digits, so both stayed unexplained. Two to four incomes in a row that are still
-- waiting for a source (the 3 s of Emitter._openGain) and add up to exactly the line's amount are that line's coin.
-- Exact sums only; the oldest fitting run is taken. Returns true when the line was used.
function Emitter.coinSplit(line)
  local open = Emitter.qList("_openGain")
  for i = 1, #open do
    local sum = open[i].amount
    for j = i + 1, math.min(#open, i + 3) do
      sum = sum + open[j].amount
      if Emitter.coinMatches(line.groups, sum, line.den) then
        local part = {}
        for k = j, i, -1 do table.insert(part, 1, table.remove(open, k)) end
        for _, o in ipairs(part) do Emitter.coinBook(o, line.share) end
        if ns.Gold and ns.Gold.fire then ns.Gold.fire() end
        return true
      end
    end
  end
  return false
end
-- the same when the line came first: a line still waiting (Emitter._coin) and the incomes that now add up to it
function Emitter.coinLate()
  local q = Emitter.qList("_coin")
  for i, cm in ipairs(q) do
    if Emitter.coinSplit(cm) then table.remove(q, i); return true end
  end
  return false
end
-- Whether an income with no other source is the mailbox's (#52). The mailbox counts as open from MAIL_SHOW to
-- MAIL_CLOSED, and the client does not always send MAIL_CLOSED (walking away, a loading screen), so on its own the
-- flag made every group share of a dungeon "mail". The flag is cleared on PLAYER_ENTERING_WORLD (a loading screen
-- closes the mailbox), and inside an instance, where there is no mailbox, an income with no mail take waiting is
-- never the mailbox's: it goes on to the coin line and the loot window, or stays with no source.
function Emitter.mailHere()
  if not Emitter.at("mail") then return false end
  local c = ns.DB and ns.charGuid and ns.charGuid() and ns.char() or nil
  if c and c.inInstance ~= nil then return false end
  return true
end

-- Repairs by the drop of the repair cost (rule 24). The cost is sampled while the purse is unchanged: when the
-- merchant opens, on UPDATE_INVENTORY_DURABILITY and after each purse change at the merchant. A drop the client
-- shows before the purse change is kept for 2 s (`prev`), so either order of the two is read the same way.
function Emitter.repairCost()
  if type(GetRepairAllCost) ~= "function" then return nil end
  return plainNum(rd(GetRepairAllCost))
end
function Emitter.repairSample()
  local r = Emitter._repair
  if r.wait then return end
  local now, cost = GetTime(), Emitter.repairCost()
  if cost and r.cost and cost < r.cost and not (r.guildAt and now - r.guildAt < 2) then r.prev = { cost = r.cost, at = now } end
  r.cost = cost
end
-- a spend at a merchant whose repair cost had not moved yet, read again (on the next durability event, after
-- 0.3 s, before the next purse change, when the merchant closes): a repair when the cost dropped by it, else a purchase
function Emitter.repairResolve()
  local r = Emitter._repair
  local w = r.wait
  if not w then return end
  r.wait = nil
  local cost = Emitter.repairCost()
  Emitter._gbal, Emitter._dayAt = w.bal, w.dayAt
  if cost and w.cost - cost == w.spent then
    Emitter._gref = { npc = Emitter._npc.merchant, kind = cost > 0 and "repairOne" or nil }
    credit(w.g, w.ses, "repairs", w.spent)
  else
    Emitter.creditItems(w.g, w.ses, "vendor", Emitter._pend.buy, w.spent, w.bal, false)
  end
  Emitter._gref, Emitter._dayAt = nil, nil
  r.cost = cost
  if ns.Gold and ns.Gold.fire then ns.Gold.fire() end
end
-- true when the spend was booked (or is waiting to be) as a repair
function Emitter.creditRepair(g, ses, spent, bal)
  local r, now = Emitter._repair, GetTime()
  local cost = Emitter.repairCost()
  local before = r.cost
  if cost ~= nil and before ~= nil then
    local prev = r.prev
    if prev and now - prev.at < 2 and prev.cost - cost == spent then before = prev.cost end
    r.prev = nil
    if before - cost == spent then
      Emitter._gref = { npc = Emitter._npc.merchant, kind = cost > 0 and "repairOne" or nil }
      credit(g, ses, "repairs", spent)
      r.cost = cost
      return true
    end
    -- the cost has not moved yet: one more look before this is a purchase
    local can = type(CanMerchantRepair) ~= "function" or rd(CanMerchantRepair) ~= false
    if can and cost == before and before >= spent and C_Timer and type(C_Timer.After) == "function" then
      local w = { g = g, ses = ses, spent = spent, bal = bal, dayAt = Emitter._dayAt, cost = before }
      r.wait = w
      -- (only this wait's own timer books it: the timer of an earlier wait must not end a later one early)
      C_Timer.After(0.3, function() if Emitter._repair.wait == w then Emitter.repairResolve() end end)
      return true
    end
    return false
  end
  -- the client has no repair cost to read (or it is not known at this merchant): the 2 s rule of before
  if now < repairUntil then
    Emitter._gref = { npc = Emitter._npc.merchant }
    credit(g, ses, "repairs", spent)
    return true
  end
  return false
end

-- What a spend went to. Exact claims first (a talent reset of this cost, a buyback of this price), then the window
-- the purse paid in, as before: a trade, the merchant (a purchase of exactly this price, else a repair, else a
-- purchase), the trainer, a flight, the auction house (with the `kind` of the claim it equals), the mailbox.
function Emitter.creditSpend(g, ses, spent, bal)
  local npc, now = Emitter._npc, GetTime()
  local e
  if Emitter.at("merchant") and not Emitter._drift then
    local back = Emitter._pend.back
    Emitter.prunePending(back)
    for i, x in ipairs(back) do if x.amount == spent then e = table.remove(back, i); break end end
  end
  if e and Emitter.soldTake(ses, e.id, spent) then
    -- a sale of this session taken back (rule 27): out of `gained` and `sold` again, a `sold` row with a negative
    -- amount, so the income keys still sum to gained, the spend keys to spent, and farm income counts the sale once
    credit(g, ses, "gained", -spent); ses.gained = (ses.gained or 0) - spent
    Emitter._gref = { npc = npc.merchant, item = e.id, n = e.n, kind = "buyback" }
    credit(g, ses, "sold", -spent)
    Emitter.repairSample()
    return
  end
  credit(g, ses, "spent", spent); ses.spent = (ses.spent or 0) + spent
  local rs = Emitter._respec
  if Emitter._drift then Emitter._gref = { drift = 1 }; credit(g, ses, "other", spent)
  elseif e then
    -- bought back with no sale of it booked in this session (sold before a /reload or in an earlier session, or the
    -- sale was not seen): a purchase, as before 0.9.46
    Emitter._gref = { npc = npc.merchant, item = e.id, n = e.n }; credit(g, ses, "vendor", spent)
    Emitter.repairSample()
    repairUntil = 0
  -- a talent reset of exactly this cost (rule 30): within 20 s of the question, or within 60 s at a trainer
  elseif rs and rs.cost == spent and (now - rs.at < 20 or (now - rs.at < 60 and Emitter.at("trainer"))) then
    Emitter._respec = nil
    Emitter._gref = { npc = Emitter.at("trainer") and npc.trainer or nil, kind = "respec" }; credit(g, ses, "training", spent)
  elseif inTrade() then Emitter._gref = Emitter.tradeRef(-spent); credit(g, ses, "tradeSpent", spent); tradeRow(-spent)   -- coin we gave in a trade
  elseif Emitter.at("merchant") then
    Emitter.prunePending(Emitter._pend.buy)
    local exact = false
    for _, e in ipairs(Emitter._pend.buy) do if e.amount == spent then exact = true end end
    if exact or not Emitter.creditRepair(g, ses, spent, bal) then
      Emitter.creditItems(g, ses, "vendor", Emitter._pend.buy, spent, bal, false)
      Emitter.repairSample()
    end
    repairUntil = 0
  elseif Emitter.at("trainer") then Emitter._gref = { npc = npc.trainer }; credit(g, ses, "training", spent)
  elseif now < taxiUntil then Emitter._gref = { npc = npc.taxi }; credit(g, ses, "flights", spent); taxiUntil = 0
  elseif Emitter.at("auction") then                       -- bids, buyouts, deposits
    local kind = Emitter.ahTake(spent)
    Emitter._gref = kind and { kind = kind } or nil
    credit(g, ses, "auctions", spent)
  elseif Emitter.at("mail") then                          -- COD payments, postage
    local m = Emitter._mailCtx
    Emitter._gref = (m and now - m.at < 3) and mailRef(m.meta) or nil
    credit(g, ses, "mailSpent", spent)
  else credit(g, ses, "other", spent) end
end
-- A flight was asked for (rule 25, the TakeTaxiNode hook): the fare is the next spend, however long the map was
-- open, until the character is on the taxi. `taxiDone` ends the wait: 2 s after boarding (the fare may reach the
-- purse just after the taxi flag), at once when the flight never starts (the client says why, or 10 s pass).
function Emitter.taxiAsked() taxiUntil = GetTime() + 15 end
function Emitter.taxiDone(grace)
  local t = GetTime() + (grace or 0)
  if taxiUntil > t then taxiUntil = t end
end
-- the client's reasons a flight does not start, as it prints them (UI_ERROR_MESSAGE)
Emitter.TAXI_ERRORS = { ERR_TAXINOTENOUGHMONEY or false, ERR_TAXINOPATHS or false, ERR_TAXINOSUCHPATH or false, ERR_TAXINOVENDOR or false,
  ERR_TAXIPLAYERBUSY or false, ERR_TAXITOOFARAWAY or false, ERR_TAXISAMENODE or false, ERR_TAXIUNSPECIFIEDSERVERERROR or false,
  ERR_TAXIPLAYERALREADYMOUNTED or false, ERR_TAXIPLAYERSHAPESHIFTED or false, ERR_TAXIPLAYERMOVING or false, ERR_TAXINOTVISITED or false }
function Emitter.taxiError(msg)
  if not msg then return end
  for _, text in ipairs(Emitter.TAXI_ERRORS) do
    if text and safeStr(text) == msg then Emitter.taxiDone(0); return end
  end
end

local function onMoney()
  if not ns.DB then return end
  if Emitter._repair.wait then Emitter.repairResolve() end   -- a spend still waiting for its repair cost is booked first
  local c = plainNum(rd(GetMoney)); if not c then return end
  if lastMoney == nil then                                   -- first read of this load seeds the baseline
    -- the character is not known yet (0.9.44, #43): no baseline is seeded against the scratch block, which would
    -- lose the comparison with the saved balance. The next money event, or a read one second later, tries again.
    if not ns.charGuid() then
      if not Emitter._guidWait and C_Timer and C_Timer.After then
        Emitter._guidWait = true
        C_Timer.After(1, function() Emitter._guidWait = nil; onMoney() end)
      end
      return
    end
    Emitter.crashRead()
    local g = goldDB(); local prev = plainNum(g.balance)
    -- a 0 at load with gold saved may be the client not ready yet (0.9.44, #43): it is not trusted until a money
    -- event brings a read that is not 0, or 15 s have passed (read again after 3 s and after 15.5 s; the wait is
    -- compared against 14.5 s, so a timer that fires a few milliseconds early still books the 0)
    local z = Emitter._zero
    if c == 0 and prev and prev > 0 and C_Timer and C_Timer.After then
      if not z then
        Emitter._zero = { at = GetTime() }
        C_Timer.After(3, onMoney); C_Timer.After(15.5, onMoney)
        return
      elseif GetTime() - z.at < 14.5 then return end
    end
    -- A read that is not 0 while a 0 was waiting. It is the client's first real answer and seeds the baseline, with
    -- one exception: a gain that something explains (a quest reward of this amount, an open trade, merchant or
    -- mailbox, a mail just taken, a loot window) is income on a purse that really was 0. Then the 0 is booked
    -- against the saved balance at once, and the read is the next change like any other.
    local qm = Emitter._questMoney
    if z and c > 0 and prev and prev > 0 and c ~= prev and lastMoney == nil
      and ((qm and qm.amount == c and GetTime() - qm.at < 3) or inTrade() or Emitter.at("merchant") or Emitter.at("mail")
        or Emitter.mailArmed() or GetTime() < lootWindowUntil) then
      lastMoney = 0; g.balance = 0
      Emitter.goldAway(-prev, 0, rd(HasNewMail) == true, nil, true)
    else
      lastMoney = c; g.balance = c
      if prev and c ~= prev then
        -- a 0 booked after the wait: if the next read of this load, within 60 s, brings the saved balance back and
        -- nothing explains it as income, the booking is taken back
        if c == 0 then Emitter._zeroSeed = { prev = prev, at = GetTime() } end
        Emitter.goldAway(c - prev, c, rd(HasNewMail) == true)
      end
      return
    end
  end
  local delta = c - lastMoney; lastMoney = c
  if delta == 0 then return end
  local zs = Emitter._zeroSeed
  Emitter._zeroSeed = nil
  if zs and c == zs.prev and GetTime() - zs.at < 60 then
    local qm = Emitter._questMoney
    if not ((qm and qm.amount == delta and GetTime() - qm.at < 3) or inTrade() or Emitter.at("merchant") or Emitter.at("mail")
      or Emitter.mailArmed() or GetTime() < lootWindowUntil) then
      goldDB().balance = c
      Emitter.goldAway(delta, c, false, true)
      return
    end
  end
  local g = goldDB(); g.balance = c
  local ses = sessionDB()
  Emitter._gbal, Emitter._gref = c, nil
  -- one reading of the clock for every credit of this change, so they land on one day row (0.9.44, #43)
  Emitter._dayAt = (GetServerTime and GetServerTime()) or time()
  if delta > 0 then
    credit(g, ses, "gained", delta); ses.gained = (ses.gained or 0) + delta
    -- Which source a gain is (0.9.44, #43, the order matters because day rows are kept): a quest reward of exactly
    -- this amount, then an open trade, then a sale just asked for at a merchant, then a mail just taken, then
    -- (0.9.46) the client's own coin line with exactly these digits, and only then the loot window: a gain within
    -- 3 s of a corpse is not looted coin when one of those explains it. After the loot window: any gain at the
    -- mailbox, else unexplained. From 0.9.46 a gain at a merchant with no sale asked for stays unexplained, and a
    -- gain found by the drift check (no purse event came for it) is unexplained with `drift=1`.
    local how, coin
    if Emitter._drift then how = nil
    elseif Emitter._questMoney and Emitter._questMoney.amount == delta and GetTime() - Emitter._questMoney.at < 3 then how = "quests"
    elseif inTrade() then how = "trade"
    elseif Emitter.at("merchant") and Emitter.pendingSale() then how = "sold"
    -- (a take still waiting claims a gain at the mailbox, or anywhere when the gain is that mail's amount; a gain
    -- of another amount away from the mailbox is not the mail's: the coin line and the loot window are asked)
    elseif Emitter.mailArmed() and (Emitter.at("mail") or Emitter.mailTake(delta, true)) then how = "mail"
    else
      coin = Emitter.coinClaim(delta)
      if coin or GetTime() < lootWindowUntil then how = "looted"
      elseif Emitter.mailHere() then how = "mail" end
    end
    if how == "looted" then                             -- gained while a loot window was open = looted coin
      local own = GetTime() < lootWindowUntil
      if coin and coin.share then Emitter._gref = { share = 1 } end
      credit(g, ses, "looted", delta)
      -- (the row just written, when it was: a coin line that comes after it may still say it was a group share)
      local log = ses.goldLog
      local _, ld, lsrc = rowParse(type(log) == "table" and log[#log] or "")
      if lsrc == "looted" and ld == delta then
        local q = Emitter.qList("_lastLoot")
        q[#q + 1] = { ses = ses, i = #log, row = log[#log], amount = delta, at = GetTime(), share = coin and coin.share }
      end
      if own then
        ns.DB.loot.log = ns.DB.loot.log or {}
        ns.DB.loot.log[#ns.DB.loot.log + 1] = {
          t = (GetServerTime and GetServerTime()) or time(), money = delta, src = lootSource, guid = lootSourceGUID, s = ns.DB.active,
          x = lootLoc and lootLoc.x, y = lootLoc and lootLoc.y, zone = lootLoc and lootLoc.zone,
        }
        ns.trimToCap(ns.DB.loot.log, 2000)
      else Emitter.coinRow(delta, coin and coin.share) end
    elseif how == "trade" then
      Emitter._gref = Emitter.tradeRef(delta)
      credit(g, ses, "trade", delta); tradeRow(delta)     -- coin another player gave us in a trade
    elseif how == "quests" then
      Emitter._gref = { quest = Emitter._questMoney.quest }
      credit(g, ses, "quests", delta)                     -- a quest's money reward (QUEST_TURNED_IN just said so)
      Emitter._questMoney = nil
    elseif how == "sold" then
      Emitter.creditItems(g, ses, "sold", Emitter._pend.sell, delta, c, true)   -- vendoring items is income too
    elseif how == "mail" then
      Emitter.creditMail(g, ses, delta, c)                -- coin taken out of a mail: auction proceeds or gold a player sent us
    else
      -- no category yet: a quest turn-in or the client's coin line may claim it; until then the journal and the
      -- day row say unexplained
      Emitter.goldDay("unexplained", delta)
      Emitter._gref = Emitter._drift and { drift = 1 } or nil
      local i = Emitter.goldRow(ses, "unexplained", delta)
      if not Emitter._drift then
        local q = Emitter.qList("_openGain")
        q[#q + 1] = { amount = delta, at = GetTime(), epoch = Emitter._dayAt, ses = ses, i = i, row = i and ses.goldLog[i] }
        -- (a coin line that came first and is paid in several purse changes: this income may complete it)
        Emitter.coinLate()
      end
    end
    if Emitter.at("merchant") then Emitter.repairSample() end
  else
    Emitter.creditSpend(g, ses, -delta, c)
  end
  Emitter._gref, Emitter._dayAt = nil, nil
  if ns.Gold and ns.Gold.fire then ns.Gold.fire() end   -- the open tooltip and the open Gold pane follow the purse
end

-- A quest's money reward (#11, G-2). The client may change the money before or after QUEST_TURNED_IN: a gain
-- of exactly the reward in the 3 s before is claimed now (its journal row turns from unexplained into quests),
-- otherwise the next gain of exactly the reward within 3 s.
function Emitter.questMoney(amount, quest)
  if not amount or amount <= 0 or not ns.DB then return end
  local open = Emitter.qList("_openGain")
  for qi, o in ipairs(open) do
    if o.amount == amount then
      table.remove(open, qi)
      if o.i then Emitter._grewrite = { ses = o.ses, i = o.i, row = o.row } end
      Emitter._gref = { quest = quest }
      -- a move on the day row the income was booked on, also after a day rollover: unexplained down, quests up
      Emitter._dayAt = o.epoch
      Emitter.goldDay("unexplained", -amount)
      credit(goldDB(), o.ses or sessionDB(), "quests", amount)
      Emitter._dayAt = nil
      Emitter._grewrite = nil
      if ns.Gold and ns.Gold.fire then ns.Gold.fire() end
      return
    end
  end
  Emitter._questMoney = { amount = amount, at = GetTime(), quest = quest }
end

-- Drift (0.9.46, #43 rule 11): the purse differs from the last read and no PLAYER_MONEY came for it. Booked at once
-- on PLAYER_ENTERING_WORLD and one frame after a window closes (a purse event of the same frame is read first, so it
-- keeps its source), as unexplained income or unexplained spending with `drift=1`. The first read of a load seeds
-- the baseline as before.
function Emitter.driftCheck()
  if not ns.DB then return end
  if lastMoney == nil then return onMoney() end
  local c = plainNum(rd(GetMoney))
  if not c or c == lastMoney then return end
  Emitter._drift = true
  local ok, err = pcall(onMoney)
  Emitter._drift = nil
  if not ok then error(err, 0) end
end
function Emitter.driftSoon()
  if C_Timer and type(C_Timer.After) == "function" then C_Timer.After(0, Emitter.driftCheck) else Emitter.driftCheck() end
end

-- The journal's own event frame (Emitter's main handler sits at Lua's 60-upvalue limit): the trade window, the names
-- of the merchant, trainer and flight master the purse pays, the roster caches behind `rel`, and from 0.9.46 the
-- client's coin lines, the talent reset cost, the auction house's commodity quote, the repair cost and the drift
-- check when a window closes. Every event is registered through pcall: one this client does not have is skipped.
Emitter._npc = {}
do
  local jf = CreateFrame("Frame")
  ns.eventFrames[#ns.eventFrames + 1] = jf
  for _, e in ipairs({ "TRADE_SHOW", "TRADE_CLOSED", "TRADE_MONEY_CHANGED", "TRADE_PLAYER_ITEM_CHANGED", "TRADE_TARGET_ITEM_CHANGED",
    "TRADE_ACCEPT_UPDATE", "UI_INFO_MESSAGE", "MERCHANT_SHOW", "MERCHANT_CLOSED", "TRAINER_SHOW", "TAXIMAP_OPENED",
    "GUILD_ROSTER_UPDATE", "FRIENDLIST_UPDATE", "PLAYER_ENTERING_WORLD",
    "CHAT_MSG_MONEY", "CONFIRM_TALENT_WIPE", "COMMODITY_PRICE_UPDATED", "UPDATE_INVENTORY_DURABILITY",
    "TRAINER_CLOSED", "MAIL_CLOSED", "AUCTION_HOUSE_CLOSED", "PLAYER_LOGOUT", "UI_ERROR_MESSAGE",
    "AUCTION_HOUSE_AUCTION_CREATED", "AUCTION_HOUSE_PURCHASE_COMPLETED", "COMMODITY_PURCHASE_SUCCEEDED", "COMMODITY_PURCHASE_FAILED",
    "AUCTION_CANCELED", "AUCTION_HOUSE_SHOW_ERROR" }) do pcall(jf.RegisterEvent, jf, e) end
  local function npcName() return UnitName and safeStr(UnitName("NPC")) or nil end
  jf:SetScript("OnEvent", function(_, event, a1, a2)
    if event == "TRADE_SHOW" then Emitter.tradeShow()
    elseif event == "TRADE_CLOSED" then Emitter.tradeClosed()
    elseif event == "TRADE_MONEY_CHANGED" or event == "TRADE_PLAYER_ITEM_CHANGED" or event == "TRADE_TARGET_ITEM_CHANGED"
      or event == "TRADE_ACCEPT_UPDATE" then Emitter.tradeSnap()
    elseif event == "UI_INFO_MESSAGE" then
      local msg = safeStr(a2) or safeStr(a1)
      if msg and ERR_TRADE_COMPLETE and msg == ERR_TRADE_COMPLETE then Emitter.tradeDone(nil)
      elseif msg and ERR_TRADE_CANCELLED and msg == ERR_TRADE_CANCELLED then Emitter.tradeCancelled() end
    elseif Emitter.AH_DONE[event] ~= nil then Emitter.ahExpire(Emitter.AH_DONE[event] or nil)
    elseif event == "UI_ERROR_MESSAGE" then Emitter.taxiError(safeStr(a2) or safeStr(a1))
    elseif event == "MERCHANT_SHOW" then
      -- (a spend still waiting for its repair cost is booked first, at the merchant it was paid at: a wait is only
      -- ever ended by Emitter.repairResolve, so its spend always gets its row)
      Emitter.repairResolve()
      Emitter._merchantOpen = true; Emitter._npc.merchant = npcName()
      Emitter._repair.prev, Emitter._repair.cost = nil, nil
      Emitter.repairSample()
    elseif event == "MERCHANT_CLOSED" then
      Emitter._merchantOpen = false
      Emitter.repairResolve()
      Emitter._repair.cost, Emitter._repair.prev = nil, nil
      Emitter.driftSoon()
    elseif event == "UPDATE_INVENTORY_DURABILITY" then
      if Emitter._repair.wait then Emitter.repairResolve()
      elseif Emitter._merchantOpen then Emitter.repairSample() end
    elseif event == "TRAINER_SHOW" then Emitter._npc.trainer = npcName()
    elseif event == "TAXIMAP_OPENED" then Emitter._npc.taxi = npcName()
    elseif event == "TRAINER_CLOSED" or event == "MAIL_CLOSED" or event == "AUCTION_HOUSE_CLOSED" then Emitter.driftSoon()
    elseif event == "CHAT_MSG_MONEY" then Emitter.coinChat(a1)
    elseif event == "CONFIRM_TALENT_WIPE" then
      -- the cost of a talent reset, asked before it is paid (rule 30): the spend of exactly this is training
      local cost = plainNum(a1)
      Emitter._respec = (cost and cost > 0) and { cost = cost, at = GetTime() } or nil
    elseif event == "COMMODITY_PRICE_UPDATED" then Emitter._ah.quote = plainNum(a2)
    elseif event == "PLAYER_LOGOUT" then Emitter.repairResolve(); Emitter.openMark()
    elseif event == "GUILD_ROSTER_UPDATE" then Emitter.loadGuild()
    elseif event == "FRIENDLIST_UPDATE" then Emitter.loadFriends()
    elseif event == "PLAYER_ENTERING_WORLD" then
      Emitter.loadAlts(); Emitter.loadFriends()
      if IsInGuild and rd(IsInGuild) then
        if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) elseif GuildRoster then pcall(GuildRoster) end
      end
    end
  end)
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
  if sumM > 0 then ns.char().durability = { pct = math.floor(sumC / sumM * 100 + 0.5), at = (GetServerTime and GetServerTime()) or time() } end
end

local function onXP()
  if not ns.DB then return end
  local xp = plainNum(rd(UnitXP, "player"))
  local mx = plainNum(rd(UnitXPMax, "player"))
  if not xp or not mx then return end
  local x = ns.char().xp or { gained = 0 }; ns.char().xp = x
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
  local c = ns.char()
  c.played = c.played or {}
  c.played.total = total
  c.played.level = plainNum(levelt)
  c.played.atEpoch = (GetServerTime and GetServerTime()) or time()
  local lvl = plainNum(rd(UnitLevel, "player"))
  if lvl and lvl > 0 then
    c.playedAtLevel = c.playedAtLevel or {}
    c.playedAtLevel[lvl] = total          -- stamp real /played at each level for the pace chart
  end
end

-- ── group roster over time ──────────────────────────────────────────────────────
-- snapshotGroup() in Fights captures the party once at pull; here we diff the roster on every change so
-- a run with a swap or a resummon reads correctly ("Dave joined", "Mia left"). Login seeds silently.
-- #42 (0.9.49): when GROUP_ROSTER_UPDATE fires the client may not know a new member's name yet and answers its
-- placeholder ("Unknown"); the addon wrote "Unknown joined the group" and then "Unknown left the group". The client
-- can also hide a name (a secret value) for as long as an encounter lasts. A member whose name is not readable
-- (ns.unitName, Logging.lua) is there, without a name:
--   * nothing is written under the placeholder; the join is written when the name is readable;
--   * a name already seen that is missing is NOT a leave while any member is unnamed (it may be that member), however
--     long that lasts. The leave is written once every name is readable, or at once when the GUIDs are readable and
--     the member's GUID is no longer in the group;
--   * each unnamed member has its own record (Emitter._rosterWait, keyed by GUID, else by unit token): the roster is
--     read again on UNIT_NAME_UPDATE and, should that event not come, every 2 s for Emitter.ROSTER_WAIT seconds
--     counted per member, so a name that never comes does not switch the re-reads off for the next one;
--   * a member unnamed at a silent seed (login, loading screen) is part of that seed whenever its name arrives:
--     not a join. Every other join and leave during that time is written as usual.
-- State lives on the Emitter table: this file has no room for another file-level local.
local rosterSeen, rosterSeeded = {}, false
Emitter.ROSTER_WAIT = 30
local function currentRoster()
  local set, units = {}, {}
  local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
  local raid = IsInRaid and IsInRaid()
  for i = 1, n do
    local u = (raid and "raid" or "party") .. i
    if UnitExists(u) and not ns.isPlayerUnit(u) then
      local nm, wait = ns.unitName(u)
      if nm then set[nm] = true end
      if nm or wait then units[#units + 1] = { unit = u, name = nm, guid = ns.unitGUID(u) } end
    end
  end
  return set, units
end
local function diffRoster(fire)
  local now, units = currentRoster()
  local t, old = GetTime(), Emitter._rosterWait
  if type(Emitter._rosterGuid) ~= "table" then Emitter._rosterGuid = {} end
  local guidOf = Emitter._rosterGuid             -- name -> GUID, for the names seen with a readable GUID
  local pend, fresh, silent = nil, false, {}
  local allGuid, here = true, {}                 -- is every unit's GUID readable, and which GUIDs are in the group
  for _, x in ipairs(units) do
    if x.guid then here[x.guid] = true else allGuid = false end
    local rec = old and ((x.guid and old[x.guid]) or old[x.unit]) or nil
    if x.name then
      if rec and rec.seed then silent[x.name] = true end   -- unnamed at a silent seed: part of it, not a join
      if x.guid then guidOf[x.name] = x.guid end
    else
      rec = rec or { since = t, seed = not fire }
      pend = pend or {}
      pend[x.guid or x.unit] = rec
      if t - rec.since < Emitter.ROSTER_WAIT then fresh = true end
    end
  end
  -- the names seen before that are not readable now: gone for sure (its GUID is not in the group), or maybe unnamed
  local gone, maybe = {}, {}
  for nm in pairs(rosterSeen) do
    if not now[nm] then
      local g = guidOf[nm]
      if g and allGuid and not here[g] then gone[#gone + 1] = nm else maybe[#maybe + 1] = nm end
    end
  end
  if fire then
    for nm in pairs(now) do
      if not rosterSeen[nm] and not silent[nm] then Emitter.event("ROSTERJOIN", { name = nm }, true) end
    end
    for _, nm in ipairs(gone) do Emitter.event("ROSTERLEAVE", { name = nm }, true) end
    for _, nm in ipairs(maybe) do
      if pend then now[nm] = true                -- kept as seen until every name is readable
      else Emitter.event("ROSTERLEAVE", { name = nm }, true) end
    end
  elseif pend then
    -- a silent seed forgets who is gone, but not a member who is only unnamed right now: as many names as there
    -- are unnamed units can be those units. More missing names than that: the old roster says nothing, it is dropped.
    local n = 0
    for _ in pairs(pend) do n = n + 1 end
    if #maybe <= n then for _, nm in ipairs(maybe) do now[nm] = true end end
  end
  for nm in pairs(guidOf) do if not now[nm] then guidOf[nm] = nil end end
  rosterSeen = now; rosterSeeded = true
  Emitter._rosterWait = pend
  -- one re-read at a time (a re-read due for more than 4 s never ran: schedule again)
  if fresh and not (Emitter._rosterTimer and t - Emitter._rosterTimer < 4) and C_Timer and C_Timer.After then
    Emitter._rosterTimer = t
    C_Timer.After(2, function()
      Emitter._rosterTimer = nil
      if Emitter._rosterWait then pcall(Emitter.rosterReread) end
    end)
  end
end
function Emitter.rosterReread() diffRoster(rosterSeeded) end

local ef = CreateFrame("Frame")
ns.eventFrames[#ns.eventFrames + 1] = ef
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
  "UNIT_NAME_UPDATE",                                    -- a member's name arrived after the roster change (#42)
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
  if ns.DB and next(out) then ns.char().professions = out end
  profSeeded = true
end

-- every reputation gain, not just tier-ups: faction, amount and what caused it (a quest turned in or a kill a
-- moment before), with the place. Kept in story.rep (capped 2000) so a mob-grinding session never pushes the
-- rest of the timeline out of story.events. Record only: nothing on screen changes.
-- A learned recipe, recorded once (#11): the WoW Forever client both prints the system line and fires
-- NEW_RECIPE_LEARNED for the same recipe, which wrote two RECIPE rows and showed two notifications. A second
-- report of the same recipe within 5 s, or an unnamed one within 5 s of any, is the same recipe.
function Emitter.recipe(name)
  local now, last = GetTime(), Emitter._lastRecipe
  if last and (now - last.at) < 5 and (last.name == name or not name) then return false end
  Emitter._lastRecipe = { name = name, at = now }
  Emitter.event("RECIPE", { name = name or "a new recipe" })
  return true
end

Emitter.REPGAIN_PAT = fmtToPattern(FACTION_STANDING_INCREASED or "Reputation with %s increased by %d.")
function Emitter.repGain(msg)
  if not ns.DB then return end
  msg = Emitter.chatText("rep", msg)      -- a line the client hides is counted and dropped (0.9.49)
  if not msg then return end
  local faction, amount = msg:match(Emitter.REPGAIN_PAT)
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
  if ns.DB and next(snap) then ns.char().reputation = snap end
end

ef:SetScript("OnEvent", function(_, event, a1, a2, a3, a4, a5)
  if event == "PLAYER_LEVEL_UP" then
    Emitter.event("LEVELUP", { level = a1 })
    if RequestTimePlayed then pcall(RequestTimePlayed) end   -- stamp real /played at this ding (pace chart)
  elseif event == "ZONE_CHANGED_NEW_AREA" then
    pcall(Emitter.checkInstance)   -- a client that enters an instance without a loading screen event still counts
    local z = GetRealZoneText() or GetZoneText()
    if z and z ~= lastZone then
      lastZone = z
      Emitter.event("ZONE", { zone = z })
      -- the journey milestone is the FIRST time you set foot somewhere, not every re-entry
      if ns.DB then
        ns.char().seenZones = ns.char().seenZones or {}
        if not ns.char().seenZones[z] then
          ns.char().seenZones[z] = (GetServerTime and GetServerTime()) or time()
          Emitter.event("FIRSTZONE", { zone = z })
        end
      end
    end
  elseif event == "PLAYER_ENTERING_WORLD" then
    mailOpen = false   -- (#52: a loading screen always closes the mailbox, and the client may send no MAIL_CLOSED)
    Emitter.backfillLootQuality()
    refreshClassColor(); paintFlag()
    place()   -- settings are loaded now, so move the flag to the corner the user saved last time
    Emitter.applyFlagPrefs()
    spellReady = false
    Emitter.loadKind(a1)   -- a login reads the mark of a session that never saved (rule 9)
    Emitter.driftCheck()   -- seeds the gold baseline on the first read of a load; later a difference no event explained is drift
    if C_Timer and C_Timer.After then
      C_Timer.After(10, function() spellReady = true; scanRep(false); repSeeded = true end)  -- seed rep baseline, don't fire on login
      C_Timer.After(12, function() if RequestTimePlayed then pcall(RequestTimePlayed) end end) -- /played once on login
      C_Timer.After(15, function() if RequestRaidInfo then pcall(RequestRaidInfo) end end)     -- lockouts once on login
    end
    if ns.Runs and ns.Runs.loaded then pcall(ns.Runs.loaded, a1, a2) end   -- the dungeon run learns what kind of load this is
    pcall(Emitter.checkInstance)   -- dungeon entry or exit, deduped on the character across /reload
    lastZone = GetRealZoneText()
    if ns.DB and lastZone then   -- the zone you log into is "seen", not discovered
      ns.char().seenZones = ns.char().seenZones or {}
      ns.char().seenZones[lastZone] = ns.char().seenZones[lastZone] or ((GetServerTime and GetServerTime()) or time())
    end
    diffRoster(false)   -- seed the roster without announcing everyone on login
    onDurability()      -- seed gear health
    scanProfessions(false)   -- seed profession ranks without announcing
    if GetAverageItemLevel and ns.DB then local _, eq = GetAverageItemLevel(); ns.char().ilvl = plainNum(eq) or ns.char().ilvl end
  elseif event == "PLAYER_REGEN_DISABLED" then
    setCombat(true)
  elseif event == "PLAYER_REGEN_ENABLED" then
    -- best-effort mob kill: combat ended and we're alive → count the foe we were fighting as killed.
    -- (uses the foe captured while it was alive; a dead corpse reports not-attackable so we can't
    --  re-derive it here. skips if a boss ENCOUNTER_END just logged the same name.)
    if not wasDead then
      local foe = combatFoe   -- already safeStr at capture (a plain string or nil)
      -- (0.9.49: the target only when it is an enemy. With the enemy's name hidden, a healer's friendly target was
      -- taken for the foe and the row read "<party member> down!", seen in the save of 2026-11-19.)
      if not foe and Emitter.targetIsFoe() then foe = safeStr(UnitName("target")) end
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
    pcall(pushed.request)
    local qxp = plainNum(a2)                              -- (questID, xpReward, moneyReward)
    Emitter.event("QUESTDONE", { name = questTitle(a1, nil), xp = qxp })
    Emitter.questMoney(plainNum(a3), plainNum(a1))
    if qxp and qxp > 0 and ns.DB then ns.char().xp = ns.char().xp or {}; ns.char().xp.fromQuests = (ns.char().xp.fromQuests or 0) + qxp end
  elseif event == "ENCOUNTER_START" then
    Emitter.event("BOSS", { name = a2 or "boss" })
  elseif event == "ENCOUNTER_END" then
    Emitter.event(a5 == 1 and "KILL" or "WIPE", { name = a2 or "boss" })
  elseif event == "PLAYER_DEAD" then
    wasDead = true; deadAt = GetTime()
    pushed.durBefore = ns.DB and ns.char().durability and ns.char().durability.pct or nil   -- gear health going in
    local hit = pushed.lastHit
    Emitter.event("DEATH", { foe = (hit and hit.name and (GetTime() - hit.at) < 10) and hit.name or nil })
    if ns.Runs and ns.Runs.deathFoe then pcall(ns.Runs.deathFoe, (hit and hit.name and (GetTime() - hit.at) < 10) and hit.name or nil) end
  elseif event == "PLAYER_UNGHOST" or event == "PLAYER_ALIVE" then
    -- only a real resurrection, not the PLAYER_ALIVE that also fires on login
    if wasDead and (not UnitIsDeadOrGhost or not UnitIsDeadOrGhost("player")) then
      wasDead = false
      local down = deadAt and math.max(0, GetTime() - deadAt) or nil; deadAt = nil
      -- stamp the downtime on the DEATH row so the Deaths tab can show how long the corpse run took
      if down and ns.DB and ns.DB.story.events then
        onDurability()   -- fresh read after the corpse run / spirit healer
        local after = ns.char().durability and ns.char().durability.pct
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
    local skill, val = (Emitter.chatText(nil, a1) or ""):match(SKILLUP_PAT)
    if skill then
      local d = { name = skill, level = tonumber(val) }
      -- if we crafted something in the last few seconds, this profession skill-up came from it
      if lastCraft and (GetTime() - lastCraft.at) < 6 then
        d.craft = lastCraft.item; d.crafted = lastCraft.count
      end
      Emitter.event("SKILLUP", d)
    end
  elseif event == "CHAT_MSG_SYSTEM" then
    local msg = Emitter.chatText("system", a1) or ""
    local area = msg:match(DISCOVER_XP_PAT) or msg:match(DISCOVER_PAT)
    local recipe = msg:match(RECIPE_PAT)
    if recipe then
      Emitter.recipe(recipe:match("%[(.-)%]") or recipe)
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
  elseif event == "UNIT_NAME_UPDATE" then
    if Emitter._rosterWait then pcall(diffRoster, rosterSeeded) end   -- only while a member has no readable name (#42)
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
      ns.char().lockouts = out
    end
  elseif event == "SKILL_LINES_CHANGED" then scanProfessions(profSeeded)
  elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
    local kxp = killXpFrom(Emitter.chatText("xp", a1) or "")
    if kxp and ns.DB then ns.char().xp = ns.char().xp or {}; ns.char().xp.fromKills = (ns.char().xp.fromKills or 0) + kxp end
  elseif event == "NEW_RECIPE_LEARNED" then
    local nm
    if a1 and C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo then local ok, info = pcall(C_TradeSkillUI.GetRecipeInfo, a1); nm = ok and info and safeStr(info.name) end
    Emitter.recipe(nm)
    if ns.Market then pcall(ns.Market.recipe, nm) end
  elseif event == "PLAYER_EQUIPMENT_CHANGED" then
    -- journey-level gear progression: equipped item level going UP (checked out of combat only)
    if not (InCombatLockdown and InCombatLockdown()) and GetAverageItemLevel and ns.DB then
      local _, eq = GetAverageItemLevel()
      eq = plainNum(eq)
      if eq then
        local prev = tonumber(ns.char().ilvl)
        if prev and eq > prev + 0.05 then Emitter.event("UPGRADE", { level = math.floor(eq + 0.5) }) end
        ns.char().ilvl = eq
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
      elseif typ == "Item" then lootSource = "Container"   -- (an opened bag item: a lockbox, a clam, a crate)
      else lootSource = "Unknown source" end
      lootSourceGUID = sg
    end
    lootWindowUntil = GetTime() + 3   -- coin gained in this window is attributed to this loot source
    -- (kept until the next loot; NOT cleared on LOOT_CLOSED, since loot messages can arrive at/after close)
  elseif event == "CHAT_MSG_LOOT" then
    local msg = Emitter.chatText("loot", a1) or ""
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
      -- (0.9.52, gate G: every row is stamped where the character stands when the item arrives, and a row with no
      -- loot window is marked `pushed` and says how its source was named, `srcBy`. Before, a row took the place of
      -- the last loot window, which could be minutes old, another zone or none at all.)
      local src, srcGUID = lootSource, lootSourceGUID
      local at, wasPushed, srcBy = locStamp(), nil, nil
      if GetTime() > lootWindowUntil + 12 then src, srcGUID, srcBy = pushedSource(msg, item); wasPushed = true end
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
          x = at and at.x, y = at and at.y, zone = at and at.zone, map = at and at.map, pushed = wasPushed, srcBy = srcBy,
        }
        ns.trimToCap(ns.DB.loot.log, 2000)
      end
      -- drops at or above the loot-toast threshold get the on-screen flag; the rest stay off-screen
      if ns.Recorder and ns.Recorder.bump then ns.Recorder.bump("items") end
      -- an item looted inside a dungeon run counts on the run, with its vendor price as an estimate (0.9.47, #43)
      if ns.Gold and ns.Gold.runItem then pcall(ns.Gold.runItem, id, count) end
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
    Emitter.taxiDone(2)   -- on the taxi: the fare is paid, or reaches the purse in a moment
  elseif fromHook then
    flightStart = { t = GetTime(), zone = zone, boarded = false }
  end
end
function Emitter.landFlight()
  if not flightStart or not flightStart.boarded then return end
  local dur = math.max(0, GetTime() - flightStart.t)
  local to = (GetRealZoneText and GetRealZoneText()) or "?"
  if ns.DB then ns.char().flightTime = (ns.char().flightTime or 0) + dur end
  local from = flightStart.zone
  flightStart = nil
  Emitter.event("FLIGHTTRIP", { name = ("%s to %s (%dm %ds)"):format(from, to, math.floor(dur / 60), math.floor(dur % 60)), duration = dur }, true)
end
if TakeTaxiNode and hooksecurefunc then
  hooksecurefunc("TakeTaxiNode", function()
    Emitter.taxiAsked()
    pcall(Emitter.boardFlight, true)
    if not (C_Timer and C_Timer.NewTicker) then return end
    local waited, tk = 0, nil
    tk = C_Timer.NewTicker(1, function()
      waited = waited + 1
      if not flightStart then if tk then tk:Cancel() end; return end
      local onTaxi = UnitOnTaxi and UnitOnTaxi("player")
      if not flightStart.boarded then
        if onTaxi then Emitter.boardFlight(false)
        elseif waited > 10 then flightStart = nil; Emitter.taxiDone(0); if tk then tk:Cancel() end end   -- the taxi never left
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
  ns.eventFrames[#ns.eventFrames + 1] = qf
  qf:RegisterEvent("QUEST_COMPLETE")
  qf:SetScript("OnEvent", function()
    local t, n = {}, 0
    if GetNumQuestChoices then local ok, c = pcall(GetNumQuestChoices); n = (ok and type(c) == "number") and c or 0 end
    for i = 1, n do t[i] = choiceName(i) end
    Emitter._rewardChoices = t
    Emitter._rewardDone = nil
  end)
end
if GetQuestReward and hooksecurefunc then
  hooksecurefunc("GetQuestReward", function(choice)
    if type(choice) ~= "number" or choice == 0 then return end
    local name = choiceName(choice) or Emitter._rewardChoices[choice]
    Emitter._rewardChoices = {}
    -- one REWARD per reward panel (#11): on WoW Forever GetQuestReward ran again 4 s after a turn-in and wrote the
    -- choice twice; the same choice again before the next panel opens is the same reward
    if name and name ~= Emitter._rewardDone then
      Emitter._rewardDone = name
      Emitter.event("REWARD", { name = name })
    end
  end)
end

-- ── the Settings tab ───────
if ns.UI and ns.UI.registerTab then
  -- the panes are Sync.lua's (ns.BuildSettings, docs/UX_OVERHAUL.md 4.12)
  ns.UI.registerTab(20, "Settings", function(content)
    if ns.BuildSettings then ns.BuildSettings(content) end
  end, function() end, nil, "bottom", "How the window and notifications behave, and whether your data reaches everbuff.gg.")

  -- ── Home > Activity (docs/UX_OVERHAUL.md 4.2): everything you did, newest first under day rows, on the kit table.
  --    The group filter and the search sit in the control row; a fight's window (ns.OpenTimelineWindow) shows on the
  --    summary line with a link back to everything. Every kind the addon writes is in exactly one group.
  local eventsRebuild, eventsTicker, eventsView
  local EVENT_GROUP = {
    journey = { QUESTACCEPT = true, QUESTDONE = true, REWARD = true, LEVELUP = true, REP = true, ACHIEV = true, SPELL = true },
    combat  = { KILL = true, BOSS = true, WIPE = true, DEATH = true, ALIVE = true, ROSTERJOIN = true, ROSTERLEAVE = true },
    travel  = { ZONE = true, FIRSTZONE = true, DISCOVERY = true, FLIGHT = true, FLIGHTTRIP = true, DUNGEON = true, DUNGEONLEAVE = true },
    loot    = { LOOT = true, COLLECT = true, UPGRADE = true, BROKEN = true, GOLDAWAY = true },
    town    = { VENDOR = true, TRAINER = true, MAIL = true, AUCTION = true, TRADE = true, BANK = true },
    professions = { SKILLUP = true, RECIPE = true, PROFTIER = true },
  }
  -- an optional time window (a fight's span) set by ns.OpenTimelineWindow; cleared from the summary line
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
      if t >= st - 1 and t <= st + (f.duration or 0) + 2 and ns.isMine(f) then return f end
    end
  end
  ns.UI.registerPane("Home", 3, "Activity", function(content)
    local UI = ns.UI
    local S, G, H = UI.S, UI.G, UI.H
    eventsView = content
    -- pane state on one table (no new upvalues for the module's event handler)
    local A = { filter = "all", GROUPS = {
      { "all", "Everything" }, { "journey", "Quests and levels" }, { "combat", "Fights" }, { "travel", "Travel" },
      { "loot", "Loot and gear" }, { "town", "Town visits" }, { "professions", "Professions" } } }
    function A.groupLabel(key) for _, g in ipairs(A.GROUPS) do if g[1] == key then return g[2] end end return "Everything" end
    -- the event text as the player reads it: one space between words (the stored notification text has two after
    -- its colon; that text is what the desktop reads on screen, so it is kept as written)
    function A.text(e) return (tostring(e.text or UI.KIND_LABEL[e.kind] or e.kind or "?"):gsub("%s%s+", " ")) end
    -- the page: one scroll holding the summary line, the section header and the list
    local v = CreateFrame("Frame", nil, content); v:SetAllPoints(content)
    local sf, col = UI.ScrollChild(v, { slim = true, top = 0, left = 0, right = 0, bottom = 0 })
    A.col = CreateFrame("Frame", nil, col); A.col:SetPoint("TOPLEFT", col, "TOPLEFT", 0, 0); A.col:SetSize(1, 1)
    col = A.col
    A.summary = UI.Summary(col)
    A.section = UI.Section(col, "All activity")
    content.timelineSummary, content.timelineSection = A.summary, A.section
    -- the control row, right to left: the group filter, then the search S2 left of it (as Loot > Items)
    local controls = content.ebControls or v
    A.filterBtn = UI.FilterButton(controls, { default = "all", label = "Everything",
      items = function()
        local out = {}
        for _, g in ipairs(A.GROUPS) do out[#out + 1] = { g[1], g[2], A.filter == g[1] } end
        return out
      end,
      onPick = function(key) content.setFilter(key) end })
    A.filterBtn:SetPoint("TOPRIGHT", controls, "TOPRIGHT", 0, 0)
    local search = UI.Search(controls, "Search activity")
    search:SetPoint("TOPRIGHT", A.filterBtn, "TOPLEFT", -S.S2, 0)
    search:HookScript("OnTextChanged", function() if eventsRebuild then eventsRebuild() end end)
    content.search, content.filterButton = search, A.filterBtn
    function content.setFilter(key)
      A.filter = EVENT_GROUP[key] and key or "all"
      A.filterBtn:SetValue(A.filter, A.groupLabel(A.filter))
      if eventsRebuild then eventsRebuild() end
    end
    content.filter = function() return A.filter end
    ns.OpenTimelineWindow = function(t0, t1, label)
      window = { t0 = t0, t1 = t1, label = label or "this window" }
      if UI.Open then UI.Open("Home", "activity") end
      if eventsRebuild then eventsRebuild() end
    end
    content.clearWindow = function() window = nil; if eventsRebuild then eventsRebuild() end end
    ns._test.timelineWindow = function() return window end
    local typeNames = {}
    for _, label in pairs(UI.KIND_LABEL) do typeNames[#typeNames + 1] = label end
    -- When · Type · Event · Place · Coords (WIDE) · ›. Type is a word in BODY fgSubtle; only a kill, a wipe and a
    -- death carry a colour (2.5 rule 3). The chevron is the last 12 px column.
    local tbl = UI.KitTable(col, {
      { key = "time", label = "When", kind = "tag", min = 40, measure = { "00:00" } },
      { key = "type", label = "Type", kind = "tag", min = 72, measure = typeNames },
      { key = "ev", label = "Event", flex = 1, min = 120 },
      { key = "where", label = "Place", kind = "tag", min = 140, max = 140 },
      { key = "coords", label = "Coords", kind = "num", min = 72, wide = true, measure = { "100.0, 100.0" } },
    }, {
      onClick = function(_, ev)
        if not ev or ev.ebSection then return end
        if EVENT_GROUP.combat[ev.kind] then
          local f = fightAt(ev.t or 0); if f and ns.OpenFightDetail then ns.OpenFightDetail(f) end
        elseif ev.kind == "LOOT" and UI.Open then UI.Open("Loot", "items") end
      end,
      onHeight = function() if A.place then pcall(A.place) end end,
      tooltip = function(r, ev, tip)
        if not ev or ev.ebSection then return end
        tip:AddLine(A.text(ev), 1, 1, 1, true)
        tip:AddLine(UI.fmtWhen(ev.t or 0) .. " \194\183 " .. (UI.KIND_LABEL[ev.kind] or ev.kind or ""), 0.78, 0.79, 0.80)
        local place = UI.fmtPlace(ev.zone, ev.sub); local co = UI.fmtCoords(ev.x, ev.y)
        if place ~= "" or co ~= "" then tip:AddLine(place .. (co ~= "" and ("  " .. co) or ""), 0.78, 0.79, 0.80) end
        if ev.standing then tip:AddLine("Standing: " .. tostring(ev.standing), 0.78, 0.79, 0.80) end
        if ev.craft then tip:AddLine(("Crafted: %s x%s"):format(tostring(ev.craft), tostring(ev.crafted or 1)), 0.78, 0.79, 0.80) end
        -- (the enemy you were fighting, only when the event does not already name it)
        if ev.foe and not A.text(ev):find(tostring(ev.foe), 1, true) then tip:AddLine("While fighting " .. tostring(ev.foe), 0.78, 0.79, 0.80) end
        if ev.downtime then tip:AddLine("Back on your feet after " .. UI.fmtDur(ev.downtime), 0.78, 0.79, 0.80) end
        if r.clickable then tip:AddLine("Click to open", 0.55, 0.57, 0.59) end
      end })
    content.timelineTable = tbl
    content.timelineRows = tbl.rows   -- exposed for the headless tests
    function A.fill(row, e)
      row.ev = e
      row.clickable = (EVENT_GROUP.combat[e.kind] and fightAt(e.t or 0) ~= nil) or e.kind == "LOOT"
      row.ebNoOpen = (not row.clickable) or nil
      local c = row.c
      c.time:SetText(UI.fmtClock(e.t or 0))
      local res = UI.KIND_RESULT[e.kind]
      local word = UI.KIND_LABEL[e.kind] or "Other"
      c.type:SetText(res == "bad" and (UI.dot("bad") .. word) or word)
      if res then UI.SetColor(c.type, res) end
      c.ev:SetText(A.text(e))
      c.where:SetText(e.zone or "-"); if not e.zone then UI.SetColor(c.where, "fgMuted") end
      local co = UI.fmtCoords(e.x, e.y)
      c.coords:SetText(co ~= "" and co or "-"); if co == "" then UI.SetColor(c.coords, "fgMuted") end
    end
    A.place = function()
      local w = G.mainW(G.winW())
      col:SetWidth(w)
      A.summary:ClearAllPoints(); A.summary:SetPoint("TOPLEFT", col, "TOPLEFT", 0, 0); A.summary:SetWidth(w); pcall(A.summary.layout)
      local y = H.SUMMARY + S.S3
      A.section:ClearAllPoints(); A.section:SetPoint("TOPLEFT", col, "TOPLEFT", 0, -y); A.section:SetWidth(w); y = y + H.SECTION
      tbl.frame:ClearAllPoints(); tbl.frame:SetPoint("TOPLEFT", col, "TOPLEFT", 0, -y); tbl.frame:SetWidth(w)
      if tbl.width ~= math.min(w, G.TABLE_MAX) then tbl.relayout(w) end
      y = y + (tbl.height or 0) + S.S4
      col:SetHeight(y); sf:SetContentHeight(y)
      A.contentH = y
    end
    content:HookScript("OnSizeChanged", function() pcall(A.place) end)
    -- the answer: what this session holds so far, or the fight's window and the way back to everything
    function A.answer(log)
      if window then
        A.summary:SetSegments({ { text = "Showing **" .. tostring(window.label) .. "**" }, { text = "Show everything", onClick = function() content.clearWindow() end } })
        return
      end
      local sid = ns.DB and ns.DB.active
      local n, kills, quests = 0, 0, 0
      for _, e in ipairs(log) do
        if e.s == sid then
          n = n + 1
          if e.kind == "KILL" then kills = kills + 1 elseif e.kind == "QUESTDONE" then quests = quests + 1 end
        end
      end
      local segs = { { text = n == 0 and "This session: nothing yet" or ("This session: **%s**"):format(UI.plural(n, "event")) } }
      if kills > 0 then segs[#segs + 1] = { text = ("**%s**"):format(UI.plural(kills, "kill")) } end
      if quests > 0 then segs[#segs + 1] = { text = ("**%s** turned in"):format(UI.plural(quests, "quest")) } end
      A.summary:SetSegments(segs)
    end
    eventsRebuild = function()
      local log = ns.mine(ns.DB and ns.DB.story.events)   -- the logged-in character's events only (#23)
      local q = search:GetText() or ""
      A.answer(log)
      local list = {}
      for i = #log, 1, -1 do if eventMatches(log[i], A.filter, q) then list[#list + 1] = log[i] end end
      -- a day row over each day: "TODAY · 42 EVENTS"
      local days = {}
      for _, e in ipairs(list) do local k = date("%Y-%m-%d", e.t or 0); days[k] = (days[k] or 0) + 1 end
      local items, lastDay = {}, nil
      for _, e in ipairs(list) do
        local k = date("%Y-%m-%d", e.t or 0)
        if k ~= lastDay then lastDay = k; items[#items + 1] = { ebSection = UI.fmtDay(e.t or 0) .. " \194\183 " .. UI.plural(days[k], "event") } end
        items[#items + 1] = e
      end
      tbl.setRows(items, A.fill)
      for _, row in ipairs(tbl.rows) do if row.item and row.item.ebSection then row.ev, row.clickable = nil, nil end end
      A.section:SetMeta(#list > 0 and UI.plural(#list, "event") or nil)
      if #items == 0 then
        if q ~= "" then tbl.setState(('No event matches "%s". '):format(q), "Clear search", function() search:SetText("") end)
        elseif #log == 0 then tbl.setState("Nothing yet. Quests, kills, loot and town visits show here as you play.")
        else tbl.setState(("Nothing under %s yet."):format(A.groupLabel(A.filter)), "Show everything", function() content.setFilter("all") end) end
      end
      A.place()
    end
    content.setFilter("all")
  end, function()
    if eventsRebuild then eventsRebuild() end
    -- rebuild only while this tab is actually visible (the old ticker ran forever, even hidden)
    if not eventsTicker then
      eventsTicker = C_Timer.NewTicker(2, function()
        if eventsView and eventsView:IsShown() and eventsRebuild then eventsRebuild() end
      end)
    end
  -- (docs/UX_PRAGMATIC.md 0.5, 1.3: Home > Activity is removed. The tab is not shown and no link opens it; the page
  -- is kept only until its code is deleted with the Activity work, behind ns.ACTIVITY_TAB for its own tests.)
  end, "Everything you did, newest first: quests, kills, loot, travel and town visits.", function() return ns.ACTIVITY_TAB == true end)
  ns._test = ns._test or {}; ns._test.eventMatches, ns._test.fmtWhere = eventMatches, fmtWhere
  ns._test.safeStr, ns._test.plainNum = safeStr, plainNum

  -- ── Loot > Items (docs/UX_PRAGMATIC.md 4.1; the design system is docs/UX_OVERHAUL.md 2): what dropped, from whom,
  --    where. Every item the character looted, newest first under day rows, or one row per item. The section header
  --    says once where the list starts and how many rows it shows; there is no line above it. Coin is not listed
  --    here (Loot > Gold, #38), nor are auction and mail rows (purchases and deliveries: Gold > Auction house).
  --    Built from the kit; all state on one table (no new upvalues here).
  local fmtMoney = ns.fmtMoney   -- the one formatter (UI.lua)
  ns._test = ns._test or {}; ns._test.fmtMoney = fmtMoney
  local lootRebuild
  ns.UI.registerHost(3, "Loot", "What you picked up, and where every copper came from and went.")
  ns.UI.registerPane("Loot", 1, "Items", function(content)
    local UI, C = ns.UI, ns.UI.C
    local S, G, H = UI.S, UI.G, UI.H
    local IT = { Q_RANK = { ff9d9d9d = 0, ffffffff = 1, ff1eff00 = 2, ff0070dd = 3, ffa335ee = 4, ffff8000 = 5, ffe6cc80 = 6 },
      QUALITY = { { "all", "Everything", 0 }, { "white", "White and better", 1 }, { "green", "Green and better", 2 },
        { "blue", "Blue and better", 3 }, { "purple", "Purple and better", 4 } },
      -- the words the capture stored when it had no name (never shown): an enemy whose name the client hid, and
      -- nothing recorded at all
      ENEMY = { ["Creature"] = true, ["an enemy"] = true }, NONE = { ["Picked up"] = true, ["Unknown source"] = true },
      -- rows that reached the bags with no loot window. Before 0.9.52 such a row took the place of the last loot
      -- window, which can be another zone, so its place is not shown; from 0.9.52 the row is marked `pushed` and
      -- stamped where it was picked up.
      PUSHED = { ["Picked up"] = true, ["an enemy"] = true, ["Quest reward"] = true },
      -- what a loot window stores for a source with no unit: shown as stored, they name no one
      LABEL = { ["Herb node"] = true, ["Mining node"] = true, ["Fishing spot"] = true, ["Skinned creature"] = true, ["Object"] = true },
      KILL_S = 20,    -- a kill this long before a pickup gave the row its name (capture: 15 s, plus the two clocks)
      STAMP_S = 15,   -- a loot window's stamp is its rows' own for this long (capture: the window counts 15 s)
      PARTIAL_TIP = { title = "Not every item is kept", text = "The list holds the items still stored in the game. The items of play sessions the desktop app has already saved are no longer stored here." },
      st = { sortKey = "time", sortAsc = false } }
    local st = IT.st
    local function cfg() return (ns.DB and ns.DB.settings) or {} end
    local function qualityOf(key) for _, q in ipairs(IT.QUALITY) do if q[1] == key then return q end end return IT.QUALITY[3] end
    st.quality = qualityOf(cfg().itemsQuality)[1]
    st.mode = cfg().itemsMode == "byitem" and "byitem" or "newest"
    st.minQ = qualityOf(st.quality)[3]
    function IT.rank(e) return IT.Q_RANK[(e.q or ""):lower()] or 1 end
    function IT.rgb(q)
      q = type(q) == "string" and q or ""
      if #q < 8 then return 0.8, 0.8, 0.8 end
      return (tonumber(q:sub(3, 4), 16) or 200) / 255, (tonumber(q:sub(5, 6), 16) or 200) / 255, (tonumber(q:sub(7, 8), 16) or 200) / 255
    end
    -- the name a row shows: link brackets stripped, never a placeholder
    function IT.name(e)
      local n = e.item
      if ns.Now and ns.Now.stripLink then n = ns.Now.stripLink(n) end
      n = tostring(n or ""):gsub("^%[(.*)%]$", "%1")
      if n == "" then return nil end
      return n
    end
    -- The kills of a session record, name -> their times: the KILL rows of its segments (every kill the addon named
    -- wrote one). Nil when the record is gone or full, and then nothing can be said about a name.
    function IT.killsOf(sid)
      local sess = sid and ns.DB and ns.DB.sessions and ns.DB.sessions[sid]
      local segs = type(sess) == "table" and sess.segments or nil
      if type(segs) ~= "table" or #segs >= 5000 then return nil end
      IT.kills = IT.kills or {}
      local c = IT.kills[sid]
      if c and c.n == #segs then return c.by end
      local by = {}
      for _, g in ipairs(segs) do
        if type(g) == "string" then
          local t, name = g:match("^%d+\t(%d+)\t[^\t]*\tKILL\t(.*)$")
          if t then by[name] = by[name] or {}; by[name][#by[name] + 1] = tonumber(t) end
        end
      end
      IT.kills[sid] = { n = #segs, by = by }
      return by
    end
    -- How a row got the name in its source (docs/UX_PRAGMATIC.md 0.2.1: a name by timing is not shown):
    --   "window"  the loot window named it: a row written from 0.9.52 that is not `pushed`, or an older row that
    --             carries the window's loot GUID
    --   "object"  the world object opened just before (from 0.9.52 `srcBy`; before it, a name with no kill behind it)
    --   "kill"    the last kill before the pickup, a guess by timing (from 0.9.52 `srcBy`; before it, the session
    --             record has a kill of that name in the IT.KILL_S seconds before the row)
    --   nil       not known: the session record that would tell is gone
    function IT.namedBy(e, name)
      if e.pushed then return e.srcBy == "object" and "object" or "kill" end
      if e.map then return "window" end
      if type(e.guid) == "string" and e.guid ~= "" then return "window" end
      local kills = IT.killsOf(e.s)
      if not kills then return nil end
      local t = tonumber(e.t) or 0
      for _, kt in ipairs(kills[name] or {}) do if kt <= t + 1 and t - kt <= IT.KILL_S then return "kill" end end
      return "object"
    end
    -- Where it came from, and what the hover says when the cell is short of a name:
    --   a source the loot window or an opened object named, as stored (the legacy " at (x, y)" split off),
    --   "Quest: <name>", "Container" (an opened bag item: the stored loot GUID starts with Item-), "Enemy" with the
    --   tip "Name not recorded" (the client hid the name, or the stored name is only the last kill before the
    --   pickup), and nothing at all, tip "Not recorded", for a row with no recorded source.
    -- Returns text or nil, tip or nil, the legacy coordinates.
    function IT.from(e)
      local srcName, legacy = (e.src or ""):match("^(.-) at (%(.-%))$")
      srcName = srcName or e.src
      if srcName == "Quest reward" then
        local qn = IT.questNames and IT.questNames[e]
        return qn and ("Quest: " .. qn) or "Quest", (not qn) and "Quest not recorded" or nil, legacy
      end
      if srcName == "Container" or (srcName == "Unknown source" and type(e.guid) == "string" and e.guid:sub(1, 5) == "Item-") then return "Container", nil, legacy end
      if IT.ENEMY[srcName] then return "Enemy", "Name not recorded", legacy end
      if srcName == nil or srcName == "" or IT.NONE[srcName] then return nil, "Not recorded", legacy end
      if IT.LABEL[srcName] then return srcName, nil, legacy end
      local by = IT.namedBy(e, srcName)
      if by == "kill" then return "Enemy", "Name not recorded", legacy end
      if by == nil then return nil, "Not recorded", legacy end
      return srcName, nil, legacy
    end
    -- Whether the stored place is where this row was picked up. From 0.9.52 every row is stamped as the item arrives
    -- (`map`, `pushed`). Before, a row carried the stamp of the last loot window, however old, so it counts only
    -- when the window was this row's own: the row has the window's loot GUID, or it is within IT.STAMP_S seconds of
    -- the first row of its session with that exact stamp. A row that reached the bags with no loot window (no
    -- source, a quest reward, a name by the last kill or by an opened object) never had its own.
    function IT.stampKey(e) return tostring(e.s) .. "|" .. tostring(e.zone) .. "|" .. tostring(e.x) .. "|" .. tostring(e.y) end
    function IT.readStamps(loot)
      local first = {}
      for _, e in ipairs(loot) do
        local t = tonumber(e.t)
        if t and e.zone and not (e.pushed or e.map) then
          local k = IT.stampKey(e)
          if not first[k] or t < first[k] then first[k] = t end
        end
      end
      IT.firstAt = first
    end
    function IT.own(e)
      if e.pushed or e.map then return true end
      local src = (e.src or ""):match("^(.-) at %(.-%)$") or e.src or ""
      if IT.PUSHED[src] then return false end
      if type(e.guid) == "string" and e.guid ~= "" then return true end
      if src ~= "" and not (IT.LABEL[src] or IT.ENEMY[src] or IT.NONE[src] or src == "Container") and IT.namedBy(e, src) ~= nil then return false end
      local first, t = IT.firstAt and IT.firstAt[IT.stampKey(e)], tonumber(e.t)
      return first ~= nil and t ~= nil and t >= first and t - first <= IT.STAMP_S
    end
    -- the zone stamped with the row; nil for a row whose stored place is not its own (IT.own)
    function IT.place(e)
      if e.agg or not e.zone then return nil end
      if not IT.own(e) then return nil end
      return e.zone
    end
    -- the coordinates of a row that shows its place, as text; nil when it has none
    function IT.coords(e)
      if IT.place(e) == nil then return nil end
      if e.x and e.y then return UI.fmtCoords(e.x, e.y) end
      local legacy = (e.src or ""):match("^.- at (%(.-%))$")
      return legacy and (legacy:gsub("[()]", "")) or nil
    end
    -- an auction or mail row: a purchase or a delivery, not loot
    function IT.notLoot(e)
      local src = e.src or ""
      return e.mail ~= nil or src:sub(1, 8) == "Auction " or src == "Mail" or src:sub(1, 10) == "Mail from "
    end
    -- the Items list never shows coin, an auction row or a mail row
    function IT.matches(e, q)
      if e.money or IT.notLoot(e) then return false end
      if st.minQ > 0 and IT.rank(e) < st.minQ then return false end
      if not q or q == "" then return true end
      local hay = ((IT.name(e) or "") .. " " .. (IT.from(e) or "") .. " " .. (IT.place(e) or "")):lower()
      return hay:find(q:lower(), 1, true) ~= nil
    end
    ns._test.lootMatches = function(e, q) local m = st.minQ; st.minQ = 0; local r = IT.matches(e, q); st.minQ = m; return r end
    -- By item: one row per item, how many in all and when it was last looted
    function IT.aggregate(loot, q, matches)
      local by, order = {}, {}
      for _, e in ipairs(loot) do
        if not e.money and e.item and matches(e, q) then
          local a = by[e.item]
          if not a then
            a = { item = e.item, count = 0, drops = 0, q = e.q, icon = e.icon, id = e.id, quest = e.quest, t = e.t, first = e.t, agg = true }
            by[e.item] = a; order[#order + 1] = a
          end
          a.count = a.count + (tonumber(e.count) or 1); a.drops = a.drops + 1
          if (e.t or 0) > (a.t or 0) then a.t = e.t end
          if (e.t or 0) < (a.first or math.huge) then a.first = e.t end
        end
      end
      table.sort(order, function(a, b) if a.count ~= b.count then return a.count > b.count end return (a.t or 0) > (b.t or 0) end)
      return order
    end
    ns._test.lootAggregate = IT.aggregate
    ns._test.lootContent = function() return content end
    ns._test.lootFrom, ns._test.lootPlace = function(e) return IT.from(e) end, function(e) return IT.place(e) end
    ns._test.lootCoords, ns._test.lootIT = function(e) return IT.coords(e) end, IT
    local SORT = {
      time = function(e) return e.t or 0 end, last = function(e) return e.t or 0 end,
      item = function(e) return (IT.name(e) or ""):lower() end, from = function(e) return (IT.from(e) or ""):lower() end,
      loc = function(e) return (IT.place(e) or ""):lower() end,
      qty = function(e) return tonumber(e.count) or 1 end,
      quality = function(e) return IT.rank(e) end,
    }
    function IT.sortRows(rows, key, asc)
      key, asc = key or st.sortKey, (asc == nil) and st.sortAsc or asc
      -- (newest first is sorted too, stable on the log's order: a row written late with an earlier time, as a
      -- merged or imported one, still lands under its own day)
      local f = SORT[key] or SORT.time
      local order = {}
      for i, e in ipairs(rows) do order[e] = i end
      table.sort(rows, function(a, b)
        local va, vb = f(a), f(b)
        if va == vb then return order[a] < order[b] end
        if asc then return va < vb else return va > vb end
      end)
      return rows
    end
    ns._test.lootSort = function(rows, key, asc) return IT.sortRows(rows, key, asc) end

    -- the page: one scroll holding the section header and the list
    local v = CreateFrame("Frame", nil, content); v:SetAllPoints(content)
    local sf, child = UI.ScrollChild(v, { slim = true, top = 0, left = 0, right = 0, bottom = 0 })
    local col = CreateFrame("Frame", nil, child); col:SetPoint("TOPLEFT", child, "TOPLEFT", 0, 0); col:SetSize(1, 1)
    -- one list-page structure on Runs and Items: the section header says where the list starts, its meta the count
    IT.section = UI.Section(col, "Items")
    content.lootSection = IT.section
    -- the control row, right to left: search, quality filter, List · By item
    local controls = content.ebControls or v
    local search = UI.Search(controls, "Search loot")   -- (fits the one search width, 176 - 26)
    search:SetPoint("TOPRIGHT", controls, "TOPRIGHT", 0, 0)
    search:HookScript("OnTextChanged", function() if lootRebuild then lootRebuild() end end)
    content.search = search
    local qf = UI.FilterButton(controls, { default = "green", label = "Green and better",
      items = function()
        local out = {}
        for _, q in ipairs(IT.QUALITY) do out[#out + 1] = { q[1], q[2], st.quality == q[1] } end
        return out
      end,
      onPick = function(key) IT.setQuality(key) end })
    qf:SetPoint("TOPRIGHT", search, "TOPLEFT", -S.S2, 0)
    content.lootQuality = qf
    local seg = UI.Segmented(controls, { { "newest", "List", "Every item, newest first" }, { "byitem", "By item", "One row per item: how many in all" } },
      { value = st.mode, onPick = function(key) IT.setMode(key) end })
    seg:SetPoint("TOPRIGHT", qf, "TOPLEFT", -S.S2, 0)
    content.lootModeControl = seg
    function IT.setQuality(key)
      local q = qualityOf(key)
      st.quality, st.minQ = q[1], q[3]
      if ns.DB and ns.DB.settings then ns.DB.settings.itemsQuality = q[1] end
      qf:SetValue(q[1], q[2])
      if lootRebuild then lootRebuild() end
    end
    function IT.setMode(key)
      st.mode = key == "byitem" and "byitem" or "newest"
      if ns.DB and ns.DB.settings then ns.DB.settings.itemsMode = st.mode end
      seg:SetValue(st.mode)
      st.sortKey, st.sortAsc = st.mode == "byitem" and "qty" or "time", false
      for _, t in pairs(IT.tbls) do t.setSort(st.sortKey, st.sortAsc) end
      if lootRebuild then lootRebuild() end
    end
    content.lootMode = function() return st.mode end
    content.lootFilter = function() return st.minQ, st.sortKey, st.sortAsc end
    content.setLootQuality, content.setLootMode = function(k) IT.setQuality(k) end, function(k) IT.setMode(k) end

    -- two tables, one per mode. The badge after a quest item's name is a neutral QUEST badge.
    local spec = {
      newest = {
        { key = "time", label = "When", kind = "tag", min = 40, measure = { "00:00" }, sort = true },
        { key = "icon", label = "", kind = "icon" },
        { key = "item", label = "Item", flex = 1, min = 120, sort = true },
        { key = "from", label = "From", min = 160, max = 240, sort = true },
        { key = "loc", label = "Place", min = 120, sort = true },
        { key = "coords", label = "Coords", kind = "num", min = 72, wide = true },
      },
      byitem = {
        { key = "icon", label = "", kind = "icon" },
        { key = "item", label = "Item", flex = 1, min = 120, sort = true },
        { key = "qty", label = "Count", kind = "num", min = 56, sort = true, tip = "How many you looted in all" },
        { key = "last", label = "Last looted", kind = "tag", min = 96, sort = true },
      },
    }
    IT.spec = { from = spec.newest[4], loc = spec.newest[5], coords = spec.newest[6] }
    IT.tbls = {}
    -- the name, then its stack count ("x4", fgMuted, a text of its own) S1 after it, then the QUEST badge: the name
    -- shortens inside what is left of the column, the count and the badge never do
    local function placeBadge(tbl, row)
      local cw, fs, b, ct = tbl.cols and tbl.cols.item, row.c and row.c.item, row.ebBadge, row.ebCount
      if not (cw and fs) then return end
      local live = row.item and not row.item.ebSection
      local cntW = (ct and ct:IsShown() and live) and (UI.TextWidth("BODY", ct:GetText()) + S.S1) or 0
      local bw = (b and b:IsShown() and live) and ((tonumber(b:GetWidth()) or 0) + S.S2) or 0
      if not live and b then b:Hide() end
      local tw = math.max(1, math.min(UI.TextWidth("BODY", fs:GetText()), cw.w - cntW - bw))
      fs:SetWidth((cntW > 0 or bw > 0) and tw or cw.w)
      if cntW > 0 then ct:ClearAllPoints(); ct:SetPoint("LEFT", row, "LEFT", cw.x + tw + S.S1, 0); ct:SetWidth(cntW - S.S1) end
      if bw > 0 then b:ClearAllPoints(); b:SetPoint("LEFT", row, "LEFT", cw.x + tw + cntW + S.S2, 0) end
    end
    IT.placeBadge = placeBadge
    for mode, sp in pairs(spec) do
      IT.tbls[mode] = UI.KitTable(col, sp, {
        sortKey = mode == "byitem" and "qty" or "time", sortAsc = false,
        onSort = function(key, asc) st.sortKey, st.sortAsc = key, asc; if lootRebuild then lootRebuild() end end,
        onLayout = function(t) for i = 1, t.shownN do pcall(placeBadge, t, t.rows[i]) end end,
        onHeight = function() if IT.place2 then pcall(IT.place2) end end,
        tooltip = function(row, e, tip)
          if not e or e.ebSection then return end
          if row.itemId and tip.SetHyperlink then tip:SetHyperlink("item:" .. tostring(row.itemId))
          else tip:AddLine(IT.name(e) or "Item", IT.rgb(e.q)) end
          if e.agg then tip:AddLine(("Looted %s, %s in all"):format(UI.plural(e.drops, "time"), UI.fmtNum(e.count)), 0.78, 0.79, 0.80)
          elseif e.t then
            tip:AddLine(UI.fmtWhen(e.t), 0.78, 0.79, 0.80)
            -- (what a short or blank cell stands for; the reason is never on the screen itself)
            local from, why = IT.from(e)
            if why then tip:AddLine((from == "Enemy" and "Enemy: " or from == "Quest" and "" or "From: ") .. why, 0.78, 0.79, 0.80) end
            local place, xy = IT.place(e), IT.coords(e)
            if place then tip:AddLine("Place: " .. place .. (xy and ("  " .. xy) or ""), 0.78, 0.79, 0.80) else tip:AddLine("Place: Not recorded", 0.78, 0.79, 0.80) end
          end
        end })
    end
    content.lootTables = IT.tbls
    -- a row opens nothing; shift-click puts the item's link in the chat box
    function IT.shiftClick(row)
      if row.itemId and IsShiftKeyDown and IsShiftKeyDown() and GetItemInfo and ChatEdit_InsertLink then
        local _, link = GetItemInfo(row.itemId); if link then ChatEdit_InsertLink(link) end
      end
    end
    function IT.fill(row, e)
      local c = row.c
      row.itemId = tonumber(e.id)
      if not row.ebShift then row.ebShift = true; row:SetScript("OnClick", IT.shiftClick) end
      if c.time then c.time:SetText(UI.fmtClock(e.t or 0)) end
      c.icon:SetTexture(e.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
      local name = IT.name(e)
      local n = tonumber(e.count) or 1
      if not row.ebCount then row.ebCount = UI.Text(row, "BODY", "fgMuted") end
      if name and not e.agg and n > 1 then row.ebCount:SetText("x" .. n); row.ebCount:Show() else row.ebCount:Hide() end
      if name then
        c.item:SetText(name)
        c.item:SetTextColor(IT.rgb(e.q))
      else
        c.item:SetText("Item " .. tostring(e.id or "")); UI.SetColor(c.item, "fgMuted")
      end
      if e.quest then
        if not row.ebBadge then row.ebBadge = UI.Badge(row, "Quest") end
        row.ebBadge:Show()
      elseif row.ebBadge then row.ebBadge:Hide() end
      if c.from then c.from:SetText(IT.from(e) or "") end
      if c.loc then c.loc:SetText(IT.place(e) or "") end
      -- (coordinates only beside their place: never for a row whose place is blank, never with the Place column hidden)
      if c.coords then c.coords:SetText(c.loc and IT.coords(e) or "") end
      if c.qty then c.qty:SetText(UI.fmtNum(e.count or 1)) end
      if c.last then c.last:SetText(UI.fmtDate(e.t or 0)) end
    end
    IT.place2 = function()
      local w = G.mainW(G.winW())
      col:SetWidth(w)
      local y = 0
      IT.section:ClearAllPoints(); IT.section:SetPoint("TOPLEFT", col, "TOPLEFT", 0, -y); IT.section:SetWidth(w); y = y + H.SECTION
      local t = IT.tbls[st.mode]
      t.frame:ClearAllPoints(); t.frame:SetPoint("TOPLEFT", col, "TOPLEFT", 0, -y); t.frame:SetWidth(w)
      if t.width ~= math.min(w, G.TABLE_MAX) then t.relayout(w) end
      y = y + (t.height or 0) + S.S4
      col:SetHeight(y); sf:SetContentHeight(y)
      IT.contentH = y
    end
    content:HookScript("OnSizeChanged", function() pcall(IT.place2) end)
    -- the quest a quest reward belongs to: the QUESTDONE row of the same turn-in (kept beside the rows, never saved)
    function IT.readQuests(loot)
      IT.questNames = setmetatable({}, { __mode = "k" })
      local done = {}
      for _, ev in ipairs((ns.DB and ns.DB.story and ns.DB.story.events) or {}) do
        if ev.kind == "QUESTDONE" and type(ev.text) == "string" then done[#done + 1] = ev end
      end
      for _, e in ipairs(loot) do
        if not e.money and e.src == "Quest reward" then
          -- (named only when one turn-in of the session lies within 5 s: with two, which one gave this item is
          -- not stored, and the cell reads "Quest")
          local hit, n = nil, 0
          for _, ev in ipairs(done) do
            if ev.s == e.s and math.abs((ev.t or 0) - (e.t or 0)) <= 5 then hit = ev; n = n + 1 end
          end
          if n == 1 then IT.questNames[e] = hit.text:match("^Complete:%s+(.+)$") end
        end
      end
    end
    -- Whether the list has a hole after its start: a dungeon run of the character whose stored item count is larger
    -- than the loot rows the save still holds for its span (the rows of a session the desktop app picked up are
    -- deleted, the run's own counters stay).
    function IT.partial(loot, since)
      local c = ns.DB and ns.charGuid and ns.charGuid() and ns.char and ns.char() or nil
      if not (c and since and type(c.goldRuns) == "table") then return false end
      for _, r in ipairs(c.goldRuns) do
        local t0, n = tonumber(r.t), tonumber(r.items)
        if t0 and n and n > 0 and t0 >= since then
          local t1, have = t0 + (tonumber(r.secs) or 0) + 60, 0
          for _, e in ipairs(loot) do
            if e.item and not e.money and tonumber(e.t) and e.t >= t0 and e.t <= t1 then have = have + 1 end
          end
          if have < n then return true end
        end
      end
      return false
    end
    -- The section header: where the list starts (the oldest item the save still holds for this character, at any
    -- quality) and what the filter shows, counted as what it is: pickups in the list ("89 pickups green or better":
    -- one row is one pickup, of one item or a stack), items in By item ("74 items green or better": one row is one
    -- item). The one muted remark, when the list has a hole after its start: ", not every item is kept".
    function IT.head(loot, n, q)
      local first
      for _, e in ipairs(loot) do
        if e.item and not e.money and not IT.notLoot(e) and tonumber(e.t) and (not first or e.t < first) then first = e.t end
      end
      IT.since = first
      IT.section:SetLabel(first and ("Items since " .. UI.fmtSince(first)) or "Items")
      local meta
      IT.isPartial = IT.partial(loot, first)
      local remark = IT.isPartial and q == ""
      if n > 0 then
        meta = UI.plural(n, st.mode == "byitem" and "item" or "pickup")
        if not (q ~= "" or st.quality == "all") then meta = meta .. " " .. (qualityOf(st.quality)[2]:lower():gsub(" and better", " or better")) end
        if remark then meta = meta .. ", not every item is kept" end
      end
      IT.section:SetMeta(meta, (meta and remark) and IT.PARTIAL_TIP or nil)
    end
    lootRebuild = function()
      local loot = ns.mine(ns.DB and ns.DB.loot.log)   -- persisted; the logged-in character's rows only (#23)
      IT.readQuests(loot)
      IT.readStamps(loot)
      local q = search:GetText() or ""
      local rows, list
      if st.mode == "byitem" then rows = IT.sortRows(IT.aggregate(loot, q, IT.matches), st.sortKey, st.sortAsc); list = rows
      else
        list = {}
        for i = #loot, 1, -1 do if loot[i].item and IT.matches(loot[i], q) then list[#list + 1] = loot[i] end end
        list = IT.sortRows(list, st.sortKey, st.sortAsc)
        if st.sortKey == "time" and not st.sortAsc then
          -- newest first: a day row over each day
          rows = {}
          local last
          for _, e in ipairs(list) do
            local k = date("%Y-%m-%d", e.t or 0)
            if k ~= last then last = k; rows[#rows + 1] = { ebSection = UI.fmtDay(e.t or 0) } end
            rows[#rows + 1] = e
          end
        else rows = list end
        -- From and Place show only while a third of the rows have a value; Place also hides when it is the same on
        -- every row (docs/UX_PRAGMATIC.md 0.3). What a hidden column held stays in the row's tooltip.
        local nFrom, nLoc, nXY, same, firstLoc = 0, 0, 0, true, nil
        for _, e in ipairs(list) do
          if IT.from(e) then nFrom = nFrom + 1 end
          if IT.coords(e) then nXY = nXY + 1 end
          local p = IT.place(e)
          if p then nLoc = nLoc + 1; firstLoc = firstLoc or p; if p ~= firstLoc then same = false end else same = false end
        end
        local hideFrom = #list > 0 and (nFrom == 0 or nFrom * 3 < #list)
        local hideLoc = #list > 0 and (nLoc == 0 or nLoc * 3 < #list or (same and #list > 1))
        -- (Coords stand beside their Place: hidden with it, and by the same third)
        local hideXY = hideLoc or (#list > 0 and (nXY == 0 or nXY * 3 < #list))
        local changed = false
        if (IT.spec.from.hide or false) ~= hideFrom then IT.spec.from.hide = hideFrom; changed = true end
        if (IT.spec.loc.hide or false) ~= hideLoc then IT.spec.loc.hide = hideLoc; changed = true end
        if (IT.spec.coords.hide or false) ~= hideXY then IT.spec.coords.hide = hideXY; changed = true end
        IT.colHidden = { from = hideFrom, loc = hideLoc, coords = hideXY }
        if changed then IT.tbls.newest.relayout(G.mainW(G.winW())) end
      end
      for mode, t in pairs(IT.tbls) do if mode == st.mode then t.frame:Show() else t.frame:Hide() end end
      local tbl = IT.tbls[st.mode]
      tbl.setSort(st.sortKey, st.sortAsc)
      tbl.setRows(rows, IT.fill)
      for i = 1, tbl.shownN do pcall(IT.placeBadge, tbl, tbl.rows[i]) end
      -- (the header counts the rows the mode shows: pickups in the list, items in By item)
      IT.nShown = #list
      IT.head(loot, IT.nShown, q)
      if #rows == 0 then
        if q ~= "" then tbl.setState(('No item matches "%s". '):format(q), "Clear search", function() search:SetText("") end)
        elseif IT.since then tbl.setState("No item matches this filter.")
        else tbl.setState("No item stored yet.") end
      end
      content.lootRows = tbl.rows
      content.lootCols = IT.colHidden
      IT.place2()
    end
    qf:SetValue(st.quality, qualityOf(st.quality)[2])
    for _, t in pairs(IT.tbls) do t.setSort(st.mode == "byitem" and "qty" or "time", false) end
    st.sortKey = st.mode == "byitem" and "qty" or "time"
    lootRebuild()
  end, function() if lootRebuild then lootRebuild() end end, "What dropped, from whom and where.")
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
-- what a fresh load starts with (#31)
ns._test.newLoad = function()
  pcall(Emitter.repairResolve)   -- a spend still waiting for its repair cost keeps its row
  lastMoney = nil
  Emitter._zero, Emitter._zeroSeed, Emitter._guidWait, Emitter._sig = nil, nil, nil, nil
  Emitter._repair, Emitter._mailQ, Emitter._coin, Emitter._lastLoot, Emitter._respec = {}, {}, nil, nil, nil
  Emitter._openGain, Emitter._sold, Emitter._crashed, Emitter._crashAsk, Emitter._reloading, Emitter._awayWait = nil, nil, nil, nil, nil, nil
  Emitter._pend, Emitter._ah = { sell = {}, buy = {}, back = {} }, { claims = {} }
  if ns.Gold then ns.Gold._seenRead, ns.Gold._seenBefore = nil, nil end
  Emitter._det = nil
  if ns.Runs and ns.Runs.newLoad then ns.Runs.newLoad() end
end
ns._test.CREATE_PAT, ns._test.SKILLUP_PAT = CREATE_PAT, SKILLUP_PAT
ns._test.DISCOVER_XP_PAT, ns._test.DISCOVER_PAT = DISCOVER_XP_PAT, DISCOVER_PAT
