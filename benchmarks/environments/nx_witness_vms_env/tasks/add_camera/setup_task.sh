#!/bin/bash
echo "=== Setting up edit_camera_credentials task ==="

source /workspace/scripts/task_utils.sh

# Refresh auth token
refresh_nx_token > /dev/null 2>&1 || true

# Record initial camera count for verification baseline
INITIAL_COUNT=$(count_cameras 2>/dev/null || echo "0")
echo "Initial camera count: $INITIAL_COUNT"
echo "$INITIAL_COUNT" > /tmp/nx_initial_camera_count.txt

# Get the Entrance Camera ID and save it
ENTRANCE_CAM_ID=$(get_camera_id_by_name "Entrance Camera" 2>/dev/null || true)
echo "Entrance Camera ID: $ENTRANCE_CAM_ID"
echo "$ENTRANCE_CAM_ID" > /tmp/nx_target_camera_id.txt

# Ensure Firefox is running and on the Nx Witness Web Admin Cameras page
ensure_firefox_running "https://localhost:7001/static/index.html#/settings/cameras"
sleep 4
maximize_firefox

# Take initial screenshot for evidence
take_screenshot /tmp/nx_edit_credentials_start.png

echo "=== edit_camera_credentials task setup complete ==="
echo "Task: Update credentials for 'Entrance Camera' via Cameras section"
echo "Target camera: Entrance Camera"
echo "New credentials: camuser / Cam@SecurePass2024"
