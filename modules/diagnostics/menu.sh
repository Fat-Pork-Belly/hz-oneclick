#!/usr/bin/env bash
set -euo pipefail

_show_missing() {
  local p="$1"
  echo "Script not found: $p"
}

show_check_menu() {
  local lang="${1:-en}"

  while true; do
    if [ "$lang" = "cn" ]; then
      echo "=== 系统检查 / 诊断 ==="
      echo "[1] 快速系统分诊"
      echo "[2] 全量基线扫描"
      echo "[0] 返回"
      echo "[q] 退出"
      read -r -p "> " c
      case "$c" in
        1)
          if [ -f ./modules/diagnostics/quick-triage.sh ]; then
            bash ./modules/diagnostics/quick-triage.sh
          else
            _show_missing "./modules/diagnostics/quick-triage.sh"
          fi
          ;;
        2) echo "敬请期待 (Coming soon)"; read -r -p "按回车继续..." _ ;;
        0) return 0 ;;
        q|Q) exit 0 ;;
        *) echo "输入无效"; read -r -p "按回车继续..." _ ;;
      esac
    else
      echo "=== Diagnostics / Check ==="
      echo "[1] Quick System Triage"
      echo "[2] Full Baseline Check"
      echo "[0] Back"
      echo "[q] Exit"
      read -r -p "> " c
      case "$c" in
        1)
          if [ -f ./modules/diagnostics/quick-triage.sh ]; then
            bash ./modules/diagnostics/quick-triage.sh
          else
            _show_missing "./modules/diagnostics/quick-triage.sh"
          fi
          ;;
        2) echo "Coming soon"; read -r -p "Press Enter to continue..." _ ;;
        0) return 0 ;;
        q|Q) exit 0 ;;
        *) echo "Invalid choice"; read -r -p "Press Enter to continue..." _ ;;
      esac
    fi
  done
}
