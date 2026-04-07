#!/bin/bash
echo "=== Exporting vertical_mixed_use_analysis result ==="

source /workspace/scripts/task_utils.sh
activate_venv

# Take final screenshot
take_screenshot /tmp/task_end.png

# Run Python script to independently calculate ground truth and evaluate agent outputs
python << 'PYEOF'
import json, re, os
import pandas as pd
import numpy as np
from datetime import datetime

task_start_path = '/home/ga/.task_start_time'
task_start = int(open(task_start_path).read().strip()) if os.path.exists(task_start_path) else 0

result = {
    "notebook_exists": False, "notebook_modified": False, "notebook_analysis": {},
    "csv_exists": False, "csv_rows": 0, "csv_columns": [], "csv_created": False,
    "json_exists": False, "json_created": False, "agent_json": {},
    "plot_exists": False, "plot_size_kb": 0, "plot_created": False,
    "task_start_time": task_start,
    "ground_truth": {}, "ground_truth_error": None,
    "csv_sample_match": False, "csv_match_details": {},
    "timestamp": datetime.now().isoformat()
}

# 1. Evaluate Notebook
nb_path = "/home/ga/urbansim_projects/notebooks/mixed_use_analysis.ipynb"
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
            if isinstance(src, list): src = ''.join(src)
            lines = [l for l in src.split('\n') if not l.strip().startswith('#')]
            all_code += '\n'.join(lines) + '\n'
            
        result["notebook_analysis"] = {
            "num_code_cells": len(code_cells),
            "num_executed_cells": sum(1 for c in code_cells if c.get('execution_count') is not None),
            "has_code": len(all_code.strip()) > 50,
            "has_merge_join": bool(re.search(r'merge|join', all_code)),
            "has_groupby": bool(re.search(r'groupby', all_code)),
            "has_fillna_or_similar": bool(re.search(r'fillna|notnull|\.add\(', all_code))
        }
    except Exception as e:
        result["notebook_analysis"] = {"error": str(e)}

# 2. Calculate Ground Truth and compare CSV
try:
    store = pd.HDFStore('/home/ga/urbansim_projects/data/sanfran_public.h5', mode='r')
    b = store['buildings']
    p = store['parcels']
    h = store['households']
    j = store['jobs']
    store.close()

    # Aggregate households and jobs
    hh_counts = h.groupby('building_id').size().rename('hh_count')
    job_counts = j.groupby('building_id').size().rename('job_count')

    # Join to buildings
    b_full = b.join(hh_counts, how='left').join(job_counts, how='left')
    b_full['hh_count'] = b_full['hh_count'].fillna(0)
    b_full['job_count'] = b_full['job_count'].fillna(0)
    b_full['is_vmu'] = (b_full['hh_count'] > 0) & (b_full['job_count'] > 0)

    # Join to parcels for zone_id
    if 'zone_id' not in b_full.columns:
        b_full = b_full.join(p['zone_id'], on='parcel_id')

    # Prep columns to conditionally aggregate households and jobs
    b_full['vmu_hh'] = np.where(b_full['is_vmu'], b_full['hh_count'], 0)
    b_full['vmu_jb'] = np.where(b_full['is_vmu'], b_full['job_count'], 0)

    # Aggregate by zone
    zone_agg = b_full.groupby('zone_id').agg(
        total_buildings=('is_vmu', 'count'),
        vmu_buildings=('is_vmu', 'sum'),
        vmu_households=('vmu_hh', 'sum'),
        vmu_jobs=('vmu_jb', 'sum')
    )

    zone_agg['pct_vmu'] = zone_agg['vmu_buildings'] / zone_agg['total_buildings']
    zone_filtered = zone_agg[zone_agg['total_buildings'] >= 10]

    # Metrics
    gt_total_zones = int(len(zone_filtered))
    gt_vmu_bldgs = int(zone_filtered['vmu_buildings'].sum())
    gt_total_bldgs = int(zone_filtered['total_buildings'].sum())
    gt_pct_vmu = float(gt_vmu_bldgs / gt_total_bldgs) if gt_total_bldgs > 0 else 0.0
    gt_top_zone = int(zone_filtered['pct_vmu'].idxmax()) if gt_total_zones > 0 else -1

    result['ground_truth'] = {
        "total_analyzed_zones": gt_total_zones,
        "citywide_vmu_buildings": gt_vmu_bldgs,
        "citywide_pct_vmu": gt_pct_vmu,
        "top_vmu_zone_id": gt_top_zone
    }

    # Analyze CSV
    csv_path = "/home/ga/urbansim_projects/output/vmu_by_zone.csv"
    if os.path.exists(csv_path):
        result["csv_exists"] = True
        result["csv_created"] = os.path.getmtime(csv_path) > task_start
        try:
            agent_csv = pd.read_csv(csv_path)
            result["csv_rows"] = len(agent_csv)
            # Ensure safe col serialization
            result["csv_columns"] = [str(c).lower().strip() for c in agent_csv.columns]
            
            # Identify standard columns if they exist
            zone_col = next((c for c in agent_csv.columns if 'zone_id' in str(c).lower() or 'zone' in str(c).lower()), None)
            vmu_bldg_col = next((c for c in agent_csv.columns if 'vmu_buildings' in str(c).lower()), None)
            
            if zone_col and vmu_bldg_col:
                agent_csv.set_index(zone_col, inplace=True)
                sample_zones = zone_filtered.head(10)
                matches = 0
                for idx, row in sample_zones.iterrows():
                    if idx in agent_csv.index:
                        agent_val = agent_csv.loc[idx, vmu_bldg_col]
                        if isinstance(agent_val, pd.Series): 
                            agent_val = agent_val.iloc[0]
                        if abs(agent_val - row['vmu_buildings']) < 1e-5:
                            matches += 1
                result["csv_sample_match"] = matches >= 8
                result["csv_match_details"] = {"checked": len(sample_zones), "matched": matches}
        except Exception as e:
            result["csv_match_details"] = {"error": str(e)}

except Exception as e:
    result["ground_truth_error"] = str(e)

# 3. Analyze JSON Summary
json_path = "/home/ga/urbansim_projects/output/vmu_summary.json"
if os.path.exists(json_path):
    result["json_exists"] = True
    result["json_created"] = os.path.getmtime(json_path) > task_start
    try:
        with open(json_path, 'r') as f:
            result["agent_json"] = json.load(f)
    except Exception:
        pass

# 4. Analyze Plot
plot_path = "/home/ga/urbansim_projects/output/vmu_scatter.png"
if os.path.exists(plot_path):
    result["plot_exists"] = True
    result["plot_size_kb"] = os.path.getsize(plot_path) / 1024
    result["plot_created"] = os.path.getmtime(plot_path) > task_start

# Write final result out securely
with open('/tmp/_task_result_tmp.json', 'w') as f:
    json.dump(result, f, indent=2, default=str)
PYEOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/_task_result_tmp.json /tmp/task_result.json 2>/dev/null || sudo cp /tmp/_task_result_tmp.json /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/_task_result_tmp.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="