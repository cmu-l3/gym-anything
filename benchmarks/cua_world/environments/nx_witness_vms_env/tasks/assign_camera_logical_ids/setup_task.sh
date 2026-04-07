#!/bin/bash
set -e
echo "=== Setting up task: Assign Logical IDs to Cameras ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# Ensure server is running
systemctl start networkoptix-mediaserver 2>/dev/null || true
wait_for_nx_server

# Refresh authentication token
TOKEN=$(refresh_nx_token)
if [ -z "$TOKEN" ]; then
    echo "ERROR: Failed to get auth token. Retrying..."
    sleep 5
    TOKEN=$(refresh_nx_token)
fi

# Wait for cameras to be available
echo "Checking for cameras..."
for attempt in $(seq 1 12); do
    CAM_COUNT=$(count_cameras)
    echo "Camera count: $CAM_COUNT (attempt $attempt)"
    if [ "$CAM_COUNT" -ge 3 ]; then
        break
    fi
    sleep 5
done

if [ "$CAM_COUNT" -lt 3 ]; then
    echo "WARNING: Fewer than 3 cameras found. Task may be impossible."
fi

# Reset ALL logical IDs to 0 (clean state)
echo "Resetting all logical IDs to 0..."
DEVICES_JSON=$(nx_api_get "/rest/v1/devices")
echo "$DEVICES_JSON" | python3 -c "
import sys, json
try:
    devices = json.load(sys.stdin)
    for d in devices:
        did = d.get('id', '')
        if did:
            print(did)
except:
    pass
" 2>/dev/null | while read device_id; do
    if [ -n "$device_id" ]; then
        nx_api_patch "/rest/v1/devices/${device_id}" '{"logicalId": 0}' > /dev/null 2>&1 || true
    fi
done
sleep 2

# Record initial state for verification
INITIAL_DEVICES=$(nx_api_get "/rest/v1/devices")
echo "$INITIAL_DEVICES" > /tmp/initial_devices.json

# Start Firefox with API documentation or Web Admin as a helpful reference
# (The task is API-based, but having the web UI available is realistic context)
ensure_firefox_running "https://localhost:7001/static/index.html#/settings/cameras"
sleep 3
dismiss_ssl_warning
sleep 2
maximize_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="