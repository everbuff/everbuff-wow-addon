-- Everbuff · Recording.lua — the "background logging" flow, made visible.
--
-- This tab has NO controls that can turn recording off. It exists only to reassure the user that the
-- always-on foundation is working: advanced combat logging is forced on in every instance, fight
-- boundaries are being indexed, and sessions are queued for upload. (Raid-lead tools are separate.)

local ADDON, ns = ...
local UI = ns.UI
local C = ns.UI.C

local bigFS, aclFS, combatFS, sessFS, storedFS, ticker

local function refresh()
  if not bigFS then return end
  local sess = ns.Recorder.active()
  local aclOn, combatOn = ns.Logging.state()

  if sess then
    bigFS:SetText("|cff47c97eRecording — everything|r")
  elseif IsInInstance() then
    bigFS:SetText("|cffc9a63cIn instance — starting…|r")
  else
    bigFS:SetText("|cff8a96a6Idle — auto-starts in any raid or dungeon|r")
  end

  aclFS:SetText(("Advanced combat logging: %s"):format(
    aclOn and "|cff47c97eON|r" or "|cffe5544bOFF|r"))
  combatFS:SetText(("Combat logging to file: %s%s"):format(
    combatOn and "|cff47c97eON|r" or "|cffe6a93cre-enabling…|r",
    (ns.Logging.repairs and ns.Logging.repairs > 0) and (" |cff8a96a6· kept on " .. ns.Logging.repairs .. "×|r") or ""))

  if sess then
    sessFS:SetText(("Current session: |cff00afd7%s|r · %s · %d markers")
      :format(sess.context or "?", sess.id, #sess.segments))
  else
    sessFS:SetText("Current session: |cff8a96a6none|r")
  end

  local n = 0
  for _ in pairs(ns.DB.sessions) do n = n + 1 end
  storedFS:SetText(("%d session(s) stored — handed to the desktop uploader on /reload or logout"):format(n))
end

local function build(content)
  local title = UI.FS(content, "GameFontNormalLarge", C.gold)
  title:SetPoint("TOPLEFT", 4, -4); title:SetText("Background logging")

  local sub = UI.FS(content, "GameFontHighlightSmall", C.dim)
  sub:SetPoint("TOPLEFT", 6, -28); sub:SetWidth(560); sub:SetJustifyH("LEFT")
  sub:SetText("Runs automatically for everyone — no setup, and no way to turn it off. This is the foundation the website is built on: the full combat log is captured cleanly for every pull, every night.")

  local card = UI.Panel(content, C.panel2[1], C.panel2[2], C.panel2[3])
  card:SetPoint("TOPLEFT", 4, -74); card:SetPoint("TOPRIGHT", -8, -74); card:SetHeight(150)

  bigFS = UI.FS(card, "GameFontNormalLarge")
  bigFS:SetPoint("TOPLEFT", 14, -14)

  aclFS = UI.FS(card, "GameFontHighlight"); aclFS:SetPoint("TOPLEFT", 14, -48)
  combatFS = UI.FS(card, "GameFontHighlight"); combatFS:SetPoint("TOPLEFT", 14, -70)
  sessFS = UI.FS(card, "GameFontHighlight"); sessFS:SetPoint("TOPLEFT", 14, -98)
  storedFS = UI.FS(card, "GameFontHighlightSmall", C.dim); storedFS:SetPoint("TOPLEFT", 14, -122)

  local note = UI.FS(content, "GameFontDisableSmall", C.dim)
  note:SetPoint("TOPLEFT", 6, -236); note:SetWidth(560); note:SetJustifyH("LEFT")
  note:SetText("A 15-second watchdog re-enables logging if any other addon or a stray /combatlog turns it off, and marks the gap so nothing is silently lost.")

  refresh()
end

UI.registerTab(1, "Recording", build, function()
  refresh()
  if not ticker then ticker = C_Timer.NewTicker(2, refresh) end
end, "Background")
