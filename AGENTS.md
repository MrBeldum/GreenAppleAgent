# Repository Guidance

## Scope
- This repo ships an OpenCode-only agent runtime for ParrotOS/Kali VMs against authorized HackTheBox/CTF machines.
- Docker, orchestrator UI, Claude Code, and Codex surfaces were intentionally removed.

## Layout
- Repo root is meta only: `install.sh`, `README.md`, `AGENTS.md`, and docs.
- `agent/` is the installable runtime copied by `install.sh`.
- OpenCode source of truth is `agent/.opencode/`: prompts in `prompts/agents/*.txt`, commands in `commands/*.md`, registration in `opencode.json`.
- Do not create root `.opencode/`, `scripts/`, `skills/`, or `references`; edit the matching `agent/` paths.

## Runtime
- Install with `./install.sh opencode ~/greenapple-agent`, start with `./run-htb.sh`, then run `/htb 10.x.x.x`.
- Default runtime is `GREENAPPLE_RUNTIME_MODE=local`; target-facing tools execute from the Parrot/Kali host VM.
- Keep using `run_tool <tool>` even in local mode so auth/user-agent handling and engagement paths stay consistent.
- `./scripts/htb_preflight.sh <target>` checks required tools, HackTheBox VPN hints, and quick reachability.

## HackTheBox Rules
- Scope is the single assigned machine plus hostnames proven to resolve to that machine.
- Do not scan adjacent HackTheBox ranges, VPN infrastructure, other players, or unrelated public domains.
- Brute forcing and cracking are capped at 5 minutes unless the machine explicitly hints at longer cracking.
- Final reports should be beginner-friendly walkthroughs: recon, enumeration, foothold, privesc, proof, cleanup, lessons learned.

## Verification
- Installer syntax: `bash -n install.sh`.
- Runtime wrapper syntax: `bash -n agent/scripts/htb_preflight.sh agent/scripts/opencode-htb.sh agent/scripts/lib/container.sh`.
- Config JSON: `jq empty agent/.opencode/opencode.json` or `python3 -m json.tool agent/.opencode/opencode.json >/dev/null`.
- OpenCode dry run: `GREENAPPLE_SKIP_PREREQ_CHECKS=1 ./install.sh --dry-run opencode`.
