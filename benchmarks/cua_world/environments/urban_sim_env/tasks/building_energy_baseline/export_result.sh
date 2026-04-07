#!/bin/bash
echo "=== Exporting building_energy_baseline result ==="

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
    "csv_created": False,
    "csv_rows": 0,
    "csv_columns": [],
    "agent_total_energy": 0,
    "agent_num_zones": 0,
    "plot_exists": False,
    "plot_created": False,
    "plot_size_kb": 0,
    "gt_total_energy": 0,
    "gt_num_zones": 0,
    "task_start_time": task_start
}

# --- 1. Compute Ground Truth ---
try:
    b = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'buildings')
    p = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'parcels')
    
    # Merge
    if 'zone_id' not in b.columns and 'zone_id' in p.columns:
        if 'parcel_id' in b.columns:
            df = b.merge(p[['zone_id']], left_on='parcel_id', right_index=True, how='left')
        else:
            df = b.copy()
    else:
        df = b.copy()

    # Total Sqft calculation
    sqft = df.get('building_sqft', pd.Series(np.nan, index=df.index)).copy()
    mask = sqft.isna() | (sqft == 0)
    
    if 'residential_units' in df.columns and 'non_residential_sqft' in df.columns:
        alt = (df['residential_units'].fillna(0) * 800) + df['non_residential_sqft'].fillna(0)
        sqft[mask] = alt[mask]
    
    df['total_sqft'] = sqft.fillna(0)
    df = df[df['total_sqft'] > 0].copy()

    # EUI assignment
    def get_eui(y):
        if pd.isna(y) or y < 1980: return 90
        elif y <= 1999: return 70
        elif y <= 2009: return 50
        else: return 35
        
    if 'year_built' in df.columns:
        df['eui'] = df['year_built'].apply(get_eui)
    else:
        df['eui'] = 90
        
    df['energy_kwh'] = df['total_sqft'] * df['eui']
    
    if 'zone_id' in df.columns:
        gt = df.groupby('zone_id')['energy_kwh'].agg(['sum', 'count']).reset_index()
        result['gt_total_energy'] = float(gt['sum'].sum())
        result['gt_num_zones'] = len(gt)
except Exception as e:
    result['gt_error'] = str(e)

# --- 2. Evaluate Notebook ---
nb_path = "/home/ga/urbansim_projects/notebooks/energy_baseline.ipynb"
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
            "has_pandas": bool(re.search(r'import pandas', all_code)),
            "has_geopandas": bool(re.search(r'import geopandas|gpd\.', all_code)),
            "has_merge": bool(re.search(r'merge|join', all_code)),
            "has_groupby": bool(re.search(r'groupby', all_code)),
            "has_plot": bool(re.search(r'\.plot\(', all_code)),
            "has_to_csv": bool(re.search(r'to_csv', all_code))
        }
    except Exception as e:
        result["notebook_analysis"]["error"] = str(e)

# --- 3. Evaluate CSV ---
csv_path = "/home/ga/urbansim_projects/output/zone_energy_baseline.csv"
if os.path.exists(csv_path):
    result["csv_exists"] = True
    result["csv_created"] = os.path.getmtime(csv_path) > task_start
    try:
        agent_df = pd.read_csv(csv_path)
        cols = [c.lower().strip() for c in agent_df.columns]
        result["csv_columns"] = cols
        result["csv_rows"] = len(agent_df)
        
        # Check values
        if 'total_energy_kwh' in cols:
            agent_energy_col = 'total_energy_kwh'
        else:
            # Fallback if named slightly differently
            matches = [c for c in cols if 'energy' in c or 'kwh' in c]
            agent_energy_col = matches[0] if matches else None
            
        if agent_energy_col:
            result['agent_total_energy'] = float(agent_df[agent_energy_col].sum())
        result['agent_num_zones'] = len(agent_df)
    except Exception as e:
        result['csv_error'] = str(e)

# --- 4. Evaluate Plot ---
plot_path = "/home/ga/urbansim_projects/output/energy_map.png"
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
cat /tmp/task_result.json
echo "=== Export complete ==="