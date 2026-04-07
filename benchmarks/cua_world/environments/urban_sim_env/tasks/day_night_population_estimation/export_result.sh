#!/bin/bash
echo "=== Exporting day_night_population_estimation result ==="

source /workspace/scripts/task_utils.sh
activate_venv

# Final screenshot
take_screenshot /tmp/task_end.png

TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

# Run an analysis script to extract metadata from outputs
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
    "task_start_time": task_start,
    "timestamp": __import__('datetime').datetime.now().isoformat()
}

# 1. Analyze Notebook
nb_path = "/home/ga/urbansim_projects/notebooks/day_night_population.ipynb"
if os.path.exists(nb_path):
    result["notebook_exists"] = True
    result["notebook_modified"] = os.path.getmtime(nb_path) > task_start
    try:
        with open(nb_path, 'r') as f:
            nb = json.load(f)
        code_cells = [c for c in nb.get('cells', []) if c.get('cell_type') == 'code']
        all_code = ''
        has_errors = False
        for c in code_cells:
            src = c.get('source', '')
            if isinstance(src, list): src = ''.join(src)
            lines = [l for l in src.split('\n') if not l.strip().startswith('#')]
            all_code += '\n'.join(lines) + '\n'
            
            # Check for cell errors
            if c.get('execution_count') is not None:
                for out in c.get('outputs', []):
                    if out.get('output_type') == 'error':
                        has_errors = True
        
        # Strip string literals to prevent keyword gaming
        clean_code = re.sub(r'"""[\s\S]*?"""|\'\'\'[\s\S]*?\'\'\'', '', all_code)
        clean_code = re.sub(r'"[^"\n]*"|\'[^\'\n]*\'', '', clean_code)

        result["notebook_analysis"] = {
            "num_code_cells": len(code_cells),
            "num_executed_cells": sum(1 for c in code_cells if c.get('execution_count') is not None),
            "has_errors": has_errors,
            "has_merge": bool(re.search(r'merge|join', clean_code)),
            "has_groupby": bool(re.search(r'groupby', clean_code)),
            "has_read_hdf": bool(re.search(r'read_hdf|HDFStore', clean_code)),
            "has_read_file": bool(re.search(r'read_file', clean_code)), # For geopandas
            "has_households": bool(re.search(r'households', clean_code)),
            "has_jobs": bool(re.search(r'jobs', clean_code)),
            "has_plot": bool(re.search(r'\.plot|matplotlib|figsize', clean_code))
        }
    except Exception as e:
        result["notebook_analysis"] = {"error": str(e)}

# 2. Analyze CSV
csv_path = "/home/ga/urbansim_projects/output/top_daytime_surge_zones.csv"
if os.path.exists(csv_path):
    result["csv_exists"] = True
    result["csv_created"] = os.path.getmtime(csv_path) > task_start
    try:
        with open(csv_path, 'r') as f:
            lines = f.readlines()
        result["csv_rows"] = max(0, len(lines) - 1) # Excluding header
        if lines:
            result["csv_columns"] = lines[0].strip().lower().replace('"', '').split(',')
    except Exception:
        pass

# 3. Analyze Plot
plot_path = "/home/ga/urbansim_projects/output/day_night_ratio_map.png"
if os.path.exists(plot_path):
    result["plot_exists"] = True
    result["plot_size_kb"] = os.path.getsize(plot_path) / 1024.0
    result["plot_created"] = os.path.getmtime(plot_path) > task_start

# Save results
with open('/tmp/_task_result_tmp.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/_task_result_tmp.json /tmp/task_result.json 2>/dev/null || sudo cp /tmp/_task_result_tmp.json /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/_task_result_tmp.json

echo "Result JSON saved to /tmp/task_result.json"
echo "=== Export complete ==="