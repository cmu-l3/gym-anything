#!/bin/bash
echo "=== Exporting create_tissue_atlas_project results ==="

source /workspace/scripts/task_utils.sh

OUTPUT_FILE="/home/ga/Documents/tissue_atlas.inv3"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Capture Final Screenshot (Evidence)
take_screenshot /tmp/task_final.png

# 2. Check if file exists and timestamps
FILE_EXISTS="false"
FILE_SIZE=0
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Analyze InVesalius Project File (Python)
# We need to peek inside the .inv3 (tar.gz) and parse plists
python3 << PYEOF
import tarfile
import plistlib
import json
import os
import sys

output_file = "$OUTPUT_FILE"
result = {
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size": $FILE_SIZE,
    "valid_project": False,
    "mask_count": 0,
    "masks": []
}

if result["file_exists"] and result["file_size"] > 100:
    try:
        if tarfile.is_tarfile(output_file):
            with tarfile.open(output_file, "r:gz") as tar:
                # Iterate over members to find masks
                for member in tar.getmembers():
                    if member.name.startswith("mask_") and member.name.endswith(".plist"):
                        try:
                            f = tar.extractfile(member)
                            if f:
                                plist_data = plistlib.load(f)
                                mask_info = {
                                    "name": plist_data.get("name", "Unknown"),
                                    "thresh_min": plist_data.get("threshold_range", [0,0])[0],
                                    "thresh_max": plist_data.get("threshold_range", [0,0])[1],
                                    "color": plist_data.get("color", [0,0,0])
                                }
                                result["masks"].append(mask_info)
                        except Exception as e:
                            print(f"Error parsing mask {member.name}: {e}", file=sys.stderr)
                
                result["valid_project"] = True
                result["mask_count"] = len(result["masks"])
    except Exception as e:
        print(f"Error reading project file: {e}", file=sys.stderr)
        result["error"] = str(e)

# Save result to JSON
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Analysis complete.")
PYEOF

# 4. Handle Permissions (ensure ga/verifier can read)
chmod 666 /tmp/task_result.json 2>/dev/null || true
chmod 666 /tmp/task_final.png 2>/dev/null || true

echo "Result JSON content:"
cat /tmp/task_result.json

echo "=== Export complete ==="