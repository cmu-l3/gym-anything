#!/bin/bash
echo "=== Exporting ev_charging_allocation result ==="

source /workspace/scripts/task_utils.sh
activate_venv

# Take final state screenshot
take_screenshot /tmp/task_end.png

# Capture notebook and file analysis using python
python << 'PYEOF'
import json
import re
import os
import datetime

task_start_time = 0
if os.path.exists('/home/ga/.task_start_time'):
    with open('/home/ga/.task_start_time', 'r') as f:
        task_start_time = int(f.read().strip())

result = {
    "task_start_time": task_start_time,
    "notebook_exists": False,
    "notebook_modified_during_task": False,
    "notebook_analysis": {},
    "csv_exists": False,
    "csv_modified_during_task": False,
    "plot_exists": False,
    "plot_modified_during_task": False,
    "plot_size_bytes": 0,
    "timestamp": datetime.datetime.now().isoformat()
}

# 1. Analyze Notebook
nb_path = "/home/ga/urbansim_projects/notebooks/ev_charging_analysis.ipynb"
if os.path.exists(nb_path):
    result["notebook_exists"] = True
    result["notebook_modified_during_task"] = os.path.getmtime(nb_path) > task_start_time
    
    try:
        with open(nb_path, 'r') as f:
            nb = json.load(f)
            
        code_cells = [c for c in nb.get('cells', []) if c.get('cell_type') == 'code']
        all_code = ''
        
        for c in code_cells:
            src = c.get('source', '')
            if isinstance(src, list):
                src = ''.join(src)
            # Exclude comments
            lines = [l for l in src.split('\n') if not l.strip().startswith('#')]
            all_code += '\n'.join(lines) + '\n'
            
        # Strip strings to prevent keyword-in-string gaming
        clean_code = re.sub(r'"""[\s\S]*?"""|\'\'\'[\s\S]*?\'\'\'', '', all_code)
        clean_code = re.sub(r'"[^"\n]*"|\'[^\'\n]*\'', '', clean_code)

        num_executed = sum(1 for c in code_cells if c.get('execution_count') is not None)
        
        # Check for error outputs
        has_errors = False
        for cell in code_cells:
            if cell.get('execution_count') is not None:
                for out in cell.get('outputs', []):
                    if out.get('output_type') == 'error':
                        has_errors = True
                        break

        result["notebook_analysis"] = {
            "num_code_cells": len(code_cells),
            "num_executed_cells": num_executed,
            "has_errors": has_errors,
            "has_pandas": bool(re.search(r'import pandas|from pandas', clean_code)),
            "has_read_hdf": bool(re.search(r'read_hdf|HDFStore', clean_code)),
            "has_joins": bool(re.search(r'merge\s*\(|join\s*\(', clean_code)),
            "has_groupby": bool(re.search(r'groupby\s*\(', clean_code)),
            "has_threshold_logic": bool(re.search(r'>=\s*5|>=\s*1|>\s*4|>\s*0', clean_code)),
            "has_households_filter": bool(re.search(r'>=\s*100|>\s*99', clean_code)),
            "has_to_csv": bool(re.search(r'to_csv\s*\(', clean_code)),
            "has_plot_save": bool(re.search(r'savefig\s*\(', clean_code))
        }
    except Exception as e:
        result["notebook_analysis"]["error"] = str(e)

# 2. Analyze CSV metadata
csv_path = "/home/ga/urbansim_projects/output/ev_charging_priority_zones.csv"
if os.path.exists(csv_path):
    result["csv_exists"] = True
    result["csv_modified_during_task"] = os.path.getmtime(csv_path) > task_start_time

# 3. Analyze Plot metadata
plot_path = "/home/ga/urbansim_projects/output/ev_vulnerability_scatter.png"
if os.path.exists(plot_path):
    result["plot_exists"] = True
    result["plot_modified_during_task"] = os.path.getmtime(plot_path) > task_start_time
    result["plot_size_bytes"] = os.path.getsize(plot_path)

with open('/tmp/task_result_tmp.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

# Move to final destination securely
rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/task_result_tmp.json /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f /tmp/task_result_tmp.json

echo "=== Export complete ==="