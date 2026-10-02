-- Everbuff · SelfTest.lua - the addon checks the WoW client it runs on (everbuff-business #45, layer L5, approved
-- 2026-10-02).
--
-- WHEN: at the first world entry on a client build (GetBuildInfo version.build) or addon version it has not
-- recorded yet. Every other login costs one string compare.
-- WHAT: every function, value and event the addon takes from the client (Deps.lua, generated from the source by
-- tools/deps.lua, the same list the L1 API diff reads), that issecretvalue exists and answers false for plain values,
-- and that none of the addon's event frames holds an event the client forbids (WoW Forever forbids
-- COMBAT_LOG_EVENT_UNFILTERED; 0.9.21 registered it and the client blocked the addon).
-- WHERE: EverbuffDB.settings.selftest = { build, interface, addon, at, ok, missing[], forbidden[], absent[], secrets,
-- events, skipped?, error? } (docs/ADDON_DATA_CONTRACT.md). The backend's live canary (L4) reads it from the save file.
-- OUTPUT (founder decision 3, option B): silent when everything passes; exactly one chat line when something fails.
--
-- missing: a "required" dependency that is gone, or a "guarded" one that the previous build had and this build has
-- not (the addon degrades without it). A guarded dependency already absent on the previous record, on the first
-- record ever, or on the first record of a new addon version (whose list may hold items the previous record never
-- checked), is listed in `absent` only: it is how this client is, not a change. Classic clients are not checked
-- (WoW Forever only): their record says skipped = "classic".

local ADDON, ns = ...

local ST = {}
ns.SelfTest = ST

local CLASSIC_PROJECTS = { "WOW_PROJECT_CLASSIC", "WOW_PROJECT_BURNING_CRUSADE_CLASSIC", "WOW_PROJECT_WRATH_CLASSIC",
  "WOW_PROJECT_CATACLYSM_CLASSIC", "WOW_PROJECT_MISTS_CLASSIC" }

-- "1.60.1.70170" and the interface number, or nil when the client does not say
function ST.buildId()
  if type(GetBuildInfo) ~= "function" then return nil end
  local ok, version, build, _, iface = pcall(GetBuildInfo)
  if not ok or (version == nil and build == nil) then return nil end
  return tostring(version or "?") .. "." .. tostring(build or "?"), tonumber(iface)
end

-- a dotted path from _G ("C_Timer.After"); nil when any step is missing or errors
function ST.resolve(path)
  local v = _G
  for part in path:gmatch("[^%.]+") do
    if type(v) ~= "table" then return nil end
    local ok, nv = pcall(function() return v[part] end)
    if not ok then return nil end
    v = nv
  end
  return v
end

local function isClassic()
  if ns.hasSecretValues then return false end   -- a client with Secret Values is WoW Forever whatever its project id
  for _, k in ipairs(CLASSIC_PROJECTS) do
    local p = rawget(_G, k)
    if p ~= nil and p == WOW_PROJECT_ID then return true end
  end
  return false
end

-- issecretvalue must exist and answer false for plain values (the guards plain, plainNum, safeStr and safeKey ask it)
function ST.secretsBehave()
  local sv = rawget(_G, "issecretvalue")
  if type(sv) ~= "function" then return false end
  local ok, a, b = pcall(function() return sv(1), sv("everbuff") end)
  return ok and a == false and b == false
end

-- The check itself. Returns the record and whether it ran (false: this build and addon version were checked before).
function ST.run()
  local db = ns.DB
  if not (db and db.settings) then return nil, false end
  local build, iface = ST.buildId()
  local prev = db.settings.selftest
  if type(prev) == "table" and prev.build == build and prev.addon == ns.VERSION then return prev, false end
  local now = (GetServerTime and GetServerTime()) or time()
  local res = { build = build, interface = iface, addon = ns.VERSION, at = now, ok = true, missing = {}, forbidden = {}, absent = {} }
  if isClassic() then
    res.skipped = "classic"
    db.settings.selftest = res
    return res, true
  end
  local ok, err = pcall(function()
    local seen = {}
    local function miss(name) if not seen[name] then seen[name] = true; res.missing[#res.missing + 1] = name end end
    -- a baseline exists when the previous record checked a client (not the first record, not a Classic one) with
    -- the same dependency list (same addon version) on another build: only then is a guarded absence a change of the
    -- client. A new addon version can list guarded items the previous record never checked, so it starts a new
    -- baseline instead of raising a false alarm.
    local baseline = type(prev) == "table" and not prev.skipped and type(prev.absent) == "table"
      and prev.addon == ns.VERSION and prev.build ~= build
    local wasAbsent = {}
    if baseline then for _, n in ipairs(prev.absent) do wasAbsent[n] = true end end
    local EU = rawget(_G, "C_EventUtils")
    local canCheckEvents = type(EU) == "table" and type(EU.IsEventValid) == "function"
    res.events = canCheckEvents and "checked" or "unchecked"
    -- the forbidden events first: the line names the worst change
    for _, ev in ipairs(ns.depsForbidden or {}) do
      for _, fr in ipairs(ns.eventFrames or {}) do
        local okR, on = pcall(fr.IsEventRegistered, fr, ev)
        if okR and on == true then res.forbidden[#res.forbidden + 1] = ev; break end
      end
    end
    res.secrets = ST.secretsBehave()
    if not res.secrets then miss("issecretvalue") end
    for _, d in ipairs(ns.deps or {}) do
      local kind, name, need = d[1], d[2], d[3]
      local present
      if kind == "event" then
        if canCheckEvents then
          local okE, valid = pcall(EU.IsEventValid, name)
          present = okE and valid == true
        end
      elseif kind == "function" then
        present = type(ST.resolve(name)) == "function"
      else
        present = ST.resolve(name) ~= nil
      end
      if present == false then
        if need == "guarded" then res.absent[#res.absent + 1] = name end
        if need == "required" or (baseline and not wasAbsent[name]) then miss(name) end
      end
    end
  end)
  if not ok then res.error = tostring(err) end
  res.ok = ok and #res.missing == 0 and #res.forbidden == 0
  db.settings.selftest = res
  return res, true
end

-- The one chat line (founder decision 3, option B), or nil when there is nothing to say.
function ST.line(res)
  if not res or res.ok or res.error then return nil end
  local items = {}
  for _, n in ipairs(res.forbidden or {}) do items[#items + 1] = n end
  for _, n in ipairs(res.missing or {}) do items[#items + 1] = n end
  if #items == 0 then return nil end
  local more = #items - 1
  return ("this WoW build changed %s%s; recording continues."):format(items[1], more > 0 and (" (and %d more)"):format(more) or "")
end

-- first world entry of this UI load: run, and say it once if something failed
function ST.onEnteringWorld(frame)
  if frame then frame:UnregisterEvent("PLAYER_ENTERING_WORLD") end   -- once per UI load; the record: once per build
  local okRun, res, ran = pcall(ST.run)
  if not (okRun and ran) then return end
  local text = ST.line(res)
  -- after the login lines, so it is the last thing the player reads from the addon
  if text then C_Timer.After(6, function() ns.msg(text) end) end
end

local f = CreateFrame("Frame")
ns.eventFrames[#ns.eventFrames + 1] = f
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", ST.onEnteringWorld)
