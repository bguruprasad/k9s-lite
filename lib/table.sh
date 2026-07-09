# table.sh — table view state and rendering.
# State: TABLE_ROWS (one preformatted line per item), CURSOR, SCROLL.

TABLE_TITLE=""
TABLE_HEADER=""
TABLE_ROWS=()
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
    *Pending*|*ContainerCreating*|*Terminating*|*Init:*)       ROW_SGR=$'\e[33m' ;;
    *Completed*)                                               ROW_SGR=$'\e[90m' ;;
    *Running*)                                                 ROW_SGR=$'\e[32m' ;;
    *)                                                         ROW_SGR="" ;;
  esac
}

# Full redraw, built as one string and printed once (single write = no flicker).
# \e[K per line + \e[J at the end instead of \e[2J avoids full-screen flash.
table_draw() {
  local body_h=$(( ROWS - 3 ))          # title, column header, footer
  (( body_h < 1 )) && body_h=1
  local n=${#TABLE_ROWS[@]}

  # clamp cursor, then scroll window to keep cursor visible
  (( CURSOR >= n )) && CURSOR=$(( n > 0 ? n - 1 : 0 ))
  (( CURSOR < 0 )) && CURSOR=0
  (( SCROLL > CURSOR )) && SCROLL=$CURSOR
  (( CURSOR >= SCROLL + body_h )) && SCROLL=$(( CURSOR - body_h + 1 ))
  (( SCROLL < 0 )) && SCROLL=0

  local buf=$'\e[H' line i row

  printf -v line ' k9s-lite  %s  (%d)' "$TABLE_TITLE" "$n"
  pad "$line"
  buf+=$'\e[7m'"$PADDED"$'\e[27m\r\n'

  pad "  $TABLE_HEADER"
  buf+=$'\e[1m'"$PADDED"$'\e[22m\r\n'

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

  printf -v line ' j/k:move  g/G:top/bottom  q:quit  [%dx%d]' "$COLS" "$ROWS"
  pad "$line"
  buf+=$'\e[7m'"$PADDED"$'\e[27m\e[J'

  printf '%s' "$buf"
}
