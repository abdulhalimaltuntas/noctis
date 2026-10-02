#!/usr/bin/env bash
# NOCTIS install script — runs in user space, needs no root, can be run
# again. It never installs system packages; it shows what's missing and how
# to install it. User settings (config.lua), sessions and AI records are kept.
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
$NAME $VERSION installer

Usage: scripts/install.sh [--no-setup] [--force] [--yes] [--bin-dir DIR]

  --no-setup   Don't download plugins now (later: $COMMAND --setup)
  --force      Overwrite a '$COMMAND' at the target that doesn't belong to NOCTIS
  --yes        Don't ask for confirmation
  --bin-dir    Launcher directory (default: ~/.local/bin)

Installed:   $APP_DIR (app), $LAUNCHER (launcher)
Untouched:   $CONFIG_HOME/$APPNAME (your settings), $STATE_HOME/$APPNAME (sessions, AI records)
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --no-setup) SETUP=0 ;;
    --force) FORCE=1 ;;
    --yes|-y) YES=1 ;;
    --bin-dir) BIN_DIR="$2"; LAUNCHER="$BIN_DIR/$COMMAND"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
  esac
  shift
done

say() { printf '%s\n' "$*"; }
ok() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*"; }

confirm() {
  [ "$YES" -eq 1 ] && return 0
  printf '%s [y/N] ' "$1"
  read -r ans || return 1
  case "$ans" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
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
      else echo "install '$1' with your distribution's package manager"; fi ;;
    Darwin) echo "macOS: brew install $1" ;;
    *) echo "install '$1'" ;;
  esac
}

say "$NAME $VERSION installer"
say ""
say "Prerequisites:"
missing=0
NVIM_BIN="${NOCTIS_NVIM:-$(command -v nvim 2>/dev/null || true)}"
if [ -n "$NVIM_BIN" ]; then
  # NVIM_APPNAME: don't touch the user's regular Neovim directories
  nv="$(NVIM_APPNAME="$APPNAME" "$NVIM_BIN" --version | head -n1 | sed -E 's/^NVIM v([0-9.]+).*/\1/')"
  if version_ge "$nv" "$MIN_NVIM"; then ok "Neovim $nv ($NVIM_BIN)"; else fail "Neovim $nv < $MIN_NVIM"; missing=1; fi
else
  fail "Neovim not found (>= $MIN_NVIM required)"
  say "      → https://github.com/neovim/neovim/releases (distro packages are often old)"
  missing=1
fi
if command -v git >/dev/null 2>&1; then ok "git"; else fail "git not found → $(os_hint git)"; missing=1; fi
if command -v rg >/dev/null 2>&1; then ok "ripgrep"; else warn "no ripgrep: text search and the AI scope scan are limited → $(os_hint ripgrep)"; fi
for opt in lazygit tree-sitter; do
  if command -v "$opt" >/dev/null 2>&1; then ok "$opt (optional)"; else say "  · no $opt (optional)"; fi
done
if [ "$missing" -ne 0 ]; then
  say ""
  say "Required components are missing; nothing was installed. This script doesn't install system packages."
  exit 1
fi

say ""
say "Targets:"
say "  app        $APP_DIR"
say "  launcher   $LAUNCHER"

# Conflict checks: never silently overwrite files that don't belong to NOCTIS
if [ -e "$LAUNCHER" ] && ! grep -q "$MARKER" "$LAUNCHER" 2>/dev/null; then
  if [ "$FORCE" -ne 1 ]; then
    fail "$LAUNCHER already exists and isn't a NOCTIS launcher. Use --force to overwrite, or --bin-dir for another location."
    exit 1
  fi
  warn "$LAUNCHER doesn't belong to NOCTIS; it will be replaced because of --force (backup: $LAUNCHER.bak)"
  cp -p "$LAUNCHER" "$LAUNCHER.bak"
fi
if [ -d "$APP_DIR" ] && [ ! -f "$APP_DIR/BRAND" ]; then
  fail "$APP_DIR exists but isn't a NOCTIS app directory; left untouched."
  exit 1
fi

if [ -d "$APP_DIR" ]; then
  say "  (the existing installation will be updated; your settings and session data are kept)"
fi
confirm "Continue?" || { say "Cancelled."; exit 1; }

# Replace the app files atomically
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
ok "app files copied"

# Launcher: pin the app path
TMP_LAUNCHER="$LAUNCHER.tmp.$$"
{
  sed -n '1p' "$REPO/bin/noctis"
  echo "$MARKER (created by scripts/install.sh; remove with: scripts/uninstall.sh)"
  printf ': "${NOCTIS_HOME:=%s}"\n' "$APP_DIR"
  sed -n '2,$p' "$REPO/bin/noctis"
} > "$TMP_LAUNCHER"
chmod 0755 "$TMP_LAUNCHER"
mv "$TMP_LAUNCHER" "$LAUNCHER"
ok "launcher installed: $LAUNCHER"

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) warn "$BIN_DIR is not in PATH. Add it to your shell config: export PATH=\"$BIN_DIR:\$PATH\"" ;;
esac

if [ "$SETUP" -eq 1 ]; then
  say ""
  say "Plugins to download (lockfile versions, from GitHub, needs network):"
  grep -oE '"[^"]+": \{ "branch": "[^"]+", "commit": "[0-9a-f]{7}' "$APP_DIR/lazy-lock.json" \
    | sed -E 's/"([^"]+)": \{ "branch": "([^"]+)", "commit": "(.*)/  • \1 \3 (\2)/'
  say "Language servers/formatters/parsers are not downloaded; pick and install them inside NOCTIS with :NoctisLang."
  if confirm "Download now?"; then
    "$LAUNCHER" --setup
  else
    say "Skipped. Later: $COMMAND --setup"
  fi
fi

say ""
say "Ready. Start with: $COMMAND   ·   check: $COMMAND --doctor"
say "Settings: $CONFIG_HOME/$APPNAME/config.lua (example: $APP_DIR/examples/config.lua)"
