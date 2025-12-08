#!/usr/bin/env bash
# install-ols-wp-standard.sh
# v0.6 - OLS + WordPress 标准安装（支持 Cloudflare Origin / Let's Encrypt SSL）
#
# 版本说明：
# - v0.6
#   * 修正 vhost/vhRoot/docRoot 配置，避免默认 404 页面
#   * 新增内存检测：<4G 时提示优先使用外部 DB/Redis 或改用 LNMP
#   * 新增 Step 8：SSL/HTTPS 三选一（不配 / Cloudflare Origin / Let's Encrypt）
#   * 安装完成后输出 IPv4/IPv6，方便去 DNS 服务商添加 A/AAAA 记录
#   * 所有配置不硬编码真实域名/IP，适合作为公共脚本分发

set -u

GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
BLUE="\033[34m"
NC="\033[0m"

TOTAL_STEPS=8

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

detect_env_and_memory() {
  header_step 1 "${TOTAL_STEPS}" "环境检查（root / 系统版本 / 架构 / 内存）"

  OS_NAME=$(lsb_release -si 2>/dev/null || echo "unknown")
  OS_VER=$(lsb_release -sr 2>/dev/null || echo "unknown")
  ARCH=$(uname -m)
  echo -e "${GREEN}[INFO] 系统：${OS_NAME} ${OS_VER}${NC}"
  echo -e "${GREEN}[INFO] CPU 架构：${ARCH}${NC}"

  local mem_kb
  mem_kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
  if [ "$mem_kb" -gt 0 ]; then
    local mem_gb
    mem_gb=$((mem_kb / 1024 / 1024))
    echo -e "${GREEN}[INFO] 物理内存约：${mem_gb} GB${NC}"
  fi

  # 内存 < 4G 时给出选项
  if [ "$mem_kb" -gt 0 ] && [ "$mem_kb" -lt 4000000 ]; then
    echo
    echo -e "${YELLOW}[WARN] 当前机器内存 < 4G。${NC}"
    echo -e "${YELLOW}[WARN] 建议：数据库 / Redis 放在其他高配机器，本机只跑 OLS + WordPress 前端，或者使用 LNMP 方案。${NC}"
    echo
    echo "如何继续？"
    echo "  1) 仍然继续当前 OLS + WordPress 前端安装（请自行保证 DB/Redis 在其他高配机器）"
    echo "  2) 改为 LNMP 安装（交给 LNMP 模块处理）"
    echo "  3) 返回上一层菜单（例如 hz.sh 主菜单）"
    echo "  4) 直接退出本脚本"
    read -rp "请选择 [1-4，默认: 1]: " LOW_MEM_CHOICE
    LOW_MEM_CHOICE=${LOW_MEM_CHOICE:-1}

    case "$LOW_MEM_CHOICE" in
      1)
        echo -e "${GREEN}[INFO] 继续执行 OLS + WordPress 安装。${NC}"
        ;;
      2)
        echo -e "${YELLOW}[INFO] 尝试切换到 LNMP 安装模块...${NC}"
        # 预留：未来 LNMP 模块路径（示例）
        if [ -x "/root/hz-oneclick/modules/wp/install-lnmp-wp-standard.sh" ]; then
          /root/hz-oneclick/modules/wp/install-lnmp-wp-standard.sh
        else
          echo -e "${RED}[WARN] 未找到 LNMP 安装脚本（/root/hz-oneclick/modules/wp/install-lnmp-wp-standard.sh）。${NC}"
          echo -e "${RED}[WARN] 请稍后在 hz-oneclick 主菜单中选择 LNMP 安装。当前退出本模块。${NC}"
        fi
        exit 0
        ;;
      3)
        echo -e "${GREEN}[INFO] 返回主菜单。${NC}"
        exit 0
        ;;
      4)
        echo -e "${GREEN}[INFO] 用户选择退出。${NC}"
        exit 0
        ;;
      *)
        echo -e "${YELLOW}[WARN] 无效输入，默认继续当前模块。${NC}"
        ;;
    esac
  fi

  pause
}

