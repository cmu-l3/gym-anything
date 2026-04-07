#!/bin/bash
echo "=== Exporting new_housing_price_premium_analysis result ==="

source /workspace/scripts/task_utils.sh
activate_venv

take_screenshot /tmp/task_end.png
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

# Run an analysis script to verify file states, parse the notebook, and calculate Ground Truth
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
    "csv_created": False,
    "scatter_exists": False,
    "scatter_size_kb": 0,
    "scatter_created": False,
    "bar_exists": False,
    "bar_size_kb": 0,
    "bar_created": False,
    "gt_valid_zones": 0,
    "gt_mean_premium": 0.0,
    "gt_error": None,
    "task_start_time": task_start
}

# 1. Evaluate Notebook
nb_path = "/home/ga/urbansim_projects/notebooks/new_construction_premium.ipynb"
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
            "has_filter": bool(re.search(r'>\s*0', all_code)),
            "has_vintage": bool(re.search(r'2000', all_code)),
            "has_group_merge": bool(re.search(r'groupby|pivot|unstack|merge|join', all_code)),
            "has_savefig": bool(re.search(r'savefig', all_code))
        }
    except Exception as e:
        result["notebook_analysis"] = {"error": str(e)}

# 2. Check Outputs Timestamps
csv_path = "/home/ga/urbansim_projects/output/zone_premium_analysis.csv"
if os.path.exists(csv_path):
    result["csv_exists"] = True
    result["csv_created"] = os.path.getmtime(csv_path) > task_start

scatter_path = "/home/ga/urbansim_projects/output/premium_scatter.png"
if os.path.exists(scatter_path):
    result["scatter_exists"] = True
    result["scatter_size_kb"] = os.path.getsize(scatter_path) / 1024
    result["scatter_created"] = os.path.getmtime(scatter_path) > task_start

bar_path = "/home/ga/urbansim_projects/output/top_premium_zones.png"
if os.path.exists(bar_path):
    result["bar_exists"] = True
    result["bar_size_kb"] = os.path.getsize(bar_path) / 1024
    result["bar_created"] = os.path.getmtime(bar_path) > task_start

# 3. Calculate Ground Truth dynamically
try:
    df = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'buildings')
    # Filter constraints
    valid = df[(df['residential_units'] > 0) & 
               (df['residential_sales_price'] > 0) & 
               (df['year_built'].notna())].copy()
               
    valid['price_per_unit'] = valid['residential_sales_price'] / valid['residential_units']
    
    new_bld = valid[valid['year_built'] >= 2000]
    ext_bld = valid[valid['year_built'] < 2000]
    
    new_agg = new_bld.groupby('zone_id').agg(new_units=('residential_units', 'sum'), median_price_new=('price_per_unit', 'median'))
    ext_agg = ext_bld.groupby('zone_id').agg(existing_units=('residential_units', 'sum'), median_price_existing=('price_per_unit', 'median'))
    
    merged = ext_agg.join(new_agg, how='inner')
    filtered = merged[(merged['new_units'] >= 20) & (merged['existing_units'] >= 50)].copy()
    filtered['price_premium_ratio'] = filtered['median_price_new'] / filtered['median_price_existing']
    
    result['gt_valid_zones'] = len(filtered)
    result['gt_mean_premium'] = float(filtered['price_premium_ratio'].mean()) if len(filtered) > 0 else 0.0
except Exception as e:
    result['gt_error'] = str(e)

result["timestamp"] = datetime.now().isoformat()

with open('/tmp/_task_result_tmp.json', 'w') as f:
    json.dump(result, f, indent=2, default=str)
PYEOF

# Move result to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/_task_result_tmp.json /tmp/task_result.json 2>/dev/null || sudo cp /tmp/_task_result_tmp.json /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/_task_result_tmp.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="