# Active Directory Enumeration

Use this reference for authorized HackTheBox/CTF Active Directory machines only. Treat the
assigned machine IP and hostnames proven to resolve to it as the complete scope.

## Pre-Credential AD/DC Checklist

When a target looks like a domain controller, cover these before calling the path blocked:

```bash
run_tool nmap -Pn -sC -sV -p 53,88,135,139,389,445,464,593,636,3268,3269,5985,9389 -oN "$DIR/scans/nmap_ad_services.txt" <ip>
run_tool dig @<ip> <domain> A +short
run_tool dig @<ip> _ldap._tcp.<domain> SRV +short
run_tool ldapsearch -x -H ldap://<ip> -s base -b "" defaultNamingContext dnsHostName rootDomainNamingContext
run_tool smbclient -L //<ip> -N
```

Record hardening results as information, not as terminal blockers: SMB signing required,
SMBv1 disabled, null sessions denied, and LDAP bind required usually mean the intended path
requires better username/credential discovery.

## Hostname Handling

If DNS/LDAP proves that a hostname belongs to the assigned machine, map it locally so Kerberos,
LDAP, SMB, and WinRM tools can use the expected names:

```bash
source scripts/lib/container.sh
export ENGAGEMENT_DIR="$DIR"
printf '%s\t%s %s\n' '<ip>' '<domain>' '<dc-hostname>' | run_privileged tee -a /etc/hosts >/dev/null
```

Do not hardcode sudo usernames or passwords. If `run_privileged` reports that sudo is not
available non-interactively, return that blocker and tell the operator to cache sudo with
`sudo -v` or configure passwordless sudo in the VM.

## Username Discovery For HTB AD

Username discovery is often the critical foothold precursor. A small list that only finds
built-ins or machine accounts is a signal to improve the candidate list, not proof that no
users exist.

Build `$DIR/scans/ad_user_candidates.txt` from target-specific clues:

- Box name, domain, NetBIOS name, DC hostname, certificate names, and DNS labels.
- Company/theme terms and variants, including words split on punctuation or camel case.
- People names from web pages, comments, SMB filenames, LDAP banners, certificates, or OSINT artifacts.
- Common HTB name formats: `first.last`, `flast`, `firstl`, `firstname`, `lastname`, `first_last`, and role names such as `svc-*`, `backup`, `support`, `helpdesk`, `web`, `sql`, and `admin`.
- Common English names only as a bounded supplement, not as an unbounded spray.

Example candidate-generation pattern using only engagement-local files:

```bash
cat > "$DIR/scans/ad_seed_words.txt" <<'EOF'
boxname
domainroot
orgname
themeword
support
helpdesk
backup
svc-boxname
svc_backup
EOF

cat > "$DIR/scans/common_htb_names.txt" <<'EOF'
alex
andrew
ben
chris
daniel
david
emily
james
john
josh
mark
michael
olivia
robert
sarah
smith
thomas
william
EOF

python3 - "$DIR/scans/ad_seed_words.txt" "$DIR/scans/common_htb_names.txt" "$DIR/scans/ad_user_candidates.txt" <<'PY'
import itertools
import sys

seed_path, names_path, out_path = sys.argv[1:]
seeds = [x.strip().lower() for x in open(seed_path, encoding="utf-8") if x.strip()]
names = [x.strip().lower() for x in open(names_path, encoding="utf-8") if x.strip()]
users = set(seeds)

for first, last in itertools.product(names, names):
    if first == last:
        continue
    users.add(f"{first}.{last}")
    users.add(f"{first[0]}{last}")
    users.add(f"{first}{last[0]}")

for seed in seeds:
    for prefix in ("svc", "svc-", "svc_", "adm", "admin", "backup", "support"):
        users.add(f"{prefix}{seed}")

with open(out_path, "w", encoding="utf-8") as handle:
    for user in sorted(users):
        handle.write(user + "\n")
PY
```

Then test Kerberos username validity with whatever authorized tool is installed:

```bash
run_tool kerbrute userenum -d <domain> --dc <dc-hostname-or-ip> "$DIR/scans/ad_user_candidates.txt" -o "$DIR/scans/kerbrute_userenum.txt"
```

If `kerbrute` is unavailable, use an Impacket-style Kerberos user-enum or AS-REP helper and
record the substitution. After confirming valid non-built-in users, check AS-REP roasting and
Kerberoasting paths with the confirmed names only; do not jump straight to password spraying.

## Post-Credential AD Enumeration

Once any credential, hash, or ticket is recovered, immediately repeat enumeration with auth:

```bash
run_tool netexec smb <ip> -u '<user>' -p '<password>' --shares
run_tool netexec ldap <ip> -u '<user>' -p '<password>' --users --groups
run_tool netexec winrm <ip> -u '<user>' -p '<password>'
```

Then check SPNs, ACLs, delegation, ADCS templates, LAPS/Windows LAPS readability, SYSVOL,
NETLOGON, GPP remnants, scripts, backups, and WinRM/RDP eligibility.

## BloodHound
```bash
# Install
apt-get install bloodhound
neo4j console   # configure at http://localhost:7474 (neo4j:neo4j)
# Collect data
SharpHound.exe -c All
# Or PowerShell ingestor
Invoke-BloodHound -CollectionMethod All
```
- Upload .zip to BloodHound GUI; query shortest paths to DA

## PowerView Key Commands
```powershell
# Import
Import-Module PowerView.ps1
# Domain info
Get-NetDomain
Get-NetForest
Get-NetDomainController
# Users and groups
Get-NetUser | select samaccountname,description
Get-NetGroupMember "Domain Admins"
Get-NetLoggedon -ComputerName TARGET
# Trusts
Get-NetDomainTrust
Get-NetForestTrust
# ACLs
Get-ObjectAcl -SamAccountName "Domain Admins" -ResolveGUIDs
# Shares
Find-DomainShare -CheckShareAccess
# SPNs (for Kerberoasting)
Get-NetUser -SPN | select serviceprincipalname
```

## AD Module Without RSAT
```powershell
# Import DLL directly (no admin required)
Import-Module Microsoft.ActiveDirectory.Management.dll
Get-ADUser -Filter * -Properties *
Get-ADComputer -Filter * -Properties *
Get-ADGroup -Filter * -Properties *
```

## ACL/ACE Abuse
- Key rights to look for: GenericAll, GenericWrite, WriteOwner, WriteDACL, ForceChangePassword
```powershell
# Find users with GenericAll on target
Get-ObjectAcl -SamAccountName TARGET -ResolveGUIDs | ? {$_.ActiveDirectoryRights -eq "GenericAll"}
# GenericAll on user = reset password
# GenericAll on group = add yourself to group
# WriteDACL = grant yourself any rights
```
