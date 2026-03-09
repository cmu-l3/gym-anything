#!/bin/bash
echo "=== Exporting Galaxy Cluster Segmentation Results ==="

# 1. Capture Final State
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Get Timing
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Analyze Results using Python (runs inside container with access to numpy/PIL)
#    We check file existence, timestamps, CSV content, and image statistics.
python3 -c "
import os
import json
import csv
import sys
import numpy as np
from PIL import Image

results = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'filtered_image_exists': False,
    'filtered_image_valid': False,
    'csv_exists': False,
    'csv_valid': False,
    'mask_exists': False,
    'cluster_count': 0,
    'mean_area': 0,
    'image_stats': {'std_dev': 0, 'mean': 0},
    'timestamp_valid': False
}

results_dir = '/home/ga/Fiji_Data/results/astronomy'
filtered_path = os.path.join(results_dir, 'm51_filtered.tif')
csv_path = os.path.join(results_dir, 'cluster_measurements.csv')
mask_path = os.path.join(results_dir, 'cluster_mask.png')

# --- Check Filtered Image ---
if os.path.exists(filtered_path):
    results['filtered_image_exists'] = True
    # Check timestamp
    if os.path.getmtime(filtered_path) > $TASK_START:
        results['timestamp_valid'] = True
    
    try:
        img = Image.open(filtered_path)
        arr = np.array(img)
        # Bandpass filter should reduce the high dynamic range of the galaxy core
        # resulting in a lower standard deviation compared to raw, or specific distribution.
        # We just record stats here for the verifier to judge.
        results['image_stats']['std_dev'] = float(np.std(arr))
        results['image_stats']['mean'] = float(np.mean(arr))
        results['filtered_image_valid'] = True
    except Exception as e:
        print(f'Error analyzing image: {e}')

# --- Check CSV ---
if os.path.exists(csv_path):
    results['csv_exists'] = True
    try:
        with open(csv_path, 'r') as f:
            reader = csv.DictReader(f)
            rows = list(reader)
            results['cluster_count'] = len(rows)
            
            if len(rows) > 0:
                # Check for Area column
                keys = [k.lower() for k in rows[0].keys()]
                if any('area' in k for k in keys):
                    results['csv_valid'] = True
                    
                # Calculate mean area
                areas = []
                for r in rows:
                    for k, v in r.items():
                        if 'area' in k.lower():
                            try:
                                areas.append(float(v))
                            except: pass
                if areas:
                    results['mean_area'] = sum(areas) / len(areas)
    except Exception as e:
        print(f'Error analyzing CSV: {e}')

# --- Check Mask ---
if os.path.exists(mask_path):
    results['mask_exists'] = True

# Write JSON
with open('/tmp/task_result.json', 'w') as f:
    json.dump(results, f)
"

# 4. Permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Result JSON written to /tmp/task_result.json"
cat /tmp/task_result.json