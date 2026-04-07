#!/bin/bash
# export_result.sh - Post-task hook for mobile_responsive_audit
# Analyzes the output image and exports verification data

echo "=== Exporting mobile_responsive_audit results ==="

# 1. Capture final state screenshot (desktop view)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Setup variables
OUTPUT_PATH="/home/ga/Desktop/energy_mobile_audit.png"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)

# 3. Analyze the output file using Python (inside env)
# We use python3-pil which is installed in the environment
python3 << PYEOF
import json
import os
import sys
from PIL import Image

result = {
    "file_exists": False,
    "file_size": 0,
    "created_during_task": False,
    "width": 0,
    "height": 0,
    "format": "unknown",
    "is_valid_image": False,
    "error": None
}

file_path = "$OUTPUT_PATH"
task_start = int("$TASK_START")

if os.path.exists(file_path):
    result["file_exists"] = True
    try:
        stat = os.stat(file_path)
        result["file_size"] = stat.st_size
        
        # Check modification time
        result["created_during_task"] = stat.st_mtime > task_start
        
        # Analyze image content
        with Image.open(file_path) as img:
            result["width"] = img.width
            result["height"] = img.height
            result["format"] = img.format
            result["is_valid_image"] = True
            
    except Exception as e:
        result["error"] = str(e)

# Write result to JSON
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

# 4. Ensure permissions for the result file
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="