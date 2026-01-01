#!/usr/bin/env bash
set -euo pipefail

# 颜色输出
cyan()   { printf '\033[36m%s\033[0m\n' "$*"; }
green()  { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
log_info() { printf '[INFO] %s\n' "$*"; }
log_warn() { printf '[WARN] %s\n' "$*" >&2; }

HZ_ONECLICK_VERSION="v2.2.0"
HZ_ONECLICK_BUILD="2026-01-01"
export REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=/dev/null
[ -f "${REPO_ROOT}/lib/common.sh" ] && source "${REPO_ROOT}/lib/common.sh"

# shellcheck source=/dev/null
source "${REPO_ROOT}/lib/ops_menu_lib.sh"

# 全局语言变量：en / zh
HZ_LANG=""
HZ_BASELINE_FORMAT="${HZ_BASELINE_FORMAT:-text}"
HZ_INSTALL_BASE_URL="${HZ_INSTALL_BASE_URL:-https://raw.githubusercontent.com/Hello-Pork-Belly/hz-oneclick/main}"
HZ_INSTALL_BASE_URL="${HZ_INSTALL_BASE_URL%/}"
HZ_WP_INSTALLER_SCRIPT="install-ols"
HZ_WP_INSTALLER_SCRIPT+="-wp-standard.sh"
MACHINE_PROFILE_SHOWN=0

baseline_menu_normalize_format() {
  local format
  format="${1:-text}"
  case "${format,,}" in
    json)
      echo "json"
      ;;
    *)
      echo "text"
      ;;
  esac
}

baseline_menu_normalize_lang() {
  local lang
  lang="${1:-zh}"
  if [[ "${lang,,}" == en* ]]; then
    echo "en"
  else
    echo "zh"
  fi
}

run_wp_baseline_verifier() {
  local site_slug default_doc_root doc_root_input doc_root verifier

  log_info "Verify WordPress baseline"
  read -rp "Site slug (optional, used for default /var/www/<slug>/html): " site_slug
  if [ -n "$site_slug" ]; then
    default_doc_root="/var/www/${site_slug}/html"
  else
    default_doc_root="/var/www/<slug>/html"
  fi
  read -rp "Site DOC_ROOT [${default_doc_root}]: " doc_root_input
  doc_root="${doc_root_input:-$default_doc_root}"

  if [ -z "$doc_root" ]; then
    log_warn "DOC_ROOT is required."
    return 1
  fi

  verifier="tools/wp-baseline-verify.sh"
  if [ ! -f "$verifier" ]; then
    log_warn "WP baseline verifier not found: ${verifier}"
    return 1
  fi

  DOC_ROOT="$doc_root" bash "$verifier"
  log_info "Also check WP Admin → Tools → Site Health."
}

