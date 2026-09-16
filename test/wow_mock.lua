-- wow_mock.lua — a minimal mock of the WoW addon API so Everbuff's Lua can run under LuaJIT.
--
-- Goal: load the real addon files, catch runtime errors, and drive logic (recording, SR parsing,
-- rolls, readiness, roster) without the game. Widgets are inert; we only track what matters for
-- verification (fontstring text, chat announcements, prints, registered events).

local M = { chat = {}, prints = {}, fontstrings = {}, eventFrames = {}, afters = {},
            tickers = {}, errors = {}, raidWarnings = {} }
_G._WOWMOCK = M

-- ── widgets ───────────────────────────────────────────────────────────────────
local Widget = {}
Widget.stateful = {}
local S = Widget.stateful

function S.CreateFontString(self, name, layer, template)
  local fs = M.makeWidget("FontString", name)
  fs.__template = template
  table.insert(self.__children, fs)
  table.insert(M.fontstrings, fs)
  return fs
end
function S.CreateTexture(self, name) local t = M.makeWidget("Texture", name); table.insert(self.__children, t); return t end
function S.SetText(self, t) self.__text = t end
function S.GetText(self) return self.__text or "" end
function S.SetChecked(self, b) self.__checked = b and true or false end
function S.GetChecked(self) return self.__checked end
function S.Show(self) self.__shown = true end
function S.Hide(self) self.__shown = false end
function S.SetShown(self, b) self.__shown = b and true or false end
function S.IsShown(self) return self.__shown ~= false end
function S.GetObjectType(self) return self.__kind end
function S.GetName(self) return self.__name end
function S.SetScrollChild(self, c) self.__scrollchild = c end
function S.SetScript(self, name, fn) self.__scripts[name] = fn end
function S.HookScript(self, name, fn) self.__scripts[name] = fn end
function S.GetScript(self, name) return self.__scripts[name] end
function S.RegisterForDrag() end
function S.RegisterEvent(self, ev)
  M.eventFrames[ev] = M.eventFrames[ev] or {}
  table.insert(M.eventFrames[ev], self)
end
function S.UnregisterEvent() end
function S.SetEnabled(self, b) self.__enabled = b end

Widget.mt = {
  __index = function(self, key)
    local m = S[key]
    if m then return m end
    -- everything else (SetSize/SetPoint/SetBackdrop/…) is an inert no-op
    return function() end
  end,
}

function M.makeWidget(kind, name)
  local w = setmetatable({ __kind = kind, __name = name, __children = {}, __scripts = {},
                           __shown = true }, Widget.mt)
  if name then _G[name] = w end
  return w
end

function CreateFrame(kind, name, parent, template)
  return M.makeWidget(kind or "Frame", name)
end

-- ── event + timer control ─────────────────────────────────────────────────────
function M.fireEvent(event, ...)
  for _, f in ipairs(M.eventFrames[event] or {}) do
    local h = f.__scripts.OnEvent
    if h then h(f, event, ...) end
  end
end
function M.flushAfters()
  local list = M.afters; M.afters = {}
  for _, fn in ipairs(list) do pcall(fn) end
end

C_Timer = {
  After = function(_, fn) table.insert(M.afters, fn) end,
  NewTicker = function(_, fn) local t = { fn = fn, Cancel = function() end }; table.insert(M.tickers, t); return t end,
  NewTimer = function() return { Cancel = function() end } end,
}
-- run every registered ticker's callback once (drives the logging guardian in tests)
function M.tick() for _, t in ipairs(M.tickers) do if t.fn then pcall(t.fn) end end end

-- ── world / group state (settable by the harness) ─────────────────────────────
function M.worldDefaults()
  return { inInstance = false, instanceType = "none",
    instance = { "", "none", 0, "", 0, 0, false, 0 }, zone = "Elwynn Forest",
    acl = "0", combat = false, aclLocked = false, level = 1, raid = false, auras = {},
    units = { player = { name = "Hart", realm = "Kazzak", class = "Paladin", classFile = "PALADIN", role = "TANK" } } }
