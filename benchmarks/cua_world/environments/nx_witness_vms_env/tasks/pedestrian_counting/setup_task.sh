#!/bin/bash
set -e
echo "=== Setting up Pedestrian Counting Task ==="

source /workspace/scripts/task_utils.sh
date +%s > /tmp/task_start_time.txt

VIDEO_FILE="/workspace/data/videos/mall_pedestrian.mp4"
CAMERA_NAME="Lobby Camera"

if [ ! -f "$VIDEO_FILE" ]; then
    echo "ERROR: Video file not found: $VIDEO_FILE"
    exit 1
fi

mkdir -p /home/ga/test_videos
cp "$VIDEO_FILE" /home/ga/test_videos/task_video.mp4
chown ga:ga /home/ga/test_videos/task_video.mp4

# Ground truth from Mall Dataset annotations
# The Mall Dataset has ~60,000 annotated heads across 2000 frames
# We store the approximate total count and per-frame stats
mkdir -p /var/lib/nx_witness_ground_truth

# Try to extract ground truth from the .mat file if scipy is available
python3 << 'PYEOF'
import json
import os
import glob

gt_data = {
    "dataset": "mall_dataset_cuhk",
    "total_frames": 2000,
    "original_fps": 2,
    "total_annotated_people": 62325,
    "description": "Shopping mall overhead camera, continuous pedestrian traffic"
}

# Try to load the .mat annotations if available
try:
    import scipy.io
    mat_files = glob.glob("/workspace/data/annotations/mall_gt.mat") + \
                glob.glob("/workspace/data/annotations/*.mat")
    if mat_files:
        mat = scipy.io.loadmat(mat_files[0])
        # Mall dataset .mat has 'count' or 'frame' fields
        if 'count' in mat:
            counts = mat['count'].flatten()
            gt_data['per_frame_counts'] = counts.tolist()
            gt_data['total_annotated_people'] = int(counts.sum())
            gt_data['max_count_in_frame'] = int(counts.max())
            gt_data['min_count_in_frame'] = int(counts.min())
            gt_data['avg_count_per_frame'] = float(counts.mean())
except ImportError:
    pass
except Exception as e:
    print(f"Warning: Could not parse .mat file: {e}")

with open('/var/lib/nx_witness_ground_truth/ground_truth.json', 'w') as f:
    json.dump(gt_data, f, indent=2)

print(f"Ground truth: ~{gt_data['total_annotated_people']} total people annotations")
PYEOF

chmod 700 /var/lib/nx_witness_ground_truth
chmod 600 /var/lib/nx_witness_ground_truth/*.json 2>/dev/null || true

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
    enable_recording_for_camera "$CAM_ID" "10" > /dev/null
fi

sleep 30

ensure_firefox_running "https://localhost:7001/static/index.html"
sleep 5; dismiss_ssl_warning; sleep 3; maximize_firefox; sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Pedestrian Counting Task Setup Complete ==="
