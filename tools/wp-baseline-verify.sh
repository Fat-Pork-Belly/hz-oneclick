#!/usr/bin/env bash
set -Euo pipefail

doc_root=""

usage() {
  cat <<'EOF'
Usage: wp-baseline-verify.sh [--doc-root <path>]

Runs LOMP WordPress baseline verification checklist.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --doc-root|--path)
      doc_root="${2:-}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      shift
      ;;
  esac
done

if [ -z "$doc_root" ]; then
  doc_root="${DOC_ROOT:-}"
fi

log_ok() {
  printf 'OK - %s\n' "$*"
}

log_warn() {
  printf 'WARN - %s\n' "$*"
}

join_by() {
  local delimiter="$1"
  shift
  local first=1 item
  for item in "$@"; do
    if [ "$first" -eq 1 ]; then
      printf '%s' "$item"
      first=0
    else
      printf '%s%s' "$delimiter" "$item"
    fi
  done
}

detect_lsphp_bin() {
  local bin
  for bin in /usr/local/lsws/lsphp*/bin/php; do
    if [ -x "$bin" ]; then
      printf '%s\n' "$bin"
    fi
  done | sort -V | tail -n1
}

resolve_default_theme_slug() {
  local year suffix
  year="$(date +%Y)"
  case "$year" in
    2020) suffix="base";;
    2021) suffix="one";;
    2022) suffix="two";;
    2023) suffix="three";;
    2024) suffix="four";;
    2025) suffix="five";;
    2026) suffix="six";;
    2027) suffix="seven";;
    2028) suffix="eight";;
    2029) suffix="nine";;
    2030) suffix="ten";;
    2031) suffix="eleven";;
    2032) suffix="twelve";;
    2033) suffix="thirteen";;
    2034) suffix="fourteen";;
    2035) suffix="fifteen";;
    *) suffix="";;
  esac

  if [ -z "$suffix" ]; then
    printf ""
    return
  fi

  if [ "$suffix" = "base" ]; then
    printf "twentytwenty"
  else
    printf "twentytwenty%s" "$suffix"
  fi
}

wp_available=0
hard_failures_enabled=1
if command -v wp >/dev/null 2>&1 && [ -n "$doc_root" ] && [ -d "$doc_root" ]; then
  wp_available=1
  log_ok "wp-cli available: $(command -v wp)"
else
  if command -v wp >/dev/null 2>&1; then
    log_warn "wp-cli available but doc root missing; skipping WP runtime checks."
  else
    log_warn "wp-cli not found; skipping WP runtime checks."
  fi
  hard_failures_enabled=0
fi

wp_cli() {
  wp --path="$doc_root" --allow-root "$@"
}

printf 'WP baseline verification checklist:\n'

php_bin="$(detect_lsphp_bin)"
if [ -z "$php_bin" ] && command -v php >/dev/null 2>&1; then
  php_bin="$(command -v php)"
fi

if [ -n "$php_bin" ] && [ -x "$php_bin" ]; then
  php_version="$("$php_bin" -r 'echo PHP_VERSION;' 2>/dev/null || true)"
  log_ok "LSPHP: ${php_bin} (${php_version:-unknown})"
else
  log_warn "LSPHP binary not found; skipping PHP extension checks."
fi

wp_installed=0
if [ "$wp_available" -eq 1 ]; then
  if wp_cli core is-installed --skip-plugins --skip-themes >/dev/null 2>&1; then
    wp_installed=1
    log_ok "WordPress core installed."
  else
    log_warn "WordPress core not installed."
    if [ "$hard_failures_enabled" -eq 1 ]; then
      hard_failures_enabled=2
    fi
  fi
else
  log_warn "wp-cli or doc root unavailable; skipping core/plugin/theme checks."
fi

