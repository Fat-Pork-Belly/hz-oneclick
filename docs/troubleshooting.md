# Troubleshooting

## Common startup failures

Use the quick triage commands first. Then use the symptom sections below to
identify the likely cause and fix.

### Quick triage

```bash
sudo systemctl status lsws
sudo systemctl restart lsws
sudo ss -lntp
sudo ufw status
curl -I http://abc.yourdomain.com
sudo journalctl -u lsws --since "1 hour ago"
sudo tail -n 200 /path/to/your/logs/error.log
```

> Log locations vary by configuration. See
> [Configuration file locations](config.md) to identify active configs and log
> paths for your setup.

### Site returns 521/5xx or cannot connect

- **Symptom:** Browser shows 521/5xx, connection refused, or timeouts.
- **Check:**
  - `sudo systemctl status lsws`
  - `sudo ss -lntp | grep -E ':(80|443|7080)\b'`
  - `curl -I http://abc.yourdomain.com`
- **Likely cause:** Web server is down, crashed, or not bound to expected ports.
- **Fix:** Restart the service and review logs.
  - `sudo systemctl restart lsws`
  - `sudo journalctl -u lsws --since "1 hour ago"`
  - `sudo tail -n 200 /path/to/your/logs/error.log`

### Ports 80/443/7080 not reachable or already in use

- **Symptom:** `curl` fails, or the web UI is unreachable.
- **Check:**
  - `sudo ss -lntp | grep -E ':(80|443|7080)\b'`
  - `sudo ufw status`
- **Likely cause:** Firewall blocking traffic, or another process is bound to the port.
- **Fix:**
  - Open the required ports in your firewall policy.
  - Stop or reconfigure the conflicting process, then restart OpenLiteSpeed.

### OpenLiteSpeed service not running or failed to start

- **Symptom:** `systemctl status lsws` shows failed or inactive.
- **Check:**
  - `sudo systemctl status lsws`
  - `sudo journalctl -u lsws --since "1 hour ago"`
- **Likely cause:** Config syntax errors, missing files, or invalid permissions.
- **Fix:**
  - Fix the error reported in logs, then restart:
    - `sudo systemctl restart lsws`
  - If you recently edited config files, re-check their paths and syntax.

### Permission or ownership problems affecting the web root

- **Symptom:** 403 errors, blank pages, or missing assets.
- **Check:**
  - `ls -ld /var/www/your-site /var/www/your-site/html`
- **Likely cause:** Incorrect ownership or permissions on the site root.
- **Fix:**
  - Set ownership to the expected web user and group:
    - `sudo chown -R your-web-user:your-web-group /var/www/your-site`
  - Ensure directories are readable/executable by the web user:
    - `sudo find /var/www/your-site -type d -exec chmod 755 {} \;`

### TLS/certificate mismatch or missing cert/key paths

- **Symptom:** HTTPS fails, browser warns about invalid certs, or TLS handshake errors.
- **Check:**
  - Confirm the configured cert/key paths exist:
    - `ls -l /path/to/your/cert.pem /path/to/your/key.pem`
  - Verify the certificate matches the domain:
    - `openssl x509 -in /path/to/your/cert.pem -noout -text | grep -E 'Subject:|DNS:'`
- **Likely cause:** Wrong certificate for the domain, or paths are incorrect.
- **Fix:**
  - Update the vhost to point at the correct cert/key files, then reload:
    - `sudo systemctl restart lsws`

### Database connection failures (MariaDB/MySQL)

- **Symptom:** App reports database connection errors or shows a DB error page.
- **Check:**
  - `sudo systemctl status mariadb`
  - `mysql -u your-db-user -p -h 127.0.0.1 -P 3306 -e "SELECT 1;"`
- **Likely cause:** DB service is down, credentials are wrong, or the DB host/port is incorrect.
- **Fix:**
  - Restart the DB service and verify credentials in your app config.

### Redis connection failures (if applicable)

- **Symptom:** Cache errors or app logs show Redis connection refused.
- **Check:**
  - `sudo systemctl status redis-server`
  - `redis-cli -h 127.0.0.1 -p 6379 ping`
- **Likely cause:** Redis service is down or not listening on the expected host/port.
- **Fix:**
  - Restart Redis and confirm the configured host/port matches.

### DNS sanity check (A/AAAA records)

- **Symptom:** Domain points to the wrong server or does not resolve as expected.
- **Check:**
  - `dig +short A abc.yourdomain.com`
  - `dig +short AAAA abc.yourdomain.com`
- **Likely cause:** DNS records point to an old or incorrect IP address.
- **Fix:**
  - Update your DNS records to the correct IPv4/IPv6 addresses and wait for DNS propagation.
