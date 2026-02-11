#!/bin/bash
set -e

export HOME=/home/bun
export PATH="/opt/opencode/bin:/usr/local/bin:$PATH"

echo "Checking Bun installation..."
if ! command -v bun >/dev/null 2>&1; then
  echo "ERROR: Bun not found. Exiting."
  exit 1
fi
echo "Bun $(bun --version 2>&1 || echo unknown)"

echo "Checking OpenCode installation..."
MIN_OPENCODE_VERSION="1.0.137"

version_gte() {
  printf '%s\n%s\n' "$2" "$1" | sort -V -C
}

if ! command -v opencode >/dev/null 2>&1; then
  echo "OpenCode not found. Installing..."
  curl -fsSL https://opencode.ai/install | bash
  command -v opencode >/dev/null 2>&1 || { echo "ERROR: Failed to install OpenCode."; exit 1; }
  echo "OpenCode installed."
fi

OPENCODE_VERSION=$(opencode --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")
echo "OpenCode $OPENCODE_VERSION"

if [ "$OPENCODE_VERSION" != "unknown" ]; then
  if ! version_gte "$OPENCODE_VERSION" "$MIN_OPENCODE_VERSION"; then
    echo "OpenCode $OPENCODE_VERSION below minimum $MIN_OPENCODE_VERSION, upgrading..."
    opencode upgrade || curl -fsSL https://opencode.ai/install | bash
    OPENCODE_VERSION=$(opencode --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")
    echo "OpenCode upgraded to $OPENCODE_VERSION"
  fi
fi

if [ -z "$AUTH_SECRET" ]; then
  cat >&2 <<'EOF'
ERROR: AUTH_SECRET is required but not set.

Generate one with: openssl rand -base64 32

  environment:
    - AUTH_SECRET=your-secure-random-secret-here
EOF
  exit 1
fi

echo "Starting OpenCode Manager..."
exec "$@"
