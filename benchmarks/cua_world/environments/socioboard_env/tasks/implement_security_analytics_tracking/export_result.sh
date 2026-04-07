#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 1. Check security.txt presence and HTTP status
SEC_FILE="/opt/socioboard/socioboard-web-php/public/.well-known/security.txt"
SEC_CREATED_DURING_TASK="false"

if [ -f "$SEC_FILE" ]; then
    SEC_MTIME=$(stat -c %Y "$SEC_FILE" 2>/dev/null || echo "0")
    if [ "$SEC_MTIME" -gt "$TASK_START" ]; then
        SEC_CREATED_DURING_TASK="true"
    fi
fi

SEC_HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/.well-known/security.txt || echo "000")
# Base64 encode the content to safely pass it in JSON without breaking formatting
SEC_CONTENT_B64=$(curl -s http://localhost/.well-known/security.txt | head -n 20 | base64 -w 0 || echo "")

# 2. Check Homepage and Tracking Snippet
HOME_HTTP_CODE=$(curl -sL -o /dev/null -w "%{http_code}" http://localhost/ || echo "000")
curl -sL http://localhost/ > /tmp/home_page.html 2>/dev/null
HOME_SIZE=$(stat -c %s /tmp/home_page.html 2>/dev/null || echo "0")

TRACKING_EXISTS="false"
if grep -q "SOCIOBOARD_CUSTOM_TRACKING_V1" /tmp/home_page.html 2>/dev/null; then
    TRACKING_EXISTS="true"
fi

APP_HEALTHY="false"
# Checking for standard keywords to ensure it's still the Socioboard app and not a dummy HTML file
if grep -qi "socioboard\|csrf-token\|<form" /tmp/home_page.html 2>/dev/null; then
    APP_HEALTHY="true"
fi

# Create JSON result (use temp file for permission safety)
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "sec_created_during_task": $SEC_CREATED_DURING_TASK,
    "sec_http_code": "$SEC_HTTP_CODE",
    "sec_content_b64": "$SEC_CONTENT_B64",
    "home_http_code": "$HOME_HTTP_CODE",
    "home_size_bytes": $HOME_SIZE,
    "tracking_exists": $TRACKING_EXISTS,
    "app_healthy": $APP_HEALTHY,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="