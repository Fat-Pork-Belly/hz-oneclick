#!/usr/bin/env bash
set -euo pipefail

show_net_menu() {
  local lang="${1:-en}"

  while true; do
    if [ "$lang" = "cn" ]; then
      echo "=== 网络中心 ==="
      echo "[1] Tailscale 组网"
      echo "[2] CF 隧道"
      echo "[0] 返回"
      echo "[q] 退出"
      read -r -p "> " c
      case "$c" in
        1) echo "敬请期待 (Coming soon)"; read -r -p "按回车继续..." _ ;;
        2) echo "敬请期待 (Coming soon)"; read -r -p "按回车继续..." _ ;;
        0) return 0 ;;
        q|Q) exit 0 ;;
        *) echo "输入无效"; read -r -p "按回车继续..." _ ;;
      esac
    else
      echo "=== Network Center ==="
      echo "[1] Tailscale Mesh Setup"
      echo "[2] Cloudflare Tunnel"
      echo "[0] Back"
      echo "[q] Exit"
      read -r -p "> " c
      case "$c" in
        1) echo "Coming Soon / 敬请期待"; read -r -p "Press Enter to continue..." _ ;;
        2) echo "Coming Soon / 敬请期待"; read -r -p "Press Enter to continue..." _ ;;
        0) return 0 ;;
        q|Q) exit 0 ;;
        *) echo "Invalid choice"; read -r -p "Press Enter to continue..." _ ;;
      esac
    fi
  done
}
