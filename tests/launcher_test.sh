#!/usr/bin/env bash
# Launcher argüman aktarımı testleri. Gerçek nvim yerine argümanları JSON
# olarak yazan sahte bir "nvim" kullanılır (NOCTIS_NVIM).
set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0

FAKE="$TMP/nvim"
cat > "$FAKE" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then echo "NVIM v0.12.4"; exit 0; fi
{
  printf 'CWD=%s\n' "$PWD"
  printf 'APPNAME=%s\n' "${NVIM_APPNAME:-}"
  printf 'SAFE=%s\n' "${NOCTIS_SAFE:-}"
  printf 'ORIG=%s|%s\n' "${NOCTIS_ORIG_NVIM_APPNAME+set}" "${NOCTIS_ORIG_NVIM_APPNAME:-}"
  for a in "$@"; do printf 'ARG=[%s]\n' "$a"; done
} > "$ARGS_OUT"
exit "${FAKE_EXIT:-0}"
EOF
chmod +x "$FAKE"
export NOCTIS_NVIM="$FAKE" ARGS_OUT="$TMP/out"
L="$REPO/bin/noctis"

check() {
  local name="$1" expect="$2"
  if grep -qxF -- "$expect" "$ARGS_OUT"; then
    pass=$((pass + 1)); echo "  ✓ $name"
  else
    fail=$((fail + 1)); echo "  ✗ $name — beklenen satır: $expect"; sed 's/^/      /' "$ARGS_OUT"
  fi
}
check_not() {
  local name="$1" unexpected="$2"
  if grep -qxF -- "$unexpected" "$ARGS_OUT"; then
    fail=$((fail + 1)); echo "  ✗ $name — beklenmeyen satır: $unexpected"
  else
    pass=$((pass + 1)); echo "  ✓ $name"
  fi
}

echo "▸ Launcher argüman aktarımı"
mkdir -p "$TMP/proje dizini"
cd "$TMP/proje dizini"

"$L" "src/a b.py" >/dev/null
check "boşluklu dosya adı tek argüman" "ARG=[src/a b.py]"
check "çalışma klasörü korunur" "CWD=$TMP/proje dizini"
check "NVIM_APPNAME ayarlanır" "APPNAME=noctis"
check "-u ile uygulama dizini" "ARG=[$REPO/app/init.lua]"

"$L" +42 "ğüşiİöç.txt" >/dev/null
check "+satır argümanı aktarılır" "ARG=[+42]"
check "Türkçe karakterli ad" "ARG=[ğüşiİöç.txt]"

"$L" -- --doctor -tire.txt >/dev/null
check "'--' sonrası --doctor dosya adıdır" "ARG=[--doctor]"
check "'--' sonrası tireli dosya" "ARG=[-tire.txt]"
check "'--' aktarılır" "ARG=[--]"

"$L" --safe . >/dev/null
check "--safe ortam değişkenine çevrilir" "SAFE=1"
check_not "--safe Neovim'e aktarılmaz" "ARG=[--safe]"
check "klasör argümanı" "ARG=[.]"

NOCTIS_SAFE=1 "$L" x >/dev/null
check "dış ortamdaki NOCTIS_SAFE sızmaz" "SAFE="

"$L" 'a;rm -rf x' '$(echo hi)' "it's" >/dev/null
check "kabuk metakarakterleri yorumlanmaz (1)" "ARG=[a;rm -rf x]"
check "kabuk metakarakterleri yorumlanmaz (2)" "ARG=[\$(echo hi)]"
check "tek tırnaklı ad" "ARG=[it's]"

NVIM_APPNAME=benim "$L" y >/dev/null
check "kullanıcının NVIM_APPNAME değeri saklanır" "ORIG=set|benim"
env -u NVIM_APPNAME "$L" y >/dev/null
check "NVIM_APPNAME yoksa 'yok' olarak saklanır" "ORIG=|"

FAKE_EXIT=7 "$L" z >/dev/null; code=$?
if [ "$code" -eq 7 ]; then pass=$((pass + 1)); echo "  ✓ editörün çıkış kodu iletilir (7)"; else fail=$((fail + 1)); echo "  ✗ çıkış kodu: $code"; fi

out="$("$L" --help)"; code=$?
if [ "$code" -eq 0 ] && grep -q -- "--doctor" <<<"$out"; then pass=$((pass + 1)); echo "  ✓ --help"; else fail=$((fail + 1)); echo "  ✗ --help"; fi
out="$("$L" --version)"
if grep -q "^NOCTIS " <<<"$out"; then pass=$((pass + 1)); echo "  ✓ --version"; else fail=$((fail + 1)); echo "  ✗ --version"; fi

NOCTIS_NVIM="$TMP/yok" "$L" a >/dev/null 2>"$TMP/err"; code=$?
if [ "$code" -eq 127 ] && grep -q "Neovim bulunamadı" "$TMP/err"; then pass=$((pass + 1)); echo "  ✓ eksik Neovim anlaşılır hata (127)"; else fail=$((fail + 1)); echo "  ✗ eksik Neovim: $code"; fi

cat > "$TMP/oldnvim" <<'EOF'
#!/usr/bin/env bash
echo "NVIM v0.9.5"
EOF
chmod +x "$TMP/oldnvim"
NOCTIS_NVIM="$TMP/oldnvim" "$L" a >/dev/null 2>"$TMP/err"; code=$?
if [ "$code" -eq 3 ] && grep -q "çok eski" "$TMP/err"; then pass=$((pass + 1)); echo "  ✓ eski Neovim reddedilir"; else fail=$((fail + 1)); echo "  ✗ eski Neovim: $code"; fi

echo
echo "$pass başarılı, $fail başarısız"
[ "$fail" -eq 0 ]
