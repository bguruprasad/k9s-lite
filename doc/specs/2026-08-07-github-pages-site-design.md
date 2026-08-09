# k9s-lite GitHub Pages site - design

Date: 2026-08-07
Status: approved (design), not yet implemented

## Goal

A landing page for k9s-lite at `https://bguruprasad.github.io/k9s-lite/` whose
centrepiece is a browser-simulated k9s-lite terminal. A visitor should, within
about fifteen seconds and without installing anything, see the tool browsing a
cluster - and then be able to press keys themselves.

The README stays the canonical documentation. The page does the one job the
README cannot: be a link you send someone.

## Why a project site, not `k9s-lite.github.io`

`<name>.github.io` is reserved for accounts, not projects: the repo name must
match a GitHub user or org exactly. `k9s-lite.github.io` would require creating
an org literally named `k9s-lite` and moving the project under it.

Chosen instead: a **project site** served from the existing repo, at
`https://bguruprasad.github.io/k9s-lite/`. No new repo, no new org, no workflow,
no change to the read-only default workflow token. The site lives beside the
code and releases it points at.

If a shorter URL is ever wanted, a custom domain (`CNAME` in `docs/` plus a DNS
record) gets a better result than an org would, and can be added later without
reworking anything.

## Delivery

Source: branch `main`, folder `/docs`, set once in Settings -> Pages by the repo
owner. No GitHub Actions workflow.

```
docs/
  index.html      structure + content
  k9l.css         styling, light/dark
  k9l-demo.js     the simulated terminal
  .nojekyll       serve raw files, no Jekyll processing
  logo.svg        copied from assets/logo.svg
```

Constraints, matching the spirit of the project:

- **Self-contained.** No CDN, no external fonts, no analytics, no third-party
  scripts. The target audience sits behind corporate proxies; the page must
  serve from one origin.
- **No build step.** Hand-written HTML/CSS/JS, readable in the repo as shipped.
- **Not linted by CI.** shellcheck does not apply, and adding a JS toolchain to
  a zero-dependency repo cuts against the project's character. The site is not
  on the release path; a broken page cannot break the tool.

`docs/superpowers/specs/` (this file) is documentation, not part of the served
site. Jekyll is disabled and nothing links to it.

## Page structure

Single scrolling page, four blocks:

