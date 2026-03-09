#!/bin/bash
# Export result for calibrate_bone_mask_volume task

echo "=== Exporting calibrate_bone_mask_volume result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Analyze the output project file
# We use Python to parse the .inv3 tarball and calculate volume from the mask numpy array
python3 << 'PYEOF'
import tarfile
import plistlib
import os
import json
import numpy as np

output_path = "/home/ga/Documents/cortical_study.inv3"
result = {
    "file_exists": False,
    "is_valid_archive": False,
    "mask_found": False,
    "mask_volume_mm3": 0.0,
    "voxel_count": 0,
    "error": None
}

if os.path.exists(output_path):
    result["file_exists"] = True
    try:
        if tarfile.is_tarfile(output_path):
            result["is_valid_archive"] = True
            with tarfile.open(output_path, "r:*") as tar:
                # 1. Get Project Metadata for Spacing
                spacing = (0.957, 0.957, 1.5) # Default fallback for Sample 0051
                try:
                    main_plist = tar.extractfile("main.plist")
                    if main_plist:
                        main_data = plistlib.load(main_plist)
                        # InVesalius plist structure varies, but usually contains spacing
                        # If not found, we use the known ground truth for this dataset
                        if "spacing" in main_data:
                            spacing = tuple(float(x) for x in main_data["spacing"])
                except Exception as e:
                    print(f"Warning reading metadata: {e}")

                voxel_volume = spacing[0] * spacing[1] * spacing[2]
                
                # 2. Find and Measure Masks
                # Masks are stored as .npy files (usually mask_0.npy, etc.)
                mask_files = [m for m in tar.getnames() if m.startswith("mask") and m.endswith(".npy")]
                
                if mask_files:
                    result["mask_found"] = True
                    # We check all masks and take the one that best fits (or the last one modified/created)
                    # For this task, we assume the user saves the correct active mask.
                    # We will report the volume of the mask that is closest to the target range 
                    # if multiple exist, or just the first one if only one.
                    
                    best_vol = 0.0
                    
                    for mf in mask_files:
                        f = tar.extractfile(mf)
                        if f:
                            # Load numpy array from file-like object
                            try:
                                mask_arr = np.load(f)
                                count = np.count_nonzero(mask_arr)
                                vol = count * voxel_volume
                                
                                # Heuristic: if this volume is in the target range (250k-350k), pick it immediately
                                # Otherwise keep track of the last one or largest one
                                if 250000 <= vol <= 350000:
                                    best_vol = vol
                                    result["voxel_count"] = int(count)
                                    break 
                                else:
                                    best_vol = vol
                                    result["voxel_count"] = int(count)
                            except Exception as e:
                                print(f"Error reading mask {mf}: {e}")

                    result["mask_volume_mm3"] = float(best_vol)

    except Exception as e:
        result["error"] = str(e)

# Save result to JSON
with open("/tmp/calibrate_volume_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="