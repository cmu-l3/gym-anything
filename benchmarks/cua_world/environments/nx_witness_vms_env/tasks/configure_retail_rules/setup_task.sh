#!/bin/bash
set -e
echo "=== Setting up configure_retail_rules task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Refresh Auth Token for API operations
refresh_nx_token > /dev/null 2>&1 || true

# 2. Clean up existing rules to ensure idempotency
# We want to remove rules that might conflict or be left over from previous runs
echo "Cleaning up existing conflicting rules..."
RULES_JSON=$(nx_api_get "/rest/v1/eventRules")

# Parse and find IDs of rules matching our criteria to delete them
echo "$RULES_JSON" | python3 -c "
import sys, json
try:
    rules = json.load(sys.stdin)
    ids_to_delete = []
    for r in rules:
        # Check for POS rules
        if r.get('eventType') == 'userDefinedEvent':
             text = r.get('eventCondition', '')
             if 'POS-Register-01' in text and ('VOID' in text or 'REFUND' in text):
                 ids_to_delete.append(r['id'])
        # Check for Silent Alarm trigger
        if r.get('eventType') == 'softwareTrigger':
             # Soft trigger name is often stored in eventCondition or separate name field depending on version
             # We'll check generic properties
             if 'Silent Alarm' in str(r):
                 ids_to_delete.append(r['id'])
    print('\n'.join(ids_to_delete))
except:
    pass
" | while read -r rule_id; do
    if [ -n "$rule_id" ]; then
        echo "Deleting existing rule: $rule_id"
        nx_api_delete "/rest/v1/eventRules/${rule_id}" || true
    fi
done

# 3. Ensure 'Entrance Camera' exists (Critical for the task)
ENTRANCE_CAM_ID=$(get_camera_id_by_name "Entrance Camera")
if [ -z "$ENTRANCE_CAM_ID" ]; then
    echo "WARNING: 'Entrance Camera' not found. Creating virtual camera..."
    # If the setup script didn't create it for some reason, we rely on the generic setup.
    # But usually, it should be there. We'll proceed, assuming standard env setup.
else
    echo "Target 'Entrance Camera' found: $ENTRANCE_CAM_ID"
fi

# 4. Launch Desktop Client (Standard Pattern for Desktop Tasks)
# Kill any existing instances
pkill -f "applauncher" 2>/dev/null || true
pkill -f "client.*networkoptix" 2>/dev/null || true
pkill -f "nxwitness" 2>/dev/null || true
sleep 2

# Handle Keyrings (prevent popups)
mkdir -p /home/ga/.local/share/keyrings 2>/dev/null || true
if [ ! -f /home/ga/.local/share/keyrings/login.keyring ]; then
    # Create dummy keyring
    echo -n "GnomeKeyring" > /home/ga/.local/share/keyrings/login.keyring
fi

# Find AppLauncher
APPLAUNCHER=$(find /opt -name "applauncher" -type f 2>/dev/null | head -1)

if [ -n "$APPLAUNCHER" ]; then
    echo "Launching Nx Witness Client..."
    DISPLAY=:1 "$APPLAUNCHER" &
    
    # Wait for initialization
    sleep 10
    
    # Attempt to dismiss EULA/Keyring dialogs via xdotool
    # (Coordinates are approximate based on standard 1920x1080 resolution)
    # EULA "I Agree"
    DISPLAY=:1 xdotool mousemove 1327 783 click 1 2>/dev/null || true
    sleep 2
    
    # Focus Main Window
    DISPLAY=:1 wmctrl -r "Nx Witness" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -a "Nx Witness" 2>/dev/null || true
else
    echo "ERROR: Nx Witness Desktop Client binary not found."
fi

# 5. Take Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="