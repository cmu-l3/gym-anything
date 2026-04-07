#!/bin/bash
echo "=== Exporting net_commute_flow_analysis result ==="

source /workspace/scripts/task_utils.sh
activate_venv

take_screenshot /tmp/task_end.png
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

# Analyze notebook and plot using python
python << 'PYEOF'
import json, re, os

task_start = int(open('/home/ga/.task_start_time').read().strip()) if os.path.exists('/home/ga/.task_start_time') else 0

result = {
    "notebook_exists": False,
    "notebook_modified": False,
    "notebook_analysis": {},
    "plot_exists": False,
    "plot_size_kb": 0,
    "plot_created": False
}

nb_path = "/home/ga/urbansim_projects/notebooks/commute_flow_analysis.ipynb"
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
            "num_executed_cells": sum(1 for c in code_cells if c.get('execution_count') is not None)
        }
    except Exception as e:
        result["notebook_analysis"] = {"error": str(e)}

plot_path = "/home/ga/urbansim_projects/output/commute_scatter.png"
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

# Copy CSV and JSON out so verifier can read them securely with copy_from_env
cp /home/ga/urbansim_projects/output/zone_commute_flows.csv /tmp/zone_commute_flows.csv 2>/dev/null || true
chmod 666 /tmp/zone_commute_flows.csv 2>/dev/null || sudo chmod 666 /tmp/zone_commute_flows.csv 2>/dev/null || true

cp /home/ga/urbansim_projects/output/commute_summary.json /tmp/commute_summary.json 2>/dev/null || true
chmod 666 /tmp/commute_summary.json 2>/dev/null || sudo chmod 666 /tmp/commute_summary.json 2>/dev/null || true

echo "Result JSONs and CSV copied to /tmp/"
echo "=== Export complete ==="