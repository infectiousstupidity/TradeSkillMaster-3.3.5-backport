#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

if [[ -n "${LUAC:-}" ]]; then
	luac_bin="$LUAC"
elif command -v luac5.1 >/dev/null 2>&1; then
	luac_bin="$(command -v luac5.1)"
elif command -v luac >/dev/null 2>&1; then
	luac_bin="$(command -v luac)"
else
	echo "error: Lua compiler not found (install Lua 5.1 or set LUAC)" >&2
	exit 1
fi

python3 scripts/validate_repo.py check --luac "$luac_bin"

if command -v luacheck >/dev/null 2>&1; then
	mapfile -t lua_files < <(python3 scripts/validate_repo.py list-lua)
	luacheck "${lua_files[@]}" \
		--config .luacheckrc \
		--codes \
		--only 221 321 341 411 511 531 532 571 582
else
	echo "note: luacheck not installed; high-signal static analysis skipped" >&2
fi
