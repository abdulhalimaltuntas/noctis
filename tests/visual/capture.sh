#!/usr/bin/env bash
# NOCTIS screenshots inside a real PTY (tmux).
# Every scene is driven by real keystrokes; a capture is the terminal's
# content at that moment (24-bit color included). These are not mockups.
#
# Requires: tmux, python3, node + playwright (Chromium), installed plugins.
# Usage: DATA=<XDG_DATA_HOME with plugins> FONTS=<dir> [DEMO=<demo project>] tests/visual/capture.sh [scene...]
#   Without DEMO, a fresh demo project is created with tests/visual/make-demo.sh.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VIS="$REPO/tests/visual"
OUT="${OUT:-$REPO/docs/screenshots}"
FONTS="${FONTS:?directory with the Nerd Font symbols font required (SymbolsNerdFontMono-Regular.ttf)}"
DATA="${DATA:?XDG_DATA_HOME with the plugins installed required}"
WORK="$(mktemp -d)"
DEMO="${DEMO:-$WORK/orders}"
[ -d "$DEMO/.git" ] || "$VIS/make-demo.sh" "$DEMO" >/dev/null
SOCK="noctis-shot-$$"
mkdir -p "$OUT"
trap 'tmux -L "$SOCK" kill-server 2>/dev/null || true; sleep 0.3; rm -rf "$WORK" 2>/dev/null || true' EXIT

cat > "$WORK/tmux.conf" <<'EOF'
set -g default-terminal "tmux-256color"
set -as terminal-features ",*:RGB"
set -g status off
set -g escape-time 10
set -g history-limit 2000
EOF

tm() { tmux -L "$SOCK" -f "$WORK/tmux.conf" "$@"; }

# start <scene> <columns> <rows> [config.lua content] [command]
start() {
  local name="$1" cols="$2" rows="$3" config="${4:-}" cmd="${5:-$REPO/bin/noctis}"
  tm kill-server 2>/dev/null || true
  local X="$WORK/$name"
  mkdir -p "$X/c/noctis" "$X/s/noctis/noctis" "$X/x"
  [ -n "$config" ] && printf '%s\n' "$config" > "$X/c/noctis/config.lua"
  # The tour only shows in the first-launch scene
  if [ "$name" != "dashboard" ]; then
    printf '{"onboarding_done":true}' > "$X/s/noctis/noctis/ui.json"
  fi
  tm new-session -d -s main -x "$cols" -y "$rows" -c "$DEMO" \
    -e "XDG_CONFIG_HOME=$X/c" -e "XDG_STATE_HOME=$X/s" -e "XDG_CACHE_HOME=$X/x" \
    -e "XDG_DATA_HOME=$DATA" -e "COLORTERM=truecolor" -e "NOCTIS_HOME=" \
    "$cmd"
  sleep "${WAIT:-2.5}"
}

keys() { tm send-keys -t main "$@"; sleep "${KEY_WAIT:-0.6}"; }
lit() { tm send-keys -t main -l "$1"; sleep "${KEY_WAIT:-0.6}"; }

shot() {
  local name="$1" bg="${2:-#0b1020}" fg="${3:-#dce5f5}"
  tm capture-pane -e -p -t main > "$WORK/$name.ansi"
  python3 "$VIS/ansi2html.py" "$WORK/$name.ansi" "$WORK/$name.html" "$name" "$bg" "$fg" "$FONTS"
  node "$VIS/shoot.mjs" "$WORK/$name.html" "$OUT/$name.png"
  [ -n "${KEEP_ANSI:-}" ] && cp "$WORK/$name.ansi" "$OUT/$name.ansi"
  echo "  ✓ $OUT/$name.png"
}

# Reset the demo project to a known state (including a pre-existing user
# edit), so scenes don't affect each other.
reset_demo() {
  (cd "$DEMO" && git checkout -q -- . && git clean -qfd \
    && sed -i 's/return f"{currency}{value:,.2f}"/return f"{currency} {value:,.2f}"/' app/utils.py)
}

FAKE_PROFILE="ai = { profiles = { test = { label = 'Test CLI', cmd = { '$REPO/tools/noctis-fake-ai' } } } }"

