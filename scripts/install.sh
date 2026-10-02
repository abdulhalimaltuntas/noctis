#!/usr/bin/env bash
# NOCTIS kurulum scripti — kullanıcı alanında, root gerektirmez, tekrar
# çalıştırılabilir. Sistem paketi kurmaz; eksikleri ve kurulum yollarını
# gösterir. Kullanıcı ayarları (config.lua), oturumlar ve AI kayıtları korunur.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BRAND_FILE="$REPO/app/BRAND"

brand() { grep -E "^$1=" "$BRAND_FILE" | head -n1 | cut -d= -f2-; }
NAME="$(brand NAME)"; COMMAND="$(brand COMMAND)"; APPNAME="$(brand APPNAME)"
VERSION="$(brand VERSION)"; MIN_NVIM="$(brand MIN_NVIM)"

DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
APP_DIR="$DATA_HOME/$APPNAME/app"
BIN_DIR="${NOCTIS_BIN_DIR:-$HOME/.local/bin}"
LAUNCHER="$BIN_DIR/$COMMAND"
MARKER="# NOCTIS-LAUNCHER"

SETUP=1; FORCE=0; YES=0
usage() {
  cat <<EOF
$NAME $VERSION kurulumu

Kullanım: scripts/install.sh [--no-setup] [--force] [--yes] [--bin-dir DİZİN]

  --no-setup   Eklentileri şimdi indirme (sonra: $COMMAND --setup)
  --force      Hedefte NOCTIS'e ait olmayan bir '$COMMAND' varsa üzerine yaz
  --yes        Onay sorma
  --bin-dir    Başlatıcı dizini (varsayılan: ~/.local/bin)

Kurulan:   $APP_DIR (uygulama), $LAUNCHER (başlatıcı)
Dokunulmaz: $CONFIG_HOME/$APPNAME (ayarlarınız), $STATE_HOME/$APPNAME (oturumlar, AI kayıtları)
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --no-setup) SETUP=0 ;;
    --force) FORCE=1 ;;
    --yes|-y) YES=1 ;;
    --bin-dir) BIN_DIR="$2"; LAUNCHER="$BIN_DIR/$COMMAND"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Bilinmeyen seçenek: $1" >&2; usage; exit 2 ;;
  esac
  shift
done

say() { printf '%s\n' "$*"; }
ok() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*"; }

confirm() {
  [ "$YES" -eq 1 ] && return 0
  printf '%s [e/H] ' "$1"
  read -r ans || return 1
  case "$ans" in e|E|evet|y|Y|yes) return 0 ;; *) return 1 ;; esac
}

version_ge() {
  local IFS=.
  local -a a=($1) b=($2)
  for i in 0 1 2; do
    local x="${a[$i]:-0}" y="${b[$i]:-0}"
    x="${x%%[!0-9]*}"; y="${y%%[!0-9]*}"; x="${x:-0}"; y="${y:-0}"
    [ "$x" -gt "$y" ] && return 0
    [ "$x" -lt "$y" ] && return 1
  done
  return 0
}

os_hint() {
  case "$(uname -s)" in
    Linux)
      if command -v apt-get >/dev/null 2>&1; then echo "Debian/Ubuntu: sudo apt install $1"
      elif command -v dnf >/dev/null 2>&1; then echo "Fedora: sudo dnf install $1"
      elif command -v pacman >/dev/null 2>&1; then echo "Arch: sudo pacman -S $1"
      else echo "dağıtımınızın paket yöneticisiyle '$1' kurun"; fi ;;
    Darwin) echo "macOS: brew install $1" ;;
    *) echo "'$1' kurun" ;;
  esac
}

say "$NAME $VERSION kurulumu"
say ""
say "Ön koşullar:"
missing=0
NVIM_BIN="${NOCTIS_NVIM:-$(command -v nvim 2>/dev/null || true)}"
if [ -n "$NVIM_BIN" ]; then
  # NVIM_APPNAME: kullanıcının normal Neovim dizinlerine dokunulmasın
  nv="$(NVIM_APPNAME="$APPNAME" "$NVIM_BIN" --version | head -n1 | sed -E 's/^NVIM v([0-9.]+).*/\1/')"
  if version_ge "$nv" "$MIN_NVIM"; then ok "Neovim $nv ($NVIM_BIN)"; else fail "Neovim $nv < $MIN_NVIM"; missing=1; fi
else
  fail "Neovim bulunamadı (>= $MIN_NVIM gerekli)"
  say "      → https://github.com/neovim/neovim/releases (dağıtım paketleri çoğunlukla eskidir)"
  missing=1
