# Claude Code Hooks für WordPress-Entwicklung

Ein kleines, getestetes Set an Hooks für Claude Code. Es prüft geschriebene Dateien auf Syntaxfehler, schützt Verzeichnisse, die niemand von Hand ändern sollte, und fragt nach, bevor etwas Unwiderrufliches passiert.

Version 1.0.0, getestet mit 63 Prüffällen. Zusammengestellt von [Blueforce Digital Solutions](https://blueforce.ch).

## Was drin ist

| Datei | Ereignis | Wirkung |
|---|---|---|
| `lint-file.sh` | PostToolUse | `php -l` auf PHP-Dateien, JSON-Prüfung auf `theme.json`, `package.json`, `composer.json`, `block.json`. Ein Fehler geht direkt an das Modell zurück und wird in derselben Runde korrigiert |
| `protect-paths.sh` | PreToolUse | lehnt Schreibzugriffe auf `vendor`, `node_modules`, `wp-admin`, `wp-includes`, `dist`, `build`, `.git` ab. Fragt nach bei `wp-config.php`, `.env`, `secrets*.php`, `.htaccess` und Schlüsseldateien, auch beim Lesen. Lesen von `vendor` und Core bleibt erlaubt |
| `guard-bash.sh` | PreToolUse | blockiert das Löschen von `/` und `~`. Fragt nach bei Live-Deploy, Datenbankbefehlen mit Datenverlust, `git push --force`, `git reset --hard`, `rm -rf`, `chmod 777` und bei Schreibzugriffen auf geschützte Pfade über die Shell |
| `notify.sh` | Notification | Systemmeldung, wenn Claude Code auf eine Freigabe wartet. macOS über `osascript`, sonst über eine Terminalsequenz |
| `_lib.sh` | wird eingebunden | Prüfung auf `jq` und die gemeinsame Entscheidungsausgabe. Kein eigener Hook |

## Voraussetzung

```bash
brew install jq
```

Zwingend. Ohne `jq` melden sich die Hooks mit einem Hinweis und lassen dann durch. Ein stiller Ausfall wäre gefährlicher als kein Hook, deshalb die Meldung.

## Installation für alle Projekte

```bash
mkdir -p ~/.claude/hooks
cp hooks/*.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/*.sh
xattr -d com.apple.quarantine ~/.claude/hooks/*.sh 2>/dev/null   # nur macOS
sed 's|${CLAUDE_PROJECT_DIR}|'"$HOME"'|g' settings.json > ~/.claude/settings.json
```

Der letzte Befehl überschreibt eine vorhandene `~/.claude/settings.json`. Prüfe vorher mit `cat ~/.claude/settings.json`. Ist dort schon etwas, übernimm nur den `hooks`-Block und ersetze `${CLAUDE_PROJECT_DIR}` von Hand durch deinen Home-Pfad.

## Installation für ein einzelnes Projekt

```bash
mkdir -p .claude/hooks
cp settings.json .claude/settings.json
cp hooks/*.sh .claude/hooks/
chmod +x .claude/hooks/*.sh
```

Hier bleibt `${CLAUDE_PROJECT_DIR}` unverändert, der Platzhalter zeigt von selbst auf den Projektstamm.

## Prüfen

```bash
python3 pruefstand.py
```

Erwartet: `63 von 63 Faellen wie erwartet`. Das Skript prüft die Hooks in `~/.claude/hooks`. Für einen anderen Ort:

```bash
HOOKS=/pfad/zu/hooks python3 pruefstand.py
```

Einzelfall von Hand:

```bash
echo '{"tool_name":"Bash","tool_input":{"command":"./deploy.sh live"}}' \
  | ~/.claude/hooks/guard-bash.sh
```

JSON mit `permissionDecision` bedeutet, die Regel greift. Keine Ausgabe bedeutet, der Befehl läuft durch.

In Claude Code zeigt `/hooks` alle konfigurierten Hooks samt Quelle.

## Anpassen

Die Muster stehen in `case`-Blöcken oben in den Skripten. `deny` lehnt ab, `ask` fragt nach. Nach jeder Änderung `pruefstand.py` laufen lassen, das fängt Tippfehler in regulären Ausdrücken ab, bevor sie im Alltag stören.

## Grenzen

Diese Hooks sind ein Stolperdraht, kein Sicherheitsmechanismus. Wer einen Pfad über eine Variable zusammensetzt oder ungewöhnlich schreibt, kommt daran vorbei. Für harte Sperren ist das Berechtigungssystem von Claude Code zuständig, also der `permissions`-Block. Die Hooks sind dafür da, dich vor eigenen Flüchtigkeitsfehlern zu schützen, nicht vor einem Angreifer.

Hooks laufen mit deinen Benutzerrechten. Lies jedes Skript, bevor du es installierst, hier wie bei jedem fremden Shell-Skript.

Getestet unter macOS mit Claude Code. Unter Linux funktioniert alles ausser der Systemmeldung, die dort eine Terminalsequenz nutzt und daher vom Terminal abhängt.

## Lizenz

MIT, siehe `LICENSE`. Nutzung auf eigene Verantwortung, ohne Gewähr.
