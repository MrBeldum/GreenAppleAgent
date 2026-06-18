# GreenAppleAgent for HTB

OpenCode agent setup for authorized Hack The Box / CTF machines from a ParrotOS or Kali Linux VM.
The agents are tuned for the intended HTB machine flow: enumerate, plan, exploit, recover user/root flags when present, and write a detailed Markdown walkthrough.

This fork is intentionally VM-native: it uses the pentesting tools already installed on the VM and does not require Docker.

## Scope

- Use only against machines you are authorized to test, such as assigned Hack The Box targets.
- Default workflow targets one machine IP/hostname at a time.
- Do not scan adjacent HTB ranges, VPN infrastructure, other players, or unrelated public domains.
- Brute forcing and password cracking are capped at 5 minutes unless the machine gives a clear hint that a longer attempt is intended.
- Final outputs should preserve proof and explain every major step toward foothold, user flag, privilege escalation, root flag, cleanup, and lessons learned.

## Requirements

- ParrotOS or Kali Linux VM
- HTB VPN connected before starting a machine
- OpenCode installed: `npm install -g opencode-ai`
- Required tools: `curl`, `jq`, `sqlite3`, `python3`, `git`, `nmap`
- Recommended tools: `ffuf`, `gobuster` or `feroxbuster`, `whatweb`, `nikto`, `nuclei`, `sqlmap`, `hydra`, `john`, `hashcat`, `searchsploit`, `smbclient`, `enum4linux-ng`, `netexec`, `evil-winrm`

## Install

```bash
./install.sh opencode ~/greenapple-agent
```

If installing over an existing runtime and preserving `engagements/` plus `.env`:

```bash
./install.sh --force opencode ~/greenapple-agent
```

## Start

```bash
cd ~/greenapple-agent
./run-htb.sh
```

`run-htb.sh` sets `GREENAPPLE_RUNTIME_MODE=local` and starts OpenCode with an auto-detected permission-bypass flag. That launch-time flag applies to the whole OpenCode session, so all registered agents inherit it. To force a specific equivalent flag, edit `.env`:

```bash
GREENAPPLE_OPENCODE_FLAGS=--allow-dangerously-skip-permissions
```

The launcher also auto-detects `--dangerously-skip-permissions` and `--dangerously-bypass-approvals-and-sandbox` when those are the flags exposed by your OpenCode build.

## Run A Machine

Inside OpenCode:

```text
/htb 10.10.x.x
```

The `/htb` command runs a VM preflight, creates an engagement workspace, and follows the HTB machine methodology in `references/hackthebox-machine-mode.md`.

## Manual Preflight

```bash
./scripts/htb_preflight.sh 10.10.x.x
```

This checks the OS profile, required tools, HTB VPN hints, and quick target reachability.

## Runtime Layout

```text
agent/
  .opencode/                  OpenCode config, commands, prompts, plugins
  scripts/                    Runtime helpers and queue/state scripts
  skills/                     Attack methodology skill files
  references/                 Tool notes, payloads, HTB methodology
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
