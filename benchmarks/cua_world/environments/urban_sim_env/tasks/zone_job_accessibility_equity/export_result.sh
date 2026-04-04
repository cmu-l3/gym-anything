#!/bin/bash
echo "=== Exporting zone_job_accessibility_equity result ==="

source /workspace/scripts/task_utils.sh
activate_venv

take_screenshot /tmp/zone_equity_end.png

/opt/urbansim_env/bin/python3 << 'PYEOF'
import json, os, csv, statistics

task_start = int(open('/tmp/zone_equity_start_ts').read().strip()) if os.path.exists('/tmp/zone_equity_start_ts') else 0
gt = {}
if os.path.exists('/tmp/zone_equity_gt.json'):
    with open('/tmp/zone_equity_gt.json') as f:
        gt = json.load(f)

result = {
    "task_start": task_start,
    "gt": gt,
    "csv_exists": False,
    "csv_is_new": False,
    "csv_rows": 0,
    "csv_columns": [],
    "has_zone_id": False,
    "has_total_jobs": False,
    "has_total_households": False,
    "has_low_income_share": False,
    "has_equity_gap_score": False,
    "has_jobs_per_household": False,
    "unique_zones": 0,
    "equity_score_min": None,
    "equity_score_max": None,
    "equity_score_std": None,
    "all_scores_in_0_1": False,
    "scores_vary": False,
    "low_income_share_in_range": False,
    "jobs_per_hh_nonnegative": False,
    "chart_exists": False,
    "chart_is_new": False,
    "chart_size_kb": 0,
    "notebook_executed_cells": 0
}

csv_path = "/home/ga/urbansim_projects/output/zone_accessibility.csv"
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
        result["has_zone_id"] = any('zone_id' in c or c == 'zone_id' for c in cols)
        result["has_total_jobs"] = any('job' in c for c in cols)
        result["has_total_households"] = any('household' in c for c in cols)
        result["has_low_income_share"] = any('low_income' in c or 'lowincome' in c or 'income_share' in c for c in cols)
        result["has_equity_gap_score"] = any('equity' in c or 'gap' in c for c in cols)
        result["has_jobs_per_household"] = any('jobs_per' in c or 'job_ratio' in c or 'accessibility' in c for c in cols)

        # Count unique zone_ids
        zone_col = next((c for c in (reader.fieldnames or []) if 'zone_id' in c.lower()), None)
        if zone_col and rows:
            result["unique_zones"] = len(set(r.get(zone_col, '') for r in rows if r.get(zone_col, '').strip()))

        # Validate equity_gap_score
        eq_col = next((c for c in (reader.fieldnames or []) if 'equity' in c.lower() or 'gap' in c.lower()), None)
        if eq_col and rows:
            try:
                vals = [float(r[eq_col]) for r in rows if r.get(eq_col, '').strip()]
                if vals:
                    result["equity_score_min"] = min(vals)
                    result["equity_score_max"] = max(vals)
                    result["equity_score_std"] = statistics.stdev(vals) if len(vals) > 1 else 0.0
                    result["all_scores_in_0_1"] = all(0.0 <= v <= 1.0 for v in vals)
                    result["scores_vary"] = max(vals) != min(vals)
            except (ValueError, TypeError):
                pass

        # Validate low_income_share in [0,1]
        li_col = next((c for c in (reader.fieldnames or [])
                       if 'low_income_share' in c.lower() or 'income_share' in c.lower()), None)
        if li_col and rows:
            try:
                li_vals = [float(r[li_col]) for r in rows if r.get(li_col, '').strip()]
                result["low_income_share_in_range"] = all(0.0 <= v <= 1.0 for v in li_vals)
            except (ValueError, TypeError):
                pass

        # Validate jobs_per_household >= 0
        jph_col = next((c for c in (reader.fieldnames or [])
                        if 'jobs_per' in c.lower() or 'accessibility' in c.lower()), None)
        if jph_col and rows:
            try:
                jph_vals = [float(r[jph_col]) for r in rows if r.get(jph_col, '').strip()]
                result["jobs_per_hh_nonnegative"] = all(v >= 0 for v in jph_vals)
            except (ValueError, TypeError):
                pass

    except Exception as e:
        result["csv_error"] = str(e)

chart_path = "/home/ga/urbansim_projects/output/equity_gap_chart.png"
if os.path.exists(chart_path):
    result["chart_exists"] = True
    result["chart_is_new"] = int(os.path.getmtime(chart_path)) > task_start
    result["chart_size_kb"] = os.path.getsize(chart_path) / 1024

nb_path = "/home/ga/urbansim_projects/notebooks/job_accessibility_equity.ipynb"
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

with open('/tmp/zone_equity_result.json', 'w') as f:
    json.dump(result, f, indent=2, default=str)
print("Result written to /tmp/zone_equity_result.json")
PYEOF

chmod 666 /tmp/zone_equity_result.json 2>/dev/null || true
cat /tmp/zone_equity_result.json
echo "=== Export complete ==="
