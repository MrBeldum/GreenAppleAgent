#!/usr/bin/env bash
# Fast readiness check for Parrot/Kali VM + Hack The Box targets.

set -euo pipefail

TARGET="${1:-}"

ok() { printf '[OK] %s\n' "$1"; }
warn() { printf '[WARN] %s\n' "$1"; }
miss() { printf '[MISSING] %s\n' "$1"; }

printf 'Hack The Box VM preflight\n'
printf '==========================\n'

if [[ -r /etc/os-release ]]; then
  . /etc/os-release
  case "${ID:-}" in
    kali|parrot) ok "Detected ${PRETTY_NAME:-$ID}" ;;
    *) warn "Detected ${PRETTY_NAME:-unknown Linux}; this profile is tuned for Parrot/Kali" ;;
  esac
else
  warn "Could not read /etc/os-release"
fi

runtime="${GREENAPPLE_RUNTIME_MODE:-local}"
if [[ "$runtime" == "local" ]]; then
  ok "GREENAPPLE_RUNTIME_MODE=local (host VM tools)"
else
  warn "GREENAPPLE_RUNTIME_MODE=$runtime; set GREENAPPLE_RUNTIME_MODE=local for no-Docker HTB VM use"
fi

required=(opencode curl jq sqlite3 python3 git nmap)
recommended=(ffuf gobuster feroxbuster whatweb nikto nuclei sqlmap hydra john hashcat searchsploit smbclient enum4linux-ng netexec bloodhound-python evil-winrm)

printf '\nRequired tools\n'
for tool in "${required[@]}"; do
  if command -v "$tool" >/dev/null 2>&1; then
    ok "$tool"
  else
    miss "$tool"
  fi
done

printf '\nRecommended pentest tools\n'
for tool in "${recommended[@]}"; do
  if command -v "$tool" >/dev/null 2>&1; then
    ok "$tool"
  else
    warn "$tool not found; install it if the machine needs that service path"
  fi
done

printf '\nVPN / routing\n'
if ip link show tun0 >/dev/null 2>&1; then
  ok "tun0 exists"
elif ip -o link show 2>/dev/null | grep -Eq 'tun[0-9]'; then
  ok "Tunnel interface exists"
else
  warn "No tun interface found. Connect the HTB VPN before /engage."
fi

if ip route 2>/dev/null | grep -Eq '10\.(10|129)\.'; then
  ok "HTB-looking route present"
else
  warn "No 10.10.x.x / 10.129.x.x route detected yet"
fi

if [[ -n "$TARGET" ]]; then
  host="$TARGET"
  host="${host#http://}"
  host="${host#https://}"
  host="${host%%/*}"
  host="${host%%:*}"
  printf '\nTarget reachability: %s\n' "$host"
  if timeout 3 bash -c "</dev/tcp/$host/80" >/dev/null 2>&1 || timeout 3 bash -c "</dev/tcp/$host/443" >/dev/null 2>&1; then
    ok "Target has TCP/80 or TCP/443 reachable"
  elif ping -c 1 -W 2 "$host" >/dev/null 2>&1; then
    ok "Target responds to ICMP"
  else
    warn "Target did not answer quick ICMP/TCP checks; HTB boxes may still be up on other ports"
  fi
fi

printf '\nOpenCode launch\n'
printf 'Use: ./run-htb.sh\n'
printf 'Then: /htb <machine-ip-or-url>\n'
