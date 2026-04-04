#!/bin/bash
# Export result for export_skull_rotation_movie task

echo "=== Exporting export_skull_rotation_movie result ==="

source /workspace/scripts/task_utils.sh

FRAMES_DIR="/home/ga/Documents/skull_rotation_frames"
VIDEO_PATH="/home/ga/Documents/skull_rotation.avi"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_end.png

# Use Python to analyze outputs (frames vs video)
python3 << PYEOF
import os
import json
import glob

frames_dir = "$FRAMES_DIR"
video_path = "$VIDEO_PATH"
task_start = int("$TASK_START")

result = {
    "mode": "none",
    "frames_count": 0,
    "frames_valid": False,
    "frame_files": [],
    "video_exists": False,
    "video_size_bytes": 0,
    "video_created_during_task": False
}

# Check Path A: Frames
if os.path.isdir(frames_dir):
    png_files = sorted(glob.glob(os.path.join(frames_dir, "*.png")))
    valid_pngs = []
    
    for f in png_files:
        try:
            # Check timestamp
            mtime = os.path.getmtime(f)
            if mtime > task_start:
                # Check magic bytes
                if os.path.getsize(f) > 1024: # Min size 1KB
                    with open(f, "rb") as fh:
                        if fh.read(8) == b"\x89PNG\r\n\x1a\n":
                            valid_pngs.append(f)
        except:
            pass
            
    if len(valid_pngs) > 0:
        result["mode"] = "frames"
        result["frames_count"] = len(valid_pngs)
        result["frames_valid"] = True
        result["frame_files"] = valid_pngs

# Check Path B: Video
if result["mode"] == "none" and os.path.isfile(video_path):
    size = os.path.getsize(video_path)
    mtime = os.path.getmtime(video_path)
    
    if mtime > task_start and size > 10240: # >10KB
        result["mode"] = "video"
        result["video_exists"] = True
        result["video_size_bytes"] = size
        result["video_created_during_task"] = True
        result["frame_files"] = [video_path] # Use this field to point to file for copy

with open("/tmp/rotation_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="