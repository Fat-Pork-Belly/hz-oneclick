#!/usr/bin/env bash
#
# hz-oneclick - gen-wp-cron-en.sh
# Version: 0.1.0
# Purpose: Detect and configure how WordPress cron (wp-cron.php) is executed
#          (built-in pseudo-cron vs systemd timer).
# Notes:
#   - Only touches wp-config.php and systemd unit files.
#   - Does NOT modify the database or site files.
#   - Handles three states:
#       A) Default pseudo-cron (no DISABLE_WP_CRON, no systemd timer)
#       B) Not recommended (DISABLE_WP_CRON = true, but no systemd timer)
#       C) Systemd has already taken over (DISABLE_WP_CRON = true + timer exists)
#

SCRIPT_VERSION="0.1.0"

# Try to load common helpers from hz-oneclick (colors, logging, etc.)
COMMON_SH="$(dirname "$0")/../lib/common.sh"
if [[ -f "$COMMON_SH" ]]; then
  # shellcheck disable=SC1090
  . "$COMMON_SH"
else
  # Fallback: minimal helper functions
  info()  { echo -e "[INFO]  $*"; }
  warn()  { echo -e "[WARN]  $*"; }
  error() { echo -e "[ERROR] $*" >&2; }
  step()  { echo -e "\n==== $* ====\n"; }
fi

# Globals
WP_ROOT=""          # e.g. /var/www/example/html
WP_CONFIG=""        # wp-config.php
SITE_SLUG=""        # e.g. example
STATE=""            # A / B / C
PHP_CMD=""          # Full command to run wp-cron.php
INTERVAL_MIN=5      # Timer interval in minutes
TARGET_MODE=""      # keep_default / enable_systemd / restore_wp_cron / keep_systemd / adjust_systemd

# Generic hints
prompt_exit_hint() {
  echo "Hint: type 0 at any prompt to cancel and return to the main menu."
}

require_systemctl() {
  if ! command -v systemctl >/dev/null 2>&1; then
    error "systemctl not found. This script requires systemd."
    exit 1
  fi
}

press_enter_to_continue() {
  read -r -p "Press Enter to continue..." _
}

# -------- Step 2 helpers: choose WP root path --------

auto_discover_wp_sites() {
  # Try to find wp-config.php inside /var/www/*/html
  find /var/www -maxdepth 3 -type f -name "wp-config.php" 2>/dev/null \
    | grep "/html/wp-config.php$" \
    | sort
}

