#!/bin/bash
echo "=== Exporting parking demand analysis result ==="

source /workspace/scripts/task_utils.sh
activate_venv

# Take final screenshot
take_screenshot /tmp/task_end.png

TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

# Use Python to accurately analyze the data logic
python << 'PYEOF'
import json, re, os
import pandas as pd
import numpy as np
from datetime import datetime

task_start = int(open('/home/ga/.task_start_time').read().strip()) if os.path.exists('/home/ga/.task_start_time') else 0

result = {
    "notebook_exists": False,
    "notebook_modified": False,
    "notebook_analysis": {},
    "csv_exists": False,
    "csv_rows": 0,
    "csv_columns": [],
    "csv_created": False,
    "is_sorted": False,
    "multiplier_math_max_error": 9999.0,
    "density_math_max_error": 9999.0,
    "agent_total_acres": 0.0,
    "agent_total_spaces": 0.0,
    "true_total_acres": 0.0,
    "json_exists": False,
    "json_keys": [],
    "json_res": 0,
    "json_non_res": 0,
    "json_total": 0,
    "plot_exists": False,
    "plot_size_kb": 0,
    "plot_created": False,
    "task_start_time": task_start
}

# 1. Analyze Ground Truth Acres (to catch double counting)
try:
    parcels = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'parcels')
    result['true_total_acres'] = float(parcels['parcel_acres'].sum())
except Exception as e:
    result['true_total_acres'] = 25000.0  # Safe fallback estimate for SF

# 2. Analyze Notebook
nb_path = "/home/ga/urbansim_projects/notebooks/parking_demand_analysis.ipynb"
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
            "has_hdf": bool(re.search(r'read_hdf|HDFStore', all_code)),
            "has_groupby": bool(re.search(r'groupby', all_code)),
            "has_merge": bool(re.search(r'merge|join', all_code)),
            "has_multipliers": bool(re.search(r'1\.2|2\.5', all_code)),
            "has_savefig": bool(re.search(r'savefig', all_code)),
            "has_to_csv": bool(re.search(r'to_csv', all_code)),
            "has_json_dump": bool(re.search(r'json\.dump', all_code))
        }
    except Exception as e:
        result["notebook_analysis"] = {"error": str(e)}

# 3. Analyze CSV
csv_path = "/home/ga/urbansim_projects/output/zone_parking_demand.csv"
if os.path.exists(csv_path):
    result["csv_exists"] = True
    result["csv_created"] = os.path.getmtime(csv_path) > task_start
    try:
        df = pd.read_csv(csv_path)
        # Normalize column names for flexible matching
        df.columns = [c.strip().lower() for c in df.columns]
        result["csv_columns"] = list(df.columns)
        result["csv_rows"] = len(df)
        
        # Verify columns exist before math
        if all(c in df.columns for c in ['residential_spaces', 'non_residential_spaces', 'total_spaces', 'total_parcel_acres', 'spaces_per_acre']):
            # Verify Sorting
            result["is_sorted"] = bool(df['total_spaces'].is_monotonic_decreasing)
            
            # Verify Addition Logic
            res_sum = df['residential_spaces'] + df['non_residential_spaces']
            diff = np.abs(df['total_spaces'] - res_sum)
            result["multiplier_math_max_error"] = float(diff.max())
            
            # Verify Density Logic (ignore zeros/NaNs to prevent infinite/nan math errors)
            mask = df['total_parcel_acres'] > 0
            if mask.any():
                expected_density = df.loc[mask, 'total_spaces'] / df.loc[mask, 'total_parcel_acres']
                den_diff = np.abs(df.loc[mask, 'spaces_per_acre'] - expected_density)
                result["density_math_max_error"] = float(den_diff.max())
            else:
                result["density_math_max_error"] = 9999.0
            
            # Record sums for double-counting check
            result["agent_total_acres"] = float(df['total_parcel_acres'].sum())
            result["agent_total_spaces"] = float(df['total_spaces'].sum())
    except Exception as e:
        result["csv_error"] = str(e)

# 4. Analyze Plot
plot_path = "/home/ga/urbansim_projects/output/top_parking_zones.png"
if os.path.exists(plot_path):
    result["plot_exists"] = True
    result["plot_size_kb"] = os.path.getsize(plot_path) / 1024
    result["plot_created"] = os.path.getmtime(plot_path) > task_start

# 5. Analyze JSON
json_path = "/home/ga/urbansim_projects/output/citywide_parking_summary.json"
if os.path.exists(json_path):
    result["json_exists"] = True
    try:
        with open(json_path, 'r') as f:
            j = json.load(f)
        result["json_keys"] = list(j.keys())
        result["json_res"] = j.get("citywide_residential_spaces", 0)
        result["json_non_res"] = j.get("citywide_non_residential_spaces", 0)
        result["json_total"] = j.get("citywide_total_spaces", 0)
    except Exception as e:
        pass

result["timestamp"] = datetime.now().isoformat()

with open('/tmp/_task_result_tmp.json', 'w') as f:
    json.dump(result, f, indent=2, default=str)

PYEOF

# Move result to safe accessible location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/_task_result_tmp.json /tmp/task_result.json 2>/dev/null || sudo cp /tmp/_task_result_tmp.json /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/_task_result_tmp.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="