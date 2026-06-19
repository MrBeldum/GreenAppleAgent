#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ENG_DIR="${1:?usage: htb_knock_triage.sh <engagement_dir> <target_ip>}"
TARGET="${2:?}"
MAX_PORTS="${3:-5}"
TIMEOUT_S="${4:-30}"

STATE=$(python3 -c "
import json, os
sf=os.path.join('$ENG_DIR','state.json')
if os.path.exists(sf):
    s=json.load(open(sf))
    print(f'tcp={len(s.get(\"tcp_ports_services\",{}))}')
    attempts=len(s.get('attempted_vectors',[]))
    creds=len(s.get('credentials',[]))
    access=s.get('access_level','none')
    print(f'attempts={attempts} creds={creds} access={access}')
else:
    print('no_state')
" 2>/dev/null || echo "no_state")

TCP_COUNT=$(echo "$STATE" | grep -oP 'tcp=\K\d+' || echo "0")
CREDS=$(echo "$STATE" | grep -oP 'creds=\K\d+' || echo "0")
ACCESS=$(echo "$STATE" | grep -oP 'access=\K(\w+)' || echo "none")

SHOULD_RUN=0

if [[ "$TCP_COUNT" -le 2 && "$CREDS" -eq 0 && "$ACCESS" == "none" ]]; then
  SHOULD_RUN=1
  echo "Port-knocking triage justified: $TCP_COUNT open TCP ports, no creds, no access"
fi

"$SCRIPT_DIR/htb_state.py" count-attempts "$ENG_DIR" --pattern "port-knock" 2>/dev/null | read -r KNOCK_COUNT || KNOCK_COUNT=0

if [[ "$KNOCK_COUNT" -ge 1 ]]; then
  echo "Port-knocking already attempted once, skipping to avoid loop"
  exit 0
fi

if [[ "$SHOULD_RUN" -eq 0 ]]; then
  echo "Port-knocking triage not justified for this target"
  exit 0
fi

echo "=== PORT-KNOCK TRIAGE ==="
echo "Testing common HTB port-knock sequences..."

"$SCRIPT_DIR/htb_state.py" add-attempt "$ENG_DIR" \
  --agent "operator" \
  --vector "port-knock" \
  --result "triage_start" 2>/dev/null || true

COMMON_SEQUENCES=(
  "7000 8000 9000"
  "1111 2222 3333"
  "1234 2345 3456"
  "1337 1337 1337"
  "1 2 3"
  "4444 6666 8888"
)

FOUND_NEW=0
for seq in "${COMMON_SEQUENCES[@]}"; do
  if [[ "$FOUND_NEW" -eq 1 ]]; then break; fi
  echo "  Trying: $seq"
  for port in $seq; do
    sudo -n -E nmap -Pn -p "$port" --max-retries 0 --host-timeout 5s "$TARGET" >/dev/null 2>&1 || true
    sleep 0.3
  done
  sleep 1
  NEW_PORTS=$(sudo -n -E nmap -Pn -p- --min-rate 5000 --host-timeout 30s "$TARGET" 2>/dev/null \
    | grep -oP '^\d+/tcp\s+open' | cut -d/ -f1 | paste -sd, - || true)
  echo "    Open ports after knock: ${NEW_PORTS:-none new}"
done

echo "Port-knock triage complete"
exit 0
