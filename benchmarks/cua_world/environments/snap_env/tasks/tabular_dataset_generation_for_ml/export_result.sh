#!/bin/bash
echo "=== Exporting tabular_dataset_generation_for_ml result ==="

source /workspace/utils/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Extract result properties using Python
python3 << 'PYEOF'
import os
import json
import random
import glob

task_start = 0
if os.path.exists('/tmp/task_start_ts'):
    with open('/tmp/task_start_ts', 'r') as f:
        task_start = int(f.read().strip())

# Look for the exported file (handles minor typos in extension)
possible_files = glob.glob('/home/ga/snap_exports/ml_training_data*')
if possible_files:
    csv_path = possible_files[0]
else:
    csv_path = '/home/ga/snap_exports/ml_training_data.csv'

result = {
    'task_start': task_start,
    'csv_found': False,
    'csv_created_after_start': False,
    'headers': [],
    'row_count': 0,
    'samples': [],
    'error': None
}

if os.path.exists(csv_path):
    mtime = int(os.path.getmtime(csv_path))
    if mtime > task_start:
        result['csv_created_after_start'] = True
    result['csv_found'] = True
    
    try:
        rows = []
        with open(csv_path, 'r', encoding='utf-8', errors='ignore') as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith('#'): continue
                # SNAP might use tab or comma
                delim = '\t' if '\t' in line else ','
                rows.append([col.strip() for col in line.split(delim)])
        
        if rows:
            result['headers'] = rows[0]
            data_rows = rows[1:]
            result['row_count'] = len(data_rows)
            
            # Send back random samples for mathematical integrity check
            if len(data_rows) > 0:
                result['samples'] = random.sample(data_rows, min(20, len(data_rows)))
    except Exception as e:
        result['error'] = str(e)

with open('/tmp/ml_task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f"Result extracted from {csv_path} and written to /tmp/ml_task_result.json")
PYEOF

echo "=== Export Complete ==="