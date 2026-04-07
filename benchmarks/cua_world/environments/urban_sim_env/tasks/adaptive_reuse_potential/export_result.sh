#!/bin/bash
echo "=== Exporting adaptive_reuse_potential result ==="

source /workspace/scripts/task_utils.sh
activate_venv

take_screenshot /tmp/task_end.png
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

# We run a Python script in the container to evaluate the exact data.
# This prevents downloading a large HDF5 file to the host verifier.
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
    "csv_created_during_task": False,
    "csv_rows": 0,
    "csv_columns": [],
    "has_req_cols": False,
    "ground_truth_matches": 0,
    "total_true_candidates": 0,
    "plot_exists": False,
    "plot_created_during_task": False,
    "plot_size_kb": 0,
    "task_start_time": task_start
}

# 1. Evaluate Notebook
nb_path = "/home/ga/urbansim_projects/notebooks/adaptive_reuse.ipynb"
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
            "has_merge": bool(re.search(r'merge|join', all_code)),
            "has_groupby": bool(re.search(r'groupby', all_code)),
            "has_filter": bool(re.search(r'residential_units.*?==.*?0|non_residential_sqft.*?>=.*?20000|year_built.*?<.*?1990', all_code)),
            "has_sqft_calc": bool(re.search(r'sqft_per_job|/', all_code)),
            "has_savefig": bool(re.search(r'savefig', all_code)),
            "has_to_csv": bool(re.search(r'to_csv', all_code))
        }
    except Exception as e:
        result["notebook_analysis"] = {"error": str(e)}

# 2. Compute Ground Truth locally to evaluate accuracy accurately
try:
    data_path = '/home/ga/urbansim_projects/data/sanfran_public.h5'
    bld = pd.read_hdf(data_path, 'buildings')
    jobs = pd.read_hdf(data_path, 'jobs')
    
    # Reset index if building_id is the index
    if bld.index.name == 'building_id' or 'building_id' not in bld.columns:
        bld = bld.reset_index()
    
    job_counts = jobs.groupby('building_id').size().reset_index(name='total_jobs')
    bld = bld.merge(job_counts, on='building_id', how='left')
    bld['total_jobs'] = bld['total_jobs'].fillna(0)
    
    # Calculate sqft per job
    bld['sqft_per_job'] = np.where(bld['total_jobs'] > 0, bld['non_residential_sqft'] / bld['total_jobs'], np.inf)
    
    # Filter
    mask = (
        (bld['residential_units'] == 0) &
        (bld['non_residential_sqft'] >= 20000) &
        (bld['year_built'] < 1990) &
        ((bld['total_jobs'] == 0) | (bld['sqft_per_job'] > 400))
    )
    
    candidates = bld[mask].copy()
    candidates = candidates.sort_values(by='non_residential_sqft', ascending=False)
    
    top_100_true_ids = set(candidates.head(100)['building_id'].astype(int).tolist())
    result["total_true_candidates"] = len(top_100_true_ids)
except Exception as e:
    print(f"Error calculating ground truth: {e}", file=sys.stderr)
    top_100_true_ids = set()

# 3. Evaluate CSV Output
csv_path = "/home/ga/urbansim_projects/output/adaptive_reuse_candidates.csv"
if os.path.exists(csv_path):
    result["csv_exists"] = True
    result["csv_created_during_task"] = os.path.getmtime(csv_path) > task_start
    try:
        user_df = pd.read_csv(csv_path)
        result["csv_rows"] = len(user_df)
        cols = [str(c).lower().strip() for c in user_df.columns]
        result["csv_columns"] = cols
        
        req_cols = ['year_built', 'non_residential_sqft', 'total_jobs', 'sqft_per_job']
        result["has_req_cols"] = all(any(req in c for c in cols) for req in req_cols)
        
        # Determine building id column
        bid_col = None
        if 'building_id' in cols:
            bid_col = user_df.columns[cols.index('building_id')]
        elif 'unnamed: 0' in cols:
            bid_col = user_df.columns[cols.index('unnamed: 0')]
        elif 'id' in cols:
            bid_col = user_df.columns[cols.index('id')]
            
        if bid_col is not None and len(top_100_true_ids) > 0:
            user_ids = set(user_df[bid_col].fillna(-1).astype(int).tolist())
            matches = len(user_ids.intersection(top_100_true_ids))
            result["ground_truth_matches"] = matches
    except Exception as e:
        print(f"Error reading CSV: {e}", file=sys.stderr)

# 4. Evaluate Plot
plot_path = "/home/ga/urbansim_projects/output/reuse_scatter.png"
if os.path.exists(plot_path):
    result["plot_exists"] = True
    result["plot_size_kb"] = os.path.getsize(plot_path) / 1024
    result["plot_created_during_task"] = os.path.getmtime(plot_path) > task_start

# Export Result
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