# everbuff.gg — WoW addon

The in-game companion for **[everbuff.gg](https://everbuff.gg)** — *every run makes you stronger.*

Always-on advanced combat logging + a fight/leveling landmark index. The addon is the in-game half
of Everbuff: it turns on combat logging automatically (no `/combatlog` needed) and writes a compact
beacon to SavedVariables so the desktop app can line up your video with the log. The combat-log file
is the source of truth; the addon just makes sure it's always being written and marks the moments the
log can't see.

## Install

The **Everbuff desktop app** installs and updates this addon for you (Addons tab) — it pulls the
latest release here and drops the `Everbuff/` folder into each WoW install. Manual install:

1. Download the latest `Everbuff.zip` from [Releases](../../releases/latest).
2. Extract the `Everbuff/` folder into `World of Warcraft/<flavor>/Interface/AddOns/`.
3. Restart WoW (or `/reload`).

Works on retail (Midnight 12.0+, the "WoW Forever" model) and Classic flavors — the multi-flavor TOCs
(`Everbuff_Mainline.toc`, `Everbuff_Vanilla.toc`) load the right build automatically.

## Layout

- `Everbuff/` — the addon that ships to the game (this is what a release zips up).
- `test/` — a LuaJIT mock harness that runs the addon with no game attached (`bash test/run.sh`).

SavedVariables: `EverbuffDB`.
