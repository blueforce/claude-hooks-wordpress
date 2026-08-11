#!/bin/bash
# PreToolUse (Edit, Write, MultiEdit, NotebookEdit, Read):
# schützt Pfade, die nicht direkt bearbeitet werden sollen, und fragt nach,
# bevor Geheimnisdateien gelesen oder geändert werden.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/_lib.sh"
require_jq

input=$(cat)
file=$(jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' <<<"$input")
tool=$(jq -r '.tool_name // empty' <<<"$input")
[ -n "$file" ] || exit 0

# Geheimnis- und Konfigurationsdateien: gilt für Lesen und Schreiben gleichermassen.
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
    decide deny "Abhängigkeiten werden nicht von Hand editiert, Änderung gehört in composer.json bzw. package.json: $file" ;;
  */wp-admin/*|*/wp-includes/*)
    decide deny "WordPress-Core wird nicht gepatcht, stattdessen Hook, Filter oder Child-Theme verwenden: $file" ;;
  */dist/*|*/build/*|*/.git/*)
    decide deny "Generiertes oder internes Verzeichnis, bitte die Quelle ändern: $file" ;;
esac

# ── Eigene Sperrliste ────────────────────────────────────────────────────────
# Produktive Kundeninstanzen, eingefrorene Altsysteme, fremde Projekte: Pfade,
# die zwar beschreibbar sind, aber nie versehentlich getroffen werden dürfen.
# Die Muster stehen bewusst NICHT hier im Code, sondern in einer lokalen Datei,
# damit dieses Repo keine Kundennamen enthält.
#
# Quelle (die erste vorhandene gewinnt):
#   1. Umgebungsvariable CLAUDE_HOOKS_PROTECTED (Muster durch : getrennt)
#   2. $CLAUDE_PROJECT_DIR/.claude/protected-paths.txt
#   3. ~/.claude/protected-paths.txt
# Format der Datei: ein Glob-Muster pro Zeile, «#» leitet einen Kommentar ein.
# Entscheidung ist bewusst «ask» und nicht «deny»: gezielte Arbeit an so einem
# Pfad bleibt möglich, aber nie unbemerkt.
sperrliste=""
if [ -n "$CLAUDE_HOOKS_PROTECTED" ]; then
  sperrliste=$(printf '%s' "$CLAUDE_HOOKS_PROTECTED" | tr ':' '\n')
elif [ -n "$CLAUDE_PROJECT_DIR" ] && [ -f "$CLAUDE_PROJECT_DIR/.claude/protected-paths.txt" ]; then
  sperrliste=$(cat "$CLAUDE_PROJECT_DIR/.claude/protected-paths.txt")
elif [ -f "$HOME/.claude/protected-paths.txt" ]; then
  sperrliste=$(cat "$HOME/.claude/protected-paths.txt")
fi

if [ -n "$sperrliste" ]; then
  while IFS= read -r zeile; do
    muster="${zeile%%#*}"                    # Kommentar abschneiden
    # Leerraum mit Bash-Bordmitteln trimmen. Ein sed pro Zeile wäre hier ein
    # Subprozess pro Muster, und dieser Hook läuft bei jedem Dateizugriff.
    muster="${muster#"${muster%%[![:space:]]*}"}"
    muster="${muster%"${muster##*[![:space:]]}"}"
    [ -n "$muster" ] || continue
    # shellcheck disable=SC2254 -- Glob-Vergleich ist hier gewollt.
    case "$file" in
      $muster)
        decide ask "Geschützter Pfad laut eigener Sperrliste ($muster). Produktive oder fremde Instanz, bitte ausdrücklich bestätigen: $file" ;;
    esac
  done <<EOF
$sperrliste
EOF
fi

exit 0
