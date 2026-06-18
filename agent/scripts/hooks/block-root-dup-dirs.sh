#!/usr/bin/env bash
# Block commits that re-introduce root-level duplicates of agent runtime dirs.
# agent/ is the canonical runtime source copied by install.sh.

set -euo pipefail

forbidden=( ".opencode" "scripts" "skills" "references" )
violations=()

for path in "${forbidden[@]}"; do
  if git diff --cached --name-only | grep -qE "^${path}/"; then
    violations+=("$path/")
  fi
done

if [ ${#violations[@]} -gt 0 ]; then
  echo "ERROR: commit introduces root-level paths that duplicate agent/ runtime:" >&2
  printf '  %s\n' "${violations[@]}" >&2
  echo "" >&2
  echo "Move these changes under agent/ instead." >&2
  exit 1
fi
