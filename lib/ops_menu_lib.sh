#!/usr/bin/env bash
# hz-oneclick ops menu library
# Version: v2.2.0
# Build: 2026-01-01

if [ -z "${REPO_ROOT:-}" ]; then
  echo "❌ Error: REPO_ROOT is not set."
  return 1
fi

ops_require_common() {
  if ! command -v log_info >/dev/null 2>&1; then
    if [ -f "${REPO_ROOT}/lib/common.sh" ]; then
      # shellcheck source=lib/common.sh
      source "${REPO_ROOT}/lib/common.sh"
    fi
  fi
}

status_fail2ban() {
  if ! command -v systemctl >/dev/null 2>&1; then
    echo "未配置/不可用"
    return 0
  fi

  if systemctl is-active --quiet fail2ban \
    && { [ -f /etc/fail2ban/jail.local ] || [ -f /etc/fail2ban/jail.d/99-hz-oneclick.local ]; }; then
    echo "已启用"
  else
    echo "未配置/不可用"
  fi
}

status_postfix() {
  if command -v systemctl >/dev/null 2>&1; then
    if systemctl is-active --quiet postfix; then
      echo "已启用"
    else
      echo "未配置/不可用"
    fi
    return 0
  fi

  if command -v service >/dev/null 2>&1; then
    if service postfix status >/dev/null 2>&1; then
      echo "已启用"
    else
      echo "未配置/不可用"
    fi
    return 0
  fi

  echo "未配置/不可用"
}

status_rclone() {
  if ! command -v rclone >/dev/null 2>&1; then
    echo "未配置/不可用"
    return 0
  fi

  if ! command -v crontab >/dev/null 2>&1; then
    echo "未配置/不可用"
    return 0
  fi

  if crontab -l 2>/dev/null | grep -qi "rclone"; then
    echo "已配置"
  else
    echo "未配置/不可用"
  fi
}

status_healthcheck() {
  if ! command -v crontab >/dev/null 2>&1; then
    echo "未配置/不可用"
    return 0
  fi

  if crontab -l 2>/dev/null | grep -qi "healthcheck"; then
    echo "已配置"
  else
    echo "未配置/不可用"
  fi
}

status_rkhunter() {
  if ! command -v rkhunter >/dev/null 2>&1; then
    echo "未配置/不可用"
    return 0
  fi

  if [ -f /etc/cron.daily/rkhunter ]; then
    echo "已配置"
    return 0
  fi

  if command -v crontab >/dev/null 2>&1 && crontab -l 2>/dev/null | grep -qi "rkhunter"; then
    echo "已配置"
  else
    echo "未配置/不可用"
  fi
}

pause_continue() {
  read -r -p "按回车继续..." _unused
}

run_module() {
  local module_path="$1"
  if [ -f "${module_path}" ]; then
    bash "${module_path}"
  else
    echo "模块缺失: ${module_path}"
  fi
}

show_ops_menu() {
  ops_require_common

  while true; do
    echo ""
    echo "=============================="
    echo " 运维与安全中心"
    echo "=============================="
    echo "1) Fail2Ban          [$(status_fail2ban)]"
    echo "2) Postfix           [$(status_postfix)]"
    echo "3) Rclone Backup     [$(status_rclone)]"
    echo "4) HealthCheck       [$(status_healthcheck)]"
    echo "5) Rkhunter          [$(status_rkhunter)]"
    echo "0) Back"
    echo ""
    read -r -p "请选择操作: " choice

    case "${choice:-}" in
      1)
        run_module "${REPO_ROOT}/modules/fail2ban.sh"
        pause_continue
        ;;
      2)
        run_module "${REPO_ROOT}/modules/postfix.sh"
        pause_continue
        ;;
      3)
        run_module "${REPO_ROOT}/modules/rclone_backup.sh"
        pause_continue
        ;;
      4)
        run_module "${REPO_ROOT}/modules/healthcheck.sh"
        pause_continue
        ;;
      5)
        run_module "${REPO_ROOT}/modules/rkhunter.sh"
        pause_continue
        ;;
      0)
        return 0
        ;;
      *)
        echo "无效选项，请重试。"
        ;;
    esac
  done
}
