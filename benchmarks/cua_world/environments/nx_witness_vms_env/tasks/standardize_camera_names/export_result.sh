#!/bin/bash
set -e

echo "=== Exporting standardize_camera_names result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Refresh auth token
TOKEN=$(refresh_nx_token)

# Get current devices state
DEVICES_JSON=$(curl -sk "${NX_BASE}/rest/v1/devices" \
    -H "Authorization: Bearer ${TOKEN}" --max-time 15 2>/dev/null || echo "[]")

# Extract relevant data for verification
# We want a list of current names and the total count
CURRENT_STATE=$(echo "$DEVICES_JSON" | python3 -c "
import sys, json
try:
    devices = json.load(sys.stdin)
    names = [d.get('name', '') for d in devices]
    ids = [d.get('id', '') for d in devices]
    print(json.dumps({'names': names, 'ids': ids, 'count': len(devices)}))
except:
    print(json.dumps({'names': [], 'ids': [], 'count': 0}))
" 2>/dev/null)

# Get initial count
INITIAL_COUNT=$(cat /tmp/initial_camera_count.txt 2>/dev/null || echo "0")

# Check if application (server) is running
APP_RUNNING="false"
if systemctl is-active --quiet networkoptix-mediaserver; then
    APP_RUNNING="true"
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "initial_camera_count": $INITIAL_COUNT,
    "final_camera_state": $CURRENT_STATE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="