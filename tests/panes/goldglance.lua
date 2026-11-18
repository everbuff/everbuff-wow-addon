-- Pane tests: gold rate and glance (everbuff-wow-addon #43, 0.9.45), with the layout engine of tests/geometry.lua.
--   the first-run question   one row above the cards of Loot / Gold until it is answered
--   the pill                 as wide as its text, inside the screen at every scale and after the screen changes
--                            size, clear of the flag wherever the flag is, saved on creation
--   the PER HOUR card        the rolling rate of the running period, its title naming the definition, dimmed while
--                            it warms up, drawn again by the 10 s repaint without closing an open list
--   Settings / Gold          every control inside the pane at the smallest and the largest window, no text over
--                            another, the page behind "More", and what each control writes
return function(P)
  local M, ns = P.M, P.ns
  local realPrint = print
  -- (a failed check is printed with the real print, whatever the test has put in its place)
  local function check(name, cond, detail) local mine = print; print = realPrint; P.check(name, cond, detail); print = mine end
  local UI, Gold = ns.UI, ns.Gold
  local C = UI.C
  local G = P.G
  local function click(b, button) b.scripts.OnClick(b, button or "LeftButton"); M.settle() end
  local function tick(cb) cb.checked = not cb.checked; cb.scripts.OnClick(cb); M.settle() end
  local savedCurrent = ns.Recorder.current
  ns.Recorder.current = function() return ns.DB.active and ns.DB.sessions[ns.DB.active] or nil end
  print = function() end
  local saved = { epoch = M.epoch, now = M.now, view = { w = G.VIEW.w, h = G.VIEW.h }, tickAt = Gold._tickAt }
  local function open(w, h, scope)
    local c = P.open("loot", "gold", w, h, "gold")
    Gold.open(scope or "session"); M.settle()
    return c
  end
  local function pillBox()
    local p = Gold.pill
    local pc = ns.DB.settings.gold.pill
    local sc = pc.scale or 1
    local w, h = p:GetWidth() * sc, Gold.PILL_H * sc
    local l, b = Gold.cornerRect(pc.corner, pc.x, pc.y, w, h, G.VIEW.w, G.VIEW.h)
    return { l = l, b = b, w = w, h = h }
  end
  local function inside(r) return r.l >= -0.01 and r.b >= -0.01 and r.l + r.w <= G.VIEW.w + 0.01 and r.b + r.h <= G.VIEW.h + 0.01 end
  -- the flag and its notification line at its widest, from the Emitter's cap (not from Gold.flagRect): 600 x 40 at
  -- the flag's size, inward from the flag's corner or from where it was dragged to
  local function flagReach()
    local st = ns.DB.settings
    local fs = math.max(1, math.min(1.5, tonumber(st.flagScale) or 1))
    local fw, fh = ns.Emitter.TOAST_MAX_W * fs, 40 * fs
    local fc, fx, fy = st.emitCorner or "TOPLEFT", 0, 0
    if st.flagPos then fc, fx, fy = st.flagPos.point, st.flagPos.x * fs, st.flagPos.y * fs end
    local l, b = Gold.cornerRect(fc, fx, fy, fw, fh, G.VIEW.w, G.VIEW.h)
    return { l = l, b = b, w = fw, h = fh }
  end
  local function clearOfFlag(r)
    local fr = flagReach()
    local m = Gold.FLAG_MARGIN - 0.01
    return r.l >= fr.l + fr.w + m or r.l + r.w <= fr.l - m or r.b >= fr.b + fr.h + m or r.b + r.h <= fr.b - m
  end

  -- ── the first-run question ──────────────────────────────────────────────────────────────────────────────────
  for _, size in ipairs({ { 900, 580 }, { 1250, 760 } }) do
    local tag = ("Gold 0.9.45 %dx%d"):format(size[1], size[2])
    local c = open(size[1], size[2])
    check(tag .. ": the question of the pill is asked in a row of its own", c.askOn == true and P.visible(c.askRow) and c.askText.text:find("Show your gold on screen?", 1, true) == 1)
    local ab, cb, tb = P.box(c.askRow), P.box(c.cBalance), P.box(c.scopeBtns[1])
    check(tag .. ": the row sits between the toolbar and the cards", ab.t >= tb.t + tb.h and cb.t >= ab.t + ab.h + UI.SP.M - 0.5, ("%s %s %s"):format(tb.t + tb.h, ab.t, cb.t))
    local yb, nb, xb = P.box(c.askYes), P.box(c.askNo), P.box(c.askText)
    check(tag .. ": the text in full at the left, Yes and No at the right, nothing overlapping", not c.askText:IsTruncated() and xb.l + G.naturalWidth(c.askText) <= yb.l and yb.l + yb.w <= nb.l and nb.l + nb.w <= ab.l + ab.w + 0.5,
      ("text %d wide from %d, Yes at %d"):format(G.naturalWidth(c.askText), xb.l, yb.l))
    local cardsAt = cb.t
    click(c.askNo)
    check(tag .. ": No is remembered, the row goes and the cards move up into its place", ns.DB.settings.gold.pill.asked == true and ns.DB.settings.gold.pill.on == false and not P.visible(c.askRow)
      and math.abs(P.box(c.cBalance).t - (cardsAt - UI.ROW_H - UI.SP.M)) < 0.51 and (Gold.pill == nil or Gold.pill.shown == false), P.box(c.cBalance).t)
    c = open(size[1], size[2])
    check(tag .. ": asked again on a save file that never answered", P.visible(c.askRow))
    click(c.askYes)
    check(tag .. ": Yes turns the pill on and the row goes", ns.DB.settings.gold.pill.on == true and ns.DB.settings.gold.pill.asked == true and not P.visible(c.askRow) and Gold.pill ~= nil and Gold.pill.shown == true)
    Gold.pillOn(false)
  end

  -- ── the pill on the screen ──────────────────────────────────────────────────────────────────────────────────
  do
    open(900, 580)
    Gold.pillOn(true)
    local p, pc = Gold.pill, ns.DB.settings.gold.pill
    local b = P.box(p)
    check("pill: as wide as its text plus S on each side, 22 high", b ~= nil and math.abs(b.w - (math.ceil(G.naturalWidth(p.text)) + 2 * UI.SP.S)) < 0.51 and b.h == Gold.PILL_H, b and b.w)
    check("pill: its text fits it", not p.text:IsTruncated() and G.naturalWidth(p.text) <= b.w - 2 * UI.SP.S + 0.5)
    check("pill: a new pill sits under the flag's row, not beside it where the notification line runs", pc.corner == "TOPLEFT" and pc.x == Gold.FLAG_MARGIN and -pc.y >= 40 * 1.5 + Gold.FLAG_MARGIN, ("%s %s"):format(tostring(pc.x), tostring(pc.y)))
    check("pill: saved on creation, inside the screen, clear of the flag", pc.corner ~= nil and pc.x ~= nil and pc.y ~= nil and inside(pillBox()) and clearOfFlag(pillBox()), ("%s %s %s"):format(tostring(pc.corner), tostring(pc.x), tostring(pc.y)))
    check("pill: the box the layout resolves is the box the settings say", math.abs(b.l - pillBox().l) < 0.51 and math.abs((G.VIEW.h - b.t - b.h) - pillBox().b) < 0.51, ("%s vs %s"):format(b.l, pillBox().l))
    -- clear of the flag wherever the flag is, also when the pill was saved right on it
    local bad = {}
    for _, fc in ipairs({ "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }) do
      for _, fs in ipairs({ 1, 1.5 }) do
        ns.DB.settings.emitCorner, ns.DB.settings.flagScale, ns.DB.settings.flagPos = fc, fs, nil
        pc.corner, pc.x, pc.y = fc, fc:find("RIGHT") and -10 or 10, fc:find("TOP") and -10 or 10
        Gold.pillPlace()
        if not (inside(pillBox()) and clearOfFlag(pillBox())) then bad[#bad + 1] = fc .. " x" .. fs end
        Gold.pillOpt("pos")
        if not (inside(pillBox()) and clearOfFlag(pillBox())) then bad[#bad + 1] = fc .. " default x" .. fs end
      end
    end
    ns.DB.settings.flagPos = { point = "TOPLEFT", x = 700, y = -300 }
    pc.corner, pc.x, pc.y = "TOPLEFT", 750, -310
    Gold.pillPlace()
    if not (inside(pillBox()) and clearOfFlag(pillBox())) then bad[#bad + 1] = "dragged flag" end
    ns.DB.settings.flagPos, ns.DB.settings.emitCorner, ns.DB.settings.flagScale = nil, "TOPLEFT", 1
    check("pill: never over the flag or its notification line, for every flag corner and size and a dragged flag", #bad == 0, table.concat(bad, "; "))
    -- the notification line itself: however long its text, it is drawn no wider than the cap the pill keeps clear of
    do
      local toast = _G.EverbuffToast
      local q = ns._test.toastQueue()
      for i = #q, 1, -1 do q[i] = nil end
      M.now = M.now + 100
      ns.Emitter.event("QUESTDONE", { name = ("A quest with a name far too long for one line "):rep(6) })
      check("pill: the widest notification is drawn at exactly the cap it keeps clear of (600)", toast ~= nil and toast._w == ns.Emitter.TOAST_MAX_W and ns.Emitter.TOAST_MAX_W == 600, toast and toast._w)
      M.now = M.now + 100
    end
    -- the flag moves after the pill was placed: the pill makes way in the same call
    bad = {}
    local E = ns.Emitter
    pc.corner, pc.x, pc.y = "TOPRIGHT", -10, -10
    Gold.pillPlace()
    if not (pc.corner == "TOPRIGHT" and pc.y == -10) then bad[#bad + 1] = "start" end
    E.setCorner("TR")
    if not (inside(pillBox()) and clearOfFlag(pillBox())) then bad[#bad + 1] = "snapped onto it" end
    E.setCorner("TL")
    pc.corner, pc.x, pc.y = "BOTTOMLEFT", 300, 400
    Gold.pillPlace()
    E.setFlagPos("BOTTOMLEFT", 100, 390)
    if not (ns.DB.settings.flagPos and inside(pillBox()) and clearOfFlag(pillBox())) then bad[#bad + 1] = "dragged onto it" end
    E.setFlagPos(nil)
    pc.corner, pc.x, pc.y = "TOPLEFT", 700, -20
    Gold.pillPlace()
    if not (pc.x == 700 and pc.y == -20) then bad[#bad + 1] = "beside the 100 percent flag" end
    E.setFlagScale(1.5)
    if not (inside(pillBox()) and clearOfFlag(pillBox())) or (pc.x == 700 and pc.y == -20) then bad[#bad + 1] = "made bigger over it" end
    E.setFlagScale(1)
    ns.DB.settings.flagPos, ns.DB.settings.emitCorner, ns.DB.settings.flagScale = nil, "TOPLEFT", 1
    check("pill: it makes way when the flag is snapped onto it, dragged onto it or made bigger over it", #bad == 0, table.concat(bad, "; "))
    -- never off screen after a scale change, at the edge of every corner
    bad = {}
    for _, corner in ipairs({ "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }) do
      for _, sc in ipairs({ 0.5, 1, 2, 1.35, 0.5, 2 }) do
        pc.corner, pc.x, pc.y = corner, corner:find("RIGHT") and -G.VIEW.w + 30 or G.VIEW.w - 30, corner:find("TOP") and -G.VIEW.h + 5 or G.VIEW.h - 5
        Gold.pillOpt("scale", sc)
        if not inside(pillBox()) or pc.scale ~= sc then bad[#bad + 1] = corner .. " x" .. sc end
      end
    end
    check("pill: never off screen after a scale change", #bad == 0, table.concat(bad, "; "))
    Gold.pillOpt("scale", 9)
    check("pill: the text size is held between 50 and 200 percent", pc.scale == 2)
    Gold.pillOpt("scale", 0.1)
    check("pill: and not under 50 percent", pc.scale == 0.5)
    Gold.pillOpt("scale", 1); Gold.pillOpt("alpha", 0.05)
    check("pill: the opacity is held at 20 percent or more", pc.alpha == 0.2 and Gold.pill._alpha == 0.2)
    Gold.pillOpt("alpha", 1)
    -- the screen changes size: the pill comes back inside it
    pc.corner, pc.x, pc.y = "BOTTOMLEFT", 1700, 1000
    Gold.pillPlace()
    G.VIEW.w, G.VIEW.h = 1280, 720
    M.fire("UI_SCALE_CHANGED")
    check("pill: after the screen got smaller it is inside it again", inside(pillBox()) and clearOfFlag(pillBox()), pillBox().l .. " " .. pillBox().b)
    G.VIEW.w, G.VIEW.h = saved.view.w, saved.view.h
    M.fire("DISPLAY_SIZE_CHANGED")
    -- a longer text: the pill grows with it and stays inside the screen from a right-hand corner
    pc.corner, pc.x, pc.y = "TOPRIGHT", 0, -200
    Gold.pillPlace()
    local w0 = p:GetWidth()
    Gold.pillSet(2, "today"); Gold.pillOpt("label", true)
    check("pill: two labelled values make it wider, still inside the screen and fitting its text", p:GetWidth() > w0 and inside(pillBox()) and not p.text:IsTruncated(), p:GetWidth())
    M.inCombat = true
    local wc = p:GetWidth()
    Gold.pillSet(2, nil)
    check("pill: in combat a shorter text does not resize it", p:GetWidth() == wc and Gold._pillDirty == true)
    M.inCombat = false
    M.fire("PLAYER_REGEN_ENABLED")
    check("pill: after the fight it takes the width of its text", p:GetWidth() < wc and math.abs(p:GetWidth() - (math.ceil(G.naturalWidth(p.text)) + 2 * UI.SP.S)) < 0.51)
    -- a text that gets longer in a fight stays inside the pill (cut short), and is shown in full after it
    M.inCombat = true
    local ws = p:GetWidth()
    Gold.pillSet(2, "today"); M.settle()
    local tb, pb = P.box(p.text), P.box(p)
    check("pill: in combat a longer text does not resize it", p:GetWidth() == ws and G.naturalWidth(p.text) > ws - 2 * UI.SP.S)
    check("pill: and is not drawn outside it: the text is held to the pill's inner width", tb ~= nil and tb.w <= ws - 2 * UI.SP.S + 0.5 and tb.l >= pb.l + UI.SP.S - 0.5 and tb.l + tb.w <= pb.l + pb.w - UI.SP.S + 0.5 and p.text:IsTruncated(), tb and (tb.l .. " " .. tb.w))
    M.inCombat = false
    M.fire("PLAYER_REGEN_ENABLED"); M.settle()
    check("pill: after the fight it is in full again, the pill as wide as it", not p.text:IsTruncated() and p:GetWidth() > ws and math.abs(p:GetWidth() - (math.ceil(G.naturalWidth(p.text)) + 2 * UI.SP.S)) < 0.51 and inside(pillBox()), p:GetWidth())
    Gold.pillSet(2, nil); M.settle()
    -- the own menu opens under the pill, as wide as its longest entry
    local keepMenu = rawget(_G, "MenuUtil")
    _G.MenuUtil = nil
    p.scripts.OnMouseUp(p, "RightButton"); M.settle()
    local m = Gold._menu
    local mb = P.box(m)
    local fits = true
    for i = 1, m.count do if m.btns[i].text:IsTruncated() then fits = false end end
    check("pill: the own menu opens under it with every entry in full", m.shown == true and mb ~= nil and fits and math.abs(mb.t - (P.box(p).t + P.box(p).h + 2)) < 0.51, mb and mb.t)
    m:Hide(); m.owner = nil
    _G.MenuUtil = keepMenu
    Gold.pillOn(false)
    check("pill: turned off it is hidden", p.shown == false)
  end

  -- ── the PER HOUR card of a running period ───────────────────────────────────────────────────────────────────
  for _, size in ipairs({ { 900, 580 }, { 1600, 1000 } }) do
    local tag = ("Gold 0.9.45 %dx%d"):format(size[1], size[2])
    local c = open(size[1], size[2], "session")
    local r = Gold.rate()
    check(tag .. ": the fixture has a few active seconds, so the rate is warming up", r.perHour ~= nil and r.warm == true, tostring(r.active))
    check(tag .. ": the running session's card is the rolling rate, named, dimmed while it warms up", c.rateLive == true and c.cRate.title.text == "FARMING PER HOUR" and c.cRate.value.text:sub(-2) == "/h"
      and c.cRate.value._color[1] == C.dim[1] and c.cRate.value._color[2] == C.dim[2], c.cRate.title.text)
    check(tag .. ": the status line names the definition and the warm-up", c.status.text:find("Farming per hour, warming up %d:%d%d: looted coin, vendor sales and quest rewards over active time") ~= nil, c.status.text)
    check(tag .. ": title and value in full", not c.cRate.title:IsTruncated() and not c.cRate.value:IsTruncated())
    check(tag .. ": the open pane keeps the 10 s repaint running", Gold._rateTicker ~= nil and Gold.rateOnScreen() == true)
    -- five more minutes of play, then the repaint: the card leaves the warm-up, an open list stays open
    Gold._tickAt = M.now
    for _ = 1, 30 do M.now = M.now + 10; M.epoch = M.epoch + 10; Gold.tick() end
    click(c.viewBtn)
    check(tag .. ": a list is open", c.menu.shown == true)
    local before = c.status.text
    Gold._rateTicker.fn(); M.settle()
    check(tag .. ": the repaint draws the card past its warm-up", c.cRate.value._color[1] == C.ink[1] and c.cRate.value._color[2] == C.ink[2] and c.cRate.value.text:sub(-2) == "/h" and Gold.rate().warm == false)
    check(tag .. ": and the window in the status line, in place", c.status.text ~= before and c.status.text:find("Farming per hour, last %d+ min: ") ~= nil, c.status.text)
    check(tag .. ": the repaint does not close the open list", c.menu.shown == true)
    c.menu:Hide()
    Gold.open("today"); M.settle()
    check(tag .. ": Today shows the same rolling rate", c.rateLive == true and c.cRate.title.text == "FARMING PER HOUR")
    ns.DB.settings.gold = ns.DB.settings.gold or {}
    ns.DB.settings.gold.rateMode = "net"
    Gold.open("today"); M.settle()
    check(tag .. ": the per hour setting changes the card's definition", c.cRate.title.text == "NET PER HOUR" and c.cRate.value.text:find("^[%+%-]") ~= nil and c.status.text:find("Net per hour, last", 1, true) ~= nil, c.cRate.title.text)
    ns.DB.settings.gold.rateMode = nil
    Gold.open("all"); M.settle()
    check(tag .. ": All time keeps CHANGED WHILE AWAY", c.rateLive == false and c.cRate.title.text == "CHANGED WHILE AWAY")
    Gold.open("yesterday"); M.settle()
    check(tag .. ": a period that is over keeps its net over the time played", c.rateLive == false and c.cRate.title.text == "NET PER HOUR")
    c.setWho("account")
    Gold.open("today"); M.settle()
    c.setWho("account"); M.settle()
    check(tag .. ": an account has no rolling rate (the window is one character's)", c.rateLive == false and c.cRate.title.text == "NET PER HOUR PLAYED", c.cRate.title.text)
    c.setWho("char")
    M.epoch, M.now = saved.epoch, saved.now
  end
  _G.EverbuffFrame:Hide()
  Gold._rateTicker.fn()
  check("Gold 0.9.45: with the window closed the next tick stops the repaint", Gold._rateTicker == nil)
  _G.EverbuffFrame:Show()

  -- ── Settings / Gold ─────────────────────────────────────────────────────────────────────────────────────────
  local function settings(w, h)
    local c = P.open("Settings", nil, w, h, "gold")
    if c and c.subtabs then c.subtabs.select("gold"); M.settle() end
    local pane = c and c.subtabs and c.subtabs.panes.gold
    if pane and pane.refresh then pane.more:Hide(); pane.main:Show(); pane.refresh(); M.settle() end
    return pane
  end
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
  for _, size in ipairs({ { 900, 580 }, { 1250, 760 }, { 1600, 1000 } }) do
    local tag = ("Settings Gold %dx%d"):format(size[1], size[2])
    local pane = settings(size[1], size[2])
    check(tag .. ": the Gold sub-tab is there", pane ~= nil and pane.refresh ~= nil and P.visible(pane.main) and not P.visible(pane.more))
    if pane and pane.refresh then
      -- two hidden characters with long names, so the list has rows
      local n = 0
      ns.DB.settings.gold = ns.DB.settings.gold or {}
      ns.DB.settings.gold.hidden = {}
      for guid, blk in pairs(ns.DB.characters) do if n < 2 and type(blk) == "table" and blk.name then ns.DB.settings.gold.hidden[guid] = true; n = n + 1 end end
      ns.DB.settings.gold.hidden["Player-9-GONE"] = true
      pane.refresh(); M.settle()
      audit(pane, tag .. ": every control of the main page inside the pane, no text over another")
      check(tag .. ": the hidden characters are listed with Show again", pane.hiddenRows[1].btn.shown ~= false and pane.hiddenRows[n + 1].btn.shown ~= false and pane.hiddenRows[n + 2].btn.shown == false
        and (function() for i = 1, n + 1 do if pane.hiddenRows[i].name.text == "No longer in the save file" then return true end end end)() == true
        and not P.visible(pane.hiddenNone), pane.hiddenRows[1].name.text)
      click(pane.moreBtn)
      check(tag .. ": More opens the second page", P.visible(pane.more) and not P.visible(pane.main))
      audit(pane, tag .. ": every control behind More inside the pane, no text over another")
      click(pane.resetHist)
      audit(pane, tag .. ": the same with the reset button asking to confirm")
      M.runTimers()
      click(pane.backBtn)
      check(tag .. ": Back returns to the main page", P.visible(pane.main) and not P.visible(pane.more))
    end
  end
  -- what the controls write
  do
    local pane = settings(900, 580)
    local g = function() return ns.DB.settings.gold or {} end
    check("Settings Gold: the defaults: tooltips on, pill off, Farming, all characters, letters, full numbers", pane.cbTips.checked == true and pane.cbPill.checked == false and pane.pick1.text.text == "Balance"
      and pane.pick2.text.text == "None" and pane.rateBtns[1].ebSelected == true and pane.pickFilter.text.text == "All characters" and pane.cbIcons.checked == false and pane.cbCompact.checked == false, pane.pick1.text.text)
    check("Settings Gold: opening it wrote nothing", ns.DB.settings.gold == nil or (ns.DB.settings.gold.pill == nil and ns.DB.settings.gold.tip == nil and ns.DB.settings.gold.rateMode == nil))
    check("Settings Gold: without a bar addon it says what bar text needs", pane.barText.text == "Bar text needs a bar addon such as Titan Panel or ElvUI")
    Gold._broker = {}
    pane.refresh()
    check("Settings Gold: with one it says detected", pane.barText.text == "Bar text: detected")
    Gold._broker = nil
    tick(pane.cbTips)
    check("Settings Gold: Show gold in tooltips", g().tips == false)
    tick(pane.cbTips)
    check("Settings Gold: and on again", g().tips == true and Gold.tooltip({ AddLine = function() end, AddDoubleLine = function() end }) > 0)
    tick(pane.cbPill)
    check("Settings Gold: Gold pill on screen", g().pill.on == true and Gold.pill.shown == true and pane.cbPill.checked == true)
    click(pane.pick1)
    local m = Gold._menu
    check("Settings Gold: Pill shows opens the six values", m.shown == true and m.count == 7 and m.btns[1].text.text == "Balance" and m.btns[1].ebSelected == true and m.btns[6].text.text == "Farm timer")
    -- an open list does not outlive what it hangs under
    pane:Hide()
    check("Settings Gold: hiding the pane closes an open list", m.shown == false and m.owner == nil)
    pane:Show(); M.settle()
    click(pane.pick1)
    click(pane.moreBtn)
    check("Settings Gold: More closes an open list", m.shown == false)
    click(pane.backBtn)
    click(pane.pick2)
    tick(pane.cbTips); tick(pane.cbTips)
    check("Settings Gold: so does any other control of the page", m.shown == false)
    click(pane.pick1)
    M.inCombat = true; M.fire("PLAYER_REGEN_DISABLED")
    check("Settings Gold: and the start of a fight", m.shown == false)
    M.inCombat = false; M.fire("PLAYER_REGEN_ENABLED"); M.settle()
    click(pane.pick1)
    check("Settings Gold: the list opens again", m.shown == true and m.count == 7)
    click(m.btns[4])
    check("Settings Gold: picking one sets the pill and the button", g().pill.metrics[1] == "today" and pane.pick1.text.text == "Today net" and m.shown == false and Gold.pill.text.text:find("^[%+%-]") ~= nil, pane.pick1.text.text)
    click(pane.pick2)
    check("Settings Gold: Second value offers None and the six", m.count == 8 and m.btns[1].text.text == "None" and m.btns[1].ebSelected == true)
    click(m.btns[2])
    check("Settings Gold: the second value", g().pill.metrics[2] == "balance" and pane.pick2.text.text == "Balance")
    click(pane.pick2); click(m.btns[1])
    check("Settings Gold: None takes it away", g().pill.metrics[2] == nil and pane.pick2.text.text == "None")
    click(pane.rateBtns[3])
    check("Settings Gold: Per hour shows Net, with its definition under the buttons", g().rateMode == "net" and pane.rateBtns[3].ebSelected == true and pane.rateBtns[1].ebSelected == nil and pane.rateNote.text == Gold.RATE_NOTE.net and Gold.rate().mode == "net")
    click(pane.rateBtns[2])
    check("Settings Gold: Earned", g().rateMode == "earned" and pane.rateNote.text:find("^Earned: ") ~= nil)
    click(pane.rateBtns[1])
    click(pane.pickFilter); click(m.btns[2])
    check("Settings Gold: Show gold from", g().filter == "realm" and pane.pickFilter.text.text == "This realm")
    click(pane.pickFilter); click(m.btns[1])
    tick(pane.cbIcons); tick(pane.cbCompact)
    check("Settings Gold: Coin icons and Compact numbers", g().icons == true and g().compact == true and Gold.fmt(12345670000) == "1.2M" .. UI.COIN_ICON.g and Gold.fmt(1234560000) == "123.4k" .. UI.COIN_ICON.g)
    tick(pane.cbIcons); tick(pane.cbCompact)
    check("Settings Gold: and off", g().icons == false and g().compact == false and Gold.fmt(12345670000) == "1,234,567g")
    -- hidden characters
    local guid = next(ns.DB.characters)
    g().hidden = { [guid] = true }
    pane.refresh()
    check("Settings Gold: a hidden character is listed by name", pane.hiddenRows[1].name.text:find(ns.DB.characters[guid].name, 1, true) == 1 and pane.hiddenRows[1].btn.guid == guid)
    click(pane.hiddenRows[1].btn)
    check("Settings Gold: Show again takes it off the list and out of the settings", g().hidden == nil and pane.hiddenRows[1].btn.shown == false and P.visible(pane.hiddenNone))
    -- behind More
    click(pane.moreBtn)
    tick(pane.cbLock)
    check("Settings Gold: Lock the pill", g().pill.locked == true)
    tick(pane.cbLock)
    pane.slScale:SetValue(1.5)
    check("Settings Gold: Pill text size", g().pill.scale == 1.5 and pane.slScale.label.text == "Pill text size: 150%", pane.slScale.label.text)
    pane.slAlpha:SetValue(0.6)
    check("Settings Gold: Pill opacity", g().pill.alpha == 0.6 and pane.slAlpha.label.text == "Pill opacity: 60%")
    pane.slRows:SetValue(12)
    check("Settings Gold: Characters in tooltips", g().tip.limit == 12 and pane.slRows.label.text == "Characters in tooltips: 12")
    tick(pane.cbWeek); tick(pane.cbMonth)
    check("Settings Gold: week and month in tooltips", g().tip.week == true and g().tip.month == true)
    tick(pane.cbWeek); tick(pane.cbMonth)
    check("Settings Gold: and off again", g().tip.week == false and g().tip.month == false)
    check("Settings Gold: no control for the flag's tooltip (it waits for the desktop's replay), no key written for it", pane.cbFlag == nil and g().tip.flag == nil and Gold.FLAG_TIP == false)
    M.inCombat = true
    pane.slScale:SetValue(0.5)
    check("Settings Gold: in combat the pill's size is not changed", g().pill.scale == 1.5)
    M.inCombat = false
    pane.refresh()
    g().pill.corner, g().pill.x, g().pill.y = "BOTTOMRIGHT", -40, 300
    Gold.pillPlace()
    click(pane.resetPos)
    check("Settings Gold: Reset pill position puts it back at its default place", g().pill.corner == "TOPLEFT" and inside(pillBox()) and clearOfFlag(pillBox()), tostring(g().pill.corner))
    local me = ns.DB.characters[UnitGUID("player")]
    check("Settings Gold: the fixture has history to reset", me.goldDays ~= nil and me.goldRate ~= nil)
    click(pane.resetRate)
    check("Settings Gold: Reset per hour", me.goldRate == nil and me.goldDays ~= nil)
    local ledger = {}
    for k, v in pairs(me.gold) do ledger[k] = v end
    click(pane.resetHist)
    check("Settings Gold: Reset gold history asks first, naming what is deleted", me.goldDays ~= nil and pane.resetHist.armed == true and pane.resetHist.text.text == "Confirm: delete this character's day history"
      and pane.resetNote.text:find("day rows", 1, true) ~= nil and pane.resetNote.text:find("The balance and the lifetime totals stay", 1, true) ~= nil)
    M.runTimers()
    check("Settings Gold: after 3 s without a second click it is as it was", pane.resetHist.armed == false and pane.resetHist.text.text == "Reset gold history" and me.goldDays ~= nil)
    click(pane.resetHist); click(pane.resetHist)
    local same = true
    for k, v in pairs(ledger) do if me.gold[k] ~= v then same = false end end
    check("Settings Gold: the second click deletes the day history and nothing else", me.goldDays == nil and me.goldRate == nil and me.goldTimer == nil and type(me.goldSince) == "number" and same and pane.resetHist.armed == false)
    M.runTimers()
    click(pane.backBtn)
    tick(pane.cbPill)
    check("Settings Gold: the pill off again", g().pill.on == false and Gold.pill.shown == false)
    if Gold._menu then Gold._menu:Hide(); Gold._menu.owner = nil end
  end

  M.epoch, M.now = saved.epoch, saved.now
  Gold._tickAt = saved.tickAt
  Gold._tipOwner, Gold._tipRedo, Gold._pillDirty, Gold._openAfter = nil, nil, nil, nil
  ns.Recorder.current = savedCurrent
  print = realPrint
end
