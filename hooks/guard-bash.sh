#!/bin/bash
# PreToolUse (Bash): bremst Befehle, die produktive Daten oder Live-Systeme treffen,
# und faengt Schreibzugriffe ab, die den Pfadschutz per Shell umgehen wuerden.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/_lib.sh"
require_jq

input=$(cat)
cmd=$(jq -r '.tool_input.command // empty' <<<"$input")
[ -n "$cmd" ] || exit 0

# Hart blockiert: Loeschbefehl, dessen Ziel exakt / oder ~ ist.
# Anfuehrungszeichen werden fuer diese eine Pruefung entfernt, sonst kaeme
# rm -rf "/" an der Sperre vorbei. Bewusst als Regex, damit echte Pfade
# wie /var/www nicht mitblockiert werden.
clean=${cmd//\"/}
clean=${clean//\'/}
if [[ "$clean" =~ rm[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*(/|~|\$HOME)(\*)?([[:space:]]|\;|$) ]]; then
  decide deny "Loeschbefehl direkt auf System- oder Home-Wurzel wird nicht ausgefuehrt."
fi

# Umgehung des Pfadschutzes ueber die Shell: geschuetzter Pfad plus Schreiboperation.
if [[ "$cmd" =~ (wp-includes|wp-admin|vendor/|node_modules) ]] &&
   [[ "$cmd" =~ (\>|tee[[:space:]]|sed[[:space:]]+-i|mv[[:space:]]|cp[[:space:]]|rsync[[:space:]]) ]]; then
  decide ask "Schreibzugriff auf einen geschuetzten Pfad ueber die Shell, das umgeht den Pfadschutz."
fi

case "$cmd" in
  *deploy*live*|*deploy*prod*)
    decide ask "Live-Deploy: vorher Backup pruefen und Staging bestaetigen." ;;
  *"wp db reset"*|*"wp db drop"*|*"wp db import"*|*"DROP TABLE"*|*"DROP DATABASE"*|*"TRUNCATE "*)
    decide ask "Datenbankbefehl mit Datenverlust-Risiko." ;;
  *"git push --force"*|*"git push -f"*|*"git reset --hard"*|*"git clean -fd"*)
    decide ask "Git-Befehl, der Arbeit unwiderruflich ueberschreibt." ;;
  *"rm -rf"*|*"rm -fr"*)
    decide ask "Rekursives Loeschen: Pfad bitte gegenlesen." ;;
  *"chmod 777"*)
    decide ask "chmod 777 auf einem Webserver ist ein Sicherheitsrisiko." ;;
esac

exit 0
