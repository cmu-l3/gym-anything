#!/bin/bash
echo "=== Exporting office_to_res_conversion result ==="

source /workspace/scripts/task_utils.sh
activate_venv

# Take final screenshot
take_screenshot /tmp/task_end.png

# Run Python validation script to assemble results
python << 'PYEOF'
import json
import os
import re
import datetime

task_start_file = '/home/ga/.task_start_time'
task_start = int(open(task_start_file).read().strip()) if os.path.exists(task_start_file) else 0

result = {
    "task_start_time": task_start,
    "timestamp": datetime.datetime.now().isoformat(),
    "notebook": {"exists": False, "modified": False, "analysis": {}},
    "top_csv": {"exists": False, "created": False, "rows": 0, "columns": []},
    "zone_csv": {"exists": False, "created": False, "rows": 0, "columns": []},
    "plot": {"exists": False, "created": False, "size_kb": 0}
}

# 1. Analyze Notebook
nb_path = "/home/ga/urbansim_projects/notebooks/office_conversion.ipynb"
if os.path.exists(nb_path):
    result["notebook"]["exists"] = True
    result["notebook"]["modified"] = os.path.getmtime(nb_path) > task_start
    try:
        with open(nb_path, 'r') as f:
            nb = json.load(f)
        
        code_cells = [c for c in nb.get('cells', []) if c.get('cell_type') == 'code']
        all_code = ''
        for c in code_cells:
            src = c.get('source', '')
            if isinstance(src, list):
                src = ''.join(src)
            # Remove comments
            lines = [l for l in src.split('\n') if not l.strip().startswith('#')]
            all_code += '\n'.join(lines) + '\n'
            
        # Clean string literals for safer logic checking
        clean_code = re.sub(r'"""[\s\S]*?"""|\'\'\'[\s\S]*?\'\'\'', '', all_code)
        clean_code = re.sub(r'"[^"\n]*"|\'[^\'\n]*\'', '', clean_code)
        
        analysis = {
            "num_code_cells": len(code_cells),
            "num_executed_cells": sum(1 for c in code_cells if c.get('execution_count') is not None),
            "has_pandas": bool(re.search(r'import pandas|from pandas', clean_code)),
            "has_merge": bool(re.search(r'merge|join', clean_code)),
            "has_building_type": bool(re.search(r'building_type_id', clean_code)),
            "has_age_math": bool(re.search(r'2026', clean_code)),
            "has_units_math": bool(re.search(r'1000', clean_code)),
            "has_score_math": bool(re.search(r'0\.6|0\.4', clean_code)),
            "has_sqft_filter": bool(re.search(r'50000', clean_code)),
            "has_groupby": bool(re.search(r'groupby', clean_code))
        }
        
        # Check for errors in executed cells
        has_errors = False
        for cell in code_cells:
            if cell.get('execution_count') is not None:
                for out in cell.get('outputs', []):
                    if out.get('output_type') == 'error':
                        has_errors = True
                        break
        analysis["has_errors"] = has_errors
        result["notebook"]["analysis"] = analysis
        
    except Exception as e:
        result["notebook"]["analysis"] = {"error": str(e)}

# 2. Analyze Top Candidates CSV
top_csv_path = "/home/ga/urbansim_projects/output/top_conversion_candidates.csv"
if os.path.exists(top_csv_path):
    result["top_csv"]["exists"] = True
    result["top_csv"]["created"] = os.path.getmtime(top_csv_path) > task_start
    try:
        import pandas as pd
        df_top = pd.read_csv(top_csv_path)
        result["top_csv"]["rows"] = len(df_top)
        result["top_csv"]["columns"] = list(df_top.columns)
    except Exception as e:
        result["top_csv"]["error"] = str(e)

# 3. Analyze Zone Capacity CSV
zone_csv_path = "/home/ga/urbansim_projects/output/zone_conversion_capacity.csv"
if os.path.exists(zone_csv_path):
    result["zone_csv"]["exists"] = True
    result["zone_csv"]["created"] = os.path.getmtime(zone_csv_path) > task_start
    try:
        import pandas as pd
        df_zone = pd.read_csv(zone_csv_path)
        result["zone_csv"]["rows"] = len(df_zone)
        result["zone_csv"]["columns"] = list(df_zone.columns)
    except Exception as e:
        result["zone_csv"]["error"] = str(e)

# 4. Analyze Plot
plot_path = "/home/ga/urbansim_projects/output/conversion_scatter.png"
if os.path.exists(plot_path):
    result["plot"]["exists"] = True
    result["plot"]["created"] = os.path.getmtime(plot_path) > task_start
    result["plot"]["size_kb"] = os.path.getsize(plot_path) / 1024

# Write JSON safely
with open('/tmp/_task_result_tmp.json', 'w') as f:
    json.dump(result, f, indent=2, default=str)

PYEOF

# Move to final location ensuring proper permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/_task_result_tmp.json /tmp/task_result.json 2>/dev/null || sudo cp /tmp/_task_result_tmp.json /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/_task_result_tmp.json

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="