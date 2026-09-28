-- Everbuff.GG · Sync.lua - the CAPTURE pane of Settings (capture health + disconnect protection).
--
-- Built into Settings > Capture by Emitter via ns.BuildCapturePane. Presents what the ADDON can actually
-- know: its own session beacon + the combat-log switch. Video recording lives in the desktop app, which
-- the game cannot see, so it is stated as such and never claimed.

local ADDON, ns = ...
local UI = ns.UI
local C = ns.UI.C

local view, refresh, ticker

local GREEN, GRAY, YELLOW = "Interface\\COMMON\\Indicator-Green", "Interface\\COMMON\\Indicator-Gray", "Interface\\COMMON\\Indicator-Yellow"
local function dot(tex) return ("|T%s:12:12:0:-1|t"):format(tex) end

refresh = function()
  local c = view; if not c or not c.rows then return end
  local sess = ns.Recorder and ns.Recorder.active and ns.Recorder.active()
  local aclOn, combatOn = false, false
  if ns.Logging and ns.Logging.state then aclOn, combatOn = ns.Logging.state() end
  local R = c.rows
  R.recording:SetText(sess
    and (dot(GREEN) .. " |cff59c77fCapturing|r  " .. (sess.context or "") .. "  (session beacon + combat log)")
    or (dot(GRAY) .. " |cff8c9197Standing by|r"))
  R.combat:SetText((combatOn and aclOn) and (dot(GREEN) .. " on, full detail")
    or (combatOn and (dot(YELLOW) .. " on, basic detail (advanced logging is off)")
    or (dot(YELLOW) .. " off, re-asserts when combat starts")))
  R.desktop:SetText("shown in the desktop app; the game cannot see it, so this panel never claims it")
  R.client:SetText(ns.hasSecretValues
    and "Secret Values client: damage/DPS comes from the combat-log file (by design)"
    or "Classic client: full combat data readable")
  local hidden, blind = (ns.Fights and ns.Fights.hiddenAuras) or 0, (ns.Fights and ns.Fights.blindScans) or 0
  R.auras:SetText((hidden == 0 and blind == 0) and (dot(GREEN) .. " readable")
    or (dot(YELLOW) .. (" hidden by the client in combat: %d unreadable names, %d fully blind scans skipped; names resolve from spell ids or after combat"):format(hidden, blind)))
  local la = ns.DB and ns.DB.combat and ns.DB.combat.lastAck
  local pending = 0
  for _, f in ipairs((ns.DB and ns.DB.combat and ns.DB.combat.fights) or {}) do if f.uploaded ~= true then pending = pending + 1 end end
  R.sync:SetText(la
    and (dot(GREEN) .. (" last synced %s (%s)  ·  %d fight%s waiting"):format(date("%b %d, %H:%M", la.at or 0), la.source == "paste" and "code" or "desktop file", pending, pending == 1 and "" or "s"))
    or (dot(YELLOW) .. (" never  ·  %d fight%s waiting for the desktop app"):format(pending, pending == 1 and "" or "s")))
  local errs = (UI.tabErrors and UI.tabErrors()) or {}
  R.ui:SetText(#errs == 0 and (dot(GREEN) .. " all tabs built cleanly") or (dot(YELLOW) .. " " .. table.concat(errs, "  |  ")))
end

function ns.BuildCapturePane(content)
  view = content
  content.rows = {}
  local y = -6
  local function heading(text) local h = UI.FS(content, "GameFontNormal", C.gold); h:SetPoint("TOPLEFT", 14, y); h:SetText(text); y = y - 24 end
  local function line(label, key)
    local l = UI.FS(content, "GameFontNormalSmall", C.dim); l:SetPoint("TOPLEFT", 16, y); l:SetWidth(150); l:SetJustifyH("LEFT"); l:SetText(label:upper())
    local v = UI.FS(content, "GameFontHighlightSmall", C.ink); v:SetPoint("TOPLEFT", 172, y); v:SetWidth(540); v:SetJustifyH("LEFT")
    content.rows[key] = v; y = y - 22
  end

  heading("Capture")
  line("Capture", "recording")
  line("Combat logging", "combat")
  line("Video recording", "desktop")
  line("Client", "client")
  line("In-combat aura names", "auras")
  line("Desktop sync", "sync")

  y = y - 8
  heading("Disconnect protection")
  local auto = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
  auto:SetPoint("TOPLEFT", 14, y + 2); auto:SetSize(24, 24)
  local isOn = (not ns.DB or not ns.DB.settings or ns.DB.settings.autoSave == nil) or (ns.DB.settings.autoSave and true or false)
  auto:SetChecked(isOn)
  local autoLbl = UI.FS(content, "GameFontHighlightSmall"); autoLbl:SetPoint("LEFT", auto, "RIGHT", 4, 0); autoLbl:SetText("Remind me to save (recommended)")
  auto:SetScript("OnClick", function(self)
    if ns.DB and ns.DB.settings then ns.DB.settings.autoSave = self:GetChecked() and true or false end
  end)
  y = y - 30
  local dc = UI.FS(content, "GameFontDisableSmall", C.dim); dc:SetPoint("TOPLEFT", 16, y); dc:SetWidth(680); dc:SetJustifyH("LEFT")
  dc:SetText("WoW only writes to disk on reload or logout, so a disconnect loses anything since then. With the reminder on, Everbuff.GG asks you to reload when it is safe (out of combat). Nothing is lost by reloading; it just commits to disk.")
  y = y - 44
  -- SECURE reload button: our addon reads secret values so a Lua-driven reload is blocked; a click on a
  -- SecureActionButton running /reload is a hardware event and works.
  local save = CreateFrame("Button", "EverbuffSyncReloadBtn", content, "SecureActionButtonTemplate,BackdropTemplate")
  save:SetSize(150, 26); save:SetPoint("TOPLEFT", 16, y)
  save:SetAttribute("type", "macro"); save:SetAttribute("macrotext", "/reload"); save:RegisterForClicks("AnyUp", "AnyDown")
  save:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
  save:SetBackdropColor(C.panel2[1], C.panel2[2], C.panel2[3], 0.9); save:SetBackdropBorderColor(C.edge[1], C.edge[2], C.edge[3], 1)
  local sfs = UI.FS(save, "GameFontNormal"); sfs:SetPoint("CENTER"); sfs:SetText("Reload & save"); sfs:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
  save:HookScript("OnEnter", function(s) s:SetBackdropColor(C.hover[1], C.hover[2], C.hover[3], 1); s:SetBackdropBorderColor(C.hover[1], C.hover[2], C.hover[3], 1) end)
  save:HookScript("OnLeave", function(s) s:SetBackdropBorderColor(C.edge[1], C.edge[2], C.edge[3], 1); s:SetBackdropColor(C.panel2[1], C.panel2[2], C.panel2[3], 0.9) end)
  y = y - 44

  heading("Health")
  line("UI health", "ui")

  refresh()
  if not ticker then
    ticker = C_Timer.NewTicker(3, function() if view and view:IsShown() and refresh then refresh() end end)
  end
end
ns.RefreshCapturePane = function() if refresh then refresh() end end
