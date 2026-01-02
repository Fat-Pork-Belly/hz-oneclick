#!/usr/bin/env bash
set -euo pipefail

ORIGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${ORIGIN_DIR}"

bootstrap_repo() {
  local target_dir="/opt/hz-oneclick"

  if ! command -v git >/dev/null 2>&1; then
    if ! command -v apt-get >/dev/null 2>&1; then
      echo "[FATAL] 缺少 git 且无法使用 apt-get 安装，请手动安装 git。"
      exit 1
    fi
    apt-get update -y
    apt-get install -y git ca-certificates
  fi

  if [ -d "${target_dir}/.git" ]; then
    git -C "${target_dir}" pull --ff-only
  else
    git clone https://github.com/Hello-Pork-Belly/hz-oneclick.git "${target_dir}"
  fi

  exec "${target_dir}/hz.sh" "$@"
}

if [ ! -f "${REPO_ROOT}/lib/common.sh" ] || [ ! -d "${REPO_ROOT}/.git" ]; then
  bootstrap_repo "$@"
fi

export REPO_ROOT

source "${REPO_ROOT}/lib/common.sh"
source "${REPO_ROOT}/lib/ops_menu_lib.sh"

if ! declare -F log_info >/dev/null 2>&1; then
  log_info() { echo "$@"; }
fi
if ! declare -F log_warn >/dev/null 2>&1; then
  log_warn() { echo "$@"; }
fi

while true; do
  echo ""
  echo "==== hz-oneclick 主菜单 ===="
  echo "1) LOMP / WordPress 安装"
  echo "2) 🛡️ 运维与安全中心"
  echo "0) 退出"
  read -r -p "请输入选项: " main_choice

  case "${main_choice}" in
    1)
      bash "${REPO_ROOT}/modules/wp/install-ols-wp-standard.sh"
      ;;
    2)
      show_ops_menu
      ;;
    0)
      log_info "已退出。"
      exit 0
      ;;
    *)
      log_warn "无效选项，请重试。"
      ;;
  esac
 done
