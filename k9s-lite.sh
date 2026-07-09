#!/usr/bin/env bash
# k9s-lite — a k9s-style Kubernetes TUI in pure bash + kubectl.
# Designed for restricted environments: Windows Git Bash (mintty), Linux, macOS.
# No dependencies beyond bash 3.2+, kubectl, and standard coreutils.
#
# Usage:
#   bash k9s-lite.sh              # live view of current kubectl context
#   K9L_DEMO=1 bash k9s-lite.sh   # built-in demo data, no cluster needed
#   K9L_KUBECTL=oc ...            # drive OpenShift's oc instead of kubectl
#
# Keys: j/k/arrows/wheel move · g/G top/bottom · r refresh · 0 toggle namespace · q quit

set -u

K9L_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$K9L_ROOT/lib/term.sh"
source "$K9L_ROOT/lib/table.sh"
source "$K9L_ROOT/lib/kube.sh"

REFRESH_SECS="${K9L_REFRESH:-2}"
RUNNING=1

demo_data() {
  TABLE_HEADER="NAME                            READY   STATUS             RESTARTS   AGE"
  TABLE_ROWS=()
  local i line statuses=(Running Running Running Pending CrashLoopBackOff Completed Running ContainerCreating Error Running)
  for i in $(seq 1 30); do
    printf -v line '%-31s %-7s %-18s %-10s %s' \
      "demo-app-$i-7d4b9c$i" "1/1" "${statuses[i % 10]}" "$(( i % 5 ))" "${i}h"
    TABLE_ROWS+=("$line")
  done
}

# fetch + derive title/message; never crashes the loop on kubectl failure
refresh() {
  kube_fetch || true
  TABLE_TITLE="${CUR_CTX}  ns:${CUR_NS:-all}  ${RESOURCE}"
  if [[ -n $KUBE_ERR ]]; then
    TABLE_MSG="ERROR: $KUBE_ERR"
  elif (( ${#TABLE_ROWS[@]} == 0 )); then
    TABLE_MSG="no resources found in ns:${CUR_NS:-all}"
  else
    TABLE_MSG=""
  fi
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
    WHEEL_DOWN) table_move 3 ;;
    WHEEL_UP)   table_move -3 ;;
    r|R)      refresh ;;
    0)        # toggle all-namespaces <-> default
      if [[ -n $CUR_NS ]]; then CUR_NS=""; else CUR_NS="default"; fi
      refresh ;;
  esac
}

main() {
  term_init
  kube_init
  refresh
  table_draw
  while (( RUNNING )); do
    if key_read "$REFRESH_SECS"; then
      dispatch "$KEY"
    else
      refresh            # timeout == refresh tick
    fi
    term_update_size     # mintty resize isn't signalled; poll each pass
    table_draw
  done
}

main
