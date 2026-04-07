#!/bin/bash
echo "=== Exporting space consumption inequity result ==="

source /workspace/scripts/task_utils.sh
activate_venv

# Take screenshot as evidence of final state
take_screenshot /tmp/task_end.png
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

# Use Python to reliably extract metrics and calculate ground-truth internally
python << 'PYEOF'
import json, re, os, traceback
import pandas as pd
import numpy as np

task_start = int(open('/home/ga/.task_start_time').read().strip()) if os.path.exists('/home/ga/.task_start_time') else 0

result = {
    "notebook_exists": False,
    "notebook_modified": False,
    "notebook_analysis": {},
    "csv1_exists": False,
    "csv1_rows": 0,
    "csv1_cols": [],
    "agent_d1": 0.0,
    "agent_d10": 0.0,
    "agent_income_monotonic": False,
    "csv2_exists": False,
    "csv2_rows": 0,
    "csv2_cols": [],
    "plot_exists": False,
    "plot_size_kb": 0,
    "plot_created": False,
    "report_exists": False,
    "report_ratio": 0.0,
    "gt_d1": 0.0,
    "gt_d10": 0.0,
    "gt_zone_count": 0,
    "gt_ratio": 0.0,
    "task_start_time": task_start,
    "error_log": []
}

# 1. Analyze the Jupyter Notebook
nb_path = "/home/ga/urbansim_projects/notebooks/space_consumption.ipynb"
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
            "has_pandas": bool(re.search(r'import pandas', all_code)),
            "has_qcut": bool(re.search(r'qcut', all_code)),
            "has_merge": bool(re.search(r'merge|join', all_code)),
            "has_groupby": bool(re.search(r'groupby', all_code))
        }
    except Exception as e:
        result["error_log"].append(f"NB Parse error: {str(e)}")

# 2. Compute Strict Ground Truth (to prevent gaming)
try:
    h5_path = '/home/ga/urbansim_projects/data/sanfran_public.h5'
    hh = pd.read_hdf(h5_path, 'households')
    bld = pd.read_hdf(h5_path, 'buildings')
    parcels = pd.read_hdf(h5_path, 'parcels')

    df = hh.merge(bld, left_on='building_id', right_index=True)
    if 'zone_id' not in df.columns:
        df = df.merge(parcels[['zone_id']], left_on='parcel_id', right_index=True)

    df = df[df['persons'] > 0].copy()

    if 'sqft_per_unit' in df.columns:
        df['unit_sqft'] = df['sqft_per_unit'].fillna(df['building_sqft'] / df['residential_units'].replace(0, np.nan))
    else:
        df['unit_sqft'] = df['building_sqft'] / df['residential_units'].replace(0, np.nan)

    df = df[(df['unit_sqft'] >= 100) & (df['unit_sqft'] <= 20000) & (df['unit_sqft'].notna())].copy()
    df['sqft_per_person'] = df['unit_sqft'] / df['persons']

    # Using rank to avoid ValueError with duplicate bins while preserving equal buckets
    df['income_decile'] = pd.qcut(df['income'].rank(method='first'), 10, labels=False) + 1
    decile_stats = df.groupby('income_decile')['sqft_per_person'].median()

    result['gt_d1'] = float(decile_stats.loc[1])
    result['gt_d10'] = float(decile_stats.loc[10])
    result['gt_ratio'] = float(result['gt_d10'] / result['gt_d1']) if result['gt_d1'] > 0 else 0.0

    zone_counts = df.groupby('zone_id').size()
    result['gt_zone_count'] = int((zone_counts >= 50).sum())

except Exception as e:
    result["error_log"].append(f"GT calc error: {str(e)}\n{traceback.format_exc()}")

# 3. Analyze output CSV 1 (Deciles)
csv1_path = "/home/ga/urbansim_projects/output/space_by_income_decile.csv"
if os.path.exists(csv1_path):
    result["csv1_exists"] = True
    try:
        df_agent1 = pd.read_csv(csv1_path)
        result["csv1_rows"] = len(df_agent1)
        result["csv1_cols"] = list(df_agent1.columns)
        
        decile_col = next((c for c in df_agent1.columns if 'decile' in c.lower()), None)
        sqft_col = next((c for c in df_agent1.columns if 'sqft' in c.lower() and 'person' in c.lower()), None)
        inc_col = next((c for c in df_agent1.columns if 'income' in c.lower() and 'median' in c.lower()), None)
        
        if decile_col and sqft_col:
            df_agent1 = df_agent1.sort_values(decile_col)
            result["agent_d1"] = float(df_agent1.iloc[0][sqft_col])
            result["agent_d10"] = float(df_agent1.iloc[-1][sqft_col])
        if inc_col:
            incomes = df_agent1[inc_col].dropna().values
            result["agent_income_monotonic"] = bool(np.all(np.diff(incomes) >= 0))
    except Exception as e:
        result["error_log"].append(f"CSV1 error: {str(e)}")

# 4. Analyze output CSV 2 (Zones)
csv2_path = "/home/ga/urbansim_projects/output/space_by_zone.csv"
if os.path.exists(csv2_path):
    result["csv2_exists"] = True
    try:
        df_agent2 = pd.read_csv(csv2_path)
        result["csv2_rows"] = len(df_agent2)
        result["csv2_cols"] = list(df_agent2.columns)
    except Exception as e:
        result["error_log"].append(f"CSV2 error: {str(e)}")

# 5. Analyze Plot
plot_path = "/home/ga/urbansim_projects/output/space_inequity_chart.png"
if os.path.exists(plot_path):
    result["plot_exists"] = True
    result["plot_size_kb"] = os.path.getsize(plot_path) / 1024
    result["plot_created"] = os.path.getmtime(plot_path) > task_start

# 6. Analyze Report
report_path = "/home/ga/urbansim_projects/output/space_ratio_report.txt"
if os.path.exists(report_path):
    result["report_exists"] = True
    try:
        with open(report_path, 'r') as f:
            content = f.read()
            # Extract first positive float/int found
            nums = re.findall(r'\b\d+(?:\.\d+)?\b', content)
            if nums:
                result["report_ratio"] = float(nums[0])
    except Exception as e:
        result["error_log"].append(f"Report error: {str(e)}")

result["timestamp"] = __import__('datetime').datetime.now().isoformat()

# Save payload to JSON securely
with open('/tmp/_task_result_tmp.json', 'w') as f:
    json.dump(result, f, indent=2, default=str)
PYEOF

# Move and fix permissions safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/_task_result_tmp.json /tmp/task_result.json 2>/dev/null || sudo cp /tmp/_task_result_tmp.json /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/_task_result_tmp.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="