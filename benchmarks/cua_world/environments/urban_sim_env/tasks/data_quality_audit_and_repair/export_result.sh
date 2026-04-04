#!/bin/bash
echo "=== Exporting data_quality_audit_and_repair result ==="

source /workspace/scripts/task_utils.sh
activate_venv

take_screenshot /tmp/data_quality_end.png

/opt/urbansim_env/bin/python3 << 'PYEOF'
import json, os, csv

task_start = int(open('/tmp/data_quality_start_ts').read().strip()) if os.path.exists('/tmp/data_quality_start_ts') else 0
gt = {}
if os.path.exists('/tmp/data_quality_gt.json'):
    with open('/tmp/data_quality_gt.json') as f:
        gt = json.load(f)

result = {
    "task_start": task_start,
    "gt": gt,
    "report_csv_exists": False,
    "report_csv_is_new": False,
    "report_csv_rows": 0,
    "report_has_issue_type": False,
    "report_has_records_affected": False,
    "report_has_repair_method": False,
    "issue_types_found": [],
    "records_affected_values": [],
    "issue_types_count": 0,
    "repaired_csv_exists": False,
    "repaired_csv_is_new": False,
    "repaired_csv_rows": 0,
    "chart_exists": False,
    "chart_is_new": False,
    "chart_size_kb": 0,
    "notebook_executed_cells": 0,
    # GT-based checks
    "found_physical_issue": False,
    "found_year_issue": False,
    "found_price_issue": False,
    "found_density_issue": False
}

# ── quality_report.csv ──────────────────────────────────────────────────
report_path = "/home/ga/urbansim_projects/output/quality_report.csv"
if os.path.exists(report_path):
    result["report_csv_exists"] = True
    result["report_csv_is_new"] = int(os.path.getmtime(report_path)) > task_start
    try:
        with open(report_path) as f:
            reader = csv.DictReader(f)
            rows = list(reader)
            cols = [c.lower().strip() for c in (reader.fieldnames or [])]
        result["report_csv_rows"] = len(rows)
        result["report_has_issue_type"] = any('issue' in c or 'type' in c for c in cols)
        result["report_has_records_affected"] = any('affect' in c or 'count' in c or 'records' in c for c in cols)
        result["report_has_repair_method"] = any('repair' in c or 'method' in c or 'fix' in c for c in cols)

        # Extract issue type names and their affected counts
        issue_col = next((c for c in (reader.fieldnames or []) if 'issue' in c.lower() or 'type' in c.lower()), None)
        count_col = next((c for c in (reader.fieldnames or []) if 'affect' in c.lower() or 'count' in c.lower() or 'records' in c.lower()), None)

        if issue_col and rows:
            issue_types = [r.get(issue_col, '').strip().lower() for r in rows if r.get(issue_col, '').strip()]
            result["issue_types_found"] = issue_types
            result["issue_types_count"] = len(set(issue_types))

            # Check which GT categories were found (flexible keyword matching)
            combined = ' '.join(issue_types)
            result["found_physical_issue"] = any(kw in combined for kw in
                ['physical', 'sqft', 'footprint', 'floor_area', 'stories', 'height', 'building_sqft', 'impossible_height'])
            result["found_year_issue"] = any(kw in combined for kw in
                ['year', 'temporal', 'date', 'built', 'future', 'historic'])
            result["found_price_issue"] = any(kw in combined for kw in
                ['price', 'sale', 'value', 'revenue', 'zero_price', 'missing_price'])
            result["found_density_issue"] = any(kw in combined for kw in
                ['density', 'unit', 'residential_unit', 'occupancy', 'capacity', 'high_density'])

        if count_col and rows:
            try:
                vals = [int(float(r[count_col])) for r in rows if r.get(count_col, '').strip()]
                result["records_affected_values"] = vals
            except (ValueError, TypeError):
                pass

    except Exception as e:
        result["report_error"] = str(e)

# ── buildings_repaired.csv ─────────────────────────────────────────────
repaired_path = "/home/ga/urbansim_projects/output/buildings_repaired.csv"
if os.path.exists(repaired_path):
    result["repaired_csv_exists"] = True
    result["repaired_csv_is_new"] = int(os.path.getmtime(repaired_path)) > task_start
    try:
        # Just count lines (avoid loading huge file)
        with open(repaired_path) as f:
            result["repaired_csv_rows"] = sum(1 for _ in f) - 1  # subtract header
    except Exception as e:
        result["repaired_error"] = str(e)

# ── chart ──────────────────────────────────────────────────────────────
chart_path = "/home/ga/urbansim_projects/output/quality_audit_chart.png"
if os.path.exists(chart_path):
    result["chart_exists"] = True
    result["chart_is_new"] = int(os.path.getmtime(chart_path)) > task_start
    result["chart_size_kb"] = os.path.getsize(chart_path) / 1024

# ── notebook ────────────────────────────────────────────────────────────
nb_path = "/home/ga/urbansim_projects/notebooks/data_quality_audit.ipynb"
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

with open('/tmp/data_quality_result.json', 'w') as f:
    json.dump(result, f, indent=2, default=str)
print("Result written to /tmp/data_quality_result.json")
PYEOF

chmod 666 /tmp/data_quality_result.json 2>/dev/null || true
cat /tmp/data_quality_result.json
echo "=== Export complete ==="
