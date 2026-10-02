#!/usr/bin/env bash
# Startup time measurement (real TUI, inside tmux at 120x35).
# Measured value: "first screen update" from Neovim's --startuptime output
# (when the first screen is drawn, in ms since process start).
#   cold: OS page cache (when root) and Lua bytecode cache empty
#   warm: median of consecutive runs
# Install time (noctis --setup) is not part of this measurement.
# Usage: DATA=<XDG_DATA_HOME with plugins> tests/perf.sh [runs=10]
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA="${DATA:?XDG_DATA_HOME with the plugins installed required}"
RUNS="${1:-10}"
WORK="$(mktemp -d)"
SOCK="noctis-perf-$$"
trap 'tmux -L "$SOCK" kill-server 2>/dev/null || true; rm -rf "$WORK"' EXIT
printf 'set -g default-terminal "tmux-256color"\nset -g status off\n' > "$WORK/tmux.conf"

PROJ="$WORK/project"
mkdir -p "$PROJ"
printf 'def main():\n    print("hello")\n' > "$PROJ/main.py"

measure() { # measure <label> <cold:0|1> <safe:0|1> [args...]
  local label="$1" cold="$2" safe="$3"; shift 3
  local X="$WORK/x-$label" log="$WORK/st.log"
  mkdir -p "$X/c" "$X/s/noctis/noctis"
  printf '{"onboarding_done":true}' > "$X/s/noctis/noctis/ui.json"
  if [ "$cold" = "1" ]; then
    rm -rf "$X/cache"
    sync
    (echo 3 > /proc/sys/vm/drop_caches) 2>/dev/null || true
  fi
  rm -f "$log"
  local envs=(-e "XDG_CONFIG_HOME=$X/c" -e "XDG_STATE_HOME=$X/s" -e "XDG_CACHE_HOME=$X/cache" -e "XDG_DATA_HOME=$DATA" -e "COLORTERM=truecolor")
  [ "$safe" = "1" ] && envs+=(-e "NOCTIS_SAFE=1")
  local launcher=("$REPO/bin/noctis")
  [ "$safe" = "1" ] && launcher+=("--safe")
  tmux -L "$SOCK" -f "$WORK/tmux.conf" new-session -d -s p -x 120 -y 35 -c "$PROJ" "${envs[@]}" \
    "${launcher[@]}" --startuptime "$log" "$@"
  # The TUI client and the embedded server write separate blocks to the same
  # file; the first-screen measurement is in the server block ("first screen update").
  for _ in $(seq 1 200); do
    if [ -f "$log" ] && grep -q "first screen update" "$log"; then break; fi
    sleep 0.05
  done
  tmux -L "$SOCK" kill-server 2>/dev/null || true
  sleep 0.2
  awk '/first screen update/ { v=$1 } END { if (v=="") print "NA"; else printf "%.1f\n", v }' "$log"
}

median() { sort -n | awk '{ a[NR]=$1 } END { if (NR%2) print a[(NR+1)/2]; else printf "%.1f\n", (a[NR/2]+a[NR/2+1])/2 }'; }

report() { # report <label> <safe> [args...]
  local label="$1" safe="$2"; shift 2
  local colds=() warms=()
  for _ in 1 2 3; do colds+=("$(measure "$label" 1 "$safe" "$@")"); done
  measure "$label" 0 "$safe" "$@" >/dev/null # warm up the cache
  for _ in $(seq 1 "$RUNS"); do warms+=("$(measure "$label" 0 "$safe" "$@")"); done
  local cm wm wmin wmax
  cm="$(printf '%s\n' "${colds[@]}" | median)"
  wm="$(printf '%s\n' "${warms[@]}" | median)"
  wmin="$(printf '%s\n' "${warms[@]}" | sort -n | head -1)"
  wmax="$(printf '%s\n' "${warms[@]}" | sort -n | tail -1)"
  printf '| %-34s | %8s ms | %8s ms | %s–%s ms |\n' "$label" "$cm" "$wm" "$wmin" "$wmax"
}

echo "Machine: $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | xargs), $(nproc) cores, $(free -h | awk '/Mem:/{print $2}') RAM"
echo "Neovim: $(nvim --version | head -1) · runs: $RUNS warm, 3 cold"
echo
echo "| Scenario                           |    Cold (median) |    Warm (median) |   Warm range |"
echo "| ---------------------------------- | ---------------- | ---------------- | ------------ |"
report "Dashboard (no arguments)" 0
report "Python file (main.py)" 0 main.py
report "Safe mode (--safe)" 1 main.py
