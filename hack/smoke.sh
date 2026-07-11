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

# Send the key sequence a few times with growing delay: on a cold pty the
# first burst can arrive before the pty is attached and get dropped.
feed() {
  local n
  for n in 1 2 3; do
    sleep "$n"
    printf 'jjj'     # move cursor 3 down
    sleep 1; printf '?'       # open help
    sleep 1; printf '\033'    # Esc back to table
    sleep 1; printf 'q'       # quit
  done
}

# K9L_CONFIG=/dev/null keeps the test hermetic - a developer's own
# ~/.k9s-lite.conf must not change what the assertions see
export K9L_DEMO=1 TERM=xterm-256color K9L_CONFIG=/dev/null

# One full pty session: launch, poll $OUT for the app's alt-screen-restore
# marker (the real proof our code ran), kill leftovers. Returns 0 when the
# marker appeared. Polling the file instead of waiting on script(1)'s exit
# sidesteps that wrapper's slow/odd teardown on some CI runners.
run_session() {
  local cap=$1 waited=0 run_pid
  : > "$OUT"
  (
    case "$(uname -s)" in
      Darwin) feed | script -q "$OUT" /bin/bash "$TARGET" ;;
      *)      feed | script -qec "bash $TARGET" "$OUT" ;;
    esac
  ) >/dev/null 2>&1 &
  run_pid=$!

  while (( waited < cap )); do
    if grep -qF $'\e[?1049l' "$OUT" 2>/dev/null; then
      echo "debug: clean-exit marker seen at ${waited}s"
      kill "$run_pid" 2>/dev/null
      wait "$run_pid" 2>/dev/null
      return 0
    fi
    if ! kill -0 "$run_pid" 2>/dev/null; then
      break   # wrapper exited on its own; final grep below decides
    fi
    (( waited % 5 == 0 )) && \
      echo "debug: t=${waited}s wrapper alive, \$OUT is $(wc -c < "$OUT" 2>/dev/null || echo 0) bytes"
    sleep 1; (( waited++ ))
  done
  kill "$run_pid" 2>/dev/null
  wait "$run_pid" 2>/dev/null
  grep -qF $'\e[?1049l' "$OUT" 2>/dev/null
}

# Observed on macos-latest GitHub runners: occasionally a pty session's stdin
# is dead for its entire lifetime - every keystroke burst is dropped and the
# app just idles on its refresh tick (output grows, cursor never moves).
# In-session re-feeding can't fix a dead pty; a FRESH pty session can.
# Three attempts with a fresh script(1) session each.
ATTEMPTS=3
ok=""
for a in $(seq 1 "$ATTEMPTS"); do
  echo "debug: pty session attempt $a/$ATTEMPTS"
  if run_session 40; then
    ok=1
    break
  fi
  echo "warn: attempt $a got no clean-exit marker (dead pty?); relaunching"
done

if [[ -z $ok ]]; then
  echo "FAIL: no attempt produced the clean-exit marker - partial output of last session:"
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
