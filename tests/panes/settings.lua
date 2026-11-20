-- Pane tests: Settings (docs/UX_OVERHAUL.md 4.12). Three sub-tabs, General, Gold display (tests/panes/goldglance.lua
-- drives its controls) and Data and sync. At 900x580, 1250x760 and 1600x1000: one settings column min(CW, 600) wide
-- at BOX_L (two columns of 500, S5 apart, at WIDE), every row's label at x 12 of the column and its control
-- right-aligned to the column's text edge, nothing past the pane, no text over another. Then what the controls
-- write, the two-step clears, the collapsed Advanced, the sync box and the secure reload button in combat.
return function(P)
  local check, M, ns = P.check, P.M, P.ns
  local UI = ns.UI
  local SET = ns.SettingsView
  local S, G = UI.S, UI.G
  local function near(a, b, tol) return a and b and math.abs(a - b) <= (tol or 0.51) end
  local function click(b) b.scripts.OnClick(b, "LeftButton"); M.settle() end
  local function settings(w, h, sub)
    local c = P.open("Settings", nil, w, h)
    if c and c.subtabs then c.subtabs.select(sub); M.settle() end
    return c, c and c.subtabs and c.subtabs.panes[sub]
  end
  check("Settings: the sub-tabs are General, Gold display, Data and sync", (function()
    local c = P.open("Settings", nil, 900, 580)
    local l = {}
    for _, b in ipairs(c.subtabs.tabs) do l[#l + 1] = b.text.text end
    return table.concat(l, ",") == "General,Gold display,Data and sync"
  end)())
  check("Settings: the aliases open the new sub-tabs", (function()
    UI.Open("Settings", "capture"); M.settle()
    local c = P.open("Settings", nil, 900, 580)
    local okCap = c.subtabs.active == "data"
    UI.Open("Settings", "gold"); M.settle()
    return okCap and c.subtabs.active == "golddisplay"
  end)())

  -- every setting row of a page: its label at x 12 of its column, its control's right edge at the column's text
  -- edge, inside the pane; no two texts over each other
  local function audit(tag, pane, pg, sections)
    local pb = P.box(pane)
    local cb = P.box(pg.col)
    local bad = {}
    -- (A2: the columns span the main column; two halves S5 apart at WIDE, Data and sync too, B23)
    local wide = G.isWide(G.winW())
    local colW = UI.settingsColumns()[1].w
    local cols = {}
    for _, sec in ipairs(sections) do
      local hb = P.box(sec.head)
      cols[hb.l] = true
      local want = colW
      if not near(hb.w, want) then bad[#bad + 1] = ("section %s is %d wide, want %d"):format(tostring(sec.head.label.text), hb.w, want) end
      for _, it in ipairs(sec.items) do
        if P.visible(it) then
          local rb = P.box(it)
          if not near(rb.l, hb.l) then bad[#bad + 1] = "a row off its section's column" end
          if it.label and it.label.text ~= "" and not near(P.box(it.label).l, rb.l + S.S3) then bad[#bad + 1] = "label x " .. tostring(it.label.text) end
          if it.control and P.visible(it.control) then
            local ctl = P.box(it.control)
            if not near(ctl.l + ctl.w, rb.l + rb.w - S.S3, 1) then bad[#bad + 1] = ("control of %s ends at %d, want %d"):format(tostring(it.label.text), ctl.l + ctl.w - rb.l, rb.w - S.S3) end
            if it.stacked then
              if P.box(it.control).t < P.box(it.label).t + UI.LINE_H.ROW_TITLE then bad[#bad + 1] = "a stacked control over its label: " .. tostring(it.label.text) end
            elseif it.label and it.label.text ~= "" then
              local lb = P.box(it.label)
              if lb.l + math.min(lb.w, P.G.naturalWidth(it.label)) > ctl.l + 0.5 then bad[#bad + 1] = ("label runs into its control: %s (natural %d, control %d at %d)"):format(tostring(it.label.text), P.G.naturalWidth(it.label), ctl.w, ctl.l - rb.l) end
            end
          end
          if rb.l + rb.w > pb.l + pb.w + 0.5 then bad[#bad + 1] = "a row past the pane" end
        end
      end
    end
    local n = 0; for _ in pairs(cols) do n = n + 1 end
    check(tag .. ": " .. (wide and "two columns" or "one column"), n == (wide and 2 or 1) or (wide and n == 1 and #sections == 1), n)
    check(tag .. ": the column starts at BOX_L", near(cb.l - P.box(P.T.frame or pane).l, 0) or near(P.box(sections[1].head).l, pb.l), cb.l)
    -- texts: none over another, none past the pane
    local texts = {}
    for _, f in ipairs(P.descendants(pg.col)) do
      if f._isFS and P.visible(f) and (f.text or "") ~= "" then
        local b = P.box(f)
        if b and b.w > 0 then
          local h = select(2, P.G.textSize(f, b.w))
          if b.l + math.min(b.w, P.G.naturalWidth(f)) > pb.l + pb.w + 0.5 then bad[#bad + 1] = "past the pane: " .. tostring(f.text):sub(1, 24) end
          if f._wrap == false and f:IsTruncated() and not (f.parentFrame and f.parentFrame._kind == "Button") then bad[#bad + 1] = "cut: " .. tostring(f.text):sub(1, 24) .. (" (w %s natural %d, row %s, control %s)"):format(tostring(f._w), P.G.naturalWidth(f), tostring(f.parentFrame._w), tostring(f.parentFrame.control and f.parentFrame.control._w)) end
          texts[#texts + 1] = { f = f, b = b, h = h }
        end
      end
    end
    for i = 1, #texts do
      for j = i + 1, #texts do
        local a, b = texts[i], texts[j]
        if a.f.parentFrame ~= b.f.parentFrame or a.f.parentFrame._kind ~= "Button" then
          if a.b.l < b.b.l + b.b.w and b.b.l < a.b.l + a.b.w and a.b.t < b.b.t + b.h - 0.5 and b.b.t < a.b.t + a.h - 0.5 then
            bad[#bad + 1] = ("'%s' over '%s'"):format(tostring(a.f.text):sub(1, 18), tostring(b.f.text):sub(1, 18))
          end
        end
      end
    end
    check(tag .. ": every row on its column, controls at the text edge, nothing over or past anything", #bad == 0, table.concat(bad, "; "))
  end

  for _, size in ipairs({ { 900, 580 }, { 1250, 760 }, { 1600, 1000 } }) do
    local tag = ("Settings %dx%d"):format(size[1], size[2])
    settings(size[1], size[2], "general")
    local g = SET.general
    check(tag .. ": General opened", g ~= nil and P.visible(g.pane))
    if g then audit(tag .. " General", g.pane, g.pg, g.sections) end
    settings(size[1], size[2], "data")
    local d = SET.data
    check(tag .. ": Data and sync opened", d ~= nil and P.visible(d.pane))
    if d then
      ns.DB.settings.advancedOpen = true; SET.refreshData(); M.settle()
      audit(tag .. " Data and sync (Advanced open)", d.pane, d.pg, d.sections)
      ns.DB.settings.advancedOpen = nil; SET.refreshData(); M.settle()
      audit(tag .. " Data and sync", d.pane, d.pg, d.sections)
      local pb, ab, rb = P.box(d.ackBox), P.box(d.ackBtn), P.box(d.pasteRow)
      check(tag .. ": the paste box is 24 high and stretches: Apply S2 after it ends on the column's text edge", d.ackBox._h == 24 and pb and ab and rb
        and math.abs(pb.l + pb.w + UI.S.S2 - ab.l) < 0.5 and math.abs(ab.l + ab.w - (rb.l + rb.w - UI.S.S3)) < 0.5, pb and ab and rb and ("%s %s %s"):format(pb.l + pb.w, ab.l, rb.l + rb.w))
      check(tag .. ": the footer names the version and /eb help", d.footerText.text == ("everbuff %s \194\183 type /eb help for every command"):format(tostring(ns.VERSION)) and P.visible(d.footer))
    end
  end
  UI.SetWindowSize(900, 580)

  -- ── General: what the controls write ──
  do
    settings(900, 580, "general")
    local g = SET.general
    local st = ns.DB.settings
    local keep = { corner = st.emitCorner, flag = st.flagScale, scale = st.winScale, mute = st.flagMute, toast = st.lootToast, pos = st.winPos }
    check("General: Position is a four-way segmented control (4.12)", #g.cornerSeg.segs == 4 and g.cornerSeg.segs[1].text.text == "Top left" and g.cornerSeg.segs[4].text.text == "Bottom right")
    click(g.cornerSeg.segs[2])
    check("General: Top right moves the flag", st.emitCorner == "TOPRIGHT" and g.cornerSeg.value == "TOPRIGHT", tostring(st.emitCorner))
    click(g.cornerSeg.segs[1])
    g.flagSlider:SetValue(1.25)
    check("General: the flag size slider sets the flag's size", math.abs((st.flagScale or 0) - 1.25) < 0.001 and g.flagSlider.valueText.text == "125%", tostring(st.flagScale))
    g.flagSlider:SetValue(3)
    check("General: the flag size stops at its maximum", math.abs((st.flagScale or 0) - ns.Emitter.FLAG_RANGE[2]) < 0.001)
    g.flagSlider:SetValue(1)
    g.scaleSlider:SetValue(1.1)
    check("General: Window scale writes the scale", math.abs((st.winScale or 0) - 1.1) < 0.001 and g.scaleSlider.valueText.text == "110%")
    check("General: Window scale runs from 90% to 130%", g.scaleSlider.GetValue and (function() g.scaleSlider:SetValue(0.1); local lo = g.scaleSlider:GetValue(); g.scaleSlider:SetValue(9); local hi = g.scaleSlider:GetValue(); return math.abs(lo - 0.9) < 0.001 and math.abs(hi - 1.3) < 0.001 end)())
    g.scaleSlider:SetValue(1)
    st.winPos = { point = "TOPLEFT", x = 40, y = -40 }
    UI.SetWindowSize(1200, 800)
    click(g.resetBtn); M.settle()
    check("General: Reset puts the window back at its smallest size, centred", st.winPos == nil and G.winW() == UI.WIN_MIN_W)
    -- notifications
    check("General: Preview sits in the section's right side", g.preview:GetParent() == g.sections[3].head.right)
    local before = #ns.DB.story.events
    click(g.preview)
    check("General: Preview shows a notification without an error", #M.errors == 0)
    click(g.lootCb)
    check("General: unticking Loot mutes loot notifications", st.flagMute and st.flagMute.loot == true and g.lootCb.checked == false)
    click(g.lootCb)
    check("General: ticking it again", not (st.flagMute and st.flagMute.loot) and g.lootCb.checked == true)
    click(g.lootFromBtn)
    local m = g.lootFromBtn.menu
    check("General: Show loot from offers the Items quality labels", m and m.shown ~= false)
    g.lootFromOpts.onPick("epic"); M.settle()
    check("General: picking Purple and better sets the toast threshold", st.lootToast == "epic" and g.lootFromBtn.text.text == "Purple and better" and not g.lootFromBtn.ebActive)
    st.lootToast = "off"; SET.refreshGeneral()
    check("General: a saved Off reads as Loot unticked", g.lootCb.checked == false)
    click(g.lootCb)
    check("General: ticking Loot after Off brings back Blue and better", st.lootToast == "rare" and g.lootCb.checked == true)
    for _, r in ipairs(g.groups) do
      click(r.cb)
      check("General: unticking " .. r.key .. " mutes it", st.flagMute and st.flagMute[r.key] == true)
      click(r.cb)
    end
    -- the welcome guide
    st.welcomeDone = true
    click(g.welcomeBtn)
    check("General: Show the welcome guide again opens Home > Now with the guide", st.welcomeDone == false)
    st.welcomeDone = true
    st.emitCorner, st.flagScale, st.winScale, st.flagMute, st.lootToast, st.winPos = keep.corner, keep.flag, keep.scale, keep.mute, keep.toast, keep.pos
    if ns.Emitter.setFlagScale then ns.Emitter.setFlagScale(keep.flag or 1) end
    UI.SetWindowSize(900, 580)
  end

  -- ── Data and sync ──
  do
    settings(900, 580, "data")
    local d = SET.data
    local keepAck = ns.DB.combat.lastAck
    ns.DB.combat.lastAck = nil; SET.refreshData()
    check("Data: before any sync it says so", d.syncStatus.text.text:find("^Not seen yet: install the desktop app from everbuff.gg") ~= nil, d.syncStatus.text.text)
    ns.DB.combat.lastAck = { at = (GetServerTime and GetServerTime() or time()) - 120, fights = 2, source = "file" }
    SET.refreshData()
    local sync = ns.SyncState()
    check("Data: the status names the last pickup and the fights waiting, from the one Sync function", d.syncStatus.text.text == ("Last picked up by the desktop app 2m ago \194\183 %s not saved yet"):format(UI.plural(sync.waiting, "pull")), d.syncStatus.text.text)
    check("Data: the error shows only after a paste attempt", not P.visible(d.ackError))
    d.ackBox:SetText("not a code"); click(d.ackBtn)
    check("Data: a bad code shows the error and changes nothing", P.visible(d.ackError) and d.ackError.text.text:find("EB-ACK-", 1, true) ~= nil and #M.errors == 0)
    ns.DB.combat.lastAck = keepAck
    -- recording health
    local keepCombat = ns.Logging._combat
    ns.Logging._combat = false; SET.refreshData()
    check("Data: Combat log off shows Turn on", d.combat.label.text:find("Combat log: off", 1, true) ~= nil and d.combat.btn.shown ~= false)
    click(d.combat.btn)
    check("Data: Turn on turns combat logging on", ns.Logging._combat == true and d.combat.label.text:find("Combat log: on", 1, true) ~= nil and d.combat.btn.shown == false)
    ns.Logging._combat = keepCombat; SET.refreshData()
    click(d.remindCb)
    check("Data: the reminder checkbox writes autoSave", ns.DB.settings.autoSave == false)
    click(d.remindCb)
    check("Data: and back on", ns.DB.settings.autoSave == true)
    -- stored data: two steps
    local keepF, keepL, keepE = ns.DB.combat.fights, ns.DB.loot.log, ns.DB.story.events
    ns.DB.combat.fights = { { uid = "x1" }, { uid = "x2" } }
    ns.DB.loot.log = { { item = "a" } }
    ns.DB.story.events = { { kind = "ZONE" }, { kind = "ZONE" }, { kind = "ZONE" } }
    SET.refreshData()
    check("Data: the stored rows read Pulls · 2 pulls stored, Loot · 1 pickup, Events · 3",
      d.stored.fights.label.text == "Pulls \194\183 2 pulls stored" and d.stored.loot.label.text == "Loot \194\183 1 pickup" and d.stored.events.label.text == "Events \194\183 3",
      d.stored.fights.label.text .. " | " .. d.stored.loot.label.text)
    check("Data: each clear says it cannot be undone", d.stored.fights.desc.text == "Cannot be undone.")
    local btn = d.stored.fights.btn
    click(btn)
    check("Data: the first click only asks", #ns.DB.combat.fights == 2 and btn.armed == true and btn.text.text == "Click again to clear 2 pulls", btn.text.text)
    M.runTimers(); M.settle()
    check("Data: after 4 s it is as it was", btn.armed == false and btn.text.text == "Clear")
    click(btn); click(btn)
    check("Data: the second click clears the pulls and nothing else", #ns.DB.combat.fights == 0 and ns.DB.combat.fightSeq == 0 and #ns.DB.loot.log == 1 and #ns.DB.story.events == 3)
    ns.DB.combat.fights, ns.DB.loot.log, ns.DB.story.events = keepF, keepL, keepE
    -- advanced
    ns.DB.settings.advancedOpen = nil; SET.refreshData()
    check("Data: Advanced is collapsed by default", not P.visible(d.sample) and d.advHead.label.text == "ADVANCED \226\128\186", tostring(d.advHead.label.text))
    click(d.advHit)
    check("Data: a click on its header opens it", ns.DB.settings.advancedOpen == true and P.visible(d.sample) and P.visible(d.errors))
    click(d.sampleSeg.segs[2])
    check("Data: Replay detail Normal writes the stat sample", ns.DB.settings.statSample == 3)
    click(d.sampleSeg.segs[1])
    check("Data: the diagnostics are status lines", d.auras.label.text:find("Aura names in combat", 1, true) ~= nil and d.video.label.text:find("the game cannot see it", 1, true) ~= nil)
    click(d.advHit)
    ns.DB.settings.advancedOpen = nil; ns.DB.settings.statSample = nil
  end

  -- ── the secure reload button: never moved in combat, the layout held until combat ends ──
  do
    settings(900, 580, "data")
    local d = SET.data
    local save = _G.EverbuffSyncReloadBtn
    check("Data: the secure reload button is there, on its row", save ~= nil and save:GetParent() == d.save)
    local touched, rowMoved = 0, 0
    local ca, sp = save.ClearAllPoints, save.SetPoint
    rawset(save, "ClearAllPoints", function(...) touched = touched + 1; return ca(...) end)
    rawset(save, "SetPoint", function(...) touched = touched + 1; return sp(...) end)
    local rsp = d.save.SetPoint
    rawset(d.save, "SetPoint", function(...) rowMoved = rowMoved + 1; return rsp(...) end)
    local was = M.inCombat
    M.inCombat = true
    SET.refreshData()
    local h = d.pane.scripts and d.pane.scripts.OnSizeChanged
    if h then h(d.pane, 700, 500) end
    M.runTimers(); M.settle()
    local inCombat = rowMoved
    M.inCombat = was
    M.fire("PLAYER_REGEN_ENABLED"); M.settle()
    rawset(save, "ClearAllPoints", nil); rawset(save, "SetPoint", nil); rawset(d.save, "SetPoint", nil)
    check("Data: in combat, refresh and a resize never move the protected reload button", touched == 0, touched .. " calls")
    check("Data: in combat, the row it hangs from is not moved either", inCombat == 0, inCombat .. " calls")
    check("Data: the held layout runs when combat ends", rowMoved > inCombat, rowMoved .. " calls")
  end
end
