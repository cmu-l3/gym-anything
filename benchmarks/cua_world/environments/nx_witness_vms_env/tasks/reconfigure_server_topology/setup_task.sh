#!/bin/bash
set -e
echo "=== Setting up reconfigure_server_topology task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Authenticate
TOKEN=$(refresh_nx_token)
if [ -z "$TOKEN" ]; then
    echo "ERROR: Failed to authenticate with Nx Witness"
    exit 1
fi
echo "Authenticated with token."

# 3. Reset Server Name to a generic default to ensure the agent actually changes it
# Get current server ID
SERVER_ID=$(get_server_id)
echo "Found Server ID: $SERVER_ID"

if [ -n "$SERVER_ID" ]; then
    echo "Resetting server name to 'GymAnything-Default-NVR'..."
    # Reset name
    nx_api_patch "/rest/v1/servers/${SERVER_ID}" '{"name": "GymAnything-Default-NVR"}' > /dev/null
    
    # Reset location parameter (if it exists, we overwrite/clear it)
    # Nx Witness stores extended attributes in 'parameters'. We set it to empty or a default.
    # Note: 'parameters' is often a list of objects or a key-value map depending on endpoint version.
    # For simplicity, we'll try to set the specific user parameter if accessible, 
    # but primarily we rely on the agent setting it correctly.
    # Here we just ensure the name is definitely NOT the target name.
fi

# 4. Clean up output files
rm -f "/home/ga/Documents/vms_architecture.json"
rm -f "/home/ga/Documents/vms_architecture_summary.txt"
mkdir -p "/home/ga/Documents"

# 5. Ensure cameras exist (rely on environment setup, but check count)
CAM_COUNT=$(count_cameras)
echo "Current camera count: $CAM_COUNT"
if [ "$CAM_COUNT" -eq 0 ]; then
    echo "WARNING: No cameras found. Attempting to trigger testcamera..."
    # (Optional: Trigger testcamera logic if needed, but env setup should handle this)
fi

# 6. Record initial state for verification
cat > /tmp/initial_state.json << EOF
{
    "server_id": "$SERVER_ID",
    "initial_name": "GymAnything-Default-NVR",
    "camera_count": $CAM_COUNT,
    "start_time": $(date +%s)
}
EOF

# 7. Open Firefox to the API documentation or just a blank tab to be helpful
ensure_firefox_running "https://localhost:7001/static/index.html#/settings/system"
maximize_firefox

# 8. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="