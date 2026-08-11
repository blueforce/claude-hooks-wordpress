#!/bin/bash
# PreToolUse (Edit, Write, MultiEdit, NotebookEdit, Read):
# schuetzt Pfade, die nicht direkt bearbeitet werden sollen, und fragt nach,
# bevor Geheimnisdateien gelesen oder geaendert werden.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/_lib.sh"
require_jq

input=$(cat)
file=$(jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' <<<"$input")
tool=$(jq -r '.tool_name // empty' <<<"$input")
[ -n "$file" ] || exit 0

# Geheimnis- und Konfigurationsdateien: gilt fuer Lesen und Schreiben gleichermassen.
case "$file" in
  *wp-config.php|*.env|*.env.*|*secrets*.php|*/.htaccess|*id_rsa|*.pem)
    decide ask "Konfigurations- oder Geheimnisdatei ($tool): $file" ;;
esac

# Ab hier nur noch Schreibzugriffe.
case "$tool" in
  Read|Grep|Glob) exit 0 ;;
esac

case "$file" in
  */vendor/*|*/node_modules/*)
    decide deny "Abhaengigkeiten werden nicht von Hand editiert, Aenderung gehoert in composer.json bzw. package.json: $file" ;;
  */wp-admin/*|*/wp-includes/*)
    decide deny "WordPress-Core wird nicht gepatcht, stattdessen Hook, Filter oder Child-Theme verwenden: $file" ;;
  */dist/*|*/build/*|*/.git/*)
    decide deny "Generiertes oder internes Verzeichnis, bitte die Quelle aendern: $file" ;;
esac

exit 0
