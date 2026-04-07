#!/bin/bash
set -e
echo "=== Setting up create_user_role task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure server is running
systemctl start networkoptix-mediaserver 2>/dev/null || true
sleep 5

# Refresh auth token
TOKEN=$(refresh_nx_token)
echo "Auth token refreshed"

# Record initial role count
INITIAL_ROLES=$(nx_api_get "/rest/v1/userRoles" | python3 -c "
import sys, json
try:
    roles = json.load(sys.stdin)
    print(len(roles) if isinstance(roles, list) else 0)
except:
    print(0)
" 2>/dev/null)
echo "$INITIAL_ROLES" > /tmp/initial_role_count.txt

# Delete any pre-existing "Night Shift Monitor" role (clean state)
echo "Checking for existing role..."
nx_api_get "/rest/v1/userRoles" | python3 -c "
import sys, json
try:
    roles = json.load(sys.stdin)
    for r in roles:
        if r.get('name','').lower() == 'night shift monitor':
            print(r.get('id',''))
except:
    pass
" 2>/dev/null | while read role_id; do
    if [ -n "$role_id" ]; then
        echo "Removing pre-existing Night Shift Monitor role: $role_id"
        nx_api_delete "/rest/v1/userRoles/${role_id}"
    fi
done

# Get Camera IDs for ground truth
PARKING_ID=$(get_camera_id_by_name "Parking Lot Camera")
ENTRANCE_ID=$(get_camera_id_by_name "Entrance Camera")

if [ -z "$PARKING_ID" ] || [ -z "$ENTRANCE_ID" ]; then
    echo "WARNING: Could not find required cameras. Waiting for cameras..."
    sleep 10
    PARKING_ID=$(get_camera_id_by_name "Parking Lot Camera")
    ENTRANCE_ID=$(get_camera_id_by_name "Entrance Camera")
fi

echo "Parking ID: $PARKING_ID"
echo "Entrance ID: $ENTRANCE_ID"

# Save expected IDs for export script to pick up later
mkdir -p /tmp/task_ground_truth
echo "$PARKING_ID" > /tmp/task_ground_truth/parking_id
echo "$ENTRANCE_ID" > /tmp/task_ground_truth/entrance_id
chmod 700 /tmp/task_ground_truth

# Open a terminal for the agent to work in
su - ga -c "DISPLAY=:1 xterm -geometry 120x40+0+0 -title 'Task Terminal' &" &
sleep 3

# Take screenshot of initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="