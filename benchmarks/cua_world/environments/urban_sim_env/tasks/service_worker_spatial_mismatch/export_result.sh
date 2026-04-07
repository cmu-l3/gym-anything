#!/bin/bash
echo "=== Exporting service worker spatial mismatch result ==="

source /workspace/scripts/task_utils.sh
activate_venv

take_screenshot /tmp/task_end.png
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

python << 'PYEOF'
import json, re, os, pandas as pd

task_start = int(open('/home/ga/.task_start_time').read().strip()) if os.path.exists('/home/ga/.task_start_time') else 0

result = {
    "notebook_exists": False,
    "notebook_modified": False,
    "notebook_analysis": {},
    "csv_exists": False,
    "csv_rows": 0,
    "csv_columns": "",
    "csv_created": False,
    "has_zone_id_col": False,
    "has_service_jobs_col": False,
    "has_low_income_hhs_col": False,
    "has_mismatch_ratio_col": False,
    "csv_top_ratio_valid": False,
    "plot_exists": False,
    "plot_size_kb": 0,
    "plot_created": False,
    "task_start_time": task_start
}

nb_path = "/home/ga/urbansim_projects/notebooks/spatial_mismatch.ipynb"
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
            "has_quantile": bool(re.search(r'quantile\s*\(\s*0?\.25\s*\)|percentile', all_code)),
            "has_sector_filter": bool(re.search(r'4|10|isin', all_code)),
            "has_plus_one": bool(re.search(r'\+\s*1', all_code)),
            "has_mismatch": bool(re.search(r'mismatch|ratio', all_code, re.IGNORECASE)),
            "has_savefig": bool(re.search(r'savefig', all_code)),
            "has_to_csv": bool(re.search(r'to_csv', all_code))
        }
    except Exception as e:
        result["notebook_analysis"] = {"error": str(e)}

csv_path = "/home/ga/urbansim_projects/output/worst_mismatch_zones.csv"
if os.path.exists(csv_path):
    result["csv_exists"] = True
    result["csv_created"] = os.path.getmtime(csv_path) > task_start
    try:
        df = pd.read_csv(csv_path)
        result["csv_rows"] = len(df)
        cols = [c.lower() for c in df.columns]
        result["csv_columns"] = ",".join(cols)
        result["has_zone_id_col"] = any('zone' in c for c in cols)
        result["has_service_jobs_col"] = any('job' in c or 'service' in c for c in cols)
        result["has_low_income_hhs_col"] = any('income' in c or 'hh' in c or 'household' in c for c in cols)
        result["has_mismatch_ratio_col"] = any('ratio' in c or 'mismatch' in c for c in cols)
        
        # Verify first row ratio logic
        if not df.empty and result["has_service_jobs_col"] and result["has_low_income_hhs_col"] and result["has_mismatch_ratio_col"]:
            sj_col = next(c for c in df.columns if 'job' in c.lower() or 'service' in c.lower())
            hh_col = next(c for c in df.columns if 'income' in c.lower() or 'hh' in c.lower() or 'household' in c.lower())
            ratio_col = next(c for c in df.columns if 'ratio' in c.lower() or 'mismatch' in c.lower())
            
            sj_val = df[sj_col].iloc[0]
            hh_val = df[hh_col].iloc[0]
            ratio_val = df[ratio_col].iloc[0]
            
            expected_ratio = sj_val / (hh_val + 1)
            if abs(ratio_val - expected_ratio) < 0.1:
                result["csv_top_ratio_valid"] = True
    except Exception:
        pass

plot_path = "/home/ga/urbansim_projects/output/mismatch_scatter.png"
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