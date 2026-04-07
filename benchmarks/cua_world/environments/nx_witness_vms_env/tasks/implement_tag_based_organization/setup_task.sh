#!/bin/bash
set -e
echo "=== Setting up implement_tag_based_organization task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Refresh auth token to ensure API access
refresh_nx_token > /dev/null 2>&1 || true

# ==============================================================================
# 1. Ensure Cameras Exist and are Renamed Correctly
# ==============================================================================
echo "Configuring cameras..."
# We need 5 specific cameras. We'll rename existing ones or fail if not enough.
# The base env setup creates 5 cameras, usually named. We enforce names here.
REQUIRED_NAMES=("Parking Lot Camera" "Loading Dock Camera" "Entrance Camera" "Server Room Camera" "Lobby Camera")
IDS_FILE="/tmp/camera_ids.json"

# Get all devices
DEVICES_JSON=$(nx_api_get "/rest/v1/devices")

# Map existing IDs to new names
echo "$DEVICES_JSON" | python3 -c "
import sys, json
try:
    devices = json.load(sys.stdin)
    # Sort by ID to be deterministic
    devices.sort(key=lambda x: x.get('id'))
    
    required = ${REQUIRED_NAMES[@] as json_array_placeholder_fix_below}
    required = ['Parking Lot Camera', 'Loading Dock Camera', 'Entrance Camera', 'Server Room Camera', 'Lobby Camera']
    
    mapping = {}
    for i, req_name in enumerate(required):
        if i < len(devices):
            mapping[devices[i]['id']] = req_name
            
    print(json.dumps(mapping))
except Exception as e:
    print('{}')
" > "$IDS_FILE"

# Apply renames via API
while read -r cam_id cam_name; do
    # Remove quotes
    cam_id=$(echo "$cam_id" | tr -d '"')
    cam_name=$(echo "$cam_name" | tr -d '"')
    
    if [ -n "$cam_id" ]; then
        echo "Renaming camera $cam_id to '$cam_name'"
        nx_api_patch "/rest/v1/devices/${cam_id}" "{\"name\": \"$cam_name\"}" > /dev/null 2>&1 || true
        
        # CLEAR TAGS (userAttributes) to ensure clean state
        # userAttributes is where tags are stored in Nx Witness
        nx_api_patch "/rest/v1/devices/${cam_id}" "{\"userAttributes\": {\"deviceTags\": \"\"}}" > /dev/null 2>&1 || true
    fi
done < <(jq -r 'to_entries[] | "\(.key) \(.value)"' "$IDS_FILE")

# ==============================================================================
# 2. Cleanup Existing Layouts
# ==============================================================================
echo "Cleaning up layouts..."
LAYOUT_ID=$(get_layout_by_name "Storm Watch" | python3 -c "import sys, json; print(json.load(sys.stdin).get('id', ''))" 2>/dev/null || true)

if [ -n "$LAYOUT_ID" ] && [ "$LAYOUT_ID" != "null" ]; then
    echo "Deleting existing 'Storm Watch' layout ($LAYOUT_ID)..."
    nx_api_delete "/rest/v1/layouts/${LAYOUT_ID}"
fi

# ==============================================================================
# 3. Setup Agent Environment (Firefox)
# ==============================================================================
echo "Launching Firefox..."
# Start at the cameras list which is relevant for tagging
ensure_firefox_running "https://localhost:7001/static/index.html#/settings/cameras"
sleep 5
maximize_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="