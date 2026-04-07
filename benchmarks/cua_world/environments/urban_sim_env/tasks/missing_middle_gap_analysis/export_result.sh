#!/bin/bash
echo "=== Exporting missing middle analysis result ==="

source /workspace/scripts/task_utils.sh
activate_venv

# Take final screenshot
take_screenshot /tmp/task_end.png
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

# Run deep verification script inside the environment to compute Ground Truth
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
    "csv_columns": [],
    "csv_created": False,
    "logic_percentages_sum_to_100": False,
    "logic_flag_correct": False,
    "logic_gt_units_match": False,
    "plot_exists": False,
    "plot_size_kb": 0,
    "plot_created": False,
    "task_start_time": task_start,
    "errors": []
}

nb_path = "/home/ga/urbansim_projects/notebooks/missing_middle.ipynb"
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
            "has_read_hdf": bool(re.search(r'read_hdf|HDFStore', all_code)),
            "has_merge": bool(re.search(r'merge|join', all_code)),
            "has_sum": bool(re.search(r'\.sum\(\)', all_code)),
            "has_plot": bool(re.search(r'plot|bar|matplotlib|seaborn', all_code)),
            "has_to_csv": bool(re.search(r'to_csv', all_code))
        }
    except Exception as e:
        result["errors"].append(f"Notebook parse error: {str(e)}")

csv_path = "/home/ga/urbansim_projects/output/missing_middle_zones.csv"
if os.path.exists(csv_path):
    result["csv_exists"] = True
    result["csv_created"] = os.path.getmtime(csv_path) > task_start
    try:
        df = pd.read_csv(csv_path)
        result["csv_rows"] = len(df)
        result["csv_columns"] = list(df.columns)
        
        # 1. Check percentage math
        if all(col in df.columns for col in ['pct_single_family', 'pct_missing_middle', 'pct_high_density']):
            pct_sum = df['pct_single_family'] + df['pct_missing_middle'] + df['pct_high_density']
            result["logic_percentages_sum_to_100"] = bool((abs(pct_sum - 100) < 1.0).all())
            
        # 2. Check flag logic
        if all(col in df.columns for col in ['pct_single_family', 'pct_missing_middle', 'is_opportunity_zone']):
            expected_flag = (df['pct_single_family'] > 50) & (df['pct_missing_middle'] < 15)
            # Handle boolean or string matching
            if df['is_opportunity_zone'].dtype == object:
                actual_flag = df['is_opportunity_zone'].astype(str).str.lower() == 'true'
            else:
                actual_flag = df['is_opportunity_zone'].astype(bool)
                
            result["logic_flag_correct"] = bool((actual_flag == expected_flag).all())
            
        # 3. Ground truth units check (Did they SUM units instead of counting buildings?)
        if 'zone_id' in df.columns and 'total_units' in df.columns and len(df) > 0:
            # Compute real ground truth
            bldgs = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'buildings')
            parcels = pd.read_hdf('/home/ga/urbansim_projects/data/sanfran_public.h5', 'parcels')
            
            bldgs = bldgs[bldgs.residential_units > 0]
            if 'zone_id' not in bldgs.columns:
                bldgs = bldgs.merge(parcels[['zone_id']], left_on='parcel_id', right_index=True)
                
            gt_units = bldgs.groupby('zone_id')['residential_units'].sum()
            
            # Check the first zone in their dataframe against GT
            zone_to_check = df.iloc[0]['zone_id']
            agent_val = df.iloc[0]['total_units']
            
            if zone_to_check in gt_units.index:
                gt_val = gt_units.loc[zone_to_check]
                # If they counted buildings instead of summing units, the number will be way off
                result["logic_gt_units_match"] = bool(abs(agent_val - gt_val) < 5)
            
    except Exception as e:
        result["errors"].append(f"CSV validation error: {str(e)}")

plot_path = "/home/ga/urbansim_projects/output/opportunity_zones_chart.png"
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