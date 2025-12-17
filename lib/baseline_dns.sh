#!/usr/bin/env bash

# Baseline diagnostics for DNS/IP (dual-stack A+AAAA).

baseline_dns_is_private_ip() {
  local ip
  ip="$1"

  if echo "$ip" | grep -Eq '^[0-9]{1,3}(\.[0-9]{1,3}){3}$'; then
    case "$ip" in
      10.*|192.168.*|127.*|169.254.*|100.6[4-9].*|100.[7-9][0-9].*|100.1[01][0-9].*|100.12[0-7].*)
        return 0
        ;;
      172.1[6-9].*|172.2[0-9].*|172.3[0-1].*)
        return 0
        ;;
    esac
    return 1
  fi

  if echo "$ip" | grep -qiE '^[0-9a-f:]+$'; then
    if echo "$ip" | grep -qiE '^(fc|fd)[0-9a-f:]*'; then
      return 0
    fi
    if echo "$ip" | grep -qiE '^fe80:'; then
      return 0
    fi
    if echo "$ip" | grep -qiE '^::1$'; then
      return 0
    fi
    if echo "$ip" | grep -qiE '^ff'; then
      return 0
    fi
    return 1
  fi

  return 1
}

baseline_dns_get_public_ip() {
  # Usage: baseline_dns_get_public_ip <4|6>
  local family ip curl_flag
  family="$1"
  ip=""
  curl_flag="-${family}"

  if command -v curl >/dev/null 2>&1; then
    ip="$(curl "${curl_flag}" -fsS --max-time 4 --connect-timeout 3 https://api.ipify.org 2>/dev/null \
      || curl "${curl_flag}" -fsS --max-time 4 --connect-timeout 3 https://ifconfig.me 2>/dev/null || true)"
    ip="${ip//$'\n'/}"
    ip="${ip//$'\r'/}"
    ip="${ip//$'\t'/}"
  fi

  if [ "$family" = "4" ]; then
    if ! echo "$ip" | grep -Eq '^[0-9]{1,3}(\.[0-9]{1,3}){3}$'; then
      if command -v ip >/dev/null 2>&1; then
        ip="$(ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1)"
      fi
    fi
    if ! echo "$ip" | grep -Eq '^[0-9]{1,3}(\.[0-9]{1,3}){3}$'; then
      ip="NOT_FOUND"
    fi
  else
    if ! echo "$ip" | grep -qiE '^[0-9a-f:]+$'; then
      if command -v ip >/dev/null 2>&1; then
        ip="$(ip -6 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1)"
      fi
    fi
    if ! echo "$ip" | grep -qiE '^[0-9a-f:]+$'; then
      ip="NOT_FOUND"
    fi
  fi

  printf "%s" "$ip"
}

baseline_dns_resolve() {
  # Usage: baseline_dns_resolve <A|AAAA> <domain>
  local record_type domain output tool_used candidate
  record_type="$1"
  domain="$2"
  output=""
  tool_used=0

  if command -v dig >/dev/null 2>&1; then
    tool_used=1
    candidate="$(dig +short "$domain" "$record_type" 2>/dev/null | sed '/^;/d' | sed '/^$/d')"
    if [ -n "$candidate" ]; then
      output="$candidate"
    fi
  fi

  if [ -z "$output" ] && command -v nslookup >/dev/null 2>&1; then
    tool_used=1
    candidate="$(nslookup -type="$record_type" "$domain" 2>/dev/null | awk '/Address: /{print $2}' | sed '/^$/d')"
    if [ -n "$candidate" ]; then
      output="$candidate"
    fi
  fi

  if [ -z "$output" ] && command -v drill >/dev/null 2>&1; then
    tool_used=1
    candidate="$(drill -t "$record_type" "$domain" 2>/dev/null | awk '/^;ANSWER/{flag=1; next} flag && NF{print $5}' | sed '/^$/d')"
    if [ -n "$candidate" ]; then
      output="$candidate"
    fi
  fi

  if [ -z "$output" ] && command -v getent >/dev/null 2>&1; then
    tool_used=1
    candidate="$(getent ahosts "$domain" 2>/dev/null | awk -v t="$record_type" 'tolower(t)=="aaaa" {if ($1 ~ /:/) print $1} tolower(t)=="a" {if ($1 !~ /:/) print $1}' | sed '/^$/d')"
    if [ -n "$candidate" ]; then
      output="$candidate"
    fi
  fi

  if [ -z "$output" ] && command -v resolvectl >/dev/null 2>&1; then
    tool_used=1
    candidate="$(resolvectl query "$domain" "$record_type" 2>/dev/null | awk '/Address: /{print $2}' | sed '/^$/d')"
    if [ -n "$candidate" ]; then
      output="$candidate"
    fi
  fi

  if [ -n "$output" ]; then
    echo "$output"
  elif [ "$tool_used" -eq 1 ]; then
    echo "EMPTY"
  else
    echo "NOT_FOUND"
  fi
}

baseline_dns_contains_ip() {
  # Usage: baseline_dns_contains_ip "<records>" "<ip>"
  local records ip record
  records="$1"
  ip="$2"

  for record in $records; do
    if [ "${record,,}" = "${ip,,}" ]; then
      return 0
    fi
  done
  return 1
}

