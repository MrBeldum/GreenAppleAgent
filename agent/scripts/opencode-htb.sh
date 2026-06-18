#!/usr/bin/env bash
# Start OpenCode for HackTheBox VM use with local host tools.

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

flags=()

if [[ -n "${GREENAPPLE_OPENCODE_FLAGS:-}" ]]; then
  # Optional advanced TUI flags/project args. Do not auto-detect `opencode run`
  # permission flags here; current OpenCode builds expose those only for `run`.
  # shellcheck disable=SC2206
  flags=(${GREENAPPLE_OPENCODE_FLAGS})
fi

if [[ $# -eq 0 ]]; then
  set -- .
fi

exec "$OPENCODE_BIN" "${flags[@]}" "$@"
