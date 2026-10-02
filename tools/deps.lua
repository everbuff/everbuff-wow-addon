-- Everbuff · tools/deps.lua - the list of everything the addon takes from the WoW client (everbuff-business #45, L1
-- and L5). It reads the files the TOC loads and lists every global function, value and event they use:
--
--   luajit tools/deps.lua            rewrites Everbuff/Deps.lua (the list the in-game self-test checks, L5)
--   luajit tools/deps.lua --check    exits 1 when Everbuff/Deps.lua is out of date (the test suite runs this)
--   luajit tools/deps.lua --json     prints the list as JSON, for the L1 API diff against the client's API files
--
-- Each entry is { kind, name, need }:
--   kind   "function" (called, passed to pcall or hooked), "value" (a table, frame or constant read), "event"
--   need   "required": used without a test, so the addon errors without it;
--          "guarded": every use is tested first (`X and X()`, `if X then`, `type(X)`, `pcall(X)`, `X or default`,
--          a test of its namespace in the same file, an event registered through pcall), so the addon degrades.
-- Forbidden events (the client blocks them from addons) are listed apart and never as a dependency.
-- Frame methods (`frame:SetPoint`) and names built at run time (`_G[name]`) are not listed.

local ROOT = (arg and arg[0] or ""):match("^(.*)[/\\]tools[/\\]deps%.lua$") or "."
local SRC = ROOT .. "/Everbuff/"
local OUT = SRC .. "Deps.lua"
local FORBIDDEN = { COMBAT_LOG_EVENT_UNFILTERED = true }   -- WoW Forever blocks it (0.9.22, founder 2026-10-02)
-- calls that protect their first argument: pcall and the addon's own wrappers (Fights `try`, Emitter `rd` call it
-- through pcall; Visits `hook` hooks tbl[name] only when it is a function)
local PROTECT = { pcall = "call", xpcall = "call", try = "call", rd = "call", hook = "table" }
-- uses the source cannot show as guarded, with the reason they are
local CONTEXT = {
  CombatLogGetCurrentEventInfo = "read only in the COMBAT_LOG_EVENT_UNFILTERED handler, registered only without Secret Values",
}

local KEYWORDS = {}
for w in ("and break do else elseif end false for function goto if in local nil not or repeat return then true until while"):gmatch("%S+") do KEYWORDS[w] = true end
-- the Lua language and its libraries, present on every client
local LUA = {}
for w in ("assert error getmetatable ipairs next pairs pcall print rawequal rawget rawset select setmetatable tonumber tostring type unpack xpcall math string table coroutine os io debug _G _VERSION arg require loadstring load"):gmatch("%S+") do LUA[w] = true end

local function readFile(p)
  local f = assert(io.open(p, "rb")); local s = f:read("*a"); f:close(); return s
end

