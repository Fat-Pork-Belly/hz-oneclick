#!/usr/bin/env bash
set -euo pipefail

DOC_ROOT="" PATH="/usr/bin:/bin" ./tools/wp-baseline-verify.sh >/dev/null
