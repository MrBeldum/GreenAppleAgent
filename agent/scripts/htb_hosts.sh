#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/engagement.sh"

ENG_DIR="${1:?usage: htb_hosts.sh <engagement_dir> <ip> <hostname1> [hostname2 ...]}"
TARGET_IP="${2:?usage: htb_hosts.sh <engagement_dir> <ip> <hostname1> [hostname2 ...]}"
shift 2

HOSTS_FILE="/etc/hosts"
LOCAL_HOSTS_FILE="$ENG_DIR/hosts.tsv"
STATE_FILE="$ENG_DIR/state.json"

if [[ ! -f "$STATE_FILE" ]]; then
  echo "WARN: state.json not yet created, skipping host-derived scope update" >&2
fi

added=0
for hostname in "$@"; do
  hostname="$(printf '%s' "$hostname" | tr -d '[:space:]')"
  [[ -z "$hostname" ]] && continue
  [[ "$hostname" == "localhost" ]] && continue
  [[ "$hostname" == "127.0.0.1" ]] && continue
  [[ "$hostname" == "0.0.0.0" ]] && continue
  [[ "$hostname" == "::1" ]] && continue
  [[ "$hostname" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && continue

  if grep -qE "^[[:space:]]*${TARGET_IP}[[:space:]]+.*${hostname}" "$HOSTS_FILE" 2>/dev/null; then
    echo "[htb_hosts] Already mapped: ${TARGET_IP} ${hostname}"
    continue
  fi

  printf '%s\t%s\n' "$TARGET_IP" "$hostname" | sudo -n tee -a "$HOSTS_FILE" >/dev/null
  printf '%s\t%s\n' "$TARGET_IP" "$hostname" >> "$LOCAL_HOSTS_FILE"
  echo "[htb_hosts] Mapped: ${TARGET_IP} ${hostname}"
  added=$((added + 1))

  if [[ -f "$STATE_FILE" ]]; then
    python3 -c "
import json, sys
try:
    with open('$STATE_FILE') as f:
        state = json.load(f)
    hosts = state.setdefault('hostnames', [])
    if '$hostname' not in hosts:
        hosts.append('$hostname')
    state['hostnames'] = sorted(set(hosts))
    with open('$STATE_FILE', 'w') as f:
        json.dump(state, f, indent=2)
except Exception as e:
    sys.stderr.write(f'state.json update failed: {e}\n')
" 2>/dev/null || true
  fi
done

echo "[htb_hosts] Added $added hostname(s) for ${TARGET_IP}"
