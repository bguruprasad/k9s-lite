#!/usr/bin/env bash
# Generate the GitHub Pages doc pages from README.md, so the README stays the
# single source of truth for install steps, the key map, and options. Edit
# README.md, re-run this, commit both.
#
# Output: docs/install.html, docs/commands.html, docs/features.html
#
# Usage: hack/build-docs.sh
#
# bash 3.2 compatible (macOS system bash), no dependencies beyond coreutils -
# same constraints as the tool itself, since anyone hacking on k9s-lite should
# be able to hack on its docs without installing a toolchain.
set -eu
cd "$(dirname "$0")/.."

README=README.md
OUT=docs

[ -f "$README" ] || { echo "build-docs: $README not found" >&2; exit 1; }
[ -d "$OUT" ] || { echo "build-docs: $OUT/ not found" >&2; exit 1; }

# --- page chrome -------------------------------------------------------------
# Shared with index.html: same stylesheet, same nav, so the docs pages and the
# landing page read as one site.
page_open() {
  # $1 = <title>, $2 = h1, $3 = active nav key
  cat <<HTML
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$1</title>
<link rel="stylesheet" href="k9l.css">
</head>
<body>
<div class="wrap">
<nav class="docnav">
  <a class="brand" href="./">k9s-lite</a>
  <a href="install.html"$([ "$3" = install ] && printf ' class="active"')>Installation</a>
  <a href="commands.html"$([ "$3" = commands ] && printf ' class="active"')>Commands</a>
  <a href="features.html"$([ "$3" = features ] && printf ' class="active"')>Features</a>
  <a href="https://github.com/bguruprasad/k9s-lite">GitHub</a>
</nav>
<main class="doc">
<h1>$2</h1>
HTML
}

page_close() {
  cat <<'HTML'
</main>
<footer>
  <p>Generated from README.md - do not edit these pages by hand.</p>
  <p>
    <a href="https://github.com/bguruprasad/k9s-lite">README</a> &middot;
    <a href="https://github.com/bguruprasad/k9s-lite/releases">Releases</a> &middot;
    <a href="https://github.com/bguruprasad/k9s-lite/blob/main/LICENSE">MIT License</a>
  </p>
</footer>
</div>
</body>
</html>
HTML
}

