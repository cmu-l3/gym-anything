#!/bin/bash
echo "=== Exporting enable_ssl_website results ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check if SSL feature is enabled in Virtualmin
SSL_FEATURE_ENABLED="false"
if virtualmin list-domains --domain acmecorp.test --multiline 2>/dev/null | grep -qi "SSL website enabled"; then
    SSL_FEATURE_ENABLED="true"
fi

# 2. Check HTTPS connectivity and Code
HTTP_CODE=$(curl -sk -o /dev/null -w '%{http_code}' https://localhost:443/ -H "Host: acmecorp.test" 2>/dev/null || echo "000")

# 3. Extract Certificate Details via OpenSSL (connecting to localhost:443)
# We use connect to verify Apache is actually serving it
CERT_INFO=$(echo | openssl s_client -connect localhost:443 -servername acmecorp.test 2>/dev/null | openssl x509 -noout -subject -dates 2>/dev/null || echo "")

CERT_SUBJECT=$(echo "$CERT_INFO" | grep "subject=" || echo "")
CERT_START_DATE=$(echo "$CERT_INFO" | grep "notBefore=" | cut -d= -f2 || echo "")
CERT_END_DATE=$(echo "$CERT_INFO" | grep "notAfter=" | cut -d= -f2 || echo "")

# Parse Subject fields
CERT_O=$(echo "$CERT_SUBJECT" | grep -oP 'O\s*=\s*[^,/]+' | sed 's/O\s*=\s*//' || echo "")
CERT_OU=$(echo "$CERT_SUBJECT" | grep -oP 'OU\s*=\s*[^,/]+' | sed 's/OU\s*=\s*//' || echo "")
CERT_L=$(echo "$CERT_SUBJECT" | grep -oP 'L\s*=\s*[^,/]+' | sed 's/L\s*=\s*//' || echo "")
CERT_ST=$(echo "$CERT_SUBJECT" | grep -oP 'ST\s*=\s*[^,/]+' | sed 's/ST\s*=\s*//' || echo "")
CERT_C=$(echo "$CERT_SUBJECT" | grep -oP 'C\s*=\s*[^,/]+' | sed 's/C\s*=\s*//' || echo "")

# Calculate validity days
VALIDITY_DAYS=0
if [ -n "$CERT_START_DATE" ] && [ -n "$CERT_END_DATE" ]; then
    START_EPOCH=$(date -d "$CERT_START_DATE" +%s 2>/dev/null || echo "0")
    END_EPOCH=$(date -d "$CERT_END_DATE" +%s 2>/dev/null || echo "0")
    if [ "$START_EPOCH" -gt 0 ] && [ "$END_EPOCH" -gt 0 ]; then
        VALIDITY_DAYS=$(( (END_EPOCH - START_EPOCH) / 86400 ))
    fi
fi

# 4. Check File Existence and Timestamps (Anti-gaming)
SSL_FILES_EXIST="false"
FILES_CREATED_DURING_TASK="false"
CERT_FILE_PATH=""

# Common locations for Virtualmin certs
POSSIBLE_PATHS=(
    "/home/acmecorp/ssl.cert"
    "/home/acmecorp/ssl.combined"
    "/var/www/certs/acmecorp.test.cert"
)
# Also try to get path from virtualmin
VIRTUALMIN_PATH=$(virtualmin list-domains --domain acmecorp.test --multiline 2>/dev/null | grep -i "SSL cert" | awk -F: '{print $2}' | tr -d ' ' || echo "")
if [ -n "$VIRTUALMIN_PATH" ]; then
    POSSIBLE_PATHS+=("$VIRTUALMIN_PATH")
fi

for path in "${POSSIBLE_PATHS[@]}"; do
    if [ -f "$path" ]; then
        SSL_FILES_EXIST="true"
        CERT_FILE_PATH="$path"
        FILE_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
            FILES_CREATED_DURING_TASK="true"
        fi
        break
    fi
done

# 5. Check if Firefox is running (Agent active)
APP_RUNNING="false"
if pgrep -f "firefox" > /dev/null; then
    APP_RUNNING="true"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "ssl_feature_enabled": $SSL_FEATURE_ENABLED,
    "http_response_code": "$HTTP_CODE",
    "cert_subject_raw": "$(json_escape "$CERT_SUBJECT")",
    "cert_details": {
        "O": "$(json_escape "$CERT_O")",
        "OU": "$(json_escape "$CERT_OU")",
        "L": "$(json_escape "$CERT_L")",
        "ST": "$(json_escape "$CERT_ST")",
        "C": "$(json_escape "$CERT_C")",
        "validity_days": $VALIDITY_DAYS
    },
    "ssl_files_exist": $SSL_FILES_EXIST,
    "cert_file_path": "$CERT_FILE_PATH",
    "files_created_during_task": $FILES_CREATED_DURING_TASK,
    "app_was_running": $APP_RUNNING,
    "task_start_time": $TASK_START,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result with permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="