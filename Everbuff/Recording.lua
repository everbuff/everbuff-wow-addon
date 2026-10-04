-- Everbuff.GG · Recording.lua - the Combat Log tab (fight browser).
--
-- Master list of every fight (from Fights.lua): time · who you faced · duration · result.
-- Click a fight to drill into its detail: party/raid, buff/debuff timeline, gear + swaps, and any
-- readable character stats - all timestamped. Damage/DPS is not here by design (it lives in the
-- engine combat-log file the desktop parses; on the Secret-Values client it is unreadable to addons).

local ADDON, ns = ...
local UI = ns.UI
local C = ns.UI.C

local listView, detailView, memberView, ticker, listRebuild
local openMember   -- forward declaration (set once memberView exists)

-- gear slot id → readable name (mirrors Fights.lua SLOTS, for the initial-loadout column)
local GEAR_SLOT = {
  [1] = "Head", [2] = "Neck", [3] = "Shoulder", [5] = "Chest", [6] = "Waist",
  [7] = "Legs", [8] = "Feet", [9] = "Wrist", [10] = "Hands", [11] = "Finger 1",
  [12] = "Finger 2", [13] = "Trinket 1", [14] = "Trinket 2", [15] = "Back",
  [16] = "Main hand", [17] = "Off hand", [18] = "Ranged",
}

-- ── formatting helpers ─────────────────────────────────────────────────────────
local function fmtDur(sec)
  sec = math.floor((sec or 0) + 0.5)
  if sec >= 60 then return ("%d:%02d"):format(math.floor(sec / 60), sec % 60) end
  return sec .. "s"
end
local function fmtOff(t) return ("+%.1fs"):format(t or 0) end
-- result glyphs (texture escapes) so kill / wipe / death never rely on color alone
local GLYPH = {
  kill  = "|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12:0:0|t ",
  wipe  = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:12:12:0:0|t ",
  death = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:12:12:0:0|t ",
  fled  = "|TInterface\\RaidFrame\\ReadyCheck-Waiting:12:12:0:0|t ",
}
local RESULT = {
  kill  = { "Kill",  C.green },
  wipe  = { "Wipe",  C.red },
  death = { "Death", C.red },
  fled  = { "Fled",  C.dim },
}
local function foesText(f)
  if f.bossName then return f.bossName end
  local n = #f.foes
  if n == 0 then return "unknown" end
  if n <= 2 then return table.concat(f.foes, ", ") end
  return ("%s, %s +%d more"):format(f.foes[1], f.foes[2], n - 2)
end

-- text search over a fight: foe names or zone contain the query (case-insensitive, plain find)
local function fightMatchesText(f, q)
  if not q or q == "" then return true end
  local hay = (foesText(f) .. " " .. (f.zone or "")):lower()
  return hay:find(q:lower(), 1, true) ~= nil
end

