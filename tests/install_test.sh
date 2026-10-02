#!/usr/bin/env bash
# Install / reinstall / conflict / uninstall tests (temporary HOME).
# No network needed (--no-setup). The real HOME is never touched.
set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
H="$(mktemp -d)"
trap 'rm -rf "$H"' EXIT
export HOME="$H"
unset XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME NOCTIS_HOME
pass=0; fail=0
ok() { pass=$((pass + 1)); echo "  ✓ $1"; }
no() { fail=$((fail + 1)); echo "  ✗ $1"; }
check() { if eval "$2"; then ok "$1"; else no "$1"; fi; }

echo "▸ Install and uninstall (temporary HOME)"
mkdir -p "$H/.config/nvim" "$H/.config/noctis"
echo "-- the user's own Neovim config" > "$H/.config/nvim/init.lua"
echo 'return { theme = "glacier" }' > "$H/.config/noctis/config.lua"

"$REPO/scripts/install.sh" --no-setup --yes >/dev/null 2>&1
check "app installed" '[ -f "$H/.local/share/noctis/app/init.lua" ]'
check "launcher installed and marked" 'grep -q "NOCTIS-LAUNCHER" "$H/.local/bin/noctis"'
check "installed launcher runs" '"$H/.local/bin/noctis" --version | grep -q "^NOCTIS"'
check "user setting is kept" 'grep -q glacier "$H/.config/noctis/config.lua"'
check "regular Neovim config is untouched" 'grep -q "own Neovim" "$H/.config/nvim/init.lua"'
check "no regular Neovim state directory is created" '[ ! -e "$H/.local/state/nvim" ]'

echo "stale" > "$H/.local/share/noctis/app/STALE"
"$REPO/scripts/install.sh" --no-setup --yes >/dev/null 2>&1
check "reinstall replaces the app completely" '[ ! -e "$H/.local/share/noctis/app/STALE" ]'
check "setting is kept on reinstall" 'grep -q glacier "$H/.config/noctis/config.lua"'

rm "$H/.local/bin/noctis"
printf '#!/bin/sh\necho other\n' > "$H/.local/bin/noctis"
"$REPO/scripts/install.sh" --no-setup --yes >/dev/null 2>&1; code=$?
check "a launcher not owned by NOCTIS is not overwritten" '[ "$code" -ne 0 ] && grep -q other "$H/.local/bin/noctis"'
rm "$H/.local/bin/noctis"
"$REPO/scripts/install.sh" --no-setup --yes >/dev/null 2>&1

mkdir -p "$H/project" "$H/.local/state/noctis/noctis"
echo "code" > "$H/project/main.py"
"$REPO/scripts/uninstall.sh" --yes >/dev/null 2>&1
check "uninstall: launcher removed" '[ ! -e "$H/.local/bin/noctis" ]'
check "uninstall: app/plugins removed" '[ ! -e "$H/.local/share/noctis" ]'
check "uninstall: settings and state kept" '[ -f "$H/.config/noctis/config.lua" ] && [ -d "$H/.local/state/noctis" ]'
check "uninstall: project untouched" '[ -f "$H/project/main.py" ]'

"$REPO/scripts/install.sh" --no-setup --yes >/dev/null 2>&1
"$REPO/scripts/uninstall.sh" --purge --yes >/dev/null 2>&1
check "--purge: settings and state removed" '[ ! -e "$H/.config/noctis" ] && [ ! -e "$H/.local/state/noctis" ]'
check "--purge: regular Neovim config kept" '[ -f "$H/.config/nvim/init.lua" ]'
check "--purge: project untouched" '[ -f "$H/project/main.py" ]'

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
