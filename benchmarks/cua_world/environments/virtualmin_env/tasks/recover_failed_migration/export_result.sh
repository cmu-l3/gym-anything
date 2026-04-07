#!/bin/bash
# =============================================================================
# Export results: recover_failed_migration
#
# Collects the current system state into /tmp/task_result.json for the
# verifier. Checks: website, status.php, email delivery, DKIM, SPF, DMARC,
# and anti-gaming checksums.
# =============================================================================

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

echo "=== Exporting results for recover_failed_migration ==="

# ---------------------------------------------------------------
# Take final screenshot
# ---------------------------------------------------------------
take_screenshot /tmp/task_final.png

# ---------------------------------------------------------------
# Test 1: Website loads content (index.php or index.html)
# ---------------------------------------------------------------
WEB_HTTP_CODE=$(curl -s -o /tmp/web_body.txt -w "%{http_code}" \
    "http://localhost/" --header "Host: acmecorp.test" --max-time 10 2>/dev/null || echo "000")
WEB_BODY=$(cat /tmp/web_body.txt 2>/dev/null | head -c 5000)
WEB_HAS_CONTENT="false"
echo "$WEB_BODY" | grep -qi "bootstrap\|album\|freelancer\|acme\|template" && WEB_HAS_CONTENT="true"
echo "Website: HTTP $WEB_HTTP_CODE, has_content=$WEB_HAS_CONTENT"
rm -f /tmp/web_body.txt

# ---------------------------------------------------------------
# Test 2: Status page returns "System Operational"
# ---------------------------------------------------------------
STATUS_HTTP_CODE=$(curl -s -o /tmp/status_body.txt -w "%{http_code}" \
    "http://localhost/status.php" --header "Host: acmecorp.test" --max-time 10 2>/dev/null || echo "000")
STATUS_BODY=$(cat /tmp/status_body.txt 2>/dev/null | head -c 2000)
STATUS_OPERATIONAL="false"
echo "$STATUS_BODY" | grep -q "System Operational" && STATUS_OPERATIONAL="true"
echo "Status page: HTTP $STATUS_HTTP_CODE, operational=$STATUS_OPERATIONAL, body=$(echo "$STATUS_BODY" | head -c 200)"
rm -f /tmp/status_body.txt

# ---------------------------------------------------------------
# Test 3: Email delivery — send test and check Maildir
# ---------------------------------------------------------------
echo "--- Sending test email ---"
echo "Migration recovery verification email sent at $(date)" | \
    mail -s "Migration Test $(date +%s)" \
    -r "admin@acmecorp.test" "info@acmecorp.test" 2>/dev/null || true

# Wait for local delivery
sleep 15

MAIL_DELIVERED="false"
MAIL_DIR="/home/acmecorp/homes/info/Maildir/new"
if [ -d "$MAIL_DIR" ]; then
    NEW_MAIL=$(find "$MAIL_DIR" -type f -newer /tmp/task_start_time.txt 2>/dev/null | head -1)
    if [ -n "$NEW_MAIL" ]; then
        MAIL_DELIVERED="true"
    fi
fi
echo "Email delivery: $MAIL_DELIVERED"

# ---------------------------------------------------------------
# Test 4: DKIM — signing enabled + DNS record published
# ---------------------------------------------------------------
DKIM_ENABLED="false"
DKIM_DNS_RECORD="false"

# Check Virtualmin domain info for DKIM status
DOMAIN_MULTILINE=$(virtualmin list-domains --domain acmecorp.test --multiline 2>/dev/null)
echo "$DOMAIN_MULTILINE" | grep -qi "DKIM.*enabled\|dkim.*yes" && DKIM_ENABLED="true"

# Also check the global config flag
DKIM_CONFIG_VAL=$(grep "^dkim_enabled=" /etc/webmin/virtual-server/config 2>/dev/null | cut -d= -f2)
[ "$DKIM_CONFIG_VAL" = "1" ] && DKIM_ENABLED="true"

# Check if DKIM key and domain list exist (Virtualmin creates these when DKIM is enabled)
if [ -f /etc/dkim.key ] && [ -f /etc/dkim-domains.txt ]; then
    if grep -q "acmecorp.test" /etc/dkim-domains.txt 2>/dev/null; then
        DKIM_ENABLED="true"
    fi
fi