-- sort a fight list by a column key (time | foe | dur | res); ties break newest-first
local function sortFights(list, key, asc)
  local out = {}
  for _, f in ipairs(list) do out[#out + 1] = f end
  local function val(f)
    if key == "foe" then return foesText(f):lower()
    elseif key == "loc" then return (f.zone or ""):lower()
    elseif key == "coords" then return f.x or 0
    elseif key == "dur" then return f.duration or 0
    elseif key == "res" then return f.outcome or ""
    else return f.startEpoch or 0 end
  end
  table.sort(out, function(a, b)
    local va, vb = val(a), val(b)
    if va == vb then return (a.startEpoch or 0) > (b.startEpoch or 0) end
    if asc then return va < vb else return va > vb end
  end)
  return out
end

-- ══ DETAIL VIEW ═════════════════════════════════════════════════════════════════
-- ── time reconstruction: character state at a moment T (seconds into the fight) ──
local function statAt(f, T)
  if not f.stats or #f.stats == 0 then return nil end
  local pick = f.stats[1]
  for _, s in ipairs(f.stats) do if (s.t or 0) <= T + 1e-6 then pick = s else break end end
  return pick
end
-- replay ANY combatant's aura gain/lose log up to T → the auras active at that moment (buffs first)
local function activeAuras(log, T)
  local active = {}
  if log then
    for _, a in ipairs(log) do
      if (a.t or 0) <= T + 1e-6 then
        -- identity: instance id when we have it (survives hidden names), else the name
        local key = (a.inst and ("#" .. tostring(a.inst)) or (a.name or "?")) .. (a.debuff and "d" or "b")
        if a.gain then active[key] = a else active[key] = nil end
      end
    end
  end
  local list = {}
  for _, a in pairs(active) do list[#list + 1] = a end
  table.sort(list, function(x, y)
    if (x.debuff or false) ~= (y.debuff or false) then return not x.debuff end
    return (x.name or "~") < (y.name or "~")   -- unknowns sort last
  end)
  return list
end

-- Render-time repair of an aura log. The beta client hides aura data a few seconds into combat; a log
-- recorded that way shows EVERY active aura "lost" at one instant and all of them "gained" again later.
-- That is a hidden window, not a real loss, and reading it as one leads to wrong conclusions about the
-- fight. Rule: a cluster at time t containing ONLY losses, that empties the whole active set, strictly
-- inside the fight (0.5s < t < duration - 0.5s), whose identities are ALL gained again later -> drop the
-- losses and the first later re-gain of each identity. A death at the end is untouched (t at duration);
-- a partial loss is untouched; an all-lost-never-regained (e.g. dispel) is untouched.
local function auraId(a) return (a.inst and ("#" .. tostring(a.inst)) or (a.name or "?")) .. (a.debuff and "d" or "b") end
local function repairAuraLog(log, duration)
  if not log or #log == 0 then return log, 0 end
  duration = duration or math.huge
  local drop = {}                       -- entry -> true
  local active = {}                     -- id -> true, replayed in order
  local i, n = 1, #log
  while i <= n do
    local t = log[i].t or 0
    local j = i
    while j + 1 <= n and (log[j + 1].t or 0) == t do j = j + 1 end   -- cluster [i..j] at the same t
    local losses, anyGain = {}, false
    for k = i, j do if log[k].gain then anyGain = true else losses[#losses + 1] = log[k] end end
    local activeN = 0; for _ in pairs(active) do activeN = activeN + 1 end
    local emptiesAll = (not anyGain) and #losses >= 2 and #losses == activeN
    if emptiesAll then
      for _, e in ipairs(losses) do if not active[auraId(e)] then emptiesAll = false; break end end
    end
    if emptiesAll and t > 0.5 and t < duration - 0.5 then
      -- are ALL of them gained again later? find the first later gain per identity
      local regain, all = {}, true
      for _, e in ipairs(losses) do
        local id, found = auraId(e), nil
        for m = j + 1, n do if log[m].gain and auraId(log[m]) == id then found = log[m]; break end end
        if found then regain[id] = found else all = false; break end
      end
      if all then
        for _, e in ipairs(losses) do drop[e] = true end
        for _, g in pairs(regain) do drop[g] = true end
        i = j + 1                     -- active set unchanged: the auras never left
      else
        for k = i, j do local e = log[k]; if e.gain then active[auraId(e)] = true else active[auraId(e)] = nil end end
        i = j + 1
      end
    else
      for k = i, j do local e = log[k]; if not drop[e] then if e.gain then active[auraId(e)] = true else active[auraId(e)] = nil end end end
      i = j + 1
    end
  end
  local out, removed = {}, 0
  for _, e in ipairs(log) do if drop[e] then removed = removed + 1 else out[#out + 1] = e end end
  return out, removed
end
local repairCache = setmetatable({}, { __mode = "k" })   -- log table -> { out, removed }; never persisted
local function repaired(log, duration)
  if not log then return nil, 0 end
  local c = repairCache[log]
  if not c then local out, removed = repairAuraLog(log, duration); c = { out = out, removed = removed }; repairCache[log] = c end
  return c.out, c.removed
end

-- loot rows that belong to a fight: picked up during it or within the looting window right after
local LOOT_TAIL = 20
local function fightLoot(f)
  local out = {}
  local s = f.startEpoch or 0
  local e = s + (f.duration or 0) + LOOT_TAIL
  for _, l in ipairs((ns.DB and ns.DB.loot.log) or {}) do
    local t = l.t or 0
    if t >= s and t <= e and ns.isMine(l) then out[#out + 1] = l end
  end
  return out
end
-- loot row hex color ("ff0070dd") → rgb table
local function hexColor(q)
  q = (q or "ffffffff"):lower()
  if #q ~= 8 then return { 1, 1, 1 } end
  return { (tonumber(q:sub(3, 4), 16) or 255) / 255, (tonumber(q:sub(5, 6), 16) or 255) / 255, (tonumber(q:sub(7, 8), 16) or 255) / 255 }
end
local function fmtCoin(c)
  c = math.floor(tonumber(c) or 0)
  local g, s, cp = math.floor(c / 10000), math.floor((c % 10000) / 100), c % 100
  local out = {}
  if g > 0 then out[#out + 1] = g .. "g" end
  if s > 0 then out[#out + 1] = s .. "s" end
  if cp > 0 or #out == 0 then out[#out + 1] = cp .. "c" end
  return table.concat(out, " ")
end

-- item quality → name color (matches WoW's rarity colors)
local Q_COLOR = {
  [0] = { 0.62, 0.62, 0.62 }, [1] = { 1, 1, 1 }, [2] = { 0.12, 1, 0 }, [3] = { 0, 0.44, 0.87 },
  [4] = { 0.64, 0.21, 0.93 }, [5] = { 1, 0.5, 0 }, [6] = { 0.9, 0.8, 0.5 }, [7] = { 0, 0.8, 1 },
}

local function buildDetail(content)
  local v = CreateFrame("Frame", nil, content)
  v:SetAllPoints(content); v:Hide()

  local back = UI.Button(v, "< Back", 70, 24, function() detailView:Hide(); listView:Show(); if listRebuild then listRebuild() end end)
  back:SetPoint("TOPLEFT", 12, -12)

  v.titleFS = UI.FS(v, "GameFontNormalLarge"); v.titleFS:SetPoint("TOPLEFT", 92, -14); v.titleFS:SetWidth(500); v.titleFS:SetJustifyH("LEFT")
  v.metaFS = UI.FS(v, "GameFontHighlightSmall", C.dim); v.metaFS:SetPoint("TOPLEFT", 14, -42); v.metaFS:SetWidth(690); v.metaFS:SetJustifyH("LEFT")

  -- delete THIS fight (a test pull, a misfire). Two clicks within 5s; the first arms it.
  local delArmedAt = 0
  v.delBtn = UI.Button(v, "Delete", 110, 24, function(b)
    if not v.fight then return end
    if (GetTime() - delArmedAt) < 5 then
      local list = (ns.DB and ns.DB.combat.fights) or {}
      for i = #list, 1, -1 do
        local g = list[i]
        if g == v.fight or (g.uid and v.fight.uid and g.uid == v.fight.uid) then table.remove(list, i) end
      end
      delArmedAt = 0; b.text:SetText("Delete")
      detailView:Hide(); listView:Show(); if listRebuild then listRebuild() end
    else
      delArmedAt = GetTime(); b.text:SetText("Confirm delete")
      if C_Timer and C_Timer.After then C_Timer.After(5, function() if (GetTime() - delArmedAt) >= 5 then b.text:SetText("Delete") end end) end
    end
  end)
  v.delBtn:SetPoint("TOPRIGHT", -14, -12)
  -- what else happened around this fight: the Timeline filtered to the fight's span (+ looting window)
  v.tlBtn = UI.Button(v, "Timeline", 90, 24, function()
    local f = v.fight; if not (f and ns.OpenTimelineWindow) then return end
    local s0 = f.startEpoch or 0
    ns.OpenTimelineWindow(s0 - 5, s0 + (f.duration or 0) + 20, foesText(f) .. "  " .. date("%H:%M", s0))
  end)
  v.tlBtn:SetPoint("RIGHT", v.delBtn, "LEFT", -8, 0)

  -- scrubber: drag to inspect the character's state at any moment of the fight
  local slider = CreateFrame("Slider", "EverbuffFightScrubber", v, "OptionsSliderTemplate")
  slider:SetOrientation("HORIZONTAL"); slider:SetWidth(560); slider:SetHeight(16)
  slider:SetPoint("TOPLEFT", 16, -70)
  slider:SetObeyStepOnDrag(true)
  if _G.EverbuffFightScrubberLow then _G.EverbuffFightScrubberLow:SetText("pull") end
  if _G.EverbuffFightScrubberHigh then _G.EverbuffFightScrubberHigh:SetText("end") end
  if _G.EverbuffFightScrubberText then _G.EverbuffFightScrubberText:SetText("") end
  slider:SetScript("OnValueChanged", function(_, val) v.curT = val; if v.renderState then v.renderState() end end)
  v.slider = slider
  -- landmarks: small clickable ticks above the scrubber for key moments (death, gear swaps, enemies
  -- joining). Click a tick to jump the scrubber there; hover for what it is. Pooled.
  v.ticks = {}
  local tickN = 0
  local function tick(x, color, label, t)
    tickN = tickN + 1
    local b = v.ticks[tickN]
    if not b then
      b = CreateFrame("Button", nil, v); b:SetSize(7, 10)
      b.tex = b:CreateTexture(nil, "OVERLAY"); b.tex:SetAllPoints()
      b:SetScript("OnEnter", function(s) GameTooltip:SetOwner(s, "ANCHOR_TOP"); GameTooltip:SetText(s.label or "", 1, 1, 1); GameTooltip:Show() end)
      b:SetScript("OnLeave", function() GameTooltip:Hide() end)
      b:SetScript("OnClick", function(s) if s.t and v.slider then v.slider:SetValue(s.t) end end)
      v.ticks[tickN] = b
    end
    b:ClearAllPoints(); b:SetPoint("BOTTOMLEFT", v.slider, "TOPLEFT", x - 3, 2)
    b.tex:SetColorTexture(color[1], color[2], color[3], 1)
    b.label = label; b.t = t; b:Show()
  end
  v.placeLandmarks = function(f, dur)
    tickN = 0
    local W = v.slider:GetWidth() or 560
    local function place(t, color, label)
      if dur > 0 then tick((math.max(0, math.min(t or 0, dur)) / dur) * W, color, label, t) end
    end
    if f.outcome == "death" or f.outcome == "wipe" then place(dur, C.red, f.outcome == "death" and "Your death" or "Wipe") end
    if f.gear and f.gear.swaps then for _, sw in ipairs(f.gear.swaps) do place(sw.t, C.data, "Swap: " .. (sw.name or "?")) end end
    if f.uses then for _, u in ipairs(f.uses) do place(u.t, C.gold, "Used: " .. (u.name or "?")) end end
    if f.enemies then for _, e in ipairs(f.enemies) do if (e.firstT or 0) > 0.5 then place(e.firstT, C.dim, (e.name or "?") .. " joins") end end end
    for j = tickN + 1, #v.ticks do v.ticks[j]:Hide() end
  end
  v.timeFS = UI.FS(v, "GameFontHighlightSmall", C.gold); v.timeFS:SetPoint("TOPLEFT", 16, -92); v.timeFS:SetWidth(560); v.timeFS:SetJustifyH("LEFT")

  local sf, child = UI.ScrollChild(v)
  sf:SetPoint("TOPLEFT", 12, -112); sf:SetPoint("BOTTOMRIGHT", -28, 12)
  child.fs = {}; child.tex = {}
  v.child = child
  local WIDTH = 690

  -- ── pooled renderers (absolute-positioned; y grows downward) ──
  local fn, tn = 0, 0
  local function cell(x, y, w, text, color, justify, template)
    fn = fn + 1
    local fs = child.fs[fn]
    if not fs then fs = ns.UI.FS(child, "GameFontHighlightSmall"); child.fs[fn] = fs end
    fs:SetFontObject(ns.UI.Font(template) or ns.UI.BODY_SM or GameFontHighlightSmall)
    fs:ClearAllPoints(); fs:SetPoint("TOPLEFT", x, -y)
    fs:SetWidth(w); fs:SetJustifyH(justify or "LEFT")
    local c = color or C.ink
    fs:SetText(text or ""); fs:SetTextColor(c[1], c[2], c[3]); fs:Show()
    return fs
  end
  local function rule(x, y, w, color)
    tn = tn + 1
    local t = child.tex[tn]
    if not t then t = child:CreateTexture(nil, "ARTWORK"); child.tex[tn] = t end
    t:ClearAllPoints(); t:SetPoint("TOPLEFT", x, -y); t:SetSize(w, 1)
    local c = color or C.line; t:SetColorTexture(c[1], c[2], c[3], 1); t:Show()
    return t
  end
  local function heading(y, text)
    y = y + 12
    cell(0, y, WIDTH, text, C.gold, "LEFT", GameFontNormal)
    y = y + 20; rule(0, y, WIDTH); return y + 8
  end
  -- clickable name (opens that party/raid member's aura-timeline view). Pooled Buttons.
  child.mbtn = {}
  local mbn = 0
  local function nameButton(x, y, w, name, r, g, b, member)
    mbn = mbn + 1
    local btn = child.mbtn[mbn]
    if not btn then
      btn = CreateFrame("Button", nil, child)
      btn.hl = btn:CreateTexture(nil, "BACKGROUND"); btn.hl:SetAllPoints(); btn.hl:SetColorTexture(C.panel2[1], C.panel2[2], C.panel2[3], 0)
      btn.fs = ns.UI.FS(btn, "GameFontHighlightSmall"); btn.fs:SetPoint("LEFT", 0, 0)
      btn:SetScript("OnEnter", function(s) s.hl:SetColorTexture(C.panel2[1], C.panel2[2], C.panel2[3], 1) end)
      btn:SetScript("OnLeave", function(s) s.hl:SetColorTexture(0, 0, 0, 0) end)
      btn:SetScript("OnClick", function(s) if openMember and s.member then openMember(v.fight, s.member) end end)
      child.mbtn[mbn] = btn
    end
    btn:SetSize(w, 16); btn:ClearAllPoints(); btn:SetPoint("TOPLEFT", x, -y)
    btn.fs:SetWidth(w - 4); btn.fs:SetJustifyH("LEFT")
    btn.fs:SetText((name or "?") .. "   |cff8c9197>|r"); btn.fs:SetTextColor(r, g, b)
    btn.member = member; btn:Show()
    return btn
  end
  -- a label/value card in a column; returns the column's new y
  local function card(colX, colW, y, title, entries)
    if #entries == 0 then return y end
    cell(colX, y, colW, title, C.dim, "LEFT", GameFontNormalSmall); y = y + 17
    for _, e in ipairs(entries) do
      cell(colX + 8, y, 116, e[1], C.dim)
      cell(colX + 128, y, colW - 128, e[2], C.ink)
      y = y + 15
    end
    return y + 10
  end

  -- two-column stat grid for a single snapshot; returns the new y
  local PRIM = { "Str", "Agi", "Sta", "Int", "Spi" }
  local RESI = { "Arcane", "Fire", "Frost", "Nature", "Shadow" }
  local function statGrid(y, s)
    local COLW, LX, RX = 330, 8, 358
    local attrs = {}
    if s.prim then for i = 1, 5 do if s.prim[i] then attrs[#attrs + 1] = { PRIM[i], tostring(s.prim[i]) } end end end
    local off = {}
    if s.ap then off[#off + 1] = { "Attack power", tostring(s.ap) } end
    if s.rap then off[#off + 1] = { "Ranged AP", tostring(s.rap) } end
    if s.spellPower and s.spellPower > 0 then off[#off + 1] = { "Spell power", tostring(s.spellPower) } end
    if s.crit then off[#off + 1] = { "Melee crit", ("%.1f%%"):format(s.crit) } end
    if s.spellCrit then off[#off + 1] = { "Spell crit", ("%.1f%%"):format(s.spellCrit) } end
    if s.haste and s.haste ~= 0 then off[#off + 1] = { "Haste", ("%.1f%%"):format(s.haste) } end
    if s.hit and s.hit ~= 0 then off[#off + 1] = { "Hit", ("%.0f%%"):format(s.hit) } end
    if s.mastery and s.mastery ~= 0 then off[#off + 1] = { "Mastery", ("%.1f%%"):format(s.mastery) } end
    local wpn = {}
    if s.weapon and s.weapon.mainLow then
      local w = s.weapon
      local dps = (w.mainSpeed and w.mainSpeed > 0) and (((w.mainLow + w.mainHigh) / 2) / w.mainSpeed) or nil
      wpn[#wpn + 1] = { "Main hand", ("%d-%d @ %.2fs"):format(w.mainLow, w.mainHigh, w.mainSpeed or 0) }
      if dps then wpn[#wpn + 1] = { "  DPS", ("%.1f"):format(dps) } end
      if w.offLow and w.offHigh and w.offLow > 0 then
        wpn[#wpn + 1] = { "Off hand", ("%d-%d @ %.2fs"):format(w.offLow, w.offHigh, w.offSpeed or 0) }
      end
    end
    local def = {}
    if s.armor then def[#def + 1] = { "Armor", tostring(s.armor) } end
    if s.defense then def[#def + 1] = { "Defense", tostring(s.defense) } end
    if s.dodge then def[#def + 1] = { "Dodge", ("%.1f%%"):format(s.dodge) } end
    if s.parry and s.parry > 0 then def[#def + 1] = { "Parry", ("%.1f%%"):format(s.parry) } end
    if s.block and s.block > 0 then def[#def + 1] = { "Block", ("%.1f%%"):format(s.block) } end
    local res = {}
    if s.resist then for _, k in ipairs(RESI) do if s.resist[k] then res[#res + 1] = { k, tostring(s.resist[k]) } end end end
    local pools = {}
    if s.hp then pools[#pools + 1] = { "Health", tostring(s.hp) } end
    if s.mana then pools[#pools + 1] = { "Mana/energy", tostring(s.mana) } end
    local top = y
    local ly = card(LX, COLW, top, "Attributes", attrs)
    ly = card(LX, COLW, ly, "Weapon", wpn)
    ly = card(LX, COLW, ly, "Pools", pools)
    local ry = card(RX, COLW, top, "Offense", off)
    ry = card(RX, COLW, ry, "Defense", def)
    ry = card(RX, COLW, ry, "Resistances", res)
    y = math.max(ly, ry)
    if ly == top and ry == top then cell(8, y, WIDTH - 8, "(values restricted on this client)", C.dim); y = y + 16 end
    return y
  end

  -- ── aura icon strip: a horizontal run of buff/debuff icons (green ring = buff, red = debuff) with a
  --    hover tooltip for each. Pooled Buttons so scrubbing is cheap. Wraps within the given width. ──
  child.abtn = {}
  local an = 0
  local ICON, PAD = 20, 2
  local function auraStrip(x, y, w, list)
    if #list == 0 then cell(x, y + 2, w, "none", C.dim); return 16 end
    local cols = math.max(1, math.floor(w / ICON))
    for i, a in ipairs(list) do
      local idx = i - 1
      local cx = x + (idx % cols) * ICON
      local cy = y + math.floor(idx / cols) * ICON
      an = an + 1
      local b = child.abtn[an]
      if not b then
        b = CreateFrame("Button", nil, child)
        b:SetSize(ICON - PAD, ICON - PAD)
        b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints()
        b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetPoint("CENTER"); b.icon:SetSize(ICON - PAD - 2, ICON - PAD - 2)
        b:SetScript("OnEnter", function(s)
          GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
          GameTooltip:SetText(s.auraName or "?", 1, 1, 1)
          GameTooltip:AddLine(s.auraKind or "", 0.6, 0.6, 0.6); GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        child.abtn[an] = b
      end
      b:ClearAllPoints(); b:SetPoint("TOPLEFT", cx, -cy)
      b.icon:SetTexture(a.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
      local rc = a.debuff and C.red or C.green
      b.bg:SetColorTexture(rc[1], rc[2], rc[3], 1)
      b.auraName = a.name or "Unknown aura (hidden by the client in combat)"; b.auraKind = a.debuff and "Debuff" or "Buff"
      b:Show()
    end
    local rows = math.floor((#list - 1) / cols) + 1
    return rows * ICON
  end
  -- one combatant: colored name on the left, its live buff/debuff icons on the right; returns new y
  local NAMEW = 150
  local function combatantRow(y, name, r, g, b, auras, member)
    if member then nameButton(8, y + 1, NAMEW, name, r, g, b, member)   -- clickable: opens their timeline
    else cell(8, y + 2, NAMEW, name, { r, g, b }) end
    local h = auraStrip(8 + NAMEW + 6, y, WIDTH - (8 + NAMEW + 6) - 8, auras)
    return y + math.max(16, h) + 4
  end
  -- readable item name from structured gear ({name,icon,quality}) or legacy raw/link string
  local function itemName(it)
    if type(it) == "table" then return it.name or "?" end
    if type(it) == "string" then return it:match("%[(.-)%]") or it end
    return "(empty)"
  end
  -- one gear line: inline icon + quality-colored name (structured items only carry safe fields)
  local function gearLine(x, y, it)
    if type(it) ~= "table" then cell(x, y + 1, WIDTH - x, itemName(it), C.ink); return end
    local icon = it.icon and ("|T" .. it.icon .. ":14:14:0:0|t ") or ""
    cell(x, y + 1, WIDTH - x, icon .. (it.name or "?"), Q_COLOR[it.quality or 1] or C.ink)
  end

  -- rebuild the scroll for the current scrubber time (v.curT); called on every slider move
  v.renderState = function()
    local f = v.fight; if not f then return end
    fn, tn, mbn, an = 0, 0, 0, 0
    local dur = math.max(f.duration or 0, 0)
    local T = math.min(v.curT or dur, dur)
    v.timeFS:SetText(("Showing the fight at |cff35eebb+%.1fs|r of %s   ·   drag to scrub"):format(T, fmtDur(dur)))
    local y = 0
    local playerLog, bridged = repaired(f.auras, dur)
    if (f.auraBlind or 0) > 0 or bridged > 0 then
      cell(0, y, WIDTH, "The client hid buff data for part of this fight; the timeline carries the last known state across those gaps.", C.dim); y = y + 18
    end

    -- Hardcore death recap: when the fight killed you (or wiped the group), lead with how it ended.
    -- The scrubber defaults to the final moment, so the state below IS your state at death.
    if f.outcome == "death" or f.outcome == "wipe" then
      local who = foesText(f)
      local headline = (f.outcome == "death") and ("You were slain by " .. who) or ("Your group wiped to " .. who)
      cell(0, y, WIDTH, headline, C.red, "LEFT", GameFontNormal); y = y + 20
      rule(0, y, WIDTH, C.red); y = y + 8
      local rcoords = UI.fmtCoords(f.x, f.y)
      cell(8, y, WIDTH - 8, ("%s%s   ·   level %s   ·   %s   ·   lasted %s"):format(
        f.zone or "?", rcoords ~= "" and ("   ·   " .. rcoords) or "", tostring(f.level or "?"),
        date("%H:%M:%S", (f.startEpoch or 0) + math.floor(dur)), fmtDur(dur)), C.ink); y = y + 16
      cell(8, y, WIDTH - 8, "Your state at the moment of death is below. Scrub back to watch the fight unfold.", C.dim); y = y + 22
    end

    -- ── YOUR GROUP: every player and the buffs/debuffs they had at this exact moment ──
    y = heading(y, "Your group  ·  buffs & debuffs at this moment")
    if f.group and #f.group > 0 then
      for _, m in ipairs(f.group) do
        local r, g, b = UI.ClassColor(m.class)
        local log = m.me and playerLog or repaired(f.memberAuras and f.memberAuras[m.name], dur)
        local deadTag = (m.deadT and m.deadT <= T + 1e-6) and ("  |cffe5484ddied at +%.0fs|r"):format(m.deadT) or ""
        y = combatantRow(y, (m.name or "?") .. (m.me and "  (you)" or "") .. deadTag, r, g, b, activeAuras(log, T),
          (not m.me) and m or nil)   -- other members are clickable -> their aura timeline
      end
    else
      local _, cls; if UnitClass then _, cls = UnitClass("player") end
      local r, g, b = UI.ClassColor(cls)
      y = combatantRow(y, "You", r, g, b, activeAuras(playerLog, T))
    end

    -- ── ENEMIES: every monster present by now and its buffs/debuffs at this moment ──
    y = heading(y, "Enemies  ·  buffs & debuffs at this moment")
    local vis = {}
    if f.enemies then for _, e in ipairs(f.enemies) do if (e.firstT or 0) <= T + 1e-6 then vis[#vis + 1] = e end end end
    if #vis > 0 then
      local counts, seen = {}, {}                       -- disambiguate duplicate mob names (X, X #2, ...)
      for _, e in ipairs(vis) do counts[e.name or "?"] = (counts[e.name or "?"] or 0) + 1 end
      for _, e in ipairs(vis) do
        local base = e.name or "?"
        local nm = base
        if (counts[base] or 0) > 1 then seen[base] = (seen[base] or 0) + 1; nm = base .. "  #" .. seen[base] end
        y = combatantRow(y, nm, C.red[1], C.red[2], C.red[3], activeAuras(repaired(e.auras, dur), T))
      end
    else
      cell(8, y, WIDTH - 8, "No monster auras captured for this fight.", C.dim); y = y + 16
    end

    -- ── LOOT picked up during this fight and the looting window right after it ──
    local loot = fightLoot(f)
    y = heading(y, ("Loot  (%d)"):format(#loot))
    if #loot > 0 then
      for _, l in ipairs(loot) do
        if l.money then
          cell(8, y, 300, "|TInterface\\Icons\\INV_Misc_Coin_01:14:14:0:0|t " .. fmtCoin(l.money), C.gold)
        else
          local icon = l.icon and ("|T" .. tostring(l.icon) .. ":14:14:0:0|t ") or ""
          cell(8, y, 300, icon .. (l.item or "?") .. ((l.count or 1) > 1 and ("  x" .. l.count) or ""), hexColor(l.q))
        end
        cell(316, y, 220, l.src or "", C.dim)
        cell(540, y, 150, date("%H:%M:%S", l.t or 0), C.dim)
        y = y + 16
      end
    else
      cell(8, y, WIDTH - 8, "Nothing picked up during this fight.", C.dim); y = y + 16
    end

    -- ── ITEMS USED: potions, food, bandages, scrolls; dim until the scrubber passes them ──
    y = heading(y, ("Items used  (%d)"):format(#(f.uses or {})))
    if f.uses and #f.uses > 0 then
      for _, u in ipairs(f.uses) do
        local done = (u.t or 0) <= T + 1e-6
        local icon = u.icon and ("|T" .. tostring(u.icon) .. ":14:14:0:0|t ") or ""
        cell(8, y + 1, 72, fmtOff(u.t), done and C.gold or C.dim)
        cell(88, y + 1, WIDTH - 88, icon .. (u.name or "?"), done and C.ink or C.dim)
        y = y + 18
      end
    else
      cell(8, y, WIDTH - 8, "No potions, food or other items used in this fight.", C.dim); y = y + 16
    end

    -- ── GEAR worn at this moment (initial loadout + swaps applied up to T), icon + name ──
    y = heading(y, "Gear worn")
    if f.gear and f.gear.initial and next(f.gear.initial) then
      local worn = {}
      for slot, it in pairs(f.gear.initial) do worn[slot] = it end
      if f.gear.swaps then for _, sw in ipairs(f.gear.swaps) do if (sw.t or 0) <= T + 1e-6 and sw.slot then worn[sw.slot] = sw.to end end end
      local slots = {}
      for slot in pairs(worn) do slots[#slots + 1] = slot end
      table.sort(slots)
      for _, slot in ipairs(slots) do
        cell(8, y + 1, 92, GEAR_SLOT[slot] or ("Slot " .. slot), C.dim)
        gearLine(108, y, worn[slot]); y = y + 18
      end
    else
      cell(8, y, WIDTH - 8, "Gear not captured for this fight.", C.dim); y = y + 16
    end
    if f.gear and f.gear.swaps and #f.gear.swaps > 0 then
      cell(8, y, WIDTH - 8, "Swaps during the fight", C.dim, "LEFT", GameFontNormalSmall); y = y + 17
      for _, sw in ipairs(f.gear.swaps) do
        local done = (sw.t or 0) <= T + 1e-6
        cell(8, y + 1, 72, fmtOff(sw.t), done and C.ink or C.dim)
        cell(88, y + 1, WIDTH - 88, ("%s:  %s  ->  %s"):format(sw.name or "?", itemName(sw.from), itemName(sw.to)), done and C.ink or C.dim)
        y = y + 18
      end
    end

    -- ── CHARACTER STATS at this moment (secondary; most are Secret Values on this client) ──
    y = heading(y, "Your character stats at this moment")
    local s = statAt(f, T)
    if s then
      if s.ilvl then cell(8, y, WIDTH - 8, ("Item level %d"):format(math.floor(s.ilvl + 0.5)), C.dim); y = y + 16 end
      y = statGrid(y, s)
    else
      cell(8, y, WIDTH - 8, "Character stats are not readable on this client (Secret Values). The combat-log file carries them.", C.dim); y = y + 16
    end

    for j = fn + 1, #child.fs do child.fs[j]:Hide() end
    for j = tn + 1, #child.tex do child.tex[j]:Hide() end
    for j = mbn + 1, #child.mbtn do child.mbtn[j]:Hide() end
    for j = an + 1, #child.abtn do child.abtn[j]:Hide() end
    child:SetSize(WIDTH, math.max(1, y + 12))
  end

  v.render = function(f)
    v.fight = f
    v.titleFS:SetText(foesText(f))
    local rc = RESULT[f.outcome] or RESULT.fled
    local groupN = (f.group and #f.group) or 0
    local groupTxt = (groupN > 1 and (groupN .. "-player group") or "solo") .. (f.spec and ("   ·   " .. f.spec) or "") .. (f.talents and ("  " .. f.talents) or "")
    local coords = UI.fmtCoords(f.x, f.y)
    v.metaFS:SetText(("|cff%02x%02x%02x%s|r   ·   %s%s   ·   %s   ·   level %s   ·   %s   ·   %s"):format(
      math.floor(rc[2][1] * 255), math.floor(rc[2][2] * 255), math.floor(rc[2][3] * 255), rc[1],
      f.zone or "?", coords ~= "" and ("   ·   " .. coords) or "", fmtDur(f.duration), tostring(f.level or "?"), groupTxt, date("%H:%M:%S", f.startEpoch or 0)))
    local dur = math.max(f.duration or 0, 0)
    v.slider:SetMinMaxValues(0, dur > 0 and dur or 1)
    v.slider:SetValueStep(dur > 60 and 1 or 0.2)
    if dur > 0 then v.slider:Show() else v.slider:Hide() end
    if v.placeLandmarks then v.placeLandmarks(f, dur) end
    v.curT = dur
    v.slider:SetValue(dur)   -- fires OnValueChanged → renderState (when the value actually changes)
    v.renderState()          -- guarantee a render even if the value didn't change
  end

  return v
end

-- ══ MEMBER VIEW ═════════════════════════════════════════════════════════════════
-- one party/raid member's identity + their buff/debuff timeline for the fight.
local function buildMemberView(content)
  local v = CreateFrame("Frame", nil, content)
  v:SetAllPoints(content); v:Hide()

  local back = UI.Button(v, "< Back", 70, 24, function() v:Hide(); if detailView then detailView:Show() end end)
  back:SetPoint("TOPLEFT", 12, -12)
  v.titleFS = UI.FS(v, "GameFontNormalLarge"); v.titleFS:SetPoint("TOPLEFT", 92, -14); v.titleFS:SetWidth(600); v.titleFS:SetJustifyH("LEFT")
  v.metaFS = UI.FS(v, "GameFontHighlightSmall", C.dim); v.metaFS:SetPoint("TOPLEFT", 14, -44); v.metaFS:SetWidth(690); v.metaFS:SetJustifyH("LEFT")

  local sf, child = UI.ScrollChild(v)
  sf:SetPoint("TOPLEFT", 12, -68); sf:SetPoint("BOTTOMRIGHT", -28, 12)
  child.fs = {}
  local WIDTH = 690
  local fn = 0
  local function cell(x, y, w, text, color, justify, template)
    fn = fn + 1
    local fs = child.fs[fn]
    if not fs then fs = ns.UI.FS(child, "GameFontHighlightSmall"); child.fs[fn] = fs end
    fs:SetFontObject(ns.UI.Font(template) or ns.UI.BODY_SM or GameFontHighlightSmall)
    fs:ClearAllPoints(); fs:SetPoint("TOPLEFT", x, -y)
    fs:SetWidth(w); fs:SetJustifyH(justify or "LEFT")
    local c = color or C.ink; fs:SetText(text or ""); fs:SetTextColor(c[1], c[2], c[3]); fs:Show()
    return fs
  end

  v.render = function(fight, member)
    fn = 0
    local r, g, b = UI.ClassColor(member.class)
    v.titleFS:SetText(member.name or "?"); v.titleFS:SetTextColor(r, g, b)
    local bits = {}
    if member.level then bits[#bits + 1] = "Level " .. member.level end
    if member.race then bits[#bits + 1] = member.race end
    if member.class then bits[#bits + 1] = member.class:sub(1, 1) .. member.class:sub(2):lower() end
    bits[#bits + 1] = "in the fight vs " .. foesText(fight)
    v.metaFS:SetText(table.concat(bits, "   ·   "))
    local y = 0
    cell(0, y, WIDTH, "Buffs & debuffs", C.gold, "LEFT", GameFontNormal); y = y + 22
    local auras = fight.memberAuras and fight.memberAuras[member.name]
    if auras and #auras > 0 then
      for _, a in ipairs(auras) do
        local col = a.gain and (a.debuff and C.red or C.green) or C.dim
        cell(8, y, 72, a.atPull and "at pull" or ("+%.1fs"):format(a.t or 0), C.dim)
        local icon = a.icon and ("|T" .. a.icon .. ":13:13:0:0|t ") or ""
        cell(88, y, WIDTH - 88, ("%s%s%s%s"):format(a.gain and "+ " or "- ", icon, a.name or "Unknown aura", a.debuff and "  (debuff)" or ""), col)
        y = y + 16
      end
    else
      cell(8, y, WIDTH - 8, "No buff/debuff changes captured for this member (out of range at pull, or restricted).", C.dim); y = y + 16
    end
    for j = fn + 1, #child.fs do child.fs[j]:Hide() end
    child:SetSize(WIDTH, math.max(1, y + 12))
  end

  return v
end

-- ══ LIST VIEW ═══════════════════════════════════════════════════════════════════
local function openDetail(f)
  listView:Hide()
  detailView.render(f)
  detailView:Show()
end

-- open a member's view from the fight detail (assigns the forward-declared upvalue)
openMember = function(fight, member)
  if not (fight and member and memberView) then return end
  detailView:Hide()
  memberView.render(fight, member)
  memberView:Show()
end

-- let other tabs (e.g. Dungeons) jump straight into a fight's detail view
ns.OpenFightDetail = function(f)
  if not f then return end
  UI.Open("Combat", "fights")   -- ensures the Fights tab is built + shown
  openDetail(f)
end

local function buildList(content)
  local v = CreateFrame("Frame", nil, content)
  v:SetAllPoints(content)

  -- filter TABS on a bordered pane (Notable = bosses + wipes + your deaths cuts through trash fights)
  local filter = "all"
  local search   -- text search box (inside the pane)
  local function matches(f)
    if not fightMatchesText(f, search and search:GetText()) then return false end
    if filter == "all" then return true end
    if filter == "notable" then return (f.bossName ~= nil) or f.outcome == "death" or f.outcome == "wipe" end
    return f.outcome == filter
  end
  local tabs = UI.Tabs(v, {
    { key = "all", label = "All" }, { key = "notable", label = "Notable" }, { key = "kill", label = "Kills" },
    { key = "wipe", label = "Wipes" }, { key = "death", label = "Deaths" },
  }, -30, 2, { shared = true, onSelect = function(key) filter = key; if listRebuild then listRebuild() end end })
  v.tabs = tabs
  local pane = tabs.content

  -- first row inside the pane: aggregate summary (left) + text search (right)
  local summary = UI.FS(pane, "GameFontHighlightSmall", C.gold); summary:SetPoint("TOPLEFT", 2, -6); summary:SetWidth(430); summary:SetJustifyH("LEFT")
  search = UI.EditBox(pane, 200, 22); search:SetPoint("TOPRIGHT", -2, -2)
  local hint = UI.FS(pane, "GameFontDisableSmall", C.dim); hint:SetPoint("LEFT", search, "LEFT", 8, 0); hint:SetText("search foe or zone")
  search:SetScript("OnTextChanged", function(e)
    if (e:GetText() or "") == "" then hint:Show() else hint:Hide() end
    if listRebuild then listRebuild() end
  end)

  -- columns: When · Faced (source) · Location (name) · Coords · Length · Result
  local COL = { time = 0, foe = 92, loc = 298, coords = 424, dur = 508, res = 584 }
  local WID = { time = 84, foe = 200, loc = 120, coords = 78, dur = 70, res = 80 }
  local ROWW = 670
  local hdr = CreateFrame("Frame", nil, pane); hdr:SetPoint("TOPLEFT", 2, -38); hdr:SetSize(ROWW, 16)
  local sortKey, sortAsc = "time", false
  local heads, styleHeads = {}, nil
  local function head(key, col, w, text)
    local b = CreateFrame("Button", nil, hdr); b:SetPoint("LEFT", col, 0); b:SetSize(w, 16)
    local fs = UI.FS(b, "GameFontNormalSmall"); fs:SetPoint("LEFT", 0, 0); fs:SetWidth(w); fs:SetJustifyH("LEFT")
    b.fs, b.key, b.label = fs, key, text
    b:SetScript("OnClick", function(hb)
      if sortKey == hb.key then sortAsc = not sortAsc else sortKey = hb.key; sortAsc = (hb.key == "foe" or hb.key == "res" or hb.key == "loc") end
      if styleHeads then styleHeads() end
      if listRebuild then listRebuild() end
    end)
    heads[#heads + 1] = b
  end
  styleHeads = function()
    for _, b in ipairs(heads) do
      local on = (b.key == sortKey)
      b.fs:SetText(b.label:upper() .. (on and (sortAsc and "  ^" or "  v") or ""))
      local col = on and C.gold or C.dim; b.fs:SetTextColor(col[1], col[2], col[3])
    end
  end
  head("time", COL.time, WID.time, "When"); head("foe", COL.foe, WID.foe, "Faced")
  head("loc", COL.loc, WID.loc, "Location"); head("coords", COL.coords, WID.coords, "Coords")
  head("dur", COL.dur, WID.dur, "Length"); head("res", COL.res, WID.res, "Result")

  local sf, child = UI.ScrollChild(pane)
  sf:SetPoint("TOPLEFT", 0, -58); sf:SetPoint("BOTTOMRIGHT", -22, 2)
  child.rows = {}
  v.rows = child.rows   -- exposed for the headless tests
  v.daysFn = function() return child.days end

  listRebuild = function()
    local fights = ns.mine(ns.Fights and ns.Fights.list())   -- the logged-in character's fights only (#23)
    local kills, wipes, deaths, secs = 0, 0, 0, 0
    for _, f in ipairs(fights) do
      if f.outcome == "kill" then kills = kills + 1
      elseif f.outcome == "wipe" then wipes = wipes + 1
      elseif f.outcome == "death" then deaths = deaths + 1 end
      secs = secs + (f.duration or 0)
    end
    summary:SetText(("%d fights  ·  %d kills  ·  %d wipes  ·  %d deaths  ·  %s in combat"):format(#fights, kills, wipes, deaths, fmtDur(secs)))
    local y, idx, dn, lastDay, lastRun = 0, 0, 0, nil, nil
    -- dungeon runs (from the Combat / Dungeons pane) so fights inside one get a run header
    local runs = (sortKey == "time" and ns.DungeonRuns) and ns.DungeonRuns() or {}
    local function runOf(f)
      local t = f.startEpoch or 0
      for _, r in ipairs(runs) do if t >= r.startT and t <= (r.endT or math.huge) then return r end end
    end
    child.days = child.days or {}
    for _, f in ipairs(sortFights(fights, sortKey, sortAsc)) do
      if matches(f) then
        if sortKey == "time" then                       -- a day header whenever the date changes
          local day = date("%Y-%m-%d", f.startEpoch or 0)
          if day ~= lastDay then
            lastDay = day; dn = dn + 1
            local dfs = child.days[dn]
            if not dfs then dfs = UI.FS(child, "GameFontNormalSmall", C.gold); dfs:SetJustifyH("LEFT"); child.days[dn] = dfs end
            dfs:ClearAllPoints(); dfs:SetPoint("TOPLEFT", 2, -(y + 4)); dfs:SetText(UI.fmtDay(f.startEpoch):upper()); dfs:Show()
            y = y + 20; lastRun = nil
          end
          local run = runOf(f)
          if run ~= lastRun then                       -- entering (or leaving) a dungeon run: a run header
            lastRun = run
            if run then
              dn = dn + 1
              local rfs = child.days[dn]
              if not rfs then rfs = UI.FS(child, "GameFontNormalSmall", C.gold); rfs:SetJustifyH("LEFT"); child.days[dn] = rfs end
              rfs:ClearAllPoints(); rfs:SetPoint("TOPLEFT", 14, -(y + 3))
              rfs:SetText(("|cff0cd29d%s|r  ·  %s  ·  %d boss%s down  ·  %d death%s"):format(run.name or "Dungeon", date("%H:%M", run.startT or 0),
                run.bossesDown or 0, (run.bossesDown or 0) == 1 and "" or "es", run.deaths or 0, (run.deaths or 0) == 1 and "" or "s"))
              rfs:Show(); y = y + 18
            end
          end
        end
        idx = idx + 1
        local row = child.rows[idx]
        if not row then
          row = CreateFrame("Button", nil, child, "BackdropTemplate"); row:SetHeight(20); row:SetPoint("RIGHT", child, "RIGHT", 0, 0)
          row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" }); row:SetBackdropColor(0, 0, 0, 0)
          row:SetScript("OnEnter", function(r)
            r:SetBackdropColor(C.panel2[1], C.panel2[2], C.panel2[3], 0.6)
            local f = r.fight; if not (f and GameTooltip) then return end
            GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
            GameTooltip:AddLine(foesText(f), 1, 1, 1)
            GameTooltip:AddLine(("%s  ·  %s  ·  %s"):format(date("%b %d %H:%M:%S", f.startEpoch or 0), fmtDur(f.duration), (RESULT[f.outcome] or RESULT.fled)[1]), 0.8, 0.8, 0.8)
            if f.zone then GameTooltip:AddLine(f.zone .. (UI.fmtCoords(f.x, f.y) ~= "" and ("  " .. UI.fmtCoords(f.x, f.y)) or ""), 0.6, 0.7, 0.75) end
            if f.group and #f.group > 0 then
              local names = {}
              for _, m in ipairs(f.group) do names[#names + 1] = (m.name or "?") .. (m.deadT and " (died)" or "") end
              GameTooltip:AddLine("Group: " .. table.concat(names, ", "), 0.6, 0.7, 0.75, true)
            end
            if f.spec or f.talents then GameTooltip:AddLine((f.spec or "") .. (f.talents and ("  " .. f.talents) or ""), 0.6, 0.7, 0.75) end
            GameTooltip:AddLine("Click to open the replay", 0.5, 0.65, 0.75)
            GameTooltip:Show()
          end)
          row:SetScript("OnLeave", function(r) r:SetBackdropColor(0, 0, 0, 0); if GameTooltip then GameTooltip:Hide() end end)
          row:SetScript("OnClick", function(r) if r.fight then openDetail(r.fight) end end)
          row.tm = UI.FS(row, "GameFontDisableSmall"); row.tm:SetPoint("LEFT", COL.time, 0); row.tm:SetWidth(WID.time); row.tm:SetJustifyH("LEFT")
          row.fo = UI.FS(row, "GameFontHighlightSmall"); row.fo:SetPoint("LEFT", COL.foe, 0); row.fo:SetWidth(WID.foe); row.fo:SetJustifyH("LEFT")
          row.lo = UI.FS(row, "GameFontDisableSmall"); row.lo:SetPoint("LEFT", COL.loc, 0); row.lo:SetWidth(WID.loc); row.lo:SetJustifyH("LEFT")
          row.co = UI.FS(row, "GameFontDisableSmall"); row.co:SetPoint("LEFT", COL.coords, 0); row.co:SetWidth(WID.coords); row.co:SetJustifyH("LEFT")
          row.du = UI.FS(row, "GameFontHighlightSmall"); row.du:SetPoint("LEFT", COL.dur, 0); row.du:SetWidth(WID.dur); row.du:SetJustifyH("LEFT")
          row.re = UI.FS(row, "GameFontHighlightSmall"); row.re:SetPoint("LEFT", COL.res, 0); row.re:SetWidth(WID.res); row.re:SetJustifyH("LEFT")
          child.rows[idx] = row
        end
        row.fight = f
        row:SetPoint("TOPLEFT", 0, -y); row:Show()
        row.tm:SetText(date("%m/%d %H:%M", f.startEpoch or 0)); row.tm:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
        local gn = (f.group and #f.group) or 0
        row.fo:SetText(foesText(f) .. (gn > 1 and ("  |cff8c9197%d-player|r"):format(gn) or "")); row.fo:SetTextColor(C.ink[1], C.ink[2], C.ink[3])
        row.lo:SetText(f.zone or ""); row.lo:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
        row.co:SetText(UI.fmtCoords(f.x, f.y)); row.co:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
        row.du:SetText(fmtDur(f.duration)); row.du:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
        local rc = RESULT[f.outcome] or RESULT.fled
        local md = tonumber(f.memberDeaths) or 0
        row.re:SetText((GLYPH[f.outcome] or GLYPH.fled) .. rc[1] .. (md > 0 and ("  |cffe5484d%d died|r"):format(md) or "")); row.re:SetTextColor(rc[2][1], rc[2][2], rc[2][3])
        y = y + 20
      end
    end
    for j = idx + 1, #child.rows do child.rows[j]:Hide() end
    for j = dn + 1, #child.days do child.days[j]:Hide() end
    if idx == 0 then
      child.empty = child.empty or (function()
        local fs = UI.FS(child, "GameFontDisableSmall"); fs:SetPoint("TOPLEFT", 0, 0); return fs
      end)()
      child.empty:SetText(#fights == 0 and "No fights yet. Enter combat and they show up here." or "No fights match this filter.")
      child.empty:Show()
    elseif child.empty then child.empty:Hide() end
    child:SetSize(math.max(ROWW, (sf:GetWidth() or ROWW) - 4), math.max(1, y))
  end

  styleHeads()
  tabs.select("all")
  return v
end

local function build(content)
  listView = buildList(content)
  detailView = buildDetail(content)
  memberView = buildMemberView(content)
end

UI.registerPane("Combat", 2, "Fights", build, function()
  -- don't yank the user out of a detail / member view
  if (detailView and detailView:IsShown()) or (memberView and memberView:IsShown()) then return end
  if listRebuild then listRebuild() end
  if not ticker then ticker = C_Timer.NewTicker(2, function()
    if listView and listView:IsShown() and listRebuild then listRebuild() end
  end) end
end)

-- ── test exports: headless luajit tests in tests/ read these; no effect in-game ──
ns._test = ns._test or {}
ns._test.activeAuras, ns._test.fmtDur, ns._test.foesText, ns._test.statAt = activeAuras, fmtDur, foesText, statAt
ns._test.fightMatchesText, ns._test.sortFights = fightMatchesText, sortFights
ns._test.fightsList = function() return listView end
ns._test.repairAuraLog = repairAuraLog
ns._test.fightLoot = fightLoot
ns._test.fightDetail = function() return detailView end
