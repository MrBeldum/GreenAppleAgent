#!/usr/bin/env bash
# Fast readiness check for Parrot/Kali VM + HackTheBox targets.

set -euo pipefail

TARGET="${1:-}"

ok() { printf '[OK] %s\n' "$1"; }
warn() { printf '[WARN] %s\n' "$1"; }
miss() { printf '[MISSING] %s\n' "$1"; }

printf 'HackTheBox VM preflight\n'
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
  warn "GREENAPPLE_RUNTIME_MODE=$runtime; set GREENAPPLE_RUNTIME_MODE=local for no-Docker HackTheBox VM use"
fi

required=(opencode curl jq sqlite3 python3 git nmap)
recommended=(ffuf gobuster feroxbuster whatweb nikto nuclei sqlmap hydra john hashcat searchsploit smbclient enum4linux-ng netexec kerbrute certipy bloodhound-python evil-winrm msfconsole)

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

printf '\nPrivilege support\n'
if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  ok "Already running as root"
elif command -v sudo >/dev/null 2>&1; then
  if sudo -n true >/dev/null 2>&1; then
    ok "sudo works non-interactively for VM setup tasks"
  else
    warn "sudo exists but needs authentication; run sudo -v before autonomous work or configure passwordless sudo. GreenAppleAgent will not store sudo credentials."
  fi
else
  warn "sudo not found; hostname mapping and other root-only VM setup may need manual handling"
fi

printf '\nVPN / routing\n'
if ip link show tun0 >/dev/null 2>&1; then
  ok "tun0 exists"
elif ip -o link show 2>/dev/null | grep -Eq 'tun[0-9]'; then
  ok "Tunnel interface exists"
else
  warn "No tun interface found. Connect the HackTheBox VPN before /engage."
fi

if ip route 2>/dev/null | grep -Eq '(^|[[:space:]])10\.[0-9]{1,3}\.'; then
  ok "HackTheBox-looking 10.x.x.x route present"
else
  warn "No 10.x.x.x route detected yet"
fi

if [[ -n "$TARGET" ]]; then
  host="$TARGET"
  host="${host#http://}"
  host="${host#https://}"
  host="${host%%/*}"
  host="${host%%:*}"
  printf '\nTarget reachability: %s\n' "$host"
  quick_ports=(21 22 53 80 88 135 139 389 443 445 464 593 636 1433 2049 3268 3269 3306 3389 5432 5985 8080 8443 9389)
  open_quick=()
  for port in "${quick_ports[@]}"; do
    if timeout 1 bash -c "</dev/tcp/$host/$port" >/dev/null 2>&1; then
      open_quick+=("$port")
    fi
  done
  if [[ ${#open_quick[@]} -gt 0 ]]; then
    ok "Target has quick TCP response on port(s): ${open_quick[*]}"
  elif ping -c 1 -W 2 "$host" >/dev/null 2>&1; then
    ok "Target responds to ICMP"
  else
    warn "Target did not answer quick ICMP/TCP checks; HackTheBox machines may still be up on uncommon ports"
  fi
fi

printf '\nOpenCode launch\n'
printf 'Use: ./run-htb.sh\n'
printf 'Then: /htb <machine-ip-or-url>\n'
