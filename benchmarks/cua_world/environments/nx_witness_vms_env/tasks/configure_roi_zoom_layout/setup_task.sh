#!/bin/bash
set -e
echo "=== Setting up Configure ROI Zoom Layout task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 1. Ensure Nx Witness Server is up and we have a token
refresh_nx_token > /dev/null 2>&1 || true

# 2. Verify 'Lobby Camera' exists and get its ID
LOBBY_CAM_ID=$(get_camera_id_by_name "Lobby Camera")

if [ -z "$LOBBY_CAM_ID" ]; then
    echo "WARNING: 'Lobby Camera' not found. Renaming a spare camera..."
    # Fallback: Find the first available camera and rename it
    SPARE_ID=$(get_first_camera_id)
    if [ -n "$SPARE_ID" ]; then
        nx_api_patch "/rest/v1/devices/${SPARE_ID}" '{"name": "Lobby Camera"}' > /dev/null
        LOBBY_CAM_ID="$SPARE_ID"
        echo "Renamed camera $SPARE_ID to 'Lobby Camera'"
    else
        echo "ERROR: No cameras available in system!"
        exit 1
    fi
fi
echo "Target Camera ID: $LOBBY_CAM_ID"
echo "$LOBBY_CAM_ID" > /tmp/target_camera_id.txt

# 3. Clean up: Delete the layout if it already exists from a previous run
LAYOUT_NAME="Lobby POS Monitor"
EXISTING_LAYOUT=$(get_layout_by_name "$LAYOUT_NAME")
if [ -n "$EXISTING_LAYOUT" ]; then
    LAYOUT_ID=$(echo "$EXISTING_LAYOUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))")
    if [ -n "$LAYOUT_ID" ]; then
        echo "Removing existing layout '$LAYOUT_NAME' (ID: $LAYOUT_ID)..."
        nx_api_delete "/rest/v1/layouts/${LAYOUT_ID}"
    fi
fi

# 4. Open Firefox to the API documentation or Web Admin to give the agent context
# We open the API docs or a generic admin page since fine-grained layout creation often requires API
ensure_firefox_running "https://localhost:7001/static/index.html#/settings/cameras"
maximize_firefox

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="
echo "Target: Create layout '$LAYOUT_NAME' for camera '$LOBBY_CAM_ID'"