#!/bin/bash
echo "=== Exporting EJ analysis result ==="

source /workspace/scripts/task_utils.sh
activate_venv

# Take final screenshot
take_screenshot /tmp/task_end.png
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

# Use Python to thoroughly inspect the agent's work AND compute Ground Truth
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
    "csv_exists": False,
    "csv_rows": 0,
    "csv_columns": "",
    "csv_created": False,
    "json_exists": False,
    "json_data": {},
    "json_created": False,
    "plot_exists": False,
    "plot_size_kb": 0,
    "plot_created": False,
    "task_start_time": task_start,
    "ground_truth": {}
}

# 1. Compute Ground Truth explicitly from the VM's dataset
try:
    import pandas as pd
    hh = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'households')
    bld = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'buildings')
    pcl = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'parcels')

    # Join households & buildings to zones
    bld_pcl = bld.join(pcl[['zone_id']], on='parcel_id')
    hh_zone = hh.join(bld_pcl[['zone_id']], on='building_id')

    # Aggregations
    hh_agg = hh_zone.groupby('zone_id').agg(
        total_households=('income', 'count'),
        median_income=('income', 'median')
    )

    ind_bld = bld_pcl[bld_pcl['building_type_id'] == 3]
    ind_agg = ind_bld.groupby('zone_id').agg(
        total_industrial_sqft=('non_residential_sqft', 'sum')
    )

    # Combine & fillna
    gt = hh_agg.join(ind_agg).fillna({'total_industrial_sqft': 0})
    
    # Filter >= 50 households
    gt = gt[gt['total_households'] >= 50].copy()
    gt['industrial_sqft_per_hh'] = gt['total_industrial_sqft'] / gt['total_households']

    result["ground_truth"]["total_zones_analyzed"] = int(len(gt))
    result["ground_truth"]["highest_exposure_zone_id"] = int(gt['industrial_sqft_per_hh'].idxmax())
    result["ground_truth"]["success"] = True
except Exception as e:
    result["ground_truth"]["success"] = False
    result["ground_truth"]["error"] = str(e)


# 2. Analyze Agent's Notebook
nb_path = "/home/ga/urbansim_projects/notebooks/industrial_exposure_ej.ipynb"
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
            # Remove comments
            lines = [l for l in src.split('\n') if not l.strip().startswith('#')]
            all_code += '\n'.join(lines) + '\n'
            
        result["notebook_analysis"] = {
            "num_code_cells": len(code_cells),
            "num_executed_cells": sum(1 for c in code_cells if c.get('execution_count') is not None),
            "has_code": len(all_code.strip()) > 50,
            "has_pandas": bool(re.search(r'import pandas|from pandas', all_code)),
            "has_read_hdf": bool(re.search(r'read_hdf|HDFStore', all_code)),
            "has_merge": bool(re.search(r'merge|join', all_code)),
            "has_groupby": bool(re.search(r'groupby', all_code)),
            "has_building_type_filter": bool(re.search(r'building_type_id\s*==\s*3', all_code)),
            "has_threshold_filter": bool(re.search(r'>=\s*50|>49', all_code)),
            "has_qcut": bool(re.search(r'qcut|quantile', all_code)),
            "has_to_csv": bool(re.search(r'to_csv', all_code)),
            "has_json_dump": bool(re.search(r'json\.dump', all_code)),
            "has_savefig": bool(re.search(r'savefig', all_code))
        }
    except Exception as e:
        result["notebook_analysis"] = {"error": str(e)}

# 3. Analyze Agent's CSV
csv_path = "/home/ga/urbansim_projects/output/zone_industrial_exposure.csv"
if os.path.exists(csv_path):
    result["csv_exists"] = True
    result["csv_created"] = os.path.getmtime(csv_path) > task_start
    try:
        with open(csv_path, 'r') as f:
            lines = f.readlines()
        result["csv_rows"] = len(lines)
        if lines:
            cols = lines[0].strip().lower().replace('"', '')
            result["csv_columns"] = cols
    except Exception:
        pass

# 4. Analyze Agent's JSON
json_path = "/home/ga/urbansim_projects/output/ej_summary.json"
if os.path.exists(json_path):
    result["json_exists"] = True
    result["json_created"] = os.path.getmtime(json_path) > task_start
    try:
        with open(json_path, 'r') as f:
            agent_json = json.load(f)
        result["json_data"] = agent_json
    except Exception as e:
        result["json_data"] = {"error": "Invalid JSON format"}

# 5. Analyze Agent's Plot
plot_path = "/home/ga/urbansim_projects/output/income_vs_exposure.png"
if os.path.exists(plot_path):
    result["plot_exists"] = True
    result["plot_size_kb"] = os.path.getsize(plot_path) / 1024
    result["plot_created"] = os.path.getmtime(plot_path) > task_start

result["timestamp"] = datetime.datetime.now().isoformat()

# Save final JSON structure safely
with open('/tmp/_task_result_tmp.json', 'w') as f:
    json.dump(result, f, indent=2, default=str)
PYEOF

# Move JSON out
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/_task_result_tmp.json /tmp/task_result.json 2>/dev/null || sudo cp /tmp/_task_result_tmp.json /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/_task_result_tmp.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="