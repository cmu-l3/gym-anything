#!/bin/bash
echo "=== Exporting displacement risk task result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot before processing
take_screenshot /tmp/task_end.png

TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

# Quick lightweight checks to build the manifest for verifier
python3 << 'PYEOF'
import json, os, datetime

task_start = int(open('/home/ga/.task_start_time').read().strip()) if os.path.exists('/home/ga/.task_start_time') else 0

result = {
    "task_start_time": task_start,
    "export_time": datetime.datetime.now().isoformat(),
    "files": {}
}

paths = {
    "notebook": "/home/ga/urbansim_projects/notebooks/displacement_risk.ipynb",
    "csv": "/home/ga/urbansim_projects/output/displacement_risk.csv",
    "json": "/home/ga/urbansim_projects/output/risk_summary.json",
    "plot": "/home/ga/urbansim_projects/output/displacement_risk_plot.png"
}

for name, path in paths.items():
    exists = os.path.exists(path)
    modified_after_start = os.path.getmtime(path) > task_start if exists else False
    size = os.path.getsize(path) if exists else 0
    
    result["files"][name] = {
        "exists": exists,
        "modified_after_start": modified_after_start,
        "size_bytes": size
    }

with open('/tmp/_task_result_tmp.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

# Move file with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/_task_result_tmp.json /tmp/task_result.json 2>/dev/null || sudo cp /tmp/_task_result_tmp.json /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/_task_result_tmp.json

echo "Result manifest saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="