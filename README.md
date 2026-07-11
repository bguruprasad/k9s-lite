<p align="center">
  <img src="assets/logo.svg" width="440" alt="k9l - k9s, but lite"/>
</p>

<p align="center">
  <a href="https://github.com/bguruprasad/k9s-lite/actions/workflows/ci.yml"><img src="https://github.com/bguruprasad/k9s-lite/actions/workflows/ci.yml/badge.svg" alt="CI"/></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT"/></a>
  <a href="#requirements"><img src="https://img.shields.io/badge/bash-3.2%2B-green.svg" alt="bash 3.2+"/></a>
</p>

# k9s-lite

A [k9s](https://k9scli.io/)-style terminal UI for Kubernetes in **pure Bash + kubectl**.
No Go binary, no tview/tcell, no jq - nothing to install. Built for locked-down
environments (corporate Windows machines with only Git Bash, jump hosts, minimal
containers) where the real k9s isn't available.

![k9s-lite browsing the demo namespace: colored pod table, k9s-style header with key map and logo](assets/k9l-screenshot.png)

## Quick start

Grab the single-file build from the [releases page](../../releases) and run it -
that one script is the entire program. Pin a specific version (recommended,
especially where you need to know exactly what you're running):

```sh
curl -LO https://github.com/bguruprasad/k9s-lite/releases/download/v0.12.0/k9s-lite.dist.sh
bash k9s-lite.dist.sh -n my-namespace
```

To always pull the newest release instead, use
`releases/latest/download/k9s-lite.dist.sh` (note GitHub's path shapes:
`latest/download/` vs `download/<tag>/`).

**curl blocked?** Corporate proxies often let browsers through but not CLI
tools (curl in Git Bash doesn't use Windows' system proxy settings).
Alternatives, in order of least friction:

- Open the [releases page](../../releases) in your browser, download
  `k9s-lite.dist.sh` from the release assets, then `bash k9s-lite.dist.sh`.
- On Windows, PowerShell **does** use the system proxy:

  ```powershell
  Invoke-WebRequest -Uri https://github.com/bguruprasad/k9s-lite/releases/download/v0.12.0/k9s-lite.dist.sh -OutFile k9s-lite.dist.sh
  ```
- Or tell curl about your proxy explicitly:
  `curl -x http://your-proxy:8080 -LO <url>` (or set `https_proxy`).

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
| `:` | command mode - switch resource: `:po` `:svc` `:deploy` `:sts` `:cm` `:secret` `:events` `:routes` … any kind or kubectl shortname |
| `a` | resource browser - pick from every kind the cluster supports (CRDs included) |
| `/` | filter rows (case-insensitive); `Esc` clears |
| `n` | namespace picker (typed entry if listing is Forbidden) |
| `c` | context picker (switches kubeconfig current-context) |
| `o` / `O` | cycle sort column / flip direction - `^`/`v` marks the sorted header; numeric columns sort numerically |
| `0` | toggle all-namespaces (needs cluster-wide list RBAC) |
| `?` / `r` / `q` | help / refresh now / quit |

### Inspect

| Key | Action |
|-----|--------|
| `Enter` | describe rendered inside the box - colorized, scrollable; `Esc` back |
| `d` | describe (plain, in pager) |
| `y` | YAML (pager) |
| `v` | events for the selected object, oldest→newest |
| `l` | logs rendered inside the box (tail 500) - `f` toggles live follow, `r` reloads, `Esc` back |
| `p` | previous-container logs (crash loops) |
| `u` | route URL (OpenShift `:routes`) - shows `https://host/path`, copies to clipboard |

### Operate

| Key | Action |
|-----|--------|
| `s` | shell into pod (bash if present, else sh) |
| `e` | `kubectl edit` |
| `Ctrl-D` | delete (asks for confirmation) |

## Options

One flag: `-n <ns>` / `--namespace <ns>`. The starting namespace resolves as:
flag → `K9L_NAMESPACE` (env or config file) → namespace set on your kubeconfig
context → `default`. The view stays locked to that one namespace unless you
explicitly toggle `0` - by design, since many users only have RBAC access to
specific namespaces.

Environment variables:

| Variable | Default | Effect |
|----------|---------|--------|
| `K9L_KUBECTL` | `kubectl` | CLI to drive - set `oc` for OpenShift |
| `K9L_REFRESH` | `2` | auto-refresh interval in seconds (raise it on slow VPNs) |
| `K9L_NAMESPACE` | unset | starting namespace (same as `-n`, lower precedence) |
| `K9L_DEMO` | unset | `1` = built-in demo data, no cluster needed |
| `K9L_ASCII` | unset | `1` = plain `+---+` borders for terminals without Unicode box drawing |
| `K9L_HIDE_COLUMNS` | `NOMINATED NODE,READINESS GATES` | comma-separated header names to hide (kubectl `-o wide` extras that are almost always `<none>`); set empty to show everything |
| `K9L_CONFIG` | `~/.k9s-lite.conf` | path to the config file |

Both forms take the same flags and variables - the examples work identically
with `k9s-lite.sh` (repo checkout) and `k9s-lite.dist.sh` (single file).

### Config file

Put your defaults in `~/.k9s-lite.conf` so you don't retype them - plain
`key=value` lines, `#` comments allowed, parsed (never executed as code):

```ini
# ~/.k9s-lite.conf
kubectl=oc          # OpenShift shop
namespace=my-team   # where I always start
refresh=5           # corporate VPN is slow
```

Recognized keys: `refresh`, `namespace`, `kubectl`, `ascii`. Precedence:
CLI flag > environment variable > config file > built-in default.

## Why pure Bash?

- **Zero dependencies** beyond `bash`, `kubectl`, and the coreutils that ship
  with Git Bash / any Linux / macOS. kubectl does all parsing and auth -
  including corporate SSO/OIDC setups that are painful to reimplement.
- **RBAC-friendly**: designed for users who can only see specific namespaces.
  Nothing requires cluster-wide permissions; when listing namespaces is
  Forbidden, you type the namespace name instead.
- **OpenShift-aware**: with `K9L_KUBECTL=oc`, `:routes` works via API
  discovery, `u` on a route row gives you its full URL (TLS-aware, copied
  to your clipboard), and the namespace picker uses RBAC-filtered `projects`.

## How it works

kubectl is the parser: lists are `kubectl get -o wide`, discovery is implicit
(any resource kind kubectl knows works in `:` command mode - CRDs and OpenShift
routes included), and events are sorted server-side with `--sort-by`. The UI is
raw ANSI escapes with a full redraw per tick; the event loop is a single
`read -t <refresh>` - the timeout doubles as the polling timer.

Logs (`l`) render inside the box like the Enter describe view; follow mode is
polling-based - the refresh tick re-fetches the tail and pins the view to the
bottom, no background processes. Interactive actions (exec, edit, pagers)
suspend the alt screen, hand the real terminal to the child, and restore raw
mode after. Pager-based views (describe, yaml, previous logs) leave no trace
in your shell's scrollback; `s` (exec) and `e` (edit) deliberately run on the
normal screen so your session transcript survives.

The layout is responsive: on wide terminals table columns stretch to fill the
screen, the key map right-aligns to the edge, and the ASCII logo appears in the
header; on narrow screens everything collapses gracefully. Colors follow k9s.

### Windows / Git Bash specifics

- Interactive kubectl (`exec -it`, `edit`) is wrapped with `winpty`
  automatically under mintty.
- All kubectl output is stripped of `\r`; the repo enforces LF endings.
- Terminal size is polled every tick (mintty doesn't deliver SIGWINCH to bash).
- No subshells in the render loop - process forks are expensive under Git Bash.

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

## Contributing

Contributions are welcome via pull request. Note the model up front: **you
open PRs, the maintainer reviews and merges.** Contributors don't merge their
own work (and don't push to `main`) - every change lands through a PR that the
maintainer approves, so someone is always gatekeeping what goes into the repo.

The workflow:

1. **Fork** the repo and clone your fork.
2. **Branch** off `main`: `git checkout -b feat/short-name` (or `fix/...`).
3. **Make your change**, keeping the conventions below.
4. **Run the checks locally** before pushing:

   ```sh
   shellcheck -S warning k9s-lite.sh lib/*.sh hack/*.sh   # if you have shellcheck
   bash hack/smoke.sh                                     # runs the TUI in a pty
   bash hack/build-dist.sh && bash hack/smoke.sh dist/k9s-lite.dist.sh
   ```
5. **Open a pull request** against `main` from your fork, then stop there - the
   maintainer takes it from that point. Keep commits small and focused, and
   describe what you changed and why. CI (shellcheck + pty smoke on Ubuntu
   bash 5 and macOS bash 3.2, source and single-file build) must be green
   before it can be merged.
6. **Expect review feedback.** The maintainer reviews every PR, may ask for
   changes, and does the merge once it's approved and green. Opening a large or
   unsolicited PR? File an issue first to check the direction - it saves you
   rework.

### Conventions

These aren't style nits - they're the constraints that keep k9s-lite working
in the locked-down environments it targets:

- **bash 3.2 is the floor.** macOS ships it, and CI tests against it. No
  `${var^^}`, no associative arrays, no `mapfile`, nothing bash 4+ only.
- **No new dependencies.** `bash`, `kubectl`/`oc`, and coreutils only. No
  `jq`, no Python, nothing you'd have to install.
- **No subshells in the render loop.** Process forks are expensive under Git
  Bash; the draw path (`table_draw` and what it calls) uses pure parameter
  expansion, no `$(...)`. Forking once per refresh (e.g. the `kubectl` call or
  a single `sort`) is fine; forking per row is not.
- **Watch multibyte and escape bytes.** `printf` pads by bytes, so a stray tab,
  em dash, or ANSI sequence in content throws off the box-border width math.
  Strip or expand it (see how `open_detail`/`logs_load` handle tabs and colors).
- **Plain ASCII `-`, not em dashes**, in code, comments, strings, and docs.
- **Update the README and the in-app `?` help** in the same PR when you add or
  change a key binding, flag, or environment variable - the two must stay in
  sync.
- **Add or extend a smoke assertion** for user-visible behavior where it's
  practical, so it can't silently regress.

### Releases (maintainers)

Releases are automated. To cut one:

1. Bump `K9L_VERSION` in `k9s-lite.sh` and merge that to `main`.
2. Tag and push: `git tag v0.12.0 && git push origin v0.12.0`.

The [release workflow](.github/workflows/release.yml) then verifies the tag
matches `K9L_VERSION`, builds `dist/k9s-lite.dist.sh`, re-runs the smoke test,
and publishes a GitHub Release with that single file attached. It also opens a
small PR bumping the two versioned install URLs in this README to the new tag -
merge that PR (`gh pr merge --admin`) to finish. (The workflow opens a PR rather
than committing to `main` directly because `main` is protection-ruled and GitHub
doesn't allow the Actions token to bypass that on a personal repo.)

## License

[MIT](LICENSE)
