#!/usr/bin/env bash
# install-ols-wp-standard.sh
# v0.2 - OLS + WordPress 标准安装（基础版：HTTP 80，无自动建库）

set -u

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

detect_env() {
  OS_NAME=$(lsb_release -si 2>/dev/null || echo "unknown")
  OS_VER=$(lsb_release -sr 2>/dev/null || echo "unknown")
  ARCH=$(uname -m)
  echo -e "${GREEN}[INFO] 检测到系统：${OS_NAME} ${OS_VER}${NC}"
  echo -e "${GREEN}[INFO] CPU 架构：${ARCH}${NC}"
}

install_ols() {
  header_step 2 7 "检查 / 安装 OpenLiteSpeed"

  # 检查 OLS 是否存在
  if command -v lswsctrl >/dev/null 2>&1 || [ -d /usr/local/lsws ]; then
    echo -e "${YELLOW}[WARN] 检测到系统中已经存在 OLS 相关文件，将尝试直接启用。${NC}"
  else
    echo -e "${YELLOW}[WARN] 未检测到 OpenLiteSpeed，将尝试安装官方 OLS。${NC}"
    read -rp "现在自动安装 OLS（会执行 apt 操作）？ [y/N，默认: y] " INSTALL_OLS
    INSTALL_OLS=${INSTALL_OLS:-y}
    if [[ "$INSTALL_OLS" =~ ^[Yy]$ ]]; then
      echo -e "${GREEN}[INFO] 开始安装 OLS（使用官方仓库）...${NC}"
      apt update -y
      # 保证必要工具存在
      apt install -y wget gnupg lsb-release
      # 官方脚本添加仓库
      wget -O - https://repo.litespeed.sh | bash
      apt update -y
      apt install -y openlitespeed
    else
      echo -e "${RED}[ERROR] 用户选择不安装 OLS，无法继续。${NC}"
      exit 1
    fi
  fi

  # 使用 systemd 管理 OLS
  if systemctl list-unit-files | grep -q "^lsws\.service"; then
    systemctl enable lsws >/dev/null 2>&1 || true
    systemctl restart lsws
  else
    # 兼容某些发行版 service 名不一样
    if systemctl list-unit-files | grep -q "^lshttpd\.service"; then
      systemctl enable lshttpd >/dev/null 2>&1 || true
      systemctl restart lshttpd
    else
      # 最后一招：直接用 lswsctrl
      if [ -x /usr/local/lsws/bin/lswsctrl ]; then
        /usr/local/lsws/bin/lswsctrl restart
      fi
    fi
  fi

  sleep 2

  # 简单检测 80 端口是否有进程监听（这里不强制失败，只提示）
  if ss -ltnp | grep -q ":80 "; then
    echo -e "${GREEN}[INFO] OLS 进程正在运行。${NC}"
  else
    echo -e "${YELLOW}[WARN] 未检测到 80 端口监听，请稍后手动检查 OLS 状态。${NC}"
  fi

  echo -e "${GREEN}[INFO] OLS 检查/安装步骤完成。${NC}"
  pause
}

collect_site_info() {
  header_step 3 7 "收集站点信息（域名 / slug / 路径）"

  # 域名
  while true; do
    read -rp "请输入站点域名（例如: example.com）: " WP_DOMAIN
    if [ -z "$WP_DOMAIN" ]; then
      echo -e "${YELLOW}[WARN] 域名不能为空，请重新输入。${NC}"
      continue
    fi
    break
  done

  # slug
  read -rp "请输入站点代号 slug（例如: ols，默认: 根据域名自动生成）: " WP_SLUG
  if [ -z "$WP_SLUG" ]; then
    WP_SLUG=$(echo "$WP_DOMAIN" | cut -d'.' -f1)
    [ -z "$WP_SLUG" ] && WP_SLUG="site"
  fi

  # docroot
  local default_docroot="/var/www/${WP_SLUG}/html"
  read -rp "WordPress 安装目录（默认: ${default_docroot}）: " WP_DOCROOT
  WP_DOCROOT=${WP_DOCROOT:-$default_docroot}

  echo
  echo -e "${GREEN}[INFO] 将使用以下站点配置：${NC}"
  echo "  域名: ${WP_DOMAIN}"
  echo "  slug: ${WP_SLUG}"
  echo "  docroot: ${WP_DOCROOT}"
  pause
}

