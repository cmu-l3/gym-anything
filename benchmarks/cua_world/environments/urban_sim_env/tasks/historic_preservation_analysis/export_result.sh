#!/bin/bash
echo "=== Exporting historic_preservation_analysis result ==="

source /workspace/scripts/task_utils.sh
activate_venv

# Final evidence screenshot
take_screenshot /tmp/task_end.png

# Run Python data validation directly inside the container
python << 'PYEOF'
import json, re, os
import pandas as pd
import numpy as np

# Load start time to verify artifacts were created during this session
task_start = int(open('/home/ga/.task_start_time').read().strip()) if os.path.exists('/home/ga/.task_start_time') else 0

result = {
    "notebook_exists": False,
    "notebook_modified": False,
    "notebook_analysis": {},
    "csv_exists": False,
    "csv_created": False,
    "csv_rows": 0,
    "csv_has_required_cols": False,
    "csv_top_zones": [],
    "plot_exists": False,
    "plot_size_kb": 0,
    "plot_created": False,
    "gt_row_count": -1,
    "gt_top_zones": [],
    "task_start_time": task_start
}

# 1. Compute Ground Truth Hidden from Agent
try:
    b = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'buildings')
    p = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'parcels')
    
    # Safely perform spatial join using parcel mapping
    if 'zone_id' not in b.columns and 'zone_id' in p.columns:
        if 'parcel_id' in p.columns:
            p_zone = p[['parcel_id', 'zone_id']].set_index('parcel_id')
        else:
            p_zone = p[['zone_id']]
        b = b.join(p_zone, on='parcel_id')
        
    b_clean = b[(b['residential_sales_price'] > 0) & (b['year_built'] > 1800)].copy()
    b_clean['is_historic'] = b_clean['year_built'] < 1940
    b_clean['is_modern'] = b_clean['year_built'] >= 1940
    
    def calculate_metrics(x):
        hist_mask = x['is_historic']
        mod_mask = x['is_modern']
        tot = len(x)
        return pd.Series({
            'historic_count': hist_mask.sum(),
            'modern_count': mod_mask.sum(),
            'total_buildings': tot,
            'pct_historic': hist_mask.sum() / tot if tot > 0 else 0,
            'avg_historic_price': x.loc[hist_mask, 'residential_sales_price'].mean(),
            'avg_modern_price': x.loc[mod_mask, 'residential_sales_price'].mean()
        })
        
    aggs = b_clean.groupby('zone_id').apply(calculate_metrics)
    filtered = aggs[(aggs['total_buildings'] >= 50) & (aggs['historic_count'] >= 10)].copy()
    filtered = filtered.sort_values('avg_historic_price', ascending=False)
    
    result["gt_row_count"] = len(filtered)
    result["gt_top_zones"] = filtered.head(3).index.astype(int).tolist()
except Exception as e:
    result["gt_error"] = str(e)
    
# 2. Check Agent CSV
csv_path = "/home/ga/urbansim_projects/output/historic_zones.csv"
if os.path.exists(csv_path):
    result["csv_exists"] = True
    result["csv_created"] = os.path.getmtime(csv_path) > task_start
    try:
        df_agent = pd.read_csv(csv_path)
        result["csv_rows"] = len(df_agent)
        
        cols = [c.lower() for c in df_agent.columns]
        req_cols = ['historic_count', 'modern_count', 'total_buildings', 'pct_historic', 'avg_historic_price']
        result["csv_has_required_cols"] = all(any(req in c for c in cols) for req in req_cols)
        
        zone_col = next((c for c in df_agent.columns if 'zone' in c.lower()), None)
        if zone_col and result["csv_rows"] > 0:
            result["csv_top_zones"] = df_agent.head(3)[zone_col].fillna(0).astype(int).tolist()
    except Exception as e:
        result["csv_error"] = str(e)
        
# 3. Check Agent Plot
plot_path = "/home/ga/urbansim_projects/output/historic_scatter.png"
if os.path.exists(plot_path):
    result["plot_exists"] = True
    result["plot_size_kb"] = os.path.getsize(plot_path) / 1024
    result["plot_created"] = os.path.getmtime(plot_path) > task_start
    
# 4. Check Agent Notebook Execution
nb_path = "/home/ga/urbansim_projects/notebooks/historic_analysis.ipynb"
if os.path.exists(nb_path):
    result["notebook_exists"] = True
    result["notebook_modified"] = os.path.getmtime(nb_path) > task_start
    try:
        with open(nb_path, 'r') as f:
            nb = json.load(f)
        code_cells = [c for c in nb.get('cells', []) if c.get('cell_type') == 'code']
        result["notebook_analysis"]["num_executed_cells"] = sum(1 for c in code_cells if c.get('execution_count') is not None)
    except Exception:
        pass
        
with open('/tmp/_task_result_tmp.json', 'w') as f:
    json.dump(result, f, indent=2, default=str)
PYEOF

# Safely copy to final export destination
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/_task_result_tmp.json /tmp/task_result.json 2>/dev/null || sudo cp /tmp/_task_result_tmp.json /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/_task_result_tmp.json

echo "Result safely saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="