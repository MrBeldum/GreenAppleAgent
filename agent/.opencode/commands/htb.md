# Command: HackTheBox Machine Engagement

You are starting an authorized HackTheBox CTF/lab machine assessment from a Parrot/Kali VM using OpenCode and host-installed tools.
Your objective is the intended HackTheBox machine path: enumerate, plan, exploit, recover user and root flags when present, and produce a detailed beginner-friendly Markdown walkthrough.

## Scope

- The target must be the single HackTheBox machine IP/URL supplied by the user.
- If the user supplies a bare IP such as `10.x.x.x`, normalize to `http://10.x.x.x` for initial workspace creation, then let recon discover actual open services.
- Do not enumerate unrelated ranges, other HackTheBox players, public internet infrastructure, or domains that are not proven to belong to this machine.
- Treat all activity as ethical CTF/lab work: evidence-driven, documented, and bounded to the assigned machine.

## Before Engagement

Run the HackTheBox VM preflight first:

```bash
./scripts/htb_preflight.sh "$ARGUMENTS"
```

If the VPN is missing or required tools are missing, explain the issue in beginner-friendly language and continue only when the target is reachable enough for a bounded scan.

## Execute

After the preflight, execute the embedded `/engage` workflow that follows this HackTheBox preamble.
Keep the HackTheBox scope/methodology rules active for every phase.

```text
$ARGUMENTS
```

Use the methodology in `references/hackthebox-machine-mode.md` throughout the run.

Brute-force and password-cracking rule: keep attempts under 5 minutes unless the box gives an explicit hint that a longer cracking/brute-force path is intended.

Final report rule: document recon, enumeration, foothold, privilege escalation, user/root flag proof, cleanup, and lessons learned in `report.md`.