collect_db_info() {
  header_step 4 7 "收集数据库信息（请确保数据库已在目标实例中创建好）"

  echo -e "${YELLOW}[提示] 本模块不会自动创建数据库 / 用户，只负责把信息写入 wp-config.php。${NC}"
  echo

  # DB Host
  while true; do
    read -rp "DB Host（例如: 127.0.0.1 或 tailscale 内网 IP，默认: 127.0.0.1）: " DB_HOST
    DB_HOST=${DB_HOST:-127.0.0.1}
    [ -n "$DB_HOST" ] && break
    echo -e "${YELLOW}[WARN] DB Host 不能为空。${NC}"
  done

  # DB Port
  while true; do
    read -rp "DB 端口（默认: 3306）: " DB_PORT
    DB_PORT=${DB_PORT:-3306}
    [ -n "$DB_PORT" ] && break
    echo -e "${YELLOW}[WARN] DB 端口不能为空。${NC}"
  done

  # DB Name
  while true; do
    read -rp "DB 名称（例如: ${WP_SLUG}_wp）: " DB_NAME
    [ -n "$DB_NAME" ] && break
    echo -e "${YELLOW}[WARN] DB 名称不能为空。${NC}"
  done

  # DB 用户
  while true; do
    read -rp "DB 用户名（例如: ${WP_SLUG}_user）: " DB_USER
    [ -n "$DB_USER" ] && break
    echo -e "${YELLOW}[WARN] DB 用户名不能为空。${NC}"
  done

  # DB 密码
  while true; do
    read -rsp "DB 密码（输入时不显示）: " DB_PASSWORD
    echo
    [ -n "$DB_PASSWORD" ] && break
    echo -e "${YELLOW}[WARN] DB 密码不能为空。${NC}"
  done

  # 表前缀
  read -rp "表前缀（默认: wp_）: " TABLE_PREFIX
  TABLE_PREFIX=${TABLE_PREFIX:-wp_}

  echo
  echo -e "${GREEN}[INFO] DB 配置信息如下（仅用于生成 wp-config.php）：${NC}"
  echo "  DB_HOST: ${DB_HOST}"
  echo "  DB_PORT: ${DB_PORT}"
  echo "  DB_NAME: ${DB_NAME}"
  echo "  DB_USER: ${DB_USER}"
  echo "  表前缀: ${TABLE_PREFIX}"

  echo
  echo -e "${YELLOW}[提示] 请确认目标 DB 实例已创建对应数据库和用户，并已授予权限。${NC}"
  pause
}

prepare_docroot() {
  header_step 5 7 "准备站点目录与权限"

  echo -e "${GREEN}[INFO] 创建站点目录: ${WP_DOCROOT}${NC}"
  mkdir -p "${WP_DOCROOT}"
  # 创建上层目录（用于未来日志等）
  mkdir -p "/var/www/${WP_SLUG}"

  # 默认用 nobody:nogroup，与你现在 OLS 习惯一致，如有需要可后续调整
  chown -R nobody:nogroup "/var/www/${WP_SLUG}"
  find "/var/www/${WP_SLUG}" -type d -exec chmod 755 {} \;
  find "/var/www/${WP_SLUG}" -type f -exec chmod 644 {} \;

  echo -e "${GREEN}[INFO] 站点目录准备完成。${NC}"
  pause
}

