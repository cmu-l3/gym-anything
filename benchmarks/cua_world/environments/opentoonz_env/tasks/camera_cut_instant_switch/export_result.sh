#!/bin/bash
echo "=== Exporting camera_cut_instant_switch results ==="

OUTPUT_DIR="/home/ga/OpenToonz/output/camera_cut"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Run Python analysis script inside the container
# This calculates visual metrics for each frame to avoid sending large images to verifier
echo "Running frame analysis..."
python3 -c "
import os
import glob
import json
import numpy as np
from PIL import Image

output_dir = '$OUTPUT_DIR'
task_start = $TASK_START

results = {
    'frame_count': 0,
    'frames_newer_than_start': 0,
    'frame_metrics': [],
    'file_list': []
}

try:
    # Find PNG files
    files = sorted(glob.glob(os.path.join(output_dir, '*.png')))
    results['frame_count'] = len(files)
    
    metrics = []
    
    for f in files:
        # Check timestamp
        if os.path.getmtime(f) > task_start:
            results['frames_newer_than_start'] += 1
            
        results['file_list'].append(os.path.basename(f))
        
        # Image Analysis
        try:
            img = Image.open(f).convert('L') # Convert to grayscale
            arr = np.array(img)
            
            # Simple metric: 'Content Mass' (Sum of inverted pixel values)
            # Assuming white background (255), we invert so dark pixels count as mass
            # 255 - pixel_value
            inverted = 255 - arr
            # Threshold to remove compression noise (only count pixels darker than 250)
            mask = inverted > 5
            mass = np.sum(inverted[mask])
            
            metrics.append(float(mass))
        except Exception as e:
            print(f'Error analyzing {f}: {e}')
            metrics.append(0.0)
            
    results['frame_metrics'] = metrics
    results['success'] = True

except Exception as e:
    results['success'] = False
    results['error'] = str(e)

with open('/tmp/task_result.json', 'w') as f:
    json.dump(results, f)
"

# Handle permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Analysis complete. JSON generated."
cat /tmp/task_result.json
echo "=== Export complete ==="