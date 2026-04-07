#!/bin/bash
set -e
echo "=== Setting up configure_motion_detection task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure Nx Witness Server is up and we have a token
refresh_nx_token > /dev/null

# Clean up any previous run artifacts
rm -f /home/ga/motion_detection_config.json
rm -f /tmp/system_state.json
rm -f /tmp/agent_report.json

# ==============================================================================
# RESET CAMERA STATE
# ==============================================================================
# We must ensure a clean starting state:
# 1. All cameras set to motionType: "default" (hardware/default)
# 2. All cameras set to recordingType: "always" (continuous recording)
# ==============================================================================

echo "Resetting camera states..."
DEVICES=$(get_all_cameras)

# Iterate through devices and reset them
echo "$DEVICES" | python3 -c "
import sys, json
try:
    devices = json.load(sys.stdin)
    for d in devices:
        print(d['id'])
except:
    pass
" | while read -r cam_id; do
    if [ -n "$cam_id" ]; then
        # Construct the default schedule (Always recording, 15fps)
        # We use a helper function pattern similar to enable_recording_for_camera but for 'always'
        # The API patch body:
        BODY='{
            "motionType": "default",
            "schedule": {
                "isEnabled": true,
                "tasks": [
                    {"dayOfWeek": 1, "startTime": 0, "endTime": 86400, "recordingType": "always", "streamQuality": "high", "fps": 15, "bitrateKbps": 2048},
                    {"dayOfWeek": 2, "startTime": 0, "endTime": 86400, "recordingType": "always", "streamQuality": "high", "fps": 15, "bitrateKbps": 2048},
                    {"dayOfWeek": 3, "startTime": 0, "endTime": 86400, "recordingType": "always", "streamQuality": "high", "fps": 15, "bitrateKbps": 2048},
                    {"dayOfWeek": 4, "startTime": 0, "endTime": 86400, "recordingType": "always", "streamQuality": "high", "fps": 15, "bitrateKbps": 2048},
                    {"dayOfWeek": 5, "startTime": 0, "endTime": 86400, "recordingType": "always", "streamQuality": "high", "fps": 15, "bitrateKbps": 2048},
                    {"dayOfWeek": 6, "startTime": 0, "endTime": 86400, "recordingType": "always", "streamQuality": "high", "fps": 15, "bitrateKbps": 2048},
                    {"dayOfWeek": 7, "startTime": 0, "endTime": 86400, "recordingType": "always", "streamQuality": "high", "fps": 15, "bitrateKbps": 2048}
                ]
            }
        }'
        
        echo "Resetting camera $cam_id..."
        nx_api_patch "/rest/v1/devices/${cam_id}" "$BODY" > /dev/null
    fi
done

# Save initial state for debugging/verification if needed
get_all_cameras > /tmp/initial_camera_state.json

# Open Firefox to the API documentation or Web Admin as a hint
ensure_firefox_running "https://localhost:7001/static/index.html#/settings/cameras"
maximize_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="