#!/bin/bash
echo "=== Exporting vacancy_rate_analysis result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")
NB_PATH="/home/ga/urbansim_projects/notebooks/vacancy_analysis.ipynb"
CSV_PATH="/home/ga/urbansim_projects/output/vacancy_by_zone.csv"
JSON_PATH="/home/ga/urbansim_projects/output/vacancy_summary.json"
PNG_PATH="/home/ga/urbansim_projects/output/vacancy_distribution.png"

# Collect file timestamps into a metadata JSON so the verifier knows accurate container mtimes
python3 << PYEOF
import json
import os

def get_file_info(path):
    if os.path.exists(path):
        return {
            "exists": True,
            "mtime": os.path.getmtime(path),
            "size": os.path.getsize(path)
        }
    return {"exists": False, "mtime": 0, "size": 0}

result = {
    "task_start_time": $TASK_START,
    "notebook": get_file_info("$NB_PATH"),
    "csv": get_file_info("$CSV_PATH"),
    "json": get_file_info("$JSON_PATH"),
    "png": get_file_info("$PNG_PATH")
}

with open('/tmp/task_metadata.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

echo "File metadata exported to /tmp/task_metadata.json"
cat /tmp/task_metadata.json
echo "=== Export complete ==="