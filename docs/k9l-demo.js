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

  var KEYMAP_LINES = [
    ['Context:', 'ctx', '<d>', 'describe', '<s>', 'shell', '<:>', 'resource'],
    ['Cluster:', 'cluster', '<y>', 'yaml', '<e>', 'edit', '</>', 'filter'],
    ['User:', 'user', '<v>', 'events', '<^d>', 'delete', '<n>', 'namespace'],
    ['K9l Rev:', null, '<l>', 'logs', '<r>', 'refresh', '<c>', 'context']
  ];

  function buildHeader(state) {
    var lines = [];
    KEYMAP_LINES.forEach(function (spec, idx) {
      var label = spec[0];
      var val = spec[1] === 'ctx' ? state.ctx : spec[1] === 'cluster' ? state.cluster :
        spec[1] === 'user' ? state.user : 'v0.13.1 (demo)';
      var left = '<span class="hdr-lbl">' + esc(padRight(label, 9)) + '</span> ' +
        '<span class="hdr-val">' + esc(padRight(val, 24)) + '</span>';
      var right = '';
      for (var i = 2; i < spec.length; i += 2) {
        right += '<span class="hdr-key">' + esc(padRight(spec[i], 5)) + '</span>' +
          '<span class="hdr-act">' + esc(padRight(spec[i + 1], 10)) + '</span>';
      }
      // Logo sits centered in the gap between the identity block and the key
      // map, one LOGO line per KEYMAP_LINES row - mirrors add_info_line's
      // centering in k9s-lite.sh, simplified (fixed-width demo, no COLS math).
      var logo = '  <span class="hdr-logo">' + esc(LOGO[idx]) + '</span>';
      lines.push(' ' + left + logo + '  ' + right);
    });
    // LOGO has 5 lines but KEYMAP_LINES only 4 (real k9s-lite has a 5th
    // Context/Cluster/User/Rev row - K8s Rev - this demo doesn't simulate).
    // Real k9s-lite centers TAG on its own trailing line under the logo
    // (k9s-lite.sh build_info, INFO_SHOW_TAG); mirrored here by giving the
    // logo's last line its own row, with TAG alongside it in the same gap.
    lines.push(padRight('', 35) + '  <span class="hdr-logo">' +
      esc(LOGO[4]) + '  ' + TAG + '</span>');
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
      : ' ?:help  o/O:sort  a:resources  r:refresh  0:all-ns  Esc:clear-filter  [80x24]';
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
        return true;
      case 'Escape':
        state.filter = '';
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

  window.K9L_DEMO.handleKey = handleKey;

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
