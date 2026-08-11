#!/bin/bash
# PreToolUse (Bash): bremst Befehle, die produktive Daten oder Live-Systeme treffen,
# und fängt Schreibzugriffe ab, die den Pfadschutz per Shell umgehen würden.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/_lib.sh"
require_jq

input=$(cat)
cmd=$(jq -r '.tool_input.command // empty' <<<"$input")
[ -n "$cmd" ] || exit 0

# Schreibzugriffe auf entfernte WordPress-Datenbanken zuerst prüfen: fehlt ein
# frischer Snapshot, gibt es keinen Rollback-Punkt, und das wiegt schwerer als
# alles Weitere hier. Der Teilprüfer gibt nur im Blockfall etwas aus.
DB_GUARD="$DIR/wp-db-guard.sh"
if [ -x "$DB_GUARD" ]; then
  db_entscheid=$(printf '%s' "$input" | "$DB_GUARD" 2>/dev/null)
  if [ -n "$db_entscheid" ]; then
    printf '%s\n' "$db_entscheid"
    exit 0
  fi
fi

# Hart blockiert: Löschbefehl, dessen Ziel exakt / oder ~ ist.
# Anführungszeichen werden für diese eine Prüfung entfernt, sonst käme
# rm -rf "/" an der Sperre vorbei. Bewusst als Regex, damit echte Pfade
# wie /var/www nicht mitblockiert werden.
clean=${cmd//\"/}
clean=${clean//\'/}
if [[ "$clean" =~ rm[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*(/|~|\$HOME)(\*)?([[:space:]]|\;|$) ]]; then
  decide deny "Löschbefehl direkt auf System- oder Home-Wurzel wird nicht ausgeführt."
fi

# Umgehung des Pfadschutzes über die Shell: geschützter Pfad plus Schreiboperation.
if [[ "$cmd" =~ (wp-includes|wp-admin|vendor/|node_modules) ]] &&
   [[ "$cmd" =~ (\>|tee[[:space:]]|sed[[:space:]]+-i|mv[[:space:]]|cp[[:space:]]|rsync[[:space:]]) ]]; then
  decide ask "Schreibzugriff auf einen geschützten Pfad über die Shell, das umgeht den Pfadschutz."
fi

case "$cmd" in
  *deploy*live*|*deploy*prod*)
    decide ask "Live-Deploy: vorher Backup prüfen und Staging bestätigen." ;;
  *"wp db reset"*|*"wp db drop"*|*"wp db import"*|*"DROP TABLE"*|*"DROP DATABASE"*|*"TRUNCATE "*)
    decide ask "Datenbankbefehl mit Datenverlust-Risiko." ;;
  *"git push --force"*|*"git push -f"*|*"git reset --hard"*|*"git clean -fd"*)
    decide ask "Git-Befehl, der Arbeit unwiderruflich überschreibt." ;;
  *"rm -rf"*|*"rm -fr"*)
    decide ask "Rekursives Löschen: Pfad bitte gegenlesen." ;;
  *"chmod 777"*)
    decide ask "chmod 777 auf einem Webserver ist ein Sicherheitsrisiko." ;;
esac

exit 0
