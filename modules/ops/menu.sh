#!/usr/bin/env bash
set -euo pipefail

_run_script_or_warn() {
  local script="$1"
  if [ -f "$script" ]; then
    bash "$script"
  else
    echo "Script not found: $script"
  fi
}

show_ops_menu() {
  local lang="${1:-en}"

  while true; do
    if [ "$lang" = "cn" ]; then
      echo "=== 运维中心 ==="
      echo "[1] 安全: 防爆破(Fail2Ban)"
      echo "[2] 备份: 云备份(Rclone)"
      echo "[3] 监控: 系统体检"
      echo "[4] 邮件: 发送服务"
      echo "[0] 返回"
      echo "[q] 退出"
      read -r -p "> " c
      case "$c" in
        1) _run_script_or_warn ./modules/security/install-fail2ban.sh ;;
        2) _run_script_or_warn ./modules/backup/setup-backup-rclone.sh ;;
        3) _run_script_or_warn ./modules/monitor/setup-healthcheck.sh ;;
        4) _run_script_or_warn ./modules/mail/setup-postfix-relay.sh ;;
        0) return 0 ;;
        q|Q) exit 0 ;;
        *) echo "输入无效"; read -r -p "按回车继续..." _ ;;
      esac
    else
      echo "=== Ops & Security Center ==="
      echo "[1] Security: Fail2Ban"
      echo "[2] Backup: Rclone Setup"
      echo "[3] Monitor: System Health"
      echo "[4] Mail: Postfix Relay"
      echo "[0] Back"
      echo "[q] Exit"
      read -r -p "> " c
      case "$c" in
        1) _run_script_or_warn ./modules/security/install-fail2ban.sh ;;
        2) _run_script_or_warn ./modules/backup/setup-backup-rclone.sh ;;
        3) _run_script_or_warn ./modules/monitor/setup-healthcheck.sh ;;
        4) _run_script_or_warn ./modules/mail/setup-postfix-relay.sh ;;
        0) return 0 ;;
        q|Q) exit 0 ;;
        *) echo "Invalid choice"; read -r -p "Press Enter to continue..." _ ;;
      esac
    fi
  done
}
