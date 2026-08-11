#!/usr/bin/env python3
"""Vollstaendiger Pruefstand fuer die Claude-Code-Hooks.

Prueft drei Ebenen:
1. Vertrag   - haelt sich die Ausgabe an das dokumentierte JSON-Schema?
2. Verhalten - entscheidet jeder Hook bei realistischen Eingaben richtig?
3. Robustheit- was passiert bei kaputten, leeren oder exotischen Eingaben?
"""
import json
import os
import subprocess
import sys
import time

HOOKS = os.environ.get("HOOKS", os.path.expanduser("~/.claude/hooks"))

BASE = {
    "session_id": "test",
    "transcript_path": "/tmp/t.jsonl",
    "cwd": "/Users/rogerperren/Sites/kunde",
    "permission_mode": "default",
}

results = []


def run(script, payload_text):
    t0 = time.time()
    p = subprocess.run([os.path.join(HOOKS, script)], input=payload_text,
                       capture_output=True, text=True)
    return p, (time.time() - t0) * 1000


def classify(p):
    """Bildet die Hook-Ausgabe auf die Entscheidung ab, die Claude Code trifft."""
    if p.returncode == 2:
        return "block", None
    if p.returncode not in (0, 2):
        return f"exit{p.returncode}", "Exit-Code ausserhalb von 0 und 2"
    out = p.stdout.strip()
    if not out:
        return "allow", None
    try:
        data = json.loads(out)
    except json.JSONDecodeError:
        return "invalid", "stdout ist kein gueltiges JSON"
    hso = data.get("hookSpecificOutput")
    if hso:
        if hso.get("hookEventName") != "PreToolUse":
            return "invalid", "hookEventName fehlt oder falsch"
        d = hso.get("permissionDecision")
        if d not in ("allow", "deny", "ask"):
            return "invalid", f"unzulaessige permissionDecision: {d}"
        if not hso.get("permissionDecisionReason"):
            return "invalid", "Begruendung fehlt"
        return d, None
    if "terminalSequence" in data:
        return "notify", None
    if "systemMessage" in data:
        return "warn", None
    return "invalid", f"unbekannte Felder: {list(data)}"


def check(script, payload, expected, desc, raw=None):
    """expected darf ein Wert oder ein Tupel zulaessiger Werte sein."""
    text = raw if raw is not None else json.dumps({**BASE, **payload})
    p, ms = run(script, text)
    got, problem = classify(p)
    zulaessig = expected if isinstance(expected, tuple) else (expected,)
    ok = (got in zulaessig) and problem is None
    expected = " oder ".join(zulaessig)
    results.append((ok, expected, got, desc, problem, ms))


P = "protect-paths.sh"
G = "guard-bash.sh"
L = "lint-file.sh"
N = "notify.sh"


def bash(cmd):
    return {"tool_name": "Bash", "tool_input": {"command": cmd}}


def edit(path, tool="Edit"):
    return {"tool_name": tool, "tool_input": {"file_path": path}}


R = "/Users/rogerperren/Sites/kunde"

# --- Loeschbefehle -----------------------------------------------------------
check(G, bash("rm -rf /"), "deny", "rm -rf /")
check(G, bash("rm -rf /*"), "deny", "rm -rf /*")
check(G, bash('rm -rf "/"'), "deny", "rm -rf mit Anfuehrungszeichen")
check(G, bash("rm -rf '/'"), "deny", "rm -rf mit Hochkomma")
check(G, bash("rm -rf ~"), "deny", "rm -rf ~")
check(G, bash("rm -rf $HOME"), "deny", "rm -rf $HOME")
check(G, bash("sudo rm -rf / --no-preserve-root"), "deny", "sudo-Variante")
check(G, bash("rm -rf ./dist"), "ask", "rm -rf auf relativen Pfad")
check(G, bash("rm -rf /var/www/alt"), "ask", "rm -rf auf echten Pfad")
check(G, bash("rm datei.txt"), "allow", "einfaches rm ohne -rf")

# --- Deploy, Datenbank, Git --------------------------------------------------
check(G, bash("./deploy.sh live"), "ask", "Live-Deploy")
check(G, bash("./deploy.sh staging"), "allow", "Staging-Deploy")
check(G, bash("bash deploy.sh production"), "ask", "Deploy nach production")
check(G, bash("wp db reset --yes"), "ask", "wp db reset")
check(G, bash("mysql -e 'DROP DATABASE kunde'"), "ask", "DROP DATABASE")
check(G, bash("wp db export backup.sql"), "allow", "Datenbank-Export ist harmlos")
check(G, bash("git push --force origin main"), "ask", "Force-Push")
check(G, bash("git push origin main"), "allow", "normaler Push")
check(G, bash("git reset --hard HEAD~1"), "ask", "hartes Reset")
check(G, bash("chmod 777 wp-content/uploads"), "ask", "chmod 777")
check(G, bash("chmod 755 wp-content/uploads"), "allow", "chmod 755")

