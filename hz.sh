#!/usr/bin/env bash
# Horizon OneClick - Bootstrap Entry
# Version: v2.2.0 (Build: 2026-01-01)
set -Eeo pipefail

INSTALL_DIR="/opt/hz-oneclick"
REPO_URL="https://github.com/Hello-Pork-Belly/hz-oneclick.git"

# --- Phase 1: Bootstrap (Curl/Standalone Mode) ---
if [[ ! -d ".git" ]] && [[ ! -f "lib/common.sh" ]]; then
    echo ">>> [Bootstrap] Running in standalone mode. Setting up environment..."

    if [[ ${EUID:-9999} -ne 0 ]]; then
        echo "Error: Must run as root."
        exit 1
    fi

    # Ensure Git
    if ! command -v git >/dev/null 2>&1; then
        echo ">>> Installing Git..."
        if command -v apt-get >/dev/null 2>&1; then
            apt-get update -y
            apt-get install -y git
        elif command -v yum >/dev/null 2>&1; then
            yum install -y git
        else
            echo "Error: No supported package manager found (apt-get/yum)."
            exit 1
        fi
    fi

    # Clone/Update
    if [[ -d "${INSTALL_DIR}/.git" ]]; then
        echo ">>> Updating existing repository at ${INSTALL_DIR}..."
        git -C "${INSTALL_DIR}" pull --ff-only
    else
        echo ">>> Cloning repository to ${INSTALL_DIR}..."
        rm -rf "${INSTALL_DIR}"
        git clone "${REPO_URL}" "${INSTALL_DIR}"
    fi

    # Handover
    echo ">>> Transferring control to local installer..."
    chmod +x "${INSTALL_DIR}/hz.sh"
    exec "${INSTALL_DIR}/hz.sh" "$@"
fi

# --- Phase 2: Execution (Repo Mode) ---
export REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${REPO_ROOT}/lib/common.sh"

# Load Ops Menu if available
if [[ -f "${REPO_ROOT}/lib/ops_menu_lib.sh" ]]; then
    # shellcheck source=/dev/null
    source "${REPO_ROOT}/lib/ops_menu_lib.sh"
fi

show_header
check_root

while true; do
    show_header
    echo -e "${C_CYAN}=== Horizon OneClick v2.2.0 ===${C_RESET}"
    echo "1) Install LOMP Stack (Standard)"
    echo "2) Ops & Security Center"
    echo "3) System Diagnostics"
    echo "0) Exit"
    echo ""
    read -r -p "Select: " choice

    case "${choice}" in
        1) bash "${REPO_ROOT}/modules/wp/install-ols-wp-standard.sh" ;;
        2)
            if declare -F show_ops_menu >/dev/null 2>&1; then
                show_ops_menu
            else
                log_warn "Ops menu not available."
                sleep 1
            fi
            ;;
        3) bash "${REPO_ROOT}/modules/diagnostics/quick-triage.sh" ;;
        0) exit 0 ;;
        *) echo "Invalid option" ; sleep 1 ;;
    esac
done
