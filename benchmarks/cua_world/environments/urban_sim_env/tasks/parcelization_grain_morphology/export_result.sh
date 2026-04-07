#!/bin/bash
echo "=== Exporting parcelization_grain_morphology result ==="

source /workspace/scripts/task_utils.sh
activate_venv

# Take final screenshot
take_screenshot /tmp/task_end.png

TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

# Analyze artifacts via python to create a structured JSON report
python << 'PYEOF'
import json
import re
import os
import datetime

task_start = int(open('/home/ga/.task_start_time').read().strip()) if os.path.exists('/home/ga/.task_start_time') else 0

result = {
    "notebook_exists": False,
    "notebook_modified": False,
    "notebook_analysis": {},
    "zone_csv_exists": False,
    "zone_csv_created": False,
    "zone_csv_rows": 0,
    "zone_csv_cols": "",
    "summary_csv_exists": False,
    "summary_csv_created": False,
    "summary_csv_rows": 0,
    "summary_csv_cols": "",
    "plot_exists": False,
    "plot_size_kb": 0,
    "plot_created": False,
    "task_start_time": task_start
}

nb_path = "/home/ga/urbansim_projects/notebooks/parcelization_morphology.ipynb"
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
            # Remove comments for code analysis
            lines = [l for l in src.split('\n') if not l.strip().startswith('#')]
            all_code += '\n'.join(lines) + '\n'
            
        result["notebook_analysis"] = {
            "num_code_cells": len(code_cells),
            "num_executed_cells": sum(1 for c in code_cells if c.get('execution_count') is not None),
            "has_pandas": bool(re.search(r'import pandas|from pandas', all_code)),
            "has_read_hdf": bool(re.search(r'read_hdf|HDFStore', all_code)),
            "has_parcels": bool(re.search(r'parcels', all_code, re.IGNORECASE)),
            "has_jobs": bool(re.search(r'jobs', all_code, re.IGNORECASE)),
            "has_buildings": bool(re.search(r'buildings', all_code, re.IGNORECASE)),
            "has_merge_or_join": bool(re.search(r'merge|join', all_code)),
            "has_groupby": bool(re.search(r'groupby', all_code)),
            "has_to_csv": bool(re.search(r'to_csv', all_code)),
            "has_savefig": bool(re.search(r'savefig', all_code)),
            "has_cut_or_apply": bool(re.search(r'pd\.cut|apply|np\.select|loc\[', all_code))
        }
    except Exception as e:
        result["notebook_analysis"] = {"error": str(e)}

# Check Zone CSV
zone_csv_path = "/home/ga/urbansim_projects/output/zone_morphology.csv"
if os.path.exists(zone_csv_path):
    result["zone_csv_exists"] = True
    result["zone_csv_created"] = os.path.getmtime(zone_csv_path) > task_start
    try:
        with open(zone_csv_path, 'r') as f:
            lines = f.readlines()
        result["zone_csv_rows"] = len(lines)
        if lines:
            result["zone_csv_cols"] = lines[0].strip().lower().replace('"', '')
    except Exception:
        pass

# Check Summary CSV
sum_csv_path = "/home/ga/urbansim_projects/output/grain_summary.csv"
if os.path.exists(sum_csv_path):
    result["summary_csv_exists"] = True
    result["summary_csv_created"] = os.path.getmtime(sum_csv_path) > task_start
    try:
        with open(sum_csv_path, 'r') as f:
            lines = f.readlines()
        result["summary_csv_rows"] = len(lines)
        if lines:
            result["summary_csv_cols"] = lines[0].strip().lower().replace('"', '')
    except Exception:
        pass

# Check Plot
plot_path = "/home/ga/urbansim_projects/output/morphology_density_chart.png"
if os.path.exists(plot_path):
    result["plot_exists"] = True
    result["plot_size_kb"] = os.path.getsize(plot_path) / 1024
    result["plot_created"] = os.path.getmtime(plot_path) > task_start

result["timestamp"] = datetime.datetime.now().isoformat()

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