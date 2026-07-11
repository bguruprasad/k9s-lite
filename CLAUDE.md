# CLAUDE.md - k9s-lite

k9s-style Kubernetes TUI in pure bash 3.2+ + kubectl. Built for locked-down
environments (corporate Windows with only Git Bash, jump hosts). Public repo:
github.com/bguruprasad/k9s-lite, MIT. Also targets OpenShift (`K9L_KUBECTL=oc`).

## Hard constraints (violating these breaks real users)

- **bash 3.2 floor** (macOS system bash; CI tests it). No `${var^^}`, no
  associative arrays, no `mapfile`, nothing bash 4+.
- **Zero dependencies** beyond bash, kubectl/oc, coreutils.
- **No subshells/forks in the draw path** (`table_draw` + everything it calls) -
  forks are expensive under Git Bash. Pure parameter expansion only. One fork
  per refresh (kubectl, or the single `sort` in table_sort) is acceptable.
- **printf pads by BYTES.** Any multibyte char (em dash, Unicode arrow), tab,
  or ANSI escape inside table/detail content breaks the box-border width math.
  Strip ANSI (logs), expand tabs (describe), use ASCII markers (`^`/`v`).
- **All kubectl output is stripped of `\r`** (Windows CRLF); repo enforces LF.

## Architecture

Single event loop in `k9s-lite.sh` `main()`: `read -t $REFRESH_SECS` is both
key input and the refresh tick. Full redraw every tick, built as one string,
printed with a single write (no flicker). Alt screen; raw mode via lib/term.sh.

Files (source order matters - config.sh must be first):

- `k9s-lite.sh` - main loop, dispatch, refresh pipeline, header/info block,
  detail/logs/help views, pickers, command mode. `K9L_VERSION` lives here.
- `lib/config.sh` - parses `~/.k9s-lite.conf` (key=value, never executed).
- `lib/term.sh` - raw mode, alt screen, key decoding (incl. mouse wheel),
  size polling (mintty has no SIGWINCH).
- `lib/table.sh` - table state + rendering. The heart. See invariant below.
- `lib/kube.sh` - kubectl wrappers. `kube_fetch` fills TABLE_HEADER/TABLE_ROWS;
  **on error it KEEPS previous rows/header** and sets KUBE_ERR (UI shows the
  error line over stale data - deliberate).
- `lib/actions.sh` - describe/yaml/logs/exec/edit/delete on the selected row;
  winpty wrapping for interactive kubectl under mintty.
- `hack/smoke.sh` - pty end-to-end test (script(1)) + unit checks. Runs against
  both the repo layout and the dist build.
- `hack/build-dist.sh` - concatenates everything into dist/k9s-lite.dist.sh
  (gitignored; built by CI and the release workflow, never committed).

## The column-position invariant (most bugs live here)

`TABLE_HEADER` byte positions define column boundaries; every TABLE_ROWS line
shares them (kubectl tabwriter alignment). `table_columns` re-derives
COL_STARTS/COL_N from the header; `table_cell` slices a cell. ANY pass that
changes header length relative to rows desyncs every row slice (mangled
columns, lost colors).

Refresh pipeline order (k9s-lite.sh `refresh()`):

    kube_fetch -> table_hide_columns -> filter -> table_sort -> table_reflow

- `table_hide_columns` - cuts exact [start,next) regions (default hides
  NOMINATED NODE / READINESS GATES; K9L_HIDE_COLUMNS env). Idempotent.
- `table_sort` - rows only, NEVER touches the header. Numeric when every
  cell's leading space-delimited token is all digits (so RESTARTS `12 (3h ago)`
  sorts numerically; READY `1/1` and AGE `2h` stay lexical - AGE lexical sort
  is a documented limitation). One `sort(1)` fork, `\x01`-decorated keys.
- The `^`/`v` sort marker is a **draw-time overlay**: `table_mark_sort` builds
  MARKED_HEADER from the pristine TABLE_HEADER each frame; it must never be
  stored back into TABLE_HEADER (storing it caused marker accumulation on
  kubectl-error ticks, resize corruption, header/row desync - a whole family
  of bugs, fixed in PR #3).
- Sort state (SORT_COL, 1-based; 0=natural; SORT_DESC) resets on ANY column
  layout change: resource switch, namespace change (`ns_change`), context
  switch, all-ns `0` toggle (NAMESPACE column appears/disappears).

## MODE state machine

`MODE`: table | picker | detail. Detail view (DETAIL_VIEW=1) reuses TABLE_ROWS
as a text scroll buffer - no cursor bar, no reflow, cursor==scroll. DETAIL_KV
gates the cyan "Key:" colorization (describe/help yes; logs no - timestamps
contain colons). Logs view (LOGS_VIEW=1) polls on the tick when FOLLOW=1.
Detail views with empty TABLE_HEADER skip the header line entirely, and the
`[N]` row-count in the title is suppressed (it would be a line count).

## Conventions (repo-specific, enforced)

- **No em dashes anywhere** - plain `-` in code, comments, strings, docs,
  release titles.
- **No Co-Authored-By trailers** in commits; no generated-with footers in PRs.
- **Small commits as you go.**
- **All changes via branch + PR** - never commit to main directly. CI (lint +
  smoke x2) must be green before merge; merge needs `gh pr merge --admin`
  (solo repo, the 1-approval rule is unsatisfiable - admin bypass is the
  intended flow, but NEVER on red/pending checks).
- **Fresh-agent review on every PR before merge.**
- **README + in-app `?` help must stay in sync** with any key/flag/env change,
  in the same PR.
- User-visible behavior gets a smoke assertion where practical. Prefer unit
  checks (source lib, call function) over pty-frame scraping - pty timing
  flakes on slow macOS runners.

## Testing

    bash hack/smoke.sh                                   # repo layout
    bash hack/build-dist.sh && bash hack/smoke.sh dist/k9s-lite.dist.sh

Smoke drives the real TUI in a pty (script(1)), feeds key bytes, greps the
captured frames; 3 fresh-session retries (macOS runners sometimes have
dead-stdin ptys). Sort-marker correctness is a direct unit check, not a frame
grep. CI: .github/workflows/ci.yml on ubuntu (bash 5) + macos (bash 3.2).

## Releases (automated)

Bump `K9L_VERSION` -> merge to main -> `git tag vX.Y.Z && git push origin
vX.Y.Z`. release.yml verifies tag==K9L_VERSION, builds dist, smoke-tests it,
publishes the Release with k9s-lite.dist.sh attached, and opens a README
pin-bump PR (merge it to finish). Only the repo owner can create `v*` tags
(tag ruleset). Repo protections: rulesets `protect-main` (PR + review + green
CI required) and `protect-release-tags`; workflow tokens default read-only.

## Gitignored local files

`PLAN.md` (historical, purged from git history), `NOTES.md` (maintainer
runbook), `dist/` (build output). Never commit these.