1. **Hero** - logo, one-line pitch ("A k9s-style terminal UI for Kubernetes in
   pure Bash + kubectl"), the three existing badges (CI, MIT, bash 3.2+). Short.
2. **The simulated terminal** - directly below, nothing competing with it.
3. **Install** - the version-pinned `curl` command in a copy-able block, plus
   the "curl blocked?" browser/PowerShell fallbacks. Deliberately more prominent
   than a typical landing page would make install, because proxy-blocked users
   are the actual target demographic.
4. **Footer** - links to README, releases, license. Thin.

Deliberately absent: key-map table, config reference, env-var list. Those stay
in the README so there is one place to update. The page's install snippet does
pin a version, which is one more place a version string appears; see Risks.

## The simulated terminal

An 80x24 character grid rendered as a `<pre>`, reproducing the real UI's
structure: header block (identity left, key map right, ASCII logo centred),
bordered table box, footer hint line.

### Values mirrored from source

Taken from the code so the simulation starts faithful:

| What | Source |
|------|--------|
| Header colors (yellow labels, bright-white values, blue keys, gray actions) | `k9s-lite.sh:72-76` |
| `k9l` ASCII logo + "k9s, but lite" tagline | `k9s-lite.sh:78-85` |
| Key map contents and layout | `k9s-lite.sh:144-152` |
| Row status colors | `lib/table.sh:110-119` |
| Box-drawing characters | `lib/table.sh:32-36` |
| Demo row shape (`demo-app-N`, READY/STATUS/RESTARTS/AGE) | `k9s-lite.sh:59-68` |

Row status colors, precisely: red for `CrashLoopBackOff`/`Error`/`Failed`/
`Evicted`/`ImagePull`, yellow for `Pending`/`ContainerCreating`/`Terminating`/
`Init:`/`Warning`, gray for `Completed`, green for `Running`, default otherwise.

### Column model

The real tool's central invariant is that `TABLE_HEADER` byte positions define
column boundaries and every row shares them. The simulation mirrors this: one
header string, fixed column starts, rows padded to match. It costs nothing and
makes the sort marker and filter behave as they do in the real tool.

The sort marker (`^`/`v`) is applied as a **draw-time overlay** on a pristine
header, never stored back - the same discipline as `table_mark_sort`, for the
same reason.

### Demo data

Starts from the shape of `K9L_DEMO=1` (`demo_data`, `k9s-lite.sh:59-68`) so a
visitor who runs `K9L_DEMO=1 k9l` afterwards sees continuity. Adjusted only
where the script needs it: one clearly-named `CrashLoopBackOff` pod with
readable log lines, and a spread of restart counts that makes the sort in Act 3
visibly reorder rows.

Context/cluster/user values match demo mode: `demo`, `demo-cluster`, `demo-user`.

### The script: three acts

Roughly 45 seconds total, with the core pitch landing in the first twelve so a
visitor who leaves early still got the point.

- **Act 1 - breadth (~12s).** Open on pods, `:svc`, `:deploy`, back to `:po`.
  Establishes "this browses your whole cluster."
- **Act 2 - the workflow (~25s).** `/` filter to the failing pod, `j` onto it,
  `Enter` for detail, `l` for logs. The job people actually do: find the broken
  pod, read why. This is the act that earns the tool.
- **Act 3 - the punchline (~8s).** Back to the table, `o` sorts by RESTARTS, the
  `^` marker appears, the crashlooper jumps to the top.

Then it **idles** with a visible cue inviting takeover - it does not loop.
Looping would talk over the invitation, which is the whole reason for building
an interactive demo rather than embedding a recording.

### Interaction

Wired keys: `j`/`k`, `:po`/`:svc`/`:deploy`, `/`, `Enter`, `l`, `o`, `Esc`, `q`.
Any wired keypress stops the script and hands control to the visitor.
Unwired keys are ignored silently. A visible "replay" control restarts the
script.

Two rules that matter more than they sound:

- **Focus is not stolen.** The demo captures keys only after the visitor clicks
  or tabs into it. Otherwise the page hijacks `/` and breaks browser
  find-in-page - a genuinely irritating bug on a landing page.
- **`prefers-reduced-motion` is respected.** Skip the animation, render the
  end state, leave it interactive.

## Scope boundary

This boundary is the drift control. The simulation reproduces:

- the pod/service/deployment table
- detail view and logs view (text in the box, scrollable)
- filter (`/`) and sort (`o`)

It does **not** reproduce: pickers (`n`, `c`), the resource browser (`a`),
command mode beyond the three wired resources, exec/edit/delete, config
handling, or the update check. Anything in flux stays out; everything wired has
been stable for many versions.

`k9l-demo.js` carries a header comment naming the source files it mirrors and
what to re-check when they change.

## Risks

**Drift is the real one, and it is not automatically detectable.** The
simulation is a second implementation of the UI. When a key changes or the
header gains a field, nothing fails - the demo quietly starts lying. CI cannot
catch this; shellcheck does not read JS, and pty smoke tests do not read the
website.

Mitigations, in order of usefulness: keep the scope narrow (above), keep the
mirrored values in one clearly-marked block at the top of `k9l-demo.js`, and
name the source files so the next person knows where to look. Accepted as a
known cost of an interactive demo.

**Version pinning.** The install snippet pins a release, so the page joins the
README as a place a version string lives. Release automation currently opens a
README pin-bump PR; the page's pin is not covered by it and will need bumping
by hand, or the automation extended. Flagged, not solved here.

## Out of scope

Live `--update` demonstration, fabricated cluster metrics, analytics, external
fonts or scripts, docs duplicated from the README, CI linting of the site.