detect_machine_profile() {
  local arch vcpu mem_kb mem_mb mem_gb swap_kb swap_mb disk_total_raw disk_avail_raw

  arch="$(uname -m 2>/dev/null || true)"
  if [ -z "$arch" ]; then
    arch="N/A"
  fi

  if command -v nproc >/dev/null 2>&1; then
    vcpu="$(nproc 2>/dev/null || true)"
  fi
  if ! echo "$vcpu" | grep -Eq '^[0-9]+$'; then
    vcpu="$(lscpu 2>/dev/null | awk -F: '/^CPU\(s\)/{gsub(/ /,"",$2); print $2}' | head -n1)"
  fi
  if ! echo "$vcpu" | grep -Eq '^[0-9]+$'; then
    vcpu="N/A"
  fi

  mem_kb="$(awk '/MemTotal/ {print $2}' /proc/meminfo 2>/dev/null || true)"
  if echo "$mem_kb" | grep -Eq '^[0-9]+$'; then
    mem_mb=$((mem_kb / 1024))
    mem_gb="$(awk -v kb="$mem_kb" 'BEGIN {printf "%.1f", kb/1024/1024}')"
  else
    mem_mb="N/A"
    mem_gb="N/A"
  fi

  swap_kb="$(awk '/SwapTotal/ {print $2}' /proc/meminfo 2>/dev/null || true)"
  if echo "$swap_kb" | grep -Eq '^[0-9]+$'; then
    swap_mb=$((swap_kb / 1024))
  else
    swap_mb="N/A"
  fi

  if command -v df >/dev/null 2>&1; then
    read -r disk_total_raw disk_avail_raw <<EOF
$(df -B1 / 2>/dev/null | awk 'NR==2 {print $2, $4}')
EOF
  fi

  if echo "$disk_total_raw" | grep -Eq '^[0-9]+$'; then
    MACHINE_DISK_TOTAL="$(awk -v b="$disk_total_raw" 'BEGIN {printf "%.1f GB", b/1024/1024/1024}')"
  else
    MACHINE_DISK_TOTAL="N/A"
  fi

  if echo "$disk_avail_raw" | grep -Eq '^[0-9]+$'; then
    MACHINE_DISK_AVAILABLE="$(awk -v b="$disk_avail_raw" 'BEGIN {printf "%.1f GB", b/1024/1024/1024}')"
  else
    MACHINE_DISK_AVAILABLE="N/A"
  fi

  MACHINE_ARCH="$arch"
  MACHINE_VCPU="$vcpu"
  MACHINE_MEM_MB="$mem_mb"
  MACHINE_MEM_GB="$mem_gb"
  MACHINE_SWAP_MB="$swap_mb"
}

recommend_machine_tier() {
  local mem_mb tier_label

  mem_mb="$MACHINE_MEM_MB"
  if ! echo "$mem_mb" | grep -Eq '^[0-9]+$'; then
    tier_label="N/A"
  elif [ "$mem_mb" -lt 4000 ]; then
    tier_label="Lite（Frontend-only）"
  elif [ "$mem_mb" -lt 16000 ]; then
    tier_label="Standard"
  else
    tier_label="Hub"
  fi

  MACHINE_RECOMMENDED_TIER="$tier_label"
}

# Canonical machine profile + recommendation emitter (print once per run).
print_machine_profile_and_recommendation() {
  local mem_display swap_display disk_display

  detect_machine_profile
  recommend_machine_tier

  if [ "$MACHINE_MEM_GB" = "N/A" ]; then
    mem_display="N/A"
  else
    mem_display="${MACHINE_MEM_MB} MB (${MACHINE_MEM_GB} GB)"
  fi

  if [ "$MACHINE_SWAP_MB" = "N/A" ]; then
    swap_display="N/A"
  else
    swap_display="${MACHINE_SWAP_MB} MB"
  fi

  disk_display="total ${MACHINE_DISK_TOTAL} / free ${MACHINE_DISK_AVAILABLE}"

  echo
  cyan "Baseline: Machine profile"
  if [ "$HZ_LANG" = "en" ]; then
    echo "Arch: ${MACHINE_ARCH}"
    echo "vCPU: ${MACHINE_VCPU}"
    echo "Total RAM: ${mem_display}"
    echo "Swap: ${swap_display}"
    echo "Disk: ${disk_display}"
  else
    echo "架构 Arch: ${MACHINE_ARCH}"
    echo "vCPU 核心: ${MACHINE_VCPU}"
    echo "内存总量: ${mem_display}"
    echo "Swap: ${swap_display}"
    echo "磁盘: ${disk_display}"
  fi

  cyan "Recommendation"
  if [ "$HZ_LANG" = "en" ]; then
    echo "Best tier: ${MACHINE_RECOMMENDED_TIER}"
  else
    echo "推荐档位: ${MACHINE_RECOMMENDED_TIER}"
  fi
  echo
}

show_machine_profile_once() {
  if [ "${MACHINE_PROFILE_SHOWN}" -eq 1 ]; then
    return
  fi

  print_machine_profile_and_recommendation
  MACHINE_PROFILE_SHOWN=1
}

parse_global_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --format)
        HZ_BASELINE_FORMAT="$(baseline_menu_normalize_format "${2:-$HZ_BASELINE_FORMAT}")"
        shift 2
        ;;
      --format=*)
        HZ_BASELINE_FORMAT="$(baseline_menu_normalize_format "${1#--format=}")"
        shift
        ;;
      --help|-h)
        echo "Usage: $0 [--format text|json]"
        exit 0
        ;;
      *)
        break
        ;;
    esac
  done
}

