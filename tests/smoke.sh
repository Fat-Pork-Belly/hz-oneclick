#!/usr/bin/env bash
set -euo pipefail

echo "[smoke] bash -n syntax check for all .sh"
while IFS= read -r -d '' f; do
  bash -n "$f"
done < <(find . -type f -name '*.sh' -print0)

echo "[smoke] OK"
