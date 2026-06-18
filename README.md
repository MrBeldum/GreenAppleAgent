# GreenAppleAgent For HackTheBox

GreenAppleAgent is an OpenCode setup for authorized HackTheBox and CTF lab machines from a ParrotOS or Kali Linux VM.

It helps you work through a machine in a repeatable way: check your VPN, enumerate services, test likely vulnerabilities, pursue user/root flags when they exist, and write a beginner-friendly walkthrough.

This project is VM-native. It uses the pentesting tools already installed in your ParrotOS/Kali VM and does not require Docker.

## Safety Rules

- Use this only on machines you are authorized to test, such as assigned HackTheBox targets.
- Work on one machine IP or hostname at a time.
- HackTheBox target IPs use the broader `10.x.x.x` pattern.
- Do not scan adjacent HackTheBox ranges, VPN infrastructure, other players, or unrelated public domains.
- Keep brute forcing and password cracking under 5 minutes unless the machine clearly hints that a longer attempt is intended.
- Save proof and explain each important step in the final walkthrough.

## What You Need

- A ParrotOS or Kali Linux VM.
- The HackTheBox VPN connected before you start a machine.
- OpenCode installed with `npm install -g opencode-ai`.
- Required tools: `curl`, `jq`, `sqlite3`, `python3`, `git`, and `nmap`.
- Recommended tools: `ffuf`, `gobuster` or `feroxbuster`, `whatweb`, `nikto`, `nuclei`, `sqlmap`, `hydra`, `john`, `hashcat`, `searchsploit`, `smbclient`, `enum4linux-ng`, `netexec`, `kerbrute`, `certipy`, `bloodhound-python`, `evil-winrm`, and `msfconsole` from Metasploit.
- Some VM setup actions need root privileges, such as adding proven in-scope hostnames to `/etc/hosts`. GreenAppleAgent never stores sudo usernames or passwords. Configure sudo in the VM, or run `sudo -v` before starting an autonomous session if your sudo policy requires a cached credential.

## Install

From the repository root, run:

```bash
./install.sh opencode ~/greenapple-agent
```

This copies the runnable agent files into `~/greenapple-agent` and creates a `.env` file from the template if one does not already exist.

If you already installed GreenAppleAgent and want to update it while keeping your previous `engagements/` and `.env`, run:

```bash
./install.sh --force opencode ~/greenapple-agent
```

## Start OpenCode

```bash
cd ~/greenapple-agent
./run-htb.sh
```

The launcher starts OpenCode in the installed runtime directory and sets `GREENAPPLE_RUNTIME_MODE=local`, which means tools run from your VM.

For normal use, leave `GREENAPPLE_OPENCODE_FLAGS` unset in `.env`. Advanced users can set extra OpenCode TUI flags or an explicit project path there if needed.

## Start A Machine

Inside OpenCode, run the `/htb` command with your assigned HackTheBox target:

```text
/htb 10.x.x.x
```

Use a bare IP when you only know the assigned machine. The agent treats this as a service-neutral target and discovers open services before deciding whether web crawling is appropriate.

You can also pass a URL or hostname when the machine explicitly requires one:

```text
/htb http://10.x.x.x
```

The `/htb` command runs a VM preflight, creates an engagement workspace, and follows the HackTheBox machine methodology in `references/hackthebox-machine-mode.md`.

## Manual Preflight

If you want to check your VM before opening OpenCode, run:

```bash
./scripts/htb_preflight.sh 10.x.x.x
```

The preflight checks your OS profile, required tools, HackTheBox VPN hints, and quick target reachability. A warning does not always mean the machine is down; some machines only answer on uncommon ports.

## Where Output Goes

Each machine gets an engagement folder under `engagements/`. Important outputs are kept there so you can review or resume later:

- `scans/` stores scan and enumeration output.
- `downloads/` stores fetched files and artifacts.
- `tools/` stores temporary tool output.
- `pids/` tracks background helper processes.
- `report.md` is the final walkthrough when generated.

## Runtime Layout

```text
agent/
  .opencode/                  OpenCode config, commands, prompts, plugins
  scripts/                    Runtime helpers and queue/state scripts
  skills/                     Attack methodology skill files
  references/                 Tool notes, payloads, HackTheBox methodology
  engagements/                Runtime output, ignored by git
install.sh                    OpenCode-only installer
AGENTS.md                     Repo-maintenance guidance for future agent sessions
```

## Development Notes

- OpenCode is the only supported CLI in this fork.
- `agent/.opencode/opencode.json` is the source of truth for agents, commands, instructions, and permissions.
- Target-facing commands should use `run_tool <tool>` even in local mode; this preserves engagement auth/user-agent behavior.
- Keep outputs under the active engagement directory: `$DIR/scans`, `$DIR/downloads`, `$DIR/tools`, `$DIR/pids`.
- Do not add root `.opencode/`, `scripts/`, `skills/`, or `references`; runtime files belong under `agent/`.

## Verification

```bash
bash -n install.sh
bash -n agent/scripts/htb_preflight.sh agent/scripts/opencode-htb.sh agent/scripts/lib/container.sh
jq empty agent/.opencode/opencode.json
GREENAPPLE_SKIP_PREREQ_CHECKS=1 ./install.sh --dry-run opencode
```

If `jq` is not installed, use:

```bash
python3 -m json.tool agent/.opencode/opencode.json >/dev/null
```
