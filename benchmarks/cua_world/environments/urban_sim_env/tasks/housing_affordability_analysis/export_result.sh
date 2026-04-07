#!/bin/bash
echo "=== Exporting housing affordability analysis result ==="

source /workspace/scripts/task_utils.sh
activate_venv

# Take final screenshot for visual verification
take_screenshot /tmp/task_end.png
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

# Collect result data via Python internally
python << 'PYEOF'
import json, re, os

task_start = int(open('/home/ga/.task_start_time').read().strip()) if os.path.exists('/home/ga/.task_start_time') else 0

result = {
    "notebook_exists": False,
    "notebook_modified": False,
    "notebook_analysis": {},
    "csv_exists": False,
    "csv_rows": 0,
    "csv_columns": "",
    "csv_created": False,
    "plot_exists": False,
    "plot_size_kb": 0,
    "plot_created": False,
    "task_start_time": task_start
}

# Analyze Jupyter Notebook
nb_path = "/home/ga/urbansim_projects/notebooks/affordability_analysis.ipynb"
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
            lines = [l for l in src.split('\n') if not l.strip().startswith('#')]
            all_code += '\n'.join(lines) + '\n'
            
        result["notebook_analysis"] = {
            "num_code_cells": len(code_cells),
            "num_executed_cells": sum(1 for c in code_cells if c.get('execution_count') is not None),
            "has_code": len(all_code.strip()) > 50,
            "has_pandas": bool(re.search(r'import pandas|from pandas', all_code)),
            "has_read_hdf": bool(re.search(r'read_hdf|HDFStore', all_code)),
            "has_groupby": bool(re.search(r'groupby', all_code)),
            "has_merge": bool(re.search(r'merge|join', all_code)),
            "has_median": bool(re.search(r'median', all_code)),
            "has_plot": bool(re.search(r'plot|bar|plt\.', all_code)),
            "has_to_csv": bool(re.search(r'to_csv', all_code)),
            "has_savefig": bool(re.search(r'savefig', all_code))
        }
    except Exception as e:
        result["notebook_analysis"] = {"error": str(e)}

# Analyze CSV File
csv_path = "/home/ga/urbansim_projects/output/affordability_by_zone.csv"
if os.path.exists(csv_path):
    result["csv_exists"] = True
    result["csv_created"] = os.path.getmtime(csv_path) > task_start
    try:
        with open(csv_path, 'r', encoding='utf-8') as f:
            lines = f.readlines()
        result["csv_rows"] = len(lines)
        if lines:
            result["csv_columns"] = lines[0].strip().lower().replace('"', '')
    except Exception:
        pass

# Analyze Plot PNG
plot_path = "/home/ga/urbansim_projects/output/affordability_chart.png"
if os.path.exists(plot_path):
    result["plot_exists"] = True
    result["plot_size_kb"] = os.path.getsize(plot_path) / 1024
    result["plot_created"] = os.path.getmtime(plot_path) > task_start

# Safely write temporary JSON
with open('/tmp/_task_result_tmp.json', 'w') as f:
    json.dump(result, f, indent=2, default=str)
PYEOF

# Move payload to final export location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/_task_result_tmp.json /tmp/task_result.json 2>/dev/null || sudo cp /tmp/_task_result_tmp.json /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/_task_result_tmp.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="