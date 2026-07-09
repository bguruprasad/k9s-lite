# term.sh — terminal init/cleanup, size detection, key reading.
# Raw ANSI escapes only; no tput dependency (mintty-safe baseline).

ROWS=24
COLS=80
KEY=""

term_init() {
  # read -rsn1 handles raw input; stty is belt-and-braces (no-op on non-tty)
  stty -echo -icanon 2>/dev/null || true
  # alt screen, hide cursor, clear
  printf '\e[?1049h\e[?25l\e[2J\e[H'
  trap term_cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  term_update_size
}

term_cleanup() {
  printf '\e[0m\e[?25h\e[?1049l'
  stty sane 2>/dev/null || true
}

# mintty doesn't reliably deliver SIGWINCH into bash — poll size every tick instead
term_update_size() {
  local sz
  sz=$(stty size 2>/dev/null) || sz=""
  if [[ $sz == *" "* ]]; then
    ROWS=${sz% *}
    COLS=${sz#* }
  else
    ROWS=${LINES:-24}
    COLS=${COLUMNS:-80}
  fi
}

# Wait up to $1 seconds for a key. Returns 1 on timeout (= refresh tick).
# Sets KEY to the character, or a symbolic name: UP DOWN LEFT RIGHT HOME END
# PGUP PGDN ENTER ESC.
key_read() {
  local t="$1" c rest _
  IFS= read -rsn1 -t "$t" c || return 1
  if [[ $c == $'\e' ]]; then
    rest=""
    IFS= read -rsn2 -t 0.05 rest || true
    case "$rest" in
      '[A') KEY=UP ;;
      '[B') KEY=DOWN ;;
      '[C') KEY=RIGHT ;;
      '[D') KEY=LEFT ;;
      '[H') KEY=HOME ;;
      '[F') KEY=END ;;
      '[5') IFS= read -rsn1 -t 0.05 _ || true; KEY=PGUP ;;
      '[6') IFS= read -rsn1 -t 0.05 _ || true; KEY=PGDN ;;
      '[1') # mintty may send \e[1~ / \e[4~ for Home/End
            IFS= read -rsn1 -t 0.05 _ || true; KEY=HOME ;;
      '[4') IFS= read -rsn1 -t 0.05 _ || true; KEY=END ;;
      '')   KEY=ESC ;;
      *)    KEY=ESC ;;
    esac
  elif [[ -z $c ]]; then
    KEY=ENTER
  else
    KEY=$c
  fi
  return 0
}

# pad <text> — truncate/pad to terminal width into $PADDED.
# printf -v, NOT $(...): subshells are forks, and forks are slow under Git Bash
# on Windows — never spawn one per row in the draw loop.
pad() {
  printf -v PADDED '%-*.*s' "$COLS" "$COLS" "$1"
}
