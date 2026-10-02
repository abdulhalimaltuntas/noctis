#!/usr/bin/env bash
# NOCTIS uninstall script. Only targets files managed by NOCTIS;
# your projects are never touched.
#   Default: launcher, app, plugins/Mason tools/parsers, cache
#   Kept:    settings (config.lua), sessions, undo history, AI records,
#            trash and recovered copies   (--purge removes these too)
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
      echo "Usage: scripts/uninstall.sh [--purge] [--yes]"
      exit 0 ;;
    *) echo "Unknown option: $a" >&2; exit 2 ;;
  esac
done

# Safety: only non-empty paths ending in APPNAME are removed
safe_rm() {
  local p="$1"
  case "$p" in
    ""|"/"|"$HOME"|"$HOME/") echo "Skipped an unsafe path: '$p'" >&2; return ;;
  esac
  case "$p" in
    */"$APPNAME") ;;
    *) echo "Skipped an unexpected path: $p" >&2; return ;;
  esac
  if [ -e "$p" ]; then
    rm -rf -- "$p"
    echo "  removed: $p"
  fi
  return 0
}

targets=()
[ -f "$LAUNCHER" ] && grep -q "$MARKER" "$LAUNCHER" && targets+=("$LAUNCHER")
[ -d "$DATA_DIR" ] && targets+=("$DATA_DIR  (app, plugins, Mason tools, parsers)")
[ -d "$CACHE_DIR" ] && targets+=("$CACHE_DIR")
if [ "$PURGE" -eq 1 ]; then
  [ -d "$CONFIG_DIR" ] && targets+=("$CONFIG_DIR  (YOUR SETTINGS)")
  [ -d "$STATE_DIR" ] && targets+=("$STATE_DIR  (sessions, undo, AI records, trash)")
fi

if [ ${#targets[@]} -eq 0 ]; then
  echo "No $NAME installation found."
  exit 0
fi
echo "$NAME will be uninstalled. To be removed:"
for t in "${targets[@]}"; do echo "  • $t"; done
if [ "$PURGE" -eq 0 ]; then
  echo "Kept (remove with --purge):"
  [ -d "$CONFIG_DIR" ] && echo "  • $CONFIG_DIR (settings)"
  [ -d "$STATE_DIR" ] && echo "  • $STATE_DIR (sessions, undo, AI records, trash, recovered copies)"
fi
echo "Your projects are not touched."
if [ "$YES" -ne 1 ]; then
  printf 'Continue? [y/N] '
  read -r ans || exit 1
  case "$ans" in y|Y|yes|YES) ;; *) echo "Cancelled."; exit 1 ;; esac
fi

if [ -f "$LAUNCHER" ] && grep -q "$MARKER" "$LAUNCHER"; then
  rm -f -- "$LAUNCHER" && echo "  removed: $LAUNCHER"
fi
safe_rm "$DATA_DIR"
safe_rm "$CACHE_DIR"
if [ "$PURGE" -eq 1 ]; then
  safe_rm "$CONFIG_DIR"
  safe_rm "$STATE_DIR"
fi
echo "Done."
