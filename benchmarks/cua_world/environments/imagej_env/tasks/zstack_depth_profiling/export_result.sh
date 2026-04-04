#!/bin/bash
# Export script for zstack_depth_profiling task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting Z-Stack Profiling Results ==="

take_screenshot /tmp/task_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

python3 << 'PYEOF'
import json
import os
import csv
import sys
import math

# Try importing image libraries
try:
    from PIL import Image
    import numpy as np
    HAS_IMG_LIB = True
except ImportError:
    HAS_IMG_LIB = False

results_dir = "/home/ga/ImageJ_Data/results"
task_start_file = "/tmp/task_start_timestamp"

expected_files = {
    "mip": "fly_brain_MIP.tif",
    "avg": "fly_brain_AVG.tif",
    "reslice": "fly_brain_reslice_XZ.tif",
    "montage": "fly_brain_montage.tif",
    "profile": "fly_brain_z_profile.csv"
}

output = {
    "files": {},
    "profile_data": {
        "rows": 0,
        "mean_intensity": 0,
        "std_dev": 0,
        "min_val": 0,
        "max_val": 0,
        "is_valid": False
    },
    "task_start_timestamp": 0
}

# Get task start time
try:
    with open(task_start_file, 'r') as f:
        output["task_start_timestamp"] = int(f.read().strip())
except:
    pass

# Check each expected file
for key, filename in expected_files.items():
    path = os.path.join(results_dir, filename)
    file_info = {
        "exists": False,
        "size": 0,
        "mtime": 0,
        "width": 0,
        "height": 0,
        "mean_pixel": 0,
        "max_pixel": 0
    }
    
    if os.path.isfile(path):
        file_info["exists"] = True
        file_info["size"] = os.path.getsize(path)
        file_info["mtime"] = int(os.path.getmtime(path))
        
        # Analyze image content if it's an image
        if HAS_IMG_LIB and filename.endswith('.tif'):
            try:
                img = Image.open(path)
                file_info["width"], file_info["height"] = img.size
                arr = np.array(img)
                file_info["mean_pixel"] = float(np.mean(arr))
                file_info["max_pixel"] = float(np.max(arr))
            except Exception as e:
                file_info["error"] = str(e)
                
    output["files"][key] = file_info

# Analyze CSV profile specifically
profile_path = os.path.join(results_dir, expected_files["profile"])
if os.path.isfile(profile_path):
    try:
        with open(profile_path, 'r') as f:
            # Handle different CSV formats (ImageJ sometimes adds header lines)
            content = f.readlines()
            # Filter for data rows (numbers)
            data_values = []
            for line in content:
                parts = line.strip().split(',')
                # Look for the intensity column (usually 2nd column if X,Y)
                # Or just take the last numeric value
                nums = []
                for p in parts:
                    try:
                        nums.append(float(p))
                    except:
                        pass
                if nums:
                    # Usually the intensity is the second value (index, mean) or just a list of values
                    # If Plot Z-axis profile 'List' is used, it often gives: X, Y
                    if len(nums) >= 2:
                        data_values.append(nums[1])
                    elif len(nums) == 1:
                        data_values.append(nums[0])
            
            if data_values:
                output["profile_data"]["rows"] = len(data_values)
                output["profile_data"]["mean_intensity"] = sum(data_values) / len(data_values)
                # Calculate simple std dev
                mean = output["profile_data"]["mean_intensity"]
                variance = sum([((x - mean) ** 2) for x in data_values]) / len(data_values)
                output["profile_data"]["std_dev"] = math.sqrt(variance)
                output["profile_data"]["min_val"] = min(data_values)
                output["profile_data"]["max_val"] = max(data_values)
                output["profile_data"]["is_valid"] = True
                
    except Exception as e:
        output["profile_data"]["error"] = str(e)

with open("/tmp/zstack_result.json", "w") as f:
    json.dump(output, f, indent=2)
PYEOF

echo "Export complete."