install_wordpress() {
  header_step 6 7 "下载并安装 WordPress"

  if [ -d "${WP_DOCROOT}/wp-admin" ] || [ -f "${WP_DOCROOT}/wp-config.php" ]; then
    echo -e "${YELLOW}[WARN] 检测到 ${WP_DOCROOT} 目录中已经存在 WordPress 文件。${NC}"
    read -rp "是否跳过下载/解压 WordPress，只生成 wp-config.php？ [y/N，默认: n] " SKIP_WP_DL
    SKIP_WP_DL=${SKIP_WP_DL:-n}
    if [[ "$SKIP_WP_DL" =~ ^[Yy]$ ]]; then
      echo -e "${YELLOW}[WARN] 将跳过 WordPress 下载与覆盖步骤。${NC}"
      pause
      return
    fi
  fi

  tmpdir=$(mktemp -d)
  cd "$tmpdir" || exit 1

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

generate_wp_config() {
  header_step 7 7 "生成 wp-config.php 与 OLS 虚拟主机配置"

  # 生成 wp-config.php（如不存在）
  if [ ! -f "${WP_DOCROOT}/wp-config.php" ]; then
    echo -e "${GREEN}[INFO] 生成新的 wp-config.php...${NC}"

    # 获取盐值
    WP_SALTS=$(curl -fsSL https://api.wordpress.org/secret-key/1.1/salt/ || echo "")

    cat > "${WP_DOCROOT}/wp-config.php" <<EOF
<?php
define( 'DB_NAME', '${DB_NAME}' );
define( 'DB_USER', '${DB_USER}' );
define( 'DB_PASSWORD', '${DB_PASSWORD}' );
define( 'DB_HOST', '${DB_HOST}:${DB_PORT}' );
define( 'DB_CHARSET', 'utf8mb4' );
define( 'DB_COLLATE', '' );

${WP_SALTS}

\$table_prefix = '${TABLE_PREFIX}';

define( 'WP_DEBUG', false );

if ( ! defined( 'ABSPATH' ) ) {
  define( 'ABSPATH', __DIR__ . '/' );
}

require_once ABSPATH . 'wp-settings.php';
EOF

    chown nobody:nogroup "${WP_DOCROOT}/wp-config.php"
    chmod 640 "${WP_DOCROOT}/wp-config.php"
  else
    echo -e "${YELLOW}[WARN] 检测到已有 wp-config.php，将不会覆盖。${NC}"
  fi

  # 生成 OLS vhost 配置（基础版，仅 HTTP 80）
  echo
  echo -e "${GREEN}[INFO] 开始为该站点创建 OLS 虚拟主机配置...${NC}"

  local lsws_conf_root="/usr/local/lsws/conf"
  local vhost_dir="${lsws_conf_root}/vhosts/${WP_SLUG}"
  mkdir -p "${vhost_dir}"

  local vhconf="${vhost_dir}/vhconf.conf"
  cat > "${vhconf}" <<EOF
docRoot                  ${WP_DOCROOT}
vhRoot                   ${vhost_dir}
configFile               \$SERVER_ROOT/conf/vhosts/${WP_SLUG}/vhconf.conf
allowSymbolicLink        1

errorlog \$SERVER_ROOT/logs/${WP_SLUG}_error.log {
  useServer               0
  logLevel                WARN
  rollingSize             10M
  keepDays                30
}

accesslog \$SERVER_ROOT/logs/${WP_SLUG}_access.log {
  useServer               0
  rollingSize             10M
  keepDays                30
  compressArchive         1
}

index  {
  useServer               0
  indexFiles              index.php, index.html
}

context / {
  type                    NULL
  location                ${WP_DOCROOT}
  allowBrowse             1
}

phpIniOverride  {
}
EOF

  # 将 vhost 注册到 httpd_config.conf 中
  local httpd_conf="${lsws_conf_root}/httpd_config.conf"

  if ! grep -q "virtualHost ${WP_SLUG}" "${httpd_conf}"; then
    cat >> "${httpd_conf}" <<EOF

virtualHost ${WP_SLUG} {
  vhRoot                  ${vhost_dir}
  configFile              conf/vhosts/${WP_SLUG}/vhconf.conf
}
EOF
  fi

  # 绑定到 80 端口 listener（这里假设默认 listener 名为 Default 或 listenerName 未改）
  if ! grep -q "listener wordpress80" "${httpd_conf}"; then
    cat >> "${httpd_conf}" <<EOF

listener wordpress80 {
  address                 *:80
  secure                  0
}
EOF
  fi

  # 为 listener wordpress80 添加 vhost 映射
  if ! grep -q "wordpress80.*${WP_SLUG}" "${httpd_conf}"; then
    cat >> "${httpd_conf}" <<EOF

listener wordpress80 {
  map                     ${WP_SLUG} ${WP_DOMAIN}
}
EOF
  fi

  echo
  echo -e "${GREEN}[INFO] 重启 OLS 以应用新配置...${NC}"
  if systemctl list-unit-files | grep -q "^lsws\.service"; then
    systemctl restart lsws
  elif systemctl list-unit-files | grep -q "^lshttpd\.service"; then
    systemctl restart lshttpd
  else
    if [ -x /usr/local/lsws/bin/lswsctrl ]; then
      /usr/local/lsws/bin/lswsctrl restart
    fi
  fi

  echo
  echo -e "${GREEN}[INFO] 所有步骤完成。请在浏览器访问 http://${WP_DOMAIN} 完成 WordPress 安装向导。${NC}"
  pause
}

main() {
  require_root

  echo "===================================================="
  echo "  OLS + WordPress 标准安装模块（v0.2）"
  echo "  - 仅处理 HTTP 80"
  echo "  - 不自动创建数据库/用户，只生成 wp-config.php 和 vhost"
  echo "===================================================="

  header_step 1 7 "环境检查（root / 系统版本 / 架构）"
  detect_env
  pause

  install_ols
  collect_site_info
  collect_db_info
  prepare_docroot
  install_wordpress
  generate_wp_config
}

main "$@"
