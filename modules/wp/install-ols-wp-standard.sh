#!/usr/bin/env bash
#
# install-ols-wp-standard.sh
# 版本：v0.1
# 功能：
#   Step 1/7 环境检查
#   Step 2/7 检查 / 安装 OpenLiteSpeed
#   Step 3/7 收集站点基本信息（slug / 域名 / 路径）
#   Step 4/7 收集数据库 / Redis 配置（含 Docker 检测）
#   Step 5/7 创建目录与权限
#   Step 6/7 安装 WordPress 并生成 wp-config.php
#   Step 7/7 创建 OLS vhost 并给出总结信息
#

set -euo pipefail

SCRIPT_VERSION="v0.1"

# ========= 通用输出函数 =========
cecho() {
  # $1: 颜色码，$2: 文本
  local color="$1"
  shift
  printf "\033[%sm%s\033[0m\n" "$color" "$*"
}

info()  { cecho "32" "[INFO] $*"; }
warn()  { cecho "33" "[WARN] $*"; }
error() { cecho "31" "[ERROR] $*"; }

pause() {
  read -r -p "按回车键继续..." _
}

print_step() {
  local n="$1"
  local title="$2"
  cecho "36" ""
  cecho "36" "==================== Step ${n}/7 ===================="
  cecho "36" "${title}"
  cecho "36" "===================================================="
}

# ========= 交互输入小工具 =========
ask_with_default() {
  local prompt="$1"
  local default="${2:-}"
  local var
  if [[ -n "$default" ]]; then
    read -r -p "${prompt} [默认: ${default}] " var || true
    if [[ -z "$var" ]]; then
      var="$default"
    fi
  else
    read -r -p "${prompt} " var || true
  fi
  echo "$var"
}

ask_secret() {
  local prompt="$1"
  local var
  read -r -s -p "${prompt} (输入内容不会回显): " var || true
  echo
  echo "$var"
}

confirm_yn() {
  local prompt="$1"
  local default="${2:-y}"
  local var
  read -r -p "${prompt} [y/n，默认: ${default}] " var || true
  if [[ -z "$var" ]]; then
    var="$default"
  fi
  if [[ "$var" == "y" || "$var" == "Y" ]]; then
    return 0
  fi
  return 1
}

# ========= Step 1/7 环境检查 =========
step1_env_check() {
  print_step 1 "环境检查（root / 系统版本 / 架构）"

  if [[ "$(id -u)" -ne 0 ]]; then
    error "请使用 root 身份运行本脚本（sudo -i 后再执行）。"
    exit 1
  fi

  local os=""
  local version_id=""
  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    os="$ID"
    version_id="$VERSION_ID"
  fi

  info "检测到系统：${os} ${version_id}"
  info "CPU 架构：$(uname -m)"

  if [[ "$os" != "ubuntu" ]]; then
    warn "本脚本目前只针对 Ubuntu 22.04 / 24.04 做了测试，其他系统请谨慎使用。"
    if ! confirm_yn "仍然继续执行吗？" "n"; then
      info "用户取消。"
      exit 0
    fi
  fi

  if [[ "$version_id" != "22.04" && "$version_id" != "24.04" ]]; then
    warn "建议使用 Ubuntu 22.04 或 24.04，当前为 ${version_id}。"
    if ! confirm_yn "仍然继续执行吗？" "n"; then
      info "用户取消。"
      exit 0
    fi
  fi

  info "环境检查完成。"
  pause
}

# ========= Step 2/7 检查 / 安装 OLS =========
ensure_ols_installed() {
  if command -v lswsctrl >/dev/null 2>&1 || systemctl list-unit-files | grep -q 'lsws\.service'; then
    info "检测到已安装 OpenLiteSpeed。"
    return 0
  fi

  warn "未检测到 OpenLiteSpeed，将尝试安装官方 OLS。"
  if ! confirm_yn "现在自动安装 OLS（会执行 apt 操作）？" "y"; then
    error "未安装 OLS，无法继续。"
    exit 1
  fi

  info "开始安装 OLS（使用官方仓库）..."
  apt update -y
  apt install -y wget gnupg lsb-release

  wget -O - https://repo.litespeed.sh | bash
  apt update -y
  apt install -y openlitespeed

  info "OLS 安装完成。"
}

step2_ols() {
  print_step 2 "检查 / 安装 OpenLiteSpeed"

  ensure_ols_installed

  info "尝试启动并设置 OLS 开机自启..."
  if systemctl list-unit-files | grep -q 'lsws\.service'; then
    systemctl enable lsws || true
    systemctl restart lsws || true
  else
    # 旧版可能使用 lswsctrl
    lswsctrl restart || true
  fi

  info "OLS 检查/安装步骤完成。"
  pause
}

