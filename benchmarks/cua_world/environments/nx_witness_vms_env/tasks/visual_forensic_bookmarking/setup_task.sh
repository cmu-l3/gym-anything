#!/bin/bash
set -e
echo "=== Setting up Visual Forensic Bookmarking Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ==============================================================================
# 1. Generate Forensic Video with Randomized Event
# ==============================================================================
VIDEO_DIR="/home/ga/test_videos"
mkdir -p "$VIDEO_DIR"
OUTPUT_VIDEO="$VIDEO_DIR/conveyor_loop.mp4"

# Random start time for the "Red Alert" (between 10s and 45s into the 60s loop)
ALERT_START=$(( 10 + RANDOM % 36 ))
ALERT_DURATION=8
ALERT_END=$(( ALERT_START + ALERT_DURATION ))

echo "Generating forensic video: Alert starts at ${ALERT_START}s..."

# Generate 60s video: Green normal -> Red alert -> Green normal
# We use ffmpeg to create a video where a red box and text overlay appears at the specific time
ffmpeg -y -f lavfi -i "color=c=green:s=1280x720:d=60:r=24" \
    -vf "drawbox=enable='between(t,${ALERT_START},${ALERT_END})':color=red:t=fill, \
         drawtext=enable='between(t,${ALERT_START},${ALERT_END})':text='CRITICAL ALERT':fontcolor=white:fontsize=80:x=(w-text_w)/2:y=(h-text_h)/2, \
         drawtext=text='Frame %{n}':x=10:y=10:fontsize=24:fontcolor=white" \
    -c:v libx264 -preset ultrafast -pix_fmt yuv420p "$OUTPUT_VIDEO" > /dev/null 2>&1

chown ga:ga "$OUTPUT_VIDEO"

# Save ground truth to a hidden location (root owned)
# The export script will read this later to bundle with results
mkdir -p /var/lib/nx_witness_ground_truth
echo "$ALERT_START" > /var/lib/nx_witness_ground_truth/alert_start.txt
echo "$ALERT_DURATION" > /var/lib/nx_witness_ground_truth/alert_duration.txt
chmod 700 /var/lib/nx_witness_ground_truth
chmod 600 /var/lib/nx_witness_ground_truth/*.txt

# ==============================================================================
# 2. Configure Camera System
# ==============================================================================

# Ensure Server is running
wait_for_nx_server

# Kill existing testcamera to reload video
pkill -f testcamera || true
sleep 2

# Find testcamera binary
TESTCAMERA=$(find /opt -name testcamera -type f 2>/dev/null | head -1)
SERVER_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}' || echo "127.0.0.1")

if [ -n "$TESTCAMERA" ]; then
    echo "Starting testcamera with forensic footage..."
    nohup "$TESTCAMERA" --local-interface="${SERVER_IP}" \
        "files=$OUTPUT_VIDEO;count=1" \
        > /tmp/testcamera_forensic.log 2>&1 &
    sleep 5
else
    echo "ERROR: testcamera utility not found."
    exit 1
fi

# Wait for camera to register
sleep 10

# Rename the camera and enable recording
CAM_ID=$(get_first_camera_id)
if [ -n "$CAM_ID" ]; then
    echo "Configuring camera $CAM_ID..."
    nx_api_patch "/rest/v1/devices/${CAM_ID}" '{"name": "Conveyor Camera"}' > /dev/null
    
    # Enable recording (Critical for bookmarks)
    enable_recording_for_camera "$CAM_ID" "24" > /dev/null
    echo "Camera renamed and recording enabled."
else
    echo "ERROR: No camera found to configure."
    exit 1
fi

# Wait a moment for recording to initialize
sleep 5

# ==============================================================================
# 3. Launch Desktop Client
# ==============================================================================
# We prefer the Desktop Client for scrubbing/bookmarking
echo "Launching Nx Witness Desktop Client..."

# Clean up any existing clients
pkill -f "networkoptix-client" || true

# Launch client
if command -v networkoptix-client &> /dev/null; then
    su - ga -c "DISPLAY=:1 networkoptix-client &"
else
    # Fallback to firefox if desktop client missing (unlikely in this env)
    ensure_firefox_running "https://localhost:7001/static/index.html#/view/${CAM_ID}"
fi

# Wait for window
sleep 10
DISPLAY=:1 wmctrl -r "Nx Witness" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="