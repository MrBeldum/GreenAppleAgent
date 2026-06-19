#!/usr/bin/env bash
# Start OpenCode for HackTheBox VM use with local host tools.
# Primes sudo so all agent commands run with full privileges non-interactively.

set -euo pipefail

OPENCODE_BIN="${OPENCODE_BIN:-opencode}"

if [[ -f .env ]]; then
  set -a
  . ./.env
  set +a
fi

export GREENAPPLE_RUNTIME_MODE="${GREENAPPLE_RUNTIME_MODE:-local}"

if ! command -v "$OPENCODE_BIN" >/dev/null 2>&1; then
  echo "ERROR: opencode not found. Install with: npm install -g opencode-ai" >&2
  exit 1
fi

if ! command -v sudo >/dev/null 2>&1; then
  echo "ERROR: sudo is required. Install it and configure passwordless sudo for the VM user." >&2
  exit 1
fi

if ! sudo -n true >/dev/null 2>&1; then
  echo "Priming sudo credential cache..." >&2
  sudo -v
fi

_greenapple_sudo_keepalive() {
  local pids_dir
  pids_dir="$(dirname "$0")/pids"
  mkdir -p "$pids_dir"
  (
    while true; do
      sleep 240
      sudo -n true >/dev/null 2>&1 || exit 0
    done
  ) &
  echo "$!" > "$pids_dir/sudo-keepalive.pid"
}

_greenapple_sudo_keepalive

flags=()

if [[ -n "${GREENAPPLE_OPENCODE_FLAGS:-}" ]]; then
  flags=(${GREENAPPLE_OPENCODE_FLAGS})
fi

if [[ $# -eq 0 ]]; then
  set -- .
fi

exec "$OPENCODE_BIN" "${flags[@]}" "$@"
