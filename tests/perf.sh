#!/usr/bin/env bash
# Açılış süresi ölçümü (gerçek TUI, tmux içinde 120x35).
# Ölçülen değer: Neovim --startuptime çıktısındaki "first screen update"
# (ilk ekranın çizildiği an, süreç başlangıcından itibaren ms).
#   soğuk: işletim sistemi sayfa önbelleği (root ise) ve Lua bytecode önbelleği boş
#   sıcak: ardışık çalıştırmaların medyanı
# Kurulum süresi (noctis --setup) bu ölçüme dahil değildir.
# Kullanım: DATA=<eklentili XDG_DATA_HOME> tests/perf.sh [tekrar=10]
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA="${DATA:?eklentilerin kurulu olduğu XDG_DATA_HOME gerekli}"
RUNS="${1:-10}"
WORK="$(mktemp -d)"
SOCK="noctis-perf-$$"
trap 'tmux -L "$SOCK" kill-server 2>/dev/null || true; rm -rf "$WORK"' EXIT
printf 'set -g default-terminal "tmux-256color"\nset -g status off\n' > "$WORK/tmux.conf"

PROJ="$WORK/proje"
mkdir -p "$PROJ"
printf 'def main():\n    print("merhaba")\n' > "$PROJ/main.py"

measure() { # measure <etiket> <soğuk:0|1> <safe:0|1> [argümanlar...]
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
  # TUI istemcisi ve gömülü sunucu aynı dosyaya ayrı bloklar yazar;
  # ilk ekran ölçümü sunucu bloğundadır ("first screen update").
  for _ in $(seq 1 200); do
    if [ -f "$log" ] && grep -q "first screen update" "$log"; then break; fi
    sleep 0.05
  done
  tmux -L "$SOCK" kill-server 2>/dev/null || true
  sleep 0.2
  awk '/first screen update/ { v=$1 } END { if (v=="") print "NA"; else printf "%.1f\n", v }' "$log"
}

median() { sort -n | awk '{ a[NR]=$1 } END { if (NR%2) print a[(NR+1)/2]; else printf "%.1f\n", (a[NR/2]+a[NR/2+1])/2 }'; }

report() { # report <etiket> <safe> [argümanlar...]
  local label="$1" safe="$2"; shift 2
  local colds=() warms=()
  for _ in 1 2 3; do colds+=("$(measure "$label" 1 "$safe" "$@")"); done
  measure "$label" 0 "$safe" "$@" >/dev/null # önbelleği ısıt
  for _ in $(seq 1 "$RUNS"); do warms+=("$(measure "$label" 0 "$safe" "$@")"); done
  local cm wm wmin wmax
  cm="$(printf '%s\n' "${colds[@]}" | median)"
  wm="$(printf '%s\n' "${warms[@]}" | median)"
  wmin="$(printf '%s\n' "${warms[@]}" | sort -n | head -1)"
  wmax="$(printf '%s\n' "${warms[@]}" | sort -n | tail -1)"
  printf '| %-34s | %8s ms | %8s ms | %s–%s ms |\n' "$label" "$cm" "$wm" "$wmin" "$wmax"
}

echo "Makine: $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | xargs), $(nproc) çekirdek, $(free -h | awk '/Mem:/{print $2}') RAM"
echo "Neovim: $(nvim --version | head -1) · tekrar: $RUNS sıcak, 3 soğuk"
echo
echo "| Senaryo                            |   Soğuk (medyan) |   Sıcak (medyan) | Sıcak aralık |"
echo "| ---------------------------------- | ---------------- | ---------------- | ------------ |"
report "Başlangıç ekranı (argümansız)" 0
report "Python dosyası (main.py)" 0 main.py
report "Güvenli mod (--safe)" 1 main.py
