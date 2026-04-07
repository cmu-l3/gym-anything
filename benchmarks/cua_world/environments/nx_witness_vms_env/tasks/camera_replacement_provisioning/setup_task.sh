#!/bin/bash
set -e
echo "=== Setting up Camera Replacement Provisioning Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# Define paths
GROUND_TRUTH_DIR="/var/lib/app/ground_truth"
mkdir -p "$GROUND_TRUTH_DIR"
GROUND_TRUTH_FILE="$GROUND_TRUTH_DIR/camera_ids.json"

# Credentials
NX_ADMIN_PASS="Admin1234!"

# 1. Wait for Nx Server and Get Token
echo "Authenticating..."
NX_TOKEN=$(refresh_nx_token)
if [ -z "$NX_TOKEN" ]; then
    echo "ERROR: Failed to get auth token"
    exit 1
fi

# 2. Get available cameras
echo "Retrieving cameras..."
CAMERAS_JSON=$(get_all_cameras)
CAMERA_COUNT=$(echo "$CAMERAS_JSON" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")

if [ "$CAMERA_COUNT" -lt 2 ]; then
    echo "ERROR: Not enough cameras found (found $CAMERA_COUNT, need 2)"
    exit 1
fi

# 3. Select two cameras to play the roles
ID_FAULTY=$(echo "$CAMERAS_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['id'])")
ID_NEW=$(echo "$CAMERAS_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)[1]['id'])")

echo "Selected Faulty ID: $ID_FAULTY"
echo "Selected New ID:    $ID_NEW"

# 4. Configure "Faulty" Camera
# Name: "Server Room (Faulty)"
# Schedule: FPS 7, Quality "low" (Unique signature)
echo "Configuring Faulty Camera..."
nx_api_patch "/rest/v1/devices/${ID_FAULTY}" '{
    "name": "Server Room (Faulty)",
    "schedule": {
        "isEnabled": true,
        "tasks": [{
            "dayOfWeek": 1,
            "startTime": 0,
            "endTime": 86400,
            "recordingType": "always",
            "streamQuality": "low",
            "fps": 7,
            "bitrateKbps": 512
        }]
    },
    "enabled": true
}' > /dev/null

# 5. Configure "New" Camera
# Name: "New_Camera_Detected_0042"
# Schedule: Default/Empty
echo "Configuring New Camera..."
nx_api_patch "/rest/v1/devices/${ID_NEW}" '{
    "name": "New_Camera_Detected_0042",
    "schedule": {
        "isEnabled": false,
        "tasks": []
    },
    "enabled": true
}' > /dev/null

# 6. Save Ground Truth (Hidden from agent)
cat <<EOF > "$GROUND_TRUTH_FILE"
{
    "faulty_id": "$ID_FAULTY",
    "new_id": "$ID_NEW",
    "expected_fps": 7,
    "expected_quality": "low",
    "initial_faulty_name": "Server Room (Faulty)",
    "initial_new_name": "New_Camera_Detected_0042"
}
EOF
chmod 600 "$GROUND_TRUTH_FILE"

# 7. Ensure Browser is open to Web Admin (Agent might use it)
ensure_firefox_running "https://localhost:7001/static/index.html#/settings/cameras"
maximize_firefox

# 8. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="