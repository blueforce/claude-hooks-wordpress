#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# wp-db-guard.sh — Schreibschutz fuer entfernte WordPress-Datenbanken.
#
# Wird von guard-bash.sh (PreToolUse, Bash) aufgerufen und blockt Remote-DB-
# SCHREIBzugriffe ueber ssh, solange kein frischer Snapshot existiert. Damit
# kann ein Eingriff nie ohne Rollback-Punkt passieren — deterministisch, nicht
# nur als Absichtserklaerung in einer Projektregel.
#
# Liest PreToolUse-JSON von stdin (.tool_input.command) und entscheidet:
#   - kein Treffer, lokaler Aufruf oder frischer Snapshot  -> erlauben (keine Ausgabe)
#   - Remote-DB-Schreibzugriff ohne frischen Snapshot      -> deny (JSON)
#
# Frische = irgendeine Marker-Datei unter MARKERDIR, juenger als FRESH_MIN.
# Den Marker schreibt das eigene Snapshot-Werkzeug nach erfolgreichem Sichern.
#
# Konfigurierbar per Umgebungsvariable:
#   WP_DB_GUARD_FRESH_MIN   Frischefenster in Minuten            (Default 30)
#   WP_DB_GUARD_MARKERDIR   Verzeichnis der Snapshot-Marker
#   WP_DB_GUARD_HINT        Projektspezifischer Behebungshinweis in der Meldung
# ─────────────────────────────────────────────────────────────────────────────
FRESH_MIN="${WP_DB_GUARD_FRESH_MIN:-30}"
MARKERDIR="${WP_DB_GUARD_MARKERDIR:-$HOME/.cache/wp-db-snapshots}"
HINT="${WP_DB_GUARD_HINT:-Zuerst einen Snapshot der Ziel-Datenbank ziehen, danach denselben Befehl wiederholen.}"

# jq fehlt -> nicht blockieren (fail-open NUR hier: ohne jq laesst sich die
# Eingabe nicht zuverlaessig parsen, und ein Hook soll die Arbeit nicht
# grundlos lahmlegen).
command -v jq >/dev/null 2>&1 || exit 0

cmd="$(jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -n "$cmd" ] || exit 0

# Nur entfernte Eingriffe sind gefaehrlich. Lokale wp-cli-Aufrufe auf der
# Entwicklungsumgebung bleiben frei.
# scp und rsync gehoeren zwingend dazu: eine Datenbankdatei ueber die entfernte
# zu schieben ist der destruktivste Fall und enthaelt das Wort «ssh» nicht.
printf '%s' "$cmd" | grep -qE '\b(ssh|scp|rsync)\b' || exit 0

# Schreibt der Befehl in die Datenbank?
# Bewusst NICHT: plugin/core/theme update (das ist Code, keine Inhalte).
danger=0
printf '%s' "$cmd" | grep -qE '\b(post|term|user|comment|option|site|post-meta|term-meta|user-meta|postmeta|usermeta)[[:space:]]+(update|delete)\b' && danger=1
if printf '%s' "$cmd" | grep -qE '\bsearch-replace\b' && ! printf '%s' "$cmd" | grep -qE '\-\-dry-run'; then danger=1; fi
printf '%s' "$cmd" | grep -qE '\bdb[[:space:]]+(import|reset|drop)\b' && danger=1
# «db query» nur blocken, wenn die Abfrage wirklich schreibt. Reine
# SELECT/SHOW/DESCRIBE/EXPLAIN sind lesend und werden durchgelassen.
if printf '%s' "$cmd" | grep -qE '\bdb[[:space:]]+query\b' && \
   printf '%s' "$cmd" | grep -qiE '\b(insert|update|delete|drop|alter|truncate|create|grant|revoke|replace[[:space:]]+into)\b'; then danger=1; fi

# Eine komplette Datenbank per scp/rsync ueber die entfernte Datei schieben ist
# der destruktivste Fall ueberhaupt und wurde bisher gar nicht erfasst.
if printf '%s' "$cmd" | grep -qE '\b(scp|rsync)\b' && \
   printf '%s' "$cmd" | grep -qE '\.(sql|sqlite|sqlite3|db)(\.gz|\.zip|\.bz2)?\b'; then danger=1; fi

[ "$danger" -eq 1 ] || exit 0

# Frischer Snapshot vorhanden?
if [ -d "$MARKERDIR" ] && find "$MARKERDIR" -type f -mmin "-$FRESH_MIN" 2>/dev/null | grep -q .; then
  exit 0
fi

# Kein frischer Snapshot -> blockieren, mit konkreter Handlungsanweisung.
if command -v jq >/dev/null 2>&1; then
  jq -n --arg r "Remote-Schreibzugriff auf eine WordPress-Datenbank ohne frischen Snapshot (juenger als ${FRESH_MIN} Minuten). ${HINT}" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $r
    }
  }'
fi
exit 0
