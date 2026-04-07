#!/bin/bash
echo "=== Exporting task result ==="

source /workspace/scripts/task_utils.sh
activate_venv

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Get timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Analyze output files programmatically
python3 << 'PYEOF'
import json, os, csv

task_start = int(open('/tmp/task_start_time.txt').read().strip()) if os.path.exists('/tmp/task_start_time.txt') else 0

result = {
    "task_start": task_start,
    "notebook_exists": False,
    "notebook_modified": False,
    "csv_exists": False,
    "csv_modified": False,
    "csv_rows": 0,
    "csv_columns": [],
    "chart_exists": False,
    "chart_modified": False,
    "chart_size_kb": 0
}

nb_path = "/home/ga/urbansim_projects/notebooks/building_vintage_analysis.ipynb"
if os.path.exists(nb_path):
    result["notebook_exists"] = True
    result["notebook_modified"] = os.path.getmtime(nb_path) > task_start

csv_path = "/home/ga/urbansim_projects/output/aging_building_zones.csv"
if os.path.exists(csv_path):
    result["csv_exists"] = True
    result["csv_modified"] = os.path.getmtime(csv_path) > task_start
    try:
        with open(csv_path, 'r') as f:
            reader = csv.reader(f)
            header = next(reader)
            result["csv_columns"] = [c.strip().lower() for c in header]
            result["csv_rows"] = sum(1 for row in reader)
    except Exception:
        pass

chart_path = "/home/ga/urbansim_projects/output/building_vintage_chart.png"
if os.path.exists(chart_path):
    result["chart_exists"] = True
    result["chart_modified"] = os.path.getmtime(chart_path) > task_start
    result["chart_size_kb"] = os.path.getsize(chart_path) / 1024

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/task_result.json

echo "Result JSON written:"
cat /tmp/task_result.json
echo "=== Export complete ==="