# ========= Step 3/7 收集站点基本信息 =========
step3_collect_site_info() {
  print_step 3 "收集站点基本信息（slug / 域名 / 路径）"

  SITE_SLUG=$(ask_with_default "请输入站点代号（slug），用于路径和配置命名" "mysite")
  SITE_SLUG="${SITE_SLUG// /-}"  # 简单把空格换成 -

  info "站点类型："
  echo "  1) 主站（使用 main-db / main-redis 模式）"
  echo "  2) 租户 / demo 站（使用 tenant-db / tenant-redis 模式）"
  local type_choice
  type_choice=$(ask_with_default "请选择站点类型 [1/2]" "1")
  case "$type_choice" in
    1) SITE_TYPE="main" ;;
    2) SITE_TYPE="tenant" ;;
    *) SITE_TYPE="main" ;;
  esac

  SITE_DOMAIN=$(ask_with_default "请输入主域名（示例：example.com）" "example.com")

  SITE_DOCROOT_DEFAULT="/var/www/${SITE_SLUG}/html"
  SITE_DOCROOT=$(ask_with_default "请输入 WordPress 安装根目录" "$SITE_DOCROOT_DEFAULT")

  SITE_LOGDIR_DEFAULT="/var/www/${SITE_SLUG}/logs"
  USE_LOGDIR="y"
  if confirm_yn "是否为该站点单独创建日志目录？" "y"; then
    USE_LOGDIR="y"
    SITE_LOGDIR="$SITE_LOGDIR_DEFAULT"
  else
    USE_LOGDIR="n"
    SITE_LOGDIR=""
  fi

  info "站点信息汇总："
  echo "  slug     : ${SITE_SLUG}"
  echo "  类型     : ${SITE_TYPE}"
  echo "  域名     : ${SITE_DOMAIN}"
  echo "  docroot  : ${SITE_DOCROOT}"
  echo "  logs dir : ${SITE_LOGDIR:-（不单独创建）}"

  if ! confirm_yn "上述信息是否正确？" "y"; then
    warn "用户选择重新输入站点信息。"
    step3_collect_site_info
    return
  fi

  pause
}

# ========= Step 4/7 收集 DB / Redis 信息（含 Docker 检测） =========
check_docker_status() {
  if command -v docker >/dev/null 2>&1; then
    info "检测到 docker 命令。"
    return 0
  fi
  return 1
}

install_docker_basic() {
  warn "未检测到 Docker，将尝试安装 Docker（官方推荐方式之一）。"
  if ! confirm_yn "现在自动安装 Docker（含 compose 插件）？" "y"; then
    warn "用户选择不安装 Docker。"
    return 1
  fi

  info "开始安装 Docker..."
  apt update -y
  apt install -y ca-certificates curl gnupg

  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg

  local codename
  codename=$(lsb_release -cs)
  echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
${codename} stable" > /etc/apt/sources.list.d/docker.list

  apt update -y
  apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  systemctl enable docker || true
  systemctl start docker || true

  info "Docker 安装完成。"
  return 0
}

