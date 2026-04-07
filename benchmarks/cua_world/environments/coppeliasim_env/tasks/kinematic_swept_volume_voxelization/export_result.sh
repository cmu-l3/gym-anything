#!/bin/bash
echo "=== Exporting kinematic_swept_volume_voxelization Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Run Python script to securely analyze the CSV and JSON, writing the output to /tmp/task_result.json
python3 << 'PYEOF'
import os
import json
import csv

try:
    with open('/tmp/task_start_ts', 'r') as f:
        task_start = int(f.read().strip())
except:
    task_start = 0

csv_path = "/home/ga/Documents/CoppeliaSim/exports/swept_voxels.csv"
json_path = "/home/ga/Documents/CoppeliaSim/exports/volume_report.json"

result = {
    "task_start": task_start,
    "csv_exists": False,
    "csv_is_new": False,
    "csv_rows": 0,
    "csv_math_consistent": False,
    "csv_bounds_min": [float('inf'), float('inf'), float('inf')],
    "csv_bounds_max": [float('-inf'), float('-inf'), float('-inf')],
    "json_exists": False,
    "json_is_new": False,
    "json_has_fields": False,
    "json_data": {}
}

# 1. Analyze CSV
if os.path.exists(csv_path):
    result["csv_exists"] = True
    if os.path.getmtime(csv_path) > task_start:
        result["csv_is_new"] = True

    math_consistent = True
    rows_count = 0
    bounds_min = [float('inf'), float('inf'), float('inf')]
    bounds_max = [float('-inf'), float('-inf'), float('-inf')]

    try:
        with open(csv_path, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            headers = [h.strip().lower() for h in reader.fieldnames or []]
            
            # Require correct columns
            req_cols = ['voxel_i', 'voxel_j', 'voxel_k', 'center_x', 'center_y', 'center_z']
            if all(c in headers for c in req_cols):
                for row in reader:
                    rows_count += 1
                    vi, vj, vk = int(row['voxel_i']), int(row['voxel_j']), int(row['voxel_k'])
                    cx, cy, cz = float(row['center_x']), float(row['center_y']), float(row['center_z'])

                    # Update bounding box
                    bounds_min = [min(bounds_min[0], cx), min(bounds_min[1], cy), min(bounds_min[2], cz)]
                    bounds_max = [max(bounds_max[0], cx), max(bounds_max[1], cy), max(bounds_max[2], cz)]

                    # Validate math matching index * 0.05
                    if abs(cx - vi*0.05) > 1e-3 or abs(cy - vj*0.05) > 1e-3 or abs(cz - vk*0.05) > 1e-3:
                        math_consistent = False
            else:
                math_consistent = False
    except Exception as e:
        result["csv_error"] = str(e)
        math_consistent = False

    result["csv_rows"] = rows_count
    if rows_count > 0:
        result["csv_math_consistent"] = math_consistent
        result["csv_bounds_min"] = bounds_min
        result["csv_bounds_max"] = bounds_max

# 2. Analyze JSON
if os.path.exists(json_path):
    result["json_exists"] = True
    if os.path.getmtime(json_path) > task_start:
        result["json_is_new"] = True

    try:
        with open(json_path, 'r', encoding='utf-8') as f:
            data = json.load(f)
            result["json_data"] = data
            req_fields = [
                'voxel_resolution_m', 'total_occupied_voxels', 'estimated_volume_m3',
                'bounding_box_min_m', 'bounding_box_max_m', 'max_joint_ranges_swept_deg'
            ]
            if all(k in data for k in req_fields):
                result["json_has_fields"] = True
    except Exception as e:
        result["json_error"] = str(e)

# 3. Write output
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
PYEOF

# Ensure permissions are correct
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="