#!/bin/bash
echo "=== Exporting install_custom_ssl_cert results ==="

# 1. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Analyze the live SSL certificate being served
OUTPUT_FILE="/tmp/ssl_scan.txt"
# Connect to localhost:443 requesting acmecorp.test SNI
echo "Q" | openssl s_client -connect localhost:443 -servername acmecorp.test -showcerts > "$OUTPUT_FILE" 2>&1 || true

# Extract specific fields
ISSUER=$(openssl x509 -in "$OUTPUT_FILE" -noout -issuer 2>/dev/null || echo "Unknown")
SUBJECT=$(openssl x509 -in "$OUTPUT_FILE" -noout -subject 2>/dev/null || echo "Unknown")
SERIAL=$(openssl x509 -in "$OUTPUT_FILE" -noout -serial 2>/dev/null || echo "Unknown")

# Check if intermediate cert was sent (chain length > 1 or presence of second cert block)
CHAIN_COUNT=$(grep -c "BEGIN CERTIFICATE" "$OUTPUT_FILE" || echo "0")

# 3. Check Apache configuration file modification
# Typically located at /etc/apache2/sites-available/acmecorp.test.conf
CONFIG_FILE=$(find /etc/apache2/sites-enabled -name "*acmecorp.test*" | head -n 1)
CONFIG_MODIFIED="false"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

if [ -f "$CONFIG_FILE" ]; then
    MOD_TIME=$(stat -c %Y "$CONFIG_FILE")
    if [ "$MOD_TIME" -gt "$TASK_START" ]; then
        CONFIG_MODIFIED="true"
    fi
fi

# 4. Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "ssl_issuer": "$(echo "$ISSUER" | sed 's/"/\\"/g')",
    "ssl_subject": "$(echo "$SUBJECT" | sed 's/"/\\"/g')",
    "ssl_serial": "$(echo "$SERIAL" | sed 's/"/\\"/g')",
    "chain_count": $CHAIN_COUNT,
    "config_modified": $CONFIG_MODIFIED,
    "timestamp": $(date +%s)
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json