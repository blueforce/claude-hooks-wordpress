#!/bin/bash
# Notification: meldet sich, wenn Claude Code auf eine Eingabe wartet.
# Auf macOS per osascript, weil Terminal.app die OSC-777-Sequenz nicht kennt.
# Auf allen anderen Systemen per terminalSequence, das auch in tmux funktioniert.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/_lib.sh"
require_jq

input=$(cat)
body=$(jq -r '.message // "Claude Code braucht deine Aufmerksamkeit"' <<<"$input")

if [ "$(uname)" = "Darwin" ] && command -v osascript >/dev/null 2>&1; then
  osascript -e "display notification \"${body//\"/}\" with title \"Claude Code\"" >/dev/null 2>&1
  exit 0
fi

seq=$(printf '\033]777;notify;%s;%s\007' "Claude Code" "$body")
jq -nc --arg seq "$seq" '{terminalSequence: $seq}'
exit 0
