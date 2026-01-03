#!/usr/bin/env bash
set -Eeuo pipefail

echo "🔍 Starting Integrity Check..."
ERROR=0

# 1) Check Non-Empty
for f in "hz.sh" "lib/ops_menu_lib.sh"; do
  if [[ ! -s "${f}" ]]; then
    echo "❌ FATAL: ${f} is empty (0 bytes)!"
    ERROR=1
  fi
done

# 2) Check Line Counts (Prevent Flattening)
HZ_LINES="$(wc -l < hz.sh | tr -d ' ')"
LIB_LINES="$(wc -l < lib/ops_menu_lib.sh | tr -d ' ')"

if [[ "${HZ_LINES}" -lt 20 ]]; then
  echo "❌ FATAL: hz.sh too short (${HZ_LINES} lines). Likely flattened."
  ERROR=1
fi

if [[ "${LIB_LINES}" -lt 50 ]]; then
  echo "❌ FATAL: lib/ops_menu_lib.sh too short (${LIB_LINES} lines). Likely flattened."
  ERROR=1
fi

# 3) Syntax Check
bash -n hz.sh || { echo "❌ FATAL: hz.sh syntax error."; ERROR=1; }
bash -n lib/ops_menu_lib.sh || { echo "❌ FATAL: lib/ops_menu_lib.sh syntax error."; ERROR=1; }

# 4) Shebang Check
if ! head -n 1 hz.sh | grep -q "bash"; then
  echo "❌ FATAL: hz.sh missing shebang."
  ERROR=1
fi

if [[ "${ERROR}" -eq 0 ]]; then
  echo "✅ ALL CHECKS PASSED. Files are valid."
  exit 0
else
  echo "🚨 VERIFICATION FAILED."
  exit 1
fi
