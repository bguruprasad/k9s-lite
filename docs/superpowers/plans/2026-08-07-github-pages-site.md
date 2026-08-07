# k9s-lite GitHub Pages Site Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a self-contained landing page at `docs/` (served by GitHub Pages
at `https://bguruprasad.github.io/k9s-lite/`) whose centerpiece is a
browser-simulated, interactive k9s-lite terminal.

**Architecture:** Static HTML/CSS/JS, no build step, no dependencies. `index.html`
holds structure and content; `k9l.css` holds theme/layout; `k9l-demo.js` holds a
self-contained terminal simulator (state machine + renderer) that scripts three
acts then hands control to the visitor via a small keymap dispatch table.

**Tech Stack:** Plain HTML5, CSS (custom properties for light/dark), vanilla
JS (ES2017, no modules/bundler - loaded via a single `<script defer>` tag).

## Global Constraints

- Self-contained: no CDN, no external fonts, no analytics, no third-party
  scripts. Single origin only.
- No build step: hand-written files, readable as shipped.
- Not linted by CI; not on the release path.
- No em dashes anywhere (plain `-`) - applies to all page copy, comments, commit
  messages.
- No Co-Authored-By trailers, no generated-with footers in commits or PRs.
- Small commits as you go.
- All changes via branch + PR, never direct to `main`. This work happens on
  the already-created branch `docs/github-pages-site`.
- Respect `prefers-reduced-motion`: skip animation, render end state.
- Demo must not steal keyboard focus until clicked/tabbed into (must not break
  browser find-in-page via `/`).
- Mirrored source values (colors, logo, key map, row-status rules, box-drawing
  chars, demo data shape) must match the exact values in `k9s-lite.sh` and
  `lib/table.sh` cited in each task - this is the drift-control contract from
  the design spec.

---

## File Structure

```
docs/
  index.html      # page structure + content (hero, terminal mount, install, footer)
  k9l.css         # theme (light/dark via prefers-color-scheme), layout, terminal chrome
  k9l-demo.js     # terminal simulator: render loop, script data, key dispatch
  logo.svg        # copy of assets/logo.svg
  .nojekyll       # empty file, disables Jekyll processing
```

Each file has one job: `index.html` never contains inline style or script
beyond the `<script defer src="k9l-demo.js">` tag; `k9l.css` never contains
terminal-content-generation logic; `k9l-demo.js` never touches page chrome
outside its own mount element.

---

## Task 1: Static page shell (hero, install, footer) with terminal mount point

**Files:**
- Create: `docs/index.html`
- Create: `docs/k9l.css`
- Create: `docs/.nojekyll`
- Create: `docs/logo.svg` (copy of `assets/logo.svg`)
- Test: manual, via `file://` in a browser (no test runner in this repo for
  static assets - see Testing Approach below)

**Interfaces:**
- Produces: a DOM element `<pre id="k9l-term" tabindex="0"></pre>` inside
  `<section id="demo">` that Task 2 mounts into, and a `<button id="k9l-replay">`
  that Task 2 wires up. Produces CSS custom properties (`--bg`, `--fg`,
  `--accent-cyan`, `--accent-yellow`, `--accent-pink`, `--accent-green`,
  `--accent-red`, `--accent-gray`) in `k9l.css` that Task 2's terminal
  renderer relies on for status colors.

This task has no unit tests (static markup); verification is a manual render
check, per the Testing Approach note below. Steps are still broken out
individually so each piece is reviewable on its own.

- [ ] **Step 1: Copy the logo asset**

```bash
cp /Users/guru/Work/k9s-clone/assets/logo.svg /Users/guru/Work/k9s-clone/docs/logo.svg
```

- [ ] **Step 2: Create `.nojekyll`**

```bash
touch /Users/guru/Work/k9s-clone/docs/.nojekyll
```

- [ ] **Step 3: Write `docs/k9l.css`**

Base theme derived from the logo's palette (`#171a26` background,
`#8be9fd`/`#f1fa8c`/`#ff79c6` accents) for visual continuity, with a light
variant via `prefers-color-scheme`. Terminal-specific color variables match
`lib/table.sh` row-status colors and `k9s-lite.sh` header colors (mapped from
ANSI to hex): yellow labels `#f1fa8c`, white values `#f8f8f2`, blue keys
`#8be9fd`, gray actions `#6272a4`; row status red `#ff5555` (CrashLoopBackOff/
Error/Failed/Evicted/ImagePull), yellow `#f1fa8c` (Pending/ContainerCreating/
Terminating/Init/Warning), gray `#6272a4` (Completed), green `#50fa7b`
(Running).

