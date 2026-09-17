-- Everbuff · Signal.lua — the visual event channel (addon → desktop, via the recording itself).
--
-- WHY: addons cannot talk to the desktop in real time (SavedVariables only flush on /reload‑logout,
-- and no sockets/files exist in the sandbox). But the desktop ALREADY watches the screen through the
-- libobs game capture — so the screen IS the channel. On the few events the combat log cannot see
-- (quest accepted / turned in, world-enter, level-up) we render a tiny STATIC strip of colored cells
-- in the top-left corner for a few seconds; the desktop's frame sampler decodes it and files a
-- timestamped event into the session package. Encounter anchors double as exact video↔log sync marks.
--
-- STRICTLY sanctioned surface: pure rendering + normal event registration. No hooks, no IO, nothing
-- that touches the process — see the desktop's "only OBS touches WoW" rule.
--
-- VISUAL CONTRACT (decoder in everbuff-desktop/recorder/src/main.rs must match):
--   • 10 square cells in one row at ABSOLUTE top-left (0,0), each CELL px (UI units) wide.
--   • 2 bits per cell via 4 colors: 00 black · 01 white · 10 magenta · 11 cyan.
--   • cells[1..2] = sentinel [magenta, cyan] (also gives the decoder the cell width),
--     cells[3..4] = event type (4 bits), cells[5..6] = sequence (4 bits, wraps),
--     cells[7..8] = payload (4 bits), cells[9..10] = checksum ((type+seq+payload) % 16).
--   • Shown STATIC for SHOW_SECS then hidden. Never blinks (photosensitivity rule): one steady
--     pattern per event, nothing otherwise.
--
-- Event types (keep in sync with the desktop):
--   1 WORLD_ENTER · 2 QUEST_ACCEPT · 3 QUEST_COMPLETE · 4 ENCOUNTER_START · 5 ENCOUNTER_END
--   6 LEVEL_UP

local ADDON, ns = ...

local CELL = 16        -- UI units per cell; the decoder infers real pixel size from the sentinel
local SHOW_SECS = 12   -- recorder samples every ~3s → each signal is seen several times
local COLORS = {       -- bit pair → r,g,b
  [0] = { 0, 0, 0 },   -- 00 black
  [1] = { 1, 1, 1 },   -- 01 white
  [2] = { 1, 0, 1 },   -- 10 magenta
  [3] = { 0, 1, 1 },   -- 11 cyan
}

local Signal = { seq = 0, last = nil }
ns.Signal = Signal

-- ── the strip ─────────────────────────────────────────────────────────────────
local strip = CreateFrame("Frame", "EverbuffSignal", UIParent)
strip:SetSize(CELL * 10, CELL)
strip:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
strip:SetFrameStrata("TOOLTIP") -- above everything, so the capture always sees it
local cells = {}
for i = 1, 10 do
  local t = strip:CreateTexture(nil, "OVERLAY")
  t:SetSize(CELL, CELL)
  t:SetPoint("TOPLEFT", strip, "TOPLEFT", (i - 1) * CELL, 0)
  cells[i] = t
end
strip:Hide()

local hideAt = 0
strip:SetScript("OnUpdate", function()
  if hideAt > 0 and GetTime() >= hideAt then
    hideAt = 0
    strip:Hide()
  end
end)

--- Encode + show one event. `etype` 1..15, `payload` 0..15 (small dedupe/context value).
function Signal.Emit(etype, payload)
  etype = math.floor(etype or 0) % 16
  payload = math.floor(payload or 0) % 16
  Signal.seq = (Signal.seq + 1) % 16
  local seq = Signal.seq
  local check = (etype + seq + payload) % 16
  -- cell bit-pairs: sentinel M(2) C(3), then two cells per nibble (high pair first).
  local pairsOf = function(n) return math.floor(n / 4) % 4, n % 4 end
  local t1, t2 = pairsOf(etype)
  local s1, s2 = pairsOf(seq)
  local p1, p2 = pairsOf(payload)
  local c1, c2 = pairsOf(check)
  local pattern = { 2, 3, t1, t2, s1, s2, p1, p2, c1, c2 }
  for i = 1, 10 do
    local rgb = COLORS[pattern[i]]
    cells[i]:SetColorTexture(rgb[1], rgb[2], rgb[3], 1)
  end
  Signal.last = { etype = etype, seq = seq, payload = payload, check = check, pattern = pattern }
  strip:Show()
  hideAt = GetTime() + SHOW_SECS
  return Signal.last
end

-- ── event wiring (the log-invisible moments) ──────────────────────────────────
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("QUEST_ACCEPTED")
f:RegisterEvent("QUEST_TURNED_IN")
f:RegisterEvent("PLAYER_LEVEL_UP")
f:RegisterEvent("ENCOUNTER_START")
f:RegisterEvent("ENCOUNTER_END")
f:SetScript("OnEvent", function(_, event, a1, a2)
  if event == "PLAYER_ENTERING_WORLD" then
    Signal.Emit(1, 0)
  elseif event == "QUEST_ACCEPTED" then
    -- classic: (questLogIndex, questID) · mainline: (questID). Take the last non-nil number.
    local qid = a2 or a1 or 0
    Signal.Emit(2, qid)
  elseif event == "QUEST_TURNED_IN" then
    Signal.Emit(3, a1 or 0)
  elseif event == "PLAYER_LEVEL_UP" then
    Signal.Emit(6, a1 or 0)
  elseif event == "ENCOUNTER_START" then
    Signal.Emit(4, a1 or 0) -- encounterID: exact video↔log anchor (the log has this moment too)
  elseif event == "ENCOUNTER_END" then
    Signal.Emit(5, a1 or 0)
  end
end)
