#!/bin/bash
echo "=== Exporting employment decentralization result ==="

source /workspace/scripts/task_utils.sh
activate_venv

# Final state screenshot
take_screenshot /tmp/task_end.png

# Collect files and run extraction logic
python << 'PYEOF'
import json
import os
import re

task_start = int(open('/home/ga/.task_start_time').read().strip()) if os.path.exists('/home/ga/.task_start_time') else 0

result = {
    "task_start_time": task_start,
    "notebook_exists": False,
    "notebook_modified": False,
    "notebook_analysis": {},
    "json_exists": False,
    "json_created": False,
    "agent_cbd_info": {},
    "csv_exists": False,
    "csv_created": False,
    "agent_sector_metrics": [],
    "plot_exists": False,
    "plot_created": False,
    "plot_size_kb": 0
}

# 1. Evaluate Notebook
nb_path = "/home/ga/urbansim_projects/notebooks/employment_decentralization.ipynb"
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
            "has_read_hdf": bool(re.search(r'read_hdf|HDFStore', all_code)),
            "has_merge_join": bool(re.search(r'merge|join', all_code)),
            "has_mean": bool(re.search(r'\.mean\(|np\.mean', all_code)),
            "has_distance": bool(re.search(r'sqrt|\*\* ?0\.5|pow\(.*0\.5\)', all_code)),
            "has_median": bool(re.search(r'median', all_code)),
            "has_quantile": bool(re.search(r'quantile|percentile', all_code)),
            "has_cdf": bool(re.search(r'cumsum|density=True|cumulative=True|ecdf|CDF', all_code, re.IGNORECASE))
        }
    except Exception as e:
        result["notebook_analysis"] = {"error": str(e)}

# 2. Evaluate JSON
json_path = "/home/ga/urbansim_projects/output/cbd_info.json"
if os.path.exists(json_path):
    result["json_exists"] = True
    result["json_created"] = os.path.getmtime(json_path) > task_start
    try:
        with open(json_path, 'r') as f:
            result["agent_cbd_info"] = json.load(f)
    except:
        pass

# 3. Evaluate CSV
csv_path = "/home/ga/urbansim_projects/output/sector_sprawl_metrics.csv"
if os.path.exists(csv_path):
    result["csv_exists"] = True
    result["csv_created"] = os.path.getmtime(csv_path) > task_start
    try:
        import pandas as pd
        df = pd.read_csv(csv_path)
        # normalize columns
        df.columns = [c.strip().lower() for c in df.columns]
        result["agent_sector_metrics"] = df.to_dict('records')
    except:
        pass

# 4. Evaluate Plot
plot_path = "/home/ga/urbansim_projects/output/job_sprawl_cdf.png"
if os.path.exists(plot_path):
    result["plot_exists"] = True
    result["plot_size_kb"] = os.path.getsize(plot_path) / 1024
    result["plot_created"] = os.path.getmtime(plot_path) > task_start

with open('/tmp/_task_result_tmp.json', 'w') as f:
    json.dump(result, f, indent=2, default=str)
PYEOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/_task_result_tmp.json /tmp/task_result.json 2>/dev/null || sudo cp /tmp/_task_result_tmp.json /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/_task_result_tmp.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="