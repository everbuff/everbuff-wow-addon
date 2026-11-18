-- Pane tests: transfers and refunds (everbuff-wow-addon #43, 0.9.48), with the layout engine of tests/geometry.lua.
--   Home / Sessions          the band's moved line (first in FLAGS, whatever else is flagged), the net of the title,
--                            of the list's gold column and of the strip without what moved
--   Settings / Gold / More   "My characters on other accounts": none, four marks (a WoW Forever length realm), the
--                            names as the player knows them, nothing cut, "Not mine"
--   Loot / Gold, Characters  the account bank's row and its tooltip at the smallest window
--   Loot / Gold, an account  the unmatched transfers line: not for the account bank alone, a plain line otherwise
return function(P)
  local M, ns = P.M, P.ns
  local realPrint = print
  local function check(name, cond, detail) local mine = print; print = realPrint; P.check(name, cond, detail); print = mine end
  local UI, Gold = ns.UI, ns.Gold
  local G = P.G
  local fmt = ns.fmtMoney
  local tip = _G.GameTooltip
  local T = "0.9.48 "
  local function click(b, button) b.scripts.OnClick(b, button or "LeftButton"); M.settle() end
  local function shown(rows) local out = {}; for _, r in ipairs(rows or {}) do if r.shown ~= false then out[#out + 1] = r end end return out end
  local savedCurrent = ns.Recorder.current
  ns.Recorder.current = function() return ns.DB.active and ns.DB.sessions[ns.DB.active] or nil end
  local savedBank = M.accountBank
  print = function() end
  local function layout(tag)
    local found = {}
    for _, x in ipairs(P.Lay.audit(M.frames)) do found[#found + 1] = ("%s: %s (%s)"):format(x.kind, x.text, x.detail) end
    check(tag .. ": no text spills out of its box, over another text, or a number cut short", #found == 0, table.concat(found, " || "):sub(1, 400))
  end

  -- ── Home / Sessions: a session with a transfer out ──────────────────────────────────────────────────────────
  for _, size in ipairs({ { 900, 580 }, { 1250, 760 } }) do
    local tag = (T .. "Sessions %dx%d"):format(size[1], size[2])
    local c = P.open("home", "sessions", size[1], size[2], "gold")
    local ses = ns.Recorder.current()
    local before = Gold.sessionNet(ses)
    -- 100g mailed to an own character in the running session, as Emitter books it: spent and xferOut, both ledgers
    local X = 1000000
    ses.spent, ses.gold.spent, ses.gold.xferOut = ses.spent + X, ses.gold.spent + X, (ses.gold.xferOut or 0) + X
    ses.goldV = 2
    ns.UI.Open("Home", "sessions"); M.settle()
    ns._test.journeyRefresh(); M.settle()
    local band = c.goldBand
    local sum = Gold.summary(ses)
    check(tag .. ": the session's net is not moved by the transfer", Gold.sessionNet(ses) == before and sum.net == before and sum.moved == -X and ses.gained - ses.spent == before - X)
    check(tag .. ": the band's title carries the net without the transfer", band.title.text:find("net " .. Gold.signed(before), 1, true) ~= nil, band.title.text)
    local L = band.blocks[4].lines
    check(tag .. ": the moved line is first in FLAGS, the flags follow it", L[1].text == "Moved between your characters: " .. fmt(X) .. " out" and L[2].text:find("^Strangers: ") ~= nil and L[3].text:find("^Unexplained: ") ~= nil,
      ("%s | %s | %s"):format(tostring(L[1].text), tostring(L[2].text), tostring(L[3].text)))
    local bb, bad = P.box(band), {}
    for _, b in ipairs(band.blocks) do
      for _, fs in ipairs(b.lines) do
        local fb = P.box(fs)
        if (fs.text or "") ~= "" and fb and fb.t + fb.h > bb.t + bb.h - 4 then bad[#bad + 1] = fs.text end
      end
    end
    check(tag .. ": every line of the band stays inside it", #bad == 0, table.concat(bad, "; "))
    local row
    for _, r in ipairs(shown(c.tbl.rows)) do if r.item == ses then row = r end end
    check(tag .. ": the list's gold column shows the net without the transfer", row ~= nil and row.c.gold.text == (before < 0 and "-" or "+") .. ns._test.journeyMoney(math.abs(before)), row and row.c.gold.text)
    local strip = ns._test.stripValues(ns._test.sessionRows(), "gained", true)
    local live
    for _, e in ipairs(strip) do if e.live then live = e end end
    check(tag .. ": the strip's bar of the running session is the net without the transfer", live ~= nil and live.v == before, live and live.v)
    check(tag .. ": no pane error", #ns.UI.paneErrors() == 0, table.concat(ns.UI.paneErrors(), " || "))
    -- a session with nothing moved has no such line
    c = P.open("home", "sessions", size[1], size[2], "gold")
    ns.UI.Open("Home", "sessions"); M.settle()
    check(tag .. ": a session with no transfer has no moved line", c.goldBand.blocks[4].lines[1].text:find("^Moved between") == nil, c.goldBand.blocks[4].lines[1].text)
  end

  -- ── Settings / Gold / More: My characters on other accounts ─────────────────────────────────────────────────
  local function settings(w, h)
    local c = P.open("Settings", nil, w, h, "gold")
    if c and c.subtabs then c.subtabs.select("gold"); M.settle() end
    local pane = c and c.subtabs and c.subtabs.panes.gold
    if pane and pane.refresh then pane.more:Hide(); pane.main:Show(); pane.refresh(); M.settle() end
    return pane
  end
  -- (the audit of tests/panes/goldglance.lua: every control inside the pane, no text over another, none cut)
  local function audit(pane, tag)
    local pb = P.box(pane)
    local out, texts = {}, {}
    for _, f in ipairs(P.descendants(pane)) do
      if P.visible(f) and (f._kind == "Button" or f._kind == "CheckButton" or f._kind == "Slider" or (f._isFS and (f.text or "") ~= "")) then
        local b = P.box(f)
        if b and b.w > 0 then
          local h = b.h
          if f._isFS then h = select(2, G.textSize(f, b.w)) end
          if b.l < pb.l - 0.5 or b.l + b.w > pb.l + pb.w + 0.5 or b.t + h > pb.t + pb.h + 0.5 then
            out[#out + 1] = ("%s ends at %d,%d of %d,%d"):format(tostring((f._isFS and f.text) or (type(f.text) == "table" and f.text.text) or f._kind):sub(1, 24), b.l + b.w - pb.l, b.t + h - pb.t, pb.w, pb.h)
          end
          if f._isFS and f.parentFrame and f.parentFrame._kind ~= "Button" then
            if f:IsTruncated() and f._wrap == false then out[#out + 1] = "cut: " .. tostring(f.text):sub(1, 24) end
            texts[#texts + 1] = { f = f, b = b, h = h }
          end
        end
      end
    end
    for i = 1, #texts do
      for j = i + 1, #texts do
        local a, b = texts[i], texts[j]
        if a.b.l < b.b.l + b.b.w and b.b.l < a.b.l + a.b.w and a.b.t < b.b.t + b.h - 0.5 and b.b.t < a.b.t + a.h - 0.5 then
          out[#out + 1] = ("'%s' over '%s'"):format(tostring(a.f.text):sub(1, 18), tostring(b.f.text):sub(1, 18))
        end
      end
    end
    check(tag, #out == 0, table.concat(out, "; "))
  end
  local FOREVER = "foreverrealm[eu]azuredawnsrest"
  for _, size in ipairs({ { 900, 580 }, { 1250, 760 } }) do
    local tag = (T .. "Settings Gold More %dx%d"):format(size[1], size[2])
    local pane = settings(size[1], size[2])
    check(tag .. ": the Gold sub-tab is there", pane ~= nil and pane.mineRows ~= nil and #pane.mineRows == 3)
    if pane and pane.mineRows then
      ns.DB.settings.gold = ns.DB.settings.gold or {}
      ns.DB.settings.gold.mine = nil
      pane.refresh(); M.settle()
      click(pane.moreBtn)
      check(tag .. ": with no mark the list says how to make one", P.visible(pane.mineNone) and pane.mineNone.text:find("^None%.") ~= nil and pane.mineRows[1].btn.shown == false and pane.mineMore.text == "")
      audit(pane, tag .. ": no mark: every control inside the pane, no text over another")
      ns.DB.settings.gold.mine = { ["otheracct banker-" .. FOREVER] = true, ["mira stonefist-" .. FOREVER] = true, ["solo-" .. FOREVER] = true,
        ["zed o'neill-" .. FOREVER] = true, ["mira stonefist-otherrealm"] = true }
      pane.refresh(); M.settle()
      check(tag .. ": a mark is listed by its name, not by its storage key", pane.mineRows[1].name.text == "Mira Stonefist (" .. FOREVER .. ")" and pane.mineRows[2].name.text == "Mira Stonefist (otherrealm)"
        and pane.mineRows[3].name.text == "Otheracct Banker" and pane.mineRows[3].btn.key == "otheracct banker-" .. FOREVER, pane.mineRows[1].name.text .. " | " .. pane.mineRows[3].name.text)
      check(tag .. ": three rows with Not mine, the rest counted, the empty note gone", pane.mineRows[3].btn.shown ~= false and pane.mineRows[3].btn.text.text == "Not mine" and pane.mineMore.text == "and 2 more" and not P.visible(pane.mineNone), pane.mineMore.text)
      -- the audit names a text cut short: a name alone is never cut (the same name on two realms carries the realm, which may be)
      ns.DB.settings.gold.mine["mira stonefist-otherrealm"] = nil
      pane.refresh(); M.settle()
      check(tag .. ": a name that is not repeated carries no realm", pane.mineRows[1].name.text == "Mira Stonefist" and pane.mineRows[2].name.text == "Otheracct Banker" and pane.mineRows[3].name.text == "Solo" and pane.mineMore.text == "and 1 more")
      audit(pane, tag .. ": four marks on a WoW Forever length realm: nothing outside the pane, over another text, or cut")
      click(pane.mineRows[2].btn)
      check(tag .. ": Not mine takes the mark away and the list moves up", ns.DB.settings.gold.mine["otheracct banker-" .. FOREVER] == nil and not Gold.isMine("Otheracct Banker") and pane.mineRows[2].name.text == "Solo"
        and pane.mineRows[3].name.text == "Zed O'neill" and pane.mineMore.text == "", pane.mineRows[2].name.text .. " | " .. pane.mineRows[3].name.text)
      click(pane.mineRows[1].btn); click(pane.mineRows[1].btn); click(pane.mineRows[1].btn)
      check(tag .. ": the last mark gone leaves no empty table and the note is back", ns.DB.settings.gold.mine == nil and P.visible(pane.mineNone) and pane.mineRows[1].btn.shown == false)
      audit(pane, tag .. ": after the last Not mine")
      click(pane.backBtn)
    end
  end

  -- ── Loot / Gold, Characters: the account bank's row ──────────────────────────────────────────────────────────
  for _, size in ipairs({ { 900, 580 }, { 1250, 760 } }) do
    local tag = (T .. "Characters %dx%d"):format(size[1], size[2])
    local c = P.open("loot", "gold", size[1], size[2], "gold")
    M.accountBank = true
    local at = M.epoch - 3 * 3600
    ns.char().goldBank = { balance = 7770000, at = at }
    Gold.open("week", "chars"); M.settle()
    c.setWho("account"); M.settle()
    local ct = (c.wide and c.tblChars or c.tblCharsNarrow)
    local rows = shown(ct.rows)
    local ro = Gold.roster("all")
    local bank = rows[2]
    check(tag .. ": the account bank is a row of its own under the total", rows[1].item.total == true and bank and bank.item.bank == true and bank.c.name.text == "Account bank" and bank.c.balance.text == fmt(7770000)
      and bank.c.today.text == "" and bank.c.d7.text == "" and bank.c.seen.text == "as of " .. Gold.fmtAge(at, M.epoch), bank and (bank.c.name.text .. " " .. bank.c.seen.text))
    check(tag .. ": the total holds it and the status line says so", ro.bank and ro.bank.counted == true and rows[1].c.balance.text == fmt(ro.total) and c.cBalance.value.text == fmt(ro.total)
      and c.status.text:find("account bank as of", 1, true) ~= nil, c.status.text)
    if c.wide and bank then check(tag .. ": the wide table gives its share of the total", bank.c.share.text == ("%d%%"):format(math.floor(7770000 / ro.total * 100 + 0.5)) and bank.c.realm.text == "" and bank.c.level.text == "", bank.c.share.text) end
    layout(tag)
    if bank then
      bank.scripts.OnEnter(bank)
      local text = table.concat(tip.lines, " | ")
      check(tag .. ": its tooltip gives the balance, the moment of the read and where it counts", text:find("Account bank  " .. fmt(7770000), 1, true) ~= nil and text:find("Balance as of " .. date("%b %d, %H:%M", at), 1, true) ~= nil
        and text:find("Part of the account's total.", 1, true) ~= nil, text)
      bank.scripts.OnLeave(bank)
      local was = c.menu.shown
      click(bank)
      check(tag .. ": a click on it opens no menu (it cannot be hidden from totals)", c.menu.shown == was or c.menu.shown == false)
    end
    -- off again: no row
    M.accountBank = savedBank
    Gold.open("week", "chars"); M.settle(); c.setWho("account"); M.settle()
    check(tag .. ": with the account bank off there is no such row", (function() for _, r in ipairs(shown(ct.rows)) do if r.item and r.item.bank then return false end end return true end)())
    check(tag .. ": no pane error", #ns.UI.paneErrors() == 0, table.concat(ns.UI.paneErrors(), " || "))
  end

  -- ── Loot / Gold, an account: the unmatched transfers line ────────────────────────────────────────────────────
  do
    local tag = T .. "Unmatched 900x580"
    local c = P.open("loot", "gold", 900, 580, "gold")
    M.accountBank = true
    local g = ns.char().gold
    -- (the gold data's own transfers have one side only: they are made legs with a character on another account, so
    -- the data starts with nothing unmatched)
    g.xferSolo = (g.xferSolo or 0) - Gold.unmatched(Gold.scope("all", "account").ledger)
    check(tag .. ": the data starts with nothing unmatched", Gold.unmatchedText(Gold.scope("all", "account").ledger) == nil)
    -- one account bank deposit and no other transfer, as Emitter books it on the lifetime ledger
    g.spent, g.xferOut, g.xferSolo = (g.spent or 0) + 40000, (g.xferOut or 0) + 40000, (g.xferSolo or 0) - 40000
    Gold.open("all", "sources"); M.settle()
    c.setWho("account"); M.settle()
    check(tag .. ": an account bank deposit alone shows no unmatched line", c.statusText:find("Unmatched transfers", 1, true) == nil and c.statusText:find("Moved between your characters: ", 1, true) ~= nil, c.statusText)
    -- a mail to an own character whose other leg is not in the save file
    g.spent, g.xferOut = g.spent + 5000, g.xferOut + 5000
    Gold.open("all", "sources"); M.settle()
    c.setWho("account"); M.settle()
    local at = c.statusText:find("Unmatched transfers: " .. fmt(5000) .. " (the other side was not recorded here)", 1, true)
    check(tag .. ": a leg with no other side is said, after what the sums leave out", at ~= nil and at > 1 and c.statusText:find("or it is in the account bank", 1, true) == nil, c.statusText)
    layout(tag)
    c.setWho("char"); M.settle()
    check(tag .. ": one character's scope never has the line", c.statusText:find("Unmatched transfers", 1, true) == nil, c.statusText)
    M.accountBank = savedBank
  end

  M.accountBank = savedBank
  ns.Recorder.current = savedCurrent
  print = realPrint
end
