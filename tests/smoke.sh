#!/usr/bin/env bash
set -euo pipefail

echo "[smoke] collecting shell scripts (excluding modules/)"
mapfile -d '' files < <(find . -type f -name '*.sh' -not -path './modules/*' -print0)

echo "[smoke] bash -n syntax check"
for f in "${files[@]}"; do
  bash -n "$f"
done

if command -v shellcheck >/dev/null 2>&1; then
  echo "[smoke] shellcheck structural pass (non-blocking)"
  shellcheck -x "${files[@]}" || true
else
  echo "[smoke] shellcheck not available; skipping static lint"
fi

echo "[smoke] OK"
