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
  # Cursor/help/Esc are retried in 3 bursts because a cold pty can drop the
  # first burst. Sorting is NOT part of that loop: each 'o' press cycles the
  # sort column (NAME -> READY -> ...), so repeating it would move the marker
  # off NAME and the 'NAME ^' assertion would flake. Press 'o' exactly once,
  # after the bursts, and give the redraw a generous settle before quitting -
  # macOS runners are slow to flush the post-sort frame to the pty.
  for n in 1 2 3; do
    sleep "$n"
    printf 'jjj'     # move cursor 3 down
    sleep 1; printf '?'       # open help
    sleep 1; printf '\033'    # Esc back to table
    sleep 1; printf 'o'       # sort - just proves the keystroke doesn't crash
                              # the loop; marker correctness is unit-checked below
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

# Sort-marker correctness is asserted directly against table_mark_sort, not by
# scraping a late pty frame: on CPU-starved macOS runners the post-'o' redraw
# could fail to flush before quit, flaking 'NAME ^' even though the logic is
# fine. This unit check sources the lib and verifies the exact marker string -
# deterministic, and stronger. The pty session above still feeds 'o' to prove
# the keystroke path doesn't crash the loop.
check_sort_marker() {
  # Assert against the sort/marker logic in lib/table.sh directly. build-dist.sh
  # inlines this file verbatim, so the dist build shares the exact same code -
  # the pty session above already proves the dist boots, renders and exits; this
  # unit check proves the algorithm, with no pty-timing dependency. table.sh only
  # defines functions and sets a few defaults on source, so sourcing is safe.
  local out
  out=$(
    /bin/bash -c '
      source lib/table.sh >/dev/null 2>&1
      declare -f table_mark_sort >/dev/null || { echo "__NOFUNC__"; exit 0; }
      COLS=100
      TABLE_HEADER="NAME                            READY   STATUS             RESTARTS   AGE"
      TABLE_ROWS=("demo-app-1-x  1/1  Running  1  1h")
      SORT_COL=1; SORT_DESC=""; LAYOUT_COLS=0
      table_reflow
      table_mark_sort
      printf "%s" "$MARKED_HEADER"
    '
  )
  case "$out" in
    *"NAME ^"*) echo "ok:   table_mark_sort marks the sorted column (NAME ^)" ;;
    __NOFUNC__) echo "FAIL: table_mark_sort not found in lib/table.sh"; fail=1 ;;
    *) echo "FAIL: table_mark_sort (got: $out)"; fail=1 ;;
  esac
}
check_sort_marker

# Logs wrap + horizontal scroll (LOGS_VIEW). Same rationale as the sort marker:
# assert the width-math directly, no pty-timing dependency. COLS=22 -> inner=20
# (above the 10-col floor the renderer enforces); a 50-char line must split into
# ceil(50/20)=3 wrapped rows. Horizontal scroll must clamp to the widest line
# minus one (never scroll everything off-screen).
check_logs_wrap() {
  local out
  out=$(
    /bin/bash -c '
      source lib/table.sh >/dev/null 2>&1
      declare -f logs_wrap_build >/dev/null || { echo "__NOFUNC__"; exit 0; }
      COLS=22                                  # inner = COLS-2 = 20
      TABLE_ROWS=("$(printf "%050d" 0)")       # one 50-char line
      LOGS_VIEW=1
      logs_measure
      logs_wrap_build
      printf "maxlen=%s rows=%s" "$LOGS_MAXLEN" "${#LOGS_WRAP_ROWS[@]}"
    '
  )
  case "$out" in
    "maxlen=50 rows=3") echo "ok:   logs_wrap_build splits a 50-char line into 3 rows at width 20" ;;
    __NOFUNC__)         echo "FAIL: logs_wrap_build not found in lib/table.sh"; fail=1 ;;
    *)                  echo "FAIL: logs_wrap_build (got: $out)"; fail=1 ;;
  esac
}
check_logs_wrap

check_logs_hscroll() {
  local out
  out=$(
    /bin/bash -c '
      source lib/table.sh >/dev/null 2>&1
      declare -f logs_hscroll >/dev/null || { echo "__NOFUNC__"; exit 0; }
      COLS=10
      TABLE_ROWS=("$(printf "%030d" 0)")       # widest line = 30 chars
      LOGS_VIEW=1; LOGS_WRAP=""; LOGS_HSCROLL=0
      logs_measure
      logs_hscroll -8                          # cannot go below 0
      a=$LOGS_HSCROLL
      logs_hscroll 999                         # clamps to maxlen-1 = 29
      b=$LOGS_HSCROLL
      LOGS_WRAP=1; LOGS_HSCROLL=5
      logs_hscroll 8                           # no-op while wrapped
      c=$LOGS_HSCROLL
      printf "low=%s high=%s wrapped=%s" "$a" "$b" "$c"
    '
  )
  case "$out" in
    "low=0 high=29 wrapped=5") echo "ok:   logs_hscroll clamps to [0, maxlen-1] and is inert when wrapped" ;;
    __NOFUNC__)                echo "FAIL: logs_hscroll not found in lib/table.sh"; fail=1 ;;
    *)                         echo "FAIL: logs_hscroll (got: $out)"; fail=1 ;;
  esac
}
check_logs_hscroll

# Update mechanism: version compare, once-a-day cache freshness, and dist
# detection - all pure logic, unit-checked directly (no network, no pty). The
# background fetch and self-replace are not exercised here (they need network /
# a writable target); this asserts the decision logic that gates them.
check_update_logic() {
  local out
  out=$(
    /bin/bash -c '
      set -u
      K9L_VERSION="0.12.0"
      K9L_HOME="$(mktemp -d)"
      source lib/update.sh >/dev/null 2>&1
      declare -f k9l_ver_gt >/dev/null || { echo "__NOFUNC__"; exit 0; }
      r=""
      k9l_ver_gt 0.13.0 0.12.0 && r="${r}gt "        # newer
      k9l_ver_gt 0.12.0 0.12.0 || r="${r}eq "        # equal is not gt
      k9l_ver_gt 0.9.0 0.12.0   || r="${r}num "      # 9 < 12 numerically, not lexically
      K9L_UPDATE_CACHE="$K9L_HOME/update"
      k9l_today
      printf "%s v0.13.0\n" "$K9L_TODAY" > "$K9L_UPDATE_CACHE"
      k9l_cache_read && [ "$K9L_LATEST_TAG" = "v0.13.0" ] && r="${r}fresh "
      k9l_update_available && r="${r}avail "
      printf "2020-01-01 v0.13.0\n" > "$K9L_UPDATE_CACHE"; K9L_LATEST_TAG=""
      k9l_cache_read || r="${r}stale "                # yesterday ignored
      # poisoned cache: today-dated but tag carries an ANSI escape -> rejected
      # on read (the tag would otherwise corrupt the header box-width math)
      printf "%s \033[31mx\n" "$K9L_TODAY" > "$K9L_UPDATE_CACHE"; K9L_LATEST_TAG=""
      k9l_cache_read || r="${r}poison "
      rm -rf "$K9L_HOME"
      printf "%s" "$r"
    '
  )
  case "$out" in
    "gt eq num fresh avail stale poison ") echo "ok:   update logic (ver compare, daily cache, availability, tag sanitization)" ;;
    __NOFUNC__)                     echo "FAIL: update functions not found in lib/update.sh"; fail=1 ;;
    *)                              echo "FAIL: update logic (got: $out)"; fail=1 ;;
  esac
}
check_update_logic

exit "$fail"
