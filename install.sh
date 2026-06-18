#!/usr/bin/env bash
# Install the OpenCode HTB runtime for ParrotOS/Kali VMs.

set -euo pipefail

PRODUCT="opencode"
TARGET_DIR="${GREENAPPLE_DIR:-$HOME/greenapple-agent}"
DRY_RUN=0
FORCE=0

usage() {
  cat <<'EOF'
Usage: ./install.sh [--dry-run] [--force] [opencode] [target_dir]

Installs the OpenCode-only GreenAppleAgent runtime for ParrotOS/Kali HTB VMs.
Docker, Claude Code, Codex, and orchestrator installs are intentionally not supported.

Options:
  --dry-run   Validate sources and print actions without writing files
  --force     Replace an existing runtime while preserving engagements/.env
  -h, --help  Show this help
EOF
}

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --force) FORCE=1 ;;
    -h|--help) usage; exit 0 ;;
    opencode) PRODUCT="opencode" ;;
    claude|codex|docker)
      echo "ERROR: only the OpenCode HTB runtime is supported in this fork." >&2
      exit 1
      ;;
    *) TARGET_DIR="$arg" ;;
  esac
done

if [[ "$PRODUCT" != "opencode" ]]; then
  echo "ERROR: unsupported product: $PRODUCT" >&2
  exit 1
fi

if [[ -d agent/.opencode ]]; then
  REPO_ROOT="$(pwd)"
  SOURCE_DIR="$REPO_ROOT/agent"
elif [[ -d .opencode && -d scripts && -d skills ]]; then
  SOURCE_DIR="$(pwd)"
  REPO_ROOT="$(cd "$SOURCE_DIR/.." && pwd)"
else
  echo "ERROR: run this from the repo root or from an installed agent runtime." >&2
  exit 1
fi

ok() { printf '[OK] %s\n' "$1"; }
warn() { printf '[WARN] %s\n' "$1"; }
fail() { printf '[FAIL] %s\n' "$1"; }

echo "GreenAppleAgent HTB OpenCode installer"
echo "Source: $SOURCE_DIR"
echo "Target: $TARGET_DIR"
echo ""

errors=0

if [[ "${GREENAPPLE_SKIP_PREREQ_CHECKS:-0}" != "1" ]]; then
  required=(opencode curl jq sqlite3 python3 git nmap)
  for tool in "${required[@]}"; do
    if command -v "$tool" >/dev/null 2>&1; then
      ok "$tool"
    else
      fail "$tool not found"
      errors=$((errors + 1))
    fi
  done
else
  warn "Skipping prerequisite checks (GREENAPPLE_SKIP_PREREQ_CHECKS=1)"
fi

for path in .opencode/opencode.json .opencode/commands/htb.md scripts/htb_preflight.sh scripts/opencode-htb.sh scripts/lib/container.sh references/hackthebox-machine-mode.md; do
  if [[ -e "$SOURCE_DIR/$path" ]]; then
    ok "$path"
  else
    fail "missing source path: $path"
    errors=$((errors + 1))
  fi
done

if command -v jq >/dev/null 2>&1; then
  jq empty "$SOURCE_DIR/.opencode/opencode.json"
else
  python3 -m json.tool "$SOURCE_DIR/.opencode/opencode.json" >/dev/null
fi
ok "OpenCode config validates"

if [[ $errors -gt 0 ]]; then
  echo ""
  fail "$errors prerequisite/source check(s) failed"
  exit 1
fi

if [[ $DRY_RUN -eq 1 ]]; then
  echo ""
  ok "Dry run complete; no files written"
  exit 0
fi

if [[ -e "$TARGET_DIR" && $FORCE -ne 1 ]]; then
  echo "ERROR: target exists: $TARGET_DIR" >&2
  echo "Use --force to replace runtime files while preserving engagements and .env." >&2
  exit 1
fi

tmp_preserve=""
if [[ -e "$TARGET_DIR" ]]; then
  tmp_preserve="$(mktemp -d)"
  for keep in engagements .env auth.json; do
    if [[ -e "$TARGET_DIR/$keep" ]]; then
      mv "$TARGET_DIR/$keep" "$tmp_preserve/$keep"
    fi
  done
  rm -rf "$TARGET_DIR"
fi

mkdir -p "$TARGET_DIR"
for item in .opencode skills references scripts engagements .env.example; do
  if [[ -e "$SOURCE_DIR/$item" ]]; then
    cp -a "$SOURCE_DIR/$item" "$TARGET_DIR/"
  fi
done

if [[ -n "$tmp_preserve" ]]; then
  for keep in engagements .env auth.json; do
    if [[ -e "$tmp_preserve/$keep" ]]; then
      rm -rf "$TARGET_DIR/$keep"
      mv "$tmp_preserve/$keep" "$TARGET_DIR/$keep"
    fi
  done
  rmdir "$tmp_preserve" 2>/dev/null || true
fi

mkdir -p "$TARGET_DIR/engagements"
if [[ ! -f "$TARGET_DIR/.env" ]]; then
  cp "$TARGET_DIR/.env.example" "$TARGET_DIR/.env"
  warn "Created $TARGET_DIR/.env from template"
fi

cat > "$TARGET_DIR/run-htb.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
exec ./scripts/opencode-htb.sh "$@"
EOF
chmod +x "$TARGET_DIR/run-htb.sh"
chmod +x "$TARGET_DIR/scripts/"*.sh "$TARGET_DIR/scripts/lib/"*.sh "$TARGET_DIR/scripts/hooks/"*.sh 2>/dev/null || true

echo ""
ok "Installation complete"
echo ""
echo "Start:"
echo "  cd $TARGET_DIR"
echo "  ./run-htb.sh"
echo ""
echo "Then run in OpenCode:"
echo "  /htb 10.10.x.x"