select_wp_root_step() {
  step "Step 2/7 - Select the WordPress site to configure"
  prompt_exit_hint
  echo

  local candidates=()
  local idx=1

  while IFS= read -r line; do
    candidates+=("$line")
  done < <(auto_discover_wp_sites)

  if ((${#candidates[@]} > 0)); then
    echo "Detected possible WordPress installations:"
    for f in "${candidates[@]}"; do
      local dir
      dir="$(dirname "$f")"
      echo "  [$idx] $dir"
      ((idx++))
    done
    echo "  [$idx] Enter path manually"
  else
    warn "No wp-config.php found under /var/www. Maybe you are using a custom path."
    echo "  [1] Enter path manually"
  fi

  echo
  echo "Example path: /var/www/example/html"
  while true; do
    read -r -p "Enter a number, or type a full path (0 = main menu): " input
    if [[ "$input" == "0" ]]; then
      info "Exiting wizard and returning to main menu."
      exit 0
    fi

    # If numeric and there are candidates, treat as index
    if [[ "$input" =~ ^[0-9]+$ ]] && ((${#candidates[@]} > 0)); then
      local num="$input"
      if ((num >= 1 && num <= ${#candidates[@]})); then
        WP_ROOT="$(dirname "${candidates[num-1]}")"
        break
      elif ((num == ${#candidates[@]} + 1)); then
        read -r -p "Enter full WordPress root path (e.g. /var/www/example/html): " WP_ROOT
        [[ -z "$WP_ROOT" ]] && continue
        break
      else
        warn "Invalid selection, please try again."
        continue
      fi
    else
      # Treat as path
      if [[ -z "$input" ]]; then
        warn "Input is empty, please try again."
        continue
      fi
      WP_ROOT="$input"
      break
    fi
  done

  WP_CONFIG="$WP_ROOT/wp-config.php"
  if [[ ! -f "$WP_CONFIG" ]]; then
    error "wp-config.php not found in $WP_ROOT. Please check the path."
    press_enter_to_continue
    select_wp_root_step
    return
  fi

  # Derive SITE_SLUG from parent directory name:
  # /var/www/example/html => example
  SITE_SLUG="$(basename "$(dirname "$WP_ROOT")")"

  info "Selected site:"
  echo "  Root: $WP_ROOT"
  echo "  Config: $WP_CONFIG"
  echo "  Site slug: $SITE_SLUG"
}

# -------- Step 3: detect current state --------

detect_state_step() {
  step "Step 3/7 - Detect current wp-cron status"

  local has_disable="no"
  local disable_true="no"

  if grep -q "DISABLE_WP_CRON" "$WP_CONFIG"; then
    has_disable="yes"
    if grep -E "DISABLE_WP_CRON'.*true" "$WP_CONFIG" >/dev/null 2>&1; then
      disable_true="yes"
    else
      disable_true="no"
    fi
  fi

  local timer_name="wp-cron-${SITE_SLUG}.timer"
  local timer_exists="no"
  local timer_active="no"

  if systemctl list-timers --all 2>/dev/null | grep -q "$timer_name"; then
    timer_exists="yes"
    if systemctl is-active "$timer_name" >/dev/null 2>&1; then
      timer_active="yes"
    fi
  fi

  # Decide state A / B / C
  # A: no DISABLE_WP_CRON + no timer
  # B: DISABLE_WP_CRON = true + no timer
  # C: DISABLE_WP_CRON = true + timer exists
  if [[ "$has_disable" == "no" ]]; then
    if [[ "$timer_exists" == "no" ]]; then
      STATE="A"
    else
      STATE="A"  # rare case: timer exists but pseudo-cron also enabled
    fi
  else
    if [[ "$disable_true" == "yes" && "$timer_exists" == "no" ]]; then
      STATE="B"
    elif [[ "$disable_true" == "yes" && "$timer_exists" == "yes" ]]; then
      STATE="C"
    else
      STATE="A"  # unusual combination, treat as A
    fi
  fi

  case "$STATE" in
    A)
      info "Detected: State A - WordPress default pseudo-cron."
      echo "  - DISABLE_WP_CRON is NOT defined in wp-config.php"
      echo "  - No systemd timer named $timer_name found"
      echo "Note: On low-traffic sites, some scheduled tasks may run late or not at all."
      ;;
    B)
      warn "Detected: State B - NOT recommended!"
      echo "  - DISABLE_WP_CRON = true in wp-config.php"
      echo "  - No systemd timer named $timer_name found"
      echo "This means WordPress cron is disabled, but nothing is taking over."
      ;;
    C)
      info "Detected: State C - systemd has taken over wp-cron."
      echo "  - DISABLE_WP_CRON = true in wp-config.php"
      echo "  - Systemd timer found: $timer_name (active: $timer_active)"
      ;;
    *)
      warn "Unknown state. Treating as State A."
      STATE="A"
      ;;
  esac

  press_enter_to_continue
}

# -------- Step 4: choose target mode --------

choose_target_mode_step() {
  step "Step 4/7 - Choose target scheduling mode"
  prompt_exit_hint
  echo

  case "$STATE" in
    A)
      echo "Current mode: WordPress default pseudo-cron."
      echo "You can keep it as-is, or switch to a systemd-based cron runner."
      echo
      echo "1) Keep current pseudo-cron behavior (no changes)"
      echo "2) Enable systemd-based wp-cron (recommended for production)"
      echo "0) Exit wizard (back to main menu)"
      while true; do
        read -r -p "Choose [1-2, 0]: " ans
        case "$ans" in
          1) TARGET_MODE="keep_default";    return ;;
          2) TARGET_MODE="enable_systemd";  return ;;
          0)
            info "Exiting wizard and returning to main menu."
            exit 0
            ;;
          *) warn "Invalid choice, please try again." ;;
        esac
      done
      ;;
    B)
      echo "Current mode: NOT recommended."
      echo "  - WordPress cron is disabled (DISABLE_WP_CRON = true)"
      echo "  - No systemd timer has taken over."
      echo
      echo "1) Create systemd wp-cron timer (recommended)"
      echo "2) Remove DISABLE_WP_CRON and go back to default pseudo-cron"
      echo "0) Exit wizard (back to main menu)"
      while true; do
        read -r -p "Choose [1-2, 0]: " ans
        case "$ans" in
          1) TARGET_MODE="enable_systemd";   return ;;
          2) TARGET_MODE="restore_wp_cron";  return ;;
          0)
            info "Exiting wizard and returning to main menu."
            exit 0
            ;;
          *) warn "Invalid choice, please try again." ;;
        esac
      done
      ;;
    C)
      echo "Current mode: systemd-based wp-cron is already active."
      echo
      echo "1) Keep current configuration (no changes)"
      echo "2) Adjust systemd timer interval"
      echo "0) Exit wizard (back to main menu)"
      while true; do
        read -r -p "Choose [1-2, 0]: " ans
        case "$ans" in
          1) TARGET_MODE="keep_systemd";     return ;;
          2) TARGET_MODE="adjust_systemd";   return ;;
          0)
            info "Exiting wizard and returning to main menu."
            exit 0
            ;;
          *) warn "Invalid choice, please try again." ;;
        esac
      done
      ;;
  esac
}