if [ "$wp_installed" -eq 1 ]; then
  installed_plugins_raw="$(wp_cli plugin list --field=name --skip-plugins --skip-themes 2>/dev/null || true)"
  active_plugins_raw="$(wp_cli plugin list --status=active --field=name --skip-plugins --skip-themes 2>/dev/null || true)"
  mapfile -t installed_plugins < <(printf '%s\n' "$installed_plugins_raw" | sed '/^$/d')
  mapfile -t active_plugins < <(printf '%s\n' "$active_plugins_raw" | sed '/^$/d')
  installed_list="$(join_by ", " "${installed_plugins[@]:-}")"
  active_list="$(join_by ", " "${active_plugins[@]:-}")"

  extra_installed=()
  for plugin in "${installed_plugins[@]:-}"; do
    if [ "$plugin" != "litespeed-cache" ]; then
      extra_installed+=("$plugin")
    fi
  done

  extra_active=()
  for plugin in "${active_plugins[@]:-}"; do
    if [ "$plugin" != "litespeed-cache" ]; then
      extra_active+=("$plugin")
    fi
  done

  lscwp_installed=0
  lscwp_active=0
  if printf '%s\n' "${installed_plugins[@]:-}" | grep -qx "litespeed-cache"; then
    lscwp_installed=1
  fi
  if printf '%s\n' "${active_plugins[@]:-}" | grep -qx "litespeed-cache"; then
    lscwp_active=1
  fi

  if [ "$lscwp_installed" -eq 1 ] && [ "${#extra_installed[@]}" -eq 0 ]; then
    log_ok "Plugins installed: ${installed_list:-none}."
  else
    log_warn "Plugins installed: ${installed_list:-none} (non-LSCache: $(join_by ", " "${extra_installed[@]:-}"))."
    if [ "$hard_failures_enabled" -ge 1 ]; then
      hard_failures_enabled=2
    fi
  fi

  if [ "$lscwp_active" -eq 1 ] && [ "${#extra_active[@]}" -eq 0 ]; then
    log_ok "Plugins active: ${active_list:-none}."
  else
    log_warn "Plugins active: ${active_list:-none} (non-LSCache: $(join_by ", " "${extra_active[@]:-}"))."
    if [ "$hard_failures_enabled" -ge 1 ]; then
      hard_failures_enabled=2
    fi
  fi
fi

wp_config="${doc_root%/}/wp-config.php"
if [ -n "$doc_root" ] && [ -f "$wp_config" ]; then
  wp_cache_enabled=0
  if grep -Eq "define\\(['\"]WP_CACHE['\"],\\s*true\\)" "$wp_config"; then
    wp_cache_enabled=1
  fi

  if [ "${lscwp_active:-0}" -eq 1 ] && [ "$wp_cache_enabled" -eq 1 ]; then
    log_ok "WP_CACHE=true (LSCWP active)."
  elif [ "${lscwp_active:-0}" -eq 1 ] && [ "$wp_cache_enabled" -eq 0 ]; then
    log_warn "WP_CACHE not set to true while LSCWP is active."
    if [ "$hard_failures_enabled" -ge 1 ]; then
      hard_failures_enabled=2
    fi
  elif [ "${lscwp_active:-0}" -eq 0 ] && [ "$wp_cache_enabled" -eq 1 ]; then
    log_warn "WP_CACHE=true but LSCWP is not active."
    if [ "$hard_failures_enabled" -ge 1 ]; then
      hard_failures_enabled=2
    fi
  else
    log_ok "WP_CACHE=false (LSCWP inactive)."
  fi

  if grep -Eq "define\\(['\"]WP_DEBUG_DISPLAY['\"],\\s*false\\)" "$wp_config"; then
    log_ok "WP_DEBUG_DISPLAY=false."
  else
    log_warn "WP_DEBUG_DISPLAY not set to false."
    if [ "$hard_failures_enabled" -ge 1 ]; then
      hard_failures_enabled=2
    fi
  fi
else
  log_warn "wp-config.php not found; cannot verify WP_CACHE."
  if [ "$hard_failures_enabled" -ge 1 ]; then
    hard_failures_enabled=2
  fi
fi

if [ -n "$doc_root" ] && [ -f "${doc_root%/}/wp-content/advanced-cache.php" ]; then
  log_ok "advanced-cache.php present."
else
  log_warn "advanced-cache.php missing (expected plugin path: ${doc_root%/}/wp-content/plugins/litespeed-cache)."
fi

uploads_basedir=""
if [ "$wp_installed" -eq 1 ]; then
  uploads_basedir="$(wp_cli eval 'echo wp_upload_dir()["basedir"];' 2>/dev/null || true)"
fi
if [ -z "$uploads_basedir" ] && [ -n "$doc_root" ]; then
  uploads_basedir="${doc_root%/}/wp-content/uploads"
fi

