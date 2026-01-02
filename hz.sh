#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Horizon OneClick - Main Entry Point (Restored v2.2.0)
# -----------------------------------------------------------------------------
set -Eeo pipefail

# --- 1. Environment Setup ---
# Calculate absolute root path
export REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source Common Library if available
if [[ -f "${REPO_ROOT}/lib/common.sh" ]]; then
    source "${REPO_ROOT}/lib/common.sh"
else
    # Minimal fallback colors if lib is missing
    C_CYAN='\033[0;36m'
    C_RED='\033[0;31m'
    C_RESET='\033[0m'
    log_error() { echo -e "${C_RED}[ERROR] $*${C_RESET}"; }
fi

# --- 2. Helper Functions ---
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "Error: This script must be run as root."
        exit 1
    fi
}

show_header() {
    clear
    echo -e "${C_CYAN}"
    echo "================================================================"
    echo "   Horizon OneClick - LOMP Stack Installer (v2.2.0)"
    echo "================================================================"
    echo -e "${C_RESET}"
}

# --- 3. Main Menu Logic ---
check_root

while true; do
    show_header
    echo "1) 🚀 Install LOMP Stack (OpenLiteSpeed + WP + Redis) [Standard]"
    echo "2) 🛠️ System Diagnostics (Quick Triage)"
    echo "0) 🚪 Exit"
    echo ""
    read -r -p "Enter option [0-2]: " choice

    case "$choice" in
        1)
            # Launch the standard installer
            SCRIPT="${REPO_ROOT}/modules/wp/install-ols-wp-standard.sh"
            if [[ -f "$SCRIPT" ]]; then
                bash "$SCRIPT"
            else
                log_error "Installer script not found at: $SCRIPT"
                sleep 2
            fi
            ;;
        2)
            # Launch diagnostics
            SCRIPT="${REPO_ROOT}/modules/diagnostics/quick-triage.sh"
            if [[ -f "$SCRIPT" ]]; then
                bash "$SCRIPT"
            else
                log_error "Diagnostics script not found at: $SCRIPT"
                sleep 2
            fi
            ;;
        0)
            echo "Exiting..."
            exit 0
            ;;
        *)
            echo "Invalid option."
            sleep 1
            ;;
    esac
done
