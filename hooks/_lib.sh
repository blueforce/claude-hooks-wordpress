#!/bin/bash
# Wird von den anderen Hooks eingebunden. Enthält die jq-Prüfung und die
# Ausgabefunktionen. Ohne diese Prüfung wären alle Guards bei fehlendem jq
# still wirkungslos, der Schutz fällt sonst lautlos aus.

require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    printf '{"systemMessage":"Claude-Code-Hook inaktiv: jq ist nicht installiert. Behebung: brew install jq"}\n'
    exit 0
  fi
}

# decide <allow|deny|ask> <Begründung>
decide() {
  jq -n --arg d "$1" --arg r "$2" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: $d,
      permissionDecisionReason: $r
    }
  }'
  exit 0
}
