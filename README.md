<p align="center">
  <img src="assets/logo.svg" width="440" alt="k9l — k9s, but lite"/>
</p>

<p align="center">
  <a href="https://github.com/bguruprasad/k9s-lite/actions/workflows/ci.yml"><img src="https://github.com/bguruprasad/k9s-lite/actions/workflows/ci.yml/badge.svg" alt="CI"/></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT"/></a>
  <a href="#requirements"><img src="https://img.shields.io/badge/bash-3.2%2B-green.svg" alt="bash 3.2+"/></a>
</p>

# k9s-lite

A [k9s](https://k9scli.io/)-style terminal UI for Kubernetes in **pure Bash + kubectl**.
No Go binary, no tview/tcell, no jq — nothing to install. Built for locked-down
environments (corporate Windows machines with only Git Bash, jump hosts, minimal
containers) where the real k9s isn't available.

![k9s-lite browsing the demo namespace: colored pod table, k9s-style header with key map and logo](assets/k9l-screenshot.png)

## Quick start

Grab the single-file build from the [releases page](../../releases) and run it —
that one script is the entire program. Pin a specific version (recommended,
especially where you need to know exactly what you're running):

```sh
curl -LO https://github.com/bguruprasad/k9s-lite/releases/download/v0.9.4/k9s-lite.dist.sh
bash k9s-lite.dist.sh -n my-namespace
```

To always pull the newest release instead, use
`releases/latest/download/k9s-lite.dist.sh` (note GitHub's path shapes:
`latest/download/` vs `download/<tag>/`).

Make it feel like a real command:

```sh
mkdir -p ~/bin && mv k9s-lite.dist.sh ~/bin/k9l && chmod +x ~/bin/k9l
k9l -n my-namespace
```

No cluster handy? `K9L_DEMO=1 k9l` runs on built-in demo data.

### Requirements

- bash 3.2+ (macOS system bash works; Git Bash on Windows ships 5.x)
- `kubectl` (or `oc`) on PATH, configured with a kubeconfig
- On Windows/Git Bash: `winpty` for `exec`/`edit` (bundled with Git for Windows)

## Keys

Press `?` inside the app for this list, always up to date.

### Navigate

| Key | Action |
|-----|--------|
| `j`/`k`, arrows, mouse wheel | move cursor |
| `g` / `G`, PgUp / PgDn | top / bottom / page |
| `:` | command mode — switch resource: `:po` `:svc` `:deploy` `:sts` `:cm` `:secret` `:events` `:routes` … any kind or kubectl shortname |
| `a` | resource browser — pick from every kind the cluster supports (CRDs included) |
| `/` | filter rows (case-insensitive); `Esc` clears |
| `n` | namespace picker (typed entry if listing is Forbidden) |
| `c` | context picker (switches kubeconfig current-context) |
| `0` | toggle all-namespaces (needs cluster-wide list RBAC) |
| `?` / `r` / `q` | help / refresh now / quit |

### Inspect

| Key | Action |
|-----|--------|
| `Enter` | describe rendered inside the box — colorized, scrollable; `Esc` back |
| `d` | describe (plain, in pager) |
| `y` | YAML (pager) |
| `v` | events for the selected object, oldest→newest |
| `l` | logs, live follow in `less +F` — `Ctrl-C` stops following (scroll/search), `q` returns |
| `p` | previous-container logs (crash loops) |

### Operate

| Key | Action |
|-----|--------|
| `s` | shell into pod (bash if present, else sh) |
| `e` | `kubectl edit` |
| `Ctrl-D` | delete (asks for confirmation) |

## Options

One flag: `-n <ns>` / `--namespace <ns>`. The starting namespace resolves as:
flag → namespace set on your kubeconfig context → `default`. The view stays
locked to that one namespace unless you explicitly toggle `0` — by design,
since many users only have RBAC access to specific namespaces.

Environment variables:

| Variable | Default | Effect |
|----------|---------|--------|
| `K9L_KUBECTL` | `kubectl` | CLI to drive — set `oc` for OpenShift |
| `K9L_REFRESH` | `2` | auto-refresh interval in seconds (raise it on slow VPNs) |
| `K9L_DEMO` | unset | `1` = built-in demo data, no cluster needed |
| `K9L_ASCII` | unset | `1` = plain `+---+` borders for terminals without Unicode box drawing |

Both forms take the same flags and variables — the examples work identically
with `k9s-lite.sh` (repo checkout) and `k9s-lite.dist.sh` (single file).

## Why pure Bash?

- **Zero dependencies** beyond `bash`, `kubectl`, and the coreutils that ship
  with Git Bash / any Linux / macOS. kubectl does all parsing and auth —
  including corporate SSO/OIDC setups that are painful to reimplement.
- **RBAC-friendly**: designed for users who can only see specific namespaces.
  Nothing requires cluster-wide permissions; when listing namespaces is
  Forbidden, you type the namespace name instead.
- **OpenShift-aware**: with `K9L_KUBECTL=oc`, `:routes` works via API
  discovery and the namespace picker uses RBAC-filtered `projects`.

## How it works

kubectl is the parser: lists are `kubectl get -o wide`, discovery is implicit
(any resource kind kubectl knows works in `:` command mode — CRDs and OpenShift
routes included), and events are sorted server-side with `--sort-by`. The UI is
raw ANSI escapes with a full redraw per tick; the event loop is a single
`read -t <refresh>` — the timeout doubles as the polling timer.

Interactive actions (logs, exec, edit, pagers) suspend the alt screen, hand the
real terminal to the child, and restore raw mode after. Pager-based views
(describe, yaml, logs) leave no trace in your shell's scrollback; `s` (exec)
and `e` (edit) deliberately run on the normal screen so your session transcript
survives.

The layout is responsive: on wide terminals table columns stretch to fill the
screen, the key map right-aligns to the edge, and the ASCII logo appears in the
header; on narrow screens everything collapses gracefully. Colors follow k9s.

### Windows / Git Bash specifics

- Interactive kubectl (`exec -it`, `edit`) is wrapped with `winpty`
  automatically under mintty.
- All kubectl output is stripped of `\r`; the repo enforces LF endings.
- Terminal size is polled every tick (mintty doesn't deliver SIGWINCH to bash).
- No subshells in the render loop — process forks are expensive under Git Bash.

## Development

```sh
git clone https://github.com/bguruprasad/k9s-lite.git && cd k9s-lite
bash k9s-lite.sh
```

Local test cluster (kind on podman or docker):

```sh
kind create cluster --name k9s-lite          # KIND_EXPERIMENTAL_PROVIDER=podman if using podman
kubectl apply -f hack/sample-resources.yaml  # healthy/crashing/pending pods, jobs, services…
bash k9s-lite.sh -n demo
```

Tests (`hack/smoke.sh`) drive the real TUI in a pseudo-terminal via
`script(1)`, feed it key bytes, and assert on the rendered frames; CI runs
them on Ubuntu (bash 5) and macOS (bash 3.2), against both the repo layout
and the single-file build (`hack/build-dist.sh`, output in `dist/`,
gitignored) so the two forms can't drift apart.

## License

[MIT](LICENSE)
