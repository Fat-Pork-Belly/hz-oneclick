#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./baseline-wrapper-common.sh
. "$SCRIPT_DIR/baseline-wrapper-common.sh"

REPO_ROOT="$(baseline_wrapper_repo_root)"
baseline_wrapper_load_libs "$REPO_ROOT" baseline_common.sh baseline.sh baseline_lsws.sh

domain="${1:-${HZ_BASELINE_DOMAIN:-}}"
lang="$(baseline_wrapper_normalize_lang "${2:-${HZ_BASELINE_LANG:-${HZ_LANG:-zh}}}")"

group="LSWS/OLS"
baseline_init
baseline_wrapper_missing_tools_warn "$group" "$lang" systemctl

baseline_lsws_run "$domain" "$lang"

baseline_wrapper_finalize "$group" "$domain" "$lang"
