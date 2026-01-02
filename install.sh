#!/usr/bin/env bash
# Horizon OneClick - Fresh Installer
# ----------------------------------
set -Eeo pipefail

# Define Root
export REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Basic Helpers
echo_green() { echo -e "\033[0;32m$1\033[0m"; }
echo_red()   { echo -e "\033[0;31m$1\033[0m"; }

# Main Menu
clear
echo "========================================"
echo "   Horizon OneClick (Recovery Mode)"
echo "========================================"
echo "1) Install LOMP Stack (Standard)"
echo "2) System Diagnostics"
echo "0) Exit"
echo ""
read -r -p "Select: " choice

case "$choice" in
    1)
        SCRIPT="${REPO_ROOT}/modules/wp/install-ols-wp-standard.sh"
        if [[ -f "$SCRIPT" ]]; then
            # Ensure it is executable
            chmod +x "$SCRIPT"
            bash "$SCRIPT"
        else
            echo_red "Error: Installer module not found!"
        fi
        ;;
    2)
        SCRIPT="${REPO_ROOT}/modules/diagnostics/quick-triage.sh"
        [[ -f "$SCRIPT" ]] && bash "$SCRIPT"
        ;;
    0)
        exit 0
        ;;
    *)
        echo "Invalid option"
        ;;
esac
