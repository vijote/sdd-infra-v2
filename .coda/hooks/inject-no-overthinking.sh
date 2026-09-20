#!/bin/bash
# UserPromptSubmit hook: enforce the "no-overthinking" rule on every prompt.
#
# Appends the rule body (frontmatter stripped) to the user's prompt before the
# model sees it, so the standing constraint is always in context.
#
# Input : JSON on stdin (includes .prompt and .cwd)
# Output: JSON on stdout with hookSpecificOutput.updatedPrompt

set -euo pipefail

# Resolve the rule file relative to this script so the hook works no matter
# which directory Coda was launched from.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RULE_FILE="$SCRIPT_DIR/../rules/no-overthinking.md"

# If the rule file is missing, pass the prompt through unchanged.
if [ ! -f "$RULE_FILE" ]; then
  exit 0
fi

# Strip the leading YAML frontmatter block (--- ... ---) if present.
if head -n1 "$RULE_FILE" | grep -q '^---'; then
  RULE_BODY="$(awk 'NR==1 && /^---[[:space:]]*$/{infm=1; next} infm && /^---[[:space:]]*$/{infm=0; next} !infm{print}' "$RULE_FILE")"
else
  RULE_BODY="$(cat "$RULE_FILE")"
fi

# Build the enhanced prompt and emit valid JSON via jq (safe escaping).
cat | jq --arg rule "$RULE_BODY" '
  .prompt as $p
  | .hookSpecificOutput = {
      hookEventName: "UserPromptSubmit",
      updatedPrompt: ($p + "\n\n[Standing rule — no-overthinking]\n" + $rule)
    }
'
