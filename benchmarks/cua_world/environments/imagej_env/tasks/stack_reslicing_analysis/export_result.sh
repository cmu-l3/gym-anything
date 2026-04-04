#!/bin/bash
# Export script for stack_reslicing_analysis task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting Stack Reslicing Result ==="

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# Define paths
RESULT_FILE="/home/ga/ImageJ_Data/results/side_view_projection.tif"
TASK_START_FILE="/tmp/task_start_timestamp"

# Use Python to analyze the output image properties directly in the environment
# This is more robust than trying to parse ImageJ logs
python3 << 'PYEOF'
import json
import os
import sys
import time
from PIL import Image
import numpy as np

result_file = "/home/ga/ImageJ_Data/results/side_view_projection.tif"
task_start_file = "/tmp/task_start_timestamp"

output = {
    "file_exists": False,
    "file_size_bytes": 0,
    "width": 0,
    "height": 0,
    "n_frames": 1,
    "mode": "unknown",
    "is_8bit": False,
    "file_created_during_task": False,
    "mean_intensity": 0,
    "task_start_timestamp": 0,
    "file_modified_time": 0,
    "error": None
}

# Load task start time
try:
    if os.path.exists(task_start_file):
        output["task_start_timestamp"] = int(open(task_start_file).read().strip())
except Exception as e:
    output["error"] = f"Timestamp read error: {e}"

if os.path.isfile(result_file):
    output["file_exists"] = True
    output["file_size_bytes"] = os.path.getsize(result_file)
    output["file_modified_time"] = int(os.path.getmtime(result_file))
    
    # Check creation time against task start
    if output["task_start_timestamp"] > 0:
        if output["file_modified_time"] > output["task_start_timestamp"]:
            output["file_created_during_task"] = True
            
    try:
        img = Image.open(result_file)
        output["width"] = img.size[0]
        output["height"] = img.size[1]
        output["mode"] = img.mode
        
        # Check if 8-bit (L)
        if img.mode == 'L' or img.mode == 'P':
            output["is_8bit"] = True
            
        # Check for stack (n_frames)
        if hasattr(img, "n_frames"):
            output["n_frames"] = img.n_frames
            
        # Check content (not empty)
        arr = np.array(img)
        output["mean_intensity"] = float(arr.mean())
        
    except Exception as e:
        output["error"] = f"Image analysis error: {e}"

with open("/tmp/stack_reslicing_result.json", "w") as f:
    json.dump(output, f, indent=2)

print(f"Export summary: Exists={output['file_exists']}, Dim={output['width']}x{output['height']}, Created={output['file_created_during_task']}")
PYEOF

echo "=== Export Complete ==="