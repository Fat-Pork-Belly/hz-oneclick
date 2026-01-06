#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ENTRY="${SCRIPT_DIR}/lib/entry.sh"

# Basic permission check (prefer root for install operations)
if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: Please run as root (sudo -i) for full functionality." >&2
fi

if [ ! -f "$ENTRY" ]; then
  echo "ERROR: Missing entry script: $ENTRY" >&2
  exit 1
fi

chmod +x "$ENTRY" || true

# shellcheck source=/dev/null
source "$ENTRY"
