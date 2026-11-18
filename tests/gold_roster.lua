-- Gold roster and glance (everbuff-wow-addon #43, 0.9.44). Loaded by tests/run_tests.lua after tests/gold_days.lua:
--   dofile("tests/gold_roster.lua")({ check = check, M = M, ns = ns })
-- Runs on a save file of its own (the suite's is put aside and put back): the roster for every filter with WoW
-- Forever style realm strings and two-name characters, a hidden character leaving every total at once, a block
-- without a name, 30 characters with the stale ones marked, the realm label, the tooltip block against a fake
-- tooltip (line budget, the current character pinned, the owner check), the change callback and /eb gold.
return function(P)
  local check, M, ns = P.check, P.M, P.ns
  local E, G, UI = ns.Emitter, ns.Gold, ns.UI
  local DAY = 86400
  local ME = "Player-1-000001"
  local realPrint = print
  local said = {}
  print = function(...) said[#said + 1] = table.concat({ ... }, " ") end

  local main = { db = ns.DB, epoch = M.epoch, now = M.now, money = M.money }
  local real = { realm = _G.GetRealmName, unitName = _G.UnitName, unmod = _G.UnitNameUnmodified, playerInfo = _G.C_PlayerInfo }
  ns.Recorder.pause("logout")
  local function fresh(db)
    ns.Recorder.discard()
    ns.DB = ns.migrateDB(db or {})
    G._held, G._baseWait, G._flushTimer, G._tickAt = nil, nil, nil, nil
    E._openGain, E._questMoney, E._dayErr = nil, nil, nil
    ns._test.newLoad()
    M.timers = {}
    for _, e in ipairs({ "MERCHANT_CLOSED", "MAIL_CLOSED", "AUCTION_HOUSE_CLOSED", "TRAINER_CLOSED", "TRADE_CLOSED" }) do M.fire(e) end
    M.units.NPC = nil
    M.now = M.now + 100
  end
  local function login(reload) M.fire("PLAYER_ENTERING_WORLD", not reload, reload and true or false); M.runTimers() end
  local function money(d) M.money = M.money + d; M.fire("PLAYER_MONEY") end
  local function row(ro, guid) for _, r in ipairs(ro.rows) do if r.guid == guid then return r end end end

  -- a WoW Forever style client: a long realm string, a character with two names
  local REALM = "Forever Realm [EU] - Azure Dawn's Rest"
  _G.GetRealmName = function() return REALM end
  _G.C_PlayerInfo = { ShouldDisplaySurname = function() return true end }
  _G.UnitName = function(u) if u == "player" then return "Hart", "Hammershield" end return real.unitName(u) end
  _G.UnitNameUnmodified = _G.UnitName

  fresh()
  M.epoch, M.money = 1795500000, 4123000
  login()
  local now = M.epoch
  local c = ns.DB.characters[ME]
  check("roster: the logged-in block carries name, surname, realm, class, faction, level and seen", c.name == "Hart" and c.surname == "Hammershield" and c.realm == REALM and c.class == "WARRIOR"
    and c.faction == "Alliance" and c.level == M.level and c.seen == now, tostring(c.surname))
  money(380000); money(-128800)
  local chars = ns.DB.characters
  local base = G.baseStored()
  local kT = G.dayKey(now, base)
  -- A: same realm (written with other spacing), same faction; B: same realm, Horde; C: another realm, Alliance;
  -- D: another realm, Horde; E: same realm, not seen since the update (no class, no faction, no seen)
  chars.A = { name = "Mira", surname = "Dawnfall", realm = "forever realm [EU] - Azure Dawns Rest", class = "MAGE", faction = "Alliance", level = 21, seen = now - 3 * DAY,
    gold = { balance = 961000 }, goldDays = { [kT] = { g = 50000, s = 20000, o = 931000, c = 961000, t = 900, n = 3, looted = 50000, repairs = 20000 },
      [G.dayKey(now - 2 * DAY, base)] = { g = 1000, s = 0, o = 930000, c = 931000, t = 100, n = 1, quests = 1000 } } }
  chars.B = { name = "Grok", realm = REALM, class = "SHAMAN", faction = "Horde", level = 40, seen = now - 10 * DAY, gold = { balance = 250000 } }
  chars.C = { name = "Mira", surname = "Sunfall", realm = "Forever Realm [EU] - Other Shore", class = "PRIEST", faction = "Alliance", level = 12, seen = now - DAY, gold = { balance = 70000 } }
  chars.D = { name = "Zug", realm = "Forever Realm [EU] - Other Shore", class = "WARRIOR", faction = "Horde", level = 8, seen = now - 40 * DAY, gold = { balance = 1000 } }
  chars.E = { name = "Hartbank", realm = REALM, gold = { balance = 3000000 } }
  chars.F = { gold = { balance = 99999999 } }   -- a block without a name
  local myBal = M.money

  -- ── the filter matrix ───────────────────────────────────────────────────────────────────────────────────────
  local function names(ro) local t = {}; for _, r in ipairs(ro.rows) do t[#t + 1] = r.guid == ME and "me" or r.guid end; table.sort(t); return table.concat(t, ",") end
  local all, realm, faction, both = G.roster("all"), G.roster("realm"), G.roster("faction"), G.roster("realmFaction")
  check("roster all: every named character, the block without a name skipped", names(all) == "A,B,C,D,E,me" and all.count == 6 and all.total == myBal + 961000 + 250000 + 70000 + 1000 + 3000000, names(all) .. " " .. all.total)
  check("roster realm: the same realm however it is spaced or cased, never another one", names(realm) == "A,B,E,me" and realm.total == myBal + 961000 + 250000 + 3000000, names(realm))
  check("roster faction: only characters known to be of the faction", names(faction) == "A,C,me" and faction.total == myBal + 961000 + 70000, names(faction))
  check("roster realm and faction", names(both) == "A,me" and both.total == myBal + 961000, names(both))
  check("roster: rows are by balance, biggest first", all.rows[1].guid == ME and all.rows[2].guid == "E" and all.rows[#all.rows].guid == "D")
  check("roster: a two-name character shows both names; the current one is marked", row(all, ME).label == "Hart Hammershield" and row(all, ME).me == true and row(all, "A").label == "Mira Dawnfall" and row(all, "C").label == "Mira Sunfall")
  check("roster: a character not seen since the update has no facts and is counted in needLogin", row(all, "E").facts == false and row(all, "A").facts == true and all.needLogin == 1 and all.unknownAge == 1)
  check("roster: the oldest balance date is the oldest seen of the counted rows", all.oldest == now - 40 * DAY and G.rosterLine(all) == "6 characters, oldest balance from " .. G.fmtDate(now - 40 * DAY), G.rosterLine(all))
  check("roster: today and the last 7 days come from the character's own day rows", row(all, "A").today == 30000 and row(all, "A").d7 == 31000 and row(all, ME).today == 380000 - 128800 and row(all, "B").today == 0)
  -- two characters whose names would look identical get their realm beside them
  chars.G = { name = "Mira", surname = "Dawnfall", realm = "Forever Realm [EU] - Other Shore", class = "ROGUE", faction = "Alliance", level = 5, seen = now, gold = { balance = 1 } }
  local dup = G.roster("all")
  check("roster: two rows never show the same name: the realm goes beside it", row(dup, "A").label ~= row(dup, "G").label and row(dup, "G").label:find("Mira Dawnfall (", 1, true) == 1 and row(dup, "G").label:find("Other Shore", 1, true) ~= nil, row(dup, "G").label)
  chars.G = nil

  -- ── the realm label ─────────────────────────────────────────────────────────────────────────────────────────
  check("realm label: a short name is kept", G.realmLabel("Realm") == "Realm" and G.realmLabel("Azure Dawn's Rest") == "Azure Dawn's Rest")
  check("realm label: brackets are dropped", G.realmLabel("Stormrage (EU)") == "Stormrage" and G.realmLabel("Azure Dawn [PvP]") == "Azure Dawn")
  check("realm label: a long string is cut at a word, at most 18 characters and three dots", #G.realmLabel("The Extremely Long Realm Name Of Forever") <= 21 and G.realmLabel("The Extremely Long Realm Name Of Forever"):find("%.%.%.$") ~= nil, G.realmLabel("The Extremely Long Realm Name Of Forever"))
  check("realm label: the Forever style string of this test", G.realmLabel(REALM) ~= "" and #G.realmLabel(REALM) <= 21, G.realmLabel(REALM))
  check("realm label: nothing for a missing or hidden realm", G.realmLabel(nil) == "" and G.realmLabel(42) == "")

  -- ── a hidden character leaves every total at once ───────────────────────────────────────────────────────────
  local acct0 = G.period("today", "account")
  check("who: the account's today is a sum over the character blocks", acct0.ledger.gained == 380000 + 50000 and acct0.ledger.spent == 128800 + 20000 and acct0.chars == 2 and G.metric("net", "account", "today") == 380000 + 50000 - 128800 - 20000)
  check("who: the realm leaves the other realm out", G.metric("balance", "realm") == realm.total and G.metric("balance", "account") == all.total)
  G.cfg(true).hidden = { A = true }
  local hid = G.roster("all")
  check("hidden: the character leaves the total and the count at once, and stays listed", hid.total == all.total - 961000 and hid.count == 5 and hid.hidden == 1 and row(hid, "A").hidden == true and row(hid, "A").counted == false)
  check("hidden: every period sum and metric follows, nothing is stored to go stale", G.period("today", "account").ledger.gained == 380000 and G.metric("balance", "account") == all.total - 961000 and G.metric("earned", "realm", "today") == 380000)
  check("hidden: the flag is a display setting; the character's block is not written", chars.A.hidden == nil and ns.DB.settings.gold.hidden.A == true)
  G.cfg(true).hidden = nil
  check("hidden: shown again, the totals are back", G.roster("all").total == all.total)

  -- ── 30 characters, the stale ones marked ────────────────────────────────────────────────────────────────────
  for i = 1, 30 do
    chars["X" .. i] = { name = "Alt" .. i, realm = REALM, class = "HUNTER", faction = "Alliance", level = i, seen = now - i * 5 * DAY, gold = { balance = i * 10000 } }
  end
  local big = G.roster("all")
  local staleN, staleSum, sumX = 0, 0, 0
  for i = 1, 30 do sumX = sumX + i * 10000; if i * 5 > 90 then staleN = staleN + 1; staleSum = staleSum + i * 10000 end end
  check("30 characters: all listed", #big.rows == 36)
  check("30 characters: those not seen for more than 90 days are marked stale and left out of the default total", big.stale == staleN and staleN == 12 and big.total == all.total + sumX - staleSum and big.count == 36 - staleN
    and row(big, "X19").stale == true and row(big, "X19").counted == false and row(big, "X18").stale == false, big.stale)
  local withStale = G.roster("all", true)
  check("30 characters: included on request, they are in the total again", withStale.total == all.total + sumX and withStale.count == 36 and row(withStale, "X19").counted == true)
  check("30 characters: the logged-in character is never stale", row(big, ME).stale == false)

  -- ── the tooltip block against a fake tooltip ────────────────────────────────────────────────────────────────
  local function fake()
    local t = { lines = {} }
    function t:AddLine(text, r, g, b) self.lines[#self.lines + 1] = { left = text, r = r, g = g, b = b } end
    function t:AddDoubleLine(l, rt, r, g, b) self.lines[#self.lines + 1] = { left = l, right = rt, r = r, g = g, b = b } end
    return t
  end
  local function find(t, pat) for i, l in ipairs(t.lines) do if l.left:find(pat) then return l, i end end end
  local tip = fake()
  local n = G.tooltip(tip)
  check("tooltip: the block stays inside its 18 lines with 36 characters known", n == #tip.lines and n <= 18 and n >= 12, n)
  check("tooltip: this character's balance, today with in and out, and the session", find(tip, "^THIS CHARACTER$") and find(tip, "^Balance$").right == ns.fmtMoney(myBal)
    and find(tip, "^Today$").right:find("^%+" .. ns.fmtMoney(251200):gsub("%p", "%%%0")) ~= nil and find(tip, "^Today$").right:find("in " .. ns.fmtMoney(380000), 1, true) ~= nil
    and find(tip, "^Today$").right:find("out " .. ns.fmtMoney(128800), 1, true) ~= nil and find(tip, "^This session$") ~= nil, find(tip, "^Today$") and find(tip, "^Today$").right)
  check("tooltip: the top sources of today", find(tip, "^TOP TODAY$") ~= nil and find(tip, "^Unexplained " .. ns.fmtMoney(380000):gsub("%p", "%%%0")) ~= nil)
  local _, headI = find(tip, "^ACCOUNT  ·  %d+ characters$")
  check("tooltip: the account header counts the characters in the total", headI ~= nil and tip.lines[headI].left == ("ACCOUNT  ·  %d characters"):format(big.count), headI and tip.lines[headI].left)
  check("tooltip: the current character is pinned first under the header, with its level", headI and tip.lines[headI + 1].left == "> Hart Hammershield  " .. M.level and tip.lines[headI + 1].right == ns.fmtMoney(myBal), headI and tip.lines[headI + 1].left)
  check("tooltip: other characters carry their age", headI and tip.lines[headI + 2].left:find("^   ") ~= nil and tip.lines[headI + 2].right:find("seen ", 1, true) ~= nil)
  local more = find(tip, "^and %d+ more$")
  local listed = 0
  for i = headI + 1, #tip.lines do if tip.lines[i].left:find("^> ") or tip.lines[i].left:find("^   ") then listed = listed + 1 end end
  check("tooltip: at most 8 characters, then how many more", listed <= 8 and more ~= nil and tonumber(more.left:match("%d+")) == big.count - listed, listed)
  check("tooltip: the total with its oldest balance date", find(tip, "^Total$") ~= nil and find(tip, "^Total$").right:find(ns.fmtMoney(big.total), 1, true) == 1 and find(tip, "^Total$").right:find("oldest balance from", 1, true) ~= nil)
  check("tooltip: today's unexplained changes are counted", find(tip, "^2 unexplained changes today$") ~= nil)
  -- the current character stays pinned when it is the poorest
  local keepBal = c.gold.balance
  c.gold.balance = 1
  tip = fake(); G.tooltip(tip)
  _, headI = find(tip, "^ACCOUNT")
  check("tooltip: the current character is listed first even when 35 others hold more", tip.lines[headI + 1].left:find("^> Hart Hammershield") ~= nil and #tip.lines <= 18)
  c.gold.balance = keepBal
  -- a smaller budget gives way in the roster, never in the character's own lines
  local small = G.tipLines({ budget = 10 })
  local okSmall = #small <= 10 and small[1].left == "THIS CHARACTER" and small[2].left == "Balance"
  local pinned = false
  for _, l in ipairs(small) do if l.left:find("^> Hart") then pinned = true end end
  check("tooltip: a budget of 10 lines is kept, the current character still listed", okSmall and pinned, #small)
  -- the filter of the Characters view is the tooltip's too
  G.cfg(true).filter = "realmFaction"
  tip = fake(); G.tooltip(tip)
  check("tooltip: the saved filter names the block", find(tip, "^THIS REALM AND FACTION  ·  ") ~= nil)
  G.cfg(true).filter = nil
  -- one character: no account block
  local saved = {}
  for k, v in pairs(chars) do if k ~= ME then saved[k] = v; chars[k] = nil end end
  tip = fake(); G.tooltip(tip)
  check("tooltip: with one character there is no account block", find(tip, "^ACCOUNT") == nil and find(tip, "^Total$") == nil and find(tip, "^Balance$") ~= nil)
  for k, v in pairs(saved) do chars[k] = v end
  -- off in the settings
  G.cfg(true).tips = false
  tip = fake()
  check("tooltip: settings.gold.tips = false adds nothing", G.tooltip(tip) == 0 and #tip.lines == 0)
  G.cfg(true).tips = nil

  -- ── the minimap button: the block under its two lines, live only while the tooltip is the button's ──────────
  do
    pcall(UI.buildMinimapButton)
    local b = UI.minimapBtn
    local gt = _G.GameTooltip
    check("minimap: the button exists", b ~= nil)
    gt:Hide()
    b.scripts.OnEnter(b)
    check("minimap: the two help lines, then the gold block", gt.owner == b and gt.lines[1] == "everbuff.gg" and gt.lines[2]:find("Left-click", 1, true) == 1 and gt.lines[3] == "THIS CHARACTER" and #gt.lines <= 20, gt.lines[3])
    local function balLine() for _, l in ipairs(gt.lines) do if type(l) == "string" and l:find("^Balance  ") then return l end end end
    check("minimap: the balance line is the purse", balLine() == "Balance  " .. ns.fmtMoney(M.money), balLine())
    money(500)
    check("minimap: while it is open the block follows the purse, in the frame of the change", balLine() == "Balance  " .. ns.fmtMoney(M.money) and gt.owner == b, balLine())
    b.scripts.OnLeave(b)
    gt.lines = {}
    money(500)
    check("minimap: once the tooltip is closed a change draws nothing", #gt.lines == 0 and gt.owner == nil)
    local otherFrame = CreateFrame("Frame")
    gt:SetOwner(otherFrame, "ANCHOR_NONE"); gt:AddLine("someone else's tooltip")
    money(500)
    check("minimap: a tooltip another frame owns is never touched", #gt.lines == 1 and gt.lines[1] == "someone else's tooltip")
    gt:Hide()
    G.cfg(true).tips = false
    b.scripts.OnEnter(b)
    check("minimap: with the gold block off the tooltip is the two lines it always was", #gt.lines == 2)
    b.scripts.OnLeave(b)
    G.cfg(true).tips = nil
  end

  -- ── the change callback ─────────────────────────────────────────────────────────────────────────────────────
  do
    local fired = 0
    G.onChange(function() fired = fired + 1 end)
    money(10); money(-5)
    check("onChange: once per purse change", fired == 2, fired)
    G.onChange(function() error("a subscriber that throws") end)
    money(1)
    check("onChange: a throwing subscriber stops nobody", fired == 3)
    G._subs[#G._subs] = nil; G._subs[#G._subs] = nil
  end

  -- ── /eb gold and /eb gold chars ─────────────────────────────────────────────────────────────────────────────
  do
    local function run(arg) said = {}; SlashCmdList.EVERBUFF(arg); local out = {}; for i, s in ipairs(said) do out[i] = s end; return out end
    local out = run("gold")
    check("/eb gold: four lines", #out == 4, #out)
    check("/eb gold: the balance and the account total", out[1] and out[1]:find("gold: " .. ns.fmtMoney(M.money), 1, true) ~= nil and out[1]:find("all characters", 1, true) ~= nil and out[1]:find("oldest balance from", 1, true) ~= nil, out[1])
    check("/eb gold: today, the session and the rate", out[2] and out[2]:find("today: +", 1, true) ~= nil and out[2]:find("in ", 1, true) ~= nil and out[3]:find("this session: ", 1, true) ~= nil and out[4]:find("per hour: ", 1, true) ~= nil, out[2])
    out = run("  GOLD   Chars ")
    check("/eb gold chars: read from the raw argument, one line per character and the total", #out == #G.roster("all").rows + 1 and out[#out]:find("total: ", 1, true) ~= nil, #out)
    local mine, stale
    for _, s in ipairs(out) do
      if s:find("> Hart Hammershield", 1, true) and s:find("you", 1, true) then mine = true end
      if s:find("Alt30", 1, true) and s:find("not in the total", 1, true) then stale = true end
    end
    check("/eb gold chars: the current character is marked, a stale one says it is not in the total", mine and stale)
    out = run("gold nonsense")
    check("/eb gold with an unknown word names the two commands", #out == 1 and out[1]:find("/eb gold chars", 1, true) ~= nil)
    M.inCombat = true
    out = run("gold")
    check("/eb gold answers in combat: it opens, moves and changes nothing", #out == 4)
    out = run("status")
    check("/eb status still waits for the fight to end", #out == 1 and out[1]:find("not during combat", 1, true) ~= nil, out[1])
    M.inCombat = false
    local okDash = true
    for _, s in ipairs(run("gold chars")) do if s:find("\226\128\148", 1, true) then okDash = false end end
    for _, l in ipairs(G.tipLines()) do if (l.left .. (l.right or "")):find("\226\128\148", 1, true) then okDash = false end end
    check("copy: no em dash in the chat replies or the tooltip", okDash)
  end

  -- ── the suite's save file and client back in place ──────────────────────────────────────────────────────────
  _G.GetRealmName, _G.UnitName, _G.UnitNameUnmodified, _G.C_PlayerInfo = real.realm, real.unitName, real.unmod, real.playerInfo
  ns.Recorder.discard()
  ns.DB = main.db
  G._held, G._baseWait, G._flushTimer, G._tickAt = nil, nil, nil, nil
  E._openGain, E._questMoney = nil, nil
  M.timers = {}
  M.epoch, M.now, M.money = main.epoch, M.now + 100, main.money
  ns._test.newLoad()
  M.fire("PLAYER_ENTERING_WORLD", false, true); M.runTimers()
  print = realPrint
  check("roster: the suite's save file is back, its session resumed", ns.DB == main.db and ns.Recorder.current() ~= nil and ns.DB.characters[ME].gold.balance == main.money and ns.DB.characters[ME].name == "Hart" and ns.DB.characters[ME].realm == "Realm")
end
