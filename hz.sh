#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Horizon OneClick - Main Entry Point (Bootstrap Wrapper)
# Version: v2.2.0
# -----------------------------------------------------------------------------
set -Eeo pipefail

# --- 0) Resolve where THIS script lives (do not rely on current working dir) ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- 1) Bootstrap Logic: Ensure we are running inside a full Git Repo ---
# If running via curl/standalone mode (no .git dir or lib/common.sh missing next to script), clone/pull to /opt.
REPO_DIR="/opt/hz-oneclick"

is_repo_ready() {
  [[ -d "${SCRIPT_DIR}/.git" ]] && [[ -f "${SCRIPT_DIR}/lib/common.sh" ]]
}

if ! is_repo_ready; then
  echo ">>> Detected standalone/curl mode. Bootstrapping to ${REPO_DIR}..."

  if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root to bootstrap."
    exit 1
  fi

  # Install git if missing
  if ! command -v git >/dev/null 2>&1; then
    if command -v apt-get >/dev/null 2>&1; then
      apt-get update -y && apt-get install -y git
    elif command -v yum >/dev/null 2>&1; then
      yum install -y git
    else
      echo "Error: no supported package manager found to install git."
      exit 1
    fi
  fi

  # Clone or update
  if [[ -d "${REPO_DIR}/.git" ]]; then
    echo ">>> Updating existing repo..."
    git -C "${REPO_DIR}" pull --ff-only || git -C "${REPO_DIR}" pull
  else
    echo ">>> Cloning repository..."
    git clone https://github.com/Hello-Pork-Belly/hz-oneclick.git "${REPO_DIR}"
  fi

  # Handover execution to the local script (IMPORTANT: cd into repo to avoid bootstrap loop)
  echo ">>> Transferring control to local script..."
  chmod +x "${REPO_DIR}/hz.sh"
  cd "${REPO_DIR}"
  exec "${REPO_DIR}/hz.sh" "$@"
fi

# --- 2) Environment Setup (Standardized) ---
export REPO_ROOT="${SCRIPT_DIR}"

# Source core library (required)
if [[ -f "${REPO_ROOT}/lib/common.sh" ]]; then
  source "${REPO_ROOT}/lib/common.sh"
else
  echo "❌ Critical Error: lib/common.sh not found in ${REPO_ROOT}"
  exit 1
fi

# Source Ops menu library (optional but expected)
if [[ -f "${REPO_ROOT}/lib/ops_menu_lib.sh" ]]; then
  source "${REPO_ROOT}/lib/ops_menu_lib.sh"
fi

show_header
check_root

main_menu() {
  while true; do
    show_header
    echo -e "${C_CYAN}=== Horizon OneClick Baseline (v2.2.0) ===${C_RESET}"
    echo "1) 🚀 安装 LOMP (WordPress) [Standard]"
    echo "2) 🛡️ 运维与安全中心 (Ops & Security Center)"
    echo "3) 🛠️ 系统诊断与排障 (Triage)"
    echo "0) 🚪 退出"
    echo ""
    read -r -p "请输入选项 [0-3]: " choice

    case "${choice}" in
      1)
        bash "${REPO_ROOT}/modules/wp/install-ols-wp-standard.sh"
        ;;
      2)
        if command -v show_ops_menu >/dev/null 2>&1; then
          show_ops_menu
        else
          log_error "Ops menu not available (lib/ops_menu_lib.sh not loaded)."
          sleep 1
        fi
        ;;
      3)
        if [[ -f "${REPO_ROOT}/modules/diagnostics/quick-triage.sh" ]]; then
          bash "${REPO_ROOT}/modules/diagnostics/quick-triage.sh"
        else
          log_warn "Diagnostics module not found: modules/diagnostics/quick-triage.sh"
          sleep 1
        fi
        ;;
      0)
        exit 0
        ;;
      *)
        log_error "无效选项。"
        sleep 1
        ;;
    esac
  done
}

main_menu
