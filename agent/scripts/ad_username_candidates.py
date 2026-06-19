#!/usr/bin/env python3
"""Generate evidence-derived AD username candidates for HTB machines.

Mines the box name, domain, hostnames, banners, theme words,
and common HTB name patterns to produce hundreds of candidates.
"""

from __future__ import annotations

import argparse
import itertools
import json
import os
import sys
from pathlib import Path

COMMON_NAMES = [
    "alex", "andrew", "anna", "ben", "chris", "daniel", "david", "emily",
    "emma", "eric", "frank", "grace", "hannah", "henry", "isabel", "jack",
    "james", "john", "josh", "julia", "karen", "kevin", "laura", "leo",
    "lisa", "mark", "michael", "nancy", "nick", "olivia", "oscar", "paul",
    "peter", "rachel", "robert", "ryan", "sam", "sarah", "simon", "smith",
    "steven", "susan", "thomas", "tim", "tom", "victor", "william",
]

ROLE_PREFIXES = ["svc", "svc-", "svc_", "adm", "admin", "backup", "support",
                 "helpdesk", "web", "sql", "db", "ftp", "srv", "dev", "test"]


def build_candidates(
    target_words: list[str],
    domain_parts: list[str],
    common_names: list[str],
    output_path: str,
) -> int:
    users: set[str] = set()

    for word in target_words:
        users.add(word)
        users.add(word.lower())
        users.add(word.capitalize())
        for prefix in ROLE_PREFIXES:
            users.add(f"{prefix}{word}")
            users.add(f"{prefix}_{word}")
            users.add(f"{prefix}.{word}")

    for part in domain_parts:
        clean = part.strip().lower()
        if clean and len(clean) > 1 and clean not in {"htb", "com", "org", "net", "local"}:
            users.add(clean)
            for prefix in ROLE_PREFIXES:
                users.add(f"{prefix}{clean}")

    for first, last in itertools.product(common_names, common_names):
        if first == last:
            continue
        users.add(f"{first}")
        users.add(f"{first}.{last}")
        users.add(f"{first}{last}")
        users.add(f"{first[0]}{last}")
        users.add(f"{first}{last[0]}")
        users.add(f"{first}_{last}")

        for role in ["admin", "adm", "svc", "backup", "support"]:
            users.add(f"{first}.{role}")
            users.add(f"{role}.{first}")

    sorted_users = sorted(u for u in users if len(u) >= 2 and len(u) <= 32)

    Path(output_path).write_text("\n".join(sorted_users) + "\n")
    print(f"Generated {len(sorted_users)} candidate usernames -> {output_path}")
    return len(sorted_users)


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate HTB AD username candidates")
    parser.add_argument("--output", required=True, help="Output file path")
    parser.add_argument("--state-file", default="", help="state.json path for target words")
    parser.add_argument("--target-words", nargs="*", default=[], help="Box name, theme words")
    parser.add_argument("--domain", default="", help="Domain (e.g. checkpoint.htb)")
    args = parser.parse_args()

    target_words: list[str] = list(args.target_words)

    if args.state_file and Path(args.state_file).exists():
        state = json.loads(Path(args.state_file).read_text())
        hostnames = state.get("hostnames", [])
        for h in hostnames:
            parts = h.replace(".htb", "").replace(".local", "").split(".")
            for p in parts:
                if p and len(p) > 1 and p not in target_words:
                    target_words.append(p)

        ip = state.get("target_ip", "")
        if ip and ip not in target_words:
            pass

    if args.domain:
        domain_parts = args.domain.replace(".htb", "").replace(".local", "").split(".")
        for p in domain_parts:
            if p and len(p) > 1 and p not in target_words:
                target_words.append(p)
    else:
        domain_parts = []

    if not target_words:
        print("No target words provided; using defaults", file=sys.stderr)
        target_words = ["user", "admin", "operator"]

    count = build_candidates(
        target_words=target_words,
        domain_parts=domain_parts if args.domain else [],
        common_names=COMMON_NAMES,
        output_path=args.output,
    )
    return 0 if count > 0 else 1


if __name__ == "__main__":
    sys.exit(main())
