#!/usr/bin/env bash
# install-ols-wp-standard.sh
# v0.5 - OLS + WordPress 标准安装（HTTP + 可选自动配置 HTTPS）
#
# 主要特性：
#   - 检测内存 <4G 时提示：仅前端 / LNMP / 回主菜单 / 退出
#   - 复用已有 80 端口 listener，自动追加 map，避免 404
#   - 结束时显示公网 IPv4 / IPv6，提醒配置 DNS
#   - SSL 三选项：
#       1) 只用 HTTP，TLS 交给 Cloudflare 等 CDN
#       2) Cloudflare Origin 证书：粘贴证书+私钥，一键写入 vhost + HTTPS
#       3) Let’s Encrypt：acme.sh 自动申请证书并写入 vhost（附带自动续期）

set -euo pipefail

# 颜色
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
BLUE="\033[34m"
NC="\033[0m"

pause() {
  echo
  read -rp "按回车键继续..." _
}

header_step() {
  local step="$1"
  local total="$2"
  local title="$3"
  echo
  echo "==================== Step ${step}/${total} ===================="
  echo "${title}"
  echo "===================================================="
}

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}[ERROR] 请用 root 执行本脚本。${NC}"
    exit 1
  fi
}

restart_lsws() {
  if systemctl list-unit-files | grep -q "^lsws\.service"; then
    systemctl restart lsws
  elif systemctl list-unit-files | grep -q "^lshttpd\.service"; then
    systemctl restart lshttpd
  elif [ -x /usr/local/lsws/bin/lswsctrl ]; then
    /usr/local/lsws/bin/lswsctrl restart
  fi
}

OS_NAME="unknown"
OS_VER="unknown"
ARCH="unknown"
MEM_MB=0
HOST_CLASS="unknown"  # low / normal

detect_env() {
  OS_NAME=$(lsb_release -si 2>/dev/null || echo "unknown")
  OS_VER=$(lsb_release -sr 2>/dev/null || echo "unknown")
  ARCH=$(uname -m)

  if grep -q "MemTotal" /proc/meminfo 2>/dev/null; then
    MEM_MB=$(awk '/MemTotal/ {printf "%.0f", $2/1024}' /proc/meminfo)
  else
    MEM_MB=0
  fi

  if (( MEM_MB > 0 && MEM_MB < 4000 )); then
    HOST_CLASS="low"
  else
    HOST_CLASS="normal"
  fi

  echo -e "${GREEN}[INFO] 系统：${OS_NAME} ${OS_VER} (${ARCH})${NC}"
  if (( MEM_MB > 0 )); then
    echo -e "${GREEN}[INFO] 物理内存：${MEM_MB} MB${NC}"
  fi

  if [ "$HOST_CLASS" = "low" ]; then
    echo -e "${YELLOW}[WARN] 当前机器内存 < 4G，建议数据库 / Redis 使用其他高配机器实例，${NC}"
    echo -e "${YELLOW}       本机只跑 OLS + WordPress 前端，或者改为 LNMP。${NC}"
  else
    echo -e "${GREEN}[INFO] 该机器内存在正常范围，可作为主站或 DB 宿主（仍建议 DB/Redis 单独规划）。${NC}"
  fi
}

handle_low_mem_choice() {
  if [ "$HOST_CLASS" != "low" ]; then
    return
  fi

  echo
  echo "请选择接下来的操作："
  echo "  1) 仍然继续执行本模块（OLS + WordPress 一键安装）"
  echo "  2) 改为 LNMP 一键安装（本模块退出，请在主菜单选择 LNMP 模块）"
  echo "  3) 返回 hz-oneclick 主菜单（本模块不做任何改动直接退出）"
  echo "  4) 直接退出脚本"
  read -rp "请输入选项 [1-4，默认: 1]: " LM_CHOICE
  LM_CHOICE=${LM_CHOICE:-1}

  case "$LM_CHOICE" in
    1)
      echo -e "${GREEN}[INFO] 已选择在低内存机器上继续安装 OLS + WordPress。${NC}"
      ;;
    2)
      echo -e "${YELLOW}[INFO] 请在 hz-oneclick 主菜单选择 LNMP 安装模块。${NC}"
      exit 0
      ;;
    3)
      echo -e "${GREEN}[INFO] 返回主菜单：本模块不做任何改动。${NC}"
      exit 0
      ;;
    4)
      echo -e "${GREEN}[INFO] 已退出脚本。${NC}"
      exit 0
      ;;
    *)
      echo -e "${YELLOW}[WARN] 无效输入，默认继续执行本模块。${NC}"
      ;;
  esac
}

