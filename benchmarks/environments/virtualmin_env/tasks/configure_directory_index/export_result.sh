#!/bin/bash
echo "=== Exporting configure_directory_index result ==="

# Record task end
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Internal Verification: HTTP Checks (curl)
echo "Running HTTP checks..."

# Check 1: Root URL (Should be promo.html)
ROOT_HTTP_CODE=$(curl -s -o /tmp/root_response.txt -w "%{http_code}" http://acmecorp.test/)
ROOT_CONTENT=$(cat /tmp/root_response.txt)

if echo "$ROOT_CONTENT" | grep -q "PROMO_2024_LAUNCH"; then
    ROOT_SERVES_PROMO="true"
else
    ROOT_SERVES_PROMO="false"
fi

# Check 2: Assets Subdirectory (Should be 403 Forbidden)
# We grep for "Index of" to be sure it's NOT a listing, and check for 403
ASSETS_HTTP_CODE=$(curl -s -o /tmp/assets_response.txt -w "%{http_code}" http://acmecorp.test/assets/)
ASSETS_CONTENT=$(cat /tmp/assets_response.txt)

if [ "$ASSETS_HTTP_CODE" == "403" ]; then
    ASSETS_FORBIDDEN="true"
    ASSETS_SHOWS_INDEX="false"
elif echo "$ASSETS_CONTENT" | grep -q "Index of"; then
    ASSETS_FORBIDDEN="false"
    ASSETS_SHOWS_INDEX="true"
else
    ASSETS_FORBIDDEN="false"
    ASSETS_SHOWS_INDEX="false"
fi

# 2. Internal Verification: Config Inspection
echo "Inspecting configuration..."
CONF_FILE="/etc/apache2/sites-available/acmecorp.test.conf"
CONF_CONTENT=""
if [ -f "$CONF_FILE" ]; then
    CONF_CONTENT=$(cat "$CONF_FILE" | base64 -w 0)
fi

# Check if file was modified
FILE_MODIFIED="false"
if [ -f "$CONF_FILE" ]; then
    MOD_TIME=$(stat -c %Y "$CONF_FILE")
    if [ "$MOD_TIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# 3. Take Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 4. Generate JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "root_http_code": "$ROOT_HTTP_CODE",
    "root_serves_promo": $ROOT_SERVES_PROMO,
    "assets_http_code": "$ASSETS_HTTP_CODE",
    "assets_forbidden": $ASSETS_FORBIDDEN,
    "assets_shows_index": $ASSETS_SHOWS_INDEX,
    "config_file_modified": $FILE_MODIFIED,
    "config_content_b64": "$CONF_CONTENT",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Safe move
rm -f /tmp/task_result.json 2>/dev/null
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="