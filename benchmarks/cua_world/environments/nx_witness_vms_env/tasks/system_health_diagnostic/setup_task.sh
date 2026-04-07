#!/bin/bash
set -e
echo "=== Setting up system_health_diagnostic task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure Nx Witness server is running
if ! systemctl is-active --quiet networkoptix-mediaserver; then
    echo "Starting Nx Witness server..."
    systemctl start networkoptix-mediaserver
    sleep 15
fi

# Wait for API to be responsive
NX_BASE="https://localhost:7001"
echo "Waiting for Nx Witness API..."
for i in {1..30}; do
    if curl -sk "${NX_BASE}/rest/v1/system/info" --max-time 5 | grep -q '"version"'; then
        echo "Nx Witness API is responsive"
        break
    fi
    sleep 2
done

# Clean up any previous report or directory
rm -rf /home/ga/reports 2>/dev/null || true

# Start Firefox with Nx Witness web interface (provides context/reference)
ensure_firefox_running "https://localhost:7001"
sleep 5
dismiss_ssl_warning
sleep 2
maximize_firefox

# Record initial state
# We verify specific counts to ensure the environment is populated
NX_TOKEN=$(refresh_nx_token)
CAM_COUNT=$(count_cameras)
USER_COUNT=$(count_users)

echo "Initial State: Cameras=$CAM_COUNT, Users=$USER_COUNT"
if [ "$CAM_COUNT" -eq 0 ]; then
    echo "WARNING: No cameras found. Task may be impossible to complete correctly."
fi

# Take initial state screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="