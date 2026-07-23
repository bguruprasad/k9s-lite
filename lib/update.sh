# shellcheck shell=bash
# update.sh - self-update mechanism.
#
# Two independent pieces:
#
#  1. A once-per-day BACKGROUND check (k9l_update_check_bg). Reads a cache
#     (~/.k9l/update, one line "YYYY-MM-DD vX.Y.Z"). If the cache is from today
#     it uses it and makes NO network call. Otherwise it forks a detached curl
#     (fallback wget) with a hard 3s timeout against the GitHub releases API and
#     writes today's date + the latest tag to the cache. The fork is detached so
#     a blocked/slow corporate proxy can never hang the UI; the fresh result is
#     picked up on the next launch. One fork, gated to once a day.
#
#  2. An on-demand SELF-UPDATE (k9l_self_update, from `--update`). Downloads the
#     latest dist to a temp file, verifies it (non-empty, `bash -n` parses,
#     carries a newer K9L_VERSION), then atomically mv's it over the running
#     file. Refuses in the multi-file repo layout (use git there). If curl/wget
#     is blocked it prints the browser/PowerShell fallback instead of failing.
#
# All of this is opt-out via K9L_NO_UPDATE_CHECK=1 (env or no_update_check=1 in
# the config file) for air-gapped/policy-locked sites.

K9L_REPO="${K9L_REPO:-bguruprasad/k9s-lite}"
K9L_UPDATE_CACHE="${K9L_UPDATE_CACHE:-$K9L_HOME/update}"
K9L_LATEST_TAG=""       # filled from the cache by k9l_update_check_bg (e.g. v0.13.0)

# k9l_today - today's date as YYYY-MM-DD into $K9L_TODAY. Prefers the bash
# builtin printf %(...)T (bash 4+, e.g. Git Bash on Windows - fork-free); falls
# back to date(1) on bash 3.2 (macOS system bash), whose printf lacks %(...)T.
# One fork at most, at startup, never in the draw path.
K9L_TODAY=""
k9l_today() {
  # bash 3.2's printf lacks %(...)T and UNSETS the target var on the bad format,
  # so read defensively with ${..:-} and re-normalize before using it.
  printf -v K9L_TODAY '%(%Y-%m-%d)T' -1 2>/dev/null
  K9L_TODAY=${K9L_TODAY:-}
  [[ -n $K9L_TODAY && $K9L_TODAY != *'%'* ]] && return 0
  K9L_TODAY=$(date +%Y-%m-%d 2>/dev/null) || K9L_TODAY=""
  [[ -n $K9L_TODAY ]]
}

# k9l_ver_gt <a> <b> - true (0) when dotted version a > b. Bash 3.2, no forks:
# splits on '.' via IFS and compares field by field numerically. Non-numeric or
# missing fields count as 0. Leading 'v' is stripped by the caller.
k9l_ver_gt() {
  local a=$1 b=$2 ai bi i
  local -a af bf
  IFS=. read -r -a af <<< "$a"
  IFS=. read -r -a bf <<< "$b"
  for (( i = 0; i < 3; i++ )); do
    ai=${af[i]:-0}; bi=${bf[i]:-0}
    [[ $ai == *[!0-9]* ]] && ai=0
    [[ $bi == *[!0-9]* ]] && bi=0
    (( ai > bi )) && return 0
    (( ai < bi )) && return 1
  done
  return 1     # equal -> not greater
}

# k9l_update_disabled - true when the daily check should not run at all
k9l_update_disabled() {
  [[ -n ${K9L_NO_UPDATE_CHECK:-} ]]
}

# k9l_fetcher - echo a command prefix that fetches a URL to stdout, honoring
# proxies, with a short timeout. Empty when neither curl nor wget is present.
K9L_FETCH=""
k9l_fetcher() {
  if [[ -n $K9L_FETCH ]]; then return 0; fi
  if command -v curl >/dev/null 2>&1; then
    K9L_FETCH="curl -fsSL --max-time"
  elif command -v wget >/dev/null 2>&1; then
    K9L_FETCH="wget -qO- --timeout"
  fi
  [[ -n $K9L_FETCH ]]
}

