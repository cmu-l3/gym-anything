#!/bin/bash
echo "=== Exporting configure_mask_surface_properties result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Analyze the output project file
# We use Python to parse the .inv3 (tar.gz) and its plist contents
python3 << 'PYEOF'
import tarfile
import plistlib
import os
import json
import time

output_path = "/home/ga/Documents/organized_project.inv3"
task_start_file = "/tmp/task_start_time.txt"

result = {
    "file_exists": False,
    "file_created_during_task": False,
    "valid_archive": False,
    "mask_found": False,
    "mask_name_correct": False,
    "mask_threshold_valid": False,
    "surface_found": False,
    "surface_name_correct": False,
    "surface_geometry_valid": False,
    "surface_color_red": False,
    "details": {}
}

# Check file existence and timestamp
if os.path.exists(output_path):
    result["file_exists"] = True
    
    try:
        with open(task_start_file, 'r') as f:
            start_time = int(f.read().strip())
        file_mtime = int(os.path.getmtime(output_path))
        if file_mtime > start_time:
            result["file_created_during_task"] = True
    except Exception:
        pass # Timestamp check failed, not critical if file exists

    # Parse Archive
    try:
        if tarfile.is_tarfile(output_path):
            with tarfile.open(output_path, "r:gz") as tar:
                result["valid_archive"] = True
                
                # Check Masks
                for member in tar.getmembers():
                    if member.name.startswith("mask_") and member.name.endswith(".plist"):
                        try:
                            f = tar.extractfile(member)
                            plist_data = plistlib.load(f)
                            
                            name = plist_data.get("name", "").strip()
                            thresh = plist_data.get("threshold_range", [0, 0])
                            
                            # Log what we found
                            result["details"]["mask_name"] = name
                            result["details"]["mask_threshold"] = thresh
                            
                            if name.lower() == "cranial bone":
                                result["mask_found"] = True
                                result["mask_name_correct"] = True
                                # Bone threshold check (generous range)
                                if thresh[0] >= 100 and thresh[1] >= 800:
                                    result["mask_threshold_valid"] = True
                                break # Found the target mask
                        except Exception as e:
                            print(f"Error parsing mask plist: {e}")
                
                # If exact name not found, check if ANY mask meets threshold (partial credit logic)
                if not result["mask_found"]:
                     for member in tar.getmembers():
                        if member.name.startswith("mask_") and member.name.endswith(".plist"):
                            f = tar.extractfile(member)
                            plist_data = plistlib.load(f)
                            thresh = plist_data.get("threshold_range", [0, 0])
                            if thresh[0] >= 100 and thresh[1] >= 800:
                                result["mask_found"] = True # Found A mask, just wrong name
                                result["mask_threshold_valid"] = True
                                break

                # Check Surfaces
                for member in tar.getmembers():
                    if member.name.startswith("surface_") and member.name.endswith(".plist"):
                        try:
                            f = tar.extractfile(member)
                            plist_data = plistlib.load(f)
                            
                            name = plist_data.get("name", "").strip()
                            color = plist_data.get("colour", [0, 0, 0])
                            
                            result["details"]["surface_name"] = name
                            result["details"]["surface_color"] = color
                            
                            if name.lower() == "skull_model":
                                result["surface_found"] = True
                                result["surface_name_correct"] = True
                                
                                # Check Color (Red)
                                # Color can be 0-1 floats or 0-255 ints
                                r, g, b = color[0], color[1], color[2]
                                is_red = False
                                if isinstance(r, float) and r <= 1.0:
                                    # Float 0-1
                                    if r > 0.8 and g < 0.4 and b < 0.4:
                                        is_red = True
                                else:
                                    # Int 0-255
                                    if r > 200 and g < 100 and b < 100:
                                        is_red = True
                                
                                if is_red:
                                    result["surface_color_red"] = True
                                break
                        except Exception as e:
                             print(f"Error parsing surface plist: {e}")
                
                # Check Surface Geometry File (.vtp)
                # We assume if a surface plist exists, there's a corresponding vtp file
                # But we verify size to ensure it's not empty
                for member in tar.getmembers():
                    if member.name.endswith(".vtp"):
                        if member.size > 50000: # 50KB+, fairly small for a skull but >0
                            result["surface_geometry_valid"] = True

    except Exception as e:
        result["details"]["error"] = str(e)

# Write result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Analysis complete.")
PYEOF

# 3. Secure output file permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="