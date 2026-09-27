-- Everbuff · Signal.lua - the visual event channel (addon → desktop, via the recording itself).
--
-- WHY: addons cannot talk to the desktop in real time (SavedVariables only flush on /reload‑logout,
-- and no sockets/files exist in the sandbox). But the desktop ALREADY watches the screen through the
-- libobs game capture - so the screen IS the channel. On the few events the combat log cannot see
-- (quest accepted / turned in, world-enter, level-up) we render a tiny STATIC strip of colored cells
-- in the top-left corner for a few seconds; the desktop's frame sampler decodes it and files a
-- timestamped event into the session package. Encounter anchors double as exact video↔log sync marks.
--
-- STRICTLY sanctioned surface: pure rendering + normal event registration. No hooks, no IO, nothing
-- that touches the process - see the desktop's "only OBS touches WoW" rule.
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
-- Event types (keep in sync with the desktop, recorder/src/main.rs decode_signal and the CVEVENT consumer):
--   1 WORLD_ENTER · 2 QUEST_ACCEPT · 3 QUEST_COMPLETE · 4 ENCOUNTER_START · 5 ENCOUNTER_END
--   6 LEVEL_UP (payload level % 16) · 7 FIGHT_START (payload fightSeq % 16) · 8 FIGHT_END (payload outcome:
--   1 kill, 2 wipe, 3 death, 4 fled) · 9 DEATH (payload level % 16) · 10 RARE_LOOT (payload quality rank 3..6)
--   11 ZONE_CHANGE (payload 0) · 12 SESSION_START (payload last hex digit of the addon session id)
-- Payload is 4 bits: a marker on the master clock, not a data channel. Ids come from the save file, which the
-- desktop joins by time (architecture 5.2).

local ADDON, ns = ...

local CELL = 16        -- UI units per cell; the decoder infers real pixel size from the sentinel
local SHOW_SECS = 12   -- recorder samples every ~3s → each signal is seen several times
local COLORS = {       -- bit pair → r,g,b
  [0] = { 0, 0, 0 },   -- 00 black
  [1] = { 1, 1, 1 },   -- 01 white
  [2] = { 1, 0, 1 },   -- 10 magenta
  [3] = { 0, 1, 1 },   -- 11 cyan
}

local Signal = { seq = 0, last = nil, history = {} }
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
  Signal.last = { etype = etype, seq = seq, payload = payload, check = check, pattern = pattern, at = GetTime() }
  Signal.history[#Signal.history + 1] = Signal.last
  while #Signal.history > 32 do table.remove(Signal.history, 1) end
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

-- ── moments the other files report (story events, loot, fights, sessions) ─────
local STORY = { DEATH = 9, ZONE = 11 }
local OUTCOME = { kill = 1, wipe = 2, death = 3, fled = 4 }
local Q_RANK = { ff9d9d9d = 0, ffffffff = 1, ff1eff00 = 2, ff0070dd = 3, ffa335ee = 4, ffff8000 = 5, ffe6cc80 = 6 }

--- Emitter.event calls this for every story kind; only the mapped kinds draw a marker.
function Signal.Story(kind, d)
  local etype = STORY[kind]
  if not etype then return nil end
  local lvl = (d and tonumber(d.level)) or (UnitLevel and tonumber(UnitLevel("player"))) or 0
  return Signal.Emit(etype, etype == 9 and (lvl % 16) or 0)
end

--- Fights.lua: a fight began (seq is the running fight counter) or ended with an outcome word.
function Signal.FightStart(seq) return Signal.Emit(7, (tonumber(seq) or 0) % 16) end
function Signal.FightEnd(outcome) return Signal.Emit(8, OUTCOME[outcome] or 0) end

--- Emitter loot path: rare and better pickups get a marker, keyed by the 8-hex quality color.
function Signal.Loot(qhex)
  local rank = Q_RANK[(qhex or ""):lower()]
  if rank and rank >= 3 then return Signal.Emit(10, rank) end
  return nil
end

--- Segments.lua: a new addon session record started; the last hex digit of its id rides along.
function Signal.Session(id)
  local tail = id and tonumber(tostring(id):sub(-1), 16) or 0
  return Signal.Emit(12, tail)
end
