#!/usr/bin/env bash
# Gerçek PTY (tmux) içinde NOCTIS ekran yakalamaları.
# Her sahne gerçek tuş vuruşlarıyla sürülür; yakalama terminalin o anki
# içeriğidir (24 bit renk dahil). Tasarlanmış mockup değildir.
#
# Gerekenler: tmux, python3, node + playwright (Chromium), kurulu eklentiler.
# Kullanım: DATA=<XDG_DATA_HOME (eklentili)> DEMO=<demo proje> tests/visual/capture.sh [sahne...]
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VIS="$REPO/tests/visual"
OUT="${OUT:-$REPO/docs/screenshots}"
FONTS="${FONTS:?Nerd Font sembol fontu dizini gerekli (SymbolsNerdFontMono-Regular.ttf)}"
DATA="${DATA:?eklentilerin kurulu olduğu XDG_DATA_HOME gerekli}"
DEMO="${DEMO:?demo proje dizini gerekli}"
WORK="$(mktemp -d)"
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

# start <sahne> <sütun> <satır> [config.lua içeriği] [komut]
start() {
  local name="$1" cols="$2" rows="$3" config="${4:-}" cmd="${5:-$REPO/bin/noctis}"
  tm kill-server 2>/dev/null || true
  local X="$WORK/$name"
  mkdir -p "$X/c/noctis" "$X/s/noctis/noctis" "$X/x"
  [ -n "$config" ] && printf '%s\n' "$config" > "$X/c/noctis/config.lua"
  # Rehber yalnız ilk açılış sahnesinde görünsün
  if [ "$name" != "01-dashboard" ]; then
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

# Demo projeyi bilinen başlangıç durumuna getir (önceden var olan kullanıcı
# düzenlemesi dahil), sahneler birbirini etkilemesin.
reset_demo() {
  (cd "$DEMO" && git checkout -q -- . && git clean -qfd \
    && sed -i 's/return f"{value:,.2f} {currency}"/return f"{value:,.2f} {currency}".replace(",", ".")/' app/utils.py)
}

FAKE_PROFILE="ai = { profiles = { test = { label = 'Test CLI', cmd = { '$REPO/tools/noctis-fake-ai' } } } }"

SCENES=("$@")
want() { [ ${#SCENES[@]} -eq 0 ] || [[ " ${SCENES[*]} " == *" $1 "* ]]; }
set --

if want 01-dashboard; then
  start 01-dashboard 120 35
  shot 01-dashboard
fi

if want 02-editor; then
  start 02-editor 120 35 "" "$REPO/bin/noctis app/main.py"
  keys " " "e"; sleep 0.8
  keys C-l; keys 18G; keys "w"
  shot 02-editor
fi

if want 03-palette; then
  start 03-palette 120 35 "" "$REPO/bin/noctis app/main.py"
  keys " " " "; sleep 0.5
  lit "ara"
  shot 03-palette
fi

if want 04-whichkey; then
  start 04-whichkey 120 35 "" "$REPO/bin/noctis app/main.py"
  tm send-keys -t main " "; sleep 1.2
  shot 04-whichkey
fi

if want 05-ai-workbench; then
  reset_demo
  start 05-ai-workbench 170 45 "return { $FAKE_PROFILE }" "$REPO/bin/noctis app/utils.py"
  keys " " "a" "n"; sleep 0.8
  lit "Test"; keys Enter; sleep 2.5
  lit "color"; keys Enter
  lit "replace app/utils.py .2f .1f"; keys Enter
  lit "write app/rapor.py def rapor():\\n    return 'hazır'\\n"; keys Enter
  sleep 1.5
  shot 05-ai-workbench
fi

if want 06-ai-changes; then
  # 05 ile aynı oturumdan devam eder (aralık değişiklikleri görünür)
  keys C-\\ e; sleep 0.4
  keys " " "a" "d"; sleep 1
  shot 06-ai-changes
fi

if want 07-diff-side; then
  keys Down Down Down Down; sleep 0.3
  tm send-keys -t main "/utils" Enter; sleep 0.4
  keys Enter; sleep 1.2
  shot 07-diff-side
fi

if want 08-diff-unified; then
  reset_demo
  start 08-diff-unified 100 32 "return { $FAKE_PROFILE }" "$REPO/bin/noctis app/utils.py"
  keys " " "a" "n"; sleep 0.8
  lit "Test"; keys Enter; sleep 2.5
  lit "replace app/utils.py .2f .1f"; keys Enter; sleep 1.5
  keys C-\\ e; sleep 0.4
  keys " " "a" "d"; sleep 1
  tm send-keys -t main "/utils" Enter; sleep 0.4
  keys Enter; sleep 1
  shot 08-diff-unified
fi

if want 09-small; then
  start 09-small 80 24 "" "$REPO/bin/noctis app/main.py"
  keys 12G
  shot 09-small
fi

if want 10-glacier; then
  start 10-glacier 120 35 "return { theme = 'glacier' }" "$REPO/bin/noctis app/main.py"
  keys " " "e"; sleep 0.8; keys C-l
  shot 10-glacier "#0a141b" "#d9e8f1"
fi

if want 11-amber; then
  start 11-amber 120 35 "return { theme = 'amber' }" "$REPO/bin/noctis app/main.py"
  keys " " "e"; sleep 0.8; keys C-l
  shot 11-amber "#14100b" "#ede3d3"
fi

if want 12-plain; then
  start 12-plain 100 30 "return { icons = false, borders = 'ascii' }" "$REPO/bin/noctis app/main.py"
  keys " " " "; sleep 0.5; lit "tema"
  shot 12-plain
fi

# Gezgindeki AI değişiklik işaretleri (A/M/D) ve Git durumları
if want 16-explorer-marks; then
  reset_demo
  start 16-explorer-marks 150 40 "return { $FAKE_PROFILE }" "$REPO/bin/noctis app/main.py"
  keys " " "a" "n"; sleep 0.8
  lit "Test"; keys Enter; sleep 2.5
  lit "replace app/utils.py .2f .1f"; keys Enter
  lit "write app/rapor.py x = 1\\n"; keys Enter
  lit "delete tests/test_main.py"; keys Enter; sleep 1.5
  keys C-\\ e; sleep 0.4
  keys " " "e"; sleep 1.5
  tm send-keys -t main ":redraw!" Enter; sleep 0.5
  shot 16-explorer-marks
  reset_demo
fi

# Gerçek Claude Code (kuruluysa): yalnız terminal uyumluluğu. Hiçbir prompt
# gönderilmez; ücretli bir görev başlatılmaz. Ctrl-C aracın kendisine gider.
if want 13-claude-code && command -v claude >/dev/null 2>&1; then
  reset_demo
  start 13-claude-code 160 45 "" "$REPO/bin/noctis app/main.py"
  keys " " "a" "n"; sleep 0.8
  lit "Claude"; keys Enter; sleep 7
  shot 13-claude-code
  tm resize-window -t main -x 120 -y 35; sleep 2
  shot 14-claude-code-resized
  tm send-keys -t main C-c; sleep 0.8; tm send-keys -t main C-c; sleep 2
  keys C-\\ e; sleep 0.4
  shot 15-claude-code-exit
  reset_demo
fi

echo "Bitti: $OUT"
