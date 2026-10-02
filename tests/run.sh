#!/usr/bin/env bash
# NOCTIS test paketi.
#   tests/run.sh            ağ gerektirmeyen tüm testler
#   tests/run.sh --plugins  + eklentili testler (ilk seferde eklentileri
#                            tests/.tmp altına indirir; ağ gerekir)
# Her paket temiz, geçici XDG dizinleriyle çalışır; kullanıcının Neovim
# veya NOCTIS kurulumuna dokunulmaz.
set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"
PLUGINS=0
[ "${1:-}" = "--plugins" ] && PLUGINS=1
fail=0

run_suite() {
  local file="$1" data="${2:-}" safe="${3:-1}"
  local T
  T="$(mktemp -d)"
  (
    export XDG_CONFIG_HOME="$T/c" XDG_STATE_HOME="$T/s" XDG_CACHE_HOME="$T/x"
    export XDG_DATA_HOME="${data:-$T/d}"
    export NOCTIS_HOME="$REPO/app" NVIM_APPNAME=noctis
    if [ "$safe" = "1" ]; then export NOCTIS_SAFE=1; else unset NOCTIS_SAFE; fi
    timeout 600 nvim --headless -u "$REPO/app/init.lua" -l "$REPO/tests/lua/$file" </dev/null
  ) || fail=1
  rm -rf "$T"
}

bash tests/launcher_test.sh || fail=1
run_suite test_core.lua
run_suite test_ai.lua
run_suite test_safe.lua "" 1
run_suite test_safe.lua "" 0 # eklentisiz normal mod (çevrimdışı açılış)

if [ "$PLUGINS" -eq 1 ]; then
  DATA="$REPO/tests/.tmp/xdg-data"
  if [ ! -d "$DATA/noctis/lazy/lazy.nvim" ]; then
    echo "▸ Eklentiler indiriliyor (tests/.tmp)…"
    mkdir -p "$DATA"
    XDG_DATA_HOME="$DATA" XDG_CONFIG_HOME="$(mktemp -d)" XDG_STATE_HOME="$(mktemp -d)" XDG_CACHE_HOME="$(mktemp -d)" \
      "$REPO/bin/noctis" --setup >/dev/null || { echo "eklenti kurulumu başarısız"; exit 1; }
  fi
  run_suite test_plugins.lua "$DATA" 0
  run_suite test_lsp.lua "$DATA" 0
fi

echo
if [ "$fail" -eq 0 ]; then echo "TÜM TESTLER GEÇTİ"; else echo "BAŞARISIZ TEST VAR"; fi
exit "$fail"