install_ols() {
  header_step 2 "${TOTAL_STEPS}" "检查 / 安装 OpenLiteSpeed"

  if command -v lswsctrl >/dev/null 2>&1 || [ -d /usr/local/lsws ]; then
    echo -e "${YELLOW}[WARN] 检测到系统中已有 OLS，将在现有基础上配置站点。${NC}"
  else
    echo -e "${YELLOW}[WARN] 未检测到 OpenLiteSpeed，将使用官方仓库自动安装。${NC}"
    read -rp "现在自动安装 OLS（会执行 apt 操作）？ [y/N，默认: y] " INSTALL_OLS
    INSTALL_OLS=${INSTALL_OLS:-y}
    if [[ "$INSTALL_OLS" =~ ^[Yy]$ ]]; then
      echo -e "${GREEN}[INFO] 开始安装 OLS（使用官方 repo.litespeed.sh 仓库）...${NC}"
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

  # 尝试用 systemd 启动
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
    echo -e "${RED}[ERROR] 无法确认 OLS 进程是否正常运行，请手动检查（systemctl status lsws / lshttpd）。${NC}"
  fi

  pause
}

collect_site_info() {
  header_step 3 "${TOTAL_STEPS}" "收集站点信息（域名 / slug / 路径）"

  while true; do
    read -rp "请输入站点主域名（例如: site.example.com）: " WP_DOMAIN
    if [ -n "$WP_DOMAIN" ]; then
      break
    fi
    echo -e "${YELLOW}[WARN] 域名不能为空，请重新输入。${NC}"
  done

  read -rp "请输入站点代号 slug（例如: site，默认: 从域名取第一段）: " WP_SLUG
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

collect_db_info() {
  header_step 4 "${TOTAL_STEPS}" "收集数据库信息（外部实例 / Docker 实例均可）"

  echo -e "${YELLOW}[提示] 本脚本不会自动创建数据库，只会把你输入的信息写入 wp-config.php。${NC}"
  echo -e "${YELLOW}[提示] 请提前在目标 DB 实例中创建数据库 / 用户并授予权限（推荐一站一库一用户）。${NC}"
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
  echo -e "${GREEN}[INFO] DB 配置信息如下：${NC}"
  echo "  DB_HOST: ${DB_HOST}"
  echo "  DB_PORT: ${DB_PORT}"
  echo "  DB_NAME: ${DB_NAME}"
  echo "  DB_USER: ${DB_USER}"
  echo "  表前缀: ${TABLE_PREFIX}"
  echo -e "${YELLOW}[提示] 请确认目标 DB 已创建对应数据库和用户，并已授予权限。${NC}"

  pause
}

prepare_docroot() {
  header_step 5 "${TOTAL_STEPS}" "准备站点目录与权限"

  echo -e "${GREEN}[INFO] 创建站点目录: ${WP_DOCROOT}${NC}"
  mkdir -p "${WP_DOCROOT}"
  mkdir -p "/var/www/${WP_SLUG}"

  # 默认使用 nobody:nogroup，与 OLS 默认一致
  chown -R nobody:nogroup "/var/www/${WP_SLUG}"
  find "/var/www/${WP_SLUG}" -type d -exec chmod 755 {} \;
  find "/var/www/${WP_SLUG}" -type f -exec chmod 644 {} \;

  echo -e "${GREEN}[INFO] 站点目录准备完成。${NC}"
  pause
}

install_wordpress() {
  header_step 6 "${TOTAL_STEPS}" "下载并安装 WordPress"

  if [ -f "${WP_DOCROOT}/index.php" ] || [ -f "${WP_DOCROOT}/wp-config.php" ]; then
    echo -e "${YELLOW}[WARN] 检测到 ${WP_DOCROOT} 已存在 WordPress 文件，将不会重复覆盖。${NC}"
    pause
    return
  fi

  tmpdir=$(mktemp -d)
  cd "$tmpdir" || exit 1

  echo -e "${GREEN}[INFO] 正在从官方获取最新 WordPress ...${NC}"
  curl -fsSL -o wordpress.tar.gz https://wordpress.org/latest.tar.gz
  tar xf wordpress.tar.gz

  echo -e "${GREEN}[INFO] 拷贝 WordPress 文件到 ${WP_DOCROOT} ...${NC}"
  cp -R wordpress/* "${WP_DOCROOT}/"

  cd /
  rm -rf "$tmpdir"

  chown -R nobody:nogroup "/var/www/${WP_SLUG}"
  find "/var/www/${WP_SLUG}" -type d -exec chmod 755 {} \;
  find "/var/www/${WP_SLUG}" -type f -exec chmod 644 {} \;

  echo -e "${GREEN}[INFO] WordPress 核心文件安装完成。${NC}"
  pause
}

generate_wp_config_and_vhost() {
  header_step 7 "${TOTAL_STEPS}" "生成 wp-config.php 与 OLS 虚拟主机配置"

  # 1) 生成 / 更新 wp-config.php
  if [ ! -f "${WP_DOCROOT}/wp-config.php" ]; then
    echo -e "${GREEN}[INFO] 生成新的 wp-config.php ...${NC}"

    WP_SALTS=$(curl -fsSL https://api.wordpress.org/secret-key/1.1/salt/ || echo "")

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
    echo -e "${YELLOW}[WARN] 已存在 ${WP_DOCROOT}/wp-config.php，请稍后手动确认其中 DB 配置是否正确。${NC}"
  fi

  # 2) 生成 / 更新 OLS vhost 配置
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

  # 删除旧的 virtualhost ${WP_SLUG} 段（避免重复）
  if [ -f "$httpd_conf" ]; then
    sed -i "/virtualhost[[:space:]]\+${WP_SLUG}[[:space:]]*{/,/}/d" "$httpd_conf"
  fi

  cat >> "$httpd_conf" <<EOF

virtualhost ${WP_SLUG} {
  vhRoot                  /var/www/${WP_SLUG}
  configFile              conf/vhosts/${WP_SLUG}/vhconf.conf
  allowSymbolLink         1
  enableScript            1
  restrained              1
}
EOF

  # HTTP listener：如不存在则创建；存在则提示检查 map
  if ! grep -q "listener HTTP" "$httpd_conf"; then
    cat >> "$httpd_conf" <<EOF

listener HTTP {
  address                 *:80
  secure                  0
  map                     ${WP_SLUG} ${WP_DOMAIN}
}
EOF
  else
    if ! grep -q "map[[:space:]]\+${WP_SLUG}[[:space:]]\+${WP_DOMAIN}" "$httpd_conf"; then
      echo -e "${YELLOW}[WARN] 已存在 listener HTTP，请手动确认其中包含：map ${WP_SLUG} ${WP_DOMAIN}${NC}"
    fi
  fi

  # 重启 OLS 应用新配置（仅 HTTP）
  echo -e "${GREEN}[INFO] 重启 OLS 以应用 HTTP 配置...${NC}"
  if systemctl list-unit-files | grep -q "^lsws\.service"; then
    systemctl restart lsws
  elif systemctl list-unit-files | grep -q "^lshttpd\.service"; then
    systemctl restart lshttpd
  elif [ -x /usr/local/lsws/bin/lswsctrl ]; then
    /usr/local/lsws/bin/lswsctrl restart
  fi
}

configure_https_listener() {
  local KEY_FILE="$1"
  local CERT_FILE="$2"

  local lsws_conf_root="/usr/local/lsws/conf"
  local httpd_conf="${lsws_conf_root}/httpd_config.conf"

  if ! grep -q "listener SSL-443" "$httpd_conf"; then
    cat >> "$httpd_conf" <<EOF

listener SSL-443 {
  address                 *:443
  secure                  1
  keyFile                 ${KEY_FILE}
  certFile                ${CERT_FILE}
  map                     ${WP_SLUG} ${WP_DOMAIN}
}
EOF
  else
    echo -e "${YELLOW}[WARN] 检测到已经存在 listener SSL-443，请手动确认 keyFile/certFile 与 map 是否正确。${NC}"
  fi

  echo -e "${GREEN}[INFO] 重启 OLS 以应用 HTTPS 配置...${NC}"
  if systemctl list-unit-files | grep -q "^lsws\.service"; then
    systemctl restart lsws
  elif systemctl list-unit-files | grep -q "^lshttpd\.service"; then
    systemctl restart lshttpd
  elif [ -x /usr/local/lsws/bin/lswsctrl ]; then
    /usr/local/lsws/bin/lswsctrl restart
  fi
}

setup_ssl_cloudflare() {
  echo
  echo -e "${BLUE}[INFO] 选项 2：使用 Cloudflare Origin Certificate。${NC}"
  echo -e "${YELLOW}[提示] 请先在 Cloudflare 面板为该域名创建 Origin Certificate，然后按提示粘贴证书和私钥。${NC}"
  echo

  local lsws_conf_root="/usr/local/lsws/conf"
  local cert_dir="${lsws_conf_root}/cert"
  mkdir -p "$cert_dir"

  local sanitized
  sanitized=$(echo "$WP_DOMAIN" | tr '*.' '_' | tr -c 'A-Za-z0-9_' '_')
  local cert_file="${cert_dir}/${sanitized}.crt"
  local key_file="${cert_dir}/${sanitized}.key"

  echo -e "${GREEN}[INFO] 将保存到：${cert_file} 和 ${key_file}${NC}"
  echo

  # 证书
  echo "请粘贴 Cloudflare Origin Certificate 内容，粘贴结束后在单独一行输入 END："
  : > "$cert_file"
  while IFS= read -r line; do
    [ "$line" = "END" ] && break
    echo "$line" >> "$cert_file"
  done

  # 私钥
  echo
  echo "请粘贴 Cloudflare Origin Private Key 内容，粘贴结束后在单独一行输入 END："
  : > "$key_file"
  while IFS= read -r line; do
    [ "$line" = "END" ] && break
    echo "$line" >> "$key_file"
  done

  chmod 600 "$cert_file" "$key_file"

  configure_https_listener "$key_file" "$cert_file"

  echo -e "${GREEN}[INFO] Cloudflare Origin 证书已写入并配置完成。${NC}"
}

setup_ssl_letsencrypt() {
  echo
  echo -e "${BLUE}[INFO] 选项 3：使用 Let's Encrypt 自动申请证书。${NC}"
  echo -e "${YELLOW}[重要] 申请前请确保：${NC}"
  echo -e "${YELLOW}  - DNS 中 ${WP_DOMAIN} 的 A/AAAA 记录直指本机，且暂时为“DNS only”（Cloudflare 灰云）；${NC}"
  echo -e "${YELLOW}  - 80 端口能从公网访问本机；${NC}"
  echo

  read -rp "请输入用于 Let's Encrypt 注册的邮箱（必须是可用邮箱）: " LE_EMAIL
  if [ -z "$LE_EMAIL" ]; then
    echo -e "${RED}[ERROR] 邮箱不能为空，无法自动申请证书。${NC}"
    return
  fi

  apt update -y
  apt install -y certbot

  echo -e "${GREEN}[INFO] 使用 webroot 模式申请证书...${NC}"
  if certbot certonly --webroot -w "${WP_DOCROOT}" -d "${WP_DOMAIN}" --email "${LE_EMAIL}" --agree-tos --non-interactive --quiet; then
    local cert_path="/etc/letsencrypt/live/${WP_DOMAIN}/fullchain.pem"
    local key_path="/etc/letsencrypt/live/${WP_DOMAIN}/privkey.pem"
    if [ -f "$cert_path" ] && [ -f "$key_path" ]; then
      configure_https_listener "$key_path" "$cert_path"
      echo -e "${GREEN}[INFO] Let's Encrypt 证书申请并配置成功。${NC}"
      echo -e "${YELLOW}[提示] certbot 会自动续期，你可以在续期 hook 中添加“systemctl reload lsws”。${NC}"
    else
      echo -e "${RED}[ERROR] 未找到预期的证书文件：${cert_path} / ${key_path}${NC}"
    fi
  else
    echo -e "${RED}[ERROR] certbot 申请证书失败，请检查输出信息。${NC}"
  fi
}

setup_ssl_menu() {
  header_step 8 "${TOTAL_STEPS}" "处理 SSL/HTTPS（可选）"

  echo "你希望如何处理本机 HTTPS？"
  echo "  1) 暂不配置，仅保持 HTTP 80（可配合 Cloudflare Flexible / Full 使用）"
  echo "  2) 使用 Cloudflare Origin Certificate（粘贴证书和私钥，本机直接跑 443）"
  echo "  3) 使用 Let's Encrypt 自动申请证书（certbot + webroot）"
  read -rp "请选择 [1-3，默认: 1]: " SSL_CHOICE
  SSL_CHOICE=${SSL_CHOICE:-1}

  case "$SSL_CHOICE" in
    1)
      echo -e "${GREEN}[INFO] 保持仅 HTTP 80，HTTPS 暂不自动配置。${NC}"
      ;;
    2)
      setup_ssl_cloudflare
      ;;
    3)
      setup_ssl_letsencrypt
      ;;
    *)
      echo -e "${YELLOW}[WARN] 无效选择，默认保持仅 HTTP 80。${NC}"
      ;;
  esac
}

print_final_summary() {
  # 检测 IP
  local IPV4 IPV6
  IPV4=$(ip -4 addr show scope global 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -n1)
  IPV6=$(ip -6 addr show scope global 2>/dev/null | awk '/inet6 /{print $2}' | cut -d/ -f1 | head -n1)

  echo
  echo -e "${GREEN}[完成] OLS + WordPress 标准安装完成（v0.6）。${NC}"
  echo "====================== 总结 ======================"
  echo "  域名：        ${WP_DOMAIN}"
  echo "  slug：        ${WP_SLUG}"
  echo "  安装路径：    ${WP_DOCROOT}"
  echo "  DB_HOST：     ${DB_HOST}"
  echo "  DB_PORT：     ${DB_PORT}"
  echo "  DB_NAME：     ${DB_NAME}"
  echo "  DB_USER：     ${DB_USER}"
  echo
  echo "  服务器 IPv4： ${IPV4:-未检测到公网 IPv4（可能仅内网或暂未配置）}"
  echo "  服务器 IPv6： ${IPV6:-未检测到公网 IPv6（可能未启用 IPv6）}"
  echo "=================================================="
  echo -e "${YELLOW}[下一步建议]：${NC}"
  echo "  1) 在 DNS 服务商（例如 Cloudflare）中，把 ${WP_DOMAIN} 的 A/AAAA 记录指向上面的 IP；"
  echo "  2) 如使用 Cloudflare 且已配置 HTTPS，请根据本机是否启用 443，选择合适的 SSL 模式："
  echo "     - 仅 HTTP 80：可先用 Flexible / Full；"
  echo "     - 已在本机配置证书并开启 443：可用 Full (strict)。"
  echo
  echo "完成 DNS 生效后，可以在浏览器测试访问："
  echo "  http://${WP_DOMAIN}/"
  echo
  echo "本模块执行完毕。你可以："
  echo "  - 按回车返回（如果是从 hz.sh 调用，将回到主菜单）；"
  echo "  - 或按 Ctrl+C 直接退出终端。"
  read -rp "" _
}

main() {
  require_root

  echo
  echo "===================================================="
  echo "  OLS + WordPress 标准安装模块（v0.6）"
  echo "===================================================="

  detect_env_and_memory
  install_ols
  collect_site_info
  collect_db_info
  prepare_docroot
  install_wordpress
  generate_wp_config_and_vhost
  setup_ssl_menu
  print_final_summary
}

main "$@"