baseline_diagnostics_menu() {
  local diag_domain diag_lang choice lang_input diag_format format_input

  diag_lang="$(baseline_menu_normalize_lang "$HZ_LANG")"
  diag_format="$(baseline_menu_normalize_format "$HZ_BASELINE_FORMAT")"
  while true; do
    clear

    if [ "$diag_lang" = "en" ]; then
      echo "== Baseline Diagnostics =="
      echo "Enter a domain to diagnose (optional, press Enter to skip):"
    else
      echo "== 基础诊断（Baseline Diagnostics）=="
      echo "请输入要诊断的域名（可留空跳过域名相关检查）："
    fi
    read -r diag_domain

    if [ "$diag_lang" = "en" ]; then
      echo "Select language for diagnostics [en/zh] (default: $diag_lang):"
    else
      echo "选择诊断语言 [en/zh]（默认：$diag_lang）："
    fi
    read -r lang_input
    diag_lang="$(baseline_menu_normalize_lang "${lang_input:-$diag_lang}")"

    if [ "$diag_lang" = "en" ]; then
      echo "Select output format [text/json] (default: $diag_format):"
    else
      echo "选择输出格式 [text/json]（默认：$diag_format）："
    fi
    read -r format_input
    diag_format="$(baseline_menu_normalize_format "${format_input:-$diag_format}")"

    while true; do
      clear
      if [ "$diag_lang" = "en" ]; then
        cyan "Baseline Diagnostics"
        echo "Domain: ${diag_domain:-<none>}"
        echo "Language: ${diag_lang}"
        echo "Format: ${diag_format}"
        echo "  1) Run Quick Triage (521/HTTPS/TLS first)"
        echo "  2) Run DNS/IP baseline group"
        echo "  3) Run Origin/Firewall baseline group"
        echo "  4) Run Proxy/CDN baseline group"
        echo "  5) Run TLS/HTTPS baseline group"
        echo "  6) Run LSWS/OLS baseline group"
        echo "  7) Run WP/App baseline group"
        echo "  8) Run Cache/Redis/OPcache baseline group"
        echo "  9) Run System/Resource baseline group"
        echo "  d) Update domain/language"
        echo "  0) Back"
        read -rp "Please enter a choice: " choice
      else
        cyan "基础诊断（Baseline Diagnostics）"
        echo "域名：${diag_domain:-<无>}"
        echo "语言：${diag_lang}"
        echo "输出格式：${diag_format}"
        echo "  1) Quick Triage（优先排查 521/HTTPS/TLS）"
        echo "  2) DNS/IP 基线检查"
        echo "  3) 源站/防火墙 基线检查"
        echo "  4) 代理/CDN 基线检查"
        echo "  5) TLS/HTTPS 基线检查"
        echo "  6) LSWS/OLS 基线检查"
        echo "  7) WP/App 基线检查"
        echo "  8) 缓存/Redis/OPcache 基线检查"
        echo "  9) 系统/资源 基线检查"
        echo "  d) 更新域名/语言"
        echo "  0) 返回"
        read -rp "请输入选项: " choice
      fi

      case "$choice" in
        1)
          echo "Running Baseline Quick Triage (read-only checks)..."
          HZ_TRIAGE_USE_LOCAL=1 HZ_TRIAGE_LOCAL_ROOT="$(pwd)" HZ_TRIAGE_LANG="$diag_lang" HZ_TRIAGE_DOMAIN="$diag_domain" HZ_TRIAGE_FORMAT="$diag_format" bash ./modules/diagnostics/quick-triage.sh --format "$diag_format"
          read -rp "Done. Press Enter to return..." _
          ;;
        2)
          HZ_BASELINE_LANG="$diag_lang" HZ_BASELINE_DOMAIN="$diag_domain" HZ_BASELINE_FORMAT="$diag_format" bash ./modules/diagnostics/baseline-dns-ip.sh "$diag_domain" "$diag_lang" --format "$diag_format"
          read -rp "Done. Press Enter to return..." _
          ;;
        3)
          HZ_BASELINE_LANG="$diag_lang" HZ_BASELINE_DOMAIN="$diag_domain" HZ_BASELINE_FORMAT="$diag_format" bash ./modules/diagnostics/baseline-origin-firewall.sh "$diag_domain" "$diag_lang" --format "$diag_format"
          read -rp "Done. Press Enter to return..." _
          ;;
        4)
          HZ_BASELINE_LANG="$diag_lang" HZ_BASELINE_DOMAIN="$diag_domain" HZ_BASELINE_FORMAT="$diag_format" bash ./modules/diagnostics/baseline-proxy-cdn.sh "$diag_domain" "$diag_lang" --format "$diag_format"
          read -rp "Done. Press Enter to return..." _
          ;;
        5)
          HZ_BASELINE_LANG="$diag_lang" HZ_BASELINE_DOMAIN="$diag_domain" HZ_BASELINE_FORMAT="$diag_format" bash ./modules/diagnostics/baseline-tls-https.sh "$diag_domain" "$diag_lang" --format "$diag_format"
          read -rp "Done. Press Enter to return..." _
          ;;
        6)
          HZ_BASELINE_LANG="$diag_lang" HZ_BASELINE_DOMAIN="$diag_domain" HZ_BASELINE_FORMAT="$diag_format" bash ./modules/diagnostics/baseline-lsws-ols.sh "$diag_domain" "$diag_lang" --format "$diag_format"
          read -rp "Done. Press Enter to return..." _
          ;;
        7)
          HZ_BASELINE_LANG="$diag_lang" HZ_BASELINE_DOMAIN="$diag_domain" HZ_BASELINE_FORMAT="$diag_format" bash ./modules/diagnostics/baseline-wp-app.sh "$diag_domain" "$diag_lang" --format "$diag_format"
          read -rp "Done. Press Enter to return..." _
          ;;
        8)
          HZ_BASELINE_LANG="$diag_lang" HZ_BASELINE_DOMAIN="$diag_domain" HZ_BASELINE_FORMAT="$diag_format" bash ./modules/diagnostics/baseline-cache.sh "$diag_domain" "$diag_lang" --format "$diag_format"
          read -rp "Done. Press Enter to return..." _
          ;;
        9)
          HZ_BASELINE_LANG="$diag_lang" HZ_BASELINE_DOMAIN="$diag_domain" HZ_BASELINE_FORMAT="$diag_format" bash ./modules/diagnostics/baseline-system.sh "$diag_domain" "$diag_lang" --format "$diag_format"
          read -rp "Done. Press Enter to return..." _
          ;;
        d|D)
          break
          ;;
        0)
          return
          ;;
        *)
          echo "Invalid choice, please try again."
          read -rp "Press Enter to continue..." _
          ;;
      esac
    done
  done
}

