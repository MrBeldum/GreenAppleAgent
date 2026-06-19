#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ENG_DIR="${1:?usage: ensure_tools.sh <engagement_dir> [tool1 tool2 ...]}"
shift

DEBIAN_FRONTEND=noninteractive
export DEBIAN_FRONTEND

REQUIRED_TOOLS=(curl jq sqlite3 python3 git nmap)
HTB_OPTIONAL_TOOLS=(
  ffuf:ffuf
  feroxbuster:feroxbuster
  whatweb:whatweb
  nikto:nikto
  nuclei:nuclei
  sqlmap:sqlmap
  hydra:hydra
  john:john
  hashcat:hashcat
  searchsploit:exploitdb
  smbclient:smbclient
  enum4linux-ng:enum4linux-ng
  netexec:netexec
  kerbrute:kerbrute
  certipy-ad:certipy-ad
  bloodhound-python:bloodhound.py
  evil-winrm:evil-winrm
  impacket-scripts:impacket-scripts
  msfconsole:metasploit-framework
  dnsrecon:dnsrecon
  gobuster:gobuster
  wfuzz:wfuzz
  dirb:dirb
  seclists:seclists
)

requires() {
  local name="$1"
  local pkg="${2:-$1}"
  if command -v "$name" >/dev/null 2>&1; then
    echo "[OK] $name"
  else
    echo "[INSTALL] $name (installing $pkg...)"
    sudo -n apt-get update -qq >/dev/null 2>&1 || true
    sudo -n apt-get install -y -qq "$pkg" >/dev/null 2>&1 || \
      echo "[MISSING] $name — could not auto-install $pkg"
  fi
}

requires_python() {
  local name="$1"
  local pip_pkg="${2:-$1}"
  if python3 -c "import $name" >/dev/null 2>&1; then
    echo "[OK] python:$name"
  else
    echo "[INSTALL] python:$name (pip install $pip_pkg...)"
    sudo -n pip3 install "$pip_pkg" >/dev/null 2>&1 || \
      echo "[MISSING] python:$name — could not pip install"
  fi
}

echo "=== Required tools ==="
for tool in "${REQUIRED_TOOLS[@]}"; do
  requires "$tool"
done

echo ""
echo "=== Optional HTB tools ==="
if [[ $# -gt 0 ]]; then
  for needed in "$@"; do
    for mapping in "${HTB_OPTIONAL_TOOLS[@]}"; do
      name="${mapping%%:*}"
      pkg="${mapping#*:}"
      if [[ "$needed" == "$name" ]]; then
        requires "$name" "$pkg"
        break
      fi
    done
  done
else
  for mapping in "${HTB_OPTIONAL_TOOLS[@]}"; do
    name="${mapping%%:*}"
    pkg="${mapping#*:}"
    requires "$name" "$pkg" 2>/dev/null
  done
fi

echo ""
echo "=== Python tools ==="
requires_python "impacket" "impacket" 2>/dev/null
requires_python "ldap3" "ldap3" 2>/dev/null
requires_python "pyOpenSSL" "pyOpenSSL" 2>/dev/null

echo ""
echo "=== Tool check complete ==="
