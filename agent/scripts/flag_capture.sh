#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ENG_DIR="${1:?usage: flag_capture.sh <engagement_dir> <flag_type: user|root> <flag_value>}"
FLAG_TYPE="${2:?}"
FLAG_VALUE="${3:?}"

if [[ "$FLAG_TYPE" != "user" && "$FLAG_TYPE" != "root" ]]; then
  echo "ERROR: flag_type must be 'user' or 'root'" >&2
  exit 1
fi

STATE_FILE="$ENG_DIR/state.json"
if [[ ! -f "$STATE_FILE" ]]; then
  echo "ERROR: state.json not found" >&2
  exit 1
fi

CURRENT=$(python3 -c "
import json
s=json.load(open('$STATE_FILE'))
f=s.get('flags_captured',{})
print('user=' + str(f.get('user',False)) + ' root=' + str(f.get('root',False)))
print('user_val=' + str(f.get('user_value','')) + ' root_val=' + str(f.get('root_value','')))
" 2>/dev/null || echo "unknown")

ALREADY=$(python3 -c "
import json
s=json.load(open('$STATE_FILE'))
f=s.get('flags_captured',{})
print(str(f.get('${FLAG_TYPE}',False)).lower())
" 2>/dev/null || echo "false")

if [[ "$ALREADY" == "true" ]]; then
  echo "Flag $FLAG_TYPE already captured"
  exit 0
fi

"$SCRIPT_DIR/htb_state.py" add-flag "$ENG_DIR" --type "$FLAG_TYPE" --value "$FLAG_VALUE"

MASKED="${FLAG_VALUE:0:4}...${FLAG_VALUE: -4}"

cat >> "$ENG_DIR/log.md" << EOF

## [$FLAG_TYPE flag captured]
**Flag**: \`$MASKED\`
**Type**: $FLAG_TYPE
**Full value saved in**: state.json
EOF

echo "[FLAG] $FLAG_TYPE flag captured: $MASKED"

TOTAL=$(python3 -c "
import json
s=json.load(open('$STATE_FILE'))
f=s.get('flags_captured',{})
print(('1' if f.get('user') else '0') + '/' + ('1' if f.get('root') else '0'))
" 2>/dev/null || echo "0/2")

echo "[FLAG] Progress: $TOTAL (user/root)"
