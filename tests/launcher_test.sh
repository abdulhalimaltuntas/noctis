#!/usr/bin/env bash
# Launcher argument passing tests. Instead of a real nvim, a fake "nvim" that
# writes its arguments out is used (NOCTIS_NVIM).
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
    fail=$((fail + 1)); echo "  ✗ $name — expected line: $expect"; sed 's/^/      /' "$ARGS_OUT"
  fi
}
check_not() {
  local name="$1" unexpected="$2"
  if grep -qxF -- "$unexpected" "$ARGS_OUT"; then
    fail=$((fail + 1)); echo "  ✗ $name — unexpected line: $unexpected"
  else
    pass=$((pass + 1)); echo "  ✓ $name"
  fi
}

echo "▸ Launcher argument passing"
mkdir -p "$TMP/project dir"
cd "$TMP/project dir"

"$L" "src/a b.py" >/dev/null
check "file name with spaces stays one argument" "ARG=[src/a b.py]"
check "working directory is kept" "CWD=$TMP/project dir"
check "NVIM_APPNAME is set" "APPNAME=noctis"
check "-u points at the app directory" "ARG=[$REPO/app/init.lua]"

"$L" +42 "ğüşiİöç.txt" >/dev/null
check "+line argument is passed" "ARG=[+42]"
check "non-ASCII file name (Turkish characters)" "ARG=[ğüşiİöç.txt]"

"$L" -- --doctor -dash.txt >/dev/null
check "--doctor after '--' is a file name" "ARG=[--doctor]"
check "dashed file after '--'" "ARG=[-dash.txt]"
check "'--' is passed through" "ARG=[--]"

"$L" --safe . >/dev/null
check "--safe becomes an environment variable" "SAFE=1"
check_not "--safe is not passed to Neovim" "ARG=[--safe]"
check "folder argument" "ARG=[.]"

NOCTIS_SAFE=1 "$L" x >/dev/null
check "NOCTIS_SAFE from the outer environment doesn't leak" "SAFE="

"$L" 'a;rm -rf x' '$(echo hi)' "it's" >/dev/null
check "shell metacharacters are not interpreted (1)" "ARG=[a;rm -rf x]"
check "shell metacharacters are not interpreted (2)" "ARG=[\$(echo hi)]"
check "single-quoted name" "ARG=[it's]"

NVIM_APPNAME=mine "$L" y >/dev/null
check "the user's NVIM_APPNAME is saved" "ORIG=set|mine"
env -u NVIM_APPNAME "$L" y >/dev/null
check "a missing NVIM_APPNAME is saved as 'unset'" "ORIG=|"

FAKE_EXIT=7 "$L" z >/dev/null; code=$?
if [ "$code" -eq 7 ]; then pass=$((pass + 1)); echo "  ✓ the editor's exit code is passed through (7)"; else fail=$((fail + 1)); echo "  ✗ exit code: $code"; fi

out="$("$L" --help)"; code=$?
if [ "$code" -eq 0 ] && grep -q -- "--doctor" <<<"$out"; then pass=$((pass + 1)); echo "  ✓ --help"; else fail=$((fail + 1)); echo "  ✗ --help"; fi
out="$("$L" --version)"
if grep -q "^NOCTIS " <<<"$out"; then pass=$((pass + 1)); echo "  ✓ --version"; else fail=$((fail + 1)); echo "  ✗ --version"; fi

NOCTIS_NVIM="$TMP/missing" "$L" a >/dev/null 2>"$TMP/err"; code=$?
if [ "$code" -eq 127 ] && grep -q "Neovim not found" "$TMP/err"; then pass=$((pass + 1)); echo "  ✓ missing Neovim gives a clear error (127)"; else fail=$((fail + 1)); echo "  ✗ missing Neovim: $code"; fi

cat > "$TMP/oldnvim" <<'EOF'
#!/usr/bin/env bash
echo "NVIM v0.9.5"
EOF
chmod +x "$TMP/oldnvim"
NOCTIS_NVIM="$TMP/oldnvim" "$L" a >/dev/null 2>"$TMP/err"; code=$?
if [ "$code" -eq 3 ] && grep -q "too old" "$TMP/err"; then pass=$((pass + 1)); echo "  ✓ old Neovim is rejected"; else fail=$((fail + 1)); echo "  ✗ old Neovim: $code"; fi

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
