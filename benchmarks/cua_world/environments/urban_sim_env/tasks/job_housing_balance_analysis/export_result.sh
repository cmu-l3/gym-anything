#!/bin/bash
echo "=== Exporting result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Package metadata into JSON
python3 << 'PYEOF'
import os
import json

task_start_path = '/home/ga/.task_start_time'
task_start = int(open(task_start_path).read().strip()) if os.path.exists(task_start_path) else 0

def get_file_info(path):
    if os.path.exists(path):
        return {
            "exists": True,
            "created_during_task": os.path.getmtime(path) > task_start,
            "size_bytes": os.path.getsize(path)
        }
    return {"exists": False, "created_during_task": False, "size_bytes": 0}

result = {
    "task_start": task_start,
    "csv": get_file_info("/home/ga/urbansim_projects/output/zone_job_housing_balance.csv"),
    "json": get_file_info("/home/ga/urbansim_projects/output/job_housing_summary.json"),
    "png": get_file_info("/home/ga/urbansim_projects/output/job_housing_balance_chart.png"),
    "notebook": get_file_info("/home/ga/urbansim_projects/notebooks/job_housing_balance.ipynb")
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/task_result.json
echo "Export Complete. Result metadata:"
cat /tmp/task_result.json