#!/bin/bash
echo "=== Exporting land_value_gradient_analysis result ==="

source /workspace/scripts/task_utils.sh
activate_venv

take_screenshot /tmp/task_end.png
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

# Use Python to analyze outputs safely
python << 'PYEOF'
import json, re, os
import pandas as pd
import numpy as np

task_start = int(open('/home/ga/.task_start_time').read().strip()) if os.path.exists('/home/ga/.task_start_time') else 0

result = {
    "notebook_exists": False,
    "notebook_modified": False,
    "notebook_analysis": {},
    "curve_csv_exists": False,
    "curve_csv_created": False,
    "curve_rows": 0,
    "anomalies_csv_exists": False,
    "anomalies_csv_created": False,
    "anomalies_rows": 0,
    "anomalies_distance_ok": False,
    "plot_exists": False,
    "plot_size_kb": 0,
    "plot_created": False,
    "task_start_time": task_start
}

nb_path = "/home/ga/urbansim_projects/notebooks/bid_rent_analysis.ipynb"
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
            "has_hdf": bool(re.search(r'read_hdf|HDFStore', all_code)),
            "has_distance": bool(re.search(r'\*\* ?2|np\.sqrt|spatial\.distance|hypot', all_code)),
            "has_groupby": bool(re.search(r'groupby', all_code)),
            "has_division": bool(re.search(r'/', all_code)) or bool(re.search(r'div\(', all_code)),
            "has_savefig": bool(re.search(r'savefig', all_code)),
            "has_to_csv": bool(re.search(r'to_csv', all_code))
        }
    except Exception as e:
        result["notebook_analysis"] = {"error": str(e)}

curve_path = "/home/ga/urbansim_projects/output/bid_rent_curve.csv"
if os.path.exists(curve_path):
    result["curve_csv_exists"] = True
    result["curve_csv_created"] = os.path.getmtime(curve_path) > task_start
    try:
        df = pd.read_csv(curve_path)
        result["curve_rows"] = len(df)
    except Exception:
        pass

anomalies_path = "/home/ga/urbansim_projects/output/value_anomalies.csv"
if os.path.exists(anomalies_path):
    result["anomalies_csv_exists"] = True
    result["anomalies_csv_created"] = os.path.getmtime(anomalies_path) > task_start
    try:
        df = pd.read_csv(anomalies_path)
        result["anomalies_rows"] = len(df)
        
        # Determine if distances are actually > 10,000 (tolerate minor rounding / floating issues)
        dist_cols = [c for c in df.columns if 'dist' in str(c).lower()]
        if dist_cols:
            d_col = dist_cols[0]
            if (pd.to_numeric(df[d_col], errors='coerce') >= 9900).all():
                result["anom_dist_col_found"] = True
                result["anomalies_distance_ok"] = True
        else:
            # Check if any numeric column has values mostly > 9900 (heuristic for distance)
            for c in df.select_dtypes(include=[np.number]).columns:
                if (df[c] > 9900).all() and (df[c] < 100000).any():
                    result["anomalies_distance_ok"] = True
                    break
    except Exception:
        pass

plot_path = "/home/ga/urbansim_projects/output/bid_rent_chart.png"
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