# -------- Step 5: detect/confirm PHP command --------

auto_detect_php_cmd() {
  local php_bin=""
  if [[ -x /usr/local/lsws/lsphp83/bin/php ]]; then
    php_bin="/usr/local/lsws/lsphp83/bin/php"
  elif command -v php >/dev/null 2>&1; then
    php_bin="$(command -v php)"
  fi

  if [[ -n "$php_bin" ]]; then
    PHP_CMD="$php_bin -q \"$WP_ROOT/wp-cron.php\""
  else
    PHP_CMD=""
  fi
}

confirm_php_cmd_step() {
  step "Step 5/7 - Confirm PHP command to run wp-cron.php"
  prompt_exit_hint
  echo

  auto_detect_php_cmd

  if [[ -n "$PHP_CMD" ]]; then
    echo "Detected a possible command:"
    echo "  $PHP_CMD"
  else
    warn "Could not auto-detect a PHP command. You will need to type it manually."
  fi

  echo
  echo "Example:"
  echo "  /usr/local/lsws/lsphp83/bin/php -q /var/www/example/html/wp-cron.php"

  while true; do
    if [[ -n "$PHP_CMD" ]]; then
      read -r -p "Use the detected command? (Y/n, 0 = main menu): " ans
      case "$ans" in
        0)
          info "Exiting wizard and returning to main menu."
          exit 0
          ;;
        ""|Y|y)
          break
          ;;
        N|n)
          PHP_CMD=""
          ;;
        *)
          warn "Please answer Y / n / 0."
          continue
          ;;
      esac
    fi

    if [[ -z "$PHP_CMD" ]]; then
      read -r -p "Enter full command (0 = main menu): " cmd
      if [[ "$cmd" == "0" ]]; then
        info "Exiting wizard and returning to main menu."
        exit 0
      fi
      if [[ -z "$cmd" ]]; then
        warn "Command cannot be empty."
        continue
      fi
      PHP_CMD="$cmd"
    fi

    local php_bin
    php_bin="$(echo "$PHP_CMD" | awk '{print $1}')"
    if ! command -v "$php_bin" >/dev/null 2>&1 && [[ ! -x "$php_bin" ]]; then
      warn "PHP binary in your command does not exist or is not executable: $php_bin"
      PHP_CMD=""
      continue
    fi

    break
  done

  info "Final command to be used:"
  echo "  $PHP_CMD"
  press_enter_to_continue
}