```css
:root {
  --bg: #171a26;
  --bg-alt: #22263a;
  --fg: #f8f8f2;
  --border: #2c3040;
  --accent-cyan: #8be9fd;
  --accent-yellow: #f1fa8c;
  --accent-pink: #ff79c6;
  --accent-green: #50fa7b;
  --accent-red: #ff5555;
  --accent-gray: #6272a4;
  --mono: Menlo, Consolas, "Liberation Mono", monospace;
}

@media (prefers-color-scheme: light) {
  :root {
    --bg: #f6f6f8;
    --bg-alt: #ffffff;
    --fg: #171a26;
    --border: #d7d9e2;
    --accent-gray: #6272a4;
  }
}

* { box-sizing: border-box; }

body {
  margin: 0;
  background: var(--bg);
  color: var(--fg);
  font-family: var(--mono);
  line-height: 1.5;
}

.wrap {
  max-width: 900px;
  margin: 0 auto;
  padding: 2rem 1.25rem 4rem;
}

.hero {
  text-align: center;
  padding: 2rem 0 1rem;
}

.hero img.logo {
  width: 280px;
  max-width: 80%;
  height: auto;
}

.hero p.tagline {
  font-size: 1.1rem;
  color: var(--accent-gray);
  margin: 0.5rem 0 1rem;
}

.badges img { margin: 0 0.15rem; }

#demo {
  margin: 2rem 0;
}

#k9l-term {
  background: #0d0e14;
  color: #eee;
  border: 1px solid var(--border);
  border-radius: 8px;
  padding: 0.75rem 1rem;
  overflow-x: auto;
  font-size: 0.82rem;
  line-height: 1.35;
  white-space: pre;
  outline: none;
}

#k9l-term:focus {
  border-color: var(--accent-cyan);
}

.demo-controls {
  display: flex;
  justify-content: flex-end;
  gap: 0.5rem;
  margin-top: 0.5rem;
}

.demo-controls button {
  font-family: var(--mono);
  background: var(--bg-alt);
  color: var(--fg);
  border: 1px solid var(--border);
  border-radius: 6px;
  padding: 0.35rem 0.8rem;
  cursor: pointer;
}

.demo-controls button:hover { border-color: var(--accent-cyan); }

.demo-hint {
  color: var(--accent-gray);
  font-size: 0.85rem;
  margin-top: 0.4rem;
}

section.install {
  margin: 3rem 0;
}

section.install h2 { margin-bottom: 0.5rem; }

pre.cmd {
  background: var(--bg-alt);
  border: 1px solid var(--border);
  border-radius: 8px;
  padding: 1rem;
  overflow-x: auto;
  position: relative;
}

pre.cmd button.copy {
  position: absolute;
  top: 0.5rem;
  right: 0.5rem;
  font-family: var(--mono);
  font-size: 0.75rem;
  background: var(--bg);
  color: var(--fg);
  border: 1px solid var(--border);
  border-radius: 4px;
  padding: 0.2rem 0.5rem;
  cursor: pointer;
}

details.fallback {
  margin-top: 1rem;
  color: var(--accent-gray);
}

details.fallback summary {
  cursor: pointer;
  color: var(--fg);
}

footer {
  margin-top: 4rem;
  padding-top: 1.5rem;
  border-top: 1px solid var(--border);
  text-align: center;
  color: var(--accent-gray);
  font-size: 0.85rem;
}

footer a { color: var(--accent-cyan); }

@media (max-width: 600px) {
  #k9l-term { font-size: 0.62rem; }
}
```

- [ ] **Step 4: Write `docs/index.html`**

Version pin note: this file hardcodes `v0.13.1` in the install command,
matching the current README pin. This is the version-pinning risk noted in
the design spec - not solved here, just kept consistent with the README at
time of writing.

```html
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>k9s-lite - k9s, but lite</title>
<meta name="description" content="A k9s-style terminal UI for Kubernetes in pure Bash + kubectl. No Go binary, nothing to install.">
<link rel="stylesheet" href="k9l.css">
</head>
<body>
<div class="wrap">

  <header class="hero">
    <img class="logo" src="logo.svg" alt="k9l - k9s, but lite">
    <p class="tagline">A k9s-style terminal UI for Kubernetes in pure Bash + kubectl.<br>
      No Go binary, no tview/tcell, no jq - nothing to install.</p>
    <p class="badges">
      <a href="https://github.com/bguruprasad/k9s-lite/actions/workflows/ci.yml"><img src="https://github.com/bguruprasad/k9s-lite/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
      <a href="https://github.com/bguruprasad/k9s-lite/blob/main/LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT"></a>
      <a href="https://github.com/bguruprasad/k9s-lite#requirements"><img src="https://img.shields.io/badge/bash-3.2%2B-green.svg" alt="bash 3.2+"></a>
    </p>
  </header>

  <section id="demo">
    <pre id="k9l-term" tabindex="0" aria-label="Interactive k9s-lite terminal demo"></pre>
    <div class="demo-controls">
      <button id="k9l-replay" type="button">Replay</button>
    </div>
    <p class="demo-hint">Click the terminal, then try <kbd>j</kbd>/<kbd>k</kbd>, <kbd>/</kbd> to filter, <kbd>o</kbd> to sort, or <kbd>:svc</kbd> to switch resources.</p>
  </section>

  <section class="install">
    <h2>Quick start</h2>
    <p>Grab the single-file build from the
      <a href="https://github.com/bguruprasad/k9s-lite/releases">releases page</a>
      and run it - that one script is the entire program.</p>
    <pre class="cmd"><button class="copy" type="button" data-copy-target="install-cmd">Copy</button><code id="install-cmd">curl -LO https://github.com/bguruprasad/k9s-lite/releases/download/v0.13.1/k9s-lite.dist.sh
bash k9s-lite.dist.sh -n my-namespace</code></pre>
    <p>No cluster handy? <code>K9L_DEMO=1 k9l</code> runs on built-in demo data -
      the same data this page's terminal is based on.</p>

    <details class="fallback">
      <summary>curl blocked?</summary>
      <p>Corporate proxies often let browsers through but not CLI tools. In order
        of least friction:</p>
      <ul>
        <li>Open the <a href="https://github.com/bguruprasad/k9s-lite/releases">releases page</a>
          in your browser and download <code>k9s-lite.dist.sh</code> directly.</li>
        <li>On Windows, PowerShell uses the system proxy:
          <pre class="cmd"><code>Invoke-WebRequest -Uri https://github.com/bguruprasad/k9s-lite/releases/download/v0.13.1/k9s-lite.dist.sh -OutFile k9s-lite.dist.sh</code></pre>
        </li>
        <li>Or tell curl about your proxy explicitly:
          <code>curl -x http://your-proxy:8080 -LO &lt;url&gt;</code></li>
      </ul>
    </details>
  </section>

  <footer>
    <p>
      <a href="https://github.com/bguruprasad/k9s-lite">README</a> ·
      <a href="https://github.com/bguruprasad/k9s-lite/releases">Releases</a> ·
      <a href="https://github.com/bguruprasad/k9s-lite/blob/main/LICENSE">MIT License</a>
    </p>
  </footer>

</div>
<script defer src="k9l-demo.js"></script>
</body>
</html>
```

- [ ] **Step 5: Manual render check**

Open `docs/index.html` directly in a browser (`file://` URL - no server
needed, no build step). Verify: logo renders, badges load (network required
for shields.io/GitHub badge images - acceptable, they're the same badges the
README already uses), install command block shows with a "Copy" button
(non-functional until Task 3), the empty `#k9l-term` box renders with dark
background and border. Confirm no console errors.

- [ ] **Step 6: Commit**

```bash
cd /Users/guru/Work/k9s-clone
git add docs/index.html docs/k9l.css docs/.nojekyll docs/logo.svg
git commit -m "docs: page shell for GitHub Pages site (hero, install, footer)"
```

