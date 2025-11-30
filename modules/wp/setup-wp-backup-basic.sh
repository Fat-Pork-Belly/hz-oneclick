#!/usr/bin/env bash
# WordPress 备份安装脚本 + systemd 定时任务（使用 rclone 远程）
# 用于一键生成单站点的 DB + 文件备份脚本

set -euo pipefail

# 预先定义变量，避免 set -u 报错
SITE=""
WP_ROOT=""
DB_NAME=""
DB_USER=""
DB_PASS=""
DB_HOST=""
BACKUP_BASE=""
RCLONE_REMOTE=""

#--------------------------------------------------
# 0) 必须用 root
#--------------------------------------------------
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "本脚本需要以 root 身份运行（要写 /usr/local/bin 和 /etc/systemd/system）。" >&2
  exit 1
fi

echo "=============================================="
echo " WordPress backup setup (DB + files)"
echo "=============================================="
echo

#--------------------------------------------------
# 1) 检查 rclone 是否已安装
#--------------------------------------------------
if ! command -v rclone >/dev/null 2>&1; then
  echo "[!] 未检测到 rclone，请先安装并配置至少一个 remote："
  echo "    rclone config"
  exit 1
fi

#--------------------------------------------------
# 2) 站点信息
#--------------------------------------------------
echo "[1/6] 站点基本信息 / Site info"
read -rp "Site ID（用于路径和文件名，如 blog1，不要包含空格）: " SITE
SITE="${SITE// /}"   # 去掉空格
if [[ -z "$SITE" ]]; then
  echo "Site ID 不能为空，退出。" >&2
  exit 1
fi

DEFAULT_WP_ROOT="/var/www/${SITE}/html"
read -rp "WordPress 根目录 [${DEFAULT_WP_ROOT}] : " WP_ROOT
WP_ROOT="${WP_ROOT:-$DEFAULT_WP_ROOT}"

if [[ ! -d "$WP_ROOT" ]]; then
  echo "[!] 目录不存在：${WP_ROOT}"
  echo "    请确认 WordPress 安装路径后重试。"
  exit 1
fi

#--------------------------------------------------
# 3) 数据库信息
#--------------------------------------------------
echo
echo "[2/6] 数据库设置 / Database settings"
read -rp "DB 名称（wp-config.php 中 DB_NAME）: " DB_NAME
read -rp "DB 用户名（wp-config.php 中 DB_USER）: " DB_USER
read -rsp "DB 密码（wp-config.php 中 DB_PASSWORD）: " DB_PASS
echo
read -rp "DB 主机（wp-config.php 中 DB_HOST，如 127.0.0.1 或 127.0.0.1:3306）: " DB_HOST

if [[ -z "$DB_NAME" || -z "$DB_USER" || -z "$DB_PASS" || -z "$DB_HOST" ]]; then
  echo "[!] 数据库信息不完整，退出。" >&2
  exit 1
fi

#--------------------------------------------------
# 4) 本机备份目录
#--------------------------------------------------
echo
echo "[3/6] 本机备份目录 / Local backup base"
DEFAULT_BACKUP_BASE="/root/backups/${SITE}"
read -rp "本机备份根目录 [${DEFAULT_BACKUP_BASE}] : " BACKUP_BASE
BACKUP_BASE="${BACKUP_BASE:-$DEFAULT_BACKUP_BASE}"
mkdir -p "$BACKUP_BASE"

#--------------------------------------------------
# 5) rclone 远程路径
#--------------------------------------------------
echo
echo "[4/6] rclone 远程路径 / rclone remote path"
echo "示例："
echo "  gdrive:${SITE}"
echo "  onedrive:${SITE}"
echo "  any-remote:some-folder"
read -rp "请输入 rclone 目标（不含日期子目录）: " RCLONE_REMOTE

if [[ -z "$RCLONE_REMOTE" ]]; then
  echo "[!] rclone 目标不能为空，退出。" >&2
  exit 1
fi

# 简单检查 remote 名称是否存在（仅提示，不强制）
REMOTE_NAME="${RCLONE_REMOTE%%:*}"
if ! rclone listremotes 2>/dev/null | grep -q "^${REMOTE_NAME}:"; then
  echo "[!] 提示：似乎没有名为 \"${REMOTE_NAME}\" 的 rclone remote。"
  echo "    如果你确认配置过，可忽略此提示；否则请先执行：rclone config"
  echo
