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
#       a resource browser (all api-resources) · / filter · n namespaces · c contexts
#       r refresh · 0 all-ns toggle · q quit
#       d describe · y yaml · v events for object · l logs (follow) · p previous logs
#       s shell · e edit · Ctrl-D delete (asks to confirm) · :events sorted event list

set -u

K9L_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$K9L_ROOT/lib/term.sh"
source "$K9L_ROOT/lib/table.sh"
source "$K9L_ROOT/lib/kube.sh"
source "$K9L_ROOT/lib/actions.sh"

K9L_VERSION="0.9.5"
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

# k9s-style header block: cluster identity on the left, key map on the right.
# Colors: yellow labels / white values; blue keys / gray actions.
C_LBL=$'\e[33m'
C_VAL=$'\e[1;97m'
C_KEY=$'\e[94m'
C_ACT=$'\e[90m'
C_RST=$'\e[0m'

K9L_LOGO=(
' _        ___     _ '
'| | __   / _ \   | |'
'| |/ /  | (_) |  | |'
'|   <    \__, |  | |'
'|_|\_\     /_/   |_|'
)
K9L_TAG="k9s, but lite"

# add_info_line <label> <value> [<key> <action>]...
# k9s layout: identity block left, key map right-aligned to the screen edge,
# ASCII logo centered when the gap fits it. Plain text is padded/measured
# first, colors wrapped after — printf field widths count escape bytes.
add_info_line() {
  local lab val s left_c right_c mid sp
  # narrow terminals: no room for the key map — identity block only, value
  # column shrunk to fit (keys stay discoverable via the footer)
  local valw=24
  if (( COLS < 80 )); then
    valw=$(( COLS - 12 ))
    (( valw < 6 )) && valw=6
  fi
  printf -v lab '%-9s' "$1"
  printf -v val '%-*.*s' "$valw" "$valw" "$2"
  left_c=" ${C_LBL}${lab}${C_RST} ${C_VAL}${val}${C_RST}"
  local left_w=$(( 2 + 9 + valw ))
  shift 2
  right_c=""
  local right_w=0
  if (( COLS >= 80 )); then
    while (( $# >= 2 )); do
      printf -v s '%-4s' "$1"
      right_c+="${C_KEY}${s}${C_RST} "
      printf -v s '%-9s' "$2"
      right_c+="${C_ACT}${s}${C_RST} "
      right_w=$(( right_w + 15 ))
      shift 2
    done
  fi
  if (( right_w == 0 )); then
    # no key map: no padding needed, \e[K clears the rest of the line
    INFO_LINES+=("$left_c")
    return
  fi
  mid=$(( COLS - left_w - right_w ))
  (( mid < 0 )) && mid=0
  local logo_w=${#K9L_LOGO[0]} line_i=${#INFO_LINES[@]} l r
  if (( mid >= logo_w + 4 && line_i < ${#K9L_LOGO[@]} )); then
    l=$(( (mid - logo_w) / 2 )); r=$(( mid - logo_w - l ))
    printf -v sp '%*s' "$l" ''
    left_c+="$sp${C_LBL}${K9L_LOGO[line_i]}${C_RST}"
    printf -v sp '%*s' "$r" ''
    left_c+="$sp"
    INFO_SHOW_TAG=1
  else
    printf -v sp '%*s' "$mid" ''
    left_c+="$sp"
  fi
  INFO_LINES+=("${left_c}${right_c}")
}

INFO_COLS=0
build_info() {
  INFO_LINES=()
  INFO_SHOW_TAG=0
  INFO_COLS=$COLS
  add_info_line "Context:" "$CUR_CTX"       "<d>"  "describe"  "<s>"  "shell"   "<:>" "resource"
  add_info_line "Cluster:" "$CUR_CLUSTER"   "<y>"  "yaml"      "<e>"  "edit"    "</>" "filter"
  add_info_line "User:"    "$CUR_USER"      "<v>"  "events"    "<^d>" "delete"  "<n>" "namespace"
  add_info_line "K9l Rev:" "v$K9L_VERSION"  "<l>"  "logs"      "<r>"  "refresh" "<c>" "context"
  add_info_line "K8s Rev:" "$K8S_VER"       "<p>"  "prev logs" "<a>"  "browse"  "<q>" "quit"
  if (( INFO_SHOW_TAG )); then
    # tagline centered under the logo (wide screens only)
    local logo_w=${#K9L_LOGO[0]} mid=$(( COLS - 35 - 45 )) sp pos
    pos=$(( 35 + (mid - logo_w) / 2 + (logo_w - ${#K9L_TAG}) / 2 ))
    (( pos < 0 )) && pos=0
    printf -v sp '%*s' "$pos" ''
    INFO_LINES+=("${sp}${C_ACT}${K9L_TAG}${C_RST}")
  fi
}

# k9s-style title: cyan resource, magenta (namespace [/filter]); the renderer
# appends the cyan [count]. TABLE_TITLE stays plain for width math.
set_title() {
  local ns="${CUR_NS:-all}${FILTER:+ /$FILTER}"
  TABLE_TITLE="${RESOURCE}(${ns})"
  TABLE_TITLE_C=$'\e[1;36m'"${RESOURCE}"$'\e[22;35m'"(${ns})"$'\e[0m'
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
  table_reflow
  set_title
  if [[ -n $KUBE_ERR ]]; then
    TABLE_MSG="ERROR: $KUBE_ERR"
  elif (( ${#TABLE_ROWS[@]} == 0 )); then
    TABLE_MSG="nothing to show in ns:${CUR_NS:-all}${FILTER:+ matching /$FILTER}"
  else
    TABLE_MSG=""
  fi
}

# --- line input on the footer row.
# Reads raw char-by-char (no termios mode flip: switching to canonical mode loses
# already-queued bytes on fast input/paste, and the leftovers fire as hotkeys).
prompt_input() {
  REPLY_STR=""
  local c
  printf '\e[%d;1H\e[0m\e[K%s' "$ROWS" "$1"
  printf '\e[?25h'
  while IFS= read -rsn1 c; do
    case "$c" in
      ''|$'\r'|$'\n') break ;;
      $'\177'|$'\b')
        if [[ -n $REPLY_STR ]]; then
          REPLY_STR=${REPLY_STR%?}
          printf '\b \b'
        fi ;;
      $'\e') REPLY_STR=""; break ;;   # Esc cancels
      *) REPLY_STR+="$c"; printf '%s' "$c" ;;
    esac
  done
  printf '\e[?25l'
}

# switch resource kind; kubectl validates, revert to previous view on error
switch_resource() {
  local old=$RESOURCE
  RESOURCE=$1
  CURSOR=0; SCROLL=0
  refresh
  if [[ -n $KUBE_ERR ]]; then
    RESOURCE=$old   # keep previous view; error line stays visible
    set_title
  fi
}

# --- command mode
cmd_mode() {
  prompt_input ":"
  local input=${REPLY_STR// /}
  case "$input" in
    "")                refresh; return ;;
    q|quit)            RUNNING=0; return ;;
    ns|namespaces|projects) open_ns_picker; return ;;
    ctx|contexts)      open_ctx_picker; return ;;
    res|api|aliases)   open_res_picker; return ;;
  esac
  switch_resource "$input"
}

filter_mode() {
  prompt_input "/"
  FILTER=$REPLY_STR
  CURSOR=0; SCROLL=0
  refresh
}

# --- detail view: Enter on a row renders colorized describe inside the box
SAVED_CURSOR=0
SAVED_SCROLL=0

open_detail() {
  act_guard || return 0
  local out line
  out=$($KUBECTL_BIN describe "$RESOURCE" "$SEL_NAME" -n "$SEL_NS" 2>&1)
  out=${out//$'\r'/}
  MODE=detail
  DETAIL_VIEW=1
  SAVED_CURSOR=$CURSOR
  SAVED_SCROLL=$SCROLL
  TABLE_TITLE="describe ${RESOURCE}/${SEL_NAME}"
  TABLE_TITLE_C=$'\e[1;36m'"describe "$'\e[22;35m'"${RESOURCE}/${SEL_NAME}"$'\e[0m'
  TABLE_HEADER="namespace: ${SEL_NS}"
  TABLE_MSG=""
  TABLE_FOOT="j/k:scroll  PgUp/PgDn  g/G:top/btm  q/Esc:back"
  TABLE_ROWS=()
  while IFS= read -r line; do
    TABLE_ROWS+=("$line")
  done <<< "$out"
  CURSOR=0; SCROLL=0
}

detail_close() {
  MODE=table
  DETAIL_VIEW=""
  TABLE_FOOT=""
  CURSOR=$SAVED_CURSOR
  SCROLL=$SAVED_SCROLL
  refresh
}

dispatch_detail() {
  case "$1" in
    j|DOWN)     table_move 1 ;;
    k|UP)       table_move -1 ;;
    g|HOME)     table_top ;;
    G|END)      table_bottom ;;
    PGDN)       table_move $(( ROWS - 4 )) ;;
    PGUP)       table_move $(( -(ROWS - 4) )) ;;
    WHEEL_DOWN) table_move 3 ;;
    WHEEL_UP)   table_move -3 ;;
    q|Q|ESC|ENTER) detail_close ;;
  esac
}