# --- README section extractor ------------------------------------------------
# section <heading>          body including nested subsections
# section <heading> own      body only, stopping at the first nested subsection
#
# "own" matters where a page wants a section's prose but places that section's
# subsections elsewhere: "## Options" holds the env-var table AND the nested
# "### Staying up to date" / "### Config file", which belong on other pages.
# Without it those subsections render twice, on two different pages.
section() {
  awk -v want="$1" -v mode="${2:-all}" '
    function level(s,   n) { n = 0; while (substr(s, n + 1, 1) == "#") n++; return n }
    BEGIN { wl = level(want); on = 0; fence = 0 }
    {
      if ($0 == want)          { on = 1; next }
      # Track fenced blocks: a "#" line inside one is code (the ini sample
      # opens with "# ~/.k9l/config"), not a heading. Without this the section
      # ends mid-block and its closing fence is lost, so every later section
      # renders inside a runaway <pre>.
      if (/^[ \t]*```/)        { fence = !fence }
      else if (on && !fence && /^#+ /) {
        if (level($0) <= wl)             { on = 0 }
        else if (mode == "own")          { on = 0 }
      }
      if (on) print
    }
  ' "$README"
}

# --- markdown block renderer -------------------------------------------------
# Reads markdown on stdin, writes HTML. Supports the block constructs the
# README uses: ATX headings, fenced code, pipe tables, "- " lists, paragraphs.
render() {
  awk '
    function esc(s) {
      gsub(/&/, "\\&amp;", s); gsub(/</, "\\&lt;", s); gsub(/>/, "\\&gt;", s)
      return s
    }
    # inline: `code`, **bold**, [text](url). Applied after esc() so the tags
    # emitted here survive; \x01/\x02 stand in for < > until the final swap.
    function inline(s) {
      s = esc(s)
      while (match(s, /`[^`]*`/)) {
        s = substr(s, 1, RSTART - 1) "\001code\002" substr(s, RSTART + 1, RLENGTH - 2) \
            "\001/code\002" substr(s, RSTART + RLENGTH)
      }
      while (match(s, /\*\*[^*]+\*\*/)) {
        s = substr(s, 1, RSTART - 1) "\001strong\002" substr(s, RSTART + 2, RLENGTH - 4) \
            "\001/strong\002" substr(s, RSTART + RLENGTH)
      }
      while (match(s, /\[[^]]*\]\([^)]*\)/)) {
        t = substr(s, RSTART, RLENGTH)
        p = index(t, "](")
        txt = substr(t, 2, p - 2)
        url = substr(t, p + 2, length(t) - p - 2)
        # README links are relative to the repo root (../../releases, LICENSE);
        # from docs/*.html those resolve nowhere, so point them at GitHub.
        if (url ~ /^\.\.\/\.\.\//) {
          sub(/^\.\.\/\.\.\//, "", url)
          url = "https://github.com/bguruprasad/k9s-lite/" url
        } else if (url !~ /^(https?:|#|mailto:)/) {
          url = "https://github.com/bguruprasad/k9s-lite/blob/main/" url
        }
        s = substr(s, 1, RSTART - 1) "\001a href=\"" url "\"\002" txt "\001/a\002" \
            substr(s, RSTART + RLENGTH)
      }
      gsub(/\001/, "<", s); gsub(/\002/, ">", s)
      return s
    }
    function closep() { if (inp) { print "</p>"; inp = 0 } }
    function closeli() { if (inli) { print "</li>"; inli = 0 } }
    function closelist() { closeli(); if (inlist) { print "</ul>"; inlist = 0 } }
    function closetable() { if (intable) { print "</tbody></table></div>"; intable = 0 } }
    function closeall() { closep(); closelist(); closetable() }

    BEGIN { inp = 0; inlist = 0; inli = 0; intable = 0; incode = 0 }

    # fenced code, possibly indented inside a list item. The closing fence must
    # match the opening one, so remember whether we opened from inside a list
    # and keep the <li> open across the block.
    /^[ \t]*```/ {
      if (incode) { print "</code></pre>"; incode = 0; next }
      closep(); closetable()
      if (!inlist) closelist()
      print "<pre><code>"
      incode = 1
      next
    }
    incode { line = $0; sub(/^  /, "", line); print esc(line); next }

    # headings (### and deeper become h3; ## is the page title, already emitted)
    /^#+ / {
      closeall()
      h = $0; sub(/^#+ +/, "", h)
      print "<h2>" inline(h) "</h2>"
      next
    }

    # table separator row - skip, it only marks the header
    /^\|[ :|-]+\|[ :|-]*$/ { next }

    # table rows
    /^\|/ {
      closep(); closelist()
      line = $0
      sub(/^\|/, "", line); sub(/\|[ \t]*$/, "", line)
      n = split(line, cell, /\|/)
      if (!intable) {
        print "<div class=\"tablewrap\"><table><thead><tr>"
        for (i = 1; i <= n; i++) { gsub(/^ +| +$/, "", cell[i]); print "<th>" inline(cell[i]) "</th>" }
        print "</tr></thead><tbody>"
        intable = 1
        next
      }
      print "<tr>"
      for (i = 1; i <= n; i++) { gsub(/^ +| +$/, "", cell[i]); print "<td>" inline(cell[i]) "</td>" }
      print "</tr>"
      next
    }

    # unordered list. <li> is closed lazily (by the next item, or by
    # closelist) so indented continuation lines join the same item.
    /^- / {
      closep(); closetable(); closeli()
      if (!inlist) { print "<ul>"; inlist = 1 }
      item = $0; sub(/^- +/, "", item)
      print "<li>" inline(item)
      inli = 1
      next
    }

    # blank line ends paragraphs and tables. A blank line inside a list is a
    # spacer between items, not the end of the list - the next non-indented,
    # non-"- " line closes it.
    /^[ \t]*$/ { closep(); closetable(); next }

    # continuation of a list item (indented under a "- ")
    /^  +/ && inli {
      item = $0; sub(/^ +/, "", item)
      print " " inline(item)
      next
    }

    # paragraph text (also ends any open list, since it is neither a "- "
    # item nor an indented continuation)
    {
      if (!inp) { closelist(); closetable(); print "<p>"; inp = 1 }
      print inline($0)
    }

    END { if (incode) print "</code></pre>"; closeall() }
  '
}

# --- landing-page feature list -----------------------------------------------
# The benefit-led feature list lives in docs/index.html (it is the landing
# page's pitch) and is lifted verbatim onto the features page, so the wording
# has one home. Prints the <ul class="featurelist"> block between the
# FEATURES:START/END markers, without the section heading around it.
featurelist() {
  awk '
    /FEATURES:START/ { on = 1; next }
    /FEATURES:END/   { on = 0 }
    on && /<ul class="featurelist">/ { grab = 1 }
    grab { print }
    on && /<\/ul>/ { grab = 0 }
  ' "$OUT/index.html"
}

# --- pages -------------------------------------------------------------------
# Each README subsection lands on exactly one page. "## Quick start" and
# "## Options" both nest subsections that belong elsewhere, so they are pulled
# with "own" and the subsections are placed explicitly, with their heading
# re-emitted (section() strips the heading it matched).
{
  page_open "Installation - k9s-lite" "Installation" install
  {
    section "## Quick start" own
    echo "### Requirements";       section "### Requirements"
    echo "### Staying up to date"; section "### Staying up to date"
  } | render
  page_close
} > "$OUT/install.html"

{
  page_open "Commands - k9s-lite" "Commands" commands
  section "## Keys" | render
  page_close
} > "$OUT/commands.html"

{
  page_open "Features - k9s-lite" "Features" features
  # the pitch first, lifted from the landing page (already HTML, so it skips
  # render), then the reference material from the README
  featurelist
  {
    echo "### Options and environment variables"
    section "## Options" own
    echo "### Config file"; section "### Config file"
    echo "### Why pure Bash?"; section "## Why pure Bash?"
    echo "### How it works";   section "## How it works" own
    echo "### Windows / Git Bash specifics"
    section "### Windows / Git Bash specifics"
  } | render
  page_close
} > "$OUT/features.html"

echo "build-docs: wrote $OUT/install.html $OUT/commands.html $OUT/features.html"
