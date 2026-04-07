#!/bin/bash
echo "=== Exporting water demand forecasting result ==="

source /workspace/scripts/task_utils.sh
activate_venv

take_screenshot /tmp/task_end.png
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

# Run python script to extract metrics and compute ground truth
python << 'PYEOF'
import json, re, os
import pandas as pd
import numpy as np

task_start = int(open('/home/ga/.task_start_time').read().strip()) if os.path.exists('/home/ga/.task_start_time') else 0

result = {
    "files_exist": {},
    "file_created": {},
    "agent_json": {},
    "agent_top15_total": [],
    "agent_top15_pc": [],
    "ground_truth": {},
    "ground_truth_error": None,
    "notebook_analysis": {},
    "task_start_time": task_start
}

# 1. Analyze Notebook
nb_path = "/home/ga/urbansim_projects/notebooks/water_demand.ipynb"
if os.path.exists(nb_path):
    result["files_exist"]["notebook"] = True
    result["file_created"]["notebook"] = os.path.getmtime(nb_path) > task_start
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
            "has_merge": bool(re.search(r'merge|join', all_code)),
            "has_groupby": bool(re.search(r'groupby', all_code)),
            "has_math": bool(re.search(r'\*|55\.0|0\.15', all_code)),
            "has_to_csv": bool(re.search(r'to_csv', all_code)),
            "has_to_json": bool(re.search(r'json|dump', all_code)),
            "has_scatter": bool(re.search(r'scatter', all_code))
        }
    except Exception as e:
        result["notebook_analysis"] = {"error": str(e)}

# 2. Extract Agent's outputs
json_path = "/home/ga/urbansim_projects/output/water_summary.json"
if os.path.exists(json_path):
    result["files_exist"]["json"] = True
    result["file_created"]["json"] = os.path.getmtime(json_path) > task_start
    try:
        with open(json_path, 'r') as f:
            result["agent_json"] = json.load(f)
    except Exception:
        pass

def extract_zones(csv_path):
    try:
        df = pd.read_csv(csv_path)
        col = next((c for c in df.columns if 'zone' in c.lower()), df.columns[0])
        return df[col].astype(int).tolist()[:15]
    except Exception:
        return []

csv_top_total = "/home/ga/urbansim_projects/output/top15_total_demand.csv"
if os.path.exists(csv_top_total):
    result["files_exist"]["csv_top_total"] = True
    result["file_created"]["csv_top_total"] = os.path.getmtime(csv_top_total) > task_start
    result["agent_top15_total"] = extract_zones(csv_top_total)

csv_top_pc = "/home/ga/urbansim_projects/output/top15_per_capita_demand.csv"
if os.path.exists(csv_top_pc):
    result["files_exist"]["csv_top_pc"] = True
    result["file_created"]["csv_top_pc"] = os.path.getmtime(csv_top_pc) > task_start
    result["agent_top15_pc"] = extract_zones(csv_top_pc)
    
plot_path = "/home/ga/urbansim_projects/output/water_demand_scatter.png"
if os.path.exists(plot_path):
    result["files_exist"]["plot"] = True
    result["file_created"]["plot"] = os.path.getmtime(plot_path) > task_start
    result["plot_size_kb"] = os.path.getsize(plot_path) / 1024

# 3. Compute Ground Truth Internally
h5_path = '/home/ga/urbansim_projects/data/sanfran_public.h5'
try:
    hh = pd.read_hdf(h5_path, 'households')
    bld = pd.read_hdf(h5_path, 'buildings')
    pcl = pd.read_hdf(h5_path, 'parcels')

    bld_df = bld.copy()
    bld_df['building_id'] = bld_df.index
    pcl_df = pcl.copy()
    pcl_df['parcel_id'] = pcl_df.index

    # Merge buildings with parcels to get zone_id
    bld_pcl = pd.merge(bld_df, pcl_df[['zone_id']], left_on='parcel_id', right_index=True, how='left')

    # Merge households with buildings to get zone_id
    hh_df = hh.copy()
    hh_bld = pd.merge(hh_df, bld_pcl[['zone_id']], left_on='building_id', right_index=True, how='left')

    # Aggregations
    hh_bld['persons'] = hh_bld['persons'].fillna(0)
    zone_persons = hh_bld.groupby('zone_id')['persons'].sum()

    bld_pcl['non_residential_sqft'] = bld_pcl['non_residential_sqft'].fillna(0)
    zone_sqft = bld_pcl.groupby('zone_id')['non_residential_sqft'].sum()

    df = pd.DataFrame({'total_persons': zone_persons, 'total_non_res_sqft': zone_sqft}).fillna(0)

    df['residential_demand_gpd'] = df['total_persons'] * 55.0
    df['commercial_demand_gpd'] = df['total_non_res_sqft'] * 0.15
    df['total_demand_gpd'] = df['residential_demand_gpd'] + df['commercial_demand_gpd']

    df['gross_per_capita_gpd'] = np.where(df['total_persons'] > 0, df['total_demand_gpd'] / df['total_persons'], 0)

    result['ground_truth'] = {
        "citywide_total_demand_gpd": float(df['total_demand_gpd'].sum()),
        "citywide_residential_demand_gpd": float(df['residential_demand_gpd'].sum()),
        "citywide_commercial_demand_gpd": float(df['commercial_demand_gpd'].sum()),
        "zone_with_highest_demand": int(df['total_demand_gpd'].idxmax()),
        "zone_with_highest_per_capita": int(df[df['total_persons'] >= 100]['gross_per_capita_gpd'].idxmax()),
        "top15_total_demand_zones": df.nlargest(15, 'total_demand_gpd').index.astype(int).tolist(),
        "top15_per_capita_zones": df[df['total_persons'] >= 100].nlargest(15, 'gross_per_capita_gpd').index.astype(int).tolist()
    }
except Exception as e:
    result['ground_truth_error'] = str(e)

with open('/tmp/_task_result_tmp.json', 'w') as f:
    json.dump(result, f, indent=2, default=str)
PYEOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/_task_result_tmp.json /tmp/task_result.json 2>/dev/null || sudo cp /tmp/_task_result_tmp.json /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/_task_result_tmp.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="