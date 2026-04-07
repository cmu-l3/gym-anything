#!/bin/bash
set -e

echo "=== Setting up standardize_camera_names task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Nx Witness server is running
systemctl start networkoptix-mediaserver 2>/dev/null || true
wait_for_nx_server 2>/dev/null || sleep 5

# Refresh auth token
TOKEN=$(refresh_nx_token)

echo "=== Resetting Camera Names to Initial State ==="

# Get current devices
DEVICES_JSON=$(curl -sk "${NX_BASE}/rest/v1/devices" \
    -H "Authorization: Bearer ${TOKEN}" --max-time 15 2>/dev/null || echo "[]")

# Define the informal names we want to start with
# We map loosely based on what we find, or rename logically if we can't identify
# For this setup, we'll rename the first few cameras found to the "Old" names
# to ensure the agent has the correct starting state.

CAMERA_NAMES=("Parking Lot Camera" "Entrance Camera" "Server Room Camera" "Lobby Camera" "Loading Dock Camera")

echo "$DEVICES_JSON" | python3 -c "
import sys, json
try:
    devices = json.load(sys.stdin)
    # Sort by ID to be deterministic
    devices.sort(key=lambda x: x.get('id', ''))
    for d in devices:
        print(d.get('id', ''))
except:
    pass
" 2>/dev/null | {
    IDX=0
    while read device_id; do
        if [ -n "$device_id" ] && [ $IDX -lt 5 ]; then
            CAMERA_NAME="${CAMERA_NAMES[$IDX]}"
            echo "  Resetting camera $device_id to: $CAMERA_NAME"
            curl -sk -X PATCH "${NX_BASE}/rest/v1/devices/${device_id}" \
                -H "Authorization: Bearer ${TOKEN}" \
                -H "Content-Type: application/json" \
                -d "{\"name\": \"${CAMERA_NAME}\"}" \
                --max-time 15 2>/dev/null || true
            IDX=$((IDX + 1))
        fi
    done
}

# Record initial state for verification
# We fetch the list AGAIN to be sure of what we have
FINAL_DEVICES_JSON=$(curl -sk "${NX_BASE}/rest/v1/devices" \
    -H "Authorization: Bearer ${TOKEN}" --max-time 15 2>/dev/null || echo "[]")

# Save initial count
INITIAL_COUNT=$(echo "$FINAL_DEVICES_JSON" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(len(d) if isinstance(d, list) else 0)
except:
    print(0)
" 2>/dev/null)
echo "$INITIAL_COUNT" > /tmp/initial_camera_count.txt
echo "Initial camera count: $INITIAL_COUNT"

# Save initial names (for debugging/audit)
echo "$FINAL_DEVICES_JSON" | python3 -c "
import sys, json
try:
    devices = json.load(sys.stdin)
    names = [d.get('name', '') for d in devices]
    print(json.dumps(names))
except:
    print('[]')
" > /tmp/initial_camera_names.json

# Open Firefox to the cameras page to give the agent a visual starting point
ensure_firefox_running "https://localhost:7001/static/index.html#/settings/cameras"
sleep 5
maximize_firefox

# Take initial state screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="