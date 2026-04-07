#!/bin/bash
echo "=== Exporting single_parent_spatial_equity result ==="

source /workspace/scripts/task_utils.sh
activate_venv

take_screenshot /tmp/task_end.png
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

python << 'PYEOF'
import json, re, os
import pandas as pd
import numpy as np

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
    "json_created": False,
    "agent_json": {},
    "plot_exists": False,
    "plot_size_kb": 0,
    "plot_created": False,
    "ground_truth": {},
    "task_start_time": task_start
}

# 1. Compute Ground Truth silently
try:
    store = pd.HDFStore('/home/ga/urbansim_projects/data/sanfran_public.h5', mode='r')
    hh = store['households']
    jobs = store['jobs']
    bld = store['buildings']
    parcels = store['parcels']
    store.close()

    hh = hh.dropna(subset=['persons', 'children'])
    hh['is_single_parent'] = (hh['children'] > 0) & ((hh['persons'] - hh['children']) == 1)

    bld_parcel = bld[['parcel_id']]
    parcel_zone = parcels[['zone_id', 'parcel_acres']]

    hh = hh.merge(bld_parcel, left_on='building_id', right_index=True)
    hh = hh.merge(parcel_zone, left_on='parcel_id', right_index=True)

    jobs = jobs.merge(bld_parcel, left_on='building_id', right_index=True)
    jobs = jobs.merge(parcel_zone, left_on='parcel_id', right_index=True)

    zone_hh = hh.groupby('zone_id').agg(
        total_households=('persons', 'count'),
        single_parent_households=('is_single_parent', 'sum'),
        median_income=('income', 'median')
    )
    zone_jobs = jobs.groupby('zone_id').size().rename('total_jobs')
    zone_acres = parcel_zone.groupby('zone_id')['parcel_acres'].sum()

    zone_stats = pd.concat([zone_hh, zone_jobs, zone_acres], axis=1).fillna({'total_jobs': 0})
    zone_stats['pct_single_parent'] = (zone_stats['single_parent_households'] / zone_stats['total_households']) * 100
    zone_stats['employment_density'] = zone_stats['total_jobs'] / zone_stats['parcel_acres']

    valid_zones = zone_stats[(zone_stats['total_households'] >= 50) & (zone_stats['parcel_acres'] > 0)]

    corr_income = valid_zones['pct_single_parent'].corr(valid_zones['median_income'])
    corr_density = valid_zones['pct_single_parent'].corr(valid_zones['employment_density'])

    citywide_sp = int(hh['is_single_parent'].sum())
    citywide_pct = float((citywide_sp / len(hh)) * 100)
    total_valid_zones = len(valid_zones)

    result["ground_truth"] = {
        "total_zones_analyzed": total_valid_zones,
        "citywide_single_parent_households": citywide_sp,
        "citywide_pct_single_parent": citywide_pct,
        "correlation_with_income": round(float(corr_income), 3),
        "correlation_with_employment_density": round(float(corr_density), 3)
    }
except Exception as e:
    result["ground_truth"] = {"error": str(e)}

# 2. Check Agent outputs
nb_path = "/home/ga/urbansim_projects/notebooks/single_parent_equity.ipynb"
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
            "has_dropna": bool(re.search(r'dropna', all_code)),
            "has_single_parent_logic": bool(re.search(r'children|persons', all_code)) and bool(re.search(r'==\s*1', all_code)),
            "has_merge": bool(re.search(r'merge|join', all_code)),
            "has_groupby": bool(re.search(r'groupby', all_code)),
            "has_corr": bool(re.search(r'corr|pearsonr', all_code)),
            "has_plot": bool(re.search(r'scatter|plot|bubble|sns\.', all_code)),
            "has_json_dump": bool(re.search(r'json\.dump|to_json', all_code))
        }
    except Exception as e:
        result["notebook_analysis"] = {"error": str(e)}

csv_path = "/home/ga/urbansim_projects/output/zone_single_parent_metrics.csv"
if os.path.exists(csv_path):
    result["csv_exists"] = True
    result["csv_created"] = os.path.getmtime(csv_path) > task_start
    try:
        with open(csv_path, 'r') as f:
            lines = f.readlines()
        result["csv_rows"] = len(lines)
        if lines:
            result["csv_columns"] = lines[0].strip().lower().replace('"', '')
    except Exception:
        pass

json_path = "/home/ga/urbansim_projects/output/equity_summary.json"
if os.path.exists(json_path):
    result["json_exists"] = True
    result["json_created"] = os.path.getmtime(json_path) > task_start
    try:
        with open(json_path, 'r') as f:
            result["agent_json"] = json.load(f)
    except Exception:
        pass

plot_path = "/home/ga/urbansim_projects/output/single_parent_bubble_chart.png"
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