local SAVED = {}
local function tocFiles()
  local files = {}
  for line in readFile(SRC .. "EverbuffJournal.toc"):gmatch("[^\r\n]+") do
    line = line:gsub("^%s+", ""):gsub("%s+$", "")
    local sv = line:match("^## SavedVariables[%w]*:%s*(.+)$")
    if sv then for name in sv:gmatch("[%w_]+") do SAVED[#SAVED + 1] = name end end
    -- Deps.lua and SelfTest.lua are the check itself, not something the addon takes from the client
    if line ~= "" and not line:match("^#") and line ~= "Deps.lua" and line ~= "SelfTest.lua" then files[#files + 1] = line end
  end
  return files
end

-- ── lexer: { t = "name" | "kw" | "str" | "num" | "op", v } (comments dropped) ──
local function lex(s)
  local toks, i, n = {}, 1, #s
  local function longBracket(at)
    local eq = s:match("^%[(=*)%[", at)
    if not eq then return nil end
    local close = "]" .. eq .. "]"
    local e = s:find(close, at + #eq + 2, true)
    return s:sub(at + #eq + 2, (e or n + 1) - 1), (e and e + #close or n + 1)
  end
  while i <= n do
    local c = s:sub(i, i)
    if c:match("%s") then i = i + 1
    elseif s:sub(i, i + 1) == "--" then
      local _, after = longBracket(i + 2)
      if after then i = after else i = (s:find("\n", i, true) or n) + 1 end
    elseif c:match("[%a_]") then
      local w = s:match("^[%w_]+", i)
      toks[#toks + 1] = { t = KEYWORDS[w] and "kw" or "name", v = w }; i = i + #w
    elseif c:match("%d") or (c == "." and s:sub(i + 1, i + 1):match("%d")) then
      local w = s:match("^0[xX]%x+", i) or s:match("^%d*%.?%d*[eE][%+%-]?%d+", i) or s:match("^%d*%.?%d*", i)
      toks[#toks + 1] = { t = "num", v = w }; i = i + #w
    elseif c == '"' or c == "'" then
      local j, buf = i + 1, {}
      while j <= n do
        local d = s:sub(j, j)
        if d == "\\" then buf[#buf + 1] = s:sub(j, j + 1); j = j + 2
        elseif d == c then break
        else buf[#buf + 1] = d; j = j + 1 end
      end
      toks[#toks + 1] = { t = "str", v = table.concat(buf) }; i = j + 1
    elseif c == "[" and s:match("^%[=*%[", i) then
      local body, after = longBracket(i)
      toks[#toks + 1] = { t = "str", v = body }; i = after
    else
      local op = s:match("^%.%.%.", i) or s:match("^[%.=~<>:][%.=:]", i)
      if op and not (op == "..." or op == ".." or op == "==" or op == "~=" or op == "<=" or op == ">=" or op == "::") then op = nil end
      op = op or c
      toks[#toks + 1] = { t = "op", v = op }; i = i + #op
    end
  end
  return toks
end

-- ── analysis of one file ──
local function analyse(file, src, deps, events, forbiddenSeen)
  local T = lex(src)
  local function tv(k) return T[k] and T[k].v end
  local function isName(k) return T[k] and T[k].t == "name" end

  -- names bound in this file: locals, parameters, loop variables, and globals the addon defines itself
  local bound = {}
  for _, sv in ipairs(SAVED) do bound[sv] = true end   -- the addon's own SavedVariables
  for k = 1, #T do
    local v = tv(k)
    if v == "local" and T[k].t == "kw" then
      if tv(k + 1) == "function" then bound[tv(k + 2)] = true
      else
        local j = k + 1
        while isName(j) do bound[tv(j)] = true; if tv(j + 1) == "," then j = j + 2 else break end end
      end
    elseif v == "function" and T[k].t == "kw" then
      local j = k + 1
      if isName(j) then   -- function a.b:c(...): a single plain name is a global the addon defines
        local single = not (tv(j + 1) == "." or tv(j + 1) == ":")
        if single then bound[tv(j)] = true end
        while isName(j) and (tv(j + 1) == "." or tv(j + 1) == ":") do j = j + 2 end
        j = j + 1
      end
      if tv(j) == "(" then
        j = j + 1
        while tv(j) ~= ")" and T[j] do if isName(j) then bound[tv(j)] = true end; j = j + 1 end
      end
    elseif v == "for" and T[k].t == "kw" then
      local j = k + 1
      while isName(j) do bound[tv(j)] = true; if tv(j + 1) == "," then j = j + 2 else break end end
    end
  end
  -- top-level assignments to a plain global (EverbuffDB = ..., SLASH_EVERBUFF1 = ...) are the addon's own
  local stack = {}
  local isKey = {}
  for k = 1, #T do
    local v = tv(k)
    if T[k].t == "op" and (v == "{" or v == "(" or v == "[") then stack[#stack + 1] = v
    elseif T[k].t == "op" and (v == "}" or v == ")" or v == "]") then stack[#stack] = nil
    elseif isName(k) and tv(k + 1) == "=" then
      local p = tv(k - 1)
      if stack[#stack] == "{" and (p == "{" or p == "," or p == ";") then isKey[k] = true
      elseif p ~= "." and p ~= ":" and not bound[v] then
        -- `a, b = ...` and `X = ...` at statement level: the addon defines X
        bound[v] = true
      end
    end
  end

  -- paths tested in this file (`if X`, `X and`, `type(X)`, `pcall(X`...): uses of them or below them are guarded
  local tested = {}
  local occ = {}   -- { path, call, guardedHere, assign }
  local k = 1
  while k <= #T do
    if isName(k) and not isKey[k] and not bound[tv(k)] and not LUA[tv(k)] and tv(k - 1) ~= "." and tv(k - 1) ~= ":" and tv(k - 1) ~= "goto" and tv(k - 1) ~= "::" then
      local parts, j = { tv(k) }, k
      while tv(j + 1) == "." and isName(j + 2) do parts[#parts + 1] = tv(j + 2); j = j + 2 end
      local nxt, prev = tv(j + 1), tv(k - 1)
      local assign = nxt == "="
      if assign then parts[#parts] = nil end
      if #parts > 0 then
        local path = table.concat(parts, ".")
        local call = (nxt == "(" or (T[j + 1] and T[j + 1].t == "str") or nxt == "{") and not assign
        local wrap = prev == "(" and PROTECT[tv(k - 2)] or nil
        local isTest = nxt == "and" or nxt == "or" or nxt == "then" or prev == "not"
          or (prev == "(" and tv(k - 2) == "type")
          or ((nxt == "==" or nxt == "~=") and tv(j + 2) == "nil")
        if isTest or wrap then tested[path] = true end
        if wrap == "call" then call = true end
        -- a fallback (`a or X`) and a comparison (`name == X`) read nil without an error
        -- and so does a plain copy into a variable (`local CSI = C_SpecializationInfo`), tested where it is used
        local copy = prev == "=" and not call and nxt ~= ":" and nxt ~= "["
        local soft = prev == "or" or prev == "==" or prev == "~=" or nxt == "==" or nxt == "~=" or copy or CONTEXT[path] ~= nil
        occ[#occ + 1] = { path = path, call = call, test = isTest or wrap ~= nil or soft }
      end
      k = j + 1
    else
      k = k + 1
    end
  end
  -- hooksecurefunc("Name", ...) and Visits' hookG("Name", ...) hook a global function, only when it exists
  for q = 1, #T do
    if (tv(q) == "hooksecurefunc" or tv(q) == "hookG") and tv(q + 1) == "(" and T[q + 2] and T[q + 2].t == "str" then
      occ[#occ + 1] = { path = tv(q + 2), call = true, test = true }
    elseif (tv(q) == "hooksecurefunc" or tv(q) == "hook") and tv(q + 1) == "(" and isName(q + 2) and not bound[tv(q + 2)]
      and tv(q + 3) == "," and T[q + 4] and T[q + 4].t == "str" then
      occ[#occ + 1] = { path = tv(q + 2) .. "." .. tv(q + 4), call = true, test = true }   -- hooksecurefunc(tbl, "Name")
    end
  end
  local function guarded(path)
    if tested[path] then return true end
    local pre = path
    while true do
      pre = pre:match("^(.*)%.[^%.]+$")
      if not pre then return false end
      if tested[pre] then return true end
    end
  end
  for _, o in ipairs(occ) do
    local d = deps[o.path] or { name = o.path, kind = "value", need = "guarded", files = {} }
    deps[o.path] = d
    if o.call then d.kind = "function" end
    if not o.test and not guarded(o.path) then d.need = "required" end
    d.files[file] = true
  end

  -- events: what each RegisterEvent registers (a literal, or the strings of the table its loop walks)
  local function tableAt(q)   -- T[q] == "{": its array strings and its string keys
    local out, depth, j = {}, 0, q
    repeat
      local v = tv(j)
      if T[j].t == "op" and v == "{" then depth = depth + 1
      elseif T[j].t == "op" and v == "}" then depth = depth - 1
      elseif depth == 1 and T[j].t == "str" and (tv(j - 1) == "{" or tv(j - 1) == ",") and (tv(j + 1) == "," or tv(j + 1) == "}") then out[#out + 1] = v
      elseif depth == 1 and isKey[j] then out[#out + 1] = v end
      j = j + 1
    until depth == 0 or j > #T
    return out
  end
  local function localTable(name)
    for q = 1, #T - 3 do
      if tv(q) == "local" and tv(q + 1) == name and tv(q + 2) == "=" and tv(q + 3) == "{" then return tableAt(q + 3) end
    end
    return {}
  end
  local function addEvent(name, viaPcall, cond)
    if not name:match("^[A-Z][A-Z0-9_]+$") then return end
    if FORBIDDEN[name] then forbiddenSeen[name] = forbiddenSeen[name] or {}; forbiddenSeen[name][file] = cond and "guarded" or "unguarded"; return end
    local e = events[name] or { name = name, kind = "event", need = "guarded", files = {} }
    events[name] = e
    if not viaPcall then e.need = "required" end
    e.files[file] = true
  end
  for q = 1, #T do
    if tv(q) == "RegisterEvent" and (tv(q - 1) == ":" or tv(q - 1) == ".") then
      local viaPcall = tv(q - 1) == "." and tv(q - 3) == "(" and tv(q - 4) == "pcall"
      -- the statement is conditional when an `if` opens it on the same line of tokens before the frame name
      local cond = tv(q - 5) == "then" or tv(q - 3) == "then"
      local argTok
      if tv(q - 1) == ":" and tv(q + 1) == "(" then argTok = q + 2
      elseif viaPcall and tv(q + 1) == "," then argTok = q + 4 end
      if argTok and T[argTok] and T[argTok].t == "str" then
        addEvent(tv(argTok), viaPcall, cond)
      elseif argTok and isName(argTok) then
        -- a loop variable: walk back to `for ... in (i)pairs( <table> ) do`
        for b = q, math.max(1, q - 400), -1 do
          if tv(b) == "for" then
            local j = b
            while tv(j) ~= "in" and j < q do j = j + 1 end
            local it = tv(j + 1)
            if (it == "ipairs" or it == "pairs") and tv(j + 2) == "(" then
              local list = tv(j + 3) == "{" and tableAt(j + 3) or (isName(j + 3) and localTable(tv(j + 3))) or {}
              for _, ev in ipairs(list) do addEvent(ev, viaPcall, cond) end
            end
            break
          end
        end
      end
    end
  end
end

local function build()
  local deps, events, forbiddenSeen = {}, {}, {}
  for _, f in ipairs(tocFiles()) do analyse(f, readFile(SRC .. f), deps, events, forbiddenSeen) end
  local list = {}
  for _, d in pairs(deps) do list[#list + 1] = d end
  for _, e in pairs(events) do list[#list + 1] = e end
  local order = { ["function"] = 1, value = 2, event = 3 }
  table.sort(list, function(a, b)
    if a.kind ~= b.kind then return order[a.kind] < order[b.kind] end
    return a.name < b.name
  end)
  local forbidden = {}
  for name, files in pairs(forbiddenSeen) do forbidden[#forbidden + 1] = { name = name, files = files } end
  table.sort(forbidden, function(a, b) return a.name < b.name end)
  return list, forbidden
end

local function render(list, forbidden)
  local out = {
    "-- Everbuff · Deps.lua - GENERATED by tools/deps.lua from the files the TOC loads; do not edit by hand.",
    "-- Everything the addon takes from the WoW client, checked by SelfTest.lua at the first login on each new build",
    "-- (everbuff-business #45, L5). Regenerate with `luajit tools/deps.lua`; the test suite fails while it is stale.",
    "-- { kind, name, need }: need is \"required\" (used untested) or \"guarded\" (tested first, the addon degrades).",
    "",
    "local ADDON, ns = ...",
    "",
    "ns.deps = {",
  }
  for _, d in ipairs(list) do
    out[#out + 1] = ("  { %q, %q, %q },"):format(d.kind, d.name, d.need)
  end
  out[#out + 1] = "}"
  out[#out + 1] = ""
  out[#out + 1] = "-- events the client blocks from addons; the self-test fails when one of the addon's frames has one registered"
  local names = {}
  for _, f in ipairs(forbidden) do names[#names + 1] = ("%q"):format(f.name) end
  for name in pairs(FORBIDDEN) do
    local seen = false
    for _, f in ipairs(forbidden) do if f.name == name then seen = true end end
    if not seen then names[#names + 1] = ("%q"):format(name) end
  end
  table.sort(names)
  out[#out + 1] = "ns.depsForbidden = { " .. table.concat(names, ", ") .. " }"
  out[#out + 1] = ""
  return table.concat(out, "\n")
end

local function json(list, forbidden)
  local function files(t) local o = {} for f in pairs(t) do o[#o + 1] = ("%q"):format(f) end table.sort(o) return "[" .. table.concat(o, ",") .. "]" end
  local rows = {}
  for _, d in ipairs(list) do
    rows[#rows + 1] = ('    {"kind":%q,"name":%q,"need":%q,"files":%s}'):format(d.kind, d.name, d.need, files(d.files))
  end
  local fb = {}
  for _, f in ipairs(forbidden) do fb[#fb + 1] = ('    {"name":%q,"files":%s}'):format(f.name, files(f.files)) end
  return "{\n  \"deps\": [\n" .. table.concat(rows, ",\n") .. "\n  ],\n  \"forbidden\": [\n" .. table.concat(fb, ",\n") .. "\n  ]\n}\n"
end

local M = { build = build, render = render, lex = lex, OUT = OUT }
if ... == "deps" then return M end   -- required as a module (the test suite)

local mode = arg and arg[1]
local list, forbidden = build()
if mode == "--json" then
  io.write(json(list, forbidden))
elseif mode == "--check" then
  local want = render(list, forbidden)
  local ok, have = pcall(readFile, OUT)
  have = ok and have:gsub("\r\n", "\n") or ""
  if have ~= want then io.stderr:write("Everbuff/Deps.lua is out of date: run luajit tools/deps.lua\n"); os.exit(1) end
  print(("Everbuff/Deps.lua is current (%d entries)"):format(#list))
else
  local f = assert(io.open(OUT, "wb")); f:write(render(list, forbidden)); f:close()
  local req = 0
  for _, d in ipairs(list) do if d.need == "required" then req = req + 1 end end
  print(("wrote %s: %d entries, %d required"):format(OUT, #list, req))
end