end
M.world = M.worldDefaults()

function IsInInstance() return M.world.inInstance, M.world.instanceType end
function GetInstanceInfo() return unpack(M.world.instance) end
function GetRealZoneText() return M.world.zone end
function IsInRaid() return M.world.raid end
function IsInGroup() return #M.orderedUnits() > 0 end

function M.orderedUnits()
  local out = {}
  for _, u in ipairs({ "player", "party1", "party2", "party3", "party4",
    "raid1","raid2","raid3","raid4","raid5","raid6","raid7","raid8","raid9","raid10" }) do
    if M.world.units[u] then out[#out + 1] = u end
  end
  return out
end
function GetNumGroupMembers()
  local n = 0
  for _ in pairs(M.world.units) do n = n + 1 end
  return n
end
function UnitExists(u) return M.world.units[u] ~= nil end
function UnitName(u) local d = M.world.units[u]; if d then return d.name, d.realm end end
function UnitNameUnmodified(u) return UnitName(u) end
function UnitClass(u) local d = M.world.units[u]; if d then return d.class, d.classFile end end
function UnitGroupRolesAssigned(u) local d = M.world.units[u]; return d and d.role or "NONE" end
function UnitIsConnected() return true end
function UnitLevel() return M.world.level or 1 end
function GetRealmName() return "Kazzak" end
function GetGuildInfo() return "Test Guild" end
function GetRaidRosterInfo(i)
  local u = "raid" .. i
  local d = M.world.units[u]
  if not d then return end
  -- name, rank, subgroup, level, class, fileName, zone, online, isDead, role, isML, combatRole
  return (d.name .. "-" .. (d.realm or "Kazzak")), 0, d.subgroup or 1, 80, d.class, d.classFile,
    "", true, false, nil, nil, d.role
end

-- ── logging cvars ─────────────────────────────────────────────────────────────
function GetCVar(k) if k == "advancedCombatLogging" then return M.world.acl end return "" end
function SetCVar(k, v)
  if k == "advancedCombatLogging" then
    if M.world.aclLocked then return true end -- simulate a client that refuses the cvar write
    M.world.acl = tostring(v)
  end
  return true
end
function LoggingCombat(arg)
  if arg ~= nil then M.world.combat = arg and true or false; return end
  return M.world.combat
end

-- anti-tamper hooks: hooksecurefunc wraps a global so `fn` runs after each call (as in WoW).
M._baseSetCVar = SetCVar
M._baseLoggingCombat = LoggingCombat
function hooksecurefunc(name, fn)
  local orig = _G[name]
  _G[name] = function(...) local r = { orig(...) }; pcall(fn, ...); return unpack(r) end
end
function debugstack() return M.debugstack or "" end

-- ── auras (readiness) ─────────────────────────────────────────────────────────
AuraUtil = {
  ForEachAura = function(unit, filter, max, fn, packed)
    for _, a in ipairs(M.world.auras[unit] or {}) do fn(a) end
  end,
}

-- ── items / loot ──────────────────────────────────────────────────────────────
function GetItemInfo(link)
  local id = tostring(link):match("item:(%d+)") or "0"
  return "Item " .. id, link, 4, 600, 0, "", "", 1, "", "Interface\\Icons\\INV_Misc_QuestionMark", 0
end
M.cursor = nil
function GetCursorInfo() if M.cursor then return "item", nil, M.cursor end end
function ClearCursor() M.cursor = nil end

-- ── chat / output ─────────────────────────────────────────────────────────────
function SendChatMessage(msg, chan) table.insert(M.chat, { msg = msg, chan = chan }) end
local realprint = print
function print(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
  table.insert(M.prints, table.concat(parts, " "))
end
M.realprint = realprint

-- ── misc globals ──────────────────────────────────────────────────────────────
UIParent = M.makeWidget("Frame", "UIParent")
UISpecialFrames = {}
SlashCmdList = {}
WOW_PROJECT_MAINLINE = 1
WOW_PROJECT_CLASSIC = 2
WOW_PROJECT_MISTS_CLASSIC = 19
WOW_PROJECT_ID = WOW_PROJECT_MAINLINE

-- ── heavy-nag surface (so the logging guardian's complaints are observable) ────
UIErrorsFrame = M.makeWidget("Frame", "UIErrorsFrame")
function UIErrorsFrame.AddMessage(_, text) table.insert(M.errors, text) end
RaidWarningFrame = M.makeWidget("Frame", "RaidWarningFrame")
function RaidNotice_AddMessage(_, text) table.insert(M.raidWarnings, text) end
ChatTypeInfo = { RAID_WARNING = { r = 1, g = .28, b = 0 } }
function PlaySound() end
RAID_CLASS_COLORS = setmetatable({
  WARRIOR={r=.78,g=.61,b=.43}, PALADIN={r=.96,g=.55,b=.73}, HUNTER={r=.67,g=.83,b=.45},
  ROGUE={r=1,g=.96,b=.41}, PRIEST={r=1,g=1,b=1}, DEATHKNIGHT={r=.77,g=.12,b=.23},
  SHAMAN={r=0,g=.44,b=.87}, MAGE={r=.25,g=.78,b=.92}, WARLOCK={r=.53,g=.53,b=.93},
  MONK={r=0,g=1,b=.6}, DRUID={r=1,g=.49,b=.04}, DEMONHUNTER={r=.64,g=.19,b=.79},
  EVOKER={r=.2,g=.58,b=.5},
}, { __index = function() return { r=1, g=1, b=1 } end })

function GetBuildInfo() return "12.0.1", "60000", "Sep 13 2026", 120007 end
function GetServerTime() return os.time() end
function GetTime() return os.clock() end
date = os.date
time = os.time

C_ChallengeMode = {
  GetActiveChallengeMapID = function() return 999 end,
  GetActiveKeystoneInfo = function() return 10, { 1, 2, 3 } end,
}
C_PartyInfo = { InviteUnit = function() end }
function InviteUnit() end
C_DamageMeter = nil -- exercise the feature-detect guard

-- WoW global helpers
function strsplit(delim, s)
  local out = {}
  for part in tostring(s):gmatch("([^" .. delim .. "]+)") do out[#out + 1] = part end
  return unpack(out)
end
M.errhandler = function(err) M.realprint("LUA ERROR: " .. tostring(err)) end
function geterrorhandler() return M.errhandler end
function seterrorhandler(fn) M.errhandler = fn end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
tinsert = table.insert
tremove = table.remove

-- ── flavor + reset (lets the harness load the addon twice: mainline then Classic) ──
function M.setFlavor(flavor)
  if flavor == "vanilla" or flavor == "classic" then
    WOW_PROJECT_ID = WOW_PROJECT_CLASSIC
    C_ChallengeMode = nil -- no Mythic+ on Classic/SoD
    C_DamageMeter = nil   -- no Blizzard meter on Classic/SoD
  else
    WOW_PROJECT_ID = WOW_PROJECT_MAINLINE
    C_ChallengeMode = {
      GetActiveChallengeMapID = function() return 999 end,
      GetActiveKeystoneInfo = function() return 10, { 1, 2, 3 } end,
    }
    C_DamageMeter = nil -- keep nil to exercise the feature-detect guard on mainline too
  end
end

function M.reset()
  M.chat, M.prints, M.fontstrings, M.afters = {}, {}, {}, {}
  M.errors, M.raidWarnings, M.tickers, M.eventFrames = {}, {}, {}, {}
  M.world = M.worldDefaults()
  M.cursor = nil
  M.debugstack = nil
  SlashCmdList = {}
  UISpecialFrames = {}
  EverbuffDB = nil
  -- undo any hooksecurefunc wrapping from a previous load
  _G.SetCVar = M._baseSetCVar
  _G.LoggingCombat = M._baseLoggingCombat
end

return M