fonts_dir=""
if [ -n "$uploads_basedir" ]; then
  fonts_dir="${uploads_basedir%/}/fonts"
  if [ -d "$uploads_basedir" ] && [ -d "$fonts_dir" ]; then
    perms="$(stat -c '%a %U:%G' "$fonts_dir" 2>/dev/null || true)"
    mode="${perms%% *}"
    owner_digit="${mode:0:1}"
    group_digit="${mode:1:1}"
    writable="no"
    if echo "$owner_digit" | grep -Eq '^[0-9]$' && [ "$owner_digit" -ge 2 ]; then
      writable="yes"
    elif echo "$group_digit" | grep -Eq '^[0-9]$' && [ "$group_digit" -ge 2 ]; then
      writable="yes"
    fi
    if [ "$writable" = "yes" ]; then
      log_ok "uploads/fonts writable: ${fonts_dir} (mode/owner=${perms:-unknown})."
    else
      log_warn "uploads/fonts not writable: ${fonts_dir} (mode/owner=${perms:-unknown})."
      if [ "$hard_failures_enabled" -ge 1 ]; then
        hard_failures_enabled=2
      fi
    fi
  else
    log_warn "uploads/fonts missing: ${fonts_dir}."
    if [ "$hard_failures_enabled" -ge 1 ]; then
      hard_failures_enabled=2
    fi
  fi
else
  log_warn "uploads directory not determined."
  if [ "$hard_failures_enabled" -ge 1 ]; then
    hard_failures_enabled=2
  fi
fi

if [ "$wp_installed" -eq 1 ]; then
  active_theme="$(wp_cli theme list --status=active --field=name --skip-plugins --skip-themes 2>/dev/null | head -n1)"
  installed_themes_raw="$(wp_cli theme list --field=name --skip-plugins --skip-themes 2>/dev/null || true)"
  mapfile -t installed_themes < <(printf '%s\n' "$installed_themes_raw" | sed '/^$/d')
  installed_theme_list="$(join_by ", " "${installed_themes[@]:-}")"
  target_theme="$(resolve_default_theme_slug)"
  expected_theme=""
  if [ -n "$target_theme" ] && printf '%s\n' "${installed_themes[@]:-}" | grep -qx "$target_theme"; then
    expected_theme="$target_theme"
  else
    expected_theme="$(printf '%s\n' "${installed_themes[@]:-}" | awk '/^twentytwenty/ {print}' | sort -V | tail -n1)"
  fi

  if [ -n "$expected_theme" ] && [ "$active_theme" = "$expected_theme" ]; then
    log_ok "Themes installed: ${installed_theme_list:-none}; active: ${active_theme}."
  else
    log_warn "Themes installed: ${installed_theme_list:-none}; active: ${active_theme:-none} (expected: ${expected_theme:-none})."
    if [ "$hard_failures_enabled" -ge 1 ]; then
      hard_failures_enabled=2
    fi
  fi
fi

if [ -n "$php_bin" ] && [ -x "$php_bin" ]; then
  modules="$("$php_bin" -m 2>/dev/null | tr '[:upper:]' '[:lower:]')" || modules=""
  missing_modules=()
  if ! printf '%s\n' "$modules" | grep -qx "imagick"; then
    missing_modules+=("imagick")
  fi
  if ! printf '%s\n' "$modules" | grep -qx "intl"; then
    missing_modules+=("intl")
  fi
  if [ "${#missing_modules[@]}" -eq 0 ]; then
    log_ok "LSPHP extensions present (imagick/intl)."
  else
    log_warn "LSPHP missing extensions: $(join_by ", " "${missing_modules[@]}")."
    if [ "$hard_failures_enabled" -ge 1 ]; then
      hard_failures_enabled=2
    fi
  fi
fi

if [ "$wp_installed" -eq 1 ]; then
  blog_public="$(wp_cli option get blog_public 2>/dev/null || true)"
  case "$blog_public" in
    1)
      log_ok "blog_public=1 (indexing enabled)."
      ;;
    *)
      log_warn "blog_public not set to 1 (current: ${blog_public:-unknown})."
      if [ "$hard_failures_enabled" -ge 1 ]; then
        hard_failures_enabled=2
      fi
      ;;
  esac
fi

if [ "$wp_installed" -eq 1 ]; then
  permalink_structure="$(wp_cli option get permalink_structure 2>/dev/null || true)"
  if [ -n "$permalink_structure" ] && [ "$permalink_structure" != "false" ]; then
    log_ok "permalink_structure set: ${permalink_structure}."
  else
    log_warn "permalink_structure not set."
    if [ "$hard_failures_enabled" -ge 1 ]; then
      hard_failures_enabled=2
    fi
  fi
fi

if [ "$hard_failures_enabled" -eq 2 ]; then
  exit 1
fi
exit 0
