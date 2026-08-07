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
    KEYMAP_LINES.forEach(function (spec) {
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

  document.addEventListener('DOMContentLoaded', function () {
    var el = document.getElementById('k9l-term');
    if (el) el.innerHTML = render(window.K9L_DEMO.state);
  });
})();
