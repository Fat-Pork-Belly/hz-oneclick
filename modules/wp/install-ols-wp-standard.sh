#!/usr/bin/env bash
# install-ols-wp-standard.sh
# v0.4 - OLS + WordPress 标准安装（基础版：HTTP 80，无自动建库）
#
# 变更摘要（相对 v0.3）：
#   - Step 8 增加公网 IPv4 / IPv6 显示，提醒去 DNS 配置 A / AAAA 记录
#   - Step 8 新增 SSL 选项说明（1=只用 HTTP + Cloudflare，2=之后自行配置证书）
#   - listener HTTP 已存在时，自动插入 map 行而不是只给提示
#   - 细节健壮性优化，避免未定义变量导致脚本中断

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
    echo -e "${YELLOW}[WARN] 当前机器内存 < 4G，建议数据库 / Redis 使用其他高配机器实例，"
    echo -e "       本机只跑 OLS + WordPress 前端。${NC}"
  else
    echo -e "${GREEN}[INFO] 该机器内存在正常范围，可作为主站或 DB 宿主（仍建议 DB/Redis 单独规划）。${NC}"
  fi
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

  if systemctl list-unit-files | grep -q "^lsws\.service"; then
    systemctl enable lsws >/dev/null 2>&1 || true
    systemctl restart lsws
  elif systemctl list-unit-files | grep -q "^lshttpd\.service"; then
    systemctl enable lshttpd >/dev/null 2>&1 || true
    systemctl restart lshttpd
  elif [ -x /usr/local/lsws/bin/lswsctrl ]; then
    /usr/local/lsws/bin/lswsctrl restart
  fi

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

  # listener HTTP + map
  if grep -q "^listener[[:space:]]\+HTTP" "$httpd_conf"; then
    # 若 listener HTTP 已存在且尚未 map 本站，则在其 block 尾部插入一行 map
    if ! grep -q "map[[:space:]]\+${WP_SLUG}[[:space:]]\+${WP_DOMAIN}" "$httpd_conf"; then
      awk -v slug="$WP_SLUG" -v dom="$WP_DOMAIN" '
        BEGIN{in_http=0}
        {
          print $0
          if ($1 == "listener" && $2 == "HTTP") {
            in_http=1
          } else if (in_http && $0 ~ /^}/) {
            printf("  map                     %s %s\n", slug, dom)
            in_http=0
          }
        }
      ' "$httpd_conf" > "${httpd_conf}.tmp" && mv "${httpd_conf}.tmp" "$httpd_conf"
    fi
  else
    # 不存在 listener HTTP：新建一个
    cat >> "$httpd_conf" <<EOF

listener HTTP {
  address                 *:80
  secure                  0
  map                     ${WP_SLUG} ${WP_DOMAIN}
}
EOF
  fi

  # 重启 OLS
  echo -e "${GREEN}[INFO] 重启 OLS 以应用新配置...${NC}"
  if systemctl list-unit-files | grep -q "^lsws\.service"; then
    systemctl restart lsws
  elif systemctl list-unit-files | grep -q "^lshttpd\.service"; then
    systemctl restart lshttpd
  elif [ -x /usr/local/lsws/bin/lswsctrl ]; then
    /usr/local/lsws/bin/lswsctrl restart
  fi

  echo -e "${GREEN}[INFO] OLS 配置步骤完成。${NC}"
  pause
}

show_ip_and_ssl_hint() {
  header_step 8 8 "服务器 IP 信息与 SSL / Cloudflare 选项"

  # 公网 IP（优先 curl ifconfig.me）
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
    echo "  公网 IPv6: 未能自动检测（如未开 IPv6 可忽略）。"
  fi

  echo
  echo "当前站点域名：${WP_DOMAIN}"
  echo "  通常你需要在 DNS 里添加："
  echo "    A    ${WP_DOMAIN} -> 公网 IPv4"
  echo "    AAAA ${WP_DOMAIN} -> 公网 IPv6（如启用）"

  echo
  echo "接下来请选择你打算如何处理 SSL / HTTPS："
  echo "  1) 暂时只用 HTTP，TLS 交给 Cloudflare 等 CDN（推荐入门）"
  echo "  2) 稍后自己在这台机上配置证书（Cloudflare Origin / Let’s Encrypt）"
  read -rp "请选择 [1/2，默认: 1]: " SSL_CHOICE
  SSL_CHOICE=${SSL_CHOICE:-1}

  if [ "$SSL_CHOICE" = "1" ]; then
    echo
    echo -e "${GREEN}[INFO] 已选择：仅配置 HTTP，由 Cloudflare 终止 TLS。${NC}"
    echo "  - Cloudflare 后台："
    echo "      * 刚开始可以用 Flexible 或 Full 模式，方便快速验证。"
    echo "      * 当你在源站配置好证书后，可以改为 Full (strict)。"
  else
    echo
    echo -e "${YELLOW}[提示] 你选择：稍后自行在源站配置证书。${NC}"
    echo "  - 建议两种方式："
    echo "      1）Cloudflare Origin Cert：在 CF 后台生成 Origin 证书 + 私钥，"
    echo "         上传到本机固定路径（例如 /usr/local/lsws/conf/certs/${WP_SLUG}.crt/.key），"
    echo "         然后在 OLS vhost 中开启 HTTPS 并指定证书。"
    echo "      2）Let’s Encrypt：使用 acme.sh 或 certbot 申请证书，"
    echo "         同样放到 /usr/local/lsws/conf/certs/ 下，并在 OLS 中引用。"
    echo "  - 未来 hz-oneclick 会提供独立模块（例如 setup-ols-ssl.sh）自动化这部分。"
  fi

  echo
  echo -e "${GREEN}[完成] OLS + WordPress 标准安装（v0.4）执行完毕。${NC}"
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
  echo "  OLS + WordPress 标准安装模块（v0.4）"
  echo "===================================================="

  header_step 1 8 "环境检查（root / 系统版本 / 架构 / 内存）"
  detect_env
  pause

  install_ols
  collect_site_info
  collect_db_info
  prepare_docroot
  install_wordpress
  generate_wp_config_and_ols
  show_ip_and_ssl_hint
}

main "$@"
