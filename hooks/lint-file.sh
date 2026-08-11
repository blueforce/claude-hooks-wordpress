#!/bin/bash
# PostToolUse (Edit, Write, MultiEdit): prüft geschriebene Dateien auf Syntax.
# PHP per php -l, JSON per jq. Ein Fehler geht per Exit 2 zurück an Claude.
# Grund für JSON: eine kaputte theme.json legt den Block-Editor lahm,
# eine kaputte composer.json oder package.json blockiert jeden Build.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/_lib.sh"
require_jq

input=$(cat)
file=$(jq -r '.tool_input.file_path // empty' <<<"$input")
[ -n "$file" ] && [ -f "$file" ] || exit 0

fail() {
  {
    echo "$1"
    echo "$2"
    echo "Bitte korrigieren, bevor etwas deployt wird."
  } >&2
  exit 2
}

case "$file" in
  *.php)
    PHP_BIN=$(command -v php 2>/dev/null)
    if [ -z "$PHP_BIN" ]; then
      # MAMP-Installation als Rückfallebene, höchste vorhandene Version.
      PHP_BIN=$(ls -d /Applications/MAMP/bin/php/php*/bin/php 2>/dev/null | sort | tail -1)
    fi
    [ -x "$PHP_BIN" ] || exit 0
    out=$("$PHP_BIN" -l "$file" 2>&1) || fail "PHP-Syntaxfehler in $file" "$out"
    ;;
  *.json)
    out=$(jq empty "$file" 2>&1) || fail "Ungültiges JSON in $file" "$out"
    ;;
esac

exit 0
