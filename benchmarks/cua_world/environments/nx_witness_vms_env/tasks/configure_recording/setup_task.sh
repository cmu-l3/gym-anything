#!/bin/bash
echo "=== Setting up configure_camera_settings task ==="

source /workspace/scripts/task_utils.sh

# Refresh auth token
refresh_nx_token > /dev/null 2>&1 || true

# Get the Parking Lot Camera ID
FIRST_CAMERA_ID=$(get_camera_id_by_name "Parking Lot Camera" 2>/dev/null || get_first_camera_id 2>/dev/null || true)
echo "Parking Lot Camera ID: $FIRST_CAMERA_ID"
echo "$FIRST_CAMERA_ID" > /tmp/nx_target_camera_id.txt

# Reset camera to default rotation (0) and audio disabled — clear start state for agent
if [ -n "$FIRST_CAMERA_ID" ]; then
    echo "Resetting Parking Lot Camera to default settings..."
    nx_api_patch "/rest/v1/devices/${FIRST_CAMERA_ID}" '{
        "options": {
            "isAudioEnabled": false
        }
    }' > /dev/null || true
    echo "Camera settings reset"

    # Get camera info for confirmation
    CAMERA_INFO=$(nx_api_get "/rest/v1/devices/${FIRST_CAMERA_ID}" 2>/dev/null || echo "{}")
    CAMERA_NAME=$(echo "$CAMERA_INFO" | python3 -c "import sys,json; print(json.load(sys.stdin).get('name','Unknown'))" 2>/dev/null || echo "Unknown")
    echo "Target camera: $CAMERA_NAME (ID: $FIRST_CAMERA_ID)"
fi

# Navigate Firefox directly to the Parking Lot Camera's detail page
if [ -n "$FIRST_CAMERA_ID" ]; then
    CAMERA_URL="https://localhost:7001/static/index.html#/settings/cameras/${FIRST_CAMERA_ID}"
    ensure_firefox_running "$CAMERA_URL"
else
    ensure_firefox_running "https://localhost:7001/static/index.html#/settings/cameras"
fi
sleep 5
maximize_firefox

# Take initial screenshot
take_screenshot /tmp/nx_configure_recording_start.png

echo "=== configure_camera_settings task setup complete ==="
echo "Task: Set Rotation=90 and enable Audio for 'Parking Lot Camera' via Web Admin"
echo "Camera ID: $FIRST_CAMERA_ID"
