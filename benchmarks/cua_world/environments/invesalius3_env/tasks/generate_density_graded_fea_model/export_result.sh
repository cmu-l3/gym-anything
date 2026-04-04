#!/bin/bash
echo "=== Exporting generate_density_graded_fea_model result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot for evidence
take_screenshot /tmp/task_final.png

# Path to the expected project file
PROJECT_FILE="/home/ga/Documents/fea_skull.inv3"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Use Python to analyze the .inv3 file (it is a tar.gz containing plists)
python3 << 'PYEOF'
import tarfile
import plistlib
import json
import os
import sys

project_path = "/home/ga/Documents/fea_skull.inv3"
result = {
    "file_exists": False,
    "file_size": 0,
    "created_during_task": False,
    "mask_count": 0,
    "masks": [],
    "surface_count": 0,
    "surfaces": [],
    "error": None
}

try:
    if os.path.exists(project_path):
        result["file_exists"] = True
        stats = os.stat(project_path)
        result["file_size"] = stats.st_size
        
        # Check timestamp
        task_start = float(os.environ.get("TASK_START", 0))
        if stats.st_mtime > task_start:
            result["created_during_task"] = True

        # Parse the InVesalius project file
        if tarfile.is_tarfile(project_path):
            with tarfile.open(project_path, "r:gz") as tar:
                # Extract mask info
                for member in tar.getmembers():
                    if member.name.startswith("mask_") and member.name.endswith(".plist"):
                        try:
                            f = tar.extractfile(member)
                            plist = plistlib.load(f)
                            mask_data = {
                                "name": plist.get("name", "Unknown"),
                                "threshold_range": plist.get("threshold_range", [0, 0]),
                                "color": plist.get("colour", [0, 0, 0])
                            }
                            result["masks"].append(mask_data)
                        except Exception as e:
                            print(f"Error parsing mask {member.name}: {e}")

                    if member.name.startswith("surface_") and member.name.endswith(".plist"):
                        try:
                            f = tar.extractfile(member)
                            plist = plistlib.load(f)
                            surface_data = {
                                "name": plist.get("name", "Unknown"),
                                "color": plist.get("colour", [0.8, 0.8, 0.8]), # RGB normalized 0-1
                                "transparency": plist.get("transparency", 0.0)
                            }
                            result["surfaces"].append(surface_data)
                        except Exception as e:
                            print(f"Error parsing surface {member.name}: {e}")

                result["mask_count"] = len(result["masks"])
                result["surface_count"] = len(result["surfaces"])
        else:
            result["error"] = "File is not a valid tar archive"
    else:
        result["error"] = "File not found"

except Exception as e:
    result["error"] = str(e)

# Save result to JSON
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Analysis complete. JSON result:")
print(json.dumps(result, indent=2))
PYEOF

# Ensure permissions for the verifier
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="