SCENES=("$@")
want() { [ ${#SCENES[@]} -eq 0 ] || [[ " ${SCENES[*]} " == *" $1 "* ]]; }
set --

if want dashboard; then
  start dashboard 120 35
  shot dashboard
fi

if want editor; then
  start editor 120 35 "" "$REPO/bin/noctis app/main.py"
  keys " " "e"; sleep 0.8
  keys C-l; keys 18G; keys "w"
  shot editor
fi

if want command-palette; then
  start command-palette 120 35 "" "$REPO/bin/noctis app/main.py"
  keys " " " "; sleep 0.5
  lit "find"
  shot command-palette
fi

if want which-key; then
  start which-key 120 35 "" "$REPO/bin/noctis app/main.py"
  tm send-keys -t main " "; sleep 1.2
  shot which-key
fi

if want ai-workbench; then
  reset_demo
  start ai-workbench 170 45 "return { $FAKE_PROFILE }" "$REPO/bin/noctis app/utils.py"
  keys " " "a" "n"; sleep 0.8
  lit "Test"; keys Enter; sleep 2.5
  lit "color"; keys Enter
  lit "replace app/utils.py .2f .1f"; keys Enter
  lit "write app/report.py def report():\\n    return 'ready'\\n"; keys Enter
  sleep 1.5
  shot ai-workbench
fi

if want ai-changes; then
  # Continues the session from 05 (the interval changes are visible)
  keys C-\\ e; sleep 0.4
  keys " " "a" "d"; sleep 1
  shot ai-changes
fi

if want diff-side-by-side; then
  keys Down Down Down Down; sleep 0.3
  tm send-keys -t main "/utils" Enter; sleep 0.4
  keys Enter; sleep 1.2
  shot diff-side-by-side
fi

if want diff-unified; then
  reset_demo
  start diff-unified 100 32 "return { $FAKE_PROFILE }" "$REPO/bin/noctis app/utils.py"
  keys " " "a" "n"; sleep 0.8
  lit "Test"; keys Enter; sleep 2.5
  lit "replace app/utils.py .2f .1f"; keys Enter; sleep 1.5
  keys C-\\ e; sleep 0.4
  keys " " "a" "d"; sleep 1
  tm send-keys -t main "/utils" Enter; sleep 0.4
  keys Enter; sleep 1
  shot diff-unified
fi

if want small-terminal; then
  start small-terminal 80 24 "" "$REPO/bin/noctis app/main.py"
  keys 12G
  shot small-terminal
fi

if want theme-glacier; then
  start theme-glacier 120 35 "return { theme = 'glacier' }" "$REPO/bin/noctis app/main.py"
  keys " " "e"; sleep 0.8; keys C-l
  shot theme-glacier "#0a141b" "#d9e8f1"
fi

if want theme-amber; then
  start theme-amber 120 35 "return { theme = 'amber' }" "$REPO/bin/noctis app/main.py"
  keys " " "e"; sleep 0.8; keys C-l
  shot theme-amber "#14100b" "#ede3d3"
fi

if want no-icons-ascii; then
  start no-icons-ascii 100 30 "return { icons = false, borders = 'ascii' }" "$REPO/bin/noctis app/main.py"
  keys " " " "; sleep 0.5; lit "theme"
  shot no-icons-ascii
fi

# AI change marks (A/M/D) and Git status in the explorer
if want explorer-ai-marks; then
  reset_demo
  start explorer-ai-marks 150 40 "return { $FAKE_PROFILE }" "$REPO/bin/noctis app/main.py"
  keys " " "a" "n"; sleep 0.8
  lit "Test"; keys Enter; sleep 2.5
  lit "replace app/utils.py .2f .1f"; keys Enter
  lit "write app/report.py x = 1\\n"; keys Enter
  lit "delete tests/test_main.py"; keys Enter; sleep 1.5
  keys C-\\ e; sleep 0.4
  keys " " "e"; sleep 1.5
  tm send-keys -t main ":redraw! | echo ''" Enter; sleep 0.5
  shot explorer-ai-marks
  reset_demo
fi

# Real Claude Code (if installed): terminal compatibility only. No prompt is
# sent; no paid task is started. Ctrl-C goes to the tool itself.
if want claude-code && command -v claude >/dev/null 2>&1; then
  reset_demo
  start claude-code 160 45 "" "$REPO/bin/noctis app/main.py"
  keys " " "a" "n"; sleep 0.8
  lit "Claude"; keys Enter; sleep 7
  shot claude-code
  tm resize-window -t main -x 120 -y 35; sleep 2
  shot claude-code-resized
  tm send-keys -t main C-c; sleep 0.8; tm send-keys -t main C-c; sleep 2
  keys C-\\ e; sleep 0.4
  shot claude-code-exit
  reset_demo
fi

echo "Done: $OUT"
