#!/bin/bash
echo "=== Exporting import_scan_sequence_twos results ==="

OUTPUT_DIR="/home/ga/OpenToonz/output/twos_import"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 1. Analyze Output Files
echo "Analyzing output sequence..."
# We use a python script to calculate frame-to-frame differences to verify the "on twos" pattern
# Pattern expected: [Diff=0, Diff>0, Diff=0, Diff>0, ...]
# i.e., Frame 1 and 2 are same, 2 and 3 differ, 3 and 4 same.

python3 -c "
import os
import json
import glob
import numpy as np
from PIL import Image

output_dir = '$OUTPUT_DIR'
task_start = $TASK_START
results = {
    'file_count': 0,
    'files_created_during_task': 0,
    'pattern_analysis': [],
    'is_valid_sequence': False,
    'error': ''
}

try:
    # Get all image files sorted by name
    files = sorted(glob.glob(os.path.join(output_dir, '*.png')) + 
                   glob.glob(os.path.join(output_dir, '*.tga')) + 
                   glob.glob(os.path.join(output_dir, '*.jpg')))
    
    results['file_count'] = len(files)
    
    if not files:
        results['error'] = 'No output files found'
    else:
        # Check timestamps
        new_files = 0
        for f in files:
            if os.path.getmtime(f) > task_start:
                new_files += 1
        results['files_created_during_task'] = new_files

        # Analyze frame differences
        # We limit analysis to first 24 frames to save time/memory
        analyze_files = files[:24]
        diffs = []
        
        if len(analyze_files) > 1:
            # Load images
            imgs = [np.array(Image.open(f).convert('L').resize((100,100))) for f in analyze_files]
            
            for i in range(len(imgs) - 1):
                # Calculate Mean Squared Error between consecutive frames
                err = np.mean((imgs[i].astype('float') - imgs[i+1].astype('float')) ** 2)
                diffs.append(float(err))
                
        results['pattern_analysis'] = diffs
        results['is_valid_sequence'] = True

except Exception as e:
    results['error'] = str(e)

# Save to JSON
with open('/tmp/analysis_result.json', 'w') as f:
    json.dump(results, f)
"

# Merge analysis into final result
if [ -f /tmp/analysis_result.json ]; then
    cp /tmp/analysis_result.json /tmp/task_result.json
else
    echo '{"error": "Analysis script failed"}' > /tmp/task_result.json
fi

# Add screenshot path
# Use jq if available, otherwise simple string manipulation or python
python3 -c "
import json
try:
    with open('/tmp/task_result.json', 'r') as f:
        data = json.load(f)
    data['screenshot_path'] = '/tmp/task_final.png'
    data['task_start'] = $TASK_START
    data['task_end'] = $TASK_END
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(data, f)
except:
    pass
"

# Permission fix
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="