step4_collect_db_redis() {
  print_step 4 "收集数据库 / Redis 配置（含 Docker 检测）"

  info "数据库实例类型："
  echo "  1) 本机 Docker（推荐）：MariaDB 运行在本机 Docker"
  echo "  2) 自定义：手动输入 DB host / port（本机已有实例或内网实例）"
  local db_mode_choice
  db_mode_choice=$(ask_with_default "请选择 DB 模式 [1/2]" "1")

  DB_MODE="docker"
  if [[ "$db_mode_choice" == "2" ]]; then
    DB_MODE="custom"
  fi

  if [[ "$DB_MODE" == "docker" ]]; then
    if ! check_docker_status; then
      warn "当前未检测到 Docker 环境。"
      if install_docker_basic; then
        info "Docker 环境已准备好。"
      else
        warn "仍未安装 Docker，将切换为“自定义 DB 模式”。"
        DB_MODE="custom"
      fi
    else
      info "Docker 已经可用。"
    fi
  fi

  if [[ "$DB_MODE" == "docker" ]]; then
    info "当前版本不会自动创建 MariaDB 容器，先默认认为 DB_HOST=127.0.0.1 / PORT=3306。"
    DB_HOST_DEFAULT="127.0.0.1"
    DB_PORT_DEFAULT="3306"
  else
    DB_HOST_DEFAULT="127.0.0.1"
    DB_PORT_DEFAULT="3306"
  fi

  DB_HOST=$(ask_with_default "请输入 DB 主机（DB_HOST）" "$DB_HOST_DEFAULT")
  DB_PORT=$(ask_with_default "请输入 DB 端口（DB_PORT）" "$DB_PORT_DEFAULT")
  DB_NAME=$(ask_with_default "请输入 DB 名称（DB_NAME）" "${SITE_SLUG}_wp")
  DB_USER=$(ask_with_default "请输入 DB 用户名（DB_USER）" "${SITE_SLUG}_user")
  DB_PASSWORD=$(ask_secret "请输入 DB 密码（DB_PASSWORD），留空则稍后手动修改 wp-config.php")

  USE_REDIS="y"
  if confirm_yn "是否启用 Redis？" "y"; then
    USE_REDIS="y"
    REDIS_HOST=$(ask_with_default "请输入 Redis 主机" "127.0.0.1")
    REDIS_PORT=$(ask_with_default "请输入 Redis 端口" "6379")
    local default_redis_db
    if [[ "$SITE_TYPE" == "tenant" ]]; then
      default_redis_db="2"
    else
      default_redis_db="1"
    fi
    REDIS_DB_INDEX=$(ask_with_default "请输入 Redis DB index" "$default_redis_db")
  else
    USE_REDIS="n"
    REDIS_HOST=""
    REDIS_PORT=""
    REDIS_DB_INDEX=""
  fi

  info "DB / Redis 信息汇总："
  echo "  DB_HOST   : ${DB_HOST}"
  echo "  DB_PORT   : ${DB_PORT}"
  echo "  DB_NAME   : ${DB_NAME}"
  echo "  DB_USER   : ${DB_USER}"
  echo "  DB_PASS   : ${DB_PASSWORD:+(已输入)}"
  echo "  Redis 启用: ${USE_REDIS}"
  if [[ "$USE_REDIS" == "y" ]]; then
    echo "  REDIS_HOST: ${REDIS_HOST}"
    echo "  REDIS_PORT: ${REDIS_PORT}"
    echo "  REDIS_DB  : ${REDIS_DB_INDEX}"
  fi

  if ! confirm_yn "上述信息是否正确？" "y"; then
    warn "用户选择重新输入 DB/Redis 信息。"
    step4_collect_db_redis
    return
  fi

  pause
}

# ========= Step 5/7 创建目录与权限 =========
step5_prepare_dirs() {
  print_step 5 "创建 WordPress 目录与权限"

  info "创建站点目录：${SITE_DOCROOT}"
  mkdir -p "${SITE_DOCROOT}"

  if [[ "$USE_LOGDIR" == "y" && -n "${SITE_LOGDIR}" ]]; then
    info "创建日志目录：${SITE_LOGDIR}"
    mkdir -p "${SITE_LOGDIR}"
  fi

  info "设置目录权限（nobody:nogroup + 755/644）..."
  mkdir -p "/var/www/${SITE_SLUG}"
  chown -R nobody:nogroup "/var/www/${SITE_SLUG}"
  find "/var/www/${SITE_SLUG}" -type d -exec chmod 755 {} \;
  find "/var/www/${SITE_SLUG}" -type f -exec chmod 644 {} \;

  info "目录与权限准备完成。"
  pause
}

# ========= Step 6/7 安装 WordPress 并生成 wp-config =========
step6_install_wp() {
  print_step 6 "安装 WordPress 并生成 wp-config.php"

  if [[ -f "${SITE_DOCROOT}/wp-config.php" ]]; then
    warn "检测到 ${SITE_DOCROOT}/wp-config.php 已存在，将跳过 WordPress 下载和配置生成。"
    pause
    return
  fi

  info "下载最新 WordPress 核心..."
  apt update -y
  apt install -y wget tar

  cd "${SITE_DOCROOT}"
  if [[ ! -f latest.tar.gz ]]; then
    wget https://wordpress.org/latest.tar.gz -O latest.tar.gz
  fi

  tar -xzf latest.tar.gz --strip-components=1
  rm -f latest.tar.gz

  info "生成 wp-config.php ..."
  cp wp-config-sample.php wp-config.php

  sed -i "s/database_name_here/${DB_NAME}/" wp-config.php
  sed -i "s/username_here/${DB_USER}/" wp-config.php
  sed -i "s/password_here/${DB_PASSWORD}/" wp-config.php
  sed -i "s/localhost/${DB_HOST}/" wp-config.php

  if [[ "$DB_PORT" != "3306" ]]; then
    sed -i "s/'${DB_HOST}'/'${DB_HOST}:${DB_PORT}'/" wp-config.php
  fi

  if [[ "$USE_REDIS" == "y" ]]; then
    cat <<EOF >> wp-config.php

/** Redis 连接设置（由缓存插件使用） */
if ( ! defined( 'WP_REDIS_HOST' ) ) {
    define( 'WP_REDIS_HOST', '${REDIS_HOST}' );
}
if ( ! defined( 'WP_REDIS_PORT' ) ) {
    define( 'WP_REDIS_PORT', ${REDIS_PORT} );
}
if ( ! defined( 'WP_REDIS_DATABASE' ) ) {
    define( 'WP_REDIS_DATABASE', ${REDIS_DB_INDEX} );
}
EOF
  fi

  cat <<'EOF' >> wp-config.php

/** 使用系统定时任务（systemd/cron）代替内置 wp-cron */
if ( ! defined( 'DISABLE_WP_CRON' ) ) {
    define( 'DISABLE_WP_CRON', true );
}
EOF

  info "WordPress 核心与 wp-config.php 已就绪。"
  pause
}

