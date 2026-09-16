# Everbuff addon — dev/test loop

Developing a WoW addon blind is hard: you can't see the UI, and group content (readiness, loot rolls,
soft-reserves) needs other players. This is a 3-tier loop to verify the addon without all that.

## Tier 1 — mock harness (fast, no game)
Runs the real addon `.lua` under **LuaJIT** (Lua 5.1, same as WoW) with a mock of the WoW API
(`wow_mock.lua`). Catches runtime errors, drives logic (recording, SR parsing, rolls, readiness,
roster), and **dumps each tab's rendered text** so the UI structure is inspectable.

```sh
bash addon/test/run.sh          # or: luajit addon/test/run.lua
```
Green = logic + every tab build verified. Add scenarios in `run.lua`.

## Tier 2 — SavedVariables bridge (real game → dev, async)
The addon writes to `WTF/Account/<acct>/SavedVariables/Everbuff.lua`, which the dev can read.

- **Errors** are auto-captured into `EverbuffDB.debug.errors` (chained error handler).
- `/rb debug` writes a **diagnostics snapshot** (`EverbuffDB.debug.snapshot`): version, logging
  state, active session, stored sessions, reserve summary, error count.
- `/rb debug group` toggles a **fake 5-man roster** so the Crew and Readiness tabs can be seen and
  tested **solo**. `/rb debug clear` wipes captured errors.

Loop: play / reproduce → `/rb debug` → `/reload` (flushes SV) → dev reads `Everbuff.lua`.

Path on this machine:
`C:\Program Files (x86)\World of Warcraft\_retail_\WTF\Account\CRAASH1990\SavedVariables\Everbuff.lua`

## Tier 3 — screenshots (visual only)
For pixel/layout: `/rb`, screenshot the tabs, share them. Tiers 1–2 have usually caught the logic
bugs by then, so this is quick.
