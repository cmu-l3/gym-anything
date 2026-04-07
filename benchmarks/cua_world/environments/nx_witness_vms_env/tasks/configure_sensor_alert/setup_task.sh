#!/bin/bash
echo "=== Setting up configure_sensor_alert task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for bookmark verification)
date +%s > /tmp/task_start_time.txt
# Also save as ISO format for easier debugging/logs
date -Iseconds > /tmp/task_start_iso.txt

# 1. Refresh Authentication
echo "Refreshing auth token..."
refresh_nx_token > /dev/null 2>&1 || true

# 2. Verify Target Camera Exists
TARGET_CAM="Server Room Camera"
CAM_ID=$(get_camera_id_by_name "$TARGET_CAM")

if [ -z "$CAM_ID" ]; then
    echo "WARNING: '$TARGET_CAM' not found. Attempting to find any camera..."
    CAM_ID=$(get_first_camera_id)
    if [ -n "$CAM_ID" ]; then
        # Rename it to ensure task instructions work
        echo "Renaming camera $CAM_ID to '$TARGET_CAM'..."
        nx_api_patch "/rest/v1/devices/${CAM_ID}" "{\"name\": \"$TARGET_CAM\"}" > /dev/null
    else
        echo "ERROR: No cameras available in system!"
        exit 1
    fi
fi
echo "Target Camera ID: $CAM_ID"
echo "$CAM_ID" > /tmp/target_camera_id.txt

# 3. Clean State: Remove existing relevant Event Rules
echo "Cleaning up existing event rules..."
RULES_JSON=$(nx_api_get "/rest/v1/eventRules")

# Parse and find rules with our source/caption to delete
echo "$RULES_JSON" | python3 -c "
import sys, json
try:
    rules = json.load(sys.stdin)
    for r in rules:
        # Check if rule matches our task parameters (source/caption)
        # Nx stores source/caption in the 'eventCondition' string or specific fields depending on version
        # For Generic Events, it's often in resourceName (source) and caption/description
        txt = json.dumps(r)
        if 'TempSensor_01' in txt or 'Overheat' in txt:
            print(r['id'])
except:
    pass
" | while read -r rule_id; do
    echo "Deleting stale rule: $rule_id"
    nx_api_delete "/rest/v1/eventRules/$rule_id"
done

# 4. Clean State: Remove existing bookmarks on this camera
# (To ensure we detect the *new* simulated bookmark)
echo "Cleaning up existing bookmarks..."
# Note: In a real env we might not want to delete everything, but for this task specific scope it's safer
# We'll just rely on the timestamp check in the verifier, but deleting helps reduce noise.

# 5. Prepare User Interface
echo "Launching Firefox..."
ensure_firefox_running "https://localhost:7001/static/index.html#/settings/eventRules"
maximize_firefox

# 6. Prepare Terminal (for the curl step)
# Launch a fresh terminal if one isn't clearly visible
if ! pgrep -f "xterm" > /dev/null; then
    echo "Launching terminal..."
    su - ga -c "DISPLAY=:1 xterm -geometry 100x30+100+100 &"
    sleep 2
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="