# k9l_cache_read - load today's cached tag into K9L_LATEST_TAG if the cache line
# is dated today; leaves it empty otherwise. Returns 0 if a fresh tag was loaded.
k9l_cache_read() {
  K9L_LATEST_TAG=""
  [[ -f $K9L_UPDATE_CACHE ]] || return 1
  local line date tag
  IFS= read -r line < "$K9L_UPDATE_CACHE" || return 1
  date=${line%% *}
  tag=${line#* }
  k9l_today || return 1
  [[ $date == "$K9L_TODAY" && -n $tag && $tag != "$date" ]] || return 1
  K9L_LATEST_TAG=$tag
  return 0
}

# k9l_update_check_bg - the daily background check (see file header). Safe to
# call unconditionally on startup: it no-ops when disabled, when the cache is
# already fresh, or when no fetcher is available.
k9l_update_check_bg() {
  k9l_update_disabled && return 0
  k9l_cache_read && return 0        # already checked today; K9L_LATEST_TAG set
  k9l_fetcher || return 0           # no curl/wget -> silent no-op
  local url="https://api.github.com/repos/$K9L_REPO/releases/latest"
  mkdir -p "$K9L_HOME" 2>/dev/null || return 0
  # Detached subshell: fetch, extract "tag_name": "vX.Y.Z", write cache. Any
  # failure leaves the cache untouched (stale-not-broken). Redirect everything
  # so a slow/blocked proxy is invisible to the UI. This is the one daily fork.
  (
    local out tag
    out=$($K9L_FETCH 3 "$url" 2>/dev/null) || exit 0
    tag=$(printf '%s\n' "$out" | grep -m1 '"tag_name"')
    tag=${tag#*: \"}; tag=${tag%%\"*}
    [[ -n $tag && $tag != *[!0-9v.]* ]] || exit 0
    k9l_today || exit 0
    printf '%s %s\n' "$K9L_TODAY" "$tag" > "$K9L_UPDATE_CACHE" 2>/dev/null
  ) >/dev/null 2>&1 &
  return 0
}

# k9l_update_available - true when a cached tag is newer than the running
# version. K9L_LATEST_TAG must already be populated (k9l_cache_read).
k9l_update_available() {
  [[ -n $K9L_LATEST_TAG ]] || return 1
  k9l_ver_gt "${K9L_LATEST_TAG#v}" "$K9L_VERSION"
}

# --- on-demand self update (--update) ---------------------------------------

# k9l_is_dist - true when the running file is the single-file dist build (it
# carries the sentinel below, stamped by hack/build-dist.sh), not a repo
# checkout. Self-replacing a git working tree would be surprising, so --update
# refuses there.
K9L_DIST_SENTINEL="#k9s-lite-dist-build-sentinel"
k9l_is_dist() {
  # in the dist, this lib is inlined into the one running file ($0). Anchor to
  # the start of a line so the bare marker matches but the K9L_DIST_SENTINEL=
  # assignment (which contains the same string mid-line) does not.
  [[ -f $0 ]] && grep -q "^$K9L_DIST_SENTINEL\$" "$0" 2>/dev/null
}

k9l_self_update() {
  if ! k9l_is_dist; then
    echo "k9s-lite: --update only works on the single-file build." >&2
    echo "You're running the repo checkout - update it with: git pull" >&2
    return 1
  fi
  local self=$0
  [[ -w $self ]] || { echo "k9s-lite: cannot write $self (permission denied)" >&2; return 1; }

  local dl="https://github.com/$K9L_REPO/releases/latest/download/k9s-lite.dist.sh"
  echo "Downloading the latest k9s-lite.dist.sh ..."
  if ! k9l_fetcher; then
    k9l_update_manual "$dl"; return 1
  fi
  local tmp
  tmp=$(mktemp "${TMPDIR:-/tmp}/k9l-update.XXXXXX") || {
    echo "k9s-lite: could not create a temp file" >&2; return 1
  }
  # shellcheck disable=SC2064
  trap "rm -f '$tmp'" RETURN

  if ! $K9L_FETCH 30 "$dl" > "$tmp" 2>/dev/null; then
    echo "Download failed (proxy or network?)." >&2
    k9l_update_manual "$dl"; return 1
  fi
  # verify before replacing the running program
  if [[ ! -s $tmp ]]; then
    echo "Downloaded file is empty - not replacing." >&2; return 1
  fi
  if ! bash -n "$tmp" 2>/dev/null; then
    echo "Downloaded file failed a syntax check - not replacing." >&2; return 1
  fi
  local newver line
  line=$(grep -m1 '^K9L_VERSION=' "$tmp") || line=""
  newver=${line#K9L_VERSION=}; newver=${newver//\"/}
  if [[ -z $newver || $newver == *[!0-9.]* ]]; then
    echo "Could not read a version from the download - not replacing." >&2; return 1
  fi
  if ! grep -q "^$K9L_DIST_SENTINEL\$" "$tmp"; then
    echo "Downloaded file is not a k9s-lite dist build - not replacing." >&2; return 1
  fi
  if [[ $newver == "$K9L_VERSION" ]]; then
    echo "Already up to date (v$K9L_VERSION)."; return 0
  fi
  if ! k9l_ver_gt "$newver" "$K9L_VERSION"; then
    echo "Latest release (v$newver) is not newer than v$K9L_VERSION - keeping current." ; return 0
  fi

  # atomic replace: preserve the exec bit, mv onto the same path
  chmod --reference="$self" "$tmp" 2>/dev/null || chmod +x "$tmp"
  if mv "$tmp" "$self" 2>/dev/null; then
    trap - RETURN
    echo "Updated k9s-lite: v$K9L_VERSION -> v$newver"
    echo "Restart k9l to run the new version."
    return 0
  fi
  # cross-filesystem mv can fail: fall back to cp then remove temp
  if cp "$tmp" "$self" 2>/dev/null; then
    echo "Updated k9s-lite: v$K9L_VERSION -> v$newver"
    echo "Restart k9l to run the new version."
    return 0
  fi
  echo "Could not replace $self." >&2
  k9l_update_manual "$dl"; return 1
}

# k9l_update_manual <download-url> - print the browser / PowerShell fallback
# for environments where curl is proxy-blocked (the common corporate case).
k9l_update_manual() {
  local dl=$1
  cat >&2 <<EOF

Automatic update was not possible. Get the latest build manually:

  1. Open in a browser:
       https://github.com/$K9L_REPO/releases/latest
     download k9s-lite.dist.sh and replace this file:
       $0

  2. Or, on Windows PowerShell (uses the system proxy):
       Invoke-WebRequest -Uri $dl -OutFile k9s-lite.dist.sh

  3. Or, if curl works with your proxy:
       curl -x http://your-proxy:8080 -LO $dl
EOF
}
