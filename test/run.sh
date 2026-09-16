#!/usr/bin/env bash
# Tier-1 dev loop: run the Everbuff addon under the WoW mock (no game needed).
# Finds LuaJIT (Lua 5.1, same as WoW) and runs the harness.
set -e
LJ="${LUAJIT:-/c/Users/samhart/AppData/Local/Programs/LuaJIT/bin/luajit.exe}"
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$LJ" "$DIR/run.lua" "$@"