# --- help view: rides on the detail-view machinery ('Key:' prefixes render cyan)
open_help() {
  MODE=detail
  DETAIL_VIEW=1
  SAVED_CURSOR=$CURSOR
  SAVED_SCROLL=$SCROLL
  # TABLE_TITLE must match TABLE_TITLE_C's visible width — it drives the border math
  TABLE_TITLE="k9s-lite v$K9L_VERSION - key reference"
  TABLE_TITLE_C=$'\e[1;36m'"k9s-lite "$'\e[22;35m'"v$K9L_VERSION - key reference"$'\e[0m'
  TABLE_HEADER="k9s, but lite"
  TABLE_MSG=""
  TABLE_FOOT="j/k:scroll  q/Esc:back"
  TABLE_ROWS=(
    ""
    "View:"
    "  Enter:        describe rendered inside the box (scroll, Esc back)"
    "  d:            describe in pager"
    "  y:            yaml in pager"
    "  v:            events for the selected object"
    "  l:            logs, live follow in less +F (Ctrl-C to scroll/search)"
    "  p:            previous-container logs (crash loops)"
    "  u:            route URL (OpenShift :routes) — shows https://host/path, copies to clipboard"
    ""
    "Operate:"
    "  s:            shell into pod (bash, falls back to sh)"
    "  e:            kubectl edit"
    "  Ctrl-D:       delete, asks for confirmation"
    "  r:            refresh now (auto-refresh every ${REFRESH_SECS}s)"
    "  0:            toggle all-namespaces (needs cluster-wide RBAC)"
    ""
    "Navigate:"
    "  j / k / arrows / wheel / PgUp / PgDn / g / G"
    "  : (cmd):      switch resource - :po :svc :deploy :sts :events :routes ..."
    "  / (filter):   filter rows, case-insensitive; Esc clears"
    "  a:            browse every resource kind the cluster supports"
    "  n:            namespace picker (type a name if listing is forbidden)"
    "  c:            context picker"
    "  ?:            this help"
    "  q / Esc:      back / quit"
    ""
    "Environment:"
    "  K9L_KUBECTL=oc     drive OpenShift's oc instead of kubectl"
    "  K9L_REFRESH=5      refresh interval in seconds"
    "  K9L_NS via -n/--namespace flag at startup"
    "  K9L_DEMO=1         demo data, no cluster needed"
    "  K9L_ASCII=1        plain +--+ borders"
  )
  CURSOR=0; SCROLL=0
}