show_lomp_lnmp_profile_menu() {
  local choice

  while true; do
    clear
    show_machine_profile_once

    if [ "$HZ_LANG" = "en" ]; then
      cyan "LOMP/LNMP Profile Selector"
      echo "Select a profile (DB / Redis configuration):"
      echo "  1) LOMP-Lite (Frontend-only)"
      echo "  2) LOMP-Standard"
      echo "  3) LOMP-Hub"
      echo "  4) LNMP-Lite (Frontend-only)"
      echo "  5) LNMP-Standard"
      echo "  6) LNMP-Hub"
      echo "  0) Back"
      echo
      read -rp "Please enter a choice: " choice
    else
      cyan "LOMP/LNMP 档位选择"
      echo "请选择档位（DB / Redis 配置）："
      echo "  1) LOMP-Lite（Frontend-only）"
      echo "  2) LOMP-Standard"
      echo "  3) LOMP-Hub"
      echo "  4) LNMP-Lite（Frontend-only）"
      echo "  5) LNMP-Standard"
      echo "  6) LNMP-Hub"
      echo "  0) 返回"
      echo
      read -rp "请输入选项: " choice
    fi

    case "$choice" in
      1)
        if [ "$HZ_LANG" = "en" ]; then
          echo "Launching LOMP-Lite (Frontend-only)..."
        else
          echo "即将启动 LOMP-Lite（Frontend-only）..."
        fi
        HZ_ENTRY="menu" HZ_LANG="$HZ_LANG" HZ_WP_PROFILE="lomp-lite" HZ_INSTALL_BASE_URL="$HZ_INSTALL_BASE_URL" \
          HZ_SUPPRESS_MACHINE_PROFILE=1 \
          bash <(curl -fsSL "$HZ_INSTALL_BASE_URL/modules/wp/${HZ_WP_INSTALLER_SCRIPT}")
        return
        ;;
      2)
        if [ "$HZ_LANG" = "en" ]; then
          echo "Launching LOMP-Standard..."
        else
          echo "即将启动 LOMP-Standard..."
        fi
        HZ_ENTRY="menu" HZ_LANG="$HZ_LANG" HZ_WP_PROFILE="lomp-standard" HZ_INSTALL_BASE_URL="$HZ_INSTALL_BASE_URL" \
          HZ_SUPPRESS_MACHINE_PROFILE=1 \
          bash <(curl -fsSL "$HZ_INSTALL_BASE_URL/modules/wp/${HZ_WP_INSTALLER_SCRIPT}")
        return
        ;;
      3)
        if [ "$HZ_LANG" = "en" ]; then
          echo "LOMP-Hub is coming soon."
          read -rp "Press Enter to return to menu..." _
        else
          echo "LOMP-Hub 暂未开放（敬请期待）。"
          read -rp "按回车返回菜单..." _
        fi
        return
        ;;
      4)
        if [ "$HZ_LANG" = "en" ]; then
          echo "LNMP-Lite is coming soon."
          read -rp "Press Enter to return to menu..." _
        else
          echo "LNMP-Lite 暂未开放（敬请期待）。"
          read -rp "按回车返回菜单..." _
        fi
        return
        ;;
      5)
        if [ "$HZ_LANG" = "en" ]; then
          echo "LNMP-Standard is coming soon."
          read -rp "Press Enter to return to menu..." _
        else
          echo "LNMP-Standard 暂未开放（敬请期待）。"
          read -rp "按回车返回菜单..." _
        fi
        return
        ;;
      6)
        if [ "$HZ_LANG" = "en" ]; then
          echo "LNMP-Hub is coming soon."
          read -rp "Press Enter to return to menu..." _
        else
          echo "LNMP-Hub 暂未开放（敬请期待）。"
          read -rp "按回车返回菜单..." _
        fi
        return
        ;;
      0)
        return
        ;;
      *)
        if [ "$HZ_LANG" = "en" ]; then
          echo "Invalid choice, please try again."
          read -rp "Press Enter to continue..." _
        else
          echo "无效选项，请重新输入。"
          read -rp "按回车继续..." _
        fi
        ;;
    esac
  done
}

