#!/bin/bash
echo "=== Exporting configure_audio_deterrence results ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Refresh token to ensure we can query API
refresh_nx_token > /dev/null 2>&1 || true

# Get the target camera ID (resolved during setup)
TARGET_ID=$(cat /tmp/target_camera_id.txt 2>/dev/null || echo "")

# If target ID is missing (shouldn't happen), try to resolve it again
if [ -z "$TARGET_ID" ]; then
    TARGET_ID=$(get_camera_id_by_name "Loading Dock Camera")
fi

echo "Target Camera ID: $TARGET_ID"

# Fetch all event rules currently in the system
echo "Fetching Event Rules..."
RULES_JSON=$(nx_api_get "/rest/v1/eventRules")

# Save raw rules for debug/verification
echo "$RULES_JSON" > /tmp/event_rules_dump.json

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create result JSON
# We embed the raw rules list so the Python verifier can parse it logic-fully
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 -c "
import json, os, time

rules_file = '/tmp/event_rules_dump.json'
target_id = '$TARGET_ID'
start_time = $TASK_START
end_time = $TASK_END

result = {
    'task_start': start_time,
    'task_end': end_time,
    'target_camera_id': target_id,
    'event_rules': [],
    'screenshot_path': '/tmp/task_final.png'
}

if os.path.exists(rules_file):
    try:
        with open(rules_file, 'r') as f:
            result['event_rules'] = json.load(f)
    except Exception as e:
        result['error'] = str(e)

print(json.dumps(result))
" > "$TEMP_JSON"

# Move to standard location with safe permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export Complete ==="