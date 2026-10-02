#!/usr/bin/env bash
# docs/KEYMAPS.md dosyasını komut kaydından üretir (tek kaynak).
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export XDG_CONFIG_HOME="$TMP/c" XDG_DATA_HOME="$TMP/d" XDG_STATE_HOME="$TMP/s" XDG_CACHE_HOME="$TMP/x"
export NOCTIS_HOME="$REPO/app" NVIM_APPNAME=noctis NOCTIS_SAFE=1
mkdir -p "$REPO/docs"
nvim --headless -u "$REPO/app/init.lua" \
  -c "lua local f = io.open('$REPO/docs/KEYMAPS.md', 'w'); f:write(require('noctis.registry').markdown() .. '\n'); f:close()" \
  -c "qa!"
echo "docs/KEYMAPS.md güncellendi"
