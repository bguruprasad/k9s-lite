# table.sh — table view state and rendering.
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

# box_rule <n> — n box-horizontal chars into $RULE (string ops only, no forks)
box_rule() {
  printf -v RULE '%*s' "$1" ''
  RULE=${RULE// /$BOX_H}
}

# Full redraw, built as one string and printed once (single write = no flicker).
# \e[K per line + \e[J at the end instead of \e[2J avoids full-screen flash.
table_draw() {
  local msg_lines=0 info_n=${#INFO_LINES[@]}
  [[ -n $TABLE_MSG ]] && msg_lines=1
  local inner=$(( COLS - 2 ))
  (( inner < 10 )) && inner=10
  # info block, top border(title), column header, [msg], bottom border, footer
  local body_h=$(( ROWS - 4 - msg_lines - info_n ))
  (( body_h < 1 )) && body_h=1
  local n=${#TABLE_ROWS[@]}

  # clamp cursor, then scroll window to keep cursor visible
  (( CURSOR >= n )) && CURSOR=$(( n > 0 ? n - 1 : 0 ))
  (( CURSOR < 0 )) && CURSOR=0
  (( SCROLL > CURSOR )) && SCROLL=$CURSOR
  (( CURSOR >= SCROLL + body_h )) && SCROLL=$(( CURSOR - body_h + 1 ))
  (( SCROLL < 0 )) && SCROLL=0

  local buf=$'\e[H' line i row title tlen left right

  # info lines carry their own segment colors and fixed-width padding —
  # don't pad here (printf width would count the escape bytes)
  for (( i = 0; i < info_n; i++ )); do
    buf+="${INFO_LINES[i]}"$'\e[K\r\n'
  done

  # top border with the title centered inside the rule; width math always uses
  # the plain title (escape bytes have no visible width)
  local tdisp
  title=" ${TABLE_TITLE}[${n}] "
  tlen=${#title}
  if (( tlen > inner )); then
    title=${title:0:inner}
    tlen=$inner
    tdisp=$'\e[1m'"${title}"$'\e[22m'
  elif [[ -n $TABLE_TITLE_C ]]; then
    tdisp=" ${TABLE_TITLE_C}"$'\e[36m'"[${n}]"$'\e[0m'" "
  else
    tdisp=$'\e[1m'"${title}"$'\e[22m'
  fi
  left=$(( (inner - tlen) / 2 ))
  right=$(( inner - tlen - left ))
  box_rule "$left";  line="${BOX_TL}${RULE}"
  box_rule "$right"
  buf+="${line}${tdisp}${RULE}${BOX_TR}"$'\e[K\r\n'

  # column header (inside the box)
  printf -v line '%-*.*s' "$inner" "$inner" " $TABLE_HEADER"
  buf+="${BOX_V}"$'\e[1m'"$line"$'\e[22m'"${BOX_V}"$'\e[K\r\n'

  if (( msg_lines )); then
    printf -v line '%-*.*s' "$inner" "$inner" " $TABLE_MSG"
    buf+="${BOX_V}"$'\e[31m'"$line"$'\e[0m'"${BOX_V}"$'\e[K\r\n'
  fi

  for (( i = SCROLL; i < SCROLL + body_h; i++ )); do
    if (( i < n )); then
      row="${TABLE_ROWS[i]}"
      if (( i == CURSOR )); then
        # k9s-style selection bar: light-blue background, black text
        printf -v line '%-*.*s' "$inner" "$inner" ">${row}"
        buf+="${BOX_V}"$'\e[104;30m'"$line"$'\e[0m'"${BOX_V}"
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
    printf -v line ' a:resources  r:refresh  0:all-ns  c:context  g/G:top/btm  Esc:clear-filter  [%dx%d]' "$COLS" "$ROWS"
  fi
  pad "$line"
  buf+=$'\e[7m'"$PADDED"$'\e[27m\e[J'

  printf '%s' "$buf"
}
