#!/bin/bash
set -e
echo "=== Setting up remove_camera task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create audit directory
mkdir -p /home/ga/audit
chown -R ga:ga /home/ga/audit
# Remove any existing audit file to ensure freshness
rm -f /home/ga/audit/camera_removal.txt

# Stop testcamera to prevent automatic re-discovery of deleted cameras
# (The existing cameras will remain in the DB but go offline, which is fine for deletion)
echo "Stopping testcamera service..."
pkill -f testcamera 2>/dev/null || true
sleep 2

# Refresh auth token
NX_TOKEN=$(refresh_nx_token)

# Ensure 'Server Room Camera' exists
TARGET_NAME="Server Room Camera"
TARGET_CAM=$(get_camera_by_name "$TARGET_NAME")

# If not found (unlikely given env setup), try to rename the first available camera
if [ -z "$TARGET_CAM" ] || [ "$TARGET_CAM" == "null" ]; then
    echo "Target camera not found, attempting to rename a camera..."
    FIRST_ID=$(get_first_camera_id)
    if [ -n "$FIRST_ID" ]; then
        nx_api_patch "/rest/v1/devices/${FIRST_ID}" "{\"name\": \"$TARGET_NAME\"}"
        TARGET_CAM=$(get_camera_by_name "$TARGET_NAME")
    fi
fi

# Capture the ID for verification
if [ -n "$TARGET_CAM" ] && [ "$TARGET_CAM" != "null" ]; then
    TARGET_ID=$(echo "$TARGET_CAM" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))")
    echo "Target Camera ID: $TARGET_ID"
    echo "$TARGET_ID" > /tmp/target_camera_id.txt
    
    # Also record initial total count
    INITIAL_COUNT=$(count_cameras)
    echo "$INITIAL_COUNT" > /tmp/initial_camera_count.txt
else
    echo "CRITICAL ERROR: Could not establish Server Room Camera. Task may fail."
    echo "0" > /tmp/initial_camera_count.txt
    echo "" > /tmp/target_camera_id.txt
fi

# Open Firefox to the cameras page
ensure_firefox_running "https://localhost:7001/static/index.html#/settings/cameras"
sleep 5
dismiss_ssl_warning
sleep 1
maximize_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="