install_ols() {
  header_step 2 8 "检查 / 安装 OpenLiteSpeed"

  if command -v lswsctrl >/dev/null 2>&1 || [ -d /usr/local/lsws ]; then
    echo -e "${GREEN}[INFO] 检测到系统中已有 OLS，将尝试直接启用。${NC}"
  else
    echo -e "${YELLOW}[WARN] 未检测到 OpenLiteSpeed，将尝试安装官方 OLS。${NC}"
    read -rp "现在自动安装 OLS（会执行 apt 操作）？ [y/N，默认: y] " INSTALL_OLS
    INSTALL_OLS=${INSTALL_OLS:-y}
    if [[ "$INSTALL_OLS" =~ ^[Yy]$ ]]; then
      echo -e "${GREEN}[INFO] 开始安装 OLS（使用官方仓库）...${NC}"
      apt update -y
      apt install -y wget gnupg lsb-release
      wget -O - https://repo.litespeed.sh | bash
      apt update -y
      apt install -y openlitespeed
    else
      echo -e "${RED}[ERROR] 用户选择不安装 OLS，无法继续。${NC}"
      exit 1
    fi
  fi

  restart_lsws
  sleep 2

  if pgrep -f lshttpd >/dev/null 2>&1; then
    echo -e "${GREEN}[INFO] OLS 进程正在运行。${NC}"
  else
    echo -e "${RED}[WARN] 无法确认 OLS 进程是否正常运行，请稍后用 systemctl status lsws 检查。${NC}"
  fi

  pause
}

WP_DOMAIN=""
WP_SLUG=""
WP_DOCROOT=""

collect_site_info() {
  header_step 3 8 "收集站点信息（域名 / slug / 路径）"

  while true; do
    read -rp "请输入站点主域名（例如: blog.example.com）: " WP_DOMAIN
    if [ -n "$WP_DOMAIN" ]; then
      break
    fi
    echo -e "${YELLOW}[WARN] 域名不能为空，请重新输入。${NC}"
  done

  read -rp "请输入站点代号 slug（例如: blog，默认: 域名第 1 段）: " WP_SLUG
  if [ -z "$WP_SLUG" ]; then
    WP_SLUG=$(echo "$WP_DOMAIN" | cut -d'.' -f1)
    [ -z "$WP_SLUG" ] && WP_SLUG="site"
  fi

  local default_docroot="/var/www/${WP_SLUG}/html"
  read -rp "WordPress 安装目录（默认: ${default_docroot}）: " WP_DOCROOT
  WP_DOCROOT=${WP_DOCROOT:-$default_docroot}

  echo
  echo -e "${GREEN}[INFO] 将使用以下站点配置：${NC}"
  echo "  域名:   ${WP_DOMAIN}"
  echo "  slug:   ${WP_SLUG}"
  echo "  路径:   ${WP_DOCROOT}"
  pause
}

DB_HOST=""
DB_PORT=""
DB_NAME=""
DB_USER=""
DB_PASSWORD=""
TABLE_PREFIX=""