baseline_dns_run() {
  # Usage: baseline_dns_run "<domain>" "<lang>"
  local domain lang group ipv4 ipv6 ipv4_private ipv6_private dns_a dns_aaaa
  local dns_a_display dns_aaaa_display a_match aaaa_match status keyword suggestions
  local -a keywords=()
  local -a suggestion_list=()

  domain="$1"
  lang="${2:-zh}"
  group="DNS/IP"

  ipv4="$(baseline_dns_get_public_ip 4)"
  ipv6="$(baseline_dns_get_public_ip 6)"

  ipv4_private=0
  ipv6_private=0
  if [ "$ipv4" != "NOT_FOUND" ] && baseline_dns_is_private_ip "$ipv4"; then
    ipv4_private=1
  fi
  if [ "$ipv6" != "NOT_FOUND" ] && baseline_dns_is_private_ip "$ipv6"; then
    ipv6_private=1
  fi

  dns_a="$(baseline_dns_resolve A "$domain")"
  dns_aaaa="$(baseline_dns_resolve AAAA "$domain")"

  dns_a_display="$dns_a"
  dns_aaaa_display="$dns_aaaa"

  if [ "$dns_a_display" = "" ]; then
    dns_a_display="EMPTY"
  fi
  if [ "$dns_aaaa_display" = "" ]; then
    dns_aaaa_display="EMPTY"
  fi

  a_match="N/A"
  aaaa_match="N/A"

  if [ "$ipv4" != "NOT_FOUND" ] && [ "$ipv4_private" -eq 0 ] && [ "$dns_a_display" != "NOT_FOUND" ] && [ "$dns_a_display" != "EMPTY" ]; then
    if baseline_dns_contains_ip "$dns_a_display" "$ipv4"; then
      a_match="YES"
    else
      a_match="NO"
    fi
  fi

  if [ "$ipv6" != "NOT_FOUND" ] && [ "$ipv6_private" -eq 0 ] && [ "$dns_aaaa_display" != "NOT_FOUND" ]; then
    if [ "$dns_aaaa_display" != "EMPTY" ]; then
      if baseline_dns_contains_ip "$dns_aaaa_display" "$ipv6"; then
        aaaa_match="YES"
      else
        aaaa_match="NO"
      fi
    else
      aaaa_match="NO"
    fi
  fi

  status="PASS"
  keyword="DNS_IP"

  if [ "$ipv4_private" -eq 1 ] || [ "$ipv6_private" -eq 1 ]; then
    keywords+=("IP_PRIVATE_DETECTED")
    status="WARN"
    if [ "$lang" = "en" ]; then
      suggestion_list+=("Detected private/local IP; verify the actual public IP via your network/NAT before updating DNS.")
    else
      suggestion_list+=("检测到内网/私网 IP，请以公网 IP 为准（NAT/代理环境可能无法获取），建议手动确认公网 IP。")
    fi
  fi

  if [ "$a_match" = "NO" ]; then
    keywords+=("DNS_MISMATCH")
    status="FAIL"
    if [ "$lang" = "en" ]; then
      suggestion_list+=("Update the domain A record to point to this server's public IPv4, then retry after it propagates.")
    else
      suggestion_list+=("请将域名 A 记录指向本机公网 IPv4，等待生效后再重试。")
    fi
  elif [ "$a_match" = "N/A" ] && [ "$ipv4" != "NOT_FOUND" ] && [ "$ipv4_private" -eq 0 ] && [ "$dns_a_display" = "EMPTY" ]; then
    keywords+=("DNS_MISMATCH")
    if [ "$status" = "PASS" ]; then
      status="WARN"
    fi
    if [ "$lang" = "en" ]; then
      suggestion_list+=("No A record found; add an A record pointing to the detected public IPv4 before deployment.")
    else
      suggestion_list+=("未找到 A 记录，请将域名 A 记录指向检测到的公网 IPv4 后再部署。")
    fi
  fi

  if [ "$aaaa_match" = "NO" ]; then
    keywords+=("AAAA_MISSING_OR_WRONG")
    if [ "$status" = "PASS" ]; then
      status="WARN"
    fi
    if [ "$lang" = "en" ]; then
      suggestion_list+=("Add or correct the AAAA record to match the public IPv6; if IPv6 is unused, remove the AAAA record to avoid mismatch.")
    else
      suggestion_list+=("请补齐或修正 AAAA 记录以匹配公网 IPv6；若暂不使用 IPv6，可移除 AAAA 记录避免错误优先。")
    fi
  fi

  if [ "${#keywords[@]}" -gt 0 ]; then
    keyword="${keywords[*]}"
  fi

  suggestions="$(printf '%s\n' "${suggestion_list[@]}" | sed '/^$/d')"

  local evidence
  evidence="PUBLIC_IPV4: ${ipv4}\nPUBLIC_IPV6: ${ipv6}\nDNS_A_RECORD: ${dns_a_display}\nDNS_AAAA_RECORD: ${dns_aaaa_display}\nA_MATCH: ${a_match}\nAAAA_MATCH: ${aaaa_match}"

  baseline_add_result "$group" "DNS_IP" "$status" "$keyword" "$evidence" "$suggestions"
}
