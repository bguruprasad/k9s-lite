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

# Hard wall-clock cap: BSD script(1) can hang waiting on pty/tty setup on some
# CI runners (observed on macos-latest GitHub Actions images, no real tty on
# stdin). Neither `timeout` nor `gtimeout` ships on stock macOS, so implement
# the cap in pure bash: launch the pipeline in a background subshell, race a
# sleep watchdog against it, kill whichever loses. 45s (not 30s) gives a slow
# runner headroom — the feed itself only needs ~4s, so 45s is still a real cap,
# not a rubber stamp. One retry absorbs a single slow/flaky tick; a genuine
# hang fails the same way on both attempts.
run_once() {
  : > "$OUT"
  (
    case "$(uname -s)" in
      Darwin) feed | script -q "$OUT" /bin/bash "$TARGET" ;;
      *)      feed | script -qec "bash $TARGET" "$OUT" ;;
    esac
  ) >/dev/null 2>&1 &
  local run_pid=$!

  ( sleep 45; kill "$run_pid" 2>/dev/null ) &
  local watchdog_pid=$!

  local rc=0
  wait "$run_pid" 2>/dev/null || rc=$?
  kill "$watchdog_pid" 2>/dev/null
  wait "$watchdog_pid" 2>/dev/null
  return "$rc"
}

if ! run_once; then
  echo "warn: attempt 1 killed/errored after up to 45s (rc=$?) — retrying once"
  if ! run_once; then
    echo "FAIL: smoke test killed/errored on retry too (rc=$?, likely script/pty hang) — partial output:"
    cat "$OUT"
    exit 1
  fi
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