collect_db_info() {
  header_step 4 8 "收集数据库信息（本脚本不自动建库）"

  echo -e "${YELLOW}[提示] 本脚本不会自动创建数据库 / 用户，只会把这些信息写入 wp-config.php。${NC}"
  if [ "$HOST_CLASS" = "low" ]; then
    echo -e "${YELLOW}[提示] 检测到本机为低配，建议 DB_HOST 填写“另一台高配机器的内网 / Tailscale IP”。${NC}"
  else
    echo -e "${GREEN}[INFO] 如 DB 容器部署在本机，可直接使用 127.0.0.1。${NC}"
  fi
  echo

  read -rp "DB 主机（默认: 127.0.0.1，不要带端口）: " DB_HOST
  DB_HOST=${DB_HOST:-127.0.0.1}

  read -rp "DB 端口（默认: 3306）: " DB_PORT
  DB_PORT=${DB_PORT:-3306}

  while true; do
    read -rp "DB 名称（例如: ${WP_SLUG}_wp）: " DB_NAME
    [ -n "$DB_NAME" ] && break
    echo -e "${YELLOW}[WARN] DB 名称不能为空。${NC}"
  done

  while true; do
    read -rp "DB 用户名（例如: ${WP_SLUG}_user）: " DB_USER
    [ -n "$DB_USER" ] && break
    echo -e "${YELLOW}[WARN] DB 用户名不能为空。${NC}"
  done

  while true; do
    read -rsp "DB 密码（输入时不显示）: " DB_PASSWORD
    echo
    [ -n "$DB_PASSWORD" ] && break
    echo -e "${YELLOW}[WARN] DB 密码不能为空。${NC}"
  done

  read -rp "表前缀（默认: wp_）: " TABLE_PREFIX
  TABLE_PREFIX=${TABLE_PREFIX:-wp_}

  echo
  echo -e "${GREEN}[INFO] DB 配置信息如下（请确保对应实例已建库+授权）：${NC}"
  echo "  DB_HOST: ${DB_HOST}"
  echo "  DB_PORT: ${DB_PORT}"
  echo "  DB_NAME: ${DB_NAME}"
  echo "  DB_USER: ${DB_USER}"
  echo "  表前缀: ${TABLE_PREFIX}"
  pause
}

prepare_docroot() {
  header_step 5 8 "准备站点目录与权限"

  echo -e "${GREEN}[INFO] 创建站点目录: ${WP_DOCROOT}${NC}"
  mkdir -p "${WP_DOCROOT}"
  mkdir -p "/var/www/${WP_SLUG}"

  chown -R nobody:nogroup "/var/www/${WP_SLUG}"
  find "/var/www/${WP_SLUG}" -type d -exec chmod 755 {} \;
  find "/var/www/${WP_SLUG}" -type f -exec chmod 644 {} \;

  echo -e "${GREEN}[INFO] 站点目录准备完成。${NC}"
  pause
}

