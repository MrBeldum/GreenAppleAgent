# HackTheBox Machine Mode

Use this mode only for authorized HackTheBox/CTF lab machines from a ParrotOS or Kali VM.

## Scope Rules

- Test only the assigned machine IP/hostname and services discovered on that host.
- Do not scan adjacent HackTheBox ranges, other players, VPN infrastructure, or unrelated public domains.
- If a hostname is discovered from the target, add it to `/etc/hosts` only when it resolves back to the assigned machine IP.
- Keep all evidence in the active engagement directory.
- A bare HackTheBox IP is a service-neutral machine target. Do not assume HTTP/80, do not start web-only tooling by default, and do not check web paths on non-web management services such as WinRM just because they speak HTTPAPI.
- HackTheBox machines are always either Linux or Windows. Use this to narrow enumeration and exploitation strategies: for Windows, check AD, Kerberos, SMB, WinRM, RDP, MSSQL, IIS; for Linux, check SSH, web apps, databases, cron, SUID binaries, container escapes.

## VM-Native Tooling

- Default runtime is `GREENAPPLE_RUNTIME_MODE=local`; `run_tool` executes host-installed Parrot/Kali tools from the VM using sudo by default so tools run with full privileges (nmap raw sockets, msfconsole, john, etc.).
- Still use `run_tool <tool>` for consistency, auth handling, logging, and engagement-local paths.
- All tools run through `run_tool` automatically get sudo when available non-interactively. If `sudo -n` fails, `run_tool` falls back to unprivileged execution and logs a warning. Configure passwordless sudo or run `sudo -v` before starting an autonomous session.
- Use `run_privileged <command>` only for explicit VM-local setup such as appending to `/etc/hosts`. Never store sudo credentials in GreenAppleAgent files.
- Always search for and use host wordlists from `/usr/share/seclists/` and `/usr/share/wordlists/` before building small engagement-local lists. Never make up tiny wordlists when a real corpus exists.
- Start OpenCode with `./run-htb.sh` from the installed runtime directory.
- Run `./scripts/htb_preflight.sh <target>` if tools, VPN, or reachability look suspicious.

## Beginner-Friendly Workflow

1. Define the target and scope in plain language.
2. Check VPN/reachability before blaming the target.
3. Run fast initial recon across common services, then explain what each open port means.
4. Enumerate one service at a time and save useful output under `$DIR/scans/`.
5. Turn observations into hypotheses before trying exploits.
6. Prove findings with exact commands and short response excerpts.
7. If credentials are found, validate them across discovered services before moving on.
8. After foothold, document user, hostname, privileges, files touched, user flag proof, and privesc path.
9. After privilege escalation, document root flag proof, cleanup, and lessons learned.
10. Write a walkthrough-style report: recon, enumeration, exploit, foothold, privilege escalation, proof, remediation.

## Command Formatting

Prefer clean, copyable commands with output files:

```bash
run_tool nmap -Pn -sC -sV -oN "$DIR/scans/nmap-initial.txt" 10.x.x.x
run_tool nmap -Pn -p- --min-rate 5000 -oN "$DIR/scans/nmap-allports.txt" 10.x.x.x
run_tool ffuf -u http://10.x.x.x/FUZZ -w /usr/share/seclists/Discovery/Web-Content/directory-list-2.3-medium.txt -t 40 -ac -o "$DIR/scans/ffuf-root.json"
```

Do not paste huge raw outputs into chat. Summarize the important lines and reference saved files.

## Recon Order

1. Quick TCP service scan: `nmap -Pn -sC -sV` against common/default ports. For bare HTB IPs, include common Windows/AD, Linux, file-sharing, database, and web ports instead of only web ports.
2. Full TCP port sweep: `nmap -Pn -p- --min-rate 5000`, then detailed scan only newly found ports.
3. UDP only when hinted or when TCP is low-signal; keep it bounded.
4. For web ports, run technology fingerprinting, content discovery, vhost checks if a hostname is present, and source review. Always use host wordlists (`/usr/share/seclists/`, `/usr/share/wordlists/`) for fuzzing, not tiny made-up lists.
5. For SMB/FTP/NFS/LDAP/WinRM/SSH, enumerate with service-appropriate tools before guessing credentials.
6. For Active Directory/DC signals, prioritize DNS, LDAP RootDSE, SMB security posture, Kerberos username discovery, AS-REP/Kerberoast checks when usernames exist, ADCS/LAPS/SPN hypotheses, and WinRM credential validation after credentials.

## HackTheBox Attack-Path Discipline

- HTB machines are designed with at least one intended path. Hardened anonymous LDAP/SMB, required SMB signing, and missing null sessions are information, not proof of a dead end.
- Keep a dead-end list, but after each blocked path ask what the box design is funneling you toward: hostname clues, username patterns, leaked files, alternate services, credentials, or a post-foothold privilege chain.
- For AD machines, do not stop after a tiny built-in-only username list. Mine the box name, domain, hostnames, company/theme words, web text if present, and common HTB name formats before declaring username discovery exhausted.
- Search for credentials everywhere: service banners, shares, web/source artifacts, backups, Git history, config files, comments, archives, certificates, and post-foothold home/application directories.
- After any shell or authenticated foothold, enumerate again from the inside before privilege escalation: users, groups, sudo privileges, SUID/SGID, services, scheduled tasks, cron, writable paths, configs, processes, databases, and internal-only listeners.

## Brute Force And Cracking Limits

- Brute forcing and password cracking must stop at 5 minutes unless the machine provides a clear hint such as an explicit wordlist, hash, username pattern, password policy, or challenge text.
- Prefer tiny, evidence-based lists from discovered usernames, site words, config leaks, and comments.
- Do not launch broad `rockyou.txt` cracking or Hydra attacks by default.
- Record the time limit and why the attempt was justified.
- If no result appears quickly, stop and return to enumeration.

## OpenCode Runtime

- `./run-htb.sh` starts one OpenCode session in the installed runtime directory.
- Because agents run inside that same OpenCode session, the project config applies to the operator and all subagents.
- Leave `GREENAPPLE_OPENCODE_FLAGS` unset for normal use. Advanced users can set extra OpenCode TUI flags or a project path there.

## Walkthrough Report Format

Use this structure for final HackTheBox-style reports:

```text
# HackTheBox Machine Walkthrough: <name-or-ip>

## Scope And Setup
## Recon Summary
## Service Enumeration
## Initial Foothold
## Privilege Escalation
## Proof / Flags
## Findings And Impact
## Cleanup Notes
## Lessons Learned
```

Keep explanations beginner-friendly: define why a command is being run, what the key output means, and how it changes the next step.
