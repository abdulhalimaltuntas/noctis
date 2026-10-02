#!/usr/bin/env bash
# NOCTIS kaldırma scripti. Yalnız NOCTIS'in yönettiği dosyaları hedefler;
# projelerinize asla dokunmaz.
#   Varsayılan: başlatıcı, uygulama, eklentiler/Mason araçları/parser'lar, cache
#   Korunur:    ayarlar (config.lua), oturumlar, undo geçmişi, AI kayıtları,
#               çöp kutusu ve kurtarılan kopyalar   (--purge ile bunlar da silinir)
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BRAND_FILE="$REPO/app/BRAND"
brand() { grep -E "^$1=" "$BRAND_FILE" | head -n1 | cut -d= -f2-; }
COMMAND="$(brand COMMAND)"; APPNAME="$(brand APPNAME)"; NAME="$(brand NAME)"

DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/$APPNAME"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/$APPNAME"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/$APPNAME"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/$APPNAME"
BIN_DIR="${NOCTIS_BIN_DIR:-$HOME/.local/bin}"
LAUNCHER="$BIN_DIR/$COMMAND"
MARKER="# NOCTIS-LAUNCHER"

PURGE=0; YES=0
for a in "$@"; do
  case "$a" in
    --purge) PURGE=1 ;;
    --yes|-y) YES=1 ;;
    -h|--help)
      sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
      echo "Kullanım: scripts/uninstall.sh [--purge] [--yes]"
      exit 0 ;;
    *) echo "Bilinmeyen seçenek: $a" >&2; exit 2 ;;
  esac
done

# Güvenlik: yalnız APPNAME ile biten, boş olmayan yollar silinir
safe_rm() {
  local p="$1"
  case "$p" in
    ""|"/"|"$HOME"|"$HOME/") echo "Güvensiz yol atlandı: '$p'" >&2; return ;;
  esac
  case "$p" in
    */"$APPNAME") ;;
    *) echo "Beklenmeyen yol atlandı: $p" >&2; return ;;
  esac
  if [ -e "$p" ]; then
    rm -rf -- "$p"
    echo "  silindi: $p"
  fi
  return 0
}

targets=()
[ -f "$LAUNCHER" ] && grep -q "$MARKER" "$LAUNCHER" && targets+=("$LAUNCHER")
[ -d "$DATA_DIR" ] && targets+=("$DATA_DIR  (uygulama, eklentiler, Mason araçları, parser'lar)")
[ -d "$CACHE_DIR" ] && targets+=("$CACHE_DIR")
if [ "$PURGE" -eq 1 ]; then
  [ -d "$CONFIG_DIR" ] && targets+=("$CONFIG_DIR  (AYARLARINIZ)")
  [ -d "$STATE_DIR" ] && targets+=("$STATE_DIR  (oturumlar, undo, AI kayıtları, çöp kutusu)")
fi

if [ ${#targets[@]} -eq 0 ]; then
  echo "$NAME kurulumu bulunamadı."
  exit 0
fi
echo "$NAME kaldırılacak. Silinecekler:"
for t in "${targets[@]}"; do echo "  • $t"; done
if [ "$PURGE" -eq 0 ]; then
  echo "Korunacaklar (silmek için --purge):"
  [ -d "$CONFIG_DIR" ] && echo "  • $CONFIG_DIR (ayarlar)"
  [ -d "$STATE_DIR" ] && echo "  • $STATE_DIR (oturumlar, undo, AI kayıtları, çöp kutusu, kurtarılan kopyalar)"
fi
echo "Projelerinize dokunulmaz."
if [ "$YES" -ne 1 ]; then
  printf 'Devam edilsin mi? [e/H] '
  read -r ans || exit 1
  case "$ans" in e|E|evet|y|Y|yes) ;; *) echo "İptal edildi."; exit 1 ;; esac
fi

if [ -f "$LAUNCHER" ] && grep -q "$MARKER" "$LAUNCHER"; then
  rm -f -- "$LAUNCHER" && echo "  silindi: $LAUNCHER"
fi
safe_rm "$DATA_DIR"
safe_rm "$CACHE_DIR"
if [ "$PURGE" -eq 1 ]; then
  safe_rm "$CONFIG_DIR"
  safe_rm "$STATE_DIR"
fi
echo "Tamam."