# -------- Step 6: set interval and apply systemd units --------

config_interval_and_apply_step() {
  step "Step 6/7 - Configure timer interval and create systemd units"
  prompt_exit_hint
  echo

  echo "Recommended: run wp-cron.php every 5 minutes."
  echo
  echo "1) Every 5 minutes (recommended)"
  echo "2) Every 10 minutes"
  echo "3) Every 15 minutes"
  echo "4) Custom interval (in minutes)"
  echo "0) Exit wizard (back to main menu)"

  while true; do
    read -r -p "Choose [1-4, 0]: " ans
    case "$ans" in
      0)
        info "Exiting wizard and returning to main menu."
        exit 0
        ;;
      1) INTERVAL_MIN=5;  break ;;
      2) INTERVAL_MIN=10; break ;;
      3) INTERVAL_MIN=15; break ;;
      4)
        read -r -p "Enter interval in minutes (integer > 0, 0 = main menu): " num
        if [[ "$num" == "0" ]]; then
          info "Exiting wizard and returning to main menu."
          exit 0
        fi
        if ! [[ "$num" =~ ^[0-9]+$ ]] || ((num <= 0)); then
          warn "Please enter a positive integer."
          continue
        fi
        INTERVAL_MIN="$num"
        break
        ;;
      *)
        warn "Invalid choice, please try again."
        ;;
    esac
  done

  echo
  echo "The following changes will be applied:"
  echo "  - Set or keep DISABLE_WP_CRON = true in wp-config.php"
  echo "  - Create/update systemd service: wp-cron-${SITE_SLUG}.service"
  echo "  - Create/update systemd timer:  wp-cron-${SITE_SLUG}.timer"
  echo "  - Timer interval: every ${INTERVAL_MIN} minutes"
  echo
  read -r -p "Proceed with these changes? (Y/n): " confirm
  case "$confirm" in
    ""|Y|y) ;;
    *)
      warn "User cancelled. Wizard will exit."
      exit 0
      ;;
  esac

  # 1) Ensure DISABLE_WP_CRON = true
  if grep -q "DISABLE_WP_CRON" "$WP_CONFIG"; then
    sed -i -E "s/define\(\s*'DISABLE_WP_CRON'.*/define( 'DISABLE_WP_CRON', true );/" "$WP_CONFIG"
  else
    {
      echo ""
      echo "/** Enable system-level wp-cron (hz-oneclick) */"
      echo "define( 'DISABLE_WP_CRON', true );"
    } >>"$WP_CONFIG"
  fi

  # 2) Write systemd unit files
  local svc="/etc/systemd/system/wp-cron-${SITE_SLUG}.service"
  local tmr="/etc/systemd/system/wp-cron-${SITE_SLUG}.timer"

  cat >"$svc" <<EOF
[Unit]
Description=Run WordPress cron for ${SITE_SLUG}

[Service]
Type=oneshot
ExecStart=/bin/bash -c '${PHP_CMD}'
EOF

  cat >"$tmr" <<EOF
[Unit]
Description=Timer to run WordPress cron for ${SITE_SLUG} every ${INTERVAL_MIN} minutes

[Timer]
OnBootSec=5min
OnUnitActiveSec=${INTERVAL_MIN}min
Unit=wp-cron-${SITE_SLUG}.service

[Install]
WantedBy=timers.target
EOF

  systemctl daemon-reload
  systemctl enable --now "wp-cron-${SITE_SLUG}.timer"

  info "Systemd wp-cron service and timer have been created/updated and enabled."
  press_enter_to_continue
}

# -------- Restore pseudo-cron: comment/remove DISABLE_WP_CRON --------