fi
if command -v git >/dev/null 2>&1; then ok "git"; else fail "git bulunamadı → $(os_hint git)"; missing=1; fi
if command -v rg >/dev/null 2>&1; then ok "ripgrep"; else warn "ripgrep yok: metin arama ve AI kapsam taraması sınırlı → $(os_hint ripgrep)"; fi
for opt in lazygit tree-sitter; do
  if command -v "$opt" >/dev/null 2>&1; then ok "$opt (isteğe bağlı)"; else say "  · $opt yok (isteğe bağlı)"; fi
done
if [ "$missing" -ne 0 ]; then
  say ""
  say "Gerekli bileşenler eksik; kurulum yapılmadı. Sistem paketleri bu script tarafından kurulmaz."
  exit 1
fi

say ""
say "Hedefler:"
say "  uygulama   $APP_DIR"
say "  başlatıcı  $LAUNCHER"

# Çakışma kontrolleri: NOCTIS'e ait olmayan dosyaların üzerine sessizce yazma
if [ -e "$LAUNCHER" ] && ! grep -q "$MARKER" "$LAUNCHER" 2>/dev/null; then
  if [ "$FORCE" -ne 1 ]; then
    fail "$LAUNCHER zaten var ve NOCTIS başlatıcısı değil. Üzerine yazmak için --force, farklı yer için --bin-dir."
    exit 1
  fi
  warn "$LAUNCHER NOCTIS'e ait değil; --force ile değiştirilecek (yedek: $LAUNCHER.bak)"
  cp -p "$LAUNCHER" "$LAUNCHER.bak"
fi
if [ -d "$APP_DIR" ] && [ ! -f "$APP_DIR/BRAND" ]; then
  fail "$APP_DIR var ama NOCTIS uygulama dizini değil; dokunulmadı."
  exit 1
fi

if [ -d "$APP_DIR" ]; then
  say "  (mevcut kurulum güncellenecek; ayarlarınız ve oturum verileri korunur)"
fi
confirm "Devam edilsin mi?" || { say "İptal edildi."; exit 1; }

# Uygulama dosyalarını atomik olarak değiştir
mkdir -p "$(dirname "$APP_DIR")" "$BIN_DIR"
STAGE="$APP_DIR.new.$$"
rm -rf "$STAGE"
cp -R "$REPO/app" "$STAGE"
if [ -d "$APP_DIR" ]; then
  mv "$APP_DIR" "$APP_DIR.old.$$"
  mv "$STAGE" "$APP_DIR"
  rm -rf "$APP_DIR.old.$$"
else
  mv "$STAGE" "$APP_DIR"
fi
ok "uygulama dosyaları kopyalandı"

# Başlatıcı: uygulama yolunu sabitle
TMP_LAUNCHER="$LAUNCHER.tmp.$$"
{
  sed -n '1p' "$REPO/bin/noctis"
  echo "$MARKER (scripts/install.sh tarafından oluşturuldu; kaldırma: scripts/uninstall.sh)"
  printf ': "${NOCTIS_HOME:=%s}"\n' "$APP_DIR"
  sed -n '2,$p' "$REPO/bin/noctis"
} > "$TMP_LAUNCHER"
chmod 0755 "$TMP_LAUNCHER"
mv "$TMP_LAUNCHER" "$LAUNCHER"
ok "başlatıcı kuruldu: $LAUNCHER"

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) warn "$BIN_DIR PATH'te değil. Kabuk yapılandırmanıza ekleyin: export PATH=\"$BIN_DIR:\$PATH\"" ;;
esac

if [ "$SETUP" -eq 1 ]; then
  say ""
  say "Eklentiler indirilecek (kilit dosyasındaki sürümler, GitHub'dan, ağ gerekir):"
  grep -oE '"[^"]+": \{ "branch": "[^"]+", "commit": "[0-9a-f]{7}' "$APP_DIR/lazy-lock.json" \
    | sed -E 's/"([^"]+)": \{ "branch": "([^"]+)", "commit": "(.*)/  • \1 \3 (\2)/'
  say "Dil sunucuları/formatter/parser indirilmez; NOCTIS içinde :NoctisLang ile seçerek kurulur."
  if confirm "Şimdi indirilsin mi?"; then
    "$LAUNCHER" --setup
  else
    say "Atlandı. Daha sonra: $COMMAND --setup"
  fi
fi

say ""
say "Hazır. Başlatmak için: $COMMAND   ·   denetim: $COMMAND --doctor"
say "Ayarlar: $CONFIG_HOME/$APPNAME/config.lua (örnek: $APP_DIR/examples/config.lua)"