# ========= Step 7/7 创建 OLS vhost 并总结 =========
step7_config_ols_vhost() {
  print_step 7 "创建 OLS vhost 并总结信息"

  local lsws_conf_dir="/usr/local/lsws/conf"
  local vhost_conf_dir="${lsws_conf_dir}/vhosts"
  local vhost_conf_path="${vhost_conf_dir}/${SITE_SLUG}.conf"

  mkdir -p "${vhost_conf_dir}"

  info "生成 vhost 配置：${vhost_conf_path}"

  cat > "${vhost_conf_path}" <<EOF
virtualHost ${SITE_SLUG} {
  vhRoot                  ${SITE_DOCROOT}
  allowSymbolLink         1
  enableScript            1
  restrained              1
  setUIDMode              0

  errorlog ${SITE_LOGDIR:-/usr/local/lsws/logs}/${SITE_SLUG}_error.log {
    useServer              0
    logLevel               ERROR
    rollingSize            10M
  }

  accesslog ${SITE_LOGDIR:-/usr/local/lsws/logs}/${SITE_SLUG}_access.log {
    useServer              0
    logFormat              "%h %l %u %t \\"%r\\" %>s %b"
    rollingSize            10M
  }

  indexFiles              index.php,index.html

  phpIniOverride  {
  }
}
EOF

  warn "当前版本不会自动修改 OLS 主配置，请在 OLS 后台手动完成以下操作："
  echo "  1) 登录 OLS WebAdmin（通常为 7080 端口），添加虚拟主机 ${SITE_SLUG}"
  echo "  2) 绑定域名：${SITE_DOMAIN}"
  echo "  3) 将该 vhost 关联到 80/443 对应的 listener"

  local notes_dir="/root/SETUP_NOTES"
  mkdir -p "${notes_dir}"
  local notes_file="${notes_dir}/wp-${SITE_SLUG}.txt"

  cat > "${notes_file}" <<EOF
[WordPress 标准站点安装记录] (${SCRIPT_VERSION})

站点 slug      : ${SITE_SLUG}
站点类型        : ${SITE_TYPE}
主域名          : ${SITE_DOMAIN}
docroot         : ${SITE_DOCROOT}
日志目录        : ${SITE_LOGDIR:-未单独创建}

DB_HOST         : ${DB_HOST}
DB_PORT         : ${DB_PORT}
DB_NAME         : ${DB_NAME}
DB_USER         : ${DB_USER}
DB_PASSWORD     : (已设置，未在此文件明文保存)

Redis 启用      : ${USE_REDIS}
Redis Host      : ${REDIS_HOST:-}
Redis Port      : ${REDIS_PORT:-}
Redis DB index  : ${REDIS_DB_INDEX:-}

vhost 名称      : ${SITE_SLUG}
vhost 配置文件  : ${vhost_conf_path}

安装时间        : $(date -u +"%Y-%m-%d %H:%M:%S UTC")
脚本版本        : ${SCRIPT_VERSION}
EOF

  info "安装完成！关键信息已记录到：${notes_file}"
  cecho "32" "请在浏览器中打开：https://${SITE_DOMAIN}（或配合 Cloudflare 解析）测试访问。"
  pause
}

# ========= 主流程 =========
main() {
  cecho "35" "===================================================="
  cecho "35" "  OLS + WordPress 标准安装模块（${SCRIPT_VERSION}）"
  cecho "35" "===================================================="

  step1_env_check
  step2_ols
  step3_collect_site_info
  step4_collect_db_redis
  step5_prepare_dirs
  step6_install_wp
  step7_config_ols_vhost

  info "全部步骤执行完成。"
}

main "$@"
