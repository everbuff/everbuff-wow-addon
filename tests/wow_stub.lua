-- Minimal fake WoW API so the addon files load and run under plain luajit (no game).
-- Frames record their scripts + registered events, so tests can M.fire("EVENT", ...) into the REAL
-- handlers. Game state is driven through the M table (money, xp, units, instance, clock).
local M = { now = 1000, epoch = 1700000000, money = 0, xp = 0, xpmax = 1000, rested = nil,
            level = 12, zone = "Elwynn Forest", units = {}, auras = {}, gear = {},
            inst = { name = "Elwynn Forest", type = "none", diff = 0, mapID = 0 },
            groupN = 1, inCombat = false, timers = {}, tickers = {}, cvars = {}, logging = false }
local frames = {}
local noop = function() end
local frameMT = {}
local function mkframe()
  local f = setmetatable({ scripts = {}, events = {}, shown = true, attrs = {} }, frameMT)
  frames[#frames + 1] = f; return f
end
frameMT.__index = function(t, k)
  -- WoW methods are PascalCase; anything else is an ordinary data field, nil until the addon sets it
  if type(k) ~= "string" or not k:match("^%u") then return nil end
  if k == "SetScript" then return function(self, n, fn) self.scripts[n] = fn; if n == "OnSizeChanged" then M.watchSize(self) end; return self end end
  if k == "GetScript" then return function(self, n) return self.scripts[n] end end
  if k == "HookScript" then return function(self, n, fn) local p = self.scripts[n]; self.scripts[n] = function(...) if p then p(...) end fn(...) end; if n == "OnSizeChanged" then M.watchSize(self) end; return self end end
  -- M.unknownEvents[ev]: an event this client does not have; registering it throws, as the real client does
  if k == "RegisterEvent" then return function(self, ev)
    if M.unknownEvents and M.unknownEvents[ev] then error(("Frame:RegisterEvent(): Attempt to register unknown event \"%s\""):format(tostring(ev)), 2) end
    self.events[ev] = true; return self end end
  if k == "IsEventRegistered" then return function(self, ev) return self.events[ev] == true end end
  if k == "UnregisterEvent" then return function(self, ev) self.events[ev] = nil; return self end end
  if k == "Show" then return function(self) self.shown = true; local h = self.scripts.OnShow; if h then h(self) end; return self end end
  if k == "Hide" then return function(self) self.shown = false; local h = self.scripts.OnHide; if h then h(self) end; return self end end
  if k == "IsShown" then return function(self) return self.shown end end
  -- on screen: the frame's own flag and every parent's (IsShown is the frame's own flag alone)
  if k == "IsVisible" then return function(self) local f = self; while f do if f.shown == false then return false end; f = rawget(f, "parentFrame") end; return true end end
  if k == "GetWidth" or k == "GetHeight" then return function() return 560 end end
  if k:match("^Get") and (k:match("Width$") or k:match("Height$") or k:match("Scale$") or k:match("Alpha$")) then return function() return 100 end end
  if k == "GetCenter" or k == "GetPoint" then return function() return 0, 0 end end
  if k == "GetFrameLevel" then return function() return 1 end end
  if k == "GetParent" then return function(self) return self.parentFrame end end
  if k == "GetLeft" or k == "GetRight" or k == "GetTop" or k == "GetBottom" or k == "GetNumPoints" then return function() return 0 end end
  if k == "SetBackdropColor" then return function(self, r, g, b, al) self.bgc = { r, g, b, al }; return self end end
  if k == "GetBackdropColor" then return function(self) local c = self.bgc or {}; return c[1], c[2], c[3], c[4] end end
  if k == "SetText" then return function(self, v) self.text = v; return self end end
  if k == "GetText" then return function(self) return self.text end end
  if k == "SetChecked" then return function(self, v) self.checked = v; return self end end
  if k == "GetChecked" then return function(self) return self.checked or false end end
  if k == "SetValue" then return function(self, v) self.value = v; local h = self.scripts.OnValueChanged; if h then h(self, v) end; return self end end
  if k == "GetValue" then return function(self) return self.value end end
  if k == "SetMinMaxValues" then return function(self, a, b) self.min, self.max = a, b; return self end end
  if k == "SetAttribute" then return function(self, a, v) self.attrs[a] = v; return self end end
  if k == "GetAttribute" then return function(self, a) return self.attrs[a] end end
  -- geometry for the layout audit (tests/layout.lua): parents, anchors, sizes, fonts and wrapping are recorded
  if k == "CreateTexture" then return function(self, _, layer) local f = mkframe(); f.parentFrame = self; f._isTex = true; f._layer = layer; return f end end
  if k == "CreateFontString" then return function(self, _, layer, tmpl) local f = mkframe(); f.parentFrame = self; f._isFS = true; f._layer = layer; f._tmpl = tmpl; return f end end
  if k == "SetPoint" then return function(self, point, a, b, c, d)
    local rel, rp, x, y
    if type(a) == "number" or a == nil then rel, rp, x, y = nil, point, a or 0, b or 0
    elseif type(b) == "string" then rel, rp, x, y = a, b, c or 0, d or 0
    else rel, rp, x, y = a, point, b or 0, c or 0 end
    if type(rel) == "string" then rel = _G[rel] end
    self._pts = self._pts or {}; self._pts[#self._pts + 1] = { p = point, rel = rel, rp = rp, x = x, y = y }; return self end end
  if k == "SetAllPoints" then return function(self, rel) self._pts = { { p = "TOPLEFT", rel = rel, rp = "TOPLEFT", x = 0, y = 0 }, { p = "BOTTOMRIGHT", rel = rel, rp = "BOTTOMRIGHT", x = 0, y = 0 } }; return self end end
  if k == "ClearAllPoints" then return function(self) self._pts = nil; return self end end
  if k == "SetWidth" then return function(self, w) self._w = w; M.sized(self); return self end end
  if k == "SetHeight" then return function(self, h) self._h = h; M.sized(self); return self end end
  if k == "SetSize" then return function(self, w, h) self._w, self._h = w, h; M.sized(self); return self end end
  -- mouse and object type, as the client answers them (UI.CellFS turns the mouse on for a plain frame it hooks)
  if k == "RegisterForClicks" then return function(self, ...) self._clicks = { ... }; return self end end
  if k == "EnableMouse" then return function(self, v) self._mouse = v and true or false; return self end end
  if k == "IsMouseEnabled" then return function(self) return self._mouse == true or self._kind == "Button" or self._kind == "EditBox" end end
  if k == "GetObjectType" then return function(self) return self._isFS and "FontString" or self._isTex and "Texture" or self._kind or "Frame" end end
  if k == "SetJustifyH" then return function(self, j) self._justify = j; return self end end
  if k == "SetWordWrap" then return function(self, v) self._wrap = v and true or false; return self end end
  if k == "SetMaxLines" then return function(self, n) self._maxLines = n; return self end end
  if k == "SetFontObject" then return function(self, fo) self._font = fo; return self end end
  if k == "SetFont" then return function(self, file, size, flags) self._file, self._size, self._flags = file, size, flags; return true end end
  -- paint for tests/render_html.lua: colors, textures, backdrops, alpha and clipping are recorded, nothing reads them back
  if k == "SetTextColor" then return function(self, r, g, b, a) self._color = { r, g, b, a or 1 }; return self end end
  if k == "SetShadowColor" then return function(self, r, g, b, a) self._shadow = { r, g, b, a or 1 }; return self end end
  if k == "SetColorTexture" then return function(self, r, g, b, a) self._fill = { r, g, b, a or 1 }; self._file = nil; return self end end
  if k == "SetTexture" then return function(self, file) self._file = file; if file ~= nil then self._fill = nil end; return self end end
  if k == "SetTexCoord" then return function(self, ...) self._tc = { ... }; return self end end
  if k == "SetVertexColor" then return function(self, r, g, b, a) self._vc = { r, g, b, a or 1 }; return self end end
  if k == "SetBackdrop" then return function(self, bd) self._bd = bd; return self end end
  if k == "SetBackdropBorderColor" then return function(self, r, g, b, a) self._bdc = { r, g, b, a or 1 }; return self end end
  if k == "SetAlpha" then return function(self, a) self._alpha = a; return self end end
  if k == "SetFrameLevel" then return function(self, n) self._level = n; return self end end
  if k == "SetClipsChildren" then return function(self, v) self._clips = v and true or false; return self end end
  if k == "SetScrollChild" then return function(self, child) self._scrollChild = child; if child then child.parentFrame = self end; return self end end
  if k == "SetTextInsets" then return function(self, l, r, t, b) self._insets = { l or 0, r or 0, t or 0, b or 0 }; return self end end
  if k == "SetSpacing" then return function(self, n) self._spacing = n; return self end end
  if k == "SetJustifyV" then return function(self, j) self._justifyV = j; return self end end
  if k == "SetParent" then return function(self, pa) self.parentFrame = pa; return self end end
  if k == "GetStringWidth" then return function(self) return M.textWidth and M.textWidth(self) or 100 end end
  if k == "GetName" then return noop end
  return function(self) return self end        -- chainable no-op for SetPoint/SetSize/etc.
end
M.errors = {}
-- OnSizeChanged, the way the client sends it: to a frame with the handler whenever the size it resolves to changes.
-- The stub has no layout engine of its own (tests/geometry.lua installs one), so it asks GetWidth and GetHeight
-- each time the window is sized (SetSize/SetWidth/SetHeight on EverbuffFrame) and when a test calls M.settle(),
-- and repeats until nothing changes, as a resize ripples down nested frames; a watched frame sized directly hears
-- its own change at once.
M.sizeWatch = {}
function M.watchSize(f) if not f._watched then f._watched = true; M.sizeWatch[#M.sizeWatch + 1] = f end end
-- a frame was sized: the window ripples through everything, a watched frame hears its own change
function M.sized(f)
  if f._root then M.settle()
  elseif f._watched and not M.settling then
    local h = f.scripts.OnSizeChanged
    local w, ht = f:GetWidth(), f:GetHeight()
    if h and (w ~= f._seenW or ht ~= f._seenH) then
      f._seenW, f._seenH = w, ht
      local ok, err = pcall(h, f, w, ht)
      if not ok then M.errors[#M.errors + 1] = "OnSizeChanged: " .. tostring(err) end
    end
  end
end
function M.settle()
  if M.settling then return end
  M.settling = true
  for _ = 1, 8 do
    local changed = false
    for _, f in ipairs(M.sizeWatch) do
      local h = f.scripts.OnSizeChanged
      if h then
        local w, ht = f:GetWidth(), f:GetHeight()
        if w ~= f._seenW or ht ~= f._seenH then
          f._seenW, f._seenH = w, ht; changed = true
          local ok, err = pcall(h, f, w, ht)
          if not ok then M.errors[#M.errors + 1] = "OnSizeChanged: " .. tostring(err) end
        end
      end
    end
    if not changed then break end
  end
  M.settling = false
end
function M.fire(event, ...)
  for _, f in ipairs(frames) do
    if f.events[event] and f.scripts.OnEvent then
      local ok, err = pcall(f.scripts.OnEvent, f, event, ...)
      if not ok then M.errors[#M.errors + 1] = event .. ": " .. tostring(err) end
    end
  end
end
function M.runTimers() local t = M.timers; M.timers = {}; for _, fn in ipairs(t) do fn() end end
function M.tick()
  for _, tk in ipairs(M.tickers) do
    if not tk.cancelled then local ok, err = pcall(tk.fn); if not ok then M.errors[#M.errors + 1] = "ticker: " .. tostring(err) end end
  end
end

_G.CreateFrame = function(kind, name, parent, tmpl) local f = mkframe(); f.parentFrame = parent; f._kind, f._tmpl = kind, tmpl; if name then _G[name] = f end; if name == "EverbuffFrame" then f._root = true end; return f end
_G.UIParent, _G.GameTooltip = mkframe(), mkframe()
-- the tooltip keeps its owner and lines so tests can read what a hover shows
do
  local tip = _G.GameTooltip
  tip.lines, tip.shown = {}, false
  function tip:SetOwner(owner, anchor) self.owner, self.anchor = owner, anchor; self.lines = {}; self._pts = nil; return self end
  function tip:GetOwner() return self.owner end
  -- the client's line FontStrings, GameTooltipTextLeft1..n, read back what each line says
  function tip:GetName() return "GameTooltip" end
  local function lineFS(i, text) _G["GameTooltipTextLeft" .. i] = { GetText = function() return text end } end
  function tip:AddLine(text) self.lines[#self.lines + 1] = text; lineFS(#self.lines, text); return self end
  function tip:AddDoubleLine(a, b) self.lines[#self.lines + 1] = tostring(a) .. "  " .. tostring(b); lineFS(#self.lines, a); return self end
  function tip:ClearLines() self.lines = {}; return self end
  function tip:NumLines() return #self.lines end
  function tip:Hide() self.shown = false; self.owner = nil; return self end
  function tip:IsOwned(frame) return self.owner ~= nil and self.owner == frame end
end
_G.C_Timer = {
  After = function(_, fn) M.timers[#M.timers + 1] = fn end,
  NewTicker = function(_, fn) local tk = { fn = fn }; tk.Cancel = function(s) s.cancelled = true end; M.tickers[#M.tickers + 1] = tk; return tk end,
}
_G.GetTime = function() return M.now end
-- Secret Values (12.0): the real client throws on compare, arithmetic and table keys; the stub cannot
-- make a plain Lua string throw, so tests mark values secret here and the guards must ask first.
M.secrets = {}
_G.issecretvalue = function(v) return M.secrets[v] == true end
_G.GetServerTime = function() return M.epoch end
-- the daily and weekly reset as the client answers them (gold day rows, everbuff-wow-addon #43): the server day
-- starts at M.resetAt seconds into the UTC day, the week on a Tuesday. M.resetSecs and M.weekStart override the
-- answers (false: the client answers nothing).
M.resetAt = 7 * 3600
_G.C_DateAndTime = {
  GetSecondsUntilDailyReset = function()
    if M.resetSecs ~= nil then return M.resetSecs or nil end
    return 86400 - ((M.epoch - M.resetAt) % 86400)
  end,
  GetWeeklyResetStartTime = function()
    if M.weekStart ~= nil then return M.weekStart or nil end
    local first = 5 * 86400 + M.resetAt   -- Tuesday 1970-01-06
    return first + math.floor((M.epoch - first) / 604800) * 604800
  end,
}
_G.time, _G.date = os.time, os.date
_G.tinsert, _G.wipe, _G.format = table.insert, function(t) for k in pairs(t) do t[k] = nil end return t end, string.format
_G.strupper, _G.strlower, _G.strtrim = string.upper, string.lower, function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
_G.strsplit = function(d, s) local out = {}; for p in (s .. d):gmatch("(.-)" .. d:gsub("%p", "%%%0")) do out[#out + 1] = p end return unpack(out) end
_G.UISpecialFrames, _G.SlashCmdList = {}, {}
_G.RequestTimePlayed = noop
-- the global Lua error handler (Debug.lua chains it)
_G.seterrorhandler = function(fn) M.errorHandler = fn end
_G.geterrorhandler = function() return M.errorHandler end
_G.debugstack = function() return "[Interface/AddOns/EverbuffJournal/Emitter.lua]:1170: in function <stub>" end
_G.hooksecurefunc = function(a, b, c)
  local tbl, name, fn = _G, a, b
  if type(a) == "table" then tbl, name, fn = a, b, c end
  local orig = tbl[name]; if type(orig) ~= "function" then return end
  tbl[name] = function(...) local r = { orig(...) }; fn(...); return unpack(r) end
end
-- quest reward panel: M.questChoices = { "Item", ... } while it is open; GetQuestReward closes it first,
-- the way the client can, so the hook reads nothing live
_G.GetNumQuestChoices = function() return M.questChoices and #M.questChoices or 0 end
_G.GetQuestItemLink = function(kind, i) local nm = kind == "choice" and M.questChoices and M.questChoices[i]; if nm then return ("|cff1eff00|Hitem:%d::::::::|h[%s]|h|r"):format(9000 + i, nm) end end
_G.GetQuestItemInfo = function(kind, i) return kind == "choice" and M.questChoices and M.questChoices[i] or nil end
_G.GetQuestReward = function() if not M.panelStays then M.questChoices = nil end end   -- M.panelStays: a client that keeps it readable
_G.TakeTaxiNode = function() end
-- mailbox: M.inbox = { { sender, subject, money, cod, invoice = { type, item, player }, items = { { name, id, count, quality } } } }
M.inbox = {}
_G.ATTACHMENTS_MAX_RECEIVE = 16
_G.GetInboxHeaderInfo = function(i) local m = M.inbox[i]; if not m then return end
  return 1, 1, m.sender, m.subject, m.money or 0, m.cod or 0, 30, m.items and #m.items > 0, true, false, false, m.canReply ~= false, false end
_G.GetInboxInvoiceInfo = function(i) local m = M.inbox[i]; if m and m.invoice then return unpack(m.invoice) end end
_G.GetInboxItem = function(i, j) local it = M.inbox[i] and M.inbox[i].items and M.inbox[i].items[j]; if not it then return end
  return it.name, it.id, 1000 + it.id, it.count, it.quality, true end
_G.GetInboxItemLink = function(i, j) local it = M.inbox[i] and M.inbox[i].items and M.inbox[i].items[j]; if not it then return end
  local Q = { [0] = "ff9d9d9d", "ffffffff", "ff1eff00", "ff0070dd", "ffa335ee", "ffff8000" }
  return ("|c%s|Hitem:%d::::::::1:::::::|h[%s]|h|r"):format(Q[it.quality or 1], it.id, it.name) end
_G.TakeInboxMoney = function(i) M.mailTook = (M.mailTook or 0) + 1 end
_G.TakeInboxItem = function(i, j) M.mailTook = (M.mailTook or 0) + 1 end
_G.AutoLootMailItem = function(i) M.mailTook = (M.mailTook or 0) + 1 end
_G.WOW_PROJECT_ID, _G.WOW_PROJECT_MAINLINE, _G.WOW_PROJECT_CLASSIC = 1, 1, 2
_G.C_Item = _G.C_Item or {}
M.itemQuality = {}
_G.C_Item.GetItemQualityByID = function(id) return M.itemQuality[id] end
_G.GetLocale = function() return "enUS" end
_G.GetBuildInfo = function() return "12.0.1", "60000", "Jan 1 2026", 120001 end
_G.GetCVar = function(k) return M.cvars[k] end
_G.SetCVar = function(k, v) M.cvars[k] = v end
M.chatCalls = 0
_G.LoggingChat = function(v) if v ~= nil then M.chatLogging = v; M.chatCalls = M.chatCalls + 1 end return M.chatLogging end
_G.LoggingCombat = function(v) if v ~= nil then M.logging = v end return M.logging end
_G.GetRealmName = function() return "Realm" end
_G.GetGuildInfo = function(u) local x = u ~= "player" and M.units[u]; return x and x.guild or nil end
_G.UnitFactionGroup = function() return "Alliance" end
_G.UnitName = function(u) if u == "player" then return "Hart", "Realm" end local x = M.units[u]; return x and x.name end
_G.UnitGUID = function(u) if u == "player" then return "Player-1-000001" end local x = M.units[u]; return x and x.guid end
_G.UnitExists = function(u) return u == "player" or M.units[u] ~= nil end
_G.UnitCanAttack = function(_, u) local x = M.units[u]; return x and x.hostile or false end
_G.UnitIsFriend = function(_, u) local x = M.units[u]; if not x then return false end if x.friend ~= nil then return x.friend end return not x.hostile end
_G.UnitIsDead = function(u) local x = M.units[u]; return x and x.dead or false end
_G.UnitIsDeadOrGhost = function(u) if u == nil or u == "player" then return M.dead or false end local x = M.units[u]; return x and x.dead or false end
_G.UnitAffectingCombat = function() return M.inCombat end
_G.InCombatLockdown = function() return M.inCombat end
_G.UnitClassification = function(u) local x = M.units[u]; return x and x.cls or "normal" end
_G.UnitLevel = function() return M.level end
_G.UnitClass = function() return "Warrior", "WARRIOR" end
_G.UnitRace = function() return "Human" end
_G.UnitIsUnit = function(a, b) return a == b end
_G.GetMaxPlayerLevel = function() return 60 end
_G.GetRealZoneText = function() return M.zone end
_G.GetSubZoneText = function() return "" end
_G.GetInstanceInfo = function() local i = M.inst; return i.name, i.type, i.diff, "", 5, 0, false, i.mapID, 5, 0 end
_G.IsInInstance = function() return M.inst.type ~= "none" end
_G.GetNumGroupMembers = function() return M.groupN end
_G.IsInRaid, _G.IsInGroup = function() return false end, function() return M.groupN > 1 end
_G.GetMoney = function() return M.money end
_G.UnitXP, _G.UnitXPMax, _G.GetXPExhaustion = function() return M.xp end, function() return M.xpmax end, function() return M.rested end
_G.GetInventoryItemLink = function(_, slot) return M.gear[slot] end
_G.GetInventoryItemTexture = function() return 135274 end
_G.GetInventoryItemQuality = function() return 2 end
_G.C_UnitAuras = { GetAuraDataByIndex = function(u, i, filter) local a = M.auras[u]; return a and a[filter] and a[filter][i] end }
_G.RAID_CLASS_COLORS = { WARRIOR = { r = 0.78, g = 0.61, b = 0.43 } }
-- localized format strings (enUS) the addon derives its parsers from
_G.LOOT_ITEM_SELF, _G.LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %s.", "You receive loot: %sx%d."
_G.LOOT_ITEM_PUSHED_SELF, _G.LOOT_ITEM_PUSHED_SELF_MULTIPLE = "You receive item: %s.", "You receive item: %sx%d."
_G.LOOT_ITEM_CREATE_SELF, _G.SKILL_RANK_UP = "You create: %s.", "Your skill in %s has increased to %d."
_G.ERR_ZONE_EXPLORED_XP, _G.ERR_ZONE_EXPLORED = "Discovered %s: %d experience gained.", "Discovered: %s"
_G.ERR_NEWTAXIPATH = "New flight path discovered!"
_G.UNKNOWNOBJECT = "Unknown"   -- the client's placeholder for a name it has not resolved yet (#42)
_G.ERR_LEARN_RECIPE_S = "You have learned how to create a new item: %s."
_G.COMBATLOG_XPGAIN_FIRSTPERSON = "%s dies, you gain %d experience."
_G.COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED = "You gain %d experience."
_G.COMBATLOG_XPGAIN_EXHAUSTION1 = "%s dies, you gain %d experience. (%s exp %s bonus)"
_G.COMBATLOG_XPGAIN_EXHAUSTION4 = "You gain %d experience. (%s exp %s bonus)"
_G.FACTION_STANDING_LABEL5 = "Friendly"
_G.GetNumFactions = function() return 1 end
_G.GetFactionInfo = function(i) if i == 1 then return "Stormwind", "", 5, 3000, 6000, 4500, false, false, false end end
for _, f in ipairs({ "GameFontNormal", "GameFontNormalLarge", "GameFontNormalSmall", "GameFontHighlight", "GameFontHighlightSmall", "GameFontDisableSmall" }) do _G[f] = mkframe() end
_G.UnitNameUnmodified = _G.UnitName
_G.UnitGroupRolesAssigned = function() return "NONE" end
_G.UnitIsConnected = function() return true end
_G.UnitIsPlayer = function(u) if u == "player" then return true end local x = M.units[u]; return x and x.player or false end
_G.UnitHealthMax, _G.UnitPowerMax = function() return 1000 end, function() return 500 end
_G.UnitStat, _G.UnitAttackPower, _G.UnitRangedAttackPower = function() return 10, 12 end, function() return 100, 0, 0 end, function() return 50, 0, 0 end
_G.UnitDamage, _G.UnitAttackSpeed, _G.UnitArmor = function() return 10, 20, 0, 0 end, function() return 2.0 end, function() return 100, 120 end
_G.UnitResistance = function() return 0, 0 end
_G.GetAverageItemLevel = function() return 20, 18 end
_G.GetCritChance, _G.GetSpellCritChance, _G.GetDodgeChance = function() return 5 end, function() return 4 end, function() return 3 end
_G.GetParryChance, _G.GetBlockChance = function() return 0 end, function() return 0 end
M.questItems = { [5075] = true }
_G.GetItemInfoInstant = function(id) return id, "Quest", "Quest", "", 134400, M.questItems[id] and 12 or 0, 0 end
_G.GetSpellInfo = function(id) return ({ [2366] = "Herb Gathering", [2575] = "Mining", [8613] = "Skinning", [7620] = "Fishing", [1243] = "Power Word: Fortitude", [1126] = "Mark of the Wild", [17534] = "Superior Healing Potion", [746] = "First Aid" })[id] end
M.knownSpells = { [2366] = true, [2575] = true, [8613] = true, [7620] = true, [1243] = true, [1126] = true, [746] = true }
_G.IsPlayerSpell = function(id) return M.knownSpells[id] or false end
_G.C_Map = { GetBestMapForUnit = function() return M.uiMap or 37 end,
             GetMapInfo = function(id) return { mapID = id, mapType = M.mapType or 3 } end,
             GetPlayerMapPosition = function() return { GetXY = function() return 0.421, 0.637 end } end }
_G.GetLootSourceInfo = function() return M.lootSourceGUID end
M.dur = {}
M.profs = {}
M.onTaxi = false
_G.UnitOnTaxi = function() return M.onTaxi end
_G.Minimap = mkframe()
_G.GetCursorPosition = function() return 0, 0 end
_G.GetSpecialization = function() return 1 end
_G.GetSpecializationInfo = function() return 71, "Arms" end
_G.GetProfessions = function() return 1, 2 end
_G.GetProfessionInfo = function(i) local pr = M.profs[i]; if pr then return pr.name, 136, pr.rank, pr.max end end
_G.C_MountJournal = { GetMountInfoByID = function(id) return ({ [458] = "Brown Horse" })[id] end }
_G.GetInventoryItemDurability = function(slot) local d = M.dur[slot]; if d then return d[1], d[2] end end
M.saved = {}
_G.RequestRaidInfo = function() end
_G.GetAddOnMetadata = function(addon, key)
  if key == "Version" then local toc = io.open("Everbuff/EverbuffJournal.toc"); if toc then local s = toc:read("*a"); toc:close(); return s:match("## Version: (%S+)") end end
end
M.cleu = nil
_G.CombatLogGetCurrentEventInfo = function() return unpack(M.cleu or {}) end
_G.GetNumSavedInstances = function() return #M.saved end
_G.GetSavedInstanceInfo = function(i) local s = M.saved[i]; if not s then return end
  return s.name, s.id or i, s.reset or 3600, 1, s.locked ~= false, s.extended or false, false, s.raid or false, s.players or 5, s.diff or "Normal", s.bosses or 0, s.down or 0 end
_G.UIFrameFadeIn, _G.UIFrameFadeOut, _G.UIFrameFade = function() end, function() end, function() end
M.shift, M.inserted = false, nil
_G.IsShiftKeyDown = function() return M.shift end
M.sellPrice = {}   -- item id -> vendor sell price per unit (GetItemInfo's 11th value)
_G.GetItemInfo = function(id) return "Item " .. tostring(id), ("|cffffffff|Hitem:%d::::::::1:::::::|h[Item %d]|h|r"):format(id, id), 1, 10, 1, "Misc", "Junk", 20, "", 134400, M.sellPrice[id] end
_G.ChatEdit_InsertLink = function(link) M.inserted = link; return true end
_G.CreateFont = function() return mkframe() end

-- auction house (Mainline shapes) and tradeskill window, for Market.lua
M.locations = {}   -- fake ItemLocation -> { name, id, icon, count }
_G.C_Item = _G.C_Item or {}
_G.C_Item.GetItemLink = function(loc) local it = M.locations[loc]; return it and ("|cffffffff|Hitem:%d::::::::1:::::::|h[%s]|h|r"):format(it.id, it.name) end
_G.C_Item.GetItemID = function(loc) local it = M.locations[loc]; return it and it.id end
_G.C_Item.GetItemName = function(loc) local it = M.locations[loc]; return it and it.name end
_G.C_Item.GetItemIcon = function(loc) local it = M.locations[loc]; return it and it.icon end
_G.C_Item.GetStackCount = function(loc) local it = M.locations[loc]; return it and it.count end
_G.C_Item.GetItemNameByID = function(id) return M.itemNames and M.itemNames[id] end
-- town services the visit hooks count (Visits.lua, everbuff-business #39)
M.repairCost = 0
_G.GetRepairAllCost = function() return M.repairCost, M.repairCost > 0 end
_G.RepairAllItems = function() M.repairCost = 0 end   -- (true: paid by the guild bank; the cost clears either way)
_G.BuyMerchantItem = function() end
_G.UseContainerItem = function() end
-- bags as WoW Forever answers them: M.bags[bag][slot] = { itemID, quality, hasNoValue? }; selling all junk empties
-- the junk slots only when the test says the server answered (M.sellJunkNow)
M.bags = { [0] = {} }
_G.C_Container = {
  GetContainerNumSlots = function(bag) return M.bags[bag] and 16 or 0 end,
  GetContainerItemInfo = function(bag, slot) return M.bags[bag] and M.bags[bag][slot] end,
  UseContainerItem = function(bag, slot) end,
}
M.junkCalls = 0
_G.C_MerchantFrame = { SellAllJunkItems = function() M.junkCalls = M.junkCalls + 1 end }
function M.serverSellsJunk()
  for _, b in pairs(M.bags) do for slot, it in pairs(b) do if it.quality == 0 and not it.hasNoValue then b[slot] = nil end end end
end
_G.BuyTrainerService = function() end
_G.QueryAuctionItems = function() end
_G.C_AuctionHouse = {
  PostItem = function() end, PostCommodity = function() end, PlaceBid = function() end,
  StartCommoditiesPurchase = function() end, ConfirmCommoditiesPurchase = function() end, CancelAuction = function() end,
}
M.tradeSkillName = nil
_G.C_TradeSkillUI = _G.C_TradeSkillUI or {}
_G.C_TradeSkillUI.GetBaseProfessionInfo = function() return { professionName = M.tradeSkillName } end
-- gold journal (#36): the trade window, merchant items, the guild roster, the friends list, new mail
-- M.tradeWin = { gaveMoney, gotMoney, player = { [slot] = { id, name, count } }, target = { ... } } while it is open
M.tradeWin = nil
local function tslot(side, i) local w = M.tradeWin; return w and w[side] and w[side][i] end
_G.MAX_TRADABLE_ITEMS = 6
_G.ERR_TRADE_COMPLETE, _G.ERR_TRADE_CANCELLED = "Trade complete.", "Trade cancelled."
_G.GetPlayerTradeMoney = function() return M.tradeWin and M.tradeWin.gaveMoney or 0 end
_G.GetTargetTradeMoney = function() return M.tradeWin and M.tradeWin.gotMoney or 0 end
_G.GetTradePlayerItemInfo = function(i) local it = tslot("player", i); if it then return it.name, 134400, it.count, 1, true, nil end end
_G.GetTradeTargetItemInfo = function(i) local it = tslot("target", i); if it then return it.name, 134400, it.count, 1, true, nil end end
_G.GetTradePlayerItemLink = function(i) local it = tslot("player", i); if it and it.id then return ("|cffffffff|Hitem:%d::::::::1:::::::|h[%s]|h|r"):format(it.id, it.name) end end
_G.GetTradeTargetItemLink = function(i) local it = tslot("target", i); if it and it.id then return ("|cffffffff|Hitem:%d::::::::1:::::::|h[%s]|h|r"):format(it.id, it.name) end end
-- M.merchant[index] = { id, name, price, qty }
M.merchant = {}
_G.GetMerchantItemLink = function(i) local it = M.merchant[i]; if it then return ("|cffffffff|Hitem:%d::::::::1:::::::|h[%s]|h|r"):format(it.id, it.name or "x") end end
_G.GetMerchantItemInfo = function(i) local it = M.merchant[i]; if it then return it.name or "x", 134400, it.price or 0, it.qty or 1, -1, true end end
M.guild, M.friends, M.newMail = {}, {}, false
_G.IsInGuild = function() return #M.guild > 0 end
_G.GetNumGuildMembers = function() return #M.guild end
_G.GetGuildRosterInfo = function(i) return M.guild[i] end
_G.C_GuildInfo = { GuildRoster = function() M.rosterAsked = (M.rosterAsked or 0) + 1 end }
_G.C_FriendList = {
  GetNumFriends = function() return #M.friends end,
  GetFriendInfoByIndex = function(i) local n = M.friends[i]; return n and { name = n } or nil end,
}
_G.HasNewMail = function() return M.newMail end
-- honest sources (everbuff-wow-addon #43, 0.9.46): the namespaced merchant and item reads, buyback, the interaction
-- manager, the auction house's deposit and cancel cost, the client's coin lines
_G.C_MerchantFrame.GetItemInfo = function(i) local it = M.merchant[i]; if it then return { name = it.name or "x", texture = 134400, price = it.price or 0, stackCount = it.qty or 1, numAvailable = -1, isPurchasable = true } end end
_G.C_Item.GetItemInfo = function(id) return "Item " .. tostring(id), ("|cffffffff|Hitem:%d::::::::1:::::::|h[Item %d]|h|r"):format(id, id), 1, 10, 1, "Misc", "Junk", 20, "", 134400, M.sellPrice[id] end
-- M.buyback[index] = { id, name, price, qty }
M.buyback = {}
_G.GetBuybackItemLink = function(i) local it = M.buyback[i]; if it then return ("|cffffffff|Hitem:%d::::::::1:::::::|h[%s]|h|r"):format(it.id, it.name or "x") end end
_G.GetBuybackItemInfo = function(i) local it = M.buyback[i]; if it then return it.name or "x", 134400, it.price, it.qty or 1, 1, true end end
_G.BuybackItem = function() end
_G.CanMerchantRepair = function() return M.canRepair ~= false end
-- M.interact[kind] = true while the client says the player is at that kind of NPC (M.interactOff: the API answers nothing)
M.interact = {}
_G.Enum = _G.Enum or {}
_G.Enum.PlayerInteractionType = { Merchant = 5, Trainer = 7, MailInfo = 17, Auctioneer = 21 }
_G.C_PlayerInteractionManager = { IsInteractingWithNpcOfType = function(t)
  if M.interactOff then return nil end
  for name, v in pairs(_G.Enum.PlayerInteractionType) do if v == t then return M.interact[name] == true end end
  return false
end }
-- M.ahDeposit, M.ahCancelCost: what the auction house answers (nil: nothing)
_G.C_AuctionHouse.CalculateItemDeposit = function() return M.ahDeposit end
_G.C_AuctionHouse.CalculateCommodityDeposit = function() return M.ahDeposit end
_G.C_AuctionHouse.GetCancelCost = function() return M.ahCancelCost end
_G.LOOT_MONEY_SPLIT, _G.YOU_LOOT_MONEY, _G.YOU_LOOT_MONEY_GUILD = "Your share of the loot is %s.", "You loot %s", "You loot %s (%s deposited to guild bank)"
_G.GOLD_AMOUNT, _G.SILVER_AMOUNT, _G.COPPER_AMOUNT = "%d Gold", "%d Silver", "%d Copper"
_G.ERR_TAXINOTENOUGHMONEY, _G.ERR_TAXINOPATHS = "You don't have enough money!", "You don't know any flight locations connected to this one."
-- a /reload: the client fires PLAYER_LOGOUT and writes the save file after this returns (a test fires the event itself)
_G.ReloadUI = function() end
_G.GetCoinTextureString = function(c) return tostring(c) end
-- The WoW Forever profile (#43, 0.9.46): the globals the Midnight engine documents a namespaced replacement for are
-- gone (C_MerchantFrame.GetItemInfo, C_Item.GetItemInfo, C_Container.GetContainerItemInfo, C_CurrencyInfo); the
-- ones without a replacement stay. Applied before the addon loads (tests/gold_profile.lua).
M.FOREVER_GONE = { "GetMerchantItemInfo", "GetItemInfo", "GetContainerItemInfo", "GetCoinTextureString" }
function M.profile(name)
  if name == "forever" then for _, g in ipairs(M.FOREVER_GONE) do _G[g] = nil end end
end
M.frames = frames
return M
