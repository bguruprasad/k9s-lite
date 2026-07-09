# table.sh — table view state and rendering.
# State: TABLE_ROWS (one preformatted line per item), CURSOR, SCROLL.

TABLE_TITLE=""
TABLE_HEADER=""
INFO_LINES=()      # k9s-style header block (context/cluster/user/ver + key map)
TABLE_ROWS=()
TABLE_MSG=""       # rendered in red under the header when set (errors, empty list)
TABLE_FOOT=""      # overrides the default footer hint when set (picker mode)
CURSOR=0
SCROLL=0
ROW_SGR=""

table_move() {
  CURSOR=$(( CURSOR + $1 ))   # clamped in table_draw
}

table_top()    { CURSOR=0; }
table_bottom() { CURSOR=$(( ${#TABLE_ROWS[@]} - 1 )); }

# row_color <row> — set ROW_SGR by status keyword (no subshell)
row_color() {
  case "$1" in
    *CrashLoopBackOff*|*Error*|*Failed*|*Evicted*|*ImagePull*) ROW_SGR=$'\e[31m' ;;
    *Pending*|*ContainerCreating*|*Terminating*|*Init:*|*Warning*) ROW_SGR=$'\e[33m' ;;
    *Completed*)                                               ROW_SGR=$'\e[90m' ;;
    *Running*)                                                 ROW_SGR=$'\e[32m' ;;
    *)                                                         ROW_SGR="" ;;
  esac
}

# Full redraw, built as one string and printed once (single write = no flicker).
# \e[K per line + \e[J at the end instead of \e[2J avoids full-screen flash.
table_draw() {
  local msg_lines=0 info_n=${#INFO_LINES[@]}
  [[ -n $TABLE_MSG ]] && msg_lines=1
  # info block, title, column header, [msg], footer
  local body_h=$(( ROWS - 3 - msg_lines - info_n ))
  (( body_h < 1 )) && body_h=1
  local n=${#TABLE_ROWS[@]}

  # clamp cursor, then scroll window to keep cursor visible
  (( CURSOR >= n )) && CURSOR=$(( n > 0 ? n - 1 : 0 ))
  (( CURSOR < 0 )) && CURSOR=0
  (( SCROLL > CURSOR )) && SCROLL=$CURSOR
  (( CURSOR >= SCROLL + body_h )) && SCROLL=$(( CURSOR - body_h + 1 ))
  (( SCROLL < 0 )) && SCROLL=0

  local buf=$'\e[H' line i row

  for (( i = 0; i < info_n; i++ )); do
    pad "${INFO_LINES[i]}"
    buf+=$'\e[36m'"$PADDED"$'\e[0m\r\n'
  done

  printf -v line ' k9s-lite  %s  (%d)' "$TABLE_TITLE" "$n"
  pad "$line"
  buf+=$'\e[7m'"$PADDED"$'\e[27m\r\n'

  pad "  $TABLE_HEADER"
  buf+=$'\e[1m'"$PADDED"$'\e[22m\r\n'

  if (( msg_lines )); then
    pad "  $TABLE_MSG"
    buf+=$'\e[31m'"$PADDED"$'\e[0m\r\n'
  fi

  for (( i = SCROLL; i < SCROLL + body_h; i++ )); do
    if (( i < n )); then
      row="${TABLE_ROWS[i]}"
      if (( i == CURSOR )); then
        pad "> $row"
        buf+=$'\e[7m'"$PADDED"$'\e[27m'
      else
        row_color "$row"
        pad "  $row"
        buf+="${ROW_SGR}${PADDED}"$'\e[0m'
      fi
    fi
    buf+=$'\e[K\r\n'
  done

  if [[ -n $TABLE_FOOT ]]; then
    line=" $TABLE_FOOT"
  else
    printf -v line ' r:refresh  0:all-ns  c:context  g/G:top/btm  Esc:clear-filter  [%dx%d]' "$COLS" "$ROWS"
  fi
  pad "$line"
  buf+=$'\e[7m'"$PADDED"$'\e[27m\e[J'

  printf '%s' "$buf"
}
