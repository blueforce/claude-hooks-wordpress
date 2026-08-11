#!/bin/bash
# Wird von den anderen Hooks eingebunden. Enthaelt die jq-Pruefung und die
# Ausgabefunktionen. Ohne diese Pruefung waeren alle Guards bei fehlendem jq
# still wirkungslos, der Schutz faellt sonst lautlos aus.

require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    printf '{"systemMessage":"Claude-Code-Hook inaktiv: jq ist nicht installiert. Behebung: brew install jq"}\n'
    exit 0
  fi
}

# decide <allow|deny|ask> <Begruendung>
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
