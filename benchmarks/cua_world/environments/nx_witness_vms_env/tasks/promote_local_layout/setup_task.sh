#!/bin/bash
set -e
echo "=== Setting up promote_local_layout task ==="

source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 1. Ensure Nx Server is up and we have a token
refresh_nx_token > /dev/null 2>&1 || true
TOKEN=$(get_nx_token)

if [ -z "$TOKEN" ]; then
    echo "ERROR: Failed to obtain auth token"
    exit 1
fi

# 2. Get Admin User ID (to make the layout private initially)
ADMIN_USER_ID=$(get_user_by_name "admin" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null)
echo "Admin User ID: $ADMIN_USER_ID"

# 3. Identify cameras to add to the layout
CAM1_ID=$(get_camera_id_by_name "Parking Lot Camera")
CAM2_ID=$(get_camera_id_by_name "Entrance Camera")

if [ -z "$CAM1_ID" ] || [ -z "$CAM2_ID" ]; then
    echo "WARNING: Could not find specific cameras, fetching any available..."
    CAM1_ID=$(get_first_camera_id)
fi

# 4. Create the target private layout 'Investigation_Board_Alpha'
LAYOUT_NAME="Investigation_Board_Alpha"

# Check if it exists and delete it to ensure clean state
EXISTING_LAYOUT=$(get_layout_by_name "$LAYOUT_NAME")
if [ -n "$EXISTING_LAYOUT" ] && [ "$EXISTING_LAYOUT" != "null" ]; then
    ID=$(echo "$EXISTING_LAYOUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))")
    echo "Deleting existing layout $ID..."
    nx_api_delete "/rest/v1/layouts/$ID"
    sleep 2
fi

echo "Creating private layout '$LAYOUT_NAME'..."
# Construct payload with camera items
# Note: item positions are simplified
PAYLOAD=$(cat <<EOF
{
  "name": "$LAYOUT_NAME",
  "parentId": "$ADMIN_USER_ID",
  "items": [
    {
      "resourceId": "$CAM1_ID",
      "flags": 0,
      "left": 0,
      "top": 0,
      "right": 0.5,
      "bottom": 0.5
    },
    {
      "resourceId": "$CAM2_ID",
      "flags": 0,
      "left": 0.5,
      "top": 0,
      "right": 1.0,
      "bottom": 0.5
    }
  ]
}
EOF
)

CREATE_RES=$(curl -sk -X POST "${NX_BASE}/rest/v1/layouts" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" --max-time 15)

echo "Layout creation response: $CREATE_RES"

# 5. Launch Desktop Client
# Kill existing
pkill -f "applauncher" 2>/dev/null || true
pkill -f "nxwitness" 2>/dev/null || true
sleep 2

# Launch
APPLAUNCHER=$(find /opt -name "applauncher" -type f 2>/dev/null | head -1)
if [ -n "$APPLAUNCHER" ]; then
    echo "Launching Nx Witness Desktop Client..."
    DISPLAY=:1 "$APPLAUNCHER" > /dev/null 2>&1 &
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "Nx Witness"; then
            echo "Client window detected."
            break
        fi
        sleep 1
    done
    
    # Maximize
    sleep 5
    DISPLAY=:1 wmctrl -r "Nx Witness" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    
    # Attempt to dismiss standard dialogs if they appear (EULA, Keyring)
    # (Simplified approach - agent usually handles interaction, but good to clear blockers)
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
else
    echo "WARNING: Desktop client binary not found!"
fi

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="