#!/bin/bash
echo "=== Exporting pointing_model_construction results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Extract Telescope States
PARK_STATE=$(indi_getprop -1 "Telescope Simulator.TELESCOPE_PARK.PARK" 2>/dev/null | cut -d= -f2 || echo "Unknown")
UNPARK_STATE=$(indi_getprop -1 "Telescope Simulator.TELESCOPE_PARK.UNPARK" 2>/dev/null | cut -d= -f2 || echo "Unknown")

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
PM_DIR="/home/ga/Images/pointing_model"
PM_FILE="/home/ga/Documents/pointing_model.dat"
SKY_FILE="/home/ga/Images/pointing_model/final_sky.png"

# 3. Read File States and serialize to JSON via Python
python3 - << PYEOF
import json
import os
import base64

task_start = int("$TASK_START")
pm_dir = "$PM_DIR"
pm_file = "$PM_FILE"
sky_file = "$SKY_FILE"

# Collect FITS files
fits_files = []
dirs_found = []

if os.path.exists(pm_dir):
    try:
        dirs_found = [d.lower() for d in os.listdir(pm_dir) if os.path.isdir(os.path.join(pm_dir, d))]
    except Exception:
        pass

    for root, _, files in os.walk(pm_dir):
        for f in files:
            if f.lower().endswith(('.fits', '.fit')):
                try:
                    path = os.path.join(root, f)
                    stat = os.stat(path)
                    dir_name = os.path.basename(root).lower()
                    fits_files.append({
                        'name': f,
                        'dir': dir_name,
                        'size': stat.st_size,
                        'mtime': stat.st_mtime
                    })
                except Exception:
                    pass

# Check pointing model file
pm_exists = os.path.isfile(pm_file)
pm_mtime = 0
pm_b64 = ""
if pm_exists:
    try:
        pm_mtime = os.stat(pm_file).st_mtime
        with open(pm_file, "rb") as f:
            pm_b64 = base64.b64encode(f.read()).decode("utf-8")
    except Exception:
        pass

# Check sky capture
sky_exists = os.path.isfile(sky_file)
sky_mtime = 0
sky_size = 0
if sky_exists:
    try:
        stat = os.stat(sky_file)
        sky_mtime = stat.st_mtime
        sky_size = stat.st_size
    except Exception:
        pass

result = {
    "task_start": task_start,
    "park_state": "$PARK_STATE",
    "unpark_state": "$UNPARK_STATE",
    "dirs_found": dirs_found,
    "fits_files": fits_files,
    "pm_file_exists": pm_exists,
    "pm_file_mtime": pm_mtime,
    "pm_file_b64": pm_b64,
    "sky_file_exists": sky_exists,
    "sky_file_mtime": sky_mtime,
    "sky_file_size": sky_size
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Export completed to /tmp/task_result.json")
PYEOF