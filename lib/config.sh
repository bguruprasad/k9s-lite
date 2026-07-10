# shellcheck shell=bash
# config.sh - optional config file: ~/.k9s-lite.conf (override path with
# K9L_CONFIG). Plain key=value lines, # comments allowed. Precedence:
# CLI flag > environment variable > config file > built-in default.
#
#   refresh=5        # seconds between auto-refreshes     (K9L_REFRESH)
#   namespace=dev    # starting namespace                 (K9L_NAMESPACE)
#   kubectl=oc       # CLI to drive, e.g. oc for OpenShift (K9L_KUBECTL)
#   ascii=1          # plain +---+ borders                (K9L_ASCII)
#
# This file MUST be sourced before the other lib files: kube.sh and table.sh
# read K9L_KUBECTL / K9L_ASCII at source time. The file is parsed, never
# sourced - a config file can't execute code.

K9L_CONFIG="${K9L_CONFIG:-$HOME/.k9s-lite.conf}"

k9l_load_config() {
  [[ -f $K9L_CONFIG ]] || return 0
  local line key val
  while IFS= read -r line || [[ -n $line ]]; do
    line=${line//$'\r'/}          # tolerate CRLF (file edited on Windows)
    line=${line%%#*}
    [[ $line == *=* ]] || continue
    key=${line%%=*}
    val=${line#*=}
    key="${key#"${key%%[![:space:]]*}"}"
    key="${key%"${key##*[![:space:]]}"}"
    val="${val#"${val%%[![:space:]]*}"}"
    val="${val%"${val##*[![:space:]]}"}"
    # tolerate quoted values: namespace="dev" means dev
    case "$val" in
      \"*\") val=${val#\"}; val=${val%\"} ;;
      \'*\') val=${val#\'}; val=${val%\'} ;;
    esac
    [[ -z $key || -z $val ]] && continue
    case "$key" in
      refresh)
        # positive integers only: 0 would busy-spin the event loop
        case "$val" in
          ''|*[!0-9]*|0*) ;;
          *) [[ -z ${K9L_REFRESH:-} ]] && K9L_REFRESH=$val ;;
        esac ;;
      namespace)
        [[ -z ${K9L_NAMESPACE:-} ]] && K9L_NAMESPACE=$val ;;
      kubectl)
        [[ -z ${K9L_KUBECTL:-} ]] && K9L_KUBECTL=$val ;;
      ascii)
        case "$val" in
          1|true|yes) [[ -z ${K9L_ASCII:-} ]] && K9L_ASCII=1 ;;
        esac ;;
    esac
  done < "$K9L_CONFIG"
  return 0
}

k9l_load_config
