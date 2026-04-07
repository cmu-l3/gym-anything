#!/bin/bash
echo "=== Exporting property tax revenue projection result ==="

source /workspace/scripts/task_utils.sh
activate_venv

take_screenshot /tmp/task_end.png
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

# Run an inline python script to analyze the agent's work AND compute ground truth
python << 'PYEOF'
import json, re, os, sys
import pandas as pd
import numpy as np

task_start = int(open('/home/ga/.task_start_time').read().strip()) if os.path.exists('/home/ga/.task_start_time') else 0

result = {
    "notebook_exists": False,
    "notebook_modified": False,
    "notebook_analysis": {},
    "csv_exists": False,
    "csv_rows": 0,
    "csv_columns": [],
    "csv_created": False,
    "plot_exists": False,
    "plot_size_kb": 0,
    "plot_created": False,
    "task_start_time": task_start,
    "agent_totals": {},
    "ground_truth": {}
}

# 1. Compute Ground Truth (Safe reference inside the container)
try:
    bld = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'buildings')
    pcl = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'parcels')
    
    # Filter valid prices
    bld_valid = bld[(bld['residential_sales_price'].notna()) & (bld['residential_sales_price'] > 0)]
    
    # Join to parcels
    joined = bld_valid.join(pcl[['zone_id']], on='parcel_id', how='inner')
    
    # Aggregate
    zone_totals = joined.groupby('zone_id')['residential_sales_price'].sum().reset_index()
    
    gt_total_assessed = float(zone_totals['residential_sales_price'].sum())
    gt_total_tax = gt_total_assessed * 0.0117
    
    # Sort for top 5
    top5 = zone_totals.sort_values('residential_sales_price', ascending=False).head(5)['zone_id'].tolist()
    
    result['ground_truth'] = {
        'total_assessed': gt_total_assessed,
        'total_tax': gt_total_tax,
        'zone_count': len(zone_totals),
        'top5_zones': [int(x) for x in top5]
    }
except Exception as e:
    result['ground_truth'] = {"error": str(e)}

# 2. Analyze Notebook Code
nb_path = "/home/ga/urbansim_projects/notebooks/tax_revenue_analysis.ipynb"
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
            "has_merge": bool(re.search(r'merge|join', all_code)),
            "has_groupby": bool(re.search(r'groupby', all_code)),
            "has_tax_rate": bool(re.search(r'0\.0117|1\.17', all_code)),
            "has_sort": bool(re.search(r'sort_values', all_code)),
            "has_bar_plot": bool(re.search(r'barh\(|bar\(|\.plot\.bar', all_code)),
            "has_savefig": bool(re.search(r'savefig', all_code))
        }
    except Exception as e:
        result["notebook_analysis"] = {"error": str(e)}

# 3. Analyze Agent Output CSV
csv_path = "/home/ga/urbansim_projects/output/zone_tax_revenue.csv"
if os.path.exists(csv_path):
    result["csv_exists"] = True
    result["csv_created"] = os.path.getmtime(csv_path) > task_start
    try:
        df = pd.read_csv(csv_path)
        df_cols = [c.lower().strip() for c in df.columns]
        result["csv_columns"] = df_cols
        result["csv_rows"] = len(df)
        
        # Identify columns
        assessed_col = next((c for c in df_cols if 'assessed' in c and 'total' in c), None) or next((c for c in df_cols if 'assessed' in c), None)
        tax_col = next((c for c in df_cols if 'tax' in c and 'acre' not in c and 'per' not in c), None)
        zone_col = next((c for c in df_cols if 'zone' in c), None)
        acre_col = next((c for c in df_cols if 'acre' in c and 'per' not in c and 'tax' not in c), None)
        tax_per_acre_col = next((c for c in df_cols if 'tax' in c and 'acre' in c), None)
        
        if assessed_col and tax_col:
            result['agent_totals']['total_assessed'] = float(df[assessed_col].sum())
            result['agent_totals']['total_tax'] = float(df[tax_col].sum())
            result['agent_totals']['zone_count'] = int(len(df))
            
            if zone_col:
                top5 = df.sort_values(tax_col, ascending=False).head(5)[zone_col].tolist()
                result['agent_totals']['top5_zones'] = [int(x) for x in top5]
                
        if tax_per_acre_col:
            result['agent_totals']['positive_tax_per_acre_count'] = int((df[tax_per_acre_col] > 0).sum())
            
    except Exception as e:
        result['agent_csv_error'] = str(e)

# 4. Analyze Output Plot
plot_path = "/home/ga/urbansim_projects/output/tax_revenue_top_zones.png"
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