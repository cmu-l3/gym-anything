#!/bin/bash
echo "=== Exporting parcel lot coverage analysis result ==="

source /workspace/scripts/task_utils.sh
activate_venv

take_screenshot /tmp/task_end.png
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

python << 'PYEOF'
import json, re, os

task_start = int(open('/home/ga/.task_start_time').read().strip()) if os.path.exists('/home/ga/.task_start_time') else 0

result = {
    "notebook_exists": False,
    "notebook_modified": False,
    "csv_exists": False,
    "csv_created": False,
    "csv_rows": 0,
    "csv_columns": "",
    "json_exists": False,
    "json_created": False,
    "json_data": {},
    "plot_exists": False,
    "plot_created": False,
    "plot_size_kb": 0,
    "task_start_time": task_start
}

# Notebook info
nb_path = "/home/ga/urbansim_projects/notebooks/lot_coverage_analysis.ipynb"
if os.path.exists(nb_path):
    result["notebook_exists"] = True
    result["notebook_modified"] = os.path.getmtime(nb_path) > task_start

# CSV info
csv_path = "/home/ga/urbansim_projects/output/zone_lot_coverage.csv"
if os.path.exists(csv_path):
    result["csv_exists"] = True
    result["csv_created"] = os.path.getmtime(csv_path) > task_start
    try:
        with open(csv_path, 'r') as f:
            lines = f.readlines()
        result["csv_rows"] = len(lines)
        if lines:
            result["csv_columns"] = lines[0].strip().lower().replace('"', '')
    except Exception:
        pass

# JSON info
json_path = "/home/ga/urbansim_projects/output/coverage_summary.json"
if os.path.exists(json_path):
    result["json_exists"] = True
    result["json_created"] = os.path.getmtime(json_path) > task_start
    try:
        with open(json_path, 'r') as f:
            data = json.load(f)
            result["json_data"] = {k: v for k, v in data.items() if isinstance(v, (int, float, str))}
    except Exception:
        pass

# Plot info
plot_path = "/home/ga/urbansim_projects/output/coverage_histogram.png"
if os.path.exists(plot_path):
    result["plot_exists"] = True
    result["plot_created"] = os.path.getmtime(plot_path) > task_start
    result["plot_size_kb"] = os.path.getsize(plot_path) / 1024

result["timestamp"] = __import__('datetime').datetime.now().isoformat()
with open('/tmp/_task_result_tmp.json', 'w') as f:
    json.dump(result, f, indent=2, default=str)
PYEOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/_task_result_tmp.json /tmp/task_result.json 2>/dev/null || sudo cp /tmp/_task_result_tmp.json /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/_task_result_tmp.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="