---

## Task 2: Terminal renderer - static frame matching real k9s-lite layout

**Files:**
- Create: `docs/k9l-demo.js`
- Test: manual, via `file://` in a browser + a small inline assertion script
  (Step 4 below) run through the browser console, since there is no JS test
  runner in this repo and adding one would violate the no-build-step /
  zero-dependency constraint.

**Interfaces:**
- Consumes: `#k9l-term` element and CSS custom properties from Task 1.
- Produces: `K9L_DEMO` global object (or module-scope const if using an IIFE)
  exposing:
  - `K9L_DEMO.state` - the mutable render state object (shape defined below)
  - `K9L_DEMO.render(state)` - pure function, returns an HTML string for
    `#k9l-term.innerHTML`
  - `K9L_DEMO.buildHeader(state)` - returns the header block lines
  - `K9L_DEMO.buildTable(state)` - returns the bordered table block lines
  - `K9L_DEMO.rowColor(rowText)` - returns a CSS class name for a row's status
  - `K9L_DEMO.markSort(header, sortCol, sortDesc)` - returns header with `^`/`v`
    overlay, never mutates the input
  These names and signatures are consumed by Task 3 (script/act driver) and
  Task 4 (key dispatch), so they must match exactly.

This task builds the renderer and a static single frame (Act 1's first frame,
no animation yet) so the visual layout can be verified before adding
scripted movement.

- [ ] **Step 1: Define the state shape and demo data**

State shape (documented as a comment block at the top of the file, then
implemented):

```js
// State shape:
// {
//   ctx: 'demo', cluster: 'demo-cluster', user: 'demo-user',
//   resource: 'po',            // 'po' | 'svc' | 'deploy'
//   header: string,            // current TABLE_HEADER-equivalent
//   rows: string[],            // current TABLE_ROWS-equivalent
//   cursor: number,
//   scroll: number,
//   sortCol: number,           // 0 = natural, 1-based otherwise
//   sortDesc: boolean,
//   filter: string,            // '' = no filter
//   mode: 'table' | 'detail' | 'logs',
//   detailLines: string[],     // populated when mode !== 'table'
//   detailTitle: string,
// }
```

Mirrors (verbatim from source, cited per the design spec):
- Header colors: `k9s-lite.sh:72-76` -> yellow `#f1fa8c` labels, white
  `#f8f8f2` values, blue `#8be9fd` keys, gray `#6272a4` actions (already in
  `k9l.css` as CSS vars from Task 1).
- ASCII logo + tagline: `k9s-lite.sh:78-85`.
- Key map: `k9s-lite.sh:144-152`.
- Row status colors: `lib/table.sh:110-119`.
- Box-drawing characters: `lib/table.sh:32-36` (`┌ ┐ └ ┘ │ ─`).
- Demo row shape: `k9s-lite.sh:59-68`.

Write the file header comment and constants:

```js
// k9l-demo.js - simulated k9s-lite terminal for the landing page.
//
// This is a second implementation of the real TUI's rendering, scoped
// deliberately narrow. It mirrors (verbatim, as of the versions cited):
//   - Header colors, ASCII logo, key map: k9s-lite.sh:72-152
//   - Row status coloring, box-drawing chars: lib/table.sh:32-119
//   - Demo data shape: k9s-lite.sh:59-68
// If those change in the real tool in a way that's user-visible, re-check
// this file. Scope is intentionally limited to: pod/service/deployment
// table, detail view, logs view, filter (/), sort (o). Pickers, exec/edit/
// delete, the resource browser, config, and update checks are NOT simulated.

(function () {
  'use strict';

  var LOGO = [
    ' _        ___     _ ',
    '| | __   / _ \\   | |',
    '| |/ /  | (_) |  | |',
    '|   <    \\__, |  | |',
    '|_|\\_\\     /_/   |_|'
  ];
  var TAG = 'k9s, but lite';

  var BOX = { h: '─', v: '│', tl: '┌', tr: '┐', bl: '└', br: '┘' };

  var STATUSES_PO = ['Running', 'Running', 'Running', 'Pending', 'CrashLoopBackOff',
    'Completed', 'Running', 'ContainerCreating', 'Error', 'Running'];

  function padRight(s, w) {
    s = s == null ? '' : String(s);
    if (s.length >= w) return s.slice(0, w);
    return s + new Array(w - s.length + 1).join(' ');
  }

  function esc(s) {
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }

  function podHeader() {
    return 'NAME                            READY   STATUS             RESTARTS   AGE';
  }

  function podRows() {
    var rows = [];
    for (var i = 1; i <= 12; i++) {
      var name = 'demo-app-' + i + '-7d4b9c' + i;
      var status = STATUSES_PO[i % STATUSES_PO.length];
      var restarts = i % 5;
      var age = i + 'h';
      if (i === 5) { // the pod Act 2's script filters to and inspects
        name = 'checkout-worker-crashloop';
        status = 'CrashLoopBackOff';
        restarts = 14;
        age = '38m';
      }
      rows.push(
        padRight(name, 31) + ' ' +
        padRight('1/1', 7) + ' ' +
        padRight(status, 18) + ' ' +
        padRight(String(restarts), 10) + ' ' +
        age
      );
    }
    return rows;
  }

  function svcHeader() {
    return 'NAME             TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)     AGE';
  }

  function svcRows() {
    return [
      padRight('checkout', 16) + ' ' + padRight('ClusterIP', 11) + ' ' + padRight('10.96.12.4', 15) + ' ' + padRight('<none>', 13) + ' ' + padRight('80/TCP', 11) + '2d',
      padRight('demo-app', 16) + ' ' + padRight('ClusterIP', 11) + ' ' + padRight('10.96.8.190', 15) + ' ' + padRight('<none>', 13) + ' ' + padRight('8080/TCP', 11) + '5d'
    ];
  }

  function deployHeader() {
    return 'NAME             READY   UP-TO-DATE   AVAILABLE   AGE';
  }

  function deployRows() {
    return [
      padRight('checkout-worker', 16) + ' ' + padRight('1/1', 7) + ' ' + padRight('1', 12) + ' ' + padRight('1', 11) + '2d',
      padRight('demo-app', 16) + ' ' + padRight('1/1', 7) + ' ' + padRight('1', 12) + ' ' + padRight('1', 11) + '5d'
    ];
  }

  var RESOURCES = {
    po: { header: podHeader, rows: podRows, title: 'po(demo)' },
    svc: { header: svcHeader, rows: svcRows, title: 'svc(demo)' },
    deploy: { header: deployHeader, rows: deployRows, title: 'deploy(demo)' }
  };

  function rowColor(row) {
    if (/CrashLoopBackOff|Error|Failed|Evicted|ImagePull/.test(row)) return 'st-red';
    if (/Pending|ContainerCreating|Terminating|Init:|Warning/.test(row)) return 'st-yellow';
    if (/Completed/.test(row)) return 'st-gray';
    if (/Running/.test(row)) return 'st-green';
    return '';
  }

  function initialState() {
    return {
      ctx: 'demo', cluster: 'demo-cluster', user: 'demo-user',
      resource: 'po',
      header: podHeader(),
      rows: podRows(),
      cursor: 0,
      scroll: 0,
      sortCol: 0,
      sortDesc: false,
      filter: '',
      mode: 'table',
      detailLines: [],
      detailTitle: ''
    };
  }

  window.K9L_DEMO = window.K9L_DEMO || {};
  window.K9L_DEMO.state = initialState();
  window.K9L_DEMO.RESOURCES = RESOURCES;
  window.K9L_DEMO.rowColor = rowColor;
  window.K9L_DEMO.padRight = padRight;
  window.K9L_DEMO.esc = esc;
  window.K9L_DEMO.LOGO = LOGO;
  window.K9L_DEMO.TAG = TAG;
  window.K9L_DEMO.BOX = BOX;
})();
```

