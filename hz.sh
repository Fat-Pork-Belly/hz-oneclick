#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Horizon OneClick - Main Entry (Safe Mode)
# -----------------------------------------------------------------------------
export REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Attempt to load common lib, but don't crash if missing
if [[ -f "${REPO_ROOT}/lib/common.sh" ]]; then
    source "${REPO_ROOT}/lib/common.sh"
else
    # Fallback minimal functions
    check_root() { [[ $EUID -ne 0 ]] && echo "Run as root" && exit 1; }
    log_info() { echo -e "[INFO] $*"; }
fi

check_root

echo "================================================================"
echo "   Horizon OneClick - LOMP Stack Installer (Rescued)"
echo "================================================================"
echo "1) 🚀 Install LOMP Stack (WordPress)"
echo "2) 🛠️ Diagnostics"
echo "0) 🚪 Exit"
echo ""
read -r -p "Select: " choice

case "$choice" in
    1) bash "${REPO_ROOT}/modules/wp/install-ols-wp-standard.sh" ;;
    2) bash "${REPO_ROOT}/modules/diagnostics/quick-triage.sh" ;;
    0) exit 0 ;;
    *) echo "Invalid" ;;
esac
