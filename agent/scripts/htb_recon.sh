#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/engagement.sh"
source "$SCRIPT_DIR/lib/container.sh"

ENG_DIR="${1:?usage: htb_recon.sh <engagement_dir> <target_ip>}"
TARGET="${2:?usage: htb_recon.sh <engagement_dir> <target_ip>}"
shift 2
UDP_PORTS="${HTB_UDP_PORTS:-50}"
FULL_TCP_MINRATE="${HTB_TCP_MINRATE:-5000}"

resolve_eng_dir() { printf '%s\n' "$ENG_DIR"; }
mkdir -p "$ENG_DIR/scans" "$ENG_DIR/downloads"

echo "=== HTB RECON: $TARGET ==="
echo "Started: $(date -u +%Y-%m-%dT%H:%M:%SZ)"

"$SCRIPT_DIR/htb_state.py" init "$ENG_DIR" --target-ip "$TARGET" 2>/dev/null || true

echo ""
echo "--- Phase 1: Quick common TCP scan ---"
nmap_cmd=(nmap -Pn -sS -sV -T4 --open
  -p 21,22,23,25,53,80,88,110,111,135,139,143,389,443,445,464,465,587,593,636,873,993,995,1025,1433,1521,1723,2049,2181,2375,2376,3000,3128,3268,3269,3306,3389,4333,5432,5555,5800,5900,5985,5986,6379,7001,8000,8009,8080,8081,8443,8888,9000,9001,9090,9200,9300,10000,11211,27017
  --host-timeout 120s
  -oN "$ENG_DIR/scans/nmap_quick_common.txt"
  -oX "$ENG_DIR/scans/nmap_quick_common.xml"
  "$TARGET")
echo "  Running: ${nmap_cmd[*]}"
sudo -n -E "${nmap_cmd[@]}" 2>&1 || echo "  (quick common scan completed or timed out)"

echo ""
echo "--- Phase 2: Full TCP port sweep ---"
full_tcp_cmd=(nmap -Pn -sS -p- --min-rate "$FULL_TCP_MINRATE" --host-timeout 300s
  --open
  -oN "$ENG_DIR/scans/nmap_full_tcp.txt"
  -oX "$ENG_DIR/scans/nmap_full_tcp.xml"
  "$TARGET")
echo "  Running: ${full_tcp_cmd[*]}"
sudo -n -E "${full_tcp_cmd[@]}" 2>&1 || echo "  (full TCP sweep completed or timed out)"

echo ""
echo "--- Phase 3: Parse discovered TCP ports ---"
OPEN_PORTS=""
if [[ -f "$ENG_DIR/scans/nmap_full_tcp.xml" ]]; then
  OPEN_PORTS=$(python3 -c "
import xml.etree.ElementTree as ET
import sys
try:
    tree = ET.parse('$ENG_DIR/scans/nmap_full_tcp.xml')
    ports = []
    for host in tree.findall('.//host'):
        for port in host.findall('.//ports/port'):
            state = port.find('state')
            if state is not None and state.get('state') == 'open':
                ports.append(port.get('portid'))
    print(','.join(sorted(ports, key=int)))
except Exception as e:
    sys.stderr.write(f'XML parse error: {e}\n')
    sys.exit(1)
" 2>/dev/null || true)
fi

if [[ -z "$OPEN_PORTS" ]]; then
  OPEN_PORTS=$(grep -oP '^\d+/tcp\s+open' "$ENG_DIR/scans/nmap_full_tcp.txt" 2>/dev/null \
    | cut -d/ -f1 | sort -n | paste -sd, - || true)
fi

echo "  Open TCP ports: ${OPEN_PORTS:-none}"

if [[ -n "$OPEN_PORTS" ]]; then
  echo ""
  echo "--- Phase 4: Targeted service version scan ---"
  targeted_cmd=(nmap -Pn -sV -sC -T4 --host-timeout 120s
    -p "$OPEN_PORTS"
    -oN "$ENG_DIR/scans/nmap_targeted_services.txt"
    -oX "$ENG_DIR/scans/nmap_targeted_services.xml"
    "$TARGET")
  echo "  Running: ${targeted_cmd[*]}"
  sudo -n -E "${targeted_cmd[@]}" 2>&1 || echo "  (targeted scan completed)"
fi

echo ""
echo "--- Phase 5: UDP top $UDP_PORTS scan ---"
UDP_SCAN_DONE=0
udp_cmd=(nmap -Pn -sU --top-ports "$UDP_PORTS" -T4 --host-timeout 120s
  --open
  -oN "$ENG_DIR/scans/nmap_udp_top.txt"
  -oX "$ENG_DIR/scans/nmap_udp_top.xml"
  "$TARGET")
echo "  Running: ${udp_cmd[*]}"
sudo -n -E "${udp_cmd[@]}" 2>&1 || echo "  (UDP scan completed)"
UDP_SCAN_DONE=1

echo ""
echo "--- Phase 6: OS detection ---"
os_cmd=(nmap -Pn -O --osscan-guess --host-timeout 60s
  -oN "$ENG_DIR/scans/nmap_os.txt"
  "$TARGET")
echo "  Running: ${os_cmd[*]}"
sudo -n -E "${os_cmd[@]}" 2>&1 || echo "  (OS detection completed)"

echo ""
echo "--- Updating state ---"

"$SCRIPT_DIR/htb_state.py" set "$ENG_DIR" full_tcp_scan_done true 2>/dev/null || true
"$SCRIPT_DIR/htb_state.py" set "$ENG_DIR" udp_scan_done true 2>/dev/null || true

if [[ -f "$ENG_DIR/scans/nmap_targeted_services.xml" ]]; then
  python3 -c "
import xml.etree.ElementTree as ET, json, sys
services = {}
try:
    tree = ET.parse('$ENG_DIR/scans/nmap_targeted_services.xml')
    for host in tree.findall('.//host'):
        for port in host.findall('.//ports/port'):
            sid = port.get('portid')
            protocol = port.get('protocol','tcp')
            svc = port.find('service')
            name = svc.get('name','') if svc is not None else ''
            product = svc.get('product','') if svc is not None else ''
            version = svc.get('version','') if svc is not None else ''
            key = f'{sid}/{protocol}'
            services[key] = {'service': name, 'product': product, 'version': version}
    with open('$ENG_DIR/scans/nmap_services.json','w') as f:
        json.dump(services, f, indent=2)
    print(f'Parsed {len(services)} services')
except Exception as e:
    sys.stderr.write(f'Parse error: {e}\n')
" 2>/dev/null || true

  if [[ -f "$ENG_DIR/scans/nmap_services.json" ]]; then
    "$SCRIPT_DIR/htb_state.py" set "$ENG_DIR" tcp_ports_services \
      "$(cat "$ENG_DIR/scans/nmap_services.json")" 2>/dev/null || true
  fi
fi

HAS_HTTP=0
if echo "$OPEN_PORTS" | grep -qE '(^|,)(80|443|8080|8443|3000|8000|8888|9000)($|,)'; then
  HAS_HTTP=1
fi

"$SCRIPT_DIR/htb_state.py" set "$ENG_DIR" http_service_detected "$HAS_HTTP" 2>/dev/null || true

echo ""
echo "=== RECON COMPLETE ==="
echo "Open TCP: ${OPEN_PORTS:-none}"
echo "HTTP detected: $HAS_HTTP"
echo "UDP scanned: $UDP_SCAN_DONE"

printf 'RECON_OPEN_TCP=%s\n' "$OPEN_PORTS"
printf 'RECON_HAS_HTTP=%s\n' "$HAS_HTTP"