install_wordpress() {
  header_step 6 8 "下载并安装 WordPress"

  if [ -f "${WP_DOCROOT}/wp-config.php" ]; then
    echo -e "${YELLOW}[WARN] 检测到 ${WP_DOCROOT}/wp-config.php 已存在，将只检查 OLS 配置。${NC}"
    pause
    return
  fi

  local tmpdir
  tmpdir=$(mktemp -d)
  cd "$tmpdir"

  echo -e "${GREEN}[INFO] 正在下载最新 WordPress...${NC}"
  curl -fsSL -o wordpress.tar.gz https://wordpress.org/latest.tar.gz
  tar xf wordpress.tar.gz

  echo -e "${GREEN}[INFO] 拷贝 WordPress 文件到 ${WP_DOCROOT}...${NC}"
  cp -R wordpress/* "${WP_DOCROOT}/"

  cd /
  rm -rf "$tmpdir"

  chown -R nobody:nogroup "/var/www/${WP_SLUG}"
  find "/var/www/${WP_SLUG}" -type d -exec chmod 755 {} \;
  find "/var/www/${WP_SLUG}" -type f -exec chmod 644 {} \;

  echo -e "${GREEN}[INFO] WordPress 核心文件安装完成。${NC}"
  pause
}

attach_domain_to_http_listener() {
  local httpd_conf="/usr/local/lsws/conf/httpd_config.conf"
  local slug="$1"
  local domain="$2"

  # 已存在 map 时，不再重复添加
  if grep -q "map[[:space:]]\+${slug}[[:space:]]\+${domain}" "$httpd_conf"; then
    echo -e "${GREEN}[INFO] 已检测到 HTTP listener 中存在 map ${slug} ${domain}，跳过添加。${NC}"
    return
  fi

  # 找第一个监听 :80 的 listener 名字
  local http_listener
  http_listener=$(
    awk '
      $1=="listener" {
        name=$2
        gsub("{","",name)
        current=name
      }
      $1=="address" && $2 ~ /:80/ {
        print current
        exit
      }
    ' "$httpd_conf" 2>/dev/null || true
  )

  if [ -n "$http_listener" ]; then
    echo -e "${GREEN}[INFO] 将域名 ${domain} 绑定到已有 HTTP listener: ${http_listener}${NC}"
    awk -v ls="$http_listener" -v slug="$slug" -v dom="$domain" '
      $1=="listener" {
        name=$2
        gsub("{","",name)
        if (name == ls) {
          in_l = 1
        }
      }
      in_l && $0 ~ /^}/ {
        printf("  map                     %s %s\n", slug, dom)
        in_l = 0
      }
      { print }
    ' "$httpd_conf" > "${httpd_conf}.tmp" && mv "${httpd_conf}.tmp" "$httpd_conf"
  else
    echo -e "${YELLOW}[WARN] 未检测到任何监听 :80 的 listener，将新建 listener HTTP。${NC}"
    cat >> "$httpd_conf" <<EOF

listener HTTP {
  address                 *:80
  secure                  0
  map                     ${slug} ${domain}
}
EOF
  fi
}

attach_domain_to_https_listener() {
  local httpd_conf="/usr/local/lsws/conf/httpd_config.conf"
  local slug="$1"
  local domain="$2"

  # 已存在 map 时不再添加
  if grep -q "map[[:space:]]\+${slug}[[:space:]]\+${domain}" "$httpd_conf"; then
    echo -e "${GREEN}[INFO] 已检测到 HTTPS listener 中存在 map ${slug} ${domain}，跳过添加。${NC}"
    return
  fi

  # 找第一个监听 :443 的 listener
  local https_listener
  https_listener=$(
    awk '
      $1=="listener" {
        name=$2
        gsub("{","",name)
        current=name
      }
      $1=="address" && $2 ~ /:443/ {
        print current
        exit
      }
    ' "$httpd_conf" 2>/dev/null || true
  )

  if [ -n "$https_listener" ]; then
    echo -e "${GREEN}[INFO] 将域名 ${domain} 绑定到已有 HTTPS listener: ${https_listener}${NC}"
    awk -v ls="$https_listener" -v slug="$slug" -v dom="$domain" '
      $1=="listener" {
        name=$2
        gsub("{","",name)
        if (name == ls) {
          in_l = 1
        }
      }
      in_l && $0 ~ /^}/ {
        # 确保 secure 1 存在
        print "  secure                  1"
        printf("  map                     %s %s\n", slug, dom)
        in_l = 0
      }
      { print }
    ' "$httpd_conf" > "${httpd_conf}.tmp" && mv "${httpd_conf}.tmp" "$httpd_conf"
  else
    echo -e "${YELLOW}[WARN] 未检测到任何监听 :443 的 listener，将新建 listener SSL。${NC}"
    cat >> "$httpd_conf" <<EOF

listener SSL {
  address                 *:443
  secure                  1
  map                     ${slug} ${domain}
}
EOF
  fi
}

add_vhssl_block() {
  local slug="$1"
  local cert_path="$2"
  local key_path="$3"

  local vhconf="/usr/local/lsws/conf/vhosts/${slug}/vhconf.conf"

  if ! grep -q "^vhssl" "$vhconf" 2>/dev/null; then
    cat >> "$vhconf" <<EOF

vhssl  {
  keyFile                 ${key_path}
  certFile                ${cert_path}
}
EOF
  else
    # 简单地在末尾追加一份，以最新为准
    cat >> "$vhconf" <<EOF

# 更新证书
vhssl  {
  keyFile                 ${key_path}
  certFile                ${cert_path}
}
EOF
  fi
}

generate_wp_config_and_ols() {
  header_step 7 8 "生成 wp-config.php 与 OLS 虚拟主机配置"

  # 1) wp-config.php
  if [ ! -f "${WP_DOCROOT}/wp-config.php" ]; then
    echo -e "${GREEN}[INFO] 生成新的 wp-config.php...${NC}"
    local WP_SALTS
    WP_SALTS=$(curl -fsSL https://api.wordpress.org/secret-key/1.1/salt/ 2>/dev/null || echo "")

    cat > "${WP_DOCROOT}/wp-config.php" <<EOF
<?php
define( 'DB_NAME', '${DB_NAME}' );
define( 'DB_USER', '${DB_USER}' );
define( 'DB_PASSWORD', '${DB_PASSWORD}' );
define( 'DB_HOST', '${DB_HOST}:${DB_PORT}' );
define( 'DB_CHARSET', 'utf8mb4' );
define( 'DB_COLLATE', '' );

\$table_prefix = '${TABLE_PREFIX}';

EOF

    if [ -n "$WP_SALTS" ]; then
      echo "$WP_SALTS" >> "${WP_DOCROOT}/wp-config.php"
    else
      echo "// TODO: 请到 https://api.wordpress.org/secret-key/1.1/salt/ 生成 SALT 并替换。" >> "${WP_DOCROOT}/wp-config.php"
    fi

    cat >> "${WP_DOCROOT}/wp-config.php" <<'EOF'

define( 'WP_DEBUG', false );
define( 'FS_METHOD', 'direct' );

if ( ! defined( 'ABSPATH' ) ) {
        define( 'ABSPATH', __DIR__ . '/' );
}
require_once ABSPATH . 'wp-settings.php';
EOF

    chown nobody:nogroup "${WP_DOCROOT}/wp-config.php"
    chmod 640 "${WP_DOCROOT}/wp-config.php"
  else
    echo -e "${YELLOW}[WARN] ${WP_DOCROOT}/wp-config.php 已存在，请确认其中 DB 配置是否正确。${NC}"
  fi

  # 2) OLS vhost + listener
  echo
  echo -e "${GREEN}[INFO] 开始为该站点创建 OLS 虚拟主机配置...${NC}"

  local lsws_conf_root="/usr/local/lsws/conf"
  local vhost_dir="${lsws_conf_root}/vhosts/${WP_SLUG}"
  local vhconf="${vhost_dir}/vhconf.conf"
  local httpd_conf="${lsws_conf_root}/httpd_config.conf"

  mkdir -p "$vhost_dir"

  cat > "$vhconf" <<EOF
docRoot                   ${WP_DOCROOT}
vhDomain                  ${WP_DOMAIN}
enableGzip                1
index  {
  useServer               0
  indexFiles              index.php,index.html
}
context / {
  location                ${WP_DOCROOT}
  allowBrowse             1
}
phpIniOverride  {
}
EOF

  # virtualhost 块
  if ! grep -q "virtualhost[[:space:]]\+${WP_SLUG}[[:space:]]*{" "$httpd_conf"; then
    cat >> "$httpd_conf" <<EOF

virtualhost ${WP_SLUG} {
  vhRoot                  /var/www/${WP_SLUG}
  configFile              conf/vhosts/${WP_SLUG}/vhconf.conf
  allowSymbolLink         1
  enableScript            1
  restrained              1
}
EOF
  fi

  # HTTP listener 绑定
  attach_domain_to_http_listener "${WP_SLUG}" "${WP_DOMAIN}"

  echo -e "${GREEN}[INFO] 重启 OLS 以应用新配置...${NC}"
  restart_lsws

  echo -e "${GREEN}[INFO] OLS 配置步骤完成。${NC}"
  pause
}

setup_https_cf_origin() {
  local cert_dir="/usr/local/lsws/conf/certs"
  mkdir -p "$cert_dir"

  local CERT_FILE="${cert_dir}/${WP_SLUG}-cf-origin.crt"
  local KEY_FILE="${cert_dir}/${WP_SLUG}-cf-origin.key"

  echo
  echo -e "${GREEN}[INFO] 现在为 Cloudflare Origin 证书准备文件：${NC}"
  echo "  域名：${WP_DOMAIN}"
  echo
  echo "步骤 1：请在浏览器中打开 Cloudflare 后台，为 ${WP_DOMAIN} 生成 Origin 证书。"
  echo "        通常会给你一段证书（BEGIN CERTIFICATE...）和一段私钥（BEGIN PRIVATE KEY...）。"
  echo
  echo "步骤 2：回到本终端："
  echo "  2.1 粘贴整段证书内容（含 BEGIN/END 行），粘贴完成后按 Ctrl+D 结束输入。"
  echo

  read -rp "准备好粘贴证书内容后按回车继续..." _

  cat > "$CERT_FILE"

  echo
  echo "现在粘贴私钥内容（包含 BEGIN PRIVATE KEY / END PRIVATE KEY），"
  echo "粘贴完成后同样按 Ctrl+D："
  echo

  cat > "$KEY_FILE"

  chmod 600 "$CERT_FILE" "$KEY_FILE"
  chown root:root "$CERT_FILE" "$KEY_FILE" || true

  echo -e "${GREEN}[INFO] 证书与私钥已保存：${NC}"
  echo "  certFile: $CERT_FILE"
  echo "  keyFile : $KEY_FILE"

  # 绑定 HTTPS listener + vhost vhssl
  attach_domain_to_https_listener "${WP_SLUG}" "${WP_DOMAIN}"
  add_vhssl_block "${WP_SLUG}" "$CERT_FILE" "$KEY_FILE"

  echo -e "${GREEN}[INFO] 重启 OLS 应用 HTTPS 配置...${NC}"
  restart_lsws
}

setup_https_letsencrypt() {
  local ACME_HOME="${HOME}/.acme.sh"
  local ACME_CMD="${ACME_HOME}/acme.sh"

  echo
  echo -e "${GREEN}[INFO] 将使用 acme.sh 自动申请 Let’s Encrypt 证书：${NC}"
  echo "  域名：${WP_DOMAIN}"
  echo "  Webroot：${WP_DOCROOT}"
  echo
  echo "请确认："
  echo "  1）${WP_DOMAIN} 已解析到本机公网 IP；"
  echo "  2）80 端口对公网开放；"
  echo "  3）如使用 Cloudflare，请确保不会拦截 HTTP-01 验证请求。"
  echo

  read -rp "请输入用于 Let’s Encrypt 通知的邮箱（可留空，直接回车跳过）: " LE_EMAIL

  if [ ! -x "$ACME_CMD" ]; then
    echo -e "${GREEN}[INFO] acme.sh 未安装，开始安装...${NC}"
    curl -fsSL https://get.acme.sh | sh
  fi

  ACME_CMD="${HOME}/.acme.sh/acme.sh"

  if [ -n "${LE_EMAIL:-}" ]; then
    "$ACME_CMD" --register-account -m "$LE_EMAIL" || true
  fi

  echo -e "${GREEN}[INFO] 正在通过 Webroot 模式申请证书...${NC}"
  if ! "$ACME_CMD" --issue -d "$WP_DOMAIN" -w "$WP_DOCROOT"; then
    echo -e "${RED}[ERROR] Let’s Encrypt 证书申请失败，请检查域名解析与 80 端口，再重试。${NC}"
    return 1
  fi

  local cert_dir="/usr/local/lsws/conf/certs"
  mkdir -p "$cert_dir"
  local CERT_FILE="${cert_dir}/${WP_SLUG}-le-fullchain.cer"
  local KEY_FILE="${cert_dir}/${WP_SLUG}-le.key"

  "$ACME_CMD" --install-cert -d "$WP_DOMAIN" \
    --fullchain-file "$CERT_FILE" \
    --key-file "$KEY_FILE" \
    --reloadcmd "systemctl restart lsws"

  chmod 600 "$CERT_FILE" "$KEY_FILE"
  chown root:root "$CERT_FILE" "$KEY_FILE" || true

  echo -e "${GREEN}[INFO] Let’s Encrypt 证书已安装：${NC}"
  echo "  certFile: $CERT_FILE"
  echo "  keyFile : $KEY_FILE"

  attach_domain_to_https_listener "${WP_SLUG}" "${WP_DOMAIN}"
  add_vhssl_block "${WP_SLUG}" "$CERT_FILE" "$KEY_FILE"
}

show_ip_and_ssl_menu() {
  header_step 8 8 "服务器 IP 信息与 SSL / HTTPS 选项"

  # 公网 IP
  local PUB4 PUB6
  PUB4=$(curl -4s --max-time 5 https://ifconfig.me 2>/dev/null || true)
  PUB6=$(curl -6s --max-time 5 https://ifconfig.me 2>/dev/null || true)

  echo -e "${GREEN}[INFO] 建议在域名 DNS 中配置以下记录：${NC}"
  if [ -n "${PUB4:-}" ]; then
    echo "  公网 IPv4: ${PUB4}  （A 记录）"
  else
    echo "  公网 IPv4: 未能自动检测，请在云控制台查看公网 IP。"
  fi
  if [ -n "${PUB6:-}" ]; then
    echo "  公网 IPv6: ${PUB6}  （AAAA 记录，如已启用 IPv6）"
  else
    echo "  公网 IPv6: 未能自动检测（如未启用 IPv6 可忽略）。"
  fi

  echo
  echo "当前站点域名：${WP_DOMAIN}"
  echo "  通常你需要在 DNS 中添加："
  echo "    A    ${WP_DOMAIN} -> 公网 IPv4"
  echo "    AAAA ${WP_DOMAIN} -> 公网 IPv6（如启用）"
  echo

  echo "请选择 SSL / HTTPS 模式："
  echo "  1) 仅使用 HTTP 源站，由 Cloudflare 等 CDN 终止 TLS"
  echo "  2) 使用 Cloudflare Origin 证书（粘贴证书+私钥，一键配置 HTTPS）"
  echo "  3) 使用 Let’s Encrypt 自动申请证书（acme.sh，自动续期）"
  read -rp "请选择 [1/2/3，默认: 1]: " SSL_CHOICE
  SSL_CHOICE=${SSL_CHOICE:-1}

  case "$SSL_CHOICE" in
    1)
      echo
      echo -e "${GREEN}[INFO] 已选择：源站只提供 HTTP，TLS 交给 Cloudflare 等 CDN。${NC}"
      echo "  - Cloudflare 后台建议："
      echo "      * 可先用 Flexible 或 Full 模式快速验证站点是否正常；"
      echo "      * 当你在源站配好证书后再切换到 Full (strict)。"
      ;;
    2)
      setup_https_cf_origin
      ;;
    3)
      setup_https_letsencrypt || true
      ;;
    *)
      echo -e "${YELLOW}[WARN] 无效输入，按选项 1 处理（仅 HTTP）。${NC}"
      ;;
  esac

  echo
  echo -e "${GREEN}[完成] OLS + WordPress 标准安装（v0.5）执行完毕。${NC}"
  echo "  域名：     ${WP_DOMAIN}"
  echo "  slug：     ${WP_SLUG}"
  echo "  安装路径： ${WP_DOCROOT}"
  echo "  DB_HOST：  ${DB_HOST}"
  echo "  DB_PORT：  ${DB_PORT}"
  echo "  DB_NAME：  ${DB_NAME}"
  echo "  DB_USER：  ${DB_USER}"
}

main() {
  require_root

  echo
  echo "===================================================="
  echo "  OLS + WordPress 标准安装模块（v0.5）"
  echo "===================================================="

  header_step 1 8 "环境检查（root / 系统版本 / 架构 / 内存）"
  detect_env
  handle_low_mem_choice
  pause

  install_ols
  collect_site_info
  collect_db_info
  prepare_docroot
  install_wordpress
  generate_wp_config_and_ols
  show_ip_and_ssl_menu
}

main "$@"
