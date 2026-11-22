-- Journal rows booked as mail with no sender (docs/UX_PRAGMATIC.md 0.2: nothing is shown that the stored data does
-- not say). Loaded by tests/run_tests.lua after the gold suites:
--   dofile("tests/gold_mailrows.lua")({ check = check, M = M, ns = ns })
-- The shapes are the founder's save of 21 Nov 2026: Fri 20 Nov 23:29, two gains of 4s 58c and 3s 12c booked as mail
-- in Tanaris, seconds after a kill there, while the only mailbox visit of that time was in Orgrimmar (#52: before
-- 0.9.52 the mailbox flag could outlive the visit). The pane said "Mail | mailbox | Tanaris" for them.
--   detail    a mail row with no sender has a blank Detail and "Sender not recorded" on hover, never "mailbox"
--   source    when the stored records place the coin away from every mailbox the Source cell reads "Source not seen";
--             when they cannot tell, it stays "Mail"
-- The suite's loot log, story events, sessions and clock are put back at the end.
return function(P)
  local check, M, ns = P.check, P.M, P.ns
  local Gold = ns.Gold
  local GP = Gold.GP
  local function eq(name, got, want) check(name, got == want, ("got %s, want %s"):format(tostring(got), tostring(want))) end

  local keep = { log = ns.DB.loot.log, events = ns.DB.story.events }
  local guid = ns.charGuid()
  local T = 1795213000
  local SID = "t-mailrows-1"
  local sess = { id = SID, guid = guid, startedEpoch = T, startedMono = 1000, endedEpoch = T + 3600, gained = 0, spent = 0, gold = {}, goldLog = {} }
  ns.DB.sessions[SID] = sess
  local bal = 1000000
  local function jr(at, delta, ref) bal = bal + delta; return ("%.1f\t%d\tmail\t%d\t%s"):format(1000 + at, delta, bal, ref or "") end
  local function coin(at, amount, zone) return { t = T + at, money = amount, src = "Mail", s = SID, zone = zone, x = 0.7634, y = 0.4547 } end
  local function build(events)
    ns.DB.story.events = events
    ns.DB.loot.log = {
      coin(100, 312, "Tanaris"),      -- a mailbox visit of that moment is stored, in Orgrimmar
      coin(200, 458, "Orgrimmar"),    -- the same visit, and the coin is stamped in Orgrimmar
      coin(900, 77, "Tanaris"),       -- no mailbox visit is stored for that moment
      coin(1000, 500, "Orgrimmar"),   -- a mail with its sender
    }
    sess.goldLog = { jr(100, 312), jr(200, 458), jr(900, 77), jr(1000, 500, "sender=Rando;rel=stranger;cod=0"), jr(1100, 123, "x=unmatched") }
    return Gold.entries(sess)
  end
  local function tipOf(e) local tip = _G.GameTooltip; tip:ClearLines(); GP.journalTip(nil, e, tip); return (table.concat(tip.lines or {}, "\n"):gsub("|T.-|t", "")) end
  local function cells(e) return (GP.srcWord(e)) .. "|" .. GP.detailOf(e) .. "|" .. tostring(e.zone) end

  -- the event list covers the session; one mailbox visit, in Orgrimmar, from T+50 to T+300
  local e = build({
    { kind = "ZONE", s = SID, t = T - 100, text = "x", zone = "Orgrimmar" },
    { kind = "MAIL", s = SID, t = T + 50, closed = T + 300, text = "Mailbox", zone = "Orgrimmar" },
  })
  eq("mail rows: five entries", #e, 5)
  eq("mail rows: coin stamped in Tanaris during a mailbox visit in Orgrimmar is not Mail: Source not seen, a blank Detail", cells(e[1]), "Source not seen||Tanaris")
  check("mail rows: its hover says why, and the stored row is untouched", e[1].unseen == true and e[1].src == "mail" and tipOf(e[1]):find("no mailbox was open", 1, true) ~= nil and sess.goldLog[1]:find("\tmail\t", 1, true) ~= nil, tipOf(e[1]))
  eq("mail rows: coin stamped where the mailbox visit was is Mail, with a blank Detail, never the word mailbox", cells(e[2]), "Mail||Orgrimmar")
  check("mail rows: its hover says Sender not recorded", e[2].unseen == nil and tipOf(e[2]):find("Sender not recorded", 1, true) ~= nil and tipOf(e[2]):find("mailbox", 1, true) == nil, tipOf(e[2]))
  eq("mail rows: no mailbox visit stored for that moment, and the event list covers it: Source not seen", cells(e[3]), "Source not seen||Tanaris")
  eq("mail rows: a mail with its sender says from whom", cells(e[4]), "Mail|from Rando (stranger)|Orgrimmar")
  check("mail rows: a gain at the mailbox that no taken mail matches keeps its own words", e[5].unseen == nil and GP.detailOf(e[5]) == "no mail taken has this amount", GP.detailOf(e[5]))
  local any = false
  for _, x in ipairs(e) do if (x.detail or ""):find("mailbox", 1, true) then any = true end end
  check("mail rows: no Detail says mailbox", not any)
  check("mail rows: the search finds the row by what it shows", GP.hay(e[1]):find("source not seen", 1, true) ~= nil and GP.hay(e[1]):find("mail", 1, true) == nil)

  -- the event list starts after the row (it holds the newest 500 events): nothing says where a mailbox was
  e = build({ { kind = "ZONE", s = SID, t = T + 950, text = "x", zone = "Tanaris" } })
  eq("mail rows: with no event stored from that time the row stays Mail (nothing proves otherwise), still with a blank Detail", cells(e[3]) .. " / " .. cells(e[1]), "Mail||Tanaris / Mail||Tanaris")
  check("mail rows: and says Sender not recorded on hover", e[3].unseen == nil and tipOf(e[3]):find("Sender not recorded", 1, true) ~= nil)

  ns.DB.sessions[SID] = nil
  ns.DB.loot.log = keep.log
  ns.DB.story.events = keep.events
end
