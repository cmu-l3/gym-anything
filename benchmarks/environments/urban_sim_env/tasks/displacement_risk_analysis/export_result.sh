#!/bin/bash
echo "=== Exporting displacement_risk_analysis result ==="

source /workspace/scripts/task_utils.sh
activate_venv

take_screenshot /tmp/displacement_risk_end.png

TASK_START=$(cat /tmp/displacement_risk_start_ts 2>/dev/null || echo "0")

/opt/urbansim_env/bin/python3 << 'PYEOF'
import json, os, csv

task_start = int(open('/tmp/displacement_risk_start_ts').read().strip()) if os.path.exists('/tmp/displacement_risk_start_ts') else 0
gt = {}
if os.path.exists('/tmp/displacement_risk_gt.json'):
    with open('/tmp/displacement_risk_gt.json') as f:
        gt = json.load(f)

result = {
    "task_start": task_start,
    "csv_exists": False,
    "csv_is_new": False,
    "csv_row_count": 0,
    "csv_columns": [],
    "has_zone_id": False,
    "has_dri_score": False,
    "has_vulnerability_score": False,
    "has_precarity_score": False,
    "has_pressure_score": False,
    "has_low_income_households": False,
    "has_mean_price_per_sqft": False,
    "dri_score_min": None,
    "dri_score_max": None,
    "dri_score_std": None,
    "unique_zone_ids": 0,
    "all_dri_in_0_1": False,
    "chart_exists": False,
    "chart_is_new": False,
    "chart_size_kb": 0,
    "notebook_executed_cells": 0,
    "gt": gt
}

csv_path = "/home/ga/urbansim_projects/output/displacement_risk.csv"
if os.path.exists(csv_path):
    result["csv_exists"] = True
    result["csv_is_new"] = int(os.path.getmtime(csv_path)) > task_start
    try:
        with open(csv_path, 'r') as f:
            reader = csv.DictReader(f)
            rows = list(reader)
            cols = [c.lower().strip() for c in (reader.fieldnames or [])]
        result["csv_row_count"] = len(rows)
        result["csv_columns"] = cols
        result["has_zone_id"] = any('zone_id' in c or c == 'zone_id' for c in cols)
        result["has_dri_score"] = any('dri' in c for c in cols)
        result["has_vulnerability_score"] = any('vulner' in c for c in cols)
        result["has_precarity_score"] = any('precar' in c for c in cols)
        result["has_pressure_score"] = any('pressure' in c for c in cols)
        result["has_low_income_households"] = any('low_income' in c or 'lowincome' in c for c in cols)
        result["has_mean_price_per_sqft"] = any('price' in c and 'sqft' in c for c in cols)

        # Count unique zone_ids
        zone_col = next((c for c in (reader.fieldnames or []) if 'zone_id' in c.lower()), None)
        if zone_col and rows:
            result["unique_zone_ids"] = len(set(r.get(zone_col, '') for r in rows if r.get(zone_col, '').strip()))

        # Validate dri_score values
        dri_col = next((c for c in (reader.fieldnames or []) if 'dri' in c.lower()), None)
        if dri_col and rows:
            try:
                vals = [float(r[dri_col]) for r in rows if r.get(dri_col, '').strip()]
                if vals:
                    result["dri_score_min"] = min(vals)
                    result["dri_score_max"] = max(vals)
                    import statistics
                    result["dri_score_std"] = statistics.stdev(vals) if len(vals) > 1 else 0.0
                    result["all_dri_in_0_1"] = all(0.0 <= v <= 1.0 for v in vals)
            except (ValueError, KeyError):
                pass
    except Exception as e:
        result["csv_error"] = str(e)

chart_path = "/home/ga/urbansim_projects/output/displacement_risk_chart.png"
if os.path.exists(chart_path):
    result["chart_exists"] = True
    result["chart_is_new"] = int(os.path.getmtime(chart_path)) > task_start
    result["chart_size_kb"] = os.path.getsize(chart_path) / 1024

# Check notebook execution
nb_path = "/home/ga/urbansim_projects/notebooks/displacement_risk.ipynb"
if os.path.exists(nb_path):
    try:
        with open(nb_path) as f:
            nb = json.load(f)
        code_cells = [c for c in nb.get('cells', []) if c.get('cell_type') == 'code']
        result["notebook_executed_cells"] = sum(
            1 for c in code_cells if c.get('execution_count') is not None
        )
    except Exception:
        pass

with open('/tmp/displacement_risk_result.json', 'w') as f:
    json.dump(result, f, indent=2, default=str)
print("Result written to /tmp/displacement_risk_result.json")
PYEOF

chmod 666 /tmp/displacement_risk_result.json 2>/dev/null || true
cat /tmp/displacement_risk_result.json
echo "=== Export complete ==="
