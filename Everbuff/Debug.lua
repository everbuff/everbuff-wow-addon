-- Everbuff · Debug.lua - the "put Claude in the loop" bridge (Tier 2 of the dev loop).
--
-- Addons can't talk to a dev machine, but SavedVariables IS a file on disk. So we:
--   1. capture every Lua error into EverbuffDB.debug.errors (survives to the SV file),
--   2. write a diagnostics snapshot on `/eb debug`,
--   3. offer a fake 5-man roster (`/eb debug group`) so the group-dependent tabs (Crew, Readiness)
--      can be seen and tested SOLO,
--   4. show every captured error in a window on `/eb errors`, ready to copy (Ctrl+C) and paste to the dev.
-- Flow: play / repro → `/eb debug` → `/reload` (flushes SV) → the dev reads
--   WTF/Account/<acct>/SavedVariables/EverbuffJournal.lua and sees exactly what happened.

local ADDON, ns = ...
local D = {}
ns.Debug = D

-- ── error capture (chains the existing handler so BugSack etc. still work) ─────
-- Each row keeps the call stack: the 2026-10-02 save file held 49 "attempt to call a nil value" rows and nothing that
-- said where. A repeat of the row before it only counts up (`n`, `last`), so one error firing on every combat event
-- cannot push every other error out of the 50 kept.
local errbuf = {}
local orig = geterrorhandler and geterrorhandler()
if seterrorhandler then
  seterrorhandler(function(err)
    local msg, at = tostring(err), date("%m-%d %H:%M:%S")
    local prev = errbuf[#errbuf]
    if prev and prev.err == msg then
      prev.n, prev.last = (prev.n or 1) + 1, at
    else
      local stack = debugstack and debugstack(2, 8, 0) or nil
      errbuf[#errbuf + 1] = { at = at, err = msg, stack = (type(stack) == "string" and stack ~= "") and stack:gsub("|", "/") or nil }
    end
    while #errbuf > 50 do table.remove(errbuf, 1) end
    if ns.DB then ns.DB.debug = ns.DB.debug or {}; ns.DB.debug.errors = errbuf end
    if orig then return orig(err) end
  end)
end

function D.active() return ns.DB and ns.DB.debug and ns.DB.debug.fakeGroup and true or false end

-- A stand-in raid so Crew / Readiness show real-looking data with no group. `scan` feeds Readiness.
function D.members()
  return {
    { unit = "player", name = UnitNameUnmodified("player") or "You", class = "Paladin", classFile = "PALADIN", role = "TANK",   online = true, scan = { flask = true,  food = true,  rune = true } },
    { unit = "dbg2", name = "Dave",    class = "Priest", classFile = "PRIEST",     role = "HEALER",  online = true, scan = { flask = true,  food = false, rune = false } },
    { unit = "dbg3", name = "Isolyte", class = "Mage",   classFile = "MAGE",       role = "DAMAGER", online = true, scan = { flask = false, food = true,  rune = true } },
    { unit = "dbg4", name = "Brster",  class = "Rogue",  classFile = "ROGUE",      role = "DAMAGER", online = true, scan = { flask = true,  food = true,  rune = false } },
    { unit = "dbg5", name = "Sudac",   class = "Warlock",classFile = "WARLOCK",    role = "DAMAGER", online = false,scan = { flask = false, food = false, rune = false } },
  }
end

function D.snapshot()
  ns.DB.debug = ns.DB.debug or {}
  local aclOn, combatOn = ns.Logging.state()
  local sess = ns.Recorder.active()
  local nsess = 0; for _ in pairs(ns.DB.sessions) do nsess = nsess + 1 end
  local resItems, resPlayers = 0, {}
  for _, list in pairs(ns.DB.loot.reserves or {}) do
    resItems = resItems + 1
    for _, e in ipairs(list) do resPlayers[e.player] = true end
  end
  local np = 0; for _ in pairs(resPlayers) do np = np + 1 end
  ns.DB.debug.snapshot = {
    at = date("%Y-%m-%d %H:%M:%S"),
    version = ns.VERSION,
    build = select(4, GetBuildInfo()),
    logging = { acl = aclOn, combat = combatOn },
    inInstance = (select(1, IsInInstance())) and (select(2, IsInInstance())) or "no",
    session = sess and { id = sess.id, context = sess.context, markers = #sess.segments } or nil,
    storedSessions = nsess,
    reserves = { items = resItems, players = np, raid = ns.DB.loot.raidCode },
    fakeGroup = D.active(),
    errorCount = #errbuf,
  }
  ns.msg("diagnostics written - |cffffffff/reload|r then share SavedVariables\\EverbuffJournal.lua")
end

-- ── /eb errors: every captured error as plain text, in a window with a Copy button ──────────────────────────────
-- WoW gives addons no clipboard, so Copy selects the whole text and focuses the box: Ctrl+C then copies it.
-- The errors are those of this load (since the last login or /reload), from every addon, ours included.
function D.report()
  local out = {}
  out[#out + 1] = ("everbuff.gg %s · WoW %s · %s · %d error row(s) since the last login or /reload")
    :format(tostring(ns.VERSION), tostring((GetBuildInfo and select(2, GetBuildInfo())) or "?"), date("%Y-%m-%d %H:%M:%S"), #errbuf)
  for i, r in ipairs(errbuf) do
    -- the first addon in the stack that is not Blizzard's own UI code (a taint error starts in Blizzard_*)
    local from
    for a in (r.stack or ""):gmatch("AddOns/([^/%]]+)/") do
      from = from or a
      if not a:match("^Blizzard_") then from = a; break end
    end
    out[#out + 1] = ""
    out[#out + 1] = ("#%d  %s  x%d  %s%s"):format(i, from or "unknown", r.n or 1, r.at or "?", r.last and (" .. " .. r.last) or "")
    out[#out + 1] = r.err or ""
    if r.stack then out[#out + 1] = r.stack end
  end
  if #errbuf == 0 then out[#out + 1] = ""; out[#out + 1] = "No errors captured." end
  return table.concat(out, "\n")
end

local errFrame
local function buildErrors()
  local UI = ns.UI; if not (UI and UI.C) then return nil end
  local C = UI.C
  local f = CreateFrame("Frame", "EverbuffErrorsFrame", UIParent, "BackdropTemplate")
  f:SetSize(640, 420); f:SetPoint("CENTER"); f:SetFrameStrata("FULLSCREEN_DIALOG"); f:SetToplevel(true)
  f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
  f:SetBackdropColor(C.bg[1], C.bg[2], C.bg[3], 0.98); f:SetBackdropBorderColor(C.edge[1], C.edge[2], C.edge[3], 1)
  f:EnableMouse(true); f:SetMovable(true); f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
  tinsert(UISpecialFrames, "EverbuffErrorsFrame")   -- Esc closes it
  local title = UI.FS(f, "GameFontNormalLarge", C.ink); title:SetPoint("TOPLEFT", 16, -16); title:SetText("Errors")
  f.count = UI.FS(f, "GameFontHighlight", C.dim); f.count:SetPoint("LEFT", title, "RIGHT", 10, 0)
  local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
  sf:SetPoint("TOPLEFT", 16, -48); sf:SetPoint("BOTTOMRIGHT", -36, 56)
  local box = CreateFrame("EditBox", nil, sf)
  box:SetMultiLine(true); box:SetMaxLetters(0); box:SetAutoFocus(false); box:SetWidth(580)
  box:SetFontObject(UI.BODY_SM or "GameFontHighlightSmall"); box:SetTextColor(C.ink[1], C.ink[2], C.ink[3])
  box:SetScript("OnEscapePressed", function() f:Hide() end)
  -- read only: any typing puts the report back
  box:SetScript("OnTextChanged", function(self, user) if user then self:SetText(f.report or ""); self:HighlightText() end end)
  sf:SetScrollChild(box)
  f.box = box
  f.hint = UI.FS(f, "GameFontHighlight", C.dim); f.hint:SetPoint("BOTTOMLEFT", 16, 24)
  local copy = UI.Button(f, "Copy", 100, 28, function()
    box:SetFocus(); box:HighlightText()
    f.hint:SetText("Selected. Press Ctrl+C to copy.")
  end)
  copy:SetPoint("BOTTOMRIGHT", -126, 16)
  f.copy = copy
  local close = UI.Button(f, "Close", 100, 28, function() f:Hide() end)
  close:SetPoint("BOTTOMRIGHT", -16, 16)
  f:Hide()
  errFrame = f
  return f
end

function D.showErrors()
  local f = errFrame or buildErrors(); if not f then return end
  f.report = D.report()
  f.box:SetText(f.report); f.box:SetCursorPosition(0)
  f.count:SetText(("%d since the last login or /reload"):format(#errbuf))
  f.hint:SetText("")
  f:Show()
end

-- slash: /eb debug [group|clear]
function D.command(rest)
  rest = (rest or ""):gsub("^%s+", "")
  if rest == "group" then
    ns.DB.debug = ns.DB.debug or {}
    ns.DB.debug.fakeGroup = not ns.DB.debug.fakeGroup
    ns.msg("fake group " .. (ns.DB.debug.fakeGroup and "|cff47c97eON|r - open Crew/Readiness" or "|cffe25a5aoff|r"))
    if ns.UI then ns.UI.onRosterUpdate() end
  elseif rest == "clear" then
    if ns.DB.debug then ns.DB.debug.errors = {}; errbuf = {} end
    ns.msg("debug errors cleared")
  else
    D.snapshot()
    if #errbuf > 0 then ns.msg(("|cffe25a5a%d error(s) captured|r - included in the snapshot"):format(#errbuf)) end
  end
end
