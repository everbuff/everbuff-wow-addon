-- The shared formatters of docs/UX_OVERHAUL.md 2.6: one dialect for times, dates, durations, deltas, numbers, plurals
-- and money. Run from tests/run_tests.lua with { check = check, ns = ns }.
return function(ctx)
  local check, ns = ctx.check, ctx.ns
  local UI = ns.UI
  local function eq(name, got, want) check(name, got == want, ("got %s, want %s"):format(tostring(got), tostring(want))) end
  local now = os.time({ year = 2026, month = 11, day = 18, hour = 21, min = 35, sec = 0 })   -- a Wednesday

  -- clock and dates
  eq("fmtClock", UI.fmtClock(now), "21:35")
  eq("fmtDate: today", UI.fmtDate(now - 3600, now), "Today")
  eq("fmtDate: yesterday", UI.fmtDate(now - 86400, now), "Yesterday")
  eq("fmtDate: this year", UI.fmtDate(now - 2 * 86400, now), "Mon 16 Nov")
  eq("fmtDate: an earlier year", UI.fmtDate(now - 366 * 86400, now), "17 Nov 2025")
  eq("fmtWhen: today", UI.fmtWhen(now - 60, now), "Today 21:34")
  eq("fmtWhen: this year", UI.fmtWhen(now - 2 * 86400, now), "Mon 16 Nov, 21:35")
  eq("fmtWhen: an earlier year has no clock", UI.fmtWhen(now - 366 * 86400, now), "17 Nov 2025")
  eq("fmtDay: today", UI.fmtDay(now, now), "TODAY")
  eq("fmtDay: yesterday", UI.fmtDay(now - 86400, now), "YESTERDAY")
  eq("fmtDay: this year", UI.fmtDay(now - 2 * 86400, now), "MONDAY 16 NOV")
  eq("fmtDay: an earlier year", UI.fmtDay(now - 366 * 86400, now), "MONDAY 17 NOV 2025")
  eq("fmtRange", UI.fmtRange(now - 2280, now), "20:57 to 21:35")
  eq("fmtRange: live", UI.fmtRange(now - 2280, nil, true), "20:57 to now")

  -- durations: words, never mm:ss
  eq("fmtDur: 0", UI.fmtDur(0), "0s")
  eq("fmtDur: 45s", UI.fmtDur(45), "45s")
  eq("fmtDur: 10m 5s", UI.fmtDur(605), "10m 5s")
  eq("fmtDur: 10m", UI.fmtDur(600), "10m")
  eq("fmtDur: hours", UI.fmtDur(5940), "1h 39m")
  eq("fmtDur: days", UI.fmtDur(2 * 86400 + 4 * 3600), "2d 4h")
  eq("fmtDur: to the minute", UI.fmtDur(2290, { minutes = true }), "38m")
  eq("fmtDur: a broken value", UI.fmtDur(nil), "-")
  eq("fmtDur: a negative value is 0s", UI.fmtDur(-5), "0s")
  for _, s in ipairs({ 5, 65, 605, 3600, 5940, 90000 }) do
    check("fmtDur: no mm:ss for " .. s, not UI.fmtDur(s):find(":", 1, true), UI.fmtDur(s))
  end

  -- deltas: faster is good, slower is warn, with words
  local t, c = UI.fmtDelta(-42)
  check("fmtDelta: 42s faster in good", t == "42s faster" and c == "good", t)
  t, c = UI.fmtDelta(75)
  check("fmtDelta: 1m 15s slower in warn", t == "1m 15s slower" and c == "warn", t)
  t = UI.fmtDelta(nil, { first = true })
  check("fmtDelta: a first run says so", type(t) == "string" and t ~= "", t)

  -- numbers and plurals
  eq("fmtNum: grouping", UI.fmtNum(1234567), "1,234,567")
  eq("fmtNum: negative", UI.fmtNum(-1500), "-1,500")
  eq("fmtNum: NaN", UI.fmtNum(0 / 0), "-")
  eq("plural: 0 items", UI.plural(0, "item"), "0 items")
  eq("plural: 1 item", UI.plural(1, "item"), "1 item")
  eq("plural: 2 entries", UI.plural(2, "entry"), "2 entries")
  eq("plural: 2 bosses", UI.plural(2, "boss"), "2 bosses")
  eq("plural: 2 copies", UI.plural(2, "copy"), "2 copies")
  eq("plural: 1,200 fights", UI.plural(1200, "fight"), "1,200 fights")

  -- money: the two largest units with the coin icons; a plain text form without them
  local m = ns.fmtMoney(1234567, { units = 2 })
  eq("money: two units", m, "123g 45s")
  eq("money: a zero unit is skipped", ns.fmtMoney(1000005, { units = 2 }), "100g 5c")
  eq("money: copper only", ns.fmtMoney(7, { units = 2 }), "7c")
  eq("money: zero", ns.fmtMoney(0, { units = 2 }), "0c")
  eq("money: big gold is grouped", ns.fmtMoney(123456780000, { units = 2 }), "12,345,678g")
  local mi = UI.money(1234567)
  local icons = 0
  for _ in mi:gmatch("|T") do icons = icons + 1 end
  check("money: UI.money draws two coin icons and no letters", icons == 2 and not mi:find("%dg") and not mi:find("%ds"), mi)
  check("money: the icons are 12 px", mi:find(":12:12", 1, true) ~= nil, mi)

  -- nothing in the dialect writes an em dash
  local all = table.concat({ UI.fmtDur(605), UI.fmtDate(now, now), UI.fmtWhen(now - 2 * 86400, now), (UI.fmtDelta(-3)), UI.plural(2, "entry"), ns.fmtMoney(1234567, { units = 2 }) }, " ")
  check("formatters: no em dash", not all:find("\226\128\148", 1, true), all)
end
