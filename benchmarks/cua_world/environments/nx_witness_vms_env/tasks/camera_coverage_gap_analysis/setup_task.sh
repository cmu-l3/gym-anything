#!/bin/bash
echo "=== Setting up Camera Coverage Gap Analysis Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Firefox is closed to free up resources (this is an API task primarily)
pkill -f firefox 2>/dev/null || true

# Refresh auth token
echo "Refreshing auth token..."
refresh_nx_token > /dev/null

# ------------------------------------------------------------------
# CONFIGURATION: Create specific gaps for the agent to find
# ------------------------------------------------------------------

# 1. SETUP CAMERAS (Ensure we have cameras)
echo "Ensuring cameras exist..."
CAMERAS=$(get_all_cameras)
CAM_COUNT=$(echo "$CAMERAS" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")

if [ "$CAM_COUNT" -lt 3 ]; then
    echo "WARNING: Not enough cameras found. Waiting for cameras..."
    sleep 10
fi

# 2. GAP 1: Disable recording on 'Server Room Camera'
echo "Creating Gap 1: Disabling recording for 'Server Room Camera'..."
SERVER_CAM_ID=$(get_camera_id_by_name "Server Room Camera")
if [ -n "$SERVER_CAM_ID" ]; then
    # Disable recording schedule
    nx_api_patch "/rest/v1/devices/${SERVER_CAM_ID}" '{
        "schedule": {
            "isEnabled": false,
            "tasks": []
        }
    }' > /dev/null
    echo "Recording disabled for Server Room Camera ($SERVER_CAM_ID)"
else
    echo "WARNING: Server Room Camera not found"
fi

# Ensure 'Entrance Camera' IS recording (for contrast)
ENTRANCE_CAM_ID=$(get_camera_id_by_name "Entrance Camera")
if [ -n "$ENTRANCE_CAM_ID" ]; then
    enable_recording_for_camera "$ENTRANCE_CAM_ID" 15 > /dev/null
fi

# 3. GAP 2: Cameras not in Layout
# Create a layout that includes only specific cameras
echo "Creating Gap 2: Configuring Layouts..."

# Delete existing layouts to start clean
LAYOUTS=$(get_all_layouts)
echo "$LAYOUTS" | python3 -c "import sys,json; ids=[l['id'] for l in json.load(sys.stdin)]; print(' '.join(ids))" | xargs -n1 -I{} bash -c "nx_api_delete /rest/v1/layouts/{}" 2>/dev/null || true

# Create 'Main Security View' layout with Entrance and Parking, BUT EXCLUDING 'Loading Dock Camera'
LOADING_DOCK_ID=$(get_camera_id_by_name "Loading Dock Camera")
PARKING_ID=$(get_camera_id_by_name "Parking Lot Camera")

if [ -n "$ENTRANCE_CAM_ID" ] && [ -n "$PARKING_ID" ]; then
    # Create layout items for Entrance and Parking
    ITEMS="[
        {\"resourceId\":\"${ENTRANCE_CAM_ID}\",\"id\":\"{11111111-1111-1111-1111-111111111111}\",\"zoomRect\":{\"left\":0,\"top\":0,\"width\":1,\"height\":1}},
        {\"resourceId\":\"${PARKING_ID}\",\"id\":\"{22222222-2222-2222-2222-222222222222}\",\"zoomRect\":{\"left\":0,\"top\":0,\"width\":1,\"height\":1}}
    ]"
    
    # Create the layout
    nx_api_post "/rest/v1/layouts" "{
        \"name\": \"Main Security View\",
        \"items\": $ITEMS
    }" > /dev/null
    echo "Created 'Main Security View' (Excludes Loading Dock Camera)"
fi

# 4. GAP 3: User without layouts
echo "Creating Gap 3: Creating user without layouts..."
# Create 'nightshift_operator'
nx_api_post "/rest/v1/users" '{
    "name": "nightshift_operator",
    "fullName": "Night Shift",
    "email": "night@test.local",
    "password": "Password123!",
    "userRoleId": "{00000000-0000-0000-0000-000000000002}", 
    "isEnabled": true
}' > /dev/null
echo "Created user 'nightshift_operator' (Viewer role)"

# Ensure admin has layouts (our Main Security View is owned by admin by default)

# ------------------------------------------------------------------
# SNAPSHOT STATE FOR DEBUGGING
# ------------------------------------------------------------------
DISPLAY=:1 wmctrl -r "Nx Witness" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take setup screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="