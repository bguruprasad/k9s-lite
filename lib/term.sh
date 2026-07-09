# term.sh — terminal init/cleanup, size detection, key reading.
# Raw ANSI escapes only; no tput dependency (mintty-safe baseline).
# Works on bash 3.2+ (macOS /bin/bash) and bash 5 (Git Bash, Linux).

ROWS=24
COLS=80
KEY=""

# bash 3.2 rejects fractional read timeouts; use 1s there. Costs only a bare-ESC
# press feeling slower — escape *sequences* arrive as a burst so decoding is unaffected.
if (( BASH_VERSINFO[0] >= 4 )); then ESC_T=0.05; else ESC_T=1; fi

term_init() {
  # read -rsn1 handles raw input; stty is belt-and-braces (no-op on non-tty)
  stty -echo -icanon 2>/dev/null || true
  # alt screen, hide cursor, clear, SGR mouse reporting (wheel scroll)
  printf '\e[?1049h\e[?25l\e[2J\e[H\e[?1000h\e[?1006h'
  trap term_cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  term_update_size
}

term_cleanup() {
  printf '\e[?1006l\e[?1000l\e[0m\e[?25h\e[?1049l'
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
  # some ptys report 0x0 (e.g. script(1) without a real terminal) — fall back sane
  (( ROWS < 5 ))  && ROWS=24
  (( COLS < 20 )) && COLS=80
}

# read one follow-up byte of an escape sequence into $SEQ; empty on timeout
seq_byte() {
  SEQ=""
  IFS= read -rsn1 -t "$ESC_T" SEQ 2>/dev/null || SEQ=""
}

# Wait up to $1 seconds for a key. Returns 1 on timeout (= refresh tick).
# Sets KEY to the character, or a symbolic name: UP DOWN LEFT RIGHT HOME END
# PGUP PGDN ENTER ESC WHEEL_UP WHEEL_DOWN MOUSE.
key_read() {
  local t="$1" c
  IFS= read -rsn1 -t "$t" c || return 1

  if [[ $c != $'\e' ]]; then
    # Enter arrives as NL (read delimiter -> empty) or CR depending on tty mode
    if [[ -z $c || $c == $'\r' ]]; then KEY=ENTER; else KEY=$c; fi
    return 0
  fi

  seq_byte
  case "$SEQ" in
    O)  # application cursor mode (some terminals): \eOA..\eOD
      seq_byte
      case "$SEQ" in
        A) KEY=UP ;;  B) KEY=DOWN ;;  C) KEY=RIGHT ;;  D) KEY=LEFT ;;
        H) KEY=HOME ;;  F) KEY=END ;;  *) KEY=ESC ;;
      esac ;;
    '[')
      seq_byte
      case "$SEQ" in
        A) KEY=UP ;;  B) KEY=DOWN ;;  C) KEY=RIGHT ;;  D) KEY=LEFT ;;
        H) KEY=HOME ;;  F) KEY=END ;;
        1|7) seq_byte; KEY=HOME ;;   # \e[1~ / \e[7~
        4|8) seq_byte; KEY=END ;;    # \e[4~ / \e[8~
        5) seq_byte; KEY=PGUP ;;     # \e[5~
        6) seq_byte; KEY=PGDN ;;     # \e[6~
        '<')  # SGR mouse: \e[<btn;col;rowM (press) or m (release)
          local mouse="" btn
          while seq_byte && [[ -n $SEQ ]]; do
            [[ $SEQ == M || $SEQ == m ]] && break
            mouse+="$SEQ"
          done
          btn=${mouse%%;*}
          if [[ $SEQ == M ]]; then
            case "$btn" in
              64) KEY=WHEEL_UP ;;
              65) KEY=WHEEL_DOWN ;;
              *)  KEY=MOUSE ;;
            esac
          else
            KEY=MOUSE
          fi ;;
        *) KEY=ESC ;;
      esac ;;
    '') KEY=ESC ;;   # bare Esc press
    *)  KEY=ESC ;;
  esac
  return 0
}

# pad <text> — truncate/pad to terminal width into $PADDED.
# printf -v, NOT $(...): subshells are forks, and forks are slow under Git Bash
# on Windows — never spawn one per row in the draw loop.
pad() {
  printf -v PADDED '%-*.*s' "$COLS" "$COLS" "$1"
}
