#!/bin/bash
echo "=== Exporting harden_domain_security result ==="

source /workspace/scripts/task_utils.sh

if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

take_screenshot /tmp/task_end_screenshot.png

TARGET_DOMAIN="acmecorp.test"

# Check SPF record in DNS
DNS_RECORDS=$(virtualmin get-dns --domain "$TARGET_DOMAIN" 2>/dev/null)
SPF_EXISTS="false"
SPF_RECORD=""
# Check for SPF record (type could be SPF or TXT)
if echo "$DNS_RECORDS" | grep -qi "spf\|v=spf1"; then
    SPF_EXISTS="true"
    SPF_RECORD=$(echo "$DNS_RECORDS" | grep -i "spf\|v=spf1" | head -1)
fi

# Check DKIM status
DOMAIN_INFO=$(virtualmin list-domains --domain "$TARGET_DOMAIN" --multiline 2>/dev/null)
DKIM_ENABLED="false"
if echo "$DOMAIN_INFO" | grep -qi "DKIM.*enabled\|dkim.*yes\|DKIM signing.*enabled"; then
    DKIM_ENABLED="true"
fi
# Also check Virtualmin global DKIM config
DKIM_CONFIG=$(grep "^dkim_enabled=" /etc/webmin/virtual-server/config 2>/dev/null | cut -d= -f2)
if [ "$DKIM_CONFIG" = "1" ]; then
    DKIM_ENABLED="true"
fi
# Also check for DKIM DNS record
DKIM_DNS="false"
if echo "$DNS_RECORDS" | grep -qi "dkim\|domainkey"; then
    DKIM_DNS="true"
    # If DNS record exists, DKIM is effectively enabled
    DKIM_ENABLED="true"
fi

# Check Apache config for SSL redirect
APACHE_CONF="/etc/apache2/sites-available/${TARGET_DOMAIN}.conf"
SSL_REDIRECT="false"
if [ -f "$APACHE_CONF" ]; then
    if grep -qi "RewriteRule.*https\|Redirect.*https\|SSLRedirect\|redirect permanent.*https" "$APACHE_CONF" 2>/dev/null; then
        SSL_REDIRECT="true"
    fi
fi
# Also check via virtualmin
WEB_INFO=$(virtualmin modify-web --domain "$TARGET_DOMAIN" 2>/dev/null || true)
if echo "$DOMAIN_INFO" | grep -qi "ssl redirect\|http to https\|https redirect"; then
    SSL_REDIRECT="true"
fi

# Check for X-Content-Type-Options header
NOSNIFF_HEADER="false"
for conf in /etc/apache2/sites-available/${TARGET_DOMAIN}*.conf /etc/apache2/sites-enabled/${TARGET_DOMAIN}*.conf; do
    if [ -f "$conf" ]; then
        if grep -qi "X-Content-Type-Options.*nosniff" "$conf" 2>/dev/null; then
            NOSNIFF_HEADER="true"
            break
        fi
    fi
done
# Also check .htaccess
HTACCESS="/home/acmecorp/public_html/.htaccess"
if [ -f "$HTACCESS" ]; then
    if grep -qi "X-Content-Type-Options.*nosniff" "$HTACCESS" 2>/dev/null; then
        NOSNIFF_HEADER="true"
    fi
fi

# Check directory listing disabled
INDEXES_DISABLED="false"
for conf in /etc/apache2/sites-available/${TARGET_DOMAIN}*.conf /etc/apache2/sites-enabled/${TARGET_DOMAIN}*.conf; do
    if [ -f "$conf" ]; then
        if grep -q "\-Indexes" "$conf" 2>/dev/null; then
            INDEXES_DISABLED="true"
            break
        fi
    fi
done
if [ -f "$HTACCESS" ]; then
    if grep -q "\-Indexes" "$HTACCESS" 2>/dev/null; then
        INDEXES_DISABLED="true"
    fi
fi

# Use Python for reliable JSON
python3 << PYEOF
import json

data = {
    "domain": "${TARGET_DOMAIN}",
    "spf_exists": '${SPF_EXISTS}' == 'true',
    "spf_record": """${SPF_RECORD}""".strip()[:200],
    "dkim_enabled": '${DKIM_ENABLED}' == 'true',
    "dkim_dns_record": '${DKIM_DNS}' == 'true',
    "ssl_redirect": '${SSL_REDIRECT}' == 'true',
    "nosniff_header": '${NOSNIFF_HEADER}' == 'true',
    "indexes_disabled": '${INDEXES_DISABLED}' == 'true',
    "export_timestamp": "$(date -Iseconds)"
}

with open("/tmp/harden_domain_security_result.json", "w") as f:
    json.dump(data, f, indent=2)

print(json.dumps(data, indent=2))
PYEOF

echo "=== Export Complete ==="
