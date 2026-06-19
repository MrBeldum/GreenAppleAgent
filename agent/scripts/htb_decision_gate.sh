#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ENG_DIR="${1:?usage: htb_decision_gate.sh <engagement_dir>}"
shift

echo "=== HTB Decision Gate ==="

BLOCKED=0

if [[ ! -f "$ENG_DIR/state.json" ]]; then
  echo "MISSING: state.json not initialized"
  exit 1
fi

FULL_TCP=$(python3 -c "import json; s=json.load(open('$ENG_DIR/state.json')); print(s.get('full_tcp_scan_done',False))" 2>/dev/null || echo "False")
UDP_DONE=$(python3 -c "import json; s=json.load(open('$ENG_DIR/state.json')); print(s.get('udp_scan_done',False))" 2>/dev/null || echo "False")
TCP_COUNT=$(python3 -c "import json; s=json.load(open('$ENG_DIR/state.json')); print(len(s.get('tcp_ports_services',{})))" 2>/dev/null || echo "0")
ATTEMPTS=$(python3 -c "import json; s=json.load(open('$ENG_DIR/state.json')); print(len(s.get('attempted_vectors',[])))" 2>/dev/null || echo "0")
DEAD_ENDS=$(python3 -c "import json; s=json.load(open('$ENG_DIR/state.json')); print(len(s.get('dead_ends',[])))" 2>/dev/null || echo "0")
CREDS=$(python3 -c "import json; s=json.load(open('$ENG_DIR/state.json')); print(len(s.get('credentials',[])))" 2>/dev/null || echo "0")
FLAGS=$(python3 -c "import json; s=json.load(open('$ENG_DIR/state.json')); f=s.get('flags_captured',{}); u=f.get('user',False); r=f.get('root',False); print(('user+' if u else '')+('root' if r else ('none' if not u else '')))" 2>/dev/null || echo "none")
ACCESS=$(python3 -c "import json; s=json.load(open('$ENG_DIR/state.json')); print(s.get('access_level','none'))" 2>/dev/null || echo "none")
SOURCE=$(python3 -c "import json; s=json.load(open('$ENG_DIR/state.json')); print(s.get('source_analysis_done',False))" 2>/dev/null || echo "False")
HTTP=$(python3 -c "import json; s=json.load(open('$ENG_DIR/state.json')); print(s.get('http_service_detected',0))" 2>/dev/null || echo "0")

echo "Full TCP: $FULL_TCP | UDP: $UDP_DONE | TCP services: $TCP_COUNT"
echo "HTTP detected: $HTTP | Source analyzed: $SOURCE"
echo "Credentials: $CREDS | Access: $ACCESS | Flags: $FLAGS"
echo "Attempts: $ATTEMPTS | Dead ends: $DEAD_ENDS"

if [[ "$FULL_TCP" != "True" ]]; then
  echo "GATE FAIL: Full TCP scan not completed"
  BLOCKED=1
fi

if [[ "$UDP_DONE" != "True" ]]; then
  echo "GATE FAIL: UDP scan not completed"
  BLOCKED=1
fi

if [[ "$HTTP" == "1" && "$SOURCE" != "True" ]]; then
  echo "GATE FAIL: HTTP service detected but source analysis not done"
  BLOCKED=1
fi

if [[ "$ATTEMPTS" -ge 20 && "$CREDS" -eq 0 && "$ACCESS" == "none" ]]; then
  echo "GATE WARN: High attempt count with zero creds/access — possible loop"
  TOP_VECTOR=$(python3 -c "
import json
s=json.load(open('$ENG_DIR/state.json'))
vecs={}
for a in s.get('attempted_vectors',[]):
    v=a.get('vector','')
    vecs[v]=vecs.get(v,0)+1
top=sorted(vecs.items(),key=lambda x:-x[1])[:3]
for v,c in top: print(f'  {c}x {v}')
" 2>/dev/null || true)
  echo "Top repeated vectors:"
  echo "$TOP_VECTOR"
fi

if [[ "$BLOCKED" -eq 0 ]]; then
  echo "GATE: All checks passed"
  exit 0
else
  echo "GATE: $BLOCKED issue(s) found — enumeration must continue before reporting"
  exit 1
fi
