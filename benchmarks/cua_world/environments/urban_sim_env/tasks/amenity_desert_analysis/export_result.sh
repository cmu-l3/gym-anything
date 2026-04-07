#!/bin/bash
echo "=== Exporting amenity_desert_analysis result ==="

source /workspace/scripts/task_utils.sh
activate_venv

# Capture final state screenshot
take_screenshot /tmp/task_end.png

# Generate Ground Truth and Parse Agent Outputs within the environment
python << 'PYEOF'
import json, re, os, sys
import pandas as pd
import numpy as np

# Convert np types for json serialization
def np_encoder(object):
    if isinstance(object, np.generic):
        return object.item()
    raise TypeError

task_start = int(open('/home/ga/.task_start_time').read().strip()) if os.path.exists('/home/ga/.task_start_time') else 0

result = {
    "notebook_exists": False,
    "notebook_modified": False,
    "notebook_analysis": {},
    "csv_exists": False,
    "csv_created": False,
    "csv_filtered_correctly": False,
    "csv_categories_valid": False,
    "json_exists": False,
    "json_created": False,
    "agent_json_data": {},
    "plot_exists": False,
    "plot_created": False,
    "plot_size_kb": 0,
    "gt_desert_population": 0,
    "gt_highest_amenity_zone_id": 0,
    "gt_total_deserts": 0,
    "task_start_time": task_start
}

# 1. Compute Ground Truth (Hidden from Agent)
try:
    hh = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'households')
    bld = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'buildings')
    parcels = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'parcels')

    bld_with_zone = bld.merge(parcels[['zone_id']], left_on='parcel_id', right_index=True, how='left')
    zone_non_res = bld_with_zone.groupby('zone_id')['non_residential_sqft'].sum().fillna(0)

    hh_with_zone = hh.merge(bld_with_zone[['zone_id']], left_on='building_id', right_index=True, how='left')
    zone_pop = hh_with_zone.groupby('zone_id')['persons'].sum().fillna(0)

    df = pd.DataFrame({'total_persons': zone_pop, 'total_non_residential_sqft': zone_non_res}).fillna(0)
    df = df[df['total_persons'] >= 500].copy()
    df['amenity_sqft_per_capita'] = df['total_non_residential_sqft'] / df['total_persons']

    deserts = df[df['amenity_sqft_per_capita'] < 50]
    result['gt_desert_population'] = float(deserts['total_persons'].sum())
    result['gt_highest_amenity_zone_id'] = int(df['amenity_sqft_per_capita'].idxmax())
    result['gt_total_deserts'] = int(len(deserts))
except Exception as e:
    result['gt_error'] = str(e)

# 2. Analyze Notebook
nb_path = "/home/ga/urbansim_projects/notebooks/amenity_analysis.ipynb"
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
            "has_pandas": bool(re.search(r'import pandas|from pandas', all_code)),
            "has_merge": bool(re.search(r'merge|join', all_code)),
            "has_groupby": bool(re.search(r'groupby', all_code)),
            "has_plot": bool(re.search(r'plot|pie|bar|matplotlib', all_code))
        }
    except Exception as e:
        result["notebook_analysis"] = {"error": str(e)}

# 3. Analyze CSV Output
csv_path = "/home/ga/urbansim_projects/output/amenity_deserts.csv"
if os.path.exists(csv_path):
    result["csv_exists"] = True
    result["csv_created"] = os.path.getmtime(csv_path) > task_start
    try:
        agent_df = pd.read_csv(csv_path)
        if 'total_persons' in agent_df.columns:
            result['csv_filtered_correctly'] = bool((agent_df['total_persons'] >= 500).all())
        if 'amenity_category' in agent_df.columns:
            valid_cats = {"Amenity Desert", "Moderate Access", "Amenity Rich"}
            unique_cats = set(agent_df['amenity_category'].dropna().unique())
            result['csv_categories_valid'] = unique_cats.issubset(valid_cats) and len(unique_cats) > 0
    except Exception as e:
        result['csv_error'] = str(e)

# 4. Analyze JSON Output
json_path = "/home/ga/urbansim_projects/output/amenity_summary.json"
if os.path.exists(json_path):
    result["json_exists"] = True
    result["json_created"] = os.path.getmtime(json_path) > task_start
    try:
        with open(json_path, 'r') as f:
            result["agent_json_data"] = json.load(f)
    except Exception as e:
        result['json_error'] = str(e)

# 5. Analyze Plot Output
plot_path = "/home/ga/urbansim_projects/output/amenity_category_distribution.png"
if os.path.exists(plot_path):
    result["plot_exists"] = True
    result["plot_created"] = os.path.getmtime(plot_path) > task_start
    result["plot_size_kb"] = os.path.getsize(plot_path) / 1024

result["timestamp"] = __import__('datetime').datetime.now().isoformat()

with open('/tmp/_task_result_tmp.json', 'w') as f:
    json.dump(result, f, indent=2, default=np_encoder)

PYEOF

# Move results to final location and set read permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/_task_result_tmp.json /tmp/task_result.json 2>/dev/null || sudo cp /tmp/_task_result_tmp.json /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/_task_result_tmp.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="