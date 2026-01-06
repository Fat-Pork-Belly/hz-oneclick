#!/usr/bin/env bash
set -euo pipefail

show_web_menu() {
  local lang="${1:-en}"

  while true; do
    if [ "$lang" = "cn" ]; then
      echo "=== 网站服务 ==="
      echo "[1] 安装 LOMP 环境 (Lite/标准版)"
      echo "[2] 站点管理"
      echo "[0] 返回"
      echo "[q] 退出"
      read -r -p "> " c
      case "$c" in
        1) bash ./modules/web/install-ols-wp-standard.sh ;;
        2) echo "站点管理（占位符）"; read -r -p "按回车继续..." _ ;;
        0) return 0 ;;
        q|Q) exit 0 ;;
        *) echo "输入无效"; read -r -p "按回车继续..." _ ;;
      esac
    else
      echo "=== Web Infrastructure ==="
      echo "[1] Install LOMP Stack (Lite/Standard)"
      echo "[2] Site Management"
      echo "[0] Back"
      echo "[q] Exit"
      read -r -p "> " c
      case "$c" in
        1) bash ./modules/web/install-ols-wp-standard.sh ;;
        2) echo "Site Management (placeholder)"; read -r -p "Press Enter to continue..." _ ;;
        0) return 0 ;;
        q|Q) exit 0 ;;
        *) echo "Invalid choice"; read -r -p "Press Enter to continue..." _ ;;
      esac
    fi
  done
}
