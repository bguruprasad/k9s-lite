# actions.sh — operations on the selected row (describe, yaml, logs, exec, edit,
# delete). Interactive ones suspend the TUI, hand the real terminal to the child
# command, then restore raw mode and the alt screen.

# mintty is not a Windows console: interactive kubectl (exec -it, edit) needs winpty
WINPTY=""
case "$(uname -s)" in
  MINGW*|MSYS*) command -v winpty >/dev/null 2>&1 && WINPTY=winpty ;;
esac

tui_suspend() {
  printf '\e[?1006l\e[?1000l\e[0m\e[?25h\e[?1049l'
  stty sane 2>/dev/null || true
  trap : INT     # Ctrl-C stops the child (logs -f), not the app
}

tui_resume() {
  trap 'exit 130' INT
  stty -echo -icanon 2>/dev/null || true
  printf '\e[?1049h\e[?25l\e[2J\e[H\e[?1000h\e[?1006h'
}

run_pager() {
  tui_suspend
  if [[ ${TERM:-dumb} == dumb ]]; then
    # less can't drive a dumb terminal — print plainly and hold
    "$@" 2>&1
    printf '\n--- press any key ---'
    IFS= read -rsn1 _ || true
  else
    "$@" 2>&1 | less -R
  fi
  tui_resume
}
run_fg()    { tui_suspend; "$@"; tui_resume; }

# Resolve SEL_NS/SEL_NAME from the cursor row. In all-namespaces mode kubectl
# prepends a NAMESPACE column; otherwise the first column is the name.
sel_target() {
  SEL_NS=$CUR_NS
  SEL_NAME=""
  (( ${#TABLE_ROWS[@]} > 0 )) || return 1
  local f1 f2 rest
  read -r f1 f2 rest <<< "${TABLE_ROWS[CURSOR]}"
  if [[ -z $CUR_NS ]]; then
    SEL_NS=$f1
    SEL_NAME=$f2
  else
    SEL_NAME=$f1
  fi
  [[ -n $SEL_NAME ]]
}

act_guard() {
  if [[ -n ${K9L_DEMO:-} ]]; then
    TABLE_MSG="actions are disabled in demo mode"
    return 1
  fi
  sel_target
}

act_describe() {
  act_guard || return 0
  run_pager $KUBECTL_BIN describe "$RESOURCE" "$SEL_NAME" -n "$SEL_NS"
}

act_yaml() {
  act_guard || return 0
  run_pager $KUBECTL_BIN get "$RESOURCE" "$SEL_NAME" -n "$SEL_NS" -o yaml
}

# follow mode; Ctrl-C returns to the table. type/name form lets kubectl resolve
# workload kinds (deploy/x, job/x) to a pod for us.
act_logs() {
  act_guard || return 0
  tui_suspend
  echo "--- logs $RESOURCE/$SEL_NAME  (Ctrl-C to return) ---"
  $KUBECTL_BIN logs "$RESOURCE/$SEL_NAME" -n "$SEL_NS" --tail=200 -f
  tui_resume
}

act_logs_prev() {
  act_guard || return 0
  run_pager $KUBECTL_BIN logs "$RESOURCE/$SEL_NAME" -n "$SEL_NS" --tail=500 --previous
}

act_shell() {
  act_guard || return 0
  run_fg $WINPTY $KUBECTL_BIN exec -it -n "$SEL_NS" "$RESOURCE/$SEL_NAME" -- \
    sh -c 'command -v bash >/dev/null 2>&1 && exec bash || exec sh'
}

act_edit() {
  act_guard || return 0
  run_fg $WINPTY $KUBECTL_BIN edit "$RESOURCE/$SEL_NAME" -n "$SEL_NS"
}

# events for the selected object only, oldest first (newest at the bottom)
act_events() {
  act_guard || return 0
  run_pager $KUBECTL_BIN get events -n "$SEL_NS" \
    --field-selector "involvedObject.name=$SEL_NAME" \
    --sort-by=.metadata.creationTimestamp -o wide
}

act_delete() {
  act_guard || return 0
  prompt_input "delete ${RESOURCE}/${SEL_NAME} in ${SEL_NS}? type y to confirm: "
  case "$REPLY_STR" in
    y|Y|yes|YES)
      local out
      out=$($KUBECTL_BIN delete "$RESOURCE" "$SEL_NAME" -n "$SEL_NS" --wait=false 2>&1)
      out=${out//$'\r'/}
      refresh
      TABLE_MSG=${out%%$'\n'*}   # show delete result until the next tick
      ;;
  esac
}