choose_lang() {
  while true; do
    clear
    cyan "hz-oneclick - HorizonTech Installer"
    echo
    echo "Please select language / 请选择语言："
    echo "  1) English"
    echo "  2) 简体中文"
    echo "  e) Exit / 退出"
    echo

    read -rp "Enter a choice and press Enter / 请输入选项并按回车: " lang_choice

    case "$lang_choice" in
      1)
        HZ_LANG="en"
        break
        ;;
      2)
        HZ_LANG="zh"
        break
        ;;
      e|E|0)
        echo "Bye~ / 再见～"
        exit 0
        ;;
      *)
        echo "Invalid choice / 无效选项，请重新输入..."
        read -rp "Press Enter to continue / 按回车继续..." _
        ;;
    esac
  done
}

main_menu() {
  while true; do
    clear

    if [ "$HZ_LANG" = "en" ]; then
      # ===== English menu =====
      cyan  "hz-oneclick - HorizonTech Installer (preview)"
      cyan  "Version: ${HZ_ONECLICK_VERSION} (${HZ_ONECLICK_BUILD})"
      green "Source: ${HZ_INSTALL_BASE_URL}"
      echo
      cyan  "Menu options"
      cyan  "  1) Immich on Cloud (VPS)"
      green "  2) 🛡️ Ops & Security Center"
      cyan  "  3) rclone basics (OneDrive etc.)"
      green "  4) Plex Media Server"
      cyan  "  5) Transmission (BT download)"
      green "  6) Tailscale access"
      cyan  "  7) Edge Tunnel / Reverse Proxy"
      green "  8) msmtp + Brevo (SMTP alert)"
      cyan  "  9) WP backup (DB + files)"
      green " 10) wp-cron helper (system cron for WordPress)"
      cyan  " 11) Verify WP baseline"
      green " 12) rkhunter (rootkit / trojan scanner)"
      cyan  " 13) rkhunter (daily check / optional mail alert)"
      green " 14) Baseline Diagnostics"
      cyan  " 15) LOMP/LNMP (DB / Redis provisioning)"
      yellow "  0) Exit"
      green "  r) Return to language selection / 返回语言选择 "
      echo
      read -rp "Please enter a choice and press Enter: " choice

      case "$choice" in
        1)
          echo "Immich installer is not ready yet (coming soon)..."
          read -rp "Press Enter to return to menu..." _
          ;;
        2)
          show_ops_menu
          ;;
        3)
          echo "Running rclone basics installer..."
          bash <(curl -fsSL "$HZ_INSTALL_BASE_URL/rclone/install.sh")
          read -rp "Done. Press Enter to return to menu..." _
          ;;
        4)
          echo "Plex installer is not ready yet (coming soon)..."
          read -rp "Press Enter to return to menu..." _
          ;;
        5)
          echo "Transmission installer is not ready yet (coming soon)..."
          read -rp "Press Enter to return to menu..." _
          ;;
        6)
          echo "Tailscale helper scripts are not ready yet (coming soon)..."
          read -rp "Press Enter to return to menu..." _
          ;;
        7)
          echo "Edge tunnel / reverse proxy helper scripts are not ready yet (coming soon)..."
          read -rp "Press Enter to return to menu..." _
          ;;
        8)
          echo "Running msmtp + Brevo alert setup..."
          bash <(curl -fsSL "$HZ_INSTALL_BASE_URL/modules/mail/setup-msmtp-brevo.sh")
          read -rp "Done. Press Enter to return to menu..." _
          ;;
        9)
          echo "Running WordPress backup (DB + files) setup..."
          bash <(curl -fsSL "$HZ_INSTALL_BASE_URL/modules/wp/setup-wp-backup-basic-en.sh")
          read -rp "Done. Press Enter to return to menu..." _
          ;;
        10)
          echo "Running wp-cron helper (system cron for WordPress)..."
          bash <(curl -fsSL "$HZ_INSTALL_BASE_URL/modules/wp/gen-wp-cron-en.sh")
          ;;
        11)
          run_wp_baseline_verifier
          read -rp "Done. Press Enter to return to menu..." _
          ;;
        12)
          echo "Installing rkhunter (rootkit / trojan scanner) ..."
          bash <(curl -fsSL "$HZ_INSTALL_BASE_URL/modules/security/install-rkhunter-en.sh")
          ;;
        13)
          echo "rkhunter (setting / optional mail alert)) ..."
          bash <(curl -fsSL "$HZ_INSTALL_BASE_URL/modules/security/setup-rkhunter-cron-en.sh")
          ;;
        14)
          baseline_diagnostics_menu
          ;;
        15)
          show_lomp_lnmp_profile_menu
          ;;
        0)
          echo "Bye~"
          exit 0
          ;;
        r|R)
          # 回到语言选择
          choose_lang
          ;;
        *)
          echo "Invalid choice, please try again."
          read -rp "Press Enter to continue..." _
          ;;
      esac

    else
      # ===== 中文菜单 =====
      cyan  "hz-oneclick - HorizonTech 一键安装入口（预览版）"
      cyan  "版本: ${HZ_ONECLICK_VERSION} (${HZ_ONECLICK_BUILD})"
      green "来源: ${HZ_INSTALL_BASE_URL}"
      echo
      cyan  "菜单选项 / Menu options"
      cyan  "  1) Immich 上云（VPS）"
      green "  2) 🛡️ 运维与安全中心 (Ops & Security Center)"
      cyan  "  3) rclone 基础安装（OneDrive 等）"
      green "  4) Plex 媒体服务器"
      cyan  "  5) Transmission BT 下载"
      green "  6) Tailscale 接入"
      cyan  "  7) 反向代理/隧道穿透"
      green "  8) 邮件报警（msmtp + Brevo）"
      cyan  "  9) WordPress 备份（数据库 + 文件）"
      green "  10) wp-cron 定时任务向导"
      cyan  "  11) 验证 WordPress 基线"
      green "  12) rkhunter（系统后门 / 木马检测）"
      cyan  "  13) rkhunter 定时扫描(报错邮件通知 /日志维护）"
      green "  14) 基础诊断（Baseline Diagnostics）"
      cyan  "  15) LOMP/LNMP（DB / Redis 配置）"
      yellow "  0) 退出"
      yellow "  r) 返回语言选择 / Return to language selection"
      echo
      read -rp "请输入选项并按回车: " choice

      case "$choice" in
        1)
          echo "Immich 安装脚本暂未开放（敬请期待）..."
          read -rp "按回车返回菜单..." _
          ;;
        2)
          show_ops_menu
          ;;
        3)
          echo "即将安装 rclone 基础模块..."
          bash <(curl -fsSL "$HZ_INSTALL_BASE_URL/rclone/install.sh")
          read -rp "完成。按回车返回菜单..." _
          ;;
        4)
          echo "Plex 安装脚本暂未开放（敬请期待）..."
          read -rp "按回车返回菜单..." _
          ;;
        5)
          echo "Transmission 安装脚本暂未开放（敬请期待）..."
          read -rp "按回车返回菜单..." _
          ;;
        6)
          echo "Tailscale 辅助脚本暂未开放（敬请期待）..."
          read -rp "按回车返回菜单..." _
          ;;
        7)
          echo "反向代理/隧道辅助脚本暂未开放（敬请期待）..."
          read -rp "按回车返回菜单..." _
          ;;
        8)
          echo "即将安装 msmtp + Brevo 邮件报警模块..."
          bash <(curl -fsSL "$HZ_INSTALL_BASE_URL/modules/mail/setup-msmtp-brevo.sh")
          read -rp "完成。按回车返回菜单..." _
          ;;
        9)
          echo "即将安装 WordPress 备份模块（数据库 + 文件）..."
          bash <(curl -fsSL "$HZ_INSTALL_BASE_URL/modules/wp/setup-wp-backup-basic.sh")
          read -rp "完成。按回车返回菜单..." _
          ;;
        10)
          echo "将运行 wp-cron 定时任务向导..."
          bash <(curl -fsSL "$HZ_INSTALL_BASE_URL/modules/wp/gen-wp-cron.sh")
          ;;
        11)
          run_wp_baseline_verifier
          read -rp "完成。按回车返回菜单..." _
          ;;
        12)
          echo "将安装 / 初始化 rkhunter（系统后门 / 木马检测）..."
          bash <(curl -fsSL "$HZ_INSTALL_BASE_URL/modules/security/install-rkhunter.sh")
          ;;
        13)
          echo "将设置 rkhunter 定时扫描（报错邮件通知 /日志维护）..."
          bash <(curl -fsSL "$HZ_INSTALL_BASE_URL/modules/security/setup-rkhunter-cron.sh")
          ;;
        14)
          baseline_diagnostics_menu
          ;;
        15)
          show_lomp_lnmp_profile_menu
          ;;
        0)
          echo "再见～"
          exit 0
          ;;
        r|R)
          # 回到语言选择
          choose_lang
          ;;
        *)
          echo "无效选项，请重新输入。"
          read -rp "按回车继续..." _
          ;;
      esac
    fi
  done
}

# 程序入口
parse_global_args "$@"
choose_lang
main_menu
