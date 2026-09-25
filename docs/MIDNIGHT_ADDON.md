# Midnight / "WoW Forever" client - addon gotchas

Hard-won lessons from building the Everbuff addon against the Midnight beta client
(`_classic_beta_`, reports `WOW_PROJECT_MAINLINE`). Read this before touching the TOC,
SavedVariables, or anything that reads Secret Values.

> **UPDATE (2026-09-19): Section 1 turned out to be a CONFIRMED BETA CLIENT BUG, not our addon.**
> The WoW Forever beta does not persist ANY addon's SavedVariables (verified against DialogueUI too;
> Blizzard forum: https://eu.forums.blizzard.com/en/wow/t/wow-forever-game-not-save-any-addons-settings/629470).
> Everything in section 1 below (fresh folders, X-Expansion, pipe stripping, AddOns.txt) was chasing a
> client bug and did NOT fix it - the "it worked" moments were `/reload` keeping the in-memory copy warm;
> a true cold restart never persisted. Do not re-chase on the beta. Test SavedVariables on the live/retail
> client instead. The combat-log FILE (engine-written) is unaffected and is the durable data channel.

---

## 1. SavedVariables write but never load  (turned out to be the beta bug above)

**Symptom.** Everything the addon saves resets on every `/reload` and relaunch - fights,
flag position, settings - even though the on-disk `SavedVariables/<Addon>.lua` is present,
valid, and full. The addon runs fine and *writes* the file; it just never gets it back.
Often paired with the in-game addon list jamming ("can't enable/disable addons").

**The three real causes (all had to be right at once):**

1. **Editing installed addon files while the game is RUNNING corrupts the addon's SavedVariables
   + addon-list state on this beta client.** This was the big one. It worked *every* time the
   addon was installed while the game was fully closed and left alone; it broke *every* time a
   file was hot-patched mid-session (a TOC tweak, or just re-copying `Emitter.lua`/`Fights.lua`)
   and then `/reload`ed. RULE: **only ever change addon files with WoW fully closed, then relaunch.**
   No mid-session reinstalls, no hot `/reload` of edits.

2. **A stale `AddOns.txt` jams addon loading.** Creating/deleting addon folders leaves ghost
   entries in `WTF/Account/<acc>/<realm>/<char>/AddOns.txt` (e.g. `Everbuff: enabled` for a
   folder you deleted, and the new folder missing entirely). That ghost corrupts the addon
   manager (can't toggle addons) and breaks loading. After any folder add/remove, rewrite
   `AddOns.txt` to list exactly the installed folders with sane states - no ghosts.

3. **Missing `## X-Expansion: MAINLINE` in the TOC.** The one reliably-persisting addon on this
   client (**DialogueUI**, which is *also* hand-copied - so manual-vs-manager is a non-issue)
   declares `## X-Expansion: MAINLINE` + `## Interface: 120100, 120105`. Mirror that exactly.

**Diagnosing (kept for reference):**
- Print `type(EverbuffDB)` at the top of `ADDON_LOADED`; `nil` = WoW did not load the SV.
- A throwaway canary SavedVariable whose counter should climb each load; if it stays at 1, SV
  isn't loading. (Note: it shares the one file with your real SV, so it can't isolate *content*.)
- Validate the file: `cat "<file>" | luajit -e 'assert(loadstring(io.read("*a")))()'`. Pipe via
  **stdin** - do NOT pass a POSIX path as an arg to Windows luajit (`loadfile` can't open `/c/...`
  and returns misleading nils).

**The fix that stuck:** with the game fully closed, install one clean folder
(`Interface\AddOns\EverbuffJournal`) with a frozen TOC (`## X-Expansion: MAINLINE`,
`## Interface: 120100, 120105`), repoint the hardcoded media paths, delete old folders + their
orphaned SV files, and rewrite `AddOns.txt` to match. Launch once and don't touch the files
while in-game. Confirmed: fights/loot/flag survive `/reload` and full relaunch.

> Red herrings that cost time: pipe characters in stored strings, the `16001` value from
> `select(4, GetBuildInfo())`, and "fresh folder name" alone (a fresh folder only worked because
> it was installed while closed - the name wasn't the point).

---

## 2. SavedVariables mechanics (things that are NOT negotiable)

- **All of an addon's SavedVariables live in ONE file** (`SavedVariables/<Folder>.lua`), loaded
  as a **single Lua chunk**. You cannot split them per tab/module into separate files. If the
  chunk fails, every declared variable comes back `nil` together.
- **SavedVariables only flush to disk on `/reload` or logout.** There is no API to force a
  mid-session flush. A disconnect/crash loses everything written since the last flush.
- **TOC changes (files, `## Interface`, `## SavedVariables`) only take effect on a full client
  restart** - `/reload` does NOT re-read TOCs. Many "still broken after I fixed it" moments were
  just `/reload` instead of a real relaunch.

---

## 3. Committing a reload from a tainted addon

Reading Secret Values (auras, stats) **taints** the addon, and a tainted addon **cannot call
`ReloadUI` / `C_UI.Reload` from its own Lua** - the call is blocked (silent failure + error
spam from a background timer). A reload must come through the **protected path**:

- Use a **SecureActionButton** with `type="macro"`, `macrotext="/reload"`. The user's click is
  a hardware event, so the macro reloads even though our code is tainted. (This is why our
  "save now" modal uses a secure button, Deathlog-style, not a Lua `ReloadUI()`.)
- `ReloadUI` may not exist on this client; prefer `C_UI.Reload()` with a `ReloadUI` fallback for
  non-secure paths.

---

## 4. Secret Values break arithmetic - and can corrupt SavedVariables

On Midnight, combat stats (`UnitAttackPower`, `UnitStat`, `UnitHealthMax`, `UnitDamage`,
`UnitArmor`, `UnitResistance`, crit/haste getters, …) return **secret numbers**. You cannot do
arithmetic, comparison, `string.format`, or **store them in SavedVariables** without
tainting/erroring. Two consequences we hit:

- Guard every such read with a `plain(v)` helper that proves it's an ordinary number
  (`pcall(function() return v + 0 end)`), dropping anything secret. Wrapping only the API call
  in `pcall` is not enough - the crash is on the later math.
- **Sanitize before storing.** A single secret value, `NaN`, `inf`, or function in the saved
  table can make the whole file unparseable → WoW discards ALL of it on next load. `Fights.lua`
  deep-sanitizes each record (finite plain numbers, strings, booleans, clean tables only).

The combat-log FILE (`WoWCombatLog.txt`, advanced logging on) remains the source of truth for
damage/DPS; the addon SavedVariables only carry the *context* the file lacks.

---

## Quick diagnosis checklist for "my SavedVariables won't persist"

1. Is it flushing? Check the on-disk file's mtime after a `/reload`.
2. Is the file valid? `cat file | luajit -e 'assert(loadstring(io.read("*a")))()'`.
3. Is it loading? `type(EverbuffDB)` at `ADDON_LOADED` - `nil` means no.
4. Content vs mechanism? Add a canary SavedVariable; if it also never persists, it's the
   mechanism (identity), so rebuild under a fresh folder name.
5. Did you actually **relaunch** (not `/reload`) after a TOC change?