# Check DNS for a DKIM key record
DNS_RECORDS=$(virtualmin get-dns --domain acmecorp.test 2>/dev/null)
echo "$DNS_RECORDS" | grep -qi "dkim\|domainkey" && DKIM_DNS_RECORD="true"
echo "DKIM: enabled=$DKIM_ENABLED, dns_record=$DKIM_DNS_RECORD"

# ---------------------------------------------------------------
# Test 5: SPF record in DNS
# ---------------------------------------------------------------
SPF_FOUND="false"
SPF_RECORD=""
if echo "$DNS_RECORDS" | grep -qi "v=spf1"; then
    SPF_FOUND="true"
    SPF_RECORD=$(echo "$DNS_RECORDS" | grep -i "v=spf1" | head -1 | tr -d '"')
fi
echo "SPF: found=$SPF_FOUND record='$SPF_RECORD'"

# ---------------------------------------------------------------
# Test 6: DMARC record with p=reject
# ---------------------------------------------------------------
DMARC_FOUND="false"
DMARC_RECORD=""

# Try dig first (most reliable for the _dmarc subdomain)
DMARC_DIG=$(dig TXT _dmarc.acmecorp.test @127.0.0.1 +short 2>/dev/null || \
            dig TXT _dmarc.acmecorp.test @localhost +short 2>/dev/null || true)
if echo "$DMARC_DIG" | grep -qi "v=DMARC1.*p=reject"; then
    DMARC_FOUND="true"
    DMARC_RECORD=$(echo "$DMARC_DIG" | grep -i "DMARC1" | head -1 | tr -d '"')
fi

# Fallback: check the zone file or virtualmin DNS output
if [ "$DMARC_FOUND" = "false" ]; then
    if echo "$DNS_RECORDS" | grep -qi "_dmarc.*v=DMARC1.*p=reject"; then
        DMARC_FOUND="true"
        DMARC_RECORD=$(echo "$DNS_RECORDS" | grep -i "_dmarc" | head -1 | tr -d '"')
    fi
fi
echo "DMARC: found=$DMARC_FOUND record='$DMARC_RECORD'"

# ---------------------------------------------------------------
# Test 7: PHP-FPM service status
# ---------------------------------------------------------------
PHP_VERSION=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null)
PHP_FPM_ACTIVE=$(systemctl is-active "php${PHP_VERSION}-fpm" 2>/dev/null || echo "unknown")
echo "PHP-FPM ($PHP_VERSION): $PHP_FPM_ACTIVE"

# ---------------------------------------------------------------
# Test 8: Anti-gaming — check that config files were modified
# ---------------------------------------------------------------
CONFIGS_CHANGED=0
if [ -f /tmp/initial_checksums.txt ]; then
    while IFS=' ' read -r old_hash old_file rest; do
        if [ -f "$old_file" ]; then
            new_hash=$(md5sum "$old_file" 2>/dev/null | awk '{print $1}')
            if [ "$new_hash" != "$old_hash" ]; then
                CONFIGS_CHANGED=$((CONFIGS_CHANGED + 1))
            fi
        fi
    done < /tmp/initial_checksums.txt
fi
echo "Anti-gaming: $CONFIGS_CHANGED config files modified"

# ---------------------------------------------------------------
# Write JSON result
# ---------------------------------------------------------------
ESCAPED_STATUS_BODY=$(json_escape "$STATUS_BODY")
ESCAPED_SPF=$(json_escape "$SPF_RECORD")
ESCAPED_DMARC=$(json_escape "$DMARC_RECORD")

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "web_http_code": "$WEB_HTTP_CODE",
    "web_has_content": $WEB_HAS_CONTENT,
    "status_http_code": "$STATUS_HTTP_CODE",
    "status_operational": $STATUS_OPERATIONAL,
    "status_body": "$ESCAPED_STATUS_BODY",
    "mail_delivered": $MAIL_DELIVERED,
    "dkim_enabled": $DKIM_ENABLED,
    "dkim_dns_record": $DKIM_DNS_RECORD,
    "spf_found": $SPF_FOUND,
    "spf_record": "$ESCAPED_SPF",
    "dmarc_found": $DMARC_FOUND,
    "dmarc_record": "$ESCAPED_DMARC",
    "php_fpm_active": "$PHP_FPM_ACTIVE",
    "configs_changed": $CONFIGS_CHANGED,
    "task_start": $TASK_START,
    "task_end": $TASK_END
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Results exported to /tmp/task_result.json ==="
