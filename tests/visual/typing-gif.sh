#!/usr/bin/env bash
# Records the typing animation as a GIF from a real PTY (tmux): a line is typed
# character by character while the pane is captured every ~35 ms; the frames
# are rendered with the same cell-grid renderer as the screenshots.
#
# Requires: tmux, python3, node + playwright (Chromium), ffmpeg, installed plugins.
# Usage: DATA=<XDG_DATA_HOME with plugins> FONTS=<dir> [DEMO=<demo project>] \
#          tests/visual/typing-gif.sh [output.gif]
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VIS="$REPO/tests/visual"
OUT="${1:-$REPO/docs/screenshots/typing.gif}"
FONTS="${FONTS:?directory with the Nerd Font symbols font required (SymbolsNerdFontMono-Regular.ttf)}"
DATA="${DATA:?XDG_DATA_HOME with the plugins installed required}"
WORK="$(mktemp -d)"
DEMO="${DEMO:-$WORK/orders}"
[ -d "$DEMO/.git" ] || "$VIS/make-demo.sh" "$DEMO" >/dev/null
SOCK="noctis-gif-$$"
trap 'tmux -L "$SOCK" kill-server 2>/dev/null || true; sleep 0.3; rm -rf "$WORK" 2>/dev/null || true' EXIT

cat > "$WORK/tmux.conf" <<'EOF'
set -g default-terminal "tmux-256color"
set -as terminal-features ",*:RGB"
set -g status off
set -g escape-time 10
EOF
tm() { tmux -L "$SOCK" -f "$WORK/tmux.conf" "$@"; }

X="$WORK/x"
mkdir -p "$X/c" "$X/s/noctis/noctis" "$X/cache" "$WORK/frames"
printf '{"onboarding_done":true}' > "$X/s/noctis/noctis/ui.json"
tm new-session -d -s main -x 80 -y 16 -c "$DEMO" \
  -e "XDG_CONFIG_HOME=$X/c" -e "XDG_STATE_HOME=$X/s" -e "XDG_CACHE_HOME=$X/cache" \
  -e "XDG_DATA_HOME=$DATA" -e "COLORTERM=truecolor" -e "NOCTIS_HOME=" \
  "$REPO/bin/noctis greet.lua"
sleep 2.5

n=0
frame() {
  tm capture-pane -e -p -t main > "$WORK/frames/$(printf '%04d' "$n").ansi"
  n=$((n + 1))
}

# A new Lua file: syntax colors, and the text has no repeated words, so no
# completion/signature popup covers the typed line (the glow is the subject).
tm send-keys -t main i; sleep 0.3
for _ in 1 2 3 4 5 6; do frame; sleep 0.05; done

type_line() {
  local text="$1" i
  for ((i = 0; i < ${#text}; i++)); do
    tm send-keys -t main -l "${text:i:1}"
    sleep 0.035; frame
    sleep 0.035; frame
  done
}
type_line 'local function greet()'
tm send-keys -t main Enter; sleep 0.05; frame
type_line 'print("Welcome back!")'
tm send-keys -t main Enter; sleep 0.05; frame
type_line 'end'
tm send-keys -t main Escape
for _ in $(seq 1 12); do sleep 0.05; frame; done

# Render: ANSI → HTML → PNG (one browser session for all frames)
args=()
for f in "$WORK"/frames/*.ansi; do
  python3 "$VIS/ansi2html.py" "$f" "${f%.ansi}.html" frame "#0b1020" "#dce5f5" "$FONTS"
  args+=("${f%.ansi}.html" "${f%.ansi}.png")
done
node "$VIS/shoot.mjs" "${args[@]}"

# Hold the last frame for ~1.5 s before the loop restarts
last="$(ls "$WORK"/frames/*.png | tail -1)"
for k in $(seq 1 30); do cp "$last" "$WORK/frames/$(printf '%04d' $((n + k))).png"; done

mkdir -p "$(dirname "$OUT")"
# 80×16 keeps the normal layout (smaller terminals hide the tab bar). Keep the
# tab bar + first code rows and the statusline row (row 14); drop the empty middle.
ROW=17
ffmpeg -loglevel error -y -framerate 20 -pattern_type glob -i "$WORK/frames/*.png" \
  -vf "split[a][b];[a]crop=iw:$((6 * ROW)):0:0[top];[b]crop=iw:$ROW:0:$((14 * ROW))[st];[top][st]vstack,split[c][d];[c]palettegen=max_colors=96:stats_mode=diff[p];[d][p]paletteuse=dither=none:diff_mode=rectangle" \
  -loop 0 "$OUT"
echo "  ✓ $OUT ($(du -h "$OUT" | cut -f1), $n frames)"
