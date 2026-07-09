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

# Resolve namespace from the kubeconfig context (what `kubectl config set-context
# --current --namespace=X` sets); falls back to "default".
kube_ctx_namespace() {
  if [[ -n ${K9L_DEMO:-} ]]; then
    CUR_NS=demo
    return 0
  fi
  local ns
  ns=$($KUBECTL_BIN config view --minify -o 'jsonpath={..namespace}' 2>/dev/null) || ns=""
  ns=${ns//$'\r'/}
  [[ -z $ns ]] && ns=default
  CUR_NS=$ns
}

# All listable resource kinds into RES_LIST (cached per session — API discovery
# is a slow multi-request operation). Returns 1 + KUBE_ERR on failure.
RES_CACHE=""
kube_api_resources() {
  RES_LIST=()
  if [[ -n ${K9L_DEMO:-} ]]; then
    RES_LIST=(configmaps deployments pods secrets services statefulsets)
    return 0
  fi
  local out rc line
  if [[ -n $RES_CACHE ]]; then
    out=$RES_CACHE
  else
    out=$($KUBECTL_BIN api-resources --verbs=list --no-headers -o name 2>&1)
    rc=$?
    out=${out//$'\r'/}
    if (( rc != 0 )); then
      KUBE_ERR=${out%%$'\n'*}
      return 1
    fi
    RES_CACHE=$out
  fi
  while IFS= read -r line; do
    [[ -n $line ]] && RES_LIST+=("$line")
  done <<< "$out"
  return 0
}

# Cluster/user of the current context + server version, for the header block.
# Cached by the caller (refetched only on context switch); short timeout so a
# dead VPN doesn't hang startup.
kube_cluster_info() {
  CUR_CLUSTER="?"; CUR_USER="?"; K8S_VER="?"
  if [[ -n ${K9L_DEMO:-} ]]; then
    CUR_CLUSTER=demo-cluster; CUR_USER=demo-user; K8S_VER=demo
    return 0
  fi
  local out l1 l2
  out=$($KUBECTL_BIN config view --minify \
        -o 'jsonpath={.contexts[0].context.cluster}{"\n"}{.contexts[0].context.user}' 2>/dev/null)
  out=${out//$'\r'/}
  l1=${out%%$'\n'*}
  l2=${out#*$'\n'}
  [[ -n $l1 ]] && CUR_CLUSTER=$l1
  [[ -n $l2 && $l2 != "$out" ]] && CUR_USER=$l2
  out=$($KUBECTL_BIN version -o json --request-timeout=3 2>/dev/null \
        | sed -n 's/.*"gitVersion": *"\([^"]*\)".*/\1/p' | tail -1)
  out=${out//$'\r'/}
  [[ -n $out ]] && K8S_VER=$out
}

# List context names into CTX_LIST. Returns 1 + KUBE_ERR on failure.
kube_contexts() {
  CTX_LIST=()
  if [[ -n ${K9L_DEMO:-} ]]; then
    CTX_LIST=(demo demo-staging)
    return 0
  fi
  local out rc line
  out=$($KUBECTL_BIN config get-contexts -o name 2>&1)
  rc=$?
  out=${out//$'\r'/}
  if (( rc != 0 )); then
    KUBE_ERR=${out%%$'\n'*}
    return 1
  fi
  while IFS= read -r line; do
    [[ -n $line ]] && CTX_LIST+=("$line")
  done <<< "$out"
  return 0
}

# Switch the kubeconfig current-context (global, like kubectx — keeps every
# kubectl call consistent with the user's other terminals).
kube_use_context() {
  [[ -n ${K9L_DEMO:-} ]] && return 0
  $KUBECTL_BIN config use-context "$1" >/dev/null 2>&1
}

# List namespace names into NS_LIST. Returns 1 + KUBE_ERR on failure.
kube_namespaces() {
  NS_LIST=()
  if [[ -n ${K9L_DEMO:-} ]]; then
    NS_LIST=(default demo demo-batch kube-system)
    return 0
  fi
  local out rc line res=namespaces
  # under oc, projects list only what your RBAC lets you see; namespaces may be Forbidden
  case "${KUBECTL_BIN##*/}" in oc|oc.exe) res=projects ;; esac
  out=$($KUBECTL_BIN get "$res" --no-headers -o custom-columns=NAME:.metadata.name 2>&1)
  rc=$?
  out=${out//$'\r'/}
  if (( rc != 0 )); then
    KUBE_ERR=${out%%$'\n'*}
    return 1
  fi
  while IFS= read -r line; do
    line=${line%% *}
    [[ -n $line ]] && NS_LIST+=("$line")
  done <<< "$out"
  return 0
}

# Fetch RESOURCE into TABLE_HEADER/TABLE_ROWS.
# On failure: keep the previous rows on screen, set KUBE_ERR, return 1.
# Always strip \r — kubectl on Windows can emit CRLF.
kube_fetch() {
  if [[ -n ${K9L_DEMO:-} ]]; then
    demo_data
    return 0
  fi
  local out rc line first=1 sort_arg=""
  # events come back in random order by default — sort chronologically
  case "$RESOURCE" in
    events|event|ev|events.*) sort_arg=--sort-by=.metadata.creationTimestamp ;;
  esac
  if [[ -n $CUR_NS ]]; then
    out=$($KUBECTL_BIN get "$RESOURCE" -n "$CUR_NS" -o wide $sort_arg 2>&1)
  else
    out=$($KUBECTL_BIN get "$RESOURCE" --all-namespaces -o wide $sort_arg 2>&1)
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
