#!/usr/bin/env bash
# k9s-lite — a k9s-style Kubernetes TUI in pure bash + kubectl.
# Designed for restricted environments: Windows Git Bash (mintty), Linux, macOS.
# No dependencies beyond bash 3.2+, kubectl, and standard coreutils.
#
# Usage:
#   bash k9s-lite.sh [-n|--namespace <ns>]
#     namespace resolution: --namespace arg > kubeconfig context namespace > "default"
#   K9L_DEMO=1 bash k9s-lite.sh   # built-in demo data, no cluster needed
#   K9L_KUBECTL=oc ...            # drive OpenShift's oc instead of kubectl
#
# Keys: j/k/arrows/wheel move · g/G top/bottom · r refresh · n namespaces
#       0 all-namespaces toggle · q quit

set -u

K9L_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$K9L_ROOT/lib/term.sh"
source "$K9L_ROOT/lib/table.sh"
source "$K9L_ROOT/lib/kube.sh"

REFRESH_SECS="${K9L_REFRESH:-2}"
RUNNING=1
MODE=table          # table | picker
LAST_NS=""          # remembered across the all-namespaces toggle
ARG_NS=""

usage() {
  sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
}

parse_args() {
  while (( $# )); do
    case "$1" in
      -n|--namespace)
        [[ -n ${2:-} ]] || { echo "error: $1 needs a value" >&2; exit 2; }
        ARG_NS=$2; shift 2 ;;
      --namespace=*) ARG_NS=${1#*=}; shift ;;
      -h|--help) usage; exit 0 ;;
      *) echo "unknown argument: $1 (try --help)" >&2; exit 2 ;;
    esac
  done
}

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

# --- line input on the footer row (for RBAC-restricted users who can't list ns)
prompt_input() {
  REPLY_STR=""
  printf '\e[%d;1H\e[0m\e[K%s' "$ROWS" "$1"
  printf '\e[?25h'
  stty echo icanon 2>/dev/null || true
  IFS= read -r REPLY_STR || REPLY_STR=""
  stty -echo -icanon 2>/dev/null || true
  printf '\e[?25l'
  REPLY_STR=${REPLY_STR//$'\r'/}
}

# --- namespace picker (reuses the table view state)
picker_open() {
  if ! kube_namespaces; then
    # namespace listing is often Forbidden with ns-scoped RBAC — type it instead
    prompt_input "can't list namespaces (${KUBE_ERR}) — enter namespace: "
    if [[ -n $REPLY_STR ]]; then
      CUR_NS=$REPLY_STR
      CURSOR=0; SCROLL=0
    fi
    refresh
    return
  fi
  MODE=picker
  TABLE_TITLE="select namespace   (current: ${CUR_NS:-all})"
  TABLE_HEADER="NAMESPACE"
  TABLE_MSG=""
  TABLE_FOOT="Enter:select  i:type-name  Esc:cancel  j/k:move"
  TABLE_ROWS=("${NS_LIST[@]}")
  CURSOR=0; SCROLL=0
  local i
  for i in "${!TABLE_ROWS[@]}"; do
    [[ ${TABLE_ROWS[i]} == "$CUR_NS" ]] && CURSOR=$i
  done
}

picker_close() {
  MODE=table
  TABLE_FOOT=""
  CURSOR=0; SCROLL=0
  refresh
}

dispatch_picker() {
  case "$1" in
    j|DOWN)     table_move 1 ;;
    k|UP)       table_move -1 ;;
    g|HOME)     table_top ;;
    G|END)      table_bottom ;;
    WHEEL_DOWN) table_move 3 ;;
    WHEEL_UP)   table_move -3 ;;
    ENTER)
      (( ${#TABLE_ROWS[@]} > 0 )) && CUR_NS="${TABLE_ROWS[CURSOR]}"
      picker_close ;;
    i)
      prompt_input "enter namespace: "
      [[ -n $REPLY_STR ]] && CUR_NS=$REPLY_STR
      picker_close ;;
    q|Q|ESC)    picker_close ;;
  esac
}

dispatch() {
  if [[ $MODE == picker ]]; then
    dispatch_picker "$1"
    return
  fi
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
    n)        picker_open ;;
    0)        # explicit all-namespaces toggle (needs cluster-wide list RBAC)
      if [[ -n $CUR_NS ]]; then LAST_NS=$CUR_NS; CUR_NS=""; else CUR_NS=${LAST_NS:-default}; fi
      CURSOR=0; SCROLL=0
      refresh ;;
  esac
}

main() {
  parse_args "$@"
  term_init
  kube_init
  if [[ -n $ARG_NS ]]; then
    CUR_NS=$ARG_NS
  elif [[ -n ${K9L_DEMO:-} ]]; then
    CUR_NS=demo
  else
    kube_ctx_namespace
  fi
  refresh
  table_draw
  while (( RUNNING )); do
    if key_read "$REFRESH_SECS"; then
      dispatch "$KEY"
    elif [[ $MODE == table ]]; then
      refresh            # tick refresh only in table mode — don't clobber the picker
    fi
    term_update_size     # mintty resize isn't signalled; poll each pass
    table_draw
  done
}

main "$@"
