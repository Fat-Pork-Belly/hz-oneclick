#!/usr/bin/env bash

get_fail2ban_status_tag() {
  if command -v systemctl >/dev/null 2>&1 \
    && systemctl is-active --quiet fail2ban \
    && { [ -f /etc/fail2ban/jail.d/99-hz-oneclick.local ] || [ -f /etc/fail2ban/jail.local ]; }; then
    echo "[已启用]"
  else
    echo "[未配置]"
  fi
}

get_postfix_status_tag() {
  if [ -f /etc/postfix/sasl_passwd ] || [ -f /etc/postfix/sasl_passwd.db ]; then
    echo "[已配置]"
  else
    echo "[未配置]"
  fi
}

get_backup_status_tag() {
  if [ -f /etc/cron.d/hz-backup ]; then
    echo "[已计划]"
    return
  fi
  if command -v crontab >/dev/null 2>&1; then
    if crontab -l -u root 2>/dev/null | grep -q "hz-backup.sh"; then
      echo "[已计划]"
      return
    fi
  fi
  echo "[未配置]"
}

get_healthcheck_status_tag() {
  if [ -f /etc/cron.d/hz-healthcheck ]; then
    echo "[已计划]"
    return
  fi
  if command -v crontab >/dev/null 2>&1; then
    if crontab -l -u root 2>/dev/null | grep -q "hz-healthcheck.sh"; then
      echo "[已计划]"
      return
    fi
  fi
  echo "[未配置]"
}

get_rkhunter_status_tag() {
  if [ -f /etc/cron.d/rkhunter ] || [ -f /etc/default/rkhunter ]; then
    echo "[已计划]"
  else
    echo "[未配置]"
  fi
}

show_ops_menu() {
  local log_info_fn log_warn_fn

  log_info_fn() {
    if declare -F log_info >/dev/null 2>&1; then
      log_info "$@"
    else
      echo "$@"
    fi
  }

  log_warn_fn() {
    if declare -F log_warn >/dev/null 2>&1; then
      log_warn "$@"
    else
      echo "$@"
    fi
  }

  while true; do
    local repo_root="${REPO_ROOT:-}"
    local fail2ban_tag postfix_tag backup_tag health_tag rkhunter_tag

    fail2ban_tag="$(get_fail2ban_status_tag)"
    postfix_tag="$(get_postfix_status_tag)"
    backup_tag="$(get_backup_status_tag)"
    health_tag="$(get_healthcheck_status_tag)"
    rkhunter_tag="$(get_rkhunter_status_tag)"

    echo ""
    echo "==== 运维与安全中心 ===="
    echo "1) Fail2Ban 防御部署 ${fail2ban_tag}"
    echo "2) Postfix 邮件告警配置 ${postfix_tag}"
    echo "3) Rclone 备份策略 ${backup_tag}"
    echo "4) HealthCheck 健康检查 ${health_tag}"
    if [ -f "${repo_root}/modules/security/install-rkhunter.sh" ]; then
      echo "5) Rkhunter 入侵检测 ${rkhunter_tag}"
    else
      echo "5) Rkhunter 入侵检测 [未提供]"
    fi
    echo "0) 返回"

    read -r -p "请输入选项: " ops_choice

    case "${ops_choice}" in
      1)
        if [ -z "${repo_root}" ]; then
          log_warn_fn "未检测到 REPO_ROOT，无法执行模块。"
          continue
        fi
        if [ -f "${repo_root}/modules/security/install-fail2ban.sh" ]; then
          bash "${repo_root}/modules/security/install-fail2ban.sh"
        else
          log_warn_fn "未找到 Fail2Ban 模块脚本。"
        fi
        ;;
      2)
        if [ -z "${repo_root}" ]; then
          log_warn_fn "未检测到 REPO_ROOT，无法执行模块。"
          continue
        fi
        if [ -f "${repo_root}/modules/mail/setup-postfix-relay.sh" ]; then
          bash "${repo_root}/modules/mail/setup-postfix-relay.sh"
        else
          log_warn_fn "未找到 Postfix 模块脚本。"
        fi
        ;;
      3)
        if [ -z "${repo_root}" ]; then
          log_warn_fn "未检测到 REPO_ROOT，无法执行模块。"
          continue
        fi
        if [ -f "${repo_root}/modules/backup/setup-backup-rclone.sh" ]; then
          bash "${repo_root}/modules/backup/setup-backup-rclone.sh"
        else
          log_warn_fn "未找到 Rclone 备份模块脚本。"
        fi
        ;;
      4)
        if [ -z "${repo_root}" ]; then
          log_warn_fn "未检测到 REPO_ROOT，无法执行模块。"
          continue
        fi
        if [ -f "${repo_root}/modules/monitor/setup-healthcheck.sh" ]; then
          bash "${repo_root}/modules/monitor/setup-healthcheck.sh"
        else
          log_warn_fn "未找到 HealthCheck 模块脚本。"
        fi
        ;;
      5)
        if [ -z "${repo_root}" ]; then
          log_warn_fn "未检测到 REPO_ROOT，无法执行模块。"
          continue
        fi
        if [ -f "${repo_root}/modules/security/install-rkhunter.sh" ]; then
          bash "${repo_root}/modules/security/install-rkhunter.sh"
        else
          log_warn_fn "未找到 Rkhunter 模块脚本。"
        fi
        ;;
      0)
        return 0
        ;;
      *)
        log_warn_fn "无效选项，请重试。"
        ;;
    esac
  done
}
