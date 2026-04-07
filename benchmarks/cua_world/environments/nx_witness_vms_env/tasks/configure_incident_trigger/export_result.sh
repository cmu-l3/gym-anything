#!/bin/bash
echo "=== Exporting configure_incident_trigger results ==="

source /workspace/scripts/task_utils.sh

# Record end time
date +%s > /tmp/task_end_time.txt

# Capture final screenshot
take_screenshot /tmp/task_final.png

# 1. Fetch System State via API
# ----------------------------------------------------------------
refresh_nx_token > /dev/null 2>&1 || true

# Get all Event Rules
RULES_JSON=$(nx_api_get "/rest/v1/eventRules")

# Get Target Camera ID (saved during setup)
TARGET_CAMERA_ID=$(cat /tmp/target_camera_id.txt 2>/dev/null || echo "")

# Get App State
APP_RUNNING="false"
if pgrep -f "Nx Witness" > /dev/null || pgrep -f "applauncher" > /dev/null; then
    APP_RUNNING="true"
fi

# 2. Save Result to JSON
# ----------------------------------------------------------------
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "event_rules": $RULES_JSON,
    "target_camera_id": "$TARGET_CAMERA_ID",
    "app_running": $APP_RUNNING,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="