#!/bin/bash
set -e
echo "=== Setting up restore_camera_config task ==="

# Source utilities for API interaction
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Nx Server is up and we have a token
echo "Waiting for Nx Server..."
wait_for_nx_server 2>/dev/null || true
refresh_nx_token > /dev/null

# Get list of current cameras
echo "Fetching current cameras..."
CAMERAS_JSON=$(get_all_cameras)
CAMERA_COUNT=$(echo "$CAMERAS_JSON" | python3 -c "import sys, json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")

if [ "$CAMERA_COUNT" -lt 3 ]; then
    echo "WARNING: Not enough cameras found ($CAMERA_COUNT). Task requires at least 3."
    # In a real scenario, we might trigger a script to add virtual cameras here
fi

# Define the Target State (The "Correct" Configuration)
# We will map these onto the actual physical IDs found in the system
TARGET_NAMES=("Parking Lot Camera" "Entrance Camera" "Server Room Camera")
TARGET_LOGICAL_IDS=(101 102 103)
TARGET_FPS=(15 10 20)

# Define the Corrupted State (What the agent sees initially)
CORRUPT_NAMES=("cam_err_01" "TEMP_DEVICE_X" "DoNotUse_Broken")

# Create the Backup JSON structure
# We iterate through actual devices to get their stable physicalIds
BACKUP_JSON_CONTENT="{\"backupTimestamp\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\", \"cameras\": []}"

echo "Corrupting camera configurations and generating backup..."
IDX=0
for row in $(echo "$CAMERAS_JSON" | python3 -c "import sys, json; print('\n'.join([c['id'] + '|' + c['physicalId'] for c in json.load(sys.stdin)]))"); do
    if [ $IDX -ge 3 ]; then break; fi
    
    CAM_ID=$(echo "$row" | cut -d'|' -f1)
    PHYS_ID=$(echo "$row" | cut -d'|' -f2)
    
    TARGET_NAME="${TARGET_NAMES[$IDX]}"
    TARGET_LID="${TARGET_LOGICAL_IDS[$IDX]}"
    TARGET_FPS_VAL="${TARGET_FPS[$IDX]}"
    CORRUPT_NAME="${CORRUPT_NAMES[$IDX]}"

    echo "Processing Camera $IDX (ID: $CAM_ID)"

    # 1. Corrupt the system state
    # - Set garbage name
    # - Set logicalId to 0
    # - Disable recording
    nx_api_patch "/rest/v1/devices/${CAM_ID}" "{
        \"name\": \"${CORRUPT_NAME}\",
        \"logicalId\": \"0\",
        \"schedule\": {\"isEnabled\": false}
    }" > /dev/null
    
    # 2. Add correct config to backup JSON string
    # We use python to append to the json structure safely
    BACKUP_JSON_CONTENT=$(echo "$BACKUP_JSON_CONTENT" | python3 -c "
import sys, json
data = json.load(sys.stdin)
new_cam = {
    'physicalId': '$PHYS_ID',
    'name': '$TARGET_NAME',
    'logicalId': $TARGET_LID,
    'recording': {
        'enabled': True,
        'fps': $TARGET_FPS_VAL,
        'recordingType': 'always'
    }
}
data['cameras'].append(new_cam)
print(json.dumps(data))
")

    IDX=$((IDX + 1))
done

# Save the backup file
mkdir -p /home/ga/Documents
echo "$BACKUP_JSON_CONTENT" > /home/ga/Documents/camera_backup.json
chmod 666 /home/ga/Documents/camera_backup.json
chown ga:ga /home/ga/Documents/camera_backup.json

echo "Backup file created at /home/ga/Documents/camera_backup.json"

# Save initial state of relevant fields for verifying "change detected"
echo "$CAMERAS_JSON" > /tmp/initial_cameras_state.json

# Ensure Firefox is running and open to API docs or Settings
ensure_firefox_running "https://localhost:7001/static/index.html#/settings/cameras"
maximize_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="