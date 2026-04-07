#!/bin/bash
set -e
echo "=== Exporting Polycentric Analysis Results ==="

# Record end time
date +%s > /tmp/task_end_time.txt
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check file existences and timestamps
CSV1="/home/ga/urbansim_projects/output/zone_employment_density.csv"
CSV2="/home/ga/urbansim_projects/output/subcenter_ranking.csv"
JSON_OUT="/home/ga/urbansim_projects/output/zipf_results.json"
PLOT="/home/ga/urbansim_projects/output/ranksize_plot.png"
NB="/home/ga/urbansim_projects/notebooks/polycentric_analysis.ipynb"

# Python script to gather file stats into result JSON
python3 << PYEOF
import json
import os
import stat

task_start = int(open('/tmp/task_start_time.txt').read().strip())

def get_file_stats(filepath):
    if not os.path.exists(filepath):
        return {"exists": False, "created_during_task": False, "size": 0}
    
    mtime = os.path.getmtime(filepath)
    size = os.path.getsize(filepath)
    return {
        "exists": True,
        "created_during_task": mtime > task_start,
        "size": size
    }

results = {
    "task_start": task_start,
    "files": {
        "csv1": get_file_stats("$CSV1"),
        "csv2": get_file_stats("$CSV2"),
        "json": get_file_stats("$JSON_OUT"),
        "plot": get_file_stats("$PLOT"),
        "notebook": get_file_stats("$NB")
    }
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(results, f, indent=2)
PYEOF

chmod 644 /tmp/task_result.json
echo "Results packaged for verifier."
echo "=== Export Complete ==="