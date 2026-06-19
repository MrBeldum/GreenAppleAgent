# GreenAppleAgent (NOTE: THIS PROJECT IS RETIRED!)

**The OpenCode agent that hunts HackTheBox machines.** Built for Kali & Parrot OS VMs. No Docker. No Claude. No nonsense. Just HTB.

GreenAppleAgent is a heavily modified OpenCode agent runtime purpose-built to enumerate, exploit, and pwn HackTheBox machines. Every design decision was made with HTB in mind — this is not a general pentesting framework.

---

## What This Thing Does

- Full TCP/UDP port scans with automatic service fingerprinting
- Automatic `/etc/hosts` management (no more forgetting to map hostnames)
- Structured state tracking so you never lose what you already found
- Deep web source analysis that actually reads HTML/JS contents (not just file sizes)
- Active Directory username discovery that doesn't quit after finding 4 built-in accounts
- Credential chaining — found creds get tested across ALL services automatically
- Anti-loop gates that stop the agent from retrying failed CVE exploits 6 times
- Flag capture with standard HTB paths (Linux & Windows)
- Sudo-safe command execution (every command gets privileges, no hanging on prompts)
- Beginner-friendly Markdown walkthrough generation

---

## Quick Start

### What You Need

- A Kali Linux or Parrot OS VM
- [OpenCode](https://opencode.ai) installed (`npm install -g opencode-ai`)
- Your HackTheBox VPN connected
- Passwordless sudo (run `sudo -v` before launching, or configure in `/etc/sudoers.d/`)

### Install

```bash
cd GreenAppleAgent
./install.sh opencode ~/greenapple-agent
```

Already installed but want to update? Your engagements and `.env` are safe:

```bash
./install.sh --force opencode ~/greenapple-agent
```

### Launch

```bash
cd ~/greenapple-agent
sudo -v          # prime your sudo cache
./run-htb.sh
```

### Start a Box

Inside OpenCode:

```
/htb 10.129.x.x
```

Use a bare IP. The agent figures out what's there. Don't assume port 80 exists.

### Resume a Box

```
/resume
```

GreenAppleAgent remembers everything. Your scans, credentials, flags, and dead ends are all tracked per-engagement in `engagements/<date-time-host>/`.

---

## Configuration

Copy `agent/.env.example` to `agent/.env` and tweak:

| Variable | What it does | Default |
|----------|-------------|---------|
| `GREENAPPLE_RUNTIME_MODE` | Always `local` — uses VM tools | `local` |
| `HTB_UDP_PORTS` | Top UDP ports to scan | `50` |
| `HTB_TCP_MINRATE` | Nmap scan speed | `5000` |
| `GREENAPPLE_MAX_ATTEMPTS_PER_VECTOR` | Max retries before falling back | `3` |
| `GREENAPPLE_MAX_PARALLEL_BATCHES` | Max parallel subagent batches | `3` |
| `GREENAPPLE_BATCH_SIZE` | Cases per subagent batch | `5` |
| `HTB_API_TOKEN` | (Optional) HTB API token for flag validation | _(unset)_ |

API keys for OSINT enrichment (all optional):

```bash
SUBFINDER_VIRUSTOTAL_API_KEY=
SECURITYTRAILS_API_KEY=
HIBP_API_KEY=
# ... more in .env.example
```

---

## Commands

| Command | What it does |
|---------|-------------|
| `/htb 10.x.x.x` | Start a new HackTheBox machine engagement |
| `/htb http://10.x.x.x` | Start when you know there's a web service on that IP |
| `/resume` | Pick up where you left off (state, flags, queue — all preserved) |
| `/status` | Show engagement state dashboard: ports, creds, findings, queue progress |
| `/stop` | Stop all background processes |
| `/report` | Generate the final beginner-friendly Markdown walkthrough |
| `/recon` | Manual override: run reconnaissance |
| `/exploit` | Manual override: exploit a specific finding |
| `/pivot` | Force strategy change based on current findings |

---

## How It Works (Step by Step)

### 1. Engagement Creation

`/htb 10.x.x.x` creates a timestamped directory under `engagements/` containing:

```
engagements/2026-06-19-093021-10-129-0-0/
  scope.json          — target, scope, phase tracking
  state.json          — structured state (ports, creds, flags, dead ends)
  notes.md            — human-readable notes organized by section
  log.md              — chronological action log
  findings.md         — confirmed vulnerability findings
  cases.db            — SQLite case queue for subagent dispatch
  auth.json           — discovered/validated credentials
  intel.md            — OSINT intelligence
  intel-secrets.json  — sensitive secrets (hashes, keys) stored separately
  hosts.tsv           — IP-to-hostname mappings
  scans/              — all scan output (nmap, ffuf, whatweb, etc.)
  downloads/          — fetched HTML/JS/CSS files and other artifacts
  tools/              — custom scripts and exploits
  pids/               — background process PIDs
```

### 2. Mandatory Recon Pipeline

For bare HTB IPs, `htb_recon.sh` runs automatically:

1. **Quick common TCP scan** — 60+ common ports
2. **Full TCP `-p-` sweep** — all 65,535 ports at `--min-rate 5000`
3. **Targeted `-sC -sV`** — service versions and default scripts on discovered ports
4. **UDP top 50 scan** — UDP is NOT skipped
5. **OS detection** — Linux vs Windows guess

For each discovered port, `htb_service_enum.sh` runs service-specific enumeration:
- SSH → auth methods, algorithms, host keys
- HTTP/HTTPS → `htb_web_enum.sh` (full web analysis)
- SMB → shares, OS, signing, null sessions
- LDAP → RootDSE, naming contexts
- FTP → anonymous access, version probes
- Kerberos → user enumeration
- Database services → version probes
- RPC → endpoint enumeration
- WinRM → authentication check
- And more...

### 3. Web Enumeration (auto-triggered when HTTP/S is found)

- Downloads raw HTML body and response headers
- Tech fingerprinting via `whatweb`
- Deep HTML inspection: comments, inline scripts, hidden inputs, `__NEXT_DATA__`, base64 strings, data attributes, `meta` tags, forms, `href` targets
- Downloads all linked JS and CSS files
- Runs `source_artifact_summary.py` on every downloaded source artifact — extracting API keys, credentials, endpoints, paths, source maps, framework markers, secret patterns
- Directory fuzzing with `ffuf` using `raft-medium-directories.txt`
- Standard info-disclosure probe: `/metrics`, `/actuator`, `/.env`, `.git/config`, `/debug`, `/phpinfo.php`, `/swagger.json`, `/graphql`, and 30+ more

### 4. Active Directory / Windows Discovery

For AD/DC targets:

- Generates **hundreds to low thousands** of evidence-derived username candidates using `ad_username_candidates.py`
- Mines: box name, domain, hostnames, NetBIOS, cert names, banners, web/source text, theme words, and common HTB patterns (`first.last`, `flast`, `first_last`, `svc-*`, `backup`, etc.)
- Kerberos user enumeration with `kerbrute` or nmap NSE
- AS-REP roasting only for confirmed usernames
- Small failed candidate sets are treated as "need more ideas" not "no users exist"

### 5. Anti-Loop Gates

- **Attempt guard**: No more than 3 attempts at the same vector without new evidence
- **CVE rabbit-hole stop**: Max 2 exploit variants per CVE. If distro patch level contradicts exploitability, one validation + one exploit, then pivot
- **Decision gate**: Before reporting failure, checks full TCP, UDP, source analysis, AD user depth, credential reuse, and service coverage
- **Port-knock triage**: When attack surface is tiny (≤2 TCP ports, no creds, no access), runs one bounded port-knock test with common sequences

### 6. Credential Chaining

When credentials are found, `credential_matrix.sh` tests them against every discovered service:
- SSH, SMB, LDAP, WinRM, FTP, MSSQL, and any authenticated web endpoints
- Successful logins are immediately recorded in `state.json`
- The agent re-enumerates with auth when new credentials are validated

### 7. Flag Capture

Standard HTB flag paths are checked automatically:
- Linux: `/home/*/user.txt`, `/root/root.txt`
- Windows: `C:\Users\*\Desktop\user.txt`, `C:\Users\Administrator\Desktop\root.txt`

Captured flags are stored in `state.json` and logged in `log.md`. Full values are saved (masked in logs). An engagement is **not** marked completed unless expected flags are captured.

---

## Sudo Model

- Every agent command is wrapped with `sudo -n -E` (non-interactive, preserves environment)
- `run-htb.sh` primes sudo with `sudo -v` on startup and runs a background keepalive loop
- If `sudo -n` fails, the agent stops with a clear message — no hung prompts
- `run_tool` always uses sudo; `run_privileged` is only for explicit `/etc/hosts` and VM setup
- Never stores sudo credentials. Configure passwordless sudo in your VM:
  ```bash
  sudo visudo -f /etc/sudoers.d/greenapple
  ```
  Add: `your_username ALL=(ALL) NOPASSWD: ALL`

---

## Brute-Force Policy

- **Default: avoid.** Brute-forcing wastes time on HTB and is rarely the intended path.
- **Allowed for enumeration:** directory busting, subdomain/vhost fuzzing, username enumeration
- **Credential brute-forcing:** only when there's concrete signal it's the intended vector
- **5-minute cap** unless the machine explicitly hints at a longer attack
- When stuck: revisit enumeration, check for missed attack surfaces, re-examine gathered data

---

## Known Anti-Patterns (Don't Do These)

| Anti-Pattern | Fix |
|-------------|-----|
| Assuming port 80/HTTP exists | Send bare IP; let recon discover services |
| Skipping UDP scan | UDP top 50 is mandatory |
| Reading file sizes but not file contents | Deep source analysis extracts raw content |
| Trying the same CVE exploit 6 times | Max 2 variants, then pivot |
| Using 77-name wordlist on an AD box | Generate hundreds from box clues |
| Finding credentials but not testing reuse | Credential matrix auto-tests across services |
| Getting a shell but skipping internal enum | Post-exploit checklist runs automatically |
| Marking completed without capturing flags | Gate blocks `completed` until flags captured |
| Treating AD hardening as dead ends | SMB signing + null session denied = info, not blocker |
| Making up tiny wordlists | `/usr/share/seclists/` and `/usr/share/wordlists/` are on your VM |

---

## Output Layout

```
engagements/
  └── 2026-06-19-093021-10-129-0-0/
      ├── scope.json
      ├── state.json
      ├── notes.md
      ├── log.md
      ├── findings.md
      ├── report.md              ← the final walkthrough
      ├── hosts.tsv
      ├── auth.json
      ├── cases.db
      ├── scans/
      │   ├── nmap_full_tcp.txt
      │   ├── nmap_targeted_services.txt
      │   ├── nmap_udp_top.txt
      │   ├── nmap_services.json
      │   ├── ffuf_dirs_80.json
      │   ├── html_deep_80.json
      │   └── ...
      ├── downloads/
      │   ├── root_80.html
      │   ├── headers_80.txt
      │   ├── web_main.js
      │   └── ...
      └── tools/
          └── ...
```

---

## Troubleshooting

**"sudo requires interactive password"** — Run `sudo -v` before launching `run-htb.sh`, or configure passwordless sudo above.

**"Target did not answer quick ICMP/TCP checks"** — Normal for some HTB machines. The full TCP sweep handles this.

**"No credentials from source analysis"** — Check `scans/html_deep_*.json` and `downloads/` for raw evidence. The `source_artifact_summary.py` output shows what was actually found.

**Flag paths not found** — Standard paths are `/home/*/user.txt`, `/root/root.txt` (Linux) and `C:\Users\*\Desktop\user.txt`, `C:\Users\Administrator\Desktop\root.txt` (Windows). Some boxes use non-standard paths — check `notes.md` and `findings.md` for the flag location.

**Tool not found** — Run `./scripts/ensure_tools.sh <engagement_dir> <tool_name>` to auto-install missing tools.

---

## Development

- **Runtime only exists under `agent/`.** Root files are meta/installer only.
- **OpenCode config:** `agent/.opencode/opencode.json` is the source of truth.
- **Agent prompts:** `agent/.opencode/prompts/agents/*.txt`
- **Skills:** `agent/skills/*/SKILL.md`
- **Reference docs:** `agent/references/`
- **Do not add root `.opencode/`, `scripts/`, `skills/`, or `references/`**

### Verify

```bash
bash -n install.sh
bash -n agent/scripts/*.sh agent/scripts/lib/*.sh
python3 -m py_compile agent/scripts/*.py
jq empty agent/.opencode/opencode.json
GREENAPPLE_SKIP_PREREQ_CHECKS=1 ./install.sh --dry-run opencode
```

---

GreenAppleAgent is built on OpenCode, heavily modified from [RedteamAgent](https://github.com/NeoTheCapt/RedteamAgent). Built for HTB. Built for Kali. Built to pwn.
