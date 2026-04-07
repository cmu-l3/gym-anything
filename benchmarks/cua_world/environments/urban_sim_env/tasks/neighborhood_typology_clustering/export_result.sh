#!/bin/bash
echo "=== Exporting neighborhood typology clustering result ==="

source /workspace/scripts/task_utils.sh
activate_venv

# Take final screenshot
take_screenshot /tmp/task_end.png

# Analyze the outputs using Python to prevent JSON formatting errors in bash
python << 'PYEOF'
import json
import re
import os
import datetime

task_start = 0
if os.path.exists('/home/ga/.task_start_time'):
    with open('/home/ga/.task_start_time') as f:
        try:
            task_start = int(f.read().strip())
        except ValueError:
            pass

result = {
    "notebook_exists": False,
    "notebook_modified": False,
    "notebook_analysis": {},
    "csv_exists": False,
    "csv_rows": 0,
    "csv_columns": "",
    "csv_created": False,
    "has_zone_id_col": False,
    "has_cluster_col": False,
    "num_feature_cols_found": 0,
    "cluster_values": [],
    "plot_exists": False,
    "plot_size_kb": 0,
    "plot_created": False,
    "task_start_time": task_start,
    "timestamp": datetime.datetime.now().isoformat()
}

nb_path = "/home/ga/urbansim_projects/notebooks/neighborhood_typology.ipynb"
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
            # Remove comments for clean matching
            lines = [l for l in src.split('\n') if not l.strip().startswith('#')]
            all_code += '\n'.join(lines) + '\n'
            
        result["notebook_analysis"] = {
            "num_code_cells": len(code_cells),
            "num_executed_cells": sum(1 for c in code_cells if c.get('execution_count') is not None),
            "has_pandas": bool(re.search(r'import pandas|from pandas', all_code)),
            "has_read_hdf": bool(re.search(r'read_hdf|HDFStore', all_code)),
            "has_merge": bool(re.search(r'merge|join', all_code)),
            "has_groupby": bool(re.search(r'groupby', all_code)),
            "has_agg": bool(re.search(r'\.agg\(|\.mean\(|\.sum\(', all_code)),
            "has_scaler": bool(re.search(r'StandardScaler|MinMaxScaler|scale', all_code)),
            "has_kmeans": bool(re.search(r'KMeans', all_code)),
            "has_k5": bool(re.search(r'n_clusters\s*=\s*5', all_code)),
            "has_to_csv": bool(re.search(r'to_csv', all_code)),
            "has_savefig": bool(re.search(r'savefig', all_code))
        }
    except Exception as e:
        result["notebook_analysis"] = {"error": str(e)}

csv_path = "/home/ga/urbansim_projects/output/zone_typologies.csv"
if os.path.exists(csv_path):
    result["csv_exists"] = True
    result["csv_created"] = os.path.getmtime(csv_path) > task_start
    try:
        import pandas as pd
        df = pd.read_csv(csv_path)
        result["csv_rows"] = len(df)
        cols = [c.lower().strip() for c in df.columns]
        result["csv_columns"] = ",".join(cols)
        
        # Check required columns loosely
        result["has_zone_id_col"] = any('zone' in c for c in cols)
        
        cluster_col = None
        for c in cols:
            if 'cluster' in c or 'typolog' in c or 'label' in c:
                cluster_col = c
                break
                
        result["has_cluster_col"] = cluster_col is not None
        
        if cluster_col and len(df) > 0:
            # Get unique cluster values
            vals = df[df.columns[cols.index(cluster_col)]].dropna().unique().tolist()
            result["cluster_values"] = [int(v) for v in vals if str(v).replace('.','',1).isdigit()]
            
        # Check how many feature columns were made
        feature_keywords = ['year', 'residential', 'sqft', 'building']
        found_features = 0
        for fk in feature_keywords:
            if any(fk in c for c in cols):
                found_features += 1
        result["num_feature_cols_found"] = found_features
        
    except Exception as e:
        result["csv_error"] = str(e)

plot_path = "/home/ga/urbansim_projects/output/cluster_profiles.png"
if os.path.exists(plot_path):
    result["plot_exists"] = True
    result["plot_size_kb"] = os.path.getsize(plot_path) / 1024
    result["plot_created"] = os.path.getmtime(plot_path) > task_start

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="