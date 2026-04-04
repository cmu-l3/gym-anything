#!/bin/bash
echo "=== Exporting curate_anatomical_masks result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final state
take_screenshot /tmp/task_final.png

# 2. Python script to parse the InVesalius project file
# InVesalius .inv3 files are Gzipped Tarballs containing Plist XML files
python3 << 'PYEOF'
import tarfile
import plistlib
import os
import json
import time

output_path = "/home/ga/Documents/teaching_head.inv3"
start_time_path = "/tmp/task_start_time.txt"

result = {
    "file_exists": False,
    "file_valid": False,
    "file_created_during_task": False,
    "mask_count": 0,
    "masks": []
}

# Check file existence and timestamp
if os.path.exists(output_path):
    result["file_exists"] = True
    mtime = os.path.getmtime(output_path)
    
    try:
        with open(start_time_path, 'r') as f:
            start_time = float(f.read().strip())
        if mtime > start_time:
            result["file_created_during_task"] = True
    except:
        pass # Timestamp check failed, handled in verifier

    # Parse the project content
    try:
        with tarfile.open(output_path, "r:gz") as tar:
            result["file_valid"] = True
            
            # Iterate through files in the tar to find masks
            for member in tar.getmembers():
                filename = os.path.basename(member.name)
                
                # Masks are stored as mask_X.plist
                if filename.startswith("mask_") and filename.endswith(".plist"):
                    f = tar.extractfile(member)
                    if f:
                        try:
                            plist_data = plistlib.load(f)
                            
                            # Extract relevant data
                            mask_info = {
                                "name": plist_data.get("name", ""),
                                "threshold_range": plist_data.get("threshold_range", [0, 0]),
                                "color": plist_data.get("color", [0, 0, 0])
                            }
                            result["masks"].append(mask_info)
                        except Exception as e:
                            print(f"Error parsing plist {filename}: {e}")

        result["mask_count"] = len(result["masks"])
            
    except Exception as e:
        print(f"Error opening tar file: {e}")
        result["error"] = str(e)

# Save result to JSON
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

# 3. Permissions fix for copy_from_env
chmod 644 /tmp/task_result.json 2>/dev/null || true
chmod 644 /tmp/task_final.png 2>/dev/null || true

echo "=== Export complete ==="