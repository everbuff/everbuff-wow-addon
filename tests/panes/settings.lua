-- Pane tests: Settings. General: every control of the right column (the notification groups and the loot toast
-- threshold buttons) lies inside the General pane at the minimum window and at the largest. Capture: the values run
-- from x 172 to the pane's right inset (no fixed width), wrap when they must, and each row starts below the measured
-- height of the row above, so a wrapped value never runs into the next label.
return function(P)
  local check, M, ns = P.check, P.M, P.ns
  local UI = ns.UI
  local function settings(w, h, sub)
    local c = P.open("Settings", nil, w, h)
    if c and c.subtabs then c.subtabs.select(sub); M.settle() end
    return c, c and c.subtabs and c.subtabs.panes[sub]
  end
  for _, size in ipairs({ { 900, 580 }, { 1250, 760 }, { 1600, 1000 } }) do
    local tag = ("Settings %dx%d"):format(size[1], size[2])
    local _, general = settings(size[1], size[2], "general")
    check(tag .. ": the General pane opened", general ~= nil)
    if general then
      local gb = P.box(general)
      local out = {}
      for _, f in ipairs(P.descendants(general)) do
        if f.parentFrame == general and P.visible(f) and (f._kind == "Button" or f._kind == "CheckButton" or (f._isFS and (f.text or "") ~= "")) then
          local b = P.box(f)
          if b and b.w > 0 and b.l + b.w > gb.l + gb.w + 0.5 then out[#out + 1] = ("%s ends at %d, pane %d"):format(tostring((f._isFS and f.text) or (type(f.text) == "table" and f.text.text) or f._kind):sub(1, 20), b.l + b.w - gb.l, gb.w) end
        end
      end
      check(tag .. ": every General control lies inside its pane", #out == 0, table.concat(out, "; "))
      local btns = general.lootToastButtons or {}
      check(tag .. ": the four loot toast buttons are there", #btns == 4)
      local fit = true
      for _, b in ipairs(btns) do
        if math.abs(b._w - math.max(44, math.ceil(P.G.naturalWidth(b.text)) + 2 * UI.SP.M)) > 0.5 then fit = false end
      end
      check(tag .. ": each threshold button is as wide as its label plus M each side", fit)
    end
    local _, capture = settings(size[1], size[2], "capture")
    check(tag .. ": the Capture pane opened", capture ~= nil and capture.rows ~= nil)
    if capture and capture.rows then
      -- the longest value the pane shows: hidden aura names with counts
      ns.Fights = ns.Fights or {}
      local h0, b0 = ns.Fights.hiddenAuras, ns.Fights.blindScans
      ns.Fights.hiddenAuras, ns.Fights.blindScans = 12, 3
      ns.RefreshCapturePane(); M.settle()
      local cb = P.box(capture)
      local bad = {}
      local texts = {}
      for _, f in ipairs(P.descendants(capture)) do
        if f._isFS and f.parentFrame == capture and P.visible(f) and (f.text or "") ~= "" then texts[#texts + 1] = f end
      end
      for _, v in pairs(capture.rows) do
        if v._w ~= nil then bad[#bad + 1] = "a value has a fixed width" end
        local b = P.box(v)
        if b.l + b.w > cb.l + cb.w - 14 + 0.5 then bad[#bad + 1] = ("value ends at %d of %d"):format(b.l + b.w - cb.l, cb.w) end
      end
      local dc = capture.disconnectNote
      if dc then
        local b = P.box(dc)
        if dc._w ~= nil or b.l + b.w > cb.l + cb.w + 0.5 then bad[#bad + 1] = "the disconnect note runs past the pane" end
      end
      -- no two texts overlap (a wrapped value's last line against the next row's label)
      for i = 1, #texts do
        for j = i + 1, #texts do
          local a, b = P.box(texts[i]), P.box(texts[j])
          local ha = select(2, P.G.textSize(texts[i], a.w))
          local hb = select(2, P.G.textSize(texts[j], b.w))
          if a.l < b.l + b.w and b.l < a.l + a.w and a.t < b.t + hb - 0.5 and b.t < a.t + ha - 0.5 then
            bad[#bad + 1] = ("'%s' over '%s'"):format(tostring(texts[i].text):sub(1, 18), tostring(texts[j].text):sub(1, 18))
          end
        end
      end
      check(tag .. ": Capture values span to the pane's inset and wrapped rows push the next down", #bad == 0, table.concat(bad, "; "))
      -- the secure reload button: under the note, clear of the Health heading, and never re-anchored by a relayout
      local save = _G.EverbuffSyncReloadBtn
      check(tag .. ": the reload button is there", save ~= nil)
      if save and dc then
        local sb, db = P.box(save), P.box(dc)
        local dh = select(2, P.G.textSize(dc, db.w))
        check(tag .. ": the reload button starts L below the note's text", sb.t >= db.t + dh + UI.SP.L - 0.5 and sb.l == db.l, ("%s vs %s"):format(sb.t, db.t + dh))
        local health
        for _, f in ipairs(texts) do if f.text == "Health" then health = P.box(f) end end
        check(tag .. ": the Health heading starts below the reload button", health ~= nil and health.t >= sb.t + 26 - 0.5, health and ("%s vs %s"):format(health.t, sb.t + 26))
        local touched, dcMoved = 0, 0
        local ca, sp = save.ClearAllPoints, save.SetPoint
        rawset(save, "ClearAllPoints", function(...) touched = touched + 1; return ca(...) end)
        rawset(save, "SetPoint", function(...) touched = touched + 1; return sp(...) end)
        local dsp = dc.SetPoint
        rawset(dc, "SetPoint", function(...) dcMoved = dcMoved + 1; return dsp(...) end)
        local was = M.inCombat
        M.inCombat = true
        ns.RefreshCapturePane(); capture.relayout()
        local h = capture.scripts and capture.scripts.OnSizeChanged
        if h then h(capture, 700, 500) end
        M.runTimers(); M.settle()
        local inCombatMoves = dcMoved
        M.inCombat = was
        M.fire("PLAYER_REGEN_ENABLED"); M.settle()
        rawset(save, "ClearAllPoints", nil); rawset(save, "SetPoint", nil); rawset(dc, "SetPoint", nil)
        check(tag .. ": in combat, refresh and a resize never move the protected reload button", touched == 0, touched .. " calls")
        check(tag .. ": in combat, the note the button hangs from is not moved either", inCombatMoves == 0, inCombatMoves .. " calls")
        check(tag .. ": the held relayout runs when combat ends", dcMoved > inCombatMoves, dcMoved .. " calls")
      end
      ns.Fights.hiddenAuras, ns.Fights.blindScans = h0, b0
    end
  end
  UI.SetWindowSize(900, 580)
end
