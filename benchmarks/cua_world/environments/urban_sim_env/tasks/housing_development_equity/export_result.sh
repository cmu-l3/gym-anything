#!/bin/bash
echo "=== Exporting housing_development_equity result ==="

source /workspace/scripts/task_utils.sh
activate_venv

# Take final screenshot
take_screenshot /tmp/task_final.png
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

# Run Python script to analyze notebook and check file metadata
python << 'PYEOF'
import json, re, os

task_start = int(open('/home/ga/.task_start_time').read().strip()) if os.path.exists('/home/ga/.task_start_time') else 0

result = {
    "notebook_exists": False,
    "notebook_modified": False,
    "notebook_analysis": {},
    "zone_csv_exists": False,
    "zone_csv_created": False,
    "quartile_csv_exists": False,
    "quartile_csv_created": False,
    "plot_exists": False,
    "plot_size_kb": 0,
    "plot_created": False,
    "task_start_time": task_start
}

nb_path = "/home/ga/urbansim_projects/notebooks/development_equity.ipynb"
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
        
        # Deep analysis of the code
        clean_code = re.sub(r'"""[\s\S]*?"""|\'\'\'[\s\S]*?\'\'\'', '', all_code)
        clean_code = re.sub(r'"[^"\n]*"|\'[^\'\n]*\'', '', clean_code)
        
        result["notebook_analysis"] = {
            "num_code_cells": len(code_cells),
            "num_executed_cells": sum(1 for c in code_cells if c.get('execution_count') is not None),
            "has_pandas": bool(re.search(r'import pandas|from pandas', clean_code)),
            "has_read_hdf": bool(re.search(r'read_hdf|HDFStore', clean_code)),
            "has_qcut": bool(re.search(r'qcut', clean_code)),
            "has_merge": bool(re.search(r'\.merge\s*\(|\.join\s*\(', clean_code)),
            "has_groupby": bool(re.search(r'\.groupby\s*\(', clean_code)),
            "has_savefig": bool(re.search(r'savefig', clean_code)),
            "has_to_csv": bool(re.search(r'to_csv', clean_code))
        }
    except Exception as e:
        result["notebook_analysis"] = {"error": str(e)}

zone_csv_path = "/home/ga/urbansim_projects/output/zone_development_equity.csv"
if os.path.exists(zone_csv_path):
    result["zone_csv_exists"] = True
    result["zone_csv_created"] = os.path.getmtime(zone_csv_path) > task_start

quartile_csv_path = "/home/ga/urbansim_projects/output/quartile_absorption.csv"
if os.path.exists(quartile_csv_path):
    result["quartile_csv_exists"] = True
    result["quartile_csv_created"] = os.path.getmtime(quartile_csv_path) > task_start

plot_path = "/home/ga/urbansim_projects/output/recent_units_by_income.png"
if os.path.exists(plot_path):
    result["plot_exists"] = True
    result["plot_size_kb"] = os.path.getsize(plot_path) / 1024
    result["plot_created"] = os.path.getmtime(plot_path) > task_start

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