fi

#--------------------------------------------------
# 6) 拆分 DB_HOST 为 host + port
#--------------------------------------------------
DB_HOST_ONLY="$DB_HOST"
DB_PORT_ONLY="3306"
if [[ "$DB_HOST" == *:* ]]; then
  DB_HOST_ONLY="${DB_HOST%%:*}"
  DB_PORT_ONLY="${DB_HOST##*:}"
fi

#--------------------------------------------------
# 7) 生成实际备份脚本
#--------------------------------------------------
BACKUP_SCRIPT="/usr/local/bin/wp-backup-${SITE}.sh"
SERVICE_FILE="/etc/systemd/system/wp-backup-${SITE}.service"
TIMER_FILE="/etc/systemd/system/wp-backup-${SITE}.timer"

cat >"$BACKUP_SCRIPT" <<EOF
#!/usr/bin/env bash
# Auto-generated WordPress backup script for site: ${SITE}

set -euo pipefail

SITE="${SITE}"
WP_ROOT="${WP_ROOT}"
DB_NAME="${DB_NAME}"
DB_USER="${DB_USER}"
DB_PASS="${DB_PASS}"
DB_HOST_ONLY="${DB_HOST_ONLY}"
DB_PORT_ONLY="${DB_PORT_ONLY}"
BACKUP_BASE="${BACKUP_BASE}"
RCLONE_REMOTE="${RCLONE_REMOTE}"

TIMESTAMP=\$(date +'%Y-%m-%d_%H%M%S')
WORK_DIR="\${BACKUP_BASE}/\${TIMESTAMP}"
LOG_TAG="[wp-backup:\${SITE}]"

echo "\${LOG_TAG} 创建本机目录: \${WORK_DIR}"
mkdir -p "\${WORK_DIR}"

DB_FILE="\${WORK_DIR}/db_\${TIMESTAMP}.sql.gz"
FILES_FILE="\${WORK_DIR}/html_\${TIMESTAMP}.tgz"

echo "\${LOG_TAG} 备份数据库..."
mysqldump -h "\${DB_HOST_ONLY}" -P "\${DB_PORT_ONLY}" -u "\${DB_USER}" -p"\${DB_PASS}" "\${DB_NAME}" | gzip -c > "\${DB_FILE}"

echo "\${LOG_TAG} 备份 WordPress 文件..."
tar -C "\${WP_ROOT}" -czf "\${FILES_FILE}" .

echo "\${LOG_TAG} 同步到远程: \${RCLONE_REMOTE}/\${TIMESTAMP}"
rclone copy "\${WORK_DIR}" "\${RCLONE_REMOTE}/\${TIMESTAMP}" --create-empty-src-dirs

echo "\${LOG_TAG} 清理远程超过 30 天的旧备份..."
rclone delete "\${RCLONE_REMOTE}" --min-age 30d || true
rclone rmdirs "\${RCLONE_REMOTE}" --leave-root || true

echo "\${LOG_TAG} 清理本机超过 7 天的旧备份..."
find "\${BACKUP_BASE}" -maxdepth 1 -type d -name "20*" -mtime +7 -print -exec rm -rf {} \; || true

echo "\${LOG_TAG} 备份完成。"
EOF

chmod +x "$BACKUP_SCRIPT"

#--------------------------------------------------
# 8) 写入 systemd service & timer（每天 03:30）
#--------------------------------------------------
cat >"$SERVICE_FILE" <<EOF
[Unit]
Description=WordPress backup for site ${SITE}
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=$BACKUP_SCRIPT
EOF

cat >"$TIMER_FILE" <<EOF
[Unit]
Description=Daily WordPress backup for site ${SITE}

[Timer]
OnCalendar=*-*-* 03:30:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now "wp-backup-${SITE}.timer"

echo
echo "=================================================="
echo "备份脚本已生成：$BACKUP_SCRIPT"
echo "systemd service：$SERVICE_FILE"
echo "systemd timer：  $TIMER_FILE"
echo
echo "已启用定时任务：每天 03:30 执行一次备份。"
echo
echo "手动立即测试一次备份："
echo "  sudo $BACKUP_SCRIPT"
echo
echo "查看定时器状态："
echo "  systemctl status wp-backup-${SITE}.timer"
echo "  journalctl -u wp-backup-${SITE}.service"
echo "=================================================="
