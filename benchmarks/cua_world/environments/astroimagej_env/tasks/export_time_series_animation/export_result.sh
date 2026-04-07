#!/bin/bash
echo "=== Exporting Time-Series Animation Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# Run Python script using OpenCV to analyze the exported AVI
# OpenCV is available in this environment's system python
python3 << 'PYEOF'
import json
import os
import sys

try:
    import cv2
    HAS_CV2 = True
except ImportError:
    HAS_CV2 = False

output_path = "/home/ga/AstroImages/tracking_video.avi"
start_time_path = "/tmp/task_start_time.txt"

result = {
    "file_exists": False,
    "file_size_bytes": 0,
    "created_during_task": False,
    "has_cv2": HAS_CV2,
    "opened_successfully": False,
    "frame_count": 0,
    "fps": 0.0,
    "mid_frame_mean": 0.0,
    "mid_frame_std": 0.0,
    "mid_frame_max": 0.0,
    "error_msg": ""
}

# Check creation time
task_start_time = 0
try:
    with open(start_time_path, "r") as f:
        task_start_time = float(f.read().strip())
except Exception:
    pass

if os.path.exists(output_path):
    result["file_exists"] = True
    result["file_size_bytes"] = os.path.getsize(output_path)
    file_mtime = os.path.getmtime(output_path)
    
    if file_mtime > task_start_time:
        result["created_during_task"] = True

    if HAS_CV2:
        try:
            cap = cv2.VideoCapture(output_path)
            if cap.isOpened():
                result["opened_successfully"] = True
                result["frame_count"] = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
                result["fps"] = float(cap.get(cv2.CAP_PROP_FPS))
                
                # Check middle frame to see if it's completely black (bad stretch)
                if result["frame_count"] > 0:
                    mid_idx = max(0, result["frame_count"] // 2)
                    cap.set(cv2.CAP_PROP_POS_FRAMES, mid_idx)
                    ret, frame = cap.read()
                    if ret and frame is not None:
                        # Convert to grayscale to evaluate brightness
                        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY) if len(frame.shape) == 3 else frame
                        result["mid_frame_mean"] = float(gray.mean())
                        result["mid_frame_std"] = float(gray.std())
                        result["mid_frame_max"] = float(gray.max())
            cap.release()
        except Exception as e:
            result["error_msg"] = str(e)

# Write results
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

PYEOF

echo "Result JSON written to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="