#!/bin/bash
set -e
echo "=== Setting up configure_holiday_schedules task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Nx Witness server is running and we can authenticate
echo "Checking VMS status..."
refresh_nx_token > /dev/null

# Ensure all 5 test cameras are present and named correctly
# The environment setup script creates them, but we verify here
echo "Verifying camera availability..."
REQUIRED_CAMERAS=("Entrance Camera" "Lobby Camera" "Parking Lot Camera" "Loading Dock Camera" "Server Room Camera")
MISSING_CAMS=0

for cam_name in "${REQUIRED_CAMERAS[@]}"; do
    CAM_ID=$(get_camera_id_by_name "$cam_name")
    if [ -z "$CAM_ID" ]; then
        echo "WARNING: Camera '$cam_name' not found."
        MISSING_CAMS=$((MISSING_CAMS + 1))
    else
        echo "Found '$cam_name' ($CAM_ID) - Resetting schedule..."
        # RESET SCHEDULE TO A KNOWN "BAD" STATE
        # This ensures the agent must actually apply changes to pass
        nx_api_patch "/rest/v1/devices/${CAM_ID}" '{
            "schedule": {
                "isEnabled": false,
                "tasks": []
            }
        }' > /dev/null
    fi
done

if [ "$MISSING_CAMS" -gt 2 ]; then
    echo "CRITICAL: Too many cameras missing. Attempting to restart testcamera..."
    # Attempt to kickstart testcamera if widely failing
    pkill testcamera || true
    SERVER_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}' || echo "127.0.0.1")
    TESTCAMERA=$(find /opt -name testcamera -type f | head -1)
    if [ -n "$TESTCAMERA" ]; then
        nohup "$TESTCAMERA" --local-interface="${SERVER_IP}" "channels=5" > /dev/null 2>&1 &
        sleep 5
    fi
fi

# Record initial state dump for anti-gaming comparison
nx_api_get "/rest/v1/devices" > /tmp/initial_devices_state.json

# Remove any previous report file
rm -f /home/ga/recording_schedule_report.txt

# Open the documentation or a terminal to hint at the API start
# We'll just open a terminal maximized as the starting point
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --maximize &"
fi

echo "=== Task setup complete ==="