# --- pickers (ns / ctx) — share the table view state
picker_enter() { # $1 kind  $2 title  $3 header  $4 current-value; TABLE_ROWS preset
  MODE=picker
  PICKER_KIND=$1
  TABLE_TITLE=$2
  TABLE_TITLE_C=""     # pickers use the plain bold title
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

open_res_picker() {
  TABLE_MSG="discovering api resources..."
  table_draw
  if ! kube_api_resources; then
    TABLE_MSG="ERROR: $KUBE_ERR"
    return
  fi
  if (( ${#RES_LIST[@]} )); then TABLE_ROWS=("${RES_LIST[@]}"); else TABLE_ROWS=(); fi
  picker_enter res "select resource   (current: $RESOURCE)" RESOURCE "$RESOURCE"
}

open_ctx_picker() {
  if ! kube_contexts; then
    TABLE_MSG="ERROR: $KUBE_ERR"
    return
  fi
  if (( ${#CTX_LIST[@]} )); then TABLE_ROWS=("${CTX_LIST[@]}"); else TABLE_ROWS=(); fi
  picker_enter ctx "select context   (current: $CUR_CTX)" CONTEXT "$CUR_CTX"
}

PENDING_RES=""

picker_apply() { # $1 selected value
  [[ -z $1 ]] && return
  case "$PICKER_KIND" in
    ns)  CUR_NS=$1 ;;
    res) PENDING_RES=$1 ;;   # applied by picker_close so revert-on-error works
    ctx)
      if kube_use_context "$1"; then
        CUR_CTX=$1
        kube_ctx_namespace   # namespace follows the new context
        kube_cluster_info
        build_info
      fi ;;
  esac
}

picker_close() {
  MODE=table
  PICKER_KIND=""
  TABLE_FOOT=""
  CURSOR=0; SCROLL=0
  if [[ -n $PENDING_RES ]]; then
    local r=$PENDING_RES
    PENDING_RES=""
    switch_resource "$r"
  else
    refresh
  fi
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
  if [[ $MODE == detail ]]; then
    dispatch_detail "$1"
    return
  fi
  case "$1" in
    ENTER)    open_detail ;;
    \?)       open_help ;;
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
    a)        open_res_picker ;;
    d)        act_describe ;;
    y)        act_yaml ;;
    v)        act_events ;;
    l)        act_logs ;;
    p)        act_logs_prev ;;
    u)        act_route_url ;;
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
  kube_cluster_info
  build_info
  refresh
  table_draw
  while (( RUNNING )); do
    if key_read "$REFRESH_SECS"; then
      dispatch "$KEY"
    elif [[ $MODE == table ]]; then
      refresh            # tick refresh only in table mode — don't clobber the picker
    fi
    term_update_size     # mintty resize isn't signalled; poll each pass
    (( INFO_COLS != COLS )) && build_info
    table_draw
  done
}

main "$@"