- [ ] **Step 2: Implement `markSort` (sort marker overlay, never mutates)**

Mirrors `table_mark_sort` (`lib/table.sh:257-286`): finds the column start
position from header spacing, inserts `^` or `v` without changing the header's
overall length relative to rows. This simplified port assumes 2+ space
column gaps (true for all three demo headers above) and targets the common
case of marking the last populated gap before the next column, matching the
same visual placement as the real renderer.

Append to `docs/k9l-demo.js`, inside the IIFE before the `window.K9L_DEMO = ...`
export block:

```js
  // columnStarts - byte offsets where each column begins, derived from
  // 2+-space gaps in the header (mirrors table_columns, lib/table.sh:126-...).
  function columnStarts(header) {
    var starts = [0];
    for (var i = 1; i < header.length; i++) {
      if (header[i] !== ' ' && header[i - 1] === ' ' && header[i - 2] === ' ') {
        starts.push(i);
      }
    }
    return starts;
  }

  // markSort - draw-time overlay only. Mirrors table_mark_sort (lib/table.sh:257-286):
  // never stores the marker back into the header state.
  function markSort(header, sortCol, sortDesc) {
    if (sortCol <= 0) return header;
    var starts = columnStarts(header);
    if (starts.length < 1) return header;
    var col = Math.min(sortCol, starts.length) - 1;
    var mark = sortDesc ? 'v' : '^';
    var start = starts[col];
    var next = col + 1 < starts.length ? starts[col + 1] : header.length;
    // cell text runs from start to the first double-space (or column end)
    var cellEnd = header.indexOf('  ', start);
    if (cellEnd === -1 || cellEnd > next) cellEnd = next;
    var pos = cellEnd;
    if (pos + 2 > next - 1) pos = Math.max(start, next - 3);
    return header.slice(0, pos) + ' ' + mark + header.slice(pos + 2);
  }
```

- [ ] **Step 3: Implement the renderer (`buildHeader`, `buildTable`, `render`)**

Mirrors the info block (`k9s-lite.sh:91-160`ish) and `table_draw`
(`lib/table.sh:368-494`): identity lines left, key map right, ASCII logo
centered; bordered box with title, column header, rows, footer hint.
Simplified to a fixed 80-column layout (the page always has room; the real
tool's narrow-terminal reflow at `COLS < 80` is out of scope per the design
spec's scope boundary).

Append to `docs/k9l-demo.js`:

```js
  var KEYMAP_LINES = [
    ['Context:', 'ctx', '<d>', 'describe', '<s>', 'shell', '<:>', 'resource'],
    ['Cluster:', 'cluster', '<y>', 'yaml', '<e>', 'edit', '</>', 'filter'],
    ['User:', 'user', '<v>', 'events', '<^d>', 'delete', '<n>', 'namespace'],
    ['K9l Rev:', null, '<l>', 'logs', '<r>', 'refresh', '<c>', 'context']
  ];

  function buildHeader(state) {
    var lines = [];
    KEYMAP_LINES.forEach(function (spec) {
      var label = spec[0];
      var val = spec[1] === 'ctx' ? state.ctx : spec[1] === 'cluster' ? state.cluster :
        spec[1] === 'user' ? state.user : 'v0.13.1 (demo)';
      var left = '<span class="hdr-lbl">' + padRight(label, 9) + '</span> ' +
        '<span class="hdr-val">' + padRight(val, 24) + '</span>';
      var right = '';
      for (var i = 2; i < spec.length; i += 2) {
        right += '<span class="hdr-key">' + padRight(spec[i], 5) + '</span>' +
          '<span class="hdr-act">' + padRight(spec[i + 1], 10) + '</span>';
      }
      lines.push(' ' + left + '  ' + right);
    });
    return lines;
  }

  function visibleRows(state) {
    if (!state.filter) return state.rows;
    var f = state.filter.toLowerCase();
    return state.rows.filter(function (r) { return r.toLowerCase().indexOf(f) !== -1; });
  }

  function buildTable(state) {
    var lines = [];
    var inner = 78;
    var rule = function (n) { return new Array(n + 1).join(BOX.h); };
    var rows = state.mode === 'table' ? visibleRows(state) : state.detailLines;
    var title = state.mode === 'table'
      ? ' ' + RESOURCES[state.resource].title + '[' + rows.length + '] '
      : ' ' + esc(state.detailTitle) + ' ';
    var left = Math.floor((inner - title.length) / 2);
    var right = inner - title.length - left;
    lines.push(BOX.tl + rule(left) + '<b>' + esc(title) + '</b>' + rule(right) + BOX.tr);

    if (state.mode === 'table') {
      var header = markSort(state.header, state.sortCol, state.sortDesc);
      lines.push(BOX.v + '<b>' + padRight(' ' + esc(header), inner) + '</b>' + BOX.v);
    }

    var bodyH = state.mode === 'table' ? 10 : 14;
    for (var i = state.scroll; i < state.scroll + bodyH; i++) {
      if (i < rows.length) {
        var row = rows[i];
        if (state.mode === 'table' && i === state.cursor) {
          lines.push(BOX.v + '<span class="row-cursor">' + padRight('>' + esc(row), inner) + '</span>' + BOX.v);
        } else {
          var cls = state.mode === 'table' ? rowColor(row) : '';
          lines.push(BOX.v + '<span class="' + cls + '">' + padRight(' ' + esc(row), inner) + '</span>' + BOX.v);
        }
      } else {
        lines.push(BOX.v + padRight('', inner) + BOX.v);
      }
    }
    lines.push(BOX.bl + rule(inner) + BOX.br);

    var footer = state.filter
      ? ' filter: ' + esc(state.filter) + '  Esc:clear-filter'
      : ' ?:help  o/O:sort  a:resources  r:refresh  0:all-ns  Esc:clear-filter  [80x24]';
    lines.push(padRight(footer, inner + 2));
    return lines;
  }

  function render(state) {
    var out = buildHeader(state).concat(buildTable(state));
    return out.join('\n');
  }

  window.K9L_DEMO.buildHeader = buildHeader;
  window.K9L_DEMO.buildTable = buildTable;
  window.K9L_DEMO.render = render;
  window.K9L_DEMO.markSort = markSort;
  window.K9L_DEMO.visibleRows = visibleRows;
```

Note: the `window.K9L_DEMO.X = ...` export lines from Step 1 and this step
both run inside the same IIFE - place Step 1's exports at the very end of the
file (after everything is defined), not before Step 2/3's functions exist.
Reorder so all function declarations come first, exports last.

- [ ] **Step 4: Wire initial render on page load**

Append at the very end of `docs/k9l-demo.js` (after all exports):

```js
  document.addEventListener('DOMContentLoaded', function () {
    var el = document.getElementById('k9l-term');
    if (el) el.innerHTML = render(window.K9L_DEMO.state);
  });
```

- [ ] **Step 5: Manual verification in browser console**

Open `docs/index.html` via `file://`, open the browser console, and run:

```js
K9L_DEMO.render(K9L_DEMO.state).includes('demo-app-1')
```

Expected: `true`. Also visually confirm: box borders render as unicode
lines, header shows Context/Cluster/User/K9l Rev on the left with key map on
the right, 12 pod rows visible with one `CrashLoopBackOff` row (styled red
once Step 6's CSS lands), title bar reads `po(demo)[12]`.

- [ ] **Step 6: Add terminal content CSS classes to `docs/k9l.css`**

Append to `docs/k9l.css`:

```css
#k9l-term b { font-weight: 700; }
#k9l-term .hdr-lbl { color: var(--accent-yellow); }
#k9l-term .hdr-val { color: var(--fg); font-weight: 700; }
#k9l-term .hdr-key { color: var(--accent-cyan); }
#k9l-term .hdr-act { color: var(--accent-gray); }
#k9l-term .st-red { color: var(--accent-red); }
#k9l-term .st-yellow { color: var(--accent-yellow); }
#k9l-term .st-green { color: var(--accent-green); }
#k9l-term .st-gray { color: var(--accent-gray); }
#k9l-term .row-cursor { background: #f8f8f2; color: #171a26; }
```

Re-run the Step 5 visual check: `CrashLoopBackOff` row should now show red
text, header labels yellow, key map keys cyan.

- [ ] **Step 7: Commit**

```bash
cd /Users/guru/Work/k9s-clone
git add docs/k9l-demo.js docs/k9l.css
git commit -m "docs: static terminal renderer matching k9s-lite layout"
```

---

## Task 3: Scripted three-act sequence

**Files:**
- Modify: `docs/k9l-demo.js`
- Test: manual, via `file://` + browser console assertions (Step 4)

**Interfaces:**
- Consumes: `render`, `RESOURCES`, `markSort`, `state` object from Task 2.
- Produces:
  - `K9L_DEMO.SCRIPT` - an array of step objects: `{ delay: <ms>, apply: fn(state) }`
  - `K9L_DEMO.playScript(state, el, onDone)` - runs the script step by step,
    re-rendering `el.innerHTML` after each step, calls `onDone()` when the
    script finishes (used by Task 4 to show the idle/takeover cue).
  - `K9L_DEMO.stopScript()` - halts an in-progress script run (used by Task 4
    when the visitor presses a key mid-script).

This task does not yet wire keyboard input - that is Task 4. This task only
makes the terminal animate through the three acts on page load and then stop.

- [ ] **Step 1: Define the script as a data array**

Each step mutates `state` via `apply` and specifies how long to hold that
frame. Append to `docs/k9l-demo.js` (before the DOMContentLoaded handler from
Task 2 Step 4 - that handler will be replaced in Step 3 below):

```js
  function switchResource(state, name) {
    state.resource = name;
    state.header = RESOURCES[name].header();
    state.rows = RESOURCES[name].rows();
    state.cursor = 0;
    state.scroll = 0;
    state.sortCol = 0;
    state.sortDesc = false;
    state.filter = '';
    state.mode = 'table';
  }

  function crashloopIndex(state) {
    for (var i = 0; i < state.rows.length; i++) {
      if (state.rows[i].indexOf('CrashLoopBackOff') !== -1) return i;
    }
    return 0;
  }

  var CRASHLOOP_LOGS = [
    '2026-08-07T10:14:02Z error connecting to redis://cache:6379: dial tcp: i/o timeout',
    '2026-08-07T10:14:02Z fatal: could not initialize worker pool, exiting',
    '2026-08-07T10:14:03Z panic: redis connection required',
    '2026-08-07T10:14:03Z goroutine 1 [running]:',
    '2026-08-07T10:14:03Z main.mustConnectRedis(...)',
    '2026-08-07T10:14:03Z    /app/main.go:41 +0x1c5',
    '2026-08-07T10:14:03Z exit status 2'
  ];

  var SCRIPT = [
    { delay: 1200, apply: function (s) { switchResource(s, 'po'); } },
    { delay: 1500, apply: function (s) { switchResource(s, 'svc'); } },
    { delay: 1500, apply: function (s) { switchResource(s, 'deploy'); } },
    { delay: 1200, apply: function (s) { switchResource(s, 'po'); } },

    { delay: 900, apply: function (s) { s.filter = 'crashloop'; } },
    { delay: 1400, apply: function (s) { s.cursor = crashloopIndex(s); } },
    { delay: 1200, apply: function (s) {
      s.mode = 'detail';
      s.detailTitle = 'describe ' + s.rows[s.cursor].split(/\s+/)[0];
      s.detailLines = [
        'Name:         ' + s.rows[s.cursor].split(/\s+/)[0],
        'Namespace:    demo',
        'Status:       CrashLoopBackOff',
        'Restart Count: 14',
        'Last State:   Terminated (Error, exit code 2)',
        'Reason:       Back-off restarting failed container'
      ];
      s.scroll = 0;
    } },
    { delay: 2200, apply: function (s) {
      s.mode = 'logs';
      s.detailTitle = 'logs ' + s.rows[s.cursor].split(/\s+/)[0];
      s.detailLines = CRASHLOOP_LOGS;
      s.scroll = 0;
    } },
    { delay: 2600, apply: function (s) {
      s.mode = 'table';
      s.filter = '';
      s.cursor = 0;
      s.scroll = 0;
    } },

    { delay: 900, apply: function (s) { s.sortCol = 4; s.sortDesc = true; sortRows(s); } }
  ];

  function sortRows(state) {
    var col = state.sortCol - 1;
    var starts = columnStarts(state.header);
    if (col < 0 || col >= starts.length) return;
    var start = starts[col];
    var end = col + 1 < starts.length ? starts[col + 1] : state.header.length;
    var withKey = state.rows.map(function (r) {
      var cell = r.slice(start, end).trim();
      var n = parseInt(cell, 10);
      return { row: r, key: isNaN(n) ? -1 : n };
    });
    withKey.sort(function (a, b) { return state.sortDesc ? b.key - a.key : a.key - b.key; });
    state.rows = withKey.map(function (w) { return w.row; });
  }
```

Note: the RESTARTS column start position depends on the exact header string;
`columnStarts` from Task 2 Step 2 already computes this generically, so
`sortCol = 4` (1-based, matching the real tool's SORT_COL convention) works
against `podHeader()`'s NAME/READY/STATUS/RESTARTS/AGE layout without a
hardcoded offset.

- [ ] **Step 2: Implement the script runner with cancellation**

```js
  var scriptTimer = null;
  var scriptRunning = false;

  function stopScript() {
    scriptRunning = false;
    if (scriptTimer) { clearTimeout(scriptTimer); scriptTimer = null; }
  }

  function playScript(state, el, onDone) {
    stopScript();
    scriptRunning = true;
    var i = 0;
    function step() {
      if (!scriptRunning) return;
      if (i >= SCRIPT.length) {
        scriptRunning = false;
        if (onDone) onDone();
        return;
      }
      var s = SCRIPT[i++];
      s.apply(state);
      el.innerHTML = render(state);
      scriptTimer = setTimeout(step, s.delay);
    }
    step();
  }

  window.K9L_DEMO.SCRIPT = SCRIPT;
  window.K9L_DEMO.playScript = playScript;
  window.K9L_DEMO.stopScript = stopScript;
  window.K9L_DEMO.switchResource = switchResource;
  window.K9L_DEMO.sortRows = sortRows;
```

- [ ] **Step 3: Replace the Task 2 Step 4 load handler**

Find the `DOMContentLoaded` block added in Task 2 Step 4:

```js
  document.addEventListener('DOMContentLoaded', function () {
    var el = document.getElementById('k9l-term');
    if (el) el.innerHTML = render(window.K9L_DEMO.state);
  });
```

Replace it with:

```js
  document.addEventListener('DOMContentLoaded', function () {
    var el = document.getElementById('k9l-term');
    if (!el) return;
    var reduceMotion = window.matchMedia &&
      window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    if (reduceMotion) {
      SCRIPT.forEach(function (s) { s.apply(window.K9L_DEMO.state); });
      el.innerHTML = render(window.K9L_DEMO.state);
    } else {
      el.innerHTML = render(window.K9L_DEMO.state);
      playScript(window.K9L_DEMO.state, el, function () {
        el.setAttribute('data-idle', '1');
      });
    }
  });
```

- [ ] **Step 4: Manual verification**

Open `docs/index.html` via `file://`. Watch the terminal for roughly 45
seconds: pods -> services -> deployments -> pods (Act 1), then a filter
narrowing to `checkout-worker-crashloop`, cursor landing on it, detail view,
logs view, back to the table (Act 2), then a sort by RESTARTS with the
crashlooping pod at the top (Act 3). Confirm `el.getAttribute('data-idle')`
is `"1"` in the console after the sequence ends, and that it does not restart
on its own.

Also test reduced motion: in Chrome DevTools, Rendering tab -> "Emulate CSS
media feature prefers-reduced-motion: reduce", reload the page. Confirm the
terminal renders immediately in the Act 3 end state (sorted table, no
animation).

- [ ] **Step 5: Commit**

```bash
cd /Users/guru/Work/k9s-clone
git add docs/k9l-demo.js
git commit -m "docs: scripted three-act terminal demo sequence"
```

---

## Task 4: Keyboard takeover and replay control

**Files:**
- Modify: `docs/k9l-demo.js`
- Test: manual, via `file://` + browser console assertions

**Interfaces:**
- Consumes: `playScript`, `stopScript`, `switchResource`, `sortRows`,
  `visibleRows`, `render`, `state` from Tasks 2-3; `#k9l-term` and
  `#k9l-replay` elements from Task 1.
- Produces: nothing consumed by later tasks (this is the last behavioral
  task); finalizes `K9L_DEMO.handleKey(state, key)` as a named,
  independently callable function (`key` is a DOM `KeyboardEvent.key` string,
  e.g. `'j'`, `'Enter'`, `'Escape'`, `'Backspace'`, `':'`, `'/'`) for the
  Step 1 test to call directly.

- [ ] **Step 1: Implement `handleKey` as a pure-ish dispatcher**

Mirrors the real key bindings (`j`/`k` navigate, `:` command mode, `/` filter,
`Enter` opens detail, `l` logs, `o` sort, `Esc` back out, `q` quits to table).
Command mode (`:po`, `:svc`, `:deploy`) is modeled as a small buffered-input
state rather than full command-line editing, since only three destinations
are wired per the design's scope boundary.

Append to `docs/k9l-demo.js`:

```js
  var cmdBuffer = null; // null = not in command mode; string = buffer since ':'
  var filterBuffer = null; // null = not filtering; string = buffer since '/'

  function handleKey(state, key) {
    // command mode: buffer chars until Enter/Esc
    if (cmdBuffer !== null) {
      if (key === 'Enter') {
        var name = cmdBuffer.replace(/^:/, '');
        if (RESOURCES[name]) switchResource(state, name);
        cmdBuffer = null;
        return true;
      }
      if (key === 'Escape') { cmdBuffer = null; return true; }
      if (key.length === 1) { cmdBuffer += key; return true; }
      return true;
    }
    if (filterBuffer !== null) {
      if (key === 'Enter' || key === 'Escape') {
        if (key === 'Escape') state.filter = '';
        filterBuffer = null;
        return true;
      }
      if (key === 'Backspace') { filterBuffer = filterBuffer.slice(0, -1); state.filter = filterBuffer; return true; }
      if (key.length === 1) { filterBuffer += key; state.filter = filterBuffer; return true; }
      return true;
    }

    if (state.mode === 'detail' || state.mode === 'logs') {
      if (key === 'Escape' || key === 'q') { state.mode = 'table'; return true; }
      if (key === 'j') { state.scroll++; return true; }
      if (key === 'k') { state.scroll = Math.max(0, state.scroll - 1); return true; }
      return false;
    }

    switch (key) {
      case 'j': {
        var rows = visibleRows(state);
        state.cursor = Math.min(rows.length - 1, state.cursor + 1);
        return true;
      }
      case 'k':
        state.cursor = Math.max(0, state.cursor - 1);
        return true;
      case ':':
        cmdBuffer = ':';
        return true;
      case '/':
        filterBuffer = '';
        state.filter = '';
        return true;
      case 'Escape':
        state.filter = '';
        return true;
      case 'Enter': {
        var vr = visibleRows(state);
        var row = vr[state.cursor];
        if (!row) return true;
        state.mode = 'detail';
        state.detailTitle = 'describe ' + row.split(/\s+/)[0];
        state.detailLines = row.indexOf('CrashLoopBackOff') !== -1 ? [
          'Name:         ' + row.split(/\s+/)[0],
          'Namespace:    demo',
          'Status:       CrashLoopBackOff',
          'Restart Count: 14',
          'Last State:   Terminated (Error, exit code 2)',
          'Reason:       Back-off restarting failed container'
        ] : [
          'Name:      ' + row.split(/\s+/)[0],
          'Namespace: demo',
          'Status:    ' + (row.split(/\s+/)[2] || 'Running')
        ];
        state.scroll = 0;
        return true;
      }
      case 'l': {
        var vr2 = visibleRows(state);
        var row2 = vr2[state.cursor];
        if (!row2) return true;
        state.mode = 'logs';
        state.detailTitle = 'logs ' + row2.split(/\s+/)[0];
        state.detailLines = row2.indexOf('CrashLoopBackOff') !== -1
          ? CRASHLOOP_LOGS
          : ['2026-08-07T10:00:00Z info: serving on :8080', '2026-08-07T10:00:01Z info: ready'];
        state.scroll = 0;
        return true;
      }
      case 'o':
        state.sortCol = state.sortCol === 4 ? 4 : 4;
        state.sortDesc = state.sortCol === 4 && !state.sortDesc ? !state.sortDesc : true;
        sortRows(state);
        return true;
      default:
        return false;
    }
  }

  window.K9L_DEMO.handleKey = handleKey;
```

- [ ] **Step 2: Wire DOM keydown, focus handling, and replay button**

Replace the `DOMContentLoaded` handler from Task 3 Step 3 with the final
version:

```js
  document.addEventListener('DOMContentLoaded', function () {
    var el = document.getElementById('k9l-term');
    var replayBtn = document.getElementById('k9l-replay');
    if (!el) return;
    var state = window.K9L_DEMO.state;
    var reduceMotion = window.matchMedia &&
      window.matchMedia('(prefers-reduced-motion: reduce)').matches;

    function start() {
      el.removeAttribute('data-idle');
      if (reduceMotion) {
        SCRIPT.forEach(function (s) { s.apply(state); });
        el.innerHTML = render(state);
        el.setAttribute('data-idle', '1');
      } else {
        el.innerHTML = render(state);
        playScript(state, el, function () { el.setAttribute('data-idle', '1'); });
      }
    }

    // Only capture keys once the visitor has focused the terminal, so the
    // page never hijacks browser shortcuts (e.g. '/' for find-in-page).
    el.addEventListener('keydown', function (ev) {
      if (ev.key.length === 1 || ['Enter', 'Escape', 'Backspace'].indexOf(ev.key) !== -1) {
        var handled = handleKey(state, ev.key);
        if (handled) {
          stopScript();
          el.innerHTML = render(state);
          ev.preventDefault();
        }
      }
    });

    if (replayBtn) {
      replayBtn.addEventListener('click', function () {
        state = window.K9L_DEMO.state = (function () {
          var s = state;
          s.resource = 'po'; s.header = RESOURCES.po.header(); s.rows = RESOURCES.po.rows();
          s.cursor = 0; s.scroll = 0; s.sortCol = 0; s.sortDesc = false; s.filter = '';
          s.mode = 'table'; s.detailLines = []; s.detailTitle = '';
          return s;
        })();
        el.focus();
        start();
      });
    }

    start();
  });
```

- [ ] **Step 3: Manual verification**

Open `docs/index.html` via `file://`. Confirm:
1. Before clicking the terminal, pressing `/` does nothing to the page and
   browser find (Cmd/Ctrl+F) still opens normally.
2. Click the terminal, wait for the script to reach Act 2 or 3, then press
   `j` - the script stops immediately and the cursor moves under your
   control.
3. Press `:`, type `svc`, press `Enter` - table switches to services.
4. Press `/`, type `demo`, press `Enter` - table filters to rows containing
   "demo".
5. Press `Esc` - filter clears.
6. Navigate to the crashloop row (after switching back to `po` via `:po` +
   `Enter`), press `Enter` for detail, `l` for logs, `Esc` back to table.
7. Press `o` on the pod table - RESTARTS column sorts, marker appears in the
   header.
8. Click "Replay" - script restarts from Act 1.

- [ ] **Step 4: Commit**

```bash
cd /Users/guru/Work/k9s-clone
git add docs/k9l-demo.js
git commit -m "docs: keyboard takeover and replay control for terminal demo"
```

---

## Task 5: Copy-to-clipboard for install command, final polish pass, and PR

**Files:**
- Modify: `docs/index.html` (none expected, listed for completeness)
- Modify: `docs/k9l-demo.js` (add copy-button handler)
- Modify: `docs/k9l.css` (only if polish pass finds issues)
- Test: manual

**Interfaces:** none - this is the final integration task, no downstream
consumers.

- [ ] **Step 1: Implement copy-to-clipboard**

Append to `docs/k9l-demo.js`, inside the same `DOMContentLoaded` handler
(after the `start();` call from Task 4 Step 2), or as a second listener
registration - add this block right after the `start();` line:

```js
    document.querySelectorAll('button.copy').forEach(function (btn) {
      btn.addEventListener('click', function () {
        var targetId = btn.getAttribute('data-copy-target');
        var target = document.getElementById(targetId);
        if (!target || !navigator.clipboard) return;
        navigator.clipboard.writeText(target.textContent).then(function () {
          var original = btn.textContent;
          btn.textContent = 'Copied';
          setTimeout(function () { btn.textContent = original; }, 1500);
        });
      });
    });
```

- [ ] **Step 2: Manual verification**

Open `docs/index.html` via `file://`. Click "Copy" next to the install
command. Paste into a text field and confirm it matches the two-line curl
command exactly (no leading/trailing whitespace from the `<code>` block
indentation - if there is stray whitespace, fix the HTML in Task 1's
`index.html` so the `<code>` content starts immediately after the opening
tag with no newline).

Note: `navigator.clipboard` requires a secure context. `file://` origins are
treated as secure by Chrome/Firefox for this API in current versions, but
confirm in your browser; if it silently no-ops locally, that's expected and
will work correctly once served over HTTPS by GitHub Pages - not a bug to
chase further at this stage.

- [ ] **Step 3: Full manual regression pass**

Re-run all manual checks from Tasks 1 through 4 in one sitting: page loads
with no console errors, three-act script plays and idles without looping,
keyboard takeover works for every wired key, reduced-motion mode shows the
end state immediately, find-in-page is not hijacked before focus, replay
button resets to Act 1, copy button works.

Also check responsive behavior: narrow the browser window to ~375px wide
(mobile width) and confirm the page does not horizontally scroll as a whole
(the `#k9l-term` box itself may internally scroll per `k9l.css`'s
`overflow-x: auto`, which is correct - only the outer page must not scroll
sideways).

- [ ] **Step 4: Update root README with a link to the new page (optional but recommended)**

Per repo convention, README stays in sync with user-visible additions. Add
one line near the top of `README.md` (after the badges, before "Quick
start"), matching existing style:

```markdown
**[Try it in your browser](https://bguruprasad.github.io/k9s-lite/)** - an interactive demo, no install needed.
```

- [ ] **Step 5: Commit**

```bash
cd /Users/guru/Work/k9s-clone
git add docs/k9l-demo.js README.md
git commit -m "docs: copy-to-clipboard for install command, link from README"
```

- [ ] **Step 6: Push branch and open PR**

```bash
cd /Users/guru/Work/k9s-clone
git push -u origin docs/github-pages-site
gh pr create --title "docs: GitHub Pages landing site with interactive terminal demo" \
  --body "$(cat <<'EOF'
Adds a static landing page under docs/ for GitHub Pages, built around a
browser-simulated k9s-lite terminal (scripted three-act demo, then keyboard
takeover).

See docs/superpowers/specs/2026-08-07-github-pages-site-design.md for the
design rationale, including the drift-risk tradeoff of a JS reimplementation
of the UI and how scope was bounded to manage it.

Not on the release path; docs/ is not linted by CI. Once merged, repo Source
setting for Pages needs to be pointed at main + /docs (currently set to this
branch for preview per the user's request - repointing to main is a manual
Settings step after merge, not part of this PR).

No functional changes to k9s-lite.sh or lib/.
EOF
)"
```

- [ ] **Step 7: Fresh-agent review**

Per repo convention (`CLAUDE.md`, `HANDOFF.md`), spawn a cold-context
reviewer agent on this PR before merge, even though it touches no shell code
- the JS terminal simulation is exactly the kind of thing worth a second set
of eyes, given the drift risk documented in the design spec. Skip only if the
user explicitly waives it for this PR.

- [ ] **Step 8: Wait for CI, then merge per repo convention**

Wait for `lint` + `smoke (ubuntu)` + `smoke (macos)` green (these should be
unaffected by docs/ changes, but must still be green - never merge on red or
pending checks). Merge with:

```bash
gh pr merge <N> --admin --squash --delete-branch
```

Only after the fresh-agent review (Step 7) is addressed and the user has
given the go-ahead, consistent with "user merges the release-critical PRs
when they say so" - confirm with the user this PR is ready to merge rather
than assuming.

---

## Post-merge follow-up (not part of this plan's tasks - flag to user, do not do automatically)

- Repoint repo Settings -> Pages source from `docs/github-pages-site` branch
  (set temporarily per the user's request for preview) to `main` branch,
  `/docs` folder.
- Consider whether release automation should also bump the version pin in
  `docs/index.html`'s install command, per the Risks section of the design
  spec - currently a manual follow-up, not automated by this plan.
