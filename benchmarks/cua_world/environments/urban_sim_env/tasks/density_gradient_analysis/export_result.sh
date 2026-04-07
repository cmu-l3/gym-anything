#!/bin/bash
echo "=== Exporting density gradient analysis result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

# Collect file modification and existence info
python3 << 'PYEOF'
import json, os, datetime

task_start = int(open('/home/ga/.task_start_time').read().strip()) if os.path.exists('/home/ga/.task_start_time') else 0

def check_file(path):
    if not os.path.exists(path):
        return {"exists": False, "created": False, "size_bytes": 0}
    mtime = os.path.getmtime(path)
    return {
        "exists": True,
        "created": mtime > task_start,
        "size_bytes": os.path.getsize(path),
        "mtime": mtime
    }

result = {
    "task_start_time": task_start,
    "timestamp": datetime.datetime.now().isoformat(),
    "notebook": check_file("/home/ga/urbansim_projects/notebooks/density_gradient.ipynb"),
    "csv": check_file("/home/ga/urbansim_projects/output/density_by_zone.csv"),
    "json": check_file("/home/ga/urbansim_projects/output/gradient_summary.json"),
    "png": check_file("/home/ga/urbansim_projects/output/density_gradient_plot.png")
}

with open('/tmp/_task_result_tmp.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/_task_result_tmp.json /tmp/task_result.json 2>/dev/null || sudo cp /tmp/_task_result_tmp.json /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/_task_result_tmp.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="