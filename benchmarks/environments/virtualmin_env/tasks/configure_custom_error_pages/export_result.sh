#!/bin/bash
echo "=== Exporting configure_custom_error_pages results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Paths
WEB_ROOT="/home/acmecorp/public_html"
ERR_DIR="$WEB_ROOT/errors"
FILE_404="$ERR_DIR/404.html"
FILE_403="$ERR_DIR/403.html"

# 1. Check Files
check_file() {
    local fpath="$1"
    if [ -f "$fpath" ]; then
        local mtime=$(stat -c %Y "$fpath")
        local owner=$(stat -c %U "$fpath")
        local content=$(cat "$fpath" | base64 -w 0)
        local created_during_task="false"
        if [ "$mtime" -ge "$TASK_START" ]; then
            created_during_task="true"
        fi
        echo "{\"exists\": true, \"created_during_task\": $created_during_task, \"owner\": \"$owner\", \"content_b64\": \"$content\"}"
    else
        echo "{\"exists\": false}"
    fi
}

JSON_404=$(check_file "$FILE_404")
JSON_403=$(check_file "$FILE_403")

# 2. Check Apache Configuration (Static Analysis)
# Check .htaccess
HTACCESS_HAS_CONFIG="false"
if [ -f "$WEB_ROOT/.htaccess" ]; then
    if grep -q "ErrorDocument" "$WEB_ROOT/.htaccess"; then
        HTACCESS_HAS_CONFIG="true"
    fi
fi

# Check Apache site config
APACHE_HAS_CONFIG="false"
CONF_FILE=$(grep -l "ServerName acmecorp.test" /etc/apache2/sites-enabled/*.conf 2>/dev/null | head -1)
if [ -n "$CONF_FILE" ]; then
    if grep -q "ErrorDocument" "$CONF_FILE"; then
        APACHE_HAS_CONFIG="true"
    fi
fi

# 3. Functional Test (Dynamic Analysis)
# Curl a non-existent page to see if we get the custom 404
# We use -H "Host: acmecorp.test" to route to the correct vhost
CURL_RESULT=$(curl -s -L -H "Host: acmecorp.test" http://localhost/this-page-definitely-does-not-exist-12345)
# Encode for JSON safety
CURL_RESULT_B64=$(echo "$CURL_RESULT" | base64 -w 0)

# Curl a forbidden page (simulating 403 is harder without setting permissions, 
# but if 404 works, 403 is likely configured similarly. 
# We can try to access .htaccess which is usually 403 protected)
CURL_403_RESULT=$(curl -s -L -H "Host: acmecorp.test" http://localhost/.htaccess)
CURL_403_RESULT_B64=$(echo "$CURL_403_RESULT" | base64 -w 0)

# 4. Take final screenshot
take_screenshot /tmp/task_final.png
SCREENSHOT_EXISTS="false"
[ -f /tmp/task_final.png ] && SCREENSHOT_EXISTS="true"

# 5. Construct Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_404": $JSON_404,
    "file_403": $JSON_403,
    "htaccess_configured": $HTACCESS_HAS_CONFIG,
    "apache_configured": $APACHE_HAS_CONFIG,
    "curl_404_response_b64": "$CURL_RESULT_B64",
    "curl_403_response_b64": "$CURL_403_RESULT_B64",
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"