#!/bin/bash
echo "=== Exporting spatial autocorrelation analysis result ==="

source /workspace/scripts/task_utils.sh
take_screenshot /tmp/task_final.png

# Extract metadata using python to safely parse file sizes and timestamps
/opt/urbansim_env/bin/python << 'PYEOF'
import json
import os

task_start = int(open('/tmp/task_start_time.txt').read().strip()) if os.path.exists('/tmp/task_start_time.txt') else 0

def get_file_info(path):
    if os.path.exists(path):
        return {
            "exists": True,
            "created_during_task": os.path.getmtime(path) > task_start,
            "size_kb": os.path.getsize(path) / 1024.0
        }
    return {"exists": False, "created_during_task": False, "size_kb": 0}

result = {
    "notebook": get_file_info('/home/ga/urbansim_projects/notebooks/spatial_autocorrelation.ipynb'),
    "csv": get_file_info('/home/ga/urbansim_projects/output/lisa_results.csv'),
    "png": get_file_info('/home/ga/urbansim_projects/output/lisa_map.png'),
    "json": get_file_info('/home/ga/urbansim_projects/output/spatial_summary.json')
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/task_result.json
echo "Result metadata saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="