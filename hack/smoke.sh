#!/usr/bin/env bash
# Smoke test: drive the TUI in a pseudo-terminal with demo data (K9L_DEMO=1,
# no cluster needed) and assert on the rendered frames.
# Works with BSD script(1) (macOS, tests bash 3.2) and util-linux script (Linux).
#
# Usage: hack/smoke.sh [path-to-script]
#   Defaults to k9s-lite.sh (the multi-file dev version). Pass
#   dist/k9s-lite.dist.sh to run the exact same assertions against the
#   single-file build, so it can never silently drift from the real thing.
set -u
cd "$(dirname "$0")/.." || exit 1

TARGET=${1:-k9s-lite.sh}
[[ -f $TARGET ]] || { echo "FAIL: $TARGET not found"; exit 1; }

OUT=$(mktemp)
trap 'rm -f "$OUT"' EXIT

feed() {
  sleep 1; printf 'jjj'     # move cursor 3 down
  sleep 1; printf '?'       # open help
  sleep 1; printf '\033'    # Esc back to table
  sleep 1; printf 'q'       # quit
}

export K9L_DEMO=1 TERM=xterm-256color

# Poll $OUT for the app's own alt-screen-restore marker instead of waiting on
# script(1)'s process exit — measures our app's real behavior, not a wrapper
# process's teardown timing. This failed twice transiently on macos-latest
# runners early on (exactly at the timeout cap, each time); confirmed via the
# debug lines below that on a normal run the marker appears in 4-5s on every
# OS, so the transient failures were runner-fleet flakiness, not a real hang.
# Keep the debug logging — cheap, and decisive if it flakes again.
CAP=60
: > "$OUT"
start_ts=$(date +%s)
(
  case "$(uname -s)" in
    Darwin) feed | script -q "$OUT" /bin/bash "$TARGET" ;;
    *)      feed | script -qec "bash $TARGET" "$OUT" ;;
  esac
) >/dev/null 2>&1 &
run_pid=$!

waited=0
while (( waited < CAP )); do
  if grep -qF $'\e[?1049l' "$OUT" 2>/dev/null; then
    echo "debug: clean-exit marker seen at ${waited}s"
    break
  fi
  if ! kill -0 "$run_pid" 2>/dev/null; then
    echo "debug: wrapper process gone at ${waited}s, \$OUT is $(wc -c < "$OUT" 2>/dev/null || echo 0) bytes"
    break
  fi
  if (( waited % 5 == 0 )); then
    echo "debug: t=${waited}s wrapper alive, \$OUT is $(wc -c < "$OUT" 2>/dev/null || echo 0) bytes so far"
  fi
  sleep 1; (( waited++ ))
done
echo "debug: loop ended after $(( $(date +%s) - start_ts ))s wall clock, waited=${waited}s"

kill "$run_pid" 2>/dev/null
wait "$run_pid" 2>/dev/null

if (( waited >= CAP )) && ! grep -qF $'\e[?1049l' "$OUT" 2>/dev/null; then
  echo "FAIL: smoke test's clean-exit marker never appeared within ${CAP}s — partial output:"
  cat "$OUT"
  exit 1
fi

echo "--- target: $TARGET ---"
fail=0
check() {
  if grep -qF -- "$1" "$OUT"; then
    echo "ok:   $2"
  else
    echo "FAIL: $2 (pattern not found: $(printf '%q' "$1"))"
    fail=1
  fi
}

check 'demo-app-1-'          'table renders demo rows'
check '(demo)'               'title shows namespace'
check '>demo-app-4-'         'j moves the cursor'
check $'\e[107;30m'          'selection bar drawn'
check 'Context:'             'header identity block'
check 'key reference'        'help view opens on ?'
check $'\e[?1049l'           'alt screen restored on quit'

exit "$fail"
