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

# Hard wall-clock cap: BSD script(1) has been observed taking ~45s to tear
# down its pty session on macos-latest GitHub Actions runners even though the
# wrapped app exits in ~4s (not reproducible locally — runner-specific pty/IO
# teardown latency, not a hang in our code). Neither `timeout` nor `gtimeout`
# ships on stock macOS, so implement the cap in pure bash: launch the pipeline
# in a background subshell, race a sleep watchdog against it, kill whichever
# loses. What actually matters is the ASSERTIONS below, not how fast script(1)
# itself exits — so poll $OUT for the app's own clean-exit marker instead of
# trusting the wrapper process's wall-clock teardown time.
CAP=90
: > "$OUT"
(
  case "$(uname -s)" in
    Darwin) feed | script -q "$OUT" /bin/bash "$TARGET" ;;
    *)      feed | script -qec "bash $TARGET" "$OUT" ;;
  esac
) >/dev/null 2>&1 &
run_pid=$!

( sleep "$CAP"; kill "$run_pid" 2>/dev/null ) &
watchdog_pid=$!

# Poll for the app's alt-screen-restore marker — the real signal that our
# code ran to completion — rather than waiting on script(1)'s own exit.
waited=0
while (( waited < CAP )); do
  grep -qF $'\e[?1049l' "$OUT" 2>/dev/null && break
  kill -0 "$run_pid" 2>/dev/null || break   # wrapper already exited
  sleep 1; (( waited++ ))
done

kill "$watchdog_pid" 2>/dev/null
wait "$watchdog_pid" 2>/dev/null
kill "$run_pid" 2>/dev/null   # done reading what we need; stop waiting on script(1)'s teardown
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
