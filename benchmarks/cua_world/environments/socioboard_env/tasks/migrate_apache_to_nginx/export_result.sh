#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check Service States
APACHE_STATE=$(systemctl is-active apache2 2>/dev/null || echo "inactive")
NGINX_STATE=$(systemctl is-active nginx 2>/dev/null || echo "inactive")
PHPFPM_STATE=$(systemctl is-active php7.4-fpm 2>/dev/null || echo "inactive")

# 2. HTTP Checks (Using -L to follow potential redirects, though frameworks usually handle routing at index)
ROOT_STATUS=$(curl -s -L -o /dev/null -w "%{http_code}" http://localhost/ || echo "000")
LOGIN_STATUS=$(curl -s -L -o /dev/null -w "%{http_code}" http://localhost/login || echo "000")

# 3. Server Header Identity
SERVER_HEADER=$(curl -s -I http://localhost/ | grep -i "^Server:" | tr -d '\r' || echo "Server: none")

# 4. Check PHP execution (Confirming Laravel/PHP runs instead of returning raw source code)
ROOT_BODY=$(curl -s -L http://localhost/ | head -n 30)
PHP_EXECUTED="false"
# If it contains HTML and doesn't contain raw PHP tags, execution is successful
if echo "$ROOT_BODY" | grep -qi "<html" && ! echo "$ROOT_BODY" | grep -q "<?php"; then
    PHP_EXECUTED="true"
fi

# 5. Extract Security Headers (converting to lowercase and trimming for strict matching)
HEADERS=$(curl -s -I http://localhost/ | tr -d '\r' | tr '[:upper:]' '[:lower:]')
X_FRAME=$(echo "$HEADERS" | grep -i "^x-frame-options:" | cut -d':' -f2 | xargs || echo "")
X_CONTENT=$(echo "$HEADERS" | grep -i "^x-content-type-options:" | cut -d':' -f2 | xargs || echo "")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create JSON result securely via temp file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "apache2_state": "$APACHE_STATE",
    "nginx_state": "$NGINX_STATE",
    "phpfpm_state": "$PHPFPM_STATE",
    "root_status": "$ROOT_STATUS",
    "login_status": "$LOGIN_STATUS",
    "server_header": "$SERVER_HEADER",
    "php_executed": $PHP_EXECUTED,
    "x_frame_options": "$X_FRAME",
    "x_content_type_options": "$X_CONTENT",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location ensuring global read permissions for verifier script
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="