#!/bin/bash
# Export script for manual_mitosis_tracking task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting Mitosis Tracking Result ==="

# Paths
RESULT_FILE="/home/ga/ImageJ_Data/results/tracking_trace.csv"
TASK_START_FILE="/tmp/task_start_time"
EXPORT_JSON="/tmp/mitosis_task_result.json"

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# Check if file exists and gather metadata
python3 << 'PYEOF'
import json
import os
import csv
import sys

result_file = "/home/ga/ImageJ_Data/results/tracking_trace.csv"
task_start_file = "/tmp/task_start_time"
output_json = "/tmp/mitosis_task_result.json"

data = {
    "file_exists": False,
    "file_created_during_task": False,
    "row_count": 0,
    "parsed_data": {},
    "file_size": 0,
    "error": None
}

# Check file existence
if os.path.exists(result_file):
    data["file_exists"] = True
    data["file_size"] = os.path.getsize(result_file)
    
    # Check creation time vs task start
    try:
        with open(task_start_file, 'r') as f:
            start_time = int(f.read().strip())
        mtime = int(os.path.getmtime(result_file))
        if mtime > start_time:
            data["file_created_during_task"] = True
    except Exception:
        # If timestamp check fails, assume true if file exists (verifier will enforce robustly)
        pass

    # Parse CSV content
    try:
        parsed_points = {}
        with open(result_file, 'r') as f:
            # Try to handle both header and no-header cases
            # We look for lines with 3 numbers: Frame, X, Y
            lines = f.readlines()
            
            for line in lines:
                parts = line.strip().replace(',', ' ').split()
                # Remove non-numeric parts
                nums = []
                for p in parts:
                    try:
                        nums.append(float(p))
                    except ValueError:
                        pass
                
                # We expect at least 3 numbers: Frame, X, Y
                if len(nums) >= 3:
                    frame = int(nums[0])
                    x = nums[1]
                    y = nums[2]
                    parsed_points[str(frame)] = [x, y]
        
        data["parsed_data"] = parsed_points
        data["row_count"] = len(parsed_points)
        
    except Exception as e:
        data["error"] = f"Parse error: {str(e)}"

# Save export data
with open(output_json, 'w') as f:
    json.dump(data, f, indent=2)

print(f"Export data saved to {output_json}")
PYEOF

# Ensure permissions
chmod 666 "$EXPORT_JSON" 2>/dev/null || true

echo "=== Export Complete ==="
cat "$EXPORT_JSON"