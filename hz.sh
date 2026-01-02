#!/usr/bin/env bash
# hz-oneclick bootstrap loader & main menu
# Version: v2.2.0
# Build: 2026-01-01

set -euo pipefail

is_repo_mode() {
  if [ -d ".git" ] || [ -f "lib/common.sh" ]; then
    return 0
  fi
  return 1
}

ensure_root() {
  if [ "${EUID:-}" -ne 0 ]; then
    echo "❌ This script must be run as root in standalone mode."
    exit 1
  fi
}

ensure_git() {
  if command -v git >/dev/null 2>&1; then
    return 0
  fi

  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y
    apt-get install -y git
    return 0
  fi

  if command -v yum >/dev/null 2>&1; then
    yum install -y git
    return 0
  fi

  echo "❌ git is required but could not be installed."
  exit 1
}

bootstrap_standalone() {
  ensure_root
  ensure_git

  local target_dir="/opt/hz-oneclick"
  if [ -d "${target_dir}/.git" ]; then
    git -C "${target_dir}" pull --ff-only
  else
    git clone https://github.com/Hello-Pork-Belly/hz-oneclick.git "${target_dir}"
  fi

  chmod +x "${target_dir}/hz.sh"
  exec "${target_dir}/hz.sh" "$@"
}

main_menu() {
  while true; do
    echo ""
    echo "=============================="
    echo " Hz One-Click Main Menu"
    echo "=============================="
    echo "1) 安装WP标准"
    echo "2) 运维与安全中心"
    echo "3) 诊断"
    echo "0) 退出"
    echo ""
    read -r -p "请选择操作: " choice

    case "${choice:-}" in
      1)
        echo "即将执行安装WP标准..."
        if [ -f "${REPO_ROOT}/modules/wp_standard.sh" ]; then
          bash "${REPO_ROOT}/modules/wp_standard.sh"
        else
          echo "模块缺失: ${REPO_ROOT}/modules/wp_standard.sh"
        fi
        ;;
      2)
        show_ops_menu
        ;;
      3)
        echo "即将执行诊断..."
        if [ -f "${REPO_ROOT}/modules/diagnostic.sh" ]; then
          bash "${REPO_ROOT}/modules/diagnostic.sh"
        else
          echo "模块缺失: ${REPO_ROOT}/modules/diagnostic.sh"
        fi
        ;;
      0)
        echo "Bye."
        exit 0
        ;;
      *)
        echo "无效选项，请重试。"
        ;;
    esac
  done
}

if ! is_repo_mode; then
  bootstrap_standalone "$@"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export REPO_ROOT

# shellcheck source=lib/common.sh
source "${REPO_ROOT}/lib/common.sh"
# shellcheck source=lib/ops_menu_lib.sh
source "${REPO_ROOT}/lib/ops_menu_lib.sh"

main_menu
