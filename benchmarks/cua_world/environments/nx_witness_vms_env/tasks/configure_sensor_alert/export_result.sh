#!/bin/bash
echo "=== Exporting configure_sensor_alert results ==="

source /workspace/scripts/task_utils.sh

# Refresh token for queries
refresh_nx_token > /dev/null 2>&1 || true

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TARGET_CAM_ID=$(cat /tmp/target_camera_id.txt 2>/dev/null || echo "")

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Extract Event Rules
echo "Querying Event Rules..."
RULES_JSON=$(nx_api_get "/rest/v1/eventRules")

# 3. Extract Bookmarks (created after start time)
echo "Querying Bookmarks..."
# Nx Witness Bookmark API takes startTimeMs.
# Task start is in seconds, convert to ms.
START_MS=$((TASK_START * 1000))
BOOKMARKS_JSON=$(nx_api_get "/rest/v1/bookmarks?filter=startTime=${START_MS}&deviceId=${TARGET_CAM_ID}")

# 4. Verify System State (Is camera still there?)
CAM_INFO=$(nx_api_get "/rest/v1/devices/${TARGET_CAM_ID}" 2>/dev/null || echo "{}")

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 -c "
import json, sys, os

try:
    rules = json.loads('''$RULES_JSON''')
except:
    rules = []

try:
    bookmarks = json.loads('''$BOOKMARKS_JSON''')
except:
    bookmarks = []

try:
    cam_info = json.loads('''$CAM_INFO''')
except:
    cam_info = {}

result = {
    'rules': rules,
    'bookmarks': bookmarks,
    'camera': cam_info,
    'task_start_ts': $TASK_START,
    'target_camera_id': '$TARGET_CAM_ID'
}

print(json.dumps(result, indent=2))
" > "$TEMP_JSON"

# Move to standard location with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result summary:"
grep -oE '"(rules|bookmarks)": \[[^]]*\]' /tmp/task_result.json | head -n 5