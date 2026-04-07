#!/bin/bash
echo "=== Exporting employment sector concentration result ==="

source /workspace/scripts/task_utils.sh
activate_venv

# Take final screenshot for visual verification
take_screenshot /tmp/task_end.png

# Run Python script to evaluate agent's outputs against computed ground truth
python << 'PYEOF'
import json, re, os, datetime
import pandas as pd
import numpy as np

task_start = int(open('/home/ga/.task_start_time').read().strip()) if os.path.exists('/home/ga/.task_start_time') else 0

result = {
    "notebook_exists": False,
    "notebook_modified": False,
    "notebook_analysis": {},
    "lq_csv_exists": False,
    "spec_csv_exists": False,
    "lq_csv_created": False,
    "spec_csv_created": False,
    "lq_match_ratio": 0.0,
    "spec_match_ratio": 0.0,
    "lq_csv_rows": 0,
    "has_lq_columns": False,
    "has_spec_columns": False,
    "plot_exists": False,
    "plot_created": False,
    "plot_size_kb": 0,
    "task_start_time": task_start
}

# 1. Analyze Notebook Code
nb_path = "/home/ga/urbansim_projects/notebooks/employment_concentration.ipynb"
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
            
        clean_code = re.sub(r'"""[\s\S]*?"""|\'\'\'[\s\S]*?\'\'\'', '', all_code)
        clean_code = re.sub(r'"[^"\n]*"|\'[^\'\n]*\'', '', clean_code)
        
        result["notebook_analysis"] = {
            "num_executed_cells": sum(1 for c in code_cells if c.get('execution_count') is not None),
            "has_pandas": bool(re.search(r'import pandas', clean_code)),
            "has_read_hdf": bool(re.search(r'read_hdf|HDFStore', clean_code)),
            "has_joins": bool(re.search(r'\.merge|\.join', clean_code)),
            "has_groupby": bool(re.search(r'\.groupby', clean_code)),
            "has_division": bool(re.search(r'/', clean_code)),
            "has_heatmap": bool(re.search(r'heatmap|imshow|pcolormesh', clean_code, re.IGNORECASE)),
            "has_to_csv": bool(re.search(r'\.to_csv', clean_code)),
            "has_savefig": bool(re.search(r'\.savefig', clean_code))
        }
    except Exception as e:
        result["notebook_analysis"] = {"error": str(e)}

# 2. Compute Ground Truth LQs
gt_lq_dict = {}
gt_top_spec = {}
try:
    jobs = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'jobs')
    bld = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'buildings')
    parcels = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'parcels')

    # Join jobs -> buildings -> parcels to get zone_id
    df = jobs[['building_id', 'sector_id']].copy()
    
    # building_id is index of buildings table
    if 'parcel_id' in bld.columns:
        df = df.join(bld[['parcel_id']], on='building_id', how='inner')
    else:
        # Fallback if building_id is a column
        df = df.merge(bld[['building_id', 'parcel_id']], on='building_id', how='inner')
        
    # parcel_id is index of parcels table
    if 'zone_id' in parcels.columns:
        df = df.join(parcels[['zone_id']], on='parcel_id', how='inner')
    else:
        df = df.merge(parcels[['parcel_id', 'zone_id']], on='parcel_id', how='inner')

    df = df.dropna(subset=['zone_id', 'sector_id'])
    
    # Calculate LQ
    zone_sector = df.groupby(['zone_id', 'sector_id']).size().rename('jobs')
    zone_total = df.groupby('zone_id').size().rename('zone_total')
    sector_total = df.groupby('sector_id').size().rename('sector_total')
    city_total = len(df)

    gt_lq = zone_sector.reset_index()
    gt_lq['zone_total'] = gt_lq['zone_id'].map(zone_total)
    gt_lq['sector_total'] = gt_lq['sector_id'].map(sector_total)
    gt_lq['lq'] = (gt_lq['jobs'] / gt_lq['zone_total']) / (gt_lq['sector_total'] / city_total)

    for _, row in gt_lq.iterrows():
        gt_lq_dict[(float(row['zone_id']), float(row['sector_id']))] = float(row['lq'])

    idx = gt_lq.groupby('zone_id')['lq'].idxmax()
    gt_top = gt_lq.loc[idx]
    for _, row in gt_top.iterrows():
        gt_top_spec[float(row['zone_id'])] = float(row['sector_id'])
        
except Exception as e:
    print(f"Error computing ground truth: {e}")

# 3. Evaluate Agent's LQ CSV
lq_csv = "/home/ga/urbansim_projects/output/location_quotients.csv"
if os.path.exists(lq_csv):
    result["lq_csv_exists"] = True
    result["lq_csv_created"] = os.path.getmtime(lq_csv) > task_start
    try:
        agent_lq = pd.read_csv(lq_csv)
        result["lq_csv_rows"] = len(agent_lq)
        
        cols = [c.lower() for c in agent_lq.columns]
        zone_col = next((c for c in cols if 'zone' in c), None)
        sector_col = next((c for c in cols if 'sector' in c), None)
        lq_col = next((c for c in cols if 'lq' in c or 'quotient' in c), None)
        
        if zone_col and sector_col and lq_col:
            result["has_lq_columns"] = True
            matches, total = 0, 0
            for _, row in agent_lq.iterrows():
                try:
                    z, s, lq = float(row[zone_col]), float(row[sector_col]), float(row[lq_col])
                    if pd.notna(z) and pd.notna(s) and pd.notna(lq):
                        key = (z, s)
                        if key in gt_lq_dict:
                            # 5% relative tolerance or 0.05 absolute tolerance
                            if abs(lq - gt_lq_dict[key]) < max(0.05 * gt_lq_dict[key], 0.05):
                                matches += 1
                            total += 1
                except:
                    pass
            if total > 0:
                result["lq_match_ratio"] = matches / total
    except Exception:
        pass

# 4. Evaluate Agent's Specialization CSV
spec_csv = "/home/ga/urbansim_projects/output/zone_specializations.csv"
if os.path.exists(spec_csv):
    result["spec_csv_exists"] = True
    result["spec_csv_created"] = os.path.getmtime(spec_csv) > task_start
    try:
        agent_spec = pd.read_csv(spec_csv)
        cols = [c.lower() for c in agent_spec.columns]
        zone_col = next((c for c in cols if 'zone' in c), None)
        sector_col = next((c for c in cols if 'sector' in c), None)
        
        if zone_col and sector_col:
            result["has_spec_columns"] = True
            matches, total = 0, 0
            for _, row in agent_spec.iterrows():
                try:
                    z, s = float(row[zone_col]), float(row[sector_col])
                    if pd.notna(z) and pd.notna(s):
                        if z in gt_top_spec:
                            if gt_top_spec[z] == s:
                                matches += 1
                            total += 1
                except:
                    pass
            if total > 0:
                result["spec_match_ratio"] = matches / total
    except Exception:
        pass

# 5. Evaluate Plot
plot_path = "/home/ga/urbansim_projects/output/sector_concentration_heatmap.png"
if os.path.exists(plot_path):
    result["plot_exists"] = True
    result["plot_size_kb"] = os.path.getsize(plot_path) / 1024
    result["plot_created"] = os.path.getmtime(plot_path) > task_start

result["timestamp"] = datetime.datetime.now().isoformat()

with open('/tmp/_task_result_tmp.json', 'w') as f:
    json.dump(result, f, indent=2, default=str)
PYEOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/_task_result_tmp.json /tmp/task_result.json 2>/dev/null || sudo cp /tmp/_task_result_tmp.json /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/_task_result_tmp.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="