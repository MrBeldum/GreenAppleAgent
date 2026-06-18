#!/usr/bin/env bash
# Start OpenCode for HTB VM use with local host tools and permissive autonomous execution.

set -euo pipefail

OPENCODE_BIN="${OPENCODE_BIN:-opencode}"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  . ./.env
  set +a
fi

export GREENAPPLE_RUNTIME_MODE="${GREENAPPLE_RUNTIME_MODE:-local}"

if ! command -v "$OPENCODE_BIN" >/dev/null 2>&1; then
  echo "ERROR: opencode not found. Install with: npm install -g opencode-ai" >&2
  exit 1
fi

help_text="$($OPENCODE_BIN --help 2>&1 || true)
$($OPENCODE_BIN run --help 2>&1 || true)"
flags=()

if [[ -n "${GREENAPPLE_OPENCODE_FLAGS:-}" ]]; then
  # shellcheck disable=SC2206
  flags=(${GREENAPPLE_OPENCODE_FLAGS})
elif grep -q -- '--allow-dangerously-skip-permissions' <<<"$help_text"; then
  flags+=(--allow-dangerously-skip-permissions)
elif grep -q -- '--dangerously-skip-permissions' <<<"$help_text"; then
  flags+=(--dangerously-skip-permissions)
elif grep -q -- '--dangerously-bypass-approvals-and-sandbox' <<<"$help_text"; then
  flags+=(--dangerously-bypass-approvals-and-sandbox)
else
  echo "WARN: Could not detect a supported dangerous permission-bypass flag in opencode --help." >&2
  echo "WARN: Continuing with OpenCode config permissions; set GREENAPPLE_OPENCODE_FLAGS if your CLI uses a different flag." >&2
fi

exec "$OPENCODE_BIN" "${flags[@]}" "$@"
