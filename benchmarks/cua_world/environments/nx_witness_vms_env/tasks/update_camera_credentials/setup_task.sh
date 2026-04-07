#!/bin/bash
set -e
echo "=== Setting up update_camera_credentials task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Remove any existing log file
rm -f /home/ga/camera_credential_update.log

# Ensure Nx Witness Server is up and we have a token
refresh_nx_token > /dev/null 2>&1 || true

# Wait for cameras to be available
echo "Checking for cameras..."
for i in {1..10}; do
    COUNT=$(count_cameras)
    if [ "$COUNT" -ge 3 ]; then
        echo "Found $COUNT cameras."
        break
    fi
    echo "Waiting for cameras... ($i/10)"
    sleep 3
done

# Ensure the specific cameras exist. If the environment setup didn't name them correctly,
# or if they were modified, we force rename the first 3 available cameras.
TARGET_NAMES=("Parking Lot Camera" "Entrance Camera" "Server Room Camera")
IDS=$(get_all_cameras | python3 -c "import sys, json; print(' '.join([d['id'] for d in json.load(sys.stdin)]))" 2>/dev/null || true)

if [ -n "$IDS" ]; then
    idx=0
    for cam_id in $IDS; do
        if [ $idx -lt 3 ]; then
            NAME="${TARGET_NAMES[$idx]}"
            echo "Ensuring camera $cam_id is named '$NAME'..."
            nx_api_patch "/rest/v1/devices/$cam_id" "{\"name\": \"$NAME\", \"credentials\": {\"user\": \"default_user\", \"password\": \"default_pass\"}}" > /dev/null
            idx=$((idx + 1))
        fi
    done
else
    echo "ERROR: No cameras found to configure!"
    exit 1
fi

# Ensure Firefox is open to the API documentation or dashboard to give a visual cue
ensure_firefox_running "https://localhost:7001/static/index.html#/settings/cameras"
sleep 5
maximize_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="