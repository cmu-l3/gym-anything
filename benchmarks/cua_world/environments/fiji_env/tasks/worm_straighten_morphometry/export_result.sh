#!/bin/bash
echo "=== Exporting Worm Straightening Results ==="

# Get timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# output paths
RES_DIR="/home/ga/Fiji_Data/results/straighten"
IMG_PATH="$RES_DIR/straightened_worm.tif"
PLOT_IMG_PATH="$RES_DIR/intensity_profile.png"
CSV_PATH="$RES_DIR/profile_data.csv"
REPORT_PATH="$RES_DIR/measurements_report.txt"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Use Python to analyze outputs safely
python3 << PYEOF
import json
import os
import sys
import re

result = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "outputs": {},
    "measurements": {}
}

def check_file(path, key):
    if os.path.exists(path):
        mtime = os.path.getmtime(path)
        size = os.path.getsize(path)
        result["outputs"][key] = {
            "exists": True,
            "created_during_task": mtime > $TASK_START,
            "size": size,
            "path": path
        }
        return True
    else:
        result["outputs"][key] = {"exists": False}
        return False

# 1. Check Straightened Image
if check_file("$IMG_PATH", "straightened_image"):
    try:
        from PIL import Image
        img = Image.open("$IMG_PATH")
        result["outputs"]["straightened_image"]["width"] = img.width
        result["outputs"]["straightened_image"]["height"] = img.height
        result["outputs"]["straightened_image"]["format"] = img.format
        # Straightened worms should be much wider than tall (landscape)
        result["outputs"]["straightened_image"]["is_landscape"] = img.width > img.height
    except Exception as e:
        result["outputs"]["straightened_image"]["error"] = str(e)

# 2. Check Profile Plot Image
check_file("$PLOT_IMG_PATH", "profile_plot_image")

# 3. Check CSV Data
if check_file("$CSV_PATH", "profile_csv"):
    try:
        with open("$CSV_PATH", 'r') as f:
            lines = f.readlines()
            result["outputs"]["profile_csv"]["row_count"] = len(lines)
            # Check for data headers or numeric content
            if len(lines) > 0 and "," in lines[0]:
                result["outputs"]["profile_csv"]["valid_format"] = True
    except Exception as e:
        result["outputs"]["profile_csv"]["error"] = str(e)

# 4. Check Report
if check_file("$REPORT_PATH", "report"):
    try:
        with open("$REPORT_PATH", 'r') as f:
            content = f.read()
            result["outputs"]["report"]["content_length"] = len(content)
            
            # Extract numbers
            # Look for Length (e.g., "Length: 850 um" or just "850")
            # We look for any float followed by um or microns, or just labelled Length
            length_match = re.search(r'(?i)length.*?(\d+\.?\d*)', content)
            if length_match:
                result["measurements"]["reported_length"] = float(length_match.group(1))
            
            # Look for Mean Intensity
            mean_match = re.search(r'(?i)mean.*?(\d+\.?\d*)', content)
            if mean_match:
                result["measurements"]["reported_mean"] = float(mean_match.group(1))
    except Exception as e:
        result["outputs"]["report"]["error"] = str(e)

# Save result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

PYEOF

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json