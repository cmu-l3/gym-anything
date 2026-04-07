#!/bin/bash
set -e
echo "=== Setting up design_split_screen_layout task ==="

source /workspace/scripts/task_utils.sh

# 1. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Ensure Nx Witness Server is ready and authenticated
echo "Checking server status..."
refresh_nx_token > /dev/null 2>&1 || true

# 3. Clean up: Delete 'Gate Monitor' layout if it already exists
echo "Cleaning up previous attempts..."
EXISTING_LAYOUT=$(get_layout_by_name "Gate Monitor" 2>/dev/null || true)
if [ -n "$EXISTING_LAYOUT" ] && [ "$EXISTING_LAYOUT" != "null" ]; then
    LAYOUT_ID=$(echo "$EXISTING_LAYOUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || true)
    if [ -n "$LAYOUT_ID" ]; then
        echo "Deleting existing 'Gate Monitor' layout ($LAYOUT_ID)..."
        nx_api_delete "/rest/v1/layouts/${LAYOUT_ID}" || true
    fi
fi

# 4. Get Camera ID for verification/logging
CAM_ID=$(get_camera_id_by_name "Parking Lot Camera" 2>/dev/null || true)
echo "Target Camera ID: $CAM_ID"
echo "$CAM_ID" > /tmp/target_camera_id.txt

# 5. Launch Desktop Client
# Check if running
if ! pgrep -f "nxwitness-client" > /dev/null && ! pgrep -f "applauncher" > /dev/null; then
    echo "Starting Nx Witness Desktop Client..."
    
    # Find binary (path varies by version)
    CLIENT_BIN=$(find /opt/networkoptix* -name "applauncher" -type f | head -n 1)
    
    if [ -z "$CLIENT_BIN" ]; then
        echo "ERROR: Nx Witness client binary not found!"
        # Fallback to verify logic without client if strictly API based, but description requires client
    else
        # Launch in background
        su - ga -c "DISPLAY=:1 $CLIENT_BIN &" 
        
        # Wait for window
        echo "Waiting for client window..."
        for i in {1..30}; do
            if DISPLAY=:1 wmctrl -l | grep -i "Nx Witness"; then
                echo "Client window detected."
                break
            fi
            sleep 1
        done
        
        # Give it time to initialize
        sleep 10
        
        # Attempt to handle First Run / Login dialogs if they appear
        # (This is best-effort automation; manual interaction is often required by the agent)
        # Dismiss "Connect to Server" tile if visible (often handled by previous sessions)
    fi
fi

# 6. Maximize Window
echo "Maximizing client window..."
DISPLAY=:1 wmctrl -r "Nx Witness" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 7. Take initial screenshot
echo "Capturing initial state..."
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="