#!/bin/bash
echo "=== Exporting gravity model zone interaction result ==="

source /workspace/scripts/task_utils.sh
activate_venv

take_screenshot /tmp/task_end.png
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

python << 'PYEOF'
import json, re, os, csv

task_start = int(open('/home/ga/.task_start_time').read().strip()) if os.path.exists('/home/ga/.task_start_time') else 0

result = {
    "notebook_exists": False,
    "notebook_modified": False,
    "notebook_analysis": {},
    "top20_csv_exists": False,
    "top20_csv_created": False,
    "top20_data": [],
    "potential_csv_exists": False,
    "potential_csv_created": False,
    "potential_data": [],
    "total_agent_population": 0,
    "total_agent_employment": 0,
    "plot_exists": False,
    "plot_size_kb": 0,
    "plot_created": False,
    "task_start_time": task_start,
    "ground_truth": {}
}

# Load ground truth
gt_path = "/tmp/gravity_ground_truth.json"
if os.path.exists(gt_path):
    try:
        with open(gt_path, 'r') as f:
            result["ground_truth"] = json.load(f)
    except Exception as e:
        result["ground_truth"] = {"error": str(e)}

# Analyze notebook
nb_path = "/home/ga/urbansim_projects/notebooks/gravity_model.ipynb"
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
        
        # Clean string literals
        clean_code = re.sub(r'"""[\s\S]*?"""|\'\'\'[\s\S]*?\'\'\'', '', all_code)
        clean_code = re.sub(r'"[^"\n]*"|\'[^\'\n]*\'', '', clean_code)
        
        has_errors = False
        for cell in code_cells:
            if cell.get('execution_count') is not None:
                for out in cell.get('outputs', []):
                    if out.get('output_type') == 'error':
                        has_errors = True
                        break

        result["notebook_analysis"] = {
            "num_code_cells": len(code_cells),
            "num_executed_cells": sum(1 for c in code_cells if c.get('execution_count') is not None),
            "has_errors": has_errors,
            "has_code": len(clean_code.strip()) > 50,
            "has_hdf_load": bool(re.search(r'read_hdf|HDFStore', clean_code)),
            "has_groupby": bool(re.search(r'\.groupby\s*\(', clean_code)),
            "has_distance": bool(re.search(r'cdist|euclidean|sqrt|distance|dist_matrix|dist\b', clean_code, re.IGNORECASE)),
            "has_gravity_formula": bool(re.search(r'interaction|gravity|\/.*\*\*\s*2|distance.*beta|decay', clean_code, re.IGNORECASE)),
            "has_to_csv": bool(re.search(r'\.to_csv\s*\(', clean_code)),
            "has_heatmap": bool(re.search(r'heatmap|imshow|pcolormesh|matshow', clean_code))
        }
    except Exception as e:
        result["notebook_analysis"] = {"error": str(e)}

top20_path = "/home/ga/urbansim_projects/output/zone_interactions_top20.csv"
if os.path.exists(top20_path):
    result["top20_csv_exists"] = True
    result["top20_csv_created"] = os.path.getmtime(top20_path) > task_start
    try:
        with open(top20_path, 'r') as f:
            reader = csv.DictReader(f)
            rows = list(reader)
            # Only keep top 5 for verification to keep JSON small
            result["top20_data"] = rows[:5] 
    except Exception:
        pass

pot_path = "/home/ga/urbansim_projects/output/zone_interaction_potential.csv"
if os.path.exists(pot_path):
    result["potential_csv_exists"] = True
    result["potential_csv_created"] = os.path.getmtime(pot_path) > task_start
    try:
        with open(pot_path, 'r') as f:
            reader = csv.DictReader(f)
            rows = list(reader)
            result["potential_data"] = rows[:10]
            
            # calculate totals over all rows
            tot_pop = 0
            tot_emp = 0
            for r in rows:
                try:
                    tot_pop += int(float(r.get('population', r.get('Population', 0))))
                    tot_emp += int(float(r.get('employment', r.get('Employment', 0))))
                except: pass
            result["total_agent_population"] = tot_pop
            result["total_agent_employment"] = tot_emp
    except Exception:
        pass

plot_path = "/home/ga/urbansim_projects/output/interaction_heatmap.png"
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
echo "=== Export complete ==="