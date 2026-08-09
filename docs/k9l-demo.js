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
//
// State shape:
// {
//   ctx: 'demo', cluster: 'demo-cluster', user: 'demo-user', k8s: 'demo',
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

  // Column widths sum to the table box's interior (COLS - 2) so rows fill it
  // edge to edge, the way kubectl's tabwriter fills a real terminal.
  // 40 + 1 + 9 + 1 + 20 + 1 + 12 + 1 + 12 = 97, + 1 lead space = 98 = COLS - 2.
  function podHeader() {
    return padRight('NAME', 40) + ' ' + padRight('READY', 9) + ' ' +
      padRight('STATUS', 20) + ' ' + padRight('RESTARTS', 12) + ' ' +
      padRight('AGE', 12);
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
        padRight(name, 40) + ' ' +
        padRight('1/1', 9) + ' ' +
        padRight(status, 20) + ' ' +
        padRight(String(restarts), 12) + ' ' +
        padRight(age, 12)
      );
    }
    return rows;
  }

  // 24 + 1 + 12 + 1 + 18 + 1 + 15 + 1 + 14 + 1 + 10 = 98
  function svcHeader() {
    return padRight('NAME', 24) + ' ' + padRight('TYPE', 12) + ' ' +
      padRight('CLUSTER-IP', 18) + ' ' + padRight('EXTERNAL-IP', 15) + ' ' +
      padRight('PORT(S)', 14) + ' ' + padRight('AGE', 10);
  }

  function svcRows() {
    var row = function (name, ip, ports, age) {
      return padRight(name, 24) + ' ' + padRight('ClusterIP', 12) + ' ' +
        padRight(ip, 18) + ' ' + padRight('<none>', 15) + ' ' +
        padRight(ports, 14) + ' ' + padRight(age, 10);
    };
    return [
      row('checkout', '10.96.12.4', '80/TCP', '2d'),
      row('demo-app', '10.96.8.190', '8080/TCP', '5d')
    ];
  }

  // 34 + 1 + 10 + 1 + 16 + 1 + 15 + 1 + 19 = 98
  function deployHeader() {
    return padRight('NAME', 34) + ' ' + padRight('READY', 10) + ' ' +
      padRight('UP-TO-DATE', 16) + ' ' + padRight('AVAILABLE', 15) + ' ' +
      padRight('AGE', 19);
  }

  function deployRows() {
    var row = function (name, age) {
      return padRight(name, 34) + ' ' + padRight('1/1', 10) + ' ' +
        padRight('1', 16) + ' ' + padRight('1', 15) + ' ' + padRight(age, 19);
    };
    return [row('checkout-worker', '2d'), row('demo-app', '5d')];
  }

  var RESOURCES = {
    // titles use the full resource names the real tool starts with
    // (lib/kube.sh:7 sets RESOURCE="pods"), not the :po/:svc shortnames
    po: { header: podHeader, rows: podRows, title: 'pods(demo)' },
    svc: { header: svcHeader, rows: svcRows, title: 'services(demo)' },
    deploy: { header: deployHeader, rows: deployRows, title: 'deployments(demo)' }
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
      ctx: 'demo', cluster: 'demo-cluster', user: 'demo-user', k8s: 'demo',
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
    // cell text runs from start to the first double-space (or column end)
    var next = col + 1 < starts.length ? starts[col + 1] : header.length;
    var cellEnd = header.indexOf('  ', start);
    if (cellEnd === -1 || cellEnd > next) cellEnd = next;
    var pos = cellEnd;
    if (col + 1 >= starts.length) {
      // last column: no gap to its right. Overwrite trailing padding if any
      // exists; otherwise append " ^"/" v" after the header text (mirrors
      // table_mark_sort's j + 1 >= COL_N branch, lib/table.sh:269-276).
      if (pos + 2 <= header.length) {
        return header.slice(0, pos) + ' ' + mark + header.slice(pos + 2);
      }
      return header + ' ' + mark;
    }
    if (pos + 2 > next - 1) pos = Math.max(start, next - 3);
    return header.slice(0, pos) + ' ' + mark + header.slice(pos + 2);
  }

  var KEYMAP_LINES = [
    ['Context:', 'ctx', '<d>', 'describe', '<s>', 'shell', '<:>', 'resource'],
    ['Cluster:', 'cluster', '<y>', 'yaml', '<e>', 'edit', '</>', 'filter'],
    ['User:', 'user', '<v>', 'events', '<^d>', 'delete', '<n>', 'namespace'],
    ['K9l Rev:', null, '<l>', 'logs', '<r>', 'refresh', '<c>', 'context'],
    ['K8s Rev:', 'k8s', '<p>', 'prev logs', '<a>', 'browse', '<q>', 'quit']
  ];

  // COLS is the single source of truth for the simulated terminal's width.
  // Every line the renderer emits - header rows, the table box, the footer -
  // is exactly COLS characters, so the whole grid shares one right edge and
  // #k9l-term's max-content width wraps it snugly (see k9l.css).
  // Mirrors the real tool's layout at a wide COLS: identity block left,
  // ASCII logo centered in the gap, key map flush right (k9s-lite.sh:91-137).
  var COLS = 100;
  // key padded to 4 + trailing space, action to 9 + trailing space = 15 per
  // pair, matching add_info_line's printf widths (k9s-lite.sh:108-114)
  var HDR_VALW = 20;
  var HDR_KEYW = 5;
  var HDR_ACTW = 10;
  var HDR_LEFTW = 1 + 9 + 1 + HDR_VALW;              // lead + label + space + value
  var HDR_RIGHTW = 3 * (HDR_KEYW + HDR_ACTW);        // 3 key/action pairs
  var HDR_GAPW = COLS - HDR_LEFTW - HDR_RIGHTW;      // logo lives in here

  function buildHeader(state) {
    var lines = [];
    var logoW = LOGO[0].length;
    // logo centered within the gap, exactly as add_info_line does when the
    // terminal is wide enough to fit it (mid >= logo_w + 4). There are 5
    // identity lines and 5 logo rows, so one logo row sits beside each -
    // the same pairing the real tool gets from `line_i < ${#K9L_LOGO[@]}`.
    var logoPad = Math.max(0, Math.floor((HDR_GAPW - logoW) / 2));
    KEYMAP_LINES.forEach(function (spec, idx) {
      var label = spec[0];
      var val = spec[1] === 'ctx' ? state.ctx : spec[1] === 'cluster' ? state.cluster :
        spec[1] === 'user' ? state.user : spec[1] === 'k8s' ? state.k8s : 'v0.13.1 (demo)';
      var left = '<span class="hdr-lbl">' + esc(padRight(label, 9)) + '</span> ' +
        '<span class="hdr-val">' + esc(padRight(val, HDR_VALW)) + '</span>';
      var right = '';
      for (var i = 2; i < spec.length; i += 2) {
        right += '<span class="hdr-key">' + esc(padRight(spec[i], HDR_KEYW)) + '</span>' +
          '<span class="hdr-act">' + esc(padRight(spec[i + 1], HDR_ACTW)) + '</span>';
      }
      var gap = padRight('', logoPad) +
        '<span class="hdr-logo">' + esc(padRight(LOGO[idx], logoW)) + '</span>' +
        padRight('', HDR_GAPW - logoPad - logoW);
      lines.push(' ' + left + gap + right);
    });
    // tagline centered under the logo on its own line, mirroring build_info's
    // INFO_SHOW_TAG path. Padded to COLS so it shares the grid's right edge.
    var tagPad = Math.max(0, HDR_LEFTW + logoPad + Math.floor((logoW - TAG.length) / 2));
    lines.push(padRight('', tagPad) + '<span class="hdr-tag">' + esc(TAG) + '</span>' +
      padRight('', COLS - tagPad - TAG.length));
    return lines;
  }

  function visibleRows(state) {
    if (!state.filter) return state.rows;
    var f = state.filter.toLowerCase();
    return state.rows.filter(function (r) { return r.toLowerCase().indexOf(f) !== -1; });
  }

  function buildTable(state) {
    var lines = [];
    var inner = COLS - 2;   // two border chars, so the box spans exactly COLS
    var rule = function (n) { return new Array(n + 1).join(BOX.h); };
    var rows = state.mode === 'table' ? visibleRows(state) : state.detailLines;
    var title = state.mode === 'table'
      ? ' ' + RESOURCES[state.resource].title + '[' + rows.length + '] '
      : ' ' + state.detailTitle + ' ';
    var left = Math.floor((inner - title.length) / 2);
    var right = inner - title.length - left;
    lines.push(BOX.tl + rule(left) + '<b>' + esc(title) + '</b>' + rule(right) + BOX.tr);

    if (state.mode === 'table') {
      var header = markSort(state.header, state.sortCol, state.sortDesc);
      lines.push(BOX.v + '<b>' + esc(padRight(' ' + header, inner)) + '</b>' + BOX.v);
    }

    var bodyH = state.mode === 'table' ? 10 : 14;
    for (var i = state.scroll; i < state.scroll + bodyH; i++) {
      if (i < rows.length) {
        var row = rows[i];
        if (state.mode === 'table' && i === state.cursor) {
          lines.push(BOX.v + '<span class="row-cursor">' + esc(padRight('>' + row, inner)) + '</span>' + BOX.v);
        } else {
          var cls = state.mode === 'table' ? rowColor(row) : '';
          lines.push(BOX.v + '<span class="' + cls + '">' + esc(padRight(' ' + row, inner)) + '</span>' + BOX.v);
        }
      } else {
        lines.push(BOX.v + padRight('', inner) + BOX.v);
      }
    }
    lines.push(BOX.bl + rule(inner) + BOX.br);

    var footer = state.filter
      ? ' filter: ' + state.filter + '  Esc:clear-filter'
      : ' ?:help  o/O:sort  a:resources  r:refresh  0:all-ns  Esc:clear-filter  [' + COLS + 'x24]';
    lines.push(esc(padRight(footer, inner + 2)));
    return lines;
  }

  function render(state) {
    var out = buildHeader(state).concat(buildTable(state));
    return out.join('\n');
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
  window.K9L_DEMO.buildHeader = buildHeader;
  window.K9L_DEMO.buildTable = buildTable;
  window.K9L_DEMO.render = render;
  window.K9L_DEMO.markSort = markSort;
  window.K9L_DEMO.visibleRows = visibleRows;

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
    // Matches by name, not just by 'CrashLoopBackOff' status: podRows() seeds
    // more than one CrashLoopBackOff row for visual variety, but only
    // checkout-worker-crashloop is the one Act 2 filters to and inspects.
    // Searches visibleRows (not state.rows) when a filter is active, since
    // buildTable renders visibleRows(state) whenever state.filter is set -
    // the cursor index must live in whatever index space the renderer uses.
    var rows = state.filter ? visibleRows(state) : state.rows;
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].indexOf('checkout-worker-crashloop') !== -1) return i;
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

  var SCRIPT = [
    { delay: 1200, apply: function (s) { switchResource(s, 'po'); } },
    { delay: 1500, apply: function (s) { switchResource(s, 'svc'); } },
    { delay: 1500, apply: function (s) { switchResource(s, 'deploy'); } },
    { delay: 1200, apply: function (s) { switchResource(s, 'po'); } },

    { delay: 900, apply: function (s) { s.filter = 'crashloop'; } },
    { delay: 1400, apply: function (s) { s.cursor = crashloopIndex(s); } },
    { delay: 1200, apply: function (s) {
      // s.filter is still active here, so the row s.cursor points at lives
      // in visibleRows(s), not s.rows (same index-space rule as
      // crashloopIndex - buildTable renders visibleRows whenever filtered).
      var targetName = visibleRows(s)[s.cursor].split(/\s+/)[0];
      s.mode = 'detail';
      s.detailTitle = 'describe ' + targetName;
      s.detailLines = [
        'Name:         ' + targetName,
        'Namespace:    demo',
        'Status:       CrashLoopBackOff',
        'Restart Count: 14',
        'Last State:   Terminated (Error, exit code 2)',
        'Reason:       Back-off restarting failed container'
      ];
      s.scroll = 0;
    } },
    { delay: 2200, apply: function (s) {
      // Same index-space note as the describe step above: s.filter is still
      // set, so resolve the row via visibleRows(s), not s.rows.
      var targetName = visibleRows(s)[s.cursor].split(/\s+/)[0];
      s.mode = 'logs';
      s.detailTitle = 'logs ' + targetName;
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
        if (key === 'Escape') { state.filter = ''; clampCursor(state); }
        filterBuffer = null;
        return true;
      }
      if (key === 'Backspace') {
        filterBuffer = filterBuffer.slice(0, -1);
        state.filter = filterBuffer;
        clampCursor(state);
        return true;
      }
      if (key.length === 1) {
        filterBuffer += key;
        state.filter = filterBuffer;
        clampCursor(state);
        return true;
      }
      return true;
    }

    if (state.mode === 'detail' || state.mode === 'logs') {
      if (key === 'Escape' || key === 'q') { state.mode = 'table'; return true; }
      if (key === 'j') {
        state.scroll = Math.min(Math.max(0, state.detailLines.length - 1), state.scroll + 1);
        return true;
      }
      if (key === 'k') { state.scroll = Math.max(0, state.scroll - 1); return true; }
      return false;
    }

    switch (key) {
      case 'j': {
        // Bound against visibleRows, not state.rows: buildTable renders
        // visibleRows(state) whenever state.filter is set, so state.cursor
        // must live in that same index space (see module header note on the
        // index-space rule fixed in crashloopIndex/SCRIPT above).
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
        clampCursor(state);
        return true;
      case 'Escape':
        state.filter = '';
        clampCursor(state);
        return true;
      case 'Enter': {
        // Look up the selected row via visibleRows, matching the index space
        // that j/k navigation and buildTable's rendering already use when a
        // filter is active - indexing state.rows here would target the wrong
        // row while filtered (the exact bug fixed twice already in SCRIPT).
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
        // Same index-space rule as Enter above: resolve via visibleRows.
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
        state.sortCol = 4;
        state.sortDesc = !state.sortDesc;
        sortRows(state);
        return true;
      default:
        return false;
    }
  }

  // clampCursor - re-clamp state.cursor whenever state.filter changes and
  // may have narrowed (or widened) visibleRows(state); without this a
  // cursor left pointing past the end of a newly-shorter filtered list
  // renders no cursor bar and makes Enter/l silently no-op.
  function clampCursor(state) {
    state.cursor = Math.max(0, Math.min(state.cursor, visibleRows(state).length - 1));
  }

  window.K9L_DEMO.handleKey = handleKey;

  // pressKeys - drive handleKey with a sequence of keys as if the visitor had
  // typed them, then re-render once at the end. This is the ONLY way command
  // buttons touch state; it is not a second way to mutate it - every button
  // click just replays the same handleKey path a real keydown uses, so a
  // button and its equivalent keystrokes always leave the demo in the same
  // state. Intermediate frames are not rendered, matching how a mouse-click
  // visitor never sees the per-keystroke frames a typed sequence would take.
  function pressKeys(state, el, keys) {
    keys.forEach(function (key) { handleKey(state, key); });
    el.innerHTML = render(state);
  }

  window.K9L_DEMO.pressKeys = pressKeys;

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
        state.resource = 'po';
        state.header = RESOURCES.po.header();
        state.rows = RESOURCES.po.rows();
        state.cursor = 0;
        state.scroll = 0;
        state.sortCol = 0;
        state.sortDesc = false;
        state.filter = '';
        state.mode = 'table';
        state.detailLines = [];
        state.detailTitle = '';
        cmdBuffer = null;
        filterBuffer = null;
        el.focus();
        start();
      });
    }

    // Command buttons: each carries a data-keys attribute, a comma-separated
    // list of the exact keys handleKey(state, key) would receive if the
    // visitor typed the equivalent shortcut (e.g. ":,p,o,Enter" for the
    // ":po" button). This is deliberately the same code path a keydown uses -
    // see pressKeys above - so button clicks and typing can never diverge.
    document.querySelectorAll('.demo-cmd-buttons button[data-keys]').forEach(function (btn) {
      btn.addEventListener('click', function () {
        stopScript();
        var keys = btn.getAttribute('data-keys').split(',');
        pressKeys(state, el, keys);
        el.focus();
      });
    });

    start();

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
  });
})();
