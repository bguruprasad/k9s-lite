#!/usr/bin/env bash
# k9s-lite — a k9s-style Kubernetes TUI in pure bash + kubectl.
# Designed for restricted environments: Windows Git Bash (mintty), Linux, macOS.
# No dependencies beyond bash 4+, kubectl, and standard coreutils.
#
# Usage: bash k9s-lite.sh        (q to quit)
# M0: terminal skeleton with demo data — proves rendering/keys work in your terminal.

set -u

K9L_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$K9L_ROOT/lib/term.sh"
source "$K9L_ROOT/lib/table.sh"

REFRESH_SECS="${K9L_REFRESH:-2}"
RUNNING=1

demo_data() {
  TABLE_TITLE="pods (demo data — M0)"
  TABLE_HEADER="NAME                            READY   STATUS             RESTARTS   AGE"
  TABLE_ROWS=()
  local i statuses=(Running Running Running Pending CrashLoopBackOff Completed Running ContainerCreating Error Running)
  for i in $(seq 1 30); do
    printf -v line '%-31s %-7s %-18s %-10s %s' \
      "demo-app-$i-7d4b9c$i" "1/1" "${statuses[i % 10]}" "$(( i % 5 ))" "${i}h"
    TABLE_ROWS+=("$line")
  done
}

dispatch() {
  case "$1" in
    q|Q)      RUNNING=0 ;;
    j|DOWN)   table_move 1 ;;
    k|UP)     table_move -1 ;;
    g|HOME)   table_top ;;
    G|END)    table_bottom ;;
    PGDN)     table_move $(( ROWS - 3 )) ;;
    PGUP)     table_move $(( -(ROWS - 3) )) ;;
  esac
}

main() {
  term_init
  demo_data
  table_draw
  while (( RUNNING )); do
    if key_read "$REFRESH_SECS"; then
      dispatch "$KEY"
    fi
    # tick or keypress either way: re-check size (mintty resize) and redraw
    term_update_size
    table_draw
  done
}

main
