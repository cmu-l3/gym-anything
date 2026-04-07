#!/bin/bash
set -e
echo "=== Setting up configure_incident_trigger task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Prepare Environment via API
# ----------------------------------------------------------------
refresh_nx_token > /dev/null 2>&1 || true

# Ensure 'Entrance Camera' exists
ENTRANCE_CAM_ID=$(get_camera_id_by_name "Entrance Camera")

if [ -z "$ENTRANCE_CAM_ID" ]; then
    echo "Entrance Camera not found, renaming first available camera..."
    FIRST_ID=$(get_first_camera_id)
    if [ -n "$FIRST_ID" ]; then
        nx_api_patch "/rest/v1/devices/${FIRST_ID}" '{"name": "Entrance Camera"}' > /dev/null
        ENTRANCE_CAM_ID="$FIRST_ID"
        echo "Renamed $FIRST_ID to Entrance Camera"
    else
        echo "ERROR: No cameras available!"
        exit 1
    fi
fi
echo "$ENTRANCE_CAM_ID" > /tmp/target_camera_id.txt

# Remove any existing "Flag Suspect" rules to ensure clean state
echo "Cleaning up existing rules..."
RULES_JSON=$(nx_api_get "/rest/v1/eventRules")
echo "$RULES_JSON" | python3 -c "
import sys, json
try:
    rules = json.load(sys.stdin)
    for rule in rules:
        # Check if it's our target rule (Soft Trigger 'Flag Suspect')
        cond = rule.get('eventCondition', '')
        if 'Flag Suspect' in cond and rule.get('eventType') == 'softwareTrigger':
            print(rule.get('id'))
except:
    pass
" | while read rule_id; do
    if [ -n "$rule_id" ]; then
        echo "Deleting existing rule: $rule_id"
        nx_api_delete "/rest/v1/eventRules/${rule_id}"
    fi
done

# 2. Launch Desktop Client
# ----------------------------------------------------------------
echo "Launching Nx Witness Desktop Client..."

# Kill any existing instances
pkill -f "Nx Witness" 2>/dev/null || true
pkill -f "applauncher" 2>/dev/null || true
sleep 2

# Find launcher
APPLAUNCHER=$(find /opt -name "applauncher" -type f 2>/dev/null | head -1)

if [ -n "$APPLAUNCHER" ]; then
    # Start client
    # Note: We don't have a direct way to bypass login easily in the client without user interaction usually,
    # but strictly speaking, the 'setup_nx_witness.sh' script sets up the server.
    # The client usually remembers the last connection or shows the tile.
    
    DISPLAY=:1 "$APPLAUNCHER" > /tmp/nx_client.log 2>&1 &
    CLIENT_PID=$!
    
    echo "Waiting for client window..."
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "Nx Witness"; then
            echo "Client window found."
            break
        fi
        sleep 1
    done
    sleep 5
    
    # Attempt to handle "Welcome" / "Connect" screen if it appears
    # This is heuristic: pressing Enter often connects to the selected tile (localhost)
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 5
    
    # Handle Login Dialog if it appears (admin/Admin1234!)
    # We type the password just in case focus is on password field
    DISPLAY=:1 xdotool type "Admin1234!" 2>/dev/null || true
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 5
    
    # Maximize window
    DISPLAY=:1 wmctrl -r "Nx Witness" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    
    # Ensure window is focused
    DISPLAY=:1 wmctrl -a "Nx Witness" 2>/dev/null || true
    
else
    echo "WARNING: Nx Witness Desktop Client binary not found. Agent may need to use Web Admin."
    # Fallback to Firefox if desktop client fails? 
    # The task prompts for Desktop Client, but verification is API based, so Web Admin is technically valid too.
    # We will launch Firefox just in case as a backup aid.
    ensure_firefox_running "https://localhost:7001/static/index.html#/settings/camera-settings?cameraId=${ENTRANCE_CAM_ID}"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="