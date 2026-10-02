#!/usr/bin/env bash
# Kurulum / yeniden kurulum / çakışma / kaldırma testleri (geçici HOME).
# Ağ gerektirmez (--no-setup). Gerçek HOME'a dokunulmaz.
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

echo "▸ Kurulum ve kaldırma (geçici HOME)"
mkdir -p "$H/.config/nvim" "$H/.config/noctis"
echo "-- kullanıcının kendi Neovim ayarı" > "$H/.config/nvim/init.lua"
echo 'return { theme = "glacier" }' > "$H/.config/noctis/config.lua"

"$REPO/scripts/install.sh" --no-setup --yes >/dev/null 2>&1
check "uygulama kuruldu" '[ -f "$H/.local/share/noctis/app/init.lua" ]'
check "başlatıcı kuruldu ve işaretli" 'grep -q "NOCTIS-LAUNCHER" "$H/.local/bin/noctis"'
check "kurulu başlatıcı çalışır" '"$H/.local/bin/noctis" --version | grep -q "^NOCTIS"'
check "kullanıcı ayarı korunur" 'grep -q glacier "$H/.config/noctis/config.lua"'
check "normal Neovim ayarına dokunulmaz" 'grep -q "kendi Neovim" "$H/.config/nvim/init.lua"'
check "normal Neovim state dizini oluşturulmaz" '[ ! -e "$H/.local/state/nvim" ]'

echo "eski" > "$H/.local/share/noctis/app/STALE"
"$REPO/scripts/install.sh" --no-setup --yes >/dev/null 2>&1
check "yeniden kurulum uygulamayı tümüyle yeniler" '[ ! -e "$H/.local/share/noctis/app/STALE" ]'
check "yeniden kurulumda ayar korunur" 'grep -q glacier "$H/.config/noctis/config.lua"'

rm "$H/.local/bin/noctis"
printf '#!/bin/sh\necho baska\n' > "$H/.local/bin/noctis"
"$REPO/scripts/install.sh" --no-setup --yes >/dev/null 2>&1; code=$?
check "NOCTIS'e ait olmayan başlatıcının üzerine yazılmaz" '[ "$code" -ne 0 ] && grep -q baska "$H/.local/bin/noctis"'
rm "$H/.local/bin/noctis"
"$REPO/scripts/install.sh" --no-setup --yes >/dev/null 2>&1

mkdir -p "$H/proje" "$H/.local/state/noctis/noctis"
echo "kod" > "$H/proje/main.py"
"$REPO/scripts/uninstall.sh" --yes >/dev/null 2>&1
check "kaldırma: başlatıcı silindi" '[ ! -e "$H/.local/bin/noctis" ]'
check "kaldırma: uygulama/eklentiler silindi" '[ ! -e "$H/.local/share/noctis" ]'
check "kaldırma: ayarlar ve state korunur" '[ -f "$H/.config/noctis/config.lua" ] && [ -d "$H/.local/state/noctis" ]'
check "kaldırma: projeye dokunulmaz" '[ -f "$H/proje/main.py" ]'

"$REPO/scripts/install.sh" --no-setup --yes >/dev/null 2>&1
"$REPO/scripts/uninstall.sh" --purge --yes >/dev/null 2>&1
check "--purge: ayarlar ve state silinir" '[ ! -e "$H/.config/noctis" ] && [ ! -e "$H/.local/state/noctis" ]'
check "--purge: normal Neovim ayarı korunur" '[ -f "$H/.config/nvim/init.lua" ]'
check "--purge: projeye dokunulmaz" '[ -f "$H/proje/main.py" ]'

echo
echo "$pass başarılı, $fail başarısız"
[ "$fail" -eq 0 ]
