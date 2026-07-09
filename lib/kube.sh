# kube.sh — all cluster access goes through here.
# K9L_KUBECTL=oc points every call at the OpenShift CLI instead.
# K9L_DEMO=1 skips the cluster entirely and uses built-in demo data.

KUBECTL_BIN="${K9L_KUBECTL:-kubectl}"
RESOURCE="pods"
CUR_NS=""          # empty = all namespaces
CUR_CTX="?"
KUBE_ERR=""

kube_init() {
  if [[ -n ${K9L_DEMO:-} ]]; then
    CUR_CTX="demo"
    return 0
  fi
  CUR_CTX=$($KUBECTL_BIN config current-context 2>/dev/null) || CUR_CTX="?"
  CUR_CTX=${CUR_CTX//$'\r'/}
  [[ -z $CUR_CTX ]] && CUR_CTX="?"
}

# Fetch RESOURCE into TABLE_HEADER/TABLE_ROWS.
# On failure: keep the previous rows on screen, set KUBE_ERR, return 1.
# Always strip \r — kubectl on Windows can emit CRLF.
kube_fetch() {
  if [[ -n ${K9L_DEMO:-} ]]; then
    demo_data
    return 0
  fi
  local out rc line first=1
  if [[ -n $CUR_NS ]]; then
    out=$($KUBECTL_BIN get "$RESOURCE" -n "$CUR_NS" -o wide 2>&1)
  else
    out=$($KUBECTL_BIN get "$RESOURCE" --all-namespaces -o wide 2>&1)
  fi
  rc=$?
  out=${out//$'\r'/}
  if (( rc != 0 )); then
    KUBE_ERR=${out%%$'\n'*}
    return 1
  fi
  KUBE_ERR=""
  TABLE_HEADER=""
  TABLE_ROWS=()
  while IFS= read -r line; do
    [[ -z $line ]] && continue
    if (( first )); then
      TABLE_HEADER=$line
      first=0
    else
      TABLE_ROWS+=("$line")
    fi
  done <<< "$out"
  return 0
}
