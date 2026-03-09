#!/bin/bash
# Export result for visualize_bone_skin_overlay task

echo "=== Exporting visualize_bone_skin_overlay result ==="

source /workspace/scripts/task_utils.sh

OUTPUT_FILE="/home/ga/Documents/skin_bone_overlay.inv3"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_end.png

# Check file timestamps for anti-gaming
FILE_CREATED_DURING_TASK="false"
if [ -f "$OUTPUT_FILE" ]; then
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Use Python to inspect the .inv3 file (tar.gz archive) content
# We need to verify: 
# 1. At least 2 surfaces exist
# 2. At least one is opaque
# 3. At least one is transparent
python3 << 'PYEOF'
import tarfile
import plistlib
import os
import json
import sys

inv3_path = "/home/ga/Documents/skin_bone_overlay.inv3"
result = {
    "file_exists": False,
    "valid_inv3": False,
    "surface_count": 0,
    "surfaces": [],
    "has_opaque": False,
    "has_transparent": False,
    "error": None
}

if os.path.isfile(inv3_path):
    result["file_exists"] = True
    try:
        if tarfile.is_tarfile(inv3_path):
            result["valid_inv3"] = True
            with tarfile.open(inv3_path, "r:*") as tar:
                # Iterate over members to find surface plists
                for member in tar.getmembers():
                    if member.name.startswith("surface_") and member.name.endswith(".plist"):
                        try:
                            f = tar.extractfile(member)
                            if f:
                                pl = plistlib.load(f)
                                name = pl.get("name", "Unknown")
                                # Transparency: 0.0 = Opaque, 1.0 = Invisible
                                transparency = float(pl.get("transparency", 0.0))
                                
                                surface_info = {
                                    "name": name,
                                    "transparency": transparency
                                }
                                result["surfaces"].append(surface_info)
                        except Exception as e:
                            print(f"Error reading member {member.name}: {e}", file=sys.stderr)
            
            result["surface_count"] = len(result["surfaces"])
            
            # Analyze surfaces
            for s in result["surfaces"]:
                t = s["transparency"]
                # Strict check: Opaque < 0.1
                if t < 0.1:
                    result["has_opaque"] = True
                # Strict check: Transparent 0.2 - 0.9
                if 0.2 <= t <= 0.9:
                    result["has_transparent"] = True
                    
    except Exception as e:
        result["error"] = str(e)
else:
    result["error"] = "File not found"

# Add shell-checked timestamp info
result["created_during_task"] = os.environ.get("FILE_CREATED_DURING_TASK") == "true"

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="