#!/bin/bash
echo "=== Exporting generate_propagate_ssl result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
DOMAIN_CERT="/home/acmecorp/ssl.cert"
WEBMIN_CERT="/etc/webmin/miniserv.pem"

# Helper to get cert info
get_modulus() {
    if [ -f "$1" ]; then
        openssl x509 -noout -modulus -in "$1" 2>/dev/null | sed 's/Modulus=//'
    else
        echo "MISSING"
    fi
}

get_subject() {
    if [ -f "$1" ]; then
        openssl x509 -noout -subject -in "$1" 2>/dev/null | sed 's/subject=//'
    else
        echo "MISSING"
    fi
}

# 1. Inspect Domain Certificate
DOMAIN_EXISTS="false"
DOMAIN_MODULUS=""
DOMAIN_SUBJECT=""
CERT_MTIME="0"

if [ -f "$DOMAIN_CERT" ]; then
    DOMAIN_EXISTS="true"
    DOMAIN_MODULUS=$(get_modulus "$DOMAIN_CERT")
    DOMAIN_SUBJECT=$(get_subject "$DOMAIN_CERT")
    CERT_MTIME=$(stat -c %Y "$DOMAIN_CERT" 2>/dev/null || echo "0")
fi

# 2. Inspect Webmin Certificate
WEBMIN_MODULUS=$(get_modulus "$WEBMIN_CERT")

# 3. Inspect Postfix Certificate
# Extract path from postconf
POSTFIX_CERT_PATH=$(postconf -h smtpd_tls_cert_file 2>/dev/null)
POSTFIX_MODULUS=$(get_modulus "$POSTFIX_CERT_PATH")

# 4. Inspect Dovecot Certificate
# Extract path from doveconf
DOVECOT_CERT_ENTRY=$(doveconf -h ssl_cert 2>/dev/null || echo "")
# Format is usually "<file"
DOVECOT_CERT_PATH=$(echo "$DOVECOT_CERT_ENTRY" | sed 's/^<//')
DOVECOT_MODULUS=$(get_modulus "$DOVECOT_CERT_PATH")

# 5. Check creation time (Anti-gaming)
FILE_CREATED_DURING_TASK="false"
if [ "$CERT_MTIME" -gt "$TASK_START" ]; then
    FILE_CREATED_DURING_TASK="true"
fi

# 6. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 7. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "domain_cert_exists": $DOMAIN_EXISTS,
    "domain_cert_subject": "$(echo $DOMAIN_SUBJECT | sed 's/"/\\"/g')",
    "domain_cert_modulus": "$DOMAIN_MODULUS",
    "webmin_cert_modulus": "$WEBMIN_MODULUS",
    "postfix_cert_modulus": "$POSTFIX_MODULUS",
    "dovecot_cert_modulus": "$DOVECOT_MODULUS",
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="