#!/usr/bin/env bash
#
# setup-fail2ban-cron-en.sh - Configure a systemd timer to maintain fail2ban.log size
#

set -euo pipefail

echo "==== Fail2ban log maintenance timer (hz-oneclick) ===="

if [[ $EUID -ne 0 ]]; then
  echo "Please run this script as root." >&2
  exit 1
fi

if ! command -v fail2ban-client >/dev/null 2>&1; then
  echo "fail2ban is not installed. Please run the install-fail2ban module first." >&2
  exit 1
fi

MAINT_SCRIPT="/usr/local/bin/fail2ban-log-maintain.sh"
SERVICE_FILE="/etc/systemd/system/fail2ban-log-maintain.service"
TIMER_FILE="/etc/systemd/system/fail2ban-log-maintain.timer"

echo "[Step 1/3] Writing log maintenance script to ${MAINT_SCRIPT} ..."
cat > "$MAINT_SCRIPT" <<'EOF'
#!/usr/bin/env bash
# fail2ban-log-maintain.sh - keep fail2ban.log size under control (by line count)

set -euo pipefail

LOG_FILE="/var/log/fail2ban.log"
MAX_LINES=5000
KEEP_LINES=3000

ts() { date +"%Y-%m-%d %H:%M:%S"; }

echo "[fail2ban-log-maintain][$(ts)] Checking log size..."

if [[ ! -f "$LOG_FILE" ]]; then
  echo "[fail2ban-log-maintain][$(ts)] Log file does not exist: $LOG_FILE"
  exit 0
fi

lines=$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)

if (( lines > MAX_LINES )); then
  echo "[fail2ban-log-maintain][$(ts)] Current lines $lines > limit $MAX_LINES, truncating..."
  tmp="${LOG_FILE}.tmp.$$"
  tail -n "$KEEP_LINES" "$LOG_FILE" > "$tmp" 2>/dev/null || true
  mv "$tmp" "$LOG_FILE"
  echo "[fail2ban-log-maintain][$(ts)] Kept last $KEEP_LINES lines."
else
  echo "[fail2ban-log-maintain][$(ts)] Current lines $lines, no truncation needed."
fi
EOF

chmod +x "$MAINT_SCRIPT"

echo "[Step 2/3] Writing systemd service and timer ..."

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Maintain fail2ban.log size (hz-oneclick)

[Service]
Type=oneshot
ExecStart=${MAINT_SCRIPT}
EOF

cat > "$TIMER_FILE" <<'EOF'
[Unit]
Description=Daily fail2ban.log maintenance timer (hz-oneclick)

[Timer]
# Run once per day at 03:40 UTC
OnCalendar=*-*-* 03:40:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

echo "[Step 3/3] Reloading systemd and enabling timer ..."
systemctl daemon-reload
systemctl enable --now fail2ban-log-maintain.timer

echo
echo "==== Done: fail2ban log maintenance timer is now active ===="
echo "Check status with:"
echo "  systemctl status fail2ban-log-maintain.service"
echo "  systemctl status fail2ban-log-maintain.timer"
echo
echo "To change the schedule, edit:"
echo "  ${TIMER_FILE}"
