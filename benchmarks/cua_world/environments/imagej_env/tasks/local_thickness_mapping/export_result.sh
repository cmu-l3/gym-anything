#!/bin/bash
# Export script for local_thickness_mapping task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting Local Thickness Result ==="

# Take final screenshot for VLM verification
take_screenshot /tmp/task_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

MAP_FILE="/home/ga/ImageJ_Data/results/thickness_map.tif"
CSV_FILE="/home/ga/ImageJ_Data/results/thickness_distribution.csv"
TASK_START_FILE="/tmp/task_start_timestamp"

# We use Python to robustly check file properties (timestamps, existence)
# and prepare a JSON summary for the verifier.
# Note: Actual image content analysis happens in verifier.py using copy_from_env

python3 << 'PYEOF'
import json
import os
import time

map_file = "/home/ga/ImageJ_Data/results/thickness_map.tif"
csv_file = "/home/ga/ImageJ_Data/results/thickness_distribution.csv"
task_start_file = "/tmp/task_start_timestamp"

output = {
    "map_exists": False,
    "map_size_bytes": 0,
    "map_mtime": 0,
    "csv_exists": False,
    "csv_size_bytes": 0,
    "csv_mtime": 0,
    "task_start_time": 0,
    "map_created_during_task": False,
    "csv_created_during_task": False
}

# Get task start time
try:
    if os.path.exists(task_start_file):
        output["task_start_time"] = int(open(task_start_file).read().strip())
except Exception:
    pass

# Check Map File
if os.path.exists(map_file):
    output["map_exists"] = True
    output["map_size_bytes"] = os.path.getsize(map_file)
    output["map_mtime"] = int(os.path.getmtime(map_file))
    if output["task_start_time"] > 0 and output["map_mtime"] > output["task_start_time"]:
        output["map_created_during_task"] = True

# Check CSV File
if os.path.exists(csv_file):
    output["csv_exists"] = True
    output["csv_size_bytes"] = os.path.getsize(csv_file)
    output["csv_mtime"] = int(os.path.getmtime(csv_file))
    if output["task_start_time"] > 0 and output["csv_mtime"] > output["task_start_time"]:
        output["csv_created_during_task"] = True

# Save to JSON
with open("/tmp/local_thickness_result.json", "w") as f:
    json.dump(output, f, indent=2)

print(f"Export summary: Map={output['map_exists']} (Fresh={output['map_created_during_task']}), "
      f"CSV={output['csv_exists']} (Fresh={output['csv_created_during_task']})")
PYEOF

echo "=== Export Complete ==="