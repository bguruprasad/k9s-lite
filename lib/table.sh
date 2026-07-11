# shellcheck shell=bash
# table.sh - table view state and rendering.
# State: TABLE_ROWS (one preformatted line per item), CURSOR, SCROLL.

TABLE_TITLE=""
TABLE_TITLE_C=""   # colored variant; must render at the same visible width as TABLE_TITLE
TABLE_HEADER=""
INFO_LINES=()      # k9s-style header block (context/cluster/user/ver + key map)
TABLE_ROWS=()
TABLE_MSG=""       # rendered in red under the header when set (errors, empty list)
TABLE_FOOT=""      # overrides the default footer hint when set (picker mode)
CURSOR=0
SCROLL=0
ROW_SGR=""
DETAIL_VIEW=""     # when set: rows are free-form text - no cursor bar, no column
                   # re-flow, cursor acts as the scroll position
DETAIL_KV=""       # when also set: colorize "Key:" prefixes cyan (describe output;
                   # log lines must stay uncolored - timestamps contain colons)
DKEY_SGR=$'\e[36m'

# box-drawing characters (K9L_ASCII=1 for plain +---+ on odd terminals)
if [[ -n ${K9L_ASCII:-} ]]; then
  BOX_H='-'; BOX_V='|'; BOX_TL='+'; BOX_TR='+'; BOX_BL='+'; BOX_BR='+'
else
  BOX_H='─'; BOX_V='│'; BOX_TL='┌'; BOX_TR='┐'; BOX_BL='└'; BOX_BR='┘'
fi

table_move() {
  CURSOR=$(( CURSOR + $1 ))   # clamped in table_draw
}

table_top()    { CURSOR=0; }
table_bottom() { CURSOR=$(( ${#TABLE_ROWS[@]} - 1 )); }

# row_color <row> - set ROW_SGR by status keyword (no subshell)
row_color() {
  case "$1" in
    *CrashLoopBackOff*|*Error*|*Failed*|*Evicted*|*ImagePull*) ROW_SGR=$'\e[31m' ;;
    *Pending*|*ContainerCreating*|*Terminating*|*Init:*|*Warning*) ROW_SGR=$'\e[33m' ;;
    *Completed*)                                               ROW_SGR=$'\e[90m' ;;
    *Running*)                                                 ROW_SGR=$'\e[32m' ;;
    *)                                                         ROW_SGR="" ;;
  esac
}

# table_columns - detect column start positions from TABLE_HEADER into
# COL_STARTS/COL_N (kubectl's tabwriter aligns rows identically to the
# header; a non-space preceded by >=2 spaces starts a column).
COL_STARTS=()
COL_N=0
table_columns() {
  COL_STARTS=(0)
  local h=$TABLE_HEADER hlen=${#TABLE_HEADER} i c gapn=0
  for (( i = 1; i < hlen; i++ )); do
    c=${h:i:1}
    if [[ $c == ' ' ]]; then
      (( gapn++ ))
    else
      (( gapn >= 2 )) && COL_STARTS+=("$i")
      gapn=0
    fi
  done
  COL_N=${#COL_STARTS[@]}
}

# table_cell <row> <col-index-0-based> - trimmed cell text into $CELL
table_cell() {
  local row=$1 j=$2 clen sp
  local start=${COL_STARTS[j]}
  if (( j + 1 < COL_N )); then
    clen=$(( ${COL_STARTS[j+1]} - start ))
    CELL=${row:start:clen}
  else
    CELL=${row:start}
  fi
  sp=${CELL##*[! ]}; CELL=${CELL%"$sp"}
  CELL="${CELL#"${CELL%%[![:space:]]*}"}"
}

# Sort TABLE_ROWS by column SORT_COL (1-based; 0 = kubectl's natural order),
# descending when SORT_DESC is set. Numeric columns (all keys digits-only)
# sort numerically. One sort(1) fork per refresh - same cost class as the
# kubectl call that produced the rows.
# IMPORTANT: sorts rows only - TABLE_HEADER must NOT be touched here. The
# header defines the column positions the rows are aligned to; changing its
# length would make reflow slice every row at the wrong offsets (columns
# bleeding into each other, status colors lost). The visual ^/v marker is a
# display-only overlay applied at draw time by table_mark_sort, never stored.
SORT_COL=0
SORT_DESC=""
table_sort() {
  (( SORT_COL <= 0 )) && return 0
  [[ -n $DETAIL_VIEW || -z $TABLE_HEADER ]] && return 0
  local n=${#TABLE_ROWS[@]}
  table_columns
  (( COL_N < 1 )) && return 0
  (( SORT_COL > COL_N )) && SORT_COL=$COL_N
  local j=$(( SORT_COL - 1 ))
  (( n < 2 )) && return 0
  local sep=$'\x01' i numeric=1 lines=()
  for (( i = 0; i < n; i++ )); do
    table_cell "${TABLE_ROWS[i]}" "$j"
    [[ $CELL == *[!0-9]* || -z $CELL ]] && numeric=0
    lines+=("${CELL}${sep}${TABLE_ROWS[i]}")
  done
  local sortargs=(-t "$sep" "-k1,1")
  (( numeric )) && sortargs+=(-n)
  [[ -n $SORT_DESC ]] && sortargs+=(-r)
  local sorted line
  sorted=$(printf '%s\n' "${lines[@]}" | LC_ALL=C sort "${sortargs[@]}")
  TABLE_ROWS=()
  while IFS= read -r line; do
    TABLE_ROWS+=("${line#*"$sep"}")
  done <<< "$sorted"
  return 0
}

# Drop columns whose header cell matches the comma-separated hide list.
# NOMINATED NODE and READINESS GATES (kubectl -o wide extras) are almost
# always <none> and just eat width the NAME column could use. Cutting the
# exact [start, next-start) region from header and rows keeps everything
# else aligned. Idempotent: on a fetch error the previous (already-cut)
# rows are kept and the scan simply finds nothing to cut.
K9L_HIDE_COLUMNS="${K9L_HIDE_COLUMNS:-NOMINATED NODE,READINESS GATES}"
table_hide_columns() {
  [[ -z $K9L_HIDE_COLUMNS || -z $TABLE_HEADER ]] && return 0
  table_columns
  (( COL_N < 2 )) && return 0
  local j drops=()
  for (( j = COL_N - 1; j >= 0; j-- )); do   # high to low: earlier offsets stay valid
    table_cell "$TABLE_HEADER" "$j"
    case ",${K9L_HIDE_COLUMNS}," in
      *",${CELL},"*) drops+=("$j") ;;
    esac
  done
  (( ${#drops[@]} == 0 )) && return 0
  local d start end n=${#TABLE_ROWS[@]} i sp
  for d in "${drops[@]}"; do
    start=${COL_STARTS[d]}
    if (( d + 1 < COL_N )); then end=${COL_STARTS[d+1]}; else end=-1; fi
    if (( end < 0 )); then
      TABLE_HEADER=${TABLE_HEADER:0:start}
      for (( i = 0; i < n; i++ )); do
        TABLE_ROWS[i]=${TABLE_ROWS[i]:0:start}
      done
    else
      TABLE_HEADER="${TABLE_HEADER:0:start}${TABLE_HEADER:end}"
      for (( i = 0; i < n; i++ )); do
        TABLE_ROWS[i]="${TABLE_ROWS[i]:0:start}${TABLE_ROWS[i]:end}"
      done
    fi
  done
  # trim trailing spaces left by a last-column cut
  sp=${TABLE_HEADER##*[! ]}; TABLE_HEADER=${TABLE_HEADER%"$sp"}
  for (( i = 0; i < n; i++ )); do
    sp=${TABLE_ROWS[i]##*[! ]}; TABLE_ROWS[i]=${TABLE_ROWS[i]%"$sp"}
  done
  return 0
}

# Build a DISPLAY-ONLY copy of the header with the ^/v sort marker, into
# $MARKED_HEADER. Never mutates TABLE_HEADER: the marker used to live in the
# header itself, so any pass that re-ran on a kept header (kubectl-error tick),
# a reflowed header (resize), or a shifted layout (0-toggle) double-marked,
# accumulated (`NODE ^ ^ ^`), or mis-derived columns. Keeping it out of the
# data makes every pass idempotent - draw calls this each frame on the pristine,
# already-reflowed TABLE_HEADER and prints the result without storing it.
#
# Length-preserving: overwrites padding spaces in place so the display copy is
# the same width as the rows (draw pads both to the box width). " ^" sits right
# after the header text when the column has slack, a bare mark in the last gap
# space when the text fills the column. The last column has no gap to its right,
# so the mark overwrites its own trailing padding; if it fills to the very end
# we append (draw truncates to the box width, and rows are independent).
MARKED_HEADER=""
table_mark_sort() {
  MARKED_HEADER=$TABLE_HEADER
  (( SORT_COL <= 0 )) && return 0
  [[ -n $DETAIL_VIEW || -z $TABLE_HEADER ]] && return 0
  table_columns
  (( COL_N < 1 )) && return 0
  (( SORT_COL > COL_N )) && SORT_COL=$COL_N
  local j=$(( SORT_COL - 1 ))
  local mark='^'
  [[ -n $SORT_DESC ]] && mark='v'
  table_cell "$TABLE_HEADER" "$j"
  local start=${COL_STARTS[j]} len=${#CELL} pos str h=$TABLE_HEADER hlen=${#TABLE_HEADER}
  if (( j + 1 >= COL_N )); then
    pos=$(( start + len ))
    if (( pos + 2 <= hlen )); then          # trailing padding to overwrite
      MARKED_HEADER="${h:0:pos} ${mark}${h:pos+2}"
    else
      MARKED_HEADER="${h} ${mark}"          # cell fills to the end: append
    fi
    return 0
  fi
  local next=${COL_STARTS[j+1]}
  pos=$(( start + len ))
  str=" ${mark}"
  if (( pos + 2 > next - 2 )); then
    pos=$(( next - 3 ))     # header fills the column: bare mark in the gap
    str=$mark
  fi
  MARKED_HEADER="${h:0:pos}${str}${h:pos+${#str}}"
  return 0
}

# Re-flow kubectl's tabwriter columns to span the full box width. Column
# boundaries come from the header (rows are aligned identically by kubectl);
# spare width is distributed proportionally to each column's natural width.
# Pure string ops - zero forks, safe to run per refresh/resize.
LAYOUT_COLS=0
table_reflow() {
  LAYOUT_COLS=$COLS
  local inner=$(( COLS - 2 ))
  [[ -n $DETAIL_VIEW ]] && return 0    # free-form text, not columns
  [[ -z $TABLE_HEADER ]] && return 0

  table_columns
  local h=$TABLE_HEADER starts=("${COL_STARTS[@]}") ncols=$COL_N
  (( ncols < 2 )) && return 0

  # pass 1: natural (trimmed) width per column, across header + rows
  local n=${#TABLE_ROWS[@]} r j row cell sp start clen total=0 maxw=()
  for (( j = 0; j < ncols; j++ )); do maxw[j]=0; done
  for (( r = -1; r < n; r++ )); do
    if (( r < 0 )); then row=$h; else row=${TABLE_ROWS[r]}; fi
    for (( j = 0; j < ncols; j++ )); do
      start=${starts[j]}
      if (( j + 1 < ncols )); then
        clen=$(( ${starts[j+1]} - start )); cell=${row:start:clen}
      else
        cell=${row:start}
      fi
      sp=${cell##*[! ]}; cell=${cell%"$sp"}
      (( ${#cell} > maxw[j] )) && maxw[j]=${#cell}
    done
  done
  for (( j = 0; j < ncols; j++ )); do total=$(( total + maxw[j] )); done

  # distribute spare width proportionally (draw adds 1 leading char)
  local gap=3 avail extra width=()
  avail=$(( inner - 1 - total - gap * (ncols - 1) ))
  (( avail < 0 )) && avail=0
  for (( j = 0; j < ncols; j++ )); do
    extra=0
    (( total > 0 )) && extra=$(( avail * maxw[j] / total ))
    width[j]=$(( maxw[j] + extra ))
  done

  # pass 2: rebuild header + rows at the new widths
  local out seg new=()
  for (( r = -1; r < n; r++ )); do
    if (( r < 0 )); then row=$h; else row=${TABLE_ROWS[r]}; fi
    out=""
    for (( j = 0; j < ncols; j++ )); do
      start=${starts[j]}
      if (( j + 1 < ncols )); then
        clen=$(( ${starts[j+1]} - start )); cell=${row:start:clen}
      else
        cell=${row:start}
      fi
      sp=${cell##*[! ]}; cell=${cell%"$sp"}
      if (( j + 1 < ncols )); then
        printf -v seg '%-*s' $(( width[j] + gap )) "$cell"
        out+=$seg
      else
        out+=$cell
      fi
    done
    if (( r < 0 )); then TABLE_HEADER=$out; else new+=("$out"); fi
  done
  if (( n > 0 )); then TABLE_ROWS=("${new[@]}"); fi
  return 0
}

# box_rule <n> - n box-horizontal chars into $RULE (string ops only, no forks)
box_rule() {
  printf -v RULE '%*s' "$1" ''
  RULE=${RULE// /$BOX_H}
}

# Full redraw, built as one string and printed once (single write = no flicker).
# \e[K per line + \e[J at the end instead of \e[2J avoids full-screen flash.
table_draw() {
  (( LAYOUT_COLS != COLS )) && table_reflow   # terminal was resized
  local msg_lines=0 info_n=${#INFO_LINES[@]} head_lines=1
  [[ -n $TABLE_MSG ]] && msg_lines=1
  # detail views (describe/logs) have no column header - reclaim that line
  [[ -n $DETAIL_VIEW && -z $TABLE_HEADER ]] && head_lines=0
  local inner=$(( COLS - 2 ))
  (( inner < 10 )) && inner=10
  # info block, top border(title), [column header], [msg], bottom border, footer
  local body_h=$(( ROWS - 3 - head_lines - msg_lines - info_n ))
  (( body_h < 1 )) && body_h=1
  local n=${#TABLE_ROWS[@]}

  # clamp cursor, then scroll window to keep cursor visible
  (( CURSOR >= n )) && CURSOR=$(( n > 0 ? n - 1 : 0 ))
  (( CURSOR < 0 )) && CURSOR=0
  (( SCROLL > CURSOR )) && SCROLL=$CURSOR
  (( CURSOR >= SCROLL + body_h )) && SCROLL=$(( CURSOR - body_h + 1 ))
  (( SCROLL < 0 )) && SCROLL=0
  if [[ -n $DETAIL_VIEW ]]; then
    # text viewer: cursor IS the scroll position; stop at the last full page
    (( CURSOR > n - body_h )) && CURSOR=$(( n - body_h ))
    (( CURSOR < 0 )) && CURSOR=0
    SCROLL=$CURSOR
  fi

  local buf=$'\e[H' line i row title tlen left right

  # info lines carry their own segment colors and fixed-width padding -
  # don't pad here (printf width would count the escape bytes)
  for (( i = 0; i < info_n; i++ )); do
    buf+="${INFO_LINES[i]}"$'\e[K\r\n'
  done

  # top border with the title centered inside the rule; width math always uses
  # the plain title (escape bytes have no visible width)
  # [N] is the row count - meaningful for a resource list, but in detail views
  # (describe/logs/help) TABLE_ROWS holds text lines, so the count is noise
  local tdisp count="[${n}]"
  [[ -n $DETAIL_VIEW ]] && count=""
  title=" ${TABLE_TITLE}${count} "
  tlen=${#title}
  if (( tlen > inner )); then
    title=${title:0:inner}
    tlen=$inner
    tdisp=$'\e[1m'"${title}"$'\e[22m'
  elif [[ -n $TABLE_TITLE_C ]]; then
    tdisp=" ${TABLE_TITLE_C}"$'\e[36m'"${count}"$'\e[0m'" "
  else
    tdisp=$'\e[1m'"${title}"$'\e[22m'
  fi
  left=$(( (inner - tlen) / 2 ))
  right=$(( inner - tlen - left ))
  box_rule "$left";  line="${BOX_TL}${RULE}"
  box_rule "$right"
  buf+="${line}${tdisp}${RULE}${BOX_TR}"$'\e[K\r\n'

  # column header (inside the box) - marker is a display-only overlay, rebuilt
  # each frame on the pristine header so resize/error ticks never desync it.
  # Skipped in detail views (no columns) so the body starts right under the title.
  if (( head_lines )); then
    table_mark_sort
    printf -v line '%-*.*s' "$inner" "$inner" " $MARKED_HEADER"
    buf+="${BOX_V}"$'\e[1m'"$line"$'\e[22m'"${BOX_V}"$'\e[K\r\n'
  fi

  if (( msg_lines )); then
    printf -v line '%-*.*s' "$inner" "$inner" " $TABLE_MSG"
    buf+="${BOX_V}"$'\e[31m'"$line"$'\e[0m'"${BOX_V}"$'\e[K\r\n'
  fi

  local dk dv
  for (( i = SCROLL; i < SCROLL + body_h; i++ )); do
    if (( i < n )); then
      row="${TABLE_ROWS[i]}"
      if [[ -n $DETAIL_VIEW ]]; then
        # describe text: cyan "Key:" prefix, value tinted by status words.
        # Pad/truncate BEFORE splitting so escape bytes never affect widths.
        printf -v line '%-*.*s' "$inner" "$inner" " ${row}"
        row_color "$row"
        dk=${line%%:*}
        if [[ -n $DETAIL_KV && $line == *:* && ${#dk} -le 40 ]]; then
          dv=${line#*:}
          buf+="${BOX_V}${DKEY_SGR}${dk}"$'\e[0m'":${ROW_SGR}${dv}"$'\e[0m'"${BOX_V}"
        else
          buf+="${BOX_V}${ROW_SGR}${line}"$'\e[0m'"${BOX_V}"
        fi
      elif (( i == CURSOR )); then
        # selection bar: white background, black text - reliable contrast
        # across terminal themes (bright-blue backgrounds render illegibly
        # in some, e.g. macOS Terminal.app default profiles)
        printf -v line '%-*.*s' "$inner" "$inner" ">${row}"
        buf+="${BOX_V}"$'\e[107;30m'"$line"$'\e[0m'"${BOX_V}"
      else
        row_color "$row"
        printf -v line '%-*.*s' "$inner" "$inner" " ${row}"
        buf+="${BOX_V}${ROW_SGR}${line}"$'\e[0m'"${BOX_V}"
      fi
    else
      printf -v line '%-*.*s' "$inner" "$inner" ""
      buf+="${BOX_V}${line}${BOX_V}"
    fi
    buf+=$'\e[K\r\n'
  done

  box_rule "$inner"
  buf+="${BOX_BL}${RULE}${BOX_BR}"$'\e[K\r\n'

  if [[ -n $TABLE_FOOT ]]; then
    line=" $TABLE_FOOT"
  else
    printf -v line ' ?:help  o/O:sort  a:resources  r:refresh  0:all-ns  Esc:clear-filter  [%dx%d]' "$COLS" "$ROWS"
  fi
  pad "$line"
  buf+=$'\e[7m'"$PADDED"$'\e[27m\e[J'

  printf '%s' "$buf"
}
