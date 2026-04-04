#!/bin/bash
echo "=== Exporting prepare_colored_airway_model result ==="

source /workspace/scripts/task_utils.sh

OUTPUT_FILE="/home/ga/Documents/airway_study.inv3"

# Capture final state screenshot for VLM verification
take_screenshot /tmp/task_end.png

# Use Python to inspect the internal structure of the saved InVesalius project
# We need to check:
# 1. Mask thresholds (must be negative for air)
# 2. Surface properties (color must be blue)
python3 << 'PYEOF'
import tarfile
import plistlib
import os
import json
import time

path = "/home/ga/Documents/airway_study.inv3"
task_start_ts = 0
try:
    with open("/tmp/task_start_timestamp", "r") as f:
        task_start_ts = int(f.read().strip())
except:
    pass

result = {
    "file_exists": False,
    "file_created_during_task": False,
    "file_size_bytes": 0,
    "valid_project": False,
    "masks": [],
    "surfaces": [],
    "parse_error": None
}

if os.path.isfile(path):
    result["file_exists"] = True
    stat = os.stat(path)
    result["file_size_bytes"] = stat.st_size
    if stat.st_mtime > task_start_ts:
        result["file_created_during_task"] = True

    try:
        # InVesalius .inv3 files are gzip-compressed tarballs
        with tarfile.open(path, "r:gz") as tar:
            result["valid_project"] = True
            
            for member in tar.getmembers():
                filename = os.path.basename(member.name)
                
                # Check Mask properties (thresholds)
                if filename.startswith("mask") and filename.endswith(".plist"):
                    try:
                        f = tar.extractfile(member)
                        plist_data = plistlib.load(f)
                        thresh = plist_data.get("threshold_range", [0, 0])
                        result["masks"].append({
                            "name": plist_data.get("name", "Unknown"),
                            "min_hu": thresh[0],
                            "max_hu": thresh[1]
                        })
                    except Exception as e:
                        print(f"Error reading mask plist: {e}")

                # Check Surface properties (color)
                # InVesalius stores color as "colour": [r, g, b] (floats 0.0-1.0)
                if filename.startswith("surface") and filename.endswith(".plist"):
                    try:
                        f = tar.extractfile(member)
                        plist_data = plistlib.load(f)
                        # Default is usually white [1,1,1]
                        color = plist_data.get("colour", plist_data.get("color", [1.0, 1.0, 1.0]))
                        result["surfaces"].append({
                            "name": plist_data.get("name", "Unknown"),
                            "color": color,
                            "visible": plist_data.get("visible", True)
                        })
                    except Exception as e:
                        print(f"Error reading surface plist: {e}")

    except Exception as e:
        result["parse_error"] = str(e)
        result["valid_project"] = False

# Save JSON result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Export analysis complete.")
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="