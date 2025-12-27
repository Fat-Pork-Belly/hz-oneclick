#!/usr/bin/env bash
set -euo pipefail

strict=0
for arg in "$@"; do
  case "$arg" in
    --strict)
      strict=1
      ;;
    *)
      echo "ERROR: Unknown argument: $arg"
      echo "Usage: $0 [--strict]"
      exit 2
      ;;
  esac
done

if [[ ! -f .github/scripts/lint_bash.sh ]]; then
  echo "ERROR: scripts/lint.sh must be run from the repository root"
  exit 1
fi

# Keep discovery consistent with CI linting (.github/scripts/lint_bash.sh).
mapfile -d '' -t files < <(find ./modules ./tests ./.github/scripts -type f -name '*.sh' -print0)

script_count=${#files[@]}
echo "Found ${script_count} shell scripts"

if [[ $script_count -eq 0 ]]; then
  echo "No shell scripts found for lint checks"
  exit 0
fi

echo ""
echo "==> bash -n"
bash_status=0
for f in "${files[@]}"; do
  if ! bash -n "$f"; then
    bash_status=1
  fi
done
if [[ $bash_status -ne 0 ]]; then
  echo "ERROR: bash -n reported syntax issues"
  exit 1
fi

echo ""
echo "==> ShellCheck"
shellcheck_status=0
if command -v shellcheck >/dev/null 2>&1; then
  set +e
  shellcheck -x "${files[@]}"
  shellcheck_status=$?
  set -e
  if [[ $shellcheck_status -ne 0 ]]; then
    echo "ERROR: ShellCheck reported findings"
  fi
else
  shellcheck_status=127
  if [[ $strict -eq 1 ]]; then
    echo "ERROR: ShellCheck is required in strict mode"
  else
    echo "WARN: ShellCheck not installed; skipping"
  fi
fi

echo ""
echo "==> shfmt (check only)"
shfmt_status=0
if command -v shfmt >/dev/null 2>&1; then
  set +e
  shfmt -d -i 2 -ci -sr "${files[@]}"
  shfmt_status=$?
  set -e
  if [[ $shfmt_status -ne 0 ]]; then
    echo "ERROR: shfmt reported formatting differences"
  fi
else
  shfmt_status=127
  if [[ $strict -eq 1 ]]; then
    echo "ERROR: shfmt is required in strict mode"
  else
    echo "WARN: shfmt not installed; skipping"
  fi
fi

echo ""
echo "Summary: bash -n=${bash_status} shellcheck=${shellcheck_status} shfmt=${shfmt_status}"

if [[ $shellcheck_status -ne 0 && $shellcheck_status -ne 127 ]]; then
  exit 1
fi
if [[ $shfmt_status -ne 0 && $shfmt_status -ne 127 ]]; then
  exit 1
fi
if [[ $strict -eq 1 ]]; then
  if [[ $shellcheck_status -eq 127 || $shfmt_status -eq 127 ]]; then
    exit 1
  fi
fi

exit 0
