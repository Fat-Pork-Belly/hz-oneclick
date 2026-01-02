#!/bin/bash
# Horizon OneClick - Lite Entry
# -----------------------------
export REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Function to run the installer
run_installer() {
    local script="${REPO_ROOT}/modules/wp/install-ols-wp-standard.sh"
    if [[ -f "$script" ]]; then
        bash "$script"
    else
        echo "Error: Installer script not found at $script"
        exit 1
    fi
}

# Main Menu
clear
echo "========================================"
echo "   Horizon OneClick (Lite Recovery)"
echo "========================================"
echo "1) Install LOMP Stack (WordPress)"
echo "2) System Diagnostics"
echo "0) Exit"
echo ""
read -r -p "Select option: " choice

case "$choice" in
    1) run_installer ;;
    2) bash "${REPO_ROOT}/modules/diagnostics/quick-triage.sh" ;;
    0) exit 0 ;;
    *) echo "Invalid option" ;;
esac