# --- Umgehung des Pfadschutzes ueber die Shell -------------------------------
check(G, bash("cat > wp-includes/version.php << 'EOF'\nx\nEOF"), "ask", "Core schreiben per Umleitung")
check(G, bash("sed -i '' 's/a/b/' vendor/lib.php"), "ask", "sed -i auf vendor")
check(G, bash("cp neu.php node_modules/x/alt.php"), "ask", "cp nach node_modules")
check(G, bash("grep -r foo wp-includes/"), "allow", "Core nur durchsuchen")
check(G, bash("cat wp-includes/version.php"), "allow", "Core nur lesen")

# --- Alltagsbefehle, die nicht stoeren duerfen -------------------------------
check(G, bash("npm run build"), "allow", "npm run build")
check(G, bash("composer install"), "allow", "composer install")
check(G, bash("rsync -av dist/ server:/var/www/"), "allow", "rsync eines Builds")
check(G, bash('echo "it'"'"'s fine" > /tmp/x'), "allow", "Apostroph im Befehl")
check(G, bash("echo $(date) && ls -la"), "allow", "Verkettung und Substitution")
check(G, bash("wp plugin list"), "allow", "wp-cli lesend")

# --- Pfadschutz --------------------------------------------------------------
check(P, edit(f"{R}/wp-includes/pluggable.php"), "deny", "Core-Datei schreiben")
check(P, edit(f"{R}/wp-admin/index.php", "Write"), "deny", "wp-admin schreiben")
check(P, edit(f"{R}/vendor/autoload.php"), "deny", "vendor schreiben")
check(P, edit(f"{R}/node_modules/x/index.js"), "deny", "node_modules schreiben")
check(P, edit(f"{R}/dist/app.js"), "deny", "dist schreiben")
check(P, edit(f"{R}/vendor/x.php", "MultiEdit"), "deny", "MultiEdit auf vendor")
check(P, {"tool_name": "NotebookEdit", "tool_input": {"notebook_path": f"{R}/vendor/a.ipynb"}}, "deny", "NotebookEdit auf vendor")
check(P, edit(f"{R}/wp-content/themes/bf/functions.php"), "allow", "eigenes Theme")
check(P, edit(f"{R}/wp-content/plugins/mein-plugin/mein-plugin.php"), "allow", "eigenes Plugin")
check(P, edit(f"{R}/wp-content/themes/bf/theme.json"), "allow", "theme.json des Themes")
check(P, edit(f"{R}/wp-content/themes/mein wp-admin theme/style.css"), "allow", "Leerzeichen und Falle im Ordnernamen")
check(P, edit(f"{R}/wp-content/themes/bf/tempÖÄÜ/style.css"), "allow", "Umlaute im Pfad")

# --- Geheimnisdateien --------------------------------------------------------
check(P, edit(f"{R}/wp-config.php"), "ask", "wp-config schreiben")
check(P, edit(f"{R}/.env", "Read"), "ask", "env lesen")
check(P, edit(f"{R}/.env.local", "Write"), "ask", "env.local schreiben")
check(P, edit(f"{R}/inc/secrets.php"), "ask", "secrets.php")
check(P, edit(f"{R}/.htaccess"), "ask", "htaccess")
check(P, edit(f"{R}/vendor/x.php", "Read"), "allow", "vendor lesen bleibt erlaubt")
check(P, edit(f"{R}/wp-includes/version.php", "Read"), "allow", "Core lesen bleibt erlaubt")
check(P, edit(f"{R}/wp-content/themes/bf/environment.php"), "allow", "environment.php ist kein env-Treffer")

# --- Robustheit --------------------------------------------------------------
check(G, {}, "allow", "leeres Objekt", raw="{}")
check(P, {}, "allow", "leeres Objekt", raw="{}")
check(G, {}, "allow", "leere Eingabe", raw="")
check(P, {}, "allow", "leere Eingabe", raw="")
check(G, {}, "allow", "kaputtes JSON", raw="{nicht json")
check(P, {}, "allow", "kaputtes JSON", raw="{nicht json")
check(P, edit(""), "allow", "leerer Dateipfad")
check(G, bash("x" * 5000), "allow", "sehr langer Befehl")
check(P, {"tool_name": "Edit", "tool_input": {}}, "allow", "tool_input ohne Pfad")
check(N, {"hook_event_name": "Notification", "message": "Freigabe noetig"}, ("notify", "allow"), "Benachrichtigung")
check(N, {"hook_event_name": "Notification"}, ("notify", "allow"), "Benachrichtigung ohne Text")


def main():
    if not os.path.isdir(HOOKS):
        print(f"Hook-Verzeichnis nicht gefunden: {HOOKS}")
        return 1
    fails = [r for r in results if not r[0]]
    slow = [r for r in results if r[5] > 500]
    for ok, exp, got, desc, problem, ms in results:
        if not ok:
            print(f"FEHLT   erwartet={exp:<7} ist={got:<7} {desc}"
                  + (f"  [{problem}]" if problem else ""))
    print(f"\n{len(results) - len(fails)} von {len(results)} Faellen wie erwartet")
    langsam = max(r[5] for r in results)
    print(f"langsamster Hook: {langsam:.0f} ms"
          f"{'  (auf macOS normal, osascript braucht kurz)' if langsam > 100 else ''}")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
