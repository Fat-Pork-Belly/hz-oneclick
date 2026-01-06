#!/usr/bin/env bash
set -euo pipefail

VERSION_FILE="$(pwd)/VERSION"

VERSION="v3.0.0-alpha"
if [ -f "$VERSION_FILE" ]; then
  VERSION="$(cat "$VERSION_FILE" 2>/dev/null || echo "v3.0.0-alpha")"
fi

REPO_URL="https://github.com/Hello-Pork-Belly/hz-oneclick.git"
WEB_URL="https://horizontech.page"
AUTHOR="Pork Belly"

# ---- colors ----
C_RESET="\033[0m"
C_RED="\033[31m"
C_GREEN="\033[32m"
C_YELLOW="\033[33m"
C_CYAN="\033[36m"
C_DIM="\033[2m"

print_c() { printf "%b\n" "$*"; }

show_logo() {
  print_c "${C_CYAN}"
  cat <<'ART'
 _   _                 _                        __     _____ _ _      _
| | | |               (_)                      /  |   /  __ \ (_)    | |
| |_| | ___  _ __ ___  _ _______  _ __ ______  `| |   | /  \/ |_  ___| | __
|  _  |/ _ \| '__/ _ \| |_  / _ \| '_ \______|  | |   | |   | | |/ __| |/ /
| | | | (_) | | | (_) | |/ / (_) | | | |      _| |_  | \__/\ | | (__|   <
\_| |_/\___/|_|  \___/|_/___\___/|_| |_|      \___/   \____/_|_|\___|_|\_\

ART
  print_c "${C_RESET}"
  print_c "${C_DIM}Version:${C_RESET} ${VERSION}"
  print_c "${C_DIM}Website:${C_RESET} ${WEB_URL}"
  print_c "${C_DIM}GitHub:${C_RESET}  ${REPO_URL}"
  print_c "${C_DIM}Powered by:${C_RESET} Pork Belly"
  echo
}

detect_virt() {
  local v="unknown"
  if command -v systemd-detect-virt >/dev/null 2>&1; then
    v="$(systemd-detect-virt 2>/dev/null || echo unknown)"
  fi
  echo "$v"
}

get_ram_mb() {
  awk '/MemTotal:/ {printf "%.0f\n", $2/1024}' /proc/meminfo 2>/dev/null || echo 0
}

check_sys_env() {
  local os kernel virt ram_mb
  os="$(. /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-unknown}")"
  kernel="$(uname -r 2>/dev/null || echo unknown)"
  virt="$(detect_virt)"
  ram_mb="$(get_ram_mb)"

  print_c "${C_DIM}OS:${C_RESET}     ${os}"
  print_c "${C_DIM}Kernel:${C_RESET} ${kernel}"
  print_c "${C_DIM}Virt:${C_RESET}   ${virt}"
  print_c "${C_DIM}RAM:${C_RESET}    ${ram_mb} MB"
  echo

  case "$virt" in
    lxc|openvz)
      print_c "${C_RED}FAIL:${C_RESET} Unsupported virtualization (${virt}). Docker is required."
      exit 1
      ;;
  esac

  if [ "$ram_mb" -lt 1024 ]; then
    print_c "${C_YELLOW}WARN:${C_RESET} Low memory (< 1GB). Some presets may not be supported."
  else
    print_c "${C_GREEN}PASS:${C_RESET} System environment check passed."
  fi
  echo
}

pause_en() { read -r -p "Press Enter to continue..." _; }
pause_cn() { read -r -p "按回车继续..." _; }

run_module_menu() {
  local category="${1:-}"
  local lang="${2:-en}"

  if [ -z "$category" ]; then
    echo "ERROR: missing category"
    return 1
  fi

  local menu_file="./modules/${category}/menu.sh"
  if [ ! -f "$menu_file" ]; then
    echo "ERROR: missing module menu: $menu_file"
    return 1
  fi

  # shellcheck source=/dev/null
  source "$menu_file"

  case "$category" in
    web)
      show_web_menu "$lang"
      ;;
    ops)
      show_ops_menu "$lang"
      ;;
    media|ops|net|check)
      if [ "$lang" = "cn" ]; then
        echo "模块占位符：${category}"
        pause_cn
      else
        echo "Module placeholder: ${category}"
        pause_en
      fi
      ;;
    *)
      echo "ERROR: unsupported category: $category"
      return 1
      ;;
  esac
}

root_menu() {
  while true; do
    show_logo
    echo "Select Language / 选择语言"
    echo "[1] English"
    echo "[2] Chinese"
    echo "[0] Exit"
    read -r -p "> " c
    case "$c" in
      1) show_main_menu_en ;;
      2) show_main_menu_cn ;;
      0) exit 0 ;;
      *) echo "Invalid choice"; pause_en ;;
    esac
  done
}

show_main_menu_en() {
  while true; do
    echo "=== Main Menu (English) ==="
    echo "[1] Web"
    echo "[2] Media"
    echo "[3] Ops"
    echo "[4] Net"
    echo "[5] Check"
    echo "[0] Back"
    echo "[q] Exit"
    read -r -p "> " c
    case "$c" in
      1) run_module_menu web en ;;
      2) run_module_menu media en ;;
      3) run_module_menu ops en ;;
      4) run_module_menu net en ;;
      5) run_module_menu check en ;;
      0) return 0 ;;
      q|Q) exit 0 ;;
      *) echo "Invalid choice"; pause_en ;;
    esac
  done
}

show_main_menu_cn() {
  while true; do
    echo "=== 主菜单（中文）==="
    echo "[1] Web"
    echo "[2] Media"
    echo "[3] Ops"
    echo "[4] Net"
    echo "[5] Check"
    echo "[0] 返回"
    echo "[q] 退出"
    read -r -p "> " c
    case "$c" in
      1) run_module_menu web cn ;;
      2) run_module_menu media cn ;;
      3) run_module_menu ops cn ;;
      4) run_module_menu net cn ;;
      5) run_module_menu check cn ;;
      0) return 0 ;;
      q|Q) exit 0 ;;
      *) echo "输入无效"; pause_cn ;;
    esac
  done
}

main() {
  show_logo
  check_sys_env
  root_menu
}

main "$@"
