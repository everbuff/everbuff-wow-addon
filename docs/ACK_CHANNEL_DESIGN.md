# Desktop -> addon ack channel

**Status 2026-09-25: the ADDON side of both A and B is built** (`ns.applyAck`, `EverbuffAck` SavedVariable, `/eb ack`, Settings > Data paste box, Settings > Capture "Desktop sync"). What remains is the DESKTOP side: detect "WoW closed", write `EverbuffAck.lua`, and show the paste code after an upload. Format in `ADDON_DATA_CONTRACT.md`.

## Problem

The addon keeps `fights[]` (cap 250), `lootlog[]` (2000) and `eventlog[]` (500) in SavedVariables. Cleanup
is meant to be upload-driven: once the desktop has shipped a fight, the addon prunes it (`pruneUploaded`
reads `fight.uploaded` / `db.uploadedThrough`). But nothing can set those today, so nothing is ever
pruned and the caps silently drop the oldest records on long days. The addon warns in chat within 25 of
the cap; that is a mitigation, not a fix.

## Constraints (hard, client-imposed)

- An addon cannot read files, open sockets, or receive anything from outside the game while running.
- SavedVariables are written by WoW **wholesale** on `/reload` and logout; any external edit made while
  the game runs is overwritten. Edits made while the game is **closed** are read at next launch.
- Fight ids: `fight.id` (per-file counter) resets if the file is lost; `fight.uid` is globally unique and
  is the key to ack on.

## Option A: companion SavedVariables file, written only while WoW is closed  (recommended)

- The addon declares a second SavedVariable, e.g. `EverbuffAck` (TOC: `## SavedVariables: EverbuffDB, EverbuffAck`).
- The desktop, **only when no WoW client process is running**, writes
  `WTF/Account/<acct>/SavedVariables/EverbuffAck.lua` containing
  `EverbuffAck = { uids = { ["Hart-Realm-1758…-3f2a"] = true, … }, through = <startEpoch>, written = <epoch> }`.
- On `ADDON_LOADED` the addon reads `EverbuffAck`, marks matching `fight.uid` as uploaded (and everything
  with `startEpoch <= through`), prunes them, then **clears** `EverbuffAck.uids` so the file cannot grow.
- Loot/event logs get the same treatment keyed by `t` (prune `<= through`).

Pros: fully automatic, no user action, robust to the beta SV bug (worst case the ack is simply re-applied
later). Cons: the desktop must detect "WoW closed" reliably (process check + file lock), and the ack is
applied one launch late (fine: the addon keeps data until then).

## Option B: paste-import string

- The desktop shows a short code (e.g. `EB-ACK-<base64 of through epoch + last 8 uids>`); the player
  pastes it into `/eb ack <code>` or an EditBox in Settings › Data.
- The addon parses it, marks/prunes, done.

Pros: works while the game runs, zero file-system coupling. Cons: manual; players will not do it often, so
caps still bite; UX friction that a "recorder" should not have.

## Recommendation

Ship **A** as the automatic path and keep **B** as a manual fallback in Settings › Data (also useful for
support). Both use `fight.uid`, both prune loot/events by `through`. Until either exists, the cap warning
stays. Decision points for you: (1) go with A+B? (2) desktop-side "WoW closed" detection is on the desktop
roadmap; (3) should `through` also prune `sessions` (currently unbounded)? I'd say yes.

## Addon-side work once decided (small)

- TOC: add `EverbuffAck` SavedVariable (needs a full client restart once).
- Core `ADDON_LOADED`: apply ack (uids + through) to fights, lootlog, eventlog, sessions; clear uids.
- `/eb ack <code>` + Settings › Data import box for B.
- Data contract doc: document the ack file format.
- Tests: apply a fake `EverbuffAck` in the stub and assert the prune.
