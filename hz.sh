#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Horizon OneClick - Main Entry (Bootstrap Mode)
# Version: v2.2.0
# -----------------------------------------------------------------------------
set -Eeo pipefail

# --- Bootstrap: Auto-Clone if running via Curl ---
REPO_DIR="/opt/hz-oneclick"
if [[ ! -d ".git" ]] && [[ ! -f "lib/common.sh" ]]; then
    echo ">>> Detected curl/standalone mode. Bootstrapping to ${REPO_DIR}..."
    if [[ $EUID -ne 0 ]]; then echo "Error: Run as root."; exit 1; fi

    # Install git (best-effort)
    if ! command -v git >/dev/null 2>&1; then
        if command -v apt-get >/dev/null 2>&1; then
            apt-get update -y && apt-get install -y git
        elif command -v yum >/dev/null 2>&1; then
            yum install -y git
        else
            echo "Error: No supported package manager found to install git."
            exit 1
        fi
    fi

    # Clone/Pull
    if [[ -d "${REPO_DIR}/.git" ]]; then
        git -C "${REPO_DIR}" pull
    else
        git clone https://github.com/Hello-Pork-Belly/hz-oneclick.git "${REPO_DIR}"
    fi

    # Execute local script
    chmod +x "${REPO_DIR}/hz.sh"
    exec "${REPO_DIR}/hz.sh" "$@"
fi

# --- Environment ---
export REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=/dev/null
source "${REPO_ROOT}/lib/common.sh"
if [[ -f "${REPO_ROOT}/lib/ops_menu_lib.sh" ]]; then
    # shellcheck source=/dev/null
    source "${REPO_ROOT}/lib/ops_menu_lib.sh"
fi

# --- Main Menu ---
show_header
check_root

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
        1) bash "${REPO_ROOT}/modules/wp/install-ols-wp-standard.sh" ;;
        2) show_ops_menu ;;
        3) bash "${REPO_ROOT}/modules/diagnostics/quick-triage.sh" ;;
        0) exit 0 ;;
        *) log_error "Invalid option." ; sleep 1 ;;
    esac
done
