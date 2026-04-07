#!/bin/bash
echo "=== Exporting income_segregation_indices result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

# Use Python to evaluate file creation states reliably
python3 << 'PYEOF'
import json, os, time

task_start = int(open('/home/ga/.task_start_time').read().strip()) if os.path.exists('/home/ga/.task_start_time') else 0

def check_file(path):
    if not os.path.exists(path):
        return {"exists": False, "created_during_task": False, "size": 0}
    mtime = os.path.getmtime(path)
    return {
        "exists": True,
        "created_during_task": mtime >= task_start,
        "size": os.path.getsize(path),
        "mtime": mtime
    }

result = {
    "task_start_time": task_start,
    "timestamp": time.time(),
    "files": {
        "notebook": check_file("/home/ga/urbansim_projects/notebooks/income_segregation.ipynb"),
        "csv": check_file("/home/ga/urbansim_projects/output/zone_income_distribution.csv"),
        "json": check_file("/home/ga/urbansim_projects/output/segregation_indices.json"),
        "png": check_file("/home/ga/urbansim_projects/output/income_segregation_chart.png")
    }
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="