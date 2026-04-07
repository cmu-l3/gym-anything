#!/bin/bash
set -e
echo "=== Setting up configure_tiered_recording_policy task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# ============================================================
# 1. Ensure Nx Server is responsive and Auth is working
# ============================================================
refresh_nx_token > /dev/null 2>&1 || true
TOKEN=$(get_nx_token)

if [ -z "$TOKEN" ]; then
    echo "ERROR: Failed to authenticate with Nx Witness"
    exit 1
fi

# ============================================================
# 2. Ensure Required Cameras Exist
# ============================================================
REQUIRED_CAMERAS=("Entrance Camera" "Parking Lot Camera" "Lobby Camera" "Server Room Camera")
EXISTING_DEVICES=$(nx_api_get "/rest/v1/devices" 2>/dev/null)

echo "Checking for required cameras..."
# We rely on the environment setup to create virtual cameras.
# If names don't match exactly, we try to rename available cameras to match our scenario.

# Get list of current camera IDs and Names
echo "$EXISTING_DEVICES" | python3 -c "
import sys, json
try:
    devices = json.load(sys.stdin)
    # create map of id -> name
    current_map = {d['id']: d['name'] for d in devices}
    
    required = ['Entrance Camera', 'Parking Lot Camera', 'Lobby Camera', 'Server Room Camera']
    used_ids = []
    
    # First pass: find exact matches
    for req in required:
        found = False
        for did, dname in current_map.items():
            if dname == req:
                print(f'MATCH:{req}:{did}')
                used_ids.append(did)
                found = True
                break
    
    # Second pass: assign unused cameras to missing requirements
    for req in required:
        # Check if we already found it in pass 1
        already_found = False
        for did, dname in current_map.items():
             if dname == req: already_found = True
        
        if not already_found:
            for did, dname in current_map.items():
                if did not in used_ids:
                    print(f'RENAME:{did}:{req}')
                    used_ids.append(did)
                    break
except Exception as e:
    print(f'ERROR: {e}')
" > /tmp/camera_setup_plan.txt

# Execute renaming plan
while IFS=':' read -r ACTION ID NAME; do
    if [ "$ACTION" == "RENAME" ]; then
        echo "Renaming camera $ID to '$NAME'..."
        nx_api_patch "/rest/v1/devices/${ID}" "{\"name\": \"${NAME}\"}" > /dev/null
    fi
done < /tmp/camera_setup_plan.txt

# ============================================================
# 3. Reset Camera Schedules (Clean State)
# ============================================================
# We want the agent to do the work, so we reset schedules to a generic default
# (e.g., Recording Disabled or low quality default)

echo "Resetting camera schedules..."
RESET_PAYLOAD='{
    "schedule": {
        "isEnabled": false,
        "tasks": []
    }
}'

# Apply reset to all required cameras
for CAM_NAME in "${REQUIRED_CAMERAS[@]}"; do
    CAM_ID=$(get_camera_id_by_name "$CAM_NAME")
    if [ -n "$CAM_ID" ]; then
        nx_api_patch "/rest/v1/devices/${CAM_ID}" "$RESET_PAYLOAD" > /dev/null
        echo "Reset schedule for $CAM_NAME"
    fi
done

# ============================================================
# 4. Prepare UI
# ============================================================
# Remove any old report file
rm -f /home/ga/recording_policy_report.txt

# Open Firefox to the Cameras settings page
ensure_firefox_running "https://localhost:7001/static/index.html#/settings/cameras"
maximize_firefox

# Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="