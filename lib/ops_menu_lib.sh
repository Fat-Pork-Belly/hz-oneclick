#!/usr/bin/env bash
# lib/ops_menu_lib.sh
# Shared menu logic for Operations & Security Center
# Version: v2.2.0
# --------------------------------------------------

# If executed directly, tell user to run hz.sh
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "This is a library. Please run: bash ./hz.sh"
  exit 1
fi

# Guard: Require REPO_ROOT
if [[ -z "${REPO_ROOT:-}" ]]; then
  echo "❌ Error: REPO_ROOT is not set. Cannot load Ops Menu."
  return 1
fi

# Ensure common environment is loaded (idempotent is handled by common.sh if present)
if ! command -v log_info >/dev/null 2>&1; then
  if [[ -f "${REPO_ROOT}/lib/common.sh" ]]; then
    source "${REPO_ROOT}/lib/common.sh"
  else
    echo "❌ Error: common.sh not found under REPO_ROOT=${REPO_ROOT}"
    return 1
  fi
fi

# --- Status Helper Functions (non-blocking) ---

get_fail2ban_status_tag() {
  local cfg1="/etc/fail2ban/jail.d/99-hz-oneclick.local"
  local cfg2="/etc/fail2ban/jail.local"
  local has_cfg="false"

  [[ -f "${cfg1}" ]] && has_cfg="true"
  [[ -f "${cfg2}" ]] && has_cfg="true"

  if command -v systemctl >/dev/null 2>&1; then
    if systemctl is-active --quiet fail2ban && [[ "${has_cfg}" == "true" ]]; then
      echo "${C_GREEN}[已启用]${C_RESET}"
      return 0
    fi
  fi

  # If service active but no cfg, show not configured to avoid misleading
  if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet fail2ban; then
    echo "${C_YELLOW}[运行中/未配置]${C_RESET}"
  else
    echo "${C_RED}[未配置]${C_RESET}"
  fi
}

get_postfix_status_tag() {
  if [[ -f /etc/postfix/sasl_passwd ]]; then
    echo "${C_GREEN}[已配置]${C_RESET}"
  else
    echo "${C_YELLOW}[未配置]${C_RESET}"
  fi
}

get_rclone_status_tag() {
  # configured if rclone.conf exists AND there is a scheduled backup
  local cfg="/root/.config/rclone/rclone.conf"
  local scheduled="false"

  if crontab -l 2>/dev/null | grep -q "hz-backup" ; then
    scheduled="true"
  fi
  if [[ -f /etc/cron.d/hz-backup ]]; then
    scheduled="true"
  fi

  if [[ -f "${cfg}" ]] && [[ "${scheduled}" == "true" ]]; then
    echo "${C_GREEN}[已计划]${C_RESET}"
  elif [[ -f "${cfg}" ]]; then
    echo "${C_YELLOW}[已配置/未计划]${C_RESET}"
  else
    echo "${C_YELLOW}[未配置]${C_RESET}"
  fi
}

get_health_status_tag() {
  if crontab -l 2>/dev/null | grep -q "hz-healthcheck" ; then
    echo "${C_GREEN}[已计划]${C_RESET}"
  else
    echo "${C_YELLOW}[未计划]${C_RESET}"
  fi
}

get_rkhunter_status_tag() {
  if [[ -f /etc/default/rkhunter ]] || [[ -f /etc/rkhunter.conf ]]; then
    echo "${C_GREEN}[已配置]${C_RESET}"
  else
    echo "${C_YELLOW}[未配置]${C_RESET}"
  fi
}

# --- Main Ops Menu Function ---
# IMPORTANT: "Back" must be neutral: return 0 and let caller decide where to go.

show_ops_menu() {
  local ops_choice
  while true; do
    clear
    echo -e "${C_CYAN}=== 🛡️ 运维与安全中心 ===${C_RESET}"
    echo -e "1) Fail2Ban 防御部署        $(get_fail2ban_status_tag)"
    echo -e "2) Postfix 邮件告警配置     $(get_postfix_status_tag)"
    echo -e "3) Rclone 备份策略          $(get_rclone_status_tag)"
    echo -e "4) HealthCheck 健康检查     $(get_health_status_tag)"
    echo -e "5) Rkhunter 入侵检测        $(get_rkhunter_status_tag)"
    echo -e "0) 🔙 返回"
    echo ""
    read -r -p "请选择模块 [0-5]: " ops_choice

    case "${ops_choice}" in
      1) bash "${REPO_ROOT}/modules/security/install-fail2ban.sh" ;;
      2) bash "${REPO_ROOT}/modules/mail/setup-postfix-relay.sh" ;;
      3) bash "${REPO_ROOT}/modules/backup/setup-backup-rclone.sh" ;;
      4) bash "${REPO_ROOT}/modules/monitor/setup-healthcheck.sh" ;;
      5) bash "${REPO_ROOT}/modules/security/install-rkhunter.sh" ;;
      0) return 0 ;;
      *) echo "无效选项。" ; sleep 1 ;;
    esac

    echo ""
    read -n 1 -s -r -p "按任意键继续..."
  done
}
