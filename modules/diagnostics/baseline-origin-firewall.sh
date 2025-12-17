#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./baseline-wrapper-common.sh
. "$SCRIPT_DIR/baseline-wrapper-common.sh"

REPO_ROOT="$(baseline_wrapper_repo_root)"
baseline_wrapper_load_libs "$REPO_ROOT" baseline_common.sh baseline.sh baseline_origin.sh

domain="${1:-${HZ_BASELINE_DOMAIN:-}}"
lang="$(baseline_wrapper_normalize_lang "${2:-${HZ_BASELINE_LANG:-${HZ_LANG:-zh}}}")"

group="ORIGIN/FW"
baseline_init
baseline_wrapper_missing_tools_warn "$group" "$lang" curl wget systemctl ss netstat

if [ -z "$domain" ]; then
  baseline_wrapper_mark_domain_skipped "$group" "$lang"
else
  baseline_origin_run "$domain" "$lang"
fi

baseline_wrapper_finalize "$group" "$domain" "$lang"
