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
# Keys: j/k/arrows/wheel move · g/G top/bottom · : command (:po :svc :deploy ...)
#       / filter · n namespaces · c contexts · r refresh · 0 all-ns toggle · q quit
#       d describe · y yaml · l logs (follow) · p previous logs · s shell
#       e edit · Ctrl-D delete (asks to confirm)

set -u

K9L_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$K9L_ROOT/lib/term.sh"
source "$K9L_ROOT/lib/table.sh"
source "$K9L_ROOT/lib/kube.sh"
source "$K9L_ROOT/lib/actions.sh"

REFRESH_SECS="${K9L_REFRESH:-2}"
RUNNING=1
MODE=table          # table | picker
PICKER_KIND=""      # ns | ctx
LAST_NS=""          # remembered across the all-namespaces toggle
FILTER=""
ARG_NS=""

usage() {
  sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
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

# fetch + filter + derive title/message; never crashes the loop on kubectl failure
refresh() {
  kube_fetch || true
  if [[ -n $FILTER && -z $KUBE_ERR && ${#TABLE_ROWS[@]} -gt 0 ]]; then
    local kept=() row
    shopt -s nocasematch
    for row in "${TABLE_ROWS[@]}"; do
      [[ $row == *"$FILTER"* ]] && kept+=("$row")
    done
    shopt -u nocasematch
    if (( ${#kept[@]} )); then TABLE_ROWS=("${kept[@]}"); else TABLE_ROWS=(); fi
  fi
  TABLE_TITLE="${CUR_CTX}  ns:${CUR_NS:-all}  ${RESOURCE}${FILTER:+  /$FILTER}"
  if [[ -n $KUBE_ERR ]]; then
    TABLE_MSG="ERROR: $KUBE_ERR"
  elif (( ${#TABLE_ROWS[@]} == 0 )); then
    TABLE_MSG="nothing to show in ns:${CUR_NS:-all}${FILTER:+ matching /$FILTER}"
  else
    TABLE_MSG=""
  fi
}

# --- line input on the footer row
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

# --- command mode: switch resource kind; kubectl validates, revert on error
cmd_mode() {
  prompt_input ":"
  local input=${REPLY_STR// /}
  case "$input" in
    "")                refresh; return ;;
    q|quit)            RUNNING=0; return ;;
    ns|namespaces|projects) open_ns_picker; return ;;
    ctx|contexts)      open_ctx_picker; return ;;
  esac
  local old=$RESOURCE
  RESOURCE=$input
  CURSOR=0; SCROLL=0
  refresh
  if [[ -n $KUBE_ERR ]]; then
    RESOURCE=$old   # keep previous view; error line stays visible
    TABLE_TITLE="${CUR_CTX}  ns:${CUR_NS:-all}  ${RESOURCE}${FILTER:+  /$FILTER}"
  fi
}

filter_mode() {
  prompt_input "/"
  FILTER=$REPLY_STR
  CURSOR=0; SCROLL=0
  refresh
}

# --- pickers (ns / ctx) — share the table view state
picker_enter() { # $1 kind  $2 title  $3 header  $4 current-value; TABLE_ROWS preset
  MODE=picker
  PICKER_KIND=$1
  TABLE_TITLE=$2
  TABLE_HEADER=$3
  TABLE_MSG=""
  TABLE_FOOT="Enter:select  i:type-name  Esc:cancel  j/k:move"
  CURSOR=0; SCROLL=0
  local i
  for i in "${!TABLE_ROWS[@]}"; do
    [[ ${TABLE_ROWS[i]} == "$4" ]] && CURSOR=$i
  done
}

open_ns_picker() {
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
  if (( ${#NS_LIST[@]} )); then TABLE_ROWS=("${NS_LIST[@]}"); else TABLE_ROWS=(); fi
  picker_enter ns "select namespace   (current: ${CUR_NS:-all})" NAMESPACE "$CUR_NS"
}

open_ctx_picker() {
  if ! kube_contexts; then
    TABLE_MSG="ERROR: $KUBE_ERR"
    return
  fi
  if (( ${#CTX_LIST[@]} )); then TABLE_ROWS=("${CTX_LIST[@]}"); else TABLE_ROWS=(); fi
  picker_enter ctx "select context   (current: $CUR_CTX)" CONTEXT "$CUR_CTX"
}

picker_apply() { # $1 selected value
  [[ -z $1 ]] && return
  case "$PICKER_KIND" in
    ns)  CUR_NS=$1 ;;
    ctx)
      if kube_use_context "$1"; then
        CUR_CTX=$1
        kube_ctx_namespace   # namespace follows the new context
      fi ;;
  esac
}

picker_close() {
  MODE=table
  PICKER_KIND=""
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
      (( ${#TABLE_ROWS[@]} > 0 )) && picker_apply "${TABLE_ROWS[CURSOR]}"
      picker_close ;;
    i)
      prompt_input "enter ${PICKER_KIND}: "
      picker_apply "$REPLY_STR"
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
    :)        cmd_mode ;;
    /)        filter_mode ;;
    r|R)      refresh ;;
    n)        open_ns_picker ;;
    c)        open_ctx_picker ;;
    d)        act_describe ;;
    y)        act_yaml ;;
    l)        act_logs ;;
    p)        act_logs_prev ;;
    s)        act_shell ;;
    e)        act_edit ;;
    $'\004')  act_delete ;;    # Ctrl-D
    ESC)      [[ -n $FILTER ]] && { FILTER=""; CURSOR=0; SCROLL=0; refresh; } ;;
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