restore_wp_cron_step() {
  step "Step 6/7 - Restore WordPress default pseudo-cron"
  prompt_exit_hint
  echo

  echo "The following actions will be performed:"
  echo "  - Comment or remove DISABLE_WP_CRON in wp-config.php"
  echo "  - Any existing systemd timer for this site will be left untouched"
  echo "    (you may disable/remove it manually if desired)."
  echo
  read -r -p "Restore default pseudo-cron mode? (Y/n): " confirm
  case "$confirm" in
    ""|Y|y) ;;
    *)
      warn "User cancelled. Wizard will exit."
      exit 0
      ;;
  esac

  if grep -q "DISABLE_WP_CRON" "$WP_CONFIG"; then
    sed -i -E "s/^(.*DISABLE_WP_CRON.*)$/\/\/ \1/" "$WP_CONFIG"
    info "DISABLE_WP_CRON line has been commented in wp-config.php."
  else
    info "DISABLE_WP_CRON is not defined. No change needed."
  fi

  press_enter_to_continue
}

# -------- Step 7: summary --------

summary_step() {
  step "Step 7/7 - Summary and next steps"

  local timer_name="wp-cron-${SITE_SLUG}.timer"
  local timer_status="not-found"
  local disable_status="unknown"

  if grep -q "DISABLE_WP_CRON" "$WP_CONFIG"; then
    if grep -E "DISABLE_WP_CRON'.*true" "$WP_CONFIG" >/dev/null 2>&1; then
      disable_status="true"
    else
      disable_status="defined-but-not-true"
    fi
  else
    disable_status="not-defined"
  fi

  if systemctl list-timers --all 2>/dev/null | grep -q "$timer_name"; then
    if systemctl is-active "$timer_name" >/dev/null 2>&1; then
      timer_status="active"
    else
      timer_status="exists-not-active"
    fi
  fi

  echo "Site root: $WP_ROOT"
  echo "DISABLE_WP_CRON: $disable_status"
  echo "Systemd timer:   $timer_name ($timer_status)"
  echo

  echo "Useful commands:"
  echo "  systemctl status $timer_name"
  echo "  systemctl list-timers | grep wp-cron"
  echo
  echo "To fully revert to default pseudo-cron:"
  echo "  1) Edit wp-config.php and remove or comment DISABLE_WP_CRON"
  echo "  2) Disable and remove the corresponding wp-cron-*.timer / wp-cron-*.service"
  echo
  echo "Wizard finished. You can run this script again anytime to adjust settings."
}

# -------- Step 1: intro --------

intro_step() {
  step "Step 1/7 - Intro & warnings (version: $SCRIPT_VERSION)"
  echo "This wizard helps you configure how WordPress cron (wp-cron.php) is executed."
  echo
  echo "It can:"
  echo "  - Detect whether DISABLE_WP_CRON is set in wp-config.php"
  echo "  - Detect whether a systemd timer is taking over wp-cron"
  echo "  - Switch to systemd-based wp-cron, or restore default pseudo-cron"
  echo
  echo "It will NOT touch:"
  echo "  - Your database"
  echo "  - Your WordPress files"
  echo
  echo "Note:"
  echo "  If DISABLE_WP_CRON is true while no systemd timer is configured,"
  echo "  scheduled tasks (e.g. SEO plugins) may never run. This wizard helps"
  echo "  you avoid that situation."
  echo
  prompt_exit_hint
  echo
  read -r -p "Continue with this wizard? (Y/n, 0 = main menu): " ans
  case "$ans" in
    0)
      info "Exiting wizard and returning to main menu."
      exit 0
      ;;
    ""|Y|y)
      ;;
    *)
      info "User cancelled. Exiting."
      exit 0
      ;;
  esac
}

# -------- Main flow --------

main() {
  require_systemctl
  intro_step
  select_wp_root_step
  detect_state_step
  choose_target_mode_step

  case "$TARGET_MODE" in
    keep_default)
      info "Keeping default pseudo-cron mode. No changes applied."
      ;;
    keep_systemd)
      info "Keeping existing systemd wp-cron configuration. No changes applied."
      ;;
    restore_wp_cron)
      restore_wp_cron_step
      ;;
    enable_systemd|adjust_systemd)
      confirm_php_cmd_step
      config_interval_and_apply_step
      ;;
    *)
      warn "Unknown target mode. Wizard aborted."
      ;;
  esac

  summary_step
}

main "$@"
