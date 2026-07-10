#!/usr/bin/env bash
# Concatenate k9s-lite.sh + lib/*.sh into one self-contained script - for
# environments where you can only carry a single file onto a box (no git
# clone, no directory structure). Output: dist/k9s-lite.dist.sh
#
# Usage: hack/build-dist.sh
set -eu
cd "$(dirname "$0")/.."

SRC=k9s-lite.sh
OUT=dist/k9s-lite.dist.sh
mkdir -p dist

# lib load order must match the `source` lines in k9s-lite.sh
LIBS="lib/config.sh lib/term.sh lib/table.sh lib/kube.sh lib/actions.sh"

{
  # shebang + the header comment block (everything up to the first blank
  # line after "set -u") comes from the main script, unchanged
  sed -n '1,/^set -u$/p' "$SRC"
  echo

  for f in $LIBS; do
    echo "# ---- inlined: $f ----"
    # drop each lib's own shellcheck directive/leading comment banner is fine
    # to keep; only the eventual `source` lines in $SRC need removing (below)
    cat "$f"
    echo
  done

  echo "# ---- inlined: $SRC (body) ----"
  # everything after the source lines: skip the shebang/header/set -u/sources
  # block we already emitted above, and the "source lib/..." lines themselves
  sed -n '/^set -u$/,$p' "$SRC" | tail -n +2 | grep -v '^source "\$K9L_ROOT/lib/'
} > "$OUT"

chmod +x "$OUT"

bash -n "$OUT"
echo "built: $OUT ($(wc -l < "$OUT" | tr -d ' ') lines)"
