#!/bin/bash
echo "=== Exporting residential space efficiency result ==="

source /workspace/scripts/task_utils.sh
activate_venv

take_screenshot /tmp/task_end.png
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

# Run programmatic analysis on outputs inside the container
python << 'PYEOF'
import json, re, os, csv

task_start = int(open('/home/ga/.task_start_time').read().strip()) if os.path.exists('/home/ga/.task_start_time') else 0

result = {
    "notebook_exists": False,
    "notebook_modified": False,
    "notebook_analysis": {},
    "csv_exists": False,
    "csv_rows": 0,
    "csv_columns": [],
    "csv_math_correct": False,
    "scatter_exists": False,
    "scatter_size": 0,
    "bar_exists": False,
    "bar_size": 0,
    "task_start_time": task_start
}

nb_path = "/home/ga/urbansim_projects/notebooks/space_efficiency_analysis.ipynb"
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
            "has_groupby": bool(re.search(r'groupby', all_code)),
            "has_merge": bool(re.search(r'merge|join', all_code)),
            "has_residential_filter": bool(re.search(r'residential_units', all_code)),
            "has_division": bool(re.search(r'/', all_code)),
            "has_savefig": bool(re.search(r'savefig', all_code)),
            "has_to_csv": bool(re.search(r'to_csv', all_code))
        }
    except Exception as e:
        result["notebook_analysis"] = {"error": str(e)}

csv_path = "/home/ga/urbansim_projects/output/zone_space_efficiency.csv"
if os.path.exists(csv_path):
    result["csv_exists"] = True
    try:
        with open(csv_path, 'r') as f:
            reader = csv.reader(f)
            header = next(reader)
            result["csv_columns"] = [c.lower().strip() for c in header]
            rows = list(reader)
            result["csv_rows"] = len(rows)

            math_correct = True
            checked_rows = 0
            
            # Use flexible column matching to handle slight variations in names
            sqft_col = next((c for c in result["csv_columns"] if 'sqft' in c and 'total' in c), None)
            pers_col = next((c for c in result["csv_columns"] if 'person' in c and 'total' in c), None)
            cap_col = next((c for c in result["csv_columns"] if 'capita' in c or 'per' in c), None)

            if sqft_col and pers_col and cap_col:
                sqft_idx = result["csv_columns"].index(sqft_col)
                pers_idx = result["csv_columns"].index(pers_col)
                cap_idx = result["csv_columns"].index(cap_col)

                for row in rows:
                    if len(row) > max(sqft_idx, pers_idx, cap_idx):
                        try:
                            sqft = float(row[sqft_idx])
                            pers = float(row[pers_idx])
                            if row[cap_idx].strip() in ('', 'nan', 'NaN', 'inf'):
                                continue
                            cap = float(row[cap_idx])
                            if pers > 0:
                                expected = sqft / pers
                                # Validate metric falls within reasonable fp tolerance
                                if abs(expected - cap) > 0.05 * expected and abs(expected - cap) > 1.0:
                                    math_correct = False
                                    break
                                checked_rows += 1
                        except ValueError:
                            pass
                
                if checked_rows > 10 and math_correct:
                    result["csv_math_correct"] = True
    except Exception as e:
        pass

plot1_path = "/home/ga/urbansim_projects/output/efficiency_scatter.png"
if os.path.exists(plot1_path):
    result["scatter_exists"] = True
    result["scatter_size"] = os.path.getsize(plot1_path)

plot2_path = "/home/ga/urbansim_projects/output/least_efficient_zones.png"
if os.path.exists(plot2_path):
    result["bar_exists"] = True
    result["bar_size"] = os.path.getsize(plot2_path)

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