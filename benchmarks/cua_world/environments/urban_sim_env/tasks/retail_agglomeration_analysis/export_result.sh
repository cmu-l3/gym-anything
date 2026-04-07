#!/bin/bash
echo "=== Exporting retail agglomeration result ==="

source /workspace/scripts/task_utils.sh
activate_venv

take_screenshot /tmp/task_end.png
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

# Run python script inside the container's environment where pandas is available 
# to calculate exact correctness metrics without passing massive data out.
python << 'PYEOF'
import json, re, os

task_start = int(open('/home/ga/.task_start_time').read().strip()) if os.path.exists('/home/ga/.task_start_time') else 0

result = {
    "notebook_exists": False,
    "notebook_modified": False,
    "notebook_analysis": {},
    "csv1_exists": False,
    "csv1_has_cols": False,
    "csv1_math_correct": False,
    "csv1_flag_correct": False,
    "csv2_exists": False,
    "csv2_filtered_correctly": False,
    "plot_exists": False,
    "plot_created": False,
    "task_start_time": task_start
}

# 1. Analyze Notebook
nb_path = "/home/ga/urbansim_projects/notebooks/retail_agglomeration.ipynb"
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
            "has_sector": bool(re.search(r'sector_id|10|11', all_code)),
            "has_merge": bool(re.search(r'merge|join', all_code)),
            "has_lq": bool(re.search(r'lq|quotient|/|sum', all_code, re.IGNORECASE))
        }
    except Exception as e:
        result["notebook_analysis"] = {"error": str(e)}

# 2. Analyze CSV 1 (Full zone data)
csv1_path = "/home/ga/urbansim_projects/output/zone_lq_analysis.csv"
if os.path.exists(csv1_path):
    result["csv1_exists"] = True
    try:
        import pandas as pd
        import numpy as np
        df = pd.read_csv(csv1_path)
        cols = [c.lower() for c in df.columns]
        req = ['zone_id', 'total_jobs', 'retail_jobs', 'lq', 'is_retail_center']
        
        if all(c in cols for c in req):
            result["csv1_has_cols"] = True
            
            # Recalculate LQ to verify math
            t_jobs = df['total_jobs'].sum()
            t_ret = df['retail_jobs'].sum()
            
            if t_jobs > 0 and t_ret > 0:
                expected_lq = (df['retail_jobs'] / df['total_jobs'].replace(0, np.nan)) / (t_ret / t_jobs)
                expected_lq = expected_lq.fillna(0)
                
                if np.abs(df['lq'] - expected_lq).max() < 0.05:
                    result["csv1_math_correct"] = True
                    
                # Verify flags
                expected_centers = (df['lq'] > 1.25) & (df['retail_jobs'] >= 100)
                if (df['is_retail_center'].astype(bool) == expected_centers).all():
                    result["csv1_flag_correct"] = True
    except Exception as e:
        result["csv1_error"] = str(e)

# 3. Analyze CSV 2 (Filtered data)
csv2_path = "/home/ga/urbansim_projects/output/retail_centers.csv"
if os.path.exists(csv2_path):
    result["csv2_exists"] = True
    try:
        import pandas as pd
        df2 = pd.read_csv(csv2_path)
        if 'lq' in df2.columns and 'retail_jobs' in df2.columns:
            if len(df2) > 0 and (df2['lq'] > 1.24).all() and (df2['retail_jobs'] >= 100).all():
                result["csv2_filtered_correctly"] = True
    except Exception as e:
        result["csv2_error"] = str(e)

# 4. Analyze Plot
plot_path = "/home/ga/urbansim_projects/output/retail_lq_plot.png"
if os.path.exists(plot_path):
    result["plot_exists"] = True
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