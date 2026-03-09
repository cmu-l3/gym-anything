#!/bin/bash
echo "=== Exporting Fix .htaccess Result ==="

source /workspace/scripts/task_utils.sh

DOMAIN="debug-practice.test"
USER="debug-practice"
HTACCESS_PATH="/home/$USER/public_html/.htaccess"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Functional Checks via HTTP
# Check Root URL
ROOT_HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://${DOMAIN}/")
ROOT_CONTENT=$(curl -s "http://${DOMAIN}/" | grep "System Operational" || echo "")

# Check Redirect URL (should be 301)
REDIRECT_HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://${DOMAIN}/old-page")
# Check where it redirects to
REDIRECT_LOC=$(curl -s -I "http://${DOMAIN}/old-page" | grep -i "Location:" | awk '{print $2}' | tr -d '\r')

echo "Root Status: $ROOT_HTTP_CODE"
echo "Redirect Status: $REDIRECT_HTTP_CODE"
echo "Redirect Location: $REDIRECT_LOC"

# 2. File Checks
HTACCESS_EXISTS="false"
HTACCESS_CONTENT=""
FILE_MODIFIED_DURING_TASK="false"

if [ -f "$HTACCESS_PATH" ]; then
    HTACCESS_EXISTS="true"
    # Read content for verifier to check syntax
    HTACCESS_CONTENT=$(cat "$HTACCESS_PATH" | base64 -w 0)
    
    # Check timestamp
    FILE_MTIME=$(stat -c %Y "$HTACCESS_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED_DURING_TASK="true"
    fi
fi

# 3. Take final screenshot
take_screenshot /tmp/task_final.png

# 4. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "root_http_code": "$ROOT_HTTP_CODE",
    "root_content_found": "$ROOT_CONTENT",
    "redirect_http_code": "$REDIRECT_HTTP_CODE",
    "redirect_location": "$REDIRECT_LOC",
    "htaccess_exists": $HTACCESS_EXISTS,
    "htaccess_content_b64": "$HTACCESS_CONTENT",
    "file_modified_during_task": $FILE_MODIFIED_DURING_TASK,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="