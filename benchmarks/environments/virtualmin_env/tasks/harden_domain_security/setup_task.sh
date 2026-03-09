#!/bin/bash
echo "=== Setting up harden_domain_security task ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type virtualmin_list_domains &>/dev/null; then
    echo "WARNING: task_utils.sh functions not available, using inline definitions"
    virtualmin_list_dns() { virtualmin get-dns --domain "$1" 2>/dev/null || true; }
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
    ensure_virtualmin_ready() { true; }
    navigate_to() {
        DISPLAY=:1 xdotool key ctrl+l; sleep 0.5
        DISPLAY=:1 xdotool type --clearmodifiers --delay 20 "$1"; sleep 0.3
        DISPLAY=:1 xdotool key Return; sleep 4
    }
fi

TARGET_DOMAIN="acmecorp.test"

# Verify domain exists
if ! virtualmin list-domains --name-only 2>/dev/null | grep -q "^${TARGET_DOMAIN}$"; then
    echo "ERROR: ${TARGET_DOMAIN} does not exist!"
    exit 1
fi

# Clean up previous run: remove SPF records, disable DKIM, remove security headers
echo "--- Cleaning up previous security hardening ---"

# Remove any existing SPF record
virtualmin modify-dns --domain "$TARGET_DOMAIN" --no-spf 2>/dev/null || true

# Disable DKIM if enabled (set-dkim is a global setting)
virtualmin set-dkim --disable 2>/dev/null || true

# Reset Apache config: remove security headers and SSL redirect
APACHE_CONF="/etc/apache2/sites-available/${TARGET_DOMAIN}.conf"
APACHE_SSL_CONF="/etc/apache2/sites-available/${TARGET_DOMAIN}-le-ssl.conf"

# Remove X-Content-Type-Options header if present
for conf in "$APACHE_CONF" "$APACHE_SSL_CONF"; do
    if [ -f "$conf" ]; then
        sed -i '/X-Content-Type-Options/d' "$conf" 2>/dev/null || true
        sed -i '/RewriteEngine.*On/d' "$conf" 2>/dev/null || true
        sed -i '/RewriteCond.*HTTPS/d' "$conf" 2>/dev/null || true
        sed -i '/RewriteRule.*https/d' "$conf" 2>/dev/null || true
    fi
done

# Re-enable directory listing (remove -Indexes if present)
if [ -f "$APACHE_CONF" ]; then
    sed -i 's/Options.*-Indexes/Options +Indexes/g' "$APACHE_CONF" 2>/dev/null || true
fi

# Reload Apache
systemctl reload apache2 2>/dev/null || true

# Record baseline state
echo "--- Recording baseline state ---"
DNS_RECORDS=$(virtualmin get-dns --domain "$TARGET_DOMAIN" 2>/dev/null)
DOMAIN_INFO=$(virtualmin list-domains --domain "$TARGET_DOMAIN" --multiline 2>/dev/null)
APACHE_CONTENT=""
if [ -f "$APACHE_CONF" ]; then
    APACHE_CONTENT=$(cat "$APACHE_CONF" 2>/dev/null)
fi

# Check initial DKIM status
DKIM_STATUS="disabled"
if echo "$DOMAIN_INFO" | grep -qi "dkim.*enabled\|dkim.*yes"; then
    DKIM_STATUS="enabled"
fi

# Check initial SPF
SPF_EXISTS="false"
if echo "$DNS_RECORDS" | grep -qi "spf"; then
    SPF_EXISTS="true"
fi

cat > /tmp/initial_security_state.json << EOF
{
    "domain": "${TARGET_DOMAIN}",
    "initial_spf_exists": ${SPF_EXISTS},
    "initial_dkim_status": "${DKIM_STATUS}",
    "initial_apache_has_nosniff": false,
    "initial_apache_has_redirect": false,
    "initial_apache_has_indexes_disabled": false
}
EOF

cat /tmp/initial_security_state.json

# Record timestamp
date +%s > /tmp/task_start_timestamp

# Ensure Firefox is ready
ensure_virtualmin_ready
sleep 2

# Navigate to Virtualmin dashboard
navigate_to "https://localhost:10000/virtual-server/index.cgi"
sleep 3

take_screenshot /tmp/task_start_screenshot.png
echo "=== harden_domain_security task setup complete ==="
