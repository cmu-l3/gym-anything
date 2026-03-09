#!/bin/bash
set -e
echo "=== Exporting configure_guidelines_page results ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Identify web container
WEB_CONTAINER=$(cat /tmp/web_container_name.txt 2>/dev/null || docker ps --format '{{.Names}}' | grep -i web | head -1)

# 1. Check HTTP Accessibility and Content
echo "Checking HTTP response..."
HTTP_CODE=$(curl -s -o /tmp/guidelines_response.html -w "%{http_code}" "http://localhost:8080/guidelines" 2>/dev/null || echo "000")
echo "HTTP Code: $HTTP_CODE"

# 2. Check File inside Container
echo "Checking file in container..."
CONTAINER_FILE_EXISTS="false"
if [ -n "$WEB_CONTAINER" ]; then
    if docker exec "$WEB_CONTAINER" test -f /usr/share/jitsi-meet/guidelines.html; then
        CONTAINER_FILE_EXISTS="true"
    fi
fi

# 3. Check Backup File
echo "Checking backup file..."
BACKUP_PATH="/home/ga/guidelines.html"
BACKUP_EXISTS="false"
BACKUP_SIZE="0"
BACKUP_CREATED_DURING_TASK="false"

if [ -f "$BACKUP_PATH" ]; then
    BACKUP_EXISTS="true"
    BACKUP_SIZE=$(stat -c%s "$BACKUP_PATH" 2>/dev/null || echo "0")
    BACKUP_MTIME=$(stat -c%Y "$BACKUP_PATH" 2>/dev/null || echo "0")
    if [ "$BACKUP_MTIME" -gt "$TASK_START" ]; then
        BACKUP_CREATED_DURING_TASK="true"
    fi
fi

# 4. Check Nginx Config
echo "Checking Nginx config..."
NGINX_CONFIG_FOUND="false"
NGINX_CONTENT=""
if [ -n "$WEB_CONTAINER" ]; then
    # Try to cat common config locations to see if 'guidelines' is mentioned
    NGINX_CONTENT=$(docker exec "$WEB_CONTAINER" grep -r "guidelines" /etc/nginx/ 2>/dev/null || echo "")
    if [ -n "$NGINX_CONTENT" ]; then
        NGINX_CONFIG_FOUND="true"
    fi
fi

# 5. Take Final Screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/task_final.png

# 6. Prepare Response Body for verification (safe copy)
cp /tmp/guidelines_response.html /tmp/task_response_body.html 2>/dev/null || touch /tmp/task_response_body.html
chmod 666 /tmp/task_response_body.html

# 7. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "http_status": "$HTTP_CODE",
    "container_file_exists": $CONTAINER_FILE_EXISTS,
    "backup_exists": $BACKUP_EXISTS,
    "backup_created_during_task": $BACKUP_CREATED_DURING_TASK,
    "backup_size": $BACKUP_SIZE,
    "nginx_config_found": $NGINX_CONFIG_FOUND,
    "initial_http_status": "$(cat /tmp/initial_guidelines_status.txt 2>/dev/null || echo 'unknown')",
    "web_container": "$WEB_CONTAINER"
}
EOF

# Save result with correct permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="
cat /tmp/task_result.json