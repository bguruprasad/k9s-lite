#!/usr/bin/env bash
# Smoke test: drive the TUI in a pseudo-terminal with demo data (K9L_DEMO=1,
# no cluster needed) and assert on the rendered frames.
# Works with BSD script(1) (macOS, tests bash 3.2) and util-linux script (Linux).
set -u
cd "$(dirname "$0")/.." || exit 1

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
# sleep watchdog against it, kill whichever loses.
(
  case "$(uname -s)" in
    Darwin) feed | script -q "$OUT" /bin/bash k9s-lite.sh ;;
    *)      feed | script -qec "bash k9s-lite.sh" "$OUT" ;;
  esac
) >/dev/null 2>&1 &
run_pid=$!

( sleep 30; kill "$run_pid" 2>/dev/null ) &
watchdog_pid=$!

if wait "$run_pid" 2>/dev/null; then
  rc=0
else
  rc=$?
fi
kill "$watchdog_pid" 2>/dev/null
wait "$watchdog_pid" 2>/dev/null

if (( rc != 0 )); then
  echo "FAIL: smoke test killed/errored after up to 30s (rc=$rc, likely script/pty hang) — partial output:"
  cat "$OUT"
  exit 1
fi

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
