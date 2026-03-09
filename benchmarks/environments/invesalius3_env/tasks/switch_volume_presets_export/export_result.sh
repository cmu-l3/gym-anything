#!/bin/bash
echo "=== Exporting switch_volume_presets_export result ==="

source /workspace/scripts/task_utils.sh

# Capture final visual state
take_screenshot /tmp/task_end.png

# Path configuration
AIRWAY_PATH="/home/ga/Documents/airway_rendering.png"
SOFTTISSUE_PATH="/home/ga/Documents/softtissue_rendering.png"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Use Python for reliable file analysis and JSON generation
python3 << PYEOF
import os
import json
import hashlib

airway_path = "$AIRWAY_PATH"
softtissue_path = "$SOFTTISSUE_PATH"
task_start = int("$TASK_START")

result = {
    "airway_exists": False,
    "airway_size": 0,
    "airway_valid_png": False,
    "airway_created_during_task": False,
    "softtissue_exists": False,
    "softtissue_size": 0,
    "softtissue_valid_png": False,
    "softtissue_created_during_task": False,
    "files_are_distinct": False,
    "app_running": False
}

def check_file(path):
    info = {
        "exists": False,
        "size": 0,
        "valid_png": False,
        "new": False,
        "hash": None
    }
    if os.path.isfile(path):
        info["exists"] = True
        info["size"] = os.path.getsize(path)
        info["new"] = os.path.getmtime(path) > task_start
        
        try:
            with open(path, "rb") as f:
                header = f.read(8)
                content = header + f.read()
                info["valid_png"] = (header == b"\x89PNG\r\n\x1a\n")
                if info["valid_png"]:
                    info["hash"] = hashlib.md5(content).hexdigest()
        except Exception:
            pass
    return info

# Check files
airway_info = check_file(airway_path)
softtissue_info = check_file(softtissue_path)

# Update result dict
result["airway_exists"] = airway_info["exists"]
result["airway_size"] = airway_info["size"]
result["airway_valid_png"] = airway_info["valid_png"]
result["airway_created_during_task"] = airway_info["new"]

result["softtissue_exists"] = softtissue_info["exists"]
result["softtissue_size"] = softtissue_info["size"]
result["softtissue_valid_png"] = softtissue_info["valid_png"]
result["softtissue_created_during_task"] = softtissue_info["new"]

# Check distinctness
if airway_info["hash"] and softtissue_info["hash"]:
    result["files_are_distinct"] = (airway_info["hash"] != softtissue_info["hash"])

# Check if app is running
if os.system("pgrep -f 'invesalius' > /dev/null") == 0:
    result["app_running"] = True

# Write result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="