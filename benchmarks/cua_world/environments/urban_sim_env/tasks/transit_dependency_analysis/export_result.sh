#!/bin/bash
echo "=== Exporting transit dependency analysis result ==="

source /workspace/scripts/task_utils.sh
activate_venv

# Capture final visual state
take_screenshot /tmp/task_end.png

# Retrieve task start time
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

# Use Python to accurately check file existence, modified times, and initial notebook parsing
python << 'PYEOF'
import json, re, os, time

task_start = int(open('/home/ga/.task_start_time').read().strip()) if os.path.exists('/home/ga/.task_start_time') else 0

result = {
    "notebook_exists": False,
    "notebook_modified": False,
    "notebook_analysis": {},
    "csv_exists": False,
    "csv_size": 0,
    "csv_created_during_task": False,
    "png1_exists": False,
    "png1_size": 0,
    "png1_created": False,
    "png2_exists": False,
    "png2_size": 0,
    "png2_created": False,
    "png3_exists": False,
    "png3_size": 0,
    "png3_created": False,
    "task_start_time": task_start
}

# 1. Check Notebook
nb_path = "/home/ga/urbansim_projects/notebooks/transit_dependency_analysis.ipynb"
if os.path.exists(nb_path):
    result["notebook_exists"] = True
    result["notebook_modified"] = os.path.getmtime(nb_path) > task_start
    try:
        with open(nb_path, 'r') as f:
            nb = json.load(f)
        code_cells = [c for c in nb.get('cells', []) if c.get('cell_type') == 'code']
        
        all_code = ''
        for c in code_cells:
            src = c.get('source', '')
            if isinstance(src, list):
                src = ''.join(src)
            # Remove comments for matching
            lines = [l for l in src.split('\n') if not l.strip().startswith('#')]
            all_code += '\n'.join(lines) + '\n'
            
        result["notebook_analysis"] = {
            "num_code_cells": len(code_cells),
            "num_executed_cells": sum(1 for c in code_cells if c.get('execution_count') is not None),
            "has_read_hdf": bool(re.search(r'read_hdf|HDFStore', all_code)),
            "has_merge": bool(re.search(r'merge|join', all_code)),
            "has_groupby": bool(re.search(r'groupby', all_code)),
            "has_plot": bool(re.search(r'plot|hist|scatter|bar', all_code)),
            "has_to_csv": bool(re.search(r'to_csv', all_code))
        }
    except Exception as e:
        result["notebook_analysis"] = {"error": str(e)}

# 2. Check CSV
csv_path = "/home/ga/urbansim_projects/output/zone_vehicle_ownership.csv"
if os.path.exists(csv_path):
    result["csv_exists"] = True
    result["csv_size"] = os.path.getsize(csv_path)
    result["csv_created_during_task"] = os.path.getmtime(csv_path) > task_start

# 3. Check PNGs
pngs = {
    "png1": "/home/ga/urbansim_projects/output/vehicle_ownership_histogram.png",
    "png2": "/home/ga/urbansim_projects/output/income_vs_cars_scatter.png",
    "png3": "/home/ga/urbansim_projects/output/transit_dependency_by_zone.png"
}

for key, path in pngs.items():
    if os.path.exists(path):
        result[f"{key}_exists"] = True
        result[f"{key}_size"] = os.path.getsize(path)
        result[f"{key}_created"] = os.path.getmtime(path) > task_start

# Save results
with open('/tmp/_task_result_tmp.json', 'w') as f:
    json.dump(result, f, indent=2, default=str)
PYEOF

# Move result safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/_task_result_tmp.json /tmp/task_result.json 2>/dev/null || sudo cp /tmp/_task_result_tmp.json /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/_task_result_tmp.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="