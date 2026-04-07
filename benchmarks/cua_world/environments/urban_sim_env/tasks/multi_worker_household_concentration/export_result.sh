#!/bin/bash
echo "=== Exporting multi_worker_household_concentration result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

# Collect file modification metadata
python3 << 'PYEOF'
import json, os, datetime

task_start = int(open('/home/ga/.task_start_time').read().strip()) if os.path.exists('/home/ga/.task_start_time') else 0

result = {
    "task_start_time": task_start,
    "files": {},
    "timestamp": datetime.datetime.now().isoformat()
}

paths = {
    "notebook": "/home/ga/urbansim_projects/notebooks/worker_demographics_analysis.ipynb",
    "json": "/home/ga/urbansim_projects/output/citywide_worker_income.json",
    "csv": "/home/ga/urbansim_projects/output/zone_worker_profiles.csv",
    "plot": "/home/ga/urbansim_projects/output/worker_income_scatter.png"
}

for key, path in paths.items():
    if os.path.exists(path):
        mtime = os.path.getmtime(path)
        result["files"][key] = {
            "exists": True,
            "size_bytes": os.path.getsize(path),
            "modified_after_start": mtime > task_start
        }
    else:
        result["files"][key] = {
            "exists": False,
            "size_bytes": 0,
            "modified_after_start": False
        }

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="