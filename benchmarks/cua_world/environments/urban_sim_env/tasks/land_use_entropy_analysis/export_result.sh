#!/bin/bash
echo "=== Exporting land_use_entropy_analysis result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

# Take final screenshot BEFORE checking files
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Gather file metrics using Python
python3 << 'PYEOF'
import json
import os
import stat

task_start = int(open('/home/ga/.task_start_time').read().strip()) if os.path.exists('/home/ga/.task_start_time') else 0

def check_file(path):
    if not os.path.exists(path):
        return {"exists": False, "size": 0, "created_during_task": False}
    
    st = os.stat(path)
    return {
        "exists": True,
        "size": st.st_size,
        "created_during_task": st.st_mtime > task_start
    }

nb_path = "/home/ga/urbansim_projects/notebooks/land_use_entropy.ipynb"
csv_path = "/home/ga/urbansim_projects/output/zone_entropy.csv"
png_path = "/home/ga/urbansim_projects/output/entropy_barplot.png"
json_path = "/home/ga/urbansim_projects/output/entropy_summary.json"

result = {
    "task_start": task_start,
    "notebook": check_file(nb_path),
    "csv": check_file(csv_path),
    "png": check_file(png_path),
    "json": check_file(json_path)
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result manifest saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="