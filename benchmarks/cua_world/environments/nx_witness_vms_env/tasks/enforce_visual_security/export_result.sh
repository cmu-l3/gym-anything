#!/bin/bash
set -e
echo "=== Exporting enforce_visual_security results ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture Final Screenshot
echo "Capturing final state..."
take_screenshot /tmp/task_final.png

# 2. Query System Settings API for Verification
echo "Querying system settings..."
TOKEN=$(get_nx_token)

SETTINGS_JSON=$(curl -sk "${NX_BASE}/rest/v1/system/settings" \
    -H "Authorization: Bearer ${TOKEN}" \
    --max-time 10 2>/dev/null || echo "{}")

# 3. Check if Firefox is still running
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# 4. Create Result JSON
# We embed the raw API response into our result file for the python verifier to parse
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "system_settings": $SETTINGS_JSON
}
EOF

# 5. Move to accessible location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="