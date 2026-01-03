#!/usr/bin/env bash
# Ops Menu Library - v2.2.0
if [ -z "${REPO_ROOT:-}" ]; then return 1; fi

show_ops_menu() {
    local op_choice
    while true; do
        clear
        echo "=== Ops & Security Center ==="
        echo "1) Install Fail2Ban"
        echo "2) Configure Postfix Relay"
        echo "3) Rclone Backup"
        echo "4) Healthcheck Monitor"
        echo "5) Rkhunter"
        echo "0) Back"
        echo ""
        read -r -p "Select: " op_choice
        case "$op_choice" in
            1) bash "${REPO_ROOT}/modules/security/install-fail2ban.sh" ;;
            2) bash "${REPO_ROOT}/modules/mail/setup-postfix-relay.sh" ;;
            3) bash "${REPO_ROOT}/modules/backup/setup-backup-rclone.sh" ;;
            4) bash "${REPO_ROOT}/modules/monitor/setup-healthcheck.sh" ;;
            5) bash "${REPO_ROOT}/modules/security/install-rkhunter.sh" ;;
            0) return 0 ;;
            *) echo "Invalid." ; sleep 1 ;;
        esac
    done
}
