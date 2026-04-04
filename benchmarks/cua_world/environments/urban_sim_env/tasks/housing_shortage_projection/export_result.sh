#!/bin/bash
echo "=== Exporting housing_shortage_projection result ==="

source /workspace/scripts/task_utils.sh
activate_venv

take_screenshot /tmp/housing_shortage_end.png

/opt/urbansim_env/bin/python3 << 'PYEOF'
import json, os, csv

task_start = int(open('/tmp/housing_shortage_start_ts').read().strip()) if os.path.exists('/tmp/housing_shortage_start_ts') else 0
gt = {}
if os.path.exists('/tmp/housing_shortage_gt.json'):
    with open('/tmp/housing_shortage_gt.json') as f:
        gt = json.load(f)

result = {
    "task_start": task_start,
    "gt": gt,
    "csv_exists": False,
    "csv_is_new": False,
    "csv_rows": 0,
    "csv_columns": [],
    "has_year_col": False,
    "has_households_col": False,
    "has_new_units_col": False,
    "has_deficit_col": False,
    "years_found": [],
    "deficit_values": [],
    "new_units_values": [],
    "new_households_values": [],
    "all_deficits_nonzero": False,
    "deficits_vary": False,
    "chart_exists": False,
    "chart_is_new": False,
    "chart_size_kb": 0,
    "notebook_has_orca": False,
    "notebook_has_orca_run": False,
    "notebook_has_orca_step": False,
    "notebook_executed_cells": 0
}

csv_path = "/home/ga/urbansim_projects/output/housing_shortage.csv"
if os.path.exists(csv_path):
    result["csv_exists"] = True
    result["csv_is_new"] = int(os.path.getmtime(csv_path)) > task_start
    try:
        with open(csv_path) as f:
            reader = csv.DictReader(f)
            rows = list(reader)
            cols = [c.lower().strip() for c in (reader.fieldnames or [])]

        result["csv_rows"] = len(rows)
        result["csv_columns"] = cols
        result["has_year_col"] = any(c == 'year' or 'year' == c for c in cols)
        result["has_households_col"] = any('household' in c for c in cols)
        result["has_new_units_col"] = any('unit' in c for c in cols)
        result["has_deficit_col"] = any('deficit' in c or 'shortage' in c or 'gap' in c for c in cols)

        # Extract year values
        year_col = next((c for c in (reader.fieldnames or []) if c.lower().strip() == 'year'), None)
        if year_col and rows:
            try:
                result["years_found"] = [int(float(r[year_col])) for r in rows if r.get(year_col, '').strip()]
            except (ValueError, TypeError):
                pass

        # Extract deficit values
        deficit_col = next((c for c in (reader.fieldnames or [])
                            if any(kw in c.lower() for kw in ['deficit', 'shortage', 'annual_def', 'gap'])), None)
        if deficit_col and rows:
            try:
                vals = [float(r[deficit_col]) for r in rows if r.get(deficit_col, '').strip()]
                result["deficit_values"] = vals
                result["all_deficits_nonzero"] = all(v != 0 for v in vals)
                result["deficits_vary"] = max(vals) != min(vals) if vals else False
            except (ValueError, TypeError):
                pass

        # Extract new_units values
        units_col = next((c for c in (reader.fieldnames or [])
                          if 'new_unit' in c.lower() or 'unit' in c.lower()), None)
        if units_col and rows:
            try:
                result["new_units_values"] = [float(r[units_col]) for r in rows if r.get(units_col, '').strip()]
            except (ValueError, TypeError):
                pass

        # Extract new_households values
        hh_col = next((c for c in (reader.fieldnames or [])
                       if 'new_household' in c.lower()), None)
        if hh_col and rows:
            try:
                result["new_households_values"] = [float(r[hh_col]) for r in rows if r.get(hh_col, '').strip()]
            except (ValueError, TypeError):
                pass

    except Exception as e:
        result["csv_error"] = str(e)

chart_path = "/home/ga/urbansim_projects/output/shortage_trend.png"
if os.path.exists(chart_path):
    result["chart_exists"] = True
    result["chart_is_new"] = int(os.path.getmtime(chart_path)) > task_start
    result["chart_size_kb"] = os.path.getsize(chart_path) / 1024

# Check notebook for orca usage
import re
nb_path = "/home/ga/urbansim_projects/notebooks/housing_shortage.ipynb"
if os.path.exists(nb_path):
    try:
        with open(nb_path) as f:
            nb = json.load(f)
        code_cells = [c for c in nb.get('cells', []) if c.get('cell_type') == 'code']
        all_code = ''
        for cell in code_cells:
            src = cell.get('source', '')
            all_code += (''.join(src) if isinstance(src, list) else src) + '\n'
        result["notebook_has_orca"] = bool(re.search(r'import orca|from orca', all_code))
        result["notebook_has_orca_run"] = bool(re.search(r'orca\.run\s*\(', all_code))
        result["notebook_has_orca_step"] = bool(re.search(r'@orca\.step|orca\.step', all_code))
        result["notebook_executed_cells"] = sum(
            1 for c in code_cells if c.get('execution_count') is not None
        )
    except Exception:
        pass

with open('/tmp/housing_shortage_result.json', 'w') as f:
    json.dump(result, f, indent=2, default=str)
print("Result written to /tmp/housing_shortage_result.json")
PYEOF

chmod 666 /tmp/housing_shortage_result.json 2>/dev/null || true
cat /tmp/housing_shortage_result.json
echo "=== Export complete ==="
