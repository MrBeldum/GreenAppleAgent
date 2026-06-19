#!/usr/bin/env python3
"""HTB state tracker: read/write structured engagement state.

state.json tracks: target, hostnames, OS, ports/services, usernames,
credentials, shells, flags, attempted vectors, scan completion gates.
notes.md tracks: freeform sections the agent appends to during the run.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

STATE_FIELDS = {
    "target_ip": "",
    "hostnames": [],
    "os_guess": "",
    "os_confidence": "",
    "tcp_ports_services": {},
    "udp_ports_services": {},
    "full_tcp_scan_done": False,
    "udp_scan_done": False,
    "usernames_discovered": [],
    "credentials": [],
    "hashes": [],
    "keys": [],
    "tickets": [],
    "access_level": "none",
    "shells": [],
    "flags_captured": {"user": False, "root": False, "user_value": "", "root_value": ""},
    "attempted_vectors": [],
    "dead_ends": [],
    "services_enumerated": [],
}

NOTES_SECTIONS = [
    "Target Information",
    "Open Services",
    "Web Findings",
    "Credentials Found",
    "Exploitation Attempts",
    "User Shell Path",
    "Privilege Escalation Path",
    "Dead Ends",
]


def _now_utc() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def cmd_init(args: argparse.Namespace) -> int:
    path = Path(args.dir) / "state.json"
    if path.exists():
        print(f"state.json already exists at {path}", file=sys.stderr)
        return 1
    state = dict(STATE_FIELDS)
    state["target_ip"] = args.target_ip or ""
    state["created_at"] = _now_utc()
    state["updated_at"] = _now_utc()
    path.write_text(json.dumps(state, indent=2) + "\n")

    notes_path = Path(args.dir) / "notes.md"
    if not notes_path.exists():
        lines = [
            "# Engagement Notes\n",
            f"**Target**: {args.target_ip or 'unknown'}\n",
            f"**Created**: {_now_utc()}\n",
        ]
        for section in NOTES_SECTIONS:
            lines.append(f"\n## {section}\n\n")
        notes_path.write_text("".join(lines))
    print(f"Initialized {path}")
    return 0


def cmd_set(args: argparse.Namespace) -> int:
    path = Path(args.dir) / "state.json"
    if not path.exists():
        print(f"state.json not found at {path}", file=sys.stderr)
        return 1
    state = json.loads(path.read_text())
    try:
        value = json.loads(args.value)
    except json.JSONDecodeError:
        value = args.value
    if args.append_flag:
        existing = state.get(args.key, [])
        if isinstance(existing, list):
            if value not in existing:
                existing.append(value)
                state[args.key] = existing
        elif isinstance(existing, dict) and isinstance(value, dict):
            existing.update(value)
            state[args.key] = existing
        else:
            state[args.key] = value
    else:
        state[args.key] = value
    state["updated_at"] = _now_utc()
    path.write_text(json.dumps(state, indent=2) + "\n")
    return 0


def cmd_add_attempt(args: argparse.Namespace) -> int:
    path = Path(args.dir) / "state.json"
    if not path.exists():
        print(f"state.json not found at {path}", file=sys.stderr)
        return 1
    state = json.loads(path.read_text())
    entry = {
        "timestamp": _now_utc(),
        "vector": args.vector,
        "agent": args.agent or "operator",
        "result": args.result,
        "notes": args.notes or "",
    }
    state.setdefault("attempted_vectors", []).append(entry)
    state["updated_at"] = _now_utc()
    path.write_text(json.dumps(state, indent=2) + "\n")
    return 0


def cmd_add_dead_end(args: argparse.Namespace) -> int:
    path = Path(args.dir) / "state.json"
    if not path.exists():
        print(f"state.json not found at {path}", file=sys.stderr)
        return 1
    state = json.loads(path.read_text())
    entry = {
        "timestamp": _now_utc(),
        "vector": args.vector,
        "reason": args.reason,
        "lessons": args.lessons or "",
    }
    seen = {(d.get("vector"), d.get("reason")) for d in state.get("dead_ends", [])}
    if (args.vector, args.reason) not in seen:
        state.setdefault("dead_ends", []).append(entry)
    state["updated_at"] = _now_utc()
    path.write_text(json.dumps(state, indent=2) + "\n")
    return 0


def cmd_add_credential(args: argparse.Namespace) -> int:
    path = Path(args.dir) / "state.json"
    if not path.exists():
        print(f"state.json not found at {path}", file=sys.stderr)
        return 1
    state = json.loads(path.read_text())
    entry = {
        "timestamp": _now_utc(),
        "type": args.cred_type,
        "username": args.username or "",
        "value": args.value or "",
        "source": args.source or "",
        "notes": args.notes or "",
    }
    seen = {(c.get("username"), c.get("value"), c.get("type")) for c in state.get("credentials", [])}
    if (args.username or "", args.value or "", args.cred_type) not in seen:
        state.setdefault("credentials", []).append(entry)
    state["updated_at"] = _now_utc()
    path.write_text(json.dumps(state, indent=2) + "\n")
    return 0


def cmd_add_flag(args: argparse.Namespace) -> int:
    path = Path(args.dir) / "state.json"
    if not path.exists():
        print(f"state.json not found at {path}", file=sys.stderr)
        return 1
    state = json.loads(path.read_text())
    flags = state.setdefault("flags_captured", {"user": False, "root": False, "user_value": "", "root_value": ""})
    flags[args.flag_type] = True
    flags[f"{args.flag_type}_value"] = args.flag_value
    state["updated_at"] = _now_utc()
    path.write_text(json.dumps(state, indent=2) + "\n")
    flags_count = sum(1 for f in ("user", "root") if flags.get(f))
    total = 2
    print(f"Flag captured: {args.flag_type} ({flags_count}/{total})")
    return 0


def cmd_show(args: argparse.Namespace) -> int:
    path = Path(args.dir) / "state.json"
    if not path.exists():
        print("state.json not found", file=sys.stderr)
        return 1
    state = json.loads(path.read_text())
    print(json.dumps({
        "target_ip": state.get("target_ip"),
        "hostnames": state.get("hostnames", []),
        "os_guess": state.get("os_guess"),
        "open_tcp_ports": list(state.get("tcp_ports_services", {}).keys()),
        "open_udp_ports": list(state.get("udp_ports_services", {}).keys()),
        "scans": {"full_tcp": state.get("full_tcp_scan_done"), "udp": state.get("udp_scan_done")},
        "usernames_found": len(state.get("usernames_discovered", [])),
        "credentials_found": len(state.get("credentials", [])),
        "access_level": state.get("access_level", "none"),
        "flags": state.get("flags_captured", {}),
        "attempted_vectors": len(state.get("attempted_vectors", [])),
        "dead_ends": len(state.get("dead_ends", [])),
        "updated_at": state.get("updated_at"),
    }, indent=2))
    return 0


def cmd_append_notes(args: argparse.Namespace) -> int:
    notes_path = Path(args.dir) / "notes.md"
    if not notes_path.exists():
        print("notes.md not found", file=sys.stderr)
        return 1
    section = args.section
    content = args.content.strip()
    timestamp = _now_utc()
    entry = f"\n**[{timestamp}]** {content}\n"

    existing = notes_path.read_text()
    header = f"## {section}"
    if header in existing:
        parts = existing.split(header, 1)
        next_header_idx = parts[1].find("\n## ")
        if next_header_idx != -1:
            new_text = parts[0] + header + parts[1][:next_header_idx] + entry + parts[1][next_header_idx:]
        else:
            new_text = parts[0] + header + parts[1] + entry
    else:
        new_text = existing.rstrip() + f"\n{header}\n{entry}\n"
    notes_path.write_text(new_text)
    print(f"Appended to {section}")
    return 0


def cmd_count_attempts(args: argparse.Namespace) -> int:
    path = Path(args.dir) / "state.json"
    if not path.exists():
        print("0")
        return 0
    state = json.loads(path.read_text())
    vec = args.vector_pattern.lower()
    count = sum(1 for a in state.get("attempted_vectors", [])
                if vec in a.get("vector", "").lower())
    print(count)
    return 0


def cmd_is_gate_clear(args: argparse.Namespace) -> int:
    path = Path(args.dir) / "state.json"
    if not path.exists():
        print("MISSING")
        return 1
    state = json.loads(path.read_text())
    checks = {
        "full_tcp": state.get("full_tcp_scan_done", False),
        "udp": state.get("udp_scan_done", False),
        "source_review": state.get("source_analysis_done", False),
        "ad_users": state.get("ad_username_enum_done", False),
        "services_enumerated": len(state.get("services_enumerated", [])) > 0,
    }
    failures = [k for k, v in checks.items() if not v]
    if failures:
        print(f"BLOCKED: {', '.join(failures)}")
        return 1
    print("CLEAR")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="HTB state tracker")
    sub = parser.add_subparsers(dest="action")

    p = sub.add_parser("init", help="Initialize state.json and notes.md")
    p.add_argument("dir", help="Engagement directory")
    p.add_argument("--target-ip", default="", help="Target IP address")

    p = sub.add_parser("set", help="Set a state key")
    p.add_argument("dir")
    p.add_argument("key")
    p.add_argument("value")
    p.add_argument("--append", dest="append_flag", action="store_true", help="Append to list or merge dict")

    p = sub.add_parser("add-attempt", help="Record an attempted vector")
    p.add_argument("dir")
    p.add_argument("--agent", default="operator")
    p.add_argument("--vector", required=True)
    p.add_argument("--result", required=True)
    p.add_argument("--notes", default="")

    p = sub.add_parser("add-dead-end", help="Record a dead end")
    p.add_argument("dir")
    p.add_argument("--vector", required=True)
    p.add_argument("--reason", required=True)
    p.add_argument("--lessons", default="")

    p = sub.add_parser("add-credential", help="Record a discovered credential")
    p.add_argument("dir")
    p.add_argument("--type", dest="cred_type", default="password")
    p.add_argument("--username", default="")
    p.add_argument("--value", default="")
    p.add_argument("--source", default="")
    p.add_argument("--notes", default="")

    p = sub.add_parser("add-flag", help="Record a captured flag")
    p.add_argument("dir")
    p.add_argument("--type", dest="flag_type", required=True, choices=["user", "root"])
    p.add_argument("--value", dest="flag_value", required=True)

    p = sub.add_parser("show", help="Show state summary")
    p.add_argument("dir")

    p = sub.add_parser("append-notes", help="Append to a notes.md section")
    p.add_argument("dir")
    p.add_argument("--section", required=True)
    p.add_argument("--content", required=True)

    p = sub.add_parser("count-attempts", help="Count attempts matching a pattern")
    p.add_argument("dir")
    p.add_argument("--pattern", dest="vector_pattern", default="")

    p = sub.add_parser("gate-check", help="Check if all scan/enum gates are clear")
    p.add_argument("dir")

    args = parser.parse_args()
    if not args.action:
        parser.print_help()
        return 1

    actions = {
        "init": cmd_init,
        "set": cmd_set,
        "add-attempt": cmd_add_attempt,
        "add-dead-end": cmd_add_dead_end,
        "add-credential": cmd_add_credential,
        "add-flag": cmd_add_flag,
        "show": cmd_show,
        "append-notes": cmd_append_notes,
        "count-attempts": cmd_count_attempts,
        "gate-check": cmd_is_gate_clear,
    }
    return actions[args.action](args)


if __name__ == "__main__":
    sys.exit(main())
