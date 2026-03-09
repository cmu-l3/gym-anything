#!/bin/bash
echo "=== Exporting Import Surgical Guide Result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final state
take_screenshot /tmp/task_end.png
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
PROJECT_PATH="/home/ga/Documents/guide_verification.inv3"

# 2. Analyze the project file using Python
# We need to extract the tarball and parse property lists to check surfaces and colors.
python3 << PYEOF
import tarfile
import plistlib
import os
import json
import sys

project_path = "$PROJECT_PATH"
task_start = $TASK_START

result = {
    "project_exists": False,
    "file_valid": False,
    "file_fresh": False,
    "surface_count": 0,
    "guide_found": False,
    "guide_color": [0.0, 0.0, 0.0],
    "bone_found": False
}

if os.path.exists(project_path):
    result["project_exists"] = True
    mtime = os.path.getmtime(project_path)
    if mtime > task_start:
        result["file_fresh"] = True

    try:
        # InVesalius 3 projects are tar.gz files containing .plist files
        with tarfile.open(project_path, "r:gz") as tar:
            # 1. Check main.plist for surface count
            try:
                f_main = tar.extractfile("main.plist")
                main_plist = plistlib.load(f_main)
                # InVesalius stores surfaces in a dict or list in main.plist usually
                # structure: {'surfaces': {'0': {...}, '1': {...}}}
                surfaces = main_plist.get('surfaces', {})
                result["surface_count"] = len(surfaces)
                result["file_valid"] = True
            except (KeyError, ValueError, Exception):
                # Fallback: Count surface_*.plist files if main structure varies by version
                pass
            
            # 2. Iterate members to find surface details
            # Surface files are named surface_0.plist, surface_1.plist, etc.
            for member in tar.getmembers():
                if member.name.startswith("surface_") and member.name.endswith(".plist"):
                    try:
                        f = tar.extractfile(member)
                        s_data = plistlib.load(f)
                        
                        name = s_data.get("name", "").lower()
                        color = s_data.get("color", [1.0, 1.0, 1.0])
                        
                        # Identify the guide by name or heuristics (it's the imported one)
                        # The user was instructed to import 'surgical_guide.stl'
                        if "surgical_guide" in name or "guide" in name:
                            result["guide_found"] = True
                            result["guide_color"] = color
                        
                        # Identify bone by name or heuristics
                        if "bone" in name or "skull" in name or "threshold" in name:
                            result["bone_found"] = True
                            
                    except Exception as e:
                        print(f"Error parsing member {member.name}: {e}", file=sys.stderr)

            # Fallback for surface count if main.plist failed
            if result["surface_count"] == 0:
                count = 0
                for member in tar.getmembers():
                    if member.name.startswith("surface_") and member.name.endswith(".plist"):
                        count += 1
                result["surface_count"] = count

    except Exception as e:
        print(f"Error opening project file: {e}", file=sys.stderr)

# Save result to JSON
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f)

print("Analysis complete:", result)
PYEOF

# 3. Secure output
chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "=== Export Complete ==="