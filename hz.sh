#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Horizon OneClick - Main Entry Point (Bootstrap Mode)
# Version: v2.2.0
# -----------------------------------------------------------------------------
set -Eeo pipefail

# --- 1. Bootstrap Logic: Ensure we are running inside a full Git Repo ---
# If running via curl (no .git dir or lib/common.sh missing), clone/pull to /opt.
REPO_DIR="/opt/hz-oneclick"

if [[ ! -d ".git" ]] && [[ ! -f "lib/common.sh" ]]; then
    echo ">>> Detected curl/standalone mode. Bootstrapping to ${REPO_DIR}..."
    
    # Check root
    if [[ $EUID -ne 0 ]]; then
       echo "Error: This script must be run as root to install dependencies." 
       exit 1
    fi

    # Install git if missing
    if ! command -v git &> /dev/null; then
        if command -v apt-get &> /dev/null; then
            apt-get update -y && apt-get install -y git
        elif command -v yum &> /dev/null; then
            yum install -y git
        fi
    fi

    # Clone or Update
    if [[ -d "${REPO_DIR}/.git" ]]; then
        echo ">>> Updating existing repo..."
        git -C "${REPO_DIR}" pull
    else
        echo ">>> Cloning repository..."
        git clone https://github.com/Hello-Pork-Belly/hz-oneclick.git "${REPO_DIR}"
    fi

    # Handover execution to the local script
    echo ">>> Transferring control to local script..."
    chmod +x "${REPO_DIR}/hz.sh"
    exec "${REPO_DIR}/hz.sh" "$@"
fi

# --- 2. Environment Setup (Standardized) ---
# At this point, we are guaranteed to be in a repo with libraries.
export REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source Core Libraries
if [[ -f "${REPO_ROOT}/lib/common.sh" ]]; then
    source "${REPO_ROOT}/lib/common.sh"
else
    # Fallback if common.sh is missing (should not happen after bootstrap)
    echo "❌ Critical Error: lib/common.sh not found in ${REPO_ROOT}"
    exit 1
fi

# Source Ops Menu Library (Optional Load)
if [[ -f "${REPO_ROOT}/lib/ops_menu_lib.sh" ]]; then
    source "${REPO_ROOT}/lib/ops_menu_lib.sh"
fi

# --- 3. Main Logic ---
show_header
check_root

function main_menu() {
    while true; do
        show_header
        echo -e "${C_CYAN}=== Horizon OneClick Baseline (v2.2.0) ===${C_RESET}"
        echo "1) 🚀 Install LOMP Stack (WordPress) [Standard]"
        echo "2) 🛡️ Ops & Security Center (Backup, Firewall, Mail)"
        echo "3) 🛠️ System Diagnostics & Triage"
        echo "0) 🚪 Exit"
        echo ""
        read -r -p "Enter option [1-3]: " choice

        case "$choice" in
            1)
                # Call the installer module
                bash "${REPO_ROOT}/modules/wp/install-ols-wp-standard.sh"
                ;;
            2)
                # Call the Ops Menu (loaded from lib)
                if declare -f show_ops_menu > /dev/null; then
                    show_ops_menu
                else
                    log_error "Ops Menu library not loaded or corrupted."
                fi
                ;;
            3)
                # Call diagnostics
                bash "${REPO_ROOT}/modules/diagnostics/quick-triage.sh"
                ;;
            0)
                exit 0
                ;;
            *)
                log_error "Invalid option."
                sleep 1
                ;;
        esac
    done
}

# Run Main
main_menu
