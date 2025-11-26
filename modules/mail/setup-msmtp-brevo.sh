#!/usr/bin/env bash
# 安装并配置 msmtp + Brevo（或兼容 SMTP）
# 只写模板，不写任何真实凭据

set -euo pipefail

if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  echo "请用 root 运行本脚本（需要写 /etc/msmtprc）" >&2
  exit 1
fi

echo "== 安装 msmtp / msmtp-mta =="
apt update -y
apt install -y msmtp msmtp-mta ca-certificates

echo
echo "== 配置 msmtp（以 Brevo 为例，其它 SMTP 也可用）=="
read -rp "发信邮箱 From（例如 no-reply@example.com）: " SMTP_FROM
read -rp "SMTP 登录用户名（例如 Brevo 的 SMTP 登录邮箱）: " SMTP_USER
read -srp "SMTP 密码 / API Key（输入不回显）: " SMTP_PASS
echo

# 备份旧配置（如果有）
if [ -f /etc/msmtprc ]; then
  cp /etc/msmtprc "/etc/msmtprc.bak.$(date +%Y%m%d%H%M%S)"
  echo "已备份旧 /etc/msmtprc -> /etc/msmtprc.bak.*"
fi

cat >/etc/msmtprc <<EOF
defaults
tls on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
auth on
syslog LOG_MAIL

account default
host smtp-relay.brevo.com
port 587
user ${SMTP_USER}
password ${SMTP_PASS}
from ${SMTP_FROM}

EOF

chmod 600 /etc/msmtprc

echo "== 创建通用发信脚本 /usr/local/bin/send-alert-mail.sh =="

cat >/usr/local/bin/send-alert-mail.sh <<'EOS'
#!/usr/bin/env bash
# 用法：send-alert-mail.sh "英文标题" "正文内容（可中英混合）" 收件人邮箱

SUBJECT="$1"
BODY="$2"
TO="$3"

if [ -z "${SUBJECT:-}" ] || [ -z "${BODY:-}" ] || [ -z "${TO:-}" ]; then
  echo "用法: send-alert-mail.sh \"英文标题\" \"正文\" 收件人邮箱" >&2
  exit 1
fi

FROM_ADDR=$(grep -m1 '^from ' /etc/msmtprc | awk '{print $2}')

printf 'From: "no-reply" <%s>\nTo: %s\nSubject: %s\nContent-Type: text/plain; charset=UTF-8\nContent-Transfer-Encoding: 8bit\n\n%s\n' \
  "${FROM_ADDR}" "${TO}" "${SUBJECT}" "${BODY}" \
  | msmtp "${TO}"
EOS

chmod +x /usr/local/bin/send-alert-mail.sh

echo
echo "完成！可以用下面命令测试发信："
echo '  send-alert-mail.sh "[host] msmtp test" "这是一封测试邮件。" "you@example.com"'
echo
