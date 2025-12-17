#!/usr/bin/env bash

# Baseline diagnostics for HTTPS/521 group.

baseline_check_listen_port() {
  # Usage: baseline_check_listen_port <80|443>
  local port output
  port="$1"

  if command -v ss >/dev/null 2>&1; then
    output="$(ss -lnt 2>/dev/null || true)"
  elif command -v netstat >/dev/null 2>&1; then
    output="$(netstat -lnt 2>/dev/null || true)"
  else
    echo "WARN"
    return 0
  fi

  if echo "$output" | awk '{print $4}' | grep -Eq "(^|[:])${port}$"; then
    echo "OK"
  else
    echo "FAIL"
  fi
}

baseline_check_url_status() {
  # Usage: baseline_check_url_status "<url>"
  local url status exit_code
  url="$1"
  BASELINE_LAST_CURL_EXIT_CODE=0

  status="$(curl -L -s -o /dev/null -w "%{http_code}" --max-time 12 --connect-timeout 8 "$url" 2>/dev/null)"
  exit_code=$?
  BASELINE_LAST_CURL_EXIT_CODE="$exit_code"

  if [ "$exit_code" -eq 28 ]; then
    echo "TIMEOUT"
    return 0
  fi

  if [ "$exit_code" -ne 0 ]; then
    echo "ERROR"
    return 0
  fi

  if echo "$status" | grep -Eq '^[0-9]{3}$'; then
    echo "$status"
  else
    echo "ERROR"
  fi
}

baseline_https_run() {
  # Usage: baseline_https_run "<domain>" "<lang>"
  local domain lang group listen80 listen443 http_status https_status
  local listen80_state listen443_state http_state https_state
  local suggestions_http suggestions_https keyword_https keys_to_add=()
  local tls_mismatch=0 evidence_http evidence_https evidence_listen

  domain="$1"
  lang="${2:-zh}"
  group="HTTPS/521"

  listen80="$(baseline_check_listen_port 80)"
  listen443="$(baseline_check_listen_port 443)"

  http_status="$(baseline_check_url_status "http://${domain}/")"
  https_status="$(baseline_check_url_status "https://${domain}/")"
  local https_exit="$BASELINE_LAST_CURL_EXIT_CODE"

  case "$listen80" in
    OK) listen80_state="PASS" ;;
    FAIL) listen80_state="FAIL" ;;
    *) listen80_state="WARN" ;;
  esac

  case "$listen443" in
    OK) listen443_state="PASS" ;;
    FAIL) listen443_state="FAIL" ;;
    *) listen443_state="WARN" ;;
  esac

  if [ "$http_status" = "TIMEOUT" ] || [ "$http_status" = "ERROR" ]; then
    http_state="FAIL"
  elif echo "$http_status" | grep -Eq '^[0-9]{3}$' && [ "$http_status" -ge 400 ]; then
    http_state="FAIL"
  elif echo "$http_status" | grep -Eq '^[0-9]{3}$'; then
    http_state="PASS"
  else
    http_state="WARN"
  fi

  if [ "$https_status" = "TIMEOUT" ] || [ "$https_status" = "ERROR" ]; then
    https_state="FAIL"
  elif echo "$https_status" | grep -Eq '^[0-9]{3}$' && [ "$https_status" -ge 400 ]; then
    https_state="FAIL"
  elif echo "$https_status" | grep -Eq '^[0-9]{3}$'; then
    https_state="PASS"
  else
    https_state="WARN"
  fi

  if [ "$https_status" = "ERROR" ] && [ "$https_exit" -eq 60 ]; then
    tls_mismatch=1
    keys_to_add+=("ORIGIN_TLS_MISMATCH")
  fi

  evidence_listen="LISTEN_80: ${listen80}\nLISTEN_443: ${listen443}"
  evidence_http="HTTP_STATUS: ${http_status}"
  evidence_https="HTTPS_STATUS: ${https_status}"

  if [ "$listen80_state" = "FAIL" ]; then
    keys_to_add+=("PORT_80_BLOCKED")
  fi
  if [ "$listen443_state" = "FAIL" ]; then
    keys_to_add+=("PORT_443_BLOCKED")
  fi

  if [ "$lang" = "en" ]; then
    suggestions_http="HTTP check failed or returned an error. Verify DNS/proxy routing and origin availability."
    suggestions_https="HTTPS check failed or returned an error. Ensure certificates and proxy mode match."
  else
    suggestions_http="HTTP 访问异常，请检查 DNS/代理配置与回源连通性。"
    suggestions_https="HTTPS 访问异常，请检查证书与代理模式是否匹配。"
  fi

  baseline_add_result "$group" "LISTEN_80" "$listen80_state" \
    "$([ "$listen80_state" = "FAIL" ] && echo "PORT_80_BLOCKED" || echo "LISTEN_80")" \
    "${evidence_listen%%\n*}" \
    "$([ "$listen80_state" = "FAIL" ] && echo "$( [ "$lang" = "en" ] && echo "Confirm firewall/security rules allow port 80 and the service is listening." || echo "检查系统防火墙与安全规则是否放行 80；确认服务已监听该端口。")" || echo "")"

  baseline_add_result "$group" "LISTEN_443" "$listen443_state" \
    "$([ "$listen443_state" = "FAIL" ] && echo "PORT_443_BLOCKED" || echo "LISTEN_443")" \
    "${evidence_listen#*\n}" \
    "$([ "$listen443_state" = "FAIL" ] && echo "$( [ "$lang" = "en" ] && echo "Confirm firewall/security rules allow port 443 and the service is listening." || echo "检查系统防火墙与安全规则是否放行 443；确认服务已监听该端口。")" || echo "")"

  baseline_add_result "$group" "HTTP_STATUS" "$http_state" "HTTP_STATUS" \
    "$evidence_http" \
    "$([ "$http_state" = "FAIL" ] && echo "$suggestions_http" || echo "")"

  keyword_https="${keys_to_add[*]}"
  if [ -z "$keyword_https" ]; then
    keyword_https="HTTPS_STATUS"
  fi

  baseline_add_result "$group" "HTTPS_STATUS" "$https_state" "$keyword_https" \
    "$evidence_https" \
    "$({
      [ "$https_state" = "FAIL" ] && echo "$suggestions_https"
      if [ "$tls_mismatch" -eq 1 ]; then
        if [ "$lang" = "en" ]; then
          echo "TLS handshake indicates certificate mismatch; align origin certificate with the selected mode."
        else
          echo "HTTPS 握手提示证书不匹配，签发/安装证书时请确保回源证书与模式一致。"
        fi
      fi
    } | sed '/^$/d')"
}
