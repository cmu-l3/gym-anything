#!/bin/bash
set -e
echo "=== Setting up False Alarm Verification Task ==="

source /workspace/scripts/task_utils.sh
date +%s > /tmp/task_start_time.txt

VIDEO_FILE="/workspace/data/videos/avenue_normal.mp4"
CAMERA_NAME="Parking Lot Camera"

if [ ! -f "$VIDEO_FILE" ]; then
    echo "ERROR: Video file not found: $VIDEO_FILE"
    exit 1
fi

mkdir -p /home/ga/test_videos
cp "$VIDEO_FILE" /home/ga/test_videos/task_video.mp4
chown ga:ga /home/ga/test_videos/task_video.mp4

# Ground truth: this is a NORMAL video, no crime
mkdir -p /var/lib/nx_witness_ground_truth
cat > /var/lib/nx_witness_ground_truth/ground_truth.json << 'GTEOF'
{
    "expected_verdict": "DISMISS",
    "is_normal": true,
    "description": "Normal activity footage - no criminal or suspicious activity present"
}
GTEOF
chmod 700 /var/lib/nx_witness_ground_truth
chmod 600 /var/lib/nx_witness_ground_truth/*.json

# Configure camera
wait_for_nx_server
pkill -f testcamera || true
sleep 2

TESTCAMERA=$(find /opt -name testcamera -type f 2>/dev/null | head -1)
SERVER_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}' || echo "127.0.0.1")

if [ -n "$TESTCAMERA" ]; then
    nohup "$TESTCAMERA" --local-interface="${SERVER_IP}" \
        "files=/home/ga/test_videos/task_video.mp4;count=3" \
        > /tmp/testcamera_task.log 2>&1 &
    sleep 10
else
    echo "ERROR: testcamera not found"; exit 1
fi

TIMEOUT=60; ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    CAM_COUNT=$(count_cameras)
    [ "$CAM_COUNT" -gt 0 ] && break
    sleep 5; ELAPSED=$((ELAPSED + 5))
done

CAM_ID=$(get_first_camera_id)
if [ -n "$CAM_ID" ]; then
    nx_api_patch "/rest/v1/devices/${CAM_ID}" "{\"name\": \"${CAMERA_NAME}\"}" > /dev/null
    enable_recording_for_camera "$CAM_ID" "25" > /dev/null
fi

sleep 30

ensure_firefox_running "https://localhost:7001/static/index.html"
sleep 5; dismiss_ssl_warning; sleep 3; maximize_firefox; sleep 2
take_screenshot /tmp/task_initial.png

echo "=== False Alarm Verification Task Setup Complete ==="
