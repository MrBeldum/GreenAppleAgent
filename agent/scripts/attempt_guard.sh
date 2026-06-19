#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ENG_DIR="${1:?usage: attempt_guard.sh <engagement_dir> <vector> <agent>}"
VECTOR="${2:?}"
AGENT="${3:-operator}"

MAX_ATTEMPTS="${GREENAPPLE_MAX_ATTEMPTS_PER_VECTOR:-3}"

COUNT=$("$SCRIPT_DIR/htb_state.py" count-attempts "$ENG_DIR" --pattern "$VECTOR" 2>/dev/null || echo 0)

if [[ "$COUNT" -ge "$MAX_ATTEMPTS" ]]; then
  echo "BLOCKED: Vector '$VECTOR' attempted $COUNT times (limit: $MAX_ATTEMPTS)"
  echo "Revisit enumeration before retrying the same approach."
  "$SCRIPT_DIR/htb_state.py" add-dead-end "$ENG_DIR" \
    --vector "$VECTOR" \
    --reason "Attempt limit reached after $COUNT attempts" \
    --lessons "Must discover new information before retrying" 2>/dev/null || true
  exit 1
fi

"$SCRIPT_DIR/htb_state.py" add-attempt "$ENG_DIR" \
  --agent "$AGENT" \
  --vector "$VECTOR" \
  --result "attempt_${COUNT}" 2>/dev/null || true

echo "OK: Attempt $((COUNT + 1))/$MAX_ATTEMPTS for '$VECTOR'"
