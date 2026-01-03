#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Ops & Security Center - Shared Menu Library (Passive)
# Baseline: v2.2.0 (Build: 2026-01-01)
# -----------------------------------------------------------------------------
set -Eeuo pipefail

# Guard: library must be sourced by a caller that sets REPO_ROOT
if [[ -z "${REPO_ROOT:-}" ]]; then
  echo "❌ Error: REPO_ROOT is not set. Run via hz.sh (repo mode) or installer entry."
  return 1 2>/dev/null || exit 1
fi

# Ensure common env is available for colors/log helpers (best-effort)
if [[ -z "${C_GREEN:-}" ]] && [[ -f "${REPO_ROOT}/lib/common.sh" ]]; then
  # shellcheck source=/dev/null
  source "${REPO_ROOT}/lib/common.sh"
fi

get_fail2ban_status_tag() {
  if systemctl is-active --quiet fail2ban && [[ -f /etc/fail2ban/jail.local ]]; then
    echo "${C_GREEN}[Enabled]${C_RESET}"
  else
    echo "${C_RED}[Not Configured]${C_RESET}"
  fi
}

get_postfix_status_tag() {
  if [[ -f /etc/postfix/sasl_passwd ]]; then
    echo "${C_GREEN}[Enabled]${C_RESET}"
  else
    echo "${C_YELLOW}[Optional]${C_RESET}"
  fi
}

get_rclone_status_tag() {
  if [[ -f /root/.config/rclone/rclone.conf ]]; then
    echo "${C_GREEN}[Configured]${C_RESET}"
  else
    echo "${C_YELLOW}[Not Configured]${C_RESET}"
  fi
}

get_health_status_tag() {
  if crontab -l 2>/dev/null | grep -q "hz-healthcheck"; then
    echo "${C_GREEN}[Active]${C_RESET}"
  else
    echo "${C_YELLOW}[Inactive]${C_RESET}"
  fi
}

get_rkhunter_status_tag() {
  if [[ -f /etc/default/rkhunter ]]; then
    echo "${C_GREEN}[Active]${C_RESET}"
  else
    echo "${C_YELLOW}[Optional]${C_RESET}"
  fi
}

show_ops_menu() {
  local ops_choice
  while true; do
    clear
    echo -e "${C_CYAN}=== 🛡️ Ops & Security Center (v2.2.0) ===${C_RESET}"
    echo -e "1) Fail2Ban Protection    $(get_fail2ban_status_tag)"
    echo -e "2) Postfix Mail Relay     $(get_postfix_status_tag)"
    echo -e "3) Rclone Backup Strategy $(get_rclone_status_tag)"
    echo -e "4) HealthCheck Monitor    $(get_health_status_tag)"
    echo -e "5) Rkhunter Intrusion     $(get_rkhunter_status_tag)"
    echo -e "0) 🔙 Back"
    echo ""
    read -r -p "Select module: " ops_choice

    case "${ops_choice}" in
      1) bash "${REPO_ROOT}/modules/security/install-fail2ban.sh" ;;
      2) bash "${REPO_ROOT}/modules/mail/setup-postfix-relay.sh" ;;
      3) bash "${REPO_ROOT}/modules/backup/setup-backup-rclone.sh" ;;
      4) bash "${REPO_ROOT}/modules/monitor/setup-healthcheck.sh" ;;
      5) bash "${REPO_ROOT}/modules/security/install-rkhunter.sh" ;;
      0) return 0 ;;
      *) echo "Invalid option." ; sleep 1 ;;
    esac

    echo ""
    read -n 1 -s -r -p "Press any key to continue..."
  done
}
