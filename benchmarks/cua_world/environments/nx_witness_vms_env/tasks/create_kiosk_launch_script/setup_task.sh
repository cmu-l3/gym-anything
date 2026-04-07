#!/bin/bash
set -e
echo "=== Setting up create_kiosk_launch_script task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean up previous attempts
rm -f /home/ga/Desktop/launch_kiosk.sh

# Refresh auth token for API operations
refresh_nx_token > /dev/null 2>&1 || true

# 1. Ensure 'kiosk' user exists
echo "Checking for 'kiosk' user..."
KIOSK_USER=$(get_user_by_name "kiosk")
if [ -z "$KIOSK_USER" ]; then
    echo "Creating 'kiosk' user..."
    nx_api_post "/rest/v1/users" '{
        "name": "kiosk",
        "password": "Kiosk123!",
        "userRoleId": "00000000-0000-0000-0000-000000000002",
        "isEnabled": true
    }' > /dev/null
else
    echo "'kiosk' user already exists."
fi

# 2. Ensure 'Lobby Monitor' layout exists
echo "Checking for 'Lobby Monitor' layout..."
LAYOUT=$(get_layout_by_name "Lobby Monitor")
LAYOUT_ID=""
if [ -z "$LAYOUT" ]; then
    echo "Creating 'Lobby Monitor' layout..."
    # Create a simple layout
    LAYOUT_RESP=$(nx_api_post "/rest/v1/layouts" '{
        "name": "Lobby Monitor",
        "cellAspectRatio": 1.777,
        "items": []
    }')
    LAYOUT_ID=$(echo "$LAYOUT_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || true)
else
    LAYOUT_ID=$(echo "$LAYOUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || true)
    echo "'Lobby Monitor' layout exists (ID: $LAYOUT_ID)."
fi

# 3. Ensure the layout is shared/accessible to the kiosk user
# (In simple RBAC, 'Advanced Viewers' or similar roles see layouts, or we assign specific rights.
# For simplicity in this task context, we ensure the user exists and the layout exists so the agent can 'test' if they want,
# although the task is primarily about script generation.)

# Ensure Desktop directory exists
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# Verify client binary location for our own sanity check (agent has to find it)
CLIENT_BIN=$(find /opt -name "networkoptix-client" -o -name "nxwitness-client" 2>/dev/null | head -1)
echo "Client binary located at: $CLIENT_BIN"

# Maximize Firefox if open (setup_nx_witness.sh might have left it)